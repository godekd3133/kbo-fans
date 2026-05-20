from __future__ import annotations

import concurrent.futures
import re
from typing import Any, Dict, List, Optional, Tuple

from kbo_fans_backend.crawlers.base import BaseCrawler
from kbo_fans_backend.utils.html import strip_tags
from kbo_fans_backend.utils.player_images import kbo_player_image_url


class RecordsOverviewCrawler(BaseCrawler):
    _HITTER_AVG_URL = "/Record/Player/HitterBasic/Basic1.aspx?sort=HRA_RT"
    _HITTER_HR_URL = "/Record/Player/HitterBasic/Basic1.aspx?sort=HR_CN"
    _HITTER_OPS_URL = "/Record/Player/HitterBasic/Basic2.aspx?sort=OPS_RT"
    _PITCHER_ERA_URL = "/Record/Player/PitcherBasic/Basic1.aspx?sort=ERA_RT"
    _LEADERBOARD_METRICS = {
        "avg": (_HITTER_AVG_URL, "AVG", "hitter"),
        "hr": (_HITTER_HR_URL, "HR", "hitter"),
        "ops": (_HITTER_OPS_URL, "OPS", "hitter"),
        "opsPlus": (_HITTER_OPS_URL, "OPS", "hitter"),
        "era": (_PITCHER_ERA_URL, "ERA", "pitcher"),
    }
    _SEASON_FIELD = "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$ddlSeason$ddlSeason"
    _PLAYER_LINK_PATTERN = re.compile(
        r'href="/Record/(?:Player/(?:Hitter|Pitcher)Detail/Basic|Retire/(?:Hitter|Pitcher))\.aspx\?playerId=(\d+)"',
        re.I,
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
            ops_plus_future = executor.submit(
                self._fetch_leaderboard, self._HITTER_OPS_URL, season, "OPS", "hitter"
            )
            era_future = executor.submit(
                self._fetch_leaders, self._PITCHER_ERA_URL, season, "ERA", "pitcher"
            )

            avg_leaders = avg_future.result()
            hr_leaders = hr_future.result()
            ops_leaders = ops_future.result()
            ops_plus_leaders = self._build_ops_plus_leaders(ops_plus_future.result())[:5]
            era_leaders = era_future.result()

        leaders = {
            "avg": avg_leaders,
            "hr": hr_leaders,
            "ops": ops_leaders,
            "opsPlus": ops_plus_leaders,
            "era": era_leaders,
        }

        return {
            "season": season,
            "leaders": leaders,
            "featured": self._build_canonical_featured(leaders=leaders, season=season),
        }

    def _fetch_leaders(
        self, path: str, season: int, metric_key: str, player_type: str
    ) -> List[Dict[str, Any]]:
        html = self._get_text(
            f"{self.base_url}{path}",
            breaker_key=f"kbo:records_overview:{path}",
        )
        html = self._post_text(
            f"{self.base_url}{path}",
            breaker_key=f"kbo:records_overview:{path}",
            data=self._build_web_form_payload(
                html,
                overrides={self._SEASON_FIELD: str(season)},
                event_target=self._SEASON_FIELD,
            ),
        )

        rows = re.findall(r"<tr>(.*?)</tr>", html, re.S)
        value_index = self._resolve_metric_index(rows, metric_key)
        leaders: List[Dict[str, Any]] = []
        for row in rows:
            cells = re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, re.S)
            if len(cells) <= value_index:
                continue
            player_link = self._extract_player_link(cells[1])
            if not player_link:
                continue
            leaders.append(
                {
                    "rank": int(strip_tags(cells[0])),
                    "playerId": player_link[0],
                    "playerType": player_type,
                    "metricKey": metric_key,
                    "name": strip_tags(cells[1]),
                    "teamId": self._team_name_to_id(strip_tags(cells[2])),
                    "value": strip_tags(cells[value_index]),
                    "isRetired": player_link[1],
                }
            )
            if len(leaders) >= 5:
                break
        return leaders

    def get_leaderboard(self, season: int, metric: str) -> List[Dict[str, Any]]:
        metric_info = self._LEADERBOARD_METRICS.get(metric)
        if metric_info is None:
            return []
        path, metric_key, player_type = metric_info
        if metric == "opsPlus":
            return self._build_ops_plus_leaders(
                self._fetch_leaderboard(path, season, metric_key, player_type)
            )
        return self._fetch_leaderboard(path, season, metric_key, player_type)

    def _fetch_leaderboard(
        self, path: str, season: int, metric_key: str, player_type: str
    ) -> List[Dict[str, Any]]:
        html = self._get_text(
            f"{self.base_url}{path}",
            breaker_key=f"kbo:records_leaderboard:{path}",
        )
        html = self._post_text(
            f"{self.base_url}{path}",
            breaker_key=f"kbo:records_leaderboard:{path}",
            data=self._build_web_form_payload(
                html,
                overrides={self._SEASON_FIELD: str(season)},
                event_target=self._SEASON_FIELD,
            ),
        )

        rows = re.findall(r"<tr>(.*?)</tr>", html, re.S)
        value_index = self._resolve_metric_index(rows, metric_key)
        leaders: List[Dict[str, Any]] = []
        for row in rows:
            cells = re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, re.S)
            if len(cells) <= value_index:
                continue
            player_link = self._extract_player_link(cells[1])
            if not player_link:
                continue
            leaders.append(
                {
                    "rank": int(strip_tags(cells[0])),
                    "playerId": player_link[0],
                    "playerType": player_type,
                    "metricKey": metric_key,
                    "name": strip_tags(cells[1]),
                    "teamId": self._team_name_to_id(strip_tags(cells[2])),
                    "value": strip_tags(cells[value_index]),
                    "isRetired": player_link[1],
                }
            )
        return leaders

    @staticmethod
    def _resolve_metric_index(rows: List[str], metric_key: str) -> int:
        for row in rows:
            cells = re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, re.S)
            labels = [strip_tags(cell).strip().upper() for cell in cells]
            if metric_key.upper() in labels:
                return labels.index(metric_key.upper())
        return 3

    @classmethod
    def _extract_player_link(cls, html: str) -> Optional[Tuple[str, bool]]:
        match = cls._PLAYER_LINK_PATTERN.search(html)
        if not match:
            return None
        return match.group(1), "/Record/Retire/" in match.group(0)

    def _build_featured_player(
        self,
        season: int,
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
            "imageUrl": kbo_player_image_url(season, leader["playerId"]),
        }

    def _build_canonical_featured(
        self, leaders: Dict[str, Any], season: int
    ) -> Dict[str, Dict[str, Any]]:
        return {
            "todayHitter": self._featured_from_leader(
                label="시즌 타율 리더",
                leader=self._first_leader(leaders, "avg"),
                season=season,
            ),
            "todayPitcher": self._featured_from_leader(
                label="시즌 ERA 리더",
                leader=self._first_leader(leaders, "era"),
                season=season,
            ),
            "monthHitter": self._featured_from_leader(
                label="시즌 홈런왕",
                leader=self._first_leader(leaders, "hr"),
                season=season,
            ),
            "monthPitcher": self._featured_from_leader(
                label="시즌 OPS 리더",
                leader=self._first_leader(leaders, "ops"),
                season=season,
            ),
        }

    @staticmethod
    def _first_leader(leaders: Dict[str, Any], metric: str) -> Optional[Dict[str, Any]]:
        metric_leaders = leaders.get(metric) or []
        if not metric_leaders:
            return None
        leader = metric_leaders[0]
        return leader if isinstance(leader, dict) else None

    def _featured_from_leader(
        self, label: str, leader: Optional[Dict[str, Any]], season: int
    ) -> Dict[str, Any]:
        if leader is None:
            return {"label": label}
        player_id = str(leader.get("playerId") or "")
        payload = {
            "label": label,
            "playerId": player_id,
            "playerType": leader.get("playerType"),
            "name": leader.get("name"),
            "teamId": leader.get("teamId"),
            "headline": self._headline_for_leader(leader),
            "summary": f"{season} 시즌 KBO 공식 기록 기준",
        }
        if player_id:
            payload["imageUrl"] = kbo_player_image_url(season, player_id)
        return payload

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
                if leader["playerId"] == player_id and leader["playerType"] == target_type:
                    reasons.append(f"{metric.upper()} {leader['rank']}위")
        if not reasons:
            return ""
        return " + ".join(reasons[:2])

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
        if metric == "OPSPLUS":
            return f"OPS+ {value}"
        if metric == "ERA":
            return f"ERA {value}"
        return value

    @staticmethod
    def _build_ops_plus_leaders(leaders: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        parsed = []
        for leader in leaders:
            try:
                ops = float(str(leader.get("value", "")).strip())
            except ValueError:
                continue
            parsed.append((leader, ops))

        if not parsed:
            return []

        league_average_ops = sum(ops for _, ops in parsed) / len(parsed)
        if league_average_ops <= 0:
            return []

        calculated = []
        for leader, ops in parsed:
            calculated.append(
                {
                    **leader,
                    "metricKey": "OPSPLUS",
                    "value": str(round((ops / league_average_ops) * 100)),
                }
            )

        calculated.sort(key=lambda leader: int(leader["value"]), reverse=True)
        return [
            {
                **leader,
                "rank": index + 1,
            }
            for index, leader in enumerate(calculated)
        ]

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
