import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/team_data.dart';
import '../../core/router/app_router.dart';
import '../../data/providers.dart';
import '../../core/theme/app_theme.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  String? _selectedTeamId;

  Future<void> _saveAndProceed() async {
    // 마이팀을 전역 Provider에 저장
    await ref.read(myTeamProvider.notifier).setTeam(_selectedTeamId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboardingDone', true);
    ref.read(onboardingDoneProvider.notifier).setValue(true);
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final selectedTeam = _selectedTeamId != null
        ? KboTeams.byId(_selectedTeamId!)
        : null;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 60),
              Text(
                'KBO Fans',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '응원하는 팀을 선택하세요',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 40),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 18,
                    childAspectRatio: 0.95,
                  ),
                  itemCount: KboTeams.teams.length,
                  itemBuilder: (context, index) {
                    final team = KboTeams.teams[index];
                    final isSelected = _selectedTeamId == team.id;
                    return GestureDetector(
                      onTap: () => setState(
                        () => _selectedTeamId = isSelected ? null : team.id,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(20),
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
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ]
                              : null,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 92,
                              height: 92,
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
                                padding: const EdgeInsets.all(10),
                                child: CachedNetworkImage(
                                  imageUrl: team.logoUrl,
                                  fit: BoxFit.contain,
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
                                fontSize: 17,
                                color: isSelected
                                    ? team.primaryColor
                                    : AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              team.name,
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
                  onPressed: _selectedTeamId != null ? _saveAndProceed : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        selectedTeam?.primaryColor ?? AppColors.divider,
                    disabledBackgroundColor: AppColors.divider,
                    foregroundColor: AppColors.textPrimary,
                    disabledForegroundColor: AppColors.textDisabled,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '시작하기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _saveAndProceed,
                child: Text(
                  '건너뛰기',
                  style: TextStyle(fontSize: 14, color: AppColors.textDisabled),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
