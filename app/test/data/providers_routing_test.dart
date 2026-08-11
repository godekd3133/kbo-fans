import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/core/config/api_endpoints.dart';
import 'package:kbo_fans/data/models/schedule.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/data/repositories/api_game_repository.dart';
import 'package:kbo_fans/data/repositories/api_player_repository.dart';
import 'package:kbo_fans/data/repositories/device_snapshot_player_repository.dart';
import 'package:kbo_fans/data/repositories/kbo_direct_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('production API fallback uses the active Lightsail HTTPS endpoint', () {
    expect(productionApiBaseUrl, 'https://3-39-79-1.sslip.io/api');
  });

  test(
    'repository routing defaults to backend API data unless explicitly disabled',
    () {
      AppConfig.initialize();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const useBackendApiFlag = String.fromEnvironment(
        'USE_BACKEND_API',
        defaultValue: '',
      );
      final useBackendApi = useBackendApiFlag.isEmpty
          ? true
          : useBackendApiFlag == 'true';
      const apiBaseUrlOverride = String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: '',
      );

      expect(AppConfig.instance.shouldUseBackendApi, useBackendApi);
      expect(AppConfig.instance.shouldUseDirectData, !useBackendApi);
      expect(
        AppConfig.instance.hasApiBaseUrlOverride,
        apiBaseUrlOverride.isNotEmpty,
      );
      if (apiBaseUrlOverride.isNotEmpty) {
        expect(AppConfig.instance.apiBaseUrl, apiBaseUrlOverride);
      }
      expect(
        container.read(gameRepositoryProvider),
        useBackendApi ? isA<ApiGameRepository>() : isA<KboDirectRepository>(),
      );
      expect(
        container.read(playerRepositoryProvider),
        useBackendApi
            ? isA<ApiPlayerRepository>()
            : isA<DeviceSnapshotPlayerRepository>(),
      );
    },
  );

  test('마이팀 저장은 느린 push registration convergence를 기다리지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final convergenceStarted = Completer<void>();
    final allowConvergence = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        myTeamRegistrationConvergenceProvider.overrideWithValue((
          myTeamId,
        ) async {
          expect(myTeamId, 'LG');
          convergenceStarted.complete();
          await allowConvergence.future;
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(myTeamProvider.notifier).setTeam('LG');
    await convergenceStarted.future;

    final prefs = await SharedPreferences.getInstance();
    expect(container.read(myTeamProvider), 'LG');
    expect(prefs.getString('myTeam'), 'LG');
    expect(allowConvergence.isCompleted, isFalse);

    allowConvergence.complete();
  });

  test('background push registration 오류는 마이팀 저장에 전파되지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final convergenceAttempted = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        myTeamRegistrationConvergenceProvider.overrideWithValue((
          myTeamId,
        ) async {
          convergenceAttempted.complete();
          throw StateError('offline');
        }),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(myTeamProvider.notifier).setTeam('KT'),
      completes,
    );
    await convergenceAttempted.future;
    await Future<void>.delayed(Duration.zero);

    final prefs = await SharedPreferences.getInstance();
    expect(container.read(myTeamProvider), 'KT');
    expect(prefs.getString('myTeam'), 'KT');
  });

  test('KBO 날짜 provider는 서울 자정 경계를 화면 구독자에게 전달한다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(kboDateProvider.notifier)
        .refresh(instant: DateTime.utc(2026, 12, 31, 15));

    expect(container.read(kboDateProvider), '2027-01-01');
  });

  test('시즌 일정 월 요청은 최대 3개만 병렬 실행하고 월 순서를 보존한다', () async {
    final months = kboScheduleSeasonMonths(2026);
    var active = 0;
    var peak = 0;

    final days = await loadKboSeasonScheduleBounded(
      yearMonths: months,
      loadMonth: (yearMonth) async {
        active += 1;
        if (active > peak) {
          peak = active;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active -= 1;
        return [ScheduleDay(date: '$yearMonth-01', games: const [])];
      },
    );

    expect(peak, 3);
    expect(days.map((day) => day.date), [
      for (final month in months) '$month-01',
    ]);
  });

  test('시즌 일정은 월별 schedule provider seam을 유지한다', () async {
    final requestedMonths = <String>[];
    final container = ProviderContainer(
      overrides: [
        scheduleProvider.overrideWith((ref, yearMonth) async {
          requestedMonths.add(yearMonth);
          return [ScheduleDay(date: '$yearMonth-01', games: const [])];
        }),
      ],
    );
    addTearDown(container.dispose);

    final days = await container.read(seasonScheduleProvider(2026).future);

    expect(requestedMonths, containsAll(kboScheduleSeasonMonths(2026)));
    expect(days.map((day) => day.date), [
      for (final month in kboScheduleSeasonMonths(2026)) '$month-01',
    ]);
  });
}
