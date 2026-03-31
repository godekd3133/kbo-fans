import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';

/// 앱 내 개발자 콘솔 — 에러/로그를 화면에 표시
class DevConsole {
  static final DevConsole _instance = DevConsole._();
  static DevConsole get instance => _instance;

  DevConsole._();

  static const _dedupeWindow = Duration(seconds: 5);
  final List<LogEntry> _logs = [];
  final _listeners = <VoidCallback>[];

  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
  void _notify() {
    for (final l in _listeners) {
      l();
    }
  }

  List<LogEntry> get logs => List.unmodifiable(_logs);

  void log(String message, {LogLevel level = LogLevel.info}) {
    final now = DateTime.now();
    if (_logs.isNotEmpty) {
      final head = _logs.first;
      if (head.message == message &&
          head.level == level &&
          now.difference(head.time) <= _dedupeWindow) {
        _logs[0] = head.copyWith(time: now, count: head.count + 1);
        _notify();
        return;
      }
    }

    _logs.insert(0, LogEntry(message: message, level: level, time: now));
    // 최대 100개
    if (_logs.length > 100) _logs.removeLast();
    _notify();
  }

  void info(String msg) => log(msg, level: LogLevel.info);
  void warn(String msg) => log(msg, level: LogLevel.warn);
  void error(String msg) => log(msg, level: LogLevel.error);

  void clear() {
    _logs.clear();
    _notify();
  }
}

enum LogLevel { info, warn, error }

enum LogCategory { all, api, kbo, ui, push }

class LogEntry {
  final String message;
  final LogLevel level;
  final DateTime time;
  final int count;
  const LogEntry({
    required this.message,
    required this.level,
    required this.time,
    this.count = 1,
  });

  LogEntry copyWith({
    String? message,
    LogLevel? level,
    DateTime? time,
    int? count,
  }) {
    return LogEntry(
      message: message ?? this.message,
      level: level ?? this.level,
      time: time ?? this.time,
      count: count ?? this.count,
    );
  }
}

/// 개발자 콘솔 FAB + 오버레이
class DevConsoleOverlay extends StatefulWidget {
  final Widget child;
  const DevConsoleOverlay({super.key, required this.child});

  @override
  State<DevConsoleOverlay> createState() => _DevConsoleOverlayState();
}

class _DevConsoleOverlayState extends State<DevConsoleOverlay> {
  static const _prefsApiOnly = 'dev_console.api_only';
  static const _prefsCategory = 'dev_console.category';
  static const _prefsInfo = 'dev_console.level.info';
  static const _prefsWarn = 'dev_console.level.warn';
  static const _prefsError = 'dev_console.level.error';
  bool _isOpen = false;
  bool _apiOnly = false;
  bool _collapseOldLogs = true;
  String _query = '';
  LogCategory _category = LogCategory.all;
  final Set<LogLevel> _visibleLevels = {
    LogLevel.info,
    LogLevel.warn,
    LogLevel.error,
  };
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    DevConsole.instance.addListener(_onLog);
    _restoreFilters();
  }

  @override
  void dispose() {
    DevConsole.instance.removeListener(_onLog);
    _searchController.dispose();
    super.dispose();
  }

  void _onLog() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _restoreFilters() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _apiOnly = prefs.getBool(_prefsApiOnly) ?? false;
      _category = LogCategory.values.elementAt(
        prefs.getInt(_prefsCategory) ?? LogCategory.all.index,
      );
      _visibleLevels
        ..clear()
        ..addAll({
          if (prefs.getBool(_prefsInfo) ?? true) LogLevel.info,
          if (prefs.getBool(_prefsWarn) ?? true) LogLevel.warn,
          if (prefs.getBool(_prefsError) ?? true) LogLevel.error,
        });
      if (_visibleLevels.isEmpty) {
        _visibleLevels.addAll(LogLevel.values);
      }
    });
  }

  Future<void> _persistFilters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsApiOnly, _apiOnly);
    await prefs.setInt(_prefsCategory, _category.index);
    await prefs.setBool(_prefsInfo, _visibleLevels.contains(LogLevel.info));
    await prefs.setBool(_prefsWarn, _visibleLevels.contains(LogLevel.warn));
    await prefs.setBool(_prefsError, _visibleLevels.contains(LogLevel.error));
  }

  int get _errorCount =>
      DevConsole.instance.logs.where((l) => l.level == LogLevel.error).length;
  List<LogEntry> get _filteredLogs => DevConsole.instance.logs
      .where((entry) => _visibleLevels.contains(entry.level))
      .where((entry) => !_apiOnly || _isApiLog(entry.message))
      .where((entry) => _matchesCategory(entry.message))
      .where(
        (entry) =>
            _query.isEmpty ||
            entry.message.toLowerCase().contains(_query.toLowerCase()),
      )
      .where((entry) => !_collapseOldLogs || _isRecent(entry.time))
      .toList();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // FAB
        Positioned(
          right: 16,
          bottom: 100,
          child: GestureDetector(
            onTap: () => setState(() => _isOpen = !_isOpen),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _errorCount > 0 ? AppColors.live : AppColors.card,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.divider),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.terminal, color: AppColors.textPrimary, size: 24),
                  if (_errorCount > 0)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: AppColors.live,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$_errorCount',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // 콘솔 패널
        if (_isOpen)
          Positioned(
            left: 8,
            right: 8,
            bottom: 90,
            top: MediaQuery.of(context).size.height * 0.4,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xF0111111),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  children: [
                  // 헤더
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '🔧 Dev Console',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'API ${AppConfig.instance.apiBaseUrl}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textDisabled,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                final text = DevConsole.instance.logs
                                    .map((e) {
                                      final t =
                                          '${e.time.hour.toString().padLeft(2, '0')}:${e.time.minute.toString().padLeft(2, '0')}:${e.time.second.toString().padLeft(2, '0')}';
                                      final lvl = e.level.name.toUpperCase();
                                      return '[$t][$lvl] ${e.message}';
                                    })
                                    .join('\n');
                                Clipboard.setData(ClipboardData(text: text));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('로그 복사됨'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                              child: const Icon(
                                Icons.copy,
                                size: 16,
                                color: AppColors.accent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => DevConsole.instance.clear(),
                              child: const Text(
                                'Clear',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.accent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => setState(() => _isOpen = false),
                              child: const Icon(
                                Icons.close,
                                size: 18,
                                color: AppColors.textDisabled,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _quickChip(
                              selected: !_apiOnly,
                              label: 'ALL',
                              onTap: () {
                                setState(() => _apiOnly = false);
                                _persistFilters();
                              },
                            ),
                            const SizedBox(width: 8),
                            _quickChip(
                              selected: _apiOnly,
                              label: 'API',
                              onTap: () {
                                setState(() => _apiOnly = true);
                                _persistFilters();
                              },
                            ),
                            const SizedBox(width: 8),
                            _quickChip(
                              selected: _collapseOldLogs,
                              label: '최근',
                              onTap: () => setState(
                                () => _collapseOldLogs = !_collapseOldLogs,
                              ),
                            ),
                            const SizedBox(width: 12),
                            _filterChip(LogLevel.info, 'INFO'),
                            const SizedBox(width: 8),
                            _filterChip(LogLevel.warn, 'WARN'),
                            const SizedBox(width: 8),
                            _filterChip(LogLevel.error, 'ERROR'),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: (value) {
                                  setState(() => _query = value.trim());
                                },
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textPrimary,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: '로그 검색',
                                  hintStyle: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textDisabled,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    size: 16,
                                    color: AppColors.textDisabled,
                                  ),
                                  suffixIcon: _query.isEmpty
                                      ? null
                                      : GestureDetector(
                                          onTap: () {
                                            _searchController.clear();
                                            setState(() => _query = '');
                                          },
                                          child: const Icon(
                                            Icons.close,
                                            size: 16,
                                            color: AppColors.textDisabled,
                                          ),
                                        ),
                                  filled: true,
                                  fillColor: AppColors.background.withValues(
                                    alpha: 0.5,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: AppColors.divider,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: AppColors.divider,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: AppColors.accent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _categoryChip(LogCategory.all, 'ALL'),
                              const SizedBox(width: 8),
                              _categoryChip(LogCategory.api, 'API'),
                              const SizedBox(width: 8),
                              _categoryChip(LogCategory.kbo, 'KBO'),
                              const SizedBox(width: 8),
                              _categoryChip(LogCategory.ui, 'UI'),
                              const SizedBox(width: 8),
                              _categoryChip(LogCategory.push, 'PUSH'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 로그 리스트
                  Expanded(
                    child: _filteredLogs.isEmpty
                        ? const Center(
                            child: Text(
                              '표시할 로그가 없습니다',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textDisabled,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _filteredLogs.length,
                            itemBuilder: (_, i) {
                              final entry = _filteredLogs[i];
                              final color = switch (entry.level) {
                                LogLevel.error => AppColors.live,
                                LogLevel.warn => AppColors.ballYellow,
                                LogLevel.info => AppColors.textSecondary,
                              };
                              final accent = _categoryColor(entry.message);
                              final timeStr =
                                  '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}:${entry.time.second.toString().padLeft(2, '0')}';
                              final repeatSuffix = entry.count > 1
                                  ? ' ×${entry.count}'
                                  : '';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: GestureDetector(
                                  onLongPress: () async {
                                    await Clipboard.setData(
                                      ClipboardData(
                                        text:
                                            '[$timeStr][${entry.level.name.toUpperCase()}] ${entry.message}',
                                      ),
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('로그 1건 복사됨'),
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                    }
                                  },
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.background.withValues(
                                        alpha: 0.22,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border(
                                        left: BorderSide(
                                          color: accent,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      '[$timeStr] ${entry.message}$repeatSuffix',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: color,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _filterChip(LogLevel level, String label) {
    final selected = _visibleLevels.contains(level);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (selected && _visibleLevels.length > 1) {
            _visibleLevels.remove(level);
          } else {
            _visibleLevels.add(level);
          }
        });
        _persistFilters();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.cardSub : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.textSecondary : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? AppColors.textPrimary : AppColors.textDisabled,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _quickChip({
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? AppColors.textPrimary : AppColors.textDisabled,
            fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  bool _isApiLog(String message) {
    return message.startsWith('API ') ||
        message.startsWith('DIAG ') ||
        message.startsWith('HOME ') ||
        message.startsWith('SCHEDULE ') ||
        message.startsWith('RECORDS ') ||
        message.startsWith('KBO ');
  }

  bool _matchesCategory(String message) {
    switch (_category) {
      case LogCategory.all:
        return true;
      case LogCategory.api:
        return _isApiLog(message);
      case LogCategory.kbo:
        return message.startsWith('KBO ');
      case LogCategory.ui:
        return message.startsWith('Flutter:') ||
            message.startsWith('HOME ') ||
            message.startsWith('SCHEDULE ');
      case LogCategory.push:
        return message.startsWith('Push ') || message.contains('push');
    }
  }

  bool _isRecent(DateTime time) {
    return DateTime.now().difference(time) <= const Duration(minutes: 2);
  }

  Widget _categoryChip(LogCategory category, String label) {
    final selected = _category == category;
    final accent = _categoryAccent(category);
    return GestureDetector(
      onTap: () {
        setState(() => _category = category);
        _persistFilters();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? accent : AppColors.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? AppColors.textPrimary : AppColors.textDisabled,
            fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Color _categoryAccent(LogCategory category) {
    switch (category) {
      case LogCategory.api:
        return AppColors.accent;
      case LogCategory.kbo:
        return AppColors.ballYellow;
      case LogCategory.ui:
        return AppColors.positive;
      case LogCategory.push:
        return AppColors.live;
      case LogCategory.all:
        return AppColors.textSecondary;
    }
  }

  Color _categoryColor(String message) {
    if (message.startsWith('KBO ')) {
      return AppColors.ballYellow;
    }
    if (message.startsWith('Push ') || message.contains('push')) {
      return AppColors.live;
    }
    if (message.startsWith('Flutter:') ||
        message.startsWith('HOME ') ||
        message.startsWith('SCHEDULE ')) {
      return AppColors.positive;
    }
    if (_isApiLog(message)) {
      return AppColors.accent;
    }
    return AppColors.textSecondary;
  }
}
