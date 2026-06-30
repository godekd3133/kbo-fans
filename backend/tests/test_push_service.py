import fcntl
import json
import os
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from kbo_fans_backend.api.routes import push as push_routes
from kbo_fans_backend.core.config import Settings
from kbo_fans_backend.main import app
from kbo_fans_backend.schemas.push import (
    LiveActivityContentState,
    LiveActivityRegisterRequest,
    LiveActivityStartTokenRegisterRequest,
    LiveActivityUnregisterRequest,
    LiveActivityUpdateRequest,
    NotificationDeliveryModes,
    NotificationSettings,
    PushDeviceTestRequest,
    PushReceiptRequest,
    PushRegisterRequest,
    PushTestRequest,
)
from kbo_fans_backend.services.apns_live_activity import ApnsLiveActivitySender
from kbo_fans_backend.services.live_activity_scoreboard import LiveActivityScoreboardSyncService
from kbo_fans_backend.services.push import PushService
from kbo_fans_backend.services.push_diagnostics import PushConfigurationDiagnostics
from kbo_fans_backend.services.push_registry import PushRegistry


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


def test_build_topics_uses_all_topics_without_my_team_immediate_duplicates() -> None:
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
    assert "scoring_LG" not in topics
    assert "homerun_LG" not in topics
    assert "game_end_LG" not in topics
    assert "inning_change_LG" not in topics


def test_build_topics_keeps_non_immediate_my_team_topics_when_all_games_enabled() -> None:
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
            inningChange=True,
            allGames=True,
            deliveryModes=NotificationDeliveryModes(
                gameEnd="summary",
                lineupOpened="summary",
                inningChange="live_only",
            ),
        ),
    )

    topics = service._build_topics(payload)

    assert "game_start_ALL" in topics
    assert "game_start_LG" not in topics
    assert "game_end_ALL" not in topics
    assert "game_end_LG" in topics
    assert "lineup_opened_ALL" not in topics
    assert "lineup_opened_LG" in topics
    assert "inning_change_ALL" not in topics
    assert "inning_change_LG" in topics


def test_build_topics_respects_delivery_modes() -> None:
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
            inningChange=True,
            allGames=False,
            deliveryModes=NotificationDeliveryModes(
                gameStart="immediate",
                scoring="summary",
                hit="off",
                homerun="live_only",
                reversal="off",
                gameEnd="immediate",
                lineupOpened="summary",
                inningChange="live_only",
                atBat="summary",
                baseballInfo="off",
            ),
        ),
    )

    topics = service._build_topics(payload)

    assert topics == [
        "game_start_LG",
        "game_start_soon_LG",
        "scoring_LG",
        "homerun_LG",
        "game_end_LG",
        "lineup_opened_LG",
        "inning_change_LG",
        "at_bat_LG",
    ]


def test_build_topics_respects_off_mode_for_my_team_game_moments() -> None:
    service = PushService()
    payload = PushRegisterRequest(
        deviceToken="token",
        platform="flutter",
        myTeam="LG",
        followedGameIds=["20260612KTOB0"],
        notifications=NotificationSettings(
            gameStart=False,
            scoring=False,
            hit=False,
            homerun=False,
            reversal=False,
            gameEnd=False,
            lineupOpened=False,
            inningChange=False,
            atBat=False,
            baseballInfo=False,
            allGames=False,
            deliveryModes=NotificationDeliveryModes(
                gameStart="off",
                scoring="off",
                hit="off",
                homerun="off",
                reversal="off",
                gameEnd="off",
                lineupOpened="off",
                inningChange="off",
                atBat="off",
                baseballInfo="off",
            ),
        ),
    )

    topics = service._build_topics(payload)

    assert topics == []


def test_build_topics_keeps_my_team_game_moments_without_follow_action() -> None:
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
            inningChange=True,
            allGames=False,
        ),
    )

    topics = service._build_topics(payload)

    assert "game_start_LG" in topics
    assert "game_start_soon_LG" in topics
    assert "scoring_LG" in topics
    assert "hit_LG" in topics
    assert "homerun_LG" in topics
    assert "reversal_LG" in topics
    assert "game_end_LG" in topics
    assert "lineup_opened_LG" in topics
    assert "inning_change_LG" in topics
    assert "at_bat_LG" in topics


def test_build_topics_keeps_my_team_topics_when_following_other_team_game() -> None:
    service = PushService()
    payload = PushRegisterRequest(
        deviceToken="token",
        platform="flutter",
        myTeam="LG",
        followedGameIds=["20260612KTOB0"],
        notifications=NotificationSettings(
            gameStart=True,
            scoring=True,
            homerun=True,
            reversal=True,
            gameEnd=True,
            lineupOpened=True,
            inningChange=True,
            allGames=False,
        ),
    )

    topics = service._build_topics(payload)

    assert "scoring_LG" in topics
    assert "scoring_GAME_20260612KTOB0" in topics
    assert "game_end_LG" in topics
    assert "game_end_GAME_20260612KTOB0" in topics
    assert "lineup_opened_LG" in topics
    assert "lineup_opened_GAME_20260612KTOB0" in topics
    assert "inning_change_LG" in topics
    assert "inning_change_GAME_20260612KTOB0" in topics
    assert "baseball_info_LG" in topics
    assert "baseball_info_GAME_20260612KTOB0" not in topics


def test_build_topics_skips_game_topic_when_followed_game_is_my_team_game() -> None:
    service = PushService()
    payload = PushRegisterRequest(
        deviceToken="token",
        platform="flutter",
        myTeam="LG",
        followedGameIds=["20260612KTLG0"],
        notifications=NotificationSettings(
            gameStart=True,
            scoring=True,
            homerun=True,
            reversal=True,
            gameEnd=True,
            lineupOpened=True,
            inningChange=True,
            allGames=False,
        ),
    )

    topics = service._build_topics(payload)

    assert "scoring_LG" in topics
    assert "game_end_LG" in topics
    assert "lineup_opened_LG" in topics
    assert "inning_change_LG" in topics
    assert "scoring_GAME_20260612KTLG0" not in topics
    assert "game_end_GAME_20260612KTLG0" not in topics
    assert "lineup_opened_GAME_20260612KTLG0" not in topics
    assert "inning_change_GAME_20260612KTLG0" not in topics


def test_build_topics_uses_team_topics_when_following_my_team_game() -> None:
    service = PushService()
    payload = PushRegisterRequest(
        deviceToken="token",
        platform="flutter",
        myTeam="LG",
        followedGameIds=["20260612KTLG0", " ", "20260612KTLG0"],
        notifications=NotificationSettings(
            gameStart=True,
            scoring=True,
            homerun=True,
            reversal=True,
            gameEnd=True,
            lineupOpened=True,
            inningChange=True,
            allGames=False,
        ),
    )

    topics = service._build_topics(payload)

    assert "scoring_LG" in topics
    assert "homerun_LG" in topics
    assert "game_start_LG" in topics
    assert "game_start_soon_LG" in topics
    assert "hit_LG" in topics
    assert "at_bat_LG" in topics
    assert "lineup_opened_LG" in topics
    assert "inning_change_LG" in topics
    assert "game_end_LG" in topics
    assert "baseball_info_LG" in topics
    assert "scoring_GAME_20260612KTLG0" not in topics
    assert "homerun_GAME_20260612KTLG0" not in topics
    assert "game_start_GAME_20260612KTLG0" not in topics
    assert "hit_GAME_20260612KTLG0" not in topics
    assert "baseball_info_GAME_20260612KTLG0" not in topics


def test_build_topics_keeps_enabled_followed_game_moments_even_when_not_immediate() -> None:
    service = PushService()
    payload = PushRegisterRequest(
        deviceToken="token",
        platform="flutter",
        myTeam="LG",
        followedGameIds=["20260612KTOB0"],
        notifications=NotificationSettings(
            gameStart=True,
            scoring=True,
            homerun=True,
            reversal=True,
            gameEnd=True,
            lineupOpened=True,
            inningChange=True,
            allGames=False,
            deliveryModes=NotificationDeliveryModes(
                gameEnd="summary",
                lineupOpened="summary",
                inningChange="live_only",
            ),
        ),
    )

    topics = service._build_topics(payload)

    assert "game_end_GAME_20260612KTOB0" in topics
    assert "lineup_opened_GAME_20260612KTOB0" in topics
    assert "inning_change_GAME_20260612KTOB0" in topics
    assert "game_end_LG" in topics
    assert "lineup_opened_LG" in topics
    assert "inning_change_LG" in topics


def test_build_topics_uses_game_topics_for_non_my_team_follow() -> None:
    service = PushService()
    payload = PushRegisterRequest(
        deviceToken="token",
        platform="flutter",
        myTeam="LG",
        followedGameIds=["20260612KTOB0"],
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

    assert "scoring_GAME_20260612KTOB0" in topics
    assert "homerun_GAME_20260612KTOB0" in topics
    assert "at_bat_GAME_20260612KTOB0" in topics
    assert "baseball_info_LG" in topics
    assert "game_end_GAME_20260612KTOB0" in topics
    assert "scoring_LG" in topics
    assert "homerun_LG" in topics
    assert "game_end_LG" in topics


def test_register_persists_device_token(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    payload = PushRegisterRequest(
        deviceToken="fcm-token",
        platform="ios",
        myTeam="LG",
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

    response = service.register(payload)

    assert response["registered"] is True
    assert "scoring_LG" in response["subscribedTopics"]
    assert "hit_LG" in response["subscribedTopics"]
    assert "game_start_soon_LG" in response["subscribedTopics"]
    assert "at_bat_LG" in response["subscribedTopics"]
    assert "game_end_LG" in response["subscribedTopics"]
    assert "lineup_opened_LG" in response["subscribedTopics"]
    assert "baseball_info_LG" in response["subscribedTopics"]


def test_register_persists_followed_game_ids(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())

    response = service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            myTeam="LG",
            followedGameIds=["20260612KTLG0", " ", "20260612KTLG0"],
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
    )

    registration = registry.device_registrations()[0]

    assert response["followedGameIds"] == ["20260612KTLG0"]
    assert registration["followedGameIds"] == ["20260612KTLG0"]


def test_register_persists_summary_detail_level(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())

    service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            myTeam="LG",
            notifications=NotificationSettings(
                gameStart=True,
                scoring=False,
                homerun=False,
                reversal=False,
                gameEnd=True,
                lineupOpened=True,
                inningChange=False,
                baseballInfo=False,
                allGames=False,
                summaryDetailLevel="standard",
            ),
        )
    )

    registration = registry.device_registrations()[0]

    assert registration["notifications"]["summaryDetailLevel"] == "standard"


def test_register_persists_live_detail_level(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())

    service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            myTeam="LG",
            notifications=NotificationSettings(
                gameStart=True,
                scoring=True,
                hit=True,
                homerun=True,
                reversal=True,
                gameEnd=True,
                lineupOpened=True,
                inningChange=False,
                baseballInfo=False,
                allGames=False,
                liveDetailLevel="standard",
            ),
        )
    )

    registration = registry.device_registrations()[0]

    assert registration["notifications"]["liveDetailLevel"] == "standard"


def test_register_persists_push_client_state_for_receipt_diagnostics(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())

    service.register(
        PushRegisterRequest(
            deviceToken="secret-fcm-token",
            platform="ios",
            installationId="install-12345678",
            myTeam="LG",
            followedGameIds=["20260612KTLG0"],
            notificationsAllowed=True,
            authorizationStatus="authorized",
            apnsTokenReady=True,
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
    )

    registration = registry.device_registrations()[0]

    assert registration["notificationsAllowed"] is True
    assert registration["installationId"] == "install-12345678"
    assert registration["authorizationStatus"] == "authorized"
    assert registration["apnsTokenReady"] is True


def test_register_replaces_stale_token_for_same_installation(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())

    service.register(
        PushRegisterRequest(
            deviceToken="old-token",
            platform="ios",
            installationId="install-12345678",
            myTeam="HT",
            followedGameIds=["20260620HTKT0"],
            notificationsAllowed=True,
            authorizationStatus="authorized",
            apnsTokenReady=True,
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
    )

    service.register(
        PushRegisterRequest(
            deviceToken="new-token",
            platform="ios",
            installationId="install-12345678",
            myTeam="HT",
            followedGameIds=["20260620HTKT0"],
            notificationsAllowed=True,
            authorizationStatus="authorized",
            apnsTokenReady=True,
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
    )

    registrations = registry.device_registrations()

    assert len(registrations) == 1
    assert registrations[0]["deviceToken"] == "new-token"
    assert registrations[0]["installationId"] == "install-12345678"
    assert registrations[0]["followedGameIds"] == ["20260620HTKT0"]


def test_send_game_moment_hit_includes_play_and_situation_payload(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_game_moment(
        moment="hit",
        game_id="20260604LGKT0",
        away_team_id="LG",
        away_team_name="LG",
        home_team_id="KT",
        home_team_name="KT",
        away_score=2,
        home_score=3,
        inning="7회말",
        batter_name="장성우",
        pitcher_name="김진성",
        situation_text="1사 1,2루",
        play_text="장성우 : 좌전 안타",
    )

    assert response["sent"] is True
    assert [message.topic for message in messaging.sent_messages] == [
        "hit_LG",
        "hit_KT",
        "hit_ALL",
        "hit_GAME_20260604LGKT0",
    ]
    first_message = messaging.sent_messages[0]
    assert first_message.notification.title == "안타"
    assert first_message.notification.body == "7회말 장성우 : 좌전 안타 · 현재 1사 1,2루"
    assert first_message.data["type"] == "hit"
    assert first_message.data["situationText"] == "1사 1,2루"
    assert first_message.data["playText"] == "장성우 : 좌전 안타"
    assert first_message.data["batterName"] == "장성우"
    assert first_message.apns.headers["apns-priority"] == "10"
    assert first_message.apns.headers["apns-push-type"] == "alert"
    assert first_message.apns.headers["apns-topic"] == "com.kbofans.kboFans"
    assert first_message.apns.payload.aps.alert.title == "안타"
    assert first_message.apns.payload.aps.alert.body == "7회말 장성우 : 좌전 안타 · 현재 1사 1,2루"
    assert first_message.apns.payload.aps.sound == "default"
    assert first_message.android.priority == "high"
    assert first_message.android.notification.channel_id == "remote_push_foreground"
    assert first_message.android.notification.sound == "default"


def test_send_game_moment_includes_followed_game_topic(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_game_moment(
        moment="scoring",
        game_id="20260604LGKT0",
        away_team_id="LG",
        away_team_name="LG",
        home_team_id="KT",
        home_team_name="KT",
        away_score=2,
        home_score=3,
        inning="7회말",
    )

    assert response["sent"] is True
    assert [message.topic for message in messaging.sent_messages] == [
        "scoring_LG",
        "scoring_KT",
        "scoring_ALL",
        "scoring_GAME_20260604LGKT0",
    ]


def test_send_game_moment_matchup_copy_normalizes_team_ids(tmp_path) -> None:
    expected_names = {
        "LG": "LG",
        "KT": "KT",
        "SK": "SSG",
        "SS": "삼성",
        "NC": "NC",
        "HH": "한화",
        "LT": "롯데",
        "HT": "KIA",
        "OB": "두산",
        "WO": "키움",
    }

    for team_id, expected_name in expected_names.items():
        registry = PushRegistry(str(tmp_path / f"push_registry_{team_id}.json"))
        service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
        messaging = FakeFcmMessaging()
        service._get_messaging = lambda messaging=messaging: messaging

        response = service.send_game_moment(
            moment="game_start",
            game_id=f"20260604{team_id}LG0",
            away_team_id=team_id,
            away_team_name=team_id,
            home_team_id="LG",
            home_team_name="LG",
            away_score=0,
            home_score=0,
            inning="경기전",
        )

        assert response["sent"] is True
        assert messaging.sent_messages[0].notification.body == (
            f"{expected_name} vs LG 경기가 시작됐습니다."
        )
        assert messaging.sent_messages[0].data["awayTeamId"] == team_id


def test_send_game_moment_homerun_uses_plain_copy_and_situation_payload(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_game_moment(
        moment="homerun",
        game_id="20260604LGKT0",
        away_team_id="LG",
        away_team_name="LG",
        home_team_id="KT",
        home_team_name="KT",
        away_score=2,
        home_score=6,
        inning="7회말",
        batter_name="장성우",
        pitcher_name="김진성",
        situation_text="1사 1,2루",
        play_text="장성우 : 좌월 홈런",
    )

    assert response["sent"] is True
    first_message = messaging.sent_messages[0]
    assert first_message.notification.title == "홈런"
    assert (
        first_message.notification.body == "7회말 장성우 : 좌월 홈런 · 현재 1사 1,2루 · 스코어 2:6"
    )
    assert "홈런 발생" not in first_message.notification.body
    assert first_message.data["type"] == "homerun"
    assert first_message.data["situationText"] == "1사 1,2루"
    assert first_message.data["playText"] == "장성우 : 좌월 홈런"


def test_send_lineup_opened_includes_followed_game_topic(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_lineup_opened(
        game_id="20260604LGKT0",
        away_team_id="LG",
        away_team_name="LG",
        home_team_id="KT",
        home_team_name="KT",
    )

    assert response["sent"] is True
    assert [message.topic for message in messaging.sent_messages] == [
        "lineup_opened_LG",
        "lineup_opened_KT",
        "lineup_opened_ALL",
        "lineup_opened_GAME_20260604LGKT0",
    ]
    first_message = messaging.sent_messages[0]
    assert first_message.notification.body == "LG vs KT 라인업이 공개됐습니다."


def test_send_lineup_opened_copy_normalizes_team_ids(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_lineup_opened(
        game_id="20260604SSSK0",
        away_team_id="SS",
        away_team_name="SS",
        home_team_id="SK",
        home_team_name="SK",
    )

    assert response["sent"] is True
    assert [message.topic for message in messaging.sent_messages] == [
        "lineup_opened_SS",
        "lineup_opened_SK",
        "lineup_opened_ALL",
        "lineup_opened_GAME_20260604SSSK0",
    ]
    first_message = messaging.sent_messages[0]
    assert first_message.notification.body == "삼성 vs SSG 라인업이 공개됐습니다."


def test_send_game_moment_lineup_opened_uses_lineup_copy(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_game_moment(
        moment="lineup_opened",
        game_id="20260604LGKT0",
        away_team_id="LG",
        away_team_name="LG",
        home_team_id="KT",
        home_team_name="KT",
        away_score=0,
        home_score=0,
        inning="경기전",
    )

    assert response["sent"] is True
    assert [message.topic for message in messaging.sent_messages] == [
        "lineup_opened_LG",
        "lineup_opened_KT",
        "lineup_opened_ALL",
        "lineup_opened_GAME_20260604LGKT0",
    ]
    first_message = messaging.sent_messages[0]
    assert first_message.notification.title == "선발 라인업 공개"
    assert first_message.notification.body == "LG vs KT 라인업이 공개됐습니다."


def test_send_game_moment_start_soon_includes_start_time_payload(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_game_moment(
        moment="game_start_soon",
        game_id="20260604LGKT0",
        away_team_id="LG",
        away_team_name="LG",
        home_team_id="KT",
        home_team_name="KT",
        away_score=0,
        home_score=0,
        inning="18:30 예정",
        start_time="18:30",
        stadium="수원",
    )

    assert response["sent"] is True
    assert [message.topic for message in messaging.sent_messages] == [
        "game_start_soon_LG",
        "game_start_soon_KT",
        "game_start_soon_ALL",
        "game_start_soon_GAME_20260604LGKT0",
    ]
    first_message = messaging.sent_messages[0]
    assert first_message.notification.title == "경기 곧 시작"
    assert first_message.notification.body == "LG vs KT 경기가 곧 시작됩니다. 18:30 · 수원"
    assert first_message.data["type"] == "game_start_soon"
    assert first_message.data["startTime"] == "18:30"
    assert first_message.data["stadium"] == "수원"


def test_send_game_moment_scoring_uses_play_text_for_varied_copy(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_game_moment(
        moment="scoring",
        game_id="20260604LGKT0",
        away_team_id="LG",
        away_team_name="LG",
        home_team_id="KT",
        home_team_name="KT",
        away_score=4,
        home_score=3,
        inning="8회초",
        batter_name="문보경",
        situation_text="2사 1,3루",
        play_text="문보경 우전 적시타",
    )

    assert response["sent"] is True
    first_message = messaging.sent_messages[0]
    assert first_message.notification.title == "득점"
    assert (
        first_message.notification.body == "8회초 문보경 우전 적시타 · 현재 2사 1,3루 · 스코어 4:3"
    )
    assert first_message.data["type"] == "scoring"
    assert first_message.data["playText"] == "문보경 우전 적시타"


def test_send_game_moment_scoring_without_play_uses_plain_copy(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_game_moment(
        moment="scoring",
        game_id="20260604LGKT0",
        away_team_id="LG",
        away_team_name="LG 트윈스",
        home_team_id="KT",
        home_team_name="KT 위즈",
        away_score=4,
        home_score=3,
        inning="8회초",
    )

    assert response["sent"] is True
    first_message = messaging.sent_messages[0]
    assert first_message.notification.title == "득점"
    assert first_message.notification.body == "8회초 LG vs KT 득점 · 스코어 4:3"
    assert "발생" not in first_message.notification.body
    assert "현재 스코어" not in first_message.notification.body


def test_send_game_moment_reversal_uses_scorebug_copy(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_game_moment(
        moment="reversal",
        game_id="20260604LGKT0",
        away_team_id="LG",
        away_team_name="LG",
        home_team_id="KT",
        home_team_name="KT",
        away_score=4,
        home_score=3,
        inning="8회초",
    )

    assert response["sent"] is True
    first_message = messaging.sent_messages[0]
    assert first_message.notification.title == "역전"
    assert first_message.notification.body == "8회초 LG vs KT 역전 · 스코어 4:3"
    assert "상황입니다" not in first_message.notification.body


def test_send_game_moment_cancelled_game_end_uses_cancel_copy(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_game_moment(
        moment="game_end",
        game_id="20260604LGKT0",
        away_team_id="LG",
        away_team_name="LG",
        home_team_id="KT",
        home_team_name="KT",
        away_score=0,
        home_score=0,
        inning="경기취소",
        game_status="CANCELLED",
    )

    assert response["sent"] is True
    first_message = messaging.sent_messages[0]
    assert first_message.notification.title == "경기 취소"
    assert first_message.notification.body == "LG vs KT 경기가 취소됐습니다."
    assert "최종 스코어" not in first_message.notification.body
    assert first_message.data["gameStatus"] == "CANCELLED"


def test_send_game_moment_suspended_game_end_uses_suspended_copy(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_game_moment(
        moment="game_end",
        game_id="20260604LGKT0",
        away_team_id="LG",
        away_team_name="LG",
        home_team_id="KT",
        home_team_name="KT",
        away_score=2,
        home_score=2,
        inning="서스펜디드",
        game_status="SUSPENDED",
    )

    assert response["sent"] is True
    first_message = messaging.sent_messages[0]
    assert first_message.notification.title == "서스펜디드"
    assert first_message.notification.body == "LG vs KT 경기가 서스펜디드 처리됐습니다."
    assert "최종 스코어" not in first_message.notification.body
    assert first_message.data["gameStatus"] == "SUSPENDED"


def test_send_game_moment_inning_change_uses_baseball_copy(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_game_moment(
        moment="inning_change",
        game_id="20260604LGKT0",
        away_team_id="LG",
        away_team_name="LG",
        home_team_id="KT",
        home_team_name="KT",
        away_score=2,
        home_score=3,
        inning="8회초",
    )

    assert response["sent"] is True
    first_message = messaging.sent_messages[0]
    assert first_message.notification.title == "이닝 교대"
    assert first_message.notification.body == "LG vs KT 8회초 시작 · 스코어 2:3"


def test_send_game_moment_at_bat_uses_plain_title(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_game_moment(
        moment="at_bat",
        game_id="20260604LGKT0",
        away_team_id="LG",
        away_team_name="LG",
        home_team_id="KT",
        home_team_name="KT",
        away_score=4,
        home_score=3,
        inning="8회초",
        batter_name="문보경",
        pitcher_name="고영표",
    )

    assert response["sent"] is True
    first_message = messaging.sent_messages[0]
    assert first_message.notification.title == "타석"
    assert first_message.notification.body == "8회초 문보경 타석 · 투수 고영표"


def test_send_baseball_info_weekly_check_targets_all_team_topics(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_baseball_info(
        kind="weekly_check",
        date="2026-06-22",
    )

    assert response["sent"] is True
    assert response["kind"] == "weekly_check"
    assert [message.topic for message in messaging.sent_messages] == [
        "baseball_info_LG",
        "baseball_info_KT",
        "baseball_info_SK",
        "baseball_info_SS",
        "baseball_info_NC",
        "baseball_info_HH",
        "baseball_info_LT",
        "baseball_info_HT",
        "baseball_info_OB",
        "baseball_info_WO",
        "baseball_info_ALL",
    ]
    first_message = messaging.sent_messages[0]
    assert first_message.notification.title == "월요일 야구 체크"
    assert first_message.notification.body == "이번 주 KBO 일정, 순위, 기록 흐름을 확인해 보세요."
    assert first_message.data["type"] == "baseball_info"
    assert first_message.data["kind"] == "weekly_check"
    assert first_message.data["date"] == "2026-06-22"


def test_send_baseball_info_team_records_copy_uses_team_name(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_baseball_info(
        kind="records_check",
        date="2026-06-24",
        team_id="LG",
    )

    assert response["sent"] is True
    assert response["kind"] == "records_check"
    assert [message.topic for message in messaging.sent_messages] == ["baseball_info_LG"]
    first_message = messaging.sent_messages[0]
    assert first_message.notification.title == "LG 트윈스 기록실"
    assert first_message.notification.body == "LG 트윈스 타자와 투수 기록 흐름을 확인해 보세요."
    assert first_message.data["teamId"] == "LG"


def test_send_baseball_info_game_day_copy_uses_team_name(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_baseball_info(
        kind="game_day",
        date="2026-06-24",
        team_id="LG",
        dry_run=True,
    )

    assert response["sent"] is False
    assert response["notification"] == {
        "title": "LG 트윈스 경기일 체크",
        "body": "오늘 LG 트윈스 경기 일정, 선발 라인업, 중계 상황을 확인해 보세요.",
    }
    assert messaging.sent_messages == []


def test_send_baseball_info_lineup_day_copy_uses_matchup_context(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_baseball_info(
        kind="lineup_day",
        date="2026-06-30",
        team_id="OB",
        game_id="20260630LTOB0",
        matchup="롯데 vs 두산",
        start_time="18:30",
        stadium="잠실",
        dry_run=True,
    )

    assert response["sent"] is False
    assert response["notification"] == {
        "title": "롯데 vs 두산 경기 전 체크",
        "body": "18:30 · 잠실 · 선발 라인업과 예매 정보를 확인해 보세요.",
    }
    assert response["data"]["teamId"] == "OB"
    assert response["data"]["gameId"] == "20260630LTOB0"
    assert response["data"]["route"] == "/game/20260630LTOB0?tab=lineup"
    assert messaging.sent_messages == []


def test_send_baseball_info_dry_run_previews_without_firebase_send(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_baseball_info(
        kind="off_day",
        date="2026-06-23",
        team_id="LG",
        dry_run=True,
    )

    assert response["sent"] is False
    assert response["dryRun"] is True
    assert response["kind"] == "off_day"
    assert response["notification"] == {
        "title": "LG 트윈스 야구 브리프",
        "body": "경기가 없는 날에는 순위표와 다음 일정을 가볍게 확인해 보세요.",
    }
    assert response["targets"] == [{"topic": "baseball_info_LG"}]
    assert response["messages"] == []
    assert messaging.sent_messages == []


def test_send_test_push_uses_visible_notification_options(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_test(
        PushTestRequest(
            title="테스트",
            body="백그라운드 수신 확인",
            topic="game_start_OB",
        )
    )

    assert response["sent"] is True
    message = messaging.sent_messages[0]
    assert message.topic == "game_start_OB"
    assert message.apns.headers["apns-priority"] == "10"
    assert message.apns.headers["apns-push-type"] == "alert"
    assert message.apns.headers["apns-topic"] == "com.kbofans.kboFans"
    assert message.apns.payload.aps.alert.title == "테스트"
    assert message.apns.payload.aps.alert.body == "백그라운드 수신 확인"
    assert message.apns.payload.aps.sound == "default"
    assert message.apns.payload.aps.content_available is True
    assert message.android.priority == "high"
    assert message.android.notification.channel_id == "remote_push_foreground"
    assert message.android.notification.sound == "default"


def test_send_test_push_to_game_topic_includes_receipt_routing_data(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    service.send_test(
        PushTestRequest(
            title="테스트",
            body="팔로우 경기 수신 확인",
            topic="hit_GAME_20260620HTKT0",
        )
    )

    message = messaging.sent_messages[0]
    assert message.topic == "hit_GAME_20260620HTKT0"
    assert message.data == {
        "type": "hit",
        "gameId": "20260620HTKT0",
        "topic": "hit_GAME_20260620HTKT0",
        "route": "/game/20260620HTKT0?tab=relay",
    }


def test_send_device_test_push_targets_registered_token_only(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging
    service.register(
        PushRegisterRequest(
            deviceToken="registered-token",
            platform="ios",
            myTeam="OB",
            notifications=NotificationSettings(
                gameStart=True,
                scoring=True,
                homerun=True,
                reversal=True,
                gameEnd=False,
                lineupOpened=True,
                inningChange=False,
                allGames=False,
            ),
        )
    )

    response = service.send_device_test(PushDeviceTestRequest(deviceToken="registered-token"))

    assert response["sent"] is True
    assert response["registered"] is True
    message = messaging.sent_messages[0]
    assert message.token == "registered-token"
    assert message.topic is None
    assert message.data["type"] == "test_push"
    assert message.data["route"] == "/diagnostics"
    assert message.apns.headers["apns-push-type"] == "alert"
    assert message.android.notification.channel_id == "remote_push_foreground"


def test_send_device_test_push_rejects_unregistered_token(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging()
    service._get_messaging = lambda: messaging

    response = service.send_device_test(PushDeviceTestRequest(deviceToken="missing-token"))

    assert response == {
        "sent": False,
        "registered": False,
        "reason": "device token is not registered",
    }
    assert messaging.sent_messages == []


def test_send_device_test_push_returns_failure_when_firebase_rejects(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging(send_error=RuntimeError("registration-token-not-registered"))
    service._get_messaging = lambda: messaging
    service.register(
        PushRegisterRequest(
            deviceToken="registered-token",
            platform="ios",
            myTeam="OB",
            notifications=NotificationSettings(
                gameStart=True,
                scoring=True,
                homerun=True,
                reversal=True,
                gameEnd=False,
                lineupOpened=True,
                inningChange=False,
                allGames=False,
            ),
        )
    )

    response = service.send_device_test(PushDeviceTestRequest(deviceToken="registered-token"))

    expected_reason = (
        "FCM 토큰이 만료되었거나 무효입니다. 앱을 완전히 종료한 뒤 다시 열고 다시 시도해주세요."
    )
    assert response == {
        "sent": False,
        "registered": True,
        "reason": expected_reason,
        "errorType": "RuntimeError",
        "debugReason": "registration-token-not-registered",
    }
    assert len(messaging.sent_messages) == 1
    assert registry.recent_device_test_results()[0]["reason"] == expected_reason
    assert registry.recent_device_test_results()[0]["debugReason"] == (
        "registration-token-not-registered"
    )


def test_send_device_test_push_classifies_ios_third_party_auth_as_apns_configuration(
    tmp_path,
) -> None:
    class ThirdPartyAuthError(RuntimeError):
        pass

    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging(
        send_error=ThirdPartyAuthError(
            "Request is missing required authentication credential. "
            "Expected OAuth 2 access token, login cookie or other valid authentication "
            "credential."
        )
    )
    service._get_messaging = lambda: messaging
    service.register(
        PushRegisterRequest(
            deviceToken="registered-token",
            platform="ios",
            myTeam="SS",
            notifications=NotificationSettings(
                gameStart=True,
                scoring=True,
                homerun=True,
                reversal=True,
                gameEnd=False,
                lineupOpened=True,
                inningChange=False,
                allGames=False,
            ),
        )
    )

    response = service.send_device_test(PushDeviceTestRequest(deviceToken="registered-token"))

    expected_reason = (
        "Firebase/APNs 인증 설정 문제로 iOS 원격 푸시를 발송하지 못했습니다. "
        "Firebase Console의 iOS 앱 Cloud Messaging APNs 키 확인이 필요합니다."
    )
    assert response["sent"] is False
    assert response["registered"] is True
    assert response["reason"] == expected_reason
    assert response["errorType"] == "ThirdPartyAuthError"
    assert registry.recent_device_test_results()[0]["reason"] == expected_reason


def test_send_device_test_push_classifies_generic_missing_oauth_as_admin_credential(
    tmp_path,
) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeFcmMessaging(
        send_error=RuntimeError(
            "Request is missing required authentication credential. "
            "Expected OAuth 2 access token, login cookie or other valid authentication "
            "credential."
        )
    )
    service._get_messaging = lambda: messaging
    service.register(
        PushRegisterRequest(
            deviceToken="registered-token",
            platform="ios",
            myTeam="SS",
            notifications=NotificationSettings(
                gameStart=True,
                scoring=True,
                homerun=True,
                reversal=True,
                gameEnd=False,
                lineupOpened=True,
                inningChange=False,
                allGames=False,
            ),
        )
    )

    response = service.send_device_test(PushDeviceTestRequest(deviceToken="registered-token"))

    expected_reason = (
        "Firebase Admin 인증 설정 문제로 원격 푸시를 발송하지 못했습니다. "
        "서버 Firebase 서비스 계정 확인이 필요합니다."
    )
    assert response["sent"] is False
    assert response["registered"] is True
    assert response["reason"] == expected_reason
    assert response["errorType"] == "RuntimeError"
    assert registry.recent_device_test_results()[0]["reason"] == expected_reason


def test_record_push_receipt_persists_registered_device_receipt(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    service.register(
        PushRegisterRequest(
            deviceToken="registered-token-123456",
            platform="ios",
            myTeam="OB",
            followedGameIds=["20260620HTKT0"],
            notifications=NotificationSettings(
                gameStart=True,
                scoring=True,
                homerun=True,
                reversal=True,
                gameEnd=False,
                lineupOpened=True,
                inningChange=False,
                allGames=False,
            ),
        )
    )

    response = service.record_receipt(
        PushReceiptRequest(
            deviceToken="registered-token-123456",
            messageId="projects/kbo-fans-47189/messages/receipt-1",
            source="foreground",
            type="hit",
            gameId="20260620HTKT0",
            route="/game/20260620HTKT0?tab=relay",
            receivedAt="2026-06-22T04:50:00Z",
            data={"topic": "hit_GAME_20260620HTKT0"},
        )
    )

    assert response["recorded"] is True
    assert response["registered"] is True
    receipts = registry.recent_push_receipts()
    assert len(receipts) == 1
    assert receipts[0]["deviceTokenSuffix"] == "n-123456"
    assert receipts[0]["myTeam"] == "OB"
    assert receipts[0]["followedGameIds"] == ["20260620HTKT0"]
    assert receipts[0]["messageId"] == "projects/kbo-fans-47189/messages/receipt-1"
    assert receipts[0]["source"] == "foreground"
    assert receipts[0]["type"] == "hit"
    assert receipts[0]["gameId"] == "20260620HTKT0"
    assert receipts[0]["route"] == "/game/20260620HTKT0?tab=relay"
    assert receipts[0]["data"] == {"topic": "hit_GAME_20260620HTKT0"}
    assert "deviceToken" not in receipts[0]


def test_record_push_receipt_rejects_unregistered_token(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())

    response = service.record_receipt(
        PushReceiptRequest(
            deviceToken="missing-token",
            messageId="message-1",
            source="foreground",
        )
    )

    assert response == {
        "recorded": False,
        "registered": False,
        "reason": "device token is not registered",
    }
    assert registry.recent_push_receipts() == []


def test_resubscribe_registered_topics_rebuilds_followed_game_topics(tmp_path) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry_path.write_text(
        json.dumps(
            {
                "devices": {
                    "fcm-token": {
                        "deviceToken": "fcm-token",
                        "platform": "ios",
                        "myTeam": "LG",
                        "notifications": {
                            "gameStart": True,
                            "scoring": True,
                            "homerun": True,
                            "reversal": True,
                            "gameEnd": True,
                            "lineupOpened": True,
                            "inningChange": False,
                            "allGames": False,
                        },
                        "followedGameIds": ["20260612KTLG0"],
                        "topics": ["game_start_LG", "scoring_LG", "legacy_LG"],
                        "updatedAt": "2026-06-18T00:00:00+00:00",
                    }
                },
                "liveActivities": {},
                "scoreboardStates": {},
                "relayStates": {},
                "syncHeartbeat": {},
            }
        ),
        encoding="utf-8",
    )
    registry = PushRegistry(str(registry_path))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    messaging = FakeTopicMessaging()
    service._get_messaging = lambda: messaging

    response = service.resubscribe_registered_topics()

    subscribed_topics = {call["topic"] for call in messaging.subscribe_calls}
    unsubscribed_topics = {call["topic"] for call in messaging.unsubscribe_calls}
    stored_topics = registry._load()["devices"]["fcm-token"]["topics"]
    stored_followed_game_ids = registry._load()["devices"]["fcm-token"]["followedGameIds"]
    stored_registration = registry._load()["devices"]["fcm-token"]

    assert response["resubscribed"] is True
    assert response["eligibleDevices"] == 1
    assert "at_bat_LG" in subscribed_topics
    assert "hit_LG" in subscribed_topics
    assert "game_start_soon_LG" in subscribed_topics
    assert "game_end_LG" in subscribed_topics
    assert "lineup_opened_LG" in subscribed_topics
    assert "baseball_info_LG" in subscribed_topics
    assert "game_start_LG" not in unsubscribed_topics
    assert "scoring_LG" not in unsubscribed_topics
    assert "legacy_LG" in unsubscribed_topics
    assert "at_bat_LG" in stored_topics
    assert "game_start_LG" in stored_topics
    assert "scoring_LG" in stored_topics
    assert "at_bat_GAME_20260612KTLG0" not in stored_topics
    assert "game_start_GAME_20260612KTLG0" not in stored_topics
    assert "scoring_GAME_20260612KTLG0" not in stored_topics
    assert "legacy_LG" not in stored_topics
    assert stored_followed_game_ids == ["20260612KTLG0"]
    assert stored_registration["updatedAt"] == "2026-06-18T00:00:00+00:00"
    assert stored_registration["topicsUpdatedAt"] != "2026-06-18T00:00:00+00:00"


def test_resubscribe_registered_topics_clears_missing_followed_game_ids(tmp_path) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry_path.write_text(
        json.dumps(
            {
                "devices": {
                    "fcm-token": {
                        "deviceToken": "fcm-token",
                        "platform": "ios",
                        "myTeam": "LG",
                        "notifications": {
                            "gameStart": True,
                            "scoring": True,
                            "homerun": True,
                            "reversal": True,
                            "gameEnd": True,
                            "lineupOpened": True,
                            "inningChange": False,
                            "allGames": False,
                        },
                        "topics": ["game_start_LG"],
                    }
                },
                "liveActivities": {},
                "scoreboardStates": {},
                "relayStates": {},
                "syncHeartbeat": {},
            }
        ),
        encoding="utf-8",
    )
    registry = PushRegistry(str(registry_path))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    service._get_messaging = lambda: FakeTopicMessaging()

    service.resubscribe_registered_topics()

    registration = registry.device_registrations()[0]
    assert registration["followedGameIds"] == []


def test_resubscribe_registered_topics_dry_run_does_not_call_firebase(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            myTeam="LG",
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
    )
    service._get_messaging = lambda: (_ for _ in ()).throw(AssertionError("called"))

    response = service.resubscribe_registered_topics(dry_run=True)

    assert response["dryRun"] is True
    assert response["subscriptionsAttempted"] > 0
    assert response["subscriptionResults"][0]["dryRun"] is True


def test_push_registry_serializes_writes_across_processes(tmp_path) -> None:
    registry_path = str(tmp_path / "push_registry.json")
    worker_count = 4
    registrations_per_worker = 12

    with ProcessPoolExecutor(max_workers=worker_count) as executor:
        futures = [
            executor.submit(
                _register_device_token_batch,
                registry_path,
                f"worker-{worker_index}",
                registrations_per_worker,
            )
            for worker_index in range(worker_count)
        ]

        total_registrations = sum(future.result(timeout=20) for future in futures)

    registry_data = PushRegistry(registry_path)._load()

    assert total_registrations == worker_count * registrations_per_worker
    assert len(registry_data["devices"]) == total_registrations


def test_push_registry_serializes_writes_across_instances_in_process(tmp_path) -> None:
    registry_path = str(tmp_path / "push_registry.json")
    worker_count = 4
    registrations_per_worker = 12

    with ThreadPoolExecutor(max_workers=worker_count) as executor:
        futures = [
            executor.submit(
                _register_device_token_batch,
                registry_path,
                f"thread-{worker_index}",
                registrations_per_worker,
            )
            for worker_index in range(worker_count)
        ]

        total_registrations = sum(future.result(timeout=20) for future in futures)

    registry_data = PushRegistry(registry_path)._load()

    assert total_registrations == worker_count * registrations_per_worker
    assert len(registry_data["devices"]) == total_registrations


def test_push_registry_shared_lock_uses_readable_lock_fd(monkeypatch, tmp_path) -> None:
    original_flock = fcntl.flock

    def asserting_flock(fd: int, operation: int) -> None:
        if operation & fcntl.LOCK_SH:
            os.read(fd, 1)
        original_flock(fd, operation)

    monkeypatch.setattr(fcntl, "flock", asserting_flock)

    heartbeat = PushRegistry(str(tmp_path / "push_registry.json")).sync_heartbeat()

    assert heartbeat == {}


def test_register_live_activity_replaces_previous_token(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())

    service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260604LGKT0",
            activityId="activity-1",
            activityPushToken="old-token",
        )
    )
    service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260604LGKT0",
            activityId="activity-1",
            activityPushToken="new-token",
            previousActivityPushToken="old-token",
        )
    )

    assert registry.live_activity_tokens_for_game("20260604LGKT0") == ["new-token"]


def test_register_live_activity_start_token_replaces_previous_token(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())

    service.register_live_activity_start_token(
        LiveActivityStartTokenRegisterRequest(
            pushToStartToken="old-start-token",
            installationId="install-1",
        )
    )
    service.register_live_activity_start_token(
        LiveActivityStartTokenRegisterRequest(
            pushToStartToken="new-start-token",
            previousPushToStartToken="old-start-token",
            installationId="install-1",
        )
    )

    data = registry._load()
    assert list(data["liveActivityStartTokens"]) == ["new-start-token"]
    assert registry.live_activity_start_token_count() == 1


def test_live_activity_start_registration_targets_my_team_ios_device(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            installationId="install-1",
            myTeam="LG",
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
            notificationsAllowed=True,
        )
    )
    service.register_live_activity_start_token(
        LiveActivityStartTokenRegisterRequest(
            pushToStartToken="start-token",
            installationId="install-1",
        )
    )

    registrations = registry.live_activity_start_registrations_for_game(
        game_id="20260604LGKT0",
        away_team_id="LG",
        home_team_id="KT",
    )

    assert [item["pushToStartToken"] for item in registrations] == ["start-token"]


def test_unregister_live_activity_by_activity_id(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260604LGKT0",
            activityId="activity-1",
            activityPushToken="token",
        )
    )

    response = service.unregister_live_activity(
        LiveActivityUnregisterRequest(gameId="20260604LGKT0", activityId="activity-1")
    )

    assert response["removed"] == 1
    assert registry.live_activity_tokens_for_game("20260604LGKT0") == []


def test_send_live_activity_update_uses_registered_tokens(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    sender = FakeLiveActivitySender()
    service = PushService(registry=registry, live_activity_sender=sender)
    service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260604LGKT0",
            activityId="activity-1",
            activityPushToken="token",
        )
    )

    response = service.send_live_activity_update(
        LiveActivityUpdateRequest(
            gameId="20260604LGKT0",
            state=_live_activity_state(),
        )
    )

    assert response["sent"] is True
    assert sender.calls[0]["activity_push_token"] == "token"
    assert sender.calls[0]["state"].homeScore == 3


def test_live_activity_scoreboard_sync_updates_registered_live_games(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    sender = FakeLiveActivitySender()
    push_service = PushService(registry=registry, live_activity_sender=sender)
    push_service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260604LGKT0",
            activityId="activity-1",
            activityPushToken="token",
        )
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardService(),
        push_service=push_service,
    )

    response = sync_service.sync_date("2026-06-04")

    assert response["checkedGames"] == 1
    assert response["updatedGames"][0]["sent"] is True
    assert sender.calls[0]["event"] == "update"
    assert sender.calls[0]["state"].inning == "7회말"
    assert registry.sync_heartbeat()["checkedGames"] == 1


def test_live_activity_scoreboard_sync_starts_my_team_live_activity_from_start_token(
    tmp_path,
) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    sender = FakeLiveActivitySender()
    push_service = PushService(registry=registry, live_activity_sender=sender)
    push_service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            installationId="install-1",
            myTeam="LG",
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
            notificationsAllowed=True,
        )
    )
    push_service.register_live_activity_start_token(
        LiveActivityStartTokenRegisterRequest(
            pushToStartToken="start-token",
            installationId="install-1",
        )
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardService(),
        push_service=push_service,
    )

    response = sync_service.sync_date("2026-06-04")
    second_response = sync_service.sync_date("2026-06-04")

    assert response["startedGames"][0]["sent"] is True
    assert sender.start_calls[0]["push_to_start_token"] == "start-token"
    assert sender.start_calls[0]["state"].inning == "7회말"
    assert sender.start_calls[0]["alert_title"] == "경기 시작"
    assert second_response["startedGames"] == []
    assert len(sender.start_calls) == 1


def test_live_activity_scoreboard_sync_starts_my_team_activity_ten_minutes_before_first_pitch(
    tmp_path,
) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    sender = FakeLiveActivitySender()
    push_service = PushService(registry=registry, live_activity_sender=sender)
    push_service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            installationId="install-1",
            myTeam="LG",
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
            notificationsAllowed=True,
        )
    )
    push_service.register_live_activity_start_token(
        LiveActivityStartTokenRegisterRequest(
            pushToStartToken="start-token",
            installationId="install-1",
        )
    )
    now = datetime(2026, 6, 4, 18, 20, tzinfo=timezone(timedelta(hours=9)))
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardSequenceService(
            [
                _scoreboard_game(
                    away_score=0,
                    home_score=0,
                    inning="18:30 예정",
                    status="SCHEDULED",
                    start_time="18:30",
                    lineup_opened=False,
                ),
                _scoreboard_game(
                    away_score=0,
                    home_score=0,
                    inning="18:30 예정",
                    status="SCHEDULED",
                    start_time="18:30",
                    lineup_opened=False,
                ),
            ]
        ),
        push_service=push_service,
        now_provider=lambda: now,
    )

    response = sync_service.sync_date("2026-06-04")
    second_response = sync_service.sync_date("2026-06-04")

    assert response["startedGames"][0]["sent"] is True
    assert sender.start_calls[0]["push_to_start_token"] == "start-token"
    assert sender.start_calls[0]["alert_title"] == "경기 곧 시작"
    assert sender.start_calls[0]["alert_body"] == "LG vs KT 경기가 곧 시작됩니다. 18:30 · 수원"
    assert sender.start_calls[0]["state"].isPregame is True
    assert sender.start_calls[0]["state"].inning == "경기전"
    assert second_response["startedGames"] == []
    assert len(sender.start_calls) == 1


def test_live_activity_scoreboard_sync_normalizes_team_codes(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    sender = FakeLiveActivitySender()
    push_service = PushService(registry=registry, live_activity_sender=sender)
    push_service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260624SSSK0",
            activityId="activity-1",
            activityPushToken="token",
        )
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardSequenceService(
            [
                _scoreboard_game(
                    game_id="20260624SSSK0",
                    away_team_id="SS",
                    away_short_name="SS",
                    home_team_id="SK",
                    home_short_name="SK",
                    away_score=4,
                    home_score=3,
                    inning="7회말",
                )
            ]
        ),
        push_service=push_service,
    )

    sync_service.sync_date("2026-06-24")

    state = sender.calls[0]["state"]
    assert state.awayTeam == "삼성"
    assert state.homeTeam == "SSG"


def test_live_activity_scoreboard_sync_updates_lineup_opened_pregame_with_ranks(
    tmp_path,
) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    sender = FakeLiveActivitySender()
    push_service = PushService(registry=registry, live_activity_sender=sender)
    push_service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260604LGKT0",
            activityId="activity-1",
            activityPushToken="token",
        )
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardSequenceService(
            [
                _scoreboard_game(
                    away_score=0,
                    home_score=0,
                    inning="18:30 예정",
                    status="SCHEDULED",
                    start_time="18:30",
                    lineup_opened=True,
                )
            ]
        ),
        push_service=push_service,
        standings_service=FakeStandingsService(),
    )

    response = sync_service.sync_date("2026-06-04")

    assert response["checkedGames"] == 1
    assert response["updatedGames"][0]["sent"] is True
    assert sender.calls[0]["event"] == "update"
    state = sender.calls[0]["state"]
    assert state.isPregame is True
    assert state.inning == "경기전"
    assert state.awayRankText == "2위"
    assert state.homeRankText == "5위"
    assert state.playText == ""


def test_live_activity_scoreboard_sync_enriches_current_at_bat_from_relay(
    tmp_path,
) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    sender = FakeLiveActivitySender()
    push_service = PushService(registry=registry, live_activity_sender=sender)
    push_service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260604LGKT0",
            activityId="activity-1",
            activityPushToken="token",
        )
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardService(),
        push_service=push_service,
        relay_service=FakeRelaySequenceService(
            [[]],
            [
                {
                    "inningText": "2회 초",
                    "batter": {"name": "디아즈", "average": "0.249"},
                    "pitcher": {
                        "name": "박준영",
                        "pitchCount": 38,
                        "era": "4.13",
                    },
                    "ballCount": {"balls": 1, "strikes": 2, "outs": 2},
                    "baseState": "주자2루",
                }
            ],
        ),
    )

    sync_service.sync_date("2026-06-04")

    state = sender.calls[0]["state"]
    assert state.inning == "2회 초"
    assert state.batter == "디아즈"
    assert state.batterAverage == "0.249"
    assert state.pitcher == "박준영"
    assert state.pitcherEra == "4.13"
    assert state.pitchCount == 38
    assert state.balls == 1
    assert state.strikes == 2
    assert state.outs == 2
    assert state.situationText == "2사 2루"


def test_live_activity_scoreboard_sync_clears_current_at_bat_for_final_update(
    tmp_path,
) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    sender = FakeLiveActivitySender()
    push_service = PushService(registry=registry, live_activity_sender=sender)
    push_service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260629SSLG0",
            activityId="activity-1",
            activityPushToken="token",
        )
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardSequenceService(
            [
                _scoreboard_game(
                    game_id="20260629SSLG0",
                    away_team_id="SS",
                    away_short_name="삼성",
                    home_team_id="LG",
                    home_short_name="LG",
                    away_score=3,
                    home_score=4,
                    inning="경기종료",
                    status="FINAL",
                    batter_name="디아즈",
                    pitcher_name="손주영",
                    balls=1,
                    strikes=3,
                    outs=3,
                )
            ]
        ),
        push_service=push_service,
    )

    response = sync_service.sync_date("2026-06-29")

    assert response["updatedGames"][0]["sent"] is True
    assert sender.calls[0]["event"] == "end"
    state = sender.calls[0]["state"]
    assert state.inning == "경기종료"
    assert state.batter == ""
    assert state.pitcher == ""
    assert state.pitchCount == 0
    assert state.balls == 0
    assert state.strikes == 0
    assert state.outs == 0
    assert state.situationText == ""


def test_scoreboard_sync_pushes_score_moments_after_baseline(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    sender = FakeLiveActivitySender()
    push_service = FakePushService(registry=registry, live_activity_sender=sender)
    push_service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            myTeam="LG",
            notifications=NotificationSettings(
                gameStart=True,
                scoring=True,
                homerun=True,
                reversal=True,
                gameEnd=True,
                lineupOpened=True,
                inningChange=True,
                allGames=False,
            ),
        )
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardSequenceService(
            [
                _scoreboard_game(away_score=2, home_score=3, inning="7회말"),
                _scoreboard_game(away_score=4, home_score=3, inning="8회초"),
            ]
        ),
        push_service=push_service,
    )

    first_response = sync_service.sync_date("2026-06-04")
    second_response = sync_service.sync_date("2026-06-04")

    assert first_response["pushedMoments"] == []
    assert [call["moment"] for call in push_service.moment_calls] == ["scoring", "reversal"]
    assert second_response["pushedMoments"][0]["moment"] == "scoring"
    assert push_service.moment_calls[0]["away_score"] == 4
    assert push_service.moment_calls[0]["home_score"] == 3


def test_scoreboard_sync_does_not_push_reversal_for_first_score(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    sender = FakeLiveActivitySender()
    push_service = FakePushService(registry=registry, live_activity_sender=sender)
    push_service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            myTeam="LG",
            notifications=NotificationSettings(
                gameStart=True,
                scoring=True,
                homerun=True,
                reversal=True,
                gameEnd=True,
                lineupOpened=True,
                inningChange=True,
                allGames=False,
            ),
        )
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardSequenceService(
            [
                _scoreboard_game(away_score=0, home_score=0, inning="1회초"),
                _scoreboard_game(away_score=1, home_score=0, inning="1회초"),
            ]
        ),
        push_service=push_service,
    )

    first_response = sync_service.sync_date("2026-06-04")
    second_response = sync_service.sync_date("2026-06-04")

    assert first_response["pushedMoments"] == []
    assert [call["moment"] for call in push_service.moment_calls] == ["scoring"]
    assert [moment["moment"] for moment in second_response["pushedMoments"]] == ["scoring"]


def test_scoreboard_sync_passes_cancelled_status_to_game_end_push(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    sender = FakeLiveActivitySender()
    push_service = FakePushService(registry=registry, live_activity_sender=sender)
    push_service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            myTeam="LG",
            notifications=NotificationSettings(
                gameStart=True,
                scoring=True,
                homerun=True,
                reversal=True,
                gameEnd=True,
                lineupOpened=True,
                inningChange=True,
                allGames=False,
            ),
        )
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardSequenceService(
            [
                _scoreboard_game(
                    away_score=0,
                    home_score=0,
                    inning="18:30",
                    status="SCHEDULED",
                ),
                _scoreboard_game(
                    away_score=0,
                    home_score=0,
                    inning="경기취소",
                    status="CANCELLED",
                ),
            ]
        ),
        push_service=push_service,
    )

    sync_service.sync_date("2026-06-04")
    response = sync_service.sync_date("2026-06-04")

    assert [call["moment"] for call in push_service.moment_calls] == ["game_end"]
    assert push_service.moment_calls[0]["game_status"] == "CANCELLED"
    assert response["pushedMoments"][0]["moment"] == "game_end"


def test_scoreboard_sync_pushes_inning_change_when_only_inning_changes(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    push_service = FakePushService(
        registry=registry,
        live_activity_sender=FakeLiveActivitySender(),
    )
    push_service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            myTeam="LG",
            notifications=NotificationSettings(
                gameStart=True,
                scoring=True,
                homerun=True,
                reversal=True,
                gameEnd=True,
                lineupOpened=True,
                inningChange=True,
                allGames=False,
            ),
        )
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardSequenceService(
            [
                _scoreboard_game(away_score=2, home_score=3, inning="7회말"),
                _scoreboard_game(away_score=2, home_score=3, inning="8회초"),
            ]
        ),
        push_service=push_service,
    )

    sync_service.sync_date("2026-06-04")
    response = sync_service.sync_date("2026-06-04")

    assert [call["moment"] for call in push_service.moment_calls] == ["inning_change"]
    assert response["pushedMoments"][0]["moment"] == "inning_change"


def test_scoreboard_sync_pushes_at_bat_when_current_batter_changes(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    push_service = FakePushService(
        registry=registry,
        live_activity_sender=FakeLiveActivitySender(),
    )
    push_service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            myTeam="LG",
            notifications=NotificationSettings(
                gameStart=True,
                scoring=True,
                homerun=True,
                reversal=True,
                gameEnd=True,
                lineupOpened=True,
                inningChange=True,
                allGames=False,
            ),
        )
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardSequenceService(
            [
                _scoreboard_game(
                    away_score=2,
                    home_score=3,
                    inning="7회말",
                    batter_name="문상철",
                    pitcher_name="김진성",
                ),
                _scoreboard_game(
                    away_score=2,
                    home_score=3,
                    inning="7회말",
                    batter_name="장성우",
                    pitcher_name="김진성",
                ),
            ]
        ),
        push_service=push_service,
    )

    sync_service.sync_date("2026-06-04")
    response = sync_service.sync_date("2026-06-04")

    assert [call["moment"] for call in push_service.moment_calls] == ["at_bat"]
    assert push_service.moment_calls[0]["batter_name"] == "장성우"
    assert push_service.moment_calls[0]["pitcher_name"] == "김진성"
    assert response["pushedMoments"][0]["moment"] == "at_bat"


def test_scoreboard_sync_pushes_homerun_from_new_relay_items(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    push_service = FakePushService(
        registry=registry,
        live_activity_sender=FakeLiveActivitySender(),
    )
    push_service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            myTeam="LG",
            notifications=NotificationSettings(
                gameStart=True,
                scoring=True,
                homerun=True,
                reversal=True,
                gameEnd=True,
                lineupOpened=True,
                inningChange=True,
                allGames=False,
            ),
        )
    )
    relay_service = FakeRelaySequenceService(
        [
            [
                {
                    "seqNo": 10,
                    "inning": 7,
                    "half": "bottom",
                    "event": "WALK",
                    "isScoring": False,
                    "text": "문상철 : 볼넷",
                    "pitchSequence": None,
                }
            ],
            [
                {
                    "seqNo": 11,
                    "inning": 7,
                    "half": "bottom",
                    "event": "HOMERUN",
                    "isScoring": True,
                    "text": "장성우 : 좌월 홈런",
                    "pitchSequence": None,
                }
            ],
        ],
        current_at_bat_by_call=[
            _current_at_bat(outs=1, base_state="주자1루"),
            _current_at_bat(outs=1, base_state="주자1,2루"),
        ],
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardSequenceService(
            [
                _scoreboard_game(away_score=2, home_score=3, inning="7회말"),
                _scoreboard_game(away_score=2, home_score=3, inning="7회말"),
            ]
        ),
        push_service=push_service,
        relay_service=relay_service,
    )

    first_response = sync_service.sync_date("2026-06-04")
    second_response = sync_service.sync_date("2026-06-04")

    assert first_response["pushedMoments"] == []
    assert relay_service.calls[1]["after"] == 10
    assert [call["moment"] for call in push_service.moment_calls] == ["homerun"]
    assert push_service.moment_calls[0]["batter_name"] == "장성우"
    assert push_service.moment_calls[0]["situation_text"] == "1사 1,2루"
    assert push_service.moment_calls[0]["play_text"] == "장성우 : 좌월 홈런"
    assert second_response["pushedMoments"][0]["moment"] == "homerun"


def test_scoreboard_sync_pushes_hit_with_base_out_situation_from_relay(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    push_service = FakePushService(
        registry=registry,
        live_activity_sender=FakeLiveActivitySender(),
    )
    push_service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            myTeam="LG",
            notifications=NotificationSettings(
                gameStart=True,
                scoring=True,
                hit=True,
                homerun=True,
                reversal=True,
                gameEnd=True,
                lineupOpened=True,
                inningChange=True,
                allGames=False,
            ),
        )
    )
    relay_service = FakeRelaySequenceService(
        [
            [
                {
                    "seqNo": 10,
                    "inning": 7,
                    "half": "bottom",
                    "event": "WALK",
                    "isScoring": False,
                    "text": "문상철 : 볼넷",
                    "pitchSequence": None,
                }
            ],
            [
                {
                    "seqNo": 11,
                    "inning": 7,
                    "half": "bottom",
                    "event": "HIT",
                    "isScoring": False,
                    "text": "장성우 : 좌전 안타",
                    "pitchSequence": None,
                }
            ],
        ],
        current_at_bat_by_call=[
            _current_at_bat(outs=1, base_state="주자1루"),
            _current_at_bat(outs=1, base_state="주자1,2루"),
        ],
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardSequenceService(
            [
                _scoreboard_game(away_score=2, home_score=3, inning="7회말"),
                _scoreboard_game(away_score=2, home_score=3, inning="7회말"),
            ]
        ),
        push_service=push_service,
        relay_service=relay_service,
    )

    first_response = sync_service.sync_date("2026-06-04")
    second_response = sync_service.sync_date("2026-06-04")

    assert first_response["pushedMoments"] == []
    assert [call["moment"] for call in push_service.moment_calls] == ["hit"]
    assert push_service.moment_calls[0]["batter_name"] == "장성우"
    assert push_service.moment_calls[0]["situation_text"] == "1사 1,2루"
    assert second_response["pushedMoments"][0]["moment"] == "hit"


def test_scoreboard_sync_rebaselines_stale_relay_state_without_backfill(
    tmp_path,
) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry_path.write_text(
        json.dumps(
            {
                "devices": {
                    "fcm-token": {
                        "deviceToken": "fcm-token",
                        "platform": "ios",
                        "myTeam": "LG",
                        "notifications": {
                            "gameStart": True,
                            "scoring": True,
                            "hit": True,
                            "homerun": True,
                            "reversal": True,
                            "gameEnd": True,
                            "lineupOpened": True,
                            "inningChange": True,
                            "allGames": False,
                        },
                        "topics": ["homerun_LG"],
                    }
                },
                "liveActivities": {},
                "scoreboardStates": {},
                "relayStates": {
                    "20260604LGKT0": {
                        "gameId": "20260604LGKT0",
                        "lastSeq": 10,
                        "updatedAt": "2026-06-04T08:30:00+00:00",
                    }
                },
                "syncHeartbeat": {},
            }
        ),
        encoding="utf-8",
    )
    registry = PushRegistry(str(registry_path))
    push_service = FakePushService(
        registry=registry,
        live_activity_sender=FakeLiveActivitySender(),
    )
    relay_service = FakeRelaySequenceService(
        [
            [
                {
                    "seqNo": 11,
                    "inning": 7,
                    "half": "bottom",
                    "event": "HOMERUN",
                    "isScoring": True,
                    "text": "장성우 : 좌월 홈런",
                    "pitchSequence": None,
                }
            ],
            [
                {
                    "seqNo": 12,
                    "inning": 7,
                    "half": "bottom",
                    "event": "HOMERUN",
                    "isScoring": True,
                    "text": "문상철 : 좌월 홈런",
                    "pitchSequence": None,
                }
            ],
        ],
        current_at_bat_by_call=[
            _current_at_bat(outs=1, base_state="주자1루"),
            _current_at_bat(outs=1, base_state="주자없음"),
        ],
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardSequenceService(
            [
                _scoreboard_game(away_score=2, home_score=3, inning="7회말"),
                _scoreboard_game(away_score=2, home_score=3, inning="7회말"),
            ]
        ),
        push_service=push_service,
        relay_service=relay_service,
        now_provider=lambda: datetime(2026, 6, 4, 9, 0, tzinfo=timezone.utc),
    )

    first_response = sync_service.sync_date("2026-06-04")
    second_response = sync_service.sync_date("2026-06-04")

    assert first_response["pushedMoments"] == []
    assert relay_service.calls[0]["after"] == 10
    assert [call["moment"] for call in push_service.moment_calls] == ["homerun"]
    assert push_service.moment_calls[0]["play_text"] == "문상철 : 좌월 홈런"
    assert second_response["pushedMoments"][0]["moment"] == "homerun"


def test_scoreboard_sync_pushes_game_start_soon_once_within_ten_minutes(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    push_service = FakePushService(
        registry=registry,
        live_activity_sender=FakeLiveActivitySender(),
    )
    push_service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            myTeam="LG",
            notifications=NotificationSettings(
                gameStart=True,
                scoring=True,
                hit=True,
                homerun=True,
                reversal=True,
                gameEnd=True,
                lineupOpened=True,
                inningChange=True,
                allGames=False,
            ),
        )
    )
    now = datetime(2026, 6, 4, 18, 20, tzinfo=timezone(timedelta(hours=9)))
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardSequenceService(
            [
                _scoreboard_game(
                    away_score=0,
                    home_score=0,
                    inning="18:30 예정",
                    status="SCHEDULED",
                    start_time="18:30",
                ),
                _scoreboard_game(
                    away_score=0,
                    home_score=0,
                    inning="18:30 예정",
                    status="SCHEDULED",
                    start_time="18:30",
                ),
            ]
        ),
        push_service=push_service,
        now_provider=lambda: now,
    )

    first_response = sync_service.sync_date("2026-06-04")
    second_response = sync_service.sync_date("2026-06-04")

    assert [call["moment"] for call in push_service.moment_calls] == ["game_start_soon"]
    assert push_service.moment_calls[0]["start_time"] == "18:30"
    assert push_service.moment_calls[0]["stadium"] == "수원"
    assert first_response["pushedMoments"][0]["moment"] == "game_start_soon"
    assert second_response["pushedMoments"] == []


def test_scoreboard_sync_pushes_lineup_opened_after_baseline(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    push_service = FakePushService(
        registry=registry,
        live_activity_sender=FakeLiveActivitySender(),
    )
    push_service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            myTeam="LG",
            notifications=NotificationSettings(
                gameStart=True,
                scoring=True,
                hit=True,
                homerun=True,
                reversal=True,
                gameEnd=True,
                lineupOpened=True,
                inningChange=True,
                allGames=False,
            ),
        )
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardSequenceService(
            [
                _scoreboard_game(
                    away_score=0,
                    home_score=0,
                    inning="18:30 예정",
                    status="SCHEDULED",
                    start_time="18:30",
                    lineup_opened=False,
                ),
                _scoreboard_game(
                    away_score=0,
                    home_score=0,
                    inning="18:30 예정",
                    status="SCHEDULED",
                    start_time="18:30",
                    lineup_opened=True,
                ),
            ]
        ),
        push_service=push_service,
    )

    first_response = sync_service.sync_date("2026-06-04")
    second_response = sync_service.sync_date("2026-06-04")

    assert first_response["pushedMoments"] == []
    assert [call["moment"] for call in push_service.moment_calls] == ["lineup_opened"]
    assert second_response["pushedMoments"][0]["moment"] == "lineup_opened"
    assert registry.pregame_alert_sent("20260604LGKT0", "lineup_opened") is True


def test_scoreboard_sync_rebaselines_stale_scoreboard_state_without_backfill(
    tmp_path,
) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry_path.write_text(
        json.dumps(
            {
                "devices": {
                    "fcm-token": {
                        "deviceToken": "fcm-token",
                        "platform": "ios",
                        "myTeam": "LG",
                        "notifications": {
                            "gameStart": True,
                            "scoring": True,
                            "hit": True,
                            "homerun": True,
                            "reversal": True,
                            "gameEnd": True,
                            "lineupOpened": True,
                            "inningChange": True,
                            "allGames": False,
                        },
                        "topics": ["lineup_opened_LG", "game_start_LG"],
                    }
                },
                "liveActivities": {},
                "scoreboardStates": {
                    "20260604LGKT0": {
                        "status": "SCHEDULED",
                        "lineupOpened": False,
                        "awayTeamId": "LG",
                        "awayTeam": "LG",
                        "homeTeamId": "KT",
                        "homeTeam": "KT",
                        "awayScore": 0,
                        "homeScore": 0,
                        "inning": "18:30 예정",
                        "batterName": "",
                        "pitcherName": "",
                        "situationText": "",
                        "playText": "",
                        "startTime": "18:30",
                        "stadium": "수원",
                        "gameId": "20260604LGKT0",
                        "updatedAt": "2026-06-04T08:30:00+00:00",
                    }
                },
                "relayStates": {},
                "syncHeartbeat": {},
            }
        ),
        encoding="utf-8",
    )
    registry = PushRegistry(str(registry_path))
    push_service = FakePushService(
        registry=registry,
        live_activity_sender=FakeLiveActivitySender(),
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardSequenceService(
            [
                _scoreboard_game(
                    away_score=0,
                    home_score=0,
                    inning="18:30 예정",
                    status="SCHEDULED",
                    start_time="18:30",
                    lineup_opened=True,
                ),
                _scoreboard_game(
                    away_score=0,
                    home_score=0,
                    inning="1회초",
                    status="LIVE",
                    start_time="18:30",
                    lineup_opened=True,
                ),
            ]
        ),
        push_service=push_service,
        now_provider=lambda: datetime(2026, 6, 4, 9, 0, tzinfo=timezone.utc),
    )

    first_response = sync_service.sync_date("2026-06-04")
    second_response = sync_service.sync_date("2026-06-04")

    assert first_response["pushedMoments"] == []
    assert [call["moment"] for call in push_service.moment_calls] == ["game_start"]
    assert second_response["pushedMoments"][0]["moment"] == "game_start"


def test_push_registry_tracks_multiple_pregame_alert_keys(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))

    registry.mark_pregame_alert_sent("20260604LGKT0", "lineup_opened")
    registry.mark_pregame_alert_sent(
        "20260604LGKT0",
        "game_start_soon:2026-06-04T18:30:00+09:00",
    )

    assert registry.pregame_alert_sent("20260604LGKT0", "lineup_opened") is True
    assert (
        registry.pregame_alert_sent(
            "20260604LGKT0",
            "game_start_soon:2026-06-04T18:30:00+09:00",
        )
        is True
    )


def test_push_config_status_reports_missing_release_secrets(tmp_path) -> None:
    settings = _settings(
        app_env="release",
        firebase_service_account_path=str(tmp_path / "missing-firebase.json"),
        push_registry_path=str(tmp_path / "runtime" / "push_registry.json"),
        apns_auth_key_path=str(tmp_path / "missing-apns.p8"),
        apns_use_sandbox=True,
        push_sync_secret="",
    )

    status = PushConfigurationDiagnostics(settings).status()

    assert status["ready"] is False
    assert status["readyForIphoneOnlyDemo"] is False
    assert "FIREBASE_SERVICE_ACCOUNT_PATH:file" in status["missing"]
    assert "APNS_AUTH_KEY_PATH:file" in status["missing"]
    assert "APNS_USE_SANDBOX=false" in status["missing"]
    assert "PUSH_SYNC_SECRET" in status["missing"]


def test_push_config_status_accepts_production_ready_paths(tmp_path) -> None:
    firebase_path = tmp_path / "firebase-service-account.json"
    apns_path = tmp_path / "AuthKey_TESTKEY.p8"
    firebase_path.write_text(_firebase_service_account_json(), encoding="utf-8")
    apns_path.write_text(
        "-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n", encoding="utf-8"
    )
    settings = _settings(
        app_env="release",
        firebase_service_account_path=str(firebase_path),
        push_registry_path=str(tmp_path / "runtime" / "push_registry.json"),
        apns_auth_key_path=str(apns_path),
        apns_use_sandbox=False,
        push_sync_secret="secret",
    )

    status = PushConfigurationDiagnostics(settings).status()

    assert status["ready"] is True
    assert status["readyForIphoneOnlyDemo"] is True
    assert status["missing"] == []
    assert status["firebase"]["serviceAccountFilename"] == "firebase-service-account.json"
    assert status["apns"]["authKeyFilename"] == "AuthKey_TESTKEY.p8"
    assert status["registry"]["parentWritable"] is True


def test_push_config_status_reports_redacted_registration_topics(tmp_path) -> None:
    firebase_path = tmp_path / "firebase-service-account.json"
    apns_path = tmp_path / "AuthKey_TESTKEY.p8"
    registry_path = tmp_path / "runtime" / "push_registry.json"
    firebase_path.write_text("{}", encoding="utf-8")
    apns_path.write_text(
        "-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n", encoding="utf-8"
    )
    registry = PushRegistry(str(registry_path))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    service._get_messaging = lambda: FakeFcmMessaging()
    service.register(
        PushRegisterRequest(
            deviceToken="secret-fcm-token",
            platform="ios",
            installationId="install-87654321",
            myTeam="OB",
            followedGameIds=["20260618KTOB0"],
            notificationsAllowed=True,
            authorizationStatus="authorized",
            apnsTokenReady=True,
            notifications=NotificationSettings(
                gameStart=True,
                scoring=True,
                hit=True,
                homerun=True,
                reversal=True,
                gameEnd=True,
                lineupOpened=True,
                inningChange=True,
                allGames=False,
            ),
        )
    )
    service.record_receipt(
        PushReceiptRequest(
            deviceToken="secret-fcm-token",
            messageId="message-1",
            source="foreground",
            type="hit",
            gameId="20260618KTOB0",
            route="/game/20260618KTOB0?tab=relay",
        )
    )
    service.send_device_test(PushDeviceTestRequest(deviceToken="secret-fcm-token"))
    settings = _settings(
        app_env="release",
        firebase_service_account_path=str(firebase_path),
        push_registry_path=str(registry_path),
        apns_auth_key_path=str(apns_path),
        apns_use_sandbox=False,
        push_sync_secret="secret",
    )

    status = PushConfigurationDiagnostics(settings).status()

    assert status["registry"]["registeredDeviceCount"] == 1
    assert status["registry"]["followedGameCount"] == 1
    assert status["registry"]["topicCounts"]["game_start_soon_OB"] == 1
    assert status["registry"]["topicCounts"]["hit_OB"] == 1
    assert "game_start_soon_GAME_20260618KTOB0" not in status["registry"]["topicCounts"]
    assert "hit_GAME_20260618KTOB0" not in status["registry"]["topicCounts"]
    assert status["registry"]["deviceSummaries"] == [
        {
            "deviceTokenSuffix": "cm-token",
            "installationIdSuffix": "87654321",
            "platform": "ios",
            "myTeam": "OB",
            "followedGameIds": ["20260618KTOB0"],
            "topicCount": 11,
            "updatedAt": status["registry"]["deviceSummaries"][0]["updatedAt"],
            "topicsUpdatedAt": "",
            "notificationsAllowed": True,
            "authorizationStatus": "authorized",
            "apnsTokenReady": True,
        }
    ]
    assert status["registry"]["pushReceiptCount"] == 1
    assert status["registry"]["recentPushReceipts"][0]["type"] == "hit"
    assert status["registry"]["recentPushReceipts"][0]["deviceTokenSuffix"] == "cm-token"
    assert status["registry"]["deviceTestResultCount"] == 1
    assert status["registry"]["recentDeviceTestResults"][0]["sent"] is True
    assert status["registry"]["recentDeviceTestResults"][0]["deviceTokenSuffix"] == "cm-token"
    assert "secret-fcm-token" not in str(status["registry"])


def test_push_config_status_accepts_aws_secret_env_content(tmp_path) -> None:
    registry_path = tmp_path / "runtime" / "push_registry.json"
    PushRegistry(str(registry_path)).record_sync_heartbeat(
        {
            "date": "2026-06-04",
            "checkedGames": 1,
            "updatedGames": 1,
            "pushedMoments": 0,
        }
    )
    settings = _settings(
        app_env="release",
        firebase_service_account_path="",
        firebase_service_account_json=_firebase_service_account_json(),
        push_registry_path=str(registry_path),
        apns_auth_key_path="",
        apns_auth_key_p8="-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n",
        apns_use_sandbox=False,
        push_sync_secret="secret",
    )

    status = PushConfigurationDiagnostics(settings).status()

    assert status["ready"] is True
    assert status["readyForIphoneOnlyDemo"] is True
    assert status["missing"] == []
    assert status["firebase"]["serviceAccountJsonConfigured"] is True
    assert status["firebase"]["serviceAccountJsonValid"] is True
    assert status["firebase"]["serviceAccountJsonHasRequiredFields"] is True
    assert status["apns"]["authKeyContentConfigured"] is True
    assert status["scheduler"]["lastSyncDate"] == "2026-06-04"
    assert status["scheduler"]["lastCheckedGames"] == 1


def test_push_config_status_rejects_firebase_json_missing_admin_fields(tmp_path) -> None:
    settings = _settings(
        app_env="release",
        firebase_service_account_path="",
        firebase_service_account_json='{"project_id":"kbo-fans"}',
        push_registry_path=str(tmp_path / "runtime" / "push_registry.json"),
        apns_auth_key_path="",
        apns_auth_key_p8="-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n",
        apns_use_sandbox=False,
        push_sync_secret="secret",
    )

    status = PushConfigurationDiagnostics(settings).status()

    assert status["ready"] is False
    assert "FIREBASE_SERVICE_ACCOUNT_JSON:service-account-fields" in status["missing"]
    assert status["firebase"]["serviceAccountJsonValid"] is True
    assert status["firebase"]["serviceAccountJsonHasRequiredFields"] is False


def test_push_config_status_reports_registry_read_error(monkeypatch, tmp_path) -> None:
    def raise_permission_error(self) -> dict:
        raise PermissionError("registry unavailable")

    monkeypatch.setattr(PushRegistry, "sync_heartbeat", raise_permission_error)
    settings = _settings(
        app_env="release",
        firebase_service_account_path="",
        firebase_service_account_json='{"project_id":"kbo-fans"}',
        push_registry_path=str(tmp_path / "runtime" / "push_registry.json"),
        apns_auth_key_path="",
        apns_auth_key_p8="-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n",
        apns_use_sandbox=False,
        push_sync_secret="secret",
    )

    status = PushConfigurationDiagnostics(settings).status()

    assert status["ready"] is False
    assert "PUSH_REGISTRY_PATH:readable" in status["missing"]
    assert status["scheduler"]["registryReadable"] is False
    assert status["scheduler"]["registryError"] == "PermissionError"


def test_push_config_status_rejects_invalid_firebase_json(tmp_path) -> None:
    settings = _settings(
        app_env="release",
        firebase_service_account_path="",
        firebase_service_account_json="{invalid-json",
        push_registry_path=str(tmp_path / "runtime" / "push_registry.json"),
        apns_auth_key_path="",
        apns_auth_key_p8="-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n",
        apns_use_sandbox=False,
        push_sync_secret="secret",
    )

    status = PushConfigurationDiagnostics(settings).status()

    assert status["ready"] is False
    assert "FIREBASE_SERVICE_ACCOUNT_JSON:json" in status["missing"]


def test_push_config_status_endpoint_uses_sync_secret(monkeypatch) -> None:
    class SecretSettings:
        push_sync_secret = "secret"

    monkeypatch.setattr(push_routes, "get_settings", lambda: SecretSettings())
    monkeypatch.setattr(push_routes.diagnostics_service, "status", lambda: {"ready": True})
    client = TestClient(app)

    denied = client.get("/api/push/config-status")
    allowed = client.get(
        "/api/push/config-status",
        headers={"X-Kbo-Push-Sync-Secret": "secret"},
    )

    assert denied.status_code == 401
    assert allowed.status_code == 200
    assert allowed.json()["data"]["ready"] is True


def test_resubscribe_topics_endpoint_uses_sync_secret(monkeypatch) -> None:
    class SecretSettings:
        push_sync_secret = "secret"

    captured = {}

    class FakeService:
        def resubscribe_registered_topics(self, *, dry_run: bool) -> dict:
            captured["dry_run"] = dry_run
            return {"resubscribed": not dry_run, "dryRun": dry_run}

    monkeypatch.setattr(push_routes, "get_settings", lambda: SecretSettings())
    monkeypatch.setattr(push_routes, "service", FakeService())
    client = TestClient(app)

    denied = client.post("/api/push/resubscribe-topics")
    allowed = client.post(
        "/api/push/resubscribe-topics?dry_run=true",
        headers={"X-Kbo-Push-Sync-Secret": "secret"},
    )

    assert denied.status_code == 401
    assert allowed.status_code == 200
    assert captured["dry_run"] is True
    assert allowed.json()["data"]["dryRun"] is True


def test_send_test_push_endpoint_uses_sync_secret(monkeypatch) -> None:
    class SecretSettings:
        push_sync_secret = "secret"

    captured = {}

    class FakeService:
        def send_test(self, payload) -> dict:
            captured["topic"] = payload.topic
            return {"sent": True, "target": f"topic:{payload.topic}"}

    monkeypatch.setattr(push_routes, "get_settings", lambda: SecretSettings())
    monkeypatch.setattr(push_routes, "service", FakeService())
    client = TestClient(app)
    body = {"title": "안타", "body": "테스트", "topic": "hit_OB"}

    denied = client.post("/api/push/test", json=body)
    allowed = client.post(
        "/api/push/test",
        json=body,
        headers={"X-Kbo-Push-Sync-Secret": "secret"},
    )

    assert denied.status_code == 401
    assert allowed.status_code == 200
    assert captured["topic"] == "hit_OB"
    assert allowed.json()["data"]["sent"] is True


def test_send_test_push_endpoint_requires_configured_sync_secret(monkeypatch) -> None:
    class LocalSettings:
        push_sync_secret = ""

    class FakeService:
        def send_test(self, payload) -> dict:
            raise AssertionError("send_test should not run without PUSH_SYNC_SECRET")

    monkeypatch.setattr(push_routes, "get_settings", lambda: LocalSettings())
    monkeypatch.setattr(push_routes, "service", FakeService())
    client = TestClient(app)
    body = {"title": "안타", "body": "테스트", "topic": "hit_OB"}

    response = client.post("/api/push/test", json=body)

    assert response.status_code == 503
    assert response.json()["detail"] == "Push sync secret is not configured"


def test_send_device_test_push_endpoint_does_not_require_sync_secret(monkeypatch) -> None:
    captured = {}

    class FakeService:
        def send_device_test(self, payload) -> dict:
            captured["deviceToken"] = payload.deviceToken
            return {"sent": True, "registered": True, "target": "token"}

    monkeypatch.setattr(push_routes, "service", FakeService())
    client = TestClient(app)

    response = client.post(
        "/api/push/test-device",
        json={"deviceToken": "registered-token"},
    )

    assert response.status_code == 200
    assert captured["deviceToken"] == "registered-token"
    assert response.json()["data"]["sent"] is True


def test_record_push_receipt_endpoint_does_not_require_sync_secret(monkeypatch) -> None:
    captured = {}

    class FakeService:
        def record_receipt(self, payload) -> dict:
            captured["deviceToken"] = payload.deviceToken
            captured["source"] = payload.source
            return {"recorded": True, "registered": True}

    monkeypatch.setattr(push_routes, "service", FakeService())
    client = TestClient(app)

    response = client.post(
        "/api/push/receipt",
        json={
            "deviceToken": "registered-token",
            "messageId": "message-1",
            "source": "foreground",
            "type": "hit",
            "gameId": "20260620HTKT0",
        },
    )

    assert response.status_code == 200
    assert captured == {"deviceToken": "registered-token", "source": "foreground"}
    assert response.json()["data"]["recorded"] is True


def test_push_config_status_allows_missing_sync_secret_for_diagnostics(monkeypatch) -> None:
    class LocalSettings:
        push_sync_secret = ""

    monkeypatch.setattr(push_routes, "get_settings", lambda: LocalSettings())
    monkeypatch.setattr(
        push_routes.diagnostics_service,
        "status",
        lambda: {"ready": False, "missing": ["PUSH_SYNC_SECRET"]},
    )
    client = TestClient(app)

    response = client.get("/api/push/config-status")

    assert response.status_code == 200
    assert response.json()["data"]["missing"] == ["PUSH_SYNC_SECRET"]


def test_send_baseball_info_endpoint_uses_sync_secret(monkeypatch) -> None:
    class SecretSettings:
        push_sync_secret = "secret"

    captured = {}

    class FakeService:
        def send_baseball_info(self, **kwargs) -> dict:
            captured.update(kwargs)
            return {"sent": True, "kind": kwargs["kind"]}

    monkeypatch.setattr(push_routes, "get_settings", lambda: SecretSettings())
    monkeypatch.setattr(push_routes, "service", FakeService())
    client = TestClient(app)
    body = {"kind": "weekly_check", "date": "2026-06-22", "dryRun": True}

    denied = client.post("/api/push/baseball-info", json=body)
    allowed = client.post(
        "/api/push/baseball-info",
        json=body,
        headers={"X-Kbo-Push-Sync-Secret": "secret"},
    )

    assert denied.status_code == 401
    assert allowed.status_code == 200
    assert captured["kind"] == "weekly_check"
    assert captured["date"] == "2026-06-22"
    assert captured["dry_run"] is True
    assert allowed.json()["data"]["sent"] is True


def test_sync_scoreboard_endpoint_defaults_to_kbo_game_day(monkeypatch) -> None:
    class SecretSettings:
        push_sync_secret = "secret"

    captured = {}

    class FakeSyncService:
        def sync_date(self, target_date: str) -> dict:
            captured["date"] = target_date
            return {"date": target_date, "checkedGames": 0}

    monkeypatch.setattr(push_routes, "get_settings", lambda: SecretSettings())
    monkeypatch.setattr(push_routes, "current_kbo_date", lambda: "2026-06-04")
    monkeypatch.setattr(push_routes, "live_activity_sync_service", FakeSyncService())
    client = TestClient(app)

    response = client.post(
        "/api/push/live-activity/sync-scoreboard",
        headers={"X-Kbo-Push-Sync-Secret": "secret"},
    )

    assert response.status_code == 200
    assert captured["date"] == "2026-06-04"
    assert response.json()["data"]["date"] == "2026-06-04"


def test_apns_live_activity_payload_matches_ios_content_state_contract(tmp_path) -> None:
    settings = _settings(
        app_env="release",
        firebase_service_account_path="",
        push_registry_path=str(tmp_path / "runtime" / "push_registry.json"),
        apns_auth_key_path="",
        apns_use_sandbox=False,
        push_sync_secret="secret",
        apns_auth_key_p8="-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n",
    )
    sender = ApnsLiveActivitySender(settings)
    state = LiveActivityContentState(
        awayTeamId="LG",
        awayTeam="LG",
        homeTeamId="KT",
        homeTeam="KT",
        awayScore=4,
        homeScore=3,
        inning="8회초",
        batter="김현수",
        batterAverage="0.312",
        pitcher="고영표",
        pitcherEra="3.21",
        pitchCount=84,
        balls=2,
        strikes=1,
        outs=1,
        stadium="수원",
        updatedAt="21:20:30",
    )

    payload = sender._build_payload(
        state=state,
        event="update",
        stale_date=1_780_000_120,
        dismissal_date=None,
        relevance_score=100,
    )

    content_state = payload["aps"]["content-state"]
    assert set(content_state) == {
        "awayTeamId",
        "awayTeam",
        "homeTeamId",
        "homeTeam",
        "awayScore",
        "homeScore",
        "inning",
        "batter",
        "batterAverage",
        "pitcher",
        "pitcherEra",
        "pitchCount",
        "balls",
        "strikes",
        "outs",
        "stadium",
        "updatedAt",
        "situationText",
        "playText",
        "isPregame",
        "awayRankText",
        "homeRankText",
    }
    assert content_state["awayScore"] == 4
    assert content_state["homeScore"] == 3
    assert content_state["batterAverage"] == "0.312"
    assert content_state["pitcherEra"] == "3.21"
    assert content_state["pitchCount"] == 84
    assert content_state["updatedAt"] == "21:20:30"
    assert payload["aps"]["event"] == "update"
    assert payload["aps"]["stale-date"] == 1_780_000_120
    assert payload["aps"]["relevance-score"] == 100
    assert "dismissal-date" not in payload["aps"]


def test_apns_live_activity_start_payload_includes_activity_attributes(tmp_path) -> None:
    settings = _settings(
        app_env="release",
        firebase_service_account_path="",
        push_registry_path=str(tmp_path / "runtime" / "push_registry.json"),
        apns_auth_key_path="",
        apns_use_sandbox=False,
        push_sync_secret="secret",
        apns_auth_key_p8="-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n",
    )
    sender = ApnsLiveActivitySender(settings)

    payload = sender._build_start_payload(
        game_id="20260604LGKT0",
        state=_live_activity_state(),
        alert_title="경기 시작",
        alert_body="LG vs KT 경기가 시작됐습니다.",
        stale_date=1_780_000_120,
        relevance_score=100,
    )

    aps = payload["aps"]
    assert aps["event"] == "start"
    assert aps["attributes-type"] == "KboFansScoreAttributes"
    assert aps["attributes"] == {"gameId": "20260604LGKT0"}
    assert aps["alert"] == {
        "title": "경기 시작",
        "body": "LG vs KT 경기가 시작됐습니다.",
    }
    assert aps["input-push-token"] == 1
    assert aps["content-state"]["homeScore"] == 3


class FakeLiveActivitySender:
    def __init__(self) -> None:
        self.calls = []
        self.start_calls = []

    def send(self, **kwargs):
        self.calls.append(kwargs)
        return {"sent": True, "apnsId": "apns-id", "statusCode": 200}

    def send_start(self, **kwargs):
        self.start_calls.append(kwargs)
        return {"sent": True, "apnsId": "apns-start-id", "statusCode": 200}


class FakeTopicResponse:
    def __init__(self, *, success_count: int, failure_count: int = 0) -> None:
        self.success_count = success_count
        self.failure_count = failure_count
        self.errors = []


class FakeTopicMessaging:
    def __init__(self) -> None:
        self.subscribe_calls = []
        self.unsubscribe_calls = []

    def subscribe_to_topic(self, tokens, topic):
        self.subscribe_calls.append({"tokens": list(tokens), "topic": topic})
        return FakeTopicResponse(success_count=len(tokens))

    def unsubscribe_from_topic(self, tokens, topic):
        self.unsubscribe_calls.append({"tokens": list(tokens), "topic": topic})
        return FakeTopicResponse(success_count=len(tokens))


class FakeFcmNotification:
    def __init__(self, *, title: str, body: str) -> None:
        self.title = title
        self.body = body


class FakeFcmApsAlert:
    def __init__(self, *, title: str, body: str) -> None:
        self.title = title
        self.body = body


class FakeFcmAps:
    def __init__(self, *, sound: str, content_available: bool = False, alert=None) -> None:
        self.sound = sound
        self.content_available = content_available
        self.alert = alert


class FakeFcmApnsPayload:
    def __init__(self, *, aps: FakeFcmAps) -> None:
        self.aps = aps


class FakeFcmApnsConfig:
    def __init__(self, *, headers, payload: FakeFcmApnsPayload) -> None:
        self.headers = headers
        self.payload = payload


class FakeFcmAndroidNotification:
    def __init__(self, *, sound: str, channel_id: str = "") -> None:
        self.sound = sound
        self.channel_id = channel_id


class FakeFcmAndroidConfig:
    def __init__(self, *, priority: str, notification: FakeFcmAndroidNotification) -> None:
        self.priority = priority
        self.notification = notification


class FakeFcmMessage:
    def __init__(
        self,
        *,
        notification,
        data=None,
        topic=None,
        token=None,
        apns=None,
        android=None,
    ) -> None:
        self.notification = notification
        self.data = data or {}
        self.topic = topic
        self.token = token
        self.apns = apns
        self.android = android


class FakeFcmMessaging:
    Notification = FakeFcmNotification
    Message = FakeFcmMessage
    ApsAlert = FakeFcmApsAlert
    Aps = FakeFcmAps
    APNSPayload = FakeFcmApnsPayload
    APNSConfig = FakeFcmApnsConfig
    AndroidNotification = FakeFcmAndroidNotification
    AndroidConfig = FakeFcmAndroidConfig

    def __init__(self, send_error=None) -> None:
        self.sent_messages = []
        self.send_error = send_error

    def send(self, message) -> str:
        self.sent_messages.append(message)
        if self.send_error is not None:
            raise self.send_error
        return f"message-{len(self.sent_messages)}"


class FakePushService(PushService):
    def __init__(self, *, registry, live_activity_sender) -> None:
        super().__init__(registry=registry, live_activity_sender=live_activity_sender)
        self.moment_calls = []

    def send_game_moment(self, **kwargs):
        self.moment_calls.append(kwargs)
        return {
            "sent": True,
            "moment": kwargs["moment"],
            "messages": [
                {"topic": f"{kwargs['moment']}_{kwargs['away_team_id']}", "messageId": "away"},
                {"topic": f"{kwargs['moment']}_{kwargs['home_team_id']}", "messageId": "home"},
                {"topic": f"{kwargs['moment']}_ALL", "messageId": "all"},
            ],
        }


class FakeScoreboardService:
    def get_home_scoreboard(self, date: str):
        return {
            "date": date,
            "games": [_scoreboard_game(away_score=2, home_score=3, inning="7회말")],
        }


class FakeScoreboardSequenceService:
    def __init__(self, games) -> None:
        self.games = games
        self.index = 0

    def get_home_scoreboard(self, date: str):
        game = self.games[min(self.index, len(self.games) - 1)]
        self.index += 1
        return {"date": date, "games": [game]}


class FakeRelaySequenceService:
    def __init__(self, relay_items_by_call, current_at_bat_by_call=None) -> None:
        self.relay_items_by_call = relay_items_by_call
        self.current_at_bat_by_call = current_at_bat_by_call or []
        self.index = 0
        self.calls = []

    def get_relay(self, game_id: str, after=None):
        self.calls.append({"game_id": game_id, "after": after})
        call_index = self.index
        relay_items = self.relay_items_by_call[min(self.index, len(self.relay_items_by_call) - 1)]
        self.index += 1
        current_at_bat = None
        if self.current_at_bat_by_call:
            current_at_bat = self.current_at_bat_by_call[
                min(call_index, len(self.current_at_bat_by_call) - 1)
            ]
        if after is not None:
            relay_items = [item for item in relay_items if item["seqNo"] > after]
        return {
            "gameId": game_id,
            "currentAtBat": current_at_bat,
            "relayItems": relay_items,
        }


class FakeStandingsService:
    def get_standings(self, season: int):
        return {
            "season": season,
            "standings": [
                {"teamId": "LG", "rank": 2, "teamName": "LG 트윈스"},
                {"teamId": "KT", "rank": 5, "teamName": "KT 위즈"},
            ],
        }


def _register_device_token_batch(
    registry_path: str,
    token_prefix: str,
    count: int,
) -> int:
    registry = PushRegistry(registry_path)
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    for index in range(count):
        service.register(
            PushRegisterRequest(
                deviceToken=f"{token_prefix}-{index}",
                platform="ios",
                myTeam="LG",
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
        )
    return count


def _scoreboard_game(
    *,
    game_id: str = "20260604LGKT0",
    away_team_id: str = "LG",
    away_short_name: str = "LG",
    home_team_id: str = "KT",
    home_short_name: str = "KT",
    away_score: int,
    home_score: int,
    inning: str,
    status: str = "LIVE",
    start_time: str = "",
    batter_name: str = "",
    pitcher_name: str = "",
    balls: int = 0,
    strikes: int = 0,
    outs: int = 0,
    lineup_opened: bool = False,
) -> dict:
    return {
        "gameId": game_id,
        "status": status,
        "inning": inning,
        "stadium": "수원",
        "startTime": start_time,
        "lineupOpened": lineup_opened,
        "current": {
            "batterName": batter_name,
            "pitcherName": pitcher_name,
            "balls": balls,
            "strikes": strikes,
            "outs": outs,
        },
        "away": {
            "teamId": away_team_id,
            "shortName": away_short_name,
            "score": away_score,
        },
        "home": {
            "teamId": home_team_id,
            "shortName": home_short_name,
            "score": home_score,
        },
    }


def _current_at_bat(*, outs: int, base_state: str) -> dict:
    return {
        "inningText": "7회말",
        "batter": {"name": "장성우"},
        "pitcher": {"name": "김진성"},
        "ballCount": {"balls": 0, "strikes": 0, "outs": outs},
        "baseState": base_state,
    }


def _live_activity_state() -> LiveActivityContentState:
    return LiveActivityContentState(
        awayTeamId="LG",
        awayTeam="LG",
        homeTeamId="KT",
        homeTeam="KT",
        awayScore=2,
        homeScore=3,
        inning="7회말",
        stadium="수원",
        updatedAt="21:10:00",
    )


def _firebase_service_account_json(*, project_id: str = "kbo-fans") -> str:
    return json.dumps(
        {
            "type": "service_account",
            "project_id": project_id,
            "private_key": "-----BEGIN PRIVATE KEY-----\nTEST\n-----END PRIVATE KEY-----\n",
            "client_email": f"firebase-adminsdk@example.{project_id}.iam.gserviceaccount.com",
        }
    )


def _settings(
    *,
    app_env: str,
    firebase_service_account_path: str,
    push_registry_path: str,
    apns_auth_key_path: str,
    apns_use_sandbox: bool,
    push_sync_secret: str,
    firebase_service_account_json: str = "",
    apns_auth_key_p8: str = "",
) -> Settings:
    return Settings(
        app_name="KBO Fans API",
        app_env=app_env,
        debug=False,
        api_prefix="/api",
        request_timeout_seconds=10,
        kbo_base_url="https://www.koreabaseball.com",
        cors_allow_origin_regex=r"^https?://localhost$",
        kbo_relay_user_id="",
        kbo_relay_password="",
        firebase_service_account_path=firebase_service_account_path,
        firebase_service_account_json=firebase_service_account_json,
        firebase_project_id="kbo-fans",
        push_registry_path=push_registry_path,
        push_sync_secret=push_sync_secret,
        apns_key_id="TESTKEY",
        apns_team_id="TEAMID",
        apns_bundle_id="com.kbofans.kboFans",
        apns_auth_key_path=apns_auth_key_path,
        apns_auth_key_p8=apns_auth_key_p8,
        apns_use_sandbox=apns_use_sandbox,
        snapshot_dir="",
    )
