###############################################################################
#
# $Id: 96_RenaultZE.pm  2023-10-15 plin $
# 96_RenaultZE.pm
#
# Forum : https://forum.fhem.de/index.php/topic,116273.0.html
# Ref https://renault-api.readthedocs.io/en/latest/endpoints.html
#
###############################################################################
#
#  (c) 2017 Copyright: plin
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and imPORTant notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
##################################################################################

#######################################################################
# need: 
# - HttpUtils
# - Time::Piece
# - JSON
#
########################################################################

############################################################################################################################
# Version History
# v 1.14 changed code for automatic update of readings distance/home during 
# v 1.13 recalculation of varius readings distance/home during update
# v 1.12 implemented new Attribute ze_homeRadius
# v 1.11 implemented new function GET checkAPIkeys
# v 1.10 addedd attribute brand, 'Dacia' will allow start/stop charge, additional readings after issueing get vehicles
# v 1.09 fixed problem with readingsBulkUpdate/readingsSingleUpdate in lines 1002ff
# v 1.08 new KAMERON API key
# v 1.07 adjusting to new output  format from charges
# v 1.06 logging "well known error" Failed to forward request to remote service only at log level 5
# v 1.05 fixed timing problem in update request
# v 1.04 typo denbled corrected
# v 1.03 hvac settings output corrected
# v 1.02 some minor corrections
# v 1.01 added hvac-settings
# v 1.00 added module to the contrib directory
# v 0.32 added attribute disabled
# v 0.31 changed API keys due to change by Renault
# v 0.30 fixed problem with bulk update
# v 0.29 fixed problem with from_json
# v 0.28 fixed timestamp issue
# v 0.27 added error-Reading in case of malformed json string
# v 0.26 fixed decode_json issue (additional tests)
# v 0.25 fixed decode_json issue
# v 0.24 get link for car image from vehicles listing
# v 0.23 pretty print ze_lastErr
# v 0.22 interpret charges data, default time frames for histories
# v 0.21 implemented further get options implemented for Phase 1 already
# v 0.20 implemented zTest attribute to test new options
# v 0.19 fix for time format "2021-01-27T16:41:42+01:00"
# v 0.18 renamed distance to distanceFromHome
# v 0.17 added reverse geocoding
# v 0.16 added distance from home
# v 0.15 minor fix (warning messages)
# v 0.14 detect '<html>' in $data (RenaultZE_gData_Step2)
# v 0.13 fixed timezone problem for UTC timestamps
# v 0.12 fixed attr problem country/county
# v 0.11 fixed parameter problem when using timer
# v 0.10 fixed timer problem
# v 0.9 changed logic, new readings
# v 0.8 suppress 0 readings
# v 0.7 fixed timer problem
# v 0.6 bug fixes
# v 0.5 improved feedback and error code checking
# v 0.4 fix bug when accId = 0
# v 0.3 adjusted options an placed hint about untested option
# v 0.2 set commands were added
# v 0.1 first version with get options 
############################################################################################################################
# code basis
# - https://github.com/jamesremuscat/pyze
# - https://gist.github.com/mountbatt/772e4512089802a2aa2622058dd1ded7
# API keys
# - https://renault-wrd-prod-1-euw1-myrapp-one.s3-eu-west-1.amazonaws.com/configuration/android/config_de_DE.json
#  KAMEREON_API -> "wiredProd" -> apikey
#  GIGYA_API    -> "gigyaProd" -> apikey
#  oder https://renault-wrd-prod-1-euw1-myrapp-one.s3-eu-west-1.amazonaws.com/configuration/iOS/config_de_DE.json ???
############################################################################################################################

# lock-status

package main;
use strict;
use warnings;

use HttpUtils;
use Time::Piece;
#use JSON qw(decode_json);
use JSON;

my $RenaultZE_version ="V1.14 / 1.11.2023";

my %RenaultZE_sets = (
	"AC:on,cancel"       => "",
	"charge:start,stop"  => "",
	"password"           => "",
	"state"              => ""
);

my %RenaultZE_gets = (
	"charge-history"                    => "",
	"charges"                           => "",
	"charging-settings:noArg"           => "",
	"hvac-history"                      => "",
	"hvac-settings:noArg"               => "",
	"notification-settings:noArg"       => "",
	"update:noArg"                      => "",
	"vehicles:noArg"                    => "",
	"checkAPIkeys:noArg"                => "",
	"zTest"                             => ""
);

sub RenaultZE_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}         = 'RenaultZE_Define';
    $hash->{UndefFn}       = 'RenaultZE_Undef';
    $hash->{SetFn}         = 'RenaultZE_Set';
    $hash->{GetFn}         = 'RenaultZE_Get';
    $hash->{AttrFn}        = 'RenaultZE_Attr';
    $hash->{ReadFn}        = 'RenaultZE_Read';
    $hash->{AsyncOutputFn} = 'RenaultZE_AsyncOutput';

    $hash->{AttrList} = "ze_phase:1,2 ".
			"ze_brand:Renault,Dacia ".
    			"ze_user ".
			"ze_country ".
			"ze_latitude ".
			"ze_longitude ".
			"ze_homeRadius ".
			"ze_showaddress:0,1 ".
			"ze_showimage:0,1,2 ".
			"disabled:0,1 ".
                        $readingFnAttributes;
}

sub RenaultZE_Define($$) {
    my ($hash, $def) = @_;
    my @param = split('[ \t]+', $def);
    
    if(int(@param) < 3) {
        return "too few parameters: define <name>  RenaultZE <vin> <interval>";
    }
     
    my $name              = $param[0];
    $hash->{VIN}          = $param[2];
    $hash->{INTERVAL}     = $param[3];


    $hash->{STATE}        = "defined";
    $hash->{GIGYA_API}    = '3_7PLksOyBRkHv126x5WhHb-5pqC1qFR8pQjxSeLB6nhAnPERTUlwnYoznHSxwX668';
    #$hash->{KAMEREON_API} = 'Ae9FDWugRxZQAGm3Sxgk7uJn6Q4CGEA2';
    #$hash->{KAMEREON_API} = 'VAX7XYKGfa92yMvXculCkEFyfZbuM7Ss';
    #$hash->{KAMEREON_API} = 'YjkKtHmGfaceeuExUDKGxrLZGGvtVS0J';
    $hash->{KAMEREON_API} = 'YjkKtHmGfaceeuExUDKGxrLZGGvtVS0J';
    #$hash->{KAMEREON_API} = 'oF09WnKqvBDcrQzcW1rJNpjIuy7KdGaB';
    $hash->{VERSION}      = $RenaultZE_version;

    readingsSingleUpdate($hash,"ze_Gigya_JWT_lastCall","0",1) unless (ReadingsVal($name,"ze_Gigya_JWT_lastCall","empty") ne "empty");
    readingsSingleUpdate($hash,"ze_Gigya_JWT_Token","",1)     unless (ReadingsVal($name,"ze_Gigya_JWT_Token","empty") ne "empty");

    $attr{$name}{ze_country}       = 'DE'                  unless (exists($attr{$name}{ze_country}));
    $attr{$name}{ze_showaddress}   = '1'                   unless (exists($attr{$name}{ze_showaddress}));
    $attr{$name}{ze_showimage}     = '1'                   unless (exists($attr{$name}{ze_showimage}));

    my $firstTrigger = gettimeofday() + 2;
    $hash->{TRIGGERTIME}     = $firstTrigger;
    $hash->{TRIGGERTIME_FMT} = FmtDateTime($firstTrigger);

    RemoveInternalTimer($hash);
    InternalTimer($firstTrigger, "RenaultZE_UpdateTimer", $hash, 0);
    Log3 $hash, 5, "TRAFFIC: ($name) InternalTimer set to call GetUpdate in 2 seconds for the first time";

    return undef;
}

sub RenaultZE_Undef($$) {
    my ($hash, $arg) = @_; 
    # nothing to do
    RemoveInternalTimer( $hash );
    return undef;
}

sub RenaultZE_Get($@) {
	my ($hash, @param) = @_;
	
	my $name = shift @param;
	my $opt = shift @param;
	my $value = join("", @param);

	if ($opt ne "?")
	{
            $hash->{FUNCTION} = 'GET';
            $hash->{PARMS}    = $opt;
            $hash->{PARMVALUE} = $value;
	    $hash->{curCL} = $hash->{CL};
	}

        Log3 $name, 5, "RenaultZE_Get - opt = $opt, value = $value";

	readingsSingleUpdate($hash,"ze_lastErr","",1)                       if ($opt ne "?");

        if ($opt eq "update")
        {
	   readingsSingleUpdate($hash,"ze_Step","getStatus",1);
	   RenaultZE_Main1($hash, @param);
        }

        elsif ($opt eq "vehicles")
        {
	   readingsSingleUpdate($hash,"ze_Step","getVehicles",1);
	   RenaultZE_Main1($hash, @param);
        }

        elsif ($opt eq "charge-history")
        {
	   if ($value eq "") {
   	       my $tt      = localtime()->strftime('%Y%m%d');
               $value = "type=day&start=20000101&end=".$tt;
	       $hash->{PARMVALUE} = $value;
	   }
	   if ( $value =~ /type=month&start=\d{6}&end=\d{6}/ or $value =~ /type=day&start=\d{8}&end=\d{8}/) {  	
	      readingsSingleUpdate($hash,"ze_Step","getHistory",1);
	      RenaultZE_Main1($hash, @param);
	   } else  {
		return "Syntax error for $opt, correct pattern is 'type=month&start=202012&end=202101' or 'type=day&start=20201212&end=20210120'";
           }
        }

        elsif ($opt eq "charges")
        {
	   if ($value eq "") {
   	       my $tt      = localtime()->strftime('%Y%m%d');
               $value = "start=20000101&end=".$tt;
	       $hash->{PARMVALUE} = $value;
	   }
	   if ( $value =~ /start=\d{8}&end=\d{8}/ ) {  	
	      readingsSingleUpdate($hash,"ze_Step","getCharges",1);
	      RenaultZE_Main1($hash, @param);
	   } else  {
		return "Syntax error for $opt, correct pattern is 'start=20201212&end=20210120'";
           }
        }

        elsif ($opt eq "hvac-history")
        {
	   if ($value eq "") {
   	       my $tt      = localtime()->strftime('%Y%m%d');
               $value = "type=day&start=20000101&end=".$tt;
	       $hash->{PARMVALUE} = $value;
	   }
	   if ( $value =~ /type=month&start=\d{6}&end=\d{6}/ or $value =~ /type=day&start=\d{8}&end=\d{8}/) {  	
	      readingsSingleUpdate($hash,"ze_Step","getHvacHistory",1);
	      RenaultZE_Main1($hash, @param);
	   } else  {
		return "Syntax error for $opt, correct pattern is 'type=month&start=202012&end=202101' or 'type=day&start=20201212&end=20210120'";
           }
        }

        elsif ($opt eq "hvac-settings")
        {
	   readingsSingleUpdate($hash,"ze_Step","getHvacSettings",1);
	   RenaultZE_Main1($hash, @param);
        }

        elsif ($opt eq "charging-settings")
        {
	   readingsSingleUpdate($hash,"ze_Step","getChargingSettings",1);
	   RenaultZE_Main1($hash, @param);
        }

        elsif ($opt eq "notification-settings")
        {
	   readingsSingleUpdate($hash,"ze_Step","getNotificationSettings",1);
	   RenaultZE_Main1($hash, @param);
        }

        elsif ($opt eq "checkAPIkeys")
        {
	   readingsSingleUpdate($hash,"ze_Step","getcheckAPIkeys",1);
	   RenaultZE_checkAPIkeys1($hash);
        }

        elsif ($opt eq "zTest")
        {
	   readingsSingleUpdate($hash,"ze_Step","getzTest",1);
	   RenaultZE_Main1($hash, @param);
        }

	elsif($opt eq "?") {
		my @cList = keys %RenaultZE_gets;
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
	}
	
	return undef;
}

sub RenaultZE_Set($@) {
	my ($hash, @param) = @_;
	
	my $name = shift @param;
	my $opt = shift @param;
	my $value = join("", @param);
        Log3 $name, 5, "RenaultZE_Set - opt = $opt, value = $value";

	if ($opt ne "?")
	{
            $hash->{FUNCTION}  = 'SET';
            $hash->{PARMS}     = $opt;
            $hash->{PARMVALUE} = $value;
            $hash->{curCL} = $hash->{CL};
        }  
	

	if($opt eq "?") {
		my @cList = keys %RenaultZE_sets;
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
	}

	readingsSingleUpdate($hash,"ze_lastErr","",1)                       if ($opt ne "?");

	if ($opt eq "AC")
        {
           readingsSingleUpdate($hash,"ze_Step","setAC",1);
           RenaultZE_Main1($hash, @param);
        }

	elsif ($opt eq "charge")
        {
           readingsSingleUpdate($hash,"ze_Step","setCharge",1);
           RenaultZE_Main1($hash, @param);
        }

        elsif ($opt eq "password" && $value ne "")
        {
           return RenaultZE_storePassword($name,$value);
        }

        elsif ($opt eq "state")
        {
           $hash->{STATE} = $value;
        }

	return undef;
}

sub RenaultZE_AsyncOutput ($$)
{
	my ( $client_hash, $text ) = @_;

	return $text;
}

sub RenaultZE_UpdateTimer($) {
    my ( $hash ) = @_;
    my $name = $hash->{NAME};

    if(AttrVal($name, "disabled", 0 ) == 1){
        RemoveInternalTimer ($hash);
        Log3 $hash, 3, "RenaultZE ($name) is disabled";
	readingsSingleUpdate($hash,"ze_Step","RenaultZE ($name) is disabled",1);
        return undef;
    }

    if ( $hash->{INTERVAL}) {
        RemoveInternalTimer ($hash);
        delete($hash->{UPDATESCHEDULE});

	my $nextTrigger = gettimeofday() + $hash->{INTERVAL};
	$hash->{TRIGGERTIME}     = $nextTrigger;
        $hash->{TRIGGERTIME_FMT} = FmtDateTime($nextTrigger);
        InternalTimer($nextTrigger, "RenaultZE_UpdateTimer", $hash, 0);
        Log3 $hash, 4, "RenaultZE ($name) internal interval timer set to call StartUpdate again at " . $hash->{TRIGGERTIME_FMT};

        readingsSingleUpdate($hash,"ze_Step","getStatus",1);
	$hash->{PARMS} = "update";
	$hash->{FUNCTION} = 'GET';
        $hash->{PARMS}    = 'update';
	my @param = ('GET', 'update');
        RenaultZE_Main1($hash, @param);
    }

}

sub RenaultZE_Main1($@) {
        my ($hash, @param) = @_;

	#my $name = shift @param;
	#my $opt = shift @param;

        my $function = $hash->{FUNCTION};
        my $opt = $hash->{PARMS};
        my $value = $hash->{PARMVALUE};
	my $key = $function."_".$opt;
	my $name = $hash->{NAME};

        Log3 $name, 5, "RenaultZE_Main1 - In, key=".$key;

	#if ($key eq "GET_update" || $key eq "GET_vehicles" || $key eq "GET_ac-state" || $key eq "SET_AC" || $key eq "SET_charge")
	#{
           readingsSingleUpdate($hash,"ze_Step","Main1",1);
           my $lastErr = $hash->{READINGS}{ze_lastErr}{VAL};
           readingsSingleUpdate($hash,"ze_Gigya_JWT_Token","",1)                if ($lastErr ne "");
	   my $ze_Gigya_JWT_Token = $hash->{READINGS}{ze_Gigya_JWT_Token}{VAL};
	   my $ze_Gigya_JWT_lastCall = $hash->{READINGS}{ze_Gigya_JWT_lastCall}{TIME};
           my $res = 0;

           Log3 $name, 5, "RenaultZE_Main1 - ze_Gigya_JWT_lastCall=".$ze_Gigya_JWT_lastCall;
	   my $gigya_time = Time::Piece->strptime( $ze_Gigya_JWT_lastCall, '%Y-%m-%d %H:%M:%S')->epoch;
           Log3 $name, 5, "RenaultZE_Main1 - ze_Gigya_JWT_lastCall=".$gigya_time;
           Log3 $name, 5, "RenaultZE_Main1 - gettimeofday=".gettimeofday();

           if ( $ze_Gigya_JWT_Token eq ""  ||  $gigya_time < gettimeofday() - 70000 ) {
              my $res = RenaultZE_getCreds_Step1($hash);
              Log3 $name, 5, "RenaultZE_Main1 - RC=".$res		if defined($res);
           }
	   else
	   {
              Log3 $name, 5, "RenaultZE_Main1 - ze_Gigya_JWT_Token=>".$ze_Gigya_JWT_Token."<";
	   }
           RenaultZE_Main2($hash);
           return undef;
	   #}

        Log3 $name, 5, "RenaultZE_Main1 - Out";
        return undef;
}

sub RenaultZE_Main2($) {
        my ($hash) = @_;

        my $function = $hash->{FUNCTION};
        my $opt = $hash->{PARMS};
        my $value = $hash->{PARMVALUE};
	my $key = $function."_".$opt;
	my $name = $hash->{NAME};

        Log3 $name, 5, "RenaultZE_Main2 - In, key=".$key;

        my $lastErr = $hash->{READINGS}{ze_lastErr}{VAL};
        return undef                    if ($lastErr ne "");

	#if ($key eq "GET_update" || $key eq "GET_vehicles" || $key eq "GET_ac-state" || $key eq "SET_AC" || $key eq "SET_charge")
	#{
           readingsSingleUpdate($hash,"ze_Step","Main2",1);
           my $ze_Renault_AccId = $hash->{READINGS}{ze_Renault_AccId}{VAL};
           my $res = 0;

           Log3 $name, 5, "RenaultZE_Main2 - ze_Renault_AccId: ".$ze_Renault_AccId;
           if ( $ze_Renault_AccId eq "" || $ze_Renault_AccId eq "0" ){
              $res = RenaultZE_getAccId_Step1($hash);
              Log3 $name, 5, "RenaultZE_getAccId_Step1 - RC=".$res;
           }
           RenaultZE_Main3($hash);
           return undef;
	   #}

        Log3 $name, 5, "RenaultZE_Main2 - Out";
        return undef;
}

sub RenaultZE_Main3($) {
        my ($hash) = @_;

        my $function = $hash->{FUNCTION};
        my $opt = $hash->{PARMS};
        my $value = $hash->{PARMVALUE};
	my $key = $function."_".$opt;
	my $name = $hash->{NAME};

        readingsSingleUpdate($hash,"ze_Step","Main3",1);
        Log3 $name, 5, "RenaultZE_Main3 - In, key=".$key;

        my $lastErr = $hash->{READINGS}{ze_lastErr}{VAL};
        return undef                    if ($lastErr ne "");

	my $phase = AttrVal($name,"ze_phase","");

        if ($key eq "GET_update")
        {
	      #my $res = RenaultZE_getData_Step1($hash);
              my $res = RenaultZE_gData_Step1($hash,'battery-status');
	      my $model = $hash->{READINGS}{vehicleDetails_model_label}{VAL};
              Log3 $name, 5, "RenaultZE_gData_Step1 - battery-status - RC=".$res;
	      InternalTimer( gettimeofday() + 1, sub() { my $a = 1; 
                 $res = RenaultZE_gData_Step1($hash,'cockpit');
                 Log3 $name, 5, "RenaultZE_gData_Step1 - cockpit - RC=".$res;
	      }, undef);
	      InternalTimer( gettimeofday() + 2, sub() { my $a = 1; 
                 $res = RenaultZE_gData_Step1($hash,'location')				if ($phase eq "2");
                 Log3 $name, 5, "RenaultZE_gData_Step1 - location - RC=".$res		if ($phase eq "2");
	      }, undef);
	      InternalTimer( gettimeofday() + 3, sub() { my $a = 1; 
                 $res = RenaultZE_gData_Step1($hash,'hvac-status')				if ($phase eq "1");
                 Log3 $name, 5, "RenaultZE_gData_Step1 - hvac-status - RC=".$res		if ($phase eq "1");
	      }, undef);
	      InternalTimer( gettimeofday() + 4, sub() { my $a = 1; 
                 $res = RenaultZE_gData_Step1($hash,'charge-mode')			if ($model ne "SPRING");
                 Log3 $name, 5, "RenaultZE_gData_Step1 - charge-mode - RC=".$res	if ($model ne "SPRING");
	      }, undef);
	}

        if ($key eq "GET_vehicles")
        {
              my $res = RenaultZE_gData_Step1($hash,'vehicles');
              Log3 $name, 5, "RenaultZE_gData_Step1 - vehicles - RC=".$res;
	}

        if ($key eq "GET_charge-history")
        {
              my $res = RenaultZE_gData_Step1($hash,'charge-history');
              Log3 $name, 5, "RenaultZE_gData_Step1 - charge-history - RC=".$res;
	}

        if ($key eq "GET_charges")
        {
              my $res = RenaultZE_gData_Step1($hash,'charges');
              Log3 $name, 5, "RenaultZE_gData_Step1 - charges - RC=".$res;
	}

        if ($key eq "GET_charging-settings")
        {
              my $res = RenaultZE_gData_Step1($hash,'charging-settings');
              Log3 $name, 5, "RenaultZE_gData_Step1 - charging-settings - RC=".$res;
	}

        if ($key eq "GET_hvac-history")
        {
              my $res = RenaultZE_gData_Step1($hash,'hvac-history');
              Log3 $name, 5, "RenaultZE_gData_Step1 - hvac-history - RC=".$res;
	}

        if ($key eq "GET_hvac-settings")
        {
              my $res = RenaultZE_gData_Step1($hash,'hvac-settings');
              Log3 $name, 5, "RenaultZE_gData_Step1 - hvac-settings - RC=".$res;
	}

        if ($key eq "GET_notification-settings")
        {
              my $res = RenaultZE_gData_Step1($hash,'notification-settings');
              Log3 $name, 5, "RenaultZE_gData_Step1 - notification-settings - RC=".$res;
	}

        if ($key eq "GET_zTest")
        {
              my $res = RenaultZE_gData_Step1($hash,'zTest');
              Log3 $name, 5, "RenaultZE_gData_Step1 - zTest - RC=".$res;
	}

        if ($key eq "SET_AC")
        {
              my $res = RenaultZE_AC_Step1($hash);
              Log3 $name, 5, "RenaultZE_AC_Step1 - RC=".$res;
	}

        if ($key eq "SET_charge")
        {
              my $res = RenaultZE_Charge_Step1($hash);
              Log3 $name, 5, "RenaultZE_Charge_Step1 - RC=".$res;
	}

        Log3 $name, 5, "RenaultZE_Main3 - Out";
}

sub RenaultZE_Main4($) {
        my ($hash) = @_;
	my $name = $hash->{NAME};

        my $lastErr = $hash->{READINGS}{ze_lastErr}{VAL};
        return undef                    if ($lastErr ne "");

        readingsSingleUpdate($hash,"ze_Step","done",1);
	$hash->{STATE} = "updated";
	return undef;
}

sub RenaultZE_Attr(@) {
	my ($cmd,$name,$attrName,$attrVal) = @_;
	my $hash  = $defs{$name};
	if($cmd eq "set") {
	    if (substr($attrName ,0,3) eq "ze_")
	    {
	        $_[3] = $attrVal;
	        $hash->{".reset"} = 1 if defined($hash->{LPID});
	    }	
	    if (($attrName eq "disabled") && ($attrVal == 1))
            {
                readingsSingleUpdate($hash,"state","disabled",1);
	        readingsSingleUpdate($hash,"ze_Step","RenaultZE ($name) is disabled",1);
                $_[3] = $attrVal;
                $hash->{".reset"} = 1 if defined($hash->{LPID});
		RemoveInternalTimer ($hash);
            }
	    elsif (($attrName eq "disabled") && ($attrVal == 0))
            {
	       readingsSingleUpdate($hash,"ze_Step","RenaultZE ($name) is enabled",1);
               $_[3] = $attrVal;
               $hash->{".reset"} = 1 if defined($hash->{LPID});
    		my $firstTrigger = gettimeofday() + 2;
    		$hash->{TRIGGERTIME}     = $firstTrigger;
    		$hash->{TRIGGERTIME_FMT} = FmtDateTime($firstTrigger);
               InternalTimer($firstTrigger, "RenaultZE_UpdateTimer", $hash, 0);
            }
        }
  	elsif ($cmd eq "del")
        {
           if (substr($attrName,0,3) eq "ze_")
           {
               $_[3] = $attrVal;
               $hash->{".reset"} = 1 if defined($hash->{LPID});
           }
	   elsif (($attrName eq "disabled") )
           {
                readingsSingleUpdate($hash,"state","enabled",1);
	        readingsSingleUpdate($hash,"ze_Step","RenaultZE ($name) is enabled",1);
                $_[3] = $attrVal;
                $hash->{".reset"} = 1 if defined($hash->{LPID});
    		my $firstTrigger = gettimeofday() + 2;
    		$hash->{TRIGGERTIME}     = $firstTrigger;
    		$hash->{TRIGGERTIME_FMT} = FmtDateTime($firstTrigger);
                InternalTimer($firstTrigger, "RenaultZE_UpdateTimer", $hash, 0);
           }
        }
        if ($attrName eq "ze_homeRadius")
        {
                my $gpsLatitude  = ReadingsVal($name,"gpsLatitude","empty");
                my $gpsLongitude = ReadingsVal($name,"gpsLongitude","empty");
		my $homeRadius = 20;							# defule radius
		$homeRadius = $attrVal							if ( $cmd eq "set" );
		$homeRadius = 20							if ( $homeRadius eq "" );	# just in case
		#Log3 $name, 5, "pre RenaultZE_distanceFromHome - In ".$cmd."/".$gpsLatitude." ".$gpsLongitude."/".$homeRadius;
                RenaultZE_distanceFromHome($hash,$gpsLatitude,$gpsLongitude,$homeRadius);
        }

	return undef;
}

######################################################
# storePW & readPW Code geklaut aus 72_FRITZBOX.pm :)
######################################################
sub RenaultZE_storePassword($$)
{
    my ($name, $password) = @_;
    my $index = "ZE_".$name."_passwd";
    my $key   = getUniqueId().$index;
    my $e_pwd = "";

    if (eval "use Digest::MD5;1")
    {
        $key  = Digest::MD5::md5_hex(unpack "H*", $key);
        $key .= Digest::MD5::md5_hex($key);
    }

    for my $char (split //, $password)
    {
        my $encode=chop($key);
        $e_pwd.=sprintf("%.2x",ord($char)^ord($encode));
        $key=$encode.$key;
    }

    my $error = setKeyValue($index, $e_pwd);
    return "error while saving ZE user password : $error" if(defined($error));
    return "ZE user password successfully saved in FhemUtils/uniqueID Key $index";
}

sub RenaultZE_readPassword($)
{
   my ($name) = @_;
   my $index  = "ZE_".$name."_passwd";
   my $key    = getUniqueId().$index;

   my ($password, $error);

   #Log3 $name,5,"$name, read ZE user password from FhemUtils/uniqueID Key $key";
   ($error, $password) = getKeyValue($index);

   if ( defined($error) )
   {
      Log3 $name,5, "$name, cant't read ZE user password from FhemUtils/uniqueID: $error";
      return undef;
   }

   if ( defined($password) )
   {
      if (eval "use Digest::MD5;1")
      {
         $key  = Digest::MD5::md5_hex(unpack "H*", $key);
         $key .= Digest::MD5::md5_hex($key);
      }

      my $dec_pwd = '';

      for my $char (map { pack('C', hex($_)) } ($password =~ /(..)/g))
      {
         my $decode=chop($key);
         $dec_pwd.=chr(ord($char)^ord($decode));
         $key=$decode.$key;
      }
      return $dec_pwd;
   }
   else
   {
      Log3 $name,3,"$name, no ZE user password found in FhemUtils/uniqueID";
      return undef;
   }
}

####### getStatus Dialog #####
#
sub RenaultZE_getCreds_Step1($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};
   Log3 $name, 5, "RenaultZE_getCreds_Step1 - In ".$hash."/".$name;
   readingsSingleUpdate($hash,"ze_Step","RenaultZE_getCreds_Step1",1);
   my $gigya_api = $hash->{GIGYA_API};
   my $username = AttrVal($name,"ze_user","");
   my $password = RenaultZE_readPassword($name);
   Log3 $name, 5, "RenaultZE_getCreds_Step1 - Parms: ".$gigya_api."/".$username."/".$password;

    my $step1= {
        ApiKey     =>  $gigya_api,
        loginId    =>  $username,
        password   =>  $password,
	include => 'data',
        sessionExpiration => 60
    };

    Log3 $name, 5, "RenaultZE_getCreds_Step1 - Data".$step1;
    my $param = {
                    url        => "https://accounts.eu1.gigya.com/accounts.login",
                    header     => "Content-type: application/x-www-form-urlencoded",                            
		    hash       => $hash,
                    timeout    => 15,
                    method     => "POST",                                                                                 
                    data       => $step1,
                    callback   => \&RenaultZE_getCreds_Step2          
                };

    HttpUtils_NonblockingGet($param);                                                                                    # Starten der HTTP Abfrage. Es gibt keinen Return-Code.
    Log3 $name, 5, "RenaultZE_getCreds_Step1 - Out";
    return undef;
}

sub RenaultZE_getCreds_Step2($)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    Log3 $name, 5, "RenaultZE_getCreds_Step2 - In ".$hash."/".$name;
    readingsSingleUpdate($hash,"ze_Step","RenaultZE_getCreds_Step2",1);

    RenaultZE_Error_err($hash,"RenaultZE_getCreds_Step2",$param->{url},$err,$data)                     if($err ne "");
    RenaultZE_Log_Data($hash,"RenaultZE_getCreds_Step2",$param->{url},$err,$data)                      if($data ne "");
    return undef										       if (RenaultZE_CheckJson($hash,$data));
    my $decode_json = from_json($data);
    my $errorCode    = $decode_json->{errorCode};
    RenaultZE_Error_errorCode1($hash,"RenaultZE_getCreds_Step2",$param->{url},$err,$data)              if($errorCode ne 0);

    my $lastErr = $hash->{READINGS}{ze_lastErr}{VAL};
    return undef        								               if ($lastErr ne "");

    $decode_json = from_json($data);
    my $ze_personId = $decode_json->{data}->{personId};
    my $oauth_token = $decode_json->{sessionInfo}->{cookieValue};
    Log3 $name, 5, "RenaultZE_getCreds_Step2 - ze_personId:".$ze_personId.", ze_cookieValue:".$oauth_token;
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"ze_personId",$ze_personId);
    readingsBulkUpdate($hash,"ze_cookieValue",$oauth_token);
    readingsEndUpdate($hash, 1 );

    my $gigya_api = $hash->{GIGYA_API};
    my $step2= {
        login_token =>  $oauth_token,
        ApiKey     =>  $gigya_api,
        fields    =>  'data.personId,data.gigyaDataCenter',
        expiration => 87000
    };
    Log3 $name, 5, "RenaultZE_getCreds_Step2 - Data".$step2;
    my $param2 = {
                    url        => "https://accounts.eu1.gigya.com/accounts.getJWT",
                    header     => "Content-type: application/x-www-form-urlencoded",                            
		    hash       => $hash,
                    timeout    => 15,
                    method     => "POST",                                                                                 
                    data       => $step2,
                    callback   => \&RenaultZE_getCreds_Step3
                };

    HttpUtils_NonblockingGet($param2);                                                                                    # Starten der HTTP Abfrage. Es gibt keinen Return-Code.
    #my $res = RenaultZE_getStatusPerformHttpRequest2($i, $e, $o, $a);
    Log3 $name, 5, "RenaultZE_getCreds_Step2 - Out";
    return undef;
}

sub RenaultZE_getCreds_Step3($)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    Log3 $name, 5, "RenaultZE_getCreds_Step3 - In ".$hash."/".$name;
    readingsSingleUpdate($hash,"ze_Step","RenaultZE_getCreds_Step3",1);

    RenaultZE_Error_err($hash,"RenaultZE_getCreds_Step3",$param->{url},$err,$data)                     if($err ne "");
    RenaultZE_Log_Data($hash,"RenaultZE_getCreds_Step3",$param->{url},$err,$data)                      if($data ne "");
    return undef                                                                                       if (RenaultZE_CheckJson($hash,$data));
    my $decode_json = from_json($data);
    my $errorCode    = $decode_json->{errorCode};
    RenaultZE_Error_errorCode1($hash,"RenaultZE_getCreds_Step3",$param->{url},$err,$data)              if($errorCode ne 0);

    my $lastErr = $hash->{READINGS}{ze_lastErr}{VAL};
    return undef                    if ($lastErr ne "");

    $decode_json = from_json($data);
    my $id_token = $decode_json->{id_token};
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"ze_Gigya_JWT_Token",$id_token);
    readingsBulkUpdate($hash,"ze_Gigya_JWT_lastCall",localtime(time));
    readingsEndUpdate($hash, 1 );

    RenaultZE_Main2($hash);

    #my $res = RenaultZE_getStatusPerformHttpRequest2($i, $e, $o, $a);
   Log3 $name, 5, "RenaultZE_getCreds_Step3 - Out";
}

sub RenaultZE_getAccId_Step1($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 5, "RenaultZE_getAccId_Step1 - In ".$hash."/".$name;
    readingsSingleUpdate($hash,"ze_Step","RenaultZE_getAccId_Step1",1);
    my $kamereon_api = $hash->{KAMEREON_API};
    my $id_token = $hash->{READINGS}{ze_Gigya_JWT_Token}{VAL};
    my $ze_personId = $hash->{READINGS}{ze_personId}{VAL};
    my $country = AttrVal($name,"ze_country","DE");
    Log3 $name, 5, "RenaultZE_getCreds_Step1 - Parms: ".$kamereon_api."/".$id_token;

    return undef                                  if ( $id_token eq "" || $ze_personId eq "" );

    my $step1= {
        'ApiKey'   =>  $kamereon_api,
        'x-gigya-id_token'  =>  $id_token
    };

    Log3 $name, 5, "RenaultZE_getCreds_Step1 - Data".$step1;
    my $url = "https://api-wired-prod-1-euw1.wrd-aws.com/commerce/v1/persons/".$ze_personId."?country=".$country;
    Log3 $name, 5, "RenaultZE_getCreds_Step1 - URL ".$url;
    my $param = {
                    url        => $url,
                    header     => $step1,
		    hash       => $hash,
                    timeout    => 15,
                    method     => "GET",                                                                                 
                    callback   => \&RenaultZE_getAccId_Step2          
                };

    HttpUtils_NonblockingGet($param);
    Log3 $name, 5, "RenaultZE_getAccId_Step1 - Out";
    return undef;
}

sub RenaultZE_getAccId_Step2($)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    Log3 $name, 5, "RenaultZE_getAccId_Step2 - In ".$hash."/".$name;
    readingsSingleUpdate($hash,"ze_Step","RenaultZE_getAccId_Step2",1);

    RenaultZE_Error_err($hash,"RenaultZE_getAccId_Step2",$param->{url},$err,$data)                     if($err ne "");
    RenaultZE_Log_Data($hash,"RenaultZE_getAccId_Step2",$param->{url},$err,$data)                      if($data ne "");
    RenaultZE_Error_errorCode2($hash,"RenaultZE_getAccId_Step2",$param->{url},$err,$data)              if($data =~ /error/);

    my $lastErr = $hash->{READINGS}{ze_lastErr}{VAL};
    return undef                  								       if ($lastErr ne "");

    return undef                                                                                       if (RenaultZE_CheckJson($hash,$data));    
    my $decode_json = from_json($data);
    my $accountId = $decode_json->{accounts}[0]->{accountId};
    Log3 $name, 5, "RenaultZE_getCreds_Step2 - accountId:".$accountId;
    readingsSingleUpdate($hash,"ze_Renault_AccId",$accountId,1);

    RenaultZE_Main3($hash);

    Log3 $name, 5, "RenaultZE_getCAccId_Step2 - Out";
}

sub RenaultZE_gData_Step1($$)
{
    my ($hash,$tree) = @_;
    my $name = $hash->{NAME};

    my $v1v2 = "v1";
    $v1v2 = "v2"				if ( $tree eq "battery-status");
    my $shortlong = "long";
    $shortlong = "short"			if ( $tree eq "vehicles");
    my $popup = "no";
    $popup = "yes"				if ( $tree eq "vehicles");
    $popup = "yes"				if ( $tree eq "charge-mode");
    my $testparms = $hash->{PARMVALUE};
    my $timespecs = "";
    if ( $tree eq "charge-history" or $tree eq "hvac-history" or $tree eq "charges") {
	    $timespecs = "&".$testparms;
    }

    Log3 $name, 5, "RenaultZE_gData_Step1 - In ".$hash."/".$tree."/".$name;
    readingsSingleUpdate($hash,"ze_Step","RenaultZE_gData_Step1",1);
    my $kamereon_api = $hash->{KAMEREON_API};
    my $id_token = $hash->{READINGS}{ze_Gigya_JWT_Token}{VAL};
    my $accId = $hash->{READINGS}{ze_Renault_AccId}{VAL};
    my $vin = $hash->{VIN};
    my $country = AttrVal($name,"ze_country","DE");
    Log3 $name, 5, "RenaultZE_gData_Step1 - Parms: ".$kamereon_api."/".$id_token;

    return 4                                       if ( $id_token eq "" || $accId eq "" );
    my $header= {
        'apikey'   =>  $kamereon_api,
        'x-gigya-id_token'  =>  $id_token
    };

    Log3 $name, 5, "RenaultZE_getData_Step1 - Data".$header;
    my $url = "";
    if ( $shortlong eq "long") {
       $url = "https://api-wired-prod-1-euw1.wrd-aws.com/commerce/v1/accounts/".$accId."/kamereon/kca/car-adapter/".$v1v2."/cars/".$vin."/".$tree."?country=".$country.$timespecs;
    }else {
       $url = "https://api-wired-prod-1-euw1.wrd-aws.com/commerce/v1/accounts/".$accId."/".$tree."?country=".$country;
    }

    # for development of new options and users of a phase 1 Zoe
    if ( $tree eq "zTest") {
       my $testparms = $hash->{PARMVALUE};
       $url = "https://api-wired-prod-1-euw1.wrd-aws.com/commerce/v1/accounts/".$accId."/kamereon/kca/car-adapter/".$v1v2."/cars/".$vin."/".$testparms;
    }
    # In Vorbereit8ung, aber derzeit noch nicht seitens Renault unterstützt:
    #$url = "https://api-wired-prod-1-euw1.wrd-aws.com/commerce/v1/accounts/".$accId."/kamereon/kca/car-adapter/".$v1v2."/cars/".$vin."/hvac-history?type=day&start=20201101&end=20210108&country=".$country;
    #$url = "https://api-wired-prod-1-euw1.wrd-aws.com/commerce/v1/accounts/".$accId."/kamereon/kca/car-adapter/".$v1v2."/cars/".$vin."/hvac-sessions?start=20201101&end=20210108&country=".$country;
    #$url = "https://api-wired-prod-1-euw1.wrd-aws.com/commerce/v1/accounts/".$accId."/kamereon/kca/car-adapter/".$v1v2."/cars/".$vin."/charges?start=20201101&end=20210108&country=".$country;
    #$url = "https://api-wired-prod-1-euw1.wrd-aws.com/commerce/v1/accounts/".$accId."/kamereon/kca/car-adapter/".$v1v2."/cars/".$vin."/charge-history?type=day&start=20201101&end=20210108&country=".$country;
    #$url = "https://api-wired-prod-1-euw1.wrd-aws.com/commerce/v1/accounts/".$accId."/kamereon/kca/car-adapter/".$v1v2."/cars/".$vin."/charge-history?type=month&start=202011&end=202101&country=".$country;
    #$url = "https://api-wired-prod-1-euw1.wrd-aws.com/commerce/v1/accounts/".$accId."/kamereon/kca/car-adapter/".$v1v2."/cars/".$vin."/lock-status?country=".$country;
    Log3 $name, 5, "RenaultZE_gData_Step1 - URL ".$url;
    my $param = {
                    url        => $url,
                    header     => $header,
                    hash       => $hash,
                    timeout    => 15,
                    method     => "GET",
                    callback   => \&RenaultZE_gData_Step2
                };

    HttpUtils_NonblockingGet($param);                                                                                    # Starten der HTTP Abfrage. Es gibt keinen Return-Code.
    Log3 $name, 5, "RenaultZE_gData_Step1 - Out";
    return 0;
}

sub RenaultZE_gData_Step2($)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    Log3 $name, 5, "RenaultZE_gData_Step2 - In ".$hash."/".$name;
    readingsSingleUpdate($hash,"ze_Step","RenaultZE_gData_Step2",1);

    RenaultZE_Error_err($hash,"RenaultZE_gData_Step2",$param->{url},$err,$data)                     if($err ne "");
    RenaultZE_Log_Data($hash,"RenaultZE_gData_Step2",$param->{url},$err,$data)                      if($data ne "");
    RenaultZE_Error_errorCode2($hash,"RenaultZE_gData_Step2",$param->{url},$err,$data)              if($data =~ /errorMessage/);

    my $lastErr = $hash->{READINGS}{ze_lastErr}{VAL};
    return undef                    								    if ($lastErr ne "");

    my $lastUrl = $hash->{READINGS}{ze_lastUrl}{VAL};

    Log3 $name, 3, "RenaultZE_gData_Step2 - DataError ".$data					    if ($data =~ /\<html\>/);
    return undef           								            if ($data =~ /\<html\>/);

    my $phase = AttrVal($name,"ze_phase","");

    return undef                                                                                    if (RenaultZE_CheckJson($hash,$data));
    my $decode_json = from_json($data);

    if($data =~ /batteryLevel/) {
        my $timestamp = $decode_json->{data}->{attributes}->{timestamp};
	#$timestamp =~ s/\+01:00/Z/sg;		# fix for time format "2021-01-27T16:41:42+01:00"
	#my $t = Time::Piece->strptime($timestamp, "%Y-%m-%dT%H:%M:%SZ")->epoch;
	my $t = RenaultZE_EpochFromDateTime($timestamp);
	my $tt = localtime($t)->strftime('%Y-%m-%d %H:%M:%S');
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"timestamp",$tt);
        readingsBulkUpdate($hash,"batteryLevel",$decode_json->{data}->{attributes}->{batteryLevel});
        readingsBulkUpdate($hash,"batteryTemperature",$decode_json->{data}->{attributes}->{batteryTemperature})			if ($phase eq "1");
        readingsBulkUpdate($hash,"batteryAutonomy",$decode_json->{data}->{attributes}->{batteryAutonomy});
        readingsBulkUpdate($hash,"batteryCapacity",$decode_json->{data}->{attributes}->{batteryCapacity})			if ($decode_json->{data}->{attributes}->{batteryCapacity} gt 0);
        readingsBulkUpdate($hash,"batteryAvailableEnergy",$decode_json->{data}->{attributes}->{batteryAvailableEnergy})		if ($decode_json->{data}->{attributes}->{batteryAvailableEnergy} gt 0);
        readingsBulkUpdate($hash,"plugStatus",$decode_json->{data}->{attributes}->{plugStatus});
        readingsBulkUpdate($hash,"chargingStatus",$decode_json->{data}->{attributes}->{chargingStatus});
        readingsBulkUpdate($hash,"chargingRemainingTime",$decode_json->{data}->{attributes}->{chargingRemainingTime});
        readingsBulkUpdate($hash,"chargingInstantaneousPower",$decode_json->{data}->{attributes}->{chargingInstantaneousPower});
        readingsEndUpdate($hash, 1 );
        return 0;
    }

    ### cockpit ###
    if($data =~ /totalMileage/) {
       readingsBeginUpdate($hash);
       readingsBulkUpdate($hash,"totalMileageKm",$decode_json->{data}->{attributes}->{totalMileage});
       readingsBulkUpdate($hash,"fuelAutonomy",$decode_json->{data}->{attributes}->{fuelAutonomy})			if ($decode_json->{data}->{attributes}->{fuelAutonomy} gt 0);
       readingsBulkUpdate($hash,"fuelQuantity",$decode_json->{data}->{attributes}->{fuelQuantity})			if ($decode_json->{data}->{attributes}->{fuelQuantity} gt 0);
       readingsEndUpdate($hash, 1 );
       return 0;
    }

    ### hvac-status ###
    if($data =~ /hvacStatus/) {
       readingsBeginUpdate($hash);
       readingsBulkUpdate($hash,"hvacStatus",$decode_json->{data}->{attributes}->{hvacStatus});
       readingsBulkUpdate($hash,"socThreshold",$decode_json->{data}->{attributes}->{socThreshold})			if ($decode_json->{data}->{attributes}->{socThreshold} gt 0);
       readingsBulkUpdate($hash,"xternalTemperature",$decode_json->{data}->{attributes}->{xternalTemperature})		if ($decode_json->{data}->{attributes}->{xternalTemperature} gt 0);
       readingsEndUpdate($hash, 1 );
       return 0;
    }

    my $gpsLatitude = "";
    my $gpsLongitude = "";
    my $lastUpdateTime = "";
    if($data =~ /gpsLatitude/) {
        if ($data =~ /locationStatus/) {
            $gpsLatitude = $decode_json->{locationStatus}->{attributes}->{gpsLatitude};
            $gpsLongitude = $decode_json->{locationStatus}->{attributes}->{gpsLongitude};
            $lastUpdateTime = $decode_json->{locationStatus}->{attributes}->{lastUpdateTime};
        } else {
            $gpsLatitude = $decode_json->{data}->{attributes}->{gpsLatitude};
            $gpsLongitude = $decode_json->{data}->{attributes}->{gpsLongitude};
            $lastUpdateTime = $decode_json->{data}->{attributes}->{lastUpdateTime};
        }
        my $gpsLatitude = $decode_json->{data}->{attributes}->{gpsLatitude};
        my $gpsLongitude = $decode_json->{data}->{attributes}->{gpsLongitude};
        my $lastUpdateTime = $decode_json->{data}->{attributes}->{lastUpdateTime};
	#$lastUpdateTime =~ s/\+01:00/Z/sg;		# fix for time format "2021-01-27T16:41:42+01:00"
	#my $t       = Time::Piece->strptime($lastUpdateTime, "%Y-%m-%dT%H:%M:%SZ")->epoch;
	my $t        = RenaultZE_EpochFromDateTime($lastUpdateTime);
	my $tt      = localtime($t)->strftime('%Y-%m-%d %H:%M:%S');
	my $oldlat  = ReadingsVal($name,"gpsLatitude","empty");
	my $oldlong = ReadingsVal($name,"gpsLongitude","empty");
        my $link = "<html><a href=\"https://www.google.com/maps/place/".$gpsLatitude.",".$gpsLongitude."\" target=\”_blank\”>Google Maps</a></html>";
	if ( $oldlat != $gpsLatitude or $oldlong != $gpsLongitude ) {
            Log3 $name, 5, "RenaultZE_gData_Step2 - GPS ".$oldlat."/".$gpsLatitude." ".$oldlong."/".$gpsLongitude;
  	    RenaultZE_distanceFromHome($hash,$gpsLatitude,$gpsLongitude,"auto");
    	}
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"gpsLatitude",$gpsLatitude);
        readingsBulkUpdate($hash,"gpsLongitude",$gpsLongitude);
        readingsBulkUpdate($hash,"gpsLastUpdateTime",$tt);
	readingsBulkUpdate($hash,"gpsGoogleMaps",$link);
	readingsEndUpdate($hash, 1 );
        return 0;
    } 

    if($data =~ /vehicleLink/) {
        my $decode_json = from_json($data);
        my $output = JSON->new->ascii->pretty->encode(decode_json join '', $data);

	# extract image urls
        my $mtab = $decode_json->{vehicleLinks};
        foreach my $item( @$mtab ) {
		next   if ($item->{vin} ne $hash->{VIN});
                my $assets = $item->{vehicleDetails}->{assets};
                foreach my $ass( @$assets ) {
                        my $cars = $ass->{renditions};
                        foreach my $car( @$cars ) {
                                my $url =  $car->{url};
                                my $size =  $car->{resolutionType};
				 my $link = "<html><img src=\"".$url."\"></html>";
    				readingsSingleUpdate($hash,"img_".$size."_url",$url,1);
    				readingsSingleUpdate($hash,"img_".$size."_img",$link,1)   if (AttrVal($name,"ze_showimage","1") gt 0 and $size =~ /SMALL/ );
    				readingsSingleUpdate($hash,"img_".$size."_img",$link,1)   if (AttrVal($name,"ze_showimage","1") eq 2 and $size =~ /LARGE/ );
                        }
                }
                my $detail = $item->{vehicleDetails}->{family}->{code};
		readingsSingleUpdate($hash,"vehicleDetails_family_code",$detail,1);
                $detail = $item->{vehicleDetails}->{family}->{label};
		readingsSingleUpdate($hash,"vehicleDetails_family_label",$detail,1);
                $detail = $item->{vehicleDetails}->{family}->{group};
		readingsSingleUpdate($hash,"vehicleDetails_family_group",$detail,1);
		#
                $detail = $item->{vehicleDetails}->{engineEnergyType};
		readingsSingleUpdate($hash,"vehicleDetails_engineEnergyType",$detail,1);
		#
                $detail = $item->{vehicleDetails}->{navigationAssistanceLevel}->{code};
		readingsSingleUpdate($hash,"vehicleDetails_navigationAssistanceLevel_code",$detail,1);
                $detail = $item->{vehicleDetails}->{navigationAssistanceLevel}->{label};
		readingsSingleUpdate($hash,"vehicleDetails_navigationAssistanceLevel_label",$detail,1);
                $detail = $item->{vehicleDetails}->{navigationAssistanceLevel}->{group};
		readingsSingleUpdate($hash,"vehicleDetails_navigationAssistanceLevel_group",$detail,1);
		#
                $detail = $item->{vehicleDetails}->{version}->{code};
		readingsSingleUpdate($hash,"vehicleDetails_version_code",$detail,1);
		#
                $detail = $item->{vehicleDetails}->{gearbox}->{code};
                readingsSingleUpdate($hash,"vehicleDetails_gearbox_code",$detail,1);
                $detail = $item->{vehicleDetails}->{gearbox}->{label};
                readingsSingleUpdate($hash,"vehicleDetails_gearbox_label",$detail,1);
                $detail = $item->{vehicleDetails}->{gearbox}->{group};
                readingsSingleUpdate($hash,"vehicleDetails_gearbox_group",$detail,1);
		#
                $detail = $item->{vehicleDetails}->{radioType}->{code};
                readingsSingleUpdate($hash,"vehicleDetails_radioType_code",$detail,1);
                $detail = $item->{vehicleDetails}->{radioType}->{label};
                readingsSingleUpdate($hash,"vehicleDetails_radioType_label",$detail,1);
                $detail = $item->{vehicleDetails}->{radioType}->{group};
                readingsSingleUpdate($hash,"vehicleDetails_radioType_group",$detail,1);
		#
                $detail = $item->{vehicleDetails}->{tcu}->{code};
                readingsSingleUpdate($hash,"vehicleDetails_tcu_code",$detail,1);
                $detail = $item->{vehicleDetails}->{tcu}->{label};
                readingsSingleUpdate($hash,"vehicleDetails_tcu_label",$detail,1);
                $detail = $item->{vehicleDetails}->{tcu}->{group};
                readingsSingleUpdate($hash,"vehicleDetails_tcu_group",$detail,1);
		#
                $detail = $item->{vehicleDetails}->{model}->{code};
                readingsSingleUpdate($hash,"vehicleDetails_model_code",$detail,1);
                $detail = $item->{vehicleDetails}->{model}->{label};
                readingsSingleUpdate($hash,"vehicleDetails_model_label",$detail,1);
                $detail = $item->{vehicleDetails}->{model}->{group};
                readingsSingleUpdate($hash,"vehicleDetails_model_group",$detail,1);
		#
                $detail = $item->{vehicleDetails}->{engineType};
                readingsSingleUpdate($hash,"vehicleDetails_engineType",$detail,1);
		#
                $detail = $item->{vehicleDetails}->{modelSCR};
                readingsSingleUpdate($hash,"vehicleDetails_modelSCR",$detail,1);
		#
                $detail = $item->{vehicleDetails}->{battery}->{code};
                readingsSingleUpdate($hash,"vehicleDetails_battery_code",$detail,1);
                $detail = $item->{vehicleDetails}->{battery}->{label};
                readingsSingleUpdate($hash,"vehicleDetails_battery_label",$detail,1);
                $detail = $item->{vehicleDetails}->{battery}->{group};
                readingsSingleUpdate($hash,"vehicleDetails_battery_group",$detail,1);
		#
                $detail = $item->{vehicleDetails}->{brand}->{label};
                readingsSingleUpdate($hash,"vehicleDetails_brand_label",$detail,1);

        }

        asyncOutput( $hash->{curCL}, $output );
        return 0;
    }

    if($data =~ /externalTemperature/) {
        my $decode_json = from_json($data);
        readingsSingleUpdate($hash,"externalTemperature",$decode_json->{data}->{attributes}->{externalTemperature},1);
        return 0;
    }

    if($data =~ /chargeMode/) {
        my $decode_json = from_json($data);
        readingsSingleUpdate($hash,"chargeMode",$decode_json->{data}->{attributes}->{chargeMode},1);
        return 0;
    }

    ### charge-history?country=DE&type=day&start=20201212&end=20210120
    ### charge-history?country=DE&type=month&start=202012&end=202101
    if($data =~ /chargeSummaries.*totalChargesNumber/) {
        my $mtab = $decode_json->{data}->{attributes}->{chargeSummaries};
        my $tperiod = "day";
        $tperiod = "month"                      if ($data =~ /month/);
        print ">>>".$tperiod."\n";
        my $output = "<html><body><b>Charge Summaries (".$tperiod.")</b><table border=1 center>";
        $output = $output."<tr>";
        $output = $output."<td align=center>".$tperiod."</td>";
        $output = $output."<td align=center>totalChargesNumber</td>";
        $output = $output."<td align=center>totalChargesDuration</td>";
        $output = $output."<td align=center>totalChargesErrors</td>";
        $output = $output."</tr>";
        foreach my $item( @$mtab ) {
             $output = $output."<tr>";
             $output = $output."<td align=center>".$item->{$tperiod}."</td>";
             $output = $output."<td align=center>".$item->{totalChargesNumber}."</td>";
             $output = $output."<td align=center>".$item->{totalChargesDuration}."</td>";
             $output = $output."<td align=center>".$item->{totalChargesErrors}."</td>";
             $output = $output."</tr>";
        }
        $output = $output."</table></body></html>";
        readingsSingleUpdate($hash,"chargeHistory",$output,1);
        return 0;
    }

    ### hvac-history?country=DE&type=month&start=202012&end=202101
    ### hvac-history?country=DE&type=day&start=20201212&end=20210120
    if($data =~ /hvacSessionsSummaries.*totalHvacSessionsNumber/) {
        my $mtab = $decode_json->{data}->{attributes}->{hvacSessionsSummaries};
        my $tperiod = "day";
        $tperiod = "month"                      if ($data =~ /month/);
        print ">>>".$tperiod."\n";
        my $output = "<html><body><b>HVAC Session Summaries (".$tperiod.")</b><table border=1 center>";
        $output = $output."<tr>";
        $output = $output."<td align=center>".$tperiod."</td>";
        $output = $output."<td align=center>totalHvacSessionsNumber</td>";
        $output = $output."<td align=center>totalHvacSessionsErrors</td>";
        $output = $output."</tr>";
        foreach my $item( @$mtab ) {
             $output = $output."<tr>";
             $output = $output."<td align=center>".$item->{$tperiod}."</td>";
             $output = $output."<td align=center>".$item->{totalHvacSessionsNumber}."</td>";
             $output = $output."<td align=center>".$item->{totalHvacSessionsErrors}."</td>";
             $output = $output."</tr>";
        }
        $output = $output."</table></body></html>";
        readingsSingleUpdate($hash,"hvacHistory",$output,1);
        return 0;
    }

    ### hvac-sessions?country=DE&start=20201210&end=20210110
    if($data =~ /hvacSessions.*hvacSessionRequestDate/) {
        my $mtab = $decode_json->{data}->{attributes}->{hvacSessions};
        #print scalar @$mtab."\n";
        my $output = "<html><body><b>HVAC Sessions</b><table border=1 center>";
        $output = $output."<tr>";
        $output = $output."<td align=center>hvacSessionRequestDate</td>";
        $output = $output."<td align=center>hvacSessionStartDate</td>";
        $output = $output."<td align=center>hvacSessionEndStatus</td>";
        $output = $output."</tr>";
        foreach my $item( @$mtab ) {
             $output = $output."<tr>";
             $output = $output."<td align=center>".$item->{hvacSessionRequestDate}."</td>";
             $output = $output."<td align=center>".$item->{hvacSessionStartDate}."</td>";
             $output = $output."<td align=center>".$item->{hvacSessionEndStatus}."</td>";
             $output = $output."</tr>";
        }
        $output = $output."</table></body></html>";
        readingsSingleUpdate($hash,"hvacSessions",$output,1);
        return 0;
    }

    ### charging-settings?country=DE
    if(($data =~ /mode.*schedules/) && ($lastUrl =~ /charg/)){
        my $mtab = $decode_json->{data}->{attributes}->{schedules};
        my $sss = @$mtab;
        #print scalar @$mtab."\n";
        my $output = "<html><body><b>Charging Settings</b><p>Mode=".$decode_json->{data}->{attributes}->{mode}."<p>&nbsp;<p>Schedules:<p>&nbsp;<p>";
        my @wdays = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "saturday" );
	if  ( $sss > 0 ) {
           foreach my $item( @$mtab ) {
             $output = $output."activated =".$item->{activated}."<table border=1 center>";
             $output = $output."<tr>";
             $output = $output."<td align=center>Day of Week</td>";
             $output = $output."<td align=center>startTime</td>";
             $output = $output."<td align=center>duration</td>";
             $output = $output."</tr>";
             foreach my $wd( @wdays ) {
                 $output = $output."<tr>";
                 $output = $output."<td align=center>".$wd."</td>";
                 $output = $output."<td align=center>".$item->{$wd}->{startTime}."</td>";
                 $output = $output."<td align=center>".$item->{$wd}->{duration}."</td>";
             $output = $output."</tr>";
             }
   	     last;
           }
           $output = $output."</table>";
        }
        $output = $output."</body></html>";
        readingsSingleUpdate($hash,"chargingSettings",$output,1);
        return 0;
    }

    ### hvac-settings?country=DE
    if(($data =~ /mode.*schedules/) && ($lastUrl =~ /hvac/)){
        my $mtab = $decode_json->{data}->{attributes}->{schedules};
        my $sss = @$mtab;
        #print scalar @$mtab."\n";
        my $output = "<html><body><b>HVAC Settings</b><p>Mode=".$decode_json->{data}->{attributes}->{mode}."<br>";
        my @wdays = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "saturday" );
        if  ( $sss > 0 ) {
           $output = $output."<p>Schedules";
           foreach my $item( @$mtab ) {
            if ($item->{activated} == 1 ) {
             $output = $output."<p>activated =".$item->{activated}."<table border=1 center>";
             $output = $output.", Target Temperature =".$item->{targetTemperature}."<table border=1 center>";
             $output = $output."<tr>";
             $output = $output."<td align=center>Day of Week</td>";
             $output = $output."<td align=center>readyAtTime</td>";
             $output = $output."</tr>";
             foreach my $wd( @wdays ) {
                 $output = $output."<tr>";
                 $output = $output."<td align=center>".$wd."</td>";
                 $output = $output."<td align=center>".$item->{$wd}->{readyAtTime}."</td>";
             $output = $output."</tr>";
             }
           $output = $output."</table>";
           }
          }
        }
        $output = $output."</body></html>";
        readingsSingleUpdate($hash,"hvacSettings",$output,1);
        return 0;
    }


    ### notification-settings?country=DE
    if($data =~ /settings.*messageKey/) {
        my $mtab = $decode_json->{data}->{attributes}->{settings};
        my $output = "<html><body><b>Notification Settings</b><table border=1 center>";
        $output = $output."<tr>";
        $output = $output."<td align=center>messageKey</td>";
        $output = $output."<td align=center>email</td>";
        $output = $output."<td align=center>sms</td>";
        $output = $output."<td align=center>pushApp</td>";
        $output = $output."</tr>";
        foreach my $item( @$mtab ) {
             $output = $output."<tr>";
             $output = $output."<td align=center>".$item->{messageKey}."</td>";
             $output = $output."<td align=center>".$item->{email}."</td>";
             $output = $output."<td align=center>".$item->{sms}."</td>";
             $output = $output."<td align=center>".$item->{pushApp}."</td>";
             $output = $output."</tr>";
        }
        $output = $output."</table></body></html>";
        readingsSingleUpdate($hash,"notificationSettings",$output,1);
        return 0;
    }

    ### charges start=20200202&end=20210202
    if($data =~ /charges/) {
        my $mtab = $decode_json->{data}->{attributes}->{charges};
        my $output = "<html><body><b>Charges</b><table border=1 align=middle>";
        $output = $output."<tr>";
        $output = $output."<td align=center>charge Start Date</td>";
        $output = $output."<td align=center>charge End Date</td>";
        $output = $output."<td align=center>charge Duration</td>";
        $output = $output."<td align=center>charge Start Battery Level</td>";
        $output = $output."<td align=center>charge End Battery Level</td>";
        $output = $output."<td align=center>charge Energy Recovered</td>";
        $output = $output."<td align=center>charge End Status</td>";
        $output = $output."</tr>";
        foreach my $item( @$mtab ) {
             $output = $output."<tr>";
             $output = $output."<td align=center>".$item->{chargeStartDate}."</td>";
             $output = $output."<td align=center>".$item->{chargeEndDate}."</td>";
             $output = $output."<td align=center>".$item->{chargeDuration}."</td>";
             $output = $output."<td align=center>".$item->{chargeStartBatteryLevel}."</td>";
             $output = $output."<td align=center>".$item->{chargeEndBatteryLevel}."</td>";
             $output = $output."<td align=center>".$item->{chargeEnergyRecovered}."</td>";
             $output = $output."<td align=center>".$item->{chargeEndStatus}."</td>";
             $output = $output."</tr>";
        }
        $output = $output."</table></body></html>";
	$output =~ s/charge//g;
        readingsSingleUpdate($hash,"chargesDetails",$output,1);
        return 0;
    }

    Log3 $name, 5, "RenaultZE_gData_Step2 - opt=".$hash->{PARMS};
    if($hash->{PARMS} eq "zTest") {
        asyncOutput( $hash->{curCL}, $data );
        return 0;
    }

    Log3 $name, 5, "RenaultZE_gData_Step2 - Out";
    return 0;
}

sub RenaultZE_AC_Step1($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $value = $hash->{PARMVALUE};
    Log3 $name, 5, "RenaultZE_AC_Step1 - In ".$hash."/".$name;
    Log3 $name, 5, "RenaultZE_Set - value = >$value<";
    readingsSingleUpdate($hash,"ze_Step","RenaultZE_AC_Step1",1);
    my $kamereon_api = $hash->{KAMEREON_API};
    my $id_token = $hash->{READINGS}{ze_Gigya_JWT_Token}{VAL};
    my $accId = $hash->{READINGS}{ze_Renault_AccId}{VAL};
    my $vin = $hash->{VIN};
    my $country = AttrVal($name,"ze_country","DE");
    Log3 $name, 5, "RenaultZE_AC_Step1 - Parms: ".$kamereon_api."/".$id_token;

    return undef                                       if ( $id_token eq "" || $accId eq "" );

    my $step1= {
	'Content-type'      => 'application/vnd.api+json',
        'apikey'            =>  $kamereon_api,
        'x-gigya-id_token'  =>  $id_token
    };

    Log3 $name, 5, "RenaultZE_AC_Step1 - Data".$step1;
    my $url= "empty";
    my $jsonData = "empty";
    if ( $value eq "on" )
    {
       $jsonData = '{"data":{"type":"HvacStart","attributes":{"action":"start","targetTemperature":"21"}}}';
       $url = "https://api-wired-prod-1-euw1.wrd-aws.com/commerce/v1/accounts/".$accId."/kamereon/kca/car-adapter/v1/cars/".$vin."/actions/hvac-start?country=".$country;
    } else {
       $jsonData = '{"data":{"type":"HvacStart","attributes":{"action":"cancel"}}}';
       $url = "https://api-wired-prod-1-euw1.wrd-aws.com/commerce/v1/accounts/".$accId."/kamereon/kca/car-adapter/v1/cars/".$vin."/actions/hvac-start?country=".$country;
    }
    Log3 $name, 5, "RenaultZE_AC_Step1 - URL ".$url;
    Log3 $name, 5, "RenaultZE_AC_Step1 - jsonData ".$jsonData;
    my $param = {
                    url        => $url,
                    header     => $step1,
                    hash       => $hash,
                    timeout    => 15,
                    method     => "POST",
		    data       => $jsonData,
                    callback   => \&RenaultZE_AC_Step2
                };

    HttpUtils_NonblockingGet($param);                                                                                    # Starten der HTTP Abfrage. Es gibt keinen Return-Code.
    Log3 $name, 5, "RenaultZE_AC_Step1 - Out";
    return undef;
}

sub RenaultZE_AC_Step2($)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    Log3 $name, 5, "RenaultZE_AC_Step2 - In ".$hash."/".$name;
    readingsSingleUpdate($hash,"ze_Step","RenaultZE_AC_Step2",1);

    RenaultZE_Error_err($hash,"RenaultZE_AC_Step2",$param->{url},$err,$data)                     if($err ne "");
    RenaultZE_Log_Data($hash,"RenaultZE_AC_Step2",$param->{url},$err,$data)                      if($data ne "");
    RenaultZE_Error_errorCode2($hash,"RenaultZE_AC_Step2",$param->{url},$err,$data)              if($data =~ /error/);

    my $lastErr = $hash->{READINGS}{ze_lastErr}{VAL};
    return undef                    if ($lastErr ne "");

    return undef                                                                                 if (RenaultZE_CheckJson($hash,$data));
    my $decode_json = from_json($data);
    Log3 $name, 5, "RenaultZE_AC_Step2 - returned".$decode_json;
    my $acstatus = $decode_json->{data}->{attributes}->{action};
    my $msg = "AC:".$acstatus;
    Log3 $name, 5, "RenaultZE_AC_Step2 - acstatus=".$msg;
    $hash->{STATE} = $msg;
    #asyncOutput( $hash->{curCL}, $output );
    return undef;
}

sub RenaultZE_Charge_Step1($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $value = $hash->{PARMVALUE};
    Log3 $name, 5, "RenaultZE_Charge_Step1 - In ".$hash."/".$name;
    Log3 $name, 5, "RenaultZE_Charge_Step1 - value = >$value<";
    readingsSingleUpdate($hash,"ze_Step","RenaultZE_Charge_Step1",1);
    my $kamereon_api = $hash->{KAMEREON_API};
    my $id_token = $hash->{READINGS}{ze_Gigya_JWT_Token}{VAL};
    my $accId = $hash->{READINGS}{ze_Renault_AccId}{VAL};
    my $vin = $hash->{VIN};
    my $country = AttrVal($name,"ze_country","DE");
    Log3 $name, 5, "RenaultZE_Charge_Step1 - Parms: ".$kamereon_api."/".$id_token;

    return undef                                       if ( $id_token eq "" || $accId eq "" );

    my $step1= {
	'Content-type'      => 'application/vnd.api+json',
        'apikey'            =>  $kamereon_api,
        'x-gigya-id_token'  =>  $id_token
    };

    Log3 $name, 5, "RenaultZE_Charge_Step1 - Data".$step1;
    my $jsonData = "empty";
    my $url= "empty";
    my $brand = AttrVal($name,"ze_brand","Renault");
    if ( $value eq "start" )
    {
       if ( $brand eq "Renault" )
       {
          $jsonData = '{"data":{"type":"ChargingStart","attributes":{"action":"start"}}}';
          $url = "https://api-wired-prod-1-euw1.wrd-aws.com/commerce/v1/accounts/".$accId."/kamereon/kca/car-adapter/v1/cars/".$vin."/actions/charging-start?country=".$country;
       }
       if ( $brand eq "Dacia" )
       {
          $jsonData = '{"data":{"type":"ChargePauseResume","attributes":{"action":"resume"}}}';
          $url = "https://api-wired-prod-1-euw1.wrd-aws.com/commerce/v1/accounts/".$accId."/kamereon/kcm/v1/vehicles/".$vin."/charge/pause-resume?country=".$country;
       }
    } else {
       if ( $brand eq "Renault" )
       {
          $jsonData = '{"data":{"type":"ChargingStart","attributes":{"action":"stop"}}}';
          $url = "https://api-wired-prod-1-euw1.wrd-aws.com/commerce/v1/accounts/".$accId."/kamereon/kca/car-adapter/v1/cars/".$vin."/actions/charging-start?country=".$country;
       }
       if ( $brand eq "Dacia" )
       {
          $jsonData = '{"data":{"type":"ChargePauseResume","attributes":{"action":"pause"}}}';
          $url = "https://api-wired-prod-1-euw1.wrd-aws.com/commerce/v1/accounts/".$accId."/kamereon/kcm/v1/vehicles/".$vin."/charge/pause-resume?country=".$country;
       }
    }
    Log3 $name, 5, "RenaultZE_Charge_Step1 - URL ".$url;
    Log3 $name, 5, "RenaultZE_Charge_Step1 - jsonData ".$jsonData;
    my $param = {
                    url        => $url,
                    header     => $step1,
                    hash       => $hash,
                    timeout    => 15,
                    method     => "POST",
		    data       => $jsonData,
                    callback   => \&RenaultZE_Charge_Step2
                };

    HttpUtils_NonblockingGet($param);                                                                                    # Starten der HTTP Abfrage. Es gibt keinen Return-Code.
    Log3 $name, 5, "RenaultZE_Charge_Step1 - Out";
    return undef;
}

sub RenaultZE_Charge_Step2($)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    Log3 $name, 5, "RenaultZE_Charge_Step2 - In ".$hash."/".$name;
    readingsSingleUpdate($hash,"ze_Step","RenaultZE_Charge_Step2",1);

    RenaultZE_Error_err($hash,"RenaultZE_Charge_Step2",$param->{url},$err,$data)                     if($err ne "");
    RenaultZE_Log_Data($hash,"RenaultZE_Charge_Step2",$param->{url},$err,$data)                      if($data ne "");
    RenaultZE_Error_errorCode2($hash,"RenaultZE_Charge_Step2",$param->{url},$err,$data)              if($data =~ /error/);

    my $lastErr = $hash->{READINGS}{ze_lastErr}{VAL};
    return undef                    if ($lastErr ne "");

    return undef                                                                                     if (RenaultZE_CheckJson($hash,$data));
    my $decode_json = from_json($data);
    Log3 $name, 5, "RenaultZE_Charge_Step2 - returned".$decode_json;
    my $chargestatus = $decode_json->{data}->{attributes}->{action};
    my $msg = "Charge:".$chargestatus;
    Log3 $name, 5, "RenaultZE_Charge_Step2 - chargestatus=".$msg;
    $hash->{STATE} = $msg;
    #asyncOutput( $hash->{curCL}, $output );
    return undef;
}

sub RenaultZE_Log_Data($$$$$)
{
    my ($hash, $step, $url, $err, $data) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 5, "INFO: ".$step.", url: ".$url.", data: ".$data.", error: ".$err;

    $err = RenaultZE_pp_err($hash,$err)                                             if($err ne "");;

    readingsSingleUpdate($hash,"ze_lastUrl",$url,1);
    readingsSingleUpdate($hash,"ze_lastErr",$err,1);
    readingsSingleUpdate($hash,"ze_lastData",$data,1);
    return undef;
}

sub RenaultZE_Error_err($$$$$)
{
    my ($hash, $step, $url, $err, $data) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 3, "ERROR: ".$step.", error while calling ".$url." - $err";

    $err = RenaultZE_pp_err($hash,$err)                                             if($err ne "");;

    readingsSingleUpdate($hash,"ze_lastUrl",$url,1);
    readingsSingleUpdate($hash,"ze_lastErr",$err,1);
    readingsSingleUpdate($hash,"ze_lastData",$data,1);
}

sub RenaultZE_Error_errorCode1($$$$$)
{
    my ($hash, $step, $url, $err, $data) = @_;
    my $name = $hash->{NAME};
    return undef                                                                                 if (RenaultZE_CheckJson($hash,$data));
    my $decode_json = from_json($data);
    my $errorCode    = $decode_json->{errorCode};
    my $errorDetails = $decode_json->{errorDetails};
    my $errorMessage = $decode_json->{errorMessage};
    my $statusReason = $decode_json->{statusReason};
    my $msg = "errorCode=".$errorCode.", errorDetails=".$errorDetails.", errorMessage=".$errorMessage.", statusReason=".$statusReason;
    Log3 $name, 3, "ERROR: (1) ".$step.", errorCode while calling ".$url." - $msg";

    $msg = RenaultZE_pp_err($hash,$errorMessage)                                           if($errorMessage ne "");;

    readingsSingleUpdate($hash,"ze_lastUrl",$url,1);
    readingsSingleUpdate($hash,"ze_lastErr",$msg,1);
    readingsSingleUpdate($hash,"ze_lastData",$data,1);
}


sub RenaultZE_Error_errorCode2($$$$$)
{
    my ($hash, $step, $url, $err, $data) = @_;
    my $name = $hash->{NAME};
    return undef                                                                                 if (RenaultZE_CheckJson($hash,$data));
    my $decode_json = from_json($data);
    my $errorCode    = $decode_json->{errors}[0]->{errorCode};
    my $errorMessage = $decode_json->{errors}[0]->{errorMessage};
    my $msg = "errorCode=".$errorCode.", errorMessage=".$errorMessage;
    Log3 $name, 3, "ERROR: (2) ".$step.", error (data) while calling ".$url." - $msg"		if($errorMessage !~ /Failed to forward request to remote service/);;
    Log3 $name, 5, "ERROR: (2) ".$step.", error (data) while calling ".$url." - $msg"		if($errorMessage =~ /Failed to forward request to remote service/);;

    $msg = RenaultZE_pp_err($hash,$msg)                                             if($msg ne "");;

    readingsSingleUpdate($hash,"ze_lastUrl",$url,1);
    readingsSingleUpdate($hash,"ze_lastErr",$msg,1);
    readingsSingleUpdate($hash,"ze_lastData",$data,1);
}

sub RenaultZE_pp_err($$)
{
    my ($hash,$err) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 3, "INFO: pretty printing error ".$err;
    my $errj = $err;
    $errj =~ s/.*errorMessage=//g;
    my $json_out = eval { decode_json($errj) };
    my $output = "";
    if ($@)
    {
        $output = $err;
    } else {
        my $decode_json = from_json($errj);
        my $mtab = $decode_json->{errors};
        $output = "<html><body><b>Error</b><table border=1 center><colgroup><col width=\"10%\"><col width=\"*\"></colgroup>";
        $output = $output."<tr>";
        $output = $output."<td><b>raw</b></td><td>".$err."</td></tr>";
        foreach my $item( @$mtab ) {
            $output = $output."<td><b>status</b></td><td>".$item->{status}."</td></tr>";
            $output = $output."<td><b>code</b></td><td>".$item->{code}."</td></tr>";
            $output = $output."<td><b>title</b></td><td>".$item->{title}."</td></tr>";
            $output = $output."<td><b>detail</b></td><td>".$item->{detail}."</td></tr>";
        }
        $output = $output."</table></body></html>";
    }
    return $output;
}
sub RenaultZE_distanceFromHome($$$$)
{
    my ($hash, $lat, $long, $homeRadius) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 5, "RenaultZE_distanceFromHome - In ".$hash."/".$lat." ".$long."/".$homeRadius;
    my $hlong = AttrVal( $name, "ze_longitude", AttrVal( "global", "longitude", 0.0 ) );
    my $hlat  = AttrVal( $name, "ze_latitude",  AttrVal( "global", "latitude",  0.0 ) );

    #Kreiszahl Pi
    my $pi = 3.14159;

    #Umrechnung von Grad in Radius
    my $long1 = $long / 180 * $pi;
    my $lat1  = $lat / 180 * $pi;
    my $long2 = $hlong / 180 * $pi;
    my $lat2  = $hlat / 180 * $pi;

    #Entfernungsberechnung
    my $distance = acos(sin($long1)*sin($long2) + cos($long1)*cos($long2)*cos($lat2-$lat1));

    #Erdrundung einbeziehen
    $distance = $distance * 6378.137;

    my $dim = "km";
    my $homeinfo = "";
    my $homestate = "away";
    $homeRadius  = AttrVal( $name, "ze_homeRadius", 20 )	if ( $homeRadius eq "auto");
    Log3 $name, 5, "RenaultZE_distanceFromHome - Check ".$hash."/".$lat." ".$long."/".$homeRadius;

    if ($distance < $homeRadius) {
            $distance = $distance * 1000;
            $dim = "m";
            if ($distance < $homeRadius) {
		    $homeinfo = "home";
		    $homestate = "home";
	    } 
    }
    $distance = sprintf("%.3f", $distance);
    $homeinfo = $distance." ".$dim." away"          if ( $homeinfo eq "");
    if ( $hlong != 0.0 and $hlat != 0.0) {
       readingsSingleUpdate($hash,"distanceFromHome",$distance,1);
       readingsSingleUpdate($hash,"distanceUnit",$dim,1);
       readingsSingleUpdate($hash,"homeInfo",$homeinfo,1);
       readingsSingleUpdate($hash,"homeState",$homestate,1);
       RenaultZE_gAddress1($hash,$lat,$long)        if (AttrVal($name,"ze_showaddress","1") eq 1);
    }


    return undef;
}

sub RenaultZE_gAddress1($$$)
{
    my ($hash,$lat,$long) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 5, "RenaultZE_gAddress1 - In ".$hash."/".$name." ".$lat."/".$long;
    readingsSingleUpdate($hash,"ze_Step","RenaultZE_gAddress1",1);

    my $url = "https://www.google.com/maps/place/$lat+$long";
    Log3 $name, 5, "RenaultZE_gData_Step1 - URL ".$url;
    my $param = {
                    url        => $url,
                    hash       => $hash,
                    timeout    => 15,
                    method     => "GET",
                    callback   => \&RenaultZE_gAddress2
                };

    HttpUtils_NonblockingGet($param);                                                                                    # Starten der HTTP Abfrage. Es gibt keinen Return-Code.
    Log3 $name, 5, "RenaultZE_gAddress1 - Out";
    return 0;
}

sub RenaultZE_gAddress2($)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    Log3 $name, 5, "RenaultZE_gAddress2 - In ".$hash."/".$name;
    Log3 $name, 5, "RenaultZE_gAddress2 - In err".$hash."/".$err;
    Log3 $name, 5, "RenaultZE_gAddress2 - In data".$hash."/".$data;
    readingsSingleUpdate($hash,"ze_Step","RenaultZE_gAddress2",1);

    #    RenaultZE_Error_err($hash,"RenaultZE_gAddress2",$param->{url},$err,$data)                     if($err ne "");
    #    RenaultZE_Log_Data($hash,"RenaultZE_gAddress2",$param->{url},$err,$data)                      if($data ne "");
    #    RenaultZE_Error_errorCode2($hash,"RenaultZE_gAddress2",$param->{url},$err,$data)              if($data =~ /error/);

    #    my $lastErr = $hash->{READINGS}{ze_lastErr}{VAL};
    #    return undef                                                                                  if ($lastErr ne "");

    $data =~ s/.*meta content=\"(.*)\" itemprop=\"description\".*/$1/sg;
    Log3 $name, 5, "RenaultZE_gAddress2 - Address ".$data;
    my $oldinfo = ReadingsVal($name,"homeInfo","");
    my $newinfo = $oldinfo." (".$data.")";
    readingsSingleUpdate($hash,"homeInfo",$newinfo,1);

    Log3 $name, 5, "RenaultZE_gAddress2 - Out";
}

sub RenaultZE_checkAPIkeys1($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $value = $hash->{PARMVALUE};
    Log3 $name, 5, "RenaultZE_checkAPIkeys_Step1 - In ".$hash."/".$name;
    readingsSingleUpdate($hash,"ze_Step","RenaultZE_checkAPIkeys1",1);
    my $kamereon_api = $hash->{KAMEREON_API};
    my $id_token = $hash->{READINGS}{ze_Gigya_JWT_Token}{VAL};
    my $country = AttrVal($name,"ze_country","DE");

    my $step1= {
        'Content-type'      => 'application/vnd.api+json'
    };

    my $url= "https://renault-wrd-prod-1-euw1-myrapp-one.s3-eu-west-1.amazonaws.com/configuration/android/config_de_DE.json";
    my $jsonData = "empty";
    Log3 $name, 5, "RenaultZE_checkAPIkeys1 ".$url;
    my $param = {
                    url        => $url,
                    header     => $step1,
                    hash       => $hash,
                    timeout    => 15,
                    method     => "GET",
                    data       => $jsonData,
                    callback   => \&RenaultZE_checkAPIkeys2
                };

    HttpUtils_NonblockingGet($param);                                                                                    # Starten der HTTP Abfrage. Es gibt keinen Return-Code.
    Log3 $name, 5, "RenaultZE_checkAPIkeys1 - Out";
    return undef;
}

sub RenaultZE_checkAPIkeys2($)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $kamereon_api = $hash->{KAMEREON_API};
    my $gigya_api = $hash->{GIGYA_API};

    Log3 $name, 5, "RenaultZE_checkAPIkeys2 - In ".$hash."/".$name;
    readingsSingleUpdate($hash,"ze_Step","RenaultZE_checkAPIkeys2",1);

    RenaultZE_Error_err($hash,"RenaultZE_checkAPIkeys2",$param->{url},$err,$data)                     if($err ne "");
    RenaultZE_Log_Data($hash,"RenaultZE_checkAPIkeys2",$param->{url},$err,$data)                      if($data ne "");
    RenaultZE_Error_errorCode2($hash,"RenaultZE_checkAPIkeys2",$param->{url},$err,$data)              if($data =~ /error/);

    my $lastErr = $hash->{READINGS}{ze_lastErr}{VAL};
    return undef                    if ($lastErr ne "");

    return undef                                                                                 if (RenaultZE_CheckJson($hash,$data));
    my $decode_json = from_json($data);
    Log3 $name, 5, "RenaultZE_checkAPIkeys2 - returned".$decode_json;
    #my $kameronkey = $decode_jmson->{data}->{servers}->{wiredProd}->{apikey};
    #my $gigyakey = $decode_json->{data}->{servers}->{gigyaProd}->{apikey};
    my $kameronkey = $decode_json->{servers}->{wiredProd}->{apikey};
    my $gigyakey = $decode_json->{servers}->{gigyaProd}->{apikey};
    Log3 $name, 5, "RenaultZE_checkAPIkeys2 KAMERON: ".$kameronkey;
    Log3 $name, 5, "RenaultZE_checkAPIkeys2 GIGYA".$gigyakey;
    Log3 $name, 5, "RenaultZE_checkAPIkeys2 Out";
    my $message = "";
    if ($kameronkey ne $kamereon_api) {
	    $message = "Neuer KAMERON API Key: \nIst: ".$kamereon_api."\nNeu: ".$kameronkey."\n\n";
    } else {
	    $message = "KAMERON API Key ist OK: \nIst: ".$kamereon_api."\nNeu: ".$kameronkey."\n\n";
    }
    if ($gigyakey ne $gigya_api) {
	    $message = $message."Neuer GIGYA API Key: \nIst: ".$gigya_api."\nNeu: ".$gigyakey."\n";
    } else {
	    $message = $message."GIGYA API Key ist OK: \nIst: ".$gigya_api."\nNeu: ".$gigyakey."\n";
    }
    asyncOutput( $hash->{curCL}, $message );
    return undef;
}

sub RenaultZE_CheckJson($$)
{
    my ($hash,$json) = @_;
    my $name = $hash->{NAME};
    my $json_out = eval { decode_json($json) };
    if ($@)
    {
    	readingsSingleUpdate($hash,"ze_lastErr","unexpected json error",1);
    	readingsSingleUpdate($hash,"ze_lastData",$json,1);
        return 1;
    }
    return 0;
}

sub RenaultZE_EpochFromDateTime($) {
    my ($timestamp) = @_;
    my $t;

    if ( substr($timestamp,-1,1) eq "Z" )
    {
       $t = eval { Time::Piece->strptime($timestamp, "%Y-%m-%dT%H:%M:%SZ")->epoch };
    }
    elsif ( substr($timestamp,-3,1) eq ":" )
    {
       $timestamp =~ s/\+(\d{2}):(\d{2})$/+$1$2/;
       $timestamp =~ s/\.\d{3}+/+/;
       $t = eval { Time::Piece->strptime($timestamp, "%Y-%m-%dT%H:%M:%S%z")->epoch };
    }
    elsif ( substr($timestamp,-5,5) =~ /\+(\d{4})/ )
    {
       $t = eval { Time::Piece->strptime($timestamp, "%Y-%m-%dT%H:%M:%S%z")->epoch };
    }

    $t = 0      if ($t eq "");

    return $t;
}

##############################
1;

=pod
=begin html

<a name="RenaultZE"></a>
<h3>RenaultZE</h3>
<ul>
    <i>RenaultZE</i> implements an interface to the Renualt ZE API<br>
    <br><br>
    <a name="RenaultZEdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; RenaultZE &lt;VIN&gt; &lt;Interval&gt;</code>
        <br><br>
        Example: <code>define myZoe RenaultZE VF1....... 300</code>
        <br><br>
        VIN is the Vehicle Identification Number (you'll find it in your registration)<br>
        Interval is the interval in seconds between status updates
    </ul>
    <br>
    
    <a name="RenaultZEset"></a>
    <b>Set</b><br>
    <ul>
        <code>set &lt;name&gt; &lt;option&gt; &lt;value&gt;</code>
        <br><br>
        You can <i>set</i><br> 
        <ul>
              <li><i>password</i><br>
                  enter your Renault ZE accounts password</li>
              <li><i>AC</i><br>
                  either on or cancel (which probably only cancles a timer)</li>
              <li><i>Charge</i><br>
                  either on or off (off doesn't work if you have set 'charge mode walways')</li>
              <li><i>state</i><br>
        </ul>
    </ul>
    <br>

    <a name="RenaultZEget"></a>
    <b>Get</b><br>
    <ul>
        <code>get &lt;name&gt; &lt;option&gt;</code>
        <br><br>
        You can <i>get</i><br>
        <ul>
              <li><a name="charge-history"></a><i>charge-history</i><br>
                  summary of charges, parameter options: <br>
		  type=day&start=YYYYMMDD&end=YYYYMMDD   (default: 1.1.2000 till today)<br>
		  type=month&start=YYYYMM&end=YYYYMM
              </li>
              <li><a name="charges"></a><i>charges</i><br>
	          <b>only for Phase1 models</b><br>
                  list of charges, parameter options: <br>
		  start=YYYYMMDD&end=YYYYMMD             (default: 1.1.2000 till today)
              </li>
              <li><a name="charging-settings"></a><i>charging-settings</i><br>
                  lists the settings for charging
              </li>
              <li><a name="hvac-history"></a><i>hvac-history</i><br>
	          <b>only for Phase1 models</b><br>
                  shows the air condition history, parameter options: <br>
		  type=day&start=YYYYMMDD&end=YYYYMMDD   (default: 1.1.2000 till today)<br>
		  type=month&start=YYYYMM&end=YYYYMM
              </li>
              <li><a name="hvac-settings"></a><i>hvac-settings</i><br>
                  shows the ac settingS <br>
              </li>
              <li><a name="notification-settings"></a><i>notification-settings</i><br>
	          <b>only for Phase1 models</b><br>
                  lists the settings for cnotifications
              </li>
              <li><a name="update"></a><i>update</i><br>
                  force update of the current readings (battery-status, cockpit, location, hvac-status, charge-mode)</li>
              <li><a name="checkAPIkeys"></a><i>checkAPIkeys</i><br>
	          check if the API are uptodate<br>
              <li><a name="vehicles"></a><i>vehicles</i><br>
	          get a list of your vehicles with details, set the readings for the images and some technical details<br>
		  if the attribute ze_showimage is set you get readings with the cars images</li>
              <li><a name="zTest"></a><i>zTest</i><br>
                  Option to test new API functions which might be implemented one day ...<br>
		  sub parameters are<br>
                  hvac-sessions?start=20201101&end=20210108&country=DE<br>
                  charge-history?type=day&start=20201101&end=20210108&country=DE<br>
                  charge-history?type=month&start=202011&end=202101&country=DE<br>
                  lock-status?country=DE<br>
                  res-state?country=DE<br>
		  As result you will either get a msgbox when the function is implemented by Renault, otherwise the ze-Readings will tell you more
              </li>
        </ul>
    </ul>
    <br>
    
    <a name="RenaultZEattr"></a>
    <b>Attributes</b>
    <ul>
        <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
        <br><br>
        See <a href="http://fhem.de/commandref.html#attr">commandref#attr</a> for more info about 
        the attr command.
        <br><br>
        Attributes:
        <ul>
            <li><i>ze_brand</i> Renault|Dacia<br>
                Car brand, default is Renault
            </li>
            <li><i>ze_phase</i> 1|2<br>
                The phase of ZE technology, either 1 or 2, right now only phase 2 is supported
            </li>
            <li><i>ze_country</i><br>
                2 letter country code, e.g. DE ot GB
            </li>
            <li><i>ze_homeRadius</i><br>
                allowed distance of car from home in m that is still considered 'home'
            </li>
            <li><i>ze_user</i><br>
                The user-id that you used to register at Renault 
            </li>
            <li><i>ze_latitude</i><br>
                Latitude of your home location. Is being used to calculate homeInfo. Function also checks for global attribte latitude als default.
            </li>
            <li><i>ze_longitude</i><br>
                Longitude of your home location. Is being used to calculate homeInfo. Function also checks for global attribte longitude als default.
            </li>
            <li><i>ze_showaddress</i><br>
                Retrieve address via reverse geocoding fromn Google Maps and add it to homeInfo.
            </li>
            <li><i>ze_showimage</i><br>
                Show the image of the car that you get from vehicles as reading<br>
		0 = off
		1 = only the small image (default)<br>
		2 = both, small and large image
            </li>
        </ul>
    </ul>
</ul>

=end html

=cut
