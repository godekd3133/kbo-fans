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
