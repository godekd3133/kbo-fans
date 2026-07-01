import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/boxscore.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/models/highlight_info.dart';
import 'package:kbo_fans/data/models/highlight_video.dart';
import 'package:kbo_fans/data/models/relay.dart';
import 'package:kbo_fans/data/models/schedule.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/data/repositories/game_repository.dart';
import 'package:kbo_fans/features/game_detail/game_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('라이브 경기 상세는 relay 탭 5초, 그 외 탭 8초 refresh cadence를 사용한다', () {
    expect(
      gameDetailRefreshIntervalFor(GameStatus.live, selectedTabIndex: 1),
      const Duration(seconds: 5),
    );
    expect(
      gameDetailRefreshIntervalFor(GameStatus.live, selectedTabIndex: 0),
      const Duration(seconds: 8),
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

  testWidgets('라이브 경기 상세 follow CTA는 푸쉬 중계 버튼만 노출한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
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

    expect(find.text('푸쉬 중계 받기'), findsOneWidget);
    expect(find.text('이 경기를 따라가면'), findsNothing);
    expect(find.text('따라가기 화면'), findsNothing);
    expect(find.text('바로 알림'), findsNothing);
    expect(find.text('홈 위젯'), findsNothing);
    expect(find.text('경기 따라가기'), findsNothing);
    expect(find.text('중계만 보기'), findsNothing);
  });

  testWidgets('라이브 경기 상세는 탭을 다시 열 때 visible 탭 데이터를 즉시 새로고침한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = _liveGame();
    final repository = _FakeGameRepository(game);
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
        overrides: [gameRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.text('박스스코어'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final firstBoxscoreCallCount = repository.boxscoreCallCount;
    expect(firstBoxscoreCallCount, greaterThan(0));

    await tester.tap(find.text('스코어'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.text('박스스코어'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(repository.boxscoreCallCount, greaterThan(firstBoxscoreCallCount));
  });

  testWidgets('종료 경기 스코어탭은 하이라이트를 자동 로드하고 앱 안 재생 버튼을 노출한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = _finalGame();
    final repository = _FakeGameRepository(
      game,
      highlightInfo: const HighlightInfo(
        officialUrl:
            'https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx?gameDate=20260629&gameId=20260629KTLG0&section=HIGHLIGHT',
        youtubeVideos: [
          HighlightVideo(
            videoId: 'tyo0j_fyPMU',
            title: 'KT vs LG 하이라이트',
            thumbnailUrl: '',
            videoUrl: 'https://www.youtube.com/watch?v=tyo0j_fyPMU',
          ),
        ],
      ),
    );
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
        overrides: [gameRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(repository.highlightCallCount, 1);
    expect(find.text('보기'), findsNothing);
    expect(find.text('바로 재생'), findsOneWidget);
  });

  testWidgets('종료 경기 상세는 스코어 탭 진입 전에 하이라이트를 미리 로드한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = _finalGame();
    final repository = _FakeGameRepository(
      game,
      highlightInfo: const HighlightInfo(
        youtubeVideos: [
          HighlightVideo(
            videoId: 'tyo0j_fyPMU',
            title: 'KT vs LG 하이라이트',
            thumbnailUrl: '',
            videoUrl: 'https://www.youtube.com/watch?v=tyo0j_fyPMU',
          ),
        ],
      ),
    );
    final router = GoRouter(
      initialLocation: '/game/${game.gameId}?tab=lineup',
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
            initialTab: state.uri.queryParameters['tab'],
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [gameRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(repository.highlightCallCount, 1);

    await tester.tap(find.text('스코어'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('바로 재생'), findsOneWidget);
  });

  testWidgets('종료 경기 상세 상단은 회차 대신 종료 상태를 표시한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = _finalGame();
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

    expect(find.text('경기 종료'), findsOneWidget);
    expect(find.text('경기종료'), findsNothing);
    expect(find.text('18:30'), findsNothing);
    expect(find.text('최종 기록'), findsNothing);
    expect(find.text('9회'), findsNothing);
  });

  testWidgets('경기 상세 상단은 두 자리 점수를 한 줄로 유지한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = _lopsidedFinalGame();
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

    final scoreFinder = find.byKey(
      const ValueKey('game-detail-scorebug-away-score'),
    );
    final scoreText = tester.widget<Text>(scoreFinder);

    expect(scoreText.data, '12');
    expect(scoreText.maxLines, 1);
    expect(scoreText.softWrap, isFalse);
    expect(tester.getSize(scoreFinder).height, lessThan(60));
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

Game _finalGame() {
  return const Game(
    gameId: '20260629KTLG0',
    status: GameStatus.final_,
    inning: '경기종료',
    away: TeamScore(
      teamId: 'KT',
      teamName: 'KT 위즈',
      shortName: 'KT',
      score: 5,
      innings: [0, 1, 0, 0, 2, 0, 0, 1, 1],
    ),
    home: TeamScore(
      teamId: 'LG',
      teamName: 'LG 트윈스',
      shortName: 'LG',
      score: 3,
      innings: [0, 0, 0, 1, 0, 0, 2, 0, 0],
    ),
    stadium: '잠실',
    startTime: '18:30',
  );
}

Game _lopsidedFinalGame() {
  return const Game(
    gameId: '20260630KIOB0',
    status: GameStatus.final_,
    inning: '경기종료',
    away: TeamScore(
      teamId: 'HT',
      teamName: 'KIA 타이거즈',
      shortName: 'KIA',
      score: 12,
      innings: [0, 0, 0, 0, 2, 7, 0, 0, 3],
      hits: 12,
      walks: 7,
    ),
    home: TeamScore(
      teamId: 'OB',
      teamName: '두산 베어스',
      shortName: '두산',
      score: 1,
      innings: [0, 0, 0, 0, 0, 0, 1, 0, 0],
      hits: 5,
      errors: 1,
      walks: 1,
    ),
    stadium: '잠실',
    startTime: '18:30',
  );
}

class _FakeGameRepository implements GameRepository {
  _FakeGameRepository(
    this.game, {
    this.failGameRefreshAfterFirstLoad = false,
    this.highlightInfo,
  });

  final Game game;
  final bool failGameRefreshAfterFirstLoad;
  final HighlightInfo? highlightInfo;
  int _getGameCallCount = 0;
  int boxscoreCallCount = 0;
  int highlightCallCount = 0;

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
  Future<HighlightInfo?> getHighlightInfo(String gameId) async {
    highlightCallCount += 1;
    return highlightInfo;
  }

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
    boxscoreCallCount += 1;
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
