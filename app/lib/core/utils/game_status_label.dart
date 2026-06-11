import '../../data/models/game.dart';

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
      return '경기 중';
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
