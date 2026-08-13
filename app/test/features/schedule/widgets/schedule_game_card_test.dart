import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/features/schedule/widgets/schedule_game_card.dart';
import 'package:kbo_fans/data/models/schedule.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark,
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

  testWidgets('종료 경기는 예매 요약을 숨긴다', (tester) async {
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
      wrap(
        const ScheduleGameCard(
          game: game,
          ticketSummary: '인터파크 티켓 · 03.21 11:00 오픈',
          showTeamLogos: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.confirmation_num_outlined), findsNothing);
    expect(find.textContaining('인터파크 티켓'), findsNothing);
  });

  testWidgets('진행 중 경기는 예매 요약을 숨긴다', (tester) async {
    const game = ScheduleGame(
      gameId: '20260328KTLG0',
      time: '14:00',
      awayId: 'KT',
      awayName: 'KT',
      awayScore: 1,
      homeId: 'LG',
      homeName: 'LG',
      homeScore: 0,
      stadium: '잠실',
      status: 'LIVE',
    );

    await tester.pumpWidget(
      wrap(
        const ScheduleGameCard(
          game: game,
          ticketSummary: '인터파크 티켓 · 03.21 11:00 오픈',
          showTeamLogos: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('경기 중'), findsOneWidget);
    expect(find.byIcon(Icons.confirmation_num_outlined), findsNothing);
    expect(find.textContaining('인터파크 티켓'), findsNothing);
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

  testWidgets('예정 경기 카드의 날짜·구장·대결 표시는 지원 텍스트를 쓴다', (tester) async {
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
      wrap(
        const ScheduleGameCard(
          game: game,
          dateLabel: '3월 31일',
          showTeamLogos: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in const ['3월 31일', '잠실', 'vs']) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.style?.color, AppTheme.darkColors.textSupporting);
    }
  });

  testWidgets('예정 경기는 0:0 점수가 들어와도 vs를 노출한다', (tester) async {
    const game = ScheduleGame(
      gameId: '20260331KTLG0',
      time: '18:30',
      awayId: 'KT',
      awayName: 'KT',
      awayScore: 0,
      homeId: 'LG',
      homeName: 'LG',
      homeScore: 0,
      stadium: '잠실',
      status: 'SCHEDULED',
    );

    await tester.pumpWidget(
      wrap(const ScheduleGameCard(game: game, showTeamLogos: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('경기 전'), findsOneWidget);
    expect(find.text('vs'), findsOneWidget);
    expect(find.text('0'), findsNothing);
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

  testWidgets('우천취소 경기는 우천취소 라벨과 vs를 노출한다', (tester) async {
    const game = ScheduleGame(
      gameId: '20260520KTSS0',
      time: '18:30',
      awayId: 'KT',
      awayName: 'KT',
      homeId: 'SS',
      homeName: '삼성',
      stadium: '포항',
      status: 'CANCELLED',
      statusLabel: '우천취소',
    );

    await tester.pumpWidget(
      wrap(const ScheduleGameCard(game: game, showTeamLogos: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('우천취소'), findsOneWidget);
    expect(find.text('경기 취소'), findsNothing);
    expect(find.text('vs'), findsOneWidget);
  });

  testWidgets('320px 240%에서도 예정 경기 정보가 잘리지 않는다', (tester) async {
    const game = ScheduleGame(
      gameId: '20260520KTSS0',
      time: '18:30',
      awayId: 'KT',
      awayName: 'KT 위즈',
      homeId: 'SS',
      homeName: '삼성 라이온즈',
      stadium: '대구 삼성 라이온즈 파크',
      status: 'SCHEDULED',
    );

    await tester.binding.setSurfaceSize(const Size(320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 844),
            textScaler: TextScaler.linear(2.4),
          ),
          child: const Scaffold(
            body: SingleChildScrollView(
              child: ScheduleGameCard(
                game: game,
                dateLabel: '5월 20일 수요일',
                ticketSummary: '인터파크 티켓 · 05.13 11:00 오픈 예정',
                myTeamId: 'SS',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final text in const [
      '5월 20일 수요일',
      '18:30',
      '경기 전',
      '대구 삼성 라이온즈 파크',
      '인터파크 티켓 · 05.13 11:00 오픈 예정',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
  });
}
