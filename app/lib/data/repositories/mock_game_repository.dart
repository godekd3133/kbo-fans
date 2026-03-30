import '../models/game.dart';
import '../models/relay.dart';
import '../models/boxscore.dart';
import '../models/schedule.dart';
import '../mock/mock_games.dart';
import '../mock/mock_game_detail.dart';
import 'game_repository.dart';

class MockGameRepository implements GameRepository {
  @override
  Future<List<Game>> getScoreboard(String date) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return mockGames;
  }

  @override
  Future<List<RelayItem>> getRelay(String gameId, {int? afterSeqNo}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (afterSeqNo != null) {
      return mockRelayItems.where((r) => r.seqNo > afterSeqNo).toList();
    }
    return mockRelayItems;
  }

  @override
  Future<CurrentAtBat?> getCurrentAtBat(String gameId) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return mockCurrentAtBat;
  }

  @override
  Future<List<BatterRecord>> getBatters(String gameId, {required bool isAway}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return mockAwayBatters;
  }

  @override
  Future<List<PitcherRecord>> getPitchers(String gameId, {required bool isAway}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return mockAwayPitchers;
  }

  @override
  Future<List<LineupEntry>> getLineup(String gameId, {required bool isAway}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return mockAwayLineup;
  }

  @override
  Future<List<ScheduleDay>> getSchedule(String yearMonth) async {
    await Future.delayed(const Duration(milliseconds: 300));
    // yearMonth 형식: "2026-03"
    return _generateMockSchedule(yearMonth);
  }

  @override
  Future<List<TeamStanding>> getStandings(int season) async {
    await Future.delayed(const Duration(milliseconds: 300));
    // 3월 30일 기준: 개막 2경기 반영
    return const [
      TeamStanding(rank: 1, teamId: 'LG', teamName: 'LG 트윈스', wins: 2, losses: 0, draws: 0, pct: '1.000', gb: '-'),
      TeamStanding(rank: 2, teamId: 'HT', teamName: 'KIA 타이거즈', wins: 2, losses: 0, draws: 0, pct: '1.000', gb: '-'),
      TeamStanding(rank: 3, teamId: 'NC', teamName: 'NC 다이노스', wins: 2, losses: 0, draws: 0, pct: '1.000', gb: '-'),
      TeamStanding(rank: 4, teamId: 'HH', teamName: '한화 이글스', wins: 1, losses: 1, draws: 0, pct: '.500', gb: '1'),
      TeamStanding(rank: 5, teamId: 'LT', teamName: '롯데 자이언츠', wins: 1, losses: 1, draws: 0, pct: '.500', gb: '1'),
      TeamStanding(rank: 6, teamId: 'KT', teamName: 'KT 위즈', wins: 1, losses: 1, draws: 0, pct: '.500', gb: '1'),
      TeamStanding(rank: 7, teamId: 'SK', teamName: 'SSG 랜더스', wins: 1, losses: 1, draws: 0, pct: '.500', gb: '1'),
      TeamStanding(rank: 8, teamId: 'SS', teamName: '삼성 라이온즈', wins: 0, losses: 2, draws: 0, pct: '.000', gb: '2'),
      TeamStanding(rank: 9, teamId: 'OB', teamName: '두산 베어스', wins: 0, losses: 2, draws: 0, pct: '.000', gb: '2'),
      TeamStanding(rank: 10, teamId: 'WO', teamName: '키움 히어로즈', wins: 0, losses: 2, draws: 0, pct: '.000', gb: '2'),
    ];
  }

  /// 월별 Mock 일정 생성
  List<ScheduleDay> _generateMockSchedule(String yearMonth) {
    final parts = yearMonth.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final lastDay = DateTime(year, month + 1, 0).day;

    // 5개 팀 매치업 (어웨이, 홈) 로테이션
    const matchups = [
      ('KT', 'LG'), ('HT', 'SK'), ('LT', 'SS'), ('OB', 'NC'), ('WO', 'HH'),
    ];
    const matchups2 = [
      ('LG', 'KT'), ('SK', 'HT'), ('SS', 'LT'), ('NC', 'OB'), ('HH', 'WO'),
    ];
    const stadiums = ['잠실', '문학', '대구', '창원', '대전'];
    const stadiums2 = ['수원', '광주', '사직', '고척', '잠실'];

    final days = <ScheduleDay>[];

    for (int d = 1; d <= lastDay; d++) {
      final date = DateTime(year, month, d);
      final weekday = date.weekday; // 1=월 ~ 7=일

      // 시범경기: 3월 12~24, 정규시즌: 3월 28~
      // 월/목 = 쉬는 날 (간단한 Mock 규칙)
      bool hasGames;
      String? label;
      if (month == 3) {
        if (d >= 12 && d <= 24 && weekday != 1) {
          hasGames = true;
          label = '시범경기';
        } else if (d >= 28) {
          hasGames = true;
          if (d == 28) label = '개막전';
        } else {
          hasGames = false;
        }
      } else {
        // 4월 이후: 월요일 제외 매일 경기
        hasGames = weekday != 1;
      }

      if (!hasGames) continue;

      final isWeekend = weekday == 6 || weekday == 7;
      final time = isWeekend ? (weekday == 6 ? '17:00' : '14:00') : '18:30';
      final useSecond = d.isEven;
      final ms = useSecond ? matchups2 : matchups;
      final ss = useSecond ? stadiums2 : stadiums;

      final dateStr = '$year-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      final games = <ScheduleGame>[];
      for (int i = 0; i < 5; i++) {
        final gameId = '${dateStr.replaceAll('-', '')}${ms[i].$1}${ms[i].$2}0';
        games.add(ScheduleGame(
          gameId: gameId,
          time: time,
          awayId: ms[i].$1,
          awayName: ms[i].$1,
          homeId: ms[i].$2,
          homeName: ms[i].$2,
          stadium: ss[i],
        ));
      }

      days.add(ScheduleDay(date: dateStr, label: label, games: games));
    }

    return days;
  }
}
