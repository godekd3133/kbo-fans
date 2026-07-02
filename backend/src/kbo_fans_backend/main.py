import logging
import os
import time
from logging.handlers import RotatingFileHandler
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from kbo_fans_backend.api.router import api_router
from kbo_fans_backend.core.config import get_settings

logger = logging.getLogger(__name__)
_SLOW_REQUEST_WARNING_MS = 800


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
        CORSMiddleware,
        allow_origin_regex=settings.cors_allow_origin_regex,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(api_router, prefix=settings.api_prefix)

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
