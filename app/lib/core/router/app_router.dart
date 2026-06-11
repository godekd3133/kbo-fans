import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/onboarding/onboarding_screen.dart';
import '../../features/home/home_screen.dart';
import '../../data/models/game.dart';
import '../../data/models/records_overview.dart';
import '../../features/game_detail/game_detail_screen.dart';
import '../../features/records/leaderboard_screen.dart';
import '../../features/records/player_detail_screen.dart';
import '../../features/records/records_screen.dart';
import '../../features/schedule/schedule_screen.dart';
import '../../features/standings/standings_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/api_diagnostics_screen.dart';
import '../../features/settings/patch_notes_screen.dart';
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

final _onboardingDoneRefreshProvider = Provider<ValueNotifier<bool?>>((ref) {
  final notifier = ValueNotifier<bool?>(ref.read(onboardingDoneProvider));
  ref.listen<bool?>(onboardingDoneProvider, (_, next) {
    notifier.value = next;
  });
  ref.onDispose(notifier.dispose);
  return notifier;
});

final routerProvider = Provider<GoRouter>((ref) {
  final onboardingDoneRefresh = ref.watch(_onboardingDoneRefreshProvider);

  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    refreshListenable: onboardingDoneRefresh,
    redirect: (context, state) {
      final onboardingDone = onboardingDoneRefresh.value;
      final location = state.uri.path;
      final hashLocation = _hashLocation(state.uri);
      if (hashLocation != null) {
        return hashLocation;
      }
      final isOnboardingEdit =
          location == '/onboarding' &&
          state.uri.queryParameters['mode'] == 'edit';
      final redirectTarget = _redirectTarget(state);
      if (onboardingDone == null) {
        return location == '/boot'
            ? null
            : Uri(
                path: '/boot',
                queryParameters: {'redirect': redirectTarget},
              ).toString();
      }
      if (!onboardingDone) {
        return location == '/onboarding'
            ? null
            : Uri(
                path: '/onboarding',
                queryParameters: {'redirect': redirectTarget},
              ).toString();
      }
      if (location == '/boot') {
        return _safeRedirectPath(state.uri.queryParameters['redirect']);
      }
      if (location == '/onboarding' && !isOnboardingEdit) {
        return _safeRedirectPath(state.uri.queryParameters['redirect']);
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/boot'),
      GoRoute(
        path: '/boot',
        pageBuilder: (context, state) => _fadeTransitionPage(
          state,
          child: BootSplashScreen(
            redirectTo: _safeRedirectPath(
              state.uri.queryParameters['redirect'],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => _fadeTransitionPage(
          state,
          child: OnboardingScreen(
            isEditMode: state.uri.queryParameters['mode'] == 'edit',
            redirectTo: _safeRedirectPath(
              state.uri.queryParameters['redirect'],
            ),
          ),
        ),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) =>
                _tabTransitionPage(state, child: const HomeScreen()),
          ),
          GoRoute(
            path: '/schedule',
            pageBuilder: (context, state) =>
                _tabTransitionPage(state, child: const ScheduleScreen()),
          ),
          GoRoute(
            path: '/standings',
            pageBuilder: (context, state) =>
                _tabTransitionPage(state, child: const StandingsScreen()),
          ),
          GoRoute(
            path: '/records',
            pageBuilder: (context, state) =>
                _tabTransitionPage(state, child: const RecordsScreen()),
          ),
          GoRoute(
            path: '/records/team/:teamId',
            pageBuilder: (context, state) => _tabTransitionPage(
              state,
              child: RecordsScreen(teamId: state.pathParameters['teamId']!),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                _tabTransitionPage(state, child: const SettingsScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/records/player/:playerId',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => CupertinoPage(
          key: state.pageKey,
          child: PlayerDetailScreen(
            playerId: state.pathParameters['playerId']!,
            season:
                int.tryParse(state.uri.queryParameters['season'] ?? '') ??
                DateTime.now().year,
          ),
        ),
      ),
      GoRoute(
        path: '/records/leaderboard/:metric',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => CupertinoPage(
          key: state.pageKey,
          child: LeaderboardScreen(
            metric:
                LeaderboardMetricX.fromKey(
                  state.pathParameters['metric'] ?? '',
                ) ??
                LeaderboardMetric.avg,
            season:
                int.tryParse(state.uri.queryParameters['season'] ?? '') ??
                DateTime.now().year,
          ),
        ),
      ),
      GoRoute(
        path: '/game/:gameId',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _drillInTransitionPage(
          state,
          child: GameDetailScreen(
            gameId: state.pathParameters['gameId']!,
            game: state.extra as Game?,
            initialTab: state.uri.queryParameters['tab'],
            focusRelay: state.uri.queryParameters['focus'] == 'relay',
          ),
        ),
      ),
      GoRoute(
        path: '/diagnostics',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            _drillInTransitionPage(state, child: const ApiDiagnosticsScreen()),
      ),
      GoRoute(
        path: '/patch-notes',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            _drillInTransitionPage(state, child: const PatchNotesScreen()),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

String _redirectTarget(GoRouterState state) {
  final target = state.uri.toString();
  return _safeRedirectPath(target);
}

String? _hashLocation(Uri uri) {
  if (uri.path != '/' || uri.fragment.isEmpty) {
    return null;
  }
  final fragment = uri.fragment;
  return fragment.startsWith('/') ? _safeRedirectPath(fragment) : null;
}

String _safeRedirectPath(String? target) {
  if (target == null ||
      target.isEmpty ||
      !target.startsWith('/') ||
      target.startsWith('//')) {
    return '/home';
  }
  final uri = Uri.tryParse(target);
  if (uri == null) {
    return '/home';
  }
  if (uri.hasScheme || uri.host.isNotEmpty) {
    return '/home';
  }
  if (uri.path == '/' || uri.path == '/boot' || uri.path == '/onboarding') {
    return '/home';
  }
  return uri.toString();
}

CustomTransitionPage<void> _fadeTransitionPage(
  GoRouterState state, {
  required Widget child,
}) {
  return _animatedPage(
    state,
    child: child,
    beginOffset: Offset.zero,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 140),
  );
}

CustomTransitionPage<void> _tabTransitionPage(
  GoRouterState state, {
  required Widget child,
}) {
  return _animatedPage(
    state,
    child: child,
    beginOffset: const Offset(0.03, 0),
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 170),
  );
}

CustomTransitionPage<void> _drillInTransitionPage(
  GoRouterState state, {
  required Widget child,
}) {
  return _animatedPage(
    state,
    child: child,
    beginOffset: const Offset(0.08, 0),
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
  );
}

CustomTransitionPage<void> _animatedPage(
  GoRouterState state, {
  required Widget child,
  required Offset beginOffset,
  required Duration transitionDuration,
  required Duration reverseTransitionDuration,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: transitionDuration,
    reverseTransitionDuration: reverseTransitionDuration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.of(context).disableAnimations) {
        return child;
      }

      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final fadeAnimation = Tween<double>(
        begin: beginOffset == Offset.zero ? 0.92 : 0.88,
        end: 1,
      ).animate(curvedAnimation);
      final slideAnimation = Tween<Offset>(
        begin: beginOffset,
        end: Offset.zero,
      ).animate(curvedAnimation);

      return FadeTransition(
        opacity: fadeAnimation,
        child: SlideTransition(position: slideAnimation, child: child),
      );
    },
  );
}
