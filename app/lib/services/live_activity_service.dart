import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

import '../core/config/app_config.dart';
import '../core/utils/game_status_label.dart';
import '../data/models/game.dart';
import '../data/models/relay.dart';
import '../data/repositories/api_game_repository.dart';
import '../data/repositories/kbo_direct_repository.dart';
import '../data/api/api_client.dart';

class LiveActivityService {
  LiveActivityService._();

  static final LiveActivityService instance = LiveActivityService._();
  static const MethodChannel _channel = MethodChannel('kbo_fans/live_activity');

  Future<void> syncCurrentScore({
    required List<Game> games,
    required String? myTeamId,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    final targetGame = _selectTargetGame(games, myTeamId);
    if (targetGame == null) {
      await endCurrentScore();
      return;
    }

    try {
      final repository = AppConfig.instance.isRelease
          ? ApiGameRepository(ApiClient())
          : KboDirectRepository();
      CurrentAtBat? currentAtBat;
      try {
        currentAtBat = await repository.getCurrentAtBat(targetGame.gameId);
      } catch (_) {
        currentAtBat = null;
      }

      await _channel.invokeMethod('syncCurrentScore', {
        'gameId': targetGame.gameId,
        'awayTeam': targetGame.away.shortName,
        'homeTeam': targetGame.home.shortName,
        'awayScore': targetGame.away.score,
        'homeScore': targetGame.home.score,
        'inning': secondaryTextForGameStatus(
          targetGame.status,
          inning: targetGame.inning,
          startTime: targetGame.startTime,
        ),
        'batter': currentAtBat?.batterName ?? '',
        'pitcher': currentAtBat?.pitcherName ?? '',
        'stadium': targetGame.stadium,
        'updatedAt': _updatedAtText(),
      });
    } on PlatformException {
      // Live Activity is optional. Fail silently when unavailable.
    } on MissingPluginException {
      // iOS native channel may be unavailable in some debug/background cases.
    }
  }

  Future<void> endCurrentScore() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    try {
      await _channel.invokeMethod('endCurrentScore');
    } on PlatformException {
      // Ignore cleanup errors when the channel exists but ActivityKit is unavailable.
    } on MissingPluginException {
      // Ignore cleanup errors in isolates that do not register the native channel.
    }
  }

  Game? _selectTargetGame(List<Game> games, String? myTeamId) {
    if (myTeamId != null) {
      for (final game in games) {
        final isMyTeam =
            game.away.teamId == myTeamId || game.home.teamId == myTeamId;
        if (isMyTeam && game.status == GameStatus.live) {
          return game;
        }
      }
      for (final game in games) {
        final isMyTeam =
            game.away.teamId == myTeamId || game.home.teamId == myTeamId;
        if (isMyTeam && game.status == GameStatus.scheduled) {
          return game;
        }
      }
    }

    for (final game in games) {
      if (game.status == GameStatus.live) {
        return game;
      }
    }

    for (final game in games) {
      if (game.status == GameStatus.scheduled) {
        return game;
      }
    }

    return null;
  }

  String _updatedAtText() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}
