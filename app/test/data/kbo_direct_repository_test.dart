import 'dart:convert';

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

  test('direct lineup analysis parser preserves live lineup stats', () {
    final repository = KboDirectRepository();
    final lineup = repository.parseLineupAnalysisForTesting(
      '20260611SKLG0',
      [
        [
          {'LINEUP_CK': true},
        ],
        [
          {'T_ID': 'LG'},
        ],
        [
          {'T_ID': 'SK'},
        ],
        [
          _lineupTableJson([
            ['1', '우익수', '홍창기', '0.82'],
            ['2', '중견수', '박해민', '1.02'],
          ]),
        ],
        [
          _lineupTableJson([
            ['1', '유격수', '박성한', '3.62'],
            ['2', '2루수', '정준재', '1.37'],
          ]),
        ],
      ],
      mainGame: {
        'T_PIT_P_ID': 51867,
        'T_PIT_P_NM': '김건우 ',
        'B_PIT_P_ID': 50157,
        'B_PIT_P_NM': '김윤식 ',
      },
    );

    expect(lineup, isNotNull);
    expect(lineup!.away.teamId, 'SK');
    expect(lineup.away.starterId, '51867');
    expect(lineup.away.starterName, '김건우');
    expect(lineup.away.lineup.first.name, '박성한');
    expect(lineup.away.lineup.first.position, 'SS');
    expect(lineup.away.lineup.first.positionKo, '유격수');
    expect(lineup.away.lineup.first.statValue, '3.62');
    expect(lineup.home.teamId, 'LG');
    expect(lineup.home.starterId, '50157');
    expect(lineup.home.starterName, '김윤식');
    expect(lineup.home.lineup.first.name, '홍창기');
    expect(lineup.home.lineup.first.position, 'RF');
    expect(lineup.home.lineup.first.statValue, '0.82');
  });

  test('direct lineup analysis parser returns null before lineup opens', () {
    final repository = KboDirectRepository();

    final lineup = repository.parseLineupAnalysisForTesting('20260612LTLG0', [
      [
        {'LINEUP_CK': false},
      ],
      const [],
      const [],
      const [],
      const [],
    ]);

    expect(lineup, isNull);
  });

  test('direct boxscore parser preserves optional advanced stats', () {
    final repository = KboDirectRepository();

    final boxscore = repository.parseBoxscoreScrollForTesting(
      '20260613KTLG0',
      _boxscorePayload(),
    );

    final batter = boxscore.away.batters.single;
    expect(batter.plateAppearances, 5);
    expect(batter.extraBaseHits, 2);
    expect(batter.totalBases, 6);
    expect(batter.slugging, 1.5);

    final pitcher = boxscore.away.pitchers.single;
    expect(pitcher.pitchCount, 34);
    expect(pitcher.runs, 1);
    expect(pitcher.gameEra, 4.5);
    expect(pitcher.gameWhip, 1.0);
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

String _lineupTableJson(List<List<String>> rows) {
  final tableRows = rows
      .map(
        (row) => {
          'row': [
            for (final value in row) {'Text': value},
          ],
        },
      )
      .toList();
  return jsonEncode({'rows': tableRows});
}

Map<String, dynamic> _boxscorePayload() {
  return {
    'arrHitter': [
      {
        'table1': _tableJson([
          ['3', '지', '강백호'],
        ]),
        'table3': _tableJson(
          [
            [
              '5',
              '4',
              '2',
              '2',
              '1',
              '0',
              '1',
              '3',
              '0',
              '0',
              '1',
              '1',
              '1',
              '0',
            ],
          ],
          headers: [
            '타석',
            '타수',
            '득점',
            '안타',
            '2루타',
            '3루타',
            '홈런',
            '타점',
            '도루',
            '도실',
            '볼넷',
            '사구',
            '삼진',
            '병살',
          ],
        ),
      },
      {'table1': _tableJson([]), 'table3': _tableJson([])},
    ],
    'arrPitcher': [
      {
        'table': _tableJson(
          [
            [
              '김영현',
              '',
              '-',
              '',
              '',
              '',
              '2.0',
              '',
              '34',
              '',
              '1',
              '',
              '1',
              '2',
              '1',
              '1',
            ],
          ],
          headers: [
            '선수명',
            '등판',
            '결과',
            '승',
            '패',
            '세',
            '이닝',
            '타자',
            '투구수',
            '타수',
            '피안타',
            '홈런',
            '4사구',
            '삼진',
            '실점',
            '자책',
          ],
        ),
      },
      {'table': _tableJson([])},
    ],
  };
}

String _tableJson(List<List<String>> rows, {List<String>? headers}) {
  return jsonEncode({
    if (headers != null) 'headers': [_tableRow(headers)],
    'rows': rows.map(_tableRow).toList(),
  });
}

Map<String, dynamic> _tableRow(List<String> row) {
  return {
    'row': [
      for (final value in row) {'Text': value},
    ],
  };
}
