import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import 'api/api_client.dart';
import 'repositories/game_repository.dart';
import 'repositories/api_game_repository.dart';
import 'repositories/kbo_direct_repository.dart';
import 'models/game.dart';
import 'models/schedule.dart';

/// API 클라이언트 (RELEASE에서만 실제 사용)
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// GameRepository — 환경에 따라 자동 전환
/// LOCAL/DEV: KBO 직접 크롤링 (웹은 CORS proxy 경유)
/// RELEASE: 백엔드 API 서버 경유
final gameRepositoryProvider = Provider<GameRepository>((ref) {
  if (AppConfig.instance.isRelease) {
    return ApiGameRepository(ref.read(apiClientProvider));
  }
  return KboDirectRepository();
});

/// 오늘의 스코어보드
final scoreboardProvider = FutureProvider.family<List<Game>, String>((ref, date) {
  return ref.read(gameRepositoryProvider).getScoreboard(date);
});

/// 월간 일정
final scheduleProvider = FutureProvider.family<List<ScheduleDay>, String>((ref, yearMonth) {
  return ref.read(gameRepositoryProvider).getSchedule(yearMonth);
});

/// 팀 순위
final standingsProvider = FutureProvider.family<List<TeamStanding>, int>((ref, season) {
  return ref.read(gameRepositoryProvider).getStandings(season);
});
