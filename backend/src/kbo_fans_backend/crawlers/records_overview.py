from __future__ import annotations

import concurrent.futures
import logging
import re
import time
from contextlib import contextmanager
from typing import Any, Callable, Dict, Iterable, Iterator, List, Optional, Tuple

from kbo_fans_backend.crawlers.base import BaseCrawler
from kbo_fans_backend.utils.html import strip_tags
from kbo_fans_backend.utils.player_images import kbo_player_image_url
from kbo_fans_backend.utils.singleflight import SingleFlight
from kbo_fans_backend.utils.ttl_cache import TtlCache

logger = logging.getLogger(__name__)


@contextmanager
def _records_executor(
    max_workers: int,
) -> Iterator[concurrent.futures.ThreadPoolExecutor]:
    executor = concurrent.futures.ThreadPoolExecutor(max_workers=max_workers)
    try:
        yield executor
    except BaseException:
        # A failed records page should not wait for unrelated sibling pages to
        # hit their crawler timeout before the API can expose the failure.
        # Already-running requests remain bounded by BaseCrawler's timeout.
        executor.shutdown(wait=False, cancel_futures=True)
        raise
    else:
        executor.shutdown(wait=True)


def _raise_on_first_failed_future(
    futures: Iterable[concurrent.futures.Future],
    *,
    on_complete: Optional[Callable[[concurrent.futures.Future], None]] = None,
) -> None:
    """Surface the first failed page without waiting on submission order."""
    for future in concurrent.futures.as_completed(futures):
        if on_complete is not None:
            on_complete(future)
        future.result()


def _log_records_timing(
    *,
    season: int,
    mode: str,
    timing_started_at: float,
    page_ready_ms: Dict[str, float],
    metric_names: Iterable[str],
    complete: bool,
) -> None:
    timing_fields = " ".join(
        f"{metric}Ms={page_ready_ms.get(metric, -1.0):.1f}"
        for metric in metric_names
    )
    logger.info(
        "records_overview_timing season=%s mode=%s complete=%s pageCount=%s %s totalMs=%.1f",
        season,
        mode,
        complete,
        len(page_ready_ms),
        timing_fields,
        (time.perf_counter() - timing_started_at) * 1000,
    )


class RecordsOverviewCrawler(BaseCrawler):
    MIN_SUPPORTED_SEASON = 2002
    _SEASON_PAGE_CACHE_TTL_SECONDS = 8
    _HITTER_AVG_URL = "/Record/Player/HitterBasic/Basic1.aspx?sort=HRA_RT"
    _HITTER_HR_URL = "/Record/Player/HitterBasic/Basic1.aspx?sort=HR_CN"
    _HITTER_OPS_URL = "/Record/Player/HitterBasic/Basic2.aspx?sort=OPS_RT"
    _PITCHER_ERA_URL = "/Record/Player/PitcherBasic/Basic1.aspx?sort=ERA_RT"
    _PITCHER_WINS_URL = "/Record/Player/PitcherBasic/Basic1.aspx?sort=W_CN"
    _PITCHER_SAVES_URL = "/Record/Player/PitcherBasic/Basic1.aspx?sort=SV_CN"
    _PITCHER_STRIKEOUTS_URL = "/Record/Player/PitcherBasic/Basic1.aspx?sort=KK_CN"
    _LEADERBOARD_METRICS = {
        "avg": (_HITTER_AVG_URL, "AVG", "hitter"),
        "hr": (_HITTER_HR_URL, "HR", "hitter"),
        "ops": (_HITTER_OPS_URL, "OPS", "hitter"),
        "opsPlus": (_HITTER_OPS_URL, "OPS", "hitter"),
        "era": (_PITCHER_ERA_URL, "ERA", "pitcher"),
        "wins": (_PITCHER_WINS_URL, "W", "pitcher"),
        "saves": (_PITCHER_SAVES_URL, "SV", "pitcher"),
        "strikeouts": (_PITCHER_STRIKEOUTS_URL, "SO", "pitcher"),
    }
    _HOME_OVERVIEW_METRICS = (
        ("avg", _HITTER_AVG_URL, "AVG", "hitter"),
        ("hr", _HITTER_HR_URL, "HR", "hitter"),
        ("era", _PITCHER_ERA_URL, "ERA", "pitcher"),
    )
    _SEASON_FIELD = "ctl00$ctl00$ctl00$cphContents$cphContents$cphContents$ddlSeason$ddlSeason"
    _PLAYER_LINK_PATTERN = re.compile(
        r'href="/Record/(?:Player/(?:Hitter|Pitcher)Detail/Basic|Retire/(?:Hitter|Pitcher))\.aspx\?playerId=(\d+)"',
        re.I,
    )

    _TIMING_METRICS = ("avg", "hr", "ops", "era", "wins", "saves", "strikeouts")
    _HOME_TIMING_METRICS = ("avg", "hr", "era")
    _HOME_SEED_TIMING_METRICS = ("ops", "wins", "saves", "strikeouts")

    def __init__(self) -> None:
        super().__init__()
        self._season_page_cache: TtlCache[str, str] = TtlCache(
            self._SEASON_PAGE_CACHE_TTL_SECONDS
        )
        self._season_page_singleflight: SingleFlight[str] = SingleFlight()

    def get_overview(self, season: int) -> Dict[str, Any]:
        if not self.is_supported_season(season):
            return self.empty_overview(season)

        # OPS and OPS+ share one page, leaving seven unique page loads. Start
        # those seven pages together so one metric does not wait behind the
        # other six; the API request bulkhead still bounds whole screen GETs.
        timing_started_at = time.perf_counter()
        page_ready_ms: Dict[str, float] = {}
        future_names: Dict[concurrent.futures.Future, str] = {}

        def mark_page_ready(future: concurrent.futures.Future) -> None:
            future_name = future_names.get(future)
            if future_name is not None:
                page_ready_ms[future_name] = (time.perf_counter() - timing_started_at) * 1000

        try:
            with _records_executor(max_workers=7) as executor:
                avg_future = executor.submit(
                    self._fetch_leaders, self._HITTER_AVG_URL, season, "AVG", "hitter"
                )
                hr_future = executor.submit(
                    self._fetch_leaders, self._HITTER_HR_URL, season, "HR", "hitter"
                )
                ops_future = executor.submit(self._fetch_ops_leaders, season)
                era_future = executor.submit(
                    self._fetch_leaders, self._PITCHER_ERA_URL, season, "ERA", "pitcher"
                )
                wins_future = executor.submit(
                    self._fetch_leaders, self._PITCHER_WINS_URL, season, "W", "pitcher"
                )
                saves_future = executor.submit(
                    self._fetch_leaders, self._PITCHER_SAVES_URL, season, "SV", "pitcher"
                )
                strikeouts_future = executor.submit(
                    self._fetch_leaders,
                    self._PITCHER_STRIKEOUTS_URL,
                    season,
                    "SO",
                    "pitcher",
                )
                future_names.update(
                    {
                        avg_future: "avg",
                        hr_future: "hr",
                        ops_future: "ops",
                        era_future: "era",
                        wins_future: "wins",
                        saves_future: "saves",
                        strikeouts_future: "strikeouts",
                    }
                )

                _raise_on_first_failed_future(
                    (
                        avg_future,
                        hr_future,
                        ops_future,
                        era_future,
                        wins_future,
                        saves_future,
                        strikeouts_future,
                    ),
                    on_complete=mark_page_ready,
                )
                avg_leaders = avg_future.result()
                hr_leaders = hr_future.result()
                ops_leaders, ops_relative_leaders = ops_future.result()
                era_leaders = era_future.result()
                win_leaders = wins_future.result()
                save_leaders = saves_future.result()
                strikeout_leaders = strikeouts_future.result()
        except Exception:
            _log_records_timing(
                season=season,
                mode="full",
                timing_started_at=timing_started_at,
                page_ready_ms=page_ready_ms,
                metric_names=self._TIMING_METRICS,
                complete=False,
            )
            raise

        _log_records_timing(
            season=season,
            mode="full",
            timing_started_at=timing_started_at,
            page_ready_ms=page_ready_ms,
            metric_names=self._TIMING_METRICS,
            complete=True,
        )

        leaders = {
            "avg": avg_leaders,
            "hr": hr_leaders,
            "ops": ops_leaders,
            # `opsPlus` is retained as the compatibility wire key. The value is
            # an OPS relative index, not an official OPS+ or wRC+ metric.
            "opsPlus": ops_relative_leaders,
            "era": era_leaders,
            "wins": win_leaders,
            "saves": save_leaders,
            "strikeouts": strikeout_leaders,
        }

        return {
            "season": season,
            "leaders": leaders,
            "featured": self._build_canonical_featured(leaders=leaders, season=season),
        }

    def get_overview_from_home(
        self,
        season: int,
        home_payload: Dict[str, Any],
    ) -> Dict[str, Any]:
        """Complete a full overview from a valid current Home seed."""
        if not self.is_supported_season(season):
            return self.empty_overview(season)

        seeded_leaders = dict(home_payload.get("leaders") or {})
        timing_started_at = time.perf_counter()
        page_ready_ms: Dict[str, float] = {}
        future_names: Dict[concurrent.futures.Future, str] = {}

        def mark_page_ready(future: concurrent.futures.Future) -> None:
            metric = future_names.get(future)
            if metric is not None:
                page_ready_ms[metric] = (time.perf_counter() - timing_started_at) * 1000

        try:
            with _records_executor(max_workers=4) as executor:
                ops_future = executor.submit(self._fetch_ops_leaders, season)
                wins_future = executor.submit(
                    self._fetch_leaders,
                    self._PITCHER_WINS_URL,
                    season,
                    "W",
                    "pitcher",
                )
                saves_future = executor.submit(
                    self._fetch_leaders,
                    self._PITCHER_SAVES_URL,
                    season,
                    "SV",
                    "pitcher",
                )
                strikeouts_future = executor.submit(
                    self._fetch_leaders,
                    self._PITCHER_STRIKEOUTS_URL,
                    season,
                    "SO",
                    "pitcher",
                )
                future_names.update(
                    {
                        ops_future: "ops",
                        wins_future: "wins",
                        saves_future: "saves",
                        strikeouts_future: "strikeouts",
                    }
                )

                _raise_on_first_failed_future(
                    (ops_future, wins_future, saves_future, strikeouts_future),
                    on_complete=mark_page_ready,
                )
                ops_leaders, ops_relative_leaders = ops_future.result()
                win_leaders = wins_future.result()
                save_leaders = saves_future.result()
                strikeout_leaders = strikeouts_future.result()
        except Exception:
            _log_records_timing(
                season=season,
                mode="home_seed",
                timing_started_at=timing_started_at,
                page_ready_ms=page_ready_ms,
                metric_names=self._HOME_SEED_TIMING_METRICS,
                complete=False,
            )
            raise

        _log_records_timing(
            season=season,
            mode="home_seed",
            timing_started_at=timing_started_at,
            page_ready_ms=page_ready_ms,
            metric_names=self._HOME_SEED_TIMING_METRICS,
            complete=True,
        )

        leaders = {
            "avg": seeded_leaders.get("avg", []),
            "hr": seeded_leaders.get("hr", []),
            "ops": ops_leaders,
            # Retain the compatibility key and its existing relative-index
            # semantics while avoiding a second OPS page request.
            "opsPlus": ops_relative_leaders,
            "era": seeded_leaders.get("era", []),
            "wins": win_leaders,
            "saves": save_leaders,
            "strikeouts": strikeout_leaders,
        }
        return {
            "season": season,
            "leaders": leaders,
            "featured": self._build_canonical_featured(leaders=leaders, season=season),
        }

    def get_home_overview(self, season: int) -> Dict[str, Any]:
        """Fetch only the record groups used to build the home brief.

        The records screen still uses ``get_overview`` and all of its groups.
        Home only needs the batting-average, home-run, and ERA leaders to build
        its current cards, so keep that secondary surface from waiting on
        strikeouts, saves, wins, OPS, and the full leaderboard fan-out.
        """
        if not self.is_supported_season(season):
            return self.empty_overview(season)

        timing_started_at = time.perf_counter()
        page_ready_ms: Dict[str, float] = {}
        future_names: Dict[concurrent.futures.Future, str] = {}

        def mark_page_ready(future: concurrent.futures.Future) -> None:
            metric = future_names.get(future)
            if metric is not None:
                page_ready_ms[metric] = (time.perf_counter() - timing_started_at) * 1000

        try:
            with _records_executor(max_workers=len(self._HOME_OVERVIEW_METRICS)) as executor:
                futures = {
                    metric: executor.submit(
                        self._fetch_leaders,
                        path,
                        season,
                        metric_key,
                        player_type,
                    )
                    for metric, path, metric_key, player_type in self._HOME_OVERVIEW_METRICS
                }
                future_names = {future: metric for metric, future in futures.items()}
                _raise_on_first_failed_future(
                    futures.values(),
                    on_complete=mark_page_ready,
                )
                leaders = {
                    metric: futures[metric].result()
                    for metric, _, _, _ in self._HOME_OVERVIEW_METRICS
                }
        except Exception:
            _log_records_timing(
                season=season,
                mode="home",
                timing_started_at=timing_started_at,
                page_ready_ms=page_ready_ms,
                metric_names=self._HOME_TIMING_METRICS,
                complete=False,
            )
            raise

        _log_records_timing(
            season=season,
            mode="home",
            timing_started_at=timing_started_at,
            page_ready_ms=page_ready_ms,
            metric_names=self._HOME_TIMING_METRICS,
            complete=True,
        )

        return {
            "season": season,
            "leaders": {
                metric: leaders.get(metric, [])
                for metric in self._LEADERBOARD_METRICS
            },
            "featured": self._build_canonical_featured(leaders=leaders, season=season),
        }

    def _fetch_leaders(
        self, path: str, season: int, metric_key: str, player_type: str
    ) -> List[Dict[str, Any]]:
        html = self._fetch_season_page(
            path,
            season,
            breaker_key=f"kbo:records_overview:{path}",
        )

        rows = re.findall(r"<tr>(.*?)</tr>", html, re.S)
        return self._parse_leaders(rows, metric_key, player_type, limit=5)

    def _fetch_ops_leaders(
        self,
        season: int,
    ) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
        html = self._fetch_season_page(
            self._HITTER_OPS_URL,
            season,
            breaker_key=f"kbo:records_overview:{self._HITTER_OPS_URL}",
        )
        rows = re.findall(r"<tr>(.*?)</tr>", html, re.S)
        ops_leaders = self._parse_leaders(rows, "OPS", "hitter", limit=5)
        ops_plus_leaders = self._parse_leaders(rows, "OPS", "hitter", limit=None)
        return ops_leaders, self._build_ops_plus_leaders(ops_plus_leaders)[:5]

    def get_leaderboard(self, season: int, metric: str) -> List[Dict[str, Any]]:
        if not self.is_supported_season(season):
            return []

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
        html = self._fetch_season_page(
            path,
            season,
            breaker_key=f"kbo:records_leaderboard:{path}",
        )

        rows = re.findall(r"<tr>(.*?)</tr>", html, re.S)
        return self._parse_leaders(rows, metric_key, player_type, limit=None)

    def _parse_leaders(
        self,
        rows: List[str],
        metric_key: str,
        player_type: str,
        *,
        limit: Optional[int],
    ) -> List[Dict[str, Any]]:
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
            if limit is not None and len(leaders) >= limit:
                break
        return leaders

    def _fetch_season_page(
        self,
        path: str,
        season: int,
        *,
        breaker_key: str,
    ) -> str:
        cache_key = f"{path}|{season}"
        cached = self._season_page_cache.get(cache_key)
        if cached is not None:
            return cached

        return self._season_page_singleflight.call(
            cache_key,
            lambda: self._fetch_season_page_uncached(
                path,
                season,
                breaker_key=breaker_key,
            ),
        )

    def _fetch_season_page_uncached(
        self,
        path: str,
        season: int,
        *,
        breaker_key: str,
    ) -> str:
        url = f"{self.base_url}{path}"
        html = self._get_text(url, breaker_key=breaker_key)
        if self._selected_season(html) == str(season):
            self._season_page_cache.set(f"{path}|{season}", html)
            return html

        selected_html = self._post_text(
            url,
            breaker_key=breaker_key,
            data=self._build_web_form_payload(
                html,
                overrides={self._SEASON_FIELD: str(season)},
                event_target=self._SEASON_FIELD,
            ),
        )
        self._season_page_cache.set(f"{path}|{season}", selected_html)
        return selected_html

    @classmethod
    def _selected_season(cls, html: str) -> Optional[str]:
        match = re.search(
            rf'<select\b[^>]*name="{re.escape(cls._SEASON_FIELD)}"[^>]*>(.*?)</select>',
            html,
            re.S | re.I,
        )
        if match is None:
            return None
        return cls._selected_option_value(match.group(1))

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
                label=(
                    "시즌 탈삼진 리더"
                    if self._first_leader(leaders, "strikeouts")
                    else "시즌 ERA 리더"
                ),
                leader=(
                    self._first_leader(leaders, "strikeouts") or self._first_leader(leaders, "era")
                ),
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

    @classmethod
    def is_supported_season(cls, season: int) -> bool:
        return season >= cls.MIN_SUPPORTED_SEASON

    @staticmethod
    def empty_overview(season: int) -> Dict[str, Any]:
        return {
            "season": season,
            "leaders": {
                "avg": [],
                "hr": [],
                "ops": [],
                "opsPlus": [],
                "era": [],
                "wins": [],
                "saves": [],
                "strikeouts": [],
            },
            "featured": {},
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
            return f"OPS 상대지수 {value}"
        if metric == "ERA":
            return f"ERA {value}"
        if metric == "W":
            return f"다승 {value}"
        if metric == "SV":
            return f"세이브 {value}"
        if metric == "HLD":
            return f"홀드 {value}"
        if metric == "SO":
            return f"탈삼진 {value}"
        return value

    @staticmethod
    def _build_ops_plus_leaders(leaders: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Build an OPS-relative index while retaining the legacy wire key."""
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
