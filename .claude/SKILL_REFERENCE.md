# KBO Fans Skill Reference

> 최종 수정: 2026-06-12

## Data / Runtime

- 기본 선택: `kbo-runtime-data`
- `kbo-history-snapshot`
  - 히스토리 데이터 snapshot 우선 조회, cache 계층 분리, 앱 cached-first 로딩 작업
- `kbo-runtime-data`
  - 앱 데이터 로딩 경로, backend-backed vs direct KBO mode, 성능/캐시 정책 조정
- `kbo-asmx-direct-integration`
  - 앱 direct KBO ASMX 호출 파라미터, plain text decode, `GetScheduleList` 파싱
- `bootstrap-fallback-data`
  - standings / records overview fallback 스냅샷 생성과 앱 연결
- `kbo-relay-integration`
  - KBO relay 로그인 세션, live text parsing, relay 서비스 작업
- `home-load-performance`
  - 홈 로딩 순서, aggregate payload, 불필요한 외부 호출 제거
- `app-startup-runtime-triage`
  - 앱 시작 흰 화면, local API base URL, Dev Console 로그 노이즈, Firebase local 경고 트리아지

### Runtime 선택 기준
- `kbo-runtime-data`
  - broad default
- `home-load-performance`
  - 홈 첫 진입 / aggregate payload / deferred sections
- `app-startup-runtime-triage`
  - startup white screen / noisy logs / plugin bootstrap
- `kbo-asmx-direct-integration`
  - native local/offline direct KBO path only
- `bootstrap-fallback-data`
  - 앱 번들 fallback snapshot 생성
- `kbo-history-snapshot`
  - snapshot persistence/read strategy

## UI / Client

- `game-detail-tab-polish`
  - 경기 상세 탭 UX와 모바일 카드형 정보 밀도 조정
- `ios-live-activity-widget`
  - iOS WidgetKit / Live Activity / Dynamic Island 관련 작업
  - destination / duplicate plugin / widget plist version 트리아지 포함
- `ios-device-run-action`
  - 연결된 실기기 우선 iOS 실행 액션, `flutter devices`/`xcodebuild` destination 불일치 점검
- `app-icon-pipeline`
  - 앱 아이콘 제작, 리소스 갱신, 플랫폼별 반영

## Process / Release

- 기본 선택: `kbo-release-flow`
- `kbo-doc-sync`
  - AGENTS / CLAUDE / README / CHANGELOG / APP_SPEC / WORKLOG / skills 동기화
- `claude-codex-sync`
  - `.claude/skills` 와 repo context 를 Codex-local skill mirror 로 동기화
- `kbo-release-flow`
  - 현재 저장소의 커밋 / 푸시 / numeric release tag / release note 흐름
- `kbo-version-release`
  - 앱 버전 변경, GitHub 릴리즈/태그 정리, 앱 내 업데이트 소식 갱신 루틴
  - 앱 안 노트는 사용자 체감 변화 중심으로 쓰고, 배포/서버/검증 세부는 CHANGELOG/WORKLOG/GitHub Release에 분리
  - 사소한 변경, 구체적인 버그 수정, 성능/안정성 개선도 `새로워졌어요` / `고쳤어요` / `빨라졌어요` / `작게 다듬었어요` 같은 유저용 분류로 정리
  - `이어서 해` 요청 시 실제 diff 기준으로 다음 숫자 버전 또는 기존 릴리즈 노트 보강을 자율 판단
- `mobile-preview-release`
  - legacy 배포 체크리스트, TestFlight / Android 배포 준비
- `app-distribution`
  - 친구/테스터 배포, Android signing, Google Play internal testing, TestFlight 준비
  - iOS TestFlight tester-facing release는 upload에서 끝내지 않고 최신 build `VALID` 확인, `External Testers` 연결, 이전 build 관계 제거, Beta App Review 제출까지 같이 확인

### Release 선택 기준
- `kbo-release-flow`
  - 현재 저장소 기본 릴리즈 흐름
- `kbo-version-release`
  - 버전 번호, changelog, 앱 내 update notes, GitHub release notes 를 같은 단위로 정리
- `mobile-preview-release`
  - 과거 배포 체크리스트 참고용
- `app-distribution`
  - 실제 배포 경로 / signing / TestFlight
- `kbo-doc-sync`
  - 문서 기준 동기화
- `claude-codex-sync`
  - Claude-side skill/doc changes 를 Codex mirror 로 전달

## Rule

- 작업이 위 패턴과 명확히 맞으면 먼저 해당 skill 을 읽고 시작한다.
- 반복 패턴이 새로 생기면 `.claude/skills/`에 승격하고 이 문서에도 추가한다.
