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

  test(
    'direct relay main-game fallback builds current player images from ids',
    () {
      final atBat = KboDirectRepository().currentAtBatFromMainGameForTesting({
        'SEASON_ID': 2026,
        'G_ID': '20260519NCOB0',
        'GAME_INN_NO': 9,
        'GAME_TB_SC_NM': '초',
        'T_P_ID': 66965,
        'T_P_NM': '도태훈',
        'B_P_ID': 65639,
        'B_P_NM': '박정수',
        'BALL_CN': 1,
        'STRIKE_CN': 2,
        'OUT_CN': 1,
      }, fallbackInning: '');

      expect(atBat, isNotNull);
      expect(atBat!.batterName, '도태훈');
      expect(atBat.batterImageUrl, contains('/2026/66965.jpg'));
      expect(atBat.pitcherName, '박정수');
      expect(atBat.pitcherImageUrl, contains('/2026/65639.jpg'));
    },
  );

  test('direct relay classification marks passed ball events', () {
    final repository = KboDirectRepository();

    expect(repository.classifyRelayEventForTesting('3루주자 박해민 : 포일로 홈인'), (
      'PASSED_BALL',
      true,
    ));
    expect(repository.classifyRelayEventForTesting('타자 홍창기 : 포일'), (
      'PASSED_BALL',
      false,
    ));
  });

  test('direct schedule parser preserves rain-cancel status label', () {
    final repository = KboDirectRepository();
    final status = repository.deriveScheduleStatusForTesting(
      '',
      statusText: '우천취소',
    );

    expect(status, 'CANCELLED');
    expect(repository.scheduleStatusLabelForTesting(status, '우천취소'), '우천취소');
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
