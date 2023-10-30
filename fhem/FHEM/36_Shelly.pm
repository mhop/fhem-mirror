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

package main;

use strict;
use warnings;

use JSON; 
use HttpUtils;

use vars qw{%attr %defs};

sub Log($$);

#-- globals on start
my $version = "5.03 31.10.2023";

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
          'act_calc'             => "Active_Power_calculated",
          'act_integrated'       => "Active_Power_integrated",
          'act_integratedPos'       => "Active_Power_integratedPos",
          'act_integratedNeg'       => "Active_Power_integratedNeg",
          'act_integratedSald'       => "Active_Power_integratedSald",
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

#-- these we may get on request
my %gets = (
  "status:noArg"     => "S",
  "shelly_status:noArg"     => "X",
  "registers:noArg"  => "R",
  "config"           => "C",
  "version:noArg"    => "V",
  "model:noArg"      => "M"
);

#-- these we may set
my %setsshelly = (      #general settings for all devices 
# "name"          => "N",    #ShellyName
  "config"        => "K",
  "interval"      => "I",
  "password"      => "P",
  "update:noArg"  => "U",
  "reboot:noArg"  => "R"
); 

my %setssw = (       #general settings for all on-off-devices 
  "on"            => "O",
  "off"           => "F",
  "toggle"        => "T",
  "on-for-timer"  => "X",
  "off-for-timer" => "E"#,
#  "xtrachannels:noArg"  => "C"   # is only setable on devices with multiple outputs
);

my %setsrol = (
  "closed"        => "C",
  "open"          => "O",
  "stop:noArg"    => "S",
  "pct:slider,0,1,100"  => "B",
  "delta"         => "B2",  #make settings pct +i possible
  "zero:noArg"    => "Z",
  "predefAttr:noArg" => "I"
); 

my %setsrgbww = (
  "on"            => "O",
  "off"           => "F",
  "toggle"        => "T",
  "on-for-timer"  => "X",
  "off-for-timer" => "E",
  "pct"           => "B",
); 

my %setsbulbw = (
  "on:noArg"      => "O",
  "off:noArg"     => "F",
  "toggle:noArg"  => "T",
  "on-for-timer"  => "X",
  "off-for-timer" => "E",
  "ct:colorpicker,CT,3000,10,6500" => "R",
  "pct:slider,0,1,100" => "W"
); 

my %setsrgbwc = (
  "on:noArg"      => "O",
  "off:noArg"     => "F",
  "toggle:noArg"  => "T",
  "on-for-timer"  => "X",
  "off-for-timer" => "E",
  "rgbw"          => "A",
  "hsv"           => "H",
#  "hsv:colorpicker,HSV"  => "R", #test
  "rgb:colorpicker,HSV"  => "R",
#  "rgb:colorpicker,RGB"  => "R",  #test
  "white:slider,0,1,100" => "W",  #slider wird erst mit set übernommen
#  "white:colorpicker,BRI,0,1,255"  => "R" #test  colorpicker wird sofort übernommen
  "gain:slider,0,1,100"  => "V"
); 

my %attributes = (
  "multichannel"  => " defchannel",
  "roller"        => " pct100:open,closed maxtime maxtime_close maxtime_open",
  "input"         => " showinputs:show,hide",
  "emeter"        => " Energymeter_F Energymeter_P Energymeter_R EMchannels:ABC_,L123_,_ABC,_L123".
                     " Periods:multiple-strict,Week,day,dayT,dayQ,hour,hourQ,min".                 # @keys = keys %periods
                     " PeriodsCorr-F",
  "metering"      => " maxpower",
  "showunits"     => " showunits:none,original,normal,normal2,ISO"
);  

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
    "SNPM-001PCEU16"  => "shellypluspm",   # Shelly Plus PM Mini
    # Misc
    "SAWD-0A1XX10EU1" => "walldisplay1"
    );


my %shelly_models = (
    #(   0      1       2         3    4    5      6    7)
    #(relays,rollers,dimmers,  meters, NG,inputs,res.,color)
    "generic"       => [0,0,0, 0,0,0],
    "shellyi3"      => [0,0,0, 0,0,3],    # 3 inputs
    "shelly1"       => [1,0,0, 0,0,1],    # not metering, only a power constant in older fw
    "shelly1L"      => [1,0,0, 1,0,1],
    "shelly1pm"     => [1,0,0, 1,0,1],
    "shelly2"       => [2,1,0, 1,0,2],    # relay mode, roller mode 
    "shelly2.5"     => [2,1,0, 2,0,2],    # relay mode, roller mode
    "shellyplug"    => [1,0,0, 1,0,-1],   # shellyplug & shellyplugS;   no input, but a button which is only reachable via Action
    "shelly4"       => [4,0,0, 4,0,0],    # shelly4pro;  inputs not provided by fw v1.6.6
    "shellyrgbw"    => [0,0,4, 4,0,1, 0,1],    # shellyrgbw2:  color mode, white mode; metering col 1 channel, white 4 channels
    "shellydimmer"  => [0,0,1, 1,0,2],
    "shellyem"      => [1,0,0, 2,0,0],    # with one control-relay, consumed energy in Wh
    "shelly3em"     => [1,0,0, 3,0,0],    # with one control-relay, consumed energy in Wh
    "shellybulb"    => [0,0,1, 1,0,0, 0,1],    # shellybulb & shellybulbrgbw:  color mode, white mode;  metering is in any case 1 channel
    "shellyuni"     => [2,0,0, 0,0,2],    # + analog dc voltage metering
    #-- 2nd generation devices
    "shellyplusplug"=> [1,0,0, 1,1,-1],
    "shellypluspm"  => [0,0,0, 1,1,0],
    "shellyplus1"   => [1,0,0, 0,1,1],
    "shellyplus1pm" => [1,0,0, 1,1,1],
    "shellyplus2pm" => [2,1,0, 2,1,2],    # switch profile, cover profile
    "shellyplusi4"  => [0,0,0, 0,1,4],
    "shellypro1"    => [1,0,0, 0,1,2],
    "shellypro1pm"  => [1,0,0, 1,1,2],
    "shellypro2"    => [2,0,0, 0,1,2],
    "shellypro2pm"  => [2,1,0, 2,1,2],    # switch profile, cover profile
    "shellypro3"    => [3,0,0, 0,1,3],    # 3 potential free contacts
    "shellypro4pm"  => [4,0,0, 4,1,4],
    "shellyproem50" => [1,0,0, 1,1,0],    # has two single-phase meter and one relay
    "shellypro3em"  => [0,0,0, 1,1,0],    # has one (1) three-phase meter
    "shellyprodual" => [0,2,0, 4,1,4],
    "walldisplay1"  => [1,0,0, 0,1,1]     # similar to ShellyPlus1PM
    );
    
my %shelly_events = (	# events, that can be used by webhooks; key is mode, value is shelly-event 
        #Gen1 devices
    "generic"       => [""],
    "shellyi3"      => [""],
    "shelly1"       => [""],
    "shelly1L"      => [""],
    "shelly1pm"     => [""],
    "shelly2"       => [""], 
    "shelly2.5"     => [""],
    "shellyplug"    => [""],
    "shelly4"       => [""],
    "shellyrgbw"    => ["longpush_url","shortpush_url"],
    "shellydimmer"  => ["btn1_on_url","btn1_off_url","btn1_shortpush_url","btn1_longpush_url",
                        "btn2_on_url","btn2_off_url","btn2_shortpush_url","btn2_longpush_url"],
    "shellyem"      => [""],
    "shelly3em"     => [""],
    "shellybulb"    => ["out_on_url","out_off_url"],
    "shellyuni"     => [""], 
        #Gen2 components
    "relay"   => ["switch.on", "switch.off"],   # events of the switch component
    "roller"  => ["cover.stopped","cover.opening","cover.closing","cover.open","cover.closed"],
    "switch"  => ["input.toggle_on","input.toggle_off"],    # for input instances of type switch
    "button"  => ["input.button_push","input.button_longpush","input.button_doublepush","input.button_triplepush"],    # for input instances of type button
    "emeter"  => ["em.active_power_change","em.voltage_change","em.current_change"]
);
       
my %fhem_events = (	# events, that can be used by webhooks; key is shelly-event, value is event 
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
	"switch.on"     => "out_on", 
	"switch.off"    => "out_off",
	"cover.stopped" => "stopped",
	"cover.opening" => "opening",
	"cover.closing" => "closing",
	"cover.open"    => "is_open",
	"cover.closed"  => "is_closed", 
	"input.toggle_on"         => "button_on",
	"input.toggle_off"        => "button_off",
        "input.button_push"       => "single_push",
        "input.button_longpush"   => "long_push",
        "input.button_doublepush" => "double_push",
        "input.button_triplepush" => "triple_push",
        "em.active_power_change"  => "Active_Power",
        "em.voltage_change"       => "Voltage",
        "em.current_change"       => "Current",
        "S"       => "single_push",
        "L"       => "long_push",
        "SS"      => "double_push",
        "SSS"     => "triple_push",
        "SL"      => "short_long_push",
        "LS"      => "long_short_push",
        "single_push" => "S",
        "long_push"   => "L",
        "double_push" => "SS",
        "triple_push" => "SSS"
);

my %shelly_regs = (
    "relay"  => "reset=1\x{27f6}factory reset\n".
                  "appliance_type=&lt;string&gt;\x{27f6}custom configurabel appliance type\n".  # uni
                  "has_timer=0|1\x{27f6}wheater there is an active timer on the channel  \n".   # uni
                  "overpower=0|1\x{27f6}wheater an overpower condition has occured  \n".   # uni  !Sh1 1pm   4pro   plug
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
      "roller_webCmd"    => "open:up:down:closed:half:stop:pct",
      "roller_eventMap_closed100"  => "/delta -15:up/delta +15:down/pct 50:half/",
      "roller_eventMap_open100"    => "/delta +15:up/delta -15:down/pct 50:half/",
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
     "rssi"          => [""," dB"]
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
  $hash->{AttrFn}   = "Shelly_Attr";
  $hash->{GetFn}    = "Shelly_Get";
  $hash->{SetFn}    = "Shelly_Set";
  $hash->{RenameFn} = "Shelly_Rename";

  $hash->{AttrList}= "model:".join(",",(sort keys %shelly_models)).
                     " maxAge".
                     " ShellyName".
                     " mode:relay,roller,white,color".
                     " interval timeout shellyuser verbose:0,1,2,3,4,5".
                     $attributes{'multichannel'}.
                     $attributes{'roller'}.
                     $attributes{'input'}.
                     $attributes{'metering'}.
                     $attributes{'showunits'}.
                     " webhook:none,".join(",",devspec2array('TYPE=FHEMWEB:FILTER=TEMPORARY!=1')).
                     $attributes{'emeter'}.
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

  return "[Shelly] Define the IP address of the Shelly device as a parameter"
    if(@a != 3);
  return "[Shelly] invalid IP address ".$a[2]." of Shelly"
    if( $a[2] !~ m|\d\d?\d?\.\d\d?\d?\.\d\d?\d?\.\d\d?\d?(\:\d+)?| );
  
  my $dev = $a[2];
  $hash->{TCPIP} = $dev;
  $hash->{INTERVAL} = AttrVal($hash->{NAME},"interval",60); # Updates each minute, if not set as attribute
  
  $modules{Shelly}{defptr}{$a[0]} = $hash;

  #-- InternalTimer blocks if init_done is not true
  my $oid = $init_done;
  $init_done = 1;
  
  # try to get model and mode, adapt attr-list
  # Note: to have access to the attributes, we have to finish Shelly_Define first
  InternalTimer(time()+5, "Shelly_get_model", $hash,0);
  
  #-- perform status update in a minute or so
  InternalTimer(time()+10, "Shelly_status", $hash,0);
  InternalTimer(time()+12, "Shelly_EMData", $hash,0);
  InternalTimer(time()+14, "Shelly_shelly", $hash,0);
     
  $init_done = $oid;

  #-- initialize calculation of integrated power value
  $hash->{helper}{power} = 0;
  $hash->{helper}{powerCnt} = 1; 
  #-- initialize these helpers to prepare summarizing of Total of pushed values
  $hash->{helper}{a_Active_Power}=0;
  $hash->{helper}{b_Active_Power}=0;
  $hash->{helper}{c_Active_Power}=0;
  return undef;
}



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
  # a counter to prevent endless looping in case Shelly does not answer or the answering device is not a Shelly
  $count=1 if( !$count );
  if($count>3){  
       Shelly_error_handling($hash,"Shelly_get_model", "aborted: cannot get model for device \'$name\'");
       return;
  }
  if( $hash && !$err && !$data ){
    my $creds = Shelly_pwd($hash); 
    #-- try to get type/model and profile/mode of Shelly -  first gen
    Log3 $name,5,"[Shelly_get_model] try to get model for device $name as first gen";
    HttpUtils_NonblockingGet({
        url      => "http://$creds".$hash->{TCPIP}."/settings",
        timeout  => 4,
        callback => sub($$$$){ Shelly_get_model($hash,$count,$_[1],$_[2]) }
    });
    $count++;
    #-- try to get type/model and profile/mode of Shelly -  second gen
    Log3 $name,5,"[Shelly_get_model] try to get model for device $name as second gen";
    HttpUtils_NonblockingGet({
        url      => "http://$creds".$hash->{TCPIP}."/rpc/Shelly.GetDeviceInfo",
        timeout  => 4,
        callback => sub($$$$){ Shelly_get_model($hash,$count,$_[1],$_[2]) }
    });
    $count++;
    return undef; 
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
              url      => "http://".$hash->{TCPIP}."/shelly",
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
  
  # get Shellies Name either from the /settings call or from the /rpc/Shelly.GetDeviceInfo call
  if( defined($jhash->{'name'}) ){ #ShellyName
      ##fhem("set $name name " . $jhash->{'name'} );
      $attr{$hash->{NAME}}{ShellyName} = $jhash->{'name'};
  }else{ 
      # if Shelly is not named, set name of Shelly equal to name of Fhem-device
      ##fhem("set $name name " . $name ); 
      $attr{$hash->{NAME}}{ShellyName} = $name; 
  }    
        
  my ($model,$mode);
       
  #-- for all 1st gen models get type (vendor_id) and mode from the /settings call  
  if( $jhash->{'device'}{'type'} ){ 
        # set the type / vendor-id as internal
        $hash->{SHELLY}=$jhash->{'device'}{'type'};
        $mode = $jhash->{'mode'}
            if( $jhash->{'mode'} );

  #-- for some 1st gen models get type (vendor_id), from the /shelly call  
  }elsif( $jhash->{'type'} ){ 
        # set the type / vendor-id as internal
        $hash->{SHELLY}=$jhash->{'type'};
      
  #-- for all 2nd gen models get type (vendor_id) and mode from the /rpc/Shelly.GetDeviceInfo call
  }elsif( $jhash->{'model'} ){ # 2nd-Gen-Device
        # set the type / vendor-id as internal
        $hash->{SHELLY}=$jhash->{'model'}; 
        if ($jhash->{'profile'}){
          $mode = $jhash->{'profile'};
          $mode =~ s/switch/relay/;  # we use 1st-Gen modes
          $mode =~ s/cover/roller/;
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
        $attr{$hash->{NAME}}{model} = $model;
            Log3 $name,1,"[Shelly_get_model] the attribute \'model\' of device $name is set to \'$model\' ";
  }
    
  ######################################################################################
  #-- change attribute list w. hidden AttrList, replace all other models, except generic  
  ######################################################################################
        my $AttrList  = $modules{Shelly}{'AttrList'};
        $AttrList  =~ s/,(\S+?)\s/,$model /
      		if( $model ne "generic" );
      
        # set the mode-attribute (when we have a multimode device)
        if ( $mode && (( $shelly_models{$model}[0]>0 && $shelly_models{$model}[1]>0 ) || $model=~/rgbw/ || $model=~/bulb/ ) ){
          Log3 $name,5,"[Shelly_get_model] discovered mode=$mode for device $name";
          $attr{$hash->{NAME}}{mode} = $mode;
          if( $mode eq "roller" || $mode eq "relay" ){
              $AttrList  =~ s/,white,color//;
          }elsif( $mode eq "white" || $mode eq "color" ){
              $AttrList  =~ s/relay,roller,//;
          }
          $hash->{MOVING}="stopped" 
              if( $mode eq "roller" ); # first initialize
        }elsif( $model ne "generic" ){  # no mode
          $AttrList  =~ s/mode:(\S+?)\s//;
        }
      
        if( $shelly_models{$model}[1]==0 ){  #no roller
          #$AttrList  =~ s/maxtime(\S*?)\s//g;
          #$AttrList  =~ s/pct100(\S+?)\s//g;
          $AttrList  =~ s/$attributes{'roller'}/""/e;
        }

        if( $model ne "shellypro3em" ){ 
          $AttrList  =~ s/$attributes{'emeter'}/""/e;
        }else{
          $AttrList  =~ s/\smaxpower//;
        }

        if( $shelly_models{$model}[3]==0  ){  #no metering, eg. shellyi3  
          $AttrList  =~ s/$attributes{'metering'}/""/e;
          if( $model eq "shellyuni" || $model =~ /walldisplay/ ){
              $AttrList  =~ s/$attributes{'showunits'}/" showunits:none,original"/e;  # shellyuni measures voltage
          }else{
              $AttrList  =~ s/$attributes{'showunits'}/""/e;  
          }
        }

        if( $shelly_models{$model}[5] <= 0 ){  #no inputs, but buttons, eg. shellyplug 
          #$AttrList  =~ s/showinputs(\S*?)\s//g;
          $AttrList  =~ s/$attributes{'input'}/""/e;
        }

        if( !$mode && $shelly_models{$model}[0]<2 ){ 
            # delete 'defchannel' from attribute list for single-mode devices with less than 2 relays
            $AttrList  =~ s/\sdefchannel//;
        }elsif( ($mode ne "roller" && $shelly_models{$model}[0]>1) ||     #more than one relay
                ($mode ne "relay"  && $shelly_models{$model}[1]>1) ||     #more than one roller
                ($mode eq "white"  && $shelly_models{$model}[2]>1)    ){  #more than one dimmer
                # we have multiple channel and need attribute 'defchannel'
        }else{
            # delete 'defchannel' from attribute list
            $AttrList  =~ s/\sdefchannel//;
        }

        if( $shelly_models{$model}[4]==0 && $model ne "shellybulb" ){  # 1st Gen 
            $AttrList  =~ s/webhook(\S*?)\s//g;
        }
 
        $hash->{'.AttrList'} = $AttrList;

    ##readingsSingleUpdate($hash,"state","Model \"$model\" identified",1);
    readingsSingleUpdate($hash,"state","initialized",1);
    #fhem("trigger WEB JS:location.reload(true)");  # try a browser refresh ??
    InternalTimer(time()+10, "Refresh", $hash,0);
    return undef;  #successful
}

sub Refresh {
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
  
  my $model =  AttrVal($name,"model","generic");
  my $mode  =  AttrVal($name,"mode","");
  Log3 $name,5,"[Shelly_Attr] $name: called with command $cmd for attribute $attrName".($attrVal?" and value $attrVal":"");
  
  #-- temporary code
 ## delete $hash->{BLOCKED};
  delete $hash->{MOVING}
      if( ($shelly_models{$model}[1] == 0) || ($mode ne "roller") );
  
  #---------------------------------------  
  if ( ($cmd eq "set") && ($attrName =~ /model/) ) {
    my $regex = "((".join(")|(",(keys %shelly_models))."))";
    if( $attrVal !~ /$regex/ && $init_done ){
      $error = "Wrong value of model attribute, see documentation for possible values";
      Log3 $name,1,"[Shelly_Attr] $name\: $error ";
      return $error;
    } 
    if( $model =~ /shelly.*/ ){
      #-- only one relay
      if( $shelly_models{$model}[0] == 1){
        fhem("deletereading $name relay_.*");
        fhem("deletereading $name overpower_.*");  
        fhem("deletereading $name button_.*"); 
      #-- no relay
      }elsif( $shelly_models{$model}[0] == 0){
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
      if( $shelly_models{$model}[1] == 1){  
   #     fhem("deletereading $name .*_.");
    #    fhem("deletereading $name stop_reason.*");
     #   fhem("deletereading $name last_dir.*");
      #  fhem("deletereading $name pct.*");
       # delete $hash->{MOVING};
        #delete $hash->{DURATION};
      #-- no rollers        
      }elsif( $shelly_models{$model}[1] == 0){  
        fhem("deletereading $name position.*");
        fhem("deletereading $name stop_reason.*");
        fhem("deletereading $name last_dir.*");
        fhem("deletereading $name pct.*");
        delete $hash->{MOVING};
        delete $hash->{DURATION};
      }
      #-- no dimmers
      if( $shelly_models{$model}[2] == 0){
        fhem("deletereading $name L-.*");
        fhem("deletereading $name rgb");
        fhem("deletereading $name pct.*");
      }

      #-- always clear readings for meters
      fhem("deletereading $name power.*");
      fhem("deletereading $name energy.*");
      fhem("deletereading $name overpower.*");
    }
                 
    #-- change attribute list for model 2/rgbw w. hidden AttrList
    my $old = $modules{Shelly}{'AttrList'};
    my $new;
    my $ind = index($old,"mode:")-1;
    my $pre = substr($old,0,$ind);
    my $pos = substr($old,$ind+31,length($old)-$ind-31);

    if( $model =~ /shelly(plus|pro)?2.*/ ){  ##R
        #  $new = $pre." mode:relay,roller ".$pos;
        $old =~ s/,white,color//;
        $old =~ s/maxtime/maxtime_open maxtime_close/;
    }elsif( $model =~ /shelly(rgbw|bulb)/){
        #  $new = $pre." mode:white,color ".$pos;
        $old =~ s/relay,roller,//;
        $old =~ s/ maxtime//;
    }elsif( $model =~ /shelly.*/){
        #  $new = $pre." ".$pos;
        $old =~ s/mode:relay,roller,white,color //;
        $old =~ s/ maxtime//;
    }

    if( $shelly_models{$model}[5]==0 ){  # no inputs, eg. shellyplug
        $old =~ s/ showinputs:show,hide//;
    }
    
    
    if( $model eq "shellypro3em" ){  
        $old =~ s/ webhook//;  # Shelly actions do not work properly (fw v0.14.1)
        $old .= " Energymeter_F Energymeter_P Energymeter_R EMchannels:ABC_,L123_,_ABC,_L123";
    }
    
    $hash->{'.AttrList'} = $old;
    
  #---------------------------------------  
  }elsif ( ($cmd eq "set") && ($attrName =~ /mode/) ) {
    if( $model eq "generic" && $init_done && 0 ){
      $error="Setting the mode attribute for model $model is not possible. \nPlease set attribute model first <$init_done>";
      Log3 $name,1,"[Shelly_Attr] $name\: $error ".($init_done?"init is done":"init not done");
      return $error;
    }
    if( defined($model) && $model !~ /shelly(2|plus2|pro2|(rgb|bulb)).*/ && $init_done ){
      $error="Setting the mode attribute for this device is not possible";
      Log3 $name,1,"[Shelly_Attr] $name\: $error  only works for model=shelly2|shelly2.5|shellyplus2pm|shellypro2|shellyrgbw|shellybulb";
      return $error;
    }
  ##if( $model =~ /shelly(2|plus2|pro2).*/ ){ ##
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
      }elsif( $init_done ){  ##if( $attrVal !~ /((relay)|(roller))/){##
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
      }elsif( $init_done ){
        $error="Wrong mode value $attrVal for this device, must be white or color";
        Log3 $name,1,"[Shelly_Attr] $name\: $error";
        return $error;
      }
    }
    if ($shelly_models{$model}[4] == 0 ){ #1st Gen
        Shelly_configure($hash,"settings?mode=$attrVal");
    }else{ #2ndGen  %26 =    %22  "
        Shelly_configure($hash,"rpc/Sys.SetConfig?config={%22device%22:{%22profile%22:$attrVal}}");
    }

  #---------------------------------------  
  }elsif ( ($cmd eq "set" ) && ($attrName =~ /maxAge/) ) {
    if ( $attrVal < 60 ){ #interval
        $error="maxAge must be at least \'interval\', in seconds";
        Log3 $name,1,"[Shelly_Attr] $name\: $error";
        return $error;
    }
 

  #---------------------------------------  
  }elsif ( ($cmd eq "set" ) && ($attrName =~ /ShellyName/) ) {  
    #$attrVal="" if( $cmd eq "del" ); #cannot set name to empty string
    if ( $attrVal =~ " " ){ #spaces not allowed in urls
        $attrVal =~ s/ /%20/g;
    }    
    if ($shelly_models{$model}[4] == 0 ){ #1st Gen
        Shelly_configure($hash,"settings?name=$attrVal");
    }else{
        Shelly_configure($hash,"rpc/Sys.SetConfig?config={%22device%22:{%22name%22:%22$attrVal%22}}");
        #                                                 {"device"   :{"  name"  :"attrVal"}}
    }
    
  #---------------------------------------  
  }elsif ( ($cmd eq "set" ) && ($attrName =~ /showinputs/) && $attrVal ne "show" ) {
     fhem("deletereading $name input.*");
     fhem("deletereading $name button.*");
  
  #---------------------------------------  
  }elsif ( $cmd eq "del" && ($attrName =~ /showinputs/) ) {
     fhem("deletereading $name input.*");
     fhem("deletereading $name button.*");
 
  #---------------------------------------  
  }elsif ( $cmd eq "set"  && ($attrName =~ /showunits/) ) {
    if( $attrVal eq "none" ){
        $hash->{units}=0;
    }else{
        $hash->{units}=1;
    }
    
  #---------------------------------------  
  }elsif ( $cmd eq "del" && ($attrName =~ /showunits/) ) {
    $hash->{units}=0;
   
  #---------------------------------------  
  }elsif ( ($cmd eq "set") && ($attrName eq "maxpower") ) {
    if( $shelly_models{$model}[3] == 0 && $init_done ){
      $error="Setting the maxpower attribute for this device is not possible";
      Log3 $name,1,"[Shelly_Attr] $name\: $error";
      return $error;
    }
    if( ($attrVal<1 || $attrVal>3500) && $init_done ){
      $error="Maxpower must be within the range 1...3500 Watt";
      Log3 $name,1,"[Shelly_Attr] $name\: $error";
      return $error;
    }
    if ($shelly_models{$model}[4] == 0 ){ #1st Gen
        Shelly_configure($hash,"settings?max_power=".$attrVal);
    }elsif( $mode eq "roller" ){ #2ndGen  %26 =    %22  "
        Shelly_configure($hash,"rpc/Cover.SetConfig?id=0&config={%22power_limit%22:$attrVal}");
    }else{
      Log3 $name,1,"[Shelly_Attr] $name\: have not set $attrVal (L 744)";   
    }

  #---------------------------------------  
  }elsif ( ($cmd eq "set") && ($attrName =~ /maxtime/) ) {
    if( ($shelly_models{$model}[1] == 0 || $mode ne "roller" ) && $init_done ){
      $error="Setting the maxtime attribute only works for devices in roller mode";
      Log3 $name,1,"[Shelly_Attr] $name\: $error model=shelly2/2.5/plus2/pro2 and mode=roller"; 
      return $error;
    }
    if ($shelly_models{$model}[4] == 0 ){ #1st Gen
        Shelly_configure($hash,"settings/roller/0?$attrName=".int($attrVal));
    }else{ #2nd Gen  %26 =    %22  "
        Shelly_configure($hash,"rpc/Cover.SetConfig?id=0&config={%22$attrName%22:$attrVal}");
      # Shelly_configure($hash,"rpc/Cover.SetConfig?id=0&config={%22maxtime_open%22:$attrVal}");
      # Shelly_configure($hash,"rpc/Cover.SetConfig?id=0&config={%22maxtime_close%22:$attrVal}");
    }    
    
  #---------------------------------------        
  }elsif ( ($cmd eq "set") && ($attrName eq "pct100") ) {
    if( ($shelly_models{$model}[1] == 0 || $mode ne "roller") && $init_done ){
      $error="Setting the pct100 attribute only works for devices in roller mode";
      Log3 $name,1,"[Shelly_Attr] $name\: $error model=shelly2/2.5/plus2/pro2 and mode=roller";  ##R
      return $error;
    }
    # perform an update of the position related readings
    RemoveInternalTimer($hash,"Shelly_status");
    InternalTimer(gettimeofday()+1, "Shelly_status", $hash);  ##ü      
    
  #---------------------------------------        
  }elsif( $attrName =~ /Energymeter/ ){
    if($cmd eq "set" && $init_done ){
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
    if( $model ne "shellypro3em" && $init_done ){
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
  }elsif( $attrName eq "Periods" ){
    if( $model ne "shellypro3em" && $init_done ){
      $error="Setting of the attribute \"$attrName\" only works for ShellyPro3EM ";
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
    }elsif( $cmd eq "set"){
        my $av=$attrVal.',';
        foreach $RP ( @keys ){
          my $rp=$RP.',';
          if( $av !~ /$rp/ ){
            fhem("deletereading $name .*_$RP");
            Log3 $name,1,"[Shelly_Attr] deleted readings $name\:.*_$RP ";
          }
        }
    }else{
            Log3 $name,3,"[Shelly_Attr] no readings deleted";
    }      
  #---------------------------------------        
  }elsif( $attrName eq "PeriodsCorr-F" ){
    if( $cmd eq "del"){
      $hash->{CORR} = 1.0;
      return;
    }
    if( $model ne "shellypro3em" && $init_done ){
      $error="Setting of the attribute \"$attrName\" only works for ShellyPro3EM ";
      Log3 $name,1,"[Shelly_Attr] $name\: $error ";
      return $error;
    }
    if( abs($attrVal-1.0) > 0.1 ){
      $error="The correction factor \"$attrVal\" is outside the valid range ( 0.90 ... 1.10 )";
      Log3 $name,1,"[Shelly_Attr] $name\: $error ";
      return $error;
    }
    if( $cmd eq "set" ){
      $hash->{CORR} = round($attrVal,4);
      $_[3] = $hash->{CORR};
      
      #------expand the periods-hash:      
      my $old = $modules{Shelly}{'AttrList'};
      my @keys = keys %periods;
      my $key;
      my $newkey;
        foreach $key ( @keys ){
            if( $key !~ /(_c)$/ ){
               $newkey=$key.'_c';
               if( !defined($periods{$newkey}) ){
                   $periods{$newkey}=$periods{$key};
                   $old =~ s/$key/$key,$newkey/;
                   Log3 $name,4,"[Shelly_Attr] expanded \'periods\' by $newkey ";
               }
            }
        }
      $hash->{'.AttrList'} = $old;
    }
  #---------------------------------------  
   }elsif( $attrName eq "webhook" ){
     if( $init_done==0 ){        
         Log3 $name,3,"[Shelly_Attr:webhook] $name: check webhooks on start of fhem";
         $hash->{CMD}="Check";
     }elsif( $cmd eq "del" ){          
         Log3 $name,3,"[Shelly_Attr:webhook] $name: delete all hooks forwarding to this host and name starts with _";
         # Delete all webhooks to fhem
         $hash->{CMD}="Delete"; 
     }else{  #processing set commands, and init is done
       Log3 $name,3,"[Shelly_Attr:webhook] $name command is $cmd, attribute webhook old: ".AttrVal($name,"webhook","NoVal")."  new: $attrVal";
       if( $shelly_models{$model}[4] != 1  && $init_done && $model ne "shellybulb" ){  # only for 2nd-Generation devices
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
     # calling Shelly_webhook() via timer, otherwise settings are not available
     Log3 $name,3,"[Shelly_Attr:webhook] we will call Shelly_webhook for device $name, command is ".$hash->{CMD}; 
     RemoveInternalTimer($hash,"Shelly_webhook"); 
     InternalTimer(gettimeofday()+3, "Shelly_webhook", $hash, 0);
       
 
  #---------------------------------------  
  }elsif( $attrName eq "interval" ){
    if( $cmd eq "set" ){
      #-- update timer
      if( $model eq "shellypro3em" && $attrVal > 0 ){ 
        # restart the 2nd timer (only when stopped)
        # adjust the timer to one second after the full minute
        InternalTimer(int((gettimeofday()+60)/60)*60+1, "Shelly_shelly", $hash, 1)
                 if( AttrVal($name,"interval",-1) == 0 ); 
        
        # adjust the 1st timer to 60 
        my @teiler=(1,2,3,4,5,6,10,12,15,20,30,60);
        my @filter = grep { $_ >= $attrVal } @teiler ;
        $attrVal = ($attrVal >60 ? int($attrVal/60)*60 : $filter[0]);
        $_[3] = $attrVal 
      }
      $hash->{INTERVAL} = int($attrVal);
    }elsif( $cmd eq "del" ){
      $hash->{INTERVAL}=60;
    }
    if ($init_done) {
      RemoveInternalTimer($hash,"Shelly_status");
      InternalTimer(gettimeofday()+$hash->{INTERVAL}, "Shelly_status", $hash, 0)
        if( $hash->{INTERVAL} != 0 );
    } 
  #---------------------------------------  
  }elsif( $attrName eq "defchannel" ){      
    if( (($shelly_models{$model}[0] < 2 && $mode eq "relay") || ($model eq "shellyrgbw" && $mode ne "white")) && $init_done ){
      $error="Setting the \'defchannel\' attribute only works for devices with multiple outputs/relays";
      Log3 $name,1,"[Shelly_Attr] $name\: $error ";
      return $error;
    }
    if( $attrVal =~ /\D/ ){  # checking if there is anything else than a digit
        $error="The value of \"$attrName\" must be a positive integer";
        Log3 $name,1,"[Shelly_Attr] $name\: $error ";
        return $error;
    }
  }
  #--------------------------------------- 
  return undef;
}


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
  
  Log3 $name,4,"[Shelly_Get] receiving command get $name ".$a[1].($a[2]?" ".$a[2]:"") ;
  
  my $model =  AttrVal($name,"model","generic");
  my $mode  =  AttrVal($name,"mode","");
  
  #-- get version
  if( $a[1] eq "version") {
    return "$name.version => $version";
    
  #-- autodetect model "get model"
  }elsif($a[1] eq "model") {
    $v = Shelly_get_model($hash);

      
  #-- current status
  }elsif($a[1] eq "status") {
    $v = Shelly_status($hash);
    
  #-- current status of shelly
  }elsif($a[1] eq "shelly_status") {
    $v = Shelly_shelly($hash);
  
  #-- some help on registers
  }elsif($a[1] eq "registers") {
    return "Please get registers of 2nd-Gen devices via Shelly-App or homepage of the Shelly" 
                    if( $shelly_models{$model}[4]==1 );  # at the moment, we do not handle registers of Gen2-Devices -> ToDo
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
                    if( $shelly_models{$model}[4]==1 );  # at the moment, we do not handle configuration of Gen2-Devices  -> ToDo
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
    my $newkeys = join(" ", sort keys %gets);
    $newkeys    =~  s/:noArg//g
      if( $a[1] ne "?");
    my $msg = "unknown argument ".$a[1].", choose one of $newkeys";
    Log3 $name,5,"[Shelly_Get] $name: $msg";
    return $msg;
  }

  return undef;
}
 
########################################################################################
#
# Shelly_Set - Implements SetFn function
#
# Parameter hash, a = argument array
#
########################################################################################

sub Shelly_Set ($@) {
  my ($hash, @a) = @_;
  my $name = shift @a;
  
  my ($newkeys,$cmd,$value,$v,$msg);

  $cmd      = shift @a;
  $value    = shift @a; 
  
  #-- when Shelly_Set is called by 'Shelly_Set($hash)' arguments are not handed over
  if( !defined($cmd) ){
     $cmd = $hash->{CMD};
  }  
  if( !defined($name) ){
     $name = $hash->{NAME};
  }
  
  my $model =  AttrVal($name,"model","generic");   # formerly: shelly1
  my $mode  =  AttrVal($name,"mode","");
  my ($channel,$time);
  
  Log3 $name,5,"[Shelly_Set] calling for device $name with command $cmd".( defined($value)?" and value $value":", without value" );

  #-- WEB asking for command list 
  if( $cmd eq "?" ) { 
      $newkeys = join(" ", sort keys %setsshelly);  # all models and generic
      if( $mode eq "relay" || ($shelly_models{$model}[0]>0 && $shelly_models{$model}[1]==0) ){
          $newkeys .= " ".join(" ", sort keys %setssw)
                       if( $shelly_models{$model}[0]>0 );
          $newkeys .= " xtrachannels:noArg"
                       if( $shelly_models{$model}[0]>1 );
      }elsif( $mode eq "roller" || ($shelly_models{$model}[0]==0 && $shelly_models{$model}[1]>0)){
          $newkeys .= " ".join(" ", sort keys %setsrol);
      }elsif( $model =~ /shellydimmer/ || ($model =~ /shellyrgbw.*/ && $mode eq "white")  ){
          $newkeys .= " ".join(" ", sort keys %setsrgbww) ;
          $newkeys .= " xtrachannels:noArg"
                        if( $mode eq "white" && $shelly_models{$model}[2]>1);  
      }elsif( $model =~ /shellybulb.*/ &&  $mode eq "white" ){
          $newkeys .= " ".join(" ", sort keys %setsbulbw) ;
      }elsif( $model =~ /shelly(rgbw|bulb).*/ && $mode eq "color" ){
          $newkeys .= " ".join(" ", sort keys %setsrgbwc) ;
      }       
 if(0 && $shelly_models{$model}[0]>0 && $shelly_models{$model}[4]==1 ){
 # xx-for-timer does not work 
            $newkeys =~ s/on-for-timer//;
            $newkeys  =~ s/off-for-timer//;
 }

      $msg = "unknown argument $cmd choose one of $newkeys";
      ###Log3 "YY",5,"[Shelly_Set] $name model=$model: $msg";
      return $msg;
  }
     
  #-- following commands do not occur in command list, eg. out_on, input_on, single_push
  #-- command received via web to register local changes of the device 
  if( $cmd =~ /^(out|button|input|single|double|triple|long|voltage|temperature|humidity|Active_Power|Voltage|Current)_(on|off|push|over|under|a|b|c|changed)/
              ||  $cmd =~ /^(stopped|opening|closing|is_open|is_closed)/ ){ 
    my $signal=$1;
    my $isWhat=$2;
    my $subs;
    Log3 $name,3,"[Shelly_Set] calling for device $name with command $cmd".( defined($value)?" and channel $value":", without channel" );
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
   
      # after a second, the pushbuttons state is back to OFF, call status of inputs
      RemoveInternalTimer($hash,"Shelly_shelly");   # not Shelly_status
      InternalTimer(int(gettimeofday()+1.9), "Shelly_shelly", $hash,0);
    }elsif( $signal =~ /^(voltage|temperature|humidity)/ ){
          $subs = defined($value)?"_".$value:"" ;
          readingsBulkUpdateMonitored($hash,$signal.$subs."_range", $isWhat );
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

    }elsif( $signal =~ /^(stopped|opening|closing)/ ){
          # do nothing 
    }elsif( $signal =~ /is/ ){
    	$cmd = "stopped";
    }else{
          Log3 $name,1,"[Shelly_Set] $name: Wrong detail on action command $cmd $value". (defined($mode)?", mode is $mode":", no mode given");
          return;
    }
    readingsEndUpdate($hash,1);
      #-- Call status after switch.n
    if( $signal !~ /^(Active_Power|Voltage|Current)/ ){      
      RemoveInternalTimer($hash,"Shelly_status"); Log3 $name,6,"shelly_set 1715 removed Timer Shelly_status, now calling in 1.5 sec";
      InternalTimer(gettimeofday()+1.5, "Shelly_status", $hash);
    }
  }
  
  #-- commands independent of Shelly type: password, reboot, update
  if( $cmd eq "password" ){
    my $user = AttrVal($name, "shellyuser", '');
    if(!$user){
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
          $value=AttrVal($name,"interval",60);
          $hash->{INTERVAL}=$value;
      }else{
          my $msg = "Value is not an positve integer";
          Log3 $name,1,"[Shelly_Set] ".$msg;
          return $msg;
      }
      Log3 $name,1,"[Shelly_Set] Setting interval of $name to $value";
     #### Shelly_Set($hash->{NAME},"startTimer");
      if( $hash->{INTERVAL} ){
        Log3 $name,2,"[Shelly_Set] Starting cyclic timers for $name ($model)";
        RemoveInternalTimer($hash,"Shelly_status");
        InternalTimer(gettimeofday()+$hash->{INTERVAL}, "Shelly_status", $hash, 0);
        RemoveInternalTimer($hash,"Shelly_shelly");
        InternalTimer(gettimeofday()+120, "Shelly_shelly", $hash,0);
        if( $model eq "shellypro3em" ){
          RemoveInternalTimer($hash,"Shelly_EMData");
          InternalTimer(int((gettimeofday()+60)/60)*60+1, "Shelly_EMData", $hash,0);
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
        InternalTimer(gettimeofday()+$hash->{INTERVAL}, "Shelly_status", $hash, 0);
        RemoveInternalTimer($hash,"Shelly_shelly");
        InternalTimer(gettimeofday()+120, "Shelly_shelly", $hash,0);
        RemoveInternalTimer($hash,"Shelly_EMData");
        InternalTimer(int((gettimeofday()+60)/60)*60+1, "Shelly_EMData", $hash,0);
      }else{
        Log3 $name,2,"[Shelly_Set] No timer started for $name";
      }
      return undef;

      
  }elsif( $cmd eq "reboot" ){
      Log3 $name,1,"[Shelly_Set] Rebooting $name";
      Shelly_configure($hash,$cmd);
      return undef;

  }elsif( $cmd eq "update") {
      Log3 $name,1,"[Shelly_Set] Updating $name";
   #  if ( $shelly_models{$model}[4] == 0 ){$cmd ="ota/update";} # Gen1 only
      Shelly_configure($hash,$cmd);
      return undef;

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
      $newname =~ s/ /%20/g;  #spaces not allowed in urls   
      Log3 $name,1,"[Shelly_Set] Renaming $name to $newname";
      if( $shelly_models{$model}[4] == 1 ){
        $cmd="rpc/Sys.SetConfig?config={%22device%22:{%22name%22:%22$newname%22}}" ;
        #                                {"device"   :{"  name"  :   "arg"}}
      }else{ 
        $cmd="settings?name=$newname";
      }
      Shelly_configure($hash,$cmd);
      return undef;
   
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
    }else{
      $pre .= "relay/$chan?";
    }
    $v = Shelly_configure($hash,$pre.$reg."=".$val);
    return undef;
    
  #-- fill in predefined attributes for roller devices
  }elsif( $cmd eq "predefAttr") {
      return "keine Kopiervorlage verfügbar" if( $mode ne "roller" );
      
      return "Set the attribute\'pct100\' first"   if( !AttrVal($name,"pct100",undef) );

      if(  !AttrVal($name,"devStateIcon",undef) ){ 
          if( AttrVal($name, "pct100", "closed") eq "closed" ){
              $v = $predefAttrs{'roller_closed100'};
          }else{
              $v = $predefAttrs{'roller_open100'};
          }
          # set the devStateIcon-attribute when the devStateIcon attribute is not set yet     
          $attr{$hash->{NAME}}{devStateIcon} = $v;
          Log3 $name,5,"[Shelly_Get] the attribute \'devStateIcon\' of device $name is set to \'$v\' ";
          $v = "devStateIcon attribute is set";
      }else{
          $v = "attribute \'devStateIcon\' is already defined";
      }
      $v .= "\n";
      if(  !AttrVal($name,"webCmd",undef) ){ 
          # set the webCmd-attribute when the webCmd attribute is not set yet     
          $attr{$hash->{NAME}}{webCmd} = $predefAttrs{'roller_webCmd'};
          Log3 $name,5,"[Shelly_Get] the attribute \'webCmd\' of device $name is set  ";
          $v .= "webCmd attribute is set";
      }else{
          $v .= "attribute \'webCmd\' is already defined";
      }
      $v .= "\n";
      if(  !AttrVal($name,"cmdIcon",undef) ){ 
          # set the cmdIcon-attribute when the cmdIcon attribute is not set yet     
          $attr{$hash->{NAME}}{cmdIcon} = $predefAttrs{'roller_cmdIcon'};
          Log3 $name,5,"[Shelly_Get] the attribute \'cmdIcon\' of device $name is set  ";
          $v .= "cmdIcon attribute is set";
      }else{
          $v .= "attribute \'cmdIcon\' is already defined";
      }
      $v .= "\n";
      if(  !AttrVal($name,"eventMap",undef) ){ 
          # set the eventMap-attribute when the eventMap attribute is not set yet   
          if( AttrVal($name, "pct100", "closed") eq "closed" ){
                $attr{$hash->{NAME}}{eventMap} = $predefAttrs{'roller_eventMap_closed100'};
          }else{
                $attr{$hash->{NAME}}{eventMap} = $predefAttrs{'roller_eventMap_open100'};
          }
          Log3 $name,5,"[Shelly_Get] the attribute \'eventMap\' of device $name is set  ";
          $v .= "eventMap attribute is set";
      }else{
          $v .= "attribute \'eventMap\' is already defined";
      }
      $v .= "\n\n to see the changes, browser refresh is necessary";
      return $v;
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
  }elsif( $cmd =~ /(on|off)-for-timer/ || ($cmd eq"pct" && $ff!=1 )|| $cmd eq "brightness" || $cmd eq "ct" ){
        $channel = shift @a;
  } 
  
  #-- check channel
  if( $cmd =~ /^(toggle|on|off|pct|brightness)/ && $ff != 1){   # not for rollers
     if( $ff != 0 && $ff !=2 && $ff !=7 ){
          $msg = "Error: forbidden command  \'$cmd\' for device $name";
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
       my $subs = ""; 
       if( ($shelly_models{$model}[0]>1 && $mode ne "roller") || ($shelly_models{$model}[2]>1 && $mode eq "white") ){
          # we have a multi-channel device
          # toggle named channel of switch type device   or   RGBW-device
          $subs = "_".$channel; # channel;
          $cmd = (ReadingsVal($name,"relay".$subs,ReadingsVal($name,"state".$subs,"off")) eq "on") ? "off" : "on";
       }else{
          $cmd = (ReadingsVal($name,"state","off") eq "on") ? "off" : "on";
       }
       Log3 $name,5,"[Shelly_Set] transfer \'toggle\' to command \'$cmd\'";
  }
  

  #- - on and off
  if( $cmd =~ /^((on)|(off)).*/ ){
    #-- check timer command
    if( $cmd =~ /(.*)-for-timer/ ){
        $time = $value;
        $cmd = $1;
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
        $cmd = $cmd."&timer=$time";
    }
    # $cmd = is 'on' or 'off'  or  'on&timer=...' or 'off&timer=....'
    
    Log3 $name,4,"[Shelly_Set] switching channel $channel for device $name with command $cmd, FF=$ff";
    if( $ff==0 ){    
        if( $shelly_models{$model}[4] < 2 ){
            $cmd = "?turn=$cmd";  ##"/relay/$channel?turn=$cmd";
        }else{
            $cmd =~ s/on/true/;
            $cmd =~ s/off/false/;
            $cmd =~ s/timer/toggle_after/;
            $cmd = "/rpc/Switch.Set?id=$channel&on=$cmd";#. ($cmd=~/on/?"true":"false");
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
        $msg = Shelly_dim($hash,$channel,"?turn=$cmd");
    }elsif($ff==7 ){
        $msg = Shelly_dim($hash,"color/$channel","?turn=$cmd");
    }
    return $msg if( $msg );
    return;
  }
  
  if( ($cmd eq "pct" || $cmd eq "brightness") && $ff != 1 ){  #not for rollers
    if( $ff !=2 ){
          $msg = "Error: forbidden command  \'$cmd\' for device $name";
          Log3 $name,1,"[Shelly_Set] ".$msg;
          return $msg;
    }
     # check value
     if( !defined($value) ){
            $msg = "Error: no $cmd value \'$value\' given for device $name";
            Log3 $name,1,"[Shelly_Set] ".$msg;
            return $msg;
     }elsif( $value =~ /\D+/ ){    #anything else than a digit
            $msg = "Error: wrong $cmd value \'$value\' for device $name, must be <integer>";
            Log3 $name,1,"[Shelly_Set] ".$msg;
            return $msg;
     }elsif( $value<0  || $value>100 ){
            $msg = "$name Error: wrong $cmd value \'$value\' given, must be 0 ... 100 ";
            Log3 $name,1,"[Shelly_Set] ".$msg;
            return $msg;
     } 
    $cmd = "?brightness=".$value;
    Log3 $name,4,"[Shelly_Set] setting brightness for device $name to $value";
    if( $ff==2 ){
        if( $model =~ /shellydimmer/ ){
            $channel = "light/$channel"; 
        }elsif( $model =~ /shellybulb/ && $mode eq "white" ){ 
            $channel = "light/$channel";
        }elsif( $model =~ /shellyrgbw/ && $mode eq "white" ){
            $channel = "white/$channel";
        } 
        $msg = Shelly_dim($hash,$channel,$cmd);
        if( !$msg ){
            $cmd="?turn=off" if( $value == 0 );
            $cmd="?turn=on"  if( $value > 0 ); 
            $msg = Shelly_dim($hash,$channel,$cmd);
        }
    }
    return $msg if( $msg );
  
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
         return "$i devices for $name created";
      }else{
         $msg = "No separate channel device created for device $name, only one channel present";
         Log3 $name,1,"[Shelly_Set] ".$msg;
         return $msg;
      }
    }

  #-- commands strongly dependent on Shelly type
  ################################################################################################################ 
  #-- we have a switch type device / relay mode
  if( $shelly_models{$model}[0]>0 && $mode ne "roller" ){
    $ff = 0;
    Log3 $name,4,"[Shelly_Set] $name is a $model ". ($mode?"($mode mode)":"(switch type device)")."FF=$ff";

  ################################################################################################################  
  #-- we have a roller type device / roller mode
  }elsif( $shelly_models{$model}[1]>0 && $mode ne "relay" ){
    $ff = 1;
    Log3 $name,5,"[Shelly_Set] $name: we have a $model ($mode mode) and command is $cmd";
 #x   my $channel = $value;
    
    my $max=AttrVal($name,"maxtime",undef);
    my $maxopen =AttrVal($name,"maxtime_open",undef);
    my $maxclose=AttrVal($name,"maxtime_close",undef);
    
    #-- open 100% or 0% ?
    my $pctnormal = (AttrVal($name,"pct100","open") eq "open");
    my $reverse_delay=0;
    
    #-- commands from shelly actions
    if( $cmd eq "opening" ){
           $hash->{MOVING} = "drive-up";
    }elsif( $cmd eq "closing" ){
           $hash->{MOVING} = "drive-down";
    }elsif( $cmd eq "stopped" ){
           $hash->{MOVING} = "stopped";
    
    #-- stop, and stay stopped  
    }elsif( $cmd eq "stop"  ||  
            $cmd eq "zero"  ||
            $hash->{MOVING} eq "drive-down" &&  $cmd eq "closed"  ||
            $hash->{MOVING} eq "drive-up"   &&  $cmd eq "open"    ||
            $hash->{MOVING} =~ /drive/      &&  $cmd eq "pct"     ||
            $hash->{MOVING} =~ /drive/      &&  $cmd eq "delta"   ){
         Shelly_updown($hash,"?go=stop");
         # -- estimate pos here ???
         $hash->{DURATION} = 0;
         # calibration of roller device
         Shelly_configure($hash,"rc")   if( $cmd eq "zero" ) ;
         
    #-- in some cases we stop movement and start again in reverse direction
    }elsif(
            $hash->{MOVING} eq "drive-down" &&  $cmd eq "open"  ||
            $hash->{MOVING} eq "drive-up"   &&  $cmd eq "closed"   ){
         Log3 $name,1,"[Shelly_Set] stopping roller and starting after delay with command \'$cmd\'";
         Shelly_updown($hash,"?go=stop");
         # -- estimate pos here ???
         $hash->{DURATION} = 0;
         $reverse_delay=1.5;  # half of a second
         $hash->{CMD}=$cmd;
         RemoveInternalTimer($hash,"Shelly_Set");
         InternalTimer(gettimeofday()+$reverse_delay, "Shelly_Set", $hash, 1);
        
    #-- is moving !!!
    }elsif(  $hash->{MOVING}  ne "stopped"  ){
         Log3 $name,1,"[Shelly_Set] Error: received command \'$cmd\', but $name is still moving";
                
    #--any other cases: no movement and commands: open, closed, pct, delta    
    }else{
      if( $cmd =~ /(closed)|(open)/ ){
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
        $cmd .= "&duration=$value"
          if(defined($value));
      #  Shelly_updown($hash,$cmd);
      }elsif( $cmd eq "pct" || $cmd eq "delta" ){
          my $targetpct = $value;
          my $pos  = ReadingsVal($name,"position","");
          my $pct  = ReadingsVal($name,"pct",undef);  
             #if( "$value" =~ /[\+-]\d*/ ){
             #  $targetpct = eval($pct."$value"); 
             #}
        #-- check for sign
        if( $cmd eq "delta" ){
           if( $value =~ /[\+-]\d*/ ){
               $targetpct += $pct;
           }else{
               Log3 $name,1,"[Shelly_Set] $name: Wrong format, must consist of a plus or minus sign followed by an integer value";
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
      Shelly_updown($hash,$cmd);
    }    
  ################################################################################################################    
  #-- we have a Shelly dimmer type device or rgbw type device in white mode
  }elsif( ($model =~ /shellydimmer/) || (($model =~ /shellyrgbw.*/) && ($mode eq "white")) ){
    $ff = 2;
    
    
  ################################################################################################################
  #-- we have a Shelly dimmer type device or rgbw type device in white mode, or a ShellyBulbDuo
  }elsif( ($model =~ /shellybulb.*/) && ($mode eq "white") ){
    $ff = 2;
    
    if( $cmd eq "ct" ){
      $channel = shift @a;
      Shelly_dim($hash,"light/0","?temp=".$value);
    }
  ################################################################################################################    
  #-- we have a Shelly rgbw type device in color mode
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
      if ($model eq "shellybulb"){
          $cmd .= "&gain=100";
      }else{
          $cmd .= sprintf("&gain=%d",$value*100);  #new
      }
      Shelly_dim($hash,"color/0","?".$cmd);
      
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
      Shelly_dim($hash,"color/0","?".$cmd);
      
    }elsif( $cmd eq "white" ){  # value 0 ... 100
      $cmd=sprintf("white=%d",$value*2.55);
      Shelly_dim($hash,"color/0","?".$cmd);
    }elsif( $cmd eq "gain" ){  # value 0 ... 100
      $cmd=sprintf("gain=%d",$value);
      Shelly_dim($hash,"color/0","?".$cmd);
    }
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
  my $user = AttrVal($name, "shellyuser", '');
  return "" if(!$user);

  my ($err, $pw) = getKeyValue("SHELLY_PASSWORD_$name");
  return $user.":".$pw."@";
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
  return "no network information" if ( !defined $net );
  return "E: 1612 device not connected" 
    if( $net =~ /not connected/ );

  my $model =  AttrVal($name,"model","generic");
  my $creds = Shelly_pwd($hash);
  
  ##2ndGen    devices will answer with "null\R"
  if( $cmd eq "update" ){
    if( $shelly_models{$model}[4] == 1 ){
      $cmd="rpc/Shelly.Update?stage=%22stable%22" ;  #beta
    }else{
      $cmd="ota?update=true";
    }
  }elsif( $cmd eq "reboot" ){
    if( $shelly_models{$model}[4] == 1 ){
      $cmd="rpc/Shelly.Reboot" ;
    }
  }elsif( $cmd eq "rc" || $cmd eq "calibrate" ){
    if( $shelly_models{$model}[4] == 1 ){
      $cmd="rpc/Cover.Calibrate?id=0" ;  #Gen2
    }elsif( $shelly_models{$model}[1]==1  &&  AttrVal($name,"mode",undef) eq "roller" ){
      $cmd="roller/0/calibrate";
    }else{ 
      $cmd="settings?calibrate=1";  # shelly-dimmer
    }
  }

  Log3 $name,5,"[Shelly_configure] $name: received command=$cmd";

  if ( $hash && !$err && !$data ){
     my $url     = "http://$creds".$hash->{TCPIP}."/".$cmd;
     my $timeout = AttrVal($name,"timeout",4);
     Log3 $name,4,"[Shelly_configure] issue a non-blocking call to $url";
     HttpUtils_NonblockingGet({
        url      => $url,
        timeout  => $timeout,
        callback => sub($$$){ Shelly_configure($hash,$cmd,$_[1],$_[2]) }
     });
     return undef;
  }elsif ( $hash && $err ){
    Shelly_error_handling($hash,"Shelly_configure",$err);
    return;
  }
  Log3 $name,3,"[Shelly_configure] device $name has returned ".length($data)." bytes of data";
  Log3 $name,5,"[Shelly_configure] device $name has returned data:\n\"$data\"";
  
  return if( $data =~ /null\R/ );   #perl 5.10.0, in older versions: \r or \n 
    
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
  }
  
  Log3 $name,4,"[Shelly_configure] device $name processing \"$cmd\" ";
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
  
sub Shelly_status {
  my ($hash, $comp, $err, $data) = @_;
  my $name = $hash->{NAME};
  my $state = $hash->{READINGS}{state}{VAL};
  
  my $model = AttrVal($name,"model","generic");
  my $creds = Shelly_pwd($hash);
  my $url     = "http://$creds".$hash->{TCPIP};
  my $timeout = AttrVal($name,"timeout",4);
  
  # for any callbacks restart timer
  if ( $hash && $err && $hash->{INTERVAL} != 0 ){   ## ($err || $data )
      #-- cyclic update nevertheless
      RemoveInternalTimer($hash,"Shelly_status"); 
      my $interval=minNum(120,$hash->{INTERVAL});
      Log3 $name,3,"[Shelly_status] $name: Error in callback, update in $interval seconds";
      InternalTimer(gettimeofday()+$interval, "Shelly_status", $hash, 1);
  }
  
  # in any cases check for error in non blocking call
  if( $hash && $err ){
      Shelly_error_handling($hash,"Shelly_status",$err);
      return $err;
  }

  #-- check if 2nd generation device
  my $is2G = ($shelly_models{$model}[4] == 1);
#3G {  
  # preparing NonBlockingGet #--------------------------------------------------  

  if( $hash && !$err && !$data ){
      #-- for 1G devices status is received in one single call
      if( !$is2G ){
         $url     .= "/status";
         Log3 $name,4,"[Shelly_status(1G)] issue a non-blocking call to $url";  
         HttpUtils_NonblockingGet({
            url      => $url,
            timeout  => $timeout,
            callback => sub($$$){ Shelly_status($hash,undef,$_[1],$_[2]) }
         });
      #-- 2G devices 
      }else{
          my $comp = AttrVal($name,"mode","relay");
          $url .= "/rpc/";
          my $id=0;
          my $chn=1;  #number of channels
          if($model eq "shellypro3em"){ 
            $comp = "EM"; 
            $url  .= "EM.GetStatus";
          }elsif($model eq "shellypluspm"){
            $comp = "PM1";
            $url  .= "PM1.GetStatus";
            #$chn = $shelly_models{$model}[5];
          }elsif($model eq "shellyplusi4"){
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
  }elsif(ReadingsVal($name,"network","") !~ /connected to/){
    # as we have received a valid JSON, we know network is connected:
    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged($hash,"network","<html>connected to <a href=\"http://".$hash->{TCPIP}."\">".$hash->{TCPIP}."</a></html>",1);
    readingsEndUpdate($hash,1);  
  }
  
  my $next;  # Time offset in seconds for next update
  if( !$is2G ){
      $next=Shelly_proc1G($hash,$jhash);
  }else{
      $next=Shelly_proc2G($hash,$comp,$jhash);
  }
  Log3 $name,4,"[Shelly_status] $name: proc.G returned with value=$next for comp $comp"; #4
  return undef if( $next == -1 );  
  
  #-- cyclic update (or update close to on/off-for-timer command)
  
  if( !defined($next) || $next > 1.5*$hash->{INTERVAL} || $next==0 ){  # remaining timer as previously read
      $next = $hash->{INTERVAL};
  }elsif( $next > $hash->{INTERVAL} ){
      $next = 0.75*$hash->{INTERVAL};
  }
  

  Log3 $name,4,"[Shelly_status] $name: next update for comp=$comp in $next seconds "; #4
  RemoveInternalTimer($hash,"Shelly_status"); 
  InternalTimer(gettimeofday()+$next, "Shelly_status", $hash, 1)
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
  
  my $model = AttrVal($name,"model","generic");
  my $creds = Shelly_pwd($hash);
  my $url     = "http://$creds".$hash->{TCPIP};
  my $timeout = AttrVal($name,"timeout",4);
  
  Log3 $name,4,"[Shelly_shelly] $name is a ".($shelly_models{$model}[4]==0?"first":"second")." Gen device";  
  #-- check if 2nd generation device
  if ($shelly_models{$model}[4] != 1){
      Log3 $name,4,"[Shelly_shelly] intentionally aborting, $name is not 2nd Gen";  
      return undef ;
  }

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

    Shelly_webhook($hash,"Check"); # check webhooks regarding change of port, token etc.
    Shelly_webhook($hash,"Count"); # check number of webhooks on Shelly
 
    ### cyclic update ###
    RemoveInternalTimer($hash,"Shelly_shelly");
    return undef
        if( $hash->{INTERVAL} == 0 ); 
        
    my $offset = 120; #$hash->{INTERVAL};
    if( $model eq "shellypro3em" ){ 
        # updates at every multiple of 60 seconds
        $offset = $hash->{INTERVAL}<=60 ? 60 : int($hash->{INTERVAL}/60)*60 ;
        # adjust to get readings 2sec after full minute
        $offset = $offset + 2 - gettimeofday() % 60;
    }
    Log3 $name,4,"[Shelly_shelly] $name: long update in $offset seconds, Timer is Shelly_shelly";  #4
    InternalTimer(gettimeofday()+$offset, "Shelly_shelly", $hash, 1);  
    return undef;
}



########################################################################################
# 
# Shelly_proc1G - process data from device 1st generation
#                   In 1G devices status are all in one call
#
########################################################################################

sub Shelly_proc1G {
  my ($hash, $jhash) = @_;
  $hash->{units}=0 if ( !defined($hash->{units}) );
  my $name  = $hash->{NAME};
  my $state = $hash->{READINGS}{state}{VAL};
  
  my $model = AttrVal($name,"model","generic");
    

  my $mode     =  AttrVal($name,"mode","");
  my $channels = $shelly_models{$model}[0];
  my $rollers  = $shelly_models{$model}[1];
  my $dimmers  = $shelly_models{$model}[2];
  my $meters   = $shelly_models{$model}[3];
 
  my ($subs,$ison,$source,$rstate,$rstopreason,$rcurrpos,$position,$rlastdir,$pct,$pctnormal);
  my ($overpower,$power,$energy);
  my $intervalN=$hash->{INTERVAL};   # next update interval
  
  readingsBeginUpdate($hash);
  Shelly_readingsBulkUpdate($hash,"network","<html>connected to <a href=\"http://".$hash->{TCPIP}."\">".$hash->{TCPIP}."</a></html>",1); 
  readingsBulkUpdateMonitored($hash,"network_rssi",$jhash->{'wifi_sta'}{'rssi'} ) 
                                                                      if( $jhash->{'wifi_sta'}{'rssi'} ); 
  readingsBulkUpdateMonitored($hash,"network_ssid",$jhash->{'wifi_sta'}{'ssid'} ) 
                                                                      if( $jhash->{'wifi_sta'}{'ssid'} );
  
  #-- for all models set internal temperature reading and status
  if ($jhash->{'temperature'}) {
    readingsBulkUpdateMonitored($hash,"inttemp",$jhash->{'temperature'}.$si_units{tempC}[$hash->{units}])
  }elsif($jhash->{'tmp'}{'tC'}) {
    readingsBulkUpdateMonitored($hash,"inttemp",$jhash->{'tmp'}{'tC'}.$si_units{tempC}[$hash->{units}])
  }
                                                                      ; 
  readingsBulkUpdateMonitored($hash,"inttempStatus",$jhash->{'temperature_status'}) 
                                                                      if ($jhash->{'temperature_status'}) ;
  readingsBulkUpdateMonitored($hash,"overtemperature",$jhash->{'overtemperature'}) 
                                                                       if ($jhash->{'overtemperature'});
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
    if ($model eq "shellyuni") {
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
      if ($dimmers > 1);
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
    
    if ( defined $gain && $gain <= 100 ) { # !=
      $red   = round($red*$gain/100.0  ,0);
      $blue  = round($blue*$gain/100.0 ,0);
      $green = round($green*$gain/100.0,0);
    }
    if(0){  # not supported by /status - call
    my $transition  = $jhash->{'lights'}[0]{'transition'};  # 0 .... 5000
    Shelly_readingsBulkUpdate($hash,"transition",$transition.$si_units{transition}[$hash->{units}]); 
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
  #readingsBulkUpdateIfChanged($hash,"coiot",$hascoiot?"enabled":"disabled");  
  
 
  #-- looking for metering values; common to all models with at least one metering channel  
  Log3 $name,4,"[Shelly_proc1G] $name: Looking for metering values";
  if( $shelly_models{$model}[3]>0 ){

    #-- Shelly RGBW in color mode has only one metering channel
    $meters = 1   if ( $mode eq "color" );

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
                                             if ( $power > 0 ); 
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
        $ison = "unknown" if (length($ison)==0);
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
  if ($jhash->{'ext_temperature'}) {
    my %sensors = %{$jhash->{'ext_temperature'}};
    foreach my $temp (keys %sensors){
      readingsBulkUpdateMonitored($hash,"temperature_".$temp,$sensors{$temp}->{'tC'}.$si_units{tempC}[$hash->{units}]); 
    }
  }
  if ($jhash->{'ext_humidity'}) {
    my %sensors = %{$jhash->{'ext_humidity'}};
    foreach my $hum (keys %sensors){
      readingsBulkUpdateMonitored($hash,"humidity_".$hum,$sensors{$hum}->{'hum'}.$si_units{relHumidity}[$hash->{units}]); 
    }
  }
  #-- look if name of Shelly has been changed
  if( defined($jhash->{'name'}) && AttrVal($name,"ShellyName","") ne $jhash->{'name'} ){ #ShellyName  we don't have this reading here!
     ##readingsBulkUpdateIfChanged($hash,"name",$jhash->{'name'} );
     $attr{$hash->{NAME}}{ShellyName} = $jhash->{'name'};
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
  $hash->{units}=0 if ( !defined($hash->{units}) );
  my $name  = $hash->{NAME};
  my $state = $hash->{READINGS}{state}{VAL};  
  my $model = AttrVal($name,"model","generic");
  my $mode  = AttrVal($name,"mode","");
 
  my $channel  = undef; 
     $channel  = $jhash->{'id'}  if( $comp eq "relay" || $comp eq "roller" || $comp eq "input" );
  my $rollers  = $shelly_models{$model}[1];
  my $dimmers  = $shelly_models{$model}[2];
  my $meters   = $shelly_models{$model}[3];
 
  my ($subs,$ison,$overpower,$voltage,$current,$power,$energy,$pfactor,$freq,$minutes,$errors);  ##R  minutes errors
  my $timer = $hash->{INTERVAL};

  # check we have a second gen device
  if( $shelly_models{$model}[4]!=1 ){
        return "ERROR: calling Proc2G for a not 2ndGen Device";
  }
   
  Log3 $name,4,"[Shelly_proc2G] device $name of model $model processing component $comp"; 
  
  readingsBeginUpdate($hash);
   
  if($shelly_models{$model}[0]>1 && ($shelly_models{$model}[1]==0 || $mode eq "relay")){
          readingsBulkUpdate($hash,"state","OK",1);  #set state for mulitchannel relay-devices; for rollers state is 'stopped' or 'drive...'
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
      readingsBulkUpdateMonitored($hash,"last_dir".$subs,$rlastdir)  if ($rlastdir ne "unknown");
      $hash->{MOVING}   = $rstate; 
      $hash->{DURATION} = 0;
      Log3 $name,5,"[Shelly_proc2G] Roller id=$id  action=$raction  state=$rstate  Last dir=$rlastdir";

      #-- for roller devices store last power & current value (otherwise you mostly see nothing)
      if( $mode eq "roller" ){
          $power = ReadingsNum($name,"power".$subs,0);
          Shelly_readingsBulkUpdate($hash,"power_last".$subs, 
             $power.$si_units{power}[$hash->{units}]." ".
             ReadingsVal($name,"last_dir".$subs,""),
             undef,
             ReadingsTimestamp($name,"power".$subs,"") )
                                             if ( $power > 0 );
          $current = ReadingsNum($name,"current".$subs,0);
          Shelly_readingsBulkUpdate($hash,"current_last".$subs, 
             $current.$si_units{current}[$hash->{units}]." ".
             ReadingsVal($name,"last_dir".$subs,""),
             undef,
             ReadingsTimestamp($name,"current".$subs,"") )
                                             if ( $current > 0 ); 
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

      readingsBulkUpdateMonitored($hash,"pct".$subs,$pct);
      readingsBulkUpdateMonitored($hash,"position".$subs,$position);
      readingsBulkUpdateMonitored($hash,"state".$subs,$rstate);

  ############retrieving EM power values rpc/EM.GetStatus?id=0
  }elsif ($comp eq "EM"){
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

      ### cumulate power values and save them in helper, will be used by Shelly_EMData()
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
        Log3 $name,6,"[Shelly_proc2G:status] Processing status for device $name L.3181";

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
         Log3 $name,5,"[Shelly_proc2G] $name: hasconn=" . ($hasconn?"true":"false");
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
       my $firmware = ReadingsVal($name,"firmware","none"); 
       $firmware = $1 
              if( $firmware =~ /^(.*?)\(/ );
       my $txt = ($firmware =~ /beta/ )?"update possible to latest stable v":"update needed to v";
       if( $update ){
              Log3 $name,5,"[Shelly_proc2G] $name: $txt$update   current in device: $firmware";
              $firmware .= "($txt$update)";
              readingsBulkUpdateIfChanged($hash,"firmware",$firmware);  
       }else{ # maybe there is a beta version available
          $update = $jhash->{'sys'}{'available_updates'}{'beta'}{'version'};
          if( $update ){
              Log3 $name,5,"[Shelly_proc2G] $name: $firmware --> $update";
              $firmware .= "(update possible to v$update)";
              readingsBulkUpdateIfChanged($hash,"firmware",$firmware);  
          }
       }
       
       #checking if connected to wifi / LAN
       #is similiar given as answer to rpc/Wifi.GetStatus
       my $eth_ip = $jhash->{'eth'}{'ip'};
       my $local_ip   = $jhash->{'wifi'}{'sta_ip'};
       my $wifi_status= $jhash->{'wifi'}{'status'};
       if( $eth_ip ){
           if( $eth_ip ne "" && $wifi_status eq "got ip" ){ 
              readingsBulkUpdateIfChanged($hash,"network","<html>connected to <a href=\"http://".$eth_ip."\">".$eth_ip."</a> (LAN, Wifi)</html>");
           }elsif( $eth_ip ne "" ){ 
              Shelly_readingsBulkUpdate($hash,"network","<html>connected to <a href=\"http://".$eth_ip."\">".$eth_ip."</a> (LAN)</html>");
           }
       }elsif( $local_ip && $wifi_status eq "got ip"){
              readingsBulkUpdateIfChanged($hash,"network","<html>connected to <a href=\"http://".$local_ip."\">".$local_ip."</a> (Wifi)</html>");
       }else{
              Shelly_error_handling($hash,"Shelly_proc2G:status","not connected");
       }
       if( $wifi_status eq "got ip"){
              readingsBulkUpdateIfChanged($hash,"network_ssid",$jhash->{'wifi'}{'ssid'});
              readingsBulkUpdateIfChanged($hash,"network_rssi",$jhash->{'wifi'}{'rssi'}.$si_units{rssi}[$hash->{units}]);
       }else{ #    if( $wifi_status eq "disconnected"){
              readingsBulkUpdateIfChanged($hash,"network_ssid",'-');
              readingsBulkUpdateIfChanged($hash,"network_rssi",'-');
       }

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
    
    #********
    if( $model =~ /walldisplay/ ){
            $subs ="";
            # readings supported by the /Shelly.GetStatus call or by individual calls eg /Temperature.GetStatus
            readingsBulkUpdateMonitored($hash,"temperature" .$subs,$jhash->{'temperature:0'}{'tC'}.$si_units{tempC}[$hash->{units}] );
            readingsBulkUpdateMonitored($hash,"humidity"    .$subs,$jhash->{'humidity:0'}{'rh'}.$si_units{relHumidity}[$hash->{units}] );
            readingsBulkUpdateMonitored($hash,"illuminance" .$subs,$jhash->{'illuminance:0'}{'lux'}.$si_units{illum}[$hash->{units}] );
            readingsBulkUpdateMonitored($hash,"illumination".$subs,$jhash->{'illuminance:0'}{'illumination'} );        
    }
    #********
    
    ################ Shelly.GetConfig
    }elsif ($comp eq "config"){
        Log3 $name,4,"[Shelly_proc2G:config] $name: processing the answer rpc/Shelly.GetConfig from Shelly_shelly()";

        #Cloud
        my $hascloud = $jhash->{'cloud'}{'enable'};
        Log3 $name,5,"[Shelly_proc2G:config] $name: hascloud=" . ($hascloud?"true":"false");
        if (!$hascloud ){  # cloud disabled
             readingsBulkUpdateIfChanged($hash,"cloud","disabled");
        }elsif(ReadingsVal($name,"cloud","none") !~ /enabled/){
             readingsBulkUpdateIfChanged($hash,"cloud","enabled");
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

    ################ Shelly.GetDeviceInfo          
    }elsif ($comp eq "info"){
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
       if( defined($jhash->{'name'}) && AttrVal($name,"ShellyName","") ne $jhash->{'name'}) {  #ShellyName 
           ##readingsBulkUpdateIfChanged($hash,"name",$jhash->{'name'} );
           $attr{$hash->{NAME}}{ShellyName} = $jhash->{'name'}; 
       }else{ 
           # if Shelly is not named, set name of Shelly equal to name of Fhem-device
           ##fhem("set $name name " . $name ); 
           $attr{$hash->{NAME}}{ShellyName} = $name;  #set ShellyName as attribute
       }
    }
    
    #############################################################################################################################
    #-- common to roller and relay, also ShellyPlusPMmini energymeter
    if($comp eq "roller" || $comp eq "relay" || $comp eq "PM1" ){
      Log3 $name,4,"[Shelly_proc2G] $name: Processing metering channel$subs";
      if( $meters > 0 ){
        #checking for errors (if present)
        $errors  = $jhash->{'errors'}[0];
        $errors = "none" 
           if (!$errors);

        $voltage = $jhash->{'voltage'}.$si_units{voltage}[$hash->{units}];
        $current = $jhash->{'current'}.$si_units{current}[$hash->{units}];
        $power   = $jhash->{'apower'} .$si_units{power}[$hash->{units}];   # active power

        $energy  = shelly_energy_fmt($hash,$jhash->{'aenergy'}{'total'},"Wh");
        # Energy consumption by minute (in Milliwatt-hours) for the last minute
        $minutes = shelly_energy_fmt($hash,$jhash->{'aenergy'}{'by_minute'}[0],"mWh");
      
        Log3 $name,4,"[Shelly_proc2G] $name $comp voltage$subs=$voltage, current$subs=$current, power$subs=$power";  #4
       
        readingsBulkUpdateMonitored($hash,"voltage".$subs,$voltage);  
        readingsBulkUpdateMonitored($hash,"current".$subs,$current);  
        readingsBulkUpdateMonitored($hash,"power"  .$subs,$power);
        # PowerFactor not supported by ShellyPlusPlugS, ShellyPlusPMmini and others
        readingsBulkUpdateMonitored($hash,"pfactor".$subs,$jhash->{'pf'}) if( defined($jhash->{'pf'}) );
        
        # frequency supported from fw 1.0.0 
        readingsBulkUpdateMonitored($hash,"frequency".$subs,$jhash->{'freq'}.$si_units{frequency}[$hash->{units}])
                                                                          if( defined($jhash->{'freq'}) ); 
        
        readingsBulkUpdateMonitored($hash,"energy" .$subs,$energy);  
        readingsBulkUpdateMonitored($hash,"energy_lastMinute".$subs,$minutes); 
        readingsBulkUpdateMonitored($hash,"protection".$subs,$errors);
        
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
    }
    readingsEndUpdate($hash,1);
    
    if ($comp eq "status" || $comp eq "config" || $comp eq "info"){
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
  $hash->{units}=0 if ( !defined($hash->{units}) );
  my $name  = $hash->{NAME};
  my $state = $hash->{READINGS}{state}{VAL};  
  my $model = AttrVal($name,"model","generic");

  # check we have a second gen device
  if( $shelly_models{$model}[4]!=1 || $model ne "shellypro3em" ){
        return "$name ERROR: calling Proc2G for a not 2ndGen Device";
  }

  if ( $hash && !$err && !$data ){
    if( $model eq "shellypro3em" ){
          $comp = "EMData";
    }
       
    # my $url     = "http://".Shelly_pwd($hash).$hash->{TCPIP}."/rpc/$comp.GetStatus?id=0";
    my $url     = "http://".Shelly_pwd($hash).$hash->{TCPIP}."/rpc/Shelly.GetStatus";   # all data in one loop
    Log3 $name,4,"[Shelly_status] issue a non-blocking call to $url";
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
    my $Tupdate = int((gettimeofday()+60)/60)*60+1;
    Log3 $name,4,"[Shelly_EMData] $name: next EMData update at $Tupdate = ".strftime("%H:%M:%S",localtime($Tupdate) )." Timer is Shelly_EMdata";
    InternalTimer($Tupdate, "Shelly_EMData", $hash, 1)
      if( $hash->{INTERVAL} != 0 );
  }

  #-- error in non blocking call  
  if ( $hash && $err ){
    Shelly_error_handling($hash,"Shelly_EMData",$err);
    return $err;
  }

  Log3 $name,5,"[Shelly_EMData] device $name has returned data $data";
  
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
        my ($active_energy,$return_energy,$deltaEnergy,$deltaAge,$timestamp,$TimeStamp);
      
        $timestamp = $jhash->{'sys'}{'unixtime'};
        readingsBulkUpdateMonitored($hash,"timestamp",strftime("%Y-%m-%d %H:%M:%S",localtime($timestamp) ) );
 
        # Energy Readings are calculated by the Shelly every minute, matching "zero"-seconds
        # with some processing time the result will appear in fhem some seconds later
        # we adjust the Timestamp to Shellies time of calculation and use a propretary version of the 'readingsBulkUpdateMonitored()' sub
        $TimeStamp = FmtDateTime($timestamp-$timestamp%60);
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
          if ( defined($jhash->{'em:0'}{$emch.'errors'}[0]) ){
              #$errors  = $jhash->{'em:0'}{$emch.'errors'}[0];
              #$errors .= "$pr$ps: $errors " if ( defined($errors) );
              $errors .= "$pr$ps: ".$jhash->{'em:0'}{$emch.'errors'}[0];
          }   
        }
        # checking for EM-system errors
        # may contain:  power_meter_failure, phase_sequence, no_load
        if( $jhash->{'em:0'}{'errors'}[0] ){
              $errors .= "System: ".$jhash->{'em:0'}{'errors'}[0];
        }
    #    if( defined($errors) ){
             readingsBulkUpdateMonitored($hash,"errors",defined($errors)?$errors:"OK");
     #        readingsBulkUpdateMonitored($hash,"state","Error");
      #  }

       # $value = $jhash->{'em:0'}{'errors'}[0];
       # $value = defined($value)?$value:"OK";
       # readingsBulkUpdateMonitored($hash,"state",$value);
        
        $value = $jhash->{'temperature:0'}{'tC'}.$si_units{tempC}[$hash->{units}];
        readingsBulkUpdateMonitored($hash,"inttemp",$value);

        #initialize helper values to avoid error in first run 
        if ( !defined( $hash->{helper}{timestamp_last} ) ){
              $hash->{helper}{timestamp_last} = $timestamp - 60;
              $hash->{helper}{Total_Energy_S}=0;
              $hash->{helper}{powerPos} = 0;
              $hash->{helper}{powerNeg} = 0;
              $hash->{helper}{Energymeter_P}=0;#$active_energy;
              $hash->{helper}{Energymeter_R}=0;#=$return_energy;
              $hash->{helper}{Energymeter_F}=0;#=$active_energy-$return_energy;
        }   
        
     ### processing calculated values ###
     ### 1. calculate Total Energy
        $value = shelly_energy_fmt($hash,$active_energy - $return_energy,"Wh");
        Shelly_readingsBulkUpdate($hash,"Total_Energy_S",$value,undef,$TimeStamp);
     
     ### 2. calculate a power value from the difference of Energy measures
        $deltaAge = $timestamp - $hash->{helper}{timestamp_last};
        $deltaEnergy  = $active_energy - $return_energy - $hash->{helper}{Total_Energy_S};
        #$hash->{helper}{active_energy_last} = $deltaEnergy;     
        $reading = $pr.$mapping{E1}{"act_calc"};
        $value  = sprintf("%4.1f",3600*$deltaEnergy/$deltaAge) if( $deltaAge>0 );  # this is a Power value in Watts.
        $value .= $si_units{power}[$hash->{units}]; 
        $value .= sprintf(" \( %d Ws = %5.2f Wh in %d s \)",3600*$deltaEnergy,$deltaEnergy,$deltaAge);
        Shelly_readingsBulkUpdate($hash,$reading,$value,undef,$TimeStamp);
        
      ### 3. calculate a power value by integration of single power values
      ### calculate purchased and returned Energy out of integration of positive and negative power values
      my $mypower=0;
      my ($mypowerPos,$mypowerNeg);
      my ($active_energy_i,$return_energy_i);
      if( $hash->{helper}{powerCnt} ){   # don't divide by zero
         $mypower = sprintf("%4.1f %s (%d values)", $hash->{helper}{power}/$hash->{helper}{powerCnt},
                                                    $si_units{power}[$hash->{units}],$hash->{helper}{powerCnt} );

         $mypowerPos = $hash->{helper}{powerPos} / $hash->{helper}{powerCnt};
         $mypowerNeg = $hash->{helper}{powerNeg} / $hash->{helper}{powerCnt};
         $active_energy_i = $mypowerPos/60 + $hash->{helper}{Energymeter_P};    # Energy in Watthours
         $return_energy_i = $mypowerNeg/60 + $hash->{helper}{Energymeter_R};
         Log3 $name,6,"[a] integrated Energy= $active_energy_i   $return_energy_i   in Watthours";
         $mypowerPos = sprintf("%4.1f %s (%d Ws = %5.2f Wh)", $mypowerPos,$si_units{power}[$hash->{units}],$mypowerPos*60,$mypowerPos/60 );
         $mypowerNeg = sprintf("%4.1f %s (%d Ws = %5.2f Wh)", $mypowerNeg,$si_units{power}[$hash->{units}],$mypowerNeg*60,$mypowerNeg/60);
      } 
      readingsBulkUpdateMonitored($hash,$pr.$mapping{E1}{act_integrated},$mypower);
      readingsBulkUpdateMonitored($hash,$pr.$mapping{E1}{act_integratedPos},$mypowerPos);
      readingsBulkUpdateMonitored($hash,$pr.$mapping{E1}{act_integratedNeg},$mypowerNeg);
      # reset helper values. They will be set while cyclic update of power values. A small update interval is necessary!
      $hash->{helper}{power} = 0;
      $hash->{helper}{powerPos} = 0;
      $hash->{helper}{powerNeg} = 0;
      $hash->{helper}{powerCnt} = 0;  
                
     ### 4. safe these values for later use, independent of readings format, in Wh.
        # We need them also to adjust the offset-attribute, see Shelly_attr():
        $hash->{helper}{timestamp_last} = $timestamp;
        $hash->{helper}{Total_Energy_S} =$active_energy-$return_energy;
        $hash->{helper}{Energymeter_P}=$active_energy_i;
        $hash->{helper}{Energymeter_R}=$return_energy_i;
        $hash->{helper}{Energymeter_F}=$active_energy_i-$return_energy_i;
 
     
if(0){        # calculate the suppliers meter value
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
            $value = sprintf("%7.2f",$value+AttrVal($name,"Energymeter_$EM",50000));
            $value = shelly_energy_fmt($hash, $value,"Wh");
            Shelly_readingsBulkUpdate($hash,"Total_Energymeter_$EM", $value, undef, $TimeStamp);
          }
        } 
                  }
        
     ### 4b. write out actual balanced meter values
        readingsBulkUpdateMonitored($hash,"Purchased_Energy_T",shelly_energy_fmt($hash,$active_energy_i,"Wh"));
        readingsBulkUpdateMonitored($hash,"Returned_Energy_T", shelly_energy_fmt($hash,$return_energy_i,"Wh"));
        readingsBulkUpdateMonitored($hash,"Total_Energy_T",    shelly_energy_fmt($hash,$active_energy_i-$return_energy_i,"Wh"));
        
      
        
     ### 5. calculate Energy-differences for a set of different periods
        #prepare the list of periods
        my @TPs=split(/,/x, AttrVal($name,"Periods", "") );
        
        #initialize helper values
        foreach my $TP (@TPs){
            # Shellie'S Energy value 'S'
            readingsBulkUpdateMonitored($hash,"Total_Energy_S_".$TP,"0 (".($active_energy - $return_energy).") 0") 
                                if(ReadingsNum($name,"Total_Energy_S_".$TP,"-") eq "-");
            readingsBulkUpdateMonitored($hash,"Purchased_Energy_S_".$TP,"0 \($active_energy\) 0") 
                                if(ReadingsNum($name,"Purchased_Energy_S_".$TP,"-") eq "-");
            readingsBulkUpdateMonitored($hash,"Returned_Energy_S_".$TP,"0 \($return_energy\) 0") 
                                if(ReadingsNum($name,"Returned_Energy_S_".$TP,"-") eq "-");
            # integrated (balanced) energy values 'T'
            readingsBulkUpdateMonitored($hash,"Total_Energy_T_".$TP,"0 \(".($active_energy_i-$return_energy_i)."\) 0") 
                                if(ReadingsNum($name,"Total_Energy_T_".$TP,"-") eq "-");
            readingsBulkUpdateMonitored($hash,"Purchased_Energy_T_".$TP,"0 \($active_energy_i\) 0") 
                                if(ReadingsNum($name,"Purchased_Energy_T_".$TP,"-") eq "-");
            readingsBulkUpdateMonitored($hash,"Returned_Energy_T_".$TP,"0 \($return_energy_i\) 0") 
                                if(ReadingsNum($name,"Returned_Energy_T_".$TP,"-") eq "-");
        }

        #calculate all periods
        my $dst = fhem('{$isdst}'); # is daylight saving time (Sommerzeit) ?   gets a log entry {$isdst} at level 3
        foreach my $TP (@TPs)
        {
           Log3 $name,5,"[Shelly__proc2G:status] calling shelly_delta_energy for period \'$TP\' ";
           shelly_delta_energy($hash,"Total_Energy_S_",    $TP,$timestamp,$active_energy-$return_energy,$TimeStamp,$dst);
           shelly_delta_energy($hash,"Purchased_Energy_S_",$TP,$timestamp,$active_energy,$TimeStamp,$dst);
           shelly_delta_energy($hash,"Returned_Energy_S_", $TP,$timestamp,$return_energy,$TimeStamp,$dst);
           # integrated energy values
           shelly_delta_energy($hash,"Total_Energy_T_",    $TP,$timestamp,$active_energy_i-$return_energy_i,$TimeStamp,$dst); # $return_energy is positive
           shelly_delta_energy($hash,"Purchased_Energy_T_",$TP,$timestamp,$active_energy_i,$TimeStamp,$dst);
           shelly_delta_energy($hash,"Returned_Energy_T_", $TP,$timestamp,$return_energy_i,$TimeStamp,$dst);
        }    
       
      
    }
    
    readingsEndUpdate($hash,1);
    return undef;
}
     
########################################################################################
#
# shelly_delta_energy - calculate energy for a periode 
#
# Parameter hash, ...
#
########################################################################################
sub shelly_delta_energy {
  my ($hash,$reading,$TP,$timestamp,$energy,$TimeStamp,$dst) = @_;
  my $name=$hash->{NAME};
  my ($energyOld,$timestampRef,$dtime);

       $reading .= $TP;   
       $timestampRef=time_str2num(ReadingsTimestamp($hash->{NAME},$reading,"2023-07-01 00:00:00")); #convert to epoch-time, like str2time
       $dtime = $timestamp - $timestampRef;
       return if(!$periods{$TP}[2]); #avoid illegal modulus
       $timestampRef = $timestampRef + $periods{$TP}[2] - ($timestampRef+$periods{$TP}[$dst]) % $periods{$TP}[2];  #adjust to last full minute,hour,etc.

       if( $timestamp >= $timestampRef ){
              my $energyF= sprintf(" (%7.4f) ",$energy);
              $energyOld=ReadingsVal($hash->{NAME},$reading,$energyF);
              $energyOld=~ /.*\((.*)\).*/;
              $energyOld=$1;
              my $corrFactor= ($TP=~/(_c)$/)?InternalVal($name,"CORR",1):1;
              my $value= ($energy - $energyOld)*$corrFactor;
              $value = 0 if(abs($value) < 0.001);
              my $power = $dtime ? sprintf(" %4.1f %s",3600*$value/$dtime,$si_units{power}[$hash->{units}]) : "-";
              $value = shelly_energy_fmt($hash,$value,"Wh").$energyF.$power;
              Log3 $name,6,"[shelly_delta_energy] writing: $name <$TP> $reading $value $TimeStamp f=$corrFactor";
              readingsBulkUpdate($hash,$reading,$value, undef, $TimeStamp);
              return "-";
              #return $value;
       }else{
       Log3 $name,6,"[shelly_delta_energy] no value set for reading $reading";
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
      $decimals += 3;
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
    
  if ( $hash && !$err && !$data ){
     my $url     = "http://$creds".$hash->{TCPIP}."/$channel$cmd";
     my $timeout = AttrVal($name,"timeout",4);
     Log3 $name,4,"[Shelly_dim] issue a non-blocking call to $url";  
     HttpUtils_NonblockingGet({
        url      => $url,
        timeout  => $timeout,
        callback => sub($$$){ Shelly_dim($hash,$channel,$cmd,$_[1],$_[2]) }
     });
     return undef;
  }elsif ( $hash && $err ){
    Shelly_error_handling($hash,"Shelly_dim",$err);
    return;
  }
  Log3 $name,5,"[Shelly_dim] device $name has returned data $data";
    
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
  }elsif( $cmd  =~ /\?brightness=(.*)/){
    my $cmd2 = $1;
    if( $bright ne $cmd2 ) {
      Log3 $name,1,"[Shelly_dim] returns without success for device $name, desired brightness $cmd, but device brightness=$bright";
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
  InternalTimer(gettimeofday()+0.5, "Shelly_status", $hash,0);

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
    
  if ( $hash && !$err && !$data ){
     my $url     = "http://$creds".$hash->{TCPIP}."/roller/0".$cmd;
     my $timeout = AttrVal($name,"timeout",4);
     Log3 $name,4,"[Shelly_updown] issue a non-blocking call to $url";  
     HttpUtils_NonblockingGet({
        url      => $url,
        timeout  => $timeout,
        callback => sub($$$){ Shelly_updown($hash,$cmd,$_[1],$_[2]) }
     });
     return undef;
  }elsif ( $hash && $err ){
    Shelly_error_handling($hash,"Shelly_updown",$err);
    return;
  }
  Log3 $name,5,"[Shelly_updown] has obtained data $data";
    
  my $json = JSON->new->utf8;
  my $jhash = eval{ $json->decode( $data ) };
  if( !$jhash ){
    if( ($model =~ /shelly(plus|pro)?2.*/) && ($data =~ /Device mode is not roller!/) ){  ##R
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
if(0){  
    if( $shelly_models{$model}[4] == 0){  # 1Gen
        #-- after 1 second call power measurement
        InternalTimer(gettimeofday()+1, "Shelly_updown2", $hash,1);
    }else{   #2Gen
        Log3 $name,5,"[Shelly_updown] calling Shelly_status for Metering of Gen2-Device";
        InternalTimer(gettimeofday()+1, "Shelly_status", $hash);
    }
}else{
  #-- perform two updates: after starting of drive, after expected stopping of drive
  if( $hash->{INTERVAL}>0 ){
      $hash->{DURATION} = 5 if( !$hash->{DURATION} );    # duration not provided by Gen2
      RemoveInternalTimer($hash,"Shelly_status");
      InternalTimer(gettimeofday()+0.5, "Shelly_status", $hash); # after that: next update in reduced interval sec
      InternalTimer(gettimeofday()+$hash->{DURATION}+0.5, "Shelly_interval", $hash,1); # reset interval
  }
}
  }
  return undef;
}


sub Shelly_interval($){
  my ($hash) =@_;
  $hash->{INTERVAL} = AttrVal($hash->{name},"interval",60);
  Log3 $hash->{NAME},3,"[Shelly_interval] interval reset to ".$hash->{INTERVAL};
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
  my $timeout = AttrVal($name,"timeout",4);
  my $creds = Shelly_pwd($hash);
    
  if ( $hash && !$err && !$data ){
     my $callback;
     my $url     = "http://$creds".$hash->{TCPIP};
if(1){
     $url .= "/relay/$channel$cmd";
     $callback="/relay/$channel$cmd";
}else{
     $cmd =~ /(id=\d)/;
     $callback= $url."/rpc/Switch.GetStatus?$1";
     $url .= $cmd;
}
     Log3 $name,4,"[Shelly_onoff] issue a non-blocking call to $url; callback to Shelly_onoff with command $callback";  
     HttpUtils_NonblockingGet({
        url      => $url,
        timeout  => $timeout,
        callback => sub($$$){ Shelly_onoff($hash,$channel,$callback,$_[1],$_[2]) }
     });
     return undef;
  }elsif ( $hash && $err ){
    Shelly_error_handling($hash,"Shelly_onoff",$err);
    return;
  }
  
  #processing incoming data
  Log3 $name,5,"[Shelly_onoff:callback] device $name has returned data \n$data";
    
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
  
    my $ison        = $jhash->{'ison'};
    my $hastimer    = undef;
    my $onofftimer  = 0;
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
  readingsBulkUpdateMonitored($hash,"source".$subs,$source); 

  if( $shelly_models{$model}[0] == 1 ){
    readingsBulkUpdateMonitored($hash,"state",$ison);
  }else{
    readingsBulkUpdateMonitored($hash,"state","OK");
  }
  readingsBulkUpdateMonitored($hash,"relay".$subs,$ison);

  readingsBulkUpdateMonitored($hash,"overpower".$subs,$overpower)
                       if( $shelly_models{$model}[3]>0 && $model ne "shelly1" );
  readingsEndUpdate($hash,1);

  #-- Call status after switch.    
  if( $hash->{INTERVAL}>0 ){
      $onofftimer = ($onofftimer % $hash->{INTERVAL}) + 0.5; #modulus
  }
  RemoveInternalTimer($hash,"Shelly_status");
  InternalTimer(gettimeofday()+$onofftimer, "Shelly_status", $hash,0);

  return undef;
}


########################################################################################
#
# Shelly_webhook - Retrieve webhook data
#                 acts as callable program Shelly_webhook($hash,$cmd)
#                                      or  Shelly_webhook($hash)     with $cmd via $hash
#                 and as callback program  Shelly_webhook($hash,$cmd,$err,$data)
# 
# Parameter hash, $cmd: Create,List,Update,Delete a webhook
#
########################################################################################

 sub Shelly_webhook {
  my ($hash, $cmd, $err, $data) = @_;
  my $name  = $hash->{NAME};
  my $state = $hash->{READINGS}{state}{VAL};
  my $net   = $hash->{READINGS}{network}{VAL};
  
     my ($host_token,$host_url);
  
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
    #Log3 $name,3,"[Shelly_webhook] Proceeding with command \'$cmd\' for device $name";
  }
  Log3 $name,5,"[Shelly_webhook] proceeding with command \'$cmd\' for device $name";

  my $model = AttrVal($name,"model","generic");
  my $gen   = $shelly_models{$model}[4]; # 0 is Gen1,  1 is Gen2
  my $creds = Shelly_pwd($hash);
  my $timeout = AttrVal($name,"timeout",4);
  my $mode  = AttrVal($name,"mode","relay");  # we need mode=relay for Shelly*1-devices
  
  Log3 $name,5,"[Shelly_webhook] device $name was called with command=$cmd";
  
  # Calling as callable program: check if err and data are empty      
  if ( $hash && !$err && !$data ){
    Log3 $name,7,"[Shelly_webhook] device $name will be called by Webhook.";
 
    my $URL     = "http://$creds".$hash->{TCPIP};
    $URL .=($gen?"/rpc/Webhook.":"/settings/actions");   #Gen2 :  Gen1
 
    if( $cmd eq "Create" ){
       $URL .= "Create" if( $gen == 1 );
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
    my ($urls_pre,$urls_part1,$fhemcmd,$urls_post);
    my $event  = "";   
    my $compCount=0;     #  number of components in device
    my $eventsCount=0;   #  number of events 

    my ($component,$element);
    foreach $component ( $mode, "input", "emeter" ){
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
       }elsif( $component eq "white" && $model eq "shellybulb" ){
          $compCount   = 1;
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
          }elsif( $component eq "emeter"){
             $element = $component;  ## ?? 
          }elsif( $gen == 0){   # Gen 1
             $element = $model;  
          }else{
             $element = $component;
          }
          $eventsCount = $#{$shelly_events{$element}};   #  $#{...} gives highest index of array
             Log3 $name,5,"[Shelly_webhook] $name: processing evtsCnt=$eventsCount events for \'$element\'";
          
          for( my $e=0; $e<=$eventsCount; $e++ ){
             if( $cmd eq "Create" ){
                 $event = $shelly_events{$element}[$e];
                 $urls  = ($gen?"?cid=$c":"?index=$c");    # component id, 0,1,...
                 $urls .= "&name=%22_". uc($event) ."_%22" if( $gen == 1 );   # name of the weblink (Gen2 only)                    
                 $urls .= ($gen?"&event=%22$event%22":"&name=$event"); 
                 $urls .= ($gen?"&enable=true":"&enabled=true");
                 
                 ($urls_pre,$urls_part1,$fhemcmd,$urls_post) = Shelly_webhookurl($hash,$cmd,$element,$c,$e);  # creating the &urls= command
                 $urls .= $urls_pre; 
                 $urls .= $urls_part1;
                 $urls .= $fhemcmd; 
                 $urls .= $urls_post;

                 if( $component eq "emeter" ){
                                  # shall we have conditions?
                     $urls .= "&condition=%22ev.act_power%20%3c%20-200%22" if( 0 && $e==0 );   #  %3c  <
                     $urls .= "&condition=%22ev.act_power%20%3e%20-100%22" if( 0 && $e==1 );   #  %3e  >
                                  # only first emeter-action (activ power) is enabled
                     $URL =~ s/enable\=true/enable\=false/  if( $e > 0 ); 
                  }
             }
             Log3 $name,5,"[Shelly_webhook] $name $cmd component=$element  count=$c   event=$e";
             Log3 $name,5,"[Shelly_webhook] issue a non-blocking call to \n$URL$urls";  
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
  }elsif ( $hash && $err ){
    Shelly_error_handling($hash,"Shelly_webhook",$err);
    return;
  }
  ################################################# $hash && $data
  # Answer: processing the received webhook data
  Log3 $name,5,"[Shelly_webhook] device $name called by Webhook.$cmd has returned data $data";
    
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
    if ( defined $jhash->{'hooks'} ){
       $hooksCount =@{$jhash->{'hooks'}};
    }else{
       #return if ($hooksCount == 0);
       $hooksCount = 0;
    }
    Log3 $name,5,"[Shelly_webhook] our counter says $hooksCount webhooks on shelly";  
}
   
    # parsing all webhooks and check for csrf-token  
    my $current_url;   # the current url of webhook on the shelly
    my $current_id;
    my $current_name;
    my ($current_url_part1, $current_url_command);
    my $urls;   # the new urls string
    
    # are there webhooks on the shelly we don't know about?
    if( (!AttrVal($name,"webhook",undef) || AttrVal($name,"webhook",undef) eq "none" ) && $jhash->{'hooks'}[0]{'urls'}[0] ){
        $current_url = $jhash->{'hooks'}[0]{'urls'}[0]; # get the first webhook url from shelly
        $current_url =~ m/.*:([0-9]*)\/.*/;
        my $fhemwebport = $1; 
        Log3 $name,1,"[Shelly_webhook] We have found a webhook with port no $fhemwebport on $name, but the webhook attribute is none or not set";
        return;
    }

    
    my ($webhook_url_pre, $webhook_url_part1, $webhook_url_command,$webhook_url_post) = Shelly_webhookurl($hash,"",0,0,0);  # a 'status' call    
    Log3 $name,5,"[Shelly_webhook] $name: webhook shall be: pre=$webhook_url_pre,  part1=$webhook_url_part1, command=$webhook_url_command,  post=$webhook_url_post"; 
    
    # preparing the calling-url, we need this when looping        
    my $URL = "http://$creds".$hash->{TCPIP}."/rpc/Webhook.Update?";
    
    my $host_ip =  qx("\"hostname -I\"");   # local
    $host_ip =~ m/(\d\d?\d?\.\d\d?\d?\.\d\d?\d?\.\d\d?\d?).*/; #extract ipv4-address
    $host_ip = $1;
    Log3 $name,5,"[Shelly_webhook] looking for webhooks forwarding to $host_ip"; 
    
    for (my $i=0;$i<$hooksCount;$i++){
        $current_url = $jhash->{'hooks'}[$i]{'urls'}[0]; # get the url from shelly
        $current_url =~ s/\%/\%25/g;    # to make it compareable to webhook_url 
        Log3 $name,5,"[Shelly_webhook] shellies $name webhook $i is $current_url";   
        if($current_url !~ /$host_ip/ ){  #skip this hook when refering to another host
             Log3 $name,5,"[Shelly_webhook] shellies $name webhook $i is refering to another host $current_url -> skipping";
             next;
         }
        $current_name = $jhash->{'hooks'}[$i]{'name'}; 
        if( $current_name !~ /^_/ ){   # name of webhook does not start with '_'  -> skipp
             Log3 $name,5,"[Shelly_webhook] shellies $name name of webhook $i $current_name does not start with _ -> skipping";
             next;
        }
        $current_id  = $jhash->{'hooks'}[$i]{'id'}; 
        Log3 $name,5,"[Shelly_webhook] $i id=$current_id: checking this url: $current_url";
        $current_url =~ m/http:\/\/(\d\d?\d?\.\d\d?\d?\.\d\d?\d?\.\d\d?\d?):([0-9]*).([a-z]*).XHR=1(.*?)(&cmd.*)/;
        $current_url_part1 = "http://$1:$2/$3?XHR=1$4";
        $current_url_command=$5;     # the &cmd...
        $current_url_part1 =~ s/\&/\%26/g;   # because there is a '&' in the token string
        $current_url_command =~ s/\&/\%26/g;
        
        Log3 $name,5,"[Shelly_webhook] $i checking part1 of url: \n$current_url_part1    against\n$webhook_url_part1\n   command is: \"$current_url_command\" ";
        
        if ($current_url_part1 ne $webhook_url_part1 ){
            Log3 $name,5,"[Shelly_webhook] $i we have to update $current_url_part1 to $webhook_url_part1";
            $urls = "urls=[%22$webhook_url_part1$current_url_command%22]&";  # %22 = "
            $urls = $URL.$urls."id=$current_id";  # will be issued
            Log3 $name,5,"[Shelly_webhook] $name: $i issue a non-blocking call with callback-command \"Updated\":\n$urls";  
            HttpUtils_NonblockingGet({
              url      => $urls,
              timeout  => $timeout,
              callback => sub($$$){ Shelly_webhook($hash,"Updated",$_[1],$_[2]) }
            });
        }else{
        Log3 $name,5,"[Shelly_webhook] $i check is OK, nothing to do";
        }
    }  
    
  #---------------------Delete all webhooks (get number of webhooks from received data)
  }elsif($cmd eq "Delete" ){
    return if (!defined $hooksCount);  # nothing to do if there are no hooks
    my $h_name;
    my $h_id;
    my $h_urls0;
    for (my $i=0;$i<$hooksCount;$i++){
        $h_name = $jhash->{'hooks'}[$i]{'name'}; 
        $h_id = $jhash->{'hooks'}[$i]{'id'};
        $h_urls0 = $jhash->{'hooks'}[$i]{'urls'}[0]; # we need this, when checking for forward ip-adress
        
        Log3 $name,5,"[Shelly_webhook] ++++ $name: checking webhook id=$h_id $h_name for deleting+++++++++++";  
        if( $h_name =~ /^_/ ){
            Log3 $name,5,"[Shelly_webhook] ++++ $name: deleting webhook $h_name +++++++++++"; 
            my $url_ = "http://$creds".$hash->{TCPIP}."/rpc/Webhook.Delete?id=$h_id"; 
            Log3 $name,5,"[Shelly_webhook] url: $url_";
            HttpUtils_NonblockingGet({
              url      => $url_,
              timeout  => $timeout,
              callback => sub($$$){ Shelly_webhook($hash,"Killed",$_[1],$_[2]) }
            });
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
########################################################################################
  
sub Shelly_webhookurl ($@) {
  my ($hash, @a) = @_ ;    
  my $name = $hash->{NAME};
  my $cmd  = shift @a;    # Create, Delete, ...
  my $entity  = shift @a; # shelly component
  my $channel = shift @a;
  my $noe     = shift @a; # number of event of entity
  
  my $V = 5;
  Log3 $name,$V,"[Shelly_webhookurl] calling url-builder with args: $name $cmd $entity ch:$channel noe:$noe";
  							
  my $host_ip =  qx("\"hostname -I\"");   # local
  $host_ip =~ m/(\d\d?\d?\.\d\d?\d?\.\d\d?\d?\.\d\d?\d?).*/; #extract ipv4-address
  $host_ip = $1;
  Log3 $name,$V,"[Shelly_webhookurl] the host-ip of $name is: $host_ip";
  my $host_url  = "http://$host_ip:";

  
  my $fhemweb = AttrVal($name,"webhook","none"); 
  if($fhemweb eq "none"){  
     Log3 $name,$V,"[Shelly_webhookurl] FHEMweb-device for $name is $fhemweb (none or undefined)";
     ## return($host_ip,InternalVal($name,"PORT",undef),"none","none");
     return($host_ip,"8084","none","none");
  }
  Log3 $name,$V,"[Shelly_webhookurl] FHEMweb-device is: $fhemweb";

  
  my $port    = InternalVal($fhemweb,"PORT",undef);
  if (!$port ){
     Log3 $name,$V,"[Shelly_webhookurl] FHEMweb device without port-number";
     return($host_ip,"9000","none","url");
  }
  Log3 $name,$V,"[Shelly_webhookurl] FHEMweb port is: $port";

  
  my $webname = AttrVal($fhemweb,"webname","fhem");
   
  Log3 $name,$V,"[Shelly_webhookurl] FHEMweb-device \"$fhemweb\" has port \"$port\" and webname \"$webname\"";
      
  # check, if CSRF is defined in according FHEMWEB
  my $token   = InternalVal($fhemweb,"CSRFTOKEN",undef);
  if (defined $token){
     $token = "&fwcsrf=".$token;
  }else{
     $token = "";
  }
  Log3 $name,$V,"[Shelly_webhookurl] the token-string is: $token";

   
  # building the url
  $host_url .= "$port\/$webname?XHR=1$token";
  $host_url =~ s/\&/\%26/g;    # substitute & by %26
  
  my ($gen,$urls_pre,$urls_part1,$urls_post);
  my $model = AttrVal($name,"model","generic");
  $gen = $shelly_models{$model}[4]; # 0 is Gen1,  1 is Gen2
  $urls_pre = ($gen?"&urls=[%22":"&urls[]="); # Gen2 : Gen1
  $urls_part1=$host_url;
  $urls_post= ($gen?"%22]":"");
  
  #-- building the command for fhem  
  
  $entity = "status" if (!$entity );
  
  my $fhemcmd;
  if ( $entity eq "status" || length($shelly_events{$entity}[$noe])==0 ){
      $fhemcmd = "get $name status";
  }else{
      $entity  = $shelly_events{$entity}[$noe];
      $entity  = $fhem_events{$entity};
      $fhemcmd = "set $name $entity";
      if( $entity eq "Active_Power" ){        
          $fhemcmd .= "_%24%7bev.phase%7d %24%7bev.act_power%7d" ;
      }elsif( $entity eq "Current" ){      
          $fhemcmd .= "_%24%7bev.phase%7d %24%7bev.current%7d" ;
      }elsif( $entity eq "Voltage" ){      
          $fhemcmd .= "_%24%7bev.phase%7d %24%7bev.voltage%7d" ;
      }else{
          $fhemcmd .= " $channel";
      } 
  }  
  Log3 $name,$V,"[Shelly_webhookurl] $name: the fhem command is: \"$fhemcmd\"";
  $fhemcmd =~ s/\s/\%2520/g;    # substitute '&' by '%2520', that will result in '%20'
  $fhemcmd = "%26cmd=".$fhemcmd;  # %26  -->  '&'
  Log3 $name,$V,"[Shelly_webhookurl] $name: $urls_pre$fhemcmd$urls_post";
  ##########
  return ($urls_pre,$urls_part1,$fhemcmd,$urls_post);
}


########################################################################################
# 
# Shelly_error_handling - handling error from callback functions
# 
# Parameter hash, function, error 
#
########################################################################################


sub Shelly_error_handling {
  my ($hash, $func, $err) = @_;
  my $name  = $hash->{NAME};
    readingsBeginUpdate($hash);
    Log3 $name,1,"[$func] device $name has error \"$err\" ";
    if( $err =~ /timed out/ ){
        if( $err =~ /read/ ){
            $err = "Error: Timeout reading";
        }elsif( $err =~ /connect/ ){
            $err = "Error: Timeout connecting"; 
        }else{
            $err = "Error: Timeout";
        }
        readingsBulkUpdateIfChanged($hash,"network",$err,1);
        $err = "Error: Network"; 
    }elsif( $err eq "not connected" ){   # from Shelly_proc2G:status 
        readingsBulkUpdateIfChanged($hash,"network","not connected",1);
        $err = "Error: Network"; #disconnected
    }elsif( $err =~ /113/ ){   # keine Route zum Zielrechner (113) 
        readingsBulkUpdateIfChanged($hash,"network","not connected (no route)",1);
        $err = "Error: Network"; #disconnected
    }elsif( $err =~ /JSON/ ){ 
        readingsBulkUpdateIfChanged($hash,"network",$err,1);
        $err = "Error: JSON"; 
    }else{
        $err = "Error"; 
    }
    Log3 $name,1,"[Shelly_error_handling] Device $name has Error \'$err\' ";
    readingsBulkUpdate($hash,"network_disconnects",ReadingsNum($name,"network_disconnects",0)+1)   if( ReadingsVal($name,"state","") ne $err );
    readingsBulkUpdateMonitored($hash,"state",$err, 1 );
    readingsEndUpdate($hash,1);
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
  my $MaxAge=AttrVal($hash->{NAME},"maxAge",21600);  # default 6h
  if( ReadingsAge($hash->{NAME},$reading,$MaxAge)>=$MaxAge || $value ne ReadingsVal($hash->{NAME},$reading,"") ){  
       Log3 $hash->{NAME},6,"$reading: maxAge=$MaxAge ReadingsAge=".ReadingsAge($hash->{NAME},$reading,0)." value=$value ? ".ReadingsVal($hash->{NAME},$reading,"");
       return readingsBulkUpdate($hash,$reading,$value,$changed);
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
      my $MaxAge=AttrVal($hash->{NAME},"maxAge",21600);  # default 6h
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
           <li> <i>Button switched ON url</i>: http://&lt;FHEM IP address&gt;:&lt;Port&gt;/fhem?XHR=1&cmd=get%20&lt;Devicename&gt;%20status</li>
           </ul>
         If one wants to detach the button from the output, one may generate an additional reading <i>button</i> by setting in the Shelly
           <ul>
           <li> For <i>Button switched ON url</i>:
                    http://&lt;FHEM IP address&gt;:&lt;Port&gt;/fhem?XHR=1&cmd=set%20&lt;Devicename&gt;%20<b>button_on</b>%20[&lt;channel&gt;]</li>
           <li> For <i>Button switched OFF url</i>:
                    http://&lt;FHEM IP address&gt;:&lt;Port&gt;/fhem?XHR=1&cmd=set%20&lt;Devicename&gt;%20<b>button_off</b>%20[&lt;channel&gt;]</li>
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
            <br>This is the only way to set the password for the Shelly web interface
            </li>
        <li>
            <a id="Shelly-set-reboot"></a>
            <code>set &lt;name&gt; reboot</code>
            <br>Reboot the Shelly 
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
                <code>set &lt;name&gt; pct &lt;integer percent value&gt; </code>
                <br />drives the roller blind to a partially closed position (normally 100=open, 0=closed, see attribute pct100). If the integer percent value
                carries a sign + or - the following number will be added to the current value of the position to acquire the target value. </li>    
            
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
            <li>
                <a id="Shelly-attr-model"></a>
                <code>attr &lt;name&gt; model generic|shelly1|shelly1pm|shelly2|shelly2.5|
                       shellyplug|shelly4|shellypro4|shellydimmer|shellyrgbw|shellyem|shelly3em|shellybulb|shellyuni </code>
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
                <br/>Maximum age of readings in seconds. The default is 21600 seconds = 6 hours, minimum value is 'interval'.
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
        Notes: <ul>
        <li>Dieses Modul benötigt die Pakete JSON und HttpUtils</li>
         
        <li>Das Attribut <code>model</code> wird automatisch gesetzt. 
           Für Shelly Geräte, welche nicht von diesem Modul unterstützt werden, wird das Attribut zu <i>generic</i> gesetzt.
           Das Device enthält dann keine Aktoren, es ist nur ein Platzhalter für die Bereitstellung von Readings</li>
         
        <li>Bei bestimmten Shelly Modellen können URLs (Webhooks) festgelegt werden, welche bei Eintreten bestimmter Ereignisse ausgelöst werden. 
           Beispielsweise lauten die Webhooks für die Information über die Betätigung lokaler Eingänge wie folgt:
           <ul>
              <li> <i>Button switched ON url</i>:
                    http://&lt;FHEM IP address&gt;:&lt;Port&gt;/fhem?XHR=1&cmd=set%20&lt;Devicename&gt;%20<b>button_on</b>%20[&lt;channel&gt;]</li>
              <li> <i>Button switched OFF url</i>:
                    http://&lt;FHEM IP address&gt;:&lt;Port&gt;/fhem?XHR=1&cmd=set%20&lt;Devicename&gt;%20<b>button_off</b>%20[&lt;channel&gt;]</li>
           </ul>
         Ein Webhook für die Aktualisierung aller Readings lautet beispielsweise:
         <ul>
           <li> http://&lt;FHEM IP address&gt;:&lt;Port&gt;/fhem?XHR=1&cmd=<b>get</b>%20&lt;Devicename&gt;%20<b>status</b></li>
           </ul>
         Hinweise: 
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
                <br />Name des Shelly Gerätes. Wenn der Shelly noch keinen Namen erhalten hat wird der Shelly nach dem FHEM-Device benannt.
                Der Shellyname darf Leerzeichen enthalten.
                </li>
                Hinweis: Leere Zeichenkentten werden nicht akzeptiert. 
                Nach dem Löschen eines Shelly Namens (auf Shellies-Website) wird der Shelly Name auf den Namen des FHEM Devices gesetzt.
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
        <li>
            <a id="Shelly-set-reboot"></a>
            <code>set &lt;name&gt; reboot</code>
            <br>Neustarten des Shelly 
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
        <br/>Für Shelly Rollladentreiber (model=shelly2/2.5/plus2/pro2 und mode=roller)  
        <ul>
            <li><a id="Shelly-set-open"></a><a id="Shelly-set-closed"></a>
                <code>set &lt;name&gt; open|closed|stop [&lt;duration&gt;]</code>
                <br />Fährt den Rollladen zu den Positionen open (offen), closed (geschlossen) oder beendet die Fahrbewegung (stop). 
                      Bei den Befehle open (öffnen) und closed (schließen) kann ein optionaler Parameter für die Fahrzeit in Sekunden mit übergeben werden
                      </li>      
            <li>
                <code>set &lt;name&gt; pct &lt;integer percent value&gt; </code>
                <br />Fährt den Rollladen zu einer Zwischenstellung (normalerweise gilt 100=offen, 0=geschlossen, siehe Attribut 'pct100'). 
                Wenn dem Wert für die Zwischenstellung ein Plus (+) oder Minus (-) - Zeichen vorangestellt wird, 
                wird der Wert auf den aktuellen Positionswert hinzugezählt.
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
                <br />schaltet Kanal &lt;channel&gt; on oder off. Kanalnummern sind 0..3 für model=shellyrgbw. 
                    Wird keine Kanalnummer angegeben, wird der mit dem Attribut 'defchannel' definierte Kanal geschaltet.</li>
            <li>
                <code>set &lt;name&gt; on-for-timer|off-for-timer &lt;time&gt; [&lt;channel&gt;] </code>
                <br />schaltet Kanal &lt;channel&gt; on oder off für &lt;time&gt; Sekunden. Kanalnummern sind 0..3 for model=shellyrgbw.
                      Wird keine Kanalnummer angegeben, wird der mit dem Attribut 'defchannel' definierte Kanal geschaltet.</li>  
            <li>
                <code>set &lt;name&gt; pct &lt;0..100&gt; [&lt;channel&gt;] </code>
                <br />Prozentualer Wert für die Helligkeit (brightness). Kanalnummern sind 0..3 für model=shellyrgbw.
                      Wird keine Kanalnummer angegeben, wird der mit dem Attribut 'defchannel' definierte Kanal geschaltet.</li> 
        </ul>
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
                <br />Benutername für den Zugang zur Website des Shelly.
                Das Passwort wird mit dem 'set ... password'-Befehl gesetzt.</li>
            <li>
                <a id="Shelly-attr-model"></a>
                <code>attr &lt;name&gt; model generic|shelly1|shelly1pm|shelly2|shelly2.5|
                       shellyplug|shelly4|shellypro4|shellydimmer|shellyrgbw|shellyem|shelly3em|shellybulb|shellyuni </code>
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
                <br/>Mit diesem Attribut kann bei einigen Readings eine Aktualisierung erzwungen werden. 
                Der Standardwert ist 21600 Sekunden = 6 Stunden, Minimalwert ist das Pollingintervall.
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
                <br/>Festlegen der 100%-Endlage für Rollladen offen (pct100=open) oder Rolladen geschlossen (pct100=closed)</li>
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
