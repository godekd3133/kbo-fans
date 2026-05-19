# KBO Fans UI/UX 디자인 철학 기반 v3 방향

> 작성일: 2026-05-19  
> 범위: 디자인 철학, 모바일 스포츠앱 레퍼런스, 플랫폼 UX 기준을 종합해 KBO Fans v3 시안 방향 정의  
> 후속 산출물: `docs/design/kbo-fans-mobile-ui-philosophy-v3-2026-05-19/index.html`

---

## 1. v3 결론

KBO Fans의 디자인 철학은 **Stadium Control Room for My Team**으로 잡는다.

단순한 스포츠 뉴스 피드나 점수판 앱이 아니라, 사용자가 앱을 여는 순간 `내 팀 지금 상태`, `지금 봐야 할 장면`, `다음 행동`을 바로 판단하게 만드는 모바일 관제판이다.

핵심 원칙:

| 원칙 | 설명 | 화면 적용 |
|------|------|-----------|
| Now / Next / Later | 지금 볼 것, 곧 일어날 것, 나중에 확인할 것을 분리 | 홈 첫 화면 구조 |
| Calm Live Data | 라이브 정보는 흥분시키되 사용자의 주의를 과도하게 뺏지 않음 | 알림, 위젯, Live Activity |
| Sport-Specific Density | 야구에만 필요한 밀도는 과감히 드러냄 | 주자, B/S/O, 투수 교체, 타순 |
| Fan Memory | 단순 현재 스코어가 아니라 팬이 기억할 장면을 남김 | 경기 상세, 결과 요약 |
| Inclusive by Default | 색상만으로 상태를 구분하지 않고, 큰 조작 영역과 명확한 문구 유지 | 모든 화면 |
| System, Not Screens | 화면별 임기응변이 아니라 반복 가능한 컴포넌트 체계로 설계 | 디자인 시스템 / Flutter 구현 |

---

## 2. 참고한 디자인 철학과 적용 판단

### 2.1 GOV.UK Service Design

GOV.UK Design Principles는 `Start with user needs`, `Do less`, `Design with data`, `Understand context`, `Build digital services, not websites`를 강조한다.

KBO Fans 적용:
- 앱 첫 화면은 “야구 포털”이 아니라 “내 팀 상태 확인”이라는 사용자 필요에서 출발한다.
- 모든 KBO 정보를 다 보여주기보다, 사용자가 경기 중 실제로 보는 정보만 우선한다.
- 예매/알림/위젯은 별도 기능이 아니라 경기 서비스 여정의 일부로 연결한다.

### 2.2 Calm Technology

Calm Tech는 가능한 적은 주의만 요구하고, 실패해도 동작하며, 최소한의 기술로 문제를 풀어야 한다고 본다.

KBO Fans 적용:
- Live Activity와 위젯은 앱 축소판이 아니라 최소 상태판이다.
- 알림은 모든 이벤트를 밀어내는 구조가 아니라 `관심도 다이얼`로 조절한다.
- 데이터가 늦거나 stale이면 숨기지 않고 작게 표시해 사용자를 안정시킨다.

### 2.3 Apple HIG / Widgets / Live Activities

Apple은 터치 타깃 44pt, 최소 11pt 텍스트, 명확한 대비를 제시한다. Widgets와 Live Activities는 한눈에 보는 최신 상태, 직접 관련된 딥링크, 앱 같은 복잡한 레이아웃 회피를 강조한다.

KBO Fans 적용:
- 위젯은 `점수 / 이닝 / 주자 / 업데이트 시각`만 둔다.
- Live Activity는 야구 특화 요소인 주자, B/S/O, 아웃을 우선한다.
- 위젯 탭은 관련 경기 상세로 바로 연결되어야 한다.

### 2.4 Material 3 / Android

Material 3는 접근 가능한 색상 역할, adaptive navigation, 적절한 navigation component 사용을 강조한다.

KBO Fans 적용:
- 최상위 5탭은 유지하되, 상세 탭은 내부 전환으로 둔다.
- 팀 컬러는 identity layer로 쓰고, 상태 의미는 별도 semantic color와 label로 표시한다.
- Android large screen 대응 시 navigation rail로 확장 가능한 구조를 유지한다.

### 2.5 Microsoft Inclusive Design

Microsoft Inclusive Design은 exclusion을 인식하고, 다양성에서 배우며, 한 사람을 위해 풀면 많은 사람에게 확장된다고 설명한다.

KBO Fans 적용:
- 색각 이상 사용자를 위해 LIVE/종료/취소를 색상만으로 구분하지 않는다.
- 야구 초심자도 이해할 수 있게 B/S/O와 주자 상태를 텍스트와 시각 요소로 같이 보여준다.
- 한 손 조작, 큰 터치 영역, 낮은 인지 부하를 기본 품질로 둔다.

### 2.6 IBM Design Language / Carbon

IBM은 “carefully considered”, “uniquely unified”, “expertly executed”를 원칙으로 두고, 불필요한 것을 제거하고 재사용 가능한 해법을 강조한다.

KBO Fans 적용:
- 화면별 장식을 늘리기보다 카드, 상태 칩, 점수 모듈, 타임라인을 반복 가능한 패턴으로 설계한다.
- UI의 개성은 장식이 아니라 `야구 정보 구조`에서 나온다.
- 같은 정보는 같은 형태로 보여준다. 예: LIVE 상태, stale, 예정, 종료.

### 2.7 Atomic Design

Atomic Design은 UI를 계층적 컴포넌트와 패턴 라이브러리로 생각하게 한다.

KBO Fans 적용:
- `StatusChip`, `ScorePair`, `BaseDiamond`, `AtBatCard`, `GameCard`, `LiveEventSurface`를 기본 단위로 본다.
- Figma/Flutter 구현 시 페이지보다 컴포넌트 contract를 먼저 맞춘다.

### 2.8 Baymard Mobile App UX

Baymard는 모바일 앱에서 명확한 탐색 경로, 스코프가 분명한 홈 링크, 과도하게 큰 horizontal scroll 영역 회피를 강조한다.

KBO Fans 적용:
- 기록실/일정/순위로 들어가는 경로는 하단 탭과 홈 카드에서 명확히 드러낸다.
- 홈 카드 CTA는 “보기” 같은 모호한 말보다 “문자중계”, “오늘 기록”, “알림 설정”처럼 스코프를 드러낸다.
- 홈을 과도한 캐러셀로 채우지 않고, 세로 스캔 구조를 유지한다.

### 2.9 ESPN / theScore / MLB Live Activity 계열

스포츠앱 레퍼런스에서는 공통적으로 개인화, 빠른 스코어 확인, 명확한 game card, 경기 특화 Live Activity가 중요하다. theScore는 종목별 Live Activity 정보로 MLB에 bases/B/S/O를 사용한다고 설명한다.

KBO Fans 적용:
- ESPN식 멀티스포츠 포털이 아니라, KBO + 마이팀에 집중한다.
- theScore/MLB식 라이브 표면은 `야구 특화 정보`를 우선한다.
- 권한 요청은 앱 진입 즉시 밀어붙이지 않고, 사용자가 알림 가치를 본 뒤 요청한다.

### 2.10 Atlassian Content Design

Atlassian은 UI 콘텐츠가 명확하고 일관되어야 한다고 본다.

KBO Fans 적용:
- CTA 문구는 기능명이 아니라 사용자가 얻는 결과를 말한다.
- 예: `보기` 대신 `문자중계`, `알림` 대신 `득점권 알림`.

### 2.11 IDEO Design Thinking

IDEO는 desirability, viability, feasibility의 균형을 이야기한다.

KBO Fans 적용:
- Desirable: 팬이 경기 중 실제로 열고 싶은가?
- Viable: KBO 데이터 신뢰도와 운영 비용 안에서 가능한가?
- Feasible: Flutter/WidgetKit/FCM/backend 구조로 구현 가능한가?

---

## 3. v3 시안 방향

### 3.1 화면 콘셉트

**Broadcast-grade, not generic dark app.**

검은 카드 UI를 반복하는 것이 아니라, 실제 경기장 전광판/중계 그래픽/덕아웃 기록지를 모바일에 맞게 압축한다.

구성:
- 상단: 현재 경기 상태를 방송 스코어버그처럼 고정
- 중단: 지금 봐야 할 장면을 주자/타석/투수 중심으로 표현
- 하단: 다음 행동과 하단 탭
- 앱 밖: 위젯과 Live Activity는 아주 작은 야구 전광판처럼 동작

### 3.2 정보 구조

홈은 `Now / Next / Later`로 나눈다.

| 영역 | 목적 | 예시 |
|------|------|------|
| Now | 지금 경기 상태 판단 | 스코어, 이닝, 주자, B/S/O, 타석 |
| Next | 곧 봐야 할 맥락 | 다음 타순, 투수 교체, 알림 |
| Later | 경기 후/다음 경기 | 결과 요약, 기록실, 일정 |

### 3.3 시각 언어

- 배경: 거의 검정에 가까운 중계 장비 톤
- 주요 대비: 흰색 숫자, 선명한 LIVE red, field green, scoreboard amber
- 팀 컬러: 카드 accent와 team marker에만 제한
- 형태: 8px 이하 radius 중심, 점수/상태는 방송 그래픽처럼 직선적
- 밀도: 숫자와 상태는 크고 명확하게, 설명 텍스트는 짧게

### 3.4 버릴 것

- 야구와 무관한 hero/marketing layout
- 앱 UI 안의 이모지
- 설명성 온보딩 텍스트 과다
- 색상만으로 의미 전달
- 큰 가로 캐러셀 남발
- 권한 요청을 가치 제시 전에 먼저 띄우는 흐름
- 위젯을 앱 축소판처럼 만드는 것

---

## 4. v3 제작 체크리스트

- [x] 다양한 디자인 철학과 플랫폼 기준 조사
- [x] KBO Fans에 맞는 핵심 디자인 철학 정의
- [x] 스포츠앱 라이브 데이터 패턴 반영
- [x] `Now / Next / Later` 홈 구조 정의
- [x] 야구 특화 Live Activity / Widget 원칙 반영
- [x] 반복 가능한 컴포넌트 체계 반영
- [x] v3 HTML 시안 제작

---

## 5. 참고 링크

- GOV.UK — Government Design Principles: https://www.gov.uk/guidance/government-design-principles
- Calm Tech Institute — Principles of Calm Technology: https://www.calmtech.institute/calm-tech-principles
- Apple Developer — UI Design Dos and Don'ts: https://developer.apple.com/design/tips/
- Apple Developer — Widgets: https://developer.apple.com/design/human-interface-guidelines/widgets
- Apple Developer — Live Activities: https://developer.apple.com/design/human-interface-guidelines/live-activities
- Android Developers — Material 3 in Compose: https://developer.android.com/develop/ui/compose/designsystems/material3
- Microsoft Inclusive Design: https://inclusive.microsoft.design/
- Microsoft Learn — Designing inclusive software: https://learn.microsoft.com/windows/apps/design/accessibility/designing-inclusive-software
- IBM Design Language — Principles: https://www.ibm.com/design/language/philosophy/principles/
- Brad Frost — Atomic Design: https://atomicdesign.bradfrost.com/
- Baymard Institute — Mobile App UX Trends 2026: https://baymard.com/blog/mobile-app-ux-trends
- theScore — Live Activities & Events: https://www.thescore.com/news/2885302
- ScreensDesign — ESPN Live Sports & Scores UI Breakdown: https://screensdesign.com/showcase/espn-live-sports-scores
- Atlassian Design System — Content: https://atlassian.design/foundations/content
- IDEO — Design Thinking: https://designthinking.ideo.com/introduction
