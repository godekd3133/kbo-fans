import '../models/game.dart';
import '../models/relay.dart';
import '../models/boxscore.dart';
import '../mock/mock_games.dart';
import '../mock/mock_game_detail.dart';
import 'game_repository.dart';

class MockGameRepository implements GameRepository {
  @override
  Future<List<Game>> getScoreboard(String date) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return mockGames;
  }

  @override
  Future<List<RelayItem>> getRelay(String gameId, {int? afterSeqNo}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (afterSeqNo != null) {
      return mockRelayItems.where((r) => r.seqNo > afterSeqNo).toList();
    }
    return mockRelayItems;
  }

  @override
  Future<CurrentAtBat?> getCurrentAtBat(String gameId) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return mockCurrentAtBat;
  }

  @override
  Future<List<BatterRecord>> getBatters(String gameId, {required bool isAway}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return mockAwayBatters;
  }

  @override
  Future<List<PitcherRecord>> getPitchers(String gameId, {required bool isAway}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return mockAwayPitchers;
  }

  @override
  Future<List<LineupEntry>> getLineup(String gameId, {required bool isAway}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return mockAwayLineup;
  }
}
