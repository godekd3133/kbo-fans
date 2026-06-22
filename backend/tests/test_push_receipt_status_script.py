from __future__ import annotations

import json
import os
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

ROOT_DIR = Path(__file__).resolve().parents[2]
SCRIPT = ROOT_DIR / "scripts" / "push-receipt-status.sh"


def test_push_receipt_status_prints_sanitized_recent_receipts_and_matches_filter() -> None:
    payload = _config_payload(
        [
            {
                "messageId": "projects/kbo-fans/messages/1",
                "source": "foreground",
                "type": "hit",
                "gameId": "GAME_20260620HTKT0",
                "route": "/game/GAME_20260620HTKT0",
                "receivedAt": "2026-06-22T05:30:00Z",
                "recordedAt": "2026-06-22T05:30:01Z",
                "deviceTokenSuffix": "abcd1234",
                "platform": "ios",
                "myTeam": "KT",
                "followedGameIds": ["GAME_20260620HTKT0"],
                "data": {
                    "topic": "hit_GAME_20260620HTKT0",
                    "kind": "hit",
                    "token": "secret-fcm-token",
                },
            }
        ]
    )
    payload["data"]["registry"]["deviceSummaries"] = [
        {
            "deviceTokenSuffix": "abcd1234",
            "installationIdSuffix": "stall-id",
            "platform": "ios",
            "myTeam": "OB",
            "followedGameIds": ["GAME_20260620HTKT0"],
            "topicCount": 8,
            "updatedAt": "2026-06-22T06:10:00+00:00",
            "topicsUpdatedAt": "2026-06-22T06:11:00+00:00",
            "notificationsAllowed": True,
            "authorizationStatus": "authorized",
            "apnsTokenReady": True,
        }
    ]
    with _mock_server(payload) as server:
        result = _run_status_script(
            server.base_url,
            "--expect-receipt",
            "--game-id",
            "GAME_20260620HTKT0",
            "--type",
            "hit",
            "--source",
            "foreground",
        )

    assert result.returncode == 0, result.stderr
    assert server.seen_secret == "secret"
    assert "push_receipts=status=ok count=1 recent=1" in result.stdout
    assert (
        "push_device=platform=ios suffix=abcd1234 installation=stall-id "
        "myTeam=OB followed=GAME_20260620HTKT0 "
        "topicCount=8 notificationsAllowed=True authorizationStatus=authorized "
        "apnsTokenReady=True updatedAt=2026-06-22T06:10:00+00:00 "
        "topicsUpdatedAt=2026-06-22T06:11:00+00:00"
    ) in result.stdout
    assert "push_receipt_match=status=ok matches=1" in result.stdout
    assert "gameId=GAME_20260620HTKT0" in result.stdout
    assert "deviceTokenSuffix=abcd1234" in result.stdout
    assert "topic=hit_GAME_20260620HTKT0" in result.stdout
    assert "secret-fcm-token" not in result.stdout
    assert "secret" not in result.stdout


def test_push_receipt_status_fails_when_expected_receipt_is_missing() -> None:
    payload = _config_payload(
        [
            {
                "source": "foreground",
                "type": "hit",
                "gameId": "GAME_20260620HTKT0",
                "deviceTokenSuffix": "abcd1234",
            }
        ]
    )
    with _mock_server(payload) as server:
        result = _run_status_script(
            server.base_url,
            "--expect-receipt",
            "--game-id",
            "GAME_20260620HTKT0",
            "--type",
            "homerun",
        )

    assert result.returncode == 1
    assert server.seen_secret == "secret"
    assert "push_receipt_match=status=missing" in result.stderr


def test_push_receipt_status_requires_sync_secret() -> None:
    result = subprocess.run(
        [str(SCRIPT), "--base-url", "http://127.0.0.1:1/api", "--allow-insecure", "true"],
        cwd=ROOT_DIR,
        text=True,
        capture_output=True,
        env={**os.environ, "PUSH_SYNC_SECRET": ""},
    )

    assert result.returncode == 1
    assert "PUSH_SYNC_SECRET is required" in result.stderr


def _run_status_script(base_url: str, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            str(SCRIPT),
            "--base-url",
            base_url,
            "--allow-insecure",
            "true",
            *args,
        ],
        cwd=ROOT_DIR,
        text=True,
        capture_output=True,
        env={**os.environ, "PUSH_SYNC_SECRET": "secret"},
    )


def _config_payload(receipts: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "success": True,
        "data": {
            "readyForIphoneOnlyDemo": True,
            "registry": {
                "registeredDeviceCount": 17,
                "followedGameCount": 1,
                "activeLiveActivityGameCount": 3,
                "pushReceiptCount": len(receipts),
                "recentPushReceipts": receipts,
            },
            "scheduler": {"lastSyncAt": "2026-06-22T05:30:00Z"},
        },
    }


class _Server:
    def __init__(self, payload: dict[str, Any]) -> None:
        self.payload = payload
        self.seen_secret = ""
        self._httpd = ThreadingHTTPServer(("127.0.0.1", 0), self._handler())
        self.base_url = f"http://127.0.0.1:{self._httpd.server_port}/api"
        self._thread = threading.Thread(target=self._httpd.serve_forever, daemon=True)

    def __enter__(self) -> "_Server":
        self._thread.start()
        return self

    def __exit__(self, *exc: object) -> None:
        self._httpd.shutdown()
        self._httpd.server_close()
        self._thread.join(timeout=5)

    def _handler(self) -> type[BaseHTTPRequestHandler]:
        parent = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802
                parent.seen_secret = self.headers.get("X-Kbo-Push-Sync-Secret", "")
                if self.path != "/api/push/config-status":
                    self.send_error(404)
                    return
                body = json.dumps(parent.payload).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                return

        return Handler


def _mock_server(payload: dict[str, Any]) -> _Server:
    return _Server(payload)
