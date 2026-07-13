#!/usr/bin/env bash

set -euo pipefail

BASE_URL="${PUSH_API_BASE_URL:-${API_BASE_URL:-${RELEASE_API_BASE_URL:-https://3-39-79-1.sslip.io/api}}}"
BASE_URL="${BASE_URL%/}"
SYNC_SECRET="${PUSH_SYNC_SECRET:-}"
TITLE="${PUSH_TEST_TITLE:-KBO Fans Test}"
BODY="${PUSH_TEST_BODY:-Push delivery test}"
TOPIC="${PUSH_TEST_TOPIC:-}"
TOKEN="${PUSH_TEST_TOKEN:-}"
TIMEOUT_SECONDS="${PUSH_TEST_TIMEOUT_SECONDS:-20}"
ALLOW_INSECURE="${ALLOW_INSECURE_PUSH_TEST:-false}"

usage() {
  cat <<'EOF'
Send one visible FCM test notification through the KBO Fans backend.

Usage:
  PUSH_SYNC_SECRET=<secret> ./scripts/push-test-notification.sh --topic game_start_LG
  PUSH_SYNC_SECRET=<secret> ./scripts/push-test-notification.sh --token <fcm-token>

Options:
  --base-url <url>   API base URL. Defaults to PUSH_API_BASE_URL, API_BASE_URL,
                     RELEASE_API_BASE_URL, then https://3-39-79-1.sslip.io/api.
  --topic <topic>    FCM topic target. Mutually exclusive with --token.
  --token <token>    FCM device token target. Mutually exclusive with --topic.
  --title <text>     Notification title. Defaults to "KBO Fans Test".
  --body <text>      Notification body. Defaults to "Push delivery test".
  --help             Show this help.

For temporary HTTP smoke backends only, set ALLOW_INSECURE_PUSH_TEST=true.
This script never prints PUSH_SYNC_SECRET or device tokens.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

is_truthy() {
  case "$1" in
    1 | true | TRUE | True | yes | YES | Yes)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)
      BASE_URL="${2:-}"
      shift 2
      ;;
    --topic)
      TOPIC="${2:-}"
      shift 2
      ;;
    --token)
      TOKEN="${2:-}"
      shift 2
      ;;
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --body)
      BODY="${2:-}"
      shift 2
      ;;
    --help | -h)
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

BASE_URL="${BASE_URL%/}"

require_cmd curl
require_cmd python3

if [[ -z "$BASE_URL" ]]; then
  echo "Push API base URL is empty." >&2
  exit 1
fi

if [[ -z "$SYNC_SECRET" ]]; then
  cat >&2 <<'EOF'
PUSH_SYNC_SECRET is required to send a test push.

Usage:
  PUSH_SYNC_SECRET=<secret> ./scripts/push-test-notification.sh --topic game_start_LG
EOF
  exit 1
fi

if [[ -n "$TOPIC" && -n "$TOKEN" ]]; then
  echo "Use only one of --topic or --token." >&2
  exit 1
fi

if [[ -z "$TOPIC" && -z "$TOKEN" ]]; then
  echo "One target is required: --topic or --token." >&2
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
print(parsed.scheme, parsed.hostname)
PY
)"
read -r URL_SCHEME URL_HOST <<< "$URL_PARTS"

if [[ "$URL_SCHEME" != "https" ]] && ! is_truthy "$ALLOW_INSECURE"; then
  cat >&2 <<EOF
Push test must use HTTPS unless this is a temporary HTTP smoke backend.

Current:
  $BASE_URL

Set ALLOW_INSECURE_PUSH_TEST=true only for the current AWS HTTP smoke endpoint.
EOF
  exit 1
fi

REQUEST_BODY="$(
  python3 - "$TITLE" "$BODY" "$TOPIC" "$TOKEN" <<'PY'
import json
import sys

title, body, topic, token = sys.argv[1:5]
payload = {"title": title, "body": body}
if topic:
    payload["topic"] = topic
if token:
    payload["token"] = token
print(json.dumps(payload, ensure_ascii=False))
PY
)"

RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$RESPONSE_FILE"' EXIT

if [[ -n "$TOPIC" ]]; then
  echo "push_test_target=topic:$TOPIC"
else
  echo "push_test_target=token:<redacted>"
fi
echo "push_test_base_url=$BASE_URL"

HTTP_CODE="$(
  curl \
    --silent \
    --show-error \
    --location \
    --request POST \
    --connect-timeout "$TIMEOUT_SECONDS" \
    --max-time "$TIMEOUT_SECONDS" \
    --header 'Content-Type: application/json' \
    --header "X-Kbo-Push-Sync-Secret: $SYNC_SECRET" \
    --data "$REQUEST_BODY" \
    --output "$RESPONSE_FILE" \
    --write-out '%{http_code}' \
    "$BASE_URL/push/test"
)"

if [[ ! "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
  echo "push_test_status=fail http=$HTTP_CODE" >&2
  python3 - "$RESPONSE_FILE" <<'PY' >&2
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        payload = json.load(f)
except Exception:
    print("response=<non-json>")
else:
    if isinstance(payload, dict):
        payload.pop("deviceToken", None)
        payload.pop("token", None)
    print(json.dumps(payload, ensure_ascii=False))
PY
  exit 1
fi

python3 - "$RESPONSE_FILE" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)

data = payload.get("data") if isinstance(payload, dict) else None
if not isinstance(data, dict):
    print("push_test_status=fail reason=missing-data")
    raise SystemExit(1)

print(f"push_test_status=ok sent={data.get('sent')}")
print(f"push_test_message_id={data.get('messageId', '')}")
print(f"push_test_target_response={data.get('target', '')}")
PY
