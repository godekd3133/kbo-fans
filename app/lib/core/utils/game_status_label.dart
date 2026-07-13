import 'kbo_time.dart';
import '../../data/models/game.dart';

const ticketInfoGameDetailHideLeadTime = Duration(hours: 2);

bool isTerminalGameStatus(GameStatus status) {
  switch (status) {
    case GameStatus.final_:
    case GameStatus.cancelled:
    case GameStatus.suspended:
      return true;
    case GameStatus.live:
    case GameStatus.scheduled:
      return false;
  }
}

bool shouldShowTicketInfoForGameStatus(GameStatus status) {
  return status == GameStatus.scheduled;
}

bool shouldShowTicketInfoForGameDetail(Game game, {DateTime? now}) {
  if (game.ticketInfo == null ||
      !shouldShowTicketInfoForGameStatus(game.status)) {
    return false;
  }

  final startAt = _gameStartDateTime(game.gameId, game.startTime);
  if (startAt == null) {
    return true;
  }

  final hideFrom = startAt.subtract(ticketInfoGameDetailHideLeadTime);
  return (now ?? DateTime.now()).isBefore(hideFrom);
}

bool isTerminalScheduleStatus(String status) {
  switch (status.toUpperCase()) {
    case 'FINAL':
    case 'CANCELLED':
    case 'SUSPENDED':
      return true;
    default:
      return false;
  }
}

DateTime? _gameStartDateTime(String gameId, String startTime) {
  if (gameId.length < 8) {
    return null;
  }

  final year = int.tryParse(gameId.substring(0, 4));
  final month = int.tryParse(gameId.substring(4, 6));
  final day = int.tryParse(gameId.substring(6, 8));
  final timeMatch = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(startTime.trim());
  if (year == null || month == null || day == null || timeMatch == null) {
    return null;
  }

  final hour = int.tryParse(timeMatch.group(1)!);
  final minute = int.tryParse(timeMatch.group(2)!);
  if (hour == null || minute == null || hour > 23 || minute > 59) {
    return null;
  }

  return kboInstantFromCivil(
    year: year,
    month: month,
    day: day,
    hour: hour,
    minute: minute,
  );
}

bool shouldShowTicketInfoForScheduleStatus(String status) {
  switch (status.toUpperCase()) {
    case 'LIVE':
    case 'FINAL':
    case 'CANCELLED':
    case 'SUSPENDED':
      return false;
    default:
      return true;
  }
}

String? _normalizedStatusLabel(String? statusLabel) {
  final label = statusLabel?.trim() ?? '';
  if (label.isEmpty || label == '정상경기') {
    return null;
  }
  return label;
}

String labelForGameStatus(GameStatus status, {String? statusLabel}) {
  switch (status) {
    case GameStatus.live:
      return _normalizedStatusLabel(statusLabel) ?? '경기 중';
    case GameStatus.final_:
      return '경기 종료';
    case GameStatus.cancelled:
      return _normalizedStatusLabel(statusLabel) ?? '경기 취소';
    case GameStatus.suspended:
      return '서스펜디드';
    case GameStatus.scheduled:
      return '경기 전';
  }
}

String labelForScheduleStatus(String status, {String? statusLabel}) {
  switch (status.toUpperCase()) {
    case 'LIVE':
      return '경기 중';
    case 'FINAL':
      return '경기 종료';
    case 'SUSPENDED':
      return '서스펜디드';
    case 'CANCELLED':
      return _normalizedStatusLabel(statusLabel) ?? '경기 취소';
    default:
      return '경기 전';
  }
}

String secondaryTextForGameStatus(
  GameStatus status, {
  String inning = '',
  String startTime = '',
  String? statusLabel,
}) {
  final label = labelForGameStatus(status, statusLabel: statusLabel);
  if (inning.isNotEmpty) {
    if (status == GameStatus.cancelled &&
        (inning == 'CANCELLED' || inning == '경기취소' || inning == '경기 취소')) {
      return label;
    }
    return inning;
  }
  if (status == GameStatus.scheduled && startTime.isNotEmpty) {
    return '$startTime 예정';
  }
  return label;
}
