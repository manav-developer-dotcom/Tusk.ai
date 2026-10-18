import sqlite3
from pathlib import Path
from fastapi.testclient import TestClient
from app.database.connection import get_db_connection
from app.database.repository import MissionRepository
from app.models.domain import MissionStatus


def test_sqlite_persistence_across_service_reconnect(client: TestClient, temp_db_path: Path):
    """Verify that missions and steps survive application / connection restarts."""
    headers = {"X-Session-ID": "persisted-session"}
    create_resp = client.post(
        "/v1/missions",
        json={"goal": "Write quarterly OKRs and strategy document"},
        headers=headers,
    )
    assert create_resp.status_code == 201
    mission_id = create_resp.json()["id"]

    # Approve mission
    approve_resp = client.post(f"/v1/missions/{mission_id}/approve", headers=headers)
    assert approve_resp.status_code == 200

    # Simulate fresh cold service start by directly opening the SQLite database
    # with a brand-new connection and repository instance
    with sqlite3.connect(str(temp_db_path)) as fresh_conn:
        fresh_conn.row_factory = sqlite3.Row
        fresh_repo = MissionRepository(fresh_conn)
        loaded = fresh_repo.get_mission_by_id("persisted-session", mission_id)

        assert loaded is not None
        assert loaded.id == mission_id
        assert loaded.status == MissionStatus.APPROVED
        assert loaded.approved_by_user is True
        assert len(loaded.plan.steps) == 4
        assert loaded.plan.steps[0].title == "Define scope and audience"


def test_session_isolation_boundaries(client: TestClient):
    """Ensure Session B cannot view, retrieve, or approve Session A's missions."""
    session_a = {"X-Session-ID": "session-user-alpha"}
    session_b = {"X-Session-ID": "session-user-beta"}

    # User A creates a mission
    resp_a = client.post(
        "/v1/missions",
        json={"goal": "Confidential internal review"},
        headers=session_a,
    )
    assert resp_a.status_code == 201
    mission_a_id = resp_a.json()["id"]

    # User B lists missions -> should be empty
    list_b = client.get("/v1/missions", headers=session_b)
    assert list_b.status_code == 200
    assert list_b.json()["total"] == 0
    assert len(list_b.json()["missions"]) == 0

    # User B attempts to fetch User A's mission by ID -> 404 (not found in session)
    get_b = client.get(f"/v1/missions/{mission_a_id}", headers=session_b)
    assert get_b.status_code == 404
    assert get_b.json()["error"]["code"] == "MISSION_NOT_FOUND"

    # User B attempts to approve User A's mission -> 404
    approve_b = client.post(f"/v1/missions/{mission_a_id}/approve", headers=session_b)
    assert approve_b.status_code == 404

    # User A can still retrieve and approve normally
    get_a = client.get(f"/v1/missions/{mission_a_id}", headers=session_a)
    assert get_a.status_code == 200
    assert get_a.json()["id"] == mission_a_id
