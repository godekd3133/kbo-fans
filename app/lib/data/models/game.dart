import 'highlight_info.dart';
import 'ticketing.dart';

enum GameStatus { scheduled, live, final_, cancelled, suspended }

class TeamScore {
  final String teamId;
  final String teamName;
  final String shortName;
  final int score;
  final List<int?> innings; // null = 미진행
  final int hits;
  final int errors;
  final int walks;
  final bool hasStats;

  const TeamScore({
    required this.teamId,
    required this.teamName,
    required this.shortName,
    required this.score,
    required this.innings,
    this.hits = 0,
    this.errors = 0,
    this.walks = 0,
    this.hasStats = true,
  });
}

class Game {
  final String gameId;
  final GameStatus status;
  final String inning; // "4회초", "경기종료" 등
  final TeamScore away;
  final TeamScore home;
  final String stadium;
  final String startTime;
  final int? crowd;
  final TicketInfo? ticketInfo;
  final HighlightInfo? highlightInfo;

  const Game({
    required this.gameId,
    required this.status,
    required this.inning,
    required this.away,
    required this.home,
    required this.stadium,
    required this.startTime,
    this.crowd,
    this.ticketInfo,
    this.highlightInfo,
  });

  bool get hasTeamStats => away.hasStats && home.hasStats;
}
