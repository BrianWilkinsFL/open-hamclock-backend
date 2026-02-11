#!/usr/bin/perl
use strict;
use warnings;
use LWP::UserAgent;
use JSON;
use URI::Escape;
use CGI; # Standard module for URL parameter handling

# --- INPUT HANDLING ---
my $q = CGI->new;

# Get parameters from URL (e.g., fetchWSPR.pl?grid=FN30&maxage=900)
# Syntax: $q->param('parameter_name') // default_value
my $ofgrid = $q->param('ofgrid') // "EN41";
my $maxage = $q->param('maxage') // 900;

# Basic Sanitization (Very important for SQL safety)
$ofgrid =~ s/[^a-zA-Z0-9]//g; # Remove anything not alphanumeric
$maxage =~ s/[^0-9]//g;       # Ensure maxage is strictly a number

# --- SQL QUERY ---
my $sql = "SELECT toUnixTimestamp(time) as epoch, tx_loc, tx_sign, rx_loc, rx_sign, frequency, snr " .
          "FROM wspr.rx " .
          "WHERE tx_loc LIKE '$ofgrid%' " .
          "AND time > subtractSeconds(now(), $maxage) " .
          "FORMAT JSON";

# --- EXECUTION ---
# Required for web output (tells the browser/requester to expect plain text)
print "Content-type: text/plain; charset=ISO-8859-1\n\n";

my $ua = LWP::UserAgent->new(agent => "HamClock-Compat/1.0");
$ua->timeout(15);

my $url = "https://db1.wspr.live/?query=" . uri_escape($sql);
my $response = $ua->get($url);

if ($response->is_success) {
    my $decoded = decode_json($response->content);

    foreach my $row (@{$decoded->{data}}) {
        my $tx_sign = uc($row->{tx_sign});
        my $tx_loc  = uc($row->{tx_loc});
        my $rx_sign = uc($row->{rx_sign});
        my $rx_loc  = uc($row->{rx_loc});
        printf("%s,%s,%s,%s,%s,WSPR,%s,%s\n",
            $row->{epoch},
            $tx_loc,
            $tx_sign,
            $rx_loc,
            $rx_sign,
            $row->{frequency},
            $row->{snr}
        );
    }
} else {
    if ($response->code == 429 || $response->code == 403) {
        print "Error: Rate limit exceeded. Wait 5 seconds between calls.\n";
    } else {
        print "HTTP Error: " . $response->status_line . "\n";
    }
}
