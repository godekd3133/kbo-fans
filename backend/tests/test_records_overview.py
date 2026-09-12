import concurrent.futures
import json
import logging
import threading
from pathlib import Path

import pytest

from kbo_fans_backend.crawlers.records_overview import RecordsOverviewCrawler
from kbo_fans_backend.services.records_overview import RecordsOverviewService
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.kbo_time import current_kbo_year


class _FailingRecordsCrawler:
    def get_overview(self, season: int):
        raise RuntimeError("overview unavailable")

    def get_leaderboard(self, season: int, metric: str):
        raise RuntimeError("leaderboard unavailable")


class _FreshRecordsCrawler:
    def get_overview(self, season: int):
        return {
            "season": season,
            "leaders": {
                "avg": [
                    {
                        "rank": 1,
                        "playerId": "fresh",
                        "playerType": "hitter",
                        "metricKey": "AVG",
                        "name": "Fresh",
                        "teamId": "LG",
                        "value": ".500",
                    }
                ],
                "hr": [],
                "ops": [],
                "era": [],
            },
            "featured": {},
        }

    def get_leaderboard(self, season: int, metric: str):
        return [
            {
                "rank": 1,
                "playerId": "fresh",
                "playerType": "hitter",
                "metricKey": metric.upper(),
                "name": "Fresh",
                "teamId": "LG",
                "value": ".500",
            }
        ]


class _HomeOverviewCrawler:
    def __init__(self) -> None:
        self.home_overview_calls = 0
        self.overview_calls = 0

    def get_home_overview(self, season: int):
        self.home_overview_calls += 1
        return {
            "season": season,
            "leaders": {
                "avg": [
                    {
                        "rank": 1,
                        "playerId": "avg",
                        "playerType": "hitter",
                        "metricKey": "AVG",
                        "name": "Average",
                        "teamId": "LG",
                        "value": ".400",
                    }
                ],
                "hr": [
                    {
                        "rank": 1,
                        "playerId": "hr",
                        "playerType": "hitter",
                        "metricKey": "HR",
                        "name": "Home Run",
                        "teamId": "KT",
                        "value": "20",
                    }
                ],
                "era": [
                    {
                        "rank": 1,
                        "playerId": "era",
                        "playerType": "pitcher",
                        "metricKey": "ERA",
                        "name": "ERA Pitcher",
                        "teamId": "HT",
                        "value": "2.00",
                    }
                ],
                "strikeouts": [
                    {
                        "rank": 1,
                        "playerId": "strikeouts",
                        "playerType": "pitcher",
                        "metricKey": "SO",
                        "name": "Strikeout Pitcher",
                        "teamId": "OB",
                        "value": "100",
                    }
                ],
            },
            "featured": {},
        }

    def get_overview(self, season: int):
        self.overview_calls += 1
        raise AssertionError("Home should not request the full records overview")

    def get_leaderboard(self, season: int, metric: str):
        return []


class _FailingHomeOverviewCrawler(_HomeOverviewCrawler):
    def get_home_overview(self, season: int):
        raise RuntimeError("home overview unavailable")


class _BlockingOverviewCrawler(_FreshRecordsCrawler):
    def __init__(self) -> None:
        self.calls = 0
        self._lock = threading.Lock()
        self.first_call_started = threading.Event()
        self.duplicate_call_started = threading.Event()
        self.release = threading.Event()

    def get_overview(self, season: int):
        with self._lock:
            self.calls += 1
            call_number = self.calls
        self.first_call_started.set()
        if call_number > 1:
            self.duplicate_call_started.set()
        if not self.release.wait(timeout=3):
            raise TimeoutError("records overview crawler was not released")
        return super().get_overview(season)


class _BlockingLeaderboardCrawler(_FreshRecordsCrawler):
    def __init__(self) -> None:
        self.calls = 0
        self._lock = threading.Lock()
        self.first_call_started = threading.Event()
        self.duplicate_call_started = threading.Event()
        self.release = threading.Event()

    def get_leaderboard(self, season: int, metric: str):
        with self._lock:
            self.calls += 1
            call_number = self.calls
        self.first_call_started.set()
        if call_number > 1:
            self.duplicate_call_started.set()
        if not self.release.wait(timeout=3):
            raise TimeoutError("leaderboard crawler was not released")
        return super().get_leaderboard(season, metric)


class _TrackingFreshRecordsCrawler(_FreshRecordsCrawler):
    def __init__(self) -> None:
        self.overview_calls = 0
        self.leaderboard_calls = 0

    def get_overview(self, season: int):
        self.overview_calls += 1
        return super().get_overview(season)

    def get_leaderboard(self, season: int, metric: str):
        self.leaderboard_calls += 1
        return super().get_leaderboard(season, metric)


class _RecoveringLeaderboardCrawler(_FreshRecordsCrawler):
    def __init__(self) -> None:
        self.leaderboard_calls = 0

    def get_leaderboard(self, season: int, metric: str):
        self.leaderboard_calls += 1
        leaders = super().get_leaderboard(season, metric)
        if self.leaderboard_calls == 1:
            return [{**leaders[0], "rank": 2, "name": "Missing First"}]
        return leaders


class _PitchingFeaturedRecordsCrawler:
    def get_overview(self, season: int):
        return {
            "season": season,
            "leaders": {
                "avg": [
                    {
                        "rank": 1,
                        "playerId": "avg",
                        "playerType": "hitter",
                        "metricKey": "AVG",
                        "name": "Avg Hitter",
                        "teamId": "LG",
                        "value": ".400",
                    }
                ],
                "hr": [],
                "ops": [
                    {
                        "rank": 1,
                        "playerId": "ops",
                        "playerType": "hitter",
                        "metricKey": "OPS",
                        "name": "Ops Hitter",
                        "teamId": "KT",
                        "value": "1.000",
                    }
                ],
                "era": [
                    {
                        "rank": 1,
                        "playerId": "era",
                        "playerType": "pitcher",
                        "metricKey": "ERA",
                        "name": "Era Pitcher",
                        "teamId": "HT",
                        "value": "2.36",
                    }
                ],
                "wins": [
                    {
                        "rank": 1,
                        "playerId": "wins",
                        "playerType": "pitcher",
                        "metricKey": "W",
                        "name": "Win Pitcher",
                        "teamId": "HH",
                        "value": "9",
                    }
                ],
                "saves": [
                    {
                        "rank": 1,
                        "playerId": "saves",
                        "playerType": "pitcher",
                        "metricKey": "SV",
                        "name": "Save Pitcher",
                        "teamId": "SS",
                        "value": "20",
                    }
                ],
                "strikeouts": [
                    {
                        "rank": 1,
                        "playerId": "strikeouts",
                        "playerType": "pitcher",
                        "metricKey": "SO",
                        "name": "Strikeout Pitcher",
                        "teamId": "OB",
                        "value": "108",
                    }
                ],
            },
            "featured": {},
        }

    def get_leaderboard(self, season: int, metric: str):
        return []


class _UnexpectedRecordsCrawler:
    def get_overview(self, season: int):
        raise AssertionError("unsupported records season should not crawl")

    def get_leaderboard(self, season: int, metric: str):
        raise AssertionError("unsupported records season should not crawl")


class _UnsortedRecordsCrawler:
    def get_overview(self, season: int):
        return {
            "season": season,
            "leaders": {
                "avg": [
                    {
                        "rank": 29,
                        "playerId": "late",
                        "playerType": "hitter",
                        "metricKey": "AVG",
                        "name": "Late",
                        "teamId": "KT",
                        "value": ".272",
                    },
                    {
                        "rank": 1,
                        "playerId": "top",
                        "playerType": "hitter",
                        "metricKey": "AVG",
                        "name": "Top",
                        "teamId": "SSG",
                        "value": ".379",
                    },
                    {
                        "rank": 2,
                        "playerId": "second",
                        "playerType": "hitter",
                        "metricKey": "AVG",
                        "name": "Second",
                        "teamId": "LG",
                        "value": ".356",
                    },
                ],
                "hr": [],
                "ops": [
                    {
                        "rank": 2,
                        "playerId": "ops-second",
                        "playerType": "hitter",
                        "metricKey": "OPS",
                        "name": "Ops Second",
                        "teamId": "LG",
                        "value": "1.000",
                    },
                    {
                        "rank": 1,
                        "playerId": "ops-top",
                        "playerType": "hitter",
                        "metricKey": "OPS",
                        "name": "Ops Top",
                        "teamId": "KT",
                        "value": "1.100",
                    },
                ],
                "era": [],
            },
            "featured": {},
        }

    def get_leaderboard(self, season: int, metric: str):
        return [
            {
                "rank": 3,
                "playerId": "third",
                "playerType": "hitter",
                "metricKey": metric.upper(),
                "name": "Third",
                "teamId": "LG",
                "value": ".300",
            },
            {
                "rank": 1,
                "playerId": "first",
                "playerType": "hitter",
                "metricKey": metric.upper(),
                "name": "First",
                "teamId": "KT",
                "value": ".400",
            },
        ]


def test_build_ops_relative_leaders_from_ops_values_with_compatibility_key() -> None:
    leaders = [
        {
            "rank": 1,
            "playerId": "p1",
            "playerType": "hitter",
            "metricKey": "OPS",
            "name": "A",
            "teamId": "LG",
            "value": "1.000",
        },
        {
            "rank": 2,
            "playerId": "p2",
            "playerType": "hitter",
            "metricKey": "OPS",
            "name": "B",
            "teamId": "KT",
            "value": "0.800",
        },
    ]

    ops_relative_leaders = RecordsOverviewCrawler._build_ops_plus_leaders(leaders)

    assert len(ops_relative_leaders) == 2
    assert ops_relative_leaders[0]["name"] == "A"
    assert ops_relative_leaders[0]["value"] == "111"
    assert ops_relative_leaders[0]["metricKey"] == "OPSPLUS"
    assert ops_relative_leaders[1]["name"] == "B"
    assert ops_relative_leaders[1]["value"] == "89"
    assert (
        RecordsOverviewCrawler._headline_for_leader(ops_relative_leaders[0]) == "OPS 상대지수 111"
    )


def test_extract_player_link_accepts_active_and_retired_records() -> None:
    active = '<a href="/Record/Player/HitterDetail/Basic.aspx?playerId=77532">손아섭</a>'
    retired = '<a href="/Record/Retire/Pitcher.aspx?playerId=75620">윤석민</a>'

    assert RecordsOverviewCrawler._extract_player_link(active) == ("77532", False)
    assert RecordsOverviewCrawler._extract_player_link(retired) == ("75620", True)


def test_historical_leaderboard_snapshots_include_retired_top_leaders() -> None:
    root = Path(__file__).resolve().parents[1]
    snapshots = root / "data" / "snapshots" / "leaderboard"
    era_2011 = json.loads((snapshots / "2011_era.json").read_text(encoding="utf-8"))
    hr_2013 = json.loads((snapshots / "2013_hr.json").read_text(encoding="utf-8"))

    assert era_2011["payload"]["leaders"][0]["name"] == "윤석민"
    assert era_2011["payload"]["leaders"][0]["value"] == "2.45"
    assert era_2011["payload"]["leaders"][0]["isRetired"] is True
    assert hr_2013["payload"]["leaders"][0]["name"] == "박병호"
    assert hr_2013["payload"]["leaders"][0]["value"] == "37"
    assert hr_2013["payload"]["leaders"][0]["isRetired"] is True


def test_unsupported_2001_overview_does_not_reuse_current_rows_or_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    store.save(
        "records_overview",
        "2001",
        {
            "season": 2001,
            "leaders": {
                "avg": [
                    {
                        "rank": 1,
                        "playerId": "current",
                        "playerType": "hitter",
                        "metricKey": "AVG",
                        "name": "Current Season",
                        "teamId": "KT",
                        "value": ".400",
                    }
                ],
                "hr": [],
                "ops": [],
                "era": [],
            },
            "featured": {},
        },
    )
    service = RecordsOverviewService(
        crawler=_UnexpectedRecordsCrawler(),
        snapshot_store=store,
    )

    payload = service.get_overview(2001)

    assert payload == RecordsOverviewCrawler.empty_overview(2001)


def test_unsupported_2001_leaderboard_does_not_crawl() -> None:
    service = RecordsOverviewService(crawler=_UnexpectedRecordsCrawler())

    payload = service.get_leaderboard(2001, "avg")

    assert payload == {"season": 2001, "metric": "avg", "leaders": []}


def test_concurrent_current_overview_cache_miss_crawls_once(tmp_path) -> None:
    crawler = _BlockingOverviewCrawler()
    service = RecordsOverviewService(
        crawler=crawler,
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
    )
    season = current_kbo_year()

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        first = executor.submit(service.get_overview, season)
        assert crawler.first_call_started.wait(timeout=1)
        second = executor.submit(service.get_overview, season)
        duplicate_started = crawler.duplicate_call_started.wait(timeout=0.5)
        crawler.release.set()
        first_payload = first.result(timeout=2)
        second_payload = second.result(timeout=2)

    assert duplicate_started is False
    assert crawler.calls == 1
    assert first_payload == second_payload


def test_current_home_overview_uses_lightweight_crawler(tmp_path) -> None:
    crawler = _HomeOverviewCrawler()
    service = RecordsOverviewService(
        crawler=crawler,
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
    )

    payload = service.get_home_overview(current_kbo_year())

    assert crawler.home_overview_calls == 1
    assert crawler.overview_calls == 0
    assert payload["leaders"]["avg"][0]["rank"] == 1
    assert payload["leaders"]["ops"] == []
    assert payload["featured"]["todayPitcher"]["name"] == "ERA Pitcher"


def test_full_overview_reuses_valid_home_seed_for_missing_groups(tmp_path) -> None:
    season = current_kbo_year()
    home_payload = {
        "season": season,
        "leaders": {
            "avg": [{"rank": 1, "playerId": "avg", "value": ".400"}],
            "hr": [{"rank": 1, "playerId": "hr", "value": "20"}],
            "era": [{"rank": 1, "playerId": "era", "value": "2.00"}],
        },
        "featured": {},
    }

    class HomeSeedCrawler:
        def __init__(self) -> None:
            self.seed_calls = 0

        def get_overview(self, season: int):
            raise AssertionError("full crawler should not reload seeded home groups")

        def get_overview_from_home(self, season: int, seed):
            self.seed_calls += 1
            return {
                "season": season,
                "leaders": {
                    **seed["leaders"],
                    "ops": [{"rank": 1, "playerId": "ops", "value": "1.000"}],
                    "opsPlus": [{"rank": 1, "playerId": "ops-plus", "value": "100"}],
                    "wins": [{"rank": 1, "playerId": "wins", "value": "10"}],
                    "saves": [{"rank": 1, "playerId": "saves", "value": "5"}],
                    "strikeouts": [
                        {"rank": 1, "playerId": "strikeouts", "value": "100"}
                    ],
                },
                "featured": {},
            }

    crawler = HomeSeedCrawler()
    service = RecordsOverviewService(
        crawler=crawler,
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
    )
    service._home_overview_cache.set(season, home_payload)

    payload = service.get_overview(season)

    assert crawler.seed_calls == 1
    assert payload["leaders"]["avg"][0]["playerId"] == "avg"
    assert payload["leaders"]["strikeouts"][0]["playerId"] == "strikeouts"


def test_full_overview_does_not_use_partial_home_seed(tmp_path) -> None:
    season = current_kbo_year()

    class FullOnlyCrawler:
        def get_overview(self, season: int):
            return {
                "season": season,
                "leaders": {
                    metric: [{"rank": 1, "playerId": metric}]
                    for metric in (
                        "avg",
                        "hr",
                        "ops",
                        "opsPlus",
                        "era",
                        "wins",
                        "saves",
                        "strikeouts",
                    )
                },
                "featured": {},
            }

        def get_overview_from_home(self, season: int, seed):
            raise AssertionError("partial Home seed must not complete full overview")

    service = RecordsOverviewService(
        crawler=FullOnlyCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
    )
    service._home_overview_cache.set(
        season,
        {
            "season": season,
            "leaders": {
                "avg": [{"rank": 1, "playerId": "avg"}],
                "hr": [],
                "era": [{"rank": 1, "playerId": "era"}],
            },
            "featured": {},
        },
    )

    payload = service.get_overview(season)

    assert payload["leaders"]["hr"][0]["playerId"] == "hr"


def test_home_overview_crawls_only_home_record_metrics(monkeypatch) -> None:
    crawler = RecordsOverviewCrawler()
    calls = []

    def fetch_leaders(path, season, metric_key, player_type):
        del path
        calls.append(metric_key)
        return [
            {
                "rank": 1,
                "playerId": metric_key.lower(),
                "playerType": player_type,
                "metricKey": metric_key,
                "name": metric_key,
                "teamId": "LG",
                "value": "1",
            }
        ]

    monkeypatch.setattr(crawler, "_fetch_leaders", fetch_leaders)

    payload = crawler.get_home_overview(current_kbo_year())

    assert set(calls) == {"AVG", "HR", "ERA"}
    assert len(calls) == 3
    assert payload["leaders"]["ops"] == []
    assert payload["leaders"]["wins"] == []
    assert payload["leaders"]["saves"] == []


def test_home_overview_logs_page_timing_without_payload_data(
    monkeypatch,
    caplog,
) -> None:
    crawler = RecordsOverviewCrawler()

    monkeypatch.setattr(crawler, "_fetch_leaders", lambda *args, **kwargs: [])

    with caplog.at_level(
        logging.INFO,
        logger="kbo_fans_backend.crawlers.records_overview",
    ):
        crawler.get_home_overview(current_kbo_year())

    assert "records_overview_timing" in caplog.text
    assert "mode=home" in caplog.text
    assert "complete=True" in caplog.text
    assert "pageCount=3" in caplog.text
    assert "avgMs=" in caplog.text
    assert "hrMs=" in caplog.text
    assert "eraMs=" in caplog.text


def test_records_overview_logs_failure_timing_without_payload_data(
    monkeypatch,
    caplog,
) -> None:
    crawler = RecordsOverviewCrawler()

    def fail_fetch(*args, **kwargs):
        raise RuntimeError("records page unavailable")

    monkeypatch.setattr(crawler, "_fetch_leaders", fail_fetch)

    with caplog.at_level(
        logging.INFO,
        logger="kbo_fans_backend.crawlers.records_overview",
    ):
        with pytest.raises(RuntimeError, match="records page unavailable"):
            crawler.get_overview(current_kbo_year())

    assert "records_overview_timing" in caplog.text
    assert "mode=full" in caplog.text
    assert "complete=False" in caplog.text


def test_home_seed_overview_logs_page_timing_without_payload_data(
    monkeypatch,
    caplog,
) -> None:
    crawler = RecordsOverviewCrawler()
    home_payload = {
        "season": current_kbo_year(),
        "leaders": {"avg": [], "hr": [], "era": []},
    }

    monkeypatch.setattr(crawler, "_fetch_ops_leaders", lambda season: ([], []))
    monkeypatch.setattr(crawler, "_fetch_leaders", lambda *args, **kwargs: [])

    with caplog.at_level(
        logging.INFO,
        logger="kbo_fans_backend.crawlers.records_overview",
    ):
        crawler.get_overview_from_home(current_kbo_year(), home_payload)

    assert "records_overview_timing" in caplog.text
    assert "mode=home_seed" in caplog.text
    assert "complete=True" in caplog.text
    assert "pageCount=4" in caplog.text


def test_current_season_leader_fetch_uses_get_page_without_post(monkeypatch) -> None:
    crawler = RecordsOverviewCrawler()
    html = f'''
    <select name="{crawler._SEASON_FIELD}">
      <option value="2025">2025</option>
      <option selected="selected" value="{current_kbo_year()}">{current_kbo_year()}</option>
    </select>
    <table>
      <tr><th>순위</th><th>선수</th><th>팀</th><th>AVG</th></tr>
      <tr><td>1</td><td><a href="/Record/Player/HitterDetail/Basic.aspx?playerId=1">
        Leader</a></td><td>LG</td><td>.400</td></tr>
    </table>
    '''
    monkeypatch.setattr(crawler, "_get_text", lambda *args, **kwargs: html)

    def fail_post(*args, **kwargs):
        raise AssertionError("current season should not issue a season POST")

    monkeypatch.setattr(crawler, "_post_text", fail_post)

    leaders = crawler._fetch_leaders(
        crawler._HITTER_AVG_URL,
        current_kbo_year(),
        "AVG",
        "hitter",
    )

    assert leaders[0]["name"] == "Leader"
    assert leaders[0]["value"] == ".400"


def test_historical_season_leader_fetch_still_posts_selected_season(monkeypatch) -> None:
    crawler = RecordsOverviewCrawler()
    historical_season = current_kbo_year() - 1
    html = f'''
    <select name="{crawler._SEASON_FIELD}">
      <option selected="selected" value="{current_kbo_year()}">{current_kbo_year()}</option>
      <option value="{historical_season}">{historical_season}</option>
    </select>
    <table>
      <tr><th>순위</th><th>선수</th><th>팀</th><th>AVG</th></tr>
      <tr><td>1</td><td><a href="/Record/Player/HitterDetail/Basic.aspx?playerId=1">
        Leader</a></td><td>LG</td><td>.400</td></tr>
    </table>
    '''
    post_calls = []
    monkeypatch.setattr(crawler, "_get_text", lambda *args, **kwargs: html)

    def post_page(*args, **kwargs):
        post_calls.append(kwargs["data"][crawler._SEASON_FIELD])
        return html

    monkeypatch.setattr(crawler, "_post_text", post_page)

    leaders = crawler._fetch_leaders(
        crawler._HITTER_AVG_URL,
        historical_season,
        "AVG",
        "hitter",
    )

    assert post_calls == [str(historical_season)]
    assert leaders[0]["name"] == "Leader"


def test_overview_reuses_one_ops_page_for_ops_and_ops_plus(monkeypatch) -> None:
    crawler = RecordsOverviewCrawler()
    html = """
    <table>
      <tr><th>순위</th><th>선수</th><th>팀</th><th>AVG</th><th>HR</th>
      <th>OPS</th><th>ERA</th><th>W</th><th>SV</th><th>SO</th></tr>
      <tr><td>1</td><td><a href="/Record/Player/HitterDetail/Basic.aspx?playerId=1">Leader</a></td>
      <td>LG</td><td>.400</td><td>20</td><td>1.100</td><td>2.00</td>
      <td>10</td><td>5</td><td>100</td></tr>
    </table>
    """
    calls = []

    def fetch_page(path, season, *, breaker_key):
        del season, breaker_key
        calls.append(path)
        return html

    monkeypatch.setattr(crawler, "_fetch_season_page", fetch_page)

    payload = crawler.get_overview(current_kbo_year())

    assert calls.count(crawler._HITTER_OPS_URL) == 1
    assert payload["leaders"]["ops"][0]["value"] == "1.100"
    assert payload["leaders"]["opsPlus"][0]["value"] == "100"


def test_full_overview_starts_all_unique_pages_together(monkeypatch) -> None:
    crawler = RecordsOverviewCrawler()
    html = """
    <table>
      <tr><th>순위</th><th>선수</th><th>팀</th><th>AVG</th><th>HR</th>
      <th>OPS</th><th>ERA</th><th>W</th><th>SV</th><th>SO</th></tr>
      <tr><td>1</td><td><a href="/Record/Player/HitterDetail/Basic.aspx?playerId=1">Leader</a></td>
      <td>LG</td><td>.400</td><td>20</td><td>1.100</td><td>2.00</td>
      <td>10</td><td>5</td><td>100</td></tr>
    </table>
    """
    started = threading.Event()
    release = threading.Event()
    calls = []
    calls_lock = threading.Lock()

    def fetch_page(path, season, *, breaker_key):
        del season, breaker_key
        with calls_lock:
            calls.append(path)
            if len(calls) == 7:
                started.set()
        assert release.wait(timeout=2)
        return html

    monkeypatch.setattr(crawler, "_fetch_season_page", fetch_page)

    thread = threading.Thread(target=lambda: crawler.get_overview(current_kbo_year()))
    thread.start()
    try:
        assert started.wait(timeout=1)
    finally:
        release.set()
        thread.join(timeout=2)

    assert not thread.is_alive()
    assert len(calls) == 7


def test_full_overview_failure_does_not_wait_for_sibling_pages(monkeypatch) -> None:
    crawler = RecordsOverviewCrawler()
    html = "<table><tr><th>순위</th><th>선수</th><th>팀</th><th>AVG</th></tr></table>"
    started = threading.Event()
    release = threading.Event()
    calls = []
    calls_lock = threading.Lock()

    def fetch_page(path, season, *, breaker_key):
        del season, breaker_key
        with calls_lock:
            calls.append(path)
            if len(calls) == 7:
                started.set()
        if path == crawler._HITTER_AVG_URL:
            assert started.wait(timeout=1)
            raise RuntimeError("records page unavailable")
        assert release.wait(timeout=2)
        return html

    monkeypatch.setattr(crawler, "_fetch_season_page", fetch_page)

    errors = []

    def request() -> None:
        try:
            crawler.get_overview(current_kbo_year())
        except BaseException as error:
            errors.append(error)

    thread = threading.Thread(target=request)
    thread.start()
    assert started.wait(timeout=1)
    try:
        thread.join(timeout=0.2)
        assert not thread.is_alive()
    finally:
        release.set()
        thread.join(timeout=2)

    assert len(errors) == 1
    assert str(errors[0]) == "records page unavailable"


def test_full_overview_late_page_failure_does_not_wait_for_first_page(
    monkeypatch,
) -> None:
    crawler = RecordsOverviewCrawler()
    html = "<table><tr><th>순위</th><th>선수</th><th>팀</th><th>AVG</th></tr></table>"
    started = threading.Event()
    release = threading.Event()
    calls = []
    calls_lock = threading.Lock()

    def fetch_page(path, season, *, breaker_key):
        del season, breaker_key
        with calls_lock:
            calls.append(path)
            if len(calls) == 7:
                started.set()
        if path == crawler._PITCHER_STRIKEOUTS_URL:
            raise RuntimeError("strikeouts page unavailable")
        assert release.wait(timeout=2)
        return html

    monkeypatch.setattr(crawler, "_fetch_season_page", fetch_page)

    errors = []

    def request() -> None:
        try:
            crawler.get_overview(current_kbo_year())
        except BaseException as error:
            errors.append(error)

    thread = threading.Thread(target=request)
    thread.start()
    assert started.wait(timeout=1)
    try:
        thread.join(timeout=0.2)
        assert not thread.is_alive()
    finally:
        release.set()
        thread.join(timeout=2)

    assert len(errors) == 1
    assert str(errors[0]) == "strikeouts page unavailable"


def test_records_crawler_reuses_recent_page_for_leaderboard_transition(monkeypatch) -> None:
    crawler = RecordsOverviewCrawler()
    html = f'''
    <select name="{crawler._SEASON_FIELD}">
      <option selected="selected" value="{current_kbo_year()}">{current_kbo_year()}</option>
    </select>
    <table>
      <tr><th>순위</th><th>선수</th><th>팀</th><th>OPS</th></tr>
      <tr><td>1</td><td><a href="/Record/Player/HitterDetail/Basic.aspx?playerId=1">
        Leader</a></td><td>LG</td><td>1.100</td></tr>
    </table>
    '''
    get_calls = []
    monkeypatch.setattr(
        crawler,
        "_get_text",
        lambda *args, **kwargs: get_calls.append(args[0]) or html,
    )
    monkeypatch.setattr(
        crawler,
        "_post_text",
        lambda *args, **kwargs: (_ for _ in ()).throw(
            AssertionError("current selected page should not POST")
        ),
    )

    leaders = crawler._fetch_leaders(
        crawler._HITTER_OPS_URL,
        current_kbo_year(),
        "OPS",
        "hitter",
    )
    leaderboard = crawler._fetch_leaderboard(
        crawler._HITTER_OPS_URL,
        current_kbo_year(),
        "OPS",
        "hitter",
    )

    assert len(get_calls) == 1
    assert leaders[0]["value"] == "1.100"
    assert leaderboard[0]["value"] == "1.100"


def test_current_home_overview_does_not_mask_lightweight_failure(tmp_path) -> None:
    service = RecordsOverviewService(
        crawler=_FailingHomeOverviewCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
    )

    with pytest.raises(RuntimeError, match="home overview unavailable"):
        service.get_home_overview(current_kbo_year())


def test_concurrent_current_leaderboard_cache_miss_crawls_once(tmp_path) -> None:
    crawler = _BlockingLeaderboardCrawler()
    service = RecordsOverviewService(
        crawler=crawler,
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
    )
    season = current_kbo_year()

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        first = executor.submit(service.get_leaderboard, season, "avg")
        assert crawler.first_call_started.wait(timeout=1)
        second = executor.submit(service.get_leaderboard, season, "avg")
        duplicate_started = crawler.duplicate_call_started.wait(timeout=0.5)
        crawler.release.set()
        first_payload = first.result(timeout=2)
        second_payload = second.result(timeout=2)

    assert duplicate_started is False
    assert crawler.calls == 1
    assert first_payload == second_payload


def test_leaderboard_falls_back_to_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year() - 1
    expected = {
        "season": season,
        "metric": "avg",
        "leaders": [
            {
                "rank": 1,
                "playerId": "p1",
                "playerType": "hitter",
                "name": "A",
                "teamId": "LG",
                "value": ".400",
            }
        ],
    }
    store.save("leaderboard", f"{season}:avg", expected)

    service = RecordsOverviewService(
        crawler=_FailingRecordsCrawler(),
        snapshot_store=store,
    )

    assert service.get_leaderboard(season, "avg") == expected


def test_historical_overview_prefers_snapshot_before_crawler(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year() - 1
    store.save(
        "records_overview",
        str(season),
        {
            "season": season,
            "leaders": {
                "avg": [
                    {
                        "rank": 1,
                        "playerId": "snapshot",
                        "playerType": "hitter",
                        "metricKey": "AVG",
                        "name": "Snapshot",
                        "teamId": "LT",
                        "value": ".345",
                    }
                ],
                "hr": [],
                "ops": [],
                "era": [],
            },
            "featured": {},
        },
    )
    crawler = _TrackingFreshRecordsCrawler()
    service = RecordsOverviewService(crawler=crawler, snapshot_store=store)

    payload = service.get_overview(season)

    assert payload["leaders"]["avg"][0]["name"] == "Snapshot"
    assert crawler.overview_calls == 0


def test_historical_leaderboard_prefers_snapshot_before_crawler(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year() - 1
    store.save(
        "leaderboard",
        f"{season}:avg",
        {
            "season": season,
            "metric": "avg",
            "leaders": [
                {
                    "rank": 1,
                    "playerId": "snapshot",
                    "playerType": "hitter",
                    "metricKey": "AVG",
                    "name": "Snapshot",
                    "teamId": "LT",
                    "value": ".345",
                }
            ],
        },
    )
    crawler = _TrackingFreshRecordsCrawler()
    service = RecordsOverviewService(crawler=crawler, snapshot_store=store)

    payload = service.get_leaderboard(season, "avg")

    assert payload["leaders"][0]["name"] == "Snapshot"
    assert crawler.leaderboard_calls == 0


def test_historical_leaderboard_ignores_snapshot_missing_rank_one(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year() - 1
    store.save(
        "leaderboard",
        f"{season}:avg",
        {
            "season": season,
            "metric": "avg",
            "leaders": [
                {
                    "rank": 2,
                    "playerId": "stale-second",
                    "playerType": "hitter",
                    "metricKey": "AVG",
                    "name": "Stale Second",
                    "teamId": "LT",
                    "value": ".345",
                }
            ],
        },
    )
    crawler = _TrackingFreshRecordsCrawler()
    service = RecordsOverviewService(crawler=crawler, snapshot_store=store)

    payload = service.get_leaderboard(season, "avg")

    assert payload["leaders"][0]["name"] == "Fresh"
    assert crawler.leaderboard_calls == 1


def test_historical_overview_ignores_malformed_root_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year() - 1
    store.save("records_overview", str(season), [])

    service = RecordsOverviewService(
        crawler=_FailingRecordsCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError, match="overview unavailable"):
        service.get_overview(season)


def test_historical_leaderboard_ignores_malformed_root_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year() - 1
    store.save("leaderboard", f"{season}:avg", [])

    service = RecordsOverviewService(
        crawler=_FailingRecordsCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError, match="leaderboard unavailable"):
        service.get_leaderboard(season, "avg")


def test_historical_records_snapshots_require_exact_identity(tmp_path) -> None:
    season = current_kbo_year() - 1
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    leaders = {
        "avg": [
            {
                "rank": 1,
                "playerId": "wrong-snapshot",
                "playerType": "hitter",
                "metricKey": "AVG",
                "name": "Wrong Snapshot",
                "teamId": "LG",
                "value": ".999",
            }
        ]
    }
    store.save(
        "records_overview",
        str(season),
        {"season": season - 1, "leaders": leaders},
    )
    store.save(
        "leaderboard",
        f"{season}:avg",
        {"season": season, "leaders": leaders["avg"]},
    )
    service = RecordsOverviewService(
        crawler=_FailingRecordsCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError, match="overview unavailable"):
        service.get_overview(season)
    with pytest.raises(RuntimeError, match="leaderboard unavailable"):
        service.get_leaderboard(season, "avg")


def test_leaderboard_does_not_cache_fresh_payload_missing_rank_one(tmp_path) -> None:
    crawler = _RecoveringLeaderboardCrawler()
    service = RecordsOverviewService(
        crawler=crawler,
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
    )

    first = service.get_leaderboard(2026, "avg")
    second = service.get_leaderboard(2026, "avg")

    assert first["leaders"][0]["rank"] == 2
    assert second["leaders"][0]["rank"] == 1
    assert crawler.leaderboard_calls == 2
    assert service.snapshot_store.load_payload("leaderboard", "2026:avg") == second


def test_current_leaderboard_rejects_old_snapshot_on_failure(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year()
    _write_snapshot_record(
        tmp_path,
        "leaderboard",
        f"{season}:avg",
        {
            "season": season,
            "metric": "avg",
            "leaders": [{"rank": 1, "name": "Stale", "teamId": "KT", "value": ".100"}],
        },
    )
    service = RecordsOverviewService(
        crawler=_FailingRecordsCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError):
        service.get_leaderboard(season, "avg")


def test_current_leaderboard_rejects_fresh_snapshot_on_failure(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year()
    store.save(
        "leaderboard",
        f"{season}:avg",
        {
            "season": season,
            "metric": "avg",
            "leaders": [{"rank": 1, "name": "Fresh Snapshot", "teamId": "KT", "value": ".400"}],
        },
    )
    service = RecordsOverviewService(
        crawler=_FailingRecordsCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError):
        service.get_leaderboard(season, "avg")


def test_leaderboard_prefers_fresh_crawler_over_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    store.save(
        "leaderboard",
        "2026:avg",
        {
            "season": 2026,
            "metric": "avg",
            "leaders": [
                {
                    "rank": 1,
                    "playerId": "stale",
                    "playerType": "hitter",
                    "name": "Stale",
                    "teamId": "KT",
                    "value": ".100",
                }
            ],
        },
    )

    service = RecordsOverviewService(
        crawler=_FreshRecordsCrawler(),
        snapshot_store=store,
    )

    assert service.get_leaderboard(2026, "avg")["leaders"][0]["name"] == "Fresh"


def test_overview_prefers_fresh_crawler_over_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    store.save(
        "records_overview",
        "2026",
        {
            "season": 2026,
            "leaders": {
                "avg": [
                    {
                        "rank": 1,
                        "playerId": "stale",
                        "playerType": "hitter",
                        "metricKey": "AVG",
                        "name": "Stale",
                        "teamId": "KT",
                        "value": ".100",
                    }
                ],
                "hr": [],
                "ops": [],
                "era": [],
            },
            "featured": {},
        },
    )

    service = RecordsOverviewService(
        crawler=_FreshRecordsCrawler(),
        snapshot_store=store,
    )

    assert service.get_overview(2026)["leaders"]["avg"][0]["name"] == "Fresh"


def test_overview_normalizes_leader_order_before_featured(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    service = RecordsOverviewService(
        crawler=_UnsortedRecordsCrawler(),
        snapshot_store=store,
    )

    payload = service.get_overview(2026)

    assert [leader["rank"] for leader in payload["leaders"]["avg"]] == [1, 2, 29]
    assert payload["featured"]["todayHitter"]["name"] == "Top"
    assert [leader["rank"] for leader in payload["leaders"]["ops"]] == [1, 2]


def test_overview_keeps_pitching_leaders_and_pitcher_featured(tmp_path) -> None:
    service = RecordsOverviewService(
        crawler=_PitchingFeaturedRecordsCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
    )

    payload = service.get_overview(2026)

    assert payload["leaders"]["wins"][0]["name"] == "Win Pitcher"
    assert payload["leaders"]["saves"][0]["metricKey"] == "SV"
    assert payload["leaders"]["strikeouts"][0]["playerType"] == "pitcher"
    assert payload["featured"]["todayPitcher"]["playerType"] == "pitcher"
    assert payload["featured"]["monthPitcher"]["name"] == "Strikeout Pitcher"
    assert payload["featured"]["monthPitcher"]["playerType"] == "pitcher"


def test_leaderboard_normalizes_leader_order(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    service = RecordsOverviewService(
        crawler=_UnsortedRecordsCrawler(),
        snapshot_store=store,
    )

    payload = service.get_leaderboard(2026, "avg")

    assert [leader["rank"] for leader in payload["leaders"]] == [1, 3]
    assert payload["leaders"][0]["name"] == "First"


def test_overview_snapshot_is_normalized_with_ops_plus(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year() - 1
    store.save(
        "records_overview",
        str(season),
        {
            "season": season,
            "leaders": {
                "ops": [
                    {
                        "rank": 1,
                        "playerId": "p1",
                        "playerType": "hitter",
                        "metricKey": "OPS",
                        "name": "A",
                        "teamId": "LG",
                        "value": "1.000",
                    },
                    {
                        "rank": 2,
                        "playerId": "p2",
                        "playerType": "hitter",
                        "metricKey": "OPS",
                        "name": "B",
                        "teamId": "KT",
                        "value": "0.800",
                    },
                ]
            },
            "featured": {},
        },
    )

    service = RecordsOverviewService(
        crawler=_FailingRecordsCrawler(),
        snapshot_store=store,
    )

    payload = service.get_overview(season)

    assert [leader["value"] for leader in payload["leaders"]["opsPlus"]] == [
        "111",
        "89",
    ]


def test_current_overview_rejects_old_snapshot_on_failure(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year()
    _write_snapshot_record(
        tmp_path,
        "records_overview",
        str(season),
        {
            "season": season,
            "leaders": {
                "avg": [
                    {
                        "rank": 1,
                        "playerId": "stale",
                        "playerType": "hitter",
                        "metricKey": "AVG",
                        "name": "Stale",
                        "teamId": "KT",
                        "value": ".100",
                    }
                ],
                "hr": [],
                "ops": [],
                "era": [],
            },
            "featured": {},
        },
    )
    service = RecordsOverviewService(
        crawler=_FailingRecordsCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError):
        service.get_overview(season)


def test_current_overview_rejects_fresh_snapshot_on_failure(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = current_kbo_year()
    store.save(
        "records_overview",
        str(season),
        {
            "season": season,
            "leaders": {
                "avg": [
                    {
                        "rank": 1,
                        "playerId": "fresh",
                        "playerType": "hitter",
                        "metricKey": "AVG",
                        "name": "Fresh Snapshot",
                        "teamId": "KT",
                        "value": ".400",
                    }
                ],
                "hr": [],
                "ops": [],
                "era": [],
            },
            "featured": {},
        },
    )
    service = RecordsOverviewService(
        crawler=_FailingRecordsCrawler(),
        snapshot_store=store,
    )

    with pytest.raises(RuntimeError):
        service.get_overview(season)


def test_overview_featured_images_use_2022_folder_for_old_seasons(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    store.save(
        "records_overview",
        "2013",
        {
            "season": 2013,
            "leaders": {
                "avg": [
                    {
                        "rank": 1,
                        "playerId": "77532",
                        "playerType": "hitter",
                        "metricKey": "AVG",
                        "name": "손아섭",
                        "teamId": "LT",
                        "value": "0.345",
                    }
                ],
                "hr": [],
                "ops": [],
                "era": [],
            },
            "featured": {},
        },
    )

    service = RecordsOverviewService(
        crawler=_FailingRecordsCrawler(),
        snapshot_store=store,
    )

    payload = service.get_overview(2013)

    assert payload["featured"]["todayHitter"]["imageUrl"].endswith("/2022/77532.jpg")


def _write_snapshot_record(tmp_path, namespace: str, key: str, payload: dict) -> None:
    path = tmp_path / namespace / f"{key}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "savedAt": "2000-01-01T00:00:00+00:00",
                "payload": payload,
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
