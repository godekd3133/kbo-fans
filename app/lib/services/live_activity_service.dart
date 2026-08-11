import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/utils/game_status_label.dart';
import '../core/utils/kbo_time.dart';
import '../core/utils/team_display.dart';
import '../core/widgets/dev_console.dart';
import '../data/api/api_client.dart';
import '../data/models/game.dart';
import '../data/models/relay.dart';
import '../data/models/schedule.dart';
import '../data/repositories/game_repository.dart';
import 'push_notification_service.dart';

const _pregameLiveActivityLeadTime = Duration(minutes: 10);

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
  static const _legacyPendingUnregisterGameIdsKey =
      'live_activity.pending_unregister_game_ids';
  static const _pendingUnregisterRequestsKey =
      'live_activity.pending_unregister_requests';
  static const _maxPendingUnregisterRequests = 32;
  static const _pushToStartTokenKey = 'live_activity.push_to_start_token';
  static const _androidNotificationId = 4420;
  static const _androidChannelId = 'followed_game_live_surface';
  static const _androidChannelName = '라이브 경기 알림';
  static const _androidChannelDescription = '라이브 경기의 진행형 스코어 알림';
  static const _androidStopActionId = 'stop_following_game';

  final FlutterLocalNotificationsPlugin _androidNotifications =
      FlutterLocalNotificationsPlugin();
  bool _androidInitialized = false;
  bool _androidNotificationsAllowed = false;
  bool _channelHandlerInitialized = false;
  bool _retryingPendingUnregisters = false;
  Future<void> _pendingUnregisterMutationQueue = Future<void>.value();
  Future<void> _liveActivityRegistrationQueue = Future<void>.value();
  Future<void> _pushToStartRegistrationQueue = Future<void>.value();

  @visibleForTesting
  Future<void> Function(Map<String, dynamic> request)?
  unregisterRequestSenderForTesting;

  @visibleForTesting
  Future<void> Function(Map<String, dynamic> request)?
  registerRequestSenderForTesting;

  @visibleForTesting
  Future<void> Function(Map<String, dynamic> request)?
  startTokenRegisterRequestSenderForTesting;

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

  Future<void> syncPushToStartToken() async {
    if (defaultTargetPlatform != TargetPlatform.iOS ||
        !shouldUseRemotePushServices(
          isWeb: kIsWeb,
          useBackendApi: AppConfig.instance.shouldUseBackendApi,
        )) {
      return;
    }

    try {
      _ensureChannelHandler();
      unawaited(
        _retryPendingLiveActivityUnregisters().catchError((Object error) {
          DevConsole.instance.warn(
            'Pending Live Activity unregister drain failed: $error',
          );
        }),
      );
      final installationId = await PushNotificationService.instance
          .installationId();
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'syncPushToStartToken',
        <String, dynamic>{
          'apiBaseUrl': AppConfig.instance.apiBaseUrl,
          'installationId': installationId,
        },
      );
      await _registerPushToStartTokenFromNativeResponse(response);
    } on PlatformException {
      DevConsole.instance.warn(
        'Live Activity push-to-start sync failed: platform exception',
      );
    } on MissingPluginException {
      DevConsole.instance.warn(
        'Live Activity push-to-start sync failed: missing plugin',
      );
    }
  }

  Future<void> syncCurrentScore({
    required List<Game> games,
    required String? myTeamId,
    GameRepository? repository,
  }) async {
    if (!_supportsFollowSurface) {
      return;
    }

    final followedId = await followedGameId();
    final myTeamTarget = selectMyTeamLiveActivityGame(
      games: games,
      myTeamId: myTeamId,
    );
    if (myTeamTarget != null && followedId != myTeamTarget.gameId) {
      await followGame(myTeamTarget.gameId);
      DevConsole.instance.info(
        'Live Activity my-team target: ${myTeamTarget.gameId}',
      );
      await syncFollowedGame(myTeamTarget, repository: repository);
      return;
    }

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
        'Live Activity auto-follow target: ${autoTarget.gameId}',
      );
      await syncFollowedGame(autoTarget, repository: repository);
      return;
    }

    final targetGame = _findGame(games, followedId);
    if (targetGame == null) {
      DevConsole.instance.info('Live Activity followed game missing; ending');
      await stopFollowing();
      return;
    }

    await syncFollowedGame(targetGame, repository: repository);
  }

  Future<void> syncFollowedGame(
    Game game, {
    GameRepository? repository,
    CurrentAtBat? currentAtBat,
  }) async {
    if (!_supportsFollowSurface) {
      return;
    }

    final followedId = await followedGameId();
    if (followedId != game.gameId) {
      return;
    }

    if (game.status == GameStatus.final_ ||
        game.status == GameStatus.cancelled) {
      await stopFollowing();
      return;
    }

    if (game.status == GameStatus.suspended) {
      await _syncGame(game);
      return;
    }

    final isPregame = _isLiveActivityPregame(game);
    if (game.status != GameStatus.live && !isPregame) {
      await endCurrentScore();
      return;
    }

    final atBat = game.status == GameStatus.live
        ? currentAtBat ?? await _fetchCurrentAtBat(game, repository)
        : null;
    final rankLabels = isPregame
        ? await _fetchRankLabels(game, repository)
        : const _LiveActivityRankLabels();
    await _syncGame(game, currentAtBat: atBat, rankLabels: rankLabels);
  }

  Future<CurrentAtBat?> _fetchCurrentAtBat(
    Game game,
    GameRepository? repository,
  ) async {
    if (game.status != GameStatus.live || repository == null) {
      return null;
    }

    try {
      return await repository
          .getCurrentAtBat(game.gameId)
          .timeout(const Duration(seconds: 4));
    } catch (error) {
      DevConsole.instance.warn(
        'Live Activity current at-bat fetch skipped: $error',
      );
      return null;
    }
  }

  Future<void> _syncGame(
    Game targetGame, {
    CurrentAtBat? currentAtBat,
    _LiveActivityRankLabels rankLabels = const _LiveActivityRankLabels(),
  }) async {
    if (targetGame.status == GameStatus.live && !targetGame.hasVerifiedScore) {
      DevConsole.instance.warn(
        'Live Activity score update held: '
        '${targetGame.gameId} score unavailable',
      );
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _showAndroidOngoingScore(targetGame, rankLabels: rankLabels);
      return;
    }

    try {
      _ensureChannelHandler();
      final installationId = await PushNotificationService.instance
          .installationId();
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'syncCurrentScore',
        _scorePayloadForGame(
          targetGame,
          currentAtBat: currentAtBat,
          rankLabels: rankLabels,
          updatedAt: _updatedAtText(),
          apiBaseUrl: AppConfig.instance.apiBaseUrl,
          installationId: installationId,
        ),
      );
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

  Map<String, dynamic> _scorePayloadForGame(
    Game targetGame, {
    required String updatedAt,
    required String apiBaseUrl,
    required String installationId,
    CurrentAtBat? currentAtBat,
    _LiveActivityRankLabels rankLabels = const _LiveActivityRankLabels(),
    DateTime? now,
  }) {
    final isTerminal = isTerminalGameStatus(targetGame.status);
    final effectiveAtBat = isTerminal ? null : currentAtBat;
    final isPregame =
        !isTerminal && _isLiveActivityPregame(targetGame, now: now);
    return {
      'gameId': targetGame.gameId,
      'awayTeamId': targetGame.away.teamId,
      'awayTeam': _liveActivityTeamLabel(targetGame.away),
      'homeTeamId': targetGame.home.teamId,
      'homeTeam': _liveActivityTeamLabel(targetGame.home),
      'awayScore': targetGame.away.score,
      'homeScore': targetGame.home.score,
      'scoreAvailable': targetGame.hasVerifiedScore,
      'inning': _inningTextForLiveActivity(
        targetGame,
        effectiveAtBat,
        isPregame: isPregame,
      ),
      'batter': effectiveAtBat?.batterName ?? '',
      'batterAverage': effectiveAtBat?.batterAverage ?? '',
      'pitcher': effectiveAtBat?.pitcherName ?? '',
      'pitcherEra': effectiveAtBat?.pitcherEra ?? '',
      'pitchCount': effectiveAtBat?.pitchCount ?? 0,
      'balls': effectiveAtBat?.balls ?? 0,
      'strikes': effectiveAtBat?.strikes ?? 0,
      'outs': effectiveAtBat?.outs ?? 0,
      'stadium': targetGame.stadium,
      'updatedAt': updatedAt,
      'situationText': _situationText(effectiveAtBat),
      'playText': '',
      'isPregame': isPregame,
      'awayRankText': isPregame ? rankLabels.away : '',
      'homeRankText': isPregame ? rankLabels.home : '',
      'apiBaseUrl': apiBaseUrl,
      'installationId': installationId,
    };
  }

  String _inningTextForLiveActivity(
    Game targetGame,
    CurrentAtBat? currentAtBat, {
    required bool isPregame,
  }) {
    final atBatInning = currentAtBat?.inningText.trim() ?? '';
    if (atBatInning.isNotEmpty) {
      return atBatInning;
    }
    if (isPregame) {
      return '경기전';
    }
    return secondaryTextForGameStatus(
      targetGame.status,
      inning: targetGame.inning,
      startTime: targetGame.startTime,
      statusLabel: targetGame.statusLabel,
    );
  }

  String _situationText(CurrentAtBat? currentAtBat) {
    if (currentAtBat == null) {
      return '';
    }
    final outs = switch (currentAtBat.outs) {
      0 => '무사',
      1 => '1사',
      2 => '2사',
      _ => '',
    };
    final base = _baseStateLabel(currentAtBat.baseState);
    if (outs.isNotEmpty && base.isNotEmpty) {
      return '$outs $base';
    }
    return outs.isNotEmpty ? outs : base;
  }

  String _baseStateLabel(String baseState) {
    final text = baseState.trim();
    if (text.isEmpty) {
      return '';
    }
    if (text == '주자없음') {
      return '주자 없음';
    }
    if (text.startsWith('주자')) {
      return text.substring(2).trim();
    }
    return text;
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
      if (call.method == 'liveActivityPushToken') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        await _registerLiveActivityToken(
          gameId: args['gameId']?.toString() ?? '',
          activityId: args['activityId']?.toString(),
          activityPushToken: args['activityPushToken']?.toString() ?? '',
          previousActivityPushToken: args['previousActivityPushToken']
              ?.toString(),
        );
        return true;
      }
      if (call.method == 'liveActivityPushToStartToken') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        await _registerPushToStartToken(
          pushToStartToken: args['pushToStartToken']?.toString() ?? '',
          previousPushToStartToken: args['previousPushToStartToken']
              ?.toString(),
        );
        return true;
      }
      return null;
    });
    _channelHandlerInitialized = true;
  }

  Future<void> _registerPushToStartTokenFromNativeResponse(
    Map<String, dynamic>? response,
  ) async {
    if (response == null) {
      return;
    }
    await _registerPushToStartToken(
      pushToStartToken: response['pushToStartToken']?.toString() ?? '',
      previousPushToStartToken: response['previousPushToStartToken']
          ?.toString(),
    );
  }

  Future<void> _registerPushToStartToken({
    required String pushToStartToken,
    String? previousPushToStartToken,
  }) {
    final operation = _pushToStartRegistrationQueue.then(
      (_) => _registerPushToStartTokenNow(
        pushToStartToken: pushToStartToken,
        previousPushToStartToken: previousPushToStartToken,
      ),
    );
    _pushToStartRegistrationQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _registerPushToStartTokenNow({
    required String pushToStartToken,
    String? previousPushToStartToken,
  }) async {
    if (pushToStartToken.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final nativePreviousToken = previousPushToStartToken?.trim();
    final previousToken =
        nativePreviousToken != null && nativePreviousToken.isNotEmpty
        ? nativePreviousToken
        : prefs.getString(_pushToStartTokenKey);

    try {
      final request = <String, dynamic>{
        'pushToStartToken': pushToStartToken,
        'previousPushToStartToken': previousToken,
        'installationId': await PushNotificationService.instance
            .installationId(),
        'platform': 'ios',
      };
      final sender = startTokenRegisterRequestSenderForTesting;
      if (sender != null) {
        await sender(request);
      } else {
        await ApiClient().post(
          '/push/live-activity/start-token/register',
          data: request,
        );
      }
      await prefs.setString(_pushToStartTokenKey, pushToStartToken);
      DevConsole.instance.info('Live Activity push-to-start token registered');
    } catch (error) {
      DevConsole.instance.warn(
        'Live Activity push-to-start token registration failed: $error',
      );
    }
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
  }) {
    final operation = _liveActivityRegistrationQueue.then(
      (_) => _registerLiveActivityTokenNow(
        gameId: gameId,
        activityPushToken: activityPushToken,
        activityId: activityId,
        previousActivityPushToken: previousActivityPushToken,
      ),
    );
    _liveActivityRegistrationQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _registerLiveActivityTokenNow({
    required String gameId,
    required String activityPushToken,
    String? activityId,
    String? previousActivityPushToken,
  }) async {
    if (gameId.isEmpty || activityPushToken.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final nativePreviousToken = previousActivityPushToken?.trim();
    final previousToken =
        nativePreviousToken != null && nativePreviousToken.isNotEmpty
        ? nativePreviousToken
        : prefs.getString('$_activityPushTokenPrefix$gameId');

    try {
      final request = <String, dynamic>{
        'gameId': gameId,
        'activityId': activityId,
        'activityPushToken': activityPushToken,
        'previousActivityPushToken': previousToken,
        'installationId': await PushNotificationService.instance
            .installationId(),
        'platform': 'ios',
      };
      final sender = registerRequestSenderForTesting;
      if (sender != null) {
        await sender(request);
      } else {
        await ApiClient().post('/push/live-activity/register', data: request);
      }
      await _enqueuePendingUnregisterMutation(() async {
        await prefs.setString(
          '$_activityPushTokenPrefix$gameId',
          activityPushToken,
        );
        if (activityId != null && activityId.isNotEmpty) {
          await prefs.setString('$_activityIdPrefix$gameId', activityId);
        }
      });
      DevConsole.instance.info('Live Activity push token registered: $gameId');
    } catch (error) {
      DevConsole.instance.warn(
        'Live Activity push token registration failed: $error',
      );
    }
  }

  Future<void> _unregisterLiveActivity(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    final installationId = await PushNotificationService.instance
        .installationId();
    final request = await _snapshotPendingLiveActivityUnregister(
      prefs,
      gameId: gameId,
      installationId: installationId,
    );
    if (request == null) {
      return;
    }
    await _sendPendingLiveActivityUnregister(prefs, request);
  }

  Future<void> _sendPendingLiveActivityUnregister(
    SharedPreferences prefs,
    _PendingLiveActivityUnregisterRequest request,
  ) async {
    try {
      final sender = unregisterRequestSenderForTesting;
      if (sender != null) {
        await sender(request.toJson());
      } else {
        await ApiClient().post(
          '/push/live-activity/unregister',
          data: request.toJson(),
        );
      }
      await _completePendingLiveActivityUnregister(prefs, request);
    } catch (error) {
      DevConsole.instance.warn('Live Activity unregister failed: $error');
    }
  }

  Future<void> _retryPendingLiveActivityUnregisters() async {
    if (_retryingPendingUnregisters) {
      return;
    }
    _retryingPendingUnregisters = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final requests = await _readPendingLiveActivityUnregisters(prefs);
      for (final request in requests) {
        await _sendPendingLiveActivityUnregister(prefs, request);
      }
    } finally {
      _retryingPendingUnregisters = false;
    }
  }

  Future<_PendingLiveActivityUnregisterRequest?>
  _snapshotPendingLiveActivityUnregister(
    SharedPreferences prefs, {
    required String gameId,
    required String installationId,
  }) async {
    _PendingLiveActivityUnregisterRequest? request;
    await _enqueuePendingUnregisterMutation(() async {
      final token = prefs.getString('$_activityPushTokenPrefix$gameId');
      final activityId = prefs.getString('$_activityIdPrefix$gameId');
      if (token == null ||
          token.isEmpty ||
          activityId == null ||
          activityId.isEmpty) {
        return;
      }
      request = _PendingLiveActivityUnregisterRequest(
        gameId: gameId,
        activityPushToken: token,
        activityId: activityId,
        installationId: installationId,
      );
      final pending = _readValidPendingLiveActivityUnregisters(prefs);
      pending.removeWhere((item) => item.identity == request!.identity);
      pending.add(request!);
      await _writePendingLiveActivityUnregisters(
        prefs,
        _boundedPendingLiveActivityUnregisters(pending),
      );
      await prefs.remove(_legacyPendingUnregisterGameIdsKey);
    });
    return request;
  }

  Future<void> _completePendingLiveActivityUnregister(
    SharedPreferences prefs,
    _PendingLiveActivityUnregisterRequest request,
  ) {
    return _enqueuePendingUnregisterMutation(() async {
      final currentToken = prefs.getString(
        '$_activityPushTokenPrefix${request.gameId}',
      );
      final currentActivityId = prefs.getString(
        '$_activityIdPrefix${request.gameId}',
      );
      if (currentToken == request.activityPushToken &&
          currentActivityId == request.activityId) {
        await prefs.remove('$_activityPushTokenPrefix${request.gameId}');
        await prefs.remove('$_activityIdPrefix${request.gameId}');
      }
      final pending = _readValidPendingLiveActivityUnregisters(
        prefs,
      ).where((item) => item.identity != request.identity).toList();
      await _writePendingLiveActivityUnregisters(prefs, pending);
    });
  }

  Future<List<_PendingLiveActivityUnregisterRequest>>
  _readPendingLiveActivityUnregisters(SharedPreferences prefs) async {
    late List<_PendingLiveActivityUnregisterRequest> result;
    await _enqueuePendingUnregisterMutation(() async {
      result = _boundedPendingLiveActivityUnregisters(
        _readValidPendingLiveActivityUnregisters(prefs),
      );
      await _writePendingLiveActivityUnregisters(prefs, result);
      await prefs.remove(_legacyPendingUnregisterGameIdsKey);
    });
    return result;
  }

  List<_PendingLiveActivityUnregisterRequest>
  _readValidPendingLiveActivityUnregisters(SharedPreferences prefs) {
    final raw = prefs.get(_pendingUnregisterRequestsKey);
    if (raw is! List<String>) {
      return <_PendingLiveActivityUnregisterRequest>[];
    }
    final byIdentity = <String, _PendingLiveActivityUnregisterRequest>{};
    for (final encoded in raw.reversed.take(
      _maxPendingUnregisterRequests * 4,
    )) {
      final request = _PendingLiveActivityUnregisterRequest.tryParse(encoded);
      if (request == null || byIdentity.containsKey(request.identity)) {
        continue;
      }
      byIdentity[request.identity] = request;
      if (byIdentity.length == _maxPendingUnregisterRequests) {
        break;
      }
    }
    return byIdentity.values.toList().reversed.toList();
  }

  List<_PendingLiveActivityUnregisterRequest>
  _boundedPendingLiveActivityUnregisters(
    List<_PendingLiveActivityUnregisterRequest> requests,
  ) {
    if (requests.length <= _maxPendingUnregisterRequests) {
      return requests;
    }
    return requests.sublist(requests.length - _maxPendingUnregisterRequests);
  }

  Future<void> _writePendingLiveActivityUnregisters(
    SharedPreferences prefs,
    List<_PendingLiveActivityUnregisterRequest> requests,
  ) async {
    if (requests.isEmpty) {
      await prefs.remove(_pendingUnregisterRequestsKey);
      return;
    }
    await prefs.setStringList(
      _pendingUnregisterRequestsKey,
      requests.map((request) => request.encode()).toList(),
    );
  }

  Future<void> _enqueuePendingUnregisterMutation(
    Future<void> Function() mutation,
  ) {
    final operation = _pendingUnregisterMutationQueue.then((_) => mutation());
    _pendingUnregisterMutationQueue = operation.catchError((Object _) {});
    return operation;
  }

  @visibleForTesting
  Future<void> unregisterLiveActivityForTesting(String gameId) {
    return _unregisterLiveActivity(gameId);
  }

  @visibleForTesting
  Future<void> registerLiveActivityTokenForTesting({
    required String gameId,
    required String activityPushToken,
    String? activityId,
    String? previousActivityPushToken,
  }) {
    return _registerLiveActivityToken(
      gameId: gameId,
      activityPushToken: activityPushToken,
      activityId: activityId,
      previousActivityPushToken: previousActivityPushToken,
    );
  }

  @visibleForTesting
  Future<void> registerPushToStartTokenForTesting({
    required String pushToStartToken,
    String? previousPushToStartToken,
  }) {
    return _registerPushToStartToken(
      pushToStartToken: pushToStartToken,
      previousPushToStartToken: previousPushToStartToken,
    );
  }

  @visibleForTesting
  Future<void> retryPendingLiveActivityUnregistersForTesting() {
    return _retryPendingLiveActivityUnregisters();
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
    return liveActivityUpdatedAtTextForTesting(DateTime.now());
  }

  Future<_LiveActivityRankLabels> _fetchRankLabels(
    Game game,
    GameRepository? repository,
  ) async {
    if (repository == null) {
      return const _LiveActivityRankLabels();
    }
    final season = _seasonFromGameId(game.gameId) ?? kboCurrentSeason();
    try {
      final standings = await repository
          .getStandings(season)
          .timeout(const Duration(seconds: 4));
      return _rankLabelsForGame(game, standings);
    } catch (error) {
      DevConsole.instance.warn(
        'Live Activity standings rank fetch skipped: $error',
      );
      return const _LiveActivityRankLabels();
    }
  }

  int? _seasonFromGameId(String gameId) {
    if (gameId.length < 4) {
      return null;
    }
    return int.tryParse(gameId.substring(0, 4));
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

  Future<void> _showAndroidOngoingScore(
    Game targetGame, {
    _LiveActivityRankLabels rankLabels = const _LiveActivityRankLabels(),
  }) async {
    final allowed = await _requestAndroidNotificationPermission();
    if (!allowed) {
      DevConsole.instance.warn(
        'Android follow notification skipped: permission denied',
      );
      return;
    }

    final title = _androidFollowNotificationTitle(
      targetGame,
      rankLabels: rankLabels,
    );
    final isPregame = _isLiveActivityPregame(targetGame);
    final statusText = isPregame
        ? '경기전'
        : secondaryTextForGameStatus(
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
            ticker: '라이브 경기 알림',
            subText: '라이브 경기 알림',
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
              summaryText: '라이브 경기 알림',
            ),
          ),
        ),
        payload: Uri(
          scheme: 'kboFans',
          host: 'game',
          queryParameters: {
            'gameId': targetGame.gameId,
            'tab': isPregame ? 'lineup' : 'relay',
          },
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

class _PendingLiveActivityUnregisterRequest {
  static const _maxEncodedLength = 4096;
  static const _maxGameIdLength = 32;
  static const _maxActivityPushTokenLength = 512;
  static const _maxActivityIdLength = 128;
  static const _maxInstallationIdLength = 128;

  final String gameId;
  final String activityPushToken;
  final String activityId;
  final String installationId;

  const _PendingLiveActivityUnregisterRequest({
    required this.gameId,
    required this.activityPushToken,
    required this.activityId,
    required this.installationId,
  });

  String get identity => encode();

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'gameId': gameId,
      'activityPushToken': activityPushToken,
      'activityId': activityId,
      'installationId': installationId,
    };
  }

  String encode() => jsonEncode(toJson());

  static _PendingLiveActivityUnregisterRequest? tryParse(String encoded) {
    if (encoded.isEmpty || encoded.length > _maxEncodedLength) {
      return null;
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final payload = decoded;
      final gameId = payload['gameId'];
      final activityPushToken = payload['activityPushToken'];
      final activityId = payload['activityId'];
      final installationId = payload['installationId'];
      if (!_isValidField(gameId, _maxGameIdLength) ||
          !_isValidField(activityPushToken, _maxActivityPushTokenLength) ||
          !_isValidField(activityId, _maxActivityIdLength) ||
          !_isValidField(installationId, _maxInstallationIdLength)) {
        return null;
      }
      return _PendingLiveActivityUnregisterRequest(
        gameId: gameId as String,
        activityPushToken: activityPushToken as String,
        activityId: activityId as String,
        installationId: installationId as String,
      );
    } on FormatException {
      return null;
    }
  }

  static bool _isValidField(Object? value, int maxLength) {
    return value is String && value.isNotEmpty && value.length <= maxLength;
  }
}

@visibleForTesting
String liveActivityUpdatedAtTextForTesting(DateTime instant) {
  final kbo = kboCivilDateTime(instant);
  final hour = kbo.hour.toString().padLeft(2, '0');
  final minute = kbo.minute.toString().padLeft(2, '0');
  final second = kbo.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

class _LiveActivityRankLabels {
  final String away;
  final String home;

  const _LiveActivityRankLabels({this.away = '', this.home = ''});

  String get awayOrDash => away.isEmpty ? '-' : away;
  String get homeOrDash => home.isEmpty ? '-' : home;
}

String _liveActivityTeamLabel(TeamScore team) {
  return kboShortTeamDisplayName(
    teamId: team.teamId,
    teamName: team.teamName,
    shortName: team.shortName,
  );
}

String _androidFollowNotificationTitle(
  Game game, {
  _LiveActivityRankLabels rankLabels = const _LiveActivityRankLabels(),
}) {
  final away = _liveActivityTeamLabel(game.away);
  final home = _liveActivityTeamLabel(game.home);
  if (_isLiveActivityPregame(game)) {
    return '$away ${rankLabels.awayOrDash} · ${rankLabels.homeOrDash} $home';
  }
  return '$away ${game.away.displayScore}:${game.home.displayScore} $home';
}

_LiveActivityRankLabels _rankLabelsForGame(
  Game game,
  List<TeamStanding> standings,
) {
  String rankFor(String teamId) {
    for (final standing in standings) {
      if (standing.teamId == teamId && standing.rank > 0) {
        return '${standing.rank}위';
      }
    }
    return '';
  }

  return _LiveActivityRankLabels(
    away: rankFor(game.away.teamId),
    home: rankFor(game.home.teamId),
  );
}

bool _isLiveActivityPregame(Game game, {DateTime? now}) {
  return game.isPregameLineupOpen ||
      _isWithinPregameLiveActivityWindow(game, now: now);
}

bool _isWithinPregameLiveActivityWindow(Game game, {DateTime? now}) {
  if (game.status != GameStatus.scheduled) {
    return false;
  }
  final startAt = _gameStartDateTimeForLiveActivity(game);
  if (startAt == null) {
    return false;
  }
  final current = now ?? DateTime.now();
  final windowStart = startAt.subtract(_pregameLiveActivityLeadTime);
  return !current.isBefore(windowStart) && !current.isAfter(startAt);
}

DateTime? _gameStartDateTimeForLiveActivity(Game game) {
  final gameId = game.gameId;
  if (gameId.length < 8) {
    return null;
  }
  final year = int.tryParse(gameId.substring(0, 4));
  final month = int.tryParse(gameId.substring(4, 6));
  final day = int.tryParse(gameId.substring(6, 8));
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(game.startTime.trim());
  if (year == null || month == null || day == null || match == null) {
    return null;
  }
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null || minute == null || hour > 23 || minute > 59) {
    return null;
  }
  return kboInstantFromCivil(
    year: year,
    month: month,
    day: day,
    hour: hour,
    minute: minute,
  );
}

@visibleForTesting
Game? selectAutoLiveActivityGame({
  required List<Game> games,
  required String? myTeamId,
  DateTime? now,
}) {
  final myTeamGame = selectMyTeamLiveActivityGame(
    games: games,
    myTeamId: myTeamId,
    now: now,
  );
  if (myTeamGame != null) {
    return myTeamGame;
  }

  final liveOther = _findAutoFollowCandidate(games, status: GameStatus.live);
  if (liveOther != null) {
    return liveOther;
  }

  return _findAutoFollowCandidate(games, requirePregameLineup: true, now: now);
}

@visibleForTesting
Game? selectMyTeamLiveActivityGame({
  required List<Game> games,
  required String? myTeamId,
  DateTime? now,
}) {
  final normalizedMyTeamId = myTeamId?.trim();
  if (normalizedMyTeamId == null || normalizedMyTeamId.isEmpty) {
    return null;
  }

  final liveMyTeam = _findAutoFollowCandidate(
    games,
    myTeamId: normalizedMyTeamId,
    status: GameStatus.live,
  );
  if (liveMyTeam != null) {
    return liveMyTeam;
  }

  return _findAutoFollowCandidate(
    games,
    myTeamId: normalizedMyTeamId,
    requirePregameLineup: true,
    now: now,
  );
}

Game? _findAutoFollowCandidate(
  List<Game> games, {
  String? myTeamId,
  GameStatus? status,
  bool requirePregameLineup = false,
  DateTime? now,
}) {
  for (final game in games) {
    if (status != null && game.status != status) {
      continue;
    }
    if (requirePregameLineup && !_isLiveActivityPregame(game, now: now)) {
      continue;
    }
    if (myTeamId != null &&
        myTeamId.isNotEmpty &&
        game.away.teamId != myTeamId &&
        game.home.teamId != myTeamId) {
      continue;
    }
    return game;
  }
  return null;
}

@visibleForTesting
Map<String, dynamic> buildLiveActivityScorePayloadForTesting({
  required Game game,
  CurrentAtBat? currentAtBat,
  List<TeamStanding> standings = const [],
  String updatedAt = '12:34:56',
  String apiBaseUrl = 'https://api.example.test',
  String installationId = 'install-test',
  DateTime? now,
}) {
  return LiveActivityService.instance._scorePayloadForGame(
    game,
    currentAtBat: currentAtBat,
    rankLabels: _rankLabelsForGame(game, standings),
    updatedAt: updatedAt,
    apiBaseUrl: apiBaseUrl,
    installationId: installationId,
    now: now,
  );
}

@visibleForTesting
String buildAndroidFollowNotificationTitleForTesting({
  required Game game,
  List<TeamStanding> standings = const [],
}) {
  return _androidFollowNotificationTitle(
    game,
    rankLabels: _rankLabelsForGame(game, standings),
  );
}
