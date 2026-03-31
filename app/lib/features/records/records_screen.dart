import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/dev_console.dart';
import '../../data/models/player.dart';
import '../../data/models/records_overview.dart';
import '../../data/models/team_records_bundle.dart';
import '../../data/models/team_stats.dart';
import '../../data/providers.dart';

enum PlayerListFilter { all, entryOnly, reserveOnly }
enum PlayerSortOption { name, avg, ops, era, whip }

class RecordsScreen extends ConsumerStatefulWidget {
  final String? teamId;

  const RecordsScreen({super.key, this.teamId});

  @override
  ConsumerState<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends ConsumerState<RecordsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  PlayerListFilter _filter = PlayerListFilter.all;
  PlayerSortOption _sort = PlayerSortOption.avg;
  String _searchQuery = '';
  late int _selectedSeason;
  int? _teamRecordsLoadStartedAtMicros;
  String? _lastTeamRecordsLogKey;

  @override
  void initState() {
    super.initState();
    _selectedSeason = DateTime.now().year;
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {
        _sort = _tabController.index == 0 ? PlayerSortOption.avg : PlayerSortOption.era;
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            const Text('기록실', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              '팀을 선택하면 해당 팀의 선수 기록실로 이동합니다.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            _seasonSelector(),
            const SizedBox(height: 14),
            overviewAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (error, stackTrace) => const SizedBox.shrink(),
              data: (overview) => Column(
                children: [
                  _featuredCards(overview),
                  const SizedBox(height: 14),
                  _leaderboardCard('리그 타율 리더보드', overview.avgLeaders),
                  const SizedBox(height: 10),
                  _leaderboardCard('리그 홈런 리더보드', overview.hrLeaders),
                  const SizedBox(height: 10),
                  _leaderboardCard('리그 OPS 리더보드', overview.opsLeaders),
                  const SizedBox(height: 10),
                  _leaderboardCard('리그 ERA 리더보드', overview.eraLeaders),
                  const SizedBox(height: 14),
                ],
              ),
            ),
            TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: '팀 검색',
                hintStyle: const TextStyle(color: AppColors.textDisabled),
                prefixIcon: const Icon(Icons.search, color: AppColors.textDisabled),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 14),
            for (final team in visibleTeams)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _teamChooserCard(team, isMyTeam: myTeamId == team.id),
              ),
            if (visibleTeams.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: Center(
                  child: Text('검색 결과가 없습니다', style: TextStyle(color: AppColors.textDisabled)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _teamChooserCard(KboTeam team, {required bool isMyTeam}) {
    return GestureDetector(
      onTap: () => context.push('/records/team/${team.id}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isMyTeam ? team.primaryColor : AppColors.divider),
        ),
        child: Row(
          children: [
            CachedNetworkImage(
              imageUrl: team.logoUrl,
              width: 34,
              height: 34,
              errorWidget: (_, _, _) => _logoFallback(team.shortName, 34),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(team.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                      if (isMyTeam)
                        Text('마이팀', style: TextStyle(fontSize: 12, color: team.primaryColor, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isMyTeam ? '마이팀 기록실 열기' : '선수 기록 보기',
                    style: TextStyle(
                      fontSize: 12,
                      color: isMyTeam ? team.primaryColor : AppColors.textSecondary,
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
    final teamRecordsAsync = ref.watch(teamRecordsProvider('$teamId|$_selectedSeason'));
    _logTeamRecordsLoad(teamId, teamRecordsAsync);

    return Scaffold(
      body: SafeArea(
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
                        const Text('기록실', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(
                          '${team?.name ?? teamId} $_selectedSeason 시즌 기록실',
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (team != null)
                    CachedNetworkImage(
                      imageUrl: team.logoUrl,
                      width: 34,
                      height: 34,
                      errorWidget: (_, _, _) => _logoFallback(team.shortName, 34),
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
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: AppColors.textPrimary,
                    borderRadius: BorderRadius.circular(12),
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
                  Expanded(child: _filterButton(label: '전체', selected: _filter == PlayerListFilter.all, onTap: () => setState(() => _filter = PlayerListFilter.all))),
                  const SizedBox(width: 8),
                  Expanded(child: _filterButton(label: '엔트리', selected: _filter == PlayerListFilter.entryOnly, onTap: () => setState(() => _filter = PlayerListFilter.entryOnly))),
                  const SizedBox(width: 8),
                  Expanded(child: _filterButton(label: '엔트리 제외', selected: _filter == PlayerListFilter.reserveOnly, onTap: () => setState(() => _filter = PlayerListFilter.reserveOnly))),
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
              child: teamRecordsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.live)),
                error: (error, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '선수 기록을 불러올 수 없습니다',
                        style: TextStyle(color: AppColors.textDisabled),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => context.push('/diagnostics'),
                        child: const Text('진단 보기'),
                      ),
                    ],
                  ),
                ),
                data: (teamRecords) => _buildList(teamRecords.players),
              ),
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
    if (!teamRecordsAsync.hasValue) {
      _teamRecordsLoadStartedAtMicros ??=
          DateTime.now().microsecondsSinceEpoch;
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

  Widget _buildList(List<PlayerProfile> players) {
    final filtered = _sortPlayers(_applyFilters(players));
    final entryPlayers = filtered.where((player) => player.rosterGroup == PlayerRosterGroup.entry).toList();
    final reservePlayers = filtered.where((player) => player.rosterGroup == PlayerRosterGroup.reserve).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _summaryCard(entryPlayers.length, reservePlayers.length),
        if (entryPlayers.isNotEmpty) ...[
          const SizedBox(height: 18),
          _sectionTitle('팀 엔트리'),
          const SizedBox(height: 10),
          ...entryPlayers.map(_playerCard),
        ],
        if (reservePlayers.isNotEmpty) ...[
          const SizedBox(height: 18),
          _sectionTitle('엔트리 제외 / 이탈'),
          const SizedBox(height: 10),
          ...reservePlayers.map(_playerCard),
        ],
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Center(child: Text('조건에 맞는 선수가 없습니다', style: TextStyle(color: AppColors.textDisabled))),
          ),
      ],
    );
  }

  List<PlayerProfile> _applyFilters(List<PlayerProfile> players) {
    final targetType = _tabController.index == 0 ? PlayerType.hitter : PlayerType.pitcher;
    var filtered = players.where((player) => player.playerType == targetType).toList();

    switch (_filter) {
      case PlayerListFilter.entryOnly:
        filtered = filtered.where((player) => player.rosterGroup == PlayerRosterGroup.entry).toList();
        break;
      case PlayerListFilter.reserveOnly:
        filtered = filtered.where((player) => player.rosterGroup == PlayerRosterGroup.reserve).toList();
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
      return const [PlayerSortOption.name, PlayerSortOption.avg, PlayerSortOption.ops];
    }
    return const [PlayerSortOption.name, PlayerSortOption.era, PlayerSortOption.whip];
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
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
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
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textDisabled)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _sectionTitle(String title) => Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700));

  Widget _playerCard(PlayerProfile player) {
    final team = KboTeams.byId(player.teamId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => context.push('/records/player/${player.id}?season=$_selectedSeason'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: team?.primaryColor.withValues(alpha: 0.14) ?? AppColors.cardSub,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text('${player.number}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(player.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                        const SizedBox(width: 8),
                        _statusBadge(player),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${player.roleLabel} · ${player.position} · ${player.handedness}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 10),
                    Text(player.headlineStat, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(player.secondaryStat, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    if (player.statusNote != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        player.statusNote!,
                        style: TextStyle(fontSize: 12, color: player.status == PlayerAvailabilityStatus.injured ? AppColors.live : AppColors.textDisabled),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.textDisabled),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(PlayerProfile player) {
    switch (player.status) {
      case PlayerAvailabilityStatus.available:
        return _pill('정상', AppColors.positive);
      case PlayerAvailabilityStatus.injured:
        return _pill('부상', AppColors.live);
      case PlayerAvailabilityStatus.inactive:
        return _pill('엔트리 제외', AppColors.textDisabled);
    }
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _filterButton({required String label, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: selected ? null : Border.all(color: AppColors.divider),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? AppColors.background : AppColors.textSecondary)),
      ),
    );
  }

  Widget _sortChip({required String label, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.cardSub : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppColors.textSecondary : AppColors.divider),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, color: selected ? AppColors.textPrimary : AppColors.textDisabled, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }

  Widget _logoFallback(String text, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: AppColors.cardSub, borderRadius: BorderRadius.circular(size / 2)),
      alignment: Alignment.center,
      child: Text(text, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
    );
  }

  Widget _seasonSelector() {
    final seasons = [for (int year = DateTime.now().year; year >= 2020; year--) year];
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Text('시즌', style: TextStyle(fontSize: 12, color: AppColors.textDisabled)),
          const Spacer(),
          DropdownButton<int>(
            value: _selectedSeason,
            dropdownColor: AppColors.card,
            underline: const SizedBox.shrink(),
            items: seasons
                .map((season) => DropdownMenuItem<int>(
                      value: season,
                      child: Text('$season', style: const TextStyle(fontSize: 14)),
                    ))
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _teamStatColumn(
              '팀 타격',
              [
                'AVG ${teamStats.hitting['AVG'] ?? '-'}',
                'HR ${teamStats.hitting['HR'] ?? '-'}',
                'OPS ${teamStats.hitting['OPS'] ?? '-'}',
              ],
            ),
          ),
          Container(width: 1, height: 56, color: AppColors.divider),
          Expanded(
            child: _teamStatColumn(
              '팀 투수',
              [
                'ERA ${teamStats.pitching['ERA'] ?? '-'}',
                'WHIP ${teamStats.pitching['WHIP'] ?? '-'}',
                'SV ${teamStats.pitching['SV'] ?? '-'}',
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamStatColumn(String title, List<String> lines) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 12, color: AppColors.textDisabled)),
        const SizedBox(height: 8),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(line, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  Widget _featuredCards(RecordsOverview overview) {
    return Row(
      children: [
        Expanded(child: _featuredCard(overview.todayPlayer)),
        const SizedBox(width: 10),
        Expanded(child: _featuredCard(overview.monthPlayer)),
      ],
    );
  }

  Widget _featuredCard(FeaturedPlayerCard card) {
    final team = KboTeams.byId(card.teamId ?? '');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(card.label, style: const TextStyle(fontSize: 12, color: AppColors.textDisabled)),
          const SizedBox(height: 10),
          Row(
            children: [
              if (card.imageUrl != null && card.imageUrl!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: card.imageUrl!,
                    width: 56,
                    height: 72,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => _logoFallback(team?.shortName ?? '', 56),
                  ),
                )
              else
                _logoFallback(team?.shortName ?? '', 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(card.name ?? '-', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(card.headline ?? '-', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Text(
                      card.summary ?? '-',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _leaderboardCard(String title, List<RecordLeader> leaders) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final leader in leaders)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text('${leader.rank}', style: const TextStyle(fontSize: 12, color: AppColors.textDisabled)),
                  ),
                  Expanded(
                    child: Text(leader.name, style: const TextStyle(fontSize: 13)),
                  ),
                  Text(
                    leader.value,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
