import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/team_data.dart';
import '../../../core/constants/visual_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/kbo_player_image_cache.dart';
import '../../../core/utils/kbo_time.dart';
import '../../../core/widgets/app_artwork_card.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/kbo_team_logo_image.dart';
import '../../../data/models/game.dart';
import '../../../data/models/boxscore.dart';
import '../../../data/models/player.dart';
import '../../../data/models/relay.dart';
import '../../../data/models/records_overview.dart';
import '../../../data/models/schedule.dart';
import '../../../data/models/team_stats.dart';
import '../../../data/providers.dart';

class LineupTab extends ConsumerStatefulWidget {
  final String gameId;
  final GameStatus gameStatus;
  final String awayName;
  final String homeName;
  final String awayTeamId;
  final String homeTeamId;
  final Future<void> Function()? onRefresh;

  const LineupTab({
    super.key,
    required this.gameId,
    required this.gameStatus,
    this.awayName = '원정',
    this.homeName = '홈',
    this.awayTeamId = '',
    this.homeTeamId = '',
    this.onRefresh,
  });

  @override
  ConsumerState<LineupTab> createState() => _LineupTabState();
}

class _LineupTabState extends ConsumerState<LineupTab> {
  String? _lastPrefetchedImageSignature;
  bool _lineupRetrying = false;

  @override
  Widget build(BuildContext context) {
    final gameId = widget.gameId;
    final gameStatus = widget.gameStatus;
    final awayName = widget.awayName;
    final homeName = widget.homeName;
    final awayTeamId = widget.awayTeamId;
    final homeTeamId = widget.homeTeamId;
    final onRefresh = widget.onRefresh;
    final colors = AppTheme.colorsOf(context);
    if (gameStatus == GameStatus.cancelled) {
      return _buildUnavailableState('취소된 경기는 라인업이 없습니다');
    }

    final gameLineupAsync = ref.watch(gameLineupProvider(gameId));
    final gameBoxscoreAsync =
        gameStatus == GameStatus.scheduled || gameStatus == GameStatus.cancelled
        ? null
        : ref.watch(gameBoxscoreProvider(gameId));
    final season = _seasonFromGameId(gameId);
    final awayPlayersAsync = awayTeamId.isEmpty
        ? const AsyncValue<List<PlayerProfile>>.data(<PlayerProfile>[])
        : ref.watch(teamPlayersProvider('$awayTeamId|$season'));
    final homePlayersAsync = homeTeamId.isEmpty
        ? const AsyncValue<List<PlayerProfile>>.data(<PlayerProfile>[])
        : ref.watch(teamPlayersProvider('$homeTeamId|$season'));
    const allImageMap = <String, String>{};

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
              onRefresh: onRefresh ?? () async {},
              color: AppColors.live,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                child: AppMotionSwitcher(
                  child: gameLineupAsync.when(
                    loading: () => Padding(
                      key: ValueKey('lineup-loading'),
                      padding: EdgeInsets.all(28),
                      child: Center(
                        child: CircularProgressIndicator(color: AppColors.live),
                      ),
                    ),
                    error: (error, _) => _buildLineupErrorState(error),
                    data: (gameLineup) {
                      if (gameStatus == GameStatus.scheduled &&
                          !_hasPublishedLineup(gameLineup)) {
                        return KeyedSubtree(
                          key: const ValueKey('lineup-unavailable'),
                          child: _buildUnavailableState('라인업 공개 전입니다'),
                        );
                      }
                      final awayImageMap = _buildPlayerImageMap(
                        allImageMap: allImageMap,
                        teamPlayers:
                            awayPlayersAsync.asData?.value ??
                            const <PlayerProfile>[],
                        season: season,
                        relayData: null,
                      );
                      final homeImageMap = _buildPlayerImageMap(
                        allImageMap: allImageMap,
                        teamPlayers:
                            homePlayersAsync.asData?.value ??
                            const <PlayerProfile>[],
                        season: season,
                        relayData: null,
                      );
                      final boxscore = gameBoxscoreAsync?.asData?.value;
                      final awayPitchers =
                          boxscore?.away.pitchers
                              .where(_isOfficialPitcherRecord)
                              .toList() ??
                          const <PitcherRecord>[];
                      final homePitchers =
                          boxscore?.home.pitchers
                              .where(_isOfficialPitcherRecord)
                              .toList() ??
                          const <PitcherRecord>[];
                      final awayStarter = _starterPitcher(
                        awayPitchers,
                        gameLineup.away.starterName,
                      );
                      final homeStarter = _starterPitcher(
                        homePitchers,
                        gameLineup.home.starterName,
                      );
                      final awayStarterImageUrl = _resolveStarterImageUrl(
                        awayImageMap,
                        name:
                            gameLineup.away.starterName ??
                            awayStarter?.name ??
                            '',
                        starterId: gameLineup.away.starterId,
                        starterImageUrl: gameLineup.away.starterImageUrl,
                        season: season,
                      );
                      final homeStarterImageUrl = _resolveStarterImageUrl(
                        homeImageMap,
                        name:
                            gameLineup.home.starterName ??
                            homeStarter?.name ??
                            '',
                        starterId: gameLineup.home.starterId,
                        starterImageUrl: gameLineup.home.starterImageUrl,
                        season: season,
                      );
                      final compareData = _buildMatchupCompareData(
                        awayTeamId: awayTeamId,
                        awayName: awayName,
                        homeTeamId: homeTeamId,
                        homeName: homeName,
                        standings: const [],
                        scheduleDays: const [],
                        awayTeamStats: null,
                        homeTeamStats: null,
                        awayStarter: awayStarter,
                        homeStarter: homeStarter,
                        awayStarterName: gameLineup.away.starterName,
                        homeStarterName: gameLineup.home.starterName,
                        awayStarterImageUrl: awayStarterImageUrl,
                        homeStarterImageUrl: homeStarterImageUrl,
                      );
                      final hasComparisonData = _hasMatchupComparisonData(
                        compareData,
                      );
                      _prefetchLineupPlayerImages([
                        awayStarterImageUrl,
                        homeStarterImageUrl,
                        ...awayImageMap.values,
                        ...homeImageMap.values,
                        for (final entry in gameLineup.away.lineup)
                          _resolveLineupEntryImageUrl(
                            awayImageMap,
                            entry,
                            season: season,
                          ),
                        for (final entry in gameLineup.home.lineup)
                          _resolveLineupEntryImageUrl(
                            homeImageMap,
                            entry,
                            season: season,
                          ),
                      ]);

                      return Column(
                        key: ValueKey(
                          'lineup-data-${gameLineup.away.lineup.length}-${gameLineup.home.lineup.length}',
                        ),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hasComparisonData) ...[
                            AppMotionListItem(
                              index: 0,
                              child: _MatchupCompareSection(
                                data: compareData,
                                awayAccent: colors.readableAccent(
                                  KboTeams.byId(awayTeamId)?.primaryColor ??
                                      colors.live,
                                ),
                                homeAccent: colors.readableAccent(
                                  KboTeams.byId(homeTeamId)?.primaryColor ??
                                      colors.accent,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          AppMotionListItem(
                            index: hasComparisonData ? 1 : 0,
                            child: _CompareSection(
                              title: '선발 라인업',
                              left: _LineupColumn(
                                teamId: awayTeamId,
                                teamName: awayName,
                                sideLabel: 'AWAY',
                                season: season,
                                starterId: gameLineup.away.starterId,
                                starterName: gameLineup.away.starterName,
                                starterImageUrl:
                                    gameLineup.away.starterImageUrl,
                                lineup: gameLineup.away.lineup,
                                batterFallback: const <BatterRecord>[],
                                pitchers: awayPitchers,
                                relayData: null,
                                imageMap: awayImageMap,
                                showBullpen: false,
                                isLive: gameStatus == GameStatus.live,
                                isAwayTeam: true,
                              ),
                              right: _LineupColumn(
                                teamId: homeTeamId,
                                teamName: homeName,
                                sideLabel: 'HOME',
                                season: season,
                                starterId: gameLineup.home.starterId,
                                starterName: gameLineup.home.starterName,
                                starterImageUrl:
                                    gameLineup.home.starterImageUrl,
                                lineup: gameLineup.home.lineup,
                                batterFallback: const <BatterRecord>[],
                                pitchers: homePitchers,
                                relayData: null,
                                imageMap: homeImageMap,
                                showBullpen: false,
                                isLive: gameStatus == GameStatus.live,
                                isAwayTeam: false,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLineupErrorState(Object error) {
    if (_isTransientLineupLoadError(error)) {
      return _buildUnavailableState(
        '라인업 응답이 지연되고 있습니다',
        detail: '네트워크 상태를 확인하고 다시 시도해 주세요',
        showRetry: true,
      );
    }

    return _buildUnavailableState(
      '라인업을 불러올 수 없습니다',
      detail: '네트워크 상태를 확인하고 다시 시도해 주세요',
      showRetry: true,
    );
  }

  Widget _buildUnavailableState(
    String message, {
    String? detail,
    bool showRetry = false,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        key: const ValueKey('lineup-state-card'),
        constraints: const BoxConstraints(minHeight: 178),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: AppArtworkBackdrop(
          assetName: VisualAssets.lineupDugout,
          alignment: Alignment.center,
          borderRadius: BorderRadius.circular(8),
          padding: const EdgeInsets.all(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 148),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text(
                  '선발 라인업',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSupporting,
                      height: 1.35,
                    ),
                  ),
                ],
                if (showRetry) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('lineup-retry-button'),
                    onPressed: _lineupRetrying
                        ? null
                        : () => unawaited(_retryLineup()),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(_lineupRetrying ? '다시 불러오는 중' : '다시 시도'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _retryLineup() async {
    if (_lineupRetrying) {
      return;
    }
    setState(() => _lineupRetrying = true);
    try {
      final onRefresh = widget.onRefresh;
      if (onRefresh != null) {
        await onRefresh();
      } else {
        final provider = gameLineupProvider(widget.gameId);
        ref.invalidate(provider);
        await ref.read(provider.future);
      }
    } catch (_) {
      // Provider 오류 상태가 재시도 UI를 계속 유지한다.
    } finally {
      if (mounted) {
        setState(() => _lineupRetrying = false);
      }
    }
  }

  void _prefetchLineupPlayerImages(Iterable<String?> imageUrls) {
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
}

bool _isTransientLineupLoadError(Object error) {
  if (error is TimeoutException) {
    return true;
  }
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badCertificate:
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return false;
    }
  }
  return false;
}

bool _hasPublishedLineup(GameLineupData gameLineup) {
  return gameLineup.away.lineup.isNotEmpty ||
      gameLineup.home.lineup.isNotEmpty ||
      (gameLineup.away.starterName?.isNotEmpty ?? false) ||
      (gameLineup.home.starterName?.isNotEmpty ?? false);
}

_MatchupCompareData _buildMatchupCompareData({
  required String awayTeamId,
  required String awayName,
  required String homeTeamId,
  required String homeName,
  required List<TeamStanding> standings,
  required List<ScheduleDay> scheduleDays,
  required TeamStats? awayTeamStats,
  required TeamStats? homeTeamStats,
  required PitcherRecord? awayStarter,
  required PitcherRecord? homeStarter,
  required String? awayStarterName,
  required String? homeStarterName,
  required String? awayStarterImageUrl,
  required String? homeStarterImageUrl,
}) {
  final awayStanding = standings
      .where((item) => item.teamId == awayTeamId)
      .firstOrNull;
  final homeStanding = standings
      .where((item) => item.teamId == homeTeamId)
      .firstOrNull;
  final allGames = [
    for (final day in scheduleDays)
      for (final game in day.games) (date: day.date, game: game),
  ]..sort((a, b) => a.date.compareTo(b.date));

  List<_RecentResultChipData> recentResults(String teamId) {
    final finished =
        allGames
            .where(
              (entry) =>
                  entry.game.awayScore != null && entry.game.homeScore != null,
            )
            .where(
              (entry) =>
                  entry.game.awayId == teamId || entry.game.homeId == teamId,
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    return finished.take(5).map((entry) {
      final isAway = entry.game.awayId == teamId;
      final myScore = isAway ? entry.game.awayScore! : entry.game.homeScore!;
      final opponentScore = isAway
          ? entry.game.homeScore!
          : entry.game.awayScore!;
      final result = myScore > opponentScore
          ? '승'
          : myScore < opponentScore
          ? '패'
          : '무';
      return _RecentResultChipData(result: result);
    }).toList();
  }

  String headToHeadSummary(String teamId, String opponentTeamId) {
    var wins = 0;
    var losses = 0;
    var draws = 0;
    for (final entry in allGames) {
      final game = entry.game;
      final isMatchup =
          (game.awayId == teamId && game.homeId == opponentTeamId) ||
          (game.awayId == opponentTeamId && game.homeId == teamId);
      if (!isMatchup || game.awayScore == null || game.homeScore == null) {
        continue;
      }
      final isAway = game.awayId == teamId;
      final myScore = isAway ? game.awayScore! : game.homeScore!;
      final opponentScore = isAway ? game.homeScore! : game.awayScore!;
      if (myScore > opponentScore) {
        wins += 1;
      } else if (myScore < opponentScore) {
        losses += 1;
      } else {
        draws += 1;
      }
    }
    return '$wins승 $draws무 $losses패';
  }

  String safeStat(Map<String, String>? stats, String key) {
    return stats?[key] ?? '-';
  }

  return _MatchupCompareData(
    away: _TeamCompareData(
      teamId: awayTeamId,
      teamName: awayName,
      standingText: awayStanding == null ? '' : '${awayStanding.rank}위',
      recordText: awayStanding == null
          ? ''
          : '${awayStanding.wins}승 ${awayStanding.draws}무 ${awayStanding.losses}패',
      recentResults: recentResults(awayTeamId),
      winPct: awayStanding?.pct ?? safeStat(awayTeamStats?.pitching, 'WPCT'),
      avg: safeStat(awayTeamStats?.hitting, 'AVG'),
      era: safeStat(awayTeamStats?.pitching, 'ERA'),
      headToHead: scheduleDays.isEmpty
          ? ''
          : headToHeadSummary(awayTeamId, homeTeamId),
      starter: _StarterCompareData(
        name: awayStarterName ?? awayStarter?.name ?? '선발 미발표',
        imageUrl: awayStarterImageUrl,
        winsLosses: _pitcherDecision(awayStarter),
        innings: _pitcherInnings(awayStarter),
        era: _formatPitcherMetric(awayStarter?.gameEra),
        whip: _formatPitcherMetric(awayStarter?.gameWhip),
      ),
    ),
    home: _TeamCompareData(
      teamId: homeTeamId,
      teamName: homeName,
      standingText: homeStanding == null ? '' : '${homeStanding.rank}위',
      recordText: homeStanding == null
          ? ''
          : '${homeStanding.wins}승 ${homeStanding.draws}무 ${homeStanding.losses}패',
      recentResults: recentResults(homeTeamId),
      winPct: homeStanding?.pct ?? safeStat(homeTeamStats?.pitching, 'WPCT'),
      avg: safeStat(homeTeamStats?.hitting, 'AVG'),
      era: safeStat(homeTeamStats?.pitching, 'ERA'),
      headToHead: scheduleDays.isEmpty
          ? ''
          : headToHeadSummary(homeTeamId, awayTeamId),
      starter: _StarterCompareData(
        name: homeStarterName ?? homeStarter?.name ?? '선발 미발표',
        imageUrl: homeStarterImageUrl,
        winsLosses: _pitcherDecision(homeStarter),
        innings: _pitcherInnings(homeStarter),
        era: _formatPitcherMetric(homeStarter?.gameEra),
        whip: _formatPitcherMetric(homeStarter?.gameWhip),
      ),
    ),
  );
}

bool _isOfficialPitcherRecord(PitcherRecord pitcher) {
  return !pitcher.liveContext && pitcher.hasDisplayableLine;
}

String _pitcherDecision(PitcherRecord? pitcher) {
  final decision = pitcher?.decision?.trim();
  if (decision == null ||
      decision.isEmpty ||
      decision == '-' ||
      decision.toUpperCase() == 'LIVE') {
    return '-';
  }
  return decision;
}

String _pitcherInnings(PitcherRecord? pitcher) {
  final innings = pitcher?.innings.trim() ?? '';
  if (innings.isEmpty || innings == '0.0') {
    return '-';
  }
  return innings;
}

String _formatPitcherMetric(double? value) {
  if (value == null) {
    return '-';
  }
  return value.toStringAsFixed(2);
}

class _MatchupCompareSection extends StatelessWidget {
  final _MatchupCompareData data;
  final Color awayAccent;
  final Color homeAccent;

  const _MatchupCompareSection({
    required this.data,
    required this.awayAccent,
    required this.homeAccent,
  });

  @override
  Widget build(BuildContext context) {
    final hasTrendData = _hasTrendData(data.away, data.home);

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: AppArtworkLayer(
              assetName: VisualAssets.lineupMatchup,
              alignment: Alignment.center,
              opacity: 0.2,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            child: Column(
              children: [
                _MatchupHeader(data: data),
                if (hasTrendData) ...[
                  const SizedBox(height: 18),
                  _RecentTrendSection(
                    away: data.away,
                    home: data.home,
                    awayAccent: awayAccent,
                    homeAccent: homeAccent,
                  ),
                  const SizedBox(height: 20),
                ] else
                  const SizedBox(height: 16),
                _StarterDuelSection(
                  away: data.away.starter,
                  home: data.home.starter,
                  awayAccent: awayAccent,
                  homeAccent: homeAccent,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchupHeader extends StatelessWidget {
  final _MatchupCompareData data;

  const _MatchupHeader({required this.data});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    Widget teamBlock(_TeamCompareData team, {required bool alignEnd}) {
      return Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            team.teamName,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
          ),
          if (team.standingText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              team.standingText,
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
          ],
          if (team.recordText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              team.recordText,
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
          ],
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: teamBlock(data.away, alignEnd: true)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            'VS',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              color: colors.textSupporting,
            ),
          ),
        ),
        Expanded(child: teamBlock(data.home, alignEnd: false)),
      ],
    );
  }
}

class _RecentTrendSection extends StatelessWidget {
  final _TeamCompareData away;
  final _TeamCompareData home;
  final Color awayAccent;
  final Color homeAccent;

  const _RecentTrendSection({
    required this.away,
    required this.home,
    required this.awayAccent,
    required this.homeAccent,
  });

  @override
  Widget build(BuildContext context) {
    if (!_hasTrendData(away, home)) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        Divider(color: AppColors.divider, height: 1),
        const SizedBox(height: 20),
        Text(
          '최근 5경기',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _RecentResultRow(
                items: away.recentResults,
                accent: awayAccent,
                alignEnd: true,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _RecentResultRow(
                items: home.recentResults,
                accent: homeAccent,
                alignEnd: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _CompareMetricBarRow(
          label: '승률',
          leftValue: away.winPct,
          rightValue: home.winPct,
          leftAccent: awayAccent,
          rightAccent: homeAccent,
        ),
        const SizedBox(height: 16),
        _CompareMetricBarRow(
          label: '타율',
          leftValue: away.avg,
          rightValue: home.avg,
          leftAccent: awayAccent,
          rightAccent: homeAccent,
        ),
        const SizedBox(height: 16),
        _CompareMetricBarRow(
          label: '평균자책',
          leftValue: away.era,
          rightValue: home.era,
          leftAccent: awayAccent,
          rightAccent: homeAccent,
          lowerIsBetter: true,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                away.headToHead,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: AppColors.textPrimary),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '상대전적',
                style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              child: Text(
                home.headToHead,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecentResultRow extends StatelessWidget {
  final List<_RecentResultChipData> items;
  final Color accent;
  final bool alignEnd;

  const _RecentResultRow({
    required this.items,
    required this.accent,
    required this.alignEnd,
  });

  @override
  Widget build(BuildContext context) {
    final chips = items
        .take(5)
        .map((item) => _RecentResultBubble(result: item.result, accent: accent))
        .toList();
    return Wrap(
      alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
      spacing: 4,
      runSpacing: 6,
      children: chips,
    );
  }
}

class _RecentResultBubble extends StatelessWidget {
  final String result;
  final Color accent;

  const _RecentResultBubble({required this.result, required this.accent});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final background = switch (result) {
      '승' => const Color(0xFF18C8F7),
      '패' => const Color(0xFFD41438),
      _ => const Color(0xFF585858),
    };
    final labelColor = colors.readableForegroundOn(background);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          result,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: labelColor,
          ),
        ),
      ),
    );
  }
}

class _CompareMetricBarRow extends StatelessWidget {
  final String label;
  final String leftValue;
  final String rightValue;
  final Color leftAccent;
  final Color rightAccent;
  final bool lowerIsBetter;

  const _CompareMetricBarRow({
    required this.label,
    required this.leftValue,
    required this.rightValue,
    required this.leftAccent,
    required this.rightAccent,
    this.lowerIsBetter = false,
  });

  @override
  Widget build(BuildContext context) {
    final leftNumber = double.tryParse(leftValue.replaceAll('%', ''));
    final rightNumber = double.tryParse(rightValue.replaceAll('%', ''));
    double leftRatio = 0.5;
    double rightRatio = 0.5;
    if (leftNumber != null &&
        rightNumber != null &&
        leftNumber + rightNumber > 0) {
      if (lowerIsBetter) {
        final leftAdjusted = 1 / leftNumber;
        final rightAdjusted = 1 / rightNumber;
        final total = leftAdjusted + rightAdjusted;
        leftRatio = leftAdjusted / total;
        rightRatio = rightAdjusted / total;
      } else {
        final total = leftNumber + rightNumber;
        leftRatio = leftNumber / total;
        rightRatio = rightNumber / total;
      }
    }

    return Row(
      children: [
        Expanded(
          child: _MetricSideBar(
            value: leftValue,
            ratio: leftRatio,
            accent: leftAccent,
            alignEnd: true,
          ),
        ),
        SizedBox(
          width: 116,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: _MetricSideBar(
            value: rightValue,
            ratio: rightRatio,
            accent: rightAccent,
            alignEnd: false,
          ),
        ),
      ],
    );
  }
}

class _MetricSideBar extends StatelessWidget {
  final String value;
  final double ratio;
  final Color accent;
  final bool alignEnd;

  const _MetricSideBar({
    required this.value,
    required this.ratio,
    required this.accent,
    required this.alignEnd,
  });

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      height: 12,
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Align(
        alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: ratio.clamp(0.18, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        bar,
      ],
    );
  }
}

class _StarterDuelSection extends StatelessWidget {
  final _StarterCompareData away;
  final _StarterCompareData home;
  final Color awayAccent;
  final Color homeAccent;

  const _StarterDuelSection({
    required this.away,
    required this.home,
    required this.awayAccent,
    required this.homeAccent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    return Column(
      children: [
        Divider(color: AppColors.divider, height: 1),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _StarterHeroCard(data: away, accent: awayAccent),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(12, 24, 12, 0),
              child: Column(
                children: [
                  Text(
                    '선발',
                    style: TextStyle(
                      fontSize: 17,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'VS',
                    style: TextStyle(
                      fontSize: 48,
                      color: colors.textSupporting,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _StarterHeroCard(data: home, accent: homeAccent),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: _StarterStatColumn(data: away, alignEnd: true)),
            const SizedBox(
              width: 104,
              child: Column(
                children: [
                  _CenterStatLabel('승패'),
                  SizedBox(height: 12),
                  _CenterStatLabel('이닝'),
                  SizedBox(height: 12),
                  _CenterStatLabel('평균자책'),
                  SizedBox(height: 12),
                  _CenterStatLabel('WHIP'),
                ],
              ),
            ),
            Expanded(child: _StarterStatColumn(data: home, alignEnd: false)),
          ],
        ),
      ],
    );
  }
}

class _StarterHeroCard extends StatelessWidget {
  final _StarterCompareData data;
  final Color accent;

  const _StarterHeroCard({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 132,
          decoration: BoxDecoration(
            color: AppColors.cardSub,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.24)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: data.imageUrl != null && data.imageUrl!.isNotEmpty
                ? Container(
                    color: AppColors.cardSub,
                    alignment: Alignment.bottomCenter,
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        widthFactor: 0.9,
                        heightFactor: 0.94,
                        alignment: Alignment.bottomCenter,
                        child: CachedNetworkImage(
                          imageUrl: data.imageUrl!,
                          httpHeaders: kboPlayerImageHeaders,
                          cacheManager: kboPlayerImageCacheManager,
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity,
                          memCacheWidth: 720,
                          memCacheHeight: 660,
                          maxWidthDiskCache: 720,
                          maxHeightDiskCache: 660,
                          alignment: Alignment.bottomCenter,
                          placeholder: (_, _) =>
                              _starterFallback(accent, data.name),
                          errorWidget: (_, _, _) =>
                              _starterFallback(accent, data.name),
                        ),
                      ),
                    ),
                  )
                : _starterFallback(accent, data.name),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          data.name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  Widget _starterFallback(Color accent, String name) {
    return Container(
      color: AppColors.cardSub,
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.substring(0, 1),
        style: TextStyle(
          fontSize: 64,
          fontWeight: FontWeight.w800,
          color: accent.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

class _StarterStatColumn extends StatelessWidget {
  final _StarterCompareData data;
  final bool alignEnd;

  const _StarterStatColumn({required this.data, required this.alignEnd});

  @override
  Widget build(BuildContext context) {
    TextStyle style = const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
    );
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(data.winsLosses, style: style),
        const SizedBox(height: 10),
        Text(data.innings, style: style),
        const SizedBox(height: 10),
        Text(data.era, style: style),
        const SizedBox(height: 10),
        Text(data.whip, style: style),
      ],
    );
  }
}

class _CenterStatLabel extends StatelessWidget {
  final String label;

  const _CenterStatLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
    );
  }
}

bool _hasTrendData(_TeamCompareData away, _TeamCompareData home) {
  final hasRecent =
      away.recentResults.isNotEmpty || home.recentResults.isNotEmpty;
  final hasMetrics =
      away.winPct != '-' ||
      home.winPct != '-' ||
      away.avg != '-' ||
      home.avg != '-' ||
      away.era != '-' ||
      home.era != '-';
  final hasHeadToHead =
      away.headToHead.isNotEmpty || home.headToHead.isNotEmpty;
  return hasRecent || hasMetrics || hasHeadToHead;
}

bool _hasMatchupComparisonData(_MatchupCompareData data) {
  if (_hasTrendData(data.away, data.home)) {
    return true;
  }
  return _hasStarterComparisonStats(data.away.starter) ||
      _hasStarterComparisonStats(data.home.starter);
}

bool _hasStarterComparisonStats(_StarterCompareData starter) {
  return starter.winsLosses != '-' ||
      starter.innings != '-' ||
      starter.era != '-' ||
      starter.whip != '-';
}

class _MatchupCompareData {
  final _TeamCompareData away;
  final _TeamCompareData home;

  const _MatchupCompareData({required this.away, required this.home});
}

class _TeamCompareData {
  final String teamId;
  final String teamName;
  final String standingText;
  final String recordText;
  final List<_RecentResultChipData> recentResults;
  final String winPct;
  final String avg;
  final String era;
  final String headToHead;
  final _StarterCompareData starter;

  const _TeamCompareData({
    required this.teamId,
    required this.teamName,
    required this.standingText,
    required this.recordText,
    required this.recentResults,
    required this.winPct,
    required this.avg,
    required this.era,
    required this.headToHead,
    required this.starter,
  });
}

class _RecentResultChipData {
  final String result;

  const _RecentResultChipData({required this.result});
}

class _StarterCompareData {
  final String name;
  final String? imageUrl;
  final String winsLosses;
  final String innings;
  final String era;
  final String whip;

  const _StarterCompareData({
    required this.name,
    required this.imageUrl,
    required this.winsLosses,
    required this.innings,
    required this.era,
    required this.whip,
  });
}

class _CompareSection extends StatelessWidget {
  final String title;
  final Widget left;
  final Widget right;

  const _CompareSection({
    required this.title,
    required this.left,
    required this.right,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 680;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              if (stacked) ...[
                left,
                const SizedBox(height: 18),
                Container(height: 1, color: AppColors.divider),
                const SizedBox(height: 18),
                right,
              ] else
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: left),
                      Container(width: 1, color: AppColors.divider),
                      Expanded(child: right),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LineupColumn extends StatelessWidget {
  final String teamId;
  final String teamName;
  final String sideLabel;
  final int season;
  final String? starterId;
  final String? starterName;
  final String? starterImageUrl;
  final List<LineupEntry> lineup;
  final List<BatterRecord> batterFallback;
  final List<PitcherRecord> pitchers;
  final RelayData? relayData;
  final Map<String, String> imageMap;
  final bool showBullpen;
  final bool isLive;
  final bool isAwayTeam;

  const _LineupColumn({
    required this.teamId,
    required this.teamName,
    required this.sideLabel,
    required this.season,
    required this.starterId,
    required this.starterName,
    required this.starterImageUrl,
    required this.lineup,
    required this.batterFallback,
    required this.pitchers,
    required this.relayData,
    required this.imageMap,
    required this.showBullpen,
    required this.isLive,
    required this.isAwayTeam,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final accent = colors.readableAccent(
      KboTeams.byId(teamId)?.primaryColor ?? colors.accent,
    );
    final baseLineup = lineup.isNotEmpty
        ? lineup.take(9).toList()
        : _lineupEntriesFromBatters(batterFallback);
    final displayedLineup = _mergeLineupWithRelaySubstitutions(
      baseLineup,
      relayData,
      isAwayTeam: isAwayTeam,
    );
    final starter = _starterPitcher(pitchers, starterName);
    final missingPitcherData = pitchers.isEmpty && displayedLineup.isNotEmpty;
    final bullpenPreview = pitchers
        .where((pitcher) => pitcher.name != (starterName ?? starter?.name))
        .toList();
    final relayBullpenNames = _relayBullpenNames(
      relayData,
      isAwayTeam: isAwayTeam,
      starterName: starterName ?? starter?.name,
      currentPitcherName: relayData?.currentAtBat?.pitcherName,
    );
    final bullpenNames = <String>[
      ...bullpenPreview.map((pitcher) => pitcher.name),
      ...relayBullpenNames.where(
        (name) => !bullpenPreview.any((pitcher) => pitcher.name == name),
      ),
    ];
    final starterDetail = starter == null
        ? ((starterName?.isNotEmpty ?? false) ? '선발 발표' : '발표 대기')
        : starter.innings.isEmpty
        ? '실시간 경기 기준 투수'
        : '${starter.innings}이닝 · 삼진 ${starter.strikeouts} · 볼넷 ${starter.walks}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TeamLogo(teamId: teamId, fallback: teamName, size: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  teamName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                sideLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '선발',
            style: TextStyle(
              fontSize: 12,
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (starterName != null || starter != null)
            _StarterRow(
              name: starterName ?? starter?.name ?? '선발 미발표',
              detail: starterDetail,
              accent: accent,
              imageUrl: _resolveStarterImageUrl(
                imageMap,
                name: starterName ?? starter?.name ?? '',
                starterId: starterId,
                starterImageUrl: starterImageUrl,
                season: season,
              ),
            )
          else if (missingPitcherData)
            const _EmptyLabel(label: 'KBO 투수 데이터 미제공')
          else
            const _EmptyLabel(label: '선발 미발표'),
          if (showBullpen) ...[
            const SizedBox(height: 12),
            _BullpenSummary(
              accent: accent,
              count: bullpenNames.length,
              hasData: !missingPitcherData || bullpenNames.isNotEmpty,
              isLive: isLive,
            ),
            const SizedBox(height: 10),
            if (bullpenNames.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _EmptyLabel(
                  label: isLive
                      ? '실시간 불펜 집계 중'
                      : missingPitcherData
                      ? '박스스코어 투수 기록 없음'
                      : '아직 불펜 등판 없음',
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int index = 0; index < bullpenNames.length; index++) ...[
                    AppMotionListItem(
                      index: index,
                      beginYOffset: 8,
                      beginScale: 0.994,
                      child: _BullpenNameRow(
                        name: bullpenNames[index],
                        accent: accent,
                        orderLabel: '${index + 1}',
                        imageUrl: _resolveImageUrl(
                          imageMap,
                          bullpenNames[index],
                        ),
                      ),
                    ),
                    if (index != bullpenNames.length - 1)
                      Divider(color: AppColors.divider, height: 14),
                  ],
                ],
              ),
          ],
          if (displayedLineup.isEmpty) ...[
            const SizedBox(height: 12),
            _EmptyLabel(label: isLive ? '실시간 타자 라인업 집계 중' : '타자 라인업 데이터 없음'),
          ],
          const SizedBox(height: 14),
          for (int index = 0; index < displayedLineup.length; index++) ...[
            AppMotionListItem(
              index: index,
              beginYOffset: 8,
              beginScale: 0.994,
              child: _LineupRow(
                entry: displayedLineup[index],
                accent: accent,
                imageUrl: _resolveLineupEntryImageUrl(
                  imageMap,
                  displayedLineup[index],
                  season: season,
                ),
              ),
            ),
            if (index != displayedLineup.length - 1)
              Divider(color: AppColors.divider, height: 14),
          ],
        ],
      ),
    );
  }

  List<LineupEntry> _lineupEntriesFromBatters(List<BatterRecord> batters) {
    return batters
        .where((batter) => batter.name.isNotEmpty)
        .take(9)
        .map(
          (batter) => LineupEntry(
            order: batter.order,
            position: batter.position,
            positionKo: batter.position,
            name: batter.name,
          ),
        )
        .toList();
  }
}

List<String> _relayBullpenNames(
  RelayData? relayData, {
  required bool isAwayTeam,
  required String? starterName,
  required String? currentPitcherName,
}) {
  if (relayData == null) {
    return const <String>[];
  }

  final targetHalf = isAwayTeam ? 'bottom' : 'top';
  final names = <String>[];
  for (final item in relayData.relayItems) {
    if (item.half != targetHalf) {
      continue;
    }
    final match = RegExp(
      r'투수\s+(.+?)\s*:\s*투수\s+(.+?)\s+\(으\)로\s+교체',
    ).firstMatch(item.text);
    final nextPitcher = match?.group(2)?.trim();
    if (nextPitcher == null || nextPitcher.isEmpty) {
      continue;
    }
    if (nextPitcher == starterName || names.contains(nextPitcher)) {
      continue;
    }
    names.add(nextPitcher);
  }

  final currentPitcher = currentPitcherName?.trim();
  if (currentPitcher != null &&
      currentPitcher.isNotEmpty &&
      currentPitcher != starterName &&
      !names.contains(currentPitcher)) {
    names.add(currentPitcher);
  }
  return names;
}

List<LineupEntry> _mergeLineupWithRelaySubstitutions(
  List<LineupEntry> lineup,
  RelayData? relayData, {
  required bool isAwayTeam,
}) {
  if (relayData == null || lineup.isEmpty) {
    return lineup;
  }

  final targetHalf = isAwayTeam ? 'top' : 'bottom';
  final merged = [...lineup];
  final items = [...relayData.relayItems]
    ..sort((a, b) => a.seqNo.compareTo(b.seqNo));

  for (final item in items) {
    if (item.half != targetHalf) {
      continue;
    }

    final pinchHit = RegExp(
      r'(?:(\d+)번타자\s+)?(.+?)\s*:\s*대타\s+(.+?)\s+\(으\)로\s+교체',
    ).firstMatch(item.text);
    final pinchRun = RegExp(
      r'(?:(\d+)루주자\s+)?(.+?)\s*:\s*대주자\s+(.+?)\s+\(으\)로\s+교체',
    ).firstMatch(item.text);
    final match = pinchHit ?? pinchRun;
    if (match == null) {
      continue;
    }

    final order = int.tryParse(match.group(1) ?? '');
    final outgoing = (match.group(2) ?? '').trim();
    final incoming = (match.group(3) ?? '').trim();
    final changeLabel = pinchHit != null ? '대타' : '대주자';
    if (incoming.isEmpty) {
      continue;
    }

    final index = order != null && order > 0
        ? merged.indexWhere((entry) => entry.order == order)
        : merged.indexWhere(
            (entry) => _normalizeName(entry.name) == _normalizeName(outgoing),
          );
    if (index == -1) {
      continue;
    }

    final current = merged[index];
    merged[index] = LineupEntry(
      order: current.order,
      position: current.position,
      positionKo: current.positionKo,
      name: incoming,
      changeLabel: changeLabel,
    );
  }

  return merged;
}

String? _resolveImageUrl(Map<String, String> imageMap, String rawName) {
  if (rawName.isEmpty) {
    return null;
  }
  if (imageMap.containsKey(rawName)) {
    return imageMap[rawName];
  }

  final normalized = _normalizeName(rawName);
  for (final entry in imageMap.entries) {
    final key = _normalizeName(entry.key);
    if (key == normalized ||
        key.contains(normalized) ||
        normalized.contains(key)) {
      return entry.value;
    }
  }
  return null;
}

String? _resolveStarterImageUrl(
  Map<String, String> imageMap, {
  required String name,
  required String? starterId,
  required String? starterImageUrl,
  required int season,
}) {
  if (starterImageUrl != null && starterImageUrl.isNotEmpty) {
    return starterImageUrl;
  }
  final mapped = _resolveImageUrl(imageMap, name);
  if (mapped != null && mapped.isNotEmpty) {
    return mapped;
  }
  return _playerImageUrl(season: season, playerId: starterId);
}

Map<String, String> _buildPlayerImageMap({
  required Map<String, String> allImageMap,
  required Iterable<PlayerProfile> teamPlayers,
  required int season,
  required RelayData? relayData,
}) {
  final imageMap = <String, String>{...allImageMap};
  for (final player in teamPlayers) {
    final imageUrl = _playerImageUrlFromProfile(player, season);
    if (player.name.isNotEmpty && imageUrl != null && imageUrl.isNotEmpty) {
      imageMap[player.name] = imageUrl;
    }
  }

  final currentAtBat = relayData?.currentAtBat;
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
  return _playerImageUrl(season: season, playerId: player.id);
}

String? _playerImageUrl({required int season, required String? playerId}) {
  final cleaned = playerId?.trim() ?? '';
  if (cleaned.isEmpty) {
    return null;
  }
  return kboPlayerImageUrl(season: season, playerId: cleaned);
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

String? _resolveLineupEntryImageUrl(
  Map<String, String> imageMap,
  LineupEntry entry, {
  required int season,
}) {
  final responseImageUrl = entry.imageUrl?.trim();
  if (responseImageUrl != null && responseImageUrl.isNotEmpty) {
    return responseImageUrl;
  }
  final idImageUrl = _playerImageUrl(season: season, playerId: entry.playerId);
  if (idImageUrl != null && idImageUrl.isNotEmpty) {
    return idImageUrl;
  }
  return _resolveImageUrl(imageMap, entry.name);
}

String _normalizeName(String value) {
  return value
      .replaceAll(RegExp(r'\([^)]*\)'), '')
      .replaceAll(RegExp(r'\[[^\]]*\]'), '')
      .replaceAll(RegExp(r'선발|투수|등판|교체'), '')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('·', '')
      .replaceAll('ㆍ', '')
      .replaceAll('.', '')
      .replaceAll(RegExp(r'[^0-9A-Za-z가-힣]'), '')
      .trim();
}

PitcherRecord? _starterPitcher(
  List<PitcherRecord> pitchers,
  String? starterName,
) {
  if (pitchers.isEmpty) {
    return null;
  }
  if (starterName == null || starterName.isEmpty) {
    return pitchers.first;
  }
  final normalizedStarter = _normalizeName(starterName);
  return pitchers
          .where((pitcher) => _normalizeName(pitcher.name) == normalizedStarter)
          .firstOrNull ??
      pitchers.first;
}

class _BullpenSummary extends StatelessWidget {
  final Color accent;
  final int count;
  final bool hasData;
  final bool isLive;

  const _BullpenSummary({
    required this.accent,
    required this.count,
    required this.hasData,
    required this.isLive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count명',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Spacer(),
        ],
      ),
    );
  }
}

class _BullpenNameRow extends StatelessWidget {
  final String name;
  final Color accent;
  final String orderLabel;
  final String? imageUrl;

  const _BullpenNameRow({
    required this.name,
    required this.accent,
    required this.orderLabel,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LineupAvatar(
          imageUrl: imageUrl,
          fallbackLabel: name,
          accent: accent,
          badgeLabel: orderLabel,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _StarterRow extends StatelessWidget {
  final String name;
  final String detail;
  final Color accent;
  final String? imageUrl;

  const _StarterRow({
    required this.name,
    required this.detail,
    required this.accent,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          _LineupAvatar(
            imageUrl: imageUrl,
            fallbackLabel: name,
            accent: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
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

class _LineupRow extends StatelessWidget {
  final LineupEntry entry;
  final Color accent;
  final String? imageUrl;

  const _LineupRow({
    required this.entry,
    required this.accent,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final positionLabel = entry.positionKo.isNotEmpty
        ? entry.positionKo
        : entry.position;
    final detailParts = [
      positionLabel,
      if (entry.position.isNotEmpty && entry.position != positionLabel)
        entry.position,
      if ((entry.statValue ?? '').isNotEmpty) '지표 ${entry.statValue}',
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 30,
          child: Text(
            '${entry.order}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ),
        const SizedBox(width: 10),
        _LineupAvatar(
          imageUrl: imageUrl,
          fallbackLabel: entry.name,
          accent: accent,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (entry.changeLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        entry.changeLabel!,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                detailParts.join(' · '),
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LineupAvatar extends StatelessWidget {
  final String? imageUrl;
  final String fallbackLabel;
  final Color accent;
  final String? badgeLabel;

  const _LineupAvatar({
    required this.imageUrl,
    required this.fallbackLabel,
    required this.accent,
    this.badgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      final cacheSize = kboPlayerImageCacheSize(42);
      return Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: imageUrl!,
              httpHeaders: kboPlayerImageHeaders,
              cacheManager: kboPlayerImageCacheManager,
              width: 42,
              height: 42,
              memCacheWidth: cacheSize,
              memCacheHeight: cacheSize,
              maxWidthDiskCache: cacheSize,
              maxHeightDiskCache: cacheSize,
              fit: BoxFit.cover,
              placeholder: (_, _) => _fallback(),
              errorWidget: (_, _, _) => _fallback(),
            ),
          ),
          if (badgeLabel != null) _orderBadge(context),
        ],
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [_fallback(), if (badgeLabel != null) _orderBadge(context)],
    );
  }

  Widget _orderBadge(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final badgeFill =
        accent.computeLuminance() > 0.75 &&
            colors.background.computeLuminance() < 0.3
        ? colors.card
        : accent;
    return Positioned(
      right: -4,
      bottom: -4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: badgeFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.background, width: 1.5),
        ),
        child: Text(
          badgeLabel!,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: colors.readableForegroundOn(badgeFill),
          ),
        ),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        fallbackLabel.isEmpty ? '?' : fallbackLabel.substring(0, 1),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _EmptyLabel extends StatelessWidget {
  final String label;

  const _EmptyLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(fontSize: 12, color: AppColors.textSupporting),
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
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return KboTeamLogoImage(
      teamId: teamId,
      fallback: fallback,
      size: size,
      padding: size <= 30 ? 1.5 : 2,
    );
  }
}
