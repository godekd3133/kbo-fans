import 'game.dart';
import 'records_overview.dart';
import 'schedule.dart';

class HomeQuickItem {
  final String eyebrow;
  final String title;
  final String subtitle;
  final String route;
  final String? teamId;
  final String? imageUrl;
  final String? fallbackLabel;

  const HomeQuickItem({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.route,
    this.teamId,
    this.imageUrl,
    this.fallbackLabel,
  });
}

class HomeKboBriefItem {
  final String type;
  final String eyebrow;
  final String title;
  final String subtitle;
  final String route;
  final String? gameId;
  final List<String> teamIds;
  final String? imageUrl;
  final String? fallbackLabel;

  const HomeKboBriefItem({
    required this.type,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.route,
    this.gameId,
    this.teamIds = const [],
    this.imageUrl,
    this.fallbackLabel,
  });
}

class HomeKboBrief {
  final String title;
  final String subtitle;
  final List<HomeKboBriefItem> items;

  const HomeKboBrief({
    required this.title,
    required this.subtitle,
    required this.items,
  });
}

class HomeRecentGameSummary {
  final String gameId;
  final String result;
  final String opponentName;
  final String score;

  const HomeRecentGameSummary({
    required this.gameId,
    required this.result,
    required this.opponentName,
    required this.score,
  });
}

class HomeMyTeamBrief {
  final String teamId;
  final String teamLabel;
  final TeamStanding? standing;
  final String? todayGameId;
  final ScheduleGame? nextGame;
  final int recentWins;
  final int recentLosses;
  final int recentDraws;
  final int recentGamesCount;
  final List<HomeRecentGameSummary> recentSummaries;

  const HomeMyTeamBrief({
    required this.teamId,
    required this.teamLabel,
    required this.standing,
    required this.todayGameId,
    required this.nextGame,
    required this.recentWins,
    required this.recentLosses,
    required this.recentDraws,
    required this.recentGamesCount,
    required this.recentSummaries,
  });
}

class HomeAggregate {
  final String date;
  final String? myTeam;
  final HomeMyTeamBrief? myTeamBrief;
  final HomeKboBrief? kboBrief;
  final List<HomeQuickItem> quickItems;
  final List<TeamStanding> standingsPreview;

  const HomeAggregate({
    required this.date,
    required this.myTeam,
    required this.myTeamBrief,
    required this.kboBrief,
    required this.quickItems,
    this.standingsPreview = const [],
  });
}

HomeAggregate buildLocalHomeAggregate({
  required String date,
  required String? myTeam,
  required List<Game> games,
  required List<ScheduleDay> scheduleDays,
  required List<TeamStanding> standings,
  required RecordsOverview overview,
}) {
  final myTeamBrief = myTeam == null
      ? null
      : _buildLocalMyTeamBrief(
          myTeam: myTeam,
          games: games,
          scheduleDays: scheduleDays,
          standings: standings,
          today: date,
        );
  final quickItems = _buildLocalQuickItems(
    myTeamBrief: myTeamBrief,
    overview: overview,
    games: games,
    season: overview.season,
  );
  final kboBrief = _buildLocalKboBrief(
    date: date,
    myTeam: myTeam,
    games: games,
    standings: standings,
    overview: overview,
  );

  return HomeAggregate(
    date: date,
    myTeam: myTeam,
    myTeamBrief: myTeamBrief,
    kboBrief: kboBrief,
    quickItems: quickItems,
    standingsPreview: _buildLocalStandingsPreview(standings, myTeam),
  );
}

List<TeamStanding> _buildLocalStandingsPreview(
  List<TeamStanding> standings,
  String? myTeam,
) {
  if (standings.isEmpty) {
    return const [];
  }

  final sorted = [...standings]..sort((a, b) => a.rank.compareTo(b.rank));
  final preview = sorted.take(5).toList();
  final myTeamStanding = myTeam == null
      ? null
      : sorted.where((item) => item.teamId == myTeam).firstOrNull;
  if (myTeamStanding != null &&
      !preview.any((item) => item.teamId == myTeamStanding.teamId)) {
    if (preview.length >= 5) {
      preview[preview.length - 1] = myTeamStanding;
    } else {
      preview.add(myTeamStanding);
    }
    preview.sort((a, b) => a.rank.compareTo(b.rank));
  }
  return List.unmodifiable(preview);
}

HomeMyTeamBrief? _buildLocalMyTeamBrief({
  required String myTeam,
  required List<Game> games,
  required List<ScheduleDay> scheduleDays,
  required List<TeamStanding> standings,
  required String today,
}) {
  final todayGame = games
      .where((game) => game.away.teamId == myTeam || game.home.teamId == myTeam)
      .firstOrNull;
  final standing = standings.where((item) => item.teamId == myTeam).firstOrNull;

  final flatGames = [
    for (final day in scheduleDays)
      for (final game in day.games) (day.date, game),
  ]..sort((a, b) => a.$1.compareTo(b.$1));

  final recentGames =
      flatGames
          .where((entry) => entry.$1.compareTo(today) <= 0)
          .where(
            (entry) => entry.$2.awayId == myTeam || entry.$2.homeId == myTeam,
          )
          .where((entry) => entry.$2.status.toUpperCase() == 'FINAL')
          .where(
            (entry) => entry.$2.awayScore != null && entry.$2.homeScore != null,
          )
          .toList()
        ..sort((a, b) => b.$1.compareTo(a.$1));

  final recentSummaries = <HomeRecentGameSummary>[];
  var wins = 0;
  var losses = 0;
  var draws = 0;
  for (final entry in recentGames.take(5)) {
    final game = entry.$2;
    final isAway = game.awayId == myTeam;
    final myScore = isAway ? game.awayScore! : game.homeScore!;
    final opponentScore = isAway ? game.homeScore! : game.awayScore!;
    late final String result;
    if (myScore > opponentScore) {
      wins += 1;
      result = '승';
    } else if (myScore < opponentScore) {
      losses += 1;
      result = '패';
    } else {
      draws += 1;
      result = '무';
    }
    recentSummaries.add(
      HomeRecentGameSummary(
        gameId: game.gameId,
        result: result,
        opponentName: isAway ? game.homeName : game.awayName,
        score: '$myScore:$opponentScore',
      ),
    );
  }

  final nextGame = flatGames
      .where((entry) => entry.$1.compareTo(today) >= 0)
      .where((entry) => entry.$2.awayId == myTeam || entry.$2.homeId == myTeam)
      .where((entry) => entry.$2.gameId != todayGame?.gameId)
      .map((entry) => entry.$2)
      .firstOrNull;

  return HomeMyTeamBrief(
    teamId: myTeam,
    teamLabel: standing?.teamName ?? myTeam,
    standing: standing,
    todayGameId: todayGame?.gameId,
    nextGame: nextGame,
    recentWins: wins,
    recentLosses: losses,
    recentDraws: draws,
    recentGamesCount: recentSummaries.length,
    recentSummaries: recentSummaries,
  );
}

List<HomeQuickItem> _buildLocalQuickItems({
  required HomeMyTeamBrief? myTeamBrief,
  required RecordsOverview overview,
  required List<Game> games,
  required int season,
}) {
  final items = <HomeQuickItem>[];
  final todayGame = myTeamBrief == null
      ? null
      : games
            .where((game) => game.gameId == myTeamBrief.todayGameId)
            .firstOrNull;

  if (todayGame != null) {
    final showScore = todayGame.status != GameStatus.scheduled;
    items.add(
      HomeQuickItem(
        eyebrow: '마이팀 경기',
        title: showScore
            ? '${todayGame.away.shortName} ${todayGame.away.score} : ${todayGame.home.score} ${todayGame.home.shortName}'
            : '${todayGame.away.shortName} vs ${todayGame.home.shortName}',
        subtitle:
            '${todayGame.inning.isEmpty ? todayGame.startTime : todayGame.inning} · ${todayGame.stadium}',
        route: '/game/${todayGame.gameId}',
        teamId: myTeamBrief?.teamId,
        fallbackLabel: myTeamBrief?.teamLabel,
      ),
    );
  } else if (myTeamBrief?.nextGame != null) {
    final nextGame = myTeamBrief!.nextGame!;
    items.add(
      HomeQuickItem(
        eyebrow: '마이팀 경기',
        title: '${nextGame.awayName} vs ${nextGame.homeName}',
        subtitle: '${nextGame.time} · ${nextGame.stadium}',
        route: '/schedule',
        teamId: myTeamBrief.teamId,
        fallbackLabel: myTeamBrief.teamLabel,
      ),
    );
  }

  if (myTeamBrief?.standing != null) {
    final standing = myTeamBrief!.standing!;
    items.add(
      HomeQuickItem(
        eyebrow: '마이팀 순위',
        title: '${standing.rank}위 · ${standing.teamName}',
        subtitle:
            '${standing.wins}승 ${standing.losses}패 ${standing.draws}무 · ${standing.gb}G차',
        route: '/standings',
        teamId: standing.teamId,
        fallbackLabel: standing.teamName,
      ),
    );
  }

  if (overview.hrLeaders.isNotEmpty) {
    final leader = overview.hrLeaders.first;
    final leaderImageUrl = leader.playerId.isEmpty
        ? null
        : kboPlayerImageUrl(season: season, playerId: leader.playerId);
    items.add(
      HomeQuickItem(
        eyebrow: '홈런왕',
        title: '${leader.name} ${leader.value}개',
        subtitle: '${leader.teamId} · 시즌 홈런 1위',
        route: leader.playerId.isEmpty
            ? '/records'
            : '/records/player/${leader.playerId}?season=$season',
        teamId: leader.teamId,
        imageUrl: leaderImageUrl,
        fallbackLabel: leader.name,
      ),
    );
  }

  final featured = overview.todayHitter.name != null
      ? overview.todayHitter
      : overview.todayPitcher;
  if (featured.name != null) {
    items.add(
      HomeQuickItem(
        eyebrow: featured.label,
        title: featured.name!,
        subtitle: [
          featured.headline,
          featured.summary,
        ].whereType<String>().where((v) => v.isNotEmpty).join(' · '),
        route: featured.playerId != null
            ? '/records/player/${featured.playerId}?season=$season'
            : '/records',
        teamId: featured.teamId,
        imageUrl: featured.imageUrl,
        fallbackLabel: featured.name,
      ),
    );
  }

  return items.take(4).toList();
}

HomeKboBrief _buildLocalKboBrief({
  required String date,
  required String? myTeam,
  required List<Game> games,
  required List<TeamStanding> standings,
  required RecordsOverview overview,
}) {
  final liveGames = games
      .where((game) => game.status == GameStatus.live)
      .toList();
  final finalGames = games
      .where((game) => game.status == GameStatus.final_)
      .toList();
  final scheduledGames = games
      .where((game) => game.status == GameStatus.scheduled)
      .toList();
  final activeGames = [
    ...liveGames,
    ...finalGames,
  ].where((game) => game.away.score + game.home.score > 0).toList();

  final title = _kboBriefTitle(
    date: date,
    hasGames: games.isNotEmpty,
    hasLive: liveGames.isNotEmpty,
    hasFinal: finalGames.isNotEmpty,
  );
  final subtitle = _kboBriefSubtitle(
    totalGames: games.length,
    liveGames: liveGames.length,
    finalGames: finalGames.length,
    scheduledGames: scheduledGames.length,
  );
  final items = <HomeKboBriefItem>[];

  void add(HomeKboBriefItem item) {
    final duplicate = items.any(
      (current) =>
          current.route == item.route && current.eyebrow == item.eyebrow,
    );
    if (!duplicate) {
      items.add(item);
    }
  }

  final closeGame =
      activeGames
          .where((game) => (game.away.score - game.home.score).abs() <= 1)
          .toList()
        ..sort((a, b) {
          final liveCompare = _gameLivePriority(
            a,
          ).compareTo(_gameLivePriority(b));
          if (liveCompare != 0) return liveCompare;
          return _totalScore(b).compareTo(_totalScore(a));
        });
  if (closeGame.isNotEmpty) {
    final game = closeGame.first;
    add(
      HomeKboBriefItem(
        type: 'game_flow',
        eyebrow: game.status == GameStatus.live ? '접전 진행 중' : '1점 승부',
        title: _scoreLine(game),
        subtitle: '${_gameTimeLabel(game)} · ${game.stadium}',
        route: '/game/${game.gameId}',
        gameId: game.gameId,
        teamIds: [game.away.teamId, game.home.teamId],
      ),
    );
  }

  final highestScoreGames = [...activeGames]
    ..sort((a, b) => _totalScore(b).compareTo(_totalScore(a)));
  if (highestScoreGames.isNotEmpty) {
    final game = highestScoreGames.first;
    add(
      HomeKboBriefItem(
        type: 'game_flow',
        eyebrow: game.status == GameStatus.live ? '득점전 진행 중' : '최다 득점 경기',
        title: _scoreLine(game),
        subtitle: '양팀 ${_totalScore(game)}득점 · ${_gameTimeLabel(game)}',
        route: '/game/${game.gameId}',
        gameId: game.gameId,
        teamIds: [game.away.teamId, game.home.teamId],
      ),
    );
  }

  final highHitGames =
      activeGames
          .where((game) => game.hasTeamStats && _totalHits(game) >= 18)
          .toList()
        ..sort((a, b) => _totalHits(b).compareTo(_totalHits(a)));
  if (highHitGames.isNotEmpty) {
    final game = highHitGames.first;
    add(
      HomeKboBriefItem(
        type: 'player_performance',
        eyebrow: '안타 공방',
        title:
            '${game.away.shortName}-${game.home.shortName} 합계 ${_totalHits(game)}안타',
        subtitle: '${_scoreLine(game)} · 타격전 체크',
        route: '/game/${game.gameId}',
        gameId: game.gameId,
        teamIds: [game.away.teamId, game.home.teamId],
      ),
    );
  }

  if (liveGames.length > 1) {
    add(
      HomeKboBriefItem(
        type: 'league_now',
        eyebrow: 'LIVE',
        title: '지금 ${liveGames.length}경기 진행 중',
        subtitle: '스코어보드에서 접전과 흐름 변화를 같이 확인하세요.',
        route: '/schedule',
        teamIds: liveGames
            .expand((game) => [game.away.teamId, game.home.teamId])
            .toSet()
            .toList(),
      ),
    );
  }

  if (scheduledGames.isNotEmpty) {
    final game = scheduledGames.first;
    add(
      HomeKboBriefItem(
        type: 'big_match',
        eyebrow: '오늘 일정',
        title: '${game.away.shortName} vs ${game.home.shortName}',
        subtitle:
            '${game.startTime} · ${game.stadium} · 오늘 ${scheduledGames.length}경기 예정',
        route: '/game/${game.gameId}',
        gameId: game.gameId,
        teamIds: [game.away.teamId, game.home.teamId],
      ),
    );
  }

  final standingsItem = _buildStandingsBriefItem(standings);
  if (standingsItem != null) {
    add(standingsItem);
  }

  final recordItem = _buildRecordBriefItem(overview);
  if (recordItem != null) {
    add(recordItem);
  }

  if (items.isEmpty) {
    add(
      const HomeKboBriefItem(
        type: 'offday',
        eyebrow: '리그 체크',
        title: '오늘은 KBO 경기가 없습니다',
        subtitle: '순위표와 리더보드로 다음 경기 관전 포인트를 준비하세요.',
        route: '/schedule',
      ),
    );
  }

  final prioritizedItems = _prioritizeKboBriefItems(
    items,
    myTeam,
  ).take(8).toList();
  return HomeKboBrief(
    title: title,
    subtitle: subtitle,
    items: prioritizedItems,
  );
}

HomeKboBriefItem? _buildStandingsBriefItem(List<TeamStanding> standings) {
  if (standings.isEmpty) {
    return null;
  }
  final sorted = [...standings]..sort((a, b) => a.rank.compareTo(b.rank));
  final leader = sorted.first;
  final second = sorted.length > 1 ? sorted[1] : null;
  final gap = second == null || second.gb.isEmpty || second.gb == '-'
      ? '선두권 흐름 확인'
      : '${second.teamName}와 ${second.gb}G차';
  return HomeKboBriefItem(
    type: 'standings',
    eyebrow: '선두권',
    title: '${leader.rank}위 ${leader.teamName}',
    subtitle: gap,
    route: '/standings',
    teamIds: [leader.teamId, if (second != null) second.teamId],
  );
}

HomeKboBriefItem? _buildRecordBriefItem(RecordsOverview overview) {
  if (overview.hrLeaders.isEmpty) {
    return null;
  }
  final leader = overview.hrLeaders.first;
  final imageUrl = leader.playerId.isEmpty
      ? null
      : kboPlayerImageUrl(season: overview.season, playerId: leader.playerId);
  return HomeKboBriefItem(
    type: 'record_radar',
    eyebrow: '기록 레이더',
    title: '${leader.name} ${leader.value}홈런',
    subtitle: '${leader.teamId} · 시즌 홈런 1위',
    route: leader.playerId.isEmpty
        ? '/records'
        : '/records/player/${leader.playerId}?season=${overview.season}',
    teamIds: [leader.teamId],
    imageUrl: imageUrl,
    fallbackLabel: leader.name,
  );
}

List<HomeKboBriefItem> _prioritizeKboBriefItems(
  List<HomeKboBriefItem> items,
  String? myTeam,
) {
  if (myTeam == null || myTeam.isEmpty) {
    return items;
  }
  final leagueItems = items.where((item) => !item.teamIds.contains(myTeam));
  final myTeamItems = items.where((item) => item.teamIds.contains(myTeam));
  return [...leagueItems, ...myTeamItems];
}

String _kboBriefTitle({
  required String date,
  required bool hasGames,
  required bool hasLive,
  required bool hasFinal,
}) {
  if (!hasGames) {
    return '이번 주 KBO 포인트';
  }
  if (hasLive) {
    return '지금 KBO';
  }
  if (hasFinal) {
    return _isYesterday(date) ? '어제의 KBO 브리프' : '오늘의 KBO 요약';
  }
  return '오늘의 KBO 관전 포인트';
}

String _kboBriefSubtitle({
  required int totalGames,
  required int liveGames,
  required int finalGames,
  required int scheduledGames,
}) {
  if (totalGames == 0) {
    return '경기가 없는 날도 리그 흐름은 이어집니다.';
  }
  if (liveGames > 0) {
    return '$liveGames경기 진행 중 · 강한 흐름부터 정리';
  }
  if (finalGames > 0) {
    return '$finalGames경기 종료 · 기록과 흐름을 빠르게 확인';
  }
  return '$scheduledGames경기 예정 · 경기 전 체크포인트';
}

bool _isYesterday(String date) {
  final parsed = DateTime.tryParse(date);
  if (parsed == null) {
    return false;
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(parsed.year, parsed.month, parsed.day);
  return target == today.subtract(const Duration(days: 1));
}

int _gameLivePriority(Game game) => game.status == GameStatus.live ? 0 : 1;

int _totalScore(Game game) => game.away.score + game.home.score;

int _totalHits(Game game) => game.away.hits + game.home.hits;

String _scoreLine(Game game) {
  return '${game.away.shortName} ${game.away.score} : ${game.home.score} ${game.home.shortName}';
}

String _gameTimeLabel(Game game) {
  if (game.inning.isNotEmpty) {
    return game.inning;
  }
  if (game.startTime.isNotEmpty) {
    return game.startTime;
  }
  return '경기 정보';
}
