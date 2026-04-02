enum PlayerType { hitter, pitcher }

enum PlayerAvailabilityStatus { available, injured, inactive }

enum PlayerRosterGroup { entry, reserve }

class PlayerRecentGame {
  final String date;
  final String opponent;
  final String summary;
  final double? score;

  const PlayerRecentGame({
    required this.date,
    required this.opponent,
    required this.summary,
    this.score,
  });
}

class PlayerProfile {
  final String id;
  final String teamId;
  final PlayerType playerType;
  final String? imageUrl;
  final String name;
  final int number;
  final String position;
  final String roleLabel;
  final String handedness;
  final String heightWeight;
  final String birthDate;
  final String career;
  final PlayerAvailabilityStatus status;
  final PlayerRosterGroup rosterGroup;
  final String? statusNote;
  final String headlineStat;
  final String secondaryStat;
  final List<String> seasonStats;
  final List<String> highlights;
  final List<PlayerRecentGame> recentGames;
  final double? avg;
  final double? ops;
  final double? era;
  final double? whip;

  const PlayerProfile({
    required this.id,
    required this.teamId,
    this.playerType = PlayerType.hitter,
    this.imageUrl,
    required this.name,
    required this.number,
    required this.position,
    required this.roleLabel,
    required this.handedness,
    required this.heightWeight,
    required this.birthDate,
    this.career = '',
    required this.status,
    required this.rosterGroup,
    this.statusNote,
    required this.headlineStat,
    required this.secondaryStat,
    required this.seasonStats,
    required this.highlights,
    required this.recentGames,
    this.avg,
    this.ops,
    this.era,
    this.whip,
  });
}
