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
  final VoidCallback? onTap;
  final bool showTeamLogos;

  const ScheduleGameCard({
    super.key,
    required this.game,
    this.dateLabel,
    this.ticketSummary,
    this.onTap,
    this.showTeamLogos = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                if (dateLabel != null) ...[
                  Text(
                    dateLabel!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textDisabled,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  game.time,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                if (game.status.isNotEmpty)
                  GameStatusBadge.forSchedule(
                    game.status,
                    statusLabel: game.statusLabel,
                  ),
                const Spacer(),
                Text(
                  game.stadium,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textDisabled,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TeamInfo(
                    teamId: game.awayId,
                    fallbackName: game.awayName,
                    alignEnd: true,
                    showLogo: showTeamLogos,
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
                  ),
                ),
              ],
            ),
            if (ticketSummary != null &&
                shouldShowTicketInfoForScheduleStatus(game.status)) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.confirmation_num_outlined,
                    size: 14,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ticketSummary!,
                      style: const TextStyle(
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
    );
  }
}

class _TeamInfo extends StatelessWidget {
  final String teamId;
  final String fallbackName;
  final bool alignEnd;
  final bool showLogo;

  const _TeamInfo({
    required this.teamId,
    required this.fallbackName,
    this.alignEnd = false,
    this.showLogo = true,
  });

  @override
  Widget build(BuildContext context) {
    final team = KboTeams.byId(teamId);
    final shortName = team?.shortName ?? fallbackName;

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
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (showLogo) _TeamLogo(teamId: teamId, size: 34),
        if (!showLogo)
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: AppColors.cardSub,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                shortName.isEmpty ? '?' : shortName.substring(0, 1),
                style: const TextStyle(
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
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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

  const _TeamLogo({required this.teamId, required this.size});

  @override
  Widget build(BuildContext context) {
    final team = KboTeams.byId(teamId);
    return KboTeamLogoImage(
      teamId: teamId,
      fallback: team?.shortName ?? '',
      size: size,
      padding: 0,
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
      return const Text(
        'vs',
        style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppMotionValue(
          value: 'away-$awayScore',
          child: Text(
            '$awayScore',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            ':',
            style: TextStyle(fontSize: 16, color: AppColors.textDisabled),
          ),
        ),
        AppMotionValue(
          value: 'home-$homeScore',
          child: Text(
            '$homeScore',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
