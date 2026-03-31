import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/constants/team_data.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/game_status_label.dart';
import '../../../core/widgets/game_status_badge.dart';
import '../../../data/models/game.dart';

class MyTeamGameCard extends StatelessWidget {
  final Game game;
  final VoidCallback? onTap;

  const MyTeamGameCard({super.key, required this.game, this.onTap});

  @override
  Widget build(BuildContext context) {
    final awayTeam = KboTeams.byId(game.away.teamId);
    final isLive = game.status == GameStatus.live;
    final secondary = _secondaryText();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // MY TEAM 라벨
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'MY TEAM',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: awayTeam?.primaryColor ?? AppColors.live,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 스코어 영역
            Row(
              children: [
                // 어웨이
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Column(
                        children: [
                          _teamLogo(game.away.teamId, 48),
                          const SizedBox(height: 4),
                          Text(
                            game.away.shortName,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '${game.away.score}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                // 이닝
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      GameStatusBadge.forGame(
                        game.status,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        fontSize: 11,
                      ),
                      if (secondary != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          secondary,
                          style: TextStyle(
                            fontSize: 13,
                            color: isLive
                                ? AppColors.live
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (isLive) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.live,
                            shape: BoxShape.circle,
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
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        children: [
                          _teamLogo(game.home.teamId, 48),
                          const SizedBox(height: 4),
                          Text(
                            game.home.shortName,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 이닝별 미니 스코어
            _inningTable(),
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

  Widget _inningTable() {
    const headerStyle = TextStyle(fontSize: 10, color: AppColors.textDisabled);
    const dataStyle = TextStyle(fontSize: 10, color: AppColors.textSecondary);
    const boldStyle = TextStyle(
      fontSize: 10,
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w700,
    );

    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            _cell('', headerStyle),
            for (int i = 1; i <= 9; i++) _cell('$i', headerStyle),
            _cell('R', headerStyle),
            _cell('H', headerStyle),
            _cell('E', headerStyle),
            _cell('B', headerStyle),
          ],
        ),
        _scoreRow(
          game.away.shortName,
          game.away.innings,
          game.away,
          dataStyle,
          boldStyle,
        ),
        _scoreRow(
          game.home.shortName,
          game.home.innings,
          game.home,
          dataStyle,
          boldStyle,
        ),
      ],
    );
  }

  TableRow _scoreRow(
    String name,
    List<int?> innings,
    TeamScore team,
    TextStyle dataStyle,
    TextStyle boldStyle,
  ) {
    return TableRow(
      children: [
        _cell(name, dataStyle),
        for (int i = 0; i < 9; i++)
          _cell(
            i < innings.length && innings[i] != null ? '${innings[i]}' : '-',
            dataStyle,
          ),
        _cell('${team.score}', boldStyle),
        _cell('${team.hits}', boldStyle),
        _cell('${team.errors}', boldStyle),
        _cell('${team.walks}', boldStyle),
      ],
    );
  }

  Widget _cell(String text, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(text, textAlign: TextAlign.center, style: style),
    );
  }

  Widget _teamLogo(String teamId, double size) {
    final team = KboTeams.byId(teamId);
    return CachedNetworkImage(
      imageUrl: team?.logoUrl ?? '',
      width: size,
      height: size,
      placeholder: (_, _) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.cardSub,
          shape: BoxShape.circle,
        ),
      ),
      errorWidget: (_, _, _) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.cardSub,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            team?.shortName ?? '',
            style: TextStyle(
              fontSize: size * 0.25,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
