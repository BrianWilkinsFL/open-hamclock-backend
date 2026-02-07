#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# How to run: sudo -u www-data PAD_FRAC_X=-0.02 PAD_FRAC_Y=-0.08 BASE_PAD_Y=-30 bash update_drap_maps.sh 

OUTDIR="/opt/hamclock-backend/htdocs/ham/HamClock/maps"

#SIZES=(
#  "660x330"
#  "1320x660"
#  "1980x990"
#  "2640x1320"
#  "3960x1980"
#  "5280x2640"
#  "5940x2970"
#  "7920x3960"
#)

# Load unified size list
# shellcheck source=/dev/null
source "/opt/hamclock-backend/scripts/lib_sizes.sh"
ohb_load_sizes

SRC_URL="https://services.swpc.noaa.gov/images/d-rap/global.png"

REF_BASE_W=660
REF_BASE_H=330
REF_CROP_W="${REF_CROP_W:-544}"
REF_CROP_H="${REF_CROP_H:-267}"

# Your tuned proportional padding (applies to sizes != 660x330)
PAD_FRAC_X="${PAD_FRAC_X:--0.02}"
PAD_FRAC_Y="${PAD_FRAC_Y:--0.08}"

# Extra pixel trim for ONLY the 660x330 case (negative trims more bottom legend)
BASE_PAD_Y="${BASE_PAD_Y:--12}"

CROP_X=0
CROP_Y=0

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 1; }; }
need curl
need convert
need python3
need install

mkdir -p "$OUTDIR"

src_png="$TMPDIR/drap_global.png"
curl -fsS -A "open-hamclock-backend/1.0" --retry 2 --retry-delay 2 "$SRC_URL" -o "$src_png"

make_bmp_v4_rgb565_topdown() {
  local inraw="$1"
  local outbmp="$2"
  local W="$3"
  local H="$4"

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
    r = raw[i]; g = raw[i+1]; b = raw[i+2]
    v = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
    pix[j:j+2] = struct.pack("<H", v)
    j += 2

bfOffBits = 14 + 108  # 122
bfSize = bfOffBits + len(pix)
filehdr = struct.pack("<2sIHHI", b"BM", bfSize, 0, 0, bfOffBits)

biSize = 108
biWidth = W
biHeight = -H
biPlanes = 1
biBitCount = 16
biCompression = 3
biSizeImage = len(pix)

rmask, gmask, bmask, amask = 0xF800, 0x07E0, 0x001F, 0x0000
cstype = 0x73524742  # 'sRGB'
endpoints = b"\x00"*36
gamma = b"\x00"*12

v4hdr = struct.pack(
    "<IiiHHIIIIII",
    biSize, biWidth, biHeight, biPlanes, biBitCount, biCompression,
    biSizeImage, 0, 0, 0, 0
) + struct.pack("<IIII", rmask, gmask, bmask, amask) \
  + struct.pack("<I", cstype) + endpoints + gamma

with open(outbmp, "wb") as f:
    f.write(filehdr); f.write(v4hdr); f.write(pix)

with open(outbmp, "rb") as f:
    if f.read(2) != b"BM":
        raise SystemExit("BAD BMP: missing BM signature")
PY
}

zlib_compress() {
  local in="$1"
  local out="$2"
  python3 - <<'PY' "$in" "$out"
import zlib, sys
data = open(sys.argv[1], "rb").read()
open(sys.argv[2], "wb").write(zlib.compress(data, 9))
PY
}

compute_crop_wh() {
  local W="$1" H="$2"
  python3 - <<PY
import math
W=int("$W"); H=int("$H")
REFW=int("$REF_BASE_W"); REFH=int("$REF_BASE_H")
RCW=int("$REF_CROP_W"); RCH=int("$REF_CROP_H")
pfx=float("$PAD_FRAC_X"); pfy=float("$PAD_FRAC_Y")
base_pad_y=int("$BASE_PAD_Y")

# Base proportional interior crop (works for all sizes, including 660x330)
cw = int(math.floor((W * RCW) / REFW + 0.5))
ch = int(math.floor((H * RCH) / REFH + 0.5))

if W == REFW and H == REFH:
    # tighten only 660x330 bottom
    ch += base_pad_y
else:
    # proportional padding for other sizes
    cw += int(math.floor(W * pfx + 0.5))
    ch += int(math.floor(H * pfy + 0.5))

cw = max(1, min(W, cw))
ch = max(1, min(H, ch))
print(cw, ch)
PY
}

for wh in "${SIZES[@]}"; do
  W="${wh%x*}"
  H="${wh#*x}"

  read -r CROP_W CROP_H < <(compute_crop_wh "$W" "$H")

  echo "DRAP ${W}x${H}: crop ${CROP_W}x${CROP_H}+${CROP_X}+${CROP_Y}"

  norm_png="$TMPDIR/drap_${W}x${H}_norm.png"
  crop_png="$TMPDIR/drap_${W}x${H}_crop.png"
  final_png="$TMPDIR/drap_${W}x${H}_final.png"
  raw_rgb="$TMPDIR/drap_${W}x${H}.rgb"

  convert "$src_png" -alpha off -colorspace sRGB -resize "${W}x${H}!" "$norm_png"
  convert "$norm_png" -crop "${CROP_W}x${CROP_H}+${CROP_X}+${CROP_Y}" +repage "$crop_png"
  convert "$crop_png" -resize "${W}x${H}!" "$final_png"
  convert "$final_png" -alpha off -colorspace sRGB -depth 8 "rgb:$raw_rgb"

  day_tmp="$TMPDIR/map-D-${W}x${H}-DRAP-S.bmp"
  night_tmp="$TMPDIR/map-N-${W}x${H}-DRAP-S.bmp"

  make_bmp_v4_rgb565_topdown "$raw_rgb" "$day_tmp" "$W" "$H"
  cp -f "$day_tmp" "$night_tmp"

  install -m 0644 "$day_tmp"   "$OUTDIR/map-D-${W}x${H}-DRAP-S.bmp"
  install -m 0644 "$night_tmp" "$OUTDIR/map-N-${W}x${H}-DRAP-S.bmp"

  zlib_compress "$OUTDIR/map-D-${W}x${H}-DRAP-S.bmp" "$OUTDIR/map-D-${W}x${H}-DRAP-S.bmp.z"
  zlib_compress "$OUTDIR/map-N-${W}x${H}-DRAP-S.bmp" "$OUTDIR/map-N-${W}x${H}-DRAP-S.bmp.z"
done

echo "OK: DRAP maps updated into $OUTDIR"

