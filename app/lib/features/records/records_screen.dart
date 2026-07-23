import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/team_data.dart';
import '../../core/constants/visual_assets.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/kbo_player_image_cache.dart';
import '../../core/utils/kbo_time.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../core/widgets/dev_console.dart';
import '../../core/widgets/kbo_team_logo_image.dart';
import '../../data/api/api_client.dart';
import '../../data/models/player.dart';
import '../../data/models/records_overview.dart';
import '../../data/models/team_records_bundle.dart';
import '../../data/models/team_stats.dart';
import '../../data/providers.dart';

enum PlayerListFilter { all, entryOnly, reserveOnly }

enum PlayerSortOption { name, avg, ops, era, whip }

const firstSupportedRecordsSeason = 2002;
TextStyle get _tableHeaderStyle => TextStyle(
  fontSize: 11,
  color: AppColors.textDisabled,
  fontWeight: FontWeight.w800,
);

class RecordsScreen extends ConsumerStatefulWidget {
  final String? teamId;

  const RecordsScreen({super.key, this.teamId});

  @override
  ConsumerState<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends ConsumerState<RecordsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  PlayerListFilter _filter = PlayerListFilter.all;
  PlayerSortOption _sort = PlayerSortOption.avg;
  String _searchQuery = '';
  late int _selectedSeason;
  LeaderboardPlayerGroup _selectedPreviewGroup = LeaderboardPlayerGroup.hitter;
  LeaderboardMetric _selectedPreviewMetric = LeaderboardMetric.avg;
  int? _teamRecordsLoadStartedAtMicros;
  String? _lastTeamRecordsLogKey;
  String? _lastTeamRecordsDiagKey;

  @override
  void initState() {
    super.initState();
    _selectedSeason = kboCurrentSeason();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {
        _sort = _tabController.index == 0
            ? PlayerSortOption.avg
            : PlayerSortOption.era;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppColors.sync(AppTheme.colorsOf(context));
    if (widget.teamId == null) {
      return _buildTeamChooser();
    }
    return _buildTeamRecords(widget.teamId!);
  }

  Future<void> _refreshOverview() async {
    ref.invalidate(recordsOverviewProvider(_selectedSeason));
    try {
      await ref.read(recordsOverviewProvider(_selectedSeason).future);
    } catch (error) {
      DevConsole.instance.warn('RECORDS overview refresh failed: $error');
    }
  }

  Future<void> _refreshTeamRecords(String teamId) async {
    ref.invalidate(teamRecordsProvider('$teamId|$_selectedSeason'));
    try {
      await ref.read(teamRecordsProvider('$teamId|$_selectedSeason').future);
    } catch (error) {
      DevConsole.instance.warn(
        'RECORDS team refresh failed: $teamId $_selectedSeason $error',
      );
    }
  }

  Widget _buildTeamChooser() {
    final myTeamId = ref.watch(myTeamProvider);
    final overviewAsync = ref.watch(recordsOverviewProvider(_selectedSeason));
    final orderedTeams = [...KboTeams.teams]
      ..sort((a, b) {
        if (a.id == myTeamId) return -1;
        if (b.id == myTeamId) return 1;
        return a.name.compareTo(b.name);
      });
    final visibleTeams = orderedTeams.where((team) {
      if (_searchQuery.isEmpty) return true;
      return team.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          team.shortName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(child: _RecordsBackdrop()),
            AppPageFrame(
              child: DefaultTextStyle.merge(
                style: TextStyle(color: AppColors.textPrimary),
                child: RefreshIndicator(
                  onRefresh: _refreshOverview,
                  color: AppColors.live,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'RECORDS',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.textDisabled,
                                    letterSpacing: 0,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  '기록실',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    height: 1.05,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  '한눈에 보는 리그 리더와 팀&선수 기록',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '기록실 새로고침',
                            onPressed: () {
                              unawaited(_refreshOverview());
                              setState(() {});
                            },
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _seasonSelector(),
                      const SizedBox(height: 10),
                      overviewAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (error, stackTrace) =>
                            _recordsOverviewErrorCard(error),
                        data: (overview) => Column(
                          children: [
                            _recordsBriefingPanel(overview),
                            const SizedBox(height: 8),
                            _metricSpotlightRail(overview),
                            const SizedBox(height: 8),
                            _recordsSectionHeader(
                              title: '리그 리더보드',
                              subtitle: '핵심 지표별 TOP 5를 빠르게 비교합니다.',
                              actionLabel: '전체 보기',
                              onActionTap: () => context.push(
                                '/records/leaderboard/${_selectedPreviewMetric.key}?season=$_selectedSeason',
                              ),
                            ),
                            const SizedBox(height: 6),
                            _metricHub(overview),
                            if (_pitcherMetricSnapshots(
                              overview,
                            ).isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _pitcherLeaderPanel(overview),
                            ],
                            const SizedBox(height: 18),
                            _recordsSectionHeader(
                              title: '팀 기록실',
                              subtitle: '마이팀을 먼저 배치하고 팀별 선수 기록으로 이어집니다.',
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                      TextField(
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                        decoration: InputDecoration(
                          hintText: '팀 검색',
                          hintStyle: TextStyle(color: AppColors.textDisabled),
                          prefixIcon: Icon(
                            Icons.search,
                            color: AppColors.textDisabled,
                          ),
                          filled: true,
                          fillColor: AppColors.card,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppColors.divider),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppColors.divider),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (final team in visibleTeams)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _teamChooserCard(
                            team,
                            isMyTeam: myTeamId == team.id,
                          ),
                        ),
                      if (visibleTeams.isEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 48),
                          child: Center(
                            child: Text(
                              '검색 결과가 없습니다',
                              style: TextStyle(color: AppColors.textDisabled),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamChooserCard(KboTeam team, {required bool isMyTeam}) {
    final colors = AppTheme.colorsOf(context);
    final accent = colors.readableAccent(team.primaryColor);
    return AppPressable(
      onTap: () => context.push('/records/team/${team.id}'),
      pressedScale: 0.97,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isMyTeam ? accent : AppColors.divider),
        ),
        child: Row(
          children: [
            KboTeamLogoImage(
              teamId: team.id,
              fallback: team.shortName,
              size: 40,
              padding: 0,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          team.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (isMyTeam)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.background.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.55),
                            ),
                          ),
                          child: Text(
                            '마이팀',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isMyTeam ? '마이팀 기록실 열기' : '선수 기록 보기',
                    style: TextStyle(
                      fontSize: 12,
                      color: isMyTeam
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: isMyTeam ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textDisabled),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamRecords(String teamId) {
    final team = KboTeams.byId(teamId);
    final teamRecordsAsync = ref.watch(
      teamRecordsProvider('$teamId|$_selectedSeason'),
    );
    final recordsMotionKey = teamRecordsAsync.isLoading
        ? 'records-loading-$teamId'
        : teamRecordsAsync.hasError
        ? 'records-error-$teamId'
        : 'records-data-$teamId-$_selectedSeason-${_tabController.index}-$_filter-$_sort-${teamRecordsAsync.asData?.value.players.length ?? 0}';
    _logTeamRecordsLoad(teamId, teamRecordsAsync);

    return Scaffold(
      body: SafeArea(
        child: AppPageFrame(
          child: DefaultTextStyle.merge(
            style: TextStyle(color: AppColors.textPrimary),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => context.go('/records'),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '기록실',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${team?.name ?? teamId} $_selectedSeason 시즌 기록실',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '팀 기록 새로고침',
                        onPressed: () => unawaited(_refreshTeamRecords(teamId)),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      if (team != null)
                        KboTeamLogoImage(
                          teamId: team.id,
                          fallback: team.shortName,
                          size: 40,
                          padding: 0,
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _seasonSelector(),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: teamRecordsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, stackTrace) => const SizedBox.shrink(),
                    data: (teamRecords) =>
                        _teamStatsCard(teamRecords.teamStats),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: AppColors.textPrimary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      dividerColor: Colors.transparent,
                      labelPadding: EdgeInsets.zero,
                      labelColor: AppColors.background,
                      unselectedLabelColor: AppColors.textSecondary,
                      labelStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      overlayColor: WidgetStateProperty.all(Colors.transparent),
                      splashFactory: NoSplash.splashFactory,
                      tabs: const [
                        Tab(height: 44, child: Center(child: Text('야수'))),
                        Tab(height: 44, child: Center(child: Text('투수'))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _filterButton(
                          label: '전체',
                          selected: _filter == PlayerListFilter.all,
                          onTap: () =>
                              setState(() => _filter = PlayerListFilter.all),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _filterButton(
                          label: '엔트리',
                          selected: _filter == PlayerListFilter.entryOnly,
                          onTap: () => setState(
                            () => _filter = PlayerListFilter.entryOnly,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _filterButton(
                          label: '엔트리 제외',
                          selected: _filter == PlayerListFilter.reserveOnly,
                          onTap: () => setState(
                            () => _filter = PlayerListFilter.reserveOnly,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: _sortOptionsForCurrentTab().map((option) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _sortChip(
                          label: _sortLabel(option),
                          selected: _sort == option,
                          onTap: () => setState(() => _sort = option),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: AppMotionSwitcher(
                    child: KeyedSubtree(
                      key: ValueKey(recordsMotionKey),
                      child: RefreshIndicator(
                        onRefresh: () => _refreshTeamRecords(teamId),
                        color: AppColors.live,
                        child: teamRecordsAsync.when(
                          loading: () => ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: 420,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.live,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          error: (error, _) => ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: 420,
                                child: Center(
                                  child: Text(
                                    '선수 기록을 불러올 수 없습니다',
                                    style: TextStyle(
                                      color: AppColors.textDisabled,
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Text(
                                  describeAsyncError(error),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textDisabled,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          data: (teamRecords) =>
                              _buildList(teamRecords.players),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _recordsOverviewErrorCard(Object error) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 20,
              color: AppColors.textDisabled,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '리그 기록을 불러올 수 없습니다',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    describeAsyncError(error),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '다시 시도',
              onPressed: () => unawaited(_refreshOverview()),
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  void _logTeamRecordsLoad(
    String teamId,
    AsyncValue<TeamRecordsBundle> teamRecordsAsync,
  ) {
    if (teamRecordsAsync.hasError) {
      _logTeamRecordsDiagnostics(teamId);
    }

    if (!teamRecordsAsync.hasValue) {
      _teamRecordsLoadStartedAtMicros ??= DateTime.now().microsecondsSinceEpoch;
      return;
    }

    final records = teamRecordsAsync.value;
    final playerCount = records?.players.length ?? 0;
    final logKey = '$teamId|$_selectedSeason|$playerCount';
    if (_lastTeamRecordsLogKey == logKey) {
      return;
    }

    final startedAt = _teamRecordsLoadStartedAtMicros;
    if (startedAt != null) {
      final elapsedMs =
          (DateTime.now().microsecondsSinceEpoch - startedAt) / 1000;
      DevConsole.instance.info(
        'RECORDS $teamId/$_selectedSeason loaded ${elapsedMs.toStringAsFixed(0)}ms ($playerCount players)',
      );
      unawaited(
        ref.read(apiClientProvider).postClientMetric({
          'screen': 'records',
          'event': 'loaded',
          'elapsedMs': elapsedMs.round(),
          'teamId': teamId,
          'season': _selectedSeason,
          'playerCount': playerCount,
        }),
      );
    }
    _lastTeamRecordsLogKey = logKey;
    _teamRecordsLoadStartedAtMicros = null;
  }

  void _logTeamRecordsDiagnostics(String teamId) {
    final diagKey = '$teamId|$_selectedSeason';
    if (_lastTeamRecordsDiagKey == diagKey) {
      return;
    }
    _lastTeamRecordsDiagKey = diagKey;
    unawaited(() async {
      final diagnostics = await ref
          .read(apiClientProvider)
          .diagnoseTeamRecords(teamId: teamId, season: _selectedSeason);
      DevConsole.instance.warn(
        'RECORDS DIAG team=$teamId season=$_selectedSeason',
      );
      for (final line in diagnostics) {
        DevConsole.instance.warn(line);
      }
    }());
  }

  Widget _buildList(List<PlayerProfile> players) {
    final filtered = _sortPlayers(_applyFilters(players));
    final entryPlayers = filtered
        .where((player) => player.rosterGroup == PlayerRosterGroup.entry)
        .toList();
    final reservePlayers = filtered
        .where((player) => player.rosterGroup == PlayerRosterGroup.reserve)
        .toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _summaryCard(entryPlayers.length, reservePlayers.length),
        if (entryPlayers.isNotEmpty) ...[
          const SizedBox(height: 18),
          _sectionTitle('팀 엔트리'),
          const SizedBox(height: 10),
          ...entryPlayers.asMap().entries.map(
            (entry) => AppMotionListItem(
              key: ValueKey('entry-player-${entry.value.id}'),
              index: entry.key,
              child: _playerCard(entry.value),
            ),
          ),
        ],
        if (reservePlayers.isNotEmpty) ...[
          const SizedBox(height: 18),
          _sectionTitle('엔트리 제외 / 이탈'),
          const SizedBox(height: 10),
          ...reservePlayers.asMap().entries.map(
            (entry) => AppMotionListItem(
              key: ValueKey('reserve-player-${entry.value.id}'),
              index: entry.key,
              child: _playerCard(entry.value),
            ),
          ),
        ],
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Center(
              child: Text(
                '조건에 맞는 선수가 없습니다',
                style: TextStyle(color: AppColors.textDisabled),
              ),
            ),
          ),
      ],
    );
  }

  List<PlayerProfile> _applyFilters(List<PlayerProfile> players) {
    final targetType = _tabController.index == 0
        ? PlayerType.hitter
        : PlayerType.pitcher;
    var filtered = players
        .where((player) => player.playerType == targetType)
        .toList();

    switch (_filter) {
      case PlayerListFilter.entryOnly:
        filtered = filtered
            .where((player) => player.rosterGroup == PlayerRosterGroup.entry)
            .toList();
        break;
      case PlayerListFilter.reserveOnly:
        filtered = filtered
            .where((player) => player.rosterGroup == PlayerRosterGroup.reserve)
            .toList();
        break;
      case PlayerListFilter.all:
        break;
    }
    return filtered;
  }

  List<PlayerProfile> _sortPlayers(List<PlayerProfile> players) {
    final sorted = [...players];
    sorted.sort((a, b) {
      switch (_sort) {
        case PlayerSortOption.name:
          return a.name.compareTo(b.name);
        case PlayerSortOption.avg:
          return (b.avg ?? -1).compareTo(a.avg ?? -1);
        case PlayerSortOption.ops:
          return (b.ops ?? -1).compareTo(a.ops ?? -1);
        case PlayerSortOption.era:
          return (a.era ?? 999).compareTo(b.era ?? 999);
        case PlayerSortOption.whip:
          return (a.whip ?? 999).compareTo(b.whip ?? 999);
      }
    });
    return sorted;
  }

  List<PlayerSortOption> _sortOptionsForCurrentTab() {
    if (_tabController.index == 0) {
      return const [
        PlayerSortOption.name,
        PlayerSortOption.avg,
        PlayerSortOption.ops,
      ];
    }
    return const [
      PlayerSortOption.name,
      PlayerSortOption.era,
      PlayerSortOption.whip,
    ];
  }

  String _sortLabel(PlayerSortOption option) {
    switch (option) {
      case PlayerSortOption.name:
        return '이름순';
      case PlayerSortOption.avg:
        return '타율';
      case PlayerSortOption.ops:
        return 'OPS';
      case PlayerSortOption.era:
        return 'ERA';
      case PlayerSortOption.whip:
        return 'WHIP';
    }
  }

  Widget _summaryCard(int entryCount, int reserveCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(child: _summaryMetric('엔트리', '$entryCount명')),
          Container(width: 1, height: 36, color: AppColors.divider),
          Expanded(child: _summaryMetric('엔트리 제외', '$reserveCount명')),
        ],
      ),
    );
  }

  Widget _summaryMetric(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) => Text(
    title,
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
  );

  Widget _playerCard(PlayerProfile player) {
    final team = KboTeams.byId(player.teamId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppPressable(
        onTap: player.isRetired
            ? null
            : () => context.push(
                '/records/player/${player.id}?season=$_selectedSeason',
              ),
        pressedScale: 0.985,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _playerPhoto(player, team),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            player.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _numberBadge(player.number, team),
                        const SizedBox(width: 8),
                        _statusBadge(player),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _playerMetaLine(player),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      player.headlineStat,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      player.secondaryStat,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (_primarySeasonMetrics(player).isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _primarySeasonMetrics(
                          player,
                        ).map((metric) => _statPill(metric)).toList(),
                      ),
                    ],
                    if (player.statusNote != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        player.statusNote!,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              player.status == PlayerAvailabilityStatus.injured
                              ? AppColors.live
                              : AppColors.textDisabled,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!player.isRetired)
                Icon(Icons.chevron_right, color: AppColors.textDisabled),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(PlayerProfile player) {
    if (player.isRetired) {
      return _pill('은퇴', AppColors.textDisabled);
    }
    switch (player.status) {
      case PlayerAvailabilityStatus.available:
        return _pill('정상', AppColors.positive);
      case PlayerAvailabilityStatus.injured:
        return _pill('부상', AppColors.live);
      case PlayerAvailabilityStatus.inactive:
        return _pill('엔트리 제외', AppColors.textDisabled);
    }
  }

  Widget _playerPhoto(PlayerProfile player, KboTeam? team) {
    final photoUrl = playerProfileImageUrl(player, season: _selectedSeason);
    if (photoUrl != null && photoUrl.isNotEmpty) {
      final cacheSize = kboPlayerImageCacheSize(52);
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: photoUrl,
          httpHeaders: kboPlayerImageHeaders,
          cacheManager: kboPlayerImageCacheManager,
          width: 52,
          height: 52,
          memCacheWidth: cacheSize,
          memCacheHeight: cacheSize,
          maxWidthDiskCache: cacheSize,
          maxHeightDiskCache: cacheSize,
          fit: BoxFit.cover,
          placeholder: (_, _) => _playerPhotoFallback(player.number, team),
          errorWidget: (_, _, _) => _playerPhotoFallback(player.number, team),
        ),
      );
    }
    return _playerPhotoFallback(player.number, team);
  }

  Widget _playerPhotoFallback(int number, KboTeam? team) {
    final colors = AppTheme.colorsOf(context);
    final accent = colors.readableAccent(
      team?.primaryColor ?? colors.textSecondary,
    );
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.person_rounded, color: accent, size: 28),
    );
  }

  Widget _numberBadge(int number, KboTeam? team) {
    final colors = AppTheme.colorsOf(context);
    final accent = colors.readableAccent(
      team?.primaryColor ?? colors.textSecondary,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$number',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _statPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _playerMetaLine(PlayerProfile player) {
    final parts = <String>[];
    final roleLabel = player.roleLabel.trim();
    final position = player.position.trim();
    final handedness = player.handedness.trim();

    if (roleLabel.isNotEmpty) {
      parts.add(roleLabel);
    }
    if (position.isNotEmpty && position != roleLabel) {
      parts.add(position);
    }
    if (handedness.isNotEmpty) {
      parts.add(handedness);
    }
    return parts.join(' · ');
  }

  List<String> _primarySeasonMetrics(PlayerProfile player) {
    final stats = player.seasonStats;
    if (stats.isEmpty) {
      return const [];
    }

    if (player.playerType == PlayerType.pitcher) {
      return _pickMetrics(stats, const [
        'G ',
        'IP ',
        'SO ',
        'ER ',
        'W ',
        'L ',
      ], maxCount: 4);
    }

    return _pickMetrics(stats, const [
      'G ',
      'PA ',
      'AB ',
      'H ',
      'HR ',
      'RBI ',
    ], maxCount: 4);
  }

  List<String> _pickMetrics(
    List<String> stats,
    List<String> preferredPrefixes, {
    required int maxCount,
  }) {
    final picked = <String>[];

    for (final prefix in preferredPrefixes) {
      final match = stats.where((stat) => stat.startsWith(prefix)).firstOrNull;
      if (match != null && !picked.contains(match)) {
        picked.add(match);
      }
      if (picked.length >= maxCount) {
        return picked;
      }
    }

    for (final stat in stats) {
      if (!picked.contains(stat)) {
        picked.add(stat);
      }
      if (picked.length >= maxCount) {
        break;
      }
    }

    return picked;
  }

  Widget _filterButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return AppPressable(
      onTap: onTap,
      pressedScale: 0.96,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: selected ? null : Border.all(color: AppColors.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.background : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _sortChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return AppPressable(
      onTap: onTap,
      pressedScale: 0.96,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.cardSub : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.textSecondary : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AppColors.textPrimary : AppColors.textDisabled,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _seasonSelector() {
    final seasons = [
      for (
        int year = kboCurrentSeason();
        year >= firstSupportedRecordsSeason;
        year--
      )
        year,
    ];
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Text(
            '시즌',
            style: TextStyle(fontSize: 11, color: AppColors.textDisabled),
          ),
          const Spacer(),
          DropdownButton<int>(
            value: _selectedSeason,
            dropdownColor: AppColors.card,
            underline: const SizedBox.shrink(),
            items: seasons
                .map(
                  (season) => DropdownMenuItem<int>(
                    value: season,
                    child: Text(
                      '$season',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedSeason = value);
            },
          ),
        ],
      ),
    );
  }

  Widget _teamStatsCard(TeamStats teamStats) {
    final battingAvg = teamStats.hitting['AVG'] ?? '-';
    final teamEra = teamStats.pitching['ERA'] ?? '-';
    final winPct = teamStats.pitching['WPCT'] ?? '-';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _heroTeamMetric(
                  '팀 타율',
                  battingAvg,
                  'OPS ${teamStats.hitting['OPS'] ?? '-'} · 홈런 ${teamStats.hitting['HR'] ?? '-'}',
                ),
              ),
              Container(width: 1, height: 56, color: AppColors.divider),
              Expanded(
                child: _heroTeamMetric(
                  '팀 승률',
                  winPct,
                  '팀 ERA $teamEra · WHIP ${teamStats.pitching['WHIP'] ?? '-'}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _summaryMetric('팀 ERA', teamEra)),
              Container(width: 1, height: 36, color: AppColors.divider),
              Expanded(
                child: _summaryMetric(
                  'WHIP',
                  teamStats.pitching['WHIP'] ?? '-',
                ),
              ),
              Container(width: 1, height: 36, color: AppColors.divider),
              Expanded(
                child: _summaryMetric('홈런', teamStats.hitting['HR'] ?? '-'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroTeamMetric(String label, String value, String detail) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          detail,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _recordsBriefingPanel(RecordsOverview overview) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final headline = _headlineLeader(overview);
    final todayFeatured = _todayFeaturedCards(overview);

    return Container(
      key: const ValueKey('records-briefing-panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isLight
              ? [
                  AppColors.card,
                  AppColors.card,
                  AppColors.cardSub.withValues(alpha: 0.76),
                ]
              : [
                  AppColors.card.withValues(alpha: 0.96),
                  AppColors.surface.withValues(alpha: 0.9),
                  AppColors.background.withValues(alpha: 0.86),
                ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.textSecondary.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: isLight
                ? const Color(0x1A0F172A)
                : Colors.black.withValues(alpha: 0.32),
            blurRadius: isLight ? 16 : 22,
            offset: Offset(0, isLight ? 8 : 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '시즌 리더 요약',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      '타자와 투수 대표를 먼저 보고 지표별 순위로 이어가세요.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$_selectedSeason',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textDisabled,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (headline == null && todayFeatured.isEmpty)
            Text(
              '현재 표시할 기록 리더가 없습니다.',
              style: TextStyle(fontSize: 13, color: AppColors.textDisabled),
            )
          else if (todayFeatured.isNotEmpty)
            _todayFeaturedPlayerStrip(todayFeatured)
          else if (headline != null)
            _headlineLeaderBlock(overview, headline),
        ],
      ),
    );
  }

  List<FeaturedPlayerCard> _todayFeaturedCards(RecordsOverview overview) {
    return [
      overview.todayHitter,
      overview.todayPitcher,
    ].where(_hasFeaturedPlayer).toList();
  }

  bool _hasFeaturedPlayer(FeaturedPlayerCard card) {
    return (card.name ?? '').trim().isNotEmpty ||
        (card.playerId ?? '').trim().isNotEmpty;
  }

  Widget _todayFeaturedPlayerStrip(List<FeaturedPlayerCard> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 330 || cards.length == 1) {
          return Column(
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                if (index > 0) const SizedBox(height: 7),
                _todayFeaturedPlayerCell(cards[index]),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < cards.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              Expanded(child: _todayFeaturedPlayerCell(cards[index])),
            ],
          ],
        );
      },
    );
  }

  Widget _todayFeaturedPlayerCell(FeaturedPlayerCard card) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final team = card.teamId == null ? null : KboTeams.byId(card.teamId!);
    final name = (card.name ?? '').trim().isEmpty ? '준비 중' : card.name!.trim();
    final summary = (card.headline ?? card.summary ?? '').trim();

    return Container(
      key: card.playerType == 'pitcher'
          ? const ValueKey('records-pitcher-spotlight')
          : card.playerType == 'hitter'
          ? const ValueKey('records-hitter-spotlight')
          : null,
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: isLight
            ? AppColors.cardSub.withValues(alpha: 0.64)
            : AppColors.background.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.textSecondary.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        children: [
          _featuredPlayerPhoto(card, team),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textDisabled,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                      height: 1.15,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _featuredPlayerPhoto(FeaturedPlayerCard card, KboTeam? team) {
    final playerId = (card.playerId ?? '').trim();
    final imageUrl = (card.imageUrl ?? '').trim().isNotEmpty
        ? card.imageUrl!.trim()
        : playerId.isNotEmpty
        ? kboPlayerImageUrl(season: _selectedSeason, playerId: playerId)
        : null;

    Widget fallback() => Container(
      width: 38,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: team == null
          ? Icon(Icons.person_rounded, size: 21, color: AppColors.textDisabled)
          : KboTeamLogoImage(
              teamId: team.id,
              fallback: team.shortName,
              size: 26,
              padding: 0,
            ),
    );

    if (imageUrl == null) {
      return fallback();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        httpHeaders: kboPlayerImageHeaders,
        cacheManager: kboPlayerImageCacheManager,
        width: 38,
        height: 44,
        memCacheWidth: kboPlayerImageCacheSize(44),
        memCacheHeight: kboPlayerImageCacheSize(44),
        maxWidthDiskCache: kboPlayerImageCacheSize(44),
        maxHeightDiskCache: kboPlayerImageCacheSize(44),
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => fallback(),
      ),
    );
  }

  Widget _headlineLeaderBlock(RecordsOverview overview, RecordLeader leader) {
    final team = KboTeams.byId(leader.teamId);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _leaderPhoto(leader, width: 64, height: 72),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (team != null) ...[
                    KboTeamLogoImage(
                      teamId: team.id,
                      fallback: team.shortName,
                      size: 22,
                      padding: 0,
                    ),
                    const SizedBox(width: 7),
                  ],
                  Expanded(
                    child: Text(
                      leader.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                team?.name ?? leader.teamId,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 7,
                runSpacing: 5,
                children: _metricSnapshots(overview)
                    .where(
                      (snapshot) =>
                          snapshot.topLeader?.playerId == leader.playerId,
                    )
                    .map(
                      (snapshot) => _miniMetricPill(
                        snapshot.metric.shortLabel,
                        snapshot.topLeader?.value ?? '-',
                        snapshot.color,
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricSpotlightRail(RecordsOverview overview) {
    final snapshots = _metricSnapshots(overview);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final cardWidth = ((constraints.maxWidth - (gap * 2)) / 3)
            .clamp(108.0, 124.0)
            .toDouble();

        return SizedBox(
          height: 116,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            itemCount: snapshots.length,
            separatorBuilder: (_, _) => const SizedBox(width: gap),
            itemBuilder: (context, index) => SizedBox(
              width: cardWidth,
              child: _metricSpotlightCard(snapshots[index]),
            ),
          ),
        );
      },
    );
  }

  Widget _metricSpotlightCard(_MetricSnapshot snapshot) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final leader = snapshot.topLeader;
    final team = leader == null ? null : KboTeams.byId(leader.teamId);
    return AppPressable(
      onTap: () => context.push(
        '/records/leaderboard/${snapshot.metric.key}?season=$_selectedSeason',
      ),
      pressedScale: 0.97,
      child: Container(
        key: ValueKey('records-metric-${snapshot.metric.key}'),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isLight
                ? [AppColors.card, AppColors.cardSub.withValues(alpha: 0.68)]
                : [
                    AppColors.card.withValues(alpha: 0.98),
                    AppColors.surface.withValues(alpha: 0.9),
                  ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: snapshot.color.withValues(alpha: 0.62)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 18,
                  decoration: BoxDecoration(
                    color: snapshot.color,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    snapshot.metric.shortLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textDisabled,
                ),
              ],
            ),
            Row(
              children: [
                if (leader != null)
                  _rankBadge('${leader.rank}위', snapshot.color),
                if (leader != null) const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    leader?.name ?? '준비 중',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              leader == null
                  ? '공식 소스 확인 중'
                  : '${team?.shortName ?? leader.teamId} · ${_leaderGapText(snapshot.metric, snapshot.leaders)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 27,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  leader?.value ?? '-',
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pitcherLeaderPanel(RecordsOverview overview) {
    final snapshots = _pitcherMetricSnapshots(overview);
    if (snapshots.isEmpty) {
      return const SizedBox.shrink();
    }
    final isLight = Theme.of(context).brightness == Brightness.light;
    final featured = snapshots.first.topLeader;

    return Container(
      key: const ValueKey('records-pitching-leader-panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLight
            ? AppColors.card
            : AppColors.card.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.live.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.sports_baseball_rounded,
                  size: 17,
                  color: AppColors.live,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '마운드 체크',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ERA, 다승, 세이브, 탈삼진 흐름을 함께 봅니다.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
          if (featured != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _leaderPhoto(featured, width: 44, height: 52),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        featured.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _pitchingLeaderSummary(
                          snapshots.first.metric,
                          featured,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
          ],
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final cellWidth = constraints.maxWidth < 330
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final snapshot in snapshots)
                    SizedBox(
                      width: cellWidth,
                      child: _pitcherMetricCell(snapshot),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _pitcherMetricCell(_MetricSnapshot snapshot) {
    final leader = snapshot.topLeader;
    return AppPressable(
      onTap: () => context.push(
        '/records/leaderboard/${snapshot.metric.key}?season=$_selectedSeason',
      ),
      pressedScale: 0.98,
      child: Container(
        constraints: const BoxConstraints(minHeight: 78),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: snapshot.color.withValues(alpha: 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  snapshot.metric.shortLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: snapshot.color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.textDisabled,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              leader?.name ?? '준비 중',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(
              leader == null
                  ? '공식 소스 확인 중'
                  : _pitchingLeaderSummary(snapshot.metric, leader),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricHub(RecordsOverview overview) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final snapshots = _metricSnapshotsForGroup(overview, _selectedPreviewGroup);
    final selected = snapshots.firstWhere(
      (snapshot) => snapshot.metric == _selectedPreviewMetric,
      orElse: () => snapshots.firstWhere(
        (snapshot) => snapshot.metric == _selectedPreviewGroup.defaultMetric,
        orElse: () => snapshots.first,
      ),
    );
    final leaders = selected.leaders.take(3).toList();

    return Container(
      key: const ValueKey('records-leaderboard-hub'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: isLight
            ? AppColors.card
            : AppColors.card.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: isLight
                ? const Color(0x140F172A)
                : Colors.black.withValues(alpha: 0.2),
            blurRadius: isLight ? 14 : 18,
            offset: Offset(0, isLight ? 7 : 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: _leaderboardGroupSegment(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _selectedPreviewGroup.description,
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
          ),
          SizedBox(
            height: 50,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tabWidth = constraints.maxWidth / snapshots.length;
                return Row(
                  children: [
                    for (final snapshot in snapshots)
                      _leaderboardTab(
                        snapshot,
                        width: tabWidth,
                        selected: snapshot.metric == selected.metric,
                      ),
                  ],
                );
              },
            ),
          ),
          Container(height: 1, color: AppColors.divider),
          _leaderboardHeader(),
          if (leaders.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(14, 18, 14, 18),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '현재 리더보드 준비 중',
                  style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
                ),
              ),
            )
          else
            for (var index = 0; index < leaders.length; index++)
              _leaderboardTableRow(
                leader: leaders[index],
                color: selected.color,
                showDivider: index != leaders.length - 1,
              ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: AppPressable(
              onTap: () => context.push(
                '/records/leaderboard/${selected.metric.key}?season=$_selectedSeason',
              ),
              pressedScale: 0.98,
              child: Container(
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.background.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${_selectedPreviewGroup.label} ${selected.metric.shortLabel} 전체 보기',
                      style: TextStyle(
                        fontSize: 13,
                        color: selected.color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: selected.color,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _leaderboardGroupSegment() {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          for (final group in LeaderboardPlayerGroup.values)
            Expanded(child: _leaderboardGroupButton(group)),
        ],
      ),
    );
  }

  Widget _leaderboardGroupButton(LeaderboardPlayerGroup group) {
    final selected = _selectedPreviewGroup == group;
    return AppPressable(
      onTap: selected ? null : () => _selectPreviewGroup(group),
      pressedScale: 0.98,
      child: AnimatedContainer(
        key: ValueKey('records-leaderboard-group-${group.name}'),
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

  void _selectPreviewGroup(LeaderboardPlayerGroup group) {
    setState(() {
      _selectedPreviewGroup = group;
      if (!group.metrics.contains(_selectedPreviewMetric)) {
        _selectedPreviewMetric = group.defaultMetric;
      }
    });
  }

  Widget _leaderboardTab(
    _MetricSnapshot snapshot, {
    required double width,
    required bool selected,
  }) {
    return AppPressable(
      onTap: selected
          ? null
          : () => setState(() => _selectedPreviewMetric = snapshot.metric),
      pressedScale: 0.98,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: width,
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? snapshot.color.withValues(alpha: 0.12)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: selected ? snapshot.color : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          snapshot.metric.shortLabel,
          style: TextStyle(
            fontSize: 14,
            color: selected ? snapshot.color : AppColors.textSecondary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _leaderboardHeader() {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          SizedBox(width: 34, child: Text('순위', style: _tableHeaderStyle)),
          SizedBox(width: 14),
          Expanded(flex: 5, child: Text('선수', style: _tableHeaderStyle)),
          Expanded(flex: 3, child: Text('팀', style: _tableHeaderStyle)),
          SizedBox(
            width: 64,
            child: Text(
              '기록',
              textAlign: TextAlign.right,
              style: _tableHeaderStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _leaderboardTableRow({
    required RecordLeader leader,
    required Color color,
    required bool showDivider,
  }) {
    final team = KboTeams.byId(leader.teamId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.divider),
          bottom: showDivider
              ? BorderSide(color: AppColors.background.withValues(alpha: 0.3))
              : BorderSide.none,
        ),
      ),
      child: AppPressable(
        onTap: leader.isRetired
            ? null
            : () => context.push(
                '/records/player/${leader.playerId}?season=$_selectedSeason',
              ),
        pressedScale: 0.992,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '${leader.rank}',
                  style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 5,
                child: Text(
                  leader.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    if (team != null) ...[
                      KboTeamLogoImage(
                        teamId: team.id,
                        fallback: team.shortName,
                        size: 22,
                        padding: 0,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        team?.shortName ?? leader.teamId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  leader.value,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rankBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _miniMetricPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _leaderPhoto(
    RecordLeader leader, {
    required double width,
    required double height,
  }) {
    final team = KboTeams.byId(leader.teamId);
    final colors = AppTheme.colorsOf(context);
    final accent = colors.readableAccent(
      team?.primaryColor ?? colors.textSecondary,
    );
    final cacheSize = kboPlayerImageCacheSize(height);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: kboPlayerImageUrl(
          season: _selectedSeason,
          playerId: leader.playerId,
        ),
        httpHeaders: kboPlayerImageHeaders,
        cacheManager: kboPlayerImageCacheManager,
        width: width,
        height: height,
        memCacheWidth: cacheSize,
        memCacheHeight: cacheSize,
        maxWidthDiskCache: cacheSize,
        maxHeightDiskCache: cacheSize,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => Container(
          width: width,
          height: height,
          color: accent.withValues(alpha: 0.14),
          alignment: Alignment.center,
          child: Text(
            leader.name.isEmpty ? '?' : leader.name.substring(0, 1),
            style: TextStyle(color: accent, fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }

  Widget _recordsSectionHeader({
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onActionTap,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        if (actionLabel != null && onActionTap != null) ...[
          const SizedBox(width: 12),
          AppPressable(
            onTap: onActionTap,
            pressedScale: 0.97,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.card.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 17,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  RecordLeader? _headlineLeader(RecordsOverview overview) {
    final leaders = _metricSnapshots(
      overview,
    ).map((snapshot) => snapshot.topLeader).whereType<RecordLeader>().toList();
    if (leaders.isEmpty) {
      return null;
    }

    final counts = <String, int>{};
    for (final leader in leaders) {
      counts[leader.playerId] = (counts[leader.playerId] ?? 0) + 1;
    }
    final ordered = [...leaders]
      ..sort((a, b) {
        final countDiff = (counts[b.playerId] ?? 0).compareTo(
          counts[a.playerId] ?? 0,
        );
        if (countDiff != 0) {
          return countDiff;
        }
        return a.rank.compareTo(b.rank);
      });
    return ordered.first;
  }

  String _briefMetricLabel(LeaderboardMetric metric) {
    return switch (metric) {
      LeaderboardMetric.avg => '타율 1위',
      LeaderboardMetric.hr => '홈런 1위',
      LeaderboardMetric.era => 'ERA 1위',
      LeaderboardMetric.wins => '다승 1위',
      LeaderboardMetric.saves => '세이브 1위',
      LeaderboardMetric.strikeouts => '탈삼진 1위',
      LeaderboardMetric.ops => 'OPS 1위',
      LeaderboardMetric.opsPlus => 'wRC+ 1위',
      LeaderboardMetric.war => 'WAR 1위',
    };
  }

  String _pitchingLeaderSummary(LeaderboardMetric metric, RecordLeader leader) {
    return '${_briefMetricLabel(metric)} · ${_pitchingMetricValue(metric, leader)}';
  }

  String _pitchingMetricValue(LeaderboardMetric metric, RecordLeader leader) {
    if (metric == LeaderboardMetric.wins) {
      return '${leader.value}승';
    }
    if (metric == LeaderboardMetric.saves) {
      return '${leader.value}SV';
    }
    if (metric == LeaderboardMetric.strikeouts) {
      return '${leader.value}K';
    }
    return leader.value;
  }

  List<_MetricSnapshot> _metricSnapshots(RecordsOverview overview) {
    final colors = AppTheme.colorsOf(context);
    return [
      _MetricSnapshot(
        metric: LeaderboardMetric.avg,
        title: '타율 리더',
        description: '컨택과 출루 흐름의 첫 기준',
        leaders: overview.avgLeaders,
        color: colors.readableAccent(AppColors.accent),
      ),
      _MetricSnapshot(
        metric: LeaderboardMetric.hr,
        title: '홈런왕 경쟁',
        description: '장타 한 방의 순위 변화',
        leaders: overview.hrLeaders,
        color: colors.readableAccent(AppColors.ballYellow),
      ),
      _MetricSnapshot(
        metric: LeaderboardMetric.ops,
        title: 'OPS 생산력',
        description: '출루와 장타를 함께 보는 지표',
        leaders: overview.opsLeaders,
        color: colors.readableAccent(AppColors.positive),
      ),
      _MetricSnapshot(
        metric: LeaderboardMetric.opsPlus,
        title: LeaderboardMetric.opsPlus.title,
        description: '리그 OPS 리더군 기준 환산',
        leaders: overview.opsPlusLeaders,
        color: colors.readableAccent(const Color(0xFF7B5CFF)),
      ),
      _MetricSnapshot(
        metric: LeaderboardMetric.era,
        title: 'ERA 마운드',
        description: '낮을수록 강한 선발 경쟁',
        leaders: overview.eraLeaders,
        color: colors.readableAccent(AppColors.live),
      ),
      _MetricSnapshot(
        metric: LeaderboardMetric.wins,
        title: '다승',
        description: '선발 승수 흐름',
        leaders: overview.winLeaders,
        color: colors.readableAccent(AppColors.positive),
      ),
      _MetricSnapshot(
        metric: LeaderboardMetric.saves,
        title: '세이브',
        description: '마무리 경쟁',
        leaders: overview.saveLeaders,
        color: colors.readableAccent(AppColors.ballYellow),
      ),
      _MetricSnapshot(
        metric: LeaderboardMetric.strikeouts,
        title: '탈삼진',
        description: '구위 지표',
        leaders: overview.strikeoutLeaders,
        color: colors.readableAccent(AppColors.accent),
      ),
    ];
  }

  List<_MetricSnapshot> _metricSnapshotsForGroup(
    RecordsOverview overview,
    LeaderboardPlayerGroup group,
  ) {
    final snapshots = {
      for (final snapshot in _metricSnapshots(overview))
        snapshot.metric: snapshot,
    };
    return [
      for (final metric in group.metrics)
        if (snapshots[metric] != null) snapshots[metric]!,
    ];
  }

  List<_MetricSnapshot> _pitcherMetricSnapshots(RecordsOverview overview) {
    return _metricSnapshotsForGroup(
      overview,
      LeaderboardPlayerGroup.pitcher,
    ).where((snapshot) => snapshot.leaders.isNotEmpty).toList();
  }

  String _leaderGapText(LeaderboardMetric metric, List<RecordLeader> leaders) {
    if (leaders.isEmpty) {
      return '데이터 준비 중';
    }
    if (leaders.length < 2) {
      return '단독 1위';
    }

    final first = double.tryParse(leaders[0].value);
    final second = double.tryParse(leaders[1].value);
    if (first == null || second == null) {
      return '2위 ${leaders[1].value}';
    }

    if (metric == LeaderboardMetric.era) {
      final diff = second - first;
      return diff > 0 ? '2위보다 ${diff.toStringAsFixed(2)} 낮음' : '공동 선두권';
    }

    final diff = first - second;
    if (diff <= 0) {
      return '공동 선두권';
    }
    if (metric == LeaderboardMetric.hr ||
        metric == LeaderboardMetric.opsPlus ||
        metric == LeaderboardMetric.wins ||
        metric == LeaderboardMetric.saves ||
        metric == LeaderboardMetric.strikeouts) {
      return '2위와 +${diff.round()}';
    }
    return '2위와 +${diff.toStringAsFixed(3)}';
  }
}

class _RecordsBackdrop extends StatelessWidget {
  const _RecordsBackdrop();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    return IgnorePointer(
      child: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isLight
                    ? [colors.background, colors.background, colors.cardSub]
                    : [
                        const Color(0xFF080808),
                        colors.background,
                        colors.background,
                      ],
                stops: const [0, 0.48, 1],
              ),
            ),
            child: SizedBox.expand(),
          ),
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: 280,
            child: Opacity(
              opacity: isLight ? 0.16 : 1,
              child: Image.asset(
                VisualAssets.recordsStadiumBackdrop,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: 320,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isLight
                      ? [
                          colors.background.withValues(alpha: 0.1),
                          colors.background.withValues(alpha: 0.72),
                          colors.background,
                        ]
                      : [
                          Colors.black.withValues(alpha: 0.18),
                          Colors.black.withValues(alpha: 0.48),
                          colors.background,
                        ],
                  stops: const [0, 0.52, 1],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricSnapshot {
  final LeaderboardMetric metric;
  final String title;
  final String description;
  final List<RecordLeader> leaders;
  final Color color;

  const _MetricSnapshot({
    required this.metric,
    required this.title,
    required this.description,
    required this.leaders,
    required this.color,
  });

  RecordLeader? get topLeader => leaders.isEmpty ? null : leaders.first;
}
