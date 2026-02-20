#!/usr/bin/env bash
set -euo pipefail

MAPDIR="${MAPDIR:-/opt/hamclock-backend/htdocs/ham/HamClock/maps}"
OUTDIR="${OUTDIR:-/opt/hamclock-backend/htdocs/ham/HamClock/maps}"
VENV="/opt/hamclock-backend/venv"
BASE="/opt/hamclock-backend"

# Load unified size list
# shellcheck source=/dev/null
source "/opt/hamclock-backend/scripts/lib_sizes.sh"
ohb_load_sizes

PY="${PY:-python3}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER="${BUILDER:-$SCRIPT_DIR/build_muf_rt.py}"

for sz in "${SIZES[@]}"; do
  w="${sz%x*}"
  h="${sz#*x}"

  base_day="$MAPDIR/map-D-$sz-Geo.bmp.z"
  base_night="$MAPDIR/map-D-$sz-Geo.bmp.z"

  if [[ ! -s "$base_day" ]]; then
    echo "WARN: missing base day $base_day; skipping $sz" >&2
    continue
  fi
  if [[ ! -s "$base_night" ]]; then
    echo "WARN: missing base night $base_night; skipping $sz" >&2
    continue
  fi

  echo "Rendering MUF-RT $sz (D+N) ..."
  "$VENV/bin/python" "$BASE/scripts/build_muf_rt.py" \
  --width "$w" \
  --height "$h" \
  --grid-w 720 \
  --grid-h 360 \
  --base-day "$base_day" \
  --outdir "$MAPDIR" \
  --alpha 0.38 \
  --k 16 \
  --p 2.8 \
  --influence-km 4000 \
  --use-sza

done

