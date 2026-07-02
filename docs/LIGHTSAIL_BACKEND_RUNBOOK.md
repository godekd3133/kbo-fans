# Lightsail Backend Runbook

## Goal

Run the KBO Fans API and push / Live Activity sync worker on one low-cost
Lightsail Linux instance without Docker, ECS, ALB, EFS, ECR, or Secrets Manager.

Target cost:

- 512 MB Linux with public IPv4: about USD 5/month
- 1 GB Linux with public IPv4: about USD 7/month if 512 MB is not stable enough

## Runtime Shape

```text
api.kbofans.com
  -> Lightsail static IP
  -> Caddy HTTPS reverse proxy
  -> 127.0.0.1:8000 FastAPI
  -> local /var/lib/kbo-fans registry

same instance
  -> systemd kbo-fans-sync-worker
  -> python -m kbo_fans_backend.scheduler.live_activity_sync_loop
```

The app contract does not change. Flutter release builds still use
`USE_BACKEND_API=true` and a production `API_BASE_URL`, preferably
`https://api.kbofans.com/api`.

If a paid Route 53 hosted zone is not desired during the tester phase, use the
free wildcard DNS host `https://<ip-with-dashes>.sslip.io/api`, for example
`https://3-39-79-1.sslip.io/api`. This avoids AWS DNS cost while keeping HTTPS,
but it depends on the third-party `sslip.io` DNS service.

## Files

- `infra/aws/lightsail/env.example`: backend env shape for file-based secrets.
- `infra/aws/lightsail/systemd/kbo-fans-api.service`: FastAPI systemd unit.
- `infra/aws/lightsail/systemd/kbo-fans-sync-worker.service`: long-running sync worker.
- `infra/aws/lightsail/Caddyfile.example`: HTTPS reverse proxy template.
- `scripts/lightsail-deploy.sh`: local SSH/SCP deployment helper.

## One-Time AWS Console Setup

1. Create a Lightsail Linux instance.
   - Start with 512 MB.
   - Use 1 GB if memory pressure or worker restarts appear.
2. Attach a Lightsail static IP to the instance.
3. Open ports `22`, `80`, and `443` in the Lightsail firewall.
4. Point `api.kbofans.com` DNS to the static IP.
   - Temporary no-cost alternative: use `<static-ip-with-dashes>.sslip.io`.
5. Keep the static IP attached. Unattached static IPs can incur hourly charges.

Stopping a Lightsail instance does not stop its plan charges. If AWS actual or
forecasted cost reaches the hard USD 10 guardrail and cost is more important
than availability, use `docs/AWS_COST_GUARD_RUNBOOK.md` and destructive mode to
delete matching Lightsail resources only after preserving anything that must
survive. Lightsail deletion requires the separate `--delete-lightsail-instances`
flag.

## Local Secret Env

Create an untracked env file:

```bash
cp infra/aws/lightsail/env.example /tmp/kbo-fans-lightsail.env
$EDITOR /tmp/kbo-fans-lightsail.env
```

Use file paths for multiline secrets:

```text
LOG_DIR=/var/log/kbo-fans
SNAPSHOT_DIR=/var/lib/kbo-fans/snapshots
FIREBASE_SERVICE_ACCOUNT_PATH=/etc/kbo-fans/firebase-service-account.json
APNS_AUTH_KEY_PATH=/etc/kbo-fans/apns-auth-key.p8
```

Pass the local source files to the deploy script. The script installs them under
`/etc/kbo-fans/` with restricted permissions.

## Deploy

```bash
./scripts/lightsail-deploy.sh \
  --host ubuntu@<lightsail-ip-or-host> \
  --env-file /tmp/kbo-fans-lightsail.env \
  --firebase-service-account /path/to/firebase-service-account.json \
  --apns-auth-key /path/to/AuthKey_<KEY_ID>.p8 \
  --domain api.kbofans.com
```

Use `--ssh-key /path/to/key.pem` if the SSH key is not already configured in
`~/.ssh/config`.

The deploy script packages only the backend runtime files and snapshots, uploads
them with `scp`, installs Python dependencies into `/opt/kbo-fans/venv`, then
restarts:

- `kbo-fans-api`
- `kbo-fans-sync-worker`

## Verify

On the server:

```bash
systemctl status kbo-fans-api --no-pager
systemctl status kbo-fans-sync-worker --no-pager
journalctl -u kbo-fans-api -n 80 --no-pager
journalctl -u kbo-fans-sync-worker -n 80 --no-pager
curl http://127.0.0.1:8000/api/health
```

From the repo:

```bash
PUSH_SYNC_SECRET=<secret> \
./scripts/push-readiness-check.sh https://api.kbofans.com/api
```

Readiness requires a fresh scheduler heartbeat by default, so a stopped worker
will fail even if `/health` is OK.

## Memory Guard

512 MB is the cost target, not a guarantee. Watch the worker for restarts:

```bash
free -h
systemctl show kbo-fans-api -p NRestarts
systemctl show kbo-fans-sync-worker -p NRestarts
journalctl -u kbo-fans-sync-worker --since "1 hour ago" --no-pager
```

If the kernel OOM killer appears or either service repeatedly restarts, resize
the instance to the 1 GB plan and keep the same static IP.

## Cutover From ECS/Fargate

1. Deploy Lightsail and verify `https://api.kbofans.com/api/health`.
2. Build the next TestFlight artifact with `API_BASE_URL=https://api.kbofans.com/api`.
3. Confirm `/push/register`, `/push/live-activity/register`, and
   `push-readiness-check` against Lightsail.
4. Keep the existing ECS/Fargate ALB running until the new build is installed by
   testers or the DNS-backed API URL is confirmed in use.
5. Delete the old CloudFormation push demo stack only after cutover is verified.

Do not delete the old stack first; current TestFlight builds may still contain
the old ALB URL.
