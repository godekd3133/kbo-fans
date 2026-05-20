import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class BootstrapRepository {
  static const _standingsAsset = 'assets/bootstrap/standings.json';
  static const _recordsOverviewAsset = 'assets/bootstrap/records_overview.json';
  static const _currentSeasonSnapshotMaxAge = Duration(hours: 6);

  static Map<String, dynamic>? _standingsCache;
  static Map<String, dynamic>? _recordsOverviewCache;

  final DateTime Function() _now;

  BootstrapRepository({DateTime Function()? now}) : _now = now ?? DateTime.now;

  Future<Map<String, dynamic>?> loadStandings(int season) async {
    final data = await _loadJson(_standingsAsset, cached: _standingsCache);
    _standingsCache ??= data;
    final snapshot =
        (data['seasons'] as Map<String, dynamic>? ?? const {})['$season']
            as Map<String, dynamic>?;
    if (!_hasStandingsData(snapshot)) {
      return null;
    }
    if (_requiresFreshSnapshot(season) && !_isFreshGeneratedAt(data)) {
      return null;
    }
    return snapshot;
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
    return null;
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

  bool _hasStandingsData(Map<String, dynamic>? data) {
    return (data?['standings'] as List<dynamic>? ?? const []).isNotEmpty;
  }

  bool _isFreshGeneratedAt(Map<String, dynamic> data) {
    final generatedAt = _parseDate(data['generatedAt']);
    if (generatedAt == null) {
      return false;
    }
    return _now().toUtc().difference(generatedAt.toUtc()) <=
        _currentSeasonSnapshotMaxAge;
  }

  bool _requiresFreshSnapshot(int season) => season >= _now().year;

  DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value.replaceAll('Z', '+00:00'));
  }
}
