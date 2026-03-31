from __future__ import annotations

import json
from typing import Any

from kbo_fans_backend.crawlers.base import BaseCrawler
from kbo_fans_backend.utils.html import strip_tags


class LineupCrawler(BaseCrawler):
    """Fetches lineup analysis data and normalizes it into lineup output."""

    def get_lineup(self, game_id: str) -> dict[str, Any]:
        payload = self._post_json(
            f"{self.base_url}/ws/Schedule.asmx/GetLineUpAnalysis",
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
            breaker_key="kbo_lineup",
        )
        away_id, home_id = self._derive_team_ids(game_id)

        if len(payload) < 5 or not payload[1] or not payload[2] or not payload[3] or not payload[4]:
            return self._empty_lineup(game_id, away_id, home_id)

        home_meta = payload[1][0]
        away_meta = payload[2][0]
        home_lineup = self._parse_lineup_table(json.loads(payload[3][0]))
        away_lineup = self._parse_lineup_table(json.loads(payload[4][0]))

        return {
            "gameId": game_id,
            "away": {
                "teamId": away_meta.get("T_ID", away_id),
                "lineup": away_lineup,
            },
            "home": {
                "teamId": home_meta.get("T_ID", home_id),
                "lineup": home_lineup,
            },
        }

    @staticmethod
    def _derive_team_ids(game_id: str) -> tuple[str, str]:
        return game_id[8:10], game_id[10:12]

    @staticmethod
    def _empty_lineup(game_id: str, away_id: str, home_id: str) -> dict[str, Any]:
        return {
            "gameId": game_id,
            "away": {"teamId": away_id, "lineup": []},
            "home": {"teamId": home_id, "lineup": []},
        }

    @staticmethod
    def _parse_lineup_table(table: dict[str, Any]) -> list[dict[str, Any]]:
        lineup = []
        for row in table["rows"]:
            cells = [strip_tags(cell["Text"]) for cell in row["row"]]
            lineup.append(
                {
                    "order": int(cells[0]),
                    "position": LineupCrawler._position_to_code(cells[1]),
                    "positionKo": cells[1],
                    "name": cells[2],
                }
            )
        return lineup

    @staticmethod
    def _position_to_code(position_ko: str) -> str:
        mapping = {
            "투수": "P",
            "포수": "C",
            "1루수": "1B",
            "2루수": "2B",
            "3루수": "3B",
            "유격수": "SS",
            "좌익수": "LF",
            "중견수": "CF",
            "우익수": "RF",
            "지명타자": "DH",
        }
        return mapping.get(position_ko, position_ko)
