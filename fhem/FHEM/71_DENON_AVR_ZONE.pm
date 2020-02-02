###############################################################################
# 71_DENON_AVR_ZONE
#
#     This file is part of Fhem.
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
#     along with Fhem.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################
#
# DENON_AVR_ZONE maintained by Martin Gutenbrunner
# original credits to raman and the community (see Forum thread)
#
# This module enables FHEM to interact with Denon and Marantz audio devices.
#
# Discussed in FHEM Forum: https://forum.fhem.de/index.php/topic,58452.300.html
#
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub DENON_AVR_ZONE_Get($$$);
sub DENON_AVR_ZONE_Set($$$);
sub DENON_AVR_ZONE_Attr($@);
sub DENON_AVR_ZONE_Define($$$);
sub DENON_AVR_ZONE_Undefine($$);


# Database and call-functions
######################################################################
my $DENON_db_zone = {
	'UP' 		=> 'up',
	'DOWN' 		=> 'down',
	'ON' 		=> 'on',	
	'OFF' 		=> 'off',
	'PHONO'		=> 'Phono', 
	'CD' 		=> 'CD',
	'TUNER' 	=> 'Tuner',
	'DVD' 		=> 'DVD',
	'BD' 		=> 'Blu-Ray',
	'TV' 		=> 'TV',
	'SAT/CBL' 	=> 'Cbl/Sat', 
	'MPLAY' 	=> 'Mediaplayer', 
	'GAME' 		=> 'Game', 
	'HDRADIO' 	=> 'HDRadio',
	'NET' 		=> 'OnlineMusic', 
	'SPOTIFY' 	=> 'Spotify', 
	'LASTFM' 	=> 'LastFM', 
	'FLICKR' 	=> 'Flickr', 
	'IRADIO' 	=> 'iRadio', 
	'SERVER' 	=> 'Server', 
	'FAVORITES' => 'Favorites',
	'PANDORA' 	=> 'Pandora',
	'SIRIUSXM' 	=> 'SiriusXM',
	'AUX1' 		=> 'Aux1', 
	'AUX2' 		=> 'Aux2',
	'AUX3' 		=> 'Aux3', 
	'AUX4' 		=> 'Aux4', 
	'AUX5' 		=> 'Aux5', 
	'AUX6' 		=> 'Aux6', 
	'AUX7' 		=> 'Aux7', 
	'BT' 		=> 'Bluetooth',
	'USB/IPOD'	=> 'Usb/iPod', 
	'USB' 		=> 'Usb_play', 
	'IPD' 		=> 'iPod_play', 
	'IRP' 		=> 'iRadio_play', 
	'FVP' 		=> 'Favorites_play',
	'QUICK1' 	=> 'Quick1',
	'QUICK2' 	=> 'Quick2',
	'QUICK3' 	=> 'Quick2',
	'QUICK4' 	=> 'Quick4',
	'QUICK5' 	=> 'Quick5',
	'SMART1' 	=> 'Smart1',
	'SMART2' 	=> 'Smart2',
	'SMART3' 	=> 'Smart3',
	'SMART4' 	=> 'Smart4',
	'SMART5' 	=> 'Smart5',
	'SI' => {
		'Phono' 					=> 'PHONO', 
		'CD' 						=> 'CD', 
		'Tuner' 					=> 'TUNER', 
		'DVD' 						=> 'DVD',
		'Blu-Ray'					=> 'BD',
		'TV' 						=> 'TV',
		'Cbl/Sat' 					=> 'SAT/CBL', 
		'Mediaplayer' 				=> 'MPLAY', 
		'Game' 						=> 'GAME', 
		'HDRadio'					=> 'HDRADIO',
		'OnlineMusic' 				=> 'NET', 
		'Spotify' 					=> 'SPOTIFY', 
		'LastFM' 					=> 'LASTFM', 
		'Flickr' 					=> 'FLICKR', 
		'iRadio' 					=> 'IRADIO', 
		'Server' 					=> 'SERVER', 
		'Favorites' 				=> 'FAVORITES',
		'Pandora'					=> 'PANDORA',
		'SiriusXM'					=> 'SIRIUSXM',
		'Aux1' 						=> 'AUX1', 
		'Aux2' 						=> 'AUX2', 
		'Aux3' 						=> 'AUX3', 
		'Aux4' 						=> 'AUX4', 
		'Aux5' 						=> 'AUX5', 
		'Aux6' 						=> 'AUX6', 
		'Aux7' 						=> 'AUX7', 
		'Bluetooth' 				=> 'BT', 
		'Usb/iPod' 					=> 'USB/IPOD', 
		'Usb_play' 					=> 'USB', 
		'iPod_play' 				=> 'IPD', 
		'iRadio_play' 				=> 'IRP', 
		'Favorites_play' 			=> 'FVP',
		'Source'                   => 'SOURCE',
#		'Status' 					=> '?',
	},
	'MU' => {
		'on' 		=> 'ON',
		'off' 		=> 'OFF',
		'status' 	=> '?',
	},
	'CS' => {
		'stereo' 	=> 'ST',
		'mono' 		=> 'MONO',
		'status' 	=> '?',
	},
	'CV' => {
		'FL'	=> 'FrontLeft',
		'FR'	=> 'FrontRight',
	},
	'HPF' => {
		'on' 		=> 'ON',
		'off' 		=> 'OFF',
		'status' 	=> '?',
	},
	'PS' => {
		'BAS' => 'bass',
		'TRE' => 'treble',	
	},
	'HDA' => {
		'HDA' 	=> 'HDMI_out',
		'THR' 	=> 'through',
		'PCM' 	=> 'pcm',
	},
	'SLP' => {
		'off' 		=> 'OFF',
		'10min'     => '010',
		'15min'     => '015',
		'30min'     => '030',
		'40min'     => '040',
		'50min'     => '050',
		'60min'     => '060',
		'70min'     => '070',
		'80min'     => '080',
		'90min'     => '090',
		'100min'    => '100',
		'110min'    => '110',
		'120min'    => '120',
		'status' 	=> '?',
	},
	'STBY' => {
		'2h' 		=> '2H',
		'4h' 		=> '4H',
		'8h' 		=> '8H',
		'off' 		=> 'OFF',
		'status' 	=> '?',
	},
	'SWITCH' => {
		"on"      => "off",
		"off"     => "on",
	},
	'REMOTE' => {      			 #Remote - all commands:
		'up' => 'UP',
		'down' => 'DOWN',
	},
	'SOD' => {            # used inputs: USE = aviable / DEL = not aviable
			'DVD' => 'USE', 
			'BD' => 'USE',       
			'TV' => 'USE',       
			'SAT/CBL' => 'USE',
			'SAT' => 'DEL',			
			'MPLAY' => 'USE',    
			'BT' => 'USE',       
			'GAME' => 'USE',
			'HDRADIO' => 'DEL',		
			'AUX1' => 'USE',
			'AUX2' => 'USE',
 			'AUX3' => 'DEL',
			'AUX4' => 'DEL',
			'AUX5' => 'DEL',
			'AUX6' => 'DEL',
			'AUX7' => 'DEL',
			'AUXA' => 'DEL',
			'AUXB' => 'DEL',
			'AUXC' => 'DEL',
			'AUXD' => 'DEL',			
			'CD' => 'USE',          
			'PHONO' => 'USE',
			'TUNER' => 'USE',
			'FAVORITES' => 'USE',
			'IRADIO' => 'USE',
			'SIRIUSXM' => 'DEL',
			'PANDORA' => 'DEL',
			'SERVER' => 'USE',
			'FLICKR' => 'USE',
			'NET' => 'USE',
			'LASTFM' => 'DEL',
			'USB/IPOD' => 'USE',
			'USB' => 'USE',
			'IPD' => 'USE',
			'IRP' => 'USE',
			'FVP' => 'USE',
			'SOURCE' => 'USE',
	},	
};

sub
DENON_ZONE_GetValue($;$;$) {	
	my ( $status, $com, $inf) = @_;

	my $command = (defined($com) ? $com : "na");
	my $info = (defined($inf) ? $inf : "na");

    if (  $command eq "na" && $info eq "na"
        && defined( $DENON_db_zone->{$status} ) )
    {
		my $value = eval { $DENON_db_zone->{$status} };
		$value = $@ ? "unknown" : $value;
        return $value; 
    }
    elsif ( defined($DENON_db_zone->{$status}{$command} ) && $info eq "na" ) {
		my $value = eval { $DENON_db_zone->{$status}{$command} };
		$value = $@ ? "unknown" : $value;
		return $value; 
    }
	elsif ( defined($DENON_db_zone->{$status}{$command}{$info}) ) {
		my $value = eval { $DENON_db_zone->{$status}{$command}{$info} };
		$value = $@ ? "unknown" : $value;
        return $value; 
    }
    else {
        return "unknown";
    }
}

sub
DENON_ZONE_GetKey($$;$) {
	my ( $status, $command, $info) = @_;

	if ( defined($status) && defined($command) && !defined($info))
    {
		my @keys = keys %{$DENON_db_zone->{$status}};
        my @values = values %{$DENON_db_zone->{$status}};
        while (@keys) {
            my $fhemCommand = pop(@keys);   
			my $denonCommand = pop(@values);
			if ($command eq $denonCommand)
			{
				return $fhemCommand;
			}
        }
	}
	if ( defined($status) && defined($command) && defined($info))
    {
		my @keys = keys %{$DENON_db_zone->{$status}{$command}};
        my @values = values %{$DENON_db_zone->{$status}{$command}};
        while (@keys) {
            my $fhemCommand = pop(@keys);   
			my $denonCommand = pop(@values);
			if ($info eq $denonCommand)
			{
				return $fhemCommand;
			}
        }
	}
	else {
        return undef;
    }
}


###################################
sub
DENON_AVR_ZONE_Initialize($)
{
	my ($hash) = @_;

	$hash->{Match}     = ".+"; 
  
	$hash->{GetFn}     = "DENON_AVR_ZONE_Get";
	$hash->{SetFn}     = "DENON_AVR_ZONE_Set";
	$hash->{DefFn}     = "DENON_AVR_ZONE_Define";
	$hash->{UndefFn}   = "DENON_AVR_ZONE_Undefine";
	$hash->{ParseFn}   = "DENON_AVR_ZONE_Parse";

	$hash->{AttrFn}    = "DENON_AVR_ZONE_Attr";
	$hash->{AttrList}  = "IODev brand:Denon,Marantz do_not_notify:1,0 disable:0,1 connectionCheck:off,30,45,60,75,90,105,120,240,300 timeout:1,2,3,4,5 unit:off,on ".$readingFnAttributes;
  
	$data{RC_makenotify}{DENON_AVR_ZONE} = "DENON_AVR_ZONE_RCmakenotify";
	$data{RC_layout}{DENON_AVR_ZONE_RC}  = "DENON_AVR_ZONE_RClayout";
	
	$hash->{parseParams} = 1;
}

#############################
sub
DENON_AVR_ZONE_Define($$$)
{
	my ($hash, $a, $h) = @_;
	my $name = $hash->{NAME};
	return "Usage: define <name> DENON_AVR_ZONE <zone>  ... wrong paramter count: ".int(@$a)    if(int(@$a) != 3);

	AssignIoPort($hash);
	
	my $IOhash = $hash->{IODev};
    my $IOname = $IOhash->{NAME};
    my $zone;
		
    if(!defined($IOhash) && !defined($IOname)) {
            my $err= "DENON_AVR_ZONE $name error: no I/O device.";
            Log3 $hash, 1, $err;
            return $err;
    }
	
	if ( !defined( @$a[2] ) ) {
        $zone = "2";
    }  
	elsif ( @$a[2] eq "2" || @$a[2] eq "3" || @$a[2] eq "4") {
        $zone = @$a[2];
    }
    else {
        return @$a[2] . " is not a valid Zone number";
    }
		
	if ( defined($modules{DENON_AVR_ZONE}{defptr}{$IOname}{$zone}) )
	{
		return "Zone already defined in " . $modules{DENON_AVR_ZONE}{defptr}{$IOname}{$zone}{NAME};
	}
    if ( !defined($IOhash) ) {
        return "No matching I/O device found, please define a DENON_AVR device first";
    }
    elsif ( !defined( $IOhash->{TYPE} ) || !defined( $IOhash->{NAME} ) ) {
        return "IODev does not seem to be existing";
    }
    elsif ( $IOhash->{TYPE} ne "DENON_AVR" ) {
        return "IODev is not of type DENON_AVR";
    }
    else {
        $hash->{ZONE} = $zone;
		$modules{DENON_AVR_ZONE}{defptr}{$IOname}{$zone} = $hash;
    }
	
	# set default attributes
    unless ( exists( $attr{$name}{webCmd} ) ) {
        $attr{$name}{webCmd} = 'volume:muteT:input';
    }
	unless ( exists( $attr{$name}{cmdIcon} ) ) {
		$attr{$name}{cmdIcon} = 'muteT:rc_MUTE';
	}
	unless ( exists( $attr{$name}{devStateIcon} ) ) {
		$attr{$name}{devStateIcon} = 'on:rc_GREEN:off off:rc_STOP:on absent:rc_RED muted:rc_MUTE@green:muteT';
	}
	unless (exists($attr{$name}{stateFormat})){
		$attr{$name}{stateFormat} = 'stateAV';
	}
	
	return undef;
}

#####################################
sub DENON_AVR_ZONE_Undefine($$) {
    my ( $hash, $name ) = @_;
    my $zone   = $hash->{ZONE};
    my $IOhash = $hash->{IODev};
    my $IOname = $IOhash->{NAME};

    Log3 $name, 5,
      "DENON_AVR_ZONE $name: called function DENON_AVR_ZONE_Undefine()";
	  
    delete $modules{DENON_AVR_ZONE}{defptr}{$IOname}{$zone}
      if ( defined( $modules{DENON_AVR_ZONE}{defptr}{$IOname}{$zone} ) );
	  
	DENON_AVR_ZONE_RCdelete($name);
	  	  
    # Disconnect from device
    DevIo_CloseDev($hash);

    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);

    return undef;
}

#####################################
sub
DENON_AVR_ZONE_Parse(@)
{	
	my ($IOhash, $msg) = @_;   # IOhash points to the DENON_AVR, not to the DENON_AVR_ZONE

	my @matches;
	my $name = $IOhash->{NAME};
	
	foreach my $d (keys %defs) {
		my $hash = $defs{$d};
		my $state = ReadingsVal( $name, "power", "off" );
						
		if($hash->{TYPE} eq "DENON_AVR_ZONE" && $hash->{IODev} eq $IOhash) {
		
			my $return = "unknown";
			my $zone = 2;
			my $zonehash = undef;
			my $zonename = undef;
			
			if ( defined($modules{DENON_AVR_ZONE}{defptr}{$name}{2}) && $msg =~ /^Z2/ )
			{
				$zone = 2;
				$zonehash = $modules{DENON_AVR_ZONE}{defptr}{$name}{2};
				$zonename = $zonehash->{NAME};
			}
			elsif ( defined($modules{DENON_AVR_ZONE}{defptr}{$name}{3}) && $msg =~ /^Z3/ )
			{
				$zone = 3;
				$zonehash = $modules{DENON_AVR_ZONE}{defptr}{$name}{3};
				$zonename = $zonehash->{NAME};
			}
			elsif ( defined($modules{DENON_AVR_ZONE}{defptr}{$name}{4}) && $msg =~ /^Z4/ )
			{
				$zone = 4;
				$zonehash = $modules{DENON_AVR_ZONE}{defptr}{$name}{4};
				$zonename = $zonehash->{NAME};
			}
			
			my $dezibel = AttrVal($zonename, "unit", "off") eq "on" ? " dB" : "";
			my $percent = AttrVal($zonename, "unit", "off") eq "on" ? " %" : "";
		
			Log3 $zonename, 5, "DENON_AVR_ZONE $zone: $name <dq($msg)>";
			push @matches, $d;
						
			if ($msg =~ /^(Z2|Z3|Z4)(.+)/) {
				my $zone = $1;
				my $arg = $2;
				
				readingsBeginUpdate($zonehash);
				
				if ($arg eq "ON" || $arg eq "OFF") {
					readingsBulkUpdate($zonehash, "power", lc($arg));
					readingsBulkUpdate($zonehash, "state", lc($arg));
					readingsBulkUpdate($zonehash, "presence", "present");
					readingsBulkUpdate($zonehash, "stateAV", DENON_AVR_ZONE_GetStateAV($zonehash));
					$return = lc($arg);
				}
				elsif ($arg =~ /^CS(.+)/) {
					Log3 $zonename, 0, "DENON_AVR_ZONE $zone: $name <$1>";
					my $status = DENON_ZONE_GetKey("CS", $1);
					readingsBulkUpdate($zonehash, "channelSetting", $status);
					$return = "channelSetting " .  $status;
				}
				elsif ($arg =~ /^CV([A-Z]+) (.+)/) {
					Log3 $zonename, 0, "DENON_AVR_ZONE $zone: $name <$1>";
					my $channel = DENON_ZONE_GetValue("CV", $1);
					my $volume = $2;
					if (length($volume) == 2)
					{
						$volume = $volume."0";
					}
					readingsBulkUpdate($zonehash, "level".$channel, ($volume / 10 - 50).$dezibel);
					$return = "level".$channel . " " .  ($volume / 10 - 50).$dezibel;
				}
				elsif ($arg =~ /^FAVORITE(.+)/)
				{
					readingsBulkUpdate($zonehash, "favorite", $1);
					$return = "favorite " .  $1;
				}
				elsif ($arg =~ /^MU(.+)/) {
					readingsBulkUpdate($zonehash, "mute", lc($1));
					readingsBulkUpdate($zonehash, "stateAV", DENON_AVR_ZONE_GetStateAV($zonehash));
					$return = "mute " .  lc($1);
				}
				elsif ($arg =~ /^HDA(.+)/) {
					my $status = DENON_ZONE_GetValue('HDA', $1);
					readingsBulkUpdate($zonehash, "digitalOut", $status);
					$return = "digitalOut " .  $status;
				}
				elsif ($arg =~ /^HPF(.+)/) {
					readingsBulkUpdate($zonehash, "highPassFilter", lc($1));
					$return = "highPassFilter " .  lc($1);
				}
				elsif ($arg =~/^PS(.+)/)
				{
					my $parameter = $1;
					if($parameter =~ /^([A-Z]{3}) (.+)/)
					{	
						my $status = DENON_ZONE_GetValue('PS', $1);
						my $volume = $2;
						if (length($volume) == 2)
						{
							$volume = $volume."0";
						}
						$volume = ($volume / 10 - 50).$dezibel;
						readingsBulkUpdate($zonehash, $status, $volume);
						$return = $status . " " . $volume;
					}
				}
				elsif ($arg =~ /^QUICK(.+)/) {
					readingsBulkUpdate($zonehash, "quickselect", $1);
					$return = "quickselect " .  $1;
				}
				elsif ($arg =~ /^SMART(.+)/) {
					readingsBulkUpdate($zonehash, "smartselect", $1);
					$return = "smartselect " .  $1;
				}
				elsif ($arg =~ /^SLP(.+)/) {
					readingsBulkUpdate($zonehash, "sleep", $1."min");
					$return = "sleep " .  $1."min";
				}
				elsif ($arg =~ /^STBY(.+)/) {
					my $status = DENON_ZONE_GetKey("STBY", $1);
					readingsBulkUpdate($zonehash, "autoStandby", $status);
					$return = "autoStandby " .  $status;
				}
				elsif ($arg =~ /(^[0-9]+)/){
					my $volume = $1;
					if (length($volume) == 2)
					{
						$volume = $volume."0";
					}
					readingsBulkUpdate($zonehash, "volumeStraight", ($volume / 10 - 80).$percent);
					readingsBulkUpdate($zonehash, "volume", ($volume / 10).$dezibel);
					$return = "volume/volumeStraight ".($volume / 10)."/".($volume / 10 - 80);
				}
				else{
					if ($arg eq 'SOURCE'){
						my $status = ReadingsVal($name, "input", "Cbl/Sat");
						readingsBulkUpdate($zonehash, "input", $status);
						$return = "input " .  $status;
					}
					else{
						my $status = DENON_ZONE_GetValue($arg);
						readingsBulkUpdate($zonehash, "input", $status);
						$return = "input " .  $status;
					}
				}
				
				readingsEndUpdate($zonehash, 1);
			}
			elsif ( $msg =~ /^power (.+)/ && defined($zonehash) ) {
				readingsBeginUpdate($zonehash);
				readingsBulkUpdate($zonehash, "power", $1);
				readingsEndUpdate($zonehash, 1);
				$return = $1;
			}
			elsif ( $msg =~ /^presence (.+)/  && defined($zonehash) ) {
				readingsBeginUpdate($zonehash);
				readingsBulkUpdate($zonehash, "presence", $1);
				readingsEndUpdate($zonehash, 1);
				$return = "presence " .  $1;
			}
			Log3 $zonename, 4, "DENON_AVR_ZONE $zone: parsing <$msg> to <$return>";
			return @matches if (@matches);
			return "UNDEFINED DENON_AVR_ZONE";
		}
	}
}

#####################################
sub
DENON_AVR_ZONE_Get($$$)
{
	my ( $hash, $a, $h ) = @_;
	my $arg;
	my $name = $hash->{NAME};
	my $zone = $hash->{ZONE};

	return "argument is missing" if (int(@$a) != 2);
	if (@$a[1] =~ /^(power|volumeStraight|volume|channelSetting|highPassFilter|mute|input|remotecontrol|autoStandby|sleep|zone|zoneStatusRequest)$/)
	{
		if (@$a[1] eq "remotecontrol")
		{
			return DENON_AVR_ZONE_RCmake($name);
		}
		elsif (@$a[1] eq "zoneStatusRequest")
		{
			DENON_AVR_ZONE_Command_Write($hash, "?", "power");
	
			return "StatusRequest zone $zone finished!";
		}
		elsif(defined(ReadingsVal( $name, @$a[1], "" )))
		{		
			return ReadingsVal( $name, @$a[1], "" );
		}
		else
		{
			return "No such reading: @$a[1]";
		}
	}
	else
	{
		return "Unknown argument @$a[1], choose one of power volumeStraight volume autoStandby channelSetting highPassFilter mute input  mute remotecontrol sleep zone zoneStatusRequest";
	}
}

#####################################
sub
DENON_AVR_ZONE_Set($$$)
{
	my ( $hash, $a, $h ) = @_;
	
	my $IOhash   = $hash->{IODev};
    my $name     = $hash->{NAME};
    my $zone     = $hash->{ZONE};
    my $state    = ReadingsVal( $name, "power", "off" );
    my $presence = ReadingsVal( $name, "presence", "absent" );
    my $return;
	my $select = "quick";
			
	my @channel = ();
	my @preset = (01..56);
	my @inputs = ();
	#my @usedInputs = ();
	my @remoteControl = ();
	my $dezibel = AttrVal($name, "unit", "off") eq "on" ? " dB" : "";
	
	foreach my $key (sort(keys %{$DENON_db_zone->{'REMOTE'}})) {
		push(@remoteControl, $key);	
	}
	
	if ( exists( $attr{$IOhash->{NAME}}{inputs} ) )
	{
		@inputs = split(/,/,$attr{$IOhash->{NAME}}{inputs});
	}
	else
	{
		foreach my $key (sort(keys %{$DENON_db_zone->{'SI'}})) {
			my $device = $DENON_db_zone->{'SI'}{$key};
			
			if ( defined($DENON_db_zone->{'SOD'}{$device}))
			{
				if ($DENON_db_zone->{'SOD'}{$device} eq 'USE')
				{
					push(@inputs, $key);
				}		
				#push(@usedInputs, $key);
			}
		}
	}
	
	if(AttrVal($name, "brand", "Denon") eq "Marantz")
	{
		$select = "smart";
	}
	
	foreach my $key (sort(keys %{$DENON_db_zone->{'CV'}})) {
		push(@channel, $DENON_db_zone->{'CV'}{$key}."_up");
		push(@channel, $DENON_db_zone->{'CV'}{$key}."_down");		
	}
	
	my $usage = "Unknown argument @$a[1], choose one of on off toggle volumeDown volumeUp volumeStraight:slider,-80,1,18 volume:slider,0,1,98 mute:on,off,toggle muteT sleep:off,10min,15min,20min,30min,40min,50min,60min,70min,80min,90min,100min,110min,120min autoStandby:off,2h,4h,8h channelSetting:stereo,mono highPassFilter:on,off " . 
			"favorite:1,2,3,4" . " " .
			$select . "select:1,2,3,4,5 " .
			"input:" . join(",", @inputs) . " " .
#			"usedInputs:multiple-strict,"  . join(",", @usedInputs) . " " .
			"bass:slider,-10,1,10 treble:slider,-10,1,10 " .
			"channelVolume:" . join(",", @channel) . " " . 
			"remoteControl:" . join(",", @remoteControl) . " " .
		    "rawCommand"; 	
	
	if (@$a[1] eq "?")
	{
		$return = "?";
		return $usage;
	}
	
	readingsBeginUpdate($hash);
	
	if (@$a[1] =~ /^(on|off)$/)
	{
		$return = DENON_AVR_ZONE_Command_SetPower($hash, @$a[1]);
	}	
	elsif (@$a[1] eq "bass")
	{
		my $volume = @$a[2] + 50;	
		$return = DENON_AVR_ZONE_Command_Write($hash, "PSBAS ".$volume, "bass", @$a[2].$dezibel);
	}
	elsif (@$a[1] eq "treble")
	{
		my $volume = @$a[2] + 50;	
		$return = DENON_AVR_ZONE_Command_Write($hash, "PSTRE ".$volume, "treble", @$a[2].$dezibel);
	}
	elsif (@$a[1] eq "channelSetting")
	{
		my $favorite = @$a[2];
		my $channel = DENON_ZONE_GetValue('CS', @$a[2]);
		$return = DENON_AVR_ZONE_Command_Write($hash, "CS".$channel, "channelSetting", @$a[2]);
	}	
	elsif (@$a[1] eq "channelVolume")
	{
		my $channel = "";
		my $command = @$a[2];
		my $volume = "";
		if($command =~ /^(.+)_(up|down)/)
		{
			$channel = DENON_ZONE_GetKey("CV", $1);
			$channel = $channel." ".uc($2);
			#my $state = ReadingsVal( $name, $channel, "0" );
			#$volume = uc($2);
			$volume = "query_CV?";
		}
		else
		{
			$channel = DENON_ZONE_GetKey("CV", $command);
			$volume = @$a[3] + 50;
			if ($volume % 1 == 0)
			{
				$volume = 40 if($volume < 40);
				$volume = 60 if($volume > 60);
				$volume = sprintf ('%02d', $volume);
				$channel = $channel." ".$volume;
				$volume = @$a[3].$dezibel;
			}
			elsif ($volume % 1 == 0.5)
			{
				$volume = 40.5 if($volume < 40.5);
				$volume = 59.5 if($volume > 59.5);
				$volume = sprintf ('%03d', ($volume * 10));
				$channel = $channel." ".$volume;
				$volume = @$a[3].$dezibel;
			}
			else
			{
				return undef;
			}
		}		
		$return = DENON_AVR_ZONE_Command_Write($hash, "CV".$channel, "channelVolume", $volume);
	}	
	elsif (@$a[1] eq "favorite")
	{
		my $favorite = @$a[2];
		$return = DENON_AVR_ZONE_Command_Write($hash, "FAVORITE".$favorite, "favorite", @$a[2]);
	}
	elsif (@$a[1] eq "highPassFilter")
	{
		my $favorite = @$a[2];
		my $channel = DENON_ZONE_GetValue('HPF', @$a[2]);
		$return = DENON_AVR_ZONE_Command_Write($hash, "HPF".$channel, "highPassFilter", @$a[2]);
	}
	elsif (@$a[1] eq "input")
	{
		my $input = DENON_ZONE_GetValue('SI', @$a[2]);
		$return = DENON_AVR_ZONE_Command_SetInput($hash, $input, @$a[2]);
	}
	elsif (@$a[1] eq "mute" || @$a[1] eq "muteT")
	{	
		my $mute = @$a[2];
		if ($mute eq "toggle" || @$a[1] eq "muteT")
		{
			my $newMuteState = DENON_ZONE_GetValue('SWITCH', ReadingsVal( $name, "mute", "off"));
			$return = DENON_AVR_ZONE_Command_SetMute($hash, $newMuteState);
		}
		else
		{
			$return = DENON_AVR_ZONE_Command_SetMute($hash, $mute);
		}
	}
	elsif (@$a[1] eq "quickselect")
	{
		my $msg = "QUICK".@$a[2];
		$return = DENON_AVR_ZONE_Command_Write($hash, $msg, "quickselect", @$a[2]);
	}
	elsif (@$a[1] eq "smartselect")
	{
		my $msg = "SMART".@$a[2];
		$return = DENON_AVR_ZONE_Command_Write($hash, $msg, "smartselect", @$a[2]);
	}
	elsif (@$a[1] eq "sleep")
	{
		my $msg = DENON_ZONE_GetValue('SLP', @$a[2]);
		$return = DENON_AVR_ZONE_Command_Write($hash, "SLP".$msg, "sleep", @$a[2]);
	}
	elsif (@$a[1] eq "autoStandby")
	{
		my $msg = DENON_ZONE_GetValue('STBY',@$a[2]);
		$return = DENON_AVR_ZONE_Command_Write($hash, "STBY".$msg, "autoStandby", @$a[2]);
	}
	elsif (@$a[1] eq "toggle")
	{
		my $newPowerState = DENON_ZONE_GetValue('SWITCH', ReadingsVal( $name, "state", "on"));			
		$return =DENON_AVR_ZONE_Command_SetPower($hash, $newPowerState);
	}
	elsif (@$a[1] eq "volumeStraight")
	{
		my $volume = @$a[2];
		$return = DENON_AVR_ZONE_Command_SetVolume($hash, $volume + 80);
	}
	elsif (@$a[1] eq "volume")
	{
		my $volume = @$a[2];
		$return = DENON_AVR_ZONE_Command_SetVolume($hash, $volume);
	}
	elsif (@$a[1] eq "volumeDown")
	{
		my $msg = "DOWN";
		my $oldVolume = ReadingsVal( $name, "volume", "0" );
		
		my $volume = @$a[2];
		if(@$a[2])
		{
			$volume = $oldVolume - $volume;
			$return = DENON_AVR_ZONE_Command_SetVolume($hash, $volume);
		}
		else
		{
			readingsBulkUpdate($hash, "volumeStraight", $oldVolume - 81);
			readingsBulkUpdate($hash, "volume", $oldVolume - 1);
			$return = DENON_AVR_ZONE_Command_Write($hash, $msg, "volumeDown");
		}
	}
	elsif (@$a[1] eq "volumeUp")
	{
		my $msg = "UP";
		my $oldVolume = ReadingsVal( $name, "volume", "0" );
		
		my $volume = @$a[2];
		if(@$a[2])
		{
			$volume = $oldVolume + $volume;
			$return = DENON_AVR_ZONE_Command_SetVolume($hash, $volume);
		}
		else
		{
			readingsBulkUpdate($hash, "volumeStraight", $oldVolume - 79);
			readingsBulkUpdate($hash, "volume", $oldVolume + 1);
			$return = DENON_AVR_ZONE_Command_Write($hash, $msg, "volumeUp");
		}
	}
	elsif (@$a[1] eq "rawCommand")
	{
		my $msg = @$a[2];
		$msg = @$a[2]." ".@$a[3] if defined @$a[3];
		$msg = $msg." ".@$a[4] if defined @$a[4];
		$return = DENON_AVR_ZONE_Command_Write($hash, $msg, "rawCommand");
	}
	elsif (@$a[1] eq "remoteControl")
	{
		if(@$a[2] =~ /^in_(.+)/) #inputs
		{
			my $input = DENON_ZONE_GetValue('SI', $1);
			$return = DENON_AVR_ZONE_Command_SetInput($hash, $input, @$a[2]);
		}
		if(@$a[2] =~ /^(up|down)$/) #volume
		{
			$return = DENON_AVR_ZONE_Command_Write($hash, uc($1), "volume");
		}
		else
		{
			fhem("set $name @$a[2]");
		}
	}
	elsif (@$a[1] eq "usedInputs")
	{
		DENON_AVR_ZONE_SetUsedInputs($hash, @$a[2]);
		$return = "";
	}
	else 
	{
        $return = $usage;
    }

    readingsEndUpdate( $hash, 1 );

    # return result
    return $return;
}

#####################################
sub
DENON_AVR_ZONE_Attr($@)
{

  my @a = @_;
  my $hash= $defs{$a[1]};

  return undef;
}

#####################################
sub
DENON_AVR_ZONE_Command_Write($$$;$)
{
	my ($hash, $msg, $call, $state) = @_;
	my $name = $hash->{NAME};
	my $zone = $hash->{ZONE};
	
	Log3 $name, 5, "DENON_AVR_ZONE $name: zone $zone called Write";	
	IOWrite($hash, "Z".$zone."".$msg, "Z".$zone." ".$call);	
	if(defined($state))
	{
		if($state =~ /^query_(.+)/)
		{
			IOWrite($hash, "Z".$zone."".$1, "Z".$zone." query");	
		}
		else
		{
			readingsBulkUpdate($hash, $call, $state);
		}
	}

	return undef;
}

#####################################
sub
DENON_AVR_ZONE_GetStateAV($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if ( ReadingsVal( $name, "presence", "absent" ) eq "absent" ) {
        return "absent";
    }
    elsif ( ReadingsVal( $name, "power", "off" ) eq "off" ) {
        return "off";
    }
    elsif ( ReadingsVal( $name, "mute", "off" ) eq "on" ) {
        return "muted";
    }
    else {
        return ReadingsVal( $name, "power", "off" );
    }
}


#####################################
sub
DENON_AVR_ZONE_Command_SetInput($$$)
{
	my ($hash, $input, $friendlyName) = @_;
	my $name = $hash->{NAME};
	my $zone = $hash->{ZONE};
	
	Log3 $name, 5, "DENON_AVR_ZONE $name: zone $zone called SetInput.";
	IOWrite($hash, "Z".$zone."".$input, "Z".$zone." input");	
	readingsBulkUpdate($hash, "input", $friendlyName);
	
	return undef;
}

#####################################
sub
DENON_AVR_ZONE_Command_SetMute($$)
{
	my ($hash, $mute) = @_;
	my $name = $hash->{NAME};
	my $zone = $hash->{ZONE};
	
	Log3 $name, 5, "DENON_AVR_ZONE $name: zone $zone called SetMute.";
	
	return "mute can only used when device is powered on" if (ReadingsVal( $name, "state", "off") eq "off");

	my $status = DENON_ZONE_GetValue('MU', lc($mute));
	
	IOWrite($hash, "Z".$zone."MU".$status, "Z".$zone." mute");
	readingsBulkUpdate($hash, "mute", $mute);
	readingsBulkUpdate($hash, "stateAV", DENON_AVR_ZONE_GetStateAV($hash));

	return undef;
}

#####################################
sub
DENON_AVR_ZONE_Command_SetPower($$)
{
	my ($hash, $power) = @_;
	my $name = $hash->{NAME};
	my $zone = $hash->{ZONE};
	
	Log3 $name, 5, "DENON_AVR_ZONE $name: zone $zone called SetPower";
	
	IOWrite($hash, "Z".$zone."".uc($power), "Z".$zone." power");
		
	readingsBulkUpdate($hash, "power", lc($power));
	readingsBulkUpdate($hash, "state", lc($power));
	readingsBulkUpdate($hash, "stateAV", DENON_AVR_ZONE_GetStateAV($hash));

	return undef;
}

#####################################
sub
DENON_AVR_ZONE_Command_SetVolume($$)
{
	my ($hash, $volume) = @_;
	my $name = $hash->{NAME};
	my $zone = $hash->{ZONE};
	
	my $dezibel = AttrVal($name, "unit", "off") eq "on" ? " dB" : "";
	my $percent = AttrVal($name, "unit", "off") eq "on" ? " %" : "";
		
	Log3 $name, 5, "DENON_AVR_ZONE $name: zone $zone called SetVolume.";
	
	if(ReadingsVal( $name, "state", "off") eq "off")
	{
		return "Volume can only set when device is powered on!";
	}
	else
	{	
		if (length($volume) == 1)
		{
			$volume = "0".$volume;
		}
		
		IOWrite($hash, "Z".$zone."".$volume, "Z".$zone." volume");	
		readingsBulkUpdate($hash, "volumeStraight", ($volume - 80).$percent);
		readingsBulkUpdate($hash, "volume", $volume.$dezibel);
	}

	return undef;
}

#####################################
sub 
DENON_AVR_ZONE_SetUsedInputs($$) {
	my ($hash, $usedInputs) = @_;
	my $name = $hash->{NAME};
	my @inputs = split(/,/,$usedInputs);
	my @denonInputs = ();
	
	foreach (@inputs)
	{
		if(exists $DENON_db_zone->{'SI'}{$_})
		{
			push(@denonInputs, $_);			
		}
	}
	$attr{$name}{inputs} = join(",", @denonInputs);
}

#####################################
sub 
DENON_AVR_ZONE_RCmakenotify($$) {
    my ( $name, $ndev ) = @_;
    my $nname = "notify_$name";

    fhem( "define $nname notify $name set $ndev remoteControl " . '$EVENT', 1 );
    Log3 $name, 3, "DENON_AVR_ZONE $name: create notify for remoteControl.";
    return "Notify created by DENON_AVR_ZONE $nname";
}

#####################################
sub 
DENON_AVR_ZONE_RCmake($) {
	my ( $name ) = @_;
	my $device = $name."_RC";
	
	if(!defined($defs{$device}))
	{
		fhem("define $device remotecontrol");
		fhem("sleep 1;set $device layout DENON_AVR_ZONE_RC");
		
		my $notify = "notify_$name";
		if(!defined($defs{$notify}))
		{
			fhem("sleep 1;set $device makenotify $name");
		}
	}
	
    Log3 $name, 3, "DENON_AVR $name: create remoteControl.";
    return "Remotecontrol created by DENON_AVR $name";
}

#####################################
sub 
DENON_AVR_ZONE_RCdelete($) {
	my ( $name ) = @_;
	my $device = $name."_RC";
	
	if(defined($defs{$device}))
	{
		fhem("delete $device");
		my $notify = "notify_".$device;
		
		if(defined($defs{$notify}))
		{
			fhem("sleep 1;delete $notify");
		}
	}
	
    Log3 undef, 3, "DENON_AVR $name: delete remoteControl.";
    return "Remotecontrol deleted by DENON_AVR_ZONE: $name";
}

#####################################
sub DENON_AVR_ZONE_RClayout() {
    my @row;
	
	$row[0] = "volumeUp:VOLUP,:blank,in_Cbl/Sat:CBLSAT,in_Blu-Ray:BR,in_DVD:DVD,in_CD:CD,:blank,play:PLAY,:blank,toggle:POWEROFF3";
	$row[1] = "muteT:MUTE,:blank,in_Mediaplayer:MEDIAPLAYER,in_iRadio:IRADIO,in_OnlineMusic:ONLINEMUSIC,in_Usb/iPod:IPODUSB,:blank,pause:PAUSE";
	$row[2] = "volumeDown:VOLDOWN,:blank,in_Bluetooth:BT,in_Favorites:FAV,in_Aux1:AUX1,in_Phono:PHONO,:blank,stop:STOP";
	$row[3] = "attr rc_iconpath icons/remotecontrol";
	$row[4] = "attr rc_iconprefix black_btn_";
	
    return @row;
}

1;


=pod
=item device
=item summary control for DENON (Marantz) AV receivers zone
=item summary_DE Zonen-Steuerung von DENON (Marantz) AV Receivern
=begin html

    <p>
      <a name="DENON_AVR_ZONE" id="DENON_AVR_ZONE"></a>
    </p>
    <h3>
      DENON_AVR_ZONE
    </h3>
    <ul>
      <a name="DENON_AVR_ZONEdefine" id="DENON_AVR_ZONEdefine"></a> <b>Define</b>
      <ul>
        <code>define &lt;name&gt; DENON_AVR_ZONE &lt;zonenumber&gt;</code><br>
        <br>
        This module controls DENON A/V receivers zones.<br>
        <br>
        <br>
        Example:<br>
		<br>
        <ul>
          <code>
          define avr_zone2 DENON_AVR_ZONE 2<br>
          <br>
          define avr_zone2 DENON_AVR_ZONE 3<br>
          <br>
          </code>
        </ul>
      </ul><br>
      <br>
      <a name="DENON_AVR_ZONEset" id="DENON_AVR_ZONEset"></a> <b>Set</b>
      <ul>
        <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br>
        <br>
        Currently, the following commands are defined:<br>
        <ul>
		  <li>
            <b>autoStandby</b> &nbsp;&nbsp;-&nbsp;&nbsp; set auto standby time
          </li>
		  <li>
            <b>favorite</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches between favorite (only older models)
          </li>
          <li>
            <b>input</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches between inputs
          </li>
          <li>
            <b>mute</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; controls volume mute
          </li>
          <li>
            <b>muteT</b> &nbsp;&nbsp;-&nbsp;&nbsp; toggle mute state
          </li>
          <li>
            <b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; turns the device in standby mode
          </li>
          <li>
            <b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; powers on the device
          </li>
		  <li>
            <b>quickselect</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches between quick select modes (1-5, only new models)
          </li>
		  <li>
            <b>rawCommand</b> &nbsp;&nbsp;-&nbsp;&nbsp;  send raw command to AV receiver
          </li>
		  <li>
            <b>remote</b> &nbsp;&nbsp;-&nbsp;&nbsp;  remote commands (play, stop, pause,...)
          </li>
		  <li>
            <b>surroundMode</b> &nbsp;&nbsp;-&nbsp;&nbsp; set surround mode
          </li>
          <li>
            <b>toggle</b> &nbsp;&nbsp;-&nbsp;&nbsp; switch between on and off
          </li>
          <li>
            <b>volume</b> 0...98 &nbsp;&nbsp;-&nbsp;&nbsp; set the volume level in percentage
          </li>
		  <li>
            <b>volumeStraight</b> -80...18 &nbsp;&nbsp;-&nbsp;&nbsp; set the volume level in dB
          </li>
          <li>
            <b>volumeUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; increases the volume level
          </li>
          <li>
            <b>volumeDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; decreases the volume level
          </li>
         </ul>
       </ul>
      <br>
      <a name="DENON_AVR_ZONEget" id="DENON_AVR_ZONEget"></a> <b>Get</b>
      <ul>
        <code>get &lt;name&gt; &lt;what&gt;</code><br>
        <br>
        Currently, the following commands are defined:<br>
        <ul>
			<li>
				<b>remoteControl</b> &nbsp;&nbsp;-&nbsp;&nbsp; autocreate remote ccontrol
			</li>
			<li>
				<b>some readings</b> &nbsp;&nbsp;-&nbsp;&nbsp; see list below
			</li>
		</ul>
	   </ul><br>
      <br>
      <b>Generated Readings/Events:</b><br>
	  <br>
      <ul>
		<li>
			<b>autoStandby</b> &nbsp;&nbsp;-&nbsp;&nbsp; auto standby state
		</li>
		<li>
			<b>input</b> &nbsp;&nbsp;-&nbsp;&nbsp; selected input
		</li>
		<li>
			<b>mute</b> &nbsp;&nbsp;-&nbsp;&nbsp; mute state
		</li>
		<li>
			<b>power</b> &nbsp;&nbsp;-&nbsp;&nbsp; power state
		</li>
		<li>
			<b>state</b> &nbsp;&nbsp;-&nbsp;&nbsp; state of AV reciever (on,off,disconnected)
		</li>
		<li>
			<b>stateAV</b> &nbsp;&nbsp;-&nbsp;&nbsp; state of AV reciever (on,off,absent,mute)
		</li>
		<li>
			<b>treble</b> &nbsp;&nbsp;-&nbsp;&nbsp; treble level in dB
		</li>
		<li>
			<b>videoSelect</b> &nbsp;&nbsp;-&nbsp;&nbsp; actual video select mode
		</li>
		<li>
			<b>volume</b> &nbsp;&nbsp;-&nbsp;&nbsp; actual volume
		</li>
		<li>
			<b>volumeMax</b> &nbsp;&nbsp;-&nbsp;&nbsp; actual maximum volume
		</li>
		<li>
			<b>volumeStraight</b> &nbsp;&nbsp;-&nbsp;&nbsp; actual volume straight
		</li>
		</ul>
		<br>
		<b>Attributes</b><br>
		<br>
		<ul>
		  <li>
			<b>IODev</b> &nbsp;&nbsp;-&nbsp;&nbsp; Input/Output Device
		  </li>
        </ul>
	</ul>

=end html

=begin html_DE

    
    <p>
      <a name="DENON_AVR_ZONE" id="DENON_AVR_ZONE"></a>
    </p>
    <h3>
      DENON_AVR_ZONE
    </h3>
    <ul>
      <a name="DENON_AVR_ZONEdefine" id="DENON_AVR_ZONEdefine"></a> <b>Define</b>
      <ul>
        <code>define &lt;name&gt; DENON_AVR_ZONE &lt;zonename[:PORT]&gt;</code><br>
        <br>
        Dieses Modul steuert DENON A/V Receiver &uuml;ber das Netzwerk.<br>
        <br>
		<br>
        Beispiele:<br>
		<br>
        <ul>
          <code>
          define avr_zone2 DENON_AVR_ZONE 2<br>
          <br>
          define avr_zone3 DENON_AVR_ZONE 3<br>
          <br>
          </code>
        </ul>
      </ul><br>
      <br>
      <a name="DENON_AVR_ZONEset" id="DENON_AVR_ZONEset"></a> <b>Set</b>
      <ul>
        <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br>
        <br>
        Momentan sind folgende Befehle verf&uuml;gbar:<br>
        <ul>
		  <li>
            <b>autoStandby</b> &nbsp;&nbsp;-&nbsp;&nbsp; Zeit für den Auto-Standby setzen
          </li>
		  <li>
            <b>favorite</b> &nbsp;&nbsp;-&nbsp;&nbsp; zur Auswahl der Favoriten (nur alte Modelle)
          </li>
          <li>
            <b>input</b> &nbsp;&nbsp;-&nbsp;&nbsp; zur Auswahl der Eing&auml;nge
          </li>
          <li>
            <b>mute</b> an,aus &nbsp;&nbsp;-&nbsp;&nbsp; AV-Receiver laut/stumm schalten
          </li>
          <li>
            <b>muteT</b> &nbsp;&nbsp;-&nbsp;&nbsp; zwischen laut und stumm wechseln
          </li>
          <li>
            <b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; Standby AV-Receiver
          </li>
          <li>
            <b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; AV-Receiver anschalten
          </li>
		  <li>
            <b>quickselect</b> &nbsp;&nbsp;-&nbsp;&nbsp; zur Auswahl der &quot;Quick-Select&quot; Modi (1-5, nur neue Modelle)
          </li>
		  <li>
            <b>rawCommand</b> &nbsp;&nbsp;-&nbsp;&nbsp;  schickt ein &quot;raw command&quot; zum AV-Receiver
          </li>
		   <li>
            <b>remote</b> &nbsp;&nbsp;-&nbsp;&nbsp;  Fernbedienungsbefehle (play, stop, pause,...)
          </li>
		  <li>
            <b>surroundMode</b> &nbsp;&nbsp;-&nbsp;&nbsp; zur Auswahl der Surround-Modi
          </li>
          <li>
            <b>toggle</b> &nbsp;&nbsp;-&nbsp;&nbsp; AV-Receiver an/aus
          </li>
          <li>
            <b>volume</b> 0...98 &nbsp;&nbsp;-&nbsp;&nbsp; Lautst&auml;rke in Prozent
          </li>
		  <li>
            <b>volumeStraight</b> -80...18 &nbsp;&nbsp;-&nbsp;&nbsp; absolute Lautst&auml;rke in dB
          </li>
          <li>
            <b>volumeUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; erhöht Lautst&auml;rke
          </li>
          <li>
            <b>volumeDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; erniedrigt Lautst&auml;rke
          </li>
        </ul>
      </ul><br>
      <br>
      <a name="DENON_AVR_ZONEget" id="DENON_AVR_ZONEget"></a> <b>Get</b>
      <ul>
        <code>get &lt;name&gt; &lt;what&gt;</code><br>
        <br>
        Momentan sind folgende Befehle verf&uuml;gbar:<br>
        <br>
		<ul>
			<li>
				<b>remoteControl</b> &nbsp;&nbsp;-&nbsp;&nbsp; Fernbedienung automatisch erzeugen
			</li>
			<li>
				<b>diverse Readings</b> &nbsp;&nbsp;-&nbsp;&nbsp; siehe Liste unten
			</li>
		</ul>
       </ul><br>
      <br>
      <b>Erzeugte Readings/Events:</b><br>
	  <br>
      <ul>
		<li>
			<b>autoStandby</b> &nbsp;&nbsp;-&nbsp;&nbsp; Standbyzustand des AV-Recievers
		</li>
		<li>
			<b>bass</b> &nbsp;&nbsp;-&nbsp;&nbsp; Bass-Level in dB
		</li>
		<li>
			<b>display</b> &nbsp;&nbsp;-&nbsp;&nbsp; Dim-Status des Displays
		</li>
		<li>
			<b>input</b> &nbsp;&nbsp;-&nbsp;&nbsp; gew&auml;hlte Eingangsquelle
		</li>
		<li>
			<b>levelFrontLeft</b> &nbsp;&nbsp;-&nbsp;&nbsp; Pegel des linken Frontlautsprechers in dB 
		</li>
		<li>
			<b>levelFrontRight</b> &nbsp;&nbsp;-&nbsp;&nbsp; Pegel des rechten Frontlautsprechers in dB 
		</li>
		<li>
			<b>mute</b> &nbsp;&nbsp;-&nbsp;&nbsp; Status der Stummschaltung
		</li>
		<li>
			<b>power</b> &nbsp;&nbsp;-&nbsp;&nbsp; Einschaltzustand des AV-Recievers
		</li>
		<li>
			<b>sound</b> &nbsp;&nbsp;-&nbsp;&nbsp; aktueller Sound-Modus
		</li>
		<li>
			<b>state</b> &nbsp;&nbsp;-&nbsp;&nbsp; Status des AV-Recievers (on,off,disconnected)
		</li>
		<li>
			<b>stateAV</b> &nbsp;&nbsp;-&nbsp;&nbsp; stateAV-Status des AV-Recievers (on,off,mute,absent)
		</li>
		<li>
			<b>toneControl</b> &nbsp;&nbsp;-&nbsp;&nbsp; Status der Klangkontrolle
		</li>
		<li>
			<b>treble</b> &nbsp;&nbsp;-&nbsp;&nbsp; H&ouml;hen-Level in dB
		</li>
		<li>
			<b>videoSelect</b> &nbsp;&nbsp;-&nbsp;&nbsp; gew&auml;hlter Videoselect-Modus
		</li>
		<li>
			<b>volume</b> &nbsp;&nbsp;-&nbsp;&nbsp; aktuelle Lautst&auml;rke in Prozent
		</li>
		<li>
			<b>volumeMax</b> &nbsp;&nbsp;-&nbsp;&nbsp; maximale Lautst&auml;rke in Prozent
		</li>
		<li>
			<b>volumeStraight</b> &nbsp;&nbsp;-&nbsp;&nbsp; aktuelle absolute Lautst&auml;rke in dB
		</li>
	   </ul>
		<br>
		<b>Attribute</b><br>
		<br>
		<ul>
		  <li>
			<b>IODev</b> &nbsp;&nbsp;-&nbsp;&nbsp; Input/Output Device
		  </li>
        </ul>
	</ul>


=end html_DE

=cut


