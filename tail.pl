#!/usr/bin/perl
use strict;
use warnings;
use CGI;

my $q = CGI->new;
my $f = $q->param('file') || '';

my %allowed = (
  lighttpd_access => "/var/log/lighttpd/access.log",
  lighttpd_error  => "/var/log/lighttpd/error.log",
  ohb             => "/opt/hamclock-backend/logs",
);
print "Content-Type: text/html\n\n";
print "<pre style='color:#f0f0f0;background:transparent;font-family:monospace;'>\n";

if ($f =~ /^ohb:(.+)$/) {
    my $log = "$allowed{ohb}/$1";
    die "Denied\n" unless -f $log;
    system("tail -n 30 $log");
    exit;
}

die "Denied\n" unless exists $allowed{$f};

system("tail -n 30 $allowed{$f}");
print "</pre>\n";
