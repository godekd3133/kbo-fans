import threading
import time
from concurrent.futures import ThreadPoolExecutor

import pytest

from kbo_fans_backend.crawlers.relay import RelayCrawler
from kbo_fans_backend.utils.resilience import UpstreamBusyError


def test_parse_current_at_bat_from_live_text_view() -> None:
    html = """
    <div class="playerBox awayBox">
      <div class="player-info-wrap">
        <span class="player-img"><img class="pic" src="//img.test/pitcher.jpg"></span>
        <strong class="who">롯데<br><span class="no">No.34 김원중</span><span>(우투)</span></strong>
        <p class="today"><span>15투구 | 6B | 9S </span></p>
      </div>
    </div>
    <div class="playerBox homeBox">
      <div class="player-info-wrap">
        <span class="player-img"><img class="pic" src="/batter.jpg"></span>
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
        "batter": {
            "name": "김지찬",
            "number": 58,
            "hand": "좌타",
            "recent": "땅볼|4구|2루타|",
            "average": "",
            "todayAtBats": 2,
            "todayHits": 1,
            "imageUrl": "https://www.koreabaseball.com/batter.jpg",
        },
        "pitcher": {
            "name": "김원중",
            "number": 34,
            "hand": "우투",
            "pitchCount": 15,
            "era": "",
            "imageUrl": "https://img.test/pitcher.jpg",
        },
        "ballCount": {"balls": 1, "strikes": 1, "outs": 3},
        "inningText": "9회 말",
        "baseState": "주자2루",
    }


def test_parse_current_at_bat_uses_top_half_player_boxes_and_stats() -> None:
    html = """
    <div class="playerBox awayBox">
      <div class="batter">
        <div class="player-info-wrap">
        <strong class="who">
          삼성<br><span class="no">No.61 디아즈</span><span>(좌타)</span>
        </strong>
          <p class="today"><span>땅볼|4구|2루타|</span></p>
        </div>
        <table>
          <thead><tr><th>2026</th><th>타수</th><th>안타</th><th>타율</th><th>타점</th></tr></thead>
          <tbody><tr><th>시즌</th><td>100</td><td>24</td><td>0.240</td><td>31</td></tr></tbody>
        </table>
      </div>
    </div>
    <div class="playerBox homeBox">
      <div class="pitcher">
        <div class="player-info-wrap">
        <strong class="who">
          한화<br><span class="no">No.68 박준영</span><span>(우투)</span>
        </strong>
          <p class="today"><span>38투구 | 13B | 25S</span></p>
        </div>
        <table>
          <thead><tr><th>2026</th><th>ERA</th><th>경기</th></tr></thead>
          <tbody><tr><th>시즌</th><td>4.13</td><td>7</td></tr></tbody>
        </table>
      </div>
    </div>
    <p class="present">
      <span class="base">
        <strong>2회 초</strong>
        <img id="imgThisGameBase" src="//example.com/ground_base2.png" alt="주자">
        <strong>1-2 2out</strong>
      </span>
    </p>
    <div class="playerName">
      <ul>
        <li class="pitcher">박준영</li>
        <li class="supervision2">디아즈</li>
      </ul>
    </div>
    """

    current_at_bat = RelayCrawler()._parse_current_at_bat(html)

    assert current_at_bat == {
        "batter": {
            "name": "디아즈",
            "number": 61,
            "hand": "좌타",
            "recent": "땅볼|4구|2루타|",
            "average": "0.245",
            "todayAtBats": 2,
            "todayHits": 1,
            "imageUrl": "",
        },
        "pitcher": {
            "name": "박준영",
            "number": 68,
            "hand": "우투",
            "pitchCount": 38,
            "era": "4.13",
            "imageUrl": "",
        },
        "ballCount": {"balls": 1, "strikes": 2, "outs": 2},
        "inningText": "2회 초",
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


def test_classify_event_marks_passed_ball_and_preserves_scoring() -> None:
    crawler = RelayCrawler()

    assert crawler._classify_event("3루주자 박해민 : 포일로 홈인") == (
        "PASSED_BALL",
        True,
    )
    assert crawler._classify_event("타자 홍창기 : 포일") == ("PASSED_BALL", False)


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


def test_concurrent_relay_fetches_do_not_share_session_operations() -> None:
    crawler = RelayCrawler()
    start_barrier = threading.Barrier(3)
    active_session_operations = 0
    max_active_session_operations = 0
    active_guard = threading.Lock()

    crawler._ensure_logged_in = lambda force=False: None

    def fake_fetch_live_text_page(game_id: str) -> None:
        nonlocal active_session_operations, max_active_session_operations
        with active_guard:
            active_session_operations += 1
            max_active_session_operations = max(
                max_active_session_operations,
                active_session_operations,
            )
        time.sleep(0.05)

    def fake_post_live_text_view(view_name: str, game_id: str) -> str:
        nonlocal active_session_operations
        with active_guard:
            active_session_operations -= 1
        return '<div id="numCont1"><span>1회초 원정팀 공격</span></div>'

    crawler._fetch_live_text_page = fake_fetch_live_text_page
    crawler._post_live_text_view = fake_post_live_text_view

    def fetch(game_id: str) -> dict:
        start_barrier.wait(timeout=1)
        return crawler.get_relay(game_id)

    with ThreadPoolExecutor(max_workers=2) as executor:
        first = executor.submit(fetch, "20260719KTLG0")
        second = executor.submit(fetch, "20260719SSHH0")
        start_barrier.wait(timeout=1)
        first.result(timeout=2)
        second.result(timeout=2)

    assert max_active_session_operations == 1


def test_relay_waiter_does_not_queue_past_lock_deadline() -> None:
    crawler = RelayCrawler(lock_wait_timeout_seconds=0.03)
    entered = threading.Event()
    release = threading.Event()
    session_calls = 0

    def blocking_session(game_id: str) -> dict:
        nonlocal session_calls
        session_calls += 1
        entered.set()
        assert release.wait(timeout=2)
        return {"gameId": game_id, "currentAtBat": None, "relayItems": []}

    crawler._get_relay_with_session = blocking_session

    with ThreadPoolExecutor(max_workers=1) as executor:
        leader = executor.submit(crawler.get_relay, "20260719KTLG0")
        assert entered.wait(timeout=1)
        try:
            with pytest.raises(UpstreamBusyError, match="relay session is busy"):
                crawler.get_relay("20260719SSHH0")
        finally:
            release.set()
        assert leader.result(timeout=1)["gameId"] == "20260719KTLG0"

    assert session_calls == 1


def test_relay_fetch_retries_then_rejects_empty_relay_shell() -> None:
    class _Response:
        def __init__(self, text: str) -> None:
            self.text = text

        def raise_for_status(self) -> None:
            return None

    class _Cookies:
        def clear(self) -> None:
            return None

    class _EmptyRelaySession:
        def __init__(self) -> None:
            self.cookies = _Cookies()
            self.view_calls = 0

        def get(self, url: str, **kwargs):
            if url.endswith("/Member/Login.aspx"):
                return _Response("<html></html>")
            return _Response("<html></html>")

        def post(self, url: str, **kwargs):
            if url.endswith("/Member/Login.aspx"):
                return _Response("로그아웃")
            self.view_calls += 1
            return _Response('<div class="playerBox awayBox"></div>')

    crawler = RelayCrawler()
    session = _EmptyRelaySession()
    crawler.session = session
    crawler.user_id = "relay-user"
    crawler.password = "relay-password"
    crawler._logged_in = True

    with pytest.raises(RuntimeError, match="did not contain relay content"):
        crawler.get_relay("20260719KTLG0")

    assert session.view_calls == 2
