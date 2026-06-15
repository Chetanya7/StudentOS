from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import ai, auth

app = FastAPI(
    title="StudentOS Backend",
    version="0.1.0",
    description="Backend for StudentOS AI requests and Google ID-token verification.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(ai.router)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
