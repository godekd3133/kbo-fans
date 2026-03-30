import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import 'api/api_client.dart';
import 'repositories/game_repository.dart';
import 'repositories/mock_game_repository.dart';
import 'repositories/api_game_repository.dart';
import 'models/game.dart';

/// API 클라이언트 (DEV/RELEASE에서만 실제 사용)
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// GameRepository — 환경에 따라 Mock or API 자동 전환
final gameRepositoryProvider = Provider<GameRepository>((ref) {
  if (AppConfig.instance.useMockData) {
    return MockGameRepository();
  }
  return ApiGameRepository(ref.read(apiClientProvider));
});

/// 오늘의 스코어보드
final scoreboardProvider = FutureProvider.family<List<Game>, String>((ref, date) {
  return ref.read(gameRepositoryProvider).getScoreboard(date);
});
