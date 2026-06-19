import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/boxscore.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/models/player.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/game_detail/tabs/boxscore_tab.dart';

void main() {
  testWidgets('박스스코어가 0값 투수 placeholder만 있으면 업데이트 전 상태를 보여준다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          gameBoxscoreProvider.overrideWith((ref, gameId) async {
            return GameBoxscoreData(
              gameId: gameId,
              officialAvailable: true,
              away: const TeamBoxscoreData(
                teamId: 'KT',
                batters: [],
                pitchers: [
                  PitcherRecord(
                    name: '선발투수',
                    innings: '',
                    hits: 0,
                    strikeouts: 0,
                    walks: 0,
                    earnedRuns: 0,
                  ),
                ],
              ),
              home: const TeamBoxscoreData(
                teamId: 'LG',
                batters: [],
                pitchers: [
                  PitcherRecord(
                    name: '상대투수',
                    innings: '',
                    hits: 0,
                    strikeouts: 0,
                    walks: 0,
                    earnedRuns: 0,
                  ),
                ],
              ),
            );
          }),
          teamPlayersProvider.overrideWith((ref, key) async {
            return const <PlayerProfile>[];
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: BoxscoreTab(
              gameId: '20260613KTLG0',
              game: _liveGame,
              gameStatus: GameStatus.live,
              awayName: 'KT',
              homeName: 'LG',
              awayTeamId: 'KT',
              homeTeamId: 'LG',
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('공식 박스스코어 업데이트 전입니다'), findsOneWidget);
    expect(find.text('타격 요약'), findsNothing);
    expect(find.text('선발투수'), findsNothing);
    expect(find.text('삼진 0'), findsNothing);
  });

  testWidgets('매칭된 박스스코어 선수는 선수 기록 보기 진입점을 보여준다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _boxscoreHarness(
        boxscore: _displayableBoxscore,
        players: [
          _playerProfile(
            id: '50054',
            teamId: 'KT',
            name: '강백호',
            number: 50,
            playerType: PlayerType.hitter,
          ),
          _playerProfile(
            id: '61023',
            teamId: 'KT',
            name: '김영현',
            number: 60,
            playerType: PlayerType.pitcher,
          ),
        ],
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('선수 기록 보기'), findsWidgets);
    expect(find.text('오늘 생산 +14'), findsOneWidget);
    expect(find.text('오늘 효율 +4'), findsOneWidget);
  });

  testWidgets('매칭되지 않은 박스스코어 선수는 선수 기록 보기 진입점을 숨긴다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _boxscoreHarness(
        boxscore: _displayableBoxscore,
        players: const <PlayerProfile>[],
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('강백호'), findsWidgets);
    expect(find.text('김영현'), findsWidgets);
    expect(find.text('선수 기록 보기'), findsNothing);
  });

  testWidgets('매칭된 박스스코어 선수 탭은 선수 상세로 이동한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _boxscoreHarness(
        boxscore: _displayableBoxscore,
        players: [
          _playerProfile(
            id: '50054',
            teamId: 'KT',
            name: '강백호',
            number: 50,
            playerType: PlayerType.hitter,
          ),
        ],
        withRoutes: true,
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('선수 기록 보기').first);
    await tester.pumpAndSettle();

    expect(find.text('player:50054'), findsOneWidget);
  });
}

const _liveGame = Game(
  gameId: '20260613KTLG0',
  status: GameStatus.live,
  inning: '1회초',
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

final _displayableBoxscore = GameBoxscoreData(
  gameId: '20260613KTLG0',
  officialAvailable: true,
  away: const TeamBoxscoreData(
    teamId: 'KT',
    batters: [
      BatterRecord(
        order: 3,
        position: '지',
        name: '강백호',
        atBats: 4,
        runs: 2,
        hits: 2,
        rbi: 3,
      ),
    ],
    pitchers: [
      PitcherRecord(
        name: '김영현',
        innings: '2.0',
        hits: 1,
        strikeouts: 2,
        walks: 0,
        earnedRuns: 0,
      ),
    ],
  ),
  home: const TeamBoxscoreData(teamId: 'LG', batters: [], pitchers: []),
);

Widget _boxscoreHarness({
  required GameBoxscoreData boxscore,
  required List<PlayerProfile> players,
  bool withRoutes = false,
}) {
  final overrides = [
    gameBoxscoreProvider.overrideWith((ref, gameId) async => boxscore),
    teamPlayersProvider.overrideWith((ref, key) async => players),
  ];

  Widget boxscoreTab() {
    return const Scaffold(
      body: BoxscoreTab(
        gameId: '20260613KTLG0',
        game: _liveGame,
        gameStatus: GameStatus.live,
        awayName: 'KT',
        homeName: 'LG',
        awayTeamId: 'KT',
        homeTeamId: 'LG',
      ),
    );
  }

  if (withRoutes) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => boxscoreTab()),
        GoRoute(
          path: '/records/player/:playerId',
          builder: (context, state) => Scaffold(
            body: Text('player:${state.pathParameters['playerId']}'),
          ),
        ),
      ],
    );

    return ProviderScope(
      retry: (_, _) => null,
      overrides: overrides,
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
  }

  return ProviderScope(
    retry: (_, _) => null,
    overrides: overrides,
    child: MaterialApp(theme: AppTheme.dark, home: boxscoreTab()),
  );
}

PlayerProfile _playerProfile({
  required String id,
  required String teamId,
  required String name,
  required int number,
  PlayerType playerType = PlayerType.hitter,
}) {
  return PlayerProfile(
    id: id,
    teamId: teamId,
    name: name,
    number: number,
    playerType: playerType,
    position: playerType == PlayerType.pitcher ? '투수' : '타자',
    roleLabel: playerType == PlayerType.pitcher ? '투수' : '야수',
    handedness: '',
    heightWeight: '',
    birthDate: '',
    status: PlayerAvailabilityStatus.available,
    rosterGroup: PlayerRosterGroup.entry,
    headlineStat: '',
    secondaryStat: '',
    seasonStats: const [],
    highlights: const [],
    recentGames: const [],
  );
}
