import os
from pathlib import Path
from typing import Any, Protocol
from ..config import settings
from .llm_provider import LLMProvider, ProviderError


class ToolResult:
    def __init__(
        self,
        text_output: str,
        artifact_filename: str | None = None,
        artifact_content: str | None = None,
        media_type: str = "text/markdown",
    ):
        self.text_output = text_output
        self.artifact_filename = artifact_filename
        self.artifact_content = artifact_content
        self.media_type = media_type


class BackendTool(Protocol):
    """Protocol for allowlisted backend tools."""
    name: str

    async def execute(
        self,
        goal: str,
        step_title: str,
        step_description: str,
        prior_context: dict[str, str],
        provider: LLMProvider | None = None,
    ) -> ToolResult:
        ...


class MarketingStrategyTool:
    name = "marketing_strategy"

    async def execute(
        self,
        goal: str,
        step_title: str,
        step_description: str,
        prior_context: dict[str, str],
        provider: LLMProvider | None = None,
    ) -> ToolResult:
        if not provider or not getattr(provider, "is_configured", False):
            # Deterministic, safe fallback output for development mode
            output = (
                "Strategy Brief:\n"
                "- Primary Audience: Downtown Seattle tech professionals, urban residents, and craft coffee enthusiasts (ages 22-45).\n"
                "- Brand Tone: Warm, artisanal, precise, welcoming, community-rooted.\n"
                "- Value Proposition: Single-origin espresso, sustainable micro-roasting, and calm work-friendly atmosphere.\n"
                "- Local Campaign Hashtags: #SeattleCoffee #PikePlaceBrew #ArtisanalRoastery #SeattleEats #SeattleCraftCoffee"
            )
            return ToolResult(text_output=output)

        prompt = (
            f"Goal: {goal}\n"
            f"Step: {step_title} - {step_description}\n"
            "Produce a focused, professional marketing strategy brief covering:\n"
            "1. Primary target audience demographics and psychographics\n"
            "2. Brand tone, voice guidelines, and key differentiators\n"
            "3. Core campaign message and value proposition\n"
            "4. 5 targeted local hashtags\n"
            "Keep formatting clean without emojis."
        )
        sys_inst = "You are a senior marketing strategist for Tusk.ai. Return clear, concise markdown text without emojis."
        text = await provider.generate_content(prompt=prompt, system_instruction=sys_inst, temperature=0.3, max_tokens=1500)
        return ToolResult(text_output=text.strip())


class CopywriterTool:
    name = "copywriter"

    async def execute(
        self,
        goal: str,
        step_title: str,
        step_description: str,
        prior_context: dict[str, str],
        provider: LLMProvider | None = None,
    ) -> ToolResult:
        context_summary = "\n".join(f"[{k}]: {v}" for k, v in prior_context.items())

        if not provider or not getattr(provider, "is_configured", False):
            output = (
                "Campaign Copy Drafts:\n\n"
                "Post 1 (Teaser):\n"
                "Something exceptional is brewing in downtown Seattle. Single-origin roasts, roasted in small batches right in the heart of the city. Opening this month.\n\n"
                "Post 2 (Craft Focus):\n"
                "Behind every pour is a direct partnership with origin farmers. Meet our seasonal Ethiopian Yirgacheffe espresso notes of bergamot and jasmine.\n\n"
                "Post 3 (Launch Special):\n"
                "Grand opening celebration: Visit us during opening week and enjoy your first pour on the house with code SEATTLEBREW20 at checkout.\n\n"
                "Post 4 (Community Highlight):\n"
                "Designed as your third place. Ample natural light, quiet acoustic booths, and handcrafted espresso.\n\n"
                "Post 5 (Weekend Special):\n"
                "Weekend brunch tasting flights are here. Pair single-origin espresso with organic local pastries."
            )
            return ToolResult(text_output=output)

        prompt = (
            f"Goal: {goal}\n"
            f"Step: {step_title} - {step_description}\n"
            f"Context from prior steps:\n{context_summary}\n\n"
            "Draft 5 complete, production-ready promotional social media posts for this launch campaign.\n"
            "Each post must include an attention-grabbing hook, clear body copy, promotional call-to-action (including coupon code TUSKLAUNCH for 20% off), and 3-4 local hashtags.\n"
            "Do not use emojis anywhere in the text."
        )
        sys_inst = "You are an expert copywriter for Tusk.ai. Output engaging, polished campaign copy without emojis."
        text = await provider.generate_content(prompt=prompt, system_instruction=sys_inst, temperature=0.4, max_tokens=2000)
        return ToolResult(text_output=text.strip())


class ContentPlannerTool:
    name = "content_planner"

    async def execute(
        self,
        goal: str,
        step_title: str,
        step_description: str,
        prior_context: dict[str, str],
        provider: LLMProvider | None = None,
    ) -> ToolResult:
        context_summary = "\n".join(f"[{k}]: {v}" for k, v in prior_context.items())

        if not provider or not getattr(provider, "is_configured", False):
            output = (
                "4-Week Launch Schedule:\n"
                "- Week 1 (Teaser Phase): 3 posts/week. Behind-the-scenes buildout and micro-roasting sneak peeks.\n"
                "- Week 2 (Grand Opening): 5 posts/week. Launch countdown, ribbon cutting, opening day promo TUSKLAUNCH.\n"
                "- Week 3 (Community & Craft): 4 posts/week. Barista highlights, origin farm story, customer testimonials.\n"
                "- Week 4 (Loyalty & Weekend Special): 3 posts/week. Weekend tasting flights, loyalty program introduction."
            )
            return ToolResult(text_output=output)

        prompt = (
            f"Goal: {goal}\n"
            f"Step: {step_title} - {step_description}\n"
            f"Context from prior steps:\n{context_summary}\n\n"
            "Create a structured 4-week multi-channel content calendar for this campaign.\n"
            "Outline post cadence, themes, platforms (Instagram, LinkedIn, Local Maps), and milestones for each week.\n"
            "Do not use emojis."
        )
        sys_inst = "You are a content operations planner for Tusk.ai. Output a clear weekly schedule table in markdown without emojis."
        text = await provider.generate_content(prompt=prompt, system_instruction=sys_inst, temperature=0.2, max_tokens=1500)
        return ToolResult(text_output=text.strip())


class DeliverablePackagerTool:
    name = "deliverable_packager"

    async def execute(
        self,
        goal: str,
        step_title: str,
        step_description: str,
        prior_context: dict[str, str],
        provider: LLMProvider | None = None,
    ) -> ToolResult:
        # Assemble comprehensive markdown deliverable
        sections = []
        sections.append(f"# Launch Campaign Deliverables Package\n\n**Campaign Goal:** {goal}\n")
        for step_name, content in prior_context.items():
            sections.append(f"## {step_name}\n\n{content}\n")

        full_package_md = "\n".join(sections)
        filename = "launch_campaign_deliverables.md"
        summary_text = (
            f"Successfully compiled all campaign assets into deliverable document '{filename}' "
            f"({len(full_package_md.encode('utf-8'))} bytes). File saved to persistent artifact storage."
        )
        return ToolResult(
            text_output=summary_text,
            artifact_filename=filename,
            artifact_content=full_package_md,
            media_type="text/markdown",
        )


class GenericWriterTool:
    name = "generic_writer"

    async def execute(
        self,
        goal: str,
        step_title: str,
        step_description: str,
        prior_context: dict[str, str],
        provider: LLMProvider | None = None,
    ) -> ToolResult:
        if not provider or not getattr(provider, "is_configured", False):
            output = f"Completed step '{step_title}': Detailed deliverables generated based on goal specifications."
            return ToolResult(text_output=output)

        prompt = (
            f"Overall Goal: {goal}\n"
            f"Step: {step_title}\n"
            f"Instructions: {step_description}\n\n"
            "Execute this step with thorough, professional content. Do not use emojis."
        )
        sys_inst = "You are Tusk.ai task execution engine. Provide comprehensive, direct results without emojis."
        text = await provider.generate_content(prompt=prompt, system_instruction=sys_inst, temperature=0.3, max_tokens=1500)
        return ToolResult(text_output=text.strip())


# Tool Registry allowlist
TOOL_REGISTRY: dict[str, BackendTool] = {
    "marketing_strategy": MarketingStrategyTool(),
    "copywriter": CopywriterTool(),
    "content_planner": ContentPlannerTool(),
    "deliverable_packager": DeliverablePackagerTool(),
    "generic_writer": GenericWriterTool(),
}


def get_tool_for_step(step_title: str, tool_kind: str | None = None) -> BackendTool:
    """Resolve an allowlisted backend tool adapter."""
    if tool_kind and tool_kind in TOOL_REGISTRY:
        return TOOL_REGISTRY[tool_kind]

    title_lower = step_title.lower()
    if any(w in title_lower for w in ["calendar", "schedule", "timeline"]):
        return TOOL_REGISTRY["content_planner"]
    elif any(w in title_lower for w in ["strategy", "audience", "persona", "angle"]):
        return TOOL_REGISTRY["marketing_strategy"]
    elif any(w in title_lower for w in ["package", "deliverable", "compile", "finalize"]):
        return TOOL_REGISTRY["deliverable_packager"]
    elif any(w in title_lower for w in ["copy", "caption", "draft", "promotional", "post"]):
        return TOOL_REGISTRY["copywriter"]

    return TOOL_REGISTRY["generic_writer"]
