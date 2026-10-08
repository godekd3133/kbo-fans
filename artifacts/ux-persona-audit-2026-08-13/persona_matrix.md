# KBO Fans 한국 야구팬 페르소나 맵

> 2026-08-13 현재 소스·기획·화면 구조를 대조한 제품 가설이다. 실제 사용자 비중, 알림 KPI, 실기기 전달률을 측정한 사용자 연구 결과로 해석하지 않는다.

## 페르소나와 핵심 과업

| 페르소나 | 경기 순간의 질문 | 현재 근거 표면 | 실패 비용 | 우선 수용 기준 |
| --- | --- | --- | --- | --- |
| 10초 라이트팬·무팀 사용자 | “오늘 우리 팀 경기와 결과가 뭐야?” | `docs/PLANNING.md:16-44`; `home_screen.dart`; `onboarding_screen.dart` | 첫 진입에서 이탈하거나 경기 상태를 오해 | 팀 선택 후 홈에서 오늘 경기의 예정/진행/종료/없음과 재시도를 390·320px에서 한 번에 인지 |
| 실시간 코어팬 | “지금 몇 회, 몇 대, 무슨 플레이야?” | `docs/APP_SPEC.md:477-744`; game detail score/relay/boxscore/lineup | 지연·stale·미확정 점수를 공식 기록으로 오인 | `scoreAvailable=false`는 `–/점수 확인 중`, LIVE 오류는 historical snapshot으로 위장하지 않음; relay 첫 화면에서 현재 타석과 최근 이벤트가 가려지지 않음 |
| 예매·원정 계획팬 | “언제, 어디서, 예매할 수 있어?” | `docs/APP_SPEC.md:754-827`; schedule cards/ticketing service | KST·공식/예상 시각을 잘못 보고 일정·예매를 놓침 | 예정 경기만 시간·구장·source를 표시하고 캘린더/구장/매치업 전환과 오류 재시도를 44px target으로 제공 |
| 공식기록 민감 데이터팬 | “이 순위·선수 기록이 어느 시즌의 공식값이야?” | `docs/APP_SPEC.md:391-476,898-957,1324-1370`; records/standings | 시즌·팀·지표 snapshot 교차 오염 또는 앱 계산값을 공식값으로 오인 | rank 정렬과 exact season/team/metric identity 검증, unavailable과 앱 계산값을 명시적으로 구분 |
| 앱 밖 알림·Live Activity 팬 | “득점·홈런·역전·라인업을 놓치지 않고 원하는 만큼만 받을 수 있어?” | `docs/APP_SPEC.md:1010-1168`; push/Live Activity services | 권한·등록 성공과 실제 전달을 혼동하거나 알림 피로·중복 수신 | moment별 설정과 follow 저장을 분리하고, 토큰/receipt/서버 상태를 별도로 표시; APNs/FCM 실기기 전달은 외부 게이트로 검증 |
| 접근성·작은 화면·태블릿 사용자 | “같은 정보와 조작을 잃지 않고 읽고 누를 수 있어?” | `docs/FIGMA_PROMPT.md`; 280/320/390px·240% 회귀 화면/테스트 | 고정 높이·분절 semantics·낮은 대비로 핵심 행동 불가 | 280/320px·240% reflow, 44/48px hit target, selected label, WCAG AA 대비; VoiceOver/TalkBack은 실기기 별도 검증 |

## 페르소나 간 충돌

- 라이트팬의 빠른 한눈 보기와 코어/데이터팬의 깊은 정보량은 Home=오늘·마이팀, Briefing=생성 문맥, Game detail=현재 경기라는 소유권으로 분리한다.
- 세밀한 알림은 차별점이지만 all-on은 피로를 만든다. 기본값을 바꾸기 전 delivery/receipt 데이터와 제품 결정을 분리한다.
- current truth와 historical snapshot-first는 경기 날짜·상태·payload identity를 기준으로 분리한다.

## 2026-08-13 합의 구현 slice

1. Home truthful slice: synthetic 최근 결과 버블을 제거하고 실제 verified final summary 또는 명시적 unavailable만 표시; nested CTA를 형제 action row로 분리한다.
2. Briefing identity slice: canonical route/entity/topic key로 동일 사실의 title/label 변형만 합치고, 서로 다른 metric·game·team 사실은 보존한다. 임의 `<=8` cap과 lead 다양성은 제품 결정으로 보류한다.
3. Push/pregame: 현재 follow와 pregame 조건은 소스상 존재하지만 APNs/FCM·iOS/Android 전달은 실기기 외부 게이트다. 기본값·새 preset·새 탭을 소스만으로 확정하지 않는다.

## 확인 불가 영역

- 실제 페르소나별 전환율·알림 피로도·첫 paint 체감·APNs/FCM 수신률.
- VoiceOver/TalkBack, iOS Live Activity, Android background, KST 자정 장시간 실행.
- API 수평 확장 시 분산 SingleFlight 및 snapshot retention 정책.
