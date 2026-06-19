import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../bootstrap/startup_prep_state.dart';
import '../constants/visual_assets.dart';
import '../theme/app_theme.dart';
import 'app_artwork_card.dart';

class BootSplashScreen extends ConsumerWidget {
  final String redirectTo;

  const BootSplashScreen({super.key, this.redirectTo = '/home'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prep = ref.watch(startupPrepProvider);
    if (!prep.blocking) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.go(redirectTo);
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.divider),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x24000000),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppArtworkCard(
                    assetName: VisualAssets.liveRelayField,
                    height: 86,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    prep.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    prep.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Align(
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AppColors.live,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: AppColors.cardSub,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: visualProgress ?? 1,
                        child: Container(
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.live,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
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
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
