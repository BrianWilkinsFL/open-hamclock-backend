#!/usr/bin/env perl
use strict;
use warnings;
use CGI qw(:standard);
use POSIX qw(strftime);

# fetchBandConditions.pl
# CGI wrapper for band_service.py

my $PY      = $ENV{PYTHON3} || "python3";
my $SCRIPT  = "/opt/hamclock-backend/htdocs/ham/HamClock/band_service.py";

# ---- helpers ----
sub is_int {
    my ($v) = @_;
    return defined($v) && $v =~ /\A-?\d+\z/;
}
sub is_num {
    my ($v) = @_;
    return defined($v) && $v =~ /\A-?\d+(?:\.\d+)?\z/;
}
sub clamp {
    my ($v, $lo, $hi) = @_;
    return $lo if $v < $lo;
    return $hi if $v > $hi;
    return $v;
}
sub bad_request {
    my ($msg) = @_;
    print header(
        -type   => 'text/plain',
        -status => '400 Bad Request',
        -charset => 'UTF-8'
    );
    print "ERROR: $msg\n";
    exit 0;
}

# ---- parse query ----
my $q = CGI->new;

# Required-ish parameters (HamClock will send these)
my $YEAR  = $q->param('YEAR');
my $MONTH = $q->param('MONTH');
my $RXLAT = $q->param('RXLAT');
my $RXLNG = $q->param('RXLNG');
my $TXLAT = $q->param('TXLAT');
my $TXLNG = $q->param('TXLNG');
my $UTC   = $q->param('UTC');
my $PATH  = $q->param('PATH');
my $POW   = $q->param('POW');
my $MODE  = $q->param('MODE');
my $TOA   = $q->param('TOA');

# ---- validate/sanitize ----
bad_request("Missing YEAR")  unless defined $YEAR  && length $YEAR;
bad_request("Missing MONTH") unless defined $MONTH && length $MONTH;
bad_request("Missing RXLAT") unless defined $RXLAT && length $RXLAT;
bad_request("Missing RXLNG") unless defined $RXLNG && length $RXLNG;
bad_request("Missing TXLAT") unless defined $TXLAT && length $TXLAT;
bad_request("Missing TXLNG") unless defined $TXLNG && length $TXLNG;
bad_request("Missing UTC")   unless defined $UTC   && length $UTC;
bad_request("Missing PATH")  unless defined $PATH  && length $PATH;
bad_request("Missing POW")   unless defined $POW   && length $POW;
bad_request("Missing MODE")  unless defined $MODE  && length $MODE;
bad_request("Missing TOA")   unless defined $TOA   && length $TOA;

bad_request("YEAR must be integer")  unless is_int($YEAR);
bad_request("MONTH must be integer") unless is_int($MONTH);
bad_request("UTC must be integer")   unless is_int($UTC);
bad_request("PATH must be integer")  unless is_int($PATH);
bad_request("POW must be integer")   unless is_int($POW);
bad_request("MODE must be integer")  unless is_int($MODE);

bad_request("RXLAT must be numeric") unless is_num($RXLAT);
bad_request("RXLNG must be numeric") unless is_num($RXLNG);
bad_request("TXLAT must be numeric") unless is_num($TXLAT);
bad_request("TXLNG must be numeric") unless is_num($TXLNG);
bad_request("TOA must be numeric")   unless is_num($TOA);

# Clamp to sane ranges (prevents weirdness; keeps inputs reasonable)
$MONTH = clamp($MONTH, 1, 12);
$UTC   = clamp($UTC,   0, 23);
$RXLAT = clamp($RXLAT, -90,  90);
$TXLAT = clamp($TXLAT, -90,  90);
$RXLNG = clamp($RXLNG, -180, 180);
$TXLNG = clamp($TXLNG, -180, 180);

# ---- build command (NO shell) ----
my @cmd = (
    $PY, $SCRIPT,
    "--YEAR",  $YEAR,
    "--MONTH", $MONTH,
    "--RXLAT", sprintf("%.3f", $RXLAT),
    "--RXLNG", sprintf("%.3f", $RXLNG),
    "--TXLAT", sprintf("%.3f", $TXLAT),
    "--TXLNG", sprintf("%.3f", $TXLNG),
    "--UTC",   $UTC,
    "--PATH",  $PATH,
    "--POW",   $POW,
    "--MODE",  $MODE,
    "--TOA",   $TOA,
);

# ---- run ----
# band_service.py is expected to print the exact HamClock-compatible response.
# We forward stdout as-is. On error, return 500 with stderr.
my $output = '';
my $err = '';

# Capture combined output safely without invoking a shell.
{
    # localize PATH just in case (optional)
    local $ENV{PATH} = $ENV{PATH} || "/usr/bin:/bin";

    # Open a pipe from the command (list form => no shell injection)
    open(my $fh, "-|", @cmd) or do {
        print header(-type => 'text/plain', -status => '500 Internal Server Error', -charset => 'UTF-8');
        print "ERROR: failed to exec band_service.py: $!\n";
        exit 0;
    };

    local $/;
    $output = <$fh> // '';
    close($fh);

    # close() exit status
    if ($? != 0) {
        my $rc = ($? >> 8);
        print header(-type => 'text/plain', -status => '500 Internal Server Error', -charset => 'UTF-8');
        print "ERROR: band_service.py exited with rc=$rc\n";
        print $output if length $output;
        exit 0;
    }
}

# ---- respond ----
print header(-type => 'text/plain', -status => '200 OK', -charset => 'UTF-8');
print $output;

exit 0;

