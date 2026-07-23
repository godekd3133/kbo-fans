import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/team_data.dart';
import '../../core/constants/visual_assets.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/kbo_time.dart';
import '../../core/widgets/app_artwork_card.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../core/widgets/kbo_team_logo_image.dart';
import '../../data/api/api_client.dart';
import '../../data/models/schedule.dart';
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
    _selectedSeason = kboCurrentSeason();
  }

  @override
  Widget build(BuildContext context) {
    final myTeamId = ref.watch(myTeamProvider);
    final standingsAsync = ref.watch(standingsProvider(_selectedSeason));
    final useCompactTitle = MediaQuery.sizeOf(context).width <= 300;

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
                      child: Text(
                        useCompactTitle ? 'KBO 순위' : '정규시즌 순위표',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _seasonDropdown(),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '순위 새로고침',
                      icon: Icon(
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
                    loading: () => KeyedSubtree(
                      key: ValueKey('standings-loading'),
                      child: Center(
                        child: CircularProgressIndicator(color: AppColors.live),
                      ),
                    ),
                    error: (e, _) => KeyedSubtree(
                      key: ValueKey('standings-error-$_selectedSeason'),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: AppArtworkCard(
                            assetName: VisualAssets.dataRetry,
                            height: 184,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                const Text(
                                  '순위를 불러올 수 없습니다',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  describeAsyncError(e),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: () => ref.invalidate(
                                      standingsProvider(_selectedSeason),
                                    ),
                                    child: const Text('다시 시도'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    data: (standings) => KeyedSubtree(
                      key: ValueKey(
                        'standings-data-$_selectedSeason-${standings.length}',
                      ),
                      child: standings.isEmpty
                          ? _buildEmptyState()
                          : Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    10,
                                  ),
                                  child: _StandingsPulseRail(
                                    standings: standings,
                                    myTeamId: myTeamId,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    0,
                                    18,
                                    2,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '차: 1위와 경기 차 · 연속: 현재 연승/연패',
                                      key: const ValueKey(
                                        'standings-column-help',
                                      ),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textDisabled,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: _buildHeaderRow(),
                                ),
                                Divider(
                                  color: AppColors.divider,
                                  height: 1,
                                  indent: 16,
                                  endIndent: 16,
                                ),
                                Expanded(
                                  child: _buildList(ref, standings, myTeamId),
                                ),
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
                    'KBO 순위 데이터 · 화면 확인 ${DateFormat('yyyy.MM.dd HH:mm').format(kboCivilDateTime())}',
                    style: TextStyle(
                      fontSize: 11,
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

  Widget _buildList(
    WidgetRef ref,
    List<TeamStanding> standings,
    String? myTeamId,
  ) {
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
          final colors = AppTheme.colorsOf(context);
          final teamColor = colors.readableAccent(
            team?.primaryColor ?? colors.live,
          );
          final screenWidth = MediaQuery.sizeOf(context).width;
          final useCompactTeamName = screenWidth <= 430;
          final useNarrowColumns = screenWidth <= 340;
          final displayTeamName = useCompactTeamName
              ? team?.shortName ?? s.teamName
              : s.teamName;
          final rowTint = Color.alphaBlend(
            teamColor.withValues(alpha: 0.2),
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
                    ? Border.all(color: teamColor.withValues(alpha: 0.58))
                    : null,
                boxShadow: isMyTeam
                    ? [
                        BoxShadow(
                          color: teamColor.withValues(alpha: 0.18),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ]
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  if (isMyTeam)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 4, color: teamColor),
                    ),
                  Row(
                    children: [
                      SizedBox(
                        width: useNarrowColumns ? 28 : 32,
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
                      if (isMyTeam && !useNarrowColumns)
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: teamColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      KboTeamLogoImage(
                        teamId: team?.id,
                        fallback: team?.shortName ?? s.teamName,
                        size: useNarrowColumns ? 20 : 24,
                        padding: 0,
                      ),
                      SizedBox(width: useNarrowColumns ? 4 : 8),
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Semantics(
                                label: s.teamName,
                                child: ExcludeSemantics(
                                  child: Text(
                                    displayTeamName,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isMyTeam
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (isMyTeam && !useNarrowColumns) ...[
                              const SizedBox(width: 6),
                              Container(
                                key: ValueKey(
                                  'standing-my-team-badge-${s.teamId}',
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: teamColor.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: teamColor.withValues(alpha: 0.52),
                                  ),
                                ),
                                child: Text(
                                  '마이팀',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(
                        width: useNarrowColumns ? 26 : 32,
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
                        width: useNarrowColumns ? 26 : 32,
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
                        width: useNarrowColumns ? 22 : 28,
                        child: Center(
                          child: Text(
                            '${s.draws}',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: useNarrowColumns ? 42 : 48,
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
                        width: useNarrowColumns ? 34 : 42,
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
                      SizedBox(
                        width: useNarrowColumns ? 42 : 50,
                        child: Center(
                          child: Text(
                            s.streakLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: _streakColor(s.streakLabel, isMyTeam),
                              fontWeight: isMyTeam
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
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
    final useNarrowColumns = MediaQuery.sizeOf(context).width <= 340;
    final style = TextStyle(fontSize: 12, color: AppColors.textDisabled);
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: useNarrowColumns ? 28 : 32,
            child: Center(child: Text('순위', style: style)),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: useNarrowColumns ? 24 : 36),
              child: Text('팀', style: style),
            ),
          ),
          SizedBox(
            width: useNarrowColumns ? 26 : 32,
            child: Center(child: Text('승', style: style)),
          ),
          SizedBox(
            width: useNarrowColumns ? 26 : 32,
            child: Center(child: Text('패', style: style)),
          ),
          SizedBox(
            width: useNarrowColumns ? 22 : 28,
            child: Center(child: Text('무', style: style)),
          ),
          SizedBox(
            width: useNarrowColumns ? 42 : 48,
            child: Center(child: Text('승률', style: style)),
          ),
          SizedBox(
            width: useNarrowColumns ? 34 : 42,
            child: Center(child: Text('차', style: style)),
          ),
          SizedBox(
            width: useNarrowColumns ? 42 : 50,
            child: Center(child: Text('연속', style: style)),
          ),
        ],
      ),
    );
  }

  Color _streakColor(String label, bool isMyTeam) {
    if (label.contains('연승')) {
      return AppColors.positive;
    }
    if (label.contains('연패')) {
      return AppColors.live;
    }
    return isMyTeam ? AppColors.textPrimary : AppColors.textSecondary;
  }

  String _gbText(String gb) {
    final value = gb.trim();
    if (value == '0') {
      return '-';
    }
    return value;
  }

  Widget _seasonDropdown() {
    final seasons = [
      for (int year = kboCurrentSeason(); year >= 2001; year--) year,
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

  Widget _buildEmptyState() {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: AppArtworkCard(
          assetName: VisualAssets.standingsRace,
          height: 196,
          alignment: Alignment.centerRight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '순위 데이터가 아직 없습니다',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                '$_selectedSeason 시즌 순위가 들어오면 이 화면에서 바로 정리됩니다.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      ref.invalidate(standingsProvider(_selectedSeason)),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('다시 확인'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StandingsPulseRail extends StatelessWidget {
  final List<TeamStanding> standings;
  final String? myTeamId;

  const _StandingsPulseRail({required this.standings, required this.myTeamId});

  @override
  Widget build(BuildContext context) {
    final topRaceLabel = _topRaceLabel(standings);
    final myTeam = myTeamId == null
        ? null
        : standings.where((item) => item.teamId == myTeamId).firstOrNull;
    final streakLeader = _streakLeader(standings);
    final streakLabel = streakLeader?.streakLabel ?? '-';
    final isLosingStreak = streakLabel.contains('연패');

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: AppArtworkLayer(
              assetName: VisualAssets.standingsRace,
              alignment: Alignment.centerRight,
              opacity: 0.18,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: _StandingsPulseItem(
                    title: '1위 경쟁',
                    value: topRaceLabel,
                    icon: Icons.flag_rounded,
                    color: AppColors.accent,
                  ),
                ),
                const _PulseDivider(),
                Expanded(
                  child: _StandingsPulseItem(
                    title: '마이팀',
                    value: myTeam == null ? '팀 선택 전' : '${myTeam.rank}위',
                    detail: myTeam == null
                        ? '설정에서 선택'
                        : '${myTeam.wins}-${myTeam.losses}-${myTeam.draws}',
                    icon: Icons.push_pin_rounded,
                    color: myTeam == null
                        ? AppColors.textSecondary
                        : AppTheme.colorsOf(context).readableAccent(
                            KboTeams.byId(myTeam.teamId)?.primaryColor ??
                                AppTheme.colorsOf(context).live,
                          ),
                  ),
                ),
                const _PulseDivider(),
                Expanded(
                  child: _StandingsPulseItem(
                    title: '연속 흐름',
                    value: streakLabel,
                    detail: streakLeader?.teamName,
                    icon: isLosingStreak
                        ? Icons.trending_down_rounded
                        : Icons.trending_up_rounded,
                    color: isLosingStreak ? AppColors.live : AppColors.positive,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _topRaceLabel(List<TeamStanding> standings) {
    if (standings.isEmpty) {
      return '-';
    }
    final withinTwoGames = standings.where((standing) {
      final gap = double.tryParse(standing.gb.replaceAll('G', '').trim()) ?? 99;
      return gap <= 2;
    }).length;
    return withinTwoGames <= 1 ? '단독 선두' : '$withinTwoGames팀';
  }

  TeamStanding? _streakLeader(List<TeamStanding> standings) {
    TeamStanding? leader;
    var longestStreak = 0;
    for (final standing in standings) {
      final match = RegExp(r'^(\d+)(연승|연패)$').firstMatch(standing.streakLabel);
      final streak = match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
      if (streak > longestStreak) {
        longestStreak = streak;
        leader = standing;
      }
    }
    return leader;
  }
}

class _StandingsPulseItem extends StatelessWidget {
  final String title;
  final String value;
  final String? detail;
  final IconData icon;
  final Color color;

  const _StandingsPulseItem({
    required this.title,
    required this.value,
    this.detail,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 74),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: color == AppColors.textSecondary
                  ? AppColors.textPrimary
                  : color,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textDisabled,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PulseDivider extends StatelessWidget {
  const _PulseDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 58,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: AppColors.divider,
    );
  }
}
