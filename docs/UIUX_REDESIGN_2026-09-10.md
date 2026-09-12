# KBO Fans UI/UX 전면 재구축 — 2026-09-10

## 결정

사장님이 새 시안 1번을 선택했고, 팀 로고가 반드시 보이도록 수정 시안을 요청했다. 수정 시안은 기존 1번의 정보 구조를 유지하면서 추상 문자 배지를 제거하고 저장소의 실제 KBO 투명 엠블럼을 사용하는 방향으로 확정했다.

선택한 화면의 핵심 순서는 다음과 같다.

1. 내 팀 경기와 점수
2. 오늘 경기 목록
3. 내 팀 기록
4. 홈·일정·기록·브리핑·설정의 일관된 탐색

장식용 경기장 사진, 손글씨 문구, 마케팅 배너, 가짜 선수 이미지와 불필요한 기능 카드는 정상 데이터 화면에서 제외한다. 숫자·상태·다음 행동이 가장 먼저 읽혀야 한다.

## 시각 기준

- 대상 프레임: 390×844 모바일
- 기본 방향: 조용한 스코어보드형 다크 스포츠 앱
- 배경: `#0F0F0F` / surface `#171717` / card `#1D1D1D`
- 텍스트: 주 `#F7F9FC` / 보조 `#A6B0BD` / disabled `#6E7784`
- 상태: LIVE `#FF4444`, 긍정 `#00C853`, 액션 `#2979FF`, 볼 카운트 `#FFD600`
- 라운드: hero 12px, 일반 surface 8px, sheet 24px
- 글꼴: Jua를 표시용 기준으로 유지하고 NanumSquareRound·Pretendard를 fallback으로 사용
- 팀 컬러는 카드 전체 배경이 아니라 3px rail, 로고, 선택 상태와 CTA에만 사용
- 정상 정보 화면에서는 추상 배지 대신 `assets/visuals/reference_team_logos/`의 실제 팀 엠블럼을 우선 사용

## 구현 범위

### 공통

- `app/lib/core/widgets/app_design_system.dart`
  - `AppSurface`, `AppPageHeader`, `AppSectionHeader`, `AppStatusPill`, `AppTeamIdentity`, `AppMetricLine`
  - 공통 surface, 상태, 접근 가능한 44px pressable 조합을 제공한다.
- `app/lib/core/widgets/app_page_frame.dart`
  - 페이지 콘텐츠를 explicit child semantics boundary로 감싸 상위 화면 요약과 내부 action 탐색을 분리한다.
- `app/lib/core/widgets/main_scaffold.dart`
  - 모바일 5탭과 700px 이상 rail의 선택 상태를 액션 accent 중심으로 정리한다.
- `app/lib/core/theme/app_theme.dart`
  - 기본 Material 하단 내비게이션의 선택 토큰도 action accent를 사용하도록 고정해, 보조 화면이 기본 내비게이션을 사용해도 LIVE red가 재유입되지 않게 한다.
- `app/lib/features/home/home_screen.dart`
  - 홈 알림 아이콘은 로컬 알림함의 미읽음 수를 badge와 tooltip에 함께 표시하고, 알림 저장·읽음 처리·알림함 복귀·앱 resume 뒤에도 현재 상태를 다시 계산한다.
  - 최근 5경기 오류·빈 상태의 CTA는 일정 화면으로 연결하고, 예매 quick item의 legacy ISO timestamp는 KST 사용자 표시로 정규화한다.
  - 예정 `big_match` 인사이트 score strip은 중복 `예정` 대신 `팀 vs 팀`과 시작 시각을 표시하고, 일반 insight 제목은 유지한다.
- `app/lib/features/settings/api_diagnostics_screen.dart`
  - 운영 진단을 다시 실행하는 동안 버튼을 비활성화하고 진행 상태를 보여 중복 요청을 막는다.
- `app/lib/features/records/records_screen.dart`
  - 리그·팀 기록 refresh가 진행되는 동안 새로고침 액션을 잠그고 spinner를 표시해 중복 provider 요청을 막는다.
- `app/lib/features/standings/standings_screen.dart`
  - 순위 refresh가 진행되는 동안 header·retry 액션을 잠그고 spinner를 표시해 중복 provider 요청을 막는다.
- `app/lib/features/schedule/schedule_screen.dart`
  - 월별·시즌 매치업 refresh가 진행되는 동안 오류 retry를 잠가 중복 provider fan-out을 막는다.
- `app/lib/features/news/news_screen.dart`
  - 브리핑 refresh가 진행되는 동안 header와 오류 retry를 잠그고 action accent spinner를 표시한다.
- `app/lib/features/notifications/notification_inbox_screen.dart`
  - 알림 목록과 설정 loader의 동시 refresh·retry를 coalescing해 inbox와 playbook 상태가 서로 덮어쓰지 않게 한다.
- `app/lib/features/records/player_detail_screen.dart`
  - 선수 상세 refresh와 retry가 같은 player provider를 중복 호출하지 않도록 단일 in-flight 상태를 사용한다.
- `app/lib/features/settings/api_diagnostics_screen.dart`
  - 각 진단 카드는 상태·detail·소요시간·note를 하나의 보조기술 요약으로 제공한다.
- `app/lib/features/records/records_area_switcher.dart`
  - 순위표·선수 기록 선택을 LIVE red가 아닌 액션 blue로 분리한다.
- `app/lib/features/settings/settings_screen.dart`
  - 화면 모드 선택은 각 옵션을 하나의 button semantics로만 노출하고 selected 상태를 유지한다.
  - 탭 가능한 섹션 row는 `AppPressable`이 단일 button semantics를 소유하도록 해 외부 중복 wrapper를 만들지 않는다.
- `app/lib/features/game_detail/tabs/boxscore_tab.dart`
  - 매칭된 선수 행의 요약 semantics가 실제 선수 기록 진입 tap action을 함께 제공한다.
- `app/lib/features/game_detail/game_detail_screen.dart`
  - 경기 상세 상단 뒤로가기는 하나의 label·button·tap semantics만 노출한다.
- `app/lib/core/widgets/app_motion.dart`
  - 명시 label이 있는 공통 pressable은 semantic boundary로 격리해 부모 제목·설명과 action label이 합쳐지지 않게 한다.
- `app/lib/features/schedule/schedule_screen.dart`
  - 월 헤더의 이전·다음·오늘 action은 공통 labeled pressable 하나로만 노출한다.
- `app/lib/features/home/home_screen.dart`
  - 순위 미리보기 행의 팀 상세 action은 하나의 labeled pressable로만 노출한다.
- `app/lib/features/onboarding/onboarding_screen.dart`
  - 팀 카드 selected 상태를 공통 pressable에 직접 연결한다.
- `app/lib/features/records/records_screen.dart`
  - 팀 상세 상단 뒤로가기는 하나의 label·button·tap semantics만 노출한다.
- `app/lib/features/onboarding/onboarding_screen.dart`
  - 편집 모드의 뒤로가기는 하나의 label·button·tap semantics만 노출한다.
- `app/lib/core/widgets/app_design_system.dart`
  - 페이지 헤더는 explicit child semantics container로 action과 제목·설명을 분리한다.
- `app/lib/features/home/home_screen.dart`
  - 알림·검색 header icon은 badge/count를 포함한 단일 labeled button semantics를 제공한다.
- `app/lib/features/game_detail/game_detail_screen.dart`
  - 영상 mode chip은 selected 상태를 action-blue 선택 semantics로 전달한다.
- `app/lib/features/records/records_screen.dart`
  - 마운드 체크 category는 action blue를 사용하고 LIVE red는 경기 상태에만 사용한다.
- `app/lib/features/home/home_screen.dart`
  - 홈 헤더 아이콘은 최소 44px 조작 영역과 직접 labeled action semantics를 제공한다.
- `app/lib/features/standings/standings_screen.dart` / `app/lib/features/records/records_screen.dart`
  - 시즌 선택 surface는 최소 44px 높이를 유지한다.
- `app/lib/features/settings/patch_notes_screen.dart` / `app/lib/features/settings/release_notes_prompt.dart`
  - 현재 버전·변경점 묶음을 하나의 접근성 요약으로 읽히게 하고, 시각 텍스트의 중복 semantics를 제외한다.
- `backend/src/kbo_fans_backend/services/scoreboard.py` / `backend/src/kbo_fans_backend/services/home.py`
  - 예정·취소 경기의 score는 원천 placeholder `0`을 verified 값으로 승격하지 않고 `null`로 유지하며, quick item은 `vs`로 표시한다.

### 화면

- 홈 헤더를 실제 KST 날짜·브랜드·알림·검색 구조로 정리한다.
- 홈 알림 아이콘에는 미읽음 알림 수를 즉시 인지할 수 있는 red badge를 표시하고, badge 숫자는 tooltip에서도 읽을 수 있게 한다. 알림함 변경 stream과 앱 resume을 통해 홈이 열린 상태에서도 badge를 최신으로 유지한다.
- 홈 LIVE 카드에 양 팀 실제 로고, 중앙 점수, 이닝, 경기장과 문자중계 진입을 배치한다.
- 미확정 점수는 중앙에 `–`를 한 번만 표시하며 0점으로 추정하지 않는다.
- 홈 오늘 경기 행은 실제 로고와 상태·스코어를 유지하면서 compact 높이를 보존한다.
- 온보딩·일정·기록·브리핑·순위·설정의 페이지 헤더 구조를 공통 `AppPageHeader`로 통일한다.
- 경기 상세 scorebug에서 정상 데이터 화면의 삽입형 배경 이미지를 제거하고 실제 팀 로고와 점수 대비를 우선한다.
- 알림함·리그 리더보드·선수 상세·API 진단·업데이트 소식도 동일한 페이지 헤더·surface·상태 언어를 사용한다.
- 리더보드의 공식 지표 선택은 액션 블루로 구분하고, LIVE red는 경기 상태와 오류에만 사용한다.
- 선수 상세는 팀 rail, 대표 기록, 시즌 기록, 최근 경기 순서로 읽히며 긴 콘텐츠에서도 surface 높이가 데이터에 맞게 계산된다.
- 알림함은 `AppPageHeader`와 액션 블루 필터를 사용하고, 직접 URL 진입에서도 `/home` 복귀를 보장한다.
- 운영용 API 진단과 업데이트 소식은 직접 URL 진입에서도 `/settings` 복귀를 보장해 상세 화면의 이동 규칙을 통일한다.
- 경기 상세 스코어 탭의 정상 이닝 표는 장식 artwork 없이 평면 데이터 surface를 사용하고, 빈/오류 상태에서만 상태 설명용 artwork를 허용한다.
- 라인업 탭은 선발 라인업과 선발 투수를 첫 콘텐츠로 두고, 비교 데이터가 있을 때만 최근 흐름·맞대결 카드를 아래에 추가한다.
- 문자중계의 회차·주요 장면 필터는 action blue로 선택 상태를 표시하고, 이벤트 카드의 득점·교체·종료 색상과 분리한다.
- 박스스코어 LIVE context는 팀 요약 헤더에 `LIVE` 상태 pill을 먼저 표시하고, 공식 기록 집계 전이라는 설명과 현재 집계값을 함께 보여준다.
- 설정의 푸시 알림 프리셋은 일반 선택이므로 테마 액션 블루를 사용하고, 마이팀 대상 스트립만 팀 색상을 유지한다.
- 브리핑의 목적 필터는 테마 액션 블루를 사용하고, 경기·순위·기록 카드의 강조색은 콘텐츠 의미를 위해 유지한다.
- 일정의 보기 모드·팀 필터·선택 날짜는 액션 블루를 사용하고, 경기 있는 날짜 outline과 경기 상태 표시는 red 의미색으로 유지한다.
- 기록실의 선수 목록·정렬·리더보드 그룹·지표 선택은 액션 블루를 사용하고, 선수·지표 데이터에 속한 팀/metric 의미색은 유지한다.
- standalone 리더보드도 타자·투수 그룹 선택을 같은 액션 블루 규칙으로 사용한다.
- 홈 순위 미리보기의 마이팀 강조는 팀의 readable color를 사용하고, LIVE red는 진행 중 경기 상태에만 사용한다.
- 홈 최근 결과는 승리 positive green, 패배 red, 무승부 action blue로 구분하고 연승·연패도 같은 의미 체계를 따른다.
- 경기 상세 하이라이트 재생 모드 선택은 액션 블루를 사용하고, 경기 상태·이벤트 의미색과 분리한다.
- 업데이트 소식의 설치 버전 badge와 bullet marker는 액션 블루를 사용하고, LIVE/오류 red는 운영 상태에만 사용한다.
- 앱 시작 업데이트 prompt도 설치 버전 화면과 같은 액션 블루 상태 언어를 사용한다.
- 데이터 로딩 indicator는 액션 블루를 사용하고, LIVE·오류·경기 이벤트 red는 실제 상태 의미에만 사용한다.
- pull-to-refresh indicator도 액션 블루를 사용하고, LIVE red는 경기 상태에만 사용한다.
- 브리핑 화면도 동일한 action-blue pull-to-refresh 상태를 사용한다.
- 브리핑의 예정 경기 quick item도 score가 미제공이면 `팀 vs 팀`으로 표시하고 `0 : 0`을 추정하지 않는다. LIVE/FINAL의 확인된 0:0은 실제 동점으로 유지한다.
- 홈 최근 5경기 오류·빈 상태는 `일정 보기` CTA로 `/schedule`에 진입해 결과 확인 경로를 제공한다.

데이터 provider, API 응답 계약, 경기 상태 코드, KST 계산, 캐시·refresh·deep link 소유권은 이번 시각 변경에서 바꾸지 않는다.

## 로고 자산

선택 시안에는 다음 실제 자산을 사용한다.

- `app/assets/visuals/reference_team_logos/LG.png`
- `app/assets/visuals/reference_team_logos/OB.png`
- `app/assets/visuals/reference_team_logos/HH.png`
- `app/assets/visuals/reference_team_logos/SS.png`
- `app/assets/visuals/reference_team_logos/WO.png`
- `app/assets/visuals/reference_team_logos/KT.png`

전체 10개 팀은 `KboTeamLogoImage`가 동일한 reference asset 경로를 통해 렌더링한다. 파일이 실패할 때만 기존 네트워크·텍스트 fallback을 사용한다.

## 검증 경계

- 정적: `fvm flutter analyze`는 현재 변경 후 `No issues found`.
- 회귀: theme·navigation·home·schedule·news·settings·standings·records·onboarding·game detail 대상 테스트와 Flutter 전체 `623 passed`를 확인했다. 홈 unread badge·header hit target·실시간 동기화 회귀는 `55 passed`, inbox loader coalescing 회귀는 `11 passed`, 선수 상세 refresh 회귀는 `5 passed`, API 진단·semantics 회귀는 `3 passed`, 업데이트 prompt 회귀는 `9 passed`, Patch Notes semantics 회귀는 `3 passed`, 설정·박스스코어 접근성 회귀를 포함한 focused 묶음은 `43 passed`, 경기 상세 navigation 회귀는 `30 passed`, 공통 `AppPressable` semantics 회귀는 `7 passed`, 페이지 헤더 boundary 회귀는 `1 passed`, 일정 header semantics 회귀를 포함한 schedule suite는 `26 passed`, 홈·온보딩 focused 묶음은 `65 passed`, 게임 상세 mode chip selected semantics 회귀를 포함한 detail focused run은 `37 passed`, 기록실 팀 상세 뒤로가기 회귀는 `3 passed`, 기록실 player-image/category color focused run은 `11 passed`, 순위·기록실 시즌 selector geometry 회귀를 포함한 focused 묶음은 `13 passed`, 기록실 refresh 중복 실행 회귀는 `2 passed`, page frame semantics suite는 `6 passed`다.
- 최신 회귀: 앱 전체 Flutter `623 passed`, backend 전체 `720 passed`, 브리핑 예정 quick item focused suite `22 passed`, 홈 focused suite `55 passed`, backend Home/Scoreboard producer-consumer focused suite `90 passed`를 확인했다.
- 최신 설정 row semantics 정리의 focused settings suite는 `22 passed`이며, 각 탭 가능한 섹션 row가 외부 중복 button wrapper 없이 `AppPressable` 하나로 동작하는 현재 구조를 확인했다.
- 시각: release web build 성공 후 390px CDP viewport에서 홈·기록 화면을 캡처했고, 2026-09-12 KST fresh API/Web AX에서 예정 LG-삼성 경기를 `vs`와 score 미제공으로 재확인했다. 실제 LIVE 카드의 실데이터 렌더링은 소스 코드와 기존 fixture 테스트로 분리 확인한다.
- 미검증: 실기기 VoiceOver/TalkBack, 실제 LIVE 경기, FCM/APNs, Live Activity, Claim·지갑·정산과 TestFlight/Play 외부 배포.

페이지별 구현 시안과 상태별 우선순위는 `docs/design_refs/2026-09-10-page-by-page-screens.md`에 고정했다. 현재 캡처에서 확인한 화면은 홈·일정·순위·기록실·브리핑·설정·온보딩·알림함·경기 상세 score/relay·리더보드·선수 상세·API 진단·업데이트 소식이며, 박스스코어·라인업은 앞선 안정화 캡처와 해당 탭 회귀 테스트를 함께 사용한다.

선택 시안 원본은 `artifacts/uiux-redesign-2026-09-10/selected-home-with-team-logos.png`에 보관한다. 이 파일은 구현 목표를 설명하는 디자인 기준이며, Figma MCP 작업 완료나 실제 운영 데이터 증거를 의미하지 않는다.
