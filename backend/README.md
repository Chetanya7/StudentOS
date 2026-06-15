# StudentOS Backend

FastAPI backend for StudentOS AI requests.

The Flutter app still signs in with Google directly. The backend verifies the frontend's Google ID token on each request, then performs Hugging Face calls server-side so the HF token is not shipped in the app.

## Setup

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

Fill in:

- `GOOGLE_CLIENT_ID`
- `HF_TOKEN`
- `HF_MODEL_URL`
- `HF_VISION_MODEL_URL`

Run:

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## Auth Contract

Frontend sends the Google ID token:

```http
Authorization: Bearer <google-id-token>
```

The backend verifies:

- token signature
- audience equals `GOOGLE_CLIENT_ID`
- issuer accepted by Google

Verified user data is available to handlers as:

```json
{
  "user_id": "google-sub",
  "email": "student@example.com",
  "name": "Student Name",
  "picture": "https://..."
}
```

## Endpoints

- `GET /health`
- `GET /auth/me`
- `POST /ai/chat`
- `POST /ai/vision/extract`
- `POST /ai/notification/extract`
- `POST /ai/smart-schedule`
- `POST /ai/schedule/suggestions`

## Notes

This backend intentionally does not own login. Login remains frontend Google Sign-In. The backend only verifies the Google ID token to know the caller is a real signed-in user.

No database is included yet. Add DynamoDB later for persisted chat memory, uploaded document chunks, transactions, or user profile state.
