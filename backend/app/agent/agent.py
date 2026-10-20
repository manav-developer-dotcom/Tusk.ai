"""Tusk.ai external agent factory and execution runner."""

import logging
from typing import Optional
from uagents import Agent

from ..config import settings
from .protocol import tusk_mission_protocol

logger = logging.getLogger("tusk.agent")


def create_tusk_agent(
    name: Optional[str] = None,
    port: Optional[int] = None,
    seed: Optional[str] = None,
    endpoint: Optional[str] = None,
    mailbox: Optional[str] = None,
) -> Agent:
    """Create and configure the Tusk.ai external agent with tusk_mission_protocol."""
    agent_name = name or settings.agent_name
    agent_port = port or settings.agent_port
    agent_seed = seed or settings.agent_seed
    agent_endpoint = endpoint or settings.agent_endpoint
    agent_mailbox = mailbox or settings.agent_mailbox_key

    agent_kwargs = {
        "name": agent_name,
        "port": agent_port,
    }
    if agent_seed:
        agent_kwargs["seed"] = agent_seed
    if agent_endpoint:
        agent_kwargs["endpoint"] = [agent_endpoint] if isinstance(agent_endpoint, str) else agent_endpoint
    if agent_mailbox:
        agent_kwargs["mailbox"] = agent_mailbox

    agent = Agent(**agent_kwargs)
    agent.include(tusk_mission_protocol, publish_manifest=True)

    logger.info(
        "Created Tusk.ai agent '%s' (Address: %s, Port: %d)",
        agent.name,
        agent.address,
        agent_port,
    )
    return agent


def start_agent_service():
    """Start standalone external agent listening service."""
    agent = create_tusk_agent()
    print("==================================================")
    print(f" Tusk.ai External Action Agent (uAgents)")
    print(f" Name    : {agent.name}")
    print(f" Address : {agent.address}")
    print(f" Port    : {settings.agent_port}")
    if settings.agent_mailbox_key:
        print(" Mailbox : Configured for Agentverse discovery")
    else:
        print(" Mailbox : Local/LAN mode (Agentverse key not set)")
    print("==================================================")
    agent.run()


if __name__ == "__main__":
    start_agent_service()
