# Phase 6 — Security, Reliability, and Release Hardening

Read `SECURITY.md`, `TESTING.md`, `ROADMAP.md`, and current known gaps.

Prioritize based on existing implementation:
- Authentication and mission/artifact ownership enforcement.
- Rate limits and abuse controls.
- Data retention/deletion behavior.
- Provider usage/cost tracking.
- Safe retries, idempotency, and approval-boundary tests.
- Privacy-safe logs and error reporting.
- Dependency and secret scanning where available.
- Debug/release configuration separation.
- Reproducible APK build and device/emulator smoke tests.

Do not add billing, teams, or a broad integration marketplace. Fix high-risk gaps before cosmetic work.

Run checks and report exact commands/results, security issues found/fixed, remaining risks, and release readiness. Do not claim legal or security certification.
