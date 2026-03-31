import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../bootstrap/bootstrap_repository.dart';
import '../models/player.dart';
import '../models/records_overview.dart';
import '../models/team_records_bundle.dart';
import '../models/team_stats.dart';
import 'mock_player_repository.dart';
import 'player_repository.dart';

class LocalAssetPlayerRepository implements PlayerRepository {
  static const _teamPlayersDir = 'assets/bootstrap/team_players';
  static const _teamStatsDir = 'assets/bootstrap/team_stats';

  final BootstrapRepository _bootstrapRepository = BootstrapRepository();
  final MockPlayerRepository _fallback = MockPlayerRepository();

  @override
  Future<List<PlayerProfile>> getTeamPlayers(String teamId, {required int season}) async {
    final payload = await _loadSnapshot('$_teamPlayersDir/$teamId-$season.json');
    final players = payload?['players'] as List<dynamic>?;
    if (players == null || players.isEmpty) {
      return _fallback.getTeamPlayers(teamId, season: season);
    }
    return players
        .map((item) => _parsePlayer(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<PlayerProfile> getPlayerDetail(String playerId, {required int season}) async {
    for (final teamId in _teamIds) {
      final players = await getTeamPlayers(teamId, season: season);
      final match = players.where((player) => player.id == playerId).firstOrNull;
      if (match != null) {
        return match;
      }
    }
    return _fallback.getPlayerDetail(playerId, season: season);
  }

  @override
  Future<TeamStats> getTeamStats(String teamId, {required int season}) async {
    final payload = await _loadSnapshot('$_teamStatsDir/$teamId-$season.json');
    if (payload == null) {
      return _fallback.getTeamStats(teamId, season: season);
    }
    return TeamStats(
      teamId: payload['teamId'] as String? ?? teamId,
      season: payload['season'] as int? ?? season,
      hitting: (payload['hitting'] as Map<String, dynamic>? ?? const {})
          .map((key, value) => MapEntry(key, value.toString())),
      pitching: (payload['pitching'] as Map<String, dynamic>? ?? const {})
          .map((key, value) => MapEntry(key, value.toString())),
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
    final snapshot = await _bootstrapRepository.loadRecordsOverview(season);
    if (snapshot == null) {
      return _fallback.getRecordsOverview(season: season);
    }
    final leaders = snapshot['leaders'] as Map<String, dynamic>? ?? const {};
    final featured = snapshot['featured'] as Map<String, dynamic>? ?? const {};
    return RecordsOverview(
      season: snapshot['season'] as int? ?? season,
      avgLeaders: _parseLeaders(leaders['avg'] as List<dynamic>? ?? const []),
      hrLeaders: _parseLeaders(leaders['hr'] as List<dynamic>? ?? const []),
      opsLeaders: _parseLeaders(leaders['ops'] as List<dynamic>? ?? const []),
      eraLeaders: _parseLeaders(leaders['era'] as List<dynamic>? ?? const []),
      todayHitter: _parseFeatured(featured['todayHitter'] as Map<String, dynamic>? ?? const {'label': '오늘의 타자'}),
      todayPitcher: _parseFeatured(featured['todayPitcher'] as Map<String, dynamic>? ?? const {'label': '오늘의 투수'}),
      monthHitter: _parseFeatured(featured['monthHitter'] as Map<String, dynamic>? ?? const {'label': '이달의 타자'}),
      monthPitcher: _parseFeatured(featured['monthPitcher'] as Map<String, dynamic>? ?? const {'label': '이달의 투수'}),
    );
  }

  Future<Map<String, dynamic>?> _loadSnapshot(String assetPath) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded['payload'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  PlayerProfile _parsePlayer(Map<String, dynamic> json) {
    final seasonStats = (json['seasonStats'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList();
    final highlights = (json['highlights'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList();
    final recentGames = (json['recentGames'] as List<dynamic>? ?? const [])
        .map((item) {
          final map = item as Map<String, dynamic>;
          return PlayerRecentGame(
            date: map['date'] as String? ?? '',
            opponent: map['opponent'] as String? ?? '',
            summary: map['summary'] as String? ?? '',
          );
        })
        .toList();
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

const _teamIds = ['LG', 'KT', 'SK', 'SS', 'NC', 'HH', 'LT', 'HT', 'OB', 'WO'];
