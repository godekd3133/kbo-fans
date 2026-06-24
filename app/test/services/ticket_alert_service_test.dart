import 'package:flutter_test/flutter_test.dart';

import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/models/ticketing.dart';
import 'package:kbo_fans/services/ticket_alert_service.dart';

void main() {
  test('예매 알림 제목은 KBO 팀 ID를 팬이 보는 짧은 팀명으로 바꾼다', () {
    final title = buildTicketAlertTitle(
      Game(
        gameId: '20260624SSSK0',
        status: GameStatus.scheduled,
        inning: '경기전',
        away: const TeamScore(
          teamId: 'SS',
          teamName: '삼성 라이온즈',
          shortName: 'SS',
          score: 0,
          innings: [],
        ),
        home: const TeamScore(
          teamId: 'SK',
          teamName: 'SSG 랜더스',
          shortName: 'SK',
          score: 0,
          innings: [],
        ),
        stadium: '대구',
        startTime: '18:30',
        ticketInfo: TicketInfo(
          vendorKey: 'ticketlink',
          vendorName: '티켓링크',
          openAt: DateTime(2026, 6, 24, 11),
        ),
      ),
    );

    expect(title, '삼성 vs SSG 예매 알림');
  });
}
