#!/usr/bin/perl
##############################################
#
# VarDump for FHEM-Devices
#
##############################################
#
#  Copyright notice
#
#  (c) 2009 - 2010
#  Copyright: Axel Rieger (fhem BEI anax PUNKT info)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
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
# <VAL> = %value
# <CMD> = %cmds
# <DAT> = %data
##############################################
package main;
use strict;
use warnings;
use POSIX;
use Data::Dumper;
use vars qw(%data);
use vars qw(%cmds);
use vars qw(%attr);
use vars qw(%defs);
use vars qw(%modules);
use vars qw(%selectlist);
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
#  $d = $a[1];
  return "Usage: dumpdef <DeviceName>" if(!$d);
  my($package, $filename, $line, $subroutine) = caller(3);
  my $r = "CALLER => $package: $filename LINE: $line SUB: $subroutine \n";
  $r .= "SUB-NAME: " .(caller(0))[3] . "\n";
  $r .= "--------------------------------------------------------------------------------\n";
  $Data::Dumper::Maxdepth = 4;
  if($d eq "CMD") {$r .= Dumper(%cmds) . "\n"; return $r; }
  if($d eq "DAT") {$r .= Dumper(%data) . "\n"; return $r; }
  if($d eq "MOD") {$r .= Dumper(%modules) . "\n"; return $r; }
  if($d eq "SEL") {$r .= Dumper(%selectlist) . "\n"; return $r; }
  if($d eq "DEF") {$r .= Dumper(%defs) . "\n"; return $r; }

  if(!defined($defs{$d})) {
    return "Unkown Device";} 
  $r .= "DUMP-DEVICE: $d \n";
  $r .= Dumper($defs{$d}) . "\n";
  $r .= "--------------------------------------------------------------------------------\n";
  $r .= "DUMP-DEVICE-ATTR \n";
  $r .= Dumper($attr{$d}) . "\n";
  $r .= "--------------------------------------------------------------------------------\n";
  $r .= "DUMP-DEVICE-Module \n";
  $r .= Dumper($modules{$defs{$d}{TYPE}}) . "\n";
  return $r;
}
1;

=pod
=begin html

<a name="dumpdef"></a>
<h3>dumpdef</h3>
<ul>
  <code>dumpdef &lt;options&gt;</code>
  <br><br>
    Data::Dumper for FHEM-Devices/Hashes<br><br>
    Dumps the content of &lt;options&gt; to FHEMWEB<br><br>
    Options:<br><br>
    <ul>
    <table>
    <tr><td><code>FHEM-DEVICENAME</code></td><td>=></td><td><code>%defs{FHEM-DEVICENAME}+%attr{FHEM-DEVICENAME}</code></td></tr>
    <tr><td><code>MOD</code></td><td>=></td><td><code>%modules</code></td></tr>
    <tr><td><code>SEL</code></td><td>=></td><td><code>%selectlist</code></td></tr>
    <tr><td><code>DAT</code></td><td>=></td><td><code>%data</code></td></tr>
    <tr><td><code>CMD</code></td><td>=></td><td><code>%cmd</code></td></tr>
    </table>
    </ul>
  <br><br>
  Example:
  <ul><br>
    <pre>dumpdef TEST

    CALLER => main: /opt/fhz/FHEM/01_FHEMWEB.pm LINE: 194 SUB: main::FW_AnswerCall
    SUB-NAME: main::Commanddumpdef
    DUMP-DEVICE: TEST
    $VAR1 = {
        'IODev' => {},
        'NAME' => 'TEST',
        'NR' => 64,
        'STATE' => '???',
        'TYPE' => 'dummy'
        };
    DUMP-DEVICE-ATTR
    $VAR1 = {
        'room' => 'DEF_DUMMY,GRP.TEST'
        };
    </pre>
  </ul>
</ul>

=end html
=cut
