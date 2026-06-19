import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/player.dart';
import '../models/records_overview.dart';
import '../models/team_records_bundle.dart';
import '../models/team_stats.dart';
import 'player_repository.dart';

class DeviceSnapshotPlayerRepository implements PlayerRepository {
  static const _prefix = 'player_snapshot:';
  static const _snapshotVersion = 'v3';
  static const _currentSeasonSnapshotMaxAge = Duration(hours: 6);
  static const _minSupportedOfficialPlayerRecordSeason = 2002;

  final PlayerRepository primary;
  final PlayerRepository fallback;
  final DateTime Function() _now;

  DeviceSnapshotPlayerRepository({
    required this.primary,
    required this.fallback,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  @override
  Future<List<PlayerProfile>> getTeamPlayers(
    String teamId, {
    required int season,
  }) async {
    if (!_isSupportedOfficialPlayerRecordSeason(season)) {
      return const <PlayerProfile>[];
    }

    final cacheKey = 'teamPlayers:$teamId:$season';
    final fresh = await _tryPrimary(
      cacheKey,
      () => primary.getTeamPlayers(teamId, season: season),
      _encodePlayers,
    );
    if (fresh != null) return fresh;

    final cached = await _readSnapshot(
      cacheKey,
      _decodePlayers,
      season: season,
    );
    if (cached != null && cached.isNotEmpty) return cached;

    return fallback.getTeamPlayers(teamId, season: season);
  }

  @override
  Future<PlayerProfile> getPlayerDetail(
    String playerId, {
    required int season,
  }) async {
    if (!_isSupportedOfficialPlayerRecordSeason(season)) {
      throw StateError('Player detail unavailable before 2002: $playerId');
    }

    final cacheKey = 'playerDetail:$playerId:$season';
    final fresh = await _tryPrimary(
      cacheKey,
      () => primary.getPlayerDetail(playerId, season: season),
      _encodePlayer,
    );
    if (fresh != null) return fresh;

    final cached = await _readSnapshot(cacheKey, _decodePlayer, season: season);
    if (cached != null && cached.id.isNotEmpty) return cached;

    return fallback.getPlayerDetail(playerId, season: season);
  }

  @override
  Future<TeamStats> getTeamStats(String teamId, {required int season}) async {
    if (!_isSupportedOfficialPlayerRecordSeason(season)) {
      return _emptyTeamStats(teamId, season);
    }

    final cacheKey = 'teamStats:$teamId:$season';
    final fresh = await _tryPrimary(
      cacheKey,
      () => primary.getTeamStats(teamId, season: season),
      _encodeTeamStats,
      isValid: _isCompleteTeamStats,
    );
    if (fresh != null) return fresh;

    final cached = await _readSnapshot(
      cacheKey,
      _decodeTeamStats,
      season: season,
    );
    if (cached != null && _isCompleteTeamStats(cached)) {
      return cached;
    }

    return fallback.getTeamStats(teamId, season: season);
  }

  @override
  Future<TeamRecordsBundle> getTeamRecords(
    String teamId, {
    required int season,
  }) async {
    if (!_isSupportedOfficialPlayerRecordSeason(season)) {
      return TeamRecordsBundle(
        players: const [],
        teamStats: _emptyTeamStats(teamId, season),
      );
    }

    final cacheKey = 'teamRecords:$teamId:$season';
    final fresh = await _tryPrimary(
      cacheKey,
      () => primary.getTeamRecords(teamId, season: season),
      _encodeTeamRecordsBundle,
      isValid: _isValidTeamRecordsBundle,
    );
    if (fresh != null) return fresh;

    final cached = await _readSnapshot(
      cacheKey,
      _decodeTeamRecordsBundle,
      season: season,
    );
    if (cached != null && _isValidTeamRecordsBundle(cached)) {
      return cached;
    }

    return fallback.getTeamRecords(teamId, season: season);
  }

  @override
  Future<RecordsOverview> getRecordsOverview({required int season}) async {
    if (!_isSupportedOfficialPlayerRecordSeason(season)) {
      return _emptyRecordsOverview(season);
    }

    final cacheKey = 'recordsOverview:$season';
    final fresh = await _tryPrimary(
      cacheKey,
      () => primary.getRecordsOverview(season: season),
      _encodeRecordsOverview,
      isValid: _isValidRecordsOverview,
    );
    if (fresh != null) return fresh;

    final cached = await _readSnapshot(
      cacheKey,
      _decodeRecordsOverview,
      season: season,
    );
    if (cached != null && _isValidRecordsOverview(cached)) {
      return cached;
    }

    return fallback.getRecordsOverview(season: season);
  }

  @override
  Future<List<RecordLeader>> getLeaderboard({
    required int season,
    required LeaderboardMetric metric,
  }) async {
    if (!_isSupportedOfficialPlayerRecordSeason(season)) {
      return const <RecordLeader>[];
    }

    final cacheKey = 'leaderboard:${metric.key}:$season';
    final fresh = await _tryPrimary(
      cacheKey,
      () => primary.getLeaderboard(season: season, metric: metric),
      _encodeLeaders,
      isValid: _isValidLeaders,
    );
    if (fresh != null) return fresh;

    final cached = await _readSnapshot(
      cacheKey,
      _decodeLeadersPayload,
      season: season,
    );
    if (cached != null && _isValidLeaders(cached)) return cached;

    return fallback.getLeaderboard(season: season, metric: metric);
  }

  bool _isSupportedOfficialPlayerRecordSeason(int season) =>
      season >= _minSupportedOfficialPlayerRecordSeason;

  TeamStats _emptyTeamStats(String teamId, int season) {
    return TeamStats(
      teamId: teamId,
      season: season,
      hitting: const {},
      pitching: const {},
    );
  }

  RecordsOverview _emptyRecordsOverview(int season) {
    return RecordsOverview(
      season: season,
      avgLeaders: const [],
      hrLeaders: const [],
      opsLeaders: const [],
      opsPlusLeaders: const [],
      eraLeaders: const [],
      todayHitter: const FeaturedPlayerCard(label: '오늘의 타자'),
      todayPitcher: const FeaturedPlayerCard(label: '오늘의 투수'),
      monthHitter: const FeaturedPlayerCard(label: '이달의 타자'),
      monthPitcher: const FeaturedPlayerCard(label: '이달의 투수'),
    );
  }

  Future<T?> _tryPrimary<T>(
    String cacheKey,
    Future<T> Function() action,
    Object Function(T value) encoder, {
    bool Function(T value)? isValid,
  }) async {
    try {
      final value = await action();
      if (isValid != null && !isValid(value)) {
        return null;
      }
      await _writeSnapshot(cacheKey, encoder(value));
      return value;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSnapshot(String cacheKey, Object payload) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefix$_snapshotVersion:$cacheKey',
      jsonEncode({
        'savedAt': _now().toUtc().toIso8601String(),
        'payload': payload,
      }),
    );
  }

  Future<T?> _readSnapshot<T>(
    String cacheKey,
    T Function(Map<String, dynamic> json) decoder, {
    required int season,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$_snapshotVersion:$cacheKey');
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final payload = _unwrapSnapshotPayload(decoded, season);
      if (payload == null) {
        return null;
      }
      return decoder(payload);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _unwrapSnapshotPayload(
    Map<String, dynamic> decoded,
    int season,
  ) {
    final payload = decoded['payload'];
    if (payload is Map<String, dynamic>) {
      final savedAt = _parseSavedAt(decoded['savedAt']);
      return _canUseSnapshot(savedAt, season) ? payload : null;
    }
    if (_requiresFreshSnapshot(season)) {
      return null;
    }
    return decoded;
  }

  bool _canUseSnapshot(DateTime? savedAt, int season) {
    if (!_requiresFreshSnapshot(season)) {
      return true;
    }
    if (savedAt == null) {
      return false;
    }
    return _now().toUtc().difference(savedAt.toUtc()) <=
        _currentSeasonSnapshotMaxAge;
  }

  bool _requiresFreshSnapshot(int season) => season >= _now().year;

  DateTime? _parseSavedAt(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value.replaceAll('Z', '+00:00'));
  }

  bool _isCompleteTeamStats(TeamStats value) =>
      value.hitting.isNotEmpty && value.pitching.isNotEmpty;

  bool _hasPartialTeamStats(TeamStats value) =>
      value.hitting.isNotEmpty != value.pitching.isNotEmpty;

  bool _isValidTeamRecordsBundle(TeamRecordsBundle value) {
    if (_hasPartialTeamStats(value.teamStats)) {
      return false;
    }
    return value.players.isNotEmpty || _isCompleteTeamStats(value.teamStats);
  }

  bool _isValidRecordsOverview(RecordsOverview value) =>
      _isValidLeaders(value.avgLeaders) &&
      _isValidLeaders(value.hrLeaders) &&
      _isValidLeaders(value.opsLeaders) &&
      _isValidLeaders(value.eraLeaders);

  bool _isValidLeaders(List<RecordLeader> leaders) =>
      leaders.isNotEmpty && leaders.first.rank == 1;

  Object _encodePlayers(List<PlayerProfile> players) => {
    'players': players.map(_encodePlayer).toList(),
  };

  List<PlayerProfile> _decodePlayers(Map<String, dynamic> json) =>
      (json['players'] as List<dynamic>? ?? const [])
          .map((item) => _decodePlayer(item as Map<String, dynamic>))
          .toList();

  Object _encodeLeaders(List<RecordLeader> leaders) => {
    'leaders': leaders
        .map(
          (leader) => {
            'rank': leader.rank,
            'playerId': leader.playerId,
            'playerType': leader.playerType,
            'name': leader.name,
            'teamId': leader.teamId,
            'value': leader.value,
            'isRetired': leader.isRetired,
          },
        )
        .toList(),
  };

  List<RecordLeader> _decodeLeadersPayload(Map<String, dynamic> json) =>
      (json['leaders'] as List<dynamic>? ?? const []).map((item) {
        final map = item as Map<String, dynamic>;
        return RecordLeader(
          rank: map['rank'] as int? ?? 0,
          playerId: map['playerId'] as String? ?? '',
          playerType: map['playerType'] as String? ?? '',
          name: map['name'] as String? ?? '',
          teamId: map['teamId'] as String? ?? '',
          value: map['value'] as String? ?? '',
          isRetired: map['isRetired'] as bool? ?? false,
        );
      }).toList();

  Object _encodePlayer(PlayerProfile player) => {
    'id': player.id,
    'teamId': player.teamId,
    'playerType': player.playerType.name,
    'imageUrl': player.imageUrl,
    'name': player.name,
    'number': player.number,
    'position': player.position,
    'roleLabel': player.roleLabel,
    'handedness': player.handedness,
    'heightWeight': player.heightWeight,
    'birthDate': player.birthDate,
    'career': player.career,
    'status': player.status.name,
    'rosterGroup': player.rosterGroup.name,
    'statusNote': player.statusNote,
    'headlineStat': player.headlineStat,
    'secondaryStat': player.secondaryStat,
    'seasonStats': player.seasonStats,
    'highlights': player.highlights,
    'recentGames': player.recentGames
        .map(
          (game) => {
            'date': game.date,
            'opponent': game.opponent,
            'summary': game.summary,
            'score': game.score,
          },
        )
        .toList(),
    'avg': player.avg,
    'ops': player.ops,
    'era': player.era,
    'whip': player.whip,
    'isRetired': player.isRetired,
  };

  PlayerProfile _decodePlayer(Map<String, dynamic> json) {
    return PlayerProfile(
      id: json['id'] as String? ?? '',
      teamId: json['teamId'] as String? ?? '',
      playerType: (json['playerType'] as String? ?? '') == 'pitcher'
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
      career: json['career'] as String? ?? '',
      status: _decodeStatus(json['status'] as String?),
      rosterGroup: (json['rosterGroup'] as String? ?? '') == 'reserve'
          ? PlayerRosterGroup.reserve
          : PlayerRosterGroup.entry,
      statusNote: json['statusNote'] as String?,
      headlineStat: json['headlineStat'] as String? ?? '',
      secondaryStat: json['secondaryStat'] as String? ?? '',
      seasonStats: (json['seasonStats'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      highlights: (json['highlights'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      recentGames: (json['recentGames'] as List<dynamic>? ?? const []).map((
        item,
      ) {
        final map = item as Map<String, dynamic>;
        return PlayerRecentGame(
          date: map['date'] as String? ?? '',
          opponent: map['opponent'] as String? ?? '',
          summary: map['summary'] as String? ?? '',
          score: (map['score'] as num?)?.toDouble(),
        );
      }).toList(),
      avg: (json['avg'] as num?)?.toDouble(),
      ops: (json['ops'] as num?)?.toDouble(),
      era: (json['era'] as num?)?.toDouble(),
      whip: (json['whip'] as num?)?.toDouble(),
      isRetired: json['isRetired'] as bool? ?? false,
    );
  }

  Object _encodeTeamStats(TeamStats stats) => {
    'teamId': stats.teamId,
    'season': stats.season,
    'hitting': stats.hitting,
    'pitching': stats.pitching,
  };

  TeamStats _decodeTeamStats(Map<String, dynamic> json) => TeamStats(
    teamId: json['teamId'] as String? ?? '',
    season: json['season'] as int? ?? 0,
    hitting: (json['hitting'] as Map<String, dynamic>? ?? const {}).map(
      (key, value) => MapEntry(key, value.toString()),
    ),
    pitching: (json['pitching'] as Map<String, dynamic>? ?? const {}).map(
      (key, value) => MapEntry(key, value.toString()),
    ),
  );

  Object _encodeTeamRecordsBundle(TeamRecordsBundle bundle) => {
    'players': bundle.players.map(_encodePlayer).toList(),
    'teamStats': _encodeTeamStats(bundle.teamStats),
  };

  TeamRecordsBundle _decodeTeamRecordsBundle(Map<String, dynamic> json) =>
      TeamRecordsBundle(
        players: (json['players'] as List<dynamic>? ?? const [])
            .map((item) => _decodePlayer(item as Map<String, dynamic>))
            .toList(),
        teamStats: _decodeTeamStats(
          json['teamStats'] as Map<String, dynamic>? ?? const {},
        ),
      );

  Object _encodeRecordsOverview(RecordsOverview overview) => {
    'season': overview.season,
    'avgLeaders': overview.avgLeaders.map(_encodeLeader).toList(),
    'hrLeaders': overview.hrLeaders.map(_encodeLeader).toList(),
    'opsLeaders': overview.opsLeaders.map(_encodeLeader).toList(),
    'opsPlusLeaders': overview.opsPlusLeaders.map(_encodeLeader).toList(),
    'eraLeaders': overview.eraLeaders.map(_encodeLeader).toList(),
    'todayHitter': _encodeFeatured(overview.todayHitter),
    'todayPitcher': _encodeFeatured(overview.todayPitcher),
    'monthHitter': _encodeFeatured(overview.monthHitter),
    'monthPitcher': _encodeFeatured(overview.monthPitcher),
  };

  RecordsOverview _decodeRecordsOverview(Map<String, dynamic> json) =>
      RecordsOverview(
        season: json['season'] as int? ?? 0,
        avgLeaders: _decodeLeaders(json['avgLeaders'] as List<dynamic>?),
        hrLeaders: _decodeLeaders(json['hrLeaders'] as List<dynamic>?),
        opsLeaders: _decodeLeaders(json['opsLeaders'] as List<dynamic>?),
        opsPlusLeaders: _decodeLeaders(
          json['opsPlusLeaders'] as List<dynamic>?,
        ),
        eraLeaders: _decodeLeaders(json['eraLeaders'] as List<dynamic>?),
        todayHitter: _decodeFeatured(
          json['todayHitter'] as Map<String, dynamic>? ?? const {},
        ),
        todayPitcher: _decodeFeatured(
          json['todayPitcher'] as Map<String, dynamic>? ?? const {},
        ),
        monthHitter: _decodeFeatured(
          json['monthHitter'] as Map<String, dynamic>? ?? const {},
        ),
        monthPitcher: _decodeFeatured(
          json['monthPitcher'] as Map<String, dynamic>? ?? const {},
        ),
      );

  Object _encodeLeader(RecordLeader leader) => {
    'rank': leader.rank,
    'playerId': leader.playerId,
    'playerType': leader.playerType,
    'name': leader.name,
    'teamId': leader.teamId,
    'value': leader.value,
    'isRetired': leader.isRetired,
  };

  List<RecordLeader> _decodeLeaders(List<dynamic>? list) =>
      (list ?? const []).map((item) {
        final map = item as Map<String, dynamic>;
        return RecordLeader(
          rank: map['rank'] as int? ?? 0,
          playerId: map['playerId'] as String? ?? '',
          playerType: map['playerType'] as String? ?? '',
          name: map['name'] as String? ?? '',
          teamId: map['teamId'] as String? ?? '',
          value: map['value'] as String? ?? '',
          isRetired: map['isRetired'] as bool? ?? false,
        );
      }).toList();

  Object _encodeFeatured(FeaturedPlayerCard card) => {
    'label': card.label,
    'playerId': card.playerId,
    'playerType': card.playerType,
    'name': card.name,
    'teamId': card.teamId,
    'headline': card.headline,
    'summary': card.summary,
    'imageUrl': card.imageUrl,
  };

  FeaturedPlayerCard _decodeFeatured(Map<String, dynamic> json) =>
      FeaturedPlayerCard(
        label: json['label'] as String? ?? '',
        playerId: json['playerId'] as String?,
        playerType: json['playerType'] as String?,
        name: json['name'] as String?,
        teamId: json['teamId'] as String?,
        headline: json['headline'] as String?,
        summary: json['summary'] as String?,
        imageUrl: json['imageUrl'] as String?,
      );

  PlayerAvailabilityStatus _decodeStatus(String? raw) {
    switch (raw) {
      case 'injured':
        return PlayerAvailabilityStatus.injured;
      case 'inactive':
        return PlayerAvailabilityStatus.inactive;
      default:
        return PlayerAvailabilityStatus.available;
    }
  }
}
