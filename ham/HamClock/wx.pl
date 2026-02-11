#!/usr/bin/perl

use strict;
use warnings;
use HTTP::Tiny;
use JSON::PP;

my $UA = HTTP::Tiny->new(
    timeout => 5,
    agent   => "HamClock-NOAA/1.1"
);

# -------------------------
# Parse QUERY_STRING
# -------------------------
my %q;
if ($ENV{QUERY_STRING}) {
    for (split /&/, $ENV{QUERY_STRING}) {
        my ($k,$v) = split /=/, $_, 2;
        next unless defined $k;
        $v //= '';
        $v =~ tr/+/ /;
        $v =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
        $q{$k} = $v;
    }
}

my ($lat,$lng) = @q{qw(lat lng)};

# -------------------------
# Defaults
# -------------------------
my %wx = (
    city             => "",
    temperature_c    => -999,
    pressure_hPa     => -999,
    pressure_chg     => -999,
    humidity_percent => -999,
    dewpoint         => -999,
    wind_speed_mps   => 0,
    wind_dir_name    => "N",
    clouds           => "",
    conditions       => "",
    attribution      => "weather.gov",
    timezone         => 0,
);

# -------------------------
# NOAA pipeline
# -------------------------
if (defined $lat && defined $lng) {

    # Timezone approximation (parity with OWM)
    $wx{timezone} = approx_timezone_seconds($lng);

    # 1) points lookup
    my $p = $UA->get("https://api.weather.gov/points/$lat,$lng");
    if ($p->{success}) {
        my $pd = eval { decode_json($p->{content}) };

        if ($pd && $pd->{properties}) {

            # City from relativeLocation
            my $rl = $pd->{properties}->{relativeLocation}->{properties};
            $wx{city} = $rl->{city} if $rl && $rl->{city};

            # Stations URL
            my $stations_url = $pd->{properties}->{observationStations};
            my $s = $UA->get($stations_url);

            if ($s->{success}) {
                my $sd = eval { decode_json($s->{content}) };
                for my $station (@{ $sd->{features} }) {
                    if ($station->{properties}->{stationIdentifier}) {
                        my $stationIdentifier = $station->{properties}->{stationIdentifier};
                        my $o = $UA->get(
                            "https://api.weather.gov/stations/$stationIdentifier/observations/latest"
                        );

                        if ($o->{success}) {
                            my $od = eval { decode_json($o->{content}) };
                            my $p = $od->{properties};

                            $wx{temperature_c}    = val($p->{temperature}->{value});
                            $wx{humidity_percent} = val($p->{relativeHumidity}->{value});
                            $wx{dewpoint}         = val($p->{dewpoint}->{value});
                            $wx{wind_speed_mps}   = val($p->{windSpeed}->{value});
                            $wx{wind_dir_name}    = deg_to_cardinal(val($p->{windDirection}->{value}));

                            if (defined $p->{seaLevelPressure}->{value}) {
                                $wx{pressure_hPa} =
                                    sprintf("%.0f", $p->{seaLevelPressure}->{value} / 100);
                            }

                            $wx{conditions} = $p->{textDescription} // "";
                            $wx{clouds}     = $p->{textDescription} // "";
                            last;
                        }
                    }
                }
            }
        }
    }
}

# -------------------------
# Output (HamClock format)
# -------------------------
print "HTTP/1.0 200 Ok\r\n";
print "Content-Type: text/plain; charset=ISO-8859-1\r\n";
print "Connection: close\r\n\r\n";

print "city=$wx{city}\n";
print "temperature_c=$wx{temperature_c}\n";
print "pressure_hPa=$wx{pressure_hPa}\n";
print "pressure_chg=$wx{pressure_chg}\n";
print "humidity_percent=$wx{humidity_percent}\n";
print "dewpoint=$wx{dewpoint}\n";
print "wind_speed_mps=$wx{wind_speed_mps}\n";
print "wind_dir_name=$wx{wind_dir_name}\n";
print "clouds=$wx{clouds}\n";
print "conditions=$wx{conditions}\n";
print "attribution=$wx{attribution}\n";
print "timezone=$wx{timezone}\n";

exit;

# -------------------------
# Helpers
# -------------------------
sub val {
    my ($v) = @_;
    return -999 unless defined $v;
    return sprintf("%.2f",$v);
}

sub deg_to_cardinal {
    my ($deg) = @_;
    return "N" unless defined $deg;
    my @d = qw(N NE E SE S SW W NW);
    return $d[int((($deg % 360)+22.5)/45)%8];
}

sub approx_timezone_seconds {
    my ($lng) = @_;
    return 0 unless defined $lng;

    # Longitude to timezone hours (15° per hour), rounded
    my $hours = int(($lng / 15) + ($lng >= 0 ? 0.5 : -0.5));

    # OpenWeatherMap-style offset: hours * 3600
    return $hours * 3600;
}
