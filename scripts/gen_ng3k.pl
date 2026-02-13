#!/usr/bin/env perl
use strict;
use warnings;

use LWP::UserAgent;
use Time::Local;
use File::Copy qw(move);

my $URL = 'https://www.ng3k.com/Misc/adxo.html';
my $OUT = '/opt/hamclock-backend/cache/ng3k.tmp';

my %mon = (
    Jan=>0, Feb=>1, Mar=>2, Apr=>3, May=>4, Jun=>5,
    Jul=>6, Aug=>7, Sep=>8, Oct=>9, Nov=>10, Dec=>11
);

my $ua = LWP::UserAgent->new(timeout => 20);
my $res = $ua->get($URL);
die "Fetch failed\n" unless $res->is_success;

my $html = $res->decoded_content;

my $now     = time();
my $future  = $now + 180 * 86400;   # ~6 months
my @records;

while ($html =~ m{
    <tr\s+class="adxoitem".*?>
    \s*<td\s+class="date">\s*(\d{4})\s+(\w{3})(\d{2})\s*</td>
    \s*<td\s+class="date">\s*(\d{4})\s+(\w{3})(\d{2})\s*</td>
    .*?
    <td\s+class="cty">\s*(.*?)\s*</td>
    .*?
    <td.*?class="call">(?:<span.*?>)?(?:<a.*?>)?([^<]+)(?:<\/a>)?(?:<\/span>)?<\/td>
}gsx) {

    my ($sy,$sm,$sd,$ey,$em,$ed,$loc,$call_html) =
        ($1,$2,$3,$4,$5,$6,$7,$8);

    # Normalize location
    $loc =~ s/&amp;/&/g;
    $loc =~ s/\s+/ /g;
    $loc =~ s/^\s+|\s+$//g;

    # Normalize callsign
    my $call = '';

    # Prefer visible callsign text
    if ($call_html =~ /\b([A-Z0-9\/]{2,})\b/) {
        $call = $1;
    }
    # Fallback: extract from dxwatch link
    elsif ($call_html =~ /dxsd1\.php\?.*?[&?]c=([^"&]+)/) {
        $call = $1;
    }

    $call =~ s/&amp;/&/g;
    $call =~ s/\s+//g;

    # Convert dates to epoch
    next unless exists $mon{$sm} && exists $mon{$em};

    my $start = timegm(0,0,0,$sd,$mon{$sm},$sy);
    my $end   = timegm(59,59,23,$ed,$mon{$em},$ey);

    # Handle year rollover
    $end += 365*86400 if $end < $start;

    # Filter window
    next if $end   < $now;
    next if $start > $future;

    push @records, {
        start => $start,
        end   => $end,
        loc   => $loc,
        call  => $call,
        url   => $URL,
    };
}

# Write output atomically
open my $fh, '>', $OUT or die "write failed\n";

for my $r (sort { $a->{start} <=> $b->{start} } @records) {
    printf $fh "%d,%d,%s,%s,%s\n",
        $r->{start},
        $r->{end},
        $r->{loc},
        $r->{call},
        $r->{url};
}

close $fh;
