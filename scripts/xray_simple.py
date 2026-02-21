#!/usr/bin/env python3

import time
import pandas as pd
import requests
from pathlib import Path

URL = "https://services.swpc.noaa.gov/json/goes/primary/xrays-3-day.json"
OUT = Path("/opt/hamclock-backend/htdocs/ham/HamClock/xray/xray.txt")

# CSI appears to lag the very newest bins; keep a safety margin so we don't
# emit bins they haven't emitted yet. Tune if needed.
CSI_LAG_MINUTES = 21

def main() -> None:
    # Retry up to 3 times with backoff in case of transient SWPC issues
    for attempt in range(3):
        r = requests.get(URL, timeout=(10, 60))
        r.raise_for_status()

        content_type = r.headers.get('Content-Type', '')
        if 'json' not in content_type:
            raise RuntimeError(
                f"Expected JSON from SWPC but got Content-Type: {content_type!r}\n"
                f"Response start: {r.text[:500]!r}"
            )

        try:
            data = r.json()
            break  # success
        except requests.exceptions.JSONDecodeError as e:
            snippet_start = r.text[:500]
            snippet_end = r.text[-500:]
            if attempt < 2:
                print(f"Attempt {attempt + 1}: JSON parse failed at pos {e.pos}, retrying in 5s...")
                time.sleep(5)
                continue
            raise RuntimeError(
                f"SWPC returned invalid JSON after 3 attempts (pos {e.pos})\n"
                f"START: {snippet_start!r}\n"
                f"END:   {snippet_end!r}"
            ) from e

    df = pd.DataFrame(data)
    required = {"time_tag", "energy", "flux"}
    if not required.issubset(df.columns):
        raise RuntimeError("Unexpected SWPC JSON schema (missing required keys)")

    # Parse timestamps as UTC
    df["time_tag"] = pd.to_datetime(df["time_tag"], utc=True)

    # Keep only the two GOES X-ray bands used by HamClock/CSI
    df = df[df["energy"].isin(["0.05-0.4nm", "0.1-0.8nm"])]

    # One row per timestamp with both flux columns
    df = df.pivot(index="time_tag", columns="energy", values="flux").dropna()
    df = df.rename(columns={"0.05-0.4nm": "short", "0.1-0.8nm": "long"}).sort_index()

    # --- CSI-like 10-minute binning (fixed bins, UTC aligned) ---
    # Floor to 10-minute boundaries
    binned = df.copy()
    binned["bin"] = binned.index.floor("10min")

    # CSI values look like per-bin MAX, not mean (MAX >= MEAN; your values were low)
    binned = binned.groupby("bin", sort=True)[["short", "long"]].max()

    # Stamp the bin at end-of-bin minute 9 (e.g., 12:50 bin -> 12:59)
    binned.index = binned.index + pd.Timedelta(minutes=9)

    # Drop newest bins with a safety lag so output ends where CSI tends to end
    now = pd.Timestamp.now(tz="UTC")
    last_allowed = now - pd.Timedelta(minutes=CSI_LAG_MINUTES)
    # Ensure last_allowed is an end-of-bin time (:..:x9)
    last_allowed = last_allowed.floor("10min") + pd.Timedelta(minutes=9)
    binned = binned[binned.index <= last_allowed]

    # Keep ~30 hours of history after binning
    #if not binned.empty:
    #   binned = binned[binned.index >= binned.index.max() - pd.Timedelta(hours=30)]

    # Keep last 150 samples only (CSI behavior)
    if len(binned) > 150:
       binned = binned.iloc[-150:]

    # Write output (CSI fixed columns)
    OUT.parent.mkdir(parents=True, exist_ok=True)

    with open(OUT, "w") as f:
        for t, row in binned.iterrows():
            # Column starts (1-based) matching CSI:
            # year 1, month 7, day 9, hhmm 13, zero1 20, zero2 27, short 37, long 49
            hhmm = t.strftime("%H%M")
            f.write(
                f"{t.year:4d}  {t.month:1d} {t.day:2d}  {hhmm:>4}   "
                f"00000  00000     "
                f"{row.short:8.2e}    {row.long:8.2e}\n"
            )

if __name__ == "__main__":
    main()
