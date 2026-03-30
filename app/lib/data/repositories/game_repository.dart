import '../models/game.dart';
import '../models/relay.dart';
import '../models/boxscore.dart';

/// 게임 데이터 추상 인터페이스 — Mock과 API 구현체가 이 계약을 따른다
abstract class GameRepository {
  Future<List<Game>> getScoreboard(String date);
  Future<List<RelayItem>> getRelay(String gameId, {int? afterSeqNo});
  Future<CurrentAtBat?> getCurrentAtBat(String gameId);
  Future<List<BatterRecord>> getBatters(String gameId, {required bool isAway});
  Future<List<PitcherRecord>> getPitchers(String gameId, {required bool isAway});
  Future<List<LineupEntry>> getLineup(String gameId, {required bool isAway});
}
