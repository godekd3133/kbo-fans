import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

import '../data/models/game.dart';

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

    final liveGame = _selectLiveGame(games, myTeamId);
    if (liveGame == null) {
      await endCurrentScore();
      return;
    }

    try {
      await _channel.invokeMethod('syncCurrentScore', {
        'gameId': liveGame.gameId,
        'awayTeam': liveGame.away.shortName,
        'homeTeam': liveGame.home.shortName,
        'awayScore': liveGame.away.score,
        'homeScore': liveGame.home.score,
        'inning': liveGame.inning,
        'stadium': liveGame.stadium,
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

  Game? _selectLiveGame(List<Game> games, String? myTeamId) {
    if (myTeamId != null) {
      for (final game in games) {
        final isMyTeam =
            game.away.teamId == myTeamId || game.home.teamId == myTeamId;
        if (isMyTeam && game.status == GameStatus.live) {
          return game;
        }
      }
    }

    for (final game in games) {
      if (game.status == GameStatus.live) {
        return game;
      }
    }

    return null;
  }

  String _updatedAtText() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
