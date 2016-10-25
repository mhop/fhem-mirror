#############################################################################
#
# 21_N4HMODULE.pm
#
# net4home Busconnector Device
#
# (c) 2014-2016 Oliver Koerber <koerber@net4home.de>
#
#
# Fhem is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# Fhem is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
# $Id$
#
##############################################################################

package main;

use strict;
use warnings;
use POSIX;
use SetExtensions;

sub N4HMODULE_Set($@);
sub N4HMODULE_Update($@);
sub N4HMODULE_DbLog_splitFn($);

my $n4hmodule_Version = "1.0.1.2 - 25.10.2016";


my %OT_devices = (
	"1" 	=> {"name" => "leer", "OTcanSet" => "false", "OTcanReq" => "false", "fields" => [] },
	
	"2" 	=> {"name" => "Eingang, Binär, Sx", "OTcanSet" => "false", "OTcanReq" => "true", "fields" => [] },
	
	"3" 	=> {"name" => "Ausgang, Binär, Relais", "OTcanSet" => "true", "OTcanReq" => "true", "fields" => [
					{ "cmd" =>  "350000", "ID" => "0", "text" => "UM", 						"Type" => "Button" , "set" => "toggle:noArg" },
					{ "cmd" =>  "326400", "ID" => "1", "text" => "EIN", 					"Type" => "Button" , "set" => "on:noArg" },
					{ "cmd" =>  "320000", "ID" => "2", "text" => "AUS", 					"Type" => "Button" , "set" => "off:noArg" },
					{ "cmd" =>  "428100", "ID" => "3", "text" => "Zwangsgeführt EIN", 		"Type" => "Button" , "set" => "lockon:noArg"  },
					{ "cmd" =>  "428000", "ID" => "4", "text" => "Zwangsgeführt AUS", 		"Type" => "Button" , "set" => "lockoff:noArg" },
					{ "cmd" =>  "420000", "ID" => "5", "text" => "Zwangsführung deaktiv", 	"Type" => "Button" , "set" => "unlock:noArg" },
                        ]},
						
	"4" 	=> {"name" => "Ausgang, Binär, Timer, Relais", "OTcanSet" => "true", "OTcanReq" => "true", "fields" => [
					{ "cmd" =>  "350000", "ID" => "0", "text" => "EIN für Dauer: Zeit 1", 	"Type" => "Button" , "set" => "toggle:noArg" },
					{ "cmd" =>  "320000", "ID" => "2", "text" => "AUS", 					"Type" => "Button" , "set" => "off:noArg" },
					{ "cmd" =>  "428100", "ID" => "3", "text" => "Zwangsgeführt EIN", 		"Type" => "Button" , "set" => "lockon:noArg" },
					{ "cmd" =>  "428000", "ID" => "4", "text" => "Zwangsgeführt AUS", 		"Type" => "Button" , "set" => "lockoff:noArg" },
					{ "cmd" =>  "420000", "ID" => "5", "text" => "Zwangsführung deaktiv", 	"Type" => "Button" , "set" => "unlock:noArg" },
                        ]},
						
	"5" 	=> {"name" => "Ausgang, Dimmer", "OTcanSet" => "true", "OTcanReq" => "true", "fields" => [
					{ "cmd" =>  "320000", "ID" => "3", "text" => "AUS", 					"Type" => "Button" , "set" => "off:noArg" },
					{ "cmd" =>  "326500", "ID" => "4", "text" => "EIN mit letztem Wert", 	"Type" => "Button" , "set" => "on:noArg" },
					{ "cmd" =>  "350000", "ID" => "5", "text" => "UM", 					 	"Type" => "Button" , "set" => "toggle:noArg" },
					{ "cmd" =>  "330000", "ID" => "7", "text" => "Heller", 					"Type" => "Button" , "set" => "dimup:noArg" },
					{ "cmd" =>  "340000", "ID" => "8", "text" => "Dunkler", 				"Type" => "Button" , "set" => "dimdown:noArg" },
					{ "cmd" =>  "428100", "ID" => "9", "text" => "Zwangsgeführt EIN", 		"Type" => "Button" , "set" => "lockon:noArg" },
					{ "cmd" =>  "428000", "ID" => "10","text" => "Zwangsgeführt AUS", 		"Type" => "Button" , "set" => "lockoff:noArg" },
					{ "cmd" =>  "32"	, "ID" => "10","text" => "Wert setzen auf", 		"Type" => "Button" , "set" => "pct:slider,0,1,100" },
					{ "cmd" =>  "420000", "ID" => "11", "Text" => "Zwangsführung deaktiv", 	"Type" => "Button" , "set" => "unlock:noArg" },
                        ]},
						
	"24" 	=> {"name" => "Messwert,Temperatur", "OTcanSet" => "false", "OTcanReq" 	=> "true", "fields" => [] },
	
	"25" 	=> {"name" => "Messwert,Helligkeit", "OTcanSet" => "false", "OTcanReq" 	=> "true", "fields" => [] },
	
	"26" 	=> {"name" => "Messwert,Feuchte", "OTcanSet" => "false", "OTcanReq" 	=> "true", "fields" => [] },
	
	"95" 	=> {"name" => "Ausgang, Jal, Motor AJ3", "OTcanSet" => "true", "OTcanReq" => "true", "fields" => [
					{ "cmd" =>  "320000", "ID" => "1", "text" => "STOP", 					"Type" => "Button" , "set" => "stop:noArg" },
					{ "cmd" =>  "320300", "ID" => "2", "text" => "AUF",					 	"Type" => "Button" , "set" => "up:noArg" },
					{ "cmd" =>  "320100", "ID" => "3", "text" => "AB", 						"Type" => "Button" , "set" => "down:noArg" },
					{ "cmd" =>  "428300", "ID" => "4", "text" => "Sperre OFFEN",			"Type" => "Button" , "set" => "lockup:noArg" },
					{ "cmd" =>  "428100", "ID" => "5", "text" => "Sperre GESCHLOSSEN", 		"Type" => "Button" , "set" => "lockdown:noArg" },
					{ "cmd" =>  "420000", "ID" => "6", "text" => "Sperre freigeben", 		"Type" => "Button" , "set" => "unlock:noArg" },
                        ]},

	"210" 	=> {"name" => "UP-RF Absender", "OTcanSet" => "false", "OTcanReq" 	=> "true", "fields" => [] },

	"240" 	=> {"name" => "Messwert,Wind", 		 "OTcanSet" => "false", "OTcanReq" 	=> "true", "fields" => [] },
	"242" 	=> {"name" => "Messwert,Luftdruck",  "OTcanSet" => "false", "OTcanReq" 	=> "true", "fields" => [] },
	"245" 	=> {"name" => "Messwert,Regenmenge", "OTcanSet" => "false", "OTcanReq" 	=> "true", "fields" => [] },
	
	"310" 	=> {"name" => "Stromzähler", "OTcanSet" => "false", "OTcanReq" 			=> "true", "fields" => [
					{ "cmd" =>  "330000", "ID" => "0", "Text" => "Inc", 					"Type" => "Button" , "set" => "inc" },
						]},
						
	"348" 	=> {"name" => "Zähler", "OTcanSet" => "false", "OTcanReq" => "true", "fields" => [
					{ "cmd" =>  "330000", "ID" => "0", "Text" => "+1", 						"Type" => "Button" , "set" => "inc"},
					{ "cmd" =>  "340000", "ID" => "1", "Text" => "-1", 						"Type" => "Button" , "set" => "dec" },
					{ "cmd" =>  "320000", "ID" => "3", "Text" => "Zählerwert reset", 		"Type" => "Button" , "set" => "reset" },
					{ "cmd" =>  "360000", "ID" => "4", "Text" => "Zählerwert lesen (nur LCD)", "Type" => "Button"  },
						] },
	"999" 	=> {"name" => "Messwert,N56", "OTcanSet" => "false", "OTcanReq" 	=> "true", "fields" => [] },
);

##################################################################################
sub N4HMODULE_Initialize($) {
##################################################################################

	my ($hash) = @_;


	my @otlist;
	foreach my $model (keys %OT_devices){
		push @otlist,$OT_devices{$model}->{name};
	}
	
	$hash->{DefFn}	       = "N4HMODULE_Define";
	$hash->{UndefFn}	   = "N4HMODULE_Undefine";
	$hash->{ParseFn}	   = "N4HMODULE_Parse";
	$hash->{SetFn}		   = "N4HMODULE_Set";
	$hash->{AttrFn}  	   = "N4HMODULE_Attr";
	$hash->{AttrList}	   = "IoDev dummy:1,0 Interval sendack:on,off setList ".
						     "$readingFnAttributes ";
						     "OT:"  .join(",", sort @otlist);                      
    $hash->{DbLog_splitFn} = "N4HMODULE_DbLog_splitFn";
}


##################################################################################
sub N4HMODULE_Define($$) {
##################################################################################

	my ($hash, $def) = @_;
	my @args = split("[ \t]+", $def);
	my ($name, $type, $n4hbus, $ot, $objadr) = @args;
	

	if(@args < 4) {
		my $msg = "Usage: define <name> N4HMODULE <N4HBUS> <OBJECTTYPE> <OBJADDR>";
		Log3 $hash, 2, $msg;
		return $msg;
	}

	$hash->{VERSION}	= $n4hmodule_Version;
	$hash->{STATE} 		= "Initializing";
	$hash->{NOTIFYDEV}  = "global";
	$hash->{IODev} 		= $n4hbus;
	$hash->{OBJADR}		= $objadr;
	$hash->{OT} 		= $ot;
	$hash->{DESC}		= $OT_devices{$ot}{name};
	$hash->{OTcanSet}	= $OT_devices{$ot}{OTcanSet};
	$hash->{OTcanReq}	= $OT_devices{$ot}{OTcanReq};

	$modules{N4HMODULE}{defptr}{$objadr} = $hash;
	
	AssignIoPort($hash, $n4hbus);
	Log3 $hash, 3, "N4HMODULE_Define -> $name ($ot) at device $n4hbus with objectadr $objadr";
	
	$hash->{helper}{from}		= '';
	$hash->{helper}{value}		= '';
	$hash->{helper}{cmd}		= '';
	$hash->{helper}{ddata}		= '';

	if ($hash->{OTcanSet}eq"true") {
		$hash->{helper}{state}	= 'undefined';
	}

	
	
	# Timer zum regelmäßigem aktualisieren auf dem Bus starten
	if (($ot ==  24) or #Temperatur
        ($ot ==  25) or #Licht
	    ($ot ==  26) or #Luftfeuchte
	    ($ot == 240) or #Wind
	    ($ot == 241) or #Sonne
		($ot == 242) or #Luftdruck
		($ot == 246) or #Luftdruck-Tendenz
	    ($ot == 245)) { #Regenmenge l/h

		RemoveInternalTimer($hash);
	 
		$hash->{Interval} = 30;

		# Timer Zeitversetzt starten, damit nicht alles auf den Bus gleichzeit kommt 30 Sekunden + x
		Log3 $hash, 3, "N4HMODULE_Define (set timer) -> $name ($ot)";
		InternalTimer( gettimeofday() + 30 + int(rand(15)) , "N4HMODULE_Start", $hash, 0 );
	} 
   return undef;
}

##################################################################################
sub N4HMODULE_Start($)
##################################################################################
{
	my ($hash) = @_;
	my $name   = $hash->{NAME};
	my $interval = $hash->{Interval}; 

    $interval = $attr{$name}{Interval}  if( defined($attr{$name}{Interval}) );
     
	Log3 $hash, 5, "N4HMODULE (start): ($name)-> ".$interval." Sekunden";

	if (($interval >= 30) and ($interval <= 86400)) {
    # reset timer if interval is defined
	  Log3 $hash, 5, "N4HMODULE (restart timer): ($name)-> ".$interval." Sekunden";
      RemoveInternalTimer( $hash );
      InternalTimer(gettimeofday() + $interval, "N4HMODULE_Start", $hash, 1 );
	  N4HMODULE_Update( $hash );
   }
}


##################################################################################
sub N4HMODULE_Undefine($$) {
##################################################################################

	my ($hash,$arg) = @_;
	
	# ToDo : Aufräumen noch mal ansehen
	
    my $c = $hash->{OBJADR};
    foreach my $dname (keys %{ $modules{N4HMODULE}{defptr}{$c} }) {
      delete($modules{N4HMODULE}{defptr}{$c}{$dname})
        if($modules{N4HMODULE}{defptr}{$c}{$dname} == $hash);
    }
	return undef;
}

##################################################################################
sub N4HMODULE_DbLog_splitFn($$) {
##################################################################################
	my ($event, $device) = @_;
	my ($reading, $value, $unit) = "";
    my $hash = $defs{$device};

    my @parts = split(/ /,$event);
    $value = $parts[1];
	
	if ($event =~ m/temperature/) {
	   $reading = 'temperature';
	   $unit = '°C';
	} elsif ($event =~ m/humidity/) {
	   $reading = 'humidity';
	   $unit = '%';
	} elsif ($event =~ m/pressure/) {
	   $reading = 'pressure';
	   $unit = 'hPas';
	} elsif ($event =~ m/co2/) {
	   $reading = 'co2';
	   $unit = 'ppm';
	} elsif ($event =~ m/rain/) {
	   $reading = 'rain';
	   $unit = 'l/h';
	} elsif ($event =~ m/brightness/) {
	   $reading = 'brightness';
	   $unit = '';
	}
	
  return ($reading, $value, $unit);
}

##################################################################################
sub N4HMODULE_Parse($$) {
##################################################################################

	my ($iodev, $msg, $local) = @_;
	my $ioName = $iodev->{NAME};
	my $object	= "";
 
	# Modul suchen
	my $type8   = hex(substr($msg,0,2));
	my $ipsrc   = substr($msg,4,2).substr($msg,2,2);
	my $ipdst   = hex(substr($msg,8,2).substr($msg,6,2));
	my $objsrc  = hex(substr($msg,12,2).substr($msg,10,2));
	my $datalen = int(hex(substr($msg,14,2)));
	my $ddata   = substr($msg,16, ($datalen*2));
	my $pos 	= $datalen*2+16;
	
	if ( length($msg) <= $pos ) {
#		Log3 $hash, 5, "N4MODULE (parse) -> ($msg) (ddata:$ddata) (pos:$pos)";
		return undef;
	}
	
	my $csRX	= substr($msg,$pos,2);
	my $csCalc	= substr($msg,$pos+2,2);
	my $len		= substr($msg,$pos+4,2);
	my $posb	= substr($msg,$pos+6,2);
	
	
	if ($ipdst == 32767) {
		$object = $objsrc;
	} else {
		$object = $ipdst;
	}

	my $hash = $modules{N4HMODULE}{defptr}{$object};
    Log3 $hash, 5, "N4HMODULE (parse): $msg";
	
	if (!$hash) {
		$object = $objsrc;
		$hash = $modules{N4HMODULE}{defptr}{$objsrc};
		}

	if(!$hash) {
		my $ret = "Undefined ObjectAddress ($object)";
		return "";
	}	
		
		my $devtype = $hash->{OT};

		N4HMODULE_ParsePayload($hash, $devtype, $ipsrc, $objsrc, $ddata);
		return $hash->{NAME};

}

##################################################################################
sub N4HMODULE_ParsePayload($@) {
##################################################################################

	my ($hash, $devtype, $ipsrc, $objsrc, $ddata) = @_;
	my $name = $hash->{NAME};
	my $dev_funcion = hex(substr($ddata,0,2)); 
	my $newState="";
	my $myval="";

	readingsBeginUpdate($hash);
	
	if( defined($objsrc))	{readingsBulkUpdate($hash,"from", $objsrc);}
	readingsBulkUpdate($hash,"ddata", $ddata);
	
#	+++++++ D0_SET
	if ($dev_funcion == hex("32")) {
		readingsBulkUpdate($hash,"cmd", "D0_SET");

		if (hex(substr($ddata,2,2))== hex("00")) {
			readingsBulkUpdate($hash,"state", "off");
		} else {
			readingsBulkUpdate($hash,"state", "on");
		}
	}

#	+++++++ D0_INC
	if ($dev_funcion == hex("33")) {
		readingsBulkUpdate($hash,"cmd", "D0_INC");
	}
	
#	+++++++ D0_TOGGLE
	if ($dev_funcion == hex("35")) {
		readingsBulkUpdate($hash,"cmd", "D0_TOGGLE");
	}

#	+++++++ D0_ACTOR_ACK
	if ($dev_funcion == hex("37")) {
		readingsBulkUpdate($hash,"cmd", "D0_ACTOR_ACK");
	}

#	+++++++ D0_REQ
	if ($dev_funcion == hex("36")) {
		readingsBulkUpdate($hash,"cmd", "D0_REQ");
		Log3 $hash, 5, "N4MODULE -> D0_REQ ($name) (".$hash->{OT}.")";
		N4HMODULE_Update( $hash );
	} 
	
#	+++++++ D0_SENSOR_ACK
	if ($dev_funcion == hex("41")) {
		readingsBulkUpdate($hash,"cmd", "D0_SENSOR_ACK");
		Log3 $hash, 5, "N4MODULE -> D0_SENSOR_ACK ($name) (".$hash->{OT}.")";
		N4HMODULE_Update( $hash );
	} 
	
#	+++++++ D0_VALUE_ACK (101)
	if ($dev_funcion == hex("65")) {
		readingsBulkUpdate($hash,"cmd", "D0_VALUE_ACK");
		my ($valtype, $lastval) = N4HMODULE_paramToText($hash, $ddata);
		if( defined($lastval))	{	readingsBulkUpdate($hash, $valtype, $lastval);	}
		
    my $state_format;
    my $readings = "";
      if( $readings =~ m/temperature/ ) {
        $state_format .= " " if( $state_format );
        $state_format .= "T: temperature";
      }
      if( $readings =~ m/humidity/ ) {
        $state_format .= " " if( $state_format );
        $state_format .= "H: humidity";
      }
	  
      if( $readings =~ m/windstrength/ ) {
        $state_format .= " " if( $state_format );
        $state_format .= "W: windstrength (windangle°)";
      }
	  
      if( $readings =~ m/co2/ ) {
        $state_format .= " " if( $state_format );
        $state_format .= "C: co2 ppm";
      }

      if( $readings =~ m/pressure/ ) {
        $state_format .= " " if( $state_format );
        $state_format .= "P: pressure";
      }

      $attr{$name}{stateFormat} = $state_format if( !defined($attr{$name}{stateFormat}) && defined($state_format) );
		
	}

#	+++++++ D0_VALUE_REQ
	if ($dev_funcion == hex("66")) {
		readingsBulkUpdate($hash,"cmd", "D0_VALUE_REQ");
		Log3 $hash, 5, "N4MODULE -> D0_VALUE_REQ ($name) (".$hash->{OT}.")";
		N4HMODULE_Update( $hash );
	} 

	#	+++++++ LCD-Text
	if ($dev_funcion == hex("3b")) {
		readingsBulkUpdate($hash,"cmd", "LCD-Text");
	}

	readingsEndUpdate( $hash , 1);
	return undef;			
}


##################################################################################
sub N4HMODULE_paramToText($@) {
##################################################################################

	my ($hash, $ddata) = @_;
	my $name = $hash->{NAME};
	my $rettype = "unbekannte Formel / Parameter";
	my $w = hex(substr($ddata,6,2))*256+hex(substr($ddata,8,2));
	my $ret = $w;
	my $t;
	
# 	+++++++++++++++++++ Licht analog - IN_HW_NR_IS_LICHT_ANALOG
	if (hex(substr($ddata,2,2)) == 5 ){
		$rettype = "brightness";
	}	

# 	+++++++++++++++++++ Uhrzeit - IN_HW_NR_IS_CLOCK
	elsif (hex(substr($ddata,2,2)) == 6 ){
		$rettype = "Uhrzeit";
	}	

# 	+++++++++++++++++++ RF-Tag Reader - IN_HW_NR_IS_RF_TAG_READER
	elsif (hex(substr($ddata,2,2)) == 7 ){ 
		$ret = uc substr($ddata,6,10);
		
		if ( (hex(substr($ddata,18,2)) & 6) == 0) {
		 $ret = $ret." vorgehalten";
		} elsif ( (hex(substr($ddata,18,2)) & 6) == 2) {
		 $ret = $ret." lang vorgehalten"; 
		} elsif ( (hex(substr($ddata,18,2)) & 6) == 4) {
		 $ret = $ret." weggezogen nach kurz";
		}
		else { $ret = $ret." ".hex(substr($ddata,18,2)) }
		 
		$rettype = "RF-Tag";
	}	

	# 	+++++++++++++++++++ Temperatur - IN_HW_NR_IS_TEMP
	elsif (hex(substr($ddata,2,2)) == 9 ){

	if (hex(substr($ddata,4,2)) == 5 ){ # USE_FROMEL_TEMP_UI16

		if (hex(substr($ddata,6,2)) == 0xff ) {
			$t = (hex(substr($ddata,8,2))-0xff)/16;
		}
		else {
			$t = $w/16;
		}
			$ret = sprintf "%.1f °C", $t;
			$rettype = "temperature";
		}
	}	
# 	+++++++++++++++++++ Feuchte - IN_HW_NR_IS_HUMIDITY
	elsif (hex(substr($ddata,2,2)) == 11 ){

		$ret = $w." %";
		$rettype = "humidity";
	}	
# 	+++++++++++++++++++ Wind - IN_HW_NR_IS_KMH
	elsif (hex(substr($ddata,2,2)) == 41 ){
	
	if (hex(substr($ddata,4,2)) == 6 ){ # USE_FROMEL_RAW_16BIT
		$ret = $w." km/h";
	}
	elsif (hex(substr($ddata,4,2)) == 7 ){ # USE_FROMEL_16BIT_X8
		$t = $w/8;
		$ret = $t." km/h";
	}
	$rettype = "wind";
		
	}	
	
# 	+++++++++++++++++++ Luftdruck - IN_HW_NR_IS_PRESS_MBAR
	elsif (hex(substr($ddata,2,2)) == 48 ){
	
		$t = $w/10;
		$ret = $t." hPas";
		$rettype = "pressure";
	}	

# 	+++++++++++++++++++ pressure Tendenz - IN_HW_NR_IS_PRESS_TENDENZ
	elsif (hex(substr($ddata,2,2)) == 49 ){
		$rettype = "pressure (Tendenz)";
	}	

	# 	+++++++++++++++++++ Uhrzeit - Sonnenaufgang heute
	elsif (hex(substr($ddata,2,2)) == 50 ){
		$rettype = "Sonnenaufgang";
	}	

# 	+++++++++++++++++++ Uhrzeit - Sonnenuntergang heute
	elsif (hex(substr($ddata,2,2)) == 51 ){
		$rettype = "Sonnenuntergang";
	}	
# 	+++++++++++++++++++ Regenmenge (Liter/Stunde) - VAL_IS_MENGE_LITER
	elsif (hex(substr($ddata,2,2)) == 53 ){
	
	if (hex(substr($ddata,4,2)) == 8 ){ # USE_FROMEL_16BIT_X10
		$t = $w/10;
		$ret = $t." l/h";
	}
	else { 
		$ret = $w." l/h";
	}
	$rettype = "rain";
		
	}	
	
	return ($rettype, $ret);
}


##################################################################################
sub N4HMODULE_Set($@) {
##################################################################################

	my ($hash, @a) = @_;
	
	return "\"set $a[0]\" needs at least two parameters" if(@a < 2);
	my $name = shift(@a);
    my $cmd  = shift(@a);
	my $ext  =  shift(@a);
	
	Log3 $hash, 5, "N4MODULE (set): ($name) ($cmd)";

	my $ot 			= $hash->{OT};
	my $ipdst		= $hash->{OBJADR};
	my $ddata 		= "";
	my @sets;
	my $fieldcmd	= "";
	my $fieldname;
	my $fieldset;
	my $setfield;
	my $devtype = $OT_devices{$ot};
	  

	if ($ot == 3 || $ot == 4 || $ot == 5 || $ot == 95) {

	for my $field (@{$devtype->{fields}}) {
	
			$setfield  = $field->{set};
			if (defined($setfield)) {
		
				push(@sets,$field->{set});
			
				$setfield = ( split /:/, $setfield, 2 )[0];

				if ($setfield eq $cmd) {
					$fieldname = $field->{text};
					$fieldcmd  = $field->{cmd};
					$fieldset  = $field->{set};
				}
			}
		 }	
		
		if ($fieldcmd ne "" && $cmd ne "?")  {
	
			if (defined($ext)) {
				
				
				if ($cmd eq "pct") {
					$fieldcmd = "$fieldcmd".sprintf ("%02x", ($ext))."00";
					$ddata = sprintf ("%02x%s", ((length($fieldcmd))/2), $fieldcmd);
					readingsSingleUpdate($hash, "pct", "$ext", 1);
					Log3 $hash, 5, "N4MODULE (set): $name to $cmd ($ext%) ($ddata)";
				} else {
					$ddata = sprintf ("%02x%s", (length($fieldcmd)/2), $fieldcmd);
					Log3 $hash, 5, "N4MODULE (set): $name to $cmd/$ext ($cmd-".join(" ", @sets)."-$devtype-$fieldcmd-$ot)";
				}
				
			} else {
				Log3 $hash, 5, "N4MODULE (set): $name to $cmd ($cmd-".join(" ", @sets)."-$devtype-$fieldcmd-$ot)";
				$ddata = sprintf ("%02x%s", (length($fieldcmd)/2), $fieldcmd);
			}
			
			readingsSingleUpdate($hash, "state", "$cmd", 1);
			IOWrite($hash, $ipdst, $ddata, 0);
			return undef;
		}
		else {
			return SetExtensions($hash, join(" ", @sets), $name, $cmd, @a);
		}
		
	}
	elsif ($ot == 24 || $ot == 25 || $ot == 26 || $ot == 240 || $ot == 242 || $ot == 245) {

		if ($cmd ne "?") {
			Log3 $hash, 5, "N4MODULE (set): $name to $cmd";
			N4HMODULE_Update($hash, $cmd);
		}	
		return undef;
	}
	elsif ($ot == 999) {

		if ($cmd ne "?") {
			Log3 $hash, 5, "N4MODULE (set n56): $name to $cmd";
			N4HMODULE_Update($hash, $cmd);
		}	
		return undef;
	}
	 
	return undef;
	
}	


##################################################################################
sub N4HMODULE_Update($@) {
##################################################################################

	my ($hash, @a) = @_;
	my $value = shift(@a);

	my $name 		= $hash->{NAME};
    return unless (defined($hash->{NAME}));

	Log3 $hash, 5, "N4MODULE (update): ($name) ($value)";

	my $ot 			= $hash->{OT};
	my $ipdst		= $hash->{OBJADR};
    my $ddata 		= "";
	my $cs			= "";
	my $cmd         = "";

	if ($ot == 24) {

#	+++++++ 65 D0_VALUE_ACK (101)
#	+++++++ 09 Temperatur
#   +++++++ 05 USE_FROMEL_TEMP_UI16

		my $ddata1 = "650905";
		
		if (defined $value) {
		 $cmd = $value; 
		 readingsSingleUpdate($hash, "temperature", "$cmd °C", 1);
		}
		else {
		 ($cmd, undef) = split(/ /, ReadingsVal($name , "temperature", "")); } 
		 
		if (defined $cmd) {

			if ($cmd >= 0) {
			$cs = $cmd*16;
			$ddata1 = $ddata1.sprintf ("%02X", ($cs>>8) );	
			}
			elsif ($cmd < 0) { 
			$cs = 0xff+($cmd*16);
			$ddata1 = $ddata1.sprintf ("%02X", 0xff );	
			}
		
			$ddata1 = $ddata1.sprintf ("%02X", ( ($cs>>0) & 255 ) );	
			$ddata = sprintf ("%02x%s", (length($ddata1)/2), $ddata1);

			Log3 $hash, 5, "N4MODULE (set temperature): $name to $cmd - $ddata, $ddata1, $ipdst";
			IOWrite($hash, 32767, $ddata, $ipdst);
		}
		return undef;
	}
	elsif ($ot == 25) { # Licht

#	+++++++ 65 D0_VALUE_ACK
#	+++++++ 05 Licht
#   +++++++ 01 USE_FROMEL

		my $ddata1 = "650506";

		if (defined $value) {
		 $cmd = $value; 
		 readingsSingleUpdate($hash, "brightness", "$cmd", 1);
		}
		else {
  		 ($cmd, undef) = split(/ /, ReadingsVal($name , "brightness","")); }

		if (defined $cmd) {
			my $cs = $cmd;
			$ddata1 = $ddata1.sprintf ("%02X", (0x00) );	
			$ddata1 = $ddata1.sprintf ("%02X", ( ($cs) ) );	
			$ddata = sprintf ("%02x%s", (length($ddata1)/2), $ddata1);

			Log3 $hash, 5, "N4MODULE (set brightness): $name to $cmd - $ddata, $ddata1, $ipdst";
			IOWrite($hash, 32767, $ddata, $ipdst);
		}
		return undef;
	}
	elsif ($ot == 26) { # Luftfeuchte

#	+++++++ 65 D0_VALUE_ACK
#	+++++++ 0B Luftfeuchte
#   +++++++ 01 USE_FROMEL

		my $ddata1 = "650B01";

		if (defined $value) {
		 $cmd = $value; 
		 readingsSingleUpdate($hash, "humidity", "$cmd %", 1);
		}
		else {
  		 ($cmd, undef) = split(/ /, ReadingsVal($name , "humidity","")); }

		if (defined $cmd) {
			my $cs = $cmd;
			$ddata1 = $ddata1.sprintf ("%02X", (0x00) );	
			$ddata1 = $ddata1.sprintf ("%02X", ( ($cs) ) );	
			$ddata = sprintf ("%02x%s", (length($ddata1)/2), $ddata1);

			Log3 $hash, 5, "N4MODULE (set humidity): $name to $cmd - $ddata, $ddata1, $ipdst";
			IOWrite($hash, 32767, $ddata, $ipdst);
		}
		return undef;
	}
	elsif ($ot == 240) { # Wind

#	+++++++ 65 D0_VALUE_ACK
#	+++++++ 29 Windgeschwindigkeit
#   +++++++ 01 USE_FROMEL

		my $ddata1 = "652907";
		
		if (defined $value) {
		 $cmd = $value; 
		 readingsSingleUpdate($hash, "wind", "$cmd km/h", 1);
		}
		else {
		 ($cmd, undef) = split(/ /, ReadingsVal($name , "wind","")); }

		if (defined $cmd) {
			my $cs = $cmd*8;

			$ddata1 = $ddata1.sprintf ("%02X", ($cs>>8) );	
			$ddata1 = $ddata1.sprintf ("%02X", ( $cs & 0xff ) );	
			$ddata = sprintf ("%02x%s", (length($ddata1)/2), $ddata1);

			Log3 $hash, 5, "N4MODULE (set wind): $name to $cmd - $ddata, $ddata1, $ipdst";
			IOWrite($hash, 32767, $ddata, $ipdst);
		}
		return undef;
	}
	elsif ($ot == 242) { # Luftdruck

#	+++++++ 65 D0_VALUE_ACK
#	+++++++ 30 Luftdruck
#   +++++++ 01 USE_FROMEL

		my $ddata1 = "653001";
		
		if (defined $value) {
		 $cmd = $value; 
		 readingsSingleUpdate($hash, "pressure", "$cmd hPas", 1);
		}
		else {
		 ($cmd, undef) = split(/ /, ReadingsVal($name , "pressure","")); }

		if (defined $cmd) {
			my $cs = $cmd*10;

			$ddata1 = $ddata1.sprintf ("%02X", ($cs>>8) );	
			$ddata1 = $ddata1.sprintf ("%02X", ( $cs & 0xff ) );	
			$ddata = sprintf ("%02x%s", (length($ddata1)/2), $ddata1);

			Log3 $hash, 5, "N4MODULE (set pressure): $name to $cmd - $ddata, $ddata1, $ipdst";
			IOWrite($hash, 32767, $ddata, $ipdst);
		}
		return undef;
	}
	elsif ($ot == 245) { # Regenmenge

#	+++++++ 65 D0_VALUE_ACK
#	+++++++ 35 Regenmenge
#   +++++++ 01 USE_FROMEL

		my $ddata1 = "653508";
		
		if (defined $value) {
		 $cmd = $value; 
		 readingsSingleUpdate($hash, "rain", "$cmd l/h", 1);
		}
		else {
		 ($cmd, undef) = split(/ /, ReadingsVal($name , "rain","")); }

		if (defined $cmd) {
			my $cs = $cmd*10;

			$ddata1 = $ddata1.sprintf ("%02X", ($cs>>8) );	
			$ddata1 = $ddata1.sprintf ("%02X", ( $cs & 0xff ) );	
			$ddata = sprintf ("%02x%s", (length($ddata1)/2), $ddata1);

			Log3 $hash, 5, "N4MODULE (set rain): $name to $cmd - $ddata, $ddata1, $ipdst";
			IOWrite($hash, 32767, $ddata, $ipdst);
		}
		return undef;
	}
	elsif ($ot == 999) { # N56

#	+++++++ 65 D0_SENSOR_ACK (41)

		my $ddata1 = "41";
		
		if (defined $value) {
			$cmd = $value; 
#			$cmd = N4HMODULE_ParseN56(substr($hash->{READINGS}{ddata},2,18));
			readingsSingleUpdate($hash, "value", "$cmd", 1);
		} else{
			return undef; 
		}
		
			my $n56 = N4HMODULE_CreateN56($value,0,0,0,2);
			$ddata1 = $ddata1.$n56;
			$ddata = sprintf ("%02x%s", (length($ddata1)/2), $ddata1);

			$ipdst = 1;
			Log3 $hash, 5, "N4MODULE (set N56): $name to $cmd - $ddata, $ddata1, $ipdst, $n56";
			IOWrite($hash, 1, $ddata, $ipdst);
		
		return undef;
	}
	
	return undef;
}	

##################################################################################
sub N4HMODULE_Attr(@) {
##################################################################################
	my ($cmd,$name,$attr_name,$attr_value) = @_;
	if($cmd eq "set") {

		if($attr_name eq "Interval") {
			if (($attr_value < 30) or ($attr_value > 86400)) {
			    my $err = "Invalid time $attr_value to $attr_name. Must be > 30 and < 86400.";
			    return $err;
			}
		}
	}

	return undef;
}

##################################################################################
sub N4HMODULE_CreateN56(@) {
##################################################################################

 my ($val32,$exp8,$expb,$findex,$decimal) = @_;
 my $ddata    = "";
 my $myformel = "";
 
# print "\n".$val32*($expb**$exp8)."\n";
 my $unsigned = $val32 < 0 ? 2 ** 32 + $val32 : $val32;
 my $myddata  = sprintf("%08X", $unsigned);
 my $ps 	  = $exp8 < 0 ? 2 ** 8 + $exp8 : $exp8;
 
 $myformel = sprintf("%04X",$findex);
 $ddata    = substr($myddata,6,2).substr($myddata,4,2).substr($myddata,2,2).substr($myddata,0,2).sprintf("%02X",$ps).substr($myformel,2,2).substr($myformel,0,2).sprintf("%02X",$decimal).sprintf("%02X",$expb);

 return ($ddata); 
}

##################################################################################
sub N4HMODULE_ParseN56($) {
##################################################################################

 my ($n56) = @_;

 
 my $exp8   = hex(substr($n56,8,2));
 my $val32  = hex(substr($n56,6,2).substr($n56,4,2).substr($n56,2,2).substr($n56,0,2));
 my $expb   = hex(substr($n56,16,2));
 my $formel = hex(substr($n56,10,2)).hex(substr($n56,12,2));;
 my $deci   = hex(substr($n56,14,2));

 $exp8  = $exp8  >>  7 ? $exp8  - 2 **  8 : $exp8;
 $val32 = $val32 >> 31 ? $val32 - 2 ** 32 : $val32;
 
 if ($expb eq 0) {
	$expb = 10;
 } elsif ($expb eq 1) {
	$expb = 2;
 }

 my $ddata = sprintf("Wert: %.".$deci."f", ($val32*($expb**$exp8)))." (Formel: $formel)";
 
 return ($ddata); 
}


##################################################################################


##################################################################################


1;

=pod
=item device
=item summary Module to emulate net4home Actors and Sensors via N4HBUS
=item summary_DE Modul zum emulieren von net4home Aktoren und Sensoren ueber N4HBUS
=begin html

<a name="N4HMODULE"></a>
<h3>N4HMODULE</h3>
 fhem-Module to communicate with net4home modules via IP
 <br /><br />

<ul>
  <br />
  <a name="N4HMODULE_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; N4HMODULE &lt;device&gt; &lt;type&gt; &lt;objectaddress&gt;</code><br />
    <br />

    Defines a net4home device connected to a <a href="#N4HBUS">N4HBUS</a> device <br /><br />

    Examples:

    <ul>
      <code>define n4h_28204 N4HMODULE n4h 24 28204</code><br />
    </ul>

	Currently the following values are supported:

	<b>Measurement</b>
	<ul>
	 <li> 24 - Measurement,Temperature</li>
	 <li> 25 - Measurement,Brightness</li>
	 <li> 26 - Measurement,Humidity</li>
	 <li>240 - Measurement,Wind</li>
	 <li>242 - Measurement,Pressure</li>
	 <li>245 - Measurement,Rain</li>
	</ul>
  </ul><br />

  <a name="N4HMODULE_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>The readings are dependent of the object of the net4home bus module.<br /></li>
  </ul><br />
  <a name="N4HMODULE_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>interval<br>
      the interval in seconds used to send values to bus.</li>
  </ul>
</ul>

=end html

=begin html_DE

<a name="N4HMODULE"></a>
<h3>N4HMODULE</h3>
 fhem-Modul zur Kommunikation mit dem net4home Bus über IP
 <br /><br />

<ul>
  <br />
  <a name="N4HMODULE_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; N4HMODULE &lt;device&gt; &lt;type&gt; &lt;objectaddress&gt;</code><br />
    <br />

	Erstellt ein net4home Modul-Device welches mit dem <a href="#N4HBUS">N4HBUS</a> Device kommuniziert.

    Beispiel:
    <ul>
      <code>define MyN4HMODULEice N4HMODULE 24 26004</code><br />
    </ul>
	
	Derzeit werden folgende Typen unterst&uuml;tzt:

	<b>Messwerte</b>
	<ul>
	 <li> 24 - Messwert,Temperatur</li>
	 <li> 25 - Messwert,Helligkeit</li>
	 <li> 26 - Messwert,Feuchte</li>
	 <li>240 - Messwert,Wind</li>
	 <li>242 - Messwert,Luftdruck</li>
	 <li>245 - Messwert,Regenmenge</li>
	</ul>

	</ul><br />

  <a name="N4HMODULE_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>Die Readings werden Abhängig vom Modultyp angegeben.<br /></li>
  </ul><br />

    <a name="N4HMODULE_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>Interval<br>
      Das Interval bestimmt bei Messwerten die Zeit zwischen dem Senden der Daten auf den Bus. Ist kein Attribut definiert, so wird der Standardwert genutzt.</li>
  </ul>


</ul>
=end html_DE

=cut
