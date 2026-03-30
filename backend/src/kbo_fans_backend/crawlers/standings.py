from __future__ import annotations

import re
from typing import Any

from kbo_fans_backend.crawlers.base import BaseCrawler


class StandingsCrawler(BaseCrawler):
    """Fetches daily team standings from the rendered standings page."""

    def get_standings(self, season: int) -> dict[str, Any]:
        response = self.session.get(
            f"{self.base_url}/Record/TeamRank/TeamRankDaily.aspx",
            timeout=self.timeout,
        )
        response.raise_for_status()
        html = response.text

        updated_match = re.search(r'<span class="exp2">\(([^)]+) 기준\)</span>', html)
        row_matches = re.findall(
            (
                r"<tr>\s*<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*"
                r"<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*"
                r"<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*"
                r"<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*</tr>"
            ),
            html,
        )

        standings = []
        for row in row_matches:
            rank, team_name, games, wins, losses, draws, pct, gb, last10, streak, home, away = row
            standings.append(
                {
                    "rank": int(rank),
                    "teamId": self._team_name_to_id(team_name),
                    "teamName": self._team_name_to_full_name(team_name),
                    "wins": int(wins),
                    "losses": int(losses),
                    "draws": int(draws),
                    "pct": pct,
                    "gb": gb,
                    "last10": last10,
                    "streak": streak,
                    "games": int(games),
                    "home": home,
                    "away": away,
                }
            )

        return {
            "season": season,
            "standings": standings,
            "updatedAt": updated_match.group(1) if updated_match else None,
        }

    @staticmethod
    def _team_name_to_id(team_name: str) -> str:
        return {
            "LG": "LG",
            "KT": "KT",
            "SSG": "SK",
            "삼성": "SS",
            "NC": "NC",
            "한화": "HH",
            "롯데": "LT",
            "KIA": "HT",
            "두산": "OB",
            "키움": "WO",
        }.get(team_name, team_name)

    @staticmethod
    def _team_name_to_full_name(team_name: str) -> str:
        return {
            "LG": "LG 트윈스",
            "KT": "KT 위즈",
            "SSG": "SSG 랜더스",
            "삼성": "삼성 라이온즈",
            "NC": "NC 다이노스",
            "한화": "한화 이글스",
            "롯데": "롯데 자이언츠",
            "KIA": "KIA 타이거즈",
            "두산": "두산 베어스",
            "키움": "키움 히어로즈",
        }.get(team_name, team_name)
