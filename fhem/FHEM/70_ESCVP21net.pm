################################################################################
# $Id$
#
# ESCVP21net 
#
# control ESC/VP21 capable devices by VP.net via LAN, e.g Epson projektors
#
# version history
#    0.1      first released versin for goo-willing testers
#    0.3      bug fixes, improved handling of disconnect status
#    1.01.01  reschedule get call if blockingFn still running
#             (don't loose command if timeout)
#             adding TW6100
#             handle model specific result values
#    1.01.01  code cleanup
#    1.01.02  supporting multiple devices (store set and result in device hash)
#             adding debug attr
#    1.01.03  rename to 70_ESCVP21net, clean up and prepare for fhem trunk
#    1.01.04  small bug fix, DevIo log messages moved to loglevel 5
#    1.01.05  socket log messages moved to loglevel 5
#             prevent DevIO from overwriting STATE ($hash->{devioNoSTATE} = 1)
#             set port 3629 as default
#    1.01.06  added toggle, added TW7400, extended Scotty capabililties
#    1.01.07  multiple checkStatusCmds, added GetStatus to set list
#             set PWR to statusOfflineMsg if init fails
#             force PWR check after CONNECTED from Dev_Io, some clean-up
#    1.01.08  small fix to handle GetAll as statusChckCmd
#             editorial corrections in pod text
#    1.01.09  fixes, optimized logging in loglevel 5
#             fixed sporadic not-deleting of RUNNING_PID
#    1.01.10  fix sporadic offline message
#    1.01.11  fix receiving unexpected IMEVENT messages, fixed typos in help
#    1.01.12  improved state check
#    1.01.13  improved cleanup, fixed empty val in AdditionalSettings
#    1.01.14  fixed problem with DevIo "No route" sending fhem to 100% CPU
#    1.01.15  add debug options
#    1.01.16  add cyclicConnect to mitigate lost TCP connection issue
#    1.01.17  add TW9400
#    1.01.18  added undocumented settings (IMGPROC, IRIS, LIRIS)
#    1.01.19  added LS12000 (especially POPLP) 
#
################################################################################
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

use Socket;
use Encode qw(encode);

use Blocking;
use Time::HiRes qw(gettimeofday);
use POSIX;

#use JSON::XS qw (encode_json decode_json);

my $version = "1.01.19";
my $missingModul = "";

eval "use JSON::XS qw (encode_json decode_json);1" or $missingModul .= "JSON::XS ";

# key(s) in defaultsets and defaultresults will be overwritten,
# if <type>sets/<type>result defines the same key(s)
my %ESCVP21net_debugsets = (
  "reRead"          => ":noArg",
  "encode"          => ":noArg",
  "decode"          => ":noArg",
  "PWSTATUS"        => ":get",
  "cleanup"         => ":noArg",
  "connect"         => ":noArg",
  "removeTimer"     => ":noArg",
  "closeDevice"     => ":noArg",
  "deleteNextOpen"  => ":noArg",
  "openDevice"      => ":noArg",
  "isOpen"          => ":noArg"
);

my %ESCVP21net_defaultsets = (  
  "GetAll"    => ":noArg",
  "GetStatus" => ":noArg",
  "ASPECT"    => ":get,HDMI,PC",
  "KEY"       => ":get,HDMI1,PC",
  "LAMP"      => ":get",
  "MUTE"      => ":get,on,off,toggle",
  "PWR"       => ":get,on,off,toggle"
);

my %ESCVP21net_Miscsets = (
  "KEY"     => ":03,05,3C,3D"
);

# TW5650 sets
my %ESCVP21net_TW5650sets = (
  "ASPECT"       => ":get,Auto,Auto20,Normal,Full,Zoom",
  "AUTOHOME"     => ":get,off,on",
  "AUTOKEYSTONE" => ":get,on,off",
  "BTAUDIO"      => ":get,on,off,toggle",
  "CMODE"        => ":get,Dynamic,Natural,Living,Cinema,3D_Cinema,3D_Dynamic",
  "HREVERSE"     => ":get,Flip,Normal",
  "ILLUM"        => ":get,on,off,toggle",
  "IMGPROC"      => ":get,fine,fast",
  "IRIS"         => ":get,00,01,02",
  "LUMINANCE"    => ":get,high,low,toggle",
  "MCFI"         => ":get,off,low,normal,high",
  "MSEL"         => ":get,black,blue,user",
  "OVSCAN"       => ":get,off,4%,8%,auto",
  "SIGNAL"       => ":get,none,2D,3D",
  "SNO"          => ":get",
  "SOURCE"       => ":get,HDMI1,HDMI2,ScreenMirror,Input1,USB,LAN",
  "VOLset"       => ":slider,0,1,20",
  "VOL"          => ":get",
  "VREVERSE"     => ":get,Flip,Normal"
);

my %ESCVP21net_TW5650result = (
  "CMODE:06"     => "Dynamic",
  "CMODE:07"     => "Natural",
  "CMODE:0C"     => "Living",
  "CMODE:15"     => "Cinema",
  "CMODE:17"     => "3D_Cinema",
  "CMODE:18"     => "3D_Dynamic",
  "LUMINANCE:00" => "high",
  "LUMINANCE:01" => "low"
);

# EB2250 sets
my %ESCVP21net_EB2250Usets = (
  "SOURCE"	=> ":get,HDMI1,HDMI2,PC1,PC2,ScreenMirror,USB,LAN"
);

my %ESCVP21net_EB2250result;

# TW6100 sets
my %ESCVP21net_TW6100sets = (
  "ASPECT"  => ":get,Normal,Auto,Full,Zoom,Wide",
  "SOURCE"	=> ":get,Input1,Input2,HDMI1,HDMI2,Video,Video(RCA),WirelessHD",
  "OVSCAN"  => ":get,off,4%,8%,auto"
);

# TW6100 has slightly different input identifiers. PWR is standard, just added for test
# (PWR:04 not avaialable for TW6100, should never return)
my %ESCVP21net_TW6100result = (
  "PWR:00"     => "Standby (Net off)", 
  "PWR:01"     => "Lamp on", 
  "PWR:02"     => "Warmup", 
  "PWR:03"     => "Cooldown", 
  "PWR:04"     => "not available",
  "PWR:05"     => "abnormal Standby",
  "PWR:07"     => "WirelessHD Standby",  
  "SOURCE:10"  => "Input1(Component)",
  "SOURCE:20"  => "Input2(Dsub)",
  "SOURCE:30"  => "HDMI1",
  "SOURCE:40"  => "Video",
  "SOURCE:41"  => "Video(RCA)",
  "SOURCE:A0"  => "HDMI2",
  "SOURCE:D0"  => "WirelessHD",
  "SOURCE:F0"  => "ChangeCyclic"
);

# TW7400 sets
my %ESCVP21net_TW7400sets = (
  "4KENHANCE" => ":get,off,FullHD",
  "AUTOHOME"     => ":get,off,on",
  "ASPECT"    => ":get,Normal,Auto,Full,Zoom",
  "CMODE"     => ":get,Dynamic,Natural,BrightCinema,Cinema,3D_Cinema,3D_Dynamic,DigitalCinema",
  "HREVERSE"  => ":get,Flip,Normal",
  "ILLUM"     => ":get,on,off,toggle",
  "LUMINANCE" => ":get,normal,eco,medium",
  "MCFI"      => ":get,off,low,normal,high",
  "MSEL"      => ":get,black,blue,user",
  "PRODUCT"   => ":get,ModelName_on,ModelName_off",
  "SIGNAL"    => ":get,none,2D,3D",
  "SNO"       => ":get",
  "SOURCE"  	=> ":get,Dsub,HDMI1,HDMI2,LAN,ChangeCyclic",
  "VREVERSE"  => ":get,Flip,Normal",
  "WLPWR"     => ":get,WLAN_on,WLAN_off"
);

my %ESCVP21net_TW7400result = (
  "CMODE:06"   => "Dynamic",
  "CMODE:07"   => "Natural",
  "CMODE:0C"   => "BrightCinema",
  "CMODE:15"   => "Cinema",
  "CMODE:17"   => "3D_Cinema",
  "CMODE:18"   => "3D_Dynamic",
  "CMODE:22"   => "DigitalCinema",
  "LUMINANCE:00" => "normal",
  "LUMINANCE:01" => "eco",
  "LUMINANCE:02" => "medium",
  "SOURCE:20"  => "Dsub",
  "SOURCE:30"  => "HDMI1",
  "SOURCE:53"  => "LAN",
  "SOURCE:A0"  => "HDMI2",
  "SOURCE:D0"  => "WirelessHD",
  "SOURCE:F0"  => "ChangeCyclic"
);

# TW9400 sets
my %ESCVP21net_TW9400sets = (
  "4KENHANCE"    => ":get,off,FullHD",
  "ASPECT"       => ":get,Auto,Normal,Full,Zoom",
  "AUTOHOME"     => ":get,off,on",
  "CMODE"        => ":get,Dynamic,Natural,BrightCinema,Cinema,3D_Cinema,3D_Dynamic,BW_Cinema,DigialCinema",
  "DYNRANGE"     => ":get,Auto,SDR,HDR10,HLG",
  "HREVERSE"     => ":get,Flip,Normal",
  "ILLUM"        => ":get,on,off,toggle",
  "IMGPRESET"    => ":get,Setting1,Setting2,Setting3,Setting4,Setting5",
  "IMGPROC"      => ":get,fine,fast",
  "IRIS"         => ":get,00,01,02",
  "LIRIS"        => ":get,0,128,255",   
  "LUMINANCE"    => ":get,normal,eco,medium",
  "MCFI"         => ":get,off,low,normal,high",
  "MSEL"         => ":get,black,blus,user",
  "OVSCAN"       => ":get,off,4%,8%,auto",
  "PRODUCT"      => ":get,ModelName_on,ModelName_off",
  "SIGNAL"       => ":get,none,2D,3D",
  "SNO"          => ":get",
  "SOURCE"       => ":get,HDMI1,HDMI2,Input1,Input2,ScreenMirror,PC1,PC2,USB,LAN,Video,Video(RCA),WirelessHD",
  "VREVERSE"     => ":get,Flip,Normal",
  "WLPWR"        => ":get,WLAN_on,WLAN_off"
);

my %ESCVP21net_TW9400result = (
  "CMODE:06"     => "Dynamic",
  "CMODE:07"     => "Natural",
  "CMODE:0C"     => "BrightCinema",
  "CMODE:15"     => "Cinema",
  "CMODE:17"     => "3D_Cinema",
  "CMODE:18"     => "3D_Dynamic",
  "CMODE:20"     => "BW_Cinema",
  "CMODE:22"     => "DigitalCinema",
  "LUMINANCE:00" => "normal",
  "LUMINANCE:01" => "eco",
  "LUMINANCE:02" => "medium"
);

# LS12000 sets
my %ESCVP21net_LS12000sets = (
  "4KENHANCE"    => ":get,off,FullHD",
  "ASPECT"       => ":get,Auto,Normal,Full,Zoom",
  "AUTOHOME"     => ":get,off,on",
  "CMODE"        => ":get,Dynamic,Natural,BrightCinema,Cinema,3D_Cinema,3D_Dynamic,BW_Cinema,DigialCinema",
  "DYNRANGE"     => ":get,Auto,SDR,HDR10,HLG",
  "HLENS"        => ":get",
  "HREVERSE"     => ":get,Flip,Normal",
  "ILLUM"        => ":get,on,off,toggle",
  "IMGPRESET"    => ":get,Setting1,Setting2,Setting3,Setting4,Setting5",
  "IMGPROC"      => ":get,fine,fast",
  "IRIS"         => ":get,00,01,02",
  "LENS"         => ":get",
  "LIRIS"        => ":get,0,128,255",   
  "LUMINANCE"    => ":get,normal,eco,medium",
  "MCFI"         => ":get,off,low,normal,high",
  "MSEL"         => ":get,black,blus,user",
  "OVSCAN"       => ":get,off,4%,8%,auto",
  "POPLP"        => ":01,01,03,04,05,06,07,08,09,0A",
  "PRODUCT"      => ":get,ModelName_on,ModelName_off",
  "SIGNAL"       => ":get,none,2D,3D",
  "SNO"          => ":get",
  "SOURCE"       => ":get,HDMI1,HDMI2,Input1,Input2,ScreenMirror,PC1,PC2,USB,LAN,Video,Video(RCA),WirelessHD",
  "VREVERSE"     => ":get,Flip,Normal",
  "WLPWR"        => ":get,WLAN_on,WLAN_off"
);

my %ESCVP21net_LS12000result = (
  "CMODE:06"     => "Dynamic",
  "CMODE:07"     => "Natural",
  "CMODE:0C"     => "BrightCinema",
  "CMODE:15"     => "Cinema",
  "CMODE:17"     => "3D_Cinema",
  "CMODE:18"     => "3D_Dynamic",
  "CMODE:20"     => "BW_Cinema",
  "CMODE:22"     => "DigitalCinema",
  "LUMINANCE:00" => "normal",
  "LUMINANCE:01" => "eco",
  "LUMINANCE:02" => "medium"
);

# scotty sets - sort of godmode, gives you enhanced set possibilities
my %ESCVP21net_Scottysets = (
  "4KENHANCE"    => ":get,off,FullHD",
  "ASPECT"       => ":get,Auto,Auto20,Normal,Full,Zoom,Wide",
  "AUTOHOME"     => ":get,off,on",
  "AUTOKEYSTONE" => ":get,on,off",
  "AUDIO"        => ":get,Audio1,Audio2,USB",
  "AVOUT"        => ":get,projection,constantly",
  "BTAUDIO"      => ":get,on,off,toggle",
  "CMODE"        => ":get,sRGB,Normal,Meeting,Presentation,Theatre,Game/LivingRoom,Natural,Dynamic/Sports,09,Custom,Living,BlackBoard,WhiteBoard,14,Photo,Cinema,3D_Cinema,3D_Dynamic,BW_Cinema,DigitalCinema",
  "DYNRANGE"     => ":get,Auto,SDR,HDR10,HLG",
  "FREEZE"       => ":get,on,off,toggle",
  "HLENS"        => ":get",
  "HREVERSE"     => ":get,Flip,Normal",
  "ILLUM"        => ":get,on,off,toggle",
  "IMGPRESET"    => ":get,Setting1,Setting2,Setting3,Setting4,Setting5",
  "IMGPROC"      => ":get,fine,fast",
  "IRIS"         => ":get,00,01,02",
  "LENS"         => ":get",
  "LIRIS"        => ":get,0,128,255",        
  "LUMINANCE"    => ":get,high,low,toggle",
  "MCFI"         => ":get,off,low,normal,high",
  "MSEL"         => ":get,black,blus,user",
  "OVSCAN"       => ":get,off,4%,8%,auto",
  "POPLP"        => ":01,01,03,04,05,06,07,08,09,0A",
  "PRODUCT"      => ":get,ModelName_on,ModelName_off",
  "PWSTATUS"     => ":get",
  "SIGNAL"       => ":get,none,2D,3D",
  "SNO"          => ":get",
  "SOURCE"       => ":get,HDMI1,HDMI2,Input1,Input2,ScreenMirror,PC1,PC2,USB,LAN,Video,Video(RCA),WirelessHD",
  "VOL"          => ":get",
  "VOLset"       => ":slider,-1,1,20",
  "VREVERSE"     => ":get,Flip,Normal",
  "WLPWR"        => ":get,WLAN_on,WLAN_off"
);

my %ESCVP21net_Scottyresult = (
  "CMODE:01"     => "sRGB",
  "CMODE:02"     => "Normal",
  "CMODE:03"     => "Meeting",
  "CMODE:04"     => "Presentation",
  "CMODE:05"     => "Theatre",
  "CMODE:06"     => "Game/LivingRoom",
  "CMODE:07"     => "Natural",
  "CMODE:08"     => "Dynamic/Sports",
  "CMODE:09"     => "09",
  "CMODE:10"     => "Custom",
  "CMODE:0C"     => "Living",
  "CMODE:11"     => "BlackBoard",
  "CMODE:12"     => "WhiteBoard",
  "CMODE:13"     => "13",
  "CMODE:14"     => "Photo",
  "CMODE:15"     => "Cinema",
  "CMODE:17"     => "3D_Cinema",
  "CMODE:18"     => "3D_Dynamic",
  "CMODE:20"     => "BW_Cinema",  
  "CMODE:22"     => "DigitalCinema",  
  "LUMINANCE:00" => "normal",
  "LUMINANCE:01" => "eco",
  "LUMINANCE:02" => "medium"
);

# data for sets - needed to tranlate the "nice" commands to raw values
my %ESCVP21net_data = (
  "4KENHANCE:off"         => "00",
  "4KENHANCE:FullHD"      => "01",
  "ASPECT:Normal"         => "00",
  "ASPECT:Auto20"         => "20",
  "ASPECT:Auto"           => "30",
  "ASPECT:Full"           => "40",
  "ASPECT:Zoom"           => "50",
  "AUDIO:Audio1"          => "01",
  "AUDIO:Audio2"          => "02",
  "AUDIO:USB"             => "03",
  "AUTOKEYSTONE:on"       => "ON",
  "AUTOKEYSTONE:off"      => "OFF",
  "AUTOHOME:off"          => "00",
  "AUTOHOME:on"           => "01",
  "AVOUT:projection"      => "00",
  "AVOUT:constantly"      => "01",
  "BTAUDIO:on"            => "01",
  "BTAUDIO:off"           => "00",
  "CMODE:sRGB"            => "01",
  "CMODE:Normal"          => "02",
  "CMODE:Meeting"         => "03",
  "CMODE:Presentation"    => "04",
  "CMODE:Theatre"         => "05",
  "CMODE:Game/LivingRoom" => "06",
  "CMODE:Dynamic"         => "06",
  "CMODE:Natural"         => "07",
  "CMODE:Dynamic/Sports"  => "08",
  "CMODE:09"              => "09",
  "CMODE:Custom"          => "10",
  "CMODE:Living"          => "0C",
  "CMODE:BrightCinema"    => "0C",
  "CMODE:BlackBoard"      => "11",
  "CMODE:WhiteBoard"      => "12",
  "CMODE:13"              => "13",
  "CMODE:Photo"           => "14",
  "CMODE:Cinema"          => "15",
  "CMODE:3D_Cinema"       => "17",
  "CMODE:3D_Dynamic"      => "18",
  "CMODE:DigitalCinema"   => "22",
  "DYNRANGE:Auto"         => "00",
  "DYNRANGE:SDR"          => "01",
  "DYNRANGE:HDR10"        => "20",
  "DYNRANGE:HLG"          => "30",              
  "FREEZE:on"             => "ON",
  "FREEZE:off"            => "OFF",
  "HREVERSE:Flip"         => "ON",
  "HREVERSE:Normal"       => "OFF",
  "ILLUM:on"              => "01",
  "ILLUM:off"             => "00",
  "IMGPRESET:Setting1"    => "01",
  "IMGPRESET:Setting2"    => "02",
  "IMGPRESET:Setting3"    => "03",
  "IMGPRESET:Setting4"    => "04",
  "IMGPRESET:Setting5"    => "05",
  "IMGPROC:fine"          => "01",
  "IMGPROC:fast"          => "02",
  "LUMINANCE:high"        => "00",
  "LUMINANCE:low"         => "01",
  "LUMINANCE:normal"      => "00",
  "LUMINANCE:eco"         => "01",
  "LUMINANCE:medium"      => "02",
  "MCFI:off"              => "00",
  "MCFI:low"              => "01",
  "MCFI:normal"           => "02",
  "MCFI:high"             => "03",
  "MSEL:black"            => "00",
  "MSEL:blue"             => "01",
  "MSEL:user"             => "02",
  "MUTE:on"               => "ON",
  "MUTE:off"              => "OFF",
  "OVSCAN:off"            => "00",
  "OVSCAN:4%"             => "02",
  "OVSCAN:8%"             => "04",
  "OVSCAN:auto"           => "A0",
  "PRODUCT:ModelName_off" => "00",
  "PRODUCT:ModelName_on"  => "01",
  "PWR:on"                => "ON",
  "PWR:off"               => "OFF",
  "SIGNAL:none"           => "00",
  "SIGNAL:2D"             => "01",
  "SIGNAL:3D"             => "02",
  "SIGNAL:not_supported"  => "03",
  "SOURCE:HDMI1"          => "30",
  "SOURCE:HDMI2"          => "A0",
  "SOURCE:ScreenMirror"   => "56",
  "SOURCE:PC"             => "10",
  "SOURCE:Input1"         => "10",  
  "SOURCE:Input2"         => "20",  
  "SOURCE:Video"          => "40",  
  "SOURCE:Video(RCA)"     => "41",  
  "SOURCE:PC1"            => "1F",
  "SOURCE:PC2"            => "2F",
  "SOURCE:USB"            => "52",
  "SOURCE:LAN"            => "53",
  "SOURCE:Dsub"           => "20",
  "SOURCE:WirelessHD"     => "D0",  
  "VREVERSE:Flip"         => "ON",
  "VREVERSE:Normal"       => "OFF",
  "WLPWR:WLAN_off"        => "00",
  "WLPWR:WLAN_on"         => "01"
);

# hash for results from device, to transtale to nice readings
# e.g answer "POW 04" will be shown als "Standby (Net on)" in GUI
# will be enhanced at runtime with %<type>result
my %ESCVP21net_defaultresults = (
  "4KENHANCE:00"     => "off",
  "4KENHANCE:01"     => "FullHD",
  "ASPECT:00"        => "Normal",
  "ASPECT:20"        => "Auto20",
  "ASPECT:30"        => "Auto",
  "ASPECT:40"        => "Full",
  "ASPECT:50"        => "Zoom",
  "ASPECT:70"        => "Wide",
  "AUDIO:01"         => "Audio1",
  "AUDIO:02"         => "Audio2",
  "AUDIO:03"         => "USB",
  "AVOUT:00"         => "projection",
  "AVOUT:01"         => "constantly",
  "AUTOHOME:00"      => "off",
  "AUTOHOME:01"      => "on",  
  "AUTOKEYSTONE:ON"  => "on",
  "AUTOKEYSTONE:OFF" => "off",
  "BTAUDIO:01"       => "on",
  "BTAUDIO:00"       => "off",
  "DYNRANGE:00"      => "Auto",
  "DYNRANGE:01"      => "SDR",
  "DYNRANGE:20"      => "HDR10",
  "DYNRANGE:30"      => "HLG",  
  "FREEZE:ON"        => "on",
  "FREEZE:OFF"       => "off",
  "HREVERSE:ON"      => "Flip",
  "HREVERSE:OFF"     => "Normal",
  "ILLUM:01"         => "on", 
  "ILLUM:00"         => "off",
  "IMGPRESET:01"     => "Setting1",
  "IMGPRESET:02"     => "Setting2",
  "IMGPRESET:03"     => "Setting3",
  "IMGPRESET:04"     => "Setting4",
  "IMGPRESET:05"     => "Setting5",
  "IMGPROC:01"       => "fine",
  "IMGPROC:02"       => "fast",    
  "MCFI:00"          => "off",
  "MCFI:01"          => "low",
  "MCFI:02"          => "normal",
  "MCFI:03"          => "high",
  "MSEL:00"          => "black",
  "MSEL:01"          => "blue",
  "MSEL:02"          => "user",
  "MUTE:ON"          => "on",
  "MUTE:OFF"         => "off",
  "OVSCAN:00"        => "off",
  "OVSCAN:02"        => "4%",
  "OVSCAN:04"        => "8%",
  "OVSCAN:A0"        => "auto",
  "PRODUCT:00"       => "ModelName_off",
  "PRODUCT:01"       => "ModelName_on",
  "PWR:00"           => "Standby (Net off)", 
  "PWR:01"           => "Lamp on", 
  "PWR:02"           => "Warmup", 
  "PWR:03"           => "Cooldown", 
  "PWR:04"           => "Standby (Net on)", 
  "PWR:05"           => "abnormal Standby",
  "PWR:07"           => "WirelessHD Standby",  
  "SIGNAL:00"        => "none",
  "SIGNAL:01"        => "2D",
  "SIGNAL:02"        => "3D",
  "SIGNAL:03"        => "not_supported",
  "SOURCE:10"        => "Input1",
  "SOURCE:1F"        => "PC1",
  "SOURCE:20"        => "Input2",
  "SOURCE:2F"        => "PC2",
  "SOURCE:30"        => "HDMI1",
  "SOURCE:40"        => "Video",
  "SOURCE:41"        => "Video(RCA)",
  "SOURCE:52"        => "USB",
  "SOURCE:53"        => "LAN",
  "SOURCE:56"        => "ScreenMirror",
  "SOURCE:A0"        => "HDMI2",
  "SOURCE:D0"        => "WirelessHD",
  "SOURCE:F0"        => "ChangeCyclic",    
  "VREVERSE:ON"      => "Flip",
  "VREVERSE:OFF"     => "Normal",
  "WLPWR:00"         => "WLAN_off",
  "WLPWR:01"         => "WLAN_on"
);

# mapping for toggle commands. if PWR is 01, toggle command is off etc
my %ESCVP21net_togglemap = (
  "BTAUDIO:00"     => "on",
  "BTAUDIO:01"     => "off",
  "ILLUM:00"       => "on",
  "ILLUM:01"       => "off",
  "LUMINANCE:00"   => "low",
  "LUMINANCE:01"   => "high",
  "MUTE:ON"        => "off",
  "MUTE:OFF"       => "on",
  "PWR:01"         => "off",
  "PWR:04"         => "on",
  "PWR:07"         => "on"
);

# setting to default, will be enhanced at runtime
my %ESCVP21net_sets = %ESCVP21net_defaultsets;

my %VP21addattrs;

sub ESCVP21net_Define {
  my ($hash, $def) = @_;
  my @param = split('[ \t]+', $def);
 
  if(int(@param) < 3) {
    return "too few parameters: define <name> ESCVP21net <IP_Address> [<port>] [<model>]";
  }
  my $port = "3629";
  my $model = "default";
  $hash->{NAME}       = $param[0];
  $hash->{IP_Address} = $param[2];
  if ($param[3]){
    if ($param[3] =~ m/^\d+$/){
      # param3 is number
      $port = $param[3];
    }
    else{
      # param3 is not a number, so must be "model"
      $model = $param[3];
    }
  }
  if ($param[4]) {
    # 4 params given, last is model
    $model = $param[4];
  }
  $hash->{port} = $port;
  $hash->{model} = $model;
  $hash->{DeviceName} = $param[2].":".$port;

  return "Cannot define device. Please install perl modules $missingModul (e.g. sudo apt-get install libjson-perl or sudo cpan install JSON)."
        if ($missingModul);
  
  # prevent "reappeared" messages in loglevel 1
  $hash->{devioLoglevel} = 5;
  # prevent DevIO from setting "STATE" at connect/disconnect
  $hash->{devioNoSTATE} = 1;
  # subscribe only to notify from global and self
  $hash->{NOTIFYDEV} = "global,TYPE=ESCVP21net";
  # set version
  $hash->{version} = $version;
  
  my $name = $hash->{NAME}; 
  
  # clean up
  RemoveInternalTimer($hash, "ESCVP21net_checkConnection");
  DevIo_CloseDev($hash) if(DevIo_IsOpen($hash));
  
  # force immediate reconnect
  delete $hash->{NEXT_OPEN} if ( defined( $hash->{NEXT_OPEN} ) );
  DevIo_OpenDev($hash, 0, "ESCVP21net_Init", "ESCVP21net_Callback");
  
  # enhance default set hashes with type specific keys
  ESCVP21net_setTypeCmds($hash);
  
	# check if definition is new or existing 
	if($init_done && !defined($hash->{OLDDEF}))
	{
		# set stateFormat
    $attr{$name}{"stateFormat"} = "PWR";
 	}
  main::Log3 $name, 5, "[$name]: Define: device $name defined";
  
  return ;
}

sub ESCVP21net_Undef {
  my ($hash, $arg) = @_; 
  RemoveInternalTimer($hash);
  BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined( $hash->{helper}{RUNNING_PID} ) );
  DevIo_CloseDev($hash);
  return ;
}

sub ESCVP21net_Shutdown {
  my ($hash) = @_;
  my $name = $hash->{NAME}; 
  RemoveInternalTimer($hash);
  DevIo_CloseDev($hash);
  BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined( $hash->{helper}{RUNNING_PID} ) );
  delete $hash->{helper}{nextConnectionCheck} if ( defined( $hash->{helper}{nextConnectionCheck} ) );
  delete $hash->{helper}{nextStatusCheck} if ( defined( $hash->{helper}{nextStatusCheck} ) );
  delete $hash->{helper}{nextCyclicConnect} if ( defined( $hash->{helper}{nextCyclicConnect} ) );
  main::Log3 $name, 5, "[$name]: Shutdown: deleting timers & RUNNING_PID, close Device";  
}

sub ESCVP21net_Initialize {
    my ($hash) = @_;

    $hash->{DefFn}      = \&ESCVP21net_Define;
    $hash->{UndefFn}    = \&ESCVP21net_Undef;
    $hash->{SetFn}      = \&ESCVP21net_Set;
    $hash->{AttrFn}     = \&ESCVP21net_Attr;
    $hash->{ReadFn}     = \&ESCVP21net_Read;
    $hash->{ReadyFn}    = \&ESCVP21net_Ready;
    $hash->{NotifyFn}   = \&ESCVP21net_Notify;
    #$hash->{StateFn}    = \&ESCVP21net_State;
    $hash->{ShutdownFn} = \&ESCVP21net_Shutdown;
    #$hash->{GetFn}      = \&ESCVP21net_Get;
    #$hash->{DeleteFn}   = \&ESCVP21net_Delete;
    #$hash->{RenameFn}   = \&ESCVP21net_Rename;
    #$hash->{DelayedShutdownFn} = \&ESCVP21net_DelayedShutdown;
    
    $hash->{AttrList} =
          "Manufacturer:Epson,other connectionCheck:off,1,15,30,60,120,300,600,3600 AdditionalSettings statusCheckCmd statusCheckInterval:off,1,5,10,15,30,60,300,600,3600 statusOfflineMsg debug:0,1 disable:0,1 cyclicConnect:off,10,15,30,60,120,300,600,3600 "
        . $readingFnAttributes;
}

sub ESCVP21net_Notify($$) {
  my ($hash, $devHash) = @_;
  my $name = $hash->{NAME}; # own name / hash
  my $devName = $devHash->{NAME}; # Device that created the events
  my $checkInterval;
  my $next;

  if(IsDisabled($name)){
    main::Log3 $name, 3, "[$name]: Notify: $name has been set to disabled!";
    return;
  }

  my $events = deviceEvents($devHash,1);
  return if( !$events );

  #main::Log3 $name, 5, "[$name]: running notify from $devName for $name, event is @{$events}";
  
  if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events})){    
    ESCVP21net_setTypeCmds($hash);
    
    if ( defined( $hash->{AdditionalSettings} )){
      ESCVP21net_Attr("set",$name,"AdditionalSettings",$hash->{AdditionalSettings});
      main::Log3 $name, 5, "adding attrs: $name, ".$hash->{AdditionalSettings};
    }
  }

  if($devName eq $name && grep(m/^CONNECTED|opened$/, @{$events})){
    main::Log3 $name, 5, "[$name]: Notify: got @{$events}, check timer";
    # CONNECTED triggers after each internal timer for connectionCheck
    # so we create a timer only if not yet existing

    if ( defined( $hash->{helper}{nextConnectionCheck} )){
      # i.e. timer exists, do nothing
      main::Log3 $name, 5, "[$name]: Notify: got @{$events}, connection timer exists, do nothing";
    }
    else{
      # no timer, so create one for first check
      main::Log3 $name, 5, "[$name]: Notify: got @{$events}, no connection timer exists, create one";
      $checkInterval = AttrVal( $name, "connectionCheck", "60" );
      #set checkInterval to 60 just for first check;
      if ($checkInterval eq "off"){$checkInterval = 60;}
      RemoveInternalTimer($hash, "ESCVP21net_checkConnection");
      $next = gettimeofday() + $checkInterval;
      $hash->{helper}{nextConnectionCheck} = $next;
      InternalTimer($next , "ESCVP21net_checkConnection", $hash);
    }

    if ( defined( $hash->{helper}{nextStatusCheck} )){
      # i.e. timer exists, do nothing
      main::Log3 $name, 5, "[$name]: Notify: got @{$events}, status timer exists, do nothing";
    }
    else{
      # no timer, so create one for first check
      main::Log3 $name, 5, "[$name]: Notify: got @{$events}, no status timer exists, create one";
      # force check after 5 seconds
      $checkInterval = 5;
      RemoveInternalTimer($hash, "ESCVP21net_checkStatus");
      $next = gettimeofday() + $checkInterval;
      $hash->{helper}{nextStatusCheck} = $next;
      InternalTimer($next , "ESCVP21net_checkStatus", $hash);
    }

    if ( defined( $hash->{helper}{nextCyclicConnect} )){
      # i.e. timer exists, do nothing
      main::Log3 $name, 5, "[$name]: Notify: got @{$events}, cyclicConnect timer exists, do nothing";
    }
    else{
      # no timer, so create one for first check
      main::Log3 $name, 5, "[$name]: Notify: got @{$events}, no cyclicConnect timer exists, create one";
      # force check after 5 seconds
      $checkInterval = 60;
      RemoveInternalTimer($hash, "ESCVP21net_cyclicConnect");
      $next = gettimeofday() + $checkInterval;
      $hash->{helper}{nextCyclicConnect} = $next;
      InternalTimer($next , "ESCVP21net_cyclicConnect", $hash);
    }

    # force first PWR check after CONNECT
    ESCVP21net_Set($hash, $name, "PWR", "get");
  }

  if($devName eq $name && grep(m/^DISCONNECTED$/, @{$events})){
    main::Log3 $name, 5, "[$name]: Notify: got @{$events}, deleting timers";
    RemoveInternalTimer($hash);
    delete $hash->{helper}{nextConnectionCheck} if ( defined( $hash->{helper}{nextConnectionCheck} ) );
    delete $hash->{helper}{nextStatusCheck} if ( defined( $hash->{helper}{nextStatusCheck} ) );
    readingsSingleUpdate( $hash, "PWR", "offline", 1);
    main::Log3 $name, 5, "[$name]: Notify: got DISCONNECTED, force PWR to offline";
    BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined( $hash->{helper}{RUNNING_PID} ) );        
  }
}

sub ESCVP21net_Attr {
  my ($cmd,$name,$attr_name,$attr_value) = @_;
	my $hash = $defs{$name};
  my $checkInterval;
  my $next;
  my %ESCVP21net_typesets;
  $attr_value = $cmd if (!$attr_value);
  main::Log3 $name, 5,"[$name]: Attr: executing $cmd $attr_name to $attr_value";

	if($cmd eq "set") {
    if($attr_name eq "Manufacurer") {
      if($attr_value !~ /^Epson|other$/) {
        my $err = "Invalid argument $attr_value to $attr_name. Must be Epson or other.";
        main::Log3 $name, 1,"[$name]: Attr Error for $attr_name: ".$err;
        return $err;
      }
    }
    elsif ($attr_name eq "AdditionalSettings") {
      my @valarray = split / /, $attr_value;
      my $key;
      my $newkey;
      my $newkeyval = "";
      %VP21addattrs = ();
      $hash->{AdditionalSettings} = $attr_value;
      foreach $key (@valarray) {
        $newkey = (split /:/, $key, 2)[0];
        # check if AdditionalSetting is only cmd (e.g. "ILLUM") without parameter (e.g. ":0,1")
        # otherwise take it as ""
        if (defined ((split /:/, $key, 2)[1])){
          $newkeyval = ":".(split /:/, $key, 2)[1];
        }
        main::Log3 $name, 5,"[$name]: Attr: setting $attr_name, key  is $newkey, val is $newkeyval";
        $VP21addattrs{$newkey} = $newkeyval;
        #%ESCVP21net_typesets = (%ESCVP21net_typesets, %VP21addattrs);
        ESCVP21net_setTypeCmds($hash);
      }
    }
    elsif ($attr_name eq "connectionCheck"){
      if ($attr_value eq "0") {
        # avoid 0 timer
        return "0 not allowed for $attr_name!";
      } 
      elsif ($attr_value eq "off"){
        RemoveInternalTimer($hash, "ESCVP21net_checkConnection");
        $hash->{helper}{nextConnectionCheck} = "off";
      }
      else{
        RemoveInternalTimer($hash, "ESCVP21net_checkConnection");
        $checkInterval = $attr_value;
        $next = gettimeofday() + $checkInterval;
        $hash->{helper}{nextConnectionCheck} = $next;
        InternalTimer( $next, "ESCVP21net_checkConnection", $hash);
        main::Log3 $name, 5,"[$name]: Attr: set $attr_name interval to $attr_value";        
      }
    }
    elsif ($attr_name eq "statusCheckInterval"){
      # timer to check status of device
      if ($attr_value eq "0") {
        # 0 means off
        return "0 not allowed for $attr_name!";
      } 
      elsif ($attr_value eq "off"){
        RemoveInternalTimer($hash, "ESCVP21net_checkStatus");
        $hash->{helper}{nextStatusCheck} = "off";
      }
      else{
        RemoveInternalTimer($hash, "ESCVP21net_checkStatus");
        $checkInterval = $attr_value;
        $next = gettimeofday() + $checkInterval;
        $hash->{helper}{nextStatusCheck} = $next;
        InternalTimer( $next, "ESCVP21net_checkStatus", $hash);
        main::Log3 $name, 5,"[$name]: Attr: set $attr_name interval to $attr_value";        
      }
    }

    elsif ($attr_name eq "cyclicConnect"){
      # timer to check status of device
      if ($attr_value eq "0") {
        # 0 means off
        return "0 not allowed for $attr_name!";
      } 
      elsif ($attr_value eq "off"){
        RemoveInternalTimer($hash, "ESCVP21net_cyclicConnect");
        $hash->{helper}{nextCyclicConnect} = "off";
      }
      else{
        RemoveInternalTimer($hash, "ESCVP21net_cyclicConnect");
        $checkInterval = $attr_value;
        $next = gettimeofday() + $checkInterval;
        $hash->{helper}{nextCyclicConnect} = $next;
        InternalTimer( $next, "ESCVP21net_cyclicConnect", $hash);
        main::Log3 $name, 5,"[$name]: Attr: set $attr_name interval to $attr_value";        
      }
    }

    elsif ($attr_name eq "StatusCheckCmd"){
      # ToDo: check for allowed commands
    }
    elsif ($attr_name eq "debug"){
      if ($attr_value eq "1"){
        %ESCVP21net_typesets = ESCVP21net_restoreJson($hash,".Sets");
        %ESCVP21net_typesets = (%ESCVP21net_typesets, %ESCVP21net_debugsets);
        readingsSingleUpdate( $hash, ".Sets", encode_json( \%ESCVP21net_typesets ), 1 );
        $hash->{debug} = 1;
        main::Log3 $name, 5, "[$name]: Attr: added debug sets";        
      }
      else{
        delete $hash->{debug};
        ESCVP21net_setTypeCmds($hash);
        main::Log3 $name, 5, "[$name]: setTypeCmds: deleted debug sets";        
      }        
    }        
  }
  elsif($cmd eq "del"){
    if($attr_name eq "Manufacturer") {
      # do nothing
    }
    elsif($attr_name eq "AdditionalSettings") {
      %VP21addattrs = ();
      #%ESCVP21net_sets = %ESCVP21net_defaultsets;
      ESCVP21net_setTypeCmds($hash);
      main::Log3 $name, 5,"[$name]: Attr: deleting $attr_name";
    }
    elsif($attr_name eq "connectionCheck") {
      RemoveInternalTimer($hash, "ESCVP21net_checkConnection");
      # set default value 600, timer running each 600s
      my $next = gettimeofday() + "600";
      $hash->{helper}{nextConnectionCheck} = $next;
      InternalTimer( $next, "ESCVP21net_checkConnection", $hash);
      main::Log3 $name, 5,"[$name]: Attr: $attr_name removed, timer set to +600";
    }
    elsif($attr_name eq "statusCheckInterval") {
      RemoveInternalTimer($hash, "ESCVP21net_checkStatus");
      # set default value 600, timer running each 600s
      my $next = gettimeofday() + "600";
      $hash->{helper}{nextStatusCheck} = $next;
      InternalTimer( $next, "ESCVP21net_checkStatus", $hash);
      main::Log3 $name, 5,"[$name]: Attr: $attr_name removed, timer set to +600";
    }
    elsif($attr_name eq "cyclicConnect") {
      RemoveInternalTimer($hash, "ESCVP21net_cyclicConnect");
      # set default value 3600, timer running each 3600s
      my $next = gettimeofday() + "3600";
      $hash->{helper}{nextCyclicConnect} = $next;
      InternalTimer( $next, "ESCVP21net_cyclicConnect", $hash);
      main::Log3 $name, 5,"[$name]: Attr: $attr_name removed, timer set to +3600";
    }
    elsif ($attr_name eq "debug"){
      delete $hash->{debug};
      ESCVP21net_setTypeCmds($hash);
      main::Log3 $name, 5, "[$name]: Attr: deleted debug sets";
    }            
  }
  return ;
}

sub ESCVP21net_Ready($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  # try to reopen the connection in case the connection is lost
  my $status = DevIo_getState($hash);
  if ($status eq "disconnected"){
    RemoveInternalTimer($hash, "ESCVP21net_checkConnection");
    DevIo_CloseDev($hash) if(DevIo_IsOpen($hash));
    DevIo_OpenDev($hash, 1, "ESCVP21net_ReInit", "ESCVP21net_CallbackReady");
  }
}

sub ESCVP21net_State($$$$){
  # not really needed
  my ($hash, $time, $readingName, $value) = @_;
  my $name = $hash->{NAME};
  # just logging subroutine call
  Log3 $name, 5, "[$name] SetState called";  
  return undef;
}

sub ESCVP21net_Get {
	# return immediately, not required currently
    return "none";
}

sub ESCVP21net_Init($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $checkInterval;
  my $next;
  main::Log3 $name, 5,"[$name]: Init: DevIo successful, initialize connectionCheck";
 
  # set initial connection check, if "off" it will only run once  
  $checkInterval = AttrVal( $name, "connectionCheck", "60" );
  if ($checkInterval eq "off"){$checkInterval = 60;}
  RemoveInternalTimer($hash, "ESCVP21net_checkConnection");
  #delete $hash->{helper}{nextConnectionCheck} if (defined($hash->{helper}{nextConnectionCheck}));
  $next = gettimeofday() + $checkInterval;
  $hash->{helper}{nextConnectionCheck} = $next;
  InternalTimer($next , "ESCVP21net_checkConnection", $hash);

  # set initial cyclic check, if "off" it will only run once
  $checkInterval = AttrVal( $name, "cyclicConnect", "3600" );
  if ($checkInterval eq "off"){$checkInterval = 60;} 
  RemoveInternalTimer($hash, "ESCVP21net_cyclicConnect");
  #delete $hash->{helper}{nextCyclicConnect} if (defined($hash->{helper}{nextCyclicConnect}));
  $next = gettimeofday() + $checkInterval;
  $hash->{helper}{nextCyclicConnect} = $next;
  InternalTimer( $next, "ESCVP21net_cyclicConnect", $hash);  

  return undef; 
}

sub ESCVP21net_ReInit($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  # just logging subroutine call
  main::Log3 $name, 5,"[$name]: ReInit: DevIo ReInit done"; 
  return undef; 
}

sub ESCVP21net_Callback($){
  # will be executed after connection establishment (see DevIo_OpenDev())
  my ($hash, $error) = @_;
  my $name = $hash->{NAME};
  my $rv;
  my $offlineMsg;
  
  if ($error){
    main::Log3 $name, 3, "[$name] DevIo callback error: $error";
    $offlineMsg = AttrVal($name, "statusOfflineMsg", "offline");
    $rv = readingsSingleUpdate($hash, "PWR", $offlineMsg, 1);
    main::Log3 $name, 3, "[$name] DevIo callback error: force PWR to $offlineMsg";
  }
  my $status = DevIo_getState($hash);
  if ($status eq "disconnected"){
    # remove timers and pending setValue calls if device is disconnected
    main::Log3 $name, 3, "[$name] DevIo callback: STATE is $status, delete timers & RUNNING_PID";
    RemoveInternalTimer($hash);
    delete $hash->{helper}{nextConnectionCheck}
      if (defined($hash->{helper}{nextConnectionCheck}));
    delete $hash->{helper}{nextStatusCheck}
      if (defined($hash->{helper}{nextStatusCheck}));
    BlockingKill($hash->{helper}{RUNNING_PID})
      if (defined($hash->{helper}{RUNNING_PID}));

    # check if we should update statusCheck
    my $checkInterval = AttrVal($name, "statusCheckInterval", "300");
    my $checkcmd = AttrVal($name, "statusCheckCmd", "PWR");
    $offlineMsg = AttrVal($name, "statusOfflineMsg", "offline");

    if ($checkInterval ne "off"){
      # update reading for $checkcmd with $offlineMsg
      #$rv = readingsSingleUpdate($hash, $checkcmd, $offlineMsg, 1);
      $rv = readingsSingleUpdate($hash, "PWR", $offlineMsg, 1);
      main::Log3 $name, 5,"[$name]: DevIo callback: $checkcmd set to $offlineMsg";
      return ;
    }      
  }    
  return undef; 
}

sub ESCVP21net_CallbackReady() {
    my ( $hash, $err ) = @_;
    my $name = $hash->{NAME};
    main::Log3 $name, 5, "[$name]: CallbackReady error: $err" if ($err);
    if ($err && $err =~ /\(113\)/){
      # seems that DevIo sends fhem into 100% CPU after TCP timeout
      # empirically, this seems to be the case when err is "No route to host (113)"
      # (normally, DevIo returns with "timed out")
      # so we reconnect then...
      ESCVP21net_connect($hash);
    }
}

sub ESCVP21net_Read($){
  # I could not yet get Read data from DevIo, so I use send/recv socket
  my ($hash) = @_;
  my $name = $hash->{NAME};
  # we dont really expect data here. Its just to gracefully close the device if the connection was closed
  my $buf = DevIo_SimpleRead($hash);
  main::Log3 $name, 5,"[$name]: Read: received $buf"; 
  return;
}

sub ESCVP21net_Set {
  my ($hash, @param) = @_;
  my $value;
	return '"set ESCVP21net" needs at least one argument'
    if (int(@param) < 2);
  my $name = shift @param;
  my $opt = shift @param;
  if (int(@param) > 0){
    $value = join("", @param);
    #my $value = shift @param;    
  }
  else{
    $value = "none";
  }
  # add LF to log for better overview...
  if ($opt ne "?"){
    main::Log3 $name, 5, "\n";
    main::Log3 $name, 5, "[$name]: Set: called with $name $opt $value";
  }
  
  $hash = $defs{$name};
  my $list = "";
  my $timeout    = 10;
  my $blockingFn = "ESCVP21net_setValue";
  my $finishFn   = "ESCVP21net_setValueDone";
  my $abortFn    = "ESCVP21net_setValueError";

  # collect available set commands
  my %ESCVP21net_typesets = ESCVP21net_restoreJson($hash,".Sets");
  
  if (AttrVal( $name, "debug", "0" ) eq "1"){
    %ESCVP21net_typesets = (%ESCVP21net_typesets, %ESCVP21net_debugsets);
    main::Log3 $name, 5, "[$name]: setTypeCmds: added debug sets";
  }
  
  my @cList = (keys %ESCVP21net_typesets);
    foreach my $key (@cList){
    $list = $list.$key.$ESCVP21net_typesets{$key}." ";    
  }
  
  #main::Log3 $name, 5, "[$name]: Set: set list is $list";

  if (!exists($ESCVP21net_typesets{$opt})){
    return "Unknown argument $opt, please choose one of $list";
  }

  if(IsDisabled($name)){
    main::Log3 $name, 3, "[$name]: Set: $name is disabled by framework!";
    return;
  }

##### next options only will be shown if attr debug is set  
  if ($opt eq "reRead"){
    # re-read set commands, needed after manual reload of module 
    ESCVP21net_setTypeCmds($hash);
    return undef;
  }

  if ($opt eq "encode"){
    # stores current set commands to .Sets
    readingsSingleUpdate( $hash, ".Sets", encode_json( \%ESCVP21net_typesets ), 1 );
    return undef;
  }  

  if ($opt eq "decode"){
    # restores set commands from .Set
    main::Log3 $name, 5, "[$name]: Set: decode: calling decode ";
    %ESCVP21net_typesets = ESCVP21net_restoreJson($hash,".Sets");
    return undef;
    
    #works too:
    #my $jsets = ReadingsVal($name, ".Sets", "reread:noArg");
    #my $decode = decode_json($jsets);
    #%ESCVP21net_typesets = %$decode;
    #my %decode = %$decode;
    #main::Log3 $name, 5, "[$name]: Set: decode: keys(%decode) ";
    #return undef;
  }

  if ($opt eq "cleanup"){
    # cleanup everything... (like shutdown)
    main::Log3 $name, 5, "[$name]: Set: cleanup: calling cleanup ";
    ESCVP21net_cleanup($hash);
    return undef;
  }

  if ($opt eq "connect"){
    # connecting via Dev_Io
    main::Log3 $name, 5, "[$name]: Set: connect: calling connect";
    ESCVP21net_connect($hash);
    return undef;
  }

  if ($opt eq "removeTimer"){
    # connecting via Dev_Io
    main::Log3 $name, 5, "[$name]: Set: removeTimer: calling removeTimer";
    ESCVP21net_removeTimer($hash);
    return undef;
  }

  if ($opt eq "closeDevice"){
    # connecting via Dev_Io
    main::Log3 $name, 5, "[$name]: Set: closeDevice: calling closeDevice";
    ESCVP21net_closeDevice($hash);
    return undef;
  }

  if ($opt eq "deleteNextOpen"){
    # connecting via Dev_Io
    main::Log3 $name, 5, "[$name]: Set: deleteNextOpen: calling deleteNextOpen";
    ESCVP21net_deleteNextOpen($hash);
    return undef;
  }

  if ($opt eq "openDevice"){
    # connecting via Dev_Io
    main::Log3 $name, 5, "[$name]: Set: openDevice: calling openDevice";
    ESCVP21net_openDevice($hash);
    return undef;
  }

  if ($opt eq "isOpen"){
    # connecting via Dev_Io
    #main::Log3 $name, 5, "[$name]: Set: isOpen: calling isOpen";
    my $status = DevIo_IsOpen($hash);
    main::Log3 $name, 5, "[$name]: Set: isOpen: status is $status, TCPDev: $hash->{TCPDev}";
    return undef;
  }
##### end of debug options
  
  # everything fine so far, so contruct $arg to pass by blockingFn  
  my $arg = $name."|".$opt."|".$value;
  # store latest command to helper
  $hash->{helper}{lastCommand} = $opt;  
  
  if ( !( exists( $hash->{helper}{RUNNING_PID} ) ) ) {
    $hash->{helper}{RUNNING_PID} = BlockingCall( $blockingFn, $arg, $finishFn, $timeout, $abortFn, $hash );
    $hash->{helper}{RUNNING_PID}{loglevel} = 4;
    # next line is required, otherwise fhem will return with "4" from last line - bug?
    main::Log3 $name, 5, "[$name]: Set: calling $blockingFn with $arg";
  }
  else {
    # reschedule
    Log3 $name, 3, "[$name] Set: Blocking Call running, reschedule for $timeout";
    my $arg = $name."|".$opt."|".$value;
    RemoveInternalTimer($arg, "ESCVP21net_rescheduleSet");
    my $next = gettimeofday() + $timeout;
    InternalTimer( $next, "ESCVP21net_rescheduleSet", $arg);
  }	
}

sub ESCVP21net_setValue($){
  # subroutine should be called unblocking e.g. via ESCVP21net_Set
  my ($string) = @_;
  my ( $name, $cmd, $val ) = split( "\\|", $string );
  my $result = "none";
  my $returnval = "$name|$cmd|error"; # just for initialization
  my @resultarr;
  my $data = "";
  my $datakey = "none";
  my $valorg = $val;
  my $encdata = "";
  my $volfactor = 12;
  my $initstatus = "";
  my $toggle = 0;
  my $sendloop = "1";
  my @cmds2set;
  my $hash = $defs{$name};

  # add ? if cmd is get
  if ($val eq "get"){
    $data = "$cmd?\r\n";
    $encdata = encode("utf8",$data);
  }
  elsif($val eq "toggle"){
    $data = "$cmd?\r\n";
    $encdata = encode("utf8",$data);
    $toggle = 1;
  }
  elsif(!defined($val)){
    # val is empty for GetAll, GetStatus
    $val = "none";
  }  
  # else get the correct raw command from data hash
  else {
    $datakey = $cmd.":".$val;
    if (exists($ESCVP21net_data{$datakey})){
      $val = $ESCVP21net_data{$datakey};
    }
    # VOLset needs special treatment, since Epson does some funny by-12 calculation
    if ($cmd eq "VOLset"){
      $val = $val*$volfactor;
	    $cmd = "VOL";      
    }
    # set end encode data to be sent, Epson wants \r\n and utf8
    $data = "$cmd $val\r\n";
    $encdata = encode("utf8",$data);  
  }

  # now open socket - couldn't get read/write to socket via DevIo
  my $sock = ESCVP21net_openSocket($hash);
  
  if (defined ($sock)){
    # send Epson initialization string, returns "init_ok" or "init_error"
    $initstatus = ESCVP21net_VP21init($name,$sock);
    main::Log3 $name, 5, "[$name]: setValue: Init sequence gave $initstatus";
  }  
  else{
    # Ups, we got no socket, i.e. no connection to Projector!
  	main::Log3 $name, 3, "[$name]: setValue: no socket";
    $initstatus = "no socket for init";
    $returnval = "$name|$cmd|no socket";
  }

  if (defined ($sock) && $initstatus eq "init_ok"){
    # re-init returnval to empty string
    $returnval = "";  
    # GetAll will query all set values which have a "get" defined
    # result of each single command will be formatted as $name|$cmd|$result
    # results of all commands will then be separated by ":"
    if ($cmd eq "GetAll" || $cmd eq "GetStatus"){
      # collect all commands which have a "get"
      if ($cmd eq "GetStatus"){
        @cmds2set = ESCVP21net_collectStatusCmds($hash);
      }
      else{
        @cmds2set = ESCVP21net_collectGetCmds($hash);
      }
      for (@cmds2set){
        $cmd = $_;
        $data = "$cmd?\r\n";
        $encdata = encode("utf8",$data);
        
        # strip CR, LF, non-ASCII just for logging - there might be a more elegant way to do this...
        my $encdatastripped = $encdata;
        $encdatastripped =~ s/[\r\n\x00-\x19]//g;
        main::Log3 $name, 5, "[$name]: setValue: GetAll or GetStatus: sending raw data: $encdatastripped";        

        send($sock , $encdata , 0);
        recv($sock, $result, 1024, 0);
        
        # strip CR, LF, non-ASCII just for logging - there might be a more elegant way to do this...
        my $resultstripped = $result;
        $resultstripped =~ s/[\r\n\x00-\x19]//g;
        main::Log3 $name, 5, "[$name]: setValue: GetAll or GetStatus: received raw data: $resultstripped";        

        # replace CR and LF in result by space
        $result =~ s/[\r\n]/ /g;
        
        # check for error
        if ($result =~ "ERR") {
          $result = "ERROR!";
          main::Log3 $name, 5, "[$name]: ERR - result of $cmd is $result";
        }
        elsif (!$result){
          $result = "ERROR!";
          main::Log3 $name, 5, "[$name]: result undef - result of $cmd is $result";
        }
        elsif ($result eq ""){
          $result = "no_answer";
          main::Log3 $name, 5, "[$name]: result empty - result of $cmd is $result";          
        }
        # no error, so run calcResult to get "nice" value
        else {
          # calcResult will get nicer text from ESCVP21net_calcResult
          $result = ESCVP21net_calcResult($hash, $result, $cmd, $datakey, $volfactor);
          main::Log3 $name, 3, "[$name]: result of $cmd is $result";
        
          # constructing returnval string - triples separated by ":";
          if ($returnval eq ""){
            # first result without leading ":"
            $returnval = $name."|".$cmd."|".$result;
            }         
          else {
            # add next result, separated by ":"
            $returnval = $returnval.":".$name."|".$cmd."|".$result;
          }
        }
      }
    # so, we return the string $returnval, containing multiple triples separated by ":"
    main::Log3 $name, 5, "[$name]: GetAll or GetStatus: resultstring is $returnval";
    }
    
    # continue here if not "GetAll"; $returnval will finally contain only one triple $name|$cmd|$result
    # command to send is either "$cmd?" (for "get") or "$cmd $value" (if we want to set an value)
    # run do loop at least once 
    else {
      do {
        my $error = "ERR";
        # just for logging: strip CR, LF, non-ASCII - there might be a more elegant way to do this...
        my $encdatastripped = $encdata;
        $encdatastripped =~ s/[\r\n\x00-\x19]//g;
        main::Log3 $name, 5, "[$name]: setValue: sending raw data: $encdatastripped";
        
        # finally, send command and receive result
        send($sock , $encdata , 0);
        recv($sock, $result, 1024, 0);

        # replace \r\n from result by space (don't delete the space, it is needed!)
        $result =~ s/[\r\n]/ /g;
        #$result =~ s/[\r\n\x00-\x19]//g; # might work too, since \x20 is kept
        
        # just for logging: strip CR, LF, non-ASCII - there might be a more elegant way to do this...
        my $resultstripped = $result;
        $resultstripped =~ s/[\r\n\x00-\x19]//g;
        main::Log3 $name, 5, "[$name]: setValue: received raw data: $resultstripped";
        
        # just another form of checking, if result contains an erorr string "ERR"
        if (index($result, $error) != -1) {
          $result = "ERROR!";
        }
        # return of ":" means OK, no value returned, i.e. we have tried to set an value
        elsif ($result eq ":") {
          # after set done, read current value
          # does not work fpr PWR!
          if ($cmd eq "PWR"){
            # need error handling - not critical, will just run in non-blocking timeout
            # seems to happen on toggle PWR only, i.e. PWR get - set - get
            # OK for all other toggles
            # OK for PWR on, i.e. PWR set - get
          }
          $data = "$cmd?\r\n";
          $encdata = encode("utf8",$data);

          # strip CR, LF, non-ASCII just for logging - there might be a more elegant way to do this...
          my $encdatastripped = $encdata;
          $encdatastripped =~ s/[\r\n\x00-\x19]//g;
          main::Log3 $name, 5, "[$name]: setValue: get after set: sending raw data: $encdatastripped";

          # finally, get after set = send command and receive result          
          send($sock , $encdata , 0);
          recv($sock, $result, 1024, 0);

          # strip CR, LF, non-ASCII just for logging - there might be a more elegant way to do this...
          $result =~ s/[\r\n]/ /g;
          my $resultstripped = $result;
          $resultstripped =~ s/[\r\n\x00-\x19]//g;
          main::Log3 $name, 5, "[$name]: setValue: get after set: received raw data: $resultstripped";

          # calcResult will get nicer text from ESCVP21net_calcResult
          $result = ESCVP21net_calcResult($hash, $result, $cmd, $datakey, $volfactor);
        }  
        else {
          # we got neither "ERR" nor ":" but an interpretable value
          if ($toggle > 0){
            my $nextcmd;
            # result is of the form "LAMP=1234 :"
            # so we strip first before " " to "LAMP=1234", then after "=" to "1234"	
            my $toggleresult = (split / /, (split /=/, $result, 2)[1], 2)[0];
            # get correct nextcmd from togglemap
            $datakey = $cmd.":".$toggleresult;
            if (exists($ESCVP21net_togglemap{$datakey})){
              $nextcmd = $ESCVP21net_togglemap{$datakey};
            #}
              Log3 $name, 5, "[$name]: setValue: toggleloop: prepare to call Set for toggle $cmd with $nextcmd";
              # translate "nice" nextcmd to raw value data
              $datakey = $cmd.":".$nextcmd;
              if (exists($ESCVP21net_data{$datakey})){
                $nextcmd = $ESCVP21net_data{$datakey};
              }
              # encode raw command
              $data = "$cmd $nextcmd\r\n";
              $encdata = encode("utf8",$data);
              # run do loop once more  
              $sendloop++;
            }
            else{
              # no mapping toggle command found
              Log3 $name, 5, "[$name]: setValue: toggleloop: no mapping toggle command found for $cmd:$toggleresult";
            }
            # don't run in toggle area during next do loop  
            $toggle--; 
          }
          $result = ESCVP21net_calcResult($hash, $result, $cmd, $datakey, $volfactor);
          main::Log3 $name, 3, "[$name]: result of $cmd is $result";
        }
        $sendloop--;
        $returnval = "$name|$cmd|$result";
      } while ($sendloop > 0);
    } 
    # returnval now contains one or more triples, we can close the socket
    close($sock);    
  }
  # Ups, initialization failed
  else{
  	main::Log3 $name, 3, "[$name]: setValue: init failed: $initstatus";
    $returnval = "$name|$cmd|init failed";
  }
  if ($returnval eq ""){
    # error handling on empty result
    $returnval = "$name|$cmd|no_result";
    main::Log3 $name, 5, "[$name]: result empty - result of $cmd is $result";
  }
  # to prevent not-deleting of RUNNIG_PID on errors in finishFn setValueDone:
  delete($hash->{helper}{RUNNING_PID}) if ( defined( $hash->{helper}{RUNNING_PID} ) );    
  return $returnval;
}

sub ESCVP21net_setValueDone {
  my ($resultstring) = @_;
  my $count = 0;
  my $rv;
  my $getcmds = "";
 
  if (!$resultstring || $resultstring eq ""){
    main::Log3 "ESCVP21net", 5, "[ESCVP21net]: setValueDone says: resultstring is empty!";
    return;
  }
  my @resultarr = split(':', $resultstring);

  # just get name from first result, count is 0
  my ( $name, $cmd, $result ) = split( "\\|", $resultarr[$count] );
  my $hash = $defs{$name};
  main::Log3 $name, 5, "[$name]: setValueDone says: result is: $result, resultarray: @resultarr";

  my $offlineMsg = AttrVal($name, "statusOfflineMsg", "offline");
  
  readingsBeginUpdate($hash);  
  
  # resultarr might contain one or more triples $name|$cmd|$result, separated by ":"
  foreach (@resultarr){
    main::Log3 $name, 5, "[$name]: setValueDone: resultarray loop begin: $resultarr[$count]";
    ( $name, $cmd, $result ) = split( "\\|", $resultarr[$count] );
    if ($result =~ "ERROR"){
      $getcmds .=$cmd." (error),";
      $rv = $result;
    }
    elsif($result =~"init failed"){
      #$getcmds .=$cmd." (init failed),";
      $getcmds .="init failed,";
      $rv = $result;
      readingsBulkUpdate($hash, "PWR", $offlineMsg, 1);
      main::Log3 $name, 5, "[$name]: setValueDone says: force PWR to $offlineMsg since init failed";
    }
    else{
      $rv = readingsBulkUpdate($hash, $cmd, $result, 1);
      # if VOL, we also have to set VOLset!
      $rv = readingsBulkUpdate($hash, "VOLset", "set to $result", 1)
        if ($cmd eq "VOL");
      $getcmds .= $cmd.",";     
    }
    main::Log3 $name, 5, "[$name]: setValueDone: resultarray loop end: $cmd set to $rv";
    $count++;
  }
  
  # strip last ","
  $getcmds = substr $getcmds, 0, -1;

  # additinally, set GetStatus or GestAll to the command set
  if ($hash->{helper}{lastCommand} eq "GetStatus"){
    readingsBulkUpdate($hash, "GetStatus", $getcmds, 1);
    main::Log3 $name, 5, "[$name]: setValueDone: additionally, set GetStatus to $getcmds";
  }
  else{
    readingsBulkUpdate($hash, "GetAll", $getcmds, 1);
    main::Log3 $name, 5, "[$name]: setValueDone: additionally, set GetAll to $getcmds";
  } 
  readingsEndUpdate($hash, 1);
  delete($hash->{helper}{RUNNING_PID}) if ( defined( $hash->{helper}{RUNNING_PID} ) );
}

sub ESCVP21net_setValueError {
   my ($hash) = @_;
   my $name = $hash->{NAME};
   main::Log3 $name, 3, "[$name]: setValue error";
   delete($hash->{helper}{RUNNING_PID});
}

sub ESCVP21net_calcResult {
  my ($hash, $result, $cmd, $datakey, $volfactor) = @_;
  # result is of the form "LAMP=1234 :"
  # or something like IMEVENT=0001 03 00000002 00000000 T1 F1 : (happens sometimes at PWR off, 03 is the relevant value then)
  if (!$result){
    $result = "none";
    return $result;
  }
  elsif ($result =~ "IMEVENT"){
    $result = (split / /, $result, 3)[1];
  }
  elsif ($result =~ "PWSTATUS"){
    # result is something like PWSTATUS=01 00000000 00000000 T1 F1 :
    $result = (split / /, (split /=/, $result, 2)[1], 2)[0];
  }  
  else{
    # so we strip first before " " to "LAMP=1234", then after "=" to "1234"	
    $result = (split / /, (split /=/, $result, 2)[1], 2)[0];
  }
  
  # translate result to a nice wording, collect available results first
  my %ESCVP21net_typeresults = ESCVP21net_restoreJson($hash,".Results");
  $datakey = $cmd.":".$result;
  if (exists($ESCVP21net_typeresults{$datakey})){
    $result = $ESCVP21net_typeresults{$datakey};
  }
  
  if ($cmd eq "VOL"){
    # Epson Vol is not linear value*12, so we need ceil to round up
    $result = ceil($result/$volfactor);
  }
  return $result;
}

sub ESCVP21net_collectGetCmds {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $count = 0;
  my $cmd;
  my $keyword = "get";
  my @setcmds;
  my @gets;
  
  # collect all commands which contain $keyword ("get")
  my%ESCVP21net_typesets = ESCVP21net_restoreJson($hash,".Sets");
  foreach $cmd (keys %ESCVP21net_typesets) {
    if (defined($ESCVP21net_typesets{$cmd})){
      $gets[$count] = $ESCVP21net_typesets{$cmd};
    }
    else{
      $gets[$count] = "none";
    }
    
    if ($gets[$count] =~ "$keyword") {      
      $setcmds[$count++] = $cmd;
    }
  }
  main::Log3 $name, 5, "[$name]: collectGetCmds: collected setcmds: @setcmds";
  return @setcmds;
}

sub ESCVP21net_collectStatusCmds {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $count = 0;
  my $cmd;
  my $keyword = "get";
  my @setcmds;
  my @gets;
  
  # collect all commands from attr statusCheckCmd which contain $keyword ("get")
  my%ESCVP21net_typesets = ESCVP21net_restoreJson($hash,".Sets");

  my $checkcmd = AttrVal( $name, "statusCheckCmd", "PWR" );
  @setcmds = split (' ',$checkcmd);

  foreach $cmd (@setcmds) {
    if (defined($ESCVP21net_typesets{$cmd})){
      $gets[$count] = $ESCVP21net_typesets{$cmd};
    }
    else{
      $gets[$count] = "none";
    }
    
    if ($gets[$count] =~ "$keyword") {      
      $setcmds[$count++] = $cmd;
    }
  }
  main::Log3 $name, 5, "[$name]: collectStatusCmds: collected statusChk cmds: @setcmds";
  return @setcmds;
}

sub ESCVP21net_openSocket($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $remote = $hash->{IP_Address};
  my $port = $hash->{port};
  my $sock = new IO::Socket::INET (
          PeerAddr => $remote,
          PeerPort => $port,
          Proto => 'tcp',
          Timout => 5
        );
  if (defined ($sock)){
    main::Log3 $name, 5, "[$name]: Socket opened to $remote on port $port";
  }
  else{
	  main::Log3 $name, 3, "[$name]: NO socket opened to $remote on port $port";
  }
  return ($sock);
}

sub ESCVP21net_VP21init ($$) {
  # initialize VP21 connection with hex sequence
  my ($name,$sock) = @_;
  #my $name = "ESCVP21net";
  my $result = "none";
  my $status = "none";
  my $initseqhex = "\x45\x53\x43\x2F\x56\x50\x2E\x6E\x65\x74\x10\x03\x00\x00\x00\x00";
  my $initans = "ESC/VP.net";
  # Send initialization for Epson "ESC/VP.net\r\n\0\0\0"
  # needs hex: \x45\x53\x43\x2F\x56\x50\x2E\x6E\x65\x74\x10\x03\x00\x00\x00\x00"
  my $encdata = encode("utf8",$initseqhex);
  if (defined ($sock)){
    send($sock , $encdata , 0);
    # Receive reply from server
    recv($sock, $result, 1024, 0);
    # strip CR, LF, non-ASCII from result
    $result =~ s/[\r\n\x00-\x20]//g;
    if ($result eq $initans){
      main::Log3 $name, 5, "[$name]: initializate gave correct answer $result";
      $status = "init_ok";
    }
    else{
      main::Log3 $name, 3, "[$name]: initializate gave wrong answer $result, expected $initans";
      $status = "init_error";
    }
  }
  else{
    main::Log3 $name, 3, "[$name]: initialization got no socket";
    $result = "no socket for initialize";
    $status = "init_error";
  }
  main::Log3 $name, 5, "[$name]: initializate gave answer $result, expected $initans";
  return $status;
}

sub ESCVP21net_checkConnection ($) {
  # checks each intervall if connection is still alive - DevIo recognizes a broken connection
  # (like device switched completely off) only after TCP timeout of 60-90 minutes
  # check can be omitted by setting checkIntervall to "off"  
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash, "ESCVP21net_checkConnection");

  my $checkInterval = AttrVal( $name, "connectionCheck", "60" );
  
  if ($checkInterval eq "off"){
    return ;
  }
  
  # my $status = DevIo_IsOpen($hash); # would just tell if FD exists
  # let's try to reopen the connection. If successful, FD is kept or created.
  # if not successful, NEXT_OPEN is created.
  # $status is always undef, since callback fn is given
  my $status = DevIo_OpenDev($hash, 1, "ESCVP21net_ReInit", "ESCVP21net_Callback");
  
  #delete $hash->{NEXT_OPEN} if ( defined( $hash->{NEXT_OPEN} ) );
  #delete $hash->{helper}{nextConnectionCheck} if ( defined( $hash->{helper}{nextConnectionCheck} ) );

  if (!($hash->{FD}) && $hash->{NEXT_OPEN}) {
    # device was connected, but TCP timeout reached
    # DevIo tries to re-open after NEXT_OPEN
    # no internal timer needed
    delete $hash->{helper}{nextConnectionCheck}
      if ( defined( $hash->{helper}{nextConnectionCheck} ) );    
    main::Log3 $name, 5, "[$name]: connectionCheck: no FD, NEXT_OPEN is $hash->{NEXT_OPEN}, no timer set";  
  }
  elsif (!($hash->{FD}) && !$hash->{NEXT_OPEN}){
    # not connected, DevIo not active, so device won't open again automatically
    # should never happen, since we called DevIo_Open above!
    # no internal timer needed, but should we ask DevIo again for opening the connection?
    main::Log3 $name, 5, "[$name]: connectionCheck: no FD, no NEXT_OPEN, should not happen!";
  }
  elsif ($hash->{FD} && $hash->{NEXT_OPEN}){
    # not connected - device was connected, but is not reachable currently
    # DevIo tries to connect again at NEXT_OPEN
    # should we try to clean up by closing and reopening?
    # no internal timer needed
    delete $hash->{helper}{nextConnectionCheck}
      if ( defined( $hash->{helper}{nextConnectionCheck} ) );
    main::Log3 $name, 5, "[$name]: connectionCheck: FD and NEXT_OPEN, Dev_Io will reconnect periodically";
  }
  elsif ($hash->{FD} && !$hash->{NEXT_OPEN}){
    # device is connected, or seems to be (since broken connection is not detected by DevIo!)
    # normal state when device is on and reachable
    # or when it was on, turned off, but DevIo did not recognize (TCP timeout not reached)
    # internal timer makes sense to check, if device is really reachable
    my $next = gettimeofday() + $checkInterval; # if checkInterval is off, we won't reach this line
    $hash->{helper}{nextConnectionCheck} = $next;
    InternalTimer( $next, "ESCVP21net_checkConnection", $hash);
    main::Log3 $name, 5, "[$name]: connectionCheck: FD but no NEXT_OPEN, next connection timer set";
  }  
}

sub ESCVP21net_checkStatus ($){
  # use $statusCheckCmd to read device status
  # Should we check if command is valid... but some users might want to use a non implemented one?
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $checkcmd;

  my $checkInterval = AttrVal( $name, "statusCheckInterval", "300" );
  # changed for multiple statusCheckCmds
  # if checkcmd is GetAll, just take it - otherwise set it to GetStatus
  # effective cmds for GetStatus will be evaluated in setValue subroutine
  $checkcmd = AttrVal( $name, "statusCheckCmd", "PWR" );
  if ($checkcmd ne "GetAll"){
    $checkcmd = "GetStatus";
  }

  my $next;
  
  if ($checkInterval eq "off"){
    RemoveInternalTimer($hash, "ESCVP21net_checkStatus");
    main::Log3 $name, 5,"[$name]: checkStatus: status timer removed";
    return ;
  }
  # else{
  #   my $value = "get";
  #   ESCVP21net_Set($hash, $name, $checkcmd, $value);
  #   $next = gettimeofday() + $checkInterval;
  #   $hash->{helper}{nextStatusCheck} = $next;
  #   InternalTimer( $next, "ESCVP21net_checkStatus", $hash);
  #   main::Log3 $name, 5,"[$name]: checkStatus: next status timer set";
  # }

  #### check if timer is required, see connectionCheck
  if (!($hash->{FD}) && $hash->{NEXT_OPEN}) {
    # device was connected, but TCP timeout reached
    # DevIo tries to re-open after NEXT_OPEN
    # no internal timer needed
    delete $hash->{helper}{nextStatusCheck}
      if ( defined( $hash->{helper}{nextStatusCheck} ) );    
    main::Log3 $name, 5, "[$name]: checkStatus: no FD, NEXT_OPEN is $hash->{NEXT_OPEN}, no timer set";  
  }
  elsif (!($hash->{FD}) && !$hash->{NEXT_OPEN}){
    # not connected, DevIo not active, so device won't open again automatically
    # should never happen, since we called DevIo_Open above!
    # no internal timer needed, but should we ask DevIo again for opening the connection?
    main::Log3 $name, 5, "[$name]: checkStatus:no FD, no NEXT_OPEN, should not happen!";
  }
  elsif ($hash->{FD} && $hash->{NEXT_OPEN}){
    # not connected - device was connected, but is not reachable currently
    # DevIo tries to connect again at NEXT_OPEN
    # should we try to clean up by closing and reopening?
    # no internal timer needed
    delete $hash->{helper}{nextStatusCheck}
      if ( defined( $hash->{helper}{nextStatusCheck} ) );
    main::Log3 $name, 5, "[$name]: checkStatus: FD and NEXT_OPEN, Dev_Io will reconnect periodically";
  }
  elsif ($hash->{FD} && !$hash->{NEXT_OPEN}){
    # device is connected, or seems to be (since broken connection is not detected by DevIo!)
    # normal state when device is on and reachable
    # or when it was on, turned off, but DevIo did not recognize (TCP timeout not reached)
    # internal timer makes sense to check, if device is really reachable
    my $value = "none";
    ESCVP21net_Set($hash, $name, $checkcmd, $value);
    $next = gettimeofday() + $checkInterval; # if checkInterval is off, we won't reach this line
    $hash->{helper}{nextStatusCheck} = $next;
    InternalTimer( $next, "ESCVP21net_checkStatus", $hash);
    main::Log3 $name, 5, "[$name]: checkStatus: FD but no NEXT_OPEN, next status timer set";
  }
}

sub ESCVP21net_setTypeCmds ($){
  # enhance default set command by type specific ones
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my %ESCVP21net_typesets;
  my %ESCVP21net_typeresults;
  
  if ($hash->{model} eq "TW5650"){
    %ESCVP21net_typesets = (%ESCVP21net_defaultsets,%ESCVP21net_TW5650sets, %VP21addattrs);
    %ESCVP21net_typeresults = (%ESCVP21net_defaultresults,%ESCVP21net_TW5650result);
    main::Log3 $name, 5, "[$name]: setTypeCmds: loaded TW5650 sets and result";
  }
  elsif ($hash->{model} eq "EB2250U"){
    %ESCVP21net_typesets = (%ESCVP21net_defaultsets,%ESCVP21net_EB2250Usets, %VP21addattrs);
    %ESCVP21net_typeresults = (%ESCVP21net_defaultresults,%ESCVP21net_EB2250result);
    main::Log3 $name, 5, "[$name]: setTypeCmds: loaded EB2250 sets and result";
  }
  elsif ($hash->{model} eq "TW6100"){
    %ESCVP21net_typesets = (%ESCVP21net_defaultsets,%ESCVP21net_TW6100sets, %VP21addattrs);
    %ESCVP21net_typeresults = (%ESCVP21net_defaultresults,%ESCVP21net_TW6100result);
    main::Log3 $name, 5, "[$name]: setTypeCmds: loaded TW6100 sets and result";
  } 
  elsif ($hash->{model} eq "TW7400"){
    %ESCVP21net_typesets = (%ESCVP21net_defaultsets,%ESCVP21net_TW7400sets, %VP21addattrs);
    %ESCVP21net_typeresults = (%ESCVP21net_defaultresults,%ESCVP21net_TW7400result);
    main::Log3 $name, 5, "[$name]: setTypeCmds: loaded TW7400 sets and result";
  }
  elsif ($hash->{model} eq "TW9400"){
    %ESCVP21net_typesets = (%ESCVP21net_defaultsets,%ESCVP21net_TW9400sets, %VP21addattrs);
    %ESCVP21net_typeresults = (%ESCVP21net_defaultresults,%ESCVP21net_TW9400result);
    main::Log3 $name, 5, "[$name]: setTypeCmds: loaded TW9400 sets and result";
  }  
  elsif ($hash->{model} eq "LS12000"){
    %ESCVP21net_typesets = (%ESCVP21net_defaultsets,%ESCVP21net_LS12000sets, %VP21addattrs);
    %ESCVP21net_typeresults = (%ESCVP21net_defaultresults,%ESCVP21net_LS12000result);
    main::Log3 $name, 5, "[$name]: setTypeCmds: loaded LS12000 sets and result";
  }  
  elsif ($hash->{model} eq "Scotty"){
    %ESCVP21net_typesets = (%ESCVP21net_defaultsets,%ESCVP21net_Scottysets, %VP21addattrs);
    %ESCVP21net_typeresults = (%ESCVP21net_defaultresults,%ESCVP21net_Scottyresult);
    main::Log3 $name, 5, "[$name]: setTypeCmds: loaded Scotty sets and result";
  }  
  else{
    %ESCVP21net_typesets = (%ESCVP21net_defaultsets, %VP21addattrs);
    %ESCVP21net_typeresults = (%ESCVP21net_defaultresults);
    main::Log3 $name, 5, "[$name]: setTypeCmds: loaded default sets and result";    
  }
  #if (AttrVal( $name, "debug", "0" ) eq "1"){
  if (defined($hash->{debug})){
    %ESCVP21net_typesets = (%ESCVP21net_typesets, %ESCVP21net_debugsets);
    main::Log3 $name, 5, "[$name]: setTypeCmds: added debug sets";
  } 
  # store sets and results in hash's invisible readings
  readingsSingleUpdate( $hash, ".Sets", encode_json( \%ESCVP21net_typesets ), 1 );
  readingsSingleUpdate( $hash, ".Results", encode_json( \%ESCVP21net_typeresults ), 1 );  
}

sub ESCVP21net_rescheduleSet($){
   # set command give too fast or toggle required, will be buffered and rescheduled
   my ($arg) = @_;
   my ( $name, $cmd, $result ) = split( "\\|", $arg );
   my $hash = $defs{$name};

   main::Log3 $name, 5, "[$name]: rescheduleSet: got arg: $arg, hash: $hash, cmd: $cmd, result: $result";
   RemoveInternalTimer($arg, "ESCVP21net_rescheduleSet");
   ESCVP21net_Set($hash, $name, $cmd, $result);
   main::Log3 $name, 5, "[$name]: rescheduleSet: send rescheduled command $cmd $result";
}

sub ESCVP21net_scheduleToggle($){
   # set command for toggle required
   my ($arg) = @_;
   my ( $name, $cmd, $result ) = split( "\\|", $arg );
   my $hash = $defs{$name};

   main::Log3 $name, 5, "[$name]: scheduleToggle: got arg: $arg, hash: $hash, cmd: $cmd, result: $result";
   RemoveInternalTimer($arg, "ESCVP21net_rescheduleSet");
   ESCVP21net_Set($hash, $name, $cmd, $result);
   main::Log3 $name, 5, "[$name]: scheduleToggle: send rescheduled command $cmd $result";
}

sub ESCVP21net_restoreJson {
  my ($hash, $reading) = @_;
  my $name = $hash->{NAME};
  my $jsets = ReadingsVal($name, $reading, "{none:none}");
  my $decode = decode_json($jsets);
  # just for logging
  #my %decode = %$decode;
  #main::Log3 $name, 5, "[$name]: restore: ". keys(%decode);
  return %$decode;
}

sub ESCVP21net_cleanup {
  my ($hash) = @_;
  my $name = $hash->{NAME};  
  RemoveInternalTimer($hash);
  DevIo_CloseDev($hash);
  BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined( $hash->{helper}{RUNNING_PID} ) );
  delete $hash->{helper}{nextConnectionCheck} if ( defined( $hash->{helper}{nextConnectionCheck} ) );
  delete $hash->{helper}{nextStatusCheck} if ( defined( $hash->{helper}{nextStatusCheck} ) );
  main::Log3 $name, 5, "[$name]: cleanup: deleting timers & RUNNING_PID, close Device";
  return ;  
}

sub ESCVP21net_connect{
  my ($hash) = @_;
  my $name = $hash->{NAME};  
  # clean up
  RemoveInternalTimer($hash, "ESCVP21net_checkConnection");
  DevIo_CloseDev($hash) if(DevIo_IsOpen($hash));
  
  # force immediate reconnect
  delete $hash->{NEXT_OPEN} if ( defined( $hash->{NEXT_OPEN} ) );
  DevIo_OpenDev($hash, 0, "ESCVP21net_Init", "ESCVP21net_Callback");
  main::Log3 $name, 5, "[$name]: connect: opening device via Dev_Io";
  return ;
}

sub ESCVP21net_cyclicConnect{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  main::Log3 $name, 5, "[$name]: cyclicConnect: cyclic reconnect...";
  
  RemoveInternalTimer($hash, "ESCVP21net_cyclicConnect");
  #delete $hash->{helper}{nextCyclicConnect} if (defined($hash->{helper}{nextCyclicConnect}));

  my $checkInterval = AttrVal( $name, "cyclicConnect", "3600" );
  
  if ($checkInterval eq "off"){
    $hash->{helper}{nextCyclicConnect} = "off";
    return ;
  }

  ESCVP21net_connect($hash);
  my $next = gettimeofday() + $checkInterval; # if checkInterval is off, we won't reach this line
  $hash->{helper}{nextCyclicConnect} = $next;
  InternalTimer( $next, "ESCVP21net_cyclicConnect", $hash);
}

sub ESCVP21net_removeTimer{
  my ($hash) = @_;
  my $name = $hash->{NAME};  
  RemoveInternalTimer($hash, "ESCVP21net_checkConnection");
  main::Log3 $name, 5, "[$name]: (debug): removeTimer";
  return ;
}

sub ESCVP21net_closeDevice{
  my ($hash) = @_;
  my $name = $hash->{NAME};  
  DevIo_CloseDev($hash) if(DevIo_IsOpen($hash));
  main::Log3 $name, 5, "[$name]: (debug): closeDevice";
  return ;
}

sub ESCVP21net_deleteNextOpen{
  my ($hash) = @_;
  my $name = $hash->{NAME};  
  delete $hash->{NEXT_OPEN} if ( defined( $hash->{NEXT_OPEN} ) );
  main::Log3 $name, 5, "[$name]: (debug): deleteNextOpen";
  return ;
}

sub ESCVP21net_openDevice{
  my ($hash) = @_;
  my $name = $hash->{NAME};  
  DevIo_OpenDev($hash, 0, "ESCVP21net_Init", "ESCVP21net_Callback");
  main::Log3 $name, 5, "[$name]: (debug): openDevice";
  return ;
}

###################################################
#                   done                          #
###################################################

1;

=pod
=item summary    control Epson Projector by VP21/VP.net via (W)Lan
=item summary_DE Steuerung von Epson Beamern mittels VP21/VP.net über (W)Lan
=begin html

<a id="ESCVP21net"></a>
<h3>ESCVP21net</h3>

<ul>
  <br><i>ESCVP21net</i> implements Epson VP21 control via (W)LAN, uses VP.net.
  <br>Attention: To be able to switch the projector power on via (W)LAN, you have to enable wireless/LAN standby mode (or whatever it is called in your projector menu), so that the projector does NOT deactivate the (W)LAN in standby mode!
  <br><br>
  <a id="ESCVP21net-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ESCVP21net &lt;IP_Address&gt [&lt;port&gt;] [&lt;model&gt;]</code>
    <br>
    <br>This module controls Epson Seiko Devices via TCP, using VP.net and ESC/VP21 commands.
    <br>For the time being, only Epson initilization is implemented (needs a special initialization string "ESC/VP.net").
    <br><br>
    <ul>
      <li><b>IP_Address</b> - the IP Address of the projector
      </li>
      <li><b>port</b> - ... guess? Yes, the port. If not given, Epson standard port 3629 is used.
      </li>
      <li><b>model</b> - defines your type of projector. It is used for loading a suitable pre-defined command set.
        <br>No parameter or <i>default</i> will provide you with a limit "set" (PWR, MUTE, LAMP, KEY, GetAll, GetStatus).
        <br>You can try <i>TW5650</i> to get a typical set of implemented commands. Providing the maintainer with a suitable set for your projector will extend the module's capabilities ;-)
        <br>Individually supported by now: TW5650, EB2250U, TW6100, TW7400, TW9400
        <br>"Hidden Feature:" Type <i>Scotty</i> will give you everything (as he does always ;) ). Not every command will work for you. You are the Captain, so decide wisely what to choose...
      </li>
      <li>Example: <code>define EPSON ESCVP21net 10.10.0.1 3629 TW5650</code>
      </li>
    </ul>      
  </ul>
  <br>

  <a id="ESCVP21net-set"></a>
  <b>Set</b>
  <br>
  <ul>
    <br>Available <b>set</b> commands depend on your model, see above.
    <br>For the predefined commands, "nice" names will be shown in the readings, e.g. for PWR: <b>Standby (Net on)</b> instead of the boring <b>PWR=04</b> (which is the device's answer if the projector is in Standby with LAN on).
    <br>Default set commands are
    <br><br>
    <li>PWR
      <br><i>on</i> or <i>off</i> to switch power, <i>get</i> to query current value
    </li>
    <br>
    <li>MUTE
      <br><i>on</i> or <i>off</i> to mute video signal (i.e. blank screen), <i>get</i> to query current state
    </li>
    <br>
    <li>LAMP
      <br><i>get</i> to query lamp hours
    </li>
    <br>
    <li>KEY
      <br>sends the value you enter to the projector.
      <br>E.g.<i>KEY 03</i> should open the OSD menu, <i>KEY 05</i> should close it.
    </li>
    <br>
    <li>GetAll
      <br>This is a little bit special - it does not send just one command to the projector, but will select <b>every</b> command defined which has a <b>get</b> option, send it to the projector and update the corresponding reading. If a command gives no result or an error, this will be suppressed, the old value is silently kept.
      <br>The status of GetAll is shown in the <b>GetAll</b> reading. It will either show the read commands, or inform if an error was received.
    </li>
    <br>
    <li>GetStatus
      <br>Also special - also does not send just one command to the projector, but will select <b>every</b> command you defined in attr "statusCheckCmd" which has a <b>get</b> option, send it to the projector and update the corresponding reading. If a command gives no result or an error, this will be suppressed, the old value is silently kept.
      <br>The status of GetStatus is shown in the <b>GetStatus</b> reading. It will either show the read commands, or inform if an error was received.
    </li>    
  </ul>
  <br>

  <a id="ESCVP21net-attr"></a>
  <b>Attributes</b>
  <br>
  <ul>
    <li>Manufacturer
      <br><i>Epson|default</i> - is not used currently.
    </li>
    <br>
    <li>AdditionalSettings
      <br><i>cmd1:val_1,...,val_n cmd2:val_1,...,val_n</i>
      <br>You can specify own set commands here, they will be added to the <b>set</b> list.
      <br>Multiple own sets can be specified, separated by a blank.
      <br>command and values are separated by <b>":"</b>, values are separated by <b>","</b>.
      <br>Example: <i>ASPECT:get,10,20,30 SN:noArg</i>
      <br>Each command with <i>get</i> will we queried when unsing <i>set &lt;name&gt; GetAll</i> 
    </li>
    <br>
    <li>connectionCheck
      <br><i>off|(value in seconds)</i>
      <br><i>value</i> defines the intervall in seconds to perform an connection check. This is useful, since the standard connection handling of fhem (DevIo) will not detect an broken TCP connection, so the state <b>disconnected</b> will only trigger after TCP timeout (60-90 minutes). If you are ok with this, just set it to <i>off</i>.
      <br>Default value is 60 seconds.
    </li>
    <br>            
    <li>statusCheckIntervall
      <br><i>off|(value in seconds)</i>
      <br><i>value</i> defines the intervall in seconds to perform an status check. Each <i>interval</i> the projector is queried with the command defined by <i>statusCheckCmd</i> (default: PWR to get power status).
      <br>Default value is 60 seconds.
    </li>
    <br>
    <li>statusCheckCmd
      <br><i>(any command(s) you set)</i>
      <br>Defines the command(s) used by statusCheckIntervall. Multiple commands can specified, e.g. <i>PWR LAMP</i>. Default: PWR to get power status.
      <br>Wrong commands or commands without a <i>get</i> will be ignored.
    </li>
    <br>            
    <li>statusOfflineMsg
      <br><i>(any message text you set)</i>
      <br>Defines the message to set in the Reading related to <i>statusCheckCmd</i> when the device goes offline. Status of device will be checked after each <i>statusCheckIntervall</i> (default: 60s), querying the <i>statusCheckCmd</i> command (default: PWR), and if STATE is <i>disconnected</i> the Reading of <i>statusCheckCmd</i> will be set to this message. Default: offline.
    </li>
    <br>
    <li>cyclicReconnectg
      <br><i>off|(value in seconds)</i>
      <br><i>value</i> defines the intervall in seconds to perform an periodic reconnect. Each <i>interval</i> we try to re-open the TCP connectionto the projector. Implemented to work around DevIo not recognizing a server-side broken connection, which can lead to a unnecessary, however non-blocking, system load.
      <br>Default value is 3600 seconds.
    </li>
    <br>
    <li>debug
      <br>You won't need it. But ok, if you insist...
      <br>debug will reveal some more set commands, namely <i>encode, decode, reread</i>. They will store the currents sets and results in json format to hidden readings <i>(encode)</i> or restore them <i>(decode)</i>. <i>reread</i> will just restore the available set commands for your projector type in case they got "lost". Don't use the other debug commands - unnless you know what you do...
      <br>Default is 0, of course.
    </li>
  </ul>
</ul>
=end html
=cut
