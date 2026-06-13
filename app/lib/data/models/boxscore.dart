class BatterRecord {
  final int order;
  final String position;
  final String name;
  final int atBats;
  final int runs;
  final int hits;
  final int rbi;

  const BatterRecord({
    required this.order,
    required this.position,
    required this.name,
    required this.atBats,
    required this.runs,
    required this.hits,
    required this.rbi,
  });
}

class TeamBoxscoreData {
  final String teamId;
  final List<BatterRecord> batters;
  final List<PitcherRecord> pitchers;

  const TeamBoxscoreData({
    required this.teamId,
    required this.batters,
    required this.pitchers,
  });

  bool get hasDisplayableRecords {
    return batters.any((batter) => batter.name.trim().isNotEmpty) ||
        pitchers.any((pitcher) => pitcher.hasDisplayableLine);
  }
}

class GameBoxscoreData {
  final String gameId;
  final bool officialAvailable;
  final TeamBoxscoreData away;
  final TeamBoxscoreData home;

  const GameBoxscoreData({
    required this.gameId,
    this.officialAvailable = true,
    required this.away,
    required this.home,
  });
}

class PitcherRecord {
  final String name;
  final String innings;
  final int hits;
  final int strikeouts;
  final int walks;
  final int earnedRuns;
  final String? decision; // "W", "L", "S", "H", null

  const PitcherRecord({
    required this.name,
    required this.innings,
    required this.hits,
    required this.strikeouts,
    required this.walks,
    required this.earnedRuns,
    this.decision,
  });

  bool get hasDisplayableLine {
    final normalizedInnings = innings.trim();
    final normalizedDecision = decision?.trim().toUpperCase();
    return name.trim().isNotEmpty &&
        (normalizedInnings.isNotEmpty && normalizedInnings != '0.0' ||
            hits > 0 ||
            strikeouts > 0 ||
            walks > 0 ||
            earnedRuns > 0 ||
            (normalizedDecision != null &&
                normalizedDecision.isNotEmpty &&
                normalizedDecision != 'LIVE' &&
                normalizedDecision != '-'));
  }
}

class LineupEntry {
  final int order;
  final String position;
  final String positionKo;
  final String name;
  final String? statValue;
  final String? changeLabel;

  const LineupEntry({
    required this.order,
    required this.position,
    required this.positionKo,
    required this.name,
    this.statValue,
    this.changeLabel,
  });
}

class TeamLineupData {
  final String teamId;
  final List<LineupEntry> lineup;
  final String? starterId;
  final String? starterName;
  final String? starterImageUrl;

  const TeamLineupData({
    required this.teamId,
    required this.lineup,
    this.starterId,
    this.starterName,
    this.starterImageUrl,
  });
}

class GameLineupData {
  final String gameId;
  final TeamLineupData away;
  final TeamLineupData home;

  const GameLineupData({
    required this.gameId,
    required this.away,
    required this.home,
  });
}
