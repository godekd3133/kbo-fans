import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/theme/app_theme.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/features/game_detail/widgets/game_reading_card.dart';

Game fixture({
  List<int?> away = const [1, 0, 2],
  List<int?> home = const [0, 2, 0],
  int awayScore = 3,
  int homeScore = 2,
  bool available = true,
  GameStatus status = GameStatus.final_,
}) => Game(
  gameId: '20260907SSLG0',
  status: status,
  inning: '',
  stadium: '잠실',
  startTime: '18:30',
  away: TeamScore(
    teamId: 'SS',
    teamName: '삼성',
    shortName: '삼성',
    score: awayScore,
    scoreAvailable: available,
    innings: away,
  ),
  home: TeamScore(
    teamId: 'LG',
    teamName: 'LG',
    shortName: 'LG',
    score: homeScore,
    innings: home,
  ),
);

void main() {
  test(
    'verified innings retain half-inning chronology and cumulative totals',
    () {
      final result = verifiedScoringInnings(fixture());
      expect(result.map((entry) => entry.label), ['1회초', '2회말', '3회초']);
      expect(result.map((entry) => entry.score), ['1 : 0', '1 : 2', '3 : 2']);
      expect(gameReadingHeadline(fixture()), '삼성, 1점 차 승리');
    },
  );
  test('missing, corrected and malformed innings never become a story', () {
    for (final game in [
      fixture(away: [1, null, 2]),
      fixture(away: [1, -1, 3]),
      fixture(awayScore: 4),
      fixture(available: false),
      fixture(status: GameStatus.cancelled),
      fixture(status: GameStatus.scheduled),
    ]) {
      expect(verifiedScoringInnings(game), isEmpty);
    }
  });
  test(
    'not-played final half and live prefix remain valid; true zero stays zero',
    () {
      expect(
        verifiedScoringInnings(
          fixture(home: [0, 2, null], status: GameStatus.live),
        ).last.score,
        '3 : 2',
      );
      final draw = fixture(
        away: [0, 0],
        home: [0, 0],
        awayScore: 0,
        homeScore: 0,
      );
      expect(gameReadingHeadline(draw), '무승부로 마무리됐어요');
      expect(verifiedScoringInnings(draw), isEmpty);
      expect(gameReadingHeadline(fixture(available: false)), '공식 점수를 확인하고 있어요');
    },
  );
  testWidgets(
    'reading actions work and text remains visible at 320px and 240%',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var relay = 0;
      var boxscore = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 844),
                textScaler: TextScaler.linear(2.4),
              ),
              child: SingleChildScrollView(
                child: GameReadingCard(
                  game: fixture(),
                  onOpenRelay: () => relay++,
                  onOpenBoxscore: () => boxscore++,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('중계로 흐름 읽기'));
      await tester.tap(find.text('중계로 흐름 읽기'));
      await tester.ensureVisible(find.text('선수 기록 확인'));
      await tester.tap(find.text('선수 기록 확인'));
      expect(relay, 1);
      expect(boxscore, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
