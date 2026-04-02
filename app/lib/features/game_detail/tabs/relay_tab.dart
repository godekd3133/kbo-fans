import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/game.dart';
import '../../../data/models/player.dart';
import '../../../data/models/relay.dart';
import '../../../data/providers.dart';

class RelayTab extends ConsumerStatefulWidget {
  final String gameId;
  final GameStatus gameStatus;
  final Game game;
  final Future<void> Function()? onRefresh;

  const RelayTab({
    super.key,
    required this.gameId,
    required this.gameStatus,
    required this.game,
    this.onRefresh,
  });

  @override
  ConsumerState<RelayTab> createState() => _RelayTabState();
}

class _RelayTabState extends ConsumerState<RelayTab> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _scrollViewKey = GlobalKey();
  final Map<String, GlobalKey> _inningKeys = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final latestGame =
        ref.watch(gameProvider(widget.gameId)).asData?.value ?? widget.game;
    final relayDataAsync = ref.watch(relayDataProvider(widget.gameId));
    final season = DateTime.now().year;
    final awayPlayers = widget.game.away.teamId.isEmpty
        ? const AsyncValue<List<PlayerProfile>>.data(<PlayerProfile>[])
        : ref.watch(teamPlayersProvider('${widget.game.away.teamId}|$season'));
    final homePlayers = widget.game.home.teamId.isEmpty
        ? const AsyncValue<List<PlayerProfile>>.data(<PlayerProfile>[])
        : ref.watch(teamPlayersProvider('${widget.game.home.teamId}|$season'));
    final imageMap = {
      for (final player in [
        ...awayPlayers.asData?.value ?? const <PlayerProfile>[],
        ...homePlayers.asData?.value ?? const <PlayerProfile>[],
      ])
        if (player.name.isNotEmpty &&
            player.imageUrl != null &&
            player.imageUrl!.isNotEmpty)
          player.name: player.imageUrl!,
    };
    final allImageMap =
        ref.watch(allPlayerImageMapProvider(season)).asData?.value ??
        const <String, String>{};
    final mergedImageMap = {...allImageMap, ...imageMap};

    return RefreshIndicator(
      onRefresh: widget.onRefresh ?? () async {},
      color: AppColors.live,
      child: relayDataAsync.when(
        loading: () => _buildRefreshPlaceholder(
          const CircularProgressIndicator(color: AppColors.live),
        ),
        error: (_, _) => _buildUnavailableState(),
        data: (relayData) {
          if (relayData.relayItems.isEmpty && relayData.currentAtBat == null) {
            return _buildFallbackContent(latestGame);
          }
          return _buildContent(
            latestGame,
            relayData.relayItems,
            relayData.currentAtBat,
            mergedImageMap,
          );
        },
      ),
    );
  }

  Widget _buildRefreshPlaceholder(Widget child) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [SizedBox(height: 520, child: Center(child: child))],
    );
  }

  Widget _buildUnavailableState() {
    final message = switch (widget.gameStatus) {
      GameStatus.live => '실시간 문자중계는 준비 중입니다',
      GameStatus.final_ => '이 경기의 문자중계 데이터가 아직 없습니다',
      GameStatus.cancelled => '취소된 경기는 문자중계를 제공하지 않습니다',
      GameStatus.suspended => '서스펜디드 경기는 재개 전까지 문자중계를 제공하지 않습니다',
      GameStatus.scheduled => '경기 중일 때만 표기됩니다',
    };

    return _buildRefreshPlaceholder(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sports_baseball, size: 48, color: AppColors.divider),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.textDisabled)),
        ],
      ),
    );
  }

  Widget _buildContent(
    Game game,
    List<RelayItem> items,
    CurrentAtBat? atBat,
    Map<String, String> imageMap,
  ) {
    final sortedItems = List<RelayItem>.from(items)
      ..sort((a, b) => b.seqNo.compareTo(a.seqNo));
    final moments = _buildMoments(sortedItems);

    return CustomScrollView(
      key: _scrollViewKey,
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _RelayGameSummary(game: game),
          ),
        ),
        if (atBat != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _CurrentAtBatHero(
                atBat: atBat,
                items: sortedItems,
                imageMap: imageMap,
              ),
            ),
          ),
        if (sortedItems.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _buildInningChips(sortedItems),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: Column(
              children: [
                for (int index = 0; index < moments.length; index++) ...[
                  KeyedSubtree(
                    key: _inningKeys.putIfAbsent(
                      '${moments[index].inningLabel}-$index',
                      () => GlobalKey(),
                    ),
                    child: _RelayMomentCard(
                      moment: moments[index],
                      imageMap: imageMap,
                    ),
                  ),
                  if (index != moments.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackContent(Game game) {
    return CustomScrollView(
      key: _scrollViewKey,
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _RelayGameSummary(game: game),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _RelayFallbackNotice(
              game: game,
              gameStatus: widget.gameStatus,
            ),
          ),
        ),
      ],
    );
  }

  List<_RelayMoment> _buildMoments(List<RelayItem> items) {
    final moments = <_RelayMoment>[];
    var currentInningLabel = '';
    _RelayMomentBuilder? current;

    for (final item in items) {
      if (item.event == 'INNING_CHANGE') {
        currentInningLabel = _chipLabel(item.text);
        current = null;
        continue;
      }

      final inningLabel = item.event == 'GAME_END'
          ? (currentInningLabel.isNotEmpty ? '$currentInningLabel 종료' : '경기 종료')
          : currentInningLabel.isNotEmpty
          ? currentInningLabel
          : '${item.inning}${item.half == 'top' ? '회초' : '회말'}';

      final isPitchDetail = item.text.startsWith('- ');
      if (isPitchDetail) {
        if (current == null) {
          current = _RelayMomentBuilder(inningLabel: inningLabel, lead: item);
          moments.add(current.build());
          current = null;
        } else {
          current.pitchItems.add(item);
          moments[moments.length - 1] = current.build();
        }
        continue;
      }

      current = _RelayMomentBuilder(inningLabel: inningLabel, lead: item);
      moments.add(current.build());
    }

    return moments;
  }

  Widget _buildInningChips(List<RelayItem> items) {
    final chips = <String>[];
    for (final item in items) {
      if (item.inning >= 900) continue;
      final label = item.event == 'INNING_CHANGE'
          ? _chipLabel(item.text)
          : '${item.inning}${item.half == "top" ? "회초" : "회말"}';
      if (!chips.contains(label)) {
        chips.add(label);
      }
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final label = chips[index];
          final isActive = index == chips.length - 1;
          return GestureDetector(
            onTap: () => _scrollToInning(label),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: isActive ? AppColors.textPrimary : AppColors.cardSub,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isActive
                      ? AppColors.background
                      : AppColors.textDisabled,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _scrollToInning(String label) {
    if (!_scrollController.hasClients) {
      return;
    }

    GlobalKey? targetKey;
    for (final entry in _inningKeys.entries) {
      if (entry.key.startsWith(label)) {
        targetKey = entry.value;
        break;
      }
    }
    final targetContext = targetKey?.currentContext;
    final scrollContext = _scrollViewKey.currentContext;
    if (targetContext == null || scrollContext == null) {
      return;
    }

    final targetRenderBox = targetContext.findRenderObject() as RenderBox?;
    final scrollRenderBox = scrollContext.findRenderObject() as RenderBox?;
    if (targetRenderBox == null || scrollRenderBox == null) {
      return;
    }

    final targetOffset = targetRenderBox
        .localToGlobal(Offset.zero, ancestor: scrollRenderBox)
        .dy;
    final desiredOffset = (_scrollController.offset + targetOffset - 12).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      desiredOffset,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  String _chipLabel(String label) {
    if (label.contains('회초') || label.contains('회말')) {
      return label;
    }
    return label.replaceAll(' 공격 ---------------------------------------', '');
  }
}

class _RelayGameSummary extends StatelessWidget {
  final Game game;

  const _RelayGameSummary({required this.game});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${game.away.shortName} ${game.away.score} : ${game.home.score} ${game.home.shortName}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                game.inning,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.live,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _RelayStatRow(
            leftLabel: game.away.shortName,
            leftValue:
                '안타 ${game.away.hits} · 실책 ${game.away.errors} · 사사구 ${game.away.walks}',
            rightLabel: game.home.shortName,
            rightValue:
                '안타 ${game.home.hits} · 실책 ${game.home.errors} · 사사구 ${game.home.walks}',
          ),
          const SizedBox(height: 12),
          _LineScoreStrip(away: game.away, home: game.home),
        ],
      ),
    );
  }
}

class _RelayFallbackNotice extends StatelessWidget {
  final Game game;
  final GameStatus gameStatus;

  const _RelayFallbackNotice({required this.game, required this.gameStatus});

  @override
  Widget build(BuildContext context) {
    final message = switch (gameStatus) {
      GameStatus.live => '공식 문자중계 원문은 아직 없지만 현재 점수와 팀 기록은 계속 반영됩니다',
      GameStatus.final_ => '공식 문자중계 원문이 없어도 최종 스코어와 팀 기록은 확인할 수 있습니다',
      _ => '문자중계 데이터가 아직 준비되지 않았습니다',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '문자중계 요약',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RelayStatRow extends StatelessWidget {
  final String leftLabel;
  final String leftValue;
  final String rightLabel;
  final String rightValue;

  const _RelayStatRow({
    required this.leftLabel,
    required this.leftValue,
    required this.rightLabel,
    required this.rightValue,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RelayStatCell(
            label: leftLabel,
            value: leftValue,
            alignEnd: false,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RelayStatCell(
            label: rightLabel,
            value: rightValue,
            alignEnd: true,
          ),
        ),
      ],
    );
  }
}

class _RelayStatCell extends StatelessWidget {
  final String label;
  final String value;
  final bool alignEnd;

  const _RelayStatCell({
    required this.label,
    required this.value,
    required this.alignEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textDisabled,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LineScoreStrip extends StatelessWidget {
  final TeamScore away;
  final TeamScore home;

  const _LineScoreStrip({required this.away, required this.home});

  @override
  Widget build(BuildContext context) {
    final inningCount = away.innings.length > home.innings.length
        ? away.innings.length
        : home.innings.length;
    if (inningCount == 0) {
      return const SizedBox.shrink();
    }

    String scoreOf(List<int?> innings, int index) {
      if (index >= innings.length) return '-';
      return innings[index]?.toString() ?? '-';
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 40),
              for (var i = 0; i < inningCount; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: SizedBox(
                    width: 18,
                    child: Text(
                      '${i + 1}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textDisabled,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _LineScoreRow(
            label: away.shortName,
            scores: [
              for (var i = 0; i < inningCount; i++) scoreOf(away.innings, i),
            ],
          ),
          const SizedBox(height: 4),
          _LineScoreRow(
            label: home.shortName,
            scores: [
              for (var i = 0; i < inningCount; i++) scoreOf(home.innings, i),
            ],
          ),
        ],
      ),
    );
  }
}

class _LineScoreRow extends StatelessWidget {
  final String label;
  final List<String> scores;

  const _LineScoreRow({required this.label, required this.scores});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        for (final score in scores)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: SizedBox(
              width: 18,
              child: Text(
                score,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CurrentAtBatHero extends StatelessWidget {
  final CurrentAtBat atBat;
  final List<RelayItem> items;
  final Map<String, String> imageMap;

  const _CurrentAtBatHero({
    required this.atBat,
    required this.items,
    required this.imageMap,
  });

  @override
  Widget build(BuildContext context) {
    final latestPlay = _latestPlay(items);
    final latestSubstitution = _latestSubstitution(items);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 380;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    '현재 타석',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  if (atBat.inningText.isNotEmpty)
                    _RelayPill(
                      label: atBat.inningText,
                      color: AppColors.textPrimary,
                      subtle: true,
                    ),
                  if (atBat.baseState.isNotEmpty)
                    _BaseStateBadge(baseState: atBat.baseState),
                  _CompactBsoSummary(
                    balls: atBat.balls,
                    strikes: atBat.strikes,
                    outs: atBat.outs,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (isCompact) ...[
                _ParticipantCard(
                  title: '타자',
                  name: _formatBatterLabel(atBat),
                  detail: _batterDetail(atBat),
                  imageUrl: atBat.batterImageUrl.isNotEmpty
                      ? atBat.batterImageUrl
                      : _resolveImageUrl(imageMap, atBat.batterName),
                ),
                const SizedBox(height: 10),
                _ParticipantCard(
                  title: '상대투수',
                  name: _formatPitcherLabel(atBat),
                  detail: _pitcherDetail(atBat),
                  imageUrl: atBat.pitcherImageUrl.isNotEmpty
                      ? atBat.pitcherImageUrl
                      : _resolveImageUrl(imageMap, atBat.pitcherName),
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: _ParticipantCard(
                        title: '타자',
                        name: _formatBatterLabel(atBat),
                        detail: _batterDetail(atBat),
                        imageUrl: atBat.batterImageUrl.isNotEmpty
                            ? atBat.batterImageUrl
                            : _resolveImageUrl(imageMap, atBat.batterName),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ParticipantCard(
                        title: '상대투수',
                        name: _formatPitcherLabel(atBat),
                        detail: _pitcherDetail(atBat),
                        imageUrl: atBat.pitcherImageUrl.isNotEmpty
                            ? atBat.pitcherImageUrl
                            : _resolveImageUrl(imageMap, atBat.pitcherName),
                      ),
                    ),
                  ],
                ),
              if (_runnerEntries.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  '루상 주자',
                  style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final runner in _runnerEntries)
                      _RunnerPill(baseLabel: runner.$1, name: runner.$2),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _CountSummaryCard(
                      label: '볼',
                      shortLabel: 'B',
                      filled: atBat.balls,
                      total: 4,
                      activeColor: AppColors.ballYellow,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CountSummaryCard(
                      label: '스트라이크',
                      shortLabel: 'S',
                      filled: atBat.strikes,
                      total: 3,
                      activeColor: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CountSummaryCard(
                      label: '아웃',
                      shortLabel: 'O',
                      filled: atBat.outs,
                      total: 3,
                      activeColor: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _CountMeter('B', atBat.balls, 4, AppColors.ballYellow),
                  _CountMeter('S', atBat.strikes, 3, AppColors.accent),
                  _CountMeter('O', atBat.outs, 3, AppColors.textPrimary),
                ],
              ),
              if (latestSubstitution != null || latestPlay != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.cardSub,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (latestSubstitution != null)
                        _HeroSummaryLine(
                          label: latestSubstitution.text.contains('대타')
                              ? '최근 대타'
                              : latestSubstitution.text.contains('대주자')
                              ? '최근 대주자'
                              : '최근 교체',
                          value: latestSubstitution.text,
                          accent: AppColors.accent,
                        ),
                      if (latestSubstitution != null && latestPlay != null)
                        const SizedBox(height: 8),
                      if (latestPlay != null)
                        _HeroSummaryLine(
                          label: '직전 플레이',
                          value: latestPlay.text,
                          accent: latestPlay.isScoring
                              ? AppColors.live
                              : AppColors.textSecondary,
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _formatBatterLabel(CurrentAtBat ab) {
    final number = ab.batterNumber > 0 ? '${ab.batterNumber}번 ' : '';
    final hand = ab.batterHand.isNotEmpty ? ' · ${ab.batterHand}' : '';
    return '$number${ab.batterName}$hand';
  }

  String _formatPitcherLabel(CurrentAtBat ab) {
    final hand = ab.pitcherHand.isNotEmpty ? ' · ${ab.pitcherHand}' : '';
    return '${ab.pitcherName}$hand';
  }

  String _batterDetail(CurrentAtBat ab) {
    if (ab.batterRecent.isNotEmpty) {
      return '최근 타석: ${ab.batterRecent}';
    }
    if (ab.baseState.isNotEmpty) {
      return ab.baseState;
    }
    return '현재 타석 진행 중';
  }

  String _pitcherDetail(CurrentAtBat ab) {
    final pitchCount = ab.pitchCount > 0
        ? '${ab.pitchCount}구'
        : ab.pitcherHand.isNotEmpty
        ? '${ab.pitcherHand} · 현재 투수'
        : '현재 투수';
    if (ab.pitcherNumber > 0) {
      return '${ab.pitcherNumber}번 · $pitchCount';
    }
    return pitchCount;
  }

  RelayItem? _latestPlay(List<RelayItem> items) {
    for (final item in items) {
      if (item.event != 'INNING_CHANGE' && !item.text.startsWith('- ')) {
        return item;
      }
    }
    return null;
  }

  RelayItem? _latestSubstitution(List<RelayItem> items) {
    for (final item in items) {
      if (item.event == 'SUBSTITUTION') {
        return item;
      }
    }
    return null;
  }

  List<(String, String)> get _runnerEntries {
    final entries = <(String, String)>[];
    if (atBat.firstRunnerName.isNotEmpty) {
      entries.add(('1루', atBat.firstRunnerName));
    }
    if (atBat.secondRunnerName.isNotEmpty) {
      entries.add(('2루', atBat.secondRunnerName));
    }
    if (atBat.thirdRunnerName.isNotEmpty) {
      entries.add(('3루', atBat.thirdRunnerName));
    }
    return entries;
  }

  String? _resolveImageUrl(Map<String, String> imageMap, String rawName) {
    if (rawName.isEmpty) {
      return null;
    }

    final normalizedTarget = _normalizeName(rawName);
    if (imageMap.containsKey(rawName)) {
      return imageMap[rawName];
    }

    for (final entry in imageMap.entries) {
      final normalizedKey = _normalizeName(entry.key);
      if (normalizedKey == normalizedTarget) {
        return entry.value;
      }
    }

    for (final entry in imageMap.entries) {
      final normalizedKey = _normalizeName(entry.key);
      if (normalizedKey.contains(normalizedTarget) ||
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
        .trim();
  }
}

class _ParticipantCard extends StatelessWidget {
  final String title;
  final String name;
  final String detail;
  final String? imageUrl;

  const _ParticipantCard({
    required this.title,
    required this.name,
    required this.detail,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _RelayPlayerAvatar(imageUrl: imageUrl, fallbackLabel: name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDisabled,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RelayPlayerAvatar extends StatelessWidget {
  static const _imageHeaders = {
    'Referer': 'https://www.koreabaseball.com/',
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
  };

  final String? imageUrl;
  final String fallbackLabel;
  final double size;
  final double radius;

  const _RelayPlayerAvatar({
    required this.imageUrl,
    required this.fallbackLabel,
    this.size = 54,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          httpHeaders: _imageHeaders,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => _fallback(),
          placeholder: (_, _) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    final initial = fallbackLabel.isNotEmpty
        ? fallbackLabel.substring(0, 1)
        : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _RunnerPill extends StatelessWidget {
  final String baseLabel;
  final String name;

  const _RunnerPill({required this.baseLabel, required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.divider),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          children: [
            TextSpan(
              text: '$baseLabel ',
              style: const TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: name,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroSummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _HeroSummaryLine({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
              children: [
                TextSpan(
                  text: '$label ',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CountMeter extends StatelessWidget {
  final String label;
  final int filled;
  final int total;
  final Color activeColor;

  const _CountMeter(this.label, this.filled, this.total, this.activeColor);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
        ),
        const SizedBox(width: 6),
        for (int i = 0; i < total; i++)
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? activeColor : Colors.transparent,
              border: Border.all(
                color: i < filled ? activeColor : AppColors.divider,
                width: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}

class _CompactBsoSummary extends StatelessWidget {
  final int balls;
  final int strikes;
  final int outs;
  final bool showOuts;

  const _CompactBsoSummary({
    required this.balls,
    required this.strikes,
    required this.outs,
    this.showOuts = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.divider),
      ),
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _MiniCountBadge(
            label: 'B',
            value: balls,
            color: AppColors.ballYellow,
          ),
          _MiniCountBadge(label: 'S', value: strikes, color: AppColors.accent),
          if (showOuts)
            _MiniCountBadge(
              label: 'O',
              value: outs,
              color: AppColors.textPrimary,
            ),
        ],
      ),
    );
  }
}

class _MiniCountBadge extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _MiniCountBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
        children: [
          TextSpan(
            text: label,
            style: TextStyle(color: color),
          ),
          const TextSpan(text: ' '),
          TextSpan(
            text: '$value',
            style: const TextStyle(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _CountSummaryCard extends StatelessWidget {
  final String label;
  final String shortLabel;
  final int filled;
  final int total;
  final Color activeColor;

  const _CountSummaryCard({
    required this.label,
    required this.shortLabel,
    required this.filled,
    required this.total,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: activeColor.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: activeColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '$filled',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                shortLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: activeColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (int i = 0; i < total; i++)
                Expanded(
                  child: Container(
                    height: 8,
                    margin: EdgeInsets.only(right: i == total - 1 ? 0 : 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: i < filled ? activeColor : AppColors.background,
                      border: Border.all(
                        color: i < filled ? activeColor : AppColors.divider,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RelayMomentCard extends StatelessWidget {
  final _RelayMoment moment;
  final Map<String, String> imageMap;

  const _RelayMomentCard({required this.moment, required this.imageMap});

  @override
  Widget build(BuildContext context) {
    final accent = moment.isScoring
        ? AppColors.live
        : moment.isSubstitution
        ? AppColors.accent
        : AppColors.textSecondary;
    final eventLabel = _eventLabel(moment.lead.event);
    final actorLabel = _actorLabel(moment.lead.text);
    final actorImageUrl = actorLabel == null
        ? null
        : _resolveImageUrl(imageMap, actorLabel);
    final pitchLogs = _buildPitchLogs(moment.pitchItems);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: moment.isScoring ? const Color(0xFF1C1111) : AppColors.cardSub,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: moment.isScoring
              ? AppColors.live.withValues(alpha: 0.45)
              : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RelayPill(
                label: moment.inningLabel,
                color: AppColors.textPrimary,
                subtle: true,
              ),
              const SizedBox(width: 8),
              if (moment.isScoring)
                const _RelayPill(label: '득점 장면', color: AppColors.live),
              if (moment.isSubstitution)
                const _RelayPill(label: '교체', color: AppColors.accent),
              if (moment.isGameEnd)
                const _RelayPill(label: '경기 종료', color: AppColors.textPrimary),
              if (!moment.isScoring &&
                  !moment.isSubstitution &&
                  !moment.isGameEnd &&
                  eventLabel != null) ...[
                const SizedBox(width: 8),
                _RelayPill(label: eventLabel, color: accent),
              ],
            ],
          ),
          if (actorLabel != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _RelayPlayerAvatar(
                  imageUrl: actorImageUrl,
                  fallbackLabel: actorLabel,
                  size: 40,
                  radius: 12,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    actorLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (pitchLogs.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (int index = 0; index < pitchLogs.length; index++) ...[
              _PitchLogRow(log: pitchLogs[index]),
              if (index != pitchLogs.length - 1) const SizedBox(height: 6),
            ],
          ],
          const SizedBox(height: 10),
          Text(
            moment.lead.text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: moment.isScoring || moment.isGameEnd
                  ? FontWeight.w800
                  : FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.35,
            ),
          ),
          if (moment.lead.pitchSequence != null &&
              moment.lead.pitchSequence!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              moment.lead.pitchSequence!,
              style: TextStyle(
                fontSize: 11,
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _eventLabel(String event) {
    switch (event) {
      case 'HIT':
        return '안타';
      case 'HOMERUN':
        return '홈런';
      case 'WALK':
        return '볼넷';
      case 'STRIKEOUT':
        return '삼진';
      case 'OUT':
        return '아웃';
      case 'RUNS':
        return '득점';
      case 'PLAY':
        return '플레이';
      default:
        return null;
    }
  }

  String? _actorLabel(String text) {
    final colonIndex = text.indexOf(':');
    if (colonIndex > 0) {
      return text.substring(0, colonIndex).trim();
    }
    final byMatch = RegExp(r'^(.*?)\s+(교체|볼넷|삼진|안타|홈런|아웃)').firstMatch(text);
    final actor = byMatch?.group(1)?.trim() ?? '';
    return actor.isEmpty ? null : actor;
  }

  List<_PitchLogViewData> _buildPitchLogs(List<RelayItem> pitchItems) {
    if (pitchItems.isEmpty) {
      return const [];
    }

    final ordered = List<RelayItem>.from(pitchItems)
      ..sort((a, b) {
        final left = _pitchNumber(a.text);
        final right = _pitchNumber(b.text);
        if (left != null && right != null && left != right) {
          return left.compareTo(right);
        }
        return a.seqNo.compareTo(b.seqNo);
      });

    var balls = 0;
    var strikes = 0;
    final rows = <_PitchLogViewData>[];

    for (final item in ordered) {
      final action = _pitchAction(item.text);
      if (action == _PitchAction.ball) {
        balls = balls < 4 ? balls + 1 : balls;
      } else if (action == _PitchAction.strike) {
        strikes = strikes < 3 ? strikes + 1 : strikes;
      } else if (action == _PitchAction.foul && strikes < 2) {
        strikes += 1;
      }

      rows.add(
        _PitchLogViewData(
          text: item.text,
          pitchNumber: _pitchNumber(item.text),
          actionLabel: _pitchActionLabel(action),
          actionColor: _pitchActionColor(action),
          balls: balls,
          strikes: strikes,
        ),
      );
    }

    return rows;
  }

  int? _pitchNumber(String text) {
    final match = RegExp(r'(\d+)구').firstMatch(text);
    return int.tryParse(match?.group(1) ?? '');
  }

  _PitchAction _pitchAction(String text) {
    if (text.contains('파울')) {
      return _PitchAction.foul;
    }
    if (text.contains('스트라이크') || text.contains('헛스윙')) {
      return _PitchAction.strike;
    }
    if (text.contains('볼')) {
      return _PitchAction.ball;
    }
    if (text.contains('타격') || text.contains('번트')) {
      return _PitchAction.inPlay;
    }
    return _PitchAction.other;
  }

  String? _pitchActionLabel(_PitchAction action) {
    switch (action) {
      case _PitchAction.ball:
        return '볼';
      case _PitchAction.strike:
        return '스트라이크';
      case _PitchAction.foul:
        return '파울';
      case _PitchAction.inPlay:
        return '타격';
      case _PitchAction.other:
        return null;
    }
  }

  Color _pitchActionColor(_PitchAction action) {
    switch (action) {
      case _PitchAction.ball:
        return AppColors.ballYellow;
      case _PitchAction.strike:
        return AppColors.accent;
      case _PitchAction.foul:
        return AppColors.textPrimary;
      case _PitchAction.inPlay:
        return AppColors.positive;
      case _PitchAction.other:
        return AppColors.textSecondary;
    }
  }

  String? _resolveImageUrl(Map<String, String> imageMap, String rawName) {
    final normalizedTarget = _normalizeName(rawName);
    if (normalizedTarget.isEmpty) {
      return null;
    }

    for (final entry in imageMap.entries) {
      if (_normalizeName(entry.key) == normalizedTarget) {
        return entry.value;
      }
    }

    for (final entry in imageMap.entries) {
      final normalizedKey = _normalizeName(entry.key);
      if (normalizedKey.contains(normalizedTarget) ||
          normalizedTarget.contains(normalizedKey)) {
        return entry.value;
      }
    }

    return null;
  }

  String _normalizeName(String value) {
    return value
        .replaceFirst(RegExp(r'^\d+번\s*'), '')
        .replaceFirst(RegExp(r'^(대타|대주자|투수|타자)\s+'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[·ㆍ.]'), '')
        .trim();
  }
}

class _PitchLogRow extends StatelessWidget {
  final _PitchLogViewData log;

  const _PitchLogRow({required this.log});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (log.pitchNumber != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.cardSub,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.divider),
              ),
              child: Text(
                '${log.pitchNumber}구',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.text.replaceFirst('- ', ''),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (log.actionLabel != null ||
                    log.balls != null ||
                    log.strikes != null) ...[
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (log.actionLabel != null)
                        _RelayPill(
                          label: log.actionLabel!,
                          color: log.actionColor,
                        ),
                      if (log.balls != null && log.strikes != null)
                        _CompactBsoSummary(
                          balls: log.balls!,
                          strikes: log.strikes!,
                          outs: 0,
                          showOuts: false,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PitchLogViewData {
  final String text;
  final int? pitchNumber;
  final String? actionLabel;
  final Color actionColor;
  final int? balls;
  final int? strikes;

  const _PitchLogViewData({
    required this.text,
    this.pitchNumber,
    required this.actionLabel,
    required this.actionColor,
    this.balls,
    this.strikes,
  });
}

enum _PitchAction { ball, strike, foul, inPlay, other }

class _RelayPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool subtle;

  const _RelayPill({
    required this.label,
    required this.color,
    this.subtle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: subtle ? AppColors.background : color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: subtle ? AppColors.divider : color.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: subtle ? AppColors.textSecondary : color,
        ),
      ),
    );
  }
}

class _BaseStateBadge extends StatelessWidget {
  final String baseState;

  const _BaseStateBadge({required this.baseState});

  @override
  Widget build(BuildContext context) {
    final occupiedBases = switch (baseState) {
      '주자1루' => {1},
      '주자2루' => {2},
      '주자3루' => {3},
      '주자1,2루' => {1, 2},
      '주자1,3루' => {1, 3},
      '주자2,3루' => {2, 3},
      '만루' => {1, 2, 3},
      _ => <int>{},
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: 0.785398,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.textDisabled,
                        width: 1,
                      ),
                    ),
                  ),
                ),
                _baseDot(occupiedBases.contains(2), const Offset(0, -5)),
                _baseDot(occupiedBases.contains(1), const Offset(5, 0)),
                _baseDot(occupiedBases.contains(3), const Offset(-5, 0)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            baseState,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _baseDot(bool visible, Offset offset) {
    return Transform.translate(
      offset: offset,
      child: Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: visible ? AppColors.accent : Colors.transparent,
          border: Border.all(
            color: visible ? AppColors.accent : AppColors.textDisabled,
            width: 0.8,
          ),
        ),
      ),
    );
  }
}

class _RelayMoment {
  final String inningLabel;
  final RelayItem lead;
  final List<RelayItem> pitchItems;
  final bool isScoring;
  final bool isGameEnd;
  final bool isSubstitution;

  const _RelayMoment({
    required this.inningLabel,
    required this.lead,
    required this.pitchItems,
    required this.isScoring,
    required this.isGameEnd,
    required this.isSubstitution,
  });
}

class _RelayMomentBuilder {
  final String inningLabel;
  final RelayItem lead;
  final List<RelayItem> pitchItems = [];

  _RelayMomentBuilder({required this.inningLabel, required this.lead});

  _RelayMoment build() {
    return _RelayMoment(
      inningLabel: inningLabel,
      lead: lead,
      pitchItems: List<RelayItem>.from(pitchItems),
      isScoring: lead.isScoring,
      isGameEnd: lead.event == 'GAME_END',
      isSubstitution: lead.event == 'SUBSTITUTION',
    );
  }
}
