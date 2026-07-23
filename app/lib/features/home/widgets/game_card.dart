import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/game_status_label.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/game_status_badge.dart';
import '../../../core/widgets/kbo_team_logo_image.dart';
import '../../../data/models/game.dart';

class GameCard extends StatelessWidget {
  final Game game;
  final VoidCallback? onTap;

  const GameCard({super.key, required this.game, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isLive = game.status == GameStatus.live;
    final secondary = _secondaryText();
    final showScore =
        game.status == GameStatus.live ||
        game.status == GameStatus.final_ ||
        game.status == GameStatus.suspended;

    return AppPressable(
      onTap: onTap,
      child: Container(
        height: 92,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            // 어웨이
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _teamLogo(game.away.teamId, game.away.shortName, 34),
                  const SizedBox(width: 8),
                  Text(
                    game.away.shortName,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  AppMotionValue(
                    value: 'away-${game.away.displayScore}',
                    child: Text(
                      showScore ? game.away.displayScore : '–',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 상태
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GameStatusBadge.forGame(
                    game.status,
                    statusLabel: game.statusLabel,
                    fontSize: 10,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  if (secondary != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      secondary,
                      style: TextStyle(
                        fontSize: 11,
                        color: isLive
                            ? AppColors.live
                            : AppColors.textSecondary,
                        fontWeight: isLive
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 홈
            Expanded(
              child: Row(
                children: [
                  AppMotionValue(
                    value: 'home-${game.home.displayScore}',
                    child: Text(
                      showScore ? game.home.displayScore : '–',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    game.home.shortName,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _teamLogo(game.home.teamId, game.home.shortName, 34),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _secondaryText() {
    final text = secondaryTextForGameStatus(
      game.status,
      inning: game.inning,
      startTime: game.startTime,
      statusLabel: game.statusLabel,
    );
    final label = labelForGameStatus(
      game.status,
      statusLabel: game.statusLabel,
    );
    return text == label ? null : text;
  }

  Widget _teamLogo(String teamId, String shortName, double size) {
    return KboTeamLogoImage(
      teamId: teamId,
      fallback: shortName,
      size: size,
      padding: 0,
    );
  }
}
