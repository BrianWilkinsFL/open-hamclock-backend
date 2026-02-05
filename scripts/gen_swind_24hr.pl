#!/usr/bin/env perl
use strict;
use warnings;

use LWP::UserAgent;
use JSON qw(decode_json);
use Time::Local;

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------
my $URL = 'https://services.swpc.noaa.gov/products/solar-wind/plasma-3-day.json';
my $MAX_SAMPLES = 1440;   # 24 hours @ 1-minute cadence

# ------------------------------------------------------------
# Fetch NOAA data
# ------------------------------------------------------------
my $ua = LWP::UserAgent->new(
    timeout => 10,
    agent   => 'HamClock-Backend/1.0',
);

my $resp = $ua->get($URL);
die "ERROR: fetch failed\n" unless $resp->is_success;

my $rows = decode_json($resp->decoded_content);
die "ERROR: bad JSON\n" unless ref $rows eq 'ARRAY';
die "ERROR: insufficient rows\n" unless @$rows > 1;

# ------------------------------------------------------------
# Header row → column index map
# ------------------------------------------------------------
my %col;
for my $i (0 .. $#{$rows->[0]}) {
    $col{ $rows->[0][$i] } = $i;
}

for my $required (qw(time_tag density speed)) {
    die "ERROR: missing column $required\n"
        unless exists $col{$required};
}

# ------------------------------------------------------------
# Parse rows
# ------------------------------------------------------------
my @samples;

for my $i (1 .. $#$rows) {
    my $row = $rows->[$i];
    next unless ref $row eq 'ARRAY';

    my $time = $row->[ $col{time_tag} ];
    my $dens = $row->[ $col{density} ];
    my $spd  = $row->[ $col{speed} ];

    next unless defined $time && defined $dens && defined $spd;
    next if $dens eq '' || $spd eq '';

    # Strip milliseconds: "YYYY-MM-DD HH:MM:SS.mmm"
    $time =~ s/\.\d+$//;

    # Parse timestamp (UTC)
    my ($Y,$m,$d,$H,$M,$S) =
        $time =~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/
        or next;

    my $epoch = timegm($S, $M, $H, $d, $m-1, $Y);

    push @samples, [
        $epoch,
        $dens + 0,
        $spd  + 0
    ];
}

# ------------------------------------------------------------
# Sort and window
# ------------------------------------------------------------
@samples = sort { $a->[0] <=> $b->[0] } @samples;

# Keep last 1440 samples only
@samples = splice(@samples, -$MAX_SAMPLES)
    if @samples > $MAX_SAMPLES;

# ------------------------------------------------------------
# Emit HamClock-compatible output
# ------------------------------------------------------------
for my $s (@samples) {
    printf "%d %.2f %.1f\n", @$s;
}

