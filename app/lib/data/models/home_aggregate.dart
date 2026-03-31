import 'schedule.dart';

class HomeQuickItem {
  final String eyebrow;
  final String title;
  final String subtitle;
  final String route;

  const HomeQuickItem({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.route,
  });
}

class HomeRecentGameSummary {
  final String result;
  final String opponentName;
  final String score;

  const HomeRecentGameSummary({
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
