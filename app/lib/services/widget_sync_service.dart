import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:workmanager/workmanager.dart';

import '../core/config/app_config.dart';
import '../core/utils/game_status_label.dart';
import '../core/utils/team_display.dart';
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
const _androidSlateWidgetName = 'KboFansSlateWidgetProvider';
const _androidQualifiedSlateWidgetName =
    'com.kbofans.kbo_fans.KboFansSlateWidgetProvider';
const _iosWidgetName = 'KboFansWidget';
const _homeWidgetLaunchUri = 'kboFans://home?homeWidget';
const _maxWidgetSummaryLines = 4;

@pragma('vm:entry-point')
void widgetCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      AppConfig.initialize();
      await WidgetSyncService.instance.initialize();
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final myTeamId = decodeWidgetMyTeamIdFromStorage(
        await HomeWidget.getWidgetData<String>('widget_my_team'),
      );
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
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await HomeWidget.setAppGroupId(_widgetGroupId);
      DevConsole.instance.info('Widget app group initialized');
    }
    _initialized = true;
  }

  GameRepository createRepositoryForBackground() {
    if (AppConfig.instance.shouldUseBackendApi) {
      return ApiGameRepository(ApiClient());
    }
    return KboDirectRepository();
  }

  Future<List<Game>> fetchBackgroundScoreboard({
    required String date,
    required String? myTeamId,
  }) {
    if (AppConfig.instance.shouldUseBackendApi) {
      return ApiGameRepository(
        ApiClient(),
      ).getCompactScoreboard(date, myTeamId: myTeamId);
    }
    return KboDirectRepository().getScoreboard(date);
  }

  Future<void> syncScoreboard({
    required List<Game> games,
    required String? myTeamId,
    GameRepository? repository,
  }) async {
    if (kIsWeb) {
      return;
    }

    final selected = _selectGame(games, myTeamId);
    final signature = _buildSignature(games: games, myTeamId: myTeamId);
    if (_lastSyncSignature == signature) {
      DevConsole.instance.info('Widget sync skipped: same signature');
      return;
    }

    await initialize();
    _lastSyncSignature = signature;
    DevConsole.instance.info(
      'Widget sync begin: game=${selected?.gameId ?? '-'} myTeam=${myTeamId ?? '-'}',
    );
    await HomeWidget.saveWidgetData<String>(
      'widget_my_team',
      encodeWidgetMyTeamIdForStorage(myTeamId),
    );
    final updatedAt = DateTime.now();
    final updatedAtText = _updatedAtText(updatedAt);
    final updatedAtEpoch = updatedAt.millisecondsSinceEpoch.toString();
    final summary = _buildSummary(
      games: games,
      selected: selected,
      myTeamId: myTeamId,
    );

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
        HomeWidget.saveWidgetData<String>('widget_balls', '0'),
        HomeWidget.saveWidgetData<String>('widget_strikes', '0'),
        HomeWidget.saveWidgetData<String>('widget_outs', '0'),
        HomeWidget.saveWidgetData<String>('widget_updated_at', updatedAtText),
        HomeWidget.saveWidgetData<String>(
          'widget_updated_at_epoch',
          updatedAtEpoch,
        ),
        HomeWidget.saveWidgetData<String>('widget_status_kind', 'none'),
        HomeWidget.saveWidgetData<String>('widget_game_id', ''),
        HomeWidget.saveWidgetData<String>(
          'widget_launch_uri',
          _homeWidgetLaunchUri,
        ),
        ..._summarySaveOperations(summary),
      ]);
      await _updateWidget();
      await LiveActivityService.instance.endCurrentScore();
      DevConsole.instance.info('Widget sync complete: no selected game');
      return;
    }

    await Future.wait([
      HomeWidget.saveWidgetData<String>(
        'widget_title',
        _widgetGameTitle(selected),
      ),
      HomeWidget.saveWidgetData<String>('widget_subtitle', selected.stadium),
      HomeWidget.saveWidgetData<String>(
        'widget_status',
        selected.isPregameLineupOpen
            ? '경기전'
            : selected.inning.isEmpty
            ? secondaryTextForGameStatus(
                selected.status,
                startTime: selected.startTime,
                statusLabel: selected.statusLabel,
              )
            : selected.inning,
      ),
      HomeWidget.saveWidgetData<String>(
        'widget_score',
        selected.status == GameStatus.scheduled ||
                selected.status == GameStatus.cancelled
            ? 'vs'
            : '${selected.away.score} : ${selected.home.score}',
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
      HomeWidget.saveWidgetData<String>('widget_balls', '0'),
      HomeWidget.saveWidgetData<String>('widget_strikes', '0'),
      HomeWidget.saveWidgetData<String>('widget_outs', '0'),
      HomeWidget.saveWidgetData<String>('widget_updated_at', updatedAtText),
      HomeWidget.saveWidgetData<String>(
        'widget_updated_at_epoch',
        updatedAtEpoch,
      ),
      HomeWidget.saveWidgetData<String>(
        'widget_status_kind',
        selected.status.name,
      ),
      HomeWidget.saveWidgetData<String>('widget_game_id', selected.gameId),
      HomeWidget.saveWidgetData<String>(
        'widget_launch_uri',
        _launchUriForGame(selected),
      ),
      ..._summarySaveOperations(summary),
    ]);

    await _updateWidget();
    await LiveActivityService.instance.syncCurrentScore(
      games: games,
      myTeamId: myTeamId,
      repository: repository ?? createRepositoryForBackground(),
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
      await HomeWidget.updateWidget(name: _androidSlateWidgetName);
      await HomeWidget.updateWidget(
        qualifiedAndroidName: _androidQualifiedSlateWidgetName,
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

    final liveGame = _findGame(games, onlyLive: true);
    if (liveGame != null) {
      return liveGame;
    }

    final pregameMyTeamGame = _findGame(
      games,
      myTeamId: myTeamId,
      onlyPregameLineup: true,
    );
    if (pregameMyTeamGame != null) {
      return pregameMyTeamGame;
    }

    final scheduledMyTeamGame = _findGame(
      games,
      myTeamId: myTeamId,
      onlyScheduled: true,
    );
    if (scheduledMyTeamGame != null) {
      return scheduledMyTeamGame;
    }

    final pregameGame = _findGame(games, onlyPregameLineup: true);
    if (pregameGame != null) {
      return pregameGame;
    }

    final scheduledGame = _findGame(games, onlyScheduled: true);
    if (scheduledGame != null) {
      return scheduledGame;
    }

    final myTeamGame = _findGame(games, myTeamId: myTeamId);
    return myTeamGame ?? games.first;
  }

  Game? _findGame(
    List<Game> games, {
    String? myTeamId,
    bool onlyLive = false,
    bool onlyPregameLineup = false,
    bool onlyScheduled = false,
  }) {
    for (final game in games) {
      if (onlyLive && game.status != GameStatus.live) {
        continue;
      }
      if (onlyPregameLineup && !game.isPregameLineupOpen) {
        continue;
      }
      if (onlyScheduled && game.status != GameStatus.scheduled) {
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

  String _updatedAtText(DateTime now) {
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  String _launchUriForGame(Game game) {
    final tab = switch (game.status) {
      GameStatus.live => 'relay',
      GameStatus.final_ => 'score',
      GameStatus.cancelled => 'score',
      GameStatus.suspended => 'score',
      GameStatus.scheduled => game.isPregameLineupOpen ? 'lineup' : 'score',
    };
    return Uri(
      scheme: 'kboFans',
      host: 'game',
      queryParameters: {'gameId': game.gameId, 'tab': tab, 'homeWidget': ''},
    ).toString();
  }

  String _buildSignature({
    required List<Game> games,
    required String? myTeamId,
  }) {
    final hasLive = games.any((game) => game.status == GameStatus.live);
    final refreshBucket =
        DateTime.now().millisecondsSinceEpoch ~/
        (hasLive ? 10000 : 15 * 60 * 1000);
    final payload = games
        .map(
          (game) => [
            game.gameId,
            game.status.name,
            game.statusLabel ?? '',
            game.inning,
            game.away.score,
            game.home.score,
            game.lineupOpened,
          ].join(':'),
        )
        .join(',');
    return '${myTeamId ?? '-'}|$payload|$refreshBucket';
  }
}

class _WidgetSummary {
  const _WidgetSummary({
    required this.title,
    required this.contextLabel,
    required this.todayCount,
    required this.liveCount,
    required this.lines,
    required this.secondaryTitle,
    required this.secondaryStatus,
    required this.secondaryScore,
  });

  final String title;
  final String contextLabel;
  final int todayCount;
  final int liveCount;
  final List<String> lines;
  final String secondaryTitle;
  final String secondaryStatus;
  final String secondaryScore;
}

String _widgetGameTitle(Game game) {
  final away = kboShortTeamDisplayName(
    teamId: game.away.teamId,
    teamName: game.away.teamName,
    shortName: game.away.shortName,
  );
  final home = kboShortTeamDisplayName(
    teamId: game.home.teamId,
    teamName: game.home.teamName,
    shortName: game.home.shortName,
  );
  return '$away vs $home';
}

_WidgetSummary _buildSummary({
  required List<Game> games,
  required Game? selected,
  required String? myTeamId,
}) {
  final ordered = _orderedWidgetGames(
    games: games,
    selected: selected,
    myTeamId: myTeamId,
  );
  final lines = ordered
      .take(_maxWidgetSummaryLines)
      .map(_widgetGameSummaryLine)
      .toList(growable: false);
  final secondary = ordered.length > 1 ? ordered[1] : null;
  final liveCount = games
      .where((game) => game.status == GameStatus.live)
      .length;
  final selectedIsMyTeam =
      selected != null && myTeamId != null && _isMyTeamGame(selected, myTeamId);

  return _WidgetSummary(
    title: games.isEmpty
        ? '오늘 경기 없음'
        : liveCount > 0
        ? 'LIVE $liveCount경기'
        : '오늘 ${games.length}경기',
    contextLabel: selectedIsMyTeam ? '마이팀' : '오늘 경기',
    todayCount: games.length,
    liveCount: liveCount,
    lines: lines,
    secondaryTitle: secondary == null ? '' : _widgetGameTitle(secondary),
    secondaryStatus: secondary == null ? '' : _widgetGameStatusText(secondary),
    secondaryScore: secondary == null ? '' : _widgetGameScoreText(secondary),
  );
}

List<Game> _orderedWidgetGames({
  required List<Game> games,
  required Game? selected,
  required String? myTeamId,
}) {
  final ordered = List<Game>.from(games);
  ordered.sort((a, b) {
    final selectedA = selected != null && a.gameId == selected.gameId ? 0 : 1;
    final selectedB = selected != null && b.gameId == selected.gameId ? 0 : 1;
    if (selectedA != selectedB) {
      return selectedA.compareTo(selectedB);
    }

    final myTeamA = _isMyTeamGame(a, myTeamId) ? 0 : 1;
    final myTeamB = _isMyTeamGame(b, myTeamId) ? 0 : 1;
    if (myTeamA != myTeamB) {
      return myTeamA.compareTo(myTeamB);
    }

    final statusA = _widgetStatusPriority(a);
    final statusB = _widgetStatusPriority(b);
    if (statusA != statusB) {
      return statusA.compareTo(statusB);
    }

    return a.startTime.compareTo(b.startTime);
  });
  return ordered;
}

bool _isMyTeamGame(Game game, String? myTeamId) {
  return myTeamId != null &&
      myTeamId.isNotEmpty &&
      (game.away.teamId == myTeamId || game.home.teamId == myTeamId);
}

int _widgetStatusPriority(Game game) {
  return switch (game.status) {
    GameStatus.live => 0,
    GameStatus.scheduled => game.isPregameLineupOpen ? 1 : 2,
    GameStatus.final_ => 3,
    GameStatus.cancelled => 4,
    GameStatus.suspended => 5,
  };
}

String _widgetGameSummaryLine(Game game) {
  final away = kboShortTeamDisplayName(
    teamId: game.away.teamId,
    teamName: game.away.teamName,
    shortName: game.away.shortName,
  );
  final home = kboShortTeamDisplayName(
    teamId: game.home.teamId,
    teamName: game.home.teamName,
    shortName: game.home.shortName,
  );
  final status = _widgetGameStatusText(game);
  return '$away ${_widgetGameScoreText(game)} $home · $status';
}

String _widgetGameScoreText(Game game) {
  if (game.status == GameStatus.scheduled ||
      game.status == GameStatus.cancelled) {
    return 'vs';
  }
  return '${game.away.score}:${game.home.score}';
}

String _widgetGameStatusText(Game game) {
  if (game.isPregameLineupOpen) {
    return '라인업 공개';
  }
  return secondaryTextForGameStatus(
    game.status,
    inning: game.inning,
    startTime: game.startTime,
    statusLabel: game.statusLabel,
  );
}

List<Future<bool?>> _summarySaveOperations(_WidgetSummary summary) {
  return [
    HomeWidget.saveWidgetData<String>('widget_summary_title', summary.title),
    HomeWidget.saveWidgetData<String>(
      'widget_context_label',
      summary.contextLabel,
    ),
    HomeWidget.saveWidgetData<String>(
      'widget_today_count',
      summary.todayCount.toString(),
    ),
    HomeWidget.saveWidgetData<String>(
      'widget_live_count',
      summary.liveCount.toString(),
    ),
    HomeWidget.saveWidgetData<String>(
      'widget_secondary_title',
      summary.secondaryTitle,
    ),
    HomeWidget.saveWidgetData<String>(
      'widget_secondary_status',
      summary.secondaryStatus,
    ),
    HomeWidget.saveWidgetData<String>(
      'widget_secondary_score',
      summary.secondaryScore,
    ),
    for (var index = 0; index < _maxWidgetSummaryLines; index += 1)
      HomeWidget.saveWidgetData<String>(
        'widget_summary_line_${index + 1}',
        index < summary.lines.length ? summary.lines[index] : '',
      ),
  ];
}

@visibleForTesting
String encodeWidgetMyTeamIdForStorage(String? myTeamId) {
  return myTeamId ?? '';
}

@visibleForTesting
String? decodeWidgetMyTeamIdFromStorage(String? storedMyTeamId) {
  if (storedMyTeamId == null || storedMyTeamId.isEmpty) {
    return null;
  }
  return storedMyTeamId;
}

@visibleForTesting
String buildWidgetGameTitleForTesting(Game game) {
  return _widgetGameTitle(game);
}

@visibleForTesting
String? selectWidgetGameIdForTesting({
  required List<Game> games,
  required String? myTeamId,
}) {
  return WidgetSyncService.instance._selectGame(games, myTeamId)?.gameId;
}

@visibleForTesting
List<String> buildWidgetSummaryLinesForTesting({
  required List<Game> games,
  required String? myTeamId,
}) {
  final selected = WidgetSyncService.instance._selectGame(games, myTeamId);
  return _buildSummary(
    games: games,
    selected: selected,
    myTeamId: myTeamId,
  ).lines;
}
