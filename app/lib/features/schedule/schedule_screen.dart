import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/constants/team_data.dart';
import '../../core/theme/app_theme.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  DateTime _currentMonth = DateTime(2026, 3);
  int _selectedDay = 28;

  // Mock: 경기 있는 날
  final _gameDays = {12, 13, 14, 15, 28, 29, 30};
  final _myTeamDays = {14, 28, 29};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildMonthHeader(),
            _buildCalendar(),
            const Divider(color: AppColors.divider, height: 1),
            Expanded(child: _buildGameList()),
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
            onPressed: () => setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1)),
          ),
          Text(
            '${_currentMonth.year}년 ${_currentMonth.month}월',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: AppColors.textPrimary),
            onPressed: () => setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1)),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    // 월요일 기준 (1=월, 7=일)
    final startWeekday = firstDay.weekday; // 1=월
    final totalCells = ((startWeekday - 1) + lastDay.day + 6) ~/ 7 * 7;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // 요일 헤더
          Row(
            children: weekdays.map((d) {
              final color = d == '토' ? AppColors.accent : d == '일' ? AppColors.live : AppColors.textDisabled;
              return Expanded(
                child: Center(child: Text(d, style: TextStyle(fontSize: 12, color: color))),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // 날짜 그리드
          ...List.generate((totalCells / 7).ceil(), (week) {
            return Row(
              children: List.generate(7, (weekday) {
                final cellIndex = week * 7 + weekday;
                final day = cellIndex - (startWeekday - 2);
                if (day < 1 || day > lastDay.day) {
                  return const Expanded(child: SizedBox(height: 44));
                }
                final isSelected = day == _selectedDay;
                final isToday = day == 28; // Mock: 오늘 = 28일
                final hasGame = _gameDays.contains(day);
                final isMyTeam = _myTeamDays.contains(day);

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
                                    : day < 28
                                        ? AppColors.textDisabled
                                        : AppColors.textPrimary,
                                fontWeight: isSelected || isToday ? FontWeight.w600 : FontWeight.normal,
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
                                color: isMyTeam ? const Color(0xFFC60C30) : AppColors.textDisabled,
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

  Widget _buildGameList() {
    final games = [
      _MockScheduleGame('20260328KTLG0', '14:00', 'KT', 'LG', '잠실'),
      _MockScheduleGame('20260328HTSK0', '14:00', 'HT', 'SK', '문학'),
      _MockScheduleGame('20260328LTSS0', '14:00', 'LT', 'SS', '대구'),
      _MockScheduleGame('20260328OBNC0', '14:00', 'OB', 'NC', '창원'),
      _MockScheduleGame('20260328WOHH0', '14:00', 'WO', 'HH', '대전'),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            '3월 $_selectedDay일 (토) — 개막전',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        ...games.map((g) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => context.push('/game/${g.gameId}'),
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Text(g.time, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                      const SizedBox(width: 16),
                      _teamLogo(g.awayId, 24),
                      const SizedBox(width: 6),
                      Text(KboTeams.byId(g.awayId)?.shortName ?? g.awayId, style: const TextStyle(fontSize: 14)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('vs', style: TextStyle(fontSize: 12, color: AppColors.textDisabled)),
                      ),
                      Text(KboTeams.byId(g.homeId)?.shortName ?? g.homeId, style: const TextStyle(fontSize: 14)),
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

class _MockScheduleGame {
  final String gameId, time, awayId, homeId, stadium;
  const _MockScheduleGame(this.gameId, this.time, this.awayId, this.homeId, this.stadium);
}
