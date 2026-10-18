# External Agent Interoperability

This document defines an integration boundary, not product branding. External platforms and protocol-specific setup must not appear in customer-facing app copy.

## Objective

Allow supported external agent interfaces to discover and use Tusk.ai's real capabilities while reusing the same mission service as the Android app.

## Requirements

- Implement the required agent protocol using its current official specification and SDK.
- Register the agent in the relevant discovery directory/platform and document the public profile URL in release notes when applicable.
- Make the agent usable directly through the supported external conversation interface.
- Demonstrate a complete primary workflow through that interface without requiring the Android app.
- Use the same planner, policy gate, execution engine, task records, and tool adapters as the Android app wherever practical.
- Never create a second implementation that simulates results separately from the core service.
- Expose a small set of clear, typed actions and explain required inputs.
- Handle invalid inputs, timeouts, partial completion, and tool failures with honest messages.
- Do not permit external callers to bypass approvals, authorization, rate limits, or safety controls.
- Keep platform credentials in backend secret storage and out of public source control.
- Provide local test instructions and a reproducible end-to-end verification checklist.

## Implementation checklist

- [ ] Confirm current protocol documentation, SDK, and runtime constraints.
- [ ] Define the agent's capabilities and input/output schema.
- [ ] Map protocol requests to the shared mission application service.
- [ ] Implement and test error/status mapping.
- [ ] Configure discovery registration.
- [ ] Verify direct use through the supported external interface.
- [ ] Publish source repository and setup instructions when ready.
- [ ] Record demo links and verification evidence outside the app's customer-facing UI.

## Out of scope

- Event-specific language, branding, onboarding, or UI.
- A parallel mock implementation that claims to have executed real tools.
- Unapproved external side effects.
