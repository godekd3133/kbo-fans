import '../models/player.dart';
import '../models/records_overview.dart';
import '../models/team_records_bundle.dart';
import '../models/team_stats.dart';

abstract class PlayerRepository {
  Future<List<PlayerProfile>> getTeamPlayers(String teamId, {required int season});
  Future<PlayerProfile> getPlayerDetail(String playerId, {required int season});
  Future<TeamStats> getTeamStats(String teamId, {required int season});
  Future<TeamRecordsBundle> getTeamRecords(String teamId, {required int season});
  Future<RecordsOverview> getRecordsOverview({required int season});
}
