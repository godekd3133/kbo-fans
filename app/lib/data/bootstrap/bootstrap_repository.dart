import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class BootstrapRepository {
  static const _standingsAsset = 'assets/bootstrap/standings.json';
  static const _recordsOverviewAsset = 'assets/bootstrap/records_overview.json';

  static Map<String, dynamic>? _standingsCache;
  static Map<String, dynamic>? _recordsOverviewCache;

  Future<Map<String, dynamic>?> loadStandings(int season) async {
    final data = await _loadJson(
      _standingsAsset,
      cached: _standingsCache,
    );
    _standingsCache ??= data;
    return (data['seasons'] as Map<String, dynamic>? ?? const {})['$season']
        as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>?> loadRecordsOverview(int season) async {
    final data = await _loadJson(
      _recordsOverviewAsset,
      cached: _recordsOverviewCache,
    );
    _recordsOverviewCache ??= data;
    final seasons = data['seasons'] as Map<String, dynamic>? ?? const {};

    final direct = seasons['$season'] as Map<String, dynamic>?;
    if (_hasOverviewData(direct)) {
      return direct;
    }

    final available = seasons.keys
        .map(int.tryParse)
        .whereType<int>()
        .where((year) => year <= season)
        .toList()
      ..sort();
    for (final year in available.reversed) {
      final candidate = seasons['$year'] as Map<String, dynamic>?;
      if (_hasOverviewData(candidate)) {
        return candidate;
      }
    }
    return direct;
  }

  Future<Map<String, dynamic>> _loadJson(
    String assetPath, {
    required Map<String, dynamic>? cached,
  }) async {
    if (cached != null) {
      return cached;
    }

    final raw = await rootBundle.loadString(assetPath);
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  bool _hasOverviewData(Map<String, dynamic>? data) {
    final leaders = data?['leaders'] as Map<String, dynamic>? ?? const {};
    return (leaders['avg'] as List<dynamic>? ?? const []).isNotEmpty ||
        (leaders['hr'] as List<dynamic>? ?? const []).isNotEmpty ||
        (leaders['ops'] as List<dynamic>? ?? const []).isNotEmpty ||
        (leaders['era'] as List<dynamic>? ?? const []).isNotEmpty;
  }
}
