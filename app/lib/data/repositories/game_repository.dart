import '../models/game.dart';
import '../models/highlight_info.dart';
import '../models/relay.dart';
import '../models/boxscore.dart';
import '../models/schedule.dart';

/// 게임 데이터 추상 인터페이스 — Mock과 API 구현체가 이 계약을 따른다
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
