########################################################################################
#
# OWX_ASYNC.pm
#
# FHEM module to commmunicate with 1-Wire bus devices
# * via an active DS2480 bus master interface attached to an USB port
# * via an Arduino running ConfigurableFirmata attached to USB
# * via an Arduino running ConfigurableFirmata connecting to FHEM via Ethernet
#
# Norbert Truchsess
# Prof. Dr. Peter A. Henning
#
# $Id$
#
########################################################################################
#
# define <name> OWX_ASYNC <serial-device> for USB interfaces or
# define <name> OWX_ASYNC <arduino-pin> for a Arduino/Firmata (10_FRM.pm) interface
#    
# where <name> may be replaced by any name string 
#       <serial-device> is a serial (USB) device
#       <arduino-pin> is an Arduino pin 
#
# get <name> alarms                 => find alarmed 1-Wire devices (not with CUNO)
# get <name> devices                => find all 1-Wire devices 
# get <name> version                => OWX_ASYNC version number
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
# attr <name> interval <seconds>    => set period for temperature conversion and alarm testing
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

use ProtoThreads;
no warnings 'deprecated';

#-- unfortunately some things OS-dependent
my $SER_regexp;
if( $^O =~ /Win/ ) {
  require Win32::SerialPort;
  $SER_regexp= "com";
} else {
  require Device::SerialPort;
  $SER_regexp= "/dev/";
} 

use Time::HiRes qw( gettimeofday tv_interval );

sub Log3($$$);

use vars qw{%owg_family %gets %sets $owx_async_version $owx_async_debug};
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
$owx_async_version=5.12;
#-- Debugging 0,1,2,3
$owx_async_debug=0;

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
  $hash->{AttrFn}   = "OWX_ASYNC_Attr";
  $hash->{NotifyFn} = "OWX_ASYNC_Notify";
  $hash->{ReadFn}   = "OWX_ASYNC_Read";
  $hash->{ReadyFn}  = "OWX_ASYNC_Ready";
  $hash->{InitFn}   = "OWX_ASYNC_Init";
  $hash->{AttrList} = "dokick:0,1 interval buspower:real,parasitic IODev timeout maxtimeouts";
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
   	return "OWX: Syntax error - must be define <name> OWX <serial-device>|<arduino-pin>" if(int(@a) < 3);

	Log3 ($hash->{NAME},2,"OWX: Warning - Some parameter(s) ignored, must be define <name> OWX <serial-device>|<arduino-pin>") if( int(@a)>3 );
	my $dev = $a[2];
  
  $hash->{NOTIFYDEV} = "global";
  
	#-- Dummy 1-Wire ROM identifier, empty device lists
	$hash->{ROM_ID}      = "FF";
	$hash->{DEVS}        = [];
	$hash->{ALARMDEVS}   = [];
	$hash->{tasks}       = {};
  
  my $owx;
  #-- First step - different methods
  #-- check if we have a serial device attached
  if ( $dev =~ m|$SER_regexp|i or $dev =~ m/^(.+):([0-9]+)$/ ){
    require "$main::attr{global}{modpath}/FHEM/OWX_SER.pm";
    $owx = OWX_SER->new();
  #-- check if we have a COC/CUNO interface attached
  }elsif( (defined $main::defs{$dev} && (defined( $main::defs{$dev}->{VERSION} ) ? $main::defs{$dev}->{VERSION} : "") =~ m/CSM|CUNO/ )){
    require "$main::attr{global}{modpath}/FHEM/OWX_CCC.pm";
    $owx = OWX_CCC->new();
  #-- check if we are connecting to Arduino (via FRM):
  } elsif ($dev =~ /^\d{1,2}$/) {
  	require "$main::attr{global}{modpath}/FHEM/OWX_FRM.pm";
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

#######################################################################################
#
# OWTX_Attr - Set one attribute value for device
#
#  Parameter hash = hash of device addressed
#            a = argument array
#
########################################################################################

sub OWX_ASYNC_Attr(@) {
  my ($do,$name,$key,$value) = @_;

  my $hash = $main::defs{$name};
  my $ret;

  if ( $do eq "set") {
    SET_HANDLER: {
      $key eq "interval" and do {
        $hash->{interval} = $value;
        if ($main::init_done) {
          OWX_ASYNC_Kick($hash);
        }
        last;
      };
      $key eq "buspower" and do {
        if ($value eq "parasitic" and (defined $hash->{dokick}) and $hash->{dokick} ne "ignored") {
          $hash->{dokick} = "ignored";
          Log3($name,3,"OWX_ASYNC: ignoring attribute dokick because buspower is parasitic");
        } elsif ($value eq "real" and (defined $hash->{dokick}) and $hash->{dokick} eq "ignored") {
          $hash->{dokick} = $main::attr{$name}{dokick};
        }
        last;
      };
      $key eq "dokick" and do {
        if ($main::attr{$name}{"buspower"} and $main::attr{$name}{"buspower"} eq "parasitic" and ((!defined $hash->{dokick}) or $hash->{dokick} ne "ignored")) {
          $hash->{dokick} = "ignored";
          Log3($name,3,"OWX_ASYNC: ignoring attribute dokick because buspower is parasitic");
        } else {
          $hash->{dokick} = $value;
        }
        last;
      };
    }
  } elsif ( $do eq "del" ) {
    DEL_HANDLER: {
      $key eq "interval" and do {
        $hash->{interval} = 300;
        if ($main::init_done) {
          OWX_ASYNC_Kick($hash);
        }
        last;
      };
      $key eq "buspower" and do {
        if ((defined $hash->{dokick}) and $hash->{dokick} eq "ignored") {
          $hash->{dokick} = $main::attr{$name}{dokick};
        }
        last;
      };
      $key eq "dokick" and do {
        delete $hash->{dokick};
        last;
      };
    }
  }
  return $ret;
}

sub OWX_ASYNC_Notify ($$) {
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

sub OWX_ASYNC_Read ($) {
  my ($hash) = @_;
  Log3 ($hash->{NAME},5,"OWX_ASYNC_Read") if ($owx_async_debug > 2);
  if (defined $hash->{ASYNC}) {
    $hash->{ASYNC}->poll();
  };
  OWX_ASYNC_RunTasks($hash);
};

sub OWX_ASYNC_Disconnect($) {
  my ($hash) = @_;
  my $async = $hash->{ASYNC};
  Log3 ($hash->{NAME},3, "OWX_ASYNC_Disconnect");
  if (defined $async) {
    $async->exit($hash);
    delete $hash->{ASYNC};
  };
  $hash->{STATE} = "disconnected" if $hash->{STATE} eq "Active";
  $hash->{PRESENT} = 0;
  GP_ForallClients($hash,sub {
    my ($client) = @_;
    RemoveInternalTimer($client);
    readingsSingleUpdate($client,"present",0,$client->{PRESENT});
    $client->{PRESENT} = 0;
  },undef);
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

sub OWX_ASYNC_PT_Alarms ($) {
  my ($hash) = @_;
  
  #-- get the interface
  my $async = $hash->{ASYNC};

  #-- Discover all devices on the 1-Wire bus, they will be found in $hash->{DEVS}
  if (defined $async) {
    return PT_THREAD(sub {
      my ($thread) = @_;
      PT_BEGIN($thread);
      $thread->{pt_alarms} = $async->get_pt_alarms();
      $thread->{TimeoutTime} = gettimeofday()+2; #TODO: implement attribute-based timeout
      PT_WAIT_THREAD($thread->{pt_alarms});
      delete $thread->{TimeoutTime};
      die $thread->{pt_alarms}->PT_CAUSE() if ($thread->{pt_alarms}->PT_STATE() == PT_ERROR);
      if (defined (my $alarmed_devs = $thread->{pt_alarms}->PT_RETVAL())) {
        OWX_ASYNC_AfterAlarms($hash,$alarmed_devs);
      };
      PT_END;
    });
  } else {
    my $owx_interface = $hash->{INTERFACE};
    if( !defined($owx_interface) ) {
      die "OWX: Alarms called with undefined interface on bus $hash->{NAME}";
    } else {
      die "OWX: Alarms called with unknown interface $owx_interface on bus $hash->{NAME}";
    } 
  }
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
# alarmed_devs = Reference to Array of device-address-strings
#
# Returns: nothing
#
########################################################################################

sub OWX_ASYNC_AfterAlarms($$) {
  my ($hash,$alarmed_devs) = @_;
  my @alarmed_devnames = ();
  GP_ForallClients($hash,sub {
    my ($client) = @_;
    my $romid = $client->{ROM_ID};
    Log3 ($client->{IODev}->{NAME},5,"OWX_ASYNC_AfterAlarms client NAME: $client->{NAME}, ROM_ID: $romid, ALARM: $client->{ALARM}, alarmed_devs: [".join(",",@$alarmed_devs)."]") if ($owx_async_debug>2);
    if (grep {$romid eq $_} @$alarmed_devs) {
      readingsSingleUpdate($client,"alarm",1,!$client->{ALARM});
      $client->{ALARM}=1;
      push (@alarmed_devnames,$client->{NAME});
    } else {
      readingsSingleUpdate($client,"alarm",0, $client->{ALARM});
      $client->{ALARM}=0;
    }
  });
  $hash->{ALARMDEVS} = \@alarmed_devnames;
  Log3 ($hash->{NAME},5,"OWX_ASYNC_AfterAlarms: ALARMDEVS = [".join(",",@alarmed_devnames)."]") if ($owx_async_debug>2);
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

sub OWX_ASYNC_PT_Discover ($) {
	my ($hash) = @_;
	
  #-- get the interface
  my $async = $hash->{ASYNC};

  #-- Discover all devices on the 1-Wire bus, they will be found in $hash->{DEVS}
  if (defined $async) {
    return PT_THREAD(sub {
      my ($thread) = @_;
      PT_BEGIN($thread);
      $thread->{pt_discover} = $async->get_pt_discover();
      $thread->{TimeoutTime} = gettimeofday()+2; #TODO: implement attribute-based timeout
      PT_WAIT_THREAD($thread->{pt_discover});
      delete $thread->{TimeoutTime};
      die $thread->{pt_discover}->PT_CAUSE() if ($thread->{pt_discover}->PT_STATE() == PT_ERROR);
      if (my $owx_devices = $thread->{pt_discover}->PT_RETVAL()) {
        PT_EXIT(OWX_ASYNC_AutoCreate($hash,$owx_devices));
      };
      PT_END;
    });
  } else {
    my $owx_interface = $hash->{INTERFACE};
    if( !defined($owx_interface) ) {
      die "OWX: Discover called with undefined interface on bus $hash->{NAME}";
    } else {
      die "OWX: Discover called with unknown interface $owx_interface on bus $hash->{NAME}";
    } 
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

sub OWX_ASYNC_PT_Search($) {
  my ($hash) = @_;
  
  #-- get the interface
  my $async = $hash->{ASYNC};

  #-- Discover all devices on the 1-Wire bus, they will be found in $hash->{DEVS}
  if (defined $async) {
    return PT_THREAD(sub {
      my ($thread) = @_;
      PT_BEGIN($thread);
      $thread->{pt_discover} = $async->get_pt_discover();
      $thread->{TimeoutTime} = gettimeofday()+2; #TODO: implement attribute-based timeout
      PT_WAIT_THREAD($thread->{pt_discover});
      delete $thread->{TimeoutTime};
      die $thread->{pt_discover}->PT_CAUSE() if ($thread->{pt_discover}->PT_STATE() == PT_ERROR);
      if (defined (my $owx_devs = $thread->{pt_discover}->PT_RETVAL())) {
        OWX_ASYNC_AfterSearch($hash,$owx_devs);
      }
      PT_END;
    });
  } else {
    my $owx_interface = $hash->{INTERFACE};
    if( !defined($owx_interface) ) {
      die "OWX: Search called with undefined interface on bus $hash->{NAME}";
    } else {
      die "OWX: Search called with unknown interface $owx_interface on bus $hash->{NAME}";
    } 
  }
}

########################################################################################
#
# OWX_ASYNC_AfterSearch - is called when the search initiated by OWX_ASYNC_Search successfully returns
#
# stores device-addresses found in $hash->{DEVS}
#
# Attention: this function is not intendet to be called directly!
#
# Parameter hash = hash of bus master
# owx_devs = Reference to Array of device-address-strings
#
# Returns: nothing
#
########################################################################################

sub OWX_ASYNC_AfterSearch($$) {
  my ($hash,$owx_devs) = @_;
#  if (defined $owx_devs and (ref($owx_devs) eq "ARRAY")) {
  my @devnames = ();
  GP_ForallClients($hash,sub {
    my ($client) = @_;
    my $romid = $client->{ROM_ID};
    Log3 ($client->{IODev}->{NAME},5,"OWX_ASYNC_AfterSearch client NAME: $client->{NAME}, ROM_ID: $romid, PRESENT: $client->{PRESENT}, devs: [".join(",",@$owx_devs)."]") if ($owx_async_debug>2);
    if (grep {$romid eq $_} @$owx_devs) {
      readingsSingleUpdate($client,"present",1,!$client->{PRESENT});
      $client->{PRESENT} = 1;
      push (@devnames,$client->{NAME});
    } else {
      readingsSingleUpdate($client,"present",0,$client->{PRESENT});
      $client->{PRESENT} = 0;
    }
  });
  $hash->{DEVS} = \@devnames;
  Log3 ($hash->{NAME},5,"OWX_ASYNC_AfterSearch: DEVS = [".join(",",@devnames)."]") if ($owx_async_debug>2);
#  }
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
          readingsSingleUpdate($main::defs{$fhem_dev},"present",1,!$main::defs{$fhem_dev}->{PRESENT});
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
          readingsSingleUpdate($main::defs{$acname},"present",1,!$main::defs{$acname}->{PRESENT});
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

  my ($task,$task_state);

  if( $a[1] eq "alarms") {
    eval {
      OWX_ASYNC_RunToCompletion($hash,OWX_ASYNC_PT_Alarms($hash));
    };
    return $@ if $@;
    unless ( defined $hash->{ALARMDEVS} and @{$hash->{ALARMDEVS}}) {
      return "OWX: No alarmed 1-Wire devices found on bus $name";
    }
    return "OWX: ".scalar(@{$hash->{ALARMDEVS}})." alarmed 1-Wire devices found on bus $name (".join(",",@{$hash->{ALARMDEVS}}).")";
  } elsif( $a[1] eq "devices") {
    eval {
      $task_state = OWX_ASYNC_RunToCompletion($hash,OWX_ASYNC_PT_Discover($hash));
    };
    return $@ if $@;
    return $task_state;
  } elsif( $a[1] eq "version") {
    return $owx_async_version;
    
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
    delete $hash->{ASYNC}; #TODO should we call delete on $hash->{ASYNC}?
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
    Log3 ($hash->{NAME},4,"OWX_ASYNC_Init failed: $@") if $@;
    if (my $err = GP_Catch($@)) {
      $hash->{PRESENT} = 0;
      $hash->{STATE} = "Init Failed: $err";
      return "OWX_ASYNC_Init failed: $err";
    };
    return undef unless $ret;
    $hash->{ASYNC} = $ret ;
    $hash->{ASYNC}->{debug} = $owx_async_debug;
    $hash->{INTERFACE} = $owx->{interface};
  } else {
    return "OWX: Init called with undefined interface";
  }

  $hash->{STATE} = "Active";

  #-- Fourth step: discovering devices on the bus
  #   in 10 seconds discover all devices on the 1-Wire bus
  my $pt_discover = OWX_ASYNC_PT_Discover($hash);
  $pt_discover->{ExecuteTime} = gettimeofday()+10;
  eval {
    OWX_ASYNC_Schedule($hash,$pt_discover);
  };
  return GP_Catch($@) if $@;

  #-- Default settings
  $hash->{interval}     = AttrVal($hash->{NAME},"interval",300);          # kick every 5 minutes
  $hash->{followAlarms} = "off";
  $hash->{ALARMED}      = "no";
  
  #-- InternalTimer blocks if init_done is not true
  $hash->{PRESENT} = 1;
  #readingsSingleUpdate($hash,"state","defined",1);
  #-- Intiate first alarm detection and eventually conversion in a minute or so
  InternalTimer(gettimeofday() + $hash->{interval}, "OWX_ASYNC_Kick", $hash,0);
  GP_ForallClients($hash,\&OWX_ASYNC_InitClient,undef);
  return undef;
}

sub OWX_ASYNC_InitClient {
  my ($hash) = @_;
	my $name = $hash->{NAME};
	#return undef unless (defined $hash->{InitFn});
	my $ret = CallFn($name,"InitFn",$hash);
	if ($ret) {
		Log3 $name,2,"error initializing '".$hash->{NAME}."': ".$ret;
	}
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

  unless ($hash->{".kickrunning"}) {
    $hash->{".kickrunning"} = 1;
    eval {
      OWX_ASYNC_Schedule( $hash, PT_THREAD(sub {
        my ($thread) = @_;
        PT_BEGIN($thread);
        #-- Only if we have the dokick attribute set to 1
        if ((defined $hash->{dokick}) and $hash->{dokick} eq "1") {
          Log3 $hash->{NAME},5,"OWX_ASYNC_PT_Kick: kicking DS14B20 temperature conversion";
          #-- issue the skip ROM command \xCC followed by start conversion command \x44 
          $thread->{pt_execute} = OWX_ASYNC_PT_Execute($hash,1,undef,"\x44",0);
          $thread->{TimeoutTime} = gettimeofday()+2; #TODO: implement attribute-based timeout
          PT_WAIT_THREAD($thread->{pt_execute});
          delete $thread->{TimeoutTime};
          if ($thread->{pt_execute}->PT_STATE() == PT_ERROR) {
            Log3 ($hash->{NAME},4,"OWX_ASYNC_PT_Kick: Failure in temperature conversion: ".$thread->{pt_execute}->PT_CAUSE());
          } else {
            $thread->{ExecuteTime} = gettimeofday()+1;
            PT_YIELD_UNTIL(gettimeofday() >= $thread->{ExecuteTime});
            delete $thread->{ExecuteTime};
            GP_ForallClients($hash,sub { 
              my ($client) = @_;
              if ($client->{TYPE} eq "OWTHERM" and AttrVal($client->{NAME},"tempConv","") eq "onkick" ) {
                Log3 $client->{NAME},5,"OWX_ASYNC_PT_Kick: doing tempConv for $client->{NAME}";
                OWX_ASYNC_Schedule($client, OWXTHERM_PT_GetValues($client) );
              }
            },undef);
          }
        }
  
        $thread->{pt_search} = OWX_ASYNC_PT_Search($hash);
        $thread->{TimeoutTime} = gettimeofday()+2; #TODO: implement attribute-based timeout
        PT_WAIT_THREAD($thread->{pt_search});
        delete $thread->{Timeouttime};
        if ($thread->{pt_search}->PT_STATE() == PT_ERROR) {
          Log3 ($hash->{NAME},4,"OWX_ASYNC_PT_Kick: Failure in search: ".$thread->{pt_search}->PT_CAUSE());
        } else {
          $thread->{pt_alarms} = OWX_ASYNC_PT_Alarms($hash);
          $thread->{TimeoutTime} = gettimeofday()+2; #TODO: implement attribute-based timeout
          PT_WAIT_THREAD($thread->{pt_alarms});
          delete $thread->{TimeoutTime};
          if ($thread->{pt_alarms}->PT_STATE() == PT_ERROR) {
            Log3 ($hash->{NAME},4,"OWX_ASYNC_PT_Kick: Failure in alarm-search: ".$thread->{pt_alarms}->PT_CAUSE());
          };
        }
        delete $hash->{".kickrunning"};
        PT_END;
      }));
    };
    Log3 ($hash->{NAME},4,"OWX_ASYNC_PT_Kick".GP_Catch($@)) if ($@);
  }
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

sub OWX_ASYNC_PT_Verify($) {
  my ($hash) = @_;

  #-- get the interface
  my $async = $hash->{IODev}->{ASYNC};
  my $romid = $hash->{ROM_ID};

  #-- Verify a devices is present on the 1-Wire bus
  return PT_THREAD(sub {
    my ($thread) = @_;
    PT_BEGIN($thread);

    if (defined $async) {

      $thread->{pt_verify} = $async->get_pt_verify($romid);
      $thread->{TimeoutTime} = gettimeofday()+2; #TODO: implement attribute-based timeout
      PT_WAIT_THREAD($thread->{pt_verify});
      delete $thread->{TimeoutTime};
      die $thread->{pt_verify}->PT_CAUSE() if ($thread->{pt_verify}->PT_STATE() == PT_ERROR);

      my $value = $thread->{pt_verify}->PT_RETVAL();

      if( $value == 0 ){
        readingsSingleUpdate($hash,"present",0,$hash->{PRESENT}); 
      } else {
        readingsSingleUpdate($hash,"present",1,!$hash->{PRESENT}); 
      }
      $hash->{PRESENT} = $value;
    } else {
      my $owx_interface = $hash->{IODev}->{INTERFACE};
      if( !defined($owx_interface) ) {
        die "OWX: Verify called with undefined interface on bus $hash->{IODev}->{NAME}";
      } else {
        die "OWX: Verify called with unknown interface $owx_interface on bus $hash->{IODev}->{NAME}";
      } 
    }
    PT_END;
  });
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

sub OWX_ASYNC_PT_Execute($$$$$) {
  my ( $hash, $reset, $owx_dev, $data, $numread ) = @_;
  if (my $executor = $hash->{ASYNC}) {
    return $executor->get_pt_execute($reset,$owx_dev,$data,$numread);
  } else {
    die "OWX_ASYNC_PT_Execute: no async device assigned";
  }
}

sub OWX_ASYNC_Schedule($$) {
  my ( $hash, $task ) = @_;
  my $master = $hash->{TYPE} eq "OWX_ASYNC" ? $hash : $hash->{IODev};
  my $name = $hash->{NAME};
  Log3 ($master->{NAME},5,"OWX_ASYNC_Schedule master: ".$master->{NAME}.", task: ".$name);
  die "OWX_ASYNC_Schedule: Master not Active" unless $master->{STATE} eq "Active";
  $task->{ExecuteTime} = gettimeofday() unless (defined $task->{ExecuteTime});

  #if buspower is parasitic serialize all tasks by scheduling everything to master queue.
  $name = $master->{NAME} if (AttrVal($master->{NAME},"buspower","real") eq "parasitic");

  if (defined $master->{tasks}->{$name}) {
    push @{$master->{tasks}->{$name}}, $task;
    $hash->{NUMTASKS} = @{$master->{tasks}->{$name}};
  } else {
    $master->{tasks}->{$name} = [$task];
    $hash->{NUMTASKS} = 1;
  }
  #TODO make use of $master->{".nexttasktime"}
  InternalTimer($task->{ExecuteTime}, "OWX_ASYNC_RunTasks", $master,0);
};

sub OWX_ASYNC_RunToCompletion($$) {
  my ($hash,$task) = @_;

  my $task_state;  
  eval {
    OWX_ASYNC_Schedule($hash,$task);
    my $master = $hash->{TYPE} eq "OWX_ASYNC" ? $hash : $hash->{IODev};
    do {
      die "interface $master->{INTERFACE} not active" unless defined $master->{ASYNC};
      $master->{ASYNC}->poll();
      OWX_ASYNC_RunTasks($master);
      $task_state = $task->PT_STATE();
    } while ($task_state == PT_INITIAL or $task_state == PT_WAITING or $task_state == PT_YIELDED);
  };
  die $@ if $@;
  die $task->PT_CAUSE() if ($task_state == PT_ERROR or $task_state == PT_CANCELED);
  return $task->PT_RETVAL();  
}

sub OWX_ASYNC_RunTasks($) {
  my ( $master ) = @_;
  if ($master->{STATE} eq "Active") {
    Log3 ($master->{NAME},5,"OWX_ASYNC_RunTasks: called") if ($owx_async_debug>2);
    my $now = gettimeofday();
    while(1) {
      my @queue_waiting  = ();
      my @queue_ready    = ();
      my @queue_sleeping = ();
      my @queue_initial  = ();
      foreach my $name (keys %{$master->{tasks}}) {
        my $queue = $master->{tasks}->{$name};
        while (@$queue) {
          my $state = $queue->[0]->PT_STATE();
          if ($state == PT_WAITING) {
            push @queue_waiting,{ device => $name, queue => $queue};
            last;
          } elsif ($state == PT_YIELDED) {
            if ($now >= $queue->[0]->{ExecuteTime}) {
              push @queue_ready, { device => $name, queue => $queue};
            } else {
              push @queue_sleeping, { device => $name, queue => $queue};
            }
            last;
          } elsif ($state == PT_INITIAL) {
            push @queue_initial, { device => $name, queue => $queue};
            last;
          } else {
            shift @$queue;
            $main::defs{$name}->{NUMTASKS} = @$queue;
          }
        };
        delete $master->{tasks}->{$name} unless (@$queue);
      }
      if (defined (my $current = @queue_waiting ? shift @queue_waiting : @queue_ready ? shift @queue_ready : @queue_initial ? shift @queue_initial : undef)) {
        my $task = $current->{queue}->[0];
        my $timeout = $task->{TimeoutTime};
        if ($task->PT_SCHEDULE()) {
          my $state = $task->PT_STATE();
          # waiting for ExecuteResponse:
          if ($state == PT_WAITING) {
            if (defined $task->{TimeoutTime}) {
              #task timed out:
              if ($now >= $task->{TimeoutTime}) {
                Log3 ($master->{NAME},4,"OWX_ASYNC_RunTasks: $current->{device} task timed out");
                Log3 ($master->{NAME},5,sprintf("OWX_ASYNC_RunTasks: TimeoutTime: %.6f, now: %.6f",$task->{TimeoutTime},$now)) if ($owx_async_debug>1);
                $task->PT_CANCEL("Timeout");
                shift @{$current->{queue}};
                $main::defs{$current->{device}}->{NUMTASKS} = @{$current->{queue}};
                $master->{TIMEOUTS}++;
                if ($master->{TIMEOUTS} > AttrVal($master->{NAME},"maxtimeouts",5)) {
                  Log3 ($master->{NAME},3,"OWX_ASYNC_RunTasks: $master->{NAME} maximum number of timeouts exceedet ($master->{TIMEOUTS}), trying to reconnect");
                  OWX_ASYNC_Disconnect($master);
                  $master->{TIMEOUTS} = 0;
                }
                next;
              } else {
                Log3 $master->{NAME},5,"OWX_ASYNC_RunTasks: $current->{device} task waiting for data or timeout" if ($owx_async_debug>2);
                #new timeout or timeout did change:
                if (!defined $timeout or $timeout != $task->{TimeoutTime}) {
                  Log3 $master->{NAME},5,sprintf("OWX_ASYNC_RunTasks: $current->{device} task schedule for timeout at %.6f",$task->{TimeoutTime});
                  InternalTimer($task->{TimeoutTime}, "OWX_ASYNC_RunTasks", $master,0);
                }
                last;
              }
            } else {
              Log3 ($master->{NAME},4,"$current->{device} unexpected thread state PT_WAITING without TimeoutTime");
              $task->{TimeoutTime} = $now + 2; #TODO implement attribute based timeout
            }
          # sleeping:
          } elsif ($state == PT_YIELDED) {
            next;
          } else {
            Log3 ($master->{NAME},4,"$current->{device} unexpected thread state while running: $state");
          }
        } else {
          my $state = $task->PT_STATE();
          if ($state == PT_ENDED) {
            Log3 ($master->{NAME},5,"OWX_ASYNC_RunTasks: $current->{device} task finished");
            $master->{TIMEOUTS} = 0;
          } elsif ($state == PT_EXITED) {
            Log3 ($master->{NAME},4,"OWX_ASYNC_RunTasks: $current->{device} task exited: ".(defined $task->PT_RETVAL() ? $task->PT_RETVAL : "- no retval -"));
          } elsif ($state == PT_ERROR) {
            Log3 ($master->{NAME},4,"OWX_ASYNC_RunTasks: $current->{device} task Error: ".$task->PT_CAUSE());
            $main::defs{$current->{device}}->{PRESENT} = 0;
          } else {
            Log3 ($master->{NAME},4,"$current->{device} unexpected thread state after termination: $state");
          }
          shift @{$current->{queue}};
          $main::defs{$current->{device}}->{NUMTASKS} = @{$current->{queue}};
          next;
        }
      } else {
        my $nexttime;
        my $nextdevice;
        foreach my $current (@queue_sleeping) {
          # if task is scheduled for future:
          if (!defined $nexttime or ($nexttime > $current->{queue}->[0]->{ExecuteTime})) {
            $nexttime = $current->{queue}->[0]->{ExecuteTime};
            $nextdevice = $current->{device};
          }
        }
        if (defined $nexttime) {
          if ($nexttime > $now) {
            if (!defined $master->{".nexttasktime"} or $nexttime < $master->{".nexttasktime"} or $now >= $master->{".nexttasktime"}) {
              Log3 $master->{NAME},5,sprintf("OWX_ASYNC_RunTasks: $nextdevice schedule next at %.6f",$nexttime) if ($owx_async_debug);
              main::InternalTimer($nexttime, "OWX_ASYNC_RunTasks", $master,0);
              $master->{".nexttasktime"} = $nexttime;
            } else {
              Log3 $master->{NAME},5,sprintf("OWX_ASYNC_RunTasks: $nextdevice skip %.6f, allready scheduled at %.6f",$nexttime,$master->{".nexttasktime"}) if ($owx_async_debug>2);
            }
          } else {
            Log3 $master->{NAME},5,sprintf("OWX_ASYNC_RunTasks: $nextdevice nexttime at %.6f allready passed",$nexttime) if ($owx_async_debug>2);
          }
        } else {
          Log3 $master->{NAME},5,sprintf("OWX_ASYNC_RunTasks: -undefined- no nexttime") if ($owx_async_debug>2);
        }
        Log3 $master->{NAME},5,sprintf("OWX_ASYNC_RunTasks: -undefined- exit loop") if ($owx_async_debug>2);
        last;
      }
    };
  }
};

1;

=pod
=begin html

<a name="OWX_ASYNC"></a>
        <h3>OWX_ASYNC</h3>
        <p> FHEM module to commmunicate with 1-Wire bus devices</p>
        <ul>
            <li>via an active DS2480 bus master interface attached to an USB port or </li>
            <li>via an Arduino running ConfigurableFirmata attached to USB</li>
            <li>via an Arduino running ConfigurableFirmata connecting to FHEM via Ethernet</li>
        </ul>
        <p>Internally these interfaces are vastly different, read the corresponding <a
            href="http://fhemwiki.de/wiki/Interfaces_f%C3%BCr_1-Wire"> Wiki pages </a></p>
        <p>OWX_ASYNC does pretty much the same job as <a href="#OWX">OWX</a> does, but using
        	an asynchronous mode of communication</p> 
        <br />
        <br />
        <h4>Example</h4><br />
        <p>
            <code>define OWio1 OWX_ASYNC /dev/ttyUSB1</code>
            <br />
            <code>define OWio3 OWX_ASYNC 10</code>
            <br />
        </p>
        <br />
        <a name="OWX_ASYNCdefine"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; OWX_ASYNC &lt;serial-device&gt;</code> or <br />
            <code>define &lt;name&gt; OWX_ASYNC &lt;cuno/coc-device&gt;</code> or <br />
            <code>define &lt;name&gt; OWX_ASYNC &lt;arduino-pin&gt;</code>
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
        <a name="OWX_ASYNCset"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="owx_async_interval">
                    <code>set &lt;name&gt; interval &lt;value&gt;</code>
                </a>
                <br />sets the time period in seconds for "kicking" the 1-Wire bus when the <a href="#OWX_ASYNCdokick">dokick attribute</a> is set (default
                is 300 seconds).
            </li>
            <li><a name="owx_async_followAlarms">
                    <code>set &lt;name&gt; followAlarms on|off</code>
                </a>
                <br /><br /> instructs the module to start an alarm search in case a reset pulse
                discovers any 1-Wire device which has the alarm flag set. </li>
        </ul>
        <br />
        <a name="OWX_ASYNCget"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="owx_async_alarms"></a>
                <code>get &lt;name&gt; alarms</code>
                <br /><br /> performs an "alarm search" for devices on the 1-Wire bus and, if found,
                generates an event in the log (not with CUNO). </li>
            <li><a name="owx_async_devices"></a>
                <code>get &lt;name&gt; devices</code>
                <br /><br /> redicovers all devices on the 1-Wire bus. If a device found has a
                previous definition, this is automatically used. If a device is found but has no
                definition, it is autocreated. If a defined device is not on the 1-Wire bus, it is
                autodeleted. </li>
        </ul>
        <br />
        <a name="OWX_ASYNCattr"></a>
        <h4>Attributes</h4>
        <ul>
            <li><a name="OWX_ASYNCdokick"><code>attr &lt;name&gt; dokick 0|1</code></a>
                <br />1 if the interface regularly kicks thermometers on the bus to do a temperature conversion, 
                and to perform an alarm check, 0 if not</li>
            <li><a name="OWX_ASYNCbuspower"><code>attr &lt;name&gt; buspower real|parasitic</code></a>
                <br />parasitic if there are any devices on the bus that steal power from the data line.
                <br />Ensures that never more than a single device on the bus is talked to (throughput is throttled noticable!)
                <br />Automatically disables attribute 'dokick'.</li>
            <li><a name="OWX_ASYNCIODev"><code>attr &lt;name&gt; IODev &lt;FRM-device&gt;</code></a>
                <br />assignes a specific FRM-device to OWX_ASYNC when working through an Arduino. 
                <br />Required only if there is more than one FRM defined.</li>
            <li><a name="OWX_ASYNCmaxtimeouts"><code>attr &lt;name&gt; maxtimeouts &lt;number&gt;</code></a>
                <br />maximum number of timeouts (in a row) before OWX_ASYNC disconnects itself from the
                busmaster and tries to establish a new connection</li>
            <li>Standard attributes <a href="#alias">alias</a>, <a href="#comment">comment</a>, <a
                    href="#event-on-update-reading">event-on-update-reading</a>, <a
                    href="#event-on-change-reading">event-on-change-reading</a>, <a href="#room"
                    >room</a>, <a href="#eventMap">eventMap</a>,
                    <a href="#webCmd">webCmd</a></li>
        </ul>

=end html
=cut
