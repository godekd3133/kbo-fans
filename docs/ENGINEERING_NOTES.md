# Engineering Notes

## Purpose

이 문서는 구현 중 얻은 반복적인 인사이트와 운영/검증 메모를 모은다.
기획 문서보다는 구현 판단 기준에 가깝고, `AGENTS.md` / `CLAUDE.md` 를 보완하는 용도로 사용한다.

## Local / Dev Data Behavior

- `local` 앱 실행은 백엔드가 항상 떠 있다고 가정하지 않는다.
- 앱 로컬 모드라도 기본 데이터 경로는 API 이며, KBO direct 경로는 `PREFER_DIRECT_SCRAPE=true` 를 준 명시적 임시 direct-primary 검증 세션에서만 사용한다.
- 앱 startup은 원격 API prefetch를 소유하지 않는다. local onboarding/my-team 상태 확인 후 첫 route로 넘기고, scoreboard/home/records/schedule 요청은 각 화면 provider가 소유한다.
- noisy fallback 로그가 과하면 `local` / 테스트 바인딩에서 prefetch, metric, push init을 완화하는 방향이 안전하다.
- local, dev, release API base URL은 코드에 고정 default 를 두되 `API_BASE_URL` override 를 우선한다.
- iPhone local debug에서 `localhost` API는 실기기에서 직접 닿지 않는다.
  - backend를 켜고 실기기에서 API를 쓰려면 Mac LAN IP를 `API_BASE_URL`로 주입해야 한다.
  - `scripts/codex-run.sh ios` 는 backend가 8000 포트로 떠 있으면 자동으로 LAN IP를 주입하도록 유지한다.
- backend가 없는 local iPhone 경로에서도 direct KBO source로 자동 fallback 하지 않는다. 필요하면 명시적 임시 direct-primary build로 분리한다.
  - scoreboard live status는 `Main.asmx/GetKboGameList` 를 우선 참고한다.
  - 일정 파서는 `GetScheduleList`의 빈 action cell에서도 `gameId`를 날짜+팀 코드로 복원해야 한다.
  - relay는 `LiveTextView2.aspx` markup(`#numCont*`, `p.present`, `.playerBox`) 기준으로 파싱한다.
- local/mobile 알림은 remote push가 아니라 앱 내부 비교 로직이다.
  - scoreboard diff: 경기 시작 / 득점 / 역전 / 종료
  - relay diff: 홈런 / 이닝 교대
  - lineup diff: 선발 라인업 공개 / 변경
  - 따라서 앱이 완전히 죽어 있으면 서버 push처럼 즉시 오지 않는다.
- 홈 scoreboard 자동 refresh cadence는 live 30초, scheduled 5분, terminal 정지로 둔다.

## Widget / Live Activity

- Live Activity 선택 우선순위:
  1. 진행중인 마이팀 경기
  2. 진행중인 다른 경기
  3. 오늘 마이팀 예정 경기
  4. 오늘 다른 예정 경기
- 홈 위젯과 Live Activity는 가능한 한 같은 source scoreboard 를 기준으로 동기화한다.
- 중복 업데이트는 signature 비교로 억제한다.
- 앱이 native에서 resumed 될 때만 scoreboard 를 다시 invalidate 해 Live Activity 를 재동기화한다. 웹은 홈 위젯/Live Activity가 없으므로 전역 resume refresh를 등록하지 않는다.
- Live Activity 는 코드상 연결만으로 끝나지 않는다.
  - Widget extension signing
  - App Group entitlement
  - 실제 기기 검증
  를 별도로 확인해야 한다.
- local iPhone debug에서는 `home_widget` / App Group / Workmanager 경로가 런타임 안정성을 해칠 수 있다.
  - `APP_ENV=local` + iOS 에서는 widget sync / periodic refresh 등록을 no-op 처리하는 편이 안전하다.
- foreground 기준 잠금화면 체감 갱신은 홈 scoreboard invalidate 주기에 의해 사실상 상한이 결정된다.
  - live game polling 간격은 현재 10초 기준으로 맞춘다.
  - static widget timeline은 1분 단위 재로드를 요청한다.
  - Live Activity / widget `updatedAt` 에는 초 단위 시각을 넣어 실제 갱신 여부를 구분한다.
- widget/live sync signature는 점수/이닝이 안 바뀌더라도 live 중에는 일정 주기로 다시 흘려보내야 체감 갱신이 유지된다.

## Launch / First Frame

- iOS/Android launch surface 는 앱 테마와 같은 다크 배경을 유지해 흰 화면 플래시를 줄인다.
- launch UI 를 바꾸면 `CHANGELOG.md` 와 `docs/WORKLOG.md` 에 같이 반영한다.

## iOS Build / Pod Warnings

- Pod deployment target 경고는 `Podfile` 의 `post_install` 에서 일괄 보정하는 편이 낫다.
- 플러그인 Objective-C 경고는 repo 코드가 아니라 pub cache / pod 소스라, 가능하면 설정으로 억제하고 근본 수정은 dependency upgrade 로 푼다.
- `dummy.o has no symbols` 는 보통 harmless warning 이다.
- Flutter가 생성하는 `Generated.xcconfig` / `flutter_export_environment.sh` 에 stale `CONFIGURATION_BUILD_DIR` 가 남으면 `Pods_Runner.framework not found` 같은 링크 오류가 날 수 있다.
- Flutter native asset `objective_c.framework` 는 실기기 빌드에서 simulator slice가 섞이거나 adhoc 서명으로 남을 수 있다.
  - 앱 타깃 build phase에서 플랫폼에 맞는 `objective_c.dylib` 를 선택해 덮어쓰고 프레임워크 번들 단위로 다시 codesign 하는 방식이 안전했다.

## Release / Preview

- 프리뷰 릴리즈를 만들 때는:
  1. 워크트리를 먼저 비운다
  2. 최신 `main` 기준 커밋/푸시를 끝낸다
  3. preview tag 를 만든다 (`0.0.1-preview`, 필요 시 `.1`, `.2`)
  4. GitHub prerelease 를 생성한다
- preview tag 는 최신 커밋과 어긋나기 쉬우므로, release 시점의 SHA 를 반드시 확인한다.

## Distribution Docs

- 배포 관련 반복 작업은 아래 문서를 같이 유지한다.
  - `docs/DISTRIBUTION_GUIDE.md`
  - `docs/ANDROID_SIGNING_GUIDE.md`
  - `docs/IOS_TESTFLIGHT_CHECKLIST.md`
