#!/usr/bin/env bash

set -euo pipefail

BASE_URL="${1:-${RELEASE_API_BASE_URL:-${API_BASE_URL:-https://api.kbofans.com/api}}}"
BASE_URL="${BASE_URL%/}"
TIMEOUT_SECONDS="${RELEASE_API_HEALTH_TIMEOUT_SECONDS:-20}"
TODAY="${RELEASE_API_HEALTH_DATE:-$(date +%Y-%m-%d)}"
MONTH="${RELEASE_API_HEALTH_MONTH:-$(date +%Y-%m)}"
SEASON="${RELEASE_API_HEALTH_SEASON:-$(date +%Y)}"
ALLOW_INSECURE="${ALLOW_INSECURE_RELEASE_API:-false}"

if [[ -z "$BASE_URL" ]]; then
  echo "Release API base URL is empty." >&2
  exit 1
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd python3
require_cmd curl

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
Release API must use HTTPS.

Current:
  $BASE_URL

For local script testing only, set ALLOW_INSECURE_RELEASE_API=true.
EOF
  exit 1
fi

echo "Release API health gate"
echo "base_url=$BASE_URL"
echo "date=$TODAY month=$MONTH season=$SEASON"

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

check_endpoint() {
  local label="$1"
  local path="$2"
  local url="$BASE_URL$path"
  local response_file
  local http_code

  response_file="$(mktemp)"
  if ! http_code="$(
    curl \
      --silent \
      --show-error \
      --location \
      --connect-timeout "$TIMEOUT_SECONDS" \
      --max-time "$TIMEOUT_SECONDS" \
      --output "$response_file" \
      --write-out '%{http_code}' \
      "$url"
  )"; then
    echo "endpoint=$label status=fail url=$url" >&2
    rm -f "$response_file"
    exit 1
  fi

  if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    echo "endpoint=$label status=fail http=$http_code url=$url" >&2
    sed -n '1,80p' "$response_file" >&2
    rm -f "$response_file"
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
    rm -f "$response_file"
    exit 1
  fi

  rm -f "$response_file"
  echo "endpoint=$label status=ok http=$http_code"
}

check_endpoint "/api/health" "/health"
check_endpoint "/api/scoreboard/home" "/scoreboard/home?date=$TODAY"
check_endpoint "/api/home" "/home?date=$TODAY"
check_endpoint "/api/schedule" "/schedule?month=$MONTH"
check_endpoint "/api/standings" "/standings?season=$SEASON"
check_endpoint "/api/records/overview" "/records/overview?season=$SEASON"

echo "Release API health gate passed."
