# Web Stack for Drive-Ride-AI

This directory contains the current web implementation of Drive-Ride-AI.

## Included workspaces

- `web/web/` Next.js frontend
- `web/server/` Express API
- `web/shared/` shared TypeScript models
- `web/gateway/` OpenClaw gateway workspace
- `web/openclaw-drive-ride-plugin/` OpenClaw trip-planning plugin
- `web/data/prparking.db` sample parking database

## Quick start

```bash
cd web
npm install
npm run dev
```

Local endpoints:
- Frontend: `http://localhost:3001`
- API: `http://localhost:3000`

## Notes

- The frontend default language is English.
- Chinese and English are both supported in the UI and voice flow.
- Do not commit real `.env` secrets. Use local environment variables instead.
