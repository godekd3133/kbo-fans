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
import '../../features/news/news_screen.dart';
import '../../features/notifications/notification_inbox_screen.dart';
import '../../features/standings/standings_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/api_diagnostics_screen.dart';
import '../../features/settings/patch_notes_screen.dart';
import 'app_route_sanitizer.dart';
import '../widgets/main_scaffold.dart';
import '../widgets/boot_splash_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();
int? _lastTabIndex;

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
  _lastTabIndex = null;

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
            pageBuilder: (context, state) => _tabTransitionPage(
              state,
              tabIndex: 0,
              child: const HomeScreen(),
            ),
          ),
          GoRoute(
            path: '/schedule',
            pageBuilder: (context, state) => _tabTransitionPage(
              state,
              tabIndex: 1,
              child: const ScheduleScreen(),
            ),
          ),
          GoRoute(
            path: '/news',
            pageBuilder: (context, state) => _tabTransitionPage(
              state,
              tabIndex: 3,
              child: const NewsScreen(),
            ),
          ),
          GoRoute(
            path: '/standings',
            pageBuilder: (context, state) => _tabTransitionPage(
              state,
              tabIndex: 3,
              child: const StandingsScreen(),
            ),
          ),
          GoRoute(
            path: '/records',
            pageBuilder: (context, state) => _tabTransitionPage(
              state,
              tabIndex: 2,
              child: const RecordsScreen(),
            ),
          ),
          GoRoute(
            path: '/records/team/:teamId',
            pageBuilder: (context, state) => _tabTransitionPage(
              state,
              tabIndex: 2,
              child: RecordsScreen(teamId: state.pathParameters['teamId']!),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => _tabTransitionPage(
              state,
              tabIndex: 4,
              child: const SettingsScreen(),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/records/player/:playerId',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _swipeBackPage(
          state,
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
        pageBuilder: (context, state) => _swipeBackPage(
          state,
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
        pageBuilder: (context, state) => _swipeBackPage(
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
            _swipeBackPage(state, child: const ApiDiagnosticsScreen()),
      ),
      GoRoute(
        path: '/patch-notes',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            _swipeBackPage(state, child: const PatchNotesScreen()),
      ),
      GoRoute(
        path: '/notifications',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            _swipeBackPage(state, child: const NotificationInboxScreen()),
      ),
    ],
  );
  ref.onDispose(() {
    _lastTabIndex = null;
    router.dispose();
  });
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
  return sanitizeAppRoute(target, fallback: '/home') ?? '/home';
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
  required int tabIndex,
  required Widget child,
}) {
  final slideDirection = _consumeTabSlideDirection(tabIndex);
  final incomingOffset = Offset(0.052 * slideDirection, 0);
  final outgoingOffset = Offset(-0.016 * slideDirection, 0);

  return _animatedPage(
    state,
    child: child,
    beginOffset: incomingOffset,
    beginOpacity: 0.88,
    beginScale: 0.994,
    outgoingOffset: outgoingOffset,
    outgoingOpacity: 0.97,
    outgoingScale: 0.998,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 280),
  );
}

int _consumeTabSlideDirection(int nextIndex) {
  final previousIndex = _lastTabIndex;
  _lastTabIndex = nextIndex;
  if (previousIndex == null || previousIndex == nextIndex) {
    return 1;
  }
  return nextIndex > previousIndex ? 1 : -1;
}

CupertinoPage<void> _swipeBackPage(
  GoRouterState state, {
  required Widget child,
}) {
  return CupertinoPage<void>(
    key: state.pageKey,
    name: state.uri.toString(),
    child: child,
  );
}

CustomTransitionPage<void> _animatedPage(
  GoRouterState state, {
  required Widget child,
  required Offset beginOffset,
  double beginOpacity = 0.88,
  double beginScale = 1,
  Offset outgoingOffset = Offset.zero,
  double outgoingOpacity = 1,
  double outgoingScale = 1,
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
        curve: Curves.easeOutQuart,
        reverseCurve: Curves.easeInOutCubic,
      );
      final curvedSecondaryAnimation = CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInOutCubic,
      );
      final fadeAnimation = Tween<double>(
        begin: beginOffset == Offset.zero ? 0.92 : beginOpacity,
        end: 1,
      ).animate(curvedAnimation);
      final slideAnimation = Tween<Offset>(
        begin: beginOffset,
        end: Offset.zero,
      ).animate(curvedAnimation);
      final scaleAnimation = Tween<double>(
        begin: beginScale,
        end: 1,
      ).animate(curvedAnimation);
      final outgoingFadeAnimation = Tween<double>(
        begin: 1,
        end: outgoingOpacity,
      ).animate(curvedSecondaryAnimation);
      final outgoingSlideAnimation = Tween<Offset>(
        begin: Offset.zero,
        end: outgoingOffset,
      ).animate(curvedSecondaryAnimation);
      final outgoingScaleAnimation = Tween<double>(
        begin: 1,
        end: outgoingScale,
      ).animate(curvedSecondaryAnimation);

      return FadeTransition(
        opacity: outgoingFadeAnimation,
        child: SlideTransition(
          position: outgoingSlideAnimation,
          child: ScaleTransition(
            scale: outgoingScaleAnimation,
            child: FadeTransition(
              opacity: fadeAnimation,
              child: SlideTransition(
                position: slideAnimation,
                child: ScaleTransition(scale: scaleAnimation, child: child),
              ),
            ),
          ),
        ),
      );
    },
  );
}
