import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/repositories/kbo_direct_repository.dart';

void main() {
  test(
    'direct relay summary fallback is suppressed before playable states',
    () {
      expect(
        shouldSuppressDirectRelaySummaryFallback(GameStatus.scheduled),
        isTrue,
      );
      expect(
        shouldSuppressDirectRelaySummaryFallback(GameStatus.cancelled),
        isTrue,
      );
      expect(
        shouldSuppressDirectRelaySummaryFallback(GameStatus.suspended),
        isTrue,
      );
      expect(
        shouldSuppressDirectRelaySummaryFallback(GameStatus.live),
        isFalse,
      );
      expect(
        shouldSuppressDirectRelaySummaryFallback(GameStatus.final_),
        isFalse,
      );
    },
  );

  test('direct relay summary fallback uses only real line-score innings', () {
    final emptyPregame = _game(
      status: GameStatus.live,
      awayInnings: const [null, null, null],
      homeInnings: const [null, null, null],
    );
    expect(directRelaySummaryInningIndexes(emptyPregame), isEmpty);

    final withScores = _game(
      status: GameStatus.live,
      awayInnings: const [0, null, 2, null],
      homeInnings: const [null, 1, null, null],
    );
    expect(directRelaySummaryInningIndexes(withScores), [0, 1, 2]);
  });
}

Game _game({
  required GameStatus status,
  required List<int?> awayInnings,
  required List<int?> homeInnings,
}) {
  return Game(
    gameId: '20260521KTSS0',
    status: status,
    inning: '',
    away: TeamScore(
      teamId: 'KT',
      teamName: 'KT',
      shortName: 'KT',
      score: 0,
      innings: awayInnings,
    ),
    home: TeamScore(
      teamId: 'SS',
      teamName: '삼성',
      shortName: '삼성',
      score: 0,
      innings: homeInnings,
    ),
    stadium: '대구',
    startTime: '18:30',
  );
}
