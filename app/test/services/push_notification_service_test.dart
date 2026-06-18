import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/services/push_notification_service.dart';

void main() {
  test('마이팀이 없고 allGames가 꺼져 있으면 토픽을 만들지 않는다', () {
    const settings = PushNotificationSettings.defaults();

    final topics = buildPushTopics(settings: settings, myTeam: null);

    expect(topics, isEmpty);
  });

  test('마이팀이 있으면 팀별 토픽만 만든다', () {
    const settings = PushNotificationSettings.defaults();

    final topics = buildPushTopics(settings: settings, myTeam: 'LG');

    expect(topics, contains('scoring_LG'));
    expect(topics, contains('homerun_LG'));
    expect(topics, contains('reversal_LG'));
    expect(topics, contains('game_start_LG'));
    expect(topics, contains('game_start_soon_LG'));
    expect(topics, contains('hit_LG'));
    expect(topics, contains('at_bat_LG'));
    expect(topics, isNot(contains('game_end_LG')));
    expect(topics, isNot(contains('game_start_ALL')));
    expect(topics, isNot(contains('all_games_enabled')));
  });

  test('allGames가 켜져 있으면 ALL 토픽과 플래그를 만든다', () {
    final settings = const PushNotificationSettings.defaults().copyWith(
      allGames: true,
    );

    final topics = buildPushTopics(settings: settings, myTeam: 'LG');

    expect(topics, contains('scoring_ALL'));
    expect(topics, contains('homerun_ALL'));
    expect(topics, contains('reversal_ALL'));
    expect(topics, contains('game_start_ALL'));
    expect(topics, contains('game_start_soon_ALL'));
    expect(topics, contains('hit_ALL'));
    expect(topics, contains('at_bat_ALL'));
    expect(topics, contains('all_games_enabled'));
    expect(topics, isNot(contains('scoring_LG')));
  });

  test('release 앱에서 마이팀이 있으면 자동 푸시 권한 요청 대상이다', () {
    expect(
      shouldAutoRequestPushPermission(
        isWeb: false,
        isLocal: false,
        alreadyRequested: false,
        myTeam: 'LG',
      ),
      isTrue,
    );
  });

  test('local 또는 마이팀 없음 또는 이미 요청한 경우 자동 푸시 권한을 요청하지 않는다', () {
    expect(
      shouldAutoRequestPushPermission(
        isWeb: false,
        isLocal: true,
        alreadyRequested: false,
        myTeam: 'LG',
      ),
      isFalse,
    );
    expect(
      shouldAutoRequestPushPermission(
        isWeb: false,
        isLocal: false,
        alreadyRequested: false,
        myTeam: null,
      ),
      isFalse,
    );
    expect(
      shouldAutoRequestPushPermission(
        isWeb: false,
        isLocal: false,
        alreadyRequested: true,
        myTeam: 'LG',
      ),
      isFalse,
    );
  });

  test('summary 또는 liveOnly delivery는 즉시 push 토픽을 만들지 않는다', () {
    final settings = const PushNotificationSettings.defaults().copyWith(
      scoringDelivery: PushNotificationDelivery.summary,
      hitDelivery: PushNotificationDelivery.off,
      homerunDelivery: PushNotificationDelivery.liveOnly,
      reversalDelivery: PushNotificationDelivery.off,
      gameEndDelivery: PushNotificationDelivery.immediate,
    );

    final topics = buildPushTopics(settings: settings, myTeam: 'LG');

    expect(topics, contains('game_end_LG'));
    expect(topics, isNot(contains('scoring_LG')));
    expect(topics, isNot(contains('hit_LG')));
    expect(topics, isNot(contains('homerun_LG')));
    expect(topics, isNot(contains('reversal_LG')));
  });

  test('push 등록 payload는 현재 따라가는 경기 id를 포함한다', () {
    const settings = PushNotificationSettings.defaults();

    final payload = buildPushRegistrationPayload(
      deviceToken: 'fcm-token',
      platform: 'ios',
      myTeam: 'LG',
      settings: settings,
      followedGameIds: const ['20260612KTLG0', '  ', '20260612KTLG0'],
    );

    expect(payload['deviceToken'], 'fcm-token');
    expect(payload['myTeam'], 'LG');
    expect(payload['followedGameIds'], ['20260612KTLG0']);
  });

  test('따라가는 경기가 없어도 빈 followedGameIds를 보내 registry를 정리한다', () {
    final payload = buildPushRegistrationPayload(
      deviceToken: 'fcm-token',
      platform: 'ios',
      myTeam: 'LG',
      settings: const PushNotificationSettings.defaults(),
      followedGameIds: const [],
    );

    expect(payload['followedGameIds'], isEmpty);
  });

  test('라인업 공개 push data는 라인업 탭 상세 route로 변환한다', () {
    final route = pushNotificationRouteForData({
      'type': 'lineup_opened',
      'gameId': '20260612KTLG0',
    });

    expect(route, '/game/20260612KTLG0?tab=lineup');
  });

  test('타석 push data는 문자중계 탭 상세 route로 변환한다', () {
    final route = pushNotificationRouteForData({
      'type': 'at_bat',
      'gameId': '20260612KTLG0',
    });

    expect(route, '/game/20260612KTLG0?tab=relay');
  });

  test('안타 push data는 문자중계 탭 상세 route로 변환한다', () {
    final route = pushNotificationRouteForData({
      'type': 'hit',
      'gameId': '20260612KTLG0',
    });

    expect(route, '/game/20260612KTLG0?tab=relay');
  });

  test('경기 시작 임박 push data는 문자중계 탭 상세 route로 변환한다', () {
    final route = pushNotificationRouteForData({
      'type': 'game_start_soon',
      'gameId': '20260612KTLG0',
    });

    expect(route, '/game/20260612KTLG0?tab=relay');
  });

  test('잘못된 push route는 앱 내부 route로 사용하지 않는다', () {
    final route = pushNotificationRouteForData({
      'route': 'https://example.com/game/20260612KTLG0',
      'gameId': '',
    });

    expect(route, isNull);
  });

  test('kboFans 딥링크 payload는 내부 route로 변환한다', () {
    final route = pushNotificationRouteForData({
      'link': 'kboFans://game?gameId=20260612KTLG0&tab=lineup',
    });

    expect(route, '/game/20260612KTLG0?tab=lineup');
  });
}
