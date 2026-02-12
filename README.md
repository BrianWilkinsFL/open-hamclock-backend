# OHB - Open HamClock Backend
Open Source and Faithful HamClock Backend Replacement. This is a community project and no relation to the creator of HamClock Elwood Downey, WB0OEW, ecdowney@clearskyinstitute.com SK

I wish the Downey family my deepest condolences

This is a WIP.

## License
MIT

## Join us on Discord 💬
We are building a community-powered backend to keep Ham Clock running. \
Discord is where we can collaborate, troubleshoot, and exchange ideas — no RF license required 😎 \
https://discord.gg/k2Nmdjup

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
- Raspberry Pi CPU Spikes due to image generation - on install specify the single image size you want - do not use the full image size bank!
- Raspberry Pi needs to use 50-Hamclock-pi.conf in the repository instead of 50-Hamclock.conf for the lighttpd conf. Replace the configuration file at /etc/lighttpd/etc/conf.enabled with 50-Hamclock-pi.conf
- Raspberry Pi may need permissions set on all scripts with chmod +x at /opt/hamclock-backend/htdocs/ham/HamClock. Execute chmod -R +x /opt/hamclock-backend/htdocs/ham/HamClock at the command line on the Raspberry Pi
- DRAP data will show as invalid on fresh OHB installs because it takes approximately 36 hours to build up a suitable cache. The reason for this is because NOAA does not publish historical, current day data so if the application wants to show a time series graph including the current day then it needs to be pulling from NOAA SWX every five minutes. The fix for this when using OHB is to allow OHB to cache for 36 hours after a fresh install
  - Running the server data sync script will pull down the latest aurora and DRAP stats.txt file from an active HamClock server (Currently ClearSkyInstitute):
    - /opt/hamclock-backend/scripts/sync_server_data_files.sh
  

## Compatibility
- [x] Ubuntu 22.x LTS
- [x] Ubuntu 24 AWS AMI
- [x] Debian 13.3 
- [x] Raspberry Pi
- [x] Windows Subsystem for Linux
- [x] Inovato Quadra
- [ ] Mac 

## Install:
(NOTE: to run OHB in docker, visit https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/docker/README.md)

```bash
   # Confirmed working in aws t3-micro Ubuntu 24.x LTS instance
   wget https://raw.githubusercontent.com/BrianWilkinsFL/open-hamclock-backend/refs/heads/main/aws/install_ohb.sh
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
 sudo cp /opt/hamclock-backend/50-ohb-dashboard.conf /etc/lighttpd/conf-enabled/
 sudo lighttpd -t -f /etc/lighttpd/lighttpd.conf
 sudo service lighttpd force-reload
 sudo -u www-data cp /opt/hamclock-backend/*.pl /opt/hamclock-backend/htdocs
 sudo -u www-data cp /opt/hamclock-backend/ascii.txt /opt/hamclock-backend/htdocs
 sudo -u www-data cp /opt/hamclock-backend/index.html /opt/hamclock-backend/htdocs
 sudo -u www-data cp /opt/hamclock-backend/traces.svg /opt/hamclock-backend/htdocs
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

### Dynamic Map Files
Note: Anything under maps/ is considered a "Core Map" in HamClock

- [x] maps/Clouds*
- [x] maps/Countries*
- [x] maps/Wx-mB*
- [ ] maps/Aurora
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
- [x] ham/HamClock/cty/cty_wt_mod-ll-dxcc.txt - Country/prefix database with lat/lon
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
- [ ] Aurora map generation, download, and display
- [ ] Aurora map generation, download, and display
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
