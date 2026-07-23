import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/team_data.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/kbo_player_image_cache.dart';
import '../../../core/utils/kbo_time.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/kbo_team_logo_image.dart';
import '../../../data/models/boxscore.dart';
import '../../../data/models/game.dart';
import '../../../data/models/player.dart';
import '../../../data/models/records_overview.dart';
import '../../../data/providers.dart';

bool _usesCompactBoxscoreLayout(BuildContext context) {
  final mediaQuery = MediaQuery.of(context);
  return mediaQuery.size.width <= 360 || mediaQuery.textScaler.scale(1) >= 1.5;
}

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
  String? _lastPrefetchedImageSignature;

  String get _selectedTeamName => _showAway ? widget.awayName : widget.homeName;
  String get _selectedTeamId =>
      _showAway ? widget.awayTeamId : widget.homeTeamId;
  String get _opponentTeamName => _showAway ? widget.homeName : widget.awayName;

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
      loading: () => Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(color: AppColors.live),
        ),
      ),
      error: (_, _) => _buildUnavailableState(
        '박스스코어를 불러올 수 없습니다',
        detail: '네트워크 상태를 확인하고 다시 시도해 주세요',
        onRetry: () => unawaited(_retryBoxscore()),
      ),
      data: (boxscore) {
        final selected = _showAway ? boxscore.away : boxscore.home;
        final opponent = _showAway ? boxscore.home : boxscore.away;
        final isLiveContext =
            !boxscore.officialAvailable && boxscore.liveContextAvailable;
        if ((!boxscore.officialAvailable && !isLiveContext) ||
            !selected.hasDisplayableRecords) {
          return _buildUnavailableState('공식 박스스코어 업데이트 전입니다');
        }

        final season = _seasonFromGameId(widget.gameId);
        final playersAsync = _selectedTeamId.isEmpty
            ? const AsyncValue<List<PlayerProfile>>.data(<PlayerProfile>[])
            : ref.watch(teamPlayersProvider('$_selectedTeamId|$season'));
        return playersAsync.when(
          loading: () => _buildContent(
            selected,
            opponent,
            const {},
            season: season,
            isLiveContext: isLiveContext,
          ),
          error: (_, _) => _buildContent(
            selected,
            opponent,
            const {},
            season: season,
            isLiveContext: isLiveContext,
          ),
          data: (players) {
            final playersByName = {
              for (final player in players)
                if (player.name.isNotEmpty) player.name: player,
            };
            _prefetchBoxscorePlayerImages(
              _boxscorePlayerImageUrlsForRows(
                selected,
                playersByName,
                season: season,
              ),
            );
            return _buildContent(
              selected,
              opponent,
              playersByName,
              season: season,
              isLiveContext: isLiveContext,
            );
          },
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

  Future<void> _retryBoxscore() async {
    try {
      final refresh = widget.onRefresh;
      if (refresh != null) {
        await refresh();
        return;
      }
      ref.invalidate(gameBoxscoreProvider(widget.gameId));
      await ref.read(gameBoxscoreProvider(widget.gameId).future);
    } catch (_) {
      // Provider state renders the safe error copy; technical details stay out of UI.
    }
  }

  Widget _buildUnavailableState(
    String message, {
    String? detail,
    VoidCallback? onRetry,
  }) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          height: 178,
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const Text(
                '박스스코어',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              if (detail != null) ...[
                const SizedBox(height: 6),
                Text(
                  detail,
                  style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
                ),
              ],
              if (onRetry != null) ...[
                const Spacer(),
                TextButton(onPressed: onRetry, child: const Text('다시 시도')),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeamToggle() {
    final away = _TeamToggleCard(
      sideLabel: 'AWAY',
      teamId: widget.awayTeamId,
      teamName: widget.awayName,
      active: _showAway,
      onTap: () => setState(() => _showAway = true),
    );
    final home = _TeamToggleCard(
      sideLabel: 'HOME',
      teamId: widget.homeTeamId,
      teamName: widget.homeName,
      active: !_showAway,
      onTap: () => setState(() => _showAway = false),
    );

    if (_usesCompactBoxscoreLayout(context)) {
      return Column(children: [away, const SizedBox(height: 10), home]);
    }

    return Row(
      children: [
        Expanded(child: away),
        const SizedBox(width: 10),
        Expanded(child: home),
      ],
    );
  }

  Widget _buildContent(
    TeamBoxscoreData selected,
    TeamBoxscoreData opponent,
    Map<String, PlayerProfile> playersByName, {
    required int season,
    required bool isLiveContext,
  }) {
    final batters = selected.batters;
    final pitchers = selected.pitchers;
    final team = KboTeams.byId(_selectedTeamId);
    final colors = AppTheme.colorsOf(context);
    final accent = colors.readableAccent(team?.primaryColor ?? colors.accent);
    final selectedMetrics = _BoxscoreTeamMetrics.from(selected);
    final opponentMetrics = _BoxscoreTeamMetrics.from(opponent);

    final officialBatters = batters.where((batter) => !batter.liveContext);
    final totalAtBats = officialBatters.fold<int>(
      0,
      (sum, batter) => sum + batter.atBats,
    );
    final totalRuns = officialBatters.fold<int>(
      0,
      (sum, batter) => sum + batter.runs,
    );
    final totalHits = officialBatters.fold<int>(
      0,
      (sum, batter) => sum + batter.hits,
    );
    final totalRbi = officialBatters.fold<int>(
      0,
      (sum, batter) => sum + batter.rbi,
    );
    final teamBattingAverage = totalAtBats > 0
        ? (totalHits / totalAtBats)
        : 0.0;
    final liveBattersWithStats = batters.where(_hasLiveBatterStats).toList();
    final liveAtBats = liveBattersWithStats.fold<int>(
      0,
      (sum, batter) => sum + batter.atBats,
    );
    final liveHits = liveBattersWithStats.fold<int>(
      0,
      (sum, batter) => sum + batter.hits,
    );
    final hasLiveBatterStats = liveAtBats > 0 || liveHits > 0;
    final liveBattingAverage = liveAtBats > 0 ? liveHits / liveAtBats : 0.0;
    final keyBatter = _keyBatter(batters, isLiveContext: isLiveContext);
    final keyPitcher = _keyPitcher(pitchers, isLiveContext: isLiveContext);
    final keyBatterPlayer = keyBatter == null
        ? null
        : _resolvePlayer(playersByName, keyBatter.name);
    final keyPitcherPlayer = keyPitcher == null
        ? null
        : _resolvePlayer(playersByName, keyPitcher.name);
    final keyBatterImageUrl = _playerImageUrlFromProfile(
      keyBatterPlayer,
      season,
    );
    final keyPitcherImageUrl = _playerImageUrlFromProfile(
      keyPitcherPlayer,
      season,
    );
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
          title: isLiveContext ? '실시간 기록 추적' : '오늘 기록 요약',
          metrics: isLiveContext
              ? hasLiveBatterStats
                    ? [
                        const _SummaryMetric(label: '상태', value: 'LIVE'),
                        _SummaryMetric(label: '타수', value: '$liveAtBats'),
                        _SummaryMetric(label: '안타', value: '$liveHits'),
                        _SummaryMetric(
                          label: '타율',
                          value: liveBattingAverage.toStringAsFixed(3),
                        ),
                        const _SummaryMetric(label: '출처', value: '실시간'),
                      ]
                    : [
                        const _SummaryMetric(label: '상태', value: 'LIVE'),
                        _SummaryMetric(label: '타자', value: '${batters.length}'),
                        _SummaryMetric(
                          label: '투수',
                          value: '${pitchers.length}',
                        ),
                        const _SummaryMetric(label: '출처', value: '실시간'),
                        const _SummaryMetric(label: '기록', value: '집계중'),
                      ]
              : [
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
        if (!isLiveContext && opponent.hasDisplayableRecords) ...[
          const SizedBox(height: 12),
          _TeamComparisonStrip(
            selectedTeamName: _selectedTeamName,
            opponentTeamName: _opponentTeamName,
            selected: selectedMetrics,
            opponent: opponentMetrics,
            accent: accent,
          ),
        ],
        if (keyBatter != null || keyPitcher != null) ...[
          const SizedBox(height: 20),
          _SectionTitle(
            title: isLiveContext ? 'LIVE 추적' : '오늘 기록 요약',
            actionLabel: _selectedTeamId.isEmpty ? null : '팀 기록 보기',
            onAction: _selectedTeamId.isEmpty
                ? null
                : () => context.push('/records/team/$_selectedTeamId'),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.divider),
                bottom: BorderSide(color: AppColors.divider),
              ),
            ),
            child: Column(
              children: [
                if (keyBatter != null)
                  _RecordHighlightRow(
                    tag: keyBatter.liveContext ? '현재 타자' : '오늘의 활약 타자',
                    name: keyBatter.name,
                    role: keyBatter.liveContext
                        ? keyBatter.contextLabel ?? '현재 타자'
                        : '${keyBatter.position}  ${keyBatter.order}번',
                    summary: keyBatter.liveContext
                        ? _hasLiveBatterStats(keyBatter)
                              ? '${keyBatter.atBats}타수 ${keyBatter.hits}안타'
                              : '공식 누적 기록 집계 전'
                        : '${keyBatter.atBats}타수 ${keyBatter.hits}안타  ${keyBatter.rbi}타점  ${keyBatter.runs}득점',
                    metricLabel: keyBatter.liveContext
                        ? _liveBatterMetricLabel(keyBatter)
                        : '앱 기준 활약 지수 $productionScore',
                    accent: accent,
                    badgeLabel: (keyBatterPlayer?.number ?? 0) > 0
                        ? '${keyBatterPlayer!.number}'
                        : null,
                    imageUrl: keyBatterImageUrl,
                    actionLabel: keyBatterPlayer == null ? null : '선수 기록 보기',
                    onTap: keyBatterPlayer == null
                        ? null
                        : () => _pushPlayerDetail(keyBatterPlayer, season),
                  ),
                if (keyPitcher != null)
                  _RecordHighlightRow(
                    tag: keyPitcher.liveContext
                        ? (keyPitcher.decision == 'LIVE' ? '현재 투수' : '선발 투수')
                        : '호투',
                    name: keyPitcher.name,
                    role: keyPitcher.liveContext
                        ? keyPitcher.contextLabel ?? '투수 정보'
                        : keyPitcher.decision == null
                        ? '투수'
                        : '투수  ${keyPitcher.decision}',
                    summary: keyPitcher.liveContext
                        ? '공식 누적 기록 집계 전'
                        : '${keyPitcher.innings}이닝  ${keyPitcher.hits}피안타  ${keyPitcher.earnedRuns}자책  ${keyPitcher.strikeouts}탈삼진',
                    metricLabel: keyPitcher.liveContext
                        ? (keyPitcher.decision ?? 'LIVE')
                        : '앱 기준 투구 효율 +$efficiencyScore',
                    accent: AppColors.live,
                    badgeLabel: (keyPitcherPlayer?.number ?? 0) > 0
                        ? '${keyPitcherPlayer!.number}'
                        : null,
                    imageUrl: keyPitcherImageUrl,
                    actionLabel: keyPitcherPlayer == null ? null : '선수 기록 보기',
                    onTap: keyPitcherPlayer == null
                        ? null
                        : () => _pushPlayerDetail(keyPitcherPlayer, season),
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
            child: _buildBatterRecordRow(
              entry.value,
              accent,
              playersByName,
              season,
            ),
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
            child: _buildPitcherRecordRow(
              entry.value,
              accent,
              playersByName,
              season,
            ),
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
    int season,
  ) {
    final player = _resolvePlayer(playersByName, batter.name);
    final imageUrl = _boxscoreRowImageUrl(
      imageUrl: batter.imageUrl,
      playerId: batter.playerId,
      fallbackPlayer: player,
      season: season,
    );
    final todayAvg = batter.atBats > 0 ? (batter.hits / batter.atBats) : 0.0;
    return _RecordDataRow(
      onTap: player == null ? null : () => _pushPlayerDetail(player, season),
      badgeLabel: (player?.number ?? 0) > 0 ? '${player!.number}' : null,
      imageUrl: imageUrl,
      name: batter.name,
      meta: batter.liveContext
          ? batter.contextLabel ?? '현재 타자'
          : '${batter.position}  ${batter.order}번',
      actionLabel: player == null ? null : '선수 기록 보기',
      accent: accent,
      supportingLabels: batter.liveContext
          ? const []
          : _batterAdvancedLabels(batter),
      values: batter.liveContext
          ? _liveBatterRecordCells(batter, accent)
          : [
              _RecordCell(label: '타수', value: '${batter.atBats}', width: 38),
              _RecordCell(label: '안타', value: '${batter.hits}', width: 38),
              _RecordCell(label: '타점', value: '${batter.rbi}', width: 38),
              _RecordCell(label: '득점', value: '${batter.runs}', width: 38),
              _RecordCell(
                label: '타율',
                value: todayAvg.toStringAsFixed(3),
                width: 54,
                color: accent,
              ),
            ],
    );
  }

  bool _hasLiveBatterStats(BatterRecord batter) {
    return batter.liveContext && (batter.atBats > 0 || batter.hits > 0);
  }

  String _liveBatterMetricLabel(BatterRecord batter) {
    if (!_hasLiveBatterStats(batter) || batter.atBats <= 0) {
      return 'LIVE';
    }
    return (batter.hits / batter.atBats).toStringAsFixed(3);
  }

  List<_RecordCell> _liveBatterRecordCells(BatterRecord batter, Color accent) {
    if (!_hasLiveBatterStats(batter)) {
      return const [
        _RecordCell(label: '타수', value: '-', width: 38),
        _RecordCell(label: '안타', value: '-', width: 38),
        _RecordCell(label: '타점', value: '-', width: 38),
        _RecordCell(label: '득점', value: '-', width: 38),
        _RecordCell(label: '타율', value: '-', width: 54),
      ];
    }
    return [
      _RecordCell(label: '타수', value: '${batter.atBats}', width: 38),
      _RecordCell(label: '안타', value: '${batter.hits}', width: 38),
      const _RecordCell(label: '타점', value: '-', width: 38),
      const _RecordCell(label: '득점', value: '-', width: 38),
      _RecordCell(
        label: '타율',
        value: batter.atBats > 0
            ? (batter.hits / batter.atBats).toStringAsFixed(3)
            : '-',
        width: 54,
        color: batter.atBats > 0 ? accent : AppColors.textDisabled,
      ),
    ];
  }

  Widget _buildPitcherRecordRow(
    PitcherRecord pitcher,
    Color accent,
    Map<String, PlayerProfile> playersByName,
    int season,
  ) {
    final player = _resolvePlayer(playersByName, pitcher.name);
    final imageUrl = _boxscoreRowImageUrl(
      imageUrl: pitcher.imageUrl,
      playerId: pitcher.playerId,
      fallbackPlayer: player,
      season: season,
    );
    return _RecordDataRow(
      onTap: player == null ? null : () => _pushPlayerDetail(player, season),
      badgeLabel: (player?.number ?? 0) > 0 ? '${player!.number}' : null,
      imageUrl: imageUrl,
      name: pitcher.name,
      meta: pitcher.liveContext ? pitcher.contextLabel ?? '투수 정보' : '투수 기록',
      actionLabel: player == null ? null : '선수 기록 보기',
      accent: AppColors.live,
      supportingLabels: pitcher.liveContext
          ? const []
          : _pitcherAdvancedLabels(pitcher),
      values: pitcher.liveContext
          ? [
              const _RecordCell(label: '이닝', value: '-', width: 42),
              const _RecordCell(label: '피안타', value: '-', width: 42),
              const _RecordCell(label: '자책', value: '-', width: 38),
              const _RecordCell(label: '삼진', value: '-', width: 38),
              _RecordCell(
                label: '결과',
                value: pitcher.decision ?? '-',
                width: 42,
                color: pitcher.decision == null
                    ? AppColors.textDisabled
                    : accent,
              ),
            ]
          : [
              _RecordCell(label: '이닝', value: pitcher.innings, width: 42),
              _RecordCell(label: '피안타', value: '${pitcher.hits}', width: 42),
              _RecordCell(
                label: '자책',
                value: '${pitcher.earnedRuns}',
                width: 38,
              ),
              _RecordCell(
                label: '삼진',
                value: '${pitcher.strikeouts}',
                width: 38,
              ),
              _RecordCell(
                label: '결과',
                value: pitcher.decision ?? '-',
                width: 42,
                color: pitcher.decision == null
                    ? AppColors.textDisabled
                    : accent,
              ),
            ],
    );
  }

  BatterRecord? _keyBatter(
    List<BatterRecord> batters, {
    required bool isLiveContext,
  }) {
    if (batters.isEmpty) {
      return null;
    }
    if (isLiveContext) {
      return batters.firstWhere(
        (batter) => batter.liveContext,
        orElse: () => batters.first,
      );
    }
    return batters.reduce((a, b) {
      final aScore = (a.hits * 3) + (a.rbi * 2) + a.runs;
      final bScore = (b.hits * 3) + (b.rbi * 2) + b.runs;
      return aScore >= bScore ? a : b;
    });
  }

  PitcherRecord? _keyPitcher(
    List<PitcherRecord> pitchers, {
    required bool isLiveContext,
  }) {
    if (pitchers.isEmpty) {
      return null;
    }
    if (isLiveContext) {
      return pitchers.firstWhere(
        (pitcher) => pitcher.liveContext && pitcher.decision == 'LIVE',
        orElse: () => pitchers.first,
      );
    }
    return pitchers.reduce((a, b) {
      final aScore = (a.strikeouts * 2) - (a.walks * 2) - (a.earnedRuns * 3);
      final bScore = (b.strikeouts * 2) - (b.walks * 2) - (b.earnedRuns * 3);
      return aScore >= bScore ? a : b;
    });
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

  List<String> _batterAdvancedLabels(BatterRecord batter) {
    return [
      if (batter.totalBases != null) '루타 ${batter.totalBases}',
      if ((batter.extraBaseHits ?? 0) > 0) '장타 ${batter.extraBaseHits}',
      if (batter.slugging != null) 'SLG ${batter.slugging!.toStringAsFixed(3)}',
      if ((batter.walks ?? 0) > 0) '볼넷 ${batter.walks}',
      if ((batter.hitByPitch ?? 0) > 0) '사구 ${batter.hitByPitch}',
      if ((batter.strikeouts ?? 0) > 0) '삼진 ${batter.strikeouts}',
      if ((batter.stolenBases ?? 0) > 0) '도루 ${batter.stolenBases}',
    ];
  }

  List<String> _pitcherAdvancedLabels(PitcherRecord pitcher) {
    return [
      if ((pitcher.pitchCount ?? 0) > 0) '투구 ${pitcher.pitchCount}',
      if (pitcher.gameEra != null) 'ERA ${pitcher.gameEra!.toStringAsFixed(2)}',
      if (pitcher.gameWhip != null)
        'WHIP ${pitcher.gameWhip!.toStringAsFixed(2)}',
      if ((pitcher.runs ?? 0) > 0) '실점 ${pitcher.runs}',
    ];
  }

  void _prefetchBoxscorePlayerImages(Iterable<String?> imageUrls) {
    final urls = <String>{
      for (final rawUrl in imageUrls)
        if ((rawUrl?.trim() ?? '').isNotEmpty) rawUrl!.trim(),
    }.toList()..sort();
    if (urls.isEmpty) {
      return;
    }
    final signature = urls.join('|');
    if (_lastPrefetchedImageSignature == signature) {
      return;
    }
    _lastPrefetchedImageSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        precacheKboPlayerImageUrls(context, urls, limit: 80).catchError((_) {}),
      );
    });
  }

  List<String> _boxscorePlayerImageUrlsForRows(
    TeamBoxscoreData team,
    Map<String, PlayerProfile> playersByName, {
    required int season,
  }) {
    final imageUrls = <String>[];
    final seen = <String>{};

    void addUrl(String? rawUrl) {
      final imageUrl = rawUrl?.trim() ?? '';
      if (imageUrl.isEmpty || !seen.add(imageUrl)) {
        return;
      }
      imageUrls.add(imageUrl);
    }

    for (final batter in team.batters) {
      addUrl(
        _boxscoreRowImageUrl(
          imageUrl: batter.imageUrl,
          playerId: batter.playerId,
          fallbackPlayer: _resolvePlayer(playersByName, batter.name),
          season: season,
        ),
      );
    }
    for (final pitcher in team.pitchers) {
      addUrl(
        _boxscoreRowImageUrl(
          imageUrl: pitcher.imageUrl,
          playerId: pitcher.playerId,
          fallbackPlayer: _resolvePlayer(playersByName, pitcher.name),
          season: season,
        ),
      );
    }
    return imageUrls;
  }

  String? _boxscoreRowImageUrl({
    required String? imageUrl,
    required String? playerId,
    required PlayerProfile? fallbackPlayer,
    required int season,
  }) {
    final sourceImageUrl = imageUrl?.trim() ?? '';
    if (sourceImageUrl.isNotEmpty) {
      return sourceImageUrl;
    }
    final cleanedPlayerId = playerId?.trim() ?? '';
    if (cleanedPlayerId.isNotEmpty) {
      return kboPlayerImageUrl(season: season, playerId: cleanedPlayerId);
    }
    return _playerImageUrlFromProfile(fallbackPlayer, season);
  }

  String? _playerImageUrlFromProfile(PlayerProfile? player, int season) {
    if (player == null) {
      return null;
    }
    return playerProfileImageUrl(player, season: season)?.trim();
  }

  void _pushPlayerDetail(PlayerProfile player, int season) {
    context.push('/records/player/${player.id}?season=$season');
  }

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

int _seasonFromGameId(String gameId) {
  if (gameId.length >= 4) {
    final parsed = int.tryParse(gameId.substring(0, 4));
    if (parsed != null) {
      return parsed;
    }
  }
  return kboCurrentSeason();
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
  final String title;
  final List<_SummaryMetric> metrics;

  const _BoxscoreSummaryPanel({
    required this.teamId,
    required this.teamName,
    required this.accent,
    required this.title,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final useReflowLayout =
            _usesCompactBoxscoreLayout(context) || constraints.maxWidth <= 328;
        final useSingleColumnMetrics = textScale >= 1.5;
        final metricWidth = useSingleColumnMetrics
            ? constraints.maxWidth
            : (constraints.maxWidth - 8) / 2;

        return Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border(
              top: BorderSide(color: AppColors.divider),
              bottom: BorderSide(color: AppColors.divider),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TeamLogo(teamId: teamId, fallback: teamName, size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
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
                if (useReflowLayout)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (int i = 0; i < metrics.length; i++)
                        SizedBox(
                          key: ValueKey('boxscore-summary-metric-$i'),
                          width: metricWidth,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              border: Border.all(color: AppColors.divider),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              child: _SummaryMetricTile(
                                metric: metrics[i],
                                allowMultipleLines: true,
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                else
                  Row(
                    children: [
                      for (int i = 0; i < metrics.length; i++) ...[
                        Expanded(
                          key: ValueKey('boxscore-summary-metric-$i'),
                          child: _SummaryMetricTile(metric: metrics[i]),
                        ),
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
        );
      },
    );
  }
}

class _SummaryMetricTile extends StatelessWidget {
  final _SummaryMetric metric;
  final bool allowMultipleLines;

  const _SummaryMetricTile({
    required this.metric,
    this.allowMultipleLines = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          metric.label,
          maxLines: allowMultipleLines ? null : 1,
          overflow: allowMultipleLines ? null : TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          metric.value,
          maxLines: allowMultipleLines ? null : 1,
          overflow: allowMultipleLines ? null : TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
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

class _BoxscoreTeamMetrics {
  final int runs;
  final int hits;
  final int rbi;
  final int extraBaseHits;

  const _BoxscoreTeamMetrics({
    required this.runs,
    required this.hits,
    required this.rbi,
    required this.extraBaseHits,
  });

  factory _BoxscoreTeamMetrics.from(TeamBoxscoreData team) {
    return _BoxscoreTeamMetrics(
      runs: team.batters.fold<int>(0, (sum, batter) => sum + batter.runs),
      hits: team.batters.fold<int>(0, (sum, batter) => sum + batter.hits),
      rbi: team.batters.fold<int>(0, (sum, batter) => sum + batter.rbi),
      extraBaseHits: team.batters.fold<int>(
        0,
        (sum, batter) => sum + (batter.extraBaseHits ?? 0),
      ),
    );
  }
}

class _TeamComparisonStrip extends StatelessWidget {
  final String selectedTeamName;
  final String opponentTeamName;
  final _BoxscoreTeamMetrics selected;
  final _BoxscoreTeamMetrics opponent;
  final Color accent;

  const _TeamComparisonStrip({
    required this.selectedTeamName,
    required this.opponentTeamName,
    required this.selected,
    required this.opponent,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.divider),
        color: AppColors.card.withValues(alpha: 0.72),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '팀 비교',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ComparisonMetric(
                label: '득점',
                selectedValue: selected.runs,
                opponentValue: opponent.runs,
                selectedTeamName: selectedTeamName,
                opponentTeamName: opponentTeamName,
                accent: accent,
              ),
              _ComparisonMetric(
                label: '안타',
                selectedValue: selected.hits,
                opponentValue: opponent.hits,
                selectedTeamName: selectedTeamName,
                opponentTeamName: opponentTeamName,
                accent: accent,
              ),
              _ComparisonMetric(
                label: '타점',
                selectedValue: selected.rbi,
                opponentValue: opponent.rbi,
                selectedTeamName: selectedTeamName,
                opponentTeamName: opponentTeamName,
                accent: accent,
              ),
              _ComparisonMetric(
                label: '장타',
                selectedValue: selected.extraBaseHits,
                opponentValue: opponent.extraBaseHits,
                selectedTeamName: selectedTeamName,
                opponentTeamName: opponentTeamName,
                accent: accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComparisonMetric extends StatelessWidget {
  final String label;
  final int selectedValue;
  final int opponentValue;
  final String selectedTeamName;
  final String opponentTeamName;
  final Color accent;

  const _ComparisonMetric({
    required this.label,
    required this.selectedValue,
    required this.opponentValue,
    required this.selectedTeamName,
    required this.opponentTeamName,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final selectedLeading = selectedValue > opponentValue;
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textDisabled,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$selectedValue : $opponentValue',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              color: selectedLeading ? accent : AppColors.textPrimary,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            selectedLeading ? selectedTeamName : opponentTeamName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
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
  final String? badgeLabel;
  final String? imageUrl;
  final String? actionLabel;
  final VoidCallback? onTap;

  const _RecordHighlightRow({
    required this.tag,
    required this.name,
    required this.role,
    required this.summary,
    required this.metricLabel,
    required this.accent,
    this.badgeLabel,
    this.imageUrl,
    this.actionLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final useNarrowLayout = MediaQuery.sizeOf(context).width <= 340;

    return AppPressable(
      pressedScale: onTap == null ? 1 : 0.985,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 84),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          crossAxisAlignment: useNarrowLayout
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            _PlayerAvatar(
              accent: accent,
              badgeLabel: badgeLabel,
              imageUrl: imageUrl,
              size: useNarrowLayout ? 48 : 52,
            ),
            SizedBox(width: useNarrowLayout ? 8 : 12),
            Expanded(child: _buildDetails(useNarrowLayout: useNarrowLayout)),
            if (!useNarrowLayout) ...[
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 104),
                child: Text(
                  key: ValueKey('record-highlight-metric-$name'),
                  metricLabel,
                  maxLines: 2,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: metricLabel.length > 10 ? 12 : 15,
                    height: 1.15,
                    color: accent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Padding(
              padding: EdgeInsets.only(top: useNarrowLayout ? 4 : 0),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: onTap == null ? AppColors.textDisabled : accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetails({required bool useNarrowLayout}) {
    final nameAndRole = Text(
      key: ValueKey('record-highlight-name-$name'),
      '$name  $role',
      maxLines: useNarrowLayout ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w900,
        height: 1.2,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (useNarrowLayout) ...[
          _RecordTag(label: tag, accent: accent),
          const SizedBox(height: 5),
          nameAndRole,
        ] else
          Row(
            children: [
              _RecordTag(label: tag, accent: accent),
              const SizedBox(width: 8),
              Expanded(child: nameAndRole),
            ],
          ),
        const SizedBox(height: 7),
        Text(
          summary,
          maxLines: useNarrowLayout ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
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
        if (useNarrowLayout) ...[
          const SizedBox(height: 6),
          Text(
            key: ValueKey('record-highlight-metric-$name'),
            metricLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: metricLabel.length > 10 ? 12 : 15,
              height: 1.15,
              color: accent,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ],
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
    if (_usesCompactBoxscoreLayout(context)) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 34,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              labels.first,
              style: TextStyle(
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
                style: TextStyle(
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
  final String? badgeLabel;
  final String? imageUrl;
  final String name;
  final String meta;
  final String? actionLabel;
  final Color accent;
  final List<String> supportingLabels;
  final List<_RecordCell> values;

  const _RecordDataRow({
    required this.onTap,
    required this.badgeLabel,
    required this.imageUrl,
    required this.name,
    required this.meta,
    required this.actionLabel,
    required this.accent,
    this.supportingLabels = const [],
    required this.values,
  });

  @override
  Widget build(BuildContext context) {
    final useReflowLayout = _usesCompactBoxscoreLayout(context);
    final semanticLabel = [
      name,
      meta.replaceAll(RegExp(r'\s+'), ' ').trim(),
      for (final value in values) '${value.label} ${value.value}',
      ...supportingLabels,
      ?actionLabel,
    ].join(', ');

    return Semantics(
      key: ValueKey('boxscore-record-row-$name'),
      container: true,
      excludeSemantics: true,
      label: semanticLabel,
      button: onTap != null,
      enabled: onTap == null ? null : true,
      child: AppPressable(
        pressedScale: onTap == null ? 1 : 0.99,
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: actionLabel == null ? 58 : 68),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: useReflowLayout
              ? _buildReflowLayout(context)
              : _buildTableLayout(),
        ),
      ),
    );
  }

  Widget _buildReflowLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PlayerAvatar(
              accent: accent,
              badgeLabel: badgeLabel,
              imageUrl: imageUrl,
              size: 42,
              radius: 10,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                key: ValueKey('boxscore-record-identity-$name'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    style: TextStyle(
                      fontSize: 12,
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
            if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 8),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: accent,
                ),
              ),
          ],
        ),
        if (supportingLabels.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final label in supportingLabels)
                _RecordSupportLabel(label: label, accent: accent),
            ],
          ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final useSingleColumn =
                MediaQuery.textScalerOf(context).scale(1) >= 1.5;
            final metricWidth = useSingleColumn
                ? constraints.maxWidth
                : (constraints.maxWidth - 8) / 2;
            return Wrap(
              key: ValueKey('boxscore-record-metrics-$name'),
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in values)
                  SizedBox(
                    width: metricWidth,
                    child: _RecordCompactMetric(cell: value),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildTableLayout() {
    return Row(
      children: [
        _PlayerAvatar(
          accent: accent,
          badgeLabel: badgeLabel,
          imageUrl: imageUrl,
          size: 42,
          radius: 10,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            key: ValueKey('boxscore-record-identity-$name'),
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
                      style: TextStyle(
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
              if (supportingLabels.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final label in supportingLabels)
                      _RecordSupportLabel(label: label, accent: accent),
                  ],
                ),
              ],
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
    );
  }
}

class _RecordCompactMetric extends StatelessWidget {
  final _RecordCell cell;

  const _RecordCompactMetric({required this.cell});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              cell.label,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            cell.value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 16,
              color: cell.color ?? AppColors.textPrimary,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordSupportLabel extends StatelessWidget {
  final String label;
  final Color accent;

  const _RecordSupportLabel({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: accent,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _RecordCell extends StatelessWidget {
  final String label;
  final String value;
  final double width;
  final Color? color;

  const _RecordCell({
    required this.label,
    required this.value,
    required this.width,
    this.color,
  });

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
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: compact ? 12 : 16,
            color: AppColors.accent,
            fontWeight: FontWeight.w900,
          ),
        ),
        Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.accent),
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
    final colors = AppTheme.colorsOf(context);
    final useReflowLayout = _usesCompactBoxscoreLayout(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final team = KboTeams.resolve(
      id: teamId,
      name: teamName,
      shortName: teamName,
    );
    final accent = colors.readableAccent(team?.primaryColor ?? colors.accent);

    return AppPressable(
      key: ValueKey('boxscore-team-toggle-${sideLabel.toLowerCase()}'),
      onTap: onTap,
      pressedScale: 0.985,
      semanticSelected: active,
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.card : AppColors.background,
          border: Border.all(color: active ? accent : AppColors.divider),
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
                      color: active ? accent : AppColors.textDisabled,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    teamName,
                    maxLines: useReflowLayout ? null : 1,
                    overflow: useReflowLayout ? null : TextOverflow.ellipsis,
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
    return KboTeamLogoImage(
      teamId: teamId,
      fallback: fallback,
      size: size,
      padding: size <= 34 ? 1.5 : 2,
    );
  }
}

class _PlayerAvatar extends StatelessWidget {
  final Color accent;
  final String? badgeLabel;
  final String? imageUrl;
  final double size;
  final double radius;

  const _PlayerAvatar({
    required this.accent,
    this.badgeLabel,
    this.imageUrl,
    this.size = 52,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _imageUrl == null ? _fallbackAvatar() : _networkAvatar(),
        if (badgeLabel != null) _numberBadge(context),
      ],
    );
  }

  String? get _imageUrl {
    final value = imageUrl?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Widget _networkAvatar() {
    final cacheSize = kboPlayerImageCacheSize(size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: _imageUrl!,
        httpHeaders: kboPlayerImageHeaders,
        cacheManager: kboPlayerImageCacheManager,
        width: size,
        height: size,
        memCacheWidth: cacheSize,
        memCacheHeight: cacheSize,
        maxWidthDiskCache: cacheSize,
        maxHeightDiskCache: cacheSize,
        fit: BoxFit.cover,
        placeholder: (_, _) => _fallbackAvatar(),
        errorWidget: (_, _, _) => _fallbackAvatar(),
      ),
    );
  }

  Widget _fallbackAvatar() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.person_rounded, color: accent, size: size * 0.54),
    );
  }

  Widget _numberBadge(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    return Positioned(
      right: -4,
      bottom: -4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.background, width: 1.5),
        ),
        child: Text(
          badgeLabel!,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: colors.readableForegroundOn(accent),
          ),
        ),
      ),
    );
  }
}
