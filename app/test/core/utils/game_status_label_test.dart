import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/utils/game_status_label.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/models/ticketing.dart';

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

  test(
    'game detail ticket info is hidden from two hours before first pitch',
    () {
      final game = _scheduledGame();

      expect(
        shouldShowTicketInfoForGameDetail(
          game,
          now: DateTime(2026, 5, 20, 16, 29),
        ),
        isTrue,
      );
      expect(
        shouldShowTicketInfoForGameDetail(
          game,
          now: DateTime(2026, 5, 20, 16, 30),
        ),
        isFalse,
      );
      expect(
        shouldShowTicketInfoForGameDetail(
          game,
          now: DateTime(2026, 5, 20, 18, 29),
        ),
        isFalse,
      );
    },
  );

  test('game detail ticket info remains hidden for non-scheduled games', () {
    final liveGame = _scheduledGame(status: GameStatus.live);

    expect(
      shouldShowTicketInfoForGameDetail(
        liveGame,
        now: DateTime(2026, 5, 20, 12),
      ),
      isFalse,
    );
  });
}

Game _scheduledGame({GameStatus status = GameStatus.scheduled}) {
  return Game(
    gameId: '20260520KTLG0',
    status: status,
    inning: '',
    away: const TeamScore(
      teamId: 'KT',
      teamName: 'KT 위즈',
      shortName: 'KT',
      score: 0,
      innings: [],
    ),
    home: const TeamScore(
      teamId: 'LG',
      teamName: 'LG 트윈스',
      shortName: 'LG',
      score: 0,
      innings: [],
    ),
    stadium: '잠실',
    startTime: '18:30',
    ticketInfo: const TicketInfo(vendorKey: 'interpark', vendorName: '인터파크 티켓'),
  );
}
