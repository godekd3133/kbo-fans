import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/data/bootstrap/bootstrap_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'current standings bootstrap uses verified fresh exact snapshot',
    () async {
      final repository = BootstrapRepository(
        now: () => DateTime.utc(2026, 5, 20, 6),
      );

      final snapshot = await repository.loadStandings(2026);
      final standings = snapshot?['standings'] as List<dynamic>? ?? const [];
      final first = standings.firstOrNull as Map<String, dynamic>?;

      expect(standings, hasLength(10));
      expect(first?['teamId'], 'SS');
      expect(first?['games'], 43);
      expect(first?['streak'], '1승');
    },
  );

  test('stale current standings bootstrap is not exposed', () async {
    final repository = BootstrapRepository(
      now: () => DateTime.utc(2026, 5, 21, 5),
    );

    expect(await repository.loadStandings(2026), isNull);
  });

  test('future-dated current standings bootstrap is not exposed', () async {
    final repository = BootstrapRepository(
      now: () => DateTime.utc(2026, 5, 20, 4),
    );

    expect(await repository.loadStandings(2026), isNull);
  });

  test('unverified historical standings bootstrap stays empty', () async {
    final repository = BootstrapRepository(
      now: () => DateTime.utc(2026, 5, 20, 5),
    );

    expect(await repository.loadStandings(2025), isNull);
  });

  test(
    'current records overview bootstrap uses fresh exact season snapshot',
    () async {
      final repository = BootstrapRepository(
        now: () => DateTime.utc(2026, 6, 20, 3),
      );
      final overview = await repository.loadRecordsOverview(2026);
      final leaders = overview?['leaders'] as Map<String, dynamic>? ?? const {};

      expect(leaders['avg'], isNotEmpty);
      expect(await repository.loadRecordsOverview(2025), isNull);
    },
  );

  test('stale current records overview bootstrap is not exposed', () async {
    final repository = BootstrapRepository(
      now: () => DateTime.utc(2026, 6, 20, 9),
    );

    expect(await repository.loadRecordsOverview(2026), isNull);
  });
}
