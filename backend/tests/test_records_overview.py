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


def test_leaderboard_falls_back_to_snapshot(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    expected = {
        "season": 2026,
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
    store.save("leaderboard", "2026:avg", expected)

    service = RecordsOverviewService(
        crawler=_FailingRecordsCrawler(),
        snapshot_store=store,
    )

    assert service.get_leaderboard(2026, "avg") == expected


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
