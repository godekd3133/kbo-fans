# KBO Fans UI/UX 레퍼런스 기반 v2 방향

> 작성일: 2026-05-19  
> 범위: 모바일 UI/UX 원칙, 접근성 기준, 플랫폼 패턴, 위젯/Live Activity 레퍼런스를 KBO Fans 디자인에 반영  
> 후속 산출물: `docs/design/kbo-fans-mobile-ui-reference-v2-2026-05-19/index.html`

---

## 1. 참고한 원칙

### 1.1 최상위 내비게이션은 3~5개 목적지

Android Developers의 Material 3 NavigationBar 문서는 compact 화면에서 같은 계층의 3~5개 목적지에 navigation bar를 쓰도록 설명한다. KBO Fans의 `홈 / 일정 / 순위 / 기록실 / 설정` 5탭은 이 범위 안에 들어간다.

적용:
- 5탭은 유지한다.
- 경기 상세의 `스코어 / 문자중계 / 박스스코어 / 라인업`은 최상위 탭이 아니라 상세 내부 탭으로 유지한다.
- 예매, 알림, 위젯, 진단은 하단 탭으로 승격하지 않고 각 문맥 안의 CTA나 설정으로 둔다.

### 1.2 기존 사용자의 정신 모델을 활용

Android layout/navigation guide는 사람들이 이미 알고 있는 navigation pairing을 쓰면 앱이 더 직관적이라고 설명한다. KBO Fans는 야구 앱이므로, 사용자가 기대하는 기본 흐름은 `오늘 경기 → 경기 상세 → 기록 확인`이다.

적용:
- 홈 첫 화면은 새로운 탐색 구조보다 `오늘 내 팀 상태`를 바로 보여준다.
- 경기 상세에서는 상단 스코어를 고정해 탭을 이동해도 현재 경기 맥락을 잃지 않게 한다.
- 기록실은 별도 탭이지만 홈에서는 리더/선수 요약 카드로 들어가는 진입점을 둔다.

### 1.3 시스템 상태 가시성

Nielsen Norman Group의 휴리스틱은 사용자가 무슨 일이 진행 중인지 알 수 있도록 적절하고 시기적절한 피드백을 제공해야 한다고 설명한다.

적용:
- LIVE 상태, stale 상태, 마지막 업데이트 시간을 화면 안에 명확히 둔다.
- 네트워크 지연/스냅샷 fallback 상태는 개발자용 로그에만 숨기지 않고, 사용자에게 필요한 수준의 `업데이트 n분 전`으로 표현한다.
- 위젯과 Live Activity에는 stale 표시가 필수다.

### 1.4 인지보다 인식

NN/g 휴리스틱은 사용자가 정보를 기억하게 만들기보다 화면의 요소와 선택지를 보이게 해야 한다고 설명한다.

적용:
- “마이팀을 선택하면 뭐가 달라지는지”를 온보딩과 홈 미선택 상태에서 직접 보여준다.
- 알림 설정은 개별 토글 나열만 하지 않고 `가볍게 보기 / 내 팀 집중 / 풀타임 팔로우` 프리셋으로 먼저 선택하게 한다.
- 경기 상세의 현재 타석 카드에는 타자/투수/BSO/주자/직전 플레이를 한 블록으로 묶는다.

### 1.5 불필요한 정보는 경쟁자

NN/g의 미니멀 디자인 원칙은 관련 없는 정보가 중요한 정보와 경쟁한다고 본다.

적용:
- 홈은 스코어/상태/다음 행동 중심으로 두고, 관중수/불필요한 전체 카운트/종료 경기 예매 CTA는 제거한다.
- 순위는 기본 열을 `순위 / 팀 / 승패무 / 승률 / 게임차`로 제한하고, 최근 10경기/연속/홈원정은 확장 정보로 둔다.
- 기록실은 첫 화면에서 마이팀 현황과 리그 리더만 먼저 보여준다.

### 1.6 터치 타깃과 접근성

WCAG 2.2 기준에서 pointer target minimum은 24x24px이고, AAA target size는 44x44px이다. 모바일 앱에서는 실제 조작 영역을 44px 이상으로 잡는 편이 안전하다.

적용:
- 하단 탭, 경기 카드, 프리셋, 토글, 주요 CTA는 44px 이상의 터치 영역을 가진다.
- 텍스트로 보이는 라벨과 접근성 이름이 어긋나지 않게 한다.
- 중요한 상태는 색상만으로 구분하지 않고 라벨도 함께 둔다.

### 1.7 앱 밖 경험은 glanceable

Apple Support는 위젯을 현재 정보를 한눈에 보는 방법으로 설명하고, Apple ActivityKit 문서는 Live Activities가 Lock Screen/Dynamic Island 등에서 최신 정보를 보여주는 구조라고 설명한다.

적용:
- 위젯은 “앱을 열지 않고 내 팀 상태 확인”에 집중한다.
- Live Activity는 경기 중 스코어/이닝/주자/업데이트 시각만 보여주고, 투구별 로그는 앱 상세로 연결한다.
- 경기 전에는 countdown/시작 시간, 경기 중에는 LIVE, 종료 후에는 final 요약으로 상태를 바꾼다.

---

## 2. v2 디자인 원칙

| 원칙 | KBO Fans 적용 |
|------|---------------|
| Glance First | 홈/위젯/Live Activity는 3초 안에 상태 판단 |
| My Team First | 마이팀 브리프를 홈 첫 번째 정보 단위로 고정 |
| Progressive Depth | 홈 요약 → 경기 상세 → 기록실 순서로 정보 깊이 증가 |
| State Honesty | LIVE/stale/final/cancelled를 숨기지 않고 표시 |
| Dense But Legible | 야구 정보는 밀도 있게, 조작 요소는 넓게 |
| One-Handed Control | 5탭 + 큰 카드 탭 + sticky detail header |
| No Surprise Alerts | 프리셋과 발송 예시를 먼저 보여주고 세부 토글 노출 |

---

## 3. 화면별 v2 보강

### 홈

- Hero 영역을 `My Team Game Console`로 정의한다.
- 마이팀 경기가 live면 `스코어 / 이닝 / 주자 / 직전 플레이 / 마지막 업데이트`를 한 번에 보여준다.
- 경기 전이면 `선발 / 라인업 상태 / 알림 / 예매`를 보여준다.
- 경기 없음이면 빈 화면 대신 `다음 경기 / 순위 / 최근 흐름`으로 전환한다.

### 경기 상세

- 상세 상단은 경기 상태를 잃지 않게 sticky score header로 유지한다.
- 문자중계는 로그 리스트가 아니라 현재 타석 카드와 이벤트 타임라인으로 나눈다.
- B/S/O는 색과 라벨을 함께 사용한다.
- 종료 경기에는 `결과 요약`을 스코어 탭 상단에 넣는다.

### 일정

- 캘린더 점 표시는 경기 있음/마이팀/취소를 구분한다.
- 예정 경기 카드에는 예매/알림을 표시하지만, 종료/취소 경기에는 숨긴다.
- 마이팀 필터는 상단 주요 제어로 둔다.

### 기록실

- 기록실 첫 화면은 마이팀 선수 현황과 리그 리더를 병렬로 보여준다.
- 선수 상세는 시즌 누적보다 최근 흐름을 먼저 둔다.
- 홈의 빠른 카드에서 기록실로 진입할 수 있게 한다.

### 설정/알림

- 알림 프리셋을 먼저 선택하게 한다.
- 프리셋 선택 후 세부 토글을 조정할 수 있게 한다.
- 각 토글은 발송 예시를 함께 보여준다.

### 위젯/Live Activity

- 위젯은 Small/Medium/Lock 상태를 분리한다.
- Live Activity에는 `스코어 / 이닝 / 주자 / stale`만 둔다.
- 상세 로그는 앱 진입으로 연결한다.

---

## 4. v2 제작 체크리스트

- [x] 5탭 구조 유지
- [x] 하단 탭과 주요 버튼 터치 영역 44px 이상
- [x] LIVE/stale/업데이트 시각 표시
- [x] 홈에 마이팀 브리프 우선 배치
- [x] 문자중계 현재 타석 카드와 이벤트 타임라인 분리
- [x] 알림 프리셋과 발송 예시 표시
- [x] 위젯/Live Activity의 glanceable 상태 시각화
- [x] 레퍼런스 기반 근거 문서화

---

## 5. 참고 링크

- Android Developers — Navigation Bar: https://developer.android.com/develop/ui/compose/components/navigation-bar
- Android Developers — Layouts and navigation patterns: https://developer.android.com/design/ui/mobile/guides/layout-and-content/layout-and-nav-patterns
- Nielsen Norman Group — Jakob's Ten Usability Heuristics: https://media.nngroup.com/media/articles/attachments/Heuristic_Summary1_A4_compressed.pdf
- WebAIM — WCAG 2 Checklist: https://webaim.org/standards/wcag/WCAG2Checklist.pdf
- Apple Support — Add, edit, and remove widgets on iPhone: https://support.apple.com/en-gb/guide/iphone/iphb8f1bf206/26/ios/26
- Apple Developer — Displaying live data with Live Activities: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
