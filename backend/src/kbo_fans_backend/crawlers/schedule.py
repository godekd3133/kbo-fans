from __future__ import annotations

import re
from collections.abc import Iterable
from typing import Any, Optional, Tuple

from kbo_fans_backend.crawlers.base import BaseCrawler
from kbo_fans_backend.utils.html import extract_game_id, strip_tags


class ScheduleCrawler(BaseCrawler):
    """Fetches monthly schedule data from KBO schedule endpoints."""

    _TEAM_NAME_TO_ID = {
        "LG": "LG",
        "LG 트윈스": "LG",
        "KT": "KT",
        "KT 위즈": "KT",
        "SSG": "SK",
        "SSG 랜더스": "SK",
        "삼성": "SS",
        "삼성 라이온즈": "SS",
        "NC": "NC",
        "NC 다이노스": "NC",
        "한화": "HH",
        "한화 이글스": "HH",
        "롯데": "LT",
        "롯데 자이언츠": "LT",
        "KIA": "HT",
        "KIA 타이거즈": "HT",
        "두산": "OB",
        "두산 베어스": "OB",
        "키움": "WO",
        "키움 히어로즈": "WO",
    }

    def get_month_schedule(self, month: str) -> list[dict[str, Any]]:
        season_id, game_month = month.split("-")
        payload = self._post_json(
            f"{self.base_url}/ws/Schedule.asmx/GetScheduleList",
            breaker_key="kbo:schedule_list",
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
        )

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
        status_text = strip_tags(cells[offset + 7]["Text"]) if len(cells) > offset + 7 else ""
        status = self._derive_status(action_html, status_text)
        away_name, home_name = self._parse_play_names(play_html)
        away_score, home_score = self._parse_play_score(play_html)
        game_id = extract_game_id(action_html)
        away_id, home_id = self._derive_team_ids_from_game_id(game_id)
        if away_id is None or home_id is None:
            away_id, home_id = self._derive_team_ids_from_names(away_name, home_name)
        if not game_id and current_date and away_id and home_id:
            game_id = self._build_synthetic_game_id(current_date, away_id, home_id)
        if status == "UNKNOWN" and time_text:
            status = "SCHEDULED"

        return {
            "date": current_date,
            "time": time_text,
            "gameId": game_id,
            "awayId": away_id,
            "awayName": away_name,
            "awayScore": away_score,
            "homeId": home_id,
            "homeName": home_name,
            "homeScore": home_score,
            "stadium": strip_tags(cells[offset + 6]["Text"]),
            "status": status,
            "statusLabel": self._derive_status_label(status, status_text),
            "lineupOpened": self._derive_lineup_opened(action_html, status_text),
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
    def _parse_play_score(play_html: str) -> tuple[Optional[int], Optional[int]]:
        score_texts = re.findall(r"<span class=\"(?:win|lose)\">(\d+)</span>", play_html)
        if len(score_texts) >= 2:
            return int(score_texts[0]), int(score_texts[1])
        return None, None

    @staticmethod
    def _derive_team_ids_from_game_id(
        game_id: Optional[str],
    ) -> Tuple[Optional[str], Optional[str]]:
        if not game_id or len(game_id) < 13:
            return None, None
        return game_id[8:10], game_id[10:12]

    @classmethod
    def _derive_team_ids_from_names(
        cls, away_name: str, home_name: str
    ) -> Tuple[Optional[str], Optional[str]]:
        return cls._TEAM_NAME_TO_ID.get(away_name), cls._TEAM_NAME_TO_ID.get(home_name)

    @staticmethod
    def _build_synthetic_game_id(date: str, away_id: str, home_id: str) -> str:
        return f"{date.replace('-', '')}{away_id}{home_id}0"

    @staticmethod
    def _derive_status(action_html: str, status_text: str = "") -> str:
        if "취소" in status_text:
            return "CANCELLED"
        if "서스펜디드" in status_text or "중단" in status_text:
            return "SUSPENDED"
        if "section=REVIEW" in action_html:
            return "FINAL"
        if (
            "section=PREVIEW" in action_html
            or "section=START_PIT" in action_html
            or "프리뷰" in action_html
        ):
            return "SCHEDULED"
        if "문자중계" in action_html or "중계" in action_html:
            return "LIVE"
        return "UNKNOWN"

    @staticmethod
    def _derive_status_label(status: str, status_text: str) -> Optional[str]:
        label = status_text.strip()
        if not label or label == "-":
            return None
        if status in {"CANCELLED", "SUSPENDED"}:
            return label
        return None

    @staticmethod
    def _derive_lineup_opened(action_html: str, status_text: str = "") -> bool:
        if "section=START_PIT" in action_html:
            return True
        label = status_text.strip()
        if "라인업" not in label:
            return False
        return "공개" in label or "발표" in label
