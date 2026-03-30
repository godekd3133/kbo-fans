from __future__ import annotations

import re
from collections.abc import Iterable
from typing import Any, Optional, Tuple

from kbo_fans_backend.crawlers.base import BaseCrawler
from kbo_fans_backend.utils.html import extract_game_id, strip_tags


class ScheduleCrawler(BaseCrawler):
    """Fetches monthly schedule data from KBO schedule endpoints."""

    def get_month_schedule(self, month: str) -> list[dict[str, Any]]:
        season_id, game_month = month.split("-")
        response = self.session.post(
            f"{self.base_url}/ws/Schedule.asmx/GetScheduleList",
            data={
                "leId": 1,
                "srIdList": "0,9,6",
                "seasonId": season_id,
                "gameMonth": game_month,
                "teamId": "",
            },
            headers={
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                "X-Requested-With": "XMLHttpRequest",
            },
            timeout=self.timeout,
        )
        response.raise_for_status()
        payload = response.json()

        rows: list[dict[str, Any]] = []
        current_date: Optional[str] = None
        for row in payload.get("rows", []):
            parsed_row = self._parse_schedule_row(row["row"], current_date, season_id)
            current_date = parsed_row["date"]
            rows.append(parsed_row)
        return rows

    def get_games_by_date(self, date: str) -> list[dict[str, Any]]:
        month = date[:7]
        return [row for row in self.get_month_schedule(month) if row["date"] == date]

    def _parse_schedule_row(
        self,
        row: Iterable[dict[str, Any]],
        current_date: Optional[str],
        season_id: str,
    ) -> dict[str, Any]:
        cells = list(row)
        offset = 0
        date_text = strip_tags(cells[0]["Text"])
        if re.match(r"\d{2}\.\d{2}\(.+\)", date_text):
            current_date = self._normalize_date(date_text, season_id)
            offset = 1

        time_text = strip_tags(cells[offset]["Text"])
        play_html = cells[offset + 1]["Text"]
        action_html = cells[offset + 2]["Text"]
        status = self._derive_status(action_html)
        away_name, home_name = self._parse_play_names(play_html)
        away_id, home_id = self._derive_team_ids_from_game_id(extract_game_id(action_html))

        return {
            "date": current_date,
            "time": time_text,
            "gameId": extract_game_id(action_html),
            "awayId": away_id,
            "awayName": away_name,
            "homeId": home_id,
            "homeName": home_name,
            "stadium": strip_tags(cells[offset + 6]["Text"]),
            "status": status,
        }

    @staticmethod
    def _normalize_date(value: str, season_id: str) -> str:
        month_day = value.split("(")[0]
        month, day = month_day.split(".")
        return f"{season_id}-{month}-{day}"

    @staticmethod
    def _parse_play_names(play_html: str) -> tuple[str, str]:
        names = re.findall(r"<span>([^<]+)</span>", play_html)
        if len(names) >= 2:
            return names[0], names[-1]
        text = strip_tags(play_html)
        parts = [part for part in text.split("vs") if part]
        if len(parts) == 2:
            return parts[0].strip(), parts[1].strip()
        return "", ""

    @staticmethod
    def _derive_team_ids_from_game_id(game_id: Optional[str]) -> Tuple[Optional[str], Optional[str]]:
        if not game_id or len(game_id) < 13:
            return None, None
        return game_id[8:10], game_id[10:12]

    @staticmethod
    def _derive_status(action_html: str) -> str:
        if "section=REVIEW" in action_html:
            return "FINAL"
        if "section=PREVIEW" in action_html:
            return "SCHEDULED"
        if "문자중계" in action_html or "중계" in action_html:
            return "LIVE"
        return "UNKNOWN"
