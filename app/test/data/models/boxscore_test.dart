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

  test('타자 확장 지표는 알려진 장타 필드에서 파생한다', () {
    const batter = BatterRecord(
      order: 3,
      position: 'DH',
      name: '강백호',
      atBats: 4,
      runs: 2,
      hits: 2,
      rbi: 3,
      doubles: 1,
      triples: 0,
      homeRuns: 1,
      walks: 1,
      hitByPitch: 1,
      strikeouts: 1,
      stolenBases: 0,
    );

    expect(batter.extraBaseHits, 2);
    expect(batter.totalBases, 6);
    expect(batter.slugging, 1.5);

    const unknown = BatterRecord(
      order: 1,
      position: 'CF',
      name: '최원준',
      atBats: 4,
      runs: 0,
      hits: 2,
      rbi: 0,
    );

    expect(unknown.extraBaseHits, isNull);
    expect(unknown.totalBases, isNull);
    expect(unknown.slugging, isNull);
  });

  test('투수 확장 지표는 이닝 텍스트와 공식 누적 지표에서 파생한다', () {
    const pitcher = PitcherRecord(
      name: '김영현',
      innings: '2.0',
      hits: 1,
      strikeouts: 2,
      walks: 1,
      earnedRuns: 1,
      pitchCount: 34,
      runs: 1,
    );

    expect(pitcher.inningsPitched, 2.0);
    expect(pitcher.gameEra, 4.5);
    expect(pitcher.gameWhip, 1.0);

    const oneOut = PitcherRecord(
      name: '불펜',
      innings: '0.1',
      hits: 0,
      strikeouts: 1,
      walks: 0,
      earnedRuns: 0,
    );

    expect(oneOut.inningsPitched, closeTo(1 / 3, 0.0001));
    expect(oneOut.gameEra, 0);
    expect(oneOut.gameWhip, 0);
  });
}
