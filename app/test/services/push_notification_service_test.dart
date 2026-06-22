import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/services/push_notification_service.dart';

void main() {
  test('마이팀이 없고 allGames가 꺼져 있으면 토픽을 만들지 않는다', () {
    final settings = const PushNotificationSettings.defaults().copyWith(
      gameEndDelivery: PushNotificationDelivery.immediate,
    );

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
    expect(topics, contains('game_end_LG'));
    expect(topics, contains('lineup_opened_LG'));
    expect(topics, contains('inning_change_LG'));
    expect(topics, contains('baseball_info_LG'));
    expect(topics, isNot(contains('game_start_ALL')));
    expect(topics, isNot(contains('all_games_enabled')));
  });

  test('마이팀은 푸쉬 중계 받기 없이 enabled game moment를 팀 토픽으로 구독한다', () {
    const settings = PushNotificationSettings.defaults();

    final topics = buildPushTopics(settings: settings, myTeam: 'LG');

    expect(topics, contains('game_start_LG'));
    expect(topics, contains('game_start_soon_LG'));
    expect(topics, contains('scoring_LG'));
    expect(topics, contains('hit_LG'));
    expect(topics, contains('homerun_LG'));
    expect(topics, contains('reversal_LG'));
    expect(topics, contains('game_end_LG'));
    expect(topics, contains('lineup_opened_LG'));
    expect(topics, contains('inning_change_LG'));
    expect(topics, contains('at_bat_LG'));
  });

  test('타 팀 경기를 따라가도 마이팀 자동 team topic은 유지하고 타 팀은 GAME topic으로 추가한다', () {
    const settings = PushNotificationSettings.defaults();

    final topics = buildPushTopics(
      settings: settings,
      myTeam: 'LG',
      followedGameIds: const ['20260612KTOB0'],
    );

    expect(topics, contains('scoring_LG'));
    expect(topics, contains('scoring_GAME_20260612KTOB0'));
    expect(topics, contains('game_end_LG'));
    expect(topics, contains('game_end_GAME_20260612KTOB0'));
    expect(topics, contains('lineup_opened_LG'));
    expect(topics, contains('lineup_opened_GAME_20260612KTOB0'));
    expect(topics, contains('inning_change_LG'));
    expect(topics, contains('inning_change_GAME_20260612KTOB0'));
    expect(topics, contains('baseball_info_LG'));
    expect(topics, isNot(contains('baseball_info_GAME_20260612KTOB0')));
  });

  test('따라가는 경기가 마이팀이면 team topic만 유지해 중복 GAME topic을 만들지 않는다', () {
    const settings = PushNotificationSettings.defaults();

    final topics = buildPushTopics(
      settings: settings,
      myTeam: 'LG',
      followedGameIds: const ['20260612KTLG0'],
    );

    expect(topics, contains('scoring_LG'));
    expect(topics, contains('game_end_LG'));
    expect(topics, contains('lineup_opened_LG'));
    expect(topics, contains('inning_change_LG'));
    expect(topics, isNot(contains('scoring_GAME_20260612KTLG0')));
    expect(topics, isNot(contains('game_end_GAME_20260612KTLG0')));
    expect(topics, isNot(contains('lineup_opened_GAME_20260612KTLG0')));
    expect(topics, isNot(contains('inning_change_GAME_20260612KTLG0')));
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
    expect(topics, contains('baseball_info_ALL'));
    expect(topics, contains('all_games_enabled'));
    expect(topics, isNot(contains('scoring_LG')));
  });

  test('따라가는 경기가 마이팀 경기이면 일반 경기 push는 마이팀 team topic으로 받는다', () {
    final settings = const PushNotificationSettings.defaults().copyWith(
      gameEndDelivery: PushNotificationDelivery.immediate,
      lineupOpenedDelivery: PushNotificationDelivery.immediate,
      inningChangeDelivery: PushNotificationDelivery.immediate,
    );

    final topics = buildPushTopics(
      settings: settings,
      myTeam: 'LG',
      followedGameIds: const ['20260612KTLG0', ' ', '20260612KTLG0'],
    );

    expect(topics, contains('baseball_info_LG'));
    expect(topics, contains('scoring_LG'));
    expect(topics, contains('homerun_LG'));
    expect(topics, contains('game_start_LG'));
    expect(topics, contains('hit_LG'));
    expect(topics, contains('game_end_LG'));
    expect(topics, contains('lineup_opened_LG'));
    expect(topics, contains('inning_change_LG'));
    expect(topics, isNot(contains('scoring_GAME_20260612KTLG0')));
    expect(topics, isNot(contains('homerun_GAME_20260612KTLG0')));
    expect(topics, isNot(contains('game_start_GAME_20260612KTLG0')));
    expect(topics, isNot(contains('game_start_soon_GAME_20260612KTLG0')));
    expect(topics, isNot(contains('game_end_GAME_20260612KTLG0')));
    expect(topics, isNot(contains('hit_GAME_20260612KTLG0')));
    expect(topics, isNot(contains('at_bat_GAME_20260612KTLG0')));
    expect(topics, isNot(contains('lineup_opened_GAME_20260612KTLG0')));
    expect(topics, isNot(contains('inning_change_GAME_20260612KTLG0')));
    expect(topics, isNot(contains('baseball_info_GAME_20260612KTLG0')));
  });

  test('따라가는 경기의 enabled moment는 summary/liveOnly여도 GAME 토픽에 포함한다', () {
    const settings = PushNotificationSettings.defaults();

    final topics = buildPushTopics(
      settings: settings,
      myTeam: 'LG',
      followedGameIds: const ['20260612KTOB0'],
    );

    expect(topics, contains('game_end_GAME_20260612KTOB0'));
    expect(topics, contains('lineup_opened_GAME_20260612KTOB0'));
    expect(topics, contains('inning_change_GAME_20260612KTOB0'));
    expect(topics, contains('game_end_LG'));
    expect(topics, contains('lineup_opened_LG'));
    expect(topics, contains('inning_change_LG'));
  });

  test('따라가는 경기가 마이팀 경기가 아니면 마이팀 team topic과 GAME topic을 함께 만든다', () {
    final settings = const PushNotificationSettings.defaults().copyWith(
      gameEndDelivery: PushNotificationDelivery.immediate,
    );

    final topics = buildPushTopics(
      settings: settings,
      myTeam: 'LG',
      followedGameIds: const ['20260612KTOB0'],
    );

    expect(topics, contains('scoring_GAME_20260612KTOB0'));
    expect(topics, contains('homerun_GAME_20260612KTOB0'));
    expect(topics, contains('at_bat_GAME_20260612KTOB0'));
    expect(topics, contains('baseball_info_LG'));
    expect(topics, contains('scoring_LG'));
    expect(topics, contains('homerun_LG'));
    expect(topics, contains('at_bat_LG'));
    expect(topics, contains('game_end_LG'));
    expect(topics, contains('game_end_GAME_20260612KTOB0'));
  });

  test('release 앱에서 마이팀이 있으면 자동 푸시 권한 요청 대상이다', () {
    expect(
      shouldAutoRequestPushPermission(
        isWeb: false,
        remotePushAvailable: true,
        alreadyRequested: false,
        myTeam: 'LG',
      ),
      isTrue,
    );
  });

  test('API mode이면 local 빌드도 remote push 등록 대상이다', () {
    expect(
      shouldUseRemotePushServices(isWeb: false, useBackendApi: true),
      isTrue,
    );
    expect(
      shouldAutoRequestPushPermission(
        isWeb: false,
        remotePushAvailable: true,
        alreadyRequested: false,
        myTeam: 'LG',
      ),
      isTrue,
    );
  });

  test('remote push 불가 또는 마이팀 없음 또는 이미 요청한 경우 자동 푸시 권한을 요청하지 않는다', () {
    expect(
      shouldAutoRequestPushPermission(
        isWeb: false,
        remotePushAvailable: false,
        alreadyRequested: false,
        myTeam: 'LG',
      ),
      isFalse,
    );
    expect(
      shouldAutoRequestPushPermission(
        isWeb: false,
        remotePushAvailable: true,
        alreadyRequested: false,
        myTeam: null,
      ),
      isFalse,
    );
    expect(
      shouldAutoRequestPushPermission(
        isWeb: false,
        remotePushAvailable: true,
        alreadyRequested: true,
        myTeam: 'LG',
      ),
      isFalse,
    );
  });

  test('마이팀 game moment는 summary/liveOnly여도 topic을 만들고 off는 제외한다', () {
    final settings = const PushNotificationSettings.defaults().copyWith(
      scoringDelivery: PushNotificationDelivery.summary,
      hitDelivery: PushNotificationDelivery.off,
      homerunDelivery: PushNotificationDelivery.liveOnly,
      reversalDelivery: PushNotificationDelivery.off,
      gameEndDelivery: PushNotificationDelivery.immediate,
      atBatDelivery: PushNotificationDelivery.summary,
      baseballInfoDelivery: PushNotificationDelivery.off,
    );

    final topics = buildPushTopics(settings: settings, myTeam: 'LG');

    expect(topics, contains('scoring_LG'));
    expect(topics, isNot(contains('hit_LG')));
    expect(topics, contains('homerun_LG'));
    expect(topics, isNot(contains('reversal_LG')));
    expect(topics, contains('game_end_LG'));
    expect(topics, contains('lineup_opened_LG'));
    expect(topics, contains('at_bat_LG'));
    expect(topics, contains('inning_change_LG'));
    expect(topics, isNot(contains('baseball_info_LG')));
  });

  test('마이팀 자동 game topic도 off 또는 disabled 항목은 구독하지 않는다', () {
    final settings = const PushNotificationSettings.defaults().copyWith(
      scoringDelivery: PushNotificationDelivery.off,
      hitDelivery: PushNotificationDelivery.off,
      homerun: false,
      gameEndDelivery: PushNotificationDelivery.off,
      lineupOpened: false,
      inningChangeDelivery: PushNotificationDelivery.off,
    );

    final topics = buildPushTopics(settings: settings, myTeam: 'LG');

    expect(topics, isNot(contains('hit_LG')));
    expect(topics, isNot(contains('scoring_LG')));
    expect(topics, isNot(contains('homerun_LG')));
    expect(topics, isNot(contains('game_end_LG')));
    expect(topics, isNot(contains('lineup_opened_LG')));
    expect(topics, isNot(contains('inning_change_LG')));
  });

  test('push 등록 payload는 현재 따라가는 경기 id를 포함한다', () {
    const settings = PushNotificationSettings.defaults();

    final payload = buildPushRegistrationPayload(
      deviceToken: 'fcm-token',
      platform: 'ios',
      installationId: 'install-12345678',
      myTeam: 'LG',
      settings: settings,
      followedGameIds: const ['20260612KTLG0', '  ', '20260612KTLG0'],
      notificationsAllowed: true,
      authorizationStatus: 'authorized',
      apnsTokenReady: true,
    );

    expect(payload['deviceToken'], 'fcm-token');
    expect(payload['installationId'], 'install-12345678');
    expect(payload['myTeam'], 'LG');
    expect(payload['notificationsAllowed'], isTrue);
    expect(payload['authorizationStatus'], 'authorized');
    expect(payload['apnsTokenReady'], isTrue);
    expect(payload['notifications']['baseballInfo'], isTrue);
    expect(
      payload['notifications']['deliveryModes']['baseballInfo'],
      'immediate',
    );
    expect(payload['followedGameIds'], ['20260612KTLG0']);
  });

  test('따라가는 경기가 없어도 빈 followedGameIds를 보내 registry를 정리한다', () {
    final payload = buildPushRegistrationPayload(
      deviceToken: 'fcm-token',
      platform: 'ios',
      installationId: 'install-12345678',
      myTeam: 'LG',
      settings: const PushNotificationSettings.defaults(),
      followedGameIds: const [],
    );

    expect(payload['followedGameIds'], isEmpty);
  });

  test('원격 테스트 push payload는 현재 기기 토큰만 보낸다', () {
    final payload = buildPushDeviceTestPayload(deviceToken: 'fcm-token');

    expect(payload, {'deviceToken': 'fcm-token'});
  });

  test('원격 push receipt payload는 등록 토큰과 라우팅 단서만 보낸다', () {
    final payload = buildPushReceiptPayload(
      deviceToken: 'fcm-token',
      messageId: 'message-1',
      source: 'foreground',
      route: '/game/20260620HTKT0?tab=relay',
      receivedAt: DateTime.utc(2026, 6, 22, 4, 50),
      data: const {
        'type': 'hit',
        'gameId': '20260620HTKT0',
        'topic': 'hit_GAME_20260620HTKT0',
      },
    );

    expect(payload['deviceToken'], 'fcm-token');
    expect(payload['messageId'], 'message-1');
    expect(payload['source'], 'foreground');
    expect(payload['type'], 'hit');
    expect(payload['gameId'], '20260620HTKT0');
    expect(payload['route'], '/game/20260620HTKT0?tab=relay');
    expect(payload['receivedAt'], '2026-06-22T04:50:00.000Z');
    expect(payload['data'], {'topic': 'hit_GAME_20260620HTKT0'});
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

  test('야구 브리프 push data는 route가 없어도 홈으로 변환한다', () {
    final route = pushNotificationRouteForData({
      'type': 'baseball_info',
      'kind': 'weekly_check',
    });

    expect(route, '/home');
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
