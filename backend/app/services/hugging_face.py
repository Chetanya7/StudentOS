from typing import Any

import httpx

from app.config import Settings


def model_id(value: str) -> str | None:
    trimmed = value.strip()
    if not trimmed:
        return None

    if "://" not in trimmed:
        return trimmed

    try:
        from urllib.parse import urlparse

        parsed = urlparse(trimmed)
        segments = [part for part in parsed.path.split("/") if part]
        if parsed.netloc == "huggingface.co":
            return "/".join(segments[:2]) or None
        if parsed.netloc == "api-inference.huggingface.co":
            if segments and segments[0] == "models":
                return "/".join(segments[1:3]) or None
            return "/".join(segments[:2]) or None
        return trimmed
    except Exception:
        return trimmed


class HuggingFaceClient:
    def __init__(self, settings: Settings):
        self._settings = settings

    async def chat(
        self,
        *,
        messages: list[dict[str, Any]],
        model_url: str | None = None,
        max_tokens: int = 700,
        temperature: float = 0.3,
    ) -> dict[str, Any]:
        token = self._settings.hf_token.strip()
        if not token:
            raise RuntimeError("HF_TOKEN is not configured")

        selected_model = model_id(model_url or self._settings.hf_model_url)
        if not selected_model:
            raise RuntimeError("HF model is not configured")

        body = {
            "model": f"{selected_model}:fastest",
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "stream": False,
        }

        async with httpx.AsyncClient(timeout=90) as client:
            response = await client.post(
                self._settings.hf_router_url,
                headers={
                    "Authorization": f"Bearer {token}",
                    "Content-Type": "application/json",
                },
                json=body,
            )
            response.raise_for_status()
            return response.json()


def extract_generated_text(response: dict[str, Any]) -> str:
    choices = response.get("choices")
    if isinstance(choices, list) and choices:
        first = choices[0]
        if isinstance(first, dict):
            message = first.get("message")
            if isinstance(message, dict):
                content = str(message.get("content") or "").strip()
                if content:
                    return content
                reasoning = str(message.get("reasoning") or "").strip()
                if reasoning:
                    return reasoning

    generated = response.get("generated_text")
    if generated is not None:
        return str(generated)

    return ""
