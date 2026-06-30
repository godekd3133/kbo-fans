from datetime import datetime
from zoneinfo import ZoneInfo

from kbo_fans_backend.crawlers.player_stats import PlayerStatsCrawler


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
