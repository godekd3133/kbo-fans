import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config/app_config.dart';

import 'api/api_client.dart';
import 'repositories/game_repository.dart';
import 'repositories/api_game_repository.dart';
import 'repositories/api_home_repository.dart';
import 'repositories/fallback_game_repository.dart';
import 'repositories/kbo_direct_repository.dart';
import 'repositories/player_repository.dart';
import 'repositories/api_player_repository.dart';
import 'repositories/device_snapshot_player_repository.dart';
import 'repositories/fallback_player_repository.dart';
import 'repositories/kbo_direct_player_repository.dart';
import 'repositories/local_asset_player_repository.dart';
import 'models/game.dart';
import 'models/highlight_info.dart';
import 'models/relay.dart';
import 'models/boxscore.dart';
import 'models/player.dart';
import 'models/records_overview.dart';
import 'models/home_aggregate.dart';
import 'models/schedule.dart';
import 'models/team_records_bundle.dart';
import 'models/team_stats.dart';
import '../services/push_notification_service.dart';
import '../services/ticket_alert_service.dart';

const _kboPersonImageBase =
    'https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/person/middle';

/// API 클라이언트 (RELEASE에서만 실제 사용)
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// GameRepository — 환경에 따라 자동 전환
final gameRepositoryProvider = Provider<GameRepository>((ref) {
  final apiRepository = ApiGameRepository(ref.read(apiClientProvider));

  if (kIsWeb) {
    return apiRepository;
  }

  if (AppConfig.instance.preferDirectScrape ||
      AppConfig.instance.shouldPreferLocalNativeData) {
    return KboDirectRepository();
  }

  if (AppConfig.instance.isLocal) {
    return FallbackGameRepository(
      primary: apiRepository,
      fallback: KboDirectRepository(),
    );
  }

  return apiRepository;
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
    await PushNotificationService.instance.syncRegistration(myTeam: teamId);
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

final highlightInfoProvider = FutureProvider.family<HighlightInfo?, String>((
  ref,
  gameId,
) {
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

final gameBoxscoreProvider = FutureProvider.family<GameBoxscoreData, String>((
  ref,
  gameId,
) {
  return ref.watch(gameRepositoryProvider).getBoxscoreData(gameId);
});

/// (gameId, isAway) 튜플을 문자열 키로 변환하여 family 파라미터로 사용
final battersProvider = FutureProvider.family<List<BatterRecord>, String>((
  ref,
  key,
) {
  final parts = key.split('|');
  final gameId = parts[0];
  final isAway = parts[1] == 'true';
  return ref
      .watch(gameBoxscoreProvider(gameId).future)
      .then((data) => (isAway ? data.away : data.home).batters);
});

final pitchersProvider = FutureProvider.family<List<PitcherRecord>, String>((
  ref,
  key,
) {
  final parts = key.split('|');
  final gameId = parts[0];
  final isAway = parts[1] == 'true';
  return ref
      .watch(gameBoxscoreProvider(gameId).future)
      .then((data) => (isAway ? data.away : data.home).pitchers);
});

final gameLineupProvider = FutureProvider.family<GameLineupData, String>((
  ref,
  gameId,
) {
  return ref.watch(gameRepositoryProvider).getLineupData(gameId);
});

final lineupProvider = FutureProvider.family<List<LineupEntry>, String>((
  ref,
  key,
) {
  final parts = key.split('|');
  final gameId = parts[0];
  final isAway = parts[1] == 'true';
  return ref
      .watch(gameLineupProvider(gameId).future)
      .then((data) => (isAway ? data.away : data.home).lineup);
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

final homeRepositoryProvider = Provider<ApiHomeRepository>((ref) {
  return ApiHomeRepository(ref.watch(apiClientProvider));
});

final homeAggregateProvider = FutureProvider.family<HomeAggregate, String>((
  ref,
  key,
) async {
  final parts = key.split('|');
  final date = parts[0];
  final myTeam = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;

  final shouldUseApiHome =
      kIsWeb ||
      !AppConfig.instance.isLocal ||
      AppConfig.instance.hasApiBaseUrlOverride;

  if (shouldUseApiHome) {
    try {
      return await ref
          .read(homeRepositoryProvider)
          .getHomeAggregate(date: date, myTeam: myTeam);
    } catch (_) {
      if (kIsWeb || !AppConfig.instance.isLocal) {
        rethrow;
      }
      // Local native direct-debug sessions can still render from the component
      // providers if the backend is unavailable.
    }
  }

  final scoreboard = await ref.read(scoreboardProvider(date).future);
  final yearMonth = date.substring(0, 7);
  final currentMonthDate = DateTime(
    int.parse(date.substring(0, 4)),
    int.parse(date.substring(5, 7)),
  );
  final previousMonthDate = DateTime(
    currentMonthDate.year,
    currentMonthDate.month - 1,
  );
  final previousYearMonth =
      '${previousMonthDate.year.toString().padLeft(4, '0')}-${previousMonthDate.month.toString().padLeft(2, '0')}';
  final season = int.parse(date.substring(0, 4));
  final schedules = await Future.wait([
    ref.read(scheduleProvider(previousYearMonth).future),
    ref.read(scheduleProvider(yearMonth).future),
  ]);
  final schedule = [...schedules[0], ...schedules[1]];
  final standings = await ref.read(standingsProvider(season).future);
  final overview = await ref.read(recordsOverviewProvider(season).future);

  return buildLocalHomeAggregate(
    date: date,
    myTeam: myTeam,
    games: scoreboard,
    scheduleDays: schedule,
    standings: standings,
    overview: overview,
  );
});

final playerRepositoryProvider = Provider<PlayerRepository>((ref) {
  final apiRepository = ApiPlayerRepository(ref.read(apiClientProvider));
  final directRepository = KboDirectPlayerRepository();
  if (kIsWeb) {
    return apiRepository;
  }
  if (AppConfig.instance.shouldPreferLocalNativeData) {
    return LocalAssetPlayerRepository();
  }
  if (AppConfig.instance.preferDirectScrape) {
    return DeviceSnapshotPlayerRepository(
      primary: directRepository,
      fallback: FallbackPlayerRepository(
        primary: LocalAssetPlayerRepository(),
        secondary: apiRepository,
      ),
    );
  }
  return DeviceSnapshotPlayerRepository(
    primary: apiRepository,
    fallback: LocalAssetPlayerRepository(),
  );
});

final allPlayerImageMapProvider =
    FutureProvider.family<Map<String, String>, int>((ref, season) async {
      final repository = ref.watch(playerRepositoryProvider);
      if (repository is LocalAssetPlayerRepository) {
        return repository.buildPlayerImageMap(season: season);
      }

      final result = <String, String>{};
      for (final teamId in const [
        'LG',
        'KT',
        'SK',
        'SS',
        'NC',
        'HH',
        'LT',
        'HT',
        'OB',
        'WO',
      ]) {
        final players = await repository.getTeamPlayers(teamId, season: season);
        for (final player in players) {
          final imageUrl =
              (player.imageUrl != null && player.imageUrl!.isNotEmpty)
              ? player.imageUrl
              : (player.id.isNotEmpty
                    ? '$_kboPersonImageBase/$season/${player.id}.jpg'
                    : null);
          if (player.name.isEmpty || imageUrl == null || imageUrl.isEmpty) {
            continue;
          }
          result[player.name] = imageUrl;
        }
      }
      return result;
    });

final teamPlayersProvider = FutureProvider.family<List<PlayerProfile>, String>((
  ref,
  key,
) {
  final parts = key.split('|');
  final teamId = parts[0];
  final season = int.parse(parts[1]);
  return ref
      .watch(playerRepositoryProvider)
      .getTeamPlayers(teamId, season: season);
});

final playerDetailProvider = FutureProvider.family<PlayerProfile, String>((
  ref,
  key,
) {
  final parts = key.split('|');
  final playerId = parts[0];
  final season = int.parse(parts[1]);
  return ref
      .watch(playerRepositoryProvider)
      .getPlayerDetail(playerId, season: season);
});

final teamStatsProvider = FutureProvider.family<TeamStats, String>((ref, key) {
  final parts = key.split('|');
  final teamId = parts[0];
  final season = int.parse(parts[1]);
  return ref
      .watch(playerRepositoryProvider)
      .getTeamStats(teamId, season: season);
});

final teamRecordsProvider = FutureProvider.family<TeamRecordsBundle, String>((
  ref,
  key,
) {
  final parts = key.split('|');
  final teamId = parts[0];
  final season = int.parse(parts[1]);
  return ref
      .watch(playerRepositoryProvider)
      .getTeamRecords(teamId, season: season);
});

final recordsOverviewProvider = FutureProvider.family<RecordsOverview, int>((
  ref,
  season,
) {
  return ref.watch(playerRepositoryProvider).getRecordsOverview(season: season);
});

final leaderboardProvider = FutureProvider.family<List<RecordLeader>, String>((
  ref,
  key,
) {
  final parts = key.split('|');
  final season = int.parse(parts[0]);
  final metric = LeaderboardMetricX.fromKey(parts[1]) ?? LeaderboardMetric.avg;
  return ref
      .watch(playerRepositoryProvider)
      .getLeaderboard(season: season, metric: metric);
});
