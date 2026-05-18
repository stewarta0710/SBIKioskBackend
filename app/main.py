import asyncio
import json
import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from app import badge
from app.schemas import VisitorSubmission

logger = logging.getLogger(__name__)

BASE_DIR = Path(__file__).resolve().parent.parent
TEMPLATES = Jinja2Templates(directory=str(BASE_DIR / "templates"))
DATA_DIR = Path(os.environ.get("VISITOR_DATA_DIR", str(BASE_DIR / "data")))
DATA_FILE = DATA_DIR / "visitors.jsonl"


def _webhook_url() -> str:
    """Read VISITOR_WEBHOOK_URL each request; strip accidental quotes from systemd."""
    v = os.environ.get("VISITOR_WEBHOOK_URL", "").strip()
    if len(v) >= 2 and v[0] in "'\"" and v[-1] == v[0]:
        v = v[1:-1].strip()
    return v


def _webhook_timeout() -> float:
    return float(os.environ.get("VISITOR_WEBHOOK_TIMEOUT_SECONDS", "15"))


def _debug_response() -> bool:
    return os.environ.get("VISITOR_DEBUG_RESPONSE", "").strip().lower() in (
        "1",
        "true",
        "yes",
    )


def _safe_debug_detail(msg: str) -> str:
    """Shorten and trim query secrets from client-visible debug strings."""
    s = (msg or "")[:220]
    low = s.lower()
    if "sig=" in low:
        i = low.index("sig=")
        s = s[: i + 4] + "…"
    return s


@asynccontextmanager
async def lifespan(app: FastAPI):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    logger.info(
        "Power Automate webhook: %s",
        "enabled" if _webhook_url() else "disabled (VISITOR_WEBHOOK_URL unset)",
    )
    yield


app = FastAPI(title="Visitor Kiosk", lifespan=lifespan)

app.mount("/static", StaticFiles(directory=str(BASE_DIR / "static")), name="static")


@app.get("/")
async def index(request: Request):
    response = TEMPLATES.TemplateResponse(
        "index.html",
        {"request": request},
    )
    # Kiosk browsers often cache the main document; avoid stale host list after deploys.
    response.headers["Cache-Control"] = "no-store, max-age=0"
    response.headers["Pragma"] = "no-cache"
    return response


@app.post("/api/visitors")
async def create_visitor(entry: VisitorSubmission):
    dump = entry.model_dump()
    full_name = f"{dump['visitor_first_name']} {dump['visitor_last_name']}".strip()
    record = {
        **dump,
        "visitor_name": full_name,
        "received_at": datetime.now(timezone.utc).isoformat(),
    }
    line = json.dumps(record, ensure_ascii=False) + "\n"
    try:
        with open(DATA_FILE, "a", encoding="utf-8") as f:
            f.write(line)
    except OSError as e:
        raise HTTPException(status_code=500, detail="Could not persist entry") from e

    hook = _webhook_url()
    webhook_info: dict[str, str] = {
        "state": "skipped",
        "detail": "VISITOR_WEBHOOK_URL unset or empty (systemd: double %% for each % in the URL)",
    }
    if hook:
        try:
            async with httpx.AsyncClient(timeout=_webhook_timeout()) as client:
                r = await client.post(
                    hook,
                    json=record,
                    headers={"Content-Type": "application/json"},
                )
                r.raise_for_status()
            webhook_info = {"state": "ok", "detail": f"HTTP {r.status_code}"}
            logger.info("Power Automate webhook POST ok (%s)", r.status_code)
        except Exception as e:
            webhook_info = {
                "state": "failed",
                "detail": _safe_debug_detail(f"{type(e).__name__}: {e}"),
            }
            logger.exception("VISITOR_WEBHOOK_URL post failed after save")

    await asyncio.to_thread(badge.print_badge, record)

    body: dict = {"ok": True, "id": record["received_at"]}
    if _debug_response():
        body["_webhook"] = webhook_info
    return JSONResponse(body)
