#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/BrianWilkinsFL/open-hamclock-backend.git"
BASE="/opt/hamclock-backend"
VENV="$BASE/venv"

# ---------- colors ----------
RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[1;33m'
BLU='\033[0;34m'
NC='\033[0m'

# ---------- spinner ----------
spinner() {
  local pid=$1
  local spin='-\|/'
  local i=0
  while kill -0 $pid 2>/dev/null; do
    i=$(( (i+1) %4 ))
    printf "\r${YEL}[%c] Working...${NC}" "${spin:$i:1}"
    sleep .1
  done
  printf "\r${GRN}[✓] Done           ${NC}\n"
}

# ---------- progress ----------
progress() {
  local step=$1
  local total=$2
  local pct=$(( step * 100 / total ))
  printf "${BLU}[%-50s] %d%%${NC}\n" "$(printf '#%.0s' $(seq 1 $((pct/2))))" "$pct"
}

# ---- image sizes (maps) ----
DEFAULT_SIZES="660x330,1320x660,1980x990,2640x1320,3960x1980,5280x2640,5940x2970,7920x3960"
OHB_SIZES="${OHB_SIZES:-}"   # no default; must be supplied via flag or env

usage() {
  echo "Usage: $0 --size WxH [--size WxH ...] | --sizes WxH,WxH,..."
  echo "  --size   WxH       One size (repeatable)"
  echo "  --sizes  WxH,...   Comma-separated list of sizes"
  echo "  OHB_SIZES env var  Alternative to flags"
  echo ""
  echo "Example: $0 --size 660x330 --size 1320x660"
  echo "Example: $0 --sizes \"660x330,1320x660\""
}

is_size() { [[ "$1" =~ ^[0-9]+x[0-9]+$ ]]; }

# Require at least one --size/--sizes argument (unless OHB_SIZES env var set)
if [[ $# -eq 0 && -z "${OHB_SIZES:-}" ]]; then
  echo -e "${RED}ERROR: --size is required.${NC}"
  usage
  exit 1
fi

# First argument must be --size, --sizes, or --help
if [[ $# -gt 0 && "$1" != --size && "$1" != --sizes && "$1" != -h && "$1" != --help ]]; then
  echo -e "${RED}ERROR: first argument must be --size or --sizes (got: $1)${NC}"
  usage
  exit 1
fi

# accept flags (also allow OHB_SIZES env var)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sizes)
      shift; [[ $# -gt 0 ]] || { echo "ERROR: --sizes requires a value"; exit 1; }
      OHB_SIZES="$1"; shift;;
    --size)
      shift; [[ $# -gt 0 ]] || { echo "ERROR: --size requires a value"; exit 1; }
      if [[ -z "${_SIZES_SET:-}" ]]; then _SIZES_SET=1; OHB_SIZES=""; fi
      OHB_SIZES+="${OHB_SIZES:+,}$1"; shift;;
    -h|--help) usage; exit 0;;
    *) echo "ERROR: unknown arg: $1"; usage; exit 1;;
  esac
done

cat <<'EOF'

   ██████╗ ██╗  ██╗██████╗
  ██╔═══██╗██║  ██║██╔══██╗
  ██║   ██║███████║██████╔╝
  ██║   ██║██╔══██║██╔══██╗
  ╚██████╔╝██║  ██║██████╔╝
   ╚═════╝ ╚═╝  ╚═╝╚═════╝

   OPEN HAMCLOCK BACKEND
          (OHB)

EOF

echo -e "${GRN}RF • Space • Propagation • Maps${NC}"
echo

STEPS=12
STEP=0

# ---------- sanity ----------
if ! command -v systemctl >/dev/null; then
  echo -e "${RED}ERROR: systemd required (enable in WSL2)${NC}"
  exit 1
fi

# ---------- packages ----------
STEP=$((STEP+1)); progress $STEP $STEPS
echo -e "${BLU}==> Installing packages${NC}"

sudo apt-get update >/dev/null &
spinner $!

sudo apt-get install -y \
git jq curl perl lighttpd imagemagick \
libwww-perl libjson-perl libxml-rss-perl libxml-feed-perl libhtml-parser-perl \
libeccodes-dev libpng-dev libtext-csv-xs-perl librsvg2-bin ffmpeg ghostscript gmt gmt-gshhg gmt-dcw \
python3 python3-venv python3-dev python3-requests python3-matplotlib build-essential gfortran gcc make libc6-dev \
libx11-dev libxaw7-dev libxmu-dev libxt-dev libmotif-dev wget logrotate xmlstarlet >/dev/null &
spinner $!

STEP=$((STEP+1)); progress $STEP $STEPS
echo -e "${BLU}==> Configuring ImageMagick policy for large maps${NC}"

POLICY=$(find /etc/ImageMagick-* /usr/lib/ImageMagick-* -name policy.xml 2>/dev/null | head -1 || true)
POLICY="${POLICY:-}"

if [[ -z "$POLICY" ]]; then
  echo -e "${YEL}WARN: ImageMagick policy not found — skipping${NC}"
else
  echo -e "${BLU}    Using: $POLICY${NC}"

  # Backup original before any modifications
  POLICY_BAK="${POLICY}.ohb.bak"
  if [[ ! -f "$POLICY_BAK" ]]; then
    sudo cp "$POLICY" "$POLICY_BAK"
    echo -e "${BLU}    Backup: $POLICY_BAK${NC}"
  else
    echo -e "${BLU}    Backup already exists: $POLICY_BAK (skipping)${NC}"
  fi

  # Sanitize invalid double-hyphens inside XML comments before xmlstarlet runs.
  # Debian/Ubuntu ships policy.xml with <!-- ... -- ... --> which is illegal XML.
  # Strategy: replace any '--' that is NOT immediately followed by '>' with a single '-'.
  sudo perl -i -pe 's/<!--.*?-->/my $c=$&; $c=~s|(?<!-)--(?!>)|-|g; $c/gse' "$POLICY" 2>/dev/null || \
    sudo sed -i -E ':a;s/(<!--[^-]*)--([^>])/\1-\2/;ta' "$POLICY"

  # Validate before proceeding
  if ! xmlstarlet val "$POLICY" &>/dev/null; then
    echo -e "${YEL}WARN: $POLICY is not valid XML even after sanitization — skipping${NC}"
    echo -e "${YEL}      Original preserved at: $POLICY_BAK${NC}"
  else
    _im_ok=1
    sudo xmlstarlet ed -L \
      -u "//policy[@domain='resource'][@name='width']/@value"  -v "16KP" \
      -u "//policy[@domain='resource'][@name='height']/@value" -v "16KP" \
      -u "//policy[@domain='resource'][@name='area']/@value"   -v "128MP" \
      -u "//policy[@domain='resource'][@name='disk']/@value"   -v "8GiB" \
      -u "//policy[@domain='resource'][@name='memory']/@value" -v "2GiB" \
      "$POLICY" || _im_ok=0

    if [[ "$_im_ok" -eq 1 ]]; then
      echo -e "${GRN}[✓] ImageMagick policy updated ($POLICY)${NC}"
      echo -e "${GRN}    Original backed up at: $POLICY_BAK${NC}"
    else
      echo -e "${YEL}WARN: ImageMagick policy update failed — large maps may not render correctly${NC}"
      echo -e "${YEL}      Fix manually: sudo nano $POLICY${NC}"
      echo -e "${YEL}      Restore original: sudo cp $POLICY_BAK $POLICY${NC}"
    fi
  fi
fi

# ---------- forced redeploy ----------
STEP=$((STEP+1)); progress $STEP $STEPS
echo -e "${BLU}==> Fetching OHB (forced redeploy)${NC}"

sudo mkdir -p "$BASE"

if [ -d "$BASE/.git" ]; then
  sudo git -C "$BASE" reset --hard HEAD >/dev/null
  sudo git -C "$BASE" clean -fd >/dev/null
  sudo git -C "$BASE" pull >/dev/null &
  spinner $!
else
  sudo rm -rf "$BASE"/*
  sudo git clone "$REPO" "$BASE" >/dev/null &
  spinner $!
fi

# git housekeeping
echo -e "${YEL}===> Doing some git housekeeping${NC}"

sudo rm -f "$BASE/.git/gc.log" || true
sudo git -C "$BASE" prune >/dev/null || true
sudo git -C "$BASE" gc --prune=now >/dev/null || true

sudo chown -R www-data:www-data "$BASE"

# ---------- persist user image size selection ----------
echo -e "${BLU}==> Persisting image size selection${NC}"

sudo mkdir -p "$BASE/etc"
echo "OHB_SIZES=\"$OHB_SIZES\"" | sudo tee "$BASE/etc/ohb-sizes.conf" >/dev/null
sudo chown -R www-data:www-data "$BASE/etc"

# ---------- python venv ----------
STEP=$((STEP+1)); progress $STEP $STEPS
echo -e "${BLU}==> Creating Python virtualenv${NC}"

sudo -u www-data mkdir -p "$BASE/tmp/pip-cache"
sudo -u www-data mkdir -p "$BASE/tmp/worldwx"
sudo -u www-data mkdir -p "$BASE/tmp/mpl"

sudo -u www-data env HOME="$BASE/tmp" XDG_CACHE_HOME="$BASE/tmp" PIP_CACHE_DIR="$BASE/tmp/pip-cache" \
python3 -m venv "$VENV" & spinner $!

sudo -u www-data env HOME="$BASE/tmp" XDG_CACHE_HOME="$BASE/tmp" PIP_CACHE_DIR="$BASE/tmp/pip-cache" \
"$VENV/bin/pip" install --upgrade pip & spinner $!

sudo -u www-data env HOME="$BASE/tmp" XDG_CACHE_HOME="$BASE/tmp" PIP_CACHE_DIR="$BASE/tmp/pip-cache" \
"$VENV/bin/pip" install requests numpy pygrib matplotlib pandas scipy feedparser beautifulsoup4 lxml >/dev/null &
spinner $!

# ---------- relocate ham ----------
STEP=$((STEP+1)); progress $STEP $STEPS
echo -e "${BLU}==> Relocating ham content into htdocs${NC}"

sudo mkdir -p "$BASE/htdocs"

if [ -d "$BASE/ham" ]; then
  sudo rm -rf "$BASE/htdocs/ham"
  sudo mv "$BASE/ham" "$BASE/htdocs/"
fi

sudo chown -R www-data:www-data "$BASE"

# Make Perl CGI scripts executable for lighttpd/mod_cgi
sudo find "$BASE/htdocs/ham/HamClock" -maxdepth 1 -type f -name '*.pl' -exec chmod 755 {} \;

# ---------- dirs ----------
STEP=$((STEP+1)); progress $STEP $STEPS
echo -e "${BLU}==> Creating directories${NC}"

sudo mkdir -p \
 "$BASE/tmp" \
 "$BASE/logs" \
 "$BASE/cache" \
 "$BASE/data" \
 "$BASE/htdocs/ham/HamClock" \
 "$BASE/htdocs/ham/HamClock/Bz" \
 "$BASE/htdocs/ham/HamClock/geomag"

# Address log existing with correct perms and keep logrotate happy

sudo chown root:root /opt/hamclock-backend/logs
sudo chmod 0755 /opt/hamclock-backend/logs

LOGDIR=/opt/hamclock-backend/logs
sudo /bin/sh -c '
  umask 002
  for f in \
    bz_simple.log flux_simple.log gen_aurora.log gen_contest-calendar.log \
    gen_drap.log gen_dxnews.log gen_kindex.log gen_ng3k.log gen_noaswxx.log \
    gen_onta.log gen_solarflux-history.log gen_ssn_history.log gen_swind_24hr.log \
    get-missing-from-csi.log merge_dxpeditions.log ssn_simple.log swind_simple.log \
    update_all_sdo.log update_aurora_maps.logs update_cloud_maps.log update_drap_maps.log \
    update_muf_rt_maps.log update_pota_parks_cache.log update_wx_mb_maps.log worldwx.log \
    xray_simple.log fetch_tle.log gen_dst.log aurora_validate.log gen_noaaswx.log \
  ; do
    : >> "'"$LOGDIR"'/$f"
  done
'

sudo chown www-data:www-data /opt/hamclock-backend/logs/*.log
sudo chmod 0664 /opt/hamclock-backend/logs/*.log
sudo chown www-data:www-data /opt/hamclock-backend/htdocs/ham/HamClock/geomag
sudo chown www-data:www-data /opt/hamclock-backend/htdocs/ham/HamClock/Bz

#Fix www-data gmt execution error
sudo mkdir -p /var/www/.gmt
sudo chown www-data:www-data /var/www/.gmt
sudo chmod 755 /var/www/.gmt

# ---------- maps (from GitHub release) ----------
STEP=$((STEP+1)); progress $STEP $STEPS
echo -e "${BLU}==> Installing map assets${NC}"

MAP_TAG="maps-v1"
MAP_BASE="https://github.com/BrianWilkinsFL/open-hamclock-backend/releases/download/$MAP_TAG"
MAP_ARCHIVE="ohb-maps.tar.zst"
MAP_SHA="$MAP_ARCHIVE.sha256"

TMPMAP="$BASE/tmp/maps"
sudo mkdir -p "$TMPMAP"
sudo chown -R www-data:www-data "$TMPMAP"

cd "$TMPMAP"

# ensure zstd exists
if ! command -v zstd >/dev/null; then
  echo -e "${BLU}==>Installing zstd...${NC}"
  sudo apt-get install -y zstd >/dev/null
fi

echo -e "${BLU}==> Fetching maps from GitHub...${NC}"

sudo -u www-data curl -fsSLO "$MAP_BASE/$MAP_ARCHIVE"
sudo -u www-data curl -fsSLO "$MAP_BASE/$MAP_SHA"

# verify checksum
sudo -u www-data sha256sum -c "$MAP_SHA"

# extract directly into HamClock tree
sudo tar -I zstd -xf "$MAP_ARCHIVE" -C "$BASE/htdocs/ham/HamClock"

# ownership sanity
sudo chown -R www-data:www-data "$BASE/htdocs/ham/HamClock/maps"

echo -e "${GRN}Maps installed.${NC}"

sudo chown -R www-data:www-data "$BASE"

# ---------- lighttpd ----------
STEP=$((STEP+1)); progress $STEP $STEPS
echo -e "${BLU}==> Configuring lighttpd${NC}"

. /etc/os-release

if [[ -f /etc/rpi-issue ]]; then
  echo -e "${YEL}Pi OS detected (${VERSION_CODENAME:-unknown})...${NC}"
  sudo ln -sf "$BASE/lighttpd-conf/52-hamclock-pi.conf" /etc/lighttpd/conf-enabled/50-hamclock.conf
else
  echo -e "${YEL}Non-Pi OS detected (${ID:-?} ${VERSION_CODENAME:-unknown})...${NC}"
  sudo ln -sf "$BASE/lighttpd-conf/50-hamclock.conf" /etc/lighttpd/conf-enabled/50-hamclock.conf
fi

sudo lighttpd -t -f /etc/lighttpd/lighttpd.conf

# Disable conflicting javascript conf
sudo lighttpd-disable-mod javascript-alias || true
if ls /etc/lighttpd/conf-enabled | grep -q javascript; then
  echo "javascript conf still enabled"
else
  echo "javascript conf not present in conf-enabled (expected)"
fi

sudo lighttpd -tt -f /etc/lighttpd/lighttpd.conf
sudo systemctl reload lighttpd
sudo systemctl daemon-reload
sudo systemctl restart lighttpd

# Enable CGI module; some distros return non-zero when it's already enabled
out="$(sudo lighttpd-enable-mod cgi 2>&1)" || rc=$?
if [[ ${rc:-0} -ne 0 ]]; then
  if echo "$out" | grep -qi 'already enabled'; then
    echo "$out"
  else
    echo "$out" >&2
    exit "${rc:-1}"
  fi
else
  echo "$out"
fi

sudo lighttpd -t -f /etc/lighttpd/lighttpd.conf
sudo systemctl daemon-reload
sudo systemctl restart lighttpd

echo -e "${GRN}lighttpd configured${NC}"

# ---------- logrotate ----------
STEP=$((STEP+1)); progress $STEP $STEPS
echo -e "${BLU}==> Installing logrotate config${NC}"

sudo cp "$BASE/ohb.logrotate" /etc/logrotate.d/ohb
sudo logrotate -d /etc/logrotate.conf

# ---------- initial gen ----------
STEP=$((STEP+1)); progress $STEP $STEPS
echo -e "${BLU}==> Initial artifact generation${NC}"

sudo chmod +x "$BASE/scripts/"*

# ---------- initial pre-seed ----------
STEP=$((STEP+1)); progress $STEP $STEPS
echo -e "${BLU}==> Initial backend pre-seed${NC}"

sudo mkdir -p "$BASE/logs"
sudo chown -R www-data:www-data "$BASE/logs"

echo -e "${YEL}Pre-seed running as: ${NC}"
sudo -u www-data id

seed_spinner() {
  local pid=$1
  local spin='-\|/'
  local i=0
  while kill -0 $pid 2>/dev/null; do
    i=$(( (i+1) %4 ))
    printf "\r${YEL}[%c] Working...${NC}" "${spin:$i:1}"
    sleep .1
  done
  printf "\r${GRN}[✓] Done           ${NC}\n"
}

run_python_to_file() {
  local f=$1
  local out=$2
  local tmp="${out}.tmp"
  local log="$BASE/logs/${f%.py}.log"

  echo -e "${YEL}Running $VENV/bin/python $f > $out${NC}"

  # ensure parent dir exists and is writable by www-data
  install -d -o www-data -g www-data "$(dirname "$out")"

  # run in foreground so we can do atomic replace; capture stderr to log
  if ! sudo -u www-data env \
      HOME="$BASE/tmp" \
      XDG_CACHE_HOME="$BASE/tmp" \
      PIP_CACHE_DIR="$BASE/tmp/pip-cache" \
      OHB_SIZES="$OHB_SIZES" \
      PATH="$VENV/bin:$PATH" \
      VIRTUAL_ENV="$VENV" \
      "$VENV/bin/python" "$BASE/scripts/$f" >"$tmp" 2>>"$log"
  then
    echo "ERROR: $f failed; see $log" >&2
    rm -f "$tmp"
    return 1
  fi

  # atomic publish
  mv -f "$tmp" "$out"
}

run_python() {
  local f=$1
  local log="$BASE/logs/${f%.py}.log"
  echo -e "${YEL}Running $VENV/bin/python $f${NC}"

  sudo -u www-data env \
    HOME="$BASE/tmp" \
    XDG_CACHE_HOME="$BASE/tmp" \
    PIP_CACHE_DIR="$BASE/tmp/pip-cache" \
    OHB_SIZES="$OHB_SIZES" \
    PATH="$VENV/bin:$PATH" \
    VIRTUAL_ENV="$VENV" \
    "$VENV/bin/python" "$BASE/scripts/$f" >>"$log" 2>&1 &

  seed_spinner $!
}

run_perl() {
  local f=$1
  local log="$BASE/logs/${f%.pl}.log"
  echo -e "${YEL}Running perl $f${NC}"
  sudo -u www-data env OHB_SIZES="$OHB_SIZES" perl "$BASE/scripts/$f" >> "$log" 2>&1 &
  seed_spinner $!
}

run_sh() {
  local f=$1
  local log="$BASE/logs/${f%.sh}.log"
  echo -e "${YEL}Running bash $f${NC}"
  sudo -u www-data env OHB_SIZES="$OHB_SIZES" bash "$BASE/scripts/$f" >> "$log" 2>&1 &
  seed_spinner $!
}

run_flock_sh() {
  local f=$1
  local log="$BASE/logs/${f%.sh}.log"
  echo -e "${YEL}Running flocked $f${NC}"
  sudo -u www-data env OHB_SIZES="$OHB_SIZES" flock -n /tmp/update_sdo.lock bash "$BASE/scripts/$f" >> "$log" 2>&1 &
  seed_spinner $!
}

# ---- ordered execution ----

run_sh  gen_solarflux-history.sh
run_python swind_simple.py
run_python ssn_simple.py
run_perl gen_ssn_history.pl
run_sh  update_pota_parks_cache.sh
run_python flux_simple.py
run_sh  update_wx_mb_maps.sh
run_perl gen_dxnews.pl
run_perl gen_ng3k.pl
run_perl merge_dxpeditions.pl
run_sh  gen_contest-calendar.sh
run_python_to_file kindex_simple.py "$BASE/htdocs/ham/HamClock/geomag/kindex.txt"
run_sh  update_cloud_maps.sh
run_sh  update_drap_maps.sh
run_sh  gen_dst.sh
run_sh  fetch_tle.sh
run_sh  gen_aurora.sh
run_sh  gen_noaaswx.sh
run_sh  update_all_sdo.sh
run_sh  update_aurora_maps.sh
run_sh  gen_cty_wt_mod.sh
run_perl update_sota_cache.pl
run_perl update_wwff_cache.pl
run_perl gen_onta.pl
run_python  bz_simple.py
run_sh  gen_drap.sh
run_python xray_simple.py
run_sh  kc2g_muf_heatmap.sh

sudo chown -R www-data:www-data "$BASE"
# ---------- footer ----------
VERSION=$(git -C "$BASE" describe --tags --dirty --always 2>/dev/null)
VERSION=${VERSION:-$(git -C "$BASE" rev-parse --short HEAD 2>/dev/null)}
VERSION=${VERSION:-"unknown"}

HOST=$(hostname)
IP=$(hostname -I | awk '{print $1}')

echo -e "${BLU}==> Integration test...${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ham/HamClock/version.pl)
if [[ "$HTTP_CODE" == "200" ]]; then
  echo -e "${GRN}[✓] HTTP $HTTP_CODE - OK${NC}"
else
  echo -e "${RED}[✗] HTTP $HTTP_CODE - Check lighttpd logs: sudo journalctl -u lighttpd -n 50${NC}"
fi

# ---------- cron ----------
STEP=$((STEP+1)); progress $STEP $STEPS
echo -e "${BLU}==> Installing www-data crontab${NC}"

sudo chmod 644 "$BASE/scripts/crontab"
sudo -u www-data crontab "$BASE/scripts/crontab"
sudo systemctl restart cron

IP=$(hostname -I 2>/dev/null | awk '{print $1}')
IP="${IP:-<unknown>}"

echo
echo -e "${GRN}===========================================${NC}"
echo -e "${GRN} OHB Version : ${VERSION}${NC}"
echo -e "${GRN} Hostname    : ${HOST}${NC}"
echo -e "${GRN} IP Address  : ${IP}${NC}"
echo -e "${GRN} Map Sizes   : ${OHB_SIZES}${NC}"
echo -e "${GRN}===========================================${NC}"
echo
echo

if grep -qi microsoft /proc/version 2>/dev/null; then
  echo -e "${YEL}WSL2 detected: ensure systemd=true in /etc/wsl.conf${NC}"
fi

echo -e "${YEL}Next steps:${NC}"
echo -e "  • Check logs for any errors or exceptions: sudo tail -f $BASE/logs/*.log"
echo -e "  • Connect your HamClock by running the command: hamclock -b ${IP}:80"
echo -e "${YEL}To change map sizes later, run: sudo bash $BASE/scripts/ohb-image-size.sh --size WxH${NC}"

