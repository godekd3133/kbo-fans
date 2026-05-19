# KBO Fans Feature Graphics 5장 + Claude Design PPT 프롬프트

> 작성일: 2026-05-19  
> 목적: 실제 마케팅/발표자료 제작을 가정한 5장 Feature Graphics 구성  
> 시안 산출물: `docs/design/kbo-fans-feature-graphics-2026-05-19/index.html`

---

## 1. 제작 기준

### 포맷

- Claude Design / PPT 기준: **16:9 widescreen**
- 권장 작업 크기: **1920 × 1080**
- Google Play Feature Graphic 변환 시: **1024 × 500**, 24-bit PNG/JPEG, alpha 없음
- Feature Graphic 변환용 주의: 핵심 카피와 폰 mockup은 중앙 80% 안에 배치해 crop/cutoff에 강하게 만든다.

### 어톤

**Premium Korean Baseball Broadcast**

느낌:
- 경기장 전광판
- 스포츠 중계 그래픽
- 어두운 밤 경기장
- 실시간 데이터 관제판
- 팬이 직접 쓰는 앱

피해야 할 것:
- 일반 SaaS 랜딩페이지 느낌
- 너무 귀여운 팬 커뮤니티 느낌
- 앱 기능 설명서처럼 보이는 화면
- 야구와 무관한 추상 gradient
- 공식 구단 로고 무단 사용
- 앱 UI 안 이모지 사용

### 컬러 시스템

| 역할 | 색상 |
|------|------|
| Background | `#07090C` |
| Deep Surface | `#10141A` |
| Raised Surface | `#171D24` |
| Divider | `#323A45` |
| Primary Text | `#F7F9FC` |
| Secondary Text | `#A6B0BD` |
| Muted Text | `#6E7784` |
| Action Blue | `#2979FF` |
| Live Red | `#FF4444` |
| Field Green | `#18C67A` |
| Scoreboard Amber | `#FFD05A` |
| KIA Accent | `#D71920` |
| LG Accent | `#C30452` |

### 타이포그래피

- Korean: Pretendard
- Numeric emphasis: SF Pro Display / system numeric
- Headline: 70~96px equivalent, 아주 굵게
- Subcopy: 26~34px equivalent
- Slide 안의 UI mockup text는 작아도 되지만 headline은 thumbnail에서도 읽혀야 한다.

### 레이아웃 규칙

- 각 장은 하나의 강한 claim만 가진다.
- 화면당 핵심 폰 mockup 1~2개만 사용한다.
- 장식보다 실제 앱 경험을 먼저 보여준다.
- 카피는 짧고 직접적으로 쓴다.
- 팀 로고는 공식 로고 대신 `KIA`, `LG` 같은 텍스트 배지로 대체한다.

---

## 2. Feature Graphics 5장 구성

### 1장 — 마이팀 한눈 보기

Headline: **내가 선택한 팀을 한눈에**  
Subcopy: 오늘 경기, 현재 스코어, 다음 일정, 주요 선수 기록까지 내 팀 중심으로.  
Hero visual: My Team hub phone mockup  
Key proof: live score, next game, team rank, key player record, ticket CTA  
Intent: KBO Fans의 가장 큰 차별점인 마이팀 중심 경험을 첫 장에서 각인

### 2장 — 일정 / 예매 / 예매 알림

Headline: **일정 확인부터 예매 알림까지**  
Subcopy: 월간 경기 일정, 예매 정보, 예매 오픈 알림을 내 팀 기준으로 확인한다.  
Hero visual: Schedule calendar + ticket info phone mockup  
Key proof: monthly calendar, my-team filter, ticket vendor/time, ticket-open alert  
Intent: 경기 전 사용성, 예매 정보, 예매 알림 매력 강조

### 3장 — 다양한 경기 알림

Headline: **득점과 역전, 예매까지 알림**  
Subcopy: 득점, 역전, 경기 시작, 예매 오픈처럼 놓치기 쉬운 순간을 원하는 방식으로 받는다.  
Hero visual: Moment Subscription settings mockup  
Key proof: score alert, comeback alert, ticket-open alert, final result summary  
Intent: 일반 결과 알림보다 세밀한 야구 moment 알림을 차별점으로 표현

### 4장 — 실시간 중계 정보

Headline: **실시간 중계도 야구답게**  
Subcopy: 문자중계, 주자 상황, 볼카운트, 타석 흐름을 한 화면에서 확인한다.  
Hero visual: Live relay / field view phone mockup  
Key proof: base diamond, current at-bat, B/S/O, pitch strip, relay timeline  
Intent: 단순 스코어 앱이 아니라 야구 맥락을 이해하는 앱임을 강조

### 5장 — 선수 기록실

Headline: **선수 기록실도 한 번에**  
Subcopy: 마이팀 선수 현황, 리그 리더, 최근 기록까지 경기 흐름과 함께 확인한다.  
Hero visual: Player records / team records phone mockup  
Key proof: my-team player cards, league leaders, recent player form, player detail entry  
Intent: 코어팬이 매일 확인할 이유와 기록실 매력 강조

---

## 3. Claude Design용 PPT 프롬프트

아래 프롬프트를 Claude Design에 그대로 넣는다.

```text
Create a premium 5-slide 16:9 PowerPoint-style marketing deck for a Korean baseball mobile app called "KBO Fans".

Goal:
Make five feature graphics that could be used for app marketing, app store screenshots, investor/product presentation, or launch announcement. The deck should feel like a premium Korean baseball broadcast package, not a generic SaaS app deck.

Visual direction:
- Theme: Premium Korean Baseball Broadcast / Stadium Control Room
- Mood: live baseball, night stadium, broadcast scorebug, real-time fan control room
- Use dark high-contrast backgrounds, crisp white text, field green, live red, action blue, scoreboard amber
- Avoid cute fan-community visuals, generic purple gradients, stock photos, emoji, mascots, unlicensed official team logos, and cluttered dashboards
- Use text team badges like "KIA", "LG" instead of official logos
- Use realistic phone mockups showing actual app UI surfaces
- Design should look like it belongs to a sports media product and a serious mobile app

Canvas:
- 16:9 widescreen PowerPoint format
- Design for 1920 x 1080
- Keep headline and core UI inside central safe area so slides can later be adapted to Google Play 1024 x 500 feature graphics

Color system:
- Background: #07090C
- Deep surface: #10141A
- Raised surface: #171D24
- Divider: #323A45
- Primary text: #F7F9FC
- Secondary text: #A6B0BD
- Muted text: #6E7784
- Action blue: #2979FF
- Live red: #FF4444
- Field green: #18C67A
- Scoreboard amber: #FFD05A
- KIA accent: #D71920
- LG accent: #C30452

Typography:
- Korean-first UI and headline style
- Use Pretendard or a similar modern Korean sans-serif
- Very bold large headlines
- Numeric scores should feel like sports broadcast typography
- Short, direct Korean copy

Slide structure:
Each slide must have:
1. One dominant Korean headline
2. One short supporting line
3. One clear phone/app mockup proof object
4. Small broadcast-style labels or chips
5. No more than three visual ideas per slide

Slide 1:
Headline: "내가 선택한 팀을 한눈에"
Subcopy: "오늘 경기, 현재 스코어, 다음 일정, 주요 선수 기록까지 내 팀 중심으로."
Visual: My Team home hub phone mockup with KIA vs LG live score 5:3, 7회말, team rank, next game, key player record, and ticket CTA.
Feeling: This is the hero slide and strongest value proposition. It should immediately communicate personalization.

Slide 2:
Headline: "일정 확인부터 예매 알림까지"
Subcopy: "월간 경기 일정, 예매 정보, 예매 오픈 알림을 내 팀 기준으로."
Visual: Schedule screen phone mockup with monthly calendar, my-team filter, upcoming game cards, ticket vendor/time, and ticket-open alert button.
Feeling: Show pre-game utility: schedule, ticket information, and ticket reminders in one place.

Slide 3:
Headline: "득점과 역전, 예매까지 알림"
Subcopy: "득점, 역전, 경기 시작, 예매 오픈처럼 놓치기 쉬운 순간을 원하는 방식으로."
Visual: Notification Playbook phone mockup. Show rows for 예매 오픈, 경기 시작, 득점, 동점/역전, 최종 결과 with delivery modes like 바로, 요약, Live만, 끔.
Feeling: This is a smart baseball-specific alert system, not a generic notification toggle list.

Slide 4:
Headline: "실시간 중계도 야구답게"
Subcopy: "문자중계, 주자 상황, 볼카운트, 타석 흐름을 한 화면에서."
Visual: Live relay / field view phone mockup with base diamond, current at-bat, B/S/O, pitch strip, and event timeline.
Feeling: Show that KBO Fans understands live baseball context better than a plain score list.

Slide 5:
Headline: "선수 기록실도 한 번에"
Subcopy: "마이팀 선수 현황, 리그 리더, 최근 기록까지 경기 흐름과 함께."
Visual: Player records screen phone mockup with my-team player cards, league leaders, recent form, and player detail entry points.
Feeling: Appeal to core baseball fans who check stats every day.

Design details:
- Use subtle stadium-light lines, broadcast lower-third composition, scoreboard grids, and field-diamond motifs.
- Keep UI cards at 8px radius or less.
- Do not use emoji in app UI.
- Do not use official KBO or team logos unless provided; use text badges only.
- Make all slides feel like a cohesive campaign.
- The first slide should be the strongest thumbnail.
- The fifth slide should feel like a satisfying close, not a generic feature list.

Output:
Produce a polished editable PowerPoint-style deck with 5 slides.
Also provide a short speaker note per slide explaining the marketing intent.
```

---

## 4. Claude Design 보정 요청 프롬프트

첫 생성 결과가 밋밋하면 아래를 추가로 넣는다.

```text
Revise the deck to feel less like a generic app presentation and more like a premium baseball broadcast campaign.
Increase the scorebug / live sports broadcast feeling.
Make phone mockups larger and reduce generic feature cards.
Use fewer words, stronger Korean headlines, and clearer sports-data proof objects.
Make slide 1 work as a standalone app store feature graphic.
Keep the same color system and no official logos.
```

---

## 5. 산출물 체크리스트

- [x] 5장 feature graphic 구성
- [x] PPT 16:9 기준 정의
- [x] Google Play Feature Graphic 변환 기준 기록
- [x] 색상 / 폰트 / 어톤 / 금지 요소 정의
- [x] Claude Design 입력 프롬프트 작성
- [x] Claude Design 보정 프롬프트 작성
