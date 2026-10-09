import '../../core/widgets/app_metadata_text.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/kbo_time.dart';
import '../../core/widgets/app_design_system.dart';
import '../../core/widgets/app_status_card.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../core/widgets/kbo_team_logo_image.dart';
import '../../data/api/api_client.dart';
import '../../data/models/schedule.dart';
import '../../data/providers.dart';
import '../records/records_area_switcher.dart';

const _largeTextStandingsScale = 1.4;

class StandingsScreen extends ConsumerStatefulWidget {
  final int? initialSeason;
  final bool followsCurrentSeason;

  const StandingsScreen({
    super.key,
    this.initialSeason,
    this.followsCurrentSeason = true,
  });

  @override
  ConsumerState<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends ConsumerState<StandingsScreen> {
  late int _selectedSeason;
  late int _currentSeason;
  bool _followsCurrentSeason = true;
  bool _refreshingStandings = false;

  @override
  void initState() {
    super.initState();
    _currentSeason =
        kboSeasonFromDateKey(ref.read(kboDateProvider)) ?? kboCurrentSeason();
    _selectedSeason =
        widget.initialSeason?.clamp(2001, _currentSeason) ?? _currentSeason;
    _followsCurrentSeason = widget.followsCurrentSeason;
    ref.listenManual<String>(kboDateProvider, (_, nextDate) {
      final nextSeason = kboSeasonFromDateKey(nextDate);
      if (!mounted || nextSeason == null || nextSeason == _currentSeason) {
        return;
      }
      setState(() {
        _currentSeason = nextSeason;
        if (_followsCurrentSeason) {
          _selectedSeason = nextSeason;
        }
      });
    });
  }

  @override
  void didUpdateWidget(covariant StandingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSeason != widget.initialSeason ||
        oldWidget.followsCurrentSeason != widget.followsCurrentSeason) {
      _selectedSeason =
          widget.initialSeason?.clamp(2001, _currentSeason) ?? _currentSeason;
      _followsCurrentSeason = widget.followsCurrentSeason;
    }
  }

  String _recordsLocation() => Uri(
    path: '/records',
    queryParameters: {
      'season': '$_selectedSeason',
      if (_followsCurrentSeason) 'seasonMode': 'current',
    },
  ).toString();

  Future<void> _refreshStandings() async {
    if (_refreshingStandings) {
      return;
    }
    setState(() => _refreshingStandings = true);
    final provider = standingsProvider(_selectedSeason);
    try {
      ref.invalidate(provider);
      await ref.read(provider.future);
    } catch (_) {
      // 화면의 AsyncValue 오류 상태가 재시도 결과를 표시한다.
    } finally {
      if (mounted) {
        setState(() => _refreshingStandings = false);
      }
    }
  }

  Widget _standingsRefreshIcon(BuildContext context) {
    if (!_refreshingStandings) {
      return Icon(Icons.refresh, size: 20, color: AppColors.textSupporting);
    }
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: AppTheme.colorsOf(context).accent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myTeamId = ref.watch(myTeamProvider);
    final standingsAsync = ref.watch(standingsProvider(_selectedSeason));
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final useCompactTitle = viewportWidth <= 300;
    final showRecordsAreaSwitcher = viewportWidth < 700;
    final useLargeText =
        MediaQuery.textScalerOf(context).scale(1) >= _largeTextStandingsScale;

    return Scaffold(
      body: SafeArea(
        child: AppPageFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: useLargeText
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppPageHeader(
                            eyebrow: 'KBO $_selectedSeason 시즌',
                            title: useCompactTitle ? 'KBO 순위' : '정규시즌 순위표',
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(child: _seasonDropdown()),
                              const SizedBox(width: 8),
                              IconButton(
                                key: const ValueKey('standings-refresh'),
                                tooltip: '순위 새로고침',
                                icon: _standingsRefreshIcon(context),
                                onPressed: _refreshingStandings
                                    ? null
                                    : () => unawaited(_refreshStandings()),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: AppPageHeader(
                              eyebrow: 'KBO $_selectedSeason 시즌',
                              title: useCompactTitle ? 'KBO 순위' : '정규시즌 순위표',
                            ),
                          ),
                          _seasonDropdown(),
                          const SizedBox(width: 8),
                          IconButton(
                            key: const ValueKey('standings-refresh'),
                            tooltip: '순위 새로고침',
                            icon: _standingsRefreshIcon(context),
                            onPressed: _refreshingStandings
                                ? null
                                : () => unawaited(_refreshStandings()),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 6),
              if (showRecordsAreaSwitcher) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: RecordsAreaSwitcher(
                    selected: RecordsAreaSection.standings,
                    onSelected: GoRouter.maybeOf(context) == null
                        ? null
                        : (section) {
                            if (section == RecordsAreaSection.records) {
                              context.go(_recordsLocation());
                            }
                          },
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Expanded(
                child: AppMotionSwitcher(
                  child: standingsAsync.when(
                    loading: () => KeyedSubtree(
                      key: ValueKey('standings-loading'),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.colorsOf(context).accent,
                        ),
                      ),
                    ),
                    error: (e, _) => KeyedSubtree(
                      key: ValueKey('standings-error-$_selectedSeason'),
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: AppStatusCard(
                            title: '순위를 불러오지 못했어요',
                            description: describeAsyncError(e),
                            onAction: _refreshingStandings
                                ? null
                                : () => unawaited(_refreshStandings()),
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
                          : useLargeText
                          ? _buildLargeTextList(standings, myTeamId)
                          : Column(
                              children: [
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
      onRefresh: _refreshStandings,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: standings.length,
        itemBuilder: (context, index) {
          final s = standings[index];
          final isMyTeam = s.teamId == myTeamId;
          final team = KboTeams.byId(s.teamId);
          final colors = AppTheme.colorsOf(context);
          final teamColor = colors.readableAccent(
            team?.primaryColor ?? colors.accent,
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
          final semanticsLabel = _standingSemanticsLabel(s, isMyTeam);

          return AppMotionListItem(
            key: ValueKey('standing-${s.teamId}-${s.rank}'),
            index: index,
            child: Semantics(
              container: true,
              label: semanticsLabel,
              child: ExcludeSemantics(
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
                                        color: teamColor.withValues(
                                          alpha: 0.52,
                                        ),
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
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLargeTextList(List<TeamStanding> standings, String? myTeamId) {
    return RefreshIndicator(
      onRefresh: _refreshStandings,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            sliver: SliverToBoxAdapter(
              child: Semantics(
                header: true,
                child: Container(
                  key: const ValueKey('standings-large-text-header'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cardSub,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: AppMetadataText(
                    '순위 · 팀 기록',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSupporting,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: standings.length,
              itemBuilder: (context, index) => _buildLargeTextStandingRow(
                standings[index],
                index: index,
                isMyTeam: standings[index].teamId == myTeamId,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
        ],
      ),
    );
  }

  String _standingSemanticsLabel(TeamStanding standing, bool isMyTeam) {
    final teamLabel = isMyTeam ? '${standing.teamName} 마이팀' : standing.teamName;
    return '${standing.rank}위 $teamLabel, ${standing.wins}승 ${standing.losses}패 ${standing.draws}무, 승률 ${standing.pct}, 경기 차 ${_gbText(standing.gb)}, ${standing.streakLabel}';
  }

  Widget _buildLargeTextStandingRow(
    TeamStanding standing, {
    required int index,
    required bool isMyTeam,
  }) {
    final team = KboTeams.byId(standing.teamId);
    final colors = AppTheme.colorsOf(context);
    final teamColor = colors.readableAccent(
      team?.primaryColor ?? colors.accent,
    );
    final rowTint = Color.alphaBlend(
      teamColor.withValues(alpha: 0.2),
      AppColors.card,
    );
    final semanticsLabel = _standingSemanticsLabel(standing, isMyTeam);

    return AppMotionListItem(
      key: ValueKey('standing-${standing.teamId}-${standing.rank}'),
      index: index,
      child: Semantics(
        container: true,
        label: semanticsLabel,
        child: ExcludeSemantics(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isMyTeam
                  ? rowTint
                  : (index.isOdd ? AppColors.card : Colors.transparent),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isMyTeam
                    ? teamColor.withValues(alpha: 0.58)
                    : AppColors.divider,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KboTeamLogoImage(
                      teamId: team?.id,
                      fallback: team?.shortName ?? standing.teamName,
                      size: 36,
                      padding: 0,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${standing.rank}위',
                            style: TextStyle(
                              fontSize: 15,
                              color: AppColors.textSupporting,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            standing.teamName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (isMyTeam)
                            Container(
                              key: ValueKey(
                                'standing-my-team-badge-${standing.teamId}',
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: teamColor.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: teamColor.withValues(alpha: 0.52),
                                ),
                              ),
                              child: const Text(
                                '마이팀',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    _largeTextMetric('${standing.wins}승'),
                    _largeTextMetric('${standing.losses}패'),
                    _largeTextMetric('${standing.draws}무'),
                    _largeTextMetric('승률 ${standing.pct}'),
                    _largeTextMetric('차 ${_gbText(standing.gb)}'),
                    _largeTextMetric(
                      standing.streakLabel,
                      color: _streakColor(standing.streakLabel, isMyTeam),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _largeTextMetric(String label, {Color? color}) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        color: color ?? AppColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildHeaderRow() {
    final useNarrowColumns = MediaQuery.sizeOf(context).width <= 340;
    final style = TextStyle(fontSize: 12, color: AppColors.textSupporting);
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
            child: Center(
              child: Tooltip(
                message: '1위와의 경기 차',
                child: Text('승차', style: style),
              ),
            ),
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
      for (int year = _currentSeason; year >= 2001; year--) year,
    ];
    return Container(
      key: const ValueKey('standings-season-dropdown'),
      constraints: const BoxConstraints(minHeight: 44),
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
          setState(() {
            _selectedSeason = value;
            _followsCurrentSeason = value == _currentSeason;
          });
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: AppStatusCard(
          icon: Icons.leaderboard_outlined,
          title: '아직 순위가 없어요',
          description:
              '$_selectedSeason 시즌 순위가 집계되면 여기서 확인할 수 있어요. 다른 시즌도 위에서 선택할 수 있어요.',
          actionLabel: _refreshingStandings ? '확인 중' : '다시 확인',
          onAction: _refreshingStandings
              ? null
              : () => unawaited(_refreshStandings()),
        ),
      ),
    );
  }
}
