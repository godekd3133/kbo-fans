import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'dart:convert';

import '../../core/constants/ticketing_policy.dart';
import '../../core/widgets/dev_console.dart';
import '../models/game.dart';
import '../models/highlight_info.dart';
import '../models/highlight_video.dart';
import '../models/relay.dart';
import '../models/boxscore.dart';
import '../models/schedule.dart';
import 'game_repository.dart';

final _log = DevConsole.instance;

/// 앱에서 직접 KBO 홈페이지 ASMX API를 호출하는 구현체
/// 백엔드 서버 없이 인터넷만 되면 실시간 데이터 갱신 가능
/// 웹에서는 CORS proxy를 경유하여 호출
class KboDirectRepository implements GameRepository {
  static const _kboBase = 'https://www.koreabaseball.com';
  // 웹 CORS 우회용 프록시
  static const _corsProxy = 'https://corsproxy.io/?';
  static const _relayUserId = 'godekd3133';
  static const _relayPassword = 'alsrb2002!';

  late final Dio _dio;
  bool _relayLoggedIn = false;
  final Map<String, Future<GameLineupData>> _lineupRequests = {};

  KboDirectRepository() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          if (!kIsWeb) 'X-Requested-With': 'XMLHttpRequest',
          if (!kIsWeb) 'Referer': '$_kboBase/',
          if (!kIsWeb) 'Origin': _kboBase,
          if (!kIsWeb)
            'User-Agent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        },
      ),
    );

    _log.info('KBO Repository: ${kIsWeb ? "웹 (CORS proxy)" : "네이티브 (직접)"}');
  }

  /// 웹에서는 CORS proxy를 통해, 네이티브에서는 직접 호출
  String _resolveUrl(String path) {
    final fullUrl = '$_kboBase$path';
    if (kIsWeb) {
      return '$_corsProxy${Uri.encodeComponent(fullUrl)}';
    }
    return fullUrl;
  }

  // ── 공통 POST 호출 ──

  Future<Map<String, dynamic>> _postAsmx(
    String path,
    Map<String, dynamic> params,
  ) async {
    final url = _resolveUrl(path);
    _log.info('KBO POST $path');
    try {
      final response = await _dio.post<String>(
        url,
        data: params.entries.map((e) => '${e.key}=${e.value}').join('&'),
        options: Options(responseType: ResponseType.plain),
      );
      _log.info('KBO OK $path → ${response.statusCode}');
      final body = response.data ?? '{}';
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
      throw FormatException('Unexpected ASMX payload type: ${decoded.runtimeType}');
    } catch (e) {
      _log.error('KBO FAIL $path → $e');
      rethrow;
    }
  }

  Future<String> _postPlain(
    String path,
    Map<String, dynamic> params, {
    Map<String, String>? headers,
  }) async {
    final url = _resolveUrl(path);
    final response = await _dio.post<String>(
      url,
      data: params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent('${e.value}')}').join('&'),
      options: Options(
        responseType: ResponseType.plain,
        headers: headers,
      ),
    );
    return response.data ?? '';
  }

  Future<String> _getPlain(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final url = _resolveUrl(path);
    final response = await _dio.get<String>(
      url,
      queryParameters: queryParameters,
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  Future<Map<String, Map<String, dynamic>>> _getMainGameMap(String date) async {
    final data = await _postAsmx('/ws/Main.asmx/GetKboGameList', {
      'leId': '1',
      'srId': _mainSeriesForDate(date),
      'date': date.replaceAll('-', ''),
    });
    final games = data['game'] as List<dynamic>? ?? const [];
    return {
      for (final item in games)
        if (item is Map<String, dynamic> && (item['G_ID'] as String?)?.isNotEmpty == true)
          item['G_ID'] as String: item,
    };
  }

  // ── 스코어보드 ──

  @override
  Future<List<Game>> getScoreboard(String date) async {
    _log.info('스코어보드 조회: $date');
    final yearMonth = date.substring(0, 7);
    final schedule = await getSchedule(yearMonth);
    final today = schedule.where((d) => d.date == date).toList();
    if (today.isEmpty) return [];
    final mainGames = await _getMainGameMap(date);

    final games = <Game>[];
    for (final sg in today.first.games) {
      try {
        final data = await _postAsmx('/ws/Schedule.asmx/GetScoreBoardScroll', {
          'leId': 1,
          'srId': 0,
          'seasonId': date.substring(0, 4),
          'gameId': sg.gameId,
        });
        final mainGame = mainGames[sg.gameId];
        final view1Detail = await _loadView1ScoreboardDetail(
          sg.gameId,
          shouldLoad: (mainGame?['GAME_STATE_SC'] as String?) == '2',
        );
        games.add(
          _parseScoreboardGame(
            data,
            sg,
            mainGame: mainGame,
            view1Detail: view1Detail,
          ),
        );
      } catch (_) {
        final mainGame = mainGames[sg.gameId];
        final view1Detail = await _loadView1ScoreboardDetail(
          sg.gameId,
          shouldLoad: (mainGame?['GAME_STATE_SC'] as String?) == '2',
        );
        games.add(
          _buildFallbackGame(
            sg,
            mainGame: mainGame,
            view1Detail: view1Detail,
          ),
        );
      }
    }
    return games;
  }

  @override
  Future<Game?> getGame(String gameId) async {
    final date = _gameDateFromId(gameId);
    if (date == null) {
      return null;
    }

    final games = await getScoreboard(date);
    try {
      return games.firstWhere((game) => game.gameId == gameId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<HighlightInfo?> getHighlightInfo(String gameId) async {
    final date = _gameDateFromId(gameId);
    if (date == null) {
      return null;
    }
    final month = date.substring(0, 7);
    final schedule = await getSchedule(month);
    for (final day in schedule) {
      for (final game in day.games) {
        if (game.gameId == gameId) {
          return HighlightInfo(
            officialUrl: _buildOfficialHighlightUrl(gameId),
            youtubeVideos: [_buildFallbackHighlight(game)],
          );
        }
      }
    }
    return HighlightInfo(officialUrl: _buildOfficialHighlightUrl(gameId));
  }

  Game _parseScoreboardGame(
    Map<String, dynamic> data,
    ScheduleGame sg, {
    Map<String, dynamic>? mainGame,
    Map<String, dynamic>? view1Detail,
  }) {
    final gameStatus = _resolveGameStatus(data, mainGame: mainGame);
    final inning = _deriveInningLabel(
      scoreboardData: data,
      mainGame: mainGame,
      startTime: sg.time,
    );

    return Game(
      gameId: sg.gameId,
      status: gameStatus,
      inning: inning,
      away: _buildTeamScore(
        data,
        isAway: true,
        scheduleGame: sg,
        mainGame: mainGame,
        view1Detail: view1Detail,
      ),
      home: _buildTeamScore(
        data,
        isAway: false,
        scheduleGame: sg,
        mainGame: mainGame,
        view1Detail: view1Detail,
      ),
      stadium: data['S_NM'] as String? ?? sg.stadium,
      startTime: sg.time,
      crowd: _parseInt(data['CROWD_CN']),
      ticketInfo:
          sg.ticketInfo ??
          TicketingPolicy.inferredTicketInfo(
            homeTeamId: sg.homeId,
            gameId: sg.gameId,
            startTime: sg.time,
          ),
      highlightInfo: HighlightInfo(
        officialUrl: _buildOfficialHighlightUrl(sg.gameId),
        youtubeVideos: [_buildFallbackHighlight(sg)],
      ),
    );
  }

  Game _buildFallbackGame(
    ScheduleGame sg, {
    Map<String, dynamic>? mainGame,
    Map<String, dynamic>? view1Detail,
  }) {
    final status = _resolveGameStatus(const {}, mainGame: mainGame);
    return Game(
      gameId: sg.gameId,
      status: status,
      inning: _deriveInningLabel(
        scoreboardData: const {},
        mainGame: mainGame,
        startTime: sg.time,
      ),
      away: _buildTeamScore(
        const {},
        isAway: true,
        scheduleGame: sg,
        mainGame: mainGame,
        view1Detail: view1Detail,
      ),
      home: _buildTeamScore(
        const {},
        isAway: false,
        scheduleGame: sg,
        mainGame: mainGame,
        view1Detail: view1Detail,
      ),
      stadium: sg.stadium,
      startTime: sg.time,
      ticketInfo: sg.ticketInfo,
      highlightInfo: HighlightInfo(
        officialUrl: _buildOfficialHighlightUrl(sg.gameId),
        youtubeVideos: [_buildFallbackHighlight(sg)],
      ),
    );
  }

  TeamScore _buildTeamScore(
    Map<String, dynamic> data, {
    required bool isAway,
    required ScheduleGame scheduleGame,
    Map<String, dynamic>? mainGame,
    Map<String, dynamic>? view1Detail,
  }) {
    final prefix = isAway ? 'AWAY' : 'HOME';
    final teamId = data['${prefix}_ID'] as String? ??
        (isAway ? scheduleGame.awayId : scheduleGame.homeId);
    final teamName =
        data['FULL_${prefix}_NM'] as String? ??
        data['${prefix}_NM'] as String? ??
        (isAway ? scheduleGame.awayName : scheduleGame.homeName);

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

    final dynamic selectedScores = isAway
        ? (view1Detail == null ? null : view1Detail['awayScores'])
        : (view1Detail == null ? null : view1Detail['homeScores']);
    final dynamic selectedTotals = isAway
        ? (view1Detail == null ? null : view1Detail['awayTotals'])
        : (view1Detail == null ? null : view1Detail['homeTotals']);
    final view1Scores = (selectedScores as List<int?>?) ?? const <int?>[];
    final view1Totals =
        (selectedTotals as Map<String, int?>?) ?? const <String, int?>{};
    final resolvedInnings = innings.every((score) => score == null) && view1Scores.isNotEmpty
        ? [...view1Scores]
        : innings;

    return TeamScore(
      teamId: teamId,
      teamName: teamName,
      shortName: data['${prefix}_NM'] as String? ?? teamId,
      score: _parseInt(data[rKey]) ??
          _parseInt(isAway ? (mainGame?['T_SCORE_CN']) : (mainGame?['B_SCORE_CN'])) ??
          (isAway ? scheduleGame.awayScore : scheduleGame.homeScore) ??
          0,
      innings: resolvedInnings,
      hits: _parseInt(data[hKey]) ?? view1Totals['hits'] ?? 0,
      errors: _parseInt(data[eKey]) ?? view1Totals['errors'] ?? 0,
      walks: _parseInt(data[bKey]) ?? view1Totals['balls'] ?? 0,
    );
  }

  GameStatus _resolveGameStatus(
    Map<String, dynamic> data, {
    Map<String, dynamic>? mainGame,
  }) {
    final mainStatus = mainGame?['GAME_STATE_SC'] as String? ?? '';
    switch (mainStatus) {
      case '2':
        return GameStatus.live;
      case '3':
        return GameStatus.final_;
      case '4':
        return GameStatus.cancelled;
      case '5':
        return GameStatus.suspended;
      case '1':
        return GameStatus.scheduled;
    }
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

  String _deriveInningLabel({
    required Map<String, dynamic> scoreboardData,
    required Map<String, dynamic>? mainGame,
    required String startTime,
  }) {
    if ((mainGame?['GAME_STATE_SC'] as String?) == '3') {
      return '경기종료';
    }
    if ((mainGame?['GAME_STATE_SC'] as String?) == '1') {
      return '$startTime 예정'.trim();
    }
    final inningNo = mainGame?['GAME_INN_NO'];
    final half = mainGame?['GAME_TB_SC_NM'];
    if (inningNo != null && half != null) {
      return '$inningNo회$half';
    }
    final currentInning = scoreboardData['CURRENT_INNING'] as String? ?? '';
    if (currentInning.isNotEmpty) {
      return currentInning;
    }
    if ((mainGame?['GAME_STATE_SC'] as String?) == '2') {
      return '경기중';
    }
    return '';
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
      'srIdList': '0,9,6',
      'seasonId': year,
      'gameMonth': month,
      'teamId': '',
    });

    final rows = data['rows'] as List<dynamic>? ?? [];
    final dayMap = <String, List<ScheduleGame>>{};
    String? currentDate;

    for (final row in rows) {
      final r = row as Map<String, dynamic>;
      final cells = r['row'] as List<dynamic>?;
      String date;
      String gameId;
      String time;
      String awayId;
      String awayName;
      int? awayScore;
      String homeId;
      String homeName;
      int? homeScore;
      String stadium;
      String status;

      if (cells != null && cells.isNotEmpty) {
        final parsed = _parseScheduleTableRow(cells, currentDate, year);
        currentDate = parsed.date;
        date = parsed.date;
        gameId = parsed.gameId;
        time = parsed.time;
        awayId = parsed.awayId;
        awayName = parsed.awayName;
        awayScore = parsed.awayScore;
        homeId = parsed.homeId;
        homeName = parsed.homeName;
        homeScore = parsed.homeScore;
        stadium = parsed.stadium;
        status = parsed.status;
      } else {
        final gameDate = r['G_DT'] as String? ?? '';
        if (gameDate.isEmpty) continue;
        date = gameDate.length == 8
            ? '${gameDate.substring(0, 4)}-${gameDate.substring(4, 6)}-${gameDate.substring(6, 8)}'
            : gameDate;
        currentDate = date;
        gameId = r['G_ID'] as String? ?? '';
        time = r['G_TM'] as String? ?? '';
        awayId = r['AWAY_ID'] as String? ?? '';
        awayName = r['AWAY_NM'] as String? ?? awayId;
        awayScore = _parseInt(r['T_SCORE_CN']);
        homeId = r['HOME_ID'] as String? ?? '';
        homeName = r['HOME_NM'] as String? ?? homeId;
        homeScore = _parseInt(r['B_SCORE_CN']);
        stadium = r['S_NM'] as String? ?? '';
        status = _mapScheduleStatus(r['GAME_STATE_SC'] as String? ?? '');
      }

      if (date.isEmpty || gameId.isEmpty) {
        continue;
      }

      dayMap.putIfAbsent(date, () => []);
      dayMap[date]!.add(
        ScheduleGame(
          gameId: gameId,
          time: time,
          awayId: awayId,
          awayName: awayName,
          awayScore: awayScore,
          homeId: homeId,
          homeName: homeName,
          homeScore: homeScore,
          stadium: stadium,
          status: status,
          ticketInfo: TicketingPolicy.inferredTicketInfo(
            homeTeamId: homeId,
            gameId: gameId,
            startTime: time,
          ),
        ),
      );
    }

    return dayMap.entries
        .map((e) => ScheduleDay(date: e.key, games: e.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  // ── 순위 ──

  @override
  Future<List<TeamStanding>> getStandings(int season) async {
    _log.info('순위 조회: $season');
    try {
      final url = _resolveUrl('/Record/TeamRank/TeamRankDaily.aspx');
      final response = await _dio.get<String>(
        url,
        queryParameters: {'seasonId': season},
        options: Options(
          headers: {'Content-Type': 'text/html', 'Accept': 'text/html'},
          responseType: ResponseType.plain,
        ),
      );

      final standings = _parseStandingsHtml(response.data ?? '');
      _log.info('순위 파싱 완료: ${standings.length}팀');
      return standings;
    } catch (e) {
      _log.error('순위 조회 실패: $e');
      return [];
    }
  }

  List<TeamStanding> _parseStandingsHtml(String html) {
    final standings = <TeamStanding>[];
    final document = html_parser.parse(html);
    final tables = document.querySelectorAll('table');

    for (final table in tables) {
      final headers = table
          .querySelectorAll('th')
          .map((node) => node.text.trim())
          .toList();
      if (!headers.contains('팀명') || !headers.contains('승') || !headers.contains('패')) {
        continue;
      }

      final rows = table.querySelectorAll('tbody tr');
      for (final row in rows) {
        final cells = row
            .querySelectorAll('td')
            .map((node) => node.text.trim())
            .toList();
        if (cells.length < 6) {
          continue;
        }

        final rank = int.tryParse(cells[0]) ?? standings.length + 1;
        final teamName = cells[1];
        final teamId = _teamNameToId(teamName);

        standings.add(
          TeamStanding(
            rank: rank,
            teamId: teamId,
            teamName: _teamNameToFullName(teamName),
            wins: int.tryParse(cells[3]) ?? 0,
            losses: int.tryParse(cells[4]) ?? 0,
            draws: int.tryParse(cells[5]) ?? 0,
            pct: cells.length > 6 ? cells[6] : '.000',
            gb: cells.length > 7 && cells[7].isNotEmpty ? cells[7] : '-',
          ),
        );
      }
      break;
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

  String _teamNameToFullName(String name) {
    if (name.contains('LG')) return 'LG 트윈스';
    if (name.contains('KT')) return 'KT 위즈';
    if (name.contains('SSG')) return 'SSG 랜더스';
    if (name.contains('삼성')) return '삼성 라이온즈';
    if (name.contains('NC')) return 'NC 다이노스';
    if (name.contains('한화')) return '한화 이글스';
    if (name.contains('롯데')) return '롯데 자이언츠';
    if (name.contains('KIA')) return 'KIA 타이거즈';
    if (name.contains('두산')) return '두산 베어스';
    if (name.contains('키움')) return '키움 히어로즈';
    return name;
  }

  // ── 문자중계 (미구현 — 추후 추가) ──

  @override
  Future<RelayData> getRelayData(String gameId, {int? afterSeqNo}) async {
    try {
      await _ensureRelayLoggedIn();
      await _getPlain('/Game/LiveText.aspx', queryParameters: {
        'leagueId': 1,
        'seriesId': 0,
        'gameId': gameId,
        'gyear': gameId.substring(0, 4),
      });
      final html = await _postPlain('/Game/LiveTextView2.aspx', {
        'leagueId': 1,
        'seriesId': 0,
        'gameId': gameId,
        'gyear': gameId.substring(0, 4),
      });
      final relayItems = _parseRelayItems(html);
      final filtered = afterSeqNo == null
          ? relayItems
          : relayItems.where((item) => item.seqNo > afterSeqNo).toList();
      return RelayData(
        currentAtBat: _parseCurrentAtBat(html),
        relayItems: filtered,
      );
    } catch (error) {
      if (error is DioException && error.response?.statusCode == 302) {
        _log.info('KBO relay login redirect for $gameId, summary fallback 사용');
      } else {
        _log.warn('KBO relay fallback failed for $gameId: $error');
      }
      return _buildSummaryRelayFallback(gameId, afterSeqNo: afterSeqNo);
    }
  }

  @override
  Future<List<RelayItem>> getRelay(String gameId, {int? afterSeqNo}) async {
    final relayData = await getRelayData(gameId, afterSeqNo: afterSeqNo);
    return relayData.relayItems;
  }

  @override
  Future<CurrentAtBat?> getCurrentAtBat(String gameId) async {
    final relayData = await getRelayData(gameId);
    return relayData.currentAtBat;
  }

  @override
  Future<GameBoxscoreData> getBoxscoreData(String gameId) async {
    final awayBatters = await getBatters(gameId, isAway: true);
    final awayPitchers = await getPitchers(gameId, isAway: true);
    final homeBatters = await getBatters(gameId, isAway: false);
    final homePitchers = await getPitchers(gameId, isAway: false);
    return GameBoxscoreData(
      gameId: gameId,
      away: TeamBoxscoreData(
        teamId: gameId.substring(8, 10),
        batters: awayBatters,
        pitchers: awayPitchers,
      ),
      home: TeamBoxscoreData(
        teamId: gameId.substring(10, 12),
        batters: homeBatters,
        pitchers: homePitchers,
      ),
    );
  }

  // ── 박스스코어 ──

  @override
  Future<List<BatterRecord>> getBatters(
    String gameId, {
    required bool isAway,
  }) async {
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
  Future<List<PitcherRecord>> getPitchers(
    String gameId, {
    required bool isAway,
  }) async {
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
  Future<GameLineupData> getLineupData(String gameId) async {
    final game = await getGame(gameId);
    if (game == null || game.status != GameStatus.live) {
      return GameLineupData(
        gameId: gameId,
        away: TeamLineupData(teamId: gameId.substring(8, 10), lineup: const []),
        home: TeamLineupData(teamId: gameId.substring(10, 12), lineup: const []),
      );
    }
    return _lineupRequests.putIfAbsent(gameId, () async {
      try {
        final data = await _postAsmx('/ws/Schedule.asmx/GetMatchPlayerList', {
          'leId': 1,
          'srId': 0,
          'seasonId': gameId.substring(0, 4),
          'gameId': gameId,
        });

        final awayRows = data['away'] as List<dynamic>? ?? const [];
        final homeRows = data['home'] as List<dynamic>? ?? const [];

        return GameLineupData(
          gameId: gameId,
          away: TeamLineupData(
            teamId: gameId.substring(8, 10),
            lineup: _parseLineupRows(awayRows),
            starterName: _parseStarterName(awayRows),
          ),
          home: TeamLineupData(
            teamId: gameId.substring(10, 12),
            lineup: _parseLineupRows(homeRows),
            starterName: _parseStarterName(homeRows),
          ),
        );
      } catch (error) {
        _log.warn('KBO lineup fallback for $gameId: $error');
        return _buildFallbackLineupData(gameId);
      } finally {
        _lineupRequests.remove(gameId);
      }
    });
  }

  @override
  Future<List<LineupEntry>> getLineup(
    String gameId, {
    required bool isAway,
  }) async {
    final data = await getLineupData(gameId);
    return (isAway ? data.away : data.home).lineup;
  }

  List<LineupEntry> _parseLineupRows(List<dynamic> rows) {
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

  String? _parseStarterName(List<dynamic> rows) {
    for (final row in rows) {
      final m = row as Map<String, dynamic>;
      final pos = m['POS_CD'] as String? ?? '';
      final posKo = m['POS_NM'] as String? ?? '';
      if (pos == 'P' || posKo.contains('투수')) {
        final name = m['P_NM'] as String? ?? '';
        if (name.isNotEmpty) {
          return name;
        }
      }
    }
    return null;
  }

  Future<GameLineupData> _buildFallbackLineupData(String gameId) async {
    try {
      final boxscore = await getBoxscoreData(gameId);
      return GameLineupData(
        gameId: gameId,
        away: TeamLineupData(
          teamId: boxscore.away.teamId,
          lineup: _lineupFromBatters(boxscore.away.batters),
          starterName: boxscore.away.pitchers.firstOrNull?.name,
        ),
        home: TeamLineupData(
          teamId: boxscore.home.teamId,
          lineup: _lineupFromBatters(boxscore.home.batters),
          starterName: boxscore.home.pitchers.firstOrNull?.name,
        ),
      );
    } catch (_) {
      return GameLineupData(
        gameId: gameId,
        away: TeamLineupData(teamId: gameId.substring(8, 10), lineup: const []),
        home: TeamLineupData(teamId: gameId.substring(10, 12), lineup: const []),
      );
    }
  }

  List<LineupEntry> _lineupFromBatters(List<BatterRecord> batters) {
    return batters
        .where((batter) => batter.name.isNotEmpty)
        .take(9)
        .map(
          (batter) => LineupEntry(
            order: batter.order,
            position: batter.position,
            positionKo: batter.position,
            name: batter.name,
          ),
        )
        .toList();
  }

  // ── 유틸 ──

  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString().replaceAll(',', ''));
  }

  Future<void> _ensureRelayLoggedIn() async {
    if (_relayLoggedIn) {
      return;
    }
    final loginPage = await _getPlain('/Member/Login.aspx');
    final document = html_parser.parse(loginPage);
    String field(String name) {
      return document
              .querySelector('input[name="$name"]')
              ?.attributes['value'] ??
          '';
    }

    final body = await _postPlain(
      '/Member/Login.aspx',
      {
        '__EVENTTARGET': '',
        '__EVENTARGUMENT': '',
        '__LASTFOCUS': '',
        '__VIEWSTATE': field('__VIEWSTATE'),
        '__VIEWSTATEGENERATOR': field('__VIEWSTATEGENERATOR'),
        '__EVENTVALIDATION': field('__EVENTVALIDATION'),
        'ctl00\$ctl00\$ctl00\$cphContents\$cphContents\$cphContents\$txtUserId': _relayUserId,
        'ctl00\$ctl00\$ctl00\$cphContents\$cphContents\$cphContents\$txtPassWord': _relayPassword,
        'ctl00\$ctl00\$ctl00\$cphContents\$cphContents\$cphContents\$btnLogin.x': '42',
        'ctl00\$ctl00\$ctl00\$cphContents\$cphContents\$cphContents\$btnLogin.y': '16',
        'ctl00\$ctl00\$ctl00\$cphContents\$cphContents\$cphContents\$hdUrl': '',
      },
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      },
    );

    if (!body.contains('로그아웃') && !body.contains('LogOut.aspx')) {
      throw StateError('KBO relay login failed');
    }
    _relayLoggedIn = true;
  }

  Future<Map<String, dynamic>?> _loadView1ScoreboardDetail(
    String gameId, {
    required bool shouldLoad,
  }) async {
    if (!shouldLoad) {
      return null;
    }
    try {
      final html = await _postPlain('/Game/LiveTextView1.aspx', {
        'leagueId': 1,
        'seriesId': 0,
        'gameId': gameId,
        'gyear': gameId.substring(0, 4),
      });
      return _parseView1ScoreboardDetail(html);
    } catch (error) {
      _log.warn('KBO view1 scoreboard fallback failed for $gameId: $error');
      return null;
    }
  }

  Map<String, dynamic>? _parseView1ScoreboardDetail(String html) {
    final document = html_parser.parse(html);
    final scoreRows = document.querySelectorAll('#tblScoreBoard2 tbody tr');
    final totalRows = document.querySelectorAll('#tblScoreBoard3 tbody tr');
    if (scoreRows.length < 2) {
      return null;
    }

    List<int?> parseScores(dom.Element row) {
      return row
          .querySelectorAll('td')
          .map((cell) => _parseInt(cell.text.trim()))
          .toList();
    }

    Map<String, int?> parseTotals(dom.Element? row) {
      final cells = row?.querySelectorAll('td') ?? const <dom.Element>[];
      return {
        'hits': cells.length > 1 ? _parseInt(cells[1].text.trim()) : null,
        'errors': cells.length > 2 ? _parseInt(cells[2].text.trim()) : null,
        'balls': cells.length > 3 ? _parseInt(cells[3].text.trim()) : null,
      };
    }

    return {
      'awayScores': parseScores(scoreRows[0]),
      'homeScores': parseScores(scoreRows[1]),
      'awayTotals': parseTotals(totalRows.isNotEmpty ? totalRows[0] : null),
      'homeTotals': parseTotals(totalRows.length > 1 ? totalRows[1] : null),
    };
  }

  List<RelayItem> _parseRelayItems(String html) {
    final document = html_parser.parse(html);
    final items = <RelayItem>[];
    var seqNo = 1;

    for (var inning = 1; inning <= 10; inning++) {
      final container = document.querySelector('#numCont$inning');
      if (container == null) {
        continue;
      }
      final texts = container
          .querySelectorAll('span')
          .map((span) => _normalizeText(span.text))
          .where((text) => text.isNotEmpty)
          .toList()
          .reversed
          .toList();

      var half = 'top';
      for (final text in texts) {
        if (text.contains('회초') && text.contains('공격')) {
          half = 'top';
          items.add(
            RelayItem(
              seqNo: seqNo++,
              inning: inning,
              half: half,
              event: 'INNING_CHANGE',
              text: text,
            ),
          );
          continue;
        }
        if (text.contains('회말') && text.contains('공격')) {
          half = 'bottom';
          items.add(
            RelayItem(
              seqNo: seqNo++,
              inning: inning,
              half: half,
              event: 'INNING_CHANGE',
              text: text,
            ),
          );
          continue;
        }
        final event = _classifyRelayEvent(text);
        items.add(
          RelayItem(
            seqNo: seqNo++,
            inning: inning,
            half: half,
            event: event.$1,
            isScoring: event.$2,
            text: text,
          ),
        );
      }
    }

    return items;
  }

  CurrentAtBat? _parseCurrentAtBat(String html) {
    final document = html_parser.parse(html);
    final present = document.querySelector('p.present');
    final playerNames = document.querySelector('div.playerName');
    if (present == null || playerNames == null) {
      return null;
    }

    final strongs = present.querySelectorAll('strong').map((e) => _normalizeText(e.text)).toList();
    final inningText = strongs.isNotEmpty ? strongs.first : '';
    final countText = strongs.length > 1 ? strongs[1] : '';
    final batterText = _normalizeText(playerNames.querySelector('li.supervision')?.text ?? '');
    final pitcherText = _normalizeText(playerNames.querySelector('li.pitcher')?.text ?? '');
    final batterMeta = _parsePlayerInfoBox(document.querySelector('.playerBox.homeBox .player-info-wrap'));
    final pitcherMeta = _parsePlayerInfoBox(document.querySelector('.playerBox.awayBox .player-info-wrap'));
    final counts = _parseCountText(countText);
    final baseState = _parseBaseState(present.querySelector('#imgThisGameBase'));

    if (inningText.isEmpty &&
        countText.isEmpty &&
        batterText.isEmpty &&
        pitcherText.isEmpty) {
      return null;
    }

    return CurrentAtBat(
      batterName: batterText.isNotEmpty ? batterText : batterMeta.$1,
      batterNumber: batterMeta.$2,
      batterHand: batterMeta.$3,
      batterRecent: batterMeta.$5,
      pitcherName: pitcherText.isNotEmpty ? pitcherText : pitcherMeta.$1,
      pitcherNumber: pitcherMeta.$2,
      pitcherHand: pitcherMeta.$3,
      pitchCount: pitcherMeta.$4,
      inningText: inningText,
      baseState: baseState,
      balls: counts.$1,
      strikes: counts.$2,
      outs: counts.$3,
    );
  }

  (String, bool) _classifyRelayEvent(String text) {
    if (text.contains('경기종료')) return ('GAME_END', false);
    if (text.contains('홈런')) return ('HOMERUN', true);
    if (text.contains('득점') || text.contains('홈인')) return ('RUNS', true);
    if (text.contains('볼넷')) return ('WALK', false);
    if (text.contains('삼진')) return ('STRIKEOUT', false);
    if (text.contains('플라이 아웃') || text.contains('땅볼 아웃') || text.contains('아웃')) {
      return ('OUT', false);
    }
    if (text.contains('교체')) return ('SUBSTITUTION', false);
    if (text.contains('안타') || text.contains('1루타') || text.contains('2루타') || text.contains('3루타')) {
      return ('HIT', false);
    }
    return ('PLAY', false);
  }

  String _normalizeText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  (int, int, int) _parseCountText(String text) {
    final match = RegExp(r'(\d+)-(\d+)\s+(\d+)out').firstMatch(text);
    if (match == null) {
      return (0, 0, 0);
    }
    return (
      int.tryParse(match.group(1) ?? '') ?? 0,
      int.tryParse(match.group(2) ?? '') ?? 0,
      int.tryParse(match.group(3) ?? '') ?? 0,
    );
  }

  (String, int, String, int, String) _parsePlayerInfoBox(dom.Element? element) {
    if (element == null) {
      return ('', 0, '', 0, '');
    }
    final numberText = _normalizeText(element.querySelector('.no')?.text ?? '');
    final hand = _normalizeText(
      element.querySelector('.who span:last-child')?.text ?? '',
    ).replaceAll(RegExp(r'^\(|\)$'), '');
    final todayText = _normalizeText(element.querySelector('.today span')?.text ?? '');
    final pitchCountMatch = RegExp(r'(\d+)투구').firstMatch(todayText);

    var name = numberText;
    var number = 0;
    final match = RegExp(r'No\.(\d+)\s+(.+)').firstMatch(numberText);
    if (match != null) {
      number = int.tryParse(match.group(1) ?? '') ?? 0;
      name = match.group(2) ?? '';
    }
    return (
      name,
      number,
      hand,
      int.tryParse(pitchCountMatch?.group(1) ?? '') ?? 0,
      pitchCountMatch == null ? todayText : '',
    );
  }

  String _parseBaseState(dom.Element? element) {
    if (element == null) {
      return '';
    }
    final src = element.attributes['src'] ?? '';
    final match = RegExp(r'ground_base(\d+)\.png').firstMatch(src);
    if (match == null) {
      final alt = _normalizeText(element.attributes['alt'] ?? '');
      return alt == '주자' ? '' : alt;
    }
    return {
          '0': '주자없음',
          '1': '주자1루',
          '2': '주자2루',
          '3': '주자1,2루',
          '4': '주자3루',
          '5': '주자1,3루',
          '6': '주자2,3루',
          '7': '만루',
        }[match.group(1)] ??
        '';
  }

  String _mainSeriesForDate(String date) {
    final compact = date.replaceAll('-', '');
    if (compact.compareTo('20241026') >= 0) {
      return '0,1,3,4,5,6,7,8,9';
    }
    if (compact.substring(0, 4).compareTo('2021') >= 0) {
      return '0,1,3,4,5,6,7,9';
    }
    return '0,1,3,4,5,7,9';
  }

  _ScheduleRow _parseScheduleTableRow(
    List<dynamic> cells,
    String? currentDate,
    String seasonId,
  ) {
    var offset = 0;
    final firstText = _stripHtml(cells[0]['Text'] as String? ?? '');
    if (RegExp(r'^\d{2}\.\d{2}\(.+\)$').hasMatch(firstText)) {
      final parts = firstText.split('(').first.split('.');
      currentDate = '$seasonId-${parts[0]}-${parts[1]}';
      offset = 1;
    }

    final time = _stripHtml(cells[offset]['Text'] as String? ?? '');
    final playHtml = cells[offset + 1]['Text'] as String? ?? '';
    final actionHtml = cells[offset + 2]['Text'] as String? ?? '';
    final teamNames = _parseTeamsFromPlayHtml(playHtml);
    final scores = _parseScoresFromPlayHtml(playHtml);
    final ids = _deriveTeamIds(
      teamNames.$1,
      teamNames.$2,
      actionHtml: actionHtml,
    );
    final gameId = _deriveGameId(
      currentDate ?? '',
      ids.$1,
      ids.$2,
      actionHtml: actionHtml,
    );
    final stadium = _stripHtml(cells[offset + 6]['Text'] as String? ?? '');
    final status = _deriveScheduleStatus(actionHtml);

    return _ScheduleRow(
      date: currentDate ?? '',
      gameId: gameId,
      time: time,
      awayId: ids.$1,
      awayName: teamNames.$1,
      awayScore: scores.$1,
      homeId: ids.$2,
      homeName: teamNames.$2,
      homeScore: scores.$2,
      stadium: stadium,
      status: status,
    );
  }

  (String, String) _parseTeamsFromPlayHtml(String playHtml) {
    final document = html_parser.parseFragment(playHtml);
    final spans = document
        .querySelectorAll('span')
        .map((e) => e.text.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (spans.length >= 2) {
      return (spans.first, spans.last);
    }
    return ('', '');
  }

  (int?, int?) _parseScoresFromPlayHtml(String playHtml) {
    final matches = RegExp(
      r'<span class=\"(?:win|lose)\">(\d+)</span>',
    ).allMatches(playHtml);
    final scores = matches
        .map((match) => int.tryParse(match.group(1) ?? ''))
        .toList();
    if (scores.length >= 2) {
      return (scores[0], scores[1]);
    }
    return (null, null);
  }

  String _deriveScheduleStatus(String actionHtml) {
    if (actionHtml.trim().isEmpty) {
      return 'SCHEDULED';
    }
    if (actionHtml.contains('section=REVIEW')) {
      return 'FINAL';
    }
    if (actionHtml.contains('section=PREVIEW') ||
        actionHtml.contains('section=START_PIT') ||
        actionHtml.contains('프리뷰')) {
      return 'SCHEDULED';
    }
    if (actionHtml.contains('문자중계') || actionHtml.contains('중계')) {
      return 'LIVE';
    }
    return 'UNKNOWN';
  }

  (String, String) _deriveTeamIds(
    String awayName,
    String homeName, {
    required String actionHtml,
  }) {
    final gameId = _extractGameId(actionHtml);
    final idsFromGameId = _deriveTeamIdsFromGameId(gameId);
    if (idsFromGameId.$1.isNotEmpty && idsFromGameId.$2.isNotEmpty) {
      return idsFromGameId;
    }
    return (_teamNameToId(awayName), _teamNameToId(homeName));
  }

  String _deriveGameId(
    String date,
    String awayId,
    String homeId, {
    required String actionHtml,
  }) {
    final gameId = _extractGameId(actionHtml);
    if (gameId.isNotEmpty) {
      return gameId;
    }
    if (date.isEmpty || awayId.isEmpty || homeId.isEmpty) {
      return '';
    }
    return '${date.replaceAll('-', '')}$awayId${homeId}0';
  }

  String _mapScheduleStatus(String status) {
    switch (status) {
      case '1':
        return 'SCHEDULED';
      case '2':
        return 'LIVE';
      case '3':
      case '4':
        return 'FINAL';
      case '5':
        return 'CANCELLED';
      default:
        return 'UNKNOWN';
    }
  }

  (String, String) _deriveTeamIdsFromGameId(String gameId) {
    if (gameId.length < 12) {
      return ('', '');
    }
    return (gameId.substring(8, 10), gameId.substring(10, 12));
  }

  String _extractGameId(String html) {
    final match = RegExp(r'gameId=([A-Z0-9]+)').firstMatch(html);
    return match?.group(1) ?? '';
  }

  String _stripHtml(String value) {
    final text = html_parser.parseFragment(value).text;
    return (text ?? '').trim();
  }

  String? _gameDateFromId(String gameId) {
    if (gameId.length < 8) {
      return null;
    }
    return '${gameId.substring(0, 4)}-${gameId.substring(4, 6)}-${gameId.substring(6, 8)}';
  }

  HighlightVideo _buildFallbackHighlight(ScheduleGame game) {
    final query = Uri.encodeComponent(
      '${game.awayName} ${game.homeName} ${game.gameId.substring(4, 6)}월 ${game.gameId.substring(6, 8)}일 하이라이트',
    );
    final videoUrl = 'https://www.youtube.com/results?search_query=$query';
    return HighlightVideo(
      videoId: '',
      title: '${game.awayName} vs ${game.homeName} 유튜브 하이라이트 검색',
      thumbnailUrl: '',
      videoUrl: videoUrl,
      source: 'youtube_search_fallback',
    );
  }

  String _buildOfficialHighlightUrl(String gameId) {
    final date = _gameDateFromId(gameId)!.replaceAll('-', '');
    return 'https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx?gameDate=$date&gameId=$gameId&section=HIGHLIGHT';
  }

  Future<RelayData> _buildSummaryRelayFallback(
    String gameId, {
    int? afterSeqNo,
  }) async {
    final game = await getGame(gameId);
    if (game == null) {
      return const RelayData(currentAtBat: null, relayItems: []);
    }

    final items = <RelayItem>[];
    var seqNo = 1;
    final innings = game.away.innings.length > game.home.innings.length
        ? game.away.innings.length
        : game.home.innings.length;

    for (var i = 0; i < innings; i++) {
      final inning = i + 1;
      final awayRuns = i < game.away.innings.length ? game.away.innings[i] : null;
      final homeRuns = i < game.home.innings.length ? game.home.innings[i] : null;

      if (awayRuns != null && awayRuns > 0) {
        items.add(
          RelayItem(
            seqNo: seqNo++,
            inning: inning,
            half: 'top',
            event: 'RUNS',
            isScoring: true,
            text: '$inning회초 ${game.away.shortName} $awayRuns득점',
          ),
        );
      }

      if (homeRuns != null && homeRuns > 0) {
        items.add(
          RelayItem(
            seqNo: seqNo++,
            inning: inning,
            half: 'bottom',
            event: 'RUNS',
            isScoring: true,
            text: '$inning회말 ${game.home.shortName} $homeRuns득점',
          ),
        );
      }
    }

    if (game.status == GameStatus.final_) {
      items.add(
        RelayItem(
          seqNo: seqNo++,
          inning: 999,
          half: 'bottom',
          event: 'GAME_END',
          text: '경기종료 ${game.away.shortName} ${game.away.score} : ${game.home.score} ${game.home.shortName}',
        ),
      );
    }

    final filtered = afterSeqNo == null
        ? items
        : items.where((item) => item.seqNo > afterSeqNo).toList();

    return RelayData(
      currentAtBat: null,
      relayItems: filtered,
    );
  }
}

class _ScheduleRow {
  final String date;
  final String gameId;
  final String time;
  final String awayId;
  final String awayName;
  final int? awayScore;
  final String homeId;
  final String homeName;
  final int? homeScore;
  final String stadium;
  final String status;

  const _ScheduleRow({
    required this.date,
    required this.gameId,
    required this.time,
    required this.awayId,
    required this.awayName,
    required this.awayScore,
    required this.homeId,
    required this.homeName,
    required this.homeScore,
    required this.stadium,
    required this.status,
  });
}
