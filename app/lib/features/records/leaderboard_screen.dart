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

class LeaderboardScreen extends ConsumerWidget {
  final int season;
  final LeaderboardMetric metric;

  const LeaderboardScreen({
    super.key,
    required this.season,
    required this.metric,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(leaderboardProvider('$season|${metric.key}'));

    return Scaffold(
      appBar: AppBar(title: Text(metric.title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$season 시즌 · ${metric.shortLabel}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              if (!metric.supportedByOfficialSource)
                _unsupportedMetricCard(metric: metric)
              else
                Expanded(
                  child: asyncValue.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: AppColors.live),
                    ),
                    error: (error, _) => Center(
                      child: Text(
                        '$error',
                        style: const TextStyle(color: AppColors.textDisabled),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    data: (leaders) {
                      if (leaders.isEmpty) {
                        return const Center(
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
                            key: ValueKey(
                              'leader-${metric.key}-${leader.playerId}',
                            ),
                            index: index,
                            child: _leaderRow(
                              context,
                              leader: leader,
                              season: season,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _leaderRow(
    BuildContext context, {
    required RecordLeader leader,
    required int season,
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
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${leader.rank}',
                style: const TextStyle(
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
                    style: const TextStyle(
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
                          style: const TextStyle(
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
            Text(
              leader.value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
        borderRadius: BorderRadius.circular(18),
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
            style: const TextStyle(
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
      child: const Text(
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
