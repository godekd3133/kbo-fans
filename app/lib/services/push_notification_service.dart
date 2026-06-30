import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/widgets/dev_console.dart';
import '../data/api/api_client.dart';
import 'notification_inbox_service.dart';

enum PushNotificationMoment {
  gameStart,
  scoring,
  hit,
  homerun,
  reversal,
  gameEnd,
  lineupOpened,
  inningChange,
  atBat,
  baseballInfo,
}

enum PushNotificationDelivery { immediate, summary, liveOnly, off }

enum PushNotificationMode { summary, live, off }

class PushDiagnosticTestResult {
  final bool sent;
  final String message;

  const PushDiagnosticTestResult({required this.sent, required this.message});
}

extension PushNotificationDeliveryX on PushNotificationDelivery {
  String get storageValue => switch (this) {
    PushNotificationDelivery.immediate => 'immediate',
    PushNotificationDelivery.summary => 'summary',
    PushNotificationDelivery.liveOnly => 'live_only',
    PushNotificationDelivery.off => 'off',
  };
}

PushNotificationDelivery _deliveryFromStorage(
  String? value, {
  required bool legacyEnabled,
  PushNotificationDelivery enabledFallback = PushNotificationDelivery.immediate,
}) {
  return switch (value) {
    'immediate' => PushNotificationDelivery.immediate,
    'summary' => PushNotificationDelivery.summary,
    'live_only' => PushNotificationDelivery.liveOnly,
    'off' => PushNotificationDelivery.off,
    _ => legacyEnabled ? enabledFallback : PushNotificationDelivery.off,
  };
}

PushNotificationDelivery _defaultDeliveryForMoment(
  PushNotificationMoment moment,
  PushNotificationMode mode,
) {
  if (mode == PushNotificationMode.off) {
    return PushNotificationDelivery.off;
  }
  if (mode == PushNotificationMode.summary) {
    return switch (moment) {
      PushNotificationMoment.gameStart ||
      PushNotificationMoment.gameEnd ||
      PushNotificationMoment.lineupOpened => PushNotificationDelivery.summary,
      PushNotificationMoment.baseballInfo => PushNotificationDelivery.immediate,
      _ => PushNotificationDelivery.off,
    };
  }
  return switch (moment) {
    PushNotificationMoment.gameEnd ||
    PushNotificationMoment.lineupOpened => PushNotificationDelivery.summary,
    PushNotificationMoment.inningChange => PushNotificationDelivery.liveOnly,
    _ => PushNotificationDelivery.immediate,
  };
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase may already be initialized in a warm background isolate.
  }
  await _recordRemotePush(message, source: 'background', read: false);
  DevConsole.instance.info(
    'Push background message: ${message.messageId ?? "-"}',
  );
}

@pragma('vm:entry-point')
void remotePushNotificationTapBackground(NotificationResponse response) {
  PushNotificationService.instance.handleNotificationPayload(response.payload);
}

Future<void> _recordRemotePush(
  RemoteMessage message, {
  required String source,
  required bool read,
  String? resolvedRoute,
}) async {
  try {
    final data = Map<String, dynamic>.from(message.data);
    final receivedAt = DateTime.now();
    final title =
        message.notification?.title ??
        _pushString(data['title']) ??
        _pushString(data['notificationTitle']) ??
        '푸시 수신';
    final body =
        message.notification?.body ??
        _pushString(data['body']) ??
        _pushString(data['notificationBody']) ??
        '';
    final route = resolvedRoute ?? pushNotificationRouteForData(data) ?? '';
    await NotificationInboxService.instance.addPush(
      messageId: message.messageId,
      title: title,
      body: body,
      data: data,
      route: route,
      source: source,
      read: read,
      receivedAt: receivedAt,
    );
    await _reportRemotePushReceipt(
      message,
      source: source,
      route: route,
      receivedAt: receivedAt,
    );
  } catch (error) {
    DevConsole.instance.warn('Push inbox record skipped: $error');
  }
}

Future<void> _reportRemotePushReceipt(
  RemoteMessage message, {
  required String source,
  required String route,
  required DateTime receivedAt,
}) async {
  if (!shouldUseRemotePushServices(
    isWeb: kIsWeb,
    useBackendApi: AppConfig.instance.shouldUseBackendApi,
  )) {
    return;
  }

  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) {
      return;
    }
    await ApiClient().post(
      '/push/receipt',
      data: buildPushReceiptPayload(
        deviceToken: token,
        messageId: message.messageId,
        source: source,
        route: route,
        receivedAt: receivedAt,
        data: message.data,
      ),
    );
  } catch (error) {
    DevConsole.instance.warn('Push receipt report skipped: $error');
  }
}

class PushNotificationSettings {
  final bool gameStart;
  final bool scoring;
  final bool hit;
  final bool homerun;
  final bool reversal;
  final bool gameEnd;
  final bool lineupOpened;
  final bool inningChange;
  final bool atBat;
  final bool baseballInfo;
  final bool allGames;
  final PushNotificationDelivery gameStartDelivery;
  final PushNotificationDelivery scoringDelivery;
  final PushNotificationDelivery hitDelivery;
  final PushNotificationDelivery homerunDelivery;
  final PushNotificationDelivery reversalDelivery;
  final PushNotificationDelivery gameEndDelivery;
  final PushNotificationDelivery lineupOpenedDelivery;
  final PushNotificationDelivery inningChangeDelivery;
  final PushNotificationDelivery atBatDelivery;
  final PushNotificationDelivery baseballInfoDelivery;

  const PushNotificationSettings({
    required this.gameStart,
    required this.scoring,
    this.hit = true,
    required this.homerun,
    required this.reversal,
    required this.gameEnd,
    required this.lineupOpened,
    required this.inningChange,
    this.atBat = true,
    this.baseballInfo = true,
    required this.allGames,
    PushNotificationDelivery? gameStartDelivery,
    PushNotificationDelivery? scoringDelivery,
    PushNotificationDelivery? hitDelivery,
    PushNotificationDelivery? homerunDelivery,
    PushNotificationDelivery? reversalDelivery,
    PushNotificationDelivery? gameEndDelivery,
    PushNotificationDelivery? lineupOpenedDelivery,
    PushNotificationDelivery? inningChangeDelivery,
    PushNotificationDelivery? atBatDelivery,
    PushNotificationDelivery? baseballInfoDelivery,
  }) : gameStartDelivery =
           gameStartDelivery ??
           (gameStart
               ? PushNotificationDelivery.immediate
               : PushNotificationDelivery.off),
       scoringDelivery =
           scoringDelivery ??
           (scoring
               ? PushNotificationDelivery.immediate
               : PushNotificationDelivery.off),
       hitDelivery =
           hitDelivery ??
           (hit
               ? PushNotificationDelivery.immediate
               : PushNotificationDelivery.off),
       homerunDelivery =
           homerunDelivery ??
           (homerun
               ? PushNotificationDelivery.immediate
               : PushNotificationDelivery.off),
       reversalDelivery =
           reversalDelivery ??
           (reversal
               ? PushNotificationDelivery.immediate
               : PushNotificationDelivery.off),
       gameEndDelivery =
           gameEndDelivery ??
           (gameEnd
               ? PushNotificationDelivery.immediate
               : PushNotificationDelivery.off),
       lineupOpenedDelivery =
           lineupOpenedDelivery ??
           (lineupOpened
               ? PushNotificationDelivery.immediate
               : PushNotificationDelivery.off),
       inningChangeDelivery =
           inningChangeDelivery ??
           (inningChange
               ? PushNotificationDelivery.immediate
               : PushNotificationDelivery.off),
       atBatDelivery =
           atBatDelivery ??
           (atBat
               ? PushNotificationDelivery.immediate
               : PushNotificationDelivery.off),
       baseballInfoDelivery =
           baseballInfoDelivery ??
           (baseballInfo
               ? PushNotificationDelivery.immediate
               : PushNotificationDelivery.off);

  const PushNotificationSettings.defaults()
    : gameStart = true,
      scoring = true,
      hit = true,
      homerun = true,
      reversal = true,
      gameEnd = true,
      lineupOpened = true,
      inningChange = true,
      atBat = true,
      baseballInfo = true,
      allGames = false,
      gameStartDelivery = PushNotificationDelivery.immediate,
      scoringDelivery = PushNotificationDelivery.immediate,
      hitDelivery = PushNotificationDelivery.immediate,
      homerunDelivery = PushNotificationDelivery.immediate,
      reversalDelivery = PushNotificationDelivery.immediate,
      gameEndDelivery = PushNotificationDelivery.summary,
      lineupOpenedDelivery = PushNotificationDelivery.summary,
      inningChangeDelivery = PushNotificationDelivery.liveOnly,
      atBatDelivery = PushNotificationDelivery.immediate,
      baseballInfoDelivery = PushNotificationDelivery.immediate;

  factory PushNotificationSettings.forMode(
    PushNotificationMode mode, {
    bool allGames = false,
  }) {
    return switch (mode) {
      PushNotificationMode.summary => PushNotificationSettings(
        gameStart: true,
        scoring: false,
        hit: false,
        homerun: false,
        reversal: false,
        gameEnd: true,
        lineupOpened: true,
        inningChange: false,
        atBat: false,
        baseballInfo: true,
        allGames: allGames,
        gameStartDelivery: PushNotificationDelivery.summary,
        scoringDelivery: PushNotificationDelivery.off,
        hitDelivery: PushNotificationDelivery.off,
        homerunDelivery: PushNotificationDelivery.off,
        reversalDelivery: PushNotificationDelivery.off,
        gameEndDelivery: PushNotificationDelivery.summary,
        lineupOpenedDelivery: PushNotificationDelivery.summary,
        inningChangeDelivery: PushNotificationDelivery.off,
        atBatDelivery: PushNotificationDelivery.off,
        baseballInfoDelivery: PushNotificationDelivery.immediate,
      ),
      PushNotificationMode.live => PushNotificationSettings(
        gameStart: true,
        scoring: true,
        hit: true,
        homerun: true,
        reversal: true,
        gameEnd: true,
        lineupOpened: true,
        inningChange: true,
        atBat: true,
        baseballInfo: true,
        allGames: allGames,
        gameStartDelivery: PushNotificationDelivery.immediate,
        scoringDelivery: PushNotificationDelivery.immediate,
        hitDelivery: PushNotificationDelivery.immediate,
        homerunDelivery: PushNotificationDelivery.immediate,
        reversalDelivery: PushNotificationDelivery.immediate,
        gameEndDelivery: PushNotificationDelivery.summary,
        lineupOpenedDelivery: PushNotificationDelivery.summary,
        inningChangeDelivery: PushNotificationDelivery.liveOnly,
        atBatDelivery: PushNotificationDelivery.immediate,
        baseballInfoDelivery: PushNotificationDelivery.immediate,
      ),
      PushNotificationMode.off => PushNotificationSettings(
        gameStart: false,
        scoring: false,
        hit: false,
        homerun: false,
        reversal: false,
        gameEnd: false,
        lineupOpened: false,
        inningChange: false,
        atBat: false,
        baseballInfo: false,
        allGames: allGames,
        gameStartDelivery: PushNotificationDelivery.off,
        scoringDelivery: PushNotificationDelivery.off,
        hitDelivery: PushNotificationDelivery.off,
        homerunDelivery: PushNotificationDelivery.off,
        reversalDelivery: PushNotificationDelivery.off,
        gameEndDelivery: PushNotificationDelivery.off,
        lineupOpenedDelivery: PushNotificationDelivery.off,
        inningChangeDelivery: PushNotificationDelivery.off,
        atBatDelivery: PushNotificationDelivery.off,
        baseballInfoDelivery: PushNotificationDelivery.off,
      ),
    };
  }

  PushNotificationSettings copyWith({
    bool? gameStart,
    bool? scoring,
    bool? hit,
    bool? homerun,
    bool? reversal,
    bool? gameEnd,
    bool? lineupOpened,
    bool? inningChange,
    bool? atBat,
    bool? baseballInfo,
    bool? allGames,
    PushNotificationDelivery? gameStartDelivery,
    PushNotificationDelivery? scoringDelivery,
    PushNotificationDelivery? hitDelivery,
    PushNotificationDelivery? homerunDelivery,
    PushNotificationDelivery? reversalDelivery,
    PushNotificationDelivery? gameEndDelivery,
    PushNotificationDelivery? lineupOpenedDelivery,
    PushNotificationDelivery? inningChangeDelivery,
    PushNotificationDelivery? atBatDelivery,
    PushNotificationDelivery? baseballInfoDelivery,
  }) {
    return PushNotificationSettings(
      gameStart: gameStart ?? this.gameStart,
      scoring: scoring ?? this.scoring,
      hit: hit ?? this.hit,
      homerun: homerun ?? this.homerun,
      reversal: reversal ?? this.reversal,
      gameEnd: gameEnd ?? this.gameEnd,
      lineupOpened: lineupOpened ?? this.lineupOpened,
      inningChange: inningChange ?? this.inningChange,
      atBat: atBat ?? this.atBat,
      baseballInfo: baseballInfo ?? this.baseballInfo,
      allGames: allGames ?? this.allGames,
      gameStartDelivery: gameStartDelivery ?? this.gameStartDelivery,
      scoringDelivery: scoringDelivery ?? this.scoringDelivery,
      hitDelivery: hitDelivery ?? this.hitDelivery,
      homerunDelivery: homerunDelivery ?? this.homerunDelivery,
      reversalDelivery: reversalDelivery ?? this.reversalDelivery,
      gameEndDelivery: gameEndDelivery ?? this.gameEndDelivery,
      lineupOpenedDelivery: lineupOpenedDelivery ?? this.lineupOpenedDelivery,
      inningChangeDelivery: inningChangeDelivery ?? this.inningChangeDelivery,
      atBatDelivery: atBatDelivery ?? this.atBatDelivery,
      baseballInfoDelivery: baseballInfoDelivery ?? this.baseballInfoDelivery,
    );
  }

  PushNotificationMode get mode {
    if (!_hasDeliverableMoments) {
      return PushNotificationMode.off;
    }
    if (_hasRealtimeMoments) {
      return PushNotificationMode.live;
    }
    return PushNotificationMode.summary;
  }

  PushNotificationSettings withMode(PushNotificationMode mode) {
    return PushNotificationSettings.forMode(mode, allGames: allGames);
  }

  PushNotificationSettings withMomentEnabled(
    PushNotificationMoment moment,
    bool enabled,
  ) {
    final delivery = enabled
        ? _defaultDeliveryForMoment(moment, mode)
        : PushNotificationDelivery.off;
    return switch (moment) {
      PushNotificationMoment.gameStart => copyWith(
        gameStart: enabled,
        gameStartDelivery: delivery,
      ),
      PushNotificationMoment.scoring => copyWith(
        scoring: enabled,
        scoringDelivery: delivery,
      ),
      PushNotificationMoment.hit => copyWith(
        hit: enabled,
        hitDelivery: delivery,
      ),
      PushNotificationMoment.homerun => copyWith(
        homerun: enabled,
        homerunDelivery: delivery,
      ),
      PushNotificationMoment.reversal => copyWith(
        reversal: enabled,
        reversalDelivery: delivery,
      ),
      PushNotificationMoment.gameEnd => copyWith(
        gameEnd: enabled,
        gameEndDelivery: delivery,
      ),
      PushNotificationMoment.lineupOpened => copyWith(
        lineupOpened: enabled,
        lineupOpenedDelivery: delivery,
      ),
      PushNotificationMoment.inningChange => copyWith(
        inningChange: enabled,
        inningChangeDelivery: delivery,
      ),
      PushNotificationMoment.atBat => copyWith(
        atBat: enabled,
        atBatDelivery: delivery,
      ),
      PushNotificationMoment.baseballInfo => copyWith(
        baseballInfo: enabled,
        baseballInfoDelivery: delivery,
      ),
    };
  }

  bool isMomentEnabled(PushNotificationMoment moment) {
    if (deliveryFor(moment) == PushNotificationDelivery.off) {
      return false;
    }
    return switch (moment) {
      PushNotificationMoment.gameStart => gameStart,
      PushNotificationMoment.scoring => scoring,
      PushNotificationMoment.hit => hit,
      PushNotificationMoment.homerun => homerun,
      PushNotificationMoment.reversal => reversal,
      PushNotificationMoment.gameEnd => gameEnd,
      PushNotificationMoment.lineupOpened => lineupOpened,
      PushNotificationMoment.inningChange => inningChange,
      PushNotificationMoment.atBat => atBat,
      PushNotificationMoment.baseballInfo => baseballInfo,
    };
  }

  bool get _hasDeliverableMoments {
    return PushNotificationMoment.values.any(isMomentEnabled);
  }

  bool get _hasRealtimeMoments {
    return const {
      PushNotificationMoment.scoring,
      PushNotificationMoment.hit,
      PushNotificationMoment.homerun,
      PushNotificationMoment.reversal,
      PushNotificationMoment.inningChange,
      PushNotificationMoment.atBat,
    }.any(isMomentEnabled);
  }

  PushNotificationDelivery deliveryFor(PushNotificationMoment moment) {
    return switch (moment) {
      PushNotificationMoment.gameStart => gameStartDelivery,
      PushNotificationMoment.scoring => scoringDelivery,
      PushNotificationMoment.hit => hitDelivery,
      PushNotificationMoment.homerun => homerunDelivery,
      PushNotificationMoment.reversal => reversalDelivery,
      PushNotificationMoment.gameEnd => gameEndDelivery,
      PushNotificationMoment.lineupOpened => lineupOpenedDelivery,
      PushNotificationMoment.inningChange => inningChangeDelivery,
      PushNotificationMoment.atBat => atBatDelivery,
      PushNotificationMoment.baseballInfo => baseballInfoDelivery,
    };
  }

  bool sendsImmediately(PushNotificationMoment moment) {
    return deliveryFor(moment) == PushNotificationDelivery.immediate;
  }

  bool enablesFollowedGamePush(PushNotificationMoment moment) {
    if (deliveryFor(moment) == PushNotificationDelivery.off) {
      return false;
    }
    return switch (moment) {
      PushNotificationMoment.gameStart => gameStart,
      PushNotificationMoment.scoring => scoring,
      PushNotificationMoment.hit => hit,
      PushNotificationMoment.homerun => homerun,
      PushNotificationMoment.reversal => reversal,
      PushNotificationMoment.gameEnd => gameEnd,
      PushNotificationMoment.lineupOpened => lineupOpened,
      PushNotificationMoment.inningChange => inningChange,
      PushNotificationMoment.atBat => atBat,
      PushNotificationMoment.baseballInfo => baseballInfo,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'gameStart': gameStart,
      'scoring': scoring,
      'hit': hit,
      'homerun': homerun,
      'reversal': reversal,
      'gameEnd': gameEnd,
      'lineupOpened': lineupOpened,
      'inningChange': inningChange,
      'atBat': atBat,
      'baseballInfo': baseballInfo,
      'allGames': allGames,
      'deliveryModes': {
        'gameStart': gameStartDelivery.storageValue,
        'scoring': scoringDelivery.storageValue,
        'hit': hitDelivery.storageValue,
        'homerun': homerunDelivery.storageValue,
        'reversal': reversalDelivery.storageValue,
        'gameEnd': gameEndDelivery.storageValue,
        'lineupOpened': lineupOpenedDelivery.storageValue,
        'inningChange': inningChangeDelivery.storageValue,
        'atBat': atBatDelivery.storageValue,
        'baseballInfo': baseballInfoDelivery.storageValue,
      },
    };
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static const _prefsPrefix = 'push_notifications.';
  static const _subscribedTopicsKey = '${_prefsPrefix}subscribed_topics';
  static const _debugLastInitStatusKey =
      '${_prefsPrefix}debug_last_init_status';
  static const _debugLastInitReasonKey =
      '${_prefsPrefix}debug_last_init_reason';
  static const _autoPermissionRequestedKey =
      '${_prefsPrefix}auto_permission_requested';
  static const _installationIdKey = '${_prefsPrefix}installation_id';
  static const _followedGameIdKey = 'live_activity.followed_game_id';
  static const _channelId = 'remote_push_foreground';
  static const _channelName = '원격 푸시 알림';
  static const _channelDescription = '앱 실행 중 수신한 원격 푸시 알림';
  static const _deliverySuffix = '.delivery';

  bool _initialized = false;
  Future<void>? _initializing;
  bool _notificationOpenHandlersAttached = false;
  String? _lastToken;
  bool _notificationsAllowed = false;
  final StreamController<String> _notificationRouteController =
      StreamController<String>.broadcast();
  final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();

  Stream<String> get notificationRoutes => _notificationRouteController.stream;

  void handleNotificationPayload(String? payload) {
    final route = _routeFromPushValue(payload);
    if (route == null) {
      DevConsole.instance.warn('Notification payload ignored: $payload');
      return;
    }
    _notificationRouteController.add(route);
    DevConsole.instance.info('Notification payload routed: $route');
  }

  Future<void> initialize({String? myTeam}) async {
    if (_initialized || kIsWeb) {
      return;
    }
    if (!_shouldUseRemotePushServices()) {
      await _saveDebugInitState(status: 'skipped', reason: null);
      DevConsole.instance.info('Push init skipped: no remote push endpoint');
      return;
    }
    final pending = _initializing;
    if (pending != null) {
      await pending;
      return;
    }

    final initialization = _initialize(myTeam: myTeam);
    _initializing = initialization;
    try {
      await initialization;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initialize({String? myTeam}) async {
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      final notificationSettings = await messaging.getNotificationSettings();
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      await _localPlugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          handleNotificationPayload(response.payload);
        },
        onDidReceiveBackgroundNotificationResponse:
            remotePushNotificationTapBackground,
      );
      await _ensureAndroidRemotePushChannel();
      _notificationsAllowed = await _resolveNotificationsAllowed(
        authorizationStatus: notificationSettings.authorizationStatus,
      );
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      messaging.onTokenRefresh.listen((token) {
        _lastToken = token;
        unawaited(syncRegistration(forceToken: token));
      });
      await _attachNotificationOpenHandlers(messaging);

      _initialized = true;
      await _saveDebugInitState(status: 'ready', reason: null);
      await syncRegistration(myTeam: myTeam);
    } catch (error) {
      final reason = error.toString();
      final remotePushAvailable = _shouldUseRemotePushServices();
      await _saveDebugInitState(
        status: remotePushAvailable ? 'failed' : 'skipped',
        reason: reason,
      );
      if (!remotePushAvailable) {
        DevConsole.instance.info('Push init skipped (local): $error');
      } else {
        DevConsole.instance.warn('Push init skipped: $error');
      }
    }
  }

  Future<void> ensureAutoPermissionAndSync({String? myTeam}) async {
    if (kIsWeb) {
      return;
    }
    final remotePushAvailable = _shouldUseRemotePushServices();
    if (!remotePushAvailable) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final alreadyRequested =
        prefs.getBool(_autoPermissionRequestedKey) ?? false;
    if (!shouldAutoRequestPushPermission(
      isWeb: kIsWeb,
      remotePushAvailable: remotePushAvailable,
      alreadyRequested: alreadyRequested,
      myTeam: myTeam,
    )) {
      await syncRegistration(myTeam: myTeam);
      return;
    }

    await prefs.setBool(_autoPermissionRequestedKey, true);
    final allowed = await requestPermissionAndSync(myTeam: myTeam);
    DevConsole.instance.info(
      allowed
          ? 'Push auto permission synced'
          : 'Push auto permission not granted',
    );
  }

  Future<PushNotificationSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final gameStartKey = '${_prefsPrefix}game_start';
    final scoringKey = '${_prefsPrefix}scoring';
    final hitKey = '${_prefsPrefix}hit';
    final homerunKey = '${_prefsPrefix}homerun';
    final reversalKey = '${_prefsPrefix}reversal';
    final gameEndKey = '${_prefsPrefix}game_end';
    final lineupOpenedKey = '${_prefsPrefix}lineup_opened';
    final inningChangeKey = '${_prefsPrefix}inning_change';
    final atBatKey = '${_prefsPrefix}at_bat';
    final baseballInfoKey = '${_prefsPrefix}baseball_info';
    final gameStart = prefs.getBool(gameStartKey) ?? true;
    final scoring = prefs.getBool(scoringKey) ?? true;
    final hit = prefs.getBool(hitKey) ?? true;
    final homerun = prefs.getBool(homerunKey) ?? true;
    final reversal = prefs.getBool(reversalKey) ?? true;
    final gameEnd = prefs.getBool(gameEndKey) ?? true;
    final lineupOpened = prefs.getBool(lineupOpenedKey) ?? true;
    final inningChange = prefs.getBool(inningChangeKey) ?? true;
    final atBat = prefs.getBool(atBatKey) ?? true;
    final baseballInfo = prefs.getBool(baseballInfoKey) ?? true;
    return PushNotificationSettings(
      gameStart: gameStart,
      scoring: scoring,
      hit: hit,
      homerun: homerun,
      reversal: reversal,
      gameEnd: gameEnd,
      lineupOpened: lineupOpened,
      inningChange: inningChange,
      atBat: atBat,
      baseballInfo: baseballInfo,
      allGames: prefs.getBool('${_prefsPrefix}all_games') ?? false,
      gameStartDelivery: _deliveryFromStorage(
        prefs.getString('${_prefsPrefix}game_start$_deliverySuffix'),
        legacyEnabled: gameStart,
      ),
      scoringDelivery: _deliveryFromStorage(
        prefs.getString('${_prefsPrefix}scoring$_deliverySuffix'),
        legacyEnabled: scoring,
      ),
      hitDelivery: _deliveryFromStorage(
        prefs.getString('${_prefsPrefix}hit$_deliverySuffix'),
        legacyEnabled: hit,
      ),
      homerunDelivery: _deliveryFromStorage(
        prefs.getString('${_prefsPrefix}homerun$_deliverySuffix'),
        legacyEnabled: homerun,
      ),
      reversalDelivery: _deliveryFromStorage(
        prefs.getString('${_prefsPrefix}reversal$_deliverySuffix'),
        legacyEnabled: reversal,
      ),
      gameEndDelivery: _deliveryFromStorage(
        prefs.getString('${_prefsPrefix}game_end$_deliverySuffix'),
        legacyEnabled: gameEnd,
        enabledFallback: PushNotificationDelivery.summary,
      ),
      lineupOpenedDelivery: _deliveryFromStorage(
        prefs.getString('${_prefsPrefix}lineup_opened$_deliverySuffix'),
        legacyEnabled: lineupOpened,
        enabledFallback: PushNotificationDelivery.summary,
      ),
      inningChangeDelivery: _deliveryFromStorage(
        prefs.getString('${_prefsPrefix}inning_change$_deliverySuffix'),
        legacyEnabled: inningChange,
        enabledFallback: PushNotificationDelivery.liveOnly,
      ),
      atBatDelivery: _deliveryFromStorage(
        prefs.getString('${_prefsPrefix}at_bat$_deliverySuffix'),
        legacyEnabled: atBat,
      ),
      baseballInfoDelivery: _deliveryFromStorage(
        prefs.getString('${_prefsPrefix}baseball_info$_deliverySuffix'),
        legacyEnabled: baseballInfo,
      ),
    );
  }

  Future<String> installationId() {
    return _loadOrCreateInstallationId();
  }

  Future<void> _attachNotificationOpenHandlers(
    FirebaseMessaging messaging,
  ) async {
    if (_notificationOpenHandlersAttached) {
      return;
    }
    _notificationOpenHandlersAttached = true;

    FirebaseMessaging.onMessageOpenedApp.listen(
      _handleOpenedRemoteMessage,
      onError: (Object error) {
        DevConsole.instance.warn('Push open stream failed: $error');
      },
    );

    final initialMessage = await messaging.getInitialMessage();
    _handleOpenedRemoteMessage(initialMessage);
  }

  void _handleOpenedRemoteMessage(RemoteMessage? message) {
    if (message == null) {
      return;
    }
    final route = pushNotificationRouteForData(message.data);
    unawaited(
      _recordRemotePush(
        message,
        source: 'opened',
        read: true,
        resolvedRoute: route,
      ),
    );
    if (route == null) {
      DevConsole.instance.warn(
        'Push open ignored: unsupported data ${message.data.keys.join(',')}',
      );
      return;
    }
    _notificationRouteController.add(route);
    DevConsole.instance.info('Push open routed: $route');
  }

  Future<void> saveSettings(
    PushNotificationSettings settings, {
    String? myTeam,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_prefsPrefix}game_start', settings.gameStart);
    await prefs.setBool('${_prefsPrefix}scoring', settings.scoring);
    await prefs.setBool('${_prefsPrefix}hit', settings.hit);
    await prefs.setBool('${_prefsPrefix}homerun', settings.homerun);
    await prefs.setBool('${_prefsPrefix}reversal', settings.reversal);
    await prefs.setBool('${_prefsPrefix}game_end', settings.gameEnd);
    await prefs.setBool('${_prefsPrefix}lineup_opened', settings.lineupOpened);
    await prefs.setBool('${_prefsPrefix}inning_change', settings.inningChange);
    await prefs.setBool('${_prefsPrefix}at_bat', settings.atBat);
    await prefs.setBool('${_prefsPrefix}baseball_info', settings.baseballInfo);
    await prefs.setBool('${_prefsPrefix}all_games', settings.allGames);
    await prefs.setString(
      '${_prefsPrefix}game_start$_deliverySuffix',
      settings.gameStartDelivery.storageValue,
    );
    await prefs.setString(
      '${_prefsPrefix}scoring$_deliverySuffix',
      settings.scoringDelivery.storageValue,
    );
    await prefs.setString(
      '${_prefsPrefix}hit$_deliverySuffix',
      settings.hitDelivery.storageValue,
    );
    await prefs.setString(
      '${_prefsPrefix}homerun$_deliverySuffix',
      settings.homerunDelivery.storageValue,
    );
    await prefs.setString(
      '${_prefsPrefix}reversal$_deliverySuffix',
      settings.reversalDelivery.storageValue,
    );
    await prefs.setString(
      '${_prefsPrefix}game_end$_deliverySuffix',
      settings.gameEndDelivery.storageValue,
    );
    await prefs.setString(
      '${_prefsPrefix}lineup_opened$_deliverySuffix',
      settings.lineupOpenedDelivery.storageValue,
    );
    await prefs.setString(
      '${_prefsPrefix}inning_change$_deliverySuffix',
      settings.inningChangeDelivery.storageValue,
    );
    await prefs.setString(
      '${_prefsPrefix}at_bat$_deliverySuffix',
      settings.atBatDelivery.storageValue,
    );
    await prefs.setString(
      '${_prefsPrefix}baseball_info$_deliverySuffix',
      settings.baseballInfoDelivery.storageValue,
    );
    await syncRegistration(myTeam: myTeam);
  }

  Future<bool> requestPermissionAndSync({String? myTeam}) async {
    if (kIsWeb || !_shouldUseRemotePushServices()) {
      return false;
    }
    if (!_initialized) {
      await initialize(myTeam: myTeam);
    }
    if (!_initialized) {
      return false;
    }
    try {
      final notificationSettings = await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true);
      _notificationsAllowed = await _resolveNotificationsAllowed(
        authorizationStatus: notificationSettings.authorizationStatus,
      );
      await syncRegistration(myTeam: myTeam);
      return _notificationsAllowed;
    } catch (error) {
      DevConsole.instance.warn('Push permission request failed: $error');
      return false;
    }
  }

  Future<void> syncRegistration({String? myTeam, String? forceToken}) async {
    if (kIsWeb || !_initialized || !_shouldUseRemotePushServices()) {
      return;
    }

    try {
      final settings = await loadSettings();
      final resolvedMyTeam = myTeam ?? await _loadStoredMyTeam();
      final followedGameIds = await _loadFollowedGameIds();
      final installationId = await _loadOrCreateInstallationId();
      final notificationSettings = await FirebaseMessaging.instance
          .getNotificationSettings();
      _notificationsAllowed = await _resolveNotificationsAllowed(
        authorizationStatus: notificationSettings.authorizationStatus,
      );
      final apnsTokenReady = await _waitForAppleApnsTokenIfNeeded();
      final token =
          forceToken ??
          _lastToken ??
          await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        DevConsole.instance.warn('Push token unavailable');
        return;
      }

      _lastToken = token;
      final desiredTopics = _buildTopics(
        settings,
        resolvedMyTeam,
        followedGameIds: followedGameIds,
      );
      final prefs = await SharedPreferences.getInstance();
      final currentTopics =
          (prefs.getStringList(_subscribedTopicsKey) ?? const <String>[])
              .toSet();

      for (final topic in desiredTopics.difference(currentTopics)) {
        await FirebaseMessaging.instance.subscribeToTopic(topic);
      }
      for (final topic in currentTopics.difference(desiredTopics)) {
        await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      }

      await prefs.setStringList(
        _subscribedTopicsKey,
        desiredTopics.toList()..sort(),
      );

      final client = ApiClient();
      await client.post(
        '/push/register',
        data: buildPushRegistrationPayload(
          deviceToken: token,
          platform: _platformName(),
          installationId: installationId,
          myTeam: resolvedMyTeam,
          settings: settings,
          followedGameIds: followedGameIds,
          notificationsAllowed: _notificationsAllowed,
          authorizationStatus: notificationSettings.authorizationStatus.name,
          apnsTokenReady: apnsTokenReady,
        ),
      );
      DevConsole.instance.info(
        'Push registration synced (${desiredTopics.length} topics)',
      );
    } catch (error) {
      DevConsole.instance.warn('Push sync failed: $error');
    }
  }

  Future<PushDiagnosticTestResult> sendRemoteDiagnosticTest({
    String? myTeam,
  }) async {
    if (kIsWeb || !_shouldUseRemotePushServices()) {
      return const PushDiagnosticTestResult(
        sent: false,
        message: '원격 푸시를 사용할 수 없는 실행 모드입니다.',
      );
    }

    if (!_initialized) {
      await initialize(myTeam: myTeam);
    }
    if (!_initialized) {
      return const PushDiagnosticTestResult(
        sent: false,
        message: '푸시 초기화가 완료되지 않았습니다.',
      );
    }

    final allowed = await requestPermissionAndSync(myTeam: myTeam);
    if (!allowed) {
      return const PushDiagnosticTestResult(
        sent: false,
        message: '시스템 알림 권한이 필요합니다.',
      );
    }

    try {
      await _waitForAppleApnsTokenIfNeeded();
      final token = _lastToken ?? await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        return const PushDiagnosticTestResult(
          sent: false,
          message: 'FCM 기기 토큰을 아직 받지 못했습니다.',
        );
      }

      _lastToken = token;
      await syncRegistration(myTeam: myTeam, forceToken: token);
      final response = await ApiClient().post(
        '/push/test-device',
        data: buildPushDeviceTestPayload(deviceToken: token),
      );
      final sent = response['sent'] == true;
      if (sent) {
        return const PushDiagnosticTestResult(
          sent: true,
          message: '원격 테스트 푸시를 요청했습니다.',
        );
      }
      return PushDiagnosticTestResult(
        sent: false,
        message: response['reason']?.toString() ?? '원격 테스트 푸시 요청이 거절됐습니다.',
      );
    } catch (error) {
      DevConsole.instance.warn('Remote push test failed: $error');
      return PushDiagnosticTestResult(
        sent: false,
        message: describeAsyncError(error),
      );
    }
  }

  Future<Map<String, dynamic>> debugState() async {
    final prefs = await SharedPreferences.getInstance();
    final remotePushAvailable = _shouldUseRemotePushServices();
    final localGameEventAlertsEnabled =
        !kIsWeb &&
        (AppConfig.instance.isLocal ||
            AppConfig.instance.enableLocalGameEventAlerts);
    return {
      'initialized': _initialized,
      'localOnlyMode': !remotePushAvailable,
      'remotePushAvailable': remotePushAvailable,
      'environment': AppConfig.instance.environment.name,
      'apiBaseUrl': AppConfig.instance.apiBaseUrl,
      'localGameEventAlertsEnabled': localGameEventAlertsEnabled,
      'localGameEventAlertsForced':
          AppConfig.instance.enableLocalGameEventAlerts,
      'tokenReady': (_lastToken ?? '').isNotEmpty,
      'status':
          prefs.getString(_debugLastInitStatusKey) ??
          (_initialized ? 'ready' : 'idle'),
      'reason': prefs.getString(_debugLastInitReasonKey),
      'topics': prefs.getStringList(_subscribedTopicsKey) ?? const <String>[],
      'settings': (await loadSettings()).toJson(),
      'notificationsAllowed': _notificationsAllowed,
    };
  }

  Set<String> _buildTopics(
    PushNotificationSettings settings,
    String? myTeam, {
    Iterable<String> followedGameIds = const <String>[],
  }) {
    return buildPushTopics(
      settings: settings,
      myTeam: myTeam,
      followedGameIds: followedGameIds,
    );
  }

  Future<String?> _loadStoredMyTeam() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('myTeam');
  }

  Future<List<String>> _loadFollowedGameIds() async {
    final prefs = await SharedPreferences.getInstance();
    final gameId = prefs.getString(_followedGameIdKey);
    if (gameId == null || gameId.isEmpty) {
      return const <String>[];
    }
    return <String>[gameId];
  }

  Future<String> _loadOrCreateInstallationId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_installationIdKey)?.trim();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final random = Random.secure().nextInt(0x7fffffff).toRadixString(36);
    final installationId = 'kbo-$timestamp-$random';
    await prefs.setString(_installationIdKey, installationId);
    return installationId;
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final title = message.notification?.title ?? '푸시 수신';
    final body = message.notification?.body ?? '';
    final route = pushNotificationRouteForData(message.data);
    unawaited(
      _recordRemotePush(
        message,
        source: 'foreground',
        read: false,
        resolvedRoute: route,
      ),
    );
    DevConsole.instance.info(
      'Push foreground: $title ${body.isEmpty ? '' : '· $body'}',
    );
    if (!_notificationsAllowed ||
        message.notification == null ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    unawaited(
      _localPlugin.show(
        (message.messageId ?? '${title}_$body').hashCode & 0x7fffffff,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: route,
      ),
    );
  }

  Future<void> _saveDebugInitState({
    required String status,
    required String? reason,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_debugLastInitStatusKey, status);
    if (reason == null || reason.isEmpty) {
      await prefs.remove(_debugLastInitReasonKey);
    } else {
      await prefs.setString(_debugLastInitReasonKey, reason);
    }
  }

  Future<bool> _resolveNotificationsAllowed({
    required AuthorizationStatus authorizationStatus,
  }) async {
    final authorized =
        authorizationStatus == AuthorizationStatus.authorized ||
        authorizationStatus == AuthorizationStatus.provisional;
    if (!authorized) {
      return false;
    }

    final androidAllowed = await _localPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.areNotificationsEnabled();
    final iosAllowed = await _localPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.checkPermissions();

    return androidAllowed ?? iosAllowed?.isEnabled ?? authorized;
  }

  Future<void> _ensureAndroidRemotePushChannel() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final android = _localPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
  }

  Future<bool?> _waitForAppleApnsTokenIfNeeded() async {
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      return null;
    }

    for (var attempt = 0; attempt < 6; attempt += 1) {
      final token = await FirebaseMessaging.instance.getAPNSToken();
      if (token != null && token.isNotEmpty) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    DevConsole.instance.warn('Push APNs token unavailable before FCM sync');
    return false;
  }

  String _platformName() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      TargetPlatform.macOS => 'macos',
      _ => 'flutter',
    };
  }

  bool _shouldUseRemotePushServices() {
    return shouldUseRemotePushServices(
      isWeb: kIsWeb,
      useBackendApi: AppConfig.instance.shouldUseBackendApi,
    );
  }
}

@visibleForTesting
Map<String, dynamic> buildPushRegistrationPayload({
  required String deviceToken,
  required String platform,
  required String installationId,
  required String? myTeam,
  required PushNotificationSettings settings,
  required Iterable<String> followedGameIds,
  bool notificationsAllowed = false,
  String authorizationStatus = '',
  bool? apnsTokenReady,
}) {
  final followed = <String>{};
  for (final gameId in followedGameIds) {
    final normalized = gameId.trim();
    if (normalized.isNotEmpty) {
      followed.add(normalized);
    }
  }

  final payload = {
    'deviceToken': deviceToken,
    'platform': platform,
    'installationId': installationId.trim(),
    'myTeam': myTeam,
    'notifications': settings.toJson(),
    'followedGameIds': followed.toList()..sort(),
    'notificationsAllowed': notificationsAllowed,
    'authorizationStatus': authorizationStatus,
  };
  if (apnsTokenReady != null) {
    payload['apnsTokenReady'] = apnsTokenReady;
  }
  return payload;
}

@visibleForTesting
Map<String, dynamic> buildPushDeviceTestPayload({required String deviceToken}) {
  return {'deviceToken': deviceToken};
}

@visibleForTesting
Map<String, dynamic> buildPushReceiptPayload({
  required String deviceToken,
  required String? messageId,
  required String source,
  required String route,
  required DateTime receivedAt,
  required Map<String, dynamic> data,
}) {
  final payload = <String, dynamic>{
    'deviceToken': deviceToken,
    'source': source,
    'receivedAt': receivedAt.toUtc().toIso8601String(),
    'data': _pushReceiptData(data),
  };
  final normalizedMessageId = messageId?.trim();
  if (normalizedMessageId != null && normalizedMessageId.isNotEmpty) {
    payload['messageId'] = normalizedMessageId;
  }
  final type = _pushString(data['type']);
  if (type != null) {
    payload['type'] = type;
  }
  final gameId = _pushString(data['gameId']);
  if (gameId != null) {
    payload['gameId'] = gameId;
  }
  if (route.isNotEmpty) {
    payload['route'] = route;
  }
  return payload;
}

Map<String, String> _pushReceiptData(Map<String, dynamic> data) {
  final receiptData = <String, String>{};
  for (final key in const ['topic', 'collapseKey', 'kind']) {
    final value = _pushString(data[key]);
    if (value != null) {
      receiptData[key] = value;
    }
  }
  return receiptData;
}

bool shouldUseRemotePushServices({
  required bool isWeb,
  required bool useBackendApi,
}) {
  if (isWeb) {
    return false;
  }
  return useBackendApi;
}

@visibleForTesting
bool shouldAutoRequestPushPermission({
  required bool isWeb,
  required bool remotePushAvailable,
  required bool alreadyRequested,
  required String? myTeam,
}) {
  return !isWeb &&
      remotePushAvailable &&
      !alreadyRequested &&
      myTeam != null &&
      myTeam.trim().isNotEmpty;
}

@visibleForTesting
Set<String> buildPushTopics({
  required PushNotificationSettings settings,
  required String? myTeam,
  Iterable<String> followedGameIds = const <String>[],
}) {
  final normalizedMyTeam = myTeam?.trim();
  final hasMyTeam = normalizedMyTeam != null && normalizedMyTeam.isNotEmpty;
  final followedGames = _cleanFollowedGameIds(followedGameIds);
  final hasFollowedGames = followedGames.isNotEmpty;
  final topics = <String>{};
  final topicMoments = <String, PushNotificationMoment>{
    'game_start': PushNotificationMoment.gameStart,
    'game_start_soon': PushNotificationMoment.gameStart,
    'scoring': PushNotificationMoment.scoring,
    'hit': PushNotificationMoment.hit,
    'homerun': PushNotificationMoment.homerun,
    'reversal': PushNotificationMoment.reversal,
    'game_end': PushNotificationMoment.gameEnd,
    'lineup_opened': PushNotificationMoment.lineupOpened,
    'inning_change': PushNotificationMoment.inningChange,
    'at_bat': PushNotificationMoment.atBat,
    'baseball_info': PushNotificationMoment.baseballInfo,
  };

  topicMoments.forEach((topicName, moment) {
    final isGameMoment = _gameMomentTopicNames.contains(topicName);

    if (isGameMoment && hasMyTeam && settings.enablesFollowedGamePush(moment)) {
      topics.add('${topicName}_$normalizedMyTeam');
    }

    if (settings.allGames) {
      if (settings.sendsImmediately(moment)) {
        topics.add('${topicName}_ALL');
      }
      return;
    }

    if (isGameMoment) {
      if (!settings.enablesFollowedGamePush(moment)) {
        return;
      }

      if (hasFollowedGames) {
        for (final gameId in followedGames) {
          if (_gameIdContainsTeam(gameId, normalizedMyTeam)) {
            continue;
          }
          topics.add('${topicName}_GAME_$gameId');
        }
      }
      return;
    }

    if (hasMyTeam && settings.sendsImmediately(moment)) {
      topics.add('${topicName}_$normalizedMyTeam');
    }
  });

  if (settings.allGames) {
    topics.add('all_games_enabled');
  }

  return topics;
}

const _gameMomentTopicNames = <String>{
  'game_start',
  'game_start_soon',
  'scoring',
  'hit',
  'homerun',
  'reversal',
  'game_end',
  'lineup_opened',
  'inning_change',
  'at_bat',
};

Set<String> _cleanFollowedGameIds(Iterable<String> followedGameIds) {
  final cleaned = <String>{};
  for (final gameId in followedGameIds) {
    final normalized = gameId.trim();
    if (normalized.isNotEmpty) {
      cleaned.add(normalized);
    }
  }
  return cleaned;
}

bool _gameIdContainsTeam(String gameId, String? teamId) {
  final normalizedTeamId = teamId?.trim();
  if (normalizedTeamId == null ||
      normalizedTeamId.isEmpty ||
      gameId.length < 12) {
    return false;
  }
  return gameId.substring(8, 10) == normalizedTeamId ||
      gameId.substring(10, 12) == normalizedTeamId;
}

String? pushNotificationRouteForData(Map<String, dynamic> data) {
  final explicitRoute = _routeFromPushValue(data['route']);
  if (explicitRoute != null) {
    return explicitRoute;
  }

  final deepLinkRoute =
      _routeFromPushValue(data['deepLink']) ??
      _routeFromPushValue(data['deep_link']) ??
      _routeFromPushValue(data['link']);
  if (deepLinkRoute != null) {
    return deepLinkRoute;
  }

  final type = (_pushString(data['type']) ?? '').toLowerCase();
  if (type == 'baseball_info') {
    return '/home';
  }

  final gameId =
      _pushString(data['gameId']) ??
      _pushString(data['game_id']) ??
      _pushString(data['game']);
  if (gameId == null) {
    return null;
  }

  final explicitTab = _normalizePushTab(_pushString(data['tab']));
  final tab = explicitTab ?? _tabForPushType(type);
  final encodedGameId = Uri.encodeComponent(gameId);
  if (tab == null) {
    return '/game/$encodedGameId';
  }
  return '/game/$encodedGameId?tab=${Uri.encodeQueryComponent(tab)}';
}

String? _routeFromPushValue(Object? value) {
  final raw = _pushString(value);
  if (raw == null) {
    return null;
  }
  final uri = Uri.tryParse(raw);
  if (uri == null) {
    return null;
  }
  if (uri.scheme.toLowerCase() == 'kbofans') {
    return _routeFromKboFansUri(uri);
  }
  if (uri.hasScheme || uri.host.isNotEmpty) {
    return null;
  }
  return _safeInternalRoute(uri.toString());
}

String? _routeFromKboFansUri(Uri uri) {
  if (uri.host == 'game') {
    final gameId = _pushString(uri.queryParameters['gameId']);
    if (gameId == null) {
      return null;
    }
    final tab = _normalizePushTab(uri.queryParameters['tab']);
    final encodedGameId = Uri.encodeComponent(gameId);
    if (tab == null) {
      return '/game/$encodedGameId';
    }
    return '/game/$encodedGameId?tab=${Uri.encodeQueryComponent(tab)}';
  }
  if (uri.host == 'home') {
    return '/home';
  }
  return null;
}

String? _safeInternalRoute(String route) {
  if (route.isEmpty || !route.startsWith('/') || route.startsWith('//')) {
    return null;
  }
  final uri = Uri.tryParse(route);
  if (uri == null || uri.hasScheme || uri.host.isNotEmpty) {
    return null;
  }
  if (uri.path == '/' || uri.path == '/boot' || uri.path == '/onboarding') {
    return '/home';
  }
  return uri.toString();
}

String? _pushString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

String? _normalizePushTab(String? value) {
  return switch ((value ?? '').toLowerCase()) {
    'relay' || 'middle' => 'relay',
    'box' || 'boxscore' => 'boxscore',
    'lineup' => 'lineup',
    _ => null,
  };
}

String? _tabForPushType(String type) {
  return switch (type) {
    'lineup_opened' || 'lineup_changed' || 'lineup' => 'lineup',
    'game_start' ||
    'game_start_soon' ||
    'scoring' ||
    'hit' ||
    'homerun' ||
    'reversal' ||
    'inning_change' ||
    'at_bat' => 'relay',
    _ => null,
  };
}
