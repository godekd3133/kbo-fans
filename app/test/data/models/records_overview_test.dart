import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/data/models/records_overview.dart';

void main() {
  test('OPS 리더보드에서 OPS+를 계산한다', () {
    const leaders = [
      RecordLeader(
        rank: 1,
        playerId: 'p1',
        playerType: 'hitter',
        name: 'A',
        teamId: 'LG',
        value: '1.000',
      ),
      RecordLeader(
        rank: 2,
        playerId: 'p2',
        playerType: 'hitter',
        name: 'B',
        teamId: 'KT',
        value: '0.800',
      ),
    ];

    final opsPlusLeaders = computeOpsPlusLeaders(leaders);

    expect(opsPlusLeaders.length, 2);
    expect(opsPlusLeaders[0].name, 'A');
    expect(opsPlusLeaders[0].value, '111');
    expect(opsPlusLeaders[1].name, 'B');
    expect(opsPlusLeaders[1].value, '89');
  });
}
