# Phase 4 — Real AI Tools and Mission Execution

Read `PRD.md`, `architecture.md`, `API_CONTRACT.md`, `SECURITY.md`, and the current implementation. Preserve established boundaries.

Implement:
- A typed provider adapter for real text generation.
- An image-generation adapter if a supported provider and credentials are configured.
- Structured plan validation and an execution orchestrator.
- Durable step transitions and result/artifact metadata.
- Timeouts, bounded retry rules, provider error mapping, and partial-completion handling.
- A results UI connected to persisted real outputs.
- Explicit approval gates before any consequential external action.

Keep credentials on the backend. Add mocked unit tests plus controlled integration/smoke tests that clearly require configured credentials. Never substitute mock success when a real provider fails.

Run the relevant tests/build and report provider configuration, actual test results, known limitations, and next step.
