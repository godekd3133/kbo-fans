import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/boxscore.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/models/highlight_info.dart';
import 'package:kbo_fans/data/models/relay.dart';
import 'package:kbo_fans/data/models/schedule.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/data/repositories/game_repository.dart';
import 'package:kbo_fans/features/game_detail/game_detail_screen.dart';

void main() {
  test('라이브 경기 문자중계 탭은 15초 refresh cadence를 사용한다', () {
    expect(
      gameDetailRefreshIntervalFor(GameStatus.live, selectedTabIndex: 1),
      const Duration(seconds: 15),
    );
    expect(
      gameDetailRefreshIntervalFor(GameStatus.live, selectedTabIndex: 0),
      const Duration(seconds: 30),
    );
  });

  testWidgets('상세가 첫 route일 때 뒤로가기는 빈 화면 대신 홈으로 이동한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = _liveGame();
    final router = GoRouter(
      initialLocation: '/game/${game.gameId}',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('홈')),
        ),
        GoRoute(
          path: '/game/:gameId',
          builder: (_, state) => GameDetailScreen(
            gameId: state.pathParameters['gameId']!,
            game: game,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          gameRepositoryProvider.overrideWithValue(_FakeGameRepository(game)),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/game/${game.gameId}',
    );

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
  });

  testWidgets('복귀 refresh 실패 시 기존 경기 상세를 유지한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = _liveGame();
    final router = GoRouter(
      initialLocation: '/game/${game.gameId}',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('홈')),
        ),
        GoRoute(
          path: '/game/:gameId',
          builder: (_, state) => GameDetailScreen(
            gameId: state.pathParameters['gameId']!,
            game: game,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          gameRepositoryProvider.overrideWithValue(
            _FakeGameRepository(game, failGameRefreshAfterFirstLoad: true),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('KT'), findsWidgets);
    expect(find.text('최신 경기 정보를 불러올 수 없습니다'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('KT'), findsWidgets);
    expect(find.text('최신 경기 정보를 불러올 수 없습니다'), findsNothing);
  });
}

Game _liveGame() {
  return const Game(
    gameId: '20260520KTLG0',
    status: GameStatus.live,
    inning: '8회초',
    away: TeamScore(
      teamId: 'KT',
      teamName: 'KT 위즈',
      shortName: 'KT',
      score: 2,
      innings: [],
    ),
    home: TeamScore(
      teamId: 'LG',
      teamName: 'LG 트윈스',
      shortName: 'LG',
      score: 1,
      innings: [],
    ),
    stadium: '잠실',
    startTime: '18:30',
  );
}

class _FakeGameRepository implements GameRepository {
  _FakeGameRepository(this.game, {this.failGameRefreshAfterFirstLoad = false});

  final Game game;
  final bool failGameRefreshAfterFirstLoad;
  int _getGameCallCount = 0;

  @override
  Future<List<Game>> getScoreboard(String date) async => [game];

  @override
  Future<Game?> getGame(String gameId) async {
    _getGameCallCount += 1;
    if (failGameRefreshAfterFirstLoad && _getGameCallCount > 1) {
      throw Exception('network unavailable after resume');
    }
    return gameId == game.gameId ? game : null;
  }

  @override
  Future<HighlightInfo?> getHighlightInfo(String gameId) async => null;

  @override
  Future<RelayData> getRelayData(String gameId, {int? afterSeqNo}) async {
    return const RelayData(currentAtBat: null, relayItems: []);
  }

  @override
  Future<List<RelayItem>> getRelay(String gameId, {int? afterSeqNo}) async {
    return const [];
  }

  @override
  Future<CurrentAtBat?> getCurrentAtBat(String gameId) async => null;

  @override
  Future<GameBoxscoreData> getBoxscoreData(String gameId) async {
    return GameBoxscoreData(
      gameId: gameId,
      officialAvailable: false,
      away: const TeamBoxscoreData(teamId: 'KT', batters: [], pitchers: []),
      home: const TeamBoxscoreData(teamId: 'LG', batters: [], pitchers: []),
    );
  }

  @override
  Future<List<BatterRecord>> getBatters(
    String gameId, {
    required bool isAway,
  }) async {
    return const [];
  }

  @override
  Future<List<PitcherRecord>> getPitchers(
    String gameId, {
    required bool isAway,
  }) async {
    return const [];
  }

  @override
  Future<GameLineupData> getLineupData(String gameId) async {
    return GameLineupData(
      gameId: gameId,
      away: const TeamLineupData(teamId: 'KT', lineup: []),
      home: const TeamLineupData(teamId: 'LG', lineup: []),
    );
  }

  @override
  Future<List<LineupEntry>> getLineup(
    String gameId, {
    required bool isAway,
  }) async {
    return const [];
  }

  @override
  Future<List<ScheduleDay>> getSchedule(String yearMonth) async => const [];

  @override
  Future<List<TeamStanding>> getStandings(int season) async => const [];
}
