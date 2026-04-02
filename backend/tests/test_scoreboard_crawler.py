from kbo_fans_backend.crawlers.scoreboard import ScoreboardCrawler


class _StubResponse:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self) -> None:
        return None

    def json(self):
        return self._payload


def test_get_game_scoreboard_handles_scheduled_payload_without_tables() -> None:
    crawler = ScoreboardCrawler()
    crawler.session.request = lambda *args, **kwargs: _StubResponse(
        {
            "S_NM": "잠실",
            "CROWD_CN": None,
            "START_TM": "18:30",
            "AWAY_ID": "HT",
            "FULL_AWAY_NM": "KIA 타이거즈",
            "AWAY_NM": "KIA",
            "A_INITIAL_LK": "//example.com/away.png",
            "T_SCORE_CN": None,
            "HOME_ID": "LG",
            "FULL_HOME_NM": "LG 트윈스",
            "HOME_NM": "LG",
            "H_INITIAL_LK": "//example.com/home.png",
            "B_SCORE_CN": None,
            "END_TM": None,
            "msg": "",
            "code": "1",
        }
    )

    result = crawler.get_game_scoreboard("20260331HTLG0")

    assert result["startTime"] == "18:30"
    assert result["away"]["teamId"] == "HT"
    assert result["home"]["teamId"] == "LG"
    assert result["away"]["scores"] == [None] * 9
    assert result["home"]["scores"] == [None] * 9
    assert result["away"]["hits"] is None
    assert result["home"]["errors"] is None


def test_parse_view1_scoreboard_detail_extracts_totals() -> None:
    crawler = ScoreboardCrawler()

    result = crawler._parse_view1_scoreboard_detail(
        """
        <table id="tblScoreBoard2">
          <tbody>
            <tr><td>0</td><td>1</td><td>2</td></tr>
            <tr><td>0</td><td>0</td><td>1</td></tr>
          </tbody>
        </table>
        <table id="tblScoreBoard3">
          <tbody>
            <tr><td>두산</td><td>10</td><td>0</td><td>6</td></tr>
            <tr><td>삼성</td><td>4</td><td>0</td><td>1</td></tr>
          </tbody>
        </table>
        """
    )

    assert result is not None
    assert result["awayScores"] == [0, 1, 2]
    assert result["homeScores"] == [0, 0, 1]
    assert result["awayTotals"] == {"hits": 10, "errors": 0, "balls": 6}
    assert result["homeTotals"] == {"hits": 4, "errors": 0, "balls": 1}
