enum LeaderboardMetric { avg, hr, ops, era, war, opsPlus }

const kboPlayerImageBase =
    'https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/person/middle';
const kboPlayerImageMinSeason = 2022;

int kboPlayerImageSeason(int season) =>
    season < kboPlayerImageMinSeason ? kboPlayerImageMinSeason : season;

String kboPlayerImageUrl({required int season, required String playerId}) =>
    '$kboPlayerImageBase/${kboPlayerImageSeason(season)}/$playerId.jpg';

extension LeaderboardMetricX on LeaderboardMetric {
  String get key => switch (this) {
    LeaderboardMetric.avg => 'avg',
    LeaderboardMetric.hr => 'hr',
    LeaderboardMetric.ops => 'ops',
    LeaderboardMetric.era => 'era',
    LeaderboardMetric.war => 'war',
    LeaderboardMetric.opsPlus => 'opsPlus',
  };

  String get title => switch (this) {
    LeaderboardMetric.avg => '리그 타율 리더보드',
    LeaderboardMetric.hr => '리그 홈런왕 순위',
    LeaderboardMetric.ops => '리그 OPS 리더보드',
    LeaderboardMetric.era => '리그 ERA 리더보드',
    LeaderboardMetric.war => '리그 WAR 리더보드',
    LeaderboardMetric.opsPlus => '리그 wRC+ 리더보드',
  };

  String get shortLabel => switch (this) {
    LeaderboardMetric.avg => 'AVG',
    LeaderboardMetric.hr => 'HR',
    LeaderboardMetric.ops => 'OPS',
    LeaderboardMetric.era => 'ERA',
    LeaderboardMetric.war => 'WAR',
    LeaderboardMetric.opsPlus => 'wRC+',
  };

  bool get supportedByOfficialSource => switch (this) {
    LeaderboardMetric.avg => true,
    LeaderboardMetric.hr => true,
    LeaderboardMetric.ops => true,
    LeaderboardMetric.era => true,
    LeaderboardMetric.war => false,
    LeaderboardMetric.opsPlus => true,
  };

  static LeaderboardMetric? fromKey(String value) {
    for (final metric in LeaderboardMetric.values) {
      if (metric.key == value) {
        return metric;
      }
    }
    return null;
  }
}

class RecordLeader {
  final int rank;
  final String playerId;
  final String playerType;
  final String name;
  final String teamId;
  final String value;

  const RecordLeader({
    required this.rank,
    required this.playerId,
    required this.playerType,
    required this.name,
    required this.teamId,
    required this.value,
  });
}

class FeaturedPlayerCard {
  final String label;
  final String? playerId;
  final String? playerType;
  final String? name;
  final String? teamId;
  final String? headline;
  final String? summary;
  final String? imageUrl;

  const FeaturedPlayerCard({
    required this.label,
    this.playerId,
    this.playerType,
    this.name,
    this.teamId,
    this.headline,
    this.summary,
    this.imageUrl,
  });
}

class RecordsOverview {
  final int season;
  final List<RecordLeader> avgLeaders;
  final List<RecordLeader> hrLeaders;
  final List<RecordLeader> opsLeaders;
  final List<RecordLeader> opsPlusLeaders;
  final List<RecordLeader> eraLeaders;
  final FeaturedPlayerCard todayHitter;
  final FeaturedPlayerCard todayPitcher;
  final FeaturedPlayerCard monthHitter;
  final FeaturedPlayerCard monthPitcher;

  const RecordsOverview({
    required this.season,
    required this.avgLeaders,
    required this.hrLeaders,
    required this.opsLeaders,
    required this.opsPlusLeaders,
    required this.eraLeaders,
    required this.todayHitter,
    required this.todayPitcher,
    required this.monthHitter,
    required this.monthPitcher,
  });
}

List<RecordLeader> computeOpsPlusLeaders(List<RecordLeader> opsLeaders) {
  final parsed = opsLeaders
      .map((leader) => (leader: leader, ops: double.tryParse(leader.value)))
      .where((entry) => entry.ops != null)
      .toList();
  if (parsed.isEmpty) {
    return const [];
  }

  final leagueAverageOps =
      parsed.fold<double>(0, (sum, entry) => sum + entry.ops!) / parsed.length;
  if (leagueAverageOps <= 0) {
    return const [];
  }

  final calculated = parsed.map((entry) {
    final opsPlus = ((entry.ops! / leagueAverageOps) * 100).round();
    return RecordLeader(
      rank: 0,
      playerId: entry.leader.playerId,
      playerType: entry.leader.playerType,
      name: entry.leader.name,
      teamId: entry.leader.teamId,
      value: '$opsPlus',
    );
  }).toList()..sort((a, b) => int.parse(b.value).compareTo(int.parse(a.value)));

  return [
    for (var index = 0; index < calculated.length; index++)
      RecordLeader(
        rank: index + 1,
        playerId: calculated[index].playerId,
        playerType: calculated[index].playerType,
        name: calculated[index].name,
        teamId: calculated[index].teamId,
        value: calculated[index].value,
      ),
  ];
}
