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
  final FeaturedPlayerCard todayPlayer;
  final FeaturedPlayerCard monthPlayer;

  const RecordsOverview({
    required this.season,
    required this.avgLeaders,
    required this.hrLeaders,
    required this.opsLeaders,
    required this.eraLeaders,
    required this.todayPlayer,
    required this.monthPlayer,
  });
}
