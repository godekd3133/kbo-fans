import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import 'app_motion.dart';

class MainScaffold extends StatelessWidget {
  final Widget child;
  const MainScaffold({super.key, required this.child});

  static const _tabs = [
    (icon: Icons.home_rounded, label: '홈', path: '/home'),
    (icon: Icons.calendar_month, label: '일정', path: '/schedule'),
    (icon: Icons.leaderboard, label: '순위', path: '/standings'),
    (icon: Icons.groups_2, label: '기록실', path: '/records'),
    (icon: Icons.settings, label: '설정', path: '/settings'),
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final idx = _tabs.indexWhere((t) => location.startsWith(t.path));
    return idx >= 0 ? idx : 0;
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentIndex(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              for (int i = 0; i < _tabs.length; i++)
                Expanded(
                  child: _NavItem(
                    icon: _tabs[i].icon,
                    label: _tabs[i].label,
                    selected: current == i,
                    onTap: () => context.go(_tabs[i].path),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = selected ? AppColors.accent : AppColors.textDisabled;
    final labelColor = selected
        ? AppColors.textPrimary
        : AppColors.textDisabled;
    const animationDuration = Duration(milliseconds: 180);
    const animationCurve = Curves.easeOutCubic;

    return AppPressable(
      behavior: HitTestBehavior.opaque,
      pressedScale: 0.94,
      pressedOpacity: 0.9,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 34,
            child: Center(
              child: AnimatedScale(
                duration: animationDuration,
                curve: animationCurve,
                scale: selected ? 1.06 : 1,
                child: AnimatedContainer(
                  duration: animationDuration,
                  curve: animationCurve,
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.accent.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: selected ? AppColors.accent : AppColors.divider,
                      width: selected ? 2 : 1.4,
                    ),
                  ),
                  child: Icon(icon, size: 14, color: iconColor),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          AnimatedDefaultTextStyle(
            duration: animationDuration,
            curve: animationCurve,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: labelColor,
            ),
            child: Text(label),
          ),
        ],
      ),
    );
  }
}
