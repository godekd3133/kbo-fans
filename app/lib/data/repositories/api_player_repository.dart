import '../api/api_client.dart';
import '../models/player.dart';
import '../models/team_stats.dart';
import 'player_repository.dart';

class ApiPlayerRepository implements PlayerRepository {
  final ApiClient _client;

  ApiPlayerRepository(this._client);

  @override
  Future<List<PlayerProfile>> getTeamPlayers(String teamId, {required int season}) async {
    final data = await _client.get('/team/$teamId/players', queryParameters: {'season': season});
    final players = data['players'] as List<dynamic>? ?? [];
    return players.map((item) => _parsePlayer(item as Map<String, dynamic>)).toList();
  }

  @override
  Future<PlayerProfile> getPlayerDetail(String playerId, {required int season}) async {
    final data = await _client.get('/player/$playerId', queryParameters: {'season': season});
    return _parsePlayer(data);
  }

  @override
  Future<TeamStats> getTeamStats(String teamId, {required int season}) async {
    final data = await _client.get('/team/$teamId/stats', queryParameters: {'season': season});
    return TeamStats(
      teamId: data['teamId'] as String? ?? teamId,
      season: data['season'] as int? ?? season,
      hitting: (data['hitting'] as Map<String, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(key, value.toString()),
      ),
      pitching: (data['pitching'] as Map<String, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }

  PlayerProfile _parsePlayer(Map<String, dynamic> json) {
    final seasonStats = (json['seasonStats'] as List<dynamic>? ?? []).map((item) => item.toString()).toList();
    final highlights = (json['highlights'] as List<dynamic>? ?? []).map((item) => item.toString()).toList();
    final recentGames = (json['recentGames'] as List<dynamic>? ?? []).map((item) {
      final map = item as Map<String, dynamic>;
      return PlayerRecentGame(
        date: map['date'] as String? ?? '',
        opponent: map['opponent'] as String? ?? '',
        summary: map['summary'] as String? ?? '',
      );
    }).toList();
    final sortMetrics = json['sortMetrics'] as Map<String, dynamic>? ?? const {};

    return PlayerProfile(
      id: json['id'] as String? ?? '',
      teamId: json['teamId'] as String? ?? '',
      playerType: (json['playerType'] as String? ?? '').toLowerCase() == 'pitcher'
          ? PlayerType.pitcher
          : PlayerType.hitter,
      imageUrl: json['imageUrl'] as String?,
      name: json['name'] as String? ?? '',
      number: json['number'] as int? ?? 0,
      position: json['position'] as String? ?? '',
      roleLabel: json['roleLabel'] as String? ?? '',
      handedness: json['handedness'] as String? ?? '',
      heightWeight: json['heightWeight'] as String? ?? '',
      birthDate: json['birthDate'] as String? ?? '',
      status: _parseStatus(json['status'] as String? ?? ''),
      rosterGroup: (json['rosterGroup'] as String? ?? '') == 'reserve'
          ? PlayerRosterGroup.reserve
          : PlayerRosterGroup.entry,
      statusNote: json['statusNote'] as String?,
      headlineStat: json['headlineStat'] as String? ?? '',
      secondaryStat: json['secondaryStat'] as String? ?? '',
      seasonStats: seasonStats,
      highlights: highlights,
      recentGames: recentGames,
      avg: (sortMetrics['avg'] as num?)?.toDouble(),
      ops: (sortMetrics['ops'] as num?)?.toDouble(),
      era: (sortMetrics['era'] as num?)?.toDouble(),
      whip: (sortMetrics['whip'] as num?)?.toDouble(),
    );
  }

  PlayerAvailabilityStatus _parseStatus(String status) {
    switch (status) {
      case 'injured':
        return PlayerAvailabilityStatus.injured;
      case 'inactive':
        return PlayerAvailabilityStatus.inactive;
      default:
        return PlayerAvailabilityStatus.available;
    }
  }
}
