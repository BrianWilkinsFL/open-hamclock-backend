#!/usr/bin/env python3
"""
Build swind-24hr.txt (epoch density speed) from NOAA SWPC plasma-1-day.json.

Upstream:
  https://services.swpc.noaa.gov/products/solar-wind/plasma-1-day.json

Output (one row per sample):
  <unix_epoch> <density> <speed>

Target path:
  /opt/hamclock-backend/htdocs/ham/HamClock/solar-wind/swind-24hr.txt

Windowing policy (CSI-like, but ending at newest available sample):
- Sort + de-dup by epoch
- Optional lag (disabled by default)
- Keep the last 1440 samples (24h @ ~1-min cadence)
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import urllib.request
from datetime import datetime, timezone
from typing import Any, Dict, List, Tuple

URL = "https://services.swpc.noaa.gov/products/solar-wind/plasma-1-day.json"
OUT = "/opt/hamclock-backend/htdocs/ham/HamClock/solar-wind/swind-24hr.txt"

# 24h at ~1-minute cadence
KEEP_N = 1440

# Set to 0 to end at newest available SWPC sample (recommended).
# If you later confirm CSI lags on purpose, set e.g. 60*60 or 90*60.
LAG_SECONDS = 0


def iso_to_epoch(s: str) -> int:
    s = s.strip().replace("T", " ")
    if s.endswith("Z"):
        s = s[:-1].strip()

    fmts = ("%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S")
    for fmt in fmts:
        try:
            dt = datetime.strptime(s, fmt).replace(tzinfo=timezone.utc)
            return int(dt.timestamp())
        except ValueError:
            pass
    raise ValueError(f"Unrecognized time_tag format: {s!r}")


def fetch_json(url: str, timeout: int = 20) -> Any:
    req = urllib.request.Request(url, headers={"User-Agent": "OHB-swind/1.2"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", errors="replace"))


def parse_plasma(rows: Any) -> List[Tuple[int, float, float]]:
    if not isinstance(rows, list) or len(rows) < 2:
        raise ValueError("Unexpected JSON shape (expected list with header + data rows)")

    header = rows[0]
    if not isinstance(header, list):
        raise ValueError("Unexpected header row shape")

    idx: Dict[str, int] = {}
    for i, name in enumerate(header):
        if isinstance(name, str):
            idx[name.strip().lower()] = i

    for needed in ("time_tag", "density", "speed"):
        if needed not in idx:
            raise ValueError(f"Missing required column {needed!r} in header: {header!r}")

    out: List[Tuple[int, float, float]] = []
    for r in rows[1:]:
        if not isinstance(r, list):
            continue
        try:
            t = iso_to_epoch(str(r[idx["time_tag"]]))
            dens = float(r[idx["density"]])
            spd = float(r[idx["speed"]])
        except Exception:
            continue

        # generous sanity bounds
        if t <= 0:
            continue
        if not (0.0 <= dens <= 500.0):
            continue
        if not (0.0 <= spd <= 5000.0):
            continue

        out.append((t, dens, spd))

    if not out:
        raise ValueError("No valid samples parsed from upstream JSON")

    out.sort(key=lambda x: x[0])

    # De-dup strictly by increasing epoch
    dedup: List[Tuple[int, float, float]] = []
    last_t = None
    for t, d, v in out:
        if last_t is None or t > last_t:
            dedup.append((t, d, v))
            last_t = t

    return dedup


def apply_window(samples: List[Tuple[int, float, float]]) -> List[Tuple[int, float, float]]:
    s = samples[:]
    if not s:
        return s

    if LAG_SECONDS and LAG_SECONDS > 0:
        newest = s[-1][0]
        lag_cutoff = newest - LAG_SECONDS
        s = [row for row in s if row[0] <= lag_cutoff]

    if len(s) > KEEP_N:
        s = s[-KEEP_N:]

    return s


def atomic_write(path: str, lines: List[str]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".swind-", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.writelines(lines)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def main() -> int:
    try:
        rows = fetch_json(URL)
        samples = parse_plasma(rows)
        samples = apply_window(samples)

        if not samples:
            raise ValueError("No samples left after windowing; check LAG_SECONDS or upstream feed")

        lines = [f"{t} {dens:.2f} {spd:.1f}\n" for (t, dens, spd) in samples]
        atomic_write(OUT, lines)
        return 0

    except Exception as e:
        print(f"swind build failed: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

