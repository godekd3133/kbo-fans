# Mobile Preview Release Skill

## When To Use

- preview tag / GitHub prerelease 를 만들 때
- TestFlight / Android internal testing 준비 문서를 정리할 때
- Android signing, iOS archive readiness 를 손볼 때

## Files To Check First

- `CHANGELOG.md`
- `docs/WORKLOG.md`
- `docs/ENGINEERING_NOTES.md`
- `docs/DISTRIBUTION_GUIDE.md`
- `docs/ANDROID_SIGNING_GUIDE.md`
- `docs/IOS_TESTFLIGHT_CHECKLIST.md`
- `app/android/app/build.gradle.kts`
- `app/android/key.properties.example`
- `app/ios/Podfile`

## Working Rules

- preview release 는 dirty worktree 상태에서 만들지 않는다
- latest main SHA 와 release tag SHA 를 반드시 확인한다
- Android signing 문서는 `key.properties` 예시와 `.gitignore` 정책까지 같이 묶는다
- iOS 배포 문서는 TestFlight archive/upload 기준으로 쓴다
- user-visible 변경이면 `CHANGELOG.md` 를 같이 갱신한다

## Suggested Flow

1. 변경 파일 커밋/푸시
2. 배포 문서 / changelog / worklog 반영
3. preview tag 생성
4. GitHub prerelease 생성
5. 태그가 최신 SHA 를 가리키는지 검증
