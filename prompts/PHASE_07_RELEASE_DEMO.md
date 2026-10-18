# Phase 7 — Release and Demo

Read `PRD.md`, `TESTING.md`, `SECURITY.md`, and all current known gaps.

Prepare a reproducible release candidate:
- Run formatter/linter/static analysis, unit/integration/UI tests available in the stack.
- Build and verify the APK (and AAB only if appropriate).
- Test the primary workflow on emulator/device, including one controlled failure.
- Verify no secrets are present in the repository or client artifact.
- Update README and DEVELOPMENT.md with verified commands and limitations.
- Prepare a short demo script that follows a real successful workflow and distinguishes configured capabilities from planned ones.
- Capture only real, current screenshots; do not fabricate external service results or user testimonials.

Report the artifact path, build/test evidence, known limitations, and a go/no-go recommendation.
