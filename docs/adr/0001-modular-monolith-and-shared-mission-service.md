# ADR 0001: Modular Backend and Shared Mission Service

- Status: Proposed
- Date: 2026-10-16

## Context

Tusk.ai is intended to serve an Android client and potentially external agent interfaces. The project must be manageable for a small team, protect credentials, and avoid duplicating mission execution logic.

## Decision

Start with a modular backend and a shared mission application service. Keep planner, approval/policy logic, orchestration, tool adapters, persistence, and artifact handling behind explicit module boundaries. External protocol adapters call the shared service. Do not begin with independently deployed microservices or multiple autonomous agents.

## Alternatives considered

- Put provider calls directly in the Android app: rejected because privileged credentials cannot be protected in a distributed client and execution would be tightly coupled to one interface.
- Build microservices immediately: rejected because it adds deployment and operational overhead before scale requirements are known.
- Implement separate logic for each client: rejected because behavior, approvals, and result states could diverge.

## Consequences

- The backend becomes the authoritative source for mission state and execution.
- Modules can be extracted later if scale or ownership boundaries justify it.
- Initial implementation must keep module boundaries clean even if deployed as one service.
- A durable queue/worker may be added if long-running tasks cannot be handled reliably by the initial runtime.
