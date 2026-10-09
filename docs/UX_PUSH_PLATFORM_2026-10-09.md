# 실행 환경에 맞는 푸시 설정

## 분석·목표

390px 웹 settings 실화면에서 알림 허용하기와 10개 알림 토글을 확인했다. 실제 PushNotificationService는 웹에서 initialize/requestPermissionAndSync를 지원하지 않고 shouldUseRemotePushServices도 false를 반환한다. 사용할 수 없는 조작을 노출하지 않고 간결한 안내를 제공한다.

## 구현·영향 범위

- Settings의 지원 판단은 서비스의 shouldUseRemotePushServices와 동일한 isWeb/USE_BACKEND_API 빌드 옵션을 사용한다. 단독 화면이 AppConfig singleton 초기화에 의존하지 않도록 immutable build flag를 사용한다.
- unsupported이면 푸시 알림과 휴대폰 앱 안내만 표시한다. 권한 requester·settings loader·saver·preset·토글을 생성하지 않는다.
- supported native API mode는 기존 설정/저장/readback/권한 동선을 유지한다. optional capability override는 tests에서 지원/미지원 화면을 확인하는 데 사용한다.
- 알림함 진입과 기존 기기 내부 보관 항목은 유지한다. backend registration/FCM/APNs payload·infra·release 변경 없음.

## 검증

미지원 case에서 UI action 부재와 loader/requester/saver 호출 0을 확인한다. 기존 supported native 설정 tests와 registration/topic service tests도 유지한다. 최종 로그·웹 capture는 `artifacts/ux-push-platform-2026-10-09/`에 보존한다. 실기기 사용 중 조건은 유지하며 native 실제 전달/권한 검증은 별도다. 전체 목표는 active다.

- 최종 전체 Flutter 656 tests·analyze·웹 build 통과. unsupported callbacks 0과 supported 저장/권한/복구 기존 테스트 포함. 웹 PNG390x844에서 권한/preset/toggle 부재·간결한 안내·inbox 진입 유지 확인. 임시 emulation clear 완료. 초기 dependency 실패 로그는 initial-config-dependency-tests.log로 구분한다.
