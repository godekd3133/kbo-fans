import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config/app_config.dart';
import '../core/utils/kbo_time.dart';
import '../core/widgets/dev_console.dart';

import 'api/api_client.dart';
import 'repositories/game_repository.dart';
import 'repositories/api_game_repository.dart';
import 'repositories/api_home_repository.dart';
import 'repositories/kbo_direct_repository.dart';
import 'repositories/player_repository.dart';
import 'repositories/api_player_repository.dart';
import 'repositories/device_snapshot_player_repository.dart';
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

/// API 클라이언트 (기본 backend API data mode에서 사용)
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// GameRepository — 환경에 따라 자동 전환
final gameRepositoryProvider = Provider<GameRepository>((ref) {
  if (AppConfig.instance.shouldUseBackendApi) {
    return ApiGameRepository(ref.read(apiClientProvider));
  }

  return KboDirectRepository();
});

// ── 마이팀 전역 상태 ──

typedef MyTeamRegistrationConvergence = Future<void> Function(String? myTeamId);

final myTeamRegistrationConvergenceProvider =
    Provider<MyTeamRegistrationConvergence>((ref) {
      return (myTeamId) => PushNotificationService.instance
          .convergeRegistration(myTeam: myTeamId);
    });

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
    unawaited(_convergeRegistration(teamId));
  }

  Future<void> _convergeRegistration(String? teamId) async {
    try {
      await ref.read(myTeamRegistrationConvergenceProvider)(teamId);
    } catch (error) {
      DevConsole.instance.warn(
        'My team push registration convergence deferred: $error',
      );
    }
  }
}

final myTeamProvider = NotifierProvider<MyTeamNotifier, String?>(
  () => MyTeamNotifier(),
);

class KboDateNotifier extends Notifier<String> {
  @override
  String build() => kboDateKey();

  void refresh({DateTime? instant}) {
    final nextDate = kboDateKey(instant);
    if (state != nextDate) {
      state = nextDate;
    }
  }
}

final kboDateProvider = NotifierProvider<KboDateNotifier, String>(
  KboDateNotifier.new,
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

List<String> kboScheduleSeasonMonths(int season) {
  return [
    for (var month = 3; month <= 11; month += 1)
      '$season-${month.toString().padLeft(2, '0')}',
  ];
}

@visibleForTesting
Future<List<ScheduleDay>> loadKboSeasonScheduleBounded({
  required List<String> yearMonths,
  required Future<List<ScheduleDay>> Function(String yearMonth) loadMonth,
  int maxConcurrent = 3,
}) async {
  if (yearMonths.isEmpty) {
    return const [];
  }
  if (maxConcurrent <= 0) {
    throw ArgumentError.value(
      maxConcurrent,
      'maxConcurrent',
      'must be positive',
    );
  }

  final results = List<List<ScheduleDay>?>.filled(yearMonths.length, null);
  var nextIndex = 0;
  Object? firstError;
  StackTrace? firstStackTrace;

  Future<void> worker() async {
    while (firstError == null) {
      final index = nextIndex;
      if (index >= yearMonths.length) {
        return;
      }
      nextIndex += 1;
      try {
        results[index] = await loadMonth(yearMonths[index]);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
  }

  final workerCount = maxConcurrent < yearMonths.length
      ? maxConcurrent
      : yearMonths.length;
  await Future.wait(List.generate(workerCount, (_) => worker()));
  if (firstError != null) {
    Error.throwWithStackTrace(firstError!, firstStackTrace!);
  }
  return [for (final days in results) ...days!];
}

final seasonScheduleProvider = FutureProvider.family<List<ScheduleDay>, int>((
  ref,
  season,
) async {
  return loadKboSeasonScheduleBounded(
    yearMonths: kboScheduleSeasonMonths(season),
    loadMonth: (yearMonth) => ref.read(scheduleProvider(yearMonth).future),
  );
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

  if (AppConfig.instance.shouldUseBackendApi) {
    try {
      return await ref
          .read(homeRepositoryProvider)
          .getHomeAggregate(date: date, myTeam: myTeam);
    } catch (_) {
      rethrow;
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
  if (AppConfig.instance.shouldUseBackendApi) {
    return ApiPlayerRepository(ref.read(apiClientProvider));
  }

  return DeviceSnapshotPlayerRepository(
    primary: KboDirectPlayerRepository(),
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
                    ? kboPlayerImageUrl(season: season, playerId: player.id)
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
