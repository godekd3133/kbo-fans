import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/schedule.dart';
import '../../data/providers.dart';

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  late DateTime _currentMonth;
  int? _selectedDay;
  String? _myTeamId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month);
    _selectedDay = now.day;
    SharedPreferences.getInstance().then((prefs) {
      setState(() => _myTeamId = prefs.getString('myTeam'));
    });
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

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildMonthHeader(),
            Expanded(
              child: scheduleAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.live)),
                error: (e, _) => Center(child: Text('일정을 불러올 수 없습니다', style: TextStyle(color: AppColors.textDisabled))),
                data: (days) => _buildBody(days),
              ),
            ),
          ],
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
    // 경기 있는 날짜 Set
    final gameDays = <int>{};
    final myTeamDays = <int>{};
    for (final d in days) {
      final day = int.tryParse(d.date.split('-').last) ?? 0;
      gameDays.add(day);
      if (_myTeamId != null) {
        final hasMyTeam = d.games.any((g) => g.awayId == _myTeamId || g.homeId == _myTeamId);
        if (hasMyTeam) myTeamDays.add(day);
      }
    }

    // 선택된 날짜의 경기 목록
    ScheduleDay? selectedSchedule;
    if (_selectedDay != null) {
      final dateStr = '${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}-${_selectedDay.toString().padLeft(2, '0')}';
      selectedSchedule = days.where((d) => d.date == dateStr).firstOrNull;
    }

    return Column(
      children: [
        _buildCalendar(gameDays, myTeamDays),
        const Divider(color: AppColors.divider, height: 1),
        Expanded(child: _buildGameList(selectedSchedule)),
      ],
    );
  }

  Widget _buildCalendar(Set<int> gameDays, Set<int> myTeamDays) {
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final startWeekday = firstDay.weekday;
    final today = DateTime.now();
    final isCurrentMonth = _currentMonth.year == today.year && _currentMonth.month == today.month;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: weekdays.map((d) {
              final color = d == '토' ? AppColors.accent : d == '일' ? AppColors.live : AppColors.textDisabled;
              return Expanded(child: Center(child: Text(d, style: TextStyle(fontSize: 12, color: color))));
            }).toList(),
          ),
          const SizedBox(height: 8),
          ...List.generate(6, (week) {
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
                final isPast = DateTime(_currentMonth.year, _currentMonth.month, day).isBefore(
                  DateTime(today.year, today.month, today.day),
                );

                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedDay = day),
                    child: SizedBox(
                      height: 44,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 32, height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected ? AppColors.textPrimary : isToday ? AppColors.cardSub : null,
                            ),
                            child: Text(
                              '$day',
                              style: TextStyle(
                                fontSize: 14,
                                color: isSelected ? AppColors.background : isPast ? AppColors.textDisabled : AppColors.textPrimary,
                                fontWeight: isSelected || isToday ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (hasGame)
                            Container(
                              width: 4, height: 4,
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isMyTeam ? (KboTeams.byId(_myTeamId!)?.primaryColor ?? AppColors.live) : AppColors.textDisabled,
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
      return Center(child: Text('날짜를 선택하세요', style: TextStyle(color: AppColors.textDisabled)));
    }

    if (schedule == null || schedule.games.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy, size: 48, color: AppColors.divider),
            const SizedBox(height: 12),
            Text('경기가 없습니다', style: TextStyle(fontSize: 16, color: AppColors.textDisabled)),
          ],
        ),
      );
    }

    final dayNames = ['', '월', '화', '수', '목', '금', '토', '일'];
    final date = DateTime(_currentMonth.year, _currentMonth.month, _selectedDay!);
    final dateLabel = '${_currentMonth.month}월 $_selectedDay일 (${dayNames[date.weekday]})';
    final label = schedule.label != null ? '$dateLabel — ${schedule.label}' : dateLabel;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        ...schedule.games.map((g) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => context.push('/game/${g.gameId}'),
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Text(g.time, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                      const SizedBox(width: 16),
                      _teamLogo(g.awayId, 24),
                      const SizedBox(width: 6),
                      Text(KboTeams.byId(g.awayId)?.shortName ?? g.awayName, style: const TextStyle(fontSize: 14)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('vs', style: TextStyle(fontSize: 12, color: AppColors.textDisabled)),
                      ),
                      Text(KboTeams.byId(g.homeId)?.shortName ?? g.homeName, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      _teamLogo(g.homeId, 24),
                      const Spacer(),
                      Text(g.stadium, style: const TextStyle(fontSize: 12, color: AppColors.textDisabled)),
                    ],
                  ),
                ),
              ),
            )),
      ],
    );
  }

  Widget _teamLogo(String teamId, double size) {
    final team = KboTeams.byId(teamId);
    return CachedNetworkImage(
      imageUrl: team?.logoUrl ?? '',
      width: size, height: size,
      placeholder: (_, _) => Container(width: size, height: size, decoration: BoxDecoration(color: AppColors.cardSub, shape: BoxShape.circle)),
      errorWidget: (_, _, _) => Container(
        width: size, height: size,
        decoration: BoxDecoration(color: AppColors.cardSub, shape: BoxShape.circle),
        child: Center(child: Text(team?.shortName ?? '', style: TextStyle(fontSize: size * 0.35, color: AppColors.textSecondary))),
      ),
    );
  }
}
