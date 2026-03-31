import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/widgets/dev_console.dart';
import 'data/providers.dart';
import 'services/game_event_alert_service.dart';
import 'services/push_notification_service.dart';
import 'services/ticket_alert_service.dart';
import 'services/widget_sync_service.dart';
import 'package:workmanager/workmanager.dart';

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      AppConfig.initialize();
      DevConsole.instance.info('환경: ${AppConfig.instance.environment.name}');

      FlutterError.onError = (details) {
        DevConsole.instance.error('Flutter: ${details.exceptionAsString()}');
      };

      runApp(const ProviderScope(child: KboFansApp()));

      unawaited(_initializePlatformServices());
    },
    (error, stack) {
      DevConsole.instance.error('$error');
    },
  );
}

Future<void> _initializePlatformServices() async {
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
    final prefs = await SharedPreferences.getInstance();
    await PushNotificationService.instance.initialize(
      myTeam: prefs.getString('myTeam'),
    );
  } catch (error) {
    DevConsole.instance.error('Push init failed: $error');
  }

  if (kIsWeb) {
    return;
  }

  try {
    await Workmanager().initialize(widgetCallbackDispatcher);
    await WidgetSyncService.instance.registerBackgroundRefresh();
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    Future.microtask(_bootstrapApp);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  Future<void> _bootstrapApp() async {
    try {
      await _loadOnboardingState().timeout(const Duration(seconds: 3));
    } catch (error) {
      DevConsole.instance.warn('onboarding bootstrap fallback: $error');
      ref.read(onboardingDoneProvider.notifier).setValue(false);
    }

    try {
      await ref
          .read(myTeamProvider.notifier)
          .load()
          .timeout(const Duration(seconds: 3));
    } catch (error) {
      DevConsole.instance.warn('myTeam bootstrap fallback: $error');
    }

    _prefetchInitialData();
  }

  Future<void> _loadOnboardingState() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboardingDone') ?? false;
    ref.read(onboardingDoneProvider.notifier).setValue(onboardingDone);
  }

  void _prefetchInitialData() {
    if (_shouldSkipInitialPrefetch()) {
      return;
    }

    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final yearMonth =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final season = now.year;

    _warm(ref.read(scoreboardProvider(today).future));
    _warm(ref.read(scheduleProvider(yearMonth).future));
    _warm(ref.read(standingsProvider(season).future));
    _warm(ref.read(recordsOverviewProvider(season).future));

    final myTeamId = ref.read(myTeamProvider);
    if (myTeamId != null && myTeamId.isNotEmpty) {
      _warm(ref.read(teamRecordsProvider('$myTeamId|$season').future));
    }
  }

  void _warm<T>(Future<T> future) {
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {},
      ),
    );
  }

  bool _shouldSkipInitialPrefetch() {
    if (_isWidgetTestBinding()) {
      return true;
    }
    return AppConfig.instance.isLocal;
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
    final scoreboardAsync = ref.watch(scoreboardProvider(today));

    scoreboardAsync.whenData((games) {
      unawaited(
        WidgetSyncService.instance.syncScoreboard(
          games: games,
          myTeamId: myTeamId,
        ),
      );
    });

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

  late final WidgetsBindingObserver _lifecycleObserver = _AppLifecycleObserver(
    onResumed: () {
      ref.invalidate(scoreboardProvider(_todayKey()));
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
