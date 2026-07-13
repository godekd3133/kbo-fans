import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/constants/ticketing_policy.dart';

void main() {
  test('inferred ticket opening is 11:00 KST regardless of device zone', () {
    final ticket = TicketingPolicy.inferredTicketInfo(
      homeTeamId: 'LG',
      gameId: '20260624LGKT0',
      startTime: '18:30',
    );

    expect(ticket?.openAt, DateTime.utc(2026, 6, 17, 2));
  });

  test('invalid game date does not synthesize a ticket opening instant', () {
    final ticket = TicketingPolicy.inferredTicketInfo(
      homeTeamId: 'LG',
      gameId: '20260231LGKT0',
      startTime: '18:30',
    );

    expect(ticket?.openAt, isNull);
  });
}
