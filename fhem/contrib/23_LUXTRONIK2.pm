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
  
  #Get first data after 5 seconds
  InternalTimer(gettimeofday() + 5, "LUXTRONIK2_GetStatus", $hash, 0);
 
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
  my $state = '';
  
  InternalTimer(gettimeofday() + $hash->{INTERVAL}, "LUXTRONIK2_GetStatus", $hash, 0);

  my $socket = new IO::Socket::INET (  PeerAddr => $host, 
                                    PeerPort => 8888,
                                    Type => SOCK_STREAM,
									Proto => 'tcp'
                                 );
  $err_log .=  "Fehler: $!\n"
    unless defined $socket;
  $socket->autoflush(1);
  
  #Read operational values
  
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
  
  # Build string arrays
  my %wpOpStat1 = ( 0 => "Waermepumpe laeuft",
		    1 => "Waermepumpe steht",
		    2 => "Waermepumpe kommt",
		    3 => "Fehler",
		    4 => "Abtauen" );
  my %wpOpStat2 = ( 0 => "Heizbetrieb",
		    1 => "Keine Anforderung",
		    2 => "Netz Einschaltverz&ouml;gerung",
		    3 => "Schaltspielzeit",
		    4 => "EVU Sperrzeit",
		    5 => "Brauchwasser",
		    6 => "Stufe",
		    7 => "Abtauen",
		    8 => "Pumpenvorlauf",
		    9 => "Thermische Desinfektion",
		    10 => "K&uuml;hlbetrieb",
		    12 => "Schwimmbad",
		    13 => "Heizen_Ext_En",
		    14 => "Brauchw_Ext_En",
		    16 => "Durchflussueberwachung",
		    17 => "Elektrische Zusatzheizung" );
  my %wpMode = ( 0 => "Automatik",
		 1 => "Zusatzheizung",
		 2 => "Party",
		 3 => "Ferien",
		 4 => "Aus" );
	
  # Erst die operativen Stati und Parameterenstellungen
  
  $sensor = "currentOperatingStatus1";
  $switch = $heatpump_values[117];
  $value = $wpOpStat1{$switch};
  $value = "unbekannt (".$switch.")" unless $value;

  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;

  $state = $value;
  
  $sensor = "currentOperatingStatus2";
  $switch = $heatpump_values[119];
  $value = $wpOpStat2{$switch};
  
  # Special cases
  if ($switch==6) { $value = "Stufe ".$heatpump_values[121]." ".($heatpump_values[122] / 10)." &deg;C "; }
  elsif ($switch==7) { 
      if ($heatpump_values[44]==1) {$value = "Abtauen (Kreisumkehr)";}
      else {$value = "Luftabtauen";}
  }
  $value = "unbekannt (".$switch.")" unless $value;
    
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;

  $state = $state." - ".$value;
  $hash->{STATE} = $state;

  
  $sensor = "hotWaterOperatingMode";
  $switch = $heatpump_parameters[4];
  
  $value = $wpMode{$switch};
  if ($switch==0 && $heatpump_values[16]>=$heatpump_parameters[700] && $heatpump_parameters[699]==1) {$value = "Automatik - Sommerbetrieb (Aus)";}
  $value = "unbekannt (".$switch.")" unless $value;

  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;
 

  $sensor = "heatingOperatingMode";
  $switch = $heatpump_parameters[3];
  
  $value = $wpMode{$switch};
  $value = "unbekannt (".$switch.")" unless $value;
 
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;

 #####################
 # Jetzt die aktuellen Betriebswerte auswerten.
 #####################
  
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

  $sensor = "flowTemperature";
  $value = $heatpump_values[10] / 10;
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;
  $hash->{CHANGED}[$i++] = "$sensor: $value";
  
  $sensor = "returnTemperature";
  $value = $heatpump_values[11] / 10;
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;
  $hash->{CHANGED}[$i++] = "$sensor: $value";
 
  $sensor = "returnTemperatureExtern";
  $value = $heatpump_values[13] / 10;
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;
  $hash->{CHANGED}[$i++] = "$sensor: $value";

  $sensor = "returnTargetTemperature";
  $value = $heatpump_values[12] / 10;
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;
  $hash->{CHANGED}[$i++] = "$sensor: $value";
 
  # Durchfluss Wärmemengenzähler
  $sensor = "flowRate";
  $value = $heatpump_values[155];
  $hash->{READINGS}{$sensor}{TIME} = TimeNow();
  $hash->{READINGS}{$sensor}{VAL} = $value;
  $hash->{CHANGED}[$i++] = "$sensor: $value";
 
  
  DoTrigger($name, undef) if($init_done);
}

1;
