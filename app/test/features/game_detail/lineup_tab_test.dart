import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/boxscore.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/models/player.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/game_detail/tabs/lineup_tab.dart';

void main() {
  testWidgets('경기 전이라도 공개된 라인업은 라인업 탭에서 보여준다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          gameLineupProvider.overrideWith((ref, gameId) async {
            return const GameLineupData(
              gameId: '20260612SKLG0',
              away: TeamLineupData(
                teamId: 'SK',
                starterId: '51867',
                starterName: '김건우',
                lineup: [
                  LineupEntry(
                    order: 1,
                    position: 'SS',
                    positionKo: '유격수',
                    name: '박성한',
                    statValue: '3.62',
                  ),
                ],
              ),
              home: TeamLineupData(
                teamId: 'LG',
                starterId: '50157',
                starterName: '김윤식',
                lineup: [
                  LineupEntry(
                    order: 1,
                    position: 'RF',
                    positionKo: '우익수',
                    name: '홍창기',
                    statValue: '0.82',
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
            body: LineupTab(
              gameId: '20260612SKLG0',
              gameStatus: GameStatus.scheduled,
              awayName: 'SSG',
              homeName: 'LG',
              awayTeamId: 'SK',
              homeTeamId: 'LG',
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('경기 시작 후 라인업이 공개됩니다'), findsNothing);
    expect(find.text('박성한'), findsOneWidget);
    expect(find.text('홍창기'), findsOneWidget);
    expect(find.textContaining('지표 3.62'), findsOneWidget);
  });

  testWidgets('경기 전 라인업이 아직 비어 있으면 공개 전 상태를 보여준다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          gameLineupProvider.overrideWith((ref, gameId) async {
            return const GameLineupData(
              gameId: '20260612SKLG0',
              away: TeamLineupData(teamId: 'SK', lineup: []),
              home: TeamLineupData(teamId: 'LG', lineup: []),
            );
          }),
          teamPlayersProvider.overrideWith((ref, key) async {
            return const <PlayerProfile>[];
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: LineupTab(
              gameId: '20260612SKLG0',
              gameStatus: GameStatus.scheduled,
              awayName: 'SSG',
              homeName: 'LG',
              awayTeamId: 'SK',
              homeTeamId: 'LG',
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('경기 시작 후 라인업이 공개됩니다'), findsNothing);
    expect(find.text('라인업 공개 전입니다'), findsOneWidget);
  });
}
