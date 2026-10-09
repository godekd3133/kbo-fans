#!/usr/bin/env bash
set -euo pipefail
HOST=""
BUILD_DIR=""
DOMAIN="3-39-79-1.sslip.io"
SOURCE_SHA=""
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --build-dir) BUILD_DIR="$2"; shift 2 ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --source-sha) SOURCE_SHA="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo 'Usage: lightsail-web-deploy.sh --host ubuntu@host --build-dir /path/build/web --source-sha SHA [--domain host] [--dry-run]' >&2; exit 2 ;;
  esac
done
[[ -n "$HOST" && -f "$BUILD_DIR/index.html" && -f "$BUILD_DIR/main.dart.js" ]] || { echo 'Host and a completed Flutter web release build are required.' >&2; exit 2; }
[[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+$ && "$SOURCE_SHA" =~ ^[a-f0-9]{8,40}$ ]] || { echo 'Invalid domain or source SHA.' >&2; exit 2; }
RELEASE_ID="$(date -u +%Y%m%d%H%M%S)-${SOURCE_SHA:0:8}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
tar -czf "$TMP_DIR/web.tar.gz" -C "$BUILD_DIR" .
echo "web_bundle=status=ok source=$SOURCE_SHA release=$RELEASE_ID"
if [[ "$DRY_RUN" == true ]]; then exit 0; fi
REMOTE_TMP="/tmp/kbo-fans-web-$RELEASE_ID"
SSH_ARGS=(-o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=4)
ssh "${SSH_ARGS[@]}" "$HOST" "mkdir -p '$REMOTE_TMP'"
scp "${SSH_ARGS[@]}" "$TMP_DIR/web.tar.gz" "$HOST:$REMOTE_TMP/web.tar.gz"
ssh "${SSH_ARGS[@]}" "$HOST" "DOMAIN='$DOMAIN' RELEASE_ID='$RELEASE_ID' REMOTE_TMP='$REMOTE_TMP' SOURCE_SHA='$SOURCE_SHA' bash -s" <<'REMOTE'
set -euo pipefail
WEB_ROOT=/opt/kbo-fans/web
RELEASE_DIR="$WEB_ROOT/releases/$RELEASE_ID"
sudo mkdir -p "$RELEASE_DIR"
sudo tar -xzf "$REMOTE_TMP/web.tar.gz" -C "$RELEASE_DIR"
sudo chown -R root:root "$RELEASE_DIR"
sudo chmod -R a+rX "$RELEASE_DIR"
printf '%s\n' "$SOURCE_SHA" | sudo tee "$RELEASE_DIR/deployment-sha.txt" >/dev/null
sudo python3 - "$DOMAIN" "$REMOTE_TMP/Caddyfile" <<'PY'
from pathlib import Path
import re,sys
host,output=sys.argv[1:]
s=Path('/etc/caddy/Caddyfile').read_text()
m=re.search(r'(?m)^'+re.escape(host)+r'\s*\{',s)
if not m: raise SystemExit('Requested host is absent from existing Caddy config; refusing to change it.')
level=1; end=m.end()
while level and end < len(s):
    if s[end]=='{': level+=1
    elif s[end]=='}': level-=1
    end+=1
if level: raise SystemExit('Unbalanced existing Caddy host block.')
block='''HOST {
    encode gzip
    @backend path /api /api/* /docs /docs/* /redoc /redoc/* /openapi.json
    handle @backend {
        reverse_proxy 127.0.0.1:8000
    }
    handle {
        root * /opt/kbo-fans/web/current
        @shell path / /index.html /flutter_bootstrap.js /main.dart.js /flutter_service_worker.js /manifest.json /version.json /deployment-sha.txt
        header @shell Cache-Control "no-cache"
        try_files {path} /index.html
        file_server
    }
}'''.replace('HOST',host,1)
Path(output).write_text(s[:m.start()]+block+s[end:])
PY
sudo caddy validate --config "$REMOTE_TMP/Caddyfile" --adapter caddyfile
BACKUP="/etc/caddy/Caddyfile.before-web-$RELEASE_ID"
sudo cp /etc/caddy/Caddyfile "$BACKUP"
OLD_LINK="$(readlink "$WEB_ROOT/current" || true)"
rollback() {
    trap - ERR
    sudo cp "$BACKUP" /etc/caddy/Caddyfile
    if [[ -n "$OLD_LINK" ]]; then sudo ln -sfn "$OLD_LINK" "$WEB_ROOT/current"; else sudo rm -f "$WEB_ROOT/current"; fi
    sudo systemctl reload caddy
}
trap rollback ERR
sudo ln -sfn "$RELEASE_DIR" "$WEB_ROOT/current"
sudo install -o root -g root -m 0644 "$REMOTE_TMP/Caddyfile" /etc/caddy/Caddyfile
sudo systemctl reload caddy
curl --fail --silent --show-error --max-time 15 "https://$DOMAIN/api/health" >/dev/null
curl --fail --silent --show-error --max-time 15 "https://$DOMAIN/deployment-sha.txt" | head -1
trap - ERR
echo "web_deploy=status=ok release=$RELEASE_ID url=https://$DOMAIN/ config_backup=$BACKUP"
REMOTE
