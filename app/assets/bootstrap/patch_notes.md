# 패치노트

## 0.0.60+60 - Live Activity Current At Bat

- Live Activity에서 초/말에 따라 현재 타자와 투수가 뒤바뀌던 표시를 보정했습니다.
- relay 기반 타율, ERA, 투구수, B-S-O 정보를 Lock Screen 표면에 함께 표시하도록 보강했습니다.
- `API_BASE_URL`이 들어간 release/direct 빌드에서도 remote push 등록과 자동 권한 요청이 유지되도록 정리했습니다.
- 문자중계 주자 상태가 `주자1,2루`처럼 축약돼도 베이스 다이아몬드가 정확히 채워지도록 보정했습니다.
- 기록 탭 상단에 stadium bitmap backdrop을 적용해 프리미엄 기록실 질감을 강화했습니다.
- 2026 기록 overview bootstrap과 backend snapshot을 최신 기록 기준으로 다시 갱신했습니다.

## 0.0.59+59 - Records Premium And Push Receipt

- 기록 탭을 headline 리더, 지표 spotlight, 탭형 TOP3 리더보드 table 중심으로 더 조밀하게 다듬었습니다.
- 2026 기록 overview bootstrap과 snapshot을 최신 기록 기준으로 갱신했습니다.
- 온보딩 시작 버튼을 레퍼런스 톤의 red gradient CTA로 정리했습니다.
- 알림함이 깨진 저장 데이터를 만나도 빈 상태로 복구되도록 안정화했습니다.
- 운영 push receipt 확인용 `scripts/push-test-notification.sh` 경로를 추가했습니다.

## 0.0.58+58 - News Records More Polish

- 뉴스 탭을 `오늘 읽을 순서`, 경기/순위/기록/마이팀 신호 grid, 편집형 브리프 카드 중심으로 재구성했습니다.
- 기록 탭을 `오늘 읽을 기록`, 지표 spotlight rail, 지표별 TOP 3 preview, 팀 기록실 흐름으로 정리했습니다.
- 온보딩, 더보기, 경기 상세/박스스코어/라인업/중계 화면의 팀 로고와 선수 이미지 표시를 더 안정적으로 보강했습니다.
- home brief 기록 레이더에 선수 이미지와 상세 route를 함께 싣고, 쉬는 날 CTA는 일정 화면으로 연결합니다.

## 0.0.57+57 - Home Info Pack Flow

- 홈 하단 정보 흐름을 `순위 -> 인사이트 팩 -> 지금 보면 좋은 정보 -> 최근 흐름` 순서로 재배치해 생성 레퍼런스의 카드뉴스형 흐름에 더 가깝게 정리했습니다.
- `0.0.56` TestFlight 업로드 checkpoint 이후 들어온 홈 인사이트 팩 재정렬까지 포함한 최신 빌드입니다.

## 0.0.56+56 - Home Brief Ordering

- 홈 `오늘의 KBO 관전 포인트` 점수 strip을 팀명/스코어/B-S-O/루상 표시 중심으로 더 조밀하게 정리했습니다.
- 미니 카드가 선수 활약, 팀 흐름, 기록 레이더, 선발/투수 체크 순서로 먼저 보이도록 정리했습니다.
- 0.0.55의 홈 인사이트 대시보드, 뉴스 탭, 경기 상세/박스스코어 UI, backend push worker 기준을 새 TestFlight build number로 다시 올렸습니다.
- Apple processing, Git tag, GitHub Release, backend deploy, topic 재등록 기준을 0.0.56으로 다시 맞춘 checkpoint입니다.

## 0.0.55+55 - Home Reference Dashboard

- 홈 하단 `오늘의 KBO 관전 포인트`와 `지금 보면 좋은 정보`를 레퍼런스형 인사이트 카드와 2열 quick info 배치로 정리했습니다.
- 홈 최근 흐름과 순위 snapshot 행을 누르면 팀 기록 화면으로 이어지도록 보강하고, 선택 haptic feedback을 추가했습니다.
- 0.0.54 업로드 이후 들어온 홈 상호작용/source sync까지 포함한 최신 TestFlight 빌드입니다.

## 0.0.54+54 - Home Reference Dashboard

- 홈 첫 화면을 `마이팀 브리프 → 오늘 경기 → 최근 흐름 → 순위` 흐름으로 재배치해 앱을 열자마자 오늘 야구 상황을 더 빨리 훑어볼 수 있습니다.
- 마이팀 브리프는 KBO 브랜드 마크, 팀 로고, 최근 5경기 결과 버블, 승률/게임차, 일정/팀 기록 버튼 중심으로 더 조밀하게 정리했습니다.
- 일부 팀 로고는 reference 전용 bundled logo asset을 사용해 홈 첫 화면에서 더 선명하게 보이도록 했습니다.
- 오늘 경기와 순위 snapshot은 별도 이미지 레일이 아니라 팀 로고, 경기 행, compact 순위표 안에 비주얼과 데이터를 통합해 보여줍니다.
- 하단 탭을 `홈 / 경기 / 기록 / 뉴스 / 더보기` 레퍼런스형 라벨과 아이콘으로 다듬었습니다.
- 뉴스 탭은 순위 화면을 임시 재사용하지 않고, 오늘 경기/순위/기록 흐름을 홈 aggregate 기반 브리프 카드로 보여줍니다.
- 일정, 순위, 더보기 알림 영역의 정상 화면 보조 이미지 rail을 덜어내 정보 밀도를 높였습니다.
- live 경기 badge는 `7회말` 같은 실제 경기 상태를 더 선명하게 보여줍니다.
- backend `/home` 응답에 홈 전용 순위 preview를 추가해 홈 화면이 별도 순위 호출 없이 필요한 정보를 받을 수 있게 했습니다.
- 일정 캘린더 모드 스크롤, 기록 탭 정보 밀도, 공통 화면 모션, 경기 상세 scorebug 안정성을 함께 보강했습니다.

## 0.0.53+53 - Home Reference Dashboard Checkpoint

- 홈 참조 대시보드 release checkpoint입니다. 업로드 전 일정/기록/모션 UX와 경기 상세 scorebug source sync가 추가되어 0.0.54로 대체했습니다.

## 0.0.52+52 - Home Reference Dashboard Checkpoint

- 홈 참조 대시보드 TestFlight upload checkpoint입니다. 업로드 중 reference team logo asset source sync가 추가되어 0.0.53으로 대체했습니다.

## 0.0.51+51 - Home Reference Dashboard Checkpoint

- 홈 참조 대시보드 TestFlight upload checkpoint입니다. 업로드 중 홈 헤더 액션 icon size source sync가 추가되어 0.0.52로 대체했습니다.

## 0.0.50+50 - Home Reference Dashboard Checkpoint

- 홈 참조 대시보드 TestFlight upload/backend deploy checkpoint입니다. 업로드와 backend deploy 뒤 홈 헤더 밀도, 최근 흐름 streak 표시, reference API metrics sink를 다시 맞추기 위해 0.0.51로 대체했습니다.

## 0.0.49+49 - Home Reference Dashboard Checkpoint

- 홈 참조 대시보드 TestFlight upload checkpoint입니다. 업로드 뒤 패치노트와 하단 `뉴스` 탭 source sync를 다시 맞추기 위해 0.0.50으로 대체했습니다.

## 0.0.48+48 - Home Reference Dashboard Checkpoint

- 홈 참조 대시보드 TestFlight upload checkpoint입니다. 업로드 직후 source sync를 다시 맞추기 위해 0.0.49로 대체했습니다.

## 0.0.47+47 - Home Reference Dashboard Checkpoint

- 홈 참조 대시보드 TestFlight upload checkpoint입니다. 하단 탭 label/route 정합성 수정이 추가되어 0.0.48로 대체했습니다.

## 0.0.46+46 - Home Reference Dashboard Checkpoint

- 홈 첫 화면을 `마이팀 브리프 → 오늘 경기 → 최근 흐름 → 순위` 흐름으로 재배치해 앱을 열자마자 오늘 야구 상황을 더 빨리 훑어볼 수 있습니다.
- 마이팀 브리프는 팀 로고, 최근 5경기 결과 버블, 승률/게임차, 일정/팀 기록 버튼 중심으로 더 조밀하게 정리했습니다.
- 오늘 경기와 순위 snapshot은 별도 이미지 레일이 아니라 팀 로고, 경기 행, compact 순위표 안에 비주얼과 데이터를 통합해 보여줍니다.
- backend `/home` 응답에 홈 전용 순위 preview를 추가해 홈 화면이 별도 순위 호출 없이 필요한 정보를 받을 수 있게 했습니다.

## 0.0.45+45 - TestFlight Reupload Checkpoint

- 앱 동작 변경 없이 0.0.44의 WebP-only 비주얼 자산 구성을 새 TestFlight build number로 다시 올렸습니다.
- Apple TestFlight 처리 빌드와 Git tag/GitHub Release 기준을 한 번 더 맞춘 배포 checkpoint입니다.

## 0.0.44+44 - WebP Visual Asset Cutover

- 대표 artwork 이미지까지 캐주얼 WebP 리소스로 전환해 화면별 비주얼 톤을 한 계열로 맞췄습니다.
- release asset manifest에서 기존 PNG 대표 이미지를 빼고 175개 캐주얼 WebP만 명시해 앱 자산 구성을 더 작고 예측 가능하게 정리했습니다.
- 0.0.43 TestFlight 처리 빌드는 최신 WebP-only 소스 기준 0.0.44로 다시 올려 Git 태그와 배포 기준을 맞췄습니다.

## 0.0.43+43 - Visual Resource Rail

- 홈, 경기 상세, 일정, 순위, 기록실, 알림 설정, 온보딩에 공통 야구 비주얼 rail을 추가해 화면별 분위기와 탐색 맥락을 더 풍부하게 보여줍니다.
- release 빌드가 참조하는 `casual_*.webp` 리소스를 명시 자산으로 포함해 TestFlight 앱과 저장소 빌드 구성을 맞췄습니다.
- 0.0.42 TestFlight 처리 빌드는 최신 소스 기준 0.0.43으로 다시 올려 Git 태그와 배포 기준을 맞췄습니다.

## 0.0.42+42 - Integrated Visual Headers

- 일정 화면의 야구 이미지를 월 헤더 카드 안으로 통합해 월 이동 버튼과 화면 분위기가 더 자연스럽게 이어집니다.
- 순위 화면의 `1위 경쟁`, `마이팀`, `연승` 요약에 순위 레이스 이미지를 은은한 배경으로 넣어 표 위 정보를 더 밀도 있게 정리했습니다.
- API 진단, 패치노트, 라인업 탭의 로딩/완료 상태와 반복 카드 등장 모션을 더 부드럽게 다듬었습니다.
- 홈/일정/순위 비주얼 통합 방향을 문서 mockup으로 남겨 다음 화면 polish 기준을 명확히 했습니다.

## 0.0.41+41 - Motion Polish

- 하단 탭을 이동할 때 실제 탭 순서에 맞춰 좌우 방향이 자연스럽게 이어지도록 조정했습니다.
- 일정 화면에서 월 이동과 오늘 버튼 이동이 더 부드러운 ease-in-out 슬라이드로 움직이도록 보강했습니다.
- 홈/일정/순위의 재시도 상태와 생성 비주얼 노출 기준을 문서와 앱 패치노트에 맞춰 정리했습니다.

## 0.0.40+40 - Game Day Experience & Brief Push Polish

- 장시간 백그라운드 후 홈 스코어보드 refresh가 실패해도 마지막 정상 홈 화면을 유지합니다.
- 문자중계 foreground 갱신과 backend live sync 기본 주기를 5초로 낮춰 중계 반영 체감을 개선했습니다.
- 홈 경기 없음 상태에 일정/기록실 바로가기를 추가하고, 하단 탭 전환과 iOS 스와이프 뒤로가기 흐름을 더 부드럽게 정리했습니다.
- 순위 시즌 선택, 순위/경기 상세/문자중계 생성 비주얼, Pretendard 폰트 적용으로 화면 탐색과 한글 가독성을 보강했습니다.
- 알림 설정에 야구 브리프를 추가하고, backend가 팀별 경기일/비경기일/기록실 확인 메시지를 스마트하게 보낼 수 있도록 확장했습니다.

## 0.0.39+39 - Push Backfill Stop

- TestFlight/release 앱을 다시 열거나 포커스했을 때 지난 경기 이벤트 알림이 몰아서 뜨지 않도록 홈 화면 로컬 알림 backfill을 막았습니다.
- 앱 밖 알림은 backend FCM/APNs 경로가 담당하도록 정리하고, 앱 내부 로컬 경기 이벤트 알림은 local 개발 모드에서만 처리합니다.

## 0.0.38+38 - Push Moment Routing Polish

- 경기 시작 10분 전 `경기 곧 시작` 알림을 누르면 경기 상세 문자중계 탭으로 이동하도록 보강했습니다.
- 문자중계 안타 알림과 경기 시작 임박 topic 계약을 테스트로 고정해, 다음 배포에서 빠지지 않도록 정리했습니다.

## 0.0.37+37 - Background Push Registration Fix

- 마이팀이 선택된 release 앱은 최초 1회 알림 권한 요청과 FCM 등록 동기화를 자동으로 실행해 앱 종료/백그라운드 push 수신 준비를 보강했습니다.
- 홈에서 자동으로 따라가는 마이팀 live 경기 상태를 backend push registry의 `followedGameIds`에 함께 반영합니다.
- 진행 중 경기의 홈 scoreboard, 경기 상세, Live Activity 원격 갱신 주기를 8초 기준으로 맞췄습니다.
- iOS Live Activity / Dynamic Island와 홈 카드의 팀 로고-스코어 중심 표현을 맞추고, 앱 전역 다크 톤과 사용자 화면 문구를 더 절제된 형태로 정리했습니다.

## 0.0.36+36 - TestFlight Push Initialization Fix

- TestFlight iOS 앱에 Firebase 설정 파일이 포함되도록 보정해 푸시 초기화가 실패하던 경로를 막았습니다.
- API 진단 화면의 push 카드가 release 환경에서도 초기화 실패 사유를 함께 보여주도록 보강했습니다.
- 운영 backend에 저장된 push registry 토큰을 현재 `at_bat` topic 계약으로 다시 구독시키는 재등록 경로를 추가했습니다.

## 0.0.35+35 - Push Moments & Boxscore Guard

- 새 타자가 타석에 들어설 때 문자중계 탭으로 연결되는 `타석` 바로 알림을 추가했습니다.
- 앱이 백그라운드나 종료 상태여도 backend scheduler가 relay 변화에서 홈런을 감지해 홈런 푸시를 보낼 수 있도록 보강했습니다.
- 진행 중 경기 박스스코어가 공식 기록 없이 선발/현재 투수 placeholder만 받은 경우 0값 기록 카드 대신 업데이트 전 상태를 표시합니다.
- Live Activity / Dynamic Island update payload가 현재 타자, 투수, B/S/O, 투구 수 정보를 함께 받을 수 있도록 backend sync payload를 보강했습니다.

## 0.0.34+34 - Relay & Detail Refresh Polish

- 진행 중 경기의 문자중계 탭이 열려 있을 때 자동 갱신 주기를 15초로 줄여 중계 반영 체감을 개선했습니다.
- 문자중계 현재 타석/주요 장면 카드가 선수 프로필 이미지와 현재 타석 이미지 URL을 더 안정적으로 사용합니다.
- 홈 마이팀 경기 카드의 진행 중 상태 배지는 `LIVE`로 더 간결하게 표시합니다.
- 장시간 화면 꺼짐 뒤 경기 상세 refresh가 실패해도 기존 경기 상세 화면을 유지합니다.
- 라인업 알림/라인업 공개 상태와 문자중계 회차 버튼 라벨을 더 안정적으로 보정했습니다.

## 0.0.33+33 - TestFlight Push Backend Handoff

- TestFlight 빌드가 배포된 AWS push backend에 토큰 등록을 보낼 수 있도록 release API URL을 맞췄습니다.
- 마이팀 경기 시작 알림과 Live Activity / Dynamic Island 자동 시작 검증을 위해 임시 HTTP smoke backend 연결을 허용했습니다.

## 0.0.32+32 - Push & Dynamic Island Autostart Fix

- 마이팀 live 경기가 시작되면 `따라가기`를 먼저 누르지 않아도 Live Activity / Dynamic Island 대상이 자동으로 잡히도록 보정했습니다.
- 마이팀 경기 시작 알림을 기본 `바로 알림`으로 받고, 서버도 앱의 알림 전달 방식에 맞춰 즉시 알림 topic만 등록합니다.
- 홈과 경기 상세에서 live 경기 중계 진입이 문자중계에 더 바로 닿도록 흐름을 다듬었습니다.
- 문자중계 현재 타석과 주요 장면 선수 표기가 등번호 대신 라인업 기준 이름/타순/포지션을 우선 사용합니다.

## 0.0.31+31 - TestFlight Background Task Fix

- TestFlight에서 위젯 백그라운드 갱신 task 등록 이후 앱이 시작 직후 종료될 수 있던 경로를 막았습니다.
- TestFlight direct 라인업 탭이 박스스코어 원천 실패에 막히지 않도록 `GetLineUpAnalysis` 원천을 우선 사용합니다.
- 홈에서 live 마이팀 경기를 자동으로 따라가는 상태로 표시하고, `따라가기` 버튼은 같은 자리에서 `따라가는 중` 상태로 바뀝니다.
- 진행 중 경기에서는 일정 카드와 경기 상세의 예매 정보를 숨겨 경기 전 정보와 live 정보를 분리했습니다.

## 0.0.30+30 - TestFlight Startup Crash Fix

- TestFlight 첫 실행에서 마이팀을 아직 선택하지 않은 상태여도 앱이 종료되지 않도록 위젯 저장값을 보정했습니다.
- iOS 위젯 백그라운드 갱신과 push background 처리를 위한 release 설정을 보강했습니다.

## 0.0.29+29 - Schedule Status & Direct Relay Polish

- 일정 화면에서 다음 달/이전 달로 이동한 뒤 하단 `일정` 탭을 다시 눌러도 선택한 월이 유지됩니다.
- 일정 데이터 로딩이 실패해도 캘린더와 월 이동 컨트롤은 유지되어 다른 달로 이동할 수 있습니다.
- KBO 취소 사유가 `우천취소`로 내려오면 일정, 홈, 상세, 위젯 상태 문구에 우천취소 라벨을 표시합니다.
- 문자중계의 포일 이벤트를 일반 플레이가 아니라 포일 이벤트로 표시합니다.
- 롯데 자이언츠 팀 로고가 흰 사각 배경 없이 투명 배경으로 표시되도록 이미지 경로를 보정했습니다.
- direct-primary 문자중계와 박스스코어/라인업에서 현재 타석 선수 이미지와 한글 선수명 매칭이 더 안정적으로 동작합니다.
- direct-primary 문자중계 요약 fallback이 예정 경기에서 실제 중계처럼 보이는 skeleton을 만들지 않도록 막았습니다.

## 0.0.28+28 - Current Boxscore & Records Guard

- LIVE/당일 박스스코어가 비어 있을 때 전날 같은 팀 경기의 선수 기록을 빌려오지 않습니다.
- 현재 경기 박스스코어가 공식 업데이트 전이면 `공식 박스스코어 업데이트 전입니다` 상태로 명확히 표시합니다.
- 과거 경기의 adjacent canonical id 보정은 유지하되 응답 `gameId`와 실제 원천 `sourceGameId`를 분리했습니다.
- 기록실 리더보드는 서버에서 rank 기준으로 정렬한 뒤 내려주어, fresh load에서도 1위부터 안정적으로 표시됩니다.

## 0.0.27+27 - Live Score Freshness Guard

- LIVE 홈/위젯 요약 스코어보드에서 KBO main list의 실제 득점을 schedule/detail fallback의 0점보다 우선합니다.
- 진행 중 경기가 실제로 득점 중인데도 fallback 0:0 때문에 홈이나 위젯에서 0:0으로 남을 수 있던 경로를 막았습니다.
- 같은 케이스가 다시 생기지 않도록 backend 회귀 테스트를 추가했습니다.

## 0.0.26+26 - Home First Paint Cache Sharing

- 홈 화면은 스코어보드가 먼저 그려진 뒤에만 마이팀 브리프와 KBO 브리프용 `/home` aggregate를 구독합니다.
- backend `/scoreboard/home`, `/home`, 일정, 순위, 기록실, 경기 상세 계열이 공용 runtime service를 공유해 같은 TTL 캐시를 재사용합니다.
- 홈 자동 새로고침 타이머가 관계없는 rebuild마다 다시 시작되지 않도록 scoreboard signature 기준으로 안정화했습니다.
- 작은 홈 로딩 카드가 일부 모바일/테스트 뷰포트에서 overflow 될 수 있던 간격을 보정했습니다.

## 0.0.25+25 - Missing Team Totals Guard

- 스코어 탭과 문자중계 요약에서 안타/실책/사사구 원천값이 없으면 `0` 대신 `-`로 표시합니다.
- 홈 마이팀 경기 카드도 양 팀 H/E/B가 확인되지 않은 경우 해당 요약 행을 숨깁니다.
- KBO 브리프의 `안타 공방` 문구는 실제 안타 통계가 내려온 경기만 후보로 사용합니다.
- 결측 team totals가 `0안타`, `0실책`, `0볼넷`처럼 확정 기록으로 보일 수 있던 경로를 막았습니다.

## 0.0.24+24 - Lightweight Scoreboard Surfaces

- 홈 스코어보드와 위젯/Live Activity용 compact 스코어보드는 schedule + main list 기반 요약만 사용합니다.
- 경기별 상세 스코어보드 크롤링은 full 스코어보드와 경기 상세 진입 때만 수행해 첫 로딩 fan-out을 줄였습니다.
- full 스코어보드는 기존처럼 상세 스코어보드와 View1 보강을 유지해 이닝별 점수, H/E/B, 현재 이닝 품질을 보존합니다.
- 현재 날짜 홈 스코어보드는 원천 실패 때 fresh snapshot으로 정상 응답처럼 대체하지 않습니다.

## 0.0.23+23 - Current Team Records Failure Guard

- 현재 시즌 팀 선수, 팀 스탯, 선수 상세는 원천 조회 실패 때 backend/app/device snapshot으로 정상 데이터처럼 대체하지 않습니다.
- backend도 현재 시즌 팀 선수, 팀 스탯, 선수 상세 crawler 실패 시 fresh snapshot을 반환하지 않습니다.
- 과거 시즌 팀 선수, 팀 스탯, 선수 상세는 기존처럼 저장 snapshot을 우선 사용해 빠르게 열립니다.
- 현재 시즌 기록실 팀/선수 화면이 원천 실패인데도 저장 데이터 때문에 최신처럼 보일 수 있던 경로를 막았습니다.
- GitHub Actions 앱 빌드는 backend 테스트를 먼저 통과해야 Android/Web/iOS artifact 빌드로 넘어갑니다.

## 0.0.22+22 - Current Data Cache Guard

- 현재 날짜 스코어보드, 홈, 경기 상세, 문자중계, 박스스코어, 라인업, 현재 월 일정, 현재 시즌 순위/기록실/팀 기록은 API 실패 시 로컬 API 캐시로 정상처럼 대체하지 않습니다.
- backend 현재 스코어보드, 일정, 순위, 기록실 요약, 리더보드도 원천 조회 실패 시 snapshot으로 정상처럼 대체하지 않습니다.
- 홈 첫 로딩에서도 오늘 스코어보드 로컬 캐시를 먼저 보여주지 않고 최신 API 응답 또는 오류 상태를 기다립니다.
- 과거 날짜/시즌/월 조회는 기존처럼 저장된 캐시와 snapshot을 우선 활용해 빠르게 열립니다.
- 2026-05-20 취소 경기와 현재 순위/기록실 snapshot 저장 시각을 최신 수집본 기준으로 갱신했습니다.
- 서버/API가 죽었을 때 남은 캐시 때문에 현재 경기나 현재 기록이 최신처럼 보일 수 있던 경로를 막았습니다.

## 0.0.21+21 - Records Cache & Error Surface

- 기록실 API 캐시는 리더보드가 1위부터 시작하는지 검증한 뒤에만 재사용하거나 저장합니다.
- 웹/앱에 남은 구형 기록실 캐시가 2013 타율처럼 1위가 빠진 순위를 계속 보여줄 수 있던 경로를 막았습니다.
- 2013 타율 리더보드 fallback이 이병규 1위부터 시작하도록 backend snapshot을 보강했습니다.
- 기록실 리그 요약 실패가 빈 공간으로 숨겨지지 않고 오류 카드와 다시 시도 버튼으로 표시됩니다.
- 팀 기록실 오류 상태에도 사용자용 실패 문구가 함께 표시됩니다.
- 앱 전역 자동 retry를 끄고 API 실패가 화면 상태와 Dev Console에 더 예측 가능하게 드러나도록 했습니다.

## 0.0.20+20 - Home Aggregate Failure Guard

- 홈 aggregate가 현재/미래 날짜에서 일정, 순위, 기록실 요약 실패를 빈 섹션처럼 숨기지 않도록 바꿨습니다.
- 현재 데이터 일부가 실패했는데도 `오늘 경기 없음`, 빈 순위, 빈 기록 카드처럼 정상으로 보일 수 있던 경로를 막았습니다.
- 과거 날짜 홈 조회만 기존 partial fallback을 유지합니다.
- 기록실 overview snapshot을 다시 만들 때 featured 카드가 시즌 리더 기준으로 생성되도록 crawler와 2011 snapshot을 맞췄습니다.
- 기록실 device snapshot 버전을 `v3`로 올려 구형/불완전 캐시가 1위 누락 리더보드를 계속 보여주지 않도록 했습니다.

## 0.0.19+19 - Release Web Command Guard

- 현재/진행 예정 경기의 박스스코어와 라인업은 과거 snapshot을 실패 fallback으로 쓰지 않도록 막았습니다.
- LIVE 경기 문자중계가 실패했을 때 요약/과거 snapshot으로 정상처럼 보이는 경로를 차단했습니다.
- 팀 기록 API는 선수 목록이나 팀 스탯 중 한쪽 실패를 빈 데이터처럼 숨기지 않고 실패로 처리합니다.
- `./scripts/codex-run.sh web` 기본 실행이 release API health gate를 통과한 static web release 경로로 동작하도록 바꿨습니다.
- Chrome debug 세션은 `./scripts/codex-run.sh web-dev`와 `scripts/codex-run-web-dev.sh`로 분리했습니다.
- 현재/라이브 데이터 실패 masking guard와 웹 기본 실행 기준을 문서와 실행 경로에 맞췄습니다.

## 0.0.18+18 - Historical Leaderboard Snapshots

- 2011 ERA와 2013 홈런 리더보드 backend snapshot을 추가했습니다.
- 원천 조회가 실패해도 `윤석민 2.45`, `박병호 37`처럼 은퇴 선수가 포함된 과거 대표 리더보드가 fallback으로 복구됩니다.
- snapshot 상위 리더가 다시 빠지지 않도록 backend 회귀 테스트를 추가했습니다.
- 웹 wrapper를 release API health gate 경로로 맞추고 Android/Web release 전용 wrapper를 추가했습니다.

## 0.0.17+17 - Direct Routing Guard

- direct KBO 경로는 local native 빌드에서 `PREFER_DIRECT_SCRAPE=true`를 명시하고 `API_BASE_URL` override가 없을 때만 사용합니다.
- 웹, release, API override 빌드는 항상 backend API 경로를 우선하도록 앱 provider와 widget background 동기화 경로를 맞췄습니다.
- provider routing 테스트를 추가해 임시 direct-primary 검증 경로가 일반 앱 실행으로 새지 않도록 했습니다.
- Android/Web release 실행도 local backend 없이 release API health gate를 통과한 URL만 사용하도록 정리했습니다.
- 일반 API-backed 앱 모드에서는 현재 시즌 순위/기록실 요약/리더보드 API 실패를 앱 번들 데이터로 대체하지 않습니다.
- 기록실 요약 device snapshot은 AVG/HR/OPS/ERA가 모두 있는 완성본만 저장하고 재사용합니다.

## 0.0.16+16 - Backend Snapshot Freshness

- backend 현재 날짜 스코어보드와 현재 시즌/월 일정, 순위, 기록실 요약, 리더보드는 원천 조회 실패 때도 6시간 이내 저장 snapshot만 fallback으로 사용합니다.
- 현재 날짜 스코어보드는 fresh + 경기 종료/취소/중단 snapshot일 때만 fallback으로 사용해 진행 중 경기의 오래된 snapshot 재노출을 막았습니다.
- 과거 날짜/시즌/월 데이터는 기존처럼 저장된 snapshot을 우선 사용해 히스토리 화면이 빠르게 열리도록 유지했습니다.
- 앱 기록실 선수/리더 데이터의 은퇴 선수 플래그를 API, local asset, device snapshot 사이에서 보존하도록 했습니다.
- 앱 API cache도 TTL이 지난 데이터는 원격 실패 fallback으로 다시 보여주지 않도록 제한했습니다.
- 현재 시즌 기록실 요약 번들은 생성 시각이 오래됐으면 fallback으로 쓰지 않도록 제한했습니다.
- 홈 스코어보드 로컬 cache도 저장 시각을 함께 남기고, 진행 중 60초 / 경기 전 5분 / 종료 6시간 기준으로 오래된 화면 선표시를 막았습니다.
- 현재 시즌 팀 선수 목록은 오래된 cache를 먼저 보여주지 않고 최신 API 응답을 먼저 시도합니다.

## 0.0.15+15 - Standings Bootstrap Cleanup

- 순위 번들도 요청한 시즌의 검증된 snapshot만 사용하도록 정리했습니다.
- 현재 시즌 순위 번들은 6시간 이내 생성본일 때만 fallback으로 쓰고, 오래된 순위는 빈 상태로 처리합니다.
- 2001~2025 시즌에 2026 초반 순위가 반복되어 보일 수 있던 번들 데이터를 제거했습니다.
- 웹 빌드가 `APP_ENV=local`이어도 명시적 override 없이는 `localhost` 대신 운영 API를 사용하도록 해 웹 프리뷰의 API 실패 가능성을 줄였습니다.
- 2009~2013, 2020 기록실 요약 backend snapshot을 실제 시즌 리더 데이터로 보강했습니다.
- KT 2026 팀 선수/팀 스탯 번들 snapshot을 최신 저장 snapshot 기준으로 갱신했습니다.

## 0.0.14+14 - Device Snapshot Freshness

- 앱이 기기에 저장하는 기록실 snapshot에 저장 시각을 함께 남기도록 바꿨습니다.
- 현재 시즌 팀 선수, 팀 스탯, 팀 기록, 리더보드 기기 snapshot은 6시간 이내 저장본만 fallback으로 사용합니다.
- 현재 시즌 번들 팀 선수/팀 스탯도 저장 시각이 오래됐으면 빈 상태로 처리해 오래된 2026 기록이 다시 보이지 않게 했습니다.
- `savedAt`이 없는 구형 기기 snapshot은 현재 시즌 기록실에서 무시합니다.

## 0.0.13+13 - Records Bootstrap & Emblem Fix

- 구단 로고를 KBO 고정 엠블럼 이미지로 바꿔 온보딩, 홈, 일정, 상세, 순위에서 더 선명하고 안정적으로 보이도록 했습니다.
- 기록실 요약 번들은 요청한 시즌의 snapshot만 사용하도록 고정했습니다. 이제 다른 시즌 리더 데이터를 빌려 보여주지 않습니다.
- 현재 시즌 팀 선수/팀 스탯은 오래된 저장 snapshot을 먼저 보여주지 않고, 원천 조회 실패 때도 6시간 이내 snapshot만 fallback으로 사용합니다.
- 번들 기록실 요약에 남아 있던 오래된 허경민/함덕주 등 잘못된 리더 데이터를 제거하고 현재 2026 snapshot 기준으로 정리했습니다.
- backend 2026 홈런 리더보드 snapshot을 추가해 원천 조회가 느릴 때도 홈런왕 순위 fallback이 더 안정적으로 동작합니다.

## 0.0.12+12 - Records Image & Motion Polish

- 과거 시즌 기록실 선수 사진이 없는 시즌 폴더를 바라보지 않도록, 2022년 이전 시즌은 확인 가능한 선수 이미지 폴더로 보정했습니다.
- 기록실 첫 화면의 미지원 WAR 카드를 wRC+ 리더보드로 바꿔 실제 제공 가능한 지표만 보이게 했습니다.
- 홈의 `홈런왕` quick item이 이름 첫 글자 대신 선수 사진과 선수 상세 경로를 사용하도록 수정했습니다.
- 홈에 `KBO 브리프`를 추가해 마이팀과 별개로 오늘 리그 전체에서 볼만한 경기, 기록, 순위 흐름을 보여줍니다.
- 경기 전 경기의 홈/일정 표기는 점수 대신 `vs` 중심으로 보여, 아직 시작하지 않은 경기가 0:0처럼 보이지 않도록 했습니다.
- 경기 카드, 일정 카드, 기록실 카드/필터, 하단 탭, 온보딩 구단 카드, 경기 상세 주요 탭에 짧은 press 피드백과 점수 변경 모션을 적용했습니다.
- 홈 이벤트 알림 처리, iOS widget 초기화, 닫힌 Dev Console 로그 갱신을 중복 실행하지 않도록 줄여 실기기 발열 후보를 낮췄습니다.
- 종료/과거 경기 상세는 완성된 박스스코어, 라인업, 문자중계 snapshot을 먼저 사용해 화면 진입 시 원천 재조회 부담을 줄였습니다.

## 0.0.11+11 - Lineup Fan-out & Patch Notes

- 라인업 탭 첫 진입이 더 가벼워졌습니다. 이제 라인업 화면은 라인업 데이터와 양 팀 선수 이미지 정보만 먼저 불러옵니다.
- 라인업 선발 비교에서 실제 기록이 없을 때 `0.00` 같은 가짜 수치를 보여주지 않고 `-` 또는 `선발 발표`로 표시합니다.
- 홈 스코어보드 자동 갱신 주기를 경기 중 30초, 경기 전 5분으로 조정하고, 종료된 경기만 있을 때는 반복 갱신을 멈춥니다.
- 홈 스코어보드 캐시가 같은 내용이면 다시 저장하거나 화면을 불필요하게 갱신하지 않도록 정리했습니다.
- 웹에서는 기록실이나 일정으로 돌아왔을 때 홈 위젯/Live Activity용 전역 갱신이 끼어들지 않도록 정리했습니다.
- 릴리즈 표기에서 preview 접미사를 제거하고, 앱 내 패치노트를 `0.0.1`부터 현재 버전까지 숫자 릴리즈 기준으로 다시 정리했습니다.

## 0.0.10+10 - Historical Records Recovery

- 임시 direct-primary iPhone 빌드에서 2025, 2024 같은 과거 시즌 기록실이 비어 보이던 문제를 고쳤습니다.
- KBO 기록 페이지의 세션과 form state를 유지해 과거 시즌 리더보드, 팀 스탯, 팀별 야수/투수 기록을 더 안정적으로 가져옵니다.
- 앱 시작 단계에서 원격 API prefetch가 첫 화면 진입을 다시 막을 수 있던 죽은 코드를 제거했습니다.
- backend 기록실 crawler도 같은 방식으로 보정해 이후 snapshot 생성이 빈 과거 시즌 데이터로 덮이지 않도록 했습니다.

## 0.0.9+9 - Home Request Budget

- 홈 화면이 `/home` aggregate 로딩 중 별도로 기록실 overview를 다시 부르던 보조 호출을 제거했습니다.
- 홈 첫 화면은 스코어보드 먼저, 이후 마이팀/보조 정보는 지연 로딩하는 흐름으로 정리했습니다.
- API-first와 임시 direct-primary 검증 모드의 역할을 문서와 실행 경로 기준으로 다시 맞췄습니다.
- 기록실 snapshot이 없는 시즌에서 다른 시즌 데이터를 빌려 보여주지 않도록 한 정책을 패치노트와 릴리즈 문서에도 맞췄습니다.

## 0.0.8+8 - Release Routine & Snapshot Baseline

- 설정 화면에서 실제 앱 버전과 빌드 번호를 확인할 수 있습니다.
- 설정의 앱 정보에서 버전별 패치노트를 바로 열어볼 수 있습니다.
- 기록실 과거 시즌 팀 선수는 시즌별 snapshot을 우선 사용하고, 불완전한 팀 스탯은 화면에 섞이지 않도록 안정화했습니다.
- iPhone local release 검증 경로를 `APP_ENV=local + PREFER_DIRECT_SCRAPE=true` 임시 direct-primary 모드로 분리했습니다.
- 릴리즈마다 GitHub 릴리즈 노트와 앱 내 패치노트가 함께 갱신되도록 버전 루틴을 정리했습니다.

## 0.0.7+7 - Final 0.0.x Rolling Snapshot

- 설정의 알림 전달 방식을 `바로 알림`, `묶음 요약`, `따라가기만`, `끄기`로 정리했습니다.
- 경기 상세에서 라이브 경기 `경기 따라가기`를 사용자가 직접 시작하도록 변경했습니다.
- iOS 위젯과 Live Activity에서 점수, 팀 로고, 현재 타석 정보를 더 안정적으로 표시하도록 개선했습니다.
- 초기 rolling snapshot의 마지막 기준입니다. 이후 릴리즈는 같은 숫자 정책을 유지해 `0.0.8`부터 이어갑니다.

## 0.0.6+6 - Compact Scoreboard & Release Guard

- compact scoreboard, 위젯/Live Activity 데이터, release API health gate 방향을 정리했습니다.
- 홈과 경기 상세의 앱 밖 표면을 API-first 기준으로 좁히기 시작했습니다.
- release 빌드 전 production API DNS/TLS/핵심 endpoint를 확인하는 guard를 도입했습니다.

## 0.0.5+5 - Distribution Prep

- Firebase, Android/iOS 배포 준비, signing 문서, tester 공유 흐름을 정리했습니다.
- 알림과 경기 따라가기 표면을 외부 테스트 준비 기준으로 확장했습니다.

## 0.0.4+4 - Records & Game Detail Baseline

- 기록실, 선수 상세, 팀 기록, 경기 상세의 기본 구조를 앱 주요 화면으로 올렸습니다.
- 일정, 순위, 예매 정보, 하이라이트 연결을 MVP 화면 흐름에 포함했습니다.

## 0.0.3+3 - My Team & Live Surface Iteration

- 마이팀 중심 UX, Dynamic Island/Live Activity 방향, 일정/상세 polish를 빠르게 검증했습니다.
- 현재 진행 중이거나 오늘 예정된 마이팀 경기를 앱 밖 표면의 우선 후보로 다루는 방향을 세웠습니다.

## 0.0.2+2 - Workflow & Widget Follow-up

- 초기 실행 스크립트, 문서, 위젯/Live Activity 후속 방향을 보강했습니다.
- 반복 작업을 `.claude/skills/`로 빼기 시작하고 AGENTS/CLAUDE 문서 기준을 맞췄습니다.

## 0.0.1+1 - Initial Prototype

- Flutter 앱 골격, FastAPI backend 골격, MVP 화면 구조, 프로젝트 문서의 첫 릴리즈입니다.
