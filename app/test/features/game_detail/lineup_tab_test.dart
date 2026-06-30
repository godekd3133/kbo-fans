import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/boxscore.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/models/player.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/game_detail/tabs/lineup_tab.dart';

void main() {
  testWidgets('다크모드 라인업 타순은 검정 팀 컬러에서도 읽히는 색을 쓴다', (tester) async {
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
              gameId: '20260612KTLG0',
              away: TeamLineupData(
                teamId: 'KT',
                lineup: [
                  LineupEntry(
                    order: 1,
                    position: 'CF',
                    positionKo: '중견수',
                    name: '배정대',
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
            body: LineupTab(
              gameId: '20260612KTLG0',
              gameStatus: GameStatus.scheduled,
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

    final orderText = tester.widget<Text>(find.text('1'));
    final orderColor = orderText.style?.color;

    expect(orderColor, isNotNull);
    expect(
      _contrastRatio(orderColor!, AppTheme.darkColors.background),
      greaterThanOrEqualTo(4.5),
    );
  });

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

  testWidgets('라인업 row는 response의 선수 이미지 URL을 우선 표시한다', (tester) async {
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
              home: TeamLineupData(
                teamId: 'LG',
                lineup: [
                  LineupEntry(
                    order: 4,
                    position: '3B',
                    positionKo: '3루수',
                    name: '문보경',
                    imageUrl: 'https://img.test/2026/69102.jpg',
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

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CachedNetworkImage &&
            widget.imageUrl == 'https://img.test/2026/69102.jpg',
      ),
      findsOneWidget,
    );
  });

  testWidgets('라인업 row는 playerId만 있으면 경기 연도 기준 KBO 이미지 URL을 만든다', (
    tester,
  ) async {
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
              gameId: '20210425SKLG0',
              away: TeamLineupData(teamId: 'SK', lineup: []),
              home: TeamLineupData(
                teamId: 'LG',
                lineup: [
                  LineupEntry(
                    order: 4,
                    position: '3B',
                    positionKo: '3루수',
                    name: '문보경',
                    playerId: '69102',
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
              gameId: '20210425SKLG0',
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

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CachedNetworkImage &&
            widget.imageUrl.endsWith('/2022/69102.jpg'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('종료 경기 라인업 선발 비교는 박스스코어 투수 기록을 보여준다', (tester) async {
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
              gameId: '20260612KTLG0',
              away: TeamLineupData(
                teamId: 'KT',
                starterName: '고영표',
                lineup: [
                  LineupEntry(
                    order: 1,
                    position: 'CF',
                    positionKo: '중견수',
                    name: '배정대',
                  ),
                ],
              ),
              home: TeamLineupData(
                teamId: 'LG',
                starterName: '임찬규',
                lineup: [
                  LineupEntry(
                    order: 1,
                    position: 'RF',
                    positionKo: '우익수',
                    name: '홍창기',
                  ),
                ],
              ),
            );
          }),
          gameBoxscoreProvider.overrideWith((ref, gameId) async {
            return GameBoxscoreData(
              gameId: gameId,
              away: const TeamBoxscoreData(
                teamId: 'KT',
                batters: [],
                pitchers: [
                  PitcherRecord(
                    name: '고영표',
                    innings: '6.0',
                    hits: 6,
                    strikeouts: 4,
                    walks: 1,
                    earnedRuns: 2,
                    decision: 'W',
                  ),
                ],
              ),
              home: const TeamBoxscoreData(
                teamId: 'LG',
                batters: [],
                pitchers: [
                  PitcherRecord(
                    name: '임찬규',
                    innings: '4.2',
                    hits: 7,
                    strikeouts: 3,
                    walks: 3,
                    earnedRuns: 4,
                    decision: 'L',
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
              gameId: '20260612KTLG0',
              gameStatus: GameStatus.final_,
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

    expect(find.text('W'), findsOneWidget);
    expect(find.text('6.0'), findsOneWidget);
    expect(find.text('3.00'), findsOneWidget);
    expect(find.text('1.17'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    expect(find.text('4.2'), findsOneWidget);
    expect(find.text('7.71'), findsOneWidget);
    expect(find.text('2.14'), findsOneWidget);
  });
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
