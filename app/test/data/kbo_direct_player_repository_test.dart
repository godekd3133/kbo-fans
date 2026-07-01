import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/data/models/player.dart';
import 'package:kbo_fans/data/models/records_overview.dart';
import 'package:kbo_fans/data/repositories/kbo_direct_player_repository.dart';

void main() {
  test('direct current team player names prefer Korean source names', () {
    final repository = KboDirectPlayerRepository();
    final player = _player(id: '50054', name: 'CHOI Won Jun', number: 61);

    final name = repository.resolveCurrentTeamPlayerDisplayNameForTesting(
      player: player,
      koreanNamesById: const {'50054': '최원준'},
      entryNamesByNumber: const {61: '최원준'},
    );

    expect(name, '최원준');
  });

  test('direct current team player names can fall back to entry number', () {
    final repository = KboDirectPlayerRepository();
    final player = _player(id: 'NO_RECORD_ROW', name: 'KIM Test', number: 7);

    final name = repository.resolveCurrentTeamPlayerDisplayNameForTesting(
      player: player,
      koreanNamesById: const {},
      entryNamesByNumber: const {7: '김테스트'},
    );

    expect(name, '김테스트');
  });

  test('direct player records treat 2001 as unsupported', () async {
    final repository = KboDirectPlayerRepository();

    expect(
      repository.isSupportedOfficialPlayerRecordSeasonForTesting(2001),
      isFalse,
    );
    expect(
      repository.isSupportedOfficialPlayerRecordSeasonForTesting(2002),
      isTrue,
    );

    final overview = await repository.getRecordsOverview(season: 2001);
    final leaderboard = await repository.getLeaderboard(
      season: 2001,
      metric: LeaderboardMetric.avg,
    );
    final players = await repository.getTeamPlayers('LG', season: 2001);
    final stats = await repository.getTeamStats('LG', season: 2001);

    expect(overview.avgLeaders, isEmpty);
    expect(overview.hrLeaders, isEmpty);
    expect(overview.opsLeaders, isEmpty);
    expect(overview.opsPlusLeaders, isEmpty);
    expect(overview.eraLeaders, isEmpty);
    expect(leaderboard, isEmpty);
    expect(players, isEmpty);
    expect(stats.season, 2001);
    expect(stats.hitting, isEmpty);
    expect(stats.pitching, isEmpty);
  });

  test(
    'direct player detail uses current KBO season when recent page omits season label',
    () {
      final repository = KboDirectPlayerRepository();

      final recentGames = repository.parseRecentGamesForTesting(
        html: _currentPlayerDetailHtmlWithoutSeasonLabel,
        season: 2026,
        playerType: PlayerType.hitter,
        now: DateTime.utc(2026, 5, 20),
      );

      expect([for (final game in recentGames) game.date], ['06.28', '06.27']);
      expect(recentGames.first.summary, 'AVG 0.500 · H 2 · HR 1 · RBI 1');
    },
  );

  test('direct player detail treats pitcher profile on hitter page as pitcher', () {
    final repository = KboDirectPlayerRepository();

    final playerType = repository.resolveDetailPlayerTypeForTesting(
      html: _pitcherProfileHtml,
      requestedType: PlayerType.hitter,
    );

    expect(playerType, PlayerType.pitcher);
  });
}

const _currentPlayerDetailHtmlWithoutSeasonLabel = '''
<span id="lblName">김도영</span>
<span id="lblBackNo">5</span>
<span id="lblBirthday">2003-10-02</span>
<span id="lblPosition">내야수(우투우타)</span>
<span id="lblHeightWeight">183cm/85kg</span>
<span id="lblCareer">동성고</span>
<h6>최근 10경기</h6>
<div class="tbl-type02 mb35">
  <table class="tbl tt">
    <tbody>
      <tr>
        <td>06.28</td><td>두산</td><td>0.500</td><td>4</td><td>4</td>
        <td>1</td><td>2</td><td>0</td><td>0</td><td>1</td><td>1</td>
      </tr>
      <tr>
        <td>06.27</td><td>두산</td><td>0.000</td><td>4</td><td>4</td>
        <td>0</td><td>0</td><td>0</td><td>0</td><td>0</td><td>0</td>
      </tr>
    </tbody>
  </table>
</div>
''';

const _pitcherProfileHtml = '''
<span id="lblName">이민호</span>
<span id="lblBackNo">26</span>
<span id="lblBirthday">2001-08-30</span>
<span id="lblPosition">투수(우투우타)</span>
<span id="lblHeightWeight">189cm/93kg</span>
<span id="lblCareer">휘문고</span>
''';

PlayerProfile _player({
  required String id,
  required String name,
  required int number,
}) {
  return PlayerProfile(
    id: id,
    teamId: 'KT',
    playerType: PlayerType.hitter,
    imageUrl: null,
    name: name,
    number: number,
    position: 'OF',
    roleLabel: 'OF',
    handedness: '',
    heightWeight: '',
    birthDate: '',
    status: PlayerAvailabilityStatus.available,
    rosterGroup: PlayerRosterGroup.entry,
    headlineStat: '',
    secondaryStat: '',
    seasonStats: const [],
    highlights: const [],
    recentGames: const [],
  );
}
