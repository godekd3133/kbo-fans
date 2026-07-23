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

  static const _entryKeyPrefix = 'push_notifications.inbox_entry_v2.';
  static const _readKeyPrefix = 'push_notifications.inbox_read_v2.';
  static const _maxEntries = 50;

  Future<List<NotificationInboxEntry>> loadEntries() async {
    final prefs = SharedPreferencesAsync();
    await _migrateLegacyEntries(prefs);
    return _loadEntries(prefs);
  }

  Future<List<NotificationInboxEntry>> _loadEntries(
    SharedPreferencesAsync prefs,
  ) async {
    final stored = await prefs.getAll();
    final entries = <NotificationInboxEntry>[];
    for (final storedEntry in stored.entries) {
      if (!storedEntry.key.startsWith(_entryKeyPrefix) ||
          storedEntry.value is! String) {
        continue;
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(storedEntry.value! as String);
      } catch (_) {
        continue;
      }
      if (decoded is! Map) {
        continue;
      }
      final entry = NotificationInboxEntry.fromJson(
        decoded.cast<String, dynamic>(),
      );
      if (entry != null) {
        final keySuffix = storedEntry.key.substring(_entryKeyPrefix.length);
        final read = entry.read || stored['$_readKeyPrefix$keySuffix'] == true;
        entries.add(read == entry.read ? entry : entry.copyWith(read: read));
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
    final prefs = SharedPreferencesAsync();
    await _migrateLegacyEntries(prefs);
    final keySuffix = _keySuffix(entry.id);
    final entryKey = '$_entryKeyPrefix$keySuffix';
    final existing = await _entryForKey(prefs, entryKey);
    final merged = existing == null
        ? entry
        : entry.copyWith(
            receivedAt: existing.receivedAt.isAfter(entry.receivedAt)
                ? existing.receivedAt
                : entry.receivedAt,
            read: existing.read || entry.read,
          );
    if (merged.read) {
      await prefs.setBool('$_readKeyPrefix$keySuffix', true);
    }
    await prefs.setString(entryKey, jsonEncode(merged.toJson()));
    await _pruneToLimit(prefs);
  }

  Future<void> markRead(String id) async {
    final prefs = SharedPreferencesAsync();
    await _migrateLegacyEntries(prefs);
    await prefs.setBool('$_readKeyPrefix${_keySuffix(id)}', true);
  }

  Future<void> markAllRead() async {
    final prefs = SharedPreferencesAsync();
    await _migrateLegacyEntries(prefs);
    final entryKeys = (await prefs.getKeys()).where(
      (key) => key.startsWith(_entryKeyPrefix),
    );
    await Future.wait([
      for (final key in entryKeys)
        prefs.setBool(
          '$_readKeyPrefix${key.substring(_entryKeyPrefix.length)}',
          true,
        ),
    ]);
  }

  Future<void> clear() async {
    final prefs = SharedPreferencesAsync();
    final keys = await prefs.getKeys();
    await prefs.clear(
      allowList: {
        storageKey,
        ...keys.where(
          (key) =>
              key.startsWith(_entryKeyPrefix) || key.startsWith(_readKeyPrefix),
        ),
      },
    );
    final legacyPrefs = await SharedPreferences.getInstance();
    await legacyPrefs.remove(storageKey);
  }

  Future<NotificationInboxEntry?> _entryForKey(
    SharedPreferencesAsync prefs,
    String key,
  ) async {
    final raw = await prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) {
      return null;
    }
    return NotificationInboxEntry.fromJson(decoded.cast<String, dynamic>());
  }

  Future<void> _pruneToLimit(SharedPreferencesAsync prefs) async {
    final entries = await _loadEntries(prefs);
    if (entries.length <= _maxEntries) {
      return;
    }
    final staleEntries = entries.skip(_maxEntries);
    await Future.wait([
      for (final entry in staleEntries) ...[
        prefs.remove('$_entryKeyPrefix${_keySuffix(entry.id)}'),
        prefs.remove('$_readKeyPrefix${_keySuffix(entry.id)}'),
      ],
    ]);
  }

  Future<void> _migrateLegacyEntries(SharedPreferencesAsync prefs) async {
    final legacyPrefs = await SharedPreferences.getInstance();
    await legacyPrefs.reload();
    final raw =
        await prefs.getString(storageKey) ?? legacyPrefs.getString(storageKey);
    if (raw == null) {
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      await prefs.remove(storageKey);
      await legacyPrefs.remove(storageKey);
      return;
    }
    if (decoded is List) {
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final entry = NotificationInboxEntry.fromJson(
          item.cast<String, dynamic>(),
        );
        if (entry == null) {
          continue;
        }
        final suffix = _keySuffix(entry.id);
        final entryKey = '$_entryKeyPrefix$suffix';
        if (!await prefs.containsKey(entryKey)) {
          await prefs.setString(entryKey, jsonEncode(entry.toJson()));
        }
        if (entry.read) {
          await prefs.setBool('$_readKeyPrefix$suffix', true);
        }
      }
    }
    await prefs.remove(storageKey);
    await legacyPrefs.remove(storageKey);
  }
}

String _keySuffix(String id) {
  return base64Url.encode(utf8.encode(id)).replaceAll('=', '');
}

String _entryId(
  String? messageId,
  String title,
  String body,
  Map<String, dynamic> data,
  DateTime receivedAt,
) {
  final eventId = _stringValue(data['eventId']).isNotEmpty
      ? _stringValue(data['eventId'])
      : _stringValue(data['event_id']);
  if (eventId.isNotEmpty) {
    return eventId;
  }
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
