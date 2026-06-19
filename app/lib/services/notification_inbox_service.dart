import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

class NotificationInboxEntry {
  final String id;
  final String title;
  final String body;
  final String type;
  final String route;
  final String gameId;
  final String teamId;
  final String source;
  final DateTime receivedAt;
  final bool read;

  const NotificationInboxEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.route,
    required this.gameId,
    required this.teamId,
    required this.source,
    required this.receivedAt,
    required this.read,
  });

  bool get hasRoute => route.isNotEmpty;

  NotificationInboxEntry copyWith({
    String? id,
    String? title,
    String? body,
    String? type,
    String? route,
    String? gameId,
    String? teamId,
    String? source,
    DateTime? receivedAt,
    bool? read,
  }) {
    return NotificationInboxEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      route: route ?? this.route,
      gameId: gameId ?? this.gameId,
      teamId: teamId ?? this.teamId,
      source: source ?? this.source,
      receivedAt: receivedAt ?? this.receivedAt,
      read: read ?? this.read,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'type': type,
      'route': route,
      'gameId': gameId,
      'teamId': teamId,
      'source': source,
      'receivedAt': receivedAt.toIso8601String(),
      'read': read,
    };
  }

  static NotificationInboxEntry? fromJson(Map<String, dynamic> json) {
    final id = _stringValue(json['id']);
    final title = _stringValue(json['title']);
    final receivedAt = DateTime.tryParse(_stringValue(json['receivedAt']));
    if (id.isEmpty || title.isEmpty || receivedAt == null) {
      return null;
    }
    return NotificationInboxEntry(
      id: id,
      title: title,
      body: _stringValue(json['body']),
      type: _stringValue(json['type']),
      route: _stringValue(json['route']),
      gameId: _stringValue(json['gameId']),
      teamId: _stringValue(json['teamId']),
      source: _stringValue(json['source']),
      receivedAt: receivedAt,
      read: json['read'] == true,
    );
  }
}

class NotificationInboxService {
  NotificationInboxService._();

  static final NotificationInboxService instance = NotificationInboxService._();

  @visibleForTesting
  static const storageKey = 'push_notifications.inbox_entries_v1';

  static const _maxEntries = 50;

  Future<List<NotificationInboxEntry>> loadEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return const <NotificationInboxEntry>[];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <NotificationInboxEntry>[];
    }
    final entries = <NotificationInboxEntry>[];
    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }
      final entry = NotificationInboxEntry.fromJson(
        item.cast<String, dynamic>(),
      );
      if (entry != null) {
        entries.add(entry);
      }
    }
    entries.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return entries;
  }

  Future<void> addPush({
    required String? messageId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
    required String route,
    required String source,
    required bool read,
    DateTime? receivedAt,
  }) async {
    final now = receivedAt ?? DateTime.now();
    final entry = NotificationInboxEntry(
      id: _entryId(messageId, title, body, data, now),
      title: title.trim().isEmpty ? '푸시 수신' : title.trim(),
      body: body.trim(),
      type: _stringValue(data['type']),
      route: route,
      gameId: _stringValue(data['gameId']).isNotEmpty
          ? _stringValue(data['gameId'])
          : _stringValue(data['game_id']),
      teamId: _stringValue(data['teamId']).isNotEmpty
          ? _stringValue(data['teamId'])
          : _stringValue(data['team_id']),
      source: source,
      receivedAt: now,
      read: read,
    );
    await upsertEntry(entry);
  }

  Future<void> upsertEntry(NotificationInboxEntry entry) async {
    final entries = await loadEntries();
    final merged = <NotificationInboxEntry>[];
    var didReplace = false;
    for (final existing in entries) {
      if (existing.id == entry.id) {
        didReplace = true;
        merged.add(
          entry.copyWith(
            receivedAt: existing.receivedAt.isAfter(entry.receivedAt)
                ? existing.receivedAt
                : entry.receivedAt,
            read: existing.read || entry.read,
          ),
        );
      } else {
        merged.add(existing);
      }
    }
    if (!didReplace) {
      merged.add(entry);
    }
    await _save(merged);
  }

  Future<void> markRead(String id) async {
    final entries = await loadEntries();
    await _save([
      for (final entry in entries)
        entry.id == id ? entry.copyWith(read: true) : entry,
    ]);
  }

  Future<void> markAllRead() async {
    final entries = await loadEntries();
    await _save([for (final entry in entries) entry.copyWith(read: true)]);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }

  Future<void> _save(List<NotificationInboxEntry> entries) async {
    final normalized = entries.toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    final capped = normalized.take(_maxEntries).toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode([for (final entry in capped) entry.toJson()]),
    );
  }
}

String _entryId(
  String? messageId,
  String title,
  String body,
  Map<String, dynamic> data,
  DateTime receivedAt,
) {
  final trimmedMessageId = messageId?.trim();
  if (trimmedMessageId != null && trimmedMessageId.isNotEmpty) {
    return trimmedMessageId;
  }
  final gameId = _stringValue(data['gameId']);
  final type = _stringValue(data['type']);
  if (gameId.isNotEmpty || type.isNotEmpty) {
    return '$type|$gameId|${title.trim()}|${body.trim()}';
  }
  return 'push-${receivedAt.microsecondsSinceEpoch}';
}

String _stringValue(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? '' : text;
}
