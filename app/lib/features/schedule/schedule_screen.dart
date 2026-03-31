import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
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
  late DateTime _currentMonth;
  int? _selectedDay;
  ScheduleViewMode _viewMode = ScheduleViewMode.calendar;
  ScheduleTeamFilter _teamFilter = ScheduleTeamFilter.all;
  int? _scheduleLoadStartedAtMicros;
  String? _lastScheduleLoadLogKey;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month);
    _selectedDay = now.day;
    _scheduleLoadStartedAtMicros = DateTime.now().microsecondsSinceEpoch;
  }

  String get _yearMonth =>
      '${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}';

  void _changeMonth(int delta) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + delta);
      _selectedDay = null; // 월 변경 시 선택 초기화
    });
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
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.live),
                  ),
                  error: (e, _) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '일정을 불러올 수 없습니다',
                          style: TextStyle(color: AppColors.textDisabled),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          describeAsyncError(e),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => ref.invalidate(scheduleProvider(_yearMonth)),
                          child: const Text('다시 시도'),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
          _buildCalendar(gameDays, myTeamDays),
          const Divider(color: AppColors.divider, height: 1),
          Expanded(child: _buildGameList(selectedSchedule)),
        ] else ...[
          const Divider(color: AppColors.divider, height: 1),
          Expanded(child: _buildStadiumList(filteredDays)),
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

  Widget _buildControls() {
    final hasMyTeam = ref.watch(myTeamProvider) != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
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
                  label: '경기장으로 보기',
                  selected: _viewMode == ScheduleViewMode.stadium,
                  onTap: () =>
                      setState(() => _viewMode = ScheduleViewMode.stadium),
                ),
              ),
            ],
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
        height: 40,
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

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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

  Widget _buildCalendar(Set<int> gameDays, Set<int> myTeamDays) {
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final startWeekday = firstDay.weekday;
    final today = DateTime.now();
    final isCurrentMonth =
        _currentMonth.year == today.year && _currentMonth.month == today.month;

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
          const SizedBox(height: 8),
          ...List.generate(((startWeekday - 1 + lastDay.day + 6) ~/ 7), (week) {
            return Row(
              children: List.generate(7, (weekday) {
                final cellIndex = week * 7 + weekday;
                final day = cellIndex - (startWeekday - 2);
                if (day < 1 || day > lastDay.day) {
                  return const Expanded(child: SizedBox(height: 44));
                }
                final isSelected = day == _selectedDay;
                final isToday = isCurrentMonth && day == today.day;
                final hasGame = gameDays.contains(day);
                final isMyTeam = myTeamDays.contains(day);
                final isPast = DateTime(
                  _currentMonth.year,
                  _currentMonth.month,
                  day,
                ).isBefore(DateTime(today.year, today.month, today.day));

                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedDay = day),
                    child: SizedBox(
                      height: 44,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
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
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildGameList(ScheduleDay? schedule) {
    if (_selectedDay == null) {
      return Center(
        child: Text(
          '날짜를 탭해 경기 일정을 보세요',
          style: TextStyle(color: AppColors.textDisabled),
        ),
      );
    }

    if (schedule == null || schedule.games.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy, size: 48, color: AppColors.divider),
            const SizedBox(height: 12),
            Text(
              '경기가 없습니다',
              style: TextStyle(fontSize: 16, color: AppColors.textDisabled),
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

    return ListView(
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
              onTap: () => context.push('/game/${g.gameId}'),
              ticketSummary: g.ticketInfo == null
                  ? null
                  : _ticketSummary(g.ticketInfo!),
            ),
          ),
        ),
      ],
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            '경기장별 일정',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        for (final stadium in stadiums) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(
              stadium,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          ...stadiumMap[stadium]!.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ScheduleGameCard(
                game: item.game,
                dateLabel: _formatDateLabel(item.date),
                onTap: () => context.push('/game/${item.game.gameId}'),
                ticketSummary: item.game.ticketInfo == null
                    ? null
                    : _ticketSummary(item.game.ticketInfo!),
              ),
            ),
          ),
        ],
      ],
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
