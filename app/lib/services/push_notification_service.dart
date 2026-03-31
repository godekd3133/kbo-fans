import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/widgets/dev_console.dart';
import '../data/api/api_client.dart';

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
  final bool allGames;

  const PushNotificationSettings({
    required this.gameStart,
    required this.scoring,
    required this.homerun,
    required this.reversal,
    required this.gameEnd,
    required this.allGames,
  });

  const PushNotificationSettings.defaults()
    : gameStart = true,
      scoring = true,
      homerun = true,
      reversal = true,
      gameEnd = true,
      allGames = false;

  PushNotificationSettings copyWith({
    bool? gameStart,
    bool? scoring,
    bool? homerun,
    bool? reversal,
    bool? gameEnd,
    bool? allGames,
  }) {
    return PushNotificationSettings(
      gameStart: gameStart ?? this.gameStart,
      scoring: scoring ?? this.scoring,
      homerun: homerun ?? this.homerun,
      reversal: reversal ?? this.reversal,
      gameEnd: gameEnd ?? this.gameEnd,
      allGames: allGames ?? this.allGames,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'gameStart': gameStart,
      'scoring': scoring,
      'homerun': homerun,
      'reversal': reversal,
      'gameEnd': gameEnd,
      'allGames': allGames,
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

  bool _initialized = false;
  String? _lastToken;

  Future<void> initialize({String? myTeam}) async {
    if (_initialized || kIsWeb) {
      return;
    }

    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      messaging.onTokenRefresh.listen((token) {
        _lastToken = token;
        unawaited(syncRegistration(myTeam: myTeam, forceToken: token));
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
    return PushNotificationSettings(
      gameStart: prefs.getBool('${_prefsPrefix}game_start') ?? true,
      scoring: prefs.getBool('${_prefsPrefix}scoring') ?? true,
      homerun: prefs.getBool('${_prefsPrefix}homerun') ?? true,
      reversal: prefs.getBool('${_prefsPrefix}reversal') ?? true,
      gameEnd: prefs.getBool('${_prefsPrefix}game_end') ?? true,
      allGames: prefs.getBool('${_prefsPrefix}all_games') ?? false,
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
    await prefs.setBool('${_prefsPrefix}all_games', settings.allGames);
    await syncRegistration(myTeam: myTeam);
  }

  Future<void> syncRegistration({String? myTeam, String? forceToken}) async {
    if (kIsWeb || !_initialized) {
      return;
    }

    try {
      final settings = await loadSettings();
      final token =
          forceToken ??
          _lastToken ??
          await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        DevConsole.instance.warn('Push token unavailable');
        return;
      }

      _lastToken = token;
      final desiredTopics = _buildTopics(settings, myTeam);
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
          'myTeam': myTeam,
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
      'tokenReady': (_lastToken ?? '').isNotEmpty,
      'status':
          prefs.getString(_debugLastInitStatusKey) ??
          (_initialized ? 'ready' : 'idle'),
      'reason': prefs.getString(_debugLastInitReasonKey),
      'topics': prefs.getStringList(_subscribedTopicsKey) ?? const <String>[],
      'settings': (await loadSettings()).toJson(),
    };
  }

  Set<String> _buildTopics(PushNotificationSettings settings, String? myTeam) {
    final teamKey = (myTeam == null || myTeam.isEmpty) ? 'ALL' : myTeam;
    final topics = <String>{};
    final flags = <String, bool>{
      'game_start': settings.gameStart,
      'scoring': settings.scoring,
      'homerun': settings.homerun,
      'reversal': settings.reversal,
      'game_end': settings.gameEnd,
    };

    flags.forEach((topicName, enabled) {
      if (!enabled) {
        return;
      }
      if (settings.allGames) {
        topics.add('${topicName}_ALL');
      } else {
        topics.add('${topicName}_$teamKey');
      }
    });

    if (settings.allGames) {
      topics.add('all_games_enabled');
    }

    return topics;
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final title = message.notification?.title ?? '푸시 수신';
    final body = message.notification?.body ?? '';
    DevConsole.instance.info(
      'Push foreground: $title ${body.isEmpty ? '' : '· $body'}',
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
}
