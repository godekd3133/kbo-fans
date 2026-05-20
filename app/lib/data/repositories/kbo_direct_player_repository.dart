import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../models/player.dart';
import '../models/records_overview.dart';
import '../models/team_records_bundle.dart';
import '../models/team_stats.dart';
import 'player_repository.dart';

class KboDirectPlayerRepository implements PlayerRepository {
  static const _kboBase = 'https://www.koreabaseball.com';
  static const _playerSearchUrl =
      'https://eng.koreabaseball.com/Teams/PlayerSearch.aspx';
  static const _registerAllUrl = '$_kboBase/Player/RegisterAll.aspx';
  static const _hitterDetailUrl =
      '$_kboBase/Record/Player/HitterDetail/Basic.aspx?playerId={playerId}';
  static const _pitcherDetailUrl =
      '$_kboBase/Record/Player/PitcherDetail/Basic.aspx?playerId={playerId}';
  static const _hitterTotalUrl =
      '$_kboBase/Record/Player/HitterDetail/Total.aspx?playerId={playerId}';
  static const _pitcherTotalUrl =
      '$_kboBase/Record/Player/PitcherDetail/Total.aspx?playerId={playerId}';
  static const _hitterAvgUrl =
      '$_kboBase/Record/Player/HitterBasic/Basic1.aspx?sort=HRA_RT';
  static const _hitterHrUrl =
      '$_kboBase/Record/Player/HitterBasic/Basic1.aspx?sort=HR_CN';
  static const _hitterOpsUrl =
      '$_kboBase/Record/Player/HitterBasic/Basic2.aspx?sort=OPS_RT';
  static const _pitcherEraUrl =
      '$_kboBase/Record/Player/PitcherBasic/Basic1.aspx?sort=ERA_RT';
  static const _seasonField =
      'ctl00\$ctl00\$ctl00\$cphContents\$cphContents\$cphContents\$ddlSeason\$ddlSeason';
  static const _teamField =
      'ctl00\$ctl00\$ctl00\$cphContents\$cphContents\$cphContents\$ddlTeam\$ddlTeam';
  static const _leaderboardMetrics =
      <LeaderboardMetric, (String, String, String)>{
        LeaderboardMetric.avg: (_hitterAvgUrl, 'AVG', 'hitter'),
        LeaderboardMetric.hr: (_hitterHrUrl, 'HR', 'hitter'),
        LeaderboardMetric.ops: (_hitterOpsUrl, 'OPS', 'hitter'),
        LeaderboardMetric.opsPlus: (_hitterOpsUrl, 'OPS', 'hitter'),
        LeaderboardMetric.era: (_pitcherEraUrl, 'ERA', 'pitcher'),
      };
  static final _recordPlayerLinkPattern = RegExp(
    r'href="/Record/(?:Player/(?:Hitter|Pitcher)Detail/Basic|Retire/(?:Hitter|Pitcher))\.aspx\?playerId=(\d+)"',
    caseSensitive: false,
  );
  static const _teamHitterUrl = '$_kboBase/Record/Team/Hitter/Basic1.aspx';
  static const _teamPitcherUrl = '$_kboBase/Record/Team/Pitcher/Basic1.aspx';

  static const _teamSearchCodeMap = {
    'LG': 'lg',
    'KT': 'kt',
    'SK': 'sk',
    'SS': 'ss',
    'NC': 'nc',
    'HH': 'hh',
    'LT': 'lt',
    'HT': 'ht',
    'OB': 'ob',
    'WO': 'wo',
  };

  static const _registerTeamNameMap = {
    'LG': 'LG',
    'KT': 'KT',
    'SK': 'SSG',
    'SS': '삼성',
    'NC': 'NC',
    'HH': '한화',
    'LT': '롯데',
    'HT': 'KIA',
    'OB': '두산',
    'WO': '키움',
  };

  static const _positionGroups = ['1', '2', '3,4,5,6', '7,8,9'];

  final Dio _dio;
  KboDirectPlayerRepository()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
            'Referer': 'https://www.koreabaseball.com/',
            'Origin': 'https://www.koreabaseball.com',
          },
        ),
      ) {
    _dio.interceptors.add(CookieManager(CookieJar()));
  }

  @override
  Future<List<PlayerProfile>> getTeamPlayers(
    String teamId, {
    required int season,
  }) async {
    if (season < DateTime.now().year) {
      return _fetchHistoricalTeamPlayers(teamId, season);
    }

    final entryKeys = await _parseRegisterAllEntries(teamId);
    final grouped = await Future.wait(
      _positionGroups.map((group) => _fetchPlayerSearchRows(teamId, group)),
    );
    final players = grouped.expand((items) => items).toList();

    return [
      for (final player in players)
        _buildPlayerSummary(
          player: player,
          season: season,
          seasonStats: const {},
          rosterGroup: entryKeys.contains((player.name, player.number))
              ? PlayerRosterGroup.entry
              : PlayerRosterGroup.reserve,
          status: entryKeys.contains((player.name, player.number))
              ? PlayerAvailabilityStatus.available
              : PlayerAvailabilityStatus.inactive,
          statusNote: entryKeys.contains((player.name, player.number))
              ? null
              : '엔트리 제외',
        ),
    ];
  }

  @override
  Future<PlayerProfile> getPlayerDetail(
    String playerId, {
    required int season,
  }) async {
    final playerType = await _guessPlayerType(playerId);
    final detailUrl = _detailUrl(playerId, playerType);
    final totalUrl = _totalUrl(playerId, playerType);
    final responses = await Future.wait([
      _getText(detailUrl),
      _getText(totalUrl),
    ]);

    final profile = _parseProfile(responses[0], playerId, playerType, season);
    final seasonStats = _parseSeasonStats(responses[1], season);
    final currentSeason = _extractCurrentSeason(responses[0]);
    final recentGames = _parseRecentGames(
      responses[0],
      includeRecent: season == currentSeason,
      playerType: playerType,
    );

    return PlayerProfile(
      id: profile.id,
      teamId: profile.teamId,
      playerType: profile.playerType,
      imageUrl: profile.imageUrl,
      name: profile.name,
      number: profile.number,
      position: profile.position,
      roleLabel: profile.roleLabel,
      handedness: profile.handedness,
      heightWeight: profile.heightWeight,
      birthDate: profile.birthDate,
      career: profile.career,
      status: PlayerAvailabilityStatus.available,
      rosterGroup: PlayerRosterGroup.entry,
      statusNote: null,
      headlineStat: _buildHeadline(playerType, seasonStats),
      secondaryStat: _buildSecondary(playerType, seasonStats),
      seasonStats: _buildSeasonStatList(playerType, seasonStats),
      highlights: _buildHighlights(playerType, seasonStats),
      recentGames: recentGames,
      avg: _buildSortMetrics(playerType, seasonStats)['avg'],
      ops: _buildSortMetrics(playerType, seasonStats)['ops'],
      era: _buildSortMetrics(playerType, seasonStats)['era'],
      whip: _buildSortMetrics(playerType, seasonStats)['whip'],
    );
  }

  @override
  Future<TeamStats> getTeamStats(String teamId, {required int season}) {
    return _fetchTeamStats(teamId, season);
  }

  @override
  Future<TeamRecordsBundle> getTeamRecords(
    String teamId, {
    required int season,
  }) async {
    final results = await Future.wait([
      getTeamPlayers(teamId, season: season),
      getTeamStats(teamId, season: season),
    ]);
    return TeamRecordsBundle(
      players: results[0] as List<PlayerProfile>,
      teamStats: results[1] as TeamStats,
    );
  }

  @override
  Future<RecordsOverview> getRecordsOverview({required int season}) async {
    final results = await Future.wait([
      _fetchLeaders(_hitterAvgUrl, season, 'AVG', 'hitter'),
      _fetchLeaders(_hitterHrUrl, season, 'HR', 'hitter'),
      _fetchLeaders(_hitterOpsUrl, season, 'OPS', 'hitter'),
      _fetchLeaderboard(_hitterOpsUrl, season, 'OPS', 'hitter'),
      _fetchLeaders(_pitcherEraUrl, season, 'ERA', 'pitcher'),
    ]);

    final avgLeaders = results[0];
    final hrLeaders = results[1];
    final opsLeaders = results[2];
    final opsPlusLeaders = computeOpsPlusLeaders(results[3]);
    final eraLeaders = results[4];

    return RecordsOverview(
      season: season,
      avgLeaders: avgLeaders,
      hrLeaders: hrLeaders,
      opsLeaders: opsLeaders,
      opsPlusLeaders: opsPlusLeaders.take(5).toList(),
      eraLeaders: eraLeaders,
      todayHitter: _buildFeaturedPlayer(
        season: season,
        label: '오늘의 타자',
        leaderGroups: {'avg': avgLeaders, 'hr': hrLeaders, 'ops': opsLeaders},
        targetType: 'hitter',
        periodLabel: '오늘',
      ),
      todayPitcher: _buildFeaturedPlayer(
        season: season,
        label: '오늘의 투수',
        leaderGroups: {'era': eraLeaders},
        targetType: 'pitcher',
        periodLabel: '오늘',
      ),
      monthHitter: _buildFeaturedPlayer(
        season: season,
        label: '이달의 타자',
        leaderGroups: {'avg': avgLeaders, 'hr': hrLeaders, 'ops': opsLeaders},
        targetType: 'hitter',
        periodLabel: '이달',
      ),
      monthPitcher: _buildFeaturedPlayer(
        season: season,
        label: '이달의 투수',
        leaderGroups: {'era': eraLeaders},
        targetType: 'pitcher',
        periodLabel: '이달',
      ),
    );
  }

  @override
  Future<List<RecordLeader>> getLeaderboard({
    required int season,
    required LeaderboardMetric metric,
  }) async {
    if (metric == LeaderboardMetric.opsPlus) {
      final opsLeaders = await _fetchLeaderboard(
        _hitterOpsUrl,
        season,
        'OPS',
        'hitter',
      );
      return computeOpsPlusLeaders(opsLeaders);
    }
    final metricInfo = _leaderboardMetrics[metric];
    if (metricInfo == null) {
      return const [];
    }
    return _fetchLeaderboard(
      metricInfo.$1,
      season,
      metricInfo.$2,
      metricInfo.$3,
    );
  }

  Future<String> _getText(String url) async {
    final response = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  Future<String> _postText(
    String url, {
    required Map<String, String> data,
  }) async {
    final response = await _dio.post<String>(
      url,
      data: data,
      options: Options(
        responseType: ResponseType.plain,
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 400,
      ),
    );
    final location = response.headers.value('location');
    if (response.statusCode != null &&
        response.statusCode! >= 300 &&
        location != null &&
        location.isNotEmpty) {
      return _getText(Uri.parse(url).resolve(location).toString());
    }
    return response.data ?? '';
  }

  Future<String> _postSeasonPage(String url, String initialHtml, int season) {
    return _postText(
      url,
      data: _buildWebFormsPayload(
        initialHtml,
        overrides: {_seasonField: '$season'},
        eventTarget: _seasonField,
      ),
    );
  }

  Future<String> _postTeamPage(String url, String seasonHtml, String teamId) {
    return _postText(
      url,
      data: _buildWebFormsPayload(
        seasonHtml,
        overrides: {_teamField: teamId},
        eventTarget: _teamField,
      ),
    );
  }

  Map<String, String> _buildWebFormsPayload(
    String html, {
    Map<String, String> overrides = const {},
    String eventTarget = '',
  }) {
    final fields = <String, String>{};

    for (final match in RegExp(
      r'<input\b[^>]*>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html)) {
      final tag = match.group(0) ?? '';
      final name = _extractAttribute(tag, 'name');
      if (name == null || name.isEmpty) {
        continue;
      }
      fields[name] = _decodeHtmlValue(_extractAttribute(tag, 'value') ?? '');
    }

    for (final match in RegExp(
      r'<select\b[^>]*name="([^"]+)"[^>]*>(.*?)</select>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html)) {
      final name = match.group(1);
      if (name == null || name.isEmpty) {
        continue;
      }
      fields[name] = _decodeHtmlValue(
        _selectedOptionValue(match.group(2) ?? ''),
      );
    }

    fields.addAll(overrides);
    fields['__EVENTTARGET'] = eventTarget;
    fields['__EVENTARGUMENT'] = '';
    return fields;
  }

  Future<Set<(String, int)>> _parseRegisterAllEntries(String teamId) async {
    final html = await _getText(_registerAllUrl);
    final teamName = _registerTeamNameMap[teamId] ?? teamId;
    final rowMatch = RegExp(
      '<tr>\\s*<th scope="row" class="fir">${RegExp.escape(teamName)}</th>(.*?)</tr>',
      dotAll: true,
    ).firstMatch(html);
    if (rowMatch == null) {
      return {};
    }

    final cells = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true)
        .allMatches(rowMatch.group(1)!)
        .map((match) => match.group(1) ?? '')
        .toList();
    final result = <(String, int)>{};
    for (final cell in cells.skip(2)) {
      for (final item in RegExp(
        r'<li>(.*?)</li>',
        dotAll: true,
      ).allMatches(cell)) {
        final raw = _stripTags(item.group(1) ?? '');
        final match = RegExp(r'(.+?)\((\d+)\)').firstMatch(raw);
        if (match != null) {
          result.add((match.group(1)!.trim(), int.parse(match.group(2)!)));
        }
      }
    }
    return result;
  }

  Future<List<PlayerProfile>> _fetchPlayerSearchRows(
    String teamId,
    String positionValue,
  ) async {
    final initialHtml = await _getText(_playerSearchUrl);
    final html = await _postText(
      _playerSearchUrl,
      data: {
        '__VIEWSTATE': _extractHidden(initialHtml, '__VIEWSTATE'),
        '__VIEWSTATEGENERATOR': _extractHidden(
          initialHtml,
          '__VIEWSTATEGENERATOR',
        ),
        '__EVENTVALIDATION': _extractHidden(initialHtml, '__EVENTVALIDATION'),
        'ctl00\$ctl00\$ctl00\$ctl00\$cphContainer\$cphContainer\$cphContent\$cphContent\$hfTeam':
            _teamSearchCodeMap[teamId] ?? teamId.toLowerCase(),
        'ctl00\$ctl00\$ctl00\$ctl00\$cphContainer\$cphContainer\$cphContent\$cphContent\$hfPosition':
            positionValue,
        '__EVENTTARGET':
            'ctl00\$ctl00\$ctl00\$ctl00\$cphContainer\$cphContainer\$cphContent\$cphContent\$lbtnSearch',
        '__EVENTARGUMENT': '',
      },
    );

    final rows = RegExp(
      r'<tr>\s*<th scope="row" title="player">.*?</tr>',
      dotAll: true,
    ).allMatches(html);
    final players = <PlayerProfile>[];
    for (final row in rows) {
      final cells = RegExp(
        r'<t[hd][^>]*>(.*?)</t[hd]>',
        dotAll: true,
      ).allMatches(row.group(0)!).map((match) => match.group(1) ?? '').toList();
      if (cells.length < 5) {
        continue;
      }
      final hrefMatch = RegExp(
        r'href="/Teams/PlayerInfo(Pitcher|Hitter)/Summary\.aspx\?pcode=(\d+)"',
      ).firstMatch(cells[0]);
      if (hrefMatch == null) {
        continue;
      }
      players.add(
        PlayerProfile(
          id: hrefMatch.group(2) ?? '',
          teamId: teamId,
          playerType: hrefMatch.group(1) == 'Pitcher'
              ? PlayerType.pitcher
              : PlayerType.hitter,
          name: _stripTags(cells[0]),
          number: _parseInt(_stripTags(cells[1])) ?? 0,
          position: _stripTags(cells[2]),
          roleLabel: _stripTags(cells[2]),
          handedness: '',
          birthDate: _stripTags(cells[3]),
          heightWeight: _stripTags(cells[4]).replaceAll(',', ' / '),
          status: PlayerAvailabilityStatus.available,
          rosterGroup: PlayerRosterGroup.entry,
          headlineStat: '',
          secondaryStat: '',
          seasonStats: const [],
          highlights: const [],
          recentGames: const [],
        ),
      );
    }
    return players;
  }

  Future<List<PlayerProfile>> _fetchHistoricalTeamPlayers(
    String teamId,
    int season,
  ) async {
    final hitterBasicRows = await _fetchTeamPlayerRecordRows(
      _hitterAvgUrl,
      season,
      teamId,
      PlayerType.hitter,
    );
    final hitterOpsRows = await _fetchTeamPlayerRecordRows(
      _hitterOpsUrl,
      season,
      teamId,
      PlayerType.hitter,
    );
    final pitcherRows = await _fetchTeamPlayerRecordRows(
      _pitcherEraUrl,
      season,
      teamId,
      PlayerType.pitcher,
    );

    final hitterOpsById = {for (final row in hitterOpsRows) row.id: row.stats};
    return [
      for (final row in hitterBasicRows)
        _buildPlayerFromRecordRow(
          row,
          season: season,
          stats: {...row.stats, ...?hitterOpsById[row.id]},
        ),
      for (final row in pitcherRows)
        _buildPlayerFromRecordRow(row, season: season, stats: row.stats),
    ];
  }

  Future<List<_TeamPlayerRecordRow>> _fetchTeamPlayerRecordRows(
    String url,
    int season,
    String teamId,
    PlayerType playerType,
  ) async {
    final initialHtml = await _getText(url);
    final seasonHtml = await _postSeasonPage(url, initialHtml, season);
    final html = await _postTeamPage(url, seasonHtml, teamId);
    return _parseTeamPlayerRecordRows(html, playerType);
  }

  List<_TeamPlayerRecordRow> _parseTeamPlayerRecordRows(
    String html,
    PlayerType playerType,
  ) {
    final headerMatch = RegExp(
      r'<thead>(.*?)</thead>',
      dotAll: true,
    ).firstMatch(html);
    final bodyMatch = RegExp(
      r'<tbody>(.*?)</tbody>',
      dotAll: true,
    ).firstMatch(html);
    if (headerMatch == null || bodyMatch == null) {
      return const [];
    }

    final headers = RegExp(r'<th[^>]*>(.*?)</th>', dotAll: true)
        .allMatches(headerMatch.group(1)!)
        .map((cell) => _stripTags(cell.group(1) ?? ''))
        .toList();
    final rows = <_TeamPlayerRecordRow>[];
    for (final row in RegExp(
      r'<tr>(.*?)</tr>',
      dotAll: true,
    ).allMatches(bodyMatch.group(1)!)) {
      final rawCells = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', dotAll: true)
          .allMatches(row.group(1) ?? '')
          .map((cell) => cell.group(1) ?? '')
          .toList();
      if (rawCells.length != headers.length || rawCells.length < 4) {
        continue;
      }

      final playerLink = _extractRecordPlayerLink(rawCells[1]);
      if (playerLink == null) {
        continue;
      }

      final cells = rawCells.map(_stripTags).toList();
      rows.add(
        _TeamPlayerRecordRow(
          id: playerLink.playerId,
          name: cells[1],
          teamId: _teamNameToId(cells[2]),
          playerType: playerType,
          isRetired: playerLink.isRetired,
          stats: {
            for (var i = 0; i < headers.length; i++)
              headers[i].replaceAll('팀명', 'TEAM').trim(): cells[i],
          },
        ),
      );
    }
    return rows;
  }

  Future<PlayerType> _guessPlayerType(String playerId) async {
    for (final type in [PlayerType.hitter, PlayerType.pitcher]) {
      final html = await _getText(_detailUrl(playerId, type));
      if (html.contains('선수명:') || html.contains('선수명')) {
        return type;
      }
    }
    return PlayerType.hitter;
  }

  String _detailUrl(String playerId, PlayerType playerType) {
    return playerType == PlayerType.pitcher
        ? _pitcherDetailUrl.replaceFirst('{playerId}', playerId)
        : _hitterDetailUrl.replaceFirst('{playerId}', playerId);
  }

  String _totalUrl(String playerId, PlayerType playerType) {
    return playerType == PlayerType.pitcher
        ? _pitcherTotalUrl.replaceFirst('{playerId}', playerId)
        : _hitterTotalUrl.replaceFirst('{playerId}', playerId);
  }

  PlayerProfile _parseProfile(
    String html,
    String playerId,
    PlayerType playerType,
    int season,
  ) {
    final positionField = _extractProfileField(html, 'lblPosition');
    var position = positionField;
    var handedness = '';
    final posMatch = RegExp(r'(.+?)\((.+)\)').firstMatch(positionField);
    if (posMatch != null) {
      position = posMatch.group(1)?.trim() ?? position;
      handedness = posMatch.group(2)?.trim() ?? '';
    }

    return PlayerProfile(
      id: playerId,
      teamId: '',
      playerType: playerType,
      imageUrl: kboPlayerImageUrl(season: season, playerId: playerId),
      name: _extractProfileField(html, 'lblName'),
      number: _parseInt(_extractProfileField(html, 'lblBackNo')) ?? 0,
      position: position,
      roleLabel: position,
      handedness: handedness,
      birthDate: _extractProfileField(html, 'lblBirthday'),
      heightWeight: _extractProfileField(
        html,
        'lblHeightWeight',
      ).replaceAll('/', ' / '),
      career: _extractProfileField(html, 'lblCareer'),
      status: PlayerAvailabilityStatus.available,
      rosterGroup: PlayerRosterGroup.entry,
      headlineStat: '',
      secondaryStat: '',
      seasonStats: const [],
      highlights: const [],
      recentGames: const [],
    );
  }

  String _extractProfileField(String html, String suffix) {
    final match = RegExp(
      'id="[^"]*$suffix"[^>]*>(.*?)</span>',
      dotAll: true,
    ).firstMatch(html);
    return _stripTags(match?.group(1) ?? '');
  }

  Map<String, String> _parseSeasonStats(String html, int season) {
    final match = RegExp(
      r'<table[^>]*class="tbl tt[^"]*"[^>]*>.*?<thead>(.*?)</thead>.*?<tbody>(.*?)</tbody>.*?</table>',
      dotAll: true,
    ).firstMatch(html);
    if (match == null) {
      return {};
    }
    final headers = RegExp(r'<th[^>]*>(.*?)</th>', dotAll: true)
        .allMatches(match.group(1)!)
        .map((cell) => _stripTags(cell.group(1) ?? ''))
        .toList();
    final rows = RegExp(
      r'<tr>(.*?)</tr>',
      dotAll: true,
    ).allMatches(match.group(2)!).map((row) => row.group(1) ?? '');
    for (final row in rows) {
      final values = RegExp(
        r'<td[^>]*>(.*?)</td>',
        dotAll: true,
      ).allMatches(row).map((cell) => _stripTags(cell.group(1) ?? '')).toList();
      if (values.isEmpty || values.first != '$season') {
        continue;
      }
      if (values.length == headers.length) {
        return {
          for (var i = 0; i < headers.length; i++)
            headers[i].replaceAll('팀명', 'TEAM').trim(): values[i],
        };
      }
    }
    return {};
  }

  int _extractCurrentSeason(String html) {
    final match = RegExp(r'(\d{4})\s*시즌').firstMatch(html);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  List<PlayerRecentGame> _parseRecentGames(
    String html, {
    required bool includeRecent,
    required PlayerType playerType,
  }) {
    if (!includeRecent) {
      return const [];
    }
    final match = RegExp(
      r'최근 10경기</h6>.*?<tbody>(.*?)</tbody>',
      dotAll: true,
    ).firstMatch(html);
    if (match == null) {
      return const [];
    }

    final rows = RegExp(
      r'<tr>(.*?)</tr>',
      dotAll: true,
    ).allMatches(match.group(1)!).take(5);
    final games = <PlayerRecentGame>[];
    for (final row in rows) {
      final cells = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true)
          .allMatches(row.group(1)!)
          .map((cell) => _stripTags(cell.group(1) ?? ''))
          .toList();
      if (cells.length < 3) {
        continue;
      }
      if (playerType == PlayerType.pitcher) {
        games.add(
          PlayerRecentGame(
            date: cells[0],
            opponent: cells[1],
            summary:
                '결과 ${_valueAt(cells, 2)} · IP ${_valueAt(cells, 5)} · SO ${_valueAt(cells, 10)} · ER ${_valueAt(cells, 12)}',
            score: _scorePitcherRecentGame(cells),
          ),
        );
      } else {
        games.add(
          PlayerRecentGame(
            date: cells[0],
            opponent: cells[1],
            summary:
                'AVG ${_valueAt(cells, 2)} · H ${_valueAt(cells, 6)} · HR ${_valueAt(cells, 9)} · RBI ${_valueAt(cells, 10)}',
            score: _scoreHitterRecentGame(cells),
          ),
        );
      }
    }
    return games;
  }

  double _scoreHitterRecentGame(List<String> cells) {
    final avg = _parseDouble(_valueAt(cells, 2)) ?? 0;
    final hits = _parseInt(_valueAt(cells, 6)) ?? 0;
    final hr = _parseInt(_valueAt(cells, 9)) ?? 0;
    final rbi = _parseInt(_valueAt(cells, 10)) ?? 0;
    return hits * 3 + hr * 6 + rbi * 2 + avg;
  }

  double _scorePitcherRecentGame(List<String> cells) {
    final result = _valueAt(cells, 2);
    final ip = _valueAt(cells, 5);
    final strikeouts = _parseInt(_valueAt(cells, 10)) ?? 0;
    final earnedRuns = _parseInt(_valueAt(cells, 12)) ?? 0;
    var score = _inningsToOuts(ip) * 0.6 + strikeouts * 1.5 - earnedRuns * 3;
    if (result.contains('승') || result.toUpperCase() == 'W') score += 3;
    if (result.contains('세') || result.toUpperCase() == 'S') score += 2;
    if (result.contains('홀') || result.toUpperCase() == 'H') score += 1;
    return score;
  }

  int _inningsToOuts(String value) {
    try {
      if (value.contains(' ')) {
        final parts = value.split(' ');
        return int.parse(parts[0]) * 3 +
            (parts[1].contains('2/3')
                ? 2
                : parts[1].contains('1/3')
                ? 1
                : 0);
      }
      if (value.contains('.')) {
        final parts = value.split('.');
        return int.parse(parts[0]) * 3 + int.parse(parts[1]);
      }
      return int.parse(value) * 3;
    } catch (_) {
      return 0;
    }
  }

  List<String> _buildSeasonStatList(
    PlayerType playerType,
    Map<String, String> stats,
  ) {
    final keys = playerType == PlayerType.pitcher
        ? ['ERA', 'G', 'W', 'L', 'SV', 'HLD', 'IP', 'SO', 'WHIP']
        : ['AVG', 'G', 'H', 'HR', 'RBI', 'SB', 'OBP', 'SLG', 'OPS'];
    return [
      for (final key in keys)
        if ((stats[key] ?? '').isNotEmpty && stats[key] != '-')
          '$key ${stats[key]}',
    ];
  }

  List<String> _buildHighlights(
    PlayerType playerType,
    Map<String, String> stats,
  ) {
    if (playerType == PlayerType.pitcher) {
      return [
        if (stats['ERA'] != null) 'ERA ${stats['ERA']}',
        if (stats['WHIP'] != null) 'WHIP ${stats['WHIP']}',
        if (stats['W'] != null && stats['L'] != null)
          '${stats['W']}승 ${stats['L']}패',
      ];
    }
    return [
      if (stats['AVG'] != null) '타율 ${stats['AVG']}',
      if (stats['OPS'] != null) 'OPS ${stats['OPS']}',
      if (stats['HR'] != null) '${stats['HR']}홈런',
    ];
  }

  String _buildHeadline(PlayerType playerType, Map<String, String> stats) {
    return playerType == PlayerType.pitcher
        ? 'ERA ${stats['ERA'] ?? '-'}'
        : '타율 ${stats['AVG'] ?? '-'}';
  }

  String _buildSecondary(PlayerType playerType, Map<String, String> stats) {
    if (playerType == PlayerType.pitcher) {
      if (stats['WHIP'] != null) {
        return 'WHIP ${stats['WHIP']}';
      }
      return '${stats['W'] ?? '0'}승 ${stats['L'] ?? '0'}패';
    }
    if (stats['OPS'] != null) {
      return 'OPS ${stats['OPS']}';
    }
    return '${stats['HR'] ?? '0'}홈런';
  }

  Map<String, double?> _buildSortMetrics(
    PlayerType playerType,
    Map<String, String> stats,
  ) {
    if (playerType == PlayerType.pitcher) {
      return {
        'era': _parseDouble(stats['ERA']),
        'whip': _parseDouble(stats['WHIP']),
      };
    }
    return {
      'avg': _parseDouble(stats['AVG']),
      'ops': _parseDouble(stats['OPS']),
    };
  }

  Future<List<RecordLeader>> _fetchLeaders(
    String url,
    int season,
    String metricKey,
    String playerType,
  ) async {
    final initialHtml = await _getText(url);
    final html = await _postSeasonPage(url, initialHtml, season);

    final rows = RegExp(r'<tr>(.*?)</tr>', dotAll: true).allMatches(html);
    final valueIndex = _resolveMetricIndex(
      rows.map((row) => row.group(1) ?? '').toList(),
      metricKey,
    );
    final leaders = <RecordLeader>[];
    for (final row in rows) {
      final cells = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', dotAll: true)
          .allMatches(row.group(1) ?? '')
          .map((cell) => cell.group(1) ?? '')
          .toList();
      if (cells.length <= valueIndex) {
        continue;
      }
      final playerLink = _extractRecordPlayerLink(cells[1]);
      if (playerLink == null) {
        continue;
      }
      leaders.add(
        RecordLeader(
          rank: int.tryParse(_stripTags(cells[0])) ?? 0,
          playerId: playerLink.playerId,
          playerType: playerType,
          name: _stripTags(cells[1]),
          teamId: _teamNameToId(_stripTags(cells[2])),
          value: _stripTags(cells[valueIndex]),
          isRetired: playerLink.isRetired,
        ),
      );
      if (leaders.length >= 5) {
        break;
      }
    }
    return leaders;
  }

  Future<List<RecordLeader>> _fetchLeaderboard(
    String url,
    int season,
    String metricKey,
    String playerType,
  ) async {
    final initialHtml = await _getText(url);
    final html = await _postSeasonPage(url, initialHtml, season);

    final rows = RegExp(r'<tr>(.*?)</tr>', dotAll: true).allMatches(html);
    final valueIndex = _resolveMetricIndex(
      rows.map((row) => row.group(1) ?? '').toList(),
      metricKey,
    );
    final leaders = <RecordLeader>[];
    for (final row in rows) {
      final cells = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', dotAll: true)
          .allMatches(row.group(1) ?? '')
          .map((cell) => cell.group(1) ?? '')
          .toList();
      if (cells.length <= valueIndex) {
        continue;
      }
      final playerLink = _extractRecordPlayerLink(cells[1]);
      if (playerLink == null) {
        continue;
      }
      leaders.add(
        RecordLeader(
          rank: int.tryParse(_stripTags(cells[0])) ?? 0,
          playerId: playerLink.playerId,
          playerType: playerType,
          name: _stripTags(cells[1]),
          teamId: _teamNameToId(_stripTags(cells[2])),
          value: _stripTags(cells[valueIndex]),
          isRetired: playerLink.isRetired,
        ),
      );
    }
    return leaders;
  }

  int _resolveMetricIndex(List<String> rows, String metricKey) {
    for (final row in rows) {
      final labels = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', dotAll: true)
          .allMatches(row)
          .map((cell) => _stripTags(cell.group(1) ?? '').trim().toUpperCase())
          .toList();
      final index = labels.indexOf(metricKey.toUpperCase());
      if (index >= 0) {
        return index;
      }
    }
    return 3;
  }

  FeaturedPlayerCard _buildFeaturedPlayer({
    required int season,
    required String label,
    required Map<String, List<RecordLeader>> leaderGroups,
    required String targetType,
    required String periodLabel,
  }) {
    final weights = {'avg': 3, 'hr': 2, 'ops': 3, 'era': 3};
    final scores = <(String, String), int>{};
    final lookup = <(String, String), RecordLeader>{};

    leaderGroups.forEach((metric, leaders) {
      final weight = weights[metric] ?? 1;
      for (final leader in leaders) {
        final key = (leader.playerId, leader.playerType);
        scores[key] = (scores[key] ?? 0) + (6 - leader.rank) * weight;
        lookup[key] = leader;
      }
    });

    if (scores.isEmpty) {
      return FeaturedPlayerCard(label: label);
    }

    final bestKey = scores.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
    final leader = lookup[bestKey]!;
    return FeaturedPlayerCard(
      label: label,
      playerId: leader.playerId,
      playerType: leader.playerType,
      name: leader.name,
      teamId: leader.teamId,
      headline: _headlineForLeader(leader),
      summary: _featureReason(
        playerId: leader.playerId,
        leaderGroups: leaderGroups,
        targetType: targetType,
        periodLabel: periodLabel,
      ),
      imageUrl: kboPlayerImageUrl(season: season, playerId: leader.playerId),
    );
  }

  String _featureReason({
    required String playerId,
    required Map<String, List<RecordLeader>> leaderGroups,
    required String targetType,
    required String periodLabel,
  }) {
    final reasons = <String>[];
    leaderGroups.forEach((metric, leaders) {
      for (final leader in leaders) {
        if (leader.playerId == playerId && leader.playerType == targetType) {
          reasons.add('${metric.toUpperCase()} ${leader.rank}위');
        }
      }
    });
    if (reasons.isEmpty) {
      return '';
    }
    return reasons.take(2).join(' + ');
  }

  String _headlineForLeader(RecordLeader leader) {
    switch (leader.playerType) {
      case 'pitcher':
        return 'ERA ${leader.value}';
      default:
        return leader.value.startsWith('.')
            ? '타율 ${leader.value}'
            : '홈런 ${leader.value}';
    }
  }

  PlayerProfile _buildPlayerSummary({
    required PlayerProfile player,
    required int season,
    required Map<String, String> seasonStats,
    required PlayerRosterGroup rosterGroup,
    required PlayerAvailabilityStatus status,
    required String? statusNote,
  }) {
    final sortMetrics = _buildSortMetrics(player.playerType, seasonStats);
    return PlayerProfile(
      id: player.id,
      teamId: player.teamId,
      playerType: player.playerType,
      imageUrl: kboPlayerImageUrl(season: season, playerId: player.id),
      name: player.name,
      number: player.number,
      position: player.position,
      roleLabel: player.roleLabel.isNotEmpty
          ? player.roleLabel
          : player.position,
      handedness: player.handedness,
      heightWeight: player.heightWeight,
      birthDate: player.birthDate,
      career: player.career,
      status: status,
      rosterGroup: rosterGroup,
      statusNote: statusNote,
      headlineStat: _buildHeadline(player.playerType, seasonStats),
      secondaryStat: _buildSecondary(player.playerType, seasonStats),
      seasonStats: _buildSeasonStatList(player.playerType, seasonStats),
      highlights: _buildHighlights(player.playerType, seasonStats),
      recentGames: const [],
      avg: sortMetrics['avg'],
      ops: sortMetrics['ops'],
      era: sortMetrics['era'],
      whip: sortMetrics['whip'],
    );
  }

  PlayerProfile _buildPlayerFromRecordRow(
    _TeamPlayerRecordRow row, {
    required int season,
    required Map<String, String> stats,
  }) {
    final sortMetrics = _buildSortMetrics(row.playerType, stats);
    return PlayerProfile(
      id: row.id,
      teamId: row.teamId,
      playerType: row.playerType,
      imageUrl: kboPlayerImageUrl(season: season, playerId: row.id),
      name: row.name,
      number: 0,
      position: row.playerType == PlayerType.pitcher ? '투수' : '야수',
      roleLabel: row.playerType == PlayerType.pitcher ? '투수' : '야수',
      handedness: '',
      heightWeight: '',
      birthDate: '',
      career: '',
      status: PlayerAvailabilityStatus.available,
      rosterGroup: PlayerRosterGroup.entry,
      statusNote: null,
      headlineStat: _buildHeadline(row.playerType, stats),
      secondaryStat: _buildSecondary(row.playerType, stats),
      seasonStats: _buildSeasonStatList(row.playerType, stats),
      highlights: _buildHighlights(row.playerType, stats),
      recentGames: const [],
      avg: sortMetrics['avg'],
      ops: sortMetrics['ops'],
      era: sortMetrics['era'],
      whip: sortMetrics['whip'],
      isRetired: row.isRetired,
    );
  }

  _RecordPlayerLink? _extractRecordPlayerLink(String html) {
    final match = _recordPlayerLinkPattern.firstMatch(html);
    if (match == null) {
      return null;
    }
    return _RecordPlayerLink(
      playerId: match.group(1) ?? '',
      isRetired: match.group(0)?.contains('/Record/Retire/') ?? false,
    );
  }

  String _extractHidden(String html, String name) {
    final match = RegExp(
      'name="${RegExp.escape(name)}"[^>]*value="([^"]*)"',
    ).firstMatch(html);
    return match?.group(1) ?? '';
  }

  String _stripTags(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

  int? _parseInt(String? value) {
    if (value == null || value.isEmpty || value == '-') {
      return null;
    }
    return int.tryParse(value.replaceAll(',', ''));
  }

  double? _parseDouble(String? value) {
    if (value == null || value.isEmpty || value == '-') {
      return null;
    }
    return double.tryParse(value.replaceAll(',', ''));
  }

  String _valueAt(List<String> cells, int index) {
    if (index < 0 || index >= cells.length) {
      return '-';
    }
    return cells[index];
  }

  String _teamNameToId(String teamName) {
    return {
          'LG': 'LG',
          'KT': 'KT',
          'SSG': 'SK',
          '삼성': 'SS',
          'NC': 'NC',
          '한화': 'HH',
          '롯데': 'LT',
          'KIA': 'HT',
          '두산': 'OB',
          '키움': 'WO',
        }[teamName] ??
        teamName;
  }

  Future<TeamStats> _fetchTeamStats(String teamId, int season) async {
    final teamName = _registerTeamNameMap[teamId] ?? teamId;
    final results = await Future.wait([
      _fetchTeamStatTable(_teamHitterUrl, season, teamName),
      _fetchTeamStatTable(_teamPitcherUrl, season, teamName),
    ]);
    return TeamStats(
      teamId: teamId,
      season: season,
      hitting: results[0],
      pitching: results[1],
    );
  }

  Future<Map<String, String>> _fetchTeamStatTable(
    String url,
    int season,
    String teamName,
  ) async {
    final initialHtml = await _getText(url);
    final html = await _postSeasonPage(url, initialHtml, season);

    final headerMatch = RegExp(
      r'<thead>(.*?)</thead>',
      dotAll: true,
    ).firstMatch(html);
    final bodyMatch = RegExp(
      r'<tbody>(.*?)</tbody>',
      dotAll: true,
    ).firstMatch(html);
    if (headerMatch == null || bodyMatch == null) {
      return {};
    }

    final headers = RegExp(r'<th[^>]*>(.*?)</th>', dotAll: true)
        .allMatches(headerMatch.group(1)!)
        .map((item) => _stripTags(item.group(1) ?? ''))
        .toList();
    final rows = RegExp(
      r'<tr>(.*?)</tr>',
      dotAll: true,
    ).allMatches(bodyMatch.group(1)!).map((row) => row.group(1) ?? '');
    for (final row in rows) {
      final cells = RegExp(
        r'<t[dh][^>]*>(.*?)</t[dh]>',
        dotAll: true,
      ).allMatches(row).map((item) => _stripTags(item.group(1) ?? '')).toList();
      if (cells.length != headers.length) {
        continue;
      }
      if (cells.length > 1 && cells[1] == teamName) {
        return {for (var i = 0; i < headers.length; i++) headers[i]: cells[i]};
      }
    }
    return {};
  }

  String? _extractAttribute(String tag, String attribute) {
    final match = RegExp(
      '$attribute="([^"]*)"',
      caseSensitive: false,
    ).firstMatch(tag);
    return match?.group(1);
  }

  String _selectedOptionValue(String selectBody) {
    String? fallback;
    for (final option in RegExp(
      r'<option\b[^>]*>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(selectBody)) {
      final tag = option.group(0) ?? '';
      final value = _extractAttribute(tag, 'value') ?? '';
      fallback ??= value;
      if (tag.toLowerCase().contains('selected')) {
        return value;
      }
    }
    return fallback ?? '';
  }

  String _decodeHtmlValue(String value) {
    return value
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }
}

class _TeamPlayerRecordRow {
  final String id;
  final String name;
  final String teamId;
  final PlayerType playerType;
  final bool isRetired;
  final Map<String, String> stats;

  const _TeamPlayerRecordRow({
    required this.id,
    required this.name,
    required this.teamId,
    required this.playerType,
    required this.isRetired,
    required this.stats,
  });
}

class _RecordPlayerLink {
  final String playerId;
  final bool isRetired;

  const _RecordPlayerLink({required this.playerId, required this.isRetired});
}
