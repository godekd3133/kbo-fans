import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/widgets/dev_console.dart';
import '../data/api/api_client.dart';

enum PushNotificationMoment {
  gameStart,
  scoring,
  homerun,
  reversal,
  gameEnd,
  lineupOpened,
  inningChange,
}

enum PushNotificationDelivery { immediate, summary, liveOnly, off }

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

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  DevConsole.instance.info(
    'Push background message: ${message.messageId ?? "-"}',
  );
}

class PushNotificationSettings {
  final bool gameStart;
  final bool scoring;
  final bool homerun;
  final bool reversal;
  final bool gameEnd;
  final bool lineupOpened;
  final bool inningChange;
  final bool allGames;
  final PushNotificationDelivery gameStartDelivery;
  final PushNotificationDelivery scoringDelivery;
  final PushNotificationDelivery homerunDelivery;
  final PushNotificationDelivery reversalDelivery;
  final PushNotificationDelivery gameEndDelivery;
  final PushNotificationDelivery lineupOpenedDelivery;
  final PushNotificationDelivery inningChangeDelivery;

  const PushNotificationSettings({
    required this.gameStart,
    required this.scoring,
    required this.homerun,
    required this.reversal,
    required this.gameEnd,
    required this.lineupOpened,
    required this.inningChange,
    required this.allGames,
    PushNotificationDelivery? gameStartDelivery,
    PushNotificationDelivery? scoringDelivery,
    PushNotificationDelivery? homerunDelivery,
    PushNotificationDelivery? reversalDelivery,
    PushNotificationDelivery? gameEndDelivery,
    PushNotificationDelivery? lineupOpenedDelivery,
    PushNotificationDelivery? inningChangeDelivery,
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
               : PushNotificationDelivery.off);

  const PushNotificationSettings.defaults()
    : gameStart = true,
      scoring = true,
      homerun = true,
      reversal = true,
      gameEnd = true,
      lineupOpened = true,
      inningChange = true,
      allGames = false,
      gameStartDelivery = PushNotificationDelivery.summary,
      scoringDelivery = PushNotificationDelivery.immediate,
      homerunDelivery = PushNotificationDelivery.immediate,
      reversalDelivery = PushNotificationDelivery.immediate,
      gameEndDelivery = PushNotificationDelivery.summary,
      lineupOpenedDelivery = PushNotificationDelivery.summary,
      inningChangeDelivery = PushNotificationDelivery.liveOnly;

  PushNotificationSettings copyWith({
    bool? gameStart,
    bool? scoring,
    bool? homerun,
    bool? reversal,
    bool? gameEnd,
    bool? lineupOpened,
    bool? inningChange,
    bool? allGames,
    PushNotificationDelivery? gameStartDelivery,
    PushNotificationDelivery? scoringDelivery,
    PushNotificationDelivery? homerunDelivery,
    PushNotificationDelivery? reversalDelivery,
    PushNotificationDelivery? gameEndDelivery,
    PushNotificationDelivery? lineupOpenedDelivery,
    PushNotificationDelivery? inningChangeDelivery,
  }) {
    return PushNotificationSettings(
      gameStart: gameStart ?? this.gameStart,
      scoring: scoring ?? this.scoring,
      homerun: homerun ?? this.homerun,
      reversal: reversal ?? this.reversal,
      gameEnd: gameEnd ?? this.gameEnd,
      lineupOpened: lineupOpened ?? this.lineupOpened,
      inningChange: inningChange ?? this.inningChange,
      allGames: allGames ?? this.allGames,
      gameStartDelivery: gameStartDelivery ?? this.gameStartDelivery,
      scoringDelivery: scoringDelivery ?? this.scoringDelivery,
      homerunDelivery: homerunDelivery ?? this.homerunDelivery,
      reversalDelivery: reversalDelivery ?? this.reversalDelivery,
      gameEndDelivery: gameEndDelivery ?? this.gameEndDelivery,
      lineupOpenedDelivery: lineupOpenedDelivery ?? this.lineupOpenedDelivery,
      inningChangeDelivery: inningChangeDelivery ?? this.inningChangeDelivery,
    );
  }

  PushNotificationDelivery deliveryFor(PushNotificationMoment moment) {
    return switch (moment) {
      PushNotificationMoment.gameStart => gameStartDelivery,
      PushNotificationMoment.scoring => scoringDelivery,
      PushNotificationMoment.homerun => homerunDelivery,
      PushNotificationMoment.reversal => reversalDelivery,
      PushNotificationMoment.gameEnd => gameEndDelivery,
      PushNotificationMoment.lineupOpened => lineupOpenedDelivery,
      PushNotificationMoment.inningChange => inningChangeDelivery,
    };
  }

  bool sendsImmediately(PushNotificationMoment moment) {
    return deliveryFor(moment) == PushNotificationDelivery.immediate;
  }

  Map<String, dynamic> toJson() {
    return {
      'gameStart': gameStart,
      'scoring': scoring,
      'homerun': homerun,
      'reversal': reversal,
      'gameEnd': gameEnd,
      'lineupOpened': lineupOpened,
      'inningChange': inningChange,
      'allGames': allGames,
      'deliveryModes': {
        'gameStart': gameStartDelivery.storageValue,
        'scoring': scoringDelivery.storageValue,
        'homerun': homerunDelivery.storageValue,
        'reversal': reversalDelivery.storageValue,
        'gameEnd': gameEndDelivery.storageValue,
        'lineupOpened': lineupOpenedDelivery.storageValue,
        'inningChange': inningChangeDelivery.storageValue,
      },
    };
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static const _prefsPrefix = 'push_notifications.';
  static const _subscribedTopicsKey = '${_prefsPrefix}subscribed_topics';
  static const _platform = 'flutter';
  static const _debugLastInitStatusKey =
      '${_prefsPrefix}debug_last_init_status';
  static const _debugLastInitReasonKey =
      '${_prefsPrefix}debug_last_init_reason';
  static const _channelId = 'remote_push_foreground';
  static const _channelName = '원격 푸시 알림';
  static const _channelDescription = '앱 실행 중 수신한 원격 푸시 알림';
  static const _deliverySuffix = '.delivery';

  bool _initialized = false;
  String? _lastToken;
  bool _notificationsAllowed = false;
  final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize({String? myTeam}) async {
    if (_initialized || kIsWeb) {
      return;
    }

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
      );
      _notificationsAllowed = await _resolveNotificationsAllowed(
        authorizationStatus: notificationSettings.authorizationStatus,
      );
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      messaging.onTokenRefresh.listen((token) {
        _lastToken = token;
        unawaited(syncRegistration(forceToken: token));
      });

      _initialized = true;
      await _saveDebugInitState(status: 'ready', reason: null);
      await syncRegistration(myTeam: myTeam);
    } catch (error) {
      final reason = error.toString();
      await _saveDebugInitState(
        status: AppConfig.instance.isLocal ? 'skipped' : 'failed',
        reason: reason,
      );
      if (AppConfig.instance.isLocal) {
        DevConsole.instance.info('Push init skipped (local): $error');
      } else {
        DevConsole.instance.warn('Push init skipped: $error');
      }
    }
  }

  Future<PushNotificationSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final gameStartKey = '${_prefsPrefix}game_start';
    final scoringKey = '${_prefsPrefix}scoring';
    final homerunKey = '${_prefsPrefix}homerun';
    final reversalKey = '${_prefsPrefix}reversal';
    final gameEndKey = '${_prefsPrefix}game_end';
    final lineupOpenedKey = '${_prefsPrefix}lineup_opened';
    final inningChangeKey = '${_prefsPrefix}inning_change';
    final gameStart = prefs.getBool(gameStartKey) ?? true;
    final scoring = prefs.getBool(scoringKey) ?? true;
    final homerun = prefs.getBool(homerunKey) ?? true;
    final reversal = prefs.getBool(reversalKey) ?? true;
    final gameEnd = prefs.getBool(gameEndKey) ?? true;
    final lineupOpened = prefs.getBool(lineupOpenedKey) ?? true;
    final inningChange = prefs.getBool(inningChangeKey) ?? true;
    return PushNotificationSettings(
      gameStart: gameStart,
      scoring: scoring,
      homerun: homerun,
      reversal: reversal,
      gameEnd: gameEnd,
      lineupOpened: lineupOpened,
      inningChange: inningChange,
      allGames: prefs.getBool('${_prefsPrefix}all_games') ?? false,
      gameStartDelivery: _deliveryFromStorage(
        prefs.getString('${_prefsPrefix}game_start$_deliverySuffix'),
        legacyEnabled: gameStart,
        enabledFallback: PushNotificationDelivery.summary,
      ),
      scoringDelivery: _deliveryFromStorage(
        prefs.getString('${_prefsPrefix}scoring$_deliverySuffix'),
        legacyEnabled: scoring,
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
    );
  }

  Future<void> saveSettings(
    PushNotificationSettings settings, {
    String? myTeam,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_prefsPrefix}game_start', settings.gameStart);
    await prefs.setBool('${_prefsPrefix}scoring', settings.scoring);
    await prefs.setBool('${_prefsPrefix}homerun', settings.homerun);
    await prefs.setBool('${_prefsPrefix}reversal', settings.reversal);
    await prefs.setBool('${_prefsPrefix}game_end', settings.gameEnd);
    await prefs.setBool('${_prefsPrefix}lineup_opened', settings.lineupOpened);
    await prefs.setBool('${_prefsPrefix}inning_change', settings.inningChange);
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
    await syncRegistration(myTeam: myTeam);
  }

  Future<bool> requestPermissionAndSync({String? myTeam}) async {
    if (kIsWeb) {
      return false;
    }
    if (!_initialized) {
      await initialize(myTeam: myTeam);
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
    if (kIsWeb || !_initialized) {
      return;
    }

    try {
      final settings = await loadSettings();
      final resolvedMyTeam = myTeam ?? await _loadStoredMyTeam();
      final token =
          forceToken ??
          _lastToken ??
          await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        DevConsole.instance.warn('Push token unavailable');
        return;
      }

      _lastToken = token;
      final desiredTopics = _buildTopics(settings, resolvedMyTeam);
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
        data: {
          'deviceToken': token,
          'platform': _platform,
          'myTeam': resolvedMyTeam,
          'notifications': settings.toJson(),
        },
      );
      DevConsole.instance.info(
        'Push registration synced (${desiredTopics.length} topics)',
      );
    } catch (error) {
      DevConsole.instance.warn('Push sync failed: $error');
    }
  }

  Future<Map<String, dynamic>> debugState() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'initialized': _initialized,
      'localOnlyMode': false,
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

  Set<String> _buildTopics(PushNotificationSettings settings, String? myTeam) {
    return buildPushTopics(settings: settings, myTeam: myTeam);
  }

  Future<String?> _loadStoredMyTeam() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('myTeam');
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final title = message.notification?.title ?? '푸시 수신';
    final body = message.notification?.body ?? '';
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
}

@visibleForTesting
Set<String> buildPushTopics({
  required PushNotificationSettings settings,
  required String? myTeam,
}) {
  final hasMyTeam = myTeam != null && myTeam.isNotEmpty;
  final topics = <String>{};
  final flags = <String, bool>{
    'game_start': settings.sendsImmediately(PushNotificationMoment.gameStart),
    'scoring': settings.sendsImmediately(PushNotificationMoment.scoring),
    'homerun': settings.sendsImmediately(PushNotificationMoment.homerun),
    'reversal': settings.sendsImmediately(PushNotificationMoment.reversal),
    'game_end': settings.sendsImmediately(PushNotificationMoment.gameEnd),
    'lineup_opened': settings.sendsImmediately(
      PushNotificationMoment.lineupOpened,
    ),
    'inning_change': settings.sendsImmediately(
      PushNotificationMoment.inningChange,
    ),
  };

  flags.forEach((topicName, enabled) {
    if (!enabled) {
      return;
    }
    if (settings.allGames) {
      topics.add('${topicName}_ALL');
      return;
    }
    if (hasMyTeam) {
      topics.add('${topicName}_$myTeam');
    }
  });

  if (settings.allGames) {
    topics.add('all_games_enabled');
  }

  return topics;
}
