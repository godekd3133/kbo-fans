from __future__ import annotations

import re
from datetime import date
from typing import Any, Optional

from kbo_fans_backend.crawlers.standings import StandingsCrawler
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.kbo_time import current_kbo_year
from kbo_fans_backend.utils.singleflight import SingleFlight
from kbo_fans_backend.utils.ttl_cache import TtlCache


class StandingsService:
    _CACHE_TTL_SECONDS = 300

    def __init__(
        self,
        crawler: Optional[StandingsCrawler] = None,
        snapshot_store: Optional[JsonSnapshotStore] = None,
    ) -> None:
        self.crawler = crawler or StandingsCrawler()
        self.snapshot_store = snapshot_store or JsonSnapshotStore()
        self._cache: TtlCache[int, dict[str, Any]] = TtlCache(self._CACHE_TTL_SECONDS)
        self._singleflight: SingleFlight[int] = SingleFlight()

    def get_standings(self, season: int) -> dict[str, Any]:
        cached = self._cache.get(season)
        if cached is not None:
            return cached
        return self._singleflight.call(season, lambda: self._load_standings(season))

    def _load_standings(self, season: int) -> dict[str, Any]:
        cached = self._cache.get(season)
        if cached is not None:
            return cached
        snapshot_record = self.snapshot_store.load("standings_latest", str(season))
        snapshot = snapshot_record.get("payload") if snapshot_record is not None else None
        if self._can_use_snapshot_before_crawling(season, snapshot):
            self._cache.set(season, snapshot)
            return snapshot
        try:
            payload = self.crawler.get_standings(season)
        except Exception:
            stale = self._cache.get_stale(season)
            if self._is_historical_season(season) and stale is not None:
                return stale
            if self._can_use_snapshot_after_failure(season, snapshot):
                return snapshot
            raise

        source_date = self._validate_payload(season, payload)
        self._cache.set(season, payload)
        self.snapshot_store.save("standings_latest", str(season), payload)
        self.snapshot_store.save(
            "standings_daily",
            f"{season}-{source_date.isoformat()}",
            payload,
        )
        return payload

    def _can_use_snapshot_after_failure(
        self,
        season: int,
        snapshot: Optional[dict[str, Any]],
    ) -> bool:
        if snapshot is None:
            return False
        if not self._is_historical_season(season):
            return False
        return self._is_valid_payload(season, snapshot)

    def _can_use_snapshot_before_crawling(
        self,
        season: int,
        snapshot: Optional[dict[str, Any]],
    ) -> bool:
        if snapshot is None:
            return False
        if not self._is_historical_season(season):
            return False
        return self._is_valid_payload(season, snapshot)

    @classmethod
    def _is_valid_payload(cls, season: int, payload: dict[str, Any]) -> bool:
        try:
            cls._validate_payload(season, payload)
        except (TypeError, ValueError):
            return False
        return True

    @classmethod
    def _validate_payload(cls, season: int, payload: dict[str, Any]) -> date:
        if not isinstance(payload, dict):
            raise TypeError("KBO standings payload must be an object")

        payload_season = cls._parse_season(payload.get("season"), "season")
        source_season = cls._parse_season(
            payload.get("sourceSeason", payload_season),
            "sourceSeason",
        )
        if payload_season != season or source_season != season:
            raise ValueError(
                "KBO standings season mismatch: "
                f"requested={season}, payload={payload_season}, source={source_season}"
            )

        standings = payload.get("standings")
        if not isinstance(standings, list) or not standings:
            raise ValueError(f"KBO standings payload is empty for season {season}")

        source_date_value = payload.get("sourceDate")
        updated_at_value = payload.get("updatedAt")
        source_date = cls._parse_source_date(
            source_date_value if source_date_value is not None else updated_at_value
        )
        if source_date.year != season:
            raise ValueError(
                "KBO standings source date mismatch: "
                f"requested={season}, source={source_date.isoformat()}"
            )

        if source_date_value is not None and updated_at_value is not None:
            updated_at_date = cls._parse_source_date(updated_at_value)
            if updated_at_date != source_date:
                raise ValueError(
                    "KBO standings source dates disagree: "
                    f"sourceDate={source_date.isoformat()}, "
                    f"updatedAt={updated_at_date.isoformat()}"
                )
        return source_date

    @staticmethod
    def _parse_season(value: Any, field_name: str) -> int:
        if isinstance(value, bool):
            raise ValueError(f"KBO standings {field_name} is invalid: {value}")
        try:
            return int(value)
        except (TypeError, ValueError) as error:
            raise ValueError(f"KBO standings {field_name} is invalid: {value}") from error

    @staticmethod
    def _parse_source_date(value: Any) -> date:
        if not isinstance(value, str):
            raise ValueError(f"KBO standings source date is invalid: {value}")
        stripped = value.strip()
        patterns = (
            r"^(\d{4})-(\d{1,2})-(\d{1,2})",
            r"^(\d{4})\.(\d{1,2})\.(\d{1,2})",
            r"^(\d{4})년\s*(\d{1,2})월\s*(\d{1,2})일",
            r"^(\d{4})(\d{2})(\d{2})$",
        )
        for pattern in patterns:
            match = re.search(pattern, stripped)
            if match is None:
                continue
            try:
                return date(*(int(part) for part in match.groups()))
            except ValueError as error:
                raise ValueError(f"KBO standings source date is invalid: {value}") from error
        raise ValueError(f"KBO standings source date is invalid: {value}")

    @staticmethod
    def _is_historical_season(season: int) -> bool:
        return season < current_kbo_year()
