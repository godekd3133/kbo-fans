import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 환경 초기화 (--dart-define=APP_ENV=local|dev|release)
  AppConfig.initialize();

  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool('onboardingDone') ?? false;

  runApp(
    ProviderScope(
      child: KboFansApp(showOnboarding: !onboardingDone),
    ),
  );
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

    return MaterialApp.router(
      title: 'KBO Fans',
      theme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: !AppConfig.instance.isRelease,
    );
  }
}
