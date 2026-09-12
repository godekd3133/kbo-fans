import 'package:flutter/material.dart';

import '../constants/team_data.dart';
import '../theme/app_theme.dart';
import 'app_motion.dart';
import 'kbo_team_logo_image.dart';

/// Shared visual primitives for the KBO Fans product surface.
///
/// These are intentionally small building blocks. Feature screens still own
/// their data and interaction logic, while spacing, surfaces, status language,
/// and team identity remain visually consistent across the app.
class AppUi {
  static const pageHorizontal = 16.0;
  static const sectionGap = 24.0;
  static const contentGap = 12.0;
  static const rowGap = 8.0;
  static const compactRadius = 8.0;
  static const heroRadius = 12.0;
  static const sheetRadius = 24.0;

  const AppUi._();
}

class AppSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? accentColor;
  final double radius;
  final bool showAccentRail;
  final BorderSide? borderSide;

  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.accentColor,
    this.radius = AppUi.compactRadius,
    this.showAccentRail = false,
    this.borderSide,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final accent = accentColor;
    final border =
        borderSide ??
        BorderSide(
          color: accent?.withValues(alpha: 0.32) ?? colors.divider,
          width: 1,
        );
    final content = Padding(padding: padding, child: child);
    final railContent = Padding(
      padding: const EdgeInsets.only(left: 3),
      child: content,
    );

    return Container(
      decoration: BoxDecoration(
        color: color ?? colors.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.fromBorderSide(border),
      ),
      clipBehavior: Clip.antiAlias,
      child: showAccentRail && accent != null
          ? Stack(
              children: [
                railContent,
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(width: 3, child: ColoredBox(color: accent)),
                  ),
                ),
              ],
            )
          : content,
    );
  }
}

class AppSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData actionIcon;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.actionIcon = Icons.chevron_right_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final action = actionLabel == null || onAction == null
        ? const SizedBox.shrink()
        : AppPressable(
            semanticLabel: actionLabel,
            onTap: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel!,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(actionIcon, size: 18, color: colors.textSecondary),
              ],
            ),
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 20,
              height: 1.05,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        action,
      ],
    );
  }
}

class AppPageHeader extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onBack;

  const AppPageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null && eyebrow!.isNotEmpty) ...[
          Text(
            eyebrow!,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 26,
            height: 1.05,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (onBack != null) ...[
              Tooltip(
                message: '뒤로',
                child: AppPressable(
                  semanticLabel: '뒤로',
                  onTap: onBack,
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.arrow_back_rounded, size: 22),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(child: titleBlock),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

class AppStatusPill extends StatelessWidget {
  final String label;
  final Color? color;
  final bool showDot;
  final EdgeInsetsGeometry padding;

  const AppStatusPill({
    super.key,
    required this.label,
    this.color,
    this.showDot = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final resolvedColor = color ?? colors.textSecondary;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: resolvedColor.withValues(alpha: 0.38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: resolvedColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class AppTeamIdentity extends StatelessWidget {
  final String teamId;
  final String fallbackLabel;
  final String? meta;
  final double logoSize;
  final bool alignEnd;
  final bool showFullName;

  const AppTeamIdentity({
    super.key,
    required this.teamId,
    required this.fallbackLabel,
    this.meta,
    this.logoSize = 48,
    this.alignEnd = false,
    this.showFullName = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final team = KboTeams.byId(teamId);
    final title = showFullName
        ? team?.name ?? fallbackLabel
        : team?.shortName ?? fallbackLabel;
    final text = Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            height: 1.15,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (meta != null && meta!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            meta!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.end : TextAlign.start,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
              height: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );

    return Row(
      mainAxisAlignment: alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: alignEnd
          ? [
              Flexible(child: text),
              const SizedBox(width: 8),
              KboTeamLogoImage(
                teamId: teamId,
                fallback: fallbackLabel,
                size: logoSize,
                padding: 0,
              ),
            ]
          : [
              KboTeamLogoImage(
                teamId: teamId,
                fallback: fallbackLabel,
                size: logoSize,
                padding: 0,
              ),
              const SizedBox(width: 8),
              Flexible(child: text),
            ],
    );
  }
}

class AppMetricLine extends StatelessWidget {
  final String label;
  final String value;
  final String? trailing;
  final VoidCallback? onTap;

  const AppMetricLine({
    super.key,
    required this.label,
    required this.value,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(
              trailing!,
              style: TextStyle(
                color: colors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
          if (onTap != null) ...[
            const SizedBox(width: 3),
            Icon(Icons.chevron_right_rounded, size: 19, color: colors.accent),
          ],
        ],
      ),
    );
    return onTap == null ? child : AppPressable(onTap: onTap, child: child);
  }
}
