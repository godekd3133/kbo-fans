import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/team_data.dart';
import '../../../core/constants/visual_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_artwork_card.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../data/models/boxscore.dart';
import '../../../data/models/game.dart';
import '../../../data/models/player.dart';
import '../../../data/providers.dart';

const _kboImageHeaders = {
  'Referer': 'https://www.koreabaseball.com/',
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
};

class BoxscoreTab extends ConsumerStatefulWidget {
  final String gameId;
  final Game game;
  final GameStatus gameStatus;
  final String awayName;
  final String homeName;
  final String awayTeamId;
  final String homeTeamId;
  final Future<void> Function()? onRefresh;

  const BoxscoreTab({
    super.key,
    required this.gameId,
    required this.game,
    required this.gameStatus,
    this.awayName = '원정',
    this.homeName = '홈',
    this.awayTeamId = '',
    this.homeTeamId = '',
    this.onRefresh,
  });

  @override
  ConsumerState<BoxscoreTab> createState() => _BoxscoreTabState();
}

class _BoxscoreTabState extends ConsumerState<BoxscoreTab> {
  bool _showAway = true;

  String get _selectedTeamName => _showAway ? widget.awayName : widget.homeName;
  String get _selectedTeamId =>
      _showAway ? widget.awayTeamId : widget.homeTeamId;

  @override
  Widget build(BuildContext context) {
    if (widget.gameStatus == GameStatus.scheduled) {
      return _buildUnavailableState('경기 시작 후 박스스코어가 제공됩니다');
    }
    if (widget.gameStatus == GameStatus.cancelled) {
      return _buildUnavailableState('취소된 경기는 박스스코어가 없습니다');
    }

    final boxscoreAsync = ref.watch(gameBoxscoreProvider(widget.gameId));
    final content = boxscoreAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(color: AppColors.live),
        ),
      ),
      error: (error, _) => _buildUnavailableState('박스스코어 로딩 실패: $error'),
      data: (boxscore) {
        final selected = _showAway ? boxscore.away : boxscore.home;
        if (!boxscore.officialAvailable || !selected.hasDisplayableRecords) {
          return _buildUnavailableState('공식 박스스코어 업데이트 전입니다');
        }

        final season = DateTime.now().year;
        final playersAsync = _selectedTeamId.isEmpty
            ? const AsyncValue<List<PlayerProfile>>.data(<PlayerProfile>[])
            : ref.watch(teamPlayersProvider('$_selectedTeamId|$season'));
        return playersAsync.when(
          loading: () =>
              _buildContent(selected.batters, selected.pitchers, const {}),
          error: (_, _) =>
              _buildContent(selected.batters, selected.pitchers, const {}),
          data: (players) =>
              _buildContent(selected.batters, selected.pitchers, {
                for (final player in players)
                  if (player.name.isNotEmpty) player.name: player,
              }),
        );
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth > 760
            ? 720.0
            : constraints.maxWidth;

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: RefreshIndicator(
              onRefresh: widget.onRefresh ?? () async {},
              color: AppColors.live,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTeamToggle(),
                    const SizedBox(height: 16),
                    AppMotionSwitcher(
                      child: KeyedSubtree(
                        key: ValueKey(
                          'boxscore-$_selectedTeamId-${boxscoreAsync.isLoading}-${boxscoreAsync.hasError}',
                        ),
                        child: content,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUnavailableState(String message) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: AppArtworkCard(
        assetName: VisualAssets.boxscoreAnalytics,
        height: 178,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text(
              '박스스코어',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamToggle() {
    return Row(
      children: [
        Expanded(
          child: _TeamToggleCard(
            sideLabel: 'AWAY',
            teamId: widget.awayTeamId,
            teamName: widget.awayName,
            active: _showAway,
            onTap: () => setState(() => _showAway = true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TeamToggleCard(
            sideLabel: 'HOME',
            teamId: widget.homeTeamId,
            teamName: widget.homeName,
            active: !_showAway,
            onTap: () => setState(() => _showAway = false),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(
    List<BatterRecord> batters,
    List<PitcherRecord> pitchers,
    Map<String, PlayerProfile> playersByName,
  ) {
    final team = KboTeams.byId(_selectedTeamId);
    final accent = team?.primaryColor ?? AppColors.accent;

    final totalAtBats = batters.fold<int>(
      0,
      (sum, batter) => sum + batter.atBats,
    );
    final totalRuns = batters.fold<int>(0, (sum, batter) => sum + batter.runs);
    final totalHits = batters.fold<int>(0, (sum, batter) => sum + batter.hits);
    final totalRbi = batters.fold<int>(0, (sum, batter) => sum + batter.rbi);
    final teamBattingAverage = totalAtBats > 0
        ? (totalHits / totalAtBats)
        : 0.0;
    final keyBatter = batters.isEmpty
        ? null
        : batters.reduce((a, b) {
            final aScore = (a.hits * 3) + (a.rbi * 2) + a.runs;
            final bScore = (b.hits * 3) + (b.rbi * 2) + b.runs;
            return aScore >= bScore ? a : b;
          });
    final keyPitcher = pitchers.isEmpty
        ? null
        : pitchers.reduce((a, b) {
            final aScore =
                (a.strikeouts * 2) - (a.walks * 2) - (a.earnedRuns * 3);
            final bScore =
                (b.strikeouts * 2) - (b.walks * 2) - (b.earnedRuns * 3);
            return aScore >= bScore ? a : b;
          });
    final playerImageMap = _playerImageMap(playersByName);
    final keyBatterPlayer = keyBatter == null
        ? null
        : _resolvePlayer(playersByName, keyBatter.name);
    final keyPitcherPlayer = keyPitcher == null
        ? null
        : _resolvePlayer(playersByName, keyPitcher.name);
    final productionScore = keyBatter == null
        ? 0
        : _batterProductionScore(keyBatter);
    final efficiencyScore = keyPitcher == null
        ? 0
        : _pitcherEfficiencyScore(keyPitcher);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BoxscoreSummaryPanel(
          teamId: _selectedTeamId,
          teamName: _selectedTeamName,
          accent: accent,
          metrics: [
            _SummaryMetric(label: '타수', value: '$totalAtBats'),
            _SummaryMetric(label: '득점', value: '$totalRuns'),
            _SummaryMetric(label: '안타', value: '$totalHits'),
            _SummaryMetric(label: '타점', value: '$totalRbi'),
            _SummaryMetric(
              label: '팀 타율',
              value: teamBattingAverage.toStringAsFixed(3),
            ),
          ],
        ),
        if (keyBatter != null || keyPitcher != null) ...[
          const SizedBox(height: 20),
          _SectionTitle(
            title: '오늘 기록 요약',
            actionLabel: _selectedTeamId.isEmpty ? null : '팀 기록 보기',
            onAction: _selectedTeamId.isEmpty
                ? null
                : () => context.push('/records/team/$_selectedTeamId'),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.divider),
                bottom: BorderSide(color: AppColors.divider),
              ),
            ),
            child: Column(
              children: [
                if (keyBatter != null)
                  _RecordHighlightRow(
                    tag: '결승타',
                    name: keyBatter.name,
                    role: '${keyBatter.position}  ${keyBatter.order}번',
                    summary:
                        '${keyBatter.atBats}타수 ${keyBatter.hits}안타  ${keyBatter.rbi}타점  ${keyBatter.runs}득점',
                    metricLabel: '생산 +$productionScore',
                    accent: accent,
                    imageUrl:
                        keyBatterPlayer?.imageUrl ??
                        _resolveImageUrl(playerImageMap, keyBatter.name),
                    badgeLabel: (keyBatterPlayer?.number ?? 0) > 0
                        ? '${keyBatterPlayer!.number}'
                        : null,
                    actionLabel: keyBatterPlayer == null ? null : '선수 기록 보기',
                    onTap: keyBatterPlayer == null
                        ? null
                        : () => _pushPlayerDetail(keyBatterPlayer),
                  ),
                if (keyPitcher != null)
                  _RecordHighlightRow(
                    tag: '호투',
                    name: keyPitcher.name,
                    role: keyPitcher.decision == null
                        ? '투수'
                        : '투수  ${keyPitcher.decision}',
                    summary:
                        '${keyPitcher.innings}이닝  ${keyPitcher.hits}피안타  ${keyPitcher.earnedRuns}자책  ${keyPitcher.strikeouts}탈삼진',
                    metricLabel: '효율 +$efficiencyScore',
                    accent: AppColors.live,
                    imageUrl:
                        keyPitcherPlayer?.imageUrl ??
                        _resolveImageUrl(playerImageMap, keyPitcher.name),
                    badgeLabel: (keyPitcherPlayer?.number ?? 0) > 0
                        ? '${keyPitcherPlayer!.number}'
                        : null,
                    actionLabel: keyPitcherPlayer == null ? null : '선수 기록 보기',
                    onTap: keyPitcherPlayer == null
                        ? null
                        : () => _pushPlayerDetail(keyPitcherPlayer),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        const _SectionTitle(title: '타자 기록'),
        const SizedBox(height: 8),
        const _RecordTableHeader(
          labels: ['선수명', '타수', '안타', '타점', '득점', '타율'],
          widths: [38, 38, 38, 38, 54],
        ),
        ...batters.asMap().entries.map(
          (entry) => AppMotionListItem(
            index: entry.key,
            child: _buildBatterRecordRow(entry.value, accent, playersByName),
          ),
        ),
        const SizedBox(height: 22),
        const _SectionTitle(title: '투수 기록'),
        const SizedBox(height: 8),
        const _RecordTableHeader(
          labels: ['선수명', '이닝', '피안타', '자책', '삼진', '결과'],
          widths: [42, 42, 38, 38, 42],
        ),
        ...pitchers.asMap().entries.map(
          (entry) => AppMotionListItem(
            index: batters.length + entry.key,
            child: _buildPitcherRecordRow(entry.value, accent, playersByName),
          ),
        ),
        if (_selectedTeamId.isNotEmpty) ...[
          const SizedBox(height: 18),
          Center(
            child: AppPressable(
              pressedScale: 0.97,
              onTap: () => context.push('/records/team/$_selectedTeamId'),
              child: const _InlineAction(label: '팀 기록 보기'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBatterRecordRow(
    BatterRecord batter,
    Color accent,
    Map<String, PlayerProfile> playersByName,
  ) {
    final player = _resolvePlayer(playersByName, batter.name);
    final todayAvg = batter.atBats > 0 ? (batter.hits / batter.atBats) : 0.0;
    return _RecordDataRow(
      onTap: player == null ? null : () => _pushPlayerDetail(player),
      name: batter.name,
      meta: '${batter.position}  ${batter.order}번',
      actionLabel: player == null ? null : '선수 기록 보기',
      accent: accent,
      values: [
        _RecordCell(value: '${batter.atBats}', width: 38),
        _RecordCell(value: '${batter.hits}', width: 38),
        _RecordCell(value: '${batter.rbi}', width: 38),
        _RecordCell(value: '${batter.runs}', width: 38),
        _RecordCell(
          value: todayAvg.toStringAsFixed(3),
          width: 54,
          color: accent,
        ),
      ],
    );
  }

  Widget _buildPitcherRecordRow(
    PitcherRecord pitcher,
    Color accent,
    Map<String, PlayerProfile> playersByName,
  ) {
    final player = _resolvePlayer(playersByName, pitcher.name);
    return _RecordDataRow(
      onTap: player == null ? null : () => _pushPlayerDetail(player),
      name: pitcher.name,
      meta: '투수 기록',
      actionLabel: player == null ? null : '선수 기록 보기',
      accent: AppColors.live,
      values: [
        _RecordCell(value: pitcher.innings, width: 42),
        _RecordCell(value: '${pitcher.hits}', width: 42),
        _RecordCell(value: '${pitcher.earnedRuns}', width: 38),
        _RecordCell(value: '${pitcher.strikeouts}', width: 38),
        _RecordCell(
          value: pitcher.decision ?? '-',
          width: 42,
          color: pitcher.decision == null ? AppColors.textDisabled : accent,
        ),
      ],
    );
  }

  int _batterProductionScore(BatterRecord batter) {
    return (batter.hits * 3) + (batter.rbi * 2) + batter.runs;
  }

  int _pitcherEfficiencyScore(PitcherRecord pitcher) {
    final score =
        (pitcher.strikeouts * 2) -
        (pitcher.walks * 2) -
        (pitcher.earnedRuns * 3);
    return score < 0 ? 0 : score;
  }

  void _pushPlayerDetail(PlayerProfile player) {
    context.push('/records/player/${player.id}?season=${DateTime.now().year}');
  }

  Map<String, String> _playerImageMap(
    Map<String, PlayerProfile> playersByName,
  ) => {
    for (final entry in playersByName.entries)
      if (entry.value.imageUrl != null && entry.value.imageUrl!.isNotEmpty)
        entry.key: entry.value.imageUrl!,
  };

  PlayerProfile? _resolvePlayer(
    Map<String, PlayerProfile> playersByName,
    String rawName,
  ) {
    if (rawName.isEmpty) {
      return null;
    }
    if (playersByName.containsKey(rawName)) {
      return playersByName[rawName];
    }
    final normalizedTarget = _normalizeName(rawName);
    for (final entry in playersByName.entries) {
      final normalizedKey = _normalizeName(entry.key);
      if (normalizedKey == normalizedTarget ||
          normalizedKey.contains(normalizedTarget) ||
          normalizedTarget.contains(normalizedKey)) {
        return entry.value;
      }
    }
    return null;
  }

  String? _resolveImageUrl(Map<String, String> imageMap, String rawName) {
    if (rawName.isEmpty) {
      return null;
    }
    if (imageMap.containsKey(rawName)) {
      return imageMap[rawName];
    }

    final normalizedTarget = _normalizeName(rawName);
    for (final entry in imageMap.entries) {
      final normalizedKey = _normalizeName(entry.key);
      if (normalizedKey == normalizedTarget ||
          normalizedKey.contains(normalizedTarget) ||
          normalizedTarget.contains(normalizedKey)) {
        return entry.value;
      }
    }
    return null;
  }

  String _normalizeName(String value) {
    return value
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('·', '')
        .replaceAll('ㆍ', '')
        .replaceAll('.', '')
        .replaceAll('(', '')
        .replaceAll(')', '')
        .toLowerCase();
  }
}

class _SummaryMetric {
  final String label;
  final String value;

  const _SummaryMetric({required this.label, required this.value});
}

class _BoxscoreSummaryPanel extends StatelessWidget {
  final String teamId;
  final String teamName;
  final Color accent;
  final List<_SummaryMetric> metrics;

  const _BoxscoreSummaryPanel({
    required this.teamId,
    required this.teamName,
    required this.accent,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.divider),
          bottom: BorderSide(color: AppColors.divider),
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: AppArtworkLayer(
              assetName: VisualAssets.boxscoreAnalytics,
              alignment: Alignment.centerRight,
              opacity: 0.14,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _TeamLogo(teamId: teamId, fallback: teamName, size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '오늘 기록 요약',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            teamName,
                            style: TextStyle(
                              fontSize: 12,
                              color: accent,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (int i = 0; i < metrics.length; i++) ...[
                      Expanded(child: _SummaryMetricTile(metric: metrics[i])),
                      if (i != metrics.length - 1)
                        Container(
                          width: 1,
                          height: 34,
                          color: AppColors.divider,
                        ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetricTile extends StatelessWidget {
  final _SummaryMetric metric;

  const _SummaryMetricTile({required this.metric});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          metric.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          metric.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 18,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionTitle({required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
        ),
        if (actionLabel != null && onAction != null)
          AppPressable(
            pressedScale: 0.97,
            onTap: onAction,
            child: _InlineAction(label: actionLabel!, compact: true),
          ),
      ],
    );
  }
}

class _RecordHighlightRow extends StatelessWidget {
  final String tag;
  final String name;
  final String role;
  final String summary;
  final String metricLabel;
  final Color accent;
  final String? imageUrl;
  final String? badgeLabel;
  final String? actionLabel;
  final VoidCallback? onTap;

  const _RecordHighlightRow({
    required this.tag,
    required this.name,
    required this.role,
    required this.summary,
    required this.metricLabel,
    required this.accent,
    this.imageUrl,
    this.badgeLabel,
    this.actionLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      pressedScale: onTap == null ? 1 : 0.985,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 84),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            _PlayerAvatar(
              imageUrl: imageUrl,
              fallbackLabel: name,
              accent: accent,
              badgeLabel: badgeLabel,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _RecordTag(label: tag, accent: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$name  $role',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (actionLabel != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      actionLabel!,
                      style: TextStyle(
                        fontSize: 11,
                        color: accent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              metricLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                color: accent,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: onTap == null ? AppColors.textDisabled : accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordTag extends StatelessWidget {
  final String label;
  final Color accent;

  const _RecordTag({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: accent,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _RecordTableHeader extends StatelessWidget {
  final List<String> labels;
  final List<double> widths;

  const _RecordTableHeader({required this.labels, required this.widths});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              labels.first,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (int i = 1; i < labels.length; i++)
            SizedBox(
              width: widths[i - 1],
              child: Text(
                labels[i],
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          const SizedBox(width: 18),
        ],
      ),
    );
  }
}

class _RecordDataRow extends StatelessWidget {
  final VoidCallback? onTap;
  final String name;
  final String meta;
  final String? actionLabel;
  final Color accent;
  final List<_RecordCell> values;

  const _RecordDataRow({
    required this.onTap,
    required this.name,
    required this.meta,
    required this.actionLabel,
    required this.accent,
    required this.values,
  });

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      pressedScale: onTap == null ? 1 : 0.99,
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: actionLabel == null ? 58 : 68),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (actionLabel != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            actionLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: accent,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            for (final value in values) value,
            SizedBox(
              width: 18,
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: onTap == null ? Colors.transparent : accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordCell extends StatelessWidget {
  final String value;
  final double width;
  final Color? color;

  const _RecordCell({required this.value, required this.width, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 16,
          color: color ?? AppColors.textPrimary,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _InlineAction extends StatelessWidget {
  final String label;
  final bool compact;

  const _InlineAction({required this.label, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: compact ? 12 : 16,
            color: AppColors.accent,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 4),
        const Icon(
          Icons.chevron_right_rounded,
          size: 20,
          color: AppColors.accent,
        ),
      ],
    );
  }
}

class _TeamToggleCard extends StatelessWidget {
  final String sideLabel;
  final String teamId;
  final String teamName;
  final bool active;
  final VoidCallback onTap;

  const _TeamToggleCard({
    required this.sideLabel,
    required this.teamId,
    required this.teamName,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final team = KboTeams.resolve(
      id: teamId,
      name: teamName,
      shortName: teamName,
    );

    return AppPressable(
      onTap: onTap,
      pressedScale: 0.985,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? AppColors.card : AppColors.background,
          border: Border.all(
            color: active
                ? (team?.primaryColor ?? AppColors.accent)
                : AppColors.divider,
          ),
        ),
        child: Row(
          children: [
            _TeamLogo(teamId: teamId, fallback: teamName, size: 34),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sideLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: active
                          ? (team?.primaryColor ?? AppColors.accent)
                          : AppColors.textDisabled,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    teamName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: active
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamLogo extends StatelessWidget {
  final String teamId;
  final String fallback;
  final double size;

  const _TeamLogo({
    required this.teamId,
    required this.fallback,
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) {
    final team = KboTeams.resolve(
      id: teamId,
      name: fallback,
      shortName: fallback,
    );
    return CachedNetworkImage(
      imageUrl: team?.logoUrl ?? '',
      httpHeaders: _kboImageHeaders,
      width: size,
      height: size,
      memCacheWidth: (size * 3).round(),
      memCacheHeight: (size * 3).round(),
      placeholder: (_, _) => _fallbackAvatar(team, fallback),
      errorWidget: (_, _, _) => _fallbackAvatar(team, fallback),
    );
  }

  Widget _fallbackAvatar(KboTeam? team, String fallback) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: (team?.primaryColor ?? AppColors.cardSub).withValues(
          alpha: 0.18,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        fallback.isNotEmpty ? fallback.substring(0, 1) : '?',
        style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _PlayerAvatar extends StatelessWidget {
  final String? imageUrl;
  final String fallbackLabel;
  final Color accent;
  final String? badgeLabel;

  const _PlayerAvatar({
    required this.imageUrl,
    required this.fallbackLabel,
    required this.accent,
    this.badgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: imageUrl!,
              httpHeaders: _kboImageHeaders,
              width: 52,
              height: 52,
              memCacheWidth: 156,
              memCacheHeight: 156,
              fit: BoxFit.cover,
              placeholder: (_, _) => _fallbackAvatar(),
              errorWidget: (_, _, _) => _fallbackAvatar(),
            ),
          ),
          if (badgeLabel != null) _numberBadge(),
        ],
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [_fallbackAvatar(), if (badgeLabel != null) _numberBadge()],
    );
  }

  Widget _fallbackAvatar() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.person_rounded, color: accent, size: 28),
    );
  }

  Widget _numberBadge() {
    return Positioned(
      right: -4,
      bottom: -4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.background, width: 1.5),
        ),
        child: Text(
          badgeLabel!,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: accent,
          ),
        ),
      ),
    );
  }
}
