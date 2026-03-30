import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../data/models/game.dart';

class TicketAlertResult {
  final bool scheduled;
  final String message;

  const TicketAlertResult({
    required this.scheduled,
    required this.message,
  });
}

class TicketAlertService {
  TicketAlertService._();

  static final TicketAlertService instance = TicketAlertService._();
  static const _prefsKey = 'ticket_alert_game_ids';
  static const _channelId = 'ticket_open_alerts';
  static const _channelName = '예매 오픈 알림';
  static const _channelDescription = '경기 예매 시작 시간 알림';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      return;
    }

    tz.initializeTimeZones();
    final timezoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneName));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: darwin, macOS: darwin);

    await _plugin.initialize(settings);
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

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

    final prefs = await SharedPreferences.getInstance();
    final ids = {...(prefs.getStringList(_prefsKey) ?? const <String>[])};
    final ticket = game.ticketInfo;

    if (!enabled) {
      await _plugin.cancel(_notificationId(game.gameId));
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

    await _plugin.zonedSchedule(
      _notificationId(game.gameId),
      '${game.away.shortName} vs ${game.home.shortName} 예매 오픈',
      '${ticket.vendorName}에서 ${_formatDateTime(ticket.openAt!)}부터 예매할 수 있습니다.',
      tz.TZDateTime.from(ticket.openAt!, tz.local),
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

    ids.add(game.gameId);
    await prefs.setStringList(_prefsKey, ids.toList()..sort());

    return TicketAlertResult(
      scheduled: true,
      message: '${ticket.vendorName} 예매 오픈 알림을 예약했습니다.',
    );
  }

  String exportScheduledAlertsDebug() {
    return jsonEncode({'initialized': _initialized});
  }

  int _notificationId(String gameId) {
    return gameId.hashCode & 0x7fffffff;
  }

  String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$month.$day $hour:$minute';
  }
}
