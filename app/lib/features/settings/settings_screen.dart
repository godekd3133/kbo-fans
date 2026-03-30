import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
import '../../data/providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notifGameStart = true;
  bool _notifScoring = true;
  bool _notifHomerun = true;
  bool _notifReversal = true;
  bool _notifGameEnd = true;
  bool _notifAllGames = false;

  @override
  Widget build(BuildContext context) {
    final myTeamId = ref.watch(myTeamProvider);
    final team = myTeamId != null ? KboTeams.byId(myTeamId) : null;
    final teamColor = team?.primaryColor ?? AppColors.live;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            const Text('⚙️ 설정', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),

            // 마이팀
            const Text('마이팀', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => context.go('/onboarding'),
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    if (team != null) ...[
                      CachedNetworkImage(
                        imageUrl: team.logoUrl, width: 32, height: 32,
                        placeholder: (_, _) => const SizedBox(width: 32, height: 32),
                        errorWidget: (_, _, _) => Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(color: AppColors.cardSub, shape: BoxShape.circle),
                          child: Center(child: Text(team.shortName, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(team.name, style: const TextStyle(fontSize: 16)),
                    ] else
                      const Text('팀을 선택하세요', style: TextStyle(fontSize: 16, color: AppColors.textDisabled)),
                    const Spacer(),
                    const Icon(Icons.chevron_right, color: AppColors.textDisabled, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 알림 설정
            const Text('알림 설정', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  _notifRow('경기 시작', _notifGameStart, teamColor, (v) => setState(() => _notifGameStart = v)),
                  _divider(),
                  _notifRow('득점', _notifScoring, teamColor, (v) => setState(() => _notifScoring = v)),
                  _divider(),
                  _notifRow('홈런', _notifHomerun, teamColor, (v) => setState(() => _notifHomerun = v)),
                  _divider(),
                  _notifRow('역전', _notifReversal, teamColor, (v) => setState(() => _notifReversal = v)),
                  _divider(),
                  _notifRow('경기 종료', _notifGameEnd, teamColor, (v) => setState(() => _notifGameEnd = v)),
                  const Divider(color: AppColors.divider, height: 1, indent: 16, endIndent: 16),
                  _notifRow('전체 경기 알림', _notifAllGames, teamColor, (v) => setState(() => _notifAllGames = v)),
                  if (_notifAllGames)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('마이팀 외 경기도 알림을 받습니다', style: TextStyle(fontSize: 12, color: AppColors.textDisabled)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 앱 정보
            const Text('앱 정보', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  _infoRow('버전', trailing: '1.0.0'),
                  _divider(),
                  _infoRow('이용약관', hasArrow: true),
                  _divider(),
                  _infoRow('개인정보처리방침', hasArrow: true),
                  _divider(),
                  _infoRow('오픈소스 라이선스', hasArrow: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notifRow(String label, bool value, Color activeColor, ValueChanged<bool> onChanged) {
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: activeColor,
              inactiveTrackColor: AppColors.divider,
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, {String? trailing, bool hasArrow = false}) {
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
            if (trailing != null)
              Text(trailing, style: const TextStyle(fontSize: 14, color: AppColors.textDisabled)),
            if (hasArrow)
              const Icon(Icons.chevron_right, color: AppColors.textDisabled, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _divider() => const Divider(color: AppColors.cardSub, height: 1, indent: 16, endIndent: 16);
}
