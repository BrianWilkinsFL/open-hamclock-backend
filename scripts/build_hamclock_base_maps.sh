#!/bin/bash
set -e

export GMT_END_SHOW=off

# ImageMagick controls (only used for smaller sizes)
export MAGICK_TMPDIR=/tmp/imcache
export MAGICK_MEMORY_LIMIT=256MiB
export MAGICK_MAP_LIMIT=512MiB
export MAGICK_DISK_LIMIT=8GiB

mkdir -p /tmp/imcache

# HamClock widths (2:1 maps)
SIZES=(660 1320 1980 2640 3960 5280 5940 7920)

COAST_SMALL=1.0
BORDER_SMALL=0.75
COAST_LARGE=1.5
BORDER_LARGE=1.0

for W in "${SIZES[@]}"; do

  H=$((W/2))
  OUT="world_${W}"

  echo "Building ${W}x${H} ..."

  if [ "$W" -ge 3960 ]; then
    COAST=$COAST_LARGE
    BORDER=$BORDER_LARGE
  else
    COAST=$COAST_SMALL
    BORDER=$BORDER_SMALL
  fi

  #
  # GMT → PPM
  #
  gmt coast \
    -R-180/180/-90/90 \
    -JQ0/${W}p \
    -W${COAST}p,white \
    -N1/${BORDER}p,white \
    -A10000 \
    -B+gblack \
    -ppm ${OUT}

  gmt clear cache 2>/dev/null || true

  #
  # PPM → RGB565 BMP
  # ImageMagick for small maps, Python for large
  #
  if [ "$W" -lt 5280 ]; then

    convert ${OUT}.ppm \
      -define bmp:subtype=RGB565 \
      ${OUT}.bmp

  else

    python3 ppm_to_rgb565.py ${OUT}.ppm ${OUT}.bmp

  fi

  rm -f ${OUT}.ppm

  echo "  -> ${OUT}.bmp"

done

echo "All maps built."
