import '../api/api_client.dart';
import '../models/player.dart';
import '../models/records_overview.dart';
import '../models/team_records_bundle.dart';
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
    return _parseTeamStats(data, fallbackTeamId: teamId, fallbackSeason: season);
  }

  @override
  Future<TeamRecordsBundle> getTeamRecords(String teamId, {required int season}) async {
    final data = await _client.get('/team/$teamId/records', queryParameters: {'season': season});
    final players = data['players'] as List<dynamic>? ?? [];
    return TeamRecordsBundle(
      players: players.map((item) => _parsePlayer(item as Map<String, dynamic>)).toList(),
      teamStats: _parseTeamStats(
        data['teamStats'] as Map<String, dynamic>? ?? const {},
        fallbackTeamId: teamId,
        fallbackSeason: season,
      ),
    );
  }

  TeamStats _parseTeamStats(
    Map<String, dynamic> data, {
    required String fallbackTeamId,
    required int fallbackSeason,
  }) {
    return TeamStats(
      teamId: data['teamId'] as String? ?? fallbackTeamId,
      season: data['season'] as int? ?? fallbackSeason,
      hitting: (data['hitting'] as Map<String, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(key, value.toString()),
      ),
      pitching: (data['pitching'] as Map<String, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }

  @override
  Future<RecordsOverview> getRecordsOverview({required int season}) async {
    final data = await _client.get('/records/overview', queryParameters: {'season': season});
    final leaders = data['leaders'] as Map<String, dynamic>? ?? const {};
    final featured = data['featured'] as Map<String, dynamic>? ?? const {};
    return RecordsOverview(
      season: data['season'] as int? ?? season,
      avgLeaders: _parseLeaders(leaders['avg'] as List<dynamic>? ?? const []),
      opsLeaders: _parseLeaders(leaders['ops'] as List<dynamic>? ?? const []),
      eraLeaders: _parseLeaders(leaders['era'] as List<dynamic>? ?? const []),
      todayPlayer: _parseFeatured(featured['todayPlayer'] as Map<String, dynamic>? ?? const {'label': '오늘의 플레이어'}),
      monthPlayer: _parseFeatured(featured['monthPlayer'] as Map<String, dynamic>? ?? const {'label': '이달의 플레이어'}),
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

  List<RecordLeader> _parseLeaders(List<dynamic> list) {
    return list.map((item) {
      final map = item as Map<String, dynamic>;
      return RecordLeader(
        rank: map['rank'] as int? ?? 0,
        playerId: map['playerId'] as String? ?? '',
        playerType: map['playerType'] as String? ?? '',
        name: map['name'] as String? ?? '',
        teamId: map['teamId'] as String? ?? '',
        value: map['value'] as String? ?? '',
      );
    }).toList();
  }

  FeaturedPlayerCard _parseFeatured(Map<String, dynamic> map) {
    return FeaturedPlayerCard(
      label: map['label'] as String? ?? '',
      playerId: map['playerId'] as String?,
      playerType: map['playerType'] as String?,
      name: map['name'] as String?,
      teamId: map['teamId'] as String?,
      headline: map['headline'] as String?,
      summary: map['summary'] as String?,
      imageUrl: map['imageUrl'] as String?,
    );
  }
}
