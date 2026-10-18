# Phase 2 — Core Mission UX

Read `PRD.md`, `architecture.md`, `API_CONTRACT.md`, and `AGENTS.md`. Inspect the existing implementation and reuse its components.

Implement the core user journey UI:
- Home mission composer and a small set of example missions.
- Clarifying-question state.
- Structured mission plan with ordered steps and expected outputs.
- Plan review/approval interaction.
- Mission activity states: draft, awaiting approval, queued, running, completed, partially completed, failed, and cancelled where applicable.
- Results workspace layout for text and image artifacts.
- Loading, empty, offline, failure, retry, and partial-completion states.
- Make each flow understandable to a first-time user; minimize taps, ask only essential clarifying questions, and keep the next action obvious.
- Include polished composer/keyboard behavior and working stop, retry, copy, or share actions only where supported.
- Define accessible voice interaction states and the circular control near the composer. Integrate actual speech APIs/services only in the designated voice phase; do not fake listening, waveforms, or transcription.

If the backend is not implemented, use only an isolated development adapter and visibly label it as demo/development data. Never present simulated execution as real.

Keep this phase focused on UX and state modelling. Run tests and build; report exact results and gaps.
