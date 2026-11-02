# Virus All Downloader backend

FastAPI + yt-dlp server. Works like fbdown.net / ssttiktok / Y2mate:
give it a video link, it returns the direct video file URL (no watermark)
plus metadata, in the exact JSON shape the Virus All Downloader app
expects.

## Run

```bash
pip install -r requirements.txt
uvicorn server:app --host 0.0.0.0 --port 8000
```

## API

- `GET /health` -> `{"status": "ok"}`
- `POST /api/v1/extract` with `{"url": "...", "prefer_codec": "h264"}` ->
  `{"platform", "id", "title", "author", "resolution",
    "is_watermarked", "video_url", "proxy_download_url"}`

v1 design: `proxy_download_url` IS the direct CDN URL. The app streams
and downloads straight from the platform CDN, so no video bytes flow
through this server.

## Vercel deployment (live)

The Vercel deployment is the FastAPI app in `api/index.py`, deployed to
`https://virus-all-downloader-backend-virus-4b61.vercel.app`
(production alias, stable across redeploys). `vercel.json` sets only
`maxDuration: 60` for it. `server.py` is the same app for local /
Termux / PC use.

Vercel lessons (Nov 3, all verified against live deployments):
- A blanket rewrite (`/(.*)` to `/api/index.py`) breaks FastAPI
  routing: the function sees the rewritten path, so every route 404s.
  No rewrite: the framework routes original paths to the app.
- The plain `handler` class in `api/v1/extract.py` does NOT work under
  this project's `fastapi` framework: the build needs an explicit
  entrypoint (`pyproject.toml`), and at runtime every request 500s,
  because the framework expects an ASGI app, not a request-handler
  class. Runtime logs are not readable via the connected account
  (403), so this was diagnosed from status codes only.

## App wiring

The app hardcodes its backend URL in `lib/main.dart` (`_backendUrl`).
Point it at wherever this server runs, then rebuild the app:

- Phone (Termux): run the server in Termux, set the app URL to
  `http://127.0.0.1:8000` (same device loopback).
- PC on the same WiFi: set the app URL to the PC's LAN IP, e.g.
  `http://192.168.1.5:8000`.
- VPS: set the app URL to the server's domain/IP.
