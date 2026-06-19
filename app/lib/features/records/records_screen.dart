import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../core/widgets/dev_console.dart';
import '../../data/api/api_client.dart';
import '../../data/models/player.dart';
import '../../data/models/records_overview.dart';
import '../../data/models/team_records_bundle.dart';
import '../../data/models/team_stats.dart';
import '../../data/providers.dart';

enum PlayerListFilter { all, entryOnly, reserveOnly }

enum PlayerSortOption { name, avg, ops, era, whip }

const firstSupportedRecordsSeason = 2002;

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
  int? _teamRecordsLoadStartedAtMicros;
  String? _lastTeamRecordsLogKey;
  String? _lastTeamRecordsDiagKey;

  @override
  void initState() {
    super.initState();
    _selectedSeason = DateTime.now().year;
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
        child: AppPageFrame(
          child: RefreshIndicator(
            onRefresh: _refreshOverview,
            color: AppColors.live,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'RECORDS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textDisabled,
                              letterSpacing: 0.8,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '기록실',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              height: 1.05,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '팀을 먼저 고르면 선수 기록과 리그 리더가 한 화면에 보입니다.',
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
                const SizedBox(height: 14),
                _seasonSelector(),
                const SizedBox(height: 14),
                overviewAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (error, stackTrace) =>
                      _recordsOverviewErrorCard(error),
                  data: (overview) => Column(
                    children: [
                      _featuredCards(overview),
                      const SizedBox(height: 14),
                      _leaderboardCard('리그 타율 리더보드', overview.avgLeaders),
                      const SizedBox(height: 10),
                      _leaderboardCard('리그 홈런왕 순위', overview.hrLeaders),
                      const SizedBox(height: 10),
                      _leaderboardCard('리그 OPS 리더보드', overview.opsLeaders),
                      const SizedBox(height: 10),
                      _leaderboardCard(
                        LeaderboardMetric.opsPlus.title,
                        overview.opsPlusLeaders,
                        metric: LeaderboardMetric.opsPlus,
                      ),
                      const SizedBox(height: 10),
                      _leaderboardCard('리그 ERA 리더보드', overview.eraLeaders),
                      const SizedBox(height: 10),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
                TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: '팀 검색',
                    hintStyle: const TextStyle(color: AppColors.textDisabled),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.textDisabled,
                    ),
                    filled: true,
                    fillColor: AppColors.card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
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
                    padding: const EdgeInsets.only(top: 48),
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
    );
  }

  Widget _teamChooserCard(KboTeam team, {required bool isMyTeam}) {
    return AppPressable(
      onTap: () => context.push('/records/team/${team.id}'),
      pressedScale: 0.97,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isMyTeam ? team.primaryColor : AppColors.divider,
          ),
        ),
        child: Row(
          children: [
            CachedNetworkImage(
              imageUrl: team.logoUrl,
              width: 40,
              height: 40,
              memCacheWidth: 120,
              memCacheHeight: 120,
              errorWidget: (_, _, _) => _logoFallback(team.shortName, 40),
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
                              color: team.primaryColor.withValues(alpha: 0.55),
                            ),
                          ),
                          child: const Text(
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
            const Icon(Icons.chevron_right, color: AppColors.textDisabled),
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
                            style: const TextStyle(
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
                      CachedNetworkImage(
                        imageUrl: team.logoUrl,
                        width: 40,
                        height: 40,
                        memCacheWidth: 120,
                        memCacheHeight: 120,
                        errorWidget: (_, _, _) =>
                            _logoFallback(team.shortName, 40),
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
                  data: (teamRecords) => _teamStatsCard(teamRecords.teamStats),
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
                          children: const [
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
                            const SizedBox(
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
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textDisabled,
                                ),
                              ),
                            ),
                          ],
                        ),
                        data: (teamRecords) => _buildList(teamRecords.players),
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
            const Icon(
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
                    style: const TextStyle(
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
          style: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
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
                      style: const TextStyle(
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
                      style: const TextStyle(
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
                const Icon(Icons.chevron_right, color: AppColors.textDisabled),
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
    final photoUrl = player.imageUrl;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: photoUrl,
          width: 52,
          height: 52,
          memCacheWidth: 156,
          memCacheHeight: 156,
          fit: BoxFit.cover,
          placeholder: (_, _) => _playerPhotoFallback(player.number, team),
          errorWidget: (_, _, _) => _playerPhotoFallback(player.number, team),
        ),
      );
    }
    return _playerPhotoFallback(player.number, team);
  }

  Widget _playerPhotoFallback(int number, KboTeam? team) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: team?.primaryColor.withValues(alpha: 0.14) ?? AppColors.cardSub,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.person_rounded,
        color: team?.primaryColor ?? AppColors.textSecondary,
        size: 28,
      ),
    );
  }

  Widget _numberBadge(int number, KboTeam? team) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (team?.primaryColor ?? AppColors.textSecondary).withValues(
          alpha: 0.14,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$number',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: team?.primaryColor ?? AppColors.textSecondary,
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

  Widget _logoFallback(String text, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.cardSub,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _seasonSelector() {
    final seasons = [
      for (
        int year = DateTime.now().year;
        year >= firstSupportedRecordsSeason;
        year--
      )
        year,
    ];
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Text(
            '시즌',
            style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
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
                      style: const TextStyle(fontSize: 14),
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
          style: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
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
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _featuredCards(RecordsOverview overview) {
    final avgLeader = _seasonLeaderCard('시즌 타율 리더', overview.avgLeaders);
    final eraLeader = _seasonLeaderCard('시즌 ERA 리더', overview.eraLeaders);
    final hrLeader = _seasonLeaderCard('시즌 홈런왕', overview.hrLeaders);
    final opsLeader = _seasonLeaderCard('시즌 OPS 리더', overview.opsLeaders);
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _featuredCard(avgLeader)),
            const SizedBox(width: 10),
            Expanded(child: _featuredCard(eraLeader)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _featuredCard(hrLeader)),
            const SizedBox(width: 10),
            Expanded(child: _featuredCard(opsLeader)),
          ],
        ),
      ],
    );
  }

  FeaturedPlayerCard _seasonLeaderCard(
    String label,
    List<RecordLeader> leaders,
  ) {
    if (leaders.isEmpty) {
      return FeaturedPlayerCard(label: label);
    }
    final leader = leaders.first;
    return FeaturedPlayerCard(
      label: label,
      playerId: leader.playerId,
      playerType: leader.playerType,
      name: leader.name,
      teamId: leader.teamId,
      headline: '${_metricLabelFromFeaturedLabel(label)} ${leader.value}',
      imageUrl: kboPlayerImageUrl(
        season: _selectedSeason,
        playerId: leader.playerId,
      ),
    );
  }

  String _metricLabelFromFeaturedLabel(String label) {
    if (label.contains('타율')) return '타율';
    if (label.contains('홈런')) return '홈런';
    if (label.contains('ERA')) return 'ERA';
    if (label.contains('OPS')) return 'OPS';
    return '기록';
  }

  Widget _featuredCard(FeaturedPlayerCard card) {
    final team = KboTeams.byId(card.teamId ?? '');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card.label,
            style: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (card.imageUrl != null && card.imageUrl!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: card.imageUrl!,
                    width: 56,
                    height: 72,
                    memCacheWidth: 168,
                    memCacheHeight: 216,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) =>
                        _logoFallback(team?.shortName ?? '', 56),
                  ),
                )
              else
                _logoFallback(team?.shortName ?? '', 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.name ?? '-',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      card.headline ?? '-',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                    if (card.summary?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 6),
                      Text(
                        card.summary!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _leaderboardCard(
    String title,
    List<RecordLeader> leaders, {
    LeaderboardMetric? metric,
  }) {
    final resolvedMetric = metric ?? _metricFromTitle(title);
    final supported = resolvedMetric?.supportedByOfficialSource ?? true;

    return AppPressable(
      onTap: resolvedMetric == null
          ? null
          : () => context.push(
              '/records/leaderboard/${resolvedMetric.key}?season=$_selectedSeason',
            ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  supported ? '전체 보기' : '준비 중',
                  style: TextStyle(
                    fontSize: 12,
                    color: supported
                        ? AppColors.textSecondary
                        : AppColors.textDisabled,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: supported
                      ? AppColors.textSecondary
                      : AppColors.textDisabled,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (leaders.isEmpty)
              const Text(
                '현재 공식 소스 기준 리더보드 준비 중',
                style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
              )
            else
              for (final leader in leaders)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${leader.rank}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textDisabled,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          leader.name,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        leader.value,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
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

  LeaderboardMetric? _metricFromTitle(String title) {
    for (final metric in LeaderboardMetric.values) {
      if (metric.title == title) {
        return metric;
      }
    }
    return null;
  }
}
