##############################################
# VarDump for FHEM-Devices
##############################################
# Installation
# 99_dumpdef.pm ins FHEM-Verzeichis kopieren
# dann: "reload 99_dumpdef.pm"
##############################################
# Aufruf: dumpdef "DEVICE-NAME"
##############################################
# Aufruf: dumpdef <XXX>
# <MOD> = %modules
# <SEL> = %selectlist
# <CMD> = %cmds
# <DAT> = %data
##############################################
package main;
use strict;
use warnings;
use POSIX;
use Data::Dumper;
sub Commanddumpdef($);

#####################################
sub
dumpdef_Initialize($)
{
  my %lhash = ( Fn=>"Commanddumpdef",
                Hlp=>"Dump <devspec> to FHEMWEB & LOG" );
  $cmds{dumpdef} = \%lhash;
}


#####################################
sub Commanddumpdef($)
{
  my ($cl, $d) = @_;
  return "Usage: dumpdef <DeviceName>" if(!$d);
  my($package, $filename, $line, $subroutine) = caller(3);
  my $r = "CALLER => $package: $filename LINE: $line SUB: $subroutine \n";
  $r .= "SUB-NAME: " .(caller(0))[3] . "\n";
  if($d eq "CMD") {$r .= Dumper(%cmds) . "\n"; return $r; }
  if($d eq "DAT") {$r .= Dumper(%data) . "\n"; return $r; }
  if($d eq "MOD") {$r .= Dumper(%modules) . "\n"; return $r; }
  if($d eq "SEL") {$r .= Dumper(%selectlist) . "\n"; return $r; }
  if(!defined($defs{$d})) {
    return "Unkown Device";} 
  $r .= "DUMP-DEVICE: $d \n";
  $r .= Dumper($defs{$d}) . "\n";
  $r .= "DUMP-DEVICE-ATTR \n";
  $r .= Dumper($attr{$d}) . "\n";
  return $r;
}
1;
