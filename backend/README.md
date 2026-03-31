# KBO Fans Backend

FastAPI backend for the KBO Fans mobile app.

## Goals

- Serve normalized REST APIs for the Flutter client
- Isolate KBO crawling logic from API route handlers
- Keep scheduler, push, and crawling boundaries clean enough for production growth

## Layout

```text
backend/
├── pyproject.toml
├── README.md
├── .env.example
├── src/kbo_fans_backend/
│   ├── api/
│   ├── core/
│   ├── crawlers/
│   ├── push/
│   ├── scheduler/
│   ├── schemas/
│   ├── services/
│   └── utils/
└── tests/
```

## Run locally

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
uvicorn kbo_fans_backend.main:app --reload
```

## Current status

- Application skeleton is ready
- Health endpoint is implemented
- Product API routes are registered as stubs against the documented contract
- Crawlers, scheduler, and push modules have dedicated boundaries but are not implemented yet

## Push notifications

Remote push requires Firebase configuration on both app and backend.

- App:
  - iOS `GoogleService-Info.plist`
  - Android `google-services.json`
- Backend:
  - `FIREBASE_SERVICE_ACCOUNT_PATH`
  - optional `FIREBASE_PROJECT_ID`

Test send endpoint:

```bash
curl -X POST http://localhost:8000/api/push/test \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "KBO Fans Test",
    "body": "Push delivery test",
    "topic": "game_start_LG"
  }'
```
