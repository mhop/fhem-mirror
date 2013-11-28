##############################################
# Example for writing to RRD. 
# notify .*T:.* {RRDUpdateTemp("@","%")}
# and put this file in the <modpath>/FHEM directory.

package main;
use strict;
use warnings;
use RRDs; 

my $DB = "/var/lib/collectd/temperature.rrd"; 

sub
RRD_Initialize($$)
{
my ($hash, $init) = @_;
$hash->{Type} = "none";

if(! -f $DB) 
   {
   Log 3, "***RRD Init";
   RRDs::create($DB, "--step=300", 
      "DS:innen:GAUGE:1800:-30.0:70.0", 
      "DS:bad:GAUGE:1800:-30.0:70.0", 
      "DS:wasser:GAUGE:1800:-30.0:70.0",
      "RRA:AVERAGE:0.5:1:288", 
      "RRA:MAX:0.5:12:168", 
      "RRA:MIN:0.5:12:168",
      "RRA:AVERAGE:0.5:288:365") or die "Create error: ($RRDs::error)"; 
   }
}

### FHT80 ###
sub
RRDUpdateInnen($$)
{
my ($a1, $a2) = @_;
my @a = split(" ", $a2);
my $tm = TimeNow();

my $value = $a[1];
Log 5, "Device $a1 was set to $a2 (type: $defs{$a1}{TYPE})";

Log 2, "***InnenTemp:$value um $tm RRD";
RRDs::update($DB, "--template", "innen", "N:$value") or 
   die "Update error: ($RRDs::error)";
}

### HMS ###
sub
RRDUpdateTemp($$)
{
my ($a1, $a2) = @_;
# a2 is like "T: 21.2  H: 37 "
my @a = split(" ", $a2);
my $tm = TimeNow();
my $value = $a[1];

Log 5, "Device $a1 was set to $a2 (type: $defs{$a1}{TYPE})";

if($a1 eq "viebadtemp")
   { 
   Log 2, "***BadTemp:$value um $tm RRD";
   RRDs::update($DB, "--template", "bad", "N:$value") or 
   die "Update error: ($RRDs::error)";
   }

if($a1 eq "viewassertemp")
   { 
   Log 2, "***WasserTemp:$value um $tm RRD";
   RRDs::update($DB, "--template", "wasser", "N:$value") or 
   die "Update error: ($RRDs::error)";
   }
}

1;
