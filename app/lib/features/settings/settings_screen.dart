import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_mode_controller.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../data/providers.dart';
import '../../services/notification_inbox_service.dart';
import '../../services/push_notification_service.dart';

typedef PushNotificationSettingsLoader =
    Future<PushNotificationSettings> Function();
typedef PushPermissionStateLoader = Future<bool> Function();
typedef PushPermissionRequester = Future<bool> Function(String? myTeam);

class SettingsScreen extends ConsumerStatefulWidget {
  final PushNotificationSettingsLoader? pushSettingsLoader;
  final PushPermissionStateLoader? pushPermissionStateLoader;
  final PushPermissionRequester? pushPermissionRequester;

  const SettingsScreen({
    super.key,
    this.pushSettingsLoader,
    this.pushPermissionStateLoader,
    this.pushPermissionRequester,
  });

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _supportEmail = 'support@kbofans.com';

  String _appVersion = '확인 중';

  @override
  void initState() {
    super.initState();
    unawaited(_loadAppVersion());
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) {
        return;
      }
      setState(() {
        _appVersion = _formatPackageVersion(packageInfo);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _appVersion = '확인 불가';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final myTeamId = ref.watch(myTeamProvider);
    final team = myTeamId != null ? KboTeams.byId(myTeamId) : null;
    final colors = AppTheme.colorsOf(context);
    final teamColor = colors.readableAccent(team?.primaryColor ?? colors.live);

    return Scaffold(
      body: SafeArea(
        child: AppPageFrame(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            children: [
              Text(
                '설정',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),

              _MoreHeroCard(
                team: team,
                teamColor: teamColor,
                onEditTeam: () =>
                    context.go('/onboarding?mode=edit&redirect=/settings'),
              ),
              const SizedBox(height: 16),

              _AppearanceSettingsCard(),
              const SizedBox(height: 16),

              _PushNotificationSettingsCard(
                team: team,
                loadSettings: widget.pushSettingsLoader,
                loadPermissionState: widget.pushPermissionStateLoader,
                requestPermission: widget.pushPermissionRequester,
              ),
              const SizedBox(height: 16),

              const _NotificationInboxPreviewCard(),
              const SizedBox(height: 20),

              Text(
                '세부 설정 및 지원',
                style: TextStyle(fontSize: 14, color: colors.textSecondary),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.divider),
                ),
                child: Column(
                  children: [
                    _infoRow(
                      'API 진단',
                      hasArrow: true,
                      onTap: () => context.push('/diagnostics'),
                    ),
                    _divider(),
                    _infoRow('버전', trailing: _appVersion),
                    _divider(),
                    _infoRow(
                      '업데이트 소식',
                      hasArrow: true,
                      onTap: () => context.push('/release-notes'),
                    ),
                    _divider(),
                    _infoRow(
                      '이용약관',
                      hasArrow: true,
                      onTap: () => _showLegalDocument(
                        title: '서비스 이용약관',
                        sections: _termsSections,
                      ),
                    ),
                    _divider(),
                    _infoRow(
                      '개인정보처리방침',
                      hasArrow: true,
                      onTap: () => _showLegalDocument(
                        title: '개인정보처리방침',
                        sections: _privacySections,
                      ),
                    ),
                    _divider(),
                    _infoRow(
                      '오픈소스 라이선스',
                      hasArrow: true,
                      onTap: _showOpenSourceLicenses,
                    ),
                    _divider(),
                    _infoRow('문의하기', hasArrow: true, onTap: _openSupportEmail),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLegalDocument({
    required String title,
    required List<_LegalSection> sections,
  }) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: AppTheme.colorsOf(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => _LegalDocumentSheet(
        title: title,
        updatedAt: '2026.05.20',
        sections: sections,
      ),
    );
  }

  void _showOpenSourceLicenses() {
    showLicensePage(
      context: context,
      applicationName: 'KBO Fans',
      applicationVersion: _appVersion == '확인 중' ? null : _appVersion,
      applicationLegalese: '© 2026 KBO Fans',
    );
  }

  Future<void> _openSupportEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {
        'subject': 'KBO Fans 문의',
        'body': '문의 내용을 입력해 주세요.\n\n---\n앱 버전: $_appVersion',
      },
    );
    final launched = await _tryLaunch(uri);
    if (launched || !mounted) {
      return;
    }
    await Clipboard.setData(const ClipboardData(text: _supportEmail));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('메일 앱을 열 수 없어 지원 이메일 주소를 복사했습니다')),
    );
  }

  Future<bool> _tryLaunch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  String _formatPackageVersion(PackageInfo packageInfo) {
    if (packageInfo.version.isEmpty) {
      return '확인 불가';
    }
    final buildNumber = packageInfo.buildNumber.trim();
    if (buildNumber.isEmpty) {
      return packageInfo.version;
    }
    return '${packageInfo.version}+$buildNumber';
  }

  Widget _infoRow(
    String label, {
    String? trailing,
    bool hasArrow = false,
    VoidCallback? onTap,
  }) {
    final colors = AppTheme.colorsOf(context);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ).copyWith(color: colors.textPrimary),
              ),
            ),
            if (trailing != null)
              Text(
                trailing,
                style: TextStyle(fontSize: 14, color: colors.textSupporting),
              ),
            if (hasArrow)
              Icon(Icons.chevron_right, color: colors.textSupporting, size: 20),
          ],
        ),
      ),
    );
    if (onTap == null) {
      return row;
    }
    return Semantics(
      button: true,
      child: AppPressable(onTap: onTap, child: row),
    );
  }

  Widget _divider() {
    final colors = AppTheme.colorsOf(context);
    return Divider(color: colors.cardSub, height: 1, indent: 16, endIndent: 16);
  }
}

enum _MoreIconKind { team }

class _AppearanceSettingsCard extends ConsumerWidget {
  const _AppearanceSettingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.colorsOf(context);
    final selectedMode = ref.watch(appThemeModeProvider);
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final usesStackedModeSelector = textScale >= 1.4;

    Widget modeButton(AppThemeModePreference mode) => _AppearanceModeButton(
      mode: mode,
      selected: selectedMode == mode,
      onTap: () =>
          unawaited(ref.read(appThemeModeProvider.notifier).setMode(mode)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: '화면 모드', actionLabel: selectedMode.label),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '휴대폰 설정을 따르거나 앱 화면을 직접 고정합니다.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.25,
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (usesStackedModeSelector)
                Column(
                  children: [
                    for (final mode in AppThemeModePreference.values) ...[
                      SizedBox(width: double.infinity, child: modeButton(mode)),
                      if (mode != AppThemeModePreference.values.last)
                        const SizedBox(height: 8),
                    ],
                  ],
                )
              else
                Row(
                  children: [
                    for (final mode in AppThemeModePreference.values) ...[
                      Expanded(child: modeButton(mode)),
                      if (mode != AppThemeModePreference.values.last)
                        const SizedBox(width: 8),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppearanceModeButton extends StatelessWidget {
  final AppThemeModePreference mode;
  final bool selected;
  final VoidCallback onTap;

  const _AppearanceModeButton({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final foreground = selected ? colors.live : colors.textSecondary;
    final background = selected
        ? colors.live.withValues(alpha: 0.12)
        : colors.cardSub;
    final border = selected ? colors.live : colors.divider;

    return Semantics(
      button: true,
      selected: selected,
      label: '${mode.label} 모드',
      child: AppPressable(
        onTap: onTap,
        pressedScale: 0.98,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutQuart,
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(mode.icon, size: 20, color: foreground),
              const SizedBox(height: 5),
              Text(
                mode.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: foreground,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreHeroCard extends StatelessWidget {
  final KboTeam? team;
  final Color teamColor;
  final VoidCallback onEditTeam;

  const _MoreHeroCard({
    required this.team,
    required this.teamColor,
    required this.onEditTeam,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final teamName = team?.name ?? '마이팀을 선택하세요';
    final teamSubtitle = team == null
        ? '홈과 알림 기준을 맞추려면 팀을 먼저 선택하세요.'
        : '홈과 알림 기준으로 사용 중입니다.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.divider),
        boxShadow: [
          BoxShadow(
            color: teamColor.withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TeamLogoMark(team: team, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: teamColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '마이팀',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: colors.textSupporting,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      teamName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      teamSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onEditTeam,
              icon: _MoreGlyph(
                kind: _MoreIconKind.team,
                color: colors.textPrimary,
                size: 16,
              ),
              label: Text(team == null ? '마이팀 선택' : '마이팀 변경'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.textPrimary,
                side: BorderSide(color: colors.divider),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PushNotificationSettingsCard extends ConsumerStatefulWidget {
  final KboTeam? team;
  final PushNotificationSettingsLoader? loadSettings;
  final PushPermissionStateLoader? loadPermissionState;
  final PushPermissionRequester? requestPermission;

  const _PushNotificationSettingsCard({
    required this.team,
    required this.loadSettings,
    required this.loadPermissionState,
    required this.requestPermission,
  });

  @override
  ConsumerState<_PushNotificationSettingsCard> createState() =>
      _PushNotificationSettingsCardState();
}

class _PushNotificationSettingsCardState
    extends ConsumerState<_PushNotificationSettingsCard> {
  late Future<PushNotificationSettings> _settingsFuture;
  late Future<bool> _permissionStateFuture;
  PushNotificationSettings? _settings;
  bool? _permissionAllowed;
  bool _requestingPermission = false;
  String? _permissionError;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _settingsFuture = _loadSettings();
    _permissionStateFuture = _loadPermissionState();
  }

  Future<PushNotificationSettings> _loadSettings() async {
    final settings =
        await (widget.loadSettings?.call() ??
            PushNotificationService.instance.loadSettings());
    _settings = settings;
    return settings;
  }

  Future<bool> _loadPermissionState() async {
    if (widget.loadPermissionState != null) {
      final allowed = await widget.loadPermissionState!();
      _permissionAllowed = allowed;
      return allowed;
    }
    try {
      final state = await PushNotificationService.instance.debugState();
      final allowed = state['notificationsAllowed'] == true;
      _permissionAllowed = allowed;
      return allowed;
    } catch (_) {
      _permissionAllowed = false;
      return false;
    }
  }

  Future<void> _requestPermission() async {
    if (_requestingPermission) {
      return;
    }
    setState(() {
      _requestingPermission = true;
      _permissionError = null;
    });
    try {
      final request = widget.requestPermission;
      final allowed = request != null
          ? await request(widget.team?.id)
          : await PushNotificationService.instance.requestPermissionAndSync(
              myTeam: widget.team?.id,
            );
      if (!mounted) {
        return;
      }
      setState(() {
        _permissionAllowed = allowed;
        _permissionStateFuture = Future<bool>.value(allowed);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _permissionError = '알림 권한을 확인하지 못했습니다';
      });
    } finally {
      if (mounted) {
        setState(() {
          _requestingPermission = false;
        });
      }
    }
  }

  void _retryLoadSettings() {
    setState(() {
      _settings = null;
      _error = null;
      _settingsFuture = _loadSettings();
    });
  }

  Future<void> _save(PushNotificationSettings settings) async {
    setState(() {
      _settings = settings;
      _saving = true;
      _error = null;
    });
    try {
      await PushNotificationService.instance.saveSettings(
        settings,
        myTeam: ref.read(myTeamProvider),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '저장하지 못했습니다';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _toggleMoment(PushNotificationMoment moment, bool value) {
    final current = _settings ?? const PushNotificationSettings.defaults();
    if (_saving) {
      return;
    }
    unawaited(_save(current.withMomentEnabled(moment, value)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PushNotificationSettings>(
      future: _settingsFuture,
      builder: (context, snapshot) {
        final colors = AppTheme.colorsOf(context);
        final settings = _settings ?? snapshot.data;
        if (settings == null) {
          if (snapshot.hasError) {
            return _NotificationSettingsShell(
              status: '불러오기 실패',
              child: _NotificationLoadError(onRetry: _retryLoadSettings),
            );
          }
          return _NotificationSettingsShell(
            status: '불러오는 중',
            child: const SizedBox(
              height: 118,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          );
        }

        final accent = colors.readableAccent(
          widget.team?.primaryColor ?? colors.accent,
        );
        final enabledMomentCount = _enabledMomentCount(settings);
        return _NotificationSettingsShell(
          status: _saving
              ? '저장 중'
              : _notificationStatusLabel(enabledMomentCount),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FutureBuilder<bool>(
                future: _permissionStateFuture,
                builder: (context, permissionSnapshot) {
                  final allowed = _permissionAllowed ?? permissionSnapshot.data;
                  return _PushPermissionStatus(
                    allowed: allowed,
                    busy: _requestingPermission,
                    error: _permissionError,
                    onRequest: _requestPermission,
                  );
                },
              ),
              const SizedBox(height: 12),
              _NotificationTargetStrip(team: widget.team, accent: accent),
              if (widget.team == null) ...[
                const SizedBox(height: 10),
                Text(
                  '마이팀 알림은 팀을 선택해야 시작됩니다. 직접 팔로우한 경기 알림은 별도로 동작합니다.',
                  key: const ValueKey('push_notification_team_required'),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                '여기서는 받을 알림을 선택합니다. 실제 수신은 알림 권한, 기기 등록, 서버 상태에 따라 달라질 수 있습니다.',
                key: const ValueKey('push_notification_delivery_notice'),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _NotificationToggleGroup(
                title: '경기 전후',
                items: const [
                  _NotificationToggleItem(
                    moment: PushNotificationMoment.lineupOpened,
                    label: '선발 라인업 공개',
                    subtitle: '라인업이 뜨면 알림',
                  ),
                  _NotificationToggleItem(
                    moment: PushNotificationMoment.gameStart,
                    label: '경기 시작과 시작 임박',
                    subtitle: '10분 전과 플레이볼',
                  ),
                  _NotificationToggleItem(
                    moment: PushNotificationMoment.gameEnd,
                    label: '경기 종료 결과',
                    subtitle: '종료와 취소 결과',
                  ),
                  _NotificationToggleItem(
                    moment: PushNotificationMoment.baseballInfo,
                    label: '야구 브리프',
                    subtitle: '경기일/기록 체크',
                  ),
                ],
                settings: settings,
                enabled: !_saving,
                onChanged: _toggleMoment,
              ),
              const SizedBox(height: 14),
              _NotificationToggleGroup(
                title: '경기 중',
                items: const [
                  _NotificationToggleItem(
                    moment: PushNotificationMoment.scoring,
                    label: '득점',
                    subtitle: '점수 변화 즉시',
                  ),
                  _NotificationToggleItem(
                    moment: PushNotificationMoment.hit,
                    label: '안타',
                    subtitle: '주자 상황 포함',
                  ),
                  _NotificationToggleItem(
                    moment: PushNotificationMoment.homerun,
                    label: '홈런',
                    subtitle: '홈런 장면 즉시',
                  ),
                  _NotificationToggleItem(
                    moment: PushNotificationMoment.reversal,
                    label: '역전',
                    subtitle: '리드 변경 시',
                  ),
                  _NotificationToggleItem(
                    moment: PushNotificationMoment.inningChange,
                    label: '이닝 전환',
                    subtitle: '초/말 전환',
                  ),
                  _NotificationToggleItem(
                    moment: PushNotificationMoment.atBat,
                    label: '타석 변화',
                    subtitle: '새 타자 진입',
                  ),
                ],
                settings: settings,
                enabled: !_saving,
                onChanged: _toggleMoment,
              ),
              if (enabledMomentCount == 0) ...[
                const SizedBox(height: 14),
                const _NotificationOffState(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.live,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _NotificationLoadError extends StatelessWidget {
  final VoidCallback onRetry;

  const _NotificationLoadError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '알림 설정을 불러오지 못했습니다',
          style: TextStyle(
            fontSize: 14,
            color: colors.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '연결을 확인한 뒤 다시 시도해 주세요.',
          style: TextStyle(
            fontSize: 12,
            height: 1.45,
            color: colors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('push_notification_load_retry'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('다시 시도'),
        ),
      ],
    );
  }
}

class _PushPermissionStatus extends StatelessWidget {
  final bool? allowed;
  final bool busy;
  final String? error;
  final VoidCallback onRequest;

  const _PushPermissionStatus({
    required this.allowed,
    required this.busy,
    required this.error,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final isAllowed = allowed == true;
    final status = allowed == null
        ? '알림 권한 확인 중'
        : isAllowed
        ? '알림 권한 허용됨'
        : '알림 권한을 확인해 주세요';
    final actionLabel = allowed == false ? '알림 허용하기' : '권한 다시 확인';

    return Container(
      key: const ValueKey('push_permission_status'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.cardSub,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status,
            style: TextStyle(
              fontSize: 13,
              color: isAllowed ? colors.positive : colors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (allowed != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('push_permission_request'),
              onPressed: busy ? null : onRequest,
              child: Text(busy ? '확인 중' : actionLabel),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: colors.live,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotificationSettingsShell extends StatelessWidget {
  final String status;
  final Widget child;

  const _NotificationSettingsShell({required this.status, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: '푸시 알림', actionLabel: status),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.divider),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _NotificationTargetStrip extends StatelessWidget {
  final KboTeam? team;
  final Color accent;

  const _NotificationTargetStrip({required this.team, required this.accent});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final target = team == null ? '마이팀 선택 전' : '${team!.shortName} 경기';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: colors.cardSub,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.push_pin_outlined, size: 17, color: accent),
          const SizedBox(width: 8),
          Text(
            '기본 대상',
            style: TextStyle(
              fontSize: 12,
              color: colors.textSupporting,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              target,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: colors.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationToggleGroup extends StatelessWidget {
  final String title;
  final List<_NotificationToggleItem> items;
  final PushNotificationSettings settings;
  final bool enabled;
  final void Function(PushNotificationMoment moment, bool value) onChanged;

  const _NotificationToggleGroup({
    required this.title,
    required this.items,
    required this.settings,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: colors.textSecondary,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          decoration: BoxDecoration(
            color: colors.cardSub,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.divider),
          ),
          child: Column(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                _NotificationToggleRow(
                  item: items[index],
                  value: settings.isMomentEnabled(items[index].moment),
                  enabled: enabled,
                  onChanged: onChanged,
                ),
                if (index != items.length - 1)
                  Divider(
                    height: 1,
                    color: colors.divider,
                    indent: 12,
                    endIndent: 12,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NotificationToggleRow extends StatelessWidget {
  final _NotificationToggleItem item;
  final bool value;
  final bool enabled;
  final void Function(PushNotificationMoment moment, bool value) onChanged;

  const _NotificationToggleRow({
    required this.item,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final allowsTextWrapping = textScale >= 1.4;
    final toggle = enabled ? () => onChanged(item.moment, !value) : null;
    final semanticsLabel = item.subtitle == null
        ? item.label
        : '${item.label}, ${item.subtitle}';

    return Semantics(
      key: ValueKey('push_toggle_${item.moment.name}'),
      container: true,
      excludeSemantics: true,
      label: semanticsLabel,
      toggled: value,
      enabled: enabled,
      onTap: toggle,
      child: AppPressable(
        onTap: toggle,
        pressedScale: 0.99,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        maxLines: allowsTextWrapping ? null : 1,
                        overflow: allowsTextWrapping
                            ? null
                            : TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: enabled
                              ? colors.textPrimary
                              : colors.textDisabled,
                        ),
                      ),
                      if (item.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle!,
                          maxLines: allowsTextWrapping ? null : 1,
                          overflow: allowsTextWrapping
                              ? null
                              : TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: enabled
                                ? colors.textSupporting
                                : colors.textDisabled,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: value,
                  onChanged: enabled
                      ? (nextValue) => onChanged(item.moment, nextValue)
                      : null,
                  activeThumbColor: colors.accent,
                  activeTrackColor: colors.accent.withValues(alpha: 0.36),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationOffState extends StatelessWidget {
  const _NotificationOffState();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.cardSub,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.divider),
      ),
      child: Text(
        '받을 알림을 선택하지 않았습니다',
        style: TextStyle(
          fontSize: 13,
          color: colors.textSecondary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _NotificationToggleItem {
  final PushNotificationMoment moment;
  final String label;
  final String? subtitle;

  const _NotificationToggleItem({
    required this.moment,
    required this.label,
    this.subtitle,
  });
}

int _enabledMomentCount(PushNotificationSettings settings) {
  return PushNotificationMoment.values.where(settings.isMomentEnabled).length;
}

String _notificationStatusLabel(int enabledMomentCount) {
  if (enabledMomentCount == 0) {
    return '선택 없음';
  }
  return '$enabledMomentCount개 선택됨';
}

class _NotificationInboxPreviewCard extends StatelessWidget {
  const _NotificationInboxPreviewCard();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    return FutureBuilder<List<NotificationInboxEntry>>(
      future: NotificationInboxService.instance.loadEntries(),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <NotificationInboxEntry>[];
        final unreadCount = entries.where((entry) => !entry.read).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: '알림함',
              actionLabel: '전체 보기',
              onAction: () => context.push('/notifications'),
            ),
            const SizedBox(height: 8),
            AppPressable(
              onTap: () => context.push('/notifications'),
              pressedScale: 0.975,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.divider),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: colors.live.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colors.live.withValues(alpha: 0.36),
                        ),
                      ),
                      child: Icon(
                        Icons.notifications_active_outlined,
                        color: colors.live,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '푸시 알림 모아보기',
                            style: TextStyle(
                              fontSize: 15,
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '최근 받은 알림을 확인합니다',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textSupporting,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      constraints: const BoxConstraints(minWidth: 54),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.cardSub,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: colors.divider),
                      ),
                      child: Text(
                        unreadCount == 0
                            ? '${entries.length}개'
                            : '$unreadCount 새 알림',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: unreadCount == 0
                              ? colors.textSecondary
                              : colors.live,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: colors.textSupporting,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MoreGlyph extends StatelessWidget {
  final _MoreIconKind kind;
  final Color color;
  final double size;

  const _MoreGlyph({required this.kind, required this.color, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MoreGlyphPainter(kind: kind, color: color),
      ),
    );
  }
}

class _MoreGlyphPainter extends CustomPainter {
  final _MoreIconKind kind;
  final Color color;

  const _MoreGlyphPainter({required this.kind, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final strokeWidth = (size.shortestSide * 0.1).clamp(1.55, 2.35).toDouble();
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (kind) {
      case _MoreIconKind.team:
        final shield = Path()
          ..moveTo(w * 0.5, h * 0.12)
          ..lineTo(w * 0.78, h * 0.24)
          ..lineTo(w * 0.72, h * 0.58)
          ..quadraticBezierTo(w * 0.68, h * 0.76, w * 0.5, h * 0.88)
          ..quadraticBezierTo(w * 0.32, h * 0.76, w * 0.28, h * 0.58)
          ..lineTo(w * 0.22, h * 0.24)
          ..close();
        canvas.drawPath(shield, stroke);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _MoreGlyphPainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.color != color;
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionHeader({required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (actionLabel != null && onAction == null)
          Text(
            actionLabel!,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (actionLabel != null && onAction != null)
          AppPressable(
            onTap: onAction,
            child: Row(
              children: [
                Text(
                  actionLabel!,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TeamLogoMark extends StatelessWidget {
  final KboTeam? team;
  final double size;

  const _TeamLogoMark({required this.team, required this.size});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    if (team == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colors.cardSub,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.divider),
        ),
        child: Icon(
          Icons.shield_outlined,
          color: colors.textSecondary,
          size: 26,
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.cardSub,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.divider),
      ),
      child: CachedNetworkImage(
        imageUrl: team!.logoUrl,
        fit: BoxFit.contain,
        placeholder: (_, _) => const SizedBox.shrink(),
        errorWidget: (_, _, _) => Center(
          child: Text(
            team!.shortName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalDocumentSheet extends StatelessWidget {
  final String title;
  final String updatedAt;
  final List<_LegalSection> sections;

  const _LegalDocumentSheet({
    required this.title,
    required this.updatedAt,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '시행일 $updatedAt',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSupporting,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Divider(color: colors.divider, height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              itemBuilder: (context, index) {
                final section = sections[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title,
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      section.body,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                );
              },
              separatorBuilder: (_, _) => const SizedBox(height: 18),
              itemCount: sections.length,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalSection {
  final String title;
  final String body;

  const _LegalSection({required this.title, required this.body});
}

const _termsSections = [
  _LegalSection(
    title: '서비스 성격',
    body:
        'KBO Fans는 KBO 경기 정보를 더 빠르게 확인하기 위한 팬용 앱입니다. KBO 공식 앱이 아니며, 구단이나 리그의 공식 발표를 대체하지 않습니다.',
  ),
  _LegalSection(
    title: '데이터와 알림',
    body:
        '스코어, 일정, 순위, 문자중계, 알림은 공식 원천과 내부 캐시 상태에 따라 지연되거나 일시적으로 다르게 보일 수 있습니다. 중요한 결정에는 공식 채널을 함께 확인해 주세요.',
  ),
  _LegalSection(
    title: '사용자 책임',
    body:
        '앱을 비정상적으로 자동화하거나 서비스 안정성을 해치는 방식으로 사용할 수 없습니다. 앱이 제공하는 링크와 외부 콘텐츠 이용에는 각 제공자의 정책이 적용됩니다.',
  ),
  _LegalSection(
    title: '변경',
    body:
        '서비스 기능, 알림 정책, 문서 내용은 앱 개선 과정에서 바뀔 수 있습니다. 중요한 변경은 앱 또는 배포 문서를 통해 안내합니다.',
  ),
];

const _privacySections = [
  _LegalSection(
    title: '수집하는 정보',
    body:
        '마이팀, 알림 설정, 라이브 경기 알림 상태처럼 앱 사용에 필요한 설정을 저장합니다. 푸시 알림을 쓰는 경우 기기 토큰과 구독 토픽이 알림 발송을 위해 사용될 수 있습니다.',
  ),
  _LegalSection(
    title: '사용 목적',
    body:
        '저장된 정보는 홈 화면 개인화, 경기 알림, Live Activity 또는 위젯 상태 갱신, 오류 진단과 서비스 안정성 개선에만 사용합니다.',
  ),
  _LegalSection(
    title: '보관과 삭제',
    body:
        '기기 안에 저장된 설정은 앱 삭제 시 함께 제거됩니다. 서버에 저장된 푸시 토큰은 알림 비활성화, 앱 삭제, 토큰 만료 이후 더 이상 정상 발송에 사용되지 않습니다.',
  ),
  _LegalSection(
    title: '문의',
    body: '개인정보와 지원 문의는 support@kbofans.com 으로 보낼 수 있습니다.',
  ),
];
