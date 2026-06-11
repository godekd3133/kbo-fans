import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/team_data.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/game.dart';
import '../../../data/models/boxscore.dart';
import '../../../data/models/player.dart';
import '../../../data/models/relay.dart';
import '../../../data/models/schedule.dart';
import '../../../data/models/team_stats.dart';
import '../../../data/providers.dart';

const _kboImageHeaders = {
  'Referer': 'https://www.koreabaseball.com/',
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
};
const _kboPersonImageBase =
    'https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/person/middle';

class LineupTab extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    if (gameStatus == GameStatus.scheduled) {
      return _buildUnavailableState('경기 시작 후 라인업이 공개됩니다');
    }
    if (gameStatus == GameStatus.cancelled) {
      return _buildUnavailableState('취소된 경기는 라인업이 없습니다');
    }

    final gameLineupAsync = ref.watch(gameLineupProvider(gameId));
    final season = DateTime.now().year;
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
                child: gameLineupAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.live),
                    ),
                  ),
                  error: (error, _) => Text(
                    '라인업 데이터 로딩 실패: $error',
                    style: const TextStyle(color: AppColors.textDisabled),
                  ),
                  data: (gameLineup) {
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
                    final compareData = _buildMatchupCompareData(
                      awayTeamId: awayTeamId,
                      awayName: awayName,
                      homeTeamId: homeTeamId,
                      homeName: homeName,
                      standings: const [],
                      scheduleDays: const [],
                      awayTeamStats: null,
                      homeTeamStats: null,
                      awayStarter: null,
                      homeStarter: null,
                      awayStarterName: gameLineup.away.starterName,
                      homeStarterName: gameLineup.home.starterName,
                      awayStarterImageUrl: _resolveStarterImageUrl(
                        awayImageMap,
                        name: gameLineup.away.starterName ?? '',
                        starterId: gameLineup.away.starterId,
                        starterImageUrl: gameLineup.away.starterImageUrl,
                        season: season,
                      ),
                      homeStarterImageUrl: _resolveStarterImageUrl(
                        homeImageMap,
                        name: gameLineup.home.starterName ?? '',
                        starterId: gameLineup.home.starterId,
                        starterImageUrl: gameLineup.home.starterImageUrl,
                        season: season,
                      ),
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MatchupCompareSection(
                          data: compareData,
                          awayAccent:
                              KboTeams.byId(awayTeamId)?.primaryColor ??
                              AppColors.live,
                          homeAccent:
                              KboTeams.byId(homeTeamId)?.primaryColor ??
                              AppColors.accent,
                        ),
                        const SizedBox(height: 16),
                        _CompareSection(
                          title: '선발 라인업',
                          left: _LineupColumn(
                            teamId: awayTeamId,
                            teamName: awayName,
                            sideLabel: 'AWAY',
                            season: season,
                            starterId: gameLineup.away.starterId,
                            starterName: gameLineup.away.starterName,
                            starterImageUrl: gameLineup.away.starterImageUrl,
                            lineup: gameLineup.away.lineup,
                            batterFallback: const <BatterRecord>[],
                            pitchers: const <PitcherRecord>[],
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
                            starterImageUrl: gameLineup.home.starterImageUrl,
                            lineup: gameLineup.home.lineup,
                            batterFallback: const <BatterRecord>[],
                            pitchers: const <PitcherRecord>[],
                            relayData: null,
                            imageMap: homeImageMap,
                            showBullpen: false,
                            isLive: gameStatus == GameStatus.live,
                            isAwayTeam: false,
                          ),
                        ),
                      ],
                    );
                  },
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
          Icon(Icons.groups_2_outlined, size: 48, color: AppColors.divider),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.textDisabled)),
        ],
      ),
    );
  }
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
        winsLosses: awayStarter?.decision ?? '-',
        innings: awayStarter?.innings ?? '-',
        era: awayStarter == null
            ? '-'
            : awayStarter.earnedRuns.toStringAsFixed(2),
        whip: awayStarter == null ? '-' : _pitcherWhip(awayStarter),
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
        winsLosses: homeStarter?.decision ?? '-',
        innings: homeStarter?.innings ?? '-',
        era: homeStarter == null
            ? '-'
            : homeStarter.earnedRuns.toStringAsFixed(2),
        whip: homeStarter == null ? '-' : _pitcherWhip(homeStarter),
      ),
    ),
  );
}

String _pitcherWhip(PitcherRecord pitcher) {
  final outs = _inningsTextToOuts(pitcher.innings);
  if (outs <= 0) {
    return '0.00';
  }
  final innings = outs / 3;
  final whip = (pitcher.hits + pitcher.walks) / innings;
  return whip.toStringAsFixed(2);
}

int _inningsTextToOuts(String innings) {
  if (innings.isEmpty) {
    return 0;
  }
  final parts = innings.split('.');
  final whole = int.tryParse(parts.first) ?? 0;
  final fraction = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return whole * 3 + fraction;
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _MatchupHeader(data: data),
          const SizedBox(height: 22),
          _RecentTrendSection(
            away: data.away,
            home: data.home,
            awayAccent: awayAccent,
            homeAccent: homeAccent,
          ),
          const SizedBox(height: 28),
          _StarterDuelSection(
            away: data.away.starter,
            home: data.home.starter,
            awayAccent: awayAccent,
            homeAccent: homeAccent,
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
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (team.recordText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              team.recordText,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: teamBlock(data.away, alignEnd: true)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            'VS',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              color: Color(0xFF555555),
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
    if (!hasRecent && !hasMetrics && !hasHeadToHead) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        const Divider(color: AppColors.divider, height: 1),
        const SizedBox(height: 20),
        const Text(
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
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Padding(
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
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
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
    final background = switch (result) {
      '승' => const Color(0xFF18C8F7),
      '패' => const Color(0xFFD41438),
      _ => const Color(0xFF585858),
    };
    final labelColor = result == '무'
        ? AppColors.textSecondary
        : AppColors.background;
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
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
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
    return Column(
      children: [
        const Divider(color: AppColors.divider, height: 1),
        const SizedBox(height: 26),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _StarterHeroCard(data: away, accent: awayAccent),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 34, 18, 0),
              child: Column(
                children: [
                  Text(
                    '선발',
                    style: TextStyle(
                      fontSize: 18,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'VS',
                    style: TextStyle(
                      fontSize: 56,
                      color: Color(0xFF555555),
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
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: _StarterStatColumn(data: away, alignEnd: true)),
            const SizedBox(
              width: 116,
              child: Column(
                children: [
                  _CenterStatLabel('승패'),
                  SizedBox(height: 18),
                  _CenterStatLabel('이닝'),
                  SizedBox(height: 18),
                  _CenterStatLabel('평균자책'),
                  SizedBox(height: 18),
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
          height: 148,
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
                          httpHeaders: _kboImageHeaders,
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity,
                          memCacheWidth: 720,
                          memCacheHeight: 660,
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
        const SizedBox(height: 12),
        Text(
          data.name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
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
      fontSize: 17,
      fontWeight: FontWeight.w700,
    );
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(data.winsLosses, style: style),
        const SizedBox(height: 14),
        Text(data.innings, style: style),
        const SizedBox(height: 14),
        Text(data.era, style: style),
        const SizedBox(height: 14),
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
      style: const TextStyle(fontSize: 16, color: AppColors.textSecondary),
    );
  }
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
    final accent = KboTeams.byId(teamId)?.primaryColor ?? AppColors.accent;
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
                    _BullpenNameRow(
                      name: bullpenNames[index],
                      accent: accent,
                      orderLabel: '${index + 1}',
                      imageUrl: _resolveImageUrl(imageMap, bullpenNames[index]),
                    ),
                    if (index != bullpenNames.length - 1)
                      const Divider(color: AppColors.divider, height: 14),
                  ],
                ],
              ),
          ],
          if (displayedLineup.isEmpty) ...[
            const SizedBox(height: 12),
            _EmptyLabel(label: isLive ? '실시간 타자 라인업 집계 중' : '타자 라인업 데이터 없음'),
          ],
          const SizedBox(height: 14),
          for (final entry in displayedLineup) ...[
            _LineupRow(
              entry: entry,
              accent: accent,
              imageUrl: _resolveImageUrl(imageMap, entry.name),
            ),
            if (entry != displayedLineup.last)
              const Divider(color: AppColors.divider, height: 14),
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
  return '$_kboPersonImageBase/$season/$cleaned.jpg';
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
  return pitchers.where((pitcher) => pitcher.name == starterName).firstOrNull ??
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
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
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
      return Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: imageUrl!,
              httpHeaders: _kboImageHeaders,
              width: 42,
              height: 42,
              memCacheWidth: 126,
              memCacheHeight: 126,
              fit: BoxFit.cover,
              placeholder: (_, _) => _fallback(),
              errorWidget: (_, _, _) => _fallback(),
            ),
          ),
          if (badgeLabel != null) _orderBadge(),
        ],
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [_fallback(), if (badgeLabel != null) _orderBadge()],
    );
  }

  Widget _orderBadge() {
    return Positioned(
      right: -4,
      bottom: -4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.background, width: 1.5),
        ),
        child: Text(
          badgeLabel!,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
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
      style: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
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
    final team = KboTeams.byId(teamId);
    final cacheSize = (size * 3).round();
    return CachedNetworkImage(
      imageUrl: team?.logoUrl ?? '',
      httpHeaders: _kboImageHeaders,
      width: size,
      height: size,
      memCacheWidth: cacheSize,
      memCacheHeight: cacheSize,
      placeholder: (_, _) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.cardSub,
          shape: BoxShape.circle,
        ),
      ),
      errorWidget: (_, _, _) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.cardSub,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          fallback.isEmpty ? '?' : fallback.substring(0, 1).toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
