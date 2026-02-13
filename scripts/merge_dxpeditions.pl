#!/usr/bin/env perl
use strict;
use warnings;
use File::Copy qw(move);

my $DXNEWS = '/opt/hamclock-backend/cache/dxnews.tmp';
my $NG3K   = '/opt/hamclock-backend/cache/ng3k.tmp';
my $TMP   = '/opt/hamclock-backend/cache/dxpeditions.tmp';
my $OUT    = '/opt/hamclock-backend/htdocs/ham/HamClock/dxpeds/dxpeditions.txt';

my %dx;

sub ingest {
    my ($file, $src) = @_;
    open my $fh, '<', $file or return;

    while (<$fh>) {
        chomp;
        next unless /^\d+,\d+,/;

        my ($s,$e,$loc,$call,$url) = split /,/, $_, 5;
        next unless $call;

        my $key = join('|', $call, $s, $e);

        if (!exists $dx{$key}) {
            $dx{$key} = {
                s    => $s,
                e    => $e,
                loc  => $loc,
                call => $call,
                url  => $url,
                src  => $src,
            };
        }
        else {
            # Prefer DxNews URL
            if ($src eq 'dxnews') {
                $dx{$key}->{url} = $url;
                $dx{$key}->{src} = 'dxnews';
            }

            # Prefer shorter non-empty location
            if ($loc && (!$dx{$key}->{loc} ||
                length($loc) < length($dx{$key}->{loc}))) {
                $dx{$key}->{loc} = $loc;
            }
        }
    }
    close $fh;
}

# ------------------------------------------------------------
# Ingest sources
# ------------------------------------------------------------
ingest($NG3K,   'ng3k');
ingest($DXNEWS, 'dxnews');

# ------------------------------------------------------------
# Write final file atomically
# ------------------------------------------------------------
open my $out, '>', $TMP or die "cannot write $TMP\n";

print $out "2\n";
print $out "DXNews\n";
print $out "https://dxnews.com\n";
print $out "NG3K\n";
print $out "https://www.ng3k.com/Misc/adxo.html\n";

for my $k (sort {
        $dx{$a}->{s} <=> $dx{$b}->{s} ||
        $dx{$a}->{call} cmp $dx{$b}->{call}
    } keys %dx) {

    my $r = $dx{$k};
    printf $out "%d,%d,%s,%s,%s\n",
        $r->{s},
        $r->{e},
        $r->{loc},
        $r->{call},
        $r->{url};
}

close $out;
move $TMP, $OUT or die "move failed\n";

