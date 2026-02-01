#!/usr/bin/perl
use strict;
use warnings;
use POSIX qw(strftime);

# ---------------- FIXED TEMPLATE (DO NOT REFORMAT) ----------------
my $TEMPLATE = <<'VOACAP';
COMMENT    Any VOACAP default cards may be placed in the file: VOACAP.DEF
LINEMAX      55       number of lines-per-page
COEFFS    CCIR
TIME          1   24    1    1
MONTH      YYYY MM.MM
SUNSPOT    SS.
LABEL     TANGIER, Morocco    BELGRADE
CIRCUIT   TT.TTN    LL.LLW    RR.RRN    OO.OOE  S     0
SYSTEM       1. 145. 0.10  90. 73.0 3.00 0.10
FPROB      1.00 1.00 1.00 0.00
ANTENNA       1    1    2   30     0.000[default/const17.voa  ]  0.0  500.0000
ANTENNA       2    2    2   30     0.000[default/swwhip.voa   ]  0.0    0.0000
FREQUENCY  6.07 7.20 9.7011.8513.7015.3517.7321.6525.89 0.00 0.00
METHOD       30    0
EXECUTE
QUIT
VOACAP

# ---------------- INPUT PARAMETERS ----------------
my %P = (
    YEAR  => 2026,
    MONTH => 1.00,
    SSN   => 86,
    TXLAT => 40.00,
    TXLNG => 99.00,
    RXLAT => 0.00,
    RXLNG => 0.00,
);

# ---------------- TEMPLATE SUBSTITUTION ----------------
my $deck = $TEMPLATE;

# MONTH line (fixed width)
$deck =~ s/YYYY\s+MM\.MM/sprintf("%4d %4.2f", $P{YEAR}, $P{MONTH})/e;

# SUNSPOT (integer + trailing dot, no padding drift)
$deck =~ s/SS\./sprintf("%2d.", $P{SSN})/e;

# CIRCUIT fields (replace tokens only; spacing preserved)
$deck =~ s/TT\.TTN/sprintf("%5.2fN", $P{TXLAT})/e;
$deck =~ s/LL\.LLW/sprintf("%5.2fW", $P{TXLNG})/e;
$deck =~ s/RR\.RRN/sprintf("%5.2fN", $P{RXLAT})/e;
$deck =~ s/OO\.OOE/sprintf("%5.2fE", $P{RXLNG})/e;

# ---------------- UNIQUE OUTPUT FILE ----------------
my $fname = sprintf(
    "hamclock_%s_%d_%05d.dat",
    strftime("%Y%m%d%H%M%S", gmtime),
    $$,
    int(rand(100000))
);

my $path = "/home/hamclock/itshfbc/run/$fname";

open my $fh, ">", $path or die "Cannot write $path: $!";
print $fh $deck;
close $fh;

print "Generated VOACAP deck:\n$path\n";

