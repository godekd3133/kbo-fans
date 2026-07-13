from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Optional

from kbo_fans_backend.utils.kbo_time import kbo_timezone


class TicketingService:
    _VENDOR_BY_TEAM = {
        "LG": {
            "vendorKey": "interpark",
            "vendorName": "인터파크 티켓",
            "vendorUrl": "https://tickets.interpark.com",
        },
        "OB": {
            "vendorKey": "interpark",
            "vendorName": "인터파크 티켓",
            "vendorUrl": "https://tickets.interpark.com",
        },
        "SK": {
            "vendorKey": "interpark",
            "vendorName": "인터파크 티켓",
            "vendorUrl": "https://tickets.interpark.com",
        },
        "KT": {
            "vendorKey": "interpark",
            "vendorName": "인터파크 티켓",
            "vendorUrl": "https://tickets.interpark.com",
        },
        "HT": {
            "vendorKey": "ticketlink",
            "vendorName": "티켓링크",
            "vendorUrl": "https://www.ticketlink.co.kr",
        },
        "HH": {
            "vendorKey": "ticketlink",
            "vendorName": "티켓링크",
            "vendorUrl": "https://www.ticketlink.co.kr",
        },
        "NC": {
            "vendorKey": "ticketlink",
            "vendorName": "티켓링크",
            "vendorUrl": "https://www.ticketlink.co.kr",
        },
        "SS": {
            "vendorKey": "ticketlink",
            "vendorName": "티켓링크",
            "vendorUrl": "https://www.ticketlink.co.kr",
        },
        "LT": {
            "vendorKey": "ticketlink",
            "vendorName": "티켓링크",
            "vendorUrl": "https://www.ticketlink.co.kr",
        },
        "WO": {
            "vendorKey": "ticketlink",
            "vendorName": "티켓링크",
            "vendorUrl": "https://www.ticketlink.co.kr",
        },
    }

    def build_ticket_info(
        self,
        *,
        home_team_id: Optional[str],
        game_id: Optional[str],
        start_time: Optional[str],
        status: Optional[str] = None,
    ) -> Optional[dict[str, Any]]:
        if not home_team_id or not game_id or not start_time:
            return None

        if status and status.upper() in {"FINAL", "CANCELLED", "SUSPENDED"}:
            return None

        vendor = self._VENDOR_BY_TEAM.get(home_team_id)
        if vendor is None:
            return None

        open_at = self._infer_open_at(game_id=game_id, start_time=start_time)
        return {
            **vendor,
            "openAt": open_at.isoformat() if open_at is not None else None,
            "source": "inferred",
            "note": "홈팀 기본 예매 정책 기준 추정값",
        }

    def _infer_open_at(self, *, game_id: str, start_time: str) -> Optional[datetime]:
        if len(game_id) < 8:
            return None

        time_parts = start_time.split(":")
        if len(time_parts) != 2:
            return None

        try:
            year = int(game_id[:4])
            month = int(game_id[4:6])
            day = int(game_id[6:8])
            hour = int(time_parts[0])
            minute = int(time_parts[1])
            game_start = datetime(
                year,
                month,
                day,
                hour,
                minute,
                tzinfo=kbo_timezone(),
            )
        except ValueError:
            return None

        open_at = game_start - timedelta(days=7)
        return open_at.replace(hour=11, minute=0, second=0, microsecond=0)
