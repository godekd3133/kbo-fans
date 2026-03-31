from __future__ import annotations

import re
from typing import Any, Dict, List, Tuple

from kbo_fans_backend.crawlers.base import BaseCrawler
from kbo_fans_backend.crawlers.player_stats import PlayerStatsCrawler
from kbo_fans_backend.utils.html import strip_tags


class RecordsOverviewCrawler(BaseCrawler):
    _HITTER_AVG_URL = "/Record/Player/HitterBasic/Basic1.aspx?sort=HRA_RT"
    _HITTER_HR_URL = "/Record/Player/HitterBasic/Basic1.aspx?sort=HR_CN"
    _HITTER_OPS_URL = "/Record/Player/HitterBasic/Basic2.aspx?sort=OPS_RT"
    _PITCHER_ERA_URL = "/Record/Player/PitcherBasic/Basic1.aspx?sort=ERA_RT"

    def __init__(self) -> None:
        super().__init__()
        self.player_stats_crawler = PlayerStatsCrawler()

    def get_overview(self, season: int) -> Dict[str, Any]:
        avg_leaders = self._fetch_leaders(self._HITTER_AVG_URL, season, "AVG", "hitter")
        hr_leaders = self._fetch_leaders(self._HITTER_HR_URL, season, "HR", "hitter")
        ops_leaders = self._fetch_leaders(self._HITTER_OPS_URL, season, "OPS", "hitter")
        era_leaders = self._fetch_leaders(self._PITCHER_ERA_URL, season, "ERA", "pitcher")

        return {
            "season": season,
            "leaders": {
                "avg": avg_leaders,
                "hr": hr_leaders,
                "ops": ops_leaders,
                "era": era_leaders,
            },
            "featured": {
                "todayPlayer": self._build_featured_card("오늘의 플레이어", avg_leaders, season),
                "monthPlayer": self._build_featured_card("이달의 플레이어", ops_leaders, season),
            },
        }

    def _fetch_leaders(
        self, path: str, season: int, metric_key: str, player_type: str
    ) -> List[Dict[str, Any]]:
        html = self._get_text(
            f"{self.base_url}{path}",
            breaker_key=f"kbo:records_overview:{path}",
        )
        payload = {
            "__VIEWSTATE": self._extract_hidden(html, "__VIEWSTATE"),
            "__VIEWSTATEGENERATOR": self._extract_hidden(html, "__VIEWSTATEGENERATOR"),
            "__EVENTVALIDATION": self._extract_hidden(html, "__EVENTVALIDATION"),
            "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$ddlSeason$ddlSeason": str(season),
            "__EVENTTARGET": "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$ddlSeason$ddlSeason",
            "__EVENTARGUMENT": "",
        }
        html = self._post_text(
            f"{self.base_url}{path}",
            breaker_key=f"kbo:records_overview:{path}",
            data=payload,
        )

        rows = re.findall(r"<tr>(.*?)</tr>", html, re.S)
        value_index = self._resolve_metric_index(rows, metric_key)
        leaders: List[Dict[str, Any]] = []
        for row in rows:
            cells = re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, re.S)
            if len(cells) <= value_index:
                continue
            player_link = re.search(
                r'href="/Record/Player/(?:Hitter|Pitcher)Detail/Basic\.aspx\?playerId=(\d+)"',
                cells[1],
            )
            if not player_link:
                continue
            leaders.append(
                {
                    "rank": int(strip_tags(cells[0])),
                    "playerId": player_link.group(1),
                    "playerType": player_type,
                    "name": strip_tags(cells[1]),
                    "teamId": self._team_name_to_id(strip_tags(cells[2])),
                    "value": strip_tags(cells[value_index]),
                }
            )
            if len(leaders) >= 5:
                break
        return leaders

    @staticmethod
    def _resolve_metric_index(rows: List[str], metric_key: str) -> int:
        for row in rows:
            cells = re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, re.S)
            labels = [strip_tags(cell).strip().upper() for cell in cells]
            if metric_key.upper() in labels:
                return labels.index(metric_key.upper())
        return 3

    def _build_featured_card(
        self, label: str, leaders: List[Dict[str, Any]], season: int
    ) -> Dict[str, Any]:
        if not leaders:
            return {"label": label}
        leader = leaders[0]
        detail = self.player_stats_crawler.get_player_detail(
            player_id=leader["playerId"],
            player_type=leader["playerType"],
            season=season,
            include_recent=True,
        )
        recent = detail.get("recentGames", [])
        return {
            "label": label,
            "playerId": leader["playerId"],
            "playerType": leader["playerType"],
            "name": detail.get("name"),
            "teamId": detail.get("teamId"),
            "headline": detail.get("headlineStat"),
            "summary": recent[0]["summary"] if recent else detail.get("secondaryStat"),
            "imageUrl": detail.get("imageUrl"),
        }

    @staticmethod
    def _extract_hidden(html: str, name: str) -> str:
        pattern = r'name="%s"[^>]*value="([^"]*)"' % re.escape(name)
        match = re.search(pattern, html)
        return match.group(1) if match else ""

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
