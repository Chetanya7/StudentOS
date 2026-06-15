from functools import lru_cache
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_env: str = Field(default="development", alias="APP_ENV")
    api_host: str = Field(default="0.0.0.0", alias="API_HOST")
    api_port: int = Field(default=8000, alias="API_PORT")

    google_client_id: str = Field(default="", alias="GOOGLE_CLIENT_ID")
    allow_dev_auth: bool = Field(default=False, alias="ALLOW_DEV_AUTH")

    hf_token: str = Field(default="", alias="HF_TOKEN")
    hf_model_url: str = Field(default="Qwen/Qwen2.5-7B-Instruct-Turbo", alias="HF_MODEL_URL")
    hf_vision_model_url: str = Field(default="Qwen/Qwen3.5-9B", alias="HF_VISION_MODEL_URL")
    hf_router_url: str = Field(
        default="https://router.huggingface.co/v1/chat/completions",
        alias="HF_ROUTER_URL",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
