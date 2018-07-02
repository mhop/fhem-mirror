#################################################################################################################
# $Id$
#################################################################################################################
# 
#
#  Copyright notice
#
#  Published according Creative Commons : Attribution-NonCommercial-ShareAlike 3.0 Unported (CC BY-NC-SA 3.0)
#  Details: https://creativecommons.org/licenses/by-nc-sa/3.0/
#
#  Credits:
#  - based on 77_SMASTP.pm by Volker Kettenbach with following credits:
#  - based on an Idea by SpenZerX and HDO
#  - Waldmensch for various improvements
#  - sbfspot (https://sbfspot.codeplex.com/)
#  - rewritten by Thomas Schoedl (sct14675) with inputs from Volker, waldmensch and DS_Starter
# 
#  Description:
#  This is an FHEM-Module for SMA Inverters.
#  Tested on Sunny Tripower 6000TL-20 and Sunny Island 4.4
#
#  Requirements:
#  This module requires:
#  - Perl Module: IO::Socket::INET
#  - Perl Module: DateTime
#
#
#################################################################################################################
# Versions History by DS_Starter
#
# 2.10.0   29.06.2018      Internal MODEL added
# 2.9.2    08.10.2017      adapted to use extended abortArg (Forum:77472)
# 2.9.1    24.04.2017      fix for issue #24 (Wrong INV_TYPE for STP10000TL-20) and fix for issue #25 (unpack out of range for SB1.5-1VL-40)
# 2.9.0    23.04.2017      fixed issue #22: wrong logon command for SunnyBoy systems
# 2.8.3    19.04.2017      enhanced inverter Type-Hash
# 2.8.2    23.03.2017      changed SMA_logon sub
# 2.8.1    06.12.2016      SMAInverter version as internal 
# 2.8      05.12.2016      changed commandsections to make sure getting only data from inverters with preset
#                          $inv_susyid and $inv_serial
# 2.7.4    04.12.2016      change loading of IO::Socket::INET, DateTime
# 2.7.3    04.12.2016      commandref adapted
# 2.7.2    03.12.2016      use Time::HiRes qw(gettimeofday tv_interval)
# 2.7.1    02.12.2016      showproctime improved
# 2.7      02.12.2016      showproctime added
# 2.6.1    29.11.2016      getstatus_DoParse changed due to inititialized issues
# 2.6      28.11.2016      bugfix warnings ParseDone redefine at startup, uninitialized value $avg if FHEM was 
#                          restarted in sleeptime, switched avg_energy to avg_power, commandref updated
# 2.5.2    27.11.2016      bugfix average calc, bugfix warnings at startup
# 2.5.1    26.11.2016      calc of averagebuf changed to 5, 10, 15 minutes
# 2.5      26.11.2016      averagebuf changed, Attr timeout added
# 2.4      26.11.2016      create ringbuffer for calculating average energy last 5, 10, 15 cycles
# 2.3      25.11.2016      bugfixing
# 2.2      24.11.2016      further optimize of non-blocking operation
# 2.1      24.11.2016      avg_energy_lastcycles added 
# 2.0      24.11.2016      switched module to non-blocking operation
# 1.8.4    23.11.2016      prepare non-blocking operation 
# 1.8.3    23.11.2016      readings opertime_start, opertime_stop
# 1.8.2    22.11.2016      eliminate global vars, prepare non-blocking operation 
# 1.8.1    22.11.2016      eliminate global vars, create command array
# 1.8      21.11.2016      eliminate $r_OK, $r_FAIL, create command-array
# 1.7      21.11.2016      devtypes completed, minor bugfixes, commandref completed
# 1.6.1    19.11.2016      bugfix perl warning during fhem start
# 1.6      09.11.2016      added operation control by sunrise,sunset, Attr offset, suppressSleep added
# 1.5      08.11.2016      added device classes hash
# 1.4      07.11.2016      compatibility to SBFSpot improved, bilingual dependend on attr "language" of global-device,
#                          added hash of SMA device types
# 1.3      07.11.2016      Attr SBFSpotComp added to get compatibility mode with SBFSpot
# 1.2      06.11.2016      function get data added, log output level changed to 4 in sub SMAInverter_Attr,
#                          some code changes
# 1.1      06.11.2016      Attr mode manual, automatic added
# 1.0      06.11.2016      Attr disable added, 
#                          $globalName replaced by $name in all expressions (due to module redesign to non-blocking later)


package main;

use strict;
use warnings;
eval "use IO::Socket::INET;1" or my $MissModulSocket = "IO::Socket::INET";
eval "use DateTime;1" or my $MissModulDateTime = "DateTime";
use Time::HiRes qw(gettimeofday tv_interval);
use Blocking;
use Time::Local;

my $SMAInverterVersion = "2.10.0";

# Inverter Data fields and supported commands flags.
# $inv_SPOT_ETODAY                # Today yield
# $inv_SPOT_ETOTAL                # Total yield
# $inv_SPOT_PDC1                  # DC power input 1
# $inv_SPOT_PDC2	              # DC power input 2
# $inv_SPOT_PAC1                  # Power L1 
# $inv_SPOT_PAC2                  # Power L2 
# $inv_SPOT_PAC3                  # Power L3 
# $inv_PACMAX1                    # Nominal power in Ok Mode
# $inv_PACMAX2                    # Nominal power in Warning Mode
# $inv_PACMAX3                    # Nominal power in Fault Mode
# $inv_PACMAX1_2                  # Maximum active power device (Some inverters like SB3300/SB1200)
# $inv_SPOT_PACTOT		          # Total Power
# $inv_ChargeStatus               # Battery Charge status
# $inv_SPOT_UDC1                  # DC voltage input
# $inv_SPOT_UDC2                  # DC voltage input
# $inv_SPOT_IDC1                  # DC current input
# $inv_SPOT_IDC2                  # DC current input
# $inv_SPOT_UAC1                  # Grid voltage phase L1
# $inv_SPOT_UAC2                  # Grid voltage phase L2
# $inv_SPOT_UAC3                  # Grid voltage phase L3
# $inv_SPOT_IAC1                  # Grid current phase L1
# $inv_SPOT_IAC2                  # Grid current phase L2
# $inv_SPOT_IAC3                  # Grid current phase L3
# $inv_BAT_UDC                    # Battery Voltage
# $inv_BAT_IDC                    # Battery Current
# $inv_BAT_CYCLES                 # Battery recharge cycles
# $inv_BAT_TEMP                   # Battery temperature
# $inv_SPOT_FREQ                  # Grid Frequency
# $inv_CLASS                      # Inverter Class
# $inv_TYPE                       # Inverter Type
# $inv_SPOT_OPERTM                # Operation Time
# $inv_SPOT_FEEDTM                # Feed-in time
# $inv_TEMP                       # Inverter temperature
# $inv_GRIDRELAY                  # Grid Relay/Contactor Status
# $inv_STATUS                     # Inverter Status

# Aufbau Wechselrichter Type-Hash
my %SMAInverter_devtypes = (
0000 => "Unknown Inverter Type",
9015 => "SB 700",
9016 => "SB 700U",
9017 => "SB 1100",
9018 => "SB 1100U",
9019 => "SB 1100LV",
9020 => "SB 1700",
9021 => "SB 1900TLJ",
9022 => "SB 2100TL",
9023 => "SB 2500",
9024 => "SB 2800",
9025 => "SB 2800i",
9026 => "SB 3000",
9027 => "SB 3000US",
9028 => "SB 3300",
9029 => "SB 3300U",
9030 => "SB 3300TL",
9031 => "SB 3300TL HC",
9032 => "SB 3800",
9033 => "SB 3800U",
9034 => "SB 4000US",
9035 => "SB 4200TL",
9036 => "SB 4200TL HC",
9037 => "SB 5000TL",
9038 => "SB 5000TLW",
9039 => "SB 5000TL HC",
9066 => "SB 1200",
9067 => "STP 10000TL-10",
9068 => "STP 12000TL-10",
9069 => "STP 15000TL-10",
9070 => "STP 17000TL-10",
9084 => "WB 3600TL-20",
9085 => "WB 5000TL-20",
9086 => "SB 3800US-10",
9098 => "STP 5000TL-20",
9099 => "STP 6000TL-20",
9100 => "STP 7000TL-20",
9101 => "STP 8000TL-10",
9102 => "STP 9000TL-20",
9103 => "STP 8000TL-20",
9104 => "SB 3000TL-JP-21",
9105 => "SB 3500TL-JP-21",
9106 => "SB 4000TL-JP-21",
9107 => "SB 4500TL-JP-21",
9108 => "SCSMC",
9109 => "SB 1600TL-10",
9131 => "STP 20000TL-10",
9139 => "STP 20000TLHE-10",
9140 => "STP 15000TLHE-10",
9157 => "Sunny Island 2012",
9158 => "Sunny Island 2224",
9159 => "Sunny Island 5048",
9160 => "SB 3600TL-20",
9168 => "SC630HE-11",
9169 => "SC500HE-11",
9170 => "SC400HE-11",
9171 => "WB 3000TL-21",
9172 => "WB 3600TL-21",
9173 => "WB 4000TL-21",
9174 => "WB 5000TL-21",
9175 => "SC 250",
9176 => "SMA Meteo Station",
9177 => "SB 240-10",
9171 => "WB 3000TL-21",
9172 => "WB 3600TL-21",
9173 => "WB 4000TL-21",
9174 => "WB 5000TL-21",
9179 => "Multigate-10",
9180 => "Multigate-US-10",
9181 => "STP 20000TLEE-10",
9182 => "STP 15000TLEE-10",
9183 => "SB 2000TLST-21",
9184 => "SB 2500TLST-21",
9185 => "SB 3000TLST-21",
9186 => "WB 2000TLST-21",
9187 => "WB 2500TLST-21",
9188 => "WB 3000TLST-21",
9189 => "WTP 5000TL-20",
9190 => "WTP 6000TL-20",
9191 => "WTP 7000TL-20",
9192 => "WTP 8000TL-20",
9193 => "WTP 9000TL-20",
9254 => "Sunny Island 3324",
9255 => "Sunny Island 4.0M",
9256 => "Sunny Island 4248",
9257 => "Sunny Island 4248U",
9258 => "Sunny Island 4500",
9259 => "Sunny Island 4548U",
9260 => "Sunny Island 5.4M",
9261 => "Sunny Island 5048U",
9262 => "Sunny Island 6048U",
9278 => "Sunny Island 3.0M",
9279 => "Sunny Island 4.4M",
9281 => "STP 10000TL-20",
9282 => "STP 11000TL-20",
9283 => "STP 12000TL-20",
9284 => "STP 20000TL-30",
9285 => "STP 25000TL-30",
9301 => "SB1.5-1VL-40",
9302 => "SB2.5-1VL-40",
9303 => "SB2.0-1VL-40",
9304 => "SB5.0-1SP-US-40",
9305 => "SB6.0-1SP-US-40",
9306 => "SB8.0-1SP-US-40",
9307 => "Energy Meter",
);

# Wechselrichter Class-Hash DE
my %SMAInverter_classesDE = (
8000 => "Alle Geräte",
8001 => "Solar-Wechselrichter",
8002 => "Wind-Wechselrichter",
8007 => "Batterie-Wechselrichter",
8033 => "Verbraucher",
8064 => "Sensorik allgemein",
8065 => "Stromzähler",
8128 => "Kommunikationsprodukte",
);

# Wechselrichter Class-Hash EN
my %SMAInverter_classesEN = (
8000 => "All Devices",
8001 => "Solar Inverters",
8002 => "Wind Turbine Inverter",
8007 => "Batterie Inverters",
8033 => "Consumer",
8064 => "Sensor System in General",
8065 => "Electricity meter",
8128 => "Communication products",
);

###############################################################
#                  SMAInverter Initialize
###############################################################
sub SMAInverter_Initialize($) {
 my ($hash) = @_;

 $hash->{DefFn}     = "SMAInverter_Define";
 $hash->{UndefFn}   = "SMAInverter_Undef";
 $hash->{GetFn}     = "SMAInverter_Get";
 $hash->{AttrList}  = "interval " . 
                      "detail-level:0,1,2 " .
                      "disable:1,0 " .
                      "mode:manual,automatic ".
                      "offset ".
                      "suppressSleep:1,0 ".
                      "SBFSpotComp:1,0 " .
					  "showproctime:1,0 ".
					  "timeout " .
                      "target-susyid " .
                      "target-serial " .
                      $readingFnAttributes;
 $hash->{AttrFn}    = "SMAInverter_Attr";

}

###############################################################
#                  SMAInverter Define
###############################################################
sub SMAInverter_Define($$) {
 my ($hash, $def) = @_;
 my @a = split("[ \t][ \t]*", $def);
 
 return "Error: Perl module ".$MissModulSocket." is missing. 
        Install it on Debian with: sudo apt-get install libio-socket-multicast-perl" if($MissModulSocket);
 return "Error: Perl module ".$MissModulDateTime." is missing. 
        Install it on Debian with: sudo apt-get install libdatetime-perl" if($MissModulDateTime);

 return "Wrong syntax: use define <name> SMAInverter <inv-userpwd> <inv-hostname/inv-ip > " if ((int(@a) < 4) and (int(@a) > 5));

 my $name                       = $hash->{NAME};
 $hash->{LASTUPDATE}            = 0;
 $hash->{INTERVAL}              = $hash->{HELPER}{INTERVAL} = AttrVal($name, "interval", 60);
 $hash->{VERSION}               = $SMAInverterVersion;
 $hash->{HELPER}{FAULTEDCYCLES} = 0;
 delete($hash->{HELPER}{AVERAGEBUF}) if($hash->{HELPER}{AVERAGEBUF});
 
 # protocol related defaults
 $hash->{HELPER}{MYSUSYID}              = 233;        # random number, has to be different from any device in local network
 $hash->{HELPER}{MYSERIALNUMBER}        = 123321123;  # random number, has to be different from any device in local network
 $hash->{HELPER}{DEFAULT_TARGET_SUSYID} = 0xFFFF;     # 0xFFFF is any susyid
 $hash->{HELPER}{DEFAULT_TARGET_SERIAL} = 0xFFFFFFFF; # 0xFFFFFFFF is any serialnumber
 $hash->{HELPER}{PKT_ID}                = 0x8001;     # Packet ID
 $hash->{HELPER}{MAXBYTES}              = 300;        # constant MAXBYTES scalar 300

 my ($IP,$Host,$Caps);

 my $Pass = $a[2];                        # to do: check 1-12 Chars

 # extract IP or Hostname from $a[3]
 if (!defined $Host) {
     if ( $a[3] =~ /^([A-Za-z0-9_.])/ ) {
         $Host = $a[3];
     }
 }

 if (!defined $Host) {
     return "Argument:{$a[3]} not accepted as Host or IP. Read device specific help file.";
 }

 $hash->{PASS} = $Pass; 
 $hash->{HOST} = $Host;

 InternalTimer(gettimeofday()+5, "SMAInverter_GetData", $hash, 0);      # Start Hauptroutine

return undef;
}

###############################################################
#                  SMAInverter Undefine
###############################################################
sub SMAInverter_Undef($$) {
 my ($hash, $name) = @_;
 RemoveInternalTimer($hash); 
 BlockingKill($hash->{HELPER}{RUNNING_PID});
return undef;
}


###############################################################
#                  SMAInverter Get
###############################################################
sub SMAInverter_Get($$) {
 my ($hash, @a) = @_;
 return "\"get X\" needs at least an argument" if ( @a < 2 );
 my $name = shift @a;
 my $opt  = shift @a;
 my $timeout  = AttrVal($name, "timeout", 60);
   
 my  $getlist = "Unknown argument $opt, choose one of ".
                "data:noArg ";
                   
 return "module is disabled" if(IsDisabled($name));
  
 if ($opt eq "data") {
     SMAInverter_GetData($hash); 
 } else {
     return "$getlist";
 } 
return undef;
}

###############################################################
#                  SMAInverter Attr
###############################################################
sub SMAInverter_Attr(@) {
    my ($cmd,$name,$aName,$aVal) = @_;
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    my $hash = $defs{$name};
    my $do;

	if ($aName eq "mode") {
        if ($cmd eq "set" && $aVal eq "manual") {
            $hash->{INTERVAL} = $aVal;
        } else {
            $hash->{INTERVAL} = $hash->{HELPER}{INTERVAL};
        }
    InternalTimer(time+5, 'SMAInverter_GetData', $hash, 0);
    }
	
    if ($aName eq "disable") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        my $val   = ($do == 1 ?  "disabled" : "initialized");
  
        readingsSingleUpdate($hash, "state", $val, 1);
        
        if ($do == 0) {
            my $mode = AttrVal($name, "mode", "automatic");
            RemoveInternalTimer($hash);
            InternalTimer(time+5, 'SMAInverter_GetData', $hash, 0);
        } else {
            RemoveInternalTimer($hash);
        }
    }

    if ($aName eq "detail-level") {
        delete $defs{$name}{READINGS};
    }
    
    if ($aName eq "SBFSpotComp") {
        delete $defs{$name}{READINGS};
    }

    if ($aName eq "interval") {
        if ($cmd eq "set") {
            $hash->{HELPER}{INTERVAL} = $aVal;
			$hash->{INTERVAL} = $aVal if(AttrVal($name, "mode", "") ne "manual");
			delete($hash->{HELPER}{AVERAGEBUF}) if($hash->{HELPER}{AVERAGEBUF});
            Log3 $name, 3, "$name - Set $aName to $aVal";
        } else {
            $hash->{INTERVAL} = $hash->{HELPER}{INTERVAL} = 60;
        }
    }
        
    if ($cmd eq "set" && $aName eq "offset") {
            if($aVal !~ /^\d+$/ || $aVal < 0 || $aVal > 7200) { return "The Value of $aName is not valid. Use value between 0 ... 7200 !";}
    } 
	if ($cmd eq "set" && $aName eq "timeout") {
        unless ($aVal =~ /^[0-9]+$/) { return " The Value for $aName is not valid. Use only figures 1-9 !";}
    }
return;
}

###############################################################
#                  Hauptschleife Datenabruf
###############################################################
sub SMAInverter_GetData($) {
 my ($hash) = @_;
 my $name = $hash->{NAME};
 my $interval = AttrVal($name, "interval", 60);
 my $timeout  = AttrVal($name, "timeout", 60);
 
 RemoveInternalTimer($hash, "SMAInverter_GetData");
 
 if ($init_done != 1) {
     InternalTimer(gettimeofday()+5, "SMAInverter_GetData", $hash, 0);
	 return;
 }
 
 return if(IsDisabled($name));
 
 if (exists($hash->{HELPER}{RUNNING_PID})) {
     Log3 ($name, 3, "SMAInverter $name - WARNING - old process $hash->{HELPER}{RUNNING_PID}{pid} will be killed now to start a new BlockingCall");
     BlockingKill($hash->{HELPER}{RUNNING_PID});
 }
 
 Log3 ($name, 4, "$name - ###############################################################");
 Log3 ($name, 4, "$name - ##########  Begin of new SMAInverter get data cycle  ##########");
 Log3 ($name, 4, "$name - ###############################################################");
 Log3 ($name, 4, "$name - timeout cycles since module start: $hash->{HELPER}{FAULTEDCYCLES}");
 
 # decide of operation   
 if(AttrVal($name,"mode","automatic") eq "automatic") {
     # automatic operation mode
	 InternalTimer(gettimeofday()+$interval, "SMAInverter_GetData", $hash, 0);	 
 } 

$hash->{HELPER}{RUNNING_PID} = BlockingCall("getstatus_DoParse", "$name", "getstatus_ParseDone", $timeout, "getstatus_ParseAborted", $hash);
$hash->{HELPER}{RUNNING_PID}{loglevel} = 4;

return;
}

###############################################################
#          non-blocking Inverter Datenabruf
###############################################################
sub getstatus_DoParse($) {
 my ($name) = @_;
 my $hash = $defs{$name};
 my $interval = AttrVal($name, "interval", 60);
 my $sc = AttrVal($name, "SBFSpotComp", 0);
 my ($sup_EnergyProduction,       
     $sup_SpotDCPower, 
     $sup_SpotACPower,            
     $sup_MaxACPower,         
     $sup_MaxACPower2,        
     $sup_SpotACTotalPower,   
     $sup_ChargeStatus,       
     $sup_SpotDCVoltage,      
     $sup_SpotACVoltage,          
     $sup_BatteryInfo,            
     $sup_SpotGridFrequency,      
     $sup_TypeLabel,              
     $sup_OperationTime,          
     $sup_InverterTemperature,    
     $sup_GridRelayStatus,        
     $sup_DeviceStatus);
 my ($inv_TYPE, $inv_CLASS,
	 $inv_SPOT_ETODAY, $inv_SPOT_ETOTAL,
     $inv_susyid,
     $inv_serial,
     $inv_SPOT_PDC1, $inv_SPOT_PDC2,
     $inv_SPOT_PAC1, $inv_SPOT_PAC2, $inv_SPOT_PAC3, $inv_SPOT_PACTOT,
     $inv_PACMAX1, $inv_PACMAX2, $inv_PACMAX3, $inv_PACMAX1_2,
     $inv_ChargeStatus,
     $inv_SPOT_UDC1, $inv_SPOT_UDC2,
     $inv_SPOT_IDC1, $inv_SPOT_IDC2,
     $inv_SPOT_UAC1, $inv_SPOT_UAC2, $inv_SPOT_UAC3,
     $inv_SPOT_IAC1, $inv_SPOT_IAC2, $inv_SPOT_IAC3,
     $inv_BAT_UDC, $inv_BAT_IDC,
     $inv_BAT_CYCLES,
     $inv_BAT_TEMP,
     $inv_SPOT_FREQ, $inv_SPOT_OPERTM, $inv_SPOT_FEEDTM, $inv_TEMP, $inv_GRIDRELAY, $inv_STATUS,);
 my @row_array;
 my @array;
 my $avg = 0;
 my ($ist,$bst,$irt,$brt,$rt);
 
 # Background-Startzeit
 $bst = [gettimeofday];
        
 Log3 ($name, 4, "$name -> Start BlockingCall getstatus_DoParse");
 
 # set dependency from surise/sunset used for inverter operation time 
 my $offset = AttrVal($name,"offset",0);
 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
 my ($sunrise_h,$sunrise_m,$sunrise_s) = split(":",sunrise_abs('-'.$offset));
 my ($sunset_h,$sunset_m,$sunset_s)    = split(":",sunset_abs('+'.$offset));
 my $oper_start = DateTime->new(year=>$year+1900,month=>$mon+1,day=>$mday,hour=>$sunrise_h,minute=>$sunrise_m,second=>$sunrise_s,time_zone=>'local');
 my $oper_stop  = DateTime->new(year=>$year+1900,month=>$mon+1,day=>$mday,hour=>$sunset_h,minute=>$sunset_m,second=>$sunset_s,time_zone=>'local');
 my $dt_now = DateTime->now(time_zone=>'local');
 Log3 $name, 4, "$name - current time: ".$dt_now->dmy('.')." ".$dt_now->hms;
 Log3 $name, 4, "$name - operation time begin: ".$oper_start->dmy('.')." ".$oper_start->hms;
 Log3 $name, 4, "$name - operation time end: ".$oper_stop->dmy('.')." ".$oper_stop->hms;
 my $opertime_start = $oper_start->dmy('.')." ".$oper_start->hms;
 my $opertime_stop  = $oper_stop->dmy('.')." ".$oper_stop->hms;
 
 if (($oper_start <= $dt_now && $dt_now <= $oper_stop) || AttrVal($name,"suppressSleep",0)) {
     # normal operation or suppressed sleepmode
	 
	 # Abfrage Inverter Startzeit
     $ist = [gettimeofday];
 
     # Get the current attributes
     my $detail_level  = AttrVal($name, "detail-level", 0);
 
     # Aufbau Command-Array
     my @commands = ("sup_TypeLabel",                  # Check TypeLabel
                     "sup_EnergyProduction",           # Check EnergyProduction
		    		 "sup_SpotDCPower",                # Check SpotDCPower
			    	 "sup_SpotACPower",                # Check SpotACPower
				     "sup_SpotACTotalPower",           # Check SpotACTotalPower
				     "sup_ChargeStatus"                # Check BatteryChargeStatus
				     );
 
     if($detail_level > 0) {
         # Detail Level 1 or 2 >> get voltage and current levels
	     push(@commands, "sup_SpotDCVoltage");         # Check SpotDCVoltage
	     push(@commands, "sup_SpotACVoltage");         # Check SpotACVoltage
	     push(@commands, "sup_BatteryInfo");           # Check BatteryInfo
     }
 
     if($detail_level > 1) {
          # Detail Level 2 >> get all data
	      push(@commands, "sup_SpotGridFrequency");     # Check SpotGridFrequency
          push(@commands, "sup_OperationTime");         # Check OperationTime
          push(@commands, "sup_InverterTemperature");   # Check InverterTemperature
          push(@commands, "sup_MaxACPower");            # Check MaxACPower
          push(@commands, "sup_MaxACPower2");           # Check MaxACPower2
          push(@commands, "sup_GridRelayStatus");       # Check GridRelayStatus
          push(@commands, "sup_DeviceStatus");	       # Check DeviceStatus 
     }

     if(SMA_logon($hash->{HOST}, $hash->{PASS}, $hash)) {
         Log3 $name, 5, "$name - Logged in now";
	 
	     foreach my $i(@commands) {
             if ($i eq "sup_TypeLabel") {
		         ($sup_TypeLabel,$inv_TYPE,$inv_CLASS,$inv_susyid,$inv_serial) = SMA_command($hash, $hash->{HOST}, 0x58000200, 0x00821E00, 0x008220FF);
		     } 
			 elsif ($i eq "sup_EnergyProduction") {
		         ($sup_EnergyProduction,$inv_SPOT_ETODAY,$inv_SPOT_ETOTAL,$inv_susyid,$inv_serial) = SMA_command($hash, $hash->{HOST}, 0x54000200, 0x00260100, 0x002622FF);
		     } 
		     elsif ($i eq "sup_SpotDCPower") {
		         ($sup_SpotDCPower,$inv_SPOT_PDC1,$inv_SPOT_PDC2,$inv_susyid,$inv_serial) = SMA_command($hash, $hash->{HOST}, 0x53800200, 0x00251E00, 0x00251EFF);
		     } 
		     elsif ($i eq "sup_SpotACPower") {
		         ($sup_SpotACPower,$inv_SPOT_PAC1,$inv_SPOT_PAC2,$inv_SPOT_PAC3,$inv_susyid,$inv_serial) = SMA_command($hash, $hash->{HOST}, 0x51000200, 0x00464000, 0x004642FF);
	         } 
		     elsif ($i eq "sup_SpotACTotalPower") {
		         ($sup_SpotACTotalPower,$inv_SPOT_PACTOT,$inv_susyid,$inv_serial) = SMA_command($hash, $hash->{HOST}, 0x51000200, 0x00263F00, 0x00263FFF);
		     }    
		     elsif ($i eq "sup_ChargeStatus") {
		         ($sup_ChargeStatus,$inv_ChargeStatus,$inv_susyid,$inv_serial) = SMA_command($hash, $hash->{HOST}, 0x51000200, 0x00295A00, 0x00295AFF);
		     } 
		     elsif ($i eq "sup_SpotDCVoltage") {
		         ($sup_SpotDCVoltage,$inv_SPOT_UDC1,$inv_SPOT_UDC2,$inv_SPOT_IDC1,$inv_SPOT_IDC2,$inv_susyid,$inv_serial) = SMA_command($hash, $hash->{HOST}, 0x53800200, 0x00451F00, 0x004521FF);
		     } 
		     elsif ($i eq "sup_SpotACVoltage") {
		         ($sup_SpotACVoltage,$inv_SPOT_UAC1,$inv_SPOT_UAC2,$inv_SPOT_UAC3,$inv_SPOT_IAC1,$inv_SPOT_IAC2,$inv_SPOT_IAC3,$inv_susyid,$inv_serial) = SMA_command($hash, $hash->{HOST}, 0x51000200, 0x00464800, 0x004655FF);
		     } 
		     elsif ($i eq "sup_BatteryInfo") {
		         ($sup_BatteryInfo,$inv_BAT_CYCLES,$inv_BAT_TEMP,$inv_BAT_UDC,$inv_BAT_IDC,$inv_susyid,$inv_serial) = SMA_command($hash, $hash->{HOST}, 0x51000200, 0x00491E00, 0x00495DFF);
		     } 
		     elsif ($i eq "sup_SpotGridFrequency") {
		         ($sup_SpotGridFrequency,$inv_SPOT_FREQ,$inv_susyid,$inv_serial) = SMA_command($hash, $hash->{HOST}, 0x51000200, 0x00465700, 0x004657FF);
		     } 
		     elsif ($i eq "sup_OperationTime") {
		         ($sup_OperationTime,$inv_SPOT_OPERTM,$inv_SPOT_FEEDTM,$inv_susyid,$inv_serial) = SMA_command($hash, $hash->{HOST}, 0x54000200, 0x00462E00, 0x00462FFF);
		     } 
		     elsif ($i eq "sup_InverterTemperature") {
		         ($sup_InverterTemperature,$inv_TEMP,$inv_susyid,$inv_serial) = SMA_command($hash, $hash->{HOST}, 0x52000200, 0x00237700, 0x002377FF);
		     } 
		     elsif ($i eq "sup_MaxACPower") {
		         ($sup_MaxACPower,$inv_PACMAX1,$inv_PACMAX2,$inv_PACMAX3,$inv_susyid,$inv_serial) = SMA_command($hash, $hash->{HOST}, 0x51000200, 0x00411E00, 0x004120FF);
		     } 
		     elsif ($i eq "sup_MaxACPower2") {
		         ($sup_MaxACPower2,$inv_PACMAX1_2,$inv_susyid,$inv_serial) = SMA_command($hash, $hash->{HOST}, 0x51000200, 0x00832A00, 0x00832AFF);
		     }   
		     elsif ($i eq "sup_GridRelayStatus") {
		         ($sup_GridRelayStatus,$inv_GRIDRELAY,$inv_susyid,$inv_serial) = SMA_command($hash, $hash->{HOST}, 0x51800200, 0x00416400, 0x004164FF);
		     } 
		     elsif ($i eq "sup_DeviceStatus") {
		         ($sup_DeviceStatus,$inv_STATUS,$inv_susyid,$inv_serial) = SMA_command($hash, $hash->{HOST}, 0x51800200, 0x00214800, 0x002148FF);
		     } 
         }	 
	 
         # nothing more to do, just log out
         SMA_logout($hash,$hash->{HOST});
 
         # Inverter Laufzeit ermitteln
         $irt = tv_interval($ist);
 
	     # Aufbau Ergebnis-Array
	     push(@row_array, "modulstate normal"."\n");
	     push(@row_array, "opertime_start ".$opertime_start."\n");
	     push(@row_array, "opertime_stop ".$opertime_stop."\n");	 
	 
	     # Durchschnittswerteberechnung Energieerzeugung der letzten 5, 10, 15 Messungen 
		 
		 my ($sum05, $sum10, $sum15);
	     my $cnt05  = int(300/$interval);          # Anzahl der Zyklen innerhalb 5 Minuten
         my $cnt10  = int(600/$interval);          # Anzahl der Zyklen innerhalb 10 Minuten
         my $cnt15  = int(900/$interval);		   # Anzahl der Zyklen innerhalb 15 Minuten = Summe aller Messzyklen
		 my $cntsum = $cnt15+1;                    # Sicherheitszuschlag Summe Anzahl aller Zyklen
		 my @averagebuf;
	     if ($sup_TypeLabel && $sup_EnergyProduction && $inv_CLASS eq 8001) {	
		     # only for this block because of warnings if values not set at restart
             no warnings 'uninitialized'; 
	         if (!$hash->{HELPER}{AVERAGEBUF}) {
		         for my $count (0..$cntsum) {
			         # fill with new values
					 $inv_SPOT_PACTOT = $inv_SPOT_PACTOT?$inv_SPOT_PACTOT:0;
				     push(@averagebuf, $inv_SPOT_PACTOT);					 
			     }
		     } else {
			     @averagebuf = split(/,/, $hash->{HELPER}{AVERAGEBUF})
			 }
	
		     # rechtes Element aus average buffer löschen 
		     pop(@averagebuf);			 
		     # und links mit neuem Wert füllen
		     unshift(@averagebuf, $inv_SPOT_PACTOT);
		     $avg = join(',', @averagebuf);

             # calculate average energy and write to array for generate readings
             my $k = 1;
			 my $avgsum = $averagebuf[0];
			 while ($k < $cntsum) {
			     $avgsum = $avgsum + $averagebuf[$k] if($averagebuf[$k]);
				 if ($k == $cnt05) {
				     $sum05 = $avgsum;
					 Log3 $name, 5, "$name - CNT05: $cnt05 SUM05: $sum05";
				 }
				 if ($k == $cnt10) {
				     $sum10 = $avgsum;
					 Log3 $name, 5, "$name - CNT10: $cnt10 SUM10: $sum10";
				 }
				 if ($k == $cnt15) {
				     $sum15 = $avgsum;
					 Log3 $name, 5, "$name - CNT15: $cnt15 SUM15: $sum15";
				 }
			     $k++;
			 }
			 
		     my $AvP05 = int( $sum05 / ($cnt05+1) );
		     my $AvP10 = int( $sum10 / ($cnt10+1) );
		     my $AvP15 = int( $sum15 / ($cnt15+1) );
	         Log3 $name, 5, "$name - Content of Averagebuffer:";
		     Log3 $name, 5, "$name - $avg";
		     Log3 $name, 5, "$name - avg_power_lastminutes_05 = $AvP05, avg_power_lastminutes_10 = $AvP10, avg_power_lastminutes_15 = $AvP15";
		 
		     push(@row_array, "avg_power_lastminutes_05 ".$AvP05."\n");   # Average Energy (last) 5 minutes
	         push(@row_array, "avg_power_lastminutes_10 ".$AvP10."\n");   # Average Energy (last) 10 minutes
	         push(@row_array, "avg_power_lastminutes_15 ".$AvP15."\n");   # Average Energy (last) 15 minutes
			 
			 use warnings;
	     } 
	 
         if ($sc) {                                            # SBFSpot Kompatibilitätsmodus
             if($sup_EnergyProduction) {
	             push(@row_array, "etotal ".($inv_SPOT_ETOTAL/1000)."\n");
	             push(@row_array, "etoday ".($inv_SPOT_ETODAY/1000)."\n");
             }
             if($sup_SpotDCPower) {
	             push(@row_array, "string_1_pdc ".sprintf("%.3f",$inv_SPOT_PDC1/1000)."\n");
	             push(@row_array, "string_2_pdc ".sprintf("%.3f",$inv_SPOT_PDC2/1000)."\n");		     
             }
             if($sup_SpotACPower) {
	             push(@row_array, "phase_1_pac ".sprintf("%.3f",$inv_SPOT_PAC1/1000)."\n");
	             push(@row_array, "phase_2_pac ".sprintf("%.3f",$inv_SPOT_PAC2/1000)."\n");	
	             push(@row_array, "phase_3_pac ".sprintf("%.3f",$inv_SPOT_PAC3/1000)."\n");	
             }
             if($sup_SpotACTotalPower) {
	             push(@row_array, "total_pac ".sprintf("%.3f",$inv_SPOT_PACTOT/1000)."\n");	
	             push(@row_array, "state ".sprintf("%.3f",$inv_SPOT_PACTOT/1000)."\n");		     
             }
             if($sup_ChargeStatus) {
	             push(@row_array, "chargestatus ".$inv_ChargeStatus."\n");		     
             }
             if($inv_CLASS && $inv_CLASS eq 8007) {
                 if($inv_SPOT_PACTOT < 0) {
	                 push(@row_array, "power_out "."0"."\n");
	                 push(@row_array, "power_in ".(-1 * $inv_SPOT_PACTOT)."\n");
                 } else {
	                 push(@row_array, "power_out ".$inv_SPOT_PACTOT."\n");
	                 push(@row_array, "power_in "."0"."\n");			     
                 }
             }
		 	 
             if($detail_level > 0) {
                 # For Detail Level 1 
                 if($sup_SpotDCVoltage) {
	                 push(@row_array, "string_1_udc ".sprintf("%.2f",$inv_SPOT_UDC1)."\n");
	                 push(@row_array, "string_2_udc ".sprintf("%.2f",$inv_SPOT_UDC2)."\n");
	                 push(@row_array, "string_1_idc ".sprintf("%.3f",$inv_SPOT_IDC1)."\n");
	                 push(@row_array, "string_2_idc ".sprintf("%.3f",$inv_SPOT_IDC2)."\n");
                 }
                 if($sup_SpotACVoltage) {
	                 push(@row_array, "phase_1_uac ".sprintf("%.2f",$inv_SPOT_UAC1)."\n");
	                 push(@row_array, "phase_2_uac ".sprintf("%.2f",$inv_SPOT_UAC2)."\n");
	                 push(@row_array, "phase_3_uac ".sprintf("%.2f",$inv_SPOT_UAC3)."\n");
	                 push(@row_array, "phase_1_iac ".sprintf("%.3f",$inv_SPOT_IAC1)."\n");
	                 push(@row_array, "phase_2_iac ".sprintf("%.3f",$inv_SPOT_IAC2)."\n");
	                 push(@row_array, "phase_3_iac ".sprintf("%.3f",$inv_SPOT_IAC3)."\n");
                 }
                 if($sup_BatteryInfo) {
	                 push(@row_array, "bat_udc ".$inv_BAT_UDC."\n");
	                 push(@row_array, "bat_idc ".$inv_BAT_IDC."\n");
                 }
             }
         
             if($detail_level > 1) {
                 # For Detail Level 2
                 if($sup_BatteryInfo) {
	                 push(@row_array,"bat_cycles ".$inv_BAT_CYCLES."\n");
	                 push(@row_array, "bat_temp ".$inv_BAT_TEMP."\n");
                 }
                 if($sup_SpotGridFrequency) {
	                 push(@row_array, "grid_freq. ".sprintf("%.2f",$inv_SPOT_FREQ)."\n");
                 }
                 if($sup_TypeLabel) {
	                 push(@row_array, "device_type ".devtype($inv_TYPE)."\n");
	                 push(@row_array, "device_class ".classtype($inv_CLASS)."\n");
					 push(@row_array, "susyid ".$inv_susyid." - SN: ".$inv_serial."\n") if($inv_susyid && $inv_serial);
	                 push(@row_array, "device_name "."SN: ".$inv_serial."\n") if($inv_serial);
	                 push(@row_array, "serial_number ".$inv_serial."\n") if($inv_serial);
                 }
                 if($sup_MaxACPower) {
	                 push(@row_array, "pac_max_phase_1 ".$inv_PACMAX1."\n");
	                 push(@row_array, "pac_max_phase_2 ".$inv_PACMAX2."\n");
	                 push(@row_array, "pac_max_phase_3 ".$inv_PACMAX3."\n");
                 }
                 if($sup_MaxACPower2) {
	                 push(@row_array, "pac_max_phase_1_2 ".$inv_PACMAX1_2."\n");
                 }
                 if($sup_InverterTemperature) {
	                 push(@row_array, "device_temperature ".sprintf("%.1f",$inv_TEMP)."\n");
                 }
                 if($sup_OperationTime) {
	                 push(@row_array, "feed-in_time ".$inv_SPOT_FEEDTM."\n");
	                 push(@row_array, "operation_time ".$inv_SPOT_OPERTM."\n");
                 }
                 if($sup_GridRelayStatus) {
	                 push(@row_array, "gridrelay_status ".StatusText($inv_GRIDRELAY)."\n");
                 }
                 if($sup_DeviceStatus) {
	                 push(@row_array, "device_status ".StatusText($inv_STATUS)."\n");
                 }
             } 
         } else {     # kein SBFSpot Compatibility Mode
             if($sup_EnergyProduction) {
	             push(@row_array, "SPOT_ETOTAL ".$inv_SPOT_ETOTAL."\n");
	             push(@row_array, "SPOT_ETODAY ".$inv_SPOT_ETODAY."\n");
             }
             if($sup_SpotDCPower) {
	             push(@row_array, "SPOT_PDC1 ".$inv_SPOT_PDC1."\n");
	             push(@row_array, "SPOT_PDC2 ".$inv_SPOT_PDC2."\n");
             }
             if($sup_SpotACPower) {
	             push(@row_array, "SPOT_PAC1 ".$inv_SPOT_PAC1."\n");
	             push(@row_array, "SPOT_PAC2 ".$inv_SPOT_PAC2."\n");
	             push(@row_array, "SPOT_PAC3 ".$inv_SPOT_PAC3."\n");
             }
             if($sup_SpotACTotalPower) {
	             push(@row_array, "SPOT_PACTOT ".$inv_SPOT_PACTOT."\n");
	             push(@row_array, "state ".$inv_SPOT_PACTOT."\n");
             }
             if($sup_ChargeStatus) {
	             push(@row_array, "ChargeStatus ".$inv_ChargeStatus."\n");
             }
             if($inv_CLASS && $inv_CLASS eq 8007) {
                 if($inv_SPOT_PACTOT < 0) {
	                 push(@row_array, "POWER_OUT "."0"."\n");
	                 push(@row_array, "POWER_IN ".(-1 * $inv_SPOT_PACTOT)."\n");
                 } else {
	                 push(@row_array, "POWER_OUT ".$inv_SPOT_PACTOT."\n");
	                 push(@row_array, "POWER_IN "."0"."\n");
                 }
             }
             if($detail_level > 0) {
                 # For Detail Level 1 
                 if($sup_SpotDCVoltage) {
	                 push(@row_array, "SPOT_UDC1 ".$inv_SPOT_UDC1."\n");
	                 push(@row_array, "SPOT_UDC2 ".$inv_SPOT_UDC2."\n");
	                 push(@row_array, "SPOT_IDC1 ".$inv_SPOT_IDC1."\n");
	                 push(@row_array, "SPOT_IDC2 ".$inv_SPOT_IDC2."\n");
                 }
                 if($sup_SpotACVoltage) {
	                 push(@row_array, "SPOT_UAC1 ".$inv_SPOT_UAC1."\n");
	                 push(@row_array, "SPOT_UAC2 ".$inv_SPOT_UAC2."\n");
	                 push(@row_array, "SPOT_UAC3 ".$inv_SPOT_UAC3."\n");
	                 push(@row_array, "SPOT_IAC1 ".$inv_SPOT_IAC1."\n");
	                 push(@row_array, "SPOT_IAC2 ".$inv_SPOT_IAC2."\n");
	                 push(@row_array, "SPOT_IAC3 ".$inv_SPOT_IAC3."\n");
                 }
                 if($sup_BatteryInfo) {
	                 push(@row_array, "BAT_UDC ".$inv_BAT_UDC."\n");
	                 push(@row_array, "BAT_IDC ".$inv_BAT_IDC."\n");
                 }
             }
              
             if($detail_level > 1) {
                 # For Detail Level 2
                 if($sup_BatteryInfo) {
	                 push(@row_array, "BAT_CYCLES ".$inv_BAT_CYCLES."\n");
	                 push(@row_array, "BAT_TEMP ".$inv_BAT_TEMP."\n");
                 }
                 if($sup_SpotGridFrequency) {
	                 push(@row_array, "SPOT_FREQ ".$inv_SPOT_FREQ."\n");
                 }
                 if($sup_TypeLabel) {
	                 push(@row_array, "INV_TYPE ".devtype($inv_TYPE)."\n");
	                 push(@row_array, "INV_CLASS ".classtype($inv_CLASS)."\n");
				     push(@row_array, "SUSyID ".$inv_susyid."\n") if($inv_susyid);
	                 push(@row_array, "Serialnumber ".$inv_serial."\n") if($inv_serial);
                 }
                 if($sup_MaxACPower) {
	                 push(@row_array, "INV_PACMAX1 ".$inv_PACMAX1."\n");
	                 push(@row_array, "INV_PACMAX2 ".$inv_PACMAX2."\n");
	                 push(@row_array, "INV_PACMAX3 ".$inv_PACMAX3."\n");
                 }
                 if($sup_MaxACPower2) {
	                 push(@row_array, "INV_PACMAX1_2 ".$inv_PACMAX1_2."\n");
                 }
                 if($sup_InverterTemperature) {
	                 push(@row_array, "INV_TEMP ".$inv_TEMP."\n");
                 }
                 if($sup_OperationTime) {
	                 push(@row_array, "SPOT_FEEDTM ".$inv_SPOT_FEEDTM."\n");
	                 push(@row_array, "SPOT_OPERTM ".$inv_SPOT_OPERTM."\n");
                 }
                 if($sup_GridRelayStatus) {
	                 push(@row_array, "INV_GRIDRELAY ".StatusText($inv_GRIDRELAY)."\n");
                 }
                 if($sup_DeviceStatus) {
	                 push(@row_array, "INV_STATUS ".StatusText($inv_STATUS)."\n");
                 }
             } 
         }
     } else {
         # Login failed/not possible
	     push(@row_array, "state Login failed"."\n");
	     push(@row_array, "modulstate login failed"."\n");	
     }
 } else {
     # sleepmode at current time and not suppressed
	 push(@row_array, "modulstate sleep"."\n");
	 push(@row_array, "opertime_start ".$opertime_start."\n");
	 push(@row_array, "opertime_stop ".$opertime_stop."\n");
	 push(@row_array, "state done"."\n");
 }
 
 Log3 ($name, 5, "$name -> row_array before encoding:");
 foreach my $row (@row_array) {
	 chomp $row;
     Log3 ($name, 5, "$name -> $row");
 }
 
 # encoding result 
 my $rowlist = join('|', @row_array);
 $rowlist    = encode_base64($rowlist,"");
 
 # Background-Laufzeit ermitteln
 $brt = tv_interval($bst);

 $rt = ($irt?$irt:'').",".$brt;
 
 Log3 ($name, 4, "$name -> BlockingCall getstatus_DoParse finished");
 
return "$name|$rowlist|$avg|$rt"; 
}
 
###############################################################
#         Auswertung non-blocking Inverter Datenabruf
###############################################################
sub getstatus_ParseDone ($) {
 my ($string)                = @_;
 my @a                       = split("\\|",$string);
 my $name                    = $a[0];
 my $hash                    = $defs{$name};
 my $rowlist                 = decode_base64($a[1]);
 $hash->{HELPER}{AVERAGEBUF} = $a[2] if($a[2]);
 my $rt                      = $a[3]; 
 my ($irt,$brt)              = split(",", $rt);
 
 Log3 ($name, 4, "$name -> Start BlockingCall getstatus_ParseDone");
  
 # proctime Readings löschen
 if(!AttrVal($name, "showproctime", undef)) {
     delete($defs{$name}{READINGS}{inverter_processing_time});
     delete($defs{$name}{READINGS}{background_processing_time});
 } else {
     delete($defs{$name}{READINGS}{inverter_processing_time}) if(!$irt);
 }
 
 # Get current time
 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
 $hash->{LASTUPDATE} = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;	

 my @row_array = split("\\|", $rowlist);
 
 Log3 ($name, 5, "$name -> row_array after decoding:");
 foreach my $row (@row_array) {
     chomp $row;
     Log3 ($name, 5, "$name -> $row");
 }
 
 readingsBeginUpdate($hash); 
 foreach my $row (@row_array) {
     chomp $row;
	 my @a = split(" ", $row, 2);
     $hash->{MODEL} = $a[1] if($a[0] eq "device_type");
     readingsBulkUpdate($hash, $a[0], $a[1]);
 }
 readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt)) if(AttrVal($name, "showproctime", undef));  
 readingsBulkUpdate($hash, "inverter_processing_time", sprintf("%.4f",$irt)) if(AttrVal($name, "showproctime", undef) && $irt);
 readingsEndUpdate($hash, 1);
 
 delete($hash->{HELPER}{RUNNING_PID});
 Log3 ($name, 4, "$name -> BlockingCall getstatus_ParseDone finished");
 
return;
}

###############################################################
#           Abbruchroutine Timeout Inverter Abfrage
###############################################################
sub getstatus_ParseAborted(@) {
  my ($hash,$cause) = @_;
  my $name      = $hash->{NAME};
  my $discycles = $hash->{HELPER}{FAULTEDCYCLES};
  $cause = $cause?$cause:"Timeout: process terminated";
  
  # count of timeouts since module start
  $discycles++;
  $hash->{HELPER}{FAULTEDCYCLES} = $discycles;
  
  Log3 ($name, 1, "SMAInverter $name -> BlockingCall $hash->{HELPER}{RUNNING_PID}{fn} $cause");
  readingsSingleUpdate($hash,"state",$cause, 1);
  
  delete($hash->{HELPER}{RUNNING_PID});

return;
}

##########################################################################
#                     SMA Command Execution
##########################################################################
sub SMA_command($$$$$) {
 # Parameters: $hash - host - command - first - last
 my ($hash,$host,$command,$first,$last) = @_;
 my $name = $hash->{NAME};
 my $cmdheader = "534D4100000402A00000000100";
 my $pktlength = "26";		              # length = 38 for data commands
 my $esignature = "0010606509A0";
 my ($inv_TYPE, $inv_CLASS,
	 $inv_SPOT_ETODAY, $inv_SPOT_ETOTAL,
     $inv_susyid,
     $inv_serial,
     $inv_SPOT_PDC1, $inv_SPOT_PDC2,
     $inv_SPOT_PAC1, $inv_SPOT_PAC2, $inv_SPOT_PAC3, $inv_SPOT_PACTOT,
     $inv_PACMAX1, $inv_PACMAX2, $inv_PACMAX3, $inv_PACMAX1_2,
     $inv_ChargeStatus,
     $inv_SPOT_UDC1, $inv_SPOT_UDC2,
     $inv_SPOT_IDC1, $inv_SPOT_IDC2,
     $inv_SPOT_UAC1, $inv_SPOT_UAC2, $inv_SPOT_UAC3,
     $inv_SPOT_IAC1, $inv_SPOT_IAC2, $inv_SPOT_IAC3,
     $inv_BAT_UDC, $inv_BAT_IDC,
     $inv_BAT_CYCLES,
     $inv_BAT_TEMP,
     $inv_SPOT_FREQ, $inv_SPOT_OPERTM, $inv_SPOT_FEEDTM, $inv_TEMP, $inv_GRIDRELAY, $inv_STATUS);
 my $mysusyid = $hash->{HELPER}{MYSUSYID};
 my $myserialnumber = $hash->{HELPER}{MYSERIALNUMBER};
 my ($cmd, $myID, $target_ID, $spkt_ID, $cmd_ID);
 my ($socket,$data,$size,$data_ID);
 my ($i, $temp);                          # Variables for loops and calculation
 
 # Seriennummer und SuSyID des Ziel-WR setzen 
 my $default_target_susyid = $hash->{HELPER}{DEFAULT_TARGET_SUSYID};
 my $default_target_serial = $hash->{HELPER}{DEFAULT_TARGET_SERIAL};   
 my $target_susyid = AttrVal($name, "target-susyid", $default_target_susyid);
 my $target_serial = AttrVal($name, "target-serial", $default_target_serial);

 # Define own ID and target ID and packet ID
 $myID      = ByteOrderShort(substr(sprintf("%04X",$mysusyid),0,4)) . ByteOrderLong(sprintf("%08X",$myserialnumber));
 $target_ID = ByteOrderShort(substr(sprintf("%04X",$target_susyid),0,4)) . ByteOrderLong(sprintf("%08X",$target_serial));
 
 # Increasing Packet ID
 $hash->{HELPER}{PKT_ID} = $hash->{HELPER}{PKT_ID} + 1;	
 $spkt_ID = ByteOrderShort(sprintf("%04X",$hash->{HELPER}{PKT_ID}));

 $cmd_ID = ByteOrderLong(sprintf("%08X",$command)) . ByteOrderLong(sprintf("%08X",$first)) . ByteOrderLong(sprintf("%08X",$last));

 #build final command to send
 $cmd = $cmdheader . $pktlength . $esignature . $target_ID . "0000" . $myID . "0000" . "00000000" . $spkt_ID . $cmd_ID . "00000000";

 # flush after every write
 $| = 1; 
 
 # Create Socket and check if successful
 $socket = new IO::Socket::INET (PeerHost => $host, PeerPort => 9522, Proto => 'udp',); # open Socket

 if (!$socket) {
    # in case of error
    Log3 $name, 1, "$name - ERROR. Can't open socket to inverter: $!";
    return 0;
 };

 # Send Data
 $data = pack("H*",$cmd);
 $socket->send($data);
 Log3 $name, 3, "$name - Send request $cmd_ID to $host on port 9522";
 Log3 $name, 5, "$name - send: $cmd";

 # Receive Data and do a first check regarding length
 # receive data
 $socket->recv($data, $hash->{HELPER}{MAXBYTES});
 $size = length($data);

 # check if something was received
 if (defined $size) {
     my $received = unpack("H*", $data);
     Log3 $name, 5, "$name - Received: $received";
 }
 
 # Nothing received -> exit
 if (not defined $size) {
     Log3 $name, 1, "$name - Nothing received...";
	 return 0;
 } else {
     # We have received something!
     if ($size > 58) {
	     # Check all parameters of answer
		 my $r_susyid = unpack("v*", substr $data, 20, 2);
		 my $r_serial = unpack("V*", substr $data, 22, 4);
		 my $r_pkt_ID = unpack("v*", substr $data, 40, 2);
		 my $r_error  = unpack("V*", substr $data, 36, 4);
		 if (($r_susyid ne $mysusyid) || ($r_serial ne $myserialnumber) || ($r_pkt_ID ne $hash->{HELPER}{PKT_ID}) || ($r_error ne 0)) {
		     # Response does not match the parameters we have sent, maybe different target
			 Log3 $name, 3, "$name - Inverter answer does not match our parameters.";
			 Log3 $name, 5, "$name - Request/Response: SusyID $mysusyid/$r_susyid, Serial $myserialnumber/$r_serial, Packet ID $hash->{HELPER}{PKT_ID}/$r_pkt_ID, Error $r_error";
			 $socket->close();
			 return 0;
		 }
	 } else {
	     Log3 $name, 3, "$name - Format of inverter response does not fit.";
		 $socket->close();
		 return 0;
	 }
 }
	
 # All seems ok, data received
 $inv_susyid = unpack("v*", substr $data, 28, 2);
 $inv_serial = unpack("V*", substr $data, 30, 4);
 $socket->close();
 
 if (AttrVal($name, "target-serial", undef)) {
     return 0 unless($target_serial eq $inv_serial);
 }
 if (AttrVal($name, "target-susyid", undef)) {
     return 0 unless($target_susyid eq $inv_susyid);
 }
	
 # Check the data identifier
 $data_ID = unpack("v*", substr $data, 55, 2);
 Log3 $name, 5, "$name - Data identifier $data_ID";
	
 if($data_ID eq 0x2601)	{
     $inv_SPOT_ETOTAL = unpack("V*", substr($data, 62, 4));
	 $inv_SPOT_ETODAY = unpack("V*", substr $data, 78, 4);
	 Log3 $name, 5, "$name - Found Data SPOT_ETOTAL=$inv_SPOT_ETOTAL and SPOT_ETODAY=$inv_SPOT_ETODAY";
	 return (1,$inv_SPOT_ETODAY,$inv_SPOT_ETOTAL,$inv_susyid,$inv_serial);
 }
			
 if($data_ID eq 0x251E) {
     $inv_SPOT_PDC1 = unpack("V*", substr $data, 62, 4);
	 if($size < 90) {$inv_SPOT_PDC2 = 0; } else {$inv_SPOT_PDC2 = unpack("V*", substr $data, 90, 4); } # catch short response, in case PDC2 not supported
	 $inv_SPOT_PDC1 = ($inv_SPOT_PDC1 == 2147483648) ? 0 : $inv_SPOT_PDC1;
	 $inv_SPOT_PDC2 = ($inv_SPOT_PDC2 == 2147483648) ? 0 : $inv_SPOT_PDC2;
	 Log3 $name, 5, "$name - Found Data SPOT_PDC1=$inv_SPOT_PDC1 and SPOT_PDC2=$inv_SPOT_PDC2";
	 return (1,$inv_SPOT_PDC1,$inv_SPOT_PDC2,$inv_susyid,$inv_serial);
 } 
		
 if($data_ID eq 0x4640) {
     $inv_SPOT_PAC1 = unpack("l*", substr $data, 62, 4);
	 if($inv_SPOT_PAC1 eq -2147483648) {$inv_SPOT_PAC1 = 0; }	# Catch 0x80000000 as 0 value
	 $inv_SPOT_PAC2 = unpack("l*", substr $data, 90, 4);
	 if($inv_SPOT_PAC2 eq -2147483648) {$inv_SPOT_PAC2 = 0; }	# Catch 0x80000000 as 0 value
	 $inv_SPOT_PAC3 = unpack("l*", substr $data, 118, 4);
	 if($inv_SPOT_PAC3 eq -2147483648) {$inv_SPOT_PAC3 = 0; }	# Catch 0x80000000 as 0 value
	 Log3 $name, 5, "$name - Found Data SPOT_PAC1=$inv_SPOT_PAC1 and SPOT_PAC2=$inv_SPOT_PAC2 and SPOT_PAC3=$inv_SPOT_PAC3";
	 return (1,$inv_SPOT_PAC1,$inv_SPOT_PAC2,$inv_SPOT_PAC3,$inv_susyid,$inv_serial);
 }
		
 if($data_ID eq 0x411E) {
     $inv_PACMAX1 = unpack("V*", substr $data, 62, 4);
	 $inv_PACMAX2 = unpack("V*", substr $data, 90, 4);
	 $inv_PACMAX3 = unpack("V*", substr $data, 118, 4);
	 Log3 $name, 5, "$name - Found Data INV_PACMAX1=$inv_PACMAX1 and INV_PACMAX2=$inv_PACMAX2 and INV_PACMAX3=$inv_PACMAX3";
	 return (1,$inv_PACMAX1,$inv_PACMAX2,$inv_PACMAX3,$inv_susyid,$inv_serial);
 }
		
 if($data_ID eq 0x832A) {
     $inv_PACMAX1_2 = unpack("V*", substr $data, 62, 4);
	 Log3 $name, 5, "$name - Found Data INV_PACMAX1_2=$inv_PACMAX1_2";
	 return (1,$inv_PACMAX1_2,$inv_susyid,$inv_serial);
 }
		
 if($data_ID eq 0x263F) {
     $inv_SPOT_PACTOT = unpack("l*", substr $data, 62, 4);
	 if($inv_SPOT_PACTOT eq -2147483648) {$inv_SPOT_PACTOT = 0; }	# Catch 0x80000000 as 0 value
	 Log3 $name, 5, "$name - Found Data SPOT_PACTOT=$inv_SPOT_PACTOT";
	 return (1,$inv_SPOT_PACTOT,$inv_susyid,$inv_serial);
 }
		
 if($data_ID eq 0x295A) {
     $inv_ChargeStatus = unpack("V*", substr $data, 62, 4);
	 Log3 $name, 5, "$name - Found Data Battery Charge Status=$inv_ChargeStatus";
	 return (1,$inv_ChargeStatus,$inv_susyid,$inv_serial);
 }

 if($data_ID eq 0x451F) {
     $inv_SPOT_UDC1 = unpack("l*", substr $data, 62, 4);
	 # catch shorter responses in case not second string supported
	 if($size < 146) {
		$inv_SPOT_UDC2 = 0;
		$inv_SPOT_IDC1 = unpack("l*", substr $data, 90, 4);
		$inv_SPOT_IDC2 = 0;	 
	 } else {
		$inv_SPOT_UDC2 = unpack("l*", substr $data, 90, 4);
		$inv_SPOT_IDC1 = unpack("l*", substr $data, 118, 4);
		$inv_SPOT_IDC2 = unpack("l*", substr $data, 146, 4);
	 }
	 if(($inv_SPOT_UDC1 eq -2147483648) || ($inv_SPOT_UDC1 eq 0xFFFFFFFF)) {$inv_SPOT_UDC1 = 0; } else {$inv_SPOT_UDC1 = $inv_SPOT_UDC1 / 100; }	# Catch 0x80000000 and 0xFFFFFFFF as 0 value
	 if(($inv_SPOT_UDC2 eq -2147483648) || ($inv_SPOT_UDC2 eq 0xFFFFFFFF)) {$inv_SPOT_UDC2 = 0; } else {$inv_SPOT_UDC2 = $inv_SPOT_UDC2 / 100; }	# Catch 0x80000000 and 0xFFFFFFFF as 0 value
	 if(($inv_SPOT_IDC1 eq -2147483648) || ($inv_SPOT_IDC1 eq 0xFFFFFFFF)) {$inv_SPOT_IDC1 = 0; } else {$inv_SPOT_IDC1 = $inv_SPOT_IDC1 / 1000; }	# Catch 0x80000000 and 0xFFFFFFFF as 0 value
	 if(($inv_SPOT_IDC2 eq -2147483648) || ($inv_SPOT_IDC2 eq 0xFFFFFFFF)) {$inv_SPOT_IDC2 = 0; } else {$inv_SPOT_IDC2 = $inv_SPOT_IDC2 / 1000; }	# Catch 0x80000000 and 0xFFFFFFFF as 0 value
	 Log3 $name, 5, "$name - Found Data SPOT_UDC1=$inv_SPOT_UDC1 and SPOT_UDC2=$inv_SPOT_UDC2 and SPOT_IDC1=$inv_SPOT_IDC1 and SPOT_IDC2=$inv_SPOT_IDC2";
	 return (1,$inv_SPOT_UDC1,$inv_SPOT_UDC2,$inv_SPOT_IDC1,$inv_SPOT_IDC2,$inv_susyid,$inv_serial);
 }

 if($data_ID eq 0x4648) {
     $inv_SPOT_UAC1 = unpack("l*", substr $data, 62, 4);
	 $inv_SPOT_UAC2 = unpack("l*", substr $data, 90, 4);
	 $inv_SPOT_UAC3 = unpack("l*", substr $data, 118, 4);
	 $inv_SPOT_IAC1 = unpack("l*", substr $data, 146, 4);
	 $inv_SPOT_IAC2 = unpack("l*", substr $data, 174, 4);
	 $inv_SPOT_IAC3 = unpack("l*", substr $data, 202, 4);
	 if(($inv_SPOT_UAC1 eq -2147483648) || ($inv_SPOT_UAC1 eq 0xFFFFFFFF) || $inv_SPOT_UAC1 < 0) {$inv_SPOT_UAC1 = 0; } else {$inv_SPOT_UAC1 = $inv_SPOT_UAC1 / 100; }	# Catch 0x80000000 and 0xFFFFFFFF as 0 value
	 if(($inv_SPOT_UAC2 eq -2147483648) || ($inv_SPOT_UAC2 eq 0xFFFFFFFF) || $inv_SPOT_UAC2 < 0) {$inv_SPOT_UAC2 = 0; } else {$inv_SPOT_UAC2 = $inv_SPOT_UAC2 / 100; }	# Catch 0x80000000 and 0xFFFFFFFF as 0 value
	 if(($inv_SPOT_UAC3 eq -2147483648) || ($inv_SPOT_UAC3 eq 0xFFFFFFFF) || $inv_SPOT_UAC3 < 0) {$inv_SPOT_UAC3 = 0; } else {$inv_SPOT_UAC3 = $inv_SPOT_UAC3 / 100; }	# Catch 0x80000000 and 0xFFFFFFFF as 0 value
	 if(($inv_SPOT_IAC1 eq -2147483648) || ($inv_SPOT_IAC1 eq 0xFFFFFFFF)) {$inv_SPOT_IAC1 = 0; } else {$inv_SPOT_IAC1 = $inv_SPOT_IAC1 / 1000; }	# Catch 0x80000000 and 0xFFFFFFFF as 0 value
	 if(($inv_SPOT_IAC2 eq -2147483648) || ($inv_SPOT_IAC2 eq 0xFFFFFFFF)) {$inv_SPOT_IAC2 = 0; } else {$inv_SPOT_IAC2 = $inv_SPOT_IAC2 / 1000; }	# Catch 0x80000000 and 0xFFFFFFFF as 0 value
	 if(($inv_SPOT_IAC3 eq -2147483648) || ($inv_SPOT_IAC3 eq 0xFFFFFFFF)) {$inv_SPOT_IAC3 = 0; } else {$inv_SPOT_IAC3 = $inv_SPOT_IAC3 / 1000; }	# Catch 0x80000000 and 0xFFFFFFFF as 0 value
	 Log3 $name, 5, "$name - Found Data SPOT_UAC1=$inv_SPOT_UAC1 and SPOT_UAC2=$inv_SPOT_UAC2 and SPOT_UAC3=$inv_SPOT_UAC3 and SPOT_IAC1=$inv_SPOT_IAC1 and SPOT_IAC2=$inv_SPOT_IAC2 and SPOT_IAC3=$inv_SPOT_IAC3";
	 return (1,$inv_SPOT_UAC1,$inv_SPOT_UAC2,$inv_SPOT_UAC3,$inv_SPOT_IAC1,$inv_SPOT_IAC2,$inv_SPOT_IAC3,$inv_susyid,$inv_serial);
 }

 if($data_ID eq 0x491E) {
     $inv_BAT_CYCLES = unpack("V*", substr $data, 62, 4);
	 $inv_BAT_TEMP = unpack("V*", substr $data, 90, 4) / 10; 
	 $inv_BAT_UDC = unpack("V*", substr $data, 118, 4) / 100;
	 $inv_BAT_IDC = unpack("l*", substr $data, 146, 4); 
	 if($inv_BAT_IDC eq -2147483648) {$inv_BAT_IDC = 0; } else { $inv_BAT_IDC = $inv_BAT_IDC / 1000;} 	# Catch 0x80000000 as 0 value
	 Log3 $name, 5, "$name - Found Data BAT_CYCLES=$inv_BAT_CYCLES and BAT_TEMP=$inv_BAT_TEMP and BAT_UDC=$inv_BAT_UDC and BAT_IDC=$inv_BAT_IDC";
	 return (1,$inv_BAT_CYCLES,$inv_BAT_TEMP,$inv_BAT_UDC,$inv_BAT_IDC,$inv_susyid,$inv_serial);
 }

 if($data_ID eq 0x2377) {
     $inv_TEMP = unpack("l*", substr $data, 62, 4);
	 if($inv_TEMP eq -2147483648) {$inv_TEMP = 0; } else { $inv_TEMP = $inv_TEMP / 100;} 	# Catch 0x80000000 as 0 value
	 Log3 $name, 5, "$name - Found Data Inverter Temp=$inv_TEMP";
	 return (1,$inv_TEMP,$inv_susyid,$inv_serial);
 }

 if($data_ID eq 0x462E) {
     $inv_SPOT_OPERTM = int(unpack("V*", substr $data, 62, 4) / 36) / 100;
	 $inv_SPOT_FEEDTM = int(unpack("V*", substr $data, 78, 4) / 36) / 100;
	 Log3 $name, 5, "$name - Found Data SPOT_OPERTM=$inv_SPOT_OPERTM and SPOT_FEEDTM=$inv_SPOT_FEEDTM";
	 return (1,$inv_SPOT_OPERTM,$inv_SPOT_FEEDTM,$inv_susyid,$inv_serial);
 }

 if($data_ID eq 0x4657) {
     $inv_SPOT_FREQ = unpack("V*", substr $data, 62, 4);
	 if(($inv_SPOT_FREQ eq -2147483648) || ($inv_SPOT_FREQ eq 0xFFFFFFFF)) {$inv_SPOT_FREQ = 0; } else {$inv_SPOT_FREQ = $inv_SPOT_FREQ / 100; }	# Catch 0x80000000 and 0xFFFFFFFF as 0 value
	 Log3 $name, 5, "$name - Found Data SPOT_FREQ=$inv_SPOT_FREQ";
	 return (1,$inv_SPOT_FREQ,$inv_susyid,$inv_serial);
 }

 if($data_ID eq 0x821E) {
     $inv_CLASS = unpack("V*", substr $data, 102, 4) & 0x00FFFFFF;
	 $i = 142;		# start address of INV_TYPE
	 $inv_TYPE = 0; # initialize to unknown inverter type
	 do {
		$temp = unpack("V*", substr $data, $i, 4);
		if(($temp & 0xFF000000) eq 0x01000000) { $inv_TYPE = $temp & 0x00FFFFFF; }				# in some models a catalogue is transmitted, right model marked with: 0x01000000 OR INV_Type
		$i = $i+4;
	 } while ((unpack("V*", substr $data, $i, 4) ne 0x00FFFFFE) && ($i<$size));			# 0x00FFFFFE is the end marker for attributes

	 Log3 $name, 5, "$name - Found Data CLASS=$inv_CLASS and TYPE=$inv_TYPE";
	 return (1,$inv_TYPE,$inv_CLASS,$inv_susyid,$inv_serial);
 }

 if($data_ID eq 0x4164) {
     $i = 0;
	 $temp = 0;
	 $inv_GRIDRELAY = 0x00FFFFFD;		# Code for No Information;
	 do {
	     $temp = unpack("V*", substr $data, 62 + $i*4, 4);
		 if(($temp & 0xFF000000) ne 0) { $inv_GRIDRELAY = $temp & 0x00FFFFFF; }
		 $i = $i + 1;
	 } while ((unpack("V*", substr $data, 62 + $i*4, 4) ne 0x00FFFFFE) && ($i < 5));		# 0x00FFFFFE is the end marker for attributes
		 Log3 $name, 5, "$name - Found Data INV_GRIDRELAY=$inv_GRIDRELAY";
		 return (1,$inv_GRIDRELAY,$inv_susyid,$inv_serial);
	 }

 if($data_ID eq 0x2148) {
     $i = 0;
	 $temp = 0;
	 $inv_STATUS = 0x00FFFFFD;		# Code for No Information;
	 do {
	     $temp = unpack("V*", substr $data, 62 + $i*4, 4);
		 if(($temp & 0xFF000000) ne 0) { $inv_STATUS = $temp & 0x00FFFFFF; }
		 $i = $i + 1;
	 } while ((unpack("V*", substr $data, 62 + $i*4, 4) ne 0x00FFFFFE) && ($i < 5)); 	# 0x00FFFFFE is the end marker for attributes
		 Log3 $name, 5, "$name - Found Data inv_STATUS=$inv_STATUS";
		 return (1,$inv_STATUS,$inv_susyid,$inv_serial);
	 }
	
return 0;
}

##########################################################################
#                                Login
##########################################################################
sub SMA_logon($$$) {
 # Parameters: host - passcode
 my ($host,$pass,$hash)  = @_;
 my $cmdheader = "534D4100000402A00000000100";
 my $pktlength = "3A";                             # length = 58 for logon command
 my $esignature = "001060650EA0";
 my $name = $hash->{NAME};
 my $mysusyid = $hash->{HELPER}{MYSUSYID};
 my $myserialnumber = $hash->{HELPER}{MYSERIALNUMBER};
 my $pkt_ID = $hash->{HELPER}{PKT_ID};
 my ($cmd, $timestmp, $myID, $target_ID, $spkt_ID, $cmd_ID);
 my ($socket,$data,$size);
 
 # Seriennummer und SuSyID des Ziel-WR setzen 
 my $default_target_susyid = $hash->{HELPER}{DEFAULT_TARGET_SUSYID};
 my $default_target_serial = $hash->{HELPER}{DEFAULT_TARGET_SERIAL};   
 my $target_susyid = AttrVal($name, "target-susyid", $default_target_susyid);
 my $target_serial = AttrVal($name, "target-serial", $default_target_serial);

 #Encode the password
 my $encpasswd = "888888888888888888888888"; # template for password	
 for my $index (0..length $pass )	     # encode password
 {
     if ( (hex(substr($encpasswd,($index*2),2)) + ord(substr($pass,$index,1))) < 256 ) {
		substr($encpasswd,($index*2),2) = substr(sprintf ("%lX", (hex(substr($encpasswd,($index*2),2)) + ord(substr($pass,$index,1)))),0,2);
	} else {
		substr($encpasswd,($index*2),2) = substr(sprintf ("%lX", (hex(substr($encpasswd,($index*2),2)) + ord(substr($pass,$index,1)))),1,2);	
	}
 }

 # Get current timestamp in epoch format (unix format)
 $timestmp = ByteOrderLong(sprintf("%08X",int(time())));

 # Define own ID and target ID and packet ID
 $myID      = ByteOrderShort(substr(sprintf("%04X",$mysusyid),0,4)) . ByteOrderLong(sprintf("%08X",$myserialnumber));
 $target_ID = ByteOrderShort(substr(sprintf("%04X",$target_susyid),0,4)) . ByteOrderLong(sprintf("%08X",$target_serial));
 $pkt_ID    = 0x8001;	# Reset to 0x8001
 $spkt_ID   = ByteOrderShort(sprintf("%04X",$pkt_ID));

 #Logon command
 $cmd_ID = "0C04FDFF" . "07000000" . "84030000";  # Logon command + User group "User" + (maybe) Timeout

 #build final command to send
 $cmd = $cmdheader . $pktlength . $esignature . $target_ID . "0001" . $myID . "0001" . "00000000" . $spkt_ID . $cmd_ID . $timestmp . "00000000" . $encpasswd . "00000000";

 # flush after every write
 $| = 1; 

 # Create Socket and check if successful
 $socket = new IO::Socket::INET (PeerHost => $host, PeerPort => 9522, Proto => 'udp',); # open Socket

 if (!$socket) {
     # in case of error
     Log3 $name, 1, "$name - ERROR - Can't open socket to inverter: $!";
     return 0;
 };

 # Send Data
 $data = pack("H*",$cmd);
 $socket->send($data);
 Log3 $name, 4, "$name - Send login to $host on Port 9522 with password $pass ";
 Log3 $name, 5, "$name - Send: $cmd ";
	
 # Receive Data and do a first check regarding length
 eval {
     $socket->recv($data, $hash->{HELPER}{MAXBYTES});
     $size = length($data);
 };

 # check if something was received
 if (defined $size)	{
     my $received = unpack("H*", $data);
     Log3 $name, 5, "$name - Received: $received";
 }

 # Nothing received -> exit
 if (not defined $size) {
     Log3 $name, 1, "$name - Nothing received...";
     # send: cmd_logout
     $socket->close();
     SMA_logout($hash,$host);
     return 0;
 } else {
    # We have received something!
    if ($size > 62) {
        # Check all parameters of answer
        my $r_susyid = unpack("v*", substr $data, 20, 2);
        my $r_serial = unpack("V*", substr $data, 22, 4);
        my $r_pkt_ID = unpack("v*", substr $data, 40, 2);
        my $r_cmd_ID = unpack("V*", substr $data, 42, 4);
        my $r_error  = unpack("V*", substr $data, 36, 4);

        if (($r_pkt_ID ne $pkt_ID) || ($r_cmd_ID ne 0xFFFD040D) || ($r_error ne 0)) {
            # Response does not match the parameters we have sent, maybe different target
            Log3 $name, 1, "$name - Inverter answer does not match our parameters.";
            Log3 $name, 5, "$name - Request/Response: SusyID $mysusyid/$r_susyid, Serial $myserialnumber/$r_serial, Packet ID $hash->{HELPER}{PKT_ID}/$r_pkt_ID, Command 0xFFFD040D/$r_cmd_ID, Error $r_error";
            # send: cmd_logout
            $socket->close();
            SMA_logout($hash,$host);
            return 0;
        }
    } else {
        Log3 $name, 1, "$name - Format of inverter response does not fit.";
        # send: cmd_logout
        $socket->close();
        SMA_logout($hash,$host);
        return 0;
    }
 }

 # All seems ok, logged in! 
 my $inv_susyid = unpack("v*", substr $data, 28, 2);
 my $inv_serial = unpack("V*", substr $data, 30, 4);
 $socket->close();
 
  if (AttrVal($name, "target-serial", undef)) {
     return 0 unless($inv_serial eq $target_serial);
 }
 if (AttrVal($name, "target-susyid", undef)) {
     return 0 unless($inv_susyid eq $target_susyid);
 }
 
 Log3 $name, 4, "$name - logged in to inverter serial: $inv_serial, susyid: $inv_susyid";
 return 1;
}

##########################################################################
#                               Logout
##########################################################################
sub SMA_logout($$) {
 # Parameters: host
 my ($hash,$host) = @_;
 my $name = $hash->{NAME};
 my $cmdheader = "534D4100000402A00000000100";
 my $pktlength = "22";		# length = 34 for logout command
 my $esignature = "0010606508A0";
 my $mysusyid = $hash->{HELPER}{MYSUSYID};
 my $myserialnumber = $hash->{HELPER}{MYSERIALNUMBER};
 my $pkt_ID = $hash->{HELPER}{PKT_ID};
 my ($cmd, $myID, $target_ID, $spkt_ID, $cmd_ID);
 my ($socket,$data,$size);
 
 # Seriennummer und SuSyID des Ziel-WR setzen 
 my $default_target_susyid = $hash->{HELPER}{DEFAULT_TARGET_SUSYID};
 my $default_target_serial = $hash->{HELPER}{DEFAULT_TARGET_SERIAL};   
 my $target_susyid = AttrVal($name, "target-susyid", $default_target_susyid);
 my $target_serial = AttrVal($name, "target-serial", $default_target_serial);

 # Define own ID and target ID and packet ID
 $myID      = ByteOrderShort(substr(sprintf("%04X",$mysusyid),0,4)) . ByteOrderLong(sprintf("%08X",$myserialnumber));
 $target_ID = ByteOrderShort(substr(sprintf("%04X",$target_susyid),0,4)) . ByteOrderLong(sprintf("%08X",$target_serial));
 # Increasing Packet ID
 $hash->{HELPER}{PKT_ID} = $hash->{HELPER}{PKT_ID} + 1;	
 $spkt_ID = ByteOrderShort(sprintf("%04X",$hash->{HELPER}{PKT_ID}));
 
 #Logout command
 $cmd_ID = "0E01FDFF" . "FFFFFFFF";  # Logout command

 #build final command to send
 $cmd = $cmdheader . $pktlength . $esignature . $target_ID . "0003" . $myID . "0003" . "00000000" . $spkt_ID . $cmd_ID . "00000000";

 # flush after every write
 $| = 1; 

 # Create Socket and check if successful
 $socket = new IO::Socket::INET (PeerHost => $host, PeerPort => 9522, Proto => 'udp',); # open Socket

 if (!$socket) {
     # in case of error
     Log3 $name, 1, "$name - ERROR - Can't open socket to inverter: $!";
     return 0;
 };

 # Send Data
 $data = pack("H*",$cmd);
 $socket->send($data);
 Log3 $name, 4, "$name - Send logout to $host on Port 9522";
 Log3 $name, 5, "$name - Send: $cmd ";
 
 $target_serial = ($target_serial eq $default_target_serial)?"any inverter":$target_serial;
 $target_susyid = ($target_susyid eq $default_target_susyid)?"any susyid":$target_susyid;
 Log3 $name, 4, "$name - logged out now from inverter serial: $target_serial, susyid: $target_susyid";
 
 $socket->close();	
 return 1;	
}

##########################################################################
#                           Hilfsroutinen
##########################################################################

##########################
sub ByteOrderShort($) {
 my $input = $_[0];
 my $output = "";
 $output = substr($input, 2, 2) . substr($input, 0, 2);
 return $output;
}

##########################
sub ByteOrderLong($) {
 my $input = $_[0];
 my $output = "";
 $output = substr($input, 6, 2) . substr($input, 4, 2) . substr($input, 2, 2) . substr($input, 0, 2);
 return $output;
}

##########################
sub StatusText($)
{
 # Parameter is the code, return value is the Text or if not known then the code as string
 my $code = $_[0];

 if($code eq 51)       { return (AttrVal("global", "language", "EN") eq "DE") ? "geschlossen" : "Closed"; }
 if($code eq 311)      { return (AttrVal("global", "language", "EN") eq "DE") ? "offen" : "Open"; }
 if($code eq 16777213) { return (AttrVal("global", "language", "EN") eq "DE") ? "Information liegt nicht vor" : "No Information"; }

 if($code eq 35)       { return (AttrVal("global", "language", "EN") eq "DE") ? "Fehler" : "Fault"; }
 if($code eq 303)      { return "Off"; }
 if($code eq 307)      { return "Ok"; }
 if($code eq 455)      { return (AttrVal("global", "language", "EN") eq "DE") ? "Warnung" : "Warning"; }

 return sprintf("%d", $code);
}

##########################
#  identify device type

sub devtype ($) {
  my ($code) = @_;
  
  unless (exists($SMAInverter_devtypes{$code})) { return $code;}
  my $dev = $SMAInverter_devtypes{$code};
  return ($dev);
}

##########################
#  identify device class

sub classtype ($) {
  my ($code) = @_;
  my $class;
  
  if(AttrVal("global", "language", "EN") eq "DE") {
      unless (exists($SMAInverter_classesDE{$code})) { return $code;}
      $class = $SMAInverter_classesDE{$code};
  } else {
      unless (exists($SMAInverter_classesEN{$code})) { return $code;}
      $class = $SMAInverter_classesEN{$code};
  }
  
return ($class);
}

1;

=pod
=item summary    Integration of SMA Inverters over it's Speedwire (=Ethernet) Interface
=item summary_DE Integration von SMA Wechselrichtern über Speedwire (=Ethernet) Interface

=begin html

<a name="SMAInverter"></a>
<h3>SMAInverter</h3>

Module for the integration of a SMA Inverter over it's Speedwire (=Ethernet) Interface.<br>
Tested on Sunny Tripower 6000TL-20 and Sunny Island 4.4 with Speedwire/Webconnect Piggyback.
<br><br>

Questions and discussions about this module you can find in the FHEM-Forum link:<br>
<a href="https://forum.fhem.de/index.php/topic,56080.msg476525.html#msg476525">76_SMAInverter.pm - Abfrage von SMA Wechselrichter</a>.
<br><br>

<b>Requirements</b> 
<br><br>
This module requires:
<ul>
    <li>Perl Module: IO::Socket::INET  (apt-get install libio-socket-multicast-perl) </li>
    <li>Perl Module: Date::Time        (apt-get install libdatetime-perl) </li>
	<li>Perl Module: Time::HiRes</li>
    <li>FHEM Module: 99_SUNRISE_EL.pm</li>
	<li>FHEM Module: Blocking.pm</li>
</ul>
<br>
<br>


<b>Define</b>
<ul>
<code>define &lt;name&gt; SMAInverter &lt;pin&gt; &lt;hostname/ip&gt; </code><br>
<br>
<li>pin: User-Password of the SMA Inverter. Default is 0000. Can be changed by "Sunny Explorer" Windows Software</li>
<li>hostname/ip: Hostname or IP-Adress of the inverter (or it's speedwire piggyback module).</li>
<li>Port of the inverter is 9522 by default. Firewall has to allow connection on this port !</li>
</ul>


<b>Operation method</b>
<ul>
The module sends commands to the inverter and checks if they are supported by the inverter.<br>
In case of a positive answer the data is collected and displayed in the readings according to the detail-level. <br>
If more than one inverter is installed, set attributes "target-susyid" and "target-serial" with an appropriate value. <br><br>

The normal operation time of the inverter is supposed from sunrise to sunset. In that time period the inverter will be polled.
The time of sunrise and sunset will be calculated by functions of FHEM module 99_SUNRISE_EL.pm which is loaded automatically by default. 
Therefore the global attribute "longitude" and "latitude" should be set to determine the position of the solar system 
(see <a href="#SUNRISE_EL">Commandref SUNRISE_EL</a>). <br><br>

By the attribute "suppressSleep" the sleep mode between sunset and sunrise can be suppressed. Using attribute "offset" you may prefer the sunrise and
defer the sunset virtually. So the working period of the inverter will be extended. <br><br>

In operating mode "automatic" the inverter will be requested periodically corresponding the preset attribute "interval". The operating mode can be 
switched to "manual" to realize the retrieval manually (e.g. to synchronize the requst with a SMA energy meter by notify). <br><br>

During inverter operating time the average energy production of the last 5, 10 and 15 minutes will be calculated and displayed in the readings  
"avg_power_lastminutes_05", "avg_power_lastminutes_10" and "avg_power_lastminutes_15". <b>Note:</b> To permit a precise calculation, you should 
also set the real request interval into the attribute "interval" although you would use the "manual" operation mode ! <br><br>

The retrieval of the inverter will be executed non-blocking. You can adjust the timeout value for this background process by attribute "timeout". <br>
</ul>

<b>Get</b> 
<br>
<ul>
<code>get &lt;name&gt; data</code>
<br><br>

The request of the inverter will be executed. Those possibility is especifically created for the "manual" operation mode (see attribute "mode").

</ul>

<b>Attributes</b>
<ul>
  <li><b>interval</b>       : Queryintreval in seconds </li>
  <li><b>detail-level</b>   : "0" - Only Power and Energy / "1" - Including Voltage and Current / "2" - All values </li>
  <li><b>disable</b>        : 1 = the module is disabled </li>
  <li><b>mode</b>           : automatic = the inverter will be polled by preset interval, manual = query only by command "get &lt;name&gt; data" </li>
  <li><b>offset</b>         : time in seconds to prefer the sunrise respectively defer the sunset virtualy (0 ... 7200).  You will be able to extend the working
                              period of the module. </li>
  <li><b>SBFSpotComp</b>    : 1 = the readings are created like SBFSpot-style </li>
  <li><b>suppressSleep</b>  : the sleep mode (after sunset, before sunrise) is deactivated and the inverter will be polled continuously.  </li>
  <li><b>showproctime</b>   : shows processing time in background and wasted time to retrieve inverter data  </li>
  <li><b>target-susyid</b>  : In case of a Multigate the target SUSyID can be defined. If more than one inverter is installed you have to
                              set the inverter-SUSyID to assign the inverter to the device definition.
                              Default is 0xFFFF, means any SUSyID</li>
  <li><b>target-serial</b>  : In case of a Multigate the target Serialnumber can be defined. If more than one inverter is installed you have to
                              set the inverter-Serialnumber to assign the inverter to the device definition.
							  Default is 0xFFFFFFFF, means any Serialnumber</li>
  <li><b>timeout</b>        : setup timeout of inverter data request (default 60s) </li>  
</ul>

<b>Readings</b>
<ul>
<li><b>BAT_CYCLES / bat_cycles</b>          :  Battery recharge cycles </li>
<li><b>BAT_IDC / bat_idc</b>                :  Battery Current </li>
<li><b>BAT_TEMP / bat_temp</b>              :  Battery temperature </li>
<li><b>BAT_UDC / bat_udc</b>                :  Battery Voltage </li>
<li><b>ChargeStatus / chargestatus</b>      :  Battery Charge status </li>
<li><b>CLASS / device_class</b>             :  Inverter Class </li>
<li><b>PACMAX1 / pac_max_phase_1</b>        :  Nominal power in Ok Mode </li>
<li><b>PACMAX1_2 / pac_max_phase_1_2</b>    :  Maximum active power device (Some inverters like SB3300/SB1200) </li>
<li><b>PACMAX2 / pac_max_phase_2</b>        :  Nominal power in Warning Mode </li>
<li><b>PACMAX3 / pac_max_phase_3</b>        :  Nominal power in Fault Mode </li>
<li><b>Serialnumber / serial_number</b>     :  Inverter Serialnumber </li>
<li><b>SPOT_ETODAY / etoday</b>             :  Today yield </li>
<li><b>SPOT_ETOTAL / etotal</b>             :  Total yield </li>
<li><b>SPOT_FEEDTM / feed-in_time</b>       :  Feed-in time </li>
<li><b>SPOT_FREQ / grid_freq.</b>           :  Grid Frequency </li>
<li><b>SPOT_IAC1 / phase_1_iac</b>          :  Grid current phase L1 </li>
<li><b>SPOT_IAC2 / phase_2_iac</b>          :  Grid current phase L2 </li>
<li><b>SPOT_IAC3 / phase_3_iac</b>          :  Grid current phase L3 </li>
<li><b>SPOT_IDC1 / string_1_idc</b>         :  DC current input </li>
<li><b>SPOT_IDC2 / string_2_idc</b>         :  DC current input </li>
<li><b>SPOT_OPERTM / operation_time</b>     :  Operation Time </li>
<li><b>SPOT_PAC1 / phase_1_pac</b>          :  Power L1  </li>
<li><b>SPOT_PAC2 / phase_2_pac</b>          :  Power L2  </li>
<li><b>SPOT_PAC3 / phase_3_pac</b>          :  Power L3  </li>
<li><b>SPOT_PACTOT / total_pac</b>          :  Total Power </li>
<li><b>SPOT_PDC1 / string_1_pdc</b>         :  DC power input 1 </li>
<li><b>SPOT_PDC2 / string_2_pdc</b>         :  DC power input 2 </li>
<li><b>SPOT_UAC1 / phase_1_uac</b>          :  Grid voltage phase L1 </li>
<li><b>SPOT_UAC2 / phase_2_uac</b>          :  Grid voltage phase L2 </li>
<li><b>SPOT_UAC3 / phase_3_uac</b>          :  Grid voltage phase L3 </li>
<li><b>SPOT_UDC1 / string_1_udc</b>         :  DC voltage input </li>
<li><b>SPOT_UDC2 / string_2_udc</b>         :  DC voltage input </li>
<li><b>SUSyID / susyid</b>                  :  Inverter SUSyID </li>
<li><b>INV_TEMP / device_temperature</b>    :  Inverter temperature </li>
<li><b>INV_TYPE / device_type</b>           :  Inverter Type </li>
<li><b>POWER_IN / power_in</b>              :  Battery Charging power </li>
<li><b>POWER_OUT / power_out</b>            :  Battery Discharging power </li>
<li><b>INV_GRIDRELAY / gridrelay_status</b> :  Grid Relay/Contactor Status </li>
<li><b>INV_STATUS / device_status</b>       :  Inverter Status </li>
<li><b>opertime_start</b>                   :  Begin of iverter operating time corresponding the calculated time of sunrise with consideration of the  
                                               attribute "offset" (if set) </li>
<li><b>opertime_stop</b>                    :  End of iverter operating time corresponding the calculated time of sunrise with consideration of the  
                                               attribute "offset" (if set) </li>
<li><b>modulstate</b>                       :  shows the current module state "normal" or "sleep" if the inverter won't be requested at the time. </li>
<li><b>avg_power_lastminutes_05</b>         :  average power of the last 5 minutes. </li>	
<li><b>avg_power_lastminutes_10</b>         :  average power of the last 10 minutes. </li>	
<li><b>avg_power_lastminutes_15</b>         :  average power of the last 15 minutes. </li>
<li><b>inverter_processing_time</b>         :  wasted time to retrieve the inverter data </li>
<li><b>background_processing_time</b>       :  total wasted time by background process (BlockingCall) </li>
</ul>
<br><br>

=end html


=begin html_DE

<a name="SMAInverter"></a>
<h3>SMAInverter</h3>

Modul zur Einbindung eines SMA Wechselrichters über Speedwire (Ethernet).<br>
Getestet mit Sunny Tripower 6000TL-20 und Sunny Island 4.4 mit Speedwire/Webconnect Piggyback.
<br><br>

Fragen und Diskussionen rund um dieses Modul finden sie im FHEM-Forum unter:<br>
<a href="https://forum.fhem.de/index.php/topic,56080.msg476525.html#msg476525">76_SMAInverter.pm - Abfrage von SMA Wechselrichter</a>.
<br><br>

<b>Voraussetzungen</b> 
<br><br>
Dieses Modul benötigt:
<ul>
    <li>Perl Modul: IO::Socket::INET   (apt-get install libio-socket-multicast-perl) </li>
    <li>Perl Modul: Datetime           (apt-get install libdatetime-perl) </li>
	<li>Perl Modul: Time::HiRes</li>
    <li>FHEM Modul: 99_SUNRISE_EL.pm</li>
	<li>FHEM Modul: Blocking.pm</li>
</ul>
<br>
<br>


<b>Define</b>
<ul>
<code>define &lt;name&gt; SMAInverter &lt;pin&gt; &lt;hostname/ip&gt;</code><br>
<br>
<li>pin: Benutzer-Passwort des SMA STP Wechselrichters. Default ist 0000. Kann über die Windows-Software "Sunny Explorer" geändert werden </li>
<li>hostname/ip: Hostname oder IP-Adresse des Wechselrichters (bzw. dessen Speedwire Moduls mit Ethernetanschluss) </li>
<li>Der Port des Wechselrichters ist 9522. Dieser Port muss in der Firewall freigeschaltet sein !</li>
</ul>


<b>Arbeitsweise</b>
<ul>
Das Modul schickt Befehle an den Wechselrichter und überprüft, ob diese unterstützt werden.<br>
Bei einer positiven Antwort werden die Daten gesammelt und je nach Detail-Level in den Readings dargestellt. <br>
Sind mehr als ein Wechselrichter installiert, sind die Attribute "target-susyid" und "target-serial" entsprechend zu setzen um die korrekte
Funktion zu gewährleisten. <br><br>

Die normale Betriebszeit des Wechselrichters wird in der Zeit vom Sonnenaufgang bis Sonnenuntergang angenommen. In dieser Periode werden die Wechselrichterdaten
abgefragt. Die Ermittlung von Sonnenaufgang / Sonnenuntergang wird über die Funktionen des FHEM-Moduls 99_SUNRISE_EL.pm vorgenommen. Zu diesem Zweck sollten die globalen
Attribute longitude und latitude gesetzt sein um den Standort der Anlage genau zu ermitteln. (siehe <a href="#SUNRISE_EL">Commandref SUNRISE_EL</a>) <br><br>

Mit dem Attribut "suppressSleep" kann der Schlafmodus unterdrückt werden. Das Attribut "offset" dient dazu den effektiven Zeitpunkt des Sonnenaufgangs / Sonnenuntergangs
um den Betrag "offset" vorzuziehen (Sonnenaufgang) bzw. zu verzögern (Sonnenuntergang) und somit die Abfrageperiode des Wechselrichters zu verlängern. <br><br>

Im Betriebsmodus "automatic" wird der Wechselrichter entsprechend des eingestellten Attributs "interval" abgefragt. Der Betriebsmodus kann in "manual" 
umgestellt werden um eine manuelle Abfrage zu realisieren (z.B. Synchronisierung mit einem SMA Energymeter über ein Notify). <br><br>

Während der Betriebszeit des Wechselrichters wird die durchschnittliche Energieerzeugung der letzten 5, 10, 15 Minuten berechnet und in den Readings 
"avg_power_lastminutes_05", "avg_power_lastminutes_10" und "avg_power_lastminutes_15" ausgegeben. <b>Hinweis:</b> Um eine korrekte Berechnung zu 
ermöglichen, sollte auch im Betriebsmodus "manual" das tatsächliche Abfrageinterval im Attribute "interval" hinterlegt werden ! <br><br>

Die Abfrage des Wechselrichters wird non-blocking ausgeführt. Der Timeoutwert für diesen Hintergrundprozess kann mit dem Attribut "timeout" eingestellt werden. <br>

</ul>

<b>Get</b> 
<br>
<ul>
<code>get &lt;name&gt; data</code>
<br><br>

Die Datenabfrage des Wechselrichters wird ausgeführt. Diese Möglichkeit ist speziell für den Betriebsmodus "manual" vorgesehen (siehe Attribut "mode").

</ul>

<b>Attribute</b>
<ul>
  <li><b>interval</b>         : Abfrageinterval in Sekunden </li>
  <li><b>detail-level</b>     : "0" - Nur Leistung und Energie / "1" - zusätzlich Strom und Spannung / "2" - Alle Werte </li>
  <li><b>disable</b>          : 1 = das Modul ist disabled </li>
  <li><b>mode</b>             : automatic = die Wechselrichterwerte werden im eingestellten Interval abgefragt, manual = Abfrage nur mit "get &lt;name&gt; data" </li>
  <li><b>offset</b>           : Zeit in Sekunden um die der Sonnenaufgang vorgezogen bzw. Sonnenuntergang verzögert wird (0 ... 7200). Dadurch wird die 
                                effektive Aktivzeit des Moduls erweitert.  </li>
  <li><b>suppressSleep</b>    : der Schlafmodus (nach Sonnenuntergang, vor Sonnenaufgang) wird ausgeschaltet und der WR abgefragt.  </li>
  <li><b>showproctime</b>     : zeigt die für den Hintergrundprozess und die Abfrage des Wechselrichter verbrauchte Zeit.  </li>
  <li><b>SBFSpotComp</b>      : 1 = die Readings werden kompatibel zu SBFSpot-Ausgaben erzeugt </li>
  <li><b>target-susyid</b>    : Im Falle eines Multigate kann die Ziel-SUSyID definiert werden. Ist mehr als ein Wechselrichter installiert,
                                muß die Wechselreichter-SUSyID gesetzt werden um den Wechselrichter der Device-Definition eindeutig zuzuweisen.
							    Default ist 0xFFFF (=keine Einschränkung)</li>
  <li><b>target-serial</b>    : Im Falle eines Multigate kann die Ziel-Seriennummer definiert werden. Ist mehr als ein Wechselrichter installiert,
                                muß die Wechselreichter-Seriennummer gesetzt werden um den Wechselrichter der Device-Definition eindeutig zuzuweisen.
								Default ist 0xFFFFFFFF (=keine Einschränkung)</li>
  <li><b>timeout</b>          : Einstellung des timeout für die Wechselrichterabfrage (default 60s) </li>  
</ul>

<b>Readings</b>
<ul>
<li><b>BAT_CYCLES / bat_cycles</b>          :  Akku Ladezyklen </li>
<li><b>BAT_IDC / bat_idc</b>                :  Akku Strom </li>
<li><b>BAT_TEMP / bat_temp</b>              :  Akku Temperatur </li>
<li><b>BAT_UDC / bat_udc</b>                :  Akku Spannung </li>
<li><b>ChargeStatus / chargestatus</b>      :  Akku Ladestand </li>
<li><b>CLASS / device_class</b>             :  Wechselrichter Klasse </li>
<li><b>PACMAX1 / pac_max_phase_1</b>        :  Nominelle Leistung in Ok Mode </li>
<li><b>PACMAX1_2 / pac_max_phase_1_2</b>    :  Maximale Leistung (für einige Wechselrichtertypen) </li>
<li><b>PACMAX2 / pac_max_phase_2</b>        :  Nominelle Leistung in Warning Mode </li>
<li><b>PACMAX3 / pac_max_phase_3</b>        :  Nominelle Leistung in Fault Mode </li>
<li><b>Serialnumber / serial_number</b>     :  Wechselrichter Seriennummer </li>
<li><b>SPOT_ETODAY / etoday</b>             :  Energie heute</li>
<li><b>SPOT_ETOTAL / etotal</b>             :  Energie Insgesamt </li>
<li><b>SPOT_FEEDTM / feed-in_time</b>       :  Einspeise-Stunden </li>
<li><b>SPOT_FREQ / grid_freq.</b>           :  Netz Frequenz </li>
<li><b>SPOT_IAC1 / phase_1_iac</b>          :  Netz Strom phase L1 </li>
<li><b>SPOT_IAC2 / phase_2_iac</b>          :  Netz Strom phase L2 </li>
<li><b>SPOT_IAC3 / phase_3_iac</b>          :  Netz Strom phase L3 </li> 
<li><b>SPOT_IDC1 / string_1_idc</b>         :  DC Strom Eingang 1 </li>
<li><b>SPOT_IDC2 / string_2_idc</b>         :  DC Strom Eingang 2 </li>
<li><b>SPOT_OPERTM / operation_time</b>     :  Betriebsstunden </li>
<li><b>SPOT_PAC1 / phase_1_pac</b>          :  Leistung L1  </li>
<li><b>SPOT_PAC2 / phase_2_pac</b>          :  Leistung L2  </li>
<li><b>SPOT_PAC3 / phase_3_pac</b>          :  Leistung L3  </li>
<li><b>SPOT_PACTOT / total_pac</b>          :  Gesamtleistung </li>
<li><b>SPOT_PDC1 / string_1_pdc</b>         :  DC Leistung Eingang 1 </li>
<li><b>SPOT_PDC2 / string_2_pdc</b>         :  DC Leistung Eingang 2 </li>
<li><b>SPOT_UAC1 / phase_1_uac</b>          :  Netz Spannung phase L1 </li>
<li><b>SPOT_UAC2 / phase_2_uac</b>          :  Netz Spannung phase L2 </li>
<li><b>SPOT_UAC3 / phase_3_uac</b>          :  Netz Spannung phase L3 </li>
<li><b>SPOT_UDC1 / string_1_udc</b>         :  DC Spannung Eingang 1 </li>
<li><b>SPOT_UDC2 / string_2_udc</b>         :  DC Spannung Eingang 2 </li>
<li><b>SUSyID / susyid</b>                  :  Wechselrichter SUSyID </li>
<li><b>INV_TEMP / device_temperature</b>    :  Wechselrichter Temperatur </li>
<li><b>INV_TYPE / device_type</b>           :  Wechselrichter Typ </li>
<li><b>POWER_IN / power_in</b>              :  Akku Ladeleistung </li>
<li><b>POWER_OUT / power_out</b>            :  Akku Entladeleistung </li>
<li><b>INV_GRIDRELAY / gridrelay_status</b> :  Netz Relais Status </li>
<li><b>INV_STATUS / device_status</b>       :  Wechselrichter Status </li>
<li><b>opertime_start</b>                   :  Beginn Aktivzeit des Wechselrichters entsprechend des ermittelten Sonnenaufgangs mit Berücksichtigung des 
                                               Attributs "offset" (wenn gesetzt) </li>
<li><b>opertime_stop</b>                    :  Ende Aktivzeit des Wechselrichters entsprechend des ermittelten Sonnenuntergangs mit Berücksichtigung des 
                                               Attributs "offset" (wenn gesetzt) </li>
<li><b>modulstate</b>                       :  zeigt den aktuellen Modulstatus "normal" oder "sleep" falls der Wechselrichter nicht abgefragt wird. </li>
<li><b>avg_power_lastminutes_05</b>         :  durchschnittlich erzeugte Leistung der letzten 5 Minuten. </li>	
<li><b>avg_power_lastminutes_10</b>         :  durchschnittlich erzeugte Leistung der letzten 10 Minuten. </li>	
<li><b>avg_power_lastminutes_15</b>         :  durchschnittlich erzeugte Leistung der letzten 15 Minuten. </li>	
<li><b>inverter_processing_time</b>         :  verbrauchte Zeit um den Wechelrichter abzufragen. </li>
<li><b>background_processing_time</b>       :  gesamte durch den Hintergrundprozess (BlockingCall) verbrauchte Zeit. </li>	
							   
</ul>
<br><br>

=end html_DE

=cut
