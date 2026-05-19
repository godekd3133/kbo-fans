import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/team_data.dart';
import '../../core/router/app_router.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../data/providers.dart';
import '../../core/theme/app_theme.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  final bool isEditMode;

  const OnboardingScreen({super.key, this.isEditMode = false});

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
    context.go(widget.isEditMode ? '/settings' : '/home');
  }

  @override
  Widget build(BuildContext context) {
    final currentTeamId = ref.watch(myTeamProvider);
    final effectiveSelectedTeamId = _selectedTeamId ?? currentTeamId;
    final selectedTeam = effectiveSelectedTeamId != null
        ? KboTeams.byId(effectiveSelectedTeamId)
        : null;
    final viewportWidth = MediaQuery.of(context).size.width;
    final contentMaxWidth = viewportWidth >= 900 ? 560.0 : 460.0;
    final crossAxisCount = viewportWidth >= 900 ? 3 : 2;
    final logoSize = viewportWidth >= 900 ? 72.0 : 84.0;

    return Scaffold(
      body: SafeArea(
        child: AppPageFrame(
          maxWidth: contentMaxWidth,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 32),
              if (widget.isEditMode)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => context.go('/settings'),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
              Text(
                'KBO Fans',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '응원 팀을 선택하세요',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '선택하면 홈에서 마이팀 경기, 최근 흐름, 순위를 먼저 보여줍니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textDisabled),
              ),
              const SizedBox(height: 10),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _OnboardingHintChip(label: '오늘 경기 우선'),
                  _OnboardingHintChip(label: '예매 오픈 추적'),
                  _OnboardingHintChip(label: '마이팀 중심 홈'),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: viewportWidth >= 900 ? 0.9 : 0.95,
                  ),
                  itemCount: KboTeams.teams.length,
                  itemBuilder: (context, index) {
                    final team = KboTeams.teams[index];
                    final isSelected = effectiveSelectedTeamId == team.id;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedTeamId = team.id),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? team.primaryColor
                                : AppColors.divider,
                            width: isSelected ? 2 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: team.primaryColor.withValues(
                                      alpha: 0.18,
                                    ),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ]
                              : null,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: logoSize,
                              height: logoSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.background,
                                border: Border.all(
                                  color: isSelected
                                      ? team.primaryColor
                                      : AppColors.divider,
                                  width: 3,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: CachedNetworkImage(
                                  imageUrl: team.logoUrl,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                  placeholder: (_, _) =>
                                      Container(color: AppColors.cardSub),
                                  errorWidget: (_, _, _) => Container(
                                    color: AppColors.cardSub,
                                    child: Center(
                                      child: Text(
                                        team.shortName,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              team.shortName,
                              style: TextStyle(
                                fontSize: 16,
                                color: isSelected
                                    ? team.primaryColor
                                    : AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isSelected ? '선택됨 · ${team.name}' : team.name,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: effectiveSelectedTeamId != null
                      ? _saveAndProceed
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        selectedTeam?.primaryColor ?? AppColors.divider,
                    disabledBackgroundColor: AppColors.divider,
                    foregroundColor: AppColors.textPrimary,
                    disabledForegroundColor: AppColors.textDisabled,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '선택 완료',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: widget.isEditMode
                    ? () => context.go('/settings')
                    : _saveAndProceed,
                child: Text(
                  widget.isEditMode ? '취소' : '나중에 설정에서 선택하기',
                  style: TextStyle(fontSize: 14, color: AppColors.textDisabled),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingHintChip extends StatelessWidget {
  final String label;

  const _OnboardingHintChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
