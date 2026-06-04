from __future__ import annotations

import json
from typing import Any, List, Optional

from bs4 import BeautifulSoup

from kbo_fans_backend.crawlers.base import BaseCrawler


class ScoreboardCrawler(BaseCrawler):
    """Fetches and normalizes scoreboard detail data from KBO sources."""

    def get_game_scoreboard(self, game_id: str) -> dict[str, Any]:
        payload = self._post_json(
            f"{self.base_url}/ws/Schedule.asmx/GetScoreBoardScroll",
            breaker_key=f"kbo:scoreboard:{game_id}",
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
        )

        inning_table = self._parse_table(payload.get("table2"))
        totals_table = self._parse_table(payload.get("table3"))
        away_scores = self._extract_scores(inning_table, row_index=0)
        home_scores = self._extract_scores(inning_table, row_index=1)
        away_totals = self._extract_totals(totals_table, row_index=0)
        home_totals = self._extract_totals(totals_table, row_index=1)

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
                "hits": away_totals["hits"],
                "errors": away_totals["errors"],
                "balls": away_totals["balls"],
            },
            "home": {
                "teamId": payload["HOME_ID"],
                "teamName": payload["FULL_HOME_NM"],
                "shortName": payload["HOME_NM"],
                "logoUrl": self._normalize_logo_url(payload["H_INITIAL_LK"]),
                "score": self._parse_int(payload.get("B_SCORE_CN")),
                "scores": home_scores,
                "hits": home_totals["hits"],
                "errors": home_totals["errors"],
                "balls": home_totals["balls"],
            },
        }

    def get_view1_scoreboard_detail(self, game_id: str) -> Optional[dict[str, Any]]:
        html = self._post_text(
            f"{self.base_url}/Game/LiveTextView1.aspx",
            breaker_key=f"kbo:scoreboard_view1:{game_id}",
            data={
                "leagueId": 1,
                "seriesId": 0,
                "gameId": game_id,
                "gyear": game_id[:4],
            },
            headers={
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                "X-Requested-With": "XMLHttpRequest",
            },
        )
        return self._parse_view1_scoreboard_detail(html)

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

    @staticmethod
    def _parse_table(raw: Optional[str]) -> Optional[dict[str, Any]]:
        if not raw:
            return None
        return json.loads(raw)

    def _extract_scores(
        self,
        inning_table: Optional[dict[str, Any]],
        *,
        row_index: int,
    ) -> List[Optional[int]]:
        if not inning_table:
            return [None] * 9

        rows = inning_table.get("rows", [])
        if row_index >= len(rows):
            return [None] * 9

        return self._row_scores(rows[row_index].get("row", []))

    def _extract_totals(
        self,
        totals_table: Optional[dict[str, Any]],
        *,
        row_index: int,
    ) -> dict[str, Optional[int]]:
        empty = {
            "hits": None,
            "errors": None,
            "balls": None,
        }
        if not totals_table:
            return empty

        rows = totals_table.get("rows", [])
        if row_index >= len(rows):
            return empty

        row = rows[row_index].get("row", [])
        if len(row) < 4:
            return empty

        return {
            "hits": self._parse_int(row[1].get("Text")),
            "errors": self._parse_int(row[2].get("Text")),
            "balls": self._parse_int(row[3].get("Text")),
        }

    def _derive_inning(self, payload: dict[str, Any]) -> str:
        if payload.get("END_TM"):
            return "경기종료"
        start_time = str(payload.get("START_TM") or "").strip()
        if not payload.get("table2"):
            return f"{start_time} 예정".strip() or "예정"
        return "경기중"

    def _parse_view1_scoreboard_detail(self, html: str) -> Optional[dict[str, Any]]:
        soup = BeautifulSoup(html, "html.parser")
        score_rows = soup.select("#tblScoreBoard2 tbody tr")
        total_rows = soup.select("#tblScoreBoard3 tbody tr")
        if len(score_rows) < 2:
            return None

        def parse_scores(row) -> List[Optional[int]]:
            values = []
            for cell in row.select("td"):
                text = cell.get_text(strip=True)
                values.append(self._parse_int(text))
            return values

        def parse_totals(row) -> dict[str, Optional[int]]:
            cells = row.select("td") if row is not None else []
            return {
                "hits": self._parse_int(cells[1].get_text(strip=True)) if len(cells) > 1 else None,
                "errors": (
                    self._parse_int(cells[2].get_text(strip=True)) if len(cells) > 2 else None
                ),
                "balls": self._parse_int(cells[3].get_text(strip=True)) if len(cells) > 3 else None,
            }

        return {
            "awayScores": parse_scores(score_rows[0]),
            "homeScores": parse_scores(score_rows[1]),
            "awayTotals": parse_totals(total_rows[0] if len(total_rows) > 0 else None),
            "homeTotals": parse_totals(total_rows[1] if len(total_rows) > 1 else None),
        }
