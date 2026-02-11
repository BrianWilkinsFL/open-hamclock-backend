#!/usr/bin/env perl
use strict;
use warnings;

use LWP::UserAgent;
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Temp qw(tempfile);
use File::Copy qw(copy);
use File::Copy qw(move);
use Time::Piece;
use Time::Seconds;

my $URL   = 'https://services.swpc.noaa.gov/text/daily-solar-indices.txt';
my $OUT   = '/opt/hamclock-backend/htdocs/ham/HamClock/ssn/ssn-31.txt';
my $CACHE = '/opt/hamclock-backend/data/ssn-cache.txt';

my $TMPDIR = '/opt/hamclock-backend/tmp';

# Ensure TMPDIR exists
if (!-d $TMPDIR) {
    make_path($TMPDIR, { mode => 0755 })
      or die "ERROR: failed to create $TMPDIR: $!\n";
}
die "ERROR: TMPDIR not writable: $TMPDIR\n" unless -w $TMPDIR;

# Ensure output directory exists
my $out_dir = dirname($OUT);
if (!-d $out_dir) {
    make_path($out_dir, { mode => 0755 })
      or die "ERROR: failed to create $out_dir: $!\n";
}
die "ERROR: output dir not writable: $out_dir\n" unless -w $out_dir;

my $ua = LWP::UserAgent->new(
    timeout => 15,
    agent   => 'hamclock-ssn-noaa/1.2',
);

# Load existing data (prefer cache; fall back to ssn-31)
my %by_date;
for my $src ($CACHE, $OUT) {
    next unless -f $src;
    open my $in, '<', $src or die "ERROR: cannot read $src: $!\n";
    while (my $line = <$in>) {
        chomp $line;
        if ($line =~ /^(\d{4}\s+\d{2}\s+\d{2})\s+(\d+)/) {
            $by_date{$1} = $2;
        }
    }
    close $in or die "ERROR: close($src) failed: $!\n";
    last if $src eq $CACHE;    # if cache exists and was read, don't also read OUT
}

# Fetch NOAA data (last ~30 days) and merge into cache
my $res = $ua->get($URL);
die "ERROR: failed to fetch NOAA data: " . $res->status_line . "\n"
    unless $res->is_success;

my $parsed = 0;
for my $line (split /\n/, $res->decoded_content) {
    # Expected data rows look like:
    # YYYY MM DD <flux> <sunspot> ...
    if ($line =~ /^\s*(\d{4})\s+(\d{2})\s+(\d{2})\s+\d+\s+(\d+)/) {
        my ($y, $m, $d, $ssn) = ($1, $2, $3, $4);
        my $date = sprintf("%04d %02d %02d", $y, $m, $d);
        $by_date{$date} = $ssn;
        $parsed++;
    }
}
die "ERROR: NOAA parse failed (0 rows)\n" if $parsed == 0;

# Persist an ever-growing cache so we always have >30 days available
{
    my @all = sort keys %by_date;

    my ($ctfh, $ctpath) = tempfile('ssn-cache_XXXXXX', DIR => $TMPDIR, UNLINK => 0);
    for my $d (@all) {
        print {$ctfh} "$d $by_date{$d}\n";
    }
    close $ctfh or die "ERROR: close(cache-temp) failed: $!\n";

    my ($cofh, $copath) = tempfile('ssn-cache_XXXXXX', DIR => $out_dir, UNLINK => 0);
    close $cofh or die "ERROR: close(cache-out-temp-handle) failed: $!\n";
    copy($ctpath, $copath) or die "ERROR: copy($ctpath -> $copath) failed: $!\n";
    move($copath, $CACHE) or die "ERROR: move($copath -> $CACHE) failed: $!\n";

    unlink $ctpath;
}

# Build an exact 31-day window ending at the most recent known date
my @sorted = sort keys %by_date;
die "ERROR: no dates available after merge\n" unless @sorted;

my $latest_str = $sorted[-1];    # "YYYY MM DD"
my $latest_tp  = Time::Piece->strptime($latest_str, "%Y %m %d");

my @dates;
for my $i (reverse 0..30) {      # 31 calendar days
    my $tp = $latest_tp - ($i * ONE_DAY);
    push @dates, $tp->strftime("%Y %m %d");
}

# Backfill any missing dates in the 31-day window.
# If we are bootstrapping and don't have older data yet, repeat the earliest known value.
my $earliest_ssn = $by_date{$sorted[0]};
my $last_known;

for my $d (@dates) {
    if (exists $by_date{$d}) {
        $last_known = $by_date{$d};
    } else {
        $by_date{$d} = defined($last_known) ? $last_known : $earliest_ssn;
    }
}

# Step 1: write ssn-31 content to a temp file in TMPDIR
my ($tfh, $tpath) = tempfile('ssn-31_XXXXXX', DIR => $TMPDIR, UNLINK => 0);
for my $d (@dates) {
    print {$tfh} "$d $by_date{$d}\n";
}
close $tfh or die "ERROR: close(temp) failed: $!\n";

# Step 2: copy into output dir as a sibling temp file, then move atomically
my ($ofh, $opath) = tempfile('ssn-31_XXXXXX', DIR => $out_dir, UNLINK => 0);
close $ofh or die "ERROR: close(out-temp-handle) failed: $!\n";  # will copy over it

copy($tpath, $opath) or die "ERROR: copy($tpath -> $opath) failed: $!\n";
move($opath, $OUT) or die "ERROR: move($opath -> $OUT) failed: $!\n";

# Best-effort cleanup of the staging temp file in TMPDIR
unlink $tpath;

exit 0;

