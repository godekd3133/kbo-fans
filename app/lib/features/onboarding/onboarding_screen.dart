import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/team_data.dart';
import '../../core/router/app_route_sanitizer.dart';
import '../../core/router/onboarding_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_design_system.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../core/widgets/kbo_team_logo_image.dart';
import '../../data/providers.dart';
import '../settings/release_notes_prompt.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  final bool isEditMode;
  final String redirectTo;

  const OnboardingScreen({
    super.key,
    this.isEditMode = false,
    this.redirectTo = '/home',
  });

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  String? _selectedTeamId;
  bool _isSubmitting = false;

  String get _returnRoute =>
      sanitizeAppRoute(widget.redirectTo, fallback: '/home') ?? '/home';

  Future<void> _saveAndProceed({bool skipTeam = false}) async {
    if (_isSubmitting) {
      return;
    }
    final resolvedTeamId = skipTeam
        ? null
        : _selectedTeamId ?? ref.read(myTeamProvider);
    setState(() => _isSubmitting = true);
    try {
      // 마이팀을 전역 Provider에 저장
      await ref.read(myTeamProvider.notifier).setTeam(resolvedTeamId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboardingDone', true);
      if (!widget.isEditMode &&
          prefs.getString(releaseNotesSeenVersionPrefsKey) == null) {
        await prefs.setBool(releaseNotesFreshInstallPendingPrefsKey, true);
      }
      ref.read(onboardingDoneProvider.notifier).setValue(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('응원팀을 저장하지 못했어요. 다시 시도해 주세요.')),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    context.go(_returnRoute);
  }

  @override
  Widget build(BuildContext context) {
    final currentTeamId = ref.watch(myTeamProvider);
    final effectiveSelectedTeamId = _selectedTeamId ?? currentTeamId;
    final selectedTeam = effectiveSelectedTeamId != null
        ? KboTeams.byId(effectiveSelectedTeamId)
        : null;
    final mediaQuery = MediaQuery.of(context);
    final viewportWidth = mediaQuery.size.width;
    final textScaleFactor = mediaQuery.textScaler.scale(1);
    final usesLargeText = textScaleFactor >= 1.5;
    final usesCompactLayout = viewportWidth < 360 || usesLargeText;
    final contentMaxWidth = viewportWidth >= 900 ? 560.0 : 430.0;
    final crossAxisCount = viewportWidth >= 900
        ? (usesLargeText ? 2 : 3)
        : (usesCompactLayout ? 1 : 2);
    final teamCardHeight = usesLargeText
        ? 100.0 + (textScaleFactor * 36.0)
        : (viewportWidth >= 900 ? 88.0 : 74.0);
    final topSpacer = widget.isEditMode
        ? 10.0
        : (mediaQuery.padding.top > 0 ? 8.0 : 30.0);

    return Scaffold(
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.colorsOf(context).background,
          border: Border(
            top: BorderSide(color: AppTheme.colorsOf(context).divider),
          ),
        ),
        child: SafeArea(
          top: false,
          child: AppPageFrame(
            maxWidth: contentMaxWidth,
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _OnboardingPrimaryButton(
                  width: double.infinity,
                  height: 52,
                  accent: selectedTeam?.primaryColor ?? AppColors.accent,
                  enabled: effectiveSelectedTeamId != null,
                  isLoading: _isSubmitting,
                  label: _isSubmitting
                      ? (widget.isEditMode ? '저장 중입니다' : '시작 중입니다')
                      : (widget.isEditMode ? '선택 완료' : '시작하기'),
                  onTap: _saveAndProceed,
                ),
                AppPressable(
                  onTap: _isSubmitting
                      ? null
                      : widget.isEditMode
                      ? () => context.go(_returnRoute)
                      : () => _saveAndProceed(skipTeam: true),
                  pressedScale: 0.97,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        widget.isEditMode ? '취소' : '나중에 선택',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: AppPageFrame(
          maxWidth: contentMaxWidth,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: topSpacer),
                    if (widget.isEditMode)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Semantics(
                          key: const ValueKey('onboarding-edit-back'),
                          container: true,
                          excludeSemantics: true,
                          label: '뒤로',
                          button: true,
                          onTap: () => context.go(_returnRoute),
                          child: IconButton(
                            tooltip: '뒤로',
                            onPressed: () => context.go(_returnRoute),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        ),
                      ),
                    AppPageHeader(
                      title: widget.isEditMode ? '응원 팀을 선택하세요' : '어느 팀을 응원하세요?',
                      subtitle: '응원팀은 나중에 바꿀 수 있어요.',
                    ),
                    const SizedBox(height: 12),

                    GridView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        mainAxisExtent: teamCardHeight,
                      ),
                      itemCount: KboTeams.teams.length,
                      itemBuilder: (context, index) {
                        final team = KboTeams.teams[index];
                        final isSelected = effectiveSelectedTeamId == team.id;
                        return AppMotionListItem(
                          index: index,
                          beginYOffset: 10,
                          child: _OnboardingTeamCard(
                            team: team,
                            isSelected: isSelected,
                            onTap: _isSubmitting
                                ? null
                                : () =>
                                      setState(() => _selectedTeamId = team.id),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPrimaryButton extends StatelessWidget {
  final double width;
  final double height;
  final bool enabled;
  final Color accent;
  final bool isLoading;
  final String label;
  final VoidCallback onTap;

  const _OnboardingPrimaryButton({
    required this.width,
    required this.height,
    required this.enabled,
    required this.accent,
    required this.isLoading,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = AppTheme.colorsOf(context).readableForegroundOn(accent);
    return AppPressable(
      onTap: enabled && !isLoading ? onTap : null,
      pressedScale: 0.982,
      child: Container(
        width: width,
        constraints: BoxConstraints(minHeight: height),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? accent : AppColors.divider,
          borderRadius: BorderRadius.circular(8),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Row(
            key: ValueKey(label),
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: foreground,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    color: enabled ? foreground : AppColors.textDisabled,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingTeamCard extends StatelessWidget {
  final KboTeam team;
  final bool isSelected;
  final VoidCallback? onTap;

  const _OnboardingTeamCard({
    required this.team,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final accent = colors.readableAccent(team.primaryColor);
    final usesLargeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return AppPressable(
      semanticSelected: isSelected,
      onTap: onTap,
      pressedScale: 0.976,
      child: AnimatedContainer(
        duration: MediaQuery.of(context).disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? accent : AppColors.divider,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.16),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Row(
              children: [
                _TeamLogoCircle(
                  teamId: team.id,
                  fallback: team.shortName,
                  accent: accent,
                  size: 50,
                  logoSize: 39,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        team.shortName,
                        maxLines: usesLargeText ? null : 1,
                        overflow: usesLargeText
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w400,
                          height: 1.08,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        team.name,
                        maxLines: usesLargeText ? null : 1,
                        overflow: usesLargeText
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isSelected)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 20,
                    color: colors.readableForegroundOn(accent),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TeamLogoCircle extends StatelessWidget {
  final String? teamId;
  final String fallback;
  final Color accent;
  final double size;
  final double logoSize;

  const _TeamLogoCircle({
    required this.teamId,
    required this.fallback,
    required this.accent,
    required this.size,
    required this.logoSize,
  });

  @override
  Widget build(BuildContext context) {
    final onboardingAsset = _onboardingReferenceLogoAsset(teamId);
    if (onboardingAsset != null) {
      return SizedBox(
        width: size,
        height: size,
        child: ClipOval(
          child: Image.asset(
            onboardingAsset,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) => _fallbackLogo(),
          ),
        ),
      );
    }

    return _fallbackLogo();
  }

  Widget _fallbackLogo() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.background,
        shape: BoxShape.circle,
        border: Border.all(color: accent.withValues(alpha: 0.34), width: 2),
      ),
      alignment: Alignment.center,
      child: KboTeamLogoImage(
        teamId: teamId,
        fallback: fallback,
        size: logoSize,
        padding: 2,
      ),
    );
  }
}

String? _onboardingReferenceLogoAsset(String? teamId) {
  final normalized = (teamId ?? '').trim().toUpperCase();
  return switch (normalized) {
    'LG' ||
    'KT' ||
    'SK' ||
    'SS' ||
    'NC' ||
    'HH' ||
    'LT' ||
    'HT' ||
    'OB' ||
    'WO' => 'assets/visuals/onboarding_reference_team_logos/$normalized.png',
    _ => null,
  };
}
