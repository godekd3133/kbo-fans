import json

from kbo_fans_backend.crawlers.boxscore import BoxscoreCrawler


class _PayloadBoxscoreCrawler(BoxscoreCrawler):
    def __init__(self, payload):
        super().__init__()
        self.payload = payload

    def _post_json(self, *args, **kwargs):
        return self.payload


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
                    [(["3", "지", "강백호"], ["5", "4", "2", "2", "1", "0", "1", "3", "0", "0", "1", "1", "1", "0"])],
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
