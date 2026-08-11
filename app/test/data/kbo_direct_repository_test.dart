import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/repositories/kbo_direct_repository.dart';

void main() {
  test('direct relay rejects missing credentials before network access', () {
    final repository = KboDirectRepository(relayUserId: '', relayPassword: '');

    expect(
      repository.validateRelayCredentialsForTesting,
      throwsA(isA<StateError>()),
    );
  });

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

  test(
    'direct relay current at-bat parser applies today results to batting average and preserves ERA',
    () {
      final atBat = KboDirectRepository().parseCurrentAtBatHtmlForTesting('''
      <div class="playerBox awayBox">
        <div class="batter">
          <div class="player-info-wrap">
            <strong class="who">삼성<br><span class="no">No.61 디아즈</span><span>(좌타)</span></strong>
            <p class="today"><span>땅볼|4구|2루타|</span></p>
          </div>
          <table>
            <thead><tr><th>2026</th><th>타수</th><th>안타</th><th>타율</th><th>타점</th></tr></thead>
            <tbody><tr><th>시즌</th><td>100</td><td>24</td><td>0.240</td><td>31</td></tr></tbody>
          </table>
        </div>
      </div>
      <div class="playerBox homeBox">
        <div class="pitcher">
          <div class="player-info-wrap">
            <strong class="who">한화<br><span class="no">No.68 박준영</span><span>(우투)</span></strong>
            <p class="today"><span>38투구 | 13B | 25S</span></p>
          </div>
          <table>
            <thead><tr><th>2026</th><th>ERA</th><th>경기</th></tr></thead>
            <tbody><tr><th>시즌</th><td>4.13</td><td>7</td></tr></tbody>
          </table>
        </div>
      </div>
      <p class="present">
        <span class="base">
          <strong>2회 초</strong>
          <img id="imgThisGameBase" src="//example.com/ground_base2.png" alt="주자">
          <strong>1-2 2out</strong>
        </span>
      </p>
      <div class="playerName">
        <ul>
          <li class="pitcher">박준영</li>
          <li class="supervision2">디아즈</li>
        </ul>
      </div>
    ''');

      expect(atBat, isNotNull);
      expect(atBat!.batterName, '디아즈');
      expect(atBat.batterRecent, '땅볼|4구|2루타|');
      expect(atBat.batterAverage, '0.245');
      expect(atBat.pitcherName, '박준영');
      expect(atBat.pitcherEra, '4.13');
      expect(atBat.pitchCount, 38);
      expect(atBat.baseState, '주자2루');
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

  test('direct standings parser preserves streak column', () {
    final repository = KboDirectRepository();
    final standings = repository.parseStandingsHtmlForTesting('''
      <table>
        <thead>
          <tr>
            <th>순위</th><th>팀명</th><th>경기</th><th>승</th><th>패</th>
            <th>무</th><th>승률</th><th>게임차</th><th>최근10경기</th>
            <th>연속</th><th>홈</th><th>방문</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>1</td><td>LG</td><td>43</td><td>25</td><td>17</td>
            <td>1</td><td>0.595</td><td>0</td><td>7승0무3패</td>
            <td>3승</td><td>13-1-9</td><td>12-0-8</td>
          </tr>
        </tbody>
      </table>
    ''');

    expect(standings.single.streak, '3승');
    expect(standings.single.streakLabel, '3연승');
  });

  test('direct standings annual request posts the requested WebForms season', () {
    final repository = KboDirectRepository();
    final payload = repository.buildStandingsFormPayloadForTesting('''
      <input type="hidden" name="__VIEWSTATE" value="state-token" />
      <select name="ctl00\$ctl00\$ctl00\$cphContents\$cphContents\$cphContents\$ddlYear">
        <option value="2026" selected="selected">2026</option>
        <option value="2025">2025</option>
      </select>
      <select name="series"><option value="0" selected="selected">정규</option></select>
    ''', 2025);

    expect(payload['__VIEWSTATE'], 'state-token');
    expect(
      payload['__EVENTTARGET'],
      'ctl00\$ctl00\$ctl00\$cphContents\$cphContents\$cphContents\$ddlYear',
    );
    expect(
      payload['ctl00\$ctl00\$ctl00\$cphContents\$cphContents\$cphContents\$ddlYear'],
      '2025',
    );
    expect(payload['series'], '0');
  });

  test(
    'direct standings rejects a response relabelled from another season',
    () {
      const response = '''
      <select name="ctl00\$ctl00\$ctl00\$cphContents\$cphContents\$cphContents\$ddlYear">
        <option value="2026" selected="selected">2026</option>
        <option value="2025">2025</option>
      </select>
      <input type="hidden" name="ctl00\$ctl00\$ctl00\$cphContents\$cphContents\$cphContents\$hfSearchYear" value="2026" />
      <input type="hidden" name="ctl00\$ctl00\$ctl00\$cphContents\$cphContents\$cphContents\$hfSearchDate" value="20261231" />
    ''';

      expect(
        () => KboDirectRepository().validateStandingsSourceForTesting(
          response,
          2025,
        ),
        throwsStateError,
      );
    },
  );

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
