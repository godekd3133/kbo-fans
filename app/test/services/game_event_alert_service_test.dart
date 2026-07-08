import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/models/relay.dart';
import 'package:kbo_fans/services/game_event_alert_service.dart';

void main() {
  test('로컬 경기 이벤트 알림은 local native 또는 명시 플래그에서만 처리한다', () {
    expect(
      shouldProcessLocalGameEventAlerts(
        isWeb: false,
        isLocal: true,
        forceEnabled: false,
      ),
      isTrue,
    );
    expect(
      shouldProcessLocalGameEventAlerts(
        isWeb: false,
        isLocal: false,
        forceEnabled: false,
      ),
      isFalse,
    );
    expect(
      shouldProcessLocalGameEventAlerts(
        isWeb: false,
        isLocal: false,
        forceEnabled: true,
      ),
      isTrue,
    );
    expect(
      shouldProcessLocalGameEventAlerts(
        isWeb: true,
        isLocal: true,
        forceEnabled: true,
      ),
      isFalse,
    );
  });

  test('로컬 경기 이벤트 알림 body는 주자 상황 앞에 현재를 붙인다', () {
    const currentAtBat = CurrentAtBat(
      batterName: '장성우',
      batterNumber: 4,
      batterHand: 'R',
      pitcherName: '김진성',
      pitcherNumber: 42,
      pitcherHand: 'R',
      pitchCount: 12,
      baseState: '주자1,2루',
      balls: 1,
      strikes: 2,
      outs: 1,
    );

    final body = buildGameEventRelayAlertBody(
      playText: '장성우 : 좌전 안타',
      currentAtBat: currentAtBat,
    );

    expect(body, '장성우 : 좌전 안타 · 현재 1사 1,2루');
  });

  test('로컬 경기 이벤트 알림 body는 상황이 없으면 relay 원문만 쓴다', () {
    final body = buildGameEventRelayAlertBody(
      playText: '장성우 : 좌월 홈런',
      currentAtBat: null,
    );

    expect(body, '장성우 : 좌월 홈런');
  });

  test('로컬 경기 이벤트 알림 팀명은 KBO 팀 ID를 팬이 보는 짧은 팀명으로 바꾼다', () {
    expect(
      buildGameEventMatchupLabel(
        awayTeamId: 'SS',
        awayTeamName: '삼성 라이온즈',
        awayShortName: 'SS',
        homeTeamId: 'SK',
        homeTeamName: 'SSG 랜더스',
        homeShortName: 'SK',
      ),
      '삼성 vs SSG',
    );
  });

  test('로컬 경기 이벤트 알림 스코어 문구도 팀 코드를 노출하지 않는다', () {
    expect(
      buildGameEventScoreLine(
        awayTeamId: '',
        awayTeamName: '삼성 라이온즈',
        awayShortName: '삼성 라이온즈',
        awayScore: 4,
        homeTeamId: 'SK',
        homeTeamName: '',
        homeShortName: 'SK',
        homeScore: 3,
      ),
      '삼성 4:3 SSG',
    );
  });

  test('로컬 경기 이벤트 알림은 첫 득점을 역전으로 보지 않는다', () {
    expect(
      shouldSendGameEventReversal(previousLeader: null, currentLeader: 'LG'),
      isFalse,
    );
  });

  test('로컬 경기 이벤트 알림은 리더가 바뀔 때만 역전으로 본다', () {
    expect(
      shouldSendGameEventReversal(previousLeader: 'KT', currentLeader: 'LG'),
      isTrue,
    );
    expect(
      shouldSendGameEventReversal(previousLeader: 'LG', currentLeader: 'LG'),
      isFalse,
    );
  });

  test('로컬 경기 이벤트 알림은 오래된 snapshot이나 설정 변경 직후 backfill하지 않는다', () {
    final nowMs = DateTime(2026, 6, 30, 18, 30).millisecondsSinceEpoch;

    expect(
      shouldNotifyFromGameEventSnapshot(
        previousUpdatedAtMs: nowMs - const Duration(minutes: 5).inMilliseconds,
        currentAtMs: nowMs,
        previousSettingsSignature: 'same',
        currentSettingsSignature: 'same',
      ),
      isTrue,
    );
    expect(
      shouldNotifyFromGameEventSnapshot(
        previousUpdatedAtMs: nowMs - const Duration(minutes: 20).inMilliseconds,
        currentAtMs: nowMs,
        previousSettingsSignature: 'same',
        currentSettingsSignature: 'same',
      ),
      isFalse,
    );
    expect(
      shouldNotifyFromGameEventSnapshot(
        previousUpdatedAtMs: nowMs - const Duration(minutes: 1).inMilliseconds,
        currentAtMs: nowMs,
        previousSettingsSignature: 'old',
        currentSettingsSignature: 'new',
      ),
      isFalse,
    );
    expect(
      shouldNotifyFromGameEventSnapshot(
        previousUpdatedAtMs: 0,
        currentAtMs: nowMs,
        previousSettingsSignature: 'same',
        currentSettingsSignature: 'same',
      ),
      isFalse,
    );
  });

  test('로컬 경기 이벤트 알림도 allGames를 무시하고 마이팀 또는 직접 따라가는 경기만 추적한다', () {
    final tracked = selectTrackedGameEventAlertGamesForTesting(
      games: [
        _game('20260612KTLG0', awayTeamId: 'KT', homeTeamId: 'LG'),
        _game('20260612SSOB0', awayTeamId: 'SS', homeTeamId: 'OB'),
        _game('20260612NCHH0', awayTeamId: 'NC', homeTeamId: 'HH'),
      ],
      myTeamId: 'LG',
      followedGameIds: const ['20260612SSOB0'],
      trackAllGames: true,
    ).map((game) => game.gameId);

    expect(tracked, ['20260612KTLG0', '20260612SSOB0']);
  });
}

Game _game(
  String gameId, {
  required String awayTeamId,
  required String homeTeamId,
}) {
  return Game(
    gameId: gameId,
    status: GameStatus.live,
    inning: '1회초',
    away: TeamScore(
      teamId: awayTeamId,
      teamName: awayTeamId,
      shortName: awayTeamId,
      score: 0,
      innings: const [],
    ),
    home: TeamScore(
      teamId: homeTeamId,
      teamName: homeTeamId,
      shortName: homeTeamId,
      score: 0,
      innings: const [],
    ),
    stadium: '잠실',
    startTime: '18:30',
  );
}
