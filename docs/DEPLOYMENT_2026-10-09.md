# 2026-10-09 프론트·백엔드 운영 배포

## 배포 입력

- 요청: 프론트와 백엔드 모두 배포. 사용자가 iOS TestFlight와 웹 모두를 지정했다.
- 버전: `0.1.36+104`, numeric tag `0.1.36`.
- 소스: `8ee2780bc2689df767a73369da41f64878a16bdc`, `origin/main`과 tag remote readback 일치.
- GitHub Release: https://github.com/godekd3133/kbo-fans/releases/tag/0.1.36
- clean managed worktree: `/Users/kimminkyu/.codex/worktrees/kbo-release-0-1-36/kbo_fans`.
- 배포 전후 tracked diff 없음. 필요한 Firebase plist는 기존 로컬 ignored 설정을 복사한다. QA artifacts, `app/ios/build/`, reference fixture script 변경은 배포 입력에 포함하지 않았다.

## 영향 표면

- app: 홈·상세·기록/순위·알림/설정 UX, push 설정 저장, iOS/Android widget 표시. 프론트 배포는 iOS Runner/Widget TestFlight와 Flutter 웹.
- backend: `HomeService` 문구 및 관련 테스트. consumer는 `ApiHomeRepository`의 `/home` 요청이며 기존 FastAPI route/envelope/provider API mode를 유지한다.
- infra: 기존 Lightsail API/worker runtime 설치와 재시작. 기존 `/etc/kbo-fans/backend.env`, credentials, registry, snapshots, Caddy/TLS 설정 보존.
- release: production `API_BASE_URL=https://3-39-79-1.sslip.io/api`, `APP_ENV=release`, `USE_BACKEND_API=true`.

## 검증

- Flutter analysis: clean. 전체 tests: 657 passed.
- Backend 전체 tests: 759 passed.
- Git diff whitespace check 통과.

## 백엔드 배포 결과

- Lightsail release `20261009075428`, `lightsail_deploy=status=ok`.
- `kbo-fans-api`, `kbo-fans-sync-worker`: active. 내부 health 정상.
- 외부 DNS/TLS 및 `/health`, `/scoreboard/home`, `/game/20261009LGLT0/relay`, `/home`, `/schedule`, `/standings`, `/records/overview`: 모두 HTTP 200과 정상 envelope.
- `home.py` local/remote SHA-256: `28304c65f86336c7662b9aa7ebbe5b5d6492ebc99d96a0ccc69a9380d4811abe`.
- 푸시 readiness: `readyForIphoneOnlyDemo=true`, missing 없음. scheduler heartbeat age 7s, 기준 180s 통과. 수동 테스트 메시지는 보내지 않았다.
- 기존 worker 종료 시 systemd timeout/SIGKILL 후 새 worker가 시작됐다. 재시작 후 sync cycle/live-game warmer가 정상 완료하고 heartbeat가 갱신됐다.

## iOS 배포 결과

- Archive 성공, 자동 프로비저닝으로 IPA export 성공. 기존 수동 profile/certificate 불일치 오류는 기존 Archive 재사용 + automatic export로 해결했다.
- Runner/Widget 버전 `0.1.36/104`, Apple Distribution `MIN KYU KIM (A23ZPKGMW9)`, `codesign --verify --deep --strict` 통과. Runner `aps-environment=production`, `get-task-allow=false`, `beta-reports-active=true`.
- IPA compiled App.framework binary에서 production API URL 확인.
- 보관 IPA: `output/release-0.1.36/kbo_fans.ipa`, SHA-256 `9db287ca454551b7532379feee4421ff6e024b6086cf020f7946baa48db2ed08`. Archive를 다시 export/upload하므로 업로드 체크포인트와 보관 IPA 해시는 구분한다.
- Xcode upload 성공/EXPORT SUCCEEDED, Apple build `ca065a23-f687-447e-afbe-f548b0fead04` processing `VALID`, audience `APP_STORE_ELIGIBLE`, encryption exemption false.
- Internal `Tester`는 build 104 자동 연결(readback 확인); internal 관계 수동 추가는 Apple API가 허용하지 않아 자동 연결 결과를 확인했다. External `External Testers` add HTTP 204/readback 확인. 기존 build 103도 유지.
- Korean beta test notes의 자동 생성된 localization을 PATCH로 갱신했다.
- Beta App Review submission HTTP 201, readback `WAITING_FOR_REVIEW`, beta detail `internalBuildState=IN_BETA_TESTING`, `externalBuildState=WAITING_FOR_BETA_REVIEW`.
- `objective_c.framework` dSYM 미포함 symbol upload warning은 non-blocking으로 기록한다. 업로드와 VALID 성공은 별도 확인했다. 외부 installability는 Apple 승인 대기.
- 실제 iPhone 설치/업데이트, closed-app 푸시 실수신, Live Activity 렌더는 서버/서명/업로드 확인과 별도 단말 acceptance이다.

## 웹 배포 결과

- 사용자 지정으로 TestFlight와 웹을 모두 배포. 공개 URL `https://3-39-79-1.sslip.io/`.
- 같은 clean SHA/production API flags로 Flutter JS web release build 성공.
- `scripts/lightsail-web-deploy.sh` dry-run/bash syntax 검증 후 적용. web release `20261009080955-8ee2780b`, config backup `/etc/caddy/Caddyfile.before-web-20261009080955-8ee2780b`.
- 기존 host 안의 API/doc 요청은 backend reverse_proxy, root는 정적 Flutter SPA로 구성. Caddy validate 성공/reload 성공. 기존 pc-supporter host block을 보존했다. shell/JS에는 no-cache 응답을 설정했다.
- 운영 브라우저(1280×720) onboarding→skip→home→game score→relay 확인. home에 실제 2026-10-09 경기/순위가 렌더됐다. desktop smoke이며 실기기/mobile acceptance는 별도다.
- screenshot `output/release-0.1.36/web-home.jpg`. 웹 적용 이후 external API 7 endpoints 재통과.
- 기존 app/backend 병행 작업 변경과 QA artifacts는 보존하고 배포 소스 범위와 분리했다.
