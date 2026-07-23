# 전면 재감사 UX·UI·기능·신뢰성 보고서 — 2026-07-23

## 결론

이번 회차는 기존 40개 페르소나 감사를 반복하지 않고, 서로 다른 세 축의 113개 페르소나를 추가 배정해 제품 구조부터 데이터 전달 실패까지 다시 감사했다.

- 제품·정보구조·진입·탐색·공유: 36개
- 실시간·저속망·원천 장애·푸시·경기 생명주기: 44개
- 접근성·초소형 화면·큰 글자·태블릿·위젯·보조기술: 33개

기존 감사까지 합친 누적 153개 맥락에서 공통으로 반복된 문제는 카드의 모양보다 다음 다섯 가지였다.

1. `순위`가 어느 탭 소속인지 알 수 없고 태블릿도 휴대폰 한 열을 그대로 사용했다.
2. 원천 점수 누락을 실제 `0:0`으로 바꿔 사용자가 틀린 사실을 믿을 수 있었다.
3. 푸시 전송보다 기준 상태를 먼저 전진시켜 부분 실패 시 이벤트를 영구히 잃을 수 있었다.
4. 포그라운드·백그라운드 알림이 동시에 저장되면 하나의 JSON 전체 저장이 서로를 덮을 수 있었다.
5. 280/320px·240% 글자와 고대비·보조기술 환경에서 경기 상세과 조작 표면의 계약이 일관되지 않았다.

이에 따라 이번 개선은 시각 폴리싱에 그치지 않고 내비게이션, 데이터 모델, 저장 단위, 푸시 전달 상태, 접근성 토큰과 레이아웃을 함께 바꾼다.

최종 로컬 검증에서는 아래 대표 여정 15개가 모두 통과했고, 추가 적대적 검토에서 발견된 다중 worker·지연 snapshot·공식 종료 점수 정정까지 회귀 테스트로 닫았다. 이는 배포나 실기기 전달 성공을 뜻하지 않으며, 증거 경계는 아래에 따로 남긴다.

## 감사 방법과 증거 경계

- 세 감사 그룹이 현재 `main` 소스와 스펙을 독립적으로 읽고 P0/P1을 낸 뒤, 같은 원인이 여러 페르소나에서 반복되는지 교차 비교했다.
- 현재 release web build를 280×844, 390×844, 1024×768에서 확인하고 홈, 일정, 순위, 기록, 브리핑, 설정, 알림함, 온보딩, 경기 상세 네 탭을 캡처했다.
- 구현 전 캡처는 `artifacts/ux-persona-audit-systemic-2026-07-23/screenshots/01-baseline-...`부터 보존한다.
- Flutter widget test는 레이아웃, semantics, 데이터 파싱, 동시 Future와 라우팅 계약을 검증한다.
- backend test는 이벤트 생성, 전송 실패 재시도, 부분 성공, 기준 상태와 smart-daily 발송 상태를 검증한다.
- 실제 VoiceOver·TalkBack·Switch Control, 저속망, APNs/FCM 전달, 위젯·Live Activity 실기기 렌더링은 별도 증거다. 소스·테스트·웹 캡처로 이를 대체하지 않는다.

## 추가 113개 페르소나 구성

### 제품·정보구조 36개

| 범주 | 페르소나 |
| --- | --- |
| 첫 진입 | 처음 설치한 라이트 팬, 응원팀 없는 중립 팬, 저속망 첫 설치, 알림 거부, 개인정보 민감 사용자 |
| 정체성 | 시즌 복귀 팬, 응원팀 변경, 가족 공용 기기, 마이팀과 가족팀을 함께 보는 팬 |
| 빠른 확인 | 10초 점수 확인, 출퇴근 한 손, 경기 중 수시 확인, 알림 재진입, 위젯 재진입, Live Activity 재진입 |
| 복기·계획 | 경기 종료 복기, 월간 일정 계획, 원정·구장 방문, 예매 오픈 추적, 맞대결 일정 |
| 기록 탐색 | 순위 경쟁 추적, 과거 시즌 연구, 선수 이름 검색, 지표 비교, 약어 초보, 리그 전체 팬 |
| 공유·플랫폼 | 메신저 공유, 앱 없는 링크 수신자, Android 딥링크, 해외 체류, 큰 글자 고령층, 스크린리더, 태블릿·가로, 출처 민감 팬 |

### 실시간·데이터·푸시 44개

| 범주 | 페르소나 |
| --- | --- |
| 네트워크 | 저속 3G 콜드 스타트, 지하철 터널, 완전 오프라인, 캡티브 포털, Wi-Fi→LTE, 데이터 절약, 배터리 절약 |
| 생명주기 | 2시간 백그라운드 복귀, KST 자정 통과, UTC-7 체류, 미래로 틀어진 기기 시계 |
| 부분 실패 | scoreboard만 성공, schedule만 실패, standings만 실패, records만 실패, relay만 실패, boxscore만 실패 |
| 원천 이상 | HTTP 200 빈 목록, 필드명 변경, 429, 503, 5경기 중 일부만 수신, worker/API 다중 프로세스 |
| 권한·토큰 | 최초 거부, OS 설정에서 허용, 온라인 토큰 교체, 오프라인 토큰 교체, 오프라인 follow/unfollow, 재설치, 2대 기기 |
| 중복·동시성 | 같은 messageId 재전송, 포그라운드·백그라운드 동시 수신, target 일부 성공, receipt POST 오프라인 |
| 상태 전이 | SCHEDULED→LIVE, LIVE→FINAL, 오래된 LIVE→FINAL, CANCELLED, 오래된 CANCELLED, SUSPENDED, SUSPENDED→LIVE |
| 식별자 | 공식 ID 더블헤더, 합성 ID 더블헤더, 우천 지연, 재편성, LIVE 점수 null |

### 접근성·기기·플랫폼 33개

| 범주 | 페르소나 |
| --- | --- |
| 초소형·확대 | 280px Android Go 240%, 280px 웹 패널 키보드, 320px iPhone SE VoiceOver, 320px Android TalkBack, 360px 손떨림, 360px Switch Control |
| 경기 중 보조기술 | iPhone VoiceOver LIVE, Android TalkBack LIVE, B/S/O·루상 비시각 사용자 |
| 넓은 화면 | 430px 한손, 700px 폴더블, 800px 태블릿 키보드, 1024px iPad VoiceOver |
| 가로 화면 | 844×390 240%, 740×360 한손 |
| 긴 문자열 | 긴 팀명·선수명 280/320px, 70대 코어팬 200% |
| 시각 인지 | 다크 저시력, 라이트 고대비, 적록색각, 햇빛 아래, 회색조, 저조도 |
| 운동·인지 | Reduce Motion, 난독 경향, 인지부하 라이트팬, 야구 초보 |
| 입력·공지 | 상지 운동장애, 웹 키보드, 지연 데이터 갱신 공지 |
| 위젯 | iOS 홈 위젯 VoiceOver, Live Activity VoiceOver, Android 위젯 TalkBack, 웹 미지원 기능 사용자 |

## 교차 우선순위

| 우선순위 | 문제 | 영향 | 이번 대응 |
| --- | --- | --- | --- |
| P0 | LIVE null 점수가 0으로 변환 | 틀린 경기 사실·가짜 득점/역전 | 점수 값과 확인 가능성을 분리하고 미확인은 `–`로 표시 |
| P0 | 푸시 전송 전 baseline/seq/sent 전진 | 부분 실패 후 영구 누락 | baseline/seq와 영속 outbox를 원자 저장하고 target별 재시도 |
| P0 | 알림함 전체 JSON read-modify-write | 동시 수신·읽음 상태 유실 | message별 key, 비캐시 async 저장, 단조 read receipt, v1 migration |
| P0 | 실제 고대비 테마 없음 | 저시력 사용자가 작은 보조 정보 판독 불가 | 독립 light/dark 고대비 팔레트와 24개 대비 조합 테스트 |
| P0 | 공통 조작 최소 영역 없음 | 손떨림·Switch Control·키보드 오조작 | `AppPressable` 44×44, label/hint/selected/enabled 계약 |
| P0 | 경기 상세 극단 화면 고정 행 | 280/320px·240%에서 팀·점수·탭 손실 | hero·탭·relay scorebug 적응형 재배치 |
| P0 | 순위가 선택된 하단 탭 없음 | 현재 위치와 복귀 맥락 상실 | 모바일 `기록` 소속, 태블릿 직접 `순위` 목적지 |
| P1 | 태블릿도 430px 한 열과 하단 탭 | 큰 화면 공간·탐색 효율 낭비 | 700px rail, 1000px extended rail, 720px 콘텐츠 폭 |
| P1 | 서스펜디드를 종료처럼 follow 해제 | 재개 경기 추적 중단 | 중단 시 follow 유지, 미확인 점수는 기존 Live 표면 보존 |
| P1 | 팀 저장이 알림 권한·서버 sync를 기다림 | 저속망 온보딩 지연·실패 | 로컬 개인화 완료와 background sync 분리 |
| P1 | 탭 760ms·상세 1000ms 전환 | 10초 점수 확인 흐름 저하 | 탭 240/200ms, 상세 420ms로 조정 |

## 중요 여정 건강도

| 여정 | 개선 전 | 개선 후 판단 |
| --- | --- | --- |
| 모바일 순위 진입 | 선택 하단 탭 없음 | `기록` 선택으로 현재 소속 표시 |
| 태블릿 홈 | 430px 휴대폰 열 + 하단 탭 | rail + 최대 720px 콘텐츠 |
| LIVE 점수 누락 | `0:0` | `– : –`, 득점·역전 생성 중지 |
| Live Activity 점수 누락 | 0으로 덮을 수 있음 | 검증 점수 없으면 update 보류 |
| 서스펜디드 follow | 종료처럼 해제 | follow 유지, 중단 상태 동기화 |
| 동시 알림 100건 | 전체 JSON 경쟁 | 서로 다른 message key로 저장, 최신 50건 보존 |
| 읽음과 중복 수신 경쟁 | `true → false` 역행 가능 | 별도 단조 read receipt로 역행 차단 |
| 고대비 | 일반 테마와 동일 | 독립 테마, 읽기 역할/4개 표면 4.5:1 이상 |
| 공통 터치 | 38~42px 조작 존재 | 공통 최소 44px, 강제 작은 부모에서는 overflow 없이 축소 |
| 경기 상세 280/320·240% | 고정 hero·탭·scorebug | 적응형 재배치와 overflow 회귀 테스트 |
| 온보딩 저속망 | push future에 직렬 결합 | 로컬 팀 저장 완료 후 즉시 이동, sync는 background |
| smart-daily 부분 실패·동시 worker | 성공 target 재발송·완료 slot 재claim | 11개 delivery별 claim/fencing, 실패 target만 재시도 |
| Live Activity 동시 start/end | 같은 Activity 중복 생성·종료 | game/token별 lease+fencing, 성공 end token 제거 |
| 늦은 과거 snapshot | 점수·이닝·타자·종료 상태 회귀 | monotonic CAS와 stable milestone, side effect 전체 gate |
| 공식 종료 점수 정정 | 일반 score 감소 guard에 막힐 수 있음 | FINAL/CANCELLED 전이·동일 terminal 정정을 최종 원천으로 수용 |

## 개선 전 대표 캡처

![390px 홈 기준](../artifacts/ux-persona-audit-systemic-2026-07-23/screenshots/01-baseline-home-390.png)

![390px 순위 기준](../artifacts/ux-persona-audit-systemic-2026-07-23/screenshots/03-baseline-standings-390.png)

![390px 경기 박스스코어 기준](../artifacts/ux-persona-audit-systemic-2026-07-23/screenshots/10-baseline-game-boxscore-390.png)

![280px 경기 상세 기준](../artifacts/ux-persona-audit-systemic-2026-07-23/screenshots/13-baseline-game-score-280.png)

![1024px 태블릿 홈 기준](../artifacts/ux-persona-audit-systemic-2026-07-23/screenshots/14-baseline-home-1024.png)

## 개선 후 대표 캡처

최종 release web build를 같은 상태·같은 viewport로 다시 캡처했다.

![390px 홈 개선 후](../artifacts/ux-persona-audit-systemic-2026-07-23/screenshots/15-after-home-390.png)

![390px 순위 개선 후](../artifacts/ux-persona-audit-systemic-2026-07-23/screenshots/16-after-standings-390.png)

![390px 경기 상세 개선 후](../artifacts/ux-persona-audit-systemic-2026-07-23/screenshots/17-after-game-score-390.png)

![280px 경기 상세 개선 후](../artifacts/ux-persona-audit-systemic-2026-07-23/screenshots/18-after-game-score-280.png)

![1024px 태블릿 홈 개선 후](../artifacts/ux-persona-audit-systemic-2026-07-23/screenshots/19-after-home-1024.png)

## 같은 입력의 전후 비교

각 비교 이미지는 왼쪽이 구현 전, 오른쪽이 개선 후다.

![390px 홈 전후](../artifacts/ux-persona-audit-systemic-2026-07-23/screenshots/20-compare-home-390-before-after.png)

![390px 순위 전후](../artifacts/ux-persona-audit-systemic-2026-07-23/screenshots/21-compare-standings-390-before-after.png)

![280px 경기 상세 전후](../artifacts/ux-persona-audit-systemic-2026-07-23/screenshots/23-compare-game-score-280-before-after.png)

![1024px 홈 전후](../artifacts/ux-persona-audit-systemic-2026-07-23/screenshots/24-compare-home-1024-before-after.png)

## 검증 체크포인트

- Flutter format: 변경 Dart 35개, `0 changed`
- Flutter 정적: `flutter analyze --no-pub`, `No issues found`
- Flutter 전체: `424 passed`
- backend focused: push/outbox/smart-daily 3파일 `133 passed`; 다중 worker 경합 4종 × 20회, 총 80회 통과
- backend 전체: `321 passed`
- Python 정적: Python 3.9 compileall, Ruff py39 전체 check, 변경 8파일 format check 통과
- build: 운영 API를 주입한 Flutter web release 성공. 현재 의존성의 Wasm dry-run과 Cupertino font notice는 남음
- iOS native build: codesign 없는 generic iOS Simulator Runner 성공, Widget extension·Live Activity capability·`점수 확인 중` label 포함
- runtime: 280×844, 390×844, 1024×768 전후 비교 완료, in-app Browser warning/error `0`
- 미실행 별도 증명: iOS/Android 실기기, 실제 VoiceOver/TalkBack/Switch Control 포커스·발화, 홈 위젯/Dynamic Island 실기기 렌더링, 실제 APNs/FCM delivery, TestFlight

## 남은 P1/P2

1. 화면별 `observedAt/generatedAt/receivedAt/source/cacheKind/isPartial` 공통 계약
2. 현재 `/home` aggregate의 섹션별 partial success 모델
3. 토큰 교체·권한 변경·오프라인 follow를 재시도하는 push registration coordinator
4. 더블헤더 합성 ID와 delayed/postponed/resumed 상태 정식화
5. 진짜 전역 검색, canonical 공유 URL과 Universal/App Link
6. iOS·Android 위젯의 합성 접근성 레이블과 Dynamic Type
7. `B/S/O`, `WHIP`, `SLG` 등 공통 야구 용어 사전
8. 같은 점수에서 실제로 두 번째 SUSPENDED가 발생하는 경우를 구분할 source revision
9. 비종료 Live Activity update의 다중 worker claim 또는 APNs collapse id 정책
10. 외부 provider 성공 직후 registry 기록 전 crash의 at-least-once 중복을 흡수할 end-to-end receipt
11. 진행 중 공식 점수 하향 정정을 stale snapshot과 구분할 source observedAt/revision

P0를 고쳤다는 사실은 실기기 전달 성공을 뜻하지 않는다. 배포 후 실제 KBO 원천 부분 응답, APNs/FCM 부분 실패, 앱 강제 종료·재개, OS 고대비·보조기술을 별도 운영 검증해야 한다.
