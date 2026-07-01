class BatterRecord {
  final int order;
  final String position;
  final String name;
  final String? playerId;
  final String? imageUrl;
  final int atBats;
  final int runs;
  final int hits;
  final int rbi;
  final int? plateAppearances;
  final int? doubles;
  final int? triples;
  final int? homeRuns;
  final int? walks;
  final int? hitByPitch;
  final int? strikeouts;
  final int? stolenBases;
  final bool liveContext;
  final String? contextLabel;

  const BatterRecord({
    required this.order,
    required this.position,
    required this.name,
    this.playerId,
    this.imageUrl,
    required this.atBats,
    required this.runs,
    required this.hits,
    required this.rbi,
    this.plateAppearances,
    this.doubles,
    this.triples,
    this.homeRuns,
    this.walks,
    this.hitByPitch,
    this.strikeouts,
    this.stolenBases,
    this.liveContext = false,
    this.contextLabel,
  });

  bool get _hasExtraBaseDetail {
    return doubles != null || triples != null || homeRuns != null;
  }

  int? get extraBaseHits {
    if (!_hasExtraBaseDetail) {
      return null;
    }
    return (doubles ?? 0) + (triples ?? 0) + (homeRuns ?? 0);
  }

  int? get totalBases {
    if (!_hasExtraBaseDetail) {
      return null;
    }
    final doubleCount = doubles ?? 0;
    final tripleCount = triples ?? 0;
    final homeRunCount = homeRuns ?? 0;
    final singles = (hits - doubleCount - tripleCount - homeRunCount).clamp(
      0,
      hits,
    );
    return singles + (doubleCount * 2) + (tripleCount * 3) + (homeRunCount * 4);
  }

  double? get slugging {
    final bases = totalBases;
    if (bases == null || atBats <= 0) {
      return null;
    }
    return bases / atBats;
  }
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
  final bool liveContextAvailable;
  final TeamBoxscoreData away;
  final TeamBoxscoreData home;

  const GameBoxscoreData({
    required this.gameId,
    this.officialAvailable = true,
    this.liveContextAvailable = false,
    required this.away,
    required this.home,
  });
}

class PitcherRecord {
  final String name;
  final String? playerId;
  final String? imageUrl;
  final String innings;
  final int hits;
  final int strikeouts;
  final int walks;
  final int earnedRuns;
  final String? decision; // "W", "L", "S", "H", null
  final int? pitchCount;
  final int? runs;
  final bool liveContext;
  final String? contextLabel;

  const PitcherRecord({
    required this.name,
    this.playerId,
    this.imageUrl,
    required this.innings,
    required this.hits,
    required this.strikeouts,
    required this.walks,
    required this.earnedRuns,
    this.decision,
    this.pitchCount,
    this.runs,
    this.liveContext = false,
    this.contextLabel,
  });

  bool get hasDisplayableLine {
    final normalizedInnings = innings.trim();
    final normalizedDecision = decision?.trim().toUpperCase();
    return name.trim().isNotEmpty &&
        (liveContext ||
            normalizedInnings.isNotEmpty && normalizedInnings != '0.0' ||
            hits > 0 ||
            strikeouts > 0 ||
            walks > 0 ||
            earnedRuns > 0 ||
            (normalizedDecision != null &&
                normalizedDecision.isNotEmpty &&
                normalizedDecision != 'LIVE' &&
                normalizedDecision != '-'));
  }

  double? get inningsPitched {
    final value = innings.trim();
    if (value.isEmpty) {
      return null;
    }
    if (value.contains(' ')) {
      final parts = value.split(RegExp(r'\s+'));
      final whole = int.tryParse(parts.first) ?? 0;
      final fraction = parts.length > 1 ? parts[1] : '';
      if (fraction.contains('2/3')) {
        return whole + (2 / 3);
      }
      if (fraction.contains('1/3')) {
        return whole + (1 / 3);
      }
      return whole.toDouble();
    }
    if (value.contains('.')) {
      final parts = value.split('.');
      final whole = int.tryParse(parts.first) ?? 0;
      final outs = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      if (outs == 1 || outs == 2) {
        return whole + (outs / 3);
      }
      return whole.toDouble();
    }
    return double.tryParse(value);
  }

  double? get gameEra {
    final inningsValue = inningsPitched;
    if (inningsValue == null || inningsValue <= 0) {
      return null;
    }
    return earnedRuns * 9 / inningsValue;
  }

  double? get gameWhip {
    final inningsValue = inningsPitched;
    if (inningsValue == null || inningsValue <= 0) {
      return null;
    }
    return (hits + walks) / inningsValue;
  }
}

class LineupEntry {
  final int order;
  final String position;
  final String positionKo;
  final String name;
  final String? playerId;
  final String? imageUrl;
  final String? statValue;
  final String? changeLabel;

  const LineupEntry({
    required this.order,
    required this.position,
    required this.positionKo,
    required this.name,
    this.playerId,
    this.imageUrl,
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
