from kbo_fans_backend.crawlers.relay import RelayCrawler


def test_parse_current_at_bat_from_live_text_view() -> None:
    html = """
    <div class="playerBox awayBox">
      <div class="player-info-wrap">
        <strong class="who">롯데<br><span class="no">No.34 김원중</span><span>(우투)</span></strong>
        <p class="today"><span>15투구 | 6B | 9S </span></p>
      </div>
    </div>
    <div class="playerBox homeBox">
      <div class="player-info-wrap">
        <strong class="who">삼성<br><span class="no">No.58 김지찬</span><span>(좌타)</span></strong>
        <p class="today"><span>땅볼|4구|2루타|</span></p>
      </div>
    </div>
    <p class="present">
      <span class="date">2026-03-29 [경기종료]</span>
      <span class="base">
        <strong>9회 말</strong>
        <img id="imgThisGameBase" src="//example.com/ground_base2.png" alt="주자">
        <strong>1-1 3out</strong>
      </span>
    </p>
    <div class="playerName">
      <ul>
        <li class="pitcher">김원중</li>
        <li class="supervision">김지찬</li>
        <li class="typing2">박세혁</li>
      </ul>
    </div>
    """

    current_at_bat = RelayCrawler()._parse_current_at_bat(html)

    assert current_at_bat == {
        "batter": {"name": "김지찬", "number": 58, "hand": "좌타", "recent": "땅볼|4구|2루타|"},
        "pitcher": {"name": "김원중", "number": 34, "hand": "우투", "pitchCount": 15},
        "ballCount": {"balls": 1, "strikes": 1, "outs": 3},
        "inningText": "9회 말",
        "baseState": "주자2루",
    }


def test_parse_current_at_bat_derives_base_state_from_runner_names() -> None:
    html = """
    <div class="playerBox awayBox">
      <div class="player-info-wrap">
        <strong class="who"><span class="no">No.34 김원중</span><span>(우투)</span></strong>
      </div>
    </div>
    <div class="playerBox homeBox">
      <div class="player-info-wrap">
        <strong class="who"><span class="no">No.58 김지찬</span><span>(좌타)</span></strong>
      </div>
    </div>
    <p class="present">
      <span class="base">
        <strong>7회 초</strong>
        <img id="imgThisGameBase" src="//example.com/current.png" alt="주자">
        <strong>2-1 1out</strong>
      </span>
    </p>
    <div id="txtBase1">홍창기</div>
    <div id="txtBase3">오스틴</div>
    <div class="playerName">
      <ul>
        <li class="pitcher">김원중</li>
        <li class="supervision">김지찬</li>
      </ul>
    </div>
    """

    current_at_bat = RelayCrawler()._parse_current_at_bat(html)

    assert current_at_bat is not None
    assert current_at_bat["baseState"] == "주자1,3루"


def test_assert_valid_relay_response_rejects_error_page() -> None:
    html = "<html><head><title>에러 | KBO홈페이지</title></head><body></body></html>"

    try:
        RelayCrawler._assert_valid_relay_response(html, "LiveTextView2")
    except RuntimeError as exc:
        assert str(exc) == "LiveTextView2 returned KBO error page."
    else:
        raise AssertionError("RuntimeError was not raised")


def test_assert_valid_relay_response_rejects_unexpected_markup() -> None:
    html = "<html><body><div>unexpected</div></body></html>"

    try:
        RelayCrawler._assert_valid_relay_response(html, "LiveTextView2")
    except RuntimeError as exc:
        assert str(exc) == "LiveTextView2 did not contain expected relay markup."
    else:
        raise AssertionError("RuntimeError was not raised")
