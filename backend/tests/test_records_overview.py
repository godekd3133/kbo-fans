from kbo_fans_backend.crawlers.records_overview import RecordsOverviewCrawler


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
