import 'player.dart';
import 'team_stats.dart';

class TeamRecordsBundle {
  final List<PlayerProfile> players;
  final TeamStats teamStats;

  const TeamRecordsBundle({
    required this.players,
    required this.teamStats,
  });
}
