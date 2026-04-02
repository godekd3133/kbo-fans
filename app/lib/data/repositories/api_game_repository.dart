import '../api/api_client.dart';
import '../bootstrap/bootstrap_repository.dart';
import '../models/game.dart';
import '../models/highlight_info.dart';
import '../models/highlight_video.dart';
import '../models/relay.dart';
import '../models/boxscore.dart';
import '../models/schedule.dart';
import '../models/ticketing.dart';
import 'game_repository.dart';

/// DEV / RELEASE 환경에서 실제 백엔드 API를 호출하는 구현체
class ApiGameRepository implements GameRepository {
  final ApiClient _client;
  final BootstrapRepository _bootstrapRepository = BootstrapRepository();
  static const _liveishCacheAge = Duration(seconds: 30);
  static const _stableCacheAge = Duration(minutes: 5);

  ApiGameRepository(this._client);

  @override
  Future<List<Game>> getScoreboard(String date) async {
    final isHistoricalDate = _isHistoricalDate(date);
    final data = await _client.getCached(
      '/scoreboard/home',
      queryParameters: {'date': date},
      cacheKey: 'scoreboard_home:$date',
      preferCache: isHistoricalDate,
      maxAge: isHistoricalDate ? _stableCacheAge : _liveishCacheAge,
    );
    final games = data['games'] as List<dynamic>? ?? [];
    return games.map((g) => _parseGame(g as Map<String, dynamic>)).toList();
  }

  @override
  Future<Game?> getGame(String gameId) async {
    final data = await _client.getCached(
      '/game/$gameId',
      cacheKey: 'game:$gameId',
      preferCache: false,
      maxAge: _liveishCacheAge,
    );
    final game = data['game'] as Map<String, dynamic>?;
    if (game == null) {
      return null;
    }
    return _parseGame(game);
  }

  @override
  Future<HighlightInfo?> getHighlightInfo(String gameId) async {
    final data = await _client.getCached(
      '/game/$gameId/highlights',
      cacheKey: 'highlights:$gameId',
      preferCache: true,
      maxAge: _stableCacheAge,
    );
    final highlightInfo = data['highlightInfo'] as Map<String, dynamic>?;
    return _parseHighlightInfo(highlightInfo);
  }

  @override
  Future<RelayData> getRelayData(String gameId, {int? afterSeqNo}) async {
    final params = <String, dynamic>{};
    if (afterSeqNo != null) params['after'] = afterSeqNo;

    final data = await _client.get(
      '/game/$gameId/relay',
      queryParameters: params,
    );
    final items = data['relayItems'] as List<dynamic>? ?? [];
    final atBat = data['currentAtBat'] as Map<String, dynamic>?;

    return RelayData(
      currentAtBat: atBat == null ? null : _parseCurrentAtBat(atBat),
      relayItems: items
          .map((r) => _parseRelayItem(r as Map<String, dynamic>))
          .toList(),
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
    final data = await _client.getCached(
      '/game/$gameId/boxscore',
      cacheKey: 'boxscore:$gameId',
      preferCache: true,
      maxAge: _liveishCacheAge,
    );
    return GameBoxscoreData(
      gameId: gameId,
      away: _parseTeamBoxscore(
        data['away'] as Map<String, dynamic>? ?? const {},
      ),
      home: _parseTeamBoxscore(
        data['home'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

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
    final data = await _client.getCached(
      '/game/$gameId/lineup',
      cacheKey: 'lineup:$gameId',
      preferCache: true,
      maxAge: _liveishCacheAge,
    );
    return GameLineupData(
      gameId: gameId,
      away: _parseTeamLineup(data['away'] as Map<String, dynamic>? ?? const {}),
      home: _parseTeamLineup(data['home'] as Map<String, dynamic>? ?? const {}),
    );
  }

  @override
  Future<List<LineupEntry>> getLineup(
    String gameId, {
    required bool isAway,
  }) async {
    final data = await getLineupData(gameId);
    return (isAway ? data.away : data.home).lineup;
  }

  @override
  Future<List<ScheduleDay>> getSchedule(String yearMonth) async {
    final data = await _client.getCached(
      '/schedule',
      queryParameters: {'month': yearMonth},
      cacheKey: 'schedule:$yearMonth',
      preferCache: true,
      maxAge: _stableCacheAge,
    );
    final days = data['days'] as List<dynamic>? ?? [];
    return days.map((d) {
      final dayMap = d as Map<String, dynamic>;
      final games = (dayMap['games'] as List<dynamic>? ?? []).map((g) {
        final gm = g as Map<String, dynamic>;
        return ScheduleGame(
          gameId: gm['gameId'] as String? ?? '',
          time: gm['time'] as String? ?? '',
          awayId: gm['awayId'] as String? ?? '',
          awayName: gm['awayName'] as String? ?? '',
          awayScore: gm['awayScore'] as int?,
          homeId: gm['homeId'] as String? ?? '',
          homeName: gm['homeName'] as String? ?? '',
          homeScore: gm['homeScore'] as int?,
          stadium: gm['stadium'] as String? ?? '',
          status: gm['status'] as String? ?? 'SCHEDULED',
          ticketInfo: _parseTicketInfo(
            gm['ticketInfo'] as Map<String, dynamic>?,
          ),
        );
      }).toList();
      return ScheduleDay(
        date: dayMap['date'] as String? ?? '',
        label: dayMap['label'] as String?,
        games: games,
      );
    }).toList();
  }

  @override
  Future<List<TeamStanding>> getStandings(int season) async {
    try {
      final data = await _client.getCached(
        '/standings',
        queryParameters: {'season': season},
        cacheKey: 'standings:$season',
        preferCache: true,
        maxAge: _stableCacheAge,
      );
      return _parseStandings(data);
    } catch (_) {
      final snapshot = await _bootstrapRepository.loadStandings(season);
      if (snapshot == null) rethrow;
      return _parseStandings(snapshot);
    }
  }

  List<TeamStanding> _parseStandings(Map<String, dynamic> data) {
    final standings = data['standings'] as List<dynamic>? ?? [];
    return standings.map((s) {
      final sm = s as Map<String, dynamic>;
      return TeamStanding(
        rank: sm['rank'] as int? ?? 0,
        teamId: sm['teamId'] as String? ?? '',
        teamName: sm['teamName'] as String? ?? '',
        wins: sm['wins'] as int? ?? 0,
        losses: sm['losses'] as int? ?? 0,
        draws: sm['draws'] as int? ?? 0,
        pct: sm['pct'] as String? ?? '.000',
        gb: sm['gb'] as String? ?? '-',
      );
    }).toList();
  }

  // ── JSON → 모델 변환 ──

  Game _parseGame(Map<String, dynamic> json) {
    return Game(
      gameId: json['gameId'] as String? ?? '',
      status: _parseStatus(json['status'] as String? ?? ''),
      inning: json['inning'] as String? ?? '',
      away: _parseTeamScore(json['away'] as Map<String, dynamic>? ?? {}),
      home: _parseTeamScore(json['home'] as Map<String, dynamic>? ?? {}),
      stadium: json['stadium'] as String? ?? '',
      startTime: json['startTime'] as String? ?? '',
      crowd: json['crowd'] as int?,
      ticketInfo: _parseTicketInfo(json['ticketInfo'] as Map<String, dynamic>?),
      highlightInfo: _parseHighlightInfo(
        json['highlightInfo'] as Map<String, dynamic>?,
      ),
    );
  }

  GameStatus _parseStatus(String status) {
    switch (status.toUpperCase()) {
      case 'LIVE':
        return GameStatus.live;
      case 'FINAL':
        return GameStatus.final_;
      case 'CANCELLED':
        return GameStatus.cancelled;
      case 'SUSPENDED':
        return GameStatus.suspended;
      default:
        return GameStatus.scheduled;
    }
  }

  TeamScore _parseTeamScore(Map<String, dynamic> json) {
    final scores =
        (json['scores'] as List<dynamic>?)?.map((s) => s as int?).toList() ??
        List.filled(9, null);

    return TeamScore(
      teamId: json['teamId'] as String? ?? '',
      teamName: json['teamName'] as String? ?? '',
      shortName: json['shortName'] as String? ?? '',
      score: json['score'] as int? ?? 0,
      innings: scores,
      hits: json['hits'] as int? ?? 0,
      errors: json['errors'] as int? ?? 0,
      walks: json['balls'] as int? ?? 0,
    );
  }

  RelayItem _parseRelayItem(Map<String, dynamic> json) {
    return RelayItem(
      seqNo: json['seqNo'] as int? ?? 0,
      inning: json['inning'] as int? ?? 0,
      half: json['half'] as String? ?? 'top',
      event: json['event'] as String? ?? '',
      isScoring: json['isScoring'] as bool? ?? false,
      text: json['text'] as String? ?? '',
      pitchSequence: json['pitchSequence'] as String?,
    );
  }

  CurrentAtBat _parseCurrentAtBat(Map<String, dynamic> json) {
    final batter = json['batter'] as Map<String, dynamic>? ?? {};
    final pitcher = json['pitcher'] as Map<String, dynamic>? ?? {};
    final bc = json['ballCount'] as Map<String, dynamic>? ?? {};

    return CurrentAtBat(
      batterName: batter['name'] as String? ?? '',
      batterNumber: batter['number'] as int? ?? 0,
      batterHand: batter['hand'] as String? ?? '',
      batterRecent: batter['recent'] as String? ?? '',
      pitcherName: pitcher['name'] as String? ?? '',
      pitcherNumber: pitcher['number'] as int? ?? 0,
      pitcherHand: pitcher['hand'] as String? ?? '',
      pitchCount: pitcher['pitchCount'] as int? ?? 0,
      inningText: json['inningText'] as String? ?? '',
      baseState: json['baseState'] as String? ?? '',
      balls: bc['balls'] as int? ?? 0,
      strikes: bc['strikes'] as int? ?? 0,
      outs: bc['outs'] as int? ?? 0,
    );
  }

  BatterRecord _parseBatter(Map<String, dynamic> json) {
    return BatterRecord(
      order: json['order'] as int? ?? 0,
      position: json['position'] as String? ?? '',
      name: json['name'] as String? ?? '',
      atBats: json['atBats'] as int? ?? 0,
      runs: json['runs'] as int? ?? 0,
      hits: json['hits'] as int? ?? 0,
      rbi: json['rbi'] as int? ?? 0,
    );
  }

  PitcherRecord _parsePitcher(Map<String, dynamic> json) {
    return PitcherRecord(
      name: json['name'] as String? ?? '',
      innings: json['innings'] as String? ?? '0.0',
      hits: json['hits'] as int? ?? 0,
      strikeouts: json['strikeouts'] as int? ?? 0,
      walks: json['walks'] as int? ?? 0,
      earnedRuns: json['earnedRuns'] as int? ?? 0,
      decision: json['decision'] as String?,
    );
  }

  TeamBoxscoreData _parseTeamBoxscore(Map<String, dynamic> json) {
    final batters = (json['batters'] as List<dynamic>? ?? [])
        .map((item) => _parseBatter(item as Map<String, dynamic>))
        .toList();
    final pitchers = (json['pitchers'] as List<dynamic>? ?? [])
        .map((item) => _parsePitcher(item as Map<String, dynamic>))
        .toList();
    return TeamBoxscoreData(
      teamId: json['teamId'] as String? ?? '',
      batters: batters,
      pitchers: pitchers,
    );
  }

  TeamLineupData _parseTeamLineup(Map<String, dynamic> json) {
    final lineup = (json['lineup'] as List<dynamic>? ?? [])
        .map((item) => _parseLineup(item as Map<String, dynamic>))
        .toList();
    final starter = json['starter'] as Map<String, dynamic>? ?? const {};
    return TeamLineupData(
      teamId: json['teamId'] as String? ?? '',
      lineup: lineup,
      starterName: starter['name'] as String?,
    );
  }

  LineupEntry _parseLineup(Map<String, dynamic> json) {
    return LineupEntry(
      order: json['order'] as int? ?? 0,
      position: json['position'] as String? ?? '',
      positionKo: json['positionKo'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }

  TicketInfo? _parseTicketInfo(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final openAtRaw = json['openAt'] as String?;
    return TicketInfo(
      vendorKey: json['vendorKey'] as String? ?? '',
      vendorName: json['vendorName'] as String? ?? '',
      vendorUrl: json['vendorUrl'] as String?,
      openAt: openAtRaw != null ? DateTime.tryParse(openAtRaw) : null,
      source: (json['source'] as String? ?? '').toLowerCase() == 'official'
          ? TicketSource.official
          : TicketSource.inferred,
      note: json['note'] as String?,
    );
  }

  HighlightVideo? _parseHighlightVideo(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    return HighlightVideo(
      videoId: json['videoId'] as String? ?? '',
      title: json['title'] as String? ?? '유튜브 하이라이트',
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      videoUrl: json['videoUrl'] as String? ?? '',
      source: json['source'] as String? ?? 'youtube_search',
    );
  }

  HighlightInfo? _parseHighlightInfo(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final youtubeVideos = (json['youtubeVideos'] as List<dynamic>? ?? [])
        .map((item) => _parseHighlightVideo(item as Map<String, dynamic>?))
        .whereType<HighlightVideo>()
        .toList();
    final officialUrl = json['officialUrl'] as String?;

    if (youtubeVideos.isEmpty && (officialUrl == null || officialUrl.isEmpty)) {
      return null;
    }

    return HighlightInfo(
      officialUrl: officialUrl,
      youtubeVideos: youtubeVideos,
    );
  }

  bool _isHistoricalDate(String date) {
    try {
      final target = DateTime.parse(date);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      return target.isBefore(today);
    } catch (_) {
      return false;
    }
  }
}
