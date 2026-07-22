import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/app_config.dart';
import 'core/bootstrap/startup_prep_state.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_controller.dart';
import 'core/router/app_router.dart';
import 'core/router/app_route_sanitizer.dart';
import 'core/utils/kbo_time.dart';
import 'core/widgets/dev_console.dart';
import 'data/providers.dart';
import 'features/settings/release_notes_prompt.dart';
import 'services/game_event_alert_service.dart';
import 'services/live_activity_service.dart';
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
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
      }

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

@visibleForTesting
Future<T> refreshOnResumeUnlessLoading<T>({
  required AsyncValue<T> current,
  required VoidCallback invalidate,
  required Future<T> Function() readFuture,
}) {
  if (!current.isLoading) {
    invalidate();
  }
  return readFuture();
}

Future<void> _initializePlatformServicesDeferred() async {
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  await _initializePlatformServices();
}

bool _shouldSkipPlatformServices() {
  return kIsWeb;
}

bool _shouldUseRemotePushServices() {
  return shouldUseRemotePushServices(
    isWeb: kIsWeb,
    useBackendApi: AppConfig.instance.shouldUseBackendApi,
  );
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
    if (_shouldUseRemotePushServices()) {
      final prefs = await SharedPreferences.getInstance();
      await PushNotificationService.instance.initialize(
        myTeam: prefs.getString('myTeam'),
      );
      await LiveActivityService.instance.syncPushToStartToken();
    } else {
      DevConsole.instance.info('Push init skipped: no remote push endpoint');
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
  bool _didScheduleReleaseNotesPrompt = false;
  StreamSubscription<Uri?>? _homeWidgetClickSubscription;
  StreamSubscription<String>? _pushNotificationRouteSubscription;
  StreamSubscription<PushForegroundNotification>?
  _foregroundPushNotificationSubscription;
  Uri? _pendingHomeWidgetUri;
  String? _pendingPushNotificationRoute;
  PushForegroundNotification? _pendingForegroundPushNotification;
  bool _didInitializeHomeWidgetRouting = false;
  bool _didInitializePushNotificationRouting = false;
  bool _foregroundPushDialogVisible = false;
  DateTime? _lastResumeSyncAt;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(appThemeModeProvider.notifier).load());
    if (!kIsWeb && !_isWidgetTestBinding()) {
      WidgetsBinding.instance.addObserver(_lifecycleObserver);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_initializeHomeWidgetRouting());
      });
    }
    if (!kIsWeb) {
      _initializePushNotificationRouting();
    }
  }

  @override
  void dispose() {
    unawaited(_homeWidgetClickSubscription?.cancel());
    unawaited(_pushNotificationRouteSubscription?.cancel());
    unawaited(_foregroundPushNotificationSubscription?.cancel());
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

    final myTeamId = ref.read(myTeamProvider);
    ref.read(onboardingDoneProvider.notifier).setValue(onboardingDone);
    startupPrep.complete('초기 화면으로 이동합니다');
    if (onboardingDone == true && myTeamId != null && myTeamId.isNotEmpty) {
      unawaited(
        PushNotificationService.instance.ensureAutoPermissionAndSync(
          myTeam: myTeamId,
        ),
      );
    }
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
    final themeMode = ref.watch(appThemeModeProvider);

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
      _routePendingPushNotificationLaunch(router);
      _scheduleReleaseNotesPrompt();
    }

    return MaterialApp.router(
      title: 'KBO Fans',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode.themeMode,
      highContrastTheme: AppTheme.light,
      highContrastDarkTheme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: !AppConfig.instance.isRelease,
      builder: (context, child) {
        AppColors.sync(AppTheme.colorsOf(context));
        final appChild = child ?? const SizedBox.shrink();
        if (!AppConfig.instance.shouldShowDevConsole) {
          return appChild;
        }

        return DevConsoleOverlay(child: appChild);
      },
    );
  }

  void _scheduleReleaseNotesPrompt() {
    if (_didScheduleReleaseNotesPrompt) {
      return;
    }
    _didScheduleReleaseNotesPrompt = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_showReleaseNotesPromptSafely());
    });
  }

  Future<void> _showReleaseNotesPromptSafely() async {
    try {
      final navigatorContext = appRootNavigatorContext;
      if (navigatorContext == null) {
        DevConsole.instance.warn('Release notes prompt skipped: no navigator');
        return;
      }
      await showReleaseNotesPromptIfNeeded(
        navigatorContext,
        router: ref.read(routerProvider),
      );
    } catch (error, stack) {
      DevConsole.instance.warn('Release notes prompt failed: $error');
      DevConsole.instance.warn(stack.toString());
    }
  }

  String _todayKey() {
    return kboDateKey();
  }

  Future<void> _syncLiveSurfacesOnResume() async {
    final now = DateTime.now();
    final lastResumeSyncAt = _lastResumeSyncAt;
    if (lastResumeSyncAt != null &&
        now.difference(lastResumeSyncAt) < const Duration(seconds: 8)) {
      DevConsole.instance.info('Resume sync skipped: recently synced');
      return;
    }
    _lastResumeSyncAt = now;

    try {
      final today = _todayKey();
      final provider = scoreboardProvider(today);
      final games = await refreshOnResumeUnlessLoading(
        current: ref.read(provider),
        invalidate: () => ref.invalidate(provider),
        readFuture: () => ref.read(provider.future),
      );
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

  void _initializePushNotificationRouting() {
    if (_didInitializePushNotificationRouting) {
      return;
    }
    _didInitializePushNotificationRouting = true;
    _pushNotificationRouteSubscription = PushNotificationService
        .instance
        .notificationRoutes
        .listen(
          _queuePushNotificationRoute,
          onError: (Object error) {
            DevConsole.instance.warn('Push route stream failed: $error');
          },
        );
    _foregroundPushNotificationSubscription = PushNotificationService
        .instance
        .foregroundNotifications
        .listen(
          _queueForegroundPushNotification,
          onError: (Object error) {
            DevConsole.instance.warn('Foreground push stream failed: $error');
          },
        );
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

  void _queuePushNotificationRoute(String route) {
    final safeRoute = _safeLaunchRoute(route);
    if (safeRoute == null) {
      DevConsole.instance.warn('Push launch route ignored: $route');
      return;
    }
    _pendingPushNotificationRoute = safeRoute;
    DevConsole.instance.info('Push launch queued: $safeRoute');
    if (mounted && ref.read(onboardingDoneProvider) == true) {
      final router = ref.read(routerProvider);
      _routePendingPushNotificationLaunch(router);
    }
  }

  void _queueForegroundPushNotification(
    PushForegroundNotification notification,
  ) {
    final safeRoute = _safeLaunchRoute(notification.route ?? '/notifications');
    _pendingForegroundPushNotification = PushForegroundNotification(
      title: notification.title,
      body: notification.body,
      route: safeRoute ?? '/notifications',
    );
    DevConsole.instance.info('Foreground push dialog queued');
    _showPendingForegroundPushNotification();
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

  void _routePendingPushNotificationLaunch(GoRouter router) {
    final route = _pendingPushNotificationRoute;
    if (route == null) {
      return;
    }
    _pendingPushNotificationRoute = null;
    _routePushNotificationSafely(router, route, source: 'Push launch');
  }

  void _showPendingForegroundPushNotification() {
    if (_foregroundPushDialogVisible) {
      return;
    }
    final notification = _pendingForegroundPushNotification;
    if (notification == null) {
      return;
    }
    _pendingForegroundPushNotification = null;
    _foregroundPushDialogVisible = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _foregroundPushDialogVisible = false;
        return;
      }
      final navigatorContext = appRootNavigatorContext;
      if (navigatorContext == null) {
        _foregroundPushDialogVisible = false;
        DevConsole.instance.warn(
          'Foreground push dialog skipped: no navigator',
        );
        return;
      }

      final shouldOpen = await showDialog<bool>(
        context: navigatorContext,
        barrierDismissible: true,
        builder: (context) {
          final body = notification.body.trim();
          return AlertDialog(
            title: Text(notification.title),
            content: body.isEmpty ? null : Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('닫기'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('보기'),
              ),
            ],
          );
        },
      );

      _foregroundPushDialogVisible = false;
      if (!mounted) {
        return;
      }
      if (shouldOpen == true) {
        await Future<void>.delayed(Duration.zero);
        if (!mounted) {
          return;
        }
        _routePushNotificationSafely(
          ref.read(routerProvider),
          notification.route ?? '/notifications',
          source: 'Foreground push',
        );
      }
      if (_pendingForegroundPushNotification != null) {
        _showPendingForegroundPushNotification();
      }
    });
  }

  void _routePushNotificationSafely(
    GoRouter router,
    String route, {
    required String source,
  }) {
    final safeRoute = _safeLaunchRoute(route) ?? '/notifications';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      try {
        router.go(safeRoute);
        DevConsole.instance.info('$source routed: $safeRoute');
      } catch (error, stack) {
        DevConsole.instance.warn('$source route failed: $error');
        DevConsole.instance.warn(stack.toString());
        try {
          router.go('/notifications');
        } catch (fallbackError) {
          DevConsole.instance.warn(
            '$source fallback route failed: $fallbackError',
          );
        }
      }
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

  String? _safeLaunchRoute(String route) {
    return sanitizeAppRoute(route, fallback: null);
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
