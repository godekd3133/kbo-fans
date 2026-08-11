#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_TARGET=""
SSH_KEY=""
ENV_FILE=""
FIREBASE_SERVICE_ACCOUNT_FILE=""
APNS_AUTH_KEY_FILE=""
DOMAIN=""
REMOTE_TMP="/tmp/kbo-fans-lightsail"
APP_DIR="/opt/kbo-fans"
INSTALL_CADDY=true
DRY_RUN=false
RELEASE_ID="$(date -u +%Y%m%d%H%M%S)"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/lightsail-deploy.sh \
    --host ubuntu@<lightsail-ip-or-host> \
    --env-file /tmp/kbo-fans-lightsail.env \
    --firebase-service-account /path/firebase-service-account.json \
    --apns-auth-key /path/AuthKey_<KEY_ID>.p8 \
    --domain api.kbofans.com

Options:
  --host                       SSH target, for example ubuntu@1.2.3.4.
  --ssh-key                    SSH private key path.
  --env-file                   Local backend env file. Required.
  --firebase-service-account   Local Firebase Admin JSON file.
  --apns-auth-key              Local APNs .p8 file.
  --domain                     HTTPS host for Caddy, for example api.kbofans.com.
  --remote-tmp                 Remote temporary upload dir. Default /tmp/kbo-fans-lightsail.
  --app-dir                    Remote app dir. Default /opt/kbo-fans.
  --skip-caddy                 Do not install or configure Caddy.
  --dry-run                    Create and inspect the deployment bundle without SSH.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      SSH_TARGET="${2:-}"
      shift 2
      ;;
    --ssh-key)
      SSH_KEY="${2:-}"
      shift 2
      ;;
    --env-file)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    --firebase-service-account)
      FIREBASE_SERVICE_ACCOUNT_FILE="${2:-}"
      shift 2
      ;;
    --apns-auth-key)
      APNS_AUTH_KEY_FILE="${2:-}"
      shift 2
      ;;
    --domain)
      DOMAIN="${2:-}"
      shift 2
      ;;
    --remote-tmp)
      REMOTE_TMP="${2:-}"
      shift 2
      ;;
    --app-dir)
      APP_DIR="${2:-}"
      shift 2
      ;;
    --skip-caddy)
      INSTALL_CADDY=false
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$ENV_FILE" ]]; then
  echo "--env-file is required." >&2
  usage >&2
  exit 2
fi

if [[ "$DRY_RUN" != "true" && -z "$SSH_TARGET" ]]; then
  echo "--host is required unless --dry-run is set." >&2
  usage >&2
  exit 2
fi

for path in "$ENV_FILE" "$FIREBASE_SERVICE_ACCOUNT_FILE" "$APNS_AUTH_KEY_FILE"; do
  if [[ -n "$path" && ! -f "$path" ]]; then
    echo "File not found: $path" >&2
    exit 2
  fi
done

require_cmd tar
require_cmd mktemp
if [[ "$DRY_RUN" != "true" ]]; then
  require_cmd ssh
  require_cmd scp
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

BUNDLE="$TMP_DIR/kbo-fans-backend-$RELEASE_ID.tar.gz"

(
  cd "$ROOT_DIR"
  tar \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='*.egg-info' \
    --exclude='.DS_Store' \
    -czf "$BUNDLE" \
    backend/pyproject.toml \
    backend/README.md \
    backend/src \
    backend/data/snapshots \
    infra/aws/lightsail
)

echo "lightsail_bundle=status=ok path=$BUNDLE"
tar -tzf "$BUNDLE" | sed -n '1,30p'

if [[ "$DRY_RUN" == "true" ]]; then
  echo "lightsail_deploy=status=ok mode=dry-run release=$RELEASE_ID"
  exit 0
fi

SSH_ARGS=()
SCP_ARGS=()
if [[ -n "$SSH_KEY" ]]; then
  SSH_ARGS+=(-i "$SSH_KEY")
  SCP_ARGS+=(-i "$SSH_KEY")
fi

ssh "${SSH_ARGS[@]}" "$SSH_TARGET" "mkdir -p '$REMOTE_TMP'"
scp "${SCP_ARGS[@]}" "$BUNDLE" "$SSH_TARGET:$REMOTE_TMP/kbo-fans-backend.tar.gz"
scp "${SCP_ARGS[@]}" "$ENV_FILE" "$SSH_TARGET:$REMOTE_TMP/backend.env"

if [[ -n "$FIREBASE_SERVICE_ACCOUNT_FILE" ]]; then
  scp "${SCP_ARGS[@]}" "$FIREBASE_SERVICE_ACCOUNT_FILE" \
    "$SSH_TARGET:$REMOTE_TMP/firebase-service-account.json"
fi

if [[ -n "$APNS_AUTH_KEY_FILE" ]]; then
  scp "${SCP_ARGS[@]}" "$APNS_AUTH_KEY_FILE" "$SSH_TARGET:$REMOTE_TMP/apns-auth-key.p8"
fi

ssh "${SSH_ARGS[@]}" "$SSH_TARGET" \
  "RELEASE_ID='$RELEASE_ID' REMOTE_TMP='$REMOTE_TMP' APP_DIR='$APP_DIR' DOMAIN='$DOMAIN' INSTALL_CADDY='$INSTALL_CADDY' HAS_FIREBASE='$([[ -n "$FIREBASE_SERVICE_ACCOUNT_FILE" ]] && echo true || echo false)' HAS_APNS='$([[ -n "$APNS_AUTH_KEY_FILE" ]] && echo true || echo false)' bash -s" <<'REMOTE'
set -euo pipefail

SERVICE_USER="kbo-fans"
RELEASE_DIR="$APP_DIR/releases/$RELEASE_ID"

if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  sudo useradd --system --home /var/lib/kbo-fans --shell /usr/sbin/nologin "$SERVICE_USER"
fi

sudo mkdir -p "$RELEASE_DIR" "$APP_DIR/shared" /etc/kbo-fans /var/lib/kbo-fans /var/log/kbo-fans
sudo tar -xzf "$REMOTE_TMP/kbo-fans-backend.tar.gz" -C "$RELEASE_DIR"
sudo chown -R root:root "$RELEASE_DIR"
sudo chown -R "$SERVICE_USER:$SERVICE_USER" /var/lib/kbo-fans /var/log/kbo-fans

sudo install -o root -g "$SERVICE_USER" -m 0640 "$REMOTE_TMP/backend.env" /etc/kbo-fans/backend.env

if [[ "$HAS_FIREBASE" == "true" ]]; then
  sudo install -o root -g "$SERVICE_USER" -m 0640 \
    "$REMOTE_TMP/firebase-service-account.json" \
    /etc/kbo-fans/firebase-service-account.json
fi

if [[ "$HAS_APNS" == "true" ]]; then
  sudo install -o root -g "$SERVICE_USER" -m 0640 \
    "$REMOTE_TMP/apns-auth-key.p8" \
    /etc/kbo-fans/apns-auth-key.p8
fi

sudo ln -sfn "$RELEASE_DIR" "$APP_DIR/current"

sudo install -d -o "$SERVICE_USER" -g "$SERVICE_USER" -m 0750 \
  /var/lib/kbo-fans/snapshots

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates \
  curl \
  python3 \
  python3-pip \
  python3-venv

if [[ ! -x "$APP_DIR/venv/bin/python" ]]; then
  sudo python3 -m venv "$APP_DIR/venv"
fi

sudo "$APP_DIR/venv/bin/python" -m pip install --upgrade --no-cache-dir pip setuptools wheel
sudo "$APP_DIR/venv/bin/python" -m pip install --upgrade --no-cache-dir "$APP_DIR/current/backend"

sudo install -o root -g root -m 0644 \
  "$APP_DIR/current/infra/aws/lightsail/systemd/kbo-fans-api.service" \
  /etc/systemd/system/kbo-fans-api.service
sudo install -o root -g root -m 0644 \
  "$APP_DIR/current/infra/aws/lightsail/systemd/kbo-fans-sync-worker.service" \
  /etc/systemd/system/kbo-fans-sync-worker.service

if [[ "$INSTALL_CADDY" == "true" ]]; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y caddy
  if [[ -n "$DOMAIN" ]]; then
    sed "s/api\.kbofans\.com/$DOMAIN/g" \
      "$APP_DIR/current/infra/aws/lightsail/Caddyfile.example" > "$REMOTE_TMP/Caddyfile"
    sudo install -o root -g root -m 0644 "$REMOTE_TMP/Caddyfile" /etc/caddy/Caddyfile
    sudo systemctl enable caddy
    sudo systemctl restart caddy
  fi
fi

sudo systemctl daemon-reload
sudo systemctl enable kbo-fans-api kbo-fans-sync-worker
sudo systemctl restart kbo-fans-api
sudo systemctl restart kbo-fans-sync-worker

curl -fsS http://127.0.0.1:8000/api/health
echo
systemctl --no-pager --full status kbo-fans-api | sed -n '1,18p'
systemctl --no-pager --full status kbo-fans-sync-worker | sed -n '1,18p'

echo "lightsail_remote_deploy=status=ok release=$RELEASE_ID"
REMOTE

echo "lightsail_deploy=status=ok release=$RELEASE_ID host=$SSH_TARGET"
