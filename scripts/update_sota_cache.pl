#!/usr/bin/env perl
use strict;
use warnings;

use LWP::UserAgent;
use Text::CSV_XS;
use File::Copy qw(move);
use POSIX qw(floor);

my $SOTA_URL = 'https://storage.sota.org.uk/summitslist.csv';
my $OUT      = '/opt/hamclock-backend/cache/sota_summits.csv';
my $TMP      = "$OUT.tmp";

# ---------------------------------------------------------------------------
# Compute Maidenhead grid square (4-character) from longitude and latitude
# ---------------------------------------------------------------------------
sub latlon_to_grid {
    my ($lat, $lon) = @_;

    return '' if !defined $lat || !defined $lon;
    return '' if $lat < -90 || $lat > 90 || $lon < -180 || $lon > 180;

    my $adj_lon = $lon + 180.0;
    my $adj_lat = $lat + 90.0;

    my $field_lon = floor($adj_lon / 20);
    my $field_lat = floor($adj_lat / 10);

    my $sq_lon = floor(($adj_lon - $field_lon * 20) / 2);
    my $sq_lat = floor($adj_lat - $field_lat * 10);

    return sprintf('%s%s%d%d',
        chr(ord('A') + $field_lon),
        chr(ord('A') + $field_lat),
        $sq_lon,
        $sq_lat,
    );
}

# ---------------------------------------------------------------------------
# Download SOTA summits list
# ---------------------------------------------------------------------------
my $ua = LWP::UserAgent->new(
    timeout => 30,
    agent   => 'HamClock-Backend/1.0',
);

print "Downloading SOTA summits list...\n";
my $resp = $ua->get($SOTA_URL);
die "Fetch failed: " . $resp->status_line . "\n" unless $resp->is_success;

my $content = $resp->decoded_content(charset => 'UTF-8');

# Strip the non-CSV first line ("SOTA Summits List (Date=...)")
$content =~ s/^[^\n]*\n// if $content =~ /^SOTA Summits List/;

# ---------------------------------------------------------------------------
# Parse and write output CSV
# ---------------------------------------------------------------------------
# Encode back to UTF-8 bytes so Perl can open it as an in-memory filehandle
# (wide characters in summit names prevent opening a decoded string directly)
use Encode qw(encode);
my $bytes = encode('UTF-8', $content);
open my $in_fh, '<:encoding(UTF-8)', \$bytes or die "Cannot open content buffer: $!\n";

my $csv = Text::CSV_XS->new({ binary => 1, auto_diag => 1 });

# Read and validate header
my $header = $csv->getline($in_fh);
die "Could not read header\n" unless $header && @$header;

# Expected columns (0-based):
#   0=SummitCode, 1=AssociationName, 2=RegionName, 3=SummitName,
#   4=AltM, 5=AltFt, 6=GridRef1, 7=GridRef2,
#   8=Longitude, 9=Latitude, 10=Points, ...
my %idx;
for my $i (0 .. $#$header) {
    $idx{$header->[$i]} = $i;
}
for my $need (qw(SummitCode Longitude Latitude)) {
    die "Missing expected column '$need' in SOTA CSV\n" unless exists $idx{$need};
}

my $i_code = $idx{SummitCode};
my $i_lon  = $idx{Longitude};
my $i_lat  = $idx{Latitude};

open my $out_fh, '>', $TMP or die "Cannot write $TMP: $!\n";
my $out_csv = Text::CSV_XS->new({ binary => 1, eol => "\n" });

# Write header matching the format load_parks_lookup() expects
$out_csv->print($out_fh, [qw(reference latitude longitude grid)]);

my $count = 0;
while (my $row = $csv->getline($in_fh)) {
    my $ref = $row->[$i_code] // next;
    $ref =~ s/^\s+|\s+$//g;
    next unless length $ref;

    my $lon = $row->[$i_lon] // '';
    my $lat = $row->[$i_lat] // '';

    # Skip rows with no usable coordinates
    next unless length($lon) && length($lat);
    next unless $lon =~ /^-?\d+\.?\d*$/ && $lat =~ /^-?\d+\.?\d*$/;

    my $grid = latlon_to_grid($lat + 0, $lon + 0);

    $out_csv->print($out_fh, [$ref, $lat, $lon, $grid]);
    $count++;
}

close $in_fh;
close $out_fh;

move($TMP, $OUT) or die "move failed $TMP -> $OUT: $!\n";
print "Written $count summits to $OUT\n";
