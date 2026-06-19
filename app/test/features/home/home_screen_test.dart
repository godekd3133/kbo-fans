import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/models/home_aggregate.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/home/home_screen.dart';
import 'package:kbo_fans/features/home/widgets/game_card.dart';
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
    expect(find.text('기록실'), findsAtLeastNWidgets(1));
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

    final gameCardFinder = find.byWidgetPredicate(
      (widget) => widget is GameCard && widget.game.gameId == game.gameId,
    );
    expect(gameCardFinder, findsAtLeastNWidgets(1));
    expect(find.text('다시 시도'), findsNothing);

    container.invalidate(scoreboardProvider(_todayKey()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(gameCardFinder, findsAtLeastNWidgets(1));
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
    expect(find.text('따라가는 중'), findsOneWidget);
  });

  testWidgets('shows other games only in the dedicated game list', (
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

    final otherGameCardFinder = find.byWidgetPredicate(
      (widget) => widget is GameCard && widget.game.gameId == otherGame.gameId,
    );

    expect(find.text('NC vs 두산'), findsNothing);
    await tester.scrollUntilVisible(
      otherGameCardFinder,
      300,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(otherGameCardFinder, findsOneWidget);
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
