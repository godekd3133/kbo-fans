# 검증과 문제 해결

## 코드 검사

Flutter는 `app/`, backend는 `backend/`에서 실행합니다. FVM을 사용하는 환경에서는 `flutter` 대신 `fvm flutter`를 사용합니다.

```bash
cd app
flutter analyze
flutter test
```

```bash
cd backend
source .venv/bin/activate
python -m pytest -q
python -m ruff check src tests
python -m compileall -q src
```

backend CI의 선언된 test gate는 `python -m pytest -q`입니다. 검사 성공은 해당 코드 층의 근거이며, 운영 API와 실기기 검증은 별도입니다.

## 증상별 접근

| 증상 | 확인할 순서 |
| --- | --- |
| 앱 시작 후 흰 화면 | 시작 로그, API URL·health, boot/onboarding route, 플랫폼 설정 |
| 실기기만 API 실패 | localhost 사용 여부, Mac LAN 주소, 서버 바인딩, 네트워크 |
| API는 정상인데 앱 종료 후 알림 없음 | 앱 권한·등록, Firebase/APNs 설정, worker heartbeat, 실제 수신 |
| 스코어보드가 오래된 0:0 | 공식 main-list 값, summary cache, warm interval, worker 로그 |
| 상세 탭 로딩/503/504 | 요청 deadline·bulkhead, singleflight, shared snapshot, upstream 지연 |
| 현재 기록이 과거 값처럼 보임 | 정확한 season/identity, current 실패 masking 여부, rank·cache shape |
| iPhone destination 누락 | `flutter devices`와 `xcodebuild -showdestinations` 둘 다 확인 |

## 로그와 진단

개발용 기술 로그는 Dev Console과 backend 로그에서 확인합니다. web은 브라우저 console과 설정의 API 진단 경로를 확인합니다. `backend/logs/backend.log`, `backend/logs/client_metrics.log`, 운영 systemd journal을 문제 영역에 맞춰 사용합니다. 토큰·자격증명을 공유 로그에 넣지 않습니다.

## 증거의 경계

Flutter 분석/테스트, backend 검사, API health, 브라우저/시뮬레이터, 실기기, 서명 artifact, 업로드, `VALID`, tester group, Beta App Review, 외부 설치 가능 여부를 따로 기록합니다. fixture·mock·저장 스냅샷 기반 화면 QA는 현재 시즌 운영 데이터 최신성을 증명하지 않습니다.

## 상세 문서와 소스

- [CI build workflow](https://github.com/godekd3133/kbo-fans/blob/main/.github/workflows/app-build-artifacts.yml)
- [시작 오류 트리아지](https://github.com/godekd3133/kbo-fans/blob/main/.claude/skills/app-startup-runtime-triage/SKILL.md)
- [iOS 실행 트리아지](https://github.com/godekd3133/kbo-fans/blob/main/.claude/skills/ios-device-run-action/SKILL.md)
