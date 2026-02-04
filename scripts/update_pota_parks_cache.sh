#!/bin/sh
set -eu

CACHE_DIR=/opt/hamclock-backend/cache
OUT="$CACHE_DIR/all_parks_ext.csv"
TMP="$OUT.tmp"

mkdir -p "$CACHE_DIR"
curl -fsS "https://pota.app/all_parks_ext.csv" -o "$TMP"
mv "$TMP" "$OUT"

