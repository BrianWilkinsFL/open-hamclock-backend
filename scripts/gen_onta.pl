#!/usr/bin/env perl
use strict;
use warnings;

use LWP::UserAgent;
use JSON qw(decode_json);
use Time::Local;
use Text::CSV_XS;
use File::Copy qw(move);

my $POTA_URL = 'https://api.pota.app/spot';
my $SOTA_URL = 'https://parksnpeaks.org/api/ALL';
my $WWFF_URL = 'https://www.cqgma.org/api/spots/wwff/';
my $OUT      = '/opt/hamclock-backend/htdocs/ham/HamClock/ONTA/onta.txt';
my $TMP      = "$OUT.tmp";

my $POTA_CSV = '/opt/hamclock-backend/cache/all_parks_ext.csv';
my $SOTA_CSV = '/opt/hamclock-backend/cache/sota_summits.csv';
my $WWFF_CSV = '/opt/hamclock-backend/cache/wwff_parks.csv';

# HamClock rejects callsigns longer than 12 characters
my $MAX_CALL  = 12;
# Parks'n'Peaks returns up to ~4 hours of history so match that window.
# POTA spots older than 1h will simply be deduped by fresher ones.
my $MAX_AGE_S = 14400;

sub org_from_ref {
    my ($ref) = @_;
    return 'WWFF' if defined($ref) && $ref =~ /^[A-Z]{1,4}FF-/i;
    return 'SOTA' if defined($ref) && $ref =~ m{/};     # e.g. W7O/NC-051
    return 'POTA';
}

# ---------------------------------------------------------------------------
# Load a reference lookup CSV into a hash keyed by reference string.
# Expects columns: reference, latitude, longitude, grid
# ---------------------------------------------------------------------------
sub load_lookup {
    my ($path) = @_;
    my %park;

    return %park unless -f $path;

    open my $fh, '<:encoding(UTF-8)', $path or do {
        warn "Cannot read $path: $!\n";
        return %park;
    };

    my $csv = Text::CSV_XS->new({ binary => 1, auto_diag => 1 });

    my $header = $csv->getline($fh);
    unless ($header && @$header) {
        warn "Empty or unreadable header in $path\n";
        close $fh;
        return %park;
    }

    my %idx;
    for my $i (0 .. $#$header) {
        my $k = $header->[$i] // next;
        $k =~ s/^"|"$//g;
        $idx{$k} = $i;
    }

    for my $need (qw(reference latitude longitude grid)) {
        unless (exists $idx{$need}) {
            warn "Missing '$need' column in $path\n";
            close $fh;
            return %park;
        }
    }

    while (my $row = $csv->getline($fh)) {
        my $ref = $row->[$idx{reference}] // next;
        $ref =~ s/^"|"$//g;

        $park{$ref} = {
            lat  => ($row->[$idx{latitude}]  // ''),
            lng  => ($row->[$idx{longitude}] // ''),
            grid => ($row->[$idx{grid}]      // ''),
        };
    }

    close $fh;
    return %park;
}

my %pota_lookup = load_lookup($POTA_CSV);
my %sota_lookup = load_lookup($SOTA_CSV);
my %wwff_lookup = load_lookup($WWFF_CSV);

# Merge into one hash; POTA takes precedence over WWFF, WWFF over SOTA
# for any ref that somehow appears in multiple sources.
my %park_lookup = (%sota_lookup, %wwff_lookup, %pota_lookup);

my $ua = LWP::UserAgent->new(
    timeout => 10,
    agent   => 'HamClock-Backend/1.0',
);

my $now = time();
my %best;   # dedup key -> row hashref

# ---------------------------------------------------------------------------
# Helper: attempt to resolve location for a park/summit reference.
# Returns (grid, lat, lng) — all empty/zero if not found.
# ---------------------------------------------------------------------------
sub resolve_location {
    my ($ref) = @_;
    return ('', 0, 0) unless $ref && exists $park_lookup{$ref};
    return (
        $park_lookup{$ref}{grid} // '',
        $park_lookup{$ref}{lat}  // 0,
        $park_lookup{$ref}{lng}  // 0,
    );
}

# ---------------------------------------------------------------------------
# Source 1: POTA  (https://api.pota.app/spot)
# Fields: activator, frequency (kHz), mode, reference, spotTime (ISO8601 UTC)
# ---------------------------------------------------------------------------
{
    my $resp = $ua->get($POTA_URL);
    if ($resp->is_success) {
        my $spots = decode_json($resp->decoded_content);
        if (ref $spots eq 'ARRAY') {
            for my $s (@$spots) {
                next unless ref $s eq 'HASH';

                my $call = $s->{activator} // next;
                next if length($call) > $MAX_CALL;
                my $freq = $s->{frequency} // next;   # kHz
                my $mode = $s->{mode}      // '';
                my $park = $s->{reference} // '';
                my $time = $s->{spotTime}  // next;

                my ($Y,$m,$d,$H,$M,$S) =
                    $time =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/
                    or next;

                my $epoch = timegm($S,$M,$H,$d,$m-1,$Y);
                next if ($now - $epoch) > $MAX_AGE_S;

                my $hz = int((0 + $freq) * 1000);
                next unless $hz > 0 && $hz <= 1_300_000_000;  # sanity: max ~1.3 GHz

                my $org = org_from_ref($park);

                my ($grid, $lat, $lng) = resolve_location($park);

                # Skip if HamClock would reject it (no location data)
                next unless $grid || ($lat != 0 && $lng != 0);

                my $key = join('|', $call, $park, $mode, $hz, $org);

                if (!exists $best{$key} || $epoch > $best{$key}{epoch}) {
                    $best{$key} = {
                        call  => $call,
                        hz    => $hz,
                        epoch => $epoch,
                        mode  => $mode,
                        grid  => $grid,
                        lat   => $lat,
                        lng   => $lng,
                        park  => $park,
                        org   => $org,
                    };
                }
            }
        }
    } else {
        warn "POTA fetch failed: " . $resp->status_line . "\n";
    }
}

# ---------------------------------------------------------------------------
# Source 2: SOTA via Parks'n'Peaks  (https://parksnpeaks.org/api/ALL)
# Fields: actCallsign, actFreq (MHz), actMode, actSiteID, actClass,
#         actTime ("YYYY-MM-DD HH:MM:SS" UTC)
# ---------------------------------------------------------------------------
{
    my $resp = $ua->get($SOTA_URL);
    if ($resp->is_success) {
        my $spots = decode_json($resp->decoded_content);
        if (ref $spots eq 'ARRAY') {
            for my $s (@$spots) {
                next unless ref $s eq 'HASH';

                my $cls = uc($s->{actClass} // '');
                next unless $cls eq 'SOTA';

                my $call = $s->{actCallsign} // next;
                next if length($call) > $MAX_CALL;
                my $freq = $s->{actFreq}     // next;   # MHz
                my $mode = $s->{actMode}     // '';
                my $time = $s->{actTime}     // next;
                my $park = $s->{actSiteID}   // '';

                # Parse "YYYY-MM-DD HH:MM:SS"
                my ($Y,$m,$d,$H,$M,$S) =
                    $time =~ /^(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})/
                    or next;

                my $epoch = timegm($S,$M,$H,$d,$m-1,$Y);
                next if ($now - $epoch) > $MAX_AGE_S;

                next unless length($freq) && $freq > 0;
                my $hz = int($freq * 1_000_000 + 0.5);
                next unless $hz > 0 && $hz <= 1_300_000_000;

                my ($grid, $lat, $lng) = resolve_location($park);
                next unless $grid || ($lat != 0 && $lng != 0);

                my $key = join('|', $call, $park, $mode, $hz, 'SOTA');

                if (!exists $best{$key} || $epoch > $best{$key}{epoch}) {
                    $best{$key} = {
                        call  => $call,
                        hz    => $hz,
                        epoch => $epoch,
                        mode  => $mode,
                        grid  => $grid,
                        lat   => $lat,
                        lng   => $lng,
                        park  => $park,
                        org   => 'SOTA',
                    };
                }
            }
        }
    } else {
        warn "Parks'n'Peaks fetch failed: " . $resp->status_line . "\n";
    }
}

# ---------------------------------------------------------------------------
# Source 3: WWFF via cqgma.org  (https://www.cqgma.org/api/spots/wwff/)
# Fields: ACTIVATOR, QRG (MHz), MODE, REF, LAT, LON, DATE ("YYYYMMDD"),
#         TIME ("HHMM" UTC)
# Location is embedded in each spot — no cache lookup needed.
# ---------------------------------------------------------------------------
{
    my $resp = $ua->get($WWFF_URL);
    if ($resp->is_success) {
        my $data = decode_json($resp->decoded_content);
        my $spots = $data->{RCD} // [];
        for my $s (@$spots) {
            next unless ref $s eq 'HASH';

            my $call = uc($s->{ACTIVATOR} // '');
            $call =~ s/^\s+|\s+$//g;
            next unless length $call;
            next if length($call) > $MAX_CALL;

            my $freq = $s->{QRG}  // next;   # kHz
            my $mode = uc($s->{MODE} // '');
            next unless length $mode;         # skip spots with no mode

            my $park = $s->{REF}  // next;
            my $lat  = $s->{LAT}  // next;
            my $lon  = $s->{LON}  // next;
            my $date = $s->{DATE} // next;   # YYYYMMDD
            my $time = $s->{TIME} // next;   # HHMM

            next unless length($freq) && $freq > 0;
            my $hz = int($freq * 1000);      # kHz -> Hz
            next unless $hz > 0 && $hz <= 1_300_000_000;

            next unless $date =~ /^(\d{4})(\d{2})(\d{2})$/ ;
            my ($Y, $m, $d) = ($1, $2, $3);
            next unless $time =~ /^(\d{2})(\d{2})$/;
            my ($H, $M) = ($1, $2);

            my $epoch = eval { timegm(0, $M, $H, $d, $m-1, $Y) } or next;
            next if ($now - $epoch) > $MAX_AGE_S;

            next unless length($lat) && length($lon);
            next unless $lat =~ /^-?\d+\.?\d*$/ && $lon =~ /^-?\d+\.?\d*$/;

            # Compute 4-char Maidenhead grid from embedded coordinates
            use POSIX qw(floor);
            my $grid = do {
                my $alon = $lon + 180.0;
                my $alat = $lat + 90.0;
                my $fl = floor($alon / 20);
                my $fla = floor($alat / 10);
                my $sl = floor(($alon - $fl * 20) / 2);
                my $sla = floor($alat - $fla * 10);
                sprintf('%s%s%d%d',
                    chr(ord('A') + $fl),
                    chr(ord('A') + $fla),
                    $sl, $sla);
            };

            my $key = join('|', $call, $park, $mode, $hz, 'WWFF');

            if (!exists $best{$key} || $epoch > $best{$key}{epoch}) {
                $best{$key} = {
                    call  => $call,
                    hz    => $hz,
                    epoch => $epoch,
                    mode  => $mode,
                    grid  => $grid,
                    lat   => $lat,
                    lng   => $lon,
                    park  => $park,
                    org   => 'WWFF',
                };
            }
        }
    } else {
        warn "WWFF fetch failed: " . $resp->status_line . "\n";
    }
}

# ---------------------------------------------------------------------------
# Sort newest-first, cap, write output
# ---------------------------------------------------------------------------
my @out = sort { $b->{epoch} <=> $a->{epoch} } values %best;

open my $fh, '>', $TMP or die "Cannot write temp file $TMP: $!\n";
print $fh "#call,Hz,unix,mode,grid,lat,lng,park,org\n";

for my $r (@out) {
    print $fh join(',',
        $r->{call},
        $r->{hz},
        $r->{epoch},
        $r->{mode},
        $r->{grid},
        $r->{lat},
        $r->{lng},
        $r->{park},
        $r->{org},
    ), "\n";
}

close $fh;
move $TMP, $OUT or die "move failed $TMP -> $OUT: $!\n";
