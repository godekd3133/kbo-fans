import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/app_config.dart';
import 'core/bootstrap/startup_prep_state.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/widgets/dev_console.dart';
import 'data/providers.dart';
import 'data/models/game.dart';
import 'data/repositories/kbo_direct_repository.dart';
import 'services/game_event_alert_service.dart';
import 'services/push_notification_service.dart';
import 'services/ticket_alert_service.dart';
import 'services/widget_sync_service.dart';
import 'package:workmanager/workmanager.dart';

final Stopwatch _dartStartupStopwatch = Stopwatch()..start();
const int _startupPreloadVersion = 2;

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      AppConfig.initialize();
      DevConsole.instance.info('환경: ${AppConfig.instance.environment.name}');

      FlutterError.onError = (details) {
        DevConsole.instance.error('Flutter: ${details.exceptionAsString()}');
        DevConsole.instance.error(
          details.stack?.toString() ?? 'Flutter stack: <none>',
        );
      };

      runApp(const ProviderScope(child: KboFansApp()));

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_shouldSkipPlatformServices()) {
          unawaited(_initializePlatformServicesDeferred());
        }
      });
    },
    (error, stack) {
      DevConsole.instance.error('$error');
      DevConsole.instance.error(stack.toString());
    },
  );
}

Future<void> _initializePlatformServicesDeferred() async {
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  await _initializePlatformServices();
}

bool _shouldSkipPlatformServices() {
  return kIsWeb;
}

Future<void> _initializePlatformServices() async {
  if (_shouldSkipPlatformServices()) {
    DevConsole.instance.info('Platform services skipped for local/web startup');
    return;
  }

  try {
    await TicketAlertService.instance.initialize();
  } catch (error) {
    DevConsole.instance.error('TicketAlert init failed: $error');
  }

  try {
    await WidgetSyncService.instance.initialize();
  } catch (error) {
    DevConsole.instance.error('WidgetSync init failed: $error');
  }

  try {
    await GameEventAlertService.instance.initialize();
  } catch (error) {
    DevConsole.instance.error('GameEventAlert init failed: $error');
  }

  try {
    if (!AppConfig.instance.isLocal) {
      final prefs = await SharedPreferences.getInstance();
      await PushNotificationService.instance.initialize(
        myTeam: prefs.getString('myTeam'),
      );
    } else {
      DevConsole.instance.info('Push init skipped for local startup');
    }
  } catch (error) {
    DevConsole.instance.error('Push init failed: $error');
  }

  try {
    if (!AppConfig.instance.isLocal) {
      await Workmanager().initialize(widgetCallbackDispatcher);
      await WidgetSyncService.instance.registerBackgroundRefresh();
    } else {
      DevConsole.instance.info('Workmanager skipped for local startup');
    }
  } catch (error) {
    DevConsole.instance.error('Workmanager init failed: $error');
  }
}

class KboFansApp extends ConsumerStatefulWidget {
  const KboFansApp({super.key});

  @override
  ConsumerState<KboFansApp> createState() => _KboFansAppState();
}

class _KboFansAppState extends ConsumerState<KboFansApp> {
  bool _didLogFirstFrame = false;
  bool _didScheduleBootstrap = false;
  static const int _startupTaskBatchSize = 6;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  Future<void> _bootstrapApp() async {
    final startupPrep = ref.read(startupPrepProvider.notifier);
    startupPrep.reset(message: '앱 설정을 확인하는 중입니다', totalSteps: 3);
    DevConsole.instance.info(
      'STARTUP bootstrap begin ${_dartStartupStopwatch.elapsedMilliseconds}ms',
    );

    var onboardingDone = false;

    try {
      onboardingDone = await _loadOnboardingState().timeout(
        const Duration(seconds: 3),
      );
      startupPrep.advance('마이팀 정보를 불러오는 중입니다');
    } catch (error) {
      DevConsole.instance.warn('onboarding bootstrap fallback: $error');
      onboardingDone = false;
    }

    try {
      await ref
          .read(myTeamProvider.notifier)
          .load()
          .timeout(const Duration(seconds: 3));
      startupPrep.advance('초기 화면용 데이터를 확인하는 중입니다');
    } catch (error) {
      DevConsole.instance.warn('myTeam bootstrap fallback: $error');
    }

    final shouldBlock = await _shouldRunBlockingStartupPrep();
    if (shouldBlock) {
      await _prefetchInitialData(blocking: true);
      await _markBlockingStartupPrepDone();
      ref.read(onboardingDoneProvider.notifier).setValue(onboardingDone);
      startupPrep.complete();
    } else {
      ref.read(onboardingDoneProvider.notifier).setValue(onboardingDone);
      startupPrep.complete('기존 캐시를 적용했습니다');
      unawaited(_prefetchInitialData(blocking: false));
    }
    DevConsole.instance.info(
      'STARTUP bootstrap complete ${_dartStartupStopwatch.elapsedMilliseconds}ms',
    );
  }

  Future<bool> _loadOnboardingState() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboardingDone') ?? false;
  }

  Future<void> _prefetchInitialData({required bool blocking}) async {
    if (_shouldSkipInitialPrefetch()) {
      return;
    }
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final yearMonth =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final season = now.year;
    final myTeamId = ref.read(myTeamProvider);
    final startupPrep = ref.read(startupPrepProvider.notifier);

    if (blocking) {
      startupPrep.configure(message: '최초 실행 데이터를 준비하는 중입니다');
      await _runBlockingStartupPrefetch(
        startupPrep: startupPrep,
        today: today,
        yearMonth: yearMonth,
        season: season,
        myTeamId: myTeamId,
      );
      return;
    }

    if (AppConfig.instance.preferDirectScrape) {
      unawaited(_primeLocalRelaySession());
    }
    _warm(ref.read(scoreboardProvider(today).future));
    _warm(ref.read(scheduleProvider(yearMonth).future));
    _warm(ref.read(standingsProvider(season).future));
    _warm(ref.read(recordsOverviewProvider(season).future));
    if (myTeamId != null && myTeamId.isNotEmpty) {
      _warm(ref.read(teamRecordsProvider('$myTeamId|$season').future));
      _warm(ref.read(homeAggregateProvider('$today|$myTeamId').future));
    }
  }

  Future<void> _runBlockingStartupPrefetch({
    required StartupPrepNotifier startupPrep,
    required String today,
    required String yearMonth,
    required int season,
    required String? myTeamId,
  }) async {
    final staticTasks = <({String label, Future<void> Function() request})>[
      if (AppConfig.instance.preferDirectScrape)
        (label: 'KBO 세션', request: _primeLocalRelaySession),
      (
        label: '오늘 경기',
        request: () async {
          await ref.read(scoreboardProvider(today).future);
        },
      ),
      (
        label: '이번 달 일정',
        request: () async {
          await ref.read(scheduleProvider(yearMonth).future);
        },
      ),
      (
        label: '순위표',
        request: () async {
          await ref.read(standingsProvider(season).future);
        },
      ),
      (
        label: '리그 기록 요약',
        request: () async {
          await ref.read(recordsOverviewProvider(season).future);
        },
      ),
      if (myTeamId != null && myTeamId.isNotEmpty) ...[
        (
          label: '마이팀 기록실',
          request: () async {
            await ref.read(teamRecordsProvider('$myTeamId|$season').future);
          },
        ),
        (
          label: '홈 요약 카드',
          request: () async {
            await ref.read(homeAggregateProvider('$today|$myTeamId').future);
          },
        ),
      ],
    ];

    startupPrep.configure(totalSteps: 3 + staticTasks.length, blocking: true);
    await _runStartupTasksBatched(startupPrep, staticTasks);

    final games = await ref.read(scoreboardProvider(today).future);
    ref.read(startupScoreboardProvider.notifier).setGames(games);
    await _saveStartupScoreboardCache(today, games);
  }

  Future<T?> _runStartupTask<T>(
    StartupPrepNotifier startupPrep,
    ({String label, Future<T> Function() request}) task,
  ) async {
    startupPrep.configure(message: 'API 대기 중: ${task.label} 받아오는 중입니다');
    try {
      final result = await task.request();
      startupPrep.advance('API 완료: ${task.label}');
      return result;
    } catch (error) {
      DevConsole.instance.warn(
        'startup preload skipped: ${task.label} / $error',
      );
      startupPrep.advance('API 실패: ${task.label}');
      return null;
    }
  }

  Future<void> _runStartupTasksBatched(
    StartupPrepNotifier startupPrep,
    List<({String label, Future<void> Function() request})> tasks,
  ) async {
    for (var i = 0; i < tasks.length; i += _startupTaskBatchSize) {
      final batch = tasks.skip(i).take(_startupTaskBatchSize).toList();
      final activeLabels = <String>{};
      await Future.wait(
        batch.map((task) async {
          activeLabels.add(task.label);
          _updateStartupParallelStatus(startupPrep, activeLabels);
          try {
            await _runStartupTask<void>(startupPrep, (
              label: task.label,
              request: () async {
                await task.request();
              },
            ));
          } finally {
            activeLabels.remove(task.label);
            _updateStartupParallelStatus(startupPrep, activeLabels);
          }
        }),
      );
    }
  }

  void _updateStartupParallelStatus(
    StartupPrepNotifier startupPrep,
    Set<String> activeLabels,
  ) {
    if (activeLabels.isEmpty) {
      startupPrep.configure(message: '다음 데이터를 준비하는 중입니다');
      return;
    }

    final labels = activeLabels.take(3).toList();
    final suffix = activeLabels.length > 3
        ? ' 외 ${activeLabels.length - 3}건'
        : '';
    startupPrep.configure(message: '병렬 로딩 중 · ${labels.join(' · ')}$suffix');
  }

  Future<void> _primeLocalRelaySession() async {
    if (!AppConfig.instance.preferDirectScrape ||
        !AppConfig.instance.isLocal ||
        kIsWeb) {
      return;
    }
    final direct = KboDirectRepository();
    await direct.primeRelaySession();
  }

  void _warm<T>(Future<T> future) {
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {},
      ),
    );
  }

  Future<void> _saveStartupScoreboardCache(
    String today,
    List<Game> games,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(games.map(_gameToJson).toList());
    await prefs.setString('home_scoreboard_cache_$today', payload);
  }

  Map<String, dynamic> _gameToJson(Game game) {
    return {
      'gameId': game.gameId,
      'status': game.status.name,
      'inning': game.inning,
      'stadium': game.stadium,
      'startTime': game.startTime,
      'crowd': game.crowd,
      'away': _teamScoreToJson(game.away),
      'home': _teamScoreToJson(game.home),
    };
  }

  Map<String, dynamic> _teamScoreToJson(TeamScore team) {
    return {
      'teamId': team.teamId,
      'teamName': team.teamName,
      'shortName': team.shortName,
      'score': team.score,
      'innings': team.innings,
      'hits': team.hits,
      'errors': team.errors,
      'walks': team.walks,
    };
  }

  bool _shouldSkipInitialPrefetch() {
    if (_isWidgetTestBinding()) {
      return true;
    }
    return false;
  }

  Future<bool> _shouldRunBlockingStartupPrep() async {
    return false;
  }

  Future<void> _markBlockingStartupPrepDone() async {
    final prefs = await SharedPreferences.getInstance();
    final key =
        'startup_preload_version:${AppConfig.instance.environment.name}';
    await prefs.setInt(key, _startupPreloadVersion);
  }

  bool _isWidgetTestBinding() {
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    return bindingName.contains('TestWidgetsFlutterBinding') ||
        bindingName.contains('AutomatedTestWidgetsFlutterBinding') ||
        bindingName.contains('LiveTestWidgetsFlutterBinding');
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final myTeamId = ref.watch(myTeamProvider);
    final today = _todayKey();
    final startupGames = ref.watch(startupScoreboardProvider);
    final scoreboardAsync = ref.watch(scoreboardProvider(today));

    if (startupGames != null && startupGames.isNotEmpty) {
      unawaited(
        WidgetSyncService.instance.syncScoreboard(
          games: startupGames,
          myTeamId: myTeamId,
          repository: ref.read(gameRepositoryProvider),
        ),
      );
    }

    scoreboardAsync.whenData((games) {
      unawaited(
        WidgetSyncService.instance.syncScoreboard(
          games: games,
          myTeamId: myTeamId,
          repository: ref.read(gameRepositoryProvider),
        ),
      );
    });

    if (!_didScheduleBootstrap) {
      _didScheduleBootstrap = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_didLogFirstFrame) {
          _didLogFirstFrame = true;
          DevConsole.instance.info(
            'STARTUP first Flutter frame ${_dartStartupStopwatch.elapsedMilliseconds}ms',
          );
        }
        if (!mounted) {
          return;
        }
        ref
            .read(startupPrepProvider.notifier)
            .reset(message: '로딩 화면을 준비하는 중입니다', totalSteps: 1);
        Future<void>.delayed(const Duration(milliseconds: 150), () {
          if (!mounted) {
            return;
          }
          unawaited(_bootstrapApp());
        });
      });
    }

    return MaterialApp.router(
      title: 'KBO Fans',
      theme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: !AppConfig.instance.isRelease,
      builder: (context, child) {
        if (AppConfig.instance.isRelease) {
          return child ?? const SizedBox.shrink();
        }

        return DevConsoleOverlay(child: child ?? const SizedBox.shrink());
      },
    );
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _syncLiveSurfacesOnResume() async {
    try {
      final today = _todayKey();
      ref.invalidate(scoreboardProvider(today));
      final games = await ref.read(scoreboardProvider(today).future);
      final myTeamId = ref.read(myTeamProvider);
      await WidgetSyncService.instance.syncScoreboard(
        games: games,
        myTeamId: myTeamId,
        repository: ref.read(gameRepositoryProvider),
      );
      DevConsole.instance.info('Resume sync complete');
    } catch (error) {
      DevConsole.instance.warn('Resume sync failed: $error');
    }
  }

  late final WidgetsBindingObserver _lifecycleObserver = _AppLifecycleObserver(
    onResumed: () {
      unawaited(_syncLiveSurfacesOnResume());
    },
  );
}

class _AppLifecycleObserver with WidgetsBindingObserver {
  _AppLifecycleObserver({required this.onResumed});

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumed();
    }
  }
}
