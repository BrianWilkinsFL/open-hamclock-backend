#!/usr/bin/env bash
# kc2g_muf_heatmap.sh
# Generates MUF heatmap BMPs (RGB565, zlib-compressed) for HamClock
# Matches aurora map pipeline: D/N variants, all sizes from lib_sizes.sh
set -euo pipefail

export GMT_USERDIR=/opt/hamclock-backend/tmp
cd "$GMT_USERDIR"

source "/opt/hamclock-backend/scripts/lib_sizes.sh"
ohb_load_sizes
echo "Building sizes: ${OHB_SIZES_NORM}"

MUFD_URL="https://prop.kc2g.com/renders/current/mufd-normal-now.geojson"
STAS_URL="https://prop.kc2g.com/api/stations.json"
OUTDIR="/opt/hamclock-backend/htdocs/ham/HamClock/maps"
CPT="/opt/hamclock-backend/scripts/muf_hamclock.cpt"
R="-180/180/-90/90"

mkdir -p "$OUTDIR"

if [[ ! -f "$CPT" ]]; then
  echo "ERROR: $CPT not found" >&2; exit 1
fi

# ── 1. Fetch ───────────────────────────────────────────────────────────────────
echo "Fetching MUF data..."
curl -fsSL "$MUFD_URL" -o mufd.geojson
curl -fsSL "$STAS_URL" -o stations.json

# ── 2. Build smooth grid (once) ────────────────────────────────────────────────
python3 - << 'PYEOF'
import json, sys
import numpy as np
from scipy.interpolate import griddata
from scipy.ndimage import gaussian_filter

gj   = json.load(open("mufd.geojson"))
stas = json.load(open("stations.json"))

# Contour points
pts = []
for feat in gj["features"]:
    value = float(feat["properties"]["level-value"])
    geom  = feat["geometry"]
    coords = geom["coordinates"]
    lines = [coords] if geom["type"] == "LineString" else coords
    for line in lines:
        for lon, lat in line:
            pts.append((float(lon), float(lat), value))
pts = np.array(pts)
print(f"  Contour levels: {sorted(set(pts[:,2]))}", file=sys.stderr)

# Station range for stretch calibration
sta_mufd = []
for row in stas:
    mufd = row.get("mufd") or row.get("muf")
    conf = float(row.get("confidence", 1.0) or 1.0)
    if mufd is None or conf < 0.1: continue
    sta_mufd.append(float(mufd))
sta_mufd = np.array(sta_mufd)
sta_lo = max(5.0,  np.percentile(sta_mufd,  5))
sta_hi = min(35.0, np.percentile(sta_mufd, 95))
print(f"  Station 5–95pct: {sta_lo:.1f} – {sta_hi:.1f} MHz", file=sys.stderr)

# Interpolate at 0.5°
lons = np.linspace(-180, 180, 721)
lats = np.linspace(-90,   90, 361)
glon, glat = np.meshgrid(lons, lats)

print("  Interpolating...", file=sys.stderr)
grid = griddata(pts[:, :2], pts[:, 2], (glon, glat), method="linear")
nan_mask = np.isnan(grid)
if nan_mask.any():
    grid_nn = griddata(pts[:, :2], pts[:, 2], (glon, glat), method="nearest")
    grid[nan_mask] = grid_nn[nan_mask]
grid = gaussian_filter(grid, sigma=1.5)

c_min, c_max = grid.min(), grid.max()
grid = sta_lo + (grid - c_min) / (c_max - c_min) * (sta_hi - sta_lo)
grid = np.clip(grid, 5, 35)
print(f"  Final: {grid.min():.1f} – {grid.max():.1f} MHz", file=sys.stderr)

with open("mufd_grid.xyz", "w") as f:
    for j in range(grid.shape[0]):
        for i in range(grid.shape[1]):
            f.write(f"{lons[i]:.2f}\t{lats[j]:.2f}\t{grid[j,i]:.3f}\n")
print("  Done.", file=sys.stderr)
PYEOF

gmt xyz2grd mufd_grid.xyz -R${R} -I0.5 -Gmufd.grd
echo "  Grid: $(gmt grdinfo mufd.grd -C | awk '{print $6, "-", $7, "MHz"}')"

# ── 3. Station files (once) ────────────────────────────────────────────────────
python3 - << 'PYEOF'
import json, sys
with open("stations.json") as fh:
    data = json.load(fh)
circles, labels = [], []
for row in data:
    st   = row.get("station", {})
    lon  = st.get("longitude")
    lat  = st.get("latitude")
    mufd = row.get("mufd") or row.get("muf")
    conf = float(row.get("confidence", 1.0) or 1.0)
    if lon is None or lat is None or mufd is None: continue
    if float(conf) < 0.05: continue
    mufd = float(mufd)
    circles.append(f"{float(lon):.3f}\t{float(lat):.3f}\t{mufd:.2f}")
    labels.append( f"{float(lon):.3f}\t{float(lat):.3f}\t{mufd:.0f}")
with open("stations_circles.txt", "w") as f:
    f.write("\n".join(circles) + "\n")
with open("stations_labels.txt", "w") as f:
    f.write("\n".join(labels) + "\n")
print(f"  {len(circles)} stations", file=sys.stderr)
PYEOF

# ── 4. Render each DN variant × size ──────────────────────────────────────────
echo "Rendering maps..."

for DN in D N; do
for SZ in "${SIZES[@]}"; do

  W="${SZ%%x*}"
  H="${SZ##*x}"
  BASE="muf_${DN}_${SZ}"
  PNG="${BASE}.png"
  PNG_FIXED="${BASE}_fixed.png"
  BMP="${BASE}.bmp"
  OUTFILE="${OUTDIR}/map-${DN}-${SZ}-MUF-RT.bmp.z"

  echo "  -> ${DN} ${SZ}"

  # Scale marker/font/line sizes relative to 660px baseline
  W_IN=$(echo "scale=4; $W / 100" | bc)
  CIRCLE_IN=$(echo "scale=4; 0.15 * $W / 660" | bc)
  FONT_PT=$(echo "scale=0; 6 * $W / 660" | bc)
  COAST_PT=$(echo "scale=4; 0.6 * $W / 660" | bc)
  BORDER_PT=$(echo "scale=4; 0.4 * $W / 660" | bc)
  CONTOUR_PT=$(echo "scale=4; 0.5 * $W / 660" | bc)
  J="Q0/${W_IN}i"

  gmt begin "$BASE" png E100
    gmt set MAP_FRAME_TYPE=plain
    # Black base
    gmt coast -R${R} -J${J} -Gblack -Sblack -B0 -Dc
    # MUF heatmap
    gmt grdimage mufd.grd -R${R} -J${J} -C${CPT} -Q
    # Day white veil (D maps only)
    if [[ "$DN" == "D" ]]; then
      gmt coast -R${R} -J${J} -Gwhite -Swhite -B0 -Dc -t80
    fi
    # Coastlines + borders
    gmt coast -R${R} -J${J} -W${COAST_PT}p,black -N1/${BORDER_PT}p,black -Dc
    # Contour lines
    gmt grdcontour mufd.grd -R${R} -J${J} -C2 -W${CONTOUR_PT}p,white@60 -S4
    # Station circles + labels
    gmt plot stations_circles.txt -R${R} -J${J} \
        -Sc${CIRCLE_IN}i -G0/200/0 -W0.5p,black
    gmt text stations_labels.txt  -R${R} -J${J} \
        -F+f${FONT_PT}p,Helvetica-Bold,black+jCM
  gmt end || { echo "    gmt failed for ${DN} ${SZ}"; continue; }

  # Resize to exact pixel dimensions
  convert "$PNG" -resize "${SZ}!" "$PNG_FIXED" \
    || { echo "    resize failed for ${DN} ${SZ}"; continue; }

  # Extract raw RGB bytes, then write proper BMPv4 RGB565 top-down
  RAW="${BASE}.raw"
  convert "$PNG_FIXED" RGB:"$RAW" || { echo "    raw extract failed for ${DN} ${SZ}"; continue; }
  python3 - << EOF
import struct, sys
inraw, outbmp, W, H = "$RAW", "$BMP", int($W), int($H)

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
) + struct.pack("<IIII", rmask, gmask, bmask, amask) \
  + struct.pack("<I", cstype) + endpoints + gamma

with open(outbmp, "wb") as f:
    f.write(filehdr)
    f.write(v4hdr)
    f.write(pix)
EOF
  rm -f "$RAW" 
  # Zlib compress → final output
  python3 - << EOF
import zlib
data = open("$BMP", "rb").read()
open("${OUTFILE}", "wb").write(zlib.compress(data, 9))
EOF

  echo "    -> ${OUTFILE}"

  # Clean up intermediates for this size
  rm -f "$PNG" "$PNG_FIXED" "$BMP"

done
done

# ── 5. Clean up shared intermediates ──────────────────────────────────────────
rm -f mufd.geojson stations.json mufd_grid.xyz mufd.grd \
      stations_circles.txt stations_labels.txt

echo "Done."
