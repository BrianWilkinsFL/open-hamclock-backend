#!/usr/bin/perl
use strict;
use warnings;
use CGI qw(:standard);

# ---------------------------------------------------------------------------
# fetchBandConditions.pl — local drop-in replacement for CSI's endpoint.
# Delegates to voacap_bandconditions.py and returns identical output.
# ---------------------------------------------------------------------------

my $PYTHON  = '/opt/hamclock-backend/venv/bin/python3';
my $SCRIPT  = '/opt/hamclock-backend/scripts/voacap_bandconditions.py';
my $CACHE_DIR = '/opt/hamclock-backend/tmp/voacap-cache';
my $CACHE_TTL = 300;   # seconds; set 0 to disable

# ---------------------------------------------------------------------------
# Parse query string parameters
# ---------------------------------------------------------------------------
my $q = CGI->new;

my $year  = $q->param('YEAR')  || '';
my $month = $q->param('MONTH') || '';
my $utc   = $q->param('UTC')   || '';
my $txlat = $q->param('TXLAT') || '';
my $txlng = $q->param('TXLNG') || '';
my $rxlat = $q->param('RXLAT') || '';
my $rxlng = $q->param('RXLNG') || '';
my $path  = $q->param('PATH')  // '0';
my $pow   = $q->param('POW')   // '100';
my $mode  = $q->param('MODE')  // '19';
my $toa   = $q->param('TOA')   // '3.0';
my $ssn   = $q->param('SSN')   || '';

# ---------------------------------------------------------------------------
# Validate required parameters
# ---------------------------------------------------------------------------
my @missing;
push @missing, 'YEAR'  unless $year  =~ /^\d{4}$/;
push @missing, 'MONTH' unless $month =~ /^\d{1,2}$/ && $month >= 1 && $month <= 12;
push @missing, 'UTC'   unless $utc   =~ /^\d{1,2}$/ && $utc   >= 0 && $utc   <= 23;
push @missing, 'TXLAT' unless $txlat =~ /^-?\d+(\.\d+)?$/;
push @missing, 'TXLNG' unless $txlng =~ /^-?\d+(\.\d+)?$/;
push @missing, 'RXLAT' unless $rxlat =~ /^-?\d+(\.\d+)?$/;
push @missing, 'RXLNG' unless $rxlng =~ /^-?\d+(\.\d+)?$/;

if (@missing) {
    print $q->header('text/plain', '400 Bad Request');
    print "Missing or invalid parameters: " . join(', ', @missing) . "\n";
    exit 1;
}

# Sanitize numerics — prevent shell injection
for ($year, $month, $utc, $txlat, $txlng, $rxlat, $rxlng,
     $path, $pow, $mode, $toa, $ssn) {
    s/[^0-9.\-]//g;
}

# Read SSN from local file
if (!$ssn || $ssn !~ /^\d+(\.\d+)?$/) {
    my $ssn_dir  = '/opt/hamclock-backend/htdocs/ham/HamClock/ssn';
    my ($ssn_file) = glob("$ssn_dir/ssn-*.txt");
    my @t     = gmtime(time());
    my $today = sprintf("%04d %02d %02d", $t[5]+1900, $t[4]+1, $t[3]);
    $ssn = 42;  # fallback
    if ($ssn_file && open(my $fh, '<', $ssn_file)) {
        my $last = 39;
        while (<$fh>) {
            if (/^(\d{4})\s+(\d{2})\s+(\d{2})\s+(\d+)/) {
                my $date = "$1 $2 $3";
                $last = $4;
                $ssn  = $4 if $date eq $today;
            }
        }
        $ssn = $last if $ssn == 42;  # today not in file yet — use most recent
    }
    $ssn = 0 if $ssn < 0;  # floor to avoid degenerate predictions
}

# ---------------------------------------------------------------------------
# Build command (use list form to avoid shell injection)
# ---------------------------------------------------------------------------
my @cmd = (
    $PYTHON, $SCRIPT,
    '--year',   $year,
    '--month',  $month,
    '--utc',    $utc,
    '--txlat',  $txlat,
    '--txlng',  $txlng,
    '--rxlat',  $rxlat,
    '--rxlng',  $rxlng,
    '--path',   $path,
    '--pow',    $pow,
    '--mode',   $mode,
    '--toa',    $toa,
    '--ssn',    $ssn,
    '--cache-dir', $CACHE_DIR,
    '--cache-ttl', $CACHE_TTL,
);


# ---------------------------------------------------------------------------
# Run and capture output
# ---------------------------------------------------------------------------
my $output = '';
my $errors = '';

{
    local $/;
    open(my $fh, '-|', @cmd) or do {
        print $q->header('text/plain', '500 Internal Server Error');
        print "Failed to execute prediction script: $!\n";
        exit 1;
    };
    $output = <$fh>;
    close $fh;
}

my $exit_code = $? >> 8;

if ($exit_code != 0 || !defined $output || $output eq '') {
    print $q->header('text/plain', '500 Internal Server Error');
    print "Prediction script returned no output (exit $exit_code)\n";
    exit 1;
}

# ---------------------------------------------------------------------------
# Return result — same content-type as CSI's server
# ---------------------------------------------------------------------------
print $q->header('text/plain');
print $output;

