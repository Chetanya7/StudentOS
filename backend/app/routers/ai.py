from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from httpx import HTTPStatusError

from app.config import Settings, get_settings
from app.deps import get_current_user
from app.models.ai import (
    AiChatRequest,
    AiTextResponse,
    NotificationExtractRequest,
    PromptRequest,
    ScheduleSuggestionRequest,
    SmartScheduleRequest,
    VisionExtractRequest,
)
from app.models.auth import AuthenticatedUser
from app.services.hugging_face import HuggingFaceClient, extract_generated_text
from app.services.prompts import (
    notification_extraction_prompt,
    schedule_suggestions_prompt,
    smart_schedule_prompt,
    vision_extraction_prompt,
)

router = APIRouter(prefix="/ai", tags=["ai"])


async def _call_hf(
    *,
    settings: Settings,
    messages: list[dict],
    max_tokens: int,
    temperature: float,
    model_url: str | None = None,
) -> AiTextResponse:
    try:
        raw = await HuggingFaceClient(settings).chat(
            messages=messages,
            model_url=model_url,
            max_tokens=max_tokens,
            temperature=temperature,
        )
    except HTTPStatusError as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Hugging Face request failed: {exc.response.status_code} {exc.response.text}",
        ) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return AiTextResponse(text=extract_generated_text(raw), raw=raw)


@router.post("/chat", response_model=AiTextResponse)
async def chat(
    request: AiChatRequest,
    _: AuthenticatedUser = Depends(get_current_user),
    settings: Settings = Depends(get_settings),
) -> AiTextResponse:
    return await _call_hf(
        settings=settings,
        messages=[message.model_dump() for message in request.messages],
        max_tokens=request.max_tokens,
        temperature=request.temperature,
    )


@router.post("/prompt", response_model=AiTextResponse)
async def prompt(
    request: PromptRequest,
    _: AuthenticatedUser = Depends(get_current_user),
    settings: Settings = Depends(get_settings),
) -> AiTextResponse:
    return await _call_hf(
        settings=settings,
        messages=[{"role": "user", "content": request.prompt}],
        max_tokens=request.max_tokens,
        temperature=request.temperature,
    )


@router.post("/vision/extract", response_model=AiTextResponse)
async def vision_extract(
    request: VisionExtractRequest,
    _: AuthenticatedUser = Depends(get_current_user),
    settings: Settings = Depends(get_settings),
) -> AiTextResponse:
    image_url = f"data:{request.mime_type};base64,{request.image_base64}"
    prompt_text = vision_extraction_prompt(
        user_message=request.user_message,
        now=datetime.now().isoformat(),
    )
    return await _call_hf(
        settings=settings,
        model_url=settings.hf_vision_model_url,
        messages=[
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt_text},
                    {"type": "image_url", "image_url": {"url": image_url}},
                ],
            }
        ],
        max_tokens=request.max_tokens,
        temperature=request.temperature,
    )


@router.post("/notification/extract", response_model=AiTextResponse)
async def notification_extract(
    request: NotificationExtractRequest,
    _: AuthenticatedUser = Depends(get_current_user),
    settings: Settings = Depends(get_settings),
) -> AiTextResponse:
    return await _call_hf(
        settings=settings,
        messages=[{"role": "user", "content": notification_extraction_prompt(request.payload)}],
        max_tokens=900,
        temperature=0.1,
    )


@router.post("/smart-schedule", response_model=AiTextResponse)
async def smart_schedule(
    request: SmartScheduleRequest,
    _: AuthenticatedUser = Depends(get_current_user),
    settings: Settings = Depends(get_settings),
) -> AiTextResponse:
    return await _call_hf(
        settings=settings,
        messages=[
            {
                "role": "user",
                "content": smart_schedule_prompt(
                    now=request.now,
                    timezone=request.timezone,
                    calendar_events=request.calendar_events,
                ),
            }
        ],
        max_tokens=900,
        temperature=0.2,
    )


@router.post("/schedule/suggestions", response_model=AiTextResponse)
async def schedule_suggestions(
    request: ScheduleSuggestionRequest,
    _: AuthenticatedUser = Depends(get_current_user),
    settings: Settings = Depends(get_settings),
) -> AiTextResponse:
    return await _call_hf(
        settings=settings,
        messages=[
            {
                "role": "user",
                "content": schedule_suggestions_prompt(record=request.record, now=request.now),
            }
        ],
        max_tokens=4200,
        temperature=0.1,
    )
