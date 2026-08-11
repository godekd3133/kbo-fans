import json
import os
import subprocess
from pathlib import Path

import kbo_fans_backend.core.config as config_module
from kbo_fans_backend.storage import JsonSnapshotStore

ROOT = Path(__file__).resolve().parents[2]
ACTIVE_RELEASE_API_URL = "https://3-39-79-1.sslip.io/api"
LIGHTSAIL_RELEASE_SEED_DIR = "/opt/kbo-fans/current/backend/data/snapshots"


def _read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def test_backend_image_packages_seed_snapshots_but_excludes_mutable_runtime() -> None:
    dockerfile = _read("backend/Dockerfile")
    dockerignore_lines = {
        line.strip()
        for line in _read("backend/.dockerignore").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }

    assert "COPY data/snapshots ./data/snapshots" in dockerfile
    assert "COPY data/runtime" not in dockerfile
    assert "data/runtime/" in dockerignore_lines
    assert "data/snapshots/" not in dockerignore_lines
    seed_root = ROOT / "backend/data/snapshots"
    assert seed_root.is_dir()
    assert next(seed_root.rglob("*.json"), None) is not None


def test_lightsail_rolling_release_reads_new_seed_without_overwriting_runtime(
    tmp_path: Path,
    monkeypatch,
) -> None:
    seed_environment = f"Environment=SNAPSHOT_SEED_DIR={LIGHTSAIL_RELEASE_SEED_DIR}"
    for service_path in [
        "infra/aws/lightsail/systemd/kbo-fans-api.service",
        "infra/aws/lightsail/systemd/kbo-fans-sync-worker.service",
    ]:
        assert seed_environment in _read(service_path)

    env_lines = {
        line.strip()
        for line in _read("infra/aws/lightsail/env.example").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }
    assert f"SNAPSHOT_SEED_DIR={LIGHTSAIL_RELEASE_SEED_DIR}" in env_lines

    deploy_script = _read("scripts/lightsail-deploy.sh")
    assert 'cp -a "$APP_DIR/current/backend/data/snapshots/."' not in deploy_script

    runtime_dir = tmp_path / "runtime"
    release_seed_dir = tmp_path / "releases" / "next" / "backend" / "data" / "snapshots"
    runtime_store = JsonSnapshotStore(base_dir=str(runtime_dir))
    runtime_store.save("standings_latest", "2025", {"source": "runtime"})
    release_store = JsonSnapshotStore(base_dir=str(release_seed_dir))
    release_store.save("standings_latest", "2026", {"source": "new-release-seed"})
    runtime_path = runtime_dir / "standings_latest" / "2025.json"
    runtime_before = runtime_path.read_bytes()

    monkeypatch.setenv("SNAPSHOT_DIR", str(runtime_dir))
    monkeypatch.setenv("SNAPSHOT_SEED_DIR", str(release_seed_dir))
    config_module.get_settings.cache_clear()
    try:
        deployed_store = JsonSnapshotStore()

        assert deployed_store.load_payload("standings_latest", "2025") == {"source": "runtime"}
        assert deployed_store.load_payload("standings_latest", "2026") == {
            "source": "new-release-seed"
        }
        assert runtime_path.read_bytes() == runtime_before
        assert not (runtime_dir / "standings_latest" / "2026.json").exists()
    finally:
        config_module.get_settings.cache_clear()


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
    assert "TZ=Asia/Seoul date +%Y-%m-%d" in body
    assert "TZ=Asia/Seoul date +%Y-%m" in body
    assert "TZ=Asia/Seoul date +%Y" in body


def test_cloudformation_task_runtime_fields_match_ecs_templates() -> None:
    stack = json.loads(_read("infra/aws/cloudformation/push-demo-stack.json"))
    resources = stack["Resources"]

    pairs = [
        ("task-definition-api.json", "ApiTaskDefinition"),
        ("task-definition-sync-worker.json", "SyncWorkerTaskDefinition"),
    ]
    for template_name, resource_name in pairs:
        template = json.loads(_read(f"infra/aws/ecs-fargate/{template_name}"))
        template_container = template["containerDefinitions"][0]
        stack_container = resources[resource_name]["Properties"]["ContainerDefinitions"][0]

        template_env = {item["name"] for item in template_container["environment"]}
        stack_env_by_name = {item["Name"]: item["Value"] for item in stack_container["Environment"]}
        template_env_by_name = {
            item["name"]: item["value"] for item in template_container["environment"]
        }
        assert stack_env_by_name["SNAPSHOT_DIR"] == "/var/lib/kbo-fans/snapshots"
        assert template_env_by_name["SNAPSHOT_DIR"] == "/var/lib/kbo-fans/snapshots"
        stack_env = set(stack_env_by_name)
        assert stack_env == template_env, (
            f"{resource_name} environment drift: "
            f"missing={sorted(template_env - stack_env)}, "
            f"extra={sorted(stack_env - template_env)}"
        )

        template_secrets = {item["name"] for item in template_container["secrets"]}
        stack_secrets = {item["Name"] for item in stack_container["Secrets"]}
        assert stack_secrets == template_secrets, (
            f"{resource_name} secret drift: "
            f"missing={sorted(template_secrets - stack_secrets)}, "
            f"extra={sorted(stack_secrets - template_secrets)}"
        )

    assert "PushBaseballInfoSmartDailyTimes" in stack["Parameters"]
    deploy_script = _read("scripts/aws-push-cloudformation.sh")
    assert 'PushBaseballInfoSmartDailyTimes="${PUSH_BASEBALL_INFO_SMART_DAILY_TIMES:-' in (
        deploy_script
    )


def test_codex_run_help_succeeds() -> None:
    subprocess.run(
        ["bash", "scripts/codex-run.sh", "--help"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )


def test_android_local_api_url_distinguishes_emulator_and_device() -> None:
    script = r"""
source scripts/codex-run.sh
android_serial_is_emulator() { [[ "$1" == emulator-* ]]; }
local_backend_api_url_for_android_emulator() { echo emulator-url; }
local_backend_api_url_for_lan() { echo physical-url; }
[[ "$(local_backend_api_url_for_android_serial emulator-5554 '')" == emulator-url ]]
[[ "$(local_backend_api_url_for_android_serial physical-123 '')" == physical-url ]]
"""
    subprocess.run(
        ["bash", "-c", script],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )


def test_ios_simulator_detection_is_not_broken_by_pipefail() -> None:
    script = r"""
source scripts/codex-run.sh
xcrun() {
  local i
  for ((i = 0; i < 10000; i++)); do
    printf 'device (available)\n'
  done
}
has_ios_simulator
"""
    subprocess.run(
        ["bash", "-c", script],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )


def test_ios_simulator_ci_uses_supported_debug_mode() -> None:
    workflow = _read(".github/workflows/app-build-artifacts.yml")
    assert "flutter build ios --simulator --release" not in workflow
    assert "flutter build ios --simulator --debug --no-codesign" in workflow


def test_runtime_release_fallbacks_use_active_https_endpoint() -> None:
    runtime_paths = [
        "app/lib/core/config/api_endpoints.dart",
        ".github/workflows/app-build-artifacts.yml",
        "scripts/codex-run.sh",
        "scripts/release-api-health-check.sh",
        "scripts/push-readiness-check.sh",
        "scripts/push-test-notification.sh",
        "scripts/push-receipt-status.sh",
    ]

    for path in runtime_paths:
        body = _read(path)
        assert ACTIVE_RELEASE_API_URL in body, f"{path} missing active release API URL"
        assert "https://api.kbofans.com/api" not in body, (
            f"{path} still contains unresolved custom-domain fallback"
        )


def test_codex_release_default_does_not_read_stale_stack_output() -> None:
    script = f"""
source scripts/codex-run.sh
unset RELEASE_API_BASE_URL API_BASE_URL
[[ "$(release_api_base_url)" == "{ACTIVE_RELEASE_API_URL}" ]]
"""
    subprocess.run(
        ["bash", "-c", script],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )


def test_aws_image_dry_run_does_not_write_output_state(tmp_path: Path) -> None:
    output_dir = tmp_path / "image-output"
    env = {
        **os.environ,
        "AWS_REGION": "ap-northeast-2",
        "ECR_REPOSITORY_URI": "example.invalid/kbo-fans-backend",
        "AWS_PUSH_OUTPUT_DIR": str(output_dir),
    }

    subprocess.run(
        ["bash", "scripts/aws-push-image.sh", "--dry-run"],
        cwd=ROOT,
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )

    assert not output_dir.exists()


def test_aws_secrets_dry_run_does_not_write_output_state(tmp_path: Path) -> None:
    firebase_file = tmp_path / "firebase.json"
    firebase_file.write_text(
        json.dumps(
            {
                "type": "service_account",
                "project_id": "test-project",
                "private_key": "test-private-key",
                "client_email": "test@example.invalid",
            }
        ),
        encoding="utf-8",
    )
    apns_file = tmp_path / "AuthKey_TEST.p8"
    private_key_marker = "BEGIN " + "PRIVATE KEY"
    private_key_end_marker = "END " + "PRIVATE KEY"
    apns_file.write_text(
        f"-----{private_key_marker}-----\ntest\n-----{private_key_end_marker}-----\n",
        encoding="utf-8",
    )
    output_dir = tmp_path / "secrets-output"
    env = {
        **os.environ,
        "AWS_REGION": "ap-northeast-2",
        "AWS_PUSH_OUTPUT_DIR": str(output_dir),
        "FIREBASE_SERVICE_ACCOUNT_FILE": str(firebase_file),
        "APNS_AUTH_KEY_FILE": str(apns_file),
        "KBO_RELAY_USER_ID": "test-user",
        "KBO_RELAY_PASSWORD": "test-password",
        "PUSH_SYNC_SECRET": "0" * 64,
    }

    subprocess.run(
        ["bash", "scripts/aws-push-secrets.sh", "--dry-run"],
        cwd=ROOT,
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )

    assert not output_dir.exists()


def test_stack_output_no_env_file_does_not_write_output_state(tmp_path: Path) -> None:
    stack_file = tmp_path / "stack.json"
    stack_file.write_text(
        json.dumps(
            {
                "Stacks": [
                    {
                        "Outputs": [
                            {
                                "OutputKey": "ApiBaseUrl",
                                "OutputValue": "https://api.example.invalid/api",
                            }
                        ]
                    }
                ]
            }
        ),
        encoding="utf-8",
    )
    output_dir = tmp_path / "stack-output"
    env = {**os.environ, "AWS_PUSH_OUTPUT_DIR": str(output_dir)}

    subprocess.run(
        [
            "bash",
            "scripts/aws-push-stack-outputs.sh",
            "--input-json",
            str(stack_file),
            "--no-env-file",
        ],
        cwd=ROOT,
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )

    assert not output_dir.exists()
