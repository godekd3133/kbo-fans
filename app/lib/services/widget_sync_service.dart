import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:workmanager/workmanager.dart';

import '../core/config/app_config.dart';
import '../data/api/api_client.dart';
import '../data/models/game.dart';
import '../data/repositories/api_game_repository.dart';
import '../data/repositories/game_repository.dart';
import '../data/repositories/kbo_direct_repository.dart';

const widgetRefreshTaskName = 'kbo_widget_refresh';
const _widgetGroupId = 'group.com.kbofans.kbo_fans';
const _androidWidgetName = 'KboFansScoreWidgetProvider';
const _androidQualifiedWidgetName = 'com.kbofans.kbo_fans.KboFansScoreWidgetProvider';
const _iosWidgetName = 'KboFansWidget';

@pragma('vm:entry-point')
void widgetCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      AppConfig.initialize();
      await WidgetSyncService.instance.initialize();
      final repository = WidgetSyncService.instance.createRepositoryForBackground();
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final games = await repository.getScoreboard(date);
      final myTeamId = await HomeWidget.getWidgetData<String>('widget_my_team');
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

  Future<void> initialize() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await HomeWidget.setAppGroupId(_widgetGroupId);
    }
  }

  GameRepository createRepositoryForBackground() {
    if (AppConfig.instance.isRelease) {
      return ApiGameRepository(ApiClient());
    }
    return KboDirectRepository();
  }

  Future<void> syncScoreboard({
    required List<Game> games,
    required String? myTeamId,
  }) async {
    final selected = _selectGame(games, myTeamId);
    await HomeWidget.saveWidgetData<String>('widget_my_team', myTeamId);

    if (selected == null) {
      await Future.wait([
        HomeWidget.saveWidgetData<String>('widget_title', '오늘 경기 없음'),
        HomeWidget.saveWidgetData<String>('widget_subtitle', 'KBO Fans'),
        HomeWidget.saveWidgetData<String>('widget_status', ''),
        HomeWidget.saveWidgetData<String>('widget_score', ''),
        HomeWidget.saveWidgetData<String>('widget_updated_at', _updatedAtText()),
      ]);
      await _updateWidget();
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
      HomeWidget.saveWidgetData<String>('widget_updated_at', _updatedAtText()),
      HomeWidget.saveWidgetData<String>('widget_game_id', selected.gameId),
    ]);

    await _updateWidget();
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
    await HomeWidget.updateWidget(name: _androidWidgetName, iOSName: _iosWidgetName);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await HomeWidget.updateWidget(
        qualifiedAndroidName: _androidQualifiedWidgetName,
      );
    }
  }

  Game? _selectGame(List<Game> games, String? myTeamId) {
    if (games.isEmpty) {
      return null;
    }

    if (myTeamId != null) {
      for (final game in games) {
        if (game.away.teamId == myTeamId || game.home.teamId == myTeamId) {
          return game;
        }
      }
    }

    for (final game in games) {
      if (game.status == GameStatus.live) {
        return game;
      }
    }

    return games.first;
  }

  String _updatedAtText() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
