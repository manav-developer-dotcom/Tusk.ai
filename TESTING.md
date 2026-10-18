# Tusk.ai — Testing Strategy

## Testing principles

- Tests must validate behavior, not just that screens render.
- Do not claim tests passed unless the commands were executed and results observed.
- Keep provider calls mocked in unit tests; reserve real provider calls for controlled integration/smoke tests.
- Test failure paths and partial completion as first-class behavior.

## Required layers

### Unit tests
- Mission state transitions and invalid transitions.
- Plan validation and tool-argument validation.
- Approval binding and expiry behavior.
- Retry eligibility and idempotency logic.
- Error mapping and status-to-UI mapping.

### Integration tests
- API validation and error responses.
- Mission creation and persistence.
- Execute/status/result lifecycle.
- Artifact ownership and access checks.
- Provider adapter timeout/rate-limit handling.
- Protocol adapter mapping to shared mission services.

### Android UI tests
- Home mission submission.
- Plan review and approval.
- Running, completed, partially completed, and failed states.
- Retry and empty-history states.
- Network unavailable and backend unavailable states.
- Accessibility labels and key navigation flows where supported.

### Manual smoke tests
- Install and launch APK on emulator/device.
- Complete one real text-generation mission.
- Complete one real image-generation mission when configured.
- Verify result can be reopened.
- Cause a controlled failure and verify it is not shown as success.
- Verify no unapproved external side effect can occur.
- Test slow and interrupted network conditions.

## Release gate

Before marking a phase complete:
1. Run formatter/linter/static checks available in the selected stack.
2. Run relevant unit and integration tests.
3. Build the app/backend components touched by the phase.
4. Record exact commands and outcomes.
5. List skipped checks and explain why.
6. Fix blocking failures or document an explicit, approved deferral.

## Test data

- Use synthetic data without real personal information.
- Never put production secrets in fixtures or screenshots.
- Label demo-only data clearly in the interface.
