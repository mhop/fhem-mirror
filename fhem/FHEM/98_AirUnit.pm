# $Id$
##############################################################################
#
#     98_AirUnit.pm
#     An FHEM Perl module for controlling Danfoss AirUnits (a1,a2,w1,w2).
#
#     Copyright by René Dommerich & Ulf von Mersewsky
#     e-mail: rdommerich at gmx punkt com
#     e-mail: umersewsky at gmail punkt com
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package FHEM::AirUnit;

use GPUtils         qw(:all);
use strict;
use warnings;

require DevIo;

BEGIN {
    GP_Import( qw(
		AttrVal
		CommandAttr
		readingsSingleUpdate
		readingsBeginUpdate
		readingsBulkUpdate
		readingsEndUpdate
		readingFnAttributes
        ReadingsVal
		Log3
		gettimeofday
		InternalVal
		InternalTimer
		RemoveInternalTimer
		TimeNow
		time_str2num
        Value
    ));
};

GP_Export(
    qw(
        Initialize
    )
);

my $Version = '0.0.5.9 - Jul 2023';

####################### GET Paramter ################################################  
# Das sind die Zahlen die gesendet werden müssen, damit man die Informationen erhält.
#####################################################################################

my @OUTDOOR_TEMPERATURE = (0x01, 0x04, 0x03, 0x34);     #### REGISTER_1_READ, OUTDOOR_TEMPERATURE
my @ROOM_TEMPERATURE = (0x01, 0x04, 0x03, 0x00);        #### REGISTER_1_READ, ROOM_TEMPERATURE
my @SUPPLY_TEMPERATURE = (0x01, 0x04, 0x14, 0x73);      #### REGISTER_1_READ, SUPPLY_TEMPERATURE / ZULUFT
my @EXTRACT_TEMPERATURE = (0x01, 0x04, 0x14, 0x74);     #### REGISTER_1_READ, EXTRACT_TEMPERATURE / ABLUFT
my @EXHAUST_TEMPERATURE = (0x01, 0x04, 0x14, 0x75);     #### REGISTER_1_READ, EXHAUST_TEMPERATURE

my @HUMIDITY = (0x01, 0x04, 0x14, 0x70);                #### REGISTER_1_READ, HUMIDITY
my @FAN_SPEED_SUPPLY = (0x04, 0x04, 0x14, 0x28);        #### REGISTER_1_READ, FAN_SPEED_SUPPLY
my @FAN_SPPED_EXTRACT = (0x04, 0x04, 0x14, 0x29);       #### REGISTER_1_READ, FAN_SPPED_EXTRACT
my @AIR_INPUT = (0x01, 0x04, 0x14, 0x40);               #### REGISTER_1_READ, AIR_INPUT
my @AIR_OUTPUT = (0x01, 0x04, 0x14, 0x41);              #### REGISTER_1_READ, AIR_OUTPUT
my @BATTERY_LIFE = (0x01, 0x04, 0x03, 0x0f);            #### REGISTER_1_READ, BATTERY_LIFE
my @FILTER_LIFE = (0x01, 0x04, 0x14, 0x6a);             #### REGISTER_1_READ, FILTER_LIFE

my @BOOST = (0x01, 0x04, 0x15, 0x30);                   #### REGISTER_1_READ, BOOST ON/OFF
my @BOOST_AUTOMATIC = (0x01, 0x04, 0x17, 0x02);         #### REGISTER_1_READ, BOOST_AUTOMATIC ON/OFF
my @BOOST_DURATION = (0x01, 0x04, 0x15, 0x31);          #### REGISTER_1_READ, BOOST_DURATION
my @BYPASS = (0x01, 0x04, 0x14, 0x60);                  #### REGISTER_1_READ, BYPASS
my @BYPASS_AUTOMATIC = (0x01, 0x04, 0x17, 0x06);        #### REGISTER_1_READ, BYPASS_AUTOMATIC ON/OFF
my @BYPASS_DURATION = (0x01, 0x04, 0x14, 0x62);         #### REGISTER_1_READ, BYPASS_DURATION

my @NIGHTCOOLING = (0x01, 0x04, 0x15, 0x71);            #### REGISTER_1_READ, NIGHTCOOLING ON/OFF
my @FIREPLACE = (0x01, 0x04, 0x17, 0x07);               #### REGISTER_1_READ, FIREPLACE ON/OFF
#my @COOKERHOOD = (0x01, 0x04, 0x15, 0x34);				#### REGISTER_1_READ, COOKERHOOD ON/OFF

my @MODE = (0x01, 0x04, 0x14, 0x12);                    #### REGISTER_1_READ, MODE
my @FAN_STEP = (0x01, 0x04, 0x15, 0x61);                #### REGISTER_1_READ, FANSPEED / FANSTUFE in MANUELL - MODE

my @FANSPEED_IN_RPM = (0x04, 0x04, 0x14, 0x50);         #### REGISTER_4_READ, FANSPEED_IN_RPM
my @FANSPEED_OUT_RPM = (0x04, 0x04, 0x14, 0x51);        #### REGISTER_4_READ, FANSPEED_OUT_RPM

my @MODEL = (0x01, 0x04, 0x15, 0xe5);                   #### REGISTER_1_READ, MODEL
my @MODEL_SN = (0x04, 0x04, 0x00, 0x25);                #### REGISTER_4_READ, MODEL SERIALNUMBER
my @OPERATION_TIME = (0x00, 0x04, 0x03, 0xe0);          #### REGISTER_0_READ, OPERATION_TIME

####################### SET Paramter ##################################################################
# Das sind die Zahlen die gesendet werden müssen + eine 5. (die Option), damit man etwas bewirken kann.
#######################################################################################################

my @W_BOOST = (0x01, 0x06, 0x15, 0x30);                     #### REGISTER_1_WRITE, BOOST ON/OFF
my @W_BYPASS = (0x01, 0x06, 0x14, 0x60);                    #### REGISTER_1_WRITE, BYPASS ON/OFF
my @W_NIGHTCOOLING = (0x01, 0x06, 0x15, 0x71);              #### REGISTER_1_WRITE, NIGHTCOOLING ON/OFF
my @W_DISABLE_BOOST_AUTOMATIC = (0x01, 0x06, 0x17, 0x02);   #### REGISTER_1_WRITE, BOOST_AUTOMATIC ON/OFF
my @W_DISABLE_BYPASS_AUTOMATIC = (0x01, 0x06, 0x17, 0x06);  #### REGISTER_1_WRITE, BYPASS_AUTOMATIC ON/OFF
my @W_MODE = (0x01, 0x06, 0x14, 0x12);                      #### REGISTER_1_WRITE, MODE
my @W_FAN_STEP = (0x01, 0x06, 0x15, 0x61);                  #### REGISTER_1_WRITE, FAN_STEP
my @W_FIREPLACE = (0x01, 0x06, 0x17, 0x07);                 #### REGISTER_1_WRITE, FIREPLACE ON/OFF
#my @W_COOKERHOOD = (0x01, 0x06, 0x15, 0x34);				#### REGISTER_1_WRITE, COOKERHOOD ON/OFF
my @W_BOOST_DURATION = (0x01, 0x06, 0x15, 0x31);            #### REGISTER_1_READ, BOOST_DURATION
my @W_BYPASS_DURATION = (0x01, 0x06, 0x14, 0x62);           #### REGISTER_1_READ, BYPASS_DURATION


########################################

sub Initialize()
{
    my ($hash) = @_;

    $hash->{DefFn}    = \&Define;         # definiert das Gerät
    $hash->{UndefFn}  = \&Undefine;       # legt fest, was alles mein löschen gemacht wird
    $hash->{GetFn}    = \&Get;            # nicht wirklich benötigt, eher ein TEST, viell. fällt mir noch was ein
    $hash->{SetFn}    = \&Set;            # dient zum setzen der SET Paramter
    $hash->{ReadFn}   = \&Read;           # wird von DevIO beim Nachrichteneingang gerufen
    $hash->{ReadyFn}  = \&Ready;          # wird von DevIO bei Kommunikationsproblemen gerufen
    $hash->{AttrFn}   = \&Attr;           # nur kopiert und angepasst
    $hash->{AttrList} = "disable:0,1 ".
                        $readingFnAttributes;

    return;
}

########################################

sub Define(){
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);

    return "Usage: define <name> AirUnit <ip-address:port> [poll-interval]" 
    if(@a <3 || @a >4);

    my $name = $a[0];
    my $host = $a[2];
    my $port = 30046;

    my $interval = 5*60;
    $interval = $a[3] if(@a == 4);
    $interval = 30 if( $interval < 30 );

    $hash->{NAME} = $name;
    $hash->{ModuleVersion} = $Version;

    $hash->{STATE} = "Initializing";
    if ( $host =~ /(.*):(.*)/xms ) {
        $host = $1;
        $port = $2;
    }
    $hash->{INTERVAL} = $interval;
    $hash->{NOTIFYDEV} = "global";
    $hash->{DeviceName} = join(':', $host, $port);
    $hash->{devioLoglevel} = 4;

	$hash->{helper}{commandQueue} = [];
 
	InitCommands($hash);

    ::DevIo_CloseDev($hash) if ( ::DevIo_IsOpen($hash) );

    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+2, \&GetUpdate, $hash, 0);

    return;
}

########################################

sub Undefine() {
    my ($hash, $arg) = @_;

    RemoveInternalTimer($hash);     # Timer wird gelöscht
    ::DevIo_CloseDev($hash);

    return;
}

########################################
# called repeatedly if device disappeared

sub Ready()
{
    my ($hash) = @_;
    my $name = $hash->{NAME};

    # reset command queue
    $hash->{helper}{commandQueue} = [];

    # try to reopen the connection in case the connection is lost and Attribute disable = 0
    if (AttrVal($name, "disable", 0) == 0) {
        return ::DevIo_OpenDev($hash, 1, undef, \&sendNextRequest);
    }

    return;
}

########################################
# called when data was received

sub Read()
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $commands = $hash->{helper}{commandHash};

    # read the available data
    my $buf = ::DevIo_SimpleRead($hash);
    
    # stop processing if no data is available (device disconnected)
    return if(!defined($buf));
    
    Log3($name, 4, "AirUnit $name: received: ".unpack('H*', $buf));

    my $lastCmd = InternalVal($name, 'LastCommand', '');
    
	if ($lastCmd =~ /0106.*/xms && $buf =~ /\x00{63}/xms) {
		# received answer from Set command
        Log3($name, 4, "AirUnit $name: command performed: $lastCmd");
	} elsif (defined($commands->{$lastCmd})) {
        $commands->{$lastCmd}->($hash, $buf);
    } else {
        Log3($name, 4, "AirUnit $name: handling of command not defined: $lastCmd");
    }

    sendNextRequest($hash);

    return;
}

########################################

sub Get() {
    my ($hash, $name, $cmd, @val) = @_;
	
	if ($cmd ne '?' && AttrVal($name, 'disable', 0) == 1) {
		Log3($name, 3, "AirUnit $name: disabled, ignore : get $name $cmd");
		return;
    } elsif($cmd eq 'update') {
        DoUpdate($hash);
        return;
    }

    my $list = " update:noArg";
        
    return "Unknown argument $cmd, choose one of $list";      
}

########################################

sub Set() {
    my ($hash, $name, $cmd, $val) = @_;
    my @w_settings;

	if ($cmd ne '?' && AttrVal($name, 'disable', 0) == 1) {
		Log3($name, 3, "AirUnit $name: disabled, ignore : set $name $cmd $val");
		return;
	} elsif($cmd eq 'Modus') {
      Log3($name, 3, "AirUnit $name: set $name $cmd $val");
		if($val eq "Bedarfsmodus"){
			@w_settings = (@W_MODE, 0x00);
		}elsif($val eq "Programm"){
			@w_settings = (@W_MODE, 0x01);
		}elsif($val eq "Manuell"){
			@w_settings = (@W_MODE, 0x02);
		}elsif($val eq "Aus"){
			@w_settings = (@W_MODE, 0x03);
		}else {
			return "Fehlerhafter Paramter: set $name $cmd $val";
		}
		DoChange($hash, \@w_settings, \@MODE);
		return;
	}
	elsif ($cmd eq 'Luefterstufe') {
		Log3($name, 3, "AirUnit $name: set $name $cmd $val");
		my $myMode = ReadingsVal($name, "Modus" , "");
		Log3($name, 3, "AirUnit $name: Modus: $myMode");
		if (($val <= 10 || $val >= 1) and $myMode eq "Manuell"){
			@w_settings = (@W_FAN_STEP, $val);
			DoChange($hash, \@w_settings, \@FAN_STEP);
		}else{
			return "Lueftung ist nicht im manuellen Modus.";
		}
		return;
	}
    elsif ($cmd eq 'Stosslueftung'){
		Log3($name, 3, "AirUnit $name: set $name $cmd $val");
		if($val eq "on"){
			@w_settings = (@W_BOOST, 0x01);
		}elsif($val eq "off"){
			@w_settings = (@W_BOOST, 0x00);
		}else {
			return "Fehlerhafter Paramter $val für Setting $cmd\n";
		}
		DoChange($hash, \@w_settings, \@BOOST);
		return;
		}
	elsif ($cmd eq 'Bypass'){
		Log3($name, 3, "AirUnit $name: set $name $cmd $val");
		if($val eq "on"){
			@w_settings = (@W_BYPASS, 0x01);
		}elsif($val eq "off"){
			@w_settings = (@W_BYPASS, 0x00);
		}else {
			return "Fehlerhafter Paramter $val für Setting $cmd\n";
		}
		DoChange($hash, \@w_settings, \@BYPASS);
		return;
	}
	elsif ($cmd eq 'Nachtkuehlung'){
		Log3($name, 3, "AirUnit $name: set $name $cmd $val");
		if($val eq "on"){
			@w_settings = (@W_NIGHTCOOLING, 0x01);
		}elsif($val eq "off"){
			@w_settings = (@W_NIGHTCOOLING, 0x00);
		}else {
			return "Fehlerhafter Paramter $val für Setting $cmd\n";
		}
		DoChange($hash, \@w_settings, \@NIGHTCOOLING);
		return;
	}
	elsif ($cmd eq 'Feuerstaette'){
		Log3($name, 3, "AirUnit $name: set $name $cmd $val");
		if($val eq "on"){
			@w_settings = (@W_FIREPLACE, 0x01);
		}elsif($val eq "off"){
			@w_settings = (@W_FIREPLACE, 0x00);
		}else {
			return "Fehlerhafter Paramter $val für Setting $cmd\n";
		}
		DoChange($hash, \@w_settings, \@FIREPLACE);
		return;
	}
	# elsif ($cmd eq 'Dunstabzugshaube'){
		# Log3($name, 3, "AirUnit $name: set $name $cmd $val");
		# if($val eq "on"){
			# @w_settings = (@W_COOKERHOOD, 0x01);
		# }elsif($val eq "off"){
			# @w_settings = (@W_COOKERHOOD, 0x00);
		# }else {
			# return "Fehlerhafter Paramter $val für Setting $cmd\n";
		# }
		# #setONOFF($hash, @w_settings);
		# sendRequest($hash, @w_settings);
		# return undef;
	# }
	elsif ($cmd eq 'automatische_Stosslueftung'){
		Log3($name, 3, "AirUnit $name: set $name $cmd $val");
		if($val eq "on"){
			@w_settings = (@W_DISABLE_BOOST_AUTOMATIC, 0x00);
		}elsif($val eq "off"){
			@w_settings = (@W_DISABLE_BOOST_AUTOMATIC, 0x01);
		}else {
			return "Fehlerhafter Paramter $val für Setting $cmd\n";
		}
		DoChange($hash, \@w_settings, \@BOOST_AUTOMATIC);
		return;
	}
	elsif ($cmd eq 'automatischer_Bypass'){
		Log3($name, 3, "AirUnit $name: set $name $cmd $val");
		if($val eq "on"){
			@w_settings = (@W_DISABLE_BYPASS_AUTOMATIC, 0x00);
		}elsif($val eq "off"){
			@w_settings = (@W_DISABLE_BYPASS_AUTOMATIC, 0x01);
		}else {
			return "Fehlerhafter Paramter $val für Setting $cmd\n";
		}
		DoChange($hash, \@w_settings, \@BYPASS_AUTOMATIC);
		return;
	}
	elsif ($cmd eq 'Stosslueftung_Dauer'){
		Log3($name, 3, "AirUnit $name: set $name $cmd $val");
		if($val <= 23 || $val >= 1){
			@w_settings = (@W_BOOST_DURATION, $val);
		}else {
			return "Fehlerhafter Paramter $val für Setting $cmd\n";
		}
		DoChange($hash, \@w_settings, \@BOOST_DURATION);
		return;
	}
	elsif ($cmd eq 'Bypass_Dauer'){
		Log3($name, 3, "AirUnit $name: set $name $cmd $val");
		if($val <= 23 || $val >= 1){
			@w_settings = (@W_BYPASS_DURATION, $val);
		}else {
			return "Fehlerhafter Paramter $val für Setting $cmd\n";
		}
		DoChange($hash, \@w_settings, \@BYPASS_DURATION);
		return;
	}
	elsif($cmd eq 'Intervall' && defined($val) ) {
      Log3($name, 3, "AirUnit $name: set $name $cmd $val");
      $val = 30 if( $val < 30 );
      $hash->{INTERVAL} = $val;
      return "Intervall wurde auf $val Sekunden gesetzt.";
   }
	
	my $list = " Modus:Bedarfsmodus,Programm,Manuell,Aus "
		." Luefterstufe:slider,1,1,10 "
		." Stosslueftung:on,off "
		." Bypass:on,off "
		." Nachtkuehlung:on,off "
		." Feuerstaette:on,off "
#		." Dunstabzugshaube:on,off "
		." automatische_Stosslueftung:on,off "
		." automatischer_Bypass:on,off "
		." Stosslueftung_Dauer:slider,1,1,23 "
		." Bypass_Dauer:slider,1,1,23 "
		." Intervall";
          
    return "Unknown argument $cmd, choose one of $list";
}

######################################## 	

sub Attr() {
    
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $::defs{$name};

    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    if ($cmd eq 'set') {
        if ($aName eq 'disable') {
            if ($aVal == 0) {
                readingsSingleUpdate($hash, 'state', 'Initializing', 1) if (Value($name) ne 'opened');
            } elsif ($aVal == 1) {
                readingsSingleUpdate($hash, 'state', 'disabled', 1);
            } else {
                return "Invalid allowSetParameter $aVal";
            }
        }
    }

    if ($cmd eq 'del') {
        if ($aName eq 'disable' && AttrVal($name, $aName, 0) == 1) {
            readingsSingleUpdate($hash, 'state', 'Initializing', 1);
        }
    }

    return;
}

########################################

sub GetUpdate() {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $interval = $hash->{INTERVAL};

    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$interval, \&GetUpdate, $hash, 0);
    return if( AttrVal($name, "disable", 0 ) == 1 );

    DoUpdate($hash);

    return;
}

########################################

sub DoUpdate(){
    my ($hash) = @_;
    my $name = $hash->{NAME};
	my $lastCmdTs = $hash->{LastCommandTS};
    my $queueRef = $hash->{helper}{commandQueue};
    my $orgQueueCount = @$queueRef;
	
	my $elapsedTime = int(gettimeofday() - time_str2num($lastCmdTs));
	if($orgQueueCount > 0 && $elapsedTime > $hash->{INTERVAL} * 2) {
		Log3($name, 3, "AirUnit $name: reset command queue, timeout after $elapsedTime seconds");
		$queueRef = [];
		$orgQueueCount = 0;
	}

    # Update readings
 
    # get_Temperature_Value

    push(@$queueRef, \@OUTDOOR_TEMPERATURE);
    push(@$queueRef, \@ROOM_TEMPERATURE);
    push(@$queueRef, \@SUPPLY_TEMPERATURE);
    push(@$queueRef, \@EXTRACT_TEMPERATURE);
    push(@$queueRef, \@EXHAUST_TEMPERATURE);

    # get_Value_in_Percent

    push(@$queueRef, \@HUMIDITY);
    push(@$queueRef, \@AIR_INPUT);
    push(@$queueRef, \@AIR_OUTPUT);
    push(@$queueRef, \@FAN_SPEED_SUPPLY);
    push(@$queueRef, \@FAN_SPPED_EXTRACT);

    # get_Lifetimes_in_Percent

    push(@$queueRef, \@FILTER_LIFE);
    push(@$queueRef, \@BATTERY_LIFE);

    # get_ON_or_OFF_Value

    push(@$queueRef, \@BOOST);
    push(@$queueRef, \@BYPASS);
    push(@$queueRef, \@NIGHTCOOLING);
    push(@$queueRef, \@FIREPLACE);
    push(@$queueRef, \@BOOST_AUTOMATIC);
    push(@$queueRef, \@BYPASS_AUTOMATIC);

    # get_FanSpeed_in_RPM

    push(@$queueRef, \@FANSPEED_IN_RPM);
    push(@$queueRef, \@FANSPEED_OUT_RPM);

    # get_Value

    push(@$queueRef, \@MODE);
    push(@$queueRef, \@FAN_STEP);
	push(@$queueRef, \@BOOST_DURATION);
    push(@$queueRef, \@BYPASS_DURATION);
	push(@$queueRef, \@OPERATION_TIME);

    #get_String

    push(@$queueRef, \@MODEL)    if (InternalVal($name, 'Model', '') eq '');
    push(@$queueRef, \@MODEL_SN) if (InternalVal($name, 'Seriennummer', '') eq '');

    sendNextRequest($hash) if ($orgQueueCount == 0);

    return;
}

sub DoChange(){
    my ($hash,$writeRef,$readRef) = @_;
    my $name = $hash->{NAME};
    my $queueRef = $hash->{helper}{commandQueue};
    my $orgQueueCount = @$queueRef;

    push(@$queueRef, $writeRef);
    push(@$queueRef, $readRef);

    sendNextRequest($hash) if ($orgQueueCount == 0);

    return;
}

sub InitCommands() {
	my ($hash) = @_;
	my %commands;

	# map commands to actions
	$commands{getCommandKey(@OUTDOOR_TEMPERATURE)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Aussenluft_Temperatur", getTemperatur($subHash, $buf), 1);
	};
	$commands{getCommandKey(@ROOM_TEMPERATURE)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Raumluft_Temperatur_AirDail", getTemperatur($subHash, $buf), 1);
	};
	$commands{getCommandKey(@SUPPLY_TEMPERATURE)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Zuluft_Temperatur", getTemperatur($subHash, $buf), 1);
	};
	$commands{getCommandKey(@EXTRACT_TEMPERATURE)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Abluft_Temperatur", getTemperatur($subHash, $buf), 1);
	};
	$commands{getCommandKey(@EXHAUST_TEMPERATURE)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Fortluft_Temperatur", getTemperatur($subHash, $buf), 1);
	};
	$commands{getCommandKey(@HUMIDITY)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Luftfeuchtigkeit", getHumidity($subHash, $buf), 1);
	};
	$commands{getCommandKey(@AIR_INPUT)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Zuluft_Grundstufe_Einstellung", getAirInputOutput($subHash, $buf), 1);
	};
	$commands{getCommandKey(@AIR_OUTPUT)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Abluft_Grundstufe_Einstellung", getAirInputOutput($subHash, $buf), 1);
	};
	$commands{getCommandKey(@FAN_SPEED_SUPPLY)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Zuluft_Stufe", getAirInputOutput($subHash, $buf), 1);
	};
	$commands{getCommandKey(@FAN_SPPED_EXTRACT)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Abluft_Stufe", getAirInputOutput($subHash, $buf), 1);
	};
	$commands{getCommandKey(@FILTER_LIFE)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "verbl.Filterlebensdauer", getFilterLifeTime($subHash, $buf), 1);
	};
	$commands{getCommandKey(@BATTERY_LIFE)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "verbl.Batterielebensdauer_AirDial", getBatteryLifeTime($subHash, $buf), 1);
	};
	$commands{getCommandKey(@BOOST)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Stosslueftung_aktiviert", getONOFF($subHash, $buf), 1);
	};
	$commands{getCommandKey(@BYPASS)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Bypass_aktiviert", getONOFF($subHash, $buf), 1);
	};
	$commands{getCommandKey(@NIGHTCOOLING)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Nachtkuehlung_aktiviert", getONOFF($subHash, $buf), 1);
	};
	$commands{getCommandKey(@FIREPLACE)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Feuerstaette_aktiviert", getONOFF($subHash, $buf), 1);
	};
	$commands{getCommandKey(@BOOST_AUTOMATIC)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "automatische_Stosslueftung", getOFFON($subHash, $buf), 1);
	}; 
	$commands{getCommandKey(@BYPASS_AUTOMATIC)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "automatischer_Bypass", getOFFON($subHash, $buf), 1);
	};
	$commands{getCommandKey(@FANSPEED_IN_RPM)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Zuluft_Luefterdrehzahl", getFanSpeedInRPM($subHash, $buf), 1);
	};
	$commands{getCommandKey(@FANSPEED_OUT_RPM)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Abluft_Luefterdrehzahl", getFanSpeedInRPM($subHash, $buf), 1);
	};
	$commands{getCommandKey(@MODE)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Modus", getMode($subHash, $buf), 1);
	};
	$commands{getCommandKey(@FAN_STEP)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Luefterstufe_manuell", getFanSpeed($subHash, $buf), 1);
	};
	$commands{getCommandKey(@BOOST_DURATION)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Stosslueftung_Dauer", getDurationTime($subHash, $buf), 1);
	};
	$commands{getCommandKey(@BYPASS_DURATION)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Bypass_Dauer", getDurationTime($subHash, $buf), 1);
	};
	$commands{getCommandKey(@OPERATION_TIME)} = sub {
		my ($subHash,$buf) = @_;
		readingsSingleUpdate( $subHash, "Arbeitsstunden", getOperationTime($subHash, $buf), 1);
	};

	# Internals
	$commands{getCommandKey(@MODEL)} = sub {
		my ($subHash,$buf) = @_;
		$subHash->{Model} = getModel($subHash, $buf);
	};
	$commands{getCommandKey(@MODEL_SN)} = sub {
		my ($subHash,$buf) = @_;
		$subHash->{Seriennummer} = getModelSN($subHash, $buf);
	};

	$hash->{helper}{commandHash} = \%commands;

	return;
}

########################################
############# GET Methoden #############
########################################

sub getTemperatur() {
    # read Temperaturen in Grad
    my ($hash,$data) = @_;
    my $name = $hash->{NAME};

    my $tempresponse = unpack("H*" , substr($data,0,2));
    Log3($name, 5, "AirUnit $name: recvunpackData in getTemperatur(): $tempresponse\n");

	# handle negative values
    my $temperature = unpack('s', pack('S', hex($tempresponse)));
	# handle invalid value
	return 'NaN' if ($temperature == -32768);

    return sprintf ('%.02f', $temperature/100);
}

sub getHumidity() {
    # read Luftfeuchtigkeit in Prozent
    my ($hash,$data) = @_;
    my $name = $hash->{NAME};

    my $tempresponse = unpack("H*" , substr($data,0,1));
    Log3($name, 5, "AirUnit $name: recvunpackData in getHumidity(): $tempresponse\n");
    my $humidity = hex($tempresponse) * 100 / 255;
    return sprintf ('%.02f', $humidity);
}

sub getAirInputOutput() {
    # read in AIR_INPUT / AIR_OUTPUT und FAN_SPEED_SUPPLY / FAN_SPPED_EXTRACT in Prozent
    my ($hash,$data) = @_;
    my $name = $hash->{NAME};

    my $tempresponse = unpack("H*" , substr($data,0,1));
    Log3($name, 5, "AirUnit $name: recvunpackData in getAirInputOutput(): $tempresponse\n");
    my $inputoutput = hex($tempresponse);
    return $inputoutput;
}

sub getBatteryLifeTime() {
    # read verbleibende Lebensdauer der Batterien im AirDail-Controller
    my ($hash,$data) = @_;
    my $name = $hash->{NAME};

    my $tempresponse = unpack("H*" , substr($data,0,1));
    Log3($name, 5, "AirUnit $name: recvunpackData in getBatteryLifeTime(): $tempresponse\n");
    my $batterylifetime = hex($tempresponse);
    return sprintf ('%.02f', $batterylifetime);
}

sub getFilterLifeTime() {
    # read verbleibende Lebensdauer der Filter in Prozent
    my ($hash,$data) = @_;
    my $name = $hash->{NAME};

    my $tempresponse = unpack("H*" , substr($data,0,1));
    Log3($name, 5, "AirUnit $name: recvunpackData in getFilterLifeTime(): $tempresponse\n");
    my $filterlifetime = hex($tempresponse) * 100 / 255;
    return sprintf ('%.02f', $filterlifetime);
}

sub getONOFF() {
	# read true/1/ON or false/0/OFF for BOOST, BYPASS, NIGHTCOOLING, FIREPLACE
	my ($hash,$data) = @_;
	my $name = $hash->{NAME};

	my $onoff = hex(unpack("H*" , substr($data,0,1)));
	Log3($name, 5, "AirUnit $name: recvunpackData in getONOFF(): $onoff\n");
	if($onoff == 1){
		return "An"
	}elsif($onoff == 0){
		return "Aus"
	}elsif($onoff == 255){  #für aktueller Status des Bypasses (aktiv)
		return "An"
	}else {
		Log3($name, 1,  "AirUnit $name: Unbekannter Paramter in getONOFF(): $onoff\n");
	}

	return;
}

sub getOFFON() {
	# read true/1/OFF or false/0/ON for DISABLE_BOOST_AUTOMATIC, DISABLE_BOOST_AUTOMATIC
	my ($hash,$data) = @_;
	my $name = $hash->{NAME};

	my $offon = hex(unpack("H*" , substr($data,0,1)));
	Log3($name, 5, "AirUnit $name: recvunpackData in getOFFON(): $offon\n");
	if($offon == 0){
		return "An"
	}elsif($offon == 1){
		return "Aus"
	}else {
		Log3($name, 1,  "AirUnit $name: Unbekannter Paramter in getOFFON(): $offon\n");
	}

	return;
}

sub getFanSpeedInRPM() {
    # read aktuelle Lüftergeschwindigkeit in U/min
    my ($hash,$data) = @_;
    my $name = $hash->{NAME};

    my $tempresponse = unpack("H*" , substr($data,0,2));
    Log3($name, 5, "AirUnit $name: recvunpackData in getFanSpeedInRPM(): $tempresponse\n");
    my $fanspeedinrpm = hex($tempresponse);
    return $fanspeedinrpm;
}

sub getFanSpeed() {
    # read aktuelle Lüftergeschwindigkeit in Stufen von 1-10
    my ($hash,$data) = @_;
    my $name = $hash->{NAME};

    my $tempresponse = unpack("H*" , substr($data,0,1));
    Log3($name, 5, "AirUnit $name: recvunpackData in getFanspeed(): $tempresponse\n");
    my $fanspeed = hex($tempresponse);
    return $fanspeed;
}

sub getModel() {
    # read Modeltyp
    my ($hash,$data) = @_;
    my $name = $hash->{NAME};

	my $model = unpack("A*" , substr($data,1));
	Log3($name, 5, "AirUnit $name: recvunpackData in getModel(): $model\n");
	return $model;
}

sub getMode() {
    # read Anlagenmodus
    my ($hash,$data) = @_;
    my $name = $hash->{NAME};

    my $tempresponse = unpack("H*" , substr($data,0,1));
    Log3($name, 5, "AirUnit $name: recvunpackData in getMode(): $tempresponse\n");
    my $getmode = hex($tempresponse);
    if($getmode == 0){
        return "Bedarfsmodus"
    }elsif($getmode == 1){
        return  "Programm"
    }elsif($getmode == 2){
        return "Manuell"
    }elsif($getmode == 3){
        return "Aus"
    }else {
        Log3($name, 1, "AirUnit $name: Unbekannter Antwortparamter in getMode(): $getmode\n");
    }
    return;
}

sub getModelSN() {
    # read Seriennummer
    my ($hash,$data) = @_;
    my $name = $hash->{NAME};

    my $tempresponse = unpack("H*" , substr($data,0,2));
    Log3($name, 5, "AirUnit $name: recvunpackData in getModelSN(): $tempresponse\n");
    my $modelsn = hex($tempresponse);
    return $modelsn;
}

sub getDurationTime() {
	# read aktuelle Dauer in Stunden für BYPASS_DURATION and BOOST_DURATION
	my ($hash,$data) = @_;
    my $name = $hash->{NAME};
	
    my $tempresponse = unpack("H*" , substr($data,0,1));
	Log3($name, 5, "AirUnit $name: recvunpackData in getDurationTime(): $tempresponse\n");
    my $getduration = hex($tempresponse);
	return $getduration;
}

sub getOperationTime() {
    # read Arbeitsstunden
    my ($hash,$data) = @_;
    my $name = $hash->{NAME};

    my $tempresponse = unpack("H*", substr($data,0,4));
    Log3($name, 5, "AirUnit $name: recvunpackData in getOperationTime(): $tempresponse\n");
	my $operationtime = hex($tempresponse) / 60;
	return sprintf ('%.01f', $operationtime);
}

sub getCommandKey() {
    my (@command) = @_;
    return unpack('H*', pack('C*' x @command, @command));
}

####################### SEND Request #######################
# VERBINDUNGSAUFBAU ZUR ANLAGE... 
############################################################

# SEND Request
sub sendNextRequest(){
    my ($hash,$error) = @_;
    my $name = $hash->{NAME};
    my $queueRef = $hash->{helper}{commandQueue};

    # create a log entry with the error message
    if ($error) {
        Log3($name, 5, "AirUnit $name: error while connecting: $error");
		return;
    }
 
    # queue is empty / device disabled - nothing to do
    if (!@$queueRef || AttrVal($name, "disable", 0) == 1) {
        $queueRef = [];
		::DevIo_CloseDev($hash);
		return;
	}

	# open connection to send commands
	if (!::DevIo_IsOpen($hash)) {
        my $reopen = Value($name) eq 'opened' ? 1 : 0;
        ::DevIo_OpenDev( $hash, $reopen, undef, \&sendNextRequest);
        return;
	}

    my @nextCmd = @{ shift(@$queueRef) };
    my $data = pack('C*' x @nextCmd, @nextCmd);
    my $unpackedData = unpack('H*', $data);

    Log3($name, 4, "AirUnit $name: sendData in sendRequest(): $unpackedData");
    ::DevIo_SimpleWrite( $hash, $data, 0 );

    $hash->{LastCommand} = $unpackedData;
	$hash->{LastCommandTS} = TimeNow();

    return;
}

1;

=pod
=item summary controls Danfoss AirUnits (a1,a2,w1,w2)
=begin html

<a name="AirUnit"></a>
<h3>AirUnit</h3>
<ul>
    <i>AirUnit</i> implements a FHEM device to control Danfoss AirUnits (a1,a2,w1,w2). Tested only with w2 (Feb 2021). 
    With this module it is possible to control the most useful functions of your ventilation system.
    <br><br>
	
	<table>
	  <tr>
		<th>possible Readings</th>
		<th>units of values</th>
	  </tr>
	  <tr>
		<td>Abluft_Grundstufe_Einstellung</td>
		<td>percent</td>
	   </tr>
	   <tr>
		 <td>Abluft_Luefterdrehzahl</td>
		 <td>rpm</td>
	   </tr>
	   	 <tr>
		 <td>Abluft_Stufe</td>
		 <td>step</td>
	   </tr>
	   	 <tr>
		 <td>Abluft_Temperatur</td>
		 <td>degree</td>
	   </tr>
	   	 <tr>
		 <td>Aussenluft_Temperatur</td>
		 <td>degree</td>
	   </tr>
	   	 <tr>
		 <td>Bypass_aktiviert</td>
		 <td>on/off</td>
	   </tr>
	    <tr>
		 <td>Bypass_Dauer</td>
		 <td>hour</td>
	   </tr>
	   	 <tr>
		 <td>Feuerstaette_aktiviert</td>
		 <td>on/off</td>
	   </tr>
	   	 <tr>
		 <td>Fortluft_Temperatur</td>
		 <td>degree</td>
	   </tr>
	   	 <tr>
		 <td>Luefterstufe_manuell</td>
		 <td>step</td>
	   </tr>
	   	 <tr>
		 <td>Luftfeuchtigkeit</td>
		 <td>percent</td>
	   </tr>
	   	 <tr>
		 <td>Model</td>
		 <td>name</td>
	   </tr>
	   	<tr>
		 <td>Modus</td>
		 <td>mode of operation</td>
	   </tr>
	   	 <tr>
		 <td>Nachtkuehlung_aktiviert</td>
		 <td>on/off</td>
	   </tr>
	   	 <tr>
		 <td>Raumluft_Temperatur_AirDail</td>
		 <td>degree</td>
	   </tr>
	   	 <tr>
		 <td>Seriennummer</td>
		 <td>number</td>
	   </tr>
	   	 <tr>
		 <td>Stosslueftung_aktiviert</td>
		 <td>on/off</td>
	   </tr>
	   	 <tr>
		 <td>Stosslueftung_Dauer</td>
		 <td>hour</td>
	   </tr>
	   	 <tr>
		 <td>Zuluft_Grundstufe_Einstellung</td>
		 <td>percent</td>
	   </tr>
	   	 <tr>
		 <td>Zuluft_Luefterdrehzahl</td>
		 <td>rpm</td>
	   </tr>
	   	 <tr>
		 <td>Zuluft_Stufe</td>
		 <td>step</td>
	   </tr>
	   	 <tr>
		 <td>Zuluft_Temperatur</td>
		 <td>degree</td>
	   </tr>
	   	 <tr>
		 <td>automatische_Stosslueftung</td>
		 <td>on/off</td>
	   </tr>
	   	 <tr>
		 <td>automatischer_Bypass</td>
		 <td>on/off</td>
	   </tr>
	   	 <tr>
		 <td>verbl.Batterielebensdauer_AirDial</td>
		 <td>percent</td>
	   </tr>
	   	 <tr>
		 <td>verbl.verbl.Filterlebensdaue</td>
		 <td>percent</td>
	   </tr>
	   	 <tr>
		 <td>Arbeitsstunden</td>
		 <td>hour</td>
	   </tr>
	</table>	
	<br><br>
	
	
    <a name="AirUnitdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; AirUnit &lt;IP-address[:Port]&gt; [poll-interval]</code><br>
        If the poll interval is omitted, it is set to 300 (seconds). Smallest possible value is 30.
        <br>
        Usually, the port needs not to be defined.
        <br>
        Example: <code>define myAirUnit AirUnit 192.168.0.12 600</code>
    </ul>
    <br>
    
    <a name="AirUnitset"></a>
    <b>Set</b><br>
    <ul>
        <code>set &lt;name&gt; &lt;option&gt; &lt;value&gt;</code>
        <br><br>
        You can <i>set</i> different values to any of the following options. 
        <br><br>
        Options:
        <ul>
                <li><i>Modus</i><br>
                  You can choose between<br>
						<i>"Bedarfsmodus"</i>, for automatic mode<br>
						<i>"Programm"</i>, you can define a programm in your AirDail-Controller and choose one.<br>
						<i>"Manuell"</i>, you can set the steps for the fans manually (only in manual mode). Bypass and Boost are in automatic mode.<br>
						<i>"Aus"</i>, the system is off for 24 hours, after this time, the system starts in automatic mode with fanstep 1.</li>
				<li><i>Luefterstufe</i><br>
                  You can set the steps for the fans manually. (only in manual mode)</li>
				<li><i>Stosslueftung</i><br>
                  You can activate/deactive the Boost-Option of your ventilation system. You can configure this mode in your AirDail-Controller, the standard fanstep 10 for 3 hours.<br>
                  It is useful if you need more Air e.g. in case of cooking or a party with more people.</li>
				<li><i>Stosslueftung_Dauer</i><br>
				  You can set the hours for the duration of Boost-Option manually.</li>
                <li><i>Bypass</i><br>
                  You can activate/deactive the Bypass-Option of you ventilations systems. Its a cooling function, the heat exchanger will be deactivated.<br>
				  You can configure this mode in your AirDail-Controller, the standard time is 3 hours.<br>
				  <b>You can't activte it, if the outdoor temperature is under 5°C.<br>
				  This option is not available for w1-unit.</b></li>
				<li><i>Bypass_Dauer</i><br>
				  You can set the hours for the duration of Bypass-Option manually.</li>
				<li><i>Nachtkuehlung</i><br>
                  You can activate/deactive the nightcooling option of you ventilations systems. You can configure this in your AirDail-Controller.<br>
				<b>This option is not available for w1-unit.</b></li>
				<li><i>automatische_Stosslueftung</i><br>
                  You can activate/deactive the automatic Boost-Option of you ventilations systems. Its automaticly activated, if the humidity increase very strong, then it runs for 30min.</li>
				<li><i>automatischer_Bypass</i><br>
                  You can activate/deactive the automatic Bypass-Option of you ventilations systems. Its automaticly activated, if the outdoor temperature and room temperature are higher then the configured values.<br>
                  You can configure this mode in your AirDail-Controller.</li>
                <li><i>Intervall</i><br>
                  You can setup the refresh intervall of your readings. Minimum 30 seconds.</li>
				<li><i>Feuerstaette</i><br>
				  You can activate/deactive the Fireplace-Option.</li>
        </ul>
    </ul>
    <br>

    <a name="AirUnitget"></a>
    <b>Get</b><br>
       <ul>
        <code>set &lt;name&gt; &lt;option&gt; &lt;value&gt;</code>
        <br><br>
        You can <i>set</i> different values to any of the following options. 
        <br><br>
        Options:
        <ul>
			<li><i>update</i><br>
            You can refresh all values manually.</li>
        </ul>
    </ul>
    <br>
	
	<a name="AirUnitattr"></a>
    <b>Attributes</b>
    <ul>
        <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
        <br><br>
        Attributes:
        <ul>
            <li><i>disable</i> 0|1<br>
                When you set disable to "1", the connection and the refresh intervall will be disabled. (takes a while)<br>
				This feature gives you the possibility to use an external connection (e.g. the Danfoss-Windows-Tool) without deletion of the device.<br>
            </li>
        </ul>
    </ul>
    <br>
	
	<a name="AirUnitaddinfo"></a>
    <b>additional information</b>
    <ul>
            <li><i>PC-Tool</i><br>
				You can donwload the Danfoss-Windows-Tool <a href="https://www.danfoss.com/da-dk/service-and-support/downloads/dhs/danfoss-air-pc-tool-end-user/#tab-overview">HERE</a>.<br>
				You can start this tool with 3 different options: enduser, service or installer.<br>
				You need only to change the "HRVPCTool.exe.config" in the installation directory.<br>
				<ul>
					<li>enduser {47464213-F94A-495e-81A0-486E54CB4F64}</li>
					<li>service {FC0CB02C-1695-4064-BCD9-FC0A5D77ED3D}</li>
					<li>installer {E4C3938B-9F3E-427e-85CF-A42FE350326D}</li>
				</ul>
            </li>
    </ul>
	
</ul>

=end html

=cut