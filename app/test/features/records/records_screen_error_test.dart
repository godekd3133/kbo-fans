import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/core/utils/kbo_time.dart';
import 'package:kbo_fans/data/models/team_records_bundle.dart';
import 'package:kbo_fans/data/models/team_stats.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/records/records_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppConfig.initialize();

  testWidgets('팀 선수 기록 오류 상태에서 다시 시도하면 목록을 복구한다', (tester) async {
    var attempts = 0;
    final season = kboCurrentSeason();

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          teamRecordsProvider.overrideWith((ref, key) async {
            attempts += 1;
            if (attempts == 1) {
              throw StateError('temporary records failure');
            }
            return TeamRecordsBundle(
              players: const [],
              teamStats: TeamStats(
                teamId: 'LG',
                season: season,
                hitting: const {},
                pitching: const {},
              ),
            );
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const RecordsScreen(teamId: 'LG'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('선수 기록을 불러올 수 없습니다'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('조건에 맞는 선수가 없습니다'), findsOneWidget);
    expect(attempts, 2);
  });
}
