import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../bootstrap/startup_prep_state.dart';
import '../router/app_route_sanitizer.dart';
import '../theme/app_theme.dart';

class BootSplashScreen extends ConsumerWidget {
  final String redirectTo;

  const BootSplashScreen({super.key, this.redirectTo = '/home'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prep = ref.watch(startupPrepProvider);
    if (!prep.blocking) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.go(
            sanitizeAppRoute(redirectTo, fallback: '/home') ?? '/home',
          );
        }
      });
    }
    final visualProgress = prep.blocking
        ? (prep.progress <= 0 ? 0.08 : prep.progress.clamp(0.08, 1.0))
        : null;
    final progressLabel = prep.blocking
        ? '${(visualProgress! * 100).round()}%'
        : 'READY';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Image.asset(
                'assets/branding/app_icon_source_1024.png',
                width: 112,
                height: 112,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(height: 22),
              Image.asset(
                'assets/visuals/kbo_header_logo.png',
                width: 142,
                height: 54,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                semanticLabel: prep.title,
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 42,
                child: Text(
                  prep.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 228,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.cardSub,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: visualProgress ?? 1,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppColors.live,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 228,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      prep.blocking
                          ? '${prep.completedSteps}/${prep.totalSteps} 단계'
                          : '곧 시작합니다',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textDisabled,
                      ),
                    ),
                    Text(
                      progressLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 4),
            ],
          ),
        ),
      ),
    );
  }
}
