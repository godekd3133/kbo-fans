import asyncio
import logging
import os
import threading
import time
from datetime import datetime, timezone
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any, Dict, List, Optional, Set

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from kbo_fans_backend.api.router import api_router
from kbo_fans_backend.core.config import get_settings
from kbo_fans_backend.utils.resilience import UpstreamBusyError, UpstreamDeadlineExceeded

logger = logging.getLogger(__name__)
_SLOW_REQUEST_WARNING_MS = 800
_RETRY_AFTER_SECONDS = "1"


def _error_response(
    *,
    status_code: int,
    code: str,
    message: str,
    headers: Optional[Dict[str, str]] = None,
) -> JSONResponse:
    response_headers = {"Cache-Control": "no-store"}
    if headers is not None:
        response_headers.update(headers)
    return JSONResponse(
        status_code=status_code,
        headers=response_headers,
        content={
            "success": False,
            "data": None,
            "error": {"code": code, "message": message},
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    )


class DataRequestGuardMiddleware:
    """Bounds screen-data GET latency while isolating abandoned sync work."""

    _EXCLUDED_PATH_SUFFIXES = ("/health",)
    _EXCLUDED_PATH_PREFIXES = ("/metrics", "/push")

    def __init__(
        self,
        app: ASGIApp,
        *,
        api_prefix: str,
        timeout_seconds: float,
        max_concurrency: int,
        queue_timeout_seconds: float,
    ) -> None:
        if timeout_seconds <= 0:
            raise ValueError("DATA_REQUEST_TIMEOUT_SECONDS must be positive")
        if max_concurrency <= 0:
            raise ValueError("DATA_REQUEST_MAX_CONCURRENCY must be positive")
        if queue_timeout_seconds < 0:
            raise ValueError("DATA_REQUEST_QUEUE_TIMEOUT_SECONDS must not be negative")
        self.app = app
        self._api_prefix = "/" + api_prefix.strip("/")
        self._timeout_seconds = timeout_seconds
        self._queue_timeout_seconds = queue_timeout_seconds
        self._slots = threading.BoundedSemaphore(max_concurrency)
        self._in_flight_tasks: Set["asyncio.Task[None]"] = set()
        self._in_flight_tasks_lock = threading.Lock()

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if not self._is_screen_data_get(scope):
            await self.app(scope, receive, send)
            return

        started_at = time.monotonic()
        request_deadline = started_at + self._timeout_seconds
        acquired = await self._acquire_slot(min(self._queue_timeout_seconds, self._timeout_seconds))
        if not acquired:
            await _error_response(
                status_code=503,
                code="UPSTREAM_BUSY",
                message="데이터 요청이 몰리고 있습니다. 잠시 후 다시 시도해주세요.",
                headers={"Retry-After": _RETRY_AFTER_SECONDS},
            )(scope, receive, send)
            return

        remaining = request_deadline - time.monotonic()
        if remaining <= 0:
            self._slots.release()
            await self._deadline_response(scope, receive, send)
            return

        captured_messages: List[Message] = []
        state: Dict[str, Any] = {"timed_out": False}

        async def capture_send(message: Message) -> None:
            captured_messages.append(dict(message))

        try:
            downstream = asyncio.create_task(self.app(scope, receive, capture_send))
        except BaseException:
            self._slots.release()
            raise
        with self._in_flight_tasks_lock:
            self._in_flight_tasks.add(downstream)

        def release_slot(completed: "asyncio.Task[None]") -> None:
            with self._in_flight_tasks_lock:
                self._in_flight_tasks.discard(completed)
            self._slots.release()
            try:
                error = completed.exception()
            except asyncio.CancelledError:
                return
            if state["timed_out"] and error is not None:
                logger.warning(
                    "Detached data request failed after deadline: %s %s [%s]",
                    scope.get("method"),
                    scope.get("path"),
                    type(error).__name__,
                )

        downstream.add_done_callback(release_slot)
        done, _ = await asyncio.wait({downstream}, timeout=remaining)
        if downstream not in done:
            state["timed_out"] = True
            logger.warning(
                "Data request deadline exceeded after %.0fms %s %s",
                (time.monotonic() - started_at) * 1000,
                scope.get("method"),
                scope.get("path"),
            )
            await self._deadline_response(scope, receive, send)
            return

        await downstream
        if not captured_messages:
            raise RuntimeError("Screen data request completed without an ASGI response")
        for message in captured_messages:
            await send(message)

    async def _acquire_slot(self, timeout_seconds: float) -> bool:
        deadline = time.monotonic() + timeout_seconds
        while True:
            if self._slots.acquire(blocking=False):
                return True
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return False
            await asyncio.sleep(min(0.01, remaining))

    def _is_screen_data_get(self, scope: Scope) -> bool:
        if scope["type"] != "http" or scope.get("method") != "GET":
            return False
        path = str(scope.get("path", ""))
        if path == self._api_prefix:
            return False
        prefix = self._api_prefix + "/"
        if not path.startswith(prefix):
            return False
        relative_path = path[len(self._api_prefix) :]
        if relative_path in self._EXCLUDED_PATH_SUFFIXES:
            return False
        return not any(
            relative_path == excluded or relative_path.startswith(excluded + "/")
            for excluded in self._EXCLUDED_PATH_PREFIXES
        )

    @staticmethod
    async def _deadline_response(scope: Scope, receive: Receive, send: Send) -> None:
        await _error_response(
            status_code=504,
            code="UPSTREAM_DEADLINE_EXCEEDED",
            message="데이터 응답 시간이 초과되었습니다. 잠시 후 다시 시도해주세요.",
        )(scope, receive, send)


def _configure_logging() -> None:
    log_dir = Path(os.getenv("LOG_DIR", Path(__file__).resolve().parents[2] / "logs"))
    log_dir.mkdir(parents=True, exist_ok=True)

    app_logger = logging.getLogger("kbo_fans_backend")
    app_logger.setLevel(logging.INFO)

    if not app_logger.handlers:
        file_handler = RotatingFileHandler(
            log_dir / "backend.log",
            maxBytes=2_000_000,
            backupCount=5,
            encoding="utf-8",
        )
        file_handler.setFormatter(
            logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s")
        )
        app_logger.addHandler(file_handler)

    metrics_logger = logging.getLogger("kbo_fans_backend.client_metrics")
    metrics_logger.setLevel(logging.INFO)
    if not metrics_logger.handlers:
        metrics_handler = RotatingFileHandler(
            log_dir / "client_metrics.log",
            maxBytes=2_000_000,
            backupCount=5,
            encoding="utf-8",
        )
        metrics_handler.setFormatter(logging.Formatter("%(message)s"))
        metrics_logger.addHandler(metrics_handler)

    logger.parent = app_logger


_configure_logging()


def create_app() -> FastAPI:
    settings = get_settings()

    app = FastAPI(
        title=settings.app_name,
        debug=settings.debug,
        version="0.1.0",
    )
    app.add_middleware(
        DataRequestGuardMiddleware,
        api_prefix=settings.api_prefix,
        timeout_seconds=settings.data_request_timeout_seconds,
        max_concurrency=settings.data_request_max_concurrency,
        queue_timeout_seconds=settings.data_request_queue_timeout_seconds,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=settings.cors_allow_origin_regex,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(api_router, prefix=settings.api_prefix)

    @app.exception_handler(UpstreamBusyError)
    async def handle_upstream_busy(
        _request: Request,
        error: UpstreamBusyError,
    ) -> JSONResponse:
        logger.warning("Upstream capacity unavailable [%s]", type(error).__name__)
        return _error_response(
            status_code=503,
            code="UPSTREAM_BUSY",
            message="데이터 요청이 몰리고 있습니다. 잠시 후 다시 시도해주세요.",
            headers={"Retry-After": _RETRY_AFTER_SECONDS},
        )

    @app.exception_handler(UpstreamDeadlineExceeded)
    async def handle_upstream_deadline(
        _request: Request,
        error: UpstreamDeadlineExceeded,
    ) -> JSONResponse:
        logger.warning(
            "Upstream deadline exceeded [%s]",
            type(error).__name__,
        )
        return _error_response(
            status_code=504,
            code="UPSTREAM_DEADLINE_EXCEEDED",
            message="데이터 응답 시간이 초과되었습니다. 잠시 후 다시 시도해주세요.",
        )

    @app.middleware("http")
    async def log_slow_requests(request: Request, call_next):
        started_at = time.perf_counter()
        response = await call_next(request)
        elapsed_ms = (time.perf_counter() - started_at) * 1000
        if elapsed_ms >= _SLOW_REQUEST_WARNING_MS:
            logger.warning(
                "Slow request %.0fms %s %s [%s]",
                elapsed_ms,
                request.method,
                request.url.path,
                response.status_code,
            )
        return response

    return app


app = create_app()
