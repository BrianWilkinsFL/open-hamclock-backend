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
- MUF-RT: MUF-RT data for this map are from GIRO collected and used by permission from KC2G.
- NOAA
- NASA
- HamWeekly.com
- NG3K.com
- ARNewsline.com
- PSKReporter by Phillip Gladstone

## Vision
The goal is to make this as a drop-in replacement for the HamClock backend by replicating the same client/server responses with Perl CGI scripting and static files. We don't have access to the backend server source code so this is completely created by looking at the interfaces. To allow existing HamClock's running on Arduino to continue to work, we will setup a local DNS sinkhole to redirect to your local backend running at your home or office. Or, the HamClock client may be modified to point to a new central server permanently or use the built-in -b option

## Interoperability
This project generates map and data artifacts in the same formats expected by the HamClock client (e.g. zlib compressed BMP RGB565 map tiles) to support interoperability. This project is not affiliated with or endorsed by the original HamClock project or any third party. Data products are derived from public upstream sources such as NOAA SWPC and NASA

## Known Issues
- Satellite planning page will cause HamClock to fail. Error message refers to a SatTool name lookup issue
- IP Geolocation will not work if API key not set. To fix, set API key in fetchIPGeoloc.pl
- Root directories missing on install. Manually create cache, tmp, and logs if missing
- One or more SDO images may report 'File is not BMP'. If this is the case, try switching to a different image temporarily.

## Compatibility
- [x] Ubuntu 22.x LTS
- [x] Ubuntu 24 AWS AMI
- [ ] Debian 13.3 
- [ ] Raspberry Pi
- [x] Windows Subsystem for Linux
- [ ] Inovato Quadra
- [ ] Mac 

## Install:
```bash
   # Confirmed working in aws t3-micro Ubuntu 24.x LTS instance
   wget https://raw.githubusercontent.com/BrianWilkinsFL/open-hamclock-backend/refs/heads/main/aws/install_ohb.sh
   sudo bash install_ohb.sh
```

## Starting HamClock
HamClock is hard-coded to use the clearskyinstitute.com URL. You can override to use a new backend by starting HamClock with the -b option

### Localhost (if running OHB adjacent to your existing HamClock client such as Raspberry Pi)

./hamclock -b localhost:80

### Different Central Server

./hamclock -b \<central-server-ip-or-host\>:80

## Project Completion Status

HamClock requests about 40+ artifacts. I have locally replicated all of them that I could find.

### Dynamic Text Files
- [x] Bz/Bz.txt
- [x] aurora/aurora.txt
- [x] xray/xray.txt
- [ ] worldwx/wx.txt
- [x] esats/esats.txt
- [x] solarflux/solarflux-history.txt
- [x] ssn/ssn-history.txt
- [x] solar-flux/solarflux-99.txt (this requires a local cache to be built up - I made a bootstrap script)
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
- [ ] maps/Aurora (Partial Sizes)
- [x] maps/DRAP
- [ ] maps/MUF-RT (Partial Sizes)
- [ ] maps/Terrain (Partial Sizes)
- [x] SDO/*

### Dynamic Web Endpoints
- [x] ham/HamClock/RSS/web15rss.pl
- [x] ham/HamClock/version.pl
- [x] ham/HamClock/wx.pl
- [x] ham/HamClock/fetchIPGeoloc.pl - requires free tier 1000 req per day account and API key
- [ ] ham/HamClock/fetchBandConditions.pl
- [ ] ham/HamClock/fetchVOACAPArea.pl
- [ ] ham/HamClock/fetchVOACAP-MUF.pl?YEAR=2026&MONTH=1&UTC=17&TXLAT=&TXLNG=&PATH=0&WATTS=100&WIDTH=660&HEIGHT=330&MHZ=0.00&TOA=3.0&MODE=19&TOA=3.0
- [ ] ham/HamClock/fetchVOACAP-TOA.pl?YEAR=2026&MONTH=1&UTC=17&TXLAT=&TXLNG=&PATH=0&WATTS=100&WIDTH=660&HEIGHT=330&MHZ=14.10&TOA=3.0&MODE=19&TOA=3.0
- [x] ham/HamClock/fetchPSKReporter.pl?ofgrid=XXYY&maxage=1800
- [ ] ham/HamClock/fetchWSPR.pl
- [ ] ham/HamClock/fetchRBN.pl

### Static Files
- [x] ham/HamClock/cities2.txt - static city file - no urgency to update this for maybe 5 years or more
- [x] ham/HamClock/cty/cty_wt_mod-ll-dxcc.txt - Country/prefix database with lat/lon
- [x] ham/HamClock/NOAASpaceWx/rank2_coeffs.txt

### Miscellaneous
- [x] zlib decompress utilty script
- [ ] VOACAP map generator

## Integration Testing Status
- [x] GOES-16 X-Ray Pane
- [x] Countries map
- [x] Terrain map
- [x] DRAP map
- [x] SDO imagery
- [ ] MUF-RT
- [x] Weather map
- [x] Clouds map
- [x] Aurora Day
- [ ] Aurora Night
- [x] Parks on the Air
- [x] SSN
- [x] Solar Wind
- [x] DRAP 
- [x] Planetary Kp
- [x] Solar flux
- [x] Amateur Satellites - see Known Issues
- [ ] PSK Reporter WSPR
- [ ] VOACAP
- [ ] RBN
- [x] PSK Reporter All

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
- sudo apt install -y build-essential gfortran gcc make libc6-dev \\\
libx11-dev libxaw7-dev libxmu-dev libxt-dev libmotif-dev wget (needed for VOACAPL)
- pip install numpy
- pip install pygrib
- pip install matplotlib
- sudo wget https://downloads.sourceforge.net/project/voacap/vocap/voacapl-0.7.6.tar.gz
  Note: VOACAPL install instructions in work
  
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
