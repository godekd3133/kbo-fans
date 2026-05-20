import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/app_config.dart';
import 'core/bootstrap/startup_prep_state.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/widgets/dev_console.dart';
import 'data/providers.dart';
import 'services/game_event_alert_service.dart';
import 'services/push_notification_service.dart';
import 'services/ticket_alert_service.dart';
import 'services/widget_sync_service.dart';
import 'package:workmanager/workmanager.dart';

final Stopwatch _dartStartupStopwatch = Stopwatch()..start();

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

      runApp(
        const ProviderScope(retry: _disableProviderRetry, child: KboFansApp()),
      );

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

Duration? _disableProviderRetry(int retryCount, Object error) => null;

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
  StreamSubscription<Uri?>? _homeWidgetClickSubscription;
  Uri? _pendingHomeWidgetUri;
  bool _didInitializeHomeWidgetRouting = false;
  DateTime? _lastResumeSyncAt;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && !_isWidgetTestBinding()) {
      WidgetsBinding.instance.addObserver(_lifecycleObserver);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_initializeHomeWidgetRouting());
      });
    }
  }

  @override
  void dispose() {
    unawaited(_homeWidgetClickSubscription?.cancel());
    if (!kIsWeb && !_isWidgetTestBinding()) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    }
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

    ref.read(onboardingDoneProvider.notifier).setValue(onboardingDone);
    startupPrep.complete('초기 화면으로 이동합니다');
    DevConsole.instance.info(
      'STARTUP bootstrap complete ${_dartStartupStopwatch.elapsedMilliseconds}ms',
    );
  }

  Future<bool> _loadOnboardingState() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboardingDone') ?? false;
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
    final onboardingDone = ref.watch(onboardingDoneProvider);

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
    if (onboardingDone == true) {
      _routePendingHomeWidgetLaunch(router);
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
    final now = DateTime.now();
    final lastResumeSyncAt = _lastResumeSyncAt;
    if (lastResumeSyncAt != null &&
        now.difference(lastResumeSyncAt) < const Duration(seconds: 15)) {
      DevConsole.instance.info('Resume sync skipped: recently synced');
      return;
    }
    _lastResumeSyncAt = now;

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

  Future<void> _initializeHomeWidgetRouting() async {
    if (_didInitializeHomeWidgetRouting) {
      return;
    }
    _didInitializeHomeWidgetRouting = true;

    try {
      await WidgetSyncService.instance.initialize();
      final initialUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      _queueHomeWidgetUri(initialUri);
      _homeWidgetClickSubscription = HomeWidget.widgetClicked.listen(
        _queueHomeWidgetUri,
        onError: (Object error) {
          DevConsole.instance.warn('Home widget click stream failed: $error');
        },
      );
    } catch (error) {
      DevConsole.instance.warn('Home widget routing init failed: $error');
    }
  }

  void _queueHomeWidgetUri(Uri? uri) {
    final route = _routeForHomeWidgetUri(uri);
    if (route == null) {
      return;
    }
    _pendingHomeWidgetUri = uri;
    DevConsole.instance.info('Home widget launch queued: $route');
    if (mounted && ref.read(onboardingDoneProvider) == true) {
      final router = ref.read(routerProvider);
      _routePendingHomeWidgetLaunch(router);
    }
  }

  void _routePendingHomeWidgetLaunch(GoRouter router) {
    final uri = _pendingHomeWidgetUri;
    final route = _routeForHomeWidgetUri(uri);
    if (route == null) {
      return;
    }
    _pendingHomeWidgetUri = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      router.go(route);
      DevConsole.instance.info('Home widget launch routed: $route');
    });
  }

  String? _routeForHomeWidgetUri(Uri? uri) {
    if (uri == null || !uri.queryParameters.containsKey('homeWidget')) {
      return null;
    }

    final gameId = uri.queryParameters['gameId'];
    if (gameId == null || gameId.isEmpty) {
      return '/home';
    }

    final tab = uri.queryParameters['tab'];
    final encodedGameId = Uri.encodeComponent(gameId);
    if (tab == null || tab.isEmpty) {
      return '/game/$encodedGameId';
    }
    return '/game/$encodedGameId?tab=${Uri.encodeQueryComponent(tab)}';
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
