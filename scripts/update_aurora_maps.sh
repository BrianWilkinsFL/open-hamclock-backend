#!/bin/bash
set -e

source "/opt/hamclock-backend/scripts/lib_sizes.sh"
ohb_load_sizes   # populates SIZES=(...) per OHB conventions

JSON=ovation.json
XYZ=ovation.xyz

echo "Fetching OVATION..."
curl -fs https://services.swpc.noaa.gov/json/ovation_aurora_latest.json -o "$JSON"

# JSON -> XYZ with longitudes in 0..360 and seam duplication
python3 <<'EOF'
import json
d=json.load(open("ovation.json"))
with open("ovation.xyz","w") as f:
    for lon,lat,val in d["coordinates"]:
        if val <= 0:
            continue
        if lon < 0:
            lon += 360.0
        f.write(f"{lon:.6f} {lat:.6f} {val:.6f}\n")
        if lon == 0.0:
            f.write(f"360.000000 {lat:.6f} {val:.6f}\n")
EOF

echo "Gridding aurora once..."

gmt xyz2grd "$XYZ" -R0/360/-90/90 -I1 -Gaurora_native.nc
gmt grdsample aurora_native.nc -I0.1 -Gaurora_dense.nc
gmt grdfilter aurora_dense.nc -Fg4 -D0 -Gaurora.nc

#cat > aurora.cpt <<EOF
#0   0/0/0       5   0/0/0
#5   0/120/0     20  0/255/0
#20  0/255/0     50  255/255/0
#50  255/255/0  100 255/0/0
#EOF
cat > aurora.cpt <<EOF
0    0/0/0     1    0/0/0
1    0/40/0    20   0/120/0
20   0/120/0  100   0/255/0
EOF


echo "Rendering maps..."

OUTDIR="/opt/hamclock-backend/htdocs/ham/HamClock/maps"
mkdir -p "$OUTDIR"

for DN in D N; do

for SZ in "${SIZES[@]}"; do
  BASE="$OUTDIR/aurora_${DN}_${SZ}"
  PNG="${BASE}.png"
  PNG_FIXED="${BASE}_fixed.png"
  BMP="$OUTDIR/map-${DN}-${SZ}-Aurora.bmp"
  
  W=${SZ%x*}
  H=${SZ#*x}

  echo "  -> BASE=$BASE"
  echo "  -> PNG=$PNG"
 
  gmt begin "$BASE" png
    gmt coast -R0/360/-90/90 -JQ0/${W}p -Gblack -Sblack -A10000
    # Day white veil (ONLY for D maps)
    if [[ "$DN" == "D" ]]; then
     gmt coast -R0/360/-90/90 -JQ0/${W}p -Gwhite -Swhite -A10000 -t85
    fi
    gmt grdimage aurora.nc -C"$CPT" -Q -n+b -t40
    gmt coast -R0/360/-90/90 -JQ0/${W}p -W0.75p,white -N1/0.5p,white -A10000
  gmt end || { echo "gmt failed for $SZ"; continue; }

  convert "$PNG" -resize "${SZ}!" "$PNG_FIXED" || { echo "resize failed for $SZ"; continue; }

  convert "$PNG_FIXED" -flip "$PNG_FIXED"

  echo "  -> PNG_FIXED=$PNG_FIXED"
  convert "$PNG_FIXED" \
    -type TrueColor \
    -define bmp:subtype=RGB565 \
    BMP3:"$BMP" || { echo "bmp convert failed for $SZ"; continue; }

  echo "  -> BMP=$BMP"

# Force BMP to top-down (negative height) for HamClock
python3 - <<EOF
import struct

with open("$BMP","r+b") as f:
    f.seek(22)                 # biHeight offset
    h = struct.unpack("<i", f.read(4))[0]
    if h > 0:
        f.seek(22)
        f.write(struct.pack("<i", -h))
EOF

# Zlib compress (HamClock format)
python3 - <<EOF
import zlib
data = open("$BMP","rb").read()
open("$BMP.z","wb").write(zlib.compress(data,9))
EOF

rm -f "$PNG" "$BMP"

done

done

rm -f aurora_native.nc aurora_dense.nc aurora.nc aurora.cpt ovation.xyz


echo "Done."

