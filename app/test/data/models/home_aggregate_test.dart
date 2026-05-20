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
  });
}
