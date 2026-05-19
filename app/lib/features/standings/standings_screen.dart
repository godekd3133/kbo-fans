import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../data/api/api_client.dart';
import '../../data/providers.dart';

class StandingsScreen extends ConsumerStatefulWidget {
  const StandingsScreen({super.key});

  @override
  ConsumerState<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends ConsumerState<StandingsScreen> {
  late int _selectedSeason;

  @override
  void initState() {
    super.initState();
    _selectedSeason = DateTime.now().year;
  }

  @override
  Widget build(BuildContext context) {
    final myTeamId = ref.watch(myTeamProvider);
    final standingsAsync = ref.watch(standingsProvider(_selectedSeason));

    return Scaffold(
      body: SafeArea(
        child: AppPageFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: const Text(
                        '정규시즌 순위표',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _seasonDropdown(),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.refresh,
                        size: 20,
                        color: AppColors.textDisabled,
                      ),
                      onPressed: () =>
                          ref.invalidate(standingsProvider(_selectedSeason)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: AppMotionSwitcher(
                  child: standingsAsync.when(
                    loading: () => const KeyedSubtree(
                      key: ValueKey('standings-loading'),
                      child: Center(
                        child: CircularProgressIndicator(color: AppColors.live),
                      ),
                    ),
                    error: (e, _) => KeyedSubtree(
                      key: ValueKey('standings-error-$_selectedSeason'),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '순위를 불러올 수 없습니다',
                              style: TextStyle(color: AppColors.textDisabled),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              describeAsyncError(e),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textDisabled,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => ref.invalidate(
                                standingsProvider(_selectedSeason),
                              ),
                              child: const Text('다시 시도'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    data: (standings) => KeyedSubtree(
                      key: ValueKey(
                        'standings-data-$_selectedSeason-${standings.length}',
                      ),
                      child: Column(
                        children: [
                          if (myTeamId != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                              child: _myTeamSummaryCard(standings, myTeamId),
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _buildHeaderRow(),
                          ),
                          const Divider(
                            color: AppColors.divider,
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                          ),
                          Expanded(child: _buildList(ref, standings, myTeamId)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Center(
                  child: Text(
                    '마지막 업데이트: ${DateFormat('yyyy.MM.dd HH:mm').format(DateTime.now())}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textDisabled,
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

  Widget _myTeamSummaryCard(List standings, String myTeamId) {
    final current = standings
        .where((item) => item.teamId == myTeamId)
        .firstOrNull;
    if (current == null) {
      return const SizedBox.shrink();
    }

    final team = KboTeams.byId(myTeamId);
    final teamColor = team?.primaryColor ?? AppColors.live;
    final cardTint = Color.alphaBlend(
      teamColor.withValues(alpha: 0.16),
      AppColors.card,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardTint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: teamColor.withValues(alpha: 0.24)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${current.teamName} 현재 순위',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${current.rank}위 · ${current.wins}승 ${current.losses}패 ${current.draws}무',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: teamColor.withValues(alpha: 0.22)),
            ),
            child: Text(
              _gbLabel(current.gb),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(WidgetRef ref, List standings, String? myTeamId) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(standingsProvider(_selectedSeason));
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: standings.length,
        itemBuilder: (context, index) {
          final s = standings[index];
          final isMyTeam = s.teamId == myTeamId;
          final team = KboTeams.byId(s.teamId);
          final teamColor = team?.primaryColor ?? AppColors.live;
          final rowTint = Color.alphaBlend(
            teamColor.withValues(alpha: 0.12),
            AppColors.card,
          );

          return AppMotionListItem(
            key: ValueKey('standing-${s.teamId}-${s.rank}'),
            index: index,
            child: Container(
              height: 56,
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: isMyTeam
                    ? rowTint
                    : (index.isOdd ? AppColors.card : Colors.transparent),
                borderRadius: BorderRadius.circular(14),
                border: isMyTeam
                    ? Border.all(color: teamColor.withValues(alpha: 0.22))
                    : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Center(
                      child: Text(
                        '${s.rank}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isMyTeam
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  if (isMyTeam)
                    Container(
                      margin: const EdgeInsets.only(right: 4),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: teamColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  CachedNetworkImage(
                    imageUrl: team?.logoUrl ?? '',
                    width: 24,
                    height: 24,
                    placeholder: (_, _) =>
                        const SizedBox(width: 24, height: 24),
                    errorWidget: (_, _, _) => Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppColors.cardSub,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          team?.shortName ?? '',
                          style: const TextStyle(
                            fontSize: 8,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.teamName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isMyTeam
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Center(
                      child: Text(
                        '${s.wins}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Center(
                      child: Text(
                        '${s.losses}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    child: Center(
                      child: Text(
                        '${s.draws}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Center(
                      child: Text(
                        s.pct,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    child: Center(
                      child: Text(
                        _gbText(s.gb),
                        style: TextStyle(
                          fontSize: 14,
                          color: isMyTeam
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontWeight: isMyTeam
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderRow() {
    const style = TextStyle(fontSize: 12, color: AppColors.textDisabled);
    return const SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Center(child: Text('순위', style: style)),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: 36),
              child: Text('팀', style: style),
            ),
          ),
          SizedBox(
            width: 32,
            child: Center(child: Text('승', style: style)),
          ),
          SizedBox(
            width: 32,
            child: Center(child: Text('패', style: style)),
          ),
          SizedBox(
            width: 28,
            child: Center(child: Text('무', style: style)),
          ),
          SizedBox(
            width: 48,
            child: Center(child: Text('승률', style: style)),
          ),
          SizedBox(
            width: 42,
            child: Center(child: Text('차', style: style)),
          ),
        ],
      ),
    );
  }

  String _gbText(String gb) {
    final value = gb.trim();
    if (value == '0') {
      return '-';
    }
    return value;
  }

  String _gbLabel(String gb) {
    final value = gb.trim();
    if (value == '0') {
      return '공동 선두';
    }
    if (value.endsWith('G')) {
      return '$value 차';
    }
    return '$value G차';
  }

  Widget _seasonDropdown() {
    final seasons = [
      for (int year = DateTime.now().year; year >= 2001; year--) year,
    ];
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: DropdownButton<int>(
        value: _selectedSeason,
        dropdownColor: AppColors.card,
        underline: const SizedBox.shrink(),
        items: seasons
            .map(
              (season) => DropdownMenuItem<int>(
                value: season,
                child: Text('$season', style: const TextStyle(fontSize: 14)),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          setState(() => _selectedSeason = value);
        },
      ),
    );
  }
}
