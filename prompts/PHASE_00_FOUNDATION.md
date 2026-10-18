# Phase 0 — Tusk.ai Foundation

Read `AGENTS.md`, `PRD.md`, `architecture.md`, `ROADMAP.md`, `API_CONTRACT.md`, `SECURITY.md`, and `PRODUCT_DECISIONS.md` before acting.

This phase is planning and repository discovery only. Do not implement the full app or backend.

1. Inspect the repository and installed tools/SDKs. Report what is actually available; do not assume a framework.
2. Recommend an Android stack and backend stack suitable for a beginner-maintainable, startup-ready product and reliable APK builds. Compare realistic alternatives briefly.
3. Confirm a modular architecture in which Android and external agent interfaces reuse the same mission service. Keep secrets server-side.
4. Propose the repository/folder structure and exact local setup, test, lint, and APK build commands.
5. Identify provider, database, storage, hosting, authentication, and external protocol prerequisites. Do not ask me to paste secrets into chat.
6. Review the docs for contradictions, resolve only obvious wording inconsistencies, and list product/architecture questions that require a decision.
7. Create or update one concise ADR for the recommended stack once the repository/environment has been inspected. Mark it Proposed if not yet approved.

Hard constraints:
- Product name: `Tusk.ai`.
- No event, competition, sponsor, or judging references in customer-facing app content or branding.
- No fake AI output, task progress, or success claims.
- No SMS or phone calls in the initial scope.
- Do not start Phase 1 until the proposed stack and plan have been reviewed.

Final report: environment findings; recommended stack and trade-offs; proposed folder structure; setup/build/test commands; prerequisites; risks/open questions; exact next step. Keep the report concise and evidence-based.
