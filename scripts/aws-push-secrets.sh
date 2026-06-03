#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${AWS_PUSH_OUTPUT_DIR:-$ROOT_DIR/outputs/aws/ecs-fargate}"
SECRET_PREFIX="${AWS_PUSH_SECRET_PREFIX:-/kbo-fans}"
FIREBASE_SECRET_NAME="${FIREBASE_SECRET_NAME:-$SECRET_PREFIX/firebase-service-account-json}"
APNS_SECRET_NAME="${APNS_SECRET_NAME:-$SECRET_PREFIX/apns-auth-key-p8}"
SYNC_SECRET_NAME="${SYNC_SECRET_NAME:-$SECRET_PREFIX/push-sync-secret}"
DRY_RUN=false
WRITE_ENV_FILE=true

usage() {
  cat <<'EOF'
Usage:
  AWS_REGION=<region> \
  FIREBASE_SERVICE_ACCOUNT_FILE=/path/firebase-service-account.json \
  APNS_AUTH_KEY_FILE=/path/AuthKey_XXXX.p8 \
  ./scripts/aws-push-secrets.sh

Optional:
  PUSH_SYNC_SECRET=<secret>        Use an existing sync secret. Otherwise generated.
  AWS_PUSH_SECRET_PREFIX=/kbo-fans Secret path prefix.
  AWS_PUSH_OUTPUT_DIR=outputs/aws/ecs-fargate
  --dry-run                       Validate inputs without calling AWS.
  --no-env-file                   Do not write outputs/aws/ecs-fargate/secrets.env.

Outputs:
  export SECRET_ARN_FIREBASE_SERVICE_ACCOUNT_JSON=...
  export SECRET_ARN_APNS_AUTH_KEY_P8=...
  export SECRET_ARN_PUSH_SYNC_SECRET=...
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
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --no-env-file)
      WRITE_ENV_FILE=false
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

require_cmd python3
if [[ "$DRY_RUN" != "true" ]]; then
  require_cmd aws
fi

if [[ -z "${AWS_REGION:-}" ]]; then
  echo "AWS_REGION is required." >&2
  exit 2
fi

if [[ -z "${FIREBASE_SERVICE_ACCOUNT_FILE:-}" ]]; then
  echo "FIREBASE_SERVICE_ACCOUNT_FILE is required." >&2
  exit 2
fi

if [[ -z "${APNS_AUTH_KEY_FILE:-}" ]]; then
  echo "APNS_AUTH_KEY_FILE is required." >&2
  exit 2
fi

python3 - "$FIREBASE_SERVICE_ACCOUNT_FILE" "$APNS_AUTH_KEY_FILE" <<'PY'
import json
import sys
from pathlib import Path

firebase_path = Path(sys.argv[1]).expanduser()
apns_path = Path(sys.argv[2]).expanduser()

if not firebase_path.is_file():
    print(f"Firebase service account file not found: {firebase_path}", file=sys.stderr)
    raise SystemExit(2)

try:
    firebase = json.loads(firebase_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"Firebase service account JSON is invalid: {exc}", file=sys.stderr)
    raise SystemExit(2)

required = {"type", "project_id", "private_key", "client_email"}
missing = sorted(required - set(firebase))
if missing:
    print(
        "Firebase service account JSON missing fields: " + ", ".join(missing),
        file=sys.stderr,
    )
    raise SystemExit(2)

if not apns_path.is_file():
    print(f"APNs auth key file not found: {apns_path}", file=sys.stderr)
    raise SystemExit(2)

apns = apns_path.read_text(encoding="utf-8").strip()
if "BEGIN PRIVATE KEY" not in apns or "END PRIVATE KEY" not in apns:
    print("APNs auth key file does not look like a .p8 private key.", file=sys.stderr)
    raise SystemExit(2)
PY

if [[ -z "${PUSH_SYNC_SECRET:-}" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    PUSH_SYNC_SECRET="$(openssl rand -hex 32)"
  else
    PUSH_SYNC_SECRET="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
)"
  fi
fi

put_secret() {
  local name="$1"
  local value="$2"
  local description="$3"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "arn:aws:secretsmanager:${AWS_REGION}:000000000000:secret:${name#/}-dry-run"
    return
  fi

  local arn
  if arn="$(aws secretsmanager describe-secret \
    --region "$AWS_REGION" \
    --secret-id "$name" \
    --query ARN \
    --output text 2>/dev/null)"; then
    aws secretsmanager put-secret-value \
      --region "$AWS_REGION" \
      --secret-id "$name" \
      --secret-string "$value" >/dev/null
    echo "$arn"
    return
  fi

  aws secretsmanager create-secret \
    --region "$AWS_REGION" \
    --name "$name" \
    --description "$description" \
    --secret-string "$value" \
    --query ARN \
    --output text
}

FIREBASE_JSON="$(python3 - "$FIREBASE_SERVICE_ACCOUNT_FILE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1]).expanduser()
payload = json.loads(path.read_text(encoding="utf-8"))
print(json.dumps(payload, separators=(",", ":")))
PY
)"
APNS_P8="$(python3 - "$APNS_AUTH_KEY_FILE" <<'PY'
import sys
from pathlib import Path

print(Path(sys.argv[1]).expanduser().read_text(encoding="utf-8"))
PY
)"

FIREBASE_ARN="$(put_secret \
  "$FIREBASE_SECRET_NAME" \
  "$FIREBASE_JSON" \
  "KBO Fans Firebase Admin service account JSON")"
APNS_ARN="$(put_secret \
  "$APNS_SECRET_NAME" \
  "$APNS_P8" \
  "KBO Fans Apple APNs Auth Key .p8 content")"
SYNC_ARN="$(put_secret \
  "$SYNC_SECRET_NAME" \
  "$PUSH_SYNC_SECRET" \
  "KBO Fans push scheduler sync secret")"

mkdir -p "$OUTPUT_DIR"
ENV_FILE="$OUTPUT_DIR/secrets.env"
if [[ "$WRITE_ENV_FILE" == "true" ]]; then
  cat > "$ENV_FILE" <<EOF
export SECRET_ARN_FIREBASE_SERVICE_ACCOUNT_JSON=$FIREBASE_ARN
export SECRET_ARN_APNS_AUTH_KEY_P8=$APNS_ARN
export SECRET_ARN_PUSH_SYNC_SECRET=$SYNC_ARN
EOF
fi

echo "aws_push_secrets=status=ok dry_run=$DRY_RUN"
echo "export SECRET_ARN_FIREBASE_SERVICE_ACCOUNT_JSON=$FIREBASE_ARN"
echo "export SECRET_ARN_APNS_AUTH_KEY_P8=$APNS_ARN"
echo "export SECRET_ARN_PUSH_SYNC_SECRET=$SYNC_ARN"
if [[ "$WRITE_ENV_FILE" == "true" ]]; then
  echo "$ENV_FILE"
fi
