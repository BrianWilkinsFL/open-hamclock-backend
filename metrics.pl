#!/usr/bin/perl
use strict;
use warnings;

my $STATE="/opt/hamclock-backend/ohb_cpu.hist";
my $MAX=30;

sub cpu_idle {
    open my $fh, "<", "/proc/stat" or return;
    my $l=<$fh>;
    close $fh;
    my @f=split /\s+/,$l;
    return ($f[4],$f[1]+$f[2]+$f[3]+$f[4]);
}

my ($i1,$t1)=cpu_idle();
sleep 1;
my ($i2,$t2)=cpu_idle();

my $usage = 100*(1-(($i2-$i1)/($t2-$t1)));
$usage = sprintf("%.1f",$usage);

# load history
my @h;
if (-f $STATE) {
    open my $fh,"<",$STATE;
    chomp(@h=<$fh>);
    close $fh;
}

push @h,$usage;
@h = @h[-$MAX..-1] if @h>$MAX;

open my $fh,">",$STATE;
print $fh join("\n",@h);
close $fh;

my @blocks = qw( ▁ ▂ ▃ ▄ ▅ ▆ ▇ █ );

sub spark {
    my @v=@_;
    my $s="";
    for (@v) {
        my $i=int($_/12.5);
        $i=7 if $i>7;
        $s.=$blocks[$i];
    }
    return $s;
}

my $mem = `free -m | grep Mem`;
$mem =~ s/^\s+//;

print "Content-Type: text/html\n\n";
print "<meta http-equiv='refresh' content='5'>\n";
print "<pre style='color:#f0f0f0;background:transparent;font-family:monospace;'>\n";
print "SYSTEM METRICS\n";
print "==============\n\n";

print "CPU: ".spark(@h)."\n";
print "Now: $usage%\n\n";

print "$mem\n";
print "</pre>\n";
