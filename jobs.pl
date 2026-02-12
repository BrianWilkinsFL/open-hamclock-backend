#!/usr/bin/perl
use strict;
use warnings;
use POSIX qw(strftime);

my $DIR="/opt/hamclock-backend/.jobs";

print "Content-Type: text/html\n\n";
print "<pre style='color:#f0f0f0;background:transparent;font-family:monospace;'>\n";

print "JOB DURATIONS\n";
print "=============\n\n";

opendir(my $dh,$DIR) or die "no jobs\n";

for my $f (sort readdir($dh)) {
    next if $f =~ /^\./;

    my %v;
    open my $fh,"<","$DIR/$f" or next;
    while(<$fh>) {
        chomp;
        my ($k,$val)=split /=/,$_,2;
        $v{$k}=$val;
    }
    close $fh;

    my $age = time - ($v{end}||0);

    printf "%-12s %4ss rc=%s age=%ds\n",
        $f,
        ($v{duration}//"?"),
        ($v{rc}//"?"),
        $age;
}

closedir($dh);
print "</pre>\n";
