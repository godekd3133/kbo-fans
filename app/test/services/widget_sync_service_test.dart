import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/services/widget_sync_service.dart';

void main() {
  group('widget my team storage', () {
    test('encodes missing my team as an empty property-list-safe string', () {
      expect(encodeWidgetMyTeamIdForStorage(null), '');
    });

    test('decodes missing stored my team values back to null', () {
      expect(decodeWidgetMyTeamIdFromStorage(null), isNull);
      expect(decodeWidgetMyTeamIdFromStorage(''), isNull);
    });

    test('preserves selected my team ids', () {
      expect(encodeWidgetMyTeamIdForStorage('LG'), 'LG');
      expect(decodeWidgetMyTeamIdFromStorage('LG'), 'LG');
    });
  });

  test('widget title normalizes KBO team IDs', () {
    final title = buildWidgetGameTitleForTesting(
      const Game(
        gameId: '20260624SSSK0',
        status: GameStatus.live,
        inning: '7회말',
        away: TeamScore(
          teamId: 'SS',
          teamName: '삼성 라이온즈',
          shortName: 'SS',
          score: 4,
          innings: [],
        ),
        home: TeamScore(
          teamId: 'SK',
          teamName: 'SSG 랜더스',
          shortName: 'SK',
          score: 3,
          innings: [],
        ),
        stadium: '대구',
        startTime: '18:30',
      ),
    );

    expect(title, '삼성 vs SSG');
  });

  test('widget target falls back to scheduled my-team game', () {
    final selected = selectWidgetGameIdForTesting(
      games: const [
        Game(
          gameId: '20260630SSSK0',
          status: GameStatus.scheduled,
          inning: '',
          away: TeamScore(
            teamId: 'SS',
            teamName: '삼성 라이온즈',
            shortName: 'SS',
            score: 0,
            innings: [],
          ),
          home: TeamScore(
            teamId: 'SK',
            teamName: 'SSG 랜더스',
            shortName: 'SK',
            score: 0,
            innings: [],
          ),
          stadium: '대구',
          startTime: '18:30',
        ),
        Game(
          gameId: '20260630LGKT0',
          status: GameStatus.scheduled,
          inning: '',
          away: TeamScore(
            teamId: 'LG',
            teamName: 'LG 트윈스',
            shortName: 'LG',
            score: 0,
            innings: [],
          ),
          home: TeamScore(
            teamId: 'KT',
            teamName: 'KT 위즈',
            shortName: 'KT',
            score: 0,
            innings: [],
          ),
          stadium: '잠실',
          startTime: '18:30',
        ),
      ],
      myTeamId: 'LG',
    );

    expect(selected, '20260630LGKT0');
  });

  test(
    'widget summary lines place selected game first and normalize labels',
    () {
      final lines = buildWidgetSummaryLinesForTesting(
        games: const [
          Game(
            gameId: '20260630SSSK0',
            status: GameStatus.live,
            inning: '7회말',
            away: TeamScore(
              teamId: 'SS',
              teamName: '삼성 라이온즈',
              shortName: 'SS',
              score: 4,
              innings: [],
            ),
            home: TeamScore(
              teamId: 'SK',
              teamName: 'SSG 랜더스',
              shortName: 'SK',
              score: 3,
              innings: [],
            ),
            stadium: '대구',
            startTime: '18:30',
          ),
          Game(
            gameId: '20260630LGKT0',
            status: GameStatus.scheduled,
            inning: '',
            away: TeamScore(
              teamId: 'LG',
              teamName: 'LG 트윈스',
              shortName: 'LG',
              score: 0,
              innings: [],
            ),
            home: TeamScore(
              teamId: 'KT',
              teamName: 'KT 위즈',
              shortName: 'KT',
              score: 0,
              innings: [],
            ),
            stadium: '잠실',
            startTime: '18:30',
          ),
        ],
        myTeamId: 'LG',
      );

      expect(lines.first, '삼성 4:3 SSG · 7회말');
      expect(lines[1], 'LG vs KT · 18:30 예정');
    },
  );
}
