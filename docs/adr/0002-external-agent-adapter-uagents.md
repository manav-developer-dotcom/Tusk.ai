# ADR 0002: External Agent Adapter via uAgents (Fetch.ai)

- Status: Accepted
- Date: 2026-10-21

## Context

Phase 5 required a thin external agent protocol adapter so that Tusk.ai mission
capabilities could be invoked through the Fetch.ai / Agentverse discovery and
messaging infrastructure, without duplicating planning, approval, execution, or
persistence logic from the Android app path.

Python/FastAPI was selected in Phase 2.5 specifically to enable `uagents` interoperability.
The `uagents` library ships its own async event loop, which conflicts with running
inside an existing FastAPI/uvicorn process.

## Decision

Implement `backend/app/agent/` as a separate, thin protocol adapter package:

- `messages.py` — typed `uagents.Model` request/response schemas.
- `protocol.py` — `tusk_mission_protocol` Protocol with message handlers
  that delegate directly to `MissionService`.
- `agent.py` — factory (`create_tusk_agent`) and entry-point (`start_agent_service`)
  for running the agent as a separate process.

The agent runs on port 8001 (configurable). FastAPI continues on port 8000.
External agent addresses map to isolated `agent:<address>` session IDs, preserving
the same ownership boundary as HTTP session headers.

## Alternatives considered

- **REST proxy inside FastAPI**: Rejected — would require re-implementing session
  resolution, error mapping, and approval checks, diverging from the shared service.
- **Embedding the agent inside the FastAPI lifespan**: Rejected — `uagents` runs
  its own `asyncio` event loop and creates a conflict when nested under uvicorn.
- **A second standalone microservice**: Rejected — unnecessary at current scale;
  the shared in-process SQLite connection is sufficient for single-node deployment.

## Consequences

- The shared `MissionService` is the single source of truth for all mission state,
  regardless of whether the caller is the Android app or an external agent.
- Approval gates, rate limits, and session isolation cannot be bypassed by external callers.
- Agentverse cloud discovery requires `TUSK_AGENT_MAILBOX_KEY` to be configured;
  the agent operates in LAN-only mode without it.
- A durable queue may be needed in a future phase if long-running execution tasks
  become unreliable for the external agent's timeout window.
