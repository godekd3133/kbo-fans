import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/constants/team_data.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/game.dart';

class GameCard extends StatelessWidget {
  final Game game;
  final VoidCallback? onTap;

  const GameCard({super.key, required this.game, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isLive = game.status == GameStatus.live;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // 어웨이
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _teamLogo(game.away.teamId, 28),
                  const SizedBox(width: 8),
                  Text(game.away.shortName, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                  const SizedBox(width: 12),
                  Text('${game.away.score}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            // 이닝
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                game.inning,
                style: TextStyle(
                  fontSize: 12,
                  color: isLive ? AppColors.live : AppColors.textDisabled,
                  fontWeight: isLive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            // 홈
            Expanded(
              child: Row(
                children: [
                  Text('${game.home.score}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 12),
                  Text(game.home.shortName, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                  const SizedBox(width: 8),
                  _teamLogo(game.home.teamId, 28),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamLogo(String teamId, double size) {
    final team = KboTeams.byId(teamId);
    return CachedNetworkImage(
      imageUrl: team?.logoUrl ?? '',
      width: size,
      height: size,
      placeholder: (_, _) => Container(
        width: size, height: size,
        decoration: BoxDecoration(color: AppColors.cardSub, shape: BoxShape.circle),
      ),
      errorWidget: (_, _, _) => Container(
        width: size, height: size,
        decoration: BoxDecoration(color: AppColors.cardSub, shape: BoxShape.circle),
        child: Center(child: Text(team?.shortName ?? '', style: TextStyle(fontSize: size * 0.3, color: AppColors.textSecondary))),
      ),
    );
  }
}
