import '../models/game.dart';
import '../models/highlight_info.dart';
import '../models/relay.dart';
import '../models/boxscore.dart';
import '../models/schedule.dart';

/// 게임 데이터 추상 인터페이스 — API와 명시적 direct-primary 구현체가 이 계약을 따른다.
abstract class GameRepository {
  Future<List<Game>> getScoreboard(String date);
  Future<Game?> getGame(String gameId);
  Future<HighlightInfo?> getHighlightInfo(String gameId);
  Future<RelayData> getRelayData(String gameId, {int? afterSeqNo});
  Future<List<RelayItem>> getRelay(String gameId, {int? afterSeqNo});
  Future<CurrentAtBat?> getCurrentAtBat(String gameId);
  Future<GameBoxscoreData> getBoxscoreData(String gameId);
  Future<List<BatterRecord>> getBatters(String gameId, {required bool isAway});
  Future<List<PitcherRecord>> getPitchers(
    String gameId, {
    required bool isAway,
  });
  Future<GameLineupData> getLineupData(String gameId);
  Future<List<LineupEntry>> getLineup(String gameId, {required bool isAway});
  Future<List<ScheduleDay>> getSchedule(String yearMonth);
  Future<List<TeamStanding>> getStandings(int season);
}

/// API-backed repositories can consume a one-shot force-refresh request on the
/// next provider load. Direct KBO repositories already perform a network read,
/// so they do not need to implement this capability.
abstract class GameRepositoryRefreshControl {
  void requestScoreboardRefresh(String date);
  void requestGameRefresh(String gameId);
  void requestRelayRefresh(String gameId);
}
