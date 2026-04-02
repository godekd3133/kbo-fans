import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/constants/team_data.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/game_status_label.dart';
import '../../../core/widgets/game_status_badge.dart';
import '../../../data/models/game.dart';

const _kboImageHeaders = {
  'Referer': 'https://www.koreabaseball.com/',
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
};

class GameCard extends StatelessWidget {
  final Game game;
  final VoidCallback? onTap;

  const GameCard({super.key, required this.game, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isLive = game.status == GameStatus.live;
    final secondary = _secondaryText();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 82,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                  _teamLogo(game.away.teamId, game.away.shortName, 28),
                  const SizedBox(width: 8),
                  Text(
                    game.away.shortName,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${game.away.score}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
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
                  Text(
                    '${game.home.score}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    game.home.shortName,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _teamLogo(game.home.teamId, game.home.shortName, 28),
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
    );
    final label = labelForGameStatus(game.status);
    return text == label ? null : text;
  }

  Widget _teamLogo(String teamId, String shortName, double size) {
    final team = KboTeams.resolve(
      id: teamId,
      name: shortName,
      shortName: shortName,
    );
    final imageUrl = team?.logoUrl ?? '';
    if (imageUrl.isEmpty) {
      return _logoFallback(team?.shortName ?? shortName, size);
    }
    return Image(
      image: CachedNetworkImageProvider(imageUrl, headers: _kboImageHeaders),
      width: size,
      height: size,
      errorBuilder: (_, _, _) =>
          _logoFallback(team?.shortName ?? shortName, size),
    );
  }

  Widget _logoFallback(String shortName, double size) {
    final label = shortName.isEmpty ? '?' : shortName.substring(0, 1);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: size * 0.34,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
