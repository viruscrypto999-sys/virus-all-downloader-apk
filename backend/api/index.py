"""Vercel entrypoint for the Virus All Downloader backend.

Self-contained copy of server.py: Vercel bundles the api/ directory, so
the FastAPI app lives here directly instead of importing server.py.
Vercel serves the ASGI `app` below; vercel.json rewrites every path to
this function and raises maxDuration to 60s.
"""
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import urllib.request
import yt_dlp

app = FastAPI(title="Virus All Downloader backend")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], allow_methods=["*"], allow_headers=["*"],
)

PLATFORM_MAP = {
    "Facebook": "facebook",
    "TikTok": "tiktok",
    "Youtube": "youtube",
    "Instagram": "instagram",
    "Twitter": "twitter",
    "X": "twitter",
}


class ExtractRequest(BaseModel):
    url: str
    prefer_codec: str = "h264"


def resolve_share_link(url: str) -> str:
    """Best-effort redirect resolution for facebook.com/share/* links.
    Only used when yt-dlp cannot handle the share URL directly."""
    try:
        req = urllib.request.Request(
            url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.geturl()
    except Exception:
        return url


def pick_format(info):
    """Best progressive (video+audio) format, preferring mp4/h264."""
    fmts = [f for f in (info.get("formats") or [])
            if f.get("url") and f.get("vcodec") not in (None, "none")
            and f.get("acodec") not in (None, "none")]
    if not fmts:
        return None

    def score(f):
        s = f.get("height") or 0
        if (f.get("ext") or "") == "mp4":
            s += 100000
        if (f.get("vcodec") or "").startswith(("avc1", "h264")):
            s += 10000
        return s

    return max(fmts, key=score)


def extract_with_ytdlp(url: str):
    ydl_opts = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "format": "best[ext=mp4]/best",
    }
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        return ydl.extract_info(url, download=False)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/api/v1/extract")
def extract(req: ExtractRequest):
    url = (req.url or "").strip()
    if not url:
        raise HTTPException(status_code=400, detail="url is required")
    try:
        info = extract_with_ytdlp(url)
    except Exception:
        # Share links sometimes need redirect resolution first.
        if "facebook.com/share/" in url:
            resolved = resolve_share_link(url)
            if resolved != url:
                try:
                    info = extract_with_ytdlp(resolved)
                except Exception as e:
                    raise HTTPException(
                        status_code=502, detail=f"extract failed: {e}")
            else:
                raise HTTPException(
                    status_code=502, detail="extract failed: share link unresolved")
        else:
            raise HTTPException(
                status_code=502, detail="extract failed")
    if info is None:
        raise HTTPException(status_code=502, detail="extract failed: no info")
    if info.get("_type") == "playlist" and info.get("entries"):
        info = info["entries"][0]
    fmt = pick_format(info)
    video_url = (fmt or {}).get("url") or info.get("url")
    if not video_url:
        raise HTTPException(status_code=502, detail="extract failed: no video url")
    width = (fmt or {}).get("width") or info.get("width") or 0
    height = (fmt or {}).get("height") or info.get("height") or 0
    extractor = info.get("extractor_key") or info.get("extractor") or "unknown"
    platform = PLATFORM_MAP.get(extractor, str(extractor).lower())
    return {
        "platform": platform,
        "id": str(info.get("id") or "0"),
        "title": info.get("title") or "Untitled Stream",
        "author": info.get("uploader") or info.get("uploader_id") or "unknown",
        "resolution": f"{width}x{height}" if width and height else "1080x1920",
        "is_watermarked": False,
        "video_url": video_url,
        "proxy_download_url": video_url,
    }
