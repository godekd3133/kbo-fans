from __future__ import annotations

import json
import logging
import threading
import time
from collections import deque
from typing import Deque, Dict

from fastapi import APIRouter, HTTPException, Request, status

from kbo_fans_backend.schemas.common import ApiEnvelope

router = APIRouter(prefix="/metrics")
metrics_logger = logging.getLogger("kbo_fans_backend.client_metrics")
_MAX_CLIENT_METRIC_BYTES = 16 * 1024
_MAX_CLIENT_METRIC_REQUESTS = 120
_CLIENT_METRIC_RATE_WINDOW_SECONDS = 60.0
_MAX_CLIENT_METRIC_RATE_KEYS = 1024
_client_metric_rate_lock = threading.Lock()
_client_metric_rate_state: Dict[str, Deque[float]] = {}


@router.post("/client", response_model=ApiEnvelope[dict])
async def log_client_metric(request: Request) -> ApiEnvelope[dict]:
    if not _allow_client_metric(request):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="클라이언트 진단 요청이 너무 많습니다",
        )

    content_length = request.headers.get("content-length")
    if content_length is not None:
        try:
            if int(content_length) > _MAX_CLIENT_METRIC_BYTES:
                raise HTTPException(
                    status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                    detail="클라이언트 진단 본문이 너무 큽니다",
                )
        except ValueError:
            pass

    chunks: list[bytes] = []
    body_length = 0
    async for chunk in request.stream():
        body_length += len(chunk)
        if body_length > _MAX_CLIENT_METRIC_BYTES:
            raise HTTPException(
                status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                detail="클라이언트 진단 본문이 너무 큽니다",
            )
        chunks.append(chunk)
    body = b"".join(chunks)
    try:
        payload = json.loads(body)
    except (TypeError, ValueError) as error:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="클라이언트 진단 형식이 올바르지 않습니다",
        ) from error
    if not isinstance(payload, dict):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="클라이언트 진단은 JSON 객체여야 합니다",
        )

    metrics_logger.info(json.dumps(payload, ensure_ascii=False))
    return ApiEnvelope.success_response({"accepted": True})


def _allow_client_metric(request: Request) -> bool:
    source = request.client.host if request.client is not None else "unknown"
    now = time.monotonic()
    cutoff = now - _CLIENT_METRIC_RATE_WINDOW_SECONDS
    with _client_metric_rate_lock:
        attempts = _client_metric_rate_state.get(source)
        if attempts is None:
            if len(_client_metric_rate_state) >= _MAX_CLIENT_METRIC_RATE_KEYS:
                oldest_source = min(
                    _client_metric_rate_state,
                    key=lambda key: _client_metric_rate_state[key][-1],
                )
                _client_metric_rate_state.pop(oldest_source, None)
            attempts = deque()
            _client_metric_rate_state[source] = attempts
        while attempts and attempts[0] <= cutoff:
            attempts.popleft()
        if len(attempts) >= _MAX_CLIENT_METRIC_REQUESTS:
            return False
        attempts.append(now)
        return True
