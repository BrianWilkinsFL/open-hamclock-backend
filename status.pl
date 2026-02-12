#!/usr/bin/perl
use strict;use warnings;use POSIX qw(strftime);
my $B="/opt/hamclock-backend";
my $M="$B/htdocs/ham/HamClock/maps";
sub age{my$f=shift;return"missing"unless-e$f;sprintf"%.1f min",(time-(stat$f)[9])/60}
sub r{chomp(my$x=`$_[0] 2>/dev/null`);$x||"n/a"}
print "Content-Type: text/html\n\n";
print "<pre style='color:#f0f0f0;background:transparent;font-family:monospace;'>\n";
print"Uptime: ".r("uptime -p")."\nLoad: ".r("cut -d' ' -f1-3 /proc/loadavg")."\n\n";
print"Backend Version: ".(-f"$B/VERSION"?r("cat $B/VERSION"):"dev")."\n";
print"Git Commit: ".(-d"$B/.git"?r("git -C $B rev-parse --short HEAD"):"n/a")."\n\n";
print"NOAA Solar Wind: ".age("$B/htdocs/ham/HamClock/solar-wind/swind-24hr.txt")."\n";
print"PSKReporter: ".age("$B/htdocs/ham/HamClock/pskreporter/psk.txt")."\n\n";
my%h;opendir(my$d,$M);while(readdir$d){/map-(D|N)-\d+x\d+-(Terrain|Countries)/&&$h{"$1-$2"}++}closedir$d;
print"Map Inventory:\n";printf"  %-10s %d\n",$_,$h{$_}for sort keys%h;
print"\nGenerated ".strftime"%F %T",localtime;
print "</pre>\n";
