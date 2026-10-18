# Instructions for Antigravity and Coding Agents

## Mission

Build Tusk.ai as a credible, startup-ready AI action assistant. Follow `PRD.md`, `architecture.md`, `ROADMAP.md`, `API_CONTRACT.md`, `SECURITY.md`, and `PRODUCT_DECISIONS.md`. If documents conflict, stop and report the conflict instead of guessing.

## Product naming and branding

- The product name is exactly `Tusk.ai`.
- Never include hackathon, competition, event, sponsor, or judging language in the app, onboarding, app metadata visible to users, demo content, or customer-facing product copy.
- Do not create event-branded screens or placeholder copy.
- Keep product language independent of any event or accelerator.
- Visual direction: premium, professional, strictly monochrome black, white, and neutral greys. Support light and dark themes, including system preference. Use a tusk-inspired abstract mark only if it remains simple and legible. Do not introduce colored accents or gradients.

## UI and design rules

- Never use emojis anywhere in the app UI, onboarding, sample content, notifications, empty/error/success states, or demo content. Use a consistent professional vector icon library instead.
- Use black, white, and neutral greys only. Define shared design tokens for both light and dark themes; do not hardcode scattered colors in individual screens.
- Use modern, legible sans-serif typography, clear hierarchy, generous spacing, restrained motion, and subtle borders.
- Choose layouts to fit each screen's purpose. Do not force every screen into the same card template; avoid nested cards and decorative clutter.
- Keep the first-run experience short and welcoming. Explain the product, then get the user into their first conversation without unnecessary setup.
- Authentication controls must be connected to real configured services. Never show a working-looking Google sign-in or account flow if the provider/backend is not implemented; label unavailable capabilities honestly.
- Provide accessible contrast, scalable text, screen-reader labels, appropriate touch targets, and clear focus/selection states.

## Working method

- Work in the smallest useful phase from `ROADMAP.md`.
- Read the relevant documents and inspect the existing repository before changing files.
- Do not implement future phases unless explicitly asked.
- Before coding, state the phase goal and the files/components likely to change.
- After coding, run relevant tests, lint, and build checks; report exact commands and results.
- If a command cannot be run, state why. Never claim a test/build passed without executing it.
- End every phase with: changes made, files changed, tests run/results, known gaps, risks, and the recommended next phase.
- Keep prompts and code changes focused. Avoid rewriting stable code or duplicating instructions already recorded here.

## Engineering rules

- Choose the app framework after inspecting the available environment; optimize for a reliable, maintainable Android APK and clear testing.
- Separate presentation, application/domain logic, data access, and platform integration.
- Keep AI orchestration and provider secrets on the backend. Never embed private API keys, service credentials, or privileged tokens in the APK or public repository.
- Android UI and external agent interfaces should call the same backend capabilities where practical.
- Use real backend execution and persistent state for production flows. Any mock/demo mode must be explicitly labelled, isolated, and easy to remove.
- Never fabricate task progress, tool execution, generated outputs, external delivery, or success.
- Make task states explicit and recoverable; support loading, empty, failure, retry, cancellation where safe, and offline/network error states.
- Require explicit user approval before sending, publishing, purchasing, deleting, or other consequential external actions.
- Validate all inputs and outputs at trust boundaries. Use least privilege and redact secrets/PII from logs.
- Keep accessibility, responsive layouts, and clear error messages in scope.
- Prefer simple, proven dependencies. Explain material dependencies and avoid premature microservices or multi-agent complexity.

## Documentation rules

- Update relevant Markdown docs when behavior, APIs, architecture, security, or decisions change.
- Add an ADR in `docs/adr/` for significant architectural decisions.
- Keep `README.md` accurate and never describe planned functionality as implemented.
- Record open questions in `PRODUCT_DECISIONS.md`.

## Effortless usability and interaction polish

- Simplicity is a product requirement. Design for a person who has never used Tusk.ai and may not be technically confident.
- Keep one obvious primary action per screen, with the composer prominent on chat screens. Minimize taps, screens, forms, menus, onboarding questions, and permission requests.
- Let users describe goals in ordinary language. Ask only essential clarifying questions, one at a time where possible. Use sensible defaults and make the next step obvious.
- Avoid complicated dashboards, excessive cards, nested navigation, crowded toolbars, and exposing advanced controls before they are relevant. Every visible control must work or be clearly unavailable.
- On a full cold launch, play a refined approximately one-second cinematic light-sweep across the Tusk.ai wordmark. This is an original monochrome animation inspired by premium film-logo reveals; do not copy Sony or any other brand assets. Do not replay on every screen/navigation. Respect reduced-motion preferences and avoid delaying access to the app.
- Include a modern voice interaction near the composer: clear circular microphone/voice control, real listening/speaking states, subtle waveform visualization, speech-to-text where supported, and clear cancel, permission, and failure states. Use actual platform APIs/services; never fake listening or transcription. Voice must not block normal typing.
- Add useful contemporary micro-interactions: smooth streaming where supported, stop/retry/copy/share actions, contextual tool and mission status, polished keyboard/composer behavior, subtle Android haptics where appropriate, and graceful loading, empty, offline, error, and partial-result states. Respect system accessibility settings and reduced motion.
- Motion and decoration must serve clarity, confidence, speed, or satisfaction. Avoid constant animation, unnecessary controls, and imitating proprietary interfaces.
