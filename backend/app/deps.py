from fastapi import Depends, Header, HTTPException, status
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token

from app.config import Settings, get_settings
from app.models.auth import AuthenticatedUser


async def get_current_user(
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
) -> AuthenticatedUser:
    if settings.allow_dev_auth:
        return AuthenticatedUser(
            user_id="dev-user",
            email="dev@studentos.local",
            name="Dev User",
            picture=None,
        )

    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization bearer token",
        )

    token = authorization.split(" ", 1)[1].strip()
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Empty bearer token",
        )

    if not settings.google_client_id:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="GOOGLE_CLIENT_ID is not configured",
        )

    try:
        claims = id_token.verify_oauth2_token(
            token,
            google_requests.Request(),
            settings.google_client_id,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Google ID token",
        ) from exc

    subject = claims.get("sub")
    if not subject:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Google ID token has no subject",
        )

    return AuthenticatedUser(
        user_id=subject,
        email=claims.get("email"),
        name=claims.get("name"),
        picture=claims.get("picture"),
    )
