import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/utils/kbo_time.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/boxscore.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/models/player.dart';
import 'package:kbo_fans/data/models/records_overview.dart';
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
    expect(find.text('1회초'), findsWidgets);
    expect(find.textContaining('두산공격'), findsNothing);
  });

  testWidgets('문자중계 상단 스코어보드는 R/H/E 합계를 같이 보여준다', (tester) async {
    const game = Game(
      gameId: '20260612OBLT0',
      status: GameStatus.live,
      inning: '5회말',
      away: TeamScore(
        teamId: 'OB',
        teamName: '두산 베어스',
        shortName: '두산',
        score: 12,
        innings: [5, 0, 7],
        hits: 14,
        errors: 1,
        walks: 4,
      ),
      home: TeamScore(
        teamId: 'LT',
        teamName: '롯데 자이언츠',
        shortName: '롯데',
        score: 8,
        innings: [1, 2, 5],
        hits: 13,
        errors: 2,
        walks: 6,
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
            return const RelayData(currentAtBat: null, relayItems: []);
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

    expect(find.text('R'), findsOneWidget);
    expect(find.text('H'), findsOneWidget);
    expect(find.text('E'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
  });

  testWidgets('현재 타석 타자는 이름 라벨과 이미지 등번호를 분리한다', (tester) async {
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
    expect(find.text('39'), findsOneWidget);
    expect(find.textContaining('39번 김성윤'), findsNothing);
  });

  testWidgets('중계 베이스 다이아몬드는 1,2루 주자를 모두 채운다', (tester) async {
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
                baseState: '주자1,2루',
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
              away: TeamLineupData(teamId: 'SS', lineup: []),
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

    expect(find.text('주자1,2루'), findsWidgets);
    expect(_filledLargeRelayBaseCount(tester), 2);
  });

  testWidgets('relay scorebug는 280·320px 240%에서 세로 재배치하고 점수 미확인을 보존한다', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      for (final width in const [280.0, 320.0]) {
        tester.view.physicalSize = Size(width, 844);
        await _pumpAdaptiveRelayScorebug(
          tester,
          textScaler: const TextScaler.linear(2.4),
        );

        expect(
          find.byKey(const ValueKey('relay-scorebug-adaptive-layout')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('relay-scorebug-wide-layout')),
          findsNothing,
        );
        expect(find.text('서울 장거리 원정 히어로즈'), findsWidgets);
        expect(find.text('부산 장거리 홈 자이언츠'), findsWidgets);
        expect(find.text('김테스트매우긴타자이름'), findsWidgets);
        expect(find.text('박테스트매우긴투수이름'), findsWidgets);
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('relay-scorebug-away-score')),
              )
              .data,
          '–',
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('relay-scorebug-home-score')),
              )
              .data,
          '–',
        );

        final scorebugSemantics = tester
            .getSemantics(
              find.byKey(const ValueKey('relay-broadcast-scorebug-semantics')),
            )
            .getSemanticsData();
        expect(scorebugSemantics.label, contains('서울 장거리 원정 히어로즈 –'));
        expect(scorebugSemantics.label, contains('부산 장거리 홈 자이언츠 –'));
        expect(scorebugSemantics.label, contains('김테스트매우긴타자이름'));
        expect(scorebugSemantics.label, contains('박테스트매우긴투수이름'));
        expect(scorebugSemantics.label, contains('볼 3, 스트라이크 2, 아웃 1'));
        expect(tester.takeException(), isNull);
      }

      tester.view.physicalSize = const Size(390, 844);
      await _pumpAdaptiveRelayScorebug(tester);
      expect(
        find.byKey(const ValueKey('relay-scorebug-wide-layout')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('relay-scorebug-adaptive-layout')),
        findsNothing,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('relay-scorebug-away-score')),
            )
            .data,
        '–',
      );
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('중계 주요 장면 필터는 선택한 이벤트 카드만 남긴다', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
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
                baseState: '주자1,2루',
                balls: 1,
                strikes: 2,
                outs: 1,
              ),
              relayItems: [
                RelayItem(
                  seqNo: 4,
                  inning: 7,
                  half: 'top',
                  event: 'OUT',
                  text: '구자욱: 중견수 플라이 아웃',
                ),
                RelayItem(
                  seqNo: 3,
                  inning: 7,
                  half: 'top',
                  event: 'SUBSTITUTION',
                  text: '대주자 김헌곤',
                ),
                RelayItem(
                  seqNo: 2,
                  inning: 7,
                  half: 'top',
                  event: 'HOMERUN',
                  isScoring: true,
                  text: '오스틴: 좌월 홈런',
                ),
                RelayItem(
                  seqNo: 1,
                  inning: 7,
                  half: 'top',
                  event: 'HIT',
                  text: '김성윤: 중전 안타',
                ),
              ],
            );
          }),
          gameLineupProvider.overrideWith((ref, gameId) async {
            return const GameLineupData(
              gameId: '20260611SSLG0',
              away: TeamLineupData(teamId: 'SS', lineup: []),
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

    expect(find.text('안타 1'), findsOneWidget);
    expect(find.text('홈런 1'), findsOneWidget);
    expect(find.text('교체 1'), findsOneWidget);

    await tester.tap(find.text('홈런 1'));
    await tester.pumpAndSettle();

    expect(find.text('오스틴: 좌월 홈런'), findsOneWidget);
    expect(find.text('김성윤: 중전 안타'), findsNothing);
    expect(find.text('구자욱: 중견수 플라이 아웃'), findsNothing);
  });

  testWidgets('득점 필터는 타자와 홈인 주자를 함께 보여준다', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
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
        score: 5,
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
              currentAtBat: null,
              relayItems: [
                RelayItem(
                  seqNo: 2,
                  inning: 7,
                  half: 'top',
                  event: 'RUNS',
                  isScoring: true,
                  text: '오지환: 우중간 2루타, 박해민 홈인, 홍창기 홈인',
                ),
                RelayItem(
                  seqNo: 1,
                  inning: 7,
                  half: 'top',
                  event: 'HIT',
                  text: '문성주: 중전 안타',
                ),
              ],
            );
          }),
          gameLineupProvider.overrideWith((ref, gameId) async {
            return const GameLineupData(
              gameId: '20260611SSLG0',
              away: TeamLineupData(teamId: 'SS', lineup: []),
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

    await tester.tap(find.text('득점 1'));
    await tester.pumpAndSettle();

    expect(find.text('친 선수'), findsOneWidget);
    expect(find.text('오지환'), findsAtLeastNWidgets(1));
    expect(find.text('홈인'), findsOneWidget);
    expect(find.text('박해민, 홍창기'), findsOneWidget);
    expect(find.text('문성주: 중전 안타'), findsNothing);
  });

  testWidgets('종료 경기는 stale 현재 타석 카드를 노출하지 않는다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const game = Game(
      gameId: '20260629SSLG0',
      status: GameStatus.final_,
      inning: '경기종료',
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
        score: 4,
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
                batterName: '디아즈',
                batterNumber: 4,
                batterHand: '좌타',
                batterRecent: '플라이4구12루타땅볼',
                pitcherName: '손주영',
                pitcherNumber: 29,
                pitcherHand: '좌투',
                pitchCount: 37,
                inningText: '9회 초',
                balls: 1,
                strikes: 3,
                outs: 3,
              ),
              relayItems: [
                RelayItem(
                  seqNo: 1,
                  inning: 9,
                  half: 'top',
                  event: 'GAME_END',
                  text: '경기종료 삼성 3 : 4 LG',
                ),
              ],
            );
          }),
          gameLineupProvider.overrideWith((ref, gameId) async {
            return const GameLineupData(
              gameId: '20260629SSLG0',
              away: TeamLineupData(teamId: 'SS', lineup: []),
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
              gameId: '20260629SSLG0',
              gameStatus: GameStatus.final_,
              game: game,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('현재 타석'), findsNothing);
    expect(find.textContaining('B 1'), findsNothing);
    expect(find.textContaining('S 3'), findsNothing);
    expect(find.textContaining('O 3'), findsNothing);
    expect(find.text('경기종료 삼성 3 : 4 LG'), findsOneWidget);
  });

  testWidgets('현재 타석은 프로필 id로 선수 사진을 gameId 시즌에 맞춰 렌더한다', (tester) async {
    const game = Game(
      gameId: '20250611SSLG0',
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
              gameId: '20250611SSLG0',
              away: TeamLineupData(teamId: 'SS', lineup: []),
              home: TeamLineupData(teamId: 'LG', lineup: []),
            );
          }),
          teamPlayersProvider.overrideWith((ref, key) async {
            if (key.startsWith('SS|')) {
              return [_playerProfile(id: '56348', teamId: 'SS', name: '김성윤')];
            }
            return const <PlayerProfile>[];
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: RelayTab(
              gameId: '20250611SSLG0',
              gameStatus: GameStatus.live,
              game: game,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('김성윤'), findsWidgets);
    expect(find.textContaining('임찬규'), findsWidgets);
    final expectedImageUrl = kboPlayerImageUrl(season: 2025, playerId: '56348');
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CachedNetworkImage && widget.imageUrl == expectedImageUrl,
      ),
      findsOneWidget,
    );
  });

  testWidgets('라이트모드 중계 이벤트는 light surface와 선수 등번호 배지를 쓴다', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => AppColors.sync(AppTheme.darkColors));
    AppColors.sync(AppTheme.lightColors);

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
              currentAtBat: null,
              relayItems: [
                RelayItem(
                  seqNo: 1,
                  inning: 7,
                  half: 'top',
                  event: 'HIT',
                  text: '김성윤: 중전 안타',
                ),
              ],
            );
          }),
          gameLineupProvider.overrideWith((ref, gameId) async {
            return const GameLineupData(
              gameId: '20260611SSLG0',
              away: TeamLineupData(teamId: 'SS', lineup: []),
              home: TeamLineupData(teamId: 'LG', lineup: []),
            );
          }),
          teamPlayersProvider.overrideWith((ref, key) async {
            if (key.startsWith('SS|')) {
              return [
                _playerProfile(
                  id: '56348',
                  teamId: 'SS',
                  name: '김성윤',
                  number: 39,
                ),
              ];
            }
            return const <PlayerProfile>[];
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
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

    final expectedImageUrl = kboPlayerImageUrl(
      season: kboCurrentSeason(),
      playerId: '56348',
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CachedNetworkImage && widget.imageUrl == expectedImageUrl,
      ),
      findsOneWidget,
    );
    expect(find.text('39'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('전체 1')).style?.color,
      AppTheme.lightColors.readableForegroundOn(AppTheme.lightColors.live),
    );

    final darkFixedContainers = tester
        .widgetList<Container>(find.byType(Container))
        .where((container) {
          final decoration = container.decoration;
          return decoration is BoxDecoration &&
              decoration.color == const Color(0xFF1E1E1E);
        });
    expect(darkFixedContainers, isEmpty);

    final lightSurfaceContainers = tester
        .widgetList<Container>(find.byType(Container))
        .where((container) {
          final decoration = container.decoration;
          return decoration is BoxDecoration &&
              decoration.color == AppTheme.lightColors.card;
        });
    expect(lightSurfaceContainers, isNotEmpty);
  });

  testWidgets('중계 이벤트는 이미지 URL로 선수 사진을 렌더한다', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
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
    const sourceImageUrl =
        'https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/person/middle/2026/56348.jpg';

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          gameProvider.overrideWith((ref, gameId) async => game),
          relayDataProvider.overrideWith((ref, gameId) async {
            return const RelayData(
              currentAtBat: CurrentAtBat(
                batterName: '김성윤',
                batterImageUrl: sourceImageUrl,
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
              relayItems: [
                RelayItem(
                  seqNo: 1,
                  inning: 7,
                  half: 'top',
                  event: 'HIT',
                  text: '김성윤: 중전 안타',
                ),
              ],
            );
          }),
          gameLineupProvider.overrideWith((ref, gameId) async {
            return const GameLineupData(
              gameId: '20260611SSLG0',
              away: TeamLineupData(teamId: 'SS', lineup: []),
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

    expect(find.textContaining('김성윤'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CachedNetworkImage && widget.imageUrl == sourceImageUrl,
      ),
      findsAtLeastNWidgets(1),
    );
  });
}

Future<void> _pumpAdaptiveRelayScorebug(
  WidgetTester tester, {
  TextScaler? textScaler,
}) async {
  const game = Game(
    gameId: '20260611SSLG9',
    status: GameStatus.live,
    inning: '연장 12회초',
    away: TeamScore(
      teamId: 'SS',
      teamName: '서울 장거리 원정 히어로즈',
      shortName: '삼성',
      score: 0,
      scoreAvailable: false,
      innings: [],
    ),
    home: TeamScore(
      teamId: 'LG',
      teamName: '부산 장거리 홈 자이언츠',
      shortName: 'LG',
      score: 0,
      scoreAvailable: false,
      innings: [],
    ),
    stadium: '서울종합운동장 야구장',
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
              batterName: '김테스트매우긴타자이름',
              batterNumber: 99,
              batterHand: '좌타',
              batterRecent: '볼넷 2루타 중전안타 우익수플라이',
              pitcherName: '박테스트매우긴투수이름',
              pitcherNumber: 98,
              pitcherHand: '우투',
              pitchCount: 123,
              inningText: '연장 12회초',
              baseState: '주자1,2루',
              balls: 3,
              strikes: 2,
              outs: 1,
            ),
            relayItems: [],
          );
        }),
        gameLineupProvider.overrideWith((ref, gameId) async {
          return const GameLineupData(
            gameId: '20260611SSLG9',
            away: TeamLineupData(teamId: 'SS', lineup: []),
            home: TeamLineupData(teamId: 'LG', lineup: []),
          );
        }),
        teamPlayersProvider.overrideWith((ref, key) async {
          return const <PlayerProfile>[];
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        builder: textScaler == null
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: child ?? const SizedBox.shrink(),
              ),
        home: const Scaffold(
          body: RelayTab(
            gameId: '20260611SSLG9',
            gameStatus: GameStatus.live,
            game: game,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

int _filledLargeRelayBaseCount(WidgetTester tester) {
  return tester.widgetList<Container>(find.byType(Container)).where((
    container,
  ) {
    final decoration = container.decoration;
    if (decoration is! BoxDecoration) {
      return false;
    }
    final border = decoration.border;
    if (border is! Border) {
      return false;
    }
    final constraints = container.constraints;
    final isRelayBaseTile =
        constraints?.minWidth == 24 &&
        constraints?.maxWidth == 24 &&
        constraints?.minHeight == 24 &&
        constraints?.maxHeight == 24 &&
        border.top.width == 1.8 &&
        border.top.color == AppColors.textPrimary;
    return isRelayBaseTile && decoration.color == AppColors.textPrimary;
  }).length;
}

PlayerProfile _playerProfile({
  required String id,
  required String teamId,
  required String name,
  int number = 0,
}) {
  return PlayerProfile(
    id: id,
    teamId: teamId,
    name: name,
    number: number,
    position: '외야수',
    roleLabel: '외야수',
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
