#!/usr/bin/env perl
use strict;
use warnings;

# ----------------------------
# Configuration
# ----------------------------

my $OUT = $ENV{ESATS_OUT}
    // "/opt/hamclock-backend/htdocs/ham/HamClock/esats/esats.txt";

my $ESATS1 = $ENV{ESATS_ORIGINAL}
    // "/opt/hamclock-backend/htdocs/ham/HamClock/esats/esats.subset.txt";

my $TLE_FILE = $ENV{ESATS_TLE_CACHE}
    // "/opt/hamclock-backend/tle/tles.txt";

# ----------------------------
# Parse TLE blocks
# ----------------------------

sub parse_tle_blocks {
    my ($content) = @_;
    my @lines = split /\n/, $content;
    my @blocks;

    my $i = 0;
    while ($i < @lines) {
        my $name = $lines[$i++];
        next unless defined $name;
        $name =~ s/\r$//;
        $name =~ s/^\s+|\s+$//g;
        next if $name eq '';

        my $l1;
        while ($i < @lines) {
            my $x = $lines[$i++];
            next unless defined $x;
            $x =~ s/\r$//;
            $x =~ s/^\s+|\s+$//g;
            next if $x eq '';
            if ($x =~ /^1\s+/) { $l1 = $x; last; }
            $name = $x if $x !~ /^[12]\s+/;
        }
        next unless defined $l1;

        my $l2;
        while ($i < @lines) {
            my $x = $lines[$i++];
            next unless defined $x;
            $x =~ s/\r$//;
            $x =~ s/^\s+|\s+$//g;
            next if $x eq '';
            if ($x =~ /^2\s+/) { $l2 = $x; last; }
            last if $x !~ /^[12]\s+/;
        }
        next unless defined $l2;

        push @blocks, [$name, $l1, $l2];
    }

    return @blocks;
}

# ----------------------------
# Load authoritative ESATS1
# ----------------------------

sub load_esats1_blocks {
    my ($path) = @_;
    open my $fh, "<", $path
        or die "Cannot open ESATS1 snapshot $path: $!";

    my @ordered;
    my %snap_by_norad;

    while (1) {
        my $row = <$fh>;
        last unless defined $row;

        chomp($row);

        my ($name, $norad);
        if ($row ne 'Moon') {
            next if $row =~ /^#.*/;
            ($name, $norad) = $row =~ /^([^ ]+)\s+(\d+)/;
            $norad = undef unless defined $norad && $norad =~ /^\d+$/;
        }

        push @ordered, [$name, $norad];
        $snap_by_norad{$norad} = [$name] if defined $norad;
    }

    close $fh;
    return (\@ordered, \%snap_by_norad);
}

# ----------------------------
# Main
# ----------------------------

# Ensure local TLE cache exists
-f $TLE_FILE
    or die "TLE cache not found: $TLE_FILE\nRun fetch_tles.sh first.\n";

# Slurp TLE cache
open my $tfh, "<", $TLE_FILE
    or die "Cannot open TLE cache $TLE_FILE: $!";
my $content = do { local $/; <$tfh> };
close $tfh;

# Parse into NORAD → [l1,l2]
my %live;
for my $blk (parse_tle_blocks($content)) {
    my ($feed_name, $l1, $l2) = @$blk;
    my ($norad) = $l1 =~ /^1\s+(\d+)[A-Z]/;
    next unless defined $norad && $norad =~ /^\d+$/;
    $live{$norad} ||= [$feed_name, $l1, $l2];
}

# Load authoritative membership + order
-f $ESATS1
    or die "Authoritative ESATS snapshot missing: $ESATS1\n";

my ($ordered_ref, $snap_by_norad_ref) =
    load_esats1_blocks($ESATS1);

# Write output
open my $out, ">", $OUT
    or die "Cannot write $OUT: $!";

my $count = 0;

for my $blk (@{$ordered_ref}) {
    my ($name, $norad) = @$blk;

    if (defined $norad && exists $live{$norad}) {
        my ($feed_name, $l1, $l2) = @{$live{$norad}};
        print $out "$name\n$l1\n$l2\n";
    } else {
        # MORE WORK: if its missing the data is old. If
        # it's the Moon we need to calculate it or the
        # data is old. Print to stdout for logging
        print "Not found: $name (NORAD ID: $norad)\n";
    }

    $count++;
}

close $out;

print "Generated $OUT with $count blocks from local TLE cache\n";
exit 0;
