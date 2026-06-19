import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('매칭된 박스스코어 선수는 선수 기록 보기 CTA를 보여준다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpBoxscoreTab(
      tester,
      boxscore: _officialBoxscore,
      players: const [_matchedBatter],
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('오늘 기록 요약'), findsWidgets);
    expect(find.text('선수 기록 보기'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CachedNetworkImage &&
            widget.imageUrl == 'https://example.test/no.png',
      ),
      findsWidgets,
    );
  });

  testWidgets('미매칭 박스스코어 선수는 선수 기록 보기 CTA를 숨긴다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpBoxscoreTab(
      tester,
      boxscore: _officialBoxscore,
      players: const <PlayerProfile>[],
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('오늘 기록 요약'), findsWidgets);
    expect(find.text('선수 기록 보기'), findsNothing);
  });
}

Future<void> _pumpBoxscoreTab(
  WidgetTester tester, {
  required GameBoxscoreData boxscore,
  required List<PlayerProfile> players,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        gameBoxscoreProvider.overrideWith((ref, gameId) async => boxscore),
        teamPlayersProvider.overrideWith((ref, key) async => players),
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

const _officialBoxscore = GameBoxscoreData(
  gameId: '20260613KTLG0',
  officialAvailable: true,
  away: TeamBoxscoreData(
    teamId: 'KT',
    batters: [
      BatterRecord(
        order: 3,
        position: '3B',
        name: '노시환',
        atBats: 4,
        runs: 1,
        hits: 2,
        rbi: 1,
      ),
    ],
    pitchers: [
      PitcherRecord(
        name: '엄상백',
        innings: '3.1',
        hits: 3,
        strikeouts: 5,
        walks: 1,
        earnedRuns: 1,
      ),
    ],
  ),
  home: TeamBoxscoreData(
    teamId: 'LG',
    batters: [
      BatterRecord(
        order: 4,
        position: '1B',
        name: '김현수',
        atBats: 4,
        runs: 0,
        hits: 1,
        rbi: 0,
      ),
    ],
    pitchers: [
      PitcherRecord(
        name: '임찬규',
        innings: '4.0',
        hits: 4,
        strikeouts: 3,
        walks: 1,
        earnedRuns: 2,
      ),
    ],
  ),
);

const _matchedBatter = PlayerProfile(
  id: 'p-no',
  teamId: 'KT',
  playerType: PlayerType.hitter,
  name: '노시환',
  number: 8,
  position: '3B',
  roleLabel: '내야수',
  handedness: '우투우타',
  heightWeight: '',
  birthDate: '',
  status: PlayerAvailabilityStatus.available,
  rosterGroup: PlayerRosterGroup.entry,
  headlineStat: '',
  secondaryStat: '',
  seasonStats: [],
  highlights: [],
  recentGames: [],
  imageUrl: 'https://example.test/no.png',
);
