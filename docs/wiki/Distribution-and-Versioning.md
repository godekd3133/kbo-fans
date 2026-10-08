# 배포와 버전

## 공유 경로

| 대상 | 기본 경로 |
| --- | --- |
| 빠른 화면 공유 | Web |
| iPhone 테스터 | TestFlight |
| Android 테스터 | 서명 설정 후 Google Play 내부 테스트 |

release 빌드는 `APP_ENV=release`, `USE_BACKEND_API=true`, 운영 `API_BASE_URL`을 명시합니다. 화면 GET과 푸시·Live Activity 토큰 등록이 같은 운영 백엔드를 사용해야 합니다.

## 버전 정책

소스 버전은 `app/pubspec.yaml`의 `MAJOR.MINOR.PATCH+BUILD`, Git tag는 `MAJOR.MINOR.PATCH`입니다. 현재 소스 기준 `0.1.35+103`, release line은 `0.1.x`입니다. 최신 배포/심사 상태는 이 버전 표기로 판단하지 않습니다.

테스터용 checkpoint는 PATCH와 build를 올립니다. preview/alpha/beta/rc 접미사·prerelease는 명시적 정책 변경 없이 생성하지 않습니다. 게시 tag는 불변으로 유지합니다.

버전 변경 시 `pubspec.yaml`, `CHANGELOG.md`, 앱 내 `patch_notes.md`, GitHub Release, `WORKLOG.md`를 함께 맞춥니다. 문서만 추가하는 이번 Wiki 작업은 앱 버전을 변경하지 않습니다.

## 배포 입력과 검증

테스터용 산출물은 정확한 pushed SHA의 clean isolated worktree에서 생성합니다. 현재 dirty worktree의 다른 작업을 release 입력으로 섞지 않습니다.

```bash
./scripts/release-api-health-check.sh
```

`App Build Artifacts` workflow는 플랫폼·환경·signed IPA 옵션·release API URL을 입력받습니다. CI 산출물이 생성된 사실과 스토어 배포 성공은 구분합니다. Android signing은 로컬 `app/android/key.properties`와 keystore로 구성하며 커밋하지 않습니다.

## TestFlight 완료 기준

1. 정확한 소스·버전·서명으로 IPA 생성 및 업로드.
2. Apple processing 완료와 build `VALID` 확인.
3. 최신 build를 `External Testers` 그룹에 연결.
4. 미제출/미승인 build는 Beta App Review 제출.
5. 승인과 외부 설치 가능 여부 확인.
6. 실기기 설치·실행·화면 데이터·알림·Live Activity 확인.

이 단계는 각각 독립 checkpoint입니다. 새 build의 외부 설치가 확인되기 전 마지막 승인/설치 가능한 build를 제거하지 않습니다. 이번 문서 작업에서는 build·upload·심사 상태 조회를 실행하지 않았습니다.

## 상세 문서와 소스

- [배포 가이드](https://github.com/godekd3133/kbo-fans/blob/main/docs/DISTRIBUTION_GUIDE.md)
- [버전 정책](https://github.com/godekd3133/kbo-fans/blob/main/docs/VERSIONING.md)
- [TestFlight 체크리스트](https://github.com/godekd3133/kbo-fans/blob/main/docs/IOS_TESTFLIGHT_CHECKLIST.md)
- [Android 서명](https://github.com/godekd3133/kbo-fans/blob/main/docs/ANDROID_SIGNING_GUIDE.md)
