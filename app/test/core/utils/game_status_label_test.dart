import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/utils/game_status_label.dart';
import 'package:kbo_fans/data/models/game.dart';

void main() {
  test('cancelled status uses explicit rain-cancel label when provided', () {
    expect(
      labelForGameStatus(GameStatus.cancelled, statusLabel: '우천취소'),
      '우천취소',
    );
    expect(
      secondaryTextForGameStatus(
        GameStatus.cancelled,
        inning: '경기취소',
        statusLabel: '우천취소',
      ),
      '우천취소',
    );
    expect(labelForScheduleStatus('CANCELLED', statusLabel: '우천취소'), '우천취소');
  });

  test('cancelled status falls back to generic label without reason', () {
    expect(labelForGameStatus(GameStatus.cancelled), '경기 취소');
    expect(labelForScheduleStatus('CANCELLED'), '경기 취소');
  });

  test('ticket info is visible only before the game starts', () {
    expect(shouldShowTicketInfoForGameStatus(GameStatus.scheduled), isTrue);
    expect(shouldShowTicketInfoForGameStatus(GameStatus.live), isFalse);
    expect(shouldShowTicketInfoForGameStatus(GameStatus.final_), isFalse);
    expect(shouldShowTicketInfoForGameStatus(GameStatus.cancelled), isFalse);
    expect(shouldShowTicketInfoForGameStatus(GameStatus.suspended), isFalse);

    expect(shouldShowTicketInfoForScheduleStatus('SCHEDULED'), isTrue);
    expect(shouldShowTicketInfoForScheduleStatus(''), isTrue);
    expect(shouldShowTicketInfoForScheduleStatus('LIVE'), isFalse);
    expect(shouldShowTicketInfoForScheduleStatus('FINAL'), isFalse);
    expect(shouldShowTicketInfoForScheduleStatus('CANCELLED'), isFalse);
    expect(shouldShowTicketInfoForScheduleStatus('SUSPENDED'), isFalse);
  });
}
