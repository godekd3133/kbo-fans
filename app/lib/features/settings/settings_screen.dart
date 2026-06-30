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

    return Scaffold(
      body: SafeArea(
        child: AppPageFrame(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            children: [
              const Text(
                '더보기',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 16),

              _MoreHeroCard(
                team: team,
                teamColor: teamColor,
                onEditTeam: () => context.go('/onboarding?mode=edit'),
              ),
              const SizedBox(height: 16),

              const _NotificationInboxPreviewCard(),
              const SizedBox(height: 16),

              const _MoreShortcutGrid(),
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

enum _MoreIconKind { game, standings, records, news, team }

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
    final teamName = team?.name ?? '마이팀을 선택하세요';
    final teamSubtitle = team == null
        ? '홈과 알림 기준을 맞추려면 팀을 먼저 선택하세요.'
        : '홈과 알림 기준으로 사용 중입니다.';

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
            ],
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onEditTeam,
              icon: const _MoreGlyph(
                kind: _MoreIconKind.team,
                color: AppColors.textPrimary,
                size: 16,
              ),
              label: Text(team == null ? '마이팀 선택' : '마이팀 변경'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.divider),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
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
      route: '/schedule',
      icon: _MoreIconKind.game,
      color: AppColors.live,
    ),
    _ShortcutItem(
      title: '순위표',
      route: '/standings',
      icon: _MoreIconKind.standings,
      color: AppColors.accent,
    ),
    _ShortcutItem(
      title: '기록실',
      route: '/records',
      icon: _MoreIconKind.records,
      color: AppColors.positive,
    ),
    _ShortcutItem(
      title: '뉴스',
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
        height: 68,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            _MoreGlyph(kind: item.icon, color: item.color, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textDisabled,
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
                          const Text(
                            '최근 받은 알림을 확인합니다',
                            style: TextStyle(
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

class _ShortcutItem {
  final String title;
  final String route;
  final _MoreIconKind icon;
  final Color color;

  const _ShortcutItem({
    required this.title,
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
