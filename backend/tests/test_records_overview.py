import json
from datetime import datetime, timezone
from pathlib import Path

import pytest

from kbo_fans_backend.crawlers.records_overview import RecordsOverviewCrawler
from kbo_fans_backend.services.records_overview import RecordsOverviewService
from kbo_fans_backend.storage import JsonSnapshotStore


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


def test_build_ops_plus_leaders_from_ops_values() -> None:
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

    ops_plus_leaders = RecordsOverviewCrawler._build_ops_plus_leaders(leaders)

    assert len(ops_plus_leaders) == 2
    assert ops_plus_leaders[0]["name"] == "A"
    assert ops_plus_leaders[0]["value"] == "111"
    assert ops_plus_leaders[1]["name"] == "B"
    assert ops_plus_leaders[1]["value"] == "89"


def test_extract_player_link_accepts_active_and_retired_records() -> None:
    active = (
        '<a href="/Record/Player/HitterDetail/Basic.aspx?playerId=77532">'
        "손아섭</a>"
    )
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


def test_leaderboard_falls_back_to_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = datetime.now(timezone.utc).year - 1
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
    season = datetime.now(timezone.utc).year - 1
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
    season = datetime.now(timezone.utc).year - 1
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


def test_current_leaderboard_rejects_old_snapshot_on_failure(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = datetime.now(timezone.utc).year
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
    season = datetime.now(timezone.utc).year
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
    season = datetime.now(timezone.utc).year - 1
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
    season = datetime.now(timezone.utc).year
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
    season = datetime.now(timezone.utc).year
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
