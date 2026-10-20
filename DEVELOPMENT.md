# Tusk.ai — Development Guide

## Status

- **Phase 0 (Foundation & Audit):** Completed. Stack decisions documented.
- **Phase 1 (App Shell & Design System):** Completed. Strict monochrome system, cold-launch wordmark shine, navigation skeleton, and APK workflow.
- **Phase 2 (Core Mission UX):** Completed. Natural-language goal intake, interactive clarification flow, isolated rule-based local planner, plan review and approval flow, state machine, and local persistence.
- **Phase 2.5 (Pre-Backend Environment & Repository Foundation):** Completed. Git version control initialized, clean baseline commit created, Python 3.12.10 installed & verified, and Phase 3 API contract audited.
- **Phase 3 (Backend Foundation & Task Persistence):** Completed. FastAPI/Python 3.12 backend implemented under `backend/` with SQLite persistence across restarts, session isolation, plan generation, structured errors, correlation tracing, and Flutter client API integration with platform-aware URL routing.
- **Phase 4 (Real AI Planning & Task Execution):** Completed. Real Gemini API integration (`gemini-3.8-flash`) for structured mission planning, single-question clarification, backend execution engine with allowlisted tools (`marketing_strategy`, `copywriter`, `content_planner`, `deliverable_packager`, `generic_writer`), persistent artifact storage, and full Flutter UI for execution and deliverable viewing.
- **Phase 5 (External Agent Interoperability):** Completed. Thin uAgents (Fetch.ai) protocol adapter implemented under `backend/app/agent/`. The adapter maps external agent cryptographic addresses to isolated session IDs and routes all requests through the shared `MissionService` (same planning, approval gate, execution engine, and artifact persistence as the Android app). 9 automated adapter tests pass covering protocol metadata, blank-goal rejection, structured planning, clarification, approval-gate enforcement, full create→approve→execute→artifact workflow, cross-agent session isolation, and idempotency.

## Verified Environment & Prerequisites

- **Client Framework:** Flutter `3.32.2` (channel stable)
- **Language / SDK:** Dart `3.8.1` (stable)
- **Android Platform:** Android SDK (API 34/35), Gradle 8.3+ via wrapper
- **Version Control:** Git (initialized with root `.gitignore` excluding build outputs, `.venv`, `.env`, and database files)
- **Host OS:** Windows (PowerShell)
- **Backend Runtime:** Python `3.12.10` (64-bit), pip `25.0.1` (verified at `C:\Users\Test\AppData\Local\Programs\Python\Python312\python.exe`)
- **Other Runtimes:** Node.js (`v22`) available on system

## Engineering Workflow & Verified Commands

### 1. Backend Service Setup & Execution
Navigate to `backend/`:
```powershell
cd backend
```

- **Set up virtual environment & install dependencies:**
  ```powershell
  python -m venv .venv
  .venv\Scripts\activate
  pip install -r requirements.txt
  ```

- **Run backend test suite (35 automated tests):**
  ```powershell
  .venv\Scripts\pytest tests -v
  ```

- **Configure Gemini API key (required for real AI planning & execution):**
  ```powershell
  # Create backend/.env from example:
  Copy-Item backend\.env.example backend\.env
  # Then edit backend/.env and set:
  # GEMINI_API_KEY=your_key_here
  ```
  Without a key the backend falls back to the rule-based dev adapter (labelled in the UI).

- **Configure external agent settings (optional):**
  ```powershell
  # In backend/.env, set optional agent config:
  # TUSK_AGENT_NAME=tusk_action_agent
  # TUSK_AGENT_PORT=8001
  # TUSK_AGENT_SEED="your secret mnemonic phrase"   # for deterministic address
  # TUSK_AGENT_MAILBOX_KEY="your_mailbox_api_key"  # for Agentverse cloud discovery
  ```

- **Start backend server locally:**
  ```powershell
  .venv\Scripts\python run.py
  # Alternatively:
  # .venv\Scripts\uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
  ```
  Health check is accessible at: `http://127.0.0.1:8000/health`
  The health response also includes agent adapter status (`agent.enabled`, `agent.name`, `agent.port`).

- **Start external agent service (separate process from FastAPI):**
  ```powershell
  # Default (port 8001):
  powershell -ExecutionPolicy Bypass -File scripts/start_agent.ps1
  # Custom port/name:
  powershell -ExecutionPolicy Bypass -File scripts/start_agent.ps1 -AgentPort 8002 -AgentName my_tusk_agent
  ```
  Agent address is logged on startup. See `backend/app/agent/` for protocol message schemas.

- **Run backend test suite (35 automated tests):**
  ```powershell
  .venv\Scripts\pytest tests -v
  ```

### 2. Flutter Client Verification
Navigate to `app/`:
```powershell
cd app
```

- **Run all automated unit and integration tests (32 tests):**
  ```powershell
  flutter test
  ```
- **Run static analysis and linter (0 issues):**
  ```powershell
  flutter analyze
  ```
- **Configure API Base URL:**
  - Android Emulator: `http://10.0.2.2:8000` (automatically routed)
  - Windows Desktop / Web: `http://127.0.0.1:8000` (automatically routed)
  - Custom target: configure in Settings screen or pass `--dart-define=API_BASE_URL=http://<host>:8000`
- **Launch application (emulator or physical device):**
  ```powershell
  flutter run
  ```

### 3. Local Android APK Build
Build the standalone debug APK and copy it to `artifacts/apk/`:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_apk.ps1
```
Verified output location: `artifacts/apk/TuskAI-debug.apk`

## Repository Structure

```text
Husk.ai/
├── app/                  # Flutter client source code and Android project
│   ├── lib/              # Core theme, widgets, and feature modules
│   └── test/             # Unit and widget test suites
├── artifacts/            # Generated outputs (APKs, reports; binaries gitignored)
├── docs/                 # Architectural Decision Records (ADRs) and integration docs
├── prompts/              # Phased execution prompts (Phase 00 through Phase 07)
├── scripts/              # Build and asset generation PowerShell scripts
├── AGENTS.md             # Antigravity operating rules & non-negotiables
├── API_CONTRACT.md       # Client-backend API specification
├── architecture.md       # Authoritative system architecture
├── DESIGN_SYSTEM.md      # Visual tokens, UX, and accessibility requirements
├── DEVELOPMENT.md        # Local setup and engineering workflow (this document)
├── PRD.md                # Product Requirements Document
├── PRODUCT_DECISIONS.md  # Durable decision log and open questions
├── README.md             # Project overview and high-level status
├── ROADMAP.md            # Phased roadmap and exit criteria
├── SECURITY.md           # Security, authentication, and data privacy baseline
└── TESTING.md            # Quality strategy and test requirements
```

## Environment Separation & Secrets

- Secrets must **never** be committed to version control or embedded in the Flutter APK.
- Backend configuration must be managed through `.env` files (ignored by `.gitignore`) with `.env.example` containing only placeholder documentation.
- `GEMINI_API_KEY` (or `TUSK_GEMINI_API_KEY`) is loaded server-side only; it is never sent to the Flutter client or included in the APK.
- When no key is configured, the backend automatically falls back to the rule-based development adapter and labels itself clearly in the UI.
