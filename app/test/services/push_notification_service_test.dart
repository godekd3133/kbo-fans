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

    expect(topics, contains('game_start_LG'));
    expect(topics, contains('scoring_LG'));
    expect(topics, isNot(contains('game_start_ALL')));
    expect(topics, isNot(contains('all_games_enabled')));
  });

  test('allGames가 켜져 있으면 ALL 토픽과 플래그를 만든다', () {
    final settings = const PushNotificationSettings.defaults().copyWith(
      allGames: true,
    );

    final topics = buildPushTopics(settings: settings, myTeam: 'LG');

    expect(topics, contains('game_start_ALL'));
    expect(topics, contains('all_games_enabled'));
    expect(topics, isNot(contains('game_start_LG')));
  });
}
