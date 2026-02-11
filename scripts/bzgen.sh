#!/usr/bin/env bash
set -euo pipefail

OUT="/opt/hamclock-backend/htdocs/ham/HamClock/Bz/Bz.txt"
mkdir -p "$(dirname "$OUT")"
TMP_OUT="${OUT}.tmp"

SRC="https://services.swpc.noaa.gov/products/solar-wind/mag-6-hour.json"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1" >&2; exit 1; }; }
need curl
need python3

TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON" "$TMP_OUT"' EXIT

curl -fsS -A "open-hamclock-backend/1.0" --retry 2 --retry-delay 2 "$SRC" -o "$TMP_JSON"

python3 - <<'PY' "$TMP_JSON" "$TMP_OUT"
import json, sys, os, re
from datetime import datetime, timezone

src, out = sys.argv[1], sys.argv[2]
DEBUG = os.environ.get("DEBUG_BZ", "0") == "1"

data = json.load(open(src, "r", encoding="utf-8"))

def to_float(x):
    if x is None:
        return None
    if isinstance(x, (int, float)):
        return float(x)
    s = str(x).strip()
    if s == "" or s.lower() in ("null", "none", "nan"):
        return None
    try:
        return float(s)
    except:
        return None

def to_epoch(t):
    if t is None:
        return None
    s = str(t).strip()
    if not s:
        return None

    # ISO-ish: 2026-02-03T18:10:00Z or with offset
    if "T" in s:
        try:
            dt = datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc)
            return int(dt.timestamp())
        except:
            pass

    # Common SWPC: "YYYY-MM-DD HH:MM" or "YYYY-MM-DD HH:MM:SS" or fractional seconds
    # Normalize fractional seconds away
    s2 = re.sub(r"(\.\d+)$", "", s)

    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M"):
        try:
            dt = datetime.strptime(s2, fmt).replace(tzinfo=timezone.utc)
            return int(dt.timestamp())
        except:
            continue

    return None

rows = []

# Expect either array-of-arrays (header row) or array-of-dicts
if isinstance(data, list) and data and isinstance(data[0], list):
    header = [str(h).strip() for h in data[0]]
    idx = {name: i for i, name in enumerate(header)}

    # Required columns
    t_i  = idx.get("time_tag")
    bz_i = idx.get("bz_gsm")
    bt_i = idx.get("bt")

    # Optional columns
    bx_i = idx.get("bx_gsm")
    by_i = idx.get("by_gsm")

    if DEBUG:
        print("DEBUG header:", header, file=sys.stderr)
        if len(data) > 1:
            print("DEBUG first row:", data[1], file=sys.stderr)
        print("DEBUG idx:", {"time_tag": t_i, "bx_gsm": bx_i, "by_gsm": by_i, "bz_gsm": bz_i, "bt": bt_i}, file=sys.stderr)

    if t_i is None or bz_i is None or bt_i is None:
        print("WARN: missing expected columns; not publishing", file=sys.stderr)
        sys.exit(2)

    for r in data[1:]:
        if not isinstance(r, list):
            continue
        if len(r) <= max(t_i, bz_i, bt_i):
            continue

        epoch = to_epoch(r[t_i])
        bz = to_float(r[bz_i])
        bt = to_float(r[bt_i])

        if epoch is None or bz is None or bt is None:
            continue

        bx = to_float(r[bx_i]) if bx_i is not None and bx_i < len(r) else None
        by = to_float(r[by_i]) if by_i is not None and by_i < len(r) else None
        bx = bx if bx is not None else -999.9
        by = by if by is not None else -999.9

        rows.append((epoch, bx, by, bz, bt))

elif isinstance(data, list) and data and isinstance(data[0], dict):
    if DEBUG:
        print("DEBUG keys:", list(data[0].keys()), file=sys.stderr)

    for r in data:
        epoch = to_epoch(r.get("time_tag"))
        bz = to_float(r.get("bz_gsm"))
        bt = to_float(r.get("bt"))
        if epoch is None or bz is None or bt is None:
            continue
        bx = to_float(r.get("bx_gsm"))
        by = to_float(r.get("by_gsm"))
        bx = bx if bx is not None else -999.9
        by = by if by is not None else -999.9
        rows.append((epoch, bx, by, bz, bt))
else:
    print("WARN: unexpected JSON structure; not publishing", file=sys.stderr)
    sys.exit(2)

rows.sort(key=lambda x: x[0])
rows = rows[-150:]

if len(rows) < 150:
    if DEBUG:
        print("DEBUG parsed rows:", len(rows), file=sys.stderr)
        if len(rows) > 0:
            print("DEBUG last row:", rows[-1], file=sys.stderr)
    print(f"WARN: only {len(rows)}/150 valid samples; not publishing", file=sys.stderr)
    sys.exit(2)

with open(out, "w", encoding="ascii") as f:
    f.write("# UNIX        Bx     By     Bz     Bt\n")

    for epoch, bx, by, bz, bt in rows:
        f.write(f"{epoch:<10d} {bx:6.1f} {by:6.1f} {bz:6.1f} {bt:6.1f}\n")

print("OK: wrote 150 samples", file=sys.stdout)
PY

# If python exited 2, keep the old file (don’t publish a short one)
rc=$?
if [[ "$rc" -eq 2 ]]; then
  exit 0
fi

mv "$TMP_OUT" "$OUT"
chmod 0644 "$OUT"

