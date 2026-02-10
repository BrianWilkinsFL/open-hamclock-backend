#!/usr/bin/env bash
# update_wx_mb_maps.sh
#
# Generates HamClock Wx-mB maps in multiple sizes, pairing each WxH output with the
# corresponding WxH Countries base bitmap.
#
# Outputs (per size):
#   map-D-<WxH>-Wx-mB.bmp(.z)
#   map-N-<WxH>-Wx-mB.bmp(.z)   (only if map-N-<WxH>-Countries.bmp.z exists)
#
# Requires: curl, python3, ImageMagick not required, pygrib installed for python3.

set -euo pipefail
export LC_ALL=C

OUTDIR="/opt/hamclock-backend/htdocs/ham/HamClock/maps"
TMPROOT="/opt/hamclock-backend/tmp"
export MPLCONFIGDIR="$TMPROOT/mpl"

# Load unified size list
# shellcheck source=/dev/null
source "/opt/hamclock-backend/scripts/lib_sizes.sh"
ohb_load_sizes


# NOMADS GFS 0.25° subset endpoint (GRIB2 filter)
NOMADS_FILTER="https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1" >&2; exit 1; }; }
need curl
need python3
mkdir -p "$OUTDIR" "$TMPROOT" "$MPLCONFIGDIR"

TMPDIR="$(mktemp -d -p "$TMPROOT" wxmb.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

# Download latest available GFS cycle (f000) with only needed vars/levels
pick_and_download() {
  local ymd="$1" hh="$2"
  local file="gfs.t${hh}z.pgrb2.0p25.f000"
  local dir="%2Fgfs.${ymd}%2F${hh}%2Fatmos"

  # Request:
  # - PRMSL at mean sea level
  # - UGRD/VGRD at 10 m above ground
  local url="${NOMADS_FILTER}?file=${file}"\
    "&lev_mean_sea_level=on&lev_10_m_above_ground=on"\
    "&var_PRMSL=on&var_UGRD=on&var_VGRD=on"\
    "&leftlon=0&rightlon=359.75&toplat=90&bottomlat=-90"\
    "&dir=${dir}"

  echo "Trying GFS ${ymd} ${hh}Z ..."
  curl -fs -A "open-hamclock-backend/1.0" --retry 2 --retry-delay 2 "$url" -o "$TMPDIR/gfs.grb2"
  RETVAL=$?
  if [ $RETVAL -eq 0 ]; then
    echo "Downloaded: ${file} (${ymd} ${hh}Z)"
    echo "${ymd} ${hh}" > "$TMPDIR/gfs_cycle.txt"
  else
    echo "Curl error '$RETVAL' on GFS ${ymd} ${hh}Z"
  fi
  return $RETVAL
}

# NOAA typically makes the weather maps available 2-4 hours after nominal runtime
# which is every 6 hours.
MAP_INTERVAL=6
MAP_READY=2
NOW=$(date -d "$MAP_READY hours ago" +%s)

# round down to the neeart 6-hour interval
HOUR_NOW=$(date -d @$NOW +%H)
START_TIME=$(($NOW - (($HOUR_NOW % $MAP_INTERVAL)*3600) ))

# try back to 8 intervals
NUM_TRYS=8

# we want to throw an error if none of the attempts worked
downloaded=0

for ((try=0; try<$NUM_TRYS; try++)); do
  check_time=$(($START_TIME - $MAP_INTERVAL*3600*$try))
  d=$(date -u -d @${check_time} +%Y%m%d)
  hh=$(date -u -d @${check_time} +%H)

  if pick_and_download "$d" "$hh"; then
    downloaded=1
    break
  fi
done

if [[ "$downloaded" -ne 1 ]]; then
  echo "ERROR: could not download a recent GFS subset from NOMADS." >&2
  exit 1
fi

# Render a Wx-mB map for one size + one base
render_one() {
  local tag="$1" W="$2" H="$3" base="$4"

  python3 - <<'PY' "$TMPDIR/gfs.grb2" "$base" "$OUTDIR" "$tag" "$W" "$H"
import sys, zlib, struct
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pygrib

grb_path, base_path, outdir, tag, W, H = sys.argv[1:]
W = int(W); H = int(H)

def zread(path: str) -> bytes:
    data = open(path, "rb").read()
    return zlib.decompress(data) if path.endswith(".z") else data

def read_bmp_v4_rgb565_topdown(blob: bytes):
    if blob[0:2] != b"BM":
        raise ValueError("Not BMP")
    bfOffBits = struct.unpack_from("<I", blob, 10)[0]
    dib = struct.unpack_from("<I", blob, 14)[0]
    w = struct.unpack_from("<i", blob, 18)[0]
    h = struct.unpack_from("<i", blob, 22)[0]
    planes = struct.unpack_from("<H", blob, 26)[0]
    bpp = struct.unpack_from("<H", blob, 28)[0]
    comp = struct.unpack_from("<I", blob, 30)[0]
    if bfOffBits != 122 or dib != 108 or planes != 1 or bpp != 16 or comp != 3:
        raise ValueError(f"Unexpected BMP header off={bfOffBits} dib={dib} planes={planes} bpp={bpp} comp={comp}")
    if h >= 0:
        raise ValueError("Expected top-down BMP (negative height)")
    H0 = -h
    pix = blob[bfOffBits:bfOffBits + (w*H0*2)]
    arr = np.frombuffer(pix, dtype="<u2").reshape((H0, w))
    return w, H0, arr

def rgb565_to_rgb888(arr565: np.ndarray) -> np.ndarray:
    a = arr565.astype(np.uint16)
    r = ((a >> 11) & 0x1F).astype(np.uint16)
    g = ((a >> 5)  & 0x3F).astype(np.uint16)
    b = (a & 0x1F).astype(np.uint16)
    r8 = ((r * 255 + 15) // 31).astype(np.uint8)
    g8 = ((g * 255 + 31) // 63).astype(np.uint8)
    b8 = ((b * 255 + 15) // 31).astype(np.uint8)
    return np.stack([r8, g8, b8], axis=2)

def rgb888_to_rgb565(rgb: np.ndarray) -> np.ndarray:
    r = (rgb[:,:,0].astype(np.uint16) >> 3) & 0x1F
    g = (rgb[:,:,1].astype(np.uint16) >> 2) & 0x3F
    b = (rgb[:,:,2].astype(np.uint16) >> 3) & 0x1F
    return (r << 11) | (g << 5) | b

def write_bmp_v4_rgb565_topdown(path: str, arr565: np.ndarray):
    H0, W0 = arr565.shape
    bfOffBits = 122
    pix = arr565.astype("<u2").tobytes()
    bfSize = bfOffBits + len(pix)
    filehdr = struct.pack("<2sIHHI", b"BM", bfSize, 0, 0, bfOffBits)

    biSize = 108
    biWidth = W0
    biHeight = -H0
    biPlanes = 1
    biBitCount = 16
    biCompression = 3
    biSizeImage = len(pix)

    rmask, gmask, bmask, amask = 0xF800, 0x07E0, 0x001F, 0x0000
    cstype = 0x73524742  # 'sRGB'
    endpoints = b"\x00"*36
    gamma0 = b"\x00"*12

    v4hdr = struct.pack(
        "<IiiHHIIIIII",
        biSize, biWidth, biHeight, biPlanes, biBitCount, biCompression,
        biSizeImage, 0, 0, 0, 0
    ) + struct.pack("<IIII", rmask, gmask, bmask, amask) + struct.pack("<I", cstype) + endpoints + gamma0

    with open(path, "wb") as f:
        f.write(filehdr); f.write(v4hdr); f.write(pix)

def zwrite(path: str, blob: bytes):
    with open(path, "wb") as f:
        f.write(zlib.compress(blob, 9))

def resize_nn(arr: np.ndarray, out_h: int, out_w: int) -> np.ndarray:
    in_h, in_w = arr.shape
    yi = (np.linspace(0, in_h-1, out_h)).astype(np.int32)
    xi = (np.linspace(0, in_w-1, out_w)).astype(np.int32)
    return arr[yi][:, xi]

# Load size-matched countries base (must already be WxH)
bw, bh, base565 = read_bmp_v4_rgb565_topdown(zread(base_path))
if (bw, bh) != (W, H):
    raise SystemExit(f"ERROR: base map is {bw}x{bh}, expected {W}x{H}: {base_path}")
base_rgb = rgb565_to_rgb888(base565)

# Read GFS fields
grbs = pygrib.open(grb_path)

# Pressure (Pa) -> mB/hPa
pr = grbs.select(shortName="prmsl")[0].values / 100.0

# Wind at 10m: some files use 10u/10v, others ugrd/vgrd at 10m.
u10 = v10 = None
try:
    u10 = grbs.select(shortName="10u")[0].values
    v10 = grbs.select(shortName="10v")[0].values
except Exception:
    pass

if u10 is None or v10 is None:
    # Prefer explicit level=10 (10 m above ground) if present
    try:
        u10 = grbs.select(shortName="ugrd", level=10)[0].values
        v10 = grbs.select(shortName="vgrd", level=10)[0].values
    except Exception:
        # Fallback: first ugrd/vgrd in the filtered file
        u10 = grbs.select(shortName="ugrd")[0].values
        v10 = grbs.select(shortName="vgrd")[0].values

grbs.close()

# Resample model grid to output size
pr_s = resize_nn(pr,  H, W)
u_s  = resize_nn(u10, H, W)
v_s  = resize_nn(v10, H, W)

# Scale annotation density with resolution (prevents huge maps from looking sparse)
scale = max(W / 660.0, 1.0)
lw = 0.6 * (scale ** 0.6)
fs = max(6.0 * (scale ** 0.6), 6.0)
step = int(max(22 * scale, 22))
qwidth = 0.0012 / scale
qscale = 55 * scale

fig = plt.figure(figsize=(W/100, H/100), dpi=100)
ax = plt.axes([0,0,1,1])
ax.set_axis_off()
ax.imshow(base_rgb, origin="upper")

levels = np.arange(960, 1045, 4)
cs = ax.contour(pr_s, levels=levels, colors="white", linewidths=lw, alpha=0.95)
ax.clabel(cs, inline=True, fmt="%d", fontsize=fs, colors="white")

yy, xx = np.mgrid[0:H:step, 0:W:step]
ax.quiver(xx, yy,
          u_s[0:H:step, 0:W:step], -v_s[0:H:step, 0:W:step],
          color="white", angles="xy", scale_units="xy", scale=qscale, width=qwidth, alpha=0.55)

fig.canvas.draw()
wpx, hpx = fig.canvas.get_width_height()
rgba = np.frombuffer(fig.canvas.buffer_rgba(), dtype=np.uint8).reshape(hpx, wpx, 4)
img = rgba[:, :, :3].copy()
plt.close(fig)

# Write HamClock BMPv4 RGB565 top-down + zlib .z
out_bmp = f"{outdir}/map-{tag}-{W}x{H}-Wx-mB.bmp"
out_z   = out_bmp + ".z"

arr565 = rgb888_to_rgb565(img)
write_bmp_v4_rgb565_topdown(out_bmp, arr565)
zwrite(out_z, open(out_bmp, "rb").read())

print("OK:", out_z)
PY
}

for wh in "${SIZES[@]}"; do
  W="${wh%x*}"
  H="${wh#*x}"

  DAY_BASE="$OUTDIR/map-D-${W}x${H}-Countries.bmp.z"
  [[ -f "$DAY_BASE" ]] || { echo "ERROR: missing $DAY_BASE" >&2; exit 1; }

  echo "Rendering Wx-mB Day ${W}x${H} (base: $(basename "$DAY_BASE"))"
  render_one "D" "$W" "$H" "$DAY_BASE"

  NIGHT_BASE="$OUTDIR/map-N-${W}x${H}-Countries.bmp.z"
  if [[ -f "$NIGHT_BASE" ]]; then
    echo "Rendering Wx-mB Night ${W}x${H} (base: $(basename "$NIGHT_BASE"))"
    render_one "N" "$W" "$H" "$NIGHT_BASE"
  else
    echo "Skipping Night ${W}x${H} (missing $(basename "$NIGHT_BASE"))"
  fi

  chmod 0644 \
    "$OUTDIR/map-D-${W}x${H}-Wx-mB.bmp" \
    "$OUTDIR/map-D-${W}x${H}-Wx-mB.bmp.z" \
    2>/dev/null || true

  if [[ -f "$OUTDIR/map-N-${W}x${H}-Wx-mB.bmp" ]]; then
    chmod 0644 \
      "$OUTDIR/map-N-${W}x${H}-Wx-mB.bmp" \
      "$OUTDIR/map-N-${W}x${H}-Wx-mB.bmp.z"
  fi
done

echo "OK: Wx-mB maps updated in $OUTDIR"

