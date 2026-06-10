from fastapi.testclient import TestClient
from kbo_fans_backend.main import app


def test_healthcheck_returns_ok() -> None:
    client = TestClient(app)

    response = client.get("/api/health")

    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    assert body["data"]["status"] == "ok"
