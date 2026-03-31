import 'package:dio/dio.dart';

import 'game_repository.dart';
import '../models/game.dart';
import '../models/highlight_info.dart';
import '../models/relay.dart';
import '../models/boxscore.dart';
import '../models/schedule.dart';
import '../../core/widgets/dev_console.dart';

class FallbackGameRepository implements GameRepository {
  final GameRepository primary;
  final GameRepository fallback;

  FallbackGameRepository({
    required this.primary,
    required this.fallback,
  });

  bool _shouldFallback(Object error) {
    if (error is DioException) {
      return error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout;
    }
    return false;
  }

  Future<T> _run<T>(String label, Future<T> Function(GameRepository repo) action) async {
    try {
      return await action(primary);
    } catch (error) {
      if (!_shouldFallback(error)) rethrow;
      DevConsole.instance.warn('API $label failed, fallback to direct KBO: $error');
      return action(fallback);
    }
  }

  @override
  Future<List<Game>> getScoreboard(String date) =>
      _run('scoreboard', (repo) => repo.getScoreboard(date));

  @override
  Future<Game?> getGame(String gameId) =>
      _run('game/$gameId', (repo) => repo.getGame(gameId));

  @override
  Future<HighlightInfo?> getHighlightInfo(String gameId) =>
      _run('game/$gameId/highlights', (repo) => repo.getHighlightInfo(gameId));

  @override
  Future<RelayData> getRelayData(String gameId, {int? afterSeqNo}) =>
      _run('game/$gameId/relay', (repo) => repo.getRelayData(gameId, afterSeqNo: afterSeqNo));

  @override
  Future<List<RelayItem>> getRelay(String gameId, {int? afterSeqNo}) =>
      _run('game/$gameId/relayItems', (repo) => repo.getRelay(gameId, afterSeqNo: afterSeqNo));

  @override
  Future<CurrentAtBat?> getCurrentAtBat(String gameId) =>
      _run('game/$gameId/currentAtBat', (repo) => repo.getCurrentAtBat(gameId));

  @override
  Future<GameBoxscoreData> getBoxscoreData(String gameId) =>
      _run('game/$gameId/boxscore', (repo) => repo.getBoxscoreData(gameId));

  @override
  Future<List<BatterRecord>> getBatters(String gameId, {required bool isAway}) =>
      _run('game/$gameId/batters', (repo) => repo.getBatters(gameId, isAway: isAway));

  @override
  Future<List<PitcherRecord>> getPitchers(String gameId, {required bool isAway}) =>
      _run('game/$gameId/pitchers', (repo) => repo.getPitchers(gameId, isAway: isAway));

  @override
  Future<GameLineupData> getLineupData(String gameId) =>
      _run('game/$gameId/lineupData', (repo) => repo.getLineupData(gameId));

  @override
  Future<List<LineupEntry>> getLineup(String gameId, {required bool isAway}) =>
      _run('game/$gameId/lineup', (repo) => repo.getLineup(gameId, isAway: isAway));

  @override
  Future<List<ScheduleDay>> getSchedule(String yearMonth) =>
      _run('schedule/$yearMonth', (repo) => repo.getSchedule(yearMonth));

  @override
  Future<List<TeamStanding>> getStandings(int season) =>
      _run('standings/$season', (repo) => repo.getStandings(season));
}
