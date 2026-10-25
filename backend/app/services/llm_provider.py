import asyncio
import json
import logging
import random
from typing import Any, Protocol
import httpx

logger = logging.getLogger("tusk.provider")

# Maximum number of seconds we will wait in a single retry backoff.
# Quota exhaustion with Retry-After > this threshold signals a daily/hourly
# limit that will not resolve within a single request lifetime, so we raise
# immediately rather than blocking the caller.
_MAX_RETRY_BACKOFF_SECONDS = 60.0


def _parse_retry_after(resp: httpx.Response) -> float | None:
    """Return the Retry-After header value in seconds, or None if absent/unparseable."""
    raw = resp.headers.get("Retry-After") or resp.headers.get("retry-after")
    if raw is None:
        return None
    try:
        return float(raw)
    except ValueError:
        return None


def _extract_retry_delay_from_body(resp: httpx.Response) -> float | None:
    """
    Gemini API embeds a retryDelay field (e.g. '11072s') inside the JSON error
    body when quota is exhausted.  Parse and return seconds, or None.
    """
    try:
        body = resp.json()
        # Structure: {"error": {"details": [{"retryDelay": "11072s"}, ...]}}
        details = body.get("error", {}).get("details", [])
        for detail in details:
            raw = detail.get("retryDelay") or detail.get("retry_delay")
            if raw:
                numeric = str(raw).rstrip("s").strip()
                return float(numeric)
        # Also check top-level retryDelay key used in some responses
        raw = body.get("retryDelay")
        if raw:
            return float(str(raw).rstrip("s").strip())
    except Exception:
        pass
    return None


class ProviderError(Exception):
    """Base class for LLM provider errors with safe displayable messages."""
    def __init__(self, code: str, message: str, status_code: int = 502, retryable: bool = False):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.retryable = retryable


class ProviderConfigurationError(ProviderError):
    def __init__(self, message: str = "AI model provider is not configured. Missing API key."):
        super().__init__(
            code="PROVIDER_NOT_CONFIGURED",
            message=message,
            status_code=503,
            retryable=False,
        )


class ProviderAuthenticationError(ProviderError):
    def __init__(self, message: str = "Invalid or expired AI provider credentials."):
        super().__init__(
            code="PROVIDER_AUTH_ERROR",
            message=message,
            status_code=401,
            retryable=False,
        )


class ProviderRateLimitError(ProviderError):
    def __init__(self, message: str = "AI model provider rate limit reached. Please try again shortly."):
        super().__init__(
            code="PROVIDER_RATE_LIMIT",
            message=message,
            status_code=429,
            retryable=True,
        )


class ProviderTimeoutError(ProviderError):
    def __init__(self, message: str = "The AI generation service took too long to respond."):
        super().__init__(
            code="PROVIDER_TIMEOUT",
            message=message,
            status_code=504,
            retryable=True,
        )


class ProviderUnavailableError(ProviderError):
    def __init__(self, message: str = "The AI model service is currently unavailable. Please retry."):
        super().__init__(
            code="PROVIDER_UNAVAILABLE",
            message=message,
            status_code=503,
            retryable=True,
        )


class LLMProvider(Protocol):
    """Protocol defining the required interface for AI model generation."""

    async def generate_content(
        self,
        prompt: str,
        system_instruction: str | None = None,
        response_schema: dict[str, Any] | None = None,
        temperature: float = 0.2,
        max_tokens: int = 4096,
    ) -> str:
        """Generate text or structured content from a prompt."""
        ...


class GeminiProvider:
    """Official Google Gemini API adapter using asynchronous HTTP requests."""

    BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"

    def __init__(
        self,
        api_key: str | None,
        model: str = "gemini-3-flash-preview",
        timeout: float = 60.0,
        max_retries: int = 3,
    ):
        self._api_key = api_key
        self.model = model
        self.timeout = timeout
        self.max_retries = max_retries

    @property
    def is_configured(self) -> bool:
        return bool(self._api_key and self._api_key.strip())

    async def generate_content(
        self,
        prompt: str,
        system_instruction: str | None = None,
        response_schema: dict[str, Any] | None = None,
        temperature: float = 0.2,
        max_tokens: int = 4096,
    ) -> str:
        """Call Gemini generateContent endpoint with finite timeout and error handling."""
        if not self.is_configured:
            raise ProviderConfigurationError()

        url = f"{self.BASE_URL}/{self.model}:generateContent?key={self._api_key}"

        payload: dict[str, Any] = {
            "contents": [
                {"parts": [{"text": prompt}]}
            ],
            "generationConfig": {
                "temperature": temperature,
                "maxOutputTokens": max_tokens,
            }
        }

        if system_instruction:
            payload["systemInstruction"] = {
                "parts": [{"text": system_instruction}]
            }

        if response_schema:
            payload["generationConfig"]["responseMimeType"] = "application/json"
            payload["generationConfig"]["responseSchema"] = response_schema

        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

        attempts = 0
        while attempts <= self.max_retries:
            attempts += 1
            try:
                async with httpx.AsyncClient(timeout=self.timeout) as client:
                    resp = await client.post(url, json=payload, headers=headers)

                if resp.status_code == 200:
                    data = resp.json()
                    candidates = data.get("candidates", [])
                    if not candidates:
                        raise ProviderError(
                            code="EMPTY_GENERATION",
                            message="AI provider returned an empty response.",
                            status_code=502,
                        )
                    parts = candidates[0].get("content", {}).get("parts", [])
                    if not parts or "text" not in parts[0]:
                        raise ProviderError(
                            code="EMPTY_CONTENT",
                            message="AI provider response contained no text output.",
                            status_code=502,
                        )
                    return parts[0]["text"]

                # Handle specific error status codes
                if resp.status_code in (401, 403):
                    raise ProviderAuthenticationError()
                elif resp.status_code == 429:
                    # Determine how long the API wants us to wait.
                    # Check Retry-After header first, then parse from JSON body.
                    retry_after = _parse_retry_after(resp)
                    if retry_after is None:
                        retry_after = _extract_retry_delay_from_body(resp)

                    if retry_after is not None and retry_after > _MAX_RETRY_BACKOFF_SECONDS:
                        # Quota exhaustion with a long mandatory wait — retrying
                        # within this request is futile. Surface to the caller.
                        logger.warning(
                            "Attempt %d/%d: 429 quota exhausted. Server Retry-After=%.0fs exceeds "
                            "max backoff (%.0fs). Raising ProviderRateLimitError immediately.",
                            attempts, self.max_retries + 1, retry_after, _MAX_RETRY_BACKOFF_SECONDS,
                        )
                        raise ProviderRateLimitError(
                            "AI model provider quota exhausted. "
                            f"Please retry after approximately {int(retry_after / 3600)} hour(s)."
                        )

                    if attempts <= self.max_retries:
                        # Short-duration rate limit — respect Retry-After or use
                        # exponential backoff with jitter, capped at _MAX_RETRY_BACKOFF_SECONDS.
                        if retry_after is not None:
                            backoff = min(retry_after, _MAX_RETRY_BACKOFF_SECONDS)
                        else:
                            base = min(_MAX_RETRY_BACKOFF_SECONDS, 2.0 * (2 ** (attempts - 1)))
                            backoff = base + random.uniform(0, min(base * 0.2, 5.0))
                        logger.warning(
                            "Attempt %d/%d: 429 rate limit. Backing off %.1fs.",
                            attempts, self.max_retries + 1, backoff,
                        )
                        await asyncio.sleep(backoff)
                        continue
                    raise ProviderRateLimitError()
                elif resp.status_code == 404:
                    raise ProviderError(
                        code="MODEL_NOT_FOUND",
                        message=f"Configured Gemini model '{self.model}' is not supported or not found.",
                        status_code=502,
                    )
                elif resp.status_code >= 500:
                    if attempts <= self.max_retries:
                        base = min(10.0, 2.0 * (1.5 ** (attempts - 1)))
                        backoff = base + random.uniform(0, min(base * 0.2, 2.0))
                        logger.warning(
                            "Attempt %d/%d: Server error HTTP %d. Retrying in %.1fs",
                            attempts, self.max_retries + 1, resp.status_code, backoff,
                        )
                        await asyncio.sleep(backoff)
                        continue
                    err_detail = ""
                    try:
                        err_data = resp.json()
                        if "error" in err_data and "message" in err_data["error"]:
                            err_detail = f": {err_data['error']['message']}"
                    except Exception:
                        pass
                    raise ProviderUnavailableError(f"The AI model service is currently unavailable{err_detail}. Please retry.")
                elif resp.status_code == 400:
                    err_msg = "AI model provider rejected request (HTTP 400)."
                    try:
                        err_data = resp.json()
                        if "error" in err_data and "message" in err_data["error"]:
                            err_msg = f"AI provider error: {err_data['error']['message']}"
                    except Exception:
                        pass
                    raise ProviderError(
                        code="INVALID_REQUEST",
                        message=err_msg,
                        status_code=400,
                    )
                else:
                    raise ProviderError(
                        code="PROVIDER_ERROR",
                        message=f"AI model provider returned error HTTP {resp.status_code}.",
                        status_code=502,
                    )

            except httpx.TimeoutException:
                if attempts <= self.max_retries:
                    base = min(10.0, 2.0 * (1.5 ** (attempts - 1)))
                    backoff = base + random.uniform(0, min(base * 0.2, 2.0))
                    logger.warning(
                        "Attempt %d/%d: Timeout waiting for AI provider. Retrying in %.1fs",
                        attempts, self.max_retries + 1, backoff,
                    )
                    await asyncio.sleep(backoff)
                    continue
                raise ProviderTimeoutError()
            except httpx.RequestError as e:
                if attempts <= self.max_retries:
                    base = min(10.0, 2.0 * (1.5 ** (attempts - 1)))
                    backoff = base + random.uniform(0, min(base * 0.2, 2.0))
                    logger.warning(
                        "Attempt %d/%d: Network error communicating with AI provider (%s). Retrying in %.1fs",
                        attempts, self.max_retries + 1, str(e), backoff,
                    )
                    await asyncio.sleep(backoff)
                    continue
                raise ProviderUnavailableError("Network error communicating with AI provider.")

        raise ProviderUnavailableError()
