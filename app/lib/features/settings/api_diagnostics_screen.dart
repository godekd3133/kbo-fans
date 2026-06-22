import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_motion.dart';
import '../../data/api/api_client.dart';
import '../../data/providers.dart';
import '../../services/game_event_alert_service.dart';
import '../../services/push_notification_service.dart';

class ApiDiagnosticsScreen extends ConsumerStatefulWidget {
  const ApiDiagnosticsScreen({super.key});

  @override
  ConsumerState<ApiDiagnosticsScreen> createState() =>
      _ApiDiagnosticsScreenState();
}

class _ApiDiagnosticsScreenState extends ConsumerState<ApiDiagnosticsScreen> {
  late Future<List<_DiagnosticResult>> _future;
  late Future<Map<String, dynamic>> _pushFuture;
  bool _localNotificationBusy = false;
  bool _remoteNotificationBusy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _pushFuture = PushNotificationService.instance.debugState();
  }

  Future<List<_DiagnosticResult>> _load() async {
    final client = ref.read(apiClientProvider);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final yearMonth = DateFormat('yyyy-MM').format(DateTime.now());

    return Future.wait([
      _measure('health', () async => client.get('/health')),
      _measure(
        'scoreboard',
        () async => client.get('/scoreboard', queryParameters: {'date': today}),
      ),
      _measure(
        'schedule',
        () async =>
            client.get('/schedule', queryParameters: {'month': yearMonth}),
      ),
    ]);
  }

  Future<_DiagnosticResult> _measure(
    String key,
    Future<Map<String, dynamic>> Function() loader,
  ) async {
    final startedAt = DateTime.now().microsecondsSinceEpoch;
    try {
      final data = await loader();
      final elapsedMs =
          (DateTime.now().microsecondsSinceEpoch - startedAt) / 1000;
      return _DiagnosticResult(
        key: key,
        ok: true,
        elapsedMs: elapsedMs,
        detail: _successDetail(key, data),
      );
    } catch (error) {
      final elapsedMs =
          (DateTime.now().microsecondsSinceEpoch - startedAt) / 1000;
      return _DiagnosticResult(
        key: key,
        ok: false,
        elapsedMs: elapsedMs,
        detail: describeAsyncError(error),
      );
    }
  }

  String _successDetail(String key, Map<String, dynamic> data) {
    switch (key) {
      case 'health':
        return 'status=${data['status'] ?? 'ok'}';
      case 'scoreboard':
        final games = data['games'] as List<dynamic>? ?? const [];
        return 'games=${games.length}';
      case 'schedule':
        final days = data['days'] as List<dynamic>? ?? const [];
        return 'days=${days.length}';
      default:
        return 'ok';
    }
  }

  Future<void> _sendLocalNotificationTest() async {
    if (_localNotificationBusy) {
      return;
    }
    setState(() {
      _localNotificationBusy = true;
    });
    try {
      final sent = await GameEventAlertService.instance
          .showDiagnosticNotification();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sent ? '로컬 알림 테스트를 보냈습니다' : '시스템 알림 권한이 필요합니다')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _localNotificationBusy = false;
        });
      }
    }
  }

  Future<void> _sendRemoteNotificationTest() async {
    if (_remoteNotificationBusy) {
      return;
    }
    setState(() {
      _remoteNotificationBusy = true;
    });
    try {
      final result = await PushNotificationService.instance
          .sendRemoteDiagnosticTest(myTeam: ref.read(myTeamProvider));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
      setState(() {
        _pushFuture = PushNotificationService.instance.debugState();
      });
    } finally {
      if (mounted) {
        setState(() {
          _remoteNotificationBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API 진단')),
      body: FutureBuilder<List<_DiagnosticResult>>(
        future: _future,
        builder: (context, snapshot) {
          Widget child;
          if (!snapshot.hasData) {
            child = const Center(
              key: ValueKey('api-diagnostics-loading'),
              child: CircularProgressIndicator(color: AppColors.live),
            );
            return AppMotionSwitcher(child: child);
          }

          final results = snapshot.data!;
          child = ListView(
            key: const ValueKey('api-diagnostics-ready'),
            padding: const EdgeInsets.all(16),
            children: [
              const AppMotionListItem(
                index: 0,
                child: Text(
                  'health / scoreboard / schedule 상태를 한 번에 확인합니다.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              for (int index = 0; index < results.length; index++) ...[
                AppMotionListItem(
                  index: index + 1,
                  child: _DiagnosticCard(result: results[index]),
                ),
                const SizedBox(height: 10),
              ],
              FutureBuilder<Map<String, dynamic>>(
                future: _pushFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox.shrink();
                  }
                  final data = snapshot.data!;
                  final topics = (data['topics'] as List<dynamic>? ?? const [])
                      .join(', ');
                  final status = data['status'] as String? ?? 'idle';
                  final reason = data['reason'] as String?;
                  final remotePushAvailable =
                      data['remotePushAvailable'] == true;
                  final localGameAlertsEnabled =
                      data['localGameEventAlertsEnabled'] == true;
                  final localGameAlertsForced =
                      data['localGameEventAlertsForced'] == true;
                  final apiBaseUrl = data['apiBaseUrl'] as String? ?? '-';
                  final isLocalSkipped =
                      !shouldUseRemotePushServices(
                        isWeb: false,
                        useBackendApi: AppConfig.instance.shouldUseBackendApi,
                      ) &&
                      status == 'skipped';
                  return AppMotionListItem(
                    index: results.length + 1,
                    child: _DiagnosticCard(
                      result: _DiagnosticResult(
                        key: 'push',
                        ok: data['initialized'] == true,
                        muted: isLocalSkipped,
                        elapsedMs: 0,
                        detail:
                            '${_pushDetailPrefix(status)} initialized=${data['initialized']} tokenReady=${data['tokenReady']}'
                            ' remote=${remotePushAvailable ? 'on' : 'off'}'
                            ' localAlerts=${localGameAlertsEnabled ? 'on' : 'off'}'
                            '${topics.isNotEmpty ? ' topics=$topics' : ''}',
                        note: _pushReasonLabel(
                          status: status,
                          reason: reason,
                          isLocalSkipped: isLocalSkipped,
                          localGameAlertsForced: localGameAlertsForced,
                          apiBaseUrl: apiBaseUrl,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _localNotificationBusy
                        ? null
                        : () => unawaited(_sendLocalNotificationTest()),
                    icon: const Icon(Icons.notifications_none_outlined),
                    label: Text(_localNotificationBusy ? '확인 중' : '로컬 알림 테스트'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _remoteNotificationBusy
                        ? null
                        : () => unawaited(_sendRemoteNotificationTest()),
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: Text(_remoteNotificationBusy ? '요청 중' : '원격 푸시 테스트'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _future = _load();
                      _pushFuture = PushNotificationService.instance
                          .debugState();
                    }),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('다시 진단'),
                  ),
                ],
              ),
            ],
          );
          return AppMotionSwitcher(child: child);
        },
      ),
    );
  }
}

class _DiagnosticResult {
  final String key;
  final bool ok;
  final bool muted;
  final double elapsedMs;
  final String detail;
  final String? note;

  const _DiagnosticResult({
    required this.key,
    required this.ok,
    this.muted = false,
    required this.elapsedMs,
    required this.detail,
    this.note,
  });
}

class _DiagnosticCard extends StatelessWidget {
  final _DiagnosticResult result;

  const _DiagnosticCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final color = result.muted
        ? AppColors.textSecondary
        : result.ok
        ? AppColors.positive
        : AppColors.live;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.muted
                    ? Icons.pause_circle_outline
                    : result.ok
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                result.key,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${result.elapsedMs.toStringAsFixed(0)}ms',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            result.detail,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          if (result.note != null) ...[
            const SizedBox(height: 6),
            Text(
              result.note!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textDisabled,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _pushDetailPrefix(String status) {
  switch (status) {
    case 'ready':
      return 'ready';
    case 'skipped':
      return 'disabled';
    case 'failed':
      return 'failed';
    default:
      return 'idle';
  }
}

String? _pushReasonLabel({
  required String status,
  required String? reason,
  required bool isLocalSkipped,
  required bool localGameAlertsForced,
  required String apiBaseUrl,
}) {
  final details = <String>[];
  if (localGameAlertsForced) {
    details.add('로컬 경기 이벤트 알림 강제 플래그가 켜져 있습니다.');
  }
  if (apiBaseUrl != '-') {
    details.add('API $apiBaseUrl');
  }
  if (reason == null || reason.isEmpty) {
    if (isLocalSkipped) {
      details.insert(0, '로컬 환경에서 푸시 초기화를 건너뛰었습니다.');
    }
    return details.isEmpty ? null : details.join(' ');
  }
  if (reason.contains('FirebaseOptions')) {
    return '로컬 Firebase 설정이 없어 푸시를 비활성 상태로 표시합니다.';
  }
  if (reason.contains('GoogleService-Info') ||
      reason.contains('FirebaseApp') ||
      reason.contains('Firebase')) {
    return 'Firebase 설정을 읽지 못해 푸시 초기화가 실패했습니다.';
  }
  return isLocalSkipped ? '로컬 환경에서 푸시 초기화를 건너뛰었습니다.' : '푸시 초기화 실패: $reason';
}
