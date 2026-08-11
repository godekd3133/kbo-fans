import 'dart:async';

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
import 'package:kbo_fans/features/game_detail/tabs/relay_tab.dart';
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

  test('relay focus 스크롤은 고정 탭 높이만큼 상단 여백을 남긴다', () {
    expect(gameDetailRelayFocusScrollTarget(400), 400 - kTextTabBarHeight);
    expect(gameDetailRelayFocusScrollTarget(24), 0);
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

  testWidgets('경기 상세의 뒤로가기는 접근 가능한 이름을 제공한다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = await _pumpGameDetail(tester, _liveGame());
      addTearDown(router.dispose);

      expect(find.byTooltip('뒤로'), findsOneWidget);
      expect(find.bySemanticsLabel('뒤로'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('복귀 refresh 실패 시 기존 경기 상세를 유지한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = _liveGame();
    final repository = _FakeGameRepository(
      game,
      failGameRefreshAfterFirstLoad: true,
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

    expect(find.text('KT'), findsWidgets);
    expect(find.text('최신 경기 정보를 불러올 수 없습니다'), findsNothing);
    expect(find.textContaining('방금 업데이트'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('KT'), findsWidgets);
    expect(find.text('최신 경기 정보를 불러올 수 없습니다'), findsNothing);
    expect(find.text('갱신 지연'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);

    final gameCallCountBeforeRetry = repository.gameCallCount;
    repository.failGameRefreshAfterFirstLoad = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(repository.gameCallCount, greaterThan(gameCallCountBeforeRetry));
    expect(find.text('KT'), findsWidgets);
    expect(find.text('갱신 지연'), findsNothing);
    expect(find.text('다시 시도'), findsNothing);
    expect(find.textContaining('방금 업데이트'), findsNothing);
  });

  testWidgets('focus=relay 진입 시 문자중계 첫 요약이 고정 탭 아래에 가려지지 않는다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = _liveGame();
    final router = GoRouter(
      initialLocation: '/game/${game.gameId}?tab=relay&focus=relay',
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
            focusRelay: state.uri.queryParameters['focus'] == 'relay',
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

    final nestedScrollState = tester.state<NestedScrollViewState>(
      find.byType(NestedScrollView),
    );
    final remainingHeaderExtent =
        nestedScrollState.outerController.position.maxScrollExtent -
        nestedScrollState.outerController.offset;
    final tabBarBottom = tester.getBottomLeft(find.byType(TabBar)).dy;
    final relaySummaryTop = tester.getTopLeft(find.text('KT 2 : 1 LG')).dy;

    expect(remainingHeaderExtent, greaterThanOrEqualTo(kTextTabBarHeight));
    expect(relaySummaryTop, greaterThanOrEqualTo(tabBarBottom));
  });

  testWidgets('같은 경기에서 initialTab이 바뀌면 해당 탭으로 전환한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = _finalGame();
    final initialTab = ValueNotifier<String?>('score');
    addTearDown(initialTab.dispose);
    final router = GoRouter(
      initialLocation: '/game/${game.gameId}',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('홈')),
        ),
        GoRoute(
          path: '/game/:gameId',
          builder: (_, state) => ValueListenableBuilder<String?>(
            valueListenable: initialTab,
            builder: (_, tab, _) => GameDetailScreen(
              gameId: state.pathParameters['gameId']!,
              game: game,
              initialTab: tab,
            ),
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
    await tester.pumpAndSettle();

    expect(tester.widget<TabBar>(find.byType(TabBar)).controller?.index, 0);

    initialTab.value = 'boxscore';
    await tester.pumpAndSettle();

    expect(tester.widget<TabBar>(find.byType(TabBar)).controller?.index, 2);
  });

  testWidgets('명시 탭 없는 예정 경기가 LIVE로 갱신되면 문자중계로 교정한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final scheduled = _scheduledGame();
    final live = Game(
      gameId: scheduled.gameId,
      status: GameStatus.live,
      inning: '1회초',
      away: scheduled.away,
      home: scheduled.home,
      stadium: scheduled.stadium,
      startTime: scheduled.startTime,
    );
    final loadedGame = Completer<Game?>();
    final router = GoRouter(
      initialLocation: '/game/${scheduled.gameId}',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('홈')),
        ),
        GoRoute(
          path: '/game/:gameId',
          builder: (_, state) => GameDetailScreen(
            gameId: state.pathParameters['gameId']!,
            game: scheduled,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          gameProvider.overrideWith((ref, gameId) => loadedGame.future),
          gameRepositoryProvider.overrideWithValue(_FakeGameRepository(live)),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();

    expect(tester.widget<TabBar>(find.byType(TabBar)).controller?.index, 0);

    loadedGame.complete(live);
    await tester.pumpAndSettle();

    expect(tester.widget<TabBar>(find.byType(TabBar)).controller?.index, 1);
  });

  testWidgets('기존 경기로 진입한 첫 상세 조회 실패도 즉시 갱신 지연과 재시도를 보여준다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = _liveGame();
    final repository = _FakeGameRepository(game, failAllGameLoads: true);
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

    expect(find.text('KT'), findsWidgets);
    expect(find.text('갱신 지연'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);

    repository.failAllGameLoads = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('갱신 지연'), findsNothing);
    expect(find.text('다시 시도'), findsNothing);
  });

  testWidgets('콜드 딥링크 경기 조회 실패는 다시 시도해 상세를 복구한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = _liveGame();
    final repository = _FakeGameRepository(game, failAllGameLoads: true);
    final router = GoRouter(
      initialLocation: '/game/${game.gameId}',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('홈')),
        ),
        GoRoute(
          path: '/game/:gameId',
          builder: (_, state) =>
              GameDetailScreen(gameId: state.pathParameters['gameId']!),
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

    expect(find.text('경기를 불러올 수 없습니다'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('홈으로'), findsOneWidget);

    repository.failAllGameLoads = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('KT'), findsWidgets);
    expect(find.text('경기를 불러올 수 없습니다'), findsNothing);
  });

  testWidgets('존재하지 않는 경기 콜드 딥링크는 홈으로 복구한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const missingGameId = 'missing-game';
    final game = _liveGame();
    final router = GoRouter(
      initialLocation: '/game/$missingGameId',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('홈')),
        ),
        GoRoute(
          path: '/game/:gameId',
          builder: (_, state) =>
              GameDetailScreen(gameId: state.pathParameters['gameId']!),
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
    await tester.pumpAndSettle();

    expect(find.text('경기를 찾을 수 없습니다'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('홈으로'), findsOneWidget);

    await tester.tap(find.text('홈으로'));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
  });

  test('경기 팔로우 저장 안내는 푸시 성공을 확정하지 않는다', () {
    expect(
      followGameSavedMessage(
        isWeb: false,
        liveActivityAllowed: true,
        eventAlertsAllowed: true,
        pushAllowed: true,
      ),
      '경기 팔로우를 저장했습니다. 알림은 기기와 서버 상태에 따라 전달됩니다.',
    );
    expect(
      followGameSavedMessage(
        isWeb: false,
        liveActivityAllowed: true,
        eventAlertsAllowed: false,
        pushAllowed: false,
      ),
      '경기 팔로우를 저장했습니다. 알림 권한 또는 지원 환경을 확인해 주세요.',
    );
    expect(
      followGameSavedMessage(
        isWeb: true,
        liveActivityAllowed: false,
        eventAlertsAllowed: false,
        pushAllowed: false,
      ),
      '경기 팔로우를 저장했습니다. 이 환경에서는 푸시 알림을 지원하지 않습니다.',
    );
  });

  testWidgets('라이브 경기 상세는 경기 팔로우 CTA를 노출한다', (tester) async {
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

    expect(find.text('경기 팔로우하기'), findsOneWidget);
    expect(find.text('푸쉬 중계 받기'), findsNothing);
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

  testWidgets('자동 갱신 중 pull refresh 요청은 끝난 뒤 한 번 더 실행한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = _liveGame();
    final pendingRelayRefresh = Completer<RelayData>();
    final repository = _FakeGameRepository(
      game,
      pendingRelayRefresh: pendingRelayRefresh,
    );
    final router = GoRouter(
      initialLocation: '/game/${game.gameId}?tab=relay',
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
    expect(repository.relayCallCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(repository.relayCallCount, 2);

    final refreshIndicator = tester.widget<RefreshIndicator>(
      find.descendant(
        of: find.byType(RelayTab),
        matching: find.byType(RefreshIndicator),
      ),
    );
    final manualRefresh = refreshIndicator.onRefresh();
    await tester.pump();

    pendingRelayRefresh.complete(
      const RelayData(currentAtBat: null, relayItems: []),
    );
    await tester.pump();
    await tester.pump();
    await manualRefresh;

    expect(repository.relayCallCount, 3);
    expect(repository.gameRefreshRequestCount, 1);
    expect(repository.relayRefreshRequestCount, 1);
  });

  testWidgets('문자중계 첫 로딩이 느려도 5초 timer가 요청을 재시작하지 않는다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = _liveGame();
    final initialRelay = Completer<RelayData>();
    final repository = _FakeGameRepository(
      game,
      pendingInitialRelay: initialRelay,
    );
    final router = GoRouter(
      initialLocation: '/game/${game.gameId}?tab=relay',
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
    expect(repository.relayCallCount, 1);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(repository.relayCallCount, 1);

    initialRelay.complete(const RelayData(currentAtBat: null, relayItems: []));
    await tester.pump();
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

  testWidgets('예정·취소 경기 상세 상단은 0대0 대신 점수 미정으로 표시한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final routers = <GoRouter>[];
    addTearDown(() {
      for (final router in routers) {
        router.dispose();
      }
    });

    for (final game in [_scheduledGame(), _cancelledGame()]) {
      final router = await _pumpGameDetail(tester, game);
      routers.add(router);

      final awayScore = tester.widget<Text>(
        find.byKey(const ValueKey('game-detail-scorebug-away-score')),
      );
      final homeScore = tester.widget<Text>(
        find.byKey(const ValueKey('game-detail-scorebug-home-score')),
      );
      expect(awayScore.data, '–');
      expect(homeScore.data, '–');
    }
  });

  testWidgets('LIVE 원천 점수가 누락되면 실제 0대0이 아닌 미확인으로 표시한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = await _pumpGameDetail(tester, _liveGameWithMissingScore());
    addTearDown(router.dispose);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('game-detail-scorebug-away-score')),
          )
          .data,
      '–',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('game-detail-scorebug-home-score')),
          )
          .data,
      '–',
    );
  });

  testWidgets('서스펜디드 경기 상세 상단은 진행 회차 대신 경기 중단을 명시한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final game = _suspendedGame();
    final router = await _pumpGameDetail(tester, game);
    addTearDown(router.dispose);

    expect(find.text('경기 중단'), findsOneWidget);
    expect(find.text('5회말'), findsNothing);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('game-detail-scorebug-away-score')),
          )
          .data,
      '2',
    );
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

  testWidgets('280·320px와 240% 글자에서 상단 hero와 탭이 재배치된다', (tester) async {
    final semantics = tester.ensureSemantics();
    final routers = <GoRouter>[];
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      for (final width in const [280.0, 320.0]) {
        tester.view.physicalSize = Size(width, 844);
        final router = await _pumpGameDetail(
          tester,
          _liveGame(),
          textScaler: const TextScaler.linear(2.4),
          initialTab: 'score',
        );
        routers.add(router);

        expect(
          find.byKey(const ValueKey('game-detail-scorebug-adaptive-layout')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('game-detail-scorebug-wide-layout')),
          findsNothing,
        );
        expect(
          find.ancestor(
            of: find.byKey(const ValueKey('game-detail-scorebug-away-score')),
            matching: find.byType(FittedBox),
          ),
          findsNothing,
        );
        expect(find.text('KT 위즈'), findsWidgets);
        expect(find.text('LG 트윈스'), findsWidgets);

        final tabBar = tester.widget<TabBar>(find.byType(TabBar));
        expect(tabBar.isScrollable, isTrue);
        for (final key in const [
          'game-detail-tab-score',
          'game-detail-tab-relay',
          'game-detail-tab-boxscore',
          'game-detail-tab-lineup',
        ]) {
          expect(
            tester.getSize(find.byKey(ValueKey(key))).height,
            greaterThanOrEqualTo(44),
          );
        }

        final scoreTabSemantics = tester
            .getSemantics(find.byKey(const ValueKey('game-detail-tab-score')))
            .getSemanticsData();
        expect(
          scoreTabSemantics.flagsCollection.isSelected.toBoolOrNull(),
          isTrue,
        );
        tabBar.controller!.animateTo(1);
        await tester.pumpAndSettle();
        final relayTabSemantics = tester
            .getSemantics(find.byKey(const ValueKey('game-detail-tab-relay')))
            .getSemanticsData();
        expect(
          relayTabSemantics.flagsCollection.isSelected.toBoolOrNull(),
          isTrue,
        );

        final scorebugSemantics = tester
            .getSemantics(
              find.byKey(const ValueKey('game-detail-scorebug-semantics')),
            )
            .getSemanticsData();
        expect(scorebugSemantics.label, contains('KT 위즈 2'));
        expect(scorebugSemantics.label, contains('LG 트윈스 1'));
        expect(scorebugSemantics.label, contains('8회초'));
        expect(tester.takeException(), isNull);
      }
    } finally {
      for (final router in routers) {
        router.dispose();
      }
      semantics.dispose();
    }
  });

  testWidgets('390px 기본 경기 상세는 기존 score hero와 균등 탭을 유지한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = await _pumpGameDetail(tester, _liveGame());
    addTearDown(router.dispose);

    expect(
      find.byKey(const ValueKey('game-detail-scorebug-wide-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('game-detail-scorebug-adaptive-layout')),
      findsNothing,
    );
    expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isFalse);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('game-detail-scorebug-away-score')),
        matching: find.byType(FittedBox),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<GoRouter> _pumpGameDetail(
  WidgetTester tester,
  Game game, {
  TextScaler? textScaler,
  String? initialTab,
}) async {
  SharedPreferences.setMockInitialValues({});
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
          initialTab: initialTab,
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        gameRepositoryProvider.overrideWithValue(_FakeGameRepository(game)),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark,
        routerConfig: router,
        builder: textScaler == null
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: child ?? const SizedBox.shrink(),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
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

Game _liveGameWithMissingScore() {
  return const Game(
    gameId: '20260520KTLG1',
    status: GameStatus.live,
    inning: '1회초',
    away: TeamScore(
      teamId: 'KT',
      teamName: 'KT 위즈',
      shortName: 'KT',
      score: 0,
      scoreAvailable: false,
      innings: [],
    ),
    home: TeamScore(
      teamId: 'LG',
      teamName: 'LG 트윈스',
      shortName: 'LG',
      score: 0,
      scoreAvailable: false,
      innings: [],
    ),
    stadium: '잠실',
    startTime: '18:30',
  );
}

Game _scheduledGame() {
  return const Game(
    gameId: '20260801KTLG0',
    status: GameStatus.scheduled,
    inning: '',
    away: TeamScore(
      teamId: 'KT',
      teamName: 'KT 위즈',
      shortName: 'KT',
      score: 0,
      innings: [],
    ),
    home: TeamScore(
      teamId: 'LG',
      teamName: 'LG 트윈스',
      shortName: 'LG',
      score: 0,
      innings: [],
    ),
    stadium: '잠실',
    startTime: '18:30',
  );
}

Game _cancelledGame() {
  return const Game(
    gameId: '20260802KTLG0',
    status: GameStatus.cancelled,
    inning: '우천 취소',
    statusLabel: '우천 취소',
    away: TeamScore(
      teamId: 'KT',
      teamName: 'KT 위즈',
      shortName: 'KT',
      score: 0,
      innings: [],
    ),
    home: TeamScore(
      teamId: 'LG',
      teamName: 'LG 트윈스',
      shortName: 'LG',
      score: 0,
      innings: [],
    ),
    stadium: '잠실',
    startTime: '18:30',
  );
}

Game _suspendedGame() {
  return const Game(
    gameId: '20260803KTLG0',
    status: GameStatus.suspended,
    inning: '5회말',
    away: TeamScore(
      teamId: 'KT',
      teamName: 'KT 위즈',
      shortName: 'KT',
      score: 2,
      innings: [0, 1, 0, 1, 0],
    ),
    home: TeamScore(
      teamId: 'LG',
      teamName: 'LG 트윈스',
      shortName: 'LG',
      score: 1,
      innings: [0, 0, 1, 0, null],
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

class _FakeGameRepository
    implements GameRepository, GameRepositoryRefreshControl {
  _FakeGameRepository(
    this.game, {
    this.failGameRefreshAfterFirstLoad = false,
    this.failAllGameLoads = false,
    this.highlightInfo,
    this.pendingRelayRefresh,
    this.pendingInitialRelay,
  });

  final Game game;
  bool failGameRefreshAfterFirstLoad;
  bool failAllGameLoads;
  final HighlightInfo? highlightInfo;
  final Completer<RelayData>? pendingRelayRefresh;
  final Completer<RelayData>? pendingInitialRelay;
  int _getGameCallCount = 0;
  int boxscoreCallCount = 0;
  int highlightCallCount = 0;
  int relayCallCount = 0;
  int gameRefreshRequestCount = 0;
  int relayRefreshRequestCount = 0;

  int get gameCallCount => _getGameCallCount;

  @override
  void requestScoreboardRefresh(String date) {}

  @override
  void requestGameRefresh(String gameId) {
    gameRefreshRequestCount += 1;
  }

  @override
  void requestRelayRefresh(String gameId) {
    relayRefreshRequestCount += 1;
  }

  @override
  Future<List<Game>> getScoreboard(String date) async => [game];

  @override
  Future<Game?> getGame(String gameId) async {
    _getGameCallCount += 1;
    if (failAllGameLoads) {
      throw Exception('network unavailable');
    }
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
    relayCallCount += 1;
    if (relayCallCount == 1 && pendingInitialRelay != null) {
      return pendingInitialRelay!.future;
    }
    if (relayCallCount == 2 && pendingRelayRefresh != null) {
      return pendingRelayRefresh!.future;
    }
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
