import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 앱 내 개발자 콘솔 — 에러/로그를 화면에 표시
class DevConsole {
  static final DevConsole _instance = DevConsole._();
  static DevConsole get instance => _instance;

  DevConsole._();

  final List<LogEntry> _logs = [];
  final _listeners = <VoidCallback>[];

  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
  void _notify() {
    for (final l in _listeners) { l(); }
  }

  List<LogEntry> get logs => List.unmodifiable(_logs);

  void log(String message, {LogLevel level = LogLevel.info}) {
    _logs.insert(0, LogEntry(
      message: message,
      level: level,
      time: DateTime.now(),
    ));
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

class LogEntry {
  final String message;
  final LogLevel level;
  final DateTime time;
  const LogEntry({required this.message, required this.level, required this.time});
}

/// 개발자 콘솔 FAB + 오버레이
class DevConsoleOverlay extends StatefulWidget {
  final Widget child;
  const DevConsoleOverlay({super.key, required this.child});

  @override
  State<DevConsoleOverlay> createState() => _DevConsoleOverlayState();
}

class _DevConsoleOverlayState extends State<DevConsoleOverlay> {
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    DevConsole.instance.addListener(_onLog);
  }

  @override
  void dispose() {
    DevConsole.instance.removeListener(_onLog);
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

  int get _errorCount => DevConsole.instance.logs.where((l) => l.level == LogLevel.error).length;

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
                      right: 2, top: 2,
                      child: Container(
                        width: 16, height: 16,
                        decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle),
                        child: Center(child: Text('$_errorCount', style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700))),
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
            left: 8, right: 8, bottom: 90, top: MediaQuery.of(context).size.height * 0.4,
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
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      children: [
                        const Text('🔧 Dev Console', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => DevConsole.instance.clear(),
                          child: const Text('Clear', style: TextStyle(fontSize: 12, color: AppColors.accent)),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => setState(() => _isOpen = false),
                          child: const Icon(Icons.close, size: 18, color: AppColors.textDisabled),
                        ),
                      ],
                    ),
                  ),
                  // 로그 리스트
                  Expanded(
                    child: DevConsole.instance.logs.isEmpty
                        ? const Center(child: Text('로그가 없습니다', style: TextStyle(fontSize: 12, color: AppColors.textDisabled)))
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: DevConsole.instance.logs.length,
                            itemBuilder: (_, i) {
                              final entry = DevConsole.instance.logs[i];
                              final color = switch (entry.level) {
                                LogLevel.error => AppColors.live,
                                LogLevel.warn => AppColors.ballYellow,
                                LogLevel.info => AppColors.textSecondary,
                              };
                              final timeStr = '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}:${entry.time.second.toString().padLeft(2, '0')}';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '[$timeStr] ${entry.message}',
                                  style: TextStyle(fontSize: 11, color: color, fontFamily: 'monospace'),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
