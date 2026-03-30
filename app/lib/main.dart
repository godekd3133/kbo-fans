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

  // 환경 초기화 (--dart-define=APP_ENV=local|dev|release)
  AppConfig.initialize();
  DevConsole.instance.info('환경: ${AppConfig.instance.environment.name}');
  DevConsole.instance.info('API: ${AppConfig.instance.apiBaseUrl}');

  // 전역 에러 핸들링 → DevConsole에 로그
  FlutterError.onError = (details) {
    DevConsole.instance.error('Flutter: ${details.exceptionAsString()}');
  };

  runZonedGuarded(() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboardingDone') ?? false;

    runApp(
      ProviderScope(
        child: KboFansApp(showOnboarding: !onboardingDone),
      ),
    );
  }, (error, stack) {
    DevConsole.instance.error('$error');
  });
}

class KboFansApp extends ConsumerWidget {
  final bool showOnboarding;
  const KboFansApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    if (showOnboarding) {
      router.go('/onboarding');
    }

    final app = MaterialApp.router(
      title: 'KBO Fans',
      theme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: !AppConfig.instance.isRelease,
    );

    // RELEASE가 아닌 환경에서 DevConsole 오버레이 표시
    if (AppConfig.instance.isRelease) return app;
    return DevConsoleOverlay(child: app);
  }
}
