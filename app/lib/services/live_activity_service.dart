import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/game_status_label.dart';
import '../core/widgets/dev_console.dart';
import '../data/models/game.dart';

class LiveActivityService {
  LiveActivityService._();

  static final LiveActivityService instance = LiveActivityService._();
  static const MethodChannel _channel = MethodChannel('kbo_fans/live_activity');
  static const _followedGameIdKey = 'live_activity.followed_game_id';

  Future<void> followGame(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_followedGameIdKey, gameId);
  }

  Future<void> stopFollowing() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_followedGameIdKey);
    await endCurrentScore();
  }

  Future<String?> followedGameId() async {
    final prefs = await SharedPreferences.getInstance();
    final gameId = prefs.getString(_followedGameIdKey);
    if (gameId == null || gameId.isEmpty) {
      return null;
    }
    return gameId;
  }

  Future<bool> isFollowing(String gameId) async {
    return await followedGameId() == gameId;
  }

  Future<void> syncCurrentScore({
    required List<Game> games,
    required String? myTeamId,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    final followedId = await followedGameId();
    if (followedId == null) {
      await endCurrentScore();
      return;
    }

    final targetGame = _findGame(games, followedId);
    if (targetGame == null) {
      DevConsole.instance.info('Live Activity followed game missing; ending');
      await stopFollowing();
      return;
    }

    await syncFollowedGame(targetGame);
  }

  Future<void> syncFollowedGame(Game game) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    final followedId = await followedGameId();
    if (followedId != game.gameId) {
      return;
    }

    if (game.status == GameStatus.final_ ||
        game.status == GameStatus.cancelled ||
        game.status == GameStatus.suspended) {
      await stopFollowing();
      return;
    }

    if (game.status != GameStatus.live) {
      await endCurrentScore();
      return;
    }

    await _syncGame(game);
  }

  Future<void> _syncGame(Game targetGame) async {
    try {
      await _channel.invokeMethod('syncCurrentScore', {
        'gameId': targetGame.gameId,
        'awayTeamId': targetGame.away.teamId,
        'awayTeam': targetGame.away.shortName,
        'homeTeamId': targetGame.home.teamId,
        'homeTeam': targetGame.home.shortName,
        'awayScore': targetGame.away.score,
        'homeScore': targetGame.home.score,
        'inning': targetGame.status == GameStatus.scheduled
            ? '경기전'
            : secondaryTextForGameStatus(
                targetGame.status,
                inning: targetGame.inning,
                startTime: targetGame.startTime,
              ),
        'batter': '',
        'pitcher': '',
        'pitchCount': 0,
        'balls': 0,
        'strikes': 0,
        'outs': 0,
        'stadium': targetGame.stadium,
        'updatedAt': _updatedAtText(),
      });
      DevConsole.instance.info(
        'Live Activity sync sent: ${targetGame.gameId} ${targetGame.away.score}:${targetGame.home.score} ${targetGame.inning}',
      );
    } on PlatformException {
      // Live Activity is optional. Fail silently when unavailable.
      DevConsole.instance.warn('Live Activity sync failed: platform exception');
    } on MissingPluginException {
      // iOS native channel may be unavailable in some debug/background cases.
      DevConsole.instance.warn('Live Activity sync failed: missing plugin');
    }
  }

  Future<void> endCurrentScore() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    try {
      await _channel.invokeMethod('endCurrentScore');
      DevConsole.instance.info('Live Activity end sent');
    } on PlatformException {
      // Ignore cleanup errors when the channel exists but ActivityKit is unavailable.
      DevConsole.instance.warn('Live Activity end failed: platform exception');
    } on MissingPluginException {
      // Ignore cleanup errors in isolates that do not register the native channel.
      DevConsole.instance.warn('Live Activity end failed: missing plugin');
    }
  }

  Game? _findGame(List<Game> games, String gameId) {
    for (final game in games) {
      if (game.gameId == gameId) {
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
