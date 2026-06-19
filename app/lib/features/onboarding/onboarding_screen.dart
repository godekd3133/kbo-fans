import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/team_data.dart';
import '../../core/constants/visual_assets.dart';
import '../../core/router/app_route_sanitizer.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_artwork_card.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../core/widgets/kbo_team_logo_image.dart';
import '../../data/providers.dart';

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

  Future<void> _saveAndProceed() async {
    final resolvedTeamId = _selectedTeamId ?? ref.read(myTeamProvider);
    // 마이팀을 전역 Provider에 저장
    await ref.read(myTeamProvider.notifier).setTeam(resolvedTeamId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboardingDone', true);
    ref.read(onboardingDoneProvider.notifier).setValue(true);
    if (!mounted) {
      return;
    }
    if (widget.isEditMode) {
      context.go('/settings');
    } else {
      context.go(
        sanitizeAppRoute(widget.redirectTo, fallback: '/home') ?? '/home',
      );
    }
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
    final contentMaxWidth = viewportWidth >= 900 ? 560.0 : 430.0;
    final crossAxisCount = viewportWidth >= 900 ? 3 : 2;
    final teamCardAspectRatio = viewportWidth >= 900 ? 2.05 : 2.35;
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
                          onPressed: () => context.go('/settings'),
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
                    const Text(
                      '응원 팀을 선택하세요',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppArtworkCard(
                      assetName: VisualAssets.onboardingStadiumHero,
                      height: viewportWidth >= 900 ? 176 : 108,
                      alignment: Alignment.center,
                    ),
                    const SizedBox(height: 10),
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
                        childAspectRatio: teamCardAspectRatio,
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
                            onTap: () =>
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
                      label: widget.isEditMode ? '선택 완료' : '시작하기',
                      onTap: _saveAndProceed,
                    ),
                    const SizedBox(height: 14),
                    AppPressable(
                      onTap: widget.isEditMode
                          ? () => context.go('/settings')
                          : _saveAndProceed,
                      pressedScale: 0.97,
                      child: Text(
                        widget.isEditMode ? '취소' : '나중에 선택',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textDisabled,
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
    final accent = team?.primaryColor ?? AppColors.live;
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
              color: accent == Colors.black ? AppColors.live : accent,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        height: 1.08,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: const [
                        Expanded(
                          child: _PreviewBenefit(
                            icon: Icons.emoji_events_outlined,
                            title: '경기 우선',
                            subtitle: '홈에서 먼저 보기',
                          ),
                        ),
                        _PreviewDivider(),
                        Expanded(
                          child: _PreviewBenefit(
                            icon: Icons.notifications_none_rounded,
                            title: '득점 알림',
                            subtitle: '실시간 알림 받기',
                          ),
                        ),
                        _PreviewDivider(),
                        Expanded(
                          child: _PreviewBenefit(
                            icon: Icons.bar_chart_rounded,
                            title: '순위 추적',
                            subtitle: '팀 순위 확인',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
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
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: AppColors.cardSub,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 15, color: AppColors.textPrimary),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  subtitle,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 8,
                    color: AppColors.textDisabled,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewDivider extends StatelessWidget {
  const _PreviewDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 26,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      color: AppColors.divider,
    );
  }
}

class _OnboardingPrimaryButton extends StatelessWidget {
  final double width;
  final double height;
  final bool enabled;
  final String label;
  final VoidCallback onTap;

  const _OnboardingPrimaryButton({
    required this.width,
    required this.height,
    required this.enabled,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: enabled ? onTap : null,
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
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            color: enabled ? AppColors.textPrimary : AppColors.textDisabled,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _OnboardingTeamCard extends StatelessWidget {
  final KboTeam team;
  final bool isSelected;
  final VoidCallback onTap;

  const _OnboardingTeamCard({
    required this.team,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = team.primaryColor == Colors.black
        ? AppColors.textPrimary
        : team.primaryColor;
    return AppPressable(
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
                        style: const TextStyle(
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
                        style: const TextStyle(
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
                  decoration: const BoxDecoration(
                    color: AppColors.live,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 20,
                    color: AppColors.textPrimary,
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
