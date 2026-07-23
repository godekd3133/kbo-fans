import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import 'app_motion.dart';

class MainScaffold extends StatelessWidget {
  final Widget child;
  const MainScaffold({super.key, required this.child});

  static const _mobileDestinations = [
    (icon: Icons.home_rounded, label: '홈', path: '/home'),
    (icon: Icons.sports_baseball_rounded, label: '일정', path: '/schedule'),
    (icon: Icons.bar_chart_rounded, label: '기록', path: '/records'),
    (icon: Icons.article_outlined, label: '브리핑', path: '/news'),
    (icon: Icons.settings_rounded, label: '설정', path: '/settings'),
  ];

  static const _wideDestinations = [
    (icon: Icons.home_rounded, label: '홈', path: '/home'),
    (icon: Icons.sports_baseball_rounded, label: '일정', path: '/schedule'),
    (icon: Icons.leaderboard_rounded, label: '순위', path: '/standings'),
    (icon: Icons.bar_chart_rounded, label: '기록', path: '/records'),
    (icon: Icons.article_outlined, label: '브리핑', path: '/news'),
    (icon: Icons.settings_rounded, label: '설정', path: '/settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final useNavigationRail = viewportWidth >= 700;
    final useExtendedRail = viewportWidth >= 1000;
    final colors = AppTheme.colorsOf(context);

    if (useNavigationRail) {
      final current = _wideNavigationIndex(location);
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              right: false,
              child: NavigationRail(
                extended: useExtendedRail,
                scrollable: true,
                minExtendedWidth: 200,
                labelType: useExtendedRail
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                groupAlignment: -1,
                backgroundColor: colors.background.withValues(alpha: 0.98),
                indicatorColor: colors.live.withValues(alpha: 0.18),
                selectedIconTheme: IconThemeData(color: colors.live, size: 24),
                unselectedIconTheme: IconThemeData(
                  color: colors.textSecondary,
                  size: 23,
                ),
                selectedLabelTextStyle: TextStyle(
                  color: colors.live,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
                unselectedLabelTextStyle: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                selectedIndex: current < 0 ? null : current,
                onDestinationSelected: (index) =>
                    context.go(_wideDestinations[index].path),
                destinations: [
                  for (final destination in _wideDestinations)
                    NavigationRailDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.icon),
                      label: Text(destination.label),
                    ),
                ],
              ),
            ),
            VerticalDivider(width: 1, thickness: 1, color: colors.divider),
            Expanded(child: child),
          ],
        ),
      );
    }

    final current = mainNavigationIndexForLocation(location);
    return Scaffold(
      body: child,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(
            color: colors.background.withValues(alpha: 0.98),
            border: Border(top: BorderSide(color: colors.divider)),
            boxShadow: [
              BoxShadow(
                color: colors.navShadow,
                blurRadius: 18,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  for (int i = 0; i < _mobileDestinations.length; i++)
                    Expanded(
                      child: _NavItem(
                        icon: _mobileDestinations[i].icon,
                        label: _mobileDestinations[i].label,
                        selected: current == i,
                        onTap: () => context.go(_mobileDestinations[i].path),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                width: 128,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textPrimary,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

int mainNavigationIndexForLocation(String location) {
  if (location.startsWith('/home')) {
    return 0;
  }
  if (location.startsWith('/schedule')) {
    return 1;
  }
  if (location == '/standings' || location.startsWith('/records')) {
    return 2;
  }
  if (location.startsWith('/news')) {
    return 3;
  }
  if (location.startsWith('/settings')) {
    return 4;
  }
  return -1;
}

int _wideNavigationIndex(String location) {
  if (location.startsWith('/home')) {
    return 0;
  }
  if (location.startsWith('/schedule')) {
    return 1;
  }
  if (location == '/standings') {
    return 2;
  }
  if (location.startsWith('/records')) {
    return 3;
  }
  if (location.startsWith('/news')) {
    return 4;
  }
  if (location.startsWith('/settings')) {
    return 5;
  }
  return -1;
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final iconColor = selected ? colors.live : colors.textSecondary;
    final labelColor = selected ? colors.live : colors.textSecondary;
    final animationDuration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 180);
    const animationCurve = Curves.easeOutCubic;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: AppPressable(
        behavior: HitTestBehavior.opaque,
        pressedScale: 0.94,
        pressedOpacity: 0.9,
        semanticSelected: selected,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 28,
              child: Center(
                child: AnimatedScale(
                  duration: animationDuration,
                  curve: animationCurve,
                  scale: selected ? 1.04 : 1,
                  child: Icon(icon, size: 23, color: iconColor),
                ),
              ),
            ),
            const SizedBox(height: 1),
            AnimatedDefaultTextStyle(
              duration: animationDuration,
              curve: animationCurve,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: labelColor,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
