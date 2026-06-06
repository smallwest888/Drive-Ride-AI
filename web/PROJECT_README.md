# Drive-Ride-AI

Drive-Ride-AI is a bilingual web-based travel planning system for urban driving, park-and-ride, and transit journeys. Users can type or speak a trip request, receive AI-generated route recommendations, and inspect the full path on a 3D globe map.

This repository currently contains the web stack of the project:
- `web/` Next.js frontend
- `server/` Express API
- `shared/` shared TypeScript models
- `gateway/` OpenClaw gateway workspace
- `openclaw-drive-ride-plugin/` OpenClaw tool plugin for trip planning

## Current product capabilities

- Natural-language trip planning in English and Chinese
- A typed “Trip request” entry in the left drawer
- A Siri-style voice entry at the bottom of the planner
- Qwen-based speech-to-text and text-to-speech
- Real route rendering on a 3D Cesium globe
- Multiple route packages such as recommended, cheapest, fastest, most comfortable, and lowest carbon
- Google Maps handoff for driving legs, transit legs, and segment-level links
- A parking management admin page with create, edit, delete, and stats
- OpenClaw / Clawdbot agent orchestration with fallback to direct local planning

## Current architecture

### Frontend

- Next.js application in `web/`
- Main planner at `/`
- Admin dashboard at `/admin`

### Backend

- Express API in `server/`
- Planning endpoint, parking CRUD, location search, speech transcription, and speech synthesis

### Shared data model

The system uses a shared model across frontend and backend:
- `TripRequest`
- `TravelModeOption`
- `Plan`

## Workspace structure

```text
.
├─ gateway/
├─ openclaw-drive-ride-plugin/
├─ server/
├─ shared/
├─ web/
├─ package.json
└─ package-lock.json
```

## Requirements

- Node.js 20+ recommended
- npm 10+ recommended

Optional external services:
- Qwen API key for ASR, TTS, and reply polishing
- Google Maps / Routes API key for live routing and transit fare coverage

## Installation

```bash
npm install
```

## Development

Run the full local stack:

```bash
npm run dev
```

Typical local endpoints:
- Frontend: `http://localhost:3001`
- API: `http://localhost:3000`

## Build

```bash
npm run build
```

## Environment variables

The server supports the following important variables:

- `PORT`
- `FRONTEND_ORIGIN`
- `DB_PATH`
- `OPENCLAW_BASE_URL`
- `OPENCLAW_TOKEN`
- `QWEN_API_KEY`
- `QWEN_BASE_URL`
- `QWEN_MODEL`
- `QWEN_ASR_MODEL`
- `QWEN_TTS_MODEL`
- `QWEN_TTS_MODEL_ZH`
- `QWEN_TTS_MODEL_EN`
- `QWEN_TTS_VOICE_ZH`
- `QWEN_TTS_VOICE_EN`
- `GOOGLE_MAPS_API_KEY`
- `OSRM_BASE_URL`

## Notes on current scope

This version is focused on the working web product. It does not yet include:
- user accounts
- saved history
- favorites
- admin authentication
- batch import/export
- realtime parking occupancy
- production-grade observability and permissions

## License

Refer to the repository license file if one is included in the destination repository.
