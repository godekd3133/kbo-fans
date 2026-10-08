# 백엔드 운영

## 배포 경로

소수 테스터의 저비용 운영은 Lightsail에서 Docker 없이 API와 sync worker를 systemd로 실행하는 경로를 우선합니다. ECS/Fargate는 API service와 sync worker를 분리하는 확장 경로입니다. 이 문서는 운영 절차를 설명하며 현재 서버 가동 상태를 보증하지 않습니다.

| Lightsail 위치 | 역할 |
| --- | --- |
| `/opt/kbo-fans` | 배포 backend |
| `/etc/kbo-fans/` | 환경과 파일 secret |
| `/var/lib/kbo-fans/` | registry·runtime 영속 상태 |
| `kbo-fans-api` | API systemd 서비스 |
| `kbo-fans-sync-worker` | 동기화 systemd 서비스 |

## Lightsail

`infra/aws/lightsail/env.example`을 복사한 untracked 환경 파일과 로컬 secret 파일을 준비합니다. 실제 배포는 대상 host·domain·현재 환경 보존 여부를 runbook에 맞춰 확인한 뒤 수행합니다.

```bash
./scripts/lightsail-deploy.sh \
  --host ubuntu@<lightsail-host> \
  --env-file /path/to/kbo-fans-lightsail.env \
  --firebase-service-account /path/to/firebase-service-account.json \
  --apns-auth-key /path/to/AuthKey.p8 \
  --domain <API-domain>
```

서버에서 상태를 확인합니다.

```bash
systemctl status kbo-fans-api --no-pager
systemctl status kbo-fans-sync-worker --no-pager
journalctl -u kbo-fans-api -n 80 --no-pager
journalctl -u kbo-fans-sync-worker -n 80 --no-pager
curl http://127.0.0.1:8000/api/health
```

API·worker가 동일한 `SNAPSHOT_DIR`을 사용하는지 확인합니다. 외부 HTTPS API와 worker heartbeat도 별도로 확인합니다.

## ECS/Fargate

`infra/aws/ecs-fargate/deploy.env.example`을 배포 입력 체크리스트로 사용합니다. secret 업로드 → ECR 이미지 build/push → task definition 렌더링·사전점검 → CloudFormation → API URL export → readiness 순으로 진행합니다. 공용 entrypoint는 `scripts/aws-push-demo-deploy.sh`입니다.

```bash
./scripts/push-demo-setup-status.sh \
  --env-file /path/to/kbo-fans-aws.env --repo godekd3133/kbo-fans
./scripts/aws-push-demo-deploy.sh --dry-run
```

입력값과 plan을 확인한 이후 실제 배포 단계로 넘어갑니다. 로컬 AWS CLI/Docker가 준비되지 않은 경우 저장소의 `Push Demo Deploy` workflow 경로를 사용할 수 있습니다.

release 앱에는 운영 HTTPS `API_BASE_URL`을 주입해야 합니다. 임시 HTTP smoke는 실기기 release 토큰 등록 검증과 구분합니다.

## 비용 관리

기존 USD 10 Cost Explorer 기반 반복 guard는 조회 자체의 비용 때문에 비활성화·삭제된 상태라는 저장소 운영 정책을 따릅니다. 반복 guard를 자동 재설치하지 않습니다. 우선 수동 AWS 리소스 점검과 native AWS Budgets 알림을 사용합니다. legacy cost-guard 문서는 과거 참고용입니다.

## 상세 문서와 소스

- [Lightsail runbook](https://github.com/godekd3133/kbo-fans/blob/main/docs/LIGHTSAIL_BACKEND_RUNBOOK.md)
- [ECS/Fargate](https://github.com/godekd3133/kbo-fans/blob/main/infra/aws/ecs-fargate/README.md)
- [통합 배포 스크립트](https://github.com/godekd3133/kbo-fans/blob/main/scripts/aws-push-demo-deploy.sh)
