import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/features/schedule/widgets/schedule_game_card.dart';
import 'package:kbo_fans/data/models/schedule.dart';

class _TolerantGoldenFileComparator extends LocalFileComparator {
  _TolerantGoldenFileComparator(
    super.testFile, {
    required double precisionTolerance,
  }) : _precisionTolerance = precisionTolerance;

  final double _precisionTolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final ComparisonResult result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );

    final passed = result.passed || result.diffPercent <= _precisionTolerance;
    if (passed) {
      result.dispose();
      return true;
    }

    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        body: Center(child: SizedBox(width: 390, child: child)),
      ),
    );
  }

  testWidgets('schedule game card final golden', (tester) async {
    final previousComparator = goldenFileComparator;
    goldenFileComparator = _TolerantGoldenFileComparator(
      Uri.parse(
        'test/features/schedule/widgets/schedule_game_card_golden_test.dart',
      ),
      precisionTolerance: 0.002,
    );
    addTearDown(() => goldenFileComparator = previousComparator);

    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 220);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const game = ScheduleGame(
      gameId: '20260328TEST0',
      time: '14:00',
      awayId: 'UNKNOWN_AWAY',
      awayName: '원정',
      awayScore: 11,
      homeId: 'UNKNOWN_HOME',
      homeName: '홈',
      homeScore: 7,
      stadium: '잠실',
      status: 'FINAL',
    );

    await tester.pumpWidget(
      wrap(
        const ScheduleGameCard(
          game: game,
          ticketSummary: '인터파크 티켓 · 03.21 11:00 오픈 · 정책 기준',
          showTeamLogos: false,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await expectLater(
      find.byType(ScheduleGameCard),
      matchesGoldenFile('goldens/schedule_game_card_final.png'),
    );
  });
}
