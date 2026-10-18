import asyncio
import json
import logging
from typing import Any, Protocol
import httpx

logger = logging.getLogger("tusk.provider")


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
        model: str = "gemini-3.8-flash",
        timeout: float = 25.0,
        max_retries: int = 1,
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
                    if attempts <= self.max_retries:
                        await asyncio.sleep(1.5 * attempts)
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
                        await asyncio.sleep(1.0 * attempts)
                        continue
                    raise ProviderUnavailableError()
                else:
                    raise ProviderError(
                        code="PROVIDER_ERROR",
                        message=f"AI model provider returned error HTTP {resp.status_code}.",
                        status_code=502,
                    )

            except httpx.TimeoutException:
                if attempts <= self.max_retries:
                    continue
                raise ProviderTimeoutError()
            except httpx.RequestError as e:
                if attempts <= self.max_retries:
                    continue
                raise ProviderUnavailableError(f"Network error communicating with AI provider.")

        raise ProviderUnavailableError()
