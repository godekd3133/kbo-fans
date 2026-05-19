import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../data/providers.dart';
import '../../services/game_event_alert_service.dart';
import '../../services/push_notification_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  PushNotificationDelivery _gameStartDelivery =
      PushNotificationDelivery.summary;
  PushNotificationDelivery _scoringDelivery =
      PushNotificationDelivery.immediate;
  PushNotificationDelivery _homerunDelivery =
      PushNotificationDelivery.immediate;
  PushNotificationDelivery _reversalDelivery =
      PushNotificationDelivery.immediate;
  PushNotificationDelivery _gameEndDelivery = PushNotificationDelivery.summary;
  PushNotificationDelivery _lineupOpenedDelivery =
      PushNotificationDelivery.summary;
  PushNotificationDelivery _inningChangeDelivery =
      PushNotificationDelivery.liveOnly;
  bool _notifAllGames = false;
  bool _pushLoaded = false;
  bool _permissionBusy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPushSettings());
  }

  Future<void> _loadPushSettings() async {
    final settings = await PushNotificationService.instance.loadSettings();
    if (!mounted) {
      return;
    }
    setState(() {
      _gameStartDelivery = settings.gameStartDelivery;
      _scoringDelivery = settings.scoringDelivery;
      _homerunDelivery = settings.homerunDelivery;
      _reversalDelivery = settings.reversalDelivery;
      _gameEndDelivery = settings.gameEndDelivery;
      _lineupOpenedDelivery = settings.lineupOpenedDelivery;
      _inningChangeDelivery = settings.inningChangeDelivery;
      _notifAllGames = settings.allGames;
      _pushLoaded = true;
    });
  }

  Future<void> _savePushSettings() async {
    final teamId = ref.read(myTeamProvider);
    await PushNotificationService.instance.saveSettings(
      PushNotificationSettings(
        gameStart: _isEnabled(_gameStartDelivery),
        scoring: _isEnabled(_scoringDelivery),
        homerun: _isEnabled(_homerunDelivery),
        reversal: _isEnabled(_reversalDelivery),
        gameEnd: _isEnabled(_gameEndDelivery),
        lineupOpened: _isEnabled(_lineupOpenedDelivery),
        inningChange: _isEnabled(_inningChangeDelivery),
        allGames: _notifAllGames,
        gameStartDelivery: _gameStartDelivery,
        scoringDelivery: _scoringDelivery,
        homerunDelivery: _homerunDelivery,
        reversalDelivery: _reversalDelivery,
        gameEndDelivery: _gameEndDelivery,
        lineupOpenedDelivery: _lineupOpenedDelivery,
        inningChangeDelivery: _inningChangeDelivery,
      ),
      myTeam: teamId,
    );
  }

  bool _isEnabled(PushNotificationDelivery delivery) {
    return delivery != PushNotificationDelivery.off;
  }

  Future<void> _setDelivery({
    required PushNotificationDelivery delivery,
    required ValueChanged<PushNotificationDelivery> update,
  }) async {
    setState(() {
      update(delivery);
    });
    await _savePushSettings();
    if (delivery == PushNotificationDelivery.immediate) {
      await _requestNotificationPermissions(showMessage: false);
    }
  }

  Future<void> _applyCorePlaybook() async {
    setState(() {
      _gameStartDelivery = PushNotificationDelivery.summary;
      _scoringDelivery = PushNotificationDelivery.immediate;
      _homerunDelivery = PushNotificationDelivery.immediate;
      _reversalDelivery = PushNotificationDelivery.immediate;
      _gameEndDelivery = PushNotificationDelivery.summary;
      _lineupOpenedDelivery = PushNotificationDelivery.summary;
      _inningChangeDelivery = PushNotificationDelivery.liveOnly;
      _notifAllGames = false;
    });
    await _savePushSettings();
    await _requestNotificationPermissions(showMessage: false);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('내 팀 집중 플레이북을 적용했습니다')));
  }

  Future<void> _requestNotificationPermissions({
    bool showMessage = true,
  }) async {
    if (_permissionBusy) {
      return;
    }
    setState(() {
      _permissionBusy = true;
    });

    try {
      final results = await Future.wait([
        GameEventAlertService.instance.requestPermissions(),
        PushNotificationService.instance.requestPermissionAndSync(
          myTeam: ref.read(myTeamProvider),
        ),
      ]);
      if (!mounted || !showMessage) {
        return;
      }
      final granted = results.any((allowed) => allowed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(granted ? '알림 권한을 확인했습니다' : '시스템 설정에서 알림 권한을 허용해야 합니다'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _permissionBusy = false;
        });
      }
    }
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
              const Text(
                '설정',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),

              const Text(
                '마이팀',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              _MyTeamCard(team: team),
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

              const Text(
                '알림 플레이북',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              _PlaybookPreviewCard(
                teamName: team?.shortName ?? '마이팀',
                teamColor: teamColor,
                onApply: _applyCorePlaybook,
                onPermissionCheck: _permissionBusy
                    ? null
                    : () => unawaited(_requestNotificationPermissions()),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  children: [
                    _momentRow(
                      label: '경기 시작',
                      description: '플레이볼 직후는 요약으로 두는 것을 권장합니다',
                      delivery: _gameStartDelivery,
                      teamColor: teamColor,
                      onTap: () => _showDeliveryPicker(
                        title: '경기 시작',
                        current: _gameStartDelivery,
                        update: (value) => _gameStartDelivery = value,
                      ),
                    ),
                    _divider(),
                    _momentRow(
                      label: '득점',
                      description: '마이팀이 점수를 올릴 때 즉시 알립니다',
                      delivery: _scoringDelivery,
                      teamColor: teamColor,
                      onTap: () => _showDeliveryPicker(
                        title: '득점',
                        current: _scoringDelivery,
                        update: (value) => _scoringDelivery = value,
                      ),
                    ),
                    _divider(),
                    _momentRow(
                      label: '홈런',
                      description: '홈런 상황은 별도 즉시 알림으로 분리합니다',
                      delivery: _homerunDelivery,
                      teamColor: teamColor,
                      onTap: () => _showDeliveryPicker(
                        title: '홈런',
                        current: _homerunDelivery,
                        update: (value) => _homerunDelivery = value,
                      ),
                    ),
                    _divider(),
                    _momentRow(
                      label: '역전',
                      description: '리드가 바뀌는 순간만 강하게 알립니다',
                      delivery: _reversalDelivery,
                      teamColor: teamColor,
                      onTap: () => _showDeliveryPicker(
                        title: '역전',
                        current: _reversalDelivery,
                        update: (value) => _reversalDelivery = value,
                      ),
                    ),
                    _divider(),
                    _momentRow(
                      label: '경기 종료',
                      description: '최종 결과는 바로 또는 요약으로 받을 수 있습니다',
                      delivery: _gameEndDelivery,
                      teamColor: teamColor,
                      onTap: () => _showDeliveryPicker(
                        title: '경기 종료',
                        current: _gameEndDelivery,
                        update: (value) => _gameEndDelivery = value,
                      ),
                    ),
                    _divider(),
                    _momentRow(
                      label: '라인업',
                      description: '선발 라인업 공개 또는 변경을 묶어서 봅니다',
                      delivery: _lineupOpenedDelivery,
                      teamColor: teamColor,
                      onTap: () => _showDeliveryPicker(
                        title: '라인업',
                        current: _lineupOpenedDelivery,
                        update: (value) => _lineupOpenedDelivery = value,
                      ),
                    ),
                    _divider(),
                    _momentRow(
                      label: '이닝 교대',
                      description: '알림 대신 Live 표면에서 상태만 갱신합니다',
                      delivery: _inningChangeDelivery,
                      teamColor: teamColor,
                      onTap: () => _showDeliveryPicker(
                        title: '이닝 교대',
                        current: _inningChangeDelivery,
                        update: (value) => _inningChangeDelivery = value,
                      ),
                    ),
                    if (!_pushLoaded)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '푸시 설정 불러오는 중',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textDisabled,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              const Text(
                '앱 밖 표면',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.divider),
                ),
                child: const Column(
                  children: [
                    _SurfaceRow(
                      icon: Icons.notifications_outlined,
                      label: 'Push',
                      description: '득점, 홈런, 역전처럼 바로 대응할 장면만 보냅니다',
                    ),
                    _DividerInset(),
                    _SurfaceRow(
                      icon: Icons.schedule_outlined,
                      label: '요약',
                      description: '시작, 종료, 라인업처럼 묶어도 되는 장면을 모읍니다',
                    ),
                    _DividerInset(),
                    _SurfaceRow(
                      icon: Icons.phone_iphone,
                      label: 'Live 표면',
                      description: '경기 상세에서 따라가기한 경기의 현재 상태만 유지합니다',
                    ),
                    _DividerInset(),
                    _SurfaceRow(
                      icon: Icons.widgets_outlined,
                      label: '위젯',
                      description: '홈 화면에서는 오늘의 대표 경기를 빠르게 확인합니다',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              const Text(
                '리그 전체 알림',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  children: [
                    _leagueAllGamesRow(teamColor),
                    if (_notifAllGames)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '마이팀 외 경기까지 포함되어 즉시 알림 수가 늘어날 수 있습니다',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textDisabled,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              const Text(
                '앱 정보 및 지원',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  children: [
                    _infoRow(
                      'API 진단',
                      hasArrow: true,
                      onTap: () => context.push('/diagnostics'),
                    ),
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

  Widget _momentRow({
    required String label,
    required String description,
    required PushNotificationDelivery delivery,
    required Color teamColor,
    required VoidCallback onTap,
  }) {
    final color = _deliveryColor(delivery, teamColor);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 66),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textDisabled,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 70,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Text(
                  _deliveryLabel(delivery),
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textDisabled,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _leagueAllGamesRow(Color teamColor) {
    return SizedBox(
      height: 62,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '리그 전체 Moment',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '켜면 마이팀 외 경기 이벤트도 함께 받습니다',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textDisabled,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _notifAllGames,
              onChanged: (value) async {
                setState(() => _notifAllGames = value);
                await _savePushSettings();
              },
              activeThumbColor: teamColor,
              inactiveTrackColor: AppColors.divider,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeliveryPicker({
    required String title,
    required PushNotificationDelivery current,
    required ValueChanged<PushNotificationDelivery> update,
  }) async {
    final selected = await showModalBottomSheet<PushNotificationDelivery>(
      context: context,
      useSafeArea: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) =>
          _DeliveryPickerSheet(title: title, current: current),
    );

    if (selected == null) {
      return;
    }
    await _setDelivery(delivery: selected, update: update);
  }

  String _deliveryLabel(PushNotificationDelivery delivery) {
    return switch (delivery) {
      PushNotificationDelivery.immediate => '바로',
      PushNotificationDelivery.summary => '요약',
      PushNotificationDelivery.liveOnly => 'Live만',
      PushNotificationDelivery.off => '끔',
    };
  }

  Color _deliveryColor(PushNotificationDelivery delivery, Color teamColor) {
    return switch (delivery) {
      PushNotificationDelivery.immediate => AppColors.live,
      PushNotificationDelivery.summary => teamColor,
      PushNotificationDelivery.liveOnly => AppColors.accent,
      PushNotificationDelivery.off => AppColors.textDisabled,
    };
  }

  Widget _infoRow(
    String label, {
    String? trailing,
    bool hasArrow = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textDisabled,
                  ),
                ),
              if (hasArrow)
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textDisabled,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() => const Divider(
    color: AppColors.cardSub,
    height: 1,
    indent: 16,
    endIndent: 16,
  );
}

class _MyTeamCard extends StatelessWidget {
  final KboTeam? team;

  const _MyTeamCard({required this.team});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/onboarding?mode=edit'),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
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
                imageUrl: team!.logoUrl,
                width: 32,
                height: 32,
                placeholder: (_, _) => const SizedBox(width: 32, height: 32),
                errorWidget: (_, _, _) => Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: AppColors.cardSub,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      team!.shortName,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                team!.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else
              const Text(
                '팀을 선택하세요',
                style: TextStyle(fontSize: 16, color: AppColors.textDisabled),
              ),
            const Spacer(),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textDisabled,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybookPreviewCard extends StatelessWidget {
  final String teamName;
  final Color teamColor;
  final VoidCallback onApply;
  final VoidCallback? onPermissionCheck;

  const _PlaybookPreviewCard({
    required this.teamName,
    required this.teamColor,
    required this.onApply,
    required this.onPermissionCheck,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: teamColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$teamName 중심',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              const Text(
                'Moment',
                style: TextStyle(fontSize: 11, color: AppColors.textDisabled),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '알림은 소음이 아니라 경기 흐름을 놓치지 않게 하는 신호로만 씁니다.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onApply,
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('내 팀 집중'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.divider),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onPermissionCheck,
                  icon: const Icon(Icons.notifications_outlined, size: 16),
                  label: const Text('권한 확인'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.textPrimary,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SurfaceRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;

  const _SurfaceRow({
    required this.icon,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDisabled,
                    height: 1.35,
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

class _DividerInset extends StatelessWidget {
  const _DividerInset();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      color: AppColors.cardSub,
      height: 1,
      indent: 16,
      endIndent: 16,
    );
  }
}

class _DeliveryPickerSheet extends StatelessWidget {
  final String title;
  final PushNotificationDelivery current;

  const _DeliveryPickerSheet({required this.title, required this.current});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            '이 장면을 앱 밖에서 어떻게 다룰지 선택합니다.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          _option(
            context,
            delivery: PushNotificationDelivery.immediate,
            label: '바로 알림',
            description: '득점, 홈런, 역전처럼 즉시 봐야 할 장면',
            icon: Icons.notifications_active_outlined,
          ),
          _option(
            context,
            delivery: PushNotificationDelivery.summary,
            label: '요약',
            description: '시작, 종료, 라인업처럼 묶어서 보기 좋은 장면',
            icon: Icons.schedule_outlined,
          ),
          _option(
            context,
            delivery: PushNotificationDelivery.liveOnly,
            label: 'Live 표면만',
            description: '경기 따라가기 중 현재 상태에만 반영',
            icon: Icons.phone_iphone,
          ),
          _option(
            context,
            delivery: PushNotificationDelivery.off,
            label: '끄기',
            description: '이 장면은 앱 밖으로 보내지 않습니다',
            icon: Icons.notifications_off_outlined,
          ),
        ],
      ),
    );
  }

  Widget _option(
    BuildContext context, {
    required PushNotificationDelivery delivery,
    required String label,
    required String description,
    required IconData icon,
  }) {
    final selected = current == delivery;
    return InkWell(
      onTap: () => Navigator.of(context).pop(delivery),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.cardSub : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.textSecondary : AppColors.divider,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textDisabled,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check, size: 18, color: AppColors.textPrimary),
          ],
        ),
      ),
    );
  }
}
