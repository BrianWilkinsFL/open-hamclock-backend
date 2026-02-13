#!/usr/bin/env perl
use strict;
use warnings;

use LWP::UserAgent;
use Time::Local;

my $INDEX = 'https://dxnews.com/dxpeditions/';
my $OUT   = '/opt/hamclock-backend/cache/dxnews.tmp';

my %mon = (
    jan=>0,feb=>1,mar=>2,apr=>3,may=>4,jun=>5,
    jul=>6,aug=>7,sep=>8,oct=>9,nov=>10,dec=>11
);

my $ua = LWP::UserAgent->new(
    timeout => 20,
    agent   => 'HamClock-DxNews/1.2',
);

# ------------------------------------------------------------
# Fetch expedition index
# ------------------------------------------------------------
my $res = $ua->get($INDEX);
die "DxNews index fetch failed\n" unless $res->is_success;

my $html = $res->decoded_content;

my %urls;
while ($html =~ m{https://dxnews\.com/[a-z0-9_]+/}gi) {
    $urls{lc $&} = 1;
}

open my $out, '>', $OUT or die "cannot write $OUT\n";

# ------------------------------------------------------------
# Process expedition pages
# ------------------------------------------------------------
for my $url (sort keys %urls) {

    my $r = $ua->get($url);
    next unless $r->is_success;

    my $p = $r->decoded_content;

    # -------- CALLSIGN --------
    my $call = '';
    if ($p =~ m{<h1[^>]*>([^<]+)</h1>}i) {
        ($call) = $1 =~ /\b([A-Z0-9\/]{3,})\b/;
    }
    next unless $call;

    # Reject org/news items
    next if $call =~ /^(RSGB|ARRL|IOTA)$/;

    # -------- DATE RANGE --------
    my ($sm,$sd,$em,$ed,$yr);
	if ($p =~ m{
		(\d{1,2})                  # $1: Start Day
		(?:\s+([A-Za-z]+))?        # $2: Optional Start Month
		\s*[-–]\s*                 # Divider (hyphen or en-dash)
		(\d{1,2})\s+               # $3: End Day
		([A-Za-z]+)\s+             # $4: End Month
		(\d{4})                    # $5: Year
	}x) {
        ($sd,$sm,$ed,$em,$yr) = ($1,$2,$3,$4,$5);
        $sm //= $em;
    }
    elsif ($p =~ m{
		([A-Za-z]+)\s+             # $1: Start Month
		(\d{1,2})                  # $2: Start Day
		\s*[-–]\s*                 # Divider (hyphen or en-dash)
		(?:\s+([A-Za-z]+))?        # $3: Optional End Month
		(\d{1,2})\s+               # $4: End Day
		(\d{4})                    # $5: Year
    }x) {
        ($sm,$sd,$em,$ed,$yr) = ($1,$2,$3,$4,$5);
        $em //= $sm;
    }
    else {
        next;
    }

    $sm = lc substr($sm,0,3);
    $em = lc substr($em,0,3);
    next unless exists $mon{$sm} && exists $mon{$em};

    my $start = timegm(0,0,0,$sd,$mon{$sm},$yr);
    my $end   = timegm(59,59,23,$ed,$mon{$em},$yr);
    $end += 365*86400 if $end < $start;

    # -------- LOCATION --------
    my $loc = 'Unknown';

    if ($p =~ m{<h1[^>]+([^<]+)</h1>}i) {
        my $t = $1;

        # Drop DXpedition / DXNews suffixes
        $t =~ s/\s+-\s+DX.*$//i;
        $t =~ s/\s+DXpedition.*$//i;

        # Remove callsign
        $t =~ s/\b\Q$call\E\b//g;

        # Remove leading separators
        $t =~ s/^[\s\-–:]+//;

        # Trim
        $t =~ s/^\s+|\s+$//g;

        # Reject news pages
        next if $t =~ /\bIOTA\b/i;

        $loc = $t if length($t) && length($t) <= 40;
    }

    printf $out "%d,%d,%s,%s,%s\n",
        $start,
        $end,
        $loc,
        $call,
        $url;
}

close $out;

