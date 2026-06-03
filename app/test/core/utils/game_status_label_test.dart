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
}
