import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/game_status_label.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../core/widgets/dev_console.dart';
import '../../data/api/api_client.dart';
import '../../data/models/schedule.dart';
import '../../data/models/ticketing.dart';
import '../../data/providers.dart';
import '../../services/game_detail_preload_service.dart';
import 'widgets/schedule_game_card.dart';

enum ScheduleViewMode { calendar, stadium }

enum ScheduleTeamFilter { all, myTeamOnly, otherTeamsOnly }

class _StadiumScheduleItem {
  final String date;
  final ScheduleGame game;

  const _StadiumScheduleItem({required this.date, required this.game});
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
  int? _scheduleLoadStartedAtMicros;
  String? _lastScheduleLoadLogKey;
  String? _lastGameDetailPreloadKey;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month);
    _calendarPageController = PageController(initialPage: _calendarInitialPage);
    _selectedDay = now.day;
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
    ref.invalidate(scheduleProvider(_yearMonth));
    await ref.read(scheduleProvider(_yearMonth).future);
  }

  void _scheduleGameDetailPreload(List<ScheduleGame> games) {
    final key = games.map((game) => game.gameId).join(',');
    if (_lastGameDetailPreloadKey == key) {
      return;
    }
    _lastGameDetailPreloadKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      for (final game in games.take(3)) {
        GameDetailPreloadService.instance.preloadGame(
          ref,
          context,
          gameId: game.gameId,
        );
      }
    });
  }

  void _openGameDetail(String gameId) {
    GameDetailPreloadService.instance.preloadGame(ref, context, gameId: gameId);
    context.push('/game/$gameId');
  }

  void _changeMonth(int delta) {
    _calendarPageController.animateToPage(
      _calendarInitialPage + _monthDeltaFromToday(_currentMonth) + delta,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheduleAsync = ref.watch(scheduleProvider(_yearMonth));
    _logScheduleLoad(scheduleAsync);

    return Scaffold(
      body: SafeArea(
        child: AppPageFrame(
          child: Column(
            children: [
              _buildMonthHeader(),
              Expanded(
                child: scheduleAsync.when(
                  loading: () => RefreshIndicator(
                    onRefresh: _refreshSchedule,
                    color: AppColors.live,
                    child: ListView(
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
                  ),
                  error: (e, _) => RefreshIndicator(
                    onRefresh: _refreshSchedule,
                    color: AppColors.live,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: 420,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  '일정을 불러올 수 없습니다',
                                  style: TextStyle(
                                    color: AppColors.textDisabled,
                                  ),
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
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: _refreshSchedule,
                                  child: const Text('다시 시도'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  data: (days) => _buildBody(days),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: AppColors.textPrimary),
            onPressed: () => _changeMonth(-1),
          ),
          Text(
            '${_currentMonth.year}년 ${_currentMonth.month}월',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: AppColors.textPrimary),
            onPressed: () => _changeMonth(1),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(List<ScheduleDay> days) {
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

    return Column(
      children: [
        _buildControls(),
        if (_viewMode == ScheduleViewMode.calendar) ...[
          _buildCalendarPager(),
          const Divider(color: AppColors.divider, height: 1),
          Expanded(child: _buildGameList(selectedSchedule)),
        ] else ...[
          const Divider(color: AppColors.divider, height: 1),
          Expanded(child: _buildStadiumPager()),
        ],
      ],
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _segmentedButton(
                  label: '달력으로 보기',
                  selected: _viewMode == ScheduleViewMode.calendar,
                  onTap: () =>
                      setState(() => _viewMode = ScheduleViewMode.calendar),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _segmentedButton(
                  label: '구장별 보기',
                  selected: _viewMode == ScheduleViewMode.stadium,
                  onTap: () =>
                      setState(() => _viewMode = ScheduleViewMode.stadium),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
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
                    selected: _teamFilter == ScheduleTeamFilter.otherTeamsOnly,
                    onTap: () => setState(
                      () => _teamFilter = ScheduleTeamFilter.otherTeamsOnly,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_viewMode == ScheduleViewMode.calendar) ...[
            const SizedBox(height: 6),
            _legendRow(),
          ] else ...[
            const SizedBox(height: 6),
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
      ),
    );
  }

  Widget _legendRow() {
    final myTeamColor =
        KboTeams.byId(ref.watch(myTeamProvider) ?? '')?.primaryColor ??
        AppColors.live;

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          _legendItem(myTeamColor, '마이팀 경기일'),
          _legendItem(AppColors.textDisabled, '일반 경기일'),
          _legendItem(AppColors.textPrimary, '선택한 날짜'),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textDisabled),
        ),
      ],
    );
  }

  Widget _segmentedButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : AppColors.card,
          borderRadius: BorderRadius.circular(12),
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

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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

  Widget _buildCalendarPager() {
    return SizedBox(
      height: 330,
      child: PageView.builder(
        controller: _calendarPageController,
        onPageChanged: (page) {
          final nextMonth = _monthForPage(page);
          setState(() {
            _currentMonth = nextMonth;
            if (_selectedDay != null) {
              final lastDay = DateTime(
                nextMonth.year,
                nextMonth.month + 1,
                0,
              ).day;
              _selectedDay = _selectedDay!.clamp(1, lastDay);
            }
          });
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

  Widget _buildStadiumPager() {
    return PageView.builder(
      controller: _calendarPageController,
      onPageChanged: (page) {
        final nextMonth = _monthForPage(page);
        setState(() {
          _currentMonth = nextMonth;
          if (_selectedDay != null) {
            final lastDay = DateTime(
              nextMonth.year,
              nextMonth.month + 1,
              0,
            ).day;
            _selectedDay = _selectedDay!.clamp(1, lastDay);
          }
        });
      },
      itemBuilder: (context, index) {
        final month = _monthForPage(index);
        final myTeamId = ref.watch(myTeamProvider);
        final yearMonth =
            '${month.year}-${month.month.toString().padLeft(2, '0')}';
        final scheduleAsync = ref.watch(scheduleProvider(yearMonth));

        return scheduleAsync.when(
          loading: () => _buildStadiumList(const <ScheduleDay>[]),
          error: (_, _) => _buildStadiumList(const <ScheduleDay>[]),
          data: (days) {
            final filteredDays = _filterDays(days, myTeamId);
            final stadiumFilteredDays = _filterDaysBySelectedTeam(
              filteredDays,
              _stadiumTeamId,
            );
            return _buildStadiumList(stadiumFilteredDays);
          },
        );
      },
    );
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
    final today = DateTime.now();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: weekdays.map((d) {
              final color = d == '토'
                  ? AppColors.accent
                  : d == '일'
                  ? AppColors.live
                  : AppColors.textDisabled;
              return Expanded(
                child: Center(
                  child: Text(d, style: TextStyle(fontSize: 12, color: color)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          ...List.generate(totalCells ~/ 7, (week) {
            return Row(
              children: List.generate(7, (weekday) {
                final cellIndex = week * 7 + weekday;
                final date = firstVisibleDay.add(Duration(days: cellIndex));
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
                final hasGame = isInCurrentMonth && gameDays.contains(day);
                final isMyTeam = isInCurrentMonth && myTeamDays.contains(day);
                final isPast = date.isBefore(
                  DateTime(today.year, today.month, today.day),
                );

                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _currentMonth = DateTime(date.year, date.month);
                      _selectedDay = date.day;
                      final targetPage =
                          _calendarInitialPage +
                          _monthDeltaFromToday(_currentMonth);
                      if (_calendarPageController.hasClients &&
                          _calendarPageController.page?.round() != targetPage) {
                        _calendarPageController.jumpToPage(targetPage);
                      }
                    }),
                    child: SizedBox(
                      height: 44,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? AppColors.textPrimary
                                  : isToday
                                  ? AppColors.cardSub
                                  : null,
                            ),
                            child: Text(
                              '$day',
                              style: TextStyle(
                                fontSize: 14,
                                color: isSelected
                                    ? AppColors.background
                                    : !isInCurrentMonth
                                    ? AppColors.textDisabled.withValues(
                                        alpha: 0.55,
                                      )
                                    : isPast
                                    ? AppColors.textDisabled
                                    : AppColors.textPrimary,
                                fontWeight: isSelected || isToday
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (hasGame)
                            Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isMyTeam
                                    ? (KboTeams.byId(
                                            ref.watch(myTeamProvider) ?? '',
                                          )?.primaryColor ??
                                          AppColors.live)
                                    : AppColors.textDisabled,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  int _monthDeltaFromToday(DateTime month) {
    final now = DateTime.now();
    return (month.year - now.year) * 12 + (month.month - now.month);
  }

  DateTime _monthForPage(int page) {
    final now = DateTime.now();
    final delta = page - _calendarInitialPage;
    return DateTime(now.year, now.month + delta);
  }

  Widget _buildGameList(ScheduleDay? schedule) {
    if (_selectedDay == null) {
      return RefreshIndicator(
        onRefresh: _refreshSchedule,
        color: AppColors.live,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 320,
              child: Center(
                child: Text(
                  '날짜를 탭해 경기 일정을 보세요',
                  style: TextStyle(color: AppColors.textDisabled),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (schedule == null || schedule.games.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshSchedule,
        color: AppColors.live,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 320,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_busy, size: 48, color: AppColors.divider),
                    const SizedBox(height: 12),
                    Text(
                      '선택한 날짜에 경기가 없습니다',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textDisabled,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
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
    _scheduleGameDetailPreload(schedule.games);

    return RefreshIndicator(
      onRefresh: _refreshSchedule,
      color: AppColors.live,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          ...schedule.games.map(
            (g) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ScheduleGameCard(
                game: g,
                onTap: () => _openGameDetail(g.gameId),
                ticketSummary:
                    g.ticketInfo == null || isTerminalScheduleStatus(g.status)
                    ? null
                    : _ticketSummary(g.ticketInfo!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStadiumList(List<ScheduleDay> days) {
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
      return Center(
        child: Text(
          '표시할 경기가 없습니다',
          style: TextStyle(color: AppColors.textDisabled),
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
          for (final stadium in stadiums) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: Text(
                stadium,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ...stadiumMap[stadium]!.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ScheduleGameCard(
                  game: item.game,
                  dateLabel: _formatDateLabel(item.date),
                  onTap: () => _openGameDetail(item.game.gameId),
                  ticketSummary:
                      item.game.ticketInfo == null ||
                          isTerminalScheduleStatus(item.game.status)
                      ? null
                      : _ticketSummary(item.game.ticketInfo!),
                ),
              ),
            ),
          ],
        ],
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
    final openAt = ticketInfo.openAt;
    if (openAt == null) {
      return '${ticketInfo.vendorName} · 예매 시간 미정';
    }

    final formatted = DateFormat('MM.dd HH:mm').format(openAt);
    return '${ticketInfo.vendorName} · $formatted 오픈';
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
