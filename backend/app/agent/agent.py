"""Tusk.ai external agent factory and execution runner."""

import asyncio
import logging
from typing import Optional
from uagents import Agent, Context

from ..config import settings
from .acp import tusk_chat_protocol
from .protocol import tusk_mission_protocol

logger = logging.getLogger("tusk.agent")


async def register_with_agentverse_token(agent: Agent, token: str) -> bool:
    """Register agent identity, endpoints, and protocols with Agentverse using an API key or user token."""
    from uagents.agent import AgentverseConnectRequest, RegistrationRequest, register_in_agentverse

    clean_token = token.strip()
    if not clean_token:
        return False

    try:
        req = AgentverseConnectRequest(
            user_token=clean_token,
            agent_type="mailbox",
        )
        profile = agent._build_registration_profile()
        registration_data = RegistrationRequest(
            address=agent.address,
            name=agent.name,
            handle=agent._handle,
            url=None,
            profile=profile,
            endpoints=agent._endpoints,
            protocols=list(agent.protocols.keys()),
            metadata=agent.metadata,
        )
        res = await register_in_agentverse(
            request=req,
            identity=agent._identity,
            prefix=agent._prefix,
            agentverse=agent._agentverse,
            agent_details=registration_data,
        )
        if res.success:
            logger.info("Successfully registered agent '%s' on Agentverse.", agent.name)
            return True
        else:
            logger.warning("Agentverse registration check returned: %s", res.detail)
            return False
    except Exception as e:
        logger.warning("Failed to connect to Agentverse during registration: %s", e)
        return False


def create_tusk_agent(
    name: Optional[str] = None,
    port: Optional[int] = None,
    seed: Optional[str] = None,
    endpoint: Optional[str] = None,
    mailbox: Optional[str] = None,
) -> Agent:
    """Create and configure the Tusk.ai external agent with mission and chat protocols."""
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
        # In modern uAgents, mailbox parameter must be boolean True to enable MailboxClient
        agent_kwargs["mailbox"] = True

    # Ensure an active event loop exists for uAgents in Python 3.12+
    try:
        current_loop = asyncio.get_event_loop()
    except RuntimeError:
        current_loop = asyncio.new_event_loop()
        asyncio.set_event_loop(current_loop)
    agent_kwargs["loop"] = current_loop

    agent = Agent(**agent_kwargs)
    agent.include(tusk_mission_protocol, publish_manifest=True)
    agent.include(tusk_chat_protocol, publish_manifest=True)

    # If a specific API key or token was provided, register with Agentverse on startup
    if agent_mailbox:
        token_candidate = str(agent_mailbox).strip()
        if token_candidate.lower() not in ("true", "1", "yes", "enabled"):
            @agent.on_event("startup")
            async def _on_startup_register(ctx: Context):
                await register_with_agentverse_token(agent, token_candidate)

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
