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

# NOTE: you have 9 progress steps below
STEPS=9
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
libx11-dev libxaw7-dev libxmu-dev libxt-dev libmotif-dev wget logrotate >/dev/null &
spinner $!

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
sudo rm -f "$BASE/.git/gc.log" || true
sudo git -C "$BASE" prune >/dev/null || true
sudo git -C "$BASE" gc --prune=now >/dev/null || true

sudo chown -R www-data:www-data "$BASE"

# ---- image sizes (maps) ----
DEFAULT_SIZES="660x330,1320x660,1980x990,2640x1320,3960x1980,5280x2640,5940x2970,7920x3960"
OHB_SIZES="${OHB_SIZES:-$DEFAULT_SIZES}"

usage() {
  echo "Usage: $0 [--sizes WxH,WxH,...] [--size WxH ...]"
  echo "Example: $0 --sizes \"660x330,1320x660\""
}

is_size() { [[ "$1" =~ ^[0-9]+x[0-9]+$ ]]; }

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

# normalize + validate + dedupe
OHB_SIZES="${OHB_SIZES//[[:space:]]/}"
IFS=',' read -r -a _tmp_sizes <<< "$OHB_SIZES"
declare -A _seen=()
_norm_sizes=()
for s in "${_tmp_sizes[@]}"; do
  [[ -n "$s" ]] || continue
  is_size "$s" || { echo "ERROR: invalid size '$s' (expected WxH)"; exit 1; }
  if [[ -z "${_seen[$s]:-}" ]]; then _seen[$s]=1; _norm_sizes+=("$s"); fi
done
[[ ${#_norm_sizes[@]} -gt 0 ]] || { echo "ERROR: empty size list"; exit 1; }
OHB_SIZES="$(IFS=','; echo "${_norm_sizes[*]}")"

if [[ "$OHB_SIZES" != *"660x330"* ]]; then
  echo "WARN: size list does not include 660x330; some maps are tuned around that baseline." >&2
fi

# ---------- persist user image size selection ----------
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
python3 -m venv "$VENV"

sudo -u www-data env HOME="$BASE/tmp" XDG_CACHE_HOME="$BASE/tmp" PIP_CACHE_DIR="$BASE/tmp/pip-cache" \
"$VENV/bin/pip" install --upgrade pip

sudo -u www-data env HOME="$BASE/tmp" XDG_CACHE_HOME="$BASE/tmp" PIP_CACHE_DIR="$BASE/tmp/pip-cache" \
"$VENV/bin/pip" install numpy pygrib matplotlib >/dev/null &
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
 "$BASE/htdocs/ham/HamClock"

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

echo -e "${BLU}==>Fetching maps from GitHub...${NC}"

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

# ---------- cron ----------
STEP=$((STEP+1)); progress $STEP $STEPS
echo -e "${BLU}==> Installing www-data crontab${NC}"

sudo chmod 644 "$BASE/scripts/crontab"
sudo -u www-data crontab "$BASE/scripts/crontab"
sudo systemctl restart cron

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
run_perl gen_swind_24hr.pl
run_perl gen_ssn.pl
run_perl gen_ssn_history.pl
run_sh  update_pota_parks_cache.sh
run_perl update_solarflux_cache.pl
run_sh  update_wx_mb_maps.sh
run_perl publish_solarflux_99.pl
run_perl gen_dxnews.pl
run_perl gen_ng3k.pl
run_perl merge_dxpeditions.pl
run_sh  gen_contest-calendar.sh
run_perl gen_kindex.pl
run_sh  update_cloud_maps.sh
run_sh  update_drap_maps.sh
run_sh  gen_dst.sh
run_sh  fetch_tle.sh
run_sh  gen_aurora.sh
run_sh  gen_noaaswx.sh
run_sh  update_all_sdo.sh
run_sh  update_aurora_maps.sh
run_perl gen_onta.pl
run_sh  bzgen.sh
run_sh  gen_drap.sh
run_perl genxray.pl
run_sh  update_muf_rt_maps.sh

sudo chown -R www-data:www-data "$BASE"
# ---------- footer ----------
VERSION=$(git -C "$BASE" describe --tags --dirty --always 2>/dev/null || echo "unknown")
HOST=$(hostname)
IP=$(hostname -I | awk '{print $1}')

echo -e "${BLU}==>Integration test. You should see HTTP 200 and version 4.22${NC}"
curl -i http://localhost/ham/HamClock/version.pl

echo
echo -e "${GRN}===========================================${NC}"
echo -e "${GRN} OHB Version : ${VERSION}${NC}"
echo -e "${GRN} Hostname    : ${HOST}${NC}"
echo -e "${GRN} IP Address : ${IP}${NC}"
echo -e "${GRN} URL        : http://${IP}/ham/HamClock/${NC}"
echo -e "${GRN}===========================================${NC}"
echo
echo -e "${YEL}If using WSL2 ensure systemd=true in /etc/wsl.conf${NC}"
echo

