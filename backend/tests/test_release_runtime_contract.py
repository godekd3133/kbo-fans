from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def _read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def test_aws_runtime_templates_inject_kbo_relay_credentials() -> None:
    required_tokens = [
        "KBO_RELAY_USER_ID",
        "KBO_RELAY_PASSWORD",
        "SECRET_ARN_KBO_RELAY_USER_ID",
        "SECRET_ARN_KBO_RELAY_PASSWORD",
    ]
    template_paths = [
        "infra/aws/ecs-fargate/task-definition-api.json",
        "infra/aws/ecs-fargate/task-definition-sync-worker.json",
        "infra/aws/ecs-fargate/iam-task-execution-secrets-policy.json",
        "infra/aws/ecs-fargate/render_task_definitions.py",
    ]

    for path in template_paths:
        body = _read(path)
        for token in required_tokens:
            assert token in body, f"{path} missing {token}"


def test_aws_secret_and_deploy_scripts_require_kbo_relay_credentials() -> None:
    required_tokens = [
        "KBO_RELAY_USER_ID",
        "KBO_RELAY_PASSWORD",
        "SECRET_ARN_KBO_RELAY_USER_ID",
        "SECRET_ARN_KBO_RELAY_PASSWORD",
    ]
    script_paths = [
        "scripts/aws-push-secrets.sh",
        "scripts/aws-push-deploy-check.sh",
        "scripts/aws-push-cloudformation.sh",
        "scripts/push-live-preflight.sh",
    ]

    for path in script_paths:
        body = _read(path)
        for token in required_tokens:
            assert token in body, f"{path} missing {token}"


def test_release_health_gate_checks_relay_endpoint() -> None:
    body = _read("scripts/release-api-health-check.sh")

    assert "gameId" in body
    assert "/relay" in body
