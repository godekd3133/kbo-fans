import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/data/models/records_overview.dart';

void main() {
  test('OPS 리더보드에서 호환 키를 유지한 상대지수를 계산한다', () {
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
    expect(opsPlusLeaders[0].metricKey, 'OPSPLUS');
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

  test('OPS 기반 상대 리더보드는 앱 계산 참고값으로 설명한다', () {
    expect(LeaderboardMetric.opsPlus.key, 'opsPlus');
    expect(LeaderboardMetric.opsPlus.title, '리그 OPS 상대지수 리더보드');
    expect(LeaderboardMetric.opsPlus.shortLabel, 'OPS 상대지수');
    expect(LeaderboardMetric.opsPlus.sourceBadgeLabel, '앱 계산');
    expect(LeaderboardMetric.opsPlus.isAppCalculated, isTrue);
    expect(
      LeaderboardMetric.opsPlus.supportedByOfficialSource,
      isTrue,
      reason: '기존 provider availability gate를 통과해 opsPlus 데이터를 계속 로드해야 한다.',
    );
    expect(LeaderboardMetric.opsPlus.disclosure, opsRelativeIndexDisclosure);
  });

  test('첫 화면 지표 라벨은 영문 약어와 한국어 의미를 함께 제공한다', () {
    expect(LeaderboardMetric.avg.explainedLabel, '타율 AVG');
    expect(LeaderboardMetric.hr.explainedLabel, '홈런 HR');
    expect(LeaderboardMetric.ops.explainedLabel, '출루·장타 OPS');
    expect(LeaderboardMetric.era.explainedLabel, '평균자책 ERA');
    expect(LeaderboardMetric.wins.explainedLabel, '다승 W');
    expect(LeaderboardMetric.saves.explainedLabel, '세이브 SV');
    expect(LeaderboardMetric.strikeouts.explainedLabel, '탈삼진 SO');
  });
}
