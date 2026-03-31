# Engineering Notes

## Purpose

이 문서는 구현 중 얻은 반복적인 인사이트와 운영/검증 메모를 모은다.
기획 문서보다는 구현 판단 기준에 가깝고, `AGENTS.md` / `CLAUDE.md` 를 보완하는 용도로 사용한다.

## Local / Dev Data Behavior

- `local` 앱 실행은 백엔드가 항상 떠 있다고 가정하지 않는다.
- 앱 로컬 모드에서는 KBO direct 경로가 필요할 수 있으므로, fallback 여부를 명시적으로 결정해야 한다.
- noisy fallback 로그가 과하면 `local` / 테스트 바인딩에서 prefetch, metric, push init을 완화하는 방향이 안전하다.
- local, dev, release API base URL은 코드에 고정 default 를 두되 `API_BASE_URL` override 를 우선한다.

## Widget / Live Activity

- Live Activity 선택 우선순위:
  1. 진행중인 마이팀 경기
  2. 진행중인 다른 경기
  3. 오늘 마이팀 예정 경기
  4. 오늘 다른 예정 경기
- 홈 위젯과 Live Activity는 가능한 한 같은 source scoreboard 를 기준으로 동기화한다.
- 중복 업데이트는 signature 비교로 억제한다.
- 앱이 resumed 될 때 scoreboard 를 다시 invalidate 해 Live Activity 를 재동기화한다.
- Live Activity 는 코드상 연결만으로 끝나지 않는다.
  - Widget extension signing
  - App Group entitlement
  - 실제 기기 검증
  를 별도로 확인해야 한다.

## Launch / First Frame

- iOS/Android launch surface 는 앱 테마와 같은 다크 배경을 유지해 흰 화면 플래시를 줄인다.
- launch UI 를 바꾸면 `CHANGELOG.md` 와 `docs/WORKLOG.md` 에 같이 반영한다.

## iOS Build / Pod Warnings

- Pod deployment target 경고는 `Podfile` 의 `post_install` 에서 일괄 보정하는 편이 낫다.
- 플러그인 Objective-C 경고는 repo 코드가 아니라 pub cache / pod 소스라, 가능하면 설정으로 억제하고 근본 수정은 dependency upgrade 로 푼다.
- `dummy.o has no symbols` 는 보통 harmless warning 이다.

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

