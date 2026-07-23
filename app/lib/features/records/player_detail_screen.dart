import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/kbo_player_image_cache.dart';
import '../../core/widgets/app_motion.dart';
import '../../data/models/player.dart';
import '../../data/providers.dart';

class PlayerDetailScreen extends ConsumerWidget {
  final String playerId;
  final int season;

  const PlayerDetailScreen({
    super.key,
    required this.playerId,
    required this.season,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerAsync = ref.watch(playerDetailProvider('$playerId|$season'));
    Future<void> refreshPlayer() async {
      ref.invalidate(playerDetailProvider('$playerId|$season'));
      await ref.read(playerDetailProvider('$playerId|$season').future);
    }

    Future<void> retryPlayer() async {
      try {
        await refreshPlayer();
      } catch (_) {
        // Provider의 오류 상태가 화면에 유지되므로 추가 예외 UI는 필요하지 않다.
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text('선수 프로필 · $season')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refreshPlayer,
          color: AppColors.live,
          child: AppMotionSwitcher(
            child: playerAsync.when(
              loading: () => const KeyedSubtree(
                key: ValueKey('player-detail-loading'),
                child: _PlayerDetailLoading(),
              ),
              error: (_, stackTrace) => KeyedSubtree(
                key: ValueKey('player-detail-error'),
                child: _PlayerDetailError(
                  onRetry: () => unawaited(retryPlayer()),
                  onRecords: () => context.go('/records'),
                ),
              ),
              data: (player) => KeyedSubtree(
                key: ValueKey('player-detail-data-${player.id}'),
                child: _buildBody(player),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(PlayerProfile player) {
    final team = KboTeams.byId(player.teamId);
    final photoUrl = playerProfileImageUrl(player, season: season);
    final recentGames = player.recentGames.take(5).toList();
    final headlineMetric = _metricFromStat(
      player.headlineStat,
      fallbackLabel: '대표 기록',
    );
    final secondaryMetric = _metricFromStat(
      player.secondaryStat,
      fallbackLabel: '보조 지표',
    );
    final primaryMetrics = <_PlayerMetric>[?headlineMetric, ?secondaryMetric];
    final primaryMetricKeys = primaryMetrics.map(_metricIdentity).toSet();
    final seasonMetrics = player.seasonStats
        .map((stat) => _metricFromStat(stat, fallbackLabel: '기록'))
        .whereType<_PlayerMetric>()
        .where((metric) => !primaryMetricKeys.contains(_metricIdentity(metric)))
        .toList();
    final hasKeyStats = primaryMetrics.isNotEmpty || seasonMetrics.isNotEmpty;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 88,
                    height: 112,
                    decoration: BoxDecoration(
                      color:
                          team?.primaryColor.withValues(alpha: 0.14) ??
                          AppColors.cardSub,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: photoUrl != null && photoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: photoUrl,
                            httpHeaders: kboPlayerImageHeaders,
                            cacheManager: kboPlayerImageCacheManager,
                            fit: BoxFit.cover,
                            memCacheWidth: kboPlayerImageCacheSize(112),
                            memCacheHeight: kboPlayerImageCacheSize(112),
                            maxWidthDiskCache: kboPlayerImageCacheSize(112),
                            maxHeightDiskCache: kboPlayerImageCacheSize(112),
                            errorWidget: (_, _, _) =>
                                _photoFallback(player.number),
                          )
                        : _photoFallback(player.number),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          player.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${team?.name ?? player.teamId} · ${player.roleLabel}',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill(player.position),
                  _pill(player.handedness),
                  _pill(player.heightWeight),
                  _pill(player.birthDate),
                  if (player.career.isNotEmpty) _pill(player.career),
                ],
              ),
              if (player.statusNote != null) ...[
                const SizedBox(height: 14),
                Text(
                  player.statusNote!,
                  style: TextStyle(
                    fontSize: 13,
                    color: player.status == PlayerAvailabilityStatus.injured
                        ? AppColors.live
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (hasKeyStats) ...[
          const SizedBox(height: 18),
          _section(
            title: '주요 기록',
            child: _PlayerKeyStats(
              primaryMetrics: primaryMetrics,
              seasonMetrics: seasonMetrics,
            ),
          ),
        ],
        const SizedBox(height: 18),
        _section(
          title: '최근 5경기',
          child: recentGames.isEmpty
              ? Text(
                  '최근 5경기 기록이 없습니다',
                  style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
                )
              : Column(
                  children: [
                    for (final game in recentGames) _recentGameRow(game),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        _section(
          title: '노트',
          child: player.highlights.isEmpty
              ? Text(
                  '표시할 메모가 없습니다',
                  style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
                )
              : Column(
                  children: [
                    for (final item in player.highlights) _statRow('메모', item),
                  ],
                ),
        ),
      ],
    );
  }

  _PlayerMetric? _metricFromStat(
    String rawValue, {
    required String fallbackLabel,
  }) {
    final normalized = rawValue.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (_isMissingMetricValue(normalized)) {
      return null;
    }

    final winLoss = RegExp(r'^(.+?)승\s+(.+?)패$').firstMatch(normalized);
    if (winLoss != null) {
      final wins = winLoss.group(1)?.trim() ?? '';
      final losses = winLoss.group(2)?.trim() ?? '';
      if (!_isMissingMetricValue(wins) && !_isMissingMetricValue(losses)) {
        return _PlayerMetric(label: '승-패', value: '$wins승 $losses패');
      }
    }

    final homeRuns = RegExp(r'^(.+?)홈런$').firstMatch(normalized);
    if (homeRuns != null) {
      final value = homeRuns.group(1)?.trim() ?? '';
      if (!_isMissingMetricValue(value)) {
        return _PlayerMetric(label: '홈런', value: value);
      }
    }

    final labeledMetric = RegExp(
      r'^([A-Za-z][A-Za-z0-9]*|타율|출루율|장타율|평균자책점)\s+(.+)$',
    ).firstMatch(normalized);
    if (labeledMetric != null) {
      final rawLabel = labeledMetric.group(1)?.trim() ?? '';
      final value = labeledMetric.group(2)?.trim() ?? '';
      if (!_isMissingMetricValue(value)) {
        return _PlayerMetric(
          label: _displayMetricLabel(rawLabel),
          value: value,
        );
      }
      return null;
    }

    return _PlayerMetric(label: fallbackLabel, value: normalized);
  }

  String _displayMetricLabel(String rawLabel) {
    return switch (rawLabel.toUpperCase()) {
      'AVG' => '타율',
      'G' => '경기',
      'H' => '안타',
      'HR' => '홈런',
      'RBI' => '타점',
      'SB' => '도루',
      'OBP' => '출루율',
      'SLG' => '장타율',
      'W' => '승',
      'L' => '패',
      'SV' => '세이브',
      'HLD' => '홀드',
      'IP' => '이닝',
      'SO' => '탈삼진',
      _ => rawLabel,
    };
  }

  bool _isMissingMetricValue(String value) {
    final normalized = value.trim().toUpperCase();
    return normalized.isEmpty ||
        normalized == '-' ||
        normalized == '--' ||
        normalized == 'N/A' ||
        normalized == 'NULL' ||
        normalized == '기록 없음' ||
        normalized == '정보 없음';
  }

  String _metricIdentity(_PlayerMetric metric) {
    return '${metric.label}\u0000${metric.value}';
  }

  Widget _section({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _recentGameRow(PlayerRecentGame game) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardSub,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 58,
              padding: const EdgeInsets.symmetric(vertical: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                game.date,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'vs ${game.opponent}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    game.summary,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.35,
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

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _photoFallback(int number) {
    return Container(
      color: AppColors.cardSub,
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _PlayerMetric {
  final String label;
  final String value;

  const _PlayerMetric({required this.label, required this.value});
}

class _PlayerKeyStats extends StatelessWidget {
  final List<_PlayerMetric> primaryMetrics;
  final List<_PlayerMetric> seasonMetrics;

  const _PlayerKeyStats({
    required this.primaryMetrics,
    required this.seasonMetrics,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (primaryMetrics.isNotEmpty)
          _ResponsiveMetricGrid(
            metrics: primaryMetrics,
            keyPrefix: 'player-primary-metric',
            emphasized: true,
          ),
        if (primaryMetrics.isNotEmpty && seasonMetrics.isNotEmpty)
          const SizedBox(height: 16),
        if (seasonMetrics.isNotEmpty) ...[
          Text(
            '시즌 기록',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          _ResponsiveMetricGrid(
            metrics: seasonMetrics,
            keyPrefix: 'player-season-metric',
          ),
        ],
      ],
    );
  }
}

class _ResponsiveMetricGrid extends StatelessWidget {
  final List<_PlayerMetric> metrics;
  final String keyPrefix;
  final bool emphasized;

  const _ResponsiveMetricGrid({
    required this.metrics,
    required this.keyPrefix,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final usesSingleColumn = constraints.maxWidth < 300 || textScale >= 1.4;
        final cardWidth = usesSingleColumn
            ? constraints.maxWidth
            : (constraints.maxWidth - 8) / 2;

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var index = 0; index < metrics.length; index++)
              SizedBox(
                width: cardWidth,
                child: _PlayerMetricCard(
                  key: ValueKey('$keyPrefix-$index'),
                  metric: metrics[index],
                  emphasized: emphasized,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PlayerMetricCard extends StatelessWidget {
  final _PlayerMetric metric;
  final bool emphasized;

  const _PlayerMetricCard({
    super.key,
    required this.metric,
    required this.emphasized,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '${metric.label}, ${metric.value}',
      excludeSemantics: true,
      child: Container(
        constraints: BoxConstraints(minHeight: emphasized ? 82 : 68),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.cardSub,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: emphasized
                ? AppColors.accent.withValues(alpha: 0.38)
                : AppColors.divider,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              metric.label,
              style: TextStyle(
                fontSize: 11,
                height: 1.25,
                color: emphasized ? AppColors.accent : AppColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              metric.value,
              softWrap: true,
              style: TextStyle(
                fontSize: emphasized ? 17 : 15,
                height: 1.25,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerDetailLoading extends StatelessWidget {
  const _PlayerDetailLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: 420,
          child: Center(
            child: CircularProgressIndicator(color: AppColors.live),
          ),
        ),
      ],
    );
  }
}

class _PlayerDetailError extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onRecords;

  const _PlayerDetailError({required this.onRetry, required this.onRecords});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        SizedBox(
          height: 420,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.person_search_outlined,
                  size: 40,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 16),
                const Text(
                  '선수 정보를 불러올 수 없습니다',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  '네트워크 연결을 확인한 뒤 다시 시도해 주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('다시 시도'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onRecords,
                  icon: const Icon(Icons.list_alt_outlined),
                  label: const Text('기록실로'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
