import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../data/providers.dart';
import '../../services/push_notification_service.dart';

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
  bool _pushLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPushSettings();
  }

  Future<void> _loadPushSettings() async {
    final settings = await PushNotificationService.instance.loadSettings();
    if (!mounted) {
      return;
    }
    setState(() {
      _notifGameStart = settings.gameStart;
      _notifScoring = settings.scoring;
      _notifHomerun = settings.homerun;
      _notifReversal = settings.reversal;
      _notifGameEnd = settings.gameEnd;
      _notifAllGames = settings.allGames;
      _pushLoaded = true;
    });
  }

  Future<void> _savePushSettings() async {
    final teamId = ref.read(myTeamProvider);
    await PushNotificationService.instance.saveSettings(
      PushNotificationSettings(
        gameStart: _notifGameStart,
        scoring: _notifScoring,
        homerun: _notifHomerun,
        reversal: _notifReversal,
        gameEnd: _notifGameEnd,
        allGames: _notifAllGames,
      ),
      myTeam: teamId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final myTeamId = ref.watch(myTeamProvider);
    final team = myTeamId != null ? KboTeams.byId(myTeamId) : null;
    final teamColor = team?.primaryColor ?? AppColors.live;

    return Scaffold(
      body: SafeArea(
        child: AppPageFrame(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            children: [
            const Text('⚙️ 설정', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),

            // 마이팀
            const Text('마이팀', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => context.go('/onboarding'),
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
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
            const SizedBox(height: 8),
            Text(
              team == null
                  ? '마이팀을 선택하면 홈과 알림이 응원팀 기준으로 맞춰집니다.'
                  : '응원팀을 바꾸면 홈 브리프와 알림 기준도 함께 바뀝니다.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textDisabled,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // 알림 설정
            const Text('마이팀 경기 알림', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cardSub,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: const Text(
                '마이팀 알림은 앱의 갱신 주기 기준으로 감지됩니다. 경기 시작, 득점, 역전, 종료를 원하는 수준으로 조절하세요.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  _notifRow('경기 시작', '플레이볼 직후 한 번 알립니다', _notifGameStart, teamColor, (v) async {
                    setState(() => _notifGameStart = v);
                    await _savePushSettings();
                  }),
                  _divider(),
                  _notifRow('득점', '마이팀이 점수를 올릴 때 알립니다', _notifScoring, teamColor, (v) async {
                    setState(() => _notifScoring = v);
                    await _savePushSettings();
                  }),
                  _divider(),
                  _notifRow('홈런', '홈런 상황을 별도로 알려줍니다', _notifHomerun, teamColor, (v) async {
                    setState(() => _notifHomerun = v);
                    await _savePushSettings();
                  }),
                  _divider(),
                  _notifRow('역전', '리드가 바뀌는 순간을 알려줍니다', _notifReversal, teamColor, (v) async {
                    setState(() => _notifReversal = v);
                    await _savePushSettings();
                  }),
                  _divider(),
                  _notifRow('경기 종료', '최종 결과와 함께 마무리 알림을 보냅니다', _notifGameEnd, teamColor, (v) async {
                    setState(() => _notifGameEnd = v);
                    await _savePushSettings();
                  }),
                  if (!_pushLoaded)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('푸시 설정 불러오는 중', style: TextStyle(fontSize: 12, color: AppColors.textDisabled)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const Text('리그 전체 알림', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  _notifRow('리그 전체 알림', '켜면 마이팀 외 경기 이벤트도 함께 받습니다', _notifAllGames, teamColor, (v) async {
                    setState(() => _notifAllGames = v);
                    await _savePushSettings();
                  }),
                  if (_notifAllGames)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('마이팀 외 경기까지 포함되어 알림 수가 늘어날 수 있습니다', style: TextStyle(fontSize: 12, color: AppColors.textDisabled)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 앱 정보
            const Text('앱 정보 및 지원', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  _infoRow('API 진단', hasArrow: true, onTap: () => context.push('/diagnostics')),
                  _divider(),
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
      ),
    );
  }

  Widget _notifRow(
    String label,
    String description,
    bool value,
    Color activeColor,
    ValueChanged<bool> onChanged,
  ) {
    return SizedBox(
      height: 62,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textDisabled,
                    ),
                  ),
                ],
              ),
            ),
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

  Widget _infoRow(String label, {String? trailing, bool hasArrow = false, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
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
      ),
    );
  }

  Widget _divider() => const Divider(color: AppColors.cardSub, height: 1, indent: 16, endIndent: 16);
}
