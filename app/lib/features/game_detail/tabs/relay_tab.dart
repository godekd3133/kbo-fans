import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  String? _selectedInningLabel;
  _RelayMomentFilter _selectedMomentFilter = _RelayMomentFilter.all;
  int? _latestSeenSeq;
  bool _hasNewRelay = false;
  String? _lastPrefetchedImageSignature;

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
    final season = _seasonFromGameId(widget.gameId);
    final awayPlayers = widget.game.away.teamId.isEmpty
        ? AsyncValue<List<PlayerProfile>>.data(<PlayerProfile>[])
        : ref.watch(teamPlayersProvider('${widget.game.away.teamId}|$season'));
    final homePlayers = widget.game.home.teamId.isEmpty
        ? AsyncValue<List<PlayerProfile>>.data(<PlayerProfile>[])
        : ref.watch(teamPlayersProvider('${widget.game.home.teamId}|$season'));
    final teamPlayers = [
      ...awayPlayers.asData?.value ?? <PlayerProfile>[],
      ...homePlayers.asData?.value ?? <PlayerProfile>[],
    ];
    final playersByName = {
      for (final player in teamPlayers)
        if (player.name.isNotEmpty) player.name: player,
    };
    final lineupData = ref
        .watch(gameLineupProvider(widget.gameId))
        .asData
        ?.value;
    return RefreshIndicator(
      onRefresh: widget.onRefresh ?? () async {},
      color: AppColors.live,
      child: relayDataAsync.when(
        skipError: true,
        loading: () => _buildRefreshPlaceholder(
          CircularProgressIndicator(color: AppColors.live),
        ),
        error: (_, _) => _buildUnavailableState(),
        data: (relayData) {
          final currentAtBat = _currentAtBatForGame(
            latestGame,
            relayData.currentAtBat,
          );
          if (relayData.relayItems.isEmpty && currentAtBat == null) {
            return _buildFallbackContent(latestGame);
          }
          _trackRelayUpdates(relayData.relayItems);
          final imageMap = _buildRelayPlayerImageMap(
            teamPlayers: teamPlayers,
            season: season,
            currentAtBat: currentAtBat,
          );
          _prefetchRelayPlayerImages(imageMap.values);
          return _buildContent(
            latestGame,
            relayData.relayItems,
            currentAtBat,
            imageMap,
            playersByName,
            lineupData,
            season: season,
          );
        },
      ),
    );
  }

  void _prefetchRelayPlayerImages(Iterable<String?> imageUrls) {
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

  CurrentAtBat? _currentAtBatForGame(Game game, CurrentAtBat? atBat) {
    return game.status == GameStatus.live ? atBat : null;
  }

  Widget _buildRefreshPlaceholder(Widget child) {
    return ListView(
      physics: AlwaysScrollableScrollPhysics(),
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
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          height: 178,
          width: double.infinity,
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '문자중계',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 6),
              Text(
                message,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    Game game,
    List<RelayItem> items,
    CurrentAtBat? atBat,
    Map<String, String> imageMap,
    Map<String, PlayerProfile> playersByName,
    GameLineupData? lineupData, {
    required int season,
  }) {
    final sortedItems = List<RelayItem>.from(items)
      ..sort((a, b) => b.seqNo.compareTo(a.seqNo));
    final moments = _buildMoments(sortedItems);
    final inningFilteredMoments = _selectedInningLabel == null
        ? moments
        : moments
              .where(
                (moment) =>
                    moment.inningLabel == _selectedInningLabel ||
                    moment.inningLabel.startsWith('$_selectedInningLabel '),
              )
              .toList();
    final filteredMoments = inningFilteredMoments
        .where((moment) => _selectedMomentFilter.matches(moment))
        .toList();

    return CustomScrollView(
      key: _scrollViewKey,
      controller: _scrollController,
      physics: AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _RelayGameSummary(game: game),
          ),
        ),
        if (atBat != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _CurrentAtBatHero(
                game: game,
                atBat: atBat,
                items: sortedItems,
                imageMap: imageMap,
                lineupData: lineupData,
              ),
            ),
          ),
        if (sortedItems.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 14),
              child: _buildInningChips(sortedItems),
            ),
          ),
        if (moments.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 10),
              child: _buildMomentFilterChips(moments),
            ),
          ),
        if (_hasNewRelay)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _NewRelayBanner(onTap: _jumpToLatestRelay),
            ),
          ),
        if (_selectedInningLabel != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: _SelectedInningHeader(
                label: _selectedInningLabel!,
                game: game,
                currentAtBat: atBat,
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: Column(
              children: [
                for (
                  int index = 0;
                  index < filteredMoments.length;
                  index++
                ) ...[
                  KeyedSubtree(
                    key: _inningKeys.putIfAbsent(
                      '${filteredMoments[index].inningLabel}-$index',
                      () => GlobalKey(),
                    ),
                    child: _RelayMomentCard(
                      moment: filteredMoments[index],
                      game: game,
                      imageMap: imageMap,
                      playersByName: playersByName,
                      currentAtBat: atBat,
                      lineupData: lineupData,
                      season: season,
                    ),
                  ),
                  if (index != filteredMoments.length - 1) SizedBox(height: 12),
                ],
                if (filteredMoments.isEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text(
                      _selectedMomentFilter == _RelayMomentFilter.all
                          ? '선택한 회차의 문자중계가 아직 없습니다'
                          : '선택한 조건의 주요 장면이 없습니다',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _trackRelayUpdates(List<RelayItem> items) {
    if (items.isEmpty) {
      return;
    }

    final latestSeq = items.fold<int>(
      0,
      (latest, item) => item.seqNo > latest ? item.seqNo : latest,
    );
    final previousSeq = _latestSeenSeq;
    if (previousSeq == null) {
      _latestSeenSeq = latestSeq;
      return;
    }
    if (latestSeq <= previousSeq) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final isAwayFromTop =
          _scrollController.hasClients && _scrollController.offset > 140;
      setState(() {
        _latestSeenSeq = latestSeq;
        _hasNewRelay = isAwayFromTop;
      });
    });
  }

  Widget _buildFallbackContent(Game game) {
    return CustomScrollView(
      key: _scrollViewKey,
      controller: _scrollController,
      physics: AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _RelayGameSummary(game: game),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
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
    final chips = <String>['전체'];
    for (final item in items) {
      if (item.inning >= 900) continue;
      final label = item.event == 'INNING_CHANGE'
          ? _chipLabel(item.text)
          : '${item.inning}${item.half == "top" ? "회초" : "회말"}';
      if (!chips.contains(label)) {
        chips.add(label);
      }
    }

    if (chips.isEmpty) return SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, _) => SizedBox(width: 8),
        itemBuilder: (context, index) {
          final label = chips[index];
          final isActive = label == '전체'
              ? _selectedInningLabel == null
              : _selectedInningLabel == label;
          return AppPressable(
            onTap: () => _selectInning(label),
            pressedScale: 0.94,
            child: AnimatedContainer(
              duration: Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: isActive ? AppColors.textPrimary : AppColors.cardSub,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isActive ? AppColors.textPrimary : AppColors.divider,
                ),
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

  Widget _buildMomentFilterChips(List<_RelayMoment> moments) {
    final filters = _RelayMomentFilter.values;
    final colors = AppTheme.colorsOf(context);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (_, _) => SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isActive = filter == _selectedMomentFilter;
          final count = filter == _RelayMomentFilter.all
              ? moments.length
              : moments.where(filter.matches).length;
          return AppPressable(
            onTap: () => _selectMomentFilter(filter),
            pressedScale: 0.94,
            child: AnimatedContainer(
              duration: Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: isActive ? AppColors.live : AppColors.cardSub,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isActive ? AppColors.live : AppColors.divider,
                ),
              ),
              child: Text(
                '${filter.label} $count',
                style: TextStyle(
                  fontSize: 12,
                  color: isActive
                      ? colors.readableForegroundOn(AppColors.live)
                      : AppColors.textDisabled,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _selectInning(String label) {
    setState(() {
      _selectedInningLabel = label == '전체' ? null : label;
    });

    if (!_scrollController.hasClients) {
      return;
    }

    _scrollController.animateTo(
      0,
      duration: Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _selectMomentFilter(_RelayMomentFilter filter) {
    setState(() {
      _selectedMomentFilter = filter;
    });

    if (!_scrollController.hasClients) {
      return;
    }

    _scrollController.animateTo(
      0,
      duration: Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _jumpToLatestRelay() {
    setState(() {
      _hasNewRelay = false;
      _selectedInningLabel = null;
      _selectedMomentFilter = _RelayMomentFilter.all;
    });

    if (!_scrollController.hasClients) {
      return;
    }

    _scrollController.animateTo(
      0,
      duration: Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  String _chipLabel(String label) {
    final inningMatch = RegExp(r'\d+회[초말]').firstMatch(label);
    if (inningMatch != null) {
      return inningMatch.group(0)!;
    }
    return label.replaceAll(' 공격 ---------------------------------------', '');
  }
}

String _formatLineupEntryLabel(LineupEntry entry) {
  final position = entry.position.trim().isNotEmpty
      ? entry.position.trim()
      : entry.positionKo.trim();
  return [
    if (entry.order > 0) '${entry.order}',
    entry.name.trim(),
    if (position.isNotEmpty) position,
  ].where((part) => part.isNotEmpty).join(' ');
}

LineupEntry? _lineupEntryForCurrentAtBat(
  Game game,
  CurrentAtBat atBat,
  GameLineupData? lineupData,
) {
  if (lineupData == null || atBat.batterName.isEmpty) {
    return null;
  }

  final isTop = _isTopHalfText(atBat.inningText);
  if (isTop == true) {
    return _lineupEntryForName(lineupData.away.lineup, atBat.batterName);
  }
  if (isTop == false) {
    return _lineupEntryForName(lineupData.home.lineup, atBat.batterName);
  }

  final gameHalf = _isTopHalfText(game.inning);
  if (gameHalf == true) {
    return _lineupEntryForName(lineupData.away.lineup, atBat.batterName);
  }
  if (gameHalf == false) {
    return _lineupEntryForName(lineupData.home.lineup, atBat.batterName);
  }

  return _lineupEntryForName(lineupData.away.lineup, atBat.batterName) ??
      _lineupEntryForName(lineupData.home.lineup, atBat.batterName);
}

LineupEntry? _lineupEntryForName(List<LineupEntry> entries, String rawName) {
  final target = _normalizeRelayPlayerName(rawName);
  if (target.isEmpty) {
    return null;
  }

  for (final entry in entries) {
    if (_normalizeRelayPlayerName(entry.name) == target) {
      return entry;
    }
  }

  for (final entry in entries) {
    final normalizedName = _normalizeRelayPlayerName(entry.name);
    if (normalizedName.isEmpty) {
      continue;
    }
    if (normalizedName.contains(target) || target.contains(normalizedName)) {
      return entry;
    }
  }

  return null;
}

bool? _isTopHalfText(String value) {
  final normalized = value.replaceAll(RegExp(r'\s+'), '');
  if (normalized.contains('회초')) {
    return true;
  }
  if (normalized.contains('회말')) {
    return false;
  }
  return null;
}

String _normalizeRelayPlayerName(String value) {
  return value
      .replaceFirst(RegExp(r'^\d+\s*번?\s*타자\s*'), '')
      .replaceFirst(RegExp(r'^\d+번\s*'), '')
      .replaceFirst(RegExp(r'^(대타|대주자|투수|타자)\s+'), '')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[·ㆍ.]'), '')
      .trim();
}

String? _relayLeadActorLabel(String text) {
  final colonIndex = text.indexOf(':');
  if (colonIndex > 0) {
    return text.substring(0, colonIndex).trim();
  }
  final byMatch = RegExp(r'^(.*?)\s+(교체|볼넷|삼진|안타|홈런|아웃)').firstMatch(text);
  final actor = byMatch?.group(1)?.trim() ?? '';
  return actor.isEmpty ? null : actor;
}

_ScoringPlayViewData? _scoringPlayViewData(RelayItem item) {
  if (!item.isScoring && item.event != 'RUNS' && item.event != 'HOMERUN') {
    return null;
  }

  final batterName = _scoringBatterName(item.text);
  final scoredRunnerNames = _scoredRunnerNames(item.text);
  if (item.text.contains('홈런') && batterName != null) {
    _addUniquePlayerName(scoredRunnerNames, batterName);
  }

  if (batterName == null && scoredRunnerNames.isEmpty) {
    return null;
  }
  return _ScoringPlayViewData(
    batterName: batterName,
    scoredRunnerNames: scoredRunnerNames,
  );
}

String? _scoringBatterName(String text) {
  final actor = _relayLeadActorLabel(text);
  if (actor == null || actor.contains('주자')) {
    return null;
  }
  return _cleanScoringPlayerName(actor);
}

List<String> _scoredRunnerNames(String text) {
  final names = <String>[];
  final segments = text.split(RegExp(r'[,，.·ㆍ]'));
  for (final segment in segments) {
    if (segment.contains('무득점')) {
      continue;
    }
    final keyword = RegExp(r'(홈인|득점)').firstMatch(segment);
    if (keyword == null) {
      continue;
    }

    var candidate = segment.substring(0, keyword.start).trim();
    final colonIndex = candidate.indexOf(':');
    if (colonIndex >= 0) {
      final left = candidate.substring(0, colonIndex).trim();
      final right = candidate.substring(colonIndex + 1).trim();
      candidate = left.contains('주자') ? left : right;
    }

    _addUniquePlayerName(names, _cleanScoringPlayerName(candidate));
  }
  return names;
}

void _addUniquePlayerName(List<String> names, String? name) {
  if (name == null || name.isEmpty) {
    return;
  }
  final normalized = _normalizeRelayPlayerName(name);
  if (normalized.isEmpty) {
    return;
  }
  final exists = names.any(
    (existing) => _normalizeRelayPlayerName(existing) == normalized,
  );
  if (!exists) {
    names.add(name);
  }
}

String? _cleanScoringPlayerName(String value) {
  var cleaned = value
      .replaceAll(RegExp(r'[:：]'), ' ')
      .replaceAll(RegExp(r'[-–—]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  cleaned = cleaned
      .replaceFirst(RegExp(r'^(?:[123]루)?주자\s*'), '')
      .replaceFirst(RegExp(r'^(대타|대주자|타자)\s+'), '')
      .trim();

  if (cleaned.contains(RegExp(r'\d|회|공격|무득점|홈인|득점'))) {
    return null;
  }
  if (!RegExp(r'[가-힣A-Za-z]').hasMatch(cleaned)) {
    return null;
  }

  final parts = cleaned.split(' ').where((part) => part.isNotEmpty).toList();
  if (parts.length > 1) {
    cleaned = parts.last;
  }
  if (cleaned.length < 2 || cleaned.length > 12) {
    return null;
  }
  return cleaned;
}

Map<String, String> _buildRelayPlayerImageMap({
  required Iterable<PlayerProfile> teamPlayers,
  required int season,
  required CurrentAtBat? currentAtBat,
}) {
  final imageMap = <String, String>{};
  for (final player in teamPlayers) {
    final imageUrl = _playerImageUrlFromProfile(player, season);
    if (player.name.isNotEmpty && imageUrl != null && imageUrl.isNotEmpty) {
      imageMap[player.name] = imageUrl;
    }
  }

  if (currentAtBat != null) {
    if (currentAtBat.batterName.isNotEmpty &&
        currentAtBat.batterImageUrl.isNotEmpty) {
      imageMap[currentAtBat.batterName] = currentAtBat.batterImageUrl;
    }
    if (currentAtBat.pitcherName.isNotEmpty &&
        currentAtBat.pitcherImageUrl.isNotEmpty) {
      imageMap[currentAtBat.pitcherName] = currentAtBat.pitcherImageUrl;
    }
  }
  return imageMap;
}

String? _playerImageUrlFromProfile(PlayerProfile player, int season) {
  if (player.imageUrl != null && player.imageUrl!.isNotEmpty) {
    return player.imageUrl;
  }
  final playerId = player.id.trim();
  if (playerId.isEmpty) {
    return null;
  }
  return kboPlayerImageUrl(season: season, playerId: playerId);
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

class _RelayGameSummary extends StatelessWidget {
  final Game game;

  const _RelayGameSummary({required this.game});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
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
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                game.inning,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.live,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          _RelayStatRow(
            leftLabel: game.away.shortName,
            leftValue: _teamStatSummary(game.away),
            rightLabel: game.home.shortName,
            rightValue: _teamStatSummary(game.home),
          ),
          SizedBox(height: 12),
          _LineScoreStrip(away: game.away, home: game.home),
        ],
      ),
    );
  }
}

String _teamStatSummary(TeamScore team) {
  if (!team.hasStats) {
    return '안타 - · 실책 - · 사사구 -';
  }
  return '안타 ${team.hits} · 실책 ${team.errors} · 사사구 ${team.walks}';
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
      height: 156,
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '문자중계 요약',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
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
        SizedBox(width: 12),
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
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textDisabled,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 4),
        Text(
          value,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: TextStyle(
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
  static final _totalLabels = ['R', 'H', 'E'];

  final TeamScore away;
  final TeamScore home;

  const _LineScoreStrip({required this.away, required this.home});

  @override
  Widget build(BuildContext context) {
    final inningCount = away.innings.length > home.innings.length
        ? away.innings.length
        : home.innings.length;
    if (inningCount == 0) {
      return SizedBox.shrink();
    }

    String scoreOf(List<int?> innings, int index) {
      if (index >= innings.length) return '-';
      return innings[index]?.toString() ?? '-';
    }

    List<String> totalsOf(TeamScore team) {
      return [
        team.score.toString(),
        team.hasStats ? team.hits.toString() : '-',
        team.hasStats ? team.errors.toString() : '-',
      ];
    }

    final headerLabels = [
      for (var i = 0; i < inningCount; i++) '${i + 1}',
      ..._totalLabels,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 40),
              for (var i = 0; i < headerLabels.length; i++) ...[
                if (i == inningCount) SizedBox(width: 4),
                Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: SizedBox(
                    width: i >= inningCount ? 22 : 18,
                    child: Text(
                      headerLabels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textDisabled,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 6),
          _LineScoreRow(
            label: away.shortName,
            totalStartIndex: inningCount,
            scores: [
              for (var i = 0; i < inningCount; i++) scoreOf(away.innings, i),
              ...totalsOf(away),
            ],
          ),
          SizedBox(height: 4),
          _LineScoreRow(
            label: home.shortName,
            totalStartIndex: inningCount,
            scores: [
              for (var i = 0; i < inningCount; i++) scoreOf(home.innings, i),
              ...totalsOf(home),
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
  final int totalStartIndex;

  const _LineScoreRow({
    required this.label,
    required this.scores,
    required this.totalStartIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        for (var i = 0; i < scores.length; i++) ...[
          if (i == totalStartIndex) SizedBox(width: 4),
          Padding(
            padding: EdgeInsets.only(right: 10),
            child: SizedBox(
              width: i >= totalStartIndex ? 22 : 18,
              child: Text(
                scores[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _NewRelayBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _NewRelayBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      pressedScale: 0.98,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.34)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '새 중계가 들어왔습니다',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '최신 보기',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedInningHeader extends StatelessWidget {
  final String label;
  final Game game;
  final CurrentAtBat? currentAtBat;

  const _SelectedInningHeader({
    required this.label,
    required this.game,
    required this.currentAtBat,
  });

  @override
  Widget build(BuildContext context) {
    final isTop = label.endsWith('회초');
    final offenseTeam = isTop ? game.away.shortName : game.home.shortName;
    final matchesCurrentInning =
        currentAtBat != null && currentAtBat!.inningText.startsWith(label);

    return Row(
      children: [
        Expanded(
          child: Text(
            '$label - $offenseTeam 공격',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        if (matchesCurrentInning) _OutStateIndicator(outs: currentAtBat!.outs),
      ],
    );
  }
}

class _RelayBroadcastScorebug extends StatelessWidget {
  final Game game;
  final CurrentAtBat atBat;
  final String baseState;
  final RelayItem? latestPlay;

  const _RelayBroadcastScorebug({
    required this.game,
    required this.atBat,
    required this.baseState,
    required this.latestPlay,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final awayColor = colors.readableAccent(
      KboTeams.byId(game.away.teamId)?.primaryColor ?? colors.accent,
    );
    final homeColor = colors.readableAccent(
      KboTeams.byId(game.home.teamId)?.primaryColor ?? colors.live,
    );
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
        gradient: LinearGradient(
          colors: [
            awayColor.withValues(alpha: 0.58),
            AppColors.cardSub,
            homeColor.withValues(alpha: 0.58),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ScorebugSide(
                  team: game.away.shortName,
                  primary: atBat.batterName.isEmpty ? '타자' : atBat.batterName,
                  secondary: atBat.batterRecent.isEmpty
                      ? _safeDetail(baseState, '타석')
                      : atBat.batterRecent,
                  alignEnd: false,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _ScorebugScore(score: game.away.score),
                          SizedBox(width: 8),
                          _RelayBaseDiamond(
                            occupiedBases: _occupiedBasesForBaseState(
                              baseState,
                            ),
                          ),
                          SizedBox(width: 8),
                          _ScorebugScore(score: game.home.score),
                        ],
                      ),
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.textPrimary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          atBat.inningText.isEmpty
                              ? _safeDetail(game.inning, '경기 중')
                              : atBat.inningText,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      SizedBox(height: 9),
                      _RelayCountDotsRow(
                        balls: atBat.balls,
                        strikes: atBat.strikes,
                        outs: atBat.outs,
                      ),
                    ],
                  ),
                ),
                _ScorebugSide(
                  team: game.home.shortName,
                  primary: atBat.pitcherName.isEmpty ? '투수' : atBat.pitcherName,
                  secondary: atBat.pitchCount > 0
                      ? '${atBat.pitchCount}구'
                      : _safeDetail(game.stadium, 'KBO'),
                  alignEnd: true,
                ),
              ],
            ),
            SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _scorebugBottomText,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _scorebugBottomText {
    final play = latestPlay == null
        ? ''
        : _cleanRelayPlayText(latestPlay!.text);
    if (play.isNotEmpty) {
      return play;
    }
    if (baseState.isNotEmpty) {
      return baseState;
    }
    if (atBat.batterName.isNotEmpty) {
      return '${atBat.batterName} 타석';
    }
    return game.stadium.isEmpty ? 'KBO 경기' : game.stadium;
  }
}

class _ScorebugSide extends StatelessWidget {
  final String team;
  final String primary;
  final String secondary;
  final bool alignEnd;

  const _ScorebugSide({
    required this.team,
    required this.primary,
    required this.secondary,
    required this.alignEnd,
  });

  @override
  Widget build(BuildContext context) {
    final alignment = alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    return SizedBox(
      width: 72,
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Text(
            team,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 22,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 22),
          Text(
            primary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              fontSize: 15,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 5),
          Text(
            secondary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScorebugScore extends StatelessWidget {
  final int? score;

  const _ScorebugScore({required this.score});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      child: Text(
        score?.toString() ?? '-',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 34,
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w900,
          height: 1.0,
        ),
      ),
    );
  }
}

class _RelayBaseDiamond extends StatelessWidget {
  final Set<int> occupiedBases;

  const _RelayBaseDiamond({required this.occupiedBases});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _base(index: 2, offset: Offset(0, -14)),
          _base(index: 3, offset: Offset(-18, 5)),
          _base(index: 1, offset: Offset(18, 5)),
        ],
      ),
    );
  }

  Widget _base({required int index, required Offset offset}) {
    final occupied = occupiedBases.contains(index);
    return Transform.translate(
      offset: offset,
      child: Transform.rotate(
        angle: 0.785398,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: occupied ? AppColors.textPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.textPrimary, width: 1.8),
          ),
        ),
      ),
    );
  }
}

class _RelayCountDotsRow extends StatelessWidget {
  final int balls;
  final int strikes;
  final int outs;

  const _RelayCountDotsRow({
    required this.balls,
    required this.strikes,
    required this.outs,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _RelayCountDots(
          label: 'B',
          value: balls,
          total: 3,
          color: AppColors.positive,
        ),
        _RelayCountDots(
          label: 'S',
          value: strikes,
          total: 2,
          color: AppColors.ballYellow,
        ),
        _RelayCountDots(
          label: 'OUT',
          value: outs,
          total: 2,
          color: AppColors.live,
        ),
      ],
    );
  }
}

class _RelayCountDots extends StatelessWidget {
  final String label;
  final int value;
  final int total;
  final Color color;

  const _RelayCountDots({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(0, total);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(width: 5),
        for (int index = 0; index < total; index++)
          Container(
            width: 8,
            height: 8,
            margin: EdgeInsets.only(right: index == total - 1 ? 0 : 4),
            decoration: BoxDecoration(
              color: index < clampedValue ? color : AppColors.textDisabled,
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}

class _CurrentAtBatHero extends StatelessWidget {
  final Game game;
  final CurrentAtBat atBat;
  final List<RelayItem> items;
  final Map<String, String> imageMap;
  final GameLineupData? lineupData;

  const _CurrentAtBatHero({
    required this.game,
    required this.atBat,
    required this.items,
    required this.imageMap,
    required this.lineupData,
  });

  @override
  Widget build(BuildContext context) {
    final latestPlay = _latestPlay(items);
    final latestSubstitution = _latestSubstitution(items);
    final baseStateLabel = _baseStateLabel;
    final colors = AppTheme.colorsOf(context);
    final isTopHalf =
        _isTopHalfText(atBat.inningText) ?? _isTopHalfText(game.inning);
    final offenseTeam = switch (isTopHalf) {
      true => KboTeams.byId(game.away.teamId),
      false => KboTeams.byId(game.home.teamId),
      null => null,
    };
    final defenseTeam = switch (isTopHalf) {
      true => KboTeams.byId(game.home.teamId),
      false => KboTeams.byId(game.away.teamId),
      null => null,
    };
    final batterAccent = colors.readableAccent(
      offenseTeam?.primaryColor ?? colors.accent,
    );
    final pitcherAccent = colors.readableAccent(
      defenseTeam?.primaryColor ?? colors.live,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 380;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RelayBroadcastScorebug(
                game: game,
                atBat: atBat,
                baseState: baseStateLabel,
                latestPlay: latestPlay,
              ),
              SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '현재 타석',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  if (atBat.inningText.isNotEmpty)
                    _RelayPill(
                      label: atBat.inningText,
                      color: AppColors.textPrimary,
                      subtle: true,
                    ),
                  if (baseStateLabel.isNotEmpty)
                    _BaseStateBadge(baseState: baseStateLabel),
                  _CompactBsoSummary(
                    balls: atBat.balls,
                    strikes: atBat.strikes,
                    outs: atBat.outs,
                  ),
                ],
              ),
              SizedBox(height: 12),
              if (isCompact) ...[
                _ParticipantCard(
                  title: '타자',
                  name: _formatBatterLabel(atBat),
                  detail: _batterDetail(atBat),
                  imageUrl: atBat.batterImageUrl.isNotEmpty
                      ? atBat.batterImageUrl
                      : _resolveImageUrl(imageMap, atBat.batterName),
                  numberLabel: _playerNumberBadgeLabel(atBat.batterNumber),
                  accent: batterAccent,
                ),
                SizedBox(height: 10),
                _ParticipantCard(
                  title: '상대투수',
                  name: _formatPitcherLabel(atBat),
                  detail: _pitcherDetail(atBat),
                  imageUrl: atBat.pitcherImageUrl.isNotEmpty
                      ? atBat.pitcherImageUrl
                      : _resolveImageUrl(imageMap, atBat.pitcherName),
                  numberLabel: _playerNumberBadgeLabel(atBat.pitcherNumber),
                  accent: pitcherAccent,
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
                        numberLabel: _playerNumberBadgeLabel(
                          atBat.batterNumber,
                        ),
                        accent: batterAccent,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: _ParticipantCard(
                        title: '상대투수',
                        name: _formatPitcherLabel(atBat),
                        detail: _pitcherDetail(atBat),
                        imageUrl: atBat.pitcherImageUrl.isNotEmpty
                            ? atBat.pitcherImageUrl
                            : _resolveImageUrl(imageMap, atBat.pitcherName),
                        numberLabel: _playerNumberBadgeLabel(
                          atBat.pitcherNumber,
                        ),
                        accent: pitcherAccent,
                      ),
                    ),
                  ],
                ),
              if (_runnerEntries.isNotEmpty) ...[
                SizedBox(height: 12),
                Text(
                  '루상 주자',
                  style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
                ),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final runner in _runnerEntries)
                      _RunnerPill(baseLabel: runner.$1, name: runner.$2),
                  ],
                ),
              ],
              SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _CountSummaryCard(
                      label: '볼',
                      shortLabel: 'B',
                      filled: atBat.balls,
                      total: 4,
                      activeColor: AppColors.positive,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _CountSummaryCard(
                      label: '스트라이크',
                      shortLabel: 'S',
                      filled: atBat.strikes,
                      total: 3,
                      activeColor: AppColors.ballYellow,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _CountSummaryCard(
                      label: '아웃',
                      shortLabel: 'O',
                      filled: atBat.outs,
                      total: 3,
                      activeColor: AppColors.live,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _CountMeter('B', atBat.balls, 4, AppColors.positive),
                  _CountMeter('S', atBat.strikes, 3, AppColors.ballYellow),
                  _CountMeter('O', atBat.outs, 3, AppColors.live),
                ],
              ),
              if (latestSubstitution != null || latestPlay != null) ...[
                SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.cardSub,
                    borderRadius: BorderRadius.circular(8),
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
                        SizedBox(height: 8),
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
    final lineupEntry = _lineupEntryForCurrentAtBat(game, ab, lineupData);
    if (lineupEntry != null) {
      return _formatLineupEntryLabel(lineupEntry);
    }
    final hand = ab.batterHand.isNotEmpty ? ' · ${ab.batterHand}' : '';
    return '${ab.batterName}$hand';
  }

  String _formatPitcherLabel(CurrentAtBat ab) {
    final hand = ab.pitcherHand.isNotEmpty ? ' · ${ab.pitcherHand}' : '';
    return '${ab.pitcherName}$hand';
  }

  String _batterDetail(CurrentAtBat ab) {
    if (ab.batterRecent.isNotEmpty) {
      return '최근 타석: ${ab.batterRecent}';
    }
    final baseStateLabel = _baseStateLabel;
    if (baseStateLabel.isNotEmpty) {
      return baseStateLabel;
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

  String get _baseStateLabel {
    if (atBat.baseState.isNotEmpty) {
      return atBat.baseState;
    }
    final runners = _runnerEntries;
    final first = runners.any((runner) => runner.$1 == '1루');
    final second = runners.any((runner) => runner.$1 == '2루');
    final third = runners.any((runner) => runner.$1 == '3루');
    if (!first && !second && !third) {
      return '';
    }
    if (first && !second && !third) {
      return '주자1루';
    }
    if (!first && second && !third) {
      return '주자2루';
    }
    if (!first && !second && third) {
      return '주자3루';
    }
    if (first && second && !third) {
      return '주자1,2루';
    }
    if (first && !second && third) {
      return '주자1,3루';
    }
    if (!first && second && third) {
      return '주자2,3루';
    }
    return '만루';
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
  final String? numberLabel;
  final Color accent;

  const _ParticipantCard({
    required this.title,
    required this.name,
    required this.detail,
    this.imageUrl,
    this.numberLabel,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _RelayPlayerAvatar(
            imageUrl: imageUrl,
            fallbackLabel: name,
            badgeLabel: numberLabel,
            accent: accent,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 11, color: AppColors.textDisabled),
                ),
                SizedBox(height: 6),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
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
  final String? imageUrl;
  final String fallbackLabel;
  final double size;
  final double radius;
  final String? badgeLabel;
  final Color? accent;

  const _RelayPlayerAvatar({
    this.imageUrl,
    required this.fallbackLabel,
    this.size = 54,
    this.radius = 8,
    this.badgeLabel,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _imageUrl == null ? _fallback() : _networkAvatar(),
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
        errorWidget: (_, _, _) => _fallback(),
        placeholder: (_, _) => _fallback(),
      ),
    );
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
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _numberBadge(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final fill = accent ?? colors.accent;
    return Positioned(
      right: -4,
      bottom: -4,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.background, width: 1.5),
        ),
        child: Text(
          badgeLabel!,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: colors.readableForegroundOn(fill),
          ),
        ),
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
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.divider),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          children: [
            TextSpan(
              text: '$baseLabel ',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: name,
              style: TextStyle(
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
          margin: EdgeInsets.only(top: 2),
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
        SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
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
                  style: TextStyle(
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
          style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
        ),
        SizedBox(width: 6),
        for (int i = 0; i < total; i++)
          Container(
            width: 12,
            height: 12,
            margin: EdgeInsets.only(right: 4),
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

  const _CompactBsoSummary({
    required this.balls,
    required this.strikes,
    required this.outs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.divider),
      ),
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _MiniCountBadge(label: 'B', value: balls, color: AppColors.positive),
          _MiniCountBadge(
            label: 'S',
            value: strikes,
            color: AppColors.ballYellow,
          ),
          _MiniCountBadge(label: 'O', value: outs, color: AppColors.live),
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
        style: TextStyle(
          fontSize: 11,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
        children: [
          TextSpan(
            text: label,
            style: TextStyle(color: color),
          ),
          TextSpan(text: ' '),
          TextSpan(
            text: '$value',
            style: TextStyle(color: AppColors.textPrimary),
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
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: activeColor.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: activeColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(width: 4),
              Text(
                '$filled',
                style: TextStyle(
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
          SizedBox(height: 8),
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
  final Game game;
  final Map<String, String> imageMap;
  final Map<String, PlayerProfile> playersByName;
  final CurrentAtBat? currentAtBat;
  final GameLineupData? lineupData;
  final int season;

  const _RelayMomentCard({
    required this.moment,
    required this.game,
    required this.imageMap,
    required this.playersByName,
    required this.currentAtBat,
    required this.lineupData,
    required this.season,
  });

  @override
  Widget build(BuildContext context) {
    final accent = moment.isScoring
        ? AppColors.live
        : moment.isSubstitution
        ? AppColors.accent
        : AppColors.textSecondary;
    final eventLabel = _eventLabel(moment.lead.event);
    final actorLabel = _actorLabel(moment.lead.text);
    final actorProfile = actorLabel == null
        ? null
        : _resolvePlayerProfile(playersByName, actorLabel);
    final actorProfileImageUrl = actorProfile == null
        ? null
        : playerProfileImageUrl(actorProfile, season: season);
    final actorImageUrl = actorLabel == null
        ? null
        : (actorProfileImageUrl ?? _resolveImageUrl(imageMap, actorLabel));
    final actorNumber = actorProfile?.number ?? _currentAtBatNumber(actorLabel);
    final offenseTeam = _offenseTeam();
    final defenseTeam = _defenseTeam();
    final actorLineupEntry = actorLabel == null
        ? null
        : _lineupEntryForName(_offenseLineup(), actorLabel);
    final pitcherName = _pitcherNameForMoment();
    final pitchLogs = _buildPitchLogs(moment.pitchItems);
    final scoringPlay = _scoringPlayViewData(moment.lead);

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: moment.isScoring
              ? AppColors.live.withValues(alpha: 0.45)
              : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RelayPill(
                label: moment.inningLabel,
                color: AppColors.textPrimary,
                subtle: true,
              ),
              if (moment.isScoring)
                _RelayPill(label: '득점 장면', color: AppColors.live),
              if (moment.isSubstitution)
                _RelayPill(label: '교체', color: AppColors.accent),
              if (moment.isGameEnd)
                _RelayPill(label: '경기 종료', color: AppColors.textPrimary),
              if (!moment.isSubstitution &&
                  !moment.isGameEnd &&
                  eventLabel != null &&
                  eventLabel != '득점')
                _RelayPill(label: eventLabel, color: accent),
            ],
          ),
          if (actorLabel != null) ...[
            SizedBox(height: 14),
            _MomentPlayerSummary(
              playerName: actorLabel,
              imageUrl: actorImageUrl,
              playerProfile: actorProfile,
              playerNumber: actorNumber,
              lineupEntry: actorLineupEntry,
              offenseTeam: offenseTeam,
              defenseTeam: defenseTeam,
              pitcherName: pitcherName,
            ),
          ],
          if (scoringPlay != null) ...[
            SizedBox(height: actorLabel == null ? 14 : 12),
            _ScoringPlaySummary(data: scoringPlay),
          ],
          SizedBox(height: 16),
          _RelayResultBar(
            label: eventLabel ?? (moment.isGameEnd ? '종료' : '플레이'),
            value: moment.lead.text,
            accent: accent,
            emphasized: moment.isScoring || moment.isGameEnd,
          ),
          if (moment.lead.text.contains(':')) ...[
            SizedBox(height: 8),
            Text(
              _cleanRelayPlayText(moment.lead.text),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
          if (pitchLogs.isNotEmpty) ...[
            SizedBox(height: 12),
            for (int index = 0; index < pitchLogs.length; index++) ...[
              _PitchLogRow(log: pitchLogs[index]),
              if (index != pitchLogs.length - 1) SizedBox(height: 8),
            ],
          ],
          if (moment.lead.pitchSequence != null &&
              moment.lead.pitchSequence!.isNotEmpty) ...[
            SizedBox(height: 12),
            _SequencePill(sequence: moment.lead.pitchSequence!),
          ],
        ],
      ),
    );
  }

  KboTeam? _offenseTeam() {
    final isTop = moment.lead.half == 'top';
    return KboTeams.byId(isTop ? game.away.teamId : game.home.teamId);
  }

  KboTeam? _defenseTeam() {
    final isTop = moment.lead.half == 'top';
    return KboTeams.byId(isTop ? game.home.teamId : game.away.teamId);
  }

  List<LineupEntry> _offenseLineup() {
    final data = lineupData;
    if (data == null) {
      return [];
    }
    return moment.lead.half == 'top' ? data.away.lineup : data.home.lineup;
  }

  String? _pitcherNameForMoment() {
    if (currentAtBat != null &&
        currentAtBat!.pitcherName.isNotEmpty &&
        currentAtBat!.inningText.startsWith(moment.inningLabel)) {
      return currentAtBat!.pitcherName;
    }

    final substitutionMatch = RegExp(
      r'투수\s+(.+?)\s*:\s*투수\s+(.+?)\s+\(으\)로\s+교체',
    ).firstMatch(moment.lead.text);
    final nextPitcher = substitutionMatch?.group(2)?.trim();
    if (nextPitcher != null && nextPitcher.isNotEmpty) {
      return nextPitcher;
    }

    return null;
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
      case 'PASSED_BALL':
        return '포일';
      case 'PLAY':
        return '플레이';
      default:
        return null;
    }
  }

  String? _actorLabel(String text) {
    return _relayLeadActorLabel(text);
  }

  List<_PitchLogViewData> _buildPitchLogs(List<RelayItem> pitchItems) {
    if (pitchItems.isEmpty) {
      return _buildPitchLogsFromSequence(moment.lead.pitchSequence);
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
          text: _pitchDetailLabel(item.text, action),
          pitchNumber: _pitchNumber(item.text),
          actionLabel: _pitchActionLabel(action),
          actionColor: _pitchActionColor(action),
          countText: _countText(balls, strikes),
        ),
      );
    }

    return rows;
  }

  List<_PitchLogViewData> _buildPitchLogsFromSequence(String? pitchSequence) {
    if (pitchSequence == null || pitchSequence.isEmpty) {
      return [];
    }

    final tokens = pitchSequence
        .split('→')
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.isEmpty) {
      return [];
    }

    var balls = 0;
    var strikes = 0;
    final rows = <_PitchLogViewData>[];

    for (int index = 0; index < tokens.length; index++) {
      final token = tokens[index];
      final action = _pitchActionFromSequence(token);
      if (action == _PitchAction.ball) {
        balls = balls < 4 ? balls + 1 : balls;
      } else if (action == _PitchAction.strike) {
        strikes = strikes < 3 ? strikes + 1 : strikes;
      } else if (action == _PitchAction.foul && strikes < 2) {
        strikes += 1;
      }

      rows.add(
        _PitchLogViewData(
          text: _sequenceTokenLabel(token),
          pitchNumber: index + 1,
          actionLabel: _pitchActionLabel(action),
          actionColor: _pitchActionColor(action),
          countText: _countText(balls, strikes),
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

  _PitchAction _pitchActionFromSequence(String token) {
    final normalized = token.toUpperCase();
    if (normalized == 'B' || token.contains('볼')) {
      return _PitchAction.ball;
    }
    if (normalized == 'S' || token.contains('스트라이크') || token.contains('헛스윙')) {
      return _PitchAction.strike;
    }
    if (normalized == 'F' || token.contains('파울')) {
      return _PitchAction.foul;
    }
    if (token.contains('타격')) {
      return _PitchAction.inPlay;
    }
    return _PitchAction.other;
  }

  String _sequenceTokenLabel(String token) {
    final normalized = token.toUpperCase();
    if (normalized == 'B') return '볼';
    if (normalized == 'S') return '스트라이크';
    if (normalized == 'F') return '파울';
    return token;
  }

  String _pitchDetailLabel(String text, _PitchAction action) {
    final cleaned = text.replaceFirst('- ', '').trim();
    if (cleaned.isNotEmpty) {
      return cleaned;
    }
    return _pitchActionLabel(action) ?? '투구';
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
        return AppColors.positive;
      case _PitchAction.strike:
        return AppColors.ballYellow;
      case _PitchAction.foul:
        return AppColors.accent;
      case _PitchAction.inPlay:
        return AppColors.accent;
      case _PitchAction.other:
        return AppColors.textSecondary;
    }
  }

  String _countText(int balls, int strikes) {
    return '$balls-$strikes';
  }

  PlayerProfile? _resolvePlayerProfile(
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

  int? _currentAtBatNumber(String? rawName) {
    if (currentAtBat == null || rawName == null || rawName.isEmpty) {
      return null;
    }
    final target = _normalizeName(rawName);
    if (target.isEmpty) {
      return null;
    }
    if (_normalizeName(currentAtBat!.batterName) == target) {
      return currentAtBat!.batterNumber;
    }
    if (_normalizeName(currentAtBat!.pitcherName) == target) {
      return currentAtBat!.pitcherNumber;
    }
    return null;
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
    return _normalizeRelayPlayerName(value);
  }
}

class _RelayResultBar extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  final bool emphasized;

  const _RelayResultBar({
    required this.label,
    required this.value,
    required this.accent,
    required this.emphasized,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.72)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(minWidth: 42),
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: accent.withValues(alpha: 0.28)),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: emphasized ? AppColors.textPrimary : accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                color: emphasized
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontWeight: emphasized ? FontWeight.w800 : FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoringPlaySummary extends StatelessWidget {
  final _ScoringPlayViewData data;

  const _ScoringPlaySummary({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (data.batterName != null)
          _ScoringFactRow(label: '친 선수', value: data.batterName!),
        if (data.batterName != null && data.scoredRunnerNames.isNotEmpty)
          SizedBox(height: 8),
        if (data.scoredRunnerNames.isNotEmpty)
          _ScoringFactRow(
            label: '홈인',
            value: data.scoredRunnerNames.join(', '),
          ),
      ],
    );
  }
}

class _ScoringFactRow extends StatelessWidget {
  final String label;
  final String value;

  const _ScoringFactRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.live,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _MomentPlayerSummary extends StatelessWidget {
  final String playerName;
  final String? imageUrl;
  final PlayerProfile? playerProfile;
  final int? playerNumber;
  final LineupEntry? lineupEntry;
  final KboTeam? offenseTeam;
  final KboTeam? defenseTeam;
  final String? pitcherName;

  const _MomentPlayerSummary({
    required this.playerName,
    required this.imageUrl,
    required this.playerProfile,
    required this.playerNumber,
    required this.lineupEntry,
    required this.offenseTeam,
    required this.defenseTeam,
    required this.pitcherName,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final badgeAccent = colors.readableAccent(
      offenseTeam?.primaryColor ?? colors.accent,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RelayPlayerAvatar(
          imageUrl: imageUrl,
          fallbackLabel: playerName,
          size: 64,
          radius: 8,
          badgeLabel: _playerNumberBadgeLabel(playerNumber ?? 0),
          accent: badgeAccent,
        ),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (offenseTeam != null)
                    KboTeamLogoImage(
                      teamId: offenseTeam!.id,
                      fallback: offenseTeam!.shortName,
                      size: 22,
                      padding: 1,
                    ),
                  if (offenseTeam != null) SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _nameLine(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6),
              Text(
                _statLine(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              pitcherName == null ? '상대팀' : '상대투수',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textDisabled,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6),
            Text(
              pitcherName ?? defenseTeam?.shortName ?? '-',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _nameLine() {
    final lineupLabel = lineupEntry == null
        ? null
        : _formatLineupEntryLabel(lineupEntry!);
    if (lineupLabel != null && lineupLabel.isNotEmpty) {
      return lineupLabel;
    }
    final metric = _primaryMetric();
    return '$playerName${metric == null ? '' : '  $metric'}';
  }

  String _statLine() {
    if (playerProfile == null) {
      return '선수 정보 확인 중';
    }

    final values = <String>[
      if (playerProfile!.headlineStat.isNotEmpty) playerProfile!.headlineStat,
      if (playerProfile!.secondaryStat.isNotEmpty) playerProfile!.secondaryStat,
    ];
    if (values.isEmpty) {
      return playerProfile!.roleLabel;
    }
    return values.join(' | ');
  }

  String? _primaryMetric() {
    if (playerProfile == null) {
      return null;
    }
    if (playerProfile!.playerType == PlayerType.pitcher) {
      if (playerProfile!.era != null) {
        return 'ERA ${playerProfile!.era!.toStringAsFixed(2)}';
      }
      return null;
    }
    if (playerProfile!.avg != null) {
      return '타율 ${playerProfile!.avg!.toStringAsFixed(3)}';
    }
    return null;
  }
}

class _OutStateIndicator extends StatelessWidget {
  final int outs;

  const _OutStateIndicator({required this.outs});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= 3; i++) ...[
          Container(
            width: 26,
            height: 26,
            margin: EdgeInsets.only(right: i == 3 ? 6 : 4),
            decoration: BoxDecoration(
              color: i <= outs
                  ? AppColors.live
                  : AppColors.textDisabled.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$i',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: colors.readableForegroundOn(AppColors.live),
              ),
            ),
          ),
        ],
        Text(
          'OUT',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SequencePill extends StatelessWidget {
  final String sequence;

  const _SequencePill({required this.sequence});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        sequence,
        style: TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PitchLogRow extends StatelessWidget {
  final _PitchLogViewData log;

  const _PitchLogRow({required this.log});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.divider.withValues(alpha: 0.55)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: log.actionColor,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '${log.pitchNumber ?? '-'}',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: colors.readableForegroundOn(log.actionColor),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              log.text,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: 12),
          Text(
            log.countText ?? '',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
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
  final String? countText;

  _PitchLogViewData({
    required this.text,
    this.pitchNumber,
    required this.actionLabel,
    required this.actionColor,
    this.countText,
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
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
    final occupiedBases = _occupiedBasesForBaseState(baseState);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                _baseDot(occupiedBases.contains(2), Offset(0, -5)),
                _baseDot(occupiedBases.contains(1), Offset(5, 0)),
                _baseDot(occupiedBases.contains(3), Offset(-5, 0)),
              ],
            ),
          ),
          SizedBox(width: 8),
          Text(
            baseState,
            style: TextStyle(
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

Set<int> _occupiedBasesForBaseState(String baseState) {
  final normalized = baseState.replaceAll(RegExp(r'\s+'), '');
  if (normalized.isEmpty ||
      normalized.contains('주자없음') ||
      normalized.contains('주자무')) {
    return <int>{};
  }
  final imageMatch = RegExp(r'ground_base(\d+)').firstMatch(normalized);
  if (imageMatch != null) {
    return switch (imageMatch.group(1)) {
      '1' => {1},
      '2' => {2},
      '3' => {1, 2},
      '4' => {3},
      '5' => {1, 3},
      '6' => {2, 3},
      '7' => {1, 2, 3},
      _ => <int>{},
    };
  }
  if (normalized.contains('만루')) {
    return {1, 2, 3};
  }
  final state = normalized.replaceFirst('주자', '');
  return {
    if (RegExp(r'1(?=루|[,/·ㆍ-]|$)').hasMatch(state)) 1,
    if (RegExp(r'2(?=루|[,/·ㆍ-]|$)').hasMatch(state)) 2,
    if (RegExp(r'3(?=루|[,/·ㆍ-]|$)').hasMatch(state)) 3,
  };
}

String _safeDetail(String value, String fallback) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

String _cleanRelayPlayText(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (trimmed.startsWith('- ')) {
    return trimmed.replaceFirst('- ', '').trim();
  }
  final colonIndex = trimmed.indexOf(':');
  if (colonIndex > 0 && colonIndex < trimmed.length - 1) {
    return trimmed.substring(colonIndex + 1).trim();
  }
  return trimmed;
}

String? _playerNumberBadgeLabel(int number) {
  return number > 0 ? '$number' : null;
}

class _ScoringPlayViewData {
  final String? batterName;
  final List<String> scoredRunnerNames;

  const _ScoringPlayViewData({
    required this.batterName,
    required this.scoredRunnerNames,
  });
}

class _RelayMoment {
  final String inningLabel;
  final RelayItem lead;
  final List<RelayItem> pitchItems;
  final bool isScoring;
  final bool isGameEnd;
  final bool isSubstitution;

  _RelayMoment({
    required this.inningLabel,
    required this.lead,
    required this.pitchItems,
    required this.isScoring,
    required this.isGameEnd,
    required this.isSubstitution,
  });
}

enum _RelayMomentFilter {
  all('전체'),
  scoring('득점'),
  hit('안타'),
  homerun('홈런'),
  substitution('교체');

  const _RelayMomentFilter(this.label);

  final String label;

  bool matches(_RelayMoment moment) {
    switch (this) {
      case _RelayMomentFilter.all:
        return true;
      case _RelayMomentFilter.scoring:
        return moment.isScoring || moment.lead.event == 'RUNS';
      case _RelayMomentFilter.hit:
        return moment.lead.event == 'HIT';
      case _RelayMomentFilter.homerun:
        return moment.lead.event == 'HOMERUN' ||
            moment.lead.text.contains('홈런');
      case _RelayMomentFilter.substitution:
        return moment.isSubstitution;
    }
  }
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
