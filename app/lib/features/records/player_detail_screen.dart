import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
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
              error: (_, stackTrace) => const KeyedSubtree(
                key: ValueKey('player-detail-error'),
                child: _PlayerDetailError(),
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
                            fit: BoxFit.cover,
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
        const SizedBox(height: 18),
        _section(
          title: '주요 기록',
          child: Column(
            children: [
              _statRow('헤드라인', player.headlineStat),
              _statRow('현재 상태', player.secondaryStat),
              for (final stat in player.seasonStats) _statRow('시즌', stat),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _section(
          title: '최근 기록',
          child: player.recentGames.isEmpty
              ? const Text(
                  '최근 기록이 없습니다',
                  style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
                )
              : Column(
                  children: [
                    for (final game in player.recentGames)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.cardSub,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 54,
                                child: Text(
                                  game.date,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textDisabled,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      game.opponent,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      game.summary,
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
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        _section(
          title: '노트',
          child: player.highlights.isEmpty
              ? const Text(
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
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textDisabled,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
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
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _photoFallback(int number) {
    return Container(
      color: AppColors.cardSub,
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
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
      children: const [
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
  const _PlayerDetailError();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 420, child: Center(child: Text('선수 정보를 불러올 수 없습니다'))),
      ],
    );
  }
}
