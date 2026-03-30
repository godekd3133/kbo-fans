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
import 'services/ticket_alert_service.dart';
import 'services/widget_sync_service.dart';
import 'package:workmanager/workmanager.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    AppConfig.initialize();
    DevConsole.instance.info('환경: ${AppConfig.instance.environment.name}');
    await TicketAlertService.instance.initialize();
    await WidgetSyncService.instance.initialize();
    if (!kIsWeb) {
      await Workmanager().initialize(widgetCallbackDispatcher);
      await WidgetSyncService.instance.registerBackgroundRefresh();
    }

    FlutterError.onError = (details) {
      DevConsole.instance.error('Flutter: ${details.exceptionAsString()}');
    };

    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboardingDone') ?? false;

    runApp(
      ProviderScope(
        overrides: [
          onboardingDoneProvider.overrideWithValue(onboardingDone),
        ],
        child: const KboFansApp(),
      ),
    );
  }, (error, stack) {
    DevConsole.instance.error('$error');
  });
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
      await ref.read(myTeamProvider.notifier).load();
      _prefetchInitialData();
    });
  }

  void _prefetchInitialData() {
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final yearMonth =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final season = now.year;

    unawaited(ref.read(scoreboardProvider(today).future));
    unawaited(ref.read(scheduleProvider(yearMonth).future));
    unawaited(ref.read(standingsProvider(season).future));
    unawaited(ref.read(recordsOverviewProvider(season).future));

    final myTeamId = ref.read(myTeamProvider);
    if (myTeamId != null && myTeamId.isNotEmpty) {
      unawaited(ref.read(teamRecordsProvider('$myTeamId|$season').future));
    }
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

        return DevConsoleOverlay(
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
