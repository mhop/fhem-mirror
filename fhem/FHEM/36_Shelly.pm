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


package main;

use strict;
use warnings;

use JSON; 
use HttpUtils;

use vars qw{%attr %defs};

use SetExtensions;

sub Log($$);
sub Shelly_Set ($@);

#-- globals on start
my $version = "5.21 21.03.2024";

my $defaultINTERVAL = 60;
my $secndIntervalMulti = 4;  # Multiplier for 'long update'

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

#-- Time slices in seconds for time zone Germany CET/CEST 
#              [offset dst==0, offset dst==1, periode length]
my %periods = ( 
   "min"    => [0,0,60],
   "hourQ"  => [0,0,900],	           # quarter of an hour
   "hour"   => [0,0,3600],
   "dayQ"   => [3600,7200,21600],          #  day quarter
   "dayT"   => [10800,14400,28800],        #  day third  =  3x8h:   06:00 -  14:00  -  22:00
   "day"    => [3600,7200,86400],
   "Week"   => [-342000,-338400,604800]    # offset=-4x24x3600 + 3600 + $isdst x 3600
);

my %attributes = (
  "multichannel"  => " defchannel",
  "roller"        => " pct100:open,closed maxtime maxtime_close maxtime_open",
  "dimmer"        => " dimstep",
  "input"         => " showinputs:show,hide",
  "emeter"        => " Energymeter_F Energymeter_P Energymeter_R EMchannels:ABC_,L123_,_ABC,_L123".
                     " Periods:multiple-strict,Week,day,dayT,dayQ,hour,hourQ,min".                 # @keys = keys %periods
                     " PeriodsCorr-F Balancing:0,1",
  "metering"      => " maxpower",
  "showunits"     => " showunits:none,original,normal,normal2,ISO"
);  

my %shelly_dropdowns = (
#-- these we may get on request
    "Gets"  => "status:noArg shelly_status:noArg registers:noArg config version:noArg model:noArg",
#-- these we may set
    "Shelly"=> "config interval password reboot:noArg update:noArg name reset:disconnects,energy",
    "Onoff" => " on off toggle on-for-timer off-for-timer",
    "Multi" => " ON:noArg OFF:noArg xtrachannels:noArg",
    "Rol"   => " closed open stop:noArg pct:slider,0,1,100 delta zero:noArg predefAttr:noArg",
    "RgbwW" => " pct dim dimup dimdown dim-for-timer",
    "BulbW" => " ct:colorpicker,CT,3000,10,6500 pct:slider,1,1,100",
    "RgbwC" => " rgbw rgb:colorpicker,HSV hsv white:slider,0,1,100 gain:slider,0,1,100"
);
## may be used for RgbwC:
##  "hsv:colorpicker,HSV" 
##  "rgb:colorpicker,RGB"
##  "white:colorpicker,BRI,0,1,255"

# Device model by https://kb.shelly.cloud/knowledge-base/
my %shelly_vendor_ids = (
    "SHSW-1"     => "shelly1",    # no power metering
    "SHSW-L"     => "shelly1L",   # with AC power metering
    "SHSW-PM"    => "shelly1pm",
    "SHSW-21"    => "shelly2",
    "SHSW-25"    => "shelly2.5",
    "SHSW-44"    => "shelly4",
    "SHDM-1"     => "shellydimmer", # Dimmer 1
    "SHDM-2"     => "shellydimmer", # Dimmer 2
    "SHIX3-1"    => "shellyi3",     # shelly ix-3
    "SHUNI-1"    => "shellyuni",
    "SHPLG2-1"   => "shellyplug",
    "SHPLG-S"    => "shellyplug",
    "SHEM"       => "shellyem",
    "SHEM-3"     => "shelly3em",
    "SHRGBW2"    => "shellyrgbw",
    "SHBLB-1"    => "shellybulb",   
    "SHBDUO-1"   => "shellybulb",  #shelly duo white
    "SHCB-1"     => "shellybulb",  # shelly duo color G10
    "SHVIN-1"    => "shellybulb",  # shelly vintage (white mode)
    "SHHT-1"     => "generic", # shelly t&h sensorOK
    "SHWT-1"     => "generic", # shelly flood sensor
    "SHSM-1"     => "generic", # shelly smoke sensor
    "SHMOS-01"   => "generic", # shelly motion sensor
    "SHMOS-02"   => "generic", # shelly motion sensor 2
    "SHGS-1"     => "generic", # shelly gas sensor
    "SHDW-1"     => "generic", # shelly door/window sensor
    "SHDW-2"     => "generic", # shelly door/window sensor 2
    "SHBTN-1"    => "generic", # shelly button 1
    "SHBTN-2"    => "generic", # shelly button 2
    "SHSEN-1"    => "generic", # shelly motion & ir-controller
    "SHSTRV-01"  => "generic", # shelly trv
    # 2nd Gen PLUS devices
    "SNPL-00110IT"  => "shellyplusplug", # italian style
    "SNPL-00112EU"  => "shellyplusplug", # german style
    "SNPL-10112EU"  => "shellyplusplug", # german style  V2
    "SNPL-00112UK"  => "shellyplusplug", # UK style
    "SNPL-00116US"  => "shellyplusplug", # US style
    "SNSW-001X16EU" => "shellyplus1",
    "SNSW-001P16EU" => "shellyplus1pm",
    "SNSW-002P16EU" => "shellyplus2pm",
    "SNSW-102P16EU" => "shellyplus2pm",   ## 102 ??
    "SNSN-0024X"    => "shellyplusi4",  # shelly plus i4 (AC)
    "SNSN-0D24X"    => "shellyplusi4",  # shelly plus i4 (DC)
    "SNSN-0013A"    => "generic",  # shelly plus ht temp&humidity sensor
    "SNDM-00100WW"  => "shellyplusdimmer", # 0-10V Dimmer
    # 2nd Gen PRO devices
    "SPSH-002PE16EU"  => "shellyprodual", # Shelly Pro Dual Cover PM
    "SPSW-001XE16EU"  => "shellypro1",
    "SPSW-201XE16EU"  => "shellypro1",    # Shelly Pro 1 v.1
    "SPSW-001PE16EU"  => "shellypro1pm",
    "SPSW-201PE16EU"  => "shellypro1pm",  # Shelly Pro 1PM v.1
    "SPSW-002XE16EU"  => "shellypro2",
    "SPSW-202XE16EU"  => "shellypro2",    # Shelly Pro 2 v.1
    "SPSW-002PE16EU"  => "shellypro2pm",
    "SPSW-202PE16EU"  => "shellypro2pm",  # Shelly Pro 2PM v.1
    "SPSW-003XE16EU"  => "shellypro3",
    "SPSW-004PE16EU"  => "shellypro4pm",  # Shelly Pro 4PM v1
    "SPSW-104PE16EU"  => "shellypro4pm",  # Shelly Pro 4PM v2
    "SPEM-002CEBEU50" => "shellyproem50", # Shelly Pro EM-50
    "SPEM-003CEBEU"   => "shellypro3em",  
    "SPEM-003CEBEU400"=> "shellypro3em",  # Shelly Pro 3EM-400
    # Mini Devices
    "SNSW-001X8EU"    => "shellyplus1",   # Shelly Plus 1 Mini
    "SNSW-001P8EU"    => "shellyplus1pm", # Shelly Plus 1 PM Mini
    "SNPM-001PCEU16"  => "shellypmmini",  # Shelly Plus PM Mini
    # Gen3 Devices
    "S3SW-001X8EU"    => "shellyplus1",   # Shelly 1 Mini Gen3
    "S3SW-001P8EU"    => "shellyplus1pm", # Shelly 1 PM Mini Gen3
    "S3PM-001PCEU16"  => "shellypmmini",  # Shelly PM Mini Gen3
    # Misc
    "SAWD-0A1XX10EU1" => "walldisplay1"
    );


my %shelly_models = (
    #(   0      1       2         3    4    5       6    7     8)
    #(relays,rollers,dimmers,  meters, NG,inputs,  res.,color,modes)
    "generic"       => [0,0,0, 0,0,0,  0,0,0],
    "shellyi3"      => [0,0,0, 0,0,3,  0,0,0],    # 3 inputs
    "shelly1"       => [1,0,0, 0,0,1,  0,0,0],    # not metering, only a power constant in older fw
    "shelly1L"      => [1,0,0, 1,0,1,  0,0,0],
    "shelly1pm"     => [1,0,0, 1,0,1,  0,0,0],
    "shelly2"       => [2,1,0, 1,0,2,  0,0,2],    # relay mode, roller mode 
    "shelly2.5"     => [2,1,0, 2,0,2,  0,0,2],    # relay mode, roller mode
    "shellyplug"    => [1,0,0, 1,0,-1, 0,0,0],    # shellyplug & shellyplugS;   no input, but a button which is only reachable via Action
    "shelly4"       => [4,0,0, 4,0,0,  0,0,0],    # shelly4pro;  inputs not provided by fw v1.6.6
    "shellyrgbw"    => [0,0,4, 4,0,1,  0,1,2],    # shellyrgbw2:  color mode, white mode; metering col 1 channel, white 4 channels
    "shellydimmer"  => [0,0,1, 1,0,2,  0,0,0],
    "shellyem"      => [1,0,0, 2,0,0,  0,0,0],    # with one control-relay, consumed energy in Wh
    "shelly3em"     => [1,0,0, 3,0,0,  0,0,0],    # with one control-relay, consumed energy in Wh
    "shellybulb"    => [0,0,1, 1,0,0,  0,1,2],    # shellybulb & shellybulbrgbw:  color mode, white mode;  metering is in any case 1 channel
    "shellyuni"     => [2,0,0, 0,0,2,  0,0,0],    # + analog dc voltage metering
    #-- 2nd generation devices
    "shellyplusplug"=> [1,0,0, 1,1,-1, 0,0,0],
    "shellypluspm"  => [0,0,0, 1,1,0,  0,0,0],
    "shellyplus1"   => [1,0,0, 0,1,1,  0,0,0],
    "shellyplus1pm" => [1,0,0, 1,1,1,  0,0,0],
    "shellyplus2pm" => [2,1,0, 2,1,2,  0,0,2],    # switch profile, cover profile
    "shellyplusdimmer"=>[0,0,1,0,1,2,  0,0,0],    # one instance of light, 0-10V output
    "shellyplusi4"  => [0,0,0, 0,1,4,  0,0,0],
    "shellypro1"    => [1,0,0, 0,1,2,  0,0,0],
    "shellypro1pm"  => [1,0,0, 1,1,2,  0,0,0],
    "shellypro2"    => [2,0,0, 0,1,2,  0,0,0],
    "shellypro2pm"  => [2,1,0, 2,1,2,  0,0,2],    # switch profile, cover profile
    "shellypro3"    => [3,0,0, 0,1,3,  0,0,0],    # 3 potential free contacts
    "shellypro4pm"  => [4,0,0, 4,1,4,  0,0,0],
    "shellyproem50" => [1,0,0, 1,1,0,  0,0,0],    # has two single-phase meter and one relay
    "shellypro3em"  => [0,0,0, 1,1,0,  0,0,0],    # has one (1) three-phase meter
    "shellyprodual" => [0,2,0, 4,1,4,  0,0,0],
    "shellypmmini"  => [0,0,0, 1,1,0,  0,0,0],    # similar to ShellyPlusPM
    "walldisplay1"  => [1,0,0, 0,2,1,  0,0,0]     # similar to ShellyPlus1PM
    );
    
my %shelly_events = (	# events, that can be used by webhooks; key is mode, value is shelly-event 
        #Gen1 devices
    "generic"       => [""],
    "shellyi3"      => ["btn_on_url","btn_off_url","shortpush_url","longpush_url",
                        "double_shortpush_url","triple_shortpush_url","shortpush_longpush_url","longpush_shortpush_url"],
    "shelly1"       => ["btn_on_url","btn_off_url","shortpush_url","longpush_url","out_on_url","out_off_url"],
    "shelly1L"      => [""],
    "shelly1pm"     => [""],
    "shelly2"       => [""], 
    "shelly2.5"     => [""],
    "shellyplug"    => ["btn_on_url","out_on_url","out_off_url"],
    "shelly4"       => [""],
    "shellyrgbw"    => ["longpush_url","shortpush_url"],
    "shellydimmer"  => ["btn1_on_url","btn1_off_url","btn1_shortpush_url","btn1_longpush_url",
                        "btn2_on_url","btn2_off_url","btn2_shortpush_url","btn2_longpush_url"],
    "shellyem"      => ["out_on_url","out_off_url","over_power_url","under_power_url"],
    "shelly3em"     => [""],
    "shellybulb"    => ["out_on_url","out_off_url"],
    "shellyuni"     => ["btn_on_url","btn_off_url","shortpush_url","longpush_url","out_on_url","out_off_url","adc_over_url","adc_under_url"], 
        #Gen2 components; event given as key 'event' by rpc/Webhook.List
    "relay"   => ["switch.on", "switch.off"],   # events of the switch component
    "roller"  => ["cover.stopped","cover.opening","cover.closing","cover.open","cover.closed"],
    "switch"  => ["input.toggle_on","input.toggle_off"],    # for input instances of type switch
    "button"  => ["input.button_push","input.button_longpush","input.button_doublepush","input.button_triplepush"],    # for input instances of type button
    "emeter"  => ["em.active_power_change","em.voltage_change","em.current_change"],
    "pm1"     => ["pm1.apower_change","pm1.voltage_change","pm1.current_change"],
    "touch"   => ["input.touch_swipe_up","input.touch_swipe_down","input.touch_multi_touch"],
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
        #emeter
        "em.active_power_change"  => "Active_Power",
        "em.voltage_change"       => "Voltage",
        "em.current_change"       => "Current",
        #mini-emeter (shellypmmini)
        "pm1.apower_change"       => "power",
        "pm1.voltage_change"      => "voltage",
        "pm1.current_change"      => "current",
        #addon
        "temperature.measurement" => "tempC",
        "temperature.change"      => "tempC",
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
      "roller_webCmd"    => "open:up:down:closed:half:stop:position",
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
     "power"         => [""," W"],     # Wirkleistung
     "reactivepower" => [""," var"],   # Blindleistung
     "apparentpower" => [""," VA"],    # Scheinleistung				
     "energy"        => [""," Wh"],    # Arbeit; 
     "frequency"     => [""," Hz"],
     "tempC"         => [""," °C"],    # Celsius
     "relHumidity"   => [""," %"],
     "pct"           => [""," %"],
     "illum"         => [""," lux"],   # illuminace eg WallDisplay
     "ct"            => [""," K"],     # color temperature / Kelvin
     "rssi"          => [""," dBm"]    # deziBel Miniwatt
     );
     
 my %energy_units  = ( #si, faktor, decimals
     "none"       => [ "Wh", 1,     0 ],
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


     
########################################################################################
#
# Shelly_Initialize
#
# Parameter hash
#
########################################################################################

sub Shelly_Initialize ($) {
  my ($hash) = @_;#Debug "running Shelly_Initialize";
  
  $hash->{DefFn}    = "Shelly_Define";
  $hash->{UndefFn}  = "Shelly_Undef";
  $hash->{DeleteFn} = "Shelly_Delete";
  $hash->{AttrFn}   = "Shelly_Attr";
  $hash->{GetFn}    = "Shelly_Get";
  $hash->{SetFn}    = "Shelly_Set";
  $hash->{RenameFn} = "Shelly_Rename";

  $hash->{AttrList}= "model:".join(",",(sort keys %shelly_models)).
                     " maxAge".
                     " ShellyName".
                     " mode:relay,roller,white,color".
                     " interval timeout shellyuser".
                     $attributes{'multichannel'}.
                     $attributes{'roller'}.
                     $attributes{'dimmer'}.
                     $attributes{'input'}.
                     $attributes{'metering'}.
                     $attributes{'showunits'}.
                     " webhook:none,".join(",",devspec2array('TYPE=FHEMWEB:FILTER=TEMPORARY!=1')).
                     $attributes{'emeter'}.
                     " verbose:0,1,2,3,4,5".
                     " ".$readingFnAttributes;
}

########################################################################################
#
# Shelly_Define - Implements DefFn function
#
# Parameter hash, definition string
#
########################################################################################

sub Shelly_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name=$hash->{NAME};#Debug "running Shelly_Define for $name";

  return "[Shelly_Define] $name: Define the IP address of the Shelly device as a parameter"
    if(@a != 3);
  return "[Shelly_Define] $name: invalid IP address ".$a[2]." of Shelly"
    if( $a[2] !~ m|\d\d?\d?\.\d\d?\d?\.\d\d?\d?\.\d\d?\d?(\:\d+)?| );
  
  my $dev = $a[2];
  $hash->{TCPIP} = $dev;
  $hash->{INTERVAL} = AttrVal($hash->{NAME},"interval",$defaultINTERVAL); # Updates each minute, if not set as attribute
  
  # use hidden AttrList to make attributes changeable by Shelly_Attr()
  $hash->{'.AttrList'} = $modules{Shelly}{'AttrList'};
  
  $modules{Shelly}{defptr}{$a[0]} = $hash;
  
  #-- InternalTimer blocks if init_done is not true
  my $oid = $init_done;
  $init_done = 1;
  
  Log3 $name,4,"[Shelly_Define] $name: setting internal timer to get status of device";
  # try to get model and mode, adapt attr-list
  # Note: to have access to the attributes, we have to finish Shelly_Define first
  my $now=time();
  InternalTimer($now+4+rand(4), "Shelly_get_model", $hash);
  # check / change CSRF-Token
  InternalTimer($now+8+rand(10),"Shelly_actionCheck", $hash); #calling only on restart 
  
  #-- perform status update etc. at a slightly random interval
  InternalTimer($now+18+rand(4), "Shelly_status", $hash);
  InternalTimer($now+22+rand(4), "Shelly_EMData", $hash);
  InternalTimer($now+26+rand(4), "Shelly_shelly", $hash);    
  $init_done = $oid;

  if( defined(AttrVal($name,"ShellyName",undef)) ){
      fhem("deleteattr $name ShellyName");
      Log3 $hash->{NAME},1,"[Shelly_Define] $name: Attribut \'ShellyName\' removed. Use \'set $name <Name>\' instead";
  }
  return undef;
} # end Shelly_Define()


########################################################################################
# 
# Shelly_get_model - try to get type/vendor_id (model) and mode (if given) from device 
#                 adapt AttrList to the model
#                 acts as callable program Shelly_get_model($hash)
#                 and as callback program  Shelly_get_model($hash,$err,$data)
# 
# Parameter hash, error, data
#
########################################################################################
sub Shelly_get_model {
  my ($hash, $count, $err, $data) = @_;
  my $name  = $hash->{NAME};
  if( AttrVal($name,"model",undef) ){
       Log3 $name,5,"[Shelly_get_model] $name: model almost identified, aborting successful";#5
       return "model almost identified";
  }
  # a counter to prevent endless looping in case Shelly does not answer or the answering device is not a Shelly
  $count=1 if( !$count );
  if($count>3){  
       Shelly_error_handling($hash,"Shelly_get_model", "aborted: cannot get model for device \'$name\'");
       return;
  }
  if( $hash && !$err && !$data ){
    my $creds = Shelly_pwd($hash); 
    my $url = "http://$creds".$hash->{TCPIP};
    #-- try to get type/model and profile/mode of Shelly -  first gen
    Log3 $name,4,"[Shelly_get_model] try to get model for device $name as first gen";
    Log3 $name,5,"[Shelly_get_model] issue a non blocking call: $url/settings";
    HttpUtils_NonblockingGet({
        url      => $url."/settings",
        timeout  => 4,
        callback => sub($$$$){ Shelly_get_model($hash,$count,$_[1],$_[2]) }
    });
    $count++;
    #-- try to get type/model and profile/mode of Shelly -  second gen
    Log3 $name,4,"[Shelly_get_model] try to get model for device $name as second gen";
    Log3 $name,5,"[Shelly_get_model] issue a non blocking call: $url/rpc/Shelly.GetDeviceInfo";
    HttpUtils_NonblockingGet({
        url      => $url."/rpc/Shelly.GetDeviceInfo",
        timeout  => 4,
        callback => sub($$$$){ Shelly_get_model($hash,$count,$_[1],$_[2]) }
    });
    $count++;
    return "wait until browser refresh"; 
  }
  
  if( $hash && $err && AttrVal($name,"model","undef") eq "undef" ){
       $err = "searching" if( $err =~ /JSON/ );
       Shelly_error_handling($hash,"Shelly_get_model",$err);
       return;
  }
  
  my ($json,$jhash);  
  if( $hash && $data ){
    Log3 $name,4,"[Shelly_get_model] $name: received ".length($data)." byte of data from device";
    Log3 $name,5,"[Shelly_get_model] $name: received data is: \n$data ";
  
    if( $data eq "Not Found" ){         
      # when checking out Shellies software generation, this is intentionally no error
      Log3 $name,5,"[Shelly_get_model] no endpoint found for URL on device $name";
      return $data;
    }

    $json = JSON->new->utf8;
    $jhash = eval{ $json->decode( $data ) };
    if( !$jhash ){
      Log3 $name,1,"[Shelly_get_model] standard decoding: has invalid JSON data for device $name";
      $json = JSON->new->utf8->relaxed;
      $jhash = eval{ $json->decode( $data ) };
      if( !$jhash ){
          Shelly_error_handling($hash,"Shelly_get_model","relaxed decoding: invalid JSON data, try to call /shelly");
          HttpUtils_NonblockingGet({
              url      => "http://".Shelly_pwd($hash).$hash->{TCPIP}."/shelly",
              timeout  => 4,
              callback => sub($$$$){ Shelly_get_model($hash,$count,$_[1],$_[2]) }
          });
          $count++;
          return;
      }else{
          Log3 $name,1,"[Shelly_get_model] decoded JSON with relaxed decoding for device $name";
      }
    }
  }
if(0){
  # get Shellies Name either from the /settings call or from the /rpc/Shelly.GetDeviceInfo call
  if( defined($jhash->{'name'}) ){ #ShellyName
      ##fhem("set $name name " . $jhash->{'name'} );
      $attr{$hash->{NAME}}{ShellyName} = $jhash->{'name'};
  }else{ 
      # if Shelly is not named, set name of Shelly equal to name of Fhem-device
      ##fhem("set $name name " . $name ); 
      $attr{$hash->{NAME}}{ShellyName} = $name; 
  }    
}        
  my ($model,$mode);
       
  #-- for all 1st gen models get type (vendor_id) and mode from the /settings call  
  if( $jhash->{'device'}{'type'} ){ 
        # set the type / vendor-id as internal
        $hash->{SHELLY}=$jhash->{'device'}{'type'};
        # get mode, only multi-mode devices
        if( $jhash->{'mode'} ){
           $mode = $jhash->{'mode'};
           Log3 $name,1,"[Shelly_get_model] the attribute \'mode\' of device $name is set to \'$mode\' ";
           $attr{$hash->{NAME}}{mode} = $mode; # _Attr
        }
  #-- for some 1st gen models get type (vendor_id), from the /shelly call  
  }elsif( $jhash->{'type'} ){ 
        # set the type / vendor-id as internal
        $hash->{SHELLY}=$jhash->{'type'};
  
  #-- for all 2nd gen models get type (vendor_id) and mode from the /rpc/Shelly.GetDeviceInfo call
  }elsif( $jhash->{'model'} ){ # 2nd-Gen-Device
        # set the type / vendor-id as internal
        $hash->{SHELLY}=$jhash->{'model'}; 
        if( $jhash->{'profile'} ){
           $mode = $jhash->{'profile'};
           Log3 $name,5,"[Shelly_get_model] $name is of 2nd-gen profile \'$mode\'";
           $mode =~ s/switch/relay/;  # we use 1st-Gen modes
           $mode =~ s/cover/roller/;
           Log3 $name,1,"[Shelly_get_model] the attribute \'mode\' of device $name is set to \'$mode\' ";
           $attr{$hash->{NAME}}{mode} = $mode; # _Attr
        }
  }elsif( 0 && AttrVal($name,"model","generic") ne "generic"){
        $model = AttrVal($name,"model","generic");
        $mode  = AttrVal($name,"mode",undef) if( AttrVal($name,"mode",undef) );
        Log3 $name,5,"[Shelly_get_model] $name has existing definiton for model=$model".($mode?" and mode=$mode":"");
  }else{ #type not detected
        Log3 $name,2,"[Shelly_get_model] Unsuccessful: Got no \'type\' (Vendor-ID) for device $name, proposed model is \'generic\'";
        readingsSingleUpdate($hash,"state","type (Vendor-ID) not detected",1);
  }
  
  if( $hash->{SHELLY} ){
        Log3 $name,2,"[Shelly_get_model] device $name is of type ".$hash->{SHELLY};
        $model = $shelly_vendor_ids{$hash->{'SHELLY'}};
        if ( $model ){
            Log3 $name,2,"[Shelly_get_model] discovered model=$model for device $name";
        }else{
            Log3 $name,2,"[Shelly_get_model] device $name is of type \'".$hash->{SHELLY}."\' but we have no key of that name, proposed model is \'generic\'";
            readingsSingleUpdate($hash,"state","type key not found, set to \"generic\" ",1);
            $model = "generic";
        }
  }else{
        Log3 $name,2,"[Shelly_get_model] type not found, proposed model of device $name is \'generic\'";
        $hash->{SHELLY} = "unknown";
        $model = "generic";
  }


  if( defined($attr{$name}{model}) ){
        my $model_old = $attr{$name}{model};
        if( $model_old eq "generic" && $model ne "generic" ){
            Log3 $name,2,"[Shelly_get_model] the model of device $name is already defined as generic, and will be redefined as \'$model\' ";    
            $attr{$hash->{NAME}}{model} = $model;
        }else{
            Log3 $name,2,"[Shelly_get_model] the model of device $name is already defined as \'$model_old\' ";
            readingsSingleUpdate($hash,"state","model already defined as \'$model_old\', might be $model",1);
        }
  }else{
        # set the model-attribute when the model attribute is not set yet     
        $attr{$hash->{NAME}}{model} = $model; # _Attr
        Log3 $name,1,"[Shelly_get_model] the attribute \'model\' of device $name is set to \'$model\' ";
        Shelly_Attr("set",$name,"model",$model,undef);
  }
    
  ######################################################################################

    readingsSingleUpdate($hash,"state","initialized",1);
    InternalTimer(time()+6, "Refresh", $hash);
    delete($attr{$hash->{NAME}}{mode}) if( $shelly_models{$model}[8]<2 );  # no multi-mode device 
    delete($hash->{helper}{Sets}); # build up the sets-dropdown with next refresh
    return;
} #end Shelly_get_model

sub Refresh {    ##see also forum topic 48736.0
    Log3 undef,1,"perform a browser refresh";
    fhem("trigger $FW_wname JS:location.reload(true)");  # try a browser refresh ??
}

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
  return undef;
}

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
}

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
}

#######################################################################################
#
# Shelly_Attr - Set one attribute value
#
# Note: the 'model' and 'mode' attributes are also set by Shelly_get_model()
#
########################################################################################

sub Shelly_Attr(@) {
  my ($cmd,$name,$attrName, $attrVal, $RR) = @_;
  
  my $hash = $main::defs{$name};
  my $error; # will be set to a message string in case of error
  my $regex;  
  
  my $model =  AttrVal($name,"model","generic");
  my $mode  =  AttrVal($name,"mode","");
  Log3 $name,4,"[Shelly_Attr] $name: called with command $cmd for attribute $attrName".(defined($attrVal)?", value=$attrVal":"")." init=$init_done";#5
  
  #---------------------------------------  
  if( $cmd eq "set" && $attrName eq "model" ){
    $regex = "((".join(")|(",(keys %shelly_models))."))";
    if( $attrVal !~ /$regex/ && $init_done ){
      $error = "Wrong value of model attribute, see documentation for possible values";
      Log3 $name,1,"[Shelly_Attr] $name\: $error ";
      return $error;
    }
    #++++++++
      
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

    if( $attrVal eq "shellypro3em" ){
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
          $hash->{'.AttrList'} =~ s/$attributes{'emeter'}/" Periods:multiple-strict,Week,day,dayT,dayQ,hour,hourQ,min"/e; #allow Periods attribute
    }else{
          $hash->{'.AttrList'} =~ s/$attributes{'emeter'}/""/e;
    }
    
    if( $shelly_models{$attrVal}[1]==0 ){  #no roller
          $hash->{'.AttrList'} =~ s/$attributes{'roller'}/""/e;
          delete $hash->{MOVING}; # ?really necessary?
    }

    if( $shelly_models{$attrVal}[3]==0 ){  #no metering, eg. shellyi3  but we have units for RSSI
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

    if( $shelly_models{$attrVal}[4]==0 && $attrVal ne "shellybulb" ){  # 1st Gen 
          $hash->{'.AttrList'} =~ s/webhook(\S*?)\s//g;
    }
    Log3 $name,5,"[Shelly_Attr] $name ($attrVal) has new attrList \n".$hash->{'.AttrList'}; #5
    
    # delete some readings------------------------
    if( $attrVal =~ /shelly.*/ ){
      #-- only one relay
      if( $shelly_models{$attrVal}[0] == 1){
        fhem("deletereading $name relay_.*");
        fhem("deletereading $name overpower_.*");  
        fhem("deletereading $name button_.*"); 
      #-- no relay
      }elsif( $shelly_models{$attrVal}[0] == 0){
        fhem("deletereading $name relay.*");
        fhem("deletereading $name overpower.*");  
        fhem("deletereading $name button.*"); 
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
        fhem("deletereading $name position.*");
        fhem("deletereading $name stop_reason.*");
        fhem("deletereading $name last_dir.*");
        fhem("deletereading $name pct.*");
        delete $hash->{MOVING};
        delete $hash->{DURATION};
      }
      #-- no dimmers
      if( $shelly_models{$attrVal}[2] == 0){
        fhem("deletereading $name L-.*");
        fhem("deletereading $name rgb");
        fhem("deletereading $name pct.*");
      }

      #-- always clear readings for meters
      fhem("deletereading $name power.*");
      fhem("deletereading $name energy.*");
      fhem("deletereading $name overpower.*");
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
        $error="Wrong mode $attrVal for this device, must be relay or roller ";
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
    if( $shelly_models{$model}[4]==0 ){ #1st Gen
        Shelly_configure($hash,"settings?mode=$attrVal");
    }else{ #2ndGen  %26 =    %22  "
        Shelly_configure($hash,"rpc/Sys.SetConfig?config={%22device%22:{%22profile%22:$attrVal}}");
    }
    delete $hash->{MOVING}      if( $attrVal ne "roller" ); # ?necessary?
  # mode/ 
  
  #---------------------------------------  
  }elsif( $attrName =~ /showunits/ ){
    if( $cmd eq "set"  && $attrVal ne "none" ){
        $hash->{units}=1;
    }else{
        $hash->{units}=0;
    }
    
  #---------------------------------------  
  #}elsif ( $cmd eq "del" && ($attrName =~ /showunits/) ) {
  #  $hash->{units}=0;

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
    if( $model ne "shellypro3em" && $model ne "shellypmmini"){
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
      foreach $key ( @keys ){#Debug $key;
           if( $key !~ /(_c)$/ ){#Debug $key."-".$periods{$key}[0];
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
#  }elsif( $init_done == 0 ){
#       return undef;
       
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
  }elsif(0&& ($cmd eq "set" ) && ($attrName =~ /ShellyName/) ) {
    #$attrVal="" if( $cmd eq "del" ); #cannot set name to empty string
    if ( $attrVal =~ " " ){ #spaces not allowed in urls
        $attrVal =~ s/ /%20/g;
    }    
    if ($shelly_models{$model}[4]==0 ){ #1st Gen
        Shelly_configure($hash,"settings?name=$attrVal");
    }else{
        Shelly_configure($hash,"rpc/Sys.SetConfig?config={%22device%22:{%22name%22:%22$attrVal%22}}");
        #                                                 {"device"   :{"  name"  :"attrVal"}}
    }
    
  #---------------------------------------  
  }elsif( ($cmd eq "set" ) && ($attrName =~ /showinputs/) && $attrVal ne "show" ) {
     fhem("deletereading $name input.*");
     fhem("deletereading $name button.*");
  
  #---------------------------------------  
  }elsif( $cmd eq "del" && ($attrName =~ /showinputs/) ) {
     fhem("deletereading $name input.*");
     fhem("deletereading $name button.*");
   
  #---------------------------------------  
  }elsif( $cmd eq "set" && $attrName eq "maxpower" ){
    if( $shelly_models{$model}[3] == 0 ){
      $error="Setting the maxpower attribute for this device is not possible";
      Log3 $name,1,"[Shelly_Attr] $name\: $error";
      return $error;
    }
    if( $attrVal<1 || $attrVal>3500 ){
      $error="Maxpower must be within the range 1...3500 Watt";
      Log3 $name,1,"[Shelly_Attr] $name\: $error";
      return $error;
    }
    if($shelly_models{$model}[4]==0 ){ #1st Gen
        Shelly_configure($hash,"settings?max_power=".$attrVal);
    }elsif( $mode eq "roller" ){ #2ndGen  %26 =    %22  "
        Shelly_configure($hash,"rpc/Cover.SetConfig?id=0&config={%22power_limit%22:$attrVal}");
    }else{
      Log3 $name,1,"[Shelly_Attr] $name\: have not set $attrVal (L 744)";   
    }

  #---------------------------------------  
  }elsif( ($cmd eq "set") && ($attrName =~ /maxtime/) ) {
    if( ($shelly_models{$model}[1] == 0 || $mode ne "roller" ) && $init_done ){
      $error="Setting the maxtime attribute only works for devices in roller mode";
      Log3 $name,1,"[Shelly_Attr] $name\: $error model=shelly2/2.5/plus2/pro2 and mode=roller"; 
      return $error;
    }
    if($shelly_models{$model}[4]==0 ){ #1st Gen
        Shelly_configure($hash,"settings/roller/0?$attrName=".int($attrVal));
    }else{ #2nd Gen  %26 =    %22  "
        Shelly_configure($hash,"rpc/Cover.SetConfig?id=0&config={%22$attrName%22:$attrVal}");
      # Shelly_configure($hash,"rpc/Cover.SetConfig?id=0&config={%22maxtime_open%22:$attrVal}");
      # Shelly_configure($hash,"rpc/Cover.SetConfig?id=0&config={%22maxtime_close%22:$attrVal}");
    }    
    
  #---------------------------------------        
  }elsif( $cmd eq "set" && $attrName eq "pct100" ){
    if( ($shelly_models{$model}[1] == 0 || $mode ne "roller") && $init_done ){
      $error="Setting the pct100 attribute only works for devices in roller mode";
      Log3 $name,1,"[Shelly_Attr] $name\: $error model=shelly2/2.5/plus2/pro2 and mode=roller";  ##R
      return $error;
    }
    if($init_done){
      # perform an update of the position related readings
      RemoveInternalTimer($hash,"Shelly_status");
      InternalTimer(time()+1, "Shelly_status", $hash);  ##ü      
    }
  #---------------------------------------        
  }elsif( $attrName =~ /Energymeter/ ){
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
      $_[3] = $attrVal - $hash->{helper}{$attrName};
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
    if( $model ne "shellypro3em" && $init_done){
      $error="Setting of the attribute \"$attrName\" only works for ShellyPro3EM";
      Log3 $name,1,"[Shelly_Attr] $name\: $error ";
      return $error;
    }
    if( AttrVal($name,"interval",60)>20 && $init_done ){
      $error="For using the \"$attrName\" the interval must not exceed 20 seconds";
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
    if( $model ne "shellypro3em" && $model ne "shellypmmini" && $init_done ){
      $error="Setting of the attribute \"$attrName\" only works for ShellyPro3EM / ShellyPMmini";
      Log3 $name,1,"[Shelly_Attr] $name\: $error ";
      return $error;
    }
    my $RP; # Readings-postfix
    my @keys = keys %periods;   #"min","hourQ","hour","dayQ","dayT","day","Week" 
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
          #Debug "$rp :: $av ::: ".$AV;
          if( $av !~ /$rp/ && $AV =~ /$rp/){
              fhem("deletereading $name .*_$RP");
              Log3 $name,1,"[Shelly_Attr] deleted readings $name\:.*_$RP ";
          }
          # check if attrVal is not existing in the attribute -> new
          if( $av =~ /$rp/ && $AV !~ /$rp/ ){
              my $energy;
              my $factor=$energy_units{AttrVal($name,"showunits","none")}[1];  # normalize readings values to "Wh"
              my @readings = ("energy"); 
              if( $model eq "shellypro3em" ){    
                  @readings = ("Purchased_Energy_S","Returned_Energy_S","Total_Energy_S"); 
                  push( @readings,"Purchased_Energy_T","Returned_Energy_T","Total_Energy_T" ) if(AttrVal($name,"Balancing",1) == 1);
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
     if( $init_done==0 ){        return;  #<<<<<<<<<<< calling "check" is done by Shelly_Define()
         Log3 $name,3,"[Shelly_Attr:webhook] $name: check webhooks on start of fhem";
         $hash->{CMD}="Check";
     }elsif( $cmd eq "del" ){          
         Log3 $name,3,"[Shelly_Attr:webhook] $name: delete all hooks forwarding to this host and name starts with _";
         # Delete all webhooks to fhem
         $hash->{CMD}="Delete"; 
     }else{  #processing set commands, and init is done
       Log3 $name,3,"[Shelly_Attr:webhook] $name command is $cmd, attribute webhook old: ".AttrVal($name,"webhook","NoVal")."  new: $attrVal";
       if( $shelly_models{$model}[4]==0 && $init_done && $model ne "shellybulb" ){  # only for 2nd-Generation devices
         $error="Setting the webhook attribute only works for 2nd-Generation devices";
         Log3 $name,3,"[Shelly_Attr:webhook]  device $name is a $model. $error.";  
         return $error;
       }elsif( $attrVal eq "none" ){ 
         Log3 $name,3,"[Shelly_Attr:webhook] delete all hooks forwarding to this host and name starts with _";
         # Delete all webhooks to fhem
         $hash->{CMD}="Delete"; 
       }elsif(AttrVal($name,"webhook","none") eq $attrVal ){
         Log3 $name,3,"[Shelly_Attr:webhook] the webhook attribute for device $name remains unchanged to $attrVal";
         # no change, do nothing ..., but check
         $hash->{CMD}="Check"; 
       }elsif( AttrVal($name,"webhook","none") eq "none" ){
         Log3 $name,3,"[Shelly_Attr:webhook] the webhook attribute is now $attrVal, create webhooks";
         # Create webhooks
         $hash->{CMD}="Create";
       }else{
         Log3 $name,3,"[Shelly_Attr:webhook] changing the webhook attribute for device $name to $attrVal";
         # do an update
         $hash->{CMD}="Check";  
       }
     }
     if( $hash->{INTERVAL} != 0 ){    
       # calling Shelly_webhook() via timer, otherwise settings are not available
       Log3 $name,3,"[Shelly_Attr:webhook] we will call Shelly_webhook for device $name, command is ".$hash->{CMD}; 
       RemoveInternalTimer($hash,"Shelly_webhook"); 
       InternalTimer(time()+3, "Shelly_webhook", $hash, 0);
     }
  #---------------------------------------  
  }elsif( $attrName eq "interval" ){
    if( $cmd eq "set" ){
      #-- update timer
      if( $model eq "shellypro3em" && $attrVal > 0 ){ 
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
      $hash->{INTERVAL}=60;
    }
    if($init_done){
      RemoveInternalTimer($hash,"Shelly_status");
      InternalTimer(time()+$hash->{INTERVAL}, "Shelly_status", $hash, 0)
        if( $hash->{INTERVAL} != 0 );
    } 
  #---------------------------------------  
  }elsif( $attrName eq "defchannel" ){
    if( ($shelly_models{$model}[0] < 2 && $mode eq "relay") || ($model eq "shellyrgbw" && $mode ne "white") ){
      $error="Setting the \'defchannel\' attribute only works for devices with multiple outputs/relays";
      Log3 $name,1,"[Shelly_Attr] $name\: $error ";
      return $error;
    }
    if( $attrVal =~ /\D/ ){  # checking if there is anything else than a digit
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
  }
  #--------------------------------------- 
  return undef;
} #END# Shelly_Attr


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
  
  Log3 $name,6,"[Shelly_Get] receiving command get $name ".$a[1].($a[2]?" ".$a[2]:"") ;
  
  my $model =  AttrVal($name,"model","generic");
  my $mode  =  AttrVal($name,"mode","");
  
  #-- get version
  if( $a[1] eq "version") {
    return "$name.version => $version";
    
  #-- autodetect model "get model"
  }elsif($a[1] eq "model") {
    $v = Shelly_get_model($hash);
return $v;
      
  #-- current status
  }elsif($a[1] eq "status") {
    $v = Shelly_status($hash);
    
  #-- current status of shelly
  }elsif($a[1] eq "shelly_status") {
    $v = Shelly_shelly($hash);
  
  #-- some help on registers
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
  
  #-- configuration register
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
    
    my $pre = "settings/";
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

    $v = Shelly_configure($hash,$pre.$reg);  # will call Shelly_configure() as Non-Blocking-Get
      
    if(defined($v)) {
       return "$a[0] $a[1] => $v";
    }else{
       return "$a[0] $a[1] $a[2] $a[3]\n\nsee reading \'config\' for result";
    }
    
  #-- else
  }else{
    my $newkeys = $shelly_dropdowns{Gets};   ## join(" ", sort keys %gets);
    $newkeys    =~  s/:noArg//g
      if( $a[1] ne "?");
    my $msg = "unknown argument ".$a[1].", choose one of $newkeys";
    Log3 $name,5,"[Shelly_Get] $name: $msg";
    return $msg;
  }

  return undef;
} #END# Shelly_Get
 
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
  
  my $parameters=( scalar(@a)?" and ".scalar(@a)." parameters: ".join(" ",@a) : ", no parameters" );
  Log3 $name,3,"[Shelly_Set] calling for device $name with command \'$cmd\'$parameters"  if($cmd ne "?");#4
  
  my $value = shift @a;  # 1st parameter

  $name = $hash->{NAME}   if( !defined($name) );
  
  #-- when Shelly_Set is called by 'Shelly_Set($hash)' arguments are not handed over, look for an termporarely stored command in internals
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
  my ($msg,$channel,$time,$brightness);


  #-- WEB asking for command list 
  if( $cmd eq "?" ){
    my $newkeys;
    if( !defined($hash->{helper}{Sets}) ){
      # all models and generic
      $newkeys = $shelly_dropdowns{Shelly};
      # most of devices, except roller, metering
      $newkeys .= $shelly_dropdowns{Onoff} 
                                    if( ($mode ne "roller" && $shelly_models{$model}[0]>0) ||  $shelly_models{$model}[2]>0 || $shelly_models{$model}[7]>0 );
      # multichannel devices
      $newkeys .= $shelly_dropdowns{Multi} if( ($mode ne "roller" && $shelly_models{$model}[0]>1) || ($shelly_models{$model}[2]>1 && $mode eq "white") );
      if( $mode eq "roller" || ($shelly_models{$model}[0]==0 && $shelly_models{$model}[1]>0)){
          $newkeys .= $shelly_dropdowns{Rol};
      }elsif( $model =~ /shellydimmer/ || ($model =~ /shellyrgbw.*/ && $mode eq "white")  ){
          $newkeys .= $shelly_dropdowns{RgbwW};
      }elsif( $model =~ /shellybulb.*/ &&  $mode eq "white" ){
          $newkeys .= " dim-for-timer".$shelly_dropdowns{BulbW};
      }elsif( $model =~ /shelly(rgbw|bulb).*/ && $mode eq "color" ){
          $newkeys .= $shelly_dropdowns{RgbwC};
      }
      if( $shelly_models{$model}[4]==0 || $shelly_models{$model}[3]==0 ){
          $newkeys =~ s/,energy//; # remove 'energy' from dropdown-list
      }
      if( $init_done ){
        $hash->{helper}{Sets}=$newkeys;
        Log3 $name,2,"[Shelly_Set] stored keys for device $name \"$newkeys\" in helper";
      }
    }else{
      $newkeys = $hash->{helper}{Sets};
    }
    
    Log3 $name,5,"[Shelly_Set] FhemWeb is requesting set-commands for device $name"; #4
    #$hash->{'.FWR'}=$hash->{'.FWR'}+1;
    # ':noArg' will be stripped off by calling instance
    return "$model $mode: unknown argument $cmd choose one of $newkeys";
  }
     
  #-- following commands do not occur in command list, eg. out_on, input_on, single_push
  #-- command received via web to register local changes of the device 
  if( $cmd =~ /^(out|button|input|short|single|double|triple|long|touch|voltage|temperature|humidity|Active_Power|Voltage|Current)_(on|off|push|up|down|multi|over|under|a|b|c|changed)/
              ||  $cmd =~ /^(stopped|opening|closing|is_open|is_closed|power|voltage|current|tempC)/ ){
    my $signal=$1;
    my $isWhat=$2;
    my $subs;
    Log3 $name,5,"[Shelly_Set] calling for device $name with command $cmd".( defined($value)?" and channel $value":", without channel" );
    Log3 $name,4,"[Shelly_Set] Calling $name with $cmd val=$value signal=$signal ".(defined($isWhat)?"iswhat=$isWhat":"isWhat not defined");
    readingsBeginUpdate($hash);
    if( $signal eq "out" && $mode eq "relay"){ #change of device output
          $subs = ($shelly_models{$model}[0] == 1) ? "" : "_".$value;
          readingsBulkUpdateMonitored($hash,"relay$subs",$isWhat);
          readingsBulkUpdateMonitored($hash,"state",$isWhat)
                      if( $shelly_models{$model}[0]==1 );      ## do not set state on multichannel-devices
    }elsif( $signal eq "out" && $mode eq "white"){ #change of bulb device output
          $subs = ($shelly_models{$model}[2] == 1) ? "" : "_".$value;  # no of dimmers
          readingsBulkUpdateMonitored($hash,"state$subs",$isWhat);
    }elsif( $signal eq "out" && !$value ){ #change of single channel device output
          #$subs = "";
          readingsBulkUpdateMonitored($hash,"state",$isWhat);
    }elsif( $signal eq "button" ){   # ShellyPlug(S)
          $subs = ($shelly_models{$model}[5] == -1) ? "" : "_".$value;
          readingsBulkUpdateMonitored($hash, "button$subs", $isWhat, 1 );
    }elsif( $signal eq "input" ){    # devices with an input-terminal
          $subs = ($shelly_models{$model}[5] == 1) ? "" : "_".$value;
          readingsBulkUpdateMonitored($hash, "input$subs", $isWhat, 1 );
    }elsif( $signal =~ /^(single|double|triple|short|long)/ ){
          $subs = (abs($shelly_models{$model}[5]) == 1) ? "" : "_".$value;
          readingsBulkUpdateMonitored($hash, "input$subs", "ON", 1 );
          readingsBulkUpdateMonitored($hash, "input$subs\_action", $cmd, 1 );
          readingsBulkUpdateMonitored($hash, "input$subs\_actionS",$fhem_events{$cmd}, 1 );
          # after a second, the pushbuttons state is back to OFF resp. 'unknown', call status of inputs
          RemoveInternalTimer($hash,"Shelly_inputstatus"); 
          InternalTimer(time()+1.4, "Shelly_inputstatus", $hash,1); 
    }elsif( $signal eq "touch" ){    # devices with an touch-display
          #$subs = ($shelly_models{$model}[5] == 1) ? "" : "_".$value;
          readingsBulkUpdateMonitored($hash, "touch", $isWhat, 1 );
    }elsif( $signal =~ /^(voltage|temperature|humidity)/ ){
          $subs = defined($value)?"_".$value:"" ;
          readingsBulkUpdateMonitored($hash,$signal.$subs."_range", $isWhat );
    }elsif( $signal =~ /^(tempC)/ ){
          $subs = defined($value)?"_".$a[0]:"" ;
          readingsBulkUpdateMonitored($hash,"temperature".$subs, $value.$si_units{tempC}[$hash->{units}] );
    }elsif( $signal =~ /^(power|voltage|current)/ ){  #as by ShellyPMmini
          $value = sprintf( "%5.2f%s", $value, $si_units{$signal}[$hash->{units}] ); ## %5.1f
          readingsBulkUpdateMonitored($hash,$signal,$value );
    }elsif( $signal =~ /^(Active_Power|Voltage|Current)/ ){
          if( !defined($isWhat) ){
              Shelly_error_handling($hash,"Shelly_Set:Active_Power","no phase received from ShellyPro3EM");
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

    #-- commands from shelly actions: opening, closing, stopped, is_closed, is_open
    }elsif( $signal eq "opening" ){
          $hash->{MOVING} = "drive-up";
    }elsif( $signal eq "closing" ){
          $hash->{MOVING} = "drive-down";
    }elsif( $signal eq "stopped" ){
          $hash->{MOVING} = "stopped";
    }elsif( $signal =~ /is/ ){
          $hash->{MOVING} = "stopped";
          $cmd = "stopped";
    }else{
          Log3 $name,1,"[Shelly_Set] $name: Wrong detail on action command $cmd $value". (defined($mode)?", mode is $mode":", no mode given");
          return;
    }
    readingsBulkUpdateMonitored($hash,"state",$hash->{MOVING}) if( defined($hash->{MOVING}) );
    readingsEndUpdate($hash,1);
      #-- Call status after switch.n
    if( $signal !~ /^(Active_Power|Voltage|Current|apower|voltage|current)/ ){      
      RemoveInternalTimer($hash,"Shelly_status"); Log3 $name,6,"shelly_set 1715 removed Timer Shelly_status, now calling in 1.5 sec";
      InternalTimer(time()+1.5, "Shelly_status", $hash);
    }
    return undef;
  }

  
  #-- real commands 
  my $ff=-1;  # Function-Family, correspondends to row in %shelly_models{model}[]
  
  #-- we have a switch type device
  if( $shelly_models{$model}[0]>0 && $mode ne "roller" ){
      $ff = 0;
  #-- we have a Shelly 2 / 2.5 or a Shelly(Plus/Pro)2pm roller type device
  }elsif( $shelly_models{$model}[1]>0 && $mode ne "relay" ){
      $ff = 1;
  #-- we have a dimable device:  Shelly dimmer or Shelly RGBW in white mode
  }elsif( ($model =~ /shellydimmer/) || (($model =~ /shellyrgbw.*/) && ($mode eq "white")) ){
      $ff = 2;
  #-- we have a ShellyBulbDuo
  }elsif( ($model =~ /shellybulb.*/) && ($mode eq "white") ){
      $ff = 2;
  #-- we have a color type device (Bulb or Shelly RGBW, and color mode)
  }elsif( ($model =~ /shelly(rgbw|bulb).*/) && ($mode eq "color")){
      $ff = 7;
  }else{
      $ff = -1;
  }  

  #-- get channel parameter
  if( $cmd eq "toggle" || $cmd eq "on" || $cmd eq "off" ){
        $channel = $value; 
  }elsif( $cmd =~ /(dimup)|(dimdown)/ ){
        my $delta = $value;
        $channel = shift @a;
        $channel = AttrVal($name,"defchannel",0)  if( !defined($channel) );
        my $subs = $shelly_models{$model}[2]>1 ? "_$channel" : "";
        if( !defined($delta) ){
            $delta = AttrVal($name,"dimstep",25);
        }
        $delta = -$delta   if( $cmd eq "dimdown" );
        $brightness = ReadingsNum($name,"pct$subs",0) + $delta;
        $brightness = 100 if( $brightness > 100 );
        if( $brightness < 10 ){
           $cmd = "off";
        }else{
           $cmd = "dim";
        }
  }elsif( $cmd =~ /(on|off)-for-timer/ ){
        $time = $value;
        $channel = shift @a;
  }elsif( $cmd =~ /dim/ ){
        $brightness = $value;
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
        $channel = shift @a if(  $channel eq "%" ); # skip %-sign coming from dropdown (units=1)
  }   
  
  #-- check channel
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
     $msg = (defined($channel))?$channel:"undefined";
     Log3 $name,4,"[Shelly_Set] $name precheck: channel is $msg";

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
     }
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
               $cmd = "?turn=off$oldtimer";
           }else{
               $cmd = "?brightness=$brightness&turn=on$oldtimer";
           }
    }
    #-- check timer command
    elsif( $cmd =~ /for-timer/ ){
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
    }elsif( $cmd =~ /(on)|(off)/ ){
        $cmd = "?turn=$cmd";
    }  
    # $cmd = is 'on' or 'off'  or  'on&timer=...' or 'off&timer=....' or 'dim&timer=....'
    
    Log3 $name,4,"[Shelly_Set] switching channel $channel for device $name with command $cmd, FF=$ff";#4
    if( $ff==0 ){    
        if( $shelly_models{$model}[4]==2 ){
##            $cmd = "?turn=$cmd"   ##"/relay/$channel?turn=$cmd";
##                  if( $cmd !~ "brightness" );
##        }else{
            $cmd =~ s/\?turn=on/true/;
            $cmd =~ s/\?turn=off/false/;
            $cmd =~ s/timer/toggle_after/;
            $cmd = "/rpc/Switch.Set?id=$channel&on=$cmd";
        }
        $msg = Shelly_onoff($hash,$channel,$cmd); 
    }elsif( $ff==2 ){
        if( $model =~ /shellydimmer/ ){
            $channel = "light/$channel"; 
        }elsif( $model =~ /shellybulb/ && $mode eq "white" ){ 
            $channel = "light/$channel";
        }elsif( $model =~ /shellyrgbw/ && $mode eq "white" ){
            $channel = "white/$channel";
        }
       #
        $msg = Shelly_dim($hash,$channel,$cmd);
    }elsif($ff==7 ){
        $msg = Shelly_dim($hash,"color/$channel",$cmd); #"?turn=$cmd"
    }
    return $msg if( $msg );
    return;
    
  #- - ON and OFF  -  switch all channels of a multichannel switch-device
  }elsif( $cmd =~ /^((ON)|(OFF))/ ){
    $cmd = lc($1);
    for(my $i=0;$i<$shelly_models{$model}[$ff];$i++){
        Shelly_Set($hash,$name,$cmd,$i);
    }
    return;
  }
    
  #- - pct, brightness, dim - set percentage volume of dimmable device (no rollers)  eg. shellydimmer or shellyrgbw in white mode
  if( ($cmd eq "pct" || $cmd eq "brightness" || $cmd =~ /^(dim)/ ) && $ff != 1 ){
    if( $ff !=2 ){
          $msg = "Error: forbidden command  \'$cmd\' for device $name <$ff>";
          Log3 $name,1,"[Shelly_Set] ".$msg;
          return $msg;
    }
     # check value
     if( !defined($value) && $cmd =~ /up|down/ ){
            $value = AttrVal($name,"dimstep",10) if(!defined($value));     
     }elsif( !defined($value) ){
            $msg = "Error: no $cmd value \'$value\' given for device $name";
            Log3 $name,1,"[Shelly_Set] ".$msg;
            return $msg;
     }elsif( $value =~ /\D+/ ){    #anything else than a digit
            $msg = "Error: wrong $cmd value \'$value\' for device $name, must be <integer>";
            Log3 $name,1,"[Shelly_Set] ".$msg;
            return $msg;
     }elsif( $value == 0 && $cmd =~ /(pct)|(dimup)|(dimdown)/ ){
            $msg = "$name Error: wrong $cmd value \'$value\' given, must be 1 ... 100 ";
            Log3 $name,1,"[Shelly_Set] ".$msg;
            return $msg;
     }elsif( $value<0  || $value>100 ){
            $msg = "$name Error: wrong $cmd value \'$value\' given, must be 0 ... 100 ";
            Log3 $name,1,"[Shelly_Set] ".$msg;
            return $msg;
     } 
    #$cmd = "?brightness=".$value;
    Log3 $name,4,"[Shelly_Set] setting brightness for device $name to $value";
    if( $ff==2 ){
        if( $model =~ /shellyrgbw/ && $mode eq "white" ){
            $channel = "white/$channel";
        }else{ 
            $channel = "light/$channel";
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
        return Shelly_dim($hash,$channel,$cmd);
    }
    return $msg if( $msg );
  }

  #-- commands strongly dependent on Shelly type -------------------------------------------------------
  #-- we have a roller type device / roller mode
  if( $cmd =~ /^(stop|closed|open|pct|pos|delta|zero)/ && $shelly_models{$model}[1]>0 && $mode ne "relay" ){
    $ff = 1;
    Log3 $name,4,"[Shelly_Set] $name: we have a $model ($mode mode) and command is $cmd";
    #x   my $channel = $value;
    
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
         InternalTimer(time()+1.0, "Shelly_Set", $hash, 1);         
         $cmd = "?go=stop";
        
    #-- is moving !!!
    }elsif(  $hash->{MOVING}  ne "stopped"  ){
         Log3 $name,1,"[Shelly_Set] Error: received command \'$cmd\', but $name is still moving";   
              
    #-- is not moving 
    }elsif(  $hash->{MOVING}  eq "stopped" && $cmd eq "zero" ){
         # calibration of roller device
         return "comand zero deactivated";
         return Shelly_configure($hash,"rc");
                
    #--any other cases: no movement and commands: open, closed, pct, pos, delta    
    }elsif( $cmd =~ /(closed)|(open)/ ){
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
        $cmd .= "&duration=$value"    if(defined($value));
        
    }elsif( $cmd eq "pct" || $cmd =~ /pos/ || $cmd eq "delta" ){
        my $targetpct = $value;
        my $pos  = ReadingsVal($name,"position","");
        my $pct  = ReadingsVal($name,"pct",undef);  
             if( $cmd eq "pct" &&  "$value" =~ /[\+-]\d*/ ){
               $targetpct = eval($pct."$value"); 
             }
        #-- check for sign
        if( $cmd eq "delta" ){
           if( $value =~ /[\+-]\d*/ ){
               $targetpct += $pct;
           }else{
               Log3 $name,1,"[Shelly_Set] $name: Wrong format of comand \'$cmd\', must consist of a plus or minus sign followed by an integer value";
               return;
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
              Log3 $name,1,"[Shelly_Set] please set the maxtime_open/closed attributes for proper operation of device $name";
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
        $cmd = "?go=to_pos&roller_pos=" . ($pctnormal ? $targetpct : 100 - $targetpct);
    }  
  Log3 $name,4,"[Shelly_Set] $name: calling Shelly_updown with comand $cmd, duration=".$hash->{DURATION};
  
  # Shelly_updown performs one status update after start, and one at expected time of stop
  return Shelly_updown($hash,$cmd);

  ################################################################################################################
  #-- we have a ShellyBulbDuo (it's a bulb in white mode) $ff=2
  }elsif( $cmd eq "ct" ){
      $channel = shift @a;
      return Shelly_dim($hash,"light/0","?temp=".$value);
    
  ################################################################################################################    
  #-- we have a Shelly rgbw type device in color mode
  #-- commands: hsv, rgb, rgbw, white, gain
  }elsif( ($model =~ /shelly(rgbw|bulb).*/) && ($mode eq "color")){
    $ff = 7;
    my $channel = $value;  
    
    if( $cmd eq "hsv" ){
      my($hue,$saturation,$value)=split(',',$value);
      #-- rescale 
      if( $hue>1 ){
        $hue = $hue/360;
      } 
      my ($red,$green,$blue)=Color::hsv2rgb($hue,$saturation,$value);
      $cmd=sprintf("red=%d&green=%d&blue=%d",int($red*255+0.5),int($green*255+0.5),int($blue*255+0.5));
      if($model eq "shellybulb"){
          $cmd .= "&gain=100";
      }else{
          $cmd .= sprintf("&gain=%d",$value*100);  #new
      }
      return Shelly_dim($hash,"color/0","?".$cmd);
      
    }elsif( $cmd =~ /rgb/ ){
      my $red  = hex(substr($value,0,2));  # convert hexadecimal number into decimal
      my $green= hex(substr($value,2,2));
      my $blue = hex(substr($value,4,2));
      if( $cmd eq "rgbw" ){
          my $white= hex(substr($value,6,2));
          $cmd     = sprintf("white=%d",$white);
      }
      $cmd    .= sprintf("&red=%d&green=%d&blue=%d",$red,$green,$blue);
      $cmd    .= "&gain=100";
      return Shelly_dim($hash,"color/0","?".$cmd);
      
    }elsif( $cmd eq "white" ){  # value 0 ... 100
      $cmd=sprintf("white=%d",$value*2.55);
      return Shelly_dim($hash,"color/0","?".$cmd);
    }elsif( $cmd eq "gain" ){  # value 0 ... 100
      $cmd=sprintf("gain=%d",$value);
      return Shelly_dim($hash,"color/0","?".$cmd);
    }
  }
  
  ###########################################################################
  #-- commands independent of Shelly type: password, interval, reboot, update
  if( $cmd eq "password" ){
    my $user = AttrVal($name,"shellyuser",undef);
    if(!$user && $shelly_models{$model}[4]==0 ){
      my $msg = "Error: password can be set only if attribute \'shellyuser\' is set";
      Log3 $name,1,"[Shelly_Set] ".$msg;
      return $msg;
    }
    setKeyValue("SHELLY_PASSWORD_$name", $value);
    return undef;
    
  }elsif( $cmd eq "interval" ){
      if( IsInt($value) && $value >= 0){  # see 99_Utils.pm
          $hash->{INTERVAL}=int($value);
      }elsif( $value == -1 ){
          $hash->{INTERVAL}=AttrVal($name,"interval",$defaultINTERVAL);
      }else{
          my $msg = "Value is not an positve integer";
          Log3 $name,1,"[Shelly_Set] ".$msg;
          return $msg;
      }
      Log3 $name,1,"[Shelly_Set] Setting interval of $name to ".$hash->{INTERVAL};
     #### Shelly_Set($hash->{NAME},"startTimer");
      if( $hash->{INTERVAL} ){
        Log3 $name,2,"[Shelly_Set] Starting cyclic timers for $name ($model)";
        RemoveInternalTimer($hash,"Shelly_status");
        InternalTimer(time()+$hash->{INTERVAL}, "Shelly_status", $hash, 0);
        RemoveInternalTimer($hash,"Shelly_shelly");
        InternalTimer(time()+$defaultINTERVAL*$secndIntervalMulti, "Shelly_shelly", $hash,0);
        if( $model eq "shellypro3em" ){
          RemoveInternalTimer($hash,"Shelly_EMData");
          InternalTimer(int((time()+60)/60)*60+1, "Shelly_EMData", $hash,0);
          Log3 $name,2,"[Shelly_Set] Starting cyclic EM-Data timers for $name";
        }
      }else{
        Log3 $name,2,"[Shelly_Set] No timer started for $name";
      }
      return undef;
      
  }elsif( $cmd eq "startTimer" ){
      if( $hash->{INTERVAL} ){
        Log3 $name,2,"[Shelly_Set] Starting cyclic timers for $name";
        RemoveInternalTimer($hash,"Shelly_status");
        InternalTimer(time()+$hash->{INTERVAL}, "Shelly_status", $hash, 0);
        RemoveInternalTimer($hash,"Shelly_shelly");
        InternalTimer(time()+$defaultINTERVAL*$secndIntervalMulti, "Shelly_shelly", $hash,0);
        RemoveInternalTimer($hash,"Shelly_EMData");
        InternalTimer(int((time()+60)/60)*60+1, "Shelly_EMData", $hash,0);
      }else{
        Log3 $name,2,"[Shelly_Set] No timer started for $name";
      }
      return "started";#undef;
      
  }elsif( $cmd eq "reboot" ){
      Log3 $name,1,"[Shelly_Set] Rebooting $name";
      Shelly_configure($hash,$cmd);
      return undef;

  }elsif( $cmd eq "update") {
      Log3 $name,1,"[Shelly_Set] Updating $name";
   #  if( $shelly_models{$model}[4]==0 ){$cmd ="ota/update";} # Gen1 only
      Shelly_configure($hash,$cmd);
      return undef;
      
  }elsif( $cmd eq "reset" ){
      my $doreset = $value;
      Log3 $name,4,"[Shelly_Set] Resetting counter \'$doreset\' of device $name";
      if( $doreset eq "disconnects" ){
         readingsSingleUpdate($hash,"network_disconnects",0,1);
      }elsif( $doreset eq "energy" ){
         if( ReadingsVal($name,"firmware","") =~ /(v0|v1.0)/ ){
              my $err = "firmware must be at least v1.1.0";
              Shelly_error_handling($hash,"Shelly_Set:reset",$err);
              return $err;
         }
         my $numC;
         if( $shelly_models{$model}[0]>0 && $mode ne "roller" ){
            $cmd = "Switch";
            $numC = $shelly_models{$model}[0];
         }elsif( $shelly_models{$model}[1]>0 && $mode ne "relay" ){
            $cmd = "Cover";
            $numC = $shelly_models{$model}[1];
         }elsif( $shelly_models{$model}[3]>0 && !$mode ){
            $cmd = "PM1";
            $numC = $shelly_models{$model}[3];
         }else{ 
            Log3 $name,1,"[Shelly_configure] Wrong command $cmd";
            return;
         }
         for( my $id=0; $id<$numC; $id++ ){
            Shelly_configure($hash,"rpc/$cmd\.ResetCounters?id=$id&type=[\"aenergy\"]");
            #readingsSingleUpdate($hash,"energy_$id","-",1) if( ReadingsNum($name,"energy_$id",undef) );
            Shelly_status($hash);
         }
      }
      return undef;

  #-- renaming the Shelly, spaces in name are allowed
  }elsif( $cmd eq "name") {   #ShellyName
      my $newname;
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
        $cmd="rpc/Sys.SetConfig?config={%22device%22:{%22name%22:%22$newname%22}}" ;
        #                                {"device"   :{"  name"  :   "arg"}}
      }else{ 
        $cmd="settings?name=$newname";
      }
      Shelly_configure($hash,$cmd);
      return $msg;
   
  #-- command config largely independent of Shelly type 
  }elsif($cmd eq "config") {
    my $reg = $value;
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
    my $pre = "settings/";
    if( ($model =~ /shelly2.*/) && ($mode eq "roller") ){  ##R
      $pre .= "roller/0?";
    }elsif( ($model eq "shellyrgbw" || $model eq "shellybulb") && ($mode eq "white") ){
      $pre .= "white/0?";
    }elsif( ($model eq "shellyrgbw" || $model eq "shellybulb") && ($mode eq "color") ){
      $pre .= "color/0?";
    }elsif( $model eq "shellydimmer" ){
      $pre .= "light/0?";
    }else{
      $pre .= "relay/$chan?";
    }
    Shelly_configure($hash,$pre.$reg."=".$val);
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
       Log3 $name,3,"[Shelly_Set] readingsProxy devices for $name requested";   
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
               fhem("attr $name\_$i userReadings input {ReadingsVal(\"$name \",\"input_$i\",\"\")}");
           }
           Log3 $name,1,"[Shelly_Set] readingsProxy device ".$name."_$i created";   
         }
         $msg = "$i devices for $name created";
      }else{
         $msg = "No separate channel device created for device $name, only one channel present";
         Log3 $name,1,"[Shelly_Set] ".$msg;
      }
      return $msg;
  }else{
  
    
  $parameters=( scalar(@args)?" and ".scalar(@args)." parameters: ".join(" ",@args) : ", no parameters" );
  Log3 $name,1,"[Shelly_Set] parsed, outstanding call for device $name with command \'$cmd\'$parameters"  if($cmd ne "?");#4
return SetExtensions($hash,$hash->{helper}{Sets},$name,$cmd,@args);
      return "$model $mode: unknown argument $cmd choose one of ".$hash->{helper}{Sets};
  } 
  return undef;
}

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
# Shelly_configure -  Configure Shelly device or read general configuration
#                 acts as callable program Shelly_configure($hash,$cmd)
#                 and as callback program  Shelly_configure($hash,$cmd,$err,$data)
# 
# Parameter hash,  cmd = command 
#
########################################################################################

 sub Shelly_configure {
  my ($hash, $cmd, $err, $data) = @_;
  my $name = $hash->{NAME};
  my $state = $hash->{READINGS}{state}{VAL};
  my $net   = $hash->{READINGS}{network}{VAL};
  return "no network information" if( !defined $net );
  return "device not connected" 
    if( $net =~ /not connected/ );

  my $model = AttrVal($name,"model","generic");
  my $creds = Shelly_pwd($hash);
  
  ##2ndGen    devices will answer with "null\R"
  if( $cmd eq "update" ){
    if( $shelly_models{$model}[4]>=1 ){
      $cmd="rpc/Shelly.Update?stage=%22stable%22" ;  #beta
    }else{
      $cmd="ota?update=true";
    }
  }elsif( $cmd eq "reboot" ){
    if( $shelly_models{$model}[4]>=1 ){
      $cmd="rpc/Shelly.Reboot" ;
    }else{
      $cmd="reboot";
    }
  }elsif( $cmd =~ /ResetCounters/ ){
      Log3 $name,5,"[Shelly_configure] resetting energy-counter for device $name ($cmd)";
    
  }elsif( $cmd eq "rc" || $cmd eq "calibrate" ){
    if( $shelly_models{$model}[4]>=1 ){
      $cmd="rpc/Cover.Calibrate?id=0" ;  #Gen2
    }elsif( $shelly_models{$model}[1]==1  &&  AttrVal($name,"mode",undef) eq "roller" ){
      $cmd="roller/0/calibrate";
    }else{ 
      $cmd="settings?calibrate=1";  # shelly-dimmer
    }
  }

  Log3 $name,5,"[Shelly_configure] $name: received command=$cmd";

  if( $hash && !$err && !$data ){
     my $url = "http://$creds".$hash->{TCPIP}."/".$cmd;
     Log3 $name,4,"[Shelly_configure] issue a non-blocking call to $url";
     HttpUtils_NonblockingGet({
        url      => $url,
        timeout  => AttrVal($name,"timeout",4),
        callback => sub($$$){ Shelly_configure($hash,$cmd,$_[1],$_[2]) }
     });
     return undef;
  }elsif( $hash && $err ){
    Shelly_error_handling($hash,"Shelly_configure",$err);
    return;
  }
  Log3 $name,3,"[Shelly_configure] device $name has returned ".length($data)." bytes of data";
  Log3 $name,5,"[Shelly_configure] device $name has returned data:\n\"$data\"";

  if( $shelly_models{$model}[4]>=1 ){
         if( $data =~ /null/ ){           #\R ? perl 5.10.0, in older versions: \r or \n 
              readingsSingleUpdate($hash,"config","successful",1);
         }elsif( $data =~ /energy/ ){    
              readingsSingleUpdate($hash,"config","counter set to 0",1);
         }else{
              Log3 $name,1,"[Shelly_configure] $name: Error while processing \'$cmd\'";
              Shelly_error_handling($hash,"Shelly_configure","Error");
         }  
         return; 
  }
  
  # proceed only on Gen 1 devices
    
  # extracting json from data
  my $json = JSON->new->utf8;
  my $jhash = eval{ $json->decode( $data ) };
  if( !$jhash ){
    Shelly_error_handling($hash,"Shelly_configure","invalid JSON data");
    return;
  }
 
  #-- if settings command, we obtain only basic settings
  if( $cmd eq "settings/" ){
    $hash->{SHELLYID} = $jhash->{'device'}{'hostname'};
    return
  }elsif( $cmd =~ /ota/ ){   # ota?update=true
      readingsSingleUpdate($hash,"config","updating",1);
      return undef;
  }elsif( $cmd =~ /reboot/ ){ # Answer is: {"ok":true}
      readingsSingleUpdate($hash,"config","rebooting",1);
      return undef;
  }
  # $cmd example:   settings/relay/0?auto_off=35
  Log3 $name,4,"[Shelly_configure] device $name processing \"$cmd\" ";#4
  #-- isolate register name 
  my $reg = substr($cmd,index($cmd,"?")+1);
  my $chan= substr($cmd,index($cmd,"?")-1,1);
  $reg    = substr($reg,0,index($reg,"="))
    if(index($reg,"=") > 0);
  my $val = $jhash->{$reg};

  $chan = $shelly_models{$model}[7] == 1  ? "" : "[channel $chan]";
  
  if( defined($val) ){
      Log3 $name,4,"[Shelly_configure] device $name result is reg: $reg $chan value $val ";    
      readingsSingleUpdate($hash,"config","$reg=$val $chan",1);
  }else{
      Log3 $name,4,"[Shelly_configure] device $name no result found for register $reg $chan";    
      readingsSingleUpdate($hash,"config","register \'$reg\' not found or empty $chan",1);
  }
  
  return undef;
}


########################################################################################
#
# Shelly_status - Retrieve data from device
#                 acts as callable program Shelly_status($hash)
#                 and  as callback program Shelly_status($hash,$err,$data) (only for 1G)
# 
# Parameter hash
#
########################################################################################
  
sub Shelly_inputstatus {
  my ($hash) = @_;
  Shelly_status($hash,"input");
}
  
sub Shelly_status {
  my ($hash, $comp, $err, $data) = @_;
  my $name = $hash->{NAME};
return if( $hash->{INTERVAL} == 0 ); 
  my $state = $hash->{READINGS}{state}{VAL};
  
  my $model = AttrVal($name,"model","generic");
  
  my $creds = Shelly_pwd($hash);
  my $url     = "http://$creds".$hash->{TCPIP};
  my $timeout = AttrVal($name,"timeout",4);
  
  # for any callbacks restart timer
  if( $hash && $err && $hash->{INTERVAL} != 0 ){   ## ($err || $data )
      #-- cyclic update nevertheless
      RemoveInternalTimer($hash,"Shelly_status"); 
      my $interval=minNum($hash->{INTERVAL},$defaultINTERVAL*$secndIntervalMulti);
      Log3 $name,3,"[Shelly_status] $name: Error in callback, update in $interval seconds";
      InternalTimer(time()+$interval, "Shelly_status", $hash, 1);
  }
  
  # in any cases check for error in non blocking call
  if( $hash && $err ){
      Shelly_error_handling($hash,"Shelly_status",$err);
      return $err;
  }

  #-- check if 2nd generation device
  my $is2G = ($shelly_models{$model}[4]>=1 ? 1 : 0 );#Log3 $name,0,"$model $is2G";
#3G {  
  # preparing Non Blocking Get #--------------------------------------------------  

  if( $hash && !$err && !$data ){
      #-- for 1G devices status is received in one single call
      if( !$is2G ){
         $url     .= "/status";
         Log3 $name,4,"[Shelly_status(1G)] issue a non-blocking call to $url";  #4
         HttpUtils_NonblockingGet({
            url      => $url,
            timeout  => $timeout,
            callback => sub($$$){ Shelly_status($hash,undef,$_[1],$_[2]) }
         });
      #-- 2G devices 
      }else{
          $comp = AttrVal($name,"mode","relay") if(!$comp);
          $url .= "/rpc/";
          my $id=0;
          my $chn=1;  #number of channels
          if($model eq "shellypro3em"){ 
            $comp = "EM"; 
            $url  .= "EM.GetStatus";
          }elsif($model eq "shellypluspm" || $model eq "shellypmmini" ){
            $comp = "pm1";
            $url  .= "PM1.GetStatus";
            #$chn = $shelly_models{$model}[5];
          }elsif($model eq "shellyplusi4"||$comp eq "input"){
            $comp = "input"; 
            $url  .= "Input.GetStatus";  
            $chn = $shelly_models{$model}[5];
          }elsif($model eq "shellyprodual" || $comp eq "roller"){  
            $url  .= "Cover.GetStatus";  
            $chn = $shelly_models{$model}[1];
          }elsif( $comp eq "relay"){
            $url  .= "Switch.GetStatus";  
            $chn = $shelly_models{$model}[0];
          }else{
            $err = "unknown model \'$model\' or mode \'$comp\' ";
            Shelly_error_handling( $hash,"Shelly_status",$err);
            return $err;
          }
          $chn = 1 if( ReadingsVal($name,"state","") =~ /Error/ );
          $url .= "?id="; 
          #-- get status of component (relay, roller, input, EM, ...); we need to submit the call several times
          for( $id=0; $id<$chn; $id++){
              #$url  = $url_."?id=".$id;
              Log3 $name,4,"[Shelly_status] issue a non-blocking call to $url$id, callback to proc2G for comp=$comp";  #4
              HttpUtils_NonblockingGet({
                url      => $url.$id,
                timeout  => $timeout,
                callback => sub($$$){ Shelly_status($hash,$comp,$_[1],$_[2]) }
              });
          }
      }
      return undef;
  }
  
  # processing incoming data #--------------------------------------------------
  Log3 $name,5,"[Shelly_status] device $name of model $model has returned data \n$data";
  
  # extracting json from data
  my $json = JSON->new->utf8;
  my $jhash = eval{ $json->decode( $data ) };  
  #-- error in data
  if( !$jhash ){
           Shelly_error_handling($hash,"Shelly_status","invalid JSON data");
           return;
#  }elsif(ReadingsVal($name,"network","") !~ /connected to/){
  }elsif(1){
    readingsBeginUpdate($hash);
    # as we have received a valid JSON, we know network is connected: we dont need this here
    #readingsBulkUpdateIfChanged($hash,"network","<html>connected to <a href=\"http://".$hash->{TCPIP}."\">".$hash->{TCPIP}."</a></html>",1);
    #transition
    if( $jhash->{'lights'}[0]{'transition'} ){
        my $chn = $shelly_models{$model}[2];
        $chn = 1 if( AttrVal($name,"mode", "color") eq "color" );
        my $subs;
        my $transition;
        for( my $i=0;$i<$chn;$i++){
            $transition  = $jhash->{'lights'}[$i]{'transition'};  # 0 .... 5000
            $subs = ($chn>1 ? "_$i" : "" );
            Shelly_readingsBulkUpdate($hash,"transition$subs",$transition.$si_units{time_ms}[$hash->{units}]); 
        }
    } 
    #-- look for transition time (bulbs only); time in milli-seconds
    if(0&&$jhash->{'transition'}) {
        readingsBulkUpdateMonitored($hash,"transition", $jhash->{'transition'}.$si_units{time_ms}[$hash->{units}]);
    }
    readingsEndUpdate($hash,1);  
  }

  my $next;  # Time offset in seconds for next update
  if( !$is2G && !$comp ){
      $next=Shelly_proc1G($hash,$jhash);
      Log3 $name,4,"[Shelly_status] $name: proc1G returned with value=$next";
  }else{
      $next=Shelly_proc2G($hash,$comp,$jhash);
      Log3 $name,4,"[Shelly_status] $name: proc2G returned with value=$next for comp $comp"; #4
  }
  return undef if( $next == -1 );  
  
  #-- cyclic update (or update close to on/off-for-timer command)
  
  if( !defined($next) || $next > 1.5*$hash->{INTERVAL} || $next==0 ){  # remaining timer as previously read
      $next = $hash->{INTERVAL};
  }elsif( $next > $hash->{INTERVAL} ){
      $next = 0.75*$hash->{INTERVAL};
  }
  
  Log3 $name,4,"[Shelly_status] $name: next update in $next seconds".(defined($comp)?" for Comp=$comp":""); #4
  RemoveInternalTimer($hash,"Shelly_status"); 
  InternalTimer(time()+$next, "Shelly_status", $hash, 1)
              if( $hash->{INTERVAL} != 0 );
  return undef;
}



########################################################################################
#
# Shelly_shelly - Retrieve additional data from device (network, firmware, webhooks, etc)
#                 acts as callable program Shelly_shelly($hash)
# 
# Parameter hash
#
########################################################################################
  
sub Shelly_shelly {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $state = $hash->{READINGS}{state}{VAL};
return if( $hash->{INTERVAL} == 0 ); 
  my $model = AttrVal($name,"model","generic");
  my $creds = Shelly_pwd($hash);
  my $url     = "http://$creds".$hash->{TCPIP};
  my $timeout = AttrVal($name,"timeout",4);
  
  Log3 $name,4,"[Shelly_shelly] $name is a ".($shelly_models{$model}[4]==0?"first":"second")." Gen device";  
  #-- check if 2nd generation device
  if( $shelly_models{$model}[4]==0 ){
    # handling 1st Gen devices
      #Log3 $name,4,"[Shelly_shelly] intentionally aborting, $name is not 2nd Gen";  
      #return undef ;
    #-- get settings of 1st-Gen-Shelly
    $url .= "/settings";
    Log3 $name,4,"[Shelly_shelly] issue a non-blocking call to ".$url;  #4
    HttpUtils_NonblockingGet({
        url      => $url,
        timeout  => $timeout,
        callback => sub($$$){ Shelly_status($hash,"settings",$_[1],$_[2]) }
    });
  }else{
    # handling 2nd Gen devices
    my $url_ = $url."/rpc/";

    #-- get status of Shelly (updates, status, ...)
    $url  = $url_."Shelly.GetStatus";
    Log3 $name,4,"[Shelly_shelly] issue a non-blocking call to ".$url;  #4
    HttpUtils_NonblockingGet({
        url      => $url,
        timeout  => $timeout,
        callback => sub($$$){ Shelly_status($hash,"status",$_[1],$_[2]) }
    });
      
    #-- get config of Shelly -
    $url  = $url_."Shelly.GetConfig";
    Log3 $name,4,"[Shelly_shelly] issue a non-blocking call to ".$url;  #4
    HttpUtils_NonblockingGet({
        url      => $url,
        timeout  => $timeout,
        callback => sub($$$){ Shelly_status($hash,"config",$_[1],$_[2]) }
    });
   
    #-- get device info of Shelly
    $url  = $url_."Shelly.GetDeviceInfo";
    Log3 $name,4,"[Shelly_shelly] issue a non-blocking call to ".$url;  #4
    HttpUtils_NonblockingGet({
        url      => $url,
        timeout  => $timeout,
        callback => sub($$$){ Shelly_status($hash,"info",$_[1],$_[2]) }
      });

 #   Shelly_webhook($hash,"Check"); # check webhooks regarding change of port, token etc.
    Shelly_webhook($hash,"Count"); # check number of webhooks on Shelly
  }
    ### cyclic update ###
    RemoveInternalTimer($hash,"Shelly_shelly");
    return undef
        if( $hash->{INTERVAL} == 0 ); 
        
    my $offset = maxNum($hash->{INTERVAL},$defaultINTERVAL)*$secndIntervalMulti; #$hash->{INTERVAL};
    if( $model eq "shellypro3em" ){ 
        # updates at every multiple of 60 seconds
        $offset = $hash->{INTERVAL}<=60 ? 60 : int($hash->{INTERVAL}/60)*60 ;
        # adjust to get readings 2sec after full minute
        $offset = $offset + 2 - time() % 60;
    }
    Log3 $name,4,"[Shelly_shelly] $name: long update in $offset seconds, Timer is Shelly_shelly";  #4
    InternalTimer(time()+$offset, "Shelly_shelly", $hash, 1);  
    return undef;
}

      
sub Shelly_actionCheck {
  my ($hash) = @_;
  my $name=$hash->{NAME};
  Log3 $name,4,"[Shelly_actionCheck] $name";
  Shelly_webhook($hash,"Check"); # check webhooks regarding change of port, token etc.
}

########################################################################################
# 
# Shelly_proc1G - process data from device 1st generation
#                   In 1G devices status are all in one call
#
########################################################################################

sub Shelly_proc1G {
  my ($hash, $jhash) = @_;
  $hash->{units}=0 if( !defined($hash->{units}) );
  my $name  = $hash->{NAME};
  my $state = $hash->{READINGS}{state}{VAL};
  
  my $model = AttrVal($name,"model","generic");
    

  my $mode     = AttrVal($name,"mode","");
  my $channels = $shelly_models{$model}[0];
  my $rollers  = $shelly_models{$model}[1];
  my $dimmers  = $shelly_models{$model}[2];
  my $meters   = $mode eq "roller" ?  $shelly_models{$model}[1] : $shelly_models{$model}[3];
 
  my ($subs,$ison,$source,$rstate,$rstopreason,$rcurrpos,$position,$rlastdir,$pct,$pctnormal);
  my ($overpower,$power,$energy);
  my $intervalN=$hash->{INTERVAL};   # next update interval
  
  readingsBeginUpdate($hash);
  Shelly_readingsBulkUpdate($hash,"network","<html>connected to <a href=\"http://".$hash->{TCPIP}."\">".$hash->{TCPIP}."</a></html>",1); 
  readingsBulkUpdateMonitored($hash,"network_rssi",Shelly_rssi($hash,$jhash->{'wifi_sta'}{'rssi'}) );
  readingsBulkUpdateMonitored($hash,"network_ssid",$jhash->{'wifi_sta'}{'ssid'} ) 
                                                                      if( $jhash->{'wifi_sta'}{'ssid'} );
  
  #-- for all models set internal temperature reading and status
  if($jhash->{'temperature'}) {
    readingsBulkUpdateMonitored($hash,"inttemp",$jhash->{'temperature'}.$si_units{tempC}[$hash->{units}])
  }elsif($jhash->{'tmp'}{'tC'}) {
    readingsBulkUpdateMonitored($hash,"inttemp",$jhash->{'tmp'}{'tC'}.$si_units{tempC}[$hash->{units}])
  }
                                                                      ; 
  readingsBulkUpdateMonitored($hash,"inttempStatus",$jhash->{'temperature_status'}) 
                                                                      if($jhash->{'temperature_status'}) ;
  readingsBulkUpdateMonitored($hash,"overtemperature",$jhash->{'overtemperature'}) 
                                                                       if($jhash->{'overtemperature'});
  ############################################################################################################################# 
  #-- 1st generation: we have a switch type device and 'relay'-mode, e.g. shelly1, shelly1pm, shelly4, shelly2, shelly2.5, shellyplug or shellyem 
  if( $shelly_models{$model}[0]>0 && $mode ne "roller" ){

    my $metern = ($model =~ /shelly.?em/)?"emeters":"meters";

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
      if( $model ne "shelly4" ){  # readings not supported by Shelly4 v1.5.7
         readingsBulkUpdateMonitored($hash,"timer".$subs,$jhash->{'relays'}[$i]{'timer_remaining'}.$si_units{time}[$hash->{units}]);
         if( $jhash->{'relays'}[$i]{'timer_remaining'}>0 ){
            $intervalN  = minNum($intervalN,$jhash->{'relays'}[$i]{'timer_remaining'});
         }
         $source = $jhash->{'relays'}[$i]{'source'};
         readingsBulkUpdateMonitored($hash,"source".$subs,$source);
      }
    }
    
    #-- we have a shellyuni device 
    if($model eq "shellyuni") {
      my  $voltage = $jhash->{'adcs'}[0]{'voltage'}.$si_units{voltage}[$hash->{units}];
      readingsBulkUpdateMonitored($hash,"voltage",$voltage);
    }
  #############################################################################################################################
  #-- we have a shelly2 or shelly2.5 roller type device
  }elsif( ($model =~ /shelly2(\.5)?/)  && ($mode eq "roller") ){
    Log3 $name,4,"[Shelly_proc1G] device $name with model=$model getting roller state ";
    for( my $i=0;$i<$rollers;$i++){
      $subs = ($rollers == 1) ? "" : "_".$i;
      
      #-- weird data: stop, close or open
      $rstate = $jhash->{'rollers'}[$i]{'state'};
      $rstate =~ s/stop/stopped/;
      $rstate =~ s/close/drive-down/;
      $rstate =~ s/open/drive-up/;
      $hash->{MOVING}   = $rstate;
      $hash->{DURATION} = 0;
      
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
        Log3 $name,5,"[Shelly_proc1G] device $name received roller position $rcurrpos, pct=$pct, position=$position (100% is ".AttrVal($name,"pct100","open").")";

      #-- we have no data from the device 
      }else{
        Log3 $name,3,"[Shelly_proc1G] device $name with model=$model returns no blind position, consider chosing a different model=shelly2/2.5"
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
        Log3 $name,3,"[Shelly_proc1G] device $name: no blind position received from device, we calculate pct=$pct, position=$position"; 
      }
      $rstate = "pct-". 10*int($pct/10+0.5)      if( $rstate eq "stopped" );   # format for state-Reading
      
      readingsBulkUpdateMonitored($hash,"state".$subs,$rstate);
      readingsBulkUpdateMonitored($hash,"pct".$subs,$pct);
      readingsBulkUpdateMonitored($hash,"position".$subs,$position);
      readingsBulkUpdateMonitored($hash,"stop_reason".$subs,$rstopreason);
      readingsBulkUpdateMonitored($hash,"last_dir".$subs,$rlastdir);
    }
  #############################################################################################################################
  #-- we have a shellydimmer or shellyrgbw white device
  }elsif( ($model eq "shellydimmer") || ($model eq "shellyrgbw" && $mode eq "white") ){
    for( my $i=0;$i<$dimmers;$i++){
      $subs = (($dimmers == 1) ? "" : "_".$i);
      $ison = $jhash->{'lights'}[$i]{'ison'};
      $ison =~ s/0|(false)/off/;
      $ison =~ s/1|(true)/on/;
      my $bri    = $jhash->{'lights'}[$i]{'brightness'};

      readingsBulkUpdateMonitored($hash,"pct".$subs,$bri.$si_units{pct}[$hash->{units}]); 
      
      readingsBulkUpdateMonitored($hash,"timer".$subs,$jhash->{'lights'}[$i]{'timer_remaining'}.$si_units{time}[$hash->{units}]);
      if( $jhash->{'lights'}[$i]{'timer_remaining'}>0 ){
        $intervalN  = minNum($intervalN,$jhash->{'lights'}[$i]{'timer_remaining'});
      }
      $source = $jhash->{'lights'}[$i]{'source'};  # 'timer' will occur as 'http'
      readingsBulkUpdateMonitored($hash,"source".$subs,$source); 
      readingsBulkUpdateMonitored($hash,"light".$subs,$ison);  # until 4.09a: "state"
    }
    readingsBulkUpdateMonitored($hash,"state", ($dimmers > 1)?"OK":$ison);
    
  #############################################################################################################################  
  #-- we have a shellybulb or shellyduo in white mode
  }elsif( $model eq "shellybulb" && $mode eq "white" ){
    for( my $i=0;$i<$dimmers;$i++){
      $subs = (($dimmers == 1) ? "" : "_".$i);
      $ison      = $jhash->{'lights'}[$i]{'ison'};
      $ison =~ s/0|(false)/off/;
      $ison =~ s/1|(true)/on/;
      my $bri    = $jhash->{'lights'}[$i]{'brightness'};
      my $ct     = $jhash->{'lights'}[$i]{'temp'};
      readingsBulkUpdateMonitored($hash,"state".$subs,$ison);
      readingsBulkUpdateMonitored($hash,"pct".$subs,$bri.$si_units{pct}[$hash->{units}]);
      readingsBulkUpdateMonitored($hash,"ct".$subs, $ct.$si_units{ct}[$hash->{units}]);
      
      readingsBulkUpdateMonitored($hash,"timer",$jhash->{'lights'}[$i]{'timer_remaining'}.$si_units{time}[$hash->{units}]);
      if( $jhash->{'lights'}[$i]{'timer_remaining'}>0 ){
        $intervalN  = minNum($intervalN,$jhash->{'lights'}[$i]{'timer_remaining'});
      }
      $source = $jhash->{'lights'}[$i]{'source'};   # Source 'timer' not supported by ShellyRGBW in color mode
      readingsBulkUpdateMonitored($hash,"source",$source); 
    }
    readingsBulkUpdateMonitored($hash,"state","OK")
      if($dimmers > 1);#Log3 $name,0,"bulb dimmers $dimmers";
  #############################################################################################################################  
  #-- we have a shellyrgbw color device
  }elsif( $model =~ /shelly(rgbw|bulb)/ && $mode eq "color" ){ 
    $ison       = $jhash->{'lights'}[0]{'ison'};
    $ison =~ s/0|(false)/off/;
    $ison =~ s/1|(true)/on/;
    my $red   = $jhash->{'lights'}[0]{'red'};   # 0 .... 255
    my $green = $jhash->{'lights'}[0]{'green'};
    my $blue  = $jhash->{'lights'}[0]{'blue'};
    my $white = $jhash->{'lights'}[0]{'white'};
    if(0){
        my ($hue,$sat,$bri)  = Color::rgb2hsv($red/255,$green/255,$blue/255);
        Shelly_readingsBulkUpdate($hash,"HSV",sprintf("%d,%4.1f,%4.1f",$hue*360,100*$sat,100*$bri)); # 'hsv' will have interference with widgets for white
    }
    my $gain  = $jhash->{'lights'}[0]{'gain'};  # 0 .... 100
    Shelly_readingsBulkUpdate($hash,"gain",$gain.$si_units{pct}[$hash->{units}]);
    
    if( defined $gain && $gain <= 100 ) { # !=
      $red   = round($red*$gain/100.0  ,0);
      $blue  = round($blue*$gain/100.0 ,0);
      $green = round($green*$gain/100.0,0);
    }
    Shelly_readingsBulkUpdate($hash,"L-red",$red);
    Shelly_readingsBulkUpdate($hash,"L-green",$green);
    Shelly_readingsBulkUpdate($hash,"L-blue",$blue);
    Shelly_readingsBulkUpdate($hash,"L-white",$white);       
    Shelly_readingsBulkUpdate($hash,"rgb",sprintf("%02X%02X%02X", $red,$green,$blue));
    Shelly_readingsBulkUpdate($hash,"rgbw",sprintf("%02X%02X%02X%02X", $red,$green,$blue,$white));

    Shelly_readingsBulkUpdate($hash,"white",round($white/2.55,1).$si_units{pct}[$hash->{units}]);    #percentual value
    readingsBulkUpdateMonitored($hash,"state",$ison);
    
    $intervalN  = $jhash->{'lights'}[0]{'timer_remaining'};
    $source = $jhash->{'lights'}[0]{'source'};
    readingsBulkUpdateMonitored($hash,"timer",$intervalN.$si_units{time}[$hash->{units}]);
    readingsBulkUpdateMonitored($hash,"source",$source); 
  #############################################################################################################################      
  }else{
      Log3 $name,5,"[Shelly_proc1G] Model of device $name is $model and mode is $mode. Updates every ".$hash->{INTERVAL}." seconds. ";
      readingsBulkUpdateMonitored($hash,"state","OK");
  }
  #############################################################################################################################
  #-- common to all models
  my $hasupdate = $jhash->{'update'}{'has_update'};
  my $firmware  = $jhash->{'update'}{'old_version'};
  $firmware     =~ /.*\/(v[0-9.]+(-rc\d|)).*/;
  $firmware     = $1 if( length($1)>5 ); # very old versions don't start with v...
  if( $hasupdate ){
     my $newfw  = $jhash->{'update'}{'new_version'};
     $newfw     =~ /.*\/(v[0-9.]+(-rc\d|)).*/;
     $newfw     = $1; 
     $firmware .= "(update needed to $newfw)";
  }
  readingsBulkUpdateIfChanged($hash,"firmware",$firmware);  
  
  my $hascloud = $jhash->{'cloud'}{'enabled'};
  if( $hascloud ){
    my $hasconn  = ($jhash->{'cloud'}{'connected'}) ? "connected" : "not connected";
    readingsBulkUpdateIfChanged($hash,"cloud","enabled($hasconn)");  
  }else{
    readingsBulkUpdateIfChanged($hash,"cloud","disabled");  
  }
   
  # coiot is updated by the settings call 
  #my $hascoiot = $jhash->{'coiot'}{'enabled'};
  #readingsBulkUpdateIfChanged($hash,"coiot",?"enabled":"disabled");
  
  #readingsBulkUpdateIfChanged($hash,"coiot",defined($jhash->{'coiot'}{'enabled'})?"enabled":"disabled");  
  
 
  #-- looking for metering values; common to all models with at least one metering channel  
  Log3 $name,4,"[Shelly_proc1G] $name: Looking for metering values";
  if( $shelly_models{$model}[3]>0 ){

    #-- Shelly RGBW in color mode has only one metering channel
    $meters = 1   if( $mode eq "color" );

    my $metern = ($model =~ /shelly.?em/)?"emeters":"meters"; 
    my $powerTTL =0;  # we will increment by power value of each channel
    my $energyTTL=0;
    my $returnedTTL=0;
    
    #-----looping all meters of the device
    for( my $i=0;$i<$meters;$i++){
      $subs  = ($meters == 1) ? "" : "_".$i;
      
      #-- for roller devices store last power value (otherwise you mostly see nothing)
      if( $mode eq "roller" ){
          $power = ReadingsNum($name,"power".$subs,0);
          Shelly_readingsBulkUpdate($hash,
             "power_last".$subs,                              # name of reading
             $power.$si_units{power}[$hash->{units}]." ".
             ReadingsVal($name,"last_dir".$subs,""),          # value
             undef,
             ReadingsTimestamp($name,"power".$subs,"") )      # timestamp
                                             if( $power > 0 ); 
      } 
      
      #-- Power is provided by all metering devices, except Shelly1 (which has a power-constant in older fw)
      $power = $jhash->{$metern}[$i]{power};
      readingsBulkUpdateMonitored($hash,"power".$subs,$power.$si_units{power}[$hash->{units}]);
      $powerTTL += $power;
      
      #-- Energy is provided except Shelly1 and Shellybulb/Vintage/Duo, ShellyUni
      if( defined($jhash->{$metern}[$i]{'total'}) ) {
          $energy = $jhash->{$metern}[$i]{'total'};
          $energyTTL += $energy;
          $energy = shelly_energy_fmt($hash,$energy,$model =~ /shelly.?em/ ? "Wh" : "Wm" );
          readingsBulkUpdateMonitored($hash,"energy".$subs,$energy);
          Log3 $name,5,"[Shelly_proc1G] $name $subs: power=$power TTL=$powerTTL, energy=$energy TTL=$energyTTL";
      }
     
      #-- Overpower: power value messured from device as overpowered, otherwise 0 (zero); not provided by all devices
      if( defined($jhash->{$metern}[$i]{'overpower'}) && $model !~ /rgbw/ ){  # 'defined' seems not working properly
          $overpower = $jhash->{$metern}[$i]{'overpower'}; 
          readingsBulkUpdateMonitored($hash,"overpower".$subs,$overpower.$si_units{power}[$hash->{units}]);
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
          #readingsBulkUpdateMonitored($hash,"energy_returned".$subs,shelly_energy_fmt($hash,$energy_returned,"Wh"));
          readingsBulkUpdateMonitored($hash,"energyReturned".$subs,shelly_energy_fmt($hash,$energy_returned,"Wh")); 
      
          my $voltage = $jhash->{$metern}[$i]{'voltage'};
          readingsBulkUpdateMonitored($hash,'voltage'.$subs,$voltage.$si_units{voltage}[$hash->{units}]);
        
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
              readingsBulkUpdateMonitored($hash,'current'.$subs,$current.$si_units{current}[$hash->{units}]);
          }
          $freq = $jhash->{$metern}[$i]{'freq'}; 
          readingsBulkUpdateMonitored($hash,'powerFactor'.$subs,$pfactor);
          readingsBulkUpdateMonitored($hash,'frequency'.$subs,$freq)  if( defined($freq) );   # supported from fw 1.0.0
          readingsBulkUpdateMonitored($hash,'apparentpower'.$subs,$apparentPower.$si_units{apparentpower}[$hash->{units}]);
          readingsBulkUpdateMonitored($hash,'reactivepower'.$subs,$reactivePower.$si_units{reactivepower}[$hash->{units}]);
      }
    }   #-- end looping all meters
    if( $meters>1 ){  #write out values for devices with more than one meter
        if( defined($jhash->{'total_power'}) ){ #not provided by Shelly4 
            readingsBulkUpdateMonitored($hash,"power_TTL",$jhash->{'total_power'}.$si_units{power}[$hash->{units}]);
        }
        readingsBulkUpdateMonitored($hash,"energy_TTL",shelly_energy_fmt($hash,$energyTTL,$model =~ /shelly.?em/ ? "Wh" : "Wm"));
        if( $model =~ /shelly.?em/ ){
          # readingsBulkUpdateMonitored($hash,"energy_returned_TTL",shelly_energy_fmt($hash,$returnedTTL,"Wh"));
            readingsBulkUpdateMonitored($hash,"energyReturned_TTL",shelly_energy_fmt($hash,$returnedTTL,"Wh"));
            #---try to calculate an energy balance
            readingsBulkUpdateMonitored($hash,"Total_Energy",shelly_energy_fmt($hash,$energyTTL-$returnedTTL,"Wh")); 
            #---
            #-- the calculated total power value may be obsolete, if always equal to the read total_power (see above)
            readingsBulkUpdateMonitored($hash,"power_TTLc",$powerTTL.$si_units{power}[$hash->{units}]);
     #   }elsif( $model eq "shellyrgbw" && $mode eq "white" ){  #Shellyrgbw is remaining total power value if state=off and pct>0 & timer>0
          #  readingsBulkUpdateMonitored($hash,"power_TTLc",$powerTTL.$si_units{power}[$hash->{units}]);
        }elsif( $model eq "shelly4" ){  #Shelly4 does not calculate total power value
            readingsBulkUpdateMonitored($hash,"power_TTL",$powerTTL.$si_units{power}[$hash->{units}]);
        }
    }
  }    

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
        Log3 $name,5,"[Shelly_proc1G] $name has input $i with state \"$ison\" ";
        readingsBulkUpdateMonitored($hash,"input".$subs,$ison); # if( $ison );  ## button
        $event = $jhash->{'inputs'}[$i]{'event'};
        $event_cnt = $jhash->{'inputs'}[$i]{'event_cnt'};
        if( $event ){
            readingsBulkUpdateMonitored($hash,"input$subs\_actionS",$event);
            readingsBulkUpdateMonitored($hash,"input$subs\_action",$fhem_events{$event}, 1 );
        }
        #readingsBulkUpdateMonitored($hash,"input$subs\_cnt",$event_cnt,1) if( $event_cnt );
        readingsBulkUpdateMonitored($hash,"input$subs\_cnt",$event_cnt) if( $event_cnt );

        if( defined($jhash->{'inputs'}[$i]{'last_sequence'}) && $jhash->{'inputs'}[$i]{'last_sequence'} eq ""  && $model eq "shellyi3" ){
             # for a shellyi3 with an input configured as TOGGLE this reading is empty 
             fhem("deletereading $name input$subs\_.*");    
        }
        $i++;
      }
  }

  #-- look for external sensors
  if($jhash->{'ext_temperature'}) {
    my %sensors = %{$jhash->{'ext_temperature'}};
    foreach my $temp (keys %sensors){
      readingsBulkUpdateMonitored($hash,"temperature_".$temp,$sensors{$temp}->{'tC'}.$si_units{tempC}[$hash->{units}]); 
    }
  }
  if($jhash->{'ext_humidity'}) {
    my %sensors = %{$jhash->{'ext_humidity'}};
    foreach my $hum (keys %sensors){
      readingsBulkUpdateMonitored($hash,"humidity_".$hum,$sensors{$hum}->{'hum'}.$si_units{relHumidity}[$hash->{units}]); 
    }
  }
  #-- look if name of Shelly has been changed
  if( defined($jhash->{'name'}) ){#&& AttrVal($name,"ShellyName","") ne $jhash->{'name'} ){ #ShellyName  we don't have this reading here!
     readingsBulkUpdateIfChanged($hash,"name",$jhash->{'name'} );
     #$attr{$hash->{NAME}}{ShellyName} = $jhash->{'name'};
  }
  readingsEndUpdate($hash,1);
  
  return $intervalN;
}

########################################################################################
# 
# Shelly_proc2G - process data from device 2nd generation
#                   Necessary because in 2G devices status are per channel
#
########################################################################################
  
sub Shelly_proc2G {
  my ($hash, $comp, $jhash) = @_;
  $hash->{units}=0 if( !defined($hash->{units}) );
  my $name  = $hash->{NAME};
  my $state = $hash->{READINGS}{state}{VAL};  
  my $model = AttrVal($name,"model","generic");
  my $mode  = AttrVal($name,"mode","");
 
  my $channel  = undef; 
     $channel  = $jhash->{'id'}  if( $comp eq "relay" || $comp eq "roller" || $comp eq "input" );
  my $rollers  = $shelly_models{$model}[1];
  my $dimmers  = $shelly_models{$model}[2];
  
  my $meters   = $mode eq "roller" ?  $shelly_models{$model}[1] : $shelly_models{$model}[3];
 # my $meters   = $shelly_models{$model}[3];
 
  my ($subs,$ison,$overpower,$voltage,$current,$power,$energy,$pfactor,$freq,$minutes,$errors);  ##R  minutes errors
  my $timer = $hash->{INTERVAL};

  # check we have a second gen device
  if( $shelly_models{$model}[4]==0 && !$comp ){
        Log3 $name,2,"[Shelly_proc2G] ERROR: calling Proc2G for a not 2ndGen Device";
        return undef;
  }
   
  Log3 $name,4,"[Shelly_proc2G] device $name of model $model processing component $comp"; 
  
  readingsBeginUpdate($hash);
   
  if($shelly_models{$model}[0]>1 && ($shelly_models{$model}[1]==0 || $mode eq "relay")){
          readingsBulkUpdate($hash,"state","OK",1);  #set state for multichannel relay-devices; for rollers state is 'stopped' or 'drive...'
  }    
  ############retrieving the relay state for relay <id>
  if( $shelly_models{$model}[0]>0  &&  $comp eq "relay"){
        Log3 $name,4,"[Shelly_proc2G:relay] Processing relay state for device $name channel/id $channel, comp is $comp"; 
        $subs = ($shelly_models{$model}[0] == 1) ? "" : "_".$channel;
        $ison = $jhash->{'output'};
        $ison =~ s/0|(false)/off/;
        $ison =~ s/1|(true)/on/;
        readingsBulkUpdateMonitored($hash,"relay".$subs,$ison);
        # Switch Reason: Trigger for switching
        # --> init, http <-fhemWEB, WS_in, timer, loopback (=schedule?), HTTP <-Shelly-App
        readingsBulkUpdateMonitored($hash,"source".$subs,$jhash->{'source'});
        
        readingsBulkUpdateMonitored($hash,"state",($shelly_models{$model}[0] == 1)?$ison:"OK");

  ############retrieving the roller state and position
  }elsif( $rollers>0 && $comp eq "roller") {
    Log3 $name,4,"[Shelly_proc2G:roller] Processing roller state for device $name (we have $rollers rollers)"; 
    my ($rsource,$rstate,$raction,$rcurrpos,$rtargetpos,$position,$pct,$pctnormal);
    my $rlastdir = "unknown";
    #for( my $i=0;$i<$rollers;$i++){
      my $id=$jhash->{'id'}; 
      $subs = ($rollers == 1) ? "" : "_".$id;

      #roller: check reason for moving or stopping: http, timeout *), WS_in, limit-switch,obstruction,overpower,overvoltage ...
      #  and safety_switch  (if Safety switch is enabled in Shelly -> see Cover.GetConfig)
      #timeout: either a) calculated moving-time given by target-pos  or b) configured maximum moving time
      $rsource = $jhash->{'source'};
      $rstate = $jhash->{'state'};     # returned values are: stopped, closed, open, closing, opening
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
      $hash->{DURATION} = 0;
      Log3 $name,4,"[Shelly_proc2G] Roller id=$id  action=$raction  state=$rstate  Last dir=$rlastdir";

      #-- for roller devices store last power & current value (otherwise you mostly see nothing)
      if( $mode eq "roller" ){
          $power = ReadingsNum($name,"power".$subs,0);
          Shelly_readingsBulkUpdate($hash,"power_last".$subs, 
             $power.$si_units{power}[$hash->{units}]." ".
             ReadingsVal($name,"last_dir".$subs,""),
             undef,
             ReadingsTimestamp($name,"power".$subs,"") )
                                             if( $power > 0 );
          $current = ReadingsNum($name,"current".$subs,0);
          Shelly_readingsBulkUpdate($hash,"current_last".$subs, 
             $current.$si_units{current}[$hash->{units}]." ".
             ReadingsVal($name,"last_dir".$subs,""),
             undef,
             ReadingsTimestamp($name,"current".$subs,"") )
                                             if( $current > 0 ); 
      }

      # Power in Watts
      $power = $jhash->{'apower'}.$si_units{power}[$hash->{units}];
      readingsBulkUpdateMonitored($hash,"power".$subs,$power);
      Log3 $name,4,"[Shelly_proc2G] Roller reading power$subs=$power";

      #-- open 100% or 0% ?
      $pctnormal = (AttrVal($name,"pct100","open") eq "open");
      
      # Receiving position of Cover, we always receive a current position of the cover, but sometimes position is lost
      if( defined($jhash->{'current_pos'}) ){
          $rcurrpos = $jhash->{'current_pos'};
          $pct = $pctnormal ? $rcurrpos : 100-$rcurrpos;
          $position = ($rcurrpos==100) ? "open" : ($rcurrpos==0 ? "closed" : $pct);  
          $rstate = "pct-". 10*int($pct/10+0.5)     if( $rstate eq "stopped" );   # format for state-Reading 
      }else{
          $pct = "unknown";
          $position = "position lost";
          $rstate = "Error: position";
      }

      Log3 $name,4,"[Shelly_proc2G] Roller id=$id  position is $position $pct";
      readingsBulkUpdateMonitored($hash,"pct".$subs,$pct);
      readingsBulkUpdateMonitored($hash,"position".$subs,$position);
      readingsBulkUpdateMonitored($hash,"state".$subs,$rstate);

  ############retrieving EM power values rpc/EM.GetStatus?id=0
  }elsif($comp eq "EM"){
      Log3 $name,4,"[Shelly_proc2G:EM] Processing Power Metering (EM) state for device $name";
      my $suffix =  AttrVal($name,"EMchannels","_ABC");
      
      my ($pr,$ps,$reading,$value);
      my ($power,$aprt_power,$reactivePower);
      
      foreach my $emch ( "a_","b_","c_","total_" ){
        if( $suffix eq "ABC_" || $suffix eq "L123_" ){
          $pr=$mapping{sf}{$suffix}{$emch};
          $ps="";
        }else{
          $pr="";
          $ps=$mapping{sf}{$suffix}{$emch};
        }  
          $reading=$pr.$mapping{E1}{current}.$ps;
          $value  =sprintf("%5.3f%s",$jhash->{$emch.'current'},$si_units{current}[$hash->{units}]);
          readingsBulkUpdateMonitored($hash,$reading,$value);

          $reading=$pr.$mapping{E1}{aprt_power}.$ps;
          $aprt_power=$jhash->{$emch.'aprt_power'};
          $value  =sprintf("%4.1f%s",$jhash->{$emch.'aprt_power'}, $si_units{apparentpower}[$hash->{units}] );
          readingsBulkUpdateMonitored($hash,$reading,$value); 
                  
          $reading=$pr.$mapping{E1}{act_power}.$ps;
          $power=$jhash->{$emch.'act_power'};
          $value  =sprintf("%5.1f%s",$jhash->{$emch.'act_power'}, $si_units{power}[$hash->{units}] );
          readingsBulkUpdateMonitored($hash,$reading,$value); # store this also as helper
if(0){    # check calculation of reactive power!
          $reading=$pr.$mapping{E1}{react_power}.$ps;
          $value = ($aprt_power * $aprt_power) - ($power * $power);
          $reactivePower = ($value<=>0)*sqrt( abs($value) );
          $value = sprintf("%4.1f%s",$reactivePower, $si_units{reactivepower}[$hash->{units}] );
          readingsBulkUpdateMonitored($hash,$reading,$value);
}          
          if($emch ne "total_"){
            # to get latest values when calculating total pushed value
            $hash->{helper}{$emch.'Active_Power'}=$jhash->{$emch.'act_power'}; 

            $reading=$pr.$mapping{E1}{voltage}.$ps;
            $value  =sprintf("%4.1f%s",$jhash->{$emch.'voltage'},$si_units{voltage}[$hash->{units}]);
            readingsBulkUpdateMonitored($hash,$reading,$value);
            
            $reading=$pr.$mapping{E1}{pf}.$ps;
            $value = $jhash->{$emch.'pf'};
            $value = sprintf("%4.2f%s",abs($value),( abs($value)==1?"":" (".( $value<0 ? $mapping{E1}{cap}:$mapping{E1}{ind}).")"));
            readingsBulkUpdateMonitored($hash,$reading,$value);
            
            $reading=$pr.$mapping{E1}{frequency}.$ps;
            $value = $jhash->{$emch.'freq'};
            readingsBulkUpdateMonitored($hash,$reading,$value.$si_units{frequency}[$hash->{units}]) if( defined($value) );  # supported from fw 1.0.0
            
            $power += $jhash->{$emch.'act_power'};
          }
      }

      ### Balancing: cumulate power values and save them in helper, will be used by Shelly_EMData()
      $hash->{helper}{powerCnt}++;
      $hash->{helper}{power} += $power;
      $hash->{helper}{powerPos} += $power if($power>0);
      $hash->{helper}{powerNeg} -= $power if($power<0);  # the cumulated value is positive!

      readingsBulkUpdateMonitored($hash,"state","OK");
    

  ############retrieving input states rpc/Input.GetStatus?id=<id>
  }elsif( $comp eq "input" ){
        Log3 $name,4,"[Shelly_proc2G:input] Processing input state for device $name channel/id $channel"; 
        $subs = ($shelly_models{$model}[5] == 1) ? "" : "_".$channel;
        $ison = defined($jhash->{'state'})?$jhash->{'state'}:"unknown";
        $ison =~ s/0|(false)/off/;
        $ison =~ s/1|(true)/on/;
        readingsBulkUpdateMonitored($hash,"input".$subs,$ison);

  }elsif( $comp eq "status" ){
       #processing the answer rpc/Shelly.GetStatus from shelly_shelly():
       Log3 $name,4,"[Shelly_proc2G:status] $name: Processing the answer rpc/Shelly.GetStatus from Shelly_shelly()";
         # in this section we read (as far as available): 
         #  cloud:connected:
         #  sys:available_updates:stable:version
         #  sys:available_updates:beta:version
         #  eth:ip:
         #  wifi:sta_ip:
         #  wifi:status:
         #  wifi:ssid:
         #  wifi:rssi:
         #  input:$i:id:
         #  input:$i:state:

       #checking if cloud is connected 
       #Note: check if cloud is allowed will result from configuration
       if(ReadingsVal($name,"cloud","none") !~ /disabled/){
         my $hasconn  = ($jhash->{'cloud'}{'connected'});
         Log3 $name,5,"[Shelly_proc2G:status] $name: hasconn=" . ($hasconn?"true":"false");
         $hasconn = $hasconn ? "connected" : "not connected"; 
         readingsBulkUpdateIfChanged($hash,"cloud","enabled($hasconn)");  
       }
       #checking if updates are available
       # /rpc/Shelly.GetDeviceInfo/fw_id
       #                          /ver       firmware version
       #                          /name      name of Shelly
       # /rpc/Shelly.GetConfig/sys:device:fw_id
       # /rpc/Shelly.GetStatus/sys:available_updates:beta:version     only when there is a beta version 
       # /rpc/Shelly.GetStatus/available_updates {} 
       my $update = $jhash->{'sys'}{'available_updates'}{'stable'}{'version'};
       my $firmware = ReadingsVal($name,"firmware","none");  # eg  1.2.5(update....
       if( $firmware =~ /^(.*?)\(/ ){
           $firmware = $1;
       }
       my $txt = ($firmware =~ /beta/ )?"update possible to latest stable v":"update needed to v";
       if( $update ){   #stable
              Log3 $name,5,"[Shelly_proc2G:status] $name: $txt$update   current in device: $firmware";
              $firmware .= "($txt$update)";
              readingsBulkUpdateIfChanged($hash,"firmware",$firmware);  
       }else{ # maybe there is a beta version available
          $update = $jhash->{'sys'}{'available_updates'}{'beta'}{'version'};
          if( $update ){
              Log3 $name,5,"[Shelly_proc2G:status] $name: $firmware --> $update beta";
              $firmware .= "(update possible to v$update beta)";
              readingsBulkUpdateIfChanged($hash,"firmware",$firmware);  
          }
       }
   
       #checking if connected to wifi / LAN
       #is similiar given as answer to rpc/Wifi.GetStatus
       
       my $eth_ip    = $jhash->{'eth'}{'ip'}    ? $jhash->{'eth'}{'ip'}    : "-";
       my $wifi_ssid = $jhash->{'wifi'}{'ssid'} ? $jhash->{'wifi'}{'ssid'} : "-";
       my $wifi_rssi = ($jhash->{'wifi'}{'rssi'} ? $jhash->{'wifi'}{'rssi'} : "-");
       readingsBulkUpdateIfChanged($hash,"network_ssid",$wifi_ssid);
       readingsBulkUpdateIfChanged($hash,"network_rssi",Shelly_rssi($hash,$wifi_rssi) );
       
       #my $wifi_status= $jhash->{'wifi'}{'status'};  # sometimes not supported by ShellyWallDisplay fw 1.2.4
       if( $eth_ip ne "-" && $wifi_ssid ne "-" ){
           readingsBulkUpdateIfChanged($hash,"network","<html>connected to <a href=\"http://".$eth_ip."\">".$eth_ip."</a> (LAN, Wifi)</html>");
       }elsif( $eth_ip ne "-" && $wifi_ssid eq "-" ){ 
           readingsBulkUpdateIfChanged($hash,"network","<html>connected to <a href=\"http://".$eth_ip."\">".$eth_ip."</a> (LAN)</html>");
       }elsif( $eth_ip eq "-" && $wifi_ssid ne "-" ){
              my $wifi_ip   = $jhash->{'wifi'}{'sta_ip'};
              readingsBulkUpdateIfChanged($hash,"network","<html>connected to <a href=\"http://".$wifi_ip."\">".$wifi_ip."</a> (Wifi)</html>");
       }else{
              Shelly_error_handling($hash,"Shelly_proc2G:status","not connected");
       }
       Log3 $name,4,"[Shelly_proc2G:status] $name ethernet=$eth_ip,wifi=$wifi_ssid @ $wifi_rssi";
       
    #Inputs in button-mode (Taster) CANNOT be read out! 
    #Inputs of cover devices are strongly attached to the device.
    #Following we assume that number of inputs is equal to number of relays.
    my ($subs, $ison);
    my $i=0;
    if( AttrVal($name,"showinputs","show") eq "show" && $shelly_models{$model}[5]>0 ){

      while( defined($jhash->{"input:$i"}{'id'}) ){ 
        $subs = $shelly_models{$model}[5]==1?"":"_$i";
        $ison = $jhash->{"input:$i"}{'state'};
        $ison = "unknown" if( !defined($ison) );
        $ison = "unknown" if(  length($ison)==0 );
        $ison =~ s/0|(false)/off/;
        $ison =~ s/1|(true)/on/;
        Log3 $name,5,"[Shelly_proc2G:status] $name has input $i with state $ison";
        readingsBulkUpdateMonitored($hash,"input".$subs,$ison) if( $ison );
        $i++;
      }
      readingsBulkUpdateMonitored($hash,"state","OK") if( $model eq "shellyplusi4" );
    }
    
    # ********
    if( $model =~ /walldisplay/ ){
            $subs ="";
            # readings supported by the /Shelly.GetStatus call or by individual calls eg /Temperature.GetStatus
            readingsBulkUpdateMonitored($hash,"temperature" .$subs,$jhash->{'temperature:0'}{'tC'}.$si_units{tempC}[$hash->{units}] );
            readingsBulkUpdateMonitored($hash,"humidity"    .$subs,$jhash->{'humidity:0'}{'rh'}.$si_units{relHumidity}[$hash->{units}] );
            readingsBulkUpdateMonitored($hash,"illuminance" .$subs,$jhash->{'illuminance:0'}{'lux'}.$si_units{illum}[$hash->{units}] );
            readingsBulkUpdateMonitored($hash,"illumination".$subs,$jhash->{'illuminance:0'}{'illumination'} );        
    }
    # ********
    # look for sensor addon
    my $t=100;
    while( $jhash->{"temperature:$t"}{id} ){
       $subs = "_".($jhash->{"temperature:$t"}{id}-100);
       readingsBulkUpdateMonitored($hash,"temperature" .$subs,$jhash->{"temperature:$t"}{'tC'}.$si_units{tempC}[$hash->{units}] );
       $t++;
    }
    
    ################ Shelly.GetConfig
    }elsif($comp eq "config"){
        Log3 $name,4,"[Shelly_proc2G:config] $name: processing the answer rpc/Shelly.GetConfig from Shelly_shelly()";

        #Cloud
        my $hascloud = $jhash->{'cloud'}{'enable'};
        Log3 $name,5,"[Shelly_proc2G:config] $name: hascloud=" . ($hascloud?"true":"false");
        if(!$hascloud ){  # cloud disabled
             readingsBulkUpdateIfChanged($hash,"cloud","disabled");
        }elsif(ReadingsVal($name,"cloud","none") !~ /enabled/){
             readingsBulkUpdateIfChanged($hash,"cloud","enabled");
        }
        #show Wifi roaming threshold only when connected via wifi
        if( $jhash->{'wifi'}{'roam'}{'rssi_thr'} && ReadingsVal($name,"network_ssid","-") ne "-"){
             readingsBulkUpdateIfChanged($hash,"network_threshold",$jhash->{'wifi'}{'roam'}{'rssi_thr'}.$si_units{rssi}[$hash->{units}]);
        }

        #Inputs: settings regarding the input 
        if( AttrVal($name,"showinputs","show") eq "show" && $shelly_models{$model}[5]>0 ){
          my $profile = $jhash->{'sys'}{'device'}{'profile'};  # switch, cover
          $profile = "switch" if( !$profile ) ;
          my ($subs, $input);
          my ($invert,$in_mode, $in_swap);
          my $i=0;

          while( defined($jhash->{"input:$i"}{'id'}) ){
            $subs = $shelly_models{$model}[5]==1?"":"_$i";
            $input   = $jhash->{"input:$i"}{'type'}; 
            $invert  = $jhash->{"input:$i"}{'invert'};    
            $invert  =~ s/0/straight/;   # 0=(false)  = not inverted
            $invert  =~ s/1/inverted/;   # 1=(true)
            $input  .= " $invert";
            if( $profile eq "cover"){
                my $ii = int($i/2);
                $in_mode = $jhash->{"$profile:$ii"}{'in_mode'};  # cover: single, dual, detached
                $in_swap = $jhash->{"cover:$ii"}{'swap_inputs'};   
                $in_swap =~ s/0/normal/;   # 0=(false)  = not swapped
                $in_swap =~ s/1/swapped/;   # 1=(true)
                $input  .= " $in_mode $in_swap";
            }elsif( $model ne "shellyi4" ){
                $in_mode = $jhash->{"$profile:$i"}{'in_mode'};  # switch: follow, detached
                $input  .= " $in_mode"   if( defined($in_mode) );
            }
            #$input = "$in_type $invert $in_mode $in_swap";
            $input  .= " disabled" if( $jhash->{"input:$i"}{'enable'} && ($jhash->{"input:$i"}{'enable'})==0 );
            Log3 $name,5,"[Shelly_proc2G:config] $name has input $i: $input"; 
            readingsBulkUpdateMonitored($hash,"input$subs\_mode",$input) if( $input );
            readingsBulkUpdateMonitored($hash,"input$subs\_name",$jhash->{"input:$i"}{'name'}) if( $jhash->{"input:$i"}{'name'} );
            $i++;
          }
        }
        # look if an addon is present: 
        if( $jhash->{'sys'}{'device'}{'addon_type'} ){
            readingsBulkUpdateMonitored($hash,"addon",$jhash->{'sys'}{'device'}{'addon_type'} );
        }elsif(ReadingsVal($name,"addon",undef)){
            fhem("deletereading $name addon");
        }

    ################ Shelly.GetDeviceInfo          
    }elsif($comp eq "info"){
      Log3 $name,4,"[Shelly_proc2G:info] $name: processing the answer rpc/Shelly.GetDeviceInfo from Shelly_shelly()";
     
       $hash->{SHELLYID}=$jhash->{'id'};
       #my $firmware_ver   = $jhash->{'fw_id'};
       my $fw_shelly  = $jhash->{'ver'};   # the firmware information stored in the Shelly

       my $fw_fhem = ReadingsVal($name,"firmware","none"); # the firmware information that fhem knows

       $fw_fhem  =~ /v([^\(]*)\K(.*)/; 
       $fw_fhem  = $1; 
       if( $fw_fhem eq $fw_shelly ){       
          Log3 $name,4,"[Shelly_proc2G:info] $name: info about current firmware Shelly and Fhem are matching: $fw_shelly";
       }else{
          Log3 $name,4,"[Shelly_proc2G:info] $name: new firmware information read from Shelly: $fw_shelly";  
          readingsBulkUpdateIfChanged($hash,"firmware","v$fw_shelly");
       } 
       if( defined($jhash->{'name'}) ){##&& AttrVal($name,"ShellyName","") ne $jhash->{'name'}) {  #ShellyName 
           readingsBulkUpdateIfChanged($hash,"name",$jhash->{'name'} );
       #    $attr{$hash->{NAME}}{ShellyName} = $jhash->{'name'}; 
       }else{ 
           # if Shelly is not named, set name of Shelly equal to name of Fhem-device
           ##fhem("set $name name " . $name ); 
       #    $attr{$hash->{NAME}}{ShellyName} = $name;  #set ShellyName as attribute
       }
    ################ /settings          
    }elsif($comp eq "settings"){
      Log3 $name,4,"[Shelly_proc2G:settings] $name: processing the answer /settings from Shelly_shelly()";#4
           readingsBulkUpdateIfChanged($hash,"coiot",defined($jhash->{'coiot'}{'enabled'})?"enabled":"disabled"); 
           readingsBulkUpdateIfChanged($hash,"coiot_period",
                       defined($jhash->{'coiot'}{'update_period'})?$jhash->{'coiot'}{'update_period'}.$si_units{time}[$hash->{units}]:"disabled");
           readingsBulkUpdateIfChanged($hash,"network_threshold",$jhash->{'ap_roaming'}{'threshold'}.$si_units{rssi}[$hash->{units}])
                                               if( defined($jhash->{'ap_roaming'}{'threshold'}) );
      
           readingsBulkUpdateIfChanged($hash,"name",$jhash->{'name'} ) if( defined($jhash->{'name'}) );  # ShellyName 
    }
    #############################################################################################################################
    #-- common to roller and relay, also ShellyPMmini energymeter
    if($comp eq "roller" || $comp eq "relay" || $comp eq "pm1" ){
      my $id  = $jhash->{'id'};
      $subs = ( $mode eq "roller" ? $shelly_models{$model}[1] : $shelly_models{$model}[3])==1?"":"_$id";
      Log3 $name,4,"[Shelly_proc2G] $name: Processing metering channel$subs";
      if( $meters > 0 ){
        #checking for errors (if present)
        $errors  = $jhash->{'errors'}[0];
        $errors = "none" 
           if(!$errors);
        #readingsBulkUpdateMonitored($hash,"errors".$subs,$errors);
        
        $voltage = $jhash->{'voltage'}.$si_units{voltage}[$hash->{units}];
        $current = $jhash->{'current'}.$si_units{current}[$hash->{units}];
        $power   = $jhash->{'apower'} .$si_units{power}[$hash->{units}];   # active power

        $energy  = $jhash->{'aenergy'}{'total'};
        # Energy consumption by minute (in Milliwatt-hours) for the last minute
        $minutes = shelly_energy_fmt($hash,$jhash->{'aenergy'}{'by_minute'}[0],"mWh"); # is cumulated while minute restarts
      
        Log3 $name,4,"[Shelly_proc2G] $name $comp voltage$subs=$voltage, current$subs=$current, power$subs=$power";  #4
       
        readingsBulkUpdateMonitored($hash,"voltage".$subs,$voltage);  
        readingsBulkUpdateMonitored($hash,"current".$subs,$current);  
        readingsBulkUpdateMonitored($hash,"power"  .$subs,$power);
        # PowerFactor not supported by ShellyPlusPlugS, ShellyPMmini and others
        readingsBulkUpdateMonitored($hash,"pfactor".$subs,$jhash->{'pf'}) if( defined($jhash->{'pf'}) );
        
        # frequency supported from fw 1.0.0 
        readingsBulkUpdateMonitored($hash,"frequency".$subs,$jhash->{'freq'}.$si_units{frequency}[$hash->{units}])
                                                                          if( defined($jhash->{'freq'}) ); 
        
        readingsBulkUpdateMonitored($hash,"energy" .$subs,shelly_energy_fmt($hash,$energy,"Wh"));  
        #readingsBulkUpdateMonitored($hash,"energy_lastMinute".$subs,$minutes); 
        readingsBulkUpdateMonitored($hash,"protection".$subs,$errors);
        readingsBulkUpdateMonitored($hash,"state",$power) if($model eq "shellypmmini");
        
      }  
      # temperature not provided by all devices
      if( defined($jhash->{'temperature'}{'tC'}) ){
            readingsBulkUpdateMonitored($hash,"inttemp",$jhash->{'temperature'}{'tC'}.$si_units{tempC}[$hash->{units}]);
      }elsif( defined($jhash->{'temperature:0'}{'tC'}) ){
            readingsBulkUpdateMonitored($hash,"inttemp",$jhash->{'temperature:0'}{'tC'}.$si_units{tempC}[$hash->{units}]);
      }
      # processing timers
      if( $jhash->{'timer_started_at'} ){
         if( $jhash->{'timer_remaining'} ){         
            $timer = $jhash->{'timer_remaining'};
         }else{
            $timer =  $jhash->{'timer_started_at'} + $jhash->{'timer_duration'} - time();
            $timer =  round($timer,1);
         }
         readingsBulkUpdateMonitored($hash,"timer".$subs,$timer.$si_units{time}[$hash->{units}]); 
      }elsif(ReadingsVal($name,"timer$subs",undef) ){
         readingsBulkUpdateMonitored($hash,"timer".$subs,'-');
      }
      #---
      #calculate all periods
      my @TPs=split(/,/x, AttrVal($name,"Periods", "") );
      #$unixtime = $unixtime-$unixtime%60;  # adjust to lass full minute  
      my $unixtime = time();
      #$TimeStamp = FmtDateTime($unixtime-$unixtime%60); # adjust to lass full minute
      my $TimeStamp = FmtDateTime( time() );
      foreach my $TP (@TPs)
      {
           Log3 $name,5,"[Shelly__proc2G:status] $name: calling shelly_delta_energy for period \'$TP\' ";
           shelly_delta_energy($hash,"energy_",$TP,$unixtime,$energy,$TimeStamp,fhem('{$isdst}'));
      }
      #---
    }
    readingsEndUpdate($hash,1);
    
    if($comp eq "status" || $comp eq "config" || $comp eq "info"){
       return -1;
    }else{
       return $timer;
    }
  }



     
########################################################################################
#
# Shelly_EMData - process EM Energy Data 
#
# Parameter hash, ...
#
########################################################################################
sub Shelly_EMData {
  my ($hash, $comp, $err, $data) = @_;
  $hash->{units}=0 if( !defined($hash->{units}) );
  my $name  = $hash->{NAME};
  my $state = $hash->{READINGS}{state}{VAL};  
  my $model = AttrVal($name,"model","generic");

  # check we have a second gen device
  if( $shelly_models{$model}[4]==0 || $model ne "shellypro3em" ){
        return "$name ERROR: calling Proc2G for a not 2ndGen Device";
  }

  if( $hash && !$err && !$data ){
    if( $model eq "shellypro3em" ){
          $comp = "EMData";
    }
    # my $url     = "http://".Shelly_pwd($hash).$hash->{TCPIP}."/rpc/$comp.GetStatus?id=0";
    my $url     = "http://".Shelly_pwd($hash).$hash->{TCPIP}."/rpc/Shelly.GetStatus";   # all data in one loop
    Log3 $name,4,"[Shelly_EMData] issue a non-blocking call to $url";
    HttpUtils_NonblockingGet({
        url      => $url,
        timeout  => AttrVal($name,"timeout",4),
        callback => sub($$$){ Shelly_EMData($hash,$comp,$_[1],$_[2]) }
      });
    return undef;
  }else{
    #-- cyclic update nevertheless
    RemoveInternalTimer($hash,"Shelly_EMData"); 
    # adjust timer to one second after full minute
    my $Tupdate = int((time()+60)/60)*60+1;
    Log3 $name,4,"[Shelly_EMData] $name: next EMData update at $Tupdate = ".strftime("%H:%M:%S",localtime($Tupdate) )." Timer is Shelly_EMdata";
    InternalTimer($Tupdate, "Shelly_EMData", $hash, 1)
      if( $hash->{INTERVAL} != 0 );
  }

  #-- error in non blocking call  
  if( $hash && $err ){
    Shelly_error_handling($hash,"Shelly_EMData",$err);
    return $err;
  }

  Log3 $name,5,"[Shelly_EMData] device $name has returned data $data";
  
  # extracting json from data
  readingsBeginUpdate($hash);    
  my $json = JSON->new->utf8;
  my $jhash = eval{ $json->decode( $data ) };
  
  #-- error in data
  if( !$jhash ){
    Shelly_error_handling($hash,"Shelly_EMData","invalid JSON data");
    return;
  }
 
  my $channel  = $jhash->{'id'};
  my $meters   = $shelly_models{$model}[3];
 
  my ($subs,$ison,$overpower,$voltage,$current,$power,$energy,$pfactor,$freq,$minutes,$errors);  ##R  minutes errors

    ############retrieving EM data   
    if( $model eq "shellypro3em" ){
    
        #  Here we have some coding regarding the reading-names
        my $suffix =  AttrVal($name,"EMchannels","_ABC");
        my ($pr,$ps,$reading,$value,$errors);
        my ($active_energy,$return_energy,$deltaEnergy,$deltaAge,$unixtime,$TimeStamp);
      
        $unixtime = $jhash->{'sys'}{'unixtime'};
        readingsBulkUpdateMonitored($hash,"timestamp",strftime("%Y-%m-%d %H:%M:%S",localtime($unixtime) ) );
 
        # Energy Readings are calculated by the Shelly every minute, matching "zero"-seconds
        # with some processing time the result will appear in fhem some seconds later
        # we adjust the Timestamp to Shellies time of calculation and use a propretary version of the 'readingsBulkUpdateMonitored()' sub
        $TimeStamp = FmtDateTime($unixtime-$unixtime%60); # adjust to lass full minute
        #--- looping all phases
        foreach my $emch ( "a_","b_","c_","total_" ){
          if( $suffix eq "ABC_" ||  $suffix eq "L123_" ){
            $pr=$mapping{sf}{$suffix}{$emch};
            $ps="";
          }else{
            $pr="";
            $ps=$mapping{sf}{$suffix}{$emch};
          }
          foreach my $flow ("act","act_ret"){
            if( $emch ne "total_" ){
              $reading = $pr.$mapping{E1}{'total_'.$flow.'_energy'}.$ps;
              $value = $jhash->{'emdata:0'}{$emch.'total_'.$flow.'_energy'};
            }else{          # processing total_ values
              $reading = $pr.$mapping{E1}{$flow}.$ps;
              $value = $jhash->{'emdata:0'}{'total_'.$flow};
              if( $flow eq "act" ){
                  $active_energy = $value;
              }else{
                  $return_energy = $value;
              }
            }
            $value = shelly_energy_fmt($hash,$value,"Wh");
            Shelly_readingsBulkUpdate($hash,$reading,$value,undef,$TimeStamp);
          } 
          # checking for errors
          # may contain:  power_meter_failure, no_load
          if( defined($jhash->{'em:0'}{$emch.'errors'}[0]) ){
              #$errors  = $jhash->{'em:0'}{$emch.'errors'}[0];
              #$errors .= "$pr$ps: $errors " if( defined($errors) );
              $errors .= "$pr$ps: ".$jhash->{'em:0'}{$emch.'errors'}[0];
          }   
        }
        # checking for EM-system errors
        # may contain:  power_meter_failure, phase_sequence, no_load
        if( $jhash->{'em:0'}{'errors'}[0] ){
              $errors .= "System: ".$jhash->{'em:0'}{'errors'}[0];
        }
        readingsBulkUpdateMonitored($hash,"errors",defined($errors)?$errors:"OK");
        
        $value = $jhash->{'temperature:0'}{'tC'}.$si_units{tempC}[$hash->{units}];
        readingsBulkUpdateMonitored($hash,"inttemp",$value);

        #initialize helper values to avoid error in first run 
        if( !defined( $hash->{helper}{timestamp_last} ) ){
          $hash->{helper}{timestamp_last} = $unixtime - 60;
          $hash->{helper}{Total_Energy_S}=0;
          $hash->{helper}{powerPos} = 0;
          $hash->{helper}{powerNeg} = 0;
        }   
        
     ### processing calculated values ###
     ### 1. calculate Total Energy
        $value = shelly_energy_fmt($hash,$active_energy - $return_energy,"Wh");
        Shelly_readingsBulkUpdate($hash,"Total_Energy_S",$value,undef,$TimeStamp);
     
     ### 2. calculate a power value from the difference of Energy measures
        $deltaAge = $unixtime - $hash->{helper}{timestamp_last};
        $hash->{helper}{timestamp_last} = $unixtime;
        
        $deltaEnergy  = $active_energy - $return_energy - $hash->{helper}{Total_Energy_S};
        $hash->{helper}{Total_Energy_S} =$active_energy-$return_energy;
             
        $reading = $pr.$mapping{E1}{"act_calculated"}; # Active_Power_calculated
        $value  = sprintf("%4.1f",3600*$deltaEnergy/$deltaAge) if( $deltaAge>0 );  # this is a Power value in Watts.
        $value .= $si_units{power}[$hash->{units}]; 
        $value .= sprintf(" \( %d Ws = %5.2f Wh in %d s \)",3600*$deltaEnergy,$deltaEnergy,$deltaAge);
        Shelly_readingsBulkUpdate($hash,$reading,$value,undef,$TimeStamp);

     ### 3. calculate Energy-differences for a set of different periods
        #prepare the list of periods
        my @TPs=split(/,/x, AttrVal($name,"Periods", "") );
        
        #calculate all periods
        my $dst = fhem('{$isdst}'); # is daylight saving time (Sommerzeit) ?   gets a log entry {$isdst} at level 3
        $unixtime = $unixtime-$unixtime%60;  # adjust to lass full minute
        foreach my $TP (@TPs){
           Log3 $name,5,"[Shelly__proc2G:status] calling shelly_delta_energy for period \'$TP\' ";
           # Shellie'S Energy value 'S'
           shelly_delta_energy($hash,"Total_Energy_S_",    $TP,$unixtime,$active_energy-$return_energy,$TimeStamp,$dst);
           shelly_delta_energy($hash,"Purchased_Energy_S_",$TP,$unixtime,$active_energy,$TimeStamp,$dst);
           shelly_delta_energy($hash,"Returned_Energy_S_", $TP,$unixtime,$return_energy,$TimeStamp,$dst);
        }


     
        if( AttrVal($name,"Balancing",1) == 1 && $hash->{helper}{powerCnt} ){   # don't divide by zero
        
      ### 4. calculate a power value by integration of single power values
      ### calculate purchased and returned Energy out of integration of positive and negative power values
          my ($mypower,$mypowerPos,$mypowerNeg)=(0,0,0);
          my ($active_energy_i,$return_energy_i);
          $mypower = sprintf("%4.1f %s (%d values)", $hash->{helper}{power}/$hash->{helper}{powerCnt},
                                                    $si_units{power}[$hash->{units}],$hash->{helper}{powerCnt} );
          $mypowerPos = $hash->{helper}{powerPos} / $hash->{helper}{powerCnt};
          $mypowerNeg = $hash->{helper}{powerNeg} / $hash->{helper}{powerCnt};
            
          $hash->{helper}{Energymeter_P}=1000*ReadingsNum($name,"Purchased_Energy_T",ReadingsNum($name,"Purchased_Energy_S",0))
          	unless( $hash->{helper}{Energymeter_P} ); #$active_energy;
          $hash->{helper}{Energymeter_R}=1000*ReadingsNum($name,"Returned_Energy_T", ReadingsNum($name,"Returned_Energy_S", 0))
                unless( $hash->{helper}{Energymeter_R} ); #=$return_energy;

          $active_energy_i = $mypowerPos/60 + $hash->{helper}{Energymeter_P};    # Energy in Watthours
          $return_energy_i = $mypowerNeg/60 + $hash->{helper}{Energymeter_R};
          Log3 $name,6,"[a] integrated Energy= $active_energy_i   $return_energy_i   in Watthours";
          $mypowerPos = sprintf("%4.1f %s (%d Ws = %5.2f Wh)", $mypowerPos,$si_units{power}[$hash->{units}],$mypowerPos*60,$mypowerPos/60 );
          $mypowerNeg = sprintf("%4.1f %s (%d Ws = %5.2f Wh)", $mypowerNeg,$si_units{power}[$hash->{units}],$mypowerNeg*60,$mypowerNeg/60);
          # don't write out when not calculated
          readingsBulkUpdateMonitored($hash,$pr.$mapping{E1}{act_integrated},$mypower);
          readingsBulkUpdateMonitored($hash,$pr.$mapping{E1}{act_integratedPos},$mypowerPos);
          readingsBulkUpdateMonitored($hash,$pr.$mapping{E1}{act_integratedNeg},$mypowerNeg);

      # 5. reset helper values. They will be set while cyclic update of power values. A small update interval is necessary!
          $hash->{helper}{power} = 0;
          $hash->{helper}{powerPos} = 0;
          $hash->{helper}{powerNeg} = 0;
          $hash->{helper}{powerCnt} = 0;  
                
     ### 6. safe these values for later use, independent of readings format, in Wh.
          # We need them also to adjust the offset-attribute, see Shelly_attr():
          $hash->{helper}{Energymeter_P}=$active_energy_i;
          $hash->{helper}{Energymeter_R}=$return_energy_i;
 
        # 7. calculate the suppliers meter value
          foreach my $EM ( "F","P","R" ){
            if( defined(AttrVal($name,"Energymeter_$EM",undef)) ){
               $reading = "Total_Energymeter_$EM";
               if( $EM eq "P" ){
                  $value = $active_energy_i;
               }elsif( $EM eq "R" ){
                  $value = $return_energy_i;
               }elsif( $EM eq "F" ){
                  $value = $active_energy_i-$return_energy_i;
               }
               # next line we need because additon works not properly!!!
               $value = sprintf("%7.4f",$value+AttrVal($name,"Energymeter_$EM",50000));
               $value = shelly_energy_fmt($hash, $value,"Wh");
               Shelly_readingsBulkUpdate($hash,"Total_Energymeter_$EM", $value, undef, $TimeStamp);
            }
          } 
        
     ### 8. write out actual balanced meter values
          readingsBulkUpdateMonitored($hash,"Purchased_Energy_T",shelly_energy_fmt($hash,$active_energy_i,"Wh"), undef, $TimeStamp);
          readingsBulkUpdateMonitored($hash,"Returned_Energy_T", shelly_energy_fmt($hash,$return_energy_i,"Wh"), undef, $TimeStamp);
          readingsBulkUpdateMonitored($hash,"Total_Energy_T",    shelly_energy_fmt($hash,$active_energy_i-$return_energy_i,"Wh"), undef, $TimeStamp);

     ### 9. calculate Energy-differences for a set of different periods
          foreach my $TP (@TPs){
              # integrated (balanced) energy values 'T'
              shelly_delta_energy($hash,"Total_Energy_T_",    $TP,$unixtime,$active_energy_i-$return_energy_i,$TimeStamp,$dst); # $return_energy is positive
              shelly_delta_energy($hash,"Purchased_Energy_T_",$TP,$unixtime,$active_energy_i,$TimeStamp,$dst);
              shelly_delta_energy($hash,"Returned_Energy_T_", $TP,$unixtime,$return_energy_i,$TimeStamp,$dst);
          } 
        }
    }
    readingsEndUpdate($hash,1);
    return undef;
}
     
########################################################################################
#
# shelly_delta_energy - calculate energy for a periode 
#
# Parameter hash, 
#           reading     name of the reading of the energy-counter
#           TP          time periode like 'hourQ'
#           unixtime    epochtime, read from the shelly, adjusted to the last full minute 
#           energy      value of the energy-counter, in Watt-hours (Wh)
#           TimeStamp   timestamp adjusted to the last full minute
#           dst         daylight savings time
#
########################################################################################
sub shelly_delta_energy {
  my ($hash,$reading,$TP,$unixtime,$energy,$TimeStamp,$dst) = @_;#Debug "$unixtime,$energy,$TimeStamp";
  
  my ($energyOld,$denergy,$timestampRef,$dtime);
  
       return if(!$periods{$TP}[2]); #avoid illegal modulus

       $reading .= $TP;   
       #$timestampRef=time_str2num(ReadingsTimestamp($hash->{NAME},$reading,"2023-07-01 00:00:00")); 
       $timestampRef=ReadingsTimestamp($hash->{NAME},$reading,
            "2023-12-05 16-00-00" #ReadingsTimestamp($hash->{NAME},"energy",undef)
            );
       if( $timestampRef ){
            $timestampRef=time_str2num( $timestampRef );  #convert to epoch-time, like str2time
            $dtime = $unixtime - $timestampRef; 
       }else{
            $dtime = 0;
       }
 #      $timestampRef = $timestampRef + $periods{$TP}[2] - ($timestampRef+$periods{$TP}[$dst]) % $periods{$TP}[2];  #adjust to last full minute,hour,etc.

 #      if( $unixtime >= $timestampRef ){
       if( $dtime >= $periods{$TP}[2] - ($timestampRef+$periods{$TP}[$dst]) % $periods{$TP}[2] ){
       
              $energyOld=ReadingsVal($hash->{NAME},$reading,undef);
              if( $energyOld ){
                  $energyOld=~ /.*\((.*)\).*/;#Debug ": $reading - $energyOld - $energy - $1 -"; #$hash->{NAME}.
                  $denergy = $energy - $1; # energy used in this periode
                  $denergy = 0 if( $denergy < 0 );
              }else{
                  $denergy = 0; # if(abs($denergy) < 0.001);
              }
              
              my $power = $dtime ? sprintf(" %4.1f %s",3600*$denergy/$dtime,$si_units{power}[$hash->{units}]) : "-";
              readingsBulkUpdate($hash,$reading,
                        shelly_energy_fmt($hash,$denergy,"Wh")
                            .sprintf(" (%7.4f) ",$energy)
                            .$power, 
                        undef, $TimeStamp);
              #--- corrected values ?
              my $corrFactor = AttrVal($hash->{NAME},"PeriodsCorr-F",undef);
              if( $corrFactor ){
                  $power = $dtime ? sprintf(" %4.1f %s",3600*$denergy*$corrFactor/$dtime,$si_units{power}[$hash->{units}]) : "-";
                  readingsBulkUpdate($hash,$reading."-c",
                        shelly_energy_fmt($hash,$denergy*$corrFactor,"Wh")
                            .sprintf(" (%7.4f f=%4.3f) ",$energy,$corrFactor)
                            .$power,
                        undef, $TimeStamp);
              }
       }
       return undef; 
}


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
      return( "$energy $unit" );
  }
  if( $unit eq "Wm" ){  # Watt-Minutes, as in Shellies first gen, except Shelly-EM
      $energy = int($energy/6)/10;   # 60 minutes per hour
      $decimals=2;
  }elsif( $unit eq "mWh" ){  # Milli-Watt-Hours, as in Shellies 2nd gen "last-minute"
      $energy /= 1000;   # 1000 mWh per Wh
      $decimals=3;
  }
  $unit = "Wh";
  if( $showunits eq "none" ){
      $unit = "";  # in Wh
      return $energy; 
  }elsif( $showunits eq "normal" ){
      $decimals += 1;
      # nothing more to do here
  }elsif( $showunits eq "normal2" ){
      $energy /= 1000;   # 1000 Wh per kWh
      $unit = "kWh";
      $decimals += 4;
  }elsif( $showunits eq "ISO" ){
      $energy *= 3.6;   # 3.6 kJ per Wh (Kilo-Joule)
      $unit = "kJ";     # Kilo-Joule
  }else{
      return "Error: wrong unit";
  }
  $decimals = 1 if( $energy == 0 ); 
  $decimals = "%1.".$decimals."f";   # e.g. %1.4f
  return( sprintf("$decimals %s",$energy, $unit ) );
}

########################################################################################
#
# Shelly_dim -    Set Shelly dimmer state
#                 acts as callable program Shelly_dim($hash,$channel,$cmd)
#                 and as callback program  Shelly_dim($hash,$channel,$cmd,$err,$data)
# 
# Parameter hash, channel = 0,1 cmd = command 
#
########################################################################################

 sub Shelly_dim {
  my ($hash, $channel, $cmd, $err, $data) = @_;
  my $name = $hash->{NAME};
  my $state = $hash->{READINGS}{state}{VAL};
  my $net   = $hash->{READINGS}{network}{VAL};
  return
    if( !$net || $net !~ /connected to/ );
  
  my $model =  AttrVal($name,"model","generic");
  my $creds = Shelly_pwd($hash);
    
  if( $hash && !$err && !$data ){
     my $url     = "http://$creds".$hash->{TCPIP}."/$channel$cmd";
     Log3 $name,4,"[Shelly_dim] issue a non-blocking call to $url";  #4
     HttpUtils_NonblockingGet({
        url      => $url,
        timeout  => AttrVal($name,"timeout",4),
        callback => sub($$$){ Shelly_dim($hash,$channel,$cmd,$_[1],$_[2]) }
     });
     return undef;
  }elsif( $hash && $err ){  
    Shelly_error_handling($hash,"Shelly_dim",$err);
    return;
  }
  Log3 $name,5,"[Shelly_dim] device $name has returned data $data";  

  # extracting json from data    
  my $json = JSON->new->utf8;
  my $jhash = eval{ $json->decode( $data ) };
  if( !$jhash ){
    if( ($model =~ /shellyrgbw.*/) && ($data =~ /Device mode is not dimmer!/) ){
      Shelly_error_handling($hash,"Shelly_dim","is not a dimmer");
    }else{
      Shelly_error_handling($hash,"Shelly_dim","invalid JSON data");
    }
    return;
  }
  
  my $ison        = $jhash->{'ison'};
  my $bright      = $jhash->{'brightness'};
  my $hastimer    = $jhash->{'has_timer'};
  my $onofftimer  = $jhash->{'timer_remaining'};
  my $source      = $jhash->{'source'};
  # more readings by shelly_dim-answer:  timer_started, timer_duration, mode, transition
  
  if( $cmd =~ /\?turn=((on)|(off))/ ){
    my $cmd2 = $1;
    $ison =~ s/0|(false)/off/;
    $ison =~ s/1|(true)/on/;
    #-- timer command
    if( index($cmd,"&") ne "-1"){
      $cmd = substr($cmd,0,index($cmd,"&"));
      if( $hastimer && $hastimer ne "1" ){
        Log3 $name,1,"[Shelly_dim] returns with problem for device $name, timer not set";
      }
    }
    if( $ison ne $cmd2 ) {
      Log3 $name,1,"[Shelly_dim] returns without success for device $name, cmd=$cmd but ison=$ison";
    }
  }elsif( $cmd  =~ /\?brightness=(\d*)/){
    my $cmd2 = $1;
    if( $bright ne $cmd2 ) {
      Log3 $name,1,"[Shelly_dim] returns without success for device $name, desired brightness $cmd2, but device brightness=$bright";
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
  
  #-- Call status after switch.
  RemoveInternalTimer($hash,"Shelly_status");
  InternalTimer(time()+0.5, "Shelly_status", $hash,0);
  my $duration=ReadingsNum($name,"transition",10000)/1000;
  InternalTimer(time()+$duration, "Shelly_status2", $hash,0);

  return undef;
}

########################################################################################
#
# Shelly_updown - Move roller blind
#                 acts as callable program Shelly_updown($hash,$cmd)
#                 and as callback program  Shelly_updown($hash,$cmd,$err,$data)
# 
# Parameter hash, channel = 0,1 cmd = command 
#
########################################################################################

 sub Shelly_updown {
  my ($hash, $cmd, $err, $data) = @_;
  my $name = $hash->{NAME};
  my $state = $hash->{READINGS}{state}{VAL};
  my $net   = $hash->{READINGS}{network}{VAL};
  return
    if( !$net || $net !~ /connected to/ );
    
  Log3 $name,5,"[Shelly_updown] is called with command $cmd ";
       
  my $model =  AttrVal($name,"model","generic");
  my $creds = Shelly_pwd($hash);
  
  #-- empty cmd parameter
  $cmd = ""
     if( !defined($cmd) );
    
  if( $hash && !$err && !$data ){
     my $url     = "http://$creds".$hash->{TCPIP}."/roller/0".$cmd;
     Log3 $name,4,"[Shelly_updown] issue a non-blocking call to $url";  
     HttpUtils_NonblockingGet({
        url      => $url,
        timeout  => AttrVal($name,"timeout",4),
        callback => sub($$$){ Shelly_updown($hash,$cmd,$_[1],$_[2]) }
     });
     return undef;
  }elsif( $hash && $err ){
    Shelly_error_handling($hash,"Shelly_updown",$err);
    return;
  }
  Log3 $name,5,"[Shelly_updown] has obtained data $data";
    
  my $json = JSON->new->utf8;
  my $jhash = eval{ $json->decode( $data ) };
  if( !$jhash ){
    if( ($model =~ /shelly(plus|pro)?2.*/) && ($data =~ /Device mode is not roller!/) ){
      Shelly_error_handling($hash,"Shelly_updown","is not in roller mode");
    }else{
      Shelly_error_handling($hash,"Shelly_updown","invalid JSON data");
    }
    return;
  }
  
  #-- immediately after starting movement
  if( $cmd ne ""){
    #-- open 100% or 0% ?
    my $pctnormal = (AttrVal($name,"pct100","open") eq "open");
    my $targetpct = $hash->{TARGETPCT};
    my $targetposition =  $targetpct;
    if( $targetpct == 100 ){
      $targetposition = $pctnormal ? "open" : "closed";   
    }elsif( $targetpct == 0 ){
      $targetposition = $pctnormal ? "closed" : "open";  
    }  
    Log3 $name,5,"[Shelly_updown] $name: pct=$targetpct";
    readingsBeginUpdate($hash);
    readingsBulkUpdateMonitored($hash,"state",$hash->{MOVING});
    readingsBulkUpdateMonitored($hash,"pct",$targetpct);
    readingsBulkUpdateMonitored($hash,"position",$targetposition);
    readingsEndUpdate($hash,1);

    #-- perform first update after starting of drive
    $hash->{DURATION} = 5 if( !$hash->{DURATION} );    # duration not provided by Gen2
    RemoveInternalTimer($hash,"Shelly_status");
    InternalTimer(time()+0.5, "Shelly_status", $hash); # update after starting 
    # next update after expected stopping of drive + offset (at least 1 sec)
    InternalTimer(time()+$hash->{DURATION}+1.5, "Shelly_status2", $hash,1); 
  }
  return undef;
}

sub Shelly_status2($){
  my ($hash) =@_;
  Shelly_status($hash);
}


########################################################################################
#
# Shelly_onoff -  Switch Shelly relay
#                 acts as callable program Shelly_onoff($hash,$channel,$cmd)
#                 and as callback program  Shelly_onoff($hash,$channel,$cmd,$err,$data)
# 
# Parameter hash, channel = 0,1 cmd = command 
#                 example:  /relay/0?turn=on&timer=4                       works for Gen1 and Gen2
#                           /rpc/Switch.Set?id=0&on=true&toggle_after=4    Gen2 only (not realized)
#
########################################################################################

 sub Shelly_onoff {
  my ($hash, $channel, $cmd, $err, $data) = @_;
  my $name = $hash->{NAME};
  my $state = $hash->{READINGS}{state}{VAL};
  my $net   = $hash->{READINGS}{network}{VAL};
  
  Log3 $name,6,"[Shelly_onoff] try to execute command $cmd channel $channel for device $name ($state, $net)"; 
  return "Unsuccessful: Network Error for device $name, try device get status " 
                  if( !$net || $net !~ /connected to/ ); 
  
  my $model = AttrVal($name,"model","generic");
  my $creds = Shelly_pwd($hash);
    
  if( $hash && !$err && !$data ){
     my $callback;
     my $url     = "http://$creds".$hash->{TCPIP};
     if($shelly_models{$model}[4]<2){
         $url .= "/relay/$channel$cmd";
         $callback="/relay/$channel$cmd";
     }else{   # eg Wall-Display
         $cmd =~ /\?id=(\d)/;
         $callback = $url."/rpc/Switch.GetStatus?id=".$1;
         $url .= $cmd;
     }
     Log3 $name,4,"[Shelly_onoff] issue a non-blocking call to $url; callback to Shelly_onoff with command $callback";  
     HttpUtils_NonblockingGet({
        url      => $url,
        timeout  => AttrVal($name,"timeout",4),
        callback => sub($$$){ Shelly_onoff($hash,$channel,$callback,$_[1],$_[2]) }
     });
     return undef;
  }elsif( $hash && $err ){
    Shelly_error_handling($hash,"Shelly_onoff",$err);
    return;
  }
  
  #processing incoming data
  Log3 $name,5,"[Shelly_onoff:callback] device $name has returned data \n$data";

  # extracting json from data
  my $json = JSON->new->utf8;
  my $jhash = eval{ $json->decode( $data ) };
  if( !$jhash ){
    if( ($model =~ /shelly(plus)?2.*/) && ($data =~ /Device mode is not relay!/) ){
      Shelly_error_handling($hash,"Shelly_onoff","is not in relay mode");
    }elsif( $data =~ /Bad timer/ ){
      Shelly_error_handling($hash,"Shelly_onoff","Bad timer argument");
    }else{
      Shelly_error_handling($hash,"Shelly_onoff","invalid JSON data");
    }
    return;
  }
  
  my $onofftimer  = 0;
  if( $jhash->{'was_on'} ){
    my $was_on      = $jhash->{'was_on'};
  }else{ 
    my $ison        = $jhash->{'ison'};
    my $hastimer    = undef;
    my $timerstr    = "-";
    my $source      = $jhash->{'source'};
    my $overpower   = $jhash->{'overpower'};
  
    $ison =~ s/0|(false)/off/;
    $ison =~ s/1|(true)/on/;
    
    if( $jhash->{'has_timer'} ){
        $hastimer    = $jhash->{'has_timer'};
        $onofftimer  = $jhash->{'timer_remaining'};
        $timerstr    = $onofftimer.$si_units{time}[$hash->{units}];
    }
    
    # check on successful execution
    $cmd =~ /\/relay\/(\d)\?turn=(on|off)(\&timer=)?(\d+)?/;
    $channel = $1;

    Log3 $name,1,"[Shelly_onoff] returns with problem for device $name, timer not set"   if( $4 && $hastimer ne "1");
    Log3 $name,1,"[Shelly_onoff] returns without success for device $name, cmd=$cmd but ison=$ison" if( $ison ne $2 );

    if( defined($overpower) && $overpower eq "1") {
      Log3 $name,1,"[Shelly_onoff] device $name switched off automatically because of overpower signal";
    }
  
  my $subs = ($shelly_models{$model}[0] == 1) ? "" : "_".$channel;

  Log3 $name,4,"[Shelly_onoff:callback] received callback from $name channel $channel is switched $ison, "
           .($hastimer?"timer is set to $onofftimer sec":"no timer set");
  readingsBeginUpdate($hash);  
  readingsBulkUpdateMonitored($hash,"timer".$subs,$timerstr);
  readingsBulkUpdateMonitored($hash,"source".$subs,$source)     if( $model ne "shelly4" ); # not supported/old fw

  if( $shelly_models{$model}[0] == 1 ){
    readingsBulkUpdateMonitored($hash,"state",$ison);
  }else{
    readingsBulkUpdateMonitored($hash,"state","OK");
  }
  readingsBulkUpdateMonitored($hash,"relay".$subs,$ison);

  readingsBulkUpdateMonitored($hash,"overpower".$subs,$overpower)
                       if( $shelly_models{$model}[3]>0 && $model ne "shelly1" );
  readingsEndUpdate($hash,1);
  } #------

  #-- Call status after switch.    
  if( $hash->{INTERVAL}>0 ){
      $onofftimer = ($onofftimer % $hash->{INTERVAL}) + 0.5; #modulus
  }
  RemoveInternalTimer($hash,"Shelly_status");
  InternalTimer(time()+$onofftimer, "Shelly_status", $hash,0);

  return undef;
}


########################################################################################
#
# Shelly_webhook - Retrieve webhook data
#                 acts as callable program Shelly_webhook($hash,$cmd)
#                                      or  Shelly_webhook($hash)     with $cmd via $hash
#                 and as callback program  Shelly_webhook($hash,$cmd,$err,$data)
# 
# Parameter hash, $cmd: Create,Check,List,Update,Delete a webhook
#
########################################################################################

 sub Shelly_webhook {
  my ($hash, $cmd, $err, $data) = @_;
  my $name  = $hash->{NAME};
return if( $hash->{INTERVAL} == 0 ); 
  my $state = $hash->{READINGS}{state}{VAL};
  my $net   = $hash->{READINGS}{network}{VAL};
  
  #  check if net is 'not connected' or 'connected to ...'
  if( $net && $net =~ /not/ ){
    Log3 $name,1,"[Shelly_webhook] Error $name: network status is not connected";
    return;
  }

  #-- undefined or empty cmd parameter
  if( !defined($cmd) ){
    Log3 $name,6,"[Shelly_webhook] was called for device $name, but without command (Create..., Update, Delete, List)";
    $cmd = $hash->{CMD};
    return if( !$cmd);
  }
  Log3 $name,4,"[Shelly_webhook] proceeding with command \'$cmd\' for device $name". (!$data?", no data given":", processing data");

  my $model = AttrVal($name,"model","generic");
  my $gen   = $shelly_models{$model}[4]; # 0 is Gen1,  1 or 2 is Gen2
  my $creds = Shelly_pwd($hash);
  my $timeout = AttrVal($name,"timeout",4);
  my $mode  = AttrVal($name,"mode","relay");  # we need mode=relay for Shelly*1-devices
  
  # Calling as callable program: check if err and data are empty      
  if( $hash && !$err && !$data ){
    Log3 $name,7,"[Shelly_webhook] device $name will be called by Webhook.";
 
    my $URL     = "http://$creds".$hash->{TCPIP};
    $URL .=($gen>=1?"/rpc/Webhook.":"/settings/actions");   #Gen2 :  Gen1
 
    if( $cmd eq "Create" ){
       $URL .= "Create" if( $gen >= 1 );
    }elsif( $cmd eq "Update" ){
       $URL .= "Update?id=1";
    }elsif( $cmd eq "Delete" ){
       $URL .= "List";  # callback-cmd is "Delete"
    }elsif( $cmd eq "Check" ){
       $URL .= "List";  # callback-cmd is "Check"
    }elsif( $cmd eq "Count" ){
       $URL .= "List";  # callback-cmd is "Count"
    }else{
       $URL .= $cmd;
    }

   #---------CHECK, UPDATE, DELETE Webhooks-------------
   if( $cmd ne "Create" ){  #Check, Count, Update, Delete
             Log3 $name,5,"[Shelly_webhook] issue a non-blocking call to $URL, callback with command \'$cmd\' ";  
             HttpUtils_NonblockingGet({
                 url      => $URL,
                 timeout  => $timeout,
                 callback => sub($$$){ Shelly_webhook($hash,$cmd,$_[1],$_[2]) }
             });
        return undef;
        
   #---------CREATE Webhooks-------------
   }elsif( $cmd eq "Create" ){
    
    my $urls   = "";
    my $event  = "";   
    my $compCount=0;     #  number of components in device
    my $eventsCount=0;   #  number of events 

    my ($component,$element);
    foreach $component ( $mode, "input", "emeter", "pm1", "touch", "addon" ){
       Log3 $name,5,"[Shelly_webhook] $name: check number of components for component=$component";
       if( $component eq "relay" ){
          $compCount   = $shelly_models{$model}[0];
       }elsif( $component eq "roller" ){
          $compCount   = $shelly_models{$model}[1];
       }elsif( $component eq "input" && AttrVal($name,"showinputs","show") eq "show" && $mode ne "roller" ){
          # ShellyPlus2PM in roller mode does not support Actions for both inputs, even with detached inputs.
          # We don't care, because we can use actions on 'opening' and 'closing'
          $compCount   = abs($shelly_models{$model}[5]);  # number of inputs on ShellyPlug is -1, because it's a button, not an wired input
       }elsif( $component eq "emeter" && $model eq "shellypro3em" ){
          $compCount   = 1;   
       }elsif( $component eq "pm1" && $model eq "shellypmmini" ){
          $compCount   = 1;
       }elsif( $component eq "touch" && $model =~ /walldisplay/ ){
          $compCount   = 1;
       }elsif( $component eq "white" && $model eq "shellybulb" ){
          $compCount   = 1;
       }elsif( $component eq "addon" && ReadingsVal($name,"temperature_0", undef) ){  # we have an addon and at least one temperature sensor
       #Debug "start processing ADDON";
          $compCount   = 5; #max number of sensors supported
       }else{
          $compCount   = 0 ;
       }
       Log3 $name,5,"[Shelly_webhook] $name: the number of \'$component\' is compCount=$compCount";
       
       for( my $c=0;$c<$compCount;$c++ ){
             Log3 $name,5,"[Shelly_webhook] $name: processing component $c of $component";
          if( $component eq "input"){ 
             my $subs= $compCount>1 ? "_$c\_mode" : "_mode" ;
             $element = ReadingsVal($name,"input$subs","none"); #input type: switch or button
             if( $element eq "none" ){
                 Log3 $name,3,"[Shelly_webhook] $name: Error: Reading \'input.*mode\' not found";
                 return;
             }
             Log3 $name,5,"[Shelly_webhook] $name: input mode no $c is \'$element\' ";
             $element =~ /(\S+?)\s.*/;  # get only characters from first string of reading
             $element = $1;
          }elsif( $component eq "emeter" || $component eq "pm1"){
             $element = $component; 
        ##     $element = "emeter";   ## ?? PM1
          }elsif( $component eq "addon"){
       #Debug "processing ADDON c=$c";
             $element = $component;
             next unless( ReadingsVal($name,"temperature_$c", undef) );
          }elsif( $gen == 0){   # Gen 1
             $element = $model;  
          }else{
             $element = $component;
          }
          
          $eventsCount = $#{$shelly_events{$element}};   #  $#{...} gives highest index of array
             Log3 $name,5,"[Shelly_webhook] $name: processing evtsCnt=$eventsCount events for \'$element\'";#5
          
          for( my $e=0; $e<=$eventsCount; $e++ ){
             if( $cmd eq "Create" ){
                 $event = $shelly_events{$element}[$e];
                 $urls  = ($gen?"?cid=$c":"?index=$c");    # component id, 0,1,...
                 $urls  = "?cid=10$c"  if( $element eq "addon" );
                 $urls .= "&name=%22_". uc($event) ."_%22" if( $gen == 1 );   # name of the weblink (Gen2 only)                    
                 $urls .= ($gen?"&event=%22$event%22":"&name=$event"); 
                 $urls .= ($gen?"&enable=true":"&enabled=true");

                 my( $WebHook,$error ) = Shelly_actionWebhook($hash,$element,$c,$e);  # creating the &urls= command
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
             Log3 $name,1,"[Shelly_webhook] $name $cmd component=$element  count=$c   event=$e";
             Log3 $name,1,"[Shelly_webhook] issue a non-blocking call to \n$URL$urls";  
             HttpUtils_NonblockingGet({
                 url      => $URL.$urls,
                 timeout  => $timeout,
                 callback => sub($$$){ Shelly_webhook($hash,$cmd,$_[1],$_[2]) }
             });
          }
       }
    }
    return undef;
   } # cmd==Create

  # Error     
  }elsif( $hash && $err ){
    Shelly_error_handling($hash,"Shelly_webhook",$err);
    return;
  }
  ################################################# $hash && $data
  # Answer: processing the received webhook data
  Log3 $name,5,"[Shelly_webhook] device $name called by Webhook.$cmd has returned data $data";

  # extracting json from data
  my $json = JSON->new->utf8;
  my $jhash = eval{ $json->decode( $data ) };
  if( !$jhash ){
    Shelly_error_handling($hash,"Shelly_webhook","invalid JSON data");
    return;
  }
  # in any case get webhook version. In some cases (eg no Update performed) we have not received an answer.
  my $webhook_v = ( defined($jhash->{'rev'}) ? $jhash->{'rev'} : ReadingsVal($name,"webhook_ver",0) ); 
  
  # get number of webhooks
  my $hooksCount = ( defined($jhash->{'hooks'}) ? @{$jhash->{'hooks'}} : ReadingsVal($name,"webhook_cnt",0) );
 
  #processing the webhook data for the different commands
  Log3 $name,5,"[Shelly_webhook] processing the webhook data for command=$cmd";
  
  #---------------------Read number of webhooks from 'List' 
  if( $cmd eq "Count" ){
  
  
  #---------------------Check the received data from 'List' if the webhook has to be changed
  }elsif( $cmd eq "Check" ){
  
if(1){    # first of all, get number of webhooks
    if( defined $jhash->{'hooks'} ){
       $hooksCount =@{$jhash->{'hooks'}};
    }else{
       #return if($hooksCount == 0);
       $hooksCount = 0;
    }
    Log3 $name,5,"[Shelly_webhook] our counter says $hooksCount webhooks on shelly";  
}
   
    # parsing all webhooks and check for csrf-token  
    my $current_url;   # the current url of webhook on the shelly
    my $current_name;
    my $urls;   # the new urls string
    
    # are there webhooks on the shelly we don't know about?
    if( (!AttrVal($name,"webhook",undef) || AttrVal($name,"webhook",undef) eq "none" ) && $jhash->{'hooks'}[0]{'urls'}[0] ){
        $current_url = $jhash->{'hooks'}[0]{'urls'}[0]; # get the first webhook url from shelly
        $current_url =~ m/.*:([0-9]*)\/.*/;
        my $fhemwebport = $1; 
        Log3 $name,4,"[Shelly_webhook] We have found a webhook with port no $fhemwebport on $name, but the webhook attribute is none or not set";
        return;
    }
   
    # preparing the calling-url, we need this when looping        
    my $URL = "http://$creds".$hash->{TCPIP};
    $URL .= ($gen>0?"/rpc/Webhook.Update":"/settings/actions");
    # host_ip
    my $host_ip = qx("\"hostname -I\"");   # local
    $host_ip    =~ m/(\d\d?\d?\.\d\d?\d?\.\d\d?\d?\.\d\d?\d?).*/; #extract ipv4-address 
    $host_ip    = $1;
    # port
    my $host_port = InternalVal(AttrVal($name,"webhook","none"),"PORT",undef);
    # CSFR-Token
    my $token = InternalVal(AttrVal($name,"webhook","none"),"CSRFTOKEN",undef);
     
    Log3 $name,3,"[Shelly_webhook] $name: start parsing $hooksCount webhooks"; 
    my $flag;
    for (my $i=0;$i<$hooksCount;$i++){
        $flag=0;
        # 1. check name of webhook
        $current_name = $jhash->{'hooks'}[$i]{'name'}; 
        Log3 $name,4,"[Shelly_webhook] $name: checking webhook \'$current_name\'"; 
        if( $current_name !~ /^_/ ){   # name of webhook does not start with '_'  -> skipp
             Log3 $name,5,"[Shelly_webhook] shellies $name name of webhook $i $current_name does not start with _ -> skipping";
             next;
        }
        $current_url = $jhash->{'hooks'}[$i]{'urls'}[0]; # get the url from shelly
        $current_url =~ s/\%/\%25/g;    # to make it compareable to webhook_url 
        Log3 $name,5,"[Shelly_webhook] shellies $name webhook $i is $current_url"; 
        # 2. check ip of webhook  
        if($current_url !~ /$host_ip/ ){  #skip this hook when refering to another host
             Log3 $name,5,"[Shelly_webhook] shellies $name webhook $i is refering to another host $current_url -> skipping";
             next;
        }
        # 3. check/change CSRF-Token
        if( $current_url =~ /.*\&fwcsrf=(csrf_\d*)/ ){
             if( $1 ne $token ){
                 Log3 $name,5,"[Shelly_webhook] $name: old token=$1 , new token=$token ";
                 $current_url =~ s/(csrf_\d*)/$token/; #substitue token
                 $flag = 1;
             }
        }
        # 4. check/change XHR
        if( $current_url =~ /(XHR=1)/ ){
                 Log3 $name,5,"[Shelly_webhook] $name: XHR removed ";
                 $current_url =~ s/(&XHR=1)//; #remove/change XHR-command
                 $flag = 1;
        }
        # 5. substitute '&' by %26
        $current_url =~ s/\&/\%26/g; 
        # 6. substitute spaces by '%2520', that will result in '%20' 
        $current_url =~ s/\s/\%2520/g;
        # 7. write out change
        if( $flag ){
            $urls  = $URL;
            $urls .= "?urls=[\"$current_url\"]";   # we use \" instead of %22 
            $urls .= "&id=".$jhash->{'hooks'}[$i]{'id'};
            Log3 $name,3,"[Shelly_webhook] $name: $i issue a non-blocking call with callback-command \"Updated\":\n$urls";  #5
            HttpUtils_NonblockingGet({
              url      => $urls,
              timeout  => $timeout,
              callback => sub($$$){ Shelly_webhook($hash,"Updated",$_[1],$_[2]) }
            });
        }else{
        Log3 $name,5,"[Shelly_webhook] $name: $i check is OK, nothing to do"; #5
        }
    }  
    
  #---------------------Delete all webhooks (get number of webhooks from received data)
  }elsif($cmd eq "Delete" ){
    return if(!defined $hooksCount);  # nothing to do if there are no hooks
    my $h_name;
    my $h_id;
    my $h_urls0;
    for (my $i=0;$i<$hooksCount;$i++){
        $h_name = $jhash->{'hooks'}[$i]{'name'}; 
        $h_id = $jhash->{'hooks'}[$i]{'id'};
        $h_urls0 = $jhash->{'hooks'}[$i]{'urls'}[0]; # we need this, when checking for forward ip-adress
        
        Log3 $name,5,"[Shelly_webhook] ++++ $name: checking webhook id=$h_id \'$h_name\' for deleting ++++";  
        if( $h_name =~ /^_/ ){
            Log3 $name,5,"[Shelly_webhook] ++++ $name: deleting webhook \'$h_name\' ++++"; 
            my $url_ = "http://$creds".$hash->{TCPIP}."/rpc/Webhook.Delete?id=$h_id"; 
            Log3 $name,5,"[Shelly_webhook] url: $url_";
            HttpUtils_NonblockingGet({
              url      => $url_,
              timeout  => $timeout,
              callback => sub($$$){ Shelly_webhook($hash,"Killed",$_[1],$_[2]) }
            });
        }else{
            Log3 $name,5,"[Shelly_webhook] ++++ $name: webhook \'$h_name\' not deleted ++++"; 
        }
    } 
  
  #---------------------endpoint when 'check' has updated a webhook  
  }elsif($cmd eq "Updated" ){
    #my $webhook_v = $jhash->{'rev'};  #we don't do this here, because of reversed sequence of callbacks
    # nothing more to do here 
  
  #---------------------endpoint when a webhook has been deleted
  }elsif($cmd eq "Killed" ){
    $hooksCount--;
    # nothing more to do here 
  
  #---------------------endpoint when a webhook has been created: get id and version from data
  }elsif($cmd =~ /Create/ ){
    if( defined($jhash->{'id'}) ){
       #retrieving webhook id 
       my $webhook_id = $jhash->{'id'};
       $hooksCount++;
       Log3 $name,5,"[Shelly_webhook] $name hook created with id=".($webhook_id?$webhook_id:"").($webhook_v?", version is $webhook_v":"");
    }else{
       my $error = "Error ".$jhash->{'code'}." occured: ".$jhash->{'message'};
       Log3 $name,1,"[Shelly_webhook] $name: $error" if $error;
    }
  }    
  readingsBeginUpdate($hash);    
  readingsBulkUpdateMonitored($hash,"webhook_ver",$webhook_v);
  readingsBulkUpdateMonitored($hash,"webhook_cnt",$hooksCount);    
  readingsEndUpdate($hash,1);   
  Log3 $name,5,"[Shelly_webhook] shelly $name has $hooksCount webhooks".($webhook_v?", latest rev is $webhook_v":"");  # No of hooks in Shelly-device

  return undef;  
}


########################################################################################
#
# Shelly_webhookurl - Retrieve the url for a webhook 
#                 acts as callable program Shelly_webhookurl($hash)
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
  
  my $V = 1;
  my $msg;
  my $name = $hash->{NAME};
  Log3 $name,$V,"[Shelly_actionWebhook] calling url-builder with args: $name $comp ch:$channel noe:$noe";

  my $model = AttrVal($name,"model","generic");
  my $gen = $shelly_models{$model}[4]; # 0 is Gen1,  1 is Gen2
  #my $webhook = ($gen>=1?"&urls=[%22":"&urls[]="); # Gen2 : Gen1
  my $webhook = ($gen>=1?"urls=[\"":"urls[]="); # Gen2 : Gen1
  							
  my $host_ip =  qx("\"hostname -I\"");   # local
  $host_ip =~ m/(\d\d?\d?\.\d\d?\d?\.\d\d?\d?\.\d\d?\d?).*/; #extract ipv4-address
  $host_ip = $1;
  Log3 $name,6,"[Shelly_actionWebhook] the host-ip of $name is: $host_ip";
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
  Log3 $name,6,"[Shelly_actionWebhook] FHEMweb-device \"$fhemweb\" has port \"$port\" and webname \"$webname\"";
  $webhook .= "\/".$webname;

  $webhook .= "?cmd=";    # set%2520".$name;

  $comp = "status" if(!$comp );
  if( $comp eq "status" || length($shelly_events{$comp}[$noe])==0 ){
      $webhook .= "get $name status";
  }else{
      $comp  = $shelly_events{$comp}[$noe];
      $comp  = $fhem_events{$comp};
      $webhook .= "set $name $comp";
      # encodings:   $ %24   { %7b    } %7d
      if( $model eq "shellypro3em" ){
          $webhook .= "_%24%7bev.phase%7d ";
      }      
      if( $comp eq "apower" ){    # shellypmmini    
          $webhook .= "%24%7bev.apower%7d" ;
      }elsif( $comp eq "Active_Power" ){        
          $webhook .= "%24%7bev.act_power%7d" ;
      }elsif( lc($comp) eq "current" ){      
          $webhook .= "%24%7bev.current%7d" ;
      }elsif( lc($comp) eq "voltage" ){      
          $webhook .= "%24%7bev.voltage%7d" ;
      }elsif( $comp eq "tempC" ){      
          $webhook .= " %24%7bev.tC%7d $channel" ;
      }else{
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
  return ($webhook);#,undef);
}



sub Shelly_rssi {
  my ($hash, $rssi) = @_;
  if( $rssi eq "-" )   { return "-";}
  my $ret = $rssi;
  if( $hash->{units} == 1){ $ret .= $si_units{rssi}[1];
     if( $rssi < -76 )    { $ret .= " (bad)";}
     elsif( $rssi < -55 ) { $ret .= " (fair)";}
     elsif( $rssi < -35 ) { $ret .= " (good)";}
     else                 { $ret .= " (excellent)";}
  }
  Log3 $hash->{NAME},5,"[Shelly_rssi] returns $ret to device ".$hash->{NAME};
  return $ret;
}

########################################################################################
# 
# Shelly_error_handling - handling error from callback functions
# 
# Parameter hash, function, error 
#
########################################################################################


sub Shelly_error_handling {
  my ($hash, $func, $err, $verbose) = @_;
  my $name  = $hash->{NAME};
  my ($errN,$errS);
  $verbose=1 if( !defined($verbose) );
  my $flag=0;
    if( $hash->{".updateTime"} ){  # is set by 'readingsBeginUpdate()'
       $flag=1;
    }else{
       readingsBeginUpdate($hash);
    }
    Log3 $name,6,"[$func] device $name has error \"$err\" ";
    if( $err =~ /timed out/ ){
        if( $err =~ /read/ ){
            $errN = "Error: Timeout reading";
        }elsif( $err =~ /connect/ ){ 
            $errN = "Error: Timeout connecting"; 
        }else{
            $errN = "Error: Timeout";
        }
        readingsBulkUpdateIfChanged($hash,"network",$errN,1);
        $errS = "Error: Network"; 
    }elsif( $err eq "not connected" ){   # from Shelly_proc2G:status 
        $errN = $err;
        readingsBulkUpdateIfChanged($hash,"network",$errN,1);
        $errS = "Error: Network"; #disconnected
    }elsif( $err =~ /113/ ){   # keine Route zum Zielrechner (113) 
        $errN = "not connected (no route)";
        readingsBulkUpdateIfChanged($hash,"network",$errN,1);
        $errS = "Error: Network"; #disconnected
    }elsif( $err =~ /JSON/ ){ 
        $errN = $err;
        readingsBulkUpdateIfChanged($hash,"network",$errN,1);
        $errS = "Error: JSON"; 
    }elsif( $err =~ /wrong/ || $err =~ /401/ ){ #401 Unauthorized
        $errN = "wrong authentication"; 
        $errS = "Error: Authentication"; 
    }else{
        $errN = $err;
        $errS = "Error"; 
    }
    Log3 $name,$verbose,"[$func] Device $name has Error \'$errN\', state is set to \'$errS\'";# \nfull text=>$err";
    readingsBulkUpdate($hash,"network_disconnects",ReadingsNum($name,"network_disconnects",0)+1)   if( ReadingsVal($name,"state","") ne $errS );
    readingsBulkUpdateMonitored($hash,"state",$errS, 1 );
    if( $flag==0 ){
       readingsEndUpdate($hash,1);
    }
  return undef;  
}

########################################################################################

# if unchanged, generates an event and hold the old timestamp
sub
readingsBulkUpdateHoldTimestamp($$$@) 
{
  my ($hash,$reading,$value,$changed)= @_;
  my $timestamp=ReadingsTimestamp($hash->{NAME},$reading,undef); # yyyy-MM-dd hh:mm:ss
  if( $value eq ReadingsVal($hash->{NAME},$reading,"") ){  
       return readingsBulkUpdate($hash,$reading,$value,$changed,$timestamp);
  }else{
       return readingsBulkUpdate($hash,$reading,$value,$changed);
  }
}


# generate events at least at given readings age, even if the reading has not changed
sub
readingsBulkUpdateMonitored($$$@) # derived from fhem.pl readingsBulkUpdateIfChanged()
{
  my ($hash,$reading,$value,$changed)= @_;
  #$changed=0 if( $changed eq undef );
  my $MaxAge=AttrVal($hash->{NAME},"maxAge",2160000);  # default 600h
  if( !defined($value) ){
       Log3 $hash->{NAME},2,$hash->{NAME}.": undefined value for $reading";
       return;
       }
  if( ReadingsAge($hash->{NAME},$reading,$MaxAge)>=$MaxAge || $value ne ReadingsVal($hash->{NAME},$reading,"")  ){  #|| $changed>=1
##       Log3 $hash->{NAME},6,"$reading: maxAge=$MaxAge ReadingsAge="
##                        .ReadingsAge($hash->{NAME},$reading,0)." new value=$value vs old="
##                        .ReadingsVal($hash->{NAME},$reading,"")
##                       # .defined($changed)?"chg=$changed":"undefiniert"
##                        ; #4
       #$changed=1 if($changed == 2 );#touch
       #return 
       readingsBulkUpdate($hash,$reading,$value,$changed);
  }else{
       return undef;
  }
}

sub
Shelly_readingsBulkUpdate($$$@) # derived from fhem.pl readingsBulkUpdateIfChanged()
{
  my ($hash,$reading,$value,$changed,$timestamp)= @_;
  my $readingsProfile ="none";
  if($value ne ReadingsVal($hash->{NAME},$reading,"")){   
    if( !defined($timestamp) ){
      # Value of Reading changed: generate Event, timestamp is actual time
      readingsBulkUpdate($hash,$reading,$value,$changed);
    }else{  
      # Value of Reading changed: generte Event and set timestamp as calculated by function 
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
}


#



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
            <code>define &lt;name&gt; Shelly &lt;IP address&gt;</code>
            <br />Defines the Shelly device. </p>
        Notes: <ul>
         <li>This module needs the JSON and the HttpUtils package</li>
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
            <code>set &lt;name&gt; config &lt;registername&gt; &lt;value&gt; [&lt;channel&gt;] </code>
            <br />set the value of a configuration register (Gen1 devices only)
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
            <a id="Shelly-set-reset"></a>
            <code>set &lt;name&gt; reset &lt;counter&gt;</code>
            <br>Resetting the counters to zero 
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
        <a id="Shelly-get"></a>
        <h4>Get</h4>
        <ul>
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
                <a id="Shelly-get-shelly_status"></a>
                <code>get &lt;name&gt; shelly_status</code>
                <br />returns the current system status of the device.</li>
            <li>
                <a id="Shelly-get-model"></a>
                <code>get &lt;name&gt; model</code>
                <br />get the type of the Shelly</li>   
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
                <br />Note: The ShellyPro3EM energy meter is working with a set of two intervals: 
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
                Careful: Use this attribute only if you get timeout errors in your log.
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
                <a id="Shelly-attr-pct100"></a>
                <code>attr &lt;name&gt; pct100 open|closed (default:open) </code>
                <br/>roller or blind devices only: is pct=100 open or closed ? </li>
        </ul>
        <br/>For energy meter ShellyPro3EM
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
            <li>   <code>webhook_cnt</code>  
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
                  
        
           <h5>ShellyPro3EM </h5>
           
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
            <code>define &lt;name&gt; Shelly &lt;IP address&gt;</code>
            <br />Definiert das Shelly Device. </p>
        Hinweise: <ul>
        <li>Dieses Modul benötigt die Pakete JSON und HttpUtils</li>
         
        <li>Das Attribut <code>model</code> wird automatisch gesetzt. 
           Für Shelly Geräte, welche nicht von diesem Modul unterstützt werden, wird das Attribut zu <i>generic</i> gesetzt.
           Das Device enthält dann keine Aktoren, es ist nur ein Platzhalter für die Bereitstellung von Readings</li>
         
        <li>Bei bestimmten Shelly Modellen können URLs (Webhooks) festgelegt werden, welche bei Eintreten bestimmter Ereignisse ausgelöst werden. 
           Beispielsweise lauten die Webhooks für die Information über die Betätigung lokaler Eingänge wie folgt:
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
         
         <ul>
           <li>Ein CSRF-Token muss gegebenenfalls in den URL aufgenommen werden oder ein zugehörendes <i>allowed</i> Device muss festgelegt werden.</li>
           <li>Die URLs (Webhooks) können mit dem Attribut 'webhook' automatisiert angelegt werden</li>
           </ul>
         </li>
         </ul>
         
        <a id="Shelly-set"></a>
        <h4>Set</h4>
        Für alle Shelly Geräte
        <ul>
        <li>
                <a id="Shelly-set-name"></a>
                <code>set &lt;name&gt; name &lt;ShellyName&gt;</code>
                <br />Name des Shelly Gerätes. <!--Wenn der Shelly noch keinen Namen erhalten hat wird der Shelly nach dem FHEM-Device benannt.-->
                Der Shellyname darf Leerzeichen enthalten.
                </li>
                Hinweis: Leere Zeichenkentten werden nicht akzeptiert. 
                <!--Nach dem Löschen eines Shelly Namens (auf Shellies-Website) wird der Shelly Name auf den Namen des FHEM Devices gesetzt.-->
        <li>
            <a id="Shelly-set-config"></a>
            <code>set &lt;name&gt; config &lt;registername&gt; &lt;value&gt; [&lt;channel&gt;] </code>
            <br />Setzen eines Registers auf den Wert value (nur für Shellies der 1. Generation)
            <br />Die verfügbaren Register erhält man mit <code>get &lt;name&gt; registers</code> 
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
            </li>
            Bei Shelly-Geräten der 1. Generation muss zuvor das Attribut 'shellyuser' gesetzt sein. 
            Ein in Fhem gespeichertes Passwort wird durch Aufruf ohne Parameter entfernt: 
            <code>set &lt;name&gt; password </code>
            Hinweis: Beim Umbenennen des Devices mit 'rename' geht das Passwort verloren
        <li>
            <a id="Shelly-set-reboot"></a>
            <code>set &lt;name&gt; reboot</code>
            <br>Neustarten des Shelly 
            </li>
        <li>
            <a id="Shelly-set-reset"></a>
            <code>set &lt;name&gt; reset &lt;counter&gt;</code>
            <br>Setzen der Zähler auf Null 
            </li>
        <li>
            <a id="Shelly-set-update"></a>
            <code>set &lt;name&gt; update</code>
            <br>Aktualisieren der Shelly Firmware zur aktuellen stabilen Version 
            </li>

        </ul>
        <br/>Für Shelly mit Relais (model=shelly1|shelly1pm|shellyuni|shelly4|shellypro4pm|shellyplug|shellyem|shelly3em oder 
        (model=shelly2/2.5/plus2/pro2 und mode=relay)) 
        <ul>
            <li>
                <code>set &lt;name&gt; on|off|toggle  [&lt;channel&gt;] </code>
                <br />schaltet den Kanal &lt;channel&gt; on oder off. Die Kanalnummern sind 0 und 1 für model=shelly2/2.5/plus2/pro2, 0..3 für model=shelly4.
                       Wenn keine Kanalnummer angegeben, wird der mit dem Attribut 'defchannel' definierte Kanal geschaltet.</li>
            <li>
                <code>set &lt;name&gt; on-for-timer|off-for-timer &lt;time&gt; [&lt;channel&gt;] </code>
                <br />schaltet den Kanal &lt;channel&gt; on oder off für &lt;time&gt; Sekunden. 
                Kanalnummern sind 0 und 1 für model=shelly2/2.5/plus2/pro2 oder model=shellyuni, und 0..3 model=shelly4/pro4.  
                Wird keine Kanalnummer angegeben, wird der mit dem Attribut 'defchannel' definierte Kanal geschaltet.</li>           
            <li>
                <code>set &lt;name&gt; xtrachannels </code>
                <br />Erstellen von <i>readingsProxy</i> Devices für Shellies mit mehr als einem Relais</li>           
   
        </ul>
        <br/>Für Shelly Rollladenaktoren (model=shelly2/2.5/plus2/pro2 und mode=roller)  
        <ul>
            <li><a id="Shelly-set-open"></a><a id="Shelly-set-closed"></a>
                <code>set &lt;name&gt; open|closed [&lt;duration&gt;]</code>
                <br />Fährt den Rollladen aufwärts zur Position offen (open) bzw. abwärts zur Position geschlossen (closed). 
                      Es kann ein optionaler Parameter für die Fahrzeit in Sekunden mit übergeben werden
                      </li>      
            
            <li><a id="Shelly-set-stop"></a>
                <code>set &lt;name&gt; stop</code>
                <br />Beendet die Fahrbewegung (stop).
                      </li>
                       
            <li><a id="Shelly-set-pos"></a>
                <code>set &lt;name&gt; pos &lt;integer percent value&gt; </code>
                <br />Fährt den Rollladen zu einer Zwischenstellung (normalerweise gilt 100=offen, 0=geschlossen, siehe Attribut 'pct100'). 
                <s>Wenn dem Wert für die Zwischenstellung ein Plus (+) oder Minus (-) - Zeichen vorangestellt wird, 
                wird der Wert auf den aktuellen Positionswert hinzugezählt.</s>
                <br />
                
                äquivalent zu <code>set &lt;name&gt; pct &lt;integer percent value&gt; </code> 
                <br />
                      </li>

            <li><a id="Shelly-set-delta"></a>
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
                      
            <li><a id="Shelly-set-pct"></a>
                <code>set &lt;name&gt; pct &lt;1...100&gt; [&lt;channel&gt;] </code>
                <br />Prozentualer Wert für die Helligkeit (brightness). Es wird nur der Helligkeitswert gesetzt ohne das Gerät ein oder aus zu schalten.
                      </li> 
                                            
            <li><a id="Shelly-set-dim"></a>
                <code>set &lt;name&gt; dim &lt;0...100&gt; [&lt;channel&gt;] </code>
                <br />Prozentualer Wert für die Helligkeit (brightness). Es wird nur der Helligkeitswert gesetzt und eingeschaltet. 
                      Bei einem Helligkeitswert gleich 0 (Null) wird ausgeschaltet, der im Shelly gespeicherte Helligkeitswert bleibt unverändert.
                      </li> 
                                                                  
            <li><a id="Shelly-set-dimup"></a>
                <code>set &lt;name&gt; dimup [&lt;1...100&gt;] [&lt;channel&gt;] </code>
                <br />Prozentualer Wert für die Vergrößerung der Helligkeit.
                Ist kein Wert angegeben, wird das Attribut dimstep ausgewertet. 
                Der größte erreichbare Helligkeitswert ist 100.
                Ist das Gerät aus, ergibt sich der neue Helligkeitswert aus dem angegebenen Wert und das Gerät wird eingeschaltet. 
                      </li>

            <li><a id="Shelly-set-dimdown"></a>
                <code>set &lt;name&gt; dimdown [&lt;1...100&gt;] [&lt;channel&gt;] </code>
                <br />Prozentualer Wert für die Verringerung der Helligkeit. 
                Ist kein Wert angegeben, wird das Attribut dimstep ausgewertet.
                Der kleinste erreichbare Helligkeitswert ist der im Shelly gespeicherte Wert für "minimum brightness".                       
                      </li> 
                      
            <li><a id="Shelly-set-dim-for-timer"></a>
                <code>set &lt;name&gt; dim-for-timer &lt;brightness&gt; &lt;time&gt; [&lt;channel&gt;] </code>
                <br />Prozentualer Wert für die Helligkeit. Nach Ablauf der Zeit 'time' wird ausgeschaltet.                       
                      </li> 
        </ul>
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
                <br /> setzt die Verstärkung (Helligkeit) der Farbkanäle aufen einen Wert 0..100</li>
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
        <a id="Shelly-get"></a>
        <h4>Get</h4>
        <ul>
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
                <a id="Shelly-get-shelly_status"></a>
                <code>get &lt;name&gt; shelly_status</code>
                <br />Aktualisiert die Systemdaten des Shelly.</li>
            <li>
                <a id="Shelly-get-model"></a>
                <code>get &lt;name&gt; model</code>
                <br />Ermittelt den Typ des Shelly und passt die Attribute an</li>
            <li>
                <a id="Shelly-get-version"></a>
                <code>get &lt;name&gt; version</code>
                <br />Zeigt die Version des FHEM-Moduls an</li>
        </ul>
        <a id="Shelly-attr"></a>
        <h4>Attributes</h4>
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
                <a id="Shelly-attr-interval"></a>
                <code>attr &lt;name&gt; interval &lt;interval&gt;</code>
                <br />Aktualisierungsinterval für das Polling der Daten vom Shelly. 
                Der Default-Wert ist 60 Sekunden, ein Wert von 0 deaktiviert das automatische Polling.
                <br />
                <br />Hinweis: Bei den ShellyPro3EM Energiemessgeräten erfolgt das Polling mit zwei verschiedenen Intervallen: 
                   Die Leistungswerte werden entsprechend dem Attribut 'interval' gelesen, 
                   die Energiewerte (und daraus rekursiv bestimmte Leistungswerte) werden alle 60 Sekunden oder einem Vielfachen davon gelesen. 
                   Beim Setzen des Attributes 'interval' wird der Wert so angepasst, 
                   dass das Intervall entweder ein ganzzahliger Teiler oder ein Vielfaches von 60 ist.
                </li>
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
                <code>attr &lt;name&gt; timeout &lt;timeout&gt;</code>
                <br />Zeitlimit für nichtblockierende Anfragen an den Shelly. Der Standardwert ist 4 Sekunden. 
                Achtung: Dieses Attribut sollte nur bei Timingproblemen ('timeout errors' in der Logdatei) verändert werden.
                </li>
             <li>
                <a id="Shelly-attr-webhook"></a>
                <code>attr &lt;name&gt; webhook none|&lt;FHEMWEB-device&gt; (default:none) </code>
                <br />Legt einen oder mehrere Actions mit an FHEM addressierten Webhooks auf dem Shelly an, 
                      so dass der Shelly von sich aus Statusänderungen an FHEM sendet.  
                      Hinweis: Dezeit nur für Shellies der 2.Gen. verfügbar, Actions auf den Shellies der 1. Gen. müssen manuell angelegt werden. 
                <br />Enthält das zugehörige FHEMWEB Device ein CSFR-Token, wird dies mit berücksichtigt.
                      Token werden vom Modul geprüft und die Webhooks auf dem Shelly werden gegenenfalls aktualisiert.
                <br />Die Namen der Actions auf dem Shelly werden entsprechend der zugehörigen Events benannt, 
                zusätzlich mit einem vorangestellten und angehangenen Unterstrich (z.B. _COVER.STOPPED_). 
                <br/>Wird das Attribut zu 'none' gesetzt, werden diese Actions (mit Unterstrich) auf dem Shelly entfernt. 
                </li>
                <s>Webhooks, welche nicht an FHEM addressiert sind, werden von diesem Mechanismus ignoriert.</s>
                <br/>Hinweis: Vor dem Löschen eine FHEM-Devices sollten die zugehörigen Actions auf dem Shelly mit <code>attr &lt;name&gt; webhook none </code> oder 
                <code>deleteattr &lt;name&gt; webhook</code> entfernt werden.
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
                <a id="Shelly-attr-pct100"></a>
                <code>attr &lt;name&gt; pct100 open|closed (default:open) </code>
                <br/>Festlegen der 100%-Endlage für Rollladen offen (pct100=open) oder Rollladen geschlossen (pct100=closed)</li>
        </ul>
        <br/>Für Energiemeter ShellyPro3EM
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
                <br/>Saldierung des Gesamtenergiedurchsatzes aktivieren/deaktivieren. Das Intervall darf nicht größer als 20 sec sein.  
                <br/> <font color="red">Achtung: 
                    Das Deaktivieren des Attributes führt zum Löschen aller zugehörigen Readings _T!</font></li>
            <li>
                <a id="Shelly-attr-Periods"></a>
                <code>attr &lt;name&gt; Periods &lt;periodes&gt; </code>
                <br/>Komma getrennte Liste von Zeitspannen für die Berechnung von Energiedifferenzen (Energieverbrauch) 
                <br/>min:   Minute
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
           <h5>Webhooks (2nd gen devices only)</h5> 
            <li>   <code>webhook_cnt</code>  
                   <br/>number of webhooks stored in the shelly,  </li>
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
                  
        
           <h5>ShellyPro3EM </h5>
           
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
