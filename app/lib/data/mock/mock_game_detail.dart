import '../models/relay.dart';
import '../models/boxscore.dart';

const mockCurrentAtBat = CurrentAtBat(
  batterName: '이정훈', batterNumber: 33, batterHand: '좌타',
  pitcherName: '이정용', pitcherNumber: 31, pitcherHand: '우투',
  pitchCount: 19, balls: 3, strikes: 2, outs: 2,
);

final mockRelayItems = <RelayItem>[
  RelayItem(seqNo: 142, inning: 4, half: 'top', event: 'HIT', isScoring: true, text: '6번 이강민: 2타점 적시타!', pitchSequence: 'S→B→B→S→F→타격'),
  RelayItem(seqNo: 141, inning: 4, half: 'top', event: 'WALK', text: '5번 김민수: 볼넷 출루', pitchSequence: 'B→S→B→B→B'),
  RelayItem(seqNo: 140, inning: 4, half: 'top', event: 'OUT', text: '4번 박찬호: 좌익수 플라이 아웃', pitchSequence: 'S→F→타격'),
  RelayItem(seqNo: 139, inning: 4, half: 'top', event: 'INNING_CHANGE', text: '4회초 시작'),
  RelayItem(seqNo: 138, inning: 3, half: 'bottom', event: 'HIT', isScoring: true, text: '3번 오지환: 솔로 홈런! (시즌 1호)', pitchSequence: 'S→타격'),
  RelayItem(seqNo: 137, inning: 3, half: 'bottom', event: 'OUT', text: '2번 김현수: 삼진 아웃', pitchSequence: 'S→B→S→F→S'),
  RelayItem(seqNo: 136, inning: 3, half: 'bottom', event: 'HIT', isScoring: true, text: '1번 박해민: 적시타! (1타점)', pitchSequence: 'B→S→타격'),
  RelayItem(seqNo: 135, inning: 3, half: 'bottom', event: 'WALK', text: '9번 정주현: 볼넷 출루', pitchSequence: 'B→B→S→B→B'),
  RelayItem(seqNo: 134, inning: 3, half: 'bottom', event: 'INNING_CHANGE', text: '3회말 시작'),
];

const mockAwayBatters = <BatterRecord>[
  BatterRecord(order: 1, position: '중', name: '최원준', atBats: 5, runs: 1, hits: 2, rbi: 0),
  BatterRecord(order: 2, position: '1', name: '김현수', atBats: 4, runs: 1, hits: 1, rbi: 2),
  BatterRecord(order: 3, position: '지', name: '강백호', atBats: 4, runs: 2, hits: 2, rbi: 3),
  BatterRecord(order: 4, position: '좌', name: '박찬호', atBats: 4, runs: 0, hits: 1, rbi: 0),
  BatterRecord(order: 5, position: '3', name: '김민수', atBats: 3, runs: 1, hits: 1, rbi: 0),
  BatterRecord(order: 6, position: '유', name: '이강민', atBats: 4, runs: 1, hits: 2, rbi: 2),
  BatterRecord(order: 7, position: '포', name: '장성우', atBats: 4, runs: 0, hits: 0, rbi: 0),
  BatterRecord(order: 8, position: '2', name: '윤석민', atBats: 3, runs: 0, hits: 0, rbi: 0),
  BatterRecord(order: 9, position: '투', name: '사우어', atBats: 2, runs: 0, hits: 0, rbi: 0),
];

const mockAwayPitchers = <PitcherRecord>[
  PitcherRecord(name: '사우어', innings: '5.0', hits: 5, strikeouts: 4, walks: 2, earnedRuns: 2, decision: 'W'),
  PitcherRecord(name: '김영현', innings: '2.0', hits: 1, strikeouts: 2, walks: 0, earnedRuns: 0),
  PitcherRecord(name: '박세진', innings: '2.0', hits: 0, strikeouts: 3, walks: 1, earnedRuns: 0),
];

const mockAwayLineup = <LineupEntry>[
  LineupEntry(order: 1, position: 'CF', positionKo: '중견수', name: '최원준'),
  LineupEntry(order: 2, position: '1B', positionKo: '1루수', name: '김현수'),
  LineupEntry(order: 3, position: 'DH', positionKo: '지명타', name: '강백호'),
  LineupEntry(order: 4, position: 'LF', positionKo: '좌익수', name: '박찬호'),
  LineupEntry(order: 5, position: '3B', positionKo: '3루수', name: '김민수'),
  LineupEntry(order: 6, position: 'SS', positionKo: '유격수', name: '이강민'),
  LineupEntry(order: 7, position: 'C', positionKo: '포수', name: '장성우'),
  LineupEntry(order: 8, position: '2B', positionKo: '2루수', name: '윤석민'),
  LineupEntry(order: 9, position: 'P', positionKo: '투수', name: '사우어'),
];
