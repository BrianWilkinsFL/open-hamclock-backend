#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

OUTDIR="/opt/hamclock-backend/htdocs/ham/HamClock/maps"
TMPROOT="/opt/hamclock-backend/tmp"
URL="https://services.swpc.noaa.gov/images/d-rap/global.png"
DAY_WHITE_PCT="${DAY_WHITE_PCT:-18}"   # 0..40 is a sane tuning range

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 1; }; }
need curl
need convert
need python3
need install

mkdir -p "$OUTDIR" "$TMPROOT"

# Load sizes from lib_sizes.sh
# shellcheck source=/dev/null
source "/opt/hamclock-backend/scripts/lib_sizes.sh"
ohb_load_sizes   # populates SIZES=(...) per OHB conventions

# Temp dir under /opt/hamclock-backend/tmp (www-data writable)
TMPDIR="$(mktemp -d -p "$TMPROOT" drap.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

IN="$TMPDIR/drap.png"
curl -fsSL -A "open-hamclock-backend/1.0" --retry 2 --retry-delay 2 -o "$IN" "$URL"

# Source crop rectangle (in NOAA source pixels)
SRC_CROP_W=677
SRC_CROP_H=330
SRC_XOFF=12
SRC_YOFF=0

# Crop once, reuse for all sizes (avoids repeated decode)
CROPPED="$TMPDIR/drap_cropped.png"
convert "$IN" -crop "${SRC_CROP_W}x${SRC_CROP_H}+${SRC_XOFF}+${SRC_YOFF}" +repage "$CROPPED"

zlib_compress() {
  local in="$1"
  local out="$2"
  python3 - <<'PY' "$in" "$out"
import zlib, sys
data = open(sys.argv[1], "rb").read()
open(sys.argv[2], "wb").write(zlib.compress(data, 9))
PY
}

# Write BMPv4 (BITMAPV4HEADER), 16bpp RGB565, top-down
make_bmp_v4_rgb565_topdown() {
  local inraw="$1" outbmp="$2" W="$3" H="$4"
  python3 - <<'PY' "$inraw" "$outbmp" "$W" "$H"
import struct, sys
inraw, outbmp, W, H = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])

raw = open(inraw, "rb").read()
exp = W*H*3
if len(raw) != exp:
    raise SystemExit(f"RAW size {len(raw)} != expected {exp}")

pix = bytearray(W*H*2)
j = 0
for i in range(0, len(raw), 3):
    r = raw[i]
    g = raw[i+1]
    b = raw[i+2]
    v = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)  # RGB565
    pix[j:j+2] = struct.pack("<H", v)
    j += 2

# BMP headers
bfOffBits = 14 + 108  # filehdr (14) + BITMAPV4HEADER (108)
bfSize = bfOffBits + len(pix)
filehdr = struct.pack("<2sIHHI", b"BM", bfSize, 0, 0, bfOffBits)

biSize = 108
biWidth = W
biHeight = -H              # top-down DIB
biPlanes = 1
biBitCount = 16
biCompression = 3          # BI_BITFIELDS
biSizeImage = len(pix)

rmask, gmask, bmask, amask = 0xF800, 0x07E0, 0x001F, 0x0000
cstype = 0x73524742        # 'sRGB'
endpoints = b"\x00"*36
gamma = b"\x00"*12

v4hdr = struct.pack(
    "<IiiHHIIIIII",
    biSize, biWidth, biHeight, biPlanes, biBitCount, biCompression,
    biSizeImage, 0, 0, 0, 0
) + struct.pack("<IIII", rmask, gmask, bmask, amask) \
  + struct.pack("<I", cstype) + endpoints + gamma

with open(outbmp, "wb") as f:
    f.write(filehdr)
    f.write(v4hdr)
    f.write(pix)

# quick sanity
with open(outbmp, "rb") as f:
    if f.read(2) != b"BM":
        raise SystemExit("Bad BMP signature")
PY
}

for sz in "${SIZES[@]}"; do
  W="${sz%x*}"
  H="${sz#*x}"

  resized_n_png="$TMPDIR/drapN_${W}x${H}.png"
  resized_d_png="$TMPDIR/drapD_${W}x${H}.png"
  raw_rgb_d="$TMPDIR/drapD_${W}x${H}.rgb"
  raw_rgb_n="$TMPDIR/drapN_${W}x${H}.rgb"

  day_bmp_tmp="$TMPDIR/map-D-${W}x${H}-DRAP-S.bmp"
  night_bmp_tmp="$TMPDIR/map-N-${W}x${H}-DRAP-S.bmp"

  # Resize once for night
  convert "$CROPPED" -resize "${W}x${H}!" +repage "$resized_n_png"

  # Day = night + "white wash" (this is the “white mask” look)
  convert "$resized_n_png" -fill white -colorize "${DAY_WHITE_PCT}%" "$resized_d_png"

  # Emit raw RGB and build distinct BMPs
  convert "$resized_d_png" RGB:"$raw_rgb_d"
  convert "$resized_n_png" RGB:"$raw_rgb_n"

  make_bmp_v4_rgb565_topdown "$raw_rgb_d" "$day_bmp_tmp" "$W" "$H"
  make_bmp_v4_rgb565_topdown "$raw_rgb_n" "$night_bmp_tmp" "$W" "$H"

  install -m 0644 "$day_bmp_tmp"   "$OUTDIR/map-D-${W}x${H}-DRAP-S.bmp"
  install -m 0644 "$night_bmp_tmp" "$OUTDIR/map-N-${W}x${H}-DRAP-S.bmp"

  zlib_compress "$OUTDIR/map-D-${W}x${H}-DRAP-S.bmp" "$OUTDIR/map-D-${W}x${H}-DRAP-S.bmp.z"
  zlib_compress "$OUTDIR/map-N-${W}x${H}-DRAP-S.bmp" "$OUTDIR/map-N-${W}x${H}-DRAP-S.bmp.z"
done

echo "OK: DRAP maps updated into $OUTDIR"

