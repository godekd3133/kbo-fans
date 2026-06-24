import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/models/home_aggregate.dart';
import 'package:kbo_fans/data/models/schedule.dart';
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
    expect(find.text('일정 보기'), findsAtLeastNWidgets(1));
    expect(find.text('순위'), findsOneWidget);
    expect(aggregateCalls, 0);

    await tester.pump();

    expect(aggregateCalls, 1);
  });

  testWidgets('keeps the last home scoreboard when resume refresh fails', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    _ensureAppConfigInitialized();
    SharedPreferences.setMockInitialValues({});
    final game = _scheduledGame(
      gameId: '20260619AABB0',
      awayTeamId: 'AA',
      awayShortName: 'A',
      homeTeamId: 'BB',
      homeShortName: 'B',
      stadium: '잠실',
    );
    var scoreboardCalls = 0;
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        scoreboardProvider.overrideWith((ref, date) async {
          scoreboardCalls++;
          if (scoreboardCalls > 1) {
            throw Exception('network unavailable after resume');
          }
          return [game];
        }),
        homeAggregateProvider.overrideWith((ref, key) async {
          return HomeAggregate(
            date: key.split('|').first,
            myTeam: null,
            myTeamBrief: null,
            kboBrief: null,
            quickItems: const [],
          );
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final gameRowFinder = find.byKey(
      ValueKey('home-today-game-${game.gameId}'),
    );
    expect(gameRowFinder, findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);

    container.invalidate(scoreboardProvider(_todayKey()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(gameRowFinder, findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);
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
    expect(
      find.byKey(ValueKey('home-today-game-${liveMyTeamGame.gameId}')),
      findsOneWidget,
    );
  });

  testWidgets('deduplicates today games and keeps my-team row visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
    _ensureAppConfigInitialized();
    final myTeamGame = _scheduledGame(
      gameId: '20260611HTLG0',
      awayTeamId: 'HT',
      awayShortName: 'KIA',
      homeTeamId: 'LG',
      homeShortName: 'LG',
      stadium: '잠실',
    );
    final otherGame = _scheduledGame(
      gameId: '20260611NCOB0',
      awayTeamId: 'NC',
      awayShortName: 'NC',
      homeTeamId: 'OB',
      homeShortName: '두산',
      stadium: '창원',
    );

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          myTeamProvider.overrideWith(() => _FixedMyTeamNotifier('LG')),
          scoreboardProvider.overrideWith((ref, date) async {
            return [myTeamGame, otherGame, otherGame];
          }),
          homeAggregateProvider.overrideWith((ref, key) async {
            return HomeAggregate(
              date: key.split('|').first,
              myTeam: 'LG',
              myTeamBrief: null,
              kboBrief: null,
              quickItems: const [],
            );
          }),
        ],
        child: MaterialApp(
          builder: (context, child) {
            final data = MediaQuery.of(
              context,
            ).copyWith(disableAnimations: true);
            return MediaQuery(data: data, child: child!);
          },
          home: const HomeScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('home-today-game-${myTeamGame.gameId}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('home-today-game-${otherGame.gameId}')),
      findsOneWidget,
    );
  });

  testWidgets('recent flow row opens team records with press interaction', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
    _ensureAppConfigInitialized();
    final router = _homeInteractionRouter();

    await tester.pumpWidget(
      _homeInteractionScope(child: MaterialApp.router(routerConfig: router)),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('4연승'));
    await tester.pumpAndSettle();

    expect(find.text('team-record-LG'), findsOneWidget);
  });

  testWidgets('standings row opens standings overview like View All', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
    _ensureAppConfigInitialized();
    final router = _homeInteractionRouter();

    await tester.pumpWidget(
      _homeInteractionScope(child: MaterialApp.router(routerConfig: router)),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    final standingsRow = find.byKey(const ValueKey('home-standings-row-HT'));
    await tester.ensureVisible(standingsRow);
    await tester.tap(standingsRow);
    await tester.pumpAndSettle();

    expect(find.text('standings'), findsOneWidget);
  });

  testWidgets('home notification header opens notification inbox', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
    _ensureAppConfigInitialized();
    final router = _homeInteractionRouter();

    await tester.pumpWidget(
      _homeInteractionScope(child: MaterialApp.router(routerConfig: router)),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('알림 설정'));
    await tester.pumpAndSettle();

    expect(find.text('notifications'), findsOneWidget);
  });

  testWidgets('KBO brief record item renders real player image URL', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
    _ensureAppConfigInitialized();
    final router = _homeInteractionRouter();
    const imageUrl =
        'https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/person/middle/2026/52605.jpg';

    await tester.pumpWidget(
      _homeInteractionScope(
        child: MaterialApp.router(routerConfig: router),
        kboBrief: const HomeKboBrief(
          title: '오늘의 KBO 인사이트 팩',
          subtitle: '실제 기록 신호',
          items: [
            HomeKboBriefItem(
              type: 'record_radar',
              eyebrow: '기록 레이더',
              title: '김도영 13홈런',
              subtitle: 'KIA 타이거즈 · 시즌 홈런 1위',
              route: '/records/player/52605?season=2026',
              teamIds: ['HT'],
              imageUrl: imageUrl,
              fallbackLabel: '김도영',
            ),
          ],
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is CachedNetworkImage && widget.imageUrl == imageUrl,
      ),
      findsOneWidget,
    );
  });

  testWidgets('home broad insight CTAs open news brief instead of records', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'myTeam': 'LG'});
    _ensureAppConfigInitialized();
    final router = _homeInteractionRouter();

    await tester.pumpWidget(
      _homeInteractionScope(
        child: MaterialApp.router(routerConfig: router),
        kboBrief: const HomeKboBrief(
          title: '오늘의 KBO 관전 포인트',
          subtitle: '2경기 예정',
          items: [
            HomeKboBriefItem(
              type: 'big_match',
              eyebrow: '오늘 일정',
              title: '삼성 vs LG',
              subtitle: '18:30 · 잠실 · 오늘 2경기 예정',
              route: '/game/20260619SSLG0',
            ),
            HomeKboBriefItem(
              type: 'standings',
              eyebrow: '선두권',
              title: 'KIA 1위',
              subtitle: 'LG와 2.0G차',
              route: '/standings',
            ),
          ],
        ),
        quickItems: const [
          HomeQuickItem(
            eyebrow: '홈런왕',
            title: '김도영 13개',
            subtitle: 'KIA · 시즌 홈런 1위',
            route: '/records/player/52605?season=2026',
          ),
        ],
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('인사이트'));
    await tester.pumpAndSettle();

    final insightHeader = find.ancestor(
      of: find.text('인사이트'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(
        of: insightHeader,
        matching: find.widgetWithText(TextButton, '전체 보기'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('news'), findsOneWidget);

    router.go('/home');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('지금 보면 좋은 정보'));
    await tester.pumpAndSettle();

    final quickHeader = find.ancestor(
      of: find.text('지금 보면 좋은 정보'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(
        of: quickHeader,
        matching: find.widgetWithText(TextButton, '더보기'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('news'), findsOneWidget);
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

  test('홈 경기 박스 route는 진행 중 경기만 중계 탭을 지정한다', () {
    final liveUri = Uri.parse(
      gameDetailLocationForGameId(
        gameId: '20260611XXYY0',
        status: GameStatus.live,
      ),
    );
    final scheduledUri = Uri.parse(
      gameDetailLocationForGameId(
        gameId: '20260612XXYY0',
        status: GameStatus.scheduled,
      ),
    );

    expect(liveUri.path, '/game/20260611XXYY0');
    expect(liveUri.queryParameters['tab'], 'relay');
    expect(scheduledUri.path, '/game/20260612XXYY0');
    expect(scheduledUri.queryParameters.containsKey('tab'), isFalse);
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

String _todayKey() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
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

GoRouter _homeInteractionRouter() {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/records/team/:teamId',
        builder: (_, state) =>
            Text('team-record-${state.pathParameters['teamId']}'),
      ),
      GoRoute(path: '/records', builder: (_, _) => const Text('records')),
      GoRoute(path: '/standings', builder: (_, _) => const Text('standings')),
      GoRoute(path: '/news', builder: (_, _) => const Text('news')),
      GoRoute(path: '/onboarding', builder: (_, _) => const Text('onboarding')),
      GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const Text('notifications'),
      ),
    ],
  );
}

Widget _homeInteractionScope({
  required Widget child,
  HomeKboBrief? kboBrief,
  List<HomeQuickItem> quickItems = const [],
}) {
  final standings = [
    _standing(
      rank: 1,
      teamId: 'HT',
      teamName: 'KIA 타이거즈',
      wins: 30,
      losses: 15,
      draws: 3,
      pct: '.667',
      gb: '-',
      streak: 'W2',
    ),
    _standing(
      rank: 2,
      teamId: 'LG',
      teamName: 'LG 트윈스',
      wins: 28,
      losses: 17,
      draws: 2,
      pct: '.622',
      gb: '2.0',
      streak: 'W4',
    ),
    _standing(
      rank: 3,
      teamId: 'SS',
      teamName: '삼성 라이온즈',
      wins: 24,
      losses: 21,
      draws: 1,
      pct: '.533',
      gb: '6.0',
      streak: 'W2',
    ),
  ];
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      myTeamProvider.overrideWith(() => _FixedMyTeamNotifier('LG')),
      scoreboardProvider.overrideWith((ref, date) async {
        return [
          _scheduledGame(
            gameId: '20260619SSLG0',
            awayTeamId: 'SS',
            awayShortName: '삼성',
            homeTeamId: 'LG',
            homeShortName: 'LG',
            stadium: '잠실',
          ),
        ];
      }),
      homeAggregateProvider.overrideWith((ref, key) async {
        return HomeAggregate(
          date: key.split('|').first,
          myTeam: 'LG',
          myTeamBrief: HomeMyTeamBrief(
            teamId: 'LG',
            teamLabel: 'LG 트윈스',
            standing: standings[1],
            todayGameId: '20260619SSLG0',
            nextGame: null,
            recentWins: 4,
            recentLosses: 1,
            recentDraws: 0,
            recentGamesCount: 5,
            recentSummaries: const [
              HomeRecentGameSummary(
                gameId: 'recent-1',
                result: '승',
                opponentName: 'NC',
                score: '4:3',
              ),
              HomeRecentGameSummary(
                gameId: 'recent-2',
                result: '승',
                opponentName: 'NC',
                score: '7:1',
              ),
            ],
          ),
          kboBrief: kboBrief,
          quickItems: quickItems,
          standingsPreview: standings,
        );
      }),
    ],
    child: child,
  );
}

TeamStanding _standing({
  required int rank,
  required String teamId,
  required String teamName,
  required int wins,
  required int losses,
  required int draws,
  required String pct,
  required String gb,
  required String streak,
}) {
  return TeamStanding(
    rank: rank,
    teamId: teamId,
    teamName: teamName,
    wins: wins,
    losses: losses,
    draws: draws,
    pct: pct,
    gb: gb,
    streak: streak,
  );
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

Game _scheduledGame({
  required String gameId,
  required String awayTeamId,
  required String awayShortName,
  required String homeTeamId,
  required String homeShortName,
  required String stadium,
}) {
  return Game(
    gameId: gameId,
    status: GameStatus.scheduled,
    inning: '18:30 예정',
    away: TeamScore(
      teamId: awayTeamId,
      teamName: awayShortName,
      shortName: awayShortName,
      score: 0,
      innings: const [],
    ),
    home: TeamScore(
      teamId: homeTeamId,
      teamName: homeShortName,
      shortName: homeShortName,
      score: 0,
      innings: const [],
    ),
    stadium: stadium,
    startTime: '18:30',
  );
}
