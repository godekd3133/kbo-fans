import json

from kbo_fans_backend.crawlers.boxscore import BoxscoreCrawler


class _PayloadBoxscoreCrawler(BoxscoreCrawler):
    def __init__(self, payload):
        super().__init__()
        self.payload = payload

    def _post_json(self, *args, **kwargs):
        return self.payload


class _RoutePayloadBoxscoreCrawler(BoxscoreCrawler):
    def __init__(self, boxscore_payload, main_payload, relay_payload=None):
        super().__init__()
        self.boxscore_payload = boxscore_payload
        self.main_payload = main_payload
        self.relay_crawler = _StubRelayCrawler(relay_payload)

    def _post_json(self, url, *args, **kwargs):
        if "GetKboGameList" in url:
            return self.main_payload
        return self.boxscore_payload


class _StubRelayCrawler:
    def __init__(self, relay_payload):
        self.relay_payload = relay_payload

    def get_relay(self, game_id: str):
        if self.relay_payload is None:
            raise RuntimeError("relay unavailable")
        return self.relay_payload


def test_boxscore_crawler_marks_pitcher_placeholder_only_payload_unofficial() -> None:
    crawler = _PayloadBoxscoreCrawler(
        {
            "arrHitter": [
                _hitter_payload([]),
                _hitter_payload([]),
            ],
            "arrPitcher": [
                _pitcher_payload([_pitcher_row(name="선발투수", innings="0.0")]),
                _pitcher_payload([_pitcher_row(name="상대투수", innings="")]),
            ],
        }
    )

    payload = crawler.get_boxscore("20260613KTLG0")

    assert payload["officialAvailable"] is False
    assert payload["away"]["batters"] == []
    assert payload["away"]["pitchers"] == []
    assert payload["home"]["pitchers"] == []


def test_boxscore_crawler_returns_live_context_when_official_endpoint_empty() -> None:
    crawler = _RoutePayloadBoxscoreCrawler(
        boxscore_payload={"arrHitter": [], "arrPitcher": []},
        main_payload={
            "game": [
                {
                    "G_ID": "20260620OBLG0",
                    "GAME_STATE_SC": "2",
                    "GAME_INN_NO": "3",
                    "GAME_TB_SC": "T",
                    "GAME_TB_SC_NM": "초",
                    "T_P_NM": "양석환",
                    "B_P_NM": "임찬규",
                    "T_PIT_P_NM": "곽빈",
                    "B_PIT_P_NM": "임찬규",
                }
            ]
        },
    )

    payload = crawler.get_boxscore("20260620OBLG0")

    assert payload["officialAvailable"] is False
    assert payload["liveContextAvailable"] is True
    assert payload["source"] == "live_context"
    assert payload["away"]["batters"][0]["name"] == "양석환"
    assert payload["away"]["batters"][0]["contextLabel"] == "3회초 현재 타자"
    assert payload["away"]["pitchers"][0]["name"] == "곽빈"
    assert payload["away"]["pitchers"][0]["liveContext"] is True
    assert payload["home"]["pitchers"][0]["name"] == "임찬규"
    assert payload["home"]["pitchers"][0]["decision"] == "LIVE"


def test_boxscore_crawler_enriches_live_context_with_relay_today_batting_line() -> None:
    crawler = _RoutePayloadBoxscoreCrawler(
        boxscore_payload={"arrHitter": [], "arrPitcher": []},
        main_payload={
            "game": [
                {
                    "G_ID": "20260620OBLG0",
                    "GAME_STATE_SC": "2",
                    "GAME_INN_NO": "3",
                    "GAME_TB_SC": "T",
                    "GAME_TB_SC_NM": "초",
                    "T_P_NM": "양석환",
                    "B_P_NM": "임찬규",
                    "T_PIT_P_NM": "곽빈",
                    "B_PIT_P_NM": "임찬규",
                }
            ]
        },
        relay_payload={
            "gameId": "20260620OBLG0",
            "currentAtBat": {
                "batter": {
                    "name": "양석환",
                    "todayAtBats": 2,
                    "todayHits": 1,
                },
                "pitcher": {"name": "임찬규"},
                "inningText": "3회초",
            },
            "relayItems": [],
        },
    )

    payload = crawler.get_boxscore("20260620OBLG0")

    assert payload["source"] == "live_context"
    assert payload["away"]["batters"][0]["name"] == "양석환"
    assert payload["away"]["batters"][0]["atBats"] == 2
    assert payload["away"]["batters"][0]["hits"] == 1
    assert payload["away"]["batters"][0]["liveStatsAvailable"] is True


def test_boxscore_crawler_keeps_zero_value_batter_rows_official() -> None:
    crawler = _PayloadBoxscoreCrawler(
        {
            "arrHitter": [
                _hitter_payload([(["1", "중", "타자"], ["0", "0", "0", "0"])]),
                _hitter_payload([]),
            ],
            "arrPitcher": [
                _pitcher_payload([]),
                _pitcher_payload([]),
            ],
        }
    )

    payload = crawler.get_boxscore("20260613KTLG0")

    assert payload["officialAvailable"] is True
    assert payload["away"]["batters"][0]["name"] == "타자"
    assert payload["away"]["batters"][0]["atBats"] == 0
    assert payload["away"]["pitchers"] == []


def test_boxscore_crawler_parses_optional_hitter_and_pitcher_stats() -> None:
    crawler = _PayloadBoxscoreCrawler(
        {
            "arrHitter": [
                _hitter_payload(
                    [
                        (
                            ["3", "지", "강백호"],
                            [
                                "5",
                                "4",
                                "2",
                                "2",
                                "1",
                                "0",
                                "1",
                                "3",
                                "0",
                                "0",
                                "1",
                                "1",
                                "1",
                                "0",
                            ],
                        )
                    ],
                    headers=[
                        "타석",
                        "타수",
                        "득점",
                        "안타",
                        "2루타",
                        "3루타",
                        "홈런",
                        "타점",
                        "도루",
                        "도실",
                        "볼넷",
                        "사구",
                        "삼진",
                        "병살",
                    ],
                ),
                _hitter_payload([]),
            ],
            "arrPitcher": [
                _pitcher_payload(
                    [_pitcher_row(name="김영현", innings="2.0", pitch_count="34", runs="1")],
                    headers=[
                        "선수명",
                        "등판",
                        "결과",
                        "승",
                        "패",
                        "세",
                        "이닝",
                        "타자",
                        "투구수",
                        "타수",
                        "피안타",
                        "홈런",
                        "4사구",
                        "삼진",
                        "실점",
                        "자책",
                    ],
                ),
                _pitcher_payload([]),
            ],
        }
    )

    payload = crawler.get_boxscore("20260613KTLG0")

    batter = payload["away"]["batters"][0]
    assert batter["plateAppearances"] == 5
    assert batter["atBats"] == 4
    assert batter["runs"] == 2
    assert batter["hits"] == 2
    assert batter["doubles"] == 1
    assert batter["triples"] == 0
    assert batter["homeRuns"] == 1
    assert batter["rbi"] == 3
    assert batter["walks"] == 1
    assert batter["hitByPitch"] == 1
    assert batter["strikeouts"] == 1

    pitcher = payload["away"]["pitchers"][0]
    assert pitcher["name"] == "김영현"
    assert pitcher["pitchCount"] == 34
    assert pitcher["runs"] == 1


def test_boxscore_crawler_totals_innings_follow_reordered_header() -> None:
    crawler = _PayloadBoxscoreCrawler(
        {
            "arrHitter": [_hitter_payload([]), _hitter_payload([])],
            "arrPitcher": [
                _pitcher_payload(
                    [["김영현", "1.2", "2", "3", "1", "1", "-", "25", "1"]],
                    headers=[
                        "선수명",
                        "이닝",
                        "피안타",
                        "삼진",
                        "4사구",
                        "자책",
                        "결과",
                        "투구수",
                        "실점",
                    ],
                ),
                _pitcher_payload([]),
            ],
        }
    )

    payload = crawler.get_boxscore("20260613KTLG0")

    assert payload["away"]["pitchers"][0]["innings"] == "1.2"
    assert payload["away"]["totals"]["pitching"]["innings"] == "1.2"


def _hitter_payload(rows, headers=None):
    return {
        "table1": json.dumps({"rows": [_row(left) for left, _ in rows]}),
        "table3": json.dumps(
            {
                "headers": [_row(headers)] if headers else [],
                "rows": [_row(right) for _, right in rows],
            }
        ),
    }


def _pitcher_payload(rows, headers=None):
    return {
        "table": json.dumps(
            {
                "headers": [_row(headers)] if headers else [],
                "rows": [_row(row) for row in rows],
            }
        )
    }


def _pitcher_row(name: str, innings: str, pitch_count: str = "0", runs: str = "0"):
    cells = [""] * 16
    cells[0] = name
    cells[2] = "-"
    cells[6] = innings
    cells[8] = pitch_count
    cells[10] = "0"
    cells[12] = "0"
    cells[13] = "0"
    cells[14] = runs
    cells[15] = "0"
    return cells


def _row(cells):
    return {"row": [{"Text": cell} for cell in cells]}
