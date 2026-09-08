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

String gameReadingHeadline(Game game) {
  if (game.status == GameStatus.scheduled) return '경기 전에 확인할 것';
  if (game.status == GameStatus.cancelled) return '취소된 경기예요';
  if (game.status == GameStatus.suspended) return '중단 이후 진행 여부를 확인해 주세요';
  if (!game.hasVerifiedScore) return '공식 점수를 확인하고 있어요';
  final difference = (game.away.score - game.home.score).abs();
  if (difference == 0) {
    return game.status == GameStatus.final_
        ? '무승부로 마무리됐어요'
        : '동점, 다음 한 점에 주목하세요';
  }
  final leader = game.away.score > game.home.score
      ? game.away.shortName
      : game.home.shortName;
  return game.status == GameStatus.final_
      ? '$leader, $difference점 차 승리'
      : '$leader, $difference점 앞서고 있어요';
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
          Text(
            '경기 한눈에',
            style: TextStyle(
              fontSize: 12,
              color: colors.readableAccent(colors.accent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            gameReadingHeadline(game),
            style: const TextStyle(fontSize: 20, height: 1.3),
          ),
          const SizedBox(height: 8),
          Text(
            scheduled
                ? game.isPregameLineupOpen
                      ? '라인업이 공개됐어요. 선발과 타순을 살펴보세요.'
                      : '선발과 타순은 공식 발표 후 확인할 수 있어요.'
                : game.status == GameStatus.cancelled ||
                      game.status == GameStatus.suspended
                ? '공식 경기 상태 기준으로 표시합니다.'
                : '현재 제공된 점수 기준 · 원정 ${game.away.shortName} / 홈 ${game.home.shortName}',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: colors.textSecondary,
            ),
          ),
          if (latest.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              innings.length > 5 ? '최근 5개 득점 이닝' : '득점 이닝 흐름',
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
            const SizedBox(height: 6),
            Text(
              '각 이닝까지의 누적 점수입니다. 진행 중인 이닝은 바뀔 수 있으며, 타석 순서는 문자중계에서 확인하세요.',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: colors.textSecondary,
              ),
            ),
          ],
          if (onOpenRelay != null ||
              onOpenBoxscore != null ||
              onOpenLineup != null) ...[
            const SizedBox(height: 12),
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
                    label: const Text('중계로 흐름 읽기'),
                  ),
                if (onOpenBoxscore != null &&
                    (game.status == GameStatus.live ||
                        game.status == GameStatus.final_))
                  OutlinedButton.icon(
                    onPressed: onOpenBoxscore,
                    icon: const Icon(Icons.bar_chart_rounded, size: 16),
                    label: const Text('선수 기록 확인'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
