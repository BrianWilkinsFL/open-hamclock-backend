#!/usr/bin/perl
use strict;
use warnings;
use CGI;
use LWP::UserAgent;
use XML::LibXML;
use File::Path qw(make_path);
use Digest::MD5 qw(md5_hex);

# ---------------- Configuration ----------------

my $CACHE_DIR = "/opt/hamclock-backend/tmp/psk-cache";
my $CACHE_TTL = 300;    # 5 minutes

make_path($CACHE_DIR);

# ---------------- CGI Setup ----------------

my $q = CGI->new;
my $ofgrid = uc($q->param('ofgrid') // '');
my $maxage = $q->param('maxage') // 900;

my $ip = $ENV{HTTP_X_FORWARDED_FOR} || $ENV{REMOTE_ADDR} || "unknown";

# Always emit header FIRST
print $q->header(
    -type => 'text/plain; charset=ISO-8859-1'
);

# Log client IP to stderr (lighttpd error.log)
#print STDERR "PSK request from $ip grid=$ofgrid\n";

# Basic validation
if (!$ofgrid) {
    print "Error: ofgrid parameter is required.\n";
    exit;
}

# ---------------- Cache Handling ----------------

my $cache_key  = md5_hex("$ofgrid:$maxage");
my $cache_file = "$CACHE_DIR/$cache_key.txt";

if (-f $cache_file) {
    my $age = time() - (stat($cache_file))[9];
    if ($age < $CACHE_TTL) {
#       print STDERR "PSK CACHE HIT $ofgrid\n";
        open my $fh, "<", $cache_file or die;
        print while <$fh>;
        close $fh;
        exit;
    }
}

#print STDERR "PSK FETCH $ofgrid\n";

# ---------------- Build PSKReporter URL ----------------

my $flowStartSeconds = $maxage * -1;

my $url = "https://pskreporter.info/cgi-bin/pskquery5.pl?" .
          "noactive=1" .
          "&nolocator=1" .
          "&statistics=1" .
          "&flowStartSeconds=$flowStartSeconds" .
          "&modify=grid" .
          "&senderCallsign=$ofgrid";

# ---------------- HTTP Client ----------------

my $ua = LWP::UserAgent->new(
    agent   => 'HamClock-Backend/1.0 (BrianWilkins)',
    timeout => 20,
);

my $response = $ua->get($url);

if (!$response->is_success) {
    print STDERR "PSK HTTP ".$response->status_line."\n";
    exit;
}

# ---------------- Parse XML ----------------

my $xml_content = $response->decoded_content;

my $parser = XML::LibXML->new();
my $xml;

eval { $xml = $parser->load_xml(string => $xml_content); };
if ($@) {
    print STDERR "PSK XML parse failure\n";
    exit;
}

my $now = time();
my @lines;

for my $node ($xml->findnodes('//receptionReport')) {

    my $t = $node->getAttribute('flowStartSeconds') || next;
    next if ($now - $t) > $maxage;

    my $s_grid = uc($node->getAttribute('senderLocator')   // '');
    my $r_grid = uc($node->getAttribute('receiverLocator') // '');

    $s_grid = length($s_grid) >= 6 ? substr($s_grid,0,6) : $s_grid;
    $r_grid = length($r_grid) >= 6 ? substr($r_grid,0,6) : $r_grid;

    push @lines, sprintf "%d,%s,%s,%s,%s,%s,%d,%d\n",
        $t,
        $s_grid,
        ($node->getAttribute('senderCallsign')   // ''),
        $r_grid,
        ($node->getAttribute('receiverCallsign')// ''),
        ($node->getAttribute('mode')            // ''),
        ($node->getAttribute('frequency')       // 0),
        ($node->getAttribute('sNR')             // 0);
}

my $output = join("", @lines);

# ---------------- Atomic Cache Write ----------------

my $tmp = "$cache_file.$$";
open my $fh, ">", $tmp or die;
print $fh $output;
close $fh;
rename $tmp, $cache_file;

# ---------------- Output ----------------

print $output;

exit;

