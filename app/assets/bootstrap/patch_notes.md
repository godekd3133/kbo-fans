# 패치노트

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
