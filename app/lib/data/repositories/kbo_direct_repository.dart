import 'package:dio/dio.dart';

import '../../core/widgets/dev_console.dart';
import '../models/game.dart';
import '../models/relay.dart';
import '../models/boxscore.dart';
import '../models/schedule.dart';
import 'game_repository.dart';

final _log = DevConsole.instance;

/// 앱에서 직접 KBO 홈페이지 ASMX API를 호출하는 구현체
/// 백엔드 서버 없이 인터넷만 되면 실시간 데이터 갱신 가능
class KboDirectRepository implements GameRepository {
  static const _kboBase = 'https://www.koreabaseball.com';

  late final Dio _dio;

  KboDirectRepository() {
    _dio = Dio(BaseOptions(
      baseUrl: _kboBase,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'X-Requested-With': 'XMLHttpRequest',
        'Referer': '$_kboBase/',
        'Origin': _kboBase,
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
      },
    ));
  }

  // ── 공통 POST 호출 ──

  Future<Map<String, dynamic>> _postAsmx(String path, Map<String, dynamic> params) async {
    _log.info('KBO POST $path ${params.toString().substring(0, params.toString().length.clamp(0, 80))}');
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        path,
        data: params.entries.map((e) => '${e.key}=${e.value}').join('&'),
      );
      _log.info('KBO OK $path → ${response.statusCode}');
      return response.data ?? {};
    } catch (e) {
      _log.error('KBO FAIL $path → $e');
      rethrow;
    }
  }

  // ── 스코어보드 ──

  @override
  Future<List<Game>> getScoreboard(String date) async {
    _log.info('스코어보드 조회: $date');
    // GetScoreBoardScroll은 gameId가 필요하므로, 먼저 일정에서 gameId 목록을 가져온다
    final yearMonth = date.substring(0, 7);
    final schedule = await getSchedule(yearMonth);
    final today = schedule.where((d) => d.date == date).toList();
    if (today.isEmpty) return [];

    final games = <Game>[];
    for (final sg in today.first.games) {
      try {
        final data = await _postAsmx('/ws/Schedule.asmx/GetScoreBoardScroll', {
          'leId': 1,
          'srId': 0,
          'seasonId': date.substring(0, 4),
          'gameId': sg.gameId,
        });

        games.add(_parseScoreboardGame(data, sg));
      } catch (_) {
        // 개별 경기 실패 시 스킵
        games.add(Game(
          gameId: sg.gameId,
          status: GameStatus.scheduled,
          inning: '',
          away: TeamScore(teamId: sg.awayId, teamName: sg.awayName, shortName: sg.awayName, score: 0, innings: List.filled(9, null)),
          home: TeamScore(teamId: sg.homeId, teamName: sg.homeName, shortName: sg.homeName, score: 0, innings: List.filled(9, null)),
          stadium: sg.stadium,
          startTime: sg.time,
        ));
      }
    }
    return games;
  }

  Game _parseScoreboardGame(Map<String, dynamic> data, ScheduleGame sg) {
    final gameStatus = _resolveGameStatus(data);
    final inning = data['CURRENT_INNING'] as String? ?? '';

    return Game(
      gameId: sg.gameId,
      status: gameStatus,
      inning: inning,
      away: _buildTeamScore(data, isAway: true),
      home: _buildTeamScore(data, isAway: false),
      stadium: data['S_NM'] as String? ?? sg.stadium,
      startTime: sg.time,
      crowd: _parseInt(data['CROWD_CN']),
    );
  }

  TeamScore _buildTeamScore(Map<String, dynamic> data, {required bool isAway}) {
    final prefix = isAway ? 'AWAY' : 'HOME';
    final teamId = data['${prefix}_ID'] as String? ?? '';
    final teamName = data['FULL_${prefix}_NM'] as String? ?? data['${prefix}_NM'] as String? ?? '';

    // 이닝별 점수 파싱
    final innings = <int?>[];
    for (int i = 1; i <= 12; i++) {
      final key = isAway ? 'T_SCORE_CN$i' : 'B_SCORE_CN$i';
      final val = data[key];
      if (val == null || val.toString().isEmpty) {
        innings.add(null);
      } else {
        innings.add(int.tryParse(val.toString()));
      }
    }

    // 9이닝까지만 기본 표시
    while (innings.length < 9) {
      innings.add(null);
    }

    final rKey = isAway ? 'T_SCORE_CN' : 'B_SCORE_CN';
    final hKey = isAway ? 'T_HIT_CN' : 'B_HIT_CN';
    final eKey = isAway ? 'T_ERR_CN' : 'B_ERR_CN';
    final bKey = isAway ? 'T_BB_CN' : 'B_BB_CN';

    return TeamScore(
      teamId: teamId,
      teamName: teamName,
      shortName: data['${prefix}_NM'] as String? ?? teamId,
      score: _parseInt(data[rKey]) ?? 0,
      innings: innings,
      hits: _parseInt(data[hKey]) ?? 0,
      errors: _parseInt(data[eKey]) ?? 0,
      walks: _parseInt(data[bKey]) ?? 0,
    );
  }

  GameStatus _resolveGameStatus(Map<String, dynamic> data) {
    final status = data['GAME_STATE_SC'] as String? ?? '';
    switch (status) {
      case '3':
        return GameStatus.live;
      case '4':
        return GameStatus.final_;
      case '5':
        return GameStatus.cancelled;
      default:
        return GameStatus.scheduled;
    }
  }

  // ── 일정 ──

  @override
  Future<List<ScheduleDay>> getSchedule(String yearMonth) async {
    // yearMonth: "2026-03"
    final parts = yearMonth.split('-');
    final year = parts[0];
    final month = parts[1];

    final data = await _postAsmx('/ws/Schedule.asmx/GetScheduleList', {
      'leId': 1,
      'srId': 0,
      'seasonId': year,
      'yearMonth': '$year$month',
    });

    final rows = data['rows'] as List<dynamic>? ?? [];
    final dayMap = <String, List<ScheduleGame>>{};

    for (final row in rows) {
      final r = row as Map<String, dynamic>;
      final gameDate = r['G_DT'] as String? ?? '';
      if (gameDate.isEmpty) continue;

      // "2026-03-28" 형식으로 정규화
      final date = gameDate.length == 8
          ? '${gameDate.substring(0, 4)}-${gameDate.substring(4, 6)}-${gameDate.substring(6, 8)}'
          : gameDate;

      final gameId = r['G_ID'] as String? ?? '';
      final time = r['G_TM'] as String? ?? '';
      final awayId = r['AWAY_ID'] as String? ?? '';
      final homeId = r['HOME_ID'] as String? ?? '';
      final stadium = r['S_NM'] as String? ?? '';

      dayMap.putIfAbsent(date, () => []);
      dayMap[date]!.add(ScheduleGame(
        gameId: gameId,
        time: time,
        awayId: awayId,
        awayName: r['AWAY_NM'] as String? ?? awayId,
        homeId: homeId,
        homeName: r['HOME_NM'] as String? ?? homeId,
        stadium: stadium,
      ));
    }

    return dayMap.entries
        .map((e) => ScheduleDay(date: e.key, games: e.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  // ── 순위 ──

  @override
  Future<List<TeamStanding>> getStandings(int season) async {
    // ASMX에 순위 전용 엔드포인트가 없으므로 HTML SSR 대신
    // 직접 GET 요청 후 JSON 파싱 시도
    try {
      final response = await _dio.get<String>(
        '/Record/TeamRank/TeamRankDaily.aspx',
        options: Options(
          headers: {
            'Content-Type': 'text/html',
            'Accept': 'text/html',
          },
          responseType: ResponseType.plain,
        ),
      );

      return _parseStandingsHtml(response.data ?? '');
    } catch (_) {
      return [];
    }
  }

  List<TeamStanding> _parseStandingsHtml(String html) {
    // 간단한 정규식 기반 파싱 (BeautifulSoup 없이)
    final standings = <TeamStanding>[];
    // tbl-type04 테이블에서 순위 데이터 추출
    final rowPattern = RegExp(r'<tr[^>]*>.*?</tr>', dotAll: true);
    final tdPattern = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true);
    final tagRemove = RegExp(r'<[^>]*>');

    final tableMatch = RegExp(r'tbl-type04.*?</table>', dotAll: true).firstMatch(html);
    if (tableMatch == null) return standings;

    final rows = rowPattern.allMatches(tableMatch.group(0)!).toList();

    int rank = 0;
    for (final rowMatch in rows) {
      final tds = tdPattern.allMatches(rowMatch.group(0)!).map((m) {
        return m.group(1)!.replaceAll(tagRemove, '').trim();
      }).toList();

      if (tds.length < 7) continue;
      rank++;

      // 팀명에서 팀 ID 추출
      final teamName = tds[0];
      final teamId = _teamNameToId(teamName);

      standings.add(TeamStanding(
        rank: rank,
        teamId: teamId,
        teamName: teamName,
        wins: int.tryParse(tds[1]) ?? 0,
        losses: int.tryParse(tds[2]) ?? 0,
        draws: int.tryParse(tds[3]) ?? 0,
        pct: tds[4],
        gb: tds[5].isEmpty ? '-' : tds[5],
      ));
    }

    return standings;
  }

  String _teamNameToId(String name) {
    if (name.contains('LG')) return 'LG';
    if (name.contains('KT')) return 'KT';
    if (name.contains('SSG')) return 'SK';
    if (name.contains('삼성')) return 'SS';
    if (name.contains('NC')) return 'NC';
    if (name.contains('한화')) return 'HH';
    if (name.contains('롯데')) return 'LT';
    if (name.contains('KIA')) return 'HT';
    if (name.contains('두산')) return 'OB';
    if (name.contains('키움')) return 'WO';
    return '';
  }

  // ── 문자중계 (미구현 — 추후 추가) ──

  @override
  Future<List<RelayItem>> getRelay(String gameId, {int? afterSeqNo}) async {
    // TODO: GetRelayData ASMX 연동
    return [];
  }

  @override
  Future<CurrentAtBat?> getCurrentAtBat(String gameId) async {
    return null;
  }

  // ── 박스스코어 ──

  @override
  Future<List<BatterRecord>> getBatters(String gameId, {required bool isAway}) async {
    final data = await _postAsmx('/ws/Schedule.asmx/GetBoxScoreScroll', {
      'leId': 1,
      'srId': 0,
      'seasonId': gameId.substring(0, 4),
      'gameId': gameId,
    });

    final key = isAway ? 'away_batter' : 'home_batter';
    final rows = data[key] as List<dynamic>? ?? [];
    return rows.map((r) {
      final m = r as Map<String, dynamic>;
      return BatterRecord(
        order: _parseInt(m['BAT_ORDER']) ?? 0,
        position: m['POS_NM'] as String? ?? '',
        name: m['P_NM'] as String? ?? '',
        atBats: _parseInt(m['AB']) ?? 0,
        runs: _parseInt(m['RUN']) ?? 0,
        hits: _parseInt(m['HIT']) ?? 0,
        rbi: _parseInt(m['RBI']) ?? 0,
      );
    }).toList();
  }

  @override
  Future<List<PitcherRecord>> getPitchers(String gameId, {required bool isAway}) async {
    final data = await _postAsmx('/ws/Schedule.asmx/GetBoxScoreScroll', {
      'leId': 1,
      'srId': 0,
      'seasonId': gameId.substring(0, 4),
      'gameId': gameId,
    });

    final key = isAway ? 'away_pitcher' : 'home_pitcher';
    final rows = data[key] as List<dynamic>? ?? [];
    return rows.map((r) {
      final m = r as Map<String, dynamic>;
      return PitcherRecord(
        name: m['P_NM'] as String? ?? '',
        innings: m['INN'] as String? ?? '0.0',
        hits: _parseInt(m['HIT']) ?? 0,
        strikeouts: _parseInt(m['KK']) ?? 0,
        walks: _parseInt(m['BB']) ?? 0,
        earnedRuns: _parseInt(m['ER']) ?? 0,
        decision: m['DC'] as String?,
      );
    }).toList();
  }

  @override
  Future<List<LineupEntry>> getLineup(String gameId, {required bool isAway}) async {
    final data = await _postAsmx('/ws/Schedule.asmx/GetMatchPlayerList', {
      'leId': 1,
      'srId': 0,
      'seasonId': gameId.substring(0, 4),
      'gameId': gameId,
    });

    final key = isAway ? 'away' : 'home';
    final rows = data[key] as List<dynamic>? ?? [];
    return rows.map((r) {
      final m = r as Map<String, dynamic>;
      return LineupEntry(
        order: _parseInt(m['BAT_ORDER']) ?? 0,
        position: m['POS_CD'] as String? ?? '',
        positionKo: m['POS_NM'] as String? ?? '',
        name: m['P_NM'] as String? ?? '',
      );
    }).toList();
  }

  // ── 유틸 ──

  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString().replaceAll(',', ''));
  }
}
