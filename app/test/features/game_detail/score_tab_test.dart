import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/features/game_detail/tabs/score_tab.dart';

void main() {
  testWidgets('스코어 탭은 연장 이닝을 동적으로 표시하고 팀 열을 고정한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semanticsHandle = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: ScoreTab(gameId: 'game-12', game: _extraGame),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('score-inning-header-10')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('score-inning-header-12')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('score-KT-inning-12')), findsOneWidget);
    expect(find.byKey(const ValueKey('score-LG-inning-12')), findsOneWidget);
    expect(find.text('R 득점 · H 안타 · E 실책 · B 사사구'), findsOneWidget);
    expect(find.textContaining('이닝을 누르면'), findsNothing);

    final horizontalScroll = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('score-scrollable-columns')),
    );
    expect(horizontalScroll.scrollDirection, Axis.horizontal);

    final fixedColumn = find.byKey(const ValueKey('score-fixed-team-column'));
    final fixedColumnX = tester.getTopLeft(fixedColumn).dx;
    await tester.drag(
      find.byKey(const ValueKey('score-scrollable-columns')),
      const Offset(-220, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(fixedColumn).dx, fixedColumnX);

    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('score-table-semantics')),
    );
    expect(semantics.label, contains('현재 12회말'));
    expect(semantics.label, contains('KT'));
    expect(semantics.label, contains('12회 1점'));
    expect(semantics.label, contains('합계 5점'));
    expect(semantics.label, contains('R은 득점'));
    semanticsHandle.dispose();
  });

  testWidgets('예정 경기의 이닝 기록이 없으면 경기 시작 안내를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: ScoreTab(gameId: 'scheduled-game', game: _scheduledGame),
        ),
      ),
    );

    expect(find.text('경기 시작 후 이닝별 기록이 표시됩니다.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('score-scrollable-columns')),
      findsNothing,
    );
    expect(find.text('R 득점 · H 안타 · E 실책 · B 사사구'), findsNothing);
  });

  testWidgets('취소 경기의 이닝 기록이 없으면 취소 안내를 표시한다', (tester) async {
    await _pumpScoreTab(tester, _gameWithoutInnings(GameStatus.cancelled));

    expect(find.text('경기 취소'), findsOneWidget);
    expect(find.text('취소된 경기라 이닝별 기록이 없습니다.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('score-scrollable-columns')),
      findsNothing,
    );
  });

  testWidgets('진행·종료 경기의 이닝 기록이 없으면 상단 총점 안내를 표시한다', (tester) async {
    for (final status in [GameStatus.live, GameStatus.final_]) {
      await _pumpScoreTab(tester, _gameWithoutInnings(status));

      expect(find.text('이닝별 기록 미제공'), findsOneWidget);
      expect(find.text('이닝별 기록이 제공되지 않았습니다. 상단 총점을 확인해 주세요.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('score-scrollable-columns')),
        findsNothing,
      );
    }
  });

  testWidgets('중단 경기의 이닝 기록이 없으면 중단 시점 안내를 표시한다', (tester) async {
    await _pumpScoreTab(tester, _gameWithoutInnings(GameStatus.suspended));

    expect(find.text('경기 중단'), findsOneWidget);
    expect(
      find.text('중단 시점의 이닝별 기록이 제공되지 않았습니다. 상단 총점을 확인해 주세요.'),
      findsOneWidget,
    );
  });
}

Future<void> _pumpScoreTab(WidgetTester tester, Game game) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: ScoreTab(gameId: game.gameId, game: game),
      ),
    ),
  );
}

Game _gameWithoutInnings(GameStatus status) {
  return Game(
    gameId: 'empty-${status.name}',
    status: status,
    inning: status == GameStatus.live ? '5회초' : '',
    away: const TeamScore(
      teamId: 'KT',
      teamName: 'KT 위즈',
      shortName: 'KT',
      score: 2,
      innings: [],
    ),
    home: const TeamScore(
      teamId: 'LG',
      teamName: 'LG 트윈스',
      shortName: 'LG',
      score: 1,
      innings: [],
    ),
    stadium: '잠실',
    startTime: '18:30',
  );
}

const _extraGame = Game(
  gameId: 'game-12',
  status: GameStatus.live,
  inning: '12회말',
  away: TeamScore(
    teamId: 'KT',
    teamName: 'KT 위즈',
    shortName: 'KT',
    score: 5,
    innings: [0, 1, 0, 0, 2, 0, 0, 1, 0, 0, 0, 1],
    hits: 10,
    errors: 1,
    walks: 4,
  ),
  home: TeamScore(
    teamId: 'LG',
    teamName: 'LG 트윈스',
    shortName: 'LG',
    score: 4,
    innings: [1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, null],
    hits: 8,
    errors: 0,
    walks: 3,
  ),
  stadium: '잠실',
  startTime: '18:30',
);

const _scheduledGame = Game(
  gameId: 'scheduled-game',
  status: GameStatus.scheduled,
  inning: '',
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
