#!/usr/bin/env perl
use strict;
use warnings;

my $CACHE = '/opt/hamclock-backend/data/solarflux-cache.txt';
my $OUT   = '/opt/hamclock-backend/htdocs/ham/HamClock/solar-flux/solarflux-99.txt';

my @values;

open my $fh, '<', $CACHE or die "Cache missing\n";
while (<$fh>) {
    chomp;
    my (undef, $v) = split;
    next unless defined $v;
    push @values, $v;
}
close $fh;

die "Insufficient cache history\n" unless @values >= 1;

# Ensure at least 90 observed values
if (@values < 90) {
    my $pad = $values[0];
    unshift @values, $pad while @values < 90;
} else {
    @values = splice(@values, -90);
}

my $today = $values[-1];

# Append 9 prediction slots (repeat last observed)
push @values, ($today) x 9;

die "Internal error\n" unless @values == 99;

open my $out, '>', $OUT or die "Write failed\n";
print $out "$_\n" for @values;
close $out;

