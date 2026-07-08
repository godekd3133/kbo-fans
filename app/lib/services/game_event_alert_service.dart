import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/utils/team_display.dart';
import '../core/widgets/dev_console.dart';
import '../data/models/boxscore.dart';
import '../data/models/game.dart';
import '../data/models/relay.dart';
import '../data/repositories/game_repository.dart';
import 'push_notification_service.dart';

@pragma('vm:entry-point')
void gameEventNotificationTapBackground(NotificationResponse response) {
  GameEventAlertService.handleNotificationResponse(response);
}

class GameEventAlertService {
  GameEventAlertService._();

  static final GameEventAlertService instance = GameEventAlertService._();
  static const _snapshotKey = 'game_event_alert.snapshots';
  static const _followedGameIdKey = 'live_activity.followed_game_id';
  static const _channelId = 'game_event_alerts';
  static const _channelName = '경기 이벤트 알림';
  static const _channelDescription = '경기 이벤트 로컬 알림';
  static const _scheduledLineupCheckInterval = Duration(minutes: 5);
  static const _liveLineupCheckInterval = Duration(minutes: 20);
  static const _snapshotFreshWindow = Duration(minutes: 10);

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _notificationsAllowed = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      return;
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          gameEventNotificationTapBackground,
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      handleNotificationResponse(launchDetails?.notificationResponse);
    }
    final androidAllowed = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.areNotificationsEnabled();
    final iosAllowed = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.checkPermissions();
    _notificationsAllowed = androidAllowed ?? iosAllowed?.isEnabled ?? false;
    _initialized = true;
  }

  static void handleNotificationResponse(NotificationResponse? response) {
    PushNotificationService.instance.handleNotificationPayload(
      response?.payload,
    );
  }

  Future<bool> requestPermissions() async {
    if (kIsWeb) {
      return false;
    }

    await initialize();
    final androidAllowed = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    final iosAllowed = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    _notificationsAllowed =
        androidAllowed ?? iosAllowed ?? _notificationsAllowed;
    return _notificationsAllowed;
  }

  Future<bool> showDiagnosticNotification() async {
    if (kIsWeb) {
      return false;
    }

    final allowed = await requestPermissions();
    if (!allowed) {
      return false;
    }

    await _showNow(
      title: 'KBO Fans 알림 테스트',
      body: '로컬 알림 경로가 연결되었습니다',
      tag: 'diagnostic:local:${DateTime.now().millisecondsSinceEpoch}',
      payload: '/diagnostics',
    );
    return true;
  }

  Future<void> processGames({
    required List<Game> games,
    required String? myTeamId,
    required GameRepository repository,
  }) async {
    if (!shouldProcessLocalGameEventAlerts(
      isWeb: kIsWeb,
      isLocal: AppConfig.instance.isLocal,
      forceEnabled: AppConfig.instance.enableLocalGameEventAlerts,
    )) {
      return;
    }

    await initialize();
    final settings = await PushNotificationService.instance.loadSettings();
    final settingsSignature = _settingsSignature(settings);
    final prefs = await SharedPreferences.getInstance();
    final snapshots = _readSnapshots(prefs);
    final followedGameIds = _readFollowedGameIds(prefs);
    final trackedGames = selectTrackedGameEventAlertGamesForTesting(
      games: games,
      myTeamId: myTeamId,
      followedGameIds: followedGameIds,
      trackAllGames: settings.allGames,
    );
    final trackedGameIds = trackedGames.map((game) => game.gameId).toSet();
    snapshots.removeWhere((gameId, _) => !trackedGameIds.contains(gameId));
    if (trackedGames.isEmpty) {
      await _writeSnapshots(prefs, snapshots);
      return;
    }

    for (final game in trackedGames) {
      final previous = snapshots[game.gameId];
      final currentObservedAtMs = DateTime.now().millisecondsSinceEpoch;
      final allowNotifications =
          _notificationsAllowed &&
          shouldNotifyFromGameEventSnapshot(
            previousUpdatedAtMs: previous?.updatedAtMs ?? 0,
            currentAtMs: currentObservedAtMs,
            previousSettingsSignature: previous?.settingsSignature ?? '',
            currentSettingsSignature: settingsSignature,
          );
      final previousRelaySeq = previous?.lastRelaySeq ?? 0;
      final nextRelaySeq = await _processRelayEvents(
        repository: repository,
        game: game,
        previous: previous,
        settings: settings,
        myTeamId: myTeamId,
        allowNotifications: allowNotifications,
      );
      final lineupResult = await _processLineupEvents(
        repository: repository,
        game: game,
        previous: previous,
        settings: settings,
        allowNotifications: allowNotifications,
      );

      final current = _GameAlertSnapshot.fromGame(
        game,
        lastRelaySeq: nextRelaySeq ?? previousRelaySeq,
        lineupSignature:
            lineupResult.signature ?? previous?.lineupSignature ?? '',
        lastLineupCheckedAtMs:
            lineupResult.checkedAtMs ?? previous?.lastLineupCheckedAtMs ?? 0,
        updatedAtMs: currentObservedAtMs,
        settingsSignature: settingsSignature,
      );

      if (previous != null && allowNotifications) {
        await _maybeNotifyScoreboardEvents(
          previous: previous,
          current: current,
          settings: settings,
          game: game,
          myTeamId: myTeamId,
        );
      }

      snapshots[game.gameId] = current;
    }

    await _writeSnapshots(prefs, snapshots);
  }

  List<String> _readFollowedGameIds(SharedPreferences prefs) {
    final followedGameId = prefs.getString(_followedGameIdKey)?.trim();
    if (followedGameId == null || followedGameId.isEmpty) {
      return const <String>[];
    }
    return <String>[followedGameId];
  }

  Future<int?> _processRelayEvents({
    required GameRepository repository,
    required Game game,
    required _GameAlertSnapshot? previous,
    required PushNotificationSettings settings,
    required String? myTeamId,
    required bool allowNotifications,
  }) async {
    final notifyHomerun = settings.sendsImmediately(
      PushNotificationMoment.homerun,
    );
    final notifyHit = settings.sendsImmediately(PushNotificationMoment.hit);
    final notifyInningChange = settings.sendsImmediately(
      PushNotificationMoment.inningChange,
    );
    if (!(notifyHomerun || notifyHit || notifyInningChange)) {
      return previous?.lastRelaySeq;
    }
    if (game.status != GameStatus.live) {
      return previous?.lastRelaySeq;
    }

    try {
      final relayData = await repository.getRelayData(
        game.gameId,
        afterSeqNo: previous?.lastRelaySeq == 0 ? null : previous?.lastRelaySeq,
      );
      final relayItems = [...relayData.relayItems]
        ..sort((a, b) => a.seqNo.compareTo(b.seqNo));
      final matchupLabel = _gameEventMatchupLabel(game);

      var maxSeq = previous?.lastRelaySeq ?? 0;
      final shouldNotify = allowNotifications && previous != null && maxSeq > 0;
      for (final item in relayItems) {
        if (item.seqNo > maxSeq) {
          maxSeq = item.seqNo;
        }
        if (!shouldNotify) {
          continue;
        }

        if (notifyHomerun && _isHomerunEvent(item)) {
          await _showNow(
            title: '$matchupLabel 홈런',
            body: buildGameEventRelayAlertBody(
              playText: item.text,
              currentAtBat: relayData.currentAtBat,
            ),
            tag: '${game.gameId}:homerun:${item.seqNo}',
          );
        }

        if (notifyHit && _isHitEvent(item)) {
          await _showNow(
            title: '$matchupLabel 안타',
            body: buildGameEventRelayAlertBody(
              playText: item.text,
              currentAtBat: relayData.currentAtBat,
            ),
            tag: '${game.gameId}:hit:${item.seqNo}',
          );
        }

        if (notifyInningChange && item.event == 'INNING_CHANGE') {
          await _showNow(
            title: '$matchupLabel 이닝 교대',
            body: item.text,
            tag: '${game.gameId}:inning:${item.seqNo}',
          );
        }
      }

      return maxSeq;
    } catch (error) {
      DevConsole.instance.warn('Relay alert processing failed: $error');
      return previous?.lastRelaySeq;
    }
  }

  Future<_LineupCheckResult> _processLineupEvents({
    required GameRepository repository,
    required Game game,
    required _GameAlertSnapshot? previous,
    required PushNotificationSettings settings,
    required bool allowNotifications,
  }) async {
    if (!settings.sendsImmediately(PushNotificationMoment.lineupOpened)) {
      return _LineupCheckResult(
        signature: previous?.lineupSignature,
        checkedAtMs: previous?.lastLineupCheckedAtMs,
      );
    }
    if (game.status == GameStatus.final_ ||
        game.status == GameStatus.cancelled ||
        game.status == GameStatus.suspended) {
      return _LineupCheckResult(
        signature: previous?.lineupSignature,
        checkedAtMs: previous?.lastLineupCheckedAtMs,
      );
    }
    if (!_shouldCheckLineupNow(game: game, previous: previous)) {
      return _LineupCheckResult(
        signature: previous?.lineupSignature,
        checkedAtMs: previous?.lastLineupCheckedAtMs,
      );
    }

    final checkedAtMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final lineup = await repository.getLineupData(game.gameId);
      final signature = _lineupSignature(lineup);
      if (signature.isEmpty) {
        return _LineupCheckResult(
          signature: previous?.lineupSignature ?? '',
          checkedAtMs: checkedAtMs,
        );
      }

      if (allowNotifications &&
          previous != null &&
          previous.lineupSignature != signature) {
        final title = previous.lineupSignature.isEmpty
            ? '선발 라인업 공개'
            : '선발 라인업 변경';
        await _showNow(
          title: title,
          body: '${_gameEventMatchupLabel(game)} 라인업이 업데이트됐습니다.',
          tag: '${game.gameId}:lineup:${signature.hashCode}',
        );
      }

      return _LineupCheckResult(signature: signature, checkedAtMs: checkedAtMs);
    } catch (error) {
      final lastChecked = previous?.lastLineupCheckedAtMs ?? 0;
      final shouldLog =
          checkedAtMs - lastChecked >=
          const Duration(minutes: 1).inMilliseconds;
      if (shouldLog) {
        DevConsole.instance.warn('Lineup alert processing failed: $error');
      }
      return _LineupCheckResult(
        signature: previous?.lineupSignature,
        checkedAtMs: checkedAtMs,
      );
    }
  }

  bool _shouldCheckLineupNow({
    required Game game,
    required _GameAlertSnapshot? previous,
  }) {
    if (game.status == GameStatus.scheduled) {
      return _isLineupCheckDue(
        previous?.lastLineupCheckedAtMs ?? 0,
        _scheduledLineupCheckInterval,
      );
    }

    if (game.status == GameStatus.live) {
      if ((previous?.lineupSignature ?? '').isEmpty) {
        return _isLineupCheckDue(
          previous?.lastLineupCheckedAtMs ?? 0,
          _scheduledLineupCheckInterval,
        );
      }

      return _isLineupCheckDue(
        previous?.lastLineupCheckedAtMs ?? 0,
        _liveLineupCheckInterval,
      );
    }

    return false;
  }

  bool _isLineupCheckDue(int lastCheckedAtMs, Duration interval) {
    if (lastCheckedAtMs <= 0) {
      return true;
    }
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - lastCheckedAtMs;
    return elapsedMs >= interval.inMilliseconds;
  }

  Future<void> _maybeNotifyScoreboardEvents({
    required _GameAlertSnapshot previous,
    required _GameAlertSnapshot current,
    required PushNotificationSettings settings,
    required Game game,
    required String? myTeamId,
  }) async {
    final isMyTeamGame =
        myTeamId != null &&
        myTeamId.isNotEmpty &&
        (game.away.teamId == myTeamId || game.home.teamId == myTeamId);
    final myTeam = isMyTeamGame
        ? (game.away.teamId == myTeamId ? game.away : game.home)
        : null;
    final opponent = isMyTeamGame
        ? (game.away.teamId == myTeamId ? game.home : game.away)
        : null;
    final matchupLabel = _gameEventMatchupLabel(game);
    final myTeamLabel = myTeam == null ? '' : _gameEventTeamLabel(myTeam);
    final opponentLabel = opponent == null ? '' : _gameEventTeamLabel(opponent);

    if (settings.sendsImmediately(PushNotificationMoment.gameStart) &&
        previous.status == GameStatus.scheduled &&
        current.status == GameStatus.live) {
      await _showNow(
        title: isMyTeamGame && myTeam != null
            ? '$myTeamLabel 경기 시작'
            : '$matchupLabel 경기 시작',
        body: isMyTeamGame && opponent != null
            ? _gameEventStartBody(opponentLabel: opponentLabel, game: game)
            : '${game.stadium} 경기 시작',
        tag: '${game.gameId}:start:${current.inning}',
      );
    }

    final awayDelta = current.awayScore - previous.awayScore;
    final homeDelta = current.homeScore - previous.homeScore;
    if (settings.sendsImmediately(PushNotificationMoment.scoring) &&
        (awayDelta > 0 || homeDelta > 0)) {
      if (isMyTeamGame && myTeam != null && opponent != null) {
        final myScoreDelta =
            current.scoreForTeam(myTeam.teamId) -
            previous.scoreForTeam(myTeam.teamId);
        if (myScoreDelta > 0) {
          await _showNow(
            title: '$myTeamLabel $myScoreDelta점 득점',
            body:
                '스코어 ${_gameEventTeamScoreLine(myTeam: myTeam, opponent: opponent, current: current)}',
            tag:
                '${game.gameId}:score:${current.scoreForTeam(myTeam.teamId)}:${current.scoreForTeam(opponent.teamId)}',
          );
        }
      } else {
        final scorer = awayDelta > 0 ? game.away : game.home;
        final delta = awayDelta > 0 ? awayDelta : homeDelta;
        await _showNow(
          title: '${_gameEventTeamLabel(scorer)} $delta점 득점',
          body: '스코어 ${_gameEventScoreLine(game: game, current: current)}',
          tag: '${game.gameId}:score:${current.awayScore}:${current.homeScore}',
        );
      }
    }

    if (settings.sendsImmediately(PushNotificationMoment.reversal)) {
      final previousLeader = previous.leadingTeamId;
      final currentLeader = current.leadingTeamId;
      if (shouldSendGameEventReversal(
        previousLeader: previousLeader,
        currentLeader: currentLeader,
      )) {
        if (isMyTeamGame && myTeam != null && opponent != null) {
          final myLeading = currentLeader == myTeam.teamId;
          await _showNow(
            title: myLeading ? '$myTeamLabel 역전' : '$myTeamLabel 역전 허용',
            body:
                '$opponentLabel전 스코어 ${current.scoreForTeam(myTeam.teamId)}:${current.scoreForTeam(opponent.teamId)}',
            tag:
                '${game.gameId}:reversal:${current.awayScore}:${current.homeScore}',
          );
        } else {
          final leader = currentLeader == game.away.teamId
              ? game.away
              : game.home;
          await _showNow(
            title: '${_gameEventTeamLabel(leader)} 역전',
            body: '스코어 ${_gameEventScoreLine(game: game, current: current)}',
            tag:
                '${game.gameId}:reversal:${current.awayScore}:${current.homeScore}',
          );
        }
      }
    }

    if (settings.sendsImmediately(PushNotificationMoment.gameEnd) &&
        previous.status != GameStatus.final_ &&
        current.status == GameStatus.final_) {
      if (isMyTeamGame && myTeam != null && opponent != null) {
        final myScore = current.scoreForTeam(myTeam.teamId);
        final opponentScore = current.scoreForTeam(opponent.teamId);
        final result = myScore > opponentScore
            ? '승리'
            : myScore < opponentScore
            ? '패배'
            : '무승부';
        await _showNow(
          title: '$myTeamLabel 경기 종료',
          body:
              '$result · ${_gameEventTeamScoreLine(myTeam: myTeam, opponent: opponent, current: current)}',
          tag: '${game.gameId}:end:$myScore:$opponentScore',
        );
      } else {
        await _showNow(
          title: '$matchupLabel 경기 종료',
          body: '최종 ${_gameEventScoreLine(game: game, current: current)}',
          tag: '${game.gameId}:end:${current.awayScore}:${current.homeScore}',
        );
      }
    }
  }

  Future<void> _showNow({
    required String title,
    required String body,
    required String tag,
    String? payload,
  }) async {
    try {
      await _plugin.show(
        tag.hashCode & 0x7fffffff,
        title,
        body,
        NotificationDetails(
          android: const AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: payload ?? _payloadForTag(tag),
      );
    } catch (error) {
      DevConsole.instance.warn('Game event alert failed: $error');
    }
  }

  String? _payloadForTag(String tag) {
    final gameId = tag.split(':').first.trim();
    if (gameId.isEmpty) {
      return null;
    }
    final tab = tag.contains(':lineup:') ? 'lineup' : 'relay';
    return Uri(
      scheme: 'kboFans',
      host: 'game',
      queryParameters: {'gameId': gameId, 'tab': tab},
    ).toString();
  }

  bool _isHomerunEvent(RelayItem item) {
    final event = item.event.toUpperCase();
    if (event.contains('HOMERUN')) {
      return true;
    }
    return item.text.contains('홈런');
  }

  bool _isHitEvent(RelayItem item) {
    if (_isHomerunEvent(item)) {
      return false;
    }
    final event = item.event.toUpperCase();
    if (event == 'HIT') {
      return true;
    }
    return item.text.contains('안타') ||
        item.text.contains('1루타') ||
        item.text.contains('2루타') ||
        item.text.contains('3루타');
  }

  String _lineupSignature(GameLineupData lineup) {
    final away = _teamLineupSignature(lineup.away);
    final home = _teamLineupSignature(lineup.home);
    if (away.isEmpty || home.isEmpty) {
      return '';
    }
    return '$away||$home';
  }

  String _teamLineupSignature(TeamLineupData data) {
    if (data.lineup.isEmpty) {
      return '';
    }
    final starter = data.starterName ?? '';
    final players = data.lineup
        .map((entry) => '${entry.order}:${entry.position}:${entry.name}')
        .join('|');
    return '${data.teamId}#$starter#$players';
  }

  Map<String, _GameAlertSnapshot> _readSnapshots(SharedPreferences prefs) {
    final raw = prefs.getString(_snapshotKey);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(
          key,
          _GameAlertSnapshot.fromJson(value as Map<String, dynamic>),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeSnapshots(
    SharedPreferences prefs,
    Map<String, _GameAlertSnapshot> snapshots,
  ) async {
    if (snapshots.isEmpty) {
      await prefs.remove(_snapshotKey);
      return;
    }
    await prefs.setString(
      _snapshotKey,
      jsonEncode({
        for (final entry in snapshots.entries) entry.key: entry.value.toJson(),
      }),
    );
  }

  String _settingsSignature(PushNotificationSettings settings) {
    return jsonEncode(settings.toJson());
  }
}

String _gameEventTeamLabel(TeamScore team) {
  return buildGameEventTeamLabel(
    teamId: team.teamId,
    teamName: team.teamName,
    shortName: team.shortName,
  );
}

String _gameEventMatchupLabel(Game game) {
  return buildGameEventMatchupLabel(
    awayTeamId: game.away.teamId,
    awayTeamName: game.away.teamName,
    awayShortName: game.away.shortName,
    homeTeamId: game.home.teamId,
    homeTeamName: game.home.teamName,
    homeShortName: game.home.shortName,
  );
}

String _gameEventScoreLine({
  required Game game,
  required _GameAlertSnapshot current,
}) {
  return buildGameEventScoreLine(
    awayTeamId: game.away.teamId,
    awayTeamName: game.away.teamName,
    awayShortName: game.away.shortName,
    awayScore: current.awayScore,
    homeTeamId: game.home.teamId,
    homeTeamName: game.home.teamName,
    homeShortName: game.home.shortName,
    homeScore: current.homeScore,
  );
}

String _gameEventTeamScoreLine({
  required TeamScore myTeam,
  required TeamScore opponent,
  required _GameAlertSnapshot current,
}) {
  return '${_gameEventTeamLabel(myTeam)} ${current.scoreForTeam(myTeam.teamId)}:'
      '${current.scoreForTeam(opponent.teamId)} ${_gameEventTeamLabel(opponent)}';
}

String _gameEventStartBody({
  required String opponentLabel,
  required Game game,
}) {
  final stadium = game.stadium.trim();
  if (stadium.isEmpty) {
    return '$opponentLabel전이 시작됐습니다.';
  }
  return '$opponentLabel전이 시작됐습니다. $stadium';
}

class _GameAlertSnapshot {
  final GameStatus status;
  final String inning;
  final String awayTeamId;
  final String homeTeamId;
  final int awayScore;
  final int homeScore;
  final int lastRelaySeq;
  final String lineupSignature;
  final int lastLineupCheckedAtMs;
  final int updatedAtMs;
  final String settingsSignature;

  const _GameAlertSnapshot({
    required this.status,
    required this.inning,
    required this.awayTeamId,
    required this.homeTeamId,
    required this.awayScore,
    required this.homeScore,
    required this.lastRelaySeq,
    required this.lineupSignature,
    required this.lastLineupCheckedAtMs,
    required this.updatedAtMs,
    required this.settingsSignature,
  });

  factory _GameAlertSnapshot.fromGame(
    Game game, {
    required int lastRelaySeq,
    required String lineupSignature,
    required int lastLineupCheckedAtMs,
    required int updatedAtMs,
    required String settingsSignature,
  }) {
    return _GameAlertSnapshot(
      status: game.status,
      inning: game.inning,
      awayTeamId: game.away.teamId,
      homeTeamId: game.home.teamId,
      awayScore: game.away.score,
      homeScore: game.home.score,
      lastRelaySeq: lastRelaySeq,
      lineupSignature: lineupSignature,
      lastLineupCheckedAtMs: lastLineupCheckedAtMs,
      updatedAtMs: updatedAtMs,
      settingsSignature: settingsSignature,
    );
  }

  factory _GameAlertSnapshot.fromJson(Map<String, dynamic> json) {
    return _GameAlertSnapshot(
      status: GameStatus.values.firstWhere(
        (value) => value.name == (json['status'] as String? ?? ''),
        orElse: () => GameStatus.scheduled,
      ),
      inning: json['inning'] as String? ?? '',
      awayTeamId: json['awayTeamId'] as String? ?? '',
      homeTeamId: json['homeTeamId'] as String? ?? '',
      awayScore: json['awayScore'] as int? ?? 0,
      homeScore: json['homeScore'] as int? ?? 0,
      lastRelaySeq: json['lastRelaySeq'] as int? ?? 0,
      lineupSignature: json['lineupSignature'] as String? ?? '',
      lastLineupCheckedAtMs: json['lastLineupCheckedAtMs'] as int? ?? 0,
      updatedAtMs: json['updatedAtMs'] as int? ?? 0,
      settingsSignature: json['settingsSignature'] as String? ?? '',
    );
  }

  int scoreForTeam(String teamId) {
    if (teamId == awayTeamId) {
      return awayScore;
    }
    if (teamId == homeTeamId) {
      return homeScore;
    }
    return 0;
  }

  String? get leadingTeamId {
    if (awayScore == homeScore) {
      return null;
    }
    return awayScore > homeScore ? awayTeamId : homeTeamId;
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'inning': inning,
      'awayTeamId': awayTeamId,
      'homeTeamId': homeTeamId,
      'awayScore': awayScore,
      'homeScore': homeScore,
      'lastRelaySeq': lastRelaySeq,
      'lineupSignature': lineupSignature,
      'lastLineupCheckedAtMs': lastLineupCheckedAtMs,
      'updatedAtMs': updatedAtMs,
      'settingsSignature': settingsSignature,
    };
  }
}

class _LineupCheckResult {
  final String? signature;
  final int? checkedAtMs;

  const _LineupCheckResult({this.signature, this.checkedAtMs});
}

@visibleForTesting
String buildGameEventTeamLabel({
  required String teamId,
  required String teamName,
  required String shortName,
}) {
  return kboShortTeamDisplayName(
    teamId: teamId,
    teamName: teamName,
    shortName: shortName,
  );
}

@visibleForTesting
String buildGameEventMatchupLabel({
  required String awayTeamId,
  required String awayTeamName,
  required String awayShortName,
  required String homeTeamId,
  required String homeTeamName,
  required String homeShortName,
}) {
  final away = buildGameEventTeamLabel(
    teamId: awayTeamId,
    teamName: awayTeamName,
    shortName: awayShortName,
  );
  final home = buildGameEventTeamLabel(
    teamId: homeTeamId,
    teamName: homeTeamName,
    shortName: homeShortName,
  );
  return '$away vs $home';
}

@visibleForTesting
String buildGameEventScoreLine({
  required String awayTeamId,
  required String awayTeamName,
  required String awayShortName,
  required int awayScore,
  required String homeTeamId,
  required String homeTeamName,
  required String homeShortName,
  required int homeScore,
}) {
  return '${buildGameEventTeamLabel(teamId: awayTeamId, teamName: awayTeamName, shortName: awayShortName)} '
      '$awayScore:$homeScore '
      '${buildGameEventTeamLabel(teamId: homeTeamId, teamName: homeTeamName, shortName: homeShortName)}';
}

@visibleForTesting
bool shouldSendGameEventReversal({
  required String? previousLeader,
  required String? currentLeader,
}) {
  return previousLeader != null &&
      currentLeader != null &&
      previousLeader != currentLeader;
}

@visibleForTesting
String buildGameEventRelayAlertBody({
  required String playText,
  required CurrentAtBat? currentAtBat,
}) {
  final situation = _gameEventSituationText(currentAtBat);
  if (situation.isEmpty) {
    return playText;
  }
  return '$playText · 현재 $situation';
}

String _gameEventSituationText(CurrentAtBat? currentAtBat) {
  if (currentAtBat == null) {
    return '';
  }
  final outs = switch (currentAtBat.outs) {
    0 => '무사',
    1 => '1사',
    2 => '2사',
    _ => '',
  };
  final base = _gameEventBaseStateLabel(currentAtBat.baseState);
  if (outs.isNotEmpty && base.isNotEmpty) {
    return '$outs $base';
  }
  return outs.isNotEmpty ? outs : base;
}

String _gameEventBaseStateLabel(String baseState) {
  final text = baseState.trim();
  if (text.isEmpty) {
    return '';
  }
  if (text == '주자없음') {
    return '주자 없음';
  }
  if (text.startsWith('주자')) {
    return text.substring(2);
  }
  return text;
}

@visibleForTesting
bool shouldProcessLocalGameEventAlerts({
  required bool isWeb,
  required bool isLocal,
  required bool forceEnabled,
}) {
  return !isWeb && (isLocal || forceEnabled);
}

@visibleForTesting
List<Game> selectTrackedGameEventAlertGamesForTesting({
  required List<Game> games,
  required String? myTeamId,
  required Iterable<String> followedGameIds,
  required bool trackAllGames,
}) {
  final normalizedMyTeamId = myTeamId?.trim();
  final followed = {
    for (final gameId in followedGameIds)
      if (gameId.trim().isNotEmpty) gameId.trim(),
  };

  final filtered = games.where((game) {
    if (game.status == GameStatus.cancelled ||
        game.status == GameStatus.suspended) {
      return false;
    }
    if (followed.contains(game.gameId)) {
      return true;
    }
    if (normalizedMyTeamId == null || normalizedMyTeamId.isEmpty) {
      return false;
    }
    return game.away.teamId == normalizedMyTeamId ||
        game.home.teamId == normalizedMyTeamId;
  }).toList();

  filtered.sort((a, b) => a.gameId.compareTo(b.gameId));
  return filtered;
}

@visibleForTesting
bool shouldNotifyFromGameEventSnapshot({
  required int previousUpdatedAtMs,
  required int currentAtMs,
  required String previousSettingsSignature,
  required String currentSettingsSignature,
}) {
  if (previousUpdatedAtMs <= 0 || currentAtMs <= 0) {
    return false;
  }
  if (previousSettingsSignature != currentSettingsSignature) {
    return false;
  }
  final ageMs = currentAtMs - previousUpdatedAtMs;
  return ageMs <= GameEventAlertService._snapshotFreshWindow.inMilliseconds;
}
