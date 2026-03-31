import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/features/schedule/widgets/schedule_game_card.dart';
import 'package:kbo_fans/data/models/schedule.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 390, child: child)),
      ),
    );
  }

  testWidgets('종료 경기는 경기 종료 라벨과 점수를 노출한다', (tester) async {
    const game = ScheduleGame(
      gameId: '20260328KTLG0',
      time: '14:00',
      awayId: 'KT',
      awayName: 'KT',
      awayScore: 11,
      homeId: 'LG',
      homeName: 'LG',
      homeScore: 7,
      stadium: '잠실',
      status: 'FINAL',
    );

    await tester.pumpWidget(
      wrap(const ScheduleGameCard(game: game, showTeamLogos: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('경기 종료'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('vs'), findsNothing);
  });

  testWidgets('예정 경기는 경기 전 라벨과 vs를 노출한다', (tester) async {
    const game = ScheduleGame(
      gameId: '20260331KTLG0',
      time: '18:30',
      awayId: 'KT',
      awayName: 'KT',
      homeId: 'LG',
      homeName: 'LG',
      stadium: '잠실',
      status: 'SCHEDULED',
    );

    await tester.pumpWidget(
      wrap(const ScheduleGameCard(game: game, showTeamLogos: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('경기 전'), findsOneWidget);
    expect(find.text('vs'), findsOneWidget);
  });

  testWidgets('서스펜디드 경기는 서스펜디드 라벨을 노출한다', (tester) async {
    const game = ScheduleGame(
      gameId: '20260331KTLG0',
      time: '18:30',
      awayId: 'KT',
      awayName: 'KT',
      homeId: 'LG',
      homeName: 'LG',
      stadium: '잠실',
      status: 'SUSPENDED',
    );

    await tester.pumpWidget(
      wrap(const ScheduleGameCard(game: game, showTeamLogos: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('서스펜디드'), findsOneWidget);
  });
}
