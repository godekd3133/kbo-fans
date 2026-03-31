import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/api/api_client.dart';
import '../../data/providers.dart';

class ApiDiagnosticsScreen extends ConsumerStatefulWidget {
  const ApiDiagnosticsScreen({super.key});

  @override
  ConsumerState<ApiDiagnosticsScreen> createState() => _ApiDiagnosticsScreenState();
}

class _ApiDiagnosticsScreenState extends ConsumerState<ApiDiagnosticsScreen> {
  late Future<List<_DiagnosticResult>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_DiagnosticResult>> _load() async {
    final client = ref.read(apiClientProvider);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final yearMonth = DateFormat('yyyy-MM').format(DateTime.now());

    return Future.wait([
      _measure('health', () async => client.get('/health')),
      _measure('scoreboard', () async => client.get('/scoreboard', queryParameters: {'date': today})),
      _measure('schedule', () async => client.get('/schedule', queryParameters: {'month': yearMonth})),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API 진단')),
      body: FutureBuilder<List<_DiagnosticResult>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.live),
            );
          }

          final results = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'health / scoreboard / schedule 상태를 한 번에 확인합니다.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              for (final result in results) ...[
                _DiagnosticCard(result: result),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _future = _load()),
                child: const Text('다시 진단'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DiagnosticResult {
  final String key;
  final bool ok;
  final double elapsedMs;
  final String detail;

  const _DiagnosticResult({
    required this.key,
    required this.ok,
    required this.elapsedMs,
    required this.detail,
  });
}

class _DiagnosticCard extends StatelessWidget {
  final _DiagnosticResult result;

  const _DiagnosticCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final color = result.ok ? AppColors.positive : AppColors.live;
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
                result.ok ? Icons.check_circle_outline : Icons.error_outline,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                result.key,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${result.elapsedMs.toStringAsFixed(0)}ms',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            result.detail,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
