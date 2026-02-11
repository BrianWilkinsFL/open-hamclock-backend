#!/usr/bin/env perl
use strict;
use warnings;

use LWP::UserAgent;
use JSON qw(decode_json);

# ================= CONFIG =================
my $API_KEY = '<YOUR FREE IPGEO API KEY HERE>';
my $API_URL = 'https://api.ipgeolocation.io/ipgeo';
# ==========================================

# CGI header
print "Content-Type: text/plain\r\n\r\n";

# Determine caller IP (trust only REMOTE_ADDR)
my $client_ip = $ENV{REMOTE_ADDR} // '';
if (!$client_ip) {
    print "ERROR=No client IP\n";
    exit;
}

# HTTP client
my $ua = LWP::UserAgent->new(
    timeout => 5,
    agent   => 'HamClock-Compat/1.0',
    ssl_opts => { verify_hostname => 1 },
);

# Build request
my $url = "$API_URL?apiKey=$API_KEY&ip=$client_ip";

my $resp = $ua->get($url);
if (!$resp->is_success) {
    print "ERROR=Geolocation lookup failed\n";
    exit;
}

# Parse JSON
my $data;
eval {
    $data = decode_json($resp->decoded_content);
};
if ($@ || ref($data) ne 'HASH') {
    print "ERROR=Invalid response\n";
    exit;
}

my $lat = $data->{latitude};
my $lng = $data->{longitude};
my $ip  = $data->{ip};

if (!defined $lat || !defined $lng) {
    print "ERROR=Incomplete geolocation data\n";
    exit;
}

# Emit HamClock-compatible output
printf "LAT=%.5f\n", $lat;
printf "LNG=%.5f\n", $lng;
print  "IP=$ip\n";
print  "CREDIT=ipgeolocation.io\n";

