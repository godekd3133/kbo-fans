import 'package:flutter/material.dart';

import '../../../core/constants/team_data.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/game_status_label.dart';
import '../../../core/widgets/app_design_system.dart';
import '../../../core/widgets/kbo_team_logo_image.dart';
import '../../../data/models/game.dart';
import '../../../data/models/schedule.dart';

Game? selectMyTeamFocusGame(List<Game> games, String? teamId) {
  if (teamId == null || teamId.isEmpty) return null;
  int priority(Game game) => switch (game.status) {
    GameStatus.live => 0,
    GameStatus.scheduled => 1,
    GameStatus.suspended => 2,
    GameStatus.final_ => 3,
    GameStatus.cancelled => 4,
  };
  Game? selected;
  for (final game in games) {
    if (game.away.teamId != teamId && game.home.teamId != teamId) continue;
    if (selected == null || priority(game) < priority(selected)) {
      selected = game;
    }
  }
  return selected;
}

String _nextGameWhen(ScheduleGame game) {
  final date = RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(game.gameId);
  if (date == null) return game.time;
  final year = int.parse(date.group(1)!);
  final month = int.parse(date.group(2)!);
  final day = int.parse(date.group(3)!);
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return game.time;
  }
  return '$month월 $day일 ${game.time}';
}

/// The first answer on Home uses the scoreboard already loaded by Home.
/// Optional next-game data must never delay or replace that answer.
class GameDayFocusCard extends StatelessWidget {
  final String? myTeamId;
  final Game? game;
  final ScheduleGame? nextGame;
  final int todayGameCount;
  final bool nextGameLoading;
  final VoidCallback onOpenGame;
  final VoidCallback onOpenSchedule;
  final VoidCallback onSelectTeam;

  const GameDayFocusCard({
    super.key,
    required this.myTeamId,
    required this.game,
    required this.nextGame,
    required this.todayGameCount,
    required this.nextGameLoading,
    required this.onOpenGame,
    required this.onOpenSchedule,
    required this.onSelectTeam,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final team = KboTeams.byId(myTeamId ?? '');
    final accent = colors.readableAccent(team?.primaryColor ?? colors.accent);
    final current = game;
    final next = nextGame?.status == 'SCHEDULED' ? nextGame : null;
    final title = myTeamId == null
        ? '오늘의 야구'
        : current == null
        ? '${team?.shortName ?? myTeamId} 경기 없는 날'
        : '${team?.shortName ?? myTeamId}의 오늘 경기';
    return Container(
      key: const ValueKey('home-game-day-focus'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppUi.heroRadius),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (team != null) ...[
                KboTeamLogoImage(
                  teamId: team.id,
                  fallback: team.shortName,
                  size: 34,
                  padding: 0,
                ),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (current != null)
                      Text(
                        labelForGameStatus(
                          current.status,
                          statusLabel: current.statusLabel,
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              if (current != null)
                Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
            ],
          ),
          const SizedBox(height: 14),
          if (current != null) ...[
            _Matchup(game: current),
            const SizedBox(height: 10),
            Text(
              [
                current.stadium,
                current.startTime,
              ].where((value) => value.isNotEmpty).join(' · '),
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            _Action(
              label: switch (current.status) {
                GameStatus.scheduled =>
                  current.isPregameLineupOpen ? '공개된 라인업 보기' : '경기 프리뷰 보기',
                GameStatus.live => '문자중계 보기',
                GameStatus.final_ => '경기 결과 자세히',
                GameStatus.cancelled || GameStatus.suspended => '경기 상태 확인',
              },
              onPressed: onOpenGame,
            ),
          ] else ...[
            Text(
              myTeamId == null
                  ? todayGameCount == 0
                        ? '오늘은 예정된 경기가 없어요'
                        : '오늘 $todayGameCount경기를 한눈에'
                  : next != null
                  ? '${_nextGameWhen(next)} 경기'
                  : '다음 일정을 확인하세요',
              style: TextStyle(
                fontSize: 21,
                height: 1.25,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              myTeamId == null
                  ? '응원팀을 고르면 경기와 기록을 먼저 보여드려요.'
                  : next != null
                  ? '${next.awayName} vs ${next.homeName} · ${next.stadium}'
                  : nextGameLoading
                  ? '다음 경기 일정을 확인하고 있어요.'
                  : '다음 경기는 일정에서 확인할 수 있어요.',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            _Action(
              label: myTeamId == null ? '응원팀 선택' : '다음 경기 일정 보기',
              onPressed: myTeamId == null ? onSelectTeam : onOpenSchedule,
            ),
          ],
        ],
      ),
    );
  }
}

class _Matchup extends StatelessWidget {
  final Game game;
  const _Matchup({required this.game});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final showScore =
        game.status == GameStatus.live || game.status == GameStatus.final_;
    final label = showScore
        ? '${game.away.displayScore} : ${game.home.displayScore}'
        : game.status == GameStatus.scheduled
        ? game.startTime
        : 'VS';
    final teams = Row(
      children: [
        Expanded(child: _team(game.away, context)),
        if (!largeText)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: TextStyle(fontSize: 34, color: colors.textPrimary),
            ),
          ),
        Expanded(child: _team(game.home, context)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        teams,
        if (largeText) ...[
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 30),
          ),
        ],
        if (showScore && !game.hasVerifiedScore) ...[
          const SizedBox(height: 8),
          Text(
            '공식 점수 확인 중',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
      ],
    );
  }

  Widget _team(TeamScore score, BuildContext context) => Column(
    children: [
      KboTeamLogoImage(
        teamId: score.teamId,
        fallback: score.shortName,
        size: 44,
      ),
      const SizedBox(height: 6),
      Text(
        score.shortName,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16),
      ),
    ],
  );
}

class _Action extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _Action({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          backgroundColor: colors.accent.withValues(alpha: 0.14),
          foregroundColor: colors.readableAccent(colors.accent, minContrast: 7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}
