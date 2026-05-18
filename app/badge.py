"""Visitor badge: ZPL for Zebra thermal via CUPS `lp`.

Default stock: 4 in wide x 3 in tall at 300 dpi (^PW1200 ^LL900).
Content is shifted down by ZEBRA_CONTENT_OFFSET_IN (default 0.5 in) then ZEBRA_MARGIN_TOP padding.
Top line is the word "Visitor" (override text ZEBRA_VISITOR_TITLE_TEXT; size defaults above ZEBRA_FONT_NAME, or set ZEBRA_FONT_VISITOR_TITLE).
Override sizes with ZEBRA_LABEL_*_IN, ZEBRA_DPI, ZEBRA_ZPL_PW / ZEBRA_ZPL_LL, and ZEBRA_FONT_*.
"""

from __future__ import annotations

import logging
import os
import subprocess
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

logger = logging.getLogger(__name__)


def _dpi() -> int:
    return int(os.environ.get("ZEBRA_DPI", "300"))


def _label_width_px() -> int:
    override = os.environ.get("ZEBRA_ZPL_PW", "").strip()
    if override:
        return int(override)
    w_in = float(os.environ.get("ZEBRA_LABEL_WIDTH_IN", "4"))
    return int(w_in * _dpi())


def _label_height_px() -> int:
    override = os.environ.get("ZEBRA_ZPL_LL", "").strip()
    if override:
        return int(override)
    h_in = float(os.environ.get("ZEBRA_LABEL_HEIGHT_IN", "3"))
    return int(h_in * _dpi())


def _fb_max_lines(label_height: int) -> int:
    raw = os.environ.get("ZEBRA_FB_MAX_LINES", "").strip()
    if raw.isdigit():
        return max(1, min(8, int(raw)))
    return 2 if label_height <= 1020 else 3


# Fonts (dots). Defaults for 4x3 @ 300 dpi; tune with ZEBRA_FONT_* if text clips.
FONT_NAME = int(os.environ.get("ZEBRA_FONT_NAME", "96"))
FONT_LINE = int(os.environ.get("ZEBRA_FONT_LINE", "60"))
FONT_DATE = int(os.environ.get("ZEBRA_FONT_DATE", "44"))

MARGIN_TOP = int(os.environ.get("ZEBRA_MARGIN_TOP", "22"))
GAP_NAME_TO_COMPANY = int(os.environ.get("ZEBRA_GAP_NAME_COMPANY", "12"))
GAP_SECTION = int(os.environ.get("ZEBRA_GAP_SECTION", "12"))
FONT_HOST_CAPTION = int(os.environ.get("ZEBRA_FONT_HOST_CAPTION", "40"))
GAP_CAPTION_TO_HOST = int(os.environ.get("ZEBRA_GAP_CAPTION_TO_HOST", "10"))
_vtt = os.environ.get("ZEBRA_FONT_VISITOR_TITLE", "").strip()
# Slightly larger than visitor name unless ZEBRA_FONT_VISITOR_TITLE is set (dots, same as ^A0N height).
FONT_VISITOR_TITLE = int(_vtt) if _vtt.isdigit() else FONT_NAME + 14
GAP_VISITOR_TO_NAME = int(os.environ.get("ZEBRA_GAP_VISITOR_TO_NAME", "14"))


def _badge_tz() -> ZoneInfo:
    """IANA zone for badge clock (default US Eastern). Set ZEBRA_TIMEZONE=e.g. America/Chicago."""
    name = os.environ.get("ZEBRA_TIMEZONE", "America/New_York").strip()
    try:
        return ZoneInfo(name)
    except Exception:
        logger.warning("Invalid ZEBRA_TIMEZONE %r; using America/New_York", name)
        return ZoneInfo("America/New_York")


def _safe_field(value: object, max_len: int = 90) -> str:
    s = "" if value is None else str(value).strip()
    s = s.replace("^", " ").replace("~", " ").replace("\\", " ")
    s = " ".join(s.split())
    if len(s) > max_len:
        s = s[: max_len - 3] + "..."
    return s.encode("ascii", errors="replace").decode("ascii")


def _format_visit_datetime(iso_ts: str) -> str:
    try:
        ts = iso_ts.replace("Z", "+00:00")
        dt = datetime.fromisoformat(ts)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        local = dt.astimezone(_badge_tz())
        return local.strftime("%b %d, %Y  %I:%M %p %Z")
    except Exception:
        return _safe_field(iso_ts, max_len=48)


def build_zpl(record: dict) -> str:
    """ZPL layout: Visitor title, name, company, 'Here to see:', host, date."""
    zpl_pw = _label_width_px()
    zpl_ll = _label_height_px()
    margin = max(12, zpl_pw // 35)
    text_w = max(120, zpl_pw - 2 * margin)
    line_gap = max(6, FONT_LINE // 8)
    fb_lines = _fb_max_lines(zpl_ll)
    block_h = fb_lines * (FONT_LINE + line_gap)

    name = _safe_field(record.get("visitor_name"), 42)
    company = _safe_field(record.get("company"), 120) or "-"
    host = _safe_field(record.get("host_name"), 120)
    when = _format_visit_datetime(str(record.get("received_at", "")))
    caption_raw = os.environ.get("ZEBRA_HOST_CAPTION_TEXT", "Here to see:").strip() or "Here to see:"
    caption = _safe_field(caption_raw, 48)
    visitor_title_raw = os.environ.get("ZEBRA_VISITOR_TITLE_TEXT", "Visitor").strip() or "Visitor"
    visitor_title = _safe_field(visitor_title_raw, 24)

    content_offset = int(
        float(os.environ.get("ZEBRA_CONTENT_OFFSET_IN", "0.5")) * _dpi()
    )
    y_visitor = content_offset + MARGIN_TOP
    y1 = y_visitor + FONT_VISITOR_TITLE + GAP_VISITOR_TO_NAME
    y2 = y1 + FONT_NAME + GAP_NAME_TO_COMPANY
    y_caption = y2 + block_h + GAP_SECTION
    y_host = y_caption + FONT_HOST_CAPTION + GAP_CAPTION_TO_HOST
    y_date = y_host + block_h + GAP_SECTION

    if y_date + FONT_DATE > zpl_ll - 16:
        logger.warning(
            "Badge ZPL may clip: y_date+font=%s label_height=%s; reduce fonts or ZEBRA_FB_MAX_LINES",
            y_date + FONT_DATE,
            zpl_ll,
        )

    parts = [
        "^XA",
        f"^PW{zpl_pw}",
        f"^LL{zpl_ll}",
        f"^FO{margin},{y_visitor}^A0N,{FONT_VISITOR_TITLE},{FONT_VISITOR_TITLE}^FD{visitor_title}^FS",
        f"^FO{margin},{y1}^A0N,{FONT_NAME},{FONT_NAME}^FD{name}^FS",
        f"^FO{margin},{y2}^A0N,{FONT_LINE},{FONT_LINE}^FB{text_w},{fb_lines},{line_gap},L,0^FD{company}^FS",
        f"^FO{margin},{y_caption}^A0N,{FONT_HOST_CAPTION},{FONT_HOST_CAPTION}^FD{caption}^FS",
        f"^FO{margin},{y_host}^A0N,{FONT_LINE},{FONT_LINE}^FB{text_w},{fb_lines},{line_gap},L,0^FD{host}^FS",
        f"^FO{margin},{y_date}^A0N,{FONT_DATE},{FONT_DATE}^FD{when}^FS",
        "^XZ",
    ]
    return "\n".join(parts) + "\n"


def print_badge(record: dict) -> None:
    queue = os.environ.get("ZEBRA_CUPS_QUEUE", "").strip()
    if not queue:
        logger.warning(
            "Badge print skipped: ZEBRA_CUPS_QUEUE unset (set in systemd for visitor-kiosk)"
        )
        return
    zpl = build_zpl(record)
    try:
        subprocess.run(
            ["lp", "-d", queue, "-o", "raw", "-"],
            input=zpl.encode("ascii"),
            check=True,
            timeout=45,
            capture_output=True,
        )
    except subprocess.CalledProcessError as e:
        err = (e.stderr or b"").decode(errors="replace").strip()
        logger.error("Badge print failed exit=%s stderr=%s", e.returncode, err)
    except Exception:
        logger.exception("Badge print failed")
