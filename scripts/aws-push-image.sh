#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${AWS_PUSH_OUTPUT_DIR:-$ROOT_DIR/outputs/aws/ecr}"
IMAGE_TAG="${KBO_BACKEND_IMAGE_TAG:-latest}"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage:
  AWS_REGION=<region> \
  ECR_REPOSITORY_URI=<account>.dkr.ecr.<region>.amazonaws.com/kbo-fans-backend \
  ./scripts/aws-push-image.sh

Options:
  --dry-run       Validate env and print the image URI without Docker/AWS calls.
  --tag <tag>     Override image tag. Default: KBO_BACKEND_IMAGE_TAG or latest.

Outputs:
  export ECR_REPOSITORY_URI=...
  export CONTAINER_IMAGE_URI=...
  outputs/aws/ecr/image.env
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --tag)
      if [[ -z "${2:-}" ]]; then
        echo "--tag requires a value." >&2
        exit 2
      fi
      IMAGE_TAG="$2"
      shift 2
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

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

if [[ -z "${AWS_REGION:-}" ]]; then
  echo "AWS_REGION is required." >&2
  exit 2
fi

if [[ -z "${ECR_REPOSITORY_URI:-}" ]]; then
  echo "ECR_REPOSITORY_URI is required." >&2
  exit 2
fi

repository_leaf="${ECR_REPOSITORY_URI##*/}"
if [[ "$repository_leaf" == *:* ]]; then
  echo "ECR_REPOSITORY_URI must not include an image tag. Use --tag or KBO_BACKEND_IMAGE_TAG instead." >&2
  exit 2
fi

registry="${ECR_REPOSITORY_URI%%/*}"
repository_name="${ECR_REPOSITORY_URI#*/}"
container_image_uri="$ECR_REPOSITORY_URI:$IMAGE_TAG"

mkdir -p "$OUTPUT_DIR"
env_file="$OUTPUT_DIR/image.env"
cat > "$env_file" <<EOF
export ECR_REPOSITORY_URI=$ECR_REPOSITORY_URI
export CONTAINER_IMAGE_URI=$container_image_uri
export KBO_BACKEND_IMAGE_TAG=$IMAGE_TAG
EOF

if [[ "$DRY_RUN" == "true" ]]; then
  echo "aws_push_image=status=ok mode=dry-run"
  echo "export ECR_REPOSITORY_URI=$ECR_REPOSITORY_URI"
  echo "export CONTAINER_IMAGE_URI=$container_image_uri"
  echo "$env_file"
  exit 0
fi

require_cmd aws
require_cmd docker

if ! aws ecr describe-repositories \
  --region "$AWS_REGION" \
  --repository-names "$repository_name" >/dev/null 2>&1; then
  aws ecr create-repository \
    --region "$AWS_REGION" \
    --repository-name "$repository_name" >/dev/null
fi

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$registry" >/dev/null

docker build -t kbo-fans-backend:"$IMAGE_TAG" "$ROOT_DIR/backend"
docker tag kbo-fans-backend:"$IMAGE_TAG" "$container_image_uri"
docker push "$container_image_uri"

echo "aws_push_image=status=ok mode=push"
echo "export ECR_REPOSITORY_URI=$ECR_REPOSITORY_URI"
echo "export CONTAINER_IMAGE_URI=$container_image_uri"
echo "$env_file"
