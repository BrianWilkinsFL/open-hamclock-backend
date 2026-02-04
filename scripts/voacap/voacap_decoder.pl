#!/usr/bin/perl
use strict;
use warnings;

# ---------------- CONFIG ----------------
my $voacap_out = "/var/www/itshfbc/run/voacapx.out";
my $UTC        = 0;
my $META       = "100W,CW,TOA>3,SP,S=97";

# S= needs to be pulled from a daily sunspot number file
# it is hard coded right now

# ---------------- READ FILE ----------------
open my $fh, "<", $voacap_out
    or die "Cannot open $voacap_out: $!";

my @lines = <$fh>;
close $fh;

# ---------------- EXTRACT ALL REL ROWS ----------------
my @rels;

for my $line (@lines) {

    next unless $line =~ /\bREL\s*$/;

    # Extract numeric tokens only
    my @nums = grep { /^[0-9.]+$/ } split /\s+/, $line;

    # VOACAP REL rows must have at least 9 values
    next unless @nums >= 9;

    push @rels, [ @nums[0..8] ];
}

# ---------------- SANITY CHECK ----------------
die "Expected 24 REL rows, found " . scalar(@rels) . "\n"
    unless @rels == 24;

# ---------------- MAP HOURS ----------------
# VOACAP outputs hours 1..23, then 0 last
my %hourly;
for my $i (0..22) {
    $hourly{$i+1} = $rels[$i];
}
$hourly{0} = $rels[23];

# ---------------- EMIT HAMCLOCK FORMAT ----------------

# Summary line = UTC hour
print join(",", @{ $hourly{$UTC} }), "\n";

# Metadata line
print "$META\n";

# Hourly rows (UTC rotated to bottom)
for my $h ((($UTC + 1) % 24) .. 23, 0 .. $UTC) {
    print "$h ", join(",", @{ $hourly{$h} }), "\n";
}

