import threading
from datetime import datetime
from zoneinfo import ZoneInfo

from kbo_fans_backend.crawlers.player_stats import PlayerStatsCrawler
from kbo_fans_backend.utils.kbo_time import current_kbo_year


class _RegisterFallbackCrawler(PlayerStatsCrawler):
    def _parse_register_all_entries(self, team_id: str):
        return {("문보경", 2)}

    def _fetch_player_search_rows(self, team_id: str, position_value: str):
        return []

    def _fetch_register_page(self, team_id: str) -> str:
        return """
        <table class="tNData">
          <thead>
            <tr>
              <th>등번호</th>
              <th>내야수</th>
              <th>투타유형</th>
              <th>생년월일</th>
              <th>체격</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>2</td>
              <td><a href="/Record/Player/HitterDetail/Basic.aspx?playerId=69102">문보경</a></td>
              <td>우투좌타</td>
              <td>2000-07-19</td>
              <td>182cm, 88kg</td>
            </tr>
          </tbody>
        </table>
        <table class="tNData">
          <thead>
            <tr>
              <th>등번호</th>
              <th>투수</th>
              <th>투타유형</th>
              <th>생년월일</th>
              <th>체격</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>29</td>
              <td><a href="/Record/Player/PitcherDetail/Basic.aspx?playerId=67143">손주영</a></td>
              <td>좌투좌타</td>
              <td>1998-12-02</td>
              <td>191cm, 95kg</td>
            </tr>
          </tbody>
        </table>
        """

    def _fetch_player_profile_summary(self, *, player_id: str, player_type: str, season: int):
        return {}

    def _fetch_player_total_stats(self, player_id: str, player_type: str, season: int):
        return {}

    def _fetch_current_team_stats_by_player(self, team_id: str, season: int):
        return {}


def test_get_team_players_falls_back_to_korean_register_page_when_search_is_empty() -> None:
    crawler = _RegisterFallbackCrawler()

    players = crawler.get_team_players("LG", 2026)

    assert [player["name"] for player in players] == ["문보경", "손주영"]
    assert players[0]["id"] == "69102"
    assert players[0]["playerType"] == "hitter"
    assert players[0]["imageUrl"].endswith("/2026/69102.jpg")
    assert players[0]["position"] == "내야수"
    assert players[0]["rosterGroup"] == "entry"
    assert players[1]["id"] == "67143"
    assert players[1]["playerType"] == "pitcher"
    assert players[1]["rosterGroup"] == "reserve"


def test_player_search_failure_does_not_wait_for_sibling_groups() -> None:
    class _SearchFailureCrawler(PlayerStatsCrawler):
        def __init__(self) -> None:
            super().__init__()
            self.barrier = threading.Barrier(4)
            self.sibling_started = threading.Event()
            self.sibling_release = threading.Event()

        def _parse_register_all_entries(self, team_id: str):
            return set()

        def _fetch_player_search_rows(self, team_id: str, position_value: str):
            self.barrier.wait(timeout=0.5)
            if position_value == "1":
                raise RuntimeError("player search unavailable")
            self.sibling_started.set()
            assert self.sibling_release.wait(timeout=2)
            return []

        def _fetch_register_roster_players(self, team_id: str):
            return []

    crawler = _SearchFailureCrawler()
    errors = []

    def load() -> None:
        try:
            crawler.get_team_players("LG", 2026)
        except BaseException as error:
            errors.append(error)

    thread = threading.Thread(target=load)
    thread.start()
    assert crawler.sibling_started.wait(timeout=1)
    try:
        thread.join(timeout=0.2)
        assert not thread.is_alive()
    finally:
        crawler.sibling_release.set()
        thread.join(timeout=2)

    assert len(errors) == 1
    assert str(errors[0]) == "player search unavailable"


def test_entry_lookup_and_register_roster_start_together() -> None:
    class _ParallelRosterCrawler(PlayerStatsCrawler):
        def __init__(self) -> None:
            super().__init__()
            self.entry_started = threading.Event()
            self.register_started = threading.Event()
            self.entry_release = threading.Event()
            self.register_release = threading.Event()

        def _parse_register_all_entries(self, team_id: str):
            self.entry_started.set()
            assert self.entry_release.wait(timeout=2)
            return set()

        def _fetch_register_roster_players(self, team_id: str):
            self.register_started.set()
            assert self.register_release.wait(timeout=2)
            return []

        def _fetch_player_search_rows(self, team_id: str, position_value: str):
            return []

    crawler = _ParallelRosterCrawler()
    result = {}

    def load() -> None:
        result["players"] = crawler.get_team_players("LG", 2026)

    thread = threading.Thread(target=load)
    thread.start()
    assert crawler.entry_started.wait(timeout=1)
    try:
        assert crawler.register_started.wait(timeout=0.5)
    finally:
        crawler.entry_release.set()
        crawler.register_release.set()
        thread.join(timeout=2)

    assert not thread.is_alive()
    assert result["players"] == []


def test_nonempty_register_roster_skips_english_search() -> None:
    class _RegisterPrimaryCrawler(PlayerStatsCrawler):
        def __init__(self) -> None:
            super().__init__()
            self.profile_calls = 0

        def _parse_register_all_entries(self, team_id: str):
            return {("홍길동", 1)}

        def _fetch_register_roster_players(self, team_id: str):
            return [
                {
                    "id": "12345",
                    "teamId": team_id,
                    "playerType": "hitter",
                    "name": "홍길동",
                    "number": 1,
                    "position": "내야수",
                    "roleLabel": "내야수",
                    "handedness": "우투좌타",
                    "birthDate": "2000-01-01",
                    "heightWeight": "180cm / 80kg",
                }
            ]

        def _fetch_player_search_rows(self, team_id: str, position_value: str):
            raise AssertionError("English player search should be a fallback")

        def _fetch_player_profile_summary(self, *, player_id: str, player_type: str, season: int):
            self.profile_calls += 1
            raise AssertionError("complete Korean roster rows do not need profile GETs")

        def _fetch_player_total_stats(self, player_id: str, player_type: str, season: int):
            return {}

        def _fetch_current_team_stats_by_player(self, team_id: str, season: int):
            return {}

    crawler = _RegisterPrimaryCrawler()
    players = crawler.get_team_players("LG", 2026)

    assert [player["id"] for player in players] == ["12345"]
    assert players[0]["rosterGroup"] == "entry"
    assert crawler.profile_calls == 0


def test_register_roster_failure_falls_back_to_english_search() -> None:
    class _RegisterFailureCrawler(PlayerStatsCrawler):
        def _parse_register_all_entries(self, team_id: str):
            return {("Hong Gil Dong", 1)}

        def _fetch_register_roster_players(self, team_id: str):
            raise RuntimeError("Korean roster unavailable")

        def _fetch_player_search_rows(self, team_id: str, position_value: str):
            if position_value != "1":
                return []
            return [
                {
                    "id": "12345",
                    "teamId": team_id,
                    "playerType": "hitter",
                    "name": "Hong Gil Dong",
                    "number": 1,
                    "position": "Infielder",
                }
            ]

        def _fetch_player_profile_summary(self, *, player_id: str, player_type: str, season: int):
            return {"name": "Hong Gil Dong", "number": 1}

        def _fetch_player_total_stats(self, player_id: str, player_type: str, season: int):
            return {}

    players = _RegisterFailureCrawler().get_team_players("LG", 2026)

    assert [player["id"] for player in players] == ["12345"]
    assert players[0]["rosterGroup"] == "entry"


def test_team_roster_player_type_seeds_player_detail_lookup() -> None:
    class _RosterTypeCrawler(PlayerStatsCrawler):
        def _parse_register_all_entries(self, team_id: str):
            return {("홍길동", 1)}

        def _fetch_register_roster_players(self, team_id: str):
            return [
                {
                    "id": "12345",
                    "teamId": team_id,
                    "playerType": "pitcher",
                    "name": "홍길동",
                    "number": 1,
                    "position": "투수",
                    "roleLabel": "투수",
                    "handedness": "우투우타",
                    "birthDate": "2000-01-01",
                    "heightWeight": "185cm / 80kg",
                }
            ]

        def _fetch_player_total_stats(self, player_id: str, player_type: str, season: int):
            return {}

        def _guess_player_type(self, player_id: str):
            raise AssertionError("team roster should seed the player type")

        def _get_text(self, url: str, *, breaker_key: str):
            del breaker_key
            if "Total.aspx" in url:
                return ""
            return '<span id="lblName">홍길동</span>'

        def _fetch_current_team_stats_by_player(self, team_id: str, season: int):
            return {}

    crawler = _RosterTypeCrawler()
    crawler.get_team_players("LG", 2026)

    detail = crawler.get_player_detail("12345", None, 2026, include_recent=False)

    assert detail["playerType"] == "pitcher"


def test_current_team_players_use_bulk_stats_and_fill_only_missing_totals() -> None:
    class _BulkStatsCrawler(PlayerStatsCrawler):
        def __init__(self) -> None:
            super().__init__()
            self.bulk_calls = []
            self.profile_calls = []
            self.total_calls = []

        def _parse_register_all_entries(self, team_id: str):
            return {("홍길동", 1), ("김철수", 2)}

        def _fetch_register_roster_players(self, team_id: str):
            return [
                {
                    "id": "12345",
                    "teamId": team_id,
                    "playerType": "hitter",
                    "name": "홍길동",
                    "number": 1,
                    "position": "내야수",
                    "roleLabel": "내야수",
                    "handedness": "우투좌타",
                    "birthDate": "2000-01-01",
                    "heightWeight": "180cm / 80kg",
                },
                {
                    "id": "67890",
                    "teamId": team_id,
                    "playerType": "hitter",
                    "name": "김철수",
                    "number": 2,
                    "position": "외야수",
                    "roleLabel": "외야수",
                    "handedness": "우투우타",
                    "birthDate": "2001-01-01",
                    "heightWeight": "181cm / 81kg",
                },
            ]

        def _fetch_current_team_stats_by_player(self, team_id: str, season: int):
            self.bulk_calls.append((team_id, season))
            return {
                "12345": {
                    "AVG": "0.321",
                    "G": "10",
                    "H": "13",
                    "HR": "2",
                    "RBI": "5",
                    "SB": "1",
                    "OBP": "0.400",
                    "SLG": "0.500",
                    "OPS": "0.900",
                }
            }

        def _fetch_player_profile_summary(self, *, player_id: str, player_type: str, season: int):
            self.profile_calls.append(player_id)
            raise AssertionError("complete Korean roster rows should skip profile GETs")

        def _fetch_player_total_stats(self, player_id: str, player_type: str, season: int):
            self.total_calls.append(player_id)
            return {"AVG": "0.111", "G": "1", "H": "1"}

    crawler = _BulkStatsCrawler()
    players = crawler.get_team_players("LG", current_kbo_year())

    assert crawler.bulk_calls == [("LG", current_kbo_year())]
    assert crawler.profile_calls == []
    assert crawler.total_calls == ["67890"]
    assert "AVG 0.321" in players[0]["seasonStats"]
    assert "AVG 0.111" in players[1]["seasonStats"]


def test_empty_entry_list_skips_current_bulk_stats() -> None:
    class _NoEntryCrawler(PlayerStatsCrawler):
        def __init__(self) -> None:
            super().__init__()
            self.bulk_calls = 0

        def _parse_register_all_entries(self, team_id: str):
            return set()

        def _fetch_register_roster_players(self, team_id: str):
            return [
                {
                    "id": "12345",
                    "teamId": team_id,
                    "playerType": "hitter",
                    "name": "홍길동",
                    "number": 1,
                    "position": "내야수",
                    "roleLabel": "내야수",
                    "handedness": "우투좌타",
                    "birthDate": "2000-01-01",
                    "heightWeight": "180cm / 80kg",
                }
            ]

        def _fetch_current_team_stats_by_player(self, team_id: str, season: int):
            self.bulk_calls += 1
            raise AssertionError("reserve-only roster should not fetch entry bulk stats")

    crawler = _NoEntryCrawler()
    players = crawler.get_team_players("LG", current_kbo_year())

    assert crawler.bulk_calls == 0
    assert players[0]["rosterGroup"] == "reserve"
    assert players[0]["seasonStats"] == []


def test_parse_current_team_stats_page_filters_player_type_and_team() -> None:
    crawler = PlayerStatsCrawler()
    html = """
    <table>
      <thead>
        <tr><th>순위</th><th>선수명</th><th>팀명</th><th>AVG</th><th>G</th><th>H</th><th>HR</th><th>RBI</th><th>SB</th></tr>
      </thead>
      <tbody>
        <tr>
          <td>1</td>
          <td><a href='/Record/Player/HitterDetail/Basic.aspx?playerId=12345'>홍길동</a></td>
          <td>LG</td><td>0.321</td><td>10</td><td>13</td><td>2</td><td>5</td><td>1</td>
        </tr>
        <tr>
          <td>2</td>
          <td><a href='/Record/Player/PitcherDetail/Basic.aspx?playerId=67890'>김철수</a></td>
          <td>LG</td><td>0.000</td><td>1</td><td>0</td><td>0</td><td>0</td><td>0</td>
        </tr>
        <tr>
          <td>3</td>
          <td><a href='/Record/Player/HitterDetail/Basic.aspx?playerId=99999'>이영희</a></td>
          <td>KT</td><td>0.400</td><td>2</td><td>1</td><td>0</td><td>1</td><td>0</td>
        </tr>
      </tbody>
    </table>
    """

    stats = crawler._parse_current_team_stats_page(  # type: ignore[attr-defined]
        html,
        player_type="hitter",
        team_id="LG",
        required_fields=("AVG", "G", "H", "HR", "RBI", "SB"),
    )

    assert list(stats) == ["12345"]
    assert stats["12345"]["AVG"] == "0.321"
    assert stats["12345"]["SB"] == "1"


def test_current_team_stats_page_posts_only_team_filter_when_season_is_selected(
    monkeypatch,
) -> None:
    crawler = PlayerStatsCrawler()
    season = current_kbo_year()
    initial_html = f"""
    <select name="{crawler._SEASON_FIELD}">
      <option selected="selected" value="{season}">{season}</option>
    </select>
    <select name="{crawler._TEAM_FIELD}">
      <option selected="selected" value="">전체</option>
      <option value="LG">LG</option>
    </select>
    """
    filtered_html = f"""
    <select name="{crawler._SEASON_FIELD}">
      <option selected="selected" value="{season}">{season}</option>
    </select>
    <select name="{crawler._TEAM_FIELD}">
      <option value="">전체</option>
      <option selected="selected" value="LG">LG</option>
    </select>
    <table>
      <thead>
        <tr><th>순위</th><th>선수명</th><th>팀명</th><th>AVG</th><th>G</th><th>H</th><th>HR</th><th>RBI</th><th>SB</th></tr>
      </thead>
      <tbody>
        <tr>
          <td>1</td>
          <td><a href="/Record/Player/HitterDetail/Basic.aspx?playerId=12345">홍길동</a></td>
          <td>LG</td><td>0.321</td><td>10</td><td>13</td><td>2</td><td>5</td><td>1</td>
        </tr>
      </tbody>
    </table>
    """
    get_calls = []
    post_calls = []
    monkeypatch.setattr(
        crawler,
        "_get_text",
        lambda url, **kwargs: get_calls.append((url, kwargs)) or initial_html,
    )

    def post_page(url: str, **kwargs):
        post_calls.append(kwargs)
        assert kwargs["data"][crawler._TEAM_FIELD] == "LG"
        assert (
            crawler._SEASON_FIELD not in kwargs["data"]
            or kwargs["data"][crawler._SEASON_FIELD] == str(season)
        )
        return filtered_html

    monkeypatch.setattr(crawler, "_post_text", post_page)

    stats = crawler._fetch_current_team_stats_page(  # type: ignore[attr-defined]
        "hitter_basic",
        "/Record/Player/HitterBasic/BasicOld.aspx?sort=HRA_RT",
        "hitter",
        ("AVG", "G", "H", "HR", "RBI", "SB"),
        "LG",
        season,
    )

    assert len(get_calls) == 1
    assert len(post_calls) == 1
    assert stats["12345"]["AVG"] == "0.321"


def test_player_detail_reuses_type_probe_html() -> None:
    class _ProbeReuseCrawler(PlayerStatsCrawler):
        def __init__(self) -> None:
            super().__init__()
            self.text_calls = []

        def _guess_player_type(self, player_id: str):
            return "pitcher"

        def _guess_player_type_with_html(self, player_id: str):
            return "pitcher", '<span id="lblName">홍길동</span>'

        def _get_text(self, url: str, *, breaker_key: str):
            del breaker_key
            self.text_calls.append(url)
            return ""

    crawler = _ProbeReuseCrawler()

    detail = crawler.get_player_detail("12345", None, 2026, include_recent=False)

    assert detail["playerType"] == "pitcher"
    assert len(crawler.text_calls) == 1
    assert "PitcherDetail/Total.aspx" in crawler.text_calls[0]


def test_entry_player_profile_and_total_pages_start_together() -> None:
    class _ParallelEnrichmentCrawler(PlayerStatsCrawler):
        def __init__(self) -> None:
            super().__init__()
            self.profile_started = threading.Event()
            self.total_started = threading.Event()
            self.profile_release = threading.Event()
            self.total_release = threading.Event()

        def _parse_register_all_entries(self, team_id: str):
            return {("홍길동", 1)}

        def _fetch_register_roster_players(self, team_id: str):
            return []

        def _fetch_player_search_rows(self, team_id: str, position_value: str):
            if position_value != "1":
                return []
            return [
                {
                    "id": "12345",
                    "teamId": team_id,
                    "playerType": "hitter",
                    "name": "홍길동",
                    "number": 1,
                    "position": "내야수",
                }
            ]

        def _fetch_player_profile_summary(self, *, player_id: str, player_type: str, season: int):
            self.profile_started.set()
            assert self.profile_release.wait(timeout=2)
            return {}

        def _fetch_player_total_stats(self, player_id: str, player_type: str, season: int):
            self.total_started.set()
            assert self.total_release.wait(timeout=2)
            return {}

    import threading

    crawler = _ParallelEnrichmentCrawler()
    result = {}

    def load() -> None:
        result["players"] = crawler.get_team_players("LG", 2026)

    thread = threading.Thread(target=load)
    thread.start()
    assert crawler.profile_started.wait(timeout=1)
    try:
        assert crawler.total_started.wait(timeout=0.5)
    finally:
        crawler.profile_release.set()
        crawler.total_release.set()
        thread.join(timeout=2)

    assert not thread.is_alive()
    assert result["players"][0]["name"] == "홍길동"


def test_parse_register_all_entries_accepts_team_total_in_header(monkeypatch) -> None:
    crawler = PlayerStatsCrawler()

    class _Response:
        text = """
        <table>
          <tbody>
            <tr>
              <th scope="row" class="fir">두산<br/><br/>40명</th>
              <td><ul><li>김원형(70)</li></ul></td>
              <td><ul><li>손시헌(73)</li></ul></td>
              <td><ul><li>박치국(1)</li></ul></td>
              <td><ul><li>양의지(25)</li></ul></td>
              <td><ul><li>강승호(23)</li></ul></td>
              <td><ul><li>정수빈(31)</li></ul></td>
            </tr>
          </tbody>
        </table>
        """

    monkeypatch.setattr(crawler.session, "get", lambda url, timeout: _Response())

    entries = crawler._parse_register_all_entries("OB")  # type: ignore[attr-defined]

    assert ("박치국", 1) in entries
    assert ("양의지", 25) in entries
    assert ("강승호", 23) in entries
    assert ("정수빈", 31) in entries
    assert ("김원형", 70) not in entries
    assert ("손시헌", 73) not in entries


def test_build_player_summary_preserves_profile_fields() -> None:
    crawler = PlayerStatsCrawler()

    payload = crawler._build_player_summary(  # type: ignore[attr-defined]
        player={
            "id": "12345",
            "teamId": "LG",
            "playerType": "pitcher",
            "name": "홍길동",
            "number": 11,
            "position": "투수",
            "roleLabel": "선발투수",
            "handedness": "우투우타",
            "birthDate": "1999-01-01",
            "heightWeight": "185cm / 88kg",
            "career": "서울고-고려대",
        },
        season=2027,
        season_stats={"ERA": "3.20", "WHIP": "1.11"},
        roster_group="entry",
        status="available",
        status_note=None,
    )

    assert payload["imageUrl"].endswith("/2027/12345.jpg")
    assert payload["roleLabel"] == "선발투수"
    assert payload["handedness"] == "우투우타"
    assert payload["career"] == "서울고-고려대"


def test_build_player_summary_uses_2022_image_folder_for_old_seasons() -> None:
    crawler = PlayerStatsCrawler()

    payload = crawler._build_player_summary(  # type: ignore[attr-defined]
        player={
            "id": "12345",
            "teamId": "LG",
            "playerType": "hitter",
            "name": "홍길동",
            "number": 11,
            "position": "야수",
        },
        season=2013,
        season_stats={},
        roster_group="entry",
        status="available",
        status_note=None,
    )

    assert payload["imageUrl"].endswith("/2022/12345.jpg")


def test_parse_profile_uses_requested_season_for_image_url() -> None:
    crawler = PlayerStatsCrawler()
    html = """
    <span id="lblName">홍길동</span>
    <span id="lblBackNo">10</span>
    <span id="lblBirthday">2000-01-01</span>
    <span id="lblPosition">투수(우투우타)</span>
    <span id="lblHeightWeight">180cm/80kg</span>
    <span id="lblCareer">서울고-고려대</span>
    """

    profile = crawler._parse_profile(  # type: ignore[attr-defined]
        html,
        "99999",
        "pitcher",
        2028,
    )

    assert profile["imageUrl"].endswith("/2028/99999.jpg")
    assert profile["handedness"] == "우투우타"
    assert profile["roleLabel"] == "투수"


def test_parse_profile_uses_2022_image_folder_for_old_seasons() -> None:
    crawler = PlayerStatsCrawler()
    html = """
    <span id="lblName">홍길동</span>
    <span id="lblBackNo">10</span>
    <span id="lblBirthday">2000-01-01</span>
    <span id="lblPosition">타자(우투좌타)</span>
    <span id="lblHeightWeight">180cm/80kg</span>
    <span id="lblCareer">서울고-고려대</span>
    """

    profile = crawler._parse_profile(  # type: ignore[attr-defined]
        html,
        "99999",
        "hitter",
        2013,
    )

    assert profile["imageUrl"].endswith("/2022/99999.jpg")


def test_guess_player_type_uses_pitcher_position_when_hitter_page_has_profile(
    monkeypatch,
) -> None:
    crawler = PlayerStatsCrawler()

    class _Response:
        def __init__(self, text: str) -> None:
            self.text = text

    def _get(url: str, timeout: int):
        if "HitterDetail" in url:
            return _Response(
                """
                <span id="lblName">이민호</span>
                <span id="lblPosition">투수(우투우타)</span>
                """
            )
        return _Response(
            """
            <span id="lblName">이민호</span>
            <span id="lblPosition">투수(우투우타)</span>
            """
        )

    monkeypatch.setattr(crawler.session, "get", _get)

    assert crawler._guess_player_type("50126") == "pitcher"  # type: ignore[attr-defined]


def test_player_detail_profile_and_total_pages_start_together() -> None:
    class _ParallelDetailCrawler(PlayerStatsCrawler):
        def __init__(self) -> None:
            super().__init__()
            self.detail_started = threading.Event()
            self.total_started = threading.Event()
            self.detail_release = threading.Event()
            self.total_release = threading.Event()

        def _get_text(self, url: str, *, breaker_key: str) -> str:
            del breaker_key
            if "Total.aspx" in url:
                self.total_started.set()
                assert self.total_release.wait(timeout=2)
                return ""
            self.detail_started.set()
            assert self.detail_release.wait(timeout=2)
            return '<span id="lblName">홍길동</span>'

    crawler = _ParallelDetailCrawler()
    result = {}

    def load() -> None:
        result["profile"] = crawler.get_player_detail(
            "12345",
            "hitter",
            2026,
            include_recent=False,
        )

    thread = threading.Thread(target=load)
    thread.start()
    assert crawler.detail_started.wait(timeout=1)
    try:
        assert crawler.total_started.wait(timeout=0.5)
    finally:
        crawler.detail_release.set()
        crawler.total_release.set()
        thread.join(timeout=2)

    assert not thread.is_alive()
    assert result["profile"]["name"] == "홍길동"


def test_player_detail_failure_does_not_wait_for_total_page() -> None:
    barrier = threading.Barrier(2)
    total_started = threading.Event()
    total_release = threading.Event()
    errors = []

    class _FailingDetailCrawler(PlayerStatsCrawler):
        def _get_text(self, url: str, *, breaker_key: str) -> str:
            del breaker_key
            barrier.wait(timeout=0.5)
            if "Total.aspx" in url:
                total_started.set()
                total_release.wait(timeout=2)
                return ""
            raise RuntimeError("player detail unavailable")

    crawler = _FailingDetailCrawler()

    def load() -> None:
        try:
            crawler.get_player_detail("12345", "hitter", 2026, include_recent=False)
        except BaseException as error:
            errors.append(error)

    thread = threading.Thread(target=load)
    thread.start()
    assert total_started.wait(timeout=1)
    try:
        thread.join(timeout=0.2)
        assert not thread.is_alive()
    finally:
        total_release.set()
        thread.join(timeout=2)

    assert len(errors) == 1
    assert str(errors[0]) == "player detail unavailable"


def test_player_total_failure_does_not_wait_for_detail_page() -> None:
    barrier = threading.Barrier(2)
    detail_started = threading.Event()
    detail_release = threading.Event()
    errors = []

    class _LateTotalFailureCrawler(PlayerStatsCrawler):
        def _get_text(self, url: str, *, breaker_key: str) -> str:
            del breaker_key
            barrier.wait(timeout=0.5)
            if "Total.aspx" in url:
                raise RuntimeError("player total unavailable")
            detail_started.set()
            assert detail_release.wait(timeout=2)
            return '<span id="lblName">홍길동</span>'

    crawler = _LateTotalFailureCrawler()

    def load() -> None:
        try:
            crawler.get_player_detail("12345", "hitter", 2026, include_recent=False)
        except BaseException as error:
            errors.append(error)

    thread = threading.Thread(target=load)
    thread.start()
    assert detail_started.wait(timeout=1)
    try:
        thread.join(timeout=0.2)
        assert not thread.is_alive()
    finally:
        detail_release.set()
        thread.join(timeout=2)

    assert len(errors) == 1
    assert str(errors[0]) == "player total unavailable"


class _CurrentPlayerDetailCrawler(PlayerStatsCrawler):
    def _get_text(self, url: str, *, breaker_key: str) -> str:
        if "Total.aspx" in url:
            return """
            <table class="tbl tt">
              <thead>
                <tr><th>연도</th><th>팀명</th><th>AVG</th><th>G</th><th>H</th><th>HR</th><th>RBI</th><th>OPS</th></tr>
              </thead>
              <tbody>
                <tr><td>2026</td><td>KIA</td><td>0.333</td><td>43</td><td>53</td><td>6</td><td>20</td><td>0.978</td></tr>
              </tbody>
            </table>
            """
        return """
        <span id="lblName">김도영</span>
        <span id="lblBackNo">5</span>
        <span id="lblBirthday">2003-10-02</span>
        <span id="lblPosition">내야수(우투우타)</span>
        <span id="lblHeightWeight">183cm/85kg</span>
        <span id="lblCareer">동성고</span>
        <h6>최근 10경기</h6>
        <div class="tbl-type02 mb35">
          <table class="tbl tt">
            <tbody>
              <tr>
                <td>06.28</td><td>두산</td><td>0.500</td><td>4</td><td>4</td>
                <td>1</td><td>2</td><td>0</td><td>0</td><td>1</td><td>1</td>
              </tr>
              <tr>
                <td>06.27</td><td>두산</td><td>0.000</td><td>4</td><td>4</td>
                <td>0</td><td>0</td><td>0</td><td>0</td><td>0</td><td>0</td>
              </tr>
            </tbody>
          </table>
        </div>
        """


def test_player_detail_includes_current_recent_games_when_page_omits_season_label() -> None:
    crawler = _CurrentPlayerDetailCrawler()
    current_season = datetime.now(ZoneInfo("Asia/Seoul")).year

    payload = crawler.get_player_detail(
        "52605",
        "hitter",
        current_season,
        include_recent=True,
    )

    assert [game["date"] for game in payload["recentGames"]] == ["06.28", "06.27"]
    assert payload["recentGames"][0]["summary"] == "AVG 0.500 · H 2 · HR 1 · RBI 1"
