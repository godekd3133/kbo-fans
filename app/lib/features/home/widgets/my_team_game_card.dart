import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/constants/team_data.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/game_status_label.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../data/models/game.dart';

const _kboImageHeaders = {
  'Referer': 'https://www.koreabaseball.com/',
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
};

class MyTeamGameCard extends StatelessWidget {
  final Game game;
  final VoidCallback? onOpenDetail;
  final VoidCallback? onOpenRelay;
  final VoidCallback? onOpenAlert;
  final VoidCallback? onFollowGame;
  final bool isFollowing;
  final bool isFollowLoading;

  const MyTeamGameCard({
    super.key,
    required this.game,
    this.onOpenDetail,
    this.onOpenRelay,
    this.onOpenAlert,
    this.onFollowGame,
    this.isFollowing = false,
    this.isFollowLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final awayTeam = KboTeams.byId(game.away.teamId);
    final homeTeam = KboTeams.byId(game.home.teamId);
    final isLive = game.status == GameStatus.live;
    final secondary = _secondaryText();
    final accent =
        awayTeam?.primaryColor ?? homeTeam?.primaryColor ?? AppColors.live;
    final primaryAction = _primaryAction();
    final secondaryAction = _secondaryAction();
    final scoreText = _scoreboardText();

    return AppPressable(
      onTap: onOpenDetail,
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
                        isLive
                            ? 'LIVE 경기중'
                            : labelForGameStatus(
                                game.status,
                                statusLabel: game.statusLabel,
                              ),
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
                Text(
                  _stateMetaText(),
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
                      AppMotionValue(
                        value: '${game.away.score}:${game.home.score}',
                        child: Text(
                          scoreText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 42,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        secondary ??
                            labelForGameStatus(
                              game.status,
                              statusLabel: game.statusLabel,
                            ),
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
            if (game.hasTeamStats) ...[
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
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: primaryAction.onPressed,
                    icon: Icon(primaryAction.icon, size: 18),
                    label: Text(primaryAction.label),
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
                if (secondaryAction != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: secondaryAction.onPressed,
                      icon: Icon(secondaryAction.icon, size: 17),
                      label: Text(secondaryAction.label),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: secondaryAction.isActive
                            ? AppColors.positive
                            : AppColors.textPrimary,
                        side: BorderSide(
                          color: secondaryAction.isActive
                              ? AppColors.positive
                              : AppColors.divider,
                        ),
                        backgroundColor: secondaryAction.isActive
                            ? AppColors.positive.withValues(alpha: 0.12)
                            : null,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _scoreText(int? score) => score == null ? '-' : '$score';

  String _scoreboardText() {
    if (game.status == GameStatus.scheduled ||
        game.status == GameStatus.cancelled) {
      return 'vs';
    }
    return '${_scoreText(game.away.score)}:${_scoreText(game.home.score)}';
  }

  _CardAction _primaryAction() {
    final detail = onOpenDetail;
    return switch (game.status) {
      GameStatus.live => _CardAction(
        label: '중계 보기',
        icon: Icons.chevron_right_rounded,
        onPressed: onOpenRelay ?? detail,
      ),
      GameStatus.final_ => _CardAction(
        label: '경기 기록',
        icon: Icons.insert_chart_outlined_rounded,
        onPressed: detail,
      ),
      GameStatus.scheduled => _CardAction(
        label: '경기 정보',
        icon: Icons.info_outline_rounded,
        onPressed: detail,
      ),
      GameStatus.cancelled || GameStatus.suspended => _CardAction(
        label: '경기 정보',
        icon: Icons.info_outline_rounded,
        onPressed: detail,
      ),
    };
  }

  _CardAction? _secondaryAction() {
    final detail = onOpenDetail;
    return switch (game.status) {
      GameStatus.live => _CardAction(
        label: isFollowing ? '따라가는 중' : '따라가기',
        icon: isFollowing
            ? Icons.check_circle_rounded
            : Icons.notifications_active_outlined,
        onPressed: isFollowLoading
            ? null
            : onFollowGame ?? onOpenAlert ?? detail,
        isActive: isFollowing,
      ),
      GameStatus.final_ => _CardAction(
        label: '하이라이트',
        icon: Icons.play_circle_outline_rounded,
        onPressed: detail,
      ),
      GameStatus.scheduled => _CardAction(
        label: '알림 설정',
        icon: Icons.notifications_outlined,
        onPressed: onOpenAlert ?? detail,
      ),
      GameStatus.cancelled || GameStatus.suspended => null,
    };
  }

  String _stateMetaText() {
    return switch (game.status) {
      GameStatus.live => '방금 업데이트',
      GameStatus.final_ => '최종 기록',
      GameStatus.scheduled =>
        game.startTime.isEmpty ? '경기 예정' : '${game.startTime} 예정',
      GameStatus.cancelled =>
        game.statusLabel?.trim().isNotEmpty == true ? game.statusLabel! : '취소',
      GameStatus.suspended => '중단',
    };
  }

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
      statusLabel: game.statusLabel,
    );
    final label = labelForGameStatus(
      game.status,
      statusLabel: game.statusLabel,
    );
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
    final cacheSize = (size * 3).round();
    return Image(
      image: CachedNetworkImageProvider(
        imageUrl,
        headers: _kboImageHeaders,
        maxWidth: cacheSize,
        maxHeight: cacheSize,
      ),
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

class _CardAction {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isActive;

  const _CardAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isActive = false,
  });
}
