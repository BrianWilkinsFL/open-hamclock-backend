#!/bin/bash
set -euo pipefail

export GMT_USERDIR=/opt/hamclock-backend/tmp
cd "$GMT_USERDIR"

source "/opt/hamclock-backend/scripts/lib_sizes.sh"
ohb_load_sizes   # populates SIZES=(...) per OHB conventions

OUTDIR="/opt/hamclock-backend/htdocs/ham/HamClock/maps"
mkdir -p "$OUTDIR"

TXT="drap_global_frequencies.txt"

echo "Fetching DRAP..."
curl -fsSL -A "open-hamclock-backend/1.0" \
  https://services.swpc.noaa.gov/text/drap_global_frequencies.txt \
  -o "$TXT"

python3 <<'PYEOF'
with open("drap_global_frequencies.txt") as f:
    lines = f.readlines()

lons_hdr = None
rows = []
for line in lines:
    s = line.strip()
    if not s or s.startswith('#'):
        continue
    if s.startswith('---'):
        continue
    parts = s.split()
    if lons_hdr is None:
        if '|' not in s and all(p.lstrip('-').replace('.','').isdigit() for p in parts):
            lons_hdr = [float(p) for p in parts]
        continue
    parts = s.replace('|', ' ').split()
    lat = float(parts[0])
    vals = [float(x) for x in parts[1:]]
    rows.append((lat, vals))

src_lats = [r[0] for r in rows]
src_lons = lons_hdr
src = {}
for li, (lat, vals) in enumerate(rows):
    for loi, val in enumerate(vals):
        src[(li, loi)] = val

def lon_dist(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)

def nearest_haf(lat, lon):
    best_li = min(range(len(src_lats)), key=lambda i: abs(src_lats[i] - lat))
    best_loi = min(range(len(src_lons)), key=lambda i: lon_dist(src_lons[i], lon))
    return src.get((best_li, best_loi), 0.0)

# Write dense XYZ in -180..180 range — only nonzero values so background stays black.
with open("drap.xyz", "w") as out:
    lat = 89.0
    while lat >= -89.0:
        lon = -179.5
        while lon <= 179.5:
            val = nearest_haf(lat, lon)
            if val > 0:
                out.write(f"{lon:.2f} {lat:.2f} {val:.4f}\n")
            lon += 0.5
        lat -= 0.5
PYEOF

NPTS=$(wc -l < drap.xyz)
echo "Dense grid points with absorption: $NPTS"

if [ "$NPTS" -gt 0 ]; then
    gmt nearneighbor drap.xyz -R-180/180/-90/90 -I0.5 -S3 -Gdrap_nn.nc
    gmt grdfilter drap_nn.nc -Fg4 -D0 -Gdrap_s1.nc
    gmt grdfilter drap_s1.nc  -Fg3 -D0 -Gdrap.nc
else
    echo "No absorption data; generating quiet grid."
    gmt grdmath -R-180/180/-90/90 -I0.5 0 = drap.nc
fi

cat > drap.cpt <<'CPTEOF'
0.0    0/0/0         0.1   20/0/40
0.1   20/0/40        1.0   60/0/90
1.0   60/0/90        2.0   100/0/150
2.0   100/0/150      4.0   130/0/200
4.0   130/0/200      6.0   80/0/255
6.0   80/0/255       9.0   0/80/255
9.0   0/80/255      12.0   0/200/220
12.0  0/200/220     16.0   0/220/100
16.0  0/220/100     20.0   180/255/0
20.0  180/255/0     24.0   255/200/0
24.0  255/200/0     28.0   255/100/0
28.0  255/100/0     35.0   255/0/0
N     0/0/0
CPTEOF

zlib_compress() {
  local in="$1" out="$2"
  python3 -c "
import zlib, sys
data = open(sys.argv[1], 'rb').read()
open(sys.argv[2], 'wb').write(zlib.compress(data, 9))
" "$in" "$out"
}

# Write BMPv4 (BITMAPV4HEADER), 16bpp RGB565, top-down — matches ClearSkyInstitute format
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
    r = raw[i]; g = raw[i+1]; b = raw[i+2]
    v = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
    pix[j:j+2] = struct.pack("<H", v)
    j += 2

bfOffBits = 14 + 108
bfSize = bfOffBits + len(pix)
filehdr = struct.pack("<2sIHHI", b"BM", bfSize, 0, 0, bfOffBits)

biSize = 108
rmask, gmask, bmask, amask = 0xF800, 0x07E0, 0x001F, 0x0000
cstype = 0x73524742  # sRGB
endpoints = b"\x00"*36
gamma = b"\x00"*12

v4hdr = struct.pack("<IiiHHIIIIII",
    biSize, W, -H, 1, 16, 3, len(pix), 0, 0, 0, 0
) + struct.pack("<IIII", rmask, gmask, bmask, amask)   + struct.pack("<I", cstype) + endpoints + gamma

with open(outbmp, "wb") as f:
    f.write(filehdr)
    f.write(v4hdr)
    f.write(pix)
PY
}

echo "Rendering DRAP maps..."

for DN in D N; do
  for SZ in "${SIZES[@]}"; do
    W=${SZ%x*}
    H=${SZ#*x}
    BASE="$GMT_USERDIR/drap_${DN}_${SZ}"
    PNG="${BASE}.png"
    PNG_FIXED="${BASE}_fixed.png"
    BMP="$OUTDIR/map-${DN}-${SZ}-DRAP-S.bmp"

    echo "  -> ${DN} ${SZ}"

    gmt begin "$BASE" png
      gmt coast -R-180/180/-90/90 -JQ0/${W}p -Gblack -Sblack -A10000

      if [[ "$DN" == "D" ]]; then
        gmt coast -R-180/180/-90/90 -JQ0/${W}p -Gwhite -Swhite -A10000 -t80
      fi

      if [ "$NPTS" -gt 0 ]; then
        gmt grdimage drap.nc -Cdrap.cpt -Q -n+b -t25
      fi

      gmt coast -R-180/180/-90/90 -JQ0/${W}p -W0.5p,white -N1/0.4p,white -A10000
    gmt end || { echo "gmt failed for $DN $SZ"; continue; }

    convert "$PNG" -resize "${SZ}!" "$PNG_FIXED" || { echo "resize failed for $DN $SZ"; continue; }

    # Extract raw RGB then write proper BMPv4 RGB565 matching ClearSkyInstitute format
    RAW="$GMT_USERDIR/drap_${DN}_${SZ}.raw"
    convert "$PNG_FIXED" RGB:"$RAW" || { echo "raw extract failed for $DN $SZ"; continue; }
    make_bmp_v4_rgb565_topdown "$RAW" "$BMP" "$W" "$H" || { echo "bmp write failed for $DN $SZ"; continue; }
    rm -f "$RAW"

    zlib_compress "$BMP" "${BMP}.z"

    rm -f "$PNG" "$PNG_FIXED"
    echo "  -> Done: $BMP"
  done
done

rm -f drap_nn.nc drap_s1.nc drap.nc drap.cpt drap.xyz "$TXT"

echo "OK: DRAP maps updated into $OUTDIR"
