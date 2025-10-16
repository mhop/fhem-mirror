########################################################################################
#
#  Shelly.pm
#
#  FHEM module to communicate with Shelly switch/roller actor devices
#  Prof. Dr. Peter A. Henning, 2022    (v. 4.02f, 3.9.2022)
#  $Id$
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

# 5.01      attr defchannel for single mode devices with multiple relays (eg Shelly4Pro)
#           improved support for wall display
#           Bug Fix: Shelly_onoff (causing delays)
#           added wifi data to Gen.1 devices
#           Bug Fix: inttemp for ShellyPro2
# 5.02      Bug Fix: on/off-for-timer for ShellyPlus2 temporarely taken out
# 5.03      Bug Fix: Refresh: removed fixed name of FHEMWEB device
#           Bug Fix: Gen.2: on/off-for-timer
#           Bug Fix: update interval of GetStatus call
# 5.04      Bug Fix: undefined values on restart
#           Energymeter activated
# 5.05      Bug Fix: Begin/End-Update in sub ()
# 5.06      Bug Fix: undefined value for ShellyPMmini and others
#           Change: Model of ShellyPMmini changed to shellypmmini
# 5.07      BugFix: shellyrgbw (white mode): set ... toggle
# 5.08      Add: set ... ON and OFF to switch all channels of a multichannel device
#           Change: set default of MaxAge to 600 hrs
#           Change: remove attribute 'ShellyName', use 'set ... name' instead
#           Bug Fix: misc. 'undefined value'
#           internal Optimization of Shelly_Set()
# 5.09      Bug Fix (dimmer-devices): set..pct will not turn on or off
#           Add (dimmer-devices): set..dim will turn on or off
# 5.10      Add (dimmer-devices): set..dimup / dimdown
#           Add (sensor-addon): temperatures
# 5.11      internal reorganisation of status calls
#           internal optimization of webhook handling
#           Bug Fix: dimmer: settings call set to lights
#           Feature: ShellyPro3EM attribute Balancing
# 5.12      Add Gen3 Mini devices (fw gen2 compatibility)
#           Add: Roller devices: use 'set ... pos' equivalent to 'pct'
#           Add (dimmer-devices): set..dim-for-timer
#           Bug Fix: store newkeys in helper after init
# 5.13      Bug Fix: handling of attr 'shellyuser' for gen2 devices
# 5.14      Add: set ... reset to set counters to zero
#           Bug Fix: rollers (gen2 only): numberof power related readings
# 5.15      change cmdref to attr ... model
# 5.16      Bug Fix: function of dimmer
# 5.17      Add: Roller devices: 'set ... position' equivalent to 'pct'
# 5.18      Bug Fix: function of all Gen1 relay devices
# 5.19      change back: roller devices: use 'set ... pct' as command
# 5.20      Bug Fix: suppress status calls for disabled devices
# 5.21      Bug Fix: Shelly-dimmer: convert dim-command with brightness=0 to an off-command
#           Bug Fix: Shelly-dimmer, Shelly-bulb: slider for pct starts with 1
# 5.21.1    Bug Fix: $oldtimer removed
# 6.00 beta 1      Internal optimization HTTP-communication, use of timers, optimization of lights-devices procedure, minor bug fixes
#           ShellyRGBW: using effects
#           added: set extensions
#           added: shellyplusUni / in work
#           fix: do not loose timer on other commands or retriggering
#           new devices: Shelly Plus 0-10V Dimmer, Shelly Pro Dimmer, Shelly Plus Uni
#           Add: range extender
#           Change: control of actions now by set commands; attribute webhook is only used to set the correspondending FHEMWEB-Device.
#           Add: BLE.CloudRelay.List
#           open issues:  shellypro3em not running properly
# 6.00 Beta_2      ShellyPro3EM: reading 'errors' changed to 'error_EM', interval for power values setable separately, fixed total reactive power
#           removed reading 'timestamp'
#           increase interval in case of network error, reset when reconnected
#           added: commands 'set config ap_enable|ap_disable' to change access point of Gen2 devices
#           reading 'state' is set to 'disabled' when interval is set to 0
#           reading 'network_threshold' moved to 'network_wifi_roaming', may be set to 'disabled'
#           internal 'SHELLY' moved to reading 'model_ID'; according new readings model_family, model_function, model_name
#           new gen3 models
#           added: reading 'energy_returned' & 'energy_purchased' for Plus&Pro devices with PM
#           changed: reading 'firmware' with hint 'check internet' when device seems not to have internet connection
# 6.00 Beta_3 fix: dimmable devices: command allowed 'set <device> pct 0' to switch off the device
#           added:  humidity, input and voltmeter to Shelly Plus Addon;
#           changed:readings name of analog input of Shelly Plus Uni will be renamed
#           added:  definition of the device by DNS-name instead of ip-address, new reading 'network_ip-address' with the ip-address of the device
#                   Pro devices only: separate readings, indexed by 'LAN' resp. 'Wifi'
#           added:  new reading 'ap_clients_<nr>_model' with the model of the connected Shelly device (when connection via range extender is established)
#           changed:  command 'set <name> reset <reading>' changed to 'set ... clear ...'
#           added:  readings timer... are supported for shelly4pro (gen1)
# 6.00 Beta_4  add: client without definition --> reading 'no definition'
#           new: attr timeout controls write out readings with response times
# 6.00      fix some details in commandref (german only)
# 6.00.1    fix: selection of readings for command 'set clear responsetimes' improved; Debug commands removed
# 6.00.2    fix: reading ble (bluetooth) may be set to disabled
# 6.00.3    fix: use Sub::Util added
# 6.00.4    fix: removed the use of Sub::Util
# 6.00.5    fix: removed irrelevant log-entries for dimmer
# 6.01 Beta_1  redesign of scheduled status updates and write out of reading /_nextUpdateTimer
#           added:  readings auto_on/off to Gen2-relay-devices
#           fix: firmware check, new readings, reading 'firmware' removed, introduced 'traffic-signs' for firmware-status
#           new: command 'get ... rgShellyFirmware|rgShellyNetwork' to create a readingsGroup device
#           new: readings 'network_connection' (online/offline) and 'network_host' (if connected to another Shellies ap)
#           change: name of access-point moved from reading 'ap' to new reading 'ap_name'
#           fix: restart timer in case of network error
#           new: maxtime values of rollers are synchronized between fhem-device and the shelly ////gen2 only
# 6.01      fix initiliasation error on disabled devices (polling interval=0)
#           fix: readout of EM-Data at wrong times when interval is set greater than 60sec.
#           add: name of Shelly to readingsGroup 'Device'
#           fix: attr room of readingsGroup 
#           add: number of controlled URLs and total number of URLs added to reading 'webhook_cnt'
#           change: use 'blank' sign instead of removing '%20' when displaying actions urls
#           change: on updating action query strings, substitue spaces by '+' sign, instead of %20 (Shelly fw replace %20 by space)
#           fix: removed lost '&' when webhooks changed to have no csrf token
# 6.01.1    fix: division by zero when attr Periods is not set at ShellyPro3EM 
# 6.01.2    add: Shelly Plug S MTR Gen3
# 6.01.3    fix: bad firmware identification
#           add: reading 'firmware_ID' (Gen2)
# 6.01.4    fix: use of defined-or operator
# 6.01.5    add: reading 'temperature' for ShellyPlusUni 
# 6.02 Beta1 add: reading 'model_function' for Gen1-devices
#           add: auto-run 'getModel' if some readings are not present
#           add: ShellyEM Energy Meter reading ct_type
#           add: ShellyEM50
#           improved: validity check in definition
#           add: reading 'network_DNS' to represent the DNS-name of the device
#           improved readings 'temperature' for ShellyPlusUni
#           improved readings for input/counter for ShellyPlusUni
# 6.02 Beta2 fix: do not reset timer after *-for-timer 
#           fix: handling of old timer on retriggering
#           add: add check for (new) beta for gen2 with fw=beta
#           internal change: moved energy-format to updater sub
# 6.02 Beta3 new: attribute host_ip to be used instead of "hostname --all-ip-addresses" [hugomckinley]
#           fix: no energy readings available on ShellyPlusRGBWpm if NoLoad on channel  [GerhardJ]
#           fix: cannot clear energy on ShellyPMMini devices [edition]
#           new: set commands for multichannel roller device [bmwfan]
#           new: set commands for wall display thermostat (experimental)
#           removed:  command get ... shelly_status (deprecated since 6/24)
# 6.02 Beta4 fix: reading state of ShellyEM50
# 6.02      fix: command "set <name> button_on" w/o channel
# 6.02.1    fix: update of input/output readings
# 6.02.2    fix: update interval if interval is set to 0
#           new: slat control für rollers Gen2+
# 6.02.3    fix: setting of attribute slat_control
# 6.02.4    fix: checking os regarding command hostname
# 6.03      new: commands script_start, script_stop
#           fix: recognition of ShellyI4Gen3
# 6.03.1    change of some log levels
# 6.03.2    new: some new devices gen4/mini and others
#           fix: Gen2-energy-meter: incomplete dropdown for attribute 'showunits'
#           fix: Gen2-energy-meter: missing reading ct_type
# 6.03.3    fix: number of channels of ShellyProEM50
#           fix: init of EM-Devices
#           add: errors in authentication
# 6.04      fix: loglevel of firmwarecheck
#           fix: model reference of Shelly3EM
#           new: commands for PLUGS_UI implemented
# 6.04.1    new: improved commands for PLUGS_UI
#           fix: update interval of energy readings (Gen2 energy meter)
# 6.04.2    new: Shelly shutter added
# 6.04.3    new: Shelly Pro2 UL-type added
#           fix: do not set gain to 100% on set hsv|rgb. 

# to do     new: periods Month and Year for energymeter
# to do     roller: get maxtime open/close from shelly gen1
#           get status on stopp even when interval == 0

# outstanded readings, to be deleted:  firmware, firmware_beta, source_, state_, timer_
package main;

use strict;
use warnings;
use 5.10.0;     # defined-or

use JSON;
use HttpUtils;
use SetExtensions;
use Socket;     # gethostbyname() gethostbyaddr() ...

use vars qw{%attr %defs};

sub Log($$);
sub Shelly_Set ($@);
sub Shelly_status(@);

#-- globals on start
my $version = "6.04.3 16.10.2025";

my $defaultINTERVAL = 60;
my $multiplyIntervalOnError = 1.0;   # mechanism disabled if value=1

my %shelly_firmware = (  # latest known versions  # as of 29.08.2024
    # used by sub Shelly_firmwarecheck
    "gen1"        => "1.14.0",   # v1.14.1-rc1
    "shelly4"     => "1.6.6",
    "gen2"        => "1.7.0",  
    "walldisplay" => "2.3.6"
    );

#-- Time slices in seconds for time zone Germany CET/CEST
#              [offset dst==0, offset dst==1, periode length]
my %periods = (
   "min"    => [0,0,60],
   "hourT"  => [0,0,300],	           # twelth of an hour (5 minutes)
   "hourQ"  => [0,0,900],	           # quarter of an hour
   "hour"   => [0,0,3600],
   "dayQ"   => [3600,7200,21600],          #  day quarter
   "dayT"   => [10800,14400,28800],        #  day third  =  3x8h:   06:00 -  14:00  -  22:00
   "day"    => [3600,7200,86400],
   "Week"   => [-342000,-338400,604800],    # offset=-4x24x3600 + 3600 + $isdst x 3600
   "Month"  => [0,0,0],
   "Year"   => [0,0,0]    # len=365x24x3600=31536000  +  is_schaljahr x 24x3600
);

my %attributes = (
  "modes"         => " mode:relay,roller,white,color",
  "multichannel"  => " defchannel",
  "roller"        => " pct100:open,closed maxtime maxtime_close maxtime_open slat_control slat_pos",
  "dimmer"        => " dimstep",
  "input"         => " showinputs:show,hide",
  "emeter"        => " Energymeter_F Energymeter_P Energymeter_R EMchannels:ABC_,L123_,_ABC,_L123".
                     " PeriodsCorr-F Balancing:0,1 interval_power",
  "emPeriods"     => " Periods:multiple-strict,Week,day,dayT,dayQ,hour,hourQ,hourT,min",   #   Year,Month,
                                        # @keys = keys %periods   descending order is used by Shelly_procEnergyData()
  "metering"      => " maxpower",
  "showunits"     => " showunits:none,original,normal,normal2,ISO"
);

my %shelly_dropdowns = (
#-- these we may get on request
    "Gets"    => "status:noArg settings:noArg registers:noArg config version:noArg model:noArg actions:noArg readingsGroup:Device,Firmware,Network,Status",
    "Colors"  => " colors:noArg",
#-- these we may set
    "Shelly"  => "config interval password reboot:noArg update:noArg name clear:disconnects,error,energy,responsetimes",
    "Actions" => " actions",  # create,delete,disable,enable,update
    "Scripts" => " script_start script_stop",
    "Onoff"   => " on off toggle on-for-timer off-for-timer",## on-till off-till on-till-overnight off-till-overnight blink intervals",
    "Multi"   => " ON:noArg OFF:noArg xtrachannels:noArg",
    "Rol"     => " closed open stop:noArg pct:slider,0,1,100 delta zero:noArg predefAttr:noArg",
    "RgbwW"   => " pct:slider,1,1,100 dim dimup dimdown dim-for-timer",   ## later we add calibrate for shellydimmer
    "BulbW"   => " ct:colorpicker,CT,3000,10,6500 pct:slider,1,1,100",
    "RgbwC"   => " rgbw rgb:colorpicker,HSV hsv white:slider,0,1,100 gain:slider,0,1,100 effect:select,Off,1,2,3",
    "Input"   => " input:momentary,toggle,edge,detached,activation", 
    "Input1"  => ",momentary_on_release",  # only Shelly1
    "Input2"  => ",cycle",                  # only ShellyPlus2
    "PlugsUI" => " colorsOn colorsOff",       # only Shelly Plugs Gen2+
    "Therm"   => " target, thermostat_type:heating,cooling thermostat_output:straight,invert"    # Wall display thermostat target temperature °C
);
## may be used for RgbwC:
##  "hsv:colorpicker,HSV"
##  "rgb:colorpicker,RGB"
##  "white:colorpicker,BRI,0,1,255"

# Device model by https://kb.shelly.cloud/knowledge-base/
# Device name as given by KB listed as comment
my %shelly_vendor_ids = (
    # keys: 'Device model' as in KB Device identification
    # value 0:  the 'model' attribute used by the Fhem
    # value 1:  the 'Device name' as in KB 
    # value 2:  the 'Device Bluetooth ID', Gen3 only
    ## Gen1 devices
    "SHSW-1"     => ["shelly1",        "Shelly 1"],   ## no power metering
    "SHSW-PM"    => ["shelly1pm",      "Shelly 1PM"],
    "SHSW-L"     => ["shelly1L",       "Shelly 1L"],  ## with AC power metering
    "SHSW-21"    => ["shelly2",        "Shelly 2"],   ## not listed in KB
    "SHSW-25"    => ["shelly2.5",      "Shelly 2.5"],
    "SHSW-44"    => ["shelly4",        "Shelly 4 Pro"],      ## not listed in KB
    "SHIX3-1"    => ["shellyi3",       "Shelly i3"],
    "SHEM"       => ["shellyem",       "Shelly EM"],
    "SHEM-3"     => ["shelly3em",      "Shelly 3EM"],
    "SHUNI-1"    => ["shellyuni",      "Shelly Uni"],
    "SHSTRV-01"  => ["generic",        "Shelly TRV"],
    "SHBTN-1"    => ["generic",        "Shelly Button 1"],
    "SHBTN-2"    => ["generic",        "Shelly Button 2"],   ##  not listed in KB
    "SHPLG2-1"   => ["shellyplug",     "Shelly Plug"],
    "SHPLG-S"    => ["shellyplug",     "Shelly Plug S"],
    "SHPLG-US"   => ["shellyplug",     "Shelly Plug US"],    ##  check device model >SHPLG-US<
    "SHRGBW2"    => ["shellyrgbw",     "Shelly RGBW2"],
    "SHDM-1"     => ["shellydimmer",   "Shelly Dimmer 1"],   ## not listed in KB
    "SHDM-2"     => ["shellydimmer",   "Shelly Dimmer 2"],

    "SHBDUO-1"   => ["shellybulb",     "Shelly Duo/Duo GU10"],  ## dimmable white (WW/CW) light with submodels: E27 or GU10 fitting
    "SHVIN-1"    => ["shellybulb",     "Shelly Vintage"],       ## dimmable white light with different fittings
    "SHBLB-1"    => ["shellybulb",     "Shelly Bulb"],          #
    "SHCB-1"     => ["shellybulb",     "Shelly Duo RGBW G10"],  # = shelly color bulb   submodels: E27, GU10

    "SHHT-1"     => ["generic",        "Shelly H&T"],           ## humidity and temperature sensor
    "SHWT-1"     => ["generic",        "Shelly Flood"],         ## flood sensor
    "SHDW-1"     => ["generic",        "Shelly Door/Window"],   ## not listed in KB
    "SHDW-2"     => ["generic",        "Shelly Door/Window 2"],
    "SHGS-1"     => ["generic",        "Shelly Gas"],           ## gas sensor
    "SHSM-1"     => ["generic",        "Shelly Smoke"],         ## smoke sensor ## not listed in KB
    "SHMOS-01"   => ["generic",        "Shelly Motion"],        ## motion sensor
    "SHMOS-02"   => ["generic",        "Shelly Motion 2"],      ## motion sensor 2
    "SHSEN-1"    => ["generic",        "Shelly motion & ir-controller"],  ## not listed in KB
    ## Plus devices  ## 2nd Gen
    "SNSW-001X16EU" => ["shellyplus1",      "Shelly Plus 1"],
    "SNSW-001P16EU" => ["shellyplus1pm",    "Shelly Plus 1PM"],
    "SNSW-001P15UL" => ["shellyplus1pm",    "Shelly Plus 1PM UL"],  ## new
    "SNSW-002P16EU" => ["shellyplus2pm",    "Shelly Plus 2PM"],
    "SNSW-102P16EU" => ["shellyplus2pm",    "Shelly Plus 2PM"],     ## 102 ?? not more listed in KB
    "SNSW-002P15UL" => ["shellyplus2pm",    "Shelly Plus 2PM UL"],  ## new
    "SNSN-0024X"    => ["shellyplusi4",     "Shelly Plus i4"],      ## AC operated
    "SNSN-0D24X"    => ["shellyplusi4",     "Shelly Plus i4DC"],
    "SNSN-0013A"    => ["generic",          "Shelly Plus H&T"],     ## temp&humidity sensor
    "SNPL-00110IT"  => ["shellyplusplug",   "Shelly Plus Plug IT"], ## italian style
    "SNPL-00112EU"  => ["shellyplusplug",   "Shelly Plus Plug S V1"], ## german style
    "SNPL-10112EU"  => ["shellyplusplug",   "Shelly Plus Plug S V2"], ## german style  V2
    "SNPL-00112UK"  => ["shellyplusplug",   "Shelly Plus Plug UK"],   ## UK style
    "SNPL-00116US"  => ["shellyplusplug",   "Shelly Plus Plug US"],   ## US style
    "SNSN-0031Z"    => ["generic",          "Shelly Plus Smoke"],
    "SNDM-0013US"   => ["generic",          "Shelly Plus Wall Dimmer"],  ##
    "SNSN-0043X"    => ["shellyplusuni",    "Shelly Plus Uni"],
    "SNDM-00100WW"  => ["shellyplus010v",   "Shelly Plus 0-10V Dimmer"],
    "SNDC-0D4P10WW" => ["shellyplusrgbwpm", "Shelly Plus RGBW PM"],  ##new
    ## Mini Devices
    "SNSW-001X8EU"    => ["shellyplus1",    "Shelly Plus 1 Mini"],
    "SNSW-001P8EU"    => ["shellyplus1pm",  "Shelly Plus 1PM Mini"],
    "SNPM-001PCEU16"  => ["shellypmmini",   "Shelly Plus PM Mini"],
    ## Gen3 Devices
    "S3SW-001X16EU"   => ["shellyplus1",    "Shelly 1 Gen3",           0x1018],   ##new
    "S3SW-001P16EU"   => ["shellyplus1pm",  "Shelly 1PM Gen3",         0x1019],   ##new
    "S3SW-002P16EU"   => ["shellyplus2pm",  "Shelly 2PM Gen3",         0x1005],   # added 10/2024
    "S3SN-0024X"      => ["shellyplusi4",   "Shelly i4 Gen3",          0x1812],   ## (AC), new
    "S3SN-0U12A"      => ["generic",        "Shelly H&T Gen3",         0x1809],   ## new, not yet implemented
    "S3DM-0010WW"     => ["shellyplus010v", "Shelly Dimmer 0/1-10V PM Gen3",0x1072], ## new
    "S3PL-00112EU"    => ["shellyplusplug", "Shelly Plug S MTR Gen3",  0x1805],   # added 10/2024
    "S3DM-0A101WWL"   => ["shellyprodm1pm", "Shelly Dimmer Gen3",      0x1073],   # added 01/2025
    "S3DM-0A1WW"      => ["generic",        "Shelly DALI Dimmer Gen3", 0x1071],   # added 10/2024
    "S3EM-002CXCEU"   => ["shellyemG3",     "Shelly EM Gen3",          0x1027],   # added 10/2024
    "S3EM-003CXCEU63" => ["shelly3emG3",    "Shelly 3EM 63 Gen3",      0x1026],   # added 01/2025    
    "S3PL-10112EU"    => ["shellyplusplug", "Shelly AZ Plug",          0x1850],   # added 01/2025  amazon compatible
    "S3PL-20112EU"    => ["shellyplusplug", "Shelly Outdoor Plug S Gen3",0x1853],   # added 02/2025
    "S3SH-0A2P4EU"    => ["shellyshutter",  "Shelly Shutter",          0x1039],   # added 09/2025
    ## Mini Gen3 Devices
    "S3SW-001X8EU"    => ["shellyplus1",    "Shelly 1 Mini Gen3",      0x1015],
    "S3SW-001P8EU"    => ["shellyplus1pm",  "Shelly 1PM Mini Gen3",    0x1016],
    "S3PM-001PCEU16"  => ["shellypmmini",   "Shelly PM Mini Gen3",     0x1023],
    ## Gen4 Devices
    "S4SW-001X16EU"   => ["shellyplus1",    "Shelly 1 Gen4",           0x1028],   # added 03/2025
    "S4SW-001P16EU"   => ["shellyplus1pm",  "Shelly 1PM Gen4",         0x1019],   # added 03/2025
    ## Mini Gen4 Devices
    "S4SW-001X8EU"    => ["shellyplus1",    "Shelly 1 Mini Gen4",      0x1030],   # added 03/2025
    "S4SW-001P8EU"    => ["shellyplus1pm",  "Shelly 1PM Mini Gen4",    0x1031],   # added 03/2025
    "S4EM-001PXCEU16" => ["shellyemmini",   "Shelly EM Mini Gen4",     0x1033],   # added 03/2025
    ## 2nd Gen PRO devices
    "SPSW-001XE16EU"  => ["shellypro1",     "Shelly Pro 1"],      ## not listed by KB
    "SPSW-201XE16EU"  => ["shellypro1",     "Shelly Pro 1 v.1"],
    "SPSW-001PE16EU"  => ["shellypro1pm",   "Shelly Pro 1PM"],    ## not listed by KB
    "SPSW-201PE16EU"  => ["shellypro1pm",   "Shelly Pro 1PM v.1"],
    "SPSW-002XE16EU"  => ["shellypro2",     "Shelly Pro 2"],      ## not listed by KB
    "SPSW-202XE16EU"  => ["shellypro2",     "Shelly Pro 2 v.1"],
    "SPSW-002PE16EU"  => ["shellypro2pm",   "Shelly Pro 2PM"],    ## not listed by KB
    "SPSW-202PE16EU"  => ["shellypro2pm",   "Shelly Pro 2PM v.1"],
    "SPSH-002PE16EU"  => ["shellyprodual",  "Shelly Pro Dual Cover/Shutter PM"],
    "SPCC-001PE10EU"  => ["shellyplus010v", "Shelly Pro Dimmer 0/1-10V PM",   0x2011],    # addes 03/2025  <<< 1V base not supported here
    "SPDC-0D5PE16EU"  => ["shellyplusrgbwpm", "Shelly Pro RGBWW PM",  0x2012],    # added 02/2025  <<<< two channels of White not supported here
    "SPDM-001PE01EU"  => ["shellyprodm1pm", "Shelly Pro Dimmer 1PM",  0x200D],    ##new
    "SPDM-002PE01EU"  => ["shellyprodm2pm", "Shelly Pro Dimmer 2PM",  0x200E],
    "SPSW-003XE16EU"  => ["shellypro3",     "Shelly Pro 3"],
    "SPEM-003CEBEU"   => ["shellypro3em",   "Shelly Pro 3EM"],
    "SPEM-003CEBEU400"=> ["shellypro3em",   "Shelly Pro 3EM-400"],
    "SPEM-003CEBEU63" => ["shellypro3em",   "Shelly Pro 3EM-3CT63"],
    "SPEM-002CEBEU50" => ["shellyproem50",  "Shelly Pro EM-50"],
    "SPSW-004PE16EU"  => ["shellypro4pm",   "Shelly Pro 4PM V1"],
    "SPSW-104PE16EU"  => ["shellypro4pm",   "Shelly Pro 4PM V2"],
    # Android Devices / Control Panels
    "SAWD-0A1XX10EU1" => ["walldisplay1",   "Shelly Wall Display"], ## prelim version ?  ## not listed by KB
    "SAWD1"           => ["walldisplay1",   "Shelly Wall Display"],
    "SAWD-2A1XX10EU1" => ["walldisplay1",   "Shelly Wall Display", 0x3002],   # added 03/2025
    # UL-Types
    "SPSW-202XE12UL"  => ["shellypro2",     "Shelly Pro 2 v.1"]          # added 10/2025, not listed by KB
    );

my %shelly_family = (
    # family code as given in first two characters of family-id
     "SH" => "Gen1",
     "SN" => "Plus/Gen2",
     "DC" => "LED driverGen3",
     "SP" => "Pro/Gen2",
     "SA" => "Control Panel",
     "S3" => "Gen3"
     );

my %shelly_category = (
    # code as given in characters 3 & 4 of family-id 
    # Gen1 - devices 
     "BD" => "bulb",             # BDUO
     "CB" => "bulb",             # CB - color bulb
     "IX" => "sensor",           # IX3
     "RG" => "LED controller",   # RGBW2
    # Gen1 & Gen2+ - devices
     "SW" => "switch",
    # Gen2+ - devices)
     "DC" => "LED driver",
     "DM" => "dimmer",
     "EM" => "energy meter",
     "PL" => "plug",
     "PM" => "power meter",
     "SH" => "shutter",
     "SN" => "sensor",
     "WD" => "wall display"
    );


my %shelly_models = (
    #(   0      1       2         3    4    5       6    7     8)
    #(relays,rollers,dimmers,  meters, NG,inputs,  EM1,color,modes)
    "generic"       => [0,0,0, 0,0,0,  0,0,0],
    "shellyi3"      => [0,0,0, 0,0,3,  0,0,0],    # 3 inputs
    "shelly1"       => [1,0,0, 0,0,1,  0,0,0],    # not metering, only a power constant in older fw
    "shelly1L"      => [1,0,0, 1,0,1,  0,0,0],
    "shelly1pm"     => [1,0,0, 1,0,1,  0,0,0],
    "shelly2"       => [2,1,0, 1,0,2,  0,0,2],    # relay mode, roller mode
    "shelly2.5"     => [2,1,0, 2,0,2,  0,0,2],    # relay mode, roller mode
    "shellyplug"    => [1,0,0, 1,0,-1, 0,0,0],    # shellyplug & shellyplugS;   no input, but a button which is only reachable via Action
    "shelly4"       => [4,0,0, 4,0,4,  0,0,0],    # shelly4pro;  inputs not provided by fw v1.6.6
    "shellyrgbw"    => [0,0,4, 4,0,1,  0,1,2], #!!   # shellyrgbw2:  color mode, white mode; metering col 1 channel, white 4 channels
    "shellydimmer"  => [0,0,1, 1,0,2,  0,0,0],
    "shellyem"      => [1,0,0, 2,0,0,  0,0,0],    # with one control-relay, consumed energy in Wh
    "shelly3em"     => [1,0,0, 3,0,0,  0,0,0],    # with one control-relay, consumed energy in Wh
    "shellybulb"    => [0,0,1, 1,0,0,  0,1,2],    # shellybulb & shellybulbrgbw:  color mode, white mode;  metering is in any case 1 channel
    "shellyuni"     => [2,0,0, 0,0,2,  0,0,0],    # + analog dc voltage metering
    #-- 2nd generation devices
    "shellyplusplug"=> [1,0,0, 1,1,0,  0,0,0],    # has a button, that is NOT reachable via action
    "shellypluspm"  => [0,0,0, 1,1,0,  0,0,0],
    "shellyplus1"   => [1,0,0, 0,1,1,  0,0,0],
    "shellyplus1pm" => [1,0,0, 1,1,1,  0,0,0],
    "shellyplus2pm" => [2,1,0, 2,2,2,  0,0,2],    # switch profile, cover profile
    "shellyplusuni" => [2,0,0, 0,1,2,  0,0,0],    ### entwurf wie shellypro2; 1 xtra input as counter
    "shellyplus010v"=> [0,0,1, 0,2,2,  0,0,0],    # one instance of light, 0-10V output
    "shellyplusi4"  => [0,0,0, 0,1,4,  0,0,0],
    "shellyplusrgbwpm"=>[0,0,4,4,2,4,  0,1,2],
    "shellypro1"    => [1,0,0, 0,1,2,  0,0,0],
    "shellypro1pm"  => [1,0,0, 1,1,2,  0,0,0],
    "shellypro2"    => [2,0,0, 0,1,2,  0,0,0],
    "shellypro2pm"  => [2,1,0, 2,1,2,  0,0,2],    # switch profile, cover profile
    "shellypro3"    => [3,0,0, 0,1,3,  0,0,0],    # 3 potential free contacts
    "shellypro4pm"  => [4,0,0, 4,1,4,  0,0,0],
    "shellyprodm1pm"=> [0,0,1, 1,2,2,  0,0,0],    # 1 dimmer with 2 inputs
    "shellyprodm2pm"=> [0,0,2, 2,2,4,  0,0,0],    # 2 dimmer with each 2 inputs
    "shellyproem50" => [1,0,0, 0,1,0,  2,0,0],    # has two single-phase meter and one relay
    "shellypro3em"  => [0,0,0, 0,1,0,  3,0,2],    # has 1 three-phase meter [EM] in triphase profile or 3 meter [EM1] in monophase-profile
    "shellyprodual" => [0,2,0, 4,1,4,  0,0,0],
    #-- 3rd generation devices (Gen3)
    "shellypmmini"  => [0,0,0, 1,1,0,  0,0,0],    # similar to ShellyPlusPM
    "shellyemG3"    => [1,0,0, 0,3,0,  2,0,0],    # similar to 'shellyproem50'
    "shelly3emG3"   => [0,0,0, 0,3,0,  3,0,2],    # similar to 'shellypro3em'
    #-- 4nd generation devices (Gen4)
    "shellyemmini"  => [0,0,0, 1,1,0,  0,0,0],    # similar to 'shellypmmini'    EM1 or PM1 ?
    #-- Android devices
    "walldisplay1"  => [1,0,0, 0,2,1,  0,0,0],     # similar to ShellyPlus1PM
    #-- 3rd generation devices (not covered by plus or pro devices)
    "shellyshutter" => [0,1,0, 2,1,2,  0,0,0]     # similar to shellyPlus2PM, but without multimode
    );

my %shelly_events = (	# events, that can be used by webhooks; key is mode, value is shelly-event
        #Gen1 devices
    "generic"       => [""],
    "shellyi3"      => ["btn_on_url","btn_off_url","shortpush_url","longpush_url",
                        "double_shortpush_url","triple_shortpush_url","shortpush_longpush_url","longpush_shortpush_url"],
    "shelly1"       => ["btn_on_url","btn_off_url","longpush_url","shortpush_url","out_on_url","out_off_url"],
    "shelly1L"      => ["btn1_on_url","btn1_off_url","btn1_longpush_url","btn1_shortpush_url",
                        "btn2_on_url","btn2_off_url","btn2_longpush_url","btn2_shortpush_url","out_on_url","out_off_url"],
    "shelly1pm"     => ["btn_on_url","btn_off_url","out_on_url","out_off_url","longpush_url","shortpush_url","lp_on_url","lp_off_url"],
    "shelly2"       => ["btn_on_url","btn_off_url","longpush_url","shortpush_url","out_on_url","out_off_url",
                        "roller_open_url","roller_close_url","roller_stop_url"],
    "shelly2.5"     => ["btn_on_url","btn_off_url","longpush_url","shortpush_url","out_on_url","out_off_url",
                        "roller_open_url","roller_close_url","roller_stop_url"],
    "shellyplug"    => ["btn_on_url","out_on_url","out_off_url"],
    "shelly4"       => [""],
    "shellyrgbw"    => ["btn_on_url","btn_off_url","longpush_url","shortpush_url","out_on_url","out_off_url"],
    "shellydimmer"  => ["btn1_on_url","btn1_off_url","btn1_longpush_url","btn1_shortpush_url",
                        "btn2_on_url","btn2_off_url","btn2_longpush_url","btn2_shortpush_url","out_on_url","out_off_url"],
    "shellyem"      => ["out_on_url","out_off_url","over_power_url","under_power_url"],
    "shelly3em"     => ["out_on_url","out_off_url","over_power_url","under_power_url"],
    "shellybulb"    => ["out_on_url","out_off_url"],
    "shellyuni"     => ["btn_on_url","btn_off_url","longpush_url","shortpush_url","out_on_url","out_off_url","adc_over_url","adc_under_url"],
    "addon1"        => ["report_url","ext_temp_over_url","ext_temp_under_url","ext_hum_over_url","ext_hum_under_url"],
        #Gen2 components; event given as key 'event' by rpc/Webhook.List
    "light"   => ["light.on", "light.off"],   # events of the light component
    "relay"   => ["switch.on", "switch.off"],   # events of the switch component
    "roller"  => ["cover.stopped","cover.opening","cover.closing","cover.open","cover.closed"],
    "switch"  => ["input.toggle_on","input.toggle_off"],    # for input instances of type switch
    "button"  => ["input.button_push","input.button_longpush","input.button_doublepush","input.button_triplepush"],    # for input instances of type button
    "emeter"  => ["em.active_power_change","em.voltage_change","em.current_change"],
    "pm1"     => ["pm1.apower_change","pm1.voltage_change","pm1.current_change"],
    "touch"   => ["input.touch_swipe_up","input.touch_swipe_down","input.touch_multi_touch"],
    "sensor"  => ["temperature.change","humidity.change","illuminance.change"],
    "addon"   => ["temperature.change"]
);

my %fhem_events = (	# events, that can be used by webhooks; key is shelly-event, value is event sent to Fhem
	#Gen 1
	"out_on_url"       => "out_on",
	"out_off_url"      => "out_off",
	"roller_stopp_url" => "stopped",
	"roller_open_url"  => "stopped",
	"roller_close_url" => "stopped",
	"btn_on_url"       => "button_on",
	"btn_off_url"      => "button_off",
	"lp_on_url"        => "",		# Shelly1pm: button long pressed
	"lp_off_url"       => "",
        "shortpush_url"    => "single_push",
        "longpush_url"     => "long_push",
        "double_shortpush_url"   => "double_push",
        "triple_shortpush_url"   => "triple_push",
        "shortpush_longpush_url" => "short_long_push",
        "longpush_shortpush_url" => "long_short_push",
        "adc_over_url"       => "",
        "adc_under_url"      => "",
        "report_url"         => "",
        "ext_temp_over_url"  => "",
        "ext_temp_under_url" => "",
        "ext_hum_over_url"   => "",
        "ext_hum_under_url"  => "",
        #Shelly dimmer
	"btn1_on_url"        => "button_on 0",
	"btn1_off_url"       => "button_off 0",
        "btn1_shortpush_url" => "single_push 0",
        "btn1_longpush_url"  => "long_push 0",
	"btn2_on_url"        => "button_on 1",
	"btn2_off_url"       => "button_off 1",
        "btn2_shortpush_url" => "single_push 1",
        "btn2_longpush_url"  => "long_push 1",

	#Gen 2
	#light
	"light.on"      => "out_on",
	"light.off"     => "out_off",
	#relay
	"switch.on"     => "out_on",
	"switch.off"    => "out_off",
	#roller
	"cover.stopped" => "stopped",
	"cover.opening" => "opening",
	"cover.closing" => "closing",
	"cover.open"    => "is_open",
	"cover.closed"  => "is_closed",
	#switch
	"input.toggle_on"         => "button_on",
	"input.toggle_off"        => "button_off",
	#button
        "input.button_push"       => "single_push",
        "input.button_longpush"   => "long_push",
        "input.button_doublepush" => "double_push",
        "input.button_triplepush" => "triple_push",
        #touch
        "input.touch_swipe_up"    => "touch_up",
        "input.touch_swipe_down"  => "touch_down",
        "input.touch_multi_touch" => "touch_multi",
        #emeter (multiphase)
        "em.active_power_change"  => 'Active_Power_${phase} ${ev.act_power}',
        "em.voltage_change"       => 'Voltage_${phase} ${ev.voltage}',
        "em.current_change"       => 'Current_${phase} ${ev.current}',
        #mini-emeter (shellypmmini)
        "pm1.apower_change"       => 'power ${ev.apower}',
        "pm1.voltage_change"      => 'voltage ${ev.voltage}',
        "pm1.current_change"      => 'current ${ev.current}',
        #addon and wall display sensor
        "temperature.measurement" => "tempC",
        "temperature.change"      => 'tempC ${ev.tC}',
        "humidity.change"         => 'humidity ${ev.rh}',
        "illuminance.change"      => 'illuminance ${ev.illumination}',
        # translations
        "S"       => "single_push",
        "L"       => "long_push",
        "SS"      => "double_push",
        "SSS"     => "triple_push",
        "SL"      => "short_long_push",
        "LS"      => "long_short_push",
        "short_push"  => "S",
        "single_push" => "S",
        "long_push"   => "L",
        "double_push" => "SS",
        "triple_push" => "SSS"
);


my %shelly_regs = (
    "relay"  => "reset=1\x{27f6}factory reset\n".
                  "appliance_type=&lt;string&gt;\x{27f6}custom configurabel appliance type\n".  # uni
                  "has_timer=0|1\x{27f6}wheather there is an active timer on the channel  \n".   # uni
                  "overpower=0|1\x{27f6}wheather an overpower condition has occured  \n".   # uni  !Sh1 1pm   4pro   plug
                  "default_state=off|on|last|switch\x{27f6}state after power on\n".
                  "btn_type=momentary|toggle|edge|detached|action|cycle|momentary_on_release\x{27f6}type of local button\n".   # extends for uni    *1L
                  "btn_reverse=0|1\x{27f6}invert local button\n".                  #   *1L   Sh1L has two buttons
                  "auto_on=&lt;seconds&gt;\x{27f6}timed on\n".
                  "auto_off=&lt;seconds&gt;\x{27f6}timed off\n".
                  "schedule=0|1\x{27f6}enable schedule timer\n".
                  "max_power=&lt;watt&gt;\x{27f6}power threshold above which an overpower condition will be triggered",   # sh1pm sh1L   !sh2  2.5   4pro  plug
    "roller" => "reset=1\x{27f6}factory reset\n".
                  "maxtime=&lt;seconds&gt;\x{27f6}maximum time needed to completely open or close\n".
                  "maxtime_open=&lt;seconds&gt;\x{27f6}maximum time needed to completely open\n".
                  "maxtime_close=&lt;seconds&gt;\x{27f6}maximum time needed to completely close\n".
                  "default_state=stop|open|close|switch\x{27f6}state after power on\n".
                  "swap=true|false\x{27f6}swap open and close directions\n".
                  "swap_inputs=true|false\x{27f6}swap inputs\n".
                  "input_mode=openclose|onebutton\x{27f6}two or one local button\n".
                  "button_type=momentary|toggle|detached|action\x{27f6}type of local button\n".   # frmly btn_type
                  "btn_reverse=true|false\x{27f6}whether to invert the state of input switch\n".
                  "state=stop|open|close\x{27f6}state of roller\n".
                  "power=&lt;watt&gt;\x{27f6}current power consumption\n".
                  "safety_switch=true|false\x{27f6}whether the safety input is currently triggered\n".
                  "schedule=true|false\x{27f6}whether scheduling is enabled\n".
                  "obstacle_mode=disabled|while_opening|while_closing|while_moving\x{27f6}when to react on obstacles\n".
                  "obstacle_action=stop|reverse\x{27f6}what to do\n".
                  "obstacle_power=&lt;watt&gt;\x{27f6}power threshold for detection\n".
                  "obstacle_delay=&lt;seconds&gt;\x{27f6}delay after motor start to watch\n".
                  "safety_mode=disabled|while_opening|while_closing|while_moving\x{27f6}safety mode=2nd button\n".
                  "safety_action=stop|pause|reverse\x{27f6}action when safety mode\n".
                  "safety_allowed_on_trigger=none|open|close|all\x{27f6}commands allowed in safety mode\n".
                  "off_power=&lt;watt&gt;\x{27f6}power value below the roller is considered \'stopped\'\n".
                  "positioning=true|false\x{27f6}whether the device is calibrated for positioning control",
    "color"   => "reset=1\x{27f6}factory reset\n".    # shellyrgbw2 color-mode: /settings/color/0  || /settings/light/0
               #  "coiot=0|1\x{27f6}enable coiot\n".
                  "name=&lt;name&gt;\x{27f6}channel name\n".
                  "transition=&lt;milliseconds&gt;\x{27f6}transition time between on and off, 0...5000\n".
                  "effect=0|1|2|3\x{27f6}apply an effect 1=Meteor Shower 2=Gradual Change 3=Flash\n".  # !|4|5|6
                  "default_state=off|on|last\x{27f6}state after power on\n".
                  "btn_type=momentary|toggle|edge|detached\x{27f6}type of local button\n".
                  "btn_reverse=0|1\x{27f6}invert local button\n".
                  "auto_on=&lt;seconds&gt;\x{27f6}timed on\n".
                  "auto_off=&lt;seconds&gt;\x{27f6}timed off\n".
                  "schedule=0|1\x{27f6}enable schedule timer\n".
                  "btn_type=momentary|toggle|edge|detached|action\x{27f6}type of local button\n".
                  "btn_reverse=0|1\x{27f6}invert local button",
    "bulbw"   => "reset=1\x{27f6}factory reset\n".     # shellyrgbw2 white-mode: /settings/white/{index}  || /settings/light/{index}   bulb white:/settings/light/0
                  "brightness=&lt;number&gt;\x{27f6}output level 0...100\n".
                  "transition=&lt;milliseconds&gt;\x{27f6}transition time between on and off, 0...5000\n".
                  "default_state=off|on|last\x{27f6}state after power on\n".  # !switch
                  "auto_on=&lt;seconds&gt;\x{27f6}timer to turn ON after every OFF command\n".
                  "auto_off=&lt;seconds&gt;\x{27f6}timer to turn OFF after every ON command\n".
                  "schedule=0|1\x{27f6}enable schedule timer",
    "white"   => "name=&lt;name&gt;\x{27f6}channel name\n".                  # additional registers for rgbw-white
                  "btn_type=momentary|toggle|edge|detached\x{27f6}type of local button\n".
                  "btn_reverse=0|1\x{27f6}invert local button\n".
                  "out_on_url=&lt;url&gt;\x{27f6}url when output is activated\n".
                  "out_off_url=&lt;url&gt;\x{27f6}url when output is deactivated",
    "light"   => "reset=1\x{27f6}factory reset\n".     # shellydimmer     /settings/light/0
                  # "reset=0|1\x{27f6}whether factory reset via 5-time flip of the input switch is enabled\n".
                 # "name=&lt;name&gt;\x{27f6}dimmer device name\n".   # does not work properly
                  "default_state=off|on|last|switch\x{27f6}state after power on\n".
                  "auto_on=&lt;seconds&gt;\x{27f6}timer to turn the dimmer ON after every OFF command\n".
                  "auto_off=&lt;seconds&gt;\x{27f6}timer to turn the dimmer OFF after every ON command\n".
                  "btn_type=one_button|dual_button|toggle|edge|detached|action\x{27f6}type of local button\n".
                  "btn_debounce=&lt;milli seconds&gt;\x{27f6}button debounce time (60...200ms)\n".
                  "swap_inputs=0|1\x{27f6}swap inputs",
    "input"   => "reset=1\x{27f6}factory reset\n".
                  "name=&lt;name&gt;\x{27f6}input name\n".
                  "btn_type=momentary|toggle\x{27f6}type of local button\n".
                  "btn_reverse=0|1\x{27f6}invert local button\n"
                  );

my %predefAttrs = (
      "roller_webCmd"    => "open:up:down:closed:half:stop:pct",
      "roller_eventMap_closed100"  => "/delta -15:up/delta +15:down/pos 50:half/",
      "roller_eventMap_open100"    => "/delta +15:up/delta -15:down/pos 50:half/",
      "roller_cmdIcon"   => "open:control_arrow_upward\@blue up:control_arrow_up\@blue down:control_arrow_down\@blue closed:control_arrow_downward\@blue".
                            " stop:rc_STOP\@blue half:fts_shutter_50\@blue",
      "roller_open100"   => "open:fts_shutter_100:closed".
      				" closed:fts_shutter_10:open".
      				" half:fts_shutter_50:closed".
      				" drive-up:fts_shutter_up\@red:stop".
      				" drive-down:fts_shutter_down\@red:stop".
      				" pct-100:fts_window_2w:closed".
      				" pct-90:fts_shutter_10:closed".
      				" pct-80:fts_shutter_20:closed".
      				" pct-70:fts_shutter_30:closed".
      				" pct-60:fts_shutter_40:closed".
      				" pct-50:fts_shutter_50:closed".
      				" pct-40:fts_shutter_60:open".
      				" pct-30:fts_shutter_70:open".
      				" pct-20:fts_shutter_80:open".
      				" pct-10:fts_shutter_90:open".
      				" pct-0:fts_shutter_100:open",
      "roller_closed100" => "open:fts_shutter_10:closed".
      				" closed:fts_shutter_100:open".
      				" half:fts_shutter_50:closed".
      				" drive-up:fts_shutter_up\@red:stop".
      				" drive-down:fts_shutter_down\@red:stop".
      				" pct-100:fts_shutter_100:open".
      				" pct-90:fts_shutter_90:closed".
      				" pct-80:fts_shutter_80:closed".
      				" pct-70:fts_shutter_70:closed".
      				" pct-60:fts_shutter_60:closed".
      				" pct-50:fts_shutter_50:closed".
      				" pct-40:fts_shutter_40:open".
      				" pct-30:fts_shutter_30:open".
      				" pct-20:fts_shutter_20:open".
      				" pct-10:fts_shutter_10:open".
      				" pct-0:fts_window_2w:closed"
      );

my %si_units = (
     "time"          => [""," sec"],
     "time_ms"       => [""," ms"],    # Milli-Seconds
     "current"       => [""," A"],
     "voltage"       => [""," V"],
     "voltmeter"     => [""," V"],     # same as voltage, used by Shelly Sensor Addon
     "power"         => [""," W"],     # Wirkleistung
     "act_power"     => [""," W"],     # double
     "reactivepower" => [""," var"],   # Blindleistung
     "react_power"   => [""," var"],   # double
     "apparentpower" => [""," VA"],    # Scheinleistung	
     "aprt_power"    => [""," VA"],    # double			
     "energy"        => [""," Wh"],    # Arbeit;
     "frequency"     => [""," Hz"],
     "tempAbs"       => [""," K"],     # Kelvin 
     "tempF"         => [""," °F"],    # Fahrenheit 
     "tempC"         => [""," °C"],    # Celsius
     "temperature"   => [""," °C"],    # Celsius
     "humidity"      => [""," %"],
     "pct"           => [""," %"],
     "illuminance"   => [""," lx"],    # Lux; illuminance eg WallDisplay
     "illumination"  => ["",""],       # values:  twilight, ... dark,...
     "ct"            => [""," K"],     # color temperature / Kelvin
     "rssi"          => [""," dBm"],   # deziBel Miniwatt
     "input"         => ["",""] ,      # dummy - used by Shelly Sensor Addon
     "digital_input" => ["",""] , 
     "analog_input"  => [""," %"]
     );

 my %energy_units  = ( #si, faktor, decimals
     "none"       => [ "Wh", 1,     0 ],
     "original"   => [ "-", 1,     0 ],
     "normal"     => [ "Wh", 1,     1 ],
     "normal2"    => [ "kWh",0.001, 4 ],
     "ISO"        => [ "kJ", 3.6,   0 ]
     );

my %peripherals = (
 # Peripheral type   =>  Component Type
  "analog_in"   => "input",
  "digital_in"  => "input",
  "dht22"       => "humidity",
  "ds18b20"     => "temperature",
  "voltmeter"   => "voltmeter"
); 

my @id2ch = ( "a_", "b_", "c_" );  # map id's of monophase device to channels
#-- support differtent readings-names for energy & power metering
my %mapping = (
        sf => {
           "none" => {
                      "a_"  => "A_",
                      "b_"  => "B_",
                      "c_"  => "C_",
                      "total_"  => "S_"
           },
           "a_b_c" => {
                      "a_"  => "a",
                      "b_"  => "b",
                      "c_"  => "c",
                      "total_"  => "total"
           },
           "ABC_" => {
                      "a_"  => "A_",
                      "b_"  => "B_",
                      "c_"  => "C_",
                      "total_"  => "S_"
           },
           "L123_" => {
                      "a_"  => "L1_",
                      "b_"  => "L2_",
                      "c_"  => "L3_",
                      "total_"  => "TTL_"
           },
           "_ABC" => {
                      "a_"  => "_A",
                      "b_"  => "_B",
                      "c_"  => "_C",
                      "total_"  => "_S"
           },
           "_L123" => {
                      "a_"  => "_L1",
                      "b_"  => "_L2",
                      "c_"  => "_L3",
                      "total_"  => "_TTL"
           },
        },
        pr => {
           "ABC_" => {
                      "a_"  => "A_",
                      "b_"  => "B_",
                      "c_"  => "C_",
                      "total_"  => "S_"
           },
           "L123_" => {
                      "a_"  => "L1_",
                      "b_"  => "L2_",
                      "c_"  => "L3_",
                      "total_"  => "TTL_"
           },
           "_ABC" => {
                      "a_"  => "",
                      "b_"  => "",
                      "c_"  => "",
                      "total_"  => ""
           },
           "_L123" => {
                      "a_"  => "",
                      "b_"  => "",
                      "c_"  => "",
                      "total_"  => ""
           },
        },
        ps => {
           "ABC_" => {
                      "a_"  => "",
                      "b_"  => "",
                      "c_"  => "",
                      "total_"  => ""
           },
           "L123_" => {
                      "a_"  => "",
                      "b_"  => "",
                      "c_"  => "",
                      "total_"  => ""
           },
           "_ABC" => {
                      "a_"  => "_A",
                      "b_"  => "_B",
                      "c_"  => "_C",
                      "total_"  => "_S"
           },
           "_L123" => {
                      "a_"  => "_L1",
                      "b_"  => "_L2",
                      "c_"  => "_L3",
                      "total_"  => "_TTL"
           },
        },
        E1 => {
          'current'              => "Current",                         # Strom
          'act_power'            => "Active_Power",                    # Leistung = Wirkleistung
          'aprt_power'           => "Apparent_Power",                  # Scheinleistung
          'react_power'          => "PowerReactive",                  # Blindleistung
          'voltage'              => "Voltage",                         # Spannung
          'pf'                   => "Power_Factor",                    # Leistungsfaktor
          'frequency'            => "Frequency",                       # Frequenz
          'cap'                  => "capacitive",                      # kapazitiv
          'ind'                  => "inductive",                       # induktiv
          'total_act_energy'     => "Purchased_Energy",                # Wirkenergie_Bezug
          'total_act_ret_energy' => "Returned_Energy",                 # Wirkenergie_Einspeisung
          'act'                  => "Purchased_Energy",
          'act_ret'              => "Returned_Energy",
          'act_calculated'       => "Active_Power_calculated",
          'act_integrated'       => "Active_Power_integrated",
          'act_integratedPos'    => "Active_Power_integratedPos",
          'act_integratedNeg'    => "Active_Power_integratedNeg",
          'act_integratedSald'   => "Active_Power_integratedSald",
          'meter'                => "Meter",
          'meter2'               => "Meter2"
        }
    );

########################### preps for Shelly BLU bluetooth devices #####################
my @shelly_models = (
    "button1",
    "button2" 
    );
    
########################################################################################
#
# Shelly_Initialize
#
# Parameter hash
#
########################################################################################

sub Shelly_Initialize ($) {
  my ($hash) = @_;

  $hash->{DefFn}    = "Shelly_Define";
  $hash->{UndefFn}  = "Shelly_Undef";
  $hash->{DeleteFn} = "Shelly_Delete";
  $hash->{RenameFn} = "Shelly_Rename";
  
  if( defined($hash->{SUBTYPE}) && $hash->{SUBTYPE} ne "BLU" ){
      $hash->{AttrList}= "model";
  }else{
      $hash->{AttrFn}   = "Shelly_Attr";
      $hash->{NotifyFn} = "Shelly_Notify";
      $hash->{GetFn}    = "Shelly_Get";
      $hash->{SetFn}    = "Shelly_Set";

      $hash->{AttrList}= "model:".join(",",(sort keys %shelly_models)).
                     " maxAge".
                     " ShellyName".
                     $attributes{'modes'}.
               #      " mode:relay,roller,white,color".
                     " interval timeout shellyuser".
                     $attributes{'multichannel'}.
                     $attributes{'roller'}.
                     $attributes{'dimmer'}.
                     $attributes{'input'}.
                     $attributes{'metering'}.
                     $attributes{'showunits'}.
                     " webhook:".join(",",devspec2array('TYPE=FHEMWEB:FILTER=TEMPORARY!=1')).   ## none,
                     $attributes{'emeter'}.
                     $attributes{'emPeriods'}.
                     " verbose:0,1,2,3,4,5".
                     " host_dns host_ip".
                     " ".$readingFnAttributes;
       
  }
} #end Shelly_Initialize()

########################################################################################
#
# Shelly_Define - Implements DefFn function
#
# Parameter hash, definition string
#
########################################################################################

sub Shelly_Define($$) {   # use Socket;
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name=$hash->{NAME};
  
  if(@a < 3){
      return "[Shelly_Define] $name: Define the address of the Shelly device as a parameter";
  }elsif(@a > 4){
     return "error in definiton / illegal number of arguments";
  }

  my $definit=$a[2];
  my ($portnumber,$hostname);
  #-- checking ipv4-address [:portnumber]
#  if( $a[2] =~ m|\d\d?\d?\.\d\d?\d?\.\d\d?\d?\.\d\d?\d?(\:\d+)?| ){ 
#  if( $a[2] =~ m|^((\d{1,3}\.?\b){4})(\:\d+)?$| ){
  if( $a[2] =~ m|^((\d{1,3}\.?\b){4})| ){
    $definit=$1; #ipaddr
    if( $a[2] =~ m/^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}(\:\d+)?$/ ){
      # we have a valid ip-address
      Log 4,"[Shelly_define] IPv4-Addr \'$definit\' is valid"; 
      $hostname = gethostbyaddr( inet_aton($definit),AF_INET);
      if( defined($hostname) && $a[2] !~ /\:/ ){
          Log 4,"[Shelly_define] Hostname of $definit is $hostname";
          $hostname =~ s/\.fritz\.box//;
          readingsSingleUpdate($hash,"network_DNS",$hostname,1);
      }else{
          readingsSingleUpdate($hash,"network_DNS","-",1);
      }
    }else{
      Log 1,"[Shelly_define] looks like an ip4-address, but is not valid";
      return "looks like an ip4-address, but is not valid";
    }

  #-- check DNS-name [:portnumber]
  }elsif( $a[2] =~ m|^(?![0-9]+$)(?!-)[a-zA-Z0-9-]{3,63}(?<!-)(\:\d+)?$| ){
      # we have a valid DNS name
      Log3 $name,3,"[Shelly_define] alphanumerical DNS name \'$definit\' is treated as valid";
      my $dnsname=$definit;
      if( $a[2] =~ m|(.*)\:(\d*)$| ){
          # we have a valid dns-name and portnumber
          $dnsname=$1 // $definit;
          my $portnum=$2 // "";
          Log3 $name,3,"[Shelly_define] DNS-name is $dnsname and port=$portnum"; 
      }      
      my $packed_ip=gethostbyname($dnsname);
      if( defined($packed_ip) ){
          my $ip_addr=Socket::inet_ntoa($packed_ip); # use
          Log 3,"[Shelly_define] $name: found ip-address=$ip_addr for host=\'$dnsname\'";
          if( $a[2] !~ /\:/ ){
              readingsSingleUpdate($hash,"network_DNS",$dnsname,1);
          }else{
              readingsSingleUpdate($hash,"network_DNS","-",1);
          }
      }else{
          Log 1,"[Shelly_define] $name: cannot find \'$dnsname\'";
          return "cannot find $dnsname";
      }
   #-- check MAC-address 
  }elsif( $a[2] =~ m/^(([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2})/ ){
      # we have a valid MAC-address
      Log 4,"[Shelly_define] $name: hexadecimal MAC-Addr \'$definit\' is treated as valid";
      $hash->{SUBTYPE} = "bluetooth";
      readingsSingleUpdate($hash,"mac",uc($a[2]),1 );
      return undef;
  }else{
      Log 1,"[Shelly_define] invalid definition (IP address / DNS name / MAC address) ".$a[2];
      return "[Shelly_Define] $name: invalid definition ".$a[2];
  }
  
  #-- checking port number
    if( $a[2] =~ m/\:(\d+)$/ ){
      # we have a port number
      $portnumber=$1;
      if( $portnumber <= 65535 ){
          Log 4,"[Shelly_define] Portno \'$portnumber' is valid"; 
      }else{
          Log 1,"[Shelly_define] \'$portnumber' is not a valid port number";
          return "port number \'$portnumber' is not valid";
      }
    }else{
      Log 4,"[Shelly_define] no port number given";
    }
  #-- authentication -----------------
  my $user="admin";
  my $pwd="";
  if( @a == 4 ){ # 
      if( $a[3] =~ /\:/ ){  # user:password
          $a[3] =~ m/(\S*):(\S*)/;
          $user=$1;
          $pwd =$2;
      }else{    # password
          $pwd =$a[3];
      } 
      Log 6,"[Shelly_define] got user=$user and password=$pwd"; #6
      $attr{$name}{shellyuser}=$user;
      Shelly_Set($hash,$name,"password",$pwd);
      # strip off user and password from DEF:
      $hash->{DEF}=$a[2];
  }

  #-- use hidden AttrList to make attributes changeable by Shelly_Attr()
  $hash->{'.AttrList'} = $modules{Shelly}{'AttrList'};
  
  #-- name of the access point ap
  if( $hash->{DEF} =~ /:/ ){
      $hash->{DEF} =~ /(.*):/;
      my $ap = (defInfo("DEF=$1",'NAME'))[0];   # the device name of the ap
      #my $host = "localhost:".InternalVal($FW_wname,'PORT',0).$FW_ME;   
      $ap = "<html><a href=\"http://localhost:"         # make it clickable    localhost eg. 192.168.178.107
            .InternalVal($FW_wname,'PORT',0)            # $FW_wname gives NAME of FHEMWEB instance
            ."$FW_ME?detail=$ap\">$ap</a></html>"  if(0);      # $FW_ME gives webname including starting '/'
      readingsSingleUpdate($hash,"network_host",$ap,1 );
  }else{
      fhem("deletereading $name network_host",1);
  }
  #--
  $modules{Shelly}{defptr}{$a[0]} = $hash;
  if( $init_done ){
      $hash->{INTERVAL} = AttrVal($hash->{NAME},"interval",$defaultINTERVAL); # Updates each minute, if not set as attribute
      Log3 $name,4,"[Shelly_define] Define is calling get modell for device $name, init=$init_done";  #  && $hash->{INTERVAL}>0
      Shelly_HttpRequest($hash,"/shelly","","Shelly_getModel" );
      InternalTimer(time()+0.6, "Refresh", $hash);   # perform a browser refresh
  }
  
  #-- initialize helper values
  $hash->{helper}{timer}=0;
  $hash->{helper}{StatusCall}=0;
  $hash->{helper}{settings_time} = 0;
  #-- initialize INTERNALS
  $hash->{units}=0 if( !defined($hash->{units}) );
  #-- remove 
  delete $hash->{SHELLY}; 
  
  #-- get host dns-name and ip-address 
  if(0 && $init_done && !AttrVal($name,"host_dns",undef) ){
      my $host=qx(hostname);
      $host =~ s/\n//;  # remove NewLine
      fhem("attr -silent $name host_dns $host");
  }   
  if($init_done && !AttrVal($name,"host_ip",undef) ){
      my $host_ip = "host-ip";
      if( $^O eq "linux" ){  # $^O contains the OS under which perl was build
          $host_ip = qx(hostname --all-ip-addresses); # only on linux, otherwise we get something else
          $host_ip =~ s/ .*\n$//;
      }
      if( $host_ip !~ m/^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$/ ){ # ip4
          fhem("attr -silent $name host_ip xxx.xxx.xxx.xxx");
          Log3 $name,1,"[Shelly_define] $name: Please set attribute \'host_ip\'  ($^O)";
      }else{
          Log3 $name,1,"[Shelly_define] $name: \'host_ip\'=$host_ip";      
      }
  }
  return undef;
} #end Shelly_Define()


sub Refresh {    ##see also forum topic 48736.0
    Log3 undef,1,"perform a browser refresh of $FW_wname";
    fhem("trigger $FW_wname JS:location.reload(true)");  # try a browser refresh ??
} #end Refresh


########################################################################################
#
# Shelly_getModel - get type/vendor_id (model) and mode (if given) from device
# Parameter:        parameter-hash, JSON-hash
#
########################################################################################

sub Shelly_getModel {
  my ($param,$jhash) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $call = $param->{cmd};
  my ($model_id,$model,$mode,$auth,$mac);

  if( $call eq "/shelly" ){  # the /shelly call is not blocked by authentication!
      if( defined($jhash->{type}) ){ #1G
          # set the type / vendor-id as internal
          $model_id=$jhash->{type};
          $mode=$jhash->{mode};   # mode is not supported by all devices within the /shelly call
          $auth=$jhash->{auth}; 
      }elsif( defined($jhash->{model}) ){ #2G
          # set the type / vendor-id as internal
          $model_id=$jhash->{model};
          $mode=$jhash->{profile};
          $auth=$jhash->{auth_en}; 
      }else{
          Log3 $name,4,"[Shelly_getModel] $name: have no result with the /shelly call, calling /settings";
          Shelly_HttpRequest($hash,"/settings",undef,"Shelly_getModel" );
      }
      
      ### MAC
      my $mac = $jhash->{mac};
      $mac =~ m/(\w\w)(\w\w)(\w\w)(\w\w)(\w\w)(\w\w)/;  # matching word characters (alphanumeric plus '_')
      $mac = sprintf("%s:%s:%s:%s:%s:%s",$1,$2,$3,$4,$5,$6);
  #    $mac .= "_(Wifi)" if( ReadingsVal($name,"model_family","unknown") =~ /Pro/ ); # we cannot get MAC of LAN adapter
      readingsSingleUpdate($hash,"mac",$mac,1);
      
      ### look if device is walldisplay with thermostat
      if( defined($jhash->{"relay_in_thermostat"}) ){
          # set the attr mode to thermostat          Shelly_Attr
          $attr{$hash->{NAME}}{mode} = "thermostat";
         # $hash->{helper}{Sets} =~ s/on off toggle on-for-timer off-for-timer/target/;
          $hash->{helper}{Sets} = "target";
          Log3 $name,1,"[Shelly_getModel] device $name is set to mode >thermostat<";
      }elsif(0&& $model =~ /walldisplay/ ){
          $attr{$hash->{NAME}}{mode} = "switch";
          Log3 $name,1,"[Shelly_getModel] device $name is of model >walldisplay< and set to mode >switch<";
      }
      
  }elsif( $call eq "/settings" ){
      if( defined($jhash->{device}{type}) ){
          # set the type / vendor-id as internal
          $model_id=$jhash->{device}{type};
          $mode=$jhash->{mode};
      }else{
          Shelly_HttpRequest($hash,"/rpc/Shelly.GetDeviceInfo",undef,"Shelly_getModel" );
      }
  }elsif( $call eq "/rpc/Shelly.GetDeviceInfo" ){
      if( defined($jhash->{model}) ){
          # set the type / vendor-id as internal
          $model_id=$jhash->{model};
          $mode=$jhash->{profile};
      }else{  #type not detected
          Log3 $name,2,"[Shelly_getModel] Unsuccessful: Got no \'type\' (Vendor-ID) for device $name, proposed model is \'generic\'";
          readingsSingleUpdate($hash,"state","type (Vendor-ID) not detected",1);
          Log3 $name,2,"[Shelly_getModel] type not found, proposed model of device $name is \'generic\'";
          $model_id = "unknown";
          $model = "generic";
      } 
      $auth=$jhash->{auth_en}; 
  }
  if( defined($model_id) ){
        Log3 $name,4,"[Shelly_getModel] device $name is of model_ID \'$model_id\'";
        readingsSingleUpdate($hash,"model_ID",$model_id,1);
        readingsSingleUpdate($hash,"model_family",$shelly_family{substr($model_id,0,2)},1);
        readingsSingleUpdate($hash,"model_function",$shelly_category{substr($model_id,2,2)}//"unknown",1);
        readingsSingleUpdate($hash,"model_name",$shelly_vendor_ids{$model_id}[1],1);
        #--------
        $model = $shelly_vendor_ids{$model_id}[0];
        if ( $model ){
            Log3 $name,4,"[Shelly_getModel] $call: discovered model=$model for device $name";
        }else{
            Log3 $name,1,"[Shelly_getModel] $call: device $name is of type \'$model_id\' but we have no key of that name, proposed model is \'generic\'";
            readingsSingleUpdate($hash,"state","type key not found, set to \"generic\" ",1);
            $model = "generic";
        }
  }
  if( defined($model) ){
    if( !defined($attr{$name}{model}) ){
        # set the model-attribute when the model attribute is not set yet
        $attr{$hash->{NAME}}{model} = $model; # _Attr
        Log3 $name,4,"[Shelly_getModel] $call: the attribute \'model\' of device $name is set to \'$model\' ";
        # reset time of last settings call
        $hash->{helper}{settings_time}=0;
    }else{
        # model is already given as attribute
        my $model_old = $attr{$name}{model};
        if( $model_old eq "generic" && $model ne "generic" ){
            Log3 $name,2,"[Shelly_getModel] $call: the model of device $name is already defined as generic, and will be redefined as \'$model\' ";
            $attr{$hash->{NAME}}{model} = $model;
        }elsif( $model_old eq $model ){
            Log3 $name,4,"[Shelly_getModel] $call: the model of device $name is already defined as \'$model\' ";
        }else{
            Log3 $name,3,"[Shelly_getModel] $call: the model of device $name is already defined as \'$model_old\', might be $model";
            readingsSingleUpdate($hash,"state","model already defined as \'$model_old\', might be $model",1);
            $model = $model_old; # old model will not be changed
        }
    }
    Shelly_Attr("set",$name,"model",$model,undef); # set the .AttrList
  }
  
  # mode / profile
      ### Gen2 energy meter are working in 'monophase' profile and (if applicant) in 'triphase' profile
      ### ShellyPlus/Pro2PM may work in profiles 'switch' or 'cover'
      ### RGBW devices may work in profiles 'white' or 'color'
  if( defined($mode) && defined($model) ){
     if( $shelly_models{$model}[8]>1 ){
         $mode =~ s/switch/relay/;  # we use 1st-Gen modes
         $mode =~ s/cover/roller/;
         Log3 $name,1,"[Shelly_getModel] $call: the mode/profile of device $name is set to \'$mode\' ";
         $attr{$hash->{NAME}}{mode} = $mode;
         Log3 $name,1,"[Shelly_getModel] device $name is working in profile \'$mode\'";
         readingsSingleUpdate($hash,"model_profile",$mode,1)  if( substr($model_id,2,2) eq "EM" );   # reading is deprecated
     }else{
         Log3 $name,1,"[Shelly_getModel] found mode \'$mode\' for device $name, but we don't have a multimode-definition";
     }
  }else{
         Log3 $name,1,"[Shelly_getModel] no mode/profile found for device $name";
         delete($attr{$hash->{NAME}}{mode});
  }
  
  # auth
  my $login = "unknown";
  if( defined($auth) ){
     my ($err, $pw) = getKeyValue("SHELLY_PASSWORD_$name");
     my $shellyuser = AttrVal($name,"shellyuser",undef);
     $shellyuser = "admin" if( $shelly_models{$model}[4] > 0 );
     if( $auth==1 ){
         if( !defined($shellyuser) ){
             $login="ERROR";
             Shelly_error_handling($hash,"Shelly_getModel","shellyuser required",1);
         }elsif( !$pw ){
             $login="ERROR";
             Shelly_error_handling($hash,"Shelly_getModel","password required",1);
         }elsif( $shelly_models{$model}[4]>0 ){
             $login = "password";
         }else{ # Gen1
             $login = "username:password";
         }
     }else{
         $login = "open";
     }
  } 
 # readingsSingleUpdate($hash,"auth",$auth,1);
  readingsSingleUpdate($hash,"login",$login,1);
         
  delete($hash->{helper}{Sets}); # build up the sets-dropdown with next refresh

  if( $param->{cmd} eq "/shelly" && $shelly_models{$model}[8]>1  && $shelly_models{$model}[4]==0 && !defined($mode) ){
        # searching for 'mode' of multimode Gen1 devices, eg. ShellyRGBW
        Log 1,"[Shelly_getModel] searching for mode of $name";
        Shelly_HttpRequest($hash,"/settings",undef,"Shelly_getModel" );
  }else{
        # start cyclic update of status & settings
        Shelly_Set($hash,$name,"startTimer");
        Shelly_status($hash,"Shelly_getModel");
  }
} #end Shelly_getModel()


#######################################################################################
#
# Shelly_Delete - Implements DeleteFn function
#
# Parameter hash = hash of device addressed
#
#######################################################################################

sub Shelly_Delete ($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my ($err, $sh_pw) = setKeyValue("SHELLY_PASSWORD_$name", undef);
  Log3 $name,1,"[Shelly_Delete] $name deleted";
  return undef;
} #end Shelly_Delete

#######################################################################################
#
# Shelly_Undef - Implements UndefFn function
#
# Parameter hash = hash of device addressed
#
#######################################################################################

sub Shelly_Undef ($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  ##if( !defined($hash->{CMD}) || $hash->{CMD} ne "del" ){
  ##    fhem("deleteattr $name webhook"); # delete Actions on shelly
  ##    $hash->{CMD}="del";
  ##    InternalTimer(time()+25,"Shelly_Undef",$hash,0);
  ##    return;
  ##}
  delete($modules{Shelly}{defptr}{NAME});
  RemoveInternalTimer($hash);
  return undef;
} #end Shelly_Undef

#######################################################################################
#
# Shelly_Rename - Implements RenameFn function
#
# Parameter hash = hash of device addressed
#
#######################################################################################

sub Shelly_Rename ($$) {
  my ( $new_name, $old_name ) = @_;

  my $old_index = "Module_Shelly_".$old_name."_data";
  my $new_index = "Module_Shelly_".$new_name."_data";

  my ($err, $old_pwd) = getKeyValue($old_index);
  return undef unless(defined($old_pwd));

  setKeyValue($new_index, $old_pwd);
  setKeyValue($old_index, undef);
  return undef;
} #end Shelly_Rename

#######################################################################################
#
# Shelly_Attr - Set one attribute value
#
# Note: the 'model' and 'mode' attributes are also set by Shelly_getModel()
#
########################################################################################

sub Shelly_Attr(@) {
  my ($cmd,$name,$attrName, $attrVal, $RR) = @_;

  my $hash = $main::defs{$name};
  my $error; # will be set to a message string in case of error
  my $regex;

  my $model =  AttrVal($name,"model","generic");
  my $mode  =  AttrVal($name,"mode","");
  Log3 $name,5,"[Shelly_Attr] $name: called with command \'$cmd\' for attribute \'$attrName\'".(defined($attrVal)?", value=$attrVal":"")." init=$init_done";#5

  #---------------------------------------
  if( $cmd eq "set" && $attrName eq "model" ){
    $regex = "((".join(")|(",(keys %shelly_models))."))";
    if( $attrVal !~ /$regex/ && $init_done ){
      $error = "Wrong value of model attribute, see documentation for possible values";
      Log3 $name,1,"[Shelly_Attr] $name\: $error ";
      return $error;
    }

    Log3 $name,5,"[Shelly_Attr] $name is set to model $attrVal and has mode=$mode, attribute list will be adapted";# \n".$hash->{'.AttrList'}; #5

       # set the mode-attribute (when we have a multimode device)
        #if ( $mode && (( $shelly_models{$model}[0]>0 && $shelly_models{$model}[1]>0 ) || $model=~/rgbw/ || $model=~/bulb/ ) ){
        if( $mode && $shelly_models{$attrVal}[8]>1 ){
          Log3 $name,5,"[Shelly_Attr] discovered mode=$mode for device $name";
          $attr{$hash->{NAME}}{mode} = $mode;
          $hash->{MOVING}="stopped"
              if( $mode eq "roller" ); # first initialize
        }

    #############################################################
    #-- change attribute list depending on model w. hidden AttrList
       ## my $AttrList = $hash->{'.AttrList'};#$modules{Shelly}{'AttrList'};

    # replace all other models, except generic
    if( $attrVal ne "generic" ){
          $hash->{'.AttrList'} =~ s/,(\S+?)\s/,$attrVal /;
    }else{
          $hash->{'.AttrList'} =~ s/mode:(\S+?)\s//; # no mode
    }
    		
    if( $attrVal =~ /shelly(plus|pro)?2.*/ ){
          $hash->{'.AttrList'} =~ s/,white,color//;
          $hash->{'.AttrList'} =~ s/( maxtime )/ /; # we have almost maxtime_open maxtime_close
    }elsif( $attrVal =~ /shelly(rgbw|bulb)/){
          $hash->{'.AttrList'} =~ s/relay,roller,//;
    #      $hash->{'.AttrList'} =~ s/ maxtime//;
    }elsif( $attrVal =~ /shelly.*/){
          $hash->{'.AttrList'} =~ s/mode:relay,roller,white,color //;
    #      $hash->{'.AttrList'} =~ s/ maxtime//;
    }

    if( $shelly_models{$attrVal}[5]==0 ){  # no inputs, eg. shellyplug
          $hash->{'.AttrList'} =~ s/ showinputs:show,hide//;
    }

    if( $shelly_models{$attrVal}[2]==0 ){  # no dimmer
          $hash->{'.AttrList'} =~ s/ dimstep//;
    }
    
    if( $shelly_models{$attrVal}[1]>0 && $mode ne "roller" || $shelly_models{$attrVal}[4]==0 ){  # no roller  or  Gen1
          $hash->{'.AttrList'} =~ s/ slat_control//;
          $hash->{'.AttrList'} =~ s/ slat_pos//;
    }

    if( $shelly_models{$attrVal}[6]>0 ){  # "shellyproem50"  "shellypro3em"  ## $attrVal =~ /pro3em|proem50/
          $hash->{'.AttrList'} =~ s/\smaxpower//;
    ##    $hash->{'.AttrList'} =~ s/ webhook:(\S+?)\s//;  # Shelly actions do not work properly (fw v0.14.1)
    ##      $hash->{'.AttrList'} .= " Energymeter_F Energymeter_P Energymeter_R EMchannels:ABC_,L123_,_ABC,_L123";
          $hash->{helper}{Total_Energy_S}=0;
          #-- initialize calculation of integrated power value
          $hash->{helper}{power} = 0;
          $hash->{helper}{powerCnt} = 1;
          #-- initialize these helpers to prepare summarizing of Total of pushed values
          $hash->{helper}{a_Active_Power}=0;
          $hash->{helper}{b_Active_Power}=0;
          $hash->{helper}{c_Active_Power}=0;

          $hash->{helper}{powerPos} = 0;
          $hash->{helper}{powerNeg} = 0;

    }elsif( $attrVal eq "shellypmmini" ){
          #allow Periods attribute
          #$hash->{'.AttrList'} =~ s/$attributes{'emeter'}/" Periods:multiple-strict,Year,Month,Week,day,dayT,dayQ,hour,hourQ,hourT,min"/e; 
          $hash->{'.AttrList'} =~ s/$attributes{'emeter'}/""/e; 
    }else{
          $hash->{'.AttrList'} =~ s/$attributes{'emeter'}/""/e;
          $hash->{'.AttrList'} =~ s/$attributes{'emPeriods'}/""/e;
    }

    if( $shelly_models{$attrVal}[1]==0 ){  #no roller
          $hash->{'.AttrList'} =~ s/$attributes{'roller'}/""/e;
          delete $hash->{MOVING}; # ?really necessary?
    }

    if( $shelly_models{$attrVal}[3]==0 && $shelly_models{$attrVal}[6]==0 ){  #no metering, eg. shellyi3  but we have units for RSSI
          $hash->{'.AttrList'} =~ s/$attributes{'metering'}/""/e;
          $hash->{'.AttrList'} =~ s/$attributes{'showunits'}/" showunits:none,original"/e;  # shellyuni measures voltage
    }

    if( $shelly_models{$attrVal}[5] <= 0 ){  #no inputs, but buttons, eg. shellyplug
          $hash->{'.AttrList'} =~ s/$attributes{'input'}/""/e;
    }

    if( $shelly_models{$attrVal}[4] > 0 ){  # Gen 2 devices. Shellyuser is "admin" by default
          $hash->{'.AttrList'} =~ s/shellyuser/""/e;
    }

    if(     defined($mode) && $mode eq "relay"  && $shelly_models{$attrVal}[0]>1 ){  #more than one relay
    }elsif( defined($mode) && $mode eq "roller" && $shelly_models{$attrVal}[1]>1 ){  #more than one roller
    }elsif( defined($mode) && $mode eq "white"  && $shelly_models{$attrVal}[2]>1 ){  #more than one dimmer
    }elsif( $shelly_models{$attrVal}[0]>1 || $shelly_models{$attrVal}[1]>1 || $shelly_models{$attrVal}[2]>1 ){ # we have single mode but multiple channel
    }else{
          # delete 'defchannel' from attribute list
          $hash->{'.AttrList'} =~ s/$attributes{'multichannel'}/""/e;
          Log3 $name,4,"[Shelly_Attr] deleted defchannel etc from device $name: model=$attrVal, mode=". (!$mode?"not defined":$mode);
    }

    if( defined($mode) && $mode eq "color" && $shelly_models{$attrVal}[7]==1 ){  #rgbw in color mode
          $hash->{'.AttrList'} =~ s/$attributes{'multichannel'}/""/e;
    }

    if( defined($mode) && $mode eq "thermostat" ){  #WallDisplay in thermostat mode
          $hash->{'.AttrList'} =~ s/$attributes{'modes'}/" mode:thermostat"/e;  # %attributes
    }
    
    if(0 && $shelly_models{$attrVal}[4]==0 && $attrVal ne "shellybulb" ){  # 1st Gen
          $hash->{'.AttrList'} =~ s/webhook(\S*?)\s//g;
    }
    Log3 $name,5,"[Shelly_Attr] $name ($attrVal) has new attrList \n".$hash->{'.AttrList'}; #5

    # delete some readings------------------------ silent
    if( $attrVal =~ /shelly.*/ ){
      #-- only one relay
      if( $shelly_models{$attrVal}[0] == 1){
        fhem("deletereading $name relay_.*",1);
        fhem("deletereading $name overpower_.*",1);
        fhem("deletereading $name button_.*",1);
      #-- no relay
      }elsif( $shelly_models{$attrVal}[0] == 0){
        fhem("deletereading $name relay.*",1);
        fhem("deletereading $name overpower.*",1);
        fhem("deletereading $name button.*",1);
      #-- other number
      }else{
        readingsDelete( $hash, "relay");
        readingsDelete( $hash, "overpower");
        readingsDelete( $hash, "button");
      }
      #-- only one roller
      if( $shelly_models{$attrVal}[1] == 1){
   #     fhem("deletereading $name .*_.");
    #    fhem("deletereading $name stop_reason.*");
     #   fhem("deletereading $name last_dir.*");
      #  fhem("deletereading $name pct.*");
       # delete $hash->{MOVING};
        #delete $hash->{DURATION};
      #-- no rollers
      }elsif( $shelly_models{$attrVal}[1] == 0){
        fhem("deletereading $name position.*",1);
        fhem("deletereading $name stop_reason.*",1);
        fhem("deletereading $name last_dir.*",1);
        fhem("deletereading $name pct.*",1);
        delete $hash->{MOVING};
        delete $hash->{DURATION};
      }
      #-- no dimmers
      if( $shelly_models{$attrVal}[2] == 0){
        fhem("deletereading $name L-.*",1);
        fhem("deletereading $name rgb",1);
        fhem("deletereading $name pct.*",1);
      }

      #-- always clear readings for meters
      fhem("deletereading $name power.*",1);
      fhem("deletereading $name energy.*",1);
      fhem("deletereading $name overpower.*",1);
    }
  # model/
  #---------------------------------------
  }elsif( $cmd eq "set" && $attrName eq "mode" && $init_done == 0 ){
          if( $attrVal eq "roller" || $attrVal eq "relay" ){
              $hash->{'.AttrList'} =~ s/,white,color//;
          }elsif( $attrVal eq "white" || $attrVal eq "color" ){
              $hash->{'.AttrList'} =~ s/relay,roller,//;
          }

  #---------------------------------------
  }elsif( $cmd eq "set" && $attrName eq "mode" && $init_done == 1 ){    # after init, we know the model !
    Log3 $name,3,"[Shelly_Attr:mode] $name: setting mode to $attrVal (model is $model)";
    if( $model eq "generic" && 0 ){
      $error="Setting the mode attribute for model $model is not possible. \nPlease set attribute model first <$init_done>";
      Log3 $name,1,"[Shelly_Attr] $name\: $error ".($init_done?"init is done":"init not done");
      return $error;
    }
    if( $model !~ /shelly(2|plus2|pro2|(rgb|bulb)).*/ ){
      $error="Setting the mode attribute for this device is not possible";
      Log3 $name,1,"[Shelly_Attr] $name\: $error  only works for model=shelly2|shelly2.5|shellyplus2pm|shellypro2|shellyrgbw|shellybulb";
      return $error;
    }

    # we have a device that can be used in relay mode or roller mode:
    if( $shelly_models{$model}[0]>0  &&  $shelly_models{$model}[1]>0 ){
      fhem("deletereading $name power.*");
      fhem("deletereading $name energy.*");
      fhem("deletereading $name overpower.*");
      if( $attrVal eq "relay"){
        fhem("deletereading $name position.*");
        fhem("deletereading $name .*_reason.*");
        fhem("deletereading $name last_dir.*");
        fhem("deletereading $name pct.*");
      }elsif( $attrVal eq "roller"){
        fhem("deletereading $name relay.*");
        # only one roller
        if( $shelly_models{$model}[1]==1 ){
            fhem("deletereading $name .*_.");
        }
      }else{
        $error="Wrong mode \'$attrVal\' for this device, must be \'relay\' or \'roller\' ";
        Log3 $name,1,"[Shelly_Attr] $name\: $error";
        return $error;
      }
    }elsif( $model eq "shellydimmer" ){
      fhem("deletereading $name power.*");
      fhem("deletereading $name energy.*");
      fhem("deletereading $name overpower.*");
    }elsif( $model eq "shellyrgbw" || $model eq "shellybulb" ){
      fhem("deletereading $name power.*");
      fhem("deletereading $name energy.*");
      fhem("deletereading $name overpower.*");
      if( $attrVal eq "color"){
        fhem("deletereading $name pct.*");
        fhem("deletereading $name ct.*");
        fhem("deletereading $name state_.*");
      }elsif( $attrVal eq "white"){
        fhem("deletereading $name L-.*");
        readingsDelete( $hash, "rgb");
        readingsDelete( $hash, "hsv");
      }else{
        $error="Wrong mode value $attrVal for this device, must be white or color";
        Log3 $name,1,"[Shelly_Attr] $name\: $error";
        return $error;
      }
    }
    if( AttrVal($name,"mode","") eq $attrVal ){
        $error="Mode is already set to desired value, aborting";
        Log3 $name,1,"[Shelly_Attr] $name\: $error";
        return $error;
    }
    if( $shelly_models{$model}[4]==0 ){ #1st Gen
        Shelly_HttpRequest($hash,"/settings","?mode=$attrVal","Shelly_response","config" );
    }else{ #2ndGen  %26 =    %22  "
        Shelly_HttpRequest($hash,"/rpc/Sys.SetConfig","?config={%22device%22:{%22profile%22:$attrVal}}","Shelly_response","config" );
    }
    delete $hash->{MOVING}      if( $attrVal ne "roller" ); # ?necessary?
  # mode/

  #---------------------------------------
  }elsif( $attrName =~ /showunits/ ){
    if( $cmd eq "set"  && $attrVal ne "none" ){
        $hash->{units}=1;
    }else{   # del or set to none
        $hash->{units}=0;
    }

  #---------------------------------------
  }elsif( $attrName eq "PeriodsCorr-F" ){
    my (@keys,$key,$newkey);
    if( $cmd eq "del"){
      $hash->{CORR} = 1.0;
      if(0){
      # remove 'corrected values'-periods from attr-list:
      $hash->{'.AttrList'} =~ s/(,[a-z]{3,}-c)//ig;  # i: also uppercas letters
      #delete readings ending with '-c'
      @keys = keys %periods;
      foreach my $RP ( @keys ){
            next if( $RP !~ /-c/ );
            fhem("deletereading $name .*_$RP");
            Log3 $name,1,"[Shelly_Attr] deleted readings $name\:.*_$RP ";
      }
      }else{
            fhem("deletereading $name .*-c");
      }
      return;
    }
    if( $shelly_models{$model}[6]==0 && $model ne "shellypmmini"){  # $model ne "shellypro3em"
      $error="Setting of the attribute \"$attrName\" only works for ShellyPro3EM / ShellyPMmini ";
      Log3 $name,1,"[Shelly_Attr] $name\: $error ";
      return $error;
    }
    if( $attrVal > 1.1 || $attrVal < 0.9 ){
      $error="The correction factor \"$attrVal\" is outside the valid range ( 0.90 ... 1.10 )";
      Log3 $name,1,"[Shelly_Attr] $name\: $error ";
      return $error;
    }
    if( $cmd eq "set" ){
      $hash->{CORR} = round($attrVal,4);
      $_[3] = $hash->{CORR};
      if(0){
      #------expand the periods-hash & expand the hidden attribute list:
      @keys = keys %periods;
      foreach $key ( @keys ){
           if( $key !~ /(_c)$/ ){
               $newkey=$key.'_c';
               #if( !exists($periods{$newkey}) ){
               unless( AttrVal($name,$attrName,undef) ){ #run only once
                   $periods{$newkey}=$periods{$key};
                   $hash->{'.AttrList'} =~ s/$key/$key,$newkey/;
                   Log3 $name,4,"[Shelly_Attr] expanded \'periods\' by $newkey ".$periods{$newkey}[0];#4
               }
           }
      }
      }
    }
  #---------------------------------------
  }elsif( $init_done == 0 ){
	Log3 $name,5,"[Shelly_Attr:noinit]leaving Shelly_Attr for cmd $attrName while init is not finished ";
       return undef;

  ########## following commands are only passed when init is done ! #############

  #---------------------------------------
  }elsif( $cmd eq "set" && $attrName eq "maxAge" ){
    if ( $attrVal < 60 ){ #interval
        $error="maxAge must be at least \'interval\', in seconds";
        Log3 $name,1,"[Shelly_Attr] $name\: $error";
        return $error;
    }
  # maxage/
  #---------------------------------------
  # set the name of the Shelly
  }elsif( $cmd eq "set" && $attrName =~ /ShellyName/ ){
    #$attrVal="" if( $cmd eq "del" ); #cannot set name to empty string
    if ( $attrVal =~ " " ){ #spaces not allowed in urls
        $attrVal =~ s/ /%20/g;
    }
    if ($shelly_models{$model}[4]==0 ){ #1st Gen
        Shelly_HttpRequest($hash,"/settings","?name=$attrVal","Shelly_response","config" );
    }else{
        #                                                 {"device"   :{"  name"  :"attrVal"}}
        Shelly_HttpRequest($hash,"/rpc/Sys.SetConfig","?config={%22device%22:{%22name%22:%22$attrVal%22}}","Shelly_response","config" );
    }

  #---------------------------------------
  }elsif( $cmd eq "set" && $attrName =~ /showinputs/ && $attrVal ne "show" ){
     fhem("deletereading $name input.*");
     fhem("deletereading $name button.*");

  #---------------------------------------
  }elsif( $cmd eq "del" && $attrName =~ /showinputs/ ){
     fhem("deletereading $name input.*");
     fhem("deletereading $name button.*");

  #---------------------------------------
  }elsif( $cmd eq "set" && $attrName eq "maxpower" ){
    if( $shelly_models{$model}[3] == 0 ){
      $error="Setting the maxpower attribute for this device is not possible";
      Log3 $name,1,"[Shelly_Attr] $name\: $error";
      return $error;
    }
    my $power_limit = ($shelly_models{$model}[4]==0?3500:2800);
    if( $attrVal<1 || $attrVal>$power_limit ){
      $error="Maxpower must be within the range 1...$power_limit Watt";  # Shelly2: up to 1840 Watt
      Log3 $name,1,"[Shelly_Attr] $name\: $error";
      return $error;
    }
    if($shelly_models{$model}[4]==0 ){ #1st Gen
        Shelly_HttpRequest($hash,"/settings","?max_power=$attrVal","Shelly_response","config" );
    }elsif( $mode eq "roller" ){ #2ndGen  %26 =    %22  "
        Shelly_HttpRequest($hash,"/rpc/Cover.SetConfig","?id=0&config={%22power_limit%22:$attrVal}","Shelly_response","config" );
    }elsif( $mode eq "relay" ){ #2ndGen  %26 =    %22  "
        Shelly_HttpRequest($hash,"/rpc/Switch.SetConfig","?id=0&config={%22power_limit%22:$attrVal}","Shelly_response","config" );
        Shelly_HttpRequest($hash,"/rpc/Switch.SetConfig","?id=1&config={%22power_limit%22:$attrVal}","Shelly_response","config" );
    }else{
      Log3 $name,1,"[Shelly_Attr] $name\: have not set $attrVal";
    }

  #---------------------------------------
  # Gen1:  maxtime  only in older firmware
  # newer fw:  maxtime_open, maxtime_close
  }elsif( $cmd eq "set" && $attrName =~ /maxtime/ ){
    if( ($shelly_models{$model}[1] == 0 || $mode ne "roller" ) && $init_done ){
      $error="Setting the maxtime attribute only works for devices in roller mode";
      Log3 $name,1,"[Shelly_Attr] $name\: $error model=shelly2/2.5/plus2/pro2 and mode=roller";
      return $error;
    }
    if( $attrVal<1 || $attrVal>300 ){
      $error="Maxtime must be within the range 1...300 Seconds";
      Log3 $name,1,"[Shelly_Attr] $name\: $error";
      return $error;
    }
    if($shelly_models{$model}[4]==0 ){ #1st Gen
        # Gen1:  using maxtime will set maxtime_open and maxtime_close!
        Shelly_HttpRequest($hash,"/settings/roller/0","?$attrName=".int($attrVal),"Shelly_response","config" );
    }else{ #2nd Gen  %26 =    %22  "
        Shelly_HttpRequest($hash,"/rpc/Cover.SetConfig","?id=0&config={%22$attrName%22:$attrVal}","Shelly_response","config" );
    }

  #---------------------------------------
  }elsif( $cmd eq "set" && $attrName eq "slat_control" ){
      $error="The slat_control attribute is set by \'get <name> settings\' only";
  #    Log3 $name,1,"[Shelly_Attr] $name\: $error ";
  #    return $error;
  #---------------------------------------
  }elsif( $cmd eq "set" && $attrName eq "slat_pos" ){
      if( $attrVal<0 || $attrVal>100 ){
          $error="slat_pos must be within the range 0...100";
          Log3 $name,1,"[Shelly_Attr] $name\: $error";
          return $error;
      }
  #---------------------------------------
  }elsif( $cmd eq "set" && $attrName eq "pct100" ){
    if( ($shelly_models{$model}[1] == 0 || $mode ne "roller") && $init_done ){
      $error="Setting the pct100 attribute only works for devices in roller mode";
      Log3 $name,1,"[Shelly_Attr] $name\: $error model=shelly2/2.5/plus2/pro2 and mode=roller";
      return $error;
    }
    if($init_done){
      # perform an update of the position related readings
      #-- scheduling next status update
      Shelly_status($hash,"Shelly_Attr",1.0);
    }
  #---------------------------------------
  }elsif( $attrName =~ /Energymeter/ ){  # Energymeter_F  ..._P   ..._R
    if($cmd eq "set" ){
      if( $model ne "shellypro3em" ){
        $error="Setting the \"$attrName\" attribute only works for ShellyPro3EM ";
        Log3 $name,1,"[Shelly_Attr] $name\: $error ";
        return $error;
      }
      if( $attrVal !~ /[\d.]/ ){
        $error="The value of \"$attrName\" must be a positive value representing the meters value in \’Wh\' ";
        Log3 $name,1,"[Shelly_Attr] $name\: $error ";
        return $error;
      }
      # return the attribute value reduced by actual content of meter
      $_[3] = $attrVal - ($hash->{helper}{$attrName}//0); # helper not defined ? 
      # set the reading to the "actual meter value"
      readingsSingleUpdate($hash,"Total_$attrName",shelly_energy_fmt($hash,$attrVal,"Wh" ),1);

    #---------------------------------------
    }elsif( $cmd eq "del" ){
      fhem("deletereading $name Total_$attrName");
    }

  #---------------------------------------
  }elsif( ($cmd eq "set" || $cmd eq "del") && ( $attrName eq "EMchannels") ){
    if( $model ne "shellypro3em" ){
      $error="Setting of the attribute \"$attrName\" only works for ShellyPro3EM ";
      Log3 $name,1,"[Shelly_Attr] $name\: $error ";
      return $error;
    }

    return undef if($attrVal eq AttrVal($name,"EMchannels",""));
    fhem("deletereading $name a_.*");
    fhem("deletereading $name b_.*");
    fhem("deletereading $name c_.*");
    fhem("deletereading $name A_.*");
    fhem("deletereading $name B_.*");
    fhem("deletereading $name C_.*");
    fhem("deletereading $name T_.*");
    fhem("deletereading $name L._.*");
    fhem("deletereading $name TTL.*");
    fhem("deletereading $name .*_total");
    fhem("deletereading $name .*_a");
    fhem("deletereading $name .*_b");
    fhem("deletereading $name .*_c");
    fhem("deletereading $name .*_T.*");
    fhem("deletereading $name .*_A");
    fhem("deletereading $name .*_B");
    fhem("deletereading $name .*_C");
    fhem("deletereading $name .*_L.");
    fhem("deletereading $name .*_calc.*");
    fhem("deletereading $name .*_integr.*");

    ## "Please use a browser refresh to make the readings visible";

  #---------------------------------------
  }elsif( $attrName eq "Balancing" ){
  #  if( $model ne "shellypro3em" && $init_done){
    if( ReadingsVal($name,"model_profile","monophase") ne "triphase" && $init_done){
      $error="Setting of the attribute \"$attrName\" only works for ShellyPro3EM in triphase profile";
      Log3 $name,1,"[Shelly_Attr] $name\: $error ";
      return $error;
    }
    if( AttrVal($name,"interval_power",AttrVal($name,"interval",$defaultINTERVAL))>20 && $attrVal == 1 && $init_done ){  # $hash->{INTERVAL}
      $error="For using the \"Balancing\" the interval must not exceed 20 seconds";
      Log3 $name,1,"[Shelly_Attr] $name\: $error ";
      return $error;
    }
    if( $cmd eq "del" || $attrVal == 0 ){
      fhem("deletereading $name .*_T");
      fhem("deletereading $name .*_T_.*");
    }elsif( $cmd eq "set" && $init_done ){
      # intialize the Total-Readings "_T"
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,"Purchased_Energy_T",ReadingsVal($name,"Total_Energymeter_P",AttrVal($name,"Energymeter_P",0)." kWh"),1);
      readingsBulkUpdate($hash,"Returned_Energy_T",ReadingsVal($name,"Total_Energymeter_R",AttrVal($name,"Energymeter_R",0)." kWh"),1);
      readingsBulkUpdate($hash,"Total_Energy_T",ReadingsVal($name,"Total_Energymeter_F",AttrVal($name,"Energymeter_F",0)." kWh"),1);
      readingsEndUpdate($hash,1);
    }
  #---------------------------------------
  }elsif( $attrName eq "Periods" ){
    if( $shelly_models{$model}[6]==0 && $model ne "shellypmmini" && $init_done ){ # $model ne "shellypro3em" && $model ne "shellyproem50"
      $error="Setting of the attribute \"$attrName\" only works for ShellyPro3EM / ShellyPro50EM / ShellyPMmini";
      Log3 $name,1,"[Shelly_Attr] $name\: $error ";
      return $error;
    }
    my $RP; # Readings-postfix
    my @keys = keys %periods;   #"min","hourT","hourQ","hour","dayQ","dayT","day","Week", Month, "Year"
    if( $cmd eq "del"){
        foreach $RP ( @keys ){
            fhem("deletereading $name .*_$RP");
            Log3 $name,1,"[Shelly_Attr] deleted readings $name\:.*_$RP ";
        }
        fhem("deleteattr $name PeriodsCorr-F");
        Log3 $name,1,"[Shelly_Attr] $name\: deleted attributes \'Periods\' and \'PeriodsCorr-F\' ";
    }elsif( $cmd eq "set" && $init_done ){
        my $av=$attrVal.',';
        my $AV=AttrVal($name,"Periods","").",";
        foreach $RP ( @keys ){
          my $rp=$RP.',';
          if( $av !~ /$rp/ && $AV =~ /$rp/){
              fhem("deletereading $name .*_$RP");
              Log3 $name,1,"[Shelly_Attr] deleted readings $name\:.*_$RP ";
          }
          # check if attrVal is not existing in the attribute -> new
          if( $av =~ /$rp/ && $AV !~ /$rp/ ){
              my $energy;
              my $factor=$energy_units{AttrVal($name,"showunits","none")}[1];  # normalize readings values to "Wh"
              my @readings = ("energy");
              if( $shelly_models{$model}[6]>0 ){  # $model =~ /shellypro3em|shellyproem50/
                  @readings = ("Purchased_Energy_S","Returned_Energy_S","Total_Energy_S");
                  push( @readings,"Purchased_Energy_T","Returned_Energy_T","Total_Energy_T" ) if(AttrVal($name,"Balancing",0) == 1);
              }
              foreach my $reading ( @readings ){
                if( ReadingsVal($name,"$reading\_$RP",undef) ){
                  Log3 $name,1,"[Shelly_Attr] $name\: reading $reading\_$RP\' already existing!";
                }else{
                  $energy = shelly_energy_fmt($hash,0,"Wh");
                  $energy.= " (";
                  $energy.= ReadingsNum($name,$reading,0.0)/$factor;
                  $energy.= ") 0.0 W";
                  Log3 $name,1,"[Shelly_Attr] $name\: adding reading $reading\_$RP\' and init to \'$energy\' ";
                  readingsSingleUpdate($hash,"$reading\_$RP",$energy,1);
                }
              }
          }
        }
    }else{
            Log3 $name,3,"[Shelly_Attr] no readings deleted";
    }
  #---------------------------------------
   }elsif( $attrName eq "webhook" ){
     if( $init_done==1 ){
        if( $cmd eq "del" ){
            Log3 $name,3,"[Shelly_Attr:webhook] $name: deleted attr webhook --> according actions set disabled";
            Shelly_Set($hash,$name,"actions","disable");
        }else{
            Log3 $name,3,"[Shelly_Attr:webhook] $name: changed attr webhook --> updating according actions";
            Shelly_Set($hash,$name,"actions","update");
        }
     }
     return;
  #---------------------------------------
  }elsif( $attrName eq "interval" ){
    if( $cmd eq "set" ){
      if( $attrVal =~ /[\D]/ ){
          $error="The value of \"$attrName\" must be 0 or a positive integer value representing the interval in seconds ";
          Log3 $name,1,"[Shelly_Attr] $name\: $error ";
          return $error;
      }elsif( $attrVal == 0 ){
          readingsSingleUpdate( $hash,"state","disabled",1 );
          readingsSingleUpdate($hash,"/_nextUpdateTimer","disabled",1)
                                        if( AttrVal($name,'timeout',undef) );
      }
      #-- update timer
      if(0&& $model eq "shellypro3em" && $attrVal > 0 ){
        # restart the 2nd timer (only when stopped)
        # adjust the timer to one second after the full minute
        InternalTimer(int((time()+60)/60)*60+1, "Shelly_shelly", $hash, 1)
                 if( AttrVal($name,"interval",-1) == 0 );

        # adjust the 1st timer to 60
        my @teiler=(1,2,3,4,5,6,10,12,15,20,30,60);
        my @filter = grep { $_ >= $attrVal } @teiler ;
        $attrVal = ($attrVal >60 ? int($attrVal/60)*60 : $filter[0]);
        $_[3] = $attrVal;
      }
      $hash->{INTERVAL} = int($attrVal);
    }elsif( $cmd eq "del" ){
      $hash->{INTERVAL} = $defaultINTERVAL;
    }
    if( $init_done ){  ## && $hash->{INTERVAL} != 0
      Shelly_Set($hash,$name,"startTimer");
    }
  #---------------------------------------
  }elsif( $attrName eq "interval_power" && $cmd eq "set" ){
    #-- update timer for power-readings of EnergyMeter (ShellyPro3EM,ShellyProEM50)
    if( $shelly_models{$model}[6]==0 ){  # $model ne "shellypro3em" && $model ne "shellyproem50"
         return "wrong model";
    }
    if( $attrVal =~ /\D/ || $attrVal == 0 ){
          $error="The value of \"$attrName\" must be a positive integer value representing the power-interval in seconds ";
          Log3 $name,1,"[Shelly_Attr] $name\: $error ";
          return $error;
    }
    if( $init_done && $hash->{INTERVAL} != 0 ){
      RemoveInternalTimer($hash,"Shelly_getEMvalues");
      InternalTimer(time()+$attrVal, "Shelly_getEMvalues", $hash);
    }
    if( $init_done ){
      Shelly_Set($hash,$name,"startTimer");
    }
  #---------------------------------------
  }elsif( $attrName eq "defchannel" ){
    if( ($shelly_models{$model}[0] < 2 && $mode eq "relay") || ($model eq "shellyrgbw" && $mode ne "white") ){
      $error="Setting the \'defchannel\' attribute only works for devices with multiple outputs/relays";
      Log3 $name,1,"[Shelly_Attr] $name\: $error ";
      return $error;
    }
    if( $attrVal eq "all" ){
    #..
    }elsif( $attrVal =~ /\D/ ){  # checking if there is anything else than a digit
        $error="The value of \"$attrName\" must be a positive integer";
        Log3 $name,1,"[Shelly_Attr] $name\: $error ";
        return $error;
    }
  #---------------------------------------
  }elsif( $attrName eq "webCmd" ){
        Log3 $name,5,"[Shelly_Attr] $name: webCmd is set to $attrVal";
  #---------------------------------------
  }elsif( $attrName eq "shellyuser" ){
        Log3 $name,5,"[Shelly_Attr] $name: shellyuser is set to $attrVal";
  #---------------------------------------
  }elsif( $attrName eq "verbose" ){
        Log3 $name,5,"[Shelly_Attr] $name: verbose level is changed or deleted";
  }elsif( $attrName eq "timeout" ){
        if( $cmd eq 'del' ){
            Log3 $name,3,"[Shelly_Attr] $name: attr timeout is deleted, response time readings will be deleted";
            fhem("deletereading $name /.*",1); #delete process time readings / silent
        }else{
            Log3 $name,3,"[Shelly_Attr] $name: attr timeout is set or changed";
        }
  }
  #---------------------------------------
  return undef;
} #end Shelly_Attr


########################################################################################
#
# Shelly_Notify -  Implements NotifyFn function
#
# Parameter:       hash ("own" device),
#                  device hash (the device that generates an event)
#
########################################################################################

sub Shelly_Notify($$) {
	my ($hash,$dev) = @_;
	my $name = $hash->{NAME};
	Log3 $name,6,"[Shelly_Notify] $name: processing Notify dN=".$dev->{NAME}; #5
	return if($dev->{NAME} ne "global");
	return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));	
	return if( defined($hash->{SUBTYPE}) );
	
        # complete readings
        # only Shelly-BLU devices have internal SUBTYPE
        if( !defined($hash->{SUBTYPE})  &&  ReadingsVal($name,"model_function","unknown") eq "unknown" ){
           # Shelly_getModel($hash);
            Shelly_HttpRequest($hash,"/shelly","","Shelly_getModel" );
        }
        
	my $interval = AttrVal($name,"interval",$defaultINTERVAL);
	if( $interval == 0 ){
            # device is disabled (AttrVal get real value, as we are initilized!)
	    $hash->{INTERVAL} = 0;
	    Log3 $name,3,"[Shelly_Notify] $name is disabled (no polling)";
	    return;
	}
        $hash->{INTERVAL} = $interval; # Updates each minute, if not set as attribute
	Log3 $name,4,"[Shelly_Notify] $name: starting timer ($interval sec) and calling actions update"; #3
	Shelly_Set($hash,$name,"startTimer");
        Shelly_Set($hash,$name,"actions","update");
        
	return undef;
} #end Shelly_Notify()


########################################################################################
#
# Shelly_Get -  Implements GetFn function
#
# Parameter hash, argument array
#
########################################################################################

sub Shelly_Get ($@) {
  my ($hash, @a) = @_;

  #-- check syntax
  my $name = $hash->{NAME};
  my $v;

  Log3 $name,5,"[Shelly_Get] receiving command get $name ".$a[1].($a[2]?" ".$a[2]:"").($a[3]?" ".$a[3]:"") ;

  my $model =  AttrVal($name,"model","generic");
  my $mode  =  AttrVal($name,"mode","");

  #-- get version
  if( $a[1] eq "version") {
    return "$name.version => $version";

  #-- get actions
  }elsif($a[1] eq "actions") {
    if( $shelly_models{$model}[4]==0 ){
         Shelly_HttpRequest($hash,"/settings/actions",undef,"Shelly_settings1G" );
    }else{
         Shelly_HttpRequest($hash,"/rpc/Webhook.List",undef,"Shelly_settings2G","actions" );
    }
  #-- autodetect model "get model"
  }elsif($a[1] eq "model") {
  #  $v = Shelly_getModel($hash);
  # delete $hash->{SHELLY};
          Shelly_HttpRequest($hash,"/shelly","","Shelly_getModel" );

  #-- current status
  }elsif($a[1] eq "status") {
    $v = Shelly_status($hash,"Shelly_Get");

  #-- current settings of shelly
  }elsif($a[1] eq "settings" ) {
    if( $shelly_models{$model}[4]==0 ){
         Shelly_HttpRequest($hash,"/settings",undef,"Shelly_settings1G" );
    }else{
         Shelly_HttpRequest($hash,"/rpc/Shelly.GetConfig",undef,"Shelly_settings2G","config" );
    }
    $v = "Done.";

  #-- GET some help on registers
  }elsif($a[1] eq "registers") {
    return "Please get registers of 2nd-Gen devices via Shelly-App or homepage of the Shelly"
                    if( $shelly_models{$model}[4]>=1 );  # at the moment, we do not handle registers of Gen2-Devices -> ToDo
    my ($txt,$txt2);
    if( ($model =~ /shelly2.*/) && ($mode eq "roller") ){
      $txt = "roller";
    }elsif( $model eq "shellydimmer" ){
      $txt = "light";
    }elsif( ($model eq "shellyrgbw" || $model eq "shellybulb") && ($mode eq "white") ){    # but use /settings/light/{}";
      $txt  = "bulbw";
      $txt2 = "white" if( $model eq "shellyrgbw" );  #some more settings
    }elsif( ($model eq "shellyrgbw" || $model eq "shellybulb") && ($mode eq "color") ){
      $txt = "color";
    }elsif( $model eq "shellyi3" ){
      $txt = "input";
    }else{
      $txt = "relay";
    }
    $txt  = $shelly_regs{"$txt"};
    $txt .= $shelly_regs{"$txt2"} if( defined($txt2) );

    return $txt."\n\nSet/Get these registers by calling set/get $name config  &lt;registername&gt; &lt;value&gt; [&lt;channel&gt;]";

  #-- GET configuration register
  }elsif($a[1] eq "config") {
    return "Please set/get configuration of 2nd-Gen devices via Shelly-App or homepage of the Shelly"
                    if( $shelly_models{$model}[4]>=1 );  # at the moment, we do not handle configuration of Gen2-Devices  -> ToDo
    my $reg = $a[2];
    my ($val,$chan);
    if( int(@a) == 4 ){
      $chan = $a[3];
    }elsif( int(@a) == 3 ){
      $chan = 0;
    }elsif( int(@a) == 2 ){
      $reg = "";
      $chan = undef;
    }else{
      my $msg = "Error: wrong number of parameters";
      Log3 $name,1,"[Shelly_Get] ".$msg;
      return $msg;
    }

    my $pre = "/";
    if( $reg ne "" ){
      if( ($model =~ /shelly2.*/) && ($mode eq "roller") ){  ##R  (plus|pro)?
        $pre .= "roller/0?";   # do not use 'rollers'
      }elsif( $model eq "shellydimmer" ){
        $pre .= "light/0?";
      }elsif( ($model eq "shellyrgbw" || $model eq "shellybulb") && ($mode eq "white") ){
        $pre .= "light/$chan?";       # !white
      }elsif( ($model eq "shellyrgbw" || $model eq "shellybulb") && ($mode eq "color") ){
        $pre .= "color/0?";
      }elsif( defined($chan)){
        $pre .= "relay/$chan?";
      }
    }else{
      my $msg = "Error: wrong number of parameters, no register given";
      Log3 $name,1,"[Shelly_Get] $name: $msg";
      return $msg;
    }
    Shelly_HttpRequest($hash,"/settings",$pre.$reg,"Shelly_response","getconfig");
    return "$a[0] $a[1] $a[2] $a[3]\n\nsee reading \'config\' for result";

  #-- get colors of PLUG-S via PLUGS_UI
  }elsif( $a[1] eq "colors" ){    
      if( ReadingsVal( $name, "model_ID", "" ) !~ /^S.PL-\d\d112EU$/ ){
              my $err = "Plug user interface not supported by this model";
              Shelly_error_handling($hash,"PLUGS_UI_GetConfig",$err,1);
              return $err;          
      }
      Shelly_HttpRequest($hash,"/rpc/PLUGS_UI.GetConfig",undef,"PLUGS_UI_GetConfig","Get" );

  #-- create readingsGroup device 
  }elsif( $a[1] eq "readingsGroup" ){
      my $rgName = "rgShelly".$a[2];
      my $rgRoom = AttrVal($rgName,"room","Shelly->".$a[2]);
      $rgRoom =~ s/,.*//;  # use only first room
      Log3 $name,4,"[Shelly_Get] readingsGroup device \'$rgName\' requested by \'$name\', placed in room \'$rgRoom\'";
      my $msg; 
      #~~~~ ***Device***
      if( $rgName eq "rgShellyDevice" ){
          fhem("defmod $rgName readingsGroup <Name>,<Definition>,<MAC>,<Model-ID>,<Shelly-ID>,<Model-Name>,<Function>,<Family>,<ShellyName>,<?ModelAttr>,<UptimeHrs>,<Units>,<Verbose>,<Subtype>
                            .*:FILTER=TYPE=Shelly:+DEF,mac,model_ID,+SHELLYID,model_name,model_function,model_family,name,?model,uptime,+units,?verbose,+SUBTYPE");  
          fhem("attr $rgName sortColumn 0"); 
          fhem("attr $rgName valueColumn { DEF=>1, model_name=>5, model_function=>6, model_family=>7, name=>8, model=>9, uptime=>10, SUBTYPE=>13 }");
          fhem("attr $rgName valueFormat { \$READING eq 'uptime'?int(ReadingsNum(\$DEVICE,\$READING,0)/3600):\$VALUE }");
      #~~~~ ***Firmware***
      }elsif( $rgName eq "rgShellyFirmware" ){
          fhem("defmod $rgName readingsGroup <Name>,<Definition>,<Family>,<Firmware>,<Text>,<>,<ID>  
                            .*:FILTER=TYPE=Shelly:+DEF,model_family,firmware_current,firmware_updText,firmware_updIcon,firmware_ID");
          fhem("attr $rgName valueColumn { DEF=>1, firmware_current=>3}");
          fhem("attr $rgName valueFormat { DEF=>\'<a href=\"http://\$VALUE\">\$VALUE</a>\' }");
          fhem("attr $rgName valueIcon { 
             \"firmware_updIcon.M\" => \"rc_dot\\\@purple\",
             \"firmware_updIcon.m\" => \"rc_dot\\\@red\",
             \"firmware_updIcon.p\" => \"rc_dot\\\@orange\",
             \"firmware_updIcon.B\" => \"rc_dot\\\@lightgreen\",
             \"firmware_updIcon.D\" => \"rc_dot\\\@yellowgreen\",
             \"firmware_updIcon.OK\" => \"rc_dot\",
             \"firmware_updIcon.U\" => \"refresh\"
             }");
          fhem("attr $rgName commands { 
             \"firmware_updIcon.M\" => \"set \%DEVICE update\",
             \"firmware_updIcon.m\" => \"set \%DEVICE update\",
             \"firmware_updIcon.p\" => \"set \%DEVICE update\",
             \"firmware_updIcon.U\" => \"get \%DEVICE status\"
             }");
      #~~~~ ***Network***
      }elsif( $rgName eq "rgShellyNetwork" ){
          fhem("defmod $rgName readingsGroup <Name>,<Definition>,<MAC>,<Connection>,<Host>,<SSID>,<RSSI>,<Roaming>,<COIOT>,<BT>,<Cloud>,<AP>,<Clients>,<Disconn>,<DNS_name>,<Webhook> 
                            .*:FILTER=TYPE=Shelly:+DEF,mac,network_connection,network_host,network_ssid,network_rssi,network_wifi_roaming,coiot,ble,cloud,ap,ap_clients,network_disconnects,network_DNS,?webhook");
          fhem("attr $rgName valueColumn { DEF=>1, network_connection=>3,network_host=>4,network_ssid=>5,network_rssi=>6,network_wifi_roaming=>7, coiot=>8,ble=>9,cloud=>10,ap=>11,ap_clients=>12,network_disconnects=>13,network_DNS=>14 }");
          fhem("attr $rgName valueFormat { DEF=>\'<a href=\"http://\$VALUE\">\$VALUE</a>\' }");
          fhem("attr $rgName valueIcon { \"network_connection.offline\" => \"15px-red\",
             \"network_connection.online\"  => \"it_wifi\\\@green\",
             \"network_connection.online (Wifi)\"  => \"it_wifi\\\@black\",
             \"network_connection.online (LAN)\"   => \"it_network\\\@black\",
             \"network_connection.remote\"         => \"it_wifi\\\@orange\",
             \"ble.enabled\"    => \"bluetooth\\\@blue\",
             \"ble.disabled\"   => \"15px-red\",
             \"cloud.enabled(connected)\"  => \"it_i-net\",
             \"cloud.enabled(not connected)\"  => \"it_i-net\\\@red\",
             \"cloud.disabled\"   => \"15px-red\",
             \"coiot.enabled\"    => \"15px-green\",
             \"coiot.disabled\"   => \"15px-red\",
             \"ap.disabled open\" => \"15px-red\",
             \"ap.enabled open\"  => \"15px-blue\",
             \"ap.enabled password\" => \"15px-green\",
             \"ap_clients.disabled\" => \"-\"
             }");
          fhem("attr $rgName commands {}");
      #~~~~ ***Status***
      }elsif( $rgName eq "rgShellyStatus" ){
            fhem("defmod $rgName readingsGroup <Name>,<Definition>,<mode>,<Interv>,<interv>,<State>,<Relay>,<Volt>,<intTemp>,<intTempStatus>,<InputMode> 
                            .*:FILTER=TYPE=Shelly:+DEF,?mode,?interval,+INTERVAL,state,relay,voltage,inttemp,inttempStatus,input_mode"  );    
          fhem("attr $rgName sortColumn 0"); 
          fhem("attr $rgName valueColumn { DEF=>1, mode=>2, interval=>3, INTERVAL=>4, state=>5, relay=>6, voltage=>7,inttemp=>8, inttempStatus=>9, input_mode=>10 }"); 
      }
      fhem("attr $rgName room $rgRoom");   # 
      $msg = "see readingsGroup device \'$rgName\' in room \'$rgRoom\'";
      Log3 $name,1,"[Shelly_Get] $msg";
      return $msg; 
  #~~~~

  }elsif( $a[1] eq "?" ){
    my $newkeys = $shelly_dropdowns{Gets};   ## join(" ", sort keys %gets);
    $newkeys .= $shelly_dropdowns{Colors}
                                    if( $model eq "shellyplusplug" && ReadingsVal( $name, "model_ID", "" ) =~ /EU$/); ## Shelly Plug-S Gen2+ 
    $newkeys =~  s/:noArg//g
      if( $a[1] ne "?");
    my $msg = "unknown argument ".$a[1].", choose one of $newkeys";
    Log3 $name,6,"[Shelly_Get] $name: $msg";
    return $msg;
  }else{   #anything else
    my $msg = "unknown argument ".$a[1];
    Log3 $name,5,"[Shelly_Get] $name: $msg";
    return $msg;
  }
  return undef;
} #end Shelly_Get

########################################################################################
#
# Shelly_Set - Implements SetFn function
#
# Parameter hash, a = argument array
#
########################################################################################

sub Shelly_Set ($@) {
  my ($hash, @a) = @_; 
  my $name  = shift @a;
  my $cmd   = shift @a;  my @args=@a;  

  my $parameters;  ##=( scalar(@a)?" and ".scalar(@a)." parameters: ".join(" ",@a) : ", no parameters" );
  if( defined($cmd) && $cmd ne "?"){
      if( scalar(@a) ){
          $parameters= join(" ",@a); 
          $parameters = " and ".scalar(@a)." parameters: ".$parameters;
      }else{
          $parameters=", no parameters" ;
      }
      readingsSingleUpdate($hash,"/_set.command",join(" ",$cmd,@a),1)  if( AttrVal($name,"timeout",undef) );
      Log3 $name,4,"[Shelly_Set] calling for device $name with command \'$cmd\'$parameters";  #4
  }elsif( !defined($name) ){
      $name = $hash->{NAME};
      Log 1,"called set without a device-name, set name to $name";
  }
    
  my $value = shift @a;  # 1st parameter

  #-- when Shelly_Set is called by 'Shelly_Set($hash)' arguments are not handed over, look for a temporarely stored command in internals
  if( !defined($cmd) ){
      if( defined($hash->{CMD}) ){
          $cmd  = $hash->{CMD};
          Log3 $name,4,"[Shelly_Set] get command \'$cmd\' from internal";
          delete $hash->{CMD};
      }else{
          Log3 $name,5,"[Shelly_Set] no command given";
          return "no command given, choose one from ".$hash->{helper}{Sets};
      }
  }

  my $model =  AttrVal($name,"model","generic");   # formerly: shelly1
  my $mode  =  AttrVal($name,"mode","");
  my ($msg,$channel,$time,$brightness,$transit);


  #-- WEB asking for command list
  if( $cmd eq "?" ){
    my $newkeys;
    if( !defined($hash->{helper}{Sets}) ){
      # all models and generic
      $newkeys = $shelly_dropdowns{Shelly};
      $newkeys =~ s/config/config:ap_disable,ap_enable/ if( $shelly_models{$model}[4]>=1 );
      # Gen2 devices only
      $newkeys .= $shelly_dropdowns{Actions}
                                    if( $shelly_models{$model}[4]>-1 ); ## all Gens
      $newkeys .= $shelly_dropdowns{Scripts}
                                    if( $shelly_models{$model}[4]>=1 ); ## Gen2+
      $newkeys .= $shelly_dropdowns{PlugsUI}
                                    if( $model eq "shellyplusplug" && ReadingsVal( $name, "model_ID", "" ) =~ /EU$/); ## Shelly Plug-S Gen2+  EU-Type                                  
      # most of devices, except roller, metering
      $newkeys .= $shelly_dropdowns{Onoff}
                                    if( ($mode ne "thermostat" && $mode ne "roller" && $shelly_models{$model}[0]>0) ||  $shelly_models{$model}[2]>0 || $shelly_models{$model}[7]>0 );
      $newkeys .= $shelly_dropdowns{Therm}
                                    if( $model =~ /walldisplay/ );
      # multichannel devices
      $newkeys .= $shelly_dropdowns{Multi} if( ($mode ne "roller" && $shelly_models{$model}[0]>1) || ($shelly_models{$model}[2]>1 && $mode eq "white") );
      if( $mode eq "roller" || ($shelly_models{$model}[0]==0 && $shelly_models{$model}[1]>0)){
          $newkeys .= $shelly_dropdowns{Rol};
      }elsif( $shelly_models{$model}[2] > 0 && $mode ne 'color' ){
               #$model =~ /shellydimmer/ || ($model =~ /shellyrgbw.*/ && $mode eq "white") || $model eq "shellyplus010v" ){
          $newkeys .= $shelly_dropdowns{RgbwW};
          $newkeys .= " calibrate:noArg"   if( $model =~ /shellydimmer/ );
          $newkeys .= " minmaxbrightness btn_fade_rate:1,2,3,4,5 transition_duration:slider,0.5,0.1,5 min_brightness_on_toggle"
                        if(0 && $model =~ /shellyplus010v/ );  # uzsuDropDown
      }elsif( $model =~ /shellybulb.*/ &&  $mode eq "white" ){
          $newkeys .= " dim-for-timer".$shelly_dropdowns{BulbW};
          foreach my $cmd ( 'on','off','toggle' ){
              $newkeys =~ s/$cmd /$cmd:noArg /g;
          }
      }elsif( $model =~ /shelly(rgbw|bulb).*/ && $mode eq "color" ){
          $newkeys .= $shelly_dropdowns{RgbwC};
      }elsif( $shelly_models{$model}[5]==1 ){ # devices with one input only
          $newkeys .= $shelly_dropdowns{Input};
          $newkeys .= $shelly_dropdowns{Input1}  if( $model =~ /Shelly1/ );
      }
      if( $shelly_models{$model}[4]==0 || $shelly_models{$model}[3]==0 ){
          $newkeys =~ s/,energy//; # remove 'energy' from dropdown-list
      }
      if( $shelly_models{$model}[2] == 1 ){ # one channel only, eg 'shellyplus010v'
          $newkeys =~ s/on /on:noArg /;
          $newkeys =~ s/off /off:noArg /;
          $newkeys =~ s/toggle /toggle:noArg /;
      }
      if( $init_done ){
        $hash->{helper}{Sets}=$newkeys;
        Log3 $name,5,"[Shelly_Set] stored keys for device $name \"$newkeys\" in helper";
      }
    }else{
      $newkeys = $hash->{helper}{Sets};
    }

    Log3 $name,6,"[Shelly_Set] FhemWeb is requesting set-commands for device $name"; #4
    #$hash->{'.FWR'}=$hash->{'.FWR'}+1;
    # ':noArg' will be stripped off by calling instance

    return SetExtensions($hash,$hash->{helper}{Sets},$name,$cmd,@args);
  } # set ... ?

  #-- following commands do not occur in command list, eg. out_on, input_on, single_push
  #-- command received via web to register local changes of the device
  if( $cmd =~ /^(out|button|input|short|single|double|triple|long|touch|voltage|temperature|humidity|Active_Power|Voltage|Current)_(on|off|push|up|down|multi|over|under|a|b|c|changed)/
              ||  $cmd =~ /(analog_in|voltmeter|power|voltage|current|tempC|humidity|illuminance|illumination)/ ){
    my $signal=$1;
    my $isWhat=$2;
    my $subs;
    Log3 $name,6,"[Shelly_Set] calling for device $name with command $cmd".( defined($value)?" and channel $value":", without channel" ).
                                                                            (defined($isWhat)?", iswhat=$isWhat":", isWhat not defined"); #6
    readingsBeginUpdate($hash);
    
    readingsBulkUpdateMonitored($hash,"/_set.command","$cmd $parameters") if( AttrVal($name,"timeout",undef) );
    if( $cmd =~ /^(out)/ ){
       my $channels = maxNum($shelly_models{$model}[0],$shelly_models{$model}[2]); # device has one or more relay or dimmer - channels
       $channels = 1  if( !$value );  #no channel given - change of single channel device output

       if( $cmd !~ /(on|off)$/ ){
          Shelly_error_handling($hash,"Shelly_Set:out","No handler for command <$cmd>",1);
       }elsif( $channels == 1 ){   # single channel device
          readingsBulkUpdateMonitored($hash,"relay",$isWhat) if( $shelly_models{$model}[0] > 0 );  # a relay device
          readingsBulkUpdateMonitored($hash,"state",$isWhat);
       }elsif( $value =~ /\D/ || $value >= $channels ){ # check if channel is anything else than a digit or wrong number
          Shelly_error_handling($hash,"Shelly_Set:out","Wrong channel <$value> for command <$cmd>",1);
       }elsif( $shelly_models{$model}[0] > 1 ){
          readingsBulkUpdateMonitored($hash,"relay_$value",$isWhat);
       }elsif( $shelly_models{$model}[2] > 1 ){
          readingsBulkUpdateMonitored($hash,"state_$value",$isWhat);
       }else{
          Shelly_error_handling($hash,"Shelly_Set:out","no handler for command <$cmd>",1);
       }
    }elsif( $signal eq "button" ){   # ShellyPlug(S)   # button_on
          if( $shelly_models{$model}[5]==0 ){
              Log3 $name,6,"[Shelly_Set] WARNING: command button_on|button_off not allowed for device $name";
          }
          $subs = ( abs($shelly_models{$model}[5])==1 || !defined($value) ) ? "" : "_".$value;
          readingsBulkUpdateMonitored($hash, "button$subs", $isWhat, 1 );
    }elsif( $signal eq "input" ){    # devices with an input-terminal
          $subs = ($shelly_models{$model}[5] == 1) ? "" : "_".$value;
          readingsBulkUpdateMonitored($hash, "input$subs", $isWhat, 1 );
    }elsif( $signal =~ /^(single|double|triple|short|long)/ ){
          $subs = (abs($shelly_models{$model}[5]) == 1) ? "" : "_".$value;
          readingsBulkUpdateMonitored($hash, "input$subs", "ON", 1 );
          readingsBulkUpdateMonitored($hash, "input$subs\_action", $cmd, 1 );
          readingsBulkUpdateMonitored($hash, "input$subs\_actionS",$fhem_events{$cmd}, 1 );
          # Note: after a second, the pushbuttons state is back to OFF resp. 'unknown', call status of inputs
          #-- scheduling next status update
          Shelly_status($hash,"Shelly_Set inp",1.4);
    }elsif( $signal eq "touch" ){    # devices with an touch-display
          #$subs = ($shelly_models{$model}[5] == 1) ? "" : "_".$value;
          readingsBulkUpdateMonitored($hash, "touch", $isWhat, 1 );
    }elsif( $signal =~ /(over|under)/ ){
          $subs = defined($value)?"_".$value:"" ;
          readingsBulkUpdateMonitored($hash,$signal.$subs."_range", $isWhat );
    }elsif( $signal =~ /^(tempC)/ ){
          $subs = defined($a[0])?"_".$a[0]:"" ;
          Shelly_readingsBulkUpdate($hash,"temperature".$subs, $value,"tempC");
    }elsif( $signal =~ /^(Xtemperature|Xhumidity|illuminance|illumination)/ ){
          $subs = defined($a[0])?"_".$a[0]:"" ;
          if( $signal eq "illumination" && ReadingsAge($name,"illuminance".$subs,0) > 2.5 ){ # to cover a bug in Shellies fw (no $ev.illuminance known)
              # readingsBulkUpdateMonitored($hash,"illuminance".$subs, "-" );
              Shelly_status($hash,"Shelly_Set sens");
          }else{
              Shelly_readingsBulkUpdate($hash,$signal.$subs,$value,$signal );
          }
    }elsif( $cmd =~ /^(power|voltage|current|temperature|humidity)/ ){  #as by ShellyPMmini, ShellyUni, ...

          my $channels = $shelly_models{$model}[3]; # number of metering channels
          $channels = 1 if( $model =~ /uni/ ); # ShellyUni or ShellyPlusUni
          $channels = 1 if( $model =~ /display/ && $cmd =~ /^(temperature|humidity)/ ); #
          $channels = 10 if( ReadingsVal($name,"addon","none") eq "sensor" ); #
          my $channel;
          if( $cmd =~ /(over|under)$/ ){  # channel is given as $value
             $channel = $value;
             $channel = 0  if( !defined($channel) );
             if( $channel =~ /\D/ || $channel >= $channels ){ # check if channel is anything else than a digit or wrong number
                 Shelly_error_handling($hash,"Shelly_Set","Wrong channel <$value> for command <$cmd>",1);
             }else{
                 $subs = $channels>1?"_".$channel:"" ;
                  readingsBulkUpdateMonitored($hash,$signal.$subs."_range", $isWhat );
             }
          }else{   # channel is given as next parameter
             $channel = $a[0];
             if( !defined($channel) ){
                 if( $channels > 1){
                     Shelly_error_handling($hash,"Shelly_Set","No channel given for command <$cmd>",1);
                     return;
                 }else{
                     $channel = 0;
                 }
             }
             if( $channel =~ /\D/ || $channel >= $channels ){ # check if channel is anything else than a digit or wrong number
                 Shelly_error_handling($hash,"Shelly_Set","Wrong channel <$channel> for command <$cmd>",1);
             }elsif( $value !~ /[0-9.]/ ){ # check if value is a number
                 Shelly_error_handling($hash,"Shelly_Set","Wrong value <$value> for command <$cmd>",1);
             }else{
                 $subs = $channels>1?"_".$channel:"" ;
                 $value = sprintf( "%5.2f", $value ); ## %5.1f
                 Shelly_readingsBulkUpdate($hash,$signal.$subs,$value,$signal);
             }
          }
    }elsif( $signal =~ /^(Active_Power|Voltage|Current)/ ){
          if( !defined($isWhat) ){
              Shelly_error_handling($hash,"Shelly_Set:Active_Power","no phase received from ShellyPro3EM",2);
              return;
          }
          my $suffix =  AttrVal($name,"EMchannels","_ABC");
          my $reading;
          $reading = $mapping{pr}{$suffix}{$isWhat.'_'} . $signal;
          $reading .='_pushed' if( $signal eq "Active_Power" );
          $reading .= $mapping{ps}{$suffix}{$isWhat.'_'};
          if( $signal eq "Active_Power" ){
          # save pushed active power value of a single phase for later calculation of total value
          # these values are overwritten by regular updates @ interval
          $hash->{helper}{"$isWhat\_Active_Power"}=$value;

          $value = sprintf( "%5.1f%s", $value, $si_units{power}[$hash->{units}] );
          readingsBulkUpdateMonitored($hash,$reading,$value );

          $reading = $mapping{pr}{$suffix}{'total_'} . "Active_Power_pushed" . $mapping{ps}{$suffix}{'total_'};
          # calculate total value out of pushed and regular values
          $value = $hash->{helper}{a_Active_Power}+$hash->{helper}{b_Active_Power}+$hash->{helper}{c_Active_Power};
          $value = sprintf("%5.1f%s", $value, $si_units{power}[$hash->{units}] );
          }else{  ##  $signal eq "Voltage" || "Current"
              $value = sprintf("%8.3f%s", $value, $si_units{ lc($signal) }[$hash->{units}] );
          }
          readingsBulkUpdateMonitored($hash,$reading,$value );

    }elsif( $signal =~ /analog_in/ ){
          #action example:  ...?cmd=set+<name>+analog_in+$percent+<inputchannel>
          my $channel = shift @a;  # 1st parameter
          return if( !defined($channel) );
          #readingsBulkUpdateMonitored($hash,"input_$channel",$value.$si_units{pct}[$hash->{units}] );
          Shelly_readingsBulkUpdate($hash,"input_$channel",$value,"pct" );

    }elsif( $signal =~ /voltmeter/ ){
          #action example:  ...?cmd=set+<name>+voltmeter+$voltage+0
          my $channel = shift @a;  # 1st parameter
          return if( !defined($channel) );
          Shelly_readingsBulkUpdate($hash,"voltmeter_$channel",$value,"voltage");
          
    }else{
          Log3 $name,1,"[Shelly_Set] $name: Wrong detail on action command $cmd $value". (defined($mode)?", mode is $mode":", no mode given");
          return;
    }
#    readingsBulkUpdateMonitored($hash,"state",$hash->{MOVING}) if( defined($hash->{MOVING}) );
    readingsEndUpdate($hash,1);
    #-- Call status after switch.n
    if( $signal !~ /^(Active_Power|Voltage|Current|apower|voltage|current)/ ){
        #-- scheduling next status update
        Shelly_status($hash,"Shelly_Set",0.75);
    }
    return undef;
  #---------------------------
  #-- commands from shelly roller actions: opening, closing, stopped, is_closed, is_open
  }elsif( $cmd =~ /opening|closing|stopped|is_/ ){
          if( $hash->{helper}{StatusCall}==1 ){  # is pending
              Log3 $name,4,"[Shelly_Set:roller actions] $name: skipping roller action \'$cmd\' because Status-Call is pending";
              return;
          }else{
              Log3 $name,3,"[Shelly_Set:roller actions] $name: \'set $cmd\' called";
          }
          my %rolleractions = (
               'opening'  =>  "drive-up",
               'closing'  =>  "drive-down",
               'stopped'   => "stopped",
               'is_closed' => "stopped",
               'is_open'   => "stopped"
          );
          $hash->{MOVING} = $rolleractions{$cmd};
          readingsSingleUpdate($hash,"state",$hash->{MOVING},1);
          if(0 && $cmd =~ /is_(.*)/ ){           
               readingsSingleUpdate($hash,"position",$1,1);
          }
          Shelly_status($hash,"Shelly_Set $cmd",0.8);    # scheduled update if not pending
          return undef;
  #---------------------------
  }elsif( $cmd =~ /actions/ ){
      Log3 $name,4,"[Shelly_Set:actions] $name: \'set $cmd\' called";
  #---------------------------
  # set actions create  info|<number>|all
  # set actions delete  <id>|own|all
  # set actions disable <id>
  # set actions enable  <id>
  # set actions update
      my $actioncmd = $value;
      my $actionselect = shift @a;
      my $actionchannel = shift @a;
      $actionselect = "" if( !defined($actionselect) );
      $actionselect = "info" if( $actioncmd eq "y" ); # for_debugging only
      Log3 $name,4,"[Shelly_Set:actions] $name: \'set $cmd $actioncmd $actionselect\' called";
      my $gen=$shelly_models{$model}[4];
      #-- check parameter
      if( $actioncmd eq "y" ){ #ok
      }elsif( $actioncmd !~ /create|delete|disable|enable|update|y/ ){
          return "Command \'$actioncmd\' is not valid";
      }elsif( $actioncmd !~ /create|enable/ && ReadingsNum($name,"webhook_cnt",0)==0 ){  # commands:  delete, disable, update
          return "No enabled actions on device $name";
      }elsif( $actioncmd =~ /update/ ){
          return "$name: Please define attr webhook first"   if( !defined(AttrVal($name,"webhook",undef)) );
      }
      if( $gen == 0 ){
          $actionchannel=0 unless( defined($actionchannel) );
      }elsif( $actionselect eq "own" || $actionselect eq "all" || $actionselect eq "info" ){ #ok
      }elsif( $actionselect =~ /\D/ ){ # has non-digits, or minus-sign
          return "Parameter is negative or not numerical";
      }elsif( $actionselect eq "" && $actioncmd ne "create" && $actioncmd ne "update" && $actioncmd ne "y" ){
          return "No id given";
      }elsif( $actionselect ne "" && $actionselect < 0 ){  # some case 0 not valid
          return "Id \'$actionselect\' is not valid";
      }
      # when using a not existing id, shelly will return 'Not Found', reading error will be set to '-105...hook_id...not found!'
      #-- perform commands
      if( $actioncmd eq "enable" ){
          if( $gen==0 ){
              Shelly_HttpRequest($hash,"/settings/actions","?index=$actionchannel&name=$actionselect&enabled=true","Shelly_settings1G","webhook_update" );
          }else{
              Shelly_HttpRequest($hash,"/rpc/Webhook.Update","?id=$actionselect&enable=true","Shelly_settings2G","webhook_update" );
          }
      }elsif( $actioncmd eq "disable"){
          if( $gen==0 ){
              Shelly_HttpRequest($hash,"/settings/actions","?index=$actionchannel&name=$actionselect&enabled=false","Shelly_settings1G","webhook_update" );
          }else{
              Shelly_HttpRequest($hash,"/rpc/Webhook.Update","?id=$actionselect&enable=false","Shelly_settings2G","webhook_update" );
          }
      }elsif( $actioncmd eq "delete" ){
        if( $gen==0 ){
              Shelly_HttpRequest($hash,"/settings/actions",
                            "?index=$actionchannel&name=$actionselect&enabled=false&urls[]=\"\"", "Shelly_settings1G","webhook_update" );
        }else{
          if( $actionselect eq "all" ){
              Shelly_HttpRequest($hash,"/rpc/Webhook.DeleteAll","","Shelly_settings2G","webhook_update" );
          }elsif( $actionselect eq "own" ){
              return "Command not implemented yet";
          }else{
              Shelly_HttpRequest($hash,"/rpc/Webhook.Delete","?id=$actionselect","Shelly_settings2G","webhook_update" );
          }
        }
      }elsif( $actioncmd eq "create" ){
         if( $gen==0 && $actionselect eq "info" ){

             Shelly_HttpRequest($hash,"/settings/actions",undef,"Shelly_settings1G",undef,2 ); # we use the 'val' parameter to get the call as $info

         }elsif( !AttrVal($name,"webhook",undef) && $actionselect ne "info" ){
            return "please define attribute webhook first";
         }else{
            return Shelly_webhook_create($hash,$actionselect);
         }
      }elsif( $actioncmd eq "update"){
          if( $gen==0 ){
               Shelly_HttpRequest($hash,"/settings/actions",undef,"Shelly_webhook_update",$actionselect );
          }else{
               Shelly_HttpRequest($hash,"/rpc/Webhook.List",undef,"Shelly_webhook_update",$actionselect );
          }
      }
      return;
  #---------------------------
  }


  #-- real commands
  my $ff=-1;  # Function-Family, correspondends to row in %shelly_models{model}[]

  #-- we have a switch type device
  if( $shelly_models{$model}[0]>0 && $mode ne 'roller' ){
      $ff = 0;
  #-- we have a Shelly 2 / 2.5 or a Shelly(Plus/Pro)2pm roller type device
  }elsif( $shelly_models{$model}[1]>0 && $mode ne 'relay' ){
      $ff = 1;
  #-- we have a dimable device:  Shelly dimmer or Shelly RGBW in white mode
  }elsif( $shelly_models{$model}[2]>0 && $mode ne 'color' ){
           # $model =~ /shellydimmer/ || ($model =~ /shellyrgbw.*/ && $mode eq 'white') || $model eq 'shellyplus010v' ){
      $ff = 2;
  #-- we have a ShellyBulbDuo
  }elsif( $model =~ /shellybulb.*/ && $mode eq 'white' ){
      $ff = 2;
  #-- we have a color type device (Bulb or Shelly RGBW, and color mode)
  }elsif( ($model =~ /shelly(rgbw|bulb).*/) && ($mode eq 'color')){
      $ff = 7;
  }else{
      $ff = -1;
  }

  #-- get channel parameter
  $msg = "";
  if( $cmd eq "toggle" || $cmd eq "on" || $cmd eq "off" ){
        $channel = $value;
  }elsif( $cmd =~ /(dimup)|(dimdown)/ ){
        # commands for single channel devices or if attr defchannel is set
        #    set <name> dimup   
        #    set <name> dimup delta
        #    set <name> dimup delta:transit
        # commands for multi channel devices  and  attr defchannel is not set     
        #    set <name> dimup channel                  
        #    set <name> dimup delta channel 
        #    set <name> dimup delta:transit channel 
         
        #channel
        my $subs;       
        my $delta;
        if( $shelly_models{$model}[2]==1 ){
           $channel = 0;
           $subs = ""; 
           $delta = $value;
           $delta = AttrVal($name,"dimstep",25) if( !defined($value) );           
        }elsif( $shelly_models{$model}[2]<1 ){
           return "invalid command";
        }elsif( defined(AttrVal($name,"defchannel",undef)) ){
           $channel = AttrVal($name,"defchannel",undef);
           $subs = "_$channel";
        }elsif( scalar(@a) == 1 ){
           $channel = shift @a;
           return "channel not numerical"  if( $channel =~ /\D/ );
           $subs = "_$channel"; 
           $delta = $value;
        }elsif( defined($value) ){
           $channel = $value;
           return "channel not numerical"  if( $channel =~ /\D/ );
           $subs = "_$channel";  
           $delta = AttrVal($name,"dimstep",25);          
        }else{
           return "channel not given and attr defchannel not defined properly";
        }
        #transition time
        if( $delta =~ /:/ ){
        $delta =~ m/(.*):(.*)/;
            $delta = $1;
            $transit=$2;
            return "brightness-difference not given or not numerical" if( $delta =~ /\D/ );
            return "transit duration not given or not numerical" if( $transit !~ /[\d.]/ );
            return "transit duration must not exceed 5 sec" if( $transit>5 && ReadingsVal($name,"model_family","-") eq "Gen1" );
            $transit = int(1000*$transit);
            $msg = ", duration is $transit msec"; 
        }
        $delta = -$delta   if( $cmd eq "dimdown" );
        $msg = "Desired delta of brightness is $delta$msg"; 
        #resulting brightness
        $cmd = "dim";
        $brightness = ReadingsNum($name,"pct$subs",0) + $delta;
        if( $brightness > 100 ){
           $brightness = 100;
        }elsif( $brightness < 10 ){
           $brightness = 0;
           $cmd = "off";
        }
        $msg .= ", setting brightness of channel \'$channel\' to \'$brightness\'";
        $msg .= ", using comand $cmd";
        Log3 $name,4,"[Shelly_Set:dimupdown] ".$msg;#return $msg;
  }elsif( $cmd =~ /(on|off)-for-timer/ ){
        $time = $value;
        $channel = shift @a;
  }elsif( $cmd =~ /dim/ ){
        if( $value =~ m/(\d*):(\d*)/ ){
            $brightness = $1;
            $transit=$2;
            $brightness = undef if( $1 eq "" );
            return "transit duration not given or not numerical" if( $2 eq "" );
        }else{
            return "brightness not numerical" if( $value =~ /\D/ );
            $brightness = $value;
        }
        return "brightness not given" if( !defined($brightness) );
        if( $brightness  > 100 ){
          $msg = "given brightness \'$brightness\' to high for device $name, must not exceed 100";
          Log3 $name,1,"[Shelly_Set] ".$msg;
          return $msg;
        }
        $time = shift @a  if( $cmd =~ /dim-for-timer/ );
        $channel = shift @a;
  }elsif( ($cmd eq "pct" && $ff!=1 ) || $cmd =~ /dim/ || $cmd eq "brightness" || $cmd eq "ct" ){
      #  $pct = $value;
        $channel = shift @a;
        $channel = shift @a if( defined($channel) && $channel eq "%" ); # skip %-sign coming from dropdown (units=1)
  }

  #******  map on and off commands to ON, OFF
  if( $cmd =~ /^((on)|(off))/  &&  !defined($channel)  &&  AttrVal($name,"defchannel","undefined") eq "all" ){
        $cmd = uc($1);
        Log3 $name,4,"[Shelly_Set] command \'$1\' mapped to switch all channels";
  }

  #******
  #-- check channel
  my $subs="";
  if( $cmd =~ /^(toggle|on|off|pct|dim|brightness)/ && $cmd!~/(till)/ && $ff != 1){   # not for rollers
     if( $ff != 0 && $ff !=2 && $ff !=7 ){
          $msg = "Error: forbidden command  \'$cmd\' for device $name ($ff)";
          Log3 $name,1,"[Shelly_Set] ".$msg;
          return $msg;
     }
     if( !defined($channel) ){
        $channel = AttrVal($name,"defchannel",undef);
     }elsif( $channel =~ /\D/ ){ #anything else than a digit
        $msg = "Error: wrong channel \'$channel\' for device $name, must be <integer>";
        Log3 $name,1,"[Shelly_Set] ".$msg;
        return $msg;
     }
     if( !defined($channel) ){
           if( $shelly_models{$model}[$ff] > 1 ){
              $msg = "$name Error: no channel given and defchannel attribute not set properly";
              Log3 $name,1,"[Shelly_Set] $msg";
              return $msg;
            }elsif( $shelly_models{$model}[$ff]==1 ){
              $channel = 0;
            }
     }elsif( $channel >= $shelly_models{$model}[$ff] ){
              $msg = "$name Error: Wrong channel number \'$channel\', must be 0 ";
              $msg .= "or omitted" if( $shelly_models{$model}[$ff]==1 );
              $msg .= "... ".($shelly_models{$model}[$ff]-1) if( $shelly_models{$model}[$ff]>1 );
              Log3 $name,1,"[Shelly_Set] $msg";
              return $msg;
     }elsif( $shelly_models{$model}[$ff] > 1 ){
              $subs = "_$channel";
     }
     Log3 $name,4,"[Shelly_Set] $name channel is $channel and subs =\'$subs\'";
  }

  #-- do not loose existing 'on' timer on retrigger
  my $tmr = "timer$subs";
  my $remainingTmr = ReadingsNum( $name, $tmr, 0 ) - ReadingsAge( $name, $tmr, 0 );  # may be negative
  my $tmrcmd = "";  # string to add to the query-url
  if( $remainingTmr > 0 && $cmd !~ /^(on|off.*)$/ ){
         $tmrcmd = "&timer=$remainingTmr";
         Log3 $name,4,"[Shelly_Set] $name \'$tmr\': adding remaining timer \'$tmrcmd\' to command $cmd";
  }

  #-- transfer toggle command to an on-off-command
  if( $cmd eq "toggle" ){ #  && $shelly_models{$model}[0]<2 && $shelly_models{$model}[2]<2 ){ #select devices with less than 2 channels
       if( ($shelly_models{$model}[0]>1 && $mode ne "roller") || ($shelly_models{$model}[2]>1 && $mode eq "white") ){
          # we have a multi-channel device
          # toggle named channel of switch type device   or   RGBW-device
          my $subs = "_".$channel; # channel;
          $cmd = (ReadingsVal($name,"relay".$subs,
                  ReadingsVal($name,"light".$subs,
                  ReadingsVal($name,"state".$subs,"off"))) eq "on") ? "off" : "on";
       }else{
          $cmd = (ReadingsVal($name,"state","off") eq "on") ? "off" : "on";
       }
       Log3 $name,5,"[Shelly_Set] transfer \'toggle\' to command \'$cmd\'";
  }

  #- - on and off, on-for-timer and off-for-timer
  if( $cmd =~ /^((on)|(off)|(dim))/ && $cmd!~/(till)/ ){  # on-till, on-till-overnight
    if( $cmd eq "dim" ){
           #
           if( $brightness == 0 ){
               $cmd = "?turn=off$tmrcmd";
           }else{
               $cmd = "?brightness=$brightness&turn=on$tmrcmd";
           }
    #-- check timer command: on-for-timer off-for-timer dim-for-timer
    }elsif( $cmd =~ /for-timer/ ){
        #
        if( $time =~ /\D+/ ){ #anything else than digits
          $msg = "Error: wrong time spec \'$time\' for device $name, must be <integer>";
          Log3 $name,1,"[Shelly_Set] ".$msg;
          return $msg;
        }elsif( $time > 100000000 ){ # more than three years
          $msg = "given time to high for device $name, must be less than one year";
          Log3 $name,1,"[Shelly_Set] ".$msg;
          return $msg;
        }elsif( $time < 1){ # to low
          $msg = "given time to low for device $name";
          Log3 $name,1,"[Shelly_Set] ".$msg;
          return $msg;
        }
        if( $cmd eq "dim-for-timer" ){
            $cmd = "?brightness=$brightness&turn=on&timer=$time";
        }elsif( $cmd eq "on-for-timer" ){
            $cmd = "?turn=on&timer=$time";
        }elsif( $cmd eq "off-for-timer" ){
            $cmd = "?turn=off&timer=$time";
        }
        $hash->{helper}{timer} = $time; # cannot read out timer in latest fw eg walldisplay
    }elsif( $cmd =~ /(on)|(off)/ ){
        $cmd = "?turn=$cmd$tmrcmd";
    }
    # $cmd = is 'on' or 'off'  or  'on&timer=...' or 'off&timer=....' or 'dim&timer=....'
    
    $cmd .="&transition=$transit" if( $transit );

    Log3 $name,4,"[Shelly_Set] switching channel $channel for device $name with command $cmd, FF=$ff";#4
    my $comp;
    if( $shelly_models{$model}[4]==2 ){ #Gen2
            # translate Gen1-commands to Gen2
            $cmd =~ s/\?/\&/g;
            $cmd =~ s/turn=on/on=true/;
            $cmd =~ s/turn=off/on=false/;
            $cmd =~ s/timer/toggle_after/;
            $cmd =~ s/transition/transition_duration/;
        if( $ff==0 ){
            $comp = "Switch";
        }elsif( $ff==2 ){
            $comp = "Light";
        }elsif( $ff==7 ){
            # tbd
        }
      #  $cmd .="&transition_duration=$transit" if( $transit );
        Shelly_HttpRequest($hash,"/rpc/$comp.Set", "?id=$channel$cmd","Shelly_response","onoff"); #RONOFF
    }else{    #Gen1
        if( $ff==0 ){
                $comp = "relay";
        }elsif( $ff==2 || $ff==7 ){
            if( $model =~ /shellydimmer/ ){
                $comp = "light";
            }elsif( $model =~ /shellybulb/ && $mode eq "white" ){
                $comp = "light";
            }elsif( $model =~ /shellyrgbw/ && $mode eq "white" ){
                $comp = "white";
            }else{ # ff==7: RGBW or Bulb in color mode
                $comp = "color";
            }
        }
        Shelly_HttpRequest($hash,"/$comp","/$channel$cmd","Shelly_response","onoff"); # dim=onoff and more
    }
    return;

  #- - ON and OFF  -  switch all channels of a multichannel switch-device
  }elsif( $cmd =~ /^((ON)|(OFF))/ ){
    $cmd = lc($1);
    for(my $i=0;$i<$shelly_models{$model}[$ff];$i++){
        Shelly_Set($hash,$name,$cmd,$i);
    }
    return;
  }

  #-- commands strongly dependent on Shelly type -------------------------------------------------------
  $msg=undef;
  ################################################################################################################
  # we have a dimmable device (no rollers)  eg. shellydimmer or shellyrgbw in white mode: set percentage volume
  if( $ff==2 && $cmd =~ /^(pct|brightness|dim)/ ){
     # check value
     if( !defined($value) && $cmd =~ /up|down/ ){
            $value = AttrVal($name,"dimstep",10);
     }
     if( !defined($value) ){
            $msg = "Error: no $cmd value \'$value\' given for device $name";
     }elsif( $value =~ /\D+/ ){    #anything else than a digit
            $msg = "Error: wrong $cmd value \'$value\' for device $name, must be <integer>";
     }elsif( $value == 0 && $cmd =~ /(dimup)|(dimdown)/ ){
            $msg = "$name Error: wrong $cmd value \'$value\' given, must be 1 ... 100 ";
     }elsif( $value<0  || $value>100 ){
            $msg = "$name Error: wrong $cmd value \'$value\' given, must be 0 ... 100 ";
     }
     if( $msg ){
         Shelly_error_handling($hash,"Shelly_Set",$msg,1);
         return $msg;
     }

     Log3 $name,4,"[Shelly_Set] setting brightness for device $name to $value";
     if( $shelly_models{$model}[4]==2 ){
            #Gen2
            # translate Gen1-commands to Gen2
            if( $value == 0 ){  # dim-command
                  $cmd="&on=false" ;
            }elsif($cmd eq "pct" ){
                  $cmd="&brightness=$value";
            }elsif($cmd =~ /dim(up|down)/ ){
                  $cmd="&dim=$1"."\&step=$value";
            }else{
                  $cmd="&brightness=$value\&on=true";
            }
            Shelly_HttpRequest($hash,"/rpc/Light.Set", "?id=$channel$cmd","Shelly_response","onoff");
     }else{
            #Gen1
            my $comp;
            if( $model =~ /shellyrgbw/ && $mode eq "white" ){
                  $comp = "white";
            }else{
                  $comp = "light";
            }
            if( $value == 0 ){  # dim-command
                  $cmd="?turn=off" ;
            }elsif($cmd eq "pct" ){
                  $cmd="?brightness=$value";
            }elsif($cmd =~ /dim(up|down)/ ){
                  $cmd="?dim=$1"."\&step=$value";
            }else{
                  $cmd="?brightness=$value\&turn=on";
            }
            Shelly_HttpRequest($hash,"/$comp","/$channel$cmd$tmrcmd","Shelly_response","dim");
     }
     return;

  ################################################################################################################
  #-- we have a roller type device / roller mode
  }elsif( $ff==1 && $cmd =~ /^(stop|closed|open|pct|pos|delta|zero)/ ){
    Log3 $name,4,"[Shelly_Set:Roller] $name: we have a $model ($mode mode) and command is $cmd";
    Log3 $name,7,"[Shelly_Set:Roller] $name: 1st parameter=$value " if( defined($value) );
    $channel = 0;   # default, and used for devices with one roller only
    if( $shelly_models{$model}[1]>1 ){   # >1
        if( scalar(@a) == 1 ){  # one more parameter
            $channel = shift @a;
            return "channel not given as parameter" if( !defined($channel) );
        }elsif( $cmd =~ /pct|pos|delta/ ){
            return "not enough parameter";
        }else{
            $channel = $value;
            $value = undef;
        }
        return "channel not numerical"  if( $channel =~ /\D/ );
        return "wrong channel number"   if( $channel >= $shelly_models{$model}[1] ); # >=
        $subs = "_$channel"; 
        Log3 $name,4,"[Shelly_Set] $name: channel is selected: $channel";
    }
    Log3 $name,4,"[Shelly_Set:Roller] $name: value parameter=$value " if( defined($value) );
    
    my $max=AttrVal($name,"maxtime",30);
    my $maxopen =AttrVal($name,"maxtime_open",30);
    my $maxclose=AttrVal($name,"maxtime_close",30);

    #-- open 100% or 0% ?
    my $pctnormal = (AttrVal($name,"pct100","open") eq "open");

    #-- stop, and stay stopped
    if( $cmd eq "stop"  ||
            $hash->{MOVING} eq "drive-down" &&  $cmd eq "closed"  ||
            $hash->{MOVING} eq "drive-up"   &&  $cmd eq "open"    ||
            $hash->{MOVING} =~ /drive/      &&  $cmd eq "pct"     ||
            $hash->{MOVING} =~ /drive/      &&  $cmd =~ /pos/     ||
            $hash->{MOVING} =~ /drive/      &&  $cmd eq "delta"   ){
         # -- estimate pos here ???
         $hash->{DURATION} = 0;
         $cmd = "?go=stop";

    #-- in some cases we stop movement and start again in reverse direction
    }elsif(
            $hash->{MOVING} eq "drive-down" &&  $cmd eq "open"  ||
            $hash->{MOVING} eq "drive-up"   &&  $cmd eq "closed"||
            $hash->{MOVING} ne "stopped"    &&  $cmd eq "zero"     ){
         Log3 $name,1,"[Shelly_Set] stopping roller and starting after delay with command \'$cmd\'";
         # -- estimate pos here ???
         $hash->{DURATION} = 0;
         $hash->{CMD}=$cmd;
         RemoveInternalTimer($hash,"Shelly_Set");
         InternalTimer(time()+1.0, "Shelly_Set", $hash);
         $cmd = "?go=stop";

    #-- is moving !!!
    }elsif( $hash->{MOVING}  ne "stopped"  ){
         Log3 $name,1,"[Shelly_Set] Error: received command \'$cmd\', but $name is still moving";

    #-- is not moving
    }elsif( $hash->{MOVING}  eq "stopped" && $cmd eq "zero" ){
         # calibration of roller device
         Log3 $name,3,"[Shelly_Set] call for calibrating $name";
         if( $shelly_models{$model}[4]==0 ){
             # Gen1
             Shelly_HttpRequest($hash,"/roller","/0/calibrate","Shelly_response","config");
             #in older fw:
             #Shelly_HttpRequest($hash,"/settings","?calibrate=1","Shelly_response","config");
         }else{
             # Gen2
             # Calibrate may not be successfull, if movement-time limits are to low !!
             Shelly_HttpRequest($hash,"/rpc/Cover.Calibrate","?id=0","Shelly_response","config");
         }
         readingsSingleUpdate( $hash,"state","calibrating",1 );
         return;

    #--any other cases: no movement and commands: open, closed, pct, pos, delta
    }elsif( $cmd =~ /(closed)|(open)/ ){
        $hash->{helper}{UserDuration} = $value if( defined($value) );
        if( $cmd eq "closed" ){
          $hash->{DURATION} = (defined($value))?$value:$maxclose;
          $hash->{MOVING} = "drive-down";
          $hash->{TARGETPCT} = $pctnormal ? 0 : 100;
          $cmd = "?go=close";
        }else{
          $hash->{DURATION} = (defined($value))?$value:$maxopen;
          $hash->{MOVING} = "drive-up";
          $hash->{TARGETPCT} = $pctnormal ? 100 : 0;
          $cmd ="?go=open";
        }
        # limit drive-time if duration is given as parameter
        if( defined($value) ){
            $cmd .= "&duration=".$hash->{DURATION}    if( $shelly_models{$model}[4]<2 );  # Gen1 only
            $hash->{helper}{timer} = $hash->{DURATION}+1.05; # state is turned to 'stopped' with a little delay
        }
    }elsif( $cmd eq "pct" || $cmd =~ /pos/ || $cmd eq "delta" ){
        my $targetpct = $value;
        my $pos  = ReadingsVal($name,"position","");
        my $pct  = ReadingsVal($name,"pct",0);
        $pct = 0  if( $pct eq "unknown" );  # when position is lost
             if( $cmd eq "pct" &&  "$value" =~ /[\+-]\d*/ ){
               $targetpct = eval($pct."$value");
             }
        #-- check for sign
        if( $cmd eq "delta" ){
           if( $value =~ /[\+-]\d*/ ){
               $targetpct += $pct;
           }else{
               my $err = "Wrong format of comand \'$cmd\', must consist of a plus or minus sign followed by an integer value";
               Shelly_error_handling($hash,"Shelly_Set",$err,1);
               return $err;
           }
        }
        if( $targetpct<0 ){
              $targetpct = 0;
              Log3 $name,1,"[Shelly_Set] $name: Target Pos limited to 0";
        }elsif( $targetpct>100 ){
              $targetpct = 100;
              Log3 $name,1,"[Shelly_Set] $name: Target Pos limited to 100";
        }elsif( abs($targetpct-$pct)<1 ){
              Log3 $name,1,"[Shelly_Set] $name: already on Target Pos, aborting";
              return;
        }

        if( !$maxopen || !$maxclose ){
              Log3 $name,1,"[Shelly_Set] please set the maxtime_open/close attributes for proper operation of device $name";
              $maxopen = $maxclose = ( $max ? $max : 20 );
        }

        if( ($pctnormal && $targetpct > $pct) || (!$pctnormal && $targetpct < $pct) ){
            $hash->{MOVING} = "drive-up";
            $max = $maxopen;
        }else{
            $hash->{MOVING} = "drive-down";
            $max = $maxclose;
        }

        #$time           = int(abs($targetpct-$pct)/100*$max);
        #$hash->{MOVING} = $pctnormal ? (($targetpct > $pct) ? "drive-up" : "drive-down") : (($targetpct > $pct) ? "drive-down" : "drive-up");

        $hash->{TARGETPCT} = $targetpct;
        $hash->{DURATION}  = abs($targetpct-$pct)/100*$max;
        $hash->{helper}{timer} = $hash->{DURATION};
        $cmd = "?go=to_pos&roller_pos=" . ($pctnormal ? $targetpct : 100 - $targetpct);
    }
    $cmd = "/roller/$channel".$cmd;  
    Log3 $name,4,"[Shelly_Set] $name: requesting up/down with comand $cmd, duration=".$hash->{DURATION};  #4

    my $CMD2;
    my $gen;
    if( $shelly_models{$model}[4]==2 ){
            # Gen2
            $cmd =~ s/\?go=stop/Cover.Stop/;
            $cmd =~ s/\?go=open/Cover.Open/;
            $cmd =~ s/\?go=close/Cover.Close/;
            $cmd =~ s/\?go=to_pos&roller_pos=/Cover.GoToPosition?pos=/;
            $cmd =~ s/\/roller\/(\d)//;
            my $channel = $1; # $channel=0;
            # Gen2 commands: rpc/Cover.Open?id=0 [ &duration=<num>  ]
            #                          Close?id=0 [ &duration=<num>  ]
            #                          Stop?id=0
            #                          GoToPosition?id=0&pos=<num>
            # in case of success we receive "null",
            # in case of error we receive $jhash->{code} and $jhash->{message} containing an err-message
            if( $cmd =~ /GoTo/ ){
                my $targetpct = $hash->{TARGETPCT};
                $targetpct = ($pctnormal ? $targetpct : 100 - $targetpct);
                $cmd="/rpc/Cover.GoToPosition";
                $CMD2="?pos=$targetpct&id=$channel";
                if( AttrVal($name,"slat_control",undef ) eq "enabled" ){
                   $CMD2 .="&slat_pos=".AttrVal($name,"slat_pos",50 );
                }
            }else{
                $cmd="/rpc/$cmd";
                $CMD2="?id=$channel";
                $CMD2 .= "&duration=".$hash->{helper}{UserDuration}    if( $hash->{helper}{UserDuration} );  # Gen2 only
                delete $hash->{helper}{UserDuration};
            }
            Log3 $name,4,"[Shelly_Set] $name Gen2 command is=$cmd$CMD2"; 
            $gen=2;
    }else{
            # Gen1;  channel is set to 0 - we don't have Gen1 multichannel roller devices
            #.#$CMD2="/0$cmd";
            #.#$cmd="/roller";
            $CMD2=$cmd;
            $cmd="";
            $gen=1;
    }
    Shelly_HttpRequest($hash,$cmd,$CMD2,"Shelly_response","updown".$gen);
    return;

  ################################################################################################################
  #-- we have a ShellyBulbDuo (it's a bulb in white mode) $ff=2
  }elsif( $cmd eq "ct" ){
    $channel = shift @a;
    Shelly_HttpRequest($hash,"/light","/0?temp=$value$tmrcmd","Shelly_response","dim");
    return;

  ################################################################################################################
  #-- we have a Shelly rgbw type device in color mode; $ff==7
  #-- commands: hsv, rgb, rgbw, white, gain, effect
  }elsif( $ff==7 && $cmd =~ /hsv|rgb|white|gain|effect/ ){
    #$ff = 7;
    #my $channel = $value;
    my ($red,$green,$blue,$white);
    my $cmd0;
    Log3 $name,5,"[Shelly_Set] processing command $cmd for $name";
    if( $cmd eq "hsv" ){
      my($hue,$saturation,$value)=split(',',$value);
      #-- rescale
      if( $hue>1 ){
        $hue = $hue/360;
      }
      ($red,$green,$blue)=Color::hsv2rgb($hue,$saturation,$value);
      $red  =int($red*255+0.5);
      $green=int($green*255+0.5);
      $blue= int($blue*255+0.5);
      $cmd0=sprintf("red=%d&green=%d&blue=%d",$red,$green,$blue);
      if($model eq "Xshellybulb"){
          $cmd0 .= "&gain=100";
      }else{
          $cmd0 .= sprintf("&gain=%d",$value*100);  #new
      }

    }elsif( $cmd =~ /rgb/ ){
      $red  = hex(substr($value,0,2));  # convert hexadecimal number into decimal
      $green= hex(substr($value,2,2));
      $blue = hex(substr($value,4,2));
      if( $cmd eq "rgbw" ){
          $white= hex(substr($value,6,2));
          $cmd0    = sprintf("white=%d",$white);
      }
      $cmd0    .= sprintf("&red=%d&green=%d&blue=%d",$red,$green,$blue);
 ##     $cmd0    .= "&gain=100";
    }elsif( $cmd eq "white" ){  # value 0 ... 100
      $cmd0=sprintf("white=%d",$value*2.55);
    }elsif( $cmd eq "gain" ){  # value 0 ... 100
      $cmd0=sprintf("gain=%d",$value);
    }elsif( $cmd eq "effect" ){  # value 0 ... 3
      $value = 0  if( $value eq 'Off' );
      $cmd0=sprintf("effect=%d",$value);
    }else{
              my $err = "no handler for command \'$cmd\'";
              Shelly_error_handling($hash,"Shelly_Set:rgbw",$err,1);
              return $err;
    }
    my ($CMD1,$CMD2);
    my $gen;
    if( $shelly_models{$model}[4]==2 ){ # Gen2   RGBWgen2
        if( $cmd =~ /hsv|rgb/ ){
                $CMD1="/rpc/RGB.Set";
                $CMD2="?id=0&on=true&rgb=[$red,$green,$blue]&brightness=100";
                $CMD2.="&white=$white"   if( $cmd =~ "rgbw" );
        }
    }else{  # Gen1
        $CMD1="/color";
        $CMD2="/0?$cmd0$tmrcmd";
    }
    Shelly_HttpRequest($hash,$CMD1,$CMD2,"Shelly_response","dim");
    return;    
  ################################################################################################################
  #-- we have a Shelly Plug Gen2+ with PLUGS-UserInterface PLUGS_UI
  # colorsOn  colorsOff
  }elsif( $model eq "shellyplusplug" && $cmd =~ /colors(.*)$/ ){  #
    my $onoff=lc($1);
    my ($leds,$rgb,$err);
    my $brightness="";
    if( ReadingsVal( $name, "model_ID", "" ) !~ /EU$/ ){
              $err = "not supported by this model";
              Shelly_error_handling($hash,"Shelly_Set:PLUG_UI",$err,1);
              return $err;          
    }
    if( !$value  ){ # no value given
              $err = "missing parameter(s)";
              Shelly_error_handling($hash,"Shelly_Set:PLUG_UI",$err,1);
              return $err;          
    }elsif( $value eq "off" ){
          $leds = "\"mode\":\"off\"";
    }elsif( $value eq "power" ){
          $leds = "\"mode\":\"power\"";   
          if( scalar(@a)==1 ){ # power-brightness given   
              $brightness = shift @a;
              if( $brightness =~ /^(100|([1-9]|)\d)$/ ){ # 0 ... 100
                  $leds .= ",\"colors\":{\"power\":{\"brightness\":$brightness}}";  
              }
          }
    }else{
          $leds = "\"mode\":\"switch\"";
          if( $value =~ /^((100|([1-9]|)\d)\,?\b){3}$/ ){ # 0 ... 100
              $rgb="\"rgb\":[$value]";
          }elsif( $value =~ /^([0-9A-Fa-f]){6}$/ ){ # 6-digit hexadecimal value 
              sub HX{sprintf("%.3f",hex(substr($_[0],$_[1],2))/2.55)}
              $rgb = "\"rgb\":[".&HX($value,0).",".&HX($value,2).",".&HX($value,4)."]";
          }elsif( $value =~ /^(100|([1-9]|)\d)$/ && scalar(@a)==0 ){ # only brightness given              
              $brightness = "\"brightness\":$value";
              $rgb = "";
          }else{
              $err = "wrong value: \'$value\'";
              Shelly_error_handling($hash,"Shelly_Set:PLUG_UI",$err,1);
              return $err;
          }
          if( scalar(@a) == 1 ){  # one more parameter
              $brightness = shift @a;
              if( $brightness !~ /^(100|([1-9]|)\d)$/ ){ # 0 ... 100
                  $err = "wrong brightness value: \'$brightness\'";
                  Shelly_error_handling($hash,"Shelly_Set:PLUG_UI",$err,1);
                  return $err;
              }
              $brightness = ",\"brightness\":$brightness";
         }
         $leds .= ",\"colors\":{\"switch:0\":{\"$onoff\":{$rgb$brightness}}}";
    }
    Shelly_HttpRequest($hash,"/rpc/PLUGS_UI.SetConfig","?config={\"leds\":{$leds}}","Shelly_response","plugsui","set");
    return; 
  ################################################################################################################
  #-- we have a Walldisplay with thermostat  ]
  }elsif( $cmd eq "target" ){  # desired temperature, in °C
     $channel = shift @a;
     Shelly_HttpRequest($hash,"/rpc/Thermostat.SetConfig","?config={\"id\":0,\"target_C\":$value}","Shelly_response","target");
     return;
  }elsif( $cmd eq "thermostat_type" ){  # thermostat_type: heating, cooling
     Shelly_HttpRequest($hash,"/rpc/Thermostat.SetConfig","?config={\"id\":0,\"type\":$value}","Shelly_response","target");
     return;
  }elsif( $cmd eq "thermostat_output" ){  # thermostat_relay_mode: straight, invert
     $value = $value eq "invert" ? 1:0;# : false;
     Shelly_HttpRequest($hash,"/rpc/Thermostat.SetConfig","?config={\"id\":0,\"invert_output\":$value}","Shelly_response","target");
     return;
  }

  ###########################################################################
  #-- commands independent of Shelly type: password, interval, reboot, update, ....
  if( $cmd eq "password" ){
    my $user = AttrVal($name,"shellyuser",undef);
    if(!$user && $shelly_models{$model}[4]==0 ){
      my $msg = "Error: password can be set only if attribute \'shellyuser\' is set";   # Gen1
      Log3 $name,1,"[Shelly_Set] ".$msg;
      return $msg;
    }
    setKeyValue("SHELLY_PASSWORD_$name", $value);
    Shelly_status($hash,"Shelly_Set pwd");
    InternalTimer(time()+0.9, "Refresh", $hash) if( $init_done );   # perform a browser refresh
    return undef;

  }elsif( $cmd eq "interval" ){
      $value = int($value);
      if( IsInt($value) && $value > 0){  # see 99_Utils.pm
          $hash->{INTERVAL} = int($value);
          Shelly_Set($hash,$name,"startTimer");
      }elsif( $value == 0 ){
          $hash->{INTERVAL} = 0;
          readingsSingleUpdate( $hash,"state","disabled",1 );
          Log3 $name,2,"[Shelly_Set:interval] No timer started for $name, polling of device is disabled";
      }elsif( $value == -1 ){
          $value =AttrVal($name,"interval",$defaultINTERVAL);
          $hash->{INTERVAL} = $value;
          Log3 $name,2,"[Shelly_Set:interval] interval for $name set to $value";
          Shelly_Set($hash,$name,"startTimer");
      }else{
          my $msg = "Value \'$value\' is not valid";
          Log3 $name,1,"[Shelly_Set:interval] $name: ".$msg;
          return $msg;
      }
      return undef;

  }elsif( $cmd eq "startTimer" ){ # starting/stopping timer
      my $timer=$hash->{INTERVAL};
      my $msg;
          RemoveInternalTimer($hash,"Shelly_getEMvalues");
          RemoveInternalTimer($hash,"Shelly_getEnergyData");
      if( $timer ){
          $msg = "(Re-)Starting cyclic timers: ";
          #---------------------------
          #-- scheduling next status update
          Shelly_status($hash,"Shelly_Set",$timer);
          $msg .= "status-timer=$timer";
          if( $shelly_models{$model}[6]>0 ){ # $model =~ /shellypro3em|shellyproem50/
              #
              RemoveInternalTimer($hash,"Shelly_getEMvalues");
              $timer=1; #$hash->{INTERVAL}/4;
              InternalTimer(time()+$hash->{INTERVAL}/4, "Shelly_getEMvalues", $hash);
              $msg .= ", EM power-values-timer=$timer";
              #
              RemoveInternalTimer($hash,"Shelly_getEnergyData");
              $timer=int((time()+60)/60)*60+1 - time();  #  +60
              InternalTimer(int((time()+60)/60)*60+1, "Shelly_getEnergyData", $hash);
              $msg .= ", EM energy-data-timer=$timer";
          }
      }else{
          $msg =  "Device $name is disabled, timer canceled";
      }
      Log3 $name,4,"[Shelly_Set:startTimer] $name: $msg";
      return undef;

  }elsif( $cmd eq "calibrate" ){  # shelly-dimmer
      Log3 $name,1,"[Shelly_Set] call for Calibrating $name";
      if( $shelly_models{$model}[4]==0 ){
          #$cmd="settings?calibrate=1";
          Shelly_HttpRequest($hash,"/settings","?calibrate=1","Shelly_response","config");
      }else{
          # Gen2; returns 'null' on success
          Shelly_HttpRequest($hash,"/rpc/Light.Calibrate","?id=0","Shelly_response","config");
      }

  }elsif( $cmd eq "reboot" ){
      Log3 $name,1,"[Shelly_Set] call for Rebooting $name";
      if( $shelly_models{$model}[4]==0 ){
          Shelly_HttpRequest($hash,"/reboot","","Shelly_response","config");
      }else{
          Shelly_HttpRequest($hash,"/rpc/Shelly.Reboot","","Shelly_response","config");
      }
      return undef;

  }elsif( $cmd eq "update" ){
      Log3 $name,1,"[Shelly_Set] call for Updating $name";
      if( $shelly_models{$model}[4]==0 ){
          Shelly_HttpRequest($hash,"/ota","?update=true","Shelly_response","config");
      }else{
          $cmd="rpc/Shelly.Update?stage=%22stable%22" ;  #beta
          Shelly_HttpRequest($hash,"/rpc/Shelly.Update","?stage=%22stable%22","Shelly_response","config");
      }
      readingsSingleUpdate($hash,"firmware_updText","...updating...",1); 
      readingsSingleUpdate($hash,"firmware_updIcon","U",1);  # set as clickable icon in readingsGroup
      return undef;

  }elsif( $cmd eq "clear" ){
      my $doreset = $value;
      my $comp;
      Log3 $name,4,"[Shelly_Set] Resetting counter \'$doreset\' of device $name";
      if( $doreset eq "disconnects" ){
         readingsSingleUpdate($hash,"network_disconnects",0,1);
      }elsif( $doreset eq "error" ){
         readingsSingleUpdate($hash,"error","-",1);
      }elsif( $doreset eq "responsetimes" ){
         my $ptrclrcnt = 0;
         foreach my $ptr ( keys %{$defs{$name}{READINGS}} ){
             if( $ptr =~ /^\// ){  # select all readings beginning with a '/'
                 readingsSingleUpdate($hash,$ptr,"-",1);  #clear process time reading
                 $ptrclrcnt++;
             }
         }
         Log3 $name,2,"[Shelly_Set:Clear] Clearing $ptrclrcnt process time readings at device $name";
      }elsif( $doreset eq "energy" ){    # command:  set <name> clear energy
         if( ReadingsVal($name,"firmware_current","") =~ /(v0|v1.0)/ ){
              my $err = "firmware must be at least v1.1.0";
              Shelly_error_handling($hash,"Shelly_Set:clear",$err,1);
              return $err;
         }
         my $numC;
         if( $shelly_models{$model}[0]>0 && $mode ne "roller" ){
            $comp = "Switch";
            $numC = $shelly_models{$model}[0];
         }elsif( $shelly_models{$model}[1]>0 && $mode ne "relay" ){
            $comp = "Cover";
            $numC = $shelly_models{$model}[1];
         }elsif( $numC=$shelly_models{$model}[2]>0 && $mode ne "color" ){
            $comp = "lights";
           # $numC = $shelly_models{$model}[2];
         }elsif( $numC=$shelly_models{$model}[7]>0 && $mode ne "white" ){
            $comp = "lights";
           # $numC = $shelly_models{$model}[7];
         }elsif( $shelly_models{$model}[3]>0 && !$mode ){
            return if( ReadingsVal($name,'model_ID','') !~ /^S.PM/ );  # eg S3PM.... or SNPM.... of model "shellypmmini"
            $comp = "PM1";
            $numC = $shelly_models{$model}[3];
         }else{
            Log3 $name,1,"[Shelly_Set] Wrong component $comp";
            return;
         }
         Log3 $name,1,"[Shelly_Set] Clear energy for $numC channels on comp=$comp / $mode id=".ReadingsVal($name,'model_ID','');
         for( my $id=0; $id<$numC; $id++ ){
            Shelly_HttpRequest($hash,"/rpc/$comp\.ResetCounters","?id=$id&type=[\"aenergy\"]","Shelly_response","config_$id");
         }
      }
      return undef;

  #-- renaming the Shelly, spaces in name are allowed
  }elsif( $cmd eq "name") {   #ShellyName
      my ($newname,$urlcmd);
      if( defined $value ){
        $newname=$value;
        while( $value=shift @a ){
          $newname .= " ". $value;
        }
      }else{
          my $msg = "Error: wrong number of parameters";
          Log3 $name,1,"[Shelly_Set] ".$msg;
          return $msg;
      }
      readingsSingleUpdate($hash,"name",$newname,1);
      $msg = "The Shelly linked to $name is named to \'$newname\'";
      Log3 $name,1,"[Shelly_Set] $msg";
      $newname =~ s/ /%20/g;  #spaces not allowed in urls
      if( $shelly_models{$model}[4]>=1 ){
        $cmd="/rpc/Sys.SetConfig" ;
        $urlcmd="?config={%22device%22:{%22name%22:%22$newname%22}}";
        #                                {"device"   :{"  name"  :   "arg"}}
      }else{
        $cmd="/settings";
        $urlcmd="?name=$newname";
      }
      Shelly_HttpRequest($hash,$cmd,$urlcmd,"Shelly_response","config");
      return $msg;

  #-- command config largely independent of Shelly type
  }elsif($cmd eq "config"){
   if( $shelly_models{$model}[4] == 0 ){
       # Gen1
       my $reg = $value; #the register, eg auto_off
       my ($val,$chan);
       if( int(@a) == 2 ){
         $chan = $a[1];
         $val = $a[0];
       }elsif( int(@a) == 1 ){
         $chan = 0;
         $val = $a[0];
       }else{
         my $msg = "Error: wrong number of parameters";
         Log3 $name,1,"[Shelly_Set] ".$msg;
         return $msg;
       }
       my $pre = "/settings/";
       if( ($model =~ /shelly2.*/) && ($mode eq "roller") ){  ##R
         $pre .= "roller/0";
       }elsif( ($model eq "shellyrgbw" || $model eq "shellybulb") && ($mode eq "white") ){
         $pre .= "white/0";
       }elsif( ($model eq "shellyrgbw" || $model eq "shellybulb") && ($mode eq "color") ){
         $pre .= "color/0";
       }elsif( $model eq "shellydimmer" ){
         $pre .= "light/0";
       }else{
         $pre .= "relay/$chan";
       }
       Shelly_HttpRequest($hash,$pre,"?$reg=$val","Shelly_response","config");
   }else{
       #Gen2
       my $config_cmd = $value;
       my $tf = "enable";
       $tf = "disable" if( $config_cmd eq "ap_disable" );
       $tf =~ s/enable/true/;
       $tf =~ s/disable/false/;
       Shelly_HttpRequest($hash,"/rpc/Wifi.SetConfig","?config={'ap':{'enable':$tf}}","Shelly_response","config");
       # on success returns 'restart required NO'
   }
   return undef;

  }elsif( $cmd eq "input"){   ## ToDo   works only for devices with one input!
      return "wrong command" if( $value !~ /action|detached|edge|momentary|switch|toggle/ );
      if( ReadingsVal($name,"input_mode","unknown") !~ /$value/ ){
          Log3 $name,1,"[Shelly_Set:input] changing input type of $name: btn_type=$value";#1
          Shelly_HttpRequest($hash,"/settings/relay/0","?btn_type=$value","Shelly_response","config");
          # answer may be: Bad button type!
      }else{
          Log3 $name,4,"[Shelly_Set:input] input type of $name is already of btn_type=$value";#4
      }
      return undef;

  #-- fill in predefined attributes for roller devices
  }elsif( $cmd eq "predefAttr") {
      return "keine Kopiervorlage verfügbar" if( $mode ne "roller" );

      return "Set the attribute\'pct100\' first"   if( !AttrVal($name,"pct100",undef) );
      $msg = "$name:\n";
      my $devStateIcon;
      my $changes = 0;
      if(  !AttrVal($name,"devStateIcon",undef) ){
          if( AttrVal($name,"pct100","open") eq "open" ){
              $devStateIcon = $predefAttrs{'roller_open100'};
          }else{
              $devStateIcon = $predefAttrs{'roller_closed100'};
          }
          # set the devStateIcon-attribute when the devStateIcon attribute is not set yet
          $attr{$hash->{NAME}}{devStateIcon} = $devStateIcon;
          Log3 $name,5,"[Shelly_Get] the attribute \'devStateIcon\' of device $name is set to \'$devStateIcon\' ";
          $msg .= "devStateIcon attribute is set";
          $changes++;
      }else{
          $msg .= "attribute \'devStateIcon\' is already defined";
      }
      $msg .= "\n";
      if(  !AttrVal($name,"webCmd",undef) ){
          # set the webCmd-attribute when the webCmd attribute is not set yet
          $attr{$hash->{NAME}}{webCmd} = $predefAttrs{'roller_webCmd'};
          Log3 $name,5,"[Shelly_Get] the attribute \'webCmd\' of device $name is set  ";
          $msg .= "webCmd attribute is set";
          $changes++;
      }else{
          $msg .= "attribute \'webCmd\' is already defined";
      }
      $msg .= "\n";
      if(  !AttrVal($name,"cmdIcon",undef) ){
          # set the cmdIcon-attribute when the cmdIcon attribute is not set yet
          $attr{$hash->{NAME}}{cmdIcon} = $predefAttrs{'roller_cmdIcon'};
          Log3 $name,5,"[Shelly_Get] the attribute \'cmdIcon\' of device $name is set  ";
          $msg .= "cmdIcon attribute is set";
          $changes++;
      }else{
          $msg .= "attribute \'cmdIcon\' is already defined";
      }
      $msg .= "\n";
      if(  !AttrVal($name,"eventMap",undef) ){
          # set the eventMap-attribute when the eventMap attribute is not set yet
          if( AttrVal($name,"pct100","open") eq "open" ){
                $attr{$hash->{NAME}}{eventMap} = $predefAttrs{'roller_eventMap_open100'};
          }else{
                $attr{$hash->{NAME}}{eventMap} = $predefAttrs{'roller_eventMap_closed100'};
          }
          Log3 $name,5,"[Shelly_Get] the attribute \'eventMap\' of device $name is set  ";
          $msg .= "eventMap attribute is set";
          $changes++;
      }else{
          $msg .= "attribute \'eventMap\' is already defined";
      }
      $msg .= "\n\n to see the changes, browser refresh is necessary" if( $changes );
      return $msg;

  #-- create readingsProxy devices
  }elsif( $cmd eq "xtrachannels" ){
       Log3 $name,4,"[Shelly_Set] readingsProxy devices for $name requested";
       if( $shelly_models{$model}[$ff]>1){
         my $channelType = ($ff==0)?'relay':'light';
         my $i;
         for( $i=0;$i<$shelly_models{$model}[$ff];$i++){
           fhem("defmod ".$name."_$i readingsProxy $name:$channelType\_$i");
           fhem("attr $name\_$i room ".AttrVal($name,"room","Unsorted"));
           fhem("attr $name\_$i group ".AttrVal($name,"group","Shelly"));
           fhem("attr $name\_$i setList on off");
           fhem("attr $name\_$i setFn {\$CMD.\" $i \"}");
           # check if number of outputs and inputs are equal
           if( $shelly_models{$model}[$ff] == $shelly_models{$model}[5] ){
               fhem("attr $name\_$i userReadings input {ReadingsVal(\"$name\",\"input_$i\",\"\")}");
           }
           Log3 $name,1,"[Shelly_Set] readingsProxy device ".$name."_$i created";
         }
         $msg = "$i devices for $name created";
      }else{
         $msg = "No separate channel device created for device $name, only one channel present";
         Log3 $name,1,"[Shelly_Set] ".$msg;
      }
      return $msg;
      
  }elsif( $cmd =~ /blink|intervals|off-till|on-till/ ){
      Log3 $name,4,"[Shelly_Set] calling SetExtension \'$cmd\' for $name";
      SetExtensions($hash,$hash->{helper}{Sets},$name,$cmd,@args);
      
  }elsif( $cmd =~ /script/ ){ # script_start script_stop
      $cmd =~ s/_/\./;
      $cmd =~ s/s/S/g; # Script.Start Script.Stop
      Log3 $name,4,"[Shelly_Set] calling script function $cmd and id $value"; #4
      Shelly_HttpRequest($hash,"/rpc/$cmd","?id=$value","Shelly_response","scripts",1 ); #1=call silent
      
  ####****** BLU ***********
  }elsif( $cmd =~ /event/ ){
      Log3 $name,4,"[Shelly_Set:BLU] calling Shelly BLUE \'$cmd\' for $name";
      readingsSingleUpdate($name,$cmd,join(" ",@args),1);
  }else{
      $parameters=( scalar(@args)?" and ".scalar(@args)." parameters: ".join(" ",@args) : ", no parameters" );
      $msg="commands parsed, outstanding call for device $name with command \'$cmd\'$parameters";  #    if($cmd ne "?")
      Shelly_error_handling($hash,"Shelly_Set",$msg,1);
      return $msg;
  }
  return undef;
} #end Shelly_Set()


########################################################################################
#
# Shelly_pwd - retrieve the credentials if set
#
# Parameter hash
#
########################################################################################

sub Shelly_pwd($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  # username is set by default for Shelly Gen2
  my $user = $shelly_models{AttrVal($name,"model","generic")}[4]>=1 ? 'admin' : AttrVal($name,"shellyuser",undef);
  return "" if(!$user);

  my ($err, $pw) = getKeyValue("SHELLY_PASSWORD_$name");
  return "" if(!$pw);
  return "$user:$pw\@";
}


########################################################################################
#
# Shelly_status        - Endpoint for Internal Timers
# Shelly_getEMvalues   - Endpoint for Internal Timers (ShellyPro3EM only)
# Shelly_getEnergyData     - Endpoint for Internal Timers (ShellyPro3EM only)
#
########################################################################################

sub Shelly_status(@){
  my $hash = shift @_;
  my $callFn=shift @_;
  my $scheduled=shift @_;
    
  my $name = $hash->{NAME};
  ##$hash->{callFn}=$callFn;  # to be used by Shelly_status2G
  
  Log3 $name,5,"[Shelly_status:1] $name: callFn=".($callFn//"undefiniert")." sched=".($scheduled//"no").", helper=".$hash->{helper}{timer}; #4
  if( $scheduled//0 ){  
      Log3 $name,6,"[Shelly_status:1a] $name: set internal Timer  ---and------BYE------";
      readingsSingleUpdate($hash,"/_nextUpdateTimer","$scheduled sec $callFn",1)
                                               if( AttrVal($name,'timeout',undef) );
      RemoveInternalTimer($hash,"Shelly_status");
      InternalTimer(time()+$scheduled, "Shelly_status", $hash);
      return;
  }elsif( defined($callFn) && AttrVal($name,'timeout',undef) ){
      Log3 $name,6,"[Shelly_status:1b] $name";
  }elsif( !defined($callFn) ){
      $callFn = "Shelly_Status"; 
      Log3 $name,6,"[Shelly_status:1c] $name";
  } 
 
  Log3 $name,4,"[Shelly_status:2] $name: processing Http-Request forced by $callFn, helper=".$hash->{helper}{timer};
  
  my $timer = $hash->{INTERVAL};

  my $model = AttrVal($name,"model","generic");
  
  ### use a flag to avoid subsequent status calls ###
  if( $hash->{helper}{StatusCall} > 0 ){
         Log3 $name,4,"[Shelly_status:3a SKIPPED STATUS_CALL for $name";
         return;
  }else{
         Log3 $name,4,"[Shelly_status:3b] set STATUS_CALL \'pending\' for $name";
         $hash->{helper}{StatusCall}=1;  # will be resetted to 0 by Shelly_HttpResponse()
  

  ### ------------------------------------------------
  if($shelly_models{$model}[4]==0 ){
         Shelly_HttpRequest($hash,"/status",undef,"Shelly_status1G" );
  }elsif( $shelly_models{$model}[4]>=1 ){
         Shelly_HttpRequest($hash,"/rpc/Shelly.GetStatus",undef,"Shelly_status2G" );
  }
  }
  #-- force short-hand OR cyclic update
  my $msg="[Shelly_status] $name ";
  if( $hash->{helper}{timer}==0 && $hash->{INTERVAL}>0 ){
      $timer = $hash->{INTERVAL};
      $msg .= "A  next status call scheduled at INTERVAL in $timer seconds";
  }elsif( $hash->{helper}{timer} > $hash->{INTERVAL} && $hash->{INTERVAL} > 0 ){  # call status at end of operation-time
      $timer = $hash->{INTERVAL};
      $hash->{helper}{timer} = $hash->{helper}{timer} - $hash->{INTERVAL};
      $msg .= "B  next intermediate status call scheduled in $timer seconds";
  }elsif(0&& $hash->{helper}{timer} > 0 && $hash->{INTERVAL} == 0 ){  # call status at end of timer
      $timer = $hash->{helper}{timer};
      $hash->{helper}{timer} = 0;
      $msg .= "C  status call scheduled in $timer seconds";
  }elsif(0&& $hash->{helper}{timer} == 0 ){  # no call status 
      $hash->{helper}{StatusCall} = 0;
      $msg .= "X  SKIPP status call ";
  }else{
      $timer = $hash->{helper}{timer};
      $hash->{helper}{timer} = 0;
      $msg .= "D  next status call scheduled in $timer seconds";
  }
  Log3 $name,4,$msg;
} #end Shelly_status()

##########################
sub Shelly_getEMvalues($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  return if( $hash->{INTERVAL} == 0 );
  my $model = AttrVal($name,"model","generic");
 
  my $EMcall="EM1.GetStatus";
  $EMcall="EM.GetStatus"  if( ReadingsVal($name,"model_profile","monophase") eq "triphase");
  # request starts with id=0, following id's are called by Shelly_procEMvalues()
  Shelly_HttpRequest($hash,"/rpc/$EMcall","?id=0","Shelly_procEMvalues" );
} #end Shelly_getEMvalues()

##########################
sub Shelly_getEnergyData($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  return if( $hash->{INTERVAL} == 0 );
  
  my $EMcall="EM1Data.GetStatus";
  $EMcall="EMData.GetStatus"  if( ReadingsVal($name,"model_profile","monophase") eq "triphase");
  # request starts with id=0, following id's are called by Shelly_procEnergyData()
  Shelly_HttpRequest($hash,"/rpc/$EMcall","?id=0","Shelly_procEnergyData" );
} #end Shelly_getEnergyData()


########################################################################################
#
# Shelly_status1G - process status data from device 1st generation
#                   In 1G devices status are all in one call
#
########################################################################################

sub Shelly_status1G {
  my ($param,$jhash) = @_;
  my $hash = $param->{hash};
  my $name  = $hash->{NAME};
  my $state = $hash->{READINGS}{state}{VAL};
  my $statusTmr1G=$hash->{INTERVAL};   # timer for next status update 
  my $remaining=-1;   # read remaining timer from Shelly

  my $model = AttrVal($name,"model","generic");
  my $mode  = AttrVal($name,"mode","");
  
  my $VERB=5;

  my ($subs,$ison,$source,$rstate,$rstopreason,$rcurrpos,$position,$rlastdir,$pct,$pctnormal);
  my ($overpower,$power,$energy);

  readingsBeginUpdate($hash);
  Shelly_readingsBulkUpdate($hash,"network","<html>connected to <a href=\"http://".$hash->{DEF}."\">".$hash->{DEF}."</a></html>",undef,1); # formerly $hash->{TCPIP}
  readingsBulkUpdateIfChanged($hash,"network_connection","online");
  Shelly_readingsBulkUpdate($hash,"network_rssi",$jhash->{wifi_sta}{rssi},"rssi=2" );
  readingsBulkUpdateMonitored($hash,"network_ip-address",$jhash->{wifi_sta}{ip} );
  readingsBulkUpdateMonitored($hash,"network_ssid",$jhash->{'wifi_sta'}{'ssid'} )
                                                                      if( $jhash->{'wifi_sta'}{'ssid'} );
  fhem("deletereading $name error",1) if( ReadingsAge($name,"error",-1)>86400 ); # 24 hours / silent
  #-----------------------------------------------------------------------------------------
  #-- 1st generation: we have a switch type device and 'relay'-mode, e.g. shelly1, shelly1pm, shelly4, shelly2, shelly2.5, shellyplug or shellyem
  if( $shelly_models{$model}[0]>0 && $mode ne "roller" ){
    my $channels = $shelly_models{$model}[0];
    for( my $i=0;$i<$channels;$i++){
      $subs = ($channels == 1) ? "" : "_".$i;
      $ison = $jhash->{'relays'}[$i]{'ison'};
      $ison =~ s/0|(false)/off/;
      $ison =~ s/1|(true)/on/;
      readingsBulkUpdateMonitored($hash,"relay".$subs,$ison);

      # for models with one relay: display state of relay as 'state'
      if( $shelly_models{$model}[0]==1 ){
        readingsBulkUpdateMonitored($hash,"state",$ison);
      }else{
        readingsBulkUpdateMonitored($hash,"state","OK");
      }

      # timer
      if( $model ne "shelly4" ){  # readings not supported by Shelly4 v1.5.7
          #-- source
          $source = $jhash->{relays}[$i]{source};
          readingsBulkUpdateMonitored($hash,"source".$subs,$source);
          #-- timer
          $remaining  = $jhash->{relays}[$i]{timer_remaining};         
      }else{  # Shelly4pro
          $remaining = 0;
          if( $jhash->{relays}[$i]{has_timer} =~ /1|(true)/ ){
               $remaining = ReadingsNum($name,"auto_off".$subs,0) if( ReadingsNum($name,"timer".$subs,0)==0 );
               $remaining += ReadingsNum($name,"timer".$subs,0)-ReadingsAge($name,"timer".$subs,0);   # interpolate remaining time
          }      
      }
      Shelly_readingsBulkUpdate($hash,"timer".$subs,$remaining,"time");
    }

    #-- we have a shellyuni device
    if($model eq "shellyuni") {
      Shelly_readingsBulkUpdate($hash,"voltage",$jhash->{adcs}[0]{voltage},"voltage");
    }
  #-----------------------------------------------------------------------------------------
  #-- we have a shelly2 or shelly2.5 roller type device
  }elsif( ($model =~ /shelly2(\.5)?/)  && ($mode eq "roller") ){
    Log3 $name,$VERB,"[Shelly_status1G] device $name with model=$model getting roller state ";
    my $rollers  = $shelly_models{$model}[1];
    for( my $i=0;$i<$rollers;$i++){
      $subs = ($rollers == 1) ? "" : "_".$i;

      #-- weird data: stop, close or open
      $rstate = $jhash->{'rollers'}[$i]{'state'};
      $rstate =~ s/stop/stopped/;
      $rstate =~ s/close/drive-down/;
      $rstate =~ s/open/drive-up/;
      $hash->{MOVING}   = $rstate;
      #$hash->{DURATION} = 0;

      #-- weird data: close or open
      $rlastdir = $jhash->{'rollers'}[$i]{'last_direction'};
      $rlastdir =~ s/close/down/;
      $rlastdir =~ s/open/up/;
      $rstopreason = $jhash->{'rollers'}[$i]{'stop_reason'};

      #-- open 100% or 0% ?
      $pctnormal = (AttrVal($name,"pct100","open") eq "open");

       #-- possibly no data
      $rcurrpos = $jhash->{'rollers'}[$i]{'current_pos'};

      #-- we have data from the device, take that one
      if( defined($rcurrpos) && ($rcurrpos =~ /\d\d?\d?/) ){
        $pct = $pctnormal ? $rcurrpos : 100-$rcurrpos;
        $position = ($rcurrpos==100) ? "open" : ($rcurrpos==0 ? "closed" : $pct);
        Log3 $name,$VERB,"[Shelly_status1G] device $name received roller position $rcurrpos, pct=$pct, position=$position (100% is ".AttrVal($name,"pct100","open").")";

      #-- we have no data from the device
      }else{
        Log3 $name,3,"[Shelly_status1G] device $name with model=$model returns no blind position, consider chosing a different model=shelly2/2.5"
          if( $model !~ /shelly2.*/ );
        $pct = ReadingsVal($name,"pct",undef);
        #-- we have a reading
        if( defined($pct) && $pct =~ /\d\d?\d?/ ){
          $rcurrpos = $pctnormal ? $pct : 100-$pct;
          $position = ($rcurrpos==100) ? "open" : ($rcurrpos==0 ? "closed" : $pct);
        #-- we have no reading
        }else{
          if( $rstate eq "stopped" && $rstopreason eq "normal"){
            if($rlastdir eq "up" ){
              $rcurrpos = 100;
              $pct      = $pctnormal?100:0;
              $position = "open"
            }else{
              $rcurrpos = 0;
              $pct      = $pctnormal?0:100;
              $position = "closed";
            }
          }
        }
        Log3 $name,3,"[Shelly_status1G] device $name: no blind position received from device, we calculate pct=$pct, position=$position";
      }
      $rstate = "pct-". 10*int($pct/10+0.5)      if( $rstate eq "stopped" );   # format for state-Reading   with steps of 10

      readingsBulkUpdateMonitored($hash,"state".$subs,$rstate);
      readingsBulkUpdateMonitored($hash,"pct".$subs,$pct);
      readingsBulkUpdateMonitored($hash,"position".$subs,$position);
      readingsBulkUpdateMonitored($hash,"stop_reason".$subs,$rstopreason);
      readingsBulkUpdateMonitored($hash,"last_dir".$subs,$rlastdir);
    }
  #-----------------------------------------------------------------------------------------
  #-- we have a lights device, eg shellydimmer, shellyrgbw, shellybulb or shellyduo
  }elsif( $shelly_models{$model}[2] > 0 ){
    my $dimmers = $shelly_models{$model}[2];
    $dimmers = 1 if( $mode eq "color" );
    for( my $i=0;$i<$dimmers;$i++){
      $subs = (($dimmers == 1) ? "" : "_".$i);
      $ison = $jhash->{'lights'}[$i]{'ison'};
      $ison =~ s/0|(false)/off/;
      $ison =~ s/1|(true)/on/;
      # colors
      if( $mode eq "color" ){
          my $red   = $jhash->{'lights'}[0]{'red'};   # 0 .... 255
          my $green = $jhash->{'lights'}[0]{'green'};
          my $blue  = $jhash->{'lights'}[0]{'blue'};
          my $white = $jhash->{'lights'}[0]{'white'};
          my $gain  = $jhash->{'lights'}[0]{'gain'};  # 0 .... 100
          Shelly_readingsBulkUpdate($hash,"gain",$gain,"pct");   ##si

          if( defined $gain && $gain <= 100 ) { # !=
             $red   = round($red*$gain/100.0  ,0);
             $blue  = round($blue*$gain/100.0 ,0);
             $green = round($green*$gain/100.0,0);
          }
          readingsBulkUpdate($hash,"L-red",$red);
          readingsBulkUpdate($hash,"L-green",$green);
          readingsBulkUpdate($hash,"L-blue",$blue);
          readingsBulkUpdate($hash,"L-white",$white);
          readingsBulkUpdate($hash,"rgb",sprintf("%02X%02X%02X", $red,$green,$blue));
          readingsBulkUpdate($hash,"rgbw",sprintf("%02X%02X%02X%02X", $red,$green,$blue,$white));
          Shelly_readingsBulkUpdate($hash,"white",round($white/2.55,1),"pct");    #percentual value  ##si
          if(0){
             my ($hue,$sat,$bri)  = Color::rgb2hsv($red/255,$green/255,$blue/255);
             readingsBulkUpdate($hash,"HSV",sprintf("%d,%4.1f,%4.1f",$hue*360,100*$sat,100*$bri)); # 'hsv' will have interference with widgets for white
          }
      # brightness (white-devices only)
      }else{
        Shelly_readingsBulkUpdate($hash,"pct".$subs,$jhash->{'lights'}[$i]{'brightness'},"pct");
      }

      # effect
      if( defined($jhash->{'lights'}[$i]{'effect'}) ){
        my $effect = $jhash->{'lights'}[$i]{'effect'}; # values: 0,1,2,3
        readingsBulkUpdateMonitored($hash,"effect".$subs, $effect );
      }

      # color-temperature ct
      if( defined($jhash->{'lights'}[$i]{'temp'}) ){  # eg shellybulb in white-mode
        Shelly_readingsBulkUpdate($hash,"ct".$subs,$jhash->{'lights'}[$i]{'temp'},"ct");
      }

      # timer
      $remaining  = $jhash->{'lights'}[$i]{'timer_remaining'};
      Shelly_readingsBulkUpdate($hash,"timer".$subs,$remaining,"time");

      # source
      $source = $jhash->{'lights'}[$i]{'source'};  # 'timer' will occur as 'http'
      readingsBulkUpdateMonitored($hash,"source".$subs,$source);

      # 'sub'-state of channels, reading is 'light_$i'
      if(($model eq "shellydimmer") || ($model eq "shellyrgbw" && $mode eq "white")){
        readingsBulkUpdateMonitored($hash,"light".$subs,$ison);  # until 4.09a: "state"
      }
    }
    readingsBulkUpdateMonitored($hash,"state", ($dimmers > 1)?"OK":$ison);
    Log3 $name,$VERB,"[Shelly_status1G] finished processing lights-device $name is $model and mode is $mode.";
  #-----------------------------------------------------------------------------------------
  }else{
    Log3 $name,$VERB,"[Shelly_status1G] Model of device $name is $model and mode is $mode. Status updates every ".$hash->{INTERVAL}." seconds. ";
    readingsBulkUpdateMonitored($hash,"state","OK");
  }
  #-----------------------------------------------------------------------------------------
  #-- common to all models
  #- uptime
  Shelly_readingsBulkUpdate($hash,"uptime",$jhash->{uptime},"time=5");

  #- checking firmware and if updates are available
  my $hasupdate = $jhash->{update}{has_update};
  my $updatestatus=$jhash->{update}{status};     # values of <ip>/ota call are: unknown, idle, pending, updating
  ##my $firmware_  = $jhash->{update}{old_version};
  ##my $betafw    = $jhash->{update}{beta_version};
  ##$firmware_     =~ /.*\/(v[0-9.]+(-rc\d|-\d|)).*/;  # catching v1.12.1 or v1.12-1 or v1.12.1-rc1
  ##$firmware_     = $1 if( length($1)>5 ); # very old versions don't start with v...

  my $firmware = $jhash->{update}{old_version};
  readingsBulkUpdateIfChanged($hash,"firmware_ID",$firmware);   # long version   find same in /settings call as {fw} 
  
  my $update = $jhash->{update}{new_version};
  $update = "none" if( $update eq $firmware );
  
  my $upd_beta = $jhash->{update}{beta_version};
  $upd_beta = "none"  if( !defined($upd_beta) || $upd_beta eq $firmware );
  
  my ($firmware_curr,$fwtxt,$icon)=Shelly_firmwarecheck($hash,
             $jhash->{update}{old_version},
             $update,
             $upd_beta
             ); 
  readingsBulkUpdateIfChanged($hash,"firmware_current",$firmware_curr);  # eg. v1.14.0
  readingsBulkUpdateIfChanged($hash,"firmware_updText",$fwtxt);
  readingsBulkUpdateIfChanged($hash,"firmware_updIcon",$icon);
  ##readingsBulkUpdateIfChanged($hash,"firmware_beta",$upd_beta)   if( $upd_beta ne "none" );
  
  #write out deprecated reading 'firmware'
  $firmware = $firmware_curr;
  if( $hasupdate ){
     my $newfw  = $jhash->{'update'}{'new_version'};
     $newfw     =~ /.*\/(v[0-9.]+(-rc\d|)).*/;
     $newfw     = $1;
     $firmware .= "(update needed to $newfw)";
  }
  ##readingsBulkUpdateIfChanged($hash,"firmware",$firmware);  ## deprecated
  

  if( $updatestatus ne "idle" ){
    readingsBulkUpdateIfChanged($hash,"update_status",$updatestatus);
  }else{
    fhem("deletereading $name update_status");
  }

  #- cloud
  my $hascloud = $jhash->{'cloud'}{'enabled'};
  if( $hascloud ){
    my $hasconn  = ($jhash->{'cloud'}{'connected'}) ? "connected" : "not connected";
    readingsBulkUpdateIfChanged($hash,"cloud","enabled($hasconn)");
  }else{
    readingsBulkUpdateIfChanged($hash,"cloud","disabled");
  }

  #-----------------------------------------------------------------------------------------
  #-- looking for metering values; common to all models with at least one metering channel
  Log3 $name,$VERB,"[Shelly_status1G] $name: Looking for metering values";
  if( $shelly_models{$model}[3]>0 ){
    #-- how much meters ?
    my $meters  = $shelly_models{$model}[3];
    if( $mode eq "roller" ){
        #-- for roller devices, number of meters is equal to number of rollers
        $meters = $shelly_models{$model}[1];
    }elsif( $mode eq "color" ){
        #-- Shelly RGBW in color mode has only one metering channel
        $meters = 1;
    }
    #-- name of meters is different
    my $metern = ($model =~ /shelly.?em/)?"emeters":"meters";

    my $powerTTL =0;  # we will increment by power value of each channel
    my $energyTTL=0;
    my $returnedTTL=0;

    #-----looping all meters of the device
    for( my $i=0;$i<$meters;$i++){
      $subs  = ($meters == 1) ? "" : "_".$i;

      #-- for roller devices store last power value (otherwise you mostly see nothing)
      my $powerR = -1;
      if( $mode eq "roller" ){
          $powerR = ReadingsNum($name,"power".$subs,0);
          Shelly_readingsBulkUpdate($hash,
             "power_last".$subs,                              # name of reading
             $powerR.$si_units{power}[$hash->{units}]." ".
             ReadingsVal($name,"last_dir".$subs,""),          # value
             undef,undef,
             ReadingsTimestamp($name,"power".$subs,"") )      # timestamp
                                             if( $powerR > 0 );
      }

      #-- Power is provided by all metering devices, except Shelly1 (which has a power-constant in older fw)
      $power = $jhash->{$metern}[$i]{power};
      Shelly_readingsBulkUpdate($hash,"power".$subs,$jhash->{$metern}[$i]{power},"power");
      $powerTTL += $power;
  Log3 $name,7,"[Shelly_status1G] $name metering sbs=$subs meters=$meters mName=$metern pwr=$powerR/$power dir=".ReadingsVal($name,"last_dir".$subs,"x");

      #-- Energy is provided except Shelly1 and Shellybulb/Vintage/Duo, ShellyUni
      if( defined($jhash->{$metern}[$i]{'total'}) ) {
          $energy = $jhash->{$metern}[$i]{'total'};
          $energyTTL += $energy;
          Shelly_readingsBulkUpdate($hash,"energy".$subs,$energy,$model =~ /shelly.?em/ ? "energy/Wh" : "energy/Wm");
      }

      #-- Overpower: power value messured from device as overpowered, otherwise 0 (zero); not provided by all devices
      if( defined($jhash->{$metern}[$i]{'overpower'}) && $model !~ /rgbw/ ){  # 'defined' seems not working properly
          $overpower = $jhash->{$metern}[$i]{'overpower'};
          Shelly_readingsBulkUpdate($hash,"overpower".$subs,$overpower,"power");
      #-- for Shelly.EM  or  ShellyRGBW  use boolean state of relay instead
      }elsif( $i>=0 && $model !~ /bulb/ && $model ne "shelly1" ){
        if( defined($jhash->{'relays'}[$i]{'overpower'}) ){
          $overpower = $jhash->{'relays'}[$i]{'overpower'};    # true if device was overpowered, otherwise false
        }elsif( defined($jhash->{'meters'}[$i]{'overpower'}) ){
          $overpower = $jhash->{'meters'}[$i]{'overpower'};    # true if device was overpowered, otherwise false
        }else{
          $overpower = "-";    # initialize
        }
        $overpower =~ s/0|(false)/off/;
        $overpower =~ s/1|(true)/on/;
        readingsBulkUpdateMonitored($hash,"overpower".$subs,$overpower);
      }

      #-- Returned energy, voltage only provided by ShellyEM and Shelly3EM
      if( $model =~ /shelly.?em/ ) {
          my $energy_returned  = $jhash->{$metern}[$i]{'total_returned'};
          $returnedTTL += $energy_returned;
          Shelly_readingsBulkUpdate($hash,"energy_returned".$subs,$energy_returned,"energy/Wh");

          my $voltage = $jhash->{$metern}[$i]{'voltage'};
          Shelly_readingsBulkUpdate($hash,'voltage'.$subs,$voltage,"voltage");

          my ($pfactor,$freq,$current);
          my $apparentPower=0;
          my $reactivePower=0;
          # apparent power = Scheinleistung
          # reactive power = Blindleistung

          if( defined($jhash->{$metern}[$i]{'reactive'}) ){ #reactive power only provided by ShellyEM
              $reactivePower = $jhash->{$metern}[$i]{'reactive'};
              # calculate Apparent Power and Power Factor
              $apparentPower = sprintf("%4.1f",sqrt( ($power * $power) + ($reactivePower * $reactivePower) ));
              $pfactor = ($apparentPower != 0)?(int($power / $apparentPower * 100) / 100):"0";
          }
          if( defined($jhash->{$metern}[$i]{'pf'}) ){ #power factor only provided by Shelly3EM
              $pfactor  = $jhash->{$metern}[$i]{'pf'};
              $apparentPower = sprintf("%4.1f",$power / $pfactor)   if( $pfactor !=0 );
              my $v=($apparentPower * $apparentPower) - ($power * $power);
              $reactivePower = sprintf("%4.1f",($v<=>0)*sqrt( abs($v) ));#    if($apparentPower>$power);
              $current      = $jhash->{$metern}[$i]{'current'};
              Shelly_readingsBulkUpdate($hash,'current'.$subs,$current,"current");
          }
          $freq = $jhash->{$metern}[$i]{'freq'};
          Shelly_readingsBulkUpdate($hash,'powerFactor'.$subs,$pfactor);
          Shelly_readingsBulkUpdate($hash,'frequency'.$subs,$freq,"frequency");
          Shelly_readingsBulkUpdate($hash,'apparentpower'.$subs,$apparentPower,"apparentpower");
          Shelly_readingsBulkUpdate($hash,'reactivepower'.$subs,$reactivePower,"reactivepower");
      }
    }   #-- end looping all meters
    if( $meters>1 ){  #write out values for devices with more than one meter
        Shelly_readingsBulkUpdate($hash,"power_TTL",$jhash->{'total_power'},"power");  #not provided by Shelly4
        
        Shelly_readingsBulkUpdate($hash,"energy_TTL",$energyTTL,$model =~ /shelly.?em/ ? "energy/Wh" : "energy/Wm");
        if( $model =~ /shelly.?em/ ){
            Shelly_readingsBulkUpdate($hash,"energy_returned_TTL",$returnedTTL,"energy/Wh");
            #---try to calculate an energy balance
            Shelly_readingsBulkUpdate($hash,"Total_Energy",$energyTTL-$returnedTTL,"energy/Wh");
            #---
            #-- the calculated total power value may be obsolete, if always equal to the read total_power (see above)
            Shelly_readingsBulkUpdate($hash,"power_TTLc",$powerTTL,"power");
     #   }elsif( $model eq "shellyrgbw" && $mode eq "white" ){  #Shellyrgbw is remaining total power value if state=off and pct>0 & timer>0
          #  readingsBulkUpdateMonitored($hash,"power_TTLc",$powerTTL.$si_units{power}[$hash->{units}]);
        }elsif( $model eq "shelly4" ){  #Shelly4 does not calculate total power value
            Shelly_readingsBulkUpdate($hash,"power_TTL",$powerTTL,"power");
        }
    }
  }
  #-----------------------------------------------------------------------------------------
  #looking for inputs
  if( AttrVal($name,"showinputs","show") eq "show" && defined($jhash->{'inputs'}[0]{'input'}) ){ # check if there is at least one input available
      my ($subs, $ison, $event, $event_cnt);
      my $inpn=$shelly_models{$model}[5]; #number of inputs
      my $i=0;
      while( $i<$inpn ){
        $subs = ($inpn==1?"":"_$i");  # subs
        $ison = $jhash->{'inputs'}[$i]{'input'};
        $ison = "unknown" if(length($ison)==0);
        $ison =~ s/0|(false)/off/;
        $ison =~ s/1|(true)/on/;
        Log3 $name,$VERB,"[Shelly_status1G] $name has input $i with state \"$ison\" ";
        readingsBulkUpdateMonitored($hash,"input".$subs,$ison); # if( $ison );  ## button
        $event = $jhash->{'inputs'}[$i]{'event'};
        $event_cnt = $jhash->{'inputs'}[$i]{'event_cnt'};
        if( $event ){
            readingsBulkUpdateMonitored($hash,"input$subs\_actionS",$event);
            readingsBulkUpdateMonitored($hash,"input$subs\_action",$fhem_events{$event}, 1 );
        }
        #readingsBulkUpdateMonitored($hash,"input$subs\_cnt",$event_cnt,1) if( $event_cnt );
        readingsBulkUpdateMonitored($hash,"input$subs\_cnt",$event_cnt) if( $event_cnt );

        if(0 && defined($jhash->{'inputs'}[$i]{'last_sequence'}) && $jhash->{'inputs'}[$i]{'last_sequence'} eq ""  && $model eq "shellyi3" ){
             # for a shellyi3 with an input configured as TOGGLE this reading is empty
             fhem("deletereading $name input$subs\_.*");
        }
        $i++;
      }
  }
  #-----------------------------------------------------------------------------------------
  #-- for most of the models set internal temperature reading and status
  Shelly_readingsBulkUpdate($hash,"inttemp",$jhash->{temperature}//$jhash->{tmp}{tC},"tempC");
  Shelly_readingsBulkUpdate($hash,"inttempStatus",$jhash->{'temperature_status'});
  Shelly_readingsBulkUpdate($hash,"overtemperature",$jhash->{'overtemperature'});
  
  #-- look for external sensors
  if( $jhash->{'ext_temperature'} ){
    my %sensors = %{$jhash->{'ext_temperature'}};
    foreach my $temp (keys %sensors){
      Shelly_readingsBulkUpdate($hash,"temperature_".$temp,$sensors{$temp}->{'tC'},"tempC");
    }
  }
  if( $jhash->{'ext_humidity'} ){
    my %sensors = %{$jhash->{'ext_humidity'}};
    foreach my $hum (keys %sensors){
      Shelly_readingsBulkUpdate($hash,"humidity_".$hum,$sensors{$hum}->{'hum'},"humidity");
    }
  }
  # calibration status
  my $calib = $jhash->{calibrated};
  if( defined($calib) ){
            $calib =~ s/0|(false)/no/;
            $calib =~ s/1|(true)/yes/;
            readingsBulkUpdateMonitored($hash,"calibrated",$calib);
  }
  #-----------------------------------------------------------------------------------------
  #-- scheduling next status update
  if( $remaining>0 ){
            if( $hash->{INTERVAL}==0 ){
                $statusTmr1G  = $remaining+0.95;
            }else{
                $statusTmr1G  = minNum($hash->{INTERVAL},$remaining+0.95);
            }
  }
  
  if( $statusTmr1G==0 && $hash->{INTERVAL}==0 ){
      Log3 $name,4,"[Shelly_status1G:iv0] $name status update is finished, no retrigger";
      $statusTmr1G = -1;    #-- to skip here
  }elsif( $statusTmr1G > $hash->{INTERVAL} + 3 && $hash->{INTERVAL} > 0 ){
      #-- override scheduling next status update: perform multiple updates
      $statusTmr1G = $statusTmr1G / ceil($statusTmr1G/$hash->{INTERVAL});   # use POSIX required
  }
  Log3 $name,6,"[Shelly_status1G:ti] $name timer=$statusTmr1G INTERVAL=".$hash->{INTERVAL}." helper=".$hash->{helper}{timer};
  
  readingsEndUpdate($hash,1);
  
  if( $statusTmr1G > 0 ){
      #-- scheduling next status update
      Shelly_status($hash,"Shelly_status1G",$statusTmr1G);
  }
  
  #-- call settings
  if( time()-$hash->{helper}{settings_time} > 36.00 ){        
         Shelly_HttpRequest($hash,"/settings",undef,"Shelly_settings1G" );
  }
} #end Shelly_status1G


########################################################################################
#
# Shelly_settings1G - process data from device 1st generation
#                   /settings call
#
########################################################################################

sub Shelly_settings1G {
  my ($param,$jhash) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $model = AttrVal($name,"model","generic");
  my $reqestcall = $param->{cmd};
  my $VERB=5;
  
  Log3 $name,$VERB,"[Shelly_settings1G] $name: processing JSON-Hash from \'$reqestcall\' call";#4
  my ($chn,$i,$subs,$onoff,$val);

  readingsBeginUpdate($hash);

  #-----------------------------------------------------------------------------------------
  if( $reqestcall eq "/settings" ){

        ### Wifi Access Point
        my $ap_ssid = $jhash->{wifi_ap}{ssid};
        if( $ap_ssid ){
             my $ap_key = $jhash->{wifi_ap}{key};
             my $ap_is_open = ($ap_key eq ""?"open":"password");

             my $ap_enabled = $jhash->{wifi_ap}{enabled};
             $ap_enabled =~ s/(true|1)/enabled/;
             $ap_enabled =~ s/(false|0)/disabled/;

             readingsBulkUpdateIfChanged($hash,"ap","$ap_enabled $ap_is_open");
             readingsBulkUpdateIfChanged($hash,"ap_name",$ap_ssid);
        }

        ### Restricted Login
        my $restricted_login = $jhash->{login}{enabled};
        $restricted_login =~ s/(true|1)/username:password/;
        $restricted_login =~ s/(false|0)/open/;
        readingsBulkUpdateIfChanged($hash,"login",$restricted_login);
        my $username = $jhash->{login}{username};
        my $msg="username:password";
        if(0&& $restricted_login eq "open" ){
          if( $username eq AttrVal($name,"shellyuser","") ){
            $msg="attribute shellyuser is defined, but restricted login is not enabled";
          }else{
            $msg="attribute shellyuser is different from Shellies username";
          }
          readingsBulkUpdateIfChanged($hash,"login","$msg");
        }



    my $profile = $jhash->{mode}; # all Gen1 devices with relays or lights (except Shelly4pro)  have this reading, even single-mode devices
    if( !defined($profile) ){
            if( $model eq "shellyi3" ){
                $profile = "input";
            }else{
                $profile = "relay";  #AttrVal($name,"mode","");
            }
    }
    Log3 $name,$VERB,"[Shelly_settings1G] the mode of device $name is \'$profile\'";

    #-- we have a switch type device and 'relay'-mode, e.g. shelly1, shelly1pm, shelly4pro, shelly2, shelly2.5, shellyplug or shellyem
    if( $shelly_models{$model}[0]>0 && $profile ne "roller" ){  # relay-devices
          $chn = $shelly_models{$model}[0];
          for( $i=0;$i<$chn;$i++ ){
              $subs = ($chn>1 ? "_$i" : "" );
              # when an on/off value is given, then the on/off function is enabled, otherwise disabled
              # when enabled, the default value is 30 sec
              foreach $onoff ("on","off"){
                  Shelly_readingsBulkUpdate($hash,"auto_$onoff$subs",$jhash->{relays}[$i]{"auto_$onoff"},"time=0");
              }
              # relay name; don't use Umlaute
              Shelly_readingsBulkUpdate($hash,"relay$subs\_name",$jhash->{relays}[$i]{name} );# if( defined($val) );
          }

          #-- we have a shellyuni device
          if($model eq "shellyuni") {
              my  $val;
              foreach my $relay ( 0, 1 ){
                 $val = sprintf("over %3.3f %s %s, under %3.3f %s %s",
                          $jhash->{adcs}[0]{relay_actions}[$relay]{over_threshold}/1000,
                          $si_units{voltage}[$hash->{units}],
                          $jhash->{adcs}[0]{relay_actions}[$relay]{over_act},
                          $jhash->{adcs}[0]{relay_actions}[$relay]{under_threshold}/1000,
                          $si_units{voltage}[$hash->{units}],
                          $jhash->{adcs}[0]{relay_actions}[$relay]{under_act}
                          );
                 $val =~ s/_/ /; # substitue underline by space
                 $val = "disabled" if( $val !~ /relay/ );
                 readingsBulkUpdateMonitored($hash,"relay_$relay\_adcs_action",$val);
              }
          }
    #-----------------------------------------------------------------------------------------
    }elsif($shelly_models{$model}[2]>0){  # lights-devices
       #
       #-- Shellybulbs, ShellyRGBW
          $chn = $shelly_models{$model}[2];
          $chn = 1 if( AttrVal($name,"mode", "color") eq "color" );
          for( $i=0;$i<$chn;$i++ ){
              $subs = ($chn>1 ? "_$i" : "" );
              # transition -- transition time (in milli-seconds) 0 .... 5000
              Shelly_readingsBulkUpdate($hash,"transition$subs",$jhash->{lights}[$i]{transition},"time_ms");
              
              # auto_on, auto_off -- default timer in seconds
              foreach $onoff ("on","off"){
                  Shelly_readingsBulkUpdate($hash,"auto_$onoff$subs",$jhash->{lights}[$i]{"auto_$onoff"},"time=0");
              }
          }
       # effect: ShellyRGBW2 in color mode
       Shelly_readingsBulkUpdate($hash,"effect",$jhash->{lights}[0]{effect}); # no subs
  
       #-- Shellydimmer
       Shelly_readingsBulkUpdate($hash,"transition",$jhash->{transition},"time_ms");
    }
    #-----------------------------------------------------------------------------------------
    # common to all 1G-devices
    # coiot
    my $coiot = $jhash->{coiot}{enabled};
    $coiot = $jhash->{coiot_execute_enable} if( !defined($coiot) ); # old fw of shelly4
    readingsBulkUpdateIfChanged($hash,"coiot",$coiot==1?"enabled":"disabled");
    Shelly_readingsBulkUpdate($hash,"coiot_period",$jhash->{coiot}{update_period}//-1,"time=4");
                    #   defined($jhash->{coiot}{update_period})?$jhash->{coiot}{update_period}.$si_units{time}[$hash->{units}]:"disabled");
    # ap-roaming
    my $ap_roaming = $jhash->{ap_roaming}{enabled} // 2 ;
    $ap_roaming = $jhash->{ap_roaming}{threshold}  if( $ap_roaming == 1 );
    Shelly_readingsBulkUpdate($hash,"network_wifi_roaming",$ap_roaming,"rssi=3");
    
    # name
    Shelly_readingsBulkUpdate($hash,"name",$jhash->{name} ); 

    my %comp = (  # name of the reading where to find input's settings
        # profile   # component
        "relay"  => "relays",
        "roller" => "rollers",
        "white"  => "lights",
        "color"  => "lights",
        "input"  => "inputs"
        );
    my $dev = $comp{$profile};

    Log3 $name,$VERB,"[Shelly_settings1G] $name: getting input-settings as model $model from: /$dev/channel";

    #Inputs: settings regarding the input
    if( AttrVal($name,"showinputs","show") eq "show" && $shelly_models{$model}[5]>0 ){
          my ($btn_type,$invert,$in_mode,$in_swap);
          my $i=0;

          if( $profile eq "roller"){

            $btn_type   = $jhash->{rollers}[0]{button_type}; # toggle, momentary, detached

            $invert  = $jhash->{rollers}[0]{btn_reverse};
            $invert  =~ s/0/straight/;   # 0=(false)  = not inverted
            $invert  =~ s/1/inverted/;   # 1=(true)

            $in_mode = $jhash->{rollers}[0]{input_mode};  # roller: single=onebutton, dual=openclose
            $in_mode =~ s/openclose/dual/;
            $in_mode =~ s/onebutton/single/;

            $in_swap = $jhash->{rollers}[0]{swap_inputs};
            $in_swap =~ s/0/normal/;   # 0=(false)  = not swapped
            $in_swap =~ s/1/swapped/;   # 1=(true)

            Log3 $name,$VERB,"[Shelly_settings1G] $name: writing input-settings to inputs\_mode=$btn_type $invert $in_mode $in_swap";
            readingsBulkUpdateMonitored($hash,"inputs\_mode","$btn_type $invert $in_mode $in_swap");

          }else{
            while( defined($jhash->{$dev}[$i]{btn_type}) ){
              $subs = $shelly_models{$model}[5]==1?"":"_$i";
              $subs ="s" if( $model eq "shellydimmer" );

              # btn_type: toggle, momentary, detached, ...
              $btn_type = $jhash->{$dev}[$i]{btn_type};

              # btn_reverse:  0, 1
              if( defined($jhash->{$dev}[$i]{btn_reverse}) ){  # not supported by older fw (eg shelly4pro)
                $invert  = $jhash->{$dev}[$i]{btn_reverse};
                $invert  =~ s/0/straight/;   # 0=(false)  = not inverted
                $invert  =~ s/1/inverted/;   # 1=(true)
              }else{
                $invert = "";
              }
              if( $model eq "shellydimmer" ){
                   $in_swap = $jhash->{$dev}[0]{swap_inputs};
                   $in_swap =~ s/0/normal/;   # 0=(false)  = not swapped
                   $in_swap =~ s/1/swapped/;  # 1=(true)
              }else{
                   $in_swap = "";
              }
              Log3 $name,$VERB,"[Shelly_settings1G] $name: writing input-settings to input$subs\_mode=$btn_type $invert $in_swap";
              readingsBulkUpdateMonitored($hash,"input$subs\_mode","$btn_type $invert $in_swap");
              $i++;
            }
          }
    }
    #-----------------------------------------------------------------------------------------
    # we use the 'val' parameter to get the call silent (no screen message)
    Shelly_HttpRequest($hash,"/settings/actions",undef,"Shelly_settings1G",undef,1 ); 

  # get actions
  }elsif( $reqestcall eq "/settings/actions" ){
      # call:  /settings/actions
      my $silent=0;   # defined($param->{val})?1:0;
      my $info=0;
      $silent= 1   if( defined($param->{val}) && $param->{val}==1);
      $info  = 1   if( defined($param->{val}) && $param->{val}==2);  # we never use this
 $info=0;
      my ($e,$i,$u,$event);
      my $a=0;       # count quantity of actions, works as an index
      my $count=0;   # count quantity of URLs
      my $enabled=0; # count quantity of enabled URLs/actions
      my $unused=0;  # count quantity of unused actions
      my $controlled=0;  # count quantity of URLs controlled by this fhem-instance
      my $msg = "check & update actions on device $name:";
      if( $shelly_events{$model}[0] ne "" ){
        $msg ="<thead><tr><th>Name</th><th>Channel&nbsp;</th>";
        $msg.="<th>Index&nbsp;</th><th>URL</th><th>EN/DIS</th>"   unless( $info );
        $msg.="</tr></thead><tbody>";
        my $url;
        my $host_ip = AttrVal($name,"host_ip",undef)//qx("\"hostname --all-ip-addresses\"");   # local   same as option -I
        foreach my $m ($model,"addon1"){
          # parsing %shelly_events
          for( $e=0; $event = $shelly_events{$m}[$e] ; $e++ ){
            for( $i=0; defined($jhash->{actions}{$event}[$i]{index}) ;$i++ ){
              for( $u=0; $u<5 ; $u++ ){
                $url=$jhash->{actions}{$event}[$i]{urls}[$u];
                if( $info ){
                   $msg.="<tr><td>$event &nbsp;</td><td> $i &nbsp;</td></tr>";
                }elsif( defined($url) ){
                   $msg.="<tr><td>$event &nbsp;</td><td> $i &nbsp;</td>";
                   $msg.="<td> $u &nbsp;</td><td>$url &nbsp;</td><td>" ;
                   $count++;
                   if( $jhash->{actions}{$event}[$i]{enabled} == 1 ){
                      $enabled++ ;
                      $msg .= "EN";
                   }else{
                      $msg .= "DIS";
                   }
                   $url =~ m/\/\/(.*):/;
                   my $ipaddr=$1;
                   if( $host_ip =~ /$ipaddr/ ){  # we don't check name of Action, because not supported by Gen1
                      $controlled++;
                   }
                   $msg .="</td></tr>";
                }elsif( $u == 0 ){
                   $unused++;
                   $msg.="<tr><td>$event &nbsp;</td><td> $i </td><td> $u </td><td>no URL defined</td></tr>";
                }
                last if( $info );  # quit the loop
              }
              $a++; # increment
            #  last if( $info );  # quit the loop
            }
          }
        }
        $msg .= "</tbody>";
        unless( $info ){
          $msg .= "<tfoot><tr><td>  &nbsp; </td></tr>";
          $msg .= "<tr><td>Total actions   </td><td>$a       </td></tr>";
          $msg .= "<tr><td>Total URLs      </td><td>$count   &nbsp; </td></tr>";
          $msg .= "<tr><td>Unused actions  </td><td>$unused  </td></tr>";
          $msg .= "<tr><td>Controlled URLs &nbsp; </td><td>$controlled  </td></tr>";
          $msg .= "<tr><td>Enabled actions </td><td>$enabled </td></tr></tfoot>";
        }
        $msg =~ s/%20/&blank;/g;   # improve readability     # &blank;  &#9251;   &#x2423;
        $msg = "<html><table>$msg</table></html>";
      }
      readingsBulkUpdateIfChanged($hash,"webhook_cnt","$enabled / $controlled / $count");
      FW_directNotify("FILTER=$name","#FHEMWEB:$FW_wname","FW_okDialog( \"$msg\" )", "") if($silent == 0);
  }
  #-----------------------------------------------------------------------------------------
  readingsEndUpdate($hash,1);
  $hash->{helper}{settings_time}=time();
} #end Shelly_settings1G()



########################################################################################
#
# Shelly_status2G - process status data from device 2nd generation
#                   called by: /rpc/Shelly.GetStatus
#
########################################################################################

sub Shelly_status2G {
  my ($param,$jhash) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  #  my $comp = $param->{comp};

  my $state = $hash->{READINGS}{state}{VAL};
  my $model = AttrVal($name,"model","generic");
  my $mode  = AttrVal($name,"mode","");

  my ($comp,$channels,$channel,$id);
    #(    0     1     2           3    4    5       6    7    8)
    #(relays,rollers,dimmers,  meters, NG,inputs,  EM,color,modes)
  my @chnls=@{$shelly_models{$model}};   # extract the array of 'model' out of the hash 
  
  # check we don't have a first gen device
  if( $chnls[4]==0 ){
        Log3 $name,2,"[Shelly_status2G] ERROR: calling status2G for a 1stdGen Device";
        return undef;
  } 
  # mofify number of channels for multi-mode devices
  if( $chnls[8] > 0 ){
     if( $mode eq "relay" ){
         $chnls[1]=0;
     }elsif( $mode eq "roller" ){
         $chnls[0]=0; # no relay channel
         $chnls[3]=$chnls[1]; # no of energy metering channels is number of rollers 
     }elsif( $mode eq "white" ){
         $chnls[7]=0; # no color channel
     }elsif( $mode eq "color" ){
         $chnls[2]=0; # no dimmer/white channel
         $chnls[3]=$chnls[7]; # no of energy metering channels is number of color channels         
     }
  } 
  Log3 $name,4,"[Shelly_status2G] device $name of model $model ($mode) processing one-in-all status call: @chnls";  #4

  my $timer = $hash->{INTERVAL};  # timer in seconds for next update of status via Shelly_status()
  if( $hash->{helper}{timer}>0 ){
     $timer=$hash->{helper}{timer}; 
     Log3 $name,5,"$name have set timer=$timer to helper";
  }

  readingsBeginUpdate($hash);
  my ($subs,$ison,$overpower,$voltage,$current,$power,$energy,$ret_energy,$pfactor,$freq,$minutes,$errors);  ##R  minutes errors

  ############ Processing system values. ##############################
  ############ Available for all Gen2 devices (exceptions are marked *)
  Log3 $name,5,"[Shelly_status2G:sys] $name: Processing sys values";

  ############ checking if cloud is connected
  #Note: check if cloud is allowed will result from configuration
  if(ReadingsVal($name,"cloud","none") !~ /disabled/){
         my $hasconn  = $jhash->{cloud}{connected};
         Log3 $name,5,"[Shelly_proc2G:status] $name: hasconn=" . ($hasconn?"true":"false");
         $hasconn = $hasconn ? "connected" : "not connected";
         readingsBulkUpdateIfChanged($hash,"cloud","enabled($hasconn)");
  }
  ############ checking if MQTT is connected
  #      my $hasconn  = $jhash->{mqtt}{connected} ? 'connected' : 'disconnected';

  ############ checking Blootooth BLE

  ############ checking Websocket WS

  ############ checking if firmware update is available
  ### check only if valid data is given
  if(defined( $jhash->{sys}{uptime}) ){  # uptime is always given
    my $firmware = ReadingsVal($name,"firmware_current",undef);
    if( defined($firmware) ){  
      my ($fwtxt,$icon);
      my $update = $jhash->{sys}{available_updates}{stable}{version};
      #$update = "none" if( !defined($update) );
      my $upd_beta= $jhash->{sys}{available_updates}{beta}{version};
      $upd_beta = "none" if( !defined($upd_beta) );
      ($firmware,$fwtxt,$icon)=Shelly_firmwarecheck($hash,
               $firmware,      # current fw
               $update,        # update version
               $upd_beta       # beta version
               ); 
      readingsBulkUpdateIfChanged($hash,"firmware_updText",$fwtxt);
      readingsBulkUpdateIfChanged($hash,"firmware_updIcon",$icon);
    }
  }else{
      readingsBulkUpdateIfChanged($hash,"/_device_not_found",time() );
  }

  ############ checking if connected to LAN. Is similiar given as answer to /rpc/Eth.GetStatus
  my $eth_ip = "-";
  my $netw_subs = "";
  if( ReadingsVal($name,"model_family","unknown") =~ /Pro/ ){
      $eth_ip = $jhash->{eth}{ip} if( defined($jhash->{eth}{ip}) );
      readingsBulkUpdateIfChanged($hash,"network_ip-address_LAN",$eth_ip );
      $netw_subs = "_Wifi";
  }

  ############ checking if connected to Wifi. Is similiar given as answer to /rpc/Wifi.GetStatus
  my ($wifi_ip,$wifi_ssid,$wifi_rssi);
  my $wifi_status= $jhash->{wifi}{status};  # disconnected, got ip
  if( $wifi_status eq "got ip" ){
      $wifi_ip   = $jhash->{wifi}{sta_ip};
      $wifi_ssid = $jhash->{wifi}{ssid};
      $wifi_rssi = $jhash->{wifi}{rssi};
  }else{
      $wifi_ip   = "-";
      $wifi_ssid = "-";
      $wifi_rssi = "-";
  }
  readingsBulkUpdateIfChanged($hash,"network_ip-address".$netw_subs,$wifi_ip );
  readingsBulkUpdateIfChanged($hash,"network_ssid",$wifi_ssid);
  Shelly_readingsBulkUpdate($hash,"network_rssi",$wifi_rssi,"rssi=2");

  if( $eth_ip eq "-" && $wifi_ssid eq "-" ){   # disconnected
      Shelly_error_handling($hash,"Shelly_status2G:status","not connected",2);
  }else{
      if( $eth_ip ne "-" && $wifi_ssid eq "-" ){
           $netw_subs = "(LAN)";
      }elsif( $eth_ip eq "-" && $wifi_ssid ne "-" ){
           $netw_subs = "(Wifi)";
      }elsif( $eth_ip eq $hash->{DEF} && $wifi_ssid ne "-" ){
           $netw_subs = "(LAN)";
      }elsif( $eth_ip ne "-" && $wifi_ip eq $hash->{DEF} ){
           $netw_subs = "(Wifi)";
      }else{  # LAN or Wifi - we don't know
           $netw_subs = "";
      }
      readingsBulkUpdateIfChanged($hash,"network","<html>connected to <a href=\"http://".$hash->{DEF}."\">".$hash->{DEF}."</a> $netw_subs</html>");
      $netw_subs = "online $netw_subs";
      $netw_subs = "online"  if( ReadingsVal($name,"model_family","")!~/Pro/ );
      $netw_subs =~ s/online/remote/   if( ReadingsVal($name,"network_host",undef) );  # if connected via another Shellies range extender
      readingsBulkUpdateIfChanged($hash,"network_connection",$netw_subs);
  }
  Log3 $name,6,"[Shelly_status2G:network] $name ethernet=$eth_ip,wifi=$wifi_ssid @ $wifi_rssi";

  ############ checking uptime
  Shelly_readingsBulkUpdate($hash,"uptime",$jhash->{sys}{uptime},"time=5");

  ############ checking webhook version
  my $webhook_rev = $jhash->{sys}{webhook_rev};
  readingsBulkUpdateIfChanged($hash,"webhook_ver",$webhook_rev);

  ############ processing input states ###############################
  #Inputs in button-mode (Taster) CANNOT be read out!
  #Inputs of cover devices are strongly attached to the device.
  $channels = $chnls[5]; # number of inputs
  if( $channels>0 ){
    Log3 $name,5,"[Shelly_status2G:input] Processing $channels input states for device $name ($model)";

    for($channel=0; $channel<$channels; $channel++){
        Log3 $name,5,"[Shelly_status2G:input] Processing state of input $channel for device $name";
        $id = $jhash->{"input:$channel"}{id};
        $subs = ($channels == 1) ? "" : "_".$channel;
        $ison = defined($jhash->{"input:$channel"}{state})?$jhash->{"input:$channel"}{state}:"unknown";
        $ison =~ s/0|(false)/off/;
        $ison =~ s/1|(true)/on/;
        readingsBulkUpdateMonitored($hash,"input".$subs,$ison);
    }
    if( $model eq "shellyplusuni" ){
        # has input:2 as counter
        $channel=2;
        $id = $jhash->{"input:$channel"}{id};
        $subs = ($channels == 1) ? "" : "_".$channel;
        #-- get values
        my $cnts_ttl  = $jhash->{"input:$channel"}{counts}{total};
        my $cnts_xttl = $jhash->{"input:$channel"}{counts}{xtotal};
        my $cnts_byminute  = $jhash->{"input:$channel"}{counts}{by_minute}[0];
        my $cnts_xbyminute = $jhash->{"input:$channel"}{counts}{xby_minute}[0];
        my $minute_ts = $jhash->{"input:$channel"}{counts}{minute_ts};
        my $freq = $jhash->{"input:$channel"}{freq};
        #-- set readings
        Shelly_readingsBulkUpdate($hash,"input$subs\_cnts_ttl",$cnts_ttl);
        Shelly_readingsBulkUpdate($hash,"input$subs\_cnts_xttl",$cnts_xttl);
        Shelly_readingsBulkUpdate($hash,"input$subs\_cnts_byminute",$cnts_byminute);
        Shelly_readingsBulkUpdate($hash,"input$subs\_cnts_xbyminute",$cnts_xbyminute);
        Shelly_readingsBulkUpdate($hash,"input$subs\_timestamp",$minute_ts);   #timestamp
        Shelly_readingsBulkUpdate($hash,"input$subs\_freq",$freq,"frequency" );
        #####
        # may have input:100 as analog input
        $channel=100;
        $id = $jhash->{"input:$channel"}{id};
        $subs = "_".$channel;
        #-- get values
       # my $percent  = $jhash->{"input:$channel"}{percent};
        #if( defined($percent) ){
            Shelly_readingsBulkUpdate($hash,"input$subs",$jhash->{"input:$channel"}{percent},"pct" );
       # }
        my ($id,$temperature);        
        for( my $ti=100;$ti<=105;$ti++){
            $id = $jhash->{"temperature:$ti"}{id};
            $temperature = $jhash->{"temperature:$ti"}{tC};
            next  if( !defined($id) );
            next  if( !defined($temperature) );
            $id -=100;
            Shelly_readingsBulkUpdate($hash,"temperature\_$id",$temperature,"tempC" );
        }
    }
    # set state of 'input-only' devices to OK  (may have state 'error')
    readingsBulkUpdateMonitored($hash,"state","OK") if( $model eq "shellyplusi4" );
  }
  ############ processing relay states ###############################
  $channels = $chnls[0]; # number of relays
  if( $channels>0 ){
    $comp="switch";
    Log3 $name,5,"[Shelly_status2G:switch] Processing $channels relay states for device $name ($model as $mode)";

    for($channel=0; $channel<$channels; $channel++){
        $id = $jhash->{"switch:$channel"}{id};
        $subs = ($channels == 1) ? "" : "_".$channel;
        $ison = $jhash->{"switch:$channel"}{output};
        $ison =~ s/0|(false)/off/;
        $ison =~ s/1|(true)/on/;
        Log3 $name,4,"[Shelly_status2G:switch] Setting state of relay $channel for device $name to \'$ison\'";
        readingsBulkUpdateMonitored($hash,"relay".$subs,$ison);

        # Switch Reason: Trigger for switching
        # --> init, http <-fhemWEB, WS_in, timer, loopback (=schedule?), HTTP <-Shelly-App
        readingsBulkUpdateMonitored($hash,"source".$subs,$jhash->{"switch:$channel"}{source});
    }
    #set state for multichannel relay-devices to "OK"
    readingsBulkUpdateMonitored($hash,"state",($channels == 1)?$ison:"OK");
  }
  ############ processing roller states and position ###############################
  $channels = $chnls[1]; # number of rollers
  if( $channels>0 ){
    $comp="cover";
    for($channel=0; $channel<$channels; $channel++){
      Log3 $name,5,"[Shelly_status2G:cover] Processing roller state for device $name channel $channel (we have $channels rollers)";
      $id = $jhash->{"cover:$channel"}{id};
      $subs = ($channels == 1) ? "" : "_".$channel;
      my ($rsource,$rstate,$raction,$rcurrpos,$rtargetpos,$position,$pct,$pctnormal);
      my $rlastdir = "unknown";

      #roller: check reason for moving or stopping: http, timeout *), WS_in, limit-switch,obstruction,overpower,overvoltage ...
      #  and safety_switch  (if Safety switch is enabled in Shelly -> see Cover.GetConfig)
      #timeout: either a) calculated moving-time given by target-pos  or b) configured maximum moving time
      $rsource = $jhash->{"cover:$channel"}{source}//"undefined";
      $rstate = $jhash->{"cover:$channel"}{state}//"unknown";     # returned values are: stopped, closed, open, closing, opening
      if( $rstate eq "closing" ){
          $raction = "start";
          $rstate  = "drive-down";
          $rlastdir= "down";    # Last direction:  not supported by "Cover.GetStatus"
      }elsif( $rstate eq "opening"){
          $raction = "start";
          $rstate  = "drive-up";
          $rlastdir= "up";
      }else{  # "stopped"  "closed"  "open"
          $raction = "stop";
          $rstate  = "stopped";
      }
      readingsBulkUpdateMonitored($hash,$raction."_reason".$subs,$rsource);  # readings start_reason & stop_reason
      readingsBulkUpdateMonitored($hash,"last_dir".$subs,$rlastdir)  if($rlastdir ne "unknown");
      $hash->{MOVING}   = $rstate;
      #$hash->{DURATION} = 0;
      Log3 $name,6,"[Shelly_status2G:cover] Roller id=$channel  action=$raction  state=$rstate  Last dir=$rlastdir";

      #-- for roller devices store last power & current value (otherwise you mostly see nothing)
      if( $mode eq "roller" ){
          $power = ReadingsNum($name,"power".$subs,0);
          Shelly_readingsBulkUpdate($hash,"power_last".$subs,
             $power.$si_units{power}[$hash->{units}]." ".
             ReadingsVal($name,"last_dir".$subs,""),
             undef,undef,
             ReadingsTimestamp($name,"power".$subs,"") )
                                             if( $power > 0 );
          $current = ReadingsNum($name,"current".$subs,0);
          Shelly_readingsBulkUpdate($hash,"current_last".$subs,
             $current.$si_units{current}[$hash->{units}]." ".
             ReadingsVal($name,"last_dir".$subs,""),
             undef,undef,
             ReadingsTimestamp($name,"current".$subs,"") )
                                             if( $current > 0 );
      }

      #-- open 100% or 0% ?
      $pctnormal = (AttrVal($name,"pct100","open") eq "open");

      # Receiving position of Cover, we always receive a current position of the cover, but sometimes position is lost
      if( defined($jhash->{"cover:$channel"}{current_pos}) ){
          $rcurrpos = $jhash->{"cover:$channel"}{current_pos};
          $pct = $pctnormal ? $rcurrpos : 100-$rcurrpos;
          $position = ($rcurrpos==100) ? "open" : ($rcurrpos==0 ? "closed" : $pct);
          $rstate = "pct-". 10*int($pct/10+0.5)     if( $rstate eq "stopped" );   # format for state-Reading
      }else{
          $pct = "unknown";
          $position = "position lost";
          $rstate = "Error: position";
      }

      Log3 $name,6,"[Shelly_status2G:cover] Roller id=$id  position is $position $pct"; #6
      readingsBulkUpdateMonitored($hash,"pct".$subs,$pct);
      readingsBulkUpdateMonitored($hash,"position".$subs,$position);
      readingsBulkUpdateMonitored($hash,"state".$subs,$rstate);
    }
  }
  ############ processing dimmer or white device ###############################
  $channels = $chnls[2]; # number of dimmers
  if( $channels>0 ){
    $comp="light";
    Log3 $name,5,"[Shelly_status2G:light] Processing $channels light states for device $name ($model)";

    for($channel=0; $channel<$channels; $channel++){
        Log3 $name,5,"[Shelly_status2G:light] Processing state of dimmer $channel for device $name ";#5
        $id = $jhash->{"light:$channel"}{id};
        $subs = ($channels == 1) ? "" : "_".$channel;
        $ison = $jhash->{"light:$channel"}{output};
        $ison =~ s/0|(false)/off/;
        $ison =~ s/1|(true)/on/;
        readingsBulkUpdateMonitored($hash,"light".$subs,$ison);

        # brightness (white-devices only)
        my $bri    = $jhash->{"light:$channel"}{brightness};
        Shelly_readingsBulkUpdate($hash,"pct".$subs,$bri,"pct" );

        # processing timers --> see 'emeters' below $timer

        # processing transition time
        if( $jhash->{"light:$channel"}{transition}{started_at} ){
           my $tran_start    = $jhash->{"light:$channel"}{transition}{started_at};
           my $tran_duration = $jhash->{"light:$channel"}{transition}{duration};
           my $tran_remaining= round($tran_start + $tran_duration - time() , 3);
           Shelly_readingsBulkUpdate($hash,"transition_timer" .$subs,$tran_remaining,"time" );
           Shelly_readingsBulkUpdate($hash,"transition_target".$subs,$jhash->{"light:$channel"}{transition}{target}{brightness},"pct" );
        }

        # Switch Reason: Trigger for switching
        # --> init, http <-fhemWEB, WS_in, timer, loopback (=schedule?), HTTP <-Shelly-App
        readingsBulkUpdateMonitored($hash,"source".$subs,$jhash->{"light:$channel"}{source});
    }
    #set state for multichannel light-devices to "OK"
    readingsBulkUpdateMonitored($hash,"state",($channels == 1)?$ison:"OK");
  }
  ##**##
  ############ processing internal temperature ###############################
  ### only for comp: switch,cover,light,rgb,rgbw
  if( defined($comp) ){
      # most Gen2 devices have internal temperature on each channel, eg. {light:1}{temperature}{tC}   we use only channel :0
      Shelly_readingsBulkUpdate($hash,"inttemp",$jhash->{"$comp:0"}{temperature}{tC}//$jhash->{'temperature:0'}{tC},"tempC");
      Log3 $name,5,"[Shelly_status2G:inttemp] $name processed internal temperature of comp $comp"; #5
  }else{
      Log3 $name,5,"[Shelly_status2G:inttemp] $name NO internal temperature"; #5
  }
  
  
  ############ processing energy meter readings ###############################
  # common to roller and relay, also ShellyPMmini energymeter, but not: Walldisplay
  # get number of metering channels

  ############ processing power measureing (PM) device ###############################
  if( $chnls[3]>0 ){  # number of pm1 channels
    $channels = $chnls[3]; 
    $comp="pm1" if( !defined($comp) );
    Log3 $name,5,"[Shelly_status2G:pm] Processing $channels PM channels of device $name ($model) as comp $comp";

    for( $channel=0; $channel<$channels; $channel++){
      my $CC = "$comp:$channel";
      my $id = $jhash->{$CC}{id};
      #$subs = ( $mode eq "roller" ? $shelly_models{$model}[1] : $shelly_models{$model}[3])==1?"":"_$id";
      $subs = $channels==1 ? "" : "_$id";
      Log3 $name,5,"[Shelly_status2G:emeter] $name: Processing metering channel$subs";

      $energy = $jhash->{$CC}{aenergy}{total};
      if( defined($energy) ){   # not available on RGBWW-channels with NoLoad
          Shelly_readingsBulkUpdate($hash,"current".$subs,$jhash->{$CC}{current},"current");
          Shelly_readingsBulkUpdate($hash,"power"  .$subs,$jhash->{$CC}{apower},"power");       # active power, in Watts
          Shelly_readingsBulkUpdate($hash,"state",$jhash->{$CC}{apower},"power") if($model eq "shellypmmini");
          Shelly_readingsBulkUpdate($hash,"energy".$subs,$energy,"energy/Wh");
          # Energy consumption by minute (in Milliwatt-hours) for the last minute, is cumulated while minute restarts
         ## $minutes = shelly_energy_fmt($hash,$jhash->{$CC}{aenergy}{by_minute}[0],"mWh"); # 
          Shelly_readingsBulkUpdate($hash,"energy_lastMinute".$subs,$jhash->{$CC}{aenergy}{by_minute}[0],"energy/mWh"); 
          # Returned Energy available with suitable devices/mode only, eg. ShellyPro1PM
          $ret_energy= $jhash->{$CC}{ret_aenergy}{total};
          if( defined($ret_energy) ){
              Shelly_readingsBulkUpdate($hash,"energy_returned" .$subs,$ret_energy,"energy/Wh");
              Shelly_readingsBulkUpdate($hash,"energy_purchased".$subs,$energy-$ret_energy,"energy/Wh");
          }
      }
      
      # Voltage is always available
      Shelly_readingsBulkUpdate($hash,"voltage".$subs,$jhash->{$CC}{voltage},"voltage");
          
      # PowerFactor not supported by ShellyPlusPlugS, ShellyPMmini and others
      Shelly_readingsBulkUpdate($hash,"pfactor".$subs,$jhash->{$CC}{pf} ) if( defined($jhash->{$CC}{pf}) );

      # frequency supported from fw 1.0.0, AC operated devices only
      Shelly_readingsBulkUpdate($hash,"frequency".$subs,$jhash->{$CC}{freq},"frequency") if( defined($jhash->{$CC}{freq}) );

      # on ShellyPlusRGBWpm we have:  $jhash->{$CC}{X}  with X is source,output,brightness,{temperature}{tc}

      # protection: checking for overload errors
      $errors  = $jhash->{$CC}{errors}[0];
      $errors = "none"   if(!$errors);
       #readingsBulkUpdateMonitored($hash,"errors".$subs,$errors);
      readingsBulkUpdateMonitored($hash,"protection".$subs,$errors);

      # processing timers, if present (not provided by Walldisplay)
      if( $jhash->{$CC}{timer_started_at} ){
         my ($tmrDur,$tmrEnd);
         Log3 $name,5,"[Shelly_status2G:timer] $name processing timer";
         if( $jhash->{$CC}{timer_remaining} ){
            $tmrDur = $jhash->{$CC}{timer_remaining};
            Log3 $name,4,"[Shelly_status2G:timer] $name remaining timer$subs is $tmrDur"; #5
            $tmrEnd = $tmrDur + time();
         }else{
            $tmrEnd = $jhash->{$CC}{timer_started_at} + $jhash->{$CC}{timer_duration};
            $tmrDur =  $tmrEnd - time();
            $tmrDur =  round($tmrDur,1);
            Log3 $name,4,"[Shelly_status2G:tmr] $name calculated timer$subs from start and duration is $tmrDur"; #5
         }
Log3 $name,6,"[Shelly_status2G:timer] $name calculated update timer is $timer vs duration=$tmrDur"; #5
#         $timer = minNum( $timer, $tmrDur ); 
         $timer = $hash->{INTERVAL}>0 ? minNum( $hash->{INTERVAL},$tmrDur ) : $tmrDur;# 
         Log3 $name,6,"[Shelly_status2G:timer] $name calculated update timer is $timer"; #5
         $tmrDur .= " sec = ".FmtDateTime($tmrEnd)  if( $hash->{units} );
         readingsBulkUpdateMonitored($hash,"timer".$subs,$tmrDur);
      }elsif( $jhash->{$CC}{move_started_at} ){  # cover, if moving
         Log3 $name,6,"[Shelly_status2G:move] $name processing movement-stated at=".$jhash->{$CC}{move_started_at};
         $timer = $jhash->{$CC}{move_started_at}+$jhash->{$CC}{move_timeout}-time();
         $timer +=0.25;  # extra time to avoid delays in positioning
         Log3 $name,6,"[Shelly_status2G:move] $name calculated remaining time=$timer";
         
      }elsif(ReadingsVal($name,"timer$subs",undef) ){
         readingsBulkUpdateMonitored($hash,"timer".$subs,'-');
         $hash->{helper}{timer}=0;    #<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
      }

      # calculate all periods, when given by attribute
      my @TPs=split(/,/x, AttrVal($name,"Periods", "") );
      #$unixtime = $unixtime-$unixtime%60;  # adjust to lass full minute
      my $unixtime = time();
      #$TimeStamp = FmtDateTime($unixtime-$unixtime%60); # adjust to lass full minute
      my $TimeStamp = FmtDateTime( time() );
      foreach my $TP (@TPs){
           Log3 $name,5,"[Shelly_status2G:periods] $name: calling Shelly_delta_energy for period \'$TP\' ";
           Shelly_delta_energy($hash,"energy_",$TP,$unixtime,$energy,$TimeStamp,fhem('{$isdst}',1));
      }
      #---
    } #end of metering channels loop    
  }
  ############ processing energy measureing (EM) device ###############################
  if( $chnls[6]>0 ){  # number of em/em1 channels
    $channels = $chnls[6]; 
   # $comp="em" if( !defined($comp) );
    if( $model eq "shellypro3em" ){
      $comp = "em";
    }elsif( $model eq "shellyproem50" ){
      $comp = "em1";
    }
    Log3 $name,5,"[Shelly_status2G:em] Processing $channels EM channels of device $name ($model) as comp $comp tbd";
    if( $comp eq "em" ){
        Log3 $name,5,"[Shelly_status2G:emeter] $name is of model $model and component $comp: processing errors (if any)";#5
        my $errors = undef;
        my $suffix = AttrVal($name,"EMchannels","_ABC");
        foreach my $emch ( "a_","b_","c_","total_" ){
           # checking for em-channel errors
           # may contain:  power_meter_failure, no_load
           if( defined($jhash->{'em:0'}{$emch.'errors'}[0]) ){
              $errors .= $mapping{sf}{$suffix}{$emch}.$jhash->{'em:0'}{$emch.'errors'}[0];
           }
        }
        # checking for EM-system errors
        # may contain:  power_meter_failure, phase_sequence (eg if a phase is switched off), no_load
        if( $jhash->{'em:0'}{errors}[0] ){
              $errors .= "System: ".$jhash->{'em:0'}{errors}[0];
        }
        readingsBulkUpdateMonitored($hash,"error_EM",defined($errors)?$errors:"ok");
    }elsif( $comp eq "em1" ){
                           # .... tbd
    }
  }

  ############ processing Walldisplay ambient readings ###############################
  if( $model =~ /walldisplay/ ){
        $comp = "walldisplay";
            $subs ="";
            # readings supported by the /Shelly.GetStatus call or by individual calls eg /Temperature.GetStatus
            Shelly_readingsBulkUpdate($hash,"temperature" .$subs,$jhash->{'temperature:0'}{'tC'},"tempC");
            Shelly_readingsBulkUpdate($hash,"humidity"    .$subs,$jhash->{'humidity:0'}{'rh'},"humidity");
            Shelly_readingsBulkUpdate($hash,"illuminance" .$subs,$jhash->{'illuminance:0'}{'lux'},"illuminance");
            Shelly_readingsBulkUpdate($hash,"illumination".$subs,$jhash->{'illuminance:0'}{'illumination'} );
  }

  ############ processing Shelly Plus Sensor Addon ############################### Y174Addon
  if( ReadingsVal($name,"addon","none") eq "sensor" ){
     Log3 $name,4,"[Shelly_status2G:addon] $name: processing Shelly Plus Sensor Addon";
     my %addon = (
        # keys are sensor types
        # values are: JSON-key, max number of sensors, Shellies components/Fhem readings
        "temperature"   => ["tC",     5, "temperature"],
        "humidity"      => ["rh",     1, "humidity"],  
        "voltmeter"     => ["voltage",1, 'voltmeter'],
        "digital_input" => ['state',  2, "input"],
        "analog_input"  => ['percent',2, "input"]
     );
     my $value;
     my ($jkey,$id,$comp);
     foreach my $sensor( keys %addon ){
        $comp = $addon{$sensor}[2];
        $jkey = $addon{$sensor}[0];
        for( $id=100; $id<(100+$addon{$sensor}[1]) ; $id++ ){
           next unless $jhash->{"$comp:$id"}{'id'}; 
           $subs = $id-100;
           $subs += $shelly_models{$model}[5]   if( $comp eq "input" ) ; # number of 'regular' inputs
           $subs = "_".$subs;
           if( defined($jhash->{"$comp:$id"}{$jkey}) ){
               $value = $jhash->{"$comp:$id"}{$jkey};
               Log3 $name,4,"[Shelly_status2G:addon] $name: processing Add On for $comp$subs: $jkey=$value (id=$id)";#4
               if( $sensor eq "digital_input" ){
                   $value =~ s/0|(false)/off/;
                   $value =~ s/1|(true)/on/;
               }              
               Shelly_readingsBulkUpdate($hash,$comp.$subs,$value,$sensor );
               Shelly_readingsBulkUpdate($hash,$comp.$subs."_id",$id)   if( $comp eq "input" );
           #  digital input is buggy:  state will appear even if the addon is not connected to the Shelly
           }elsif( defined($jhash->{"$comp:$id"}{errors}[0]) ){
               my $errmsg = "[Shelly_status2G:addon] $name: AddOn/$sensor: no value found for $comp$subs: id=$id";
               $errmsg .= " Error=\'".$jhash->{"$comp:$id"}{errors}[0]."\'";
               Log3 $name,3,$errmsg;             
               readingsBulkUpdateMonitored($hash,$comp.$subs,"-" );
           }
        }
     }
  }

  
  ############ processing H&T readings ###############################
  if( ReadingsVal($name,"model_ID","") eq "S3SN-0U12A" ){
            # readings supported by the /Shelly.GetStatus call 
            Shelly_readingsBulkUpdate($hash,"temperature"  ,$jhash->{'temperature:0'}{'tC'},"tempC");
            Shelly_readingsBulkUpdate($hash,"humidity"     ,$jhash->{'humidity:0'}{'rh'},"humidity");
            Shelly_readingsBulkUpdate($hash,"power_battery",$jhash->{'devicepower:0'}{'battery'}{V},"voltage");
            Shelly_readingsBulkUpdate($hash,"power_battery",$jhash->{'devicepower:0'}{'battery'}{percent},"pct");
            Shelly_readingsBulkUpdate($hash,"power_wakeup" ,$jhash->{sys}{wakeup_period},"time");
            Shelly_readingsBulkUpdate($hash,"power_external",$jhash->{'devicepower:0'}{'external'}{present}?1:0 );
  }

  #--------------------------------------------------------------------------------
  readingsEndUpdate($hash,1);

  fhem("deletereading $name error",1) if( ReadingsAge($name,"error",-1)>36000 ); # delete after 10 hours, silent
  
  #-- scheduling next status update
  Shelly_status($hash,"Shelly_status2G",$timer) if( $timer>0 );

  if( $hash->{helper}{timer} == 0  &&  $hash->{INTERVAL}>0 ){
      #-- call settings
      if( time()-$hash->{helper}{settings_time} > 360.00 ){
         Log3 $name,4,"[Shelly_status2G:final] $name is calling GetConfig";
         Shelly_HttpRequest($hash,"/rpc/Shelly.GetConfig",undef,"Shelly_settings2G","config" );
      }
  }
} #end Shelly_status2G()


########################################################################################
#
# Shelly_settings2G - process config/settings data from device 2nd generation
#
########################################################################################

sub Shelly_settings2G {
  my ($param,$jhash) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $comp = $param->{comp};
  my $model= AttrVal($name,"model","generic");
  my @chnls=@{$shelly_models{$model}};   # extract the array of 'model' out of the hash 
  my $subs;
  my $range_extender_enable;

  # check we have the comp parameter
  if( !$comp ){
        Log3 $name,2,"[Shelly_settings2G] ERROR: calling Shelly_settings2G(), but no component given";
        return undef;
  }
  # check we have a second gen device
  if( $shelly_models{$model}[4]==0 ){
        Log3 $name,2,"[Shelly_settings2G] ERROR: calling Shelly_settings2G(), but $name is not a 2ndGen Device";
        return undef;
  }
  Log3 $name,4,"[Shelly_settings2G] device $name of model $model processing component $comp";
  readingsBeginUpdate($hash);

  ################ Shelly.GetConfig
  if($comp eq "config"){
        Log3 $name,4,"[Shelly_settings2G:config] $name: processing the answer /rpc/Shelly.GetConfig";
        ### Shelly name
        my $shName = $jhash->{sys}{device}{name};  # Shelly-Name; most device also given in /rpc/Shelly.GetDeviceInfo
        readingsBulkUpdateIfChanged($hash,"name",$shName)  if( defined($shName) );  
        
        ### checking bluetooth ble
        my $ble  = $jhash->{ble}{enable};
        $ble = defined($ble) ? ($ble == 1 ? "enabled" : "disabled"):"error";
        if( $ble eq "enabled" ){ 
            readingsBulkUpdateIfChanged($hash,"ble_rpc",($jhash->{ble}{rpc}{enable}==1 ? "enabled" : "disabled")); 
        }else{
            readingsBulkUpdateIfChanged($hash,"ble_rpc","-");
         #   readingsBulkUpdateIfChanged($hash,"ble_obs","-");
        }
        readingsBulkUpdateIfChanged($hash,"ble",$ble);
        if( defined($jhash->{ble}{observer}{enable}) ){
            readingsBulkUpdateIfChanged($hash,"ble_obs",($jhash->{ble}{observer}{enable}==1 ? "enabled" : "disabled"));
        }else{
            fhem("deletereading $name ble_obs");   # 'bluetooth gateway' not supported by fw 1.5.0+
        }

        ### Cloud
        my $hascloud = $jhash->{cloud}{enable};
        Log3 $name,5,"[Shelly_settings2G:config] $name: hascloud=" . ($hascloud?"true":"false");
        if(!$hascloud ){  # cloud disabled
             readingsBulkUpdateIfChanged($hash,"cloud","disabled");
        }elsif(ReadingsVal($name,"cloud","none") !~ /enabled/){
             readingsBulkUpdateIfChanged($hash,"cloud","enabled");
        }
        ### show Wifi roaming threshold only when connected via wifi
        if( $jhash->{wifi}{roam}{rssi_thr} && ReadingsVal($name,"network_ssid","-") ne "-"){
           ##  readingsBulkUpdateIfChanged($hash,"network_wifi_roaming",$jhash->{wifi}{roam}{rssi_thr}.$si_units{rssi}[$hash->{units}]);
        }
        #**********
        # ap-roaming
        my $ap_roaming = $jhash->{wifi}{roam}{interval} // 2;
        $ap_roaming = $jhash->{wifi}{roam}{rssi_thr} if( $ap_roaming > 0 ); 
        Shelly_readingsBulkUpdate($hash,"network_wifi_roaming",$ap_roaming,"rssi=3");
        #**********

        ### Access Point network, range extender
        my $ap_ssid = $jhash->{wifi}{ap}{ssid};
        if( $ap_ssid ){
             my $ap_is_open = $jhash->{wifi}{ap}{is_open};
             $ap_is_open =~ s/(true|1)/open/;
             $ap_is_open =~ s/(false|0)/password/;

             my $ap_enabled = $jhash->{wifi}{ap}{enable};
             $ap_enabled =~ s/(true|1)/enabled/;
             $ap_enabled =~ s/(false|0)/disabled/;

             readingsBulkUpdateIfChanged($hash,"ap","$ap_enabled $ap_is_open");
             readingsBulkUpdateIfChanged($hash,"ap_name",$ap_ssid);

             my $extender = $jhash->{wifi}{ap}{range_extender}{enable};
             $extender =~ s/(true|1)/enabled/;
             $extender =~ s/(false|0)/disabled/;
             $hash->{helper}{range_extender}=$extender;
             readingsBulkUpdateIfChanged($hash,"ap_clients",$extender)   if( $extender eq "disabled");  # get no of clients, if enabled
        }

        ### Inputs: settings regarding the input
        if( AttrVal($name,"showinputs","show") eq "show" && $shelly_models{$model}[5]>0 ){
          my $profile = $jhash->{sys}{device}{profile};  # switch, cover

          if( !$profile ){
            foreach my $c ("switch","cover","light"){
              if( defined($jhash->{"$c:0"}{id}) ){
                 $profile = $c;
                 last;
              }
            }
          }

          my $c=0; # component counter
          my $i=0; # input
          my ($subs,$in_mode);
          while( defined($profile) && defined($jhash->{"$profile:$c"}{id}) ){ # parse all components
            $in_mode = $jhash->{"$profile:$c"}{in_mode};
            if( $profile eq "cover" || $profile eq "light" ){
              $i=2*$c;  # two inputs each light-channel
              # inputs mode: dimup-down with input_0 or dual dim
              if( $in_mode eq "dual_dim" ){
                 readingsBulkUpdateIfChanged($hash,"input_$i\_function","dimdown");
                 $i++;
                 readingsBulkUpdateIfChanged($hash,"input_$i\_function","dimup");
              }elsif( $in_mode eq "dual" ){
                 # inputs swapped (cover only, in dual mode) ?
                 my $in_swap = $jhash->{"cover:$c"}{swap_inputs};
                 my $dir = ($in_swap==1?"downwards":"upwards");
                 readingsBulkUpdateIfChanged($hash,"input_$i\_function",$dir);
                 $i++;
                 $dir = ($in_swap==1?"upwards":"downwards");
                 readingsBulkUpdateIfChanged($hash,"input_$i\_function",$dir);
                 $in_swap =~ s/0/normal/;    # 0=(false)  = not swapped
                 $in_swap =~ s/1/swapped/;   # 1=(true)
              }else{
                 readingsBulkUpdateIfChanged($hash,"input_$i\_function",$in_mode);  # Button set to "dim", "activate" or "detached"
                                                                              # Switch as Toggle: 'follow' or Switch as Edge: 'flip'
                 $i++;
                 readingsBulkUpdateIfChanged($hash,"input_$i\_function","detached");
              }
            }elsif( $model ne "shellyi4" ){  # switch: follow, detached
                $subs = $shelly_models{$model}[5]<2?"":"_$i";
                readingsBulkUpdateIfChanged($hash,"input$subs\_function",$in_mode);
            }
            # outputs swapped / reverse directions (cover only) ?
            if( $profile eq "cover" ){
                my $output_mode = $jhash->{"$profile:$c"}{invert_directions}==1 ? "O1=down, O2=up (swapped)" : "O1=up, O2=down";
                $subs = $shelly_models{$model}[1]==1?"":"_$i";
                readingsBulkUpdateIfChanged($hash,"output$subs\_mode",$output_mode);
            }
            $c++;            
            Log3 $name,6,"[Shelly_settings2G:config:inputs] $name is of profile=$profile and input-mode=$in_mode";
          }
   
          my ($i_start,$input,$enable,$invert);
          foreach $i_start (0, 100 ){ # eg ShellyPlusUni has input:100 as analog input
            $i=$i_start;
            while( defined($jhash->{"input:$i"}{id}) ){  # parse all inputs
               if( $i < 100 ){
                   $subs = $shelly_models{$model}[5]==1?"":"_$i";
               }else{
                   $subs = $i - 100 + $shelly_models{$model}[5];
                   $subs = "_$subs";
               }

               # type of input: button, switch, count, analog
               $input   = $jhash->{"input:$i"}{type};

               # input inverted?
               if( $input !~ /count/ ){
                 $invert  = $jhash->{"input:$i"}{invert};
                 $invert  =~ s/0/ straight /;   # 0=(false)  = not inverted
                 $invert  =~ s/1/ inverted /;   # 1=(true)
                 $input  .= $invert;
               }

               # input enabled?
               $enable  = $jhash->{"input:$i"}{enable};
               if( defined($enable) ){
                  $enable  =~ s/0/disabled /;  # 0=(false)
                  $enable  =~ s/1/enabled /;   # 1=(true)
                  $input   .= $enable;
               }else{
                  $input   .= "-";
               }

               Log3 $name,5,"[Shelly_settings2G:config] $name has input $i: $input";
               readingsBulkUpdateMonitored($hash,"input$subs\_mode",$input) if( $input );
               readingsBulkUpdateMonitored($hash,"input$subs\_name",$jhash->{"input:$i"}{name}) if( $jhash->{"input:$i"}{name} );
               $i++;
            }
          }
        }

        # looking for roller maxtime and slat-control values
        if( $shelly_models{$model}[1]>0 && AttrVal($name,"mode","-") eq "roller" ){  # $chnls
           foreach my $limit ( 'maxtime_open','maxtime_close' ){
              my $maxtime=$jhash->{'cover:0'}{$limit};
              # set attribute in silent mode, but do not save to cfg-file
              fhem("attr -silent $name $limit $maxtime") if( AttrVal($name,$limit,0) != $maxtime );
           }
           my $sc=$jhash->{'cover:0'}{slat}{enable}//-1;
           if( $sc == 1 ){
            #   $sc = $jhash->{'cover:0'}{slat}{open_time};
            #   $sc .= ",".$jhash->{'cover:0'}{slat}{close_time};
               fhem("attr -silent $name slat_control enabled");
           }elsif( $sc == 0 ){
               fhem("attr -silent $name slat_control disabled");
           }
           Log3 $name,3,"[Shelly_settings2G:config] $name: slat control is $sc";  #3
        }else{
          ### looking for auto_on & auto_off (components: switch & light)
          my @comps= ( "switch", "cover", "light" );
          foreach my $m (0,2 ){
            if($shelly_models{$model}[$m]>0){
               my ($chn,$c,$comp,$i,$val,$onoff);
               $chn = $shelly_models{$model}[$m];
               #$chn = 1 if( AttrVal($name,"mode", "color") eq "color" );
               for( $c=0;$c<$chn;$c++ ){
                  $subs = ($chn>1 ? "_$c" : "" );
                  $comp = $comps[$m].":".$c;
                  # transition -- transition time (in seconds) 0 .... 5 sec, steps of 0.1 sec
                  Shelly_readingsBulkUpdate($hash,"transition$subs",$jhash->{$comp}{transition_duration},"time");
             
                  # auto_on, auto_off -- default timer in seconds
                  foreach $onoff ("on","off"){
                     $val=$jhash->{$comp}{"auto_$onoff"} ? $jhash->{$comp}{"auto_$onoff\_delay"} : 0;
                     Shelly_readingsBulkUpdate($hash,"auto_$onoff$subs",$val,"time=1");
                  }
               }
            }
          }
        }

        ### look if an addon is present:
        if( $jhash->{sys}{device}{addon_type} ){
            readingsBulkUpdateMonitored($hash,"addon",$jhash->{sys}{device}{addon_type} );
        }elsif(ReadingsVal($name,"addon",undef)){
            fhem("deletereading $name addon");
        }
        ### temperature sensors   # 2G:addon
        if( $jhash->{sys}{device}{addon_type} ){
        Log3 $name,5,"[Shelly_settings2G:config] $name: processing add-on sensors";  #5
          for( my $sid=100; $sid<=105; $sid++ ){
            next if( !defined($jhash->{"temperature:$sid"}{name} ));
            my $jvalue= $jhash->{"temperature:$sid"}{name};
            my $fid=$sid-100;
            readingsBulkUpdateMonitored($hash,"temperature_$fid\_name",$jvalue);
          }
        }

        ### look if device is walldisplay with thermostat
        if( defined($jhash->{'thermostat:0'}{enable}) ){
            my $enable  = $jhash->{'thermostat:0'}{enable};
            $enable  =~ s/0|(false)/disabled/;  # 0=(false)
            $enable  =~ s/1|(true)/enabled/;   # 1=(true)
            readingsBulkUpdateMonitored($hash,"thermostat",$enable );
            readingsBulkUpdateMonitored($hash,"thermostat_sensor",$jhash->{'thermostat:0'}{sensor} );
            readingsBulkUpdateMonitored($hash,"thermostat_relay" ,$jhash->{'thermostat:0'}{actuator} );
            readingsBulkUpdateMonitored($hash,"thermostat_type",  $jhash->{'thermostat:0'}{type} );
            Shelly_readingsBulkUpdate($hash,"thermostat_hysteresis",$jhash->{'thermostat:0'}{hysteresis},"tempAbs" );
            Shelly_readingsBulkUpdate($hash,"thermostat_target",$jhash->{'thermostat:0'}{target_C},"temperature" );
            my $output = $jhash->{'thermostat:0'}{invert_output};
            $output  =~ s/0|(false)/straight/;  # 0=(false)
            $output  =~ s/1|(true)/inverted/;   # 1=(true)
            #$output = $output eq (false) ? 'straight' : 'inverted';
            readingsBulkUpdateMonitored($hash,"thermostat_relay_mode",  $output );
        }
        # EnergyMeter: CT Types
        if( $shelly_models{$model}[6]>0 && ReadingsVal($name,"model_function","unknown") eq "energy meter" ){
            readingsBulkUpdateMonitored($hash,"ct_type",  ($jhash->{'em:0'}{ct_type} // ($jhash->{'em1:0'}{ct_type} // "unknown")) );
        }
            
        Shelly_HttpRequest($hash,"/rpc/Shelly.GetDeviceInfo",undef,"Shelly_settings2G","info" );

  ################ Shelly.GetDeviceInfo
  }elsif($comp eq "info"){
      Log3 $name,4,"[Shelly_settings2G:info] $name: processing the answer from the \"/rpc/Shelly.GetDeviceInfo\"  call";

       $hash->{SHELLYID}=$jhash->{id};
       my $model_id = $jhash->{model};  # vendor id
       readingsBulkUpdateIfChanged($hash,"model_ID",$model_id);

       my $firmware_id   = $jhash->{fw_id};  #eg "20241011-114455/1.4.4-g7d3b567"
       readingsBulkUpdateIfChanged($hash,"firmware_ID",$firmware_id);       
       
       my $fw_shelly  = $jhash->{ver};   # the firmware information stored in the Shelly

       my $fw_fhem = ReadingsVal($name,"firmware_current","none"); # the firmware information that fhem knows

       $fw_fhem  =~ /v([^\(]*)\K(.*)/; 
       $fw_fhem  = $1;   # everything between 'v' and opening bracket '('  ;  removing  '(update needed....'
       if( $fw_fhem eq $fw_shelly ){
          Log3 $name,4,"[Shelly_settings2G:info] $name: info about current firmware Shelly and Fhem are matching: $fw_shelly";
       }else{
          Log3 $name,4,"[Shelly_settings2G:info] $name: new firmware information read from Shelly: $fw_shelly";
          readingsBulkUpdateIfChanged($hash,"firmware_current","v$fw_shelly");
       }

       if( ReadingsVal($name,"addon","none") eq "sensor" ){
           Shelly_HttpRequest($hash,"/rpc/SensorAddon.GetPeripherals",undef,"Shelly_procAddOn");
       }
       $hash->{helper}{settings_time}=time();

       $range_extender_enable = $hash->{helper}{range_extender};
       if( defined($range_extender_enable) && $range_extender_enable ne "disabled" ){
           Shelly_HttpRequest($hash,"/rpc/Wifi.ListAPClients",undef,"Shelly_settings2G","clients" );
       }elsif( $model !~ /display/ ){
          Shelly_HttpRequest($hash,"/rpc/BLE.CloudRelay.List",undef,"Shelly_settings2G","BLEclients" );
       }
       
       ### look if device is walldisplay with thermostat
       if( defined($jhash->{"relay_in_thermostat"}) ){
          foreach my $comp ( 'relay','sensor' ){
            my $val  = $jhash->{"$comp\_in_thermostat"};
            $val  =~ s/0|(false)/external/;  # 0=(false)
            $val  =~ s/1|(true)/internal/;   # 1=(true)
            readingsBulkUpdateMonitored($hash,"thermostat_$comp\_i",$val );
          }
       }
  ################ Wifi.ListAPClients
  }elsif($comp eq "clients"){
      Log3 $name,4,"[Shelly_settings2G:clients] $name: processing the answer /rpc/Wifi.ListAPClients";
      fhem("deletereading $name ap_clients.*",1); # always clear readings before re-writing / silent
      # this call return for each client:  MAC, IP-address (as client), port and timestamp
      my $xi=0;  # ap-client index
      my ($timestamp,$mac);
      my $ip_ext;  # ip at the extended network (ap of the Shelly), typical 192.168.33.nn
      my $ip_int;  # ip of the internal network, typical <ip>:<port>
      my $client_name;  # the fhem NAME of the client
      my $client;  # the fhem internal 'NAME' of the client
       
      while( $jhash->{ap_clients}[$xi]{mac} ){           
           # use the since-value as Readings-Timestamp
           $timestamp = FmtDateTime($jhash->{ap_clients}[$xi]{since});

           # MAC
           $mac = uc($jhash->{ap_clients}[$xi]{mac});    # uppercase of clients MAC
           Shelly_readingsBulkUpdate($hash,"ap_clients_$xi\_mac",$mac,undef,undef,$timestamp );

           # the ip at the extended network
           $ip_ext = $jhash->{ap_clients}[$xi]{ip};
           Shelly_readingsBulkUpdate($hash,"ap_clients_$xi\_extlink",$ip_ext,undef,undef,$timestamp );

           # intlink
           $ip_int = InternalVal($name,"DEF","ip");
           $ip_int.= ":".$jhash->{ap_clients}[$xi]{mport};
           Shelly_readingsBulkUpdate($hash,"ap_clients_$xi\_intlink",$ip_int,undef,undef,$timestamp );

           # scanning all fhem-devices for the 'MAC'           
           foreach my $d ( keys %defs ){
              # my $hash = $defs{$d};
              next  if( ($defs{$d})->{TYPE} ne "Shelly" );
               my $cname = ($defs{$d})->{NAME};
               if( defined(($defs{$d})->{READINGS}{mac}{VAL}) ){
                 if( ($defs{$d})->{READINGS}{mac}{VAL} eq $mac ){ 
                   $client_name = $cname;
                   Log3 $name,4,"[Shelly_settings2G:clients] found $cname as client of $name"; #4
                   last;
                 }
               }else{
                   Log3 $name,4,"[Shelly_settings2G:clients] checking for $name: device $cname without reading \'mac\'"; #4
               }
           }
           
           if( $client_name ){
               Log3 $name,4,"[Shelly_settings2G:APclients] $name: found client \'$client_name\' with MAC=$mac";
               Shelly_readingsBulkUpdate($hash,"ap_clients_$xi\_model",ReadingsVal($client_name,"model_name","unknown"),undef,undef,$timestamp );
               $client = InternalVal($client_name,"DEF",undef);
               if( $client ne $ip_int ) {
                   Log3 $name,1,"[Shelly_settings2G:APclients] $client_name: wrong definition \'$client\', use <DNS-name>:<port>";
                   $client = "clients \'$client_name\' definition \'$client\' is wrong";                  
               }else{
                   Log3 $name,4,"[Shelly_settings2G:APclients] device \'$client_name\' is defined as $client (OK)"; 
                   # format as clickable link
                   $client = "<html><a href=\"http://$ip_int\">$client_name</a></html>";  
               }
           }else{
               $client = "no definition";  # may be a smartphone as client - this is no error
               Log3 $name,3,"[Shelly_settings2G:APclients] $name: no fhem device found with MAC=$mac ";
           }
           Shelly_readingsBulkUpdate($hash,"ap_clients_$xi\_name",$client,undef,undef,$timestamp );
           $xi++;
      }
      # Total number of clients
    # Shelly_readingsBulkUpdate($hash,"ap_clients",$xi,undef,undef,FmtDateTime($jhash->{ts}) );     $jhash->{ts}  is null
      readingsBulkUpdateIfChanged($hash,"ap_clients",$xi);
      ###--- start next request
      if( $model !~ /display/ ){
          Shelly_HttpRequest($hash,"/rpc/BLE.CloudRelay.List",undef,"Shelly_settings2G","BLEclients" );
      }

  ################ BLE.CloudRelay.List
  }elsif($comp eq "BLEclients"){
      Log3 $name,4,"[Shelly_settings2G:BLEclients] $name: processing the answer /rpc/BLE.CloudRelay.List";
      my $ai=0;

      # /rpc/BLE.CloudRelay.List
      while( defined($jhash->{addrs}[$ai]) ){
          readingsBulkUpdateIfChanged($hash,"ble_client_$ai",$jhash->{addrs}[$ai] );
          $ai++;
      }
      while( defined(ReadingsVal($name,"ble_client_$ai",undef)) ){
          fhem("deletereading $name ble_client_$ai"); # not silent: -> logging at level 3
          $ai++;
      }
      Shelly_HttpRequest($hash,"/rpc/Script.List",undef,"Shelly_settings2G","scripts",1 ); #call silent


  ################ Script.List
  }elsif($comp eq "scripts"){
      Log3 $name,4,"[Shelly_settings2G:scripts] $name: processing the answer /rpc/Script.List"; #4
      my $i=0; #index
      my ($scriptname,$scriptid,$enable,$running);
      # /rpc/Script.List
      while( defined($jhash->{scripts}[$i]{id}) ){
          $scriptid=$jhash->{scripts}[$i]{id};
          $scriptname=$jhash->{scripts}[$i]{name};
          $enable=$jhash->{scripts}[$i]{enable};
          $enable =~ s/0/disabled/;
          $enable =~ s/1/enabled/;
          $running=$jhash->{scripts}[$i]{running};
          $running =~ s/0/stopped/;
          $running =~ s/1/running/;
          
          readingsBulkUpdateIfChanged($hash,"script_$i","$scriptid: $scriptname $enable $running" );
          $i++;
      }
      # number of scripts, write out only when scripts have been at least once 
      readingsBulkUpdateIfChanged($hash,"scripts",$i ) if( $i || $hash->{READINGS}{scripts}{VAL} );
      # delete reading of non existing scripts
      while( defined(ReadingsVal($name,"script_$i",undef)) ){   # start with the last value of $i
          fhem("deletereading $name script_$i"); # not silent: -> logging at level 3
          $i++;
      }
      Shelly_HttpRequest($hash,"/rpc/Webhook.List",undef,"Shelly_settings2G","actions",1 ); #call silent

  ################ Webhook.List
  }elsif($comp eq "actions"){
      Log3 $name,4,"[Shelly_settings2G:actions] $name: processing the answer /rpc/Webhook.List";
      my $silent = defined($param->{val})?1:0;
      my ($e,$i,$u,$id,$event,$action,$isenabled,$rev);
      my $count=0;    # counts total number of urls defined
      my $enabled=0;  # counts the number of urls of actions that are enabled
      my $unused=0;
      my $controlled=0;  # counts the number of urls controled by this fhem-instance
      my $host_ip = AttrVal($name,"host_ip",undef)//qx("\"hostname --all-ip-addresses\"");   # local   same as option -I
      my $msg="<thead><tr><th>Id</th><th>Name</th><th>Action</th><th>URL</th><th>EN/DIS</th></tr></thead><tbody>";
      my $url;
      $rev = $jhash->{rev};
      # foreach my $m ($model,"addon1"){
        # for( $e=0; $event = $shelly_events{$m}[$e] ; $e++ ){
          for( $i=0; defined($jhash->{hooks}[$i]{id}) ;$i++ ){
            $id = $jhash->{hooks}[$i]{id};
            $event = $jhash->{hooks}[$i]{event};
            $action= $jhash->{hooks}[$i]{name};
            for( $u=0; $u<5 ; $u++ ){
              $url=$jhash->{hooks}[$i]{urls}[$u];
              if( defined($url) ){
                $msg.="<tr><td>$id &nbsp;</td><td>$action &nbsp;</td><td>$event &nbsp;</td><td>$url &nbsp;</td><td>";
                $count++;
                $isenabled=$jhash->{hooks}[$i]{enable};
                $isenabled =~ s/0|(false)/DIS/;
                $isenabled =~ s/1|(true)/EN/;
                $msg .= $isenabled;
                $enabled++ if( $isenabled eq "EN" );
                my $ipaddr=""; 
                if( $url =~ m/\/\/(.*)(:\d*)?\// ){
                    $ipaddr=$1;
                }else{
                    Log3 $name,4,"[Shelly_settings2G:actions] $name: no ip-address detected in url $url"; #4
                }
                if( $action =~ /^_.*_$/ &&  $host_ip =~ /$ipaddr/ ){
                    $controlled++;  
                }
                $msg .="</td></tr>";
              }elsif( $u == 0 ){
                $unused++;
                $msg.="<tr><td>$event</td><td>no URL defined</td></tr>";
              }
            }
          }
        #}
      #}
      $msg .= "</tbody><tfoot><tr><td></td>  <td>Rev=$rev&nbsp;</td>   <td>controlled urls=$controlled&nbsp;</td>";
      $msg .= "<td>Total URLs=$count&nbsp;</td>  <td>Enabled=$enabled</td></tr></tfoot>";
      $msg =~ s/%20/&blank;/g;     # improve readability
      $msg = "<html><table>$msg</table></html>";
      $msg ="No Actions" if( $count == 0 );
      readingsBulkUpdateIfChanged($hash,"webhook_ver",$rev );
      readingsBulkUpdateIfChanged($hash,"webhook_cnt","$enabled / $controlled / $count" );
      FW_directNotify("FILTER=$name","#FHEMWEB:$FW_wname","FW_okDialog( \"$msg\" )", "") if( $silent == 0 );

  ################ Webhook.Update
  }elsif($comp eq "webhook_update"){
      Log3 $name,4,"[Shelly_settings2G:webhook_update] $name: processing the answer /rpc/Webhook.Update";
      my $rev = $jhash->{rev};
      if( !defined($rev) ){
          readingsBulkUpdateIfChanged($hash,"error","action not changed" );
      }else{
          readingsBulkUpdateIfChanged($hash,"webhook_ver",$rev );
      }
  }
  #-----------------------------------------------------------------------------------------
  readingsEndUpdate($hash,1);
} #end Shelly_settings2G()


########################################################################################
#
# Shelly_procAddOn - process config/settings of 2nd generation sensor add-on
#
########################################################################################

sub Shelly_procAddOn {
    my ($param,$jhash) = @_;
    my $hash = $param->{hash};
    my ($peripheralT,$comp_type,$comp_id,$addr,$subs,$name);
    readingsBeginUpdate($hash);
    #---------------------------------------
    if( $param->{cmd} eq "/rpc/SensorAddon.GetPeripherals" ){
      foreach $peripheralT ("digital_in", "ds18b20", "dht22", "analog_in", "voltmeter" ){
        $comp_type = $peripherals{$peripheralT};
        if( $jhash->{$peripheralT} ){
          foreach $comp_id ( 100..110 ){
            next if( !defined($jhash->{$peripheralT}{"$comp_type:$comp_id"}{addr}) );
            $addr = $jhash->{$peripheralT}{"$comp_type:$comp_id"}{addr};
            $addr =~ m/(\d\d?\d?):(\d\d?\d?):(\d\d?\d?):(\d\d?\d?):(\d\d?\d?):(\d\d?\d?):(\d\d?\d?):(\d\d?\d?)/;
            $addr = sprintf("%02X:%02X:%02X:%02X:%02X:%02X:%02X:%02X",$1,$2,$3,$4,$5,$6,$7,$8);
            $subs = "_".($comp_id-100);
            readingsBulkUpdateMonitored($hash,"$comp_type$subs\_sensor","$comp_id $peripheralT $addr" );
          }
        }
      }
    #---------------------------------------
    }elsif( $param->{cmd} eq "/rpc/SensorAddon.OneWireScan" ){
          my $dev_id=0;
          my $type;
          while( $jhash->{devices}[$dev_id]{type} ){
            $type = $jhash->{devices}[$dev_id]{type};
            $addr = $jhash->{devices}[$dev_id]{addr};
            $addr =~ m/(\d\d?\d?):(\d\d?\d?):(\d\d?\d?):(\d\d?\d?):(\d\d?\d?):(\d\d?\d?):(\d\d?\d?):(\d\d?\d?)/;
            $addr = sprintf("%02X:%02X:%02X:%02X:%02X:%02X:%02X:%02X",$1,$2,$3,$4,$5,$6,$7,$8);
            # if a device is not already registered by the shelly, component is null
            if( defined($jhash->{devices}[$dev_id]{component}) ){
              $comp_id   = $jhash->{devices}[$dev_id]{component};
              $comp_id =~ m/temperature:(\d*)/;
              $comp_id = $1;
              $subs = "_".($comp_id-100);
              readingsBulkUpdateMonitored($hash,"temperature$subs\_sensor","$comp_id:$dev_id $type $addr" );
            }else{
              $addr  = $jhash->{devices}[$dev_id]{addr};  # reload w/decimal values
              my $cmd = "?type=\"$type\"&attrs={\"addr\":\"$addr\"}";
              #$cmd = urlEncode($cmd);
              #$cmd = urlDecode($cmd);
              Shelly_HttpRequest($hash,"/rpc/SensorAddon.AddPeripheral",$cmd);
            }
            $dev_id++;
          }
    #---------------------------------------
    }elsif( $param->{cmd} eq "/rpc/SensorAddon.AddPeripheral" ){
       my $count=0;
       foreach $comp_id ( 100..110 ){
          if( defined($jhash->{"temperature:$comp_id"}) ){
              $count++;
          }
       }
       Shelly_Set($hash,$name,"reboot");
    #---------------------------------------
    }elsif( $param->{cmd} eq "/rpc/Temperature.GetConfig" ){
                   $comp_type="temperature";
        if( defined($jhash->{id}) ){
            $comp_id = $jhash->{id};
            if( defined($jhash->{name}) ){
                $name = $jhash->{name};
                $subs = "_".($comp_id-100);
                readingsBulkUpdateMonitored($hash,"$comp_type$subs\_name",$name );
            }
        $comp_id++;
        }
        return if( $comp_id > 110 );
        Shelly_HttpRequest($hash,"/rpc/Temperature.GetConfig","?id=$comp_id");
    #---------------------------------------
    }elsif( $param->{cmd} eq "/rpc/Shelly.GetConfig" ){
      my ($jelement,$jvalue,$jreading);
      # sys device
      foreach $jelement ("name","mac","fw_id","profile","addon_type" ){
          $jvalue = $jhash->{sys}{device}{$jelement};
          $jvalue = "-" unless defined($jvalue);
          $jreading = "sys_device_$jelement";
          readingsBulkUpdateMonitored($hash,$jreading,$jvalue);
      }
      # wifi
      foreach $jelement ("ap","sta","sta1" ){
          $jvalue = $jhash->{wifi}{$jelement}{ssid};
          $jvalue = "-" unless defined($jvalue);
          $jreading = "wifi_$jelement\_ssid";
          readingsBulkUpdateMonitored($hash,$jreading,$jvalue);
      }
      foreach $jelement ("rssi_thr","interval" ){
          $jvalue = $jhash->{wifi}{roam}{$jelement};
          $jvalue = "-" unless defined($jvalue);
          $jreading = "wifi_roam_$jelement";
          $jreading =~ s/{/_/g;
          $jreading =~ s/}//g;

          readingsBulkUpdateMonitored($hash,$jreading,$jvalue);
      }
      $jvalue= $jhash->{'temperature:100'}{name};
      readingsBulkUpdateMonitored($hash,"temperature_0_name",$jvalue);
    }
    #---------------------------------------
    readingsEndUpdate($hash,1);
} #end Shelly_procAddOn


########################################################################################
#
# Shelly_procEMvalues - processing ShellyPro3EM (channel=0) Energy Metering values
#                 data requested by /rpc/EM.GetStatus?id=0
#
# Parameter param, jhash
#
# Readings:     current, power (active, apparent, reactive), voltage, frequency, power factor
#
########################################################################################

sub Shelly_procEMvalues {
  my ($param,$jhash) = @_;
  my $hash=$param->{hash};
  my $name=$hash->{NAME};
  my $id=$jhash->{id};
  my $model = AttrVal($name,"model","generic");
  my @chnls=@{$shelly_models{$model}}; 

  Log3 $name,4,"[Shelly_procEMvalues] processing Shelly_procEMvalues() for device $name channel/id=$id"; #4
  return  if( $chnls[6]==0 );  # check number of EM1-channels
#  return  if( $model ne "shellypro3em" && $model ne "shellyproem50" );  # 

  readingsBeginUpdate($hash);

  my $suffix = AttrVal($name,"EMchannels","_ABC");
  my ($pr,$ps,$reading,$value);
  my ($act_power,$aprt_power,$current,$reactive_power); 
  my $power=0;  # cumulated active power

  my (@emchannels,$mpsub,$mpch);  
  if( ReadingsVal($name,"model_profile","monophase") eq "triphase" ){
    # triphase
    @emchannels = ("a_","b_","c_","total_");
    $mpsub="";
  }else{   
    # monophase
    @emchannels = ("");
    $mpsub = "_energy";
    $mpch=$id2ch[$id];
  }
  
  foreach my $emch ( @emchannels ){
      if( $suffix =~ /_$/ ){  # ABC_  L123_
          $pr=$mapping{sf}{$suffix}{$mpch//$emch};  # take $emch if $mpch is undefined
          $ps="";
      }else{          # _ABC  _L123
          $pr="";
          $ps=$mapping{sf}{$suffix}{$mpch//$emch};
      }
      # current
      $reading=$pr.$mapping{E1}{current}.$ps;
      $current=$jhash->{$emch.'current'};
      $value  =sprintf("%5.3f",$current);
      Shelly_readingsBulkUpdate($hash,$reading,$value,"current");

      # aparent power
      $reading=$pr.$mapping{E1}{aprt_power}.$ps;
      $aprt_power=$jhash->{$emch.'aprt_power'}; 
      $value  =sprintf("%4.1f",$aprt_power);
      Shelly_readingsBulkUpdate($hash,$reading,$value,"apparentpower");
      
      # active power
      $reading=$pr.$mapping{E1}{act_power}.$ps;
      $act_power=$jhash->{$emch.'act_power'};
      $value  =sprintf("%5.1f",$act_power);
      Shelly_readingsBulkUpdate($hash,$reading,$value,"power"); # store this also as helper

      if($emch ne "total_"){
          # to get latest values when calculating total pushed value
          $hash->{helper}{$emch.'Active_Power'} = $act_power;

          # voltage
          $reading=$pr.$mapping{E1}{voltage}.$ps;
          $value  =sprintf("%4.1f",$jhash->{$emch.'voltage'});
          Shelly_readingsBulkUpdate($hash,$reading,$value,"voltage");

          # power factor
          $reading=$pr.$mapping{E1}{pf}.$ps;
          $value = $jhash->{$emch.'pf'};
          $value = sprintf("%4.2f%s",abs($value),( abs($value)==1?"":" (".( $value<0 ? $mapping{E1}{cap}:$mapping{E1}{ind}).")"));
          readingsBulkUpdateMonitored($hash,$reading,$value);

          # frequency
          $reading=$pr.$mapping{E1}{frequency}.$ps;
          Shelly_readingsBulkUpdate($hash,$reading,$jhash->{$emch.'freq'},"frequency"); # supported from fw1.0.0

          $power += $act_power;
          
          # reactive power: not provided by Shelly
          # calculation of reactive power!
          $reading=$pr.$mapping{E1}{react_power}.$ps;
          $value = ($aprt_power * $aprt_power) - ($act_power * $act_power);
          $reactive_power = round( ($value<=>0)*sqrt( abs($value) ),1);
          $value = sprintf("%4.1f",$reactive_power);
          Shelly_readingsBulkUpdate($hash,$reading,$value,"reactivepower");
      }
  }
  $value = $jhash->{'n_current'};
  if( defined($value) ){
          $reading='Current_N';  ## $pr.$mapping{E1}{current}.$ps;
          $value  =sprintf("%5.3f",$value);
          Shelly_readingsBulkUpdate($hash,$reading,$value,"current");
  }
  
  ### Balancing: cumulate power values and save them in helper, will be used by Shelly_procEnergyData()
  $hash->{helper}{powerCnt}++;
  $hash->{helper}{power} += $power;
  $hash->{helper}{powerPos} += $power if($power>0);
  $hash->{helper}{powerNeg} -= $power if($power<0);  # the cumulated value is positive!

  ### ----------------------------------------
  ### get cumulated values in monophase profile
  if( ReadingsVal($name,"model_profile","monophase") ne "triphase" ){
          if( $id==0 ){   # initialize helper values
              $hash->{helper}{'act_power'}  = 0;
              $hash->{helper}{'aprt_power'}  = 0;
              $hash->{helper}{'react_power'}  = 0;
              $hash->{helper}{'current'}  = 0;
          }
          $hash->{helper}{'act_power'} += $act_power;
          $hash->{helper}{'aprt_power'} += $aprt_power;
          $hash->{helper}{'react_power'} += $reactive_power;
          $hash->{helper}{'current'} += $current;
          
          if( $id == $shelly_models{$model}[6]-1 ){ 
            # write out cumulated values when passed last channel 
            foreach my $helper( 'act_power','aprt_power','react_power','current' ){
               if( $suffix =~ /^_/ ){ # _ABC  _L123
                   $ps = '_S';
               }else{     # ABC_  L123_
                   $pr = 'S_';
               }
               $reading = $pr.$mapping{E1}{$helper}.$ps;
               Shelly_readingsBulkUpdate($hash,$reading,$hash->{helper}{$helper},$helper);
            }
          }
  }

  readingsBulkUpdateMonitored($hash,"state","OK")  if( $chnls[0]==0 );

  readingsEndUpdate($hash,1);
  #~~~~~~~~~~~~~~~~~~~~~
  
  if( ReadingsVal($name,"model_profile","monophase") ne "triphase"    &&    ++$id < $shelly_models{$model}[6] ){
         Shelly_HttpRequest($hash,"/rpc/EM1.GetStatus","?id=$id","Shelly_procEMvalues" );
         return;
  }

  if( $hash->{INTERVAL}>0 ){
      #-- initiate next run
      my $timer=AttrVal($name,"interval_power",$hash->{INTERVAL});
      RemoveInternalTimer($hash,"Shelly_getEMvalues");
      InternalTimer(time()+$timer, "Shelly_getEMvalues", $hash);
      Log3 $name,4,"[Shelly_procEMvalues] $name: next \'Get EM values\' update in $timer seconds"; #4
  }
} #end Shelly_procEMvalues()


########################################################################################
#
# Shelly_procEnergyData - processing ShellyPro energy meter Energy Data
#                 data requested by /rpc/EMData.GetStatus?id=0     ShellyPro3EM in triphase profile (channel=0)
#                 data requested by /rpc/EM1Data.GetStatus?id=$id  in monophase profile
#
# Parameter param, jhash
#
########################################################################################

sub Shelly_procEnergyData {
  my ($param,$jhash) = @_;
  my $hash=$param->{hash};
  my $name=$hash->{NAME};
  my $id=$jhash->{id};  
  my $V;  # set verbose focus; set undefined to use 'normal' verbose values
  my $model = AttrVal($name,"model","generic");

  my $unixtime = time();####$jhash->{sys}{unixtime};
  my $TimeStamp = strftime("%Y-%m-%d %H:%M:%S",localtime($unixtime) );
  my $dst = fhem('{$isdst}',1); # is daylight saving time (Sommerzeit) ?   silent/no log entry {$isdst} at level 3
  
  readingsBeginUpdate($hash);
  #readingsBulkUpdateMonitored($hash,"timestamp", $TimeStamp);
  Log3 $name,$V//5,"[Shelly_procEnergyData] processing Shelly_procEnergyData() for device $name, channel=$id";   #5

  # Energy Readings are calculated by the Shelly every minute, matching "zero"-seconds
  # with some processing time the result will appear in fhem some seconds later
  # we adjust the Timestamp to Shellies time of calculation and use a propretary version of the 'readingsBulkUpdateMonitored()' sub
  $TimeStamp = FmtDateTime($unixtime-$unixtime%60); # adjust to lass full minute

  #  Here we have some coding regarding the reading-names
  my $suffix =  AttrVal($name,"EMchannels","_ABC");
  my ($pr,$ps,$reading,$value);
  my ($active_energy,$return_energy,$deltaEnergy,$deltaAge);
  
  my (@emchannels,$mpsub,$mpch);  
  
  #prepare the list of Time-Periods
  my @TPs=split(/,/x, AttrVal($name,"Periods", "") );
  my $TP;
  
  if( ReadingsVal($name,"model_profile","monophase") eq "triphase" ){
    # triphase: we have for the channel 0:
    # a_total_act_energy
    # a_total_act_ret_energy
    # b_...
    # c_...
    # total_act
    # total_act_ret
    @emchannels = ("a_","b_","c_","total_");
    $mpsub="";
  }else{   
    # monophase: we have for each channel 0,1,2:
    # total_act_energy
    # total_act_ret_energy
    @emchannels = ("total_");
    $mpsub = "_energy";
    $mpch=$id2ch[$id];  # monophase channel
  }
  #--- looping all phases
  foreach my $emch ( @emchannels ){                  # "a_","b_","c_","total_"
       # Log3 $name,$V//5,"[Shelly_procEnergyData:0] $name channel=$id: processing EM-channel=$emch <$mpsub>$suffix<";   #5
        if( $suffix =~ /_$/ ){  # ABC_  L123_
            $pr=$mapping{sf}{$suffix}{$mpch//$emch};  # take $emch if $mpch is undefined
            $ps="";
        }else{         # _ABC  _L123
            $pr="";
            $ps=$mapping{sf}{$suffix}{$mpch//$emch};
        }
        foreach my $flow ("act","act_ret"){ 
            if( $emch ne "total_" ){
              $reading = $pr.$mapping{E1}{'total_'.$flow.'_energy'}.$ps;
              $value = $jhash->{$emch.'total_'.$flow.'_energy'};
            }else{          # processing total_ values
              $reading = $pr.$mapping{E1}{$flow}.$ps;
              $value = $jhash->{'total_'.$flow.$mpsub};
              if( $flow eq "act" ){
                  $active_energy = $value;
              }else{
                  $return_energy = $value;
              } 
              Log3 $name,$V//6,"[Shelly_procEnergyDamy] $emch  $flow   $value"; 
            }
            Log3 $name,$V//5,"[Shelly_procEnergyData:0] $name channel=$id: updating reading=$reading";   #5
            Shelly_readingsBulkUpdate($hash,$reading,$value,"energy/Wh",undef,$TimeStamp);
            #new#            
            Log3 $name,$V//5,"[Shelly_procEnergyData:0] $name channel=$id: updating delta values of reading=$reading";   #5
            foreach $TP (@TPs){
                Shelly_delta_energy($hash,$reading."_",$TP,$unixtime,$value,$TimeStamp,$dst); 
            }
        }
  }

  #initialize helper values to avoid error in first run
  if( !defined( $hash->{helper}{timestamp_last} ) ){
          $hash->{helper}{timestamp_last} = $unixtime - 60;
          $hash->{helper}{Total_Energy_S}=0;
          $hash->{helper}{powerPos} = 0;
          $hash->{helper}{powerNeg} = 0;
  }

  ### processing calculated values ###
  ### 1. calculate Total Energy
        $reading = $pr."Total_Energy".$ps;
        Log3 $name,$V//5,"[Shelly_procEnergyData:1] $name channel=$id: updating reading=$reading";   #5
        Shelly_readingsBulkUpdate($hash,$reading,$active_energy - $return_energy,"energy/Wh",undef,$TimeStamp);

  ### 2. calculate Energy-differences for a set of different periods   //  all meters
        Log3 $name,$V//5,"[Shelly_procEnergyData:2] $name channel=$id: preparing periods ".AttrVal($name,"Periods", "");

        #calculate all periods
        $unixtime = $unixtime-$unixtime%60;  # adjust to lass full minute
        foreach $TP (@TPs){
           Log3 $name,$V//5,"[Shelly_procEnergyData:2] $name channel=$id: $pr$ps calling Shelly_delta_energy for period \'$TP\' ";
           # Shellie'S Energy value 'S'
           Shelly_delta_energy($hash,$pr."Total_Energy".    $ps."_",$TP,$unixtime,$active_energy-$return_energy,$TimeStamp,$dst);
           Shelly_delta_energy($hash,$pr."Purchased_Energy".$ps."_",$TP,$unixtime,$active_energy,$TimeStamp,$dst);
           Shelly_delta_energy($hash,$pr."Returned_Energy". $ps."_",$TP,$unixtime,$return_energy,$TimeStamp,$dst);
        } 
        
  ### ~~~~~~~~~~Triphase~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~      
  if( ReadingsVal($name,"model_profile","monophase") eq "triphase" ){
  ### 3. calculate a power value from the difference of Energy measures
        $deltaAge = $unixtime - $hash->{helper}{timestamp_last};
        $hash->{helper}{timestamp_last} = $unixtime;

        $deltaEnergy  = $active_energy - $return_energy - $hash->{helper}{Total_Energy_S};
        $hash->{helper}{Total_Energy_S} =$active_energy-$return_energy;

        $reading = $pr.$mapping{E1}{"act_calculated"}; # Active_Power_calculated
        $value  = sprintf("%4.1f",3600*$deltaEnergy/$deltaAge) if( $deltaAge>0 );  # this is a Power value in Watts.
        $value .= $si_units{power}[$hash->{units}];
        $value .= sprintf(" \( %d Ws = %5.2f Wh in %d s \)",3600*$deltaEnergy,$deltaEnergy,$deltaAge);
        Log3 $name,$V//5,"[Shelly_procEnergyData:3] $name channel=$id: updating triphase reading=$reading";   #5
        Shelly_readingsBulkUpdate($hash,$reading,$value,undef,undef,$TimeStamp);
  }  # Triphase/

  ############ Balancing ######################
  if( ReadingsVal($name,"model_profile","monophase") eq "triphase"  
    &&  AttrVal($name,"Balancing",1) == 1 
    &&  $hash->{helper}{powerCnt} ){   # don't divide by zero
      Log3 $name,$V//5,"[Shelly_procEnergyData] processing Balancing";
      ### 4. calculate a power value by integration of single power values
      ### calculate purchased and returned Energy out of integration of positive and negative power values
          my ($mypower,$mypowerPos,$mypowerNeg)=(0,0,0);
          my ($active_energy_i,$return_energy_i);
          $mypower = sprintf("%4.1f %s (%d values)", $hash->{helper}{power}/$hash->{helper}{powerCnt},
                                                    $si_units{power}[$hash->{units}],$hash->{helper}{powerCnt} );
          $mypowerPos = $hash->{helper}{powerPos} / $hash->{helper}{powerCnt};
          $mypowerNeg = $hash->{helper}{powerNeg} / $hash->{helper}{powerCnt};
# showunits
        my $factor=$energy_units{AttrVal($name,"showunits","none")}[1];  # normalize readings values to "Wh"
        my $decimals=$energy_units{AttrVal($name,"showunits","none")}[2];
        $factor=1/$factor//1; #Debug $factor;
          $hash->{helper}{Energymeter_P}=$factor*ReadingsNum($name,"Purchased_Energy_T",ReadingsNum($name,"Purchased_Energy_S",0))
          	unless( $hash->{helper}{Energymeter_P} ); #$active_energy;
          $hash->{helper}{Energymeter_R}=$factor*ReadingsNum($name,"Returned_Energy_T", ReadingsNum($name,"Returned_Energy_S", 0))
                unless( $hash->{helper}{Energymeter_R} ); #=$return_energy;

          $active_energy_i = $mypowerPos/60 + $hash->{helper}{Energymeter_P};    # Energy in Watthours
          $return_energy_i = $mypowerNeg/60 + $hash->{helper}{Energymeter_R};
          Log3 $name,$V//5,"[Shelly_procEnergyData:4] integrated Energy= $active_energy_i   $return_energy_i   in Watthours";
          $mypowerPos = sprintf("%4.1f %s (%d Ws = %5.2f Wh)", $mypowerPos,$si_units{power}[$hash->{units}],$mypowerPos*60,$mypowerPos/60 );
          $mypowerNeg = sprintf("%4.1f %s (%d Ws = %5.2f Wh)", $mypowerNeg,$si_units{power}[$hash->{units}],$mypowerNeg*60,$mypowerNeg/60);
          # don't write out when not calculated
          readingsBulkUpdateMonitored($hash,$pr.$mapping{E1}{act_integrated},$mypower);
          readingsBulkUpdateMonitored($hash,$pr.$mapping{E1}{act_integratedPos},$mypowerPos);
          readingsBulkUpdateMonitored($hash,$pr.$mapping{E1}{act_integratedNeg},$mypowerNeg);

     ### 5. reset helper values. They will be set while cyclic update of power values. A small update interval is necessary!
          $hash->{helper}{power} = 0;
          $hash->{helper}{powerPos} = 0;
          $hash->{helper}{powerNeg} = 0;
          $hash->{helper}{powerCnt} = 0;

     ### 6. safe these values for later use, independent of readings format, in Wh.
          # We need them also to adjust the offset-attribute, see Shelly_attr():
          $hash->{helper}{Energymeter_P}=$active_energy_i;
          $hash->{helper}{Energymeter_R}=$return_energy_i;

     ### 7. calculate the suppliers meter value
          foreach my $EM ( "F","P","R" ){
            if( defined(AttrVal($name,"Energymeter_$EM",undef)) ){
               $reading = "Total_Energymeter_$EM";
               if( $EM eq "P" ){
                  $value = $active_energy_i;
               }elsif( $EM eq "R" ){
                  $value = $return_energy_i;
               }elsif( $EM eq "F" ){ # Energymeter_F
                  $value = $active_energy_i-$return_energy_i;
               }
               # next line we need because additon works not properly!!!
          Log3 $name,$V//5,"[Shelly_procEnergyData:5] Energy Meter value $EM = $value in Watthours"; #5
               $value = sprintf("%7.4f",$value+AttrVal($name,"Energymeter_$EM",50000));
               Shelly_readingsBulkUpdate($hash,"Total_Energymeter_$EM",$value,"energy/Wh",undef,$TimeStamp);
            }
          }

     ### 8. write out actual balanced meter values
          Shelly_readingsBulkUpdate($hash,"Purchased_Energy_T",$active_energy_i,"energy/Wh", undef, $TimeStamp);
          Shelly_readingsBulkUpdate($hash,"Returned_Energy_T",$return_energy_i,"energy/Wh", undef, $TimeStamp);
          Shelly_readingsBulkUpdate($hash,"Total_Energy_T",$active_energy_i-$return_energy_i,"energy/Wh", undef, $TimeStamp);

     ### 9. calculate Energy-differences for a set of different periods
          foreach $TP (@TPs){
          Log3 $name,$V//5,"[Shelly_procEnergyData:9] $name channel=$id calling delta for totals of Total/Purch./Ret. periode=$TP <$dst>";
              # integrated (balanced) energy values 'T'
              Shelly_delta_energy($hash,"Total_Energy_T_",    $TP,$unixtime,$active_energy_i-$return_energy_i,$TimeStamp,$dst); # $return_energy is positive
              Shelly_delta_energy($hash,"Purchased_Energy_T_",$TP,$unixtime,$active_energy_i,$TimeStamp,$dst);
              Shelly_delta_energy($hash,"Returned_Energy_T_", $TP,$unixtime,$return_energy_i,$TimeStamp,$dst);
          }
  }  # Balancing/ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~      
  readingsEndUpdate($hash,1);

  if( ReadingsVal($name,"model_profile","monophase") ne "triphase"    &&    ++$id < $shelly_models{$model}[6] ){
         Log3 $name,$V//5,"[Shelly_procEnergyData] $name requesting next EnergyData channel=$id";
         Shelly_HttpRequest($hash,"/rpc/EM1Data.GetStatus","?id=$id","Shelly_procEnergyData" );
         return;
  }
  
  # last run: get total values  for monophase profile
  if( ReadingsVal($name,"model_profile","monophase") ne "triphase"  ){
      readingsBeginUpdate($hash);
      my ($val,$unit);
      #    $reading = $pr.$mapping{E1}{'total_'}.$ps;
      foreach my $reading( "Purchased_Energy","Returned_Energy","Total_Energy" ){
          $value=0;
          #   for( my $i=0; $i<$shelly_models{$model}[6]; $i++){
          foreach my $idx( "A","B","C" ){
              last unless( ReadingsNum($name,"$reading\_$idx",undef) );
              $val = ReadingsVal($name,"$reading\_$idx",0) =~ /(\d+.?\d+)\s(\S*)/;
              $unit = $2//"";  # no units in reading if attr showunits is 'none'
              $value += ReadingsNum($name,"$reading\_$idx",0);
            #  $value += ($1//0);
          }
          # Shellie'S Energy value 'S'
          $pr="";$ps="_S";
          Log3 $name,$V//3,"[Shelly_procEnergyData:m] $name: reading=$pr.$reading.$ps val=$value unit >$unit<"; 
          Shelly_readingsBulkUpdate($hash,$pr.$reading.$ps,$value,"energy/$unit"); # Purchased_Energy, ...
          foreach $TP (@TPs){
              Log3 $name,$V//5,"[Shelly_procEnergyData] calling Shelly_delta_energy for period \'$TP\' for Shelly in monophase-profile";
              Shelly_delta_energy($hash,$pr.$reading.$ps."_",$TP,$unixtime,$value,$TimeStamp,$dst);
          } 
      }
      readingsEndUpdate($hash,1);
  }

  if( $hash->{INTERVAL}>0 ){
      #-- initiate next run, adjusted to full minute plus 1 sec
      my $perds = AttrVal($name,"Periods", "none");
      $perds=~/(\w+)$/; # \w matches all word chars, looking for last key in descending order   
      my $timer=($periods{$1}[2]  //   maxNum($hash->{INTERVAL}-$hash->{INTERVAL}%60,60) ); # modulo ;  at least 60 sec
      my $Time=(int(time()/$timer)+1)*$timer+1; 
      Log3 $name,$V//4,"[Shelly_procEnergyData] $name: \'EM Data\' update interval is $timer sec, next update \@ ".
                        strftime("%H:%M:%S",localtime($Time) ); #4
      RemoveInternalTimer($hash,"Shelly_getEnergyData");
      InternalTimer( $Time, "Shelly_getEnergyData", $hash);
  }
  return undef;
} #end Shelly_procEnergyData()


########################################################################################
#
# Shelly_delta_energy - calculate energy for a periode
#
# Parameter hash,
#           reading     name of the reading of the energy-counter
#           TP          time periode like 'hourQ'
#           utime       epochtime, adjusted to the last full minute
#           energy      value of the energy-counter, in Watt-hours (Wh)
#           TimeStamp   timestamp adjusted to the last full minute
#           dst         daylight savings time
#
########################################################################################

sub Shelly_delta_energy {
  my ($hash,$reading,$TP,$utime,$energy,$TimeStamp,$dst) = @_;

  my ($energyOld,$denergy,$timestampRef,$dtime);

       return if(!$periods{$TP}[2]); #avoid illegal modulus

       $reading .= $TP;
       $timestampRef=ReadingsTimestamp($hash->{NAME},$reading,"2023-12-05 16-00-00" );
       if( $timestampRef ){
            $timestampRef=time_str2num( $timestampRef );  #convert to epoch-time, like str2time
            $dtime = $utime - $timestampRef;
       }else{
            $dtime = 0;
       }

       if( $dtime >= $periods{$TP}[2] - ($timestampRef+$periods{$TP}[$dst]) % $periods{$TP}[2] ){

          $energyOld=ReadingsVal($hash->{NAME},$reading,undef);
          if( $energyOld ){
                $energyOld=~ /.*\((.*)\).*/;
                $denergy = $energy - $1; # energy used in this periode, may be negative!
          }else{
                $denergy = 0; # if(abs($denergy) < 0.001);
          }

          my $power = $dtime ? sprintf(" %4.1f %s",3600*$denergy/$dtime,$si_units{power}[$hash->{units}]) : "-";
          Log3 $hash->{NAME},5,"[Shelly_delta_energy] updating $reading";
          readingsBulkUpdateIfChanged($hash,$reading,
                  shelly_energy_fmt($hash,$denergy,"Wh").sprintf(" (%7.4f) ",$energy).$power,
                  undef, $TimeStamp);
          #--- corrected values ?
          my $corrFactor = AttrVal($hash->{NAME},"PeriodsCorr-F",undef);
          if( $corrFactor ){
                $power = $dtime ? sprintf(" %4.1f %s",3600*$denergy*$corrFactor/$dtime,$si_units{power}[$hash->{units}]) : "-";
                readingsBulkUpdateIfChanged($hash,$reading."-c",
                  shelly_energy_fmt($hash,$denergy*$corrFactor,"Wh").sprintf(" (%7.4f f=%4.3f) ",$energy,$corrFactor).$power,
                  undef, $TimeStamp);
          }
       }
       return undef;
} #end Shelly_delta_energy()


########################################################################################
#
# shelly_energy_fmt - format the energy reading
#
# Parameter hash, energy value, unit of shellies energy-value
#
########################################################################################

sub shelly_energy_fmt {
  my ($hash, $energy, $unit) = @_;    #                          return $energy;
  my $showunits = AttrVal($hash->{NAME},"showunits","none");
  my $decimals=1;  # no of decimals in output
  my $name = $hash->{NAME};

  if( $showunits eq "original" ){
      return( sprintf("%4.2f %s",$energy, $unit ) );
 #    return( "$energy $unit" );
  }
  if( $unit eq "Wm" ){  # Watt-Minutes, as in Shellies first gen, except Shelly-EM
      $energy = int($energy/6)/10;   # 60 minutes per hour
      $decimals=2;
  }elsif( $unit eq "mWh" ){  # Milli-Watt-Hours, as in Shellies 2nd gen "last-minute"
      $energy /= 1000;   # 1000 mWh per Wh
      $decimals=3;
  }elsif( $unit eq "kWh" ){  # Kilo-Watt-Hours, when reading Values with ReadingsVal()
      $energy *= 1000;   # 1000 mWh per Wh
      $decimals=6;
  }
  my $unit2 = "Wh";
  if( $showunits eq "none" ){
      $unit2 = "";  # in Wh
      return $energy;
  }elsif( $showunits eq "normal" ){
      $decimals += 1;
      # nothing more to do here
  }elsif( $showunits eq "normal2" ){
      $energy /= 1000;   # 1000 Wh per kWh
      $unit2 = "kWh";
      $decimals += 4;
      $decimals = 5   if( $unit eq $unit2 );
  }elsif( $showunits eq "ISO" ){
      $energy *= 3.6;   # 3.6 kJ per Wh (Kilo-Joule)
      $unit2 = "kJ";     # Kilo-Joule
  }else{
      return "Error: wrong unit";
  }
  $decimals = 1 if( $energy == 0 );
  $decimals = "%1.".$decimals."f";   # e.g. %1.4f
  return( sprintf("$decimals %s",$energy, $unit2 ) );
} #end shelly_energy_fmt()


########################################################################################
#
# Shelly_response - processing the response of calls to the Shelly
#
# Parameter: $param, $jhash
#
########################################################################################

sub Shelly_response {
  my ($param,$jhash) = @_;
  my $hash = $param->{hash};
  my $comp = $param->{comp};
  my $cmd  = $param->{cmd};
  my $urlcmd=$param->{urlcmd};
  my $name = $hash->{NAME};
  my $model= AttrVal($name,"model","generic");
  my $timer;
  #processing incoming data
  Log3 $name,4,"[Shelly_response] device $name has returned JSON for component \'$comp\' to set \'$cmd\'"; #4

  #---------------------------
  if( $comp eq "dim" ){
      Log3 $name,4,"[Shelly_response:dim] ok";
      #*************************
      my $ison        = $jhash->{'ison'};
      my $hastimer    = $jhash->{'has_timer'};
      my $onofftimer  = $jhash->{'timer_remaining'};
      my $source      = $jhash->{'source'};
      # more readings by shelly_dim-answer:  timer_started, timer_duration, mode, transition

  #*************************

      if( $cmd  =~ /\?brightness=(\d*)/){
        Log3 $name,4,"[Shelly_dim] running for brightness command";
        my $val = $1;
        my $bright = $jhash->{brightness};
        if( $bright ne $val ) {
          Log3 $name,1,"[Shelly_dim] returns without success for device $name, desired brightness $val, but device brightness=$bright";
        }
      }

  readingsBeginUpdate($hash);
  if( $jhash->{'overpower'} ){ #not supported by ShellyDimmer2 bulb/dimmer
    my $overpower   = $jhash->{'overpower'};
    Log3 $name,1,"[Shelly_dim] device $name switched off automatically because of overpower signal"
                     if( $overpower eq "1");
    readingsBulkUpdateMonitored($hash,"overpower",$overpower)
                     if( $shelly_models{$model}[3] > 0);
  }
  readingsEndUpdate($hash,1);

      Shelly_status($hash,"response_dim");
      $timer = 0.25 + ReadingsNum($name,"transition",10000)/1000;
      #*************************
  }elsif( $comp eq "onoff" ){
      my $onofftimer  = 0;
      if( defined($jhash->{was_on}) ){   # response by Gen2 fw
        my $oldState      = $jhash->{was_on};
        $oldState =~ s/0|(false)/off/;
        $oldState =~ s/1|(true)/on/;
        $onofftimer = $hash->{helper}{timer} if( defined($hash->{helper}{timer}) );
        my $msg = "Successfull, device $name was $oldState ";
        $msg .= ", device switched with timer of $onofftimer seconds" if( $onofftimer );
        Log3 $name,4,"[Shelly_response:onoff] $msg"; 
      }elsif( defined($jhash->{cover}) && $jhash->{cover} eq "successfull" ){
          if( $urlcmd =~ m/toggle_after=(\d+)/ ){
              $hash->{helper}{timer} = $1;
              $hash->{helper}{timerCnt}=1;
          } 
        # Shellies type dimmer gen2 response of 'on-for-timer' etc. is 'null'
        Log3 $name,5,"[Shelly_response:onoff] received \'null\' --> skipping helper=$1=".$hash->{helper}{timer};
      }else{
        my $ison        = $jhash->{ison};
        my $hastimer    = undef;
        my $source      = $jhash->{source};
        my $overpower   = $jhash->{overpower};

        $ison =~ s/0|(false)/off/;
        $ison =~ s/1|(true)/on/;

        if( defined($jhash->{has_timer}) ){
            $hastimer    = $jhash->{has_timer};
            if( defined($jhash->{timer_remaining}) ){
                $onofftimer  = $jhash->{timer_remaining};
                $hash->{helper}{timer} = $onofftimer;
            }else{
                $onofftimer = "-";   # no remaining time given by old fw eg Shelly4pro
            }
        }
        if( defined($jhash->{timer_duration}) ){
                $onofftimer  = $jhash->{timer_duration};
                $hash->{helper}{timer} = $onofftimer;
        }
        if( $urlcmd =~ /\&timer=(\d+)?/ ){
            $onofftimer = $1; 
        }
        Log3 $name,1,"[Shelly_response:onoff] returns with problem for device $name, timer not set"   if( $onofftimer && !$hastimer );

        # check on successful execution
        $urlcmd =~ m/\/(\d)\?/;
        my $channel = $1;
        
        $urlcmd =~ m/turn=(on|off)/; 
        Log3 $name,1,"[Shelly_response:onoff] returns without success for device $name, cmd=$urlcmd but ison=$ison vs $1"  if( $ison ne $1 );

        if( defined($overpower) && $overpower eq "1") {
          Log3 $name,1,"[Shelly_response:onoff] device $name switched off automatically because of overpower signal";
        }
        
        my $subs = "";
        $subs = "_".$channel  if( $shelly_models{$model}[0] > 1 || ($shelly_models{$model}[2] > 1 && AttrVal($name,"mode","na") ne "color") );
        # Note: ShellyRGBW2 has 4 channels in relay-mode, but 1 channel in color-mode
        
        Log3 $name,4,"[Shelly_response:onoff] received callback from $name channel $channel is switched $ison, "
               .($hastimer?"timer is set to $onofftimer sec":"no timer set");
        readingsBeginUpdate($hash);
        if( $model ne "shelly4" ){
            $onofftimer .= $si_units{time}[$hash->{units}];
            readingsBulkUpdateMonitored($hash,"source".$subs,$source); # not supported/old fw
        }else{
            $onofftimer = $hastimer?$onofftimer.$si_units{time}[$hash->{units}]:"--";
        }
        readingsBulkUpdateMonitored($hash,"timer".$subs,$onofftimer);      
        
if(0){
    if( $shelly_models{$model}[0] == 1 ){
      readingsBulkUpdateMonitored($hash,"state",$ison);
    }else{
      readingsBulkUpdateMonitored($hash,"state","OK");
    }
    readingsBulkUpdateMonitored($hash,"relay".$subs,$ison);  # also  "light"

    readingsBulkUpdateMonitored($hash,"overpower".$subs,$overpower)
                       if( $shelly_models{$model}[3]>0 && $model ne "shelly1" );
}
        readingsEndUpdate($hash,1);
        }

        # switching dimable devices on or off also have 'brightness' and 'transition'
        my $brightness = $jhash->{brightness};
        my $transition = $jhash->{transition};
        
        $timer=maxNum(1.40,ReadingsNum($name,"transition",0)/1000);

  #---------------------------
  }elsif( $comp =~ /updown(\d)/ ){   # updown1  updown2
      $timer= ( $1==1 ? 1.44 : 0.424 ); # wait until Shelly has passed first measurement periode - Gen2 is faster
      my $duration = $hash->{DURATION};
      if( $duration > $timer ){
          $hash->{helper}{timer}=$hash->{DURATION};
          $hash->{helper}{timerCnt}=1;
      }else{
          $timer=$duration+0.45;
          $hash->{helper}{timer}=0;      # don't make successive status-call 
          $hash->{helper}{timerCnt}=0;   
      } 
      if( $comp eq "updown1" ){
          my $rstate = $jhash->{'state'};
          $rstate =~ s/stop/stopped/;
          $rstate =~ s/close/drive-down/;
          $rstate =~ s/open/drive-up/;     
          $hash->{MOVING}   = $rstate;
          Log3 $name,3,"[Shelly_response:updown1] $name: got answer for comand $urlcmd, state is set to \'$rstate\', call status in $timer seconds";
          readingsSingleUpdate($hash,'state',$rstate,1); # other data represent old state, not useful
      }else{  #  updown2
          Log3 $name,3,"[Shelly_response:updown2] $name: got answer from shelly ...";  ## we usually get "null"
          Log3 $name,5,"[Shelly_response:updown2] $name: DURATION=$duration   timer=$timer  "; 
          Log3 $name,5,"[Shelly_response:updown2] $name: HELPER=".$hash->{helper}{timer}." - tmrCnt=".$hash->{helper}{timerCnt}; 
      }
  
      delete $hash->{CMD};

  #---------------------------
  }elsif( $comp =~ /target/ ){
          Log3 $name,3,"[Shelly_response:target] $name: got answer from a target call";  ##3
  
  #---------------------------
  }elsif( $comp =~ /script/ ){ # returned data:  was_running
      my $was_running = $jhash->{'was_running'};
      #  $was_running =~ s/0|(false)/was not running/;
      #  $was_running =~ s/1|(true)/was running/;
      my $script_state;
      if( $cmd =~ /Start/ ){
          if( $was_running =~ /0|(false)/ ){
              $script_state = "started";
          }else{
              $script_state = "has already been started";
          }
      }else{ # Stop
          if( $was_running =~ /0|(false)/ ){
              $script_state = "was already stopped";
          }else{
              $script_state = "stopped";
          }
      }
      $urlcmd =~ s/\?//;
      Log3 $name,2,"[Shelly_response:script] $name: got answer from $comp call: script $urlcmd $script_state";  ##2
      # Script.List
      Shelly_HttpRequest($hash,"/rpc/Script.List",undef,"Shelly_settings2G","scripts",1 ); #call silent
 
  #---------------------------
  }elsif( $comp =~ /config/ ){
        $timer=1.25;

        # "reboot"
        if( $cmd eq "/reboot" ){
            # Gen1
            my $ok = $jhash->{ok};
            if( $ok != 0 ){
                Log3 $name,4,"[Shelly_response:config] device $name is rebooting ";
                readingsSingleUpdate($hash,"state","rebooting",1);
                $timer=15.0;
            }else{
                Log3 $name,2,"[Shelly_response:config] device $name was called for reboot, but answers with $ok ";
            }

        # "update"
        }elsif( $cmd eq "/ota" ){
            #update Gen1
            my $status = $jhash->{status};
            my $has_update = $jhash->{has_update};
            if( $has_update != 0 ){
                Log3 $name,4,"[Shelly_response:config] device $name is $status, update is $has_update ";
                readingsSingleUpdate($hash,"state",$status,1);
                $timer=30;
            }else{
                Log3 $name,2,"[Shelly_response:config] device $name was called for update, but no update present (state is $status) ";
            }

        # "calibrate"  roller       ********* this is not tested **************
        }elsif( $cmd eq "/roller" && $urlcmd =~ /calibrate/){
                readingsSingleUpdate($hash,"state","calibrating",1);
                $timer=150.0;


        # "calibrate"  dimmer       ********* this is not final **************
        }elsif( $cmd eq "/settings" && $urlcmd =~ /calibrate/){
            my $calibrated = $jhash->{calibrated};
            if( $calibrated != 0 ){
                Log3 $name,2,"[Shelly_response:config] device $name is called for calibration";
                readingsSingleUpdate($hash,"state","calibrating",1);
                $timer=15.0;
            }else{
                Log3 $name,6,"[Shelly_response:config] $name: device was called for calibration, but is not calibrated";
                Log3 $name,6,"[Shelly_response:config] $name: Start Calibration from Shellies WEB-UI";
                return;
            }

        # Gen2 Sys.SetConfig  Cover.SetConfig Wifi.SetConfig etc.
        }elsif( $cmd =~ /SetConfig/ ){
            if( defined( $jhash->{restart_required}) ){
                Log3 $name,1,"[Shelly_response:config] device $name has set Config successfull, Restart required: "
                            .($jhash->{restart_required}?"YES":"NO");
            }
            #call settings
            Shelly_HttpRequest($hash,"/rpc/Shelly.GetConfig",undef,"Shelly_settings2G","config" );
            return;


        # Gen2 Switch.ResetCounters  Cover.ResetCounters
        }elsif( $cmd =~ /ResetCounter/ ){
            if( defined($jhash->{aenergy}{total}) ){
                $comp =~ /(\d)/;
                my $id = $1;
                my $subs = (defined(ReadingsNum($name,"energy_0",undef))?"\_$id":"");
                Log3 $name,3,"[Shelly_response:config] device $name has reset counter \'energy$subs\' successfull";
                readingsSingleUpdate($hash,"energy$subs",$jhash->{aenergy}{total},1);
                $timer=1;
            }

        # Gen2 Shelly.Reboot
        }elsif( $cmd =~ /Shelly.Reboot/ ){
            if( defined( $jhash->{cover}) && $jhash->{cover} eq "successfull" ){
                Log3 $name,2,"[Shelly_response:config] device $name is rebooting";
                readingsSingleUpdate($hash,"state","rebooting",1);
                $timer=15;
            }

        # Gen2 Shelly.Update
        }elsif( $cmd =~ /Shelly.Update/ ){
            if( defined( $jhash->{cover}) && $jhash->{cover} eq "successfull" ){
                Log3 $name,2,"[Shelly_response:config] device $name is updating";
                readingsSingleUpdate($hash,"state","updating",1);
                $timer=30;
            }
        }else{
                Log3 $name,4,"[Shelly_response:config] device $name has been processed";
        }

  # GET CONFIG
  #---------------------------
  }elsif( $comp eq "getconfig" ){
        Log3 $name,4,"[Shelly_response:getconfig] device $name processing call \"$cmd$urlcmd\" ";#4
        $timer=1.25;
        #-- isolate channel and register name
        $urlcmd =~ /.*\/(\d)\?(.*)/;
        my $chan= $1;
        my $reg = $2;
        my $val = $jhash->{$reg};
        Log3 $name,4,"[Shelly_response:getconfig] $name: isolated register=$reg, channel=$chan, value=$val";#4

     ##   $chan = $shelly_models{$model}[7] == 1  ? "" : "[channel $chan]";

        if( defined($val) ){
            Log3 $name,4,"[Shelly_response:getconfig] device $name result is: register=\'$reg\' channel=\'$chan\' value=\'$val\' ";
            readingsSingleUpdate($hash,"config","$reg=$val $chan",1);
        }else{
            Log3 $name,4,"[Shelly_response:getconfig] device $name no result found for register $reg $chan";
            readingsSingleUpdate($hash,"config","register \'$reg\' not found or empty $chan",1);
        }
        return undef;  # do not perform call for status
  }elsif( $comp eq "plugsui" ){ 
         Shelly_HttpRequest($hash,"/rpc/PLUGS_UI.GetConfig",undef,"PLUGS_UI_GetConfig","Get" );
  }else{
        Log3 $name,3,"[Shelly_response] called by $name for \'$comp\': not implemented";  
  }
  #---------------------------
  #-- scheduling next status update
  Shelly_status($hash,"Shelly_response",$timer);
  return undef;
} #end Shelly_response()


########################################################################################
#
# PLUGS_UI_GetConfig - process the answer of /rpc/PLUGS_UI.GetConfig
#
########################################################################################settings2G
sub PLUGS_UI_GetConfig{
  my ($param,$jhash) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $comp = $param->{comp};
  my $err;
  my $model= AttrVal($name,"model","generic");
  
  Log3 $name,4,"[PLUGS_UI_GetConfig] $name: processing the answer /rpc/PLUGS_UI.GetConfig ($comp)";
  my $mode = ($jhash->{leds}{mode});
  if( !defined($mode) ){
      $err = "error in JSON";
      Shelly_error_handling($hash,"PLUGS_UI_GetConfig",$err,2);
      return $err;
  }
  my $colors = $mode;
  my $rgb= "-";
  if( $mode eq "switch" ){
     my @set;
     foreach my $onoff ( "on","off"){
         my @cols = @{$jhash->{leds}{colors}{'switch:0'}{$onoff}{rgb}};
         $colors   .= " $onoff: ".($cols[0]);
         $colors   .= ",".        ($cols[1]);
         $colors   .= ",".        ($cols[2]);
         $colors   .= ";".$jhash->{leds}{colors}{'switch:0'}{$onoff}{brightness};
         if( ReadingsVal($name,"state","unknown") eq $onoff ){
             $rgb=sprintf("%02X%02X%02X",round(2.55*$cols[0],0),
                                         round(2.55*$cols[1],0),
                                         round(2.55*$cols[2],0));
         }
     }
  }elsif( $mode eq "power" ){
     $colors   .= " ".$jhash->{leds}{colors}{power}{brightness};
  }
  readingsSingleUpdate($hash,"colors",$colors,1); 
  readingsSingleUpdate($hash,"colorsRGB",$rgb,1);  
}

########################################################################################
#
# Shelly_webhook_create - Create a set of webhook
#
# Parameter: hash
#            cmd      info, all or a number
#
########################################################################################

sub Shelly_webhook_create {
  my ($hash,$cmd) = @_;
  my $name  = $hash->{NAME};
  my $number = -1;
  #return "Error"  unless( $cmd =~ /info|all/ || $cmd =~ /\d/ );

  if( $cmd eq "info"){
      Log3 $name,4,"[Shelly_webhook_create] generating list of possible webhook(s) for device $name";
  }elsif($cmd eq "all" ){
      Log3 $name,4,"[Shelly_webhook_create] creating all webhooks for device $name";
        delete $hash->{helper}{actionCreate};
  }elsif( $cmd =~ /\d/ ){
      $number = $cmd;
      Log3 $name,2,"[Shelly_webhook_create] creating webhook number $number for device $name";
  }else{
      Log3 $name,2,"[Shelly_webhook_create] $name: wrong parameter";
      return "Error";
  }

  my $model = AttrVal($name,"model","generic");
  my $gen   = $shelly_models{$model}[4]; # 0 is Gen1,  1 or 2 is Gen2
  my $creds = Shelly_pwd($hash);
  my $timeout = AttrVal($name,"timeout",4);
  my $mode  = AttrVal($name,"mode","relay");  # we need mode=relay for Shelly*1-devices

  my $html = "";
  my $count= 0;
  my $URL =($gen>=1?"/rpc/Webhook.Create":"/settings/actions");   #Gen2 :  Gen1
  my $enable = ($cmd eq "all"?"false":"true");

  my $urls   = "";
  my $event  = "";
  my $action;          #  name of the action
  my $compCount=0;     #  number of components in device
  my $eventsCount=0;   #  number of events
  my ($component,$element);

  foreach $component ( $mode, "light", "input", "emeter", "pm1", "touch", "sensor", "addon" ){
       Log3 $name,4,"[Shelly_webhook_create] $name: check number of components for component=$component";
       if( $component eq "relay" ){
          $compCount   = $shelly_models{$model}[0];
       }elsif( $component eq "roller" ){
          $compCount   = $shelly_models{$model}[1];
       }elsif( $component eq "light" && $gen>0 ){
          $compCount   = $shelly_models{$model}[2];
       }elsif( $component eq "white" && $gen==0 ){  # eg Shellybulb in white mode
          $compCount   = $shelly_models{$model}[2];
       }elsif( $component eq "color" && $gen==0){  # eg. ShellyRGBW in color mode
          $compCount   = $shelly_models{$model}[7];
       }elsif( $component eq "input" && AttrVal($name,"showinputs","show") eq "show" && $mode ne "roller" ){
          # ShellyPlus2PM in roller mode does not support Actions for both inputs, even with detached inputs.
          # We don't care, because we can use actions on 'opening' and 'closing'
          $compCount   = abs($shelly_models{$model}[5]);  # number of inputs on ShellyPlug is -1, because it's a button, not an wired input
       }elsif( $component eq "emeter" && $model =~ /shellypro3em|shellyproem50/ ){
          $compCount   = 1;
       }elsif( $component eq "pm1" && $model eq "shellypmmini" ){
          $compCount   = 1;
       }elsif( $component =~ /touch|sensor/ && $model =~ /walldisplay/ ){
          $compCount   = 1;
       }elsif( $component eq "addon" && ReadingsVal($name,"temperature_0", undef) ){  # we have an addon and at least one temperature sensor
          $compCount   = 5; #max number of sensors supported
       }else{
          $compCount   = 0 ;
       }
       Log3 $name,4,"[Shelly_webhook_create] $name: the number of \'$component\' is compCount=$compCount";

       for( my $c=0;$c<$compCount;$c++ ){
          Log3 $name,4,"[Shelly_webhook_create] $name: processing component $c of $component";
          if( $component eq "input" && $gen > 0){
             my $subs = $compCount>1 ? "_$c\_mode" : "_mode" ;
             $element = ReadingsVal($name,"input$subs","none"); #input type: switch or button
             if( $element eq "none" ){
                 Log3 $name,3,"[Shelly_webhook_create] $name: Error: Reading \'input.*mode\' not found";
                 return;
             }
             Log3 $name,4,"[Shelly_webhook_create] $name: input mode no $c is \'$element\' ";
             $element =~ /(\S+?)\s.*/;  # get only characters from first string of reading: 'button' or 'switch'
             $element = $1;  # momentary or toggle
          }elsif( $component eq "emeter" || $component eq "pm1"){
             $element = $component;
          }elsif( $component eq "addon"){
             $element = $component;
             next unless( ReadingsVal($name,"temperature_$c", undef) );
          }elsif( $gen == 0){   # Gen 1
             $element = $model;
          }else{
             $element = $component;
          }

          $eventsCount = $#{$shelly_events{$element}};   #  $#{...} gives highest index of array  %shelly_events
          $eventsCount++;
          Log3 $name,4,"[Shelly_webhook_create] $name: processing evtsCnt=$eventsCount events for \'$element\'";#5

          for( my $e=0; $e<$eventsCount; $e++ ){
                 $event = $shelly_events{$element}[$e];
                 $action = uc($event);
                # $action =~ s/\./_$c\./   if( $eventsCount>1 );        # add comp-id to the actions-name
                 $action =~ s/\./_$c\./   if( $compCount>1 );        # add comp-id to the actions-name
                 $action = "_".$action."_";     # add _ to the name
                 if( $gen >= 1 ){
                     $urls  = "?cid=$c";
                     $urls  = "?cid=10$c"  if( $element eq "addon" );
                     $urls .= "&event=%22$event%22";   # %22 will get quotes
                     $urls .= "&enable=$enable";
                     $urls .= "&name=%22$action%22";   # name of the weblink (Gen2 only)
                     $urls =~ s/\%22//g   if( $model =~ /walldisplay/ );  # is there a bug?
                 }else{
                     $urls  = "?index=$c";
                     $urls .= "&name=$event";
                     $urls .= "&enabled=$enable";
                 }

          Log3 $name,4,"[Shelly_webhook_create] $name: processing event=$e $event for \'$element\': \n$urls";#5
            if( $cmd ne "info" ){
                 my $cc = $compCount>1?$c:undef;
                 my( $WebHook,$error ) = Shelly_actionWebhook($hash,$element,$cc,$e);  # creating the &urls= command
                 return if($error);
                 $urls .= $WebHook;

                 if( $component eq "emeter" ){
                                  # shall we have conditions?
                     $urls .= "&condition=%22ev.act_power%20%3c%20-200%22" if( 0 && $e==0 );   #  %3c  <
                     $urls .= "&condition=%22ev.act_power%20%3e%20-100%22" if( 0 && $e==1 );   #  %3e  >
                                  # only first emeter-action (activ power) is enabled
                     $URL =~ s/enable\=true/enable\=false/  if( $e > 0 );
                  }
            }
             Log3 $name,4,"[Shelly_webhook_create] $name component=$element $c count=$count   event=$e -----------------";
             if( $cmd eq "info" ){
                 $html .= "<tr><td>$count&nbsp;</td><td>$component $c </td><td> $event </td></tr>";
             }elsif( $cmd eq "all" ){
                 Log3 $name,4,"[Shelly_webhook_create] webhook #$number: write the non-blocking call to stack: \n$URL$urls";
                 $hash->{helper}{actionCreate}[$count] = $urls;
             }elsif( $number == $count ){
                 Log3 $name,4,"[Shelly_webhook_create] webhook #$number: process the non-blocking call: \n$URL$urls";
                 Shelly_HttpRequest($hash,$URL,$urls,"Shelly_webhook_update","procCreate",0);
                 return;
             }else{
                 Log3 $name,4,"[Shelly_webhook_create] skipping: $count is not eq to $number";
             }
             $count++;
          }
       }
  }
  if( $count == 0 ){
        Log3 $name,2,"[Shelly_webhook_create] $name: no actions to create";
        return;
  }elsif( $cmd ne "info" ){
        Log3 $name,1,"[Shelly_webhook_create] $name: start creating $count actions";
        $count--;  # undo last inkrement
        # start creating with last entry on stack
        Shelly_HttpRequest($hash,$URL,$hash->{helper}{actionCreate}[$count],"Shelly_webhook_update","procCreate",$count); # on success, we receive data
        FW_directNotify("FILTER=$name","#FHEMWEB:$FW_wname","FW_okDialog( \" Done \" )", "");
        return;
  }elsif( $cmd eq "info" ){
        $html = "<tr><td><b>Index &nbsp; </b></td><td><b>Component &nbsp; </b></td><td><b> Event </b></td></tr>$html";
        $html = "<html><table><thead><tr><th>Events $model </th></tr></thead><tbody>$html</tbody></table></html>";
        return $html;
        FW_directNotify("FILTER=$name","#FHEMWEB:$FW_wname","FW_okDialog( \"$html\" )", "");
        return;
  }
} #end Shelly_webhook_create()


########################################################################################
#
# Shelly_webhook_update - Update one or all actions of a Shelly
#
# Parameter: hash
#            cmd      'all' or the id of the action
#
########################################################################################

sub Shelly_webhook_update {
  my ($param,$jhash) = @_;
  my $hash = $param->{hash};
  my $comp = $param->{comp};
  my $val  = $param->{val};
  my $cmd  = $param->{cmd};
  my $urlcmd=$param->{urlcmd};
  my $name = $hash->{NAME};
  my $model= AttrVal($name,"model","generic");
  my $gen  = $shelly_models{$model}[4]; # 0 is Gen1,  1 or 2 is Gen2
  ##############
  my $id;
  Log3 $name,5,"[Shelly_webhook_update] $name: calling with comp=$comp".(defined($val)?" and val=[$val]":", without ID");
  if( $comp eq "proc" ){
      $val--;
      if( $val < 0 ){
        delete $hash->{helper}{actionUpdate}; 
        if( defined($FW_wname) ){
            FW_directNotify("FILTER=$name","#FHEMWEB:$FW_wname","FW_okDialog( \"Update finished\" )", "");
        }else{ # if update is started by event
            Log 1,"**Update of actions finished**";
        }
        return;
      }
      if( $gen > 0 ){
          # set webhook_ver (Gen2 only)
          Log3 $name,5,"[Shelly_webhook_update] $name: [$val] processing the answer /rpc/Webhook.Update";
          my $rev = $jhash->{rev};
          if( !defined($rev) ){
              readingsSingleUpdate($hash,"error","action not changed",1);
          }else{
              readingsSingleUpdate($hash,"webhook_ver",$rev,1);
          }
      }
      $urlcmd=$hash->{helper}{actionUpdate}[$val];
  #   $urlcmd =~ s/\s/%20/g; # substitute space sign
      $urlcmd =~ s/\s/+/g; # substitute space sign
      $urlcmd =~ s/\&fwcsrf/%26fwcsrf/g;  # substitute & sign
  #    $urlcmd =~ s/%/%25/g; # substitute % sign
      Log3 $name,3,"[Shelly_webhook_update] $name: processing next action update index $val, command is $cmd and urlcmd=$urlcmd";
      Shelly_HttpRequest($hash,$cmd,$urlcmd,"Shelly_webhook_update","proc",$val); # on success, we receive data
      return;
  }elsif( $comp eq "procCreate" ){
      $val--;
      if( $val < 0 ){
        delete $hash->{helper}{actionCreate};
        FW_directNotify("FILTER=$name","#FHEMWEB:$FW_wname","FW_okDialog( \"Creating actions finished\" )", "");
        return;
      }
      if( $gen > 0 ){
          # set webhook_ver (Gen2 only)
          Log3 $name,5,"[Shelly_webhook_update] $name: [$val] processing the answer /rpc/Webhook.Create";
          my $rev = $jhash->{rev};
          if( !defined($rev) ){
              readingsSingleUpdate($hash,"error","action not created",1);
          }else{
              readingsSingleUpdate($hash,"webhook_ver",$rev,1);
          }
      }
      Log3 $name,3,"[Shelly_webhook_update] creaing next action index $val, command is $cmd";
      Shelly_HttpRequest($hash,$cmd,$hash->{helper}{actionCreate}[$val],"Shelly_webhook_update","procCreate",$val); # on success, we receive data
      return;
  }elsif( $comp eq "" ){
      $id = 0;
      Log3 $name,4,"[Shelly_webhook_update] $name: check for updating all own webhooks at device";
  }elsif( $comp =~ /\d/ ){
      $id = $comp;
      Log3 $name,4,"[Shelly_webhook_update] updating webhook ID=$id for device $name";
  }else{
      Log3 $name,1,"[Shelly_webhook_update] Bad parameter \'$comp\', aborting";
      return "Error";
  }

  my $hooksCount = 0;  # number of webhooks on the Shelly
  if( $gen == 0 ){
      $hooksCount = ReadingsNum( $name,"webhook_cnt",0 );
  }else{
      $hooksCount = @{$jhash->{'hooks'}};
  }

  if( !defined($hooksCount) ){
      Log3 $name,3,"[Shelly_webhook_update] $name: no webhooks on shelly";
      return;
  }else{
      Log3 $name,4,"[Shelly_webhook_update] $name: our counter says $hooksCount webhooks on shelly";
  }

  # current values
  # FHEMWEB-device used for webhooks
  my $hookdevice = AttrVal($name,"webhook",undef);
  if( !defined($hookdevice) ){
      Log3 $name,2,"[Shelly_webhook_update] no FHEMWEB device for webhooks defined";
      return "Please define attr webhook first";
  }
  # webname
  my $curr_host_webname = AttrVal($hookdevice,"webname","fhem");
  # port
  my $curr_host_port = InternalVal($hookdevice,"PORT",undef);
  # CSFR-Token
  my $curr_token = InternalVal($hookdevice,"CSRFTOKEN","");
  # ip
  my $curr_host_ip = AttrVal($name,"host_ip",undef)//qx("\"hostname --all-ip-addresses\"");   # local
  $curr_host_ip    =~ m/(\d\d?\d?\.\d\d?\d?\.\d\d?\d?\.\d\d?\d?).*/; #extract ipv4-address
  $curr_host_ip    = $1;

  Log3 $name,4,"[Shelly_webhook_update] $name: current values: hookdevice=$hookdevice, ip:port/webname=$curr_host_ip:$curr_host_port/$curr_host_webname token=\'$curr_token\'";

  # parsing all actions
  my ($i,$u); # loop counter
  my ($sh_hookid,$sh_hookname,$sh_url,$sh_ip,$sh_port,$sh_webname,$sh_token); # values read from Shelly

  my $updcmd = ($gen>0?"/rpc/Webhook.Update":"/settings/actions");
  my $ttlChanges=0; # counts total number of changed urls
  my $urlChanges=0; # counts number of changed urls of a single event / action

  #get actions
  my $msg = "actions on device $name:";
  if( $gen == 0 ){
    # call:  /settings/actions
    my ($e,$i,$u,$event);
    if( $shelly_events{$model}[0] ne "" ){
      foreach my $m ($model,"addon1"){
        # parsing %shelly_events
        for( $e=0; $event = $shelly_events{$m}[$e] ; $e++ ){
          for( $i=0; defined($jhash->{actions}{$event}[$i]{index}) ;$i++ ){
            $urlcmd="";
            $urlChanges=0;
            for( $u=0; $u<5 ; $u++ ){  # up to 5 possible
              $sh_url=$jhash->{actions}{$event}[$i]{urls}[$u];
              #########################
              if( !defined($sh_url) ){
                  next;
              }
              $msg .= "\n".$sh_url;
              Log3 $name,4,"[Shelly_webhook_update] $name ($m) ch$i $event: URL$u on shelly is $sh_url";
              if( $sh_url =~ /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/ ){
                  $sh_ip = $1;
              }else{
                  $sh_ip = "non_valid";
              }
              if( $sh_url =~ /:(\d{1,4})\/(.*)\?/ ){
                  $sh_port = $1;
                  $sh_webname = $2;
              }else{
                  $sh_port = 0;
                  $sh_webname = "";
              }
              if( $sh_url =~ m/fwcsrf=(csrf_[a-z0-9]+)/ ){
                  $sh_token = $1;
              }else{
                  $sh_token = "";
              }
              Log3 $name,5,"[Shelly_webhook_update:X] ip=$sh_ip port=$sh_port webname=$sh_webname token=$sh_token";
              #########################
              if( $curr_host_ip ne $sh_ip ){
                  Log3 $name,5,"[Shelly_webhook_update] ip not matching, skipping";
                  $urlcmd .= "&urls[]=$sh_url"; # get this w/o change
              }elsif( $curr_host_port==$sh_port
                   && $curr_host_webname eq $sh_webname
                   && $curr_token eq $sh_token
                   && $sh_url !~ /\s/       # no spaces
                   && $sh_url !~ /XHR/ ){
                  Log3 $name,5,"[Shelly_webhook_update] port/webname and token are matching, no spaces, no XHR, skipping";
                  $urlcmd .= "&urls[]=$sh_url"; # get this w/o change
              }else{
                  # removing spaces
                  $sh_url =~ s/ /+/g;
                  
                  # removing XHR
                  if( $sh_url =~ s/\?XHR=1\&/\?/ ){
                  }else{
                      $sh_url =~ s/\&XHR=1//;
                  }
                  # start changing url
                  if( $curr_host_port != $sh_port ){
                      $sh_url =~ s/:$sh_port\/$sh_webname/:$curr_host_port\/$curr_host_webname/;
                      Log3 $name,5,"[Shelly_webhook_update] changed port/webname of url: $sh_url";
                  }
                  Log3 $name,5,"[Shelly_webhook_update:T] token=$sh_token";
                  if( $curr_token ne "" && $sh_token eq "" ){
                      $sh_url .= "&fwcsrf=$curr_token";
                      Log3 $name,4,"[Shelly_webhook_update:1a] token added to url: $sh_url";
                  }elsif( $curr_token eq "" && $sh_token ne "" ){
                      $sh_url =~ s/fwcsrf=csrf_[a-z0-9]+//;
                      $sh_url =~ s/&$//;      # has been at end of the query string
                      $sh_url =~ s/&&/&/;     # has been in the middle of the query string
                      $sh_url =~ s/\?&/\?/;   # has been first parameter in the query string
                      Log3 $name,4,"[Shelly_webhook_update:1r] token removed from url: $sh_url";
                  }elsif( $curr_token ne $sh_token ){
                      $sh_url =~ s/$sh_token/$curr_token/;
                      Log3 $name,4,"[Shelly_webhook_update:1c] changed token in url: $sh_url";
                  }else{
                      Log3 $name,4,"[Shelly_webhook_update] no changes regarding token";
                  }
                  $urlcmd .= "&urls[]=$sh_url";  # %22 = "    %22$sh_url%22
                  $urlChanges++;
                  $msg .= "\n$sh_url n \n";
                  Log3 $name,2,"[Shelly_webhook_update] $name ($m) ch$i $event: URL$u is now $sh_url";
              }
            }
            if( $urlChanges > 0 ){ # we have to update this action because at least one url has changed
                $urlcmd = "?index=$i&name=$event$urlcmd";  #  &enabled=true
                Log3 $name,4,"[Shelly_webhook_update] $name ($m) $event ch$i: command[$ttlChanges] is: $urlcmd\n";
                $hash->{helper}{actionUpdate}[$ttlChanges]=$urlcmd;
                $ttlChanges++;
            }else{
                Log3 $name,4,"[Shelly_webhook_update] $name ($m) channel $i: check of action \'$event\' is OK, nothing to do"; #5
            }
          }
        }
      }
    }
  # Gen2
  }else{
        $ttlChanges = 0;
        for( $i=0; defined($jhash->{hooks}[$i]{id}) ;$i++ ){
            $sh_hookid = $jhash->{hooks}[$i]{id};
            # Gen2 only: update only one action, if ID is given with command
            if( $id!=0 && $id!=$sh_hookid ){
                Log3 $name,4,"[Shelly_webhook_update] $name: hookid $sh_hookid not selected, skipping update";
                next;
            }else{
                Log3 $name,4, "[Shelly_webhook_update] $name: checking action with hookid $sh_hookid";
            }
            $sh_hookname = $jhash->{hooks}[$i]{name};
            if( !defined($sh_hookname) ){
                Log3 $name,1,"[Shelly_webhook_update] $name: expected hookname for hook-ID=$sh_hookid ($i) not given, skipping"  ;
                next;
            }elsif( $sh_hookname !~ /^_/ ){
                Log3 $name,4,"[Shelly_webhook_update] $name: hookname $sh_hookname not selected, skipping update";
                next;
            }
            $urlcmd = "";
            $urlChanges=0;
            for( $u=0; $u<5 ; $u++ ){
              $sh_url=$jhash->{hooks}[$i]{urls}[$u];
              #########################
              if( !defined($sh_url) ){
                  next;
              }
              $msg .= "\n$sh_hookid: $sh_url";
              Log3 $name,4,"[Shelly_webhook_update:S] $name ($id) ch$i: URL$u on shelly is $sh_url";
              if( $sh_url =~ /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/ ){
                  $sh_ip = $1;
              }else{
                  $sh_ip = "non_valid";
              }
              if( $sh_url =~ /:(\d{1,4})\/(.*)\?/ ){
                  $sh_port = $1;
                  $sh_webname = $2;
              }else{
                  $sh_port = 0;
                  $sh_webname = "";
              }
              if( $sh_url =~ m/fwcsrf=(csrf_[a-z0-9]+)/ ){
                  $sh_token = $1;
              }else{
                  $sh_token = "";
              }
              Log3 $name,5,"[Shelly_webhook_update:S] ip=$sh_ip port=$sh_port webname=$sh_webname token=$sh_token";
              #########################
              if( $curr_host_ip ne $sh_ip ){
                  Log3 $name,4,"[Shelly_webhook_update] ip not matching, skipping update";
                  #$urlcmd .= "\"$sh_url\","; # get this w/o change
              }elsif( $curr_host_port == $sh_port
                    && $curr_host_webname eq $sh_webname
                    && $curr_token eq $sh_token
                    && $sh_url !~ /\s/       # no spaces
                    && $sh_url !~ /XHR/ ){
                  Log3 $name,4,"[Shelly_webhook_update] port/webname and token are matching, no spaces, no XHR, skipping update";
                  #$urlcmd .= "\"$sh_url\","; # get this w/o change
              }else{
                  # removing spaces
                  $sh_url =~ s/ /+/g;
                  
                  # removing XHR
                  if( $sh_url =~ s/\?XHR=1\&/\?/ ){
                  }else{
                      $sh_url =~ s/\&XHR=1//;
                  }
                  # start changing url
                  if( $curr_host_port != $sh_port ){
                      $sh_url =~ s/:$sh_port\/$sh_webname/:$curr_host_port\/$curr_host_webname/;
                      Log3 $name,4,"[Shelly_webhook_update] changed port/webname of url: $sh_url";
                  }
                  Log3 $name,4,"[Shelly_webhook_update:Z] token=$sh_token";
                  if( $curr_token ne "" && $sh_token eq "" ){
                      $sh_url .= "&fwcsrf=$curr_token";
                      Log3 $name,4,"[Shelly_webhook_update:2a] token added to url: $sh_url";
                  }elsif( $curr_token eq "" && $sh_token ne "" ){
                      $sh_url =~ s/fwcsrf=csrf_[a-z0-9]+//;
                      $sh_url =~ s/&$//;      # has been at end of the query string
                      $sh_url =~ s/&&/&/;     # has been in the middle of the query string
                      $sh_url =~ s/\?&/\?/;   # has been first parameter in the query string
                      Log3 $name,4,"[Shelly_webhook_update:2r] token removed from url: $sh_url";
                  }elsif( $curr_token ne $sh_token ){
                      $sh_url =~ s/$sh_token/$curr_token/;
                      Log3 $name,4,"[Shelly_webhook_update:2c] changed token in url: $sh_url";
                  }else{
                      Log3 $name,4,"[Shelly_webhook_update] no changes regarding token";
                  }
                  #$urlcmd .= "\"$sh_url\",";
                  $urlChanges++;
                  $msg .= "\n$sh_hookid: $sh_url n \n";
                  Log3 $name,4,"[Shelly_webhook_update] $name ($id) ch$i: URL$u is now $sh_url";
              }
             # $urlcmd .= "\"$sh_url\",";
              $urlcmd .= "%22$sh_url%22,";
            }

            if( $urlChanges > 0 ){ # we have at least one (of up to 5) url to update
                $urlcmd =~ s/&/%26/g;
                $urlcmd = "?id=$sh_hookid&urls=[$urlcmd]"; 
                $urlcmd =~ s/,]/]/; # remove last comma
               # $urlcmd =~ s/ /%20/g;
               # $urlcmd =~ s/ /+/g;
          if(0){
                $urlcmd =~ s/,/%2C/g;
                $urlcmd =~ s/\[/%5B/g;
                $urlcmd =~ s/]/%5D/g;}
                Log3 $name,4,"[Shelly_webhook_update] $name update command [$ttlChanges] is: $urlcmd";
                $hash->{helper}{actionUpdate}[$ttlChanges]=$urlcmd;
                $ttlChanges++;
            }else{
                Log3 $name,5,"[Shelly_webhook_update] $name: check of action ID $sh_hookid is OK, nothing to do"; #5
            }
        }
  }
  #  FW_directNotify("FILTER=$name","#FHEMWEB:$FW_wname","FW_okDialog( \"$msg\" )", "");   $msg
  if( $ttlChanges == 0 ){
        $msg = "no actions to update";
  }else{
        $msg =  "start updating $ttlChanges actions with command $updcmd";
        #start update procedure with the last action
        # on success, we receive data
        Shelly_HttpRequest($hash,$updcmd,$hash->{helper}{actionUpdate}[$ttlChanges-1],"Shelly_webhook_update","proc",$ttlChanges); 
  }
  Log3 $name,3,"[Shelly_webhook_update] $name: $msg";
  return;
} #end Shelly_webhook_update()


########################################################################################
#
# Shelly_actionWebhook - Retrieve the url for a webhook
#
# Parameter hash, a =argument array
#                    $cmd: Create, Delete, ...
#                    entity:  corresponds to shellies component
#                    channel:  shellies channel = 0,1,...
#                    noe:  number of event in event-list
#
# result:  get <name> status
#          set <name> out_on|out_off|button_on|button_off|single_push, ... channel
#
# returning string like: &urls=["http://129.168.178.100:8083/fhem?cmd=get $name status&fwcsrf=csrf_1234567890"]
# &XHR=1 removed from string
########################################################################################

sub Shelly_actionWebhook ($@) {
  my ($hash, @a) = @_ ;
  my $comp    = shift @a; # shelly component
  my $channel = shift @a;
  my $noe     = shift @a; # number of event of component

  my $V = 4;  # verbose level
  my $msg;
  my $name = $hash->{NAME};
  $msg = "calling url-builder with args: $name $comp ";
  $msg .= defined($channel)?"ch:$channel ":"no channel ";
  $msg .= "noe:$noe";
  Log3 $name,$V,"[Shelly_actionWebhook] $msg";

  my $model = AttrVal($name,"model","generic");
  my $gen = $shelly_models{$model}[4]; # 0 is Gen1,  1 is Gen2
  #my $webhook = ($gen>=1?"&urls=[%22":"&urls[]="); # Gen2 : Gen1
  my $webhook = ($gen>=1?"urls=[\"":"urls[]="); # Gen2 : Gen1
  							
  my $host_ip = AttrVal($name,"host_ip",undef)//qx("\"hostname --all-ip-addresses\"");   # local
  $host_ip =~ m/(\d\d?\d?\.\d\d?\d?\.\d\d?\d?\.\d\d?\d?).*/; #extract ipv4-address
  $host_ip = $1;
  Log3 $name,$V,"[Shelly_actionWebhook] the host-ip of $name is: $host_ip";
  $webhook  .= "http://".$host_ip;

  my $fhemweb = AttrVal($name,"webhook","none");
  if($fhemweb eq "none"){
     $msg = "FHEMweb-device for $name is \'none\' or undefined)";
     Log3 $name,$V,"[Shelly_actionWebhook] $msg";
     return(undef,"Error: FHEMweb-device for $name is \'none\' or undefined");
  }

  my $port    = InternalVal($fhemweb,"PORT",undef);
  if(!$port ){
     $msg = "FHEMweb device without port-number";
     Log3 $name,$V,"[Shelly_actionWebhook] $msg";
     return(undef,"Error: $msg");
  }
  $webhook .= ":".$port;

  my $webname = AttrVal($fhemweb,"webname","fhem");
  Log3 $name,$V,"[Shelly_actionWebhook] FHEMweb-device \"$fhemweb\" has port \"$port\" and webname \"$webname\"";
  $webhook .= "\/".$webname;

  $webhook .= "?cmd=";    # set%2520".$name;

  $comp = "status" if(!$comp );
  if( $comp eq "status" || length($shelly_events{$comp}[$noe])==0 ){
      $webhook .= "get $name status";
  }else{
      $comp  = $shelly_events{$comp}[$noe];    #  %shelly_events
      $webhook .= "set $name ".$fhem_events{$comp};
      # encodings:   $ %24   { %7b    } %7d
      $webhook =~ s/\$/\%24/g;
      $webhook =~ s/\{/\%7b/g;
      $webhook =~ s/\}/\%7d/g;

      if( defined($channel) ){
          $webhook .= " $channel";
      }
  }
  $webhook =~ s/\s/\%2520/g;    # substitute '&' by '%2520', that will result in '%20'

  $webhook .= "&XHR=1"    if(0);

  # check, if CSRF is defined in according FHEMWEB
  my $token   = InternalVal($fhemweb,"CSRFTOKEN",undef);
  $webhook .= "&fwcsrf=".$token  if(defined $token);  # same as global variable: $FW_CSRF

  #$webhook .= ($gen>=1?"%22]":"");
  $webhook .= ($gen>=1?"\"]":"");

  $webhook =~ s/\&/\%26/g;    # substitute & by %26
  $webhook = "&".$webhook;

  Log3 $name,$V,"[Shelly_actionWebhook] $name: $webhook";
  ##########
  return ($webhook);
} #end Shelly_actionWebhook()


sub Shelly_firmwarecheck {
  ############ checking if current firmware is up to date
  my ($hash,$firmware,$update,$beta) = @_;
  my $name=$hash->{NAME};
  my $model = AttrVal($name,"model","generic");
  Log3 $name,5,"[Shelly_firmwarecheck] $name: current=$firmware update=".($update?$update:"-")." beta=$beta";#2
  my (@num_fw,@num_upd,$firmwareV,$updateV);
  my $txt ="-";
  my $icon="/";

  #-- we don't have info about an update (really no update,  no internet)
  if( !defined($update) ){  #gen2 only
      $update = $model =~ /walldisplay/ ? $shelly_firmware{walldisplay} : $shelly_firmware{gen2};
      ($firmware,$update,$txt,$icon) = cmpVersions( $firmware,$update );  
      if( $icon ne "OK" ){  
          $txt = "check internet for update min. $update";
      }
  
  #-- existing fw is beta
  }elsif( $firmware =~ /(rc)|(beta)/ ){
      ($firmware,$update,$txt,$icon) = cmpVersions( $firmware,$update );
      if( $icon eq "OK" ){  
          $txt = "downgrade possible to latest stable $update";
          $icon= "D";
      }
      if( defined($beta) && $beta ne "none" ){
          $txt .= ", check for new beta-version "; 
      }
      
  #-- we have a non-beta existing fw and no update / gen1
  }elsif( $update eq "none" ){
      $update = $model =~ /shelly4/ ? $shelly_firmware{shelly4} : $shelly_firmware{gen1};
      ($firmware,$update,$txt,$icon) = cmpVersions( $firmware,$update ); ## "0.0.0"
      if( defined($beta) && $beta ne "none" ){
          $txt = "check for beta-version ";  
          $icon= "B";
      }
      
  #-- we have an update ...
  }elsif( $update ne "none" ){
      ($firmware,$update,$txt,$icon) = cmpVersions( $firmware,$update );
      
      $txt .= ", check for beta-version"  if( $beta ne "none" );
  }
  Log3 $name,5,"[Shelly_firmwarecheck] $name: $firmware - $txt - $icon";
  return ($firmware,$txt,$icon);
} #end Shelly_firmwarecheck


sub cmpVersions {
    my ($firmware,$update)=@_;
    my (@oldN,@newN,$icon,$txt);
    $firmware =~ /v?(\d+)\.(\d+)\.?(\d+)?(-((rc)|(beta))\d+)?/;
    $oldN[1]=($1 // 0);
    $oldN[2]=($2 // 0);
    $oldN[3]=($3 // 0);
    $oldN[0] = "v$1.$2";
    $oldN[0] .= ".$3"  if( defined($3) );
    $oldN[0] .= $4  if( defined($4) );
    $update =~ /(\d+)\.(\d+)\.?(\d+)?(-((rc)|(beta))\d+)?/;
    $newN[1]=($1 // 0);
    $newN[2]=($2 // 0);
    $newN[3]=($3 // 0);
    $newN[0] = "v$1.$2";
    $newN[0] .= ".$3"  if( defined($3) );
    $newN[0] .= $4  if( defined($4) );
    $txt = "update needed to ".$newN[0];
    if( $newN[1] > $oldN[1] ){   #major update available
       $icon = "M";
    }elsif( $newN[1] < $oldN[1] ){       
       $icon = "OK";
    }elsif( $newN[2] > $oldN[2] ){   #minor update available
       $icon = "m";
    }elsif( $newN[2] < $oldN[2] ){       
       $icon = "OK";
    }elsif( $newN[3] > $oldN[3] ){   #patch update available
       $icon = "p";
    }else{
       $icon = "OK";
    }
    $txt = "-/-" if( $icon eq "OK" );#return $oldN[0]." == $icon >> $txt ".$newN[0];
    return ( $oldN[0],$newN[0],$txt,$icon );
} #end cmpVersions()


########################################################################################
#
# Shelly_error_handling - handling error from callback functions
#
# Parameter: hash, function, error , verbose
#
# Note:  messages to the Logfile handled by this sub are preceeded with the name of 
#          the origin sub in round parantheses, instead of [Shelly_error_handling]
#
########################################################################################

sub Shelly_error_handling {
    my ($hash, $func, $err, $verbose) = @_;
    my $name  = $hash->{NAME};
    my ($errN,$errE,$errS);
    $verbose=2 if( !defined($verbose) );
    Log3 $name,5,"($func) $name processing [Shelly_error_handling] for ERROR: $err";
    my $flag=0;
    if( $hash->{".updateTime"} ){  # is set by 'readingsBeginUpdate()'
        $flag=1;
    }else{
        readingsBeginUpdate($hash);
    }
    if( $err =~ /timed out/ ){
        if( $err =~ /read/ ){
            $errN = "Error: Timeout reading";
        }elsif( $err =~ /connect/ ){
            $errN = "Error: Timeout connecting";
        }else{
            $errN = "Error: Timeout";
        }
        $errS = "Error: Network";
    }elsif( $err =~ /not connected|unreachable/ ){   # from Shelly_proc.G:status
        $errN = $err;
        $errS = "Error: Network"; #disconnected
    }elsif( $err =~ /113/ ){   # keine Route zum Zielrechner (113)
        $errN = "not connected (no route)";
        $errS = "Error: Network"; #disconnected
    }elsif( $err =~ /gethostbyname.*failed/ ){
        $errN = $err;
        $errS = "Error in definition";
        readingsBulkUpdateIfChanged($hash,"network_ip-address","-",1);
    }elsif( $err =~ /JSON/ ){
        $errE = $err;
        $errS = "Error: JSON";
    }elsif( $err =~ /Auth/ ){ # Shelly is protected by User/Password
        $errE = undef;
        $errS = "Authentication required";
    }elsif( $err =~ /wrong (value|pct)/ ){
        $errE = $err;
        $errS = "Error";
    }elsif( $err =~ /wrong/ || $err =~ /401/ ){ #401 Unauthorized
        $errE = $err;
        $errS = "Error: Authentication";
    }elsif( $err =~ /404/ ){ #404 No Handler / wrong command
        $errE = $err;
        $errS = "Error: No Handler";
    }else{
        $errE = $err;
        $errS = "Error";
    }
    my $intv = InternalVal($name,"INTERVAL",600);
    my $msg = "($func) Device $name has Error \'$err\'";
    $msg .= ", state is set to \'$errS\'"  if( ReadingsVal($name,"state","-") ne $errS );
    $msg .= " -> increasing interval"  if( $errN && $intv < 43200 && $multiplyIntervalOnError > 1 );
    if( $errN ){
        # Network errors
        readingsBulkUpdateIfChanged($hash,"network",$errN,1);
        readingsBulkUpdateIfChanged($hash,"network_connection","offline");
        readingsBulkUpdateIfChanged($hash,"error","network",1);
        readingsBulkUpdate($hash,"network_disconnects",ReadingsNum($name,"network_disconnects",0)+1)
                                                                       if( ReadingsVal($name,"state","") ne $errS );
        if( $multiplyIntervalOnError > 1 && $intv < 43200 ){
            #increase the INTERNAL update interval, but do not exceed 43200sec=12hours
            $intv=minNum($multiplyIntervalOnError*$intv,43200);
            Shelly_Set($hash,$name,"interval",$intv);  # use Shelly_Set() to restart timer!
        }
        $verbose = 4  if( ReadingsAge($name,"network_disconnects",0) < 3600 ); # try to minimize Log-entries on lower verbose levels
    }elsif( $errE ){
        # other errors
        readingsBulkUpdateIfChanged($hash,"error",$errE,1);
    }
    Log3 $name,$verbose,$msg  if( ReadingsVal($name,"state","-") ne "Error: Network");
    readingsBulkUpdateMonitored($hash,"state",$errS, 1 ); 
    if( $flag==0 ){
       readingsEndUpdate($hash,1);
    }
    if( $errN ){        
        #******* RESTARTING TIMERS ***********
        # we need this after 'readingsEndUpdate'
        Log3 $name,4,"($func) calling Shelly_Set for restarting timer(s) caused by network-error of device $name";
        Shelly_Set($hash,$name,"startTimer");
        #*************************************
    }
} #end Shelly_error_handling()

########################################################################################

# generate events at least at given readings age, even if the reading has not changed
sub readingsBulkUpdateMonitored($$$@) # derived from fhem.pl readingsBulkUpdateIfChanged()
{
  my ($hash,$reading,$value,$changed)= @_;
  #$changed=0 if( $changed eq undef );
  my $MaxAge=AttrVal($hash->{NAME},"maxAge",2160000);  # default 600h
  if( !defined($value) ){
       Log3 $hash->{NAME},2,$hash->{NAME}.": undefined value for $reading";
       return;
       }
  if( ReadingsAge($hash->{NAME},$reading,$MaxAge)>=$MaxAge || $value ne ReadingsVal($hash->{NAME},$reading,"")  ){
       readingsBulkUpdate($hash,$reading,$value,$changed);
  }else{
       return undef;
  }
} #end readingsBulkUpdateMonitored()


sub Shelly_readingsBulkUpdate($$$@){ # derived from fhem.pl readingsBulkUpdateIfChanged()
  my ($hash,$reading,$value,$unit,$changed,$timestamp)= @_;
  return if( !defined($value) );
  my $name=$hash->{NAME};
  my $readingsProfile ="none";
     if( defined($unit) && $value =~ /^-?\d+(\.\d+)?$/ && $value ne "xx-" ){ ## value shall be a decimal 
        my $flag=-1;        
        
        if( $unit =~ /(.*)=(\d)/ ){ # eg "time=0"
            $unit = $1;
            $flag=$2;
        }elsif( $unit =~ /energy\/([km]?W[hm])/ ){   # mWh, Wh, kWh, Wm
            $unit = $1;
            $flag = 9;
        } 
        
        if( $flag == 9 ){
            $value = shelly_energy_fmt($hash,$value,$unit);
            
        }elsif( $value == 0 && $flag == 0 ){
            $value = "0 - disabled";
        }elsif( $value == 0 && $flag == 1 ){
            $value = "disabled";
        }elsif( $flag == 2 ){  #  rssi=2
          if( $value ne "-" && AttrVal($name,"showunits","none") ne "none"){
            my $rssi=$value;
            $value .= $si_units{rssi}[1];
            if( $rssi < -76 )    { $value .= " (bad)";}
            elsif( $rssi < -55 ) { $value .= " (fair)";}
            elsif( $rssi < -35 ) { $value .= " (good)";}
            else                 { $value .= " (excellent)";}    
          }
        }elsif( $value == 0 && $flag == 3 ){  #  rssi=3     normal values are negative!
             $value = "disabled"; 
        }elsif( $value == 2 && $flag == 3 ){ 
             return;
        }elsif( $value == -1 && $flag == 4 ){   # time=4
             return;
        }elsif( $flag == 5 && $hash->{units} ){  #  time=5
             my $seconds = $value;  # $value is uptime of device in seconds
             my $num;
             $value .= " sec";
             if(    $seconds > 31536000 ){ $value .= " (more than a year)"; }
             elsif( $seconds > 5184000 ) { $num = int($seconds/2592000); # 30 day per month
                                           $value .= " (more than $num months)"; }
             elsif( $seconds > 2678400 ) { $value .= " (more than a month)"; }  # 31 days
             elsif( $seconds > 192800 )  { $num = int($seconds/86400); # 24 hrsm per day
                                           $value .= " (more than $num days)"; }
             elsif( $seconds > 86400 )   { $value .= " (more than a day)"; }
             else                        { $value .= " (less than a day)"; } # don't worry if it is exactly a day
             $value .= ", last reboot at ".FmtDateTime(time()-$seconds);
        }elsif( AttrVal($name,"showunits","none") ne "none" ){
            $value .= $si_units{$unit}[1];  # add a si-units string to the reading
        }
     }
  if($value ne ReadingsVal($name,$reading,"")){ 
    Log3 $name,5,"[Shelly_readingsBulkUpdate] writing $name $reading $value ".($timestamp//"no timestamp ");
    if( !defined($timestamp) ){
      # Value of Reading changed: generate Event, timestamp is actual time
      readingsBulkUpdate($hash,$reading,$value,$changed);
    }else{
      # Value of Reading changed: generate Event and set timestamp as calculated by function
      readingsBulkUpdate($hash,$reading,$value,$changed,$timestamp);
    }
  }elsif($readingsProfile eq "none" ){                    # no change -> do noting,  like readingsBulkUpdateIfChanged()
      return undef;
  }elsif($readingsProfile eq "actual" ){                  # no change ->  set actual Timestamp, no Event   :: Browser refresh erforderlich
      # return readingsBulkUpdate($hash,$reading,$value,0,"2023-07-20 19:00:45"); # das gibt es nicht
      setReadingsVal($hash, $reading, $value,TimeNow() ); #  timestamp im Format "2023-07-20 19:33:45"
  }elsif($readingsProfile eq "update" ){                  # no change ->  set actual TS and sent event, like readingsBulkUpdate()
      return readingsBulkUpdate($hash,$reading,$value,$changed);
  }elsif($readingsProfile eq "maxAge" ){                  # no change ->  like above, but only when readings is more than maxAge old
      my $MaxAge=AttrVal($hash->{NAME},"maxAge",2160000);  # default 600h
      return readingsBulkUpdate($hash,$reading,$value,$changed)  if( ReadingsAge($hash->{NAME},$reading,$MaxAge)>=$MaxAge );
  }elsif($readingsProfile eq "hold" ){                    # no change ->  sent event, but dont change timestamp
       return readingsBulkUpdate($hash,$reading,$value,$changed,ReadingsTimestamp($hash->{NAME},$reading,undef));
  }else{ #Error
       return "Error";
  }
  return undef;
} #end Shelly_readingsBulkUpdate()


########################################################################################
#
# Shelly_HttpRequest - processing a non-blocking http call
#
# Parameter: hash,
#            cmd     eg. "/rpc/Switch.Set"
#            urlcmd  eg. "?id=0&on=true"
#            callback   to be called by Shelly_HttpResponse(), eg. "Shelly_response"
#            comp    additional parameter to process the response,  eg. "onoff"
#
# Note:      callback function for HttpUtils_NonblockingGet() is always Shelly_HttpResponse()
#
########################################################################################

sub Shelly_HttpRequest(@){
    my $hash=shift @_;
    my $cmd=shift @_;
    my $urlcmd=shift @_;
    my $function=shift @_;
    my $comp=shift @_;  # 2G only
    my $val =shift @_;
    my $name = $hash->{NAME};
    my $creds = Shelly_pwd($hash);
    my $tcpip = $hash->{DEF}; # formerly InternalVal($name,"TCPIP","");
    my $model = AttrVal($name,"model","generic");
    my $gen = $shelly_models{$model}[4]; # 0 is Gen1,  1 is Gen2
    my $url_ = "";##($gen>10 ? "/rpc/" : "/");
    $urlcmd = "" if( !defined($urlcmd) );
    $urlcmd =~ s/'/\"/g;
    $comp = "" if( !defined($comp) );

    my $param = {
        cmd      => $cmd,
        urlcmd   => $urlcmd,
        url      => "http://".$creds.$tcpip.$url_.$cmd.$urlcmd,
        timeout  => AttrVal($name,"timeout",4.9),
        hash     => $hash,
        callback => \&Shelly_HttpResponse,
        function => \&$function,    # reference to the subroutine given with $function
        funcname => $function,      # don't forget the name of the subroutine  
        comp     => $comp,
        val      => $val,
        request  => time()
        };
    Log3 $name,4,"[Shelly_HttpRequest] issue a non-blocking call to ".$param->{url}.", callback to $function, $comp";
    HttpUtils_NonblockingGet($param);
}   #end Shelly_HttpRequest()

########################################################################################
#
# Shelly_HttpResponse - processing the answer from a non-blocking http call
#
# Parameter: param,  the parameter hash
#            err     the err-parameter from the call
#            data    the returned data from the call, will be forwared to the function given by param
########################################################################################

sub Shelly_HttpResponse($){
    my ($param,$err,$data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $msg="";

    ### use a flag to avoid subsequent status calls ###
    ### the flag is set by Shelly_status()
    if( $param->{funcname} =~ /Shelly_status/ ){ # 1G  or  2G
         Log3 $name,4,"[Shelly_HttpResponse] incoming STATUS_CALL answer for $name, resetting flag ".$hash->{helper}{StatusCall};
         $hash->{helper}{StatusCall}=0;
    }
    ### -----------------------------------------------

    # write out request time
    if( AttrVal($name,'timeout',undef) ){ 
        my $maxRequest = ReadingsNum($name,$param->{cmd},0); # in milli-seconds
        my $currRequest= round(1000*(time()-$param->{request}),3);
        $maxRequest = $currRequest if( $currRequest > $maxRequest );
        readingsSingleUpdate($hash,$param->{cmd},"$maxRequest msec | $currRequest msec",1)  if( $param->{cmd} ne "" );
    }

    if($data eq "null"){
        $data = '{"cover":"successfull"}';
        Log3 $name,5,"[Shelly_HttpResponse] successfull: $name returned \'null\', transfering to JSON: $data";
        delete $hash->{CMD};
    }
    if( $param && $err ){
        Shelly_error_handling($hash,"Shelly_HttpResponse:err","$err :: ".$param->{cmd},2);
        readingsSingleUpdate($hash,"error",$err,1);
        my $val = $param->{code};
        $msg .= "code: $val"         if( defined($val) );
        $val = $param->{httpheader};
        $msg .= "  header: $val"     if( defined($val) );
        $msg .= "\nprotocol: ".$param->{protocol};
        $msg .= "  redirects: ".$param->{redirects};
        $msg .= "  url: ".$param->{url};
        $msg .= "\npath: ".$param->{path};
        Log3 $name,6,"[Shelly_HttpResponse:err] $msg";#6
        return;
    }elsif($data ne ""){
        my $call = $param->{url};
        $msg = AttrVal($name,"verbose",1) == 5 ? $data : (substr($data,0,16)."....");   # make Logging more readable
        Log3 $name,4,"[Shelly_HttpResponse] $name $call returned data: $msg";

        # Reset the increasing INTERVAL to default value (attr)
        if($multiplyIntervalOnError > 1 && ReadingsVal($name,"state","") =~ /Error/ ){
            Log3 $name,5,"[Shelly_HttpResponse] $name network Error is gone, reset INTERVAL to attributes value";
            Shelly_Set($hash,$name,"interval",-1);
        }

        if(ReadingsVal($name,"network","")=~/not connected/){
            readingsSingleUpdate($hash,"network","connected",1);
            readingsSingleUpdate($hash,"state","got data",1);
        }
        # extracting json from data
        my $json = JSON->new->utf8;
        my $jhash = eval{ $json->decode( $data ) };
        Log3 $name,5,"[Shelly_HttpResponse] $name: standard JSON decoding";
        if( !$jhash ){   ## option 'i' means case-insensitive
          if( $data =~ /Not found/i ){
            $msg="error in command: id or component not found";
          }elsif( $data =~ /Device mode is not dimmer/i ){
            $msg="is not a dimmer";
          }elsif( $data =~ /Device mode is not relay/i ){
            $msg="is not in relay mode";
          }elsif( $data =~ /Device mode is not roller/i ){
            $msg="is not in roller mode";
          }elsif( $data =~ /Bad roller_pos/i ){
            $msg="bad roller positon";
          }elsif( $data =~ /Bad timer/i ){
            $msg="bad timer argument";
          }elsif( $data =~ /Precondition failed:(.*)/i ){
            # eg: FAILED_PRECONDITION: Precondition failed: Overvoltage condition present!
            $msg=$1;
          }elsif( $data =~ /Bad/i ){ # something else gone wrong, eg. bad go
            $msg=$data;
          }else{
            $msg="invalid JSON data (2): $data";
            $json = JSON->new->utf8->relaxed;
            $jhash = eval{ $json->decode( $data ) };
            Log3 $name,5,"[Shelly_HttpResponse] $name: relaxed JSON decoding";
          }
        }
        if( !$jhash ){
            Shelly_error_handling($hash,"Shelly_HttpResponse:no-hash","$name: $msg",2);
            readingsSingleUpdate($hash,"error",$msg,1);
            return;
        }

        if( $jhash->{code} ){ # we got an error code
             my $err = $jhash->{code};
             my $msg = $jhash->{message};
             Shelly_error_handling($hash,"Shelly_HttpResponse:code","$err: $msg",2);
             return;
        }
        Log3 $name,5,"[Shelly_HttpResponse] $name: forwarding JSON-Hash to func: ".$param->{funcname};
        # calling the sub() forwarded by $param
        $param->{function}->($param,$jhash);
    }else{
        Log3 $name,3,"[Shelly_HttpResponse] ERROR haven't error neither data for $name (maybe missing credentials)";
    }
}   #end Shelly_HttpResponse()

1;

=pod
=item device
=item summary to communicate with a Shelly switch/roller actuator
=item summary_DE  Ger&auml;temodul f&uuml;r Shelly-Ger&auml;te
=begin html

<a id="Shelly"></a>
<h3>Shelly</h3>
<ul>
        <p> FHEM module to communicate with a Shelly switch/roller actuator/dimmer/RGBW controller or energy meter</p>
        <a id="Shelly-define"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; Shelly &lt;IP address&gt;[:port] [[user:]password]</code>
            <br />Defines the Shelly device. </p>
        Notes: <ul>
         <li>This module needs the packages JSON and HttpUtils</li>
         <li>In Shelly button, switch, roller or dimmer devices one may set URL values that are "hit" when the input or output status changes.
         This is useful to transmit status changes arising from locally pressed buttons directly to FHEM by setting
         <ul>
           <li> <i>Button switched ON url</i>: http://&lt;FHEM IP address&gt;:&lt;Port&gt;/fhem?cmd=get%20&lt;Devicename&gt;%20status</li>
           </ul>
         If one wants to detach the button from the output, one may generate an additional reading <i>button</i> by setting in the Shelly
           <ul>
           <li> For <i>Button switched ON url</i>:
                    http://&lt;FHEM IP address&gt;:&lt;Port&gt;/fhem?cmd=set%20&lt;Devicename&gt;%20<b>button_on</b>%20[&lt;channel&gt;]</li>
           <li> For <i>Button switched OFF url</i>:
                    http://&lt;FHEM IP address&gt;:&lt;Port&gt;/fhem?cmd=set%20&lt;Devicename&gt;%20<b>button_off</b>%20[&lt;channel&gt;]</li>
           </ul>
           Attention: Of course, a csrfToken must be included as well - or a proper <i>allowed</i> device declared.</li>
           <li>The attribute <code>model</code> is set automatically.
           For shelly devices that are not supported by the device, the attribute is set to <i>generic</i>.
           If the model attribute is set to <i>generic</i>, the device does not contain any actors, it is just a placeholder for arbitrary sensors</li>
         </ul>

        <a id="Shelly-set"></a>
        <h4>Set</h4>
        For all Shelly devices
        <ul>
        <li>
                <a id="Shelly-set-name"></a>
                <code>set &lt;name&gt; name &lt;ShellyName&gt;</code>
                <br />name of the Shelly device. If the Shelly is not named, its name will set to the name of the Fhem-device.
                ShellyName may contain space characters.
                </li>
                Note: Empty strings are not accepted, deletion of Shellies name on its website will result in remaining it to the modules name
        <li>
            <a id="Shelly-set-config"></a>
            Gen1: <code>set &lt;name&gt; config &lt;registername&gt; &lt;value&gt; [&lt;channel&gt;] </code>
            <br/>set the value of a configuration register (Gen1 devices only)
            <br/>Gen2: <code>set &lt;name&gt; config &lt;command&gt; </code>
            <br/>ap_enable|ap_disable  change the access point
            </li>
        <li>
            <a id="Shelly-set-interval"></a>
            <code>set &lt;name&gt; interval &lt;integer&gt;</code>
            <br>Temporarely set the update interval. Will be overwritten by the attribute on restart.
                          A value of -1 set the interval to the default given by attribute,
                          a value of 0 disables the automatic update.
            </li>
        <li>
            <a id="Shelly-set-password"></a>
            <code>set &lt;name&gt; password &lt;password&gt;</code>
            <br>This is the only way to set the password for the Shelly web interface.
            </li>
            For Shelly devices first gen, the attribute 'shellyuser' must be defined
            To remove a password, use:
            <code>set &lt;name&gt; password </code>
        <li>
            <a id="Shelly-set-reboot"></a>
            <code>set &lt;name&gt; reboot</code>
            <br>Reboot the Shelly
            </li>
        <li>
            <a id="Shelly-set-script_start"></a>
            <code>set &lt;name&gt; script_start &lt;id&gt;</code>
            <br>Start of script &lt;id&gt;
            </li>
        <li>
            <a id="Shelly-set-script_stop"></a>
            <code>set &lt;name&gt; script_stop &lt;id&gt;</code>
            <br>Stopping the script &lt;id&gt;
            </li>
        <li>
            <a id="Shelly-set-clear"></a>
            <code>set &lt;name&gt; clear &lt;reading&gt;</code>
            <br>Clearing the reading
            </li>
        <li>
            <a id="Shelly-set-update"></a>
            <code>set &lt;name&gt; update</code>
            <br>Update the Shelly to the latest stable version
            </li>

        </ul>
        <br/>For Shelly switching devices (model=shelly1|shelly1pm|shellyuni|shelly4|shellypro4pm|shellyplug|shellyem|shelly3em or
        (model=shelly2/2.5/plus2/pro2 and mode=relay))
        <ul>
            <li>
                <code>set &lt;name&gt; on|off|toggle  [&lt;channel&gt;] </code>
                <br />switches channel &lt;channel&gt; on or off. Channel numbers are 0 and 1 for model=shelly2/2.5/plus2/pro2, 0..3 for model=shelly4.
                       If the channel parameter is omitted, the module will switch the channel defined in the defchannel attribute.</li>
            <li>
                <code>set &lt;name&gt; on-for-timer|off-for-timer &lt;time&gt; [&lt;channel&gt;] </code>
                <br />switches &lt;channel&gt; on or off for &lt;time&gt; seconds.
                Channel numbers are 0 and 1 for model=shelly2/2.5/plus2/pro2 or model=shellyuni, and 0..3 model=shelly4/pro4.
                If the channel parameter is omitted, the module will switch the channel defined in the defchannel attribute.</li>
            <li>
                <code>set &lt;name&gt; xtrachannels </code>
                <br />create <i>readingsProxy</i> devices for switching devices with more than one channel</li>

        </ul>
        <br/>For Shelly roller blind devices (model=shelly2/2.5/plus2/pro2 and mode=roller)
        <ul>
            <li><a id="Shelly-set-open"></a><a id="Shelly-set-closed"></a>
                <code>set &lt;name&gt; open|closed|stop [&lt;duration&gt;]</code>
                <br />drives the roller blind open, closed or to a stop.
                      The commands open and closed take an optional parameter that determines the drive time in seconds</li>
            <li>
            <a id="Shelly-set-pos"></a>
                <code>set &lt;name&gt; pos &lt;integer percent value&gt; </code>
                <br/>drives the roller blind to a partially closed position (normally 100=open, 0=closed, see attribute pct100). If the integer percent value
                carries a sign + or - the following number will be added to the current value of the position to acquire the target value.
                <br/>
                <code>set &lt;name&gt; pct &lt;integer percent value&gt; </code>
                <br/>same as <code>set &lt;name&gt; pos &lt;integer percent value&gt; </code>
                </li>

            <li><a id="Shelly-set-delta"></a>
                <code>set &lt;name&gt; delta +|-&lt;percentage&gt;</code>
                <br />drives the roller blind a given percentage down or up.
                      The moving direction depends on the attribute 'pct100'.</li>
            <li>
                <a id="Shelly-set-zero"></a>
                <code>set &lt;name&gt; zero </code>
                <br />calibration of roller device </li>
            <li>
                <a id="Shelly-set-predefAttr"></a>
                <code>set &lt;name&gt; predefAttr</code>
                <br/>sets predefined attributes: devStateIcon, cmdIcon, webCmd and eventMap
                <br/>Attribute 'pct100' must be set earlier
                <br/>Attributes are set only when not defined yet
                </li>
        </ul>
        <br/>For Shelly dimmer devices model=shellydimmer or (model=shellyrgbw and mode=white)
        <ul>
            <li>
               <code>set &lt;name&gt; on|off|toggle  [&lt;channel&gt;] </code>
                <br />switches channel &lt;channel&gt; on or off. Channel numbers are 0..3 for model=shellyrgbw.
                      If the channel parameter is omitted, the module will switch the channel defined in the defchannel attribute.</li>
            <li>
                <code>set &lt;name&gt; on-for-timer|off-for-timer &lt;time&gt; [&lt;channel&gt;] </code>
                <br />switches &lt;channel&gt; on or off for &lt;time&gt; seconds. Channel numbers 0..3 for model=shellyrgbw.
                      If the channel parameter is omitted, the module will switch the channel defined in the defchannel attribute.</li>
            <li>
                <code>set &lt;name&gt; pct &lt;0..100&gt; [&lt;channel&gt;] </code>
                <br />percent value to set brightness value. Channel numbers 0..3 for model=shellyrgbw.
                      If the channel parameter is omitted, the module will dim the channel defined in the defchannel attribute.</li>
        </ul>
        <br/>For Shelly RGBW devices (model=shellyrgbw and mode=color)
        <ul>
            <li>
               <code>set &lt;name&gt; on|off|toggle</code>
                <br />switches device &lt;channel&gt; on or off</li>
            <li>
                <code>set &lt;name&gt; on-for-timer|off-for-timer &lt;time&gt;</code>
                <br />switches device on or off for &lt;time&gt; seconds. </li>
            <li>
                <a id="Shelly-set-hsv"></a>
                <code>set &lt;name&gt; hsv &lt;hue value 0..360&gt;,&lt;saturation value 0..1&gt;,&lt;brightness value 0..1&gt; </code>
                <br />comma separated list of hue, saturation and value to set the color. Note, that 360° is the same hue as 0° = red.
                Hue values smaller than 1 will be treated as fraction of the full circle, e.g. 0.5 will give the same hue as 180°.</li>
            <li>
                <a id="Shelly-set-gain"></a>
                <code>set &lt;name&gt; gain &lt;integer&gt;</code>
                <br /> number 0..100 to set the gain of the color channels</li>
            <li>
                <a id="Shelly-set-effect"></a>
                <code>set &lt;name&gt; effect &lt;Off|0|1|2|3&gt;</code>
                <br /> activies an effect: 1=Meteor Shower  2=Gradual Change  3=Flash </li>
            <li>
                <a id="Shelly-set-rgb"></a>
                <code>set &lt;name&gt; rgb &lt;rrggbb&gt; </code>
                <br />6-digit hex string to set the color</li>
            <li>
                <a id="Shelly-set-rgbw"></a>
                <code>set &lt;name&gt; rgbw &lt;rrggbbww&gt; </code>
                <br />8-digit hex string to set the color and white value</li>
            <li>
                <a id="Shelly-set-white"></a>
                <code>set &lt;name&gt; white &lt;integer&gt;</code>
                <br /> number 0..100 to set the white value</li>
        </ul>
        <br/>For Shelly Plugs Gen2+ devices (model=shellyplusplug)
        <ul>
            <li>
                <a id="Shelly-set-colorsOn"></a>
                <code>set &lt;name&gt; colorsOn|colorsOff red,green,blue [brightness]</code>
                red, green, blue and brightness are integer values 0-100
                <br />setting the plug's color of f</li>
        </ul>
                
                
        <a id="Shelly-get"></a>
        <h4>Get</h4>
        <ul>
            <li>
                <a id="Shelly-get-actions"></a>
                <code>get &lt;name&gt; actions</code>
                <br/>prints a list of the actions on the screen</li>
                <br/>Note: due to better readability, <code>%20</code> will be represented by the blank symbol <code>&blank;</code>
            <li>
                <a id="Shelly-get-colors"></a>
                <code>get &lt;name&gt; colors</code>
                <br/>write the colors of the Shelly Plug S LEDs to the reading "colorsRGB"</li>
            <li>
                <a id="Shelly-get-config"></a>
                <code>get &lt;name&gt; config [&lt;registername&gt;] [&lt;channel&gt;]</code>
                <br />get the value of a configuration register and writes it in reading config.
                          If the register name is omitted, only general data like e.g. the SHELLYID are fetched.</li>
            <li>
                <a id="Shelly-get-registers"></a>
                <code>get &lt;name&gt; registers</code>
                <br />displays the names of the configuration registers for this device</li>
            <li>
                <a id="Shelly-get-status"></a>
                <code>get &lt;name&gt; status</code>
                <br />returns the current status of the device.</li>
            <li>
                <a id="Shelly-get-settings"></a>
                <code>get &lt;name&gt; settings</code>
                <br />returns the current settings of the device.</li>
            <li>
                <a id="Shelly-get-model"></a>
                <code>get &lt;name&gt; model</code>
                <br />get the type of the Shelly</li>
            <li>
                <a id="Shelly-get-readingsGroup"></a>
                <code>get &lt;name&gt; readingsGroup Device|Firmware|Network|Status</code>
                <br />create a readingsGroup device to get a thematic summary of all Shellies</li>
            <li>
                <a id="Shelly-get-version"></a>
                <code>get &lt;name&gt; version</code>
                <br />display the version of the module</li>
        </ul>
        <a id="Shelly-attr"></a>
        <h4>Attributes</h4>
        <ul>
        <li>
                <a id="Shelly-attr-ShellyName"></a>
                <code>attr &lt;name&gt; name &lt;ShellyName&gt;</code>
                <br />name of the Shelly device. If the Shelly is not named, its name will set to the name of the Fhem-device.
                ShellyName may contain space characters.
                </li>
                Note: Empty strings are not accepted, deletion of Shellies name on its website will result in remaining it to the modules name

            <li>
                <a id="Shelly-attr-shellyuser"></a>
                <code>attr &lt;name&gt; shellyuser &lt;shellyuser&gt;</code>
                <br />username for addressing the Shelly web interface. Set the password with the set command.</li>
                Applicable only for Shellies first gen.
            <li>
                <a id="Shelly-attr-model"></a>
                <code>attr &lt;name&gt; model &lt;model&gt; </code>
                <br />type of the Shelly device. If the model attribute is set to <i>generic</i>, the device does not contain any actors,
                it is just a placeholder for arbitrary sensors.
                Note: this attribute is determined automatically.</li>
            <li>
                <a id="Shelly-attr-mode"></a>
                <code>attr &lt;name&gt; mode relay|roller</code> (only for model=shelly2/2.5/plus2/pro2)
                <br />             <code>attr &lt;name&gt; mode white|color </code> (only for model=shellyrgbw)
                <br />type of the Shelly device</li>
             <li>
                <a id="Shelly-attr-interval"></a>
                <code>attr &lt;name&gt; interval &lt;interval&gt;</code>
                <br />Update interval for reading in seconds. The default is 60 seconds, a value of 0 disables the automatic update.
                <br />
                <br />Note: The ShellyPro3EM / ShellyProEM50 energy meter is working with a set of two intervals:
                   The power values are read at the main interval (as set by the attribute value),
                   the energy values and calculated power values are read at a multiple of 60 seconds.
                   When setting the main interval, the value is adjusted to match an integer divider of 60.
                </li>
             <li>
                <a id="Shelly-attr-maxAge"></a>
                <code>attr &lt;name&gt; maxAge &lt;seconds&gt;</code>
                <br/>Maximum age of readings in seconds. The default is 2160000 seconds = 600 hours, minimum value is 'interval'.
                <br/>
                </li>
             <li>
                <code>attr &lt;name&gt; showinputs show|hide</code>
                <a id="Shelly-attr-showinputs"></a>
                <br />Add the state of the input buttons and their mode to the readings. The default value is show.
                Most comfortable when triggered by actions/webhooks from the device.
                </li>
             <li>
                <a id="Shelly-attr-showunits"></a>
                <code>attr &lt;name&gt; showunits none|original|normal|normal2|ISO</code>
                <br />Add the units to the readings. The default value is none (no units).
                      The energy unit can be selected between Wh, kWh, kJ.
                      <ul>
                <li><code>none</code>: recommended to get results consistend with ShellyMonitor</li>
                <li><code>original</code>: the units are as given by the shelly device (eg Wm (Watt-Minutes) for most of first generation devices)</li>
                <li><code>normal</code>: energy will be calculated to Wh (Watt-Hours)</li>
                <li><code>normal2</code>: energy will be calculated to kWh (Kilo-Watt-Hours)</li>
                <li><code>ISO</code>: energy will be calculated to kJ (Kilo-Joule)</li>
                      </ul>
                </li>
             <li>
                <a id="Shelly-attr-maxpower"></a>
                <code>attr &lt;name&gt; maxpower &lt;maxpower&gt;</code>
                <br />Max power protection in watts. The default value and its range is predetermined by the shelly device.
                </li>
             <li>
                <a id="Shelly-attr-timeout"></a>
                <code>attr &lt;name&gt; timeout &lt;timeout&gt;</code>
                <br />Timeout in seconds for HttpUtils_NonblockingGet. The default is 4 seconds.
                Careful: Use this attribute only if you get 'connect to ... timed out' errors in your log.
                </li>
             <li>
                <a id="Shelly-attr-webhook"></a>
                <code>attr &lt;name&gt; webhook none|&lt;FHEMWEB-device&gt; (default:none) </code>
                <br />create a set of webhooks on the shelly device which send a status request to fhem (only 2nd gen devices).
                <br />If a csrf token is set on the FHEMWEB device, this is taken into account. The tokens are checked regulary and will be updated on the shelly.
                <br />The names of the webhooks in the shelly device are based on the names of shellies events,
                with an preceding and trailing underscore (eg _COVER.STOPPED_).
                <br/>If the attribute is set to none, these webhooks (with a trailing underscore) will be deleted.
                </li>
                <s>Webhooks that point to another IP address are ignored by this mechanism.</s>
                <br/>Note: When deleting a fhem device, remove associated webhooks on the Shelly before with <code>attr &lt;name&gt; webhook none </code> or
                <code>deleteattr &lt;name&gt; webhook</code>
        </ul>
        <br/>For Shelly switching devices (mode=relay for model=shelly2/2.5/plus2/pro2, standard for all other switching models)
        <ul>
        <li>
                <a id="Shelly-attr-defchannel"></a>
                <code>attr &lt;name&gt; defchannel &lt;integer&gt; </code>
                <br />only for multi-channel switches eg model=shelly2|shelly2.5|shelly4 or shellyrgbw in white mode:
                Which channel will be switched, if a command is received without channel number
                </li>
        </ul>
        <br/>For Shelly roller blind devices (mode=roller for model=shelly2/2.5/plus2/pro2)
        <ul>
            <li>
                <a id="Shelly-attr-maxtime"></a>
                <code>attr &lt;name&gt; maxtime &lt;int|float&gt; </code>
                <br/>time needed (in seconds) for a complete drive upward or downward</li>
            <li>
                <a id="Shelly-attr-maxtime_close"></a>
                     <code>attr &lt;name&gt; maxtime_close &lt;int&gt;   </code> Gen1
                <br/><code>attr &lt;name&gt; maxtime_close &lt;float&gt; </code> Gen2
                <br/>time needed (in seconds) for a complete drive downward</li>
            <li>
                <a id="Shelly-attr-maxtime_open"></a>
                     <code>attr &lt;name&gt; maxtime_open &lt;int&gt;   </code> Gen1
                <br/><code>attr &lt;name&gt; maxtime_open &lt;float&gt; </code> Gen2
                <br/>time needed (in seconds) for a complete drive upward</li>
            <li>
                <a id="Shelly-attr-slat_control"></a>
                     <code>attr &lt;name&gt; slat_control enabled|disabled </code> 
                <br/>whether slat control is enabled by the Shelly</li>
            <li>
                <a id="Shelly-attr-slat_pos"></a>
                     <code>attr &lt;name&gt; slat_pos &lt;0...100&gt;   </code>
                <br/>percentual value for the pos of the slats</li>
            <li>
                <a id="Shelly-attr-pct100"></a>
                <code>attr &lt;name&gt; pct100 open|closed (default:open) </code>
                <br/>roller or blind devices only: is pct=100 open or closed ? </li>
        </ul>
        <br/>For energy meter ShellyPro3EM/ShellyProEM50 
        <ul>
            <li>
                <a id="Shelly-attr-Energymeter_P"></a>
                <code>attr &lt;name&gt; Energymeter_P &lt;float&gt; </code>
                <br />calibrate to the suppliers meter-device for meters with backstop functionality
                           or for the purchase meter if two meters or a bidirectional meter are installed
                <br />value(s) added to Shellies value(s) to represent the suppliers meter value(s), in Wh (Watthours).
                <br />     Note: the stored attribute value is reduced by the actual value</li>
            <li>
                <a id="Shelly-attr-Energymeter_R"></a>
                <code>attr &lt;name&gt; Energymeter_R &lt;float&gt; </code>
                <br />calibrate returned energy to the second suppliers meter-device (Bidirectional meters only)
                <br />value(s) added to Shellies value(s) to represent the suppliers meter value(s), in Wh (Watthours).
                <br />     Note: the stored attribute value is reduced by the actual value</li>
            <li>
                <a id="Shelly-attr-Energymeter_F"></a>
                <code>attr &lt;name&gt; Energymeter_F &lt;float&gt; </code>
                <br />calibrate to the suppliers meter-device for Ferraris-type meters
                <br />value(s) added to Shellies value(s) to represent the suppliers meter value(s), in Wh (Watthours).
                <br />     Note: the stored attribute value is reduced by the actual value</li>
            <li>
                <a id="Shelly-attr-EMchannels"></a>
                <code>attr &lt;name&gt; EMchannels ABC_|L123_|_ABC|_L123 (default: _ABC) </code>
                <br/>used to attach prefixes or postfixes to the names of the power and energy readings
                <br/><font color="red">Caution: deleting or change of this attribute will remove relevant readings! </font></li>
            <li>
                <a id="Shelly-attr-Periods"></a>
                <code>attr &lt;name&gt; Periods &lt;periodes&gt; </code>
                <br/>comma separated list of periodes to calculate energy differences
                <br/>hourQ: a quarter of an hour
                <br/>hourT: a twelth of an hour (5 minutes)
                <br/>dayQ:  a quarter of a day
                <br/>dayT:  a third of a day (8 hours), starting at 06:00
                <br/> <font color="red">Caution: when removing an entry from this list or when deleting this attribute,
                           all relevant readings are deleted!</font></li>
            <li>
                <a id="Shelly-attr-PeriodsCorr-F"></a>
                <code>attr &lt;name&gt; PeriodsCorr-F &lt;0.90 ... 1.10&gt; </code>
                <br/>a float number as correction factor for the energy differences for the periods given by the attribute "Periods"   </li>
        </ul>
        <br/>Standard attributes
        <ul>
            <li><a href="#alias">alias</a>,
                <a href="#comment">comment</a>,
                <a href="#event-on-update-reading">event-on-update-reading</a>,
                <a href="#event-on-change-reading">event-on-change-reading</a>,
                <a href="#room">room</a>,
                <a href="#eventMap">eventMap</a>,
                <a href="#verbose">verbose</a>,
                <a href="#webCmd">webCmd</a></li>
        </ul>



        <a id="Shelly-events"></a>
        <h4>Readings/Generated events </h4> (selection)
        <ul>
           <h5>Webhooks (2nd gen devices only)</h5>
            <li>   <code>webhook_cnt active / controlled / total </code>
                   <br/>number of webhooks stored in the shelly </li>
            <li>   <code>webhook_ver</code>
                   <br/>latest revision number of shellies webhooks </li>


           <h5>ShellyPlus and ShellyPro devices  </h5>

           <li>
                  indicating the configuration of Shellies hardware inputs
                  <br/>  <code>input_&lt;channel&gt;_mode</code>
                  <br/>  ShellyPlus/Pro2PM in relay mode:
                  <br/>		<code>button|switch straight|inverted follow|detached</code>
                  <br/>  ShellyPlus/Pro2PM in roller mode:
                  <br/>		<code>button|switch straight|inverted single|dual|detached normal|swapped</code>
                  <br/>  ShellyPlusI4:
                  <br/>		<code>button|switch straight|inverted</code>
                  <ul>
                  <li>   <code>button     </code>  input type: button attached to the Shelly </li>
                  <li>   <code>switch     </code>  input type: switch attached to the Shelly </li>
                  <li>   <code>straight   </code>  the input is not inverted </li>
                  <li>   <code>inverted   </code>  the input is inverted </li>
                  <li>   <code>single     </code>  control button mode: the roller is controlled by one input  * </li>
                  <li>   <code>dual       </code>  control button mode: the roller is controlled by two inputs * </li>
                  <li>   <code>follow     </code>  control button mode: the relay is controlled by the input  ** </li>
                  <li>   <code>detached   </code>  control button mode: the input is detached from the relay|roller  </li>
                  <li>   <code>normal     </code>  the inputs are not swapped * </li>
                  <li>   <code>swapped    </code>  the inputs are swapped * </li>
                  <br/>  * roller mode only   ** relay mode only
                  <br/>
                  </ul>
                  </li>

           <li>
                  indicating the reason for start or stop of the roller
                  <br/>  <code>start_reason, stop_reason</code>
                  <ul>
                  <li>   <code>button       </code>  button or switch attached to the Shelly </li>
                  <li>   <code>http         </code>  HTTP/URL eg Fhem </li>
                  <li>   <code>HTTP         </code>  Shelly-App </li>
                  <li>   <code>loopback     </code>  Shelly-App timer </li>
                  <li>   <code>limit_switch </code>  roller reaches upper or lower end </li>
                  <li>   <code>timeout      </code>  after given drive time (eg fhem) </li>
                  <li>   <code>WS_in	    </code>  Websocket </li>
                  <li>   <code>obstruction  </code>  Obstruction detection </li>
                  <li>   <code>overpower    </code> </li>
                  <li>   <code>overvoltage  </code> </li>
                  <li>   <code>overcurrent  </code> </li>
                  </ul>
                  </li>



           <h5>ShellyPlusI4 </h5>

                  an input in mode 'button' has usually the state 'unknown'.
                  When activated, the input state is set to 'ON' for a short periode, independent from activation time.
                  The activation time and sequence is reprensented by the readings <code>input_&lt;ch&gt;_action</code> and <code>input_&lt;ch&gt;_actionS</code>,
                  which will act simultanously with following values:
                  <ul>
                  <li> S	single_push </li>
                  <li> SS 	double_push </li>
                  <li> SSS 	triple_push </li>
                  <li> L 	long_push </li>
                  </ul>

                  NOTE: the readings of an input in mode 'button' cannot actualized by polling.
                  It is necessary to set actions/webhooks on the Shelly!

                  <br/>
                  <br/> Webhooks on ShellyPlusI4
                  <br/> Webhooks generated by Fhem are named as follows:
                  <br/>Input mode 'switch'
                  <ul>
                  <li> _INPUT.TOGGLE_ON_  </li>
                  <li> _INPUT.TOGGLE_OFF_ </li>
                  </ul>

                  <br/>Input mode 'button'
                  <ul>
                  <li> _INPUT.BUTTON_PUSH_  </li>
                  <li> _INPUT.BUTTON_DOUBLEPUSH_  </li>
                  <li> _INPUT.BUTTON_TRIPLEPUSH_  </li>
                  <li> _INPUT.BUTTON_LONGPUSH_  </li>
                  </ul>


           <h5>ShellyPro3EM / ShellyProEM50 </h5>

           <h6>Power</h6>

           Power, Voltage, Current and Power-Factor are updated at the main interval, unless otherwise specified
            <li>
                <a name="Power"></a>Active Power
                <br/> <code>Active_Power_&lt;A|B|C|T&gt;</code>
                <br/> float values of the actual active power </li>
            <li>
                <a name="Calculated Power"></a>Calculated Active Power
                <br/> <code>Active_Power_calculated</code>
                <br/> float value, calculated from the difference of Shellies Total_Energy reading (updated each minute, or multiple)</li>
            <li>
                <a name="Integrated Power"></a>Integrated Active Power
                <br/> <code>Active_Power_integrated</code>
                <br/> float value, calculated from the integration of Shellies power readings (updated each minute, or multiple)</li>
            <li>
                <a name="Pushed Power"></a>Pushed Power
                <br/> <code>Active_Power_pushed_&lt;A|B|C|T&gt;</code>
                <br/> float values of the actual power pushed by the Shelly when the value of a phase differs at least 10% to the previous sent value
                       (update interval depends on load, possible minimum is 1 second)
                       Action on power-events on the Shelly must be enabled.
                       </li>
            <li>
                <a name="Apparent Power"></a>Apparent Power
                <br/> <code>Apparent_Power_&lt;A|B|C|T&gt;</code>
                <br/> float values of the actual apparent power </li>
            <li>
                <a name="Power"></a>Voltage, Current and Power-Factor
                <br/> <code>Voltage_&lt;A|B|C&gt;</code>
                <br/> <code>Current_&lt;A|B|C|T&gt;</code>
                <br/> <code>Power_Factor_&lt;A|B|C&gt;</code>
                <br/> float values of the actual voltage, current and power factor </li>

           <h6>Energy</h6>

                  Energy readings are updated each minute, or multiple.
                <br/> When the showunits attribute is set, the associated units (Wh, kWh, kJ) are appended to the values
            <li>
                <a name="Energy"></a>Active Energy
                <br/> <code>Purchased_Energy_&lt;A|B|C|T&gt;</code>
                <br/> <code>Returned_Energy_&lt;A|B|C|T&gt;</code>
                <br/> float values of the purchased or returned energy per phase and total </li>
            <li>
                <a name="Total_Energy&lt;period&gt;"></a>Total Active Energy
                <br/> <code>Total_Energy</code>
                <br/> float value of total purchased energy minus total returned energy
                <br/> A minus sign is indicating returned energy.
                <br/> The timestamp of the reading is set to the full minute, as this is Shellies time base.
                      Day and Week are based on GMT.
                      </li>
            <li>
                <a name="Total_Energymeter&lt;type&gt;"></a>Energymeter
                <br/> <code>Total_Energymeter_&lt;F|P|R&gt;</code>
                <br/> float values of the purchased (P) or returned (R) energy displayed by the suppliers meter.
                      For Ferraris type meters (F), the returned energy is subtracted from the purchased energy </li>
            <li>
                <a name="Energy periods&lt;period&gt;"></a>Energy differences in a period of time
                <br/> <code>[measuredEnergy]_&lt;Min|QHour|Hour|Qday|TDay|Day|Week&gt;</code>
                <br/> float value of energy in a period of time (updated at the defined time interval).
                <br/> QDay is a period of 6 hours, starting at 00:00.
                <br/> TDay is a period of 8 hours, starting at 06:00.
                <br/> Week is a period of 7 days, starting mondays at 00:00.
                      </li>

        </ul>
        </ul>
=end html

=begin html_DE

<a id="Shelly"></a>
<h3>Shelly</h3>
<ul>
        <p> FHEM Modul zur Kommunikation mit Shelly Aktoren und Sensoren/Energiezähler</p>
        <a id="Shelly-define"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; Shelly &lt;IP-Adresse|DNS-Name&gt;[:Port] [[Benutzername:]Passwort]</code>
            <br/>Definiert das Shelly Device.
            <table>
	       <tr>
		     <th align=left>Beispiele</th>
               </tr>
               <tr>
                     <td><code>define meinDevice Shelly 192.168.178.100</code> </td>
                     <td>      mit IP-Adresse </td>
               </tr>      
               <tr>
                     <td> <code>define meineLampe Shelly 192.168.178.101 fritzi:geheim  &nbsp;&nbsp;&nbsp; </code> </td>
                     <td>       mit IP-Adresse, Benutzername und Passwort </td>
               </tr>      
               <tr>
                     <td> <code>define meinePumpe Shelly ShellyPlusPlugS-Pumpe</code></td>
                     <td>       mit DNS-Namen </td>
               </tr>      
               <tr>
                     <td> <code>define meinShelly Shelly 192.168.178.100:11101</code> </td>
                     <td>       mit IP-Adresse des Range-Extender-Devices und Port-Nummer </td>        </tr> 
            </table>
            </p>
         <!--   IP-Adresse:	die Adresse des Shelly
            Port:    die Portnummer, wenn der Shelly an einem als Range-Extender arbeitenden Shelly angemeldet ist
            Benutzername:  nur bei Gen1:
            Passwort: -->
        Hinweise: <ul>
        <li>Dieses Modul benötigt die Pakete JSON und HttpUtils </li>

        <li>Das Attribut <code>model</code> wird automatisch gesetzt.
           Für Shelly Geräte, welche nicht von diesem Modul unterstützt werden, wird das Attribut zu <i>generic</i> gesetzt.
           Das Device enthält dann keine Aktoren, es ist nur ein Platzhalter für die Bereitstellung von Readings</li>

        <li>Bei bestimmten Shelly Modellen können URLs (Webhooks) festgelegt werden, welche bei Eintreten bestimmter Ereignisse ausgelöst werden.
           Beispielsweise lauten die Webhooks für die Information über die Betätigung lokaler Taster wie folgt:
           <ul>
              <li> <i>Button switched ON url</i>:
                    http://&lt;FHEM IP address&gt;:&lt;Port&gt;/fhem?cmd=set%20&lt;Devicename&gt;%20<b>button_on</b>%20[&lt;channel&gt;]</li>
              <li> <i>Button switched OFF url</i>:
                    http://&lt;FHEM IP address&gt;:&lt;Port&gt;/fhem?cmd=set%20&lt;Devicename&gt;%20<b>button_off</b>%20[&lt;channel&gt;]</li>
           </ul>
         Ein Webhook für die Aktualisierung aller Readings lautet beispielsweise:
           <ul>
           <li> http://&lt;FHEM IP address&gt;:&lt;Port&gt;/fhem?cmd=<b>get</b>%20&lt;Devicename&gt;%20<b>status</b></li>
           </ul>
           Ein CSRF-Token muss gegebenenfalls in den URL aufgenommen werden oder ein zugehörendes <i>allowed</i> Device muss festgelegt werden.<br/>
           Die URLs (Webhooks) können mit dem Attribut 'webhook' automatisiert angelegt werden
       </li>
       </ul>

        <a id="Shelly-set"></a>
        <h4>Set</h4>
        Für alle Shelly Geräte
        <ul>
        <br>
        <li><a href="#setExtensions"> Set-Extensions</a> können genutzt werden, allerdings bei Geräten mit mehreren Kanälen
                     nur für den per <code>defchannel</code> festgelegten Kanal.
        </li>
        <br><li>
            <a id="Shelly-set-name"></a>
            <code>set &lt;name&gt; name &lt;ShellyName&gt;</code>
            <br/>Name des Shelly Gerätes. <!--Wenn der Shelly noch keinen Namen erhalten hat wird der Shelly nach dem FHEM-Device benannt.-->
            Der Shellyname darf Leerzeichen enthalten.
            </li>
            Hinweis: Leere Zeichenkentten werden nicht akzeptiert.
            <!--Nach dem Löschen eines Shelly Namens (auf Shellies-Website) wird der Shelly Name auf den Namen des FHEM Devices gesetzt.-->
        <li>
            <a id="Shelly-set-config"></a>
            Gen1: <code>set &lt;name&gt; config &lt;registername&gt; &lt;value&gt; [&lt;channel&gt;] </code>
            <br/>Setzen eines Registers auf den Wert value (nur für Shellies der 1. Generation)
            <br/>Die verfügbaren Register erhält man mit <code>get &lt;name&gt; registers</code>

            <br/>Gen2: <code>set &lt;name&gt; config &lt;command&gt; </code>
            <br/>ap_enable|ap_disable  aktiviert/deaktiviert den Zugangspunkt (access point)
            </li>
        <li>
            <a id="Shelly-set-interval"></a>
            <code>set &lt;name&gt; interval &lt;integer&gt;</code>
            <br>Vorübergehendes Setzen des Aktualisierungsintervals. Wird bei Restart vom Wert des Attributes interval überschrieben.
                         Der Wert -1 setzt das Interval auf den Wert des Attributes,
                         der Wert 0 deaktiviert die automatische Aktualisierung.
            </li>
        <li>
            <a id="Shelly-set-password"></a>
            <code>set &lt;name&gt; password &lt;password&gt;</code>
            <br>Setzen des Passwortes für das Shelly Web Interface
            <code>set &lt;name&gt; password </code>
            <br>Entfernen des in Fhem gespeicherten Passwortes (Aufruf ohne Parameter)
            </li>
            Bei Shelly-Geräten der 1. Generation muss zuvor das Attribut 'shellyuser' gesetzt sein.
            Hinweis: Beim Umbenennen des Devices mit 'rename' geht das Passwort verloren
        <li>
            <a id="Shelly-set-reboot"></a>
            <code>set &lt;name&gt; reboot</code>
            <br>Neustarten des Shelly
            </li>
        <li>
            <a id="Shelly-set-script_start"></a>
            <code>set &lt;name&gt; script_start &lt;id&gt;</code>
            <br>Starten des Scripts &lt;id&gt;
            </li>
        <li>
            <a id="Shelly-set-script_stop"></a>
            <code>set &lt;name&gt; script_stop &lt;id&gt;</code>
            <br>Stoppen des Scripts &lt;id&gt;
            </li>
        <li>
            <a id="Shelly-set-clear"></a>
            <code>set &lt;name&gt; clear &lt;reading&gt;</code>
            <br>Zurücksetzen des/der ausgewählten Readings
            <ul>
              <li> disconnects: Reading <code>network_disconnects</code></li> 
              <li> error: Reading <code>error</code></li> 
              <li> energy: Reading <code>energy</code>  (nur bei PMmini Leistungsmessgeräten)</li> 
              <li> responsetimes: Readings <code>/....</code>  (nur sichtbar, wenn Attribut <code>timeout</code> gesetzt ist)</li>
            </ul> 
            </li> 
        <li>
            <a id="Shelly-set-update"></a>
            <code>set &lt;name&gt; update</code>
            <br>Aktualisieren der Shelly Firmware zur aktuellen stabilen Version
            </li>

        </ul>
        <br/>Für Shelly mit Relais (model=shelly1|shelly1pm|shellyuni|shelly4|shellypro4pm|shellyplug|shellyem|shelly3em oder
        (model=shelly2/2.5/plus2/pro2 und mode=relay)) sowie Dimmer, RGBW und Leuchten
        <ul>
            <li>
                <a id="Shelly-set-ON"></a>
                <a id="Shelly-set-OFF"></a>
                <code>set &lt;name&gt; ON|OFF </code>
                <br />schaltet ALLE Kanäle eines mehrkanaligen Gerätes ein bzw. aus. </li>
            <li>
                <a id="Shelly-set-on"></a>
                <a id="Shelly-set-off"></a>
                <a id="Shelly-set-toggle"></a>
                <code>set &lt;name&gt; on|off|toggle  [&lt;channel&gt;] </code>
                <br />schaltet den Kanal &lt;channel&gt; ein bzw. aus. Bei Geräten mit nur einem Kanal kann die Angabe des Kanals entfallen.
                       Wenn bei mehrkanaligen Geräte keine Kanalnummer angegeben wird, wird der mit dem Attribut 'defchannel' definierte Kanal geschaltet.</li>
            <li>
                <a id="Shelly-set-on-for-timer"></a>
                <a id="Shelly-set-off-for-timer"></a>
                <code>set &lt;name&gt; on-for-timer|off-for-timer &lt;time&gt; [&lt;channel&gt;] </code>
                <br />schaltet den Kanal &lt;channel&gt; für &lt;time&gt; Sekunden ein bzw. aus.
                    Wenn bei mehrkanaligen Geräte keine Kanalnummer angegeben wird, wird der mit dem Attribut 'defchannel' definierte Kanal geschaltet.
                <ul>
                Hinweise:
                 <li>Im Shelly aktivierte Timer 'auto_on' und 'auto_off' bleiben unberücksichtig.</li>
                 <li>Bei nachfolgenden Befehlen, z.B. 'set ... pct ...' bleiben gestartete 'on-for-timer' Timer bestehen</li>
                </ul>
                </li>

            <li>
                <a id="Shelly-set-intervals"></a>
                <code>set &lt;name&gt; intervals &lt;from1&gt;-&lt;till1&gt; &lt;from2&gt;-&lt;till2&gt; ...</code>
                <br />Das Gerät wird für die spezifizierten Intervalle eingeschaltet.
                      Bei mehrkanaligen Geräten wird der mit <code>defchannel</code> definierte Kanal geschaltet.
                      Die einzelnen Intervalle sind Leerzeichen getrennt, und ein Intervall besteht aus zwei Zeitspezifikationen,
                      die mit einem "-" getrennt sind.</li>

            <li>
                <a id="Shelly-set-xtrachannels"></a>
                <code>set &lt;name&gt; xtrachannels </code>
                <br />Erstellen von <i>readingsProxy</i> Devices für Shellies mit mehr als einem Kanal</li>

        </ul>
        <br/>Für Shelly Rollladenaktoren (model=shelly2/2.5/plus2/pro2 und mode=roller)
        <ul>
            <li>
                <a id="Shelly-set-open"></a>
                <a id="Shelly-set-closed"></a>
                <code>set &lt;name&gt; open|closed [&lt;duration&gt;]</code>
                <br />Fährt den Rollladen aufwärts zur Position offen (open) bzw. abwärts zur Position geschlossen (closed).
                      Es kann ein optionaler Parameter für die Fahrzeit in Sekunden mit übergeben werden
                      </li>

            <li>
                <a id="Shelly-set-stop"></a>
                <code>set &lt;name&gt; stop</code>
                <br />Beendet die Fahrbewegung (stop).
                      </li>

            <li>
                <a id="Shelly-set-pos"></a>
                <code>set &lt;name&gt; pos &lt;integer percent value&gt; </code>
                <br />Fährt den Rollladen zu einer Zwischenstellung (normalerweise gilt 100=offen, 0=geschlossen, siehe Attribut 'pct100').
          <!--      <s>Wenn dem Wert für die Zwischenstellung ein Plus (+) oder Minus (-) - Zeichen vorangestellt wird,
                wird der Wert auf den aktuellen Positionswert hinzugezählt.</s>  //-->
                <br />

                äquivalent zu <code>set &lt;name&gt; pct &lt;integer percent value&gt; </code>
                <br />
                      </li>

            <li>
                <a id="Shelly-set-delta"></a>
                <code>set &lt;name&gt; delta +|-&lt;percentage&gt;</code>
                <br />Fährt den Rollladen einen gegebenen Prozentwert auf oder ab.
                      Die Fahrtrichtung ist abhängig vom Attribut 'pct100'.</li>
            <li>
                <a id="Shelly-set-zero"></a>
                <code>set &lt;name&gt; zero </code>
                <br />Den Shelly kalibrieren  </li>
            <li>
                <a id="Shelly-set-predefAttr"></a>
                <code>set &lt;name&gt; predefAttr</code>
                <br/>Setzen von vordefinierten Attributen: devStateIcon, cmdIcon, webCmd and eventMap
                <br/>Das Attribut 'pct100' muss bereits definiert sein
                <br/>Attribute werden nur gesetzt, wenn sie nicht bereits definiert sind
                </li>
        </ul>
        <br/>Für Shelly Dimmer Devices (model=shellydimmer oder model=shellyrgbw und mode=white)
        <ul>
            <li>
                <code>set &lt;name&gt; on|off|toggle  [&lt;channel&gt;] </code>
                <br />schaltet Kanal &lt;channel&gt; on oder off. </li>
            <li>
                <a id="Shelly-set-blink"></a>
                <code>set &lt;name&gt; blink &lt;count&gt; &lt;time&gt;  [&lt;channel&gt;] </code>
                <br />schaltet Kanal &lt;channel&gt; entsprechend Anzahl 'count' für Zeit 'time' ein und aus. </li>
            <li>
                <code>set &lt;name&gt; on-for-timer|off-for-timer &lt;time&gt; [&lt;channel&gt;] </code>
                <br />schaltet Kanal &lt;channel&gt; on oder off für &lt;time&gt; Sekunden. </li>

            <li>
                <a id="Shelly-set-pct"></a>
                <code>set &lt;name&gt; pct &lt;1...100&gt; [&lt;channel&gt;] </code>
                <br />Dimmer: Prozentualer Wert für die Helligkeit (brightness). 
                      Es wird nur der Helligkeitswert gesetzt ohne das Gerät ein oder aus zu schalten.                      
                <br />Rollo: Prozentualer Wert für die Position, siehe auch <code>set &lt;name&gt; pos &lt;integer percent value&gt; </code>. 
                      </li>
            <li>   <code>set &lt;name&gt; pct 0 [&lt;channel&gt;] </code>
                <br />Das Gerät/Kanal wird ausgeschaltet, der vorhandene Helligkeitswert bleibt unverändert.
                      </li>

            <li>
                <a id="Shelly-set-dim"></a>
                <code>set &lt;name&gt; dim &lt;0...100&gt;[:&lt;transition&gt;] [&lt;channel&gt;] </code>
                <br />Prozentualer Wert für die Helligkeit (brightness). Es wird der Helligkeitswert gesetzt und eingeschaltet.
                      Bei einem Helligkeitswert gleich 0 (Null) wird ausgeschaltet, der im Shelly gespeicherte Helligkeitswert bleibt unverändert.
                      Optional kann mit Doppelpunkt getrennt die Transit-Zeit 'transition' in Sekunden vorgegen werden.
                      </li>

            <li>
                <a id="Shelly-set-dimup"></a>
                <code>set &lt;name&gt; dimup [&lt;1...100&gt;][:&lt;transition&gt;] [&lt;channel&gt;] </code>
                <br />Prozentualer Wert für die Vergrößerung der Helligkeit.
                      Ist kein Wert angegeben, wird das Attribut dimstep ausgewertet.
                      Der größte erreichbare Helligkeitswert ist 100.
                      Ist das Gerät aus, ergibt sich der neue Helligkeitswert aus dem angegebenen Wert und das Gerät wird eingeschaltet.
                      Optional kann mit Doppelpunkt die Transit-Zeit 'transition' in Sekunden vorgegen werden.
                      </li>

            <li>
                <a id="Shelly-set-dimdown"></a>
                <code>set &lt;name&gt; dimdown [&lt;1...100&gt;][:&lt;transition&gt;] [&lt;channel&gt;] </code>
                <br />Prozentualer Wert für die Verringerung der Helligkeit.
                      Ist kein Wert angegeben, wird das Attribut dimstep ausgewertet.
                      Der kleinste erreichbare Helligkeitswert ist der im Shelly gespeicherte Wert für "minimum brightness".
                      Optional kann mit Doppelpunkt die Transit-Zeit 'transition' in Sekunden vorgegen werden.
                      </li>

            <li>
                <a id="Shelly-set-dim-for-timer"></a>
                <code>set &lt;name&gt; dim-for-timer &lt;brightness&gt;[:&lt;transition&gt;] &lt;time&gt; [&lt;channel&gt;] </code>
                <br />Wie <code>on-for-timer</code> mit zusätzlicher Angabe eines prozentualen Wertes 'brightness' für die Helligkeit.
                      Nach Ablauf der Zeit 'time' wird ausgeschaltet.
                      Optional kann mit Doppelpunkt die Transit-Zeit 'transition' in Sekunden vorgegen werden.
                      </li>

        </ul>
        <br/>
        Hinweis zu transition: Nur bei Gen2-Dimmern verfügbar.
                      Ist das Gerät eingeschaltet 'on', dann beginnt der Dimmvorgang beim aktuellen Helligkeitswert.
                      Bei ausgeschaltetem Gerät beginnt der Dimmvorgang bei 0.
        <br/>
        Hinweis für ShellyRGBW (white-Mode): Kanalnummern sind 0..3.
                      Wird keine Kanalnummer angegeben, wird der mit dem Attribut 'defchannel' definierte Kanal geschaltet.
        <br/>
        <br/>Für Shelly RGBW Devices (model=shellyrgbw und mode=color)
        <ul>
            <li>
               <code>set &lt;name&gt; on|off|toggle</code>
                <br />schaltet das Device &lt;channel&gt; on oder off</li>
            <li>
                <code>set &lt;name&gt; on-for-timer|off-for-timer &lt;time&gt;</code>
                <br />schaltet das Device für &lt;time&gt; Sekunden on oder off. </li>
            <li>
                <a id="Shelly-set-hsv"></a>
                <code>set &lt;name&gt; hsv &lt;hue value 0..360&gt;,&lt;saturation value 0..1&gt;,&lt;brightness value 0..1&gt; </code>
                <br />Komma separierte Liste von Farbton (hue), Sättigung (saturation) und Helligkeit zum Setzen der Lichtfarbe.
                Hinweis: ein Hue-Wert von 360° entspricht einem Hue-Wert von 0° = rot.
                Hue-Werte kleiner als 1 werden als Prozentwert von 360° gewertet, z.B. entspricht ein Hue-Wert von 0.5 einem Hue-Wert von 180°.</li>
            <li>
                <a id="Shelly-set-gain"></a>
                <code>set &lt;name&gt; gain &lt;integer&gt;</code>
                <br /> setzt die Verstärkung (Helligkeit) der Farbkanäle auf einen Wert 0..100</li>
            <li>
                <a id="Shelly-set-effect"></a>
                <code>set &lt;name&gt; effect &lt;Off|0|1|2|3&gt;</code>
                <br /> aktiviert einen Effekt (nur Farbkanäle): 1=Meteor Shower Farbwechsel 2=Gradual Change Farbwechsel 3=Flash Blitz</li>
                	1 ws bl vt rt ge gn ge
                	2 gn bl vt rt ge
            <li>
                <a id="Shelly-set-rgb"></a>
                <code>set &lt;name&gt; rgb &lt;rrggbb&gt; </code>
                <br />6-stelliger hexadezimal String zum Setzten der Farbe</li>
            <li>
                <a id="Shelly-set-rgbw"></a>
                <code>set &lt;name&gt; rgbw &lt;rrggbbww&gt; </code>
                <br />8-stelliger hexadezimal String zum Setzten der Farbe und des Weiß-Wertes</li>
            <li>
                <a id="Shelly-set-white"></a>
                <code>set &lt;name&gt; white &lt;integer&gt;</code>
                <br />setzt den Weiß-Wert auf einen Wert 0..100</li>
            </ul>

            <br/>Für Shelly Bulb duo:
            <ul>
                <li>
                <a id="Shelly-set-ct"></a>
                <code>set &lt;name&gt; ct &lt;integer&gt;</code>
                <br/>setzt die Farbtemperatur auf einen Wert 3000...6500 K</li>
            </ul>
            
            <br/> Für Shellies Gen2:
            <ul>
                <li>
                <a id="Shelly-set-actions"></a>
                <code>set &lt;name&gt; actions create|delete|disable|enable|update &lt;...&gt;</code>
                <br/>
                <br/><code>set &lt;name&gt; actions create info|&lt;index&gt;|all &nbsp;</code>
                                            Erstellen von Actions auf dem Shelly
                <br/><code>set &lt;name&gt; actions delete  &lt;id&gt;|own|all   &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</code>
                                            Löschen von Actions auf dem Shelly
                <br/><code>set &lt;name&gt; actions disable &lt;id&gt;  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;  </code>
                                            Deaktivieren einer Action auf dem Shelly
                <br/><code>set &lt;name&gt; actions enable  &lt;id&gt;  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; </code>
                                            Deaktivieren einer Action auf dem Shelly
                <br/><code>set &lt;name&gt; actions update  [&lt;id&gt;]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; </code>
                                            Aktualisieren aller/einer Action(s) auf dem Shelly
                </li>

                <li> create info:
                      Gibt eine Liste der verfügbaren Actions aus. Mit dem in der ersten Spalte aufgeführtem Index kann eine einzelne Action angelegt werden.</li>
                <li> create &lt;index&gt;:
                      Legte eine Action für das unter &lt;index&gt; angegebene Event auf dem Shelly an.</li>
                <li> create all:
                      Legt alle verfügbaren Actions mit an FHEM addressierten Webhooks auf dem Shelly an,
                      so dass der Shelly von sich aus Statusänderungen an FHEM sendet.
                      Voraussetzung ist, dass eine FHEMWEB-Instanz für das Ziel der Webhooks mittels des Attributes <code>webhook</code> definiert ist.
                      <br/>Hinweise:
                      <br/>Dezeit nur für Shellies der 2.Gen. verfügbar, Actions auf den Shellies der 1. Gen. müssen manuell angelegt werden.
                      <br/>Enthält das zugehörige FHEMWEB Device ein CSFR-Token, wird dies mit berücksichtigt.
                      <br/>Die Namen der Actions auf dem Shelly werden entsprechend der zugehörigen Events benannt,
                       zusätzlich mit einem vorangestellten und angehangenen Unterstrich (z.B. _COVER.STOPPED_). <br/></li>
                <li> delete id:
                      Die Action mit der ID &lt;id&gt; wird vom Shelly entfernt. <br/></li>
                <li> delete own:
                      Automatisch erstellte Actions zur eigenen FHEMWEB-Instanz (mit Unterstrich) auf dem Shelly werden entfernt. <br/></li>
                <li> delete all:
                      <b>Alle</b> actions auf dem Shelly werden entfernt. <br/></li>
                <li> disable id:
                      Die Action mit der ID &lt;id&gt; wird auf dem Shelly deaktiviert. <br/></li>
                <li> enable id:
                      Die Action mit der ID &lt;id&gt; wird auf dem Shelly aktiviert. <br/></li>
                <li> update:
                      Die automatisch erstellten 'eigenen' Actions auf dem Shelly werden aktualisiert.
                      Token werden vom Modul geprüft und die Webhooks auf dem Shelly werden gegenenfalls aktualisiert. <br/></li>
                <li> update id:
                      Wie 'update' jedoch wird nur die Action mit der ID &lt;id&gt; aktualisiert. <br/></li>
                <s>Actions mit bis zu fünf Webhooks werden unterstützt.
                   Webhooks, welche nicht an FHEM addressiert sind, werden von diesem Mechanismus nicht verändert.</s>
            </ul>

        
        <br/>Für Shelly Plug S|UK Gen2+ Zwischenstecker (model=shellyplusplug)
        <ul>
            <li>
                <a id="Shelly-set-colorsOn"></a>
                <a id="Shelly-set-colorsOff"></a>
                <code>set &lt;name&gt; colorsOn|colorsOff &lt;Rot&gt;,&lt;Grün&gt;,&lt;Blau&gt; [&lt;Helligkeit&gt;]</code><br/>
                <code>set &lt;name&gt; colorsOn|colorsOff &lt;RRGGBB&gt; [&lt;Helligkeit&gt;]</code><br/>
                <code>set &lt;name&gt; colorsOn|colorsOff &lt;Helligkeit&gt;</code><br/>
                <code>set &lt;name&gt; colorsOn|colorsOff power [&lt;Helligkeit&gt;]</code><br/>
                <code>set &lt;name&gt; colorsOn|colorsOff off</code>
                
                <br/>Einstellen der Farbe und Modus des Leuchtrings. 
                <br/>Rot, Grün, Blau: ganzzahlige Werte 0...100
                <br/>RRGGBB: 6-stelliger hexadezimal String für die Farben Rot, Grün und Blau, jeweils 00...FF
                <br/>Helligkeit: Werte 0...100
                <br/>power: Leistungsgesteuerter Modus
                <br/>off: Leuchtring ausgeschaltet (unabhängig von Schaltzustand oder Leistung)</li> 
                Hinweis: Hexadezimalwerte werden in Prozentwerte umgerechnet und mit drei Dezimalstellen an den Shelly übertragen.
        </ul>


            <br/>Für Shelly Devices mit Eingängen (model=...)
            <ul>
               <li>
               <code>set &lt;name&gt; input mode [channel]</code>
                <br/>ändert den Modus des Einganges [channel] zu &lt;mode&gt;</li>
            </ul>

            <br/>Für ShellyPro3EM / ShellyProEM50 (model=...)
            <ul>
               <li>
               <code>set &lt;name&gt; interval_power &lt;integer&gt;</code>
                <br/>setzt das Aktualisierungsintervall der Power-Readings zu &lt;integer&gt; Sekunden
                <br/>Standardwert ist das allgemeine Intervall.
                </li>
            </ul>

                <br/>
                <br/>Hinweise:
                <br/>Vor dem Löschen eines FHEM-Devices sollten die zugehörigen Actions auf dem Shelly entfernt werden.
                <br/>Alle mit dem Shelly-Modul durchführbaren Operationen können natürlich auch manuell über das GUI des Shelly durchgeführt werden.


        <a id="Shelly-get"></a>
        <h4>Get</h4>
        <ul>
            <li>
                <a id="Shelly-get-actions"></a>
                <code>get &lt;name&gt; actions</code>
                <br/>Erstellt eine Liste aller auf dem Shelly vorhandenen Actions
                <br/>Hinweis: zur besseren Lesbarkeit wird dabei <code>%20</code> durch das Blank-Symbol <code>&blank;</code> dargestellt
                </li>
            <li>
                <a id="Shelly-get-colors"></a>
                <code>get &lt;name&gt; colors</code>  
                <br/>nur für Shelly Plus Plug S
                <br/>schreibt die Einstellungen für die LEDS in das Reading "colors"
                <br/>schreibt die aktuelle Farbe der LEDS als sechstellige Hexadezimalzahl in das Reading "colorsRGB"
                </li>
            <li>
                <a id="Shelly-get-config"></a>
                <code>get &lt;name&gt; config [&lt;registername&gt;] [&lt;channel&gt;]</code>
                <br />Holt den Inhalt eines Konfigurationsregisters vom Shelly und schreibt das Ergebnis in das Reading 'config'.
                          Wird kein Registername angegeben, werden nur allgemeine Daten wie z.B. die SHELLYID abgelegt.</li>
            <li>
                <a id="Shelly-get-registers"></a>
                <code>get &lt;name&gt; registers</code>
                <br />Zeigt die Namen der verfügbaren Konfigurationsregister für dieses Device an. </li>
            <li>
                <a id="Shelly-get-status"></a>
                <code>get &lt;name&gt; status</code>
                <br />Aktualisiert den Gerätestatus.</li>
            <li>
                <a id="Shelly-get-settings"></a>
                <code>get &lt;name&gt; settings</code>
                <br />Aktualisiert die Systemdaten des Shelly. </li>
            <li>
                <a id="Shelly-get-model"></a>
                <code>get &lt;name&gt; model</code>
                <br />Ermittelt den Typ des Shelly und passt die Attribute an</li>
            <li>
                <a id="Shelly-get-readingsGroup"></a>
                <code>get &lt;name&gt; readingsGroup Device|Firmware|Network|Status</code>
                <br />Erstellt ein readingsGroup Device zur thematischen Darstellung aller Shellies</li>
            <li>
                <a id="Shelly-get-version"></a>
                <code>get &lt;name&gt; version</code>
                <br />Zeigt die Version des FHEM-Moduls an</li>            
        </ul>


        <a id="Shelly-attr"></a>
        <h4>Attribute</h4>
        <ul>
        <li>
                <a id="Shelly-attr-ShellyName"></a>
                <code>attr &lt;name&gt; name &lt;ShellyName&gt;</code>
                <br />Name des Shelly Devices.
                Wenn kein Name für den Shelly vergeben wurde oder wenn der Name auf der Website des Shelly gelöscht wird,
                wird der Shelly-Name entsprechend dem Namens des FHEM-Devices gesetzt.
                Der Shelly-Name darf Leerzeichen enthalten, leere Zeichenketten werden nicht akzeptiert.
                </li>

            <li>
                <a id="Shelly-attr-shellyuser"></a>
                <code>attr &lt;name&gt; shellyuser &lt;shellyuser&gt;</code>
                <br />Benutzername für den Zugang zur Website des Shelly.
                Das Passwort wird mit dem 'set ... password'-Befehl gesetzt.
                </li>
                Bei den Shellies der 2. Gen ist shellyuser=admin fest vorgegeben und kann nicht geändert werden.

            <li>
                <a id="Shelly-attr-model"></a>
                <code>attr &lt;name&gt; model &lt;model&gt; </code>
                <br />Type des Shelly Device. Wenn das Attribut model zu <i>generic</i> gesetzt wird, enthält das Device keine Aktoren,
                es ist dann nur ein Platzhalter für Readings.
                Hinweis: Dieses Attribut wird bei Definition automatisch ermittelt.</li>
            <li>
                <a id="Shelly-attr-mode"></a>
                <code>attr &lt;name&gt; mode relay|roller</code> (nur bei model=shelly2/2.5/plus2/pro2)
                <br />             <code>attr &lt;name&gt; mode white|color </code> (nur bei model=shellyrgbw)
                <br />Betriebsart bei bestimmten Shelly Devices</li>
                
                
            <li>
                <a id="Shelly-attr-host_dns"></a>
                <code>attr &lt;name&gt; host_dns &lt;dns-name&gt; </code> 
                <br/>DNS-Name des FHEM-Hosts
                <br/>Hinweis: wird bei Definition eines Devices vom System gesetzt
                </li>         
            <li>
                <a id="Shelly-attr-host_ip"></a>
                <code>attr &lt;name&gt; host_ip &lt;ip-address&gt; </code> 
                <br/>IP-Adresse des FHEM-Hosts 
                <br/>Beispiel: <code>attr meinShelly host_ip 192.168.178.200</code> 
                <br/>Hinweis: wird bei Definition eines Devices vom System gesetzt, sofern unterstützt
                </li>
                
             <li>
                <a id="Shelly-attr-interval"></a>
                <code>attr &lt;name&gt; interval &lt;interval&gt;</code>
                <br />Aktualisierungsinterval für das Polling der Daten vom Shelly.
                Der Default-Wert ist 60 Sekunden, ein Wert von 0 deaktiviert das automatische Polling.
                <br/></li>
             <li>
                <a id="Shelly-attr-interval_power"></a>
                <code>attr &lt;name&gt; interval_power &lt;interval&gt;</code>
                <br />Aktualisierungsinterval für das Polling der Leistungswerte von ShellyPro3EM / ShellyProEM50 Energiemessgeräten (i.W. Strom, Spannung, Leistung).
                Der Default-Wert ist das mit dem Attribut <code>interval</code> festgelegte Intervall. Minimalwert ist 1 sec.
                <br/>
                </li>
                <br/>Hinweise: 
                <br/>Wenn <code>interval_power</code> gesetzt ist, kann <code>interval</code> auf einen größeren Wert (z.B. 300 sec) gesetzt werden.
                <br/>Bei den ShellyPro3EM / ShellyProEM50 Energiemessgeräten werden die Energiewerte (und daraus rekursiv bestimmte Leistungswerte)
                alle 60 Sekunden oder einem Vielfachen davon gelesen.

             <li>
                <a id="Shelly-attr-maxAge"></a>
                <code>attr &lt;name&gt; maxAge &lt;seconds&gt;</code>
                <br/>Mit diesem Attribut kann bei einigen Readings die Auslösung eines Events bei Aktualisierung des Readings erzwungen werden,
                           auch wenn sich das Reading nicht geändert hat.
                Der Standardwert ist 2160000 Sekunden = 600 Stunden, Minimalwert ist das Pollingintervall.
                <br/>
                </li>
             <li>
                <code>attr &lt;name&gt; showinputs show|hide</code>
                <a id="Shelly-attr-showinputs"></a>
                <br />Das Attribut steuert die Berücksichtigung von Eingangssignalen an den Schalteingängen 'input' des Shelly.
                Der Status und die Betriebsart des Eingangs/der Eingänge werden als Reading dargestellt.
                In der Standardeinstellung werden die Readings angezeigt ('show').
                Dies ist besonders dann sinnvoll, wenn die Informationen zu den Eingängen vom Shelly via 'Shelly actions' (webhooks) vom Shelly gepusht werden.
                </li>
             <li>
                <a id="Shelly-attr-showunits"></a>
                <code>attr &lt;name&gt; showunits none|original|normal|normal2|ISO</code>
                <br />Anzeige der Einheiten in den Readings. Der Standardwert ist 'none' (keine Einheiten anzeigen).
                      Die Einheit für Energie können zwischen Wh, kWh und kJ gewählt werden.
                      <ul>
                <li><code>none</code>: empfohlen im Zusammenhang mit ShellyMonitor</li>
                <li><code>original</code>: Einheiten werden entsprechend dem Shelly-Device angezeigt
                                          (z.B. Wm (Wattminuten) für die meisten Devices der 1. Gen.)</li>
                <li><code>normal</code>: Energie wird als Wh (Wattstunde) ausgegeben</li>
                <li><code>normal2</code>: Energie wird als kWh (Kilowattstunde) ausgegeben</li>
                <li><code>ISO</code>: Energie wird als kJ (Kilojoule) ausgegeben</li>
                </ul>
                </li>
             <li>
                <a id="Shelly-attr-maxpower"></a>
                <code>attr &lt;name&gt; maxpower &lt;maxpower&gt;</code>
                <br />Leistungswert für den Überlastungsschutz des Shelly in Watt.
                Der Standardwert und der Einstellbereich wird vom Shelly-Device vorgegeben.
                </li>
             <li>
                <a id="Shelly-attr-timeout"></a>
                <code>attr &lt;name&gt; timeout &lt;seconds&gt;</code>
                <br />Zeitlimit für nichtblockierende Anfragen an den Shelly. Der Standardwert ist 4 Sekunden.
                Dieses Attribut sollte bei Timingproblemen ('connect to ... timed out' in der Logdatei) angepasst werden. 
                <br />Durch das Setzen dieses Attributs werden für die diversen Anfragen an den Shelly Readings (beginnend mit '/') 
                      mit Angaben der Reaktionszeit, 
                      der letzte Set-Befehl sowie die Zeitspanne bis zur nächsten Status-Aktualisierung geschrieben. 
                      Diese Readings werden durch Löschen des Attributes entfernt und 
                      mit <code>set &lt;name&gt; clear responsetimes</code> zurückgesetzt.
                </li>
             <li>
                <a id="Shelly-attr-webhook"></a>
                <code>attr &lt;name&gt; webhook &lt;FHEMWEB-device&gt; </code>
                <br />Auswahl der FHEMWEB-Instanz, für welche die Webhooks generiert werden (siehe <code>set &lt;name&gt; actions create</code>)
</li>
        </ul>
        <br/>Für Shelly Relais Devices (mode=relay für model=shelly2/2.5/plus2/pro2, Standard für alle anderen Relais Modelle)
        <ul>
            <li>
                <a id="Shelly-attr-defchannel"></a>
                <code>attr &lt;name&gt; defchannel &lt;integer&gt; </code>
                <br />nur für mehrkanalige Relais Modelle (z.B. model=shelly2|shelly2.5|shelly4) oder ShellyRGBW im 'white mode':
                Festlegen des zu schaltenden Kanals, wenn ein Befehl ohne Angabe einer Kanalnummer empfangen wird.
                </li>
        </ul>
        <br/>Für Shelly Dimmer Devices oder Shelly RGBW im White-Mode
        <ul>
            <li>
                <a id="Shelly-attr-dimstep"></a>
                <code>attr &lt;name&gt; dimstep &lt;integer&gt; </code>
                <br />nur für dimmbare Modelle (z.B. model=shellydimmer) oder ShellyRGBW im 'white mode':
                Festlegen der Schrittweite der Befehle dimup / dimdown. Default ist 25.
                </li>
        </ul>

        <br/>Für Shelly Rollladen Aktoren (mode=roller für model=shelly2/2.5/plus2/pro2)
        <ul>
            <li>
                <a id="Shelly-attr-maxtime"></a>
                <code>attr &lt;name&gt; maxtime &lt;int|float&gt; </code>
                <br/>Benötigte Zeit für das vollständige Öffnen oder Schließen</li>
            <li>
                <a id="Shelly-attr-maxtime_close"></a>
                     <code>attr &lt;name&gt; maxtime_close &lt;int&gt;   </code> Gen1
                <br/><code>attr &lt;name&gt; maxtime_close &lt;float&gt; </code> Gen2
                <br/>Benötigte Zeit für das vollständige Schließen</li>
            <li>
                <a id="Shelly-attr-maxtime_open"></a>
                     <code>attr &lt;name&gt; maxtime_open &lt;int&gt;   </code> Gen1
                <br/><code>attr &lt;name&gt; maxtime_open &lt;float&gt; </code> Gen2
                <br/>Benötigte Zeit für das vollständige Öffnen</li>
            <li>
                <a id="Shelly-attr-slat_control"></a>
                     <code>attr &lt;name&gt; slat_control enabled|disabled </code> 
                <br/>Status der Lamellensteuerung</li>
            <li>
                <a id="Shelly-attr-slat_pos"></a>
                     <code>attr &lt;name&gt; slat_pos &lt;0...100&gt;   </code>
                <br/>Prozentwert für die Steuerung der Lamellen</li>
            <li>
                <a id="Shelly-attr-pct100"></a>
                <code>attr &lt;name&gt; pct100 open|closed (default:open) </code>
                <br/>Festlegen der 100%-Endlage für Rollladen offen (pct100=open) oder Rollladen geschlossen (pct100=closed)</li>
        </ul>
        <br/>Für Energiemeter ShellyPro3EM / ShellyProEM50
        <ul>
            <li>
                <a id="Shelly-attr-Energymeter_P"></a>
                <code>attr &lt;name&gt; Energymeter_P &lt;float&gt; </code>
                <br />Anpassen des Zählerstandes an den Zähler des Netzbetreibers, für Zähler mit Rücklaufsperre bzw. für den Bezugszähler, in Wh (Wattstunden).
                <br />     Hinweis: Beim Anlegen des Attributes wird der Wert um den aktuellen Zählerstand reduziert</li>
            <li>
                <a id="Shelly-attr-Energymeter_R"></a>
                <code>attr &lt;name&gt; Energymeter_R &lt;float&gt; </code>
                <br />Anpassen des Zählerstandes an den Einspeisezähler des Netzbetreibers (Bidirectional meters only), in Wh (Wattstunden).
                <br />     Hinweis: Beim Anlegen des Attributes wird der Wert um den aktuellen Zählerstand reduziert</li>
            <li>
                <a id="Shelly-attr-Energymeter_F"></a>
                <code>attr &lt;name&gt; Energymeter_F &lt;float&gt; </code>
                <br />Anpassen des Zählerstandes an den Zähler des Netzbetreibers, für Zähler ohne Rücklaufsperre (Ferraris-Zähler), in Wh (Wattstunden).
                <br />     Hinweis: Beim Anlegen des Attributes wird der Wert um den aktuellen Zählerstand reduziert</li>
            <li>
                <a id="Shelly-attr-EMchannels"></a>
                <code>attr &lt;name&gt; EMchannels ABC_|L123_|_ABC|_L123 (default: _ABC) </code>
                <br/>Festlegung der Readingnamen mit Postfix oder Präfix
                <br/><font color="red">Achtung: Das Löschen oder Ändern dieses Attributes führt zum Löschen der zugehörigen Readings! </font></li>
            <li>
                <a id="Shelly-attr-Balancing"></a>
                <code>attr &lt;name&gt; Balancing [0|1] </code>
                <br/>Saldierung des Gesamtenergiedurchsatzes aktivieren/deaktivieren. Das Intervall-Attribut darf nicht größer als 20 sec sein.
                <br/> <font color="red">Achtung:
                    Das Deaktivieren des Attributes führt zum Löschen aller zugehörigen Readings _T!</font></li>
            <li>
                <a id="Shelly-attr-Periods"></a>
                <code>attr &lt;name&gt; Periods &lt;periodes&gt; </code>
                <br/>Komma getrennte Liste von Zeitspannen für die Berechnung von Energiedifferenzen (Energieverbrauch). 
                Die kleinste hier definierte Zeitspanne wird anstelle von Intervall für das Update der Energy-Readings genutzt.
                <br/>min:   Minute
                <br/>hourT: Zwölftelstunde (5 Minuten)
                <br/>hourQ: Viertelstunde (15 Minuten)
                <br/>hour:  Stunde
                <br/>dayQ:  Tagesviertel (6 Stunden)
                <br/>dayT:  Tagesdrittel (8 Stunden) beginnend um 06:00
                <br/>Week:  Woche
                <br/> <font color="red">Achtung:
                    Das Entfernen eines Eintrages dieser Liste oder Löschen des Attributes führt zum Löschen aller zugehörigen Readings!</font></li>
            <li>
                <a id="Shelly-attr-PeriodsCorr-F"></a>
                <code>attr &lt;name&gt; PeriodsCorr-F &lt;0.90 ... 1.10&gt; </code>
                <br/>Korrekturfaktor für die berechneten Energiedifferenzen in den durch das Attribut 'Periods' gewählten Zeitspannen
                </li>
        </ul>
        <br/>Standard Attribute
        <ul>
            <li><a href="#alias">   alias</a>,
                <a href="#comment"> comment</a>,
                <a href="#event-on-update-reading"> event-on-update-reading</a>,
                <a href="#event-on-change-reading"> event-on-change-reading</a>,
                <a href="#room">     room</a>,
                <a href="#eventMap"> eventMap</a>,
                <a href="#verbose">  verbose</a>,
                <a href="#webCmd">   webCmd</a>
            </li>
        </ul>

        <a id="Shelly-events"></a>
        <h4>Readings und erzeugte Events  (Auswahl)</h4>
        <ul>
           <h5>Webhooks </h5>
            <li>   <code>webhook_cnt active / controlled / total </code>
                   <br/>Anzahl der Action-URLs auf dem Shelly: 
                   <br/>    active: Anzahl der aktiven URLs (enabled)
                   <br/>    controlled: Anzahl der von dieser FHEM-Instanz kontrollierten URLs
                   <br/>    total: Gesamtzahl der URLs  </li>
            <li>   <code>webhook_ver</code>
                   <br/>latest revision number of shellies webhooks. </li>


           <h5>ShellyPlus and ShellyPro devices  </h5>

           <li>
                  indicating the configuration of Shellies hardware inputs
                  <br/>  <code>input_&lt;channel&gt;_mode</code>
                  <br/>  ShellyPlus/Pro2PM in relay mode:
                  <br/>		<code>button|switch straight|inverted follow|detached</code>
                  <br/>  ShellyPlus/Pro2PM in roller mode:
                  <br/>		<code>button|switch straight|inverted single|dual|detached normal|swapped</code>
                  <br/>  ShellyPlusI4:
                  <br/>		<code>button|switch straight|inverted</code>
                  <ul>
                  <li>   <code>button     </code>  input type: button attached to the Shelly </li>
                  <li>   <code>switch     </code>  input type: switch attached to the Shelly </li>
                  <li>   <code>straight   </code>  the input is not inverted </li>
                  <li>   <code>inverted   </code>  the input is inverted </li>
                  <li>   <code>single     </code>  control button mode: the roller is controlled by one input  * </li>
                  <li>   <code>dual       </code>  control button mode: the roller is controlled by two inputs * </li>
                  <li>   <code>follow     </code>  control button mode: the relay is controlled by the input  ** </li>
                  <li>   <code>detached   </code>  control button mode: the input is detached from the relay|roller  </li>
                  <li>   <code>normal     </code>  the inputs are not swapped * </li>
                  <li>   <code>swapped    </code>  the inputs are swapped * </li>
                  <br/>  * roller mode only   ** relay mode only
                  <br/>  <br/>
                  </ul>
                </li>

           <li>
                  indicating the reason for start or stop of the roller
                  <br/>  <code>start_reason, stop_reason</code>
                  <ul>
                  <li>   <code>button       </code>  button or switch attached to the Shelly </li>
                  <li>   <code>http         </code>  HTTP/URL eg Fhem </li>
                  <li>   <code>HTTP         </code>  Shelly-App </li>
                  <li>   <code>loopback     </code>  Shelly-App timer </li>
                  <li>   <code>limit_switch </code>  roller reaches upper or lower end </li>
                  <li>   <code>timeout      </code>  after given drive time (eg fhem) </li>
                  <li>   <code>WS_in	    </code>  Websocket </li>
                  <li>   <code>obstruction  </code>  Obstruction detection </li>
                  <li>   <code>overpower    </code> </li>
                  <li>   <code>overvoltage  </code> </li>
                  <li>   <code>overcurrent  </code> </li>
                  </ul>
                </li>



           <h5>ShellyPlusI4 </h5>

                  an input in mode 'button' has usually the state 'unknown'.
                  When activated, the input state is set to 'ON' for a short periode, independent from activation time.
                  The activation time and sequence is reprensented by the readings <code>input_&lt;ch&gt;_action</code> and <code>input_&lt;ch&gt;_actionS</code>,
                  which will act simultanously with following values:
                  <ul>
                  <li> S	single_push </li>
                  <li> SS 	double_push </li>
                  <li> SSS 	triple_push </li>
                  <li> L 	long_push </li>
                  </ul>

                  NOTE: the readings of an input in mode 'button' cannot actualized by polling.
                  It is necessary to set actions/webhooks on the Shelly!

                  <br/>
                  <br/> Webhooks on ShellyPlusI4
                  <br/> Webhooks generated by Fhem are named as follows:
                  <br/> Input mode 'switch'
                  <ul>
                  <li> _INPUT.TOGGLE_ON_  </li>
                  <li> _INPUT.TOGGLE_OFF_ </li>
                  </ul>

                  <br/>Input mode 'button'
                  <ul>
                  <li> _INPUT.BUTTON_PUSH_  </li>
                  <li> _INPUT.BUTTON_DOUBLEPUSH_  </li>
                  <li> _INPUT.BUTTON_TRIPLEPUSH   </li>_
                  <li> _INPUT.BUTTON_LONGPUSH_    </li>
                  </ul>


           <h5>ShellyPro3EM / ShellyProEM50 </h5>

           <h6>Power</h6>

           Power, Voltage, Current and Power-Factor are updated at the main interval, unless otherwise specified
            <li>
                <a name="Power"></a>Active Power
                <br/> <code>Active_Power_&lt;A|B|C|T&gt;</code>
                <br/> float values of the actual active power </li>
            <li>
                <a name="Calculated Power"></a>Calculated Active Power
                <br/> <code>Active_Power_calculated</code>
                <br/> float value, calculated from the difference of Shellies Total_Energy reading (updated each minute, or multiple)</li>
            <li>
                <a name="Integrated Power"></a>Integrated Active Power
                <br/> <code>Active_Power_integrated</code>
                <br/> float value, calculated from the integration of Shellies power readings (updated each minute, or multiple)</li>
            <li>
                <a name="Pushed Power"></a>Pushed Power
                <br/> <code>Active_Power_pushed_&lt;A|B|C|T&gt;</code>
                <br/> float values of the actual power pushed by the Shelly when the value of a phase differs at least 10% to the previous sent value
                       (update interval depends on load, possible minimum is 1 second)
                       Action on power-events on the Shelly must be enabled.
                       </li>
            <li>
                <a name="Apparent Power"></a>Apparent Power
                <br/> <code>Apparent_Power_&lt;A|B|C|T&gt;</code>
                <br/> float values of the actual apparent power </li>
            <li>
                <a name="Power"></a>Voltage, Current and Power-Factor
                <br/> <code>Voltage_&lt;A|B|C&gt;</code>
                <br/> <code>Current_&lt;A|B|C|T&gt;</code>
                <br/> <code>Power_Factor_&lt;A|B|C&gt;</code>
                <br/> float values of the actual voltage, current and power factor </li>

           <h6>Energy</h6>

                  Energy readings are updated each minute, or multiple.
                <br/> When the showunits attribute is set, the associated units (Wh, kWh, kJ) are appended to the values
            <li>
                <a name="Energy"></a>Active Energy
                <br/> <code>Purchased_Energy_&lt;A|B|C|T&gt;</code>
                <br/> <code>Returned_Energy_&lt;A|B|C|T&gt;</code>
                <br/> float values of the purchased or returned energy per phase and total </li>
            <li>
                <a name="Total_Energy&lt;period&gt;"></a>Total Active Energy
                <br/> <code>Total_Energy</code>
                <br/> float value of total purchased energy minus total returned energy
                <br/> A minus sign is indicating returned energy.
                <br/> The timestamp of the reading is set to the full minute, as this is Shellies time base.
                      Day and Week are based on GMT.
              </li>

            <li>
                <a name="Total_Energymeter&lt;type&gt;"></a>Energymeter
                <br/> <code>Total_Energymeter_&lt;F|P|R&gt;</code>
                <br/> float values of the purchased (P) or returned (R) energy displayed by the suppliers meter.
                      For Ferraris type meters (F), the returned energy is subtracted from the purchased energy </li>
            <li>
                <a name="Energy periods&lt;period&gt;"></a>Energy differences in a period of time
                <br/> <code>[measuredEnergy]_&lt;Min|QHour|Hour|Qday|TDay|Day|Week&gt;</code>
                <br/> float value of energy in a period of time (updated at the defined time interval).
                <ul>
                <li> QDay is a period of 6 hours, starting at 00:00. </li>
                <li> TDay is a period of 8 hours, starting at 06:00. </li>
                <li> Week is a period of 7 days, starting mondays at 00:00. </li>
                </ul>
              </li>

        </ul>
        </ul>
=end html_DE
=cut ($@)
