import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/data/models/player.dart';
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
}

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
