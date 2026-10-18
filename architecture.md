# Tusk.ai — Architecture

- Status: Proposed baseline; confirm technology choices in Phase 0.
- Version: 0.1

## 1. Architectural goals

1. Keep product experience independent from any single distribution channel.
2. Separate planning from tool execution and external side effects.
3. Represent task state durably and honestly.
4. Keep privileged credentials on the backend.
5. Support an Android client and agent/protocol adapters over shared capabilities.
6. Begin as a modular monolith unless measured needs justify distributed services.

## 2. Logical architecture

```text
Android App ───────────────┐
                           ├── Auth/API boundary ── Mission Application Service
Agent/Protocol Adapter ────┘                              │
                                                         ├── Planner
                                                         ├── Policy & Approval Gate
                                                         ├── Execution Orchestrator
                                                         ├── Tool Registry / Tool Adapters
                                                         ├── Result & Artifact Service
                                                         └── Task State / Event Service
                                                                  │
                         ┌────────────────────────────────────────┼──────────────┐
                         │                                        │              │
                    Database                                Object Storage   Model APIs
                    (tasks, users,                         (images/files)   (text/image)
                     plans, approvals)
```

This is a logical diagram, not a statement that these components already exist.

## 3. Component responsibilities

### Android client
- Presentation, navigation, local transient UI state, upload/download UX.
- Calls the backend through a versioned API.
- Does not contain provider secrets or own authoritative task state.
- Supports loading, empty, offline, retry, and partial-completion states.

### API and authentication boundary
- Validates inputs and identity/authorization.
- Applies request size limits, rate limits, and request correlation.
- Returns structured errors and stable identifiers.
- Version API contracts when compatibility requires it.

### Mission application service
- Creates missions and coordinates the lifecycle.
- Persists plan, approvals, execution state, artifacts, and errors.
- Exposes status and result retrieval independent of the client.

### Planner
- Converts a goal and relevant context into a structured plan.
- Declares required inputs, steps, tool requirements, expected outputs, and approval boundaries.
- Must not directly perform consequential side effects.

### Policy and approval gate
- Classifies external side effects and permission requirements.
- Binds approval to a specific action and payload summary.
- Rejects stale or mismatched approvals.

### Execution orchestrator
- Runs approved steps with bounded concurrency, timeouts, retries, and cancellation where safe.
- Records step transitions and tool results.
- Supports partial completion and safe recovery.
- Uses idempotency for actions where duplicate execution would be harmful.

### Tool adapters
- Provide typed interfaces to model providers and external services.
- Normalize provider errors and results.
- Apply provider-specific limits and timeouts.
- Are replaceable without rewriting the mission domain.

### Persistence and artifact storage
- Relational or equivalent durable storage for users, missions, steps, approvals, and artifact metadata.
- Object storage for generated files where appropriate.
- Enforce ownership and access checks for every artifact retrieval.
- Define retention and deletion policies before storing sensitive user content.

### Agent/protocol adapter
- Translates external agent protocol requests into the same mission/application capabilities.
- Must not fork a separate implementation of planning or tool execution.
- Exposes only supported, permission-checked operations.

## 4. Core domain entities

- User: identity and account metadata, when authentication is implemented.
- Mission: goal, owner, status, timestamps, plan version, and final summary.
- MissionStep: ordered step, kind, status, inputs/outputs references, retry count, and error.
- Approval: action identifier, payload summary/hash, approver, status, expiry, and timestamp.
- Artifact: owner, mission/step association, media type, storage reference, metadata, and retention state.
- ToolExecution: tool name/version, sanitized input summary, result reference, timing, status, and correlation ID.
- UsageRecord: provider/model/tool usage and estimated cost, subject to privacy controls.

Do not store unnecessary raw prompts or sensitive content in operational logs.

## 5. State model

Mission states should be explicit, for example:
`draft → awaiting_approval → queued → running → completed | partially_completed | failed | cancelled`

Step states may include:
`pending → ready → running → succeeded | failed | skipped | awaiting_approval | cancelled`

Rules:
- State transitions are validated server-side.
- Terminal states are not silently overwritten.
- Partial completion is not reported as full success.
- Retry creates an auditable attempt or transition.
- UI progress is derived from persisted state/events, never from a fake timer.
- Cancellation must not claim that an already completed external side effect was undone.

## 6. Data flow

1. Client submits goal and optional context.
2. API validates request and creates a mission record.
3. Planner produces a structured plan.
4. Mission and steps are persisted and returned for review.
5. User approves the plan; any consequential action also receives specific approval at the correct execution boundary.
6. Orchestrator runs steps through tool adapters.
7. Each transition and artifact reference is persisted.
8. Client polls or subscribes to supported status updates.
9. Client fetches results and renders them with accurate provenance/status.

## 7. API principles

See `API_CONTRACT.md`. Use versioned routes, typed request/response models, stable error codes, pagination for histories, and idempotency for mission creation and external side effects where supported. Do not expose provider credentials or internal stack traces.

## 8. Deployment strategy

- Begin with a modular backend service and managed database/storage where practical.
- Keep development, staging, and production configuration separate.
- Use environment/secret management supplied by the deployment platform.
- Add health/readiness checks, structured logs, correlation IDs, and basic usage/cost tracking.
- Use migrations for schema changes.
- Avoid Kubernetes, microservices, queues, or multi-agent complexity until workload justifies them. A durable job queue may be added if the initial runtime cannot reliably handle long tasks.

## 9. Technology selection policy

Phase 0 must inspect the installed environment and choose a stack based on:
- reliable Android APK build and test path;
- maintainability for a small team/beginner;
- stable ecosystem and documentation;
- backend deployment options;
- protocol/library compatibility;
- low friction for local development.

Document the decision and trade-offs in `docs/adr/`. Do not assume a framework without checking the environment.

## 10. Failure handling and observability

- Classify errors as validation, auth, policy/approval, provider, timeout, rate limit, network, or internal.
- Use bounded retries only for transient/retry-safe failures.
- Persist sanitized failure details and correlation IDs.
- Never log secrets, access tokens, or full sensitive payloads by default.
- Show user-facing explanations and next steps, not raw stack traces.
- Add provider cost and latency measurements before scaling usage.

## 11. Architecture decision triggers

Revisit the baseline if:
- task volume requires a durable queue/worker pool;
- multiple clients require stronger API versioning;
- authorization requirements become multi-tenant/team-based;
- tool execution needs sandboxing;
- a single backend deployment becomes a reliability bottleneck;
- multi-agent orchestration demonstrates measurable benefit over one orchestrator.
