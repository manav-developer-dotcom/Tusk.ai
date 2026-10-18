# Tusk.ai — Design System and First-Run Experience

- Status: Design requirements baseline
- Product: Tusk.ai

## 1. Design goals

Create a premium, professional AI product that feels clear, calm, capable, and trustworthy. Use the visual restraint of monochrome social/productivity apps and the low-friction conversation journey familiar to users of modern AI assistants. Do not copy another product’s exact screen design, branding, copy, or assets.

## 2. Color system

Use black, white, and neutral greys only. Do not introduce teal, blue, purple, other colored accents, or gradients. Define semantic tokens rather than scattering literal colors through screens.

### Dark theme
- Primary background: black or near-black.
- Elevated surface: very dark neutral grey.
- Primary text: white.
- Secondary text: mid/light neutral grey with sufficient contrast.
- Dividers and outlines: subtle neutral grey.
- Disabled states: muted neutral grey, while retaining legibility.

### Light theme
- Primary background: white.
- Elevated surface: white or very light neutral grey.
- Primary text: black or near-black.
- Secondary text: dark neutral grey with sufficient contrast.
- Dividers and outlines: light neutral grey.
- Disabled states: muted neutral grey, while retaining legibility.

Support system preference and a manual Light / Dark / System selection in settings. Theme changes must apply consistently across every screen, dialog, sheet, input, and navigation element.

## 3. Typography and layout

- Use a modern, legible sans-serif family supported by the selected platform.
- Define consistent type roles for screen titles, section headings, body, labels, captions, and code/content previews.
- Use generous whitespace, a consistent spacing scale, and clear alignment.
- Keep body copy concise and readable; support text scaling.
- Use restrained corner radii and subtle borders. Shadows should be rare and functional.
- Avoid visual clutter, decorative gradients, excessive animation, and nested cards.
- Do not force all screens into the same card template. Select layouts according to content and task.

## 4. Iconography and prohibited decoration

**Emojis are prohibited throughout the app.** This includes welcome/onboarding, chat examples, buttons, navigation, avatars, status labels, notifications, toasts, empty states, errors, success messages, generated sample content authored by the app, and demo data.

Use a consistent professional vector icon library. Match stroke weight, size, alignment, and optical balance. Every icon must have a clear meaning; provide accessible labels for icon-only controls. Do not use emoji as status indicators or decorative substitutes for icons.

## 5. Screen patterns

- **Welcome:** typography-led, concise value proposition, clear Get started and Log in actions.
- **Authentication:** focused forms, visible validation, password visibility control where appropriate, clear recovery route, and loading/error states.
- **Onboarding:** a few short steps explaining chat, Mission Mode, and connected tools. Skippable when security/account requirements allow. No long tutorial.
- **Home / first chat:** prominent composer, welcoming headline, a small number of text-only example prompts, and simple access to history/settings. Avoid excessive dashboard widgets.
- **Conversation:** readable message hierarchy, streaming/loading feedback, stop/retry/copy actions where supported, and clear distinction between assistant suggestions and actual tool actions.
- **Mission plan:** structured steps, dependencies if needed, expected outputs, approval requirements, and a clear start/review action.
- **Execution:** step statuses must derive from real backend state. Clearly show running, waiting for approval, completed, failed, cancelled, and partially completed states as supported.
- **Results workspace:** prioritize the artifact. Provide supported edit, revise/regenerate, download, and share actions without implying unavailable features.
- **History / projects:** readable list or grouped timeline, useful metadata, search if implemented, and clear empty states.
- **Settings:** simple grouped rows for profile/account, appearance, connected tools, privacy, and logout. Show only capabilities that exist.
- **Dialogs and bottom sheets:** reserve for focused decisions, confirmations, or secondary actions; avoid stacking multiple overlays.

## 6. New-user journey

1. Welcome screen introduces Tusk.ai in one sentence.
2. User chooses Get started or Log in.
3. Account flow uses only configured, real authentication methods.
4. Explain verification and recovery clearly; never simulate them.
5. Give a concise, skippable product introduction when allowed.
6. Land the user in a simple first-chat screen with useful text-only suggestions.
7. Explain Mission Mode when the user first encounters a plan or execution step, rather than front-loading every detail.
8. Returning users can access new chat, history, missions/projects, settings, connected-tool state, privacy controls, and logout.

If a guest experience is supported securely, consider letting users try a first conversation before registration. If an account is required, state the reason plainly. Do not persist sensitive or valuable work to an anonymous account without a documented migration/ownership design.

## 7. Authentication requirements

The planned account lifecycle for a public multi-user release includes email registration, email verification, login, password reset, secure session persistence/refresh/revocation, logout, account ownership enforcement, and account/data deletion. Google sign-in is optional. It must be hidden or clearly unavailable until provider setup, backend verification, secure token handling, and tests are complete.

A screen is not a functioning authentication feature. Do not claim auth is implemented unless the client, backend/provider, error paths, secure storage, and relevant tests work end to end. Keep provider secrets out of the APK.

## 8. Accessibility and feedback

- Meet WCAG-style contrast targets where practical: aim for at least 4.5:1 for normal text and 3:1 for large text and essential UI graphics.
- Support system font scaling and screen readers.
- Provide accessible labels, meaningful focus order, visible focus/selection, and touch targets appropriate to Android guidance.
- Do not communicate status by color alone; use text labels and professional icons.
- Design loading, empty, offline, permission-denied, validation, retry, partial-completion, and failure states.
- Motion should be subtle, purposeful, and respectful of reduced-motion preferences where supported.

## 9. Product trust

- Never fabricate AI progress, execution, tool results, generated artifacts, or delivery.
- Clearly distinguish drafts from content actually sent or published.
- Obtain explicit approval immediately before consequential external actions.
- Do not expose connected tools as active unless the connection is real and authorized.
- Do not place hackathon, competition, sponsor, or judging references in customer-facing UI or metadata.

## 10. Design acceptance checklist

- [ ] Black, white, and neutral grey palette only.
- [ ] Light, dark, and system theme behavior is consistent.
- [ ] No emojis anywhere in UI or app-authored sample/demo content.
- [ ] Iconography is consistent, purposeful, and accessible.
- [ ] Layouts fit their screen purpose rather than repeating generic cards.
- [ ] Welcome, auth entry, onboarding, first chat, history, and settings are specified.
- [ ] Authentication capabilities are accurately labelled and backed by real integrations.
- [ ] Accessibility, loading, empty, error, offline, and partial-completion states are considered.
- [ ] No event-specific customer-facing content.

## 11. Effortless usability and modern interaction details

### Usability principle
Design for first-time users, including people with little technical knowledge. A user should quickly understand where to start, how to describe a goal, what Tusk.ai is doing, and where to find the result. Prefer the smallest clear solution over a feature-heavy interface.

- Keep one obvious primary action per screen and make the composer the dominant action on chat screens.
- Minimize taps, screens, forms, menus, onboarding questions, and permissions. Ask only essential clarifying questions, one at a time where possible.
- Use plain language, sensible defaults, visible recovery actions, and contextual controls. Hide advanced options until relevant.
- Do not make users understand agents, providers, workflows, or technical integrations to use the product.
- Avoid dashboard overload, excessive cards, nested menus, crowded toolbars, and decorative complexity.

### Cold-launch wordmark animation
- On a full cold launch, animate a refined light sweep across the Tusk.ai wordmark for approximately one second.
- Keep the animation original, monochrome, smooth, and cinematic, inspired by the general idea of a premium film-logo shine only. Do not copy Sony's logo, assets, timing design, or other proprietary branding.
- Do not replay unnecessarily on navigation or every app resume. Avoid blocking interaction longer than necessary and respect reduced-motion preferences.
- The animation must not compromise startup reliability or accessibility; provide a reduced-motion/static alternative.

### Voice interaction
- Place an obvious, accessible circular microphone/voice control near the composer without competing with the send action.
- Clearly distinguish idle, requesting permission, listening, transcribing, speaking, cancelled, and failed states.
- Use real supported Android/platform speech APIs or a configured service. Never simulate microphone activity, waveform input, or transcription.
- Provide useful live/final transcription where supported, allow users to review or correct text before sending, and make cancellation straightforward.
- Handle denied permissions, unavailable services, no speech detected, network loss, and interruptions with concise recovery guidance. Typing must remain available at all times.

### Modern micro-interactions
- Smooth message streaming where supported, a real stop-generation control, and retry after failures.
- Contextual copy/share actions and artifact actions only when supported by the content and platform.
- Clear tool-use and mission status indicators backed by real state; no fake thinking or progress.
- Polished composer expansion, keyboard insets, focus, send behavior, and scrolling.
- Subtle transitions and optional Android haptics for meaningful actions, never constant or distracting feedback.
- Responsive layouts, clear connectivity feedback, and reliable empty/loading/error/partial-result states.
- Respect system reduced-motion and accessibility preferences. All controls need accessible names, adequate touch targets, and screen-reader semantics.

### Mandatory simplicity review
Before accepting a screen, verify that a first-time user can identify the main action immediately; remove unnecessary taps, questions, fields, and controls; confirm every visible control works; and ensure errors have an obvious recovery path. If a design feels complicated, simplify it before adding features.
