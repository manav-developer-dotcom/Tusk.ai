# Phase 3 — Backend and Persistence

Read the architecture, API contract, security baseline, and relevant ADRs. Inspect current code before modifying it.

Implement the smallest production-shaped backend foundation:
- Health endpoint.
- Versioned mission create/list/read/status/result APIs.
- Validated request/response models and stable error codes.
- Persistent mission and step state.
- Configuration from environment/secret management; `.env.example` contains placeholders only.
- Correlation IDs, sanitized structured logs, request limits, and ownership-ready authorization boundaries.
- App network client wired to the real API with timeout and error handling.

Do not add real model providers or external side effects in this phase unless explicitly required by an existing dependency. Remove or isolate demo adapters so production mode cannot silently fall back to mock success.

Add unit/integration tests and document exact setup commands. Run tests/builds and report results, migrations, environment variables, and known gaps.
