from __future__ import annotations

import concurrent.futures
import re
from typing import Any, Dict, List, Tuple

from kbo_fans_backend.crawlers.base import BaseCrawler
from kbo_fans_backend.utils.html import strip_tags


class RecordsOverviewCrawler(BaseCrawler):
    _HITTER_AVG_URL = "/Record/Player/HitterBasic/Basic1.aspx?sort=HRA_RT"
    _HITTER_HR_URL = "/Record/Player/HitterBasic/Basic1.aspx?sort=HR_CN"
    _HITTER_OPS_URL = "/Record/Player/HitterBasic/Basic2.aspx?sort=OPS_RT"
    _PITCHER_ERA_URL = "/Record/Player/PitcherBasic/Basic1.aspx?sort=ERA_RT"
    _PLAYER_IMAGE_URL = (
        "https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/person/middle/2026/{player_id}.jpg"
    )

    def get_overview(self, season: int) -> Dict[str, Any]:
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            avg_future = executor.submit(
                self._fetch_leaders, self._HITTER_AVG_URL, season, "AVG", "hitter"
            )
            hr_future = executor.submit(
                self._fetch_leaders, self._HITTER_HR_URL, season, "HR", "hitter"
            )
            ops_future = executor.submit(
                self._fetch_leaders, self._HITTER_OPS_URL, season, "OPS", "hitter"
            )
            era_future = executor.submit(
                self._fetch_leaders, self._PITCHER_ERA_URL, season, "ERA", "pitcher"
            )

            avg_leaders = avg_future.result()
            hr_leaders = hr_future.result()
            ops_leaders = ops_future.result()
            era_leaders = era_future.result()

        hitter_groups = {
            "avg": avg_leaders,
            "hr": hr_leaders,
            "ops": ops_leaders,
        }
        pitcher_groups = {
            "era": era_leaders,
        }

        return {
            "season": season,
            "leaders": {
                "avg": avg_leaders,
                "hr": hr_leaders,
                "ops": ops_leaders,
                "era": era_leaders,
            },
            "featured": {
                "todayHitter": self._build_featured_player(
                    label="오늘의 타자",
                    leader_groups=hitter_groups,
                    target_type="hitter",
                    period_label="오늘",
                ),
                "todayPitcher": self._build_featured_player(
                    label="오늘의 투수",
                    leader_groups=pitcher_groups,
                    target_type="pitcher",
                    period_label="오늘",
                ),
                "monthHitter": self._build_featured_player(
                    label="이달의 타자",
                    leader_groups=hitter_groups,
                    target_type="hitter",
                    period_label="이달",
                ),
                "monthPitcher": self._build_featured_player(
                    label="이달의 투수",
                    leader_groups=pitcher_groups,
                    target_type="pitcher",
                    period_label="이달",
                ),
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
            "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$ddlSeason$ddlSeason": str(
                season
            ),
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
                    "metricKey": metric_key,
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

    def _build_featured_player(
        self,
        label: str,
        leader_groups: Dict[str, List[Dict[str, Any]]],
        target_type: str,
        period_label: str,
    ) -> Dict[str, Any]:
        weights = {"avg": 3, "hr": 2, "ops": 3, "era": 3}
        scores: Dict[Tuple[str, str], int] = {}
        leader_lookup: Dict[Tuple[str, str], Dict[str, Any]] = {}
        for metric, leaders in leader_groups.items():
            weight = weights.get(metric, 1)
            for leader in leaders:
                key = (leader["playerId"], leader["playerType"])
                scores[key] = scores.get(key, 0) + (6 - leader["rank"]) * weight
                leader_lookup[key] = leader

        if not scores:
            return {"label": label}

        best_key = max(scores, key=scores.get)
        leader = leader_lookup[best_key]
        return {
            "label": label,
            "playerId": leader["playerId"],
            "playerType": leader["playerType"],
            "name": leader["name"],
            "teamId": leader["teamId"],
            "headline": self._headline_for_leader(leader),
            "summary": self._feature_reason(
                player_id=leader["playerId"],
                leader_groups=leader_groups,
                target_type=target_type,
                period_label=period_label,
            ),
            "imageUrl": self._PLAYER_IMAGE_URL.format(player_id=leader["playerId"]),
        }

    def _feature_reason(
        self,
        player_id: str,
        leader_groups: Dict[str, List[Dict[str, Any]]],
        target_type: str,
        period_label: str,
    ) -> str:
        reasons = []
        for metric, leaders in leader_groups.items():
            for leader in leaders:
                if (
                    leader["playerId"] == player_id
                    and leader["playerType"] == target_type
                ):
                    reasons.append(f"{metric.upper()} {leader['rank']}위")
        if not reasons:
            return ""
        return f"{period_label} 리더보드 기준 {' + '.join(reasons[:2])}"

    @staticmethod
    def _headline_for_leader(leader: Dict[str, Any]) -> str:
        metric = str(leader.get("metricKey", "")).upper()
        value = str(leader.get("value", "-"))
        if metric == "AVG":
            return f"타율 {value}"
        if metric == "HR":
            return f"홈런 {value}"
        if metric == "OPS":
            return f"OPS {value}"
        if metric == "ERA":
            return f"ERA {value}"
        return value

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
