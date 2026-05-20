from __future__ import annotations

import concurrent.futures
import re
from typing import Any, Dict, Optional

from kbo_fans_backend.crawlers.base import BaseCrawler
from kbo_fans_backend.utils.html import strip_tags


class TeamStatsCrawler(BaseCrawler):
    _HITTER_URL = "/Record/Team/Hitter/Basic1.aspx"
    _PITCHER_URL = "/Record/Team/Pitcher/Basic1.aspx"
    _SEASON_FIELD = (
        "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$ddlSeason$ddlSeason"
    )
    _TEAM_NAME_MAP = {
        "LG": "LG",
        "KT": "KT",
        "SK": "SSG",
        "SS": "삼성",
        "NC": "NC",
        "HH": "한화",
        "LT": "롯데",
        "HT": "KIA",
        "OB": "두산",
        "WO": "키움",
    }

    def get_team_stats(self, team_id: str, season: int) -> Dict[str, Any]:
        team_name = self._TEAM_NAME_MAP[team_id]
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            hitter_future = executor.submit(
                self._fetch_table_stats, self._HITTER_URL, season, team_name
            )
            pitcher_future = executor.submit(
                self._fetch_table_stats, self._PITCHER_URL, season, team_name
            )
            hitter_stats = hitter_future.result()
            pitcher_stats = pitcher_future.result()
        return {
            "teamId": team_id,
            "season": season,
            "hitting": hitter_stats,
            "pitching": pitcher_stats,
        }

    def _fetch_table_stats(self, path: str, season: int, team_name: str) -> Dict[str, str]:
        html = self._get_text(
            f"{self.base_url}{path}",
            breaker_key=f"kbo:team_stats:{path}",
        )
        html = self._post_text(
            f"{self.base_url}{path}",
            breaker_key=f"kbo:team_stats:{path}",
            data=self._build_web_form_payload(
                html,
                overrides={self._SEASON_FIELD: str(season)},
                event_target=self._SEASON_FIELD,
            ),
        )

        header_match = re.search(r"<thead>(.*?)</thead>", html, re.S)
        body_match = re.search(r"<tbody>(.*?)</tbody>", html, re.S)
        if not header_match or not body_match:
            return {}

        headers = [strip_tags(item) for item in re.findall(r"<th[^>]*>(.*?)</th>", header_match.group(1), re.S)]
        rows = re.findall(r"<tr>(.*?)</tr>", body_match.group(1), re.S)
        for row in rows:
            cells = [strip_tags(item) for item in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, re.S)]
            if len(cells) != len(headers):
                continue
            if cells[1] == team_name:
                return {header: value for header, value in zip(headers, cells)}
        return {}

    @staticmethod
    def _extract_hidden(html: str, name: str) -> str:
        pattern = r'name="%s"[^>]*value="([^"]*)"' % re.escape(name)
        match = re.search(pattern, html)
        return match.group(1) if match else ""
