# Tusk.ai

Tusk.ai is a startup-oriented AI action assistant that turns a user's intent into completed, verifiable work. Users describe an outcome; Tusk.ai clarifies requirements, plans a mission, executes available tools, tracks real status, and presents usable results.

## Product principles

- Outcome-first: optimize for completed work, not prolonged chat.
- Honest execution: never fabricate tool calls, progress, results, or success.
- Human control: request approval before consequential external actions.
- Secure by design: keep provider credentials and secrets on trusted backend infrastructure.
- Modular and portable: the Android app is a client of a reusable core service.
- Ship in small increments: each phase has acceptance criteria, tests, and a concise report.
- Professional monochrome UI: black, white, and neutral greys with light/dark themes.
- No emojis in product UI; use consistent vector iconography.
- Familiar, low-friction onboarding and account flows, backed by real integrations rather than decorative screens.

## Source-of-truth documents

- `PRD.md` — product vision, users, scope, requirements, and success measures.
- `architecture.md` — system boundaries, components, data flow, and deployment principles.
- `ROADMAP.md` — phased implementation plan and exit criteria.
- `AGENTS.md` — working rules for Antigravity and coding agents.
- `API_CONTRACT.md` — proposed client/backend contract.
- `SECURITY.md` — security and privacy requirements.
- `TESTING.md` — quality strategy and required checks.
- `DEVELOPMENT.md` — local setup and engineering workflow.
- `PRODUCT_DECISIONS.md` — durable decisions and unresolved questions.
- `DESIGN_SYSTEM.md` — visual rules, accessibility, screen patterns, and first-run UX requirements.
- `docs/EXTERNAL_AGENT_INTEGRATION.md` — agent interoperability requirements, separate from product branding.
- `prompts/` — focused prompts to run one phase at a time.

## How to use this pack

1. Put these files in the root of the Tusk.ai repository, preserving the folder structure.
2. Give Antigravity `AGENTS.md` and `ROADMAP.md` as operating context.
3. Start with `prompts/PHASE_00_FOUNDATION.md`.
4. Review the report and proposed stack before authorizing the next phase.
5. Update documentation when a decision changes; do not silently contradict it.

## Current status

- **Phase 0 (Foundation & Audit):** Completed. Stack selected (Flutter on Android, FastAPI/Python backend target).
- **Phase 1 (App Shell & Branding):** Completed. Monochrome design tokens, cold-launch wordmark shine, navigation, history sidebar, and local APK build workflow.
- **Phase 2 (Core Mission UX):** Completed. Natural-language goal intake, interactive clarification, isolated rule-based local planner adapter, plan review & approval flow, explicit mission state machine, and persistence.
- **Phase 3 (Backend Foundation & Task Persistence):** Completed. FastAPI/Python backend service with SQLite persistence, session isolation, plan generation, structured errors, correlation tracing, and Flutter client API integration.
- **Phase 4 (Real AI Tools & Execution Engine):** Next phase. Provider adapters, real execution records, and artifact storage.

## Usability and interaction principles

Tusk.ai is designed to feel effortless to new users: a clear primary action, prominent composer, minimal setup, plain-language interaction, and easy recovery from errors. The design baseline also includes a refined approximately one-second monochrome wordmark shine on full cold launch, real voice interaction where supported, and thoughtful micro-interactions. No emojis are used anywhere in the app. See `DESIGN_SYSTEM.md` and `AGENTS.md` for acceptance criteria.
