import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/game_status_label.dart';
import '../core/widgets/dev_console.dart';
import '../data/models/game.dart';

@pragma('vm:entry-point')
void liveActivityNotificationTapBackground(NotificationResponse response) {
  LiveActivityService.handleAndroidNotificationResponse(response);
}

class LiveActivityService {
  LiveActivityService._();

  static final LiveActivityService instance = LiveActivityService._();
  static const MethodChannel _channel = MethodChannel('kbo_fans/live_activity');
  static const _followedGameIdKey = 'live_activity.followed_game_id';
  static const _androidNotificationId = 4420;
  static const _androidChannelId = 'followed_game_live_surface';
  static const _androidChannelName = '경기 따라가기';
  static const _androidChannelDescription = '따라가는 경기의 진행형 스코어 알림';
  static const _androidStopActionId = 'stop_following_game';

  final FlutterLocalNotificationsPlugin _androidNotifications =
      FlutterLocalNotificationsPlugin();
  bool _androidInitialized = false;
  bool _androidNotificationsAllowed = false;

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

  static void handleAndroidNotificationResponse(NotificationResponse response) {
    if (response.actionId != _androidStopActionId) {
      return;
    }
    unawaited(instance.stopFollowing());
  }

  Future<bool> requestPermissions() async {
    if (kIsWeb) {
      return false;
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    return _requestAndroidNotificationPermission();
  }

  Future<void> syncCurrentScore({
    required List<Game> games,
    required String? myTeamId,
  }) async {
    if (!_supportsFollowSurface) {
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
    if (!_supportsFollowSurface) {
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
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _showAndroidOngoingScore(targetGame);
      return;
    }

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
    if (kIsWeb) {
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _cancelAndroidOngoingScore();
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.iOS) {
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

  bool get _supportsFollowSurface {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  Future<void> _ensureAndroidInitialized() async {
    if (_androidInitialized ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _androidNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: handleAndroidNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          liveActivityNotificationTapBackground,
    );
    _androidNotificationsAllowed =
        await _androidNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.areNotificationsEnabled() ??
        true;
    _androidInitialized = true;
  }

  Future<bool> _requestAndroidNotificationPermission() async {
    await _ensureAndroidInitialized();
    final android = _androidNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final requested = await android?.requestNotificationsPermission();
    _androidNotificationsAllowed =
        requested ?? await android?.areNotificationsEnabled() ?? true;
    return _androidNotificationsAllowed;
  }

  Future<void> _showAndroidOngoingScore(Game targetGame) async {
    final allowed = await _requestAndroidNotificationPermission();
    if (!allowed) {
      DevConsole.instance.warn(
        'Android follow notification skipped: permission denied',
      );
      return;
    }

    final title =
        '${targetGame.away.shortName} ${targetGame.away.score} : '
        '${targetGame.home.score} ${targetGame.home.shortName}';
    final statusText = secondaryTextForGameStatus(
      targetGame.status,
      inning: targetGame.inning,
      startTime: targetGame.startTime,
    );
    final updatedAt = _updatedAtText();
    final stadium = targetGame.stadium.isEmpty ? 'KBO' : targetGame.stadium;
    final body = '$statusText · $stadium · 업데이트 $updatedAt';

    try {
      await _androidNotifications.show(
        _androidNotificationId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannelId,
            _androidChannelName,
            channelDescription: _androidChannelDescription,
            importance: Importance.low,
            priority: Priority.low,
            category: AndroidNotificationCategory.service,
            visibility: NotificationVisibility.public,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            showWhen: true,
            when: DateTime.now().millisecondsSinceEpoch,
            playSound: false,
            enableVibration: false,
            channelShowBadge: false,
            silent: true,
            ticker: '경기 따라가기',
            subText: '경기 따라가기',
            actions: const <AndroidNotificationAction>[
              AndroidNotificationAction(
                _androidStopActionId,
                '그만 보기',
                cancelNotification: true,
              ),
            ],
            styleInformation: BigTextStyleInformation(
              body,
              contentTitle: title,
              summaryText: '경기 따라가기',
            ),
          ),
        ),
        payload: Uri(
          scheme: 'kboFans',
          host: 'game',
          queryParameters: {'gameId': targetGame.gameId, 'tab': 'relay'},
        ).toString(),
      );
      DevConsole.instance.info(
        'Android follow notification updated: ${targetGame.gameId}',
      );
    } catch (error) {
      DevConsole.instance.warn('Android follow notification failed: $error');
    }
  }

  Future<void> _cancelAndroidOngoingScore() async {
    try {
      await _ensureAndroidInitialized();
      await _androidNotifications.cancel(_androidNotificationId);
      DevConsole.instance.info('Android follow notification cancelled');
    } catch (error) {
      DevConsole.instance.warn(
        'Android follow notification cancel failed: $error',
      );
    }
  }
}
