# OHB - Open HamClock Backend
Open Source and Faithful HamClock Backend Replacement. This is a community project and no relation to the creator of HamClock Elwood Downey, WB0OEW, ecdowney@clearskyinstitute.com SK

I wish the Downey family my deepest condolences

This is a WIP.

## License
MIT

## Join us on Discord 💬
We are building a community-powered backend to keep Ham Clock running. \
Discord is where we can collaborate, troubleshoot, and exchange ideas — no RF license required 😎 \
https://discord.gg/wb8ATjVn6M

## Attribution
- [MUF-RT](https://prop.kc2g.com/) Note: MUF-RT data for this map are from GIRO collected and used by permission from KC2G.
- [Space Weather Prediction Center](https://www.swpc.noaa.gov/)
- NASA for [SDO](https://sdo.gsfc.nasa.gov/) and [STEREO](https://stereo.gsfc.nasa.gov/) images
- National Research Council Canada [10.7 cm solar flux](https://www.spaceweather.gc.ca/forecast-prevision/solar-solaire/solarflux/sx-en.php) data
- [HamWeekly.com](https://hamweekly.com/)
- [NG3K.com](https://www.ng3k.com/)
- [ARNewsline.com](https://www.arnewsline.org/)
- [PSKReporter](https://pskreporter.info/) by Phillip Gladstone
- [WSPR Live](https://wspr.live/)
- [WA7BNM Weekend Contests Calendar](https://www.contestcalendar.com/)
- [Amateur Radio Country Files](https://www.country-files.com/big-cty/)

## Data sources and attribution

Sunspot numbers published in `ssn-31.txt` are derived from the following public datasets:

1. **NOAA / NWS Space Weather Prediction Center (SWPC) — Daily Solar Data (DSD.txt)**
   - Source: SWPC Data Service text product **`daily-solar-indices.txt`** (“Last 30 Days Daily Solar Data”).
   - Use in this project: parses the daily **SESC Sunspot Number** column for historical days.
   - URL: https://services.swpc.noaa.gov/text/daily-solar-indices.txt

2. **NOAA / NWS Space Weather Prediction Center (SWPC) — Solar-cycle JSON**
   - Source: SWPC Data Service JSON **`swpc_observed_ssn.json`**.
   - Use in this project: uses **`swpc_ssn`** for the **current UTC day** (when present), to avoid the common 1-day lag in the “Last 30 Days” text product.
   - URL: https://services.swpc.noaa.gov/json/solar-cycle/swpc_observed_ssn.json

3. **SILSO (Royal Observatory of Belgium / SIDC) — Estimated International Sunspot Number (EISN)**
   - Source: **`EISN_current.txt`** (plain ASCII fixed-width format).
   - Use in this project: **fallback only** for the **current UTC day** if SWPC solar-cycle JSON does not yet include today’s value.
   - URL: https://sidc.be/SILSO/DATA/EISN/EISN_current.txt

### Notes
- “Today” is determined using **UTC**.
- All data remain the property of their respective providers; this project redistributes derived values and does not claim ownership of the underlying observations or indices.

## Vision
The goal is to make this as a drop-in replacement for the HamClock backend by replicating the same client/server responses with Perl CGI scripting and static files. We don't have access to the backend server source code so this is completely created by looking at the interfaces. The goal is to allow for local or central install of OHB to keep all existing HamClock's from working beyond June 2026

## Interoperability
This project generates map and data artifacts in the same formats expected by the HamClock client (e.g. zlib compressed BMP RGB565 map tiles) to support interoperability. This project is not affiliated with or endorsed by the original HamClock project or any third party. Data products are derived from public upstream sources such as NOAA SWPC and NASA

## In Work
- maps/Aurora
Status: In Progress. We made progress by developing a script to create the base layer and have an Aurora producing script. However, we have not produced all the base layer maps to be able to support all Aurora map sizes. Only Night has been proven to be working so far at 660x330

## Known Issues
[Active Issues](https://github.com/BrianWilkinsFL/open-hamclock-backend/issues)

- Satellite planning page will cause HamClock to fail. Error message refers to a SatTool name lookup issue. This seems to only happen if two satellites are not selected by the user. To the best of our knowledge, this is a HamClock bug
- IP Geolocation will not work if API key not set. To fix, set API key in fetchIPGeoloc.pl
- Root directories missing on install. Manually create cache, tmp, tmp/psk-cache, and logs if missing
- One or more SDO images may report 'File is not BMP'. If this is the case, try switching to a different image temporarily
- Invalid data may display and it can take time for the backend to build up a suitable cache
  - Running the server data sync script will pull down the latest aurora and DRAP stats.txt file from an active HamClock server (Currently ClearSkyInstitute):
    - /opt/hamclock-backend/scripts/sync_server_data_files.sh
  
# Importance of Accurate and Consistent Time
This is worth documenting explicitly. Your backend now depends on monotonic, synchronized time. Without it, feeds appear “broken” even when structurally correct.

## Time Synchronization Requirements

Open HamClock Backend (OHB) and all HamClock clients must maintain accurate and synchronized system time.

OHB generates time-series data (aurora, solar wind, DRAP, SSN, etc.) using Unix epoch timestamps. HamClock clients compute data age using:

```age = now_client - epoch_from_backend```

If the client clock is incorrect or significantly out of sync with the backend, HamClock will discard valid data and log errors such as:

AURORA: skipping age -491926 hrs
AURORA: only 0 points

Negative ages indicate the client believes the data is from the future.

## Required Conditions

* Backend system clock must be accurate (UTC)
* HamClock client clock must be accurate (UTC)
* Clock skew between backend and clients should be less than a few seconds

Even multi-minute skew can distort plotted slopes
Large skew (hours/days/years) will cause complete data rejection

## Enabling Time Sync (Linux / Raspberry Pi)

Verify status:

```timedatectl```

Enable NTP synchronization:

```sudo timedatectl set-ntp true```
```sudo systemctl restart systemd-timesyncd```

If systemd-timesyncd is not available:

```sudo apt install ntp```
```sudo systemctl enable ntp```
```sudo systemctl start ntp```

Confirm synchronization:

```timedatectl```

You should see:

```System clock synchronized: yes```

## Why This Matters

* OHB uses deterministic epoch flooring (30-minute cadence)
* HamClock assumes evenly spaced historical bins

Time drift breaks these assumptions.

Symptoms of clock problems include:

* Aurora graph shows no data
* “skipping age” messagesFlatlined plots
* Sudden apparent time gaps

These are almost always clock skew issues — not backend failures

OHB does not compensate for client clock drift by design

## Compatibility
- [x] Ubuntu 22.x LTS (Baremetal, VM, or WSL)
- [x] Ubuntu 24 AWS AMI (Baremetal, VM, or WSL)
- [x] Debian 13.3 
- [x] Raspberry Pi 3b+, 4, and 5
     - [x] Tested Trixie 64 bit OS on Pi 3b+ with image sizes 660x330, 1320x660
           - 2640x1320 for MUF-RT does not currently work
- [x] Inovato Quadra
- [ ] Mac 

## Install:
(NOTE: to run OHB in docker, visit https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/docker/README.md)

```bash
   # Confirmed working in aws t3-micro Ubuntu 24.x LTS instance
   wget -O install_ohb.sh https://raw.githubusercontent.com/BrianWilkinsFL/open-hamclock-backend/refs/heads/main/aws/install_ohb.sh
   chmod +x install_ohb.sh
   sudo ./install_ohb.sh
```
## Selecting map image sizes during install

By default, OHB generates the full HamClock size set. This is only recommend on a high end PC or VM:

`660x330,1320x660,1980x990,2640x1320,3960x1980,5280x2640,5940x2970,7920x3960`

To install with a custom size set, pass one of the options below:

### Option A: Comma-separated list
> [!WARNING]
> Attempting to image generate multiple sizes or 4K UHD sizes on Pi3B can cause it to overheat!

```bash
chmod +x ./install_ohb.sh
sudo ./install_ohb.sh --sizes "660x330,1320x660,1980x990"
```
### Option B: Repeat --size
> [!WARNING]
> Attempting to image generate multiple sizes or 4K UHD sizes on Pi3B can cause it to overheat!

```bash
chmod +x ./install_ohb.sh
sudo ./install_ohb.sh --size 660x330 --size 1320x660 --size 1980x990
```

Install script will store configuration under /opt/hamclock-backend/etc/ohb-sizes.conf

```bash
# Canonical default list (keep in sync with HamClock)
DEFAULT_SIZES=( \
  "660x330" \
  "1320x660" \
  "1980x990" \
  "2640x1320" \
  "3960x1980" \
  "5280x2640" \
  "5940x2970" \
  "7920x3960" \
)
```

Note: OHB will install default maps (Countries and Terrain) for all possible sizes. This does not incur any major CPU or RAM hit on small form factor PCs as it is just a download, extract and install

After install, update your HamClock startup script to point to OHB. Then, reboot your HamClock.

## Starting HamClock with OHB Local Install
HamClock is hard-coded to use the clearskyinstitute.com URL. You can override to use a new backend by starting HamClock with the -b option

### Localhost (if running OHB adjacent to your existing HamClock client such as Raspberry Pi)
```bash
hamclock -b localhost:80
```
Note: Depending on where you installed HamClock application, the path may be different. If you followed the instructions [here](https://qso365.co.uk/2024/05/how-to-set-up-a-hamclock-for-your-shack/), then it will be installed in /usr/local/bin.

### Starting HamClock with OHB Central Install
```bash
hamclock -b \<central-server-ip-or-host\>:80
```
## Stopping OHB
### Web Server
```bash
sudo systemctl stop lighttpd
```
### Cron Jobs
#### Remove all jobs
```bash
sudo crontab -u www-data -l > ~/www-data.cron.backup
sudo crontab -u www-data -r
```
Note: Removing the cron jobs will stop all future background processes, not currently running. Ensure that the www-data.cron.backup actually was created before you remove all of www-data user's cronjobs

#### Restore all jobs
```bash
sudo crontab -u www-data /path/to/www-data.cron.backup
sudo crontab -u www-data -l | head
```

## Enabling OHB Dashboard
To enable OHB dashboard, it is a manual install while it is being developed. 

```bash
 sudo cp /opt/hamclock-backend/lighttpd-conf/51-ohb-dashboard.conf /etc/lighttpd/conf-enabled/
 sudo lighttpd -t -f /etc/lighttpd/lighttpd.conf
 sudo service lighttpd force-reload
 sudo -u www-data cp /opt/hamclock-backend/ham/dashboard/* /opt/hamclock-backend/htdocs
```
Ensure all scripts are owned by www-data under /opt/hamclock-backend/htdocs

## Project Completion Status

HamClock requests about 40+ artifacts. I have locally replicated all of them that I could find.

### Dynamic Text Files
- [x] Bz/Bz.txt
- [x] aurora/aurora.txt
- [x] xray/xray.txt
- [x] worldwx/wx.txt
- [x] esats/esats.txt
- [x] solarflux/solarflux-history.txt
- [x] ssn/ssn-history.txt
- [x] solar-flux/solarflux-99.txt
- [x] geomag/kindex.txt
- [x] dst/dst.txt
- [x] drap/stats.txt
- [x] solar-wind/swind-24hr.txt
- [x] ssn/ssn-31.txt
- [x] ONTA/onta.txt
- [x] contests/contests311.txt
- [x] dxpeds/dxpeditions.txt
- [x] NOAASpaceWX/noaaswx.txt
- [x] ham/HamClock/cty/cty_wt_mod-ll-dxcc.txt - Country/prefix database with lat/lon
      
### Dynamic Map Files
Note: Anything under maps/ is considered a "Core Map" in HamClock

- [x] maps/Clouds*
- [x] maps/Countries*
- [x] maps/Wx-mB*
- [x] maps/Aurora
- [x] maps/DRAP
- [x] maps/MUF-RT
- [x] maps/Terrain
- [x] SDO/*

### Dynamic Web Endpoints
- [x] ham/HamClock/RSS/web15rss.pl
- [x] ham/HamClock/version.pl
- [x] ham/HamClock/wx.pl
- [x] ham/HamClock/fetchIPGeoloc.pl - requires free tier 1000 req per day account and API key
- [x] ham/HamClock/fetchBandConditions.pl
- [ ] ham/HamClock/fetchVOACAPArea.pl
- [ ] ham/HamClock/fetchVOACAP-MUF.pl?YEAR=2026&MONTH=1&UTC=17&TXLAT=&TXLNG=&PATH=0&WATTS=100&WIDTH=660&HEIGHT=330&MHZ=0.00&TOA=3.0&MODE=19&TOA=3.0
- [ ] ham/HamClock/fetchVOACAP-TOA.pl?YEAR=2026&MONTH=1&UTC=17&TXLAT=&TXLNG=&PATH=0&WATTS=100&WIDTH=660&HEIGHT=330&MHZ=14.10&TOA=3.0&MODE=19&TOA=3.0
- [x] ham/HamClock/fetchPSKReporter.pl?ofgrid=XXYY&maxage=1800
- [x] ham/HamClock/fetchWSPR.pl
- [ ] ham/HamClock/fetchRBN.pl

### Static Files
- [x] ham/HamClock/cities2.txt - static city file - no urgency to update this for maybe 5 years or more
- [x] ham/HamClock/NOAASpaceWx/rank2_coeffs.txt

## Integration Testing Status
- [x] GOES-16 X-Ray
- [x] Countries map download
- [x] Terrain map download
- [x] DRAP map generation, download, and display
- [x] SDO generation, download, and display
- [x] MUF-RT map generation, download, and display
- [x] Weather map generation, download, and display
- [x] Clouds map generation, download, and display
- [x] Aurora map generation, download, and display
- [x] Aurora map generation, download, and display
- [x] Parks on the Air generation, pull and display
- [x] SSN generation, pull, and display
- [x] Solar wind generation, pull and display
- [x] DRAP data generation, pull and display
- [x] Planetary Kp data generation, pull and display
- [x] Solar flux data generation, pull and display
- [x] Amateur Satellites data generation, pull and display
- [ ] PSK Reporter WSPR
- [X] VOACAP DE DX
- [ ] VOACAP MUF MAP
- [ ] RBN

## Requirements and Install

### Dependency Install
Note: Installer script should take care of these dependencies. If not, you can manually install them

- sudo apt install -y jq
- sudo apt install -y perl
- sudo apt install -y lighttpd
- sudo apt install -y imagemagick
- sudo apt install -y libwww-perl
- sudo apt install -y libjson-perl
- sudo apt install -y libxml-rss-perl
- sudo apt install -y libxml-feed-perl
- sudo apt install -y libhtml-parser-perl
- sudo apt install -y libeccodes-dev
- sudo apt install -y libg2c-dev
- sudo apt install -y libpng-dev
- sudo apt install -y libg2c-dev
- sudo apt install -y libeccodes-dev
- sudo apt install -y libtext-csv-xs-perl
- sudo apt install -y librsvg2-bin
- sudo apt install -y ffmpeg
- sudo apt install -y python3
- sudo apt install -y python3-pip
- sudo apt install -y python3-pyproj
- sudo apt install -y python3-dev
\# Canonical Ubuntu Way
- sudo apt install -y python3-matplotlib
- sudo apt install -y python3-pygrib
- sudo apt install -y python3-grib
\# Canonical Ubuntu Way
- sudo apt install -y build-essential gfortran gcc make libc6-dev \\\
libx11-dev libxaw7-dev libxmu-dev libxt-dev libmotif-dev wget (needed for VOACAPL)
- pip install numpy
- pip install pygrib
- pip install matplotlib

  
## Testing

After install, you can verify any script is working by using sudo -u www-data /opt/hamclock/scripts/<scriptname> <optional-param>

Most cron-jobs will log to /opt/hamclock-backend/logs

## Automated Pulls
- Once per month: /opt/hamclock-backend/scripts/gen_solarflux-history.sh
- Once per day at 12:10am: /opt/hamclock-backend/scripts/gen_swind_24hr.pl
- Once per day at 12:15am: /opt/hamclock-backend/scripts/update_solarflux_cache.pl
- Once per day at 12:20am: /opt/hamclock-backend/scripts/publish_solarflux_99.pl
- Once per dat at 12:25am: /opt/hamclock-backend/scripts/gen_dxnews.pl
- Once per day at 12:30am: /opt/hamclock-backend/scripts/gen_ng3k.pl
- Once per day at 12:35am: /opt/hamclock-backend/scripts/merge_dxpeditions.pl
- Every 12 hours: /opt/hamclock-backend/scripts/gen_kindex.pl
- Every 8 hours: /opt/hamclock-backend/scripts/gen_contest-calendar.pl
- Every 3 hours: /opt/hamclock-backend/scripts/build_esats.pl
- Every hour: /opt/hamclock-backend/scripts/update_clouds_maps.sh
- Every hour: /opt/hamclock-backend/scripts/update_drap_maps.sh
- Every hour: /opt/hamclock-backend/scripts/gen_dst.sh
- Every 30 minutes: /opt/hamclock-backend/scripts/gen_aurora.sh
- Every 30 minutes: /opt/hamclock-backend/scripts/gen_noaaswx.sh
- Every 5 minutes: /opt/hamclock-backend/scripts/gen_onta.pl
- Every 5 minutes: /opt/hamclock-backend/scripts/bzgen.sh
- Every 3 minutes: /opt/hamclock-backend/scripts/gen_drap.sh
- Once per minute: /opt/hamclock-backend/scripts/genxray.pl
