import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';

class MainScaffold extends StatelessWidget {
  final Widget child;
  const MainScaffold({super.key, required this.child});

  static const _tabs = [
    (icon: Icons.calendar_month, label: '일정', path: '/schedule'),
    (icon: Icons.leaderboard, label: '순위', path: '/standings'),
    (icon: Icons.sports_baseball, label: '홈', path: '/home'),
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
            color: AppColors.background,
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
                    emphasized: i == 2,
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
  final bool emphasized;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.emphasized,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = selected ? AppColors.textPrimary : AppColors.textDisabled;
    final labelColor = selected
        ? AppColors.textPrimary
        : AppColors.textDisabled;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emphasized)
            Transform.translate(
              offset: Offset(0, selected ? -7 : -3),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: selected ? 68 : 60,
                height: selected ? 48 : 42,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.cardSub
                      : AppColors.card.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected ? AppColors.textPrimary : AppColors.divider,
                    width: selected ? 1.2 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: AppColors.background.withValues(alpha: 0.7),
                            blurRadius: 4,
                            spreadRadius: 0,
                            offset: const Offset(0, 2),
                          ),
                          BoxShadow(
                            color: AppColors.textPrimary.withValues(
                              alpha: 0.10,
                            ),
                            blurRadius: 18,
                            spreadRadius: 0,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: selected ? 28 : 24, color: iconColor),
              ),
            )
          else
            SizedBox(
              height: 42,
              child: Center(child: Icon(icon, size: 22, color: iconColor)),
            ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }
}
