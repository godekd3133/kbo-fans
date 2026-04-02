import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

import '../core/utils/game_status_label.dart';
import '../core/widgets/dev_console.dart';
import '../data/models/game.dart';
import '../data/models/relay.dart';
import '../data/repositories/kbo_direct_repository.dart';

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
      DevConsole.instance.info('Live Activity target missing; ending current');
      await endCurrentScore();
      return;
    }

    try {
      final repository = KboDirectRepository();
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
        'inning': targetGame.status == GameStatus.scheduled
            ? '경기전'
            : secondaryTextForGameStatus(
                targetGame.status,
                inning: targetGame.inning,
                startTime: targetGame.startTime,
              ),
        'batter': currentAtBat?.batterName ?? '',
        'pitcher': currentAtBat?.pitcherName ?? '',
        'balls': currentAtBat?.balls ?? 0,
        'strikes': currentAtBat?.strikes ?? 0,
        'outs': currentAtBat?.outs ?? 0,
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
