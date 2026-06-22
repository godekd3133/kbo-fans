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
  final String? statusLabel;
  final int? crowd;
  final TicketInfo? ticketInfo;
  final HighlightInfo? highlightInfo;
  final bool lineupOpened;

  const Game({
    required this.gameId,
    required this.status,
    required this.inning,
    required this.away,
    required this.home,
    required this.stadium,
    required this.startTime,
    this.statusLabel,
    this.crowd,
    this.ticketInfo,
    this.highlightInfo,
    this.lineupOpened = false,
  });

  bool get hasTeamStats => away.hasStats && home.hasStats;

  bool get isPregameLineupOpen {
    if (status != GameStatus.scheduled) {
      return false;
    }
    if (lineupOpened) {
      return true;
    }
    return _mentionsLineupOpen(inning) || _mentionsLineupOpen(statusLabel);
  }
}

bool _mentionsLineupOpen(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) {
    return false;
  }
  final mentionsLineup =
      text.contains('라인업') || text.toLowerCase().contains('lineup');
  if (!mentionsLineup) {
    return false;
  }
  return text.contains('공개') ||
      text.contains('발표') ||
      text.toLowerCase().contains('open');
}
