class ScheduleGame {
  final String gameId;
  final String time;
  final String awayId;
  final String awayName;
  final String homeId;
  final String homeName;
  final String stadium;
  final String status;

  const ScheduleGame({
    required this.gameId,
    required this.time,
    required this.awayId,
    required this.awayName,
    required this.homeId,
    required this.homeName,
    required this.stadium,
    this.status = 'SCHEDULED',
  });
}

class ScheduleDay {
  final String date;
  final String? label;
  final List<ScheduleGame> games;

  const ScheduleDay({
    required this.date,
    this.label,
    required this.games,
  });
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

  const TeamStanding({
    required this.rank,
    required this.teamId,
    required this.teamName,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.pct,
    required this.gb,
  });
}
