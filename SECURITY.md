# Tusk.ai — Security and Privacy Baseline

This document is an engineering baseline, not legal advice or a substitute for a security review.

## Non-negotiable rules

- Never commit API keys, signing keys, passwords, access tokens, or production credentials.
- Never embed privileged provider credentials in the Android APK.
- Use environment variables or a deployment secret manager on the backend.
- Keep `.env` files out of version control; provide `.env.example` with placeholder values only.
- Rotate any credential that is accidentally exposed.
- Do not log secrets, authorization headers, full sensitive prompts, or private artifact URLs.

## Authentication and authorization

- Define ownership checks for every mission and artifact.
- Do not trust client-supplied user IDs or ownership fields.
- Deny by default when authorization cannot be established.
- Use short-lived credentials where supported and secure transport.
- Apply rate limits and request-size limits at public boundaries.
- Add abuse protections before public access.

## Tool execution and approvals

- Treat model output and user-provided content as untrusted input.
- Validate tool arguments against typed schemas and allowlists.
- Separate planning from execution.
- Require explicit, action-specific approval for sending, publishing, purchasing, deleting, or other consequential operations.
- Bind approvals to the actual action payload; invalidate approval if the payload changes.
- Use idempotency and duplicate protection for side effects where possible.
- Do not let generated instructions bypass policy, authorization, or approval checks.

## Data minimization

- Store only data required for product behavior.
- Define retention and deletion behavior before production launch.
- Avoid storing secrets or payment data in mission context.
- Redact or minimize personally identifying information in logs.
- Restrict artifact access and use expiring links where suitable.
- Document model/provider data handling and retention before selecting production providers.

## Mobile client

- Assume the APK can be inspected and modified.
- Do not place backend admin keys, provider API keys, or permanent privileged tokens in client code or assets.
- Validate security-sensitive operations on the server.
- Use platform-secure storage for user credentials when applicable.
- Treat client-side feature flags as presentation controls, not authorization.

## Build and supply chain

- Pin or constrain dependency versions appropriately.
- Run available static analysis, dependency audits, and secret scanning.
- Keep signing keys out of source control and build logs.
- Separate debug and release configurations.
- Document how release artifacts are built and signed.

## Incident response

Before public launch, document how to revoke credentials, disable a compromised integration, inspect sanitized audit events, communicate an incident, and restore service.
