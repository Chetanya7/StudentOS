from fastapi import APIRouter, Depends

from app.deps import get_current_user
from app.models.auth import AuthenticatedUser

router = APIRouter(prefix="/auth", tags=["auth"])


@router.get("/me", response_model=AuthenticatedUser)
async def me(user: AuthenticatedUser = Depends(get_current_user)) -> AuthenticatedUser:
    return user
