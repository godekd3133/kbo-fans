import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/team_data.dart';
import '../../core/router/app_route_sanitizer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../data/models/home_aggregate.dart';
import '../../data/models/schedule.dart';
import '../../data/providers.dart';
import '../../services/notification_inbox_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

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
    final teamColor = team?.primaryColor ?? AppColors.live;
    final today = _dateKey(DateTime.now());
    final aggregateAsync = ref.watch(
      homeAggregateProvider('$today|${myTeamId ?? ''}'),
    );
    final aggregate = aggregateAsync.asData?.value;

    return Scaffold(
      body: SafeArea(
        child: AppPageFrame(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '더보기',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textDisabled,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'KBO 팬 허브',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _MoreHeroCard(
                team: team,
                teamColor: teamColor,
                aggregate: aggregate,
                isLoading: aggregateAsync.isLoading,
                hasError: aggregateAsync.hasError,
                onEditTeam: () => context.go('/onboarding?mode=edit'),
                onOpenPrimary: () {
                  final todayGameId = aggregate?.myTeamBrief?.todayGameId;
                  if (todayGameId != null && todayGameId.isNotEmpty) {
                    context.go('/game/$todayGameId');
                    return;
                  }
                  context.go('/schedule');
                },
              ),
              const SizedBox(height: 16),

              _MoreInsightSection(
                aggregate: aggregate,
                isLoading: aggregateAsync.isLoading,
                hasError: aggregateAsync.hasError,
              ),
              const SizedBox(height: 16),

              const _NotificationInboxPreviewCard(),
              const SizedBox(height: 16),

              const _MoreShortcutGrid(),
              const SizedBox(height: 20),

              const _MoreSurfaceCard(),
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
                '세부 설정 및 지원',
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
      backgroundColor: AppColors.card,
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

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _infoRow(
    String label, {
    String? trailing,
    bool hasArrow = false,
    VoidCallback? onTap,
  }) {
    final row = SizedBox(
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
    );
    if (onTap == null) {
      return row;
    }
    return Semantics(
      button: true,
      child: AppPressable(onTap: onTap, child: row),
    );
  }

  Widget _divider() => const Divider(
    color: AppColors.cardSub,
    height: 1,
    indent: 16,
    endIndent: 16,
  );
}

enum _MoreIconKind { game, standings, records, news, push, live, brief, team }

class _MoreHeroCard extends StatelessWidget {
  final KboTeam? team;
  final Color teamColor;
  final HomeAggregate? aggregate;
  final bool isLoading;
  final bool hasError;
  final VoidCallback onEditTeam;
  final VoidCallback onOpenPrimary;

  const _MoreHeroCard({
    required this.team,
    required this.teamColor,
    required this.aggregate,
    required this.isLoading,
    required this.hasError,
    required this.onEditTeam,
    required this.onOpenPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final brief = aggregate?.myTeamBrief;
    final standing = brief?.standing;
    final teamName = team?.name ?? '마이팀을 선택하세요';
    final teamSubtitle = team == null
        ? '응원팀 기준으로 경기, 기록, 알림을 묶습니다.'
        : _teamSubtitle(standing);
    final todayLabel = brief?.todayGameId?.isNotEmpty == true
        ? '경기 있음'
        : (brief?.nextGame?.time.isNotEmpty == true
              ? brief!.nextGame!.time
              : (isLoading ? '확인 중' : '일정 보기'));
    final rankLabel = standing == null ? '-' : '${standing.rank}위';
    final recentLabel = brief == null || brief.recentGamesCount == 0
        ? '-'
        : '${brief.recentWins}승 ${brief.recentLosses}패';
    final statusLabel = hasError
        ? '업데이트 대기'
        : (brief?.todayGameId?.isNotEmpty == true ? '오늘 경기' : '팬 허브');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
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
                        const Text(
                          '마이팀',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textDisabled,
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
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      teamSubtitle,
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
              const SizedBox(width: 8),
              _StatusPill(label: statusLabel, color: teamColor),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  label: '오늘',
                  value: todayLabel,
                  color: AppColors.live,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroMetric(
                  label: '순위',
                  value: rankLabel,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroMetric(
                  label: '최근',
                  value: recentLabel,
                  color: teamColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEditTeam,
                  icon: const _MoreGlyph(
                    kind: _MoreIconKind.team,
                    color: AppColors.textPrimary,
                    size: 16,
                  ),
                  label: const Text('마이팀 변경'),
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
                  onPressed: onOpenPrimary,
                  icon: const _MoreGlyph(
                    kind: _MoreIconKind.game,
                    color: AppColors.background,
                    size: 16,
                  ),
                  label: const Text('오늘 경기'),
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

  String _teamSubtitle(TeamStanding? standing) {
    if (standing == null) {
      return '순위와 최근 흐름을 불러오고 있습니다.';
    }
    return '${standing.wins}승 ${standing.losses}패 ${standing.draws}무 · 승률 ${standing.pct}';
  }
}

class _HeroMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _HeroMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreInsightSection extends StatelessWidget {
  final HomeAggregate? aggregate;
  final bool isLoading;
  final bool hasError;

  const _MoreInsightSection({
    required this.aggregate,
    required this.isLoading,
    required this.hasError,
  });

  @override
  Widget build(BuildContext context) {
    final items = _insightItems(aggregate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: '오늘 챙길 정보',
          actionLabel: '뉴스 브리프',
          onAction: () => context.go('/news'),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: hasError
              ? const _InsightStatusRow(
                  icon: Icons.cloud_off_outlined,
                  title: '정보 업데이트 대기',
                  subtitle: '경기, 순위, 기록 브리프를 다시 불러오면 최신 정보가 표시됩니다.',
                )
              : (items.isEmpty && isLoading)
              ? const _InsightStatusRow(
                  icon: Icons.sync_rounded,
                  title: '오늘 정보 불러오는 중',
                  subtitle: '마이팀 경기, 순위 변동, 기록 신호를 묶고 있습니다.',
                )
              : Column(
                  children: [
                    for (int index = 0; index < items.length; index++) ...[
                      _MoreInsightRow(item: items[index]),
                      if (index != items.length - 1)
                        const Divider(
                          color: AppColors.cardSub,
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  static List<_MoreInfoItem> _insightItems(HomeAggregate? aggregate) {
    final briefItems = aggregate?.kboBrief?.items ?? const <HomeKboBriefItem>[];
    if (briefItems.isNotEmpty) {
      return briefItems
          .take(4)
          .map((item) {
            return _MoreInfoItem(
              eyebrow: item.eyebrow,
              title: item.title,
              subtitle: item.subtitle,
              route: item.route,
              icon: _iconFor(item.type, item.route),
              color: _colorFor(item.type, item.route),
            );
          })
          .toList(growable: false);
    }

    final quickItems = aggregate?.quickItems ?? const <HomeQuickItem>[];
    if (quickItems.isNotEmpty) {
      return quickItems
          .take(4)
          .map((item) {
            return _MoreInfoItem(
              eyebrow: item.eyebrow,
              title: item.title,
              subtitle: item.subtitle,
              route: item.route,
              icon: _iconFor('', item.route),
              color: _colorFor('', item.route),
            );
          })
          .toList(growable: false);
    }

    return const [
      _MoreInfoItem(
        eyebrow: 'SCHEDULE',
        title: '오늘 경기 일정',
        subtitle: '전 구장 경기와 시작 시간을 확인합니다',
        route: '/schedule',
        icon: _MoreIconKind.game,
        color: AppColors.live,
      ),
      _MoreInfoItem(
        eyebrow: 'RECORDS',
        title: '리그 기록 TOP',
        subtitle: '타자와 투수 리더보드를 빠르게 엽니다',
        route: '/records',
        icon: _MoreIconKind.records,
        color: AppColors.positive,
      ),
      _MoreInfoItem(
        eyebrow: 'NEWS',
        title: '경기 브리프',
        subtitle: '경기, 순위, 기록 신호를 짧은 카드로 봅니다',
        route: '/news',
        icon: _MoreIconKind.news,
        color: AppColors.accent,
      ),
    ];
  }

  static _MoreIconKind _iconFor(String type, String route) {
    if (route.startsWith('/game')) {
      return _MoreIconKind.game;
    }
    if (route.startsWith('/records')) {
      return _MoreIconKind.records;
    }
    if (route.startsWith('/standings') || type == 'standings') {
      return _MoreIconKind.standings;
    }
    if (route.startsWith('/schedule')) {
      return _MoreIconKind.game;
    }
    return _MoreIconKind.news;
  }

  static Color _colorFor(String type, String route) {
    if (route.startsWith('/game')) {
      return AppColors.live;
    }
    if (route.startsWith('/records')) {
      return AppColors.positive;
    }
    if (route.startsWith('/standings') || type == 'standings') {
      return AppColors.accent;
    }
    if (route.startsWith('/schedule')) {
      return AppColors.ballYellow;
    }
    return AppColors.textSecondary;
  }
}

class _MoreInsightRow extends StatelessWidget {
  final _MoreInfoItem item;

  const _MoreInsightRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: () => context.go(
        sanitizeAppRoute(item.route, fallback: '/news') ?? '/news',
      ),
      pressedScale: 0.985,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 74),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              _MoreIconWell(kind: item.icon, color: item.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.eyebrow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: item.color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textDisabled,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
}

class _InsightStatusRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InsightStatusRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
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

class _MoreShortcutGrid extends StatelessWidget {
  const _MoreShortcutGrid();

  static const _items = [
    _ShortcutItem(
      title: '경기 일정',
      subtitle: '오늘과 이번 주',
      route: '/schedule',
      icon: _MoreIconKind.game,
      color: AppColors.live,
    ),
    _ShortcutItem(
      title: '순위표',
      subtitle: '게임차와 흐름',
      route: '/standings',
      icon: _MoreIconKind.standings,
      color: AppColors.accent,
    ),
    _ShortcutItem(
      title: '기록실',
      subtitle: '선수와 팀 기록',
      route: '/records',
      icon: _MoreIconKind.records,
      color: AppColors.positive,
    ),
    _ShortcutItem(
      title: '뉴스',
      subtitle: '짧은 경기 브리프',
      route: '/news',
      icon: _MoreIconKind.news,
      color: AppColors.ballYellow,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: '빠른 이동'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _ShortcutCard(item: _items[0])),
            const SizedBox(width: 10),
            Expanded(child: _ShortcutCard(item: _items[1])),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _ShortcutCard(item: _items[2])),
            const SizedBox(width: 10),
            Expanded(child: _ShortcutCard(item: _items[3])),
          ],
        ),
      ],
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  final _ShortcutItem item;

  const _ShortcutCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: () => context.go(
        sanitizeAppRoute(item.route, fallback: '/settings') ?? '/settings',
      ),
      pressedScale: 0.97,
      child: Container(
        height: 94,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _MoreGlyph(kind: item.icon, color: item.color, size: 21),
                const Spacer(),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textDisabled,
                ),
              ],
            ),
            const Spacer(),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(
              item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textDisabled,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationInboxPreviewCard extends StatelessWidget {
  const _NotificationInboxPreviewCard();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<NotificationInboxEntry>>(
      future: NotificationInboxService.instance.loadEntries(),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <NotificationInboxEntry>[];
        final unreadCount = entries.where((entry) => !entry.read).length;
        final latest = entries.isEmpty ? null : entries.first;
        final subtitle = latest == null
            ? '득점, 홈런, 타석, 브리프가 수신 순서로 쌓입니다'
            : '${_previewTitle(latest)} · ${_previewTime(latest.receivedAt)}';

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
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.live.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.live.withValues(alpha: 0.36),
                        ),
                      ),
                      child: const Icon(
                        Icons.notifications_active_outlined,
                        color: AppColors.live,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '푸시 알림 모아보기',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textDisabled,
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
                        color: AppColors.cardSub,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.divider),
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
                              ? AppColors.textSecondary
                              : AppColors.live,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppColors.textDisabled,
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

  String _previewTitle(NotificationInboxEntry entry) {
    if (entry.title.isNotEmpty) {
      return entry.title;
    }
    return switch (entry.type) {
      'baseball_info' => '야구 브리프',
      'scoring' => '득점 알림',
      'hit' => '안타 알림',
      'homerun' => '홈런 알림',
      'at_bat' => '타석 알림',
      _ => '푸시 수신',
    };
  }

  String _previewTime(DateTime receivedAt) {
    final local = receivedAt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _MoreSurfaceCard extends StatelessWidget {
  const _MoreSurfaceCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: '앱 밖 표면'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: const Column(
            children: [
              _SurfaceRow(
                icon: _MoreIconKind.push,
                title: '푸시',
                subtitle: '득점, 홈런, 역전처럼 놓치면 안 되는 장면',
                color: AppColors.live,
              ),
              Divider(
                color: AppColors.cardSub,
                height: 1,
                indent: 16,
                endIndent: 16,
              ),
              _SurfaceRow(
                icon: _MoreIconKind.live,
                title: '라이브 액티비티',
                subtitle: '따라가는 경기의 점수와 이닝을 잠금화면에 유지',
                color: AppColors.accent,
              ),
              Divider(
                color: AppColors.cardSub,
                height: 1,
                indent: 16,
                endIndent: 16,
              ),
              _SurfaceRow(
                icon: _MoreIconKind.brief,
                title: '브리프',
                subtitle: '비경기일과 월요일에 일정, 순위, 기록을 묶음 요약',
                color: AppColors.positive,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SurfaceRow extends StatelessWidget {
  final _MoreIconKind icon;
  final String title;
  final String subtitle;
  final Color color;

  const _SurfaceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          _MoreIconWell(
            kind: icon,
            color: color,
            size: 34,
            glyphSize: 19,
            showBorder: false,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDisabled,
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

class _MoreIconWell extends StatelessWidget {
  final _MoreIconKind kind;
  final Color color;
  final double size;
  final double glyphSize;
  final bool showBorder;

  const _MoreIconWell({
    required this.kind,
    required this.color,
    this.size = 38,
    this.glyphSize = 20,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: showBorder ? 0.16 : 0.11),
        borderRadius: BorderRadius.circular(8),
        border: showBorder
            ? Border.all(color: color.withValues(alpha: 0.35))
            : null,
      ),
      child: _MoreGlyph(kind: kind, color: color, size: glyphSize),
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
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (kind) {
      case _MoreIconKind.game:
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.36, stroke);
        final leftSeam = Path()
          ..moveTo(w * 0.36, h * 0.22)
          ..cubicTo(w * 0.24, h * 0.36, w * 0.24, h * 0.64, w * 0.36, h * 0.78);
        final rightSeam = Path()
          ..moveTo(w * 0.64, h * 0.22)
          ..cubicTo(w * 0.76, h * 0.36, w * 0.76, h * 0.64, w * 0.64, h * 0.78);
        canvas.drawPath(leftSeam, stroke);
        canvas.drawPath(rightSeam, stroke);
        break;
      case _MoreIconKind.standings:
        _drawRoundedBar(canvas, fill, w * 0.18, h * 0.50, w * 0.15, h * 0.30);
        _drawRoundedBar(canvas, fill, w * 0.43, h * 0.32, w * 0.15, h * 0.48);
        _drawRoundedBar(canvas, fill, w * 0.68, h * 0.20, w * 0.15, h * 0.60);
        break;
      case _MoreIconKind.records:
        final trend = Path()
          ..moveTo(w * 0.16, h * 0.72)
          ..lineTo(w * 0.38, h * 0.50)
          ..lineTo(w * 0.58, h * 0.57)
          ..lineTo(w * 0.82, h * 0.28);
        canvas.drawPath(trend, stroke);
        for (final point in [
          Offset(w * 0.16, h * 0.72),
          Offset(w * 0.38, h * 0.50),
          Offset(w * 0.58, h * 0.57),
          Offset(w * 0.82, h * 0.28),
        ]) {
          canvas.drawCircle(point, strokeWidth * 0.72, fill);
        }
        break;
      case _MoreIconKind.news:
        final page = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.2, h * 0.12, w * 0.6, h * 0.76),
          Radius.circular(w * 0.08),
        );
        canvas.drawRRect(page, stroke);
        canvas.drawLine(
          Offset(w * 0.34, h * 0.36),
          Offset(w * 0.66, h * 0.36),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.34, h * 0.52),
          Offset(w * 0.66, h * 0.52),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.34, h * 0.68),
          Offset(w * 0.54, h * 0.68),
          stroke,
        );
        break;
      case _MoreIconKind.push:
        final bell = Path()
          ..moveTo(w * 0.5, h * 0.18)
          ..cubicTo(w * 0.35, h * 0.2, w * 0.3, h * 0.34, w * 0.3, h * 0.52)
          ..lineTo(w * 0.3, h * 0.62)
          ..cubicTo(w * 0.27, h * 0.68, w * 0.22, h * 0.71, w * 0.22, h * 0.78)
          ..lineTo(w * 0.78, h * 0.78)
          ..cubicTo(w * 0.78, h * 0.71, w * 0.73, h * 0.68, w * 0.7, h * 0.62)
          ..lineTo(w * 0.7, h * 0.52)
          ..cubicTo(w * 0.7, h * 0.34, w * 0.65, h * 0.2, w * 0.5, h * 0.18);
        canvas.drawPath(bell, stroke);
        canvas.drawLine(
          Offset(w * 0.42, h * 0.88),
          Offset(w * 0.58, h * 0.88),
          stroke,
        );
        break;
      case _MoreIconKind.live:
        final phone = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.28, h * 0.1, w * 0.44, h * 0.8),
          Radius.circular(w * 0.09),
        );
        canvas.drawRRect(phone, stroke);
        canvas.drawLine(
          Offset(w * 0.42, h * 0.22),
          Offset(w * 0.58, h * 0.22),
          stroke,
        );
        canvas.drawCircle(Offset(w * 0.5, h * 0.76), strokeWidth * 0.55, fill);
        break;
      case _MoreIconKind.brief:
        _drawBriefLine(canvas, fill, w, h, 0.22, 0.56);
        _drawBriefLine(canvas, fill, w, h, 0.44, 0.68);
        _drawBriefLine(canvas, fill, w, h, 0.66, 0.48);
        break;
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

  void _drawRoundedBar(
    Canvas canvas,
    Paint paint,
    double left,
    double top,
    double width,
    double height,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, width, height),
        Radius.circular(width * 0.5),
      ),
      paint,
    );
  }

  void _drawBriefLine(
    Canvas canvas,
    Paint paint,
    double w,
    double h,
    double topFactor,
    double widthFactor,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.2, h * topFactor, w * widthFactor, h * 0.12),
        Radius.circular(h * 0.06),
      ),
      paint,
    );
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
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (actionLabel != null && onAction != null)
          AppPressable(
            onTap: onAction,
            child: Row(
              children: [
                Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textSecondary,
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
    if (team == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.cardSub,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: const Icon(
          Icons.shield_outlined,
          color: AppColors.textSecondary,
          size: 26,
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: CachedNetworkImage(
        imageUrl: team!.logoUrl,
        fit: BoxFit.contain,
        placeholder: (_, _) => const SizedBox.shrink(),
        errorWidget: (_, _, _) => Center(
          child: Text(
            team!.shortName,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _MoreInfoItem {
  final String eyebrow;
  final String title;
  final String subtitle;
  final String route;
  final _MoreIconKind icon;
  final Color color;

  const _MoreInfoItem({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.icon,
    required this.color,
  });
}

class _ShortcutItem {
  final String title;
  final String subtitle;
  final String route;
  final _MoreIconKind icon;
  final Color color;

  const _ShortcutItem({
    required this.title,
    required this.subtitle,
    required this.route,
    required this.icon,
    required this.color,
  });
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
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '시행일 $updatedAt',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textDisabled,
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
          const Divider(color: AppColors.divider, height: 1),
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
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      section.body,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
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
        '마이팀, 알림 설정, 경기 따라가기 상태처럼 앱 사용에 필요한 설정을 저장합니다. 푸시 알림을 쓰는 경우 기기 토큰과 구독 토픽이 알림 발송을 위해 사용될 수 있습니다.',
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

class _MyTeamCard extends StatelessWidget {
  final KboTeam? team;

  const _MyTeamCard({required this.team});

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: () => context.go('/onboarding?mode=edit'),
      pressedScale: 0.975,
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
