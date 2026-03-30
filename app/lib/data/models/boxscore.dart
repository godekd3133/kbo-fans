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
}

class LineupEntry {
  final int order;
  final String position;
  final String positionKo;
  final String name;

  const LineupEntry({
    required this.order,
    required this.position,
    required this.positionKo,
    required this.name,
  });
}
