import 'package:flutter_test/flutter_test.dart';
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
}
