import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import 'api/api_client.dart';
import 'repositories/game_repository.dart';
import 'repositories/api_game_repository.dart';
import 'repositories/kbo_direct_repository.dart';
import 'repositories/player_repository.dart';
import 'repositories/api_player_repository.dart';
import 'repositories/mock_player_repository.dart';
import 'models/game.dart';
import 'models/highlight_info.dart';
import 'models/relay.dart';
import 'models/boxscore.dart';
import 'models/player.dart';
import 'models/records_overview.dart';
import 'models/schedule.dart';
import 'models/team_stats.dart';
import '../services/ticket_alert_service.dart';

/// API 클라이언트 (RELEASE에서만 실제 사용)
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// GameRepository — 환경에 따라 자동 전환
final gameRepositoryProvider = Provider<GameRepository>((ref) {
  // 웹은 KBO 원본을 직접 호출하면 CORS/프록시 이슈가 커서 항상 백엔드 API를 경유한다.
  if (kIsWeb) {
    return ApiGameRepository(ref.read(apiClientProvider));
  }

  if (AppConfig.instance.isRelease) {
    return ApiGameRepository(ref.read(apiClientProvider));
  }

  return KboDirectRepository();
});

// ── 마이팀 전역 상태 ──

class MyTeamNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('myTeam');
  }

  Future<void> setTeam(String? teamId) async {
    final prefs = await SharedPreferences.getInstance();
    if (teamId != null) {
      await prefs.setString('myTeam', teamId);
    } else {
      await prefs.remove('myTeam');
    }
    state = teamId;
  }
}

final myTeamProvider = NotifierProvider<MyTeamNotifier, String?>(
  () => MyTeamNotifier(),
);

// ── 스코어보드 ──

final scoreboardProvider = FutureProvider.family<List<Game>, String>((
  ref,
  date,
) {
  return ref.watch(gameRepositoryProvider).getScoreboard(date);
});

final gameProvider = FutureProvider.family<Game?, String>((ref, gameId) {
  return ref.watch(gameRepositoryProvider).getGame(gameId);
});

final highlightInfoProvider = FutureProvider.family<HighlightInfo?, String>((ref, gameId) {
  return ref.watch(gameRepositoryProvider).getHighlightInfo(gameId);
});

final ticketAlertEnabledProvider = FutureProvider.family<bool, String>((
  ref,
  gameId,
) {
  return TicketAlertService.instance.isAlertEnabled(gameId);
});

// ── 경기 상세 ──

final relayDataProvider = FutureProvider.family<RelayData, String>((
  ref,
  gameId,
) {
  return ref.watch(gameRepositoryProvider).getRelayData(gameId);
});

final relayProvider = FutureProvider.family<List<RelayItem>, String>((
  ref,
  gameId,
) {
  return ref.watch(gameRepositoryProvider).getRelay(gameId);
});

final currentAtBatProvider = FutureProvider.family<CurrentAtBat?, String>((
  ref,
  gameId,
) {
  return ref.watch(gameRepositoryProvider).getCurrentAtBat(gameId);
});

/// (gameId, isAway) 튜플을 문자열 키로 변환하여 family 파라미터로 사용
final battersProvider = FutureProvider.family<List<BatterRecord>, String>((
  ref,
  key,
) {
  final parts = key.split('|');
  final gameId = parts[0];
  final isAway = parts[1] == 'true';
  return ref.watch(gameRepositoryProvider).getBatters(gameId, isAway: isAway);
});

final pitchersProvider = FutureProvider.family<List<PitcherRecord>, String>((
  ref,
  key,
) {
  final parts = key.split('|');
  final gameId = parts[0];
  final isAway = parts[1] == 'true';
  return ref.watch(gameRepositoryProvider).getPitchers(gameId, isAway: isAway);
});

final lineupProvider = FutureProvider.family<List<LineupEntry>, String>((
  ref,
  key,
) {
  final parts = key.split('|');
  final gameId = parts[0];
  final isAway = parts[1] == 'true';
  return ref.watch(gameRepositoryProvider).getLineup(gameId, isAway: isAway);
});

// ── 일정/순위 ──

final scheduleProvider = FutureProvider.family<List<ScheduleDay>, String>((
  ref,
  yearMonth,
) {
  return ref.watch(gameRepositoryProvider).getSchedule(yearMonth);
});

final standingsProvider = FutureProvider.family<List<TeamStanding>, int>((
  ref,
  season,
) {
  return ref.watch(gameRepositoryProvider).getStandings(season);
});

final playerRepositoryProvider = Provider<PlayerRepository>((ref) {
  if (kIsWeb || AppConfig.instance.isRelease) {
    return ApiPlayerRepository(ref.read(apiClientProvider));
  }
  return MockPlayerRepository();
});

final teamPlayersProvider = FutureProvider.family<List<PlayerProfile>, String>((ref, key) {
  final parts = key.split('|');
  final teamId = parts[0];
  final season = int.parse(parts[1]);
  return ref.watch(playerRepositoryProvider).getTeamPlayers(teamId, season: season);
});

final playerDetailProvider = FutureProvider.family<PlayerProfile, String>((ref, key) {
  final parts = key.split('|');
  final playerId = parts[0];
  final season = int.parse(parts[1]);
  return ref.watch(playerRepositoryProvider).getPlayerDetail(playerId, season: season);
});

final teamStatsProvider = FutureProvider.family<TeamStats, String>((ref, key) {
  final parts = key.split('|');
  final teamId = parts[0];
  final season = int.parse(parts[1]);
  return ref.watch(playerRepositoryProvider).getTeamStats(teamId, season: season);
});

final recordsOverviewProvider = FutureProvider.family<RecordsOverview, int>((ref, season) {
  return ref.watch(playerRepositoryProvider).getRecordsOverview(season: season);
});
