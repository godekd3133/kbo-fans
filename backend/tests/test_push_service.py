from kbo_fans_backend.schemas.push import NotificationSettings
from kbo_fans_backend.schemas.push import PushRegisterRequest
from kbo_fans_backend.services.push import PushService


def test_build_topics_returns_empty_without_team_when_all_games_disabled() -> None:
    service = PushService()
    payload = PushRegisterRequest(
        deviceToken="token",
        platform="flutter",
        myTeam=None,
        notifications=NotificationSettings(
            gameStart=True,
            scoring=True,
            homerun=True,
            reversal=True,
            gameEnd=True,
            lineupOpened=True,
            inningChange=False,
            allGames=False,
        ),
    )

    topics = service._build_topics(payload)

    assert topics == []


def test_build_topics_returns_all_topics_when_all_games_enabled() -> None:
    service = PushService()
    payload = PushRegisterRequest(
        deviceToken="token",
        platform="flutter",
        myTeam="LG",
        notifications=NotificationSettings(
            gameStart=True,
            scoring=True,
            homerun=True,
            reversal=True,
            gameEnd=True,
            lineupOpened=True,
            inningChange=False,
            allGames=True,
        ),
    )

    topics = service._build_topics(payload)

    assert "game_start_ALL" in topics
    assert "all_games_enabled" in topics
    assert "game_start_LG" not in topics
