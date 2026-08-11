import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/team_data.dart';
import '../../core/constants/visual_assets.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/kbo_player_image_cache.dart';
import '../../core/utils/kbo_time.dart';
import '../../core/widgets/app_artwork_card.dart';
import '../../core/utils/game_status_label.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../core/widgets/dev_console.dart';
import '../../data/api/api_client.dart';
import '../../data/models/boxscore.dart';
import '../../data/models/game.dart';
import '../../data/models/player.dart';
import '../../data/models/records_overview.dart';
import '../../data/models/relay.dart';
import '../../data/models/schedule.dart';
import '../../data/models/ticketing.dart';
import '../../data/providers.dart';
import 'widgets/schedule_game_card.dart';

enum ScheduleViewMode { calendar, stadium, matchup }

enum _CalendarLegendStyle { dot, outline, filled }

enum ScheduleTeamFilter { all, myTeamOnly, otherTeamsOnly }

const _scheduleGameDetailOpenTimeout = Duration(seconds: 4);
const _scheduleGameDetailPlayerImagePrefetchTimeout = Duration(seconds: 8);
const _scheduleTeamPlayerImagePrefetchTimeout = Duration(seconds: 3);
const _scheduleGameDetailPlayerImagePrefetchLimit = 80;
const _eagerScheduleGameDetailWarmupEnabled = false;

@visibleForTesting
String formatScheduleTicketSummary(TicketInfo ticketInfo) {
  final openAt = ticketInfo.openAt;
  if (openAt == null) {
    return '${ticketInfo.vendorName} · 예매 시간 미정';
  }

  final kboOpenAt = kboCivilDateTime(openAt);
  final formatted = DateFormat('MM.dd HH:mm').format(kboOpenAt);
  final sourceLabel = ticketInfo.isInferred ? '예상 오픈' : '공식 오픈';
  return '${ticketInfo.vendorName} · $formatted KST $sourceLabel';
}

int _seasonFromGameId(String gameId) {
  if (gameId.length >= 4) {
    final parsed = int.tryParse(gameId.substring(0, 4));
    if (parsed != null) {
      return parsed;
    }
  }
  return kboCurrentSeason();
}

String _normalizePlayerNameForImagePrefetch(String value) {
  return value
      .replaceFirst(RegExp(r'^\d+\s*번?\s*타자\s*'), '')
      .replaceFirst(RegExp(r'^\d+번\s*'), '')
      .replaceFirst(RegExp(r'^(대타|대주자|투수|타자)\s+'), '')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[·ㆍ.]'), '')
      .trim();
}

Map<String, String> _playerImageUrlByName(
  Iterable<PlayerProfile> players,
  int season,
) {
  return {
    for (final player in players)
      if (player.name.isNotEmpty)
        _normalizePlayerNameForImagePrefetch(player.name):
            playerProfileImageUrl(player, season: season) ?? '',
  }..removeWhere((_, imageUrl) => imageUrl.isEmpty);
}

String? _resolvePlayerImageUrl(
  Map<String, String> imageByName,
  String rawName,
) {
  final normalizedTarget = _normalizePlayerNameForImagePrefetch(rawName);
  if (normalizedTarget.isEmpty) {
    return null;
  }
  final exact = imageByName[normalizedTarget];
  if (exact != null && exact.isNotEmpty) {
    return exact;
  }
  for (final entry in imageByName.entries) {
    if (entry.key.contains(normalizedTarget) ||
        normalizedTarget.contains(entry.key)) {
      return entry.value;
    }
  }
  return null;
}

String? _lineupStarterImageUrl(
  TeamLineupData teamLineup, {
  required Map<String, String> imageByName,
  required int season,
}) {
  final starterImageUrl = teamLineup.starterImageUrl?.trim() ?? '';
  if (starterImageUrl.isNotEmpty) {
    return starterImageUrl;
  }
  final starterId = teamLineup.starterId?.trim() ?? '';
  if (starterId.isNotEmpty) {
    return kboPlayerImageUrl(season: season, playerId: starterId);
  }
  return _resolvePlayerImageUrl(imageByName, teamLineup.starterName ?? '');
}

String? _lineupEntryImageUrl(
  LineupEntry entry, {
  required Map<String, String> imageByName,
  required int season,
}) {
  final imageUrl = entry.imageUrl?.trim() ?? '';
  if (imageUrl.isNotEmpty) {
    return imageUrl;
  }
  final playerId = entry.playerId?.trim() ?? '';
  if (playerId.isNotEmpty) {
    return kboPlayerImageUrl(season: season, playerId: playerId);
  }
  return _resolvePlayerImageUrl(imageByName, entry.name);
}

List<String> _playerProfileImageUrlsForPrefetch(
  Iterable<PlayerProfile> players,
  int season,
) {
  final imageUrls = <String>[];
  for (final player in players) {
    final imageUrl = playerProfileImageUrl(player, season: season)?.trim();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      imageUrls.add(imageUrl);
    }
  }
  return imageUrls;
}

class _StadiumScheduleItem {
  final String date;
  final ScheduleGame game;

  const _StadiumScheduleItem({required this.date, required this.game});
}

class _MatchupScheduleItem {
  final String date;
  final ScheduleGame game;

  const _MatchupScheduleItem({required this.date, required this.game});
}

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  static const _calendarInitialPage = 1200;
  late DateTime _currentMonth;
  late final PageController _calendarPageController;
  int? _selectedDay;
  ScheduleViewMode _viewMode = ScheduleViewMode.calendar;
  ScheduleTeamFilter _teamFilter = ScheduleTeamFilter.all;
  String? _stadiumTeamId;
  String? _matchupFirstTeamId;
  String? _matchupSecondTeamId;
  final Map<String, GlobalKey> _stadiumSectionKeys = {};
  int? _scheduleLoadStartedAtMicros;
  String? _lastScheduleLoadLogKey;
  int? _pendingSelectedDay;
  bool _gameDetailNavigationInFlight = false;
  late String _observedKboDate;

  @override
  void initState() {
    super.initState();
    final now = kboCivilDateTime();
    _currentMonth = DateTime(now.year, now.month);
    _calendarPageController = PageController(initialPage: _calendarInitialPage);
    _selectedDay = now.day;
    _observedKboDate = kboDateKey();
    _scheduleLoadStartedAtMicros = DateTime.now().microsecondsSinceEpoch;
  }

  @override
  void dispose() {
    _calendarPageController.dispose();
    super.dispose();
  }

  String get _yearMonth =>
      '${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}';

  Future<void> _refreshSchedule() async {
    final season = _currentMonth.year;
    if (_viewMode == ScheduleViewMode.matchup) {
      for (final yearMonth in kboScheduleSeasonMonths(season)) {
        ref.invalidate(scheduleProvider(yearMonth));
      }
      ref.invalidate(seasonScheduleProvider(season));
      await ref.read(seasonScheduleProvider(season).future);
      return;
    }

    ref.invalidate(scheduleProvider(_yearMonth));
    ref.invalidate(seasonScheduleProvider(season));
    await ref.read(scheduleProvider(_yearMonth).future);
  }

  void _openGameDetail(ScheduleGame scheduleGame) {
    if (_gameDetailNavigationInFlight) {
      return;
    }
    _gameDetailNavigationInFlight = true;
    final navigation = context.push(
      _gameDetailLocation(
        scheduleGame.gameId,
        tab: _defaultTabForScheduleGame(scheduleGame),
      ),
    );
    unawaited(
      navigation.whenComplete(() => _gameDetailNavigationInFlight = false),
    );
    unawaited(_refreshGameDetailInBackground(scheduleGame));
  }

  Future<void> _refreshGameDetailInBackground(ScheduleGame scheduleGame) async {
    final gameId = scheduleGame.gameId;

    try {
      ref.invalidate(gameProvider(gameId));
      final game = await ref
          .read(gameProvider(gameId).future)
          .timeout(_scheduleGameDetailOpenTimeout);
      if (_eagerScheduleGameDetailWarmupEnabled && game != null) {
        unawaited(
          _warmGameDetailFirstTab(
            game,
            tab: _defaultTabForGame(game, fallback: scheduleGame),
          ),
        );
      }
    } catch (error) {
      DevConsole.instance.warn(
        'SCHEDULE game detail background refresh failed: $gameId $error',
      );
    }
  }

  Future<void> _warmGameDetailFirstTab(
    Game game, {
    required String? tab,
  }) async {
    RelayData? relayData;
    switch (tab) {
      case 'relay':
        ref.invalidate(relayDataProvider(game.gameId));
        relayData = await _readScheduleWarmupProvider<RelayData>(
          'relay',
          ref.read(relayDataProvider(game.gameId).future),
        );
        break;
      case null:
        break;
    }
    await _warmGameDetailPlayerImages(game, relayData: relayData);
  }

  Future<T?> _readScheduleWarmupProvider<T>(String label, Future<T> future) {
    return future
        .timeout(_scheduleGameDetailOpenTimeout)
        .then<T?>((value) {
          return value;
        })
        .catchError((Object error, StackTrace stackTrace) {
          DevConsole.instance.warn(
            'SCHEDULE game detail $label warmup skipped: $error',
          );
          return null;
        });
  }

  String _gameDetailLocation(String gameId, {required String? tab}) {
    return Uri(
      path: '/game/$gameId',
      queryParameters: tab == null ? null : {'tab': tab},
    ).toString();
  }

  String? _defaultTabForGame(Game? game, {required ScheduleGame fallback}) {
    if (game?.status == GameStatus.live) {
      return 'relay';
    }
    return _defaultTabForScheduleGame(fallback);
  }

  String? _defaultTabForScheduleGame(ScheduleGame game) {
    return _isLiveScheduleGame(game) ? 'relay' : null;
  }

  bool _isLiveScheduleGame(ScheduleGame game) {
    final status = game.status.trim().toUpperCase();
    if (status == 'LIVE' || status == 'IN_PROGRESS') {
      return true;
    }
    final label = game.statusLabel?.trim() ?? '';
    return label.contains('진행') || label.toUpperCase().contains('LIVE');
  }

  Future<void> _warmGameDetailPlayerImages(
    Game game, {
    required RelayData? relayData,
  }) async {
    if (!mounted) {
      return;
    }

    try {
      final season = _seasonFromGameId(game.gameId);
      final teamPlayersFuture = _teamPlayersForImagePrefetch(game, season);
      ref.invalidate(gameLineupProvider(game.gameId));
      final lineupDataFuture = _readScheduleWarmupProvider<GameLineupData>(
        'lineup image source',
        ref.read(gameLineupProvider(game.gameId).future),
      );
      final teamPlayers = await teamPlayersFuture;
      final lineupData = await lineupDataFuture;
      if (!mounted) {
        return;
      }

      final imageUrls = _gameDetailPlayerImageUrls(
        relayData: relayData,
        lineupData: lineupData,
        teamPlayers: teamPlayers,
        season: season,
      );
      if (imageUrls.isEmpty) {
        return;
      }
      await precacheKboPlayerImageUrls(
        context,
        imageUrls,
        limit: _scheduleGameDetailPlayerImagePrefetchLimit,
      ).timeout(
        _scheduleGameDetailPlayerImagePrefetchTimeout,
        onTimeout: () {},
      );
    } catch (error) {
      DevConsole.instance.warn(
        'SCHEDULE game detail image prefetch skipped: ${game.gameId} $error',
      );
    }
  }

  Future<List<PlayerProfile>> _teamPlayersForImagePrefetch(
    Game game,
    int season,
  ) async {
    final groups = await Future.wait([
      _readTeamPlayersForImagePrefetch(game.away.teamId, season),
      _readTeamPlayersForImagePrefetch(game.home.teamId, season),
    ]);
    return [for (final group in groups) ...group];
  }

  Future<List<PlayerProfile>> _readTeamPlayersForImagePrefetch(
    String teamId,
    int season,
  ) async {
    if (teamId.isEmpty) {
      return const [];
    }
    try {
      return await ref
          .read(teamPlayersProvider('$teamId|$season').future)
          .timeout(_scheduleTeamPlayerImagePrefetchTimeout);
    } catch (error) {
      DevConsole.instance.warn(
        'SCHEDULE game detail team image source skipped: $teamId $season $error',
      );
      return const [];
    }
  }

  List<String> _gameDetailPlayerImageUrls({
    required RelayData? relayData,
    required GameLineupData? lineupData,
    required Iterable<PlayerProfile> teamPlayers,
    required int season,
  }) {
    final imageUrls = <String>[];
    final seen = <String>{};
    final imageByName = _playerImageUrlByName(teamPlayers, season);

    void addUrl(String? rawUrl) {
      final imageUrl = rawUrl?.trim() ?? '';
      if (imageUrl.isEmpty || !seen.add(imageUrl)) {
        return;
      }
      imageUrls.add(imageUrl);
    }

    final currentAtBat = relayData?.currentAtBat;
    if (currentAtBat != null) {
      addUrl(
        currentAtBat.batterImageUrl.isNotEmpty
            ? currentAtBat.batterImageUrl
            : _resolvePlayerImageUrl(imageByName, currentAtBat.batterName),
      );
      addUrl(
        currentAtBat.pitcherImageUrl.isNotEmpty
            ? currentAtBat.pitcherImageUrl
            : _resolvePlayerImageUrl(imageByName, currentAtBat.pitcherName),
      );
    }

    void addLineupUrls(TeamLineupData lineup, Iterable<PlayerProfile> players) {
      final lineupImageByName = _playerImageUrlByName(players, season);
      addUrl(
        _lineupStarterImageUrl(
          lineup,
          imageByName: lineupImageByName,
          season: season,
        ),
      );
      for (final entry in lineup.lineup) {
        addUrl(
          _lineupEntryImageUrl(
            entry,
            imageByName: lineupImageByName,
            season: season,
          ),
        );
      }
    }

    if (lineupData != null) {
      final awayPlayers = teamPlayers.where(
        (player) => player.teamId == lineupData.away.teamId,
      );
      final homePlayers = teamPlayers.where(
        (player) => player.teamId == lineupData.home.teamId,
      );
      addLineupUrls(lineupData.away, awayPlayers);
      addLineupUrls(lineupData.home, homePlayers);
    }

    for (final imageUrl in _playerProfileImageUrlsForPrefetch(
      teamPlayers,
      season,
    )) {
      addUrl(imageUrl);
    }

    return imageUrls.take(_scheduleGameDetailPlayerImagePrefetchLimit).toList();
  }

  GlobalKey _stadiumSectionKey(String yearMonth, String stadium) {
    return _stadiumSectionKeys.putIfAbsent(
      '$yearMonth::$stadium',
      () => GlobalKey(),
    );
  }

  void _scrollToStadium(String yearMonth, String stadium) {
    final sectionContext =
        _stadiumSectionKeys['$yearMonth::$stadium']?.currentContext;
    if (sectionContext == null) {
      return;
    }

    Scrollable.ensureVisible(
      sectionContext,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.04,
    );
  }

  void _changeMonth(int delta) {
    _goToMonth(
      DateTime(_currentMonth.year, _currentMonth.month + delta),
      animateCalendar: true,
    );
  }

  void _goToToday() {
    final now = kboCivilDateTime();
    _goToMonth(
      DateTime(now.year, now.month),
      selectedDay: now.day,
      animateCalendar: true,
    );
  }

  void _goToMonth(
    DateTime month, {
    int? selectedDay,
    bool animateCalendar = false,
  }) {
    final normalizedMonth = DateTime(month.year, month.month);
    final targetPage = _pageForMonth(normalizedMonth);

    if (_hasSingleCalendarClient()) {
      final currentPage = _calendarPageController.page?.round();
      if (currentPage != targetPage) {
        _pendingSelectedDay = selectedDay;
        if (animateCalendar) {
          unawaited(
            _calendarPageController.animateToPage(
              targetPage,
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeInOutCubic,
            ),
          );
        } else {
          _calendarPageController.jumpToPage(targetPage);
        }
        return;
      }
    }

    _pendingSelectedDay = null;
    _applyVisibleMonth(normalizedMonth, selectedDay: selectedDay);
  }

  void _applyVisibleMonth(DateTime month, {int? selectedDay}) {
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final nextSelectedDay = selectedDay ?? _selectedDay;

    setState(() {
      _currentMonth = DateTime(month.year, month.month);
      _selectedDay = nextSelectedDay?.clamp(1, lastDay);
    });
  }

  bool _hasSingleCalendarClient() {
    return _calendarPageController.hasClients &&
        _calendarPageController.positions.length == 1;
  }

  int _pageForMonth(DateTime month) {
    return _calendarInitialPage + _monthDeltaFromToday(month);
  }

  void _selectDate(DateTime date) {
    final selectedMonth = DateTime(date.year, date.month);
    final shouldMoveCalendar =
        selectedMonth.year != _currentMonth.year ||
        selectedMonth.month != _currentMonth.month;
    _goToMonth(
      selectedMonth,
      selectedDay: date.day,
      animateCalendar: shouldMoveCalendar,
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncKboDate(ref.watch(kboDateProvider));
    final scheduleAsync = ref.watch(scheduleProvider(_yearMonth));
    _logScheduleLoad(scheduleAsync);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            AppPageFrame(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMonthHeader(),
                  Expanded(child: _buildBody(scheduleAsync)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _syncKboDate(String nextDateKey) {
    if (nextDateKey == _observedKboDate) {
      return;
    }
    final previousDate = DateTime.tryParse(_observedKboDate);
    final nextDate = DateTime.tryParse(nextDateKey);
    _observedKboDate = nextDateKey;
    if (previousDate == null ||
        nextDate == null ||
        _currentMonth.year != previousDate.year ||
        _currentMonth.month != previousDate.month) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _goToMonth(
        DateTime(nextDate.year, nextDate.month),
        selectedDay: nextDate.day,
      );
    });
  }

  Widget _buildMonthHeader() {
    return SizedBox(
      key: const ValueKey('schedule-month-header'),
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 34),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat(
                      'MMM yyyy',
                      'en_US',
                    ).format(_currentMonth).toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSupporting,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '일정',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ),
            _HeaderIconButton(
              icon: Icons.chevron_left_rounded,
              semanticLabel: '이전 달',
              onTap: () => _changeMonth(-1),
            ),
            const SizedBox(width: 8),
            _HeaderIconButton(
              icon: Icons.chevron_right_rounded,
              semanticLabel: '다음 달',
              onTap: () => _changeMonth(1),
            ),
            const SizedBox(width: 8),
            _HeaderIconButton(
              icon: Icons.today_rounded,
              semanticLabel: '오늘로 이동',
              onTap: _goToToday,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AsyncValue<List<ScheduleDay>> scheduleAsync) {
    final days = scheduleAsync.asData?.value ?? const <ScheduleDay>[];
    final myTeamId = ref.watch(myTeamProvider);
    final filteredDays = _filterDays(days, myTeamId);
    final gameDays = <int>{};
    final myTeamDays = <int>{};
    for (final d in filteredDays) {
      final day = int.tryParse(d.date.split('-').last) ?? 0;
      gameDays.add(day);
      if (myTeamId != null) {
        final hasMyTeam = d.games.any(
          (g) => g.awayId == myTeamId || g.homeId == myTeamId,
        );
        if (hasMyTeam) myTeamDays.add(day);
      }
    }

    // 선택된 날짜의 경기 목록
    ScheduleDay? selectedSchedule;
    if (_selectedDay != null) {
      final dateStr =
          '${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}-${_selectedDay.toString().padLeft(2, '0')}';
      selectedSchedule = filteredDays
          .where((d) => d.date == dateStr)
          .firstOrNull;
    }

    if (_viewMode == ScheduleViewMode.calendar) {
      return _buildCalendarModeBody(scheduleAsync, selectedSchedule);
    }

    if (_viewMode == ScheduleViewMode.stadium) {
      return Column(
        children: [
          _buildControls(),
          Divider(color: AppColors.divider, height: 1),
          Expanded(child: _buildStadiumPager()),
        ],
      );
    }

    return Column(
      children: [
        _buildControls(),
        Divider(color: AppColors.divider, height: 1),
        Expanded(child: _buildMatchupBody()),
      ],
    );
  }

  Widget _buildCalendarModeBody(
    AsyncValue<List<ScheduleDay>> scheduleAsync,
    ScheduleDay? selectedSchedule,
  ) {
    final isInitialLoading =
        scheduleAsync.isLoading && scheduleAsync.asData == null;
    if (isInitialLoading) {
      return Column(
        children: [
          _buildControls(),
          _buildCalendarPager(context),
          Divider(color: AppColors.divider, height: 1),
          Expanded(child: _buildGameListLoading()),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshSchedule,
      color: AppColors.live,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          _buildControls(),
          _buildCalendarPager(context),
          Divider(color: AppColors.divider, height: 1),
          ...scheduleAsync.when<List<Widget>>(
            loading: () => [_buildGameListLoadingSection()],
            error: (error, _) => [_buildScheduleErrorContent(error)],
            data: (_) => _buildGameListItems(selectedSchedule),
          ),
        ],
      ),
    );
  }

  List<ScheduleDay> _filterDays(List<ScheduleDay> days, String? myTeamId) {
    if (_teamFilter == ScheduleTeamFilter.all || myTeamId == null) {
      return days;
    }

    final keepOnlyMyTeam = _teamFilter == ScheduleTeamFilter.myTeamOnly;
    final filtered = <ScheduleDay>[];

    for (final day in days) {
      final games = day.games.where((game) {
        final isMyTeamGame = game.awayId == myTeamId || game.homeId == myTeamId;
        return keepOnlyMyTeam ? isMyTeamGame : !isMyTeamGame;
      }).toList();

      if (games.isNotEmpty) {
        filtered.add(
          ScheduleDay(date: day.date, label: day.label, games: games),
        );
      }
    }

    return filtered;
  }

  List<ScheduleDay> _filterDaysBySelectedTeam(
    List<ScheduleDay> days,
    String? teamId,
  ) {
    if (teamId == null || teamId.isEmpty) {
      return days;
    }

    final filtered = <ScheduleDay>[];
    for (final day in days) {
      final games = day.games.where((game) {
        return game.awayId == teamId || game.homeId == teamId;
      }).toList();
      if (games.isNotEmpty) {
        filtered.add(
          ScheduleDay(date: day.date, label: day.label, games: games),
        );
      }
    }
    return filtered;
  }

  Widget _buildControls() {
    final hasMyTeam = ref.watch(myTeamProvider) != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final useCompactLabels = constraints.maxWidth <= 320;
              return Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _segmentedButton(
                        label: hasMyTeam
                            ? useCompactLabels
                                  ? '내 팀 우선'
                                  : '내 팀 먼저 보기'
                            : '달력 보기',
                        selected: _viewMode == ScheduleViewMode.calendar,
                        onTap: () => setState(
                          () => _viewMode = ScheduleViewMode.calendar,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _segmentedButton(
                        label: '구장별',
                        selected: _viewMode == ScheduleViewMode.stadium,
                        onTap: () => setState(
                          () => _viewMode = ScheduleViewMode.stadium,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _segmentedButton(
                        label: '매치업',
                        selected: _viewMode == ScheduleViewMode.matchup,
                        onTap: () => setState(
                          () => _viewMode = ScheduleViewMode.matchup,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          if (_viewMode == ScheduleViewMode.matchup)
            _buildMatchupTeamControls()
          else ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip(
                    label: '전체',
                    selected: _teamFilter == ScheduleTeamFilter.all,
                    onTap: () =>
                        setState(() => _teamFilter = ScheduleTeamFilter.all),
                  ),
                  if (hasMyTeam) ...[
                    const SizedBox(width: 8),
                    _filterChip(
                      label: '마이팀만',
                      selected: _teamFilter == ScheduleTeamFilter.myTeamOnly,
                      onTap: () => setState(
                        () => _teamFilter = ScheduleTeamFilter.myTeamOnly,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _filterChip(
                      label: '다른 경기',
                      selected:
                          _teamFilter == ScheduleTeamFilter.otherTeamsOnly,
                      onTap: () => setState(
                        () => _teamFilter = ScheduleTeamFilter.otherTeamsOnly,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_viewMode == ScheduleViewMode.calendar) ...[
              const SizedBox(height: 8),
              _legendRow(),
            ] else ...[
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip(
                      label: '전체 팀',
                      selected: _stadiumTeamId == null,
                      onTap: () => setState(() => _stadiumTeamId = null),
                    ),
                    ...KboTeams.teams.map((team) {
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _filterChip(
                          label: team.shortName,
                          selected: _stadiumTeamId == team.id,
                          onTap: () => setState(() => _stadiumTeamId = team.id),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _legendRow() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          _legendItem(
            AppColors.live,
            '경기 있는 날짜',
            style: _CalendarLegendStyle.outline,
          ),
          _legendItem(AppColors.accent, '마이팀 경기'),
          _legendItem(AppColors.textSupporting, '일반 경기'),
          _legendItem(
            AppColors.live,
            '선택한 날짜',
            style: _CalendarLegendStyle.filled,
          ),
        ],
      ),
    );
  }

  Widget _legendItem(
    Color color,
    String label, {
    _CalendarLegendStyle style = _CalendarLegendStyle.dot,
  }) {
    final marker = switch (style) {
      _CalendarLegendStyle.dot => BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      _CalendarLegendStyle.outline => BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(3),
      ),
      _CalendarLegendStyle.filled => BoxDecoration(
        color: color.withValues(alpha: 0.62),
        border: Border.all(color: color.withValues(alpha: 0.82)),
        borderRadius: BorderRadius.circular(3),
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: style == _CalendarLegendStyle.dot ? 8 : 11,
          height: style == _CalendarLegendStyle.dot ? 8 : 11,
          decoration: marker,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: AppColors.textSupporting),
        ),
      ],
    );
  }

  Widget _segmentedButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return AppPressable(
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
        onTap();
      },
      pressedScale: 0.97,
      semanticSelected: selected,
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.cardSub : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return AppPressable(
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
        onTap();
      },
      pressedScale: 0.96,
      semanticSelected: selected,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.cardSub : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.textSecondary
                : AppColors.divider.withValues(alpha: 0.72),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildMatchupTeamControls() {
    final myTeamId = ref.watch(myTeamProvider);
    final firstTeamId = _effectiveMatchupFirstTeamId(myTeamId);
    final secondTeamId = _effectiveMatchupSecondTeamId(firstTeamId);

    return Column(
      children: [
        _teamSelectRow(
          label: '팀 1',
          selectedTeamId: firstTeamId,
          disabledTeamId: secondTeamId,
          onSelect: _setMatchupFirstTeam,
        ),
        const SizedBox(height: 8),
        _teamSelectRow(
          label: '팀 2',
          selectedTeamId: secondTeamId,
          disabledTeamId: firstTeamId,
          onSelect: _setMatchupSecondTeam,
        ),
      ],
    );
  }

  Widget _teamSelectRow({
    required String label,
    required String selectedTeamId,
    required String disabledTeamId,
    required ValueChanged<String> onSelect,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSupporting,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: KboTeams.teams.map((team) {
                final selected = selectedTeamId == team.id;
                final disabled = disabledTeamId == team.id;
                return Padding(
                  padding: EdgeInsets.only(
                    left: team == KboTeams.teams.first ? 0 : 8,
                  ),
                  child: _teamChoiceChip(
                    team: team,
                    selected: selected,
                    disabled: disabled,
                    onTap: () => onSelect(team.id),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _teamChoiceChip({
    required KboTeam team,
    required bool selected,
    required bool disabled,
    required VoidCallback onTap,
  }) {
    final colors = AppTheme.colorsOf(context);
    final accent = colors.readableAccent(team.primaryColor);

    return IgnorePointer(
      ignoring: disabled,
      child: Opacity(
        opacity: disabled ? 0.38 : 1,
        child: AppPressable(
          onTap: disabled ? null : onTap,
          pressedScale: 0.96,
          semanticSelected: selected,
          child: Container(
            constraints: const BoxConstraints(minWidth: 46),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.24)
                  : AppColors.cardSub.withValues(alpha: 0.68),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.84)
                    : AppColors.divider.withValues(alpha: 0.72),
              ),
            ),
            child: Text(
              team.shortName,
              style: TextStyle(
                fontSize: 12,
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _effectiveMatchupFirstTeamId(String? myTeamId) {
    if (_isKnownTeam(_matchupFirstTeamId)) {
      return _matchupFirstTeamId!;
    }
    if (_isKnownTeam(myTeamId)) {
      return myTeamId!;
    }
    return KboTeams.teams.first.id;
  }

  String _effectiveMatchupSecondTeamId(String firstTeamId) {
    if (_isKnownTeam(_matchupSecondTeamId) &&
        _matchupSecondTeamId != firstTeamId) {
      return _matchupSecondTeamId!;
    }
    return _fallbackOpponentId(firstTeamId);
  }

  bool _isKnownTeam(String? teamId) {
    return teamId != null && KboTeams.byId(teamId) != null;
  }

  String _fallbackOpponentId(String teamId) {
    return KboTeams.teams
        .firstWhere(
          (team) => team.id != teamId,
          orElse: () => KboTeams.teams.first,
        )
        .id;
  }

  void _setMatchupFirstTeam(String teamId) {
    setState(() {
      _matchupFirstTeamId = teamId;
      if (_matchupSecondTeamId == null || _matchupSecondTeamId == teamId) {
        _matchupSecondTeamId = _fallbackOpponentId(teamId);
      }
    });
  }

  void _setMatchupSecondTeam(String teamId) {
    final firstTeamId = _effectiveMatchupFirstTeamId(ref.read(myTeamProvider));
    if (teamId == firstTeamId) {
      return;
    }
    setState(() => _matchupSecondTeamId = teamId);
  }

  Widget _buildCalendarPager(BuildContext context) {
    return SizedBox(
      height: _calendarPagerHeight(context),
      child: PageView.builder(
        controller: _calendarPageController,
        onPageChanged: (page) {
          final nextMonth = _monthForPage(page);
          final selectedDay = _pendingSelectedDay;
          _pendingSelectedDay = null;
          _applyVisibleMonth(nextMonth, selectedDay: selectedDay);
        },
        itemBuilder: (context, index) {
          final month = _monthForPage(index);
          final myTeamId = ref.watch(myTeamProvider);
          final yearMonth =
              '${month.year}-${month.month.toString().padLeft(2, '0')}';
          final scheduleAsync = ref.watch(scheduleProvider(yearMonth));

          return scheduleAsync.when(
            loading: () => _buildCalendar(month, const <int>{}, const <int>{}),
            error: (_, _) =>
                _buildCalendar(month, const <int>{}, const <int>{}),
            data: (days) {
              final filteredDays = _filterDays(days, myTeamId);
              final gameDays = <int>{};
              final myTeamDays = <int>{};
              for (final d in filteredDays) {
                final day = int.tryParse(d.date.split('-').last) ?? 0;
                gameDays.add(day);
                if (myTeamId != null) {
                  final hasMyTeam = d.games.any(
                    (g) => g.awayId == myTeamId || g.homeId == myTeamId,
                  );
                  if (hasMyTeam) myTeamDays.add(day);
                }
              }
              return _buildCalendar(month, gameDays, myTeamDays);
            },
          );
        },
      ),
    );
  }

  double _calendarPagerHeight(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final scaledTextAllowance = (textScale - 1).clamp(0.0, 1.4) * 18;
    if (viewportHeight < 700) {
      return 286 + scaledTextAllowance;
    }
    if (viewportHeight < 780) {
      return 310 + scaledTextAllowance;
    }
    return 322 + scaledTextAllowance;
  }

  Widget _buildStadiumPager() {
    return PageView.builder(
      controller: _calendarPageController,
      onPageChanged: (page) {
        final nextMonth = _monthForPage(page);
        final selectedDay = _pendingSelectedDay;
        _pendingSelectedDay = null;
        _applyVisibleMonth(nextMonth, selectedDay: selectedDay);
      },
      itemBuilder: (context, index) {
        final month = _monthForPage(index);
        final myTeamId = ref.watch(myTeamProvider);
        final yearMonth =
            '${month.year}-${month.month.toString().padLeft(2, '0')}';
        final scheduleAsync = ref.watch(scheduleProvider(yearMonth));

        return scheduleAsync.when(
          loading: _buildGameListLoading,
          error: (error, _) => RefreshIndicator(
            onRefresh: _refreshSchedule,
            color: AppColors.live,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [_buildScheduleErrorContent(error)],
            ),
          ),
          data: (days) {
            final filteredDays = _filterDays(days, myTeamId);
            final stadiumFilteredDays = _filterDaysBySelectedTeam(
              filteredDays,
              _stadiumTeamId,
            );
            return _buildStadiumList(yearMonth, stadiumFilteredDays);
          },
        );
      },
    );
  }

  Widget _buildMatchupBody() {
    final myTeamId = ref.watch(myTeamProvider);
    final firstTeamId = _effectiveMatchupFirstTeamId(myTeamId);
    final secondTeamId = _effectiveMatchupSecondTeamId(firstTeamId);
    final season = _currentMonth.year;
    final scheduleAsync = ref.watch(seasonScheduleProvider(season));

    return scheduleAsync.when(
      loading: _buildGameListLoading,
      error: (error, _) => RefreshIndicator(
        onRefresh: _refreshSchedule,
        color: AppColors.live,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [_buildScheduleErrorContent(error)],
        ),
      ),
      data: (days) => _buildMatchupList(
        season: season,
        items: _matchupItems(days, firstTeamId, secondTeamId),
        firstTeamId: firstTeamId,
        secondTeamId: secondTeamId,
      ),
    );
  }

  List<_MatchupScheduleItem> _matchupItems(
    List<ScheduleDay> days,
    String firstTeamId,
    String secondTeamId,
  ) {
    final items = <_MatchupScheduleItem>[];
    for (final day in days) {
      for (final game in day.games) {
        final gameTeamIds = {game.awayId, game.homeId};
        if (gameTeamIds.contains(firstTeamId) &&
            gameTeamIds.contains(secondTeamId)) {
          if (!_isPastScheduleDate(day.date) &&
              _isUpcomingMatchupStatus(game.status)) {
            items.add(_MatchupScheduleItem(date: day.date, game: game));
          }
        }
      }
    }
    items.sort(_compareUpcomingMatchupItemsByDate);
    return items;
  }

  int _compareUpcomingMatchupItemsByDate(
    _MatchupScheduleItem a,
    _MatchupScheduleItem b,
  ) {
    final aDate = _parseScheduleDate(a.date);
    final bDate = _parseScheduleDate(b.date);
    final dateComparison = aDate.compareTo(bDate);
    if (dateComparison != 0) {
      return dateComparison;
    }
    return a.game.time.compareTo(b.game.time);
  }

  DateTime _parseScheduleDate(String date) {
    final parsed = DateTime.tryParse(date);
    if (parsed == null) {
      return DateTime(9999);
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  bool _isPastScheduleDate(String date) {
    final today = kboCivilDateTime();
    final todayDate = DateTime(today.year, today.month, today.day);
    return _parseScheduleDate(date).isBefore(todayDate);
  }

  bool _isUpcomingMatchupStatus(String status) {
    final normalized = status.trim().toUpperCase();
    return normalized != 'LIVE' && !isTerminalScheduleStatus(normalized);
  }

  Widget _buildCalendar(
    DateTime month,
    Set<int> gameDays,
    Set<int> myTeamDays,
  ) {
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final startWeekday = firstDay.weekday;
    final leadingDays = startWeekday - 1;
    final totalCells = ((leadingDays + lastDay.day + 6) ~/ 7) * 7;
    final firstVisibleDay = firstDay.subtract(Duration(days: leadingDays));
    final today = kboCivilDateTime();
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final isCompactViewport = viewportHeight < 700;
    final usesDenseCalendarSpacing = viewportHeight < 780;
    const cellHeight = 44.0;
    final dateBoxSize = isCompactViewport ? 30.0 : 34.0;
    const weekdayNames = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final calendarWidth = viewportWidth < 360 ? 330.0 : viewportWidth - 32;
        final calendar = SizedBox(
          key: const ValueKey('schedule-calendar-card'),
          width: calendarWidth,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              10,
              usesDenseCalendarSpacing ? 4 : 14,
              10,
              usesDenseCalendarSpacing ? 4 : 8,
            ),
            decoration: BoxDecoration(
              color: AppColors.card.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.divider.withValues(alpha: 0.88),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: weekdays.map((d) {
                    final color = d == '토'
                        ? AppColors.accent
                        : d == '일'
                        ? AppColors.live
                        : AppColors.textSupporting;
                    return Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: TextStyle(
                            fontSize: 12,
                            height: usesDenseCalendarSpacing ? 1 : null,
                            color: color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (!usesDenseCalendarSpacing) const SizedBox(height: 8),
                ...List.generate(totalCells ~/ 7, (week) {
                  return Row(
                    children: List.generate(7, (weekday) {
                      final cellIndex = week * 7 + weekday;
                      final date = firstVisibleDay.add(
                        Duration(days: cellIndex),
                      );
                      final isInCurrentMonth =
                          date.year == month.year && date.month == month.month;
                      final day = date.day;
                      final isSelected =
                          isInCurrentMonth &&
                          month.year == _currentMonth.year &&
                          month.month == _currentMonth.month &&
                          day == _selectedDay;
                      final isToday =
                          date.year == today.year &&
                          date.month == today.month &&
                          date.day == today.day;
                      final hasGame =
                          isInCurrentMonth && gameDays.contains(day);
                      final isMyTeam =
                          isInCurrentMonth && myTeamDays.contains(day);
                      final isPast = date.isBefore(
                        DateTime(today.year, today.month, today.day),
                      );
                      final isSaturday = date.weekday == DateTime.saturday;
                      final isSunday = date.weekday == DateTime.sunday;
                      final semanticParts = <String>[
                        '${date.month}월 ${date.day}일 ${weekdayNames[date.weekday - 1]}',
                        if (!isInCurrentMonth) '다른 달',
                        if (isToday) '오늘',
                        if (isMyTeam) '마이팀 경기 있음' else if (hasGame) '경기 있음',
                        if (isSelected) '선택됨',
                      ];

                      return Expanded(
                        child: Semantics(
                          key: ValueKey(
                            'schedule-date-${date.year}-${date.month}-${date.day}',
                          ),
                          button: true,
                          selected: isSelected,
                          label: semanticParts.join(', '),
                          onTap: () => _selectDate(date),
                          child: ExcludeSemantics(
                            child: AppPressable(
                              onTap: () => _selectDate(date),
                              pressedScale: 0.92,
                              child: SizedBox(
                                height: cellHeight,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    AnimatedContainer(
                                      duration:
                                          MediaQuery.of(
                                            context,
                                          ).disableAnimations
                                          ? Duration.zero
                                          : const Duration(milliseconds: 180),
                                      width: dateBoxSize,
                                      height: dateBoxSize,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(7),
                                        color: isSelected
                                            ? AppColors.live.withValues(
                                                alpha: 0.62,
                                              )
                                            : isToday
                                            ? AppColors.cardSub
                                            : null,
                                        border: hasGame || isToday
                                            ? Border.all(
                                                color: hasGame
                                                    ? AppColors.live.withValues(
                                                        alpha: isSelected
                                                            ? 0.82
                                                            : 0.62,
                                                      )
                                                    : AppColors.divider,
                                              )
                                            : null,
                                      ),
                                      child: Text(
                                        '$day',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isSelected
                                              ? AppColors.textPrimary
                                              : !isInCurrentMonth
                                              ? AppColors.textSupporting
                                              : isPast
                                              ? AppColors.textSupporting
                                              : isSaturday
                                              ? AppColors.accent
                                              : isSunday
                                              ? AppColors.live
                                              : AppColors.textPrimary,
                                          fontWeight: isSelected || isToday
                                              ? FontWeight.w900
                                              : FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    if (hasGame)
                                      SizedBox(
                                        height: 7,
                                        child: isMyTeam
                                            ? Icon(
                                                Icons.star_rounded,
                                                size: 8,
                                                color: AppColors.accent,
                                              )
                                            : Container(
                                                width: 4,
                                                height: 4,
                                                margin: const EdgeInsets.only(
                                                  top: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color:
                                                      AppColors.textSupporting,
                                                ),
                                              ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                }),
                if (!usesDenseCalendarSpacing) const SizedBox(height: 8),
              ],
            ),
          ),
        );
        if (viewportWidth < 360) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(mainAxisSize: MainAxisSize.min, children: [calendar]),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: calendar,
        );
      },
    );
  }

  int _monthDeltaFromToday(DateTime month) {
    final now = kboCivilDateTime();
    return (month.year - now.year) * 12 + (month.month - now.month);
  }

  DateTime _monthForPage(int page) {
    final now = kboCivilDateTime();
    final delta = page - _calendarInitialPage;
    return DateTime(now.year, now.month + delta);
  }

  List<Widget> _buildGameListItems(ScheduleDay? schedule) {
    if (_selectedDay == null) {
      return [
        _buildScheduleEmptyArtwork(
          title: '일정 선택',
          message: '날짜를 탭해 경기 일정을 보세요',
        ),
      ];
    }

    if (schedule == null || schedule.games.isEmpty) {
      return [
        _buildScheduleEmptyArtwork(title: '경기 없음', message: '선택한 날짜에 경기가 없습니다'),
      ];
    }

    final dayNames = ['', '월', '화', '수', '목', '금', '토', '일'];
    final date = DateTime(
      _currentMonth.year,
      _currentMonth.month,
      _selectedDay!,
    );
    final dateLabel =
        '${_currentMonth.month}월 $_selectedDay일 (${dayNames[date.weekday]})';
    final label = schedule.label != null
        ? '$dateLabel — ${schedule.label}'
        : dateLabel;
    final myTeamId = ref.watch(myTeamProvider);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ),
      ...schedule.games.asMap().entries.map(
        (entry) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: AppMotionListItem(
            key: ValueKey('schedule-game-${entry.value.gameId}'),
            index: entry.key,
            child: ScheduleGameCard(
              game: entry.value,
              myTeamId: myTeamId,
              onTap: () => _openGameDetail(entry.value),
              ticketSummary:
                  entry.value.ticketInfo == null ||
                      !shouldShowTicketInfoForScheduleStatus(entry.value.status)
                  ? null
                  : _ticketSummary(entry.value.ticketInfo!),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
    ];
  }

  Widget _buildScheduleEmptyArtwork({
    required String title,
    required String message,
  }) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final cardHeight = 178 + (textScale - 1).clamp(0.0, 1.4) * 42;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
      child: AppArtworkCard(
        assetName: VisualAssets.scheduleEmptyCalendar,
        height: cardHeight,
        alignment: Alignment.center,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameListLoading() {
    return Center(child: CircularProgressIndicator(color: AppColors.live));
  }

  Widget _buildGameListLoadingSection() {
    return SizedBox(height: 260, child: _buildGameListLoading());
  }

  Widget _buildScheduleErrorContent(Object error) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: AppArtworkCard(
        assetName: VisualAssets.dataRetry,
        height: 184,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text(
              '일정을 불러올 수 없습니다',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _refreshSchedule,
                child: const Text('다시 시도'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStadiumList(String yearMonth, List<ScheduleDay> days) {
    final myTeamId = ref.watch(myTeamProvider);
    final stadiumMap = <String, List<_StadiumScheduleItem>>{};
    for (final day in days) {
      for (final game in day.games) {
        stadiumMap.putIfAbsent(game.stadium, () => []);
        stadiumMap[game.stadium]!.add(
          _StadiumScheduleItem(date: day.date, game: game),
        );
      }
    }

    final stadiums = stadiumMap.keys.toList()..sort();
    if (stadiums.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshSchedule,
        color: AppColors.live,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _buildScheduleEmptyArtwork(
              title: '구장별 일정 없음',
              message: '표시할 경기가 없습니다',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshSchedule,
      color: AppColors.live,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              '구장별 일정',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final stadium in stadiums) ...[
                  _stadiumQuickLinkButton(
                    stadium: stadium,
                    gameCount: stadiumMap[stadium]!.length,
                    onTap: () => _scrollToStadium(yearMonth, stadium),
                  ),
                  if (stadium != stadiums.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final stadium in stadiums) ...[
            Padding(
              key: _stadiumSectionKey(yearMonth, stadium),
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: Text(
                stadium,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ...stadiumMap[stadium]!.asMap().entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppMotionListItem(
                  key: ValueKey(
                    'stadium-game-$stadium-${entry.value.game.gameId}',
                  ),
                  index: entry.key,
                  child: ScheduleGameCard(
                    game: entry.value.game,
                    dateLabel: _formatDateLabel(entry.value.date),
                    myTeamId: myTeamId,
                    onTap: () => _openGameDetail(entry.value.game),
                    ticketSummary:
                        entry.value.game.ticketInfo == null ||
                            !shouldShowTicketInfoForScheduleStatus(
                              entry.value.game.status,
                            )
                        ? null
                        : _ticketSummary(entry.value.game.ticketInfo!),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMatchupList({
    required int season,
    required List<_MatchupScheduleItem> items,
    required String firstTeamId,
    required String secondTeamId,
  }) {
    final myTeamId = ref.watch(myTeamProvider);
    final firstTeam = KboTeams.byId(firstTeamId);
    final secondTeam = KboTeams.byId(secondTeamId);
    final matchupLabel =
        '${firstTeam?.shortName ?? firstTeamId} vs ${secondTeam?.shortName ?? secondTeamId}';

    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshSchedule,
        color: AppColors.live,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _buildMatchupSummary(
              matchupLabel: matchupLabel,
              gameCount: 0,
              season: season,
            ),
            _buildScheduleEmptyArtwork(
              title: '매치업 일정 없음',
              message: '$matchupLabel 남은 경기가 이번 시즌 일정에 없습니다',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshSchedule,
      color: AppColors.live,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildMatchupSummary(
            matchupLabel: matchupLabel,
            gameCount: items.length,
            season: season,
          ),
          const SizedBox(height: 12),
          ...items.asMap().entries.map((entry) {
            final item = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppMotionListItem(
                key: ValueKey('matchup-game-${item.game.gameId}'),
                index: entry.key,
                child: ScheduleGameCard(
                  game: item.game,
                  dateLabel: _formatDateLabel(item.date),
                  myTeamId: myTeamId,
                  onTap: () => _openGameDetail(item.game),
                  ticketSummary:
                      item.game.ticketInfo == null ||
                          !shouldShowTicketInfoForScheduleStatus(
                            item.game.status,
                          )
                      ? null
                      : _ticketSummary(item.game.ticketInfo!),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMatchupSummary({
    required String matchupLabel,
    required int gameCount,
    required int season,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '팀 매치업 일정',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSupporting,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            matchupLabel,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            '$season 시즌 · 남은 $gameCount경기 · 오늘 기준 가까운 순 · 홈/원정 무관',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stadiumQuickLinkButton({
    required String stadium,
    required int gameCount,
    required VoidCallback onTap,
  }) {
    return AppPressable(
      onTap: onTap,
      pressedScale: 0.96,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardSub,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.place_outlined,
              size: 14,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              stadium,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$gameCount',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSupporting,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateLabel(String date) {
    final parts = date.split('-');
    if (parts.length != 3) {
      return date;
    }
    final month = parts[1];
    final day = parts[2];
    return '$month.$day';
  }

  String _ticketSummary(TicketInfo ticketInfo) {
    return formatScheduleTicketSummary(ticketInfo);
  }

  void _logScheduleLoad(AsyncValue<List<ScheduleDay>> scheduleAsync) {
    if (!scheduleAsync.hasValue) {
      _scheduleLoadStartedAtMicros ??= DateTime.now().microsecondsSinceEpoch;
      return;
    }

    final days = scheduleAsync.value ?? const <ScheduleDay>[];
    final gameCount = days.fold<int>(0, (sum, day) => sum + day.games.length);
    final logKey = '$_yearMonth|${days.length}|$gameCount';
    if (_lastScheduleLoadLogKey == logKey) {
      return;
    }

    final startedAt = _scheduleLoadStartedAtMicros;
    if (startedAt != null) {
      final elapsedMs =
          (DateTime.now().microsecondsSinceEpoch - startedAt) / 1000;
      DevConsole.instance.info(
        'SCHEDULE $_yearMonth loaded ${elapsedMs.toStringAsFixed(0)}ms (${days.length} days/$gameCount games)',
      );
      unawaited(
        ref.read(apiClientProvider).postClientMetric({
          'screen': 'schedule',
          'event': 'loaded',
          'elapsedMs': elapsedMs.round(),
          'month': _yearMonth,
          'dayCount': days.length,
          'gameCount': gameCount,
        }),
      );
    }
    _lastScheduleLoadLogKey = logKey;
    _scheduleLoadStartedAtMicros = null;
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  const _HeaderIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Tooltip(
        message: semanticLabel,
        child: AppPressable(
          onTap: onTap,
          pressedScale: 0.94,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.divider),
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 20),
          ),
        ),
      ),
    );
  }
}
