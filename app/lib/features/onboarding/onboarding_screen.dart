import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  String? _selectedTeamId;

  Future<void> _saveAndProceed() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedTeamId != null) {
      await prefs.setString('myTeam', _selectedTeamId!);
    }
    await prefs.setBool('onboardingDone', true);
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final selectedTeam = _selectedTeamId != null ? KboTeams.byId(_selectedTeamId!) : null;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 60),
              Text('⚾ KBO Fans', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 8),
              Text('응원하는 팀을 선택하세요', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 40),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 24,
                    mainAxisSpacing: 20,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: KboTeams.teams.length,
                  itemBuilder: (context, index) {
                    final team = KboTeams.teams[index];
                    final isSelected = _selectedTeamId == team.id;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedTeamId = isSelected ? null : team.id),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? team.primaryColor : AppColors.divider,
                                width: 3,
                              ),
                            ),
                            child: ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: team.logoUrl,
                                width: 58,
                                height: 58,
                                placeholder: (_, _) => Container(color: AppColors.cardSub),
                                errorWidget: (_, _, _) => Container(
                                  color: AppColors.cardSub,
                                  child: Center(child: Text(team.shortName, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary))),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            team.shortName,
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? team.primaryColor : AppColors.textSecondary,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
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
                    backgroundColor: selectedTeam?.primaryColor ?? AppColors.divider,
                    disabledBackgroundColor: AppColors.divider,
                    foregroundColor: AppColors.textPrimary,
                    disabledForegroundColor: AppColors.textDisabled,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('시작하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _saveAndProceed,
                child: Text('건너뛰기', style: TextStyle(fontSize: 14, color: AppColors.textDisabled)),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
