from __future__ import annotations

import logging
import re
import time
from html import unescape
from typing import Any, Dict, Optional

from requests import Session

from kbo_fans_backend.core.config import get_settings

logger = logging.getLogger(__name__)


class BaseCrawler:
    _CIRCUIT_BREAKER_THRESHOLD = 3
    _CIRCUIT_BREAKER_COOLDOWN_SECONDS = 30
    _CIRCUIT_BREAKER_STATE_TTL_SECONDS = 600
    _CIRCUIT_BREAKER_MAX_KEYS = 4096
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
        now = time.monotonic()
        self._prune_breaker_state(now)
        key = breaker_key or url
        state = self._breaker_state.get(key, {"failures": 0, "opened_until": 0.0})
        opened_until = state.get("opened_until", 0.0)
        if opened_until and now < opened_until:
            raise RuntimeError(f"Circuit open for {key}")

        try:
            response = self.session.request(method, url, timeout=self.timeout, **kwargs)
            response.raise_for_status()
            self._breaker_state[key] = {
                "failures": 0,
                "opened_until": 0.0,
                "updated_at": now,
            }
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
                "updated_at": now,
            }
            raise

    @classmethod
    def _prune_breaker_state(cls, now: float) -> None:
        for key, state in list(cls._breaker_state.items()):
            opened_until = float(state.get("opened_until", 0.0) or 0.0)
            updated_at = float(state.get("updated_at", 0.0) or 0.0)
            if (opened_until and now >= opened_until) or (
                not opened_until and now - updated_at >= cls._CIRCUIT_BREAKER_STATE_TTL_SECONDS
            ):
                cls._breaker_state.pop(key, None)

        overflow = len(cls._breaker_state) - cls._CIRCUIT_BREAKER_MAX_KEYS
        if overflow <= 0:
            return
        oldest_keys = sorted(
            cls._breaker_state,
            key=lambda key: float(cls._breaker_state[key].get("updated_at", 0.0) or 0.0),
        )[:overflow]
        for key in oldest_keys:
            cls._breaker_state.pop(key, None)

    def _get_text(self, url: str, *, breaker_key: Optional[str] = None, **kwargs) -> str:
        return self._request("GET", url, breaker_key=breaker_key, **kwargs).text

    def _post_text(self, url: str, *, breaker_key: Optional[str] = None, **kwargs) -> str:
        return self._request("POST", url, breaker_key=breaker_key, **kwargs).text

    def _get_json(self, url: str, *, breaker_key: Optional[str] = None, **kwargs):
        return self._request("GET", url, breaker_key=breaker_key, **kwargs).json()

    def _post_json(self, url: str, *, breaker_key: Optional[str] = None, **kwargs):
        return self._request("POST", url, breaker_key=breaker_key, **kwargs).json()

    def _build_web_form_payload(
        self,
        html: str,
        *,
        overrides: Optional[Dict[str, str]] = None,
        event_target: str = "",
    ) -> Dict[str, str]:
        fields: Dict[str, str] = {}

        for tag in re.findall(r"<input\b[^>]*>", html, re.S | re.I):
            name = self._extract_attr(tag, "name")
            if not name:
                continue
            fields[name] = unescape(self._extract_attr(tag, "value") or "")

        for match in re.finditer(
            r'<select\b[^>]*name="([^"]+)"[^>]*>(.*?)</select>',
            html,
            re.S | re.I,
        ):
            fields[match.group(1)] = unescape(self._selected_option_value(match.group(2)))

        fields.update(overrides or {})
        fields["__EVENTTARGET"] = event_target
        fields["__EVENTARGUMENT"] = ""
        return fields

    @staticmethod
    def _extract_attr(tag: str, attr: str) -> Optional[str]:
        match = re.search(r'%s="([^"]*)"' % re.escape(attr), tag, re.I)
        return match.group(1) if match else None

    @classmethod
    def _selected_option_value(cls, select_body: str) -> str:
        fallback: Optional[str] = None
        for option_tag in re.findall(r"<option\b[^>]*>", select_body, re.S | re.I):
            value = cls._extract_attr(option_tag, "value") or ""
            if fallback is None:
                fallback = value
            if "selected" in option_tag.lower():
                return value
        return fallback or ""
