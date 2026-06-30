from kbo_fans_backend.services.youtube_highlight import YoutubeHighlightService


def test_relevant_title_accepts_short_team_aliases() -> None:
    service = YoutubeHighlightService()

    assert service._is_relevant_title(
        title="6/30 KT vs LG 하이라이트",
        away_name="KT 위즈",
        home_name="LG 트윈스",
        game_id="20260630KTLG0",
    )
