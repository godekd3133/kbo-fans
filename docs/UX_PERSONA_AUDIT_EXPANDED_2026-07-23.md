# 확장 UX 페르소나 감사 및 개선 보고서 — 2026-07-23

## 결론

기존 세 페르소나 감사를 20개 사용 맥락으로 확장해 온보딩, 홈, 경기 상세 네 탭, 일정, 순위, 기록실, 선수 상세, 데이터 브리핑, 알림함, 설정을 다시 점검했다.

가장 큰 문제는 장식의 완성도보다 정보의 진실성이었다. 원천 필드가 없는 홈 LIVE B/S/O·루상, 9회로 고정된 스코어 표, 휴리스틱 최고 타자를 공식 `결승타`처럼 부르던 표현, 내부 데이터 요약을 실제 뉴스처럼 보이게 한 화면명과 출처 부재를 P1으로 판정했다. 이번 작업에서 이 네 항목과 작은 화면 정보 밀도, 알림 실패 구분, 반복 기록 요약, 일정 범례, 순위 연패 요약, 선수 지표 형태를 함께 개선했다.

공통 데이터 관측 시각을 모든 API envelope에서 도메인 모델까지 전달하는 작업, 오래 읽는 문자중계의 floating 새 이벤트 CTA와 scroll anchor 보존, 실제 iOS VoiceOver·Android TalkBack·권한 거부·백그라운드 복귀 검증은 별도 후속 범위로 남는다.

## 감사 방법과 증거 경계

- 실제 로컬 release web preview는 전 중요 여정을 390×844에서 탐색하고, 320×844에서는 온보딩·홈·홈 순위 요약·단독 순위·선수 상세·박스스코어를 추가 점검했다.
- 2026-07-23 운영 backend API가 제공한 홈, LIVE 경기, 일정, 순위, 기록, 선수, 설정 상태를 사용했다.
- 개선 전 19장과 개선 후 18장, 총 화면 캡처 37장을 같은 감사 폴더에 보존하고 코드·FastAPI 응답 계약·기존 테스트와 교차 확인했다.
- UI에서 보인 데이터가 운영 FastAPI의 어느 crawler 응답인지까지는 로컬 네트워크 trace로 증명하지 않았다.
- 실제 기기 알림 권한, FCM/APNs token 등록, VoiceOver/TalkBack, 장시간 background 복귀는 소스·widget test만으로 완료 판정하지 않았다.

## 확장 페르소나

| 번호 | 페르소나 | 가장 중요한 질문 | 초기 건강도 | 개선 후 판단 |
| --- | --- | --- | --- | --- |
| 1 | 최초 설치 라이트 팬 | 팀을 고르고 오늘 경기까지 막힘없이 가는가 | 주의 | 양호 |
| 2 | 팀을 아직 정하지 않은 팬 | 개인화 없이도 앱을 이해하고 나중에 선택할 수 있는가 | 주의 | 양호 |
| 3 | 재방문 마이팀 팬 | 홈 첫 화면에서 내 팀 흐름을 빠르게 읽는가 | 주의 | 양호 |
| 4 | 점수만 빠르게 보는 팬 | 실제 점수와 미제공 상황 정보를 혼동하지 않는가 | 위험 | 양호 |
| 5 | 문자중계를 오래 읽는 팬 | 갱신 지연과 새 이벤트를 읽던 위치에서 아는가 | 주의 | 주의 |
| 6 | 연장 경기 팬 | 10회 이후 이닝과 합계를 잃지 않는가 | 위험 | 양호 |
| 7 | 기록 신뢰에 민감한 팬 | 공식 기록과 앱 계산을 구분하는가 | 위험 | 양호 |
| 8 | 경기 전 라인업 팬 | 빈 비교 장식보다 공개 타순을 먼저 보는가 | 주의 | 양호 |
| 9 | 느린 네트워크·복귀 사용자 | 보존 데이터와 최신 성공을 구분하는가 | 위험 | 주의 |
| 10 | 일정 계획 사용자 | 날짜 표식과 선택 상태의 의미가 일치하는가 | 주의 | 양호 |
| 11 | 구장 직관 팬 | 구장별·팀별 필터를 이해하고 탐색하는가 | 주의 | 주의 |
| 12 | 순위 경쟁 팬 | 연승·연패와 경기 차를 과장 없이 읽는가 | 위험 | 양호 |
| 13 | 기록실 탐색 팬 | 같은 리더를 반복하지 않고 비교로 이어가는가 | 위험 | 양호 |
| 14 | 선수 상세 팬 | `헤드라인/시즌` 같은 내부 역할명 대신 지표를 읽는가 | 주의 | 양호 |
| 15 | 출처 민감 사용자 | 생성 브리핑을 실제 기사로 오인하지 않는가 | 위험 | 양호 |
| 16 | 알림함 사용자 | 정상 빈 상태와 목록·설정 실패를 구분하는가 | 위험 | 양호 |
| 17 | 알림 권한 거부 사용자 | 선택한 알림과 실제 수신 가능성을 구분하는가 | 위험 | 양호 |
| 18 | 320px 작은 화면 사용자 | 축소 글자·겹침 없이 같은 정보를 읽는가 | 위험 | 양호 |
| 19 | 큰 글자·스크린리더·키보드 사용자 | 선택 상태와 지표 전체를 조작·이해하는가 | 주의 | 양호 |
| 20 | 업데이트 후 복귀 사용자 | 기존 설정·새 기능 경계를 잃지 않는가 | 양호 | 양호 |

## 중요 여정별 상태

| 단계 | 상태 | 관찰과 조치 |
| --- | --- | --- |
| 최초 온보딩 390px | 양호 | 팀 선택, 건너뛰기, 마이팀 미리보기가 한 흐름으로 이어진다. |
| 온보딩 320px | 개선 완료 | 8px까지 축소되던 혜택 문구를 제거하고, 10px 이상 텍스트의 2열 Wrap 카드로 전환했다. |
| 무팀 홈 | 양호 | 마이팀 선택 CTA가 edit 온보딩을 거쳐 홈으로 복귀한다. |
| 재방문 홈 390px | 양호 | 마이팀·오늘 경기·실시간 경기 우선순위가 유지된다. |
| 재방문 홈 320px | 개선 완료 | 최근 경기와 팀 지표가 겹치지 않게 작은 폭에서 두 행으로 흐르게 했다. |
| 홈 LIVE 상황 | 개선 완료 | 계약에 없는 고정 B/S/O `3/2/2`와 고정 루상을 제거하고 `볼카운트·주자 상황 정보 미제공`을 표시한다. |
| LIVE 상세 진입 | 주의 | 기존 데이터 보존과 `갱신 지연`은 동작하지만 모든 표면의 마지막 성공 시각 계약은 아직 없다. |
| 스코어 탭 | 개선 완료 | 양 팀 이닝과 현재 회차를 기준으로 9회 이상 동적 생성하고 팀 열 고정·가로 스크롤·R/H/E/B 범례·접근성 요약을 제공한다. |
| 문자중계 탭 | 주의 | 필터와 읽기 흐름은 동작하지만 오래 읽는 위치 위에 새 항목이 추가될 때 floating CTA와 scroll anchor 보존이 남았다. |
| 박스스코어 탭 | 개선 완료 | 원시 예외를 숨기고 재시도를 제공하며 `결승타`를 `오늘의 활약 타자`, 타자·투수 파생값을 `앱 기준 활약 지수`·`앱 기준 투구 효율`로 구분한다. 320px에서는 태그·이름·계산 지표를 세로로 배치한다. |
| 라인업 탭 | 개선 완료 | 모든 비교값이 비어 있으면 큰 선발 비교표를 숨기고 공개 타순을 먼저 보여준다. |
| 일정 달력 | 개선 완료 | 경기일 외곽선, 마이팀·일반 경기 점, 선택 날짜 채움의 실제 모양과 범례를 맞췄다. |
| 구장별 일정 | 주의 | 필터와 quick link는 동작하지만 수평 목록의 추가 scroll affordance는 남았다. |
| 순위 | 개선 완료 | 승패를 모두 포함한 가장 긴 `연속 흐름`을 보여주고, 320px에서는 팀 공식 짧은 이름과 축소 열 간격으로 가로 넘침을 없앴다. `마지막 업데이트` 대신 화면 확인 시각임을 명시한다. |
| 기록실 첫 화면 | 개선 완료 | `시즌 리더 요약`에서 타자·투수 대표만 먼저 보여주고 반복 수치 상자·문장 요약을 제거해 지표 rail을 위로 올렸다. |
| 리더보드 | 양호 | 지표별 TOP 5와 선수 상세 이동이 유지된다. |
| 선수 상세 | 개선 완료 | 지표명과 값을 카드로 분리하고 빈 값과 주요·시즌 기록의 동일 지표·값 반복을 숨기며, 320px·큰 글자는 한 열로 전환한다. |
| 데이터 브리핑 | 개선 완료 | 하단·헤더 이름을 `데이터 브리핑`으로 바꾸고 `실제 뉴스 기사 아님`, KBO 데이터 자동 정리, 생성 시각 또는 미제공 상태를 표시한다. |
| 계산형 브리핑 | 개선 완료 | 홈런·승수 144경기 환산에 `앱 계산`을 붙이고 실제 2경기 차 이내에서만 `턱밑`을 쓴다. 중복 제목 접두사를 방지한다. |
| 알림함 | 개선 완료 | 최근 최대 50개 계약, 현재 표시 수, 목록·설정 독립 실패와 독립 재시도, 실패 중 unread `확인 불가`, 44px 선택 필터 semantics를 제공한다. |
| 푸시 설정 | 개선 완료 | `N개 켜짐`을 `N개 선택됨`으로 바꾸고 설정 로드 실패를 무한 spinner가 아닌 재시도 상태로 구분한다. 실제 수신은 권한·기기 등록·서버 상태에 달렸음을 밝힌다. |
| 하단 5탭 | 개선 완료 | 실제 정보 성격에 맞게 `홈 / 일정 / 기록 / 브리핑 / 설정`으로 명명한다. |

## 우선순위별 피드백과 처리

### P1 — 즉시 수정

1. 원천 필드가 없는 LIVE B/S/O·루상 고정 표현: 제거 완료.
2. 9회로 고정된 스코어 탭: 동적 연장 이닝 표로 교체 완료.
3. 휴리스틱을 공식 `결승타`로 표현: 파생 지표로 명확히 구분 완료.
4. 내부 데이터 요약을 실제 `뉴스`처럼 표현하고 생성 시각을 버림: 데이터 브리핑·생성 시각 계약으로 개선 완료.

### P2 — 이번 범위에서 수정

- 알림 목록과 설정 실패를 하나의 빈 상태로 합치던 문제
- 푸시 선호 개수와 실제 전송 가능성을 같게 보이던 문제
- 기록실 첫 화면의 같은 리더 반복
- 선수 상세의 내부 역할명과 반복 `시즌` 라벨
- 320px 온보딩의 지나치게 작은 축소 글자
- 320px 홈 마이팀 요약 겹침
- 달력 범례와 실제 표식 불일치
- 순위 요약이 연패를 무시하고 `연승 -`으로 보이던 문제
- 라인업의 값 없는 큰 비교 카드
- 박스스코어 원시 예외 문자열 노출

### 남은 후속

- API response `timestamp`와 원천 `observedAt`을 구분하는 공통 `DataObservation` 계약
- 홈·경기 상세의 마지막 성공 시각과 표면별 stale 상태
- 문자중계 `새 중계 N개 · 최신으로` floating CTA, 읽던 item anchor 보존
- 예정 라인업 오류의 명시적 즉시 재시도와 실제 5분 cadence 문구
- 실기기 알림 권한·token/topic/server 등록 상태의 end-to-end 진단
- iOS VoiceOver·Android TalkBack·200% 글자 실제 기기 검증

## 대표 감사 캡처

### LIVE 정보 신뢰

![기존 홈과 LIVE 흐름](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/01-home-returning-myteam.png)

![기존 스코어 탭](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/04-live-score-tab.png)

![기존 박스스코어 탭](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/05-live-boxscore-empty.png)

### 일정·기록·출처

![기존 일정 달력과 범례](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/07-schedule-calendar.png)

![기존 기록실의 반복 요약](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/09-records-overview.png)

![기존 뉴스형 데이터 피드](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/12-news-feed.png)

### 작은 화면·알림

![기존 320px 온보딩 혜택 글자](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/16-onboarding-edit-320.png)

![기존 320px 홈 정보 밀도](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/17-home-320.png)

![기존 알림함 빈 상태](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/02-notification-inbox-empty.png)

## 개선 후 대표 캡처

### 실제 데이터와 파생 정보 구분

![개선 후 동적 스코어 표](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/21-score-dynamic-table.png)

![개선 후 라인업 우선 배치](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/23-lineup-compact.png)

![개선 후 320px 박스스코어 계산 지표](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/34-boxscore-320.png)

![개선 후 데이터 브리핑 출처 고지](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/27-data-briefing-trust.png)

### 정보 밀도와 작은 화면

![개선 후 기록실 첫 화면](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/25-records-summary.png)

![개선 후 320px 선수 지표 1열](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/26b-player-detail-320.png)

![개선 후 320px 온보딩](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/30-onboarding-320-readable.png)

![개선 후 320px 홈 순위 표](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/31b-home-320-standings.png)

### 일정·순위·알림 신뢰

![개선 후 일정 표식과 범례](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/24-schedule-legend.png)

![개선 후 승패 연속 흐름](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/32-standings-flow.png)

![개선 후 320px 단독 순위표](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/33-standings-320.png)

![개선 후 알림함 보관 계약](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/28-notification-inbox-contract.png)

![개선 후 푸시 선택과 실제 수신 경계](../artifacts/ux-persona-audit-expanded-2026-07-23/screenshots/29-settings-notification-trust.png)

## 검증 기준

- 정적 검증: 변경 파일 format, Flutter analyzer 무경고, widget/service 전체 373개 회귀 테스트, `git diff --check`
- 빌드 검증: backend API release define을 사용한 `0.1.20+88` Flutter web release build
- 런타임 검증: 390×844 실제 web preview의 온보딩, 홈, LIVE 상세, 일정, 순위, 기록, 선수, 브리핑, 알림, 설정. 320×844는 온보딩·홈·홈 순위 요약·단독 순위·선수 상세·박스스코어를 추가 확인. 캡처 시 브라우저 warning/error 없음
- 별도 증명으로 유지: 운영 API health, 실제 iPhone/Android, APNs/FCM 수신, TestFlight installability

테스트 통과, web build 성공, 운영 API 응답, TestFlight 처리 상태는 서로 대체하지 않는다.
