#!/usr/bin/env bash

set -euo pipefail

BASE_URL="${PUSH_API_BASE_URL:-${API_BASE_URL:-${RELEASE_API_BASE_URL:-https://api.kbofans.com/api}}}"
BASE_URL="${BASE_URL%/}"
SYNC_SECRET="${PUSH_SYNC_SECRET:-}"
TIMEOUT_SECONDS="${PUSH_RECEIPT_STATUS_TIMEOUT_SECONDS:-20}"
ALLOW_INSECURE="${ALLOW_INSECURE_PUSH_RECEIPT_STATUS:-false}"
EXPECT_RECEIPT=false
FILTER_GAME_ID="${PUSH_RECEIPT_GAME_ID:-}"
FILTER_TYPE="${PUSH_RECEIPT_TYPE:-}"
FILTER_SOURCE="${PUSH_RECEIPT_SOURCE:-}"
FILTER_SINCE="${PUSH_RECEIPT_SINCE:-}"

usage() {
  cat <<'EOF'
Inspect recent remote push receipts recorded by the KBO Fans backend.

Usage:
  PUSH_SYNC_SECRET=<secret> ./scripts/push-receipt-status.sh
  PUSH_SYNC_SECRET=<secret> ./scripts/push-receipt-status.sh --expect-receipt --game-id GAME_20260620HTKT0 --type hit

Options:
  --base-url <url>       API base URL. Defaults to PUSH_API_BASE_URL, API_BASE_URL,
                         RELEASE_API_BASE_URL, then https://api.kbofans.com/api.
  --expect-receipt       Exit non-zero when no recent receipt matches filters.
  --game-id <gameId>     Match a specific receipt gameId.
  --type <type>          Match a specific receipt type, such as hit or scoring.
  --source <source>      Match a receipt source, such as foreground or opened.
  --since <iso-time>     Match receipts received/recorded at or after this time.
  --allow-insecure bool  Allow temporary HTTP smoke backend. Default: false.
  --help                 Show this help.

This script never prints PUSH_SYNC_SECRET or raw device tokens.
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
    --expect-receipt)
      EXPECT_RECEIPT=true
      shift
      ;;
    --game-id)
      FILTER_GAME_ID="${2:-}"
      shift 2
      ;;
    --type)
      FILTER_TYPE="${2:-}"
      shift 2
      ;;
    --source)
      FILTER_SOURCE="${2:-}"
      shift 2
      ;;
    --since)
      FILTER_SINCE="${2:-}"
      shift 2
      ;;
    --allow-insecure)
      ALLOW_INSECURE="${2:-}"
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
PUSH_SYNC_SECRET is required to inspect push receipt status.

Usage:
  PUSH_SYNC_SECRET=<secret> ./scripts/push-receipt-status.sh
EOF
  exit 1
fi

case "$ALLOW_INSECURE" in
  true | false | TRUE | FALSE | True | False | 1 | 0 | yes | no | YES | NO | Yes | No) ;;
  *)
    echo "--allow-insecure must be true or false." >&2
    exit 2
    ;;
esac

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
Push receipt status must use HTTPS unless this is a temporary HTTP smoke backend.

Current:
  $BASE_URL

Set ALLOW_INSECURE_PUSH_RECEIPT_STATUS=true or pass --allow-insecure true only for the current AWS HTTP smoke endpoint.
EOF
  exit 1
fi

RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$RESPONSE_FILE"' EXIT

HTTP_CODE="$(
  curl \
    --silent \
    --show-error \
    --location \
    --request GET \
    --connect-timeout "$TIMEOUT_SECONDS" \
    --max-time "$TIMEOUT_SECONDS" \
    --header "X-Kbo-Push-Sync-Secret: $SYNC_SECRET" \
    --output "$RESPONSE_FILE" \
    --write-out '%{http_code}' \
    "$BASE_URL/push/config-status"
)"

if [[ ! "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
  echo "push_receipts=status=fail http=$HTTP_CODE base_url=$BASE_URL" >&2
  sed -n '1,80p' "$RESPONSE_FILE" >&2
  exit 1
fi

python3 - \
  "$RESPONSE_FILE" \
  "$EXPECT_RECEIPT" \
  "$FILTER_GAME_ID" \
  "$FILTER_TYPE" \
  "$FILTER_SOURCE" \
  "$FILTER_SINCE" <<'PY'
from __future__ import annotations

from datetime import datetime, timezone
import json
import sys
from typing import Any

path, expect_raw, game_id_filter, type_filter, source_filter, since_raw = sys.argv[1:7]

try:
    with open(path, "r", encoding="utf-8") as file:
        payload = json.load(file)
except Exception as exc:
    print(f"push_receipts=status=fail reason=invalid-json detail={exc}", file=sys.stderr)
    raise SystemExit(1)

if isinstance(payload, dict) and payload.get("success") is False:
    print("push_receipts=status=fail reason=api-envelope-false", file=sys.stderr)
    raise SystemExit(1)

data = payload.get("data") if isinstance(payload, dict) else None
if not isinstance(data, dict):
    print("push_receipts=status=fail reason=missing-data", file=sys.stderr)
    raise SystemExit(1)

registry = data.get("registry") if isinstance(data.get("registry"), dict) else {}
receipts = registry.get("recentPushReceipts")
if not isinstance(receipts, list):
    receipts = []

print(
    "push_receipts=status=ok "
    f"count={registry.get('pushReceiptCount', len(receipts))} "
    f"recent={len(receipts)} "
    f"registeredDevices={registry.get('registeredDeviceCount')} "
    f"followedGames={registry.get('followedGameCount')}"
)

since = None
if since_raw:
    try:
        since = datetime.fromisoformat(since_raw.replace("Z", "+00:00"))
    except ValueError:
        print(f"push_receipt_match=status=fail reason=invalid-since value={since_raw}", file=sys.stderr)
        raise SystemExit(1)
    if since.tzinfo is None:
        since = since.replace(tzinfo=timezone.utc)


def text(value: Any) -> str:
    return str(value or "").strip()


def receipt_time(receipt: dict[str, Any]) -> datetime | None:
    raw = text(receipt.get("receivedAt")) or text(receipt.get("recordedAt"))
    if not raw:
        return None
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def matches(receipt: dict[str, Any]) -> bool:
    if game_id_filter and text(receipt.get("gameId")) != game_id_filter:
        return False
    if type_filter and text(receipt.get("type")) != type_filter:
        return False
    if source_filter and text(receipt.get("source")) != source_filter:
        return False
    if since is not None:
        observed = receipt_time(receipt)
        if observed is None or observed < since:
            return False
    return True


match_count = 0
for index, receipt in enumerate(receipts):
    if not isinstance(receipt, dict):
        continue
    if matches(receipt):
        match_count += 1
    data_payload = receipt.get("data") if isinstance(receipt.get("data"), dict) else {}
    safe_topic = text(data_payload.get("topic"))
    safe_kind = text(data_payload.get("kind"))
    safe_collapse_key = text(data_payload.get("collapseKey"))
    print(
        f"recent_receipt[{index}]="
        f"source={text(receipt.get('source')) or '-'} "
        f"type={text(receipt.get('type')) or '-'} "
        f"gameId={text(receipt.get('gameId')) or '-'} "
        f"route={text(receipt.get('route')) or '-'} "
        f"messageId={text(receipt.get('messageId')) or '-'} "
        f"deviceTokenSuffix={text(receipt.get('deviceTokenSuffix')) or '-'} "
        f"platform={text(receipt.get('platform')) or '-'} "
        f"myTeam={text(receipt.get('myTeam')) or '-'} "
        f"receivedAt={text(receipt.get('receivedAt')) or '-'} "
        f"recordedAt={text(receipt.get('recordedAt')) or '-'} "
        f"topic={safe_topic or '-'} "
        f"kind={safe_kind or '-'} "
        f"collapseKey={safe_collapse_key or '-'}"
    )

if expect_raw == "true":
    if match_count < 1:
        print(
            "push_receipt_match=status=missing "
            f"gameId={game_id_filter or '*'} "
            f"type={type_filter or '*'} "
            f"source={source_filter or '*'} "
            f"since={since_raw or '*'}",
            file=sys.stderr,
        )
        raise SystemExit(1)
    print(f"push_receipt_match=status=ok matches={match_count}")
else:
    print(f"push_receipt_match=status=not-required matches={match_count}")
PY
