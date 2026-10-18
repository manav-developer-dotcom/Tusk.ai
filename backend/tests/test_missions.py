from fastapi.testclient import TestClient


def test_create_mission_generates_structured_plan(client: TestClient):
    headers = {"X-Session-ID": "test-session-1"}
    payload = {"goal": "Write a launch announcement for our beta version"}

    response = client.post("/v1/missions", json=payload, headers=headers)
    assert response.status_code == 201
    data = response.json()

    assert data["id"].startswith("mission_")
    assert data["goal"] == "Write a launch announcement for our beta version"
    assert data["status"] == "readyForApproval"
    assert data["approved_by_user"] is False
    assert len(data["plan"]["steps"]) == 4
    assert data["plan"]["steps"][0]["title"] == "Define scope and audience"
    assert data["plan"]["steps"][1]["depends_on"] == [data["plan"]["steps"][0]["id"]]


def test_create_mission_triggers_clarification_for_vague_goal(client: TestClient):
    headers = {"X-Session-ID": "test-session-1"}
    payload = {"goal": "do it"}

    response = client.post("/v1/missions", json=payload, headers=headers)
    assert response.status_code == 201
    data = response.json()

    assert data["status"] == "needsClarification"
    assert len(data["clarifications"]) == 2
    assert len(data["plan"]["steps"]) == 0


def test_create_mission_idempotency_via_client_request_id(client: TestClient):
    headers = {"X-Session-ID": "test-session-1"}
    payload = {
        "goal": "Research market competitors",
        "client_request_id": "client-uuid-12345",
    }

    r1 = client.post("/v1/missions", json=payload, headers=headers)
    assert r1.status_code == 201
    m1 = r1.json()

    # Second call with same client_request_id
    r2 = client.post("/v1/missions", json=payload, headers=headers)
    assert r2.status_code == 201
    m2 = r2.json()

    assert m1["id"] == m2["id"]
    assert m1["created_at"] == m2["created_at"]


def test_list_and_get_mission(client: TestClient):
    headers = {"X-Session-ID": "test-session-1"}
    # Create two missions
    client.post("/v1/missions", json={"goal": "Goal 1: Document architecture"}, headers=headers)
    client.post("/v1/missions", json={"goal": "Goal 2: Plan sprint milestones"}, headers=headers)

    list_resp = client.get("/v1/missions", headers=headers)
    assert list_resp.status_code == 200
    data = list_resp.json()
    assert data["total"] == 2
    assert len(data["missions"]) == 2

    # Get single
    m_id = data["missions"][0]["id"]
    get_resp = client.get(f"/v1/missions/{m_id}", headers=headers)
    assert get_resp.status_code == 200
    assert get_resp.json()["id"] == m_id


def test_approve_mission_flow(client: TestClient):
    headers = {"X-Session-ID": "test-session-1"}
    create_resp = client.post(
        "/v1/missions",
        json={"goal": "Write summary notes for release"},
        headers=headers,
    )
    mission_id = create_resp.json()["id"]
    assert create_resp.json()["status"] == "readyForApproval"

    # Approve
    approve_resp = client.post(f"/v1/missions/{mission_id}/approve", headers=headers)
    assert approve_resp.status_code == 200
    approved_data = approve_resp.json()
    assert approved_data["status"] == "approved"
    assert approved_data["approved_by_user"] is True


def test_cancel_mission(client: TestClient):
    headers = {"X-Session-ID": "test-session-1"}
    create_resp = client.post(
        "/v1/missions",
        json={"goal": "Plan project outline"},
        headers=headers,
    )
    mission_id = create_resp.json()["id"]

    cancel_resp = client.post(
        f"/v1/missions/{mission_id}/cancel",
        json={"reason": "User changed mind"},
        headers=headers,
    )
    assert cancel_resp.status_code == 200
    assert cancel_resp.json()["status"] == "cancelled"
    assert cancel_resp.json()["failure_reason"] == "User changed mind"


def test_invalid_state_transition_returns_409(client: TestClient):
    headers = {"X-Session-ID": "test-session-1"}
    create_resp = client.post(
        "/v1/missions",
        json={"goal": "Write report draft"},
        headers=headers,
    )
    mission_id = create_resp.json()["id"]

    # Cancel it
    client.post(f"/v1/missions/{mission_id}/cancel", headers=headers)

    # Attempting to approve a cancelled mission must fail with 409
    bad_approve = client.post(f"/v1/missions/{mission_id}/approve", headers=headers)
    assert bad_approve.status_code == 409
    error_body = bad_approve.json()
    assert error_body["error"]["code"] == "INVALID_STATE_TRANSITION"
    assert "Cannot transition mission" in error_body["error"]["message"]


def test_retry_mission_from_failed_state(client: TestClient):
    headers = {"X-Session-ID": "test-session-1"}
    create_resp = client.post(
        "/v1/missions",
        json={"goal": "Draft press release"},
        headers=headers,
    )
    mission_id = create_resp.json()["id"]

    # Directly set to failed via DB to test retry path
    from app.database.connection import get_db_connection
    from app.models.domain import MissionStatus
    with get_db_connection() as conn:
        conn.execute(
            "UPDATE missions SET status = ?, failure_reason = 'Network glitch' WHERE id = ?",
            (MissionStatus.FAILED.value, mission_id),
        )

    # Retry should return state to readyForApproval
    retry_resp = client.post(f"/v1/missions/{mission_id}/retry", headers=headers)
    assert retry_resp.status_code == 200
    assert retry_resp.json()["status"] == "readyForApproval"
    assert retry_resp.json()["failure_reason"] is None


def test_status_endpoint(client: TestClient):
    headers = {"X-Session-ID": "test-session-1"}
    create_resp = client.post(
        "/v1/missions",
        json={"goal": "Research AI agents"},
        headers=headers,
    )
    mission_id = create_resp.json()["id"]

    status_resp = client.get(f"/v1/missions/{mission_id}/status", headers=headers)
    assert status_resp.status_code == 200
    data = status_resp.json()
    assert data["id"] == mission_id
    assert data["status"] == "readyForApproval"
    assert data["is_terminal"] is False
    assert len(data["step_states"]) == 3


def test_artifacts_empty_in_phase_3(client: TestClient):
    headers = {"X-Session-ID": "test-session-1"}
    create_resp = client.post(
        "/v1/missions",
        json={"goal": "Write report draft"},
        headers=headers,
    )
    mission_id = create_resp.json()["id"]

    artifacts_resp = client.get(f"/v1/missions/{mission_id}/artifacts", headers=headers)
    assert artifacts_resp.status_code == 200
    data = artifacts_resp.json()
    assert data["artifacts"] == []
    assert data["total"] == 0


def test_correlation_id_propagation(client: TestClient):
    custom_cid = "custom-trace-uuid-999"
    response = client.get("/health", headers={"X-Correlation-ID": custom_cid})
    assert response.status_code == 200
    assert response.headers.get("x-correlation-id") == custom_cid


def test_validation_error_structured_response(client: TestClient):
    # Empty goal should fail validation
    response = client.post("/v1/missions", json={"goal": ""})
    assert response.status_code == 422
    data = response.json()
    assert "error" in data
    assert data["error"]["code"] == "VALIDATION_ERROR"
    assert data["error"]["correlation_id"] is not None
