#!/usr/bin/perl
use strict;
use warnings;
use POSIX qw(strftime);

my $f="/opt/hamclock-backend/.heartbeat";

print "Content-Type: text/html\n\n";
print "<pre style='color:#f0f0f0;background:transparent;font-family:monospace;'>\n";

unless (-f $f) {
    print "CRON: missing\n";
    exit;
}

my $t=(stat($f))[9];
my $age=time-$t;

print "CRON HEARTBEAT\n";
print "==============\n\n";

print "Last tick: ".strftime("%Y-%m-%d %H:%M:%S",localtime($t))."\n";
print "Age: $age sec\n";

if ($age > 180) {
    print "\nSTATUS: STALE\n";
} else {
    print "\nSTATUS: OK\n";
}
print "</pre>\n";
