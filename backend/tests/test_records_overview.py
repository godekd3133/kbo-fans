import json
from datetime import datetime, timezone

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


def test_leaderboard_falls_back_to_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    season = datetime.now(timezone.utc).year
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


def test_overview_snapshot_is_normalized_with_ops_plus(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    store.save(
        "records_overview",
        "2026",
        {
            "season": 2026,
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

    payload = service.get_overview(2026)

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
