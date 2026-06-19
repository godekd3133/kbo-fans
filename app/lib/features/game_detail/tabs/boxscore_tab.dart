import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/team_data.dart';
import '../../../core/theme/app_theme.dart';
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
  final Set<String> _expandedRows = <String>{};

  String get _selectedTeamName => _showAway ? widget.awayName : widget.homeName;
  String get _selectedTeamId =>
      _showAway ? widget.awayTeamId : widget.homeTeamId;
  String get _opponentTeamName => _showAway ? widget.homeName : widget.awayName;
  String get _opponentTeamId =>
      _showAway ? widget.homeTeamId : widget.awayTeamId;

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
        final opponent = _showAway ? boxscore.home : boxscore.away;
        if (!boxscore.officialAvailable || !selected.hasDisplayableRecords) {
          return _buildUnavailableState('공식 박스스코어 업데이트 전입니다');
        }

        final season = DateTime.now().year;
        final playersAsync = _selectedTeamId.isEmpty
            ? const AsyncValue<List<PlayerProfile>>.data(<PlayerProfile>[])
            : ref.watch(teamPlayersProvider('$_selectedTeamId|$season'));
        return playersAsync.when(
          loading: () => _buildContent(selected, opponent, const {}),
          error: (_, _) => _buildContent(selected, opponent, const {}),
          data: (players) => _buildContent(selected, opponent, {
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sports_baseball, size: 48, color: AppColors.divider),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.textDisabled)),
        ],
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
    TeamBoxscoreData selected,
    TeamBoxscoreData opponent,
    Map<String, PlayerProfile> playersByName,
  ) {
    final team = KboTeams.byId(_selectedTeamId);
    final accent = team?.primaryColor ?? AppColors.accent;
    final batters = selected.batters;
    final pitchers = selected.pitchers;
    final selectedMetrics = _TeamBoxscoreMetrics.from(selected);
    final opponentMetrics = _TeamBoxscoreMetrics.from(opponent);

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryHeader(
          teamId: _selectedTeamId,
          teamName: _selectedTeamName,
          accent: accent,
          title: '오늘 기록 요약',
          statTiles: [
            _StatTile(label: '타수', value: '$totalAtBats'),
            _StatTile(label: '득점', value: '$totalRuns'),
            _StatTile(label: '안타', value: '$totalHits'),
            _StatTile(label: '타점', value: '$totalRbi'),
            _StatTile(
              label: '팀 타율',
              value: teamBattingAverage.toStringAsFixed(3),
            ),
          ],
        ),
        if (opponent.hasDisplayableRecords) ...[
          const SizedBox(height: 12),
          _TeamComparisonCard(
            selectedTeamId: _selectedTeamId,
            selectedTeamName: _selectedTeamName,
            opponentTeamId: _opponentTeamId,
            opponentTeamName: _opponentTeamName,
            selected: selectedMetrics,
            opponent: opponentMetrics,
            accent: accent,
          ),
        ],
        if (keyBatter != null || keyPitcher != null) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (keyBatter != null)
                _HighlightCard(
                  title: '핵심 타자',
                  name: keyBatter.name,
                  accent: accent,
                  metricLabel: '오늘 생산 +${_batterProductionScore(keyBatter)}',
                  imageUrl:
                      keyBatterPlayer?.imageUrl ??
                      _resolveImageUrl(playerImageMap, keyBatter.name),
                  badgeLabel: (keyBatterPlayer?.number ?? 0) > 0
                      ? '${keyBatterPlayer!.number}'
                      : null,
                  summary:
                      '안타 ${keyBatter.hits} · 타점 ${keyBatter.rbi} · 득점 ${keyBatter.runs}',
                  onTap: keyBatterPlayer == null
                      ? null
                      : () => _openPlayerDetail(keyBatterPlayer),
                ),
              if (keyPitcher != null)
                _HighlightCard(
                  title: '핵심 투수',
                  name: keyPitcher.name,
                  accent: AppColors.live,
                  metricLabel: '오늘 효율 +${_pitcherEfficiencyScore(keyPitcher)}',
                  imageUrl:
                      keyPitcherPlayer?.imageUrl ??
                      _resolveImageUrl(playerImageMap, keyPitcher.name),
                  badgeLabel: (keyPitcherPlayer?.number ?? 0) > 0
                      ? '${keyPitcherPlayer!.number}'
                      : null,
                  summary:
                      '이닝 ${keyPitcher.innings} · 삼진 ${keyPitcher.strikeouts} · 자책 ${keyPitcher.earnedRuns}',
                  onTap: keyPitcherPlayer == null
                      ? null
                      : () => _openPlayerDetail(keyPitcherPlayer),
                ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        const Text(
          '타자',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        ...batters.asMap().entries.map(
          (entry) => AppMotionListItem(
            index: entry.key,
            child: _buildBatterCard(entry.value, accent, playersByName),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          '투수',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        ...pitchers.asMap().entries.map(
          (entry) => AppMotionListItem(
            index: batters.length + entry.key,
            child: _buildPitcherCard(entry.value, accent, playersByName),
          ),
        ),
      ],
    );
  }

  Widget _buildBatterCard(
    BatterRecord batter,
    Color accent,
    Map<String, PlayerProfile> playersByName,
  ) {
    final player = _resolvePlayer(playersByName, batter.name);
    final imageUrl =
        player?.imageUrl ??
        _resolveImageUrl(_playerImageMap(playersByName), batter.name);
    final todayAvg = batter.atBats > 0 ? (batter.hits / batter.atBats) : 0.0;
    final rowKey = _rowKey('batter', batter.name);
    final expanded = _expandedRows.contains(rowKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppPressable(
        onTap: player == null ? null : () => _openPlayerDetail(player),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              _PlayerAvatar(
                imageUrl: imageUrl,
                fallbackLabel: batter.name,
                accent: accent,
                badgeLabel: (player?.number ?? 0) > 0
                    ? '${player!.number}'
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            batter.name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _InfoPill(label: '${batter.order}번', accent: accent),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${batter.position} 포지션',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoPill(
                          label: '생산 +${_batterProductionScore(batter)}',
                          accent: AppColors.positive,
                        ),
                        ..._batterAdvancedPills(batter),
                        _InfoPill(
                          label: '오늘 타율 ${todayAvg.toStringAsFixed(3)}',
                          accent: accent,
                        ),
                        _InfoPill(
                          label: '타수 ${batter.atBats}',
                          accent: AppColors.textDisabled,
                          subtle: true,
                        ),
                        _InfoPill(
                          label: '안타 ${batter.hits}',
                          accent: AppColors.positive,
                        ),
                        _InfoPill(
                          label: '타점 ${batter.rbi}',
                          accent: AppColors.live,
                        ),
                        _InfoPill(
                          label: '득점 ${batter.runs}',
                          accent: AppColors.ballYellow,
                        ),
                      ],
                    ),
                    if (player != null) ...[
                      const SizedBox(height: 8),
                      const _RecordsLinkCue(),
                    ],
                    const SizedBox(height: 8),
                    _BoxscoreDetailToggle(
                      expanded: expanded,
                      onTap: () => _toggleRow(rowKey),
                    ),
                    if (expanded)
                      _BatterDetailPanel(
                        batter: batter,
                        player: player,
                        accent: accent,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPitcherCard(
    PitcherRecord pitcher,
    Color accent,
    Map<String, PlayerProfile> playersByName,
  ) {
    final player = _resolvePlayer(playersByName, pitcher.name);
    final imageUrl =
        player?.imageUrl ??
        _resolveImageUrl(_playerImageMap(playersByName), pitcher.name);
    final rowKey = _rowKey('pitcher', pitcher.name);
    final expanded = _expandedRows.contains(rowKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppPressable(
        onTap: player == null ? null : () => _openPlayerDetail(player),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PlayerAvatar(
                    imageUrl: imageUrl,
                    fallbackLabel: pitcher.name,
                    accent: accent,
                    badgeLabel: (player?.number ?? 0) > 0
                        ? '${player!.number}'
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pitcher.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '투수 기록',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pitcher.decision != null) ...[
                    const SizedBox(width: 8),
                    _InfoPill(
                      label: pitcher.decision!,
                      accent: AppColors.positive,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoPill(
                    label: '효율 +${_pitcherEfficiencyScore(pitcher)}',
                    accent: AppColors.positive,
                  ),
                  ..._pitcherAdvancedPills(pitcher),
                  _InfoPill(label: '이닝 ${pitcher.innings}', accent: accent),
                  _InfoPill(
                    label: '안타 ${pitcher.hits}',
                    accent: AppColors.textDisabled,
                    subtle: true,
                  ),
                  _InfoPill(
                    label: '삼진 ${pitcher.strikeouts}',
                    accent: AppColors.live,
                  ),
                  _InfoPill(
                    label: '사사구 ${pitcher.walks}',
                    accent: AppColors.ballYellow,
                  ),
                  _InfoPill(
                    label: '자책 ${pitcher.earnedRuns}',
                    accent: AppColors.textDisabled,
                    subtle: true,
                  ),
                ],
              ),
              if (player != null) ...[
                const SizedBox(height: 10),
                const _RecordsLinkCue(),
              ],
              const SizedBox(height: 8),
              _BoxscoreDetailToggle(
                expanded: expanded,
                onTap: () => _toggleRow(rowKey),
              ),
              if (expanded)
                _PitcherDetailPanel(
                  pitcher: pitcher,
                  player: player,
                  accent: accent,
                ),
            ],
          ),
        ),
      ),
    );
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

  int _batterProductionScore(BatterRecord batter) {
    return (batter.hits * 3) + (batter.rbi * 2) + batter.runs;
  }

  int _pitcherEfficiencyScore(PitcherRecord pitcher) {
    return (pitcher.strikeouts * 2) -
        (pitcher.walks * 2) -
        (pitcher.earnedRuns * 3);
  }

  String _rowKey(String type, String rawName) {
    return '$_selectedTeamId:$type:${_normalizeName(rawName)}';
  }

  void _toggleRow(String rowKey) {
    setState(() {
      if (!_expandedRows.remove(rowKey)) {
        _expandedRows.add(rowKey);
      }
    });
  }

  List<Widget> _batterAdvancedPills(BatterRecord batter) {
    return [
      if (batter.totalBases != null)
        _InfoPill(label: '루타 ${batter.totalBases}', accent: AppColors.accent),
      if ((batter.extraBaseHits ?? 0) > 0)
        _InfoPill(label: '장타 ${batter.extraBaseHits}', accent: AppColors.live),
      if (batter.slugging != null)
        _InfoPill(
          label: 'SLG ${batter.slugging!.toStringAsFixed(3)}',
          accent: AppColors.accent,
        ),
      if ((batter.walks ?? 0) > 0)
        _InfoPill(label: '볼넷 ${batter.walks}', accent: AppColors.ballYellow),
      if ((batter.hitByPitch ?? 0) > 0)
        _InfoPill(
          label: '사구 ${batter.hitByPitch}',
          accent: AppColors.ballYellow,
        ),
      if ((batter.strikeouts ?? 0) > 0)
        _InfoPill(
          label: '삼진 ${batter.strikeouts}',
          accent: AppColors.textDisabled,
          subtle: true,
        ),
      if ((batter.stolenBases ?? 0) > 0)
        _InfoPill(
          label: '도루 ${batter.stolenBases}',
          accent: AppColors.positive,
        ),
    ];
  }

  List<Widget> _pitcherAdvancedPills(PitcherRecord pitcher) {
    return [
      if ((pitcher.pitchCount ?? 0) > 0)
        _InfoPill(label: '투구 ${pitcher.pitchCount}', accent: AppColors.accent),
      if (pitcher.gameEra != null)
        _InfoPill(
          label: 'ERA ${pitcher.gameEra!.toStringAsFixed(2)}',
          accent: AppColors.live,
        ),
      if (pitcher.gameWhip != null)
        _InfoPill(
          label: 'WHIP ${pitcher.gameWhip!.toStringAsFixed(2)}',
          accent: AppColors.accent,
        ),
      if ((pitcher.runs ?? 0) > 0)
        _InfoPill(label: '실점 ${pitcher.runs}', accent: AppColors.ballYellow),
    ];
  }

  void _openPlayerDetail(PlayerProfile player) {
    context.push('/records/player/${player.id}?season=${DateTime.now().year}');
  }
}

class _TeamBoxscoreMetrics {
  final int runs;
  final int hits;
  final int rbi;
  final int pitcherStrikeouts;
  final int? extraBaseHits;
  final int? batterWalks;

  const _TeamBoxscoreMetrics({
    required this.runs,
    required this.hits,
    required this.rbi,
    required this.pitcherStrikeouts,
    required this.extraBaseHits,
    required this.batterWalks,
  });

  factory _TeamBoxscoreMetrics.from(TeamBoxscoreData team) {
    return _TeamBoxscoreMetrics(
      runs: team.batters.fold<int>(0, (sum, batter) => sum + batter.runs),
      hits: team.batters.fold<int>(0, (sum, batter) => sum + batter.hits),
      rbi: team.batters.fold<int>(0, (sum, batter) => sum + batter.rbi),
      pitcherStrikeouts: team.pitchers.fold<int>(
        0,
        (sum, pitcher) => sum + pitcher.strikeouts,
      ),
      extraBaseHits: _sumKnownInt(
        team.batters.map((batter) => batter.extraBaseHits),
      ),
      batterWalks: _sumKnownInt(team.batters.map((batter) => batter.walks)),
    );
  }
}

int? _sumKnownInt(Iterable<int?> values) {
  var hasKnown = false;
  var total = 0;
  for (final value in values) {
    if (value == null) {
      continue;
    }
    hasKnown = true;
    total += value;
  }
  return hasKnown ? total : null;
}

String _knownIntText(int? value) => value == null ? '-' : '$value';

List<Widget> _seasonPills(PlayerProfile? player) {
  if (player == null) {
    return const <Widget>[];
  }
  return [
    if (player.avg != null)
      _InfoPill(
        label: 'AVG ${_formatThreeNoLeadingZero(player.avg!)}',
        accent: AppColors.positive,
      ),
    if (player.ops != null)
      _InfoPill(
        label: 'OPS ${_formatThreeNoLeadingZero(player.ops!)}',
        accent: AppColors.accent,
      ),
    if (player.era != null)
      _InfoPill(
        label: 'ERA ${player.era!.toStringAsFixed(2)}',
        accent: AppColors.live,
      ),
    if (player.whip != null)
      _InfoPill(
        label: 'WHIP ${player.whip!.toStringAsFixed(2)}',
        accent: AppColors.accent,
      ),
  ];
}

String _formatThreeNoLeadingZero(double value) {
  final formatted = value.toStringAsFixed(3);
  if (formatted.startsWith('0')) {
    return formatted.substring(1);
  }
  return formatted;
}

class _TeamComparisonCard extends StatelessWidget {
  final String selectedTeamId;
  final String selectedTeamName;
  final String opponentTeamId;
  final String opponentTeamName;
  final _TeamBoxscoreMetrics selected;
  final _TeamBoxscoreMetrics opponent;
  final Color accent;

  const _TeamComparisonCard({
    required this.selectedTeamId,
    required this.selectedTeamName,
    required this.opponentTeamId,
    required this.opponentTeamName,
    required this.selected,
    required this.opponent,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <_ComparisonMetric>[
      _ComparisonMetric('득점', '${selected.runs}', '${opponent.runs}'),
      _ComparisonMetric('안타', '${selected.hits}', '${opponent.hits}'),
      _ComparisonMetric('타점', '${selected.rbi}', '${opponent.rbi}'),
      if (selected.extraBaseHits != null || opponent.extraBaseHits != null)
        _ComparisonMetric(
          '장타',
          _knownIntText(selected.extraBaseHits),
          _knownIntText(opponent.extraBaseHits),
        ),
      if (selected.batterWalks != null || opponent.batterWalks != null)
        _ComparisonMetric(
          '볼넷',
          _knownIntText(selected.batterWalks),
          _knownIntText(opponent.batterWalks),
        ),
      _ComparisonMetric(
        '탈삼진',
        '${selected.pitcherStrikeouts}',
        '${opponent.pitcherStrikeouts}',
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSub.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '팀 비교',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              _TeamMiniLabel(
                teamId: selectedTeamId,
                teamName: selectedTeamName,
              ),
              const SizedBox(width: 8),
              const Text(
                'vs',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textDisabled,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              _TeamMiniLabel(
                teamId: opponentTeamId,
                teamName: opponentTeamName,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _ComparisonMetricRow(metric: rows[i], accent: accent),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TeamMiniLabel extends StatelessWidget {
  final String teamId;
  final String teamName;

  const _TeamMiniLabel({required this.teamId, required this.teamName});

  @override
  Widget build(BuildContext context) {
    final team = KboTeams.resolve(
      id: teamId,
      name: teamName,
      shortName: teamName,
    );
    return Container(
      constraints: const BoxConstraints(maxWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: (team?.primaryColor ?? AppColors.card).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        teamName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ComparisonMetric {
  final String label;
  final String selected;
  final String opponent;

  const _ComparisonMetric(this.label, this.selected, this.opponent);
}

class _ComparisonMetricRow extends StatelessWidget {
  final _ComparisonMetric metric;
  final Color accent;

  const _ComparisonMetricRow({required this.metric, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(
            metric.selected,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                metric.label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 54,
          child: Text(
            metric.opponent,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _BoxscoreDetailToggle extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _BoxscoreDetailToggle({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: AppColors.textSecondary,
        ),
        icon: Icon(
          expanded
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          size: 18,
        ),
        label: Text(
          expanded ? '접기' : '상세 기록',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _BatterDetailPanel extends StatelessWidget {
  final BatterRecord batter;
  final PlayerProfile? player;
  final Color accent;

  const _BatterDetailPanel({
    required this.batter,
    required this.player,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final detailPills = <Widget>[
      if (batter.plateAppearances != null)
        _InfoPill(
          label: '타석 ${batter.plateAppearances}',
          accent: AppColors.textSecondary,
          subtle: true,
        ),
      _InfoPill(
        label: '타수 ${batter.atBats}',
        accent: AppColors.textSecondary,
        subtle: true,
      ),
      if (batter.totalBases != null)
        _InfoPill(label: '루타 ${batter.totalBases}', accent: accent),
      if (batter.extraBaseHits != null)
        _InfoPill(label: '장타 ${batter.extraBaseHits}', accent: AppColors.live),
      if (batter.walks != null)
        _InfoPill(label: '볼넷 ${batter.walks}', accent: AppColors.ballYellow),
      if (batter.hitByPitch != null)
        _InfoPill(
          label: '사구 ${batter.hitByPitch}',
          accent: AppColors.ballYellow,
        ),
      if (batter.strikeouts != null)
        _InfoPill(
          label: '삼진 ${batter.strikeouts}',
          accent: AppColors.textSecondary,
          subtle: true,
        ),
      if (batter.stolenBases != null)
        _InfoPill(
          label: '도루 ${batter.stolenBases}',
          accent: AppColors.positive,
        ),
    ];
    final seasonPills = _seasonPills(player);
    final contextPills = <Widget>[
      if (batter.hits >= 2)
        const _ContextBadge(label: '멀티히트', color: AppColors.positive),
      if (batter.rbi >= 2 || batter.runs >= 2)
        const _ContextBadge(label: '득점 관여', color: AppColors.live),
      if ((batter.homeRuns ?? 0) > 0)
        const _ContextBadge(label: '홈런', color: AppColors.ballYellow),
      if ((batter.stolenBases ?? 0) > 0)
        const _ContextBadge(label: '주루 기여', color: AppColors.accent),
    ];

    return _DetailPanel(
      children: [
        if (contextPills.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: contextPills),
        ],
        const SizedBox(height: 10),
        const _DetailTitle('오늘 세부 기록'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: detailPills),
        if (seasonPills.isNotEmpty) ...[
          const SizedBox(height: 12),
          const _DetailTitle('시즌 기록'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: seasonPills),
        ],
      ],
    );
  }
}

class _PitcherDetailPanel extends StatelessWidget {
  final PitcherRecord pitcher;
  final PlayerProfile? player;
  final Color accent;

  const _PitcherDetailPanel({
    required this.pitcher,
    required this.player,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final detailPills = <Widget>[
      if (pitcher.pitchCount != null)
        _InfoPill(label: '투구수 ${pitcher.pitchCount}', accent: accent),
      _InfoPill(label: '이닝 ${pitcher.innings}', accent: accent),
      _InfoPill(
        label: '피안타 ${pitcher.hits}',
        accent: AppColors.textSecondary,
        subtle: true,
      ),
      _InfoPill(label: '삼진 ${pitcher.strikeouts}', accent: AppColors.live),
      _InfoPill(label: '사사구 ${pitcher.walks}', accent: AppColors.ballYellow),
      _InfoPill(
        label: '자책 ${pitcher.earnedRuns}',
        accent: AppColors.textSecondary,
        subtle: true,
      ),
      if (pitcher.runs != null)
        _InfoPill(label: '실점 ${pitcher.runs}', accent: AppColors.ballYellow),
    ];
    final seasonPills = _seasonPills(player);
    final contextPills = <Widget>[
      if (pitcher.earnedRuns == 0 && (pitcher.inningsPitched ?? 0) > 0)
        const _ContextBadge(label: '무자책', color: AppColors.positive),
      if (pitcher.runs != null &&
          pitcher.runs == 0 &&
          (pitcher.inningsPitched ?? 0) > 0)
        const _ContextBadge(label: '무실점', color: AppColors.positive),
      if (pitcher.strikeouts >= 2)
        const _ContextBadge(label: '탈삼진 흐름', color: AppColors.live),
      if (pitcher.walks == 0 && (pitcher.inningsPitched ?? 0) > 0)
        const _ContextBadge(label: '무볼넷', color: AppColors.accent),
    ];

    return _DetailPanel(
      children: [
        if (contextPills.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: contextPills),
        ],
        const SizedBox(height: 10),
        const _DetailTitle('투수 세부 기록'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: detailPills),
        if (seasonPills.isNotEmpty) ...[
          const SizedBox(height: 12),
          const _DetailTitle('시즌 기록'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: seasonPills),
        ],
      ],
    );
  }
}

class _DetailPanel extends StatelessWidget {
  final List<Widget> children;

  const _DetailPanel({required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 1,
            width: double.infinity,
            color: AppColors.divider,
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _DetailTitle extends StatelessWidget {
  final String label;

  const _DetailTitle(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _ContextBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _ContextBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  final String teamId;
  final String teamName;
  final Color accent;
  final String title;
  final List<Widget> statTiles;

  const _SummaryHeader({
    required this.teamId,
    required this.teamName,
    required this.accent,
    required this.title,
    required this.statTiles,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.16), AppColors.card],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TeamLogo(teamId: teamId, fallback: teamName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      teamName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: statTiles),
        ],
      ),
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
      pressedScale: 0.97,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active ? AppColors.card : AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? (team?.primaryColor ?? AppColors.textPrimary)
                : AppColors.divider,
          ),
        ),
        child: Row(
          children: [
            _TeamLogo(teamId: teamId, fallback: teamName),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sideLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: active
                          ? (team?.primaryColor ?? AppColors.textPrimary)
                          : AppColors.textDisabled,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    teamName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
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

  const _TeamLogo({required this.teamId, required this.fallback});

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
      width: 46,
      height: 46,
      memCacheWidth: 138,
      memCacheHeight: 138,
      placeholder: (_, _) => _fallbackAvatar(team, fallback),
      errorWidget: (_, _, _) => _fallbackAvatar(team, fallback),
    );
  }

  Widget _fallbackAvatar(KboTeam? team, String fallback) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: (team?.primaryColor ?? AppColors.cardSub).withValues(
          alpha: 0.18,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        fallback.isNotEmpty ? fallback.substring(0, 1) : '?',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  final String title;
  final String name;
  final String summary;
  final Color accent;
  final String metricLabel;
  final String? imageUrl;
  final String? badgeLabel;
  final VoidCallback? onTap;

  const _HighlightCard({
    required this.title,
    required this.name,
    required this.summary,
    required this.accent,
    required this.metricLabel,
    this.imageUrl,
    this.badgeLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      pressedScale: onTap == null ? 1 : 0.98,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.24)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent.withValues(alpha: 0.16), AppColors.card],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _InfoPill(label: metricLabel, accent: accent),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        summary,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            onTap == null
                ? const Text(
                    '오늘 경기 기준',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : const _RecordsLinkCue(),
          ],
        ),
      ),
    );
  }
}

class _RecordsLinkCue extends StatelessWidget {
  const _RecordsLinkCue();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '선수 기록 보기',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.accent,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.accent),
      ],
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

class _InfoPill extends StatelessWidget {
  final String label;
  final Color accent;
  final bool subtle;

  const _InfoPill({
    required this.label,
    required this.accent,
    this.subtle = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = subtle ? AppColors.textSecondary : accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
