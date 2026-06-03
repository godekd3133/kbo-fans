from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path
from typing import Optional

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]
DEFAULT_OUTPUT_DIR = REPO_ROOT / "outputs" / "aws" / "ecs-fargate"

TEMPLATES = {
    "iam-task-execution-secrets-policy.json": (
        "iam-task-execution-secrets-policy.rendered.json"
    ),
    "task-definition-api.json": "task-definition-api.rendered.json",
    "task-definition-sync-worker.json": "task-definition-sync-worker.rendered.json",
}

PLACEHOLDER_ENV = {
    "AWS_REGION": "AWS_REGION",
    "ECR_REPOSITORY_URI": "ECR_REPOSITORY_URI",
    "ECS_TASK_EXECUTION_ROLE_ARN": "ECS_TASK_EXECUTION_ROLE_ARN",
    "ECS_TASK_ROLE_ARN": "ECS_TASK_ROLE_ARN",
    "EFS_FILE_SYSTEM_ID": "EFS_FILE_SYSTEM_ID",
    "FIREBASE_PROJECT_ID": "FIREBASE_PROJECT_ID",
    "APNS_KEY_ID": "APNS_KEY_ID",
    "APNS_TEAM_ID": "APNS_TEAM_ID",
    "SECRET_ARN_FIREBASE_SERVICE_ACCOUNT_JSON": (
        "SECRET_ARN_FIREBASE_SERVICE_ACCOUNT_JSON"
    ),
    "SECRET_ARN_APNS_AUTH_KEY_P8": "SECRET_ARN_APNS_AUTH_KEY_P8",
    "SECRET_ARN_PUSH_SYNC_SECRET": "SECRET_ARN_PUSH_SYNC_SECRET",
}

UNRESOLVED_PLACEHOLDER_PATTERN = re.compile(r"<[A-Z0-9_]+>")


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Render AWS ECS/Fargate deployment templates for KBO Fans push demo."
        )
    )
    parser.add_argument(
        "--output-dir",
        default=str(DEFAULT_OUTPUT_DIR),
        help="Directory for rendered AWS deployment JSON files.",
    )
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Validate required environment and rendered JSON without writing files.",
    )
    args = parser.parse_args(argv)

    replacements = _load_replacements()
    output_dir = Path(args.output_dir)
    if not args.validate_only:
        output_dir.mkdir(parents=True, exist_ok=True)

    rendered_files = []
    for template_name, output_name in TEMPLATES.items():
        rendered = _render_template(SCRIPT_DIR / template_name, replacements)
        payload = json.loads(rendered)
        normalized = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=False)

        if not args.validate_only:
            output_path = output_dir / output_name
            output_path.write_text(f"{normalized}\n", encoding="utf-8")
            rendered_files.append(str(output_path))

    if args.validate_only:
        print("aws_ecs_templates=status=ok mode=validate-only")
    else:
        print("aws_ecs_templates=status=ok")
        for path in rendered_files:
            print(path)
    return 0


def _load_replacements() -> dict[str, str]:
    missing = [
        env_name for env_name in PLACEHOLDER_ENV.values() if not os.getenv(env_name)
    ]
    if missing:
        print("Missing required environment variables:")
        for name in missing:
            print(f"  - {name}")
        raise SystemExit(2)

    return {
        f"<{placeholder}>": os.environ[env_name]
        for placeholder, env_name in PLACEHOLDER_ENV.items()
    }


def _render_template(path: Path, replacements: dict[str, str]) -> str:
    rendered = path.read_text(encoding="utf-8")
    for placeholder, value in replacements.items():
        rendered = rendered.replace(placeholder, value)

    unresolved = _unresolved_placeholders(rendered)
    if unresolved:
        names = ", ".join(sorted(unresolved))
        raise SystemExit(f"{path.name} has unresolved placeholders: {names}")

    try:
        json.loads(rendered)
    except json.JSONDecodeError as error:
        raise SystemExit(f"{path.name} rendered invalid JSON: {error}") from error

    return rendered


def _unresolved_placeholders(rendered: str) -> set[str]:
    return set(UNRESOLVED_PLACEHOLDER_PATTERN.findall(rendered))


if __name__ == "__main__":
    raise SystemExit(main())
