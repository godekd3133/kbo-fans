import 'package:flutter/material.dart';

import '../../../core/constants/visual_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_artwork_card.dart';
import '../../../data/models/game.dart';

class ScoreTab extends StatelessWidget {
  static const _teamColumnWidth = 64.0;
  static const _scoreColumnWidth = 44.0;
  static const _headerRowHeight = 40.0;
  static const _scoreRowHeight = 44.0;

  final String gameId;
  final Game game;
  final Future<void> Function()? onRefresh;
  final Widget? footer;

  const ScoreTab({
    super.key,
    required this.gameId,
    required this.game,
    this.onRefresh,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh ?? () async {},
      color: AppColors.live,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_hasAnyInningData)
              _buildInningTable()
            else
              _buildMissingInningCard(),
            if (footer != null) ...[const SizedBox(height: 12), footer!],
          ],
        ),
      ),
    );
  }

  bool get _hasAnyInningData {
    return game.away.innings.any((score) => score != null) ||
        game.home.innings.any((score) => score != null);
  }

  Widget _buildMissingInningCard() {
    final (icon, title, description) = switch (game.status) {
      GameStatus.cancelled => (
        Icons.event_busy_outlined,
        '경기 취소',
        '취소된 경기라 이닝별 기록이 없습니다.',
      ),
      GameStatus.scheduled => (
        Icons.schedule_outlined,
        '경기 전',
        '경기 시작 후 이닝별 기록이 표시됩니다.',
      ),
      GameStatus.suspended => (
        Icons.pause_circle_outline,
        '경기 중단',
        '중단 시점의 이닝별 기록이 제공되지 않았습니다. 상단 총점을 확인해 주세요.',
      ),
      GameStatus.live || GameStatus.final_ => (
        Icons.info_outline,
        '이닝별 기록 미제공',
        '이닝별 기록이 제공되지 않았습니다. 상단 총점을 확인해 주세요.',
      ),
    };

    return Container(
      key: const ValueKey('score-inning-empty-state'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInningTable() {
    final currentInning = _currentInning();
    final inningCount = [
      9,
      game.away.innings.length,
      game.home.innings.length,
      currentInning,
    ].reduce((value, element) => value > element ? value : element);
    final headers = [
      for (var inning = 1; inning <= inningCount; inning++) '$inning',
      'R',
      'H',
      'E',
      'B',
    ];
    final headerStyle = TextStyle(
      fontSize: 12,
      color: AppColors.textSupporting,
      fontWeight: FontWeight.w500,
    );
    final dataStyle = TextStyle(fontSize: 14, color: AppColors.textPrimary);
    final boldStyle = TextStyle(
      fontSize: 14,
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w700,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'R 득점 · H 안타 · E 실책 · B 사사구',
          key: const ValueKey('score-stat-legend'),
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          key: const ValueKey('score-table-semantics'),
          container: true,
          label: _scoreAccessibilitySummary(inningCount),
          child: ExcludeSemantics(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.divider),
              ),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: AppArtworkLayer(
                      assetName: VisualAssets.scoreLinescore,
                      alignment: Alignment.centerRight,
                      opacity: 0.18,
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        key: const ValueKey('score-fixed-team-column'),
                        width: _teamColumnWidth,
                        child: Table(
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.middle,
                          children: [
                            TableRow(
                              children: [
                                _tableCell(
                                  '팀',
                                  headerStyle,
                                  height: _headerRowHeight,
                                ),
                              ],
                            ),
                            _dividerRow(1),
                            TableRow(
                              children: [
                                _tableCell(
                                  game.away.shortName,
                                  boldStyle,
                                  height: _scoreRowHeight,
                                ),
                              ],
                            ),
                            _dividerRow(1),
                            TableRow(
                              children: [
                                _tableCell(
                                  game.home.shortName,
                                  boldStyle,
                                  height: _scoreRowHeight,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: _headerRowHeight + (_scoreRowHeight * 2) + 2,
                        color: AppColors.divider,
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          key: const ValueKey('score-scrollable-columns'),
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: headers.length * _scoreColumnWidth,
                            child: Table(
                              defaultVerticalAlignment:
                                  TableCellVerticalAlignment.middle,
                              defaultColumnWidth: const FixedColumnWidth(
                                _scoreColumnWidth,
                              ),
                              children: [
                                TableRow(
                                  children: headers.asMap().entries.map((
                                    entry,
                                  ) {
                                    final inningNo = entry.key < inningCount
                                        ? entry.key + 1
                                        : null;
                                    return _tableCell(
                                      entry.value,
                                      headerStyle,
                                      key: inningNo == null
                                          ? ValueKey(
                                              'score-stat-header-${entry.value}',
                                            )
                                          : ValueKey(
                                              'score-inning-header-$inningNo',
                                            ),
                                      height: _headerRowHeight,
                                      isHighlight:
                                          inningNo != null &&
                                          inningNo == currentInning,
                                    );
                                  }).toList(),
                                ),
                                _dividerRow(headers.length),
                                _scoreRow(
                                  game.away,
                                  inningCount,
                                  currentInning,
                                  dataStyle,
                                  boldStyle,
                                ),
                                _dividerRow(headers.length),
                                _scoreRow(
                                  game.home,
                                  inningCount,
                                  currentInning,
                                  dataStyle,
                                  boldStyle,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  TableRow _scoreRow(
    TeamScore team,
    int inningCount,
    int currentInning,
    TextStyle dataStyle,
    TextStyle boldStyle,
  ) {
    return TableRow(
      children: [
        for (int i = 0; i < inningCount; i++)
          _tableCell(
            i < team.innings.length && team.innings[i] != null
                ? '${team.innings[i]}'
                : '-',
            dataStyle,
            key: ValueKey('score-${team.teamId}-inning-${i + 1}'),
            height: _scoreRowHeight,
            isHighlight: (i + 1) == currentInning,
          ),
        _tableCell(
          team.displayScore,
          boldStyle,
          key: ValueKey('score-${team.teamId}-total-runs'),
          height: _scoreRowHeight,
        ),
        _tableCell(
          _teamStatText(team, team.hits),
          boldStyle,
          key: ValueKey('score-${team.teamId}-total-hits'),
          height: _scoreRowHeight,
        ),
        _tableCell(
          _teamStatText(team, team.errors),
          boldStyle,
          key: ValueKey('score-${team.teamId}-total-errors'),
          height: _scoreRowHeight,
        ),
        _tableCell(
          _teamStatText(team, team.walks),
          boldStyle,
          key: ValueKey('score-${team.teamId}-total-walks'),
          height: _scoreRowHeight,
        ),
      ],
    );
  }

  TableRow _dividerRow(int cellCount) {
    return TableRow(
      children: List.generate(
        cellCount,
        (_) => SizedBox(height: 1, child: ColoredBox(color: AppColors.divider)),
      ),
    );
  }

  String _teamStatText(TeamScore team, int value) {
    return team.hasStats ? '$value' : '-';
  }

  Widget _tableCell(
    String text,
    TextStyle style, {
    Key? key,
    required double height,
    bool isHighlight = false,
  }) {
    return Container(
      key: key,
      height: height,
      alignment: Alignment.center,
      color: isHighlight ? AppColors.cardSub : null,
      child: Text(text, textAlign: TextAlign.center, style: style),
    );
  }

  int _currentInning() {
    return int.tryParse(game.inning.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  String _scoreAccessibilitySummary(int inningCount) {
    final current = _currentInning();
    final currentLabel = current > 0 ? '현재 ${game.inning}. ' : '';
    return '이닝별 점수표. $currentLabel'
        '${_teamAccessibilitySummary(game.away, inningCount)} '
        '${_teamAccessibilitySummary(game.home, inningCount)} '
        'R은 득점, H는 안타, E는 실책, B는 사사구입니다.';
  }

  String _teamAccessibilitySummary(TeamScore team, int inningCount) {
    final inningScores = <String>[];
    for (
      var index = 0;
      index < team.innings.length && index < inningCount;
      index++
    ) {
      final score = team.innings[index];
      if (score != null) {
        inningScores.add('${index + 1}회 $score점');
      }
    }
    final inningText = inningScores.isEmpty
        ? '진행된 이닝 점수 없음'
        : inningScores.join(', ');
    final statsText = team.hasStats
        ? '안타 ${team.hits}, 실책 ${team.errors}, 사사구 ${team.walks}'
        : '안타, 실책, 사사구 정보 미제공';
    final totalText = team.scoreAvailable ? '합계 ${team.score}점' : '합계 미확정';
    return '${team.shortName} $inningText, $totalText, $statsText.';
  }
}
