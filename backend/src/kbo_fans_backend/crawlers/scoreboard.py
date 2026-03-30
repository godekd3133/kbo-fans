from __future__ import annotations

import json
from typing import Any, List, Optional

from kbo_fans_backend.crawlers.base import BaseCrawler


class ScoreboardCrawler(BaseCrawler):
    """Fetches and normalizes scoreboard detail data from KBO sources."""

    def get_game_scoreboard(self, game_id: str) -> dict[str, Any]:
        response = self.session.post(
            f"{self.base_url}/ws/Schedule.asmx/GetScoreBoardScroll",
            data={
                "leId": 1,
                "srId": 0,
                "seasonId": int(game_id[:4]),
                "gameId": game_id,
            },
            headers={
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                "X-Requested-With": "XMLHttpRequest",
            },
            timeout=self.timeout,
        )
        response.raise_for_status()
        payload = response.json()

        inning_table = json.loads(payload["table2"])
        totals_table = json.loads(payload["table3"])
        away_scores = self._row_scores(inning_table["rows"][0]["row"])
        home_scores = self._row_scores(inning_table["rows"][1]["row"])

        return {
            "inning": self._derive_inning(payload),
            "stadium": payload["S_NM"],
            "crowd": self._parse_int(payload.get("CROWD_CN")),
            "startTime": payload.get("START_TM"),
            "away": {
                "teamId": payload["AWAY_ID"],
                "teamName": payload["FULL_AWAY_NM"],
                "shortName": payload["AWAY_NM"],
                "logoUrl": self._normalize_logo_url(payload["A_INITIAL_LK"]),
                "score": self._parse_int(payload.get("T_SCORE_CN")),
                "scores": away_scores,
                "hits": self._parse_int(totals_table["rows"][0]["row"][1]["Text"]),
                "errors": self._parse_int(totals_table["rows"][0]["row"][2]["Text"]),
                "balls": self._parse_int(totals_table["rows"][0]["row"][3]["Text"]),
            },
            "home": {
                "teamId": payload["HOME_ID"],
                "teamName": payload["FULL_HOME_NM"],
                "shortName": payload["HOME_NM"],
                "logoUrl": self._normalize_logo_url(payload["H_INITIAL_LK"]),
                "score": self._parse_int(payload.get("B_SCORE_CN")),
                "scores": home_scores,
                "hits": self._parse_int(totals_table["rows"][1]["row"][1]["Text"]),
                "errors": self._parse_int(totals_table["rows"][1]["row"][2]["Text"]),
                "balls": self._parse_int(totals_table["rows"][1]["row"][3]["Text"]),
            },
        }

    @staticmethod
    def _normalize_logo_url(value: Optional[str]) -> Optional[str]:
        if not value:
            return None
        if value.startswith("//"):
            return f"https:{value}"
        return value

    @staticmethod
    def _parse_int(value: Any) -> Optional[int]:
        if value in (None, "", "-"):
            return None
        if isinstance(value, int):
            return value
        return int(str(value).replace(",", ""))

    @staticmethod
    def _row_scores(cells: list[dict[str, Any]]) -> List[Optional[int]]:
        scores: List[Optional[int]] = []
        for cell in cells:
            text = str(cell.get("Text", "")).strip()
            scores.append(None if text in {"", "-"} else int(text))
        return scores

    def _derive_inning(self, payload: dict[str, Any]) -> str:
        if payload.get("END_TM"):
            return "경기종료"
        return "경기중"
