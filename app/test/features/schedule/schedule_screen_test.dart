import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/data/models/schedule.dart';
import 'package:kbo_fans/data/providers.dart';
import 'package:kbo_fans/features/schedule/schedule_screen.dart';

void main() {
  testWidgets('일정 초기 로딩은 새로고침 indicator와 중복되지 않는다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleProvider.overrideWith(
            (_, _) => Completer<List<ScheduleDay>>().future,
          ),
        ],
        child: const MaterialApp(home: ScheduleScreen()),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsNothing);
  });
}
