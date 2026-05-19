import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/constants/team_data.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/game_status_label.dart';
import '../../../data/models/game.dart';

const _kboImageHeaders = {
  'Referer': 'https://www.koreabaseball.com/',
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
};

class MyTeamGameCard extends StatelessWidget {
  final Game game;
  final VoidCallback? onTap;

  const MyTeamGameCard({super.key, required this.game, this.onTap});

  @override
  Widget build(BuildContext context) {
    final awayTeam = KboTeams.byId(game.away.teamId);
    final homeTeam = KboTeams.byId(game.home.teamId);
    final isLive = game.status == GameStatus.live;
    final secondary = _secondaryText();
    final accent =
        awayTeam?.primaryColor ?? homeTeam?.primaryColor ?? AppColors.live;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.34),
              AppColors.card,
              AppColors.surface,
            ],
            stops: const [0, 0.48, 1],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.live.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.live.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.live,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isLive ? 'LIVE 경기중' : labelForGameStatus(game.status),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const Text(
                  '방금 업데이트',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _teamBlock(
                    game.away.teamId,
                    game.away.shortName,
                    '원정',
                  ),
                ),
                SizedBox(
                  width: 124,
                  child: Column(
                    children: [
                      Text(
                        '${_scoreText(game.away.score)}:${_scoreText(game.home.score)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 42,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        secondary ?? labelForGameStatus(game.status),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: isLive
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _teamBlock(game.home.teamId, game.home.shortName, '홈'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _statusTile(
                    '안타',
                    '${game.away.hits}-${game.home.hits}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statusTile(
                    '실책',
                    '${game.away.errors}-${game.home.errors}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statusTile(
                    '볼넷',
                    '${game.away.walks}-${game.home.walks}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.chevron_right_rounded, size: 18),
                    label: const Text('중계 보기'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.notifications_outlined, size: 17),
                    label: const Text('핵심 알림'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.divider),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _scoreText(int? score) => score == null ? '-' : '$score';

  Widget _teamBlock(String teamId, String shortName, String caption) {
    return Column(
      children: [
        _teamLogo(teamId, shortName, 48),
        const SizedBox(height: 8),
        Text(
          shortName,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _statusTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.textDisabled),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ],
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
            fontSize: size * 0.28,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
