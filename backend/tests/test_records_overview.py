from kbo_fans_backend.crawlers.records_overview import RecordsOverviewCrawler
from kbo_fans_backend.services.records_overview import RecordsOverviewService
from kbo_fans_backend.storage import JsonSnapshotStore


class _FailingRecordsCrawler:
    def get_overview(self, season: int):
        raise RuntimeError("overview unavailable")

    def get_leaderboard(self, season: int, metric: str):
        raise RuntimeError("leaderboard unavailable")


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
