# Tusk.ai — Phased Roadmap

The phases are deliberately small. Complete the exit criteria for one phase before moving to the next. Do not build the entire product in one prompt.

## Phase 0 — Discovery and project foundation
**Goal:** inspect the environment, confirm a stack, and establish source-of-truth documentation.

Tasks:
- Inspect repository, installed SDKs, build tools, and available runtime.
- Review PRD, architecture, security, and API contract.
- Propose Android and backend stack with trade-offs.
- Define repository structure, local setup, configuration strategy, and initial test/build commands.
- Create/update `AGENTS.md`, ADR, and environment checklist.
- Identify external credentials and deployment prerequisites without requesting secrets in chat.

Exit criteria:
- A documented stack decision and rationale.
- No full product implementation yet.
- Risks, prerequisites, and next phase clearly reported.

## Phase 1 — App shell and design system
**Goal:** a clean, buildable app with navigation and reusable visual foundations.

Tasks:
- Set up project and build configuration.
- Add a strict monochrome design system (black, white, neutral greys), light/dark themes, typography, spacing, reusable controls, and accessible states.
- Do not use emojis; use a consistent professional vector icon library.
- Implement navigation skeleton for Home, Projects, Activity, and Settings.
- Define the welcome, sign-up/login entry, concise onboarding, and first-chat screen structure without pretending authentication is already connected.
- Add app identity and event-independent copy.
- Add basic UI/unit tests and build APK.

Exit criteria:
- Debug APK builds successfully.
- Navigation works; no dead primary controls.
- No fake AI execution or authentication is presented as real.
- No emojis or non-monochrome accent colors appear in the UI.

## Phase 2 — Core mission UX
**Goal:** user can enter a goal and review a structured plan using a clearly labelled temporary development adapter if backend is not ready.

Tasks:
- Home mission composer and examples.
- Clarifying-question state.
- Mission plan and step list.
- Approval/review screen.
- Loading, empty, error, and retry states.
- Keep development/demo responses explicitly labelled and isolated.

Exit criteria:
- Core screens are navigable and tested.
- Demo mode cannot be mistaken for a production connection.

## Phase 3 — Backend foundation and task persistence (Completed)
**Goal:** connect the app to a real backend contract.

Tasks:
- Implement API service, environment config, and health check.
- Implement mission creation, plan retrieval, status retrieval, and result retrieval.
- Persist mission and step states.
- Add request validation, structured errors, correlation IDs, and authorization design.
- Add integration tests and documented local setup.

Exit criteria:
- App creates and retrieves a real persisted mission.
- Backend errors appear honestly in the UI.
- Secrets remain server-side.

## Phase 4 — Real AI tools and execution engine
**Goal:** complete useful work through real provider/tool calls.

Tasks:
- Add provider adapter for text generation.
- Add image generation adapter if credentials, provider terms, and environment permit.
- Add orchestrator, timeouts, bounded retries, execution records, and artifact storage.
- Implement results workspace and retry behavior.
- Add approval gate for consequential actions.

Exit criteria:
- At least one real text workflow works end-to-end.
- Image workflow works end-to-end if supported by configured provider.
- Results and progress are based on actual execution records.
- Failure and partial-completion tests pass.

## Phase 5 — External agent interoperability
**Goal:** make supported mission capabilities usable through the required agent interface without duplicating business logic.

Tasks:
- Read `docs/EXTERNAL_AGENT_INTEGRATION.md`.
- Implement protocol adapter against the shared mission service.
- Register/configure the agent on the chosen discovery platform.
- Verify discoverability and a full conversation workflow through the external interface.
- Keep app branding and copy event-independent.

Exit criteria:
- External interface invokes real shared capabilities.
- Setup and verification instructions are documented.
- Public demo/repository content contains no secrets.

## Phase 6 — Startup-readiness essentials
**Goal:** close the most important operational gaps without scope explosion.

Tasks, prioritized by feasibility:
- Real account lifecycle: email registration/verification, login, password reset, secure session handling, logout, account/data deletion, and optional Google sign-in only if fully configured.
- Authentication and ownership enforcement.
- Data retention/deletion behavior.
- Basic usage and provider-cost tracking.
- Rate limits, abuse controls, and deployment configuration.
- Crash/error reporting with privacy-safe telemetry.
- Basic privacy policy and terms drafts for review before public launch.

Exit criteria:
- Security checklist reviewed.
- User data boundaries tested.
- Operational and cost risks documented.

## Phase 7 — Release hardening and demo
**Goal:** deliver a reproducible, stable build.

Tasks:
- Run automated tests, static analysis, and dependency/security checks available in the stack.
- Test on emulator/device and poor-network/error scenarios.
- Fix high-severity bugs and verify the main flow.
- Build and verify release APK/AAB as appropriate.
- Update README, screenshots, demo script, and known limitations.

Exit criteria:
- Clean documented build path.
- Evidence-based test report.
- Demo follows a real successful workflow and discloses any demo-only limitations.

## Scope guardrails

- No SMS or phone-call integrations in the initial product.
- No unapproved external sending/publishing.
- No multi-agent architecture unless a concrete workflow benefits from it.
- No billing/team/marketplace build-out before core usage is validated.
- A phase is not complete because code was generated; it is complete when acceptance criteria and checks pass.

## Cross-phase experience quality gate

Every UI phase must pass a first-time-user simplicity review: obvious primary action, minimal taps and questions, plain language, no unnecessary permissions, functional visible controls, and clear recovery paths. Apply the shared monochrome design system with no emojis. Plan the one-second cold-launch wordmark shine and real voice interaction in the appropriate phases; do not simulate voice or execution. Add streaming controls, stop/retry, copy/share, mission/tool status, keyboard handling, subtle haptics, connectivity states, and reduced-motion/accessibility support only where they are useful and genuinely implemented. See `DESIGN_SYSTEM.md` for detailed acceptance criteria.
