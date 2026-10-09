# 알림 설정 저장 실패와 복구

## 분석·목표

설정 화면은 토글을 먼저 바꾸고 저장이 실패해도 draft 값을 그대로 남겼다. SharedPreferences legacy 구현은 platform 쓰기 전에 cache를 바꾸고, 쓰기 실패를 false로 반환할 수 있는데 service가 bool 결과를 확인하지 않았다. 일부 저장 후 실패할 수 있어 단순 이전값 rollback도 실제 저장 상태와 다를 수 있다.

실패를 확인하고 저장소를 다시 읽어 표시를 맞춘다. 저장값 확인까지 실패하면 어떤 토글이 저장됐는지 추측하지 않고 복구 action을 제공한다.

## 구현·영향 범위

- PushNotificationService.saveSettings의 기존 bool/string key별 write 결과를 확인해 false를 실패로 처리한다. key·delivery 값·토픽 계산·등록 payload는 유지한다. 원자적 저장으로 바뀐 것은 아니며 부분 저장은 가능하다.
- loadSettings의 명시적 reloadFromStorage 옵션은 실패 readback에서만 사용한다. SharedPreferences.reload로 platform 저장 상태를 읽고 낙관적 cache를 재사용하지 않는다.
- Settings UI는 save failure 후 저장값을 읽어 현재 토글을 맞춘다. readback failure 시 저장 상태 확인 필요와 retry-load를 표시한다. 카드 keepAlive로 스크롤 밖으로 나가도 failure state를 잃지 않는다.
- 기존 loader와 같은 수준의 optional saver injection을 추가해 partial/failure를 검증한다. production은 기존 service 경로를 사용한다.
- backend push/register consumer 계약과 service registration catch를 확인했다. local preference 저장과 server sync는 독립 상태이며 이 변경으로 실제 푸시 등록/수신 성공을 주장하지 않는다. backend/infra/release 변경 없음.

## 검증

- 설정/service 관련 62 tests passed. 정상 토글·preset 저장/권한 요청 분리·부분 저장/실패·readback 실패 후 복구 포함.
- 실제 platform store false를 반환하는 테스트에서 write failure를 확인했다. 일반 load는 낙관적 cache를 읽고, reloadFromStorage는 실제 stored true를 읽는 차이를 검증했다.
- 이번 저장 실패 실화면·실기기·서버 sync/delivery 검증은 not-run. 전체 목표는 진행 중이다.

- 최종 analyze 무결함·설정/service 62 tests·전체 Flutter 654 tests 통과. 실제 기기 저장 실패/서버 전달/이번 실패 state 실화면은 not-run.
