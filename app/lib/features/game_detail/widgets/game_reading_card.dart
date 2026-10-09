import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/game.dart';

class ScoringInning {
  final String label;
  final String teamName;
  final int runs;
  final String score;
  const ScoringInning(this.label, this.teamName, this.runs, this.score);
}

/// Only derive an inning narrative when the complete prefix agrees with both
/// official totals. Missing innings, corrected totals and negative cells are
/// not evidence of a scoreless inning.
List<ScoringInning> verifiedScoringInnings(Game game) {
  if (!game.hasVerifiedScore ||
      (game.status != GameStatus.live && game.status != GameStatus.final_)) {
    return const [];
  }
  final count = game.away.innings.length > game.home.innings.length
      ? game.away.innings.length
      : game.home.innings.length;
  final result = <ScoringInning>[];
  var away = 0;
  var home = 0;
  var missing = false;
  for (var inning = 0; inning < count; inning++) {
    for (var side = 0; side < 2; side++) {
      final team = side == 0 ? game.away : game.home;
      final value = inning < team.innings.length ? team.innings[inning] : null;
      if (value == null) {
        missing = true;
        continue;
      }
      if (missing || value < 0) return const [];
      if (side == 0) {
        away += value;
      } else {
        home += value;
      }
      if (value > 0) {
        result.add(
          ScoringInning(
            '${inning + 1}회${side == 0 ? '초' : '말'}',
            team.shortName,
            value,
            '$away : $home',
          ),
        );
      }
    }
  }
  if (away != game.away.score || home != game.home.score) return const [];
  return result;
}

class GameReadingCard extends StatelessWidget {
  final Game game;
  final VoidCallback? onOpenRelay;
  final VoidCallback? onOpenBoxscore;
  final VoidCallback? onOpenLineup;
  const GameReadingCard({
    super.key,
    required this.game,
    this.onOpenRelay,
    this.onOpenBoxscore,
    this.onOpenLineup,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final innings = verifiedScoringInnings(game);
    final latest = innings.length > 5
        ? innings.sublist(innings.length - 5)
        : innings;
    final scheduled = game.status == GameStatus.scheduled;
    final hasActions = scheduled
        ? onOpenLineup != null
        : (game.status == GameStatus.live ||
                  game.status == GameStatus.final_) &&
              (onOpenRelay != null || onOpenBoxscore != null);
    if (latest.isEmpty && !hasActions) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('game-reading-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (latest.isNotEmpty) ...[
            Text(
              innings.length > 5 ? '최근 5개 득점 이닝' : '득점 이닝',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            for (final inning in latest)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      inning.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                    Text(
                      '${inning.teamName} +${inning.runs}점',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      inning.score,
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.readableAccent(colors.accent),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (hasActions) ...[
            if (latest.isNotEmpty) const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (scheduled && onOpenLineup != null)
                  OutlinedButton.icon(
                    onPressed: onOpenLineup,
                    icon: const Icon(
                      Icons.format_list_numbered_rounded,
                      size: 16,
                    ),
                    label: const Text('선발·라인업'),
                  ),
                if (!scheduled &&
                    onOpenRelay != null &&
                    (game.status == GameStatus.live ||
                        game.status == GameStatus.final_))
                  OutlinedButton.icon(
                    onPressed: onOpenRelay,
                    icon: const Icon(Icons.notes_rounded, size: 16),
                    label: const Text('문자중계'),
                  ),
                if (onOpenBoxscore != null &&
                    (game.status == GameStatus.live ||
                        game.status == GameStatus.final_))
                  OutlinedButton.icon(
                    onPressed: onOpenBoxscore,
                    icon: const Icon(Icons.bar_chart_rounded, size: 16),
                    label: const Text('박스스코어'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
