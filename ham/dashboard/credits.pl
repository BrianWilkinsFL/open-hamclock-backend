#!/usr/bin/perl
use strict;
use warnings;
use POSIX qw(strftime);

print "Content-Type: text/html\n\n";


print <<'EOH';
<head>
<style>
a:link {
    color: green;
    background-color: transparent;
    text-decoration: none;
}
a:visited {
    color: pink;
    background-color: transparent;
    text-decoration: none;
}
a:hover {
    color: red;
    background-color: transparent;
    text-decoration: underline;
}
a:active {
    color: yellow;
    background-color: transparent;
    text-decoration: underline;
}
</style>
</head>
EOH

print <<'EOF';
    <div style='color:#f0f0f0;background:transparent;'>
    <div id="tab-credits">

        <p>
        HamClock would not be possible without the following resources:
        <p>

        <ul>
            <li>
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://www.swpc.noaa.gov/">Space Weather Prediction Center</a>
                for several data sets:

                <ul>

                    <li><a target="_blank" href="https://web.archive.org/web/20260123074655/https://services.swpc.noaa.gov/json/solar-cycle/swpc_observed_ssn.json"> Sunspot number</a>
                    </li>

                    <li><a target="_blank" href="https://web.archive.org/web/20260123074655/https://services.swpc.noaa.gov/text/daily-solar-indices.txt">Solar flux monthly</a>
                        and
                        <a target="_blank" href="https://web.archive.org/web/20260123074655/https://services.swpc.noaa.gov/text/wwv.txt"> current</a>
                    </li>


                    <li><a target="_blank" href="https://web.archive.org/web/20260123074655/https://services.swpc.noaa.gov/json/ovation_aurora_latest.json"> Aurora</a>
                    </li>

                    <li><a target="_blank" href="https://web.archive.org/web/20260123074655/https://services.swpc.noaa.gov/products/noaa-scales.json"> Scales</a>
                    </li>

                    <li><a target="_blank" href="https://web.archive.org/web/20260123074655/https://services.swpc.noaa.gov/text/drap_global_frequencies.txt"> DRAP</a>
                    </li>

                    <li><a target="_blank" href="https://web.archive.org/web/20260123074655/https://services.swpc.noaa.gov/json/goes/primary/xrays-3-day.json"> X-Ray</a>
                    </li>

                    <li><a target="_blank" href="https://web.archive.org/web/20260123074655/https://services.swpc.noaa.gov/products/solar-wind/plasma-3-day.json"> Solar wind</a>
                    </li>

                    <li><a target="_blank" href="https://web.archive.org/web/20260123074655/https://services.swpc.noaa.gov/text/daily-geomagnetic-indices.txt"> K index</a>
                    and
                    <a target="_blank" href="https://web.archive.org/web/20260123074655/https://services.swpc.noaa.gov/text/3-day-solar-geomag-predictions.txt"> K and SFI forecast </a>
                    </li>

                    <li><a target="_blank" href="https://web.archive.org/web/20260123074655/https://services.swpc.noaa.gov/text/ace-magnetometer.txt"> Bz and Bt</a>
                    </li>

                </ul>

            </li>


            <li>
                Jari Perkimki, Gregory Hand and Jim Watson for generous
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://www.voacap.com/">VOACAP</a>
                support.
            </li>

            <li>
                DX cluster
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://www.ng3k.com/misc/cluster.html">operators</a>
                and spotters the world over.
            </li>

            <li>
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://www.sota.org.uk/">SOTA</a>,
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://pota.app/">POTA</a> and
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://wwff.co/">WWFF</a>
                users and their respective data base maintainers.
            </li>

            <li>
                Bruce Horn, WA7BNM, for the
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://www.contestcalendar.com/weeklycont.php">
                8 day context calendar</a>.
            </li>

            <li>
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://www.celestrak.com/">Celestrak</a>
                for timely satellite elements.
            </li>

            <li>
                NASA for
                    <a target="_blank" href="https://web.archive.org/web/20260123074655/https://sdo.gsfc.nasa.gov/">SDO</a>
                and
                    <a target="_blank" href="https://web.archive.org/web/20260123074655/https://stereo.gsfc.nasa.gov/">STEREO</a> 
                images.
            </li>

            <li>
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://nrc.canada.ca/en">National Research Council Canada </a>
                for 70 years of continuous
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://www.spaceweather.gc.ca/forecast-prevision/solar-solaire/solarflux/sx-en.php">10.7 cm solar flux</a>
                data and
                Dr. Ken Tapping for his gracious support to the amateur radio community.
            </li>

            <li>
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://openweathermap.org/">Open Weather Map</a>
                for near-real-time world-wide weather data.
            </li>

            <li> Philip Gladstone, N1DQ, for assistance and live data from his web site
                <a target="_blank" href="https://web.archive.org/web/20260123074655/http://pskreporter.info/"> PSKReport.info </a>.
            </li>

            <li> Pete Smith, N4ZR, and Felipe Ceglia, PY1NB, for their innovation and tireless
                work behind the scenes at the
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://reversebeacon.net/"> Reverse Beacon Network.</a>
            </li>

            <li> Arne for assistance and live data from his site
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://wspr.live/"> wspr.live </a>.
            </li>

            <li> NOAA for the
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://www.ncei.noaa.gov/products/world-magnetic-model"> World Magnetic Model</a>
                and their
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://sos.noaa.gov/"> Science on a Sphere</a> real-time cloud maps.
            </li>

            <li> Davidson Francis for his
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://github.com/Theldus/wsServer"> Websocket server</a>.
            </li>

            <li>
                Andrew D. Rodland, KC2G, for providing ready access to the data behind his
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://prop.kc2g.com/">ionosonde map</a>
                which in turn are provided by
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://prop.kc2g.com/acknowledgments">these organizations</a>.
            </li>

            <li>
                Sean Barrett for compact and easy-to-use image format writer
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://github.com/nothings/stb/blob/master/stb_image_write.h">
                here</a>.
            </li>

            <li>
                Jim Reisert, AD1C, for maintaining the 
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://www.country-files.com/">cty country file</a>.
            </li>

            <li>
                ITU and CQ zones based on data from
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://zone-check.eu/">zone-check.eu</a>.
            </li>

            <li>
                Mario, DL4MFM, for his support and assistance with data from 
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://wwff.co/">WWFF</a>.
            </li>

            <li>
                DX expedition data from
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://www.ng3k.com/Misc/adxo.html">NG3K</a>
                and
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://dxnews.com/dxpeditions">DXNews</a>
            </li>

            <li>
                World Data Center for Geomagnetism, Kyoto University, for
                <a target="_blank" href="https://web.archive.org/web/20260123074655/https://wdc.kugi.kyoto-u.ac.jp/wdc/Sec3.html">DST data</a>.
            </li>

        </ul>

        <p>
        And special <b>Shoutouts</b> to
        <a target="_blank" href="https://web.archive.org/web/20260123074655/https://www.adafruit.com/about">Adafruit</a>
        and
        <a target="_blank" href="https://web.archive.org/web/20260123074655/https://www.raspberrypi.org/about">Raspberry Pi Foundation</a>
        for great products and support.

    </div>    <!-- tab-credits -->
<div>
EOF
