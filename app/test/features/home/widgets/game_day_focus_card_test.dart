import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/models/schedule.dart';
import 'package:kbo_fans/features/home/widgets/game_day_focus_card.dart';

Game fixture(GameStatus status, {bool available = true}) => Game(
  gameId: '20260907SSLG0',
  status: status,
  inning: '',
  stadium: '잠실',
  startTime: '18:30',
  away: TeamScore(
    teamId: 'SS',
    teamName: '삼성',
    shortName: '삼성',
    score: 0,
    scoreAvailable: available,
    innings: const [],
  ),
  home: const TeamScore(
    teamId: 'LG',
    teamName: 'LG',
    shortName: 'LG',
    score: 1,
    innings: [],
  ),
);

void main() {
  test(
    'doubleheader chooses live then scheduled instead of cancelled or final',
    () {
      final cancelled = fixture(GameStatus.cancelled);
      final finalGame = fixture(GameStatus.final_);
      final scheduled = fixture(GameStatus.scheduled);
      final live = fixture(GameStatus.live);
      expect(
        selectMyTeamFocusGame([cancelled, finalGame, scheduled], 'LG'),
        same(scheduled),
      );
      expect(
        selectMyTeamFocusGame([finalGame, scheduled, live], 'LG'),
        same(live),
      );
      expect(selectMyTeamFocusGame([live], 'KT'), isNull);
      expect(selectMyTeamFocusGame([live], null), isNull);
    },
  );
  testWidgets(
    'unknown score never turns into zero, primary action works at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 844),
                textScaler: TextScaler.linear(2.4),
              ),
              child: SingleChildScrollView(
                child: GameDayFocusCard(
                  myTeamId: 'LG',
                  game: fixture(GameStatus.final_, available: false),
                  nextGame: null,
                  todayGameCount: 1,
                  nextGameLoading: false,
                  onOpenGame: () => opens++,
                  onOpenSchedule: () {},
                  onSelectTeam: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('– : 1'), findsOneWidget);
      expect(find.text('공식 점수 확인 중'), findsOneWidget);
      await tester.ensureVisible(find.text('경기 결과 자세히'));
      await tester.tap(find.text('경기 결과 자세히'));
      expect(opens, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('off day shows verified next date and schedule action', (
    tester,
  ) async {
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: GameDayFocusCard(
            myTeamId: 'LG',
            game: null,
            nextGame: const ScheduleGame(
              gameId: '20260908WOLG0',
              time: '18:30',
              awayId: 'WO',
              awayName: '키움',
              homeId: 'LG',
              homeName: 'LG',
              stadium: '잠실',
            ),
            todayGameCount: 0,
            nextGameLoading: false,
            onOpenGame: () {},
            onOpenSchedule: () => opens++,
            onSelectTeam: () {},
          ),
        ),
      ),
    );
    expect(find.textContaining('9월 8일 18:30'), findsOneWidget);
    await tester.tap(find.text('다음 경기 일정 보기'));
    expect(opens, 1);
    expect(tester.takeException(), isNull);
  });
}
