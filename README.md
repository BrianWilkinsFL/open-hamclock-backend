# open-hamclock-backend
Open Source and Faithful HamClock Backend Replacement. This is a community project and no relation to the creator of HamClock Elwood Downey, WB0OEW, ecdowney@clearskyinstitute.com SK

I wish the Downey family my deepest condolences.

This is a WIP.

# License
MIT - this is free. Not for commercial use

# Project Completion Status

HamClock requests about 40+ artifacts. I have locally replicated all of them that I could find.

- [x] Bz.txt generator
- [x] wx.pl working
- [x] Xray.txt generator
- [ ] aurora.txt generator
- [ ] VOACAP map generator
- [x] IP geolocation fetch implemented - requires free tier 1000 req per day account and API key
- [ ] fetchBandConditions.pl re-implemented
- [ ] SDO/f_211_193_171_170.bmp.z
- [ ] SDO/latest_170_HMIB.bmp.z
- [ ] fetchVOACAPArea.pl
- [ ] fetchPSKReporter.pl?ofgrid=XXYY&maxage=1800 
- [ ] worldwx/wx.txt
- [ ] solar-flux/solarflux-99.txt
- [x] geomag/kindex.txt
- [ ] dst/dst.txt
- [ ] drap/stats.txt
- [ ] solar-wind/swind-24hr.txt
- [ ] cities2.txt
- [ ] ssn/ssn-31.txt
- [ ] ONTA/onta.txt
- [ ] contests/contests311.txt
- [ ] dxpeds/dxpeditions.txt
- [ ] NOAASpaceWX/noaaswx.txt
- [ ] maps/map-D-2640x1320-Countries.bmp.z
- [ ] maps/map-N-2640x1320-Countries.bmp.z
- [ ] maps/map-D-660x330-Clouds.bmp.z
- [ ] maps/map-N-660x330-Clouds.bmp.z
- [ ] maps/map-N-660x330-Terrain.bmp.z
- [ ] maps/map-D-660x330-DRAP-S.bmp.z
- [ ] maps/map-N-660x330-DRAP-S.bmp.z
- [ ] maps/map-N-660x330-MUF-RT.bmp.z
- [ ] maps/map-D-660x330-MUF-RT.bmp.z
- [ ] maps/map-D-660x330-Aurora.bmp.z
- [ ] maps/map-N-660x330-Aurora.bmp.z
- [ ] maps/map-D-660x330-Wx-mB.bmp.z
- [ ] maps/map-N-660x330-Wx-mB.bmp.z
- [ ] SDO/f_304_170.bmp.z
- [ ] fetchVOACAP-MUF.pl?YEAR=2026&MONTH=1&UTC=17&TXLAT=&TXLNG=&PATH=0&WATTS=100&WIDTH=660&HEIGHT=330&MHZ=0.00&TOA=3.0&MODE=19&TOA=3.0
- [ ] fetchVOACAP-TOA.pl?YEAR=2026&MONTH=1&UTC=17&TXLAT=&TXLNG=&PATH=0&WATTS=100&WIDTH=660&HEIGHT=330&MHZ=14.10&TOA=3.0&MODE=19&TOA=3.0
- [ ] RSS/web15rss.pl
- [x] HamWeekly.com RSS feed generator
- [x] AR Newsline RSS feed generator
- [x] NG3K.com feed generator
- [x] zlib decompress utilty script
- [x] Generic backend to keep HamClocks alive beyond June 2026
- [ ] Complete end-to-end working backend

# Vision
The goal is to make this as a drop-in replacement for the HamClock backend by replicating the same client/server responses with Perl CGI scripting and static files. We don't have access to the backend server source code so this is completely created by looking at the interfaces. To allow existing HamClock's running on Arduino to continue to work, we will setup a local DNS sinkhole to redirect to your local backend running at your home or office.

# Requirements:
- perl
- lighttpd (or apache httpd with CGI enabled)
- perl-libwww-perl
- perl-JSON
- perl-XML-RSS
- perl-XML-Feed
- perl-HTML-Parser

### Prerequisites

This backend is designed to be lightweight and portable. It relies on a standard web server with CGI support and a small set of Perl modules.

You will need:

- Perl 5.10 or newer
- `lighttpd` (recommended) or Apache httpd with CGI enabled
- Cron (for scheduled data generation)
  
# Install:
```bash
  apt install \
  lighttpd \
  libwww-perl \
  libjson-perl \
  libxml-rss-perl \
  libxml-feed-perl \
  libhtml-parser-perl
  
  sudo tar xzf hamclock-backend.tar.gz -C /opt
  sudo chown -R www-data:www-data /opt/hamclock-backend
  sudo chmod +x /opt/hamclock-backend/htdocs/ham/HamClock/*.pl
  sudo cp 50-hamclock.conf /etc/lighttpd/conf-available/50-hamclock.conf
  sudo lighttpd -tt -f /etc/lighttpd/lighttpd.conf
  sudo lighttpd-enable-mod hamclock
  sudo systemctl restart lighttpd
