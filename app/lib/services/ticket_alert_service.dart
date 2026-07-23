import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../core/utils/kbo_time.dart';
import '../core/utils/team_display.dart';
import '../data/models/game.dart';

class TicketAlertResult {
  final bool scheduled;
  final String message;

  const TicketAlertResult({required this.scheduled, required this.message});
}

class TicketAlertService {
  TicketAlertService._();

  static final TicketAlertService instance = TicketAlertService._();
  static const _prefsKey = 'ticket_alert_game_ids';
  static const _channelId = 'ticket_open_alerts';
  static const _channelName = '예매 오픈 알림';
  static const _channelDescription = '경기 예매 시작 시간 알림';
  static const _reminderOffsets = <Duration>[
    Duration(days: 1),
    Duration(hours: 1),
    Duration(minutes: 10),
  ];

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _notificationsAllowed = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      return;
    }

    tz.initializeTimeZones();
    final timezoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneName));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );

    await _plugin.initialize(settings);
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

    _notificationsAllowed = androidAllowed ?? iosAllowed ?? true;
    _initialized = true;
  }

  Future<bool> isAlertEnabled(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_prefsKey) ?? const <String>[];
    return ids.contains(gameId);
  }

  Future<TicketAlertResult> setAlert({
    required Game game,
    required bool enabled,
  }) async {
    if (kIsWeb) {
      return const TicketAlertResult(
        scheduled: false,
        message: '웹에서는 예약 알림을 지원하지 않습니다.',
      );
    }

    await initialize();
    if (!_notificationsAllowed) {
      return const TicketAlertResult(
        scheduled: false,
        message: '알림 권한이 꺼져 있어 예매 알림을 예약할 수 없습니다.',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final ids = {...(prefs.getStringList(_prefsKey) ?? const <String>[])};
    final ticket = game.ticketInfo;

    if (!enabled) {
      await _cancelScheduledReminders(game.gameId);
      ids.remove(game.gameId);
      await prefs.setStringList(_prefsKey, ids.toList()..sort());
      return const TicketAlertResult(
        scheduled: true,
        message: '예매 알림을 해제했습니다.',
      );
    }

    if (ticket == null || ticket.openAt == null) {
      return const TicketAlertResult(
        scheduled: false,
        message: '예매 오픈 시간이 없어 알림을 예약할 수 없습니다.',
      );
    }

    if (!ticket.openAt!.isAfter(DateTime.now())) {
      return const TicketAlertResult(
        scheduled: false,
        message: '이미 지난 예매 오픈 시간이라 알림을 예약할 수 없습니다.',
      );
    }

    await _cancelScheduledReminders(game.gameId);

    final now = DateTime.now();
    final scheduledLabels = <String>[];
    for (var index = 0; index < _reminderOffsets.length; index++) {
      final offset = _reminderOffsets[index];
      final reminderTime = ticket.openAt!.subtract(offset);
      if (!reminderTime.isAfter(now)) {
        continue;
      }

      await _plugin.zonedSchedule(
        _notificationId(game.gameId, index),
        buildTicketAlertTitle(game),
        '${ticket.vendorName} 예매 ${_relativeLabel(offset)} 전입니다. 오픈 시각 ${formatTicketOpenAt(ticket.openAt!)} KST',
        tz.TZDateTime.from(reminderTime, tz.local),
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
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      scheduledLabels.add(_relativeLabel(offset));
    }

    if (scheduledLabels.isEmpty) {
      return const TicketAlertResult(
        scheduled: false,
        message: '남은 예매 리마인드 시점이 없어 알림을 예약할 수 없습니다.',
      );
    }

    ids.add(game.gameId);
    await prefs.setStringList(_prefsKey, ids.toList()..sort());

    return TicketAlertResult(
      scheduled: true,
      message:
          '${ticket.vendorName} 예매 알림을 ${scheduledLabels.join(', ')} 기준으로 예약했습니다.',
    );
  }

  String exportScheduledAlertsDebug() {
    return jsonEncode({
      'initialized': _initialized,
      'notificationsAllowed': _notificationsAllowed,
    });
  }

  Future<void> _cancelScheduledReminders(String gameId) async {
    for (var index = 0; index < _reminderOffsets.length; index++) {
      await _plugin.cancel(_notificationId(gameId, index));
    }
  }

  int _notificationId(String gameId, int index) {
    var hash = 0x811C9DC5;
    final text = '$gameId#$index';
    for (final codeUnit in text.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  String _relativeLabel(Duration offset) {
    if (offset.inDays == 1) {
      return '하루 전';
    }
    if (offset.inHours == 1) {
      return '1시간 전';
    }
    if (offset.inMinutes == 10) {
      return '10분 전';
    }
    return '${offset.inMinutes}분 전';
  }
}

String formatTicketOpenAt(DateTime value) {
  final kbo = kboCivilDateTime(value);
  final month = kbo.month.toString().padLeft(2, '0');
  final day = kbo.day.toString().padLeft(2, '0');
  final hour = kbo.hour.toString().padLeft(2, '0');
  final minute = kbo.minute.toString().padLeft(2, '0');
  return '$month.$day $hour:$minute';
}

@visibleForTesting
String buildTicketAlertTitle(Game game) {
  return '${_ticketTeamLabel(game.away)} vs ${_ticketTeamLabel(game.home)} 예매 알림';
}

String _ticketTeamLabel(TeamScore team) {
  return kboShortTeamDisplayName(
    teamId: team.teamId,
    teamName: team.teamName,
    shortName: team.shortName,
  );
}
