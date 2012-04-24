################################################################
#
#  Copyright notice
#
#  (c) 2012 Torsten Poitzsch (torsten.poitzsch@gmx.de)
#
#  This script is free software; you can redistribute it and/or modify
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
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################

##############################################
package main;

use strict;
use warnings;
use IO::Socket; 

sub
LUXTRONIK2_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "LUXTRONIK2_Define";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6";
}

sub
LUXTRONIK2_Define($$)
{
  my ($hash, $def) = @_;
  my $name=$hash->{NAME};
  my @a = split("[ \t][ \t]*", $def);

  return "Wrong syntax: use define <name> LUXTRONIK2 <ip-address> [<poll-interval>]" if(int(@a) <3 || int(@a) >4);
  $hash->{Host} = $a[2];
  $hash->{INTERVAL}=$a[3] || 300;
 
  InternalTimer(gettimeofday() + $hash->{INTERVAL}, "LUXTRONIK2_GetStatus", $hash, 0);
 
  return undef;
}

#####################################

sub
LUXTRONIK2_GetStatus($)
{
  my ($hash) = @_;
  my $err_log='';
  my @heatpump_values;
  my @heatpump_parameters;
  my $result='';
  my $switch=0;
  my $value='';
  my $i=0;
  my $name = $hash->{NAME};
  my $host = $hash->{Host};
  my $sensor = '';
  
  InternalTimer(gettimeofday() + $hash->{INTERVAL}, "LUXTRONIK2_GetStatus", $hash, 0);

  my $socket = new IO::Socket::INET (  PeerAddr => $host, 
                                    PeerPort => 8888,
                                    Type => SOCK_STREAM,
									Proto => 'tcp'
                                 );
  $err_log .=  "Fehler: $!\n"
    unless defined $socket;
  $socket->autoflush(1);
  
  #Betriebswerte lesen
  
  $socket->send(pack("l", 3004));
  $socket->send(pack("l", 0));
 
  $socket->recv($result,4);
  @heatpump_values = unpack("l", $result);
 
  $socket->recv($result,4);
  @heatpump_values = unpack("l", $result);
  
  $socket->recv($result,4);
  @heatpump_values = unpack("l", $result);
  
  $socket->recv($result,1024);
  @heatpump_values = unpack("l@heatpump_values", $result);
  
  # Parametereinstellung lesen
  $socket->send(pack("l", 3003));
  $socket->send(pack("l", 0));

  $socket->recv($result,4);
  @heatpump_parameters = unpack("l", $result);
 
  $socket->recv($result,4);
  @heatpump_parameters = unpack("l", $result);
  
  $socket->recv($result,1024);
  @heatpump_parameters = unpack("l@heatpump_parameters", $result);
 
 $socket->close();

  if($err_log ne "")
  {
        Log GetLogLevel($name,2), "LUXTRONIK2 ".$err_log;
        return("");
  }

  $sensor = "currentOperatingStatus1";
  $switch = $heatpump_values[117];
  if ($switch==0) { $value = "Waermepumpe laeuft"; }
  elsif ($switch==1) { $value = "Waermepumpe steht"; }
  elsif ($switch==2) { $value = "Waermepumpe kommt"; }
  elsif ($switch==4) { $value = "Fehler"; }
  elsif ($switch==5) { $value = "Abtauen"; }
  else { $value = "unbekannt (".$switch.")"; }

  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;

  my $state = $value;
  
  $sensor = "currentOperatingStatus2";
  $switch = $heatpump_values[119];
  if ($switch==0) { $value = "Heizbetrieb"; }
  elsif ($switch==1) { $value = "Keine Anforderung"; }
  elsif ($switch==2) { $value = "Netz Einschaltverz&ouml;gerung"; }
  elsif ($switch==3) { $value = "Schaltspielzeit"; }
  elsif ($switch==4) { $value = "EVU Sperrzeit"; }
  elsif ($switch==5) { $value = "Brauchwasser"; }
  elsif ($switch==6) { $value = "Stufe ".$heatpump_values[121]." ".($heatpump_values[122] / 10)." &deg;C "; }
  elsif ($switch==7) { 
		if ($heatpump_values[44]==1) {$value = "Abtauen (Kreisumkehr)";}
		else {$value = "Luftabtauen";}
	}
  elsif ($switch==8) { $value = "Pumpenvorlauf"; }
  elsif ($switch==9) { $value = "Thermische Desinfektion"; }
  elsif ($switch==10) { $value = "Kuhlbetrieb"; }
  elsif ($switch==12) { $value = "Schwimmbad"; }
  elsif ($switch==13) { $value = "Heizen_Ext_En"; }
  elsif ($switch==14) { $value = "Brauchw_Ext_En"; }
  elsif ($switch==15) { $value = "unbekannt"; }
  elsif ($switch==16) { $value = "Durchflussueberwachung"; }
  elsif ($switch==17) { $value = "Elektrische Zusatzheizung"; }
  else { $value = "unbekannt (".$switch.")"; }
  
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;

  $state = $state." - ".$value;
  $hash->{STATE} = $state;
  #$hash->{CHANGED}[0] = $state;
  
  $sensor = "ambientTemperature";
  $value = $heatpump_values[15] / 10;
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;
  $hash->{CHANGED}[$i++] = "$sensor: $value";
  
  $sensor = "averageAmbientTemperature";
  $value = $heatpump_values[16] / 10;
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;
  $hash->{CHANGED}[$i++] = "$sensor: $value";
  
  Log GetLogLevel($name,4), $sensor.": ".$value;
  #Log 4, "LUXTRONIK2_GetStatus: $name $host ".$hash->{STATE}." -> ".$state;
   
  $sensor = "hotWaterTemperature";
  $value = $heatpump_values[17] / 10;
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;
  $hash->{CHANGED}[$i++] = "$sensor: $value";
  
  $sensor = "hotWaterOperatingMode";
  $switch = $heatpump_parameters[4];
  
  if ($switch==0) { $value = "Automatik"; }
  elsif ($switch==1) { $value = "Zusatzheizung"; }
  elsif ($switch==2) { $value = "Party"; }
  elsif ($switch==3) { $value = "Ferien"; }
  elsif ($switch==4) { $value = "Aus"; }
  else { $value = "unbekannt (".$switch.")"; }
 
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;
 

  $sensor = "heatingOperatingMode";
  $switch = $heatpump_parameters[3];
  
  if ($switch==0) { $value = "Automatik"; }
  elsif ($switch==1) { $value = "Zusatzheizung"; }
  elsif ($switch==2) { $value = "Party"; }
  elsif ($switch==3) { $value = "Ferien"; }
  elsif ($switch==4) { $value = "Aus"; }
  else { $value = "unbekannt (".$switch.")"; }
 
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;
 
  $sensor = "inletTemperature";
  $value = $heatpump_values[10] / 10;
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;
  $hash->{CHANGED}[$i++] = "$sensor: $value";
  
  $sensor = "returnTemperature";
  $value = $heatpump_values[11] / 10;
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;
  $hash->{CHANGED}[$i++] = "$sensor: $value";
 
  $sensor = "returnTargetTemperature";
  $value = $heatpump_values[12] / 10;
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;
  $hash->{CHANGED}[$i++] = "$sensor: $value";
 
  $sensor = "flowRate";
  $value = $heatpump_values[155];
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;
  $hash->{CHANGED}[$i++] = "$sensor: $value";
 
  
  DoTrigger($name, undef) if($init_done);
}

1;
