import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/services/live_activity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Android notification stop action clears followed game', () async {
    await LiveActivityService.instance.followGame('20260520LGKT0');

    await LiveActivityService.handleAndroidNotificationResponseForTesting(
      const NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: 'stop_following_game',
      ),
    );

    expect(await LiveActivityService.instance.followedGameId(), isNull);
  });

  test('other Android notification actions keep followed game', () async {
    await LiveActivityService.instance.followGame('20260520LGKT0');

    await LiveActivityService.handleAndroidNotificationResponseForTesting(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
      ),
    );

    expect(
      await LiveActivityService.instance.followedGameId(),
      '20260520LGKT0',
    );
  });

  test('auto Live Activity target prefers a live my-team game', () {
    final games = [
      _game(
        gameId: '20260520LGKT0',
        awayTeamId: 'LG',
        homeTeamId: 'KT',
        status: GameStatus.scheduled,
      ),
      _game(
        gameId: '20260520SSOB0',
        awayTeamId: 'SS',
        homeTeamId: 'OB',
        status: GameStatus.live,
      ),
      _game(
        gameId: '20260520NCHH0',
        awayTeamId: 'NC',
        homeTeamId: 'HH',
        status: GameStatus.live,
      ),
    ];

    final selected = selectAutoLiveActivityGame(games: games, myTeamId: 'NC');

    expect(selected?.gameId, '20260520NCHH0');
  });

  test('auto Live Activity target ignores scheduled my-team games', () {
    final games = [
      _game(
        gameId: '20260520LGKT0',
        awayTeamId: 'LG',
        homeTeamId: 'KT',
        status: GameStatus.scheduled,
      ),
    ];

    final selected = selectAutoLiveActivityGame(games: games, myTeamId: 'LG');

    expect(selected, isNull);
  });
}

Game _game({
  required String gameId,
  required String awayTeamId,
  required String homeTeamId,
  required GameStatus status,
}) {
  return Game(
    gameId: gameId,
    status: status,
    inning: status == GameStatus.live ? '1회초' : '',
    away: TeamScore(
      teamId: awayTeamId,
      teamName: awayTeamId,
      shortName: awayTeamId,
      score: 0,
      innings: const [],
    ),
    home: TeamScore(
      teamId: homeTeamId,
      teamName: homeTeamId,
      shortName: homeTeamId,
      score: 0,
      innings: const [],
    ),
    stadium: '잠실',
    startTime: '18:30',
  );
}
