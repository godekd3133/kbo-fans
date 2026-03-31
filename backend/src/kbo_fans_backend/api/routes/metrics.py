from __future__ import annotations

import json
import logging
from typing import Any, Dict

from fastapi import APIRouter

from kbo_fans_backend.schemas.common import ApiEnvelope

router = APIRouter(prefix="/metrics")
metrics_logger = logging.getLogger("kbo_fans_backend.client_metrics")


@router.post("/client", response_model=ApiEnvelope[dict])
def log_client_metric(payload: Dict[str, Any]) -> ApiEnvelope[dict]:
    metrics_logger.info(json.dumps(payload, ensure_ascii=False))
    return ApiEnvelope.success_response({"accepted": True})
