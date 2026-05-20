# 패치노트

## 0.1.0+4 - Preview 4

- 라인업 탭 첫 진입이 더 가벼워졌습니다. 이제 라인업 화면은 라인업 데이터와 양 팀 선수 이미지 정보만 먼저 불러옵니다.
- 라인업 선발 비교에서 실제 기록이 없을 때 `0.00` 같은 가짜 수치를 보여주지 않고 `-` 또는 `선발 발표`로 표시합니다.
- 홈 스코어보드 자동 갱신 주기를 경기 중 30초, 경기 전 5분으로 조정하고, 종료된 경기만 있을 때는 반복 갱신을 멈춥니다.
- 홈 스코어보드 캐시가 같은 내용이면 다시 저장하거나 화면을 불필요하게 갱신하지 않도록 정리했습니다.
- 웹에서는 기록실이나 일정으로 돌아왔을 때 홈 위젯/Live Activity용 전역 갱신이 끼어들지 않도록 정리했습니다.

## 0.1.0+3 - Preview 3

- 임시 direct-primary iPhone 빌드에서 2025, 2024 같은 과거 시즌 기록실이 비어 보이던 문제를 고쳤습니다.
- KBO 기록 페이지의 세션과 form state를 유지해 과거 시즌 리더보드, 팀 스탯, 팀별 야수/투수 기록을 더 안정적으로 가져옵니다.
- 앱 시작 단계에서 원격 API prefetch가 첫 화면 진입을 다시 막을 수 있던 죽은 코드를 제거했습니다.
- backend 기록실 crawler도 같은 방식으로 보정해 이후 snapshot 생성이 빈 과거 시즌 데이터로 덮이지 않도록 했습니다.

## 0.1.0+2 - Preview 2

- 홈 화면이 `/home` aggregate 로딩 중 별도로 기록실 overview를 다시 부르던 보조 호출을 제거했습니다.
- 홈 첫 화면은 스코어보드 먼저, 이후 마이팀/보조 정보는 지연 로딩하는 흐름으로 정리했습니다.
- API-first와 임시 direct-primary 검증 모드의 역할을 문서와 실행 경로 기준으로 다시 맞췄습니다.
- 기록실 snapshot이 없는 시즌에서 다른 시즌 데이터를 빌려 보여주지 않도록 한 정책을 패치노트와 릴리즈 문서에도 맞췄습니다.

## 0.1.0+1 - Preview 1

- 설정 화면에서 실제 앱 버전과 빌드 번호를 확인할 수 있습니다.
- 설정의 앱 정보에서 버전별 패치노트를 바로 열어볼 수 있습니다.
- 기록실 과거 시즌 팀 선수는 시즌별 snapshot을 우선 사용하고, 불완전한 팀 스탯은 화면에 섞이지 않도록 안정화했습니다.
- iPhone local release 검증 경로를 `APP_ENV=local + PREFER_DIRECT_SCRAPE=true` 임시 direct-primary 모드로 분리했습니다.
- 릴리즈마다 GitHub 릴리즈 노트와 앱 내 패치노트가 함께 갱신되도록 버전 루틴을 정리했습니다.

## 0.0.5 - Legacy Preview

- 설정의 알림 전달 방식을 `바로 알림`, `묶음 요약`, `따라가기만`, `끄기`로 정리했습니다.
- 경기 상세에서 라이브 경기 `경기 따라가기`를 사용자가 직접 시작하도록 변경했습니다.
- iOS 위젯과 Live Activity에서 점수, 팀 로고, 현재 타석 정보를 더 안정적으로 표시하도록 개선했습니다.
- `0.0.x` rolling preview 라인의 마지막 snapshot이며, 이후 작업은 `0.1.0-preview.N`으로 이동했습니다.

## 0.0.4 - Legacy Stable Checkpoint

- compact scoreboard, 위젯/Live Activity 데이터, release API health gate 방향을 정리했습니다.
- 홈과 경기 상세의 앱 밖 표면을 API-first 기준으로 좁히기 시작했습니다.
- 현재 stable legacy 기준으로 남겨두고, 새 미리보기는 `0.1.0-preview.N`에서 이어갑니다.

## 0.0.3 - Legacy Distribution Prep

- Firebase, Android/iOS 배포 준비, signing 문서, tester 공유 흐름을 정리했습니다.
- 알림과 경기 따라가기 표면을 외부 테스트 준비 기준으로 확장했습니다.

## 0.0.2 - Legacy Records Baseline

- 기록실, 선수 상세, 팀 기록, 경기 상세의 기본 구조를 앱 주요 화면으로 올렸습니다.
- 일정, 순위, 예매 정보, 하이라이트 연결을 MVP 화면 흐름에 포함했습니다.

## 0.0.2-preview - Legacy My Team Preview

- 마이팀 중심 UX, Dynamic Island/Live Activity 방향, 일정/상세 polish를 빠르게 검증한 preview입니다.

## 0.0.1-preview.1 - Legacy Workflow Follow-up

- 초기 실행 스크립트, 문서, 위젯/Live Activity 후속 방향을 보강한 preview입니다.

## 0.0.1-preview - Legacy Initial Prototype

- Flutter 앱 골격, FastAPI backend 골격, MVP 화면 구조, 프로젝트 문서의 첫 preview입니다.
