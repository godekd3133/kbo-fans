import '../mock/mock_players.dart';
import '../models/player.dart';
import '../models/records_overview.dart';
import '../models/team_records_bundle.dart';
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

  @override
  Future<TeamRecordsBundle> getTeamRecords(String teamId, {required int season}) async {
    final results = await Future.wait([
      getTeamPlayers(teamId, season: season),
      getTeamStats(teamId, season: season),
    ]);
    return TeamRecordsBundle(
      players: results[0] as List<PlayerProfile>,
      teamStats: results[1] as TeamStats,
    );
  }

  @override
  Future<RecordsOverview> getRecordsOverview({required int season}) async {
    await Future.delayed(const Duration(milliseconds: 120));
    return const RecordsOverview(
      season: 2026,
      avgLeaders: [
        RecordLeader(rank: 1, playerId: 'LG-29-PARK', playerType: 'hitter', name: '박해민', teamId: 'LG', value: '.318'),
      ],
      hrLeaders: [
        RecordLeader(rank: 1, playerId: 'LG-10-OH', playerType: 'hitter', name: '오지환', teamId: 'LG', value: '12'),
      ],
      opsLeaders: [
        RecordLeader(rank: 1, playerId: 'LG-10-OH', playerType: 'hitter', name: '오지환', teamId: 'LG', value: '.882'),
      ],
      eraLeaders: [
        RecordLeader(rank: 1, playerId: 'LG-54-KELLY', playerType: 'pitcher', name: '켈리', teamId: 'LG', value: '2.45'),
      ],
      todayPlayer: FeaturedPlayerCard(label: '오늘의 플레이어', name: '박해민', teamId: 'LG', headline: '타율 .318', summary: '최근 3경기 연속 안타'),
      monthPlayer: FeaturedPlayerCard(label: '이달의 플레이어', name: '오지환', teamId: 'LG', headline: 'OPS .882', summary: '최근 7경기 OPS 1.001'),
    );
  }
}
