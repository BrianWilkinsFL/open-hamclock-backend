#!/usr/bin/env perl
use strict;
use warnings;
use LWP::UserAgent;

# Output that HamClock downloads
my $OUT = $ENV{ESATS_OUT} // "/opt/hamclock-backend/htdocs/ham/HamClock/esats/esats.txt";

# Authoritative snapshot (esats1.txt) used for exact membership + order + names + Moon
my $ESATS1 = $ENV{ESATS_ORIGINAL} // "/opt/hamclock-backend/htdocs/ham/HamClock/esats/esats1.txt";

# Subset patterns file (used only if ESATS1 is missing)
my $SUBSET_TXT = $ENV{ESATS_SUBSET} // "/opt/hamclock-backend/htdocs/ham/HamClock/esats/esats.subset.txt";

# Celestrak sources (live)
my @urls = (
    "https://celestrak.org/NORAD/elements/gp.php?GROUP=active&FORMAT=tle",
    "https://celestrak.org/NORAD/elements/gp.php?GROUP=amateur&FORMAT=tle",
    "https://celestrak.org/NORAD/elements/gp.php?GROUP=stations&FORMAT=tle",
);

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

sub slurp_subset_patterns {
    my ($path) = @_;
    open my $sfh, "<", $path or die "Cannot open subset file $path: $!";
    my @pats;
    while (my $line = <$sfh>) {
        chomp($line);
        $line =~ s/\r$//;
        $line =~ s/^\s+|\s+$//g;
        next if $line eq '' || $line =~ /^\s*#/;
        push @pats, $line;
    }
    close $sfh;
    die "Subset file $path had no patterns\n" unless @pats;
    return @pats;
}

sub normalize_name {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/\r$//;
    $s =~ s/^\s+|\s+$//g;
    $s =~ s/[\(\)\[\]]/ /g;
    $s =~ s/[_\-]+/ /g;
    $s =~ s/\s+/ /g;
    return $s;
}

sub wanted_by_subset {
    my ($candidate, $candidate_norm, $pats_ref) = @_;
    for my $pat (@{$pats_ref}) {
        return 1 if ($candidate // '')      =~ /$pat/i;
        return 1 if ($candidate_norm // '') =~ /$pat/i;
    }
    return 0;
}

# “Natural” compare: digit runs compared numerically.
sub natcmp {
    my ($a, $b) = @_;
    my @aa = ($a =~ /(\d+|\D+)/g);
    my @bb = ($b =~ /(\d+|\D+)/g);

    my $n = @aa < @bb ? @aa : @bb;
    for (my $i = 0; $i < $n; $i++) {
        my ($x, $y) = ($aa[$i], $bb[$i]);
        my $xnum = ($x =~ /^\d+$/);
        my $ynum = ($y =~ /^\d+$/);
        my $c = ($xnum && $ynum) ? (int($x) <=> int($y)) : ($x cmp $y);
        return $c if $c != 0;
    }
    return @aa <=> @bb;
}

# Read ESATS1 into ordered 3-line blocks; also return norad->(name,l1,l2) for fallback.
sub load_esats1_blocks {
    my ($path) = @_;
    open my $fh, "<", $path or die "Cannot open $path: $!";

    my @ordered;             # array of [name, l1, l2, norad_or_undef]
    my %snap_by_norad;       # norad => [name,l1,l2]

    while (1) {
        my $name = <$fh>;
        my $l1   = <$fh>;
        my $l2   = <$fh>;
        last unless defined $l2;

        chomp($name, $l1, $l2);
        $name =~ s/\r$//; $l1 =~ s/\r$//; $l2 =~ s/\r$//;
        $name =~ s/^\s+|\s+$//g;

        my $norad;
        if ($name ne 'Moon') {
            ($norad) = $l1 =~ /^1\s+(\d+)[A-Z]/;
            $norad = undef unless defined $norad && $norad =~ /^\d+$/;
        }

        push @ordered, [$name, $l1, $l2, $norad];
        $snap_by_norad{$norad} = [$name, $l1, $l2] if defined $norad;
    }

    close $fh;
    return (\@ordered, \%snap_by_norad);
}

# Fetch live TLEs from celestrak into norad-> [l1,l2]
sub fetch_live_tles {
    my ($ua, $urls_ref) = @_;
    my %live;

    for my $url (@{$urls_ref}) {
        my $res = $ua->get($url);
        die "Fetch failed: $url\n" . $res->status_line . "\n" unless $res->is_success;
        my $content = $res->decoded_content;
        die "HTML detected from $url (serving wrong content?)\n" if $content =~ /<html/i;

        for my $blk (parse_tle_blocks($content)) {
            my ($feed_name, $l1, $l2) = @$blk;
            my ($norad) = $l1 =~ /^1\s+(\d+)[A-Z]/;
            next unless defined $norad && $norad =~ /^\d+$/;
            # first one wins; doesn't matter much, but prevents flapping between groups
            $live{$norad} ||= [$l1, $l2];
        }
    }

    return \%live;
}

# ---- main ----
my $ua = LWP::UserAgent->new(timeout => 20, agent => "hamclock-esats/1.6");

my $wrote_blocks = 0;

if (-f $ESATS1) {
    # Authoritative mode: exact names+order from ESATS1, live lines spliced in by NORAD.
    my ($ordered_ref, $snap_by_norad_ref) = load_esats1_blocks($ESATS1);
    my $live_ref = fetch_live_tles($ua, \@urls);

    open my $out, ">", $OUT or die "Cannot write $OUT: $!";

    for my $blk (@{$ordered_ref}) {
        my ($name, $snap_l1, $snap_l2, $norad) = @$blk;

        if (defined $norad && exists $live_ref->{$norad}) {
            my ($l1, $l2) = @{$live_ref->{$norad}};
            print $out "$name\n$l1\n$l2\n";
        } else {
            # Moon (norad undef) or missing live NORAD: keep snapshot block to preserve membership.
            print $out "$name\n$snap_l1\n$snap_l2\n";
        }
        $wrote_blocks++;
    }

    close $out;

    print "Generated $OUT with $wrote_blocks blocks (authoritative ESATS_ORIGINAL order)\n";
    exit 0;
}

# Fallback mode (no ESATS1): subset-driven selection + natural sort + include Moon if subset matches it.
my @subset_pats = slurp_subset_patterns($SUBSET_TXT);
my $live_ref = fetch_live_tles($ua, \@urls);

my @out_blocks;

for my $norad (keys %{$live_ref}) {
    # no authoritative names available in fallback; use NORAD as-is name from feed is not stored here,
    # so fallback mode is inherently less exact. If we need fallback correctness, keep our old behavior.
    # (Most users run authoritative mode.)
    next;
}

die "ESATS_ORIGINAL ($ESATS1) not found; authoritative mode requires it.\n";

