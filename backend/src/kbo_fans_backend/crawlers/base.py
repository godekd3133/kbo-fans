from __future__ import annotations

import logging
import time
from typing import Any, Dict, Optional

from requests import Session

from kbo_fans_backend.core.config import get_settings

logger = logging.getLogger(__name__)


class BaseCrawler:
    _CIRCUIT_BREAKER_THRESHOLD = 3
    _CIRCUIT_BREAKER_COOLDOWN_SECONDS = 30
    _breaker_state: Dict[str, Dict[str, Any]] = {}

    def __init__(self) -> None:
        settings = get_settings()
        self.base_url = settings.kbo_base_url
        self.timeout = settings.request_timeout_seconds
        self.session = Session()
        self.session.headers.update(
            {
                "User-Agent": (
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
                ),
                "Referer": f"{self.base_url}/",
            }
        )

    def _request(self, method: str, url: str, *, breaker_key: Optional[str] = None, **kwargs):
        key = breaker_key or url
        state = self._breaker_state.get(key, {"failures": 0, "opened_until": 0.0})
        now = time.monotonic()
        opened_until = state.get("opened_until", 0.0)
        if opened_until and now < opened_until:
            raise RuntimeError(f"Circuit open for {key}")

        try:
            response = self.session.request(method, url, timeout=self.timeout, **kwargs)
            response.raise_for_status()
            self._breaker_state[key] = {"failures": 0, "opened_until": 0.0}
            return response
        except Exception:
            failures = int(state.get("failures", 0)) + 1
            opened_until = 0.0
            if failures >= self._CIRCUIT_BREAKER_THRESHOLD:
                opened_until = now + self._CIRCUIT_BREAKER_COOLDOWN_SECONDS
                logger.warning(
                    "KBO circuit opened for %s after %s failures",
                    key,
                    failures,
                )
            self._breaker_state[key] = {
                "failures": failures,
                "opened_until": opened_until,
            }
            raise

    def _get_text(self, url: str, *, breaker_key: Optional[str] = None, **kwargs) -> str:
        return self._request("GET", url, breaker_key=breaker_key, **kwargs).text

    def _post_text(
        self, url: str, *, breaker_key: Optional[str] = None, **kwargs
    ) -> str:
        return self._request("POST", url, breaker_key=breaker_key, **kwargs).text

    def _get_json(self, url: str, *, breaker_key: Optional[str] = None, **kwargs):
        return self._request("GET", url, breaker_key=breaker_key, **kwargs).json()

    def _post_json(self, url: str, *, breaker_key: Optional[str] = None, **kwargs):
        return self._request("POST", url, breaker_key=breaker_key, **kwargs).json()
