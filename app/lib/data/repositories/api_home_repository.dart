import '../api/api_client.dart';
import '../models/home_aggregate.dart';
import '../models/schedule.dart';
import '../models/ticketing.dart';

class ApiHomeRepository {
  final ApiClient _client;
  static const _cacheAge = Duration(minutes: 5);

  ApiHomeRepository(this._client);

  Future<HomeAggregate> getHomeAggregate({
    required String date,
    String? myTeam,
  }) async {
    final data = await _client.getCached(
      '/home',
      queryParameters: {
        'date': date,
        if (myTeam != null && myTeam.isNotEmpty) 'myTeam': myTeam,
      },
      cacheKey: 'homeAggregate:$date:${myTeam ?? ''}',
      preferCache: true,
      maxAge: _cacheAge,
    );

    final quickItems = (data['quickItems'] as List<dynamic>? ?? [])
        .map((item) => _parseQuickItem(item as Map<String, dynamic>))
        .toList();
    final briefMap = data['myTeamBrief'] as Map<String, dynamic>?;

    return HomeAggregate(
      date: data['date'] as String? ?? date,
      myTeam: data['myTeam'] as String?,
      myTeamBrief: briefMap == null ? null : _parseMyTeamBrief(briefMap),
      quickItems: quickItems,
    );
  }

  HomeQuickItem _parseQuickItem(Map<String, dynamic> json) {
    return HomeQuickItem(
      eyebrow: json['eyebrow'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      route: json['route'] as String? ?? '/home',
    );
  }

  HomeMyTeamBrief _parseMyTeamBrief(Map<String, dynamic> json) {
    final standingMap = json['standing'] as Map<String, dynamic>?;
    final nextGameMap = json['nextGame'] as Map<String, dynamic>?;
    final recentSummaries = (json['recentSummaries'] as List<dynamic>? ?? [])
        .map((item) => _parseRecentSummary(item as Map<String, dynamic>))
        .toList();

    return HomeMyTeamBrief(
      teamId: json['teamId'] as String? ?? '',
      teamLabel: json['teamLabel'] as String? ?? '',
      standing: standingMap == null ? null : _parseStanding(standingMap),
      todayGameId: json['todayGameId'] as String?,
      nextGame: nextGameMap == null ? null : _parseScheduleGame(nextGameMap),
      recentWins: json['recentWins'] as int? ?? 0,
      recentLosses: json['recentLosses'] as int? ?? 0,
      recentDraws: json['recentDraws'] as int? ?? 0,
      recentGamesCount: json['recentGamesCount'] as int? ?? 0,
      recentSummaries: recentSummaries,
    );
  }

  HomeRecentGameSummary _parseRecentSummary(Map<String, dynamic> json) {
    return HomeRecentGameSummary(
      result: json['result'] as String? ?? '',
      opponentName: json['opponentName'] as String? ?? '',
      score: json['score'] as String? ?? '',
    );
  }

  TeamStanding _parseStanding(Map<String, dynamic> json) {
    return TeamStanding(
      rank: json['rank'] as int? ?? 0,
      teamId: json['teamId'] as String? ?? '',
      teamName: json['teamName'] as String? ?? '',
      wins: json['wins'] as int? ?? 0,
      losses: json['losses'] as int? ?? 0,
      draws: json['draws'] as int? ?? 0,
      pct: json['pct'] as String? ?? '.000',
      gb: json['gb'] as String? ?? '-',
    );
  }

  ScheduleGame _parseScheduleGame(Map<String, dynamic> json) {
    return ScheduleGame(
      gameId: json['gameId'] as String? ?? '',
      time: json['time'] as String? ?? '',
      awayId: json['awayId'] as String? ?? '',
      awayName: json['awayName'] as String? ?? '',
      awayScore: json['awayScore'] as int?,
      homeId: json['homeId'] as String? ?? '',
      homeName: json['homeName'] as String? ?? '',
      homeScore: json['homeScore'] as int?,
      stadium: json['stadium'] as String? ?? '',
      status: json['status'] as String? ?? 'SCHEDULED',
      ticketInfo: _parseTicketInfo(json['ticketInfo'] as Map<String, dynamic>?),
    );
  }

  TicketInfo? _parseTicketInfo(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return TicketInfo(
      vendorKey: json['vendorKey'] as String? ?? '',
      vendorName: json['vendorName'] as String? ?? '',
      vendorUrl: json['vendorUrl'] as String?,
      openAt: json['openAt'] == null
          ? null
          : DateTime.tryParse(json['openAt'] as String),
      source: (json['source'] as String? ?? '').toLowerCase() == 'official'
          ? TicketSource.official
          : TicketSource.inferred,
      note: json['note'] as String?,
    );
  }
}
