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
        isRetired: true,
      ),
    ];

    final opsPlusLeaders = computeOpsPlusLeaders(leaders);

    expect(opsPlusLeaders.length, 2);
    expect(opsPlusLeaders[0].name, 'A');
    expect(opsPlusLeaders[0].value, '111');
    expect(opsPlusLeaders[1].name, 'B');
    expect(opsPlusLeaders[1].value, '89');
    expect(opsPlusLeaders[1].isRetired, isTrue);
  });

  test('과거 시즌 선수 이미지는 2022 CDN 폴더를 사용한다', () {
    expect(kboPlayerImageSeason(2013), 2022);
    expect(
      kboPlayerImageUrl(season: 2013, playerId: '77532'),
      'https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/person/middle/2022/77532.jpg',
    );
  });

  test('OPS 기반 상대 리더보드 표시 라벨은 wRC+를 사용한다', () {
    expect(LeaderboardMetric.opsPlus.title, '리그 wRC+ 리더보드');
    expect(LeaderboardMetric.opsPlus.shortLabel, 'wRC+');
  });
}
