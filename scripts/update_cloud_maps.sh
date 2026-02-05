#!/usr/bin/env bash
set -euo pipefail

OUTDIR="/opt/hamclock-backend/htdocs/ham/HamClock/maps"

# All target WxH sizes for Clouds
SIZES=(
  "660x330"
  "1320x660"
  "1980x990"
  "2640x1320"
  "3960x1980"
  "5280x2640"
  "5940x2970"
  "7920x3960"
)

FTP_DIR="ftp://public.sos.noaa.gov/rt/sat/linear/raw/"
PATTERN='^linear_rgb_cyl_[0-9]{8}_[0-9]{4}\.jpg$'

# Night transform (tunable)
# Default values are what we used for 660x330.
NIGHT_MULT="${NIGHT_MULT:-0.39}"
NIGHT_ADD="${NIGHT_ADD:-8}"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 1; }; }
need curl
need convert
need python3
need install

mkdir -p "$OUTDIR"

# Find newest source JPG by filename sort (timestamp is embedded in the name)
latest="$(curl -fsS --list-only "$FTP_DIR" \
  | tr -d '\r' \
  | grep -E "$PATTERN" \
  | sort \
  | tail -n 1 || true)"

if [[ -z "$latest" ]]; then
  echo "ERROR: Could not find any matching files in $FTP_DIR" >&2
  exit 1
fi

src_jpg="$TMPDIR/$latest"
curl -fsS -A "open-hamclock-backend/1.0" --retry 2 --retry-delay 2 "${FTP_DIR}${latest}" -o "$src_jpg"

# Build BMPv4 RGB565 top-down from a raw RGB888 file
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
    r = raw[i]
    g = raw[i+1]
    b = raw[i+2]
    v = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
    pix[j:j+2] = struct.pack("<H", v)
    j += 2

bfType = b"BM"
bfOffBits = 14 + 108  # 122
bfSize = bfOffBits + len(pix)
filehdr = struct.pack("<2sIHHI", bfType, bfSize, 0, 0, bfOffBits)

biSize = 108
biWidth = W
biHeight = -H            # top-down
biPlanes = 1
biBitCount = 16
biCompression = 3        # BI_BITFIELDS
biSizeImage = len(pix)

bV4RedMask   = 0xF800
bV4GreenMask = 0x07E0
bV4BlueMask  = 0x001F
bV4AlphaMask = 0x0000
bV4CSType    = 0x73524742  # 'sRGB'
endpoints = b"\x00" * 36
gamma = b"\x00" * 12

v4hdr = struct.pack(
    "<IiiHHIIIIII",
    biSize, biWidth, biHeight, biPlanes, biBitCount, biCompression,
    biSizeImage, 0, 0, 0, 0
) + struct.pack("<IIII", bV4RedMask, bV4GreenMask, bV4BlueMask, bV4AlphaMask) \
  + struct.pack("<I", bV4CSType) + endpoints + gamma

if len(v4hdr) != 108:
    raise SystemExit(f"V4 header length {len(v4hdr)} != 108")

with open(outbmp, "wb") as f:
    f.write(filehdr)
    f.write(v4hdr)
    f.write(pix)

# Validate core expectations (prevents "file not bmp" surprises)
with open(outbmp, "rb") as f:
    if f.read(2) != b"BM":
        raise SystemExit("BAD: signature")
    f.seek(2); fsize = struct.unpack("<I", f.read(4))[0]
    f.seek(10); off = struct.unpack("<I", f.read(4))[0]
    f.seek(14); dib = struct.unpack("<I", f.read(4))[0]
    w = struct.unpack("<i", f.read(4))[0]
    h = struct.unpack("<i", f.read(4))[0]
    planes = struct.unpack("<H", f.read(2))[0]
    bpp = struct.unpack("<H", f.read(2))[0]
    comp = struct.unpack("<I", f.read(4))[0]
    f.seek(14+40); r,g,b = struct.unpack("<III", f.read(12))

exp_size = 122 + W*H*2
errs = []
if off != 122: errs.append(f"bfOffBits={off} (expected 122)")
if dib != 108: errs.append(f"DIB size={dib} (expected 108 BMPv4)")
if w != W or h != -H: errs.append(f"w,h={w},{h} (expected {W},-{H})")
if planes != 1: errs.append(f"planes={planes} (expected 1)")
if bpp != 16: errs.append(f"bpp={bpp} (expected 16)")
if comp != 3: errs.append(f"comp={comp} (expected 3)")
if (r,g,b) != (0xF800,0x07E0,0x001F): errs.append(f"masks={hex(r)},{hex(g)},{hex(b)}")
if fsize != exp_size: errs.append(f"file size={fsize} (expected {exp_size})")

if errs:
    raise SystemExit("BAD BMP:\n  " + "\n  ".join(errs))
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

for wh in "${SIZES[@]}"; do
  W="${wh%x*}"
  H="${wh#*x}"

  echo "Generating Clouds ${W}x${H} ..."

  day_png="$TMPDIR/day_${W}x${H}.png"
  night_png="$TMPDIR/night_${W}x${H}.png"

  # Day: unmodified (just normalize size/colorspace)
  convert "$src_jpg" \
    -alpha off -colorspace sRGB \
    -resize "${W}x${H}!" \
    "$day_png"

  # Night: scale down then lift blacks
  convert "$src_jpg" \
    -alpha off -colorspace sRGB \
    -resize "${W}x${H}!" \
    -evaluate multiply "$NIGHT_MULT" \
    -evaluate add "$NIGHT_ADD" \
    "$night_png"

  day_raw="$TMPDIR/day_${W}x${H}.rgb"
  night_raw="$TMPDIR/night_${W}x${H}.rgb"
  convert "$day_png"   -alpha off -colorspace sRGB -depth 8 "rgb:$day_raw"
  convert "$night_png" -alpha off -colorspace sRGB -depth 8 "rgb:$night_raw"

  day_bmp_tmp="$TMPDIR/map-D-${W}x${H}-Clouds.bmp"
  night_bmp_tmp="$TMPDIR/map-N-${W}x${H}-Clouds.bmp"

  make_bmp_v4_rgb565_topdown "$day_raw"   "$day_bmp_tmp"   "$W" "$H"
  make_bmp_v4_rgb565_topdown "$night_raw" "$night_bmp_tmp" "$W" "$H"

  install -m 0644 "$day_bmp_tmp"   "$OUTDIR/map-D-${W}x${H}-Clouds.bmp"
  install -m 0644 "$night_bmp_tmp" "$OUTDIR/map-N-${W}x${H}-Clouds.bmp"

  zlib_compress "$OUTDIR/map-D-${W}x${H}-Clouds.bmp" "$OUTDIR/map-D-${W}x${H}-Clouds.bmp.z"
  zlib_compress "$OUTDIR/map-N-${W}x${H}-Clouds.bmp" "$OUTDIR/map-N-${W}x${H}-Clouds.bmp.z"
done

echo "OK: updated Clouds from ${latest} (night multiply=${NIGHT_MULT} add=${NIGHT_ADD})"

