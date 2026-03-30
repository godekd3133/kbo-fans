import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/widgets/dev_console.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AppConfig.initialize();
  DevConsole.instance.info('환경: ${AppConfig.instance.environment.name}');

  FlutterError.onError = (details) {
    DevConsole.instance.error('Flutter: ${details.exceptionAsString()}');
  };

  runZonedGuarded(() async {
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

class KboFansApp extends ConsumerWidget {
  const KboFansApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    final app = MaterialApp.router(
      title: 'KBO Fans',
      theme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: !AppConfig.instance.isRelease,
    );

    if (AppConfig.instance.isRelease) return app;
    return DevConsoleOverlay(child: app);
  }
}
