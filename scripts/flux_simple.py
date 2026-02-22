#!/usr/bin/env python3
"""
solarflux_99_swpc.py

Reconstruct ClearSky-like solarflux-99 generation without ClearSky availability.

Observed:
- SWPC daily-solar-indices.txt
- SWPC wwv.txt (patch newest day)

Forecast:
- SWPC 27-day-outlook.txt (next days, smoothed Elwood-style)

Algorithm:
- Maintain rolling cache of daily values (YYYYMMDD -> int flux)
- Inject 2 forecast days using adjacent means
- Keep last 33 days
- Expand each day to 3 samples => 99 values
"""

from __future__ import annotations

import os
import re
import sys
import tempfile
from datetime import datetime
from typing import Dict, List, Optional, Tuple

import requests

URL_DSD = "https://services.swpc.noaa.gov/text/daily-solar-indices.txt"
URL_WWV = "https://services.swpc.noaa.gov/text/wwv.txt"
URL_OUTLOOK = "https://services.swpc.noaa.gov/text/27-day-outlook.txt"

CACHE_PATH = "/opt/hamclock-backend/data/solarflux-swpc-cache.txt"
OUT_PATH = "/opt/hamclock-backend/htdocs/ham/HamClock/solar-flux/solarflux-99.txt"

DAYS = 33
REPEAT = 3
TOTAL = DAYS * REPEAT

UA = "open-hamclock-backend/solarflux-99"


def fetch_text(url: str) -> str:
    r = requests.get(url, headers={"User-Agent": UA}, timeout=30)
    r.raise_for_status()
    return r.text


def atomic_write(path: str, content: str) -> None:
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix="._solarflux.", dir=d, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            f.write(content)
        os.replace(tmp, path)
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def load_cache(path: str) -> Dict[str, int]:
    out = {}
    try:
        with open(path) as f:
            for l in f:
                p = l.split()
                if len(p) == 2 and re.fullmatch(r"\d{8}", p[0]):
                    out[p[0]] = int(p[1])
    except FileNotFoundError:
        pass
    return out


def save_cache(path: str, cache: Dict[str, int]):
    atomic_write(path, "".join(f"{k} {cache[k]}\n" for k in sorted(cache)))


def parse_dsd(txt: str) -> Dict[str, int]:
    out = {}
    for l in txt.splitlines():
        if re.match(r"\s*\d{4}\s+\d+\s+\d+", l):
            p = l.split()
            ymd = f"{int(p[0]):04d}{int(p[1]):02d}{int(p[2]):02d}"
            out[ymd] = int(float(p[3]))
    return out


def parse_wwv(txt: str) -> Optional[Tuple[str, int]]:
    yr = None
    for l in txt.splitlines():
        if l.startswith(":Issued:"):
            m = re.search(r"(\d{4})", l)
            if m:
                yr = int(m.group(1))
            break
    if not yr:
        return None

    day = mon = None
    for l in txt.splitlines():
        m = re.search(r"indices for\s+(\d+)\s+([A-Za-z]+)", l)
        if m:
            day = int(m.group(1))
            mon = m.group(2)
            break

    if not day:
        return None

    dt = datetime.strptime(f"{yr} {mon} {day}", "%Y %b %d").strftime("%Y%m%d")

    for l in txt.splitlines():
        m = re.search(r"Solar flux\s+(\d+)", l)
        if m:
            return dt, int(m.group(1))

    return None

def parse_outlook(txt: str) -> Dict[str, int]:
    """
    Parse NOAA 27-day outlook table (27DO.txt style).

    Lines look like:
    2026 Feb 22     120           5          2
    """

    out = {}

    for l in txt.splitlines():
        l = l.strip()
        if not l:
            continue

        parts = l.split()
        if len(parts) >= 4 and parts[0].isdigit():
            try:
                y = parts[0]
                mon = parts[1]
                d = parts[2]
                flux = parts[3]

                dt = datetime.strptime(f"{y} {mon} {d}", "%Y %b %d")
                out[dt.strftime("%Y%m%d")] = int(flux)
            except Exception:
                continue

    return out

def build_99(cache: Dict[str, int]) -> List[int]:
    vals = [cache[k] for k in sorted(cache)]
    if len(vals) < DAYS:
        vals = [vals[0]] * (DAYS - len(vals)) + vals
    vals = vals[-DAYS:]

    out = []
    for v in vals:
        out += [v] * REPEAT

    if len(out) != TOTAL:
        raise ValueError("internal length mismatch")

    return out


def main():
    first = not os.path.exists(CACHE_PATH)
    cache = load_cache(CACHE_PATH)

    dsd = parse_dsd(fetch_text(URL_DSD))
    for k, v in dsd.items():
        if k not in cache:
            cache[k] = v

    try:
        wwv = parse_wwv(fetch_text(URL_WWV))
        if wwv:
            d, f = wwv
            if d >= max(cache):
                cache[d] = f
    except Exception:
        pass

    # ---- Elwood smoothing via NOAA outlook ----
    # ---- Elwood smoothing via NOAA outlook ----
    try:
       outlook = parse_outlook(fetch_text(URL_OUTLOOK))

       last = max(cache)
       fkeys = sorted(k for k in outlook if k > last)

       if len(fkeys) >= 2:
          o = cache[last]
          f1 = outlook[fkeys[0]]
          f2 = outlook[fkeys[1]]

          # Day+1: plateau (repeat observed)
          cache[fkeys[0]] = o

          # Day+2: first blend
          s1 = round((o + f1) / 2)
          cache[fkeys[1]] = s1

          # Day+3: second blend
          s2 = round((f1 + f2) / 2)
          if len(fkeys) >= 3:
             cache[fkeys[2]] = s2

          # Day+4: repeat S2 (CSI does this)
          if len(fkeys) >= 4:
             cache[fkeys[3]] = s2

          # drop everything beyond
          for k in fkeys[4:]:
             cache.pop(k, None)

    except Exception:
      pass

    if first and cache:
      cache.pop(sorted(cache)[0])

    keys = sorted(cache)
    if len(keys) > DAYS:
        for k in keys[:-DAYS]:
            cache.pop(k)

    save_cache(CACHE_PATH, cache)

    out = build_99(cache)
    atomic_write(OUT_PATH, "\n".join(map(str, out)) + "\n")


if __name__ == "__main__":
    main()
