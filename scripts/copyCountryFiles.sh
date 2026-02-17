#!/usr/bin/env bash
set -euo pipefail

SRC="/opt/hamclock-backend/htdocs/ham/HamClock/maps"
DEST="${1:-.}"

mkdir -p "$DEST"

shopt -s nullglob
files=("$SRC"/map-*-*x*-Countries.bmp "$SRC"/map-*-*x*-Countries.bmp.z)
shopt -u nullglob

if ((${#files[@]} == 0)); then
  echo "ERROR: No Countries files found in: $SRC" >&2
  exit 2
fi

cp -av "${files[@]}" "$DEST"/

