import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/kbo_team_logo_image.dart';
import '../../data/models/records_overview.dart';
import '../../data/providers.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  final int season;
  final LeaderboardMetric metric;

  const LeaderboardScreen({
    super.key,
    required this.season,
    required this.metric,
  });

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  late LeaderboardPlayerGroup _selectedGroup;
  late LeaderboardMetric _selectedMetric;

  @override
  void initState() {
    super.initState();
    _applyInitialMetric(widget.metric);
  }

  @override
  void didUpdateWidget(covariant LeaderboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metric != widget.metric) {
      _applyInitialMetric(widget.metric);
    }
  }

  void _applyInitialMetric(LeaderboardMetric metric) {
    _selectedGroup = metric.playerGroup;
    _selectedMetric = _selectedGroup.metrics.contains(metric)
        ? metric
        : _selectedGroup.defaultMetric;
  }

  @override
  Widget build(BuildContext context) {
    AppColors.sync(AppTheme.colorsOf(context));
    final asyncValue = ref.watch(
      leaderboardProvider('${widget.season}|${_selectedMetric.key}'),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('리그 리더보드')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.season} 시즌 · ${_selectedGroup.label} 지표',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
              _groupSegment(),
              const SizedBox(height: 10),
              _metricSelector(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedMetric.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _sourceBadge(_selectedMetric),
                ],
              ),
              const SizedBox(height: 12),
              if (!_selectedMetric.supportedByOfficialSource)
                Expanded(child: _unsupportedMetricCard(metric: _selectedMetric))
              else
                Expanded(
                  child: AppMotionSwitcher(
                    child: KeyedSubtree(
                      key: ValueKey('leaderboard-${_selectedMetric.key}'),
                      child: asyncValue.when(
                        loading: () => Center(
                          child: CircularProgressIndicator(
                            color: AppColors.live,
                          ),
                        ),
                        error: (error, _) => Center(
                          child: Text(
                            '$error',
                            style: TextStyle(color: AppColors.textDisabled),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        data: (leaders) => _leaderList(leaders),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupSegment() {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          for (final group in LeaderboardPlayerGroup.values)
            Expanded(child: _groupButton(group)),
        ],
      ),
    );
  }

  Widget _groupButton(LeaderboardPlayerGroup group) {
    final selected = _selectedGroup == group;
    return AppPressable(
      onTap: selected ? null : () => _selectGroup(group),
      pressedScale: 0.98,
      child: AnimatedContainer(
        key: ValueKey('leaderboard-group-${group.name}'),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          group.label,
          style: TextStyle(
            fontSize: 14,
            color: selected ? AppColors.background : AppColors.textSecondary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  void _selectGroup(LeaderboardPlayerGroup group) {
    setState(() {
      _selectedGroup = group;
      if (!group.metrics.contains(_selectedMetric)) {
        _selectedMetric = group.defaultMetric;
      }
    });
  }

  Widget _metricSelector() {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedGroup.metrics.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final metric = _selectedGroup.metrics[index];
          return _metricChip(metric);
        },
      ),
    );
  }

  Widget _metricChip(LeaderboardMetric metric) {
    final selected = _selectedMetric == metric;
    return AppPressable(
      onTap: selected ? null : () => setState(() => _selectedMetric = metric),
      pressedScale: 0.97,
      child: AnimatedContainer(
        key: ValueKey('leaderboard-metric-${metric.key}'),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.live.withValues(alpha: 0.14)
              : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.live : AppColors.divider,
          ),
        ),
        child: Text(
          metric.shortLabel,
          style: TextStyle(
            fontSize: 13,
            color: selected ? AppColors.live : AppColors.textSecondary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _sourceBadge(LeaderboardMetric metric) {
    final official = metric.supportedByOfficialSource;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: (official ? AppColors.positive : AppColors.textDisabled)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        official ? '공식' : '미지원',
        style: TextStyle(
          fontSize: 11,
          color: official ? AppColors.positive : AppColors.textSecondary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _leaderList(List<RecordLeader> leaders) {
    if (leaders.isEmpty) {
      return Center(
        child: Text(
          '표시할 리더보드 데이터가 없습니다',
          style: TextStyle(color: AppColors.textDisabled),
        ),
      );
    }
    return ListView.separated(
      itemCount: leaders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final leader = leaders[index];
        return AppMotionListItem(
          key: ValueKey('leader-${_selectedMetric.key}-${leader.playerId}'),
          index: index,
          child: _leaderRow(
            context,
            leader: leader,
            season: widget.season,
            metric: _selectedMetric,
          ),
        );
      },
    );
  }

  Widget _leaderRow(
    BuildContext context, {
    required RecordLeader leader,
    required int season,
    required LeaderboardMetric metric,
  }) {
    final team = KboTeams.byId(leader.teamId);
    final imageUrl = kboPlayerImageUrl(
      season: season,
      playerId: leader.playerId,
    );

    return AppPressable(
      onTap: leader.isRetired
          ? null
          : () => context.push(
              '/records/player/${leader.playerId}?season=$season',
            ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${leader.rank}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ClipOval(
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: 40,
                height: 40,
                memCacheWidth: 120,
                memCacheHeight: 120,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Container(
                  width: 40,
                  height: 40,
                  color: AppColors.cardSub,
                  alignment: Alignment.center,
                  child: Text(
                    leader.name.isEmpty ? '?' : leader.name.substring(0, 1),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  if (team != null) ...[
                    KboTeamLogoImage(
                      teamId: team.id,
                      fallback: team.shortName,
                      size: 26,
                      padding: 0,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                leader.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (leader.isRetired) ...[
                              const SizedBox(width: 6),
                              _retiredBadge(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          team?.name ?? leader.teamId,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  leader.value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  metric.shortLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textDisabled,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _unsupportedMetricCard({required LeaderboardMetric metric}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            metric == LeaderboardMetric.war
                ? '현재 KBO 공식 소스 기준으로는 WAR 리더보드를 같은 방식으로 공개하지 않아 아직 연결하지 못했습니다.'
                : '현재 이 지표는 사용할 수 없습니다.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _retiredBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.textDisabled.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '은퇴',
        style: TextStyle(
          fontSize: 10,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
