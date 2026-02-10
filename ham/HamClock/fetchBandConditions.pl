#!/usr/bin/env perl
use strict;
use warnings;
use Fcntl qw(:DEFAULT);
use File::Spec;

my $VOACAP_DIR = "/opt/hamclock-backend/itshfbc";
my $RUN_DIR    = "/opt/hamclock-backend/itshfbc/run";
my $VOACAPL    = "voacapl";

my $DEFAULT_SSN_I = 107;
my $DEFAULT_NOISE = 153;
my $DEFAULT_TOA   = 3.0;
my $DEFAULT_POW_W = 100.0;
my $DEFAULT_MODE  = 19.0;

my $FREQ_CARD = "FREQUENCY  3.60 5.30 7.10 10.10 14.10 18.10 21.20 24.95 28.40 0.00 0.00\n";

if (!-d $RUN_DIR) {
    print "Content-type: text/plain\r\n\r\n";
    print "ERROR: RUN_DIR does not exist: $RUN_DIR\n";
    exit 0;
}

# Hardening for CGI under lighttpd (PATH/HOME often empty)
$ENV{PATH}   = "/usr/local/bin:/usr/bin:/bin";
$ENV{HOME}   = "/tmp";
$ENV{TMPDIR} = "/tmp";
$ENV{LC_ALL} = "C";
$ENV{LANG}   = "C";

my $VOACAPL = "/usr/local/bin/voacapl";   # change if different

sub url_decode {
    my ($s) = @_;
    $s //= '';
    $s =~ tr/+/ /;
    $s =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    return $s;
}

sub parse_query_string {
    my %p;
    my $qs = $ENV{QUERY_STRING} // '';
    for my $pair (split /&/, $qs) {
        next if $pair eq '';
        my ($k, $v) = split /=/, $pair, 2;
        $k = url_decode($k // '');
        $v = url_decode($v // '');
        $p{$k} = $v;
    }
    return %p;
}

sub clamp_num {
    my ($x, $min, $max, $def) = @_;
    return $def if !defined($x) || $x !~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/;
    $x = 0 + $x;
    $x = $min if defined($min) && $x < $min;
    $x = $max if defined($max) && $x > $max;
    return $x;
}

sub lat_parts_2dp {
    my ($lat) = @_;
    $lat = clamp_num($lat, -90, 90, 0);
    my $hem = ($lat < 0) ? 'S' : 'N';
    $lat = abs($lat);
    return (sprintf("%.2f", $lat), $hem);
}

sub lon_parts_2dp {
    my ($lon) = @_;
    $lon = clamp_num($lon, -180, 180, 0);
    my $hem = ($lon < 0) ? 'W' : 'E';
    $lon = abs($lon);
    return (sprintf("%.2f", $lon), $hem);
}

sub path_letter {
    my ($path) = @_;
    return 'L' if defined($path) && $path =~ /^(?:1|L|LP)$/i;
    return 'S';
}

sub path_label {
    my ($path) = @_;
    return 'LP' if defined($path) && $path =~ /^(?:1|L|LP)$/i;
    return 'SP';
}

sub mode_label {
    my ($mode) = @_;
    return ($mode <= 20.0) ? "CW" : "SSB";
}

sub unique_base_8 {
    my $pid5 = sprintf("%05X", $$ % 0x100000);
    for (1..600) {
        my $r2   = sprintf("%02X", int(rand(0x100)));
        my $base = "B${pid5}${r2}";
        my $dat  = File::Spec->catfile($RUN_DIR, "$base.DAT");
        my $out  = File::Spec->catfile($RUN_DIR, "$base.OUT");
        next if -e $dat || -e $out;
        return $base;
    }
    return;
}

sub safe_write_file {
    my ($path, $content) = @_;
    sysopen(my $fh, $path, O_WRONLY|O_CREAT|O_EXCL, 0644) or return (0, "open($path): $!");
    binmode($fh);
    print {$fh} $content;
    close($fh) or return (0, "close($path): $!");
    return (1, "");
}

sub read_entire_file {
    my ($path) = @_;
    open(my $fh, '<', $path) or return (undef, "open($path): $!");
    binmode($fh);
    local $/ = undef;
    my $data = <$fh>;
    close($fh);
    return ($data, "");
}

sub http_error {
    my ($msg) = @_;
    print "Content-type: text/plain\r\n";
    print "Cache-Control: no-store\r\n\r\n";
    print "ERROR: $msg\n";
    exit 0;
}

sub fmt_row9 {
    my ($arrref) = @_;
    return join(",", map { sprintf("%.2f", $_) } @$arrref[0..8]);
}

sub parse_rel_rows {
    my ($out_text) = @_;
    my @all;
    for my $line (split /\n/, $out_text) {
        next unless $line =~ /\bREL\s*$/;
        my @nums = grep { /^[0-9.]+$/ } split /\s+/, $line;
        next unless @nums >= 9;
        push @all, [ @nums[0..8] ];
    }
    return () if @all < 24;
    return @all[@all-24 .. @all-1];
}

my %q = parse_query_string();

my $year  = int(clamp_num($q{YEAR},  1900, 2100, 2026));
my $month = clamp_num($q{MONTH}, 1, 12, 1);

my $utc   = int(clamp_num($q{UTC}, 0, 23, 0));
my $pchar = path_letter($q{PATH});
my $plab  = path_label($q{PATH});

my $pow_w  = clamp_num($q{POW}, 0.1, 50000, $DEFAULT_POW_W);
my $pow_kw = $pow_w / 1000.0;

my $mode = clamp_num($q{MODE}, 0, 1000, $DEFAULT_MODE);
my $mlab = mode_label($mode);

my $toa  = clamp_num($q{TOA},  0, 90,   $DEFAULT_TOA);

my $ssn_i = defined($q{SSN}) ? int(clamp_num($q{SSN}, 0, 400, $DEFAULT_SSN_I) + 0.5) : $DEFAULT_SSN_I;

http_error("Missing TXLAT/TXLNG/RXLAT/RXLNG")
  if !defined($q{TXLAT}) || !defined($q{TXLNG}) || !defined($q{RXLAT}) || !defined($q{RXLNG});

my ($txlat_v, $txlat_h) = lat_parts_2dp($q{TXLAT});
my ($txlng_v, $txlng_h) = lon_parts_2dp($q{TXLNG});
my ($rxlat_v, $rxlat_h) = lat_parts_2dp($q{RXLAT});
my ($rxlng_v, $rxlng_h) = lon_parts_2dp($q{RXLNG});

my $base = unique_base_8() // http_error("Unable to allocate unique temp filenames");
my $dat_name = "$base.DAT";
my $out_name = "$base.OUT";
my $dat_path = File::Spec->catfile($RUN_DIR, $dat_name);
my $out_path = File::Spec->catfile($RUN_DIR, $out_name);

my $dat = "";
$dat .= "COMMENT    HamClock fetchBandConditions (isotropic ends)\n";
$dat .= "LINEMAX      55       number of lines-per-page\n";
$dat .= "COEFFS    CCIR\n";
$dat .= "TIME          1   24    1    1\n";
$dat .= sprintf("MONTH      %d %.2f\n", $year, $month);
$dat .= sprintf("SUNSPOT    %d.\n", $ssn_i);
$dat .= "LABEL     TX_QTH              RX_QTH\n";

# FIX: robust CIRCUIT formatting so W/E never gets dropped/mis-columned
$dat .= sprintf(
  "CIRCUIT   %5s%1s   %6s%1s    %5s%1s   %6s%1s  %s     0\n",
  $txlat_v, $txlat_h,
  $txlng_v, $txlng_h,
  $rxlat_v, $rxlat_h,
  $rxlng_v, $rxlng_h,
  $pchar
);

$dat .= sprintf("SYSTEM       1. %.0f. %.2f  90. %.1f 3.00 0.10\n",
    $DEFAULT_NOISE, $toa, $mode
);

$dat .= "FPROB      1.00 1.00 1.00 0.00\n";
$dat .= sprintf("ANTENNA       1    1    2   30     0.000[default/ccir.000     ]  0.0    %.4f\n", $pow_kw);
$dat .= "ANTENNA       2    2    2   30     0.000[default/ccir.000     ]  0.0    0.0000\n";
$dat .= $FREQ_CARD;
$dat .= "METHOD       30    0\n";
$dat .= "EXECUTE\n";
$dat .= "QUIT\n";

my ($ok, $err) = safe_write_file($dat_path, $dat);
http_error("Failed to write DAT file: $err") if !$ok;

chdir($RUN_DIR) or do {
    unlink $dat_path;
    http_error("chdir($RUN_DIR) failed: $!");
};

$ENV{LC_ALL} = "C";
$ENV{LANG}   = "C";

my @cmd = ($VOACAPL, "-s", $VOACAP_DIR, $dat_name, $out_name);
system(@cmd);
my $rc = $? >> 8;

if ($rc != 0) {
	#unlink $dat_path;
	#unlink $out_path;
    http_error("voacapl exited rc=$rc; cmd=@cmd; dat=$dat_name out=$out_name");
}

my ($out, $re) = read_entire_file($out_path);
if (!defined $out) {
	#unlink $dat_path;
	#unlink $out_path;
    http_error("voacapl succeeded but OUT not readable: $re");
}

my @rels = parse_rel_rows($out);
if (@rels < 24) {
	#    unlink $dat_path;
	#unlink $out_path;
    http_error("Could not extract 24 REL rows from VOACAP output (found " . scalar(@rels) . ")");
}

my $row_utc = fmt_row9($rels[$utc]);
my $row0    = fmt_row9($rels[0]);

my $toa_txt = ($toa == int($toa)) ? sprintf("%.0f", $toa) : sprintf("%.1f", $toa);
my $header  = sprintf("%dW,%s,TOA>%s,%s,S=%d",
    int($pow_w + 0.5), $mlab, $toa_txt, $plab, $ssn_i
);

print "Content-type: text/plain\r\n";
print "Cache-Control: no-store\r\n\r\n";
print $row_utc, "\n";
print $header,  "\n";
for my $h (1..23) {
    print $h, " ", fmt_row9($rels[$h]), "\n";
}
print "0 ", $row0, "\n";

#unlink $dat_path;
#unlink $out_path;
exit 0;

