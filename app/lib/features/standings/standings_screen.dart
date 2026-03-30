import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/schedule.dart';
import '../../data/providers.dart';

class StandingsScreen extends ConsumerStatefulWidget {
  const StandingsScreen({super.key});

  @override
  ConsumerState<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends ConsumerState<StandingsScreen> {
  String? _myTeamId;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      setState(() => _myTeamId = prefs.getString('myTeam'));
    });
  }

  @override
  Widget build(BuildContext context) {
    final season = DateTime.now().year;
    final standingsAsync = ref.watch(standingsProvider(season));

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('📊 $season 정규시즌 순위', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20, color: AppColors.textDisabled),
                    onPressed: () => ref.invalidate(standingsProvider(season)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildHeaderRow(),
            ),
            const Divider(color: AppColors.divider, height: 1, indent: 16, endIndent: 16),
            Expanded(
              child: standingsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.live)),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('순위를 불러올 수 없습니다', style: TextStyle(color: AppColors.textDisabled)),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref.invalidate(standingsProvider(season)),
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
                data: (standings) => _buildList(standings),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  '마지막 업데이트: ${DateFormat('yyyy.MM.dd HH:mm').format(DateTime.now())}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<TeamStanding> standings) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(standingsProvider(DateTime.now().year));
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: standings.length,
        itemBuilder: (context, index) {
          final s = standings[index];
          final isMyTeam = s.teamId == _myTeamId;
          final team = KboTeams.byId(s.teamId);
          final teamColor = team?.primaryColor ?? AppColors.live;

          return Container(
            height: 48,
            decoration: BoxDecoration(
              color: isMyTeam
                  ? teamColor.withValues(alpha: 0.1)
                  : (index.isOdd ? AppColors.card : Colors.transparent),
              border: isMyTeam ? Border(left: BorderSide(color: teamColor, width: 4)) : null,
            ),
            child: Row(
              children: [
                SizedBox(width: 32, child: Center(child: Text('${s.rank}', style: const TextStyle(fontSize: 14)))),
                if (isMyTeam)
                  Padding(padding: const EdgeInsets.only(right: 4), child: Text('★', style: TextStyle(fontSize: 12, color: teamColor))),
                CachedNetworkImage(
                  imageUrl: team?.logoUrl ?? '', width: 24, height: 24,
                  placeholder: (_, _) => const SizedBox(width: 24, height: 24),
                  errorWidget: (_, _, _) => Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(color: AppColors.cardSub, shape: BoxShape.circle),
                    child: Center(child: Text(team?.shortName ?? '', style: const TextStyle(fontSize: 8, color: AppColors.textSecondary))),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(s.teamName, style: const TextStyle(fontSize: 14))),
                SizedBox(width: 32, child: Center(child: Text('${s.wins}', style: const TextStyle(fontSize: 14)))),
                SizedBox(width: 32, child: Center(child: Text('${s.losses}', style: const TextStyle(fontSize: 14)))),
                SizedBox(width: 28, child: Center(child: Text('${s.draws}', style: const TextStyle(fontSize: 14)))),
                SizedBox(width: 48, child: Center(child: Text(s.pct, style: const TextStyle(fontSize: 14)))),
                SizedBox(width: 28, child: Center(child: Text(s.gb, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)))),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderRow() {
    const style = TextStyle(fontSize: 12, color: AppColors.textDisabled);
    return const SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(width: 32, child: Center(child: Text('순위', style: style))),
          Expanded(child: Padding(padding: EdgeInsets.only(left: 36), child: Text('팀', style: style))),
          SizedBox(width: 32, child: Center(child: Text('승', style: style))),
          SizedBox(width: 32, child: Center(child: Text('패', style: style))),
          SizedBox(width: 28, child: Center(child: Text('무', style: style))),
          SizedBox(width: 48, child: Center(child: Text('승률', style: style))),
          SizedBox(width: 28, child: Center(child: Text('차', style: style))),
        ],
      ),
    );
  }
}
