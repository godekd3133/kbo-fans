import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/data/models/schedule.dart';

void main() {
  test('streak label renders Korean win/loss streaks', () {
    expect(_standing(streak: '3승').streakLabel, '3연승');
    expect(_standing(streak: '2패').streakLabel, '2연패');
    expect(_standing(streak: '1무').streakLabel, '1무');
  });

  test('streak label renders API win/loss codes', () {
    expect(_standing(streak: 'W4').streakLabel, '4연승');
    expect(_standing(streak: 'L1').streakLabel, '1연패');
    expect(_standing(streak: 'D2').streakLabel, '2무');
  });

  test('empty streak label falls back to dash', () {
    expect(_standing(streak: '').streakLabel, '-');
    expect(_standing(streak: '-').streakLabel, '-');
  });
}

TeamStanding _standing({required String streak}) {
  return TeamStanding(
    rank: 1,
    teamId: 'LG',
    teamName: 'LG 트윈스',
    wins: 1,
    losses: 0,
    draws: 0,
    pct: '1.000',
    gb: '0',
    streak: streak,
  );
}
