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
    Future.microtask(() async {
      await _loadOnboardingState();
      await ref.read(myTeamProvider.notifier).load();
      _prefetchInitialData();
    });
  }

  Future<void> _loadOnboardingState() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboardingDone') ?? false;
    ref.read(onboardingDoneProvider.notifier).setValue(onboardingDone);
  }

  void _prefetchInitialData() {
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

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

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
}
