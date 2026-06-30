import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/models/home_aggregate.dart';
import 'package:kbo_fans/data/models/records_overview.dart';
import 'package:kbo_fans/data/models/schedule.dart';

void main() {
  test('home run quick item carries player image and detail route', () {
    final aggregate = buildLocalHomeAggregate(
      date: '2026-05-20',
      myTeam: null,
      games: const [],
      scheduleDays: const [],
      standings: const [],
      overview: const RecordsOverview(
        season: 2026,
        avgLeaders: [],
        hrLeaders: [
          RecordLeader(
            rank: 1,
            playerId: '52605',
            playerType: 'hitter',
            name: '김도영',
            teamId: 'HT',
            value: '13',
          ),
        ],
        opsLeaders: [],
        opsPlusLeaders: [],
        eraLeaders: [],
        todayHitter: FeaturedPlayerCard(label: 'today hitter'),
        todayPitcher: FeaturedPlayerCard(label: 'today pitcher'),
        monthHitter: FeaturedPlayerCard(label: 'month hitter'),
        monthPitcher: FeaturedPlayerCard(label: 'month pitcher'),
      ),
    );

    final item = aggregate.quickItems.single;

    expect(item.title, '김도영 13개');
    expect(item.route, '/records/player/52605?season=2026');
    expect(item.imageUrl, endsWith('/2026/52605.jpg'));
    expect(aggregate.kboBrief?.title, '이번 주 KBO 포인트');
    expect(aggregate.kboBrief?.items.single.title, '김도영 13홈런');
    expect(
      aggregate.kboBrief?.items.single.imageUrl,
      endsWith('/2026/52605.jpg'),
    );
    expect(aggregate.kboBrief?.items.single.fallbackLabel, '김도영');
  });

  test('local quick items include hitter and pitcher brief cards together', () {
    final aggregate = buildLocalHomeAggregate(
      date: '2026-06-30',
      myTeam: null,
      games: const [],
      scheduleDays: const [],
      standings: const [],
      overview: const RecordsOverview(
        season: 2026,
        avgLeaders: [],
        hrLeaders: [],
        opsLeaders: [],
        opsPlusLeaders: [],
        eraLeaders: [],
        todayHitter: FeaturedPlayerCard(
          label: '오늘의 타자',
          playerId: '64166',
          name: '홍창기',
          teamId: 'LG',
          headline: '타율 1위',
        ),
        todayPitcher: FeaturedPlayerCard(
          label: '오늘의 투수',
          playerId: '50126',
          name: '폰세',
          teamId: 'HH',
          headline: 'ERA 1위',
        ),
        monthHitter: FeaturedPlayerCard(label: 'month hitter'),
        monthPitcher: FeaturedPlayerCard(label: 'month pitcher'),
      ),
    );

    expect(
      aggregate.quickItems.map((item) => item.title),
      containsAll(['홍창기', '폰세']),
    );
    expect(aggregate.quickItems.length, 2);
  });

  test('off-day KBO brief opens schedule instead of generic records', () {
    final aggregate = buildLocalHomeAggregate(
      date: '2026-06-20',
      myTeam: null,
      games: const [],
      scheduleDays: const [],
      standings: const [],
      overview: const RecordsOverview(
        season: 2026,
        avgLeaders: [],
        hrLeaders: [],
        opsLeaders: [],
        opsPlusLeaders: [],
        eraLeaders: [],
        todayHitter: FeaturedPlayerCard(label: 'today hitter'),
        todayPitcher: FeaturedPlayerCard(label: 'today pitcher'),
        monthHitter: FeaturedPlayerCard(label: 'month hitter'),
        monthPitcher: FeaturedPlayerCard(label: 'month pitcher'),
      ),
    );

    final item = aggregate.kboBrief!.items.single;

    expect(item.type, 'offday');
    expect(item.title, '오늘은 KBO 경기가 없습니다');
    expect(item.route, '/schedule');
  });

  test('local home aggregate keeps every standings row in rank order', () {
    final aggregate = buildLocalHomeAggregate(
      date: '2026-06-20',
      myTeam: 'LG',
      games: const [],
      scheduleDays: const [],
      standings: const [
        TeamStanding(
          rank: 6,
          teamId: 'LG',
          teamName: 'LG 트윈스',
          wins: 24,
          losses: 24,
          draws: 2,
          pct: '.500',
          gb: '7.0',
        ),
        TeamStanding(
          rank: 1,
          teamId: 'HT',
          teamName: 'KIA 타이거즈',
          wins: 31,
          losses: 17,
          draws: 2,
          pct: '.646',
          gb: '-',
        ),
        TeamStanding(
          rank: 2,
          teamId: 'OB',
          teamName: '두산 베어스',
          wins: 30,
          losses: 18,
          draws: 2,
          pct: '.625',
          gb: '1.0',
        ),
        TeamStanding(
          rank: 3,
          teamId: 'SS',
          teamName: '삼성 라이온즈',
          wins: 28,
          losses: 20,
          draws: 2,
          pct: '.583',
          gb: '3.0',
        ),
        TeamStanding(
          rank: 4,
          teamId: 'SK',
          teamName: 'SSG 랜더스',
          wins: 27,
          losses: 21,
          draws: 2,
          pct: '.563',
          gb: '4.0',
        ),
        TeamStanding(
          rank: 5,
          teamId: 'NC',
          teamName: 'NC 다이노스',
          wins: 26,
          losses: 22,
          draws: 2,
          pct: '.542',
          gb: '5.0',
        ),
      ],
      overview: _emptyOverview(),
    );

    expect(aggregate.standingsPreview.map((standing) => standing.teamId), [
      'HT',
      'OB',
      'SS',
      'SK',
      'NC',
      'LG',
    ]);
  });

  test('local KBO brief puts league game ahead of my-team duplicate', () {
    final aggregate = buildLocalHomeAggregate(
      date: '2026-05-20',
      myTeam: 'LG',
      games: const [
        Game(
          gameId: '20260520HTLG0',
          status: GameStatus.live,
          inning: '8회말',
          away: TeamScore(
            teamId: 'HT',
            teamName: 'KIA 타이거즈',
            shortName: 'KIA',
            score: 3,
            innings: [],
          ),
          home: TeamScore(
            teamId: 'LG',
            teamName: 'LG 트윈스',
            shortName: 'LG',
            score: 3,
            innings: [],
          ),
          stadium: '잠실',
          startTime: '18:30',
        ),
        Game(
          gameId: '20260520NCOB0',
          status: GameStatus.live,
          inning: '7회초',
          away: TeamScore(
            teamId: 'NC',
            teamName: 'NC 다이노스',
            shortName: 'NC',
            score: 9,
            innings: [],
          ),
          home: TeamScore(
            teamId: 'OB',
            teamName: '두산 베어스',
            shortName: '두산',
            score: 7,
            innings: [],
          ),
          stadium: '창원',
          startTime: '18:30',
        ),
      ],
      scheduleDays: const [],
      standings: const [],
      overview: const RecordsOverview(
        season: 2026,
        avgLeaders: [],
        hrLeaders: [],
        opsLeaders: [],
        opsPlusLeaders: [],
        eraLeaders: [],
        todayHitter: FeaturedPlayerCard(label: 'today hitter'),
        todayPitcher: FeaturedPlayerCard(label: 'today pitcher'),
        monthHitter: FeaturedPlayerCard(label: 'month hitter'),
        monthPitcher: FeaturedPlayerCard(label: 'month pitcher'),
      ),
    );

    final firstItem = aggregate.kboBrief!.items.first;

    expect(aggregate.kboBrief!.title, '지금 KBO');
    expect(firstItem.route, '/game/20260520NCOB0');
    expect(firstItem.teamIds, isNot(contains('LG')));
  });

  test('scheduled zero score is not treated as a recent draw', () {
    final aggregate = buildLocalHomeAggregate(
      date: '2026-05-20',
      myTeam: 'LG',
      games: const [
        Game(
          gameId: '20260520OBLG0',
          status: GameStatus.scheduled,
          inning: '18:30 예정',
          away: TeamScore(
            teamId: 'OB',
            teamName: '두산 베어스',
            shortName: '두산',
            score: 0,
            innings: [],
          ),
          home: TeamScore(
            teamId: 'LG',
            teamName: 'LG 트윈스',
            shortName: 'LG',
            score: 0,
            innings: [],
          ),
          stadium: '잠실',
          startTime: '18:30',
        ),
      ],
      scheduleDays: const [
        ScheduleDay(
          date: '2026-05-18',
          games: [
            ScheduleGame(
              gameId: '20260518OBLG0',
              time: '18:30',
              awayId: 'OB',
              awayName: '두산',
              awayScore: 2,
              homeId: 'LG',
              homeName: 'LG',
              homeScore: 5,
              stadium: '잠실',
              status: 'FINAL',
            ),
          ],
        ),
        ScheduleDay(
          date: '2026-05-20',
          games: [
            ScheduleGame(
              gameId: '20260520OBLG0',
              time: '18:30',
              awayId: 'OB',
              awayName: '두산',
              awayScore: 0,
              homeId: 'LG',
              homeName: 'LG',
              homeScore: 0,
              stadium: '잠실',
              status: 'SCHEDULED',
            ),
          ],
        ),
      ],
      standings: const [],
      overview: const RecordsOverview(
        season: 2026,
        avgLeaders: [],
        hrLeaders: [],
        opsLeaders: [],
        opsPlusLeaders: [],
        eraLeaders: [],
        todayHitter: FeaturedPlayerCard(label: 'today hitter'),
        todayPitcher: FeaturedPlayerCard(label: 'today pitcher'),
        monthHitter: FeaturedPlayerCard(label: 'month hitter'),
        monthPitcher: FeaturedPlayerCard(label: 'month pitcher'),
      ),
    );

    final brief = aggregate.myTeamBrief!;

    expect(brief.recentGamesCount, 1);
    expect(brief.recentWins, 1);
    expect(brief.recentDraws, 0);
    expect(brief.recentSummaries.single.score, '5:2');
    expect(aggregate.quickItems.first.title, '두산 vs LG');
    expect(aggregate.kboBrief?.title, 'KBO 소식');
    expect(aggregate.kboBrief?.items.first.title, '두산 vs LG');
  });

  test(
    'local KBO brief does not treat missing hit totals as high-hit game',
    () {
      final aggregate = buildLocalHomeAggregate(
        date: '2026-05-20',
        myTeam: null,
        games: const [
          Game(
            gameId: '20260520OBSS0',
            status: GameStatus.live,
            inning: '8회초',
            away: TeamScore(
              teamId: 'OB',
              teamName: '두산 베어스',
              shortName: '두산',
              score: 5,
              innings: [],
              hits: 11,
              hasStats: false,
            ),
            home: TeamScore(
              teamId: 'SS',
              teamName: '삼성 라이온즈',
              shortName: '삼성',
              score: 4,
              innings: [],
              hits: 8,
              hasStats: false,
            ),
            stadium: '대구',
            startTime: '18:30',
          ),
        ],
        scheduleDays: const [],
        standings: const [],
        overview: const RecordsOverview(
          season: 2026,
          avgLeaders: [],
          hrLeaders: [],
          opsLeaders: [],
          opsPlusLeaders: [],
          eraLeaders: [],
          todayHitter: FeaturedPlayerCard(label: 'today hitter'),
          todayPitcher: FeaturedPlayerCard(label: 'today pitcher'),
          monthHitter: FeaturedPlayerCard(label: 'month hitter'),
          monthPitcher: FeaturedPlayerCard(label: 'month pitcher'),
        ),
      );

      final titles = aggregate.kboBrief!.items
          .map((item) => item.title)
          .toList();
      final highHitItems = aggregate.kboBrief!.items.where(
        (item) => item.type == 'player_performance',
      );

      expect(titles, isNot(contains('두산-삼성 합계 19안타')));
      expect(highHitItems, isEmpty);
    },
  );

  test('local KBO brief surfaces high-error game', () {
    final aggregate = buildLocalHomeAggregate(
      date: '2026-06-29',
      myTeam: null,
      games: const [
        Game(
          gameId: '20260629OBLG0',
          status: GameStatus.final_,
          inning: '경기종료',
          away: TeamScore(
            teamId: 'OB',
            teamName: '두산 베어스',
            shortName: '두산',
            score: 4,
            innings: [],
            hits: 8,
            errors: 3,
          ),
          home: TeamScore(
            teamId: 'LG',
            teamName: 'LG 트윈스',
            shortName: 'LG',
            score: 6,
            innings: [],
            hits: 10,
            errors: 2,
          ),
          stadium: '잠실',
          startTime: '18:30',
        ),
      ],
      scheduleDays: const [],
      standings: const [],
      overview: _emptyOverview(),
    );

    final defenseItems = aggregate.kboBrief!.items.where(
      (item) => item.type == 'defense_issue',
    );

    expect(defenseItems, isNotEmpty);
    expect(defenseItems.first.eyebrow, '실책 많은 경기');
    expect(defenseItems.first.title, '두산-LG 합계 5실책');
    expect(defenseItems.first.subtitle, '두산 3실책 · LG 2실책');
    expect(defenseItems.first.route, '/game/20260629OBLG0');
  });

  test('local KBO brief surfaces team error rank for day', () {
    final aggregate = buildLocalHomeAggregate(
      date: '2026-06-29',
      myTeam: null,
      games: const [
        Game(
          gameId: '20260629OBLG0',
          status: GameStatus.final_,
          inning: '경기종료',
          away: TeamScore(
            teamId: 'OB',
            teamName: '두산 베어스',
            shortName: '두산',
            score: 4,
            innings: [],
            errors: 3,
          ),
          home: TeamScore(
            teamId: 'LG',
            teamName: 'LG 트윈스',
            shortName: 'LG',
            score: 6,
            innings: [],
            errors: 2,
          ),
          stadium: '잠실',
          startTime: '18:30',
        ),
        Game(
          gameId: '20260629HTSS0',
          status: GameStatus.final_,
          inning: '경기종료',
          away: TeamScore(
            teamId: 'HT',
            teamName: 'KIA 타이거즈',
            shortName: 'KIA',
            score: 5,
            innings: [],
            errors: 1,
          ),
          home: TeamScore(
            teamId: 'SS',
            teamName: '삼성 라이온즈',
            shortName: '삼성',
            score: 3,
            innings: [],
          ),
          stadium: '대구',
          startTime: '18:30',
        ),
      ],
      scheduleDays: const [],
      standings: const [],
      overview: _emptyOverview(),
    );

    final rankItems = aggregate.kboBrief!.items.where(
      (item) => item.type == 'defense_rank',
    );

    expect(rankItems, isNotEmpty);
    expect(rankItems.first.eyebrow, '팀별 실책');
    expect(rankItems.first.title, '두산 3개 · LG 2개');
    expect(rankItems.first.subtitle, '6월 29일 경기 기준 · 실책 많은 팀 순');
    expect(rankItems.first.route, '/schedule');
  });

  test('local KBO brief uses batting average leader when available', () {
    final aggregate = buildLocalHomeAggregate(
      date: '2026-06-30',
      myTeam: null,
      games: const [],
      scheduleDays: const [],
      standings: const [],
      overview: const RecordsOverview(
        season: 2026,
        avgLeaders: [
          RecordLeader(
            rank: 1,
            playerId: '64166',
            playerType: 'hitter',
            name: '홍창기',
            teamId: 'LG',
            value: '0.351',
          ),
        ],
        hrLeaders: [],
        opsLeaders: [],
        opsPlusLeaders: [],
        eraLeaders: [],
        todayHitter: FeaturedPlayerCard(label: 'today hitter'),
        todayPitcher: FeaturedPlayerCard(label: 'today pitcher'),
        monthHitter: FeaturedPlayerCard(label: 'month hitter'),
        monthPitcher: FeaturedPlayerCard(label: 'month pitcher'),
      ),
    );

    final avgItems = aggregate.kboBrief!.items.where(
      (item) => item.type == 'batting_leader',
    );

    expect(avgItems, isNotEmpty);
    expect(avgItems.first.eyebrow, '6월 현재 타율');
    expect(avgItems.first.title, '홍창기 타율 0.351');
    expect(avgItems.first.route, '/records/player/64166?season=2026');
    expect(avgItems.first.imageUrl, endsWith('/2026/64166.jpg'));
  });

  test('local KBO brief surfaces my-team record milestone', () {
    final aggregate = buildLocalHomeAggregate(
      date: '2026-07-01',
      myTeam: 'HT',
      games: const [],
      scheduleDays: const [],
      standings: const [],
      overview: const RecordsOverview(
        season: 2026,
        avgLeaders: [],
        hrLeaders: [],
        opsLeaders: [],
        opsPlusLeaders: [],
        eraLeaders: [],
        milestoneLeaders: [
          RecordLeader(
            rank: 3,
            playerId: '78224',
            playerType: 'hitter',
            metricKey: 'TB',
            name: '최형우',
            teamId: 'HT',
            value: '2000',
            milestoneLabel: '2000루타',
            allTimeRank: 3,
          ),
        ],
        todayHitter: FeaturedPlayerCard(label: 'today hitter'),
        todayPitcher: FeaturedPlayerCard(label: 'today pitcher'),
        monthHitter: FeaturedPlayerCard(label: 'month hitter'),
        monthPitcher: FeaturedPlayerCard(label: 'month pitcher'),
      ),
    );

    final milestoneItems = aggregate.kboBrief!.items.where(
      (item) => item.type == 'record_milestone',
    );

    expect(milestoneItems, isNotEmpty);
    expect(milestoneItems.first.eyebrow, '기록 달성');
    expect(milestoneItems.first.title, '최형우 2000루타 달성');
    expect(milestoneItems.first.subtitle, 'KIA · 역대 3번째');
    expect(milestoneItems.first.route, '/records/player/78224?season=2026');
    expect(milestoneItems.first.teamIds, ['HT']);
  });
}

RecordsOverview _emptyOverview() {
  return const RecordsOverview(
    season: 2026,
    avgLeaders: [],
    hrLeaders: [],
    opsLeaders: [],
    opsPlusLeaders: [],
    eraLeaders: [],
    todayHitter: FeaturedPlayerCard(label: 'today hitter'),
    todayPitcher: FeaturedPlayerCard(label: 'today pitcher'),
    monthHitter: FeaturedPlayerCard(label: 'month hitter'),
    monthPitcher: FeaturedPlayerCard(label: 'month pitcher'),
  );
}
