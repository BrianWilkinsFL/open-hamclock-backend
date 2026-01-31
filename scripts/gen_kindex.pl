#!/usr/bin/env perl
use strict;
use warnings;

use LWP::UserAgent;
use File::Temp qw(tempfile);

# NOAA source
my $URL = 'https://services.swpc.noaa.gov/text/daily-geomagnetic-indices.txt';

# HamClock constants (derived from client + observed file)
my $KP_NV = 45;

my $OUT = 'kindex.txt';

my $ua = LWP::UserAgent->new(
    timeout => 20,
    agent   => 'HamClock-kindex-backend/1.0'
);

my $resp = $ua->get($URL);
die "ERROR: fetch failed\n" unless $resp->is_success;

my @kp_series;

# Parse NOAA file
for my $line (split /\n/, $resp->decoded_content) {

    next if $line =~ /^\s*#/;
    next unless $line =~ /^\d{4}\s+\d{2}\s+\d{2}/;

    my @f = split /\s+/, $line;

    # Planetary Kp floats are the LAST 8 fields
    my @kp = @f[-8 .. -1];

    for my $v (@kp) {
        next if $v < 0;              # skip future slots
        push @kp_series, sprintf("%.2f", $v);
    }
}

# Take the last KP_NV completed values
@kp_series = @kp_series[-$KP_NV .. -1] if @kp_series > $KP_NV;

# IMPORTANT: output oldest -> newest (client expects this)
my ($fh, $tmp) = tempfile('kindexXXXX', UNLINK => 0);
print $fh "$_\n" for @kp_series;
close $fh;

rename $tmp, $OUT or die "ERROR: rename failed: $!\n";

