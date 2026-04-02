from kbo_fans_backend.crawlers.player_stats import PlayerStatsCrawler


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
