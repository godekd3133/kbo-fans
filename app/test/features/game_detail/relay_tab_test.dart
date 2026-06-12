import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/boxscore.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/models/player.dart';
import 'package:kbo_fans/data/models/relay.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/game_detail/tabs/relay_tab.dart';

void main() {
  testWidgets('이닝 전환 원문의 공격 배너는 회차 버튼으로 노출하지 않는다', (tester) async {
    const game = Game(
      gameId: '20260612OBLT0',
      status: GameStatus.live,
      inning: '1회초',
      away: TeamScore(
        teamId: 'OB',
        teamName: '두산 베어스',
        shortName: '두산',
        score: 0,
        innings: [],
      ),
      home: TeamScore(
        teamId: 'LT',
        teamName: '롯데 자이언츠',
        shortName: '롯데',
        score: 0,
        innings: [],
      ),
      stadium: '사직',
      startTime: '18:30',
    );

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          gameProvider.overrideWith((ref, gameId) async => game),
          relayDataProvider.overrideWith((ref, gameId) async {
            return const RelayData(
              currentAtBat: null,
              relayItems: [
                RelayItem(
                  seqNo: 1,
                  inning: 1,
                  half: 'top',
                  event: 'INNING_CHANGE',
                  text: '1회초 두산공격--------------',
                ),
                RelayItem(
                  seqNo: 2,
                  inning: 1,
                  half: 'top',
                  event: 'PLAY',
                  text: '정수빈: 중전 안타',
                ),
              ],
            );
          }),
          gameLineupProvider.overrideWith((ref, gameId) async {
            return const GameLineupData(
              gameId: '20260612OBLT0',
              away: TeamLineupData(teamId: 'OB', lineup: []),
              home: TeamLineupData(teamId: 'LT', lineup: []),
            );
          }),
          teamPlayersProvider.overrideWith((ref, key) async {
            return const <PlayerProfile>[];
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: RelayTab(
              gameId: '20260612OBLT0',
              gameStatus: GameStatus.live,
              game: game,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('전체'), findsOneWidget);
    expect(find.text('1회초'), findsNWidgets(2));
    expect(find.textContaining('두산공격'), findsNothing);
  });

  testWidgets('현재 타석 타자는 등번호 대신 타순 이름 포지션으로 표시한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const game = Game(
      gameId: '20260611SSLG0',
      status: GameStatus.live,
      inning: '7회초',
      away: TeamScore(
        teamId: 'SS',
        teamName: '삼성 라이온즈',
        shortName: '삼성',
        score: 3,
        innings: [],
      ),
      home: TeamScore(
        teamId: 'LG',
        teamName: 'LG 트윈스',
        shortName: 'LG',
        score: 2,
        innings: [],
      ),
      stadium: '잠실',
      startTime: '18:30',
    );

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          gameProvider.overrideWith((ref, gameId) async => game),
          relayDataProvider.overrideWith((ref, gameId) async {
            return const RelayData(
              currentAtBat: CurrentAtBat(
                batterName: '김성윤',
                batterNumber: 39,
                batterHand: '좌타',
                pitcherName: '임찬규',
                pitcherNumber: 1,
                pitcherHand: '우투',
                pitchCount: 12,
                inningText: '7회초',
                balls: 1,
                strikes: 2,
                outs: 1,
              ),
              relayItems: [],
            );
          }),
          gameLineupProvider.overrideWith((ref, gameId) async {
            return const GameLineupData(
              gameId: '20260611SSLG0',
              away: TeamLineupData(
                teamId: 'SS',
                lineup: [
                  LineupEntry(
                    order: 9,
                    position: 'LF',
                    positionKo: '좌익수',
                    name: '김성윤',
                  ),
                ],
              ),
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
            body: RelayTab(
              gameId: '20260611SSLG0',
              gameStatus: GameStatus.live,
              game: game,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('9 김성윤 LF'), findsOneWidget);
    expect(find.textContaining('39번 김성윤'), findsNothing);
  });
}
