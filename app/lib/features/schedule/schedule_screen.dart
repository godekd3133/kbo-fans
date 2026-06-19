import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/team_data.dart';
import '../../core/constants/visual_assets.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_artwork_card.dart';
import '../../core/utils/game_status_label.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_page_frame.dart';
import '../../core/widgets/dev_console.dart';
import '../../data/api/api_client.dart';
import '../../data/models/schedule.dart';
import '../../data/models/ticketing.dart';
import '../../data/providers.dart';
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
  final Map<String, GlobalKey> _stadiumSectionKeys = {};
  int? _scheduleLoadStartedAtMicros;
  String? _lastScheduleLoadLogKey;
  int? _pendingSelectedDay;

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

  void _openGameDetail(String gameId) {
    context.push('/game/$gameId');
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
    final now = DateTime.now();
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
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
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
    _goToMonth(DateTime(date.year, date.month), selectedDay: date.day);
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
              _buildScheduleArtwork(),
              Expanded(child: _buildBody(scheduleAsync)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleArtwork() {
    if (MediaQuery.sizeOf(context).height < 760) {
      return const SizedBox.shrink();
    }
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: AppArtworkCard(
        assetName: VisualAssets.scheduleTicketing,
        height: 78,
        alignment: Alignment.centerRight,
      ),
    );
  }

  Widget _buildMonthHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
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
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDisabled,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '일정',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
          _HeaderIconButton(
            icon: Icons.chevron_left_rounded,
            onTap: () => _changeMonth(-1),
          ),
          const SizedBox(width: 8),
          _HeaderIconButton(
            icon: Icons.chevron_right_rounded,
            onTap: () => _changeMonth(1),
          ),
          const SizedBox(width: 8),
          _HeaderIconButton(icon: Icons.today_rounded, onTap: _goToToday),
        ],
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

    return Column(
      children: [
        _buildControls(),
        if (_viewMode == ScheduleViewMode.calendar) ...[
          _buildCalendarPager(),
          const Divider(color: AppColors.divider, height: 1),
          Expanded(
            child: scheduleAsync.when(
              loading: _buildGameListLoading,
              error: (e, _) => _buildScheduleError(e),
              data: (_) => _buildGameList(selectedSchedule),
            ),
          ),
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
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
                    label: '내 팀 먼저 보기',
                    selected: _viewMode == ScheduleViewMode.calendar,
                    onTap: () =>
                        setState(() => _viewMode = ScheduleViewMode.calendar),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _segmentedButton(
                    label: '구장별',
                    selected: _viewMode == ScheduleViewMode.stadium,
                    onTap: () =>
                        setState(() => _viewMode = ScheduleViewMode.stadium),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
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
    return AppPressable(
      onTap: onTap,
      pressedScale: 0.97,
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
            fontSize: 12,
            fontWeight: FontWeight.w600,
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
      onTap: onTap,
      pressedScale: 0.96,
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
      height: 308,
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
          loading: () => _buildStadiumList(yearMonth, const <ScheduleDay>[]),
          error: (_, _) => _buildStadiumList(yearMonth, const <ScheduleDay>[]),
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
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
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
                    child: Text(
                      d,
                      style: TextStyle(fontSize: 12, color: color),
                    ),
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
                    child: AppPressable(
                      onTap: () => _selectDate(date),
                      pressedScale: 0.92,
                      child: SizedBox(
                        height: 40,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 34,
                              height: 30,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(7),
                                color: isSelected
                                    ? AppColors.live.withValues(alpha: 0.58)
                                    : isToday
                                    ? AppColors.cardSub
                                    : null,
                                border: hasGame
                                    ? Border.all(
                                        color: isMyTeam
                                            ? AppColors.live.withValues(
                                                alpha: 0.75,
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
          ...schedule.games.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppMotionListItem(
                key: ValueKey('schedule-game-${entry.value.gameId}'),
                index: entry.key,
                child: ScheduleGameCard(
                  game: entry.value,
                  onTap: () => _openGameDetail(entry.value.gameId),
                  ticketSummary:
                      entry.value.ticketInfo == null ||
                          !shouldShowTicketInfoForScheduleStatus(
                            entry.value.status,
                          )
                      ? null
                      : _ticketSummary(entry.value.ticketInfo!),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameListLoading() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.live),
    );
  }

  Widget _buildScheduleError(Object error) {
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
                  const Text(
                    '일정을 불러올 수 없습니다',
                    style: TextStyle(color: AppColors.textDisabled),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    describeAsyncError(error),
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
    );
  }

  Widget _buildStadiumList(String yearMonth, List<ScheduleDay> days) {
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
                    onTap: () => _openGameDetail(entry.value.game.gameId),
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
            const Icon(
              Icons.place_outlined,
              size: 14,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              stadium,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$gameCount',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textDisabled,
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

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      pressedScale: 0.94,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.divider),
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 18),
      ),
    );
  }
}
