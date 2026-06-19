import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/utils/game_status_label.dart';
import '../core/widgets/dev_console.dart';
import '../data/api/api_client.dart';
import '../data/models/game.dart';
import 'push_notification_service.dart';

@pragma('vm:entry-point')
void liveActivityNotificationTapBackground(NotificationResponse response) {
  LiveActivityService.handleAndroidNotificationResponse(response);
}

class LiveActivityService {
  LiveActivityService._();

  static final LiveActivityService instance = LiveActivityService._();
  static const MethodChannel _channel = MethodChannel('kbo_fans/live_activity');
  static const _followedGameIdKey = 'live_activity.followed_game_id';
  static const _activityPushTokenPrefix = 'live_activity.activity_push_token.';
  static const _activityIdPrefix = 'live_activity.activity_id.';
  static const _androidNotificationId = 4420;
  static const _androidChannelId = 'followed_game_live_surface';
  static const _androidChannelName = '경기 따라가기';
  static const _androidChannelDescription = '따라가는 경기의 진행형 스코어 알림';
  static const _androidStopActionId = 'stop_following_game';

  final FlutterLocalNotificationsPlugin _androidNotifications =
      FlutterLocalNotificationsPlugin();
  bool _androidInitialized = false;
  bool _androidNotificationsAllowed = false;
  bool _channelHandlerInitialized = false;

  Future<void> followGame(String gameId) async {
    _ensureChannelHandler();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_followedGameIdKey, gameId);
    unawaited(PushNotificationService.instance.syncRegistration());
  }

  Future<void> stopFollowing() async {
    final prefs = await SharedPreferences.getInstance();
    final gameId = prefs.getString(_followedGameIdKey);
    if (gameId != null && gameId.isNotEmpty) {
      await _unregisterLiveActivity(gameId);
    }
    await prefs.remove(_followedGameIdKey);
    unawaited(PushNotificationService.instance.syncRegistration());
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
    unawaited(_handleAndroidNotificationResponse(response));
  }

  @visibleForTesting
  static Future<void> handleAndroidNotificationResponseForTesting(
    NotificationResponse response,
  ) {
    return _handleAndroidNotificationResponse(response);
  }

  static Future<void> _handleAndroidNotificationResponse(
    NotificationResponse response,
  ) async {
    if (response.actionId != _androidStopActionId) {
      return;
    }
    await instance.stopFollowing();
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
      final autoTarget = selectAutoLiveActivityGame(
        games: games,
        myTeamId: myTeamId,
      );
      if (autoTarget == null) {
        await endCurrentScore();
        return;
      }

      await followGame(autoTarget.gameId);
      DevConsole.instance.info(
        'Live Activity auto-follow my team game: ${autoTarget.gameId}',
      );
      await syncFollowedGame(autoTarget);
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
      _ensureChannelHandler();
      final response = await _channel
          .invokeMapMethod<String, dynamic>('syncCurrentScore', {
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
                    statusLabel: targetGame.statusLabel,
                  ),
            'batter': '',
            'pitcher': '',
            'pitchCount': 0,
            'balls': 0,
            'strikes': 0,
            'outs': 0,
            'stadium': targetGame.stadium,
            'updatedAt': _updatedAtText(),
            'situationText': '',
            'playText': '',
            'apiBaseUrl': AppConfig.instance.apiBaseUrl,
          });
      await _registerLiveActivityFromNativeResponse(response);
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

  void _ensureChannelHandler() {
    if (_channelHandlerInitialized ||
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'liveActivityPushToken') {
        return null;
      }
      final args = Map<String, dynamic>.from(call.arguments as Map);
      await _registerLiveActivityToken(
        gameId: args['gameId']?.toString() ?? '',
        activityId: args['activityId']?.toString(),
        activityPushToken: args['activityPushToken']?.toString() ?? '',
        previousActivityPushToken: args['previousActivityPushToken']
            ?.toString(),
      );
      return true;
    });
    _channelHandlerInitialized = true;
  }

  Future<void> _registerLiveActivityFromNativeResponse(
    Map<String, dynamic>? response,
  ) async {
    if (response == null) {
      return;
    }
    await _registerLiveActivityToken(
      gameId: response['gameId']?.toString() ?? '',
      activityId: response['activityId']?.toString(),
      activityPushToken: response['activityPushToken']?.toString() ?? '',
      previousActivityPushToken: response['previousActivityPushToken']
          ?.toString(),
    );
  }

  Future<void> _registerLiveActivityToken({
    required String gameId,
    required String activityPushToken,
    String? activityId,
    String? previousActivityPushToken,
  }) async {
    if (gameId.isEmpty || activityPushToken.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final previousToken =
        previousActivityPushToken ??
        prefs.getString('$_activityPushTokenPrefix$gameId');

    try {
      await ApiClient().post(
        '/push/live-activity/register',
        data: {
          'gameId': gameId,
          'activityId': activityId,
          'activityPushToken': activityPushToken,
          'previousActivityPushToken': previousToken,
          'platform': 'ios',
        },
      );
      await prefs.setString(
        '$_activityPushTokenPrefix$gameId',
        activityPushToken,
      );
      if (activityId != null && activityId.isNotEmpty) {
        await prefs.setString('$_activityIdPrefix$gameId', activityId);
      }
      DevConsole.instance.info('Live Activity push token registered: $gameId');
    } catch (error) {
      DevConsole.instance.warn(
        'Live Activity push token registration failed: $error',
      );
    }
  }

  Future<void> _unregisterLiveActivity(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('$_activityPushTokenPrefix$gameId');
    final activityId = prefs.getString('$_activityIdPrefix$gameId');
    if ((token == null || token.isEmpty) &&
        (activityId == null || activityId.isEmpty)) {
      return;
    }
    try {
      await ApiClient().post(
        '/push/live-activity/unregister',
        data: {
          'gameId': gameId,
          'activityPushToken': token,
          'activityId': activityId,
        },
      );
    } catch (error) {
      DevConsole.instance.warn('Live Activity unregister failed: $error');
    } finally {
      await prefs.remove('$_activityPushTokenPrefix$gameId');
      await prefs.remove('$_activityIdPrefix$gameId');
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
      statusLabel: targetGame.statusLabel,
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

@visibleForTesting
Game? selectAutoLiveActivityGame({
  required List<Game> games,
  required String? myTeamId,
}) {
  if (myTeamId == null || myTeamId.isEmpty) {
    return null;
  }

  for (final game in games) {
    if (game.status != GameStatus.live) {
      continue;
    }
    if (game.away.teamId == myTeamId || game.home.teamId == myTeamId) {
      return game;
    }
  }
  return null;
}
