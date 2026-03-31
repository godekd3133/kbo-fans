from __future__ import annotations

import json
from html import unescape
from typing import Any, Optional, Union

from kbo_fans_backend.crawlers.base import BaseCrawler
from kbo_fans_backend.utils.html import strip_tags


class BoxscoreCrawler(BaseCrawler):
    """Fetches boxscore data."""

    def get_boxscore(self, game_id: str) -> dict[str, Any]:
        payload = self._post_json(
            f"{self.base_url}/ws/Schedule.asmx/GetBoxScoreScroll",
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
            breaker_key="kbo_boxscore",
        )
        away_id, home_id = self._derive_team_ids(game_id)

        hitters_payload = payload.get("arrHitter")
        pitchers_payload = payload.get("arrPitcher")
        if not hitters_payload or not pitchers_payload:
            return self._empty_boxscore(game_id, away_id, home_id)

        away_hitters = self._parse_hitter_team(hitters_payload[0])
        home_hitters = self._parse_hitter_team(hitters_payload[1])
        away_pitchers = self._parse_pitcher_team(pitchers_payload[0])
        home_pitchers = self._parse_pitcher_team(pitchers_payload[1])

        return {
            "gameId": game_id,
            "away": {
                "teamId": away_id,
                "batters": away_hitters["batters"],
                "pitchers": away_pitchers["pitchers"],
                "totals": {
                    "batting": away_hitters["totals"],
                    "pitching": away_pitchers["totals"],
                },
            },
            "home": {
                "teamId": home_id,
                "batters": home_hitters["batters"],
                "pitchers": home_pitchers["pitchers"],
                "totals": {
                    "batting": home_hitters["totals"],
                    "pitching": home_pitchers["totals"],
                },
            },
        }

    @staticmethod
    def _empty_boxscore(game_id: str, away_id: str, home_id: str) -> dict[str, Any]:
        empty_totals = {
            "batting": {"atBats": 0, "runs": 0, "hits": 0, "rbi": 0},
            "pitching": {
                "innings": "0.0",
                "hits": 0,
                "strikeouts": 0,
                "walks": 0,
                "earnedRuns": 0,
            },
        }
        return {
            "gameId": game_id,
            "away": {
                "teamId": away_id,
                "batters": [],
                "pitchers": [],
                "totals": empty_totals,
            },
            "home": {
                "teamId": home_id,
                "batters": [],
                "pitchers": [],
                "totals": empty_totals,
            },
        }

    def _parse_hitter_team(self, team_payload: dict[str, Any]) -> dict[str, Any]:
        table1 = json.loads(team_payload["table1"])
        table3 = json.loads(team_payload["table3"])

        batters = []
        totals = {"atBats": 0, "runs": 0, "hits": 0, "rbi": 0}
        for row1, row3 in zip(table1["rows"], table3["rows"]):
            left = [strip_tags(cell["Text"]).replace("\xa0", "").strip() for cell in row1["row"]]
            right = [strip_tags(cell["Text"]).replace("\xa0", "").strip() for cell in row3["row"]]
            batter = {
                "order": self._parse_int(left[0]),
                "position": left[1],
                "name": left[2],
                "atBats": self._parse_int(right[0]),
                "hits": self._parse_int(right[1]),
                "rbi": self._parse_int(right[2]),
                "runs": self._parse_int(right[3]),
            }
            batters.append(batter)
            totals["atBats"] += batter["atBats"] or 0
            totals["runs"] += batter["runs"] or 0
            totals["hits"] += batter["hits"] or 0
            totals["rbi"] += batter["rbi"] or 0

        return {"batters": batters, "totals": totals}

    def _parse_pitcher_team(self, team_payload: dict[str, Any]) -> dict[str, Any]:
        table = json.loads(team_payload["table"])
        pitchers = []
        totals = {
            "innings": "0.0",
            "hits": 0,
            "strikeouts": 0,
            "walks": 0,
            "earnedRuns": 0,
        }
        innings_outs = 0

        for row in table["rows"]:
            cells = [strip_tags(cell["Text"]).replace("\xa0", "").strip() for cell in row["row"]]
            pitcher = {
                "name": cells[0],
                "innings": cells[6],
                "hits": self._parse_int(cells[10]),
                "strikeouts": self._parse_int(cells[13]),
                "walks": self._parse_int(cells[12]),
                "earnedRuns": self._parse_int(cells[15]),
                "decision": None if cells[2] in {"", "-"} else unescape(cells[2]),
            }
            pitchers.append(pitcher)
            totals["hits"] += pitcher["hits"] or 0
            totals["strikeouts"] += pitcher["strikeouts"] or 0
            totals["walks"] += pitcher["walks"] or 0
            totals["earnedRuns"] += pitcher["earnedRuns"] or 0
            innings_outs += self._innings_to_outs(cells[6])

        totals["innings"] = self._outs_to_innings(innings_outs)
        return {"pitchers": pitchers, "totals": totals}

    @staticmethod
    def _derive_team_ids(game_id: str) -> tuple[str, str]:
        return game_id[8:10], game_id[10:12]

    @staticmethod
    def _parse_int(value: Union[str, int, None]) -> Optional[int]:
        if value in (None, "", "-", "&nbsp;"):
            return None
        if isinstance(value, int):
            return value
        return int(str(value))

    @staticmethod
    def _innings_to_outs(value: str) -> int:
        value = value.strip()
        if not value:
            return 0
        if " " in value:
            whole, frac = value.split(" ", 1)
            return int(whole) * 3 + (2 if "2/3" in frac else 1 if "1/3" in frac else 0)
        if value.isdigit():
            return int(value) * 3
        return 0

    @staticmethod
    def _outs_to_innings(outs: int) -> str:
        whole = outs // 3
        remainder = outs % 3
        return f"{whole}.{remainder}"
