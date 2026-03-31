import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/widgets/dev_console.dart';
import '../data/models/game.dart';
import 'push_notification_service.dart';

class GameEventAlertService {
  GameEventAlertService._();

  static final GameEventAlertService instance = GameEventAlertService._();
  static const _snapshotKey = 'game_event_alert.snapshots';
  static const _channelId = 'game_event_alerts';
  static const _channelName = '경기 이벤트 알림';
  static const _channelDescription = '마이팀 경기 이벤트 로컬 알림';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      return;
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );

    await _plugin.initialize(settings);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    _initialized = true;
  }

  Future<void> processScoreboard({
    required List<Game> games,
    required String? myTeamId,
  }) async {
    if (kIsWeb || myTeamId == null || myTeamId.isEmpty) {
      return;
    }

    await initialize();
    final pushSettings = await PushNotificationService.instance.loadSettings();
    final prefs = await SharedPreferences.getInstance();
    final snapshots = _readSnapshots(prefs);

    for (final game in games) {
      if (!_isMyTeamGame(game, myTeamId)) {
        continue;
      }

      final isAway = game.away.teamId == myTeamId;
      final current = _GameAlertSnapshot.fromGame(game, isAway: isAway);
      final previous = snapshots[game.gameId];

      if (previous != null) {
        await _maybeNotify(
          previous: previous,
          current: current,
          settings: pushSettings,
          game: game,
          myTeamId: myTeamId,
        );
      }

      snapshots[game.gameId] = current;
    }

    await prefs.setString(_snapshotKey, jsonEncode({
      for (final entry in snapshots.entries) entry.key: entry.value.toJson(),
    }));
  }

  Future<void> _maybeNotify({
    required _GameAlertSnapshot previous,
    required _GameAlertSnapshot current,
    required PushNotificationSettings settings,
    required Game game,
    required String myTeamId,
  }) async {
    final myTeam = game.away.teamId == myTeamId ? game.away : game.home;
    final opponent = game.away.teamId == myTeamId ? game.home : game.away;

    if (settings.gameStart &&
        previous.status == GameStatus.scheduled &&
        current.status == GameStatus.live) {
      await _showNow(
        title: '${myTeam.shortName} 경기 시작',
        body: '${opponent.shortName}전이 시작됐습니다. ${game.stadium}',
        tag: '${game.gameId}:start:${current.inning}',
      );
    }

    if (settings.scoring && current.myScore > previous.myScore) {
      final delta = current.myScore - previous.myScore;
      await _showNow(
        title: '${myTeam.shortName} $delta점 득점',
        body: '현재 ${myTeam.shortName} ${current.myScore} : ${current.opponentScore} ${opponent.shortName}',
        tag: '${game.gameId}:score:${current.myScore}:${current.opponentScore}',
      );
    }

    if (settings.reversal) {
      final previousDiff = previous.myScore - previous.opponentScore;
      final currentDiff = current.myScore - current.opponentScore;
      if (previousDiff <= 0 && currentDiff > 0) {
        await _showNow(
          title: '${myTeam.shortName} 역전',
          body: '${opponent.shortName}전에서 경기를 뒤집었습니다. ${current.myScore}:${current.opponentScore}',
          tag: '${game.gameId}:reversal:win:${current.myScore}:${current.opponentScore}',
        );
      } else if (previousDiff >= 0 && currentDiff < 0) {
        await _showNow(
          title: '${myTeam.shortName} 역전 허용',
          body: '${opponent.shortName}에게 리드를 내줬습니다. ${current.myScore}:${current.opponentScore}',
          tag: '${game.gameId}:reversal:lose:${current.myScore}:${current.opponentScore}',
        );
      }
    }

    if (settings.gameEnd &&
        previous.status != GameStatus.final_ &&
        current.status == GameStatus.final_) {
      final result = current.myScore > current.opponentScore
          ? '승리'
          : current.myScore < current.opponentScore
              ? '패배'
              : '무승부';
      await _showNow(
        title: '${myTeam.shortName} 경기 종료',
        body: '$result · ${current.myScore} : ${current.opponentScore} ${opponent.shortName}',
        tag: '${game.gameId}:end:${current.myScore}:${current.opponentScore}',
      );
    }
  }

  Future<void> _showNow({
    required String title,
    required String body,
    required String tag,
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
      );
    } catch (error) {
      DevConsole.instance.warn('Game event alert failed: $error');
    }
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

  bool _isMyTeamGame(Game game, String myTeamId) {
    return game.away.teamId == myTeamId || game.home.teamId == myTeamId;
  }
}

class _GameAlertSnapshot {
  final GameStatus status;
  final String inning;
  final int myScore;
  final int opponentScore;

  const _GameAlertSnapshot({
    required this.status,
    required this.inning,
    required this.myScore,
    required this.opponentScore,
  });

  factory _GameAlertSnapshot.fromGame(Game game, {required bool isAway}) {
    return _GameAlertSnapshot(
      status: game.status,
      inning: game.inning,
      myScore: isAway ? game.away.score : game.home.score,
      opponentScore: isAway ? game.home.score : game.away.score,
    );
  }

  factory _GameAlertSnapshot.fromJson(Map<String, dynamic> json) {
    return _GameAlertSnapshot(
      status: GameStatus.values.firstWhere(
        (value) => value.name == (json['status'] as String? ?? ''),
        orElse: () => GameStatus.scheduled,
      ),
      inning: json['inning'] as String? ?? '',
      myScore: json['myScore'] as int? ?? 0,
      opponentScore: json['opponentScore'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'inning': inning,
      'myScore': myScore,
      'opponentScore': opponentScore,
    };
  }
}
