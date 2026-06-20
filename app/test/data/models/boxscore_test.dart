import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/data/models/boxscore.dart';

void main() {
  test('0값 투수 placeholder만 있는 팀 박스스코어는 표시 가능한 공식 기록이 아니다', () {
    const team = TeamBoxscoreData(
      teamId: 'KT',
      batters: [],
      pitchers: [
        PitcherRecord(
          name: '선발투수',
          innings: '',
          hits: 0,
          strikeouts: 0,
          walks: 0,
          earnedRuns: 0,
        ),
      ],
    );

    expect(team.hasDisplayableRecords, isFalse);
  });

  test('0값 타자 rows는 이름/타순이 있으면 공식 박스스코어 row로 표시한다', () {
    const team = TeamBoxscoreData(
      teamId: 'KT',
      batters: [
        BatterRecord(
          order: 1,
          position: 'CF',
          name: '타자',
          atBats: 0,
          runs: 0,
          hits: 0,
          rbi: 0,
        ),
      ],
      pitchers: [],
    );

    expect(team.hasDisplayableRecords, isTrue);
  });

  test('이닝이나 누적 지표가 있는 투수 rows는 표시 가능한 공식 기록이다', () {
    const byInnings = PitcherRecord(
      name: '선발투수',
      innings: '1.0',
      hits: 0,
      strikeouts: 0,
      walks: 0,
      earnedRuns: 0,
    );
    const byStats = PitcherRecord(
      name: '불펜투수',
      innings: '',
      hits: 1,
      strikeouts: 0,
      walks: 0,
      earnedRuns: 0,
    );

    expect(byInnings.hasDisplayableLine, isTrue);
    expect(byStats.hasDisplayableLine, isTrue);
  });

  test('live context 투수 row는 공식 누적 지표가 없어도 표시 가능하다', () {
    const team = TeamBoxscoreData(
      teamId: 'LG',
      batters: [],
      pitchers: [
        PitcherRecord(
          name: '임찬규',
          innings: '',
          hits: 0,
          strikeouts: 0,
          walks: 0,
          earnedRuns: 0,
          decision: 'LIVE',
          liveContext: true,
          contextLabel: '3회초 현재 투수',
        ),
      ],
    );

    expect(team.hasDisplayableRecords, isTrue);
  });
}
