import '../../core/widgets/dev_console.dart';
import '../models/player.dart';
import '../models/records_overview.dart';
import '../models/team_records_bundle.dart';
import '../models/team_stats.dart';
import 'player_repository.dart';

class FallbackPlayerRepository implements PlayerRepository {
  static final _log = DevConsole.instance;
  final PlayerRepository primary;
  final PlayerRepository secondary;

  FallbackPlayerRepository({required this.primary, required this.secondary});

  @override
  Future<List<PlayerProfile>> getTeamPlayers(
    String teamId, {
    required int season,
  }) async {
    final players = await _tryPrimary(
      label: 'team/$teamId/players',
      () => primary.getTeamPlayers(teamId, season: season),
      isValid: (value) => value.isNotEmpty,
    );
    if (players != null) {
      return players;
    }
    _log.warn('PLAYER team/$teamId/players fallback to secondary repository');
    return secondary.getTeamPlayers(teamId, season: season);
  }

  @override
  Future<PlayerProfile> getPlayerDetail(
    String playerId, {
    required int season,
  }) async {
    final player = await _tryPrimary(
      label: 'player/$playerId',
      () => primary.getPlayerDetail(playerId, season: season),
      isValid: (value) => value.id.isNotEmpty && value.name.isNotEmpty,
    );
    if (player != null) {
      return player;
    }
    _log.warn('PLAYER player/$playerId fallback to secondary repository');
    return secondary.getPlayerDetail(playerId, season: season);
  }

  @override
  Future<TeamStats> getTeamStats(String teamId, {required int season}) async {
    final stats = await _tryPrimary(
      label: 'team/$teamId/stats',
      () => primary.getTeamStats(teamId, season: season),
      isValid: (value) => value.hitting.isNotEmpty || value.pitching.isNotEmpty,
    );
    if (stats != null) {
      return stats;
    }
    _log.warn('PLAYER team/$teamId/stats fallback to secondary repository');
    return secondary.getTeamStats(teamId, season: season);
  }

  @override
  Future<TeamRecordsBundle> getTeamRecords(
    String teamId, {
    required int season,
  }) async {
    final bundle = await _tryPrimary(
      label: 'team/$teamId/records',
      () => primary.getTeamRecords(teamId, season: season),
      isValid: (value) =>
          value.players.isNotEmpty ||
          value.teamStats.hitting.isNotEmpty ||
          value.teamStats.pitching.isNotEmpty,
    );
    if (bundle != null) {
      return bundle;
    }
    _log.warn('PLAYER team/$teamId/records fallback to secondary repository');
    return secondary.getTeamRecords(teamId, season: season);
  }

  @override
  Future<RecordsOverview> getRecordsOverview({required int season}) async {
    final overview = await _tryPrimary(
      label: 'records/overview',
      () => primary.getRecordsOverview(season: season),
      isValid: (value) =>
          value.avgLeaders.isNotEmpty ||
          value.hrLeaders.isNotEmpty ||
          value.opsLeaders.isNotEmpty ||
          value.opsPlusLeaders.isNotEmpty ||
          value.eraLeaders.isNotEmpty,
    );
    if (overview != null) {
      return overview;
    }
    _log.warn('PLAYER records/overview fallback to secondary repository');
    return secondary.getRecordsOverview(season: season);
  }

  @override
  Future<List<RecordLeader>> getLeaderboard({
    required int season,
    required LeaderboardMetric metric,
  }) async {
    final leaders = await _tryPrimary(
      label: 'records/leaderboard/${metric.key}',
      () => primary.getLeaderboard(season: season, metric: metric),
      isValid: (value) => value.isNotEmpty || !metric.supportedByOfficialSource,
    );
    if (leaders != null) {
      return leaders;
    }
    _log.warn(
      'PLAYER records/leaderboard/${metric.key} fallback to secondary repository',
    );
    return secondary.getLeaderboard(season: season, metric: metric);
  }

  Future<T?> _tryPrimary<T>(
    Future<T> Function() action, {
    required String label,
    required bool Function(T value) isValid,
  }) async {
    try {
      final value = await action();
      if (isValid(value)) {
        return value;
      }
      _log.warn('PLAYER $label primary returned empty payload');
    } catch (error) {
      _log.warn('PLAYER $label primary failed: $error');
    }
    return null;
  }
}
