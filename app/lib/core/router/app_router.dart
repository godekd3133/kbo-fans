import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/onboarding/onboarding_screen.dart';
import '../../features/home/home_screen.dart';
import '../../data/models/game.dart';
import '../../features/game_detail/game_detail_screen.dart';
import '../../features/records/player_detail_screen.dart';
import '../../features/records/records_screen.dart';
import '../../features/schedule/schedule_screen.dart';
import '../../features/standings/standings_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/api_diagnostics_screen.dart';
import '../widgets/main_scaffold.dart';
import '../widgets/boot_splash_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

class OnboardingDoneNotifier extends Notifier<bool?> {
  @override
  bool? build() => null;

  void setValue(bool value) {
    state = value;
  }
}

/// 앱 초기 부트스트랩 중에는 null
final onboardingDoneProvider = NotifierProvider<OnboardingDoneNotifier, bool?>(
  OnboardingDoneNotifier.new,
);

final routerProvider = Provider<GoRouter>((ref) {
  final onboardingDone = ref.watch(onboardingDoneProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/boot',
    redirect: (context, state) {
      final location = state.uri.path;
      if (onboardingDone == null) {
        return location == '/boot' ? null : '/boot';
      }
      if (location == '/boot') {
        return onboardingDone ? '/home' : '/onboarding';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/boot',
        builder: (context, state) => const BootSplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: '/schedule',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ScheduleScreen()),
          ),
          GoRoute(
            path: '/standings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: StandingsScreen()),
          ),
          GoRoute(
            path: '/records',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: RecordsScreen()),
          ),
          GoRoute(
            path: '/records/team/:teamId',
            pageBuilder: (context, state) => NoTransitionPage(
              child: RecordsScreen(teamId: state.pathParameters['teamId']!),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/records/player/:playerId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => PlayerDetailScreen(
          playerId: state.pathParameters['playerId']!,
          season:
              int.tryParse(state.uri.queryParameters['season'] ?? '') ??
              DateTime.now().year,
        ),
      ),
      GoRoute(
        path: '/game/:gameId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => GameDetailScreen(
          gameId: state.pathParameters['gameId']!,
          game: state.extra as Game?,
        ),
      ),
      GoRoute(
        path: '/diagnostics',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ApiDiagnosticsScreen(),
      ),
    ],
  );
});
