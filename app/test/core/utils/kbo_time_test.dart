import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/utils/kbo_time.dart';

void main() {
  test('KBO date advances at midnight in Seoul regardless of device zone', () {
    final instant = DateTime.utc(2026, 7, 12, 15);

    expect(kboDateKey(instant), '2026-07-13');
    expect(kboDisplayDateKey(instant), '2026.07.13');
  });

  test('KBO current month and season use Seoul civil time', () {
    final instant = DateTime.utc(2026, 12, 31, 15, 30);

    expect(kboYearMonthKey(instant), '2027-01');
    expect(kboCurrentSeason(instant), 2027);
  });

  test('historical date classification uses the KBO civil date', () {
    final instant = DateTime.utc(2026, 7, 12, 19);

    expect(isHistoricalKboDate('2026-07-12', now: instant), isTrue);
    expect(isHistoricalKboDate('2026-07-13', now: instant), isFalse);
    expect(isHistoricalKboDate('2026-07-14', now: instant), isFalse);
    expect(isYesterdayKboDate('2026-07-12', now: instant), isTrue);
    expect(isYesterdayKboDate('2026-07-11', now: instant), isFalse);
  });

  test('historical month classification uses the KBO civil month', () {
    final instant = DateTime.utc(2026, 12, 31, 15, 30);

    expect(isHistoricalKboMonth('2026-12', now: instant), isTrue);
    expect(isHistoricalKboMonth('2027-01', now: instant), isFalse);
  });

  test('KBO civil game time converts to a zone-independent UTC instant', () {
    expect(
      kboInstantFromCivil(year: 2026, month: 5, day: 20, hour: 18, minute: 30),
      DateTime.utc(2026, 5, 20, 9, 30),
    );
  });

  test('naive backend timestamps are interpreted as KST', () {
    expect(
      parseKboDateTime('2026-06-17T11:00:00'),
      DateTime.utc(2026, 6, 17, 2),
    );
    expect(
      parseKboDateTime('2026-06-17T11:00:00+09:00'),
      DateTime.utc(2026, 6, 17, 2),
    );
  });

  test('malformed civil dates and months are never treated as historical', () {
    final instant = DateTime.utc(2026, 7, 12, 19);

    expect(isHistoricalKboDate('2026-02-31', now: instant), isFalse);
    expect(isHistoricalKboDate('not-a-date', now: instant), isFalse);
    expect(isHistoricalKboMonth('2026-13', now: instant), isFalse);
  });
}
