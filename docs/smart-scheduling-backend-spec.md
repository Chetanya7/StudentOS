# StudentOS Smart Scheduling AI Spec

## Hackathon Decision

For the hackathon, StudentOS calls Hugging Face directly from the Flutter app.

There is no backend in this version.

This is not production-secure because the Hugging Face token is bundled into the app, but it is fast and fine for a demo.

## `.env` File

Create a `.env` file in the project root:

```text
HF_MODEL_URL=https://api-inference.huggingface.co/models/your-org/your-model
HF_TOKEN=hf_your_token_here
```

`.env` is gitignored. `.env.example` is committed as a template.

## Flutter Flow

1. User signs in with Google in the Flutter app.
2. Flutter reads this week's Google Calendar events.
3. Flutter builds a smart scheduling prompt.
4. Flutter sends that prompt to Hugging Face using `HF_MODEL_URL` and `HF_TOKEN`.
5. Hugging Face returns JSON text.
6. Flutter parses the JSON into smart scheduling cards.
7. Flutter shows the top recommendation as a local notification.
8. If Hugging Face fails, Flutter uses local fallback rules.

## Hugging Face Request

StudentOS sends:

```json
{
  "inputs": "prompt text",
  "parameters": {
    "max_new_tokens": 700,
    "temperature": 0.2,
    "return_full_text": false
  }
}
```

Headers:

```text
Authorization: Bearer <HF_TOKEN>
Content-Type: application/json
```

## Required AI Output

The model should return JSON only:

```json
{
  "recommendations": [
    {
      "id": "stable-short-id",
      "type": "study",
      "title": "Study for Physics quiz",
      "message": "Study for Physics quiz today. Tomorrow is already packed.",
      "reason": "The quiz is in two days and tomorrow has class plus a club meeting.",
      "suggestedDate": "2026-06-13T18:00:00+05:30",
      "priority": 1
    }
  ]
}
```

Allowed `type` values:

- `study`
- `prepare`
- `rest`
- `plan`

Priority:

- `1`: urgent/high value
- `2`: important
- `3`: useful
- `4`: low urgency
- `5`: optional

## Fallback Behavior

If the Hugging Face call fails, times out, returns non-JSON, or `.env` is blank, the app uses local rules.

The local fallback already handles the core demo example:

- Quiz/exam/deadline soon
- Busy calendar before it
- Recommend studying today

## Production Note

For a real app, move this call to a backend so the Hugging Face token is never shipped inside the mobile app.

