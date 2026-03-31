import '../../data/models/game.dart';

String labelForGameStatus(GameStatus status) {
  switch (status) {
    case GameStatus.live:
      return '경기 중';
    case GameStatus.final_:
      return '경기 종료';
    case GameStatus.cancelled:
      return '경기 취소';
    case GameStatus.suspended:
      return '서스펜디드';
    case GameStatus.scheduled:
      return '경기 전';
  }
}

String labelForScheduleStatus(String status) {
  switch (status.toUpperCase()) {
    case 'LIVE':
      return '경기 중';
    case 'FINAL':
      return '경기 종료';
    case 'SUSPENDED':
      return '서스펜디드';
    case 'CANCELLED':
      return '경기 취소';
    default:
      return '경기 전';
  }
}

String secondaryTextForGameStatus(
  GameStatus status, {
  String inning = '',
  String startTime = '',
}) {
  if (inning.isNotEmpty) {
    return inning;
  }
  if (status == GameStatus.scheduled && startTime.isNotEmpty) {
    return '$startTime 예정';
  }
  return labelForGameStatus(status);
}
