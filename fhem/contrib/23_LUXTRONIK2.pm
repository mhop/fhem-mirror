################################################################
#
#  Copyright notice
#
#  (c) 2012 Torsten Poitzsch (torsten.poitzsch@gmx.de)
#  (c) 2012 Jan-Hinrich Fessel (oskar@fessel.org)
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

my $cc; # The Itmes Changed Counter

sub
LUXTRONIK2_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "LUXTRONIK2_Define";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6 firmware statusHTML";
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

sub
LUXTRONIK2_TempValueMerken($$$)
{
  my ($hash, $param, $paramName) = @_;

  $param /= 10;
  if($hash->{READINGS}{$paramName}{VAL} != $param) {
    $hash->{READINGS}{$paramName}{TIME} = TimeNow();
    $hash->{READINGS}{$paramName}{VAL} = $param;
    $hash->{READINGS}{$paramName}{UNIT} = "Degree Celsius";
    $hash->{CHANGED}[$cc++] = $paramName .": ". $param;
  }
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
  my $count=0;
#  my $i=0;
  my $name = $hash->{NAME};
  my $host = $hash->{Host};
  my $sensor = '';
  my $state = '';
  my $firmware;
  my $serialno;

  $cc = 0; #initialize counter
 
  InternalTimer(gettimeofday() + $hash->{INTERVAL}, "LUXTRONIK2_GetStatus", $hash, 0);

  my $socket = new IO::Socket::INET (  PeerAddr => $host, 
				       PeerPort => 8888,
				       #   Type => SOCK_STREAM, # probably needed on some systems
				       Proto => 'tcp'
      );
  if (!$socket) {
      $hash->{STATE} = "error opening device"; 
      Log 1,"$name: Error opening Connection to $host";
      return "Can't Connect to $host -> $@ ( $!)\n";
  }
  $socket->autoflush(1);
  
  #Read operational values
  
  $socket->send(pack("N", 3004));
  $socket->send(pack("N", 0));
  
  # read response, should be 3004, status, number of parameters, and the parameters...
  $socket->recv($result,4);
  $count = unpack("N", $result);
  if($count != 3004) {
      Log 2, "LUXTRONIK2_GetStatus: $name $host 3004 Status problem 1: ".length($result)." -> ".$count;
      return "3004 != 3004";
  }
 
  $socket->recv($result,4);
  $count = unpack("N", $result);
  if($count != 0) {
      Log 2, "LUXTRONIK2_GetStatus: $name $host ".length($result)." -> ".$count;
      return "0 != 0";
  }
  
  $socket->recv($result,4);
  $count = unpack("N", $result);
  if($count == 0) {
      Log 2, "LUXTRONIK2_GetStatus: $name $host 0 Paramters read".length($result)." -> ".$count;
      return "0 Paramters read";
  }

  $socket->recv($result, $count*4+4);
  if(length($result) != $count*4) {
      Log 1, "LUXTRONIK2_GetStatus status report length check: $name $host ".length($result)." should have been ". $count * 4;
      return "Value read mismatch Lux2 ( $!)\n";
  }
  @heatpump_values = unpack("N!$count", $result);
  if(scalar(@heatpump_values) != $count) {
      Log 2, "LUXTRONIK2_GetStatus10: $name $host ".scalar(@heatpump_values)." -> ".$heatpump_values[10];
      return "Value unpacking problem";
  }
  
  # Parametereinstellung lesen
  $socket->send(pack("N", 3003));
  $socket->send(pack("N", 0));

  $socket->recv($result,4);
  $count = unpack("N", $result);
  $count = unpack("N", $result);
  if($count != 3003) {
      Log 2, "LUXTRONIK2_GetStatus: $name $host 3003 Status problem 1: ".length($result)." -> ".$count;
      return "3003 != 3003";
  }
  
  $socket->recv($result,4);
  $count = unpack("N", $result);
 
  $socket->recv($result, $count*4+4);
  if(length($result) != $count*4) {
      my $loop = 4; # safety net in case of communication problems
      while((length($result) < ($count * 4)) && ($loop-- > 0) ) {
	  my $result2;
	  my $newcnt = ($count * 4) - length($result);
	  $socket->recv($result2, $newcnt);
	  $result .= $result2;
#	  Log 3, "LUXTRONIK2_GetStatus read additional " . length($result2)
#	      . " bytes of expected " . $newcnt . " bytes, total should be "
#	      . $count * 4 . " buflen=" . length($result);
      }
      if($loop == 0) {
        Log 3, "LUXTRONIK2_GetStatus parameter settings length check: $name $host "
	  . length($result) . " should have been " . $count * 4;
      }
  }
  @heatpump_parameters = unpack("N$count", $result);
  if(scalar(@heatpump_parameters) != $count) {
      Log 1, "LUXTRONIK2_GetStatus: $name $host pump parameter problem: received parameter count ("
	  . scalar(@heatpump_parameters) .
	  ") is not equal to announced parameter count(" . $count . ")!";
      return "Parameter read mismatch LUXTRONIK2 ( $!)\n";
  }
 
  $socket->close();

  if($err_log ne "")
  {
      Log GetLogLevel($name,2), "LUXTRONIK2 ".$err_log;
      return("LUXTRONIK2 general problem with heatpump connection");
  }
  
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

  $sensor = "firmware";
  $value = '';
  for(my $fi=81; $fi<91; $fi++) {
      $value .= chr($heatpump_values[$fi]) if $heatpump_values[$fi];
  }
  if($hash->{READINGS}{$sensor}{VAL} ne $value) {
      $hash->{READINGS}{$sensor}{TIME} = TimeNow();
      $hash->{READINGS}{$sensor}{VAL} = $value;
      $hash->{CHANGED}[$cc++] = $sensor.": ".$value;
  }

  $sensor = "currentOperatingStatus1";
  $switch = $heatpump_values[117];
  $value = $wpOpStat1{$switch};
  $value = "unbekannt (".$switch.")" unless $value;

  if($hash->{READINGS}{$sensor}{VAL} ne $value) {
      $hash->{READINGS}{$sensor}{TIME} = TimeNow();
      $hash->{READINGS}{$sensor}{VAL} = $value;
      $hash->{CHANGED}[$cc++] = $sensor.": ".$value;
  }

  $state = $value;
  
  $sensor = "currentOperatingStatus2";
  $switch = $heatpump_values[119];
  $value = $wpOpStat2{$switch};

  # Sonderfaelle behandeln:
  if ($switch==6) { $value = "Stufe ".$heatpump_values[121]." ".($heatpump_values[122] / 10)." &deg;C "; }
  elsif ($switch==7) { 
      if ($heatpump_values[44]==1) {$value = "Abtauen (Kreisumkehr)";}
      else {$value = "Luftabtauen";}
  }
  $value = "unbekannt (".$switch.")" unless $value;
  
  if($hash->{READINGS}{$sensor}{VAL} ne $value) {
      $hash->{READINGS}{$sensor}{TIME} = TimeNow();
      $hash->{READINGS}{$sensor}{VAL} = $value;
      $hash->{CHANGED}[$cc++] = $sensor.": ".$value;
  }

  $state = $state." - ".$value;
  $hash->{READINGS}{state}{VAL} = $state;
  $hash->{READINGS}{state}{TIME} = TimeNow();
  
  $sensor = "hotWaterOperatingMode";
  $switch = $heatpump_parameters[4];
  
  $value = $wpMode{$switch};
  $value = "unbekannt (".$switch.")" unless $value;
 
  if($hash->{READINGS}{$sensor}{VAL} ne $value) {
      $hash->{READINGS}{$sensor}{TIME} = TimeNow();
      $hash->{READINGS}{$sensor}{VAL} = $value;
      $hash->{CHANGED}[$cc++] = $sensor.": ".$value;
  }

  $sensor = "heatingOperatingMode";
  $switch = $heatpump_parameters[3];
  
  $value = $wpMode{$switch};
  if ($switch == 0 
		&& $heatpump_values[16] >= $heatpump_parameters[700] 
		&& $heatpump_parameters[699] == 1)
	{$value = "Automatik - Sommerbetrieb (Aus)";}
  $value = "unbekannt (" . $switch . ")" unless $value;
 
  if($hash->{READINGS}{$sensor}{VAL} ne $value) {
      $hash->{READINGS}{$sensor}{TIME} = TimeNow();
      $hash->{READINGS}{$sensor}{VAL} = $value;
      $hash->{CHANGED}[$cc++] = $sensor.": ".$value;
  }

#####################
# Jetzt die aktuellen Betriebswerte auswerten.
#####################

  # is ambient temperature the correct wording for the outside temperature?
  # Wikipedia:
  # Ambient temperature simply means "the temperature of the surroundings" and will be the same as room temperature indoors.
  LUXTRONIK2_TempValueMerken($hash,$heatpump_values[15],"ambientTemperature");
  
  LUXTRONIK2_TempValueMerken($hash,$heatpump_values[16],"averageAmbientTemperature");
  
  Log GetLogLevel($name,4), $sensor.": ".$value;
#  Log 4, "LUXTRONIK2_GetStatus: $name $host ".$hash->{STATE}." -> ".$state;
   
  LUXTRONIK2_TempValueMerken($hash,$heatpump_values[17],"hotWaterTemperature");
  
  # Wert 10 gibt die Vorlauftemperatur an, die 
  # korrekte Uebersetzung ist flow temperature.
  LUXTRONIK2_TempValueMerken($hash,$heatpump_values[10],"flowTemperature");
  # Ruecklauftempereatur
  LUXTRONIK2_TempValueMerken($hash,$heatpump_values[11],"returnTemperature");
  # Ruecklauftemperatur Sollwert
  LUXTRONIK2_TempValueMerken($hash,$heatpump_values[12],"returnTemperatureTarget");
  # Ruecklauftemperatur am externen Sensor.
  LUXTRONIK2_TempValueMerken($hash,$heatpump_values[13],"returnTemperatureExtern");

# Wärmequellen
  LUXTRONIK2_TempValueMerken($hash,$heatpump_values[19],"heatSourceIN");
  LUXTRONIK2_TempValueMerken($hash,$heatpump_values[20],"heatSourceOUT");


  # Durchfluss Waermemengenzaehler
  $sensor = "flowRate";
  $value = $heatpump_values[155];
  if($hash->{READINGS}{$sensor}{VAL} != $value) {
      $hash->{READINGS}{$sensor}{TIME} = TimeNow();
      $hash->{READINGS}{$sensor}{VAL} = $value;
      $hash->{READINGS}{$sensor}{UNIT} = "l/h";
      $hash->{CHANGED}[$cc++] = $sensor.": ".$value;
  }
  # Waermemengenzaehler
  $sensor = "flowCountHeating";
  $value = $heatpump_values[151];
  if($hash->{READINGS}{$sensor}{VAL} != $value) {
      $hash->{READINGS}{$sensor}{TIME} = TimeNow();
      $hash->{READINGS}{$sensor}{VAL} = $value;
      $hash->{READINGS}{$sensor}{UNIT} = "Wh";
      $hash->{CHANGED}[$cc++] = $sensor.": ".$value;
  }
  # Waermemengenzaehler                                                                                                                                           
  $sensor = "flowCountHotWater";
  $value = $heatpump_values[152];
  if($hash->{READINGS}{$sensor}{VAL} != $value) {
      $hash->{READINGS}{$sensor}{TIME} = TimeNow();
      $hash->{READINGS}{$sensor}{VAL} = $value;
      $hash->{READINGS}{$sensor}{UNIT} = "Wh";
      $hash->{CHANGED}[$cc++] = $sensor.": ".$value;
  }

  if(AttrVal($hash->{NAME}, "statusHTML", "none") ne "none") {
      $sensor = "floorplanHTML";
      $value = '<div class=fp_' . $name . '_title>' . $name . "</div>";
      $value .= $hash->{READINGS}{'currentOperatingStatus1'}{VAL} . '<br>';
      $value .= $hash->{READINGS}{'currentOperatingStatus2'}{VAL} . '<br>';
      $value .= "Brauchwasser:" . $hash->{READINGS}{hotWaterTemperature}{VAL} . '&deg;C';
      $hash->{READINGS}{$sensor}{TIME} = TimeNow();
      $hash->{READINGS}{$sensor}{VAL} = $value;
      $hash->{READINGS}{$sensor}{UNIT} = "HTML";
  }

  DoTrigger($name, undef) if($init_done);
}

1;

=pod
=begin html

<a name="LUXTRONIK2"></a>
<h3>LUXTRONIK2</h3>
<ul>
  Luxtronik 2.0 is a heating controller used in Alpha Innotec and Siemens Novelan Heatpumps.
  It can be directly integrated into a local area network (Ethernet port).<br>
  <br>

  <a name="LUXTRONIK2define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LUXTRONIK2 &lt;IP-address&gt; [&lt;poll-interval&gt;]</code>
    <br><br>
	If the pool interval is omitted, it is set to 300 (seconds).
	<br><br>
    Example:
    <ul>
      <code>define Heizung LUXTRONIK2 192.168.0.12 600</code><br>
    </ul>
  </ul>
  <br>

  <a name="LUXTRONIK2set"></a>
  <b>Set </b>
	<ul>
    Nothing to set here yet...
    </ul>
  <br>

  <a name="LUXTRONIK2get"></a>
  <b>Get</b>
  <ul>
   No get implemented yet ...
  </ul>
  <br>

  <a name="LUXTRONIK2attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#loglevel">loglevel</a></li>
  </ul>
  <br>

  </ul>

=end html
=cut
