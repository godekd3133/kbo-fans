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
    expect(aggregate.kboBrief?.title, '오늘의 KBO 관전 포인트');
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
}
