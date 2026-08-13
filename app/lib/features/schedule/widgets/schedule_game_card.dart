import 'package:flutter/material.dart';

import '../../../core/constants/team_data.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/game_status_label.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/game_status_badge.dart';
import '../../../core/widgets/kbo_team_logo_image.dart';
import '../../../data/models/schedule.dart';

class ScheduleGameCard extends StatelessWidget {
  final ScheduleGame game;
  final String? dateLabel;
  final String? ticketSummary;
  final String? myTeamId;
  final VoidCallback? onTap;
  final bool showTeamLogos;

  const ScheduleGameCard({
    super.key,
    required this.game,
    this.dateLabel,
    this.ticketSummary,
    this.myTeamId,
    this.onTap,
    this.showTeamLogos = true,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedMyTeamId = myTeamId?.trim();
    final isMyTeamGame =
        normalizedMyTeamId != null &&
        normalizedMyTeamId.isNotEmpty &&
        (game.awayId == normalizedMyTeamId ||
            game.homeId == normalizedMyTeamId);
    final colors = AppTheme.colorsOf(context);
    final myTeamColor = colors.readableAccent(
      KboTeams.byId(normalizedMyTeamId ?? '')?.primaryColor ?? colors.accent,
    );
    final cardColor = isMyTeamGame
        ? Color.alphaBlend(myTeamColor.withValues(alpha: 0.18), AppColors.card)
        : AppColors.card.withValues(alpha: 0.92);
    final useLargeTextLayout = MediaQuery.textScalerOf(context).scale(1) >= 1.6;

    return AppPressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isMyTeamGame
                ? myTeamColor.withValues(alpha: 0.62)
                : AppColors.divider.withValues(alpha: 0.86),
          ),
          boxShadow: isMyTeamGame
              ? [
                  BoxShadow(
                    color: myTeamColor.withValues(alpha: 0.16),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            if (isMyTeamGame)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 4, color: myTeamColor),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (useLargeTextLayout) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (dateLabel != null)
                          Text(
                            dateLabel!,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSupporting,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        Text(
                          game.time,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (game.status.isNotEmpty)
                          GameStatusBadge.forSchedule(
                            game.status,
                            statusLabel: game.statusLabel,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            fontSize: 11,
                          ),
                        if (isMyTeamGame)
                          _MyTeamBadge(
                            key: ValueKey(
                              'schedule-my-team-badge-${game.gameId}',
                            ),
                            color: myTeamColor,
                          ),
                      ],
                    ),
                    if (game.stadium.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        game.stadium,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSupporting,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ] else
                    Row(
                      children: [
                        if (dateLabel != null) ...[
                          Text(
                            dateLabel!,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSupporting,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          game.time,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (game.status.isNotEmpty)
                          GameStatusBadge.forSchedule(
                            game.status,
                            statusLabel: game.statusLabel,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            fontSize: 11,
                          ),
                        if (isMyTeamGame) ...[
                          const SizedBox(width: 8),
                          _MyTeamBadge(
                            key: ValueKey(
                              'schedule-my-team-badge-${game.gameId}',
                            ),
                            color: myTeamColor,
                          ),
                        ],
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            game.stadium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSupporting,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 13),
                  if (useLargeTextLayout)
                    Column(
                      children: [
                        _TeamInfo(
                          teamId: game.awayId,
                          fallbackName: game.awayName,
                          showLogo: showTeamLogos,
                          highlighted: game.awayId == normalizedMyTeamId,
                          accentColor: myTeamColor,
                        ),
                        const SizedBox(height: 10),
                        _ScoreOrVersus(
                          awayScore: game.awayScore,
                          homeScore: game.homeScore,
                          status: game.status,
                        ),
                        const SizedBox(height: 10),
                        _TeamInfo(
                          teamId: game.homeId,
                          fallbackName: game.homeName,
                          showLogo: showTeamLogos,
                          highlighted: game.homeId == normalizedMyTeamId,
                          accentColor: myTeamColor,
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: _TeamInfo(
                            teamId: game.awayId,
                            fallbackName: game.awayName,
                            alignEnd: true,
                            showLogo: showTeamLogos,
                            highlighted: game.awayId == normalizedMyTeamId,
                            accentColor: myTeamColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _ScoreOrVersus(
                          awayScore: game.awayScore,
                          homeScore: game.homeScore,
                          status: game.status,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TeamInfo(
                            teamId: game.homeId,
                            fallbackName: game.homeName,
                            showLogo: showTeamLogos,
                            highlighted: game.homeId == normalizedMyTeamId,
                            accentColor: myTeamColor,
                          ),
                        ),
                      ],
                    ),
                  if (ticketSummary != null &&
                      shouldShowTicketInfoForScheduleStatus(game.status)) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.confirmation_num_outlined,
                          size: 14,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            ticketSummary!,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamInfo extends StatelessWidget {
  final String teamId;
  final String fallbackName;
  final bool alignEnd;
  final bool showLogo;
  final bool highlighted;
  final Color accentColor;

  const _TeamInfo({
    required this.teamId,
    required this.fallbackName,
    this.alignEnd = false,
    this.showLogo = true,
    this.highlighted = false,
    this.accentColor = Colors.transparent,
  });

  @override
  Widget build(BuildContext context) {
    final team = KboTeams.byId(teamId);
    final shortName = team?.shortName ?? fallbackName;
    final teamNameStyle = TextStyle(
      fontSize: 15,
      fontWeight: highlighted ? FontWeight.w900 : FontWeight.w800,
      color: highlighted ? AppColors.textPrimary : null,
    );

    return Row(
      mainAxisAlignment: alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        if (alignEnd) ...[
          Flexible(
            child: Text(
              shortName,
              overflow: TextOverflow.ellipsis,
              style: teamNameStyle,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (showLogo)
          _TeamLogo(
            teamId: teamId,
            size: 38,
            highlighted: highlighted,
            accentColor: accentColor,
          ),
        if (!showLogo)
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.cardSub,
              shape: BoxShape.circle,
              border: highlighted
                  ? Border.all(color: accentColor.withValues(alpha: 0.7))
                  : null,
            ),
            child: Center(
              child: Text(
                shortName.isEmpty ? '?' : shortName.substring(0, 1),
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        if (!alignEnd) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              shortName,
              overflow: TextOverflow.ellipsis,
              style: teamNameStyle,
            ),
          ),
        ],
      ],
    );
  }
}

class _TeamLogo extends StatelessWidget {
  final String teamId;
  final double size;
  final bool highlighted;
  final Color accentColor;

  const _TeamLogo({
    required this.teamId,
    required this.size,
    this.highlighted = false,
    this.accentColor = Colors.transparent,
  });

  @override
  Widget build(BuildContext context) {
    final team = KboTeams.byId(teamId);
    final logo = KboTeamLogoImage(
      teamId: teamId,
      fallback: team?.shortName ?? '',
      size: size,
      padding: 0,
    );

    if (!highlighted) {
      return logo;
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accentColor.withValues(alpha: 0.72)),
      ),
      child: logo,
    );
  }
}

class _MyTeamBadge extends StatelessWidget {
  final Color color;

  const _MyTeamBadge({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.52)),
      ),
      child: Text(
        '마이팀',
        style: TextStyle(
          fontSize: 10,
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ScoreOrVersus extends StatelessWidget {
  final int? awayScore;
  final int? homeScore;
  final String status;

  const _ScoreOrVersus({
    required this.awayScore,
    required this.homeScore,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final hasScore =
        status.toUpperCase() != 'SCHEDULED' &&
        awayScore != null &&
        homeScore != null;
    if (!hasScore) {
      return Text(
        'vs',
        style: TextStyle(fontSize: 12, color: AppColors.textSupporting),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppMotionValue(
          value: 'away-$awayScore',
          child: Text(
            '$awayScore',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            ':',
            style: TextStyle(
              fontSize: 18,
              color: AppColors.textSupporting,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        AppMotionValue(
          value: 'home-$homeScore',
          child: Text(
            '$homeScore',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}
