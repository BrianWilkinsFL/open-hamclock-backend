#!/usr/bin/env perl
use strict;
use warnings;

use LWP::UserAgent;
use Text::CSV_XS;
use File::Copy qw(move);
use Encode qw(encode);

my $WWFF_URL = 'https://wwff.co/wwff-data/wwff_directory.csv';
my $OUT      = '/opt/hamclock-backend/cache/wwff_parks.csv';
my $TMP      = "$OUT.tmp";

my $ua = LWP::UserAgent->new(
    timeout => 30,
    agent   => 'HamClock-Backend/1.0',
);

print "Downloading WWFF directory...\n";
my $resp = $ua->get($WWFF_URL);
die "Fetch failed: " . $resp->status_line . "\n" unless $resp->is_success;

my $bytes = encode('UTF-8', $resp->decoded_content(charset => 'UTF-8'));
open my $in_fh, '<:encoding(UTF-8)', \$bytes or die "Cannot open content buffer: $!\n";

my $csv = Text::CSV_XS->new({ binary => 1, auto_diag => 1 });

my $header = $csv->getline($in_fh);
die "Could not read header\n" unless $header && @$header;

my %idx;
for my $i (0 .. $#$header) {
    $idx{$header->[$i]} = $i;
}

for my $need (qw(reference latitude longitude iaruLocator)) {
    die "Missing expected column '$need' in WWFF CSV\n" unless exists $idx{$need};
}

my $i_ref  = $idx{reference};
my $i_lat  = $idx{latitude};
my $i_lon  = $idx{longitude};
my $i_grid = $idx{iaruLocator};
my $i_stat = $idx{status} // -1;

open my $out_fh, '>', $TMP or die "Cannot write $TMP: $!\n";
my $out_csv = Text::CSV_XS->new({ binary => 1, eol => "\n" });

$out_csv->print($out_fh, [qw(reference latitude longitude grid)]);

my $count = 0;
while (my $row = $csv->getline($in_fh)) {
    # Skip inactive references if status column is present
    if ($i_stat >= 0) {
        my $status = $row->[$i_stat] // '';
        next unless $status eq 'active';
    }

    my $ref = $row->[$i_ref] // next;
    $ref =~ s/^\s+|\s+$//g;
    next unless length $ref;

    my $lat  = $row->[$i_lat]  // '';
    my $lon  = $row->[$i_lon]  // '';
    my $grid = $row->[$i_grid] // '';

    # Skip rows with no usable coordinates
    next unless length($lat) && length($lon);
    next unless $lat =~ /^-?\d+\.?\d*$/ && $lon =~ /^-?\d+\.?\d*$/;

    # Truncate Maidenhead to 4 characters (WWFF provides 6-char locators)
    $grid = substr($grid, 0, 4) if length($grid) >= 4;

    $out_csv->print($out_fh, [$ref, $lat, $lon, $grid]);
    $count++;
}

close $in_fh;
close $out_fh;

move($TMP, $OUT) or die "move failed $TMP -> $OUT: $!\n";
print "Written $count references to $OUT\n";
