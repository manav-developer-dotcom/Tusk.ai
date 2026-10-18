# Phase 5 — External Agent Interoperability

Read `docs/EXTERNAL_AGENT_INTEGRATION.md`, `architecture.md`, `API_CONTRACT.md`, and `SECURITY.md`.

Inspect current official protocol documentation and supported SDKs before coding. Implement a thin adapter that maps external requests into the same mission application service used by the Android app.

Requirements:
- Typed inputs/outputs and clear capability descriptions.
- Honest status/error mapping and real execution records.
- Approval and authorization checks cannot be bypassed.
- Configure registration/discovery only with documented, available credentials.
- Verify the primary workflow directly through the external conversation interface.
- Keep all event/competition-specific language out of customer-facing product UI and copy.
- Do not expose secrets in source control or public logs.

Run adapter tests and document registration, local testing, public profile/discovery verification, and a complete manual smoke test. Do not claim external discoverability until verified.
