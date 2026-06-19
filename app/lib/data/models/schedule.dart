import 'ticketing.dart';

class ScheduleGame {
  final String gameId;
  final String time;
  final String awayId;
  final String awayName;
  final int? awayScore;
  final String homeId;
  final String homeName;
  final int? homeScore;
  final String stadium;
  final String status;
  final String? statusLabel;
  final TicketInfo? ticketInfo;

  const ScheduleGame({
    required this.gameId,
    required this.time,
    required this.awayId,
    required this.awayName,
    this.awayScore,
    required this.homeId,
    required this.homeName,
    this.homeScore,
    required this.stadium,
    this.status = 'SCHEDULED',
    this.statusLabel,
    this.ticketInfo,
  });
}

class ScheduleDay {
  final String date;
  final String? label;
  final List<ScheduleGame> games;

  const ScheduleDay({required this.date, this.label, required this.games});
}

class TeamStanding {
  final int rank;
  final String teamId;
  final String teamName;
  final int wins;
  final int losses;
  final int draws;
  final String pct;
  final String gb;
  final String streak;

  const TeamStanding({
    required this.rank,
    required this.teamId,
    required this.teamName,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.pct,
    required this.gb,
    this.streak = '',
  });

  String get streakLabel {
    final value = streak.trim();
    if (value.isEmpty || value == '-') {
      return '-';
    }

    final koreanMatch = RegExp(r'^(\d+)(승|패|무)$').firstMatch(value);
    if (koreanMatch != null) {
      final count = koreanMatch.group(1)!;
      final result = koreanMatch.group(2)!;
      if (result == '승') return '$count연승';
      if (result == '패') return '$count연패';
      return '$count무';
    }

    final normalized = value.toUpperCase();
    final codeMatch = RegExp(r'^(W|L|D)(\d+)$').firstMatch(normalized);
    if (codeMatch != null) {
      final code = codeMatch.group(1)!;
      final count = codeMatch.group(2)!;
      if (code == 'W') return '$count연승';
      if (code == 'L') return '$count연패';
      return '$count무';
    }

    return value;
  }
}
