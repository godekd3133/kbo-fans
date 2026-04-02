enum LeaderboardMetric { avg, hr, ops, era, war, wrcPlus }

extension LeaderboardMetricX on LeaderboardMetric {
  String get key => switch (this) {
    LeaderboardMetric.avg => 'avg',
    LeaderboardMetric.hr => 'hr',
    LeaderboardMetric.ops => 'ops',
    LeaderboardMetric.era => 'era',
    LeaderboardMetric.war => 'war',
    LeaderboardMetric.wrcPlus => 'wrcPlus',
  };

  String get title => switch (this) {
    LeaderboardMetric.avg => '리그 타율 리더보드',
    LeaderboardMetric.hr => '리그 홈런 리더보드',
    LeaderboardMetric.ops => '리그 OPS 리더보드',
    LeaderboardMetric.era => '리그 ERA 리더보드',
    LeaderboardMetric.war => '리그 WAR 리더보드',
    LeaderboardMetric.wrcPlus => '리그 wRC+ 리더보드',
  };

  String get shortLabel => switch (this) {
    LeaderboardMetric.avg => 'AVG',
    LeaderboardMetric.hr => 'HR',
    LeaderboardMetric.ops => 'OPS',
    LeaderboardMetric.era => 'ERA',
    LeaderboardMetric.war => 'WAR',
    LeaderboardMetric.wrcPlus => 'wRC+',
  };

  bool get supportedByOfficialSource => switch (this) {
    LeaderboardMetric.avg => true,
    LeaderboardMetric.hr => true,
    LeaderboardMetric.ops => true,
    LeaderboardMetric.era => true,
    LeaderboardMetric.war => false,
    LeaderboardMetric.wrcPlus => false,
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
    required this.eraLeaders,
    required this.todayHitter,
    required this.todayPitcher,
    required this.monthHitter,
    required this.monthPitcher,
  });
}
