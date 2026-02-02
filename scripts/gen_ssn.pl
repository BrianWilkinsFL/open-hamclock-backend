#!/usr/bin/env perl
use strict;
use warnings;
use LWP::UserAgent;

my $URL = 'https://services.swpc.noaa.gov/text/daily-solar-indices.txt';
my $OUT = '/opt/hamclock-backend/htdocs/ham/HamClock/ssn/ssn-31.txt';

my $ua = LWP::UserAgent->new(
    timeout => 15,
    agent   => 'hamclock-ssn-noaa/1.1'
);

# Load existing data (if any)
my %by_date;
if (-f $OUT) {
    open my $in, '<', $OUT or die "ERROR: cannot read $OUT\n";
    while (<$in>) {
        chomp;
        if (/^(\d{4}\s+\d{2}\s+\d{2})\s+(\d+)/) {
            $by_date{$1} = $2;
        }
    }
    close $in;
}

# Fetch NOAA data
my $res = $ua->get($URL);
die "ERROR: failed to fetch NOAA data\n"
    unless $res->is_success;

my $parsed = 0;

for my $line (split /\n/, $res->decoded_content) {
    # YYYY MM DD <flux> <sunspot> ...
    if ($line =~ /^\s*(\d{4})\s+(\d{2})\s+(\d{2})\s+\d+\s+(\d+)/) {
        my ($y,$m,$d,$ssn) = ($1,$2,$3,$4);
        my $date = sprintf("%04d %02d %02d", $y,$m,$d);
        $by_date{$date} = $ssn;
        $parsed++;
    }
}

die "ERROR: NOAA parse failed (0 rows)\n"
    if $parsed == 0;

# Sort by date and keep last 31
my @dates = sort keys %by_date;
@dates = @dates[-31 .. -1] if @dates > 31;

# Atomic write
my $tmp = "$OUT.tmp";
open my $fh, '>', $tmp or die "ERROR: cannot write temp file\n";
for my $d (@dates) {
    print $fh "$d $by_date{$d}\n";
}
close $fh;
rename $tmp, $OUT or die "ERROR: rename failed\n";

exit 0;

