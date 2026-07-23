import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/team_data.dart';
import '../../core/router/app_route_sanitizer.dart';
import '../../core/router/onboarding_state.dart';
import '../../core/theme/app_theme.dart';
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

  Future<void> _saveAndProceed() async {
    if (_isSubmitting) {
      return;
    }
    final resolvedTeamId = _selectedTeamId ?? ref.read(myTeamProvider);
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
        const SnackBar(content: Text('시작 준비에 실패했습니다. 다시 시도해주세요.')),
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
        ? 104.0
        : (viewportWidth >= 900 ? 88.0 : 74.0);
    final topSpacer = widget.isEditMode
        ? 10.0
        : (mediaQuery.padding.top > 0 ? 8.0 : 30.0);

    return Scaffold(
      body: SafeArea(
        child: AppPageFrame(
          maxWidth: contentMaxWidth,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    SizedBox(height: topSpacer),
                    if (widget.isEditMode)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          onPressed: () => context.go(_returnRoute),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                    Text(
                      'KBO Fans',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                            height: 1.06,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '응원 팀을 선택하세요',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SelectedTeamPreview(team: selectedTeam),
                    const SizedBox(height: 10),
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
                    _OnboardingPrimaryButton(
                      width: double.infinity,
                      height: 52,
                      enabled: effectiveSelectedTeamId != null,
                      isLoading: _isSubmitting,
                      label: _isSubmitting
                          ? (widget.isEditMode ? '저장 중입니다' : '시작 중입니다')
                          : (widget.isEditMode ? '선택 완료' : '시작하기'),
                      onTap: _saveAndProceed,
                    ),
                    const SizedBox(height: 14),
                    AppPressable(
                      onTap: _isSubmitting
                          ? null
                          : widget.isEditMode
                          ? () => context.go(_returnRoute)
                          : _saveAndProceed,
                      pressedScale: 0.97,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Center(
                            child: Text(
                              widget.isEditMode ? '취소' : '나중에 선택',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
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

class _SelectedTeamPreview extends StatelessWidget {
  final KboTeam? team;

  const _SelectedTeamPreview({required this.team});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final accent = colors.readableAccent(team?.primaryColor ?? colors.live);
    final title = team?.name ?? '마이팀 미리보기';
    final logoTeamId = team?.id;
    final fallback = team?.shortName ?? 'KBO';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: AppColors.background.withValues(alpha: 0.32),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MY TEAM',
            style: TextStyle(
              fontSize: 11,
              color: accent,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _TeamLogoCircle(
                teamId: logoTeamId,
                fallback: fallback,
                accent: accent,
                size: 58,
                logoSize: 45,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 8.0;
              final columns = constraints.maxWidth >= 350 ? 3 : 2;
              final width =
                  (constraints.maxWidth - (gap * (columns - 1))) / columns;
              const benefits = [
                _PreviewBenefit(
                  icon: Icons.emoji_events_outlined,
                  title: '경기 우선',
                  subtitle: '홈에서 먼저 보기',
                ),
                _PreviewBenefit(
                  icon: Icons.notifications_none_rounded,
                  title: '득점 알림',
                  subtitle: '실시간 알림 받기',
                ),
                _PreviewBenefit(
                  icon: Icons.bar_chart_rounded,
                  title: '순위 추적',
                  subtitle: '팀 순위 확인',
                ),
              ];
              return Wrap(
                spacing: gap,
                runSpacing: 7,
                children: [
                  for (final benefit in benefits)
                    SizedBox(width: width, child: benefit),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PreviewBenefit extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _PreviewBenefit({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 42),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardSub.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.textPrimary),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPrimaryButton extends StatelessWidget {
  final double width;
  final double height;
  final bool enabled;
  final bool isLoading;
  final String label;
  final VoidCallback onTap;

  const _OnboardingPrimaryButton({
    required this.width,
    required this.height,
    required this.enabled,
    required this.isLoading,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: enabled && !isLoading ? onTap : null,
      pressedScale: 0.982,
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xFFFF1F2F), Color(0xFFE90023)],
                )
              : null,
          color: enabled ? null : AppColors.divider,
          borderRadius: BorderRadius.circular(8),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.live.withValues(alpha: 0.18),
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
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  color: enabled
                      ? AppColors.textPrimary
                      : AppColors.textDisabled,
                  fontWeight: FontWeight.w900,
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
    return Semantics(
      selected: isSelected,
      child: AppPressable(
        onTap: onTap,
        pressedScale: 0.976,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.live : AppColors.divider,
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.live.withValues(alpha: 0.16),
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w900,
                            height: 1.08,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          team.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
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
                      color: AppColors.live,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 20,
                      color: AppColors.textPrimary,
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
          ),
        ),
      );
    }

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
