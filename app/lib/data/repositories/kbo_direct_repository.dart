import 'dart:async';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
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
  static const _youtubeBase = 'https://www.youtube.com';
  static const _kboPersonImageBase =
      'https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/person/middle';
  // 웹 CORS 우회용 프록시
  static const _corsProxy = 'https://corsproxy.io/?';
  static const _relayUserId = 'godekd3133';
  static const _relayPassword = 'alsrb2002!';
  static const _relayGameLookupTimeout = Duration(seconds: 3);
  static const _relayWarmupTimeout = Duration(seconds: 2);
  static const _relayFetchTimeout = Duration(seconds: 12);
  static const _relaySummaryTimeout = Duration(seconds: 6);
  static Future<void> _networkQueue = Future<void>.value();
  static bool _relayLoggedIn = false;
  static final Map<String, String> _sessionCookies = {};

  late final Dio _dio;
  final Map<String, Future<List<Game>>> _scoreboardRequests = {};
  final Map<String, Future<List<ScheduleDay>>> _scheduleRequests = {};
  final Map<String, Future<Map<String, Map<String, dynamic>>>>
  _mainGameMapRequests = {};
  final Map<String, Future<GameLineupData>> _lineupRequests = {};
  final Map<String, Future<RelayData>> _relayRequests = {};

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
    if (!kIsWeb) {
      _dio.interceptors.add(CookieManager(CookieJar()));
    }

    _log.info('KBO Repository: ${kIsWeb ? "웹 (CORS proxy)" : "네이티브 (직접)"}');
  }

  Future<void> primeRelaySession() async {
    if (kIsWeb) {
      return;
    }
    try {
      await _ensureRelayLoggedIn();
      _log.info('KBO relay session primed');
    } catch (error) {
      _log.warn('KBO relay session prime failed: $error');
    }
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

  Future<T> _enqueueNetwork<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final scheduled = _networkQueue.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _networkQueue = scheduled.then<void>(
      (_) {},
      onError: (error, stackTrace) {},
    );
    return completer.future;
  }

  Future<dynamic> _postAsmx(String path, Map<String, dynamic> params) async {
    return _enqueueNetwork(() async {
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
        if (decoded is List) {
          return decoded;
        }
        throw FormatException(
          'Unexpected ASMX payload type: ${decoded.runtimeType}',
        );
      } catch (e) {
        _log.error('KBO FAIL $path → $e');
        rethrow;
      }
    });
  }

  Future<String> _postPlain(
    String path,
    Map<String, dynamic> params, {
    Map<String, String>? headers,
    bool allowNotModified = false,
    bool allowRedirect = false,
    bool queued = true,
  }) async {
    Future<String> request() async {
      final url = _resolveUrl(path);
      final response = await _dio.post<String>(
        url,
        data: params.entries
            .map((e) => '${e.key}=${Uri.encodeQueryComponent('${e.value}')}')
            .join('&'),
        options: Options(
          responseType: ResponseType.plain,
          headers: _mergeHeaders(headers),
          validateStatus: (status) {
            if (status == null) return false;
            if (allowNotModified && status == 304) return true;
            if (allowRedirect && (status == 301 || status == 302)) return true;
            return status >= 200 && status < 300;
          },
        ),
      );
      _captureCookies(response);
      if (allowNotModified && response.statusCode == 304) {
        return '';
      }
      if (allowRedirect &&
          (response.statusCode == 301 || response.statusCode == 302)) {
        return response.data ?? '';
      }
      return response.data ?? '';
    }

    return queued ? _enqueueNetwork(request) : request();
  }

  Future<String> _getPlain(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool allowNotModified = false,
    bool queued = true,
  }) async {
    Future<String> request() async {
      final url = _resolveUrl(path);
      final response = await _dio.get<String>(
        url,
        queryParameters: queryParameters,
        options: Options(
          responseType: ResponseType.plain,
          headers: _mergeHeaders(headers),
          validateStatus: (status) {
            if (status == null) return false;
            if (allowNotModified && status == 304) return true;
            return status >= 200 && status < 300;
          },
        ),
      );
      _captureCookies(response);
      if (allowNotModified && response.statusCode == 304) {
        return '';
      }
      return response.data ?? '';
    }

    return queued ? _enqueueNetwork(request) : request();
  }

  Map<String, String>? _mergeHeaders(Map<String, String>? headers) {
    final merged = <String, String>{if (headers != null) ...headers};
    final cookieHeader = _cookieHeader();
    if (cookieHeader.isNotEmpty) {
      merged['Cookie'] = cookieHeader;
    }
    return merged.isEmpty ? null : merged;
  }

  void _captureCookies(Response<dynamic> response) {
    if (kIsWeb) {
      return;
    }
    final rawCookies = response.headers.map['set-cookie'] ?? const <String>[];
    for (final raw in rawCookies) {
      final pair = raw.split(';').first.trim();
      final eqIndex = pair.indexOf('=');
      if (eqIndex <= 0) {
        continue;
      }
      final name = pair.substring(0, eqIndex).trim();
      final value = pair.substring(eqIndex + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty) {
        _sessionCookies[name] = value;
      }
    }
  }

  String _cookieHeader() {
    if (_sessionCookies.isEmpty) {
      return '';
    }
    return _sessionCookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  Future<Map<String, Map<String, dynamic>>> _getMainGameMap(String date) async {
    return _mainGameMapRequests.putIfAbsent(date, () async {
      try {
        final data = await _postAsmx('/ws/Main.asmx/GetKboGameList', {
          'leId': '1',
          'srId': _mainSeriesForDate(date),
          'date': date.replaceAll('-', ''),
        });
        final games = data['game'] as List<dynamic>? ?? const [];
        return {
          for (final item in games)
            if (item is Map<String, dynamic> &&
                (item['G_ID'] as String?)?.isNotEmpty == true)
              item['G_ID'] as String: item,
        };
      } finally {
        _mainGameMapRequests.remove(date);
      }
    });
  }

  // ── 스코어보드 ──

  @override
  Future<List<Game>> getScoreboard(String date) async {
    return _scoreboardRequests.putIfAbsent(date, () async {
      try {
        _log.info('스코어보드 조회: $date');
        final yearMonth = date.substring(0, 7);
        final schedule = await getSchedule(yearMonth);
        final today = schedule.where((d) => d.date == date).toList();
        if (today.isEmpty) return [];
        final mainGames = await _getMainGameMap(date);

        final games = <Game>[];
        for (final sg in today.first.games) {
          final mainGame = mainGames[sg.gameId];
          final srId = _seriesIdFromMainGame(mainGame);
          try {
            final data =
                await _postAsmx('/ws/Schedule.asmx/GetScoreBoardScroll', {
                  'leId': 1,
                  'srId': srId,
                  'seasonId': date.substring(0, 4),
                  'gameId': sg.gameId,
                });
            final view1Detail = await _loadView1ScoreboardDetail(
              sg.gameId,
              seriesId: srId,
              shouldLoad:
                  ((mainGame?['GAME_STATE_SC'] as String?) == '2') ||
                  ((mainGame?['GAME_STATE_SC'] as String?) == '3'),
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
            final view1Detail = await _loadView1ScoreboardDetail(
              sg.gameId,
              seriesId: srId,
              shouldLoad:
                  ((mainGame?['GAME_STATE_SC'] as String?) == '2') ||
                  ((mainGame?['GAME_STATE_SC'] as String?) == '3'),
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
      } finally {
        _scoreboardRequests.remove(date);
      }
    });
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
          final youtubeVideos = await _fetchYoutubeHighlightVideos(
            gameId: gameId,
            awayName: game.awayName,
            homeName: game.homeName,
          );
          return HighlightInfo(
            officialUrl: _buildOfficialHighlightUrl(gameId),
            youtubeVideos: youtubeVideos.isNotEmpty
                ? youtubeVideos
                : [_buildFallbackHighlight(game)],
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
    final statusLabel = _statusLabelFromMainGame(mainGame);
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
      stadium: _firstNonEmptyString([data['S_NM'] as String?, sg.stadium]),
      startTime: sg.time,
      statusLabel: statusLabel ?? sg.statusLabel,
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
    final statusLabel = _statusLabelFromMainGame(mainGame);
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
      statusLabel: statusLabel ?? sg.statusLabel,
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
    final teamId = _firstNonEmptyString([
      data['${prefix}_ID'] as String?,
      isAway ? scheduleGame.awayId : scheduleGame.homeId,
    ]);
    final teamName = _firstNonEmptyString([
      data['FULL_${prefix}_NM'] as String?,
      data['${prefix}_NM'] as String?,
      isAway ? scheduleGame.awayName : scheduleGame.homeName,
    ]);

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
    final inningValueCount = innings.where((score) => score != null).length;
    final view1ValueCount = view1Scores.where((score) => score != null).length;
    final resolvedInnings = view1ValueCount > inningValueCount
        ? [...view1Scores]
        : innings;

    return TeamScore(
      teamId: teamId,
      teamName: teamName,
      score:
          _parseInt(data[rKey]) ??
          _parseInt(
            isAway ? (mainGame?['T_SCORE_CN']) : (mainGame?['B_SCORE_CN']),
          ) ??
          (isAway ? scheduleGame.awayScore : scheduleGame.homeScore) ??
          0,
      innings: resolvedInnings,
      shortName: _firstNonEmptyString([
        data['${prefix}_NM'] as String?,
        teamId,
      ]),
      hits: view1Totals['hits'] ?? _parseInt(data[hKey]) ?? 0,
      errors: view1Totals['errors'] ?? _parseInt(data[eKey]) ?? 0,
      walks: view1Totals['balls'] ?? _parseInt(data[bKey]) ?? 0,
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
    final mainStatus = _gameStatusFromMainGame(mainGame);
    if (mainStatus == GameStatus.final_) {
      return '경기종료';
    }
    if (mainStatus == GameStatus.scheduled) {
      return '$startTime 예정'.trim();
    }
    if (mainStatus == GameStatus.cancelled) {
      return _statusLabelFromMainGame(mainGame) ?? '경기취소';
    }
    if (mainStatus == GameStatus.suspended) {
      return '서스펜디드';
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
    return _scheduleRequests.putIfAbsent(yearMonth, () async {
      try {
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

        for (var index = 0; index < rows.length; index++) {
          final row = rows[index];
          if (row is! Map<String, dynamic>) {
            _log.warn(
              'SCHEDULE row skipped[$yearMonth#$index]: invalid row type ${row.runtimeType}',
            );
            continue;
          }
          final r = row;
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
          String? statusLabel;

          try {
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
              statusLabel = parsed.statusLabel;
            } else {
              final gameDate = r['G_DT'] as String? ?? '';
              if (gameDate.isEmpty) continue;
              date = gameDate.length == 8
                  ? '${gameDate.substring(0, 4)}-${gameDate.substring(4, 6)}-${gameDate.substring(6, 8)}'
                  : gameDate;
              currentDate = date;
              gameId = _firstNonEmptyString([r['G_ID'] as String?, '']);
              time = _firstNonEmptyString([r['G_TM'] as String?, '']);
              awayId = _firstNonEmptyString([r['AWAY_ID'] as String?, '']);
              awayName = _firstNonEmptyString([
                r['AWAY_NM'] as String?,
                awayId,
              ]);
              awayScore = _parseInt(r['T_SCORE_CN']);
              homeId = _firstNonEmptyString([r['HOME_ID'] as String?, '']);
              homeName = _firstNonEmptyString([
                r['HOME_NM'] as String?,
                homeId,
              ]);
              homeScore = _parseInt(r['B_SCORE_CN']);
              stadium = _firstNonEmptyString([r['S_NM'] as String?, '']);
              status = _mapScheduleStatus(r['GAME_STATE_SC'] as String? ?? '');
              statusLabel = null;
            }
          } catch (error, stackTrace) {
            _log.warn(
              'SCHEDULE row skipped[$yearMonth#$index]: $error '
              '(gameDate=${r['G_DT'] ?? ''}, cells=${cells?.length ?? 0})',
            );
            _log.warn(stackTrace.toString());
            continue;
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
              statusLabel: statusLabel,
              ticketInfo: TicketingPolicy.inferredTicketInfo(
                homeTeamId: homeId,
                gameId: gameId,
                startTime: time,
              ),
            ),
          );
        }

        final days =
            dayMap.entries
                .map((e) => ScheduleDay(date: e.key, games: e.value))
                .toList()
              ..sort((a, b) => a.date.compareTo(b.date));

        return _enrichScheduleWithMainGames(days);
      } finally {
        _scheduleRequests.remove(yearMonth);
      }
    });
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
      if (!headers.contains('팀명') ||
          !headers.contains('승') ||
          !headers.contains('패')) {
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
            streak: cells.length > 9 ? cells[9] : '',
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

  Future<List<ScheduleDay>> _enrichScheduleWithMainGames(
    List<ScheduleDay> days,
  ) async {
    final today = _todayDateString();
    final targets = days
        .where(
          (day) =>
              day.date == today ||
              day.games.any(
                (game) =>
                    game.status == 'FINAL' &&
                    (game.awayScore == null || game.homeScore == null),
              ),
        )
        .toList();

    if (targets.isEmpty) {
      return days;
    }

    final gameMaps = <String, Map<String, dynamic>>{};
    for (final day in targets) {
      try {
        gameMaps[day.date] = await _getMainGameMap(day.date);
      } catch (_) {
        gameMaps[day.date] = const {};
      }
    }

    return days.map((day) {
      final mainGames = gameMaps[day.date] ?? const {};
      final games = day.games.map((game) {
        final main = _findMainGameForSchedule(game, mainGames);
        if (main == null) {
          return game;
        }

        final mainStatus = _mapMainGameScheduleStatus(
          main['GAME_STATE_SC']?.toString() ?? '',
        );
        final status = mainStatus == 'UNKNOWN' ? game.status : mainStatus;
        final shouldShowScore =
            status == 'LIVE' || status == 'FINAL' || status == 'SUSPENDED';
        final statusLabel =
            _statusLabelFromMainGame(main) ??
            (status == game.status ? game.statusLabel : null);
        return ScheduleGame(
          gameId: game.gameId,
          time: _firstNonEmptyString([main['G_TM'] as String?, game.time]),
          awayId: game.awayId,
          awayName: game.awayName,
          awayScore: shouldShowScore
              ? _parseInt(main['T_SCORE_CN']) ?? game.awayScore
              : null,
          homeId: game.homeId,
          homeName: game.homeName,
          homeScore: shouldShowScore
              ? _parseInt(main['B_SCORE_CN']) ?? game.homeScore
              : null,
          stadium: _firstNonEmptyString([
            main['S_NM'] as String?,
            game.stadium,
          ]),
          status: status,
          statusLabel: statusLabel,
          ticketInfo: game.ticketInfo,
        );
      }).toList();
      return ScheduleDay(date: day.date, label: day.label, games: games);
    }).toList();
  }

  String _todayDateString() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic>? _findMainGameForSchedule(
    ScheduleGame game,
    Map<String, dynamic> mainGames,
  ) {
    final byId = mainGames[game.gameId];
    if (byId is Map<String, dynamic>) {
      return byId;
    }
    for (final value in mainGames.values) {
      if (value is! Map<String, dynamic>) {
        continue;
      }
      final mainGameId = value['G_ID']?.toString() ?? '';
      final ids = _deriveTeamIdsFromGameId(mainGameId);
      if (ids.$1 == game.awayId && ids.$2 == game.homeId) {
        return value;
      }
    }
    return null;
  }

  String _mapMainGameScheduleStatus(String status) {
    switch (status) {
      case '1':
        return 'SCHEDULED';
      case '2':
        return 'LIVE';
      case '3':
        return 'FINAL';
      case '4':
        return 'CANCELLED';
      case '5':
        return 'SUSPENDED';
      default:
        return 'UNKNOWN';
    }
  }

  String _firstNonEmptyString(List<String?> values) {
    for (final value in values) {
      final normalized = _normalizeText(value ?? '');
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
  }

  // ── 문자중계 (미구현 — 추후 추가) ──

  @override
  Future<RelayData> getRelayData(String gameId, {int? afterSeqNo}) async {
    final requestKey = afterSeqNo == null ? gameId : '$gameId|$afterSeqNo';
    return _relayRequests.putIfAbsent(requestKey, () async {
      try {
        return await _loadRelayData(gameId, afterSeqNo: afterSeqNo);
      } finally {
        _relayRequests.remove(requestKey);
      }
    });
  }

  Future<RelayData> _loadRelayData(String gameId, {int? afterSeqNo}) async {
    _log.info('KBO relay load begin $gameId');
    Map<String, dynamic>? mainGame;
    try {
      mainGame = await _getMainGameForGame(
        gameId,
      ).timeout(_relayGameLookupTimeout, onTimeout: () => null);
    } catch (error) {
      _log.warn('KBO relay main game lookup skipped for $gameId: $error');
    }

    final isFinal = _gameStatusFromMainGame(mainGame) == GameStatus.final_;
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        if (attempt > 0) {
          _resetRelaySession();
        }
        final html = await _fetchRelayHtml(
          gameId,
          mainGame: mainGame,
        ).timeout(_relayFetchTimeout);
        final relayItems = _parseRelayItems(html);
        _log.info('KBO relay loaded $gameId (${relayItems.length} items)');
        if (isFinal && relayItems.isEmpty) {
          return _buildSummaryRelayFallback(
            gameId,
            afterSeqNo: afterSeqNo,
            mainGameSnapshot: mainGame,
          );
        }
        final filtered = afterSeqNo == null
            ? relayItems
            : relayItems.where((item) => item.seqNo > afterSeqNo).toList();
        final parsedAtBat = isFinal ? null : _parseCurrentAtBat(html);
        return RelayData(
          currentAtBat: isFinal
              ? null
              : _currentAtBatWithMainGameImages(
                  parsedAtBat ??
                      _currentAtBatFromMainGame(
                        mainGame,
                        fallbackInning: _formatMainGameInning(mainGame),
                      ),
                  mainGame,
                ),
          relayItems: filtered,
        );
      } catch (error) {
        lastError = error;
        final isRedirect =
            error is DioException &&
            (error.response?.statusCode == 302 ||
                error.response?.statusCode == 301);
        if (!isRedirect || attempt > 0) {
          break;
        }
        _log.warn('KBO relay session refresh for $gameId after redirect');
      }
    }

    if (lastError is DioException &&
        ((lastError.response?.statusCode == 302) ||
            (lastError.response?.statusCode == 301))) {
      _log.info('KBO relay login redirect for $gameId, summary fallback 사용');
    } else if (lastError != null) {
      _log.warn('KBO relay fallback failed for $gameId: $lastError');
    }
    return _buildSummaryRelayFallback(
      gameId,
      afterSeqNo: afterSeqNo,
      mainGameSnapshot: mainGame,
    );
  }

  Future<String> _fetchRelayHtml(
    String gameId, {
    Map<String, dynamic>? mainGame,
  }) async {
    final seriesId = _seriesIdFromMainGame(mainGame);
    final relayHeaders = _relayRequestHeaders(gameId, seriesId);
    final noCacheHeaders = _relayNoCacheHeaders(
      baseHeaders: relayHeaders,
      cacheBuster: DateTime.now().millisecondsSinceEpoch,
    );
    await _ensureRelayLoggedIn(queued: false);
    _log.info('KBO relay GET LiveText $gameId');
    try {
      await _getPlain(
        '/Game/LiveText.aspx',
        queryParameters: {
          'leagueId': 1,
          'seriesId': seriesId,
          'gameId': gameId,
          'gyear': gameId.substring(0, 4),
          '_ts': noCacheHeaders.$2,
        },
        headers: noCacheHeaders.$1,
        allowNotModified: true,
        queued: false,
      ).timeout(_relayWarmupTimeout);
    } catch (error) {
      _log.warn('KBO relay LiveText warmup skipped for $gameId: $error');
    }
    final payload = {
      'leagueId': 1,
      'seriesId': seriesId,
      'gameId': gameId,
      'gyear': gameId.substring(0, 4),
    };
    _log.info('KBO relay POST LiveTextView2 $gameId');
    final initialHtml = await _postPlain(
      '/Game/LiveTextView2.aspx?_ts=${noCacheHeaders.$2}',
      payload,
      headers: noCacheHeaders.$1,
      allowNotModified: true,
      queued: false,
    );
    if (initialHtml.isNotEmpty) {
      return initialHtml;
    }

    _log.info('KBO relay 304 retry for $gameId');
    final retryHeaders = _relayNoCacheHeaders(
      baseHeaders: relayHeaders,
      cacheBuster: DateTime.now().microsecondsSinceEpoch,
    );
    return _postPlain(
      '/Game/LiveTextView2.aspx?_ts=${retryHeaders.$2}',
      payload,
      headers: retryHeaders.$1,
      queued: false,
    );
  }

  GameStatus? _gameStatusFromMainGame(Map<String, dynamic>? mainGame) {
    switch (mainGame?['GAME_STATE_SC']?.toString()) {
      case '1':
        return GameStatus.scheduled;
      case '2':
        return GameStatus.live;
      case '3':
        return GameStatus.final_;
      case '4':
        return GameStatus.cancelled;
      case '5':
        return GameStatus.suspended;
    }
    return null;
  }

  String? _statusLabelFromMainGame(Map<String, dynamic>? mainGame) {
    if (_gameStatusFromMainGame(mainGame) != GameStatus.cancelled) {
      return null;
    }
    final label = _normalizeText(mainGame?['CANCEL_SC_NM']?.toString() ?? '');
    if (label.isEmpty || label == '정상경기') {
      return null;
    }
    return label;
  }

  Map<String, String> _relayRequestHeaders(String gameId, int seriesId) {
    final gameYear = gameId.substring(0, 4);
    return {
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'Referer':
          '$_kboBase/Game/LiveText.aspx?leagueId=1&seriesId=$seriesId&gameId=$gameId&gyear=$gameYear',
    };
  }

  (Map<String, String>, int) _relayNoCacheHeaders({
    required Map<String, String> baseHeaders,
    required int cacheBuster,
  }) {
    return (
      {
        ...baseHeaders,
        'Cache-Control': 'no-cache, no-store, max-age=0',
        'Pragma': 'no-cache',
        'If-Modified-Since': 'Thu, 01 Jan 1970 00:00:00 GMT',
        'Expires': '0',
      },
      cacheBuster,
    );
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
    final mainGame = await _getMainGameForGame(gameId);
    final data = await _postAsmx('/ws/Schedule.asmx/GetBoxScoreScroll', {
      'leId': 1,
      'srId': _seriesIdFromMainGame(mainGame),
      'seasonId': gameId.substring(0, 4),
      'gameId': gameId,
    });

    final hitterPayload = data['arrHitter'] as List<dynamic>? ?? const [];
    final pitcherPayload = data['arrPitcher'] as List<dynamic>? ?? const [];

    final awayBatters = hitterPayload.isNotEmpty
        ? _parseHitterTeamFromTables(hitterPayload[0] as Map<String, dynamic>)
        : const <BatterRecord>[];
    final homeBatters = hitterPayload.length > 1
        ? _parseHitterTeamFromTables(hitterPayload[1] as Map<String, dynamic>)
        : const <BatterRecord>[];
    final awayPitchers = pitcherPayload.isNotEmpty
        ? _parsePitcherTeamFromTable(pitcherPayload[0] as Map<String, dynamic>)
        : const <PitcherRecord>[];
    final homePitchers = pitcherPayload.length > 1
        ? _parsePitcherTeamFromTable(pitcherPayload[1] as Map<String, dynamic>)
        : const <PitcherRecord>[];
    final parsedAway = TeamBoxscoreData(
      teamId: gameId.substring(8, 10),
      batters: awayBatters,
      pitchers: awayPitchers,
    );
    final parsedHome = TeamBoxscoreData(
      teamId: gameId.substring(10, 12),
      batters: homeBatters,
      pitchers: homePitchers,
    );
    final hasOfficialRows =
        parsedAway.hasDisplayableRecords || parsedHome.hasDisplayableRecords;
    if (!hasOfficialRows) {
      final liveContext = _buildLiveContextBoxscore(gameId, mainGame);
      if (liveContext != null) {
        return liveContext;
      }
    }

    final enrichedPitchers = hasOfficialRows
        ? await _enrichLivePitchers(
            gameId: gameId,
            awayPitchers: awayPitchers,
            homePitchers: homePitchers,
          )
        : (awayPitchers, homePitchers);

    return GameBoxscoreData(
      gameId: gameId,
      officialAvailable: hasOfficialRows,
      away: TeamBoxscoreData(
        teamId: parsedAway.teamId,
        batters: awayBatters,
        pitchers: enrichedPitchers.$1,
      ),
      home: TeamBoxscoreData(
        teamId: parsedHome.teamId,
        batters: homeBatters,
        pitchers: enrichedPitchers.$2,
      ),
    );
  }

  GameBoxscoreData? _buildLiveContextBoxscore(
    String gameId,
    Map<String, dynamic>? mainGame,
  ) {
    if (mainGame?['GAME_STATE_SC']?.toString() != '2') {
      return null;
    }

    final inningText = _formatMainGameInning(mainGame);
    final isTop = _isTopInning(inningText, mainGame);
    final awayBatters = <BatterRecord>[];
    final homeBatters = <BatterRecord>[];
    final awayPitchers = <PitcherRecord>[];
    final homePitchers = <PitcherRecord>[];
    String? mainGameValue(String key) =>
        mainGame == null ? null : mainGame[key] as String?;
    final currentBatter = _cleanPlayerName(
      isTop ? mainGameValue('T_P_NM') : mainGameValue('B_P_NM'),
    );
    final currentPitcher = _cleanPlayerName(
      isTop ? mainGameValue('B_P_NM') : mainGameValue('T_P_NM'),
    );
    final starterNames = _starterNamesFromMainGame(mainGame);
    final batterLabel = inningText.isEmpty ? '현재 타자' : '$inningText 현재 타자';
    final pitcherLabel = inningText.isEmpty ? '현재 투수' : '$inningText 현재 투수';

    if (currentBatter != null) {
      final record = BatterRecord(
        order: 0,
        position: '타자',
        name: currentBatter,
        atBats: 0,
        runs: 0,
        hits: 0,
        rbi: 0,
        liveContext: true,
        contextLabel: batterLabel,
      );
      if (isTop) {
        awayBatters.add(record);
      } else {
        homeBatters.add(record);
      }
    }

    void addPitcher(
      List<PitcherRecord> pitchers,
      String? name, {
      required String label,
      String? decision,
    }) {
      final cleaned = _cleanPlayerName(name);
      if (cleaned == null) {
        return;
      }
      final existingIndex = pitchers.indexWhere(
        (pitcher) => _cleanPlayerName(pitcher.name) == cleaned,
      );
      if (existingIndex >= 0) {
        if (decision != null) {
          final existing = pitchers[existingIndex];
          pitchers[existingIndex] = PitcherRecord(
            name: existing.name,
            innings: existing.innings,
            hits: existing.hits,
            strikeouts: existing.strikeouts,
            walks: existing.walks,
            earnedRuns: existing.earnedRuns,
            decision: decision,
            liveContext: true,
            contextLabel: label,
          );
        }
        return;
      }
      pitchers.add(
        PitcherRecord(
          name: cleaned,
          innings: '',
          hits: 0,
          strikeouts: 0,
          walks: 0,
          earnedRuns: 0,
          decision: decision,
          liveContext: true,
          contextLabel: label,
        ),
      );
    }

    addPitcher(awayPitchers, starterNames.$1, label: '선발 투수');
    addPitcher(homePitchers, starterNames.$2, label: '선발 투수');
    if (isTop) {
      addPitcher(
        homePitchers,
        currentPitcher,
        label: pitcherLabel,
        decision: 'LIVE',
      );
    } else {
      addPitcher(
        awayPitchers,
        currentPitcher,
        label: pitcherLabel,
        decision: 'LIVE',
      );
    }

    final away = TeamBoxscoreData(
      teamId: gameId.substring(8, 10),
      batters: awayBatters,
      pitchers: awayPitchers,
    );
    final home = TeamBoxscoreData(
      teamId: gameId.substring(10, 12),
      batters: homeBatters,
      pitchers: homePitchers,
    );
    final hasLiveContext =
        away.hasDisplayableRecords || home.hasDisplayableRecords;
    if (!hasLiveContext) {
      return null;
    }
    return GameBoxscoreData(
      gameId: gameId,
      officialAvailable: false,
      liveContextAvailable: true,
      away: away,
      home: home,
    );
  }

  // ── 박스스코어 ──

  @override
  Future<List<BatterRecord>> getBatters(
    String gameId, {
    required bool isAway,
  }) async {
    final data = await getBoxscoreData(gameId);
    return (isAway ? data.away : data.home).batters;
  }

  @override
  Future<List<PitcherRecord>> getPitchers(
    String gameId, {
    required bool isAway,
  }) async {
    final data = await getBoxscoreData(gameId);
    return (isAway ? data.away : data.home).pitchers;
  }

  @override
  Future<GameLineupData> getLineupData(String gameId) async {
    final game = await getGame(gameId);
    if (game?.status == GameStatus.cancelled) {
      return GameLineupData(
        gameId: gameId,
        away: TeamLineupData(teamId: gameId.substring(8, 10), lineup: const []),
        home: TeamLineupData(
          teamId: gameId.substring(10, 12),
          lineup: const [],
        ),
      );
    }
    return _lineupRequests.putIfAbsent(gameId, () async {
      try {
        return await _buildLineupData(gameId, game: game);
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

  Future<GameLineupData> _buildLineupData(String gameId, {Game? game}) async {
    final mainGame = await _getMainGameForGame(gameId);
    GameLineupData? lineup;
    try {
      lineup = await _fetchLineupAnalysisData(gameId, mainGame: mainGame);
    } catch (error) {
      _log.warn('LINEUP_ANALYSIS_FAIL $gameId: $error');
    }
    if (lineup != null) {
      return lineup;
    }
    if (!_shouldRequestLineup(game)) {
      return _emptyLineupData(gameId, mainGame: mainGame);
    }
    return _buildFallbackLineupData(gameId, mainGame: mainGame);
  }

  Future<GameLineupData?> _fetchLineupAnalysisData(
    String gameId, {
    required Map<String, dynamic>? mainGame,
  }) async {
    final data = await _postAsmx('/ws/Schedule.asmx/GetLineUpAnalysis', {
      'leId': 1,
      'srId': _seriesIdFromMainGame(mainGame),
      'seasonId': gameId.substring(0, 4),
      'gameId': gameId,
    });
    return _parseLineupAnalysisPayload(gameId, data, mainGame: mainGame);
  }

  GameLineupData? _parseLineupAnalysisPayload(
    String gameId,
    Object? payload, {
    Map<String, dynamic>? mainGame,
  }) {
    if (payload is! List || payload.length < 5 || !_lineupIsOpen(payload[0])) {
      return null;
    }

    final homeMeta = _firstMap(payload[1]);
    final awayMeta = _firstMap(payload[2]);
    final homeLineup = _parseLineupAnalysisTable(_firstString(payload[3]));
    final awayLineup = _parseLineupAnalysisTable(_firstString(payload[4]));
    if (awayLineup.isEmpty && homeLineup.isEmpty) {
      return null;
    }

    final starterNames = _starterNamesFromMainGame(mainGame);
    final starterIds = _starterIdsFromMainGame(mainGame);
    final season =
        _gameDateFromId(gameId)?.substring(0, 4) ??
        DateTime.now().year.toString();
    return GameLineupData(
      gameId: gameId,
      away: TeamLineupData(
        teamId: awayMeta['T_ID']?.toString() ?? gameId.substring(8, 10),
        lineup: awayLineup,
        starterId: starterIds.$1,
        starterName: starterNames.$1,
        starterImageUrl: _playerImageUrl(season, starterIds.$1),
      ),
      home: TeamLineupData(
        teamId: homeMeta['T_ID']?.toString() ?? gameId.substring(10, 12),
        lineup: homeLineup,
        starterId: starterIds.$2,
        starterName: starterNames.$2,
        starterImageUrl: _playerImageUrl(season, starterIds.$2),
      ),
    );
  }

  bool _lineupIsOpen(Object? payload) {
    final flag = _firstMap(payload)['LINEUP_CK'];
    return flag == true || flag?.toString().toLowerCase() == 'true';
  }

  Map<String, dynamic> _firstMap(Object? payload) {
    if (payload is List && payload.isNotEmpty) {
      final first = payload.first;
      if (first is Map<String, dynamic>) {
        return first;
      }
      if (first is Map) {
        return first.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    return const {};
  }

  String? _firstString(Object? payload) {
    if (payload is List && payload.isNotEmpty) {
      return payload.first?.toString();
    }
    return null;
  }

  List<LineupEntry> _parseLineupAnalysisTable(String? rawTable) {
    if (rawTable == null || rawTable.isEmpty) {
      return const [];
    }
    final table = jsonDecode(rawTable) as Map<String, dynamic>;
    final rows = table['rows'] as List<dynamic>? ?? const [];
    final lineup = <LineupEntry>[];
    for (final row in rows) {
      final cells =
          ((row as Map<String, dynamic>)['row'] as List<dynamic>? ?? const [])
              .map(
                (cell) => _stripHtml(
                  (cell as Map<String, dynamic>)['Text'] as String? ?? '',
                ).replaceAll('\u00a0', '').trim(),
              )
              .toList();
      if (cells.length < 3) {
        continue;
      }
      final name = cells[2];
      if (name.isEmpty) {
        continue;
      }
      final positionKo = cells.length > 1 ? cells[1] : '';
      final statValue = cells.length > 3 ? cells[3] : '';
      lineup.add(
        LineupEntry(
          order: _parseInt(cells[0]) ?? 0,
          position: _positionToCode(positionKo),
          positionKo: positionKo,
          name: name,
          statValue: statValue.isEmpty ? null : statValue,
        ),
      );
    }
    return lineup;
  }

  Future<GameLineupData> _buildFallbackLineupData(
    String gameId, {
    required Map<String, dynamic>? mainGame,
  }) async {
    try {
      final boxscore = await getBoxscoreData(gameId);
      final starterNames = _starterNamesFromMainGame(mainGame);
      final starterIds = _starterIdsFromMainGame(mainGame);
      final season =
          _gameDateFromId(gameId)?.substring(0, 4) ??
          DateTime.now().year.toString();
      return GameLineupData(
        gameId: gameId,
        away: TeamLineupData(
          teamId: boxscore.away.teamId,
          lineup: _lineupFromBatters(boxscore.away.batters),
          starterId: starterIds.$1,
          starterName:
              starterNames.$1 ?? boxscore.away.pitchers.firstOrNull?.name,
          starterImageUrl: _playerImageUrl(season, starterIds.$1),
        ),
        home: TeamLineupData(
          teamId: boxscore.home.teamId,
          lineup: _lineupFromBatters(boxscore.home.batters),
          starterId: starterIds.$2,
          starterName:
              starterNames.$2 ?? boxscore.home.pitchers.firstOrNull?.name,
          starterImageUrl: _playerImageUrl(season, starterIds.$2),
        ),
      );
    } catch (_) {
      return _emptyLineupData(gameId, mainGame: mainGame);
    }
  }

  GameLineupData _emptyLineupData(
    String gameId, {
    Map<String, dynamic>? mainGame,
  }) {
    final starterNames = _starterNamesFromMainGame(mainGame);
    final starterIds = _starterIdsFromMainGame(mainGame);
    final season =
        _gameDateFromId(gameId)?.substring(0, 4) ??
        DateTime.now().year.toString();
    return GameLineupData(
      gameId: gameId,
      away: TeamLineupData(
        teamId: gameId.substring(8, 10),
        lineup: const [],
        starterId: starterIds.$1,
        starterName: starterNames.$1,
        starterImageUrl: _playerImageUrl(season, starterIds.$1),
      ),
      home: TeamLineupData(
        teamId: gameId.substring(10, 12),
        lineup: const [],
        starterId: starterIds.$2,
        starterName: starterNames.$2,
        starterImageUrl: _playerImageUrl(season, starterIds.$2),
      ),
    );
  }

  List<LineupEntry> _lineupFromBatters(List<BatterRecord> batters) {
    final ordered = batters
        .where((batter) => batter.name.isNotEmpty)
        .where((batter) => batter.order > 0)
        .toList();
    ordered.sort((a, b) => a.order.compareTo(b.order));
    return ordered
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

  List<BatterRecord> _parseHitterTeamFromTables(Map<String, dynamic> payload) {
    final table1 =
        jsonDecode(payload['table1'] as String) as Map<String, dynamic>;
    final table3 =
        jsonDecode(payload['table3'] as String) as Map<String, dynamic>;
    final rows1 = table1['rows'] as List<dynamic>? ?? const [];
    final rows3 = table3['rows'] as List<dynamic>? ?? const [];
    final length = rows1.length < rows3.length ? rows1.length : rows3.length;
    final batters = <BatterRecord>[];
    for (var i = 0; i < length; i++) {
      final left =
          ((rows1[i] as Map<String, dynamic>)['row'] as List<dynamic>? ??
                  const [])
              .map(
                (cell) => _stripHtml(
                  (cell as Map<String, dynamic>)['Text'] as String? ?? '',
                ).replaceAll('\u00a0', '').trim(),
              )
              .toList();
      final right =
          ((rows3[i] as Map<String, dynamic>)['row'] as List<dynamic>? ??
                  const [])
              .map(
                (cell) => _stripHtml(
                  (cell as Map<String, dynamic>)['Text'] as String? ?? '',
                ).replaceAll('\u00a0', '').trim(),
              )
              .toList();
      if (left.length < 3 || right.length < 4) {
        continue;
      }
      final order =
          left
              .map(_parseInt)
              .firstWhere(
                (value) => value != null && value > 0,
                orElse: () => null,
              ) ??
          0;
      final position = left.firstWhere(
        _looksLikePositionToken,
        orElse: () => left.length > 1 ? left[1] : '',
      );
      final name = left.lastWhere(
        (cell) => _parseInt(cell) == null && !_looksLikePositionToken(cell),
        orElse: () => left.last,
      );
      final numericStats = right
          .map((cell) => _parseInt(cell) ?? -1)
          .where((value) => value >= 0)
          .toList();
      batters.add(
        BatterRecord(
          order: order,
          position: _normalizePositionToken(position),
          name: name,
          atBats: numericStats.isNotEmpty ? numericStats[0] : 0,
          hits: numericStats.length > 1 ? numericStats[1] : 0,
          rbi: numericStats.length > 2 ? numericStats[2] : 0,
          runs: numericStats.length > 3 ? numericStats[3] : 0,
        ),
      );
    }
    return batters;
  }

  bool _looksLikePositionToken(String value) {
    const tokens = {
      '투',
      '포',
      '一',
      '二',
      '三',
      '유',
      '좌',
      '중',
      '우',
      '지',
      '중우',
      '좌중',
      '우중',
      '내',
      '외',
      'P',
      'C',
      '1B',
      '2B',
      '3B',
      'SS',
      'LF',
      'CF',
      'RF',
      'DH',
      'INF',
      'OF',
    };
    return tokens.contains(value) || _positionToCode(value) != value;
  }

  String _normalizePositionToken(String value) {
    const shorthand = {
      '투': 'P',
      '포': 'C',
      '一': '1B',
      '二': '2B',
      '三': '3B',
      '유': 'SS',
      '좌': 'LF',
      '중': 'CF',
      '우': 'RF',
      '지': 'DH',
      '중우': 'CF/RF',
      '좌중': 'LF/CF',
      '우중': 'RF/CF',
      '내': 'INF',
      '외': 'OF',
    };
    return shorthand[value] ?? _positionToCode(value);
  }

  List<PitcherRecord> _parsePitcherTeamFromTable(Map<String, dynamic> payload) {
    final table =
        jsonDecode(payload['table'] as String) as Map<String, dynamic>;
    final rows = table['rows'] as List<dynamic>? ?? const [];
    final headerMap = _headerIndexMap(table);
    final pitchers = <PitcherRecord>[];
    for (final row in rows) {
      final cells =
          ((row as Map<String, dynamic>)['row'] as List<dynamic>? ?? const [])
              .map(
                (cell) => _stripHtml(
                  (cell as Map<String, dynamic>)['Text'] as String? ?? '',
                ).replaceAll('\u00a0', '').trim(),
              )
              .toList();
      if (cells.length < 8) {
        continue;
      }
      String value(String header, {int? fallbackIndex}) {
        final index = headerMap[header] ?? fallbackIndex;
        if (index == null || index < 0 || index >= cells.length) {
          return '';
        }
        return cells[index];
      }

      final decision = value('결과', fallbackIndex: 2);
      pitchers.add(
        PitcherRecord(
          name: value('선수명', fallbackIndex: 0),
          innings: value('이닝', fallbackIndex: 6),
          hits: _parseInt(value('피안타', fallbackIndex: 10)) ?? 0,
          strikeouts: _parseInt(value('삼진', fallbackIndex: 13)) ?? 0,
          walks: _parseInt(value('4사구', fallbackIndex: 12)) ?? 0,
          earnedRuns: _parseInt(value('자책', fallbackIndex: 15)) ?? 0,
          decision:
              (decision.isEmpty || decision == '-' || decision == '&nbsp;')
              ? null
              : decision,
        ),
      );
    }
    return pitchers;
  }

  Map<String, int> _headerIndexMap(Map<String, dynamic> table) {
    final headers = table['headers'] as List<dynamic>? ?? const [];
    if (headers.isEmpty) {
      return const {};
    }
    final firstRow = headers.first as Map<String, dynamic>;
    final headerCells = firstRow['row'] as List<dynamic>? ?? const [];
    final result = <String, int>{};
    for (var index = 0; index < headerCells.length; index++) {
      final text = _stripHtml(
        (headerCells[index] as Map<String, dynamic>)['Text'] as String? ?? '',
      ).replaceAll('\u00a0', '').trim();
      if (text.isNotEmpty) {
        result[text] = index;
      }
    }
    return result;
  }

  Future<Map<String, dynamic>?> _getMainGameForGame(String gameId) async {
    final date = _gameDateFromId(gameId);
    if (date == null) {
      return null;
    }
    final map = await _getMainGameMap(date);
    return map[gameId];
  }

  Future<(List<PitcherRecord>, List<PitcherRecord>)> _enrichLivePitchers({
    required String gameId,
    required List<PitcherRecord> awayPitchers,
    required List<PitcherRecord> homePitchers,
  }) async {
    if (awayPitchers.isNotEmpty && homePitchers.isNotEmpty) {
      return (awayPitchers, homePitchers);
    }

    final mainGame = await _getMainGameForGame(gameId);
    final isLive = (mainGame?['GAME_STATE_SC']?.toString() == '2');
    if (!isLive) {
      return (awayPitchers, homePitchers);
    }

    final starterNames = _starterNamesFromMainGame(mainGame);
    final currentPitcher = await _currentPitcherContext(
      gameId,
      inningTextFallback: _formatMainGameInning(mainGame),
      mainGame: mainGame,
    );
    final relayBullpens = await _relayPitchersBySide(gameId);

    final awayMerged = _mergeSynthesizedPitchers(
      pitchers: awayPitchers,
      starterName: starterNames.$1,
      currentPitcherName: currentPitcher.$1 ? currentPitcher.$2 : null,
      relayPitchers: relayBullpens.$1,
    );
    final homeMerged = _mergeSynthesizedPitchers(
      pitchers: homePitchers,
      starterName: starterNames.$2,
      currentPitcherName: currentPitcher.$1 ? null : currentPitcher.$2,
      relayPitchers: relayBullpens.$2,
    );

    _log.info(
      'LINEUP_PITCHERS $gameId '
      'starterAway=${starterNames.$1} '
      'starterHome=${starterNames.$2} '
      'currentPitcher=${currentPitcher.$2} '
      'currentIsAway=${currentPitcher.$1} '
      'relayAway=${relayBullpens.$1.join(",")} '
      'relayHome=${relayBullpens.$2.join(",")} '
      'mergedAway=${awayMerged.map((e) => e.name).join(",")} '
      'mergedHome=${homeMerged.map((e) => e.name).join(",")}',
    );

    return (awayMerged, homeMerged);
  }

  (String?, String?) _starterNamesFromMainGame(Map<String, dynamic>? mainGame) {
    return (
      _cleanPlayerName(mainGame?['T_PIT_P_NM'] as String?),
      _cleanPlayerName(mainGame?['B_PIT_P_NM'] as String?),
    );
  }

  (String?, String?) _starterIdsFromMainGame(Map<String, dynamic>? mainGame) {
    return (
      _cleanPlayerId(mainGame?['T_PIT_P_ID']),
      _cleanPlayerId(mainGame?['B_PIT_P_ID']),
    );
  }

  String? _playerImageUrl(String season, String? playerId) {
    if (playerId == null || playerId.isEmpty) {
      return null;
    }
    return '$_kboPersonImageBase/$season/$playerId.jpg';
  }

  String? _cleanPlayerId(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }
    return text;
  }

  @visibleForTesting
  List<TeamStanding> parseStandingsHtmlForTesting(String html) {
    return _parseStandingsHtml(html);
  }

  @visibleForTesting
  CurrentAtBat? currentAtBatFromMainGameForTesting(
    Map<String, dynamic>? mainGame, {
    required String fallbackInning,
  }) {
    return _currentAtBatFromMainGame(mainGame, fallbackInning: fallbackInning);
  }

  @visibleForTesting
  CurrentAtBat? parseCurrentAtBatHtmlForTesting(String source) {
    return _parseCurrentAtBat(source);
  }

  @visibleForTesting
  GameLineupData? parseLineupAnalysisForTesting(
    String gameId,
    Object? payload, {
    Map<String, dynamic>? mainGame,
  }) {
    return _parseLineupAnalysisPayload(gameId, payload, mainGame: mainGame);
  }

  @visibleForTesting
  String deriveScheduleStatusForTesting(
    String actionHtml, {
    String statusText = '',
  }) {
    return _deriveScheduleStatus(actionHtml, statusText: statusText);
  }

  @visibleForTesting
  String? scheduleStatusLabelForTesting(String status, String statusText) {
    return _scheduleStatusLabel(status, statusText);
  }

  @visibleForTesting
  (String, bool) classifyRelayEventForTesting(String text) {
    return _classifyRelayEvent(text);
  }

  Future<(bool, String?)> _currentPitcherContext(
    String gameId, {
    required String inningTextFallback,
    required Map<String, dynamic>? mainGame,
  }) async {
    try {
      final current = await getCurrentAtBat(gameId);
      final pitcherName = _cleanPlayerName(current?.pitcherName);
      final inningText = current?.inningText ?? inningTextFallback;
      final isAwayPitching = inningText.contains('회말');
      final isHomePitching = inningText.contains('회초');
      if (pitcherName != null && (isAwayPitching || isHomePitching)) {
        return (isAwayPitching, pitcherName);
      }
    } catch (_) {}

    final inningText = inningTextFallback;
    final isAwayPitching = inningText.contains('회말');
    final isHomePitching = inningText.contains('회초');
    if (isAwayPitching || isHomePitching) {
      final mainGamePitcher = _cleanPlayerName(
        isAwayPitching
            ? (mainGame?['T_P_NM'] as String?)
            : (mainGame?['B_P_NM'] as String?),
      );
      if (mainGamePitcher != null) {
        return (isAwayPitching, mainGamePitcher);
      }
    }
    return (false, null);
  }

  String _formatMainGameInning(Map<String, dynamic>? mainGame) {
    if (mainGame == null) {
      return '';
    }
    final inningNo = mainGame['GAME_INN_NO'];
    final half = mainGame['GAME_TB_SC_NM'];
    if (inningNo != null &&
        half != null &&
        '$inningNo'.isNotEmpty &&
        '$half'.isNotEmpty) {
      return '$inningNo회$half';
    }
    return '';
  }

  List<PitcherRecord> _mergeSynthesizedPitchers({
    required List<PitcherRecord> pitchers,
    required String? starterName,
    required String? currentPitcherName,
    required List<String> relayPitchers,
  }) {
    final merged = <PitcherRecord>[...pitchers];

    void addIfMissing(String? name, {String? decision}) {
      final cleaned = _cleanPlayerName(name);
      if (cleaned == null) {
        return;
      }
      final exists = merged.any(
        (pitcher) => _cleanPlayerName(pitcher.name) == cleaned,
      );
      if (exists) {
        return;
      }
      merged.add(
        PitcherRecord(
          name: cleaned,
          innings: '',
          hits: 0,
          strikeouts: 0,
          walks: 0,
          earnedRuns: 0,
          decision: decision,
        ),
      );
    }

    addIfMissing(starterName);
    for (final relayPitcher in relayPitchers) {
      if (_cleanPlayerName(relayPitcher) == _cleanPlayerName(starterName)) {
        continue;
      }
      addIfMissing(relayPitcher);
    }
    if (_cleanPlayerName(currentPitcherName) != _cleanPlayerName(starterName)) {
      addIfMissing(currentPitcherName, decision: 'LIVE');
    }
    return merged;
  }

  Future<(List<String>, List<String>)> _relayPitchersBySide(
    String gameId,
  ) async {
    try {
      final html = await _fetchRelayHtml(gameId);
      final relayItems = _parseRelayItems(html);
      final away = <String>[];
      final home = <String>[];

      for (final item in relayItems) {
        final nextPitcher = _extractPitcherSubstitution(item.text);
        if (nextPitcher == null) {
          continue;
        }
        if (item.half == 'bottom') {
          if (!away.contains(nextPitcher)) {
            away.add(nextPitcher);
          }
        } else if (item.half == 'top') {
          if (!home.contains(nextPitcher)) {
            home.add(nextPitcher);
          }
        }
      }
      _log.info(
        'LINEUP_RELAY_PITCHERS $gameId away=${away.join(",")} home=${home.join(",")}',
      );
      return (away, home);
    } catch (error) {
      _log.warn('LINEUP_RELAY_PITCHERS_FAIL $gameId: $error');
      return (const <String>[], const <String>[]);
    }
  }

  String? _extractPitcherSubstitution(String text) {
    final normalized = _normalizeText(text);
    final match = RegExp(
      r'투수\s+(.+?)\s*:\s*투수\s+(.+?)\s+\(으\)로\s+교체',
    ).firstMatch(normalized);
    return _cleanPlayerName(match?.group(2));
  }

  String? _cleanPlayerName(String? value) {
    final normalized = _normalizeText(
      value ?? '',
    ).replaceAll(RegExp(r'\s+$'), '');
    return normalized.isEmpty ? null : normalized;
  }

  String _positionToCode(String positionKo) {
    const mapping = {
      '투수': 'P',
      '포수': 'C',
      '1루수': '1B',
      '2루수': '2B',
      '3루수': '3B',
      '유격수': 'SS',
      '좌익수': 'LF',
      '중견수': 'CF',
      '우익수': 'RF',
      '지명타자': 'DH',
    };
    return mapping[positionKo] ?? positionKo;
  }

  bool _shouldRequestLineup(Game? game) {
    if (game == null) {
      return false;
    }
    if (game.status == GameStatus.scheduled ||
        game.status == GameStatus.cancelled) {
      return false;
    }
    if (game.inning.contains('예정')) {
      return false;
    }
    final hasAnyLineScore =
        game.away.innings.any((score) => score != null) ||
        game.home.innings.any((score) => score != null);
    final hasBoxTotals =
        game.away.hits > 0 ||
        game.home.hits > 0 ||
        game.away.walks > 0 ||
        game.home.walks > 0;
    return hasAnyLineScore || hasBoxTotals || game.status == GameStatus.live;
  }

  // ── 유틸 ──

  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString().replaceAll(',', ''));
  }

  Future<void> _ensureRelayLoggedIn({bool queued = true}) async {
    if (_relayLoggedIn) {
      return;
    }
    _sessionCookies.clear();
    final loginPage = await _getPlain('/Member/Login.aspx', queued: queued);
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
        'ctl00\$ctl00\$ctl00\$cphContents\$cphContents\$cphContents\$txtUserId':
            _relayUserId,
        'ctl00\$ctl00\$ctl00\$cphContents\$cphContents\$cphContents\$txtPassWord':
            _relayPassword,
        'ctl00\$ctl00\$ctl00\$cphContents\$cphContents\$cphContents\$btnLogin.x':
            '42',
        'ctl00\$ctl00\$ctl00\$cphContents\$cphContents\$cphContents\$btnLogin.y':
            '16',
        'ctl00\$ctl00\$ctl00\$cphContents\$cphContents\$cphContents\$hdUrl': '',
      },
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      },
      allowRedirect: true,
      queued: queued,
    );

    if (_sessionCookies.keys.any((key) => key.toLowerCase().contains('auth')) ||
        _sessionCookies.keys.any(
          (key) => key.toLowerCase().contains('member'),
        ) ||
        body.contains('로그아웃') ||
        body.contains('LogOut.aspx')) {
      _relayLoggedIn = true;
      return;
    }

    if (!body.contains('로그아웃') && !body.contains('LogOut.aspx')) {
      throw StateError('KBO relay login failed');
    }
    _relayLoggedIn = true;
  }

  void _resetRelaySession() {
    _relayLoggedIn = false;
    _sessionCookies.clear();
  }

  Future<Map<String, dynamic>?> _loadView1ScoreboardDetail(
    String gameId, {
    required int seriesId,
    required bool shouldLoad,
  }) async {
    if (!shouldLoad) {
      return null;
    }
    try {
      final noCacheHeaders = _relayNoCacheHeaders(
        baseHeaders: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
        cacheBuster: DateTime.now().microsecondsSinceEpoch,
      );
      final html = await _postPlain(
        '/Game/LiveTextView1.aspx?_ts=${noCacheHeaders.$2}',
        {
          'leagueId': 1,
          'seriesId': seriesId,
          'gameId': gameId,
          'gyear': gameId.substring(0, 4),
        },
        headers: noCacheHeaders.$1,
        allowNotModified: true,
      );
      if (html.isEmpty) {
        final retryHeaders = _relayNoCacheHeaders(
          baseHeaders: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
          cacheBuster: DateTime.now().millisecondsSinceEpoch,
        );
        final retriedHtml = await _postPlain(
          '/Game/LiveTextView1.aspx?_ts=${retryHeaders.$2}',
          {
            'leagueId': 1,
            'seriesId': seriesId,
            'gameId': gameId,
            'gyear': gameId.substring(0, 4),
          },
          headers: retryHeaders.$1,
        );
        if (retriedHtml.isEmpty) {
          return null;
        }
        return _parseView1ScoreboardDetail(retriedHtml);
      }
      return _parseView1ScoreboardDetail(html);
    } catch (error) {
      _log.warn('KBO view1 scoreboard fallback failed for $gameId: $error');
      return null;
    }
  }

  Map<String, dynamic>? _parseView1ScoreboardDetail(String html) {
    final document = html_parser.parse(html);
    final scoreRows = document
        .querySelectorAll('#tblScoreBoard2 tr')
        .where((row) => row.querySelectorAll('td').isNotEmpty)
        .toList();
    final totalRows = document
        .querySelectorAll('#tblScoreBoard3 tr')
        .where((row) => row.querySelectorAll('td').isNotEmpty)
        .toList();
    final totalHeaderCells = document.querySelectorAll(
      '#tblScoreBoard3 thead th',
    );
    if (scoreRows.length < 2) {
      return null;
    }

    List<int?> parseScores(dom.Element row) {
      return row
          .querySelectorAll('td')
          .map((cell) => _parseInt(cell.text.trim()))
          .toList();
    }

    final totalHeaderMap = <String, int>{};
    for (var index = 0; index < totalHeaderCells.length; index++) {
      final text = totalHeaderCells[index].text.trim();
      if (text.isNotEmpty) {
        totalHeaderMap[text] = index;
      }
    }

    Map<String, int?> parseTotals(dom.Element? row) {
      final cells = row?.querySelectorAll('td') ?? const <dom.Element>[];
      int? at(String key, int fallbackIndex) {
        final index = totalHeaderMap[key] ?? fallbackIndex;
        if (index < 0 || index >= cells.length) {
          return null;
        }
        return _parseInt(cells[index].text.trim());
      }

      return {'hits': at('H', 1), 'errors': at('E', 2), 'balls': at('B', 3)};
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
    final containers =
        document
            .querySelectorAll('[id^="numCont"]')
            .where((node) => node.id.startsWith('numCont'))
            .toList()
          ..sort((a, b) {
            final aNo = int.tryParse(a.id.replaceFirst('numCont', '')) ?? 0;
            final bNo = int.tryParse(b.id.replaceFirst('numCont', '')) ?? 0;
            return aNo.compareTo(bNo);
          });

    for (final container in containers) {
      final inning =
          int.tryParse(container.id.replaceFirst('numCont', '')) ?? 0;
      if (inning <= 0) {
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

    final strongs = present
        .querySelectorAll('strong')
        .map((e) => _normalizeText(e.text))
        .toList();
    final inningText = strongs.isNotEmpty ? strongs.first : '';
    final countText = strongs.length > 1 ? strongs[1] : '';
    final batterText = _currentBatterText(playerNames);
    final pitcherText = _normalizeText(
      playerNames.querySelector('li.pitcher')?.text ?? '',
    );
    final batterMeta = _parsePlayerInfoBox(
      _currentBatterBox(document, inningText),
    );
    final pitcherMeta = _parsePlayerInfoBox(
      _currentPitcherBox(document, inningText),
    );
    final counts = _parseCountText(countText);
    final runnerNames = _parseRunnerNames(document);
    final parsedBaseState = _parseBaseState(
      present.querySelector('#imgThisGameBase'),
    );
    final baseState = parsedBaseState.isNotEmpty
        ? parsedBaseState
        : _baseStateFromRunnerNames(runnerNames);

    if (inningText.isEmpty &&
        countText.isEmpty &&
        batterText.isEmpty &&
        pitcherText.isEmpty) {
      return null;
    }

    return CurrentAtBat(
      batterName: batterText.isNotEmpty ? batterText : batterMeta.name,
      batterImageUrl: batterMeta.imageUrl,
      batterNumber: batterMeta.number,
      batterHand: batterMeta.hand,
      batterRecent: batterMeta.recent,
      batterAverage: batterMeta.average,
      pitcherName: pitcherText.isNotEmpty ? pitcherText : pitcherMeta.name,
      pitcherImageUrl: pitcherMeta.imageUrl,
      pitcherNumber: pitcherMeta.number,
      pitcherHand: pitcherMeta.hand,
      pitcherEra: pitcherMeta.era,
      pitchCount: pitcherMeta.pitchCount,
      inningText: inningText,
      baseState: baseState,
      firstRunnerName: runnerNames.$1,
      secondRunnerName: runnerNames.$2,
      thirdRunnerName: runnerNames.$3,
      balls: counts.$1,
      strikes: counts.$2,
      outs: counts.$3,
    );
  }

  String _currentBatterText(dom.Element playerNames) {
    for (final selector in ['li.supervision', 'li.supervision2']) {
      final text = _normalizeText(
        playerNames.querySelector(selector)?.text ?? '',
      );
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  dom.Element? _currentBatterBox(dom.Document document, String inningText) {
    final explicit = document.querySelector('.playerBox .batter');
    if (explicit != null) {
      return explicit;
    }
    final isTop = _isTopInning(inningText, null);
    return isTop
        ? document.querySelector('.playerBox.awayBox')
        : document.querySelector('.playerBox.homeBox');
  }

  dom.Element? _currentPitcherBox(dom.Document document, String inningText) {
    final explicit = document.querySelector('.playerBox .pitcher');
    if (explicit != null) {
      return explicit;
    }
    final isTop = _isTopInning(inningText, null);
    return isTop
        ? document.querySelector('.playerBox.homeBox')
        : document.querySelector('.playerBox.awayBox');
  }

  (String, String, String) _parseRunnerNames(dom.Document document) {
    String resolveBySelectors(List<String> selectors) {
      for (final selector in selectors) {
        final node = document.querySelector(selector);
        final text = _cleanPlayerName(node?.text);
        if (text != null && text.isNotEmpty) {
          return text;
        }
      }
      return '';
    }

    final first = resolveBySelectors([
      '#txtBase1',
      '#base1Player',
      '.base1 .name',
      '.runner-first .name',
      '.baseRunner.first',
    ]);
    final second = resolveBySelectors([
      '#txtBase2',
      '#base2Player',
      '.base2 .name',
      '.runner-second .name',
      '.baseRunner.second',
    ]);
    final third = resolveBySelectors([
      '#txtBase3',
      '#base3Player',
      '.base3 .name',
      '.runner-third .name',
      '.baseRunner.third',
    ]);

    return (first, second, third);
  }

  String _baseStateFromRunnerNames((String, String, String) runnerNames) {
    final occupied = [
      runnerNames.$1.isNotEmpty,
      runnerNames.$2.isNotEmpty,
      runnerNames.$3.isNotEmpty,
    ];
    if (!occupied[0] && !occupied[1] && !occupied[2]) {
      return '';
    }
    if (occupied[0] && !occupied[1] && !occupied[2]) {
      return '주자1루';
    }
    if (!occupied[0] && occupied[1] && !occupied[2]) {
      return '주자2루';
    }
    if (!occupied[0] && !occupied[1] && occupied[2]) {
      return '주자3루';
    }
    if (occupied[0] && occupied[1] && !occupied[2]) {
      return '주자1,2루';
    }
    if (occupied[0] && !occupied[1] && occupied[2]) {
      return '주자1,3루';
    }
    if (!occupied[0] && occupied[1] && occupied[2]) {
      return '주자2,3루';
    }
    return '만루';
  }

  (String, bool) _classifyRelayEvent(String text) {
    if (text.contains('경기종료')) return ('GAME_END', false);
    if (text.contains('포일')) {
      return ('PASSED_BALL', text.contains('득점') || text.contains('홈인'));
    }
    if (text.contains('홈런')) return ('HOMERUN', true);
    if (text.contains('득점') || text.contains('홈인')) return ('RUNS', true);
    if (text.contains('볼넷')) return ('WALK', false);
    if (text.contains('삼진')) return ('STRIKEOUT', false);
    if (text.contains('플라이 아웃') ||
        text.contains('땅볼 아웃') ||
        text.contains('아웃')) {
      return ('OUT', false);
    }
    if (text.contains('교체')) return ('SUBSTITUTION', false);
    if (text.contains('안타') ||
        text.contains('1루타') ||
        text.contains('2루타') ||
        text.contains('3루타')) {
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

  ({
    String name,
    int number,
    String hand,
    int pitchCount,
    String recent,
    String average,
    String era,
    String imageUrl,
  })
  _parsePlayerInfoBox(dom.Element? element) {
    if (element == null) {
      return (
        name: '',
        number: 0,
        hand: '',
        pitchCount: 0,
        recent: '',
        average: '',
        era: '',
        imageUrl: '',
      );
    }
    final playerInfo = element.querySelector('.player-info-wrap') ?? element;
    final numberText = _normalizeText(
      playerInfo.querySelector('.no')?.text ?? '',
    );
    final hand = _normalizeText(
      playerInfo.querySelector('.who span:last-child')?.text ?? '',
    ).replaceAll(RegExp(r'^\(|\)$'), '');
    final todayText = _normalizeText(
      playerInfo.querySelector('.today span')?.text ?? '',
    );
    final pitchCountMatch = RegExp(r'(\d+)\s*투구').firstMatch(todayText);
    final imageSrc =
        playerInfo.querySelector('.player-img img.pic')?.attributes['src'] ??
        '';
    final imageUrl = _normalizeRelayPlayerImageUrl(imageSrc);

    var name = numberText;
    var number = 0;
    final match = RegExp(r'No\.(\d+)\s+(.+)').firstMatch(numberText);
    if (match != null) {
      number = int.tryParse(match.group(1) ?? '') ?? 0;
      name = match.group(2) ?? '';
    }
    return (
      name: name,
      number: number,
      hand: hand,
      pitchCount: int.tryParse(pitchCountMatch?.group(1) ?? '') ?? 0,
      recent: pitchCountMatch != null || todayText == '-' ? '' : todayText,
      average: _parseLiveBattingAverage(element, todayText),
      era: _parseSeasonStat(element, const ['ERA', '평균자책', '평균자책점']),
      imageUrl: imageUrl,
    );
  }

  String _parseLiveBattingAverage(dom.Element element, String todayText) {
    final seasonAverage = _parseSeasonStat(element, const ['타율', 'AVG']);
    final seasonAtBats = _parseSeasonStatInt(element, const ['타수', 'AB']);
    final seasonHits = _parseSeasonStatInt(element, const ['안타', 'H']);
    final todayLine = _parseTodayBattingLine(todayText);

    if (seasonAtBats == null ||
        seasonHits == null ||
        todayLine.atBats <= 0 ||
        seasonAtBats + todayLine.atBats <= 0) {
      return seasonAverage;
    }

    final average =
        (seasonHits + todayLine.hits) / (seasonAtBats + todayLine.atBats);
    return average.toStringAsFixed(3);
  }

  String _parseSeasonStat(dom.Element element, List<String> headerCandidates) {
    for (final table in element.querySelectorAll('table')) {
      final headers = table
          .querySelectorAll('thead th')
          .map((header) => _normalizeText(header.text))
          .toList();
      final statIndex = headers.indexWhere(headerCandidates.contains);
      if (statIndex < 0) {
        continue;
      }

      for (final row in table.querySelectorAll('tbody tr')) {
        final cells = row.querySelectorAll('th, td');
        if (cells.isEmpty || statIndex >= cells.length) {
          continue;
        }
        final label = _normalizeText(cells.first.text);
        if (label != '시즌') {
          continue;
        }
        final value = _normalizeText(cells[statIndex].text);
        if (value.isNotEmpty && value != '-') {
          return value;
        }
      }
    }
    return '';
  }

  int? _parseSeasonStatInt(dom.Element element, List<String> headerCandidates) {
    final value = _parseSeasonStat(element, headerCandidates);
    if (value.isEmpty) {
      return null;
    }
    final match = RegExp(r'\d+').firstMatch(value.replaceAll(',', ''));
    return int.tryParse(match?.group(0) ?? '');
  }

  ({int atBats, int hits}) _parseTodayBattingLine(String todayText) {
    var atBats = 0;
    var hits = 0;
    for (final rawResult in todayText.split('|')) {
      final result = _normalizeText(rawResult);
      if (result.isEmpty || result == '-') {
        continue;
      }
      if (_isNonAtBatResult(result)) {
        continue;
      }
      if (_isHitResult(result)) {
        atBats += 1;
        hits += 1;
        continue;
      }
      if (_isAtBatResult(result)) {
        atBats += 1;
      }
    }
    return (atBats: atBats, hits: hits);
  }

  bool _isNonAtBatResult(String result) {
    return const [
      '4구',
      '볼넷',
      '고의',
      '사구',
      '몸에 맞',
      '희생',
      '희비',
      '희번',
      '타격방해',
      '포수방해',
    ].any(result.contains);
  }

  bool _isHitResult(String result) {
    if (const ['안타', '1루타', '2루타', '3루타', '홈런'].any(result.contains)) {
      return true;
    }
    return RegExp(r'(좌|중|우|내야|번트).*(안|홈)$').hasMatch(result);
  }

  bool _isAtBatResult(String result) {
    if (const [
      '삼진',
      '땅볼',
      '플라이',
      '파울플라이',
      '직선타',
      '라인드라이브',
      '병살',
      '실책',
      '야수선택',
      '야선',
      '아웃',
    ].any(result.contains)) {
      return true;
    }
    return result.endsWith('땅') || result.endsWith('비') || result.endsWith('직');
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

  int _seriesIdFromMainGame(Map<String, dynamic>? mainGame) {
    final raw = mainGame?['SR_ID'];
    if (raw is int) {
      return raw;
    }
    return int.tryParse('${raw ?? ''}') ?? 0;
  }

  _ScheduleRow _parseScheduleTableRow(
    List<dynamic> cells,
    String? currentDate,
    String seasonId,
  ) {
    if (cells.length < 7) {
      throw StateError('Schedule row cells too short: ${cells.length}');
    }
    var offset = 0;
    final firstText = _stripHtml(cells[0]['Text'] as String? ?? '');
    if (RegExp(r'^\d{2}\.\d{2}\(.+\)$').hasMatch(firstText)) {
      final parts = firstText.split('(').first.split('.');
      currentDate = '$seasonId-${parts[0]}-${parts[1]}';
      offset = 1;
    }
    if (cells.length <= offset + 6) {
      throw StateError(
        'Schedule row cells too short after offset: ${cells.length} (offset=$offset)',
      );
    }

    final time = _stripHtml(cells[offset]['Text'] as String? ?? '');
    final playHtml = cells[offset + 1]['Text'] as String? ?? '';
    final actionHtml = cells[offset + 2]['Text'] as String? ?? '';
    final statusText = cells.length > offset + 7
        ? _stripHtml(cells[offset + 7]['Text'] as String? ?? '')
        : '';
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
    final status = _deriveScheduleStatus(actionHtml, statusText: statusText);

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
      statusLabel: _scheduleStatusLabel(status, statusText),
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

  String _deriveScheduleStatus(String actionHtml, {String statusText = ''}) {
    if (statusText.contains('취소')) {
      return 'CANCELLED';
    }
    if (statusText.contains('서스펜디드') || statusText.contains('중단')) {
      return 'SUSPENDED';
    }
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

  String? _scheduleStatusLabel(String status, String statusText) {
    final label = _normalizeText(statusText);
    if (label.isEmpty || label == '정상경기') {
      return null;
    }
    if (status == 'CANCELLED' || status == 'SUSPENDED') {
      return label;
    }
    return null;
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

  Future<List<HighlightVideo>> _fetchYoutubeHighlightVideos({
    required String gameId,
    required String awayName,
    required String homeName,
    int limit = 4,
  }) async {
    try {
      final month = gameId.substring(4, 6).replaceFirst(RegExp(r'^0'), '');
      final day = gameId.substring(6, 8).replaceFirst(RegExp(r'^0'), '');
      final response = await _dio.get<String>(
        '$_youtubeBase/results',
        queryParameters: {
          'search_query': '$month월 $day일 $awayName $homeName 하이라이트',
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
          },
        ),
      );
      final html = response.data ?? '';
      final matches = RegExp(r'"videoId":"([A-Za-z0-9_-]{11})"')
          .allMatches(html)
          .map((match) => match.group(1) ?? '')
          .where((videoId) => videoId.isNotEmpty)
          .toList();
      final seen = <String>{};
      final videos = <HighlightVideo>[];
      for (final videoId in matches) {
        if (!seen.add(videoId)) {
          continue;
        }
        videos.add(
          HighlightVideo(
            videoId: videoId,
            title: '$awayName vs $homeName 하이라이트',
            thumbnailUrl: 'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
            videoUrl: '$_youtubeBase/watch?v=$videoId',
            source: 'youtube_search',
          ),
        );
        if (videos.length >= limit) {
          break;
        }
      }
      return videos;
    } catch (error) {
      _log.warn('YOUTUBE highlight fetch failed for $gameId: $error');
      return const <HighlightVideo>[];
    }
  }

  String _buildOfficialHighlightUrl(String gameId) {
    final date = _gameDateFromId(gameId)!.replaceAll('-', '');
    return 'https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx?gameDate=$date&gameId=$gameId&section=HIGHLIGHT';
  }

  Future<RelayData> _buildSummaryRelayFallback(
    String gameId, {
    int? afterSeqNo,
    Map<String, dynamic>? mainGameSnapshot,
  }) async {
    Game? game;
    Map<String, dynamic>? mainGame = mainGameSnapshot;
    try {
      game = await getGame(
        gameId,
      ).timeout(_relaySummaryTimeout, onTimeout: () => null);
    } catch (error) {
      _log.warn('KBO relay summary game lookup failed for $gameId: $error');
    }
    if (mainGame == null) {
      try {
        mainGame = await _getMainGameForGame(
          gameId,
        ).timeout(_relayGameLookupTimeout, onTimeout: () => null);
      } catch (error) {
        _log.warn('KBO relay summary main lookup failed for $gameId: $error');
      }
    }
    if (game == null) {
      return const RelayData(currentAtBat: null, relayItems: []);
    }
    if (shouldSuppressDirectRelaySummaryFallback(game.status)) {
      return const RelayData(currentAtBat: null, relayItems: []);
    }

    final items = <RelayItem>[];
    var seqNo = 1;
    final inningIndexes = directRelaySummaryInningIndexes(game);

    if (inningIndexes.isEmpty) {
      return RelayData(
        currentAtBat: game.status == GameStatus.live
            ? _currentAtBatFromMainGame(mainGame, fallbackInning: game.inning)
            : null,
        relayItems: const [],
      );
    }

    for (final i in inningIndexes) {
      final inning = i + 1;
      final awayRuns = i < game.away.innings.length
          ? game.away.innings[i]
          : null;
      final homeRuns = i < game.home.innings.length
          ? game.home.innings[i]
          : null;

      items.add(
        RelayItem(
          seqNo: seqNo++,
          inning: inning,
          half: 'top',
          event: 'INNING_CHANGE',
          text: '$inning회초 공격 ---------------------------------------',
        ),
      );

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
      } else if (awayRuns != null) {
        items.add(
          RelayItem(
            seqNo: seqNo++,
            inning: inning,
            half: 'top',
            event: 'PLAY',
            text: '$inning회초 ${game.away.shortName} 무득점',
          ),
        );
      }

      items.add(
        RelayItem(
          seqNo: seqNo++,
          inning: inning,
          half: 'bottom',
          event: 'INNING_CHANGE',
          text: '$inning회말 공격 ---------------------------------------',
        ),
      );

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
      } else if (homeRuns != null) {
        items.add(
          RelayItem(
            seqNo: seqNo++,
            inning: inning,
            half: 'bottom',
            event: 'PLAY',
            text: '$inning회말 ${game.home.shortName} 무득점',
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
          text:
              '경기종료 ${game.away.shortName} ${game.away.score} : ${game.home.score} ${game.home.shortName}',
        ),
      );
    }

    final filtered = afterSeqNo == null
        ? items
        : items.where((item) => item.seqNo > afterSeqNo).toList();

    return RelayData(
      currentAtBat: game.status == GameStatus.final_
          ? null
          : _currentAtBatFromMainGame(mainGame, fallbackInning: game.inning),
      relayItems: filtered,
    );
  }

  CurrentAtBat? _currentAtBatFromMainGame(
    Map<String, dynamic>? mainGame, {
    required String fallbackInning,
  }) {
    if (mainGame == null) {
      return null;
    }

    final inningText = _formatMainGameInning(mainGame).isNotEmpty
        ? _formatMainGameInning(mainGame)
        : fallbackInning;
    final normalizedInningText = inningText.replaceAll(RegExp(r'\s+'), '');
    final isTop = _isTopInning(inningText, mainGame);
    final isBottom =
        normalizedInningText.contains('회말') ||
        (!isTop && mainGame['GAME_TB_SC_NM']?.toString() == '말');

    final batterName = _cleanPlayerName(
      isTop
          ? mainGame['T_P_NM'] as String?
          : isBottom
          ? mainGame['B_P_NM'] as String?
          : null,
    );
    final pitcherName = _cleanPlayerName(
      isTop
          ? mainGame['B_P_NM'] as String?
          : isBottom
          ? mainGame['T_P_NM'] as String?
          : null,
    );
    final season = _seasonFromMainGame(mainGame);
    final batterId = _currentMainGameBatterId(mainGame, isTop: isTop);
    final pitcherId = _currentMainGamePitcherId(
      mainGame,
      isTop: isTop,
      pitcherName: pitcherName,
    );

    final baseOrders = [
      _parseInt(mainGame['B1_BAT_ORDER_NO']) ?? 0,
      _parseInt(mainGame['B2_BAT_ORDER_NO']) ?? 0,
      _parseInt(mainGame['B3_BAT_ORDER_NO']) ?? 0,
    ];

    return CurrentAtBat(
      batterName: batterName ?? '',
      batterImageUrl: _playerImageUrl(season, batterId) ?? '',
      batterNumber: 0,
      batterHand: '',
      batterRecent: '',
      pitcherName: pitcherName ?? '',
      pitcherImageUrl: _playerImageUrl(season, pitcherId) ?? '',
      pitcherNumber: 0,
      pitcherHand: '',
      pitchCount: 0,
      inningText: inningText,
      baseState: _baseStateFromOrders(baseOrders),
      firstRunnerName: _cleanPlayerName(mainGame['B1_P_NM'] as String?) ?? '',
      secondRunnerName: _cleanPlayerName(mainGame['B2_P_NM'] as String?) ?? '',
      thirdRunnerName: _cleanPlayerName(mainGame['B3_P_NM'] as String?) ?? '',
      balls: _parseInt(mainGame['BALL_CN']) ?? 0,
      strikes: _parseInt(mainGame['STRIKE_CN']) ?? 0,
      outs: _parseInt(mainGame['OUT_CN']) ?? 0,
    );
  }

  CurrentAtBat? _currentAtBatWithMainGameImages(
    CurrentAtBat? atBat,
    Map<String, dynamic>? mainGame,
  ) {
    if (atBat == null || mainGame == null) {
      return atBat;
    }

    final season = _seasonFromMainGame(mainGame);
    final inningText = atBat.inningText.isNotEmpty
        ? atBat.inningText
        : _formatMainGameInning(mainGame);
    final isTop = _isTopInning(inningText, mainGame);
    final batterId = _currentMainGameBatterId(mainGame, isTop: isTop);
    final pitcherId = _currentMainGamePitcherId(
      mainGame,
      isTop: isTop,
      pitcherName: atBat.pitcherName,
    );

    final batterImageUrl = _preferredRelayPlayerImageUrl(
      atBat.batterImageUrl,
      season: season,
      playerId: batterId,
    );
    final pitcherImageUrl = _preferredRelayPlayerImageUrl(
      atBat.pitcherImageUrl,
      season: season,
      playerId: pitcherId,
    );

    if (batterImageUrl == atBat.batterImageUrl &&
        pitcherImageUrl == atBat.pitcherImageUrl) {
      return atBat;
    }

    return CurrentAtBat(
      batterName: atBat.batterName,
      batterImageUrl: batterImageUrl,
      batterNumber: atBat.batterNumber,
      batterHand: atBat.batterHand,
      batterRecent: atBat.batterRecent,
      batterAverage: atBat.batterAverage,
      pitcherName: atBat.pitcherName,
      pitcherImageUrl: pitcherImageUrl,
      pitcherNumber: atBat.pitcherNumber,
      pitcherHand: atBat.pitcherHand,
      pitcherEra: atBat.pitcherEra,
      pitchCount: atBat.pitchCount,
      inningText: atBat.inningText,
      baseState: atBat.baseState,
      firstRunnerName: atBat.firstRunnerName,
      secondRunnerName: atBat.secondRunnerName,
      thirdRunnerName: atBat.thirdRunnerName,
      balls: atBat.balls,
      strikes: atBat.strikes,
      outs: atBat.outs,
    );
  }

  String _preferredRelayPlayerImageUrl(
    String currentUrl, {
    required String season,
    required String? playerId,
  }) {
    final normalized = _normalizeRelayPlayerImageUrl(currentUrl);
    if (_isUsableRelayPlayerImageUrl(normalized)) {
      return normalized;
    }
    return _playerImageUrl(season, playerId) ?? '';
  }

  String _normalizeRelayPlayerImageUrl(String imageSrc) {
    final src = imageSrc.trim();
    if (src.isEmpty) {
      return '';
    }
    if (src.startsWith('//')) {
      return 'https:$src';
    }
    if (src.startsWith('/')) {
      return '$_kboBase$src';
    }
    return src;
  }

  bool _isUsableRelayPlayerImageUrl(String imageUrl) {
    if (imageUrl.isEmpty) {
      return false;
    }
    final lower = imageUrl.toLowerCase();
    return !lower.contains('noimage') &&
        !lower.contains('no_img') &&
        !lower.contains('noimg') &&
        !lower.contains('no_photo') &&
        !lower.contains('player_no') &&
        !lower.contains('playernone');
  }

  String _seasonFromMainGame(Map<String, dynamic>? mainGame) {
    final season = mainGame?['SEASON_ID']?.toString() ?? '';
    if (RegExp(r'^\d{4}$').hasMatch(season)) {
      return season;
    }
    final gameId = mainGame?['G_ID']?.toString() ?? '';
    if (gameId.length >= 4) {
      return gameId.substring(0, 4);
    }
    return DateTime.now().year.toString();
  }

  bool _isTopInning(String inningText, Map<String, dynamic>? mainGame) {
    final normalized = inningText.replaceAll(RegExp(r'\s+'), '');
    if (normalized.contains('회초')) {
      return true;
    }
    if (normalized.contains('회말')) {
      return false;
    }
    return mainGame?['GAME_TB_SC_NM']?.toString() == '초';
  }

  String? _currentMainGameBatterId(
    Map<String, dynamic>? mainGame, {
    required bool isTop,
  }) {
    return _cleanPlayerId(mainGame?[isTop ? 'T_P_ID' : 'B_P_ID']);
  }

  String? _currentMainGamePitcherId(
    Map<String, dynamic>? mainGame, {
    required bool isTop,
    required String? pitcherName,
  }) {
    final currentId = _cleanPlayerId(mainGame?[isTop ? 'B_P_ID' : 'T_P_ID']);
    if (currentId != null) {
      return currentId;
    }

    final starterName = _cleanPlayerName(
      mainGame?[isTop ? 'B_PIT_P_NM' : 'T_PIT_P_NM'] as String?,
    );
    if (_cleanPlayerName(pitcherName) == starterName) {
      return _cleanPlayerId(mainGame?[isTop ? 'B_PIT_P_ID' : 'T_PIT_P_ID']);
    }
    return null;
  }

  String _baseStateFromOrders(List<int> orders) {
    final first = orders[0] > 0;
    final second = orders[1] > 0;
    final third = orders[2] > 0;
    if (!first && !second && !third) {
      return '주자없음';
    }
    if (first && !second && !third) {
      return '주자1루';
    }
    if (!first && second && !third) {
      return '주자2루';
    }
    if (first && second && !third) {
      return '주자1,2루';
    }
    if (!first && !second && third) {
      return '주자3루';
    }
    if (first && !second && third) {
      return '주자1,3루';
    }
    if (!first && second && third) {
      return '주자2,3루';
    }
    return '만루';
  }
}

@visibleForTesting
bool shouldSuppressDirectRelaySummaryFallback(GameStatus status) {
  return status == GameStatus.scheduled ||
      status == GameStatus.cancelled ||
      status == GameStatus.suspended;
}

@visibleForTesting
List<int> directRelaySummaryInningIndexes(Game game) {
  final innings = game.away.innings.length > game.home.innings.length
      ? game.away.innings.length
      : game.home.innings.length;
  return [
    for (var i = 0; i < innings; i++)
      if ((i < game.away.innings.length ? game.away.innings[i] : null) !=
              null ||
          (i < game.home.innings.length ? game.home.innings[i] : null) != null)
        i,
  ];
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
  final String? statusLabel;

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
    required this.statusLabel,
  });
}
