import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:workmanager/workmanager.dart';

import '../core/config/app_config.dart';
import '../core/widgets/dev_console.dart';
import '../data/api/api_client.dart';
import '../data/models/game.dart';
import '../data/repositories/api_game_repository.dart';
import '../data/repositories/game_repository.dart';
import '../data/repositories/kbo_direct_repository.dart';
import 'live_activity_service.dart';

const widgetRefreshTaskName = 'kbo_widget_refresh';
const _widgetGroupId = 'group.com.kbofans.kbo_fans';
const _androidWidgetName = 'KboFansScoreWidgetProvider';
const _androidQualifiedWidgetName =
    'com.kbofans.kbo_fans.KboFansScoreWidgetProvider';
const _iosWidgetName = 'KboFansWidget';

@pragma('vm:entry-point')
void widgetCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      AppConfig.initialize();
      await WidgetSyncService.instance.initialize();
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final myTeamId = await HomeWidget.getWidgetData<String>('widget_my_team');
      final games = await WidgetSyncService.instance.fetchBackgroundScoreboard(
        date: date,
        myTeamId: myTeamId,
      );
      await WidgetSyncService.instance.syncScoreboard(
        games: games,
        myTeamId: myTeamId,
      );
      return true;
    } catch (_) {
      return false;
    }
  });
}

class WidgetSyncService {
  WidgetSyncService._();

  static final WidgetSyncService instance = WidgetSyncService._();
  String? _lastSyncSignature;

  Future<void> initialize() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await HomeWidget.setAppGroupId(_widgetGroupId);
      DevConsole.instance.info('Widget app group initialized');
    }
  }

  GameRepository createRepositoryForBackground() {
    if (AppConfig.instance.preferDirectScrape) {
      return KboDirectRepository();
    }
    return ApiGameRepository(ApiClient());
  }

  Future<List<Game>> fetchBackgroundScoreboard({
    required String date,
    required String? myTeamId,
  }) {
    if (AppConfig.instance.preferDirectScrape) {
      return KboDirectRepository().getScoreboard(date);
    }
    return ApiGameRepository(
      ApiClient(),
    ).getCompactScoreboard(date, myTeamId: myTeamId);
  }

  Future<void> syncScoreboard({
    required List<Game> games,
    required String? myTeamId,
    GameRepository? repository,
  }) async {
    if (kIsWeb) {
      return;
    }

    await initialize();

    final selected = _selectGame(games, myTeamId);
    final signature = _buildSignature(games: games, myTeamId: myTeamId);
    if (_lastSyncSignature == signature) {
      DevConsole.instance.info('Widget sync skipped: same signature');
      return;
    }
    _lastSyncSignature = signature;
    DevConsole.instance.info(
      'Widget sync begin: game=${selected?.gameId ?? '-'} myTeam=${myTeamId ?? '-'}',
    );
    await HomeWidget.saveWidgetData<String>('widget_my_team', myTeamId);

    if (selected == null) {
      await Future.wait([
        HomeWidget.saveWidgetData<String>('widget_title', '오늘 경기 없음'),
        HomeWidget.saveWidgetData<String>('widget_subtitle', 'KBO Fans'),
        HomeWidget.saveWidgetData<String>('widget_status', ''),
        HomeWidget.saveWidgetData<String>('widget_score', ''),
        HomeWidget.saveWidgetData<String>('widget_away_team_id', ''),
        HomeWidget.saveWidgetData<String>('widget_home_team_id', ''),
        HomeWidget.saveWidgetData<String>('widget_batter', ''),
        HomeWidget.saveWidgetData<String>('widget_pitcher', ''),
        HomeWidget.saveWidgetData<String>('widget_pitch_count', '0'),
        HomeWidget.saveWidgetData<String>(
          'widget_updated_at',
          _updatedAtText(),
        ),
      ]);
      await _updateWidget();
      await LiveActivityService.instance.endCurrentScore();
      DevConsole.instance.info('Widget sync complete: no selected game');
      return;
    }

    await Future.wait([
      HomeWidget.saveWidgetData<String>(
        'widget_title',
        '${selected.away.shortName} vs ${selected.home.shortName}',
      ),
      HomeWidget.saveWidgetData<String>('widget_subtitle', selected.stadium),
      HomeWidget.saveWidgetData<String>(
        'widget_status',
        selected.inning.isEmpty ? '${selected.startTime} 예정' : selected.inning,
      ),
      HomeWidget.saveWidgetData<String>(
        'widget_score',
        '${selected.away.score} : ${selected.home.score}',
      ),
      HomeWidget.saveWidgetData<String>(
        'widget_away_team_id',
        selected.away.teamId,
      ),
      HomeWidget.saveWidgetData<String>(
        'widget_home_team_id',
        selected.home.teamId,
      ),
      HomeWidget.saveWidgetData<String>('widget_batter', ''),
      HomeWidget.saveWidgetData<String>('widget_pitcher', ''),
      HomeWidget.saveWidgetData<String>('widget_pitch_count', '0'),
      HomeWidget.saveWidgetData<String>('widget_updated_at', _updatedAtText()),
      HomeWidget.saveWidgetData<String>('widget_game_id', selected.gameId),
    ]);

    await _updateWidget();
    await LiveActivityService.instance.syncCurrentScore(
      games: games,
      myTeamId: myTeamId,
    );
    DevConsole.instance.info('Widget sync complete: ${selected.gameId}');
  }

  Future<void> registerBackgroundRefresh() async {
    await Workmanager().registerPeriodicTask(
      'kbo-widget-periodic',
      widgetRefreshTaskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  Future<void> _updateWidget() async {
    await HomeWidget.updateWidget(
      name: _androidWidgetName,
      iOSName: _iosWidgetName,
    );
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await HomeWidget.updateWidget(
        qualifiedAndroidName: _androidQualifiedWidgetName,
      );
    }
    DevConsole.instance.info('Widget update request sent');
  }

  Game? _selectGame(List<Game> games, String? myTeamId) {
    if (games.isEmpty) {
      return null;
    }

    final liveMyTeamGame = _findGame(games, myTeamId: myTeamId, onlyLive: true);
    if (liveMyTeamGame != null) {
      return liveMyTeamGame;
    }

    final myTeamGame = _findGame(games, myTeamId: myTeamId);
    if (myTeamGame != null) {
      return myTeamGame;
    }

    final liveGame = _findGame(games, onlyLive: true);
    if (liveGame != null) {
      return liveGame;
    }

    return null;
  }

  Game? _findGame(List<Game> games, {String? myTeamId, bool onlyLive = false}) {
    for (final game in games) {
      if (onlyLive && game.status != GameStatus.live) {
        continue;
      }
      if (myTeamId == null ||
          game.away.teamId == myTeamId ||
          game.home.teamId == myTeamId) {
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

  String _buildSignature({
    required List<Game> games,
    required String? myTeamId,
  }) {
    final hasLive = games.any((game) => game.status == GameStatus.live);
    final liveRefreshBucket = hasLive
        ? DateTime.now().millisecondsSinceEpoch ~/ 10000
        : 0;
    final payload = games
        .map(
          (game) => [
            game.gameId,
            game.status.name,
            game.inning,
            game.away.score,
            game.home.score,
          ].join(':'),
        )
        .join(',');
    return '${myTeamId ?? '-'}|$payload|$liveRefreshBucket';
  }
}
