import json

from kbo_fans_backend.crawlers.boxscore import BoxscoreCrawler


class _PayloadBoxscoreCrawler(BoxscoreCrawler):
    def __init__(self, payload):
        super().__init__()
        self.payload = payload

    def _post_json(self, *args, **kwargs):
        return self.payload


class _RoutePayloadBoxscoreCrawler(BoxscoreCrawler):
    def __init__(self, boxscore_payload, main_payload):
        super().__init__()
        self.boxscore_payload = boxscore_payload
        self.main_payload = main_payload

    def _post_json(self, url, *args, **kwargs):
        if "GetKboGameList" in url:
            return self.main_payload
        return self.boxscore_payload


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


def _hitter_payload(rows):
    return {
        "table1": json.dumps({"rows": [_row(left) for left, _ in rows]}),
        "table3": json.dumps({"rows": [_row(right) for _, right in rows]}),
    }


def _pitcher_payload(rows):
    return {"table": json.dumps({"rows": [_row(row) for row in rows]})}


def _pitcher_row(name: str, innings: str):
    cells = [""] * 16
    cells[0] = name
    cells[2] = "-"
    cells[6] = innings
    cells[10] = "0"
    cells[12] = "0"
    cells[13] = "0"
    cells[15] = "0"
    return cells


def _row(cells):
    return {"row": [{"Text": cell} for cell in cells]}
