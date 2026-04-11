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
  final List<HomeQuickItem> quickItems;

  const HomeAggregate({
    required this.date,
    required this.myTeam,
    required this.myTeamBrief,
    required this.quickItems,
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

  return HomeAggregate(
    date: date,
    myTeam: myTeam,
    myTeamBrief: myTeamBrief,
    quickItems: quickItems,
  );
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
          .where(
            (entry) => entry.$2.awayScore != null && entry.$2.homeScore != null,
          )
          .toList()
        ..sort((a, b) => b.$1.compareTo(a.$1));

  final recentSummaries = <HomeRecentGameSummary>[];
  var wins = 0;
  var losses = 0;
  var draws = 0;
  for (final entry in recentGames.take(3)) {
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
    items.add(
      HomeQuickItem(
        eyebrow: '마이팀 경기',
        title:
            '${todayGame.away.shortName} ${todayGame.away.score} : ${todayGame.home.score} ${todayGame.home.shortName}',
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
    items.add(
      HomeQuickItem(
        eyebrow: '홈런 리더',
        title: '${leader.name} ${leader.value}개',
        subtitle: '${leader.teamId} · 시즌 홈런 선두',
        route: '/records',
        teamId: leader.teamId,
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
