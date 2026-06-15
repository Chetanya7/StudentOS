from pydantic import BaseModel, EmailStr


class AuthenticatedUser(BaseModel):
    user_id: str
    email: EmailStr | None = None
    name: str | None = None
    picture: str | None = None
