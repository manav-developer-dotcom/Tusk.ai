# Phase 1 — App Shell and Monochrome Design System

Proceed only after Phase 0's stack recommendation is approved. Read `AGENTS.md`, `PRD.md`, and the current architecture/ADR first.

Build only the app foundation:
- Set up the selected Android project and repeatable debug build.
- Implement shared monochrome design tokens for black, white, and neutral greys, with light/dark themes and system-theme support.
- Use professional sans-serif typography, consistent spacing, accessible reusable controls, subtle borders, and restrained motion.
- Do not use emojis anywhere in the UI; use a consistent professional vector icon library.
- Use screen-appropriate layouts rather than repeating generic card templates.
- Implement a polished navigation skeleton for Home, Projects, Activity, and Settings.
- Define the welcome, authentication entry, short onboarding, and first-chat screen structure, but do not claim authentication is functional without a real provider/backend.
- Include accessible loading, empty, error, offline, and disabled states.
- Make the shell exceptionally easy for first-time users: one obvious primary action per screen, minimal navigation, plain-language labels, and no unnecessary setup.
- Implement the cold-launch wordmark shine only if it fits this phase and the chosen stack: approximately one second, original monochrome light sweep, cold launch only, reduced-motion alternative, and no copying of Sony/other brand assets. If not implemented now, document the exact follow-up phase.
- Define the voice-control placement and state model near the composer, but defer actual speech integration to its dedicated phase. Never simulate listening or transcription.
- Add tasteful, restrained interaction foundations and ensure all motion respects accessibility preferences.
- Keep domain/network logic out of presentation components.
- Add basic tests for navigation, theme behavior, and critical design-system behavior.

Do not implement real AI, billing, or a full backend in this phase. Do not show fake authentication, fake execution, or fake progress. Keep product copy independent of events and competitions.

Run the actual lint/test/build commands and verify the APK output path. Report files changed, exact checks and results, known gaps, and the next recommended phase.
