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
