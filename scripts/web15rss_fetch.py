#!/usr/bin/env python3
# web15rss_fetch.py — run via cron or systemd timer, NOT by clients
# Writes: /opt/hamclock-backend/cache/rss/{arnewsline,ng3k,hamweekly}.txt
#
# Requirements:
#   pip install requests feedparser beautifulsoup4 lxml
#
# Suggested cron (every 15 min):
#   */15 * * * * /usr/bin/python3 /opt/hamclock-backend/web15rss_fetch.py >> /var/log/ohb-rss-fetch.log 2>&1

import os
import sys
import logging
import tempfile
from datetime import date, datetime

import requests
import feedparser
from bs4 import BeautifulSoup

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
CACHE_DIR = "/opt/hamclock-backend/cache/rss"
REQUEST_TIMEOUT = 15
HEADERS = {"User-Agent": "Mozilla/5.0"}
NG3K_MAX = 5
HAMWEEKLY_MAX = 5

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Helper: atomic cache write
# Writes to a .tmp file then renames so clients never see a partial file.
# ---------------------------------------------------------------------------
def write_cache(name: str, lines: list[str]) -> None:
    if not lines:
        log.warning("[%s] Nothing to write, keeping existing cache", name)
        return

    os.makedirs(CACHE_DIR, exist_ok=True)
    dest = os.path.join(CACHE_DIR, f"{name}.txt")
    tmp_fd, tmp_path = tempfile.mkstemp(dir=CACHE_DIR, prefix=f"{name}_", suffix=".tmp")

    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
        os.replace(tmp_path, dest)  # atomic on Linux
        log.info("[%s] Wrote %d lines to cache", name, len(lines))
    except Exception:
        os.unlink(tmp_path)
        raise

# ---------------------------------------------------------------------------
# 1. ARNewsLine
# ---------------------------------------------------------------------------
def fetch_arnewsline() -> None:
    log.info("[arnewsline] Fetching...")

    resp = requests.get(
        "https://www.arnewsline.org/?format=rss",
        headers=HEADERS,
        timeout=REQUEST_TIMEOUT,
    )
    resp.raise_for_status()

    feed = feedparser.parse(resp.text)
    if not feed.entries:
        raise ValueError("No entries in feed")

    entry = feed.entries[0]
    html = entry.get("content", [{}])[0].get("value", "") or entry.get("summary", "")

    soup = BeautifulSoup(html, "lxml")

    # Remove script/audio link paragraphs
    for p in soup.find_all("p"):
        if p.find("a"):
            p.decompose()

    text = soup.get_text(separator="\n")

    lines = []
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("- "):
            headline = line[2:].strip()
            if headline:
                lines.append(f"ARNewsLine.org: {headline}")

    if not lines:
        raise ValueError("No bullet lines parsed")

    write_cache("arnewsline", lines)


# ---------------------------------------------------------------------------
# 2. NG3K DXpeditions
# ---------------------------------------------------------------------------
def fetch_ng3k() -> None:
    log.info("[ng3k] Fetching...")

    resp = requests.get(
        "https://www.ng3k.com/Misc/adxo.html",
        headers=HEADERS,
        timeout=REQUEST_TIMEOUT,
    )
    resp.raise_for_status()

    soup = BeautifulSoup(resp.text, "lxml")
    today = date.today()
    lines = []

    for row in soup.find_all("tr", class_="adxoitem"):
        if len(lines) >= NG3K_MAX:
            break

        tds = row.find_all("td")
        if len(tds) < 4:
            continue

        start_text = tds[0].get_text(strip=True)
        end_text   = tds[1].get_text(strip=True)
        entity     = tds[2].get_text(strip=True)

        call_span = row.find("span", class_="call")
        call = call_span.get_text(strip=True) if call_span else ""

        qsl = tds[-1].get_text(strip=True)

        # Parse dates: "2025 Mar01" or "2025 Mar 01"
        try:
            start = datetime.strptime(start_text, "%Y %b%d").date()
        except ValueError:
            try:
                start = datetime.strptime(start_text, "%Y %b %d").date()
            except ValueError:
                continue

        try:
            end = datetime.strptime(end_text, "%Y %b%d").date()
        except ValueError:
            try:
                end = datetime.strptime(end_text, "%Y %b %d").date()
            except ValueError:
                continue

        if not (start <= today <= end):
            continue

        smon = start.strftime("%b")
        sday = start.day
        emon = end.strftime("%b")
        eday = end.day
        year = start.year

        lines.append(
            f"NG3K.com: {entity}: {smon} {sday} - {emon} {eday}, {year} -- {call} -- QSL: {qsl}"
        )

    if not lines:
        raise ValueError("No active DXpeditions parsed")

    write_cache("ng3k", lines)


# ---------------------------------------------------------------------------
# 3. HamWeekly
# ---------------------------------------------------------------------------
def fetch_hamweekly() -> None:
    log.info("[hamweekly] Fetching...")

    resp = requests.get(
        "https://daily.hamweekly.com/atom.xml",
        headers=HEADERS,
        timeout=REQUEST_TIMEOUT,
    )
    resp.raise_for_status()

    feed = feedparser.parse(resp.text)
    if not feed.entries:
        raise ValueError("No entries in feed")

    lines = []
    for entry in feed.entries[:HAMWEEKLY_MAX]:
        title = entry.get("title", "").strip()
        if title:
            lines.append(f"HamWeekly.com: {title}")

    if not lines:
        raise ValueError("No titles parsed")

    write_cache("hamweekly", lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
SOURCES = [
    ("arnewsline", fetch_arnewsline),
    ("ng3k",       fetch_ng3k),
    ("hamweekly",  fetch_hamweekly),
]

if __name__ == "__main__":
    log.info("Starting RSS fetch")
    any_failed = False

    for name, fn in SOURCES:
        try:
            fn()
        except Exception as exc:
            log.error("[%s] FAILED: %s", name, exc)
            any_failed = True

    log.info("Fetch complete")
    sys.exit(1 if any_failed else 0)
