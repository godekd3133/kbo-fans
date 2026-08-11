const Duration kboUtcOffset = Duration(hours: 9);

/// KBO가 사용하는 Asia/Seoul 벽시계의 필드를 담은 UTC DateTime을 반환한다.
///
/// 반환값은 날짜/시/분 필드를 읽는 civil-time carrier다. 실제 instant 비교에는
/// [kboInstantFromCivil]을 사용한다.
DateTime kboCivilDateTime([DateTime? instant]) {
  return (instant ?? DateTime.now()).toUtc().add(kboUtcOffset);
}

String kboDateKey([DateTime? instant]) {
  final kbo = kboCivilDateTime(instant);
  return '${_fourDigits(kbo.year)}-${_twoDigits(kbo.month)}-${_twoDigits(kbo.day)}';
}

String kboDisplayDateKey([DateTime? instant]) {
  final kbo = kboCivilDateTime(instant);
  return '${_fourDigits(kbo.year)}.${_twoDigits(kbo.month)}.${_twoDigits(kbo.day)}';
}

String kboYearMonthKey([DateTime? instant]) {
  final kbo = kboCivilDateTime(instant);
  return '${_fourDigits(kbo.year)}-${_twoDigits(kbo.month)}';
}

Duration durationUntilNextKboDate([DateTime? instant]) {
  final now = (instant ?? DateTime.now()).toUtc();
  final kbo = kboCivilDateTime(now);
  final nextCivilDate = DateTime.utc(
    kbo.year,
    kbo.month,
    kbo.day,
  ).add(const Duration(days: 1));
  final nextKboMidnight = nextCivilDate.subtract(kboUtcOffset);
  final remaining = nextKboMidnight.difference(now);
  return remaining.isNegative ? Duration.zero : remaining;
}

int kboCurrentSeason([DateTime? instant]) => kboCivilDateTime(instant).year;

int? kboSeasonFromDateKey(String value) => _parseCivilDate(value)?.year;

bool isHistoricalKboDate(String date, {DateTime? now}) {
  final target = _parseCivilDate(date);
  if (target == null) {
    return false;
  }
  final kbo = kboCivilDateTime(now);
  final today = DateTime.utc(kbo.year, kbo.month, kbo.day);
  return target.isBefore(today);
}

bool isHistoricalKboMonth(String yearMonth, {DateTime? now}) {
  final target = _parseCivilMonth(yearMonth);
  if (target == null) {
    return false;
  }
  final kbo = kboCivilDateTime(now);
  final current = DateTime.utc(kbo.year, kbo.month);
  return target.isBefore(current);
}

bool isYesterdayKboDate(String date, {DateTime? now}) {
  final target = _parseCivilDate(date);
  if (target == null) {
    return false;
  }
  final kbo = kboCivilDateTime(now);
  final yesterday = DateTime.utc(
    kbo.year,
    kbo.month,
    kbo.day,
  ).subtract(const Duration(days: 1));
  return target == yesterday;
}

DateTime? kboInstantFromCivil({
  required int year,
  required int month,
  required int day,
  int hour = 0,
  int minute = 0,
  int second = 0,
}) {
  final civil = DateTime.utc(year, month, day, hour, minute, second);
  if (civil.year != year ||
      civil.month != month ||
      civil.day != day ||
      civil.hour != hour ||
      civil.minute != minute ||
      civil.second != second) {
    return null;
  }
  return civil.subtract(kboUtcOffset);
}

DateTime? parseKboDateTime(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) {
    return null;
  }
  if (RegExp(r'(?:[zZ]|[+-]\d{2}:?\d{2})$').hasMatch(raw)) {
    return DateTime.tryParse(raw)?.toUtc();
  }

  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?$',
  ).firstMatch(raw);
  if (match == null) {
    return null;
  }
  final instant = kboInstantFromCivil(
    year: int.parse(match.group(1)!),
    month: int.parse(match.group(2)!),
    day: int.parse(match.group(3)!),
    hour: int.parse(match.group(4)!),
    minute: int.parse(match.group(5)!),
    second: int.parse(match.group(6) ?? '0'),
  );
  if (instant == null) {
    return null;
  }
  final fraction = match.group(7) ?? '';
  if (fraction.isEmpty) {
    return instant;
  }
  final microseconds = int.parse('${fraction}000000'.substring(0, 6));
  return instant.add(Duration(microseconds: microseconds));
}

DateTime? _parseCivilDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    return null;
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

DateTime? _parseCivilMonth(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(value);
  if (match == null) {
    return null;
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final parsed = DateTime.utc(year, month);
  if (parsed.year != year || parsed.month != month) {
    return null;
  }
  return parsed;
}

String _fourDigits(int value) => value.toString().padLeft(4, '0');

String _twoDigits(int value) => value.toString().padLeft(2, '0');
