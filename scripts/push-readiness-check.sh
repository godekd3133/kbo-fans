#!/usr/bin/env bash

set -euo pipefail

BASE_URL="${1:-${PUSH_API_BASE_URL:-${API_BASE_URL:-https://api.kbofans.com/api}}}"
BASE_URL="${BASE_URL%/}"
SYNC_SECRET="${2:-${PUSH_SYNC_SECRET:-}}"
TIMEOUT_SECONDS="${PUSH_READINESS_TIMEOUT_SECONDS:-20}"
ALLOW_INSECURE="${ALLOW_INSECURE_PUSH_READINESS:-false}"
RUN_SYNC="${PUSH_READINESS_RUN_SYNC:-false}"
SYNC_DATE="${PUSH_READINESS_DATE:-}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd curl
require_cmd python3

if [[ -z "$BASE_URL" ]]; then
  echo "Push API base URL is empty." >&2
  exit 1
fi

if [[ -z "$SYNC_SECRET" ]]; then
  cat >&2 <<'EOF'
PUSH_SYNC_SECRET is required for push readiness checks.

Usage:
  PUSH_SYNC_SECRET=<secret> ./scripts/push-readiness-check.sh https://api.kbofans.com/api
EOF
  exit 1
fi

URL_PARTS="$(
  python3 - "$BASE_URL" <<'PY'
from urllib.parse import urlparse
import sys

url = sys.argv[1]
parsed = urlparse(url)
if parsed.scheme not in {"http", "https"}:
    print(f"Invalid API URL scheme: {parsed.scheme or '<empty>'}", file=sys.stderr)
    raise SystemExit(2)
if not parsed.hostname:
    print(f"Invalid API URL host: {url}", file=sys.stderr)
    raise SystemExit(2)
port = parsed.port or (443 if parsed.scheme == "https" else 80)
print(parsed.scheme, parsed.hostname, port)
PY
)"
read -r URL_SCHEME URL_HOST URL_PORT <<< "$URL_PARTS"

if [[ "$URL_SCHEME" != "https" && "$ALLOW_INSECURE" != "true" ]]; then
  cat >&2 <<EOF
Push readiness check must use HTTPS for remote demo backend.

Current:
  $BASE_URL

For local script testing only, set ALLOW_INSECURE_PUSH_READINESS=true.
EOF
  exit 1
fi

echo "Push readiness check"
echo "base_url=$BASE_URL"
echo "sync_date=${SYNC_DATE:-backend-default-kbo-date}"

DNS_ADDRESSES="$(
  python3 - "$URL_HOST" "$URL_PORT" <<'PY'
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
try:
    infos = socket.getaddrinfo(host, port, proto=socket.IPPROTO_TCP)
except socket.gaierror as exc:
    print(f"DNS lookup failed for {host}: {exc}", file=sys.stderr)
    raise SystemExit(1)

addresses = sorted({info[4][0] for info in infos})
if not addresses:
    print(f"DNS lookup returned no addresses for {host}", file=sys.stderr)
    raise SystemExit(1)
print("\n".join(addresses))
PY
)"
echo "dns=ok host=$URL_HOST addresses=$(echo "$DNS_ADDRESSES" | paste -sd ',' -)"

if [[ "$URL_SCHEME" == "https" ]]; then
  require_cmd openssl
  TLS_LOG="$(mktemp)"
  if ! openssl s_client \
    -connect "$URL_HOST:$URL_PORT" \
    -servername "$URL_HOST" \
    -verify_return_error \
    </dev/null >"$TLS_LOG" 2>&1; then
    echo "TLS certificate validation failed for $URL_HOST:$URL_PORT" >&2
    sed -n '1,120p' "$TLS_LOG" >&2
    rm -f "$TLS_LOG"
    exit 1
  fi
  rm -f "$TLS_LOG"
  echo "tls=ok host=$URL_HOST"
fi

request_json() {
  local method="$1"
  local label="$2"
  local path="$3"
  local response_file="$4"
  local url="$BASE_URL$path"
  local http_code

  if ! http_code="$(
    curl \
      --silent \
      --show-error \
      --location \
      --request "$method" \
      --connect-timeout "$TIMEOUT_SECONDS" \
      --max-time "$TIMEOUT_SECONDS" \
      --header "X-Kbo-Push-Sync-Secret: $SYNC_SECRET" \
      --output "$response_file" \
      --write-out '%{http_code}' \
      "$url"
  )"; then
    echo "endpoint=$label status=fail url=$url" >&2
    exit 1
  fi

  if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    echo "endpoint=$label status=fail http=$http_code url=$url" >&2
    sed -n '1,80p' "$response_file" >&2
    exit 1
  fi

  if ! python3 - "$response_file" "$label" <<'PY'
import json
import sys

path, label = sys.argv[1], sys.argv[2]
try:
    with open(path, "r", encoding="utf-8") as f:
        payload = json.load(f)
except Exception as exc:
    print(f"endpoint={label} status=fail reason=invalid-json detail={exc}", file=sys.stderr)
    raise SystemExit(1)

if isinstance(payload, dict) and payload.get("success") is False:
    print(f"endpoint={label} status=fail reason=api-envelope-false payload={payload}", file=sys.stderr)
    raise SystemExit(1)
PY
  then
    exit 1
  fi

  echo "endpoint=$label status=ok http=$http_code"
}

HEALTH_RESPONSE="$(mktemp)"
CONFIG_RESPONSE="$(mktemp)"
SYNC_RESPONSE="$(mktemp)"
trap 'rm -f "$HEALTH_RESPONSE" "$CONFIG_RESPONSE" "$SYNC_RESPONSE"' EXIT

request_json GET "/api/health" "/health" "$HEALTH_RESPONSE"
request_json GET "/api/push/config-status" "/push/config-status" "$CONFIG_RESPONSE"

python3 - "$CONFIG_RESPONSE" <<'PY'
import json
import sys

path = sys.argv[1]
payload = json.load(open(path, "r", encoding="utf-8"))
data = payload.get("data") if isinstance(payload, dict) else None
if not isinstance(data, dict):
    print("push_config=status=fail reason=missing-data", file=sys.stderr)
    raise SystemExit(1)

if data.get("readyForIphoneOnlyDemo") is not True:
    missing = data.get("missing") or []
    print(f"push_config=status=fail readyForIphoneOnlyDemo=false missing={missing}", file=sys.stderr)
    raise SystemExit(1)

print("push_config=status=ok readyForIphoneOnlyDemo=true")
PY

if [[ "$RUN_SYNC" == "true" ]]; then
  sync_path="/push/live-activity/sync-scoreboard"
  if [[ -n "$SYNC_DATE" ]]; then
    sync_path="$sync_path?date=$SYNC_DATE"
  fi
  request_json POST \
    "/api/push/live-activity/sync-scoreboard" \
    "$sync_path" \
    "$SYNC_RESPONSE"
  python3 - "$SYNC_RESPONSE" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], "r", encoding="utf-8"))
data = payload.get("data") if isinstance(payload, dict) else None
if not isinstance(data, dict):
    print("sync_scoreboard=status=fail reason=missing-data", file=sys.stderr)
    raise SystemExit(1)
print(
    "sync_scoreboard=status=ok "
    f"checkedGames={data.get('checkedGames')} "
    f"updatedGames={len(data.get('updatedGames') or [])} "
    f"pushedMoments={len(data.get('pushedMoments') or [])}"
)
PY
else
  echo "sync_scoreboard=skipped set PUSH_READINESS_RUN_SYNC=true to trigger one scoreboard sync"
fi

echo "Push readiness check passed."
