# Tusk.ai — Initial API Contract

This is a proposed contract to guide implementation. Final route syntax and schemas may be refined in Phase 0, but semantic guarantees should remain.

## Principles

- Version public routes (for example `/v1`).
- JSON requests/responses unless a file-transfer endpoint requires otherwise.
- Authenticate and authorize every user-owned resource once auth is enabled.
- Use stable error codes; never return stack traces or secrets.
- Use idempotency keys for mission creation and duplicate-sensitive external actions.
- Represent long-running work as a resource with a stable ID.
- Keep provider-specific types behind adapters.

## Suggested endpoints

| Method | Route | Purpose |
|---|---|---|
| GET | `/health` | Liveness/readiness suitable for deployment checks |
| POST | `/v1/auth/register` | Register user account with email/password and obtain JWT tokens |
| POST | `/v1/auth/login` | Authenticate credentials and receive access/refresh tokens |
| POST | `/v1/auth/refresh` | Exchange refresh token for fresh access token |
| GET | `/v1/auth/me` | Retrieve authenticated caller profile |
| POST | `/v1/missions` | Create a mission from a user goal |
| GET | `/v1/missions` | List current user's missions with pagination |
| GET | `/v1/missions/{mission_id}` | Retrieve mission and plan |
| POST | `/v1/missions/{mission_id}/approve` | Approve a plan or specified action |
| POST | `/v1/missions/{mission_id}/execute` | Start execution after required approval |
| POST | `/v1/missions/{mission_id}/cancel` | Request safe cancellation |
| POST | `/v1/missions/{mission_id}/retry` | Retry eligible failed steps |
| GET | `/v1/missions/{mission_id}/status` | Retrieve authoritative status and step states |
| GET | `/v1/missions/{mission_id}/artifacts` | List result artifacts |
| GET | `/v1/artifacts/{artifact_id}` | Retrieve authorized artifact metadata/content URL |


## Create mission request

```json
{
  "goal": "Create a launch campaign for a new product",
  "context": {
    "audience": "small business customers",
    "tone": "confident and helpful"
  },
  "client_request_id": "client-generated-id"
}
```

Do not place secrets or payment credentials in arbitrary context fields.

## Mission response (illustrative)

```json
{
  "id": "mission_id",
  "status": "draft",
  "goal": "Create a launch campaign for a new product",
  "plan": {
    "version": 1,
    "steps": [
      {
        "id": "step_1",
        "title": "Draft campaign copy",
        "kind": "generate_text",
        "status": "pending",
        "requires_approval": false,
        "expected_outputs": ["campaign_copy"]
      }
    ]
  },
  "created_at": "ISO-8601 timestamp"
}
```

Illustrative schemas are not implementation claims. Use real generated identifiers and timestamps.

## Status vocabulary

Mission: `draft`, `awaiting_approval`, `queued`, `running`, `completed`, `partially_completed`, `failed`, `cancelled`.

Step: `pending`, `ready`, `running`, `awaiting_approval`, `succeeded`, `failed`, `skipped`, `cancelled`.

Document any deviations and keep app/backend mappings consistent.

## Error response

```json
{
  "error": {
    "code": "PROVIDER_TIMEOUT",
    "message": "The generation service took too long to respond.",
    "retryable": true,
    "correlation_id": "request-correlation-id"
  }
}
```

Messages must not disclose internal stack traces or credentials. Error text should be safe for display.

## Approval contract

An approval must refer to a specific mission step/action and a clear payload summary. Where possible, store a canonical payload hash and expiry. A changed payload invalidates the previous approval. Plan approval does not automatically grant approval for all future external side effects.

## Artifact contract

Artifacts should include ID, mission/step association, media type, size where available, creation timestamp, and authorized retrieval information. Do not expose unrestricted object-storage credentials or permanent public URLs for private files.

## Compatibility

- Treat breaking response changes as versioned changes.
- Add contract tests for critical schemas and error cases.
- Keep agent/protocol adapters mapped to the same mission domain, not a parallel implementation.
