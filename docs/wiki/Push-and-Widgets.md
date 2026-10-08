# 푸시와 위젯

## 역할 분담

| 표면 | 전달 경로 |
| --- | --- |
| 일반 알림 | 백엔드 경기 변화 감지 → FCM |
| Live Activity / Dynamic Island 시작·갱신 | 백엔드 → APNs ActivityKit push-to-start/update token |
| 앱 foreground 위젯 데이터 반영 | 앱 데이터 → 플랫폼 위젯 연동 |
| 앱 background 위젯 갱신 | 플랫폼·OS의 실행 정책에 영향 받음 |
| 예매 오픈 안내 | 앱 로컬 예약 알림 |

Firebase 일반 푸시와 ActivityKit push는 서로 다른 토큰·전달 경로입니다. 앱이 종료된 뒤에도 경기 정보를 전달하려면 백엔드 worker가 실행 중이어야 합니다.

## 설정 항목

앱에는 iOS Firebase plist, Android Firebase JSON, 알림 권한과 APNs/Live Activity capability가 필요합니다. 백엔드는 Firebase service account, APNs key·team·bundle 설정, `PUSH_SYNC_SECRET`, `PUSH_REGISTRY_PATH`가 필요합니다.

Lightsail 파일 secret은 `/etc/kbo-fans/`에서 참조하고 registry는 `/var/lib/kbo-fans/push_registry.json`에 둡니다. ECS는 Secrets Manager의 `FIREBASE_SERVICE_ACCOUNT_JSON`, `APNS_AUTH_KEY_P8`, `PUSH_SYNC_SECRET`을 주입합니다. 실제 키·토큰은 소스나 Wiki에 올리지 않습니다.

## Worker

`kbo_fans_backend.scheduler.live_activity_sync_loop`가 장기 실행 worker입니다. 가벼운 스코어보드 워밍과 relay/push 동기화 cadence를 분리합니다. `SCOREBOARD_WARM_INTERVAL_SECONDS` 기본은 5초이고 `LIVE_SCOREBOARD_MAX_AGE_SECONDS` 기본은 20초입니다. 상세 warmer는 실행 시간에 맞춰 간격을 조절하고 완성된 종료 데이터만 FINAL로 승격합니다.

## 점검

저장소 루트에서 실행합니다.

```bash
./scripts/push-live-preflight.sh --app-only
./scripts/push-live-preflight.sh --env-file /path/to/kbo-fans-aws.env --aws
./scripts/push-readiness-check.sh https://<운영-API-host>/api
```

readiness에 필요한 `PUSH_SYNC_SECRET`은 안전한 로컬 환경에 주입합니다. 기본 검사는 최신 worker heartbeat를 요구합니다. `/health` 통과는 worker 동작, 푸시 실수신, 앱 종료 후 갱신의 증거와 구분합니다.

## 상세 문서와 소스

- [푸시 설정](https://github.com/godekd3133/kbo-fans/blob/main/docs/PUSH_LIVE_ACTIVITY_BACKEND_SETUP.md)
- [Worker 구현](https://github.com/godekd3133/kbo-fans/blob/main/backend/src/kbo_fans_backend/scheduler/live_activity_sync_loop.py)
- [위젯 작업 가이드](https://github.com/godekd3133/kbo-fans/blob/main/.claude/skills/ios-live-activity-widget/SKILL.md)
