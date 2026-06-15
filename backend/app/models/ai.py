from typing import Any, Literal
from pydantic import BaseModel, Field


class ChatMessage(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str


class AiChatRequest(BaseModel):
    messages: list[ChatMessage]
    max_tokens: int = Field(default=700, ge=1, le=5000)
    temperature: float = Field(default=0.3, ge=0, le=2)


class AiTextResponse(BaseModel):
    text: str
    raw: dict[str, Any] | None = None


class VisionExtractRequest(BaseModel):
    image_base64: str
    mime_type: str = "image/jpeg"
    user_message: str = ""
    max_tokens: int = Field(default=2600, ge=1, le=5000)
    temperature: float = Field(default=0.1, ge=0, le=2)


class PromptRequest(BaseModel):
    prompt: str
    max_tokens: int = Field(default=900, ge=1, le=5000)
    temperature: float = Field(default=0.1, ge=0, le=2)


class NotificationExtractRequest(BaseModel):
    payload: dict[str, Any]


class SmartScheduleRequest(BaseModel):
    now: str
    timezone: str | None = None
    calendar_events: list[dict[str, Any]] = Field(default_factory=list)


class ScheduleSuggestionRequest(BaseModel):
    record: dict[str, Any]
    now: str
