import '../mock/mock_players.dart';
import '../models/player.dart';
import '../models/team_stats.dart';
import 'player_repository.dart';

class MockPlayerRepository implements PlayerRepository {
  @override
  Future<List<PlayerProfile>> getTeamPlayers(String teamId, {required int season}) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return mockPlayers.where((player) => player.teamId == teamId).toList();
  }

  @override
  Future<PlayerProfile> getPlayerDetail(String playerId, {required int season}) async {
    await Future.delayed(const Duration(milliseconds: 120));
    return mockPlayers.firstWhere((player) => player.id == playerId);
  }

  @override
  Future<TeamStats> getTeamStats(String teamId, {required int season}) async {
    await Future.delayed(const Duration(milliseconds: 120));
    return TeamStats(
      teamId: teamId,
      season: season,
      hitting: const {'AVG': '.281', 'HR': '18', 'OPS': '.781'},
      pitching: const {'ERA': '3.52', 'WHIP': '1.28', 'SV': '9'},
    );
  }
}
