import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/models/home_aggregate.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/home/home_screen.dart';
import 'package:kbo_fans/services/live_activity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('defers home aggregate provider until after scoreboard paint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    _ensureAppConfigInitialized();
    SharedPreferences.setMockInitialValues({});
    var aggregateCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          scoreboardProvider.overrideWith((ref, date) async {
            return const <Game>[];
          }),
          homeAggregateProvider.overrideWith((ref, key) async {
            aggregateCalls++;
            return HomeAggregate(
              date: key.split('|').first,
              myTeam: null,
              myTeamBrief: null,
              kboBrief: null,
              quickItems: const [],
            );
          }),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pump();

    expect(find.text('홈 첫 화면을 먼저 띄우는 중입니다.'), findsOneWidget);
    expect(aggregateCalls, 0);

    await tester.pump();

    expect(aggregateCalls, 1);
  });

  testWidgets('auto follows a live my team game on home', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'XX'});
    _ensureAppConfigInitialized();
    final liveMyTeamGame = _liveGame(
      gameId: '20260611XXYY0',
      awayTeamId: 'XX',
      homeTeamId: 'YY',
    );

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          myTeamProvider.overrideWith(() => _FixedMyTeamNotifier('XX')),
          scoreboardProvider.overrideWith((ref, date) async {
            return [liveMyTeamGame];
          }),
          homeAggregateProvider.overrideWith((ref, key) async {
            return HomeAggregate(
              date: key.split('|').first,
              myTeam: 'XX',
              myTeamBrief: null,
              kboBrief: null,
              quickItems: const [],
            );
          }),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(
      await LiveActivityService.instance.followedGameId(),
      liveMyTeamGame.gameId,
    );
    expect(find.text('따라가는 중'), findsOneWidget);
  });

  test('진행 중인 경기 상세 route는 기본으로 중계 탭을 지정한다', () {
    final liveGame = _liveGame(
      gameId: '20260611XXYY0',
      awayTeamId: 'XX',
      homeTeamId: 'YY',
    );

    final uri = Uri.parse(gameDetailLocationFor(liveGame));

    expect(uri.path, '/game/${liveGame.gameId}');
    expect(uri.queryParameters['tab'], 'relay');
  });

  test('마이팀 중계 보기 route는 중계 본문 focus 신호를 포함한다', () {
    final liveMyTeamGame = _liveGame(
      gameId: '20260611XXYY0',
      awayTeamId: 'XX',
      homeTeamId: 'YY',
    );

    final uri = Uri.parse(
      gameDetailLocationFor(liveMyTeamGame, tab: 'relay', focusRelay: true),
    );

    expect(uri.path, '/game/${liveMyTeamGame.gameId}');
    expect(uri.queryParameters['tab'], 'relay');
    expect(uri.queryParameters['focus'], 'relay');
  });
}

var _appConfigInitialized = false;

void _ensureAppConfigInitialized() {
  if (_appConfigInitialized) {
    return;
  }
  AppConfig.initialize();
  _appConfigInitialized = true;
}

class _FixedMyTeamNotifier extends MyTeamNotifier {
  _FixedMyTeamNotifier(this.teamId);

  final String? teamId;

  @override
  String? build() => teamId;
}

Game _liveGame({
  required String gameId,
  required String awayTeamId,
  required String homeTeamId,
}) {
  return Game(
    gameId: gameId,
    status: GameStatus.live,
    inning: '7회말',
    away: TeamScore(
      teamId: awayTeamId,
      teamName: awayTeamId,
      shortName: awayTeamId,
      score: 2,
      innings: const [],
    ),
    home: TeamScore(
      teamId: homeTeamId,
      teamName: homeTeamId,
      shortName: homeTeamId,
      score: 1,
      innings: const [],
    ),
    stadium: '잠실',
    startTime: '18:30',
  );
}
