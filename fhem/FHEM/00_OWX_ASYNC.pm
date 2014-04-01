########################################################################################
#
# OWX.pm
#
# FHEM module to commmunicate with 1-Wire bus devices
# * via an active DS2480/DS2482/DS2490/DS9097U bus master interface attached to an USB port
# * via a passive DS9097 interface attached to an USB port
# * via a network-attached CUNO
# * via a COC attached to a Raspberry Pi
# * via an Arduino running OneWireFirmata attached to USB
#
# Prof. Dr. Peter A. Henning
# Norbert Truchsess
#
# $Id: 00_OWX.pm 2013-03 - pahenning $
#
########################################################################################
#
# define <name> OWX <serial-device> for USB interfaces or
# define <name> OWX <cuno/coc-device> for a CUNO or COC interface
# define <name> OWX <arduino-pin> for a Arduino/Firmata (10_FRM.pm) interface
#    
# where <name> may be replaced by any name string 
#       <serial-device> is a serial (USB) device
#       <cuno/coc-device> is a CUNO or COC device
#       <arduino-pin> is an Arduino pin 
#
# get <name> alarms                 => find alarmed 1-Wire devices (not with CUNO)
# get <name> devices                => find all 1-Wire devices 
# get <name> version                => OWX version number
#
# set <name> interval <seconds>     => set period for temperature conversion and alarm testing
# set <name> followAlarms on/off    => determine whether an alarm is followed by a search for
#                                      alarmed devices
#
# attr <name> dokick 0/1            => 1 if the interface regularly kicks thermometers on the
#                                      bus to do a temperature conversion, 
#                                      and to make an alarm check
#                                      0 if not
#
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
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
########################################################################################
package main;

use strict;
use warnings;
use GPUtils qw(:all);

#add FHEM/lib to @INC if it's not allready included. Should rather be in fhem.pl than here though...
BEGIN {
	if (!grep(/FHEM\/lib$/,@INC)) {
		foreach my $inc (grep(/FHEM$/,@INC)) {
			push @INC,$inc."/lib";
		};
	};
};

#-- unfortunately some things OS-dependent
my $SER_regexp;
if( $^O =~ /Win/ ) {
  require Win32::SerialPort;
  $SER_regexp= "com";
} else {
  require Device::SerialPort;
  $SER_regexp= "/dev/";
} 

use Time::HiRes qw(gettimeofday);

require "$main::attr{global}{modpath}/FHEM/DevIo.pm";
sub Log3($$$);

use vars qw{%owg_family %gets %sets $owx_version $owx_debug};
# 1-Wire devices 
# http://owfs.sourceforge.net/family.html
%owg_family = (
  "01"  => ["DS2401/DS1990A","OWID DS2401"],
  "05"  => ["DS2405","OWID 05"],
  "10"  => ["DS18S20/DS1920","OWTHERM DS1820"],
  "12"  => ["DS2406/DS2507","OWSWITCH DS2406"],
  "1B"  => ["DS2436","OWID 1B"],
  "1D"  => ["DS2423","OWCOUNT DS2423"],
  "20"  => ["DS2450","OWAD DS2450"],
  "22"  => ["DS1822","OWTHERM DS1822"],
  "24"  => ["DS2415/DS1904","OWID 24"],
  "26"  => ["DS2438","OWMULTI DS2438"],
  "27"  => ["DS2417","OWID 27"],
  "28"  => ["DS18B20","OWTHERM DS18B20"],
  "29"  => ["DS2408","OWSWITCH DS2408"],
  "3A"  => ["DS2413","OWSWITCH DS2413"],
  "3B"  => ["DS1825","OWID 3B"],
  "81"  => ["DS1420","OWID 81"],
  "FF"  => ["LCD","OWLCD"]
);

#-- These we may get on request
%gets = (
   "alarms"  => "A",
   "devices" => "D",
   "version" => "V"
);

#-- These occur in a pulldown menu as settable values for the bus master
%sets = (
   "interval"     => "T",
   "followAlarms" => "F"
);

#-- These are attributes
my %attrs = (
);

#-- some globals needed for the 1-Wire module
$owx_version=4.6;
#-- Debugging 0,1,2,3
$owx_debug=0;

########################################################################################
#
# The following subroutines are independent of the bus interface
#
########################################################################################
#
# OWX_ASYNC_Initialize
#
# Parameter hash = hash of device addressed
#
########################################################################################

sub OWX_ASYNC_Initialize ($) {
  my ($hash) = @_;
  #-- Provider
  $hash->{Clients} = ":OWAD:OWCOUNT:OWID:OWLCD:OWMULTI:OWSWITCH:OWTHERM:";

  #-- Normal Devices
  $hash->{DefFn}    = "OWX_ASYNC_Define";
  $hash->{UndefFn}  = "OWX_ASYNC_Undef";
  $hash->{GetFn}    = "OWX_ASYNC_Get";
  $hash->{SetFn}    = "OWX_ASYNC_Set";
  $hash->{NotifyFn} = "OWX_ASYNC_Notify";
  $hash->{ReadFn}   = "OWX_ASYNC_Poll";
  $hash->{ReadyFn}  = "OWX_ASYNC_Ready";
  $hash->{InitFn}   = "OWX_ASYNC_Init";
  $hash->{AttrList} = "dokick:0,1 async:0,1 IODev timeout";
  main::LoadModule("OWX");
}

########################################################################################
#
# OWX_ASYNC_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
#
########################################################################################

sub OWX_ASYNC_Define ($$) {
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
  
	#-- check syntax
   	return "OWX: Syntax error - must be define <name> OWX <serial-device>|<cuno/coc-device>|<arduino-pin>" if(int(@a) < 3);

	Log3 ($hash->{NAME},2,"OWX: Warning - Some parameter(s) ignored, must be define <name> OWX <serial-device>|<cuno/coc-device>|<arduino-pin>") if( int(@a)>3 );
	my $dev = $a[2];
  
  $hash->{NOTIFYDEV} = "global";
  
	#-- Dummy 1-Wire ROM identifier, empty device lists
	$hash->{ROM_ID}      = "FF";
	$hash->{DEVS}        = [];
	$hash->{ALARMDEVS}   = [];
  
  my $owx;
  #-- First step - different methods
  #-- check if we have a serial device attached
  if ( $dev =~ m|$SER_regexp|i){  
    require "$main::attr{global}{modpath}/FHEM/11_OWX_SER.pm";
    $owx = OWX_SER->new();
  #-- check if we have a COC/CUNO interface attached  
  }elsif( (defined $main::defs{$dev} && (defined( $main::defs{$dev}->{VERSION} ) ? $main::defs{$dev}->{VERSION} : "") =~ m/CSM|CUNO/ )){
    require "$main::attr{global}{modpath}/FHEM/11_OWX_CCC.pm";
    $owx = OWX_CCC->new();
  #-- check if we are connecting to Arduino (via FRM):
  } elsif ($dev =~ /^\d{1,2}$/) {
  	require "$main::attr{global}{modpath}/FHEM/11_OWX_FRM.pm";
    $owx = OWX_FRM->new();
  } else {
    return "OWX: Define failed, unable to identify interface type $dev"
  };
  
  my $ret = $owx->Define($hash,$def);
  #-- cancel definition of OWX if interface define fails 
  return $ret if $ret;  
  	
  $hash->{OWX} = $owx;
  $hash->{INTERFACE} = $owx->{interface};

  $hash->{STATE} = "Defined";

  if ($main::init_done) {
    return OWX_ASYNC_Init($hash);
  }
	return undef;
}

sub OWX_ASYNC_Notify {
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};

  if( grep(m/^(INITIALIZED|REREADCFG)$/, @{$dev->{CHANGED}}) ) {
  	OWX_ASYNC_Init($hash);
  } elsif( grep(m/^SAVE$/, @{$dev->{CHANGED}}) ) {
  }
}

sub OWX_ASYNC_Ready ($) {
  my $hash = shift;
  unless ( $hash->{STATE} eq "Active" ) {
    my $ret = OWX_ASYNC_Init($hash);
    if ($ret) {
      Log3 ($hash->{NAME},2,"OWX: Error initializing ".$hash->{NAME}.": ".$ret);
      return undef;
    }
  }
	return 1;
};

sub OWX_ASYNC_Poll ($) {
	my $hash = shift;
	if (defined $hash->{ASYNC}) {
		$hash->{ASYNC}->poll($hash);
	};
};

sub OWX_ASYNC_Disconnect($) {
	my ($hash) = @_;
	my $async = $hash->{ASYNC};
	Log3 ($hash->{NAME},3, "OWX_ASYNC_Disconnect");
	if (defined $async) {
		$async->exit($hash);
	};
	my $times = AttrVal($hash->{NAME},"timeout",5000) / 50; #timeout in ms, defaults to 1 sec?
	for (my $i=0;$i<$times;$i++) {
		OWX_ASYNC_Poll($hash);
		if ($hash->{STATE} ne "Active") {
			last;
		}
	};
};

sub OWX_ASYNC_Disconnected($) {
	my ($hash) = @_;
	Log3 ($hash->{NAME},4, "OWX_ASYNC_Disconnected");
	if ($hash->{ASYNC} and $hash->{ASYNC} != $hash->{OWX}) {
		delete $hash->{ASYNC};
	};
	if (my $owx = $hash->{OWX}) {
		$owx->Disconnect($hash);
	};
	$hash->{STATE} = "disconnected" if $hash->{STATE} eq "Active";
};	

########################################################################################
#
# OWX_ASYNC_Alarms - Initiate search for devices on the 1-Wire bus which have the alarm flag set
#
# Parameter hash = hash of bus master
#
# Return: 1 if search could be successfully initiated. Message or list of alarmed devices
#     undef otherwise
#TODO fix OWX_ASYNC_Alarms return value on failure
########################################################################################

sub OWX_ASYNC_Alarms ($) {
	my ($hash) = @_;

	#-- get the interface
	my $name          = $hash->{NAME};
	my $async           = $hash->{ASYNC};
	my $res;

	if (defined $async) {
		delete $hash->{ALARMDEVS};
		return $async->alarms($hash);
	} else {
		#-- interface error
		my $owx_interface = $hash->{INTERFACE};
		if( !(defined($owx_interface))){
			return undef;
		} else {
			return "OWX: Alarms called with unknown interface $owx_interface on bus $name";
		}
	}
};

#######################################################################################
#
# OWX_ASYNC_AwaitAlarmsResponse - Wait for the result of a call to OWX_ASYNC_Alarms 
#
# Parameter hash = hash of bus master
#
# Return: Reference to Array of alarmed 1-Wire-addresses found on 1-Wire bus.
#         undef if timeout occours
#
########################################################################################

sub OWX_ASYNC_AwaitAlarmsResponse($) {
	my ($hash) = @_;

	#-- get the interface
	my $async           = $hash->{ASYNC};
	if (defined $async) {
		my $times = AttrVal($hash->{NAME},"timeout",5000) / 50; #timeout in ms, defaults to 1 sec #TODO add attribute timeout?
		for (my $i=0;$i<$times;$i++) {
			if(! defined $hash->{ALARMDEVS} ) {
				select (undef,undef,undef,0.05);
				$async->poll($hash);
			} else {
				return $hash->{ALARMDEVS};
			};
		};
	};
	return undef;
}

########################################################################################
#
# OWX_ASYNC_AfterAlarms - is called when the search for alarmed devices that was initiated by OWX_ASYNC_Alarms successfully returns
#
# stores device-addresses found in $hash->{ALARMDEVS}
#
# Attention: this function is not intendet to be called directly! 
#
# Parameter hash = hash of bus master
#       alarmed_devs = Reference to Array of device-address-strings
#
# Returns: nothing
#
########################################################################################

sub OWX_ASYNC_AfterAlarms($$) {
  my ($hash,$alarmed_devs) = @_;
  $hash->{ALARMDEVS} = $alarmed_devs;
  GP_ForallClients($hash,sub {
  	my ($hash,$devs) = @_;
  	my $romid = $hash->{ROM_ID};
  	if (grep {/$romid/} @$devs) {
  		readingsSingleUpdate($hash,"alarm",1,!$hash->{ALARM});
  		$hash->{ALARM}=1;
  	} else {
  		readingsSingleUpdate($hash,"alarm",0, $hash->{ALARM});
  		$hash->{ALARM}=0;
  	}
  },$alarmed_devs);
};

########################################################################################
#
# OWX_ASYNC_DiscoverAlarms - Search for devices on the 1-Wire bus which have the alarm flag set
#
# Parameter hash = hash of bus master
#
# Return: Message or list of alarmed devices
#
########################################################################################

sub OWX_ASYNC_DiscoverAlarms($) {
  my ($hash) = @_;
  if (OWX_ASYNC_Alarms($hash)) {
  	if (my $alarmed_devs = OWX_ASYNC_AwaitAlarmsResponse($hash)) {
      my @owx_alarm_names=();
      my $name = $hash->{NAME};
  	
  if( $alarmed_devs == 0){
    return "OWX: No alarmed 1-Wire devices found on bus $name";
  }
  #-- walk through all the devices to get their proper fhem names
  foreach my $fhem_dev (sort keys %main::defs) {
    #-- skip if busmaster
    next if( $name eq $main::defs{$fhem_dev}{NAME} );
    #-- all OW types start with OW
    next if( substr($main::defs{$fhem_dev}{TYPE},0,2) ne "OW");
    foreach my $owx_dev  (@{$alarmed_devs}) {
      #-- two pieces of the ROM ID found on the bus
      my $owx_rnf = substr($owx_dev,3,12);
      my $owx_f   = substr($owx_dev,0,2);
      my $id_owx  = $owx_f.".".$owx_rnf;
        
      #-- skip if not in alarm list
      if( $owx_dev eq $main::defs{$fhem_dev}{ROM_ID} ){
        $main::defs{$fhem_dev}{STATE} = "Alarmed";
        push(@owx_alarm_names,$main::defs{$fhem_dev}{NAME});
      }
    }
  }
  #-- so far, so good - what do we want to do with this ?
  return "OWX: ".scalar(@owx_alarm_names)." alarmed 1-Wire devices found on bus $name (".join(",",@owx_alarm_names).")";
  	}
  }
};

########################################################################################
#
# OWX_ASYNC_Discover - Discover devices on the 1-Wire bus, 
#                autocreate devices if not already present
#
# Parameter hash = hash of bus master
#
# Return: List of devices in table format or undef
#
########################################################################################

sub OWX_ASYNC_Discover ($) {
	my ($hash) = @_;
	if (OWX_ASYNC_Search($hash)) {
		if (my $owx_devices = OWX_ASYNC_AwaitSearchResponse($hash)) {
			return OWX_ASYNC_AutoCreate($hash,$owx_devices);			
		};
	} else {
		return undef;
	}
}

#######################################################################################
#
# OWX_ASYNC_Search - Initiate Search for devices on the 1-Wire bus 
#
# Parameter hash = hash of bus master
#
# Return: 1, if initiation of search could be startet, undef if not
#
########################################################################################

sub OWX_ASYNC_Search($) {
	my ($hash) = @_;
  
	my $res;
	my $ow_dev;
  
	#-- get the interface
	my $async = $hash->{ASYNC};

	#-- Discover all devices on the 1-Wire bus, they will be found in $hash->{DEVS}
	if (defined $async) {
		delete $hash->{DEVS};
		return $async->discover($hash);
	} else {
		my $owx_interface = $hash->{INTERFACE};
		if( !defined($owx_interface) ) {
			return undef;
		} else {
			Log3 ($hash->{NAME},3,"OWX: Search called with unknown interface $owx_interface");
			return undef;
		} 
	}
}

#######################################################################################
#
# OWX_ASYNC_AwaitSearchResponse - Wait for the result of a call to OWX_ASYNC_Search 
#
# Parameter hash = hash of bus master
#
# Return: Reference to Array of 1-Wire-addresses found on 1-Wire bus.
#         undef if timeout occours
#
########################################################################################

sub OWX_ASYNC_AwaitSearchResponse($) {
	my ($hash) = @_;
	#-- get the interface
	my $async = $hash->{ASYNC};

	#-- Discover all devices on the 1-Wire bus, they will be found in $hash->{DEVS}
	if (defined $async) {
		my $times = AttrVal($hash->{NAME},"timeout",5000) / 50; #timeout in ms, defaults to 1 sec #TODO add attribute timeout?
		for (my $i=0;$i<$times;$i++) {
			if(! defined $hash->{DEVS} ) {
				select (undef,undef,undef,0.05);
				$async->poll($hash);
			} else {
				return $hash->{DEVS};
			};
		};
	};
	return undef;
};

########################################################################################
#
# OWX_ASYNC_AfterSearch - is called when the search initiated by OWX_ASYNC_Search successfully returns
#
# stores device-addresses found in $hash->{DEVS}
#
# Attention: this function is not intendet to be called directly! 
#
# Parameter hash = hash of bus master
#       owx_devs = Reference to Array of device-address-strings
#
# Returns: nothing
#
########################################################################################

sub OWX_ASYNC_AfterSearch($$) {
  my ($hash,$owx_devs) = @_;
  if (defined $owx_devs and (ref($owx_devs) eq "ARRAY")) {
  	$hash->{DEVS} = $owx_devs;
  	GP_ForallClients($hash,sub {
  		my ($hash,$devs) = @_;
  		my $romid = $hash->{ROM_ID};
  		if (grep {/$romid/} @$devs) {
  			readingsSingleUpdate($hash,"present",1,!$hash->{PRESENT});
  			$hash->{PRESENT} = 1;
  		} else {
  			readingsSingleUpdate($hash,"present",0,$hash->{PRESENT});
  			$hash->{PRESENT} = 0;
  		}
  	},$owx_devs);
  }
}

########################################################################################
#
# OWX_ASYNC_Autocreate - autocreate devices if not already present
#
# Parameter hash = hash of bus master
#       owx_devs = Reference to Array of device-address-strings as OWX_ASYNC_AfterSearch stores in $hash->{DEVS}
#
# Return: List of devices in table format or undef
#
########################################################################################

sub OWX_ASYNC_AutoCreate($$) { 
  my ($hash,$owx_devs) = @_;
  my $name = $hash->{NAME};
  my ($chip,$acstring,$acname,$exname);
  my $ret= "";
  my @owx_names=();
  
  if (defined $owx_devs and (ref($owx_devs) eq "ARRAY")) {
    #-- Go through all devices found on this bus
    foreach my $owx_dev  (@{$owx_devs}) {
      #-- ignore those which do not have the proper pattern
      if( !($owx_dev =~ m/[0-9A-F]{2}\.[0-9A-F]{12}\.[0-9A-F]{2}/) ){
        Log3 ($hash->{NAME},3,"OWX: Invalid 1-Wire device ID $owx_dev, ignoring it");
        next;
      }
    
      #-- three pieces of the ROM ID found on the bus
      my $owx_rnf = substr($owx_dev,3,12);
      my $owx_f   = substr($owx_dev,0,2);
      my $owx_crc = substr($owx_dev,16,2);
      my $id_owx  = $owx_f.".".$owx_rnf;
      
      my $match = 0;
    
      #-- Check against all existing devices  
      foreach my $fhem_dev (sort keys %main::defs) { 
        #-- skip if busmaster
        # next if( $hash->{NAME} eq $main::defs{$fhem_dev}{NAME} );
        #-- all OW types start with OW
        next if( !defined($main::defs{$fhem_dev}{TYPE}));
        next if( substr($main::defs{$fhem_dev}{TYPE},0,2) ne "OW");
        my $id_fhem = substr($main::defs{$fhem_dev}{ROM_ID},0,15);
        #-- skip interface device
        next if( length($id_fhem) != 15 );
        #-- testing if equal to the one found here  
        #   even with improper family
        #   Log 1, " FHEM-Device = ".substr($id_fhem,3,12)." OWX discovered device ".substr($id_owx,3,12);
        if( substr($id_fhem,3,12) eq substr($id_owx,3,12) ) {
          #-- warn if improper family id
          if( substr($id_fhem,0,2) ne substr($id_owx,0,2) ){
            Log3 ($hash->{NAME},3, "OWX: Warning, $fhem_dev is defined with improper family id ".substr($id_fhem,0,2). 
             ", must enter correct model in configuration");
             #$main::defs{$fhem_dev}{OW_FAMILY} = substr($id_owx,0,2);
          }
          $exname=$main::defs{$fhem_dev}{NAME};
          push(@owx_names,$exname);
          #-- replace the ROM ID by the proper value including CRC
          $main::defs{$fhem_dev}{ROM_ID}=$owx_dev;
          $main::defs{$fhem_dev}{PRESENT}=1;    
          $match = 1;
          last;
        }
        #
      }
 
      #-- Determine the device type
      if(exists $owg_family{$owx_f}) {
        $chip     = $owg_family{$owx_f}[0];
        $acstring = $owg_family{$owx_f}[1];
      }else{  
        Log3 ($hash->{NAME},3, "OWX: Unknown family code '$owx_f' found");
        #-- All unknown families are ID only
        $chip     = "unknown";
        $acstring = "OWID $owx_f";  
      }
      #Log 1,"###\nfor the following device match=$match, chip=$chip name=$name acstring=$acstring";
      #-- device exists
      if( $match==1 ){
        $ret .= sprintf("%s.%s      %-14s %s\n", $owx_f,$owx_rnf, $chip, $exname);
      #-- device unknown, autocreate
      }else{
        #-- example code for checking global autocreate - do we want this ?
        #foreach my $d (keys %defs) {
        #next if($defs{$d}{TYPE} ne "autocreate");
        #return undef if(AttrVal($defs{$d}{NAME},"disable",undef));
        $acname = sprintf "OWX_%s_%s",$owx_f,$owx_rnf;
        #Log 1, "to define $acname $acstring $owx_rnf";
        my $res = CommandDefine(undef,"$acname $acstring $owx_rnf");
        if($res) {
          $ret.= "OWX: Error autocreating with $acname $acstring $owx_rnf: $res\n";
        } else{
          select(undef,undef,undef,0.1);
          push(@owx_names,$acname);
          $main::defs{$acname}{PRESENT}=1;
          #-- THIS IODev, default room (model is set in the device module)
          CommandAttr (undef,"$acname IODev $hash->{NAME}"); 
          CommandAttr (undef,"$acname room OWX"); 
          #-- replace the ROM ID by the proper value 
          $main::defs{$acname}{ROM_ID}=$owx_dev;
          $ret .= sprintf("%s.%s      %-10s %s\n", $owx_f,$owx_rnf, $chip, $acname);
        } 
      }
    }
  }

  #-- final step: Undefine all 1-Wire devices which 
  #   are autocreated and
  #   not discovered on this bus 
  #   but have this IODev
  foreach my $fhem_dev (sort keys %main::defs) {
    #-- skip if malformed device
    #next if( !defined($main::defs{$fhem_dev}{NAME}) );
    #-- all OW types start with OW, but safeguard against deletion of other devices
    #next if( !defined($main::defs{$fhem_dev}{TYPE}));
    next if( substr($main::defs{$fhem_dev}{TYPE},0,2) ne "OW");
    next if( uc($main::defs{$fhem_dev}{TYPE}) eq "OWX");
    next if( uc($main::defs{$fhem_dev}{TYPE}) eq "OWFS");
    next if( uc($main::defs{$fhem_dev}{TYPE}) eq "OWSERVER");
    next if( uc($main::defs{$fhem_dev}{TYPE}) eq "OWDEVICE");
    #-- restrict to autocreated devices
    next if( $main::defs{$fhem_dev}{NAME} !~ m/OWX_[0-9a-fA-F]{2}_/);
    #-- skip if the device is present.
    next if( $main::defs{$fhem_dev}{PRESENT} == 1);
    #-- skip if different IODev, but only if other IODev exists
    if ( $main::defs{$fhem_dev}{IODev} ){
      next if( $main::defs{$fhem_dev}{IODev}{NAME} ne $hash->{NAME} );
    }
    Log3 ($hash->{NAME},3, "OWX: Deleting unused 1-Wire device $main::defs{$fhem_dev}{NAME} of type $main::defs{$fhem_dev}{TYPE}");
    CommandDelete(undef,$main::defs{$fhem_dev}{NAME});
    #Log 1, "present= ".$main::defs{$fhem_dev}{PRESENT}." iodev=".$main::defs{$fhem_dev}{IODev}{NAME};
  }
  #-- Log the discovered devices
  Log3 ($hash->{NAME},2, "OWX: 1-Wire devices found on bus $name (".join(",",@owx_names).")");
  #-- tabular view as return value
  return "OWX: 1-Wire devices found on bus $name \n".$ret;
}   

########################################################################################
#
# OWX_ASYNC_Get - Implements GetFn function 
#
#  Parameter hash = hash of the bus master a = argument array
#
########################################################################################

sub OWX_ASYNC_Get($@) {
  my ($hash, @a) = @_;
  return "OWX: Get needs exactly one parameter" if(@a != 2);

  my $name     = $hash->{NAME};
  my $owx_dev  = $hash->{ROM_ID};

  if( $a[1] eq "alarms") {
    my $res = OWX_ASYNC_DiscoverAlarms($hash);
    #-- process result
    return $res
    
  } elsif( $a[1] eq "devices") {
    my $res = OWX_ASYNC_Discover($hash);
    #-- process result
    return $res
        
  } elsif( $a[1] eq "version") {
    return $owx_version;
    
  } else {
    return "OWX: Get with unknown argument $a[1], choose one of ". 
    join(" ", sort keys %gets);
  }
}

#######################################################################################
# 
# OWX_ASYNC_Init - Re-Initialize the device 
#
# Parameter hash = hash of bus master
#
# Return 0 or undef : OK
#        1 or Errormessage : not OK
#
########################################################################################

sub OWX_ASYNC_Init ($) {
  my ($hash)=@_;
  
  RemoveInternalTimer($hash);
  if (defined ($hash->{ASNYC})) {
  	$hash->{ASYNC}->exit($hash);
  	$hash->{ASYNC} = undef; #TODO should we call delete on $hash->{ASYNC}?
  } 
  #-- get the interface
  my $owx = $hash->{OWX};
  
  if (defined $owx) {
	$hash->{INTERFACE} = $owx->{interface};
	my $ret;
	#-- Third step: see, if a bus interface is detected
	eval {
	  $ret = $owx->initialize($hash);
	};
	if (my $err = GP_Catch($@)) {
	  $hash->{PRESENT} = 0;
	  $hash->{STATE} = "Init Failed: $err";
	  return "OWX_ASYNC_Init failed: $err";
	};
	$hash->{ASYNC} = $ret;
   	$hash->{INTERFACE} = $owx->{interface};
  } else {
    return "OWX: Init called with undefined interface";
  }
  
  #-- Fourth step: discovering devices on the bus
  #   in 10 seconds discover all devices on the 1-Wire bus
  InternalTimer(gettimeofday()+10, "OWX_ASYNC_Discover", $hash,0);
  
  #-- Default settings
  $hash->{interval}     = 300;          # kick every 5 minutes
  $hash->{followAlarms} = "off";
  $hash->{ALARMED}      = "no";
  
  #-- InternalTimer blocks if init_done is not true
  $hash->{PRESENT} = 1;
  #readingsSingleUpdate($hash,"state","defined",1);
  #-- Intiate first alarm detection and eventually conversion in a minute or so
  InternalTimer(gettimeofday() + $hash->{interval}, "OWX_ASYNC_Kick", $hash,0);
  $hash->{STATE} = "Active";
  return undef;
}

########################################################################################
#
# OWX_ASYNC_Kick - Initiate some processes in all devices
#
# Parameter hash = hash of bus master
#
# Return 1 : OK
#        0 : Not OK
#
########################################################################################

sub OWX_ASYNC_Kick($) {
  my($hash) = @_;
  my $ret;

  #-- Call us in n seconds again.
  InternalTimer(gettimeofday()+ $hash->{interval}, "OWX_ASYNC_Kick", $hash,0);

  #-- Only if we have the dokick attribute set to 1
  if (main::AttrVal($hash->{NAME},"dokick",0)) {
    #-- issue the skip ROM command \xCC followed by start conversion command \x44 
    $ret = OWX_Execute($hash,"kick",1,undef,"\xCC\x44",0,undef);
    if( !$ret ){
      Log3 ($hash->{NAME},3, "OWX: Failure in temperature conversion\n");
      return 0;
    }
  }
  
  if (OWX_ASYNC_Search($hash)) {
    OWX_ASYNC_Alarms($hash);
  };
  
  return 1;
}

########################################################################################
#
# OWX_ASYNC_Set - Implements SetFn function
# 
# Parameter hash , a = argument array
#
########################################################################################

sub OWX_ASYNC_Set($@) {
  my ($hash, @a) = @_;
  my $name = shift @a;
  my $res;

  #-- First we need to find the ROM ID corresponding to the device name
  my $owx_romid =  $hash->{ROM_ID};
  Log3 ($hash->{NAME},5, "OWX_ASYNC_Set request $name $owx_romid ".join(" ",@a));

  #-- for the selector: which values are possible
  return join(" ", sort keys %sets) if(@a != 2);
  return "OWX_ASYNC_Set: With unknown argument $a[0], choose one of " . join(" ", sort keys %sets)
    if(!defined($sets{$a[0]}));
    
  #-- Set timer value
  if( $a[0] eq "interval" ){
    #-- only values >= 15 secs allowed
    if( $a[1] >= 15){
      $hash->{interval} = $a[1];
  	  $res = 1;
  	} else {
  	  $res = 0;
  	}
  }
  
  #-- Set alarm behaviour
  if( $a[0] eq "followAlarms" ){
    #-- only values >= 15 secs allowed
    if( (lc($a[1]) eq "off") && ($hash->{followAlarms} eq "on") ){
      $hash->{followAlarms} = "off";  
  	  $res = 1;
  	}elsif( (lc($a[1]) eq "on") && ($hash->{followAlarms} eq "off") ){
      $hash->{followAlarms} = "on";  
  	  $res = 1;
  	} else {
  	  $res = 0;
  	}
    
  }
  Log3 ($name,3, "OWX_ASYNC_Set $name ".join(" ",@a)." => $res");  
  DoTrigger($name, undef) if($main::init_done);
  return "OWX_ASYNC_Set => $name ".join(" ",@a)." => $res";
}

########################################################################################
#
# OWX_ASYNC_Undef - Implements UndefFn function
#
# Parameter hash = hash of the bus master, name
#
########################################################################################

sub OWX_ASYNC_Undef ($$) {
  my ($hash, $name) = @_;
  RemoveInternalTimer($hash);
  OWX_ASYNC_Disconnect($hash);
  return undef;
}

########################################################################################
#
# OWX_ASYNC_Verify - Verify a particular device on the 1-Wire bus
#
# Parameter hash = hash of bus master, dev =  8 Byte ROM ID of device to be tested
#
# Return 1 : device found
#        0 : device not found
#
########################################################################################

sub OWX_ASYNC_Verify ($$) {
	my ($hash,$dev) = @_;
	my $address = substr($dev,0,15);
	if (OWX_ASYNC_Search($hash)) {
		if (my $owx_devices = OWX_ASYNC_AwaitSearchResponse($hash)) {
		  if (grep {/$address/} @{$owx_devices}) {
		    return 1;
			};
		};
	}
	return 0;
}

########################################################################################
#
# OWX_Execute - # similar to OWX_Complex, but asynchronous
# executes a sequence of 'reset','skip/match ROM','write','read','delay' on the bus
#
# Parameter hash = hash of bus master,
#        context = anything that can be sent as a hash-member through a thread-safe queue 
#                  see http://perldoc.perl.org/Thread/Queue.html#DESCRIPTION
#          reset = 1/0 if 1 reset the bus first 
#        owx_dev = 8 Byte ROM ID of device to be tested, if undef do a 'skip ROM' instead
#           data = bytes to write (string)
#        numread = number of bytes to read after write
#          delay = optional delay (in ms) to wait after executing the next command 
#                  for the same device
#
# Returns : 1 if OK
#           0 if not OK
#
########################################################################################


sub OWX_Execute($$$$$$$) {
	my ( $hash, $context, $reset, $owx_dev, $data, $numread, $delay ) = @_;
	if (my $executor = $hash->{ASYNC}) {
		delete $hash->{replies}{$owx_dev}{$context} if (defined $owx_dev and defined $context);
		return $executor->execute( $hash, $context, $reset, $owx_dev, $data, $numread, $delay );
	} else {
		return 0;
	}
};

#######################################################################################
#
# OWX_AwaitExecuteResponse - Wait for the result of a call to OWX_Execute 
#
# Parameter hash = hash of bus master
#        context = correlates the response with the call to OWX_Execute
#        owx_dev = 1-Wire-address of device that is to be read
#
# Return: Data that has been read from device
#         undef if timeout occours
#
########################################################################################

sub OWX_AwaitExecuteResponse($$$) {
	my ($hash,$context,$owx_dev) = @_;
	#-- get the interface
	my $async = $hash->{ASYNC};

	#-- Discover all devices on the 1-Wire bus, they will be found in $hash->{DEVS}
	if (defined $async and defined $owx_dev and defined $context) {
		my $times = AttrVal($hash->{NAME},"timeout",5000) / 50; #timeout in ms, defaults to 1 sec
		for (my $i=0;$i<$times;$i++) {
			if(! defined $hash->{replies}{$owx_dev}{$context}) {
				select (undef,undef,undef,0.05);
				$async->poll($hash);
			} else {
				return $hash->{replies}{$owx_dev}{$context};
			};
		};
	};
	return undef;
};

########################################################################################
#
# OWX_ASYNC_AfterExecute - is called when a query initiated by OWX_Execute successfully returns
#
# calls 'AfterExecuteFn' on the devices module (if such is defined)
# stores data read in $hash->{replies}{$owx_dev}{$context} after calling 'AfterExecuteFn'
#
# Attention: this function is not intendet to be called directly! 
#
# Parameter hash = hash of bus master
#        context = context parameter of call to OWX_Execute. Allows to correlate request and response
#        success = indicates whether an error did occur
#          reset = indicates whether a reset was carried out
#        owx_dev = 1-wire device-address
#           data = data written to the 1-wire device before read was executed
#        numread = number of bytes requested from 1-wire device
#       readdata = bytes read from 1-wire device
#
# Returns: nothing
#
########################################################################################

sub OWX_ASYNC_AfterExecute($$$$$$$$) {
	my ( $master, $context, $success, $reset, $owx_dev, $writedata, $numread, $readdata ) = @_;

	Log3 ($master->{NAME},5,"AfterExecute:".
	" context: ".(defined $context ? $context : "undef").
	", success: ".(defined $success ? $success : "undef").
	", reset: ".(defined $reset ? $reset : "undef").
	", owx_dev: ".(defined $owx_dev ? $owx_dev : "undef").
	", writedata: ".(defined $writedata ? unpack ("H*",$writedata) : "undef").
	", numread: ".(defined $numread ? $numread : "undef").
	", readdata: ".(defined $readdata ? unpack ("H*",$readdata) : "undef"));

	if (defined $owx_dev) {
		foreach my $d ( sort keys %main::defs ) {
			if ( my $hash = $main::defs{$d} ) {
				if ( defined( $hash->{ROM_ID} )
				  && defined( $hash->{IODev} )
				  && $hash->{IODev} == $master
				  && $hash->{ROM_ID} eq $owx_dev ) {
				  if ($main::modules{$hash->{TYPE}}{AfterExecuteFn}) {
				    my $ret = CallFn($d,"AfterExecuteFn", $hash, $context, $success, $reset, $owx_dev, $writedata, $numread, $readdata);
				    Log3 ($master->{NAME},4,"OWX_ASYNC_AfterExecute [".(defined $owx_dev ? $owx_dev : "unknown owx device")."]: $ret") if ($ret);
				    if ($success) {
				      readingsSingleUpdate($hash,"PRESENT",1,1) unless ($hash->{PRESENT});
				    } else {
				      readingsSingleUpdate($hash,"PRESENT",0,1) if ($hash->{PRESENT});
				    }
					}
				}
			}
		}
		if (defined $context) {
			$master->{replies}{$owx_dev}{$context} = $readdata;
		}
	}
};

1;

=pod
=begin html

<a name="OWX"></a>
        <h3>OWX</h3>
        <p> FHEM module to commmunicate with 1-Wire bus devices</p>
        <ul>
            <li>via an active DS2480/DS2482/DS2490/DS9097U bus master interface attached to an USB
                port or </li>
            <li>via a passive DS9097 interface attached to an USB port or</li>
            <li>via a network-attached CUNO or through a COC on the RaspBerry Pi</li>
            <li>via an Arduino running OneWireFirmata attached to USB</li>
        </ul> Internally these interfaces are vastly different, read the corresponding <a
            href="http://fhemwiki.de/wiki/Interfaces_f%C3%BCr_1-Wire"> Wiki pages </a>
        <br />
        <br />
        <h4>Example</h4><br />
        <p>
            <code>define OWio1 OWX /dev/ttyUSB1</code>
            <br />
            <code>define OWio2 OWX COC</code>
            <br />
            <code>define OWio3 OWX 10</code>
            <br />
        </p>
        <br />
        <a name="OWXdefine"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; OWX &lt;serial-device&gt;</code> or <br />
            <code>define &lt;name&gt; OWX &lt;cuno/coc-device&gt;</code> or <br />
            <code>define &lt;name&gt; OWX &lt;arduino-pin&gt;</code>
            <br /><br /> Define a 1-Wire interface to communicate with a 1-Wire bus.<br />
            <br />
        </p>
        <ul>
            <li>
                <code>&lt;serial-device&gt;</code> The serial device (e.g. USB port) to which the
                1-Wire bus is attached.</li>
            <li>
                <code>&lt;cuno-device&gt;</code> The previously defined CUNO to which the 1-Wire bus
                is attached. </li>
            <li>
                <code>&lt;arduino-pin&gt;</code> The pin of the previous defined <a href="#FRM">FRM</a>
                to which the 1-Wire bus is attached. If there is more than one FRM device defined
                use <a href="#IODev">IODev</a> attribute to select which FRM device to use.</li>
        </ul>
        <br />
        <a name="OWXset"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="owx_interval">
                    <code>set &lt;name&gt; interval &lt;value&gt;</code>
                </a>
                <br />sets the time period in seconds for "kicking" the 1-Wire bus when the <a href="#OWXdokick">dokick attribute</a> is set (default
                is 300 seconds).
            </li>
            <li><a name="owx_followAlarms">
                    <code>set &lt;name&gt; followAlarms on|off</code>
                </a>
                <br /><br /> instructs the module to start an alarm search in case a reset pulse
                discovers any 1-Wire device which has the alarm flag set. </li>
        </ul>
        <br />
        <a name="OWXget"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="owx_alarms"></a>
                <code>get &lt;name&gt; alarms</code>
                <br /><br /> performs an "alarm search" for devices on the 1-Wire bus and, if found,
                generates an event in the log (not with CUNO). </li>
            <li><a name="owx_devices"></a>
                <code>get &lt;name&gt; devices</code>
                <br /><br /> redicovers all devices on the 1-Wire bus. If a device found has a
                previous definition, this is automatically used. If a device is found but has no
                definition, it is autocreated. If a defined device is not on the 1-Wire bus, it is
                autodeleted. </li>
        </ul>
        <br />
        <a name="OWXattr"></a>
        <h4>Attributes</h4>
        <ul>
            <li><a name="OWXdokick"><code>attr &lt;name&gt; dokick 0|1</code></a>
                <br />1 if the interface regularly kicks thermometers on the bus to do a temperature conversion, 
               and to perform an alarm check, 0 if not</li>
            <li><a name="OWXIODev"><code>attr &lt;name&gt; IODev <FRM-device></code></a>
                <br />assignes a specific FRM-device to OWX when working through an Arduino. 
                Required only if there is more than one FRM defined.</li>
            <li>Standard attributes <a href="#alias">alias</a>, <a href="#comment">comment</a>, <a
                    href="#event-on-update-reading">event-on-update-reading</a>, <a
                    href="#event-on-change-reading">event-on-change-reading</a>, <a href="#room"
                    >room</a>, <a href="#eventMap">eventMap</a>,
                    <a href="#webCmd">webCmd</a></li>
        </ul>

=end html
=cut
