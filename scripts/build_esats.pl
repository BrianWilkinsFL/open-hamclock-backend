#!/usr/bin/env perl
use strict;
use warnings;
use LWP::UserAgent;

# Output that HamClock downloads
my $OUT = $ENV{ESATS_OUT} // "/opt/hamclock-backend/htdocs/ham/HamClock/esats/esats.txt";

# Optional authoritative rename map (3-line blocks). If missing, we still work.
my $ESATS1 = $ENV{ESATS_ORIGINAL} // "/opt/hamclock-backend/scripts/esats_original.txt";

# Your subset patterns file (defaults to uploaded location for this chat)
my $SUBSET_TXT = $ENV{ESATS_SUBSET} // "/opt/hamclock-backend/htdocs/ham/HamClock/esats/esats.subset.txt";

# Celestrak sources (you can add/remove, but amateur should be enough for your subset)
my @urls = (
    "https://celestrak.org/NORAD/elements/gp.php?GROUP=amateur&FORMAT=tle",
    # sometimes a few “ham-adjacent” end up elsewhere; safe to include:
    "https://celestrak.org/NORAD/elements/gp.php?GROUP=stations&FORMAT=tle",
);

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

sub load_authoritative_map {
    my ($path) = @_;
    my %norad_to_name;

    return %norad_to_name unless -f $path;

    open my $fh, "<", $path or die "Cannot open $path: $!";
    while (1) {
        my $name = <$fh>;
        my $l1   = <$fh>;
        my $l2   = <$fh>;
        last unless defined $l2;

        chomp($name, $l1, $l2);

        # Accept U/C/S classification (and generally any alpha)
        my ($norad) = $l1 =~ /^1\s+(\d+)[A-Z]/;
        next unless defined $norad && $norad =~ /^\d+$/;

        $name =~ s/\r$//;
        $name =~ s/^\s+|\s+$//g;
        next unless length $name;

        $norad_to_name{$norad} = $name;
    }
    close $fh;

    return %norad_to_name;
}

sub normalize_name {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/\r$//;
    $s =~ s/^\s+|\s+$//g;
    # Remove common punctuation differences for matching
    $s =~ s/[\(\)\[\]]/ /g;
    $s =~ s/[_\-]+/ /g;
    $s =~ s/\s+/ /g;
    return $s;
}

sub wanted_by_subset {
    my ($candidate, $candidate_norm, $pats_ref) = @_;
    for my $pat (@{$pats_ref}) {
        # Treat each subset line as a regex, as indicated by the file header/comment.
        # Match against raw and normalized variants.
        return 1 if ($candidate // '')      =~ /$pat/i;
        return 1 if ($candidate_norm // '') =~ /$pat/i;
    }
    return 0;
}

sub parse_tle_blocks {
    my ($content) = @_;
    my @lines = split /\n/, $content;
    my @blocks;

    # Robust scan:
    #   name line (anything non-empty)
    #   next non-empty line starting with "1 "
    #   next non-empty line starting with "2 "
    my $i = 0;
    while ($i < @lines) {
        my $name = $lines[$i++];
        next unless defined $name;
        $name =~ s/\r$//;
        $name =~ s/^\s+|\s+$//g;
        next if $name eq '';

        # Find line1
        my $l1;
        while ($i < @lines) {
            my $x = $lines[$i++];
            next unless defined $x;
            $x =~ s/\r$//;
            $x =~ s/^\s+|\s+$//g;
            next if $x eq '';
            if ($x =~ /^1\s+/) { $l1 = $x; last; }
            # If we hit another apparent name without seeing line1, reset to treat it as a name
            $name = $x if $x !~ /^[12]\s+/;
        }
        next unless defined $l1;

        # Find line2
        my $l2;
        while ($i < @lines) {
            my $x = $lines[$i++];
            next unless defined $x;
            $x =~ s/\r$//;
            $x =~ s/^\s+|\s+$//g;
            next if $x eq '';
            if ($x =~ /^2\s+/) { $l2 = $x; last; }
            # If the feed is malformed, abandon this block and continue scanning
            last if $x !~ /^[12]\s+/;
        }
        next unless defined $l2;

        push @blocks, [$name, $l1, $l2];
    }

    return @blocks;
}

# ---- main ----

my @subset_pats = slurp_subset_patterns($SUBSET_TXT);
my %norad_to_name = load_authoritative_map($ESATS1);

my $ua = LWP::UserAgent->new(timeout => 20, agent => "hamclock-esats/1.3");

# We will keep only satellites whose NAME matches subset patterns.
# But we’ll also record “misses” for debugging (subset pattern matched no emitted TLE).
my %selected_by_norad;
my %emitted;
my %name_for_norad;

# Pull + parse each feed into TLE blocks
for my $url (@urls) {
    my $res = $ua->get($url);
    die "Fetch failed: $url\n" . $res->status_line . "\n" unless $res->is_success;

    my $content = $res->decoded_content;
    die "HTML detected from $url (serving wrong content?)\n" if $content =~ /<html/i;

    for my $blk (parse_tle_blocks($content)) {
        my ($feed_name, $l1, $l2) = @$blk;

        # Parse NORAD (classification not assumed)
        my ($norad) = $l1 =~ /^1\s+(\d+)[A-Z]/;
        next unless defined $norad && $norad =~ /^\d+$/;

        my $auth_name = $norad_to_name{$norad};
        my $print_name = defined($auth_name) && length($auth_name) ? $auth_name : $feed_name;

        my $cand_raw  = $print_name;
        my $cand_norm = normalize_name($print_name);

        # Subset match decision: check both the printable name and also the raw feed name
        my $feed_norm = normalize_name($feed_name);
        my $want = wanted_by_subset($cand_raw, $cand_norm, \@subset_pats)
               || wanted_by_subset($feed_name, $feed_norm, \@subset_pats);

        next unless $want;

        # De-dupe by NORAD: keep the first seen (usually fine for Celestrak)
        next if $selected_by_norad{$norad}++;

        $name_for_norad{$norad} = $print_name;
        $emitted{$norad} = [$print_name, $l1, $l2];
    }
}

open my $out, ">", $OUT or die "Cannot write $OUT: $!";

# Emit in numeric NORAD order for stability
for my $norad (sort { $a <=> $b } keys %emitted) {
    my ($n, $l1, $l2) = @{$emitted{$norad}};
    $n =~ s/\r$//; $l1 =~ s/\r$//; $l2 =~ s/\r$//;
    $n =~ s/^\s+|\s+$//g;
    next unless length $n;
    print $out "$n\n$l1\n$l2\n";
}

# Append Moon sentinel EXACTLY
print $out <<'MOON';
Moon
1     1U     1A   26032.68547454  .00000000  00000-0  0000000 0  0011
2     1 331.4749 175.8066 0362000 332.1449 342.5152  0.03660000    12
MOON

close $out;

# Optional: warn if some subset patterns appear to have produced zero matches.
# (This is heuristic; patterns can be broad, and matching is name-based.)
# print STDERR "Wrote $OUT with " . scalar(keys %emitted) . " satellites\n";

print "Generated $OUT with " . scalar(keys %emitted) . " satellites from subset patterns\n";

