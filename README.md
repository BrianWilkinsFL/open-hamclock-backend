# open-hamclock-backend
Open Source and Faithful HamClock Backend Replacement. This is a community project and no relation to the creator of HamClock Elwood Downey, WB0OEW, ecdowney@clearskyinstitute.com SK

I wish the Downey family my deepest condolences.

This is a WIP.

# License
MIT - this is free. Not for commercial use

# Project Completion Status

HamClock requests about 40+ artifacts. I have locally replicated all of them that I could find.

- [x] Bz.txt generator (and crontab)
- [x] wx.pl working
- [x] Xray.txt generator
- [x] aurora.txt generator (and publisher)
- [ ] VOACAP map generator
- [x] IP geolocation fetch implemented - requires free tier 1000 req per day account and API key
- [ ] fetchBandConditions.pl re-implemented
- [ ] SDO/f_211_193_171_170.bmp.z
- [ ] SDO/latest_170_HMIB.bmp.z
- [ ] fetchVOACAPArea.pl
- [x] fetchPSKReporter.pl?ofgrid=XXYY&maxage=1800 
- [ ] worldwx/wx.txt
- [x] esats/esats.txt
- [ ] solarflux/solarflux-history.txt
- [ ] ssn/ssn-history.txt
- [x] solar-flux/solarflux-99.txt (this requires a local cache to be built up - I made a bootstrap script)
- [x] geomag/kindex.txt
- [x] dst/dst.txt
- [x] drap/stats.txt
- [x] solar-wind/swind-24hr.txt generator
- [x] cron job to put swind-24hr.txt in the solar-wind location
- [x] cities2.txt (static city file - no urgency to update this for maybe 5 years or more)
- [x] ssn/ssn-31.txt
- [x] ONTA/onta.txt
- [ ] contests/contests311.txt (this may stay broken until an agreement is made based on the site's ToS https://www.contestcalendar.com/terms.php)
- [x] dxpeds/dxpeditions.txt
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
- [x] ham/HamClock/RSS/web15rss.pl
- [x] ham/HamClock/version.pl
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
- VOACAPL: https://www.qsl.net/hz1jw/voacapl/index.html

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

  # Update the server modules inside your lighttpd configuration file located at: /etc/lighttpd/lighttpd.conf
  # Only change should be the "mod_cgi" module at the end:
      server.modules = (
          "mod_indexfile",
          "mod_access",
          "mod_alias",
          "mod_redirect",
          "mod_cgi",
      )

  sudo lighttpd -tt -f /etc/lighttpd/lighttpd.conf
  sudo lighttpd-enable-mod hamclock
  sudo systemctl restart lighttpd
  # add crontab as user www-data and described in scripts/crontab
```

# Automated Pulls
- Every 30 minutes: /opt/hamclock-backend/scripts/gen_aurora.sh
- Every 5 minutes: /opt/hamclock-backend/scripts/gen_onta.pl
- Once per day at 12:15am /opt/hamclock-backend/scripts/update_solarflux_cache.pl
- Once per day at 12:20am /opt/hamclock-backend/scripts/publish_solarflux_99.pl
- Once per day at 12:10am /opt/hamclock-backend/scripts/gen_swind_24hr.pl
- Every 5 minutes: /opt/hamclock-backend/scripts/bzgen.sh
- Once per minute: /opt/hamclock-backend/scripts/genxray.pl
  
```
