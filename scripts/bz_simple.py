#!/usr/bin/env python3

import requests
import time
from datetime import datetime, timezone

URL = "https://services.swpc.noaa.gov/products/solar-wind/mag-3-day.json"
OUT = "/opt/hamclock-backend/htdocs/ham/HamClock/Bz/Bz.txt"

BZBT_NV = 150          # 25 hours @ 10 minutes
STEP = 600            # seconds


def iso_to_epoch(s):
    # format: "2026-02-14 21:19:00.000"
    return int(datetime.strptime(s, "%Y-%m-%d %H:%M:%S.%f")
               .replace(tzinfo=timezone.utc)
               .timestamp())


def main():

    r = requests.get(URL, timeout=30)
    r.raise_for_status()

    data = r.json()

    # Drop header row
    rows = data[1:]

    samples = []
    for d in rows:
        try:
            t = iso_to_epoch(d[0])
            bx = float(d[1])
            by = float(d[2])
            bz = float(d[3])
            bt = float(d[6])
            samples.append((t, bx, by, bz, bt))
        except:
            continue

    if not samples:
        raise SystemExit("No usable samples")

    # sort ascending
    samples.sort()

    # map by epoch
    samp = {t:(bx,by,bz,bt) for t,bx,by,bz,bt in samples}

    oldest = samples[0][0]

    now = int(time.time())
    t = (now // STEP) * STEP

    buffer = []

    while len(buffer) < BZBT_NV and t >= oldest:

        # closest sample <= bin
        keys = [k for k in samp.keys() if k <= t]
        if keys:
            k = max(keys)
            bx,by,bz,bt = samp[k]
            buffer.append((t,bx,by,bz,bt))

        t -= STEP

    if len(buffer) < BZBT_NV:
        print(f"WARNING: only produced {len(buffer)} rows")

    # newest->oldest → oldest->newest
    buffer.reverse()

    with open(OUT, "w") as f:
        f.write("# UNIX        Bx     By     Bz     Bt\n")
        for t,bx,by,bz,bt in buffer:
            f.write(f"{t:10d} {bx:8.2f} {by:8.2f} {bz:8.2f} {bt:8.2f}\n")


if __name__ == "__main__":
    main()

