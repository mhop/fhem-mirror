########################################################################################################################
# $Id$
#########################################################################################################################
#       49_SSCam.pm
#
#       (c) 2015-2018 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This Module can be used to operate Cameras defined in Synology Surveillance Station 7.0 or higher.
#       It's based on and uses Synology Surveillance Station API.
# 
#       This script is part of fhem.
#
#       Fhem is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 2 of the License, or
#       (at your option) any later version.
#
#       Fhem is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#########################################################################################################################
#  Versions History:
# 
# 5.2.0  14.06.2018    support longpoll refresh of SSCamSTRM-Devices
# 5.1.0  13.06.2018    more control elements (Start/Stop Recording, Take Snapshot) in func SSCam_StreamDev
#                      control of detaillink is moved to SSCamSTRM-device
# 5.0.1  12.06.2018    control of page refresh improved (for e.g. Floorplan,Dashboard)
# 5.0.0  11.06.2018    HLS Streaming, Buttons for Streaming-Devices, use of module SSCamSTRM for Streaming-Devices, 
#                      deletion of Streaming-devices if SSCam-device is deleted, some more improvements, minor bugfixes
# 4.3.0  27.05.2018    HLS preparation changed
# 4.2.0  22.05.2018    PTZ-Panel integrated to created StreamDevice
# 4.1.0  05.05.2018    use SYNO.SurveillanceStation.VideoStream instead of SYNO.SurveillanceStation.VideoStreaming,
#                      preparation for hls
# 4.0.0  01.05.2018    AudioStream possibility added
# 3.10.0 24.04.2018    CreateStreamDev added, new features lastrec_fw_MJPEG, lastrec_fw_MPEG4/H.264 added to 
#                      playback MPEG4/H.264 videos
# 3.9.2  21.04.2018    minor fixes
# 3.9.1  20.04.2018    Attribute ptzPanel_use, initial webcommands in DeviceOverview changed, minor fixes ptzPanel
# 3.9.0  17.04.2018    control panel & PTZcontrol weblink device for PTZ cams
# 3.8.4  06.04.2018    Internal MODEL changed to SVS or "CamVendor - CamModel" for Cams
# 3.8.3  05.04.2018    bugfix V3.8.2, $OpMode "Start" changed, composegallery changed
# 3.8.2  04.04.2018    $attr replaced by AttrVal, SSCam_wdpollcaminfo redesigned
# 3.8.1  04.04.2018    some codereview like new sub SSCam_jboolmap
# 3.8.0  03.04.2018    new reading PresetHome, setHome command, minor fixes
# 3.7.0  26.03.2018    minor details of setPreset changed, new command delPreset
# 3.6.0  25.03.2018    setPreset command, changed SSCam_wdpollcaminfo, SSCam_getcaminfoall
# 3.5.0  22.03.2018    new get command listPresets
# 3.4.0  21.03.2018    new commands startTracking, stopTracking
# 3.3.1  20.03.2018    new readings CapPTZObjTracking, CapPTZPresetNumber
# 3.3.0  25.02.2018    code review, API bug fix of runview lastrec, commandref revised (forum:#84953)
# 3.2.4  18.11.2017    fix bug don't retrieve SSCam_getptzlistpreset if cam is disabled
# 3.2.3  08.10.2017    set optimizeParams, get caminfo (simple), minor bugfix, commandref revised
# 3.2.2  03.10.2017    make functions ready to use "SYNO.SurveillanceStation.PTZ" version 5, minor fixes, commandref 
#                      revised
# 3.2.1  02.10.2017    change some "SYNO.SurveillanceStation.Camera" methods to version 9             
# 3.2.0  27.09.2017    new command get listLog, change to $hash->{HELPER}{".SNAPHASH"} for avoid huge "list"-report
# 3.1.0  26.09.2017    move extevent from CAM to SVS model, Reading PollState enhanced for CAM-Model, minor fixes
# 3.0.0  23.09.2017    Internal MODEL SVS or CAM -> distinguish/support Cams and SVS in different devices
#                      new comand get storedCredentials, commandref revised
# 2.9.0  20.09.2017    new function get homeModeState, minor fixes at simu_SVSversion, commandref revised
# 2.8.2  19.09.2017    some preparations for version 9 of API "SYNO.SurveillanceStation.Camera", SSCam_logout added to function
#                      get scanVirginirgin
# 2.8.1  17.09.2017    attr simu_SVSversion changed, $mjpegHttp quotes dependend if noQuotesForSID set, commandref revised
# 2.8.0  07.09.2017    Home Mode, commandref revised
# 2.7.1  28.08.2017    minor fixes
# 2.7.0  20.08.2017    bugfix if credentials not set, set maximum password lenth to 20
# 2.6.3  12.08.2017    get snapGallery can also be triggered by at or notify (better use than "set"), commandref revised
# 2.6.2  11.08.2017    set snapGallery can be triggered by at or notify
# 2.6.1  07.08.2017    some changes in composegallery if createSnapGallery used, room Snapshots changed to SnapGalllery
#                      commandref revised
# 2.6.0  06.08.2017    new command createSnapGallery
# 2.5.4  05.08.2017    analyze $hash->{CL} in SetFn bzw. GetFn, set snapGallery only if snapGalleryBoost=1 is set,
#                      some snapGallery improvements and fixes
# 2.5.3  02.08.2017    implement snapGallery as set-command
# 2.5.2  01.08.2017    get snapGallery with or without snapGalleryBoost (some more attributes for snapGallery)
# 2.5.1  31.07.2017    sub composegallery (no polling necessary)
# 2.5.0  31.07.2017    logtext revised, new get snapGallery command
# 2.4.1  29.07.2017    fix behavior of state when starting lastsnap_fw, fix "uninitialized value in pattern match (m//) 
#                      at ./FHEM/49_SSCam.pm line 2895"
# 2.4.0  28.07.2017    new set command runView lastsnap_fw, commandref revised, minor fixes
# 2.3.2  28.07.2017    code change of SSCam_getcaminfo (params of Internaltimer)
# 2.3.1  28.07.2017    code review creating log entries when pollnologging is set/unset
# 2.3.0  27.07.2017    new "get snapinfo" command, minor fixes
# 2.2.4  25.07.2017    avoid error "Operation Getptzlistpreset of Camera ... was not successful" if cam is disabled
# 2.2.3  30.06.2017    fix if SVSversion small "0", create events for "snap"
# 2.2.2  11.06.2017    bugfix SSCam_login, SSCam_login_return, 
#                      Forum: https://forum.fhem.de/index.php/topic,45671.msg646701.html#msg646701
# 2.2.1  15.05.2017    avoid FW_detailFn because of FW_deviceOverview is active (double streams in detailview if on)
# 2.2.0  10.05.2017    check if JSON module has been loaded successfully, DeviceOverview available, options of 
#                      runView changed image->live_fw, link->live_link, link_open->live_open, lastrec ->lastrec_fw,
#                      commandref revised
# 2.1.4  08.05.2017    commandref changed
# 2.1.3  05.05.2017    issue of operation error if CAMID is set and SID isn't valid, more login-errorcodes evaluation
# 2.1.2  04.05.2017    default login retries increased to 3
# 2.1.1  17.04.2017    SSCam_runliveview routine changed, {HELPER}{SID_STRM} deleted
# 2.1.0  12.04.2017    some codereview, getapisites cached, CAMID cached, rewrite logs from verbose 4 to 5,
#                      get scanVirgin, commandref replenished
# 2.0.0  10.04.2017    redesign login procedure, fix Reading SVSversion use SMALL version, new attr loginRetries
# 1.42   15.03.2017    SSCam_camop changed to get all cam id's and names
# 1.41   15.03.2017    minor bugfix of blank character in state "disabled" (row 3383)
# 1.40   21.01.2017    downgrade of API apicammaxver in SVS 8.0.0
# 1.39   20.01.2017    compatibility to SVS 8.0.0, Version in Internals, execute SSCam_getsvsinfo after set credentials
# 1.37   10.10.2016    bugfix Experimental keys on scalar is now forbidden (Perl >= 5.23)
#                      (Forum: #msg501709)
# 1.36   18.09.2016    bugfix of get presets, get patrols of zoom-cams without pan/tilt
# 1.35   17.09.2016    internal timer of start-routines optimized
# 1.34   15.09.2016    simu_SVSversion changed, added 407 errorcode message, external recording changed 
#                      for SVS 7.2
# 1.33   21.08.2016    function get stmUrlPath added, fit to new commandref style, attribute showStmInfoFull added
# 1.32.1 18.08.2016    empty event LastSnapId fixed
# 1.32   17.08.2016    Logging of verbose 4 changed
# 1.31   15.08.2016    Attr "noQuotesForSID" added, avoid possible 402 - permission denied problems 
#                      in some SVS/DS-combinations
# 1.30   15.08.2016    commandref revised, more v4 logging in special case 
# 1.29   02.07.2016    add regex for adaption SVS version, url call for "snap" changed 
# 1.28   30.06.2016    Attr "showPassInLog" added, per default no password will be shown in log 
# 1.27   29.06.2016    Attr "simu_SVSversion" added, sub login_nonbl changed, 
#                      sub camret_nonbl changed (getlistptzpreset) due to 7.2 problem
# 1.26.3 28.06.2016    Time::HiRes added
# 1.26.2 05.05.2016    change: get "snapfileinfo" will get back an Infomessage if Reading "LastSnapId" 
#                      isn't available
# 1.26.1 27.04.2016    bugfix module will not load due to Unknown warnings category 'experimental'
#                      when using an older perl version 
# 1.26   22.04.2016    Attribute "disable" to deactivate the module added
# 1.25   18.04.2016    motion detection parameters can be entered if  
#                      motion detection by camera or SVS is used
# 1.24   16.04.2016    behavior of "set ... on" changed, Attr "recextend" added
#                      please have a look at commandref and Wiki
#                      bugfix: setstate-warning if FHEM will restarted and SVS is not reachable
#                      (Forum: #308)
# 1.23.2 12.04.2016    code review, no functional changes
# 1.23.1 07.04.2016    command check for set cmd's don't work completely
# 1.23   02.04.2016    change to RemoveInternalTimer for functions
# 1.22   27.03.2016    bugfix "link_open" doesn't work after last update
# 1.21   23.03.2016    added "lastrec"," lastrec_open" to playback last recording 
# 1.20.3 19.03.2016    change: delay of InternalTimer(s) changed
#                      "ptzlistpresets" - "id" changed to "position" according to Synology-ticket
#                      run "SSCam_geteventlist" automatically after recording-stop
# 1.20.2 14.03.2016    change: routine "SSCam_initonboot" changed
# 1.20.1 12.03.2016    bugfix: default recordtime 15 s is used if attribute "rectime" is set to "0"
# 1.20   09.03.2016    command "extevent" added
# 1.19.3 07.03.2016    bugfix "uninitialized value $lastrecstarttime",
#                      "uninitialized value $lastrecstoptime",
#                      new attribute "videofolderMap"
# 1.19.2 06.03.2016    Reading "CamLastRec" added which contains Path/name
#                      of last recording
# 1.19.1 28.02.2016    enhanced command runView by option "link_open" to
#                      open a streamlink immediately
# 1.19   25.02.2016    functions for cam-livestream added
# 1.18.1 21.02.2016    fixed a problem that the state is "disable" instead of
#                      "disabled" if a camera is disabled and FHEM will be restarted
# 1.18   20.02.2016    function "get ... eventlist" added,
#                      Reading "CamEventNum" added which containes total number of
#                      camera events,
#                      change usage of reading "LastUpdateTime" 
# 1.17   19.02.2016    function "runPatrol" added that starts predefined patrols
#                      of PTZ-cameras,
#                      Reading "CamDetMotSc" added
# 1.16.1 17.02.2016    Reading "CamExposureControl" added
# 1.16   16.02.2016    set up of motion detection source now possible
# 1.15   15.02.2016    control of exposure mode day, night & auto is possible now
# 1.14   14.02.2016    The port in DEF-String is optional now,
#                      if not given, default port 5000 is used
# 1.13.2 13.02.2016    fixed a problem that manual updates using "getcaminfoall" are
#                      leading to additional pollingloops if polling is used,
#                      attribute "debugactivetoken" added for debugging-use 
# 1.13.1 12.02.2016    fixed a problem that a usersession won't be destroyed if a
#                      function couldn't be executed successfully
# 1.13                 feature for retrieval snapfilename added
# 1.12.1 09.02.2016    bugfix: "goAbsPTZ" may be unavailable on Windows-systems
# 1.12   08.02.2016    added function "move" for continuous PTZ action
# 1.11.1 07.02.2016    entries with loglevel "2" reviewed, changed to loglevel "3"
# 1.11   05.02.2016    added function "goPreset" and "goAbsPTZ" to control the move of PTZ lense
#                      to absolute positions
#                      refere to commandref or have a look in forum at: 
#                      http://forum.fhem.de/index.php/topic,45671.msg404275.html#msg404275 ,
#                      http://forum.fhem.de/index.php/topic,45671.msg404892.html#msg404892
# 1.10   02.02.2016    added function "svsinfo" to get informations about installed SVS-package,
#                      if Availability = " disconnected" then "state"-value will be "disconnected" too,
#                      saved Credentials were deleted from file if a device will be deleted
# 1.9.1  31.01.2016    a little bit code optimization
# 1.9    28.01.2016    fixed the problem a recording may still stay active if fhem
#                      will be restarted after a recording was triggered and
#                      the recordingtime wasn't be over,
#                      Enhancement of readings.
# 1.8    25.01.2016    changed define in order to remove credentials from string,
#                      added "set credentials" command to save username/password,
#                      added Attribute "session" to make login-session selectable,
#                      Note: You have to adapt your define-strings !!
#                      Refere to commandref or look in forum at: 
#                      http://forum.fhem.de/index.php/topic,45671.msg397449.html#msg397449
# 1.7    18.01.2016    Attribute "httptimeout" added
# 1.6    16.01.2016    Change the define-string related to rectime.
#                      Note: See all changes to rectime usage in commandref or here:
#                      http://forum.fhem.de/index.php/topic,45671.msg391664.html#msg391664
# 1.5.1  11.01.2016    Vars "USERNAME" and "RECTIME" removed from internals,
#                      Var (Internals) "SERVERNAME" changed to "SERVERADDR",
#                      minor change of Log messages,
#                      Note: use rereadcfg in order to activate the changes
# 1.5     04.01.2016   Function "Get" for creating Camera-Readings integrated,
#                      Attributs pollcaminfoall, pollnologging  added,
#                      Function for Polling Cam-Infos added.
# 1.4     23.12.2015   function "enable" and "disable" for SS-Cams added,
#                      changed timout of Http-calls to a higher value
# 1.3     19.12.2015   function "snap" for taking snapshots added,
#                      fixed a bug that functions may impact each other 
# 1.2     14.12.2015   improve usage of verbose-modes
# 1.1     13.12.2015   use of InternalTimer instead of fhem(sleep)
# 1.0     12.12.2015   changed completly to HttpUtils_NonblockingGet for calling websites nonblocking, 
#                      LWP is not needed anymore
#
#
# Definition: define <name> SSCam <camname> <ServerAddr> [ServerPort] 
# 
# Example of defining a Cam-device: define CamCP1 SSCAM Carport 192.168.2.20 [5000]
# Example of defining a SVS-device: define SDS1 SSCAM SVS 192.168.2.20 [5000]
#

package main;
              
eval "use JSON qw( decode_json );1;" or my $SScamMMDBI = "JSON";  # Debian: apt-get install libjson-perl
use Data::Dumper;                                                 # Perl Core module
use strict;                           
use warnings;
use MIME::Base64;
use Time::HiRes;
use HttpUtils;
# no if $] >= 5.017011, warnings => 'experimental';  

my $SSCamVersion = "5.2.0";

# Aufbau Errorcode-Hashes (siehe Surveillance Station Web API)
my %SSCam_errauthlist = (
  100 => "Unknown error",
  101 => "The account parameter is not specified",
  102 => "API does not exist",
  400 => "Invalid user or password",
  401 => "Guest or disabled account",
  402 => "Permission denied - DSM-Session: make sure user is member of Admin-group, SVS-Session: make sure SVS package is started, make sure FHEM-Server IP won't be blocked in DSM automated blocking list",
  403 => "One time password not specified",
  404 => "One time password authenticate failed",
  405 => "method not allowd - maybe the password is too long",
  407 => "Permission denied - make sure FHEM-Server IP won't be blocked in DSM automated blocking list",
);

my %SSCam_errlist = (
  100 => "Unknown error",
  101 => "Invalid parameters",
  102 => "API does not exist",
  103 => "Method does not exist",
  104 => "This API version is not supported",
  105 => "Insufficient user privilege",
  106 => "Connection time out",
  107 => "Multiple login detected",
  117 => "need manager rights in SurveillanceStation for operation",
  400 => "Execution failed",
  401 => "Parameter invalid",
  402 => "Camera disabled",
  403 => "Insufficient license",
  404 => "Codec activation failed",
  405 => "CMS server connection failed",
  407 => "CMS closed",
  410 => "Service is not enabled",
  412 => "Need to add license",
  413 => "Reach the maximum of platform",
  414 => "Some events not exist",
  415 => "message connect failed",
  417 => "Test Connection Error",
  418 => "Object is not exist",
  419 => "Visualstation name repetition",
  439 => "Too many items selected",
  502 => "Camera disconnected",
  600 => "Presetname and PresetID not found in Hash",
);

# Standardvariablen
my $SSCam_slim = 3;                          # default Anzahl der abzurufenden Schnappschüsse mit snapGallery
my $SSCAM_snum = "1,2,3,4,5,6,7,8,9,10";     # mögliche Anzahl der abzurufenden Schnappschüsse mit snapGallery

sub SSCam_Initialize($) {
 my ($hash) = @_;
 $hash->{DefFn}        = "SSCam_Define";
 $hash->{UndefFn}      = "SSCam_Undef";
 $hash->{DeleteFn}     = "SSCam_Delete"; 
 $hash->{SetFn}        = "SSCam_Set";
 $hash->{GetFn}        = "SSCam_Get";
 $hash->{AttrFn}       = "SSCam_Attr";
 # Aufrufe aus FHEMWEB
 $hash->{FW_summaryFn} = "SSCam_FWsummaryFn";
 $hash->{FW_detailFn}  = "SSCam_FWdetailFn";
 $hash->{FW_deviceOverview} = 1;
 
 $hash->{AttrList} =
         "disable:1,0 ".
         "httptimeout ".
         "htmlattr ".
         "livestreamprefix ".
		 "loginRetries:1,2,3,4,5,6,7,8,9,10 ".
         "videofolderMap ".
         "pollcaminfoall ".
		 "snapGalleryBoost:0,1 ".
		 "snapGallerySize:Icon,Full ".
		 "snapGalleryNumber:$SSCAM_snum ".
		 "snapGalleryColumns ".
		 "snapGalleryHtmlAttr ".
         "pollnologging:1,0 ".
         "debugactivetoken:1,0 ".
         "rectime ".
         "recextend:1,0 ".
         "noQuotesForSID:1,0 ".
         "session:SurveillanceStation,DSM ".
         "showPassInLog:1,0 ".
         "showStmInfoFull:1,0 ".
         "simu_SVSversion:7.2-xxxx,7.1-xxxx,8.0.0-xxxx ".
         "webCmd ".
         $readingFnAttributes;   
         
return undef;   
}

################################################################
sub SSCam_Define($@) {
  # Die Define-Funktion eines Moduls wird von Fhem aufgerufen wenn der Define-Befehl für ein Gerät ausgeführt wird 
  # Welche und wie viele Parameter akzeptiert werden ist Sache dieser Funktion. Die Werte werden nach dem übergebenen Hash in ein Array aufgeteilt
  # define CamCP1 SSCAM Carport 192.168.2.20 [5000] 
  #       ($hash)  [1]    [2]        [3]      [4]  
  #
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  
 return "Error: Perl module ".$SScamMMDBI." is missing. Install it on Debian with: sudo apt-get install libjson-perl" if($SScamMMDBI);
  
  my @a = split("[ \t][ \t]*", $def);
  
  if(int(@a) < 4) {
        return "You need to specify more parameters.\n". "Format: define <name> SSCAM <Cameraname> <ServerAddress> [Port]";
        }
        
  my $camname    = $a[2];
  my $serveraddr = $a[3];
  my $serverport = $a[4] ? $a[4] : 5000;
  
  $hash->{SERVERADDR} = $serveraddr;
  $hash->{SERVERPORT} = $serverport;
  $hash->{CAMNAME}    = $camname;
  $hash->{VERSION}    = $SSCamVersion;
  $hash->{MODEL}      = ($camname =~ m/^SVS$/i)?"SVS":"CAM";                     # initial, CAM wird später ersetzt durch CamModel
 
  # benötigte API's in $hash einfügen
  $hash->{HELPER}{APIINFO}        = "SYNO.API.Info";                             # Info-Seite für alle API's, einzige statische Seite !                                                    
  $hash->{HELPER}{APIAUTH}        = "SYNO.API.Auth";                             # API used to perform session login and logout
  $hash->{HELPER}{APISVSINFO}     = "SYNO.SurveillanceStation.Info"; 
  $hash->{HELPER}{APIEVENT}       = "SYNO.SurveillanceStation.Event"; 
  $hash->{HELPER}{APIEXTREC}      = "SYNO.SurveillanceStation.ExternalRecording"; 
  $hash->{HELPER}{APIEXTEVT}      = "SYNO.SurveillanceStation.ExternalEvent";
  $hash->{HELPER}{APICAM}         = "SYNO.SurveillanceStation.Camera";           # This API provides a set of methods to acquire camera-related information and to enable/disable cameras
  $hash->{HELPER}{APISNAPSHOT}    = "SYNO.SurveillanceStation.SnapShot";
  $hash->{HELPER}{APIPTZ}         = "SYNO.SurveillanceStation.PTZ";
  $hash->{HELPER}{APIPRESET}      = "SYNO.SurveillanceStation.PTZ.Preset";
  $hash->{HELPER}{APICAMEVENT}    = "SYNO.SurveillanceStation.Camera.Event";
  $hash->{HELPER}{APIVIDEOSTM}    = "SYNO.SurveillanceStation.VideoStreaming";   # wird verwendet in Response von "SYNO.SurveillanceStation.Camera: GetLiveViewPath" -> StreamKey-Methode
  $hash->{HELPER}{APISTM}         = "SYNO.SurveillanceStation.Streaming";        # This API provides methods to get Live View or Event video stream
  $hash->{HELPER}{APIHM}          = "SYNO.SurveillanceStation.HomeMode";
  $hash->{HELPER}{APILOG}         = "SYNO.SurveillanceStation.Log";
  $hash->{HELPER}{APIAUDIOSTM}    = "SYNO.SurveillanceStation.AudioStream";      # Audiostream mit SID
  $hash->{HELPER}{APIVIDEOSTMS}   = "SYNO.SurveillanceStation.VideoStream";      # Videostream mit SID
  
  # Startwerte setzen
  if(SSCam_IsModelCam($hash)) {
      $attr{$name}{webCmd}             = "on:off:snap:enable:disable:runView:stopView";  # initiale Webkommandos setzen
  } else {
      $attr{$name}{webCmd}             = "homeMode";
	  $attr{$name}{webCmdLabel}        = "HomeMode";
  }
  $hash->{HELPER}{ACTIVE}              = "off";                                  # Funktionstoken "off", Funktionen können sofort starten
  $hash->{HELPER}{OLDVALPOLLNOLOGGING} = "0";                                    # Loggingfunktion für Polling ist an
  $hash->{HELPER}{OLDVALPOLL}          = "0";  
  $hash->{HELPER}{RECTIME_DEF}         = "15";                                   # Standard für rectime setzen, überschreibbar durch Attribut "rectime" bzw. beim "set .. on-for-time"
  $hash->{HELPER}{OLDPTZHOME}          = "";
  $hash->{".ptzhtml"}                  = "";
  $hash->{HELPER}{HLSSTREAM}           = "inactive";                             # Aktivitätsstatus HLS-Streaming
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"PollState","Inactive");                              # es ist keine Gerätepolling aktiv
  if(SSCam_IsModelCam($hash)) {
      readingsBulkUpdate($hash,"Availability", "???");                           # Verfügbarkeit ist unbekannt
      readingsBulkUpdate($hash,"state", "off");                                  # Init für "state" , Problemlösung für setstate, Forum #308
  } else {
      readingsBulkUpdate($hash,"state", "Initialized");                          # Init für "state" wenn SVS  
  }
  readingsEndUpdate($hash,1);                                          
  
  SSCam_getcredentials($hash,1);                                                       # Credentials lesen und in RAM laden ($boot=1)      
  
  # initiale Routinen nach Restart ausführen   , verzögerter zufälliger Start
  RemoveInternalTimer($hash, "SSCam_initonboot");
  InternalTimer(gettimeofday()+int(rand(30)), "SSCam_initonboot", $hash, 0);

return undef;
}

################################################################
sub SSCam_Undef($$) {
    my ($hash, $arg) = @_;
    SSCam_logout($hash);
    RemoveInternalTimer($hash);
return undef;
}

################################################################
sub SSCam_Delete($$) {
    my ($hash, $arg) = @_;
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_credentials";
    my $name  = $hash->{NAME};
    
    # gespeicherte Credentials löschen
    setKeyValue($index, undef);
	
	# löschen snapGallerie-Device falls vorhanden
	my $sgdev = "SSCam.$hash->{NAME}.snapgallery";
    CommandDelete($hash->{CL},"$sgdev");
    
	# alle Streaming-Devices löschen falls vorhanden
    CommandDelete($hash->{CL},"TYPE=SSCamSTRM:FILTER=PARENT=$name");
    
return undef;
}

################################################################
sub SSCam_Attr($$$$) {
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};
    my ($do,$val);
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    
    # dynamisch PTZ-Attribute setzen (wichtig beim Start wenn Reading "DeviceType" nicht gesetzt ist)
    if ($cmd eq "set" && ($aName =~ m/ptzPanel_.*/)) {
        foreach my $n (0..9) { 
            $n = sprintf("%2.2d",$n);
            addToDevAttrList($name, "ptzPanel_row$n");
        }
        addToDevAttrList($name, "ptzPanel_iconPrefix");
        addToDevAttrList($name, "ptzPanel_iconPath");
    }
    
    if($aName =~ m/ptzPanel_row.*|ptzPanel_Home|ptzPanel_use/) {
        InternalTimer(gettimeofday()+0.7, "SSCam_addptzattr", "$name", 0);
    } 
    
    if ($aName eq "disable") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
		if(SSCam_IsModelCam($hash)) {
            $val = ($do == 1 ? "inactive" : "off");
		} else {
		    $val = ($do == 1 ? "disabled" : "initialized");
		}
    
        readingsSingleUpdate($hash, "state", $val, 1);
        readingsSingleUpdate($hash, "PollState", "Inactive", 1) if($do == 1);
        readingsSingleUpdate($hash, "Availability", "???", 1) if($do == 1 && SSCam_IsModelCam($hash));
    }
    
    if ($aName eq "showStmInfoFull") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");

        if ($do == 0) {
            delete($defs{$name}{READINGS}{StmKeymjpegHttp});
            delete($defs{$name}{READINGS}{StmKeyUnicst});
            delete($defs{$name}{READINGS}{LiveStreamUrl}); 	
			delete($defs{$name}{READINGS}{StmKeyUnicstOverHttp});			
        }
    }

    if ($aName eq "snapGallerySize") {
        if($cmd eq "set") {
            $do = ($aVal eq "Icon")?1:2;
        }
        $do = 0 if($cmd eq "del");

        if ($do == 0) {
            delete($hash->{HELPER}{".SNAPHASH"}) if(AttrVal($name,"snapGalleryBoost",0));  # Snaphash nur löschen wenn Snaps gepollt werden   
            Log3($name, 4, "$name - Snapshot hash deleted");
		} elsif (AttrVal($name,"snapGalleryBoost",0)) {
		    # snap-Infos abhängig ermitteln wenn gepollt werden soll
		    my ($slim,$ssize);
            $hash->{HELPER}{GETSNAPGALLERY} = 1;
		    $slim  = AttrVal($name,"snapGalleryNumber",$SSCam_slim);    # Anzahl der abzurufenden Snaps
			$ssize = $do;
			RemoveInternalTimer("SSCam_getsnapinfo"); 
			InternalTimer(gettimeofday()+0.7, "SSCam_getsnapinfo", "$name:$slim:$ssize", 0);
		}
    }     
	
    if ($aName eq "snapGalleryBoost") {
        if($cmd eq "set") {
            $do = ($aVal == 1)?1:0;
        }
        $do = 0 if($cmd eq "del");

        if ($do == 0) {
            delete($hash->{HELPER}{".SNAPHASH"});  # Snaphash löschen
            Log3($name, 4, "$name - Snapshot hash deleted");
		
		} else {
		    # snapgallery regelmäßig neu einlesen wenn Polling ein
			return "When you want activate \"snapGalleryBoost\", you have to set the attribute \"pollcaminfoall\" first because the functionality depends on retrieving snapshots periodical." 
		       if(!AttrVal($name,"pollcaminfoall",0));
			   
		    my ($slim,$ssize);
            $hash->{HELPER}{GETSNAPGALLERY} = 1;
		    $slim  = AttrVal($name,"snapGalleryNumber",$SSCam_slim); # Anzahl der abzurufenden Snaps
			my $sg = AttrVal($name,"snapGallerySize","Icon");        # Auflösung Image
			$ssize = ($sg eq "Icon")?1:2;
			RemoveInternalTimer("SSCam_getsnapinfo"); 
			InternalTimer(gettimeofday()+0.7, "SSCam_getsnapinfo", "$name:$slim:$ssize", 0);
		}
    } 
	
	if ($aName eq "snapGalleryNumber" && AttrVal($name,"snapGalleryBoost",0)) {
		my ($slim,$ssize);    
        if($cmd eq "set") {
            $do = ($aVal != 0)?1:0;
        }
        $do = 0 if($cmd eq "del");
		
        if ($do == 0) { 
		    $slim = 3;
		} else {
		    $slim = $aVal;
		}
        
		$hash->{HELPER}{GETSNAPGALLERY} = 1;
		my $sg = AttrVal($name,"snapGallerySize","Icon");  # Auflösung Image
		$ssize = ($sg eq "Icon")?1:2;
		RemoveInternalTimer("SSCam_getsnapinfo"); 
		InternalTimer(gettimeofday()+0.7, "SSCam_getsnapinfo", "$name:$slim:$ssize", 0);
	}
    
    if ($aName eq "simu_SVSversion") {
	    delete $hash->{HELPER}{APIPARSET};
	    delete $hash->{HELPER}{SID};
		delete $hash->{CAMID};
        RemoveInternalTimer($hash, "SSCam_getsvsinfo");
        InternalTimer(gettimeofday()+0.5, "SSCam_getsvsinfo", $hash, 0);
    }
    
    if($aName =~ m/pollcaminfoall/ && $init_done == 1) {
        RemoveInternalTimer($hash, "SSCam_getcaminfoall");
        InternalTimer(gettimeofday()+1.0, "SSCam_getcaminfoall", $hash, 0);
        RemoveInternalTimer($hash, "SSCam_wdpollcaminfo");
        InternalTimer(gettimeofday()+1.5, "SSCam_wdpollcaminfo", $hash, 0);
    }
    
    if($aName =~ m/pollnologging/ && $init_done == 1) {
        RemoveInternalTimer($hash, "SSCam_wdpollcaminfo");
        InternalTimer(gettimeofday()+1.0, "SSCam_wdpollcaminfo", $hash, 0);
    } 
                         
    if ($cmd eq "set") {
        if ($aName =~ m/httptimeout|snapGalleryColumns|rectime|pollcaminfoall/) {
            unless ($aVal =~ /^\d+$/) { return " The Value for $aName is not valid. Use only figures 1-9 !";}
        }
        if($aName =~ m/pollcaminfoall/) {
            return "The value of \"$aName\" has to be greater than 10 seconds." if($aVal <= 10);
        }         
    }

    if ($cmd eq "del") {
        if ($aName =~ m/pollcaminfoall/ ) {
		    # Polling nicht ausschalten wenn snapGalleryBoost ein (regelmäßig neu einlesen)
			return "Please switch off \"snapGalleryBoost\" first if you want to deactivate \"pollcaminfoall\" because the functionality of \"snapGalleryBoost\" depends on retrieving snapshots periodical." 
		       if(AttrVal($name,"snapGalleryBoost",0));
        }       
    }

return undef;
}

################################################################
sub SSCam_Set($@) {
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name    = $a[0];
  my $opt     = $a[1];
  my $prop    = $a[2];
  my $prop1   = $a[3];
  my $prop2   = $a[4];
  my $prop3   = $a[5];
  my $camname = $hash->{CAMNAME}; 
  my $success;
  my $setlist;
  my @prop;
        
  return "module is deactivated" if(IsDisabled($name));
 
  if(SSCam_IsModelCam($hash)) {
      # selist für Cams
      my $hlslfw = (ReadingsVal($name,"CamStreamFormat","MJPEG") eq "HLS")?",live_fw_hls,":",";
      $setlist = "Unknown argument $opt, choose one of ".
                 "credentials ".
                 ((ReadingsVal("$name", "CapPTZPan", "false") ne "false") ? "delPreset:".ReadingsVal("$name","Presets","")." " : "").
                 "expmode:auto,day,night ".
                 "on ".
                 "off:noArg ".
                 "motdetsc:disable,camera,SVS ".
                 "snap:noArg ".
	     		 (AttrVal($name, "snapGalleryBoost",0)?(AttrVal($name,"snapGalleryNumber",undef) || AttrVal($name,"snapGalleryBoost",0))?"snapGallery:noArg ":"snapGallery:$SSCAM_snum ":" ").
	     		 "createSnapGallery:noArg ".
                 "createStreamDev:mjpeg,switched ".
                 ((ReadingsVal("$name", "CapPTZPan", "false") ne "false") ? "createPTZcontrol:noArg ": "").
                 "enable:noArg ".
                 "disable:noArg ".
				 "optimizeParams ".
                 "runView:live_fw".$hlslfw."live_link,live_open,lastrec_fw,lastrec_fw_MJPEG,lastrec_fw_MPEG4/H.264,lastrec_open,lastsnap_fw ".
                 ((ReadingsVal("$name", "CapPTZPan", "false") ne "false") ? "setPreset ": "").
                 ((ReadingsVal("$name", "CapPTZPan", "false") ne "false") ? "setHome:---currentPosition---,".ReadingsVal("$name","Presets","")." " : "").
                 "stopView:noArg ".
                 ((ReadingsVal("$name", "CapPTZObjTracking", "false") ne "false") ? "startTracking:noArg " : "").
                 ((ReadingsVal("$name", "CapPTZObjTracking", "false") ne "false") ? "stopTracking:noArg " : "").
                 ((ReadingsVal("$name", "CapPTZDirections", 0) > 0) ? "move"." " : "").
                 ((ReadingsVal("$name", "CapPTZPan", "false") ne "false") ? "runPatrol:".ReadingsVal("$name", "Patrols", "")." " : "").
                 ((ReadingsVal("$name", "CapPTZPan", "false") ne "false") ? "goPreset:".ReadingsVal("$name", "Presets", "")." " : "").
                 (ReadingsVal("$name", "CapPTZAbs", 0) ? "goAbsPTZ"." " : ""). 
                 ((ReadingsVal("$name", "CapPTZDirections", 0) > 0) ? "move"." " : "");
  } else {
      # setlist für SVS Devices
      $setlist = "Unknown argument $opt, choose one of ".
	             "credentials ".
				 "extevent:1,2,3,4,5,6,7,8,9,10 ".
		     	 ($hash->{HELPER}{APIHMMAXVER}?"homeMode:on,off ": "");
  }         

  if ($opt eq "on" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
            
      if (defined($prop)) {
          unless ($prop =~ /^\d+$/) { return " The Value for \"$opt\" is not valid. Use only figures 0-9 without decimal places !";}
          $hash->{HELPER}{RECTIME_TEMP} = $prop;
      }
      SSCam_camstartrec($hash);
 
  } elsif ($opt eq "off" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      SSCam_camstoprec($hash);
        
  } elsif ($opt eq "snap" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      SSCam_camsnap($hash);
        
  } elsif ($opt eq "startTracking" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      if ($hash->{HELPER}{APIPTZMAXVER} < 5)  {return "Function \"$opt\" needs a higher version of Surveillance Station";}
      SSCam_starttrack($hash);
        
  } elsif ($opt eq "stopTracking" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      if ($hash->{HELPER}{APIPTZMAXVER} < 5)  {return "Function \"$opt\" needs a higher version of Surveillance Station";}
      SSCam_stoptrack($hash);
        
  } elsif ($opt eq "snapGallery" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      my $ret = SSCam_getclhash($hash);
      return $ret if($ret);
  
	  if(!AttrVal($name, "snapGalleryBoost",0)) {
	      # Snaphash ist nicht vorhanden und wird neu abgerufen und ausgegeben
		  $hash->{HELPER}{GETSNAPGALLERY} = 1;
        
		  # snap-Infos für Gallerie abrufen
		  my ($sg,$slim,$ssize); 
		  $slim  = $prop?AttrVal($name,"snapGalleryNumber",$prop):AttrVal($name,"snapGalleryNumber",$SSCam_slim);  # Anzahl der abzurufenden Snapshots
		  $ssize = (AttrVal($name,"snapGallerySize","Icon") eq "Icon")?1:2;                                        # Image Size 1-Icon, 2-Full		
        
		  SSCam_getsnapinfo("$name:$slim:$ssize");
		
      } else {
		  # Snaphash ist vorhanden und wird zur Ausgabe aufbereitet (Polling ist aktiv)
		  my $htmlCode = composegallery($name);
		  for (my $k=1; (defined($hash->{HELPER}{CL}{$k})); $k++ ) {
		      if ($hash->{HELPER}{CL}{$k}->{COMP}) {
		          # CL zusammengestellt (Auslösung durch Notify)
		          asyncOutput($hash->{HELPER}{CL}{$k}, "$htmlCode");						
		      } else {
			      # Output wurde über FHEMWEB ausgelöst
		          return $htmlCode;
		      }
		  }
		  delete($hash->{HELPER}{CL});
	  }
	  
  } elsif ($opt eq "createSnapGallery" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      my ($ret,$sgdev);
      return "Before use \"$opt\" you have to set the attribute \"snapGalleryBoost\" first due to the technology of retrieving snapshots automatically is needed." 
		       if(!AttrVal($name,"snapGalleryBoost",0));
	  $sgdev = "SSCamSTRM.$name.snapgallery";
      $ret = CommandDefine($hash->{CL},"$sgdev SSCamSTRM {composegallery('$name','$sgdev','snapgallery')}");
	  return $ret if($ret);
	  my $room = "SnapGallery";
      $attr{$sgdev}{room}  = $room;
	  return "Snapgallery device \"$sgdev\" created and assigned to room \"$room\".";
      
  } elsif ($opt eq "createPTZcontrol" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
	  my $ptzcdev = "SSCamSTRM.$name.PTZcontrol";
      my $ret     = CommandDefine($hash->{CL},"$ptzcdev SSCamSTRM {SSCam_ptzpanel('$name','$ptzcdev','ptzcontrol')}");
	  return $ret if($ret);
	  my $room    = AttrVal($name,"room","PTZcontrol");
      $attr{$ptzcdev}{room}  = $room;
      $attr{$ptzcdev}{group} = $name."_PTZcontrol";
	  return "PTZ control device \"$ptzcdev\" created and assigned to room \"$room\".";
  
  } elsif ($opt eq "createStreamDev" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
	  my ($livedev,$ret);
      
      if($prop =~ /mjpeg/) {
          $livedev = "SSCamSTRM.$name.mjpeg";
          $ret = CommandDefine($hash->{CL},"$livedev SSCamSTRM {SSCam_StreamDev('$name','$livedev','mjpeg')}");
	      return $ret if($ret);
      }
      if($prop =~ /switched/) {
          $livedev = "SSCamSTRM.$name.switched";
          $ret = CommandDefine($hash->{CL},"$livedev SSCamSTRM {SSCam_StreamDev('$name','$livedev','switched')}");
	      return $ret if($ret);
      }
      
	  my $room = AttrVal($name,"room","Livestream");
      $attr{$livedev}{room}  = $room;
	  return "Livestream device \"$livedev\" created and assigned to room \"$room\".";
  
  } elsif ($opt eq "enable" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      SSCam_camenable($hash);
        
  } elsif ($opt eq "disable" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      SSCam_camdisable($hash);
       
  } elsif ($opt eq "motdetsc" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      if (!$prop || $prop !~ /^(disable|camera|SVS)$/) { return " \"$opt\" needs one of those arguments: disable, camera, SVS !";}
            
      $hash->{HELPER}{MOTDETSC} = $prop;
            
      if ($prop1) {
          # check ob Zahl zwischen 1 und 99
          return "invalid value for sensitivity (SVS or camera) - use number between 1 - 99" if ($prop1 !~ /^([1-9]|[1-9][0-9])*$/);
          $hash->{HELPER}{MOTDETSC_PROP1} = $prop1;
      }
      if ($prop2) {
          # check ob Zahl zwischen 1 und 99
          return "invalid value for threshold (SVS) / object size (camera) - use number between 1 - 99" if ($prop2 !~ /^([1-9]|[1-9][0-9])*$/);
          $hash->{HELPER}{MOTDETSC_PROP2} = $prop2;
      }
      if ($prop3) {
          # check ob Zahl zwischen 1 und 99
          return "invalid value for threshold (SVS) / object size (camera) - use number between 1 - 99" if ($prop3 !~ /^([1-9]|[1-9][0-9])*$/);
          $hash->{HELPER}{MOTDETSC_PROP3} = $prop3;
      }
      SSCam_cammotdetsc($hash);
        
  } elsif ($opt eq "credentials") {
      return "Credentials are incomplete, use username password" if (!$prop || !$prop1);
	  return "Password is too long. It is limited up to and including 20 characters." if (length $prop1 > 20);
      delete $hash->{HELPER}{SID} if($hash->{HELPER}{SID});          
      ($success) = SSCam_setcredentials($hash,$prop,$prop1);
      $hash->{HELPER}{ACTIVE} = "off";  
	  
	  if($success) {
	      SSCam_getcaminfoall($hash,0);
          RemoveInternalTimer($hash, "SSCam_getptzlistpreset");
          InternalTimer(gettimeofday()+11, "SSCam_getptzlistpreset", $hash, 0);
          RemoveInternalTimer($hash, "SSCam_getptzlistpatrol");
          InternalTimer(gettimeofday()+12, "SSCam_getptzlistpatrol", $hash, 0);
		  return "Username and Password saved successfully";
	  } else {
		   return "Error while saving Username / Password - see logfile for details";
	  }
			
  } elsif ($opt eq "expmode" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      unless ($prop) { return " \"$opt\" needs one of those arguments: auto, day, night !";}
            
      $hash->{HELPER}{EXPMODE} = $prop;
      SSCam_camexpmode($hash);
        
  } elsif ($opt eq "homeMode" && !SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      unless ($prop) { return " \"$opt\" needs one of those arguments: on, off !";}
            
      $hash->{HELPER}{HOMEMODE} = $prop;
      SSCam_sethomemode($hash);
        
  } elsif ($opt eq "goPreset" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      if (!$prop) {return "Function \"goPreset\" needs a \"Presetname\" as an argument";}
            
      $hash->{HELPER}{GOPRESETNAME} = $prop;
      $hash->{HELPER}{PTZACTION}    = "gopreset";
      SSCam_doptzaction($hash);
        
  } elsif ($opt eq "optimizeParams" && SSCam_IsModelCam($hash)) {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
		
		my %cpcl = (ntp => 1, mirror => 2, flip => 4, rotate => 8);
		SSCam_extoptpar($hash,$prop,\%cpcl) if($prop);
        SSCam_extoptpar($hash,$prop1,\%cpcl) if($prop1);
        SSCam_extoptpar($hash,$prop2,\%cpcl) if($prop2);
		SSCam_setoptpar($hash);
                
  } elsif ($opt eq "runPatrol" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      if (!$prop) {return "Function \"runPatrol\" needs a \"Patrolname\" as an argument";}
            
      $hash->{HELPER}{GOPATROLNAME} = $prop;
      $hash->{HELPER}{PTZACTION}    = "runpatrol";
      SSCam_doptzaction($hash);
        
  } elsif ($opt eq "goAbsPTZ" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}

      if ($prop eq "up" || $prop eq "down" || $prop eq "left" || $prop eq "right") {
          if ($prop eq "up")    {$hash->{HELPER}{GOPTZPOSX} = 320; $hash->{HELPER}{GOPTZPOSY} = 480;}
          if ($prop eq "down")  {$hash->{HELPER}{GOPTZPOSX} = 320; $hash->{HELPER}{GOPTZPOSY} = 0;}
          if ($prop eq "left")  {$hash->{HELPER}{GOPTZPOSX} = 0; $hash->{HELPER}{GOPTZPOSY} = 240;}    
          if ($prop eq "right") {$hash->{HELPER}{GOPTZPOSX} = 640; $hash->{HELPER}{GOPTZPOSY} = 240;} 
                
          $hash->{HELPER}{PTZACTION} = "goabsptz";
          SSCam_doptzaction($hash);
          return undef;
            
	  } else {
          if ($prop !~ /\d+/ || $prop1 !~ /\d+/ || abs($prop) > 640 || abs($prop1) > 480) {
              return "Function \"goAbsPTZ\" needs two coordinates, posX=0-640 and posY=0-480, as arguments or use up, down, left, right instead";
          }
                
          $hash->{HELPER}{GOPTZPOSX} = abs($prop);
          $hash->{HELPER}{GOPTZPOSY} = abs($prop1);
                
          $hash->{HELPER}{PTZACTION}  = "goabsptz";
          SSCam_doptzaction($hash);
                
          return undef;     
      } 
      return "Function \"goAbsPTZ\" needs two coordinates, posX=0-640 and posY=0-480, as arguments or use up, down, left, right instead";

  } elsif ($opt eq "move" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      
	  return "PTZ version of Synology API isn't set. Use \"get $name scanVirgin\" first." if(!$hash->{HELPER}{APIPTZMAXVER});
      
	  if($hash->{HELPER}{APIPTZMAXVER} <= 4) {
	      if (!defined($prop) || ($prop !~ /^up$|^down$|^left$|^right$|^dir_\d$/)) {return "Function \"move\" needs an argument like up, down, left, right or dir_X (X = 0 to CapPTZDirections-1)";}
	      $hash->{HELPER}{GOMOVEDIR} = $prop;
	  
	  } elsif ($hash->{HELPER}{APIPTZMAXVER} >= 5) {
	      if (!defined($prop) || ($prop !~ /^right$|^upright$|^up$|^upleft$|^left$|^downleft$|^down$|^downright$/)) {return "Function \"move\" needs an argument like right, upright, up, upleft, left, downleft, down, downright ";}
	      my %dirs = (
		              right     => 0,
                      upright   => 4,
                      up        => 8,
                      upleft    => 12,
                      left      => 16,
                      downleft  => 20,
                      down      => 24,
                      downright => 28,
		             );
		  $hash->{HELPER}{GOMOVEDIR} = $dirs{$prop};
	  }
	  
      $hash->{HELPER}{GOMOVETIME} = defined($prop1) ? $prop1 : 1;
            
      $hash->{HELPER}{PTZACTION}  = "movestart";
      SSCam_doptzaction($hash);
        
  } elsif ($opt eq "runView" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}

      if ($prop eq "live_open") {
          if ($prop1) {$hash->{HELPER}{VIEWOPENROOM} = $prop1;} else {delete $hash->{HELPER}{VIEWOPENROOM};}
          $hash->{HELPER}{OPENWINDOW} = 1;
          $hash->{HELPER}{WLTYPE}     = "link";    
		  $hash->{HELPER}{ALIAS}      = "LiveView";
		  $hash->{HELPER}{RUNVIEW}    = "live_open";				
      } elsif ($prop eq "live_link") {
          $hash->{HELPER}{OPENWINDOW} = 0;
          $hash->{HELPER}{WLTYPE}     = "link"; 
		  $hash->{HELPER}{ALIAS}      = "LiveView";
		  $hash->{HELPER}{RUNVIEW}    = "live_link";
      } elsif ($prop eq "lastrec_open") {
          if ($prop1) {$hash->{HELPER}{VIEWOPENROOM} = $prop1;} else {delete $hash->{HELPER}{VIEWOPENROOM};}
          $hash->{HELPER}{OPENWINDOW} = 1;
          $hash->{HELPER}{WLTYPE}     = "link"; 
	      $hash->{HELPER}{ALIAS}      = "LastRecording";
		  $hash->{HELPER}{RUNVIEW}    = "lastrec_open";
      }  elsif ($prop eq "lastrec_fw") {                     # Video in iFrame eingebettet
          $hash->{HELPER}{OPENWINDOW} = 0;
          $hash->{HELPER}{WLTYPE}     = "iframe"; 
	      $hash->{HELPER}{ALIAS}      = " ";
		  $hash->{HELPER}{RUNVIEW}    = "lastrec";
      } elsif ($prop eq "lastrec_fw_MJPEG") {                # “video/avi” – MJPEG format event
          $hash->{HELPER}{OPENWINDOW} = 0;
          $hash->{HELPER}{WLTYPE}     = "image"; 
	      $hash->{HELPER}{ALIAS}      = " ";
		  $hash->{HELPER}{RUNVIEW}    = "lastrec";
      } elsif ($prop eq "lastrec_fw_MPEG4/H.264") {          # “video/mp4” – MPEG4/H.264 format event
          $hash->{HELPER}{OPENWINDOW} = 0;
          $hash->{HELPER}{WLTYPE}     = "video"; 
	      $hash->{HELPER}{ALIAS}      = " ";
		  $hash->{HELPER}{RUNVIEW}    = "lastrec";
      } elsif ($prop eq "live_fw") {
          $hash->{HELPER}{OPENWINDOW} = 0;
          $hash->{HELPER}{WLTYPE}     = "image"; 
		  $hash->{HELPER}{ALIAS}      = " ";
		  $hash->{HELPER}{RUNVIEW}    = "live_fw";
      } elsif ($prop eq "live_fw_hls") {
          $hash->{HELPER}{OPENWINDOW} = 0;
          $hash->{HELPER}{WLTYPE}     = "hls"; 
		  $hash->{HELPER}{ALIAS}      = "View only on compatible browsers";
		  $hash->{HELPER}{RUNVIEW}    = "live_fw_hls";
      } elsif ($prop eq "lastsnap_fw") {
          $hash->{HELPER}{OPENWINDOW}  = 0;
          $hash->{HELPER}{WLTYPE}      = "base64img"; 
		  $hash->{HELPER}{ALIAS}       = " ";
		  $hash->{HELPER}{RUNVIEW}     = "lastsnap_fw";
      } else {
          return "$prop isn't a valid option of runview, use one of live_fw, live_link, live_open, lastrec_fw, lastrec_open, lastsnap_fw";
      }
      SSCam_runliveview($hash); 
            
  } elsif ($opt eq "hlsreactivate" && SSCam_IsModelCam($hash)) {
      # ohne SET-Menüeintrag
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      SSCam_hlsreactivate($hash);
        
  } elsif ($opt eq "hlsactivate" && SSCam_IsModelCam($hash)) {
      # ohne SET-Menüeintrag
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      SSCam_hlsactivate($hash);
        
  } elsif ($opt eq "extevent" && !SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
                                   
      $hash->{HELPER}{EVENTID} = $prop;
      SSCam_extevent($hash);
        
  } elsif ($opt eq "stopView" && SSCam_IsModelCam($hash)) {
      SSCam_stopliveview($hash);            
        
  } elsif ($opt eq "setPreset" && SSCam_IsModelCam($hash)) {
	  if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
	  if (!$prop) {return "Syntax of function \"$opt\" was wrong. Please use \"set $name setPreset <PresetNumber> <PresetName> [<Speed>]\" ";}
      $hash->{HELPER}{PNUMBER} = $prop;
      $hash->{HELPER}{PNAME}   = $prop1?$prop1:$prop;  # wenn keine Presetname angegeben -> Presetnummer als Name verwenden
      $hash->{HELPER}{PSPEED}  = $prop2 if($prop2);
	  SSCam_setPreset($hash);
                
  } elsif ($opt eq "setHome" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      if (!$prop) {return "Function \"$opt\" needs a \"Presetname\" as argument";}      
      $hash->{HELPER}{SETHOME} = $prop;
      SSCam_setHome($hash);
                
  } elsif ($opt eq "delPreset" && SSCam_IsModelCam($hash)) {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      if (!$prop) {return "Function \"$opt\" needs a \"Presetname\" as argument";}      
      $hash->{HELPER}{DELPRESETNAME} = $prop;
      SSCam_delPreset($hash);
        
  } else {
      return "$setlist";
  }  
  
return;
}

################################################################
sub SSCam_Get($@) {
    my ($hash, @a) = @_;
    return "\"get X\" needs at least an argument" if ( @a < 2 );
    my $name = shift @a;
    my $opt = shift @a;
	my $arg = shift @a;
	my $arg1 = shift @a;
	my $arg2 = shift @a;
	my $ret = "";
	my $getlist;

	if(SSCam_IsModelCam($hash)) {
	    # selist für Cams
	    $getlist = "Unknown argument $opt, choose one of ".
                   "caminfoall:noArg ".
				   "caminfo:noArg ".
		 		   ((AttrVal($name,"snapGalleryNumber",undef) || AttrVal($name,"snapGalleryBoost",0))
				       ?"snapGallery:noArg ":"snapGallery:$SSCAM_snum ").
                   ((ReadingsVal("$name", "CapPTZPresetNumber", 0) != 0) ? "listPresets:noArg " : "").
				   "snapinfo:noArg ".
                   "svsinfo:noArg ".
                   "snapfileinfo:noArg ".
                   "eventlist:noArg ".
	        	   "stmUrlPath:noArg ".
				   "storedCredentials:noArg ".
				   "scanVirgin:noArg "
                   ;
	} else {
        # setlist für SVS Devices
	    $getlist = "Unknown argument $opt, choose one of ".
		           "caminfoall:noArg ".
				   ($hash->{HELPER}{APIHMMAXVER}?"homeModeState:noArg ": "").
                   "svsinfo:noArg ".
				   "listLog ".
				   "storedCredentials:noArg ".
				   "scanVirgin:noArg "
                   ;
	}
				  
    return if(IsDisabled($name));             
        
    if ($opt eq "caminfo") {
        # "1" ist Statusbit für manuelle Abfrage, kein Einstieg in Pollingroutine
		if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        SSCam_getcaminfo($hash);
                
    } elsif ($opt eq "caminfoall") {
        # "1" ist Statusbit für manuelle Abfrage, kein Einstieg in Pollingroutine
		if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        SSCam_getcaminfoall($hash,1);
                
    } elsif ($opt eq "homeModeState" && !SSCam_IsModelCam($hash)) {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        SSCam_gethomemodestate($hash);
                
    } elsif ($opt eq "listLog" && !SSCam_IsModelCam($hash)) {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        # übergebenen CL-Hash (FHEMWEB) in Helper eintragen 
	    SSCam_getclhash($hash,1);
		
		SSCam_extlogargs($hash,$arg) if($arg);
        SSCam_extlogargs($hash,$arg1) if($arg1);
        SSCam_extlogargs($hash,$arg2) if($arg2);
		SSCam_getsvslog($hash);
                
    } elsif ($opt eq "listPresets" && SSCam_IsModelCam($hash)) {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        # übergebenen CL-Hash (FHEMWEB) in Helper eintragen 
	    SSCam_getclhash($hash,1);
		SSCam_getpresets($hash);
                
    } elsif ($opt eq "svsinfo") {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        SSCam_getsvsinfo($hash);
                
    } elsif ($opt eq "storedCredentials") {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        # Credentials abrufen
        my ($success, $username, $password) = SSCam_getcredentials($hash,0);
        unless ($success) {return "Credentials couldn't be retrieved successfully - see logfile"};
        return "Stored Credentials for $name - Username: $username, Password: $password";
                
    } elsif ($opt eq "snapGallery" && SSCam_IsModelCam($hash)) {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
	    my $txt = SSCam_getclhash($hash);
        return $txt if($txt);

		if(!AttrVal($name, "snapGalleryBoost",0)) {	
            # Snaphash ist nicht vorhanden und wird abgerufen		
		    $hash->{HELPER}{GETSNAPGALLERY} = 1;
        
		    # snap-Infos für Gallerie abrufen
		    my ($sg,$slim,$ssize); 
		    $slim  = $arg?AttrVal($name,"snapGalleryNumber",$arg):AttrVal($name,"snapGalleryNumber",$SSCam_slim);  # Anzahl der abzurufenden Snapshots
		    $ssize = (AttrVal($name,"snapGallerySize","Icon") eq "Icon")?1:2;                                      # Image Size 1-Icon, 2-Full		
        
		    SSCam_getsnapinfo("$name:$slim:$ssize");
		
		} else {
		    # Snaphash ist vorhanden und wird zur Ausgabe aufbereitet
			my $htmlCode = composegallery($name);
		    for (my $k=1; (defined($hash->{HELPER}{CL}{$k})); $k++ ) {
		        if ($hash->{HELPER}{CL}{$k}->{COMP}) {
		            # CL zusammengestellt (Auslösung durch Notify)
		            asyncOutput($hash->{HELPER}{CL}{$k}, "$htmlCode");						
		        } else {
			        # Output wurde über FHEMWEB ausgelöst
		            return $htmlCode;
		        }
		    }
		    delete($hash->{HELPER}{CL});
		}

    } elsif ($opt eq "snapinfo" && SSCam_IsModelCam($hash)) {
        # Schnappschußgalerie abrufen (snapGalleryBoost) oder nur Info des letzten Snaps
		if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        my ($slim,$ssize) = SSCam_snaplimsize($hash);		
        SSCam_getsnapinfo("$name:$slim:$ssize");
                
    } elsif ($opt eq "snapfileinfo" && SSCam_IsModelCam($hash)) {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        if (!ReadingsVal("$name", "LastSnapId", undef)) {return "Reading LastSnapId is empty - please take a snapshot before !"}
        SSCam_getsnapfilename($hash);
                
    } elsif ($opt eq "eventlist" && SSCam_IsModelCam($hash)) {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        SSCam_geteventlist ($hash);
                
    } elsif ($opt eq "stmUrlPath" && SSCam_IsModelCam($hash)) {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        SSCam_getStmUrlPath ($hash);
            
	} elsif ($opt eq "scanVirgin") {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
		SSCam_sessionoff($hash);
		delete $hash->{HELPER}{APIPARSET};
		delete $hash->{CAMID};
		# "1" ist Statusbit für manuelle Abfrage, kein Einstieg in Pollingroutine
        SSCam_getcaminfoall($hash,1);
    
	} else {
        return "$getlist";
	}
return $ret;  # not generate trigger out of command
}

######################################################################################
#                         Kamera Liveview Anzeige in FHEMWEB
######################################################################################
# wird von FW aufgerufen. $FW_wname = aufrufende Webinstanz, $d = aufrufendes 
# Device (z.B. CamCP1)
sub SSCam_FWsummaryFn ($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_;   # pageHash is set for summaryFn in FHEMWEB
  my $hash   = $defs{$d};
  my $name   = $hash->{NAME};
  my $link   = $hash->{HELPER}{LINK};
  my $wltype = $hash->{HELPER}{WLTYPE};
  my $ret;
  my $alias;
    
  return if(!$hash->{HELPER}{LINK} || ReadingsVal($d, "state", "") =~ /^dis.*/ || IsDisabled($name));
  
  my $attr = AttrVal($d, "htmlattr", " ");
  Log3($name, 4, "$name - SSCam_FWsummaryFn called - FW_wname: $FW_wname, device: $d, room: $room, attributes: $attr");
  
  if($wltype eq "image") {
    $ret = "<img src=$link $attr><br>";
    if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($d, "CamAudioType", "Unknown") !~ /Unknown/) {
        $ret .= "<audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>
                 Your browser does not support the audio element.      
                 </audio>";
    }
    
  } elsif($wltype eq "iframe") {
    $ret = "<iframe src=$link $attr controls>Iframes disabled</iframe>";
    if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($d, "CamAudioType", "Unknown") !~ /Unknown/) {
        $ret .= "<audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>
                 Your browser does not support the audio element.      
                 </audio>";
    }
           
  } elsif($wltype eq "embed") {
    $ret = "<embed src=$link $attr>";
    if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($d, "CamAudioType", "Unknown") !~ /Unknown/) {
        $ret .= "<audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>
                 Your browser does not support the audio element.      
                 </audio>";
    }
           
  } elsif($wltype eq "link") {
    $alias = $hash->{HELPER}{ALIAS};
    $ret = "<a href=$link $attr>$alias</a><br>";     

  } elsif($wltype eq "base64img") {
    $alias = $hash->{HELPER}{ALIAS};
    $ret = "<img $attr alt='$alias' src='data:image/jpeg;base64,$link'><br>";
  
  } elsif($wltype eq "hls") {
    $alias = $hash->{HELPER}{ALIAS};
    $ret = "<video $attr controls autoplay>
            <source src=\"$link\" type=\"application/x-mpegURL\">
            <source src=$link type=\"video/MP2T\">
            </video>";
  
  } elsif($wltype eq "video") {
    $ret = "<video $attr controls> 
             <source src=$link type=\"video/mp4\"> 
             <source src=$link type=\"video/ogg\">
             <source src=$link type=\"video/webm\">
             Your browser does not support the video tag.
             </video>"; 
    if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($d, "CamAudioType", "Unknown") !~ /Unknown/) {
        $ret .= "<audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>
                 Your browser does not support the audio element.      
                 </audio>";
    }             
  } 

return $ret;
}

######################################################################################
#                 PTZ-Steuerpanel in Detailanzeige darstellen 
######################################################################################
sub SSCam_FWdetailFn ($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_;           # pageHash is set for summaryFn.
  my $hash = $defs{$d};
  
  return undef if(!AttrVal($d,"ptzPanel_use",1));
  $hash->{".ptzhtml"} = SSCam_ptzpanel($d) if($hash->{".ptzhtml"} eq "");

  if($hash->{".ptzhtml"} ne "") {
      return $hash->{".ptzhtml"};
  } else {
      return undef;
  }
}

######################################################################################
#                   initiale Startroutinen nach Restart FHEM
######################################################################################
sub SSCam_initonboot ($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash, "SSCam_initonboot");
  
  if ($init_done == 1) {
     RemoveInternalTimer($hash);                                                                     # alle Timer löschen
     
     delete($defs{$name}{READINGS}{LiveStreamUrl}) if($defs{$name}{READINGS}{LiveStreamUrl});        # LiveStream URL zurücksetzen
     
     # check ob alle Recordings = "Stop" nach Reboot -> sonst stoppen
     if (ReadingsVal($hash->{NAME}, "Record", "Stop") eq "Start") {
         Log3($name, 2, "$name - Recording of $hash->{CAMNAME} seems to be still active after FHEM restart - try to stop it now");
         SSCam_camstoprec($hash);
     }
         
     # Konfiguration der Synology Surveillance Station abrufen
     if (!$hash->{CREDENTIALS}) {
         Log3($name, 2, "$name - Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"");
     } else {
         # allg. SVS-Eigenschaften abrufen
         SSCam_getsvsinfo($hash);
         
		 if(SSCam_IsModelCam($hash)) {
		     # Kameraspezifische Infos holen
             SSCam_getcaminfo($hash);           

             SSCam_getcapabilities($hash);
             
			 # Preset/Patrollisten in Hash einlesen zur PTZ-Steuerung
             SSCam_getptzlistpreset($hash);
             SSCam_getptzlistpatrol($hash);

             # Schnappschußgalerie abrufen (snapGalleryBoost) oder nur Info des letzten Snaps
             my ($slim,$ssize) = SSCam_snaplimsize($hash);
             RemoveInternalTimer("SSCam_getsnapinfo"); 
             InternalTimer(gettimeofday()+0.9, "SSCam_getsnapinfo", "$name:$slim:$ssize", 0); 
		 }
     }
         
     # Subroutine Watchdog-Timer starten (sollen Cam-Infos regelmäßig abgerufen werden ?), verzögerter zufälliger Start 0-30s 
     RemoveInternalTimer($hash, "SSCam_wdpollcaminfo");
     InternalTimer(gettimeofday()+int(rand(30)), "SSCam_wdpollcaminfo", $hash, 0);
  
  } else {
      InternalTimer(gettimeofday()+1, "SSCam_initonboot", $hash, 0);
  }
return;
}

######################################################################################
#                            Username / Paßwort speichern
######################################################################################
sub SSCam_setcredentials ($@) {
    my ($hash, @credentials) = @_;
    my $name     = $hash->{NAME};
    my $success;
    my $credstr;
    my $index;
    my $retcode;
    my (@key,$len,$i);
    
    $credstr = encode_base64(join(':', @credentials));
    
    # Beginn Scramble-Routine
    @key = qw(1 3 4 5 6 3 2 1 9);
    $len = scalar @key;  
    $i = 0;  
    $credstr = join "",  
            map { $i = ($i + 1) % $len;  
            chr((ord($_) + $key[$i]) % 256) } split //, $credstr; 
    # End Scramble-Routine    
       
    $index = $hash->{TYPE}."_".$hash->{NAME}."_credentials";
    $retcode = setKeyValue($index, $credstr);
    
    if ($retcode) { 
        Log3($name, 2, "$name - Error while saving the Credentials - $retcode");
        $success = 0;
    } else {
        SSCam_getcredentials($hash,1);        # Credentials nach Speicherung lesen und in RAM laden ($boot=1) 
        $success = 1;
    }

return ($success);
}

######################################################################################
#                             Username / Paßwort abrufen
######################################################################################
sub SSCam_getcredentials ($$) {
    my ($hash,$boot) = @_;
    my $name     = $hash->{NAME};
    my $success;
    my $username;
    my $passwd;
    my $index;
    my ($retcode, $credstr);
    my (@key,$len,$i);
    
    if ($boot eq 1) {
        # mit $boot=1 Credentials von Platte lesen und als scrambled-String in RAM legen
        $index = $hash->{TYPE}."_".$hash->{NAME}."_credentials";
        ($retcode, $credstr) = getKeyValue($index);
    
        if ($retcode) {
            Log3($name, 2, "$name - Unable to read password from file: $retcode");
            $success = 0;
        }  

        if ($credstr) {
            # beim Boot scrambled Credentials in den RAM laden
            $hash->{HELPER}{CREDENTIALS} = $credstr;
        
            # "Credentials" wird als Statusbit ausgewertet. Wenn nicht gesetzt -> Warnmeldung und keine weitere Verarbeitung
            $hash->{CREDENTIALS} = "Set";
            $success = 1;
        }
    } else {
        # boot = 0 -> Credentials aus RAM lesen, decoden und zurückgeben
        $credstr = $hash->{HELPER}{CREDENTIALS};
    
        # Beginn Descramble-Routine
        @key = qw(1 3 4 5 6 3 2 1 9); 
        $len = scalar @key;  
        $i = 0;  
        $credstr = join "",  
        map { $i = ($i + 1) % $len;  
        chr((ord($_) - $key[$i] + 256) % 256) }  
        split //, $credstr;   
        # Ende Descramble-Routine
    
        ($username, $passwd) = split(":",decode_base64($credstr));
    
        my $logpw = AttrVal($name, "showPassInLog", "0") == 1 ? $passwd : "********";
        Log3($name, 4, "$name - Credentials read from RAM: $username $logpw");
    
        $success = (defined($passwd)) ? 1 : 0;
    }
return ($success, $username, $passwd);        
}

######################################################################################
#                              Polling Überwachung
######################################################################################
sub SSCam_wdpollcaminfo ($) {
    # Überwacht die Wert von Attribut "pollcaminfoall" und Reading "PollState"
    # wenn Attribut "pollcaminfoall" > 10 und "PollState"=Inactive -> start Polling
    my ($hash)   = @_;
    my $name     = $hash->{NAME};
    my $camname  = $hash->{CAMNAME};
    my $pcia     = AttrVal($name,"pollcaminfoall",0); 
    my $pnl      = AttrVal($name,"pollnologging",0); 
    my $watchdogtimer = 90;
    
    RemoveInternalTimer($hash, "SSCam_wdpollcaminfo");

    # Poll-Logging prüfen
    if ($hash->{HELPER}{OLDVALPOLLNOLOGGING} != $pnl) {
        $hash->{HELPER}{OLDVALPOLLNOLOGGING} = $pnl;    # aktuellen pollnologging-Wert in $hash eintragen für späteren Vergleich
        if ($pnl) {
            Log3($name, 3, "$name - Polling-Log of $camname is deactivated");          
        } else {
            Log3($name, 3, "$name - Polling-Log of $camname is activated");
        }
    }    
    
    # Polling prüfen
    if ($pcia && !IsDisabled($name)) {
        if(ReadingsVal($name, "PollState", "Active") eq "Inactive") {
            readingsSingleUpdate($hash,"PollState","Active",1);                             # Polling ist jetzt aktiv
            readingsSingleUpdate($hash,"state","polling",1) if(!SSCam_IsModelCam($hash));   # Polling-state bei einem SVS-Device setzten
		    Log3($name, 3, "$name - Polling of $camname is activated - Pollinginterval: $pcia s");
            $hash->{HELPER}{OLDVALPOLL} = $pcia;                                            # in $hash eintragen für späteren Vergleich (Changes von pollcaminfoall)
            SSCam_getcaminfoall($hash,0);  
        }
        
        my $lupd = ReadingsVal($name, "LastUpdateTime", 0);
        if ($lupd) {
            my ($year, $month, $mday, $hour, $min, $sec) = ($lupd =~ /(\d+)\.(\d+)\.(\d+) \/ (\d+):(\d+):(\d+)/);
            $lupd = fhemTimeGm($sec, $min, $hour, $mday, $month, $year);
        }
        if( gettimeofday() < ($lupd + $pcia + 20) ) {
            SSCam_getcaminfoall($hash,0);  
        }
        
    }
    
    if (defined($hash->{HELPER}{OLDVALPOLL}) && $pcia) {
        if ($hash->{HELPER}{OLDVALPOLL} != $pcia) {
            Log3($name, 3, "$name - Pollinginterval of $camname has been changed to: $pcia s");
            $hash->{HELPER}{OLDVALPOLL} = $pcia;
        }
    }

InternalTimer(gettimeofday()+$watchdogtimer, "SSCam_wdpollcaminfo", $hash, 0);
return undef;
}

############################################################################################################
#                                        OpMode-Startroutinen                                              #
#   $hash->{HELPER}{ACTIVE} = Funktionstoken                                                               #
#   $hash->{HELPER}{ACTIVE} = "on"    ->  eine Routine läuft, Start anderer Routine erst wenn "off".       #
#   $hash->{HELPER}{ACTIVE} = "off"   ->  keine andere Routine läuft, sofortiger Start möglich             #
############################################################################################################

###############################################################################
#                          Kamera Aufnahme starten
###############################################################################
sub SSCam_camstartrec ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_camstartrec");
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = SSCam_experror($hash,$errorcode);

        # Setreading 
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        Log3($name, 2, "$name - ERROR - Start Recording of Camera $camname can't be executed - $error");
        
        return;
    }
        
    if (ReadingsVal("$name", "Record", undef) eq "Start" and !AttrVal($name, "recextend", undef)) {
        Log3($name, 3, "$name - another recording is already running - new start-command will be ignored");
        return;
    } 
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        # Aufnahme starten                         
        $hash->{OPMODE} = "Start";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
    
	} else {
        InternalTimer(gettimeofday()+0.3, "SSCam_camstartrec", $hash);
    }
}

###############################################################################
#                           Kamera Aufnahme stoppen
###############################################################################
sub SSCam_camstoprec ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_camstoprec");
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = SSCam_experror($hash,$errorcode);

        # Setreading 
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        Log3($name, 2, "$name - ERROR - Stop Recording of Camera $camname can't be executed - $error");
        return;
    }
        
    if (ReadingsVal("$name", "Record", undef) eq "Stop") {
        Log3($name, 3, "$name - recording is already stopped - new stop-command will be ignored");
        return;
    } 
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        $hash->{OPMODE} = "Stop";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }  
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+0.3, "SSCam_camstoprec", $hash, 0);
    }
}

###############################################################################
#                   Kamera Auto / Day / Nightmode setzen
###############################################################################
sub SSCam_camexpmode($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_camexpmode");
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = SSCam_experror($hash,$errorcode);

        # Setreading 
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        Log3($name, 2, "$name - ERROR - Setting exposure mode of Camera $camname can't be executed - $error");
        return;
    }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                           
        $hash->{OPMODE} = "ExpMode";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+0.5, "SSCam_camexpmode", $hash, 0);
    }
}

###############################################################################
#                    Art der Bewegungserkennung setzen
###############################################################################
sub SSCam_cammotdetsc($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_cammotdetsc");
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = SSCam_experror($hash,$errorcode);

        # Setreading 
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        Log3($name, 2, "$name - ERROR - Setting of motion detection source of Camera $camname can't be executed - $error");
        return;
    }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {             
        $hash->{OPMODE} = "MotDetSc";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }    
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+0.5, "SSCam_cammotdetsc", $hash, 0);
    }
}

###############################################################################
#                       Kamera Schappschuß aufnehmen
###############################################################################
sub SSCam_camsnap($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_camsnap");
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = SSCam_experror($hash,$errorcode);

        # Setreading 
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        Log3($name, 2, "$name - ERROR - Snapshot of Camera $camname can't be executed - $error");
        
        return;
    }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        # einen Schnappschuß aufnehmen              
        $hash->{OPMODE} = "Snap";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+0.3, "SSCam_camsnap", $hash, 0);
    }    
}

###############################################################################
#                       Start Object Tracking
###############################################################################
sub SSCam_starttrack($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_starttrack");
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = SSCam_experror($hash,$errorcode);

        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        Log3($name, 2, "$name - ERROR - Object Tracking of Camera $camname can't switched on - $error");
        
        return;
    }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {             
        $hash->{OPMODE} = "startTrack";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+0.9, "SSCam_starttrack", $hash, 0);
    }    
}

###############################################################################
#                       Stopp Object Tracking
###############################################################################
sub SSCam_stoptrack($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_stoptrack");
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = SSCam_experror($hash,$errorcode);

        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        Log3($name, 2, "$name - ERROR - Object Tracking of Camera $camname can't switched off - $error");
        
        return;
    }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {             
        $hash->{OPMODE} = "stopTrack";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+0.9, "SSCam_stoptrack", $hash, 0);
    }    
}

###############################################################################
#                       Preset-Array abrufen
###############################################################################
sub SSCam_getpresets($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_getpresets");
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = SSCam_experror($hash,$errorcode);

        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        Log3($name, 2, "$name - ERROR - Preset list of Camera $camname can't be get - $error");
        
        return;
    }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {             
        $hash->{OPMODE} = "getPresets";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+1.2, "SSCam_getpresets", $hash, 0);
    }    
}

###############################################################################
#                       einen Preset setzen
###############################################################################
sub SSCam_setPreset($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_setPreset");
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = SSCam_experror($hash,$errorcode);

        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        Log3($name, 2, "$name - ERROR - Preset of Camera $camname can't be set - $error");
        
        return;
    }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {             
        $hash->{OPMODE} = "setPreset";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+1.2, "SSCam_setPreset", $hash, 0);
    }    
}

###############################################################################
#                       einen Preset löschen
###############################################################################
sub SSCam_delPreset($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_delPreset");
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = SSCam_experror($hash,$errorcode);

        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        Log3($name, 2, "$name - ERROR - Preset of Camera $camname can't be deleted - $error");
        
        return;
    }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {             
        $hash->{OPMODE} = "delPreset";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+1.4, "SSCam_delPreset", $hash, 0);
    }    
}

###############################################################################
#                       Preset Home setzen
###############################################################################
sub SSCam_setHome($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_setHome");
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = SSCam_experror($hash,$errorcode);

        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        Log3($name, 2, "$name - ERROR - Home preset of Camera $camname can't be set - $error");
        
        return;
    }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {             
        $hash->{OPMODE} = "setHome";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+1.2, "SSCam_setHome", $hash, 0);
    }    
}

###############################################################################
#                         Kamera Liveview starten
###############################################################################
sub SSCam_runliveview($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_runliveview");
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = &SSCam_experror($hash,$errorcode);

        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        Log3($name, 2, "$name - ERROR - Liveview of Camera $camname can't be started - $error");
        return;
    }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        # Liveview starten             
        $hash->{OPMODE} = "runliveview";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0; 
		# erzwingen die Camid zu ermitteln und bei login-Fehler neue SID zu holen
		delete $hash->{CAMID};  
        
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        readingsSingleUpdate($hash,"state","runView ".$hash->{HELPER}{RUNVIEW},1); 
        SSCam_getapisites($hash);
    
	} else {
        InternalTimer(gettimeofday()+0.5, "SSCam_runliveview", $hash, 0);
    }    
}

###############################################################################
#                         Kamera HLS-Stream aktivieren
###############################################################################
sub SSCam_hlsactivate($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_hlsactivate");
    return if(IsDisabled($name));
 
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = &SSCam_experror($hash,$errorcode);

        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        Log3($name, 2, "$name - ERROR - HLS-Stream of Camera $camname can't be activated - $error");
        return;
    }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        # Aktivierung starten             
        $hash->{OPMODE} = "activate_hls";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;   
        
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
    
	} else {
        InternalTimer(gettimeofday()+0.3, "SSCam_hlsactivate", $hash, 0);
    }    
}

###############################################################################
#               HLS-Stream reaktivieren (stoppen & starten)
###############################################################################
sub SSCam_hlsreactivate($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_hlsreactivate");
    return if(IsDisabled($name));
 
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = &SSCam_experror($hash,$errorcode);

        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        Log3($name, 2, "$name - ERROR - HLS-Stream of Camera $camname can't be activated - $error");
        return;
    }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        # Aktivierung starten             
        $hash->{OPMODE} = "reactivate_hls";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;   
        
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
    
	} else {
        InternalTimer(gettimeofday()+0.4, "SSCam_hlsreactivate", $hash, 0);
    }    
}

###############################################################################
#                         Kamera Liveview stoppen
###############################################################################
sub SSCam_stopliveview ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
   
    RemoveInternalTimer($hash, "SSCam_stopliveview");
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        
        # Liveview stoppen           
        $hash->{OPMODE} = "stopliveview";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        
        # Link aus Helper-hash löschen
        delete $hash->{HELPER}{LINK};
        delete $hash->{HELPER}{AUDIOLINK};
        
        # Reading LiveStreamUrl löschen
        delete($defs{$name}{READINGS}{LiveStreamUrl}) if ($defs{$name}{READINGS}{LiveStreamUrl});
        
        readingsSingleUpdate($hash,"state","stopview",1);           
        
        if($hash->{HELPER}{WLTYPE} eq "hls") {
            # HLS Stream war aktiv, Streaming beenden
            $hash->{OPMODE} = "stopliveview_hls";
            SSCam_getapisites($hash);
        } else {
            # kein HLS Stream
			SSCam_refresh($hash,0,1,1);    # kein Room-Refresh, Longpoll SSCam, Longpoll SSCamSTRM
		    $hash->{HELPER}{ACTIVE} = "off";  
		    if (AttrVal($name,"debugactivetoken",0)) {
                Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
            }
        }
	
	} else {
        InternalTimer(gettimeofday()+0.5, "SSCam_stopliveview", $hash, 0);
    }    
}

###############################################################################
#                       external Event 1-10 auslösen
###############################################################################
sub SSCam_extevent ($) {
    my ($hash)   = @_;
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_extevent");
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE} = "extevent";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+0.5, "SSCam_extevent", $hash, 0);
    }    
}

###############################################################################
#                      PTZ-Kamera auf Position fahren
###############################################################################
sub SSCam_doptzaction ($) {
    my ($hash)       = @_;
    my $camname      = $hash->{CAMNAME};
    my $name         = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_doptzaction");
    return if(IsDisabled($name));

    if (ReadingsVal("$name", "DeviceType", "Camera") ne "PTZ") {
        Log3($name, 2, "$name - ERROR - Operation \"$hash->{HELPER}{PTZACTION}\" is only possible for cameras of DeviceType \"PTZ\" - please compare with device Readings");
        return;
    }
    if ($hash->{HELPER}{PTZACTION} eq "goabsptz" && !ReadingsVal("$name", "CapPTZAbs", "false")) {
        Log3($name, 2, "$name - ERROR - Operation \"$hash->{HELPER}{PTZACTION}\" is only possible if camera supports absolute PTZ action - please compare with device Reading \"CapPTZAbs\"");
        return;
    }
    if ( $hash->{HELPER}{PTZACTION} eq "movestart" && ReadingsVal("$name", "CapPTZDirections", "0") < 1) {
        Log3($name, 2, "$name - ERROR - Operation \"$hash->{HELPER}{PTZACTION}\" is only possible if camera supports \"Tilt\" and \"Pan\" operations - please compare with device Reading \"CapPTZDirections\"");
        return;
    }
    
    if ($hash->{HELPER}{PTZACTION} eq "gopreset") {
        if (!defined($hash->{HELPER}{ALLPRESETS}{$hash->{HELPER}{GOPRESETNAME}})) {
            $errorcode = "600";
            # Fehlertext zum Errorcode ermitteln
            $error = SSCam_experror($hash,$errorcode);
        
            # Setreading 
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode",$errorcode);
            readingsBulkUpdate($hash,"Error",$error);
            readingsEndUpdate($hash, 1);
    
            Log3($name, 2, "$name - ERROR - goPreset to position \"$hash->{HELPER}{GOPRESETNAME}\" of Camera $camname can't be executed - $error");
            return;        
        }
    }
    
    if ($hash->{HELPER}{PTZACTION} eq "runpatrol") {
        if (!defined($hash->{HELPER}{ALLPATROLS}{$hash->{HELPER}{GOPATROLNAME}})) {
            $errorcode = "600";
            # Fehlertext zum Errorcode ermitteln
            $error = SSCam_experror($hash,$errorcode);
        
            # Setreading 
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode",$errorcode);
            readingsBulkUpdate($hash,"Error",$error);
            readingsEndUpdate($hash, 1);
    
            Log3($name, 2, "$name - ERROR - runPatrol to patrol \"$hash->{HELPER}{GOPATROLNAME}\" of Camera $camname can't be executed - $error");
            return;        
        }
    }
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = SSCam_experror($hash,$errorcode);

        # Setreading 
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        Log3($name, 2, "$name - ERROR - $hash->{HELPER}{PTZACTION} of Camera $camname can't be executed - $error");
        return;
        }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        
        if ($hash->{HELPER}{PTZACTION} eq "gopreset") {
            Log3($name, 4, "$name - Move Camera $camname to position \"$hash->{HELPER}{GOPRESETNAME}\" with ID \"$hash->{HELPER}{ALLPRESETS}{$hash->{HELPER}{GOPRESETNAME}}\" now");
        } elsif ($hash->{HELPER}{PTZACTION} eq "runpatrol") {
            Log3($name, 4, "$name - Start patrol \"$hash->{HELPER}{GOPATROLNAME}\" with ID \"$hash->{HELPER}{ALLPATROLS}{$hash->{HELPER}{GOPATROLNAME}}\" of Camera $camname now");
        } elsif ($hash->{HELPER}{PTZACTION} eq "goabsptz") {
            Log3($name, 4, "$name - Start move Camera $camname to position posX=\"$hash->{HELPER}{GOPTZPOSX}\" and posY=\"$hash->{HELPER}{GOPTZPOSY}\" now");
        } elsif ($hash->{HELPER}{PTZACTION} eq "movestart") {
            Log3($name, 4, "$name - Start move Camera $camname to direction \"$hash->{HELPER}{GOMOVEDIR}\" with duration of $hash->{HELPER}{GOMOVETIME} s");
        }
 
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
    
        $hash->{OPMODE} = $hash->{HELPER}{PTZACTION};
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
 
        SSCam_getapisites($hash);
 
    } else {
        InternalTimer(gettimeofday()+0.5, "SSCam_doptzaction", $hash, 0);
    }    
}

###############################################################################
#                         stoppen continoues move
###############################################################################
sub SSCam_movestop ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_movestop");
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE} = "movestop";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");;
        }
        SSCam_getapisites($hash);
   
    } else {
        InternalTimer(gettimeofday()+0.3, "SSCam_movestop", $hash, 0);
    }    
}

###############################################################################
#                           Kamera aktivieren
###############################################################################
sub SSCam_camenable ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_camenable");
    return if(IsDisabled($name));
    
    # if (ReadingsVal("$name", "Availability", "disabled") eq "enabled") {return;}       # Kamera ist bereits enabled
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        # eine Kamera aktivieren
        Log3($name, 4, "$name - Enable Camera $camname");
                        
        $hash->{OPMODE} = "Enable";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
    
	} else {
        InternalTimer(gettimeofday()+0.5, "SSCam_camenable", $hash, 0);
    }    
}

###############################################################################
#                            Kamera deaktivieren
###############################################################################
sub SSCam_camdisable ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_camdisable");
    return if(IsDisabled($name));
    
    # if (ReadingsVal("$name", "Availability", "enabled") eq "disabled") {return;}       # Kamera ist bereits disabled
    
    if ($hash->{HELPER}{ACTIVE} eq "off" and ReadingsVal("$name", "Record", "Start") ne "Start") {
        # eine Kamera deaktivieren
        Log3($name, 4, "$name - Disable Camera $camname");
                        
        $hash->{OPMODE} = "Disable";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+0.5, "SSCam_camdisable", $hash, 0);
    }    
}

###############################################################################
#      Kamera alle Informationen abrufen (Get) bzw. Einstieg Polling
###############################################################################
sub SSCam_getcaminfoall ($$) {
    my ($hash,$mode)   = @_;
    my $camname        = $hash->{CAMNAME};
    my $name           = $hash->{NAME};
    my ($now,$new);
    
    RemoveInternalTimer($hash, "SSCam_getcaminfoall");
    return if(IsDisabled($name));
    
    RemoveInternalTimer($hash, "SSCam_getsvsinfo");
    InternalTimer(gettimeofday()+1, "SSCam_getsvsinfo", $hash, 0);
	
	if(SSCam_IsModelCam($hash)) {
	    # Model ist CAM
        RemoveInternalTimer($hash, "SSCam_geteventlist");
        InternalTimer(gettimeofday()+0.5, "SSCam_geteventlist", $hash, 0);
	    RemoveInternalTimer($hash, "SSCam_getmotionenum");
        InternalTimer(gettimeofday()+0.6, "SSCam_getmotionenum", $hash, 0);
        RemoveInternalTimer($hash, "SSCam_getcaminfo");
        InternalTimer(gettimeofday()+0.9, "SSCam_getcaminfo", $hash, 0);
        RemoveInternalTimer($hash, "SSCam_getcapabilities");
        InternalTimer(gettimeofday()+1.3, "SSCam_getcapabilities", $hash, 0);
        RemoveInternalTimer($hash, "SSCam_getstreamformat");
        InternalTimer(gettimeofday()+1.4, "SSCam_getstreamformat", $hash, 0);
        
        # Schnappschußgalerie abrufen (snapGalleryBoost) oder nur Info des letzten Snaps
        my ($slim,$ssize) = SSCam_snaplimsize($hash);
        RemoveInternalTimer("SSCam_getsnapinfo"); 
        InternalTimer(gettimeofday()+1.5, "SSCam_getsnapinfo", "$name:$slim:$ssize", 0);
	
        RemoveInternalTimer($hash, "SSCam_getptzlistpreset");
        InternalTimer(gettimeofday()+1.6, "SSCam_getptzlistpreset", $hash, 0);
        RemoveInternalTimer($hash, "SSCam_getptzlistpatrol");
        InternalTimer(gettimeofday()+1.9, "SSCam_getptzlistpatrol", $hash, 0);
        RemoveInternalTimer($hash, "SSCam_getStmUrlPath");
        InternalTimer(gettimeofday()+2.1, "SSCam_getStmUrlPath", $hash, 0);

	} else {
	    # Model ist SVS
        RemoveInternalTimer($hash, "SSCam_gethomemodestate");
        InternalTimer(gettimeofday()+0.7, "SSCam_gethomemodestate", $hash, 0);
        RemoveInternalTimer($hash, "SSCam_getsvslog");
        InternalTimer(gettimeofday()+0.8, "SSCam_getsvslog", $hash, 0);
    }
    
	# wenn gesetzt = manuelle Abfrage
    # return if ($mode);                # 24.03.2018 geänd.
    
    my $pcia = AttrVal($name,"pollcaminfoall",0);
    my $pnl  = AttrVal($name,"pollnologging",0);
    if ($pcia) {        
        $new = gettimeofday()+$pcia; 
        InternalTimer($new, "SSCam_getcaminfoall", $hash, 0);
		
		$now = FmtTime(gettimeofday());
        $new = FmtTime(gettimeofday()+$pcia);
		readingsSingleUpdate($hash,"state","polling",1) if(!SSCam_IsModelCam($hash));  # state für SVS-Device setzen
		readingsSingleUpdate($hash,"PollState","Active - next time: $new",1);  
        
        if (!$pnl) {
            Log3($name, 3, "$name - Polling now: $now , next Polling: $new");
        }
    
	} else {
        # Beenden Polling aller Caminfos
        readingsSingleUpdate($hash,"PollState","Inactive",1);
		readingsSingleUpdate($hash,"state","initialized",1) if(!SSCam_IsModelCam($hash));  # state für SVS-Device setzen
        Log3($name, 3, "$name - Polling of $camname is deactivated");
    }
return;
}

###########################################################################
#  Infos zu Snaps abfragen (z.B. weil nicht über SSCam ausgelöst)
###########################################################################
sub SSCam_getsnapinfo ($) {
    my ($str)   = @_;
	my ($name,$slim,$ssize) = split(":",$str);
	my $hash = $defs{$name};
    my $camname  = $hash->{CAMNAME};
    
    RemoveInternalTimer("SSCam_getsnapinfo"); 
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {               
        $hash->{OPMODE} = "getsnapinfo";
		$hash->{OPMODE} = "getsnapgallery" if(exists($hash->{HELPER}{GETSNAPGALLERY}));
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		$hash->{HELPER}{SNAPLIMIT}    = $slim;   # 0-alle Snapshots werden abgerufen und ausgewertet, sonst $slim
		$hash->{HELPER}{SNAPIMGSIZE}  = $ssize;  # 0-Do not append image, 1-Icon size, 2-Full size
		$hash->{HELPER}{KEYWORD}      = $camname;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+1.7, "SSCam_getsnapinfo", "$name:$slim:$ssize", 0);
    }
}

###############################################################################
#                     Filename zu Schappschuß ermitteln
###############################################################################
sub SSCam_getsnapfilename ($) {
    my ($hash)   = @_;
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_getsnapfilename");
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {    
        $hash->{OPMODE} = "getsnapfilename";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
    
	} else {
        InternalTimer(gettimeofday()+0.5, "SSCam_getsnapfilename", $hash, 0);
    }    
}

###########################################################################
#       allgemeine Infos über Synology Surveillance Station
###########################################################################
sub SSCam_getsvsinfo ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_getsvsinfo");
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE} = "getsvsinfo";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+1, "SSCam_getsvsinfo", $hash, 0);
    }
}

###########################################################################
#                                HomeMode setzen 
###########################################################################
sub SSCam_sethomemode ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_sethomemode");
    return if(IsDisabled($name) || !defined($hash->{HELPER}{APIHMMAXVER}));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE} = "sethomemode";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+0.6, "SSCam_sethomemode", $hash, 0);
    }
}

###########################################################################
#                         Optimierparameter setzen 
###########################################################################
sub SSCam_setoptpar ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_setoptpar");
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE} = "setoptpar";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+0.6, "SSCam_setoptpar", $hash, 0);
    }
}

###########################################################################
#                         HomeMode Status abfragen
###########################################################################
sub SSCam_gethomemodestate ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_gethomemodestate");
    return if(IsDisabled($name) || !defined($hash->{HELPER}{APIHMMAXVER}));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE} = "gethomemodestate";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+0.7, "SSCam_gethomemodestate", $hash, 0);
    }
}

###########################################################################
#                         SVS Log abrufen
###########################################################################
sub SSCam_getsvslog ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_getsvslog");
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE} = "getsvslog";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+0.9, "SSCam_getsvslog", $hash, 0);
    }
}

###########################################################################
#                           Session SSCam_logout
###########################################################################
sub SSCam_sessionoff ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_sessionoff");
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE} = "logout";
        $hash->{HELPER}{ACTIVE} = "on";
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_logout($hash);
		
    } else {
        InternalTimer(gettimeofday()+1.1, "SSCam_sessionoff", $hash, 0);
    }
}

###########################################################################
#               Kamera allgemeine Informationen abrufen (Get) 
###########################################################################
sub SSCam_getcaminfo ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_getcaminfo");
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE} = "Getcaminfo";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        } 
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+2, "SSCam_getcaminfo", $hash, 0);
    } 
}

###########################################################################
#   SYNO.SurveillanceStation.VideoStream query aktuelles Streamformat 
###########################################################################
sub SSCam_getstreamformat ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_getstreamformat");
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE} = "getstreamformat";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        } 
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+1.4, "SSCam_getstreamformat", $hash, 0);
    } 
}

################################################################################
#                      Kamera Stream Urls abrufen (Get)
################################################################################
sub SSCam_getStmUrlPath ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_getStmUrlPath");
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        # Stream-Urls abrufen              
        $hash->{OPMODE} = "getStmUrlPath";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+2, "SSCam_getStmUrlPath", $hash, 0);
    }
}

###########################################################################
#                         query SVS-Event information 
###########################################################################
sub SSCam_geteventlist ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_geteventlist");
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {      
        $hash->{OPMODE} = "geteventlist";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+2, "SSCam_geteventlist", $hash, 0);
    } 
}

###########################################################################
#               Enumerate motion detection parameters
###########################################################################
sub SSCam_getmotionenum ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_getmotionenum");
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {   
        $hash->{OPMODE} = "getmotionenum";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+2, "SSCam_getmotionenum", $hash, 0);
    }
    
}

##########################################################################
#             Capabilities von Kamera abrufen (Get)
##########################################################################
sub SSCam_getcapabilities ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_getcapabilities");
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                       
        $hash->{OPMODE} = "Getcapabilities";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+2, "SSCam_getcapabilities", $hash, 0);
    }
}

##########################################################################
#                      PTZ Presets abrufen (Get)
##########################################################################
sub SSCam_getptzlistpreset ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_getptzlistpreset");
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "DeviceType", "") ne "PTZ") {
        Log3($name, 4, "$name - Retrieval of Presets for $camname can't be executed - $camname is not a PTZ-Camera");
        return;
    }
    if (ReadingsVal("$name", "CapPTZTilt", "") eq "false" | ReadingsVal("$name", "CapPTZPan", "") eq "false") {
        Log3($name, 4, "$name - Retrieval of Presets for $camname can't be executed - $camname has no capability to tilt/pan");
        return;
    }
    
	if ($hash->{HELPER}{ACTIVE} eq "off") {                       
        $hash->{OPMODE} = "Getptzlistpreset";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+2, "SSCam_getptzlistpreset", $hash, 0);
    }
}

##########################################################################
#                    PTZ Patrols abrufen (Get)
##########################################################################
sub SSCam_getptzlistpatrol ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_getptzlistpatrol");
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "DeviceType", "") ne "PTZ") {
        Log3($name, 4, "$name - Retrieval of Patrols for $camname can't be executed - $camname is not a PTZ-Camera");
        return;
    }
    if (ReadingsVal("$name", "CapPTZTilt", "") eq "false" | ReadingsVal("$name", "CapPTZPan", "") eq "false") {
        Log3($name, 4, "$name - Retrieval of Patrols for $camname can't be executed - $camname has no capability to tilt/pan");
        return;
    }

    if ($hash->{HELPER}{ACTIVE} ne "on") {                        
        $hash->{OPMODE} = "Getptzlistpatrol";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+2, "SSCam_getptzlistpatrol", $hash, 0);
    }
}

#############################################################################################################################
#######    Begin Kameraoperationen mit NonblockingGet (nicht blockierender HTTP-Call)                                 #######
#############################################################################################################################
sub SSCam_getapisites($) {
   my ($hash) = @_;
   my $serveraddr  = $hash->{SERVERADDR};
   my $serverport  = $hash->{SERVERPORT};
   my $name        = $hash->{NAME};
   my $apiinfo     = $hash->{HELPER}{APIINFO};                # Info-Seite für alle API's, einzige statische Seite !
   my $apiauth     = $hash->{HELPER}{APIAUTH};            
   my $apiextrec   = $hash->{HELPER}{APIEXTREC};            
   my $apiextevt   = $hash->{HELPER}{APIEXTEVT};             
   my $apicam      = $hash->{HELPER}{APICAM};                          
   my $apitakesnap = $hash->{HELPER}{APISNAPSHOT};
   my $apiptz      = $hash->{HELPER}{APIPTZ};
   my $apipreset   = $hash->{HELPER}{APIPRESET};
   my $apisvsinfo  = $hash->{HELPER}{APISVSINFO};
   my $apicamevent = $hash->{HELPER}{APICAMEVENT};
   my $apievent    = $hash->{HELPER}{APIEVENT};
   my $apivideostm = $hash->{HELPER}{APIVIDEOSTM};
   my $apiaudiostm = $hash->{HELPER}{APIAUDIOSTM};
   my $apivideostms = $hash->{HELPER}{APIVIDEOSTMS};
   my $apistm      = $hash->{HELPER}{APISTM};
   my $apihm       = $hash->{HELPER}{APIHM};
   my $apilog      = $hash->{HELPER}{APILOG};     
   my $url;
   my $param;
  
   # API-Pfade und MaxVersions ermitteln 
   Log3($name, 4, "$name - ####################################################"); 
   Log3($name, 4, "$name - ###    start cam operation $hash->{OPMODE}          "); 
   Log3($name, 4, "$name - ####################################################"); 
   Log3($name, 4, "$name - --- Begin Function SSCam_getapisites nonblocking ---");
   
   if ($hash->{HELPER}{APIPARSET}) {
       # API-Hashwerte sind bereits gesetzt -> Abruf überspringen
	   Log3($name, 4, "$name - API hashvalues already set - ignore get apisites");
       return SSCam_checksid($hash);
   }

   my $httptimeout = AttrVal($name,"httptimeout",4);
   Log3($name, 5, "$name - HTTP-Call will be done with httptimeout-Value: $httptimeout s");

   # URL zur Abfrage der Eigenschaften der  API's
   $url = "http://$serveraddr:$serverport/webapi/query.cgi?api=$apiinfo&method=Query&version=1&query=$apiauth,$apiextrec,$apicam,$apitakesnap,$apiptz,$apipreset,$apisvsinfo,$apicamevent,$apievent,$apivideostm,$apiextevt,$apistm,$apihm,$apilog,$apiaudiostm,$apivideostms";

   Log3($name, 4, "$name - Call-Out now: $url");
   
   $param = {
               url      => $url,
               timeout  => $httptimeout,
               hash     => $hash,
               method   => "GET",
               header   => "Accept: application/json",
               callback => \&SSCam_getapisites_parse
            };
   HttpUtils_NonblockingGet ($param);  
} 

####################################################################################  
#      Auswertung Abruf apisites
####################################################################################
sub SSCam_getapisites_parse ($) {
   my ($param, $err, $myjson) = @_;
   my $hash        = $param->{hash};
   my $name        = $hash->{NAME};
   my $serveraddr  = $hash->{SERVERADDR};
   my $serverport  = $hash->{SERVERPORT};
   my $apiauth     = $hash->{HELPER}{APIAUTH};
   my $apiextrec   = $hash->{HELPER}{APIEXTREC};
   my $apiextevt   = $hash->{HELPER}{APIEXTEVT};
   my $apicam      = $hash->{HELPER}{APICAM};
   my $apitakesnap = $hash->{HELPER}{APISNAPSHOT};
   my $apiptz      = $hash->{HELPER}{APIPTZ};
   my $apipreset   = $hash->{HELPER}{APIPRESET};
   my $apisvsinfo  = $hash->{HELPER}{APISVSINFO};
   my $apicamevent = $hash->{HELPER}{APICAMEVENT};
   my $apievent    = $hash->{HELPER}{APIEVENT};
   my $apivideostm = $hash->{HELPER}{APIVIDEOSTM};
   my $apiaudiostm = $hash->{HELPER}{APIAUDIOSTM};
   my $apivideostms = $hash->{HELPER}{APIVIDEOSTMS};
   my $apistm      = $hash->{HELPER}{APISTM};
   my $apihm       = $hash->{HELPER}{APIHM};
   my $apilog      = $hash->{HELPER}{APILOG};
   my ($apicammaxver,$apicampath);
  
    if ($err ne "") {
	    # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
        Log3($name, 2, "$name - error while requesting ".$param->{url}." - $err");
       
        readingsSingleUpdate($hash, "Error", $err, 1);

        # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
        $hash->{HELPER}{ACTIVE} = "off"; 
        
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
        }
        return;
		
    } elsif ($myjson ne "") {          
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, my $success) = SSCam_evaljson($hash,$myjson);
        
        unless ($success) {
            Log3($name, 4, "$name - Data returned: $myjson");
            $hash->{HELPER}{ACTIVE} = "off";
            
            if (AttrVal($name,"debugactivetoken",0)) {
                Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
            }
            return;
        }
        
        my $data = decode_json($myjson);
        
        # Logausgabe decodierte JSON Daten
        Log3($name, 5, "$name - JSON returned: ". Dumper $data);
   
        $success = $data->{'success'};
    
        if ($success) {
            my $logstr;
                        
          # Pfad und Maxversion von "SYNO.API.Auth" ermitteln
            my $apiauthpath = $data->{'data'}->{$apiauth}->{'path'};
            $apiauthpath =~ tr/_//d if (defined($apiauthpath));
            my $apiauthmaxver = $data->{'data'}->{$apiauth}->{'maxVersion'}; 
       
            $logstr = defined($apiauthpath) ? "Path of $apiauth selected: $apiauthpath" : "Path of $apiauth undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apiauthmaxver) ? "MaxVersion of $apiauth selected: $apiauthmaxver" : "MaxVersion of $apiauth undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
       
          # Pfad und Maxversion von "SYNO.SurveillanceStation.ExternalRecording" ermitteln
            my $apiextrecpath = $data->{'data'}->{$apiextrec}->{'path'};
            $apiextrecpath =~ tr/_//d if (defined($apiextrecpath));
            my $apiextrecmaxver = $data->{'data'}->{$apiextrec}->{'maxVersion'}; 
       
   	        $logstr = defined($apiextrecpath) ? "Path of $apiextrec selected: $apiextrecpath" : "Path of $apiextrec undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apiextrecmaxver) ? "MaxVersion of $apiextrec selected: $apiextrecmaxver" : "MaxVersion of $apiextrec undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
       
          # Pfad und Maxversion von "SYNO.SurveillanceStation.Camera" ermitteln
            $apicampath = $data->{'data'}->{$apicam}->{'path'};
            $apicampath =~ tr/_//d if (defined($apicampath));
            $apicammaxver = $data->{'data'}->{$apicam}->{'maxVersion'};
                               
            $logstr = defined($apicampath) ? "Path of $apicam selected: $apicampath" : "Path of $apicam undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apiextrecmaxver) ? "MaxVersion of $apicam: $apicammaxver" : "MaxVersion of $apicam undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
       
          # Pfad und Maxversion von "SYNO.SurveillanceStation.SnapShot" ermitteln  
            my $apitakesnappath = $data->{'data'}->{$apitakesnap}->{'path'};
            $apitakesnappath =~ tr/_//d if (defined($apitakesnappath));
            my $apitakesnapmaxver = $data->{'data'}->{$apitakesnap}->{'maxVersion'};
                            
            $logstr = defined($apitakesnappath) ? "Path of $apitakesnap selected: $apitakesnappath" : "Path of $apitakesnap undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apitakesnapmaxver) ? "MaxVersion of $apitakesnap: $apitakesnapmaxver" : "MaxVersion of $apitakesnap undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");

          # Pfad und Maxversion von "SYNO.SurveillanceStation.PTZ" ermitteln 
            my $apiptzpath = $data->{'data'}->{$apiptz}->{'path'};
            $apiptzpath =~ tr/_//d if (defined($apiptzpath));
            my $apiptzmaxver = $data->{'data'}->{$apiptz}->{'maxVersion'};
                            
            $logstr = defined($apiptzpath) ? "Path of $apiptz selected: $apiptzpath" : "Path of $apiptz undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apiptzmaxver) ? "MaxVersion of $apiptz: $apiptzmaxver" : "MaxVersion of $apiptz undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");	

          # Pfad und Maxversion von "SYNO.SurveillanceStation.PTZ.Preset" ermitteln 
            my $apipresetpath = $data->{'data'}->{$apipreset}->{'path'};
            $apipresetpath =~ tr/_//d if (defined($apipresetpath));
            my $apipresetmaxver = $data->{'data'}->{$apipreset}->{'maxVersion'};
                            
            $logstr = defined($apipresetpath) ? "Path of $apipreset selected: $apipresetpath" : "Path of $apipreset undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apipresetmaxver) ? "MaxVersion of $apipreset: $apipresetmaxver" : "MaxVersion of $apipreset undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");				
			
          # Pfad und Maxversion von "SYNO.SurveillanceStation.Info" ermitteln
            my $apisvsinfopath = $data->{'data'}->{$apisvsinfo}->{'path'};
            $apisvsinfopath =~ tr/_//d if (defined($apisvsinfopath));
            my $apisvsinfomaxver = $data->{'data'}->{$apisvsinfo}->{'maxVersion'};
                            
            $logstr = defined($apisvsinfopath) ? "Path of $apisvsinfo selected: $apisvsinfopath" : "Path of $apisvsinfo undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apisvsinfomaxver) ? "MaxVersion of $apisvsinfo: $apisvsinfomaxver" : "MaxVersion of $apisvsinfo undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
                        
          # Pfad und Maxversion von "SYNO.Surveillance.Camera.Event" ermitteln    
            my $apicameventpath = $data->{'data'}->{$apicamevent}->{'path'};
            $apicameventpath =~ tr/_//d if (defined($apicameventpath));
            my $apicameventmaxver = $data->{'data'}->{$apicamevent}->{'maxVersion'};
                            
            $logstr = defined($apicameventpath) ? "Path of $apicamevent selected: $apicameventpath" : "Path of $apicamevent undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apicameventmaxver) ? "MaxVersion of $apicamevent: $apicameventmaxver" : "MaxVersion of $apicamevent undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
                        
          # Pfad und Maxversion von "SYNO.Surveillance.Event" ermitteln     
            my $apieventpath = $data->{'data'}->{$apievent}->{'path'};
            $apieventpath =~ tr/_//d if (defined($apieventpath));
            my $apieventmaxver = $data->{'data'}->{$apievent}->{'maxVersion'};
                            
            $logstr = defined($apieventpath) ? "Path of $apievent selected: $apieventpath" : "Path of $apievent undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apieventmaxver) ? "MaxVersion of $apievent: $apieventmaxver" : "MaxVersion of $apievent undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
                        
          # Pfad und Maxversion von "SYNO.Surveillance.VideoStream" ermitteln
            my $apivideostmpath = $data->{'data'}->{$apivideostm}->{'path'};
            $apivideostmpath =~ tr/_//d if (defined($apivideostmpath));
            my $apivideostmmaxver = $data->{'data'}->{$apivideostm}->{'maxVersion'};
                            
            $logstr = defined($apivideostmpath) ? "Path of $apivideostm selected: $apivideostmpath" : "Path of $apivideostm undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apivideostmmaxver) ? "MaxVersion of $apivideostm: $apivideostmmaxver" : "MaxVersion of $apivideostm undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
                        
          # Pfad und Maxversion von "SYNO.SurveillanceStation.ExternalEvent" ermitteln
            my $apiextevtpath = $data->{'data'}->{$apiextevt}->{'path'};
            $apiextevtpath =~ tr/_//d if (defined($apiextevtpath));
            my $apiextevtmaxver = $data->{'data'}->{$apiextevt}->{'maxVersion'}; 
       
            $logstr = defined($apiextevtpath) ? "Path of $apiextevt selected: $apiextevtpath" : "Path of $apiextevt undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apiextevtmaxver) ? "MaxVersion of $apiextevt selected: $apiextevtmaxver" : "MaxVersion of $apiextevt undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
                        
          # Pfad und Maxversion von "SYNO.SurveillanceStation.Streaming" ermitteln
            my $apistmpath = $data->{'data'}->{$apistm}->{'path'};
            $apistmpath =~ tr/_//d if (defined($apistmpath));
            my $apistmmaxver = $data->{'data'}->{$apistm}->{'maxVersion'}; 
       
            $logstr = defined($apistmpath) ? "Path of $apistm selected: $apistmpath" : "Path of $apistm undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apistmmaxver) ? "MaxVersion of $apistm selected: $apistmmaxver" : "MaxVersion of $apistm undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");

          # Pfad und Maxversion von "SYNO.SurveillanceStation.HomeMode" ermitteln
            my $apihmpath = $data->{'data'}->{$apihm}->{'path'};
            $apihmpath =~ tr/_//d if (defined($apihmpath));
            my $apihmmaxver = $data->{'data'}->{$apihm}->{'maxVersion'}; 
       
            $logstr = defined($apihmpath) ? "Path of $apihm selected: $apihmpath" : "Path of $apihm undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apihmmaxver) ? "MaxVersion of $apihm selected: $apihmmaxver" : "MaxVersion of $apihm undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
        
          # Pfad und Maxversion von "SYNO.SurveillanceStation.Log" ermitteln
            my $apilogpath = $data->{'data'}->{$apilog}->{'path'};
            $apilogpath =~ tr/_//d if (defined($apilogpath));
            my $apilogmaxver = $data->{'data'}->{$apilog}->{'maxVersion'}; 
       
            $logstr = defined($apilogpath) ? "Path of $apilog selected: $apilogpath" : "Path of $apilog undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apilogmaxver) ? "MaxVersion of $apilog selected: $apilogmaxver" : "MaxVersion of $apilog undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
			
          # Pfad und Maxversion von "SYNO.SurveillanceStation.AudioStream" ermitteln
            my $apiaudiostmpath = $data->{'data'}->{$apiaudiostm}->{'path'};
            $apiaudiostmpath =~ tr/_//d if (defined($apiaudiostmpath));
            my $apiaudiostmmaxver = $data->{'data'}->{$apiaudiostm}->{'maxVersion'}; 
       
            $logstr = defined($apiaudiostmpath) ? "Path of $apiaudiostm selected: $apiaudiostmpath" : "Path of $apiaudiostm undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apiaudiostmmaxver) ? "MaxVersion of $apiaudiostm selected: $apiaudiostmmaxver" : "MaxVersion of $apiaudiostm undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            
          # Pfad und Maxversion von "SYNO.SurveillanceStation.VideoStream" ermitteln
            my $apivideostmspath = $data->{'data'}->{$apivideostms}->{'path'};
            $apivideostmspath =~ tr/_//d if (defined($apivideostmspath));
            my $apivideostmsmaxver = $data->{'data'}->{$apivideostms}->{'maxVersion'}; 
       
            $logstr = defined($apivideostmspath) ? "Path of $apivideostms selected: $apivideostmspath" : "Path of $apivideostms undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apivideostmsmaxver) ? "MaxVersion of $apivideostms selected: $apivideostmsmaxver" : "MaxVersion of $apivideostms undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
		
            # aktuelle oder simulierte SVS-Version für Fallentscheidung setzen
            no warnings 'uninitialized'; 
            my $major = $hash->{HELPER}{SVSVERSION}{MAJOR};
            my $minor = $hash->{HELPER}{SVSVERSION}{MINOR};
			my $small = $hash->{HELPER}{SVSVERSION}{SMALL};
            my $build = $hash->{HELPER}{SVSVERSION}{BUILD}; 
            my $actvs = $major.$minor.$small.$build;
            Log3($name, 4, "$name - installed SVS version is: $actvs");
            use warnings; 
                        
            if(AttrVal($name,"simu_SVSversion",0)) {
                my @vl = split (/\.|-/,AttrVal($name, "simu_SVSversion", ""));
                $actvs = $vl[0];
                $actvs .= $vl[1];
                $actvs .= ($vl[2] =~ /\d/)?$vl[2]."xxxx":$vl[2];
				$actvs .= "-simu";
            }
			
            # Downgrades für nicht kompatible API-Versionen
			# hier nur nutzen wenn API zentral downgraded werden soll
            # In den neueren API-Upgrades werden nur einzelne Funktionen auf eine höhere API-Version gezogen
            # -> diese Steuerung erfolgt in den einzelnen Funktionsaufrufen in SSCam_camop			
            Log3($name, 4, "$name - ------- Begin of adaption section -------");
            
			#$apiptzmaxver = 4;
            #Log3($name, 4, "$name - MaxVersion of $apiptz adapted to: $apiptzmaxver");
            #$apicammaxver = 8;
            #Log3($name, 4, "$name - MaxVersion of $apicam adapted to: $apicammaxver");
            
			Log3($name, 4, "$name - ------- End of adaption section -------");
			
                        			
            # Simulation anderer SVS-Versionen
            Log3($name, 4, "$name - ------- Begin of simulation section -------");
            
			if (AttrVal($name, "simu_SVSversion", undef)) {
                Log3($name, 4, "$name - SVS version $actvs will be simulated");
                if ($actvs =~ /^71/) {
                    $apicammaxver = 8;
                    Log3($name, 4, "$name - MaxVersion of $apicam adapted to: $apicammaxver");
                    $apiauthmaxver = 4;
                    Log3($name, 4, "$name - MaxVersion of $apiauth adapted to: $apiauthmaxver");
                    $apiextrecmaxver = 2;
                    Log3($name, 4, "$name - MaxVersion of $apiextrec adapted to: $apiextrecmaxver");
                    $apiptzmaxver    = 4;
                    Log3($name, 4, "$name - MaxVersion of $apiptz adapted to: $apiptzmaxver");
                } elsif ($actvs =~ /^72/) {
                    $apicammaxver = 8;
                    Log3($name, 4, "$name - MaxVersion of $apicam adapted to: $apicammaxver");
                    $apiauthmaxver = 6;
                    Log3($name, 4, "$name - MaxVersion of $apiauth adapted to: $apiauthmaxver");
                    $apiextrecmaxver = 3;
                    Log3($name, 4, "$name - MaxVersion of $apiextrec adapted to: $apiextrecmaxver");
                    $apiptzmaxver    = 5;
                    Log3($name, 4, "$name - MaxVersion of $apiptz adapted to: $apiptzmaxver");                               
                } elsif ($actvs =~ /^800/) {
                    $apicammaxver = 9;
                    Log3($name, 4, "$name - MaxVersion of $apicam adapted to: $apicammaxver");
                    $apiauthmaxver = 6;
                    Log3($name, 4, "$name - MaxVersion of $apiauth adapted to: $apiauthmaxver");
                    $apiextrecmaxver = 3;
                    Log3($name, 4, "$name - MaxVersion of $apiextrec adapted to: $apiextrecmaxver");
                    $apiptzmaxver    = 5;
                    Log3($name, 4, "$name - MaxVersion of $apiptz adapted to: $apiptzmaxver");                               
                }
            
			} else {
                Log3($name, 4, "$name - no simulations done !");
            } 
            Log3($name, 4, "$name - ------- End of simulation section -------");  
			       
            # ermittelte Werte in $hash einfügen
            $hash->{HELPER}{APIAUTHPATH}        = $apiauthpath;
            $hash->{HELPER}{APIAUTHMAXVER}      = $apiauthmaxver;
            $hash->{HELPER}{APIEXTRECPATH}      = $apiextrecpath;
            $hash->{HELPER}{APIEXTRECMAXVER}    = $apiextrecmaxver;
            $hash->{HELPER}{APICAMPATH}         = $apicampath;
            $hash->{HELPER}{APICAMMAXVER}       = $apicammaxver;
            $hash->{HELPER}{APITAKESNAPPATH}    = $apitakesnappath;
            $hash->{HELPER}{APITAKESNAPMAXVER}  = $apitakesnapmaxver;
            $hash->{HELPER}{APIPTZPATH}         = $apiptzpath;
            $hash->{HELPER}{APIPTZMAXVER}       = $apiptzmaxver;
            $hash->{HELPER}{APIPRESETPATH}      = $apipresetpath;
            $hash->{HELPER}{APIPRESETMAXVER}    = $apipresetmaxver;
            $hash->{HELPER}{APISVSINFOPATH}     = $apisvsinfopath;
            $hash->{HELPER}{APISVSINFOMAXVER}   = $apisvsinfomaxver;
            $hash->{HELPER}{APICAMEVENTPATH}    = $apicameventpath;
            $hash->{HELPER}{APICAMEVENTMAXVER}  = $apicameventmaxver;
            $hash->{HELPER}{APIEVENTPATH}       = $apieventpath;
            $hash->{HELPER}{APIEVENTMAXVER}     = $apieventmaxver;
            $hash->{HELPER}{APIVIDEOSTMPATH}    = $apivideostmpath;
            $hash->{HELPER}{APIVIDEOSTMMAXVER}  = $apivideostmmaxver;      
            $hash->{HELPER}{APIAUDIOSTMPATH}    = $apiaudiostmpath;
            $hash->{HELPER}{APIAUDIOSTMMAXVER}  = $apiaudiostmmaxver;   
            $hash->{HELPER}{APIEXTEVTPATH}      = $apiextevtpath;
            $hash->{HELPER}{APIEXTEVTMAXVER}    = $apiextevtmaxver;
            $hash->{HELPER}{APISTMPATH}         = $apistmpath;
            $hash->{HELPER}{APISTMMAXVER}       = $apistmmaxver;
            $hash->{HELPER}{APIHMPATH}          = $apihmpath;
            $hash->{HELPER}{APIHMMAXVER}        = $apihmmaxver;
            $hash->{HELPER}{APILOGPATH}         = $apilogpath;
            $hash->{HELPER}{APILOGMAXVER}       = $apilogmaxver;
            $hash->{HELPER}{APIVIDEOSTMSPATH}   = $apivideostmspath;
            $hash->{HELPER}{APIVIDEOSTMSMAXVER} = $apivideostmsmaxver;
            
       
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode","none");
            readingsBulkUpdate($hash,"Error","none");
            readingsEndUpdate($hash,1);
			
			# API Hash values sind gesetzt
			$hash->{HELPER}{APIPARSET} = 1;
                        
        } else {
            my $error = "couldn't call API-Infosite";
       
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode","none");
            readingsBulkUpdate($hash,"Error",$error);
            readingsEndUpdate($hash, 1);

            Log3($name, 2, "$name - ERROR - the API-Query couldn't be executed successfully");                    
                        
            # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
            $hash->{HELPER}{ACTIVE} = "off"; 
                        
            if (AttrVal($name,"debugactivetoken",0)) {
                Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
            }
            return;
        }
	}
return SSCam_checksid($hash);
}

#############################################################################################
#                        Check ob Session ID gesetzt ist - ggf. login
#############################################################################################
sub SSCam_checksid ($) {  
   my ($hash) = @_;
   my $name   = $hash->{NAME};
   my $subref;
   
   if(SSCam_IsModelCam($hash)) {
       # Folgefunktion wenn Cam-Device
       $subref = "SSCam_getcamid";
   } else {
       # Folgefunktion wenn SVS-Device
       $subref = "SSCam_camop";
   }
   
   # SID holen bzw. login
   my $sid = $hash->{HELPER}{SID};
   if(!$sid) {
       Log3($name, 3, "$name - no session ID found - get new one");
	   SSCam_login($hash,$subref);
	   return;
   }
   
   if(SSCam_IsModelCam($hash)) {
       # Normalverarbeitung für Cams
       return SSCam_getcamid($hash);
   } else {
       # Sprung zu SSCam_camop wenn SVS Device
       return SSCam_camop($hash);
   }

}

#############################################################################################
#                             Abruf der installierten Cams
#############################################################################################
sub SSCam_getcamid ($) {  
   my ($hash)       = @_;
   my $name         = $hash->{NAME};
   my $serveraddr   = $hash->{SERVERADDR};
   my $serverport   = $hash->{SERVERPORT};
   my $apicam       = $hash->{HELPER}{APICAM};
   my $apicampath   = $hash->{HELPER}{APICAMPATH};
   my $apicammaxver = $hash->{HELPER}{APICAMMAXVER};
   my $sid          = $hash->{HELPER}{SID};
   
   my $url;
    
   # die Kamera-Id wird aus dem Kameranamen (Surveillance Station) ermittelt
   Log3($name, 4, "$name - --- Begin Function SSCam_getcamid nonblocking ---");
	
   if ($hash->{CAMID}) {
       # Camid ist bereits ermittelt -> Abruf überspringen
	   Log3($name, 4, "$name - CAMID already set - ignore get camid");
       return SSCam_camop($hash);
   }
    
   my $httptimeout = AttrVal($name,"httptimeout", 4);
   Log3($name, 5, "$name - HTTP-Call will be done with httptimeout-Value: $httptimeout s");
  
   $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=List&basic=true&streamInfo=true&camStm=true&_sid=\"$sid\"";
   if ($apicammaxver >= 9) {
       $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=\"List\"&basic=true&streamInfo=true&camStm=0&_sid=\"$sid\"";
   }
 
   Log3($name, 4, "$name - Call-Out now: $url");
  
   my $param = {
               url      => $url,
               timeout  => $httptimeout,
               hash     => $hash,
               method   => "GET",
               header   => "Accept: application/json",
               callback => \&SSCam_getcamid_parse
               };
   
   HttpUtils_NonblockingGet($param);
}  

#############################################################################################
#               Auswertung installierte Cams, Selektion Cam , Ausführung Operation
#############################################################################################
sub SSCam_getcamid_parse ($) {  
   my ($param, $err, $myjson) = @_;
   my $hash              = $param->{hash};
   my $name              = $hash->{NAME};
   my $camname           = $hash->{CAMNAME};
   my $apicammaxver      = $hash->{HELPER}{APICAMMAXVER};  
   my ($data,$success,$error,$errorcode,$camid);
   my ($i,$n,$id);
   my %allcams;
  
   if ($err ne "") {
       # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
       Log3($name, 2, "$name - error while requesting ".$param->{url}." - $err");
       
	   readingsSingleUpdate($hash, "Error", $err, 1);
       return SSCam_login($hash,'SSCam_getapisites');
   
   } elsif ($myjson ne "") {
       # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)   
       # evaluiere ob Daten im JSON-Format empfangen wurden, Achtung: sehr viele Daten mit verbose=5
       ($hash, $success) = SSCam_evaljson($hash,$myjson);
        
       unless ($success) {
           Log3($name, 4, "$name - Data returned: ".$myjson);
		   
           $hash->{HELPER}{ACTIVE} = "off";
           if (AttrVal($name,"debugactivetoken",0)) {
               Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
           }
           return; 
       }
        
       $data = decode_json($myjson);
        
       # lesbare Ausgabe der decodierten JSON-Daten
       Log3($name, 5, "$name - JSON returned: ". Dumper $data);
   
       $success = $data->{'success'};
                
       if ($success) {
           # die Liste aller Kameras konnte ausgelesen werden	   
           $i = 0;
         
           # Namen aller installierten Kameras mit Id's in Assoziatives Array einlesen
           %allcams = ();
           while ($data->{'data'}->{'cameras'}->[$i]) {
               if ($apicammaxver <= 8) {
			       $n = $data->{'data'}->{'cameras'}->[$i]->{'name'};
			   } else {
				   $n = $data->{'data'}->{'cameras'}->[$i]->{'newName'};  # Änderung ab SVS 8.0.0
			   }
               $id = $data->{'data'}->{'cameras'}->[$i]->{'id'};
               $allcams{"$n"} = "$id";
               $i += 1;
           }
             
           # Ist der gesuchte Kameraname im Hash enhalten (in SVS eingerichtet ?)
           if (exists($allcams{$camname})) {
               $camid = $allcams{$camname};
               # in hash eintragen
               $hash->{CAMID} = $camid;
                 
               # Logausgabe
               Log3($name, 4, "$name - Detection Camid successful - $camname ID: $camid");
           
		   } else {
               # Kameraname nicht gefunden, id = ""
               # Setreading 
               readingsBeginUpdate($hash);
               readingsBulkUpdate($hash,"Errorcode","none");
               readingsBulkUpdate($hash,"Error","Camera(ID) not found in Surveillance Station");
               readingsEndUpdate($hash, 1);
                                  
               # Logausgabe
               Log3($name, 2, "$name - ERROR - Cameraname $camname wasn't found in Surveillance Station. Check Userrights, Cameraname and Spelling");
               			   
               $hash->{HELPER}{ACTIVE} = "off";
               if (AttrVal($name,"debugactivetoken",0)) {
                   Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
               }
               return;
           }
      
	  } else {
           # Errorcode aus JSON ermitteln
           $errorcode = $data->{'error'}->{'code'};

           # Fehlertext zum Errorcode ermitteln
           $error = SSCam_experror($hash,$errorcode);
       
           readingsBeginUpdate($hash);
           readingsBulkUpdate($hash,"Errorcode",$errorcode);
           readingsBulkUpdate($hash,"Error",$error);
           readingsEndUpdate($hash, 1);
           
		   if ($errorcode =~ /(105|401)/) {
		       # neue Login-Versuche
			   Log3($name, 2, "$name - ERROR - $errorcode - $error -> try new login");
		       return SSCam_login($hash,'SSCam_getapisites');
		   
		   } else {
		       # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
               $hash->{HELPER}{ACTIVE} = "off";
               if (AttrVal($name,"debugactivetoken",0)) {
                   Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
               }
			   Log3($name, 2, "$name - ERROR - ID of Camera $camname couldn't be selected. Errorcode: $errorcode - $error");
               return;
		   }
      }
  }
return SSCam_camop($hash);
}

#############################################################################################
#                                     Ausführung Operation
#############################################################################################
sub SSCam_camop ($) {  
   my ($hash) = @_;
   my $name               = $hash->{NAME};
   my $serveraddr         = $hash->{SERVERADDR};
   my $serverport         = $hash->{SERVERPORT};
   my $apicam             = $hash->{HELPER}{APICAM};
   my $apicampath         = $hash->{HELPER}{APICAMPATH};
   my $apicammaxver       = $hash->{HELPER}{APICAMMAXVER};  
   my $apiextrec          = $hash->{HELPER}{APIEXTREC};
   my $apiextrecpath      = $hash->{HELPER}{APIEXTRECPATH};
   my $apiextrecmaxver    = $hash->{HELPER}{APIEXTRECMAXVER};
   my $apiextevt          = $hash->{HELPER}{APIEXTEVT};
   my $apiextevtpath      = $hash->{HELPER}{APIEXTEVTPATH};
   my $apiextevtmaxver    = $hash->{HELPER}{APIEXTEVTMAXVER};
   my $apitakesnap        = $hash->{HELPER}{APISNAPSHOT};
   my $apitakesnappath    = $hash->{HELPER}{APITAKESNAPPATH};
   my $apitakesnapmaxver  = $hash->{HELPER}{APITAKESNAPMAXVER};
   my $apiptz             = $hash->{HELPER}{APIPTZ};
   my $apiptzpath         = $hash->{HELPER}{APIPTZPATH};
   my $apiptzmaxver       = $hash->{HELPER}{APIPTZMAXVER};
   my $apipreset          = $hash->{HELPER}{APIPRESET};
   my $apipresetpath      = $hash->{HELPER}{APIPRESETPATH};
   my $apipresetmaxver    = $hash->{HELPER}{APIPRESETMAXVER};
   my $apisvsinfo         = $hash->{HELPER}{APISVSINFO};
   my $apisvsinfopath     = $hash->{HELPER}{APISVSINFOPATH};
   my $apisvsinfomaxver   = $hash->{HELPER}{APISVSINFOMAXVER};
   my $apicamevent        = $hash->{HELPER}{APICAMEVENT};
   my $apicameventpath    = $hash->{HELPER}{APICAMEVENTPATH};
   my $apicameventmaxver  = $hash->{HELPER}{APICAMEVENTMAXVER};
   my $apievent           = $hash->{HELPER}{APIEVENT};
   my $apieventpath       = $hash->{HELPER}{APIEVENTPATH};
   my $apieventmaxver     = $hash->{HELPER}{APIEVENTMAXVER};
   my $apivideostm        = $hash->{HELPER}{APIVIDEOSTM};
   my $apivideostmpath    = $hash->{HELPER}{APIVIDEOSTMPATH};
   my $apivideostmmaxver  = $hash->{HELPER}{APIVIDEOSTMMAXVER};  
   my $apiaudiostm        = $hash->{HELPER}{APIAUDIOSTM};
   my $apiaudiostmpath    = $hash->{HELPER}{APIAUDIOSTMPATH};
   my $apiaudiostmmaxver  = $hash->{HELPER}{APIAUDIOSTMMAXVER};   
   my $apistm             = $hash->{HELPER}{APISTM};
   my $apistmpath         = $hash->{HELPER}{APISTMPATH};
   my $apistmmaxver       = $hash->{HELPER}{APISTMMAXVER};
   my $apihm              = $hash->{HELPER}{APIHM};
   my $apihmpath          = $hash->{HELPER}{APIHMPATH};
   my $apihmmaxver        = $hash->{HELPER}{APIHMMAXVER};
   my $apilog             = $hash->{HELPER}{APILOG};
   my $apilogpath         = $hash->{HELPER}{APILOGPATH};
   my $apilogmaxver       = $hash->{HELPER}{APILOGMAXVER};
   my $apivideostms       = $hash->{HELPER}{APIVIDEOSTMS};
   my $apivideostmspath   = $hash->{HELPER}{APIVIDEOSTMSPATH};
   my $apivideostmsmaxver = $hash->{HELPER}{APIVIDEOSTMSMAXVER};
   my $sid                = $hash->{HELPER}{SID};
   my $OpMode             = $hash->{OPMODE};
   my $camid              = $hash->{CAMID};
   my ($exturl,$winname,$attr,$room,$param);
   my ($url,$snapid,$httptimeout,$expmode,$motdetsc);
       
   Log3($name, 4, "$name - --- Begin Function $OpMode nonblocking ---");

   $httptimeout = AttrVal($name, "httptimeout", 4);
   $httptimeout = $httptimeout+90 if($OpMode eq "setoptpar");   # setzen der Optimierungsparameter dauert lange !
   
   Log3($name, 5, "$name - HTTP-Call will be done with httptimeout-Value: $httptimeout s");
   
   if ($OpMode eq "Start") {
      $url = "http://$serveraddr:$serverport/webapi/$apiextrecpath?api=$apiextrec&method=Record&version=$apiextrecmaxver&cameraId=$camid&action=start&_sid=\"$sid\"";
      if($apiextrecmaxver >= 3) {
          $url = "http://$serveraddr:$serverport/webapi/$apiextrecpath?api=$apiextrec&method=Record&version=$apiextrecmaxver&cameraIds=$camid&action=start&_sid=\"$sid\"";
      }
   } elsif ($OpMode eq "Stop") {
      $url = "http://$serveraddr:$serverport/webapi/$apiextrecpath?api=$apiextrec&method=Record&version=$apiextrecmaxver&cameraId=$camid&action=stop&_sid=\"$sid\"";
      if($apiextrecmaxver >= 3) {
          $url = "http://$serveraddr:$serverport/webapi/$apiextrecpath?api=$apiextrec&method=Record&version=$apiextrecmaxver&cameraIds=$camid&action=stop&_sid=\"$sid\"";
      }   
   
   } elsif ($OpMode eq "Snap") {
      # ein Schnappschuß wird ausgelöst
      $url = "http://$serveraddr:$serverport/webapi/$apitakesnappath?api=\"$apitakesnap\"&dsId=\"0\"&method=\"TakeSnapshot\"&version=\"$apitakesnapmaxver\"&camId=\"$camid\"&blSave=\"true\"&_sid=\"$sid\"";
      readingsSingleUpdate($hash,"state", "snap", 1); 
      readingsSingleUpdate($hash, "LastSnapId", "", 0);
   
   } elsif ($OpMode eq "getsnapinfo" || $OpMode eq "getsnapgallery") {
      # Informationen über den letzten oder mehrere Schnappschüsse ermitteln
	  my $limit   = $hash->{HELPER}{SNAPLIMIT};
	  my $imgsize = $hash->{HELPER}{SNAPIMGSIZE};
	  my $keyword = $hash->{HELPER}{KEYWORD};
	  Log3($name,4, "$name - Call getsnapinfo with params: Image numbers => $limit, Image size => $imgsize, Keyword => $keyword");
      $url = "http://$serveraddr:$serverport/webapi/$apitakesnappath?api=\"$apitakesnap\"&method=\"List\"&version=\"$apitakesnapmaxver\"&keyword=\"$keyword\"&imgSize=\"$imgsize\"&limit=\"$limit\"&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "getsnapfilename") {
      # der Filename der aktuellen Schnappschuß-ID wird ermittelt
      $snapid = ReadingsVal("$name", "LastSnapId", " ");
      Log3($name, 4, "$name - Get filename of present Snap-ID $snapid");
      $url = "http://$serveraddr:$serverport/webapi/$apitakesnappath?api=\"$apitakesnap\"&method=\"List\"&version=\"$apitakesnapmaxver\"&imgSize=\"0\"&idList=\"$snapid\"&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "gopreset") {
      # Preset wird angefahren
      $apiptzmaxver = ($apiptzmaxver >= 5)?4:$apiptzmaxver;
	  $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"GoPreset\"&position=\"$hash->{HELPER}{ALLPRESETS}{$hash->{HELPER}{GOPRESETNAME}}\"&cameraId=\"$camid\"&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "getPresets") {
      # Liste der Presets abrufen
	  $url = "http://$serveraddr:$serverport/webapi/$apipresetpath?api=\"$apipreset\"&version=\"$apipresetmaxver\"&method=\"Enum\"&cameraId=\"$camid\"&_sid=\"$sid\""; 
   
   } elsif ($OpMode eq "setPreset") {
      # einen Preset setzen
      my $pnumber = $hash->{HELPER}{PNUMBER};
      my $pname   = $hash->{HELPER}{PNAME};
      my $pspeed  = $hash->{HELPER}{PSPEED};
      if ($pspeed) {
	      $url = "http://$serveraddr:$serverport/webapi/$apipresetpath?api=\"$apipreset\"&version=\"$apipresetmaxver\"&method=\"SetPreset\"&position=$pnumber&name=\"$pname\"&speed=\"$pspeed\"&cameraId=\"$camid\"&_sid=\"$sid\""; 
      } else {
	      $url = "http://$serveraddr:$serverport/webapi/$apipresetpath?api=\"$apipreset\"&version=\"$apipresetmaxver\"&method=\"SetPreset\"&position=$pnumber&name=\"$pname\"&cameraId=\"$camid\"&_sid=\"$sid\"";       
      }
      
   } elsif ($OpMode eq "delPreset") {
      # einen Preset löschen
	  $url = "http://$serveraddr:$serverport/webapi/$apipresetpath?api=\"$apipreset\"&version=\"$apipresetmaxver\"&method=\"DelPreset\"&position=\"$hash->{HELPER}{ALLPRESETS}{$hash->{HELPER}{DELPRESETNAME}}\"&cameraId=\"$camid\"&_sid=\"$sid\""; 
   
   } elsif ($OpMode eq "setHome") {
      # aktuelle Position als Home setzen
      if($hash->{HELPER}{SETHOME} eq "---currentPosition---") {
          $url = "http://$serveraddr:$serverport/webapi/$apipresetpath?api=\"$apipreset\"&version=\"$apipresetmaxver\"&method=\"SetHome\"&cameraId=\"$camid\"&_sid=\"$sid\""; 
      } else {
          my $bindpos = $hash->{HELPER}{ALLPRESETS}{$hash->{HELPER}{SETHOME}};
	      $url = "http://$serveraddr:$serverport/webapi/$apipresetpath?api=\"$apipreset\"&version=\"$apipresetmaxver\"&method=\"SetHome\"&bindPosition=\"$bindpos\"&cameraId=\"$camid\"&_sid=\"$sid\""; 
      }
      
   } elsif ($OpMode eq "startTrack") {
      # Object Tracking einschalten
	  $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"ObjTracking\"&cameraId=\"$camid\"&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "stopTrack") {
      # Object Tracking stoppen
	  $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"ObjTracking\"&moveType=\"Stop\"&cameraId=\"$camid\"&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "runpatrol") {
      # eine Überwachungstour starten
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"RunPatrol\"&patrolId=\"$hash->{HELPER}{ALLPATROLS}{$hash->{HELPER}{GOPATROLNAME}}\"&cameraId=\"$camid\"&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "goabsptz") {
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"AbsPtz\"&cameraId=\"$camid\"&posX=\"$hash->{HELPER}{GOPTZPOSX}\"&posY=\"$hash->{HELPER}{GOPTZPOSY}\"&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "movestart") {
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"Move\"&cameraId=\"$camid\"&direction=\"$hash->{HELPER}{GOMOVEDIR}\"&speed=\"3\"&moveType=\"Start\"&_sid=\"$sid\"";
      
   } elsif ($OpMode eq "movestop") {
      Log3($name, 4, "$name - Stop Camera $hash->{CAMNAME} moving to direction \"$hash->{HELPER}{GOMOVEDIR}\" now");
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"Move\"&cameraId=\"$camid\"&direction=\"$hash->{HELPER}{GOMOVEDIR}\"&moveType=\"Stop\"&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "Enable") {
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=Enable&cameraIds=$camid&_sid=\"$sid\"";     
      if($apicammaxver >= 9) {
	      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&version=$apicammaxver&method=\"Enable\"&idList=\"$camid\"&_sid=\"$sid\"";     
	  }
   
   } elsif ($OpMode eq "Disable") {
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=Disable&cameraIds=$camid&_sid=\"$sid\"";     
      if($apicammaxver >= 9) {
	      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&version=$apicammaxver&method=\"Disable\"&idList=\"$camid\"&_sid=\"$sid\"";     
	  }
	  
   } elsif ($OpMode eq "sethomemode") {
      my $sw = $hash->{HELPER}{HOMEMODE};     # HomeMode on,off
	  $sw  = ($sw eq "on")?"true":"false";
      $url = "http://$serveraddr:$serverport/webapi/$apihmpath?on=$sw&api=$apihm&method=Switch&version=$apihmmaxver&_sid=\"$sid\"";     
   
   } elsif ($OpMode eq "gethomemodestate") {
      $url = "http://$serveraddr:$serverport/webapi/$apihmpath?api=$apihm&method=GetInfo&version=$apihmmaxver&_sid=\"$sid\"";     
   
   } elsif ($OpMode eq "getsvslog") {
      my $sev = $hash->{HELPER}{LISTLOGSEVERITY}?$hash->{HELPER}{LISTLOGSEVERITY}:"";
	  my $lim = $hash->{HELPER}{LISTLOGLIMIT}?$hash->{HELPER}{LISTLOGLIMIT}:0;
	  my $mco = $hash->{HELPER}{LISTLOGMATCH}?$hash->{HELPER}{LISTLOGMATCH}:"";
	  $mco = SSCam_IsModelCam($hash)?$hash->{CAMNAME}:$mco;
	  $lim = 1 if(!$hash->{HELPER}{CL}{1});  # Datenabruf im Hintergrund
	  $sev = (lc($sev) =~ /error/)?3:(lc($sev) =~ /warning/)?2:(lc($sev) =~ /info/)?1:"";
	  
	  no warnings 'uninitialized'; 
      Log3($name,4, "$name - get logList with params: severity => $hash->{HELPER}{LISTLOGSEVERITY}, limit => $lim, matchcode => $hash->{HELPER}{LISTLOGMATCH}");
      use warnings;
	  
	  $url = "http://$serveraddr:$serverport/webapi/$apilogpath?api=$apilog&version=\"2\"&method=\"List\"&time2String=\"no\"&level=\"$sev\"&limit=\"$lim\"&keyword=\"$mco\"&_sid=\"$sid\"";     

	  delete($hash->{HELPER}{LISTLOGSEVERITY});
	  delete($hash->{HELPER}{LISTLOGLIMIT});
	  delete($hash->{HELPER}{LISTLOGMATCH});
	  
   } elsif ($OpMode eq "getsvsinfo") {
      $url = "http://$serveraddr:$serverport/webapi/$apisvsinfopath?api=\"$apisvsinfo\"&version=\"$apisvsinfomaxver\"&method=\"GetInfo\"&_sid=\"$sid\"";   
   
   } elsif ($OpMode eq "setoptpar") {
      my $mirr = $hash->{HELPER}{MIRROR}?$hash->{HELPER}{MIRROR}:ReadingsVal("$name","CamVideoMirror","");
	  my $flip = $hash->{HELPER}{FLIP}?$hash->{HELPER}{FLIP}:ReadingsVal("$name","CamVideoFlip","");
	  my $rot  = $hash->{HELPER}{ROTATE}?$hash->{HELPER}{ROTATE}:ReadingsVal("$name","CamVideoRotate","");
	  my $ntp  = $hash->{HELPER}{NTPSERV}?$hash->{HELPER}{NTPSERV}:ReadingsVal("$name","CamNTPServer","");
	  my $clst = $hash->{HELPER}{CHKLIST}?$hash->{HELPER}{CHKLIST}:"";
	  $apicammaxver = ($apicammaxver >= 9)?8:$apicammaxver;
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&version=\"$apicammaxver\"&method=\"SaveOptimizeParam\"&vdoMirror=$mirr&vdoRotation=$rot&vdoFlip=$flip&timeServer=\"$ntp\"&camParamChkList=$clst&cameraIds=\"$camid\"&_sid=\"$sid\"";  
             
   } elsif ($OpMode eq "Getcaminfo") {
      $apicammaxver = ($apicammaxver >= 9)?8:$apicammaxver;
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&version=\"$apicammaxver\"&method=\"GetInfo\"&cameraIds=\"$camid\"&deviceOutCap=\"true\"&streamInfo=\"true\"&ptz=\"true\"&basic=\"true\"&camAppInfo=\"true\"&optimize=\"true\"&fisheye=\"true\"&eventDetection=\"true\"&_sid=\"$sid\"";   
   
   } elsif ($OpMode eq "getStmUrlPath") {
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&version=\"$apicammaxver\"&method=\"GetStmUrlPath\"&cameraIds=\"$camid\"&_sid=\"$sid\"";   
      if($apicammaxver >= 9) {
	      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&method=\"GetLiveViewPath\"&version=$apicammaxver&idList=\"$camid\"&_sid=\"$sid\"";   
	  }
   
   } elsif ($OpMode eq "geteventlist") {
      # Abruf der Events einer Kamera
      $url = "http://$serveraddr:$serverport/webapi/$apieventpath?api=\"$apievent\"&version=\"$apieventmaxver\"&method=\"List\"&cameraIds=\"$camid\"&locked=\"0\"&blIncludeSnapshot=\"false\"&reason=\"\"&limit=\"2\"&includeAllCam=\"false\"&_sid=\"$sid\"";   
   
   } elsif ($OpMode eq "Getptzlistpreset") {
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=$apiptz&version=$apiptzmaxver&method=ListPreset&cameraId=$camid&_sid=\"$sid\"";   
   
   } elsif ($OpMode eq "Getcapabilities") {
      # Capabilities einer Cam werden abgerufen
	  $apicammaxver = ($apicammaxver >= 9)?8:$apicammaxver;
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=\"GetCapabilityByCamId\"&cameraId=$camid&_sid=\"$sid\"";    
   
   } elsif ($OpMode eq "Getptzlistpatrol") {
      # PTZ-ListPatrol werden abgerufen
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=$apiptz&version=$apiptzmaxver&method=ListPatrol&cameraId=$camid&_sid=\"$sid\"";   
   
   } elsif ($OpMode eq "ExpMode") {
      if ($hash->{HELPER}{EXPMODE} eq "auto") {
          $expmode = "0";
      }
      elsif ($hash->{HELPER}{EXPMODE} eq "day") {
          $expmode = "1";
      }
      elsif ($hash->{HELPER}{EXPMODE} eq "night") {
          $expmode = "2";
      }
	  $apicammaxver = ($apicammaxver >= 9)?8:$apicammaxver;
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&version=\"$apicammaxver\"&method=\"SaveOptimizeParam\"&cameraIds=\"$camid\"&expMode=\"$expmode\"&camParamChkList=32&_sid=\"$sid\"";   
   
   } elsif ($OpMode eq "MotDetSc") {
      # Hash für Optionswerte sichern für Logausgabe in Befehlsauswertung
      my %motdetoptions = ();    
        
      if ($hash->{HELPER}{MOTDETSC} eq "disable") {
          $motdetsc = "-1";
          $url = "http://$serveraddr:$serverport/webapi/$apicameventpath?api=\"$apicamevent\"&version=\"$apicameventmaxver\"&method=\"MDParamSave\"&camId=\"$camid\"&source=$motdetsc&keep=true&_sid=\"$sid\"";
      } elsif ($hash->{HELPER}{MOTDETSC} eq "camera") {
          $motdetsc = "0";
          
          $motdetoptions{SENSITIVITY} = $hash->{'HELPER'}{'MOTDETSC_PROP1'} if ($hash->{'HELPER'}{'MOTDETSC_PROP1'});
          $motdetoptions{OBJECTSIZE}  = $hash->{'HELPER'}{'MOTDETSC_PROP2'} if ($hash->{'HELPER'}{'MOTDETSC_PROP2'});
          $motdetoptions{PERCENTAGE}  = $hash->{'HELPER'}{'MOTDETSC_PROP3'} if ($hash->{'HELPER'}{'MOTDETSC_PROP3'});
          
          $url = "http://$serveraddr:$serverport/webapi/$apicameventpath?api=\"$apicamevent\"&version=\"$apicameventmaxver\"&method=\"MDParamSave\"&camId=\"$camid\"&source=$motdetsc&_sid=\"$sid\"";
          
          if ($hash->{HELPER}{MOTDETSC_PROP1} || $hash->{HELPER}{MOTDETSC_PROP2} || $hash->{HELPER}{MOTDETSC_PROP13}) {
              # umschalten und neue Werte setzen
              $url .= "&keep=false";
          } else {
              # nur Umschaltung, alte Werte beibehalten
              $url .= "&keep=true";
          }
 
          if ($hash->{HELPER}{MOTDETSC_PROP1}) {
              # der Wert für Bewegungserkennung Kamera -> Empfindlichkeit ist gesetzt
              my $sensitivity = delete $hash->{HELPER}{MOTDETSC_PROP1};
              $url .= "&sensitivity=\"$sensitivity\"";
          }
          
          if ($hash->{HELPER}{MOTDETSC_PROP2}) {
              # der Wert für Bewegungserkennung Kamera -> Objektgröße ist gesetzt
              my $objectsize = delete $hash->{HELPER}{MOTDETSC_PROP2};
              $url .= "&objectSize=\"$objectsize\"";
          }
 
          if ($hash->{HELPER}{MOTDETSC_PROP3}) {
              # der Wert für Bewegungserkennung Kamera -> Prozentsatz für Auslösung ist gesetzt
              my $percentage = delete $hash->{HELPER}{MOTDETSC_PROP3};
              $url .= "&percentage=\"$percentage\"";
          }          
      
	  } elsif ($hash->{HELPER}{MOTDETSC} eq "SVS") {
          $motdetsc = "1";
          
          $motdetoptions{SENSITIVITY} = $hash->{'HELPER'}{'MOTDETSC_PROP1'} if ($hash->{'HELPER'}{'MOTDETSC_PROP1'});
          $motdetoptions{THRESHOLD}   = $hash->{'HELPER'}{'MOTDETSC_PROP2'} if ($hash->{'HELPER'}{'MOTDETSC_PROP2'});
      
          # nur Umschaltung, alte Werte beibehalten
          $url = "http://$serveraddr:$serverport/webapi/$apicameventpath?api=\"$apicamevent\"&version=\"$apicameventmaxver\"&method=\"MDParamSave\"&camId=\"$camid\"&source=$motdetsc&keep=true&_sid=\"$sid\"";

          if ($hash->{HELPER}{MOTDETSC_PROP1}) {
              # der Wert für Bewegungserkennung SVS -> Empfindlichkeit ist gesetzt
              my $sensitivity = delete $hash->{HELPER}{MOTDETSC_PROP1};
              $url .= "&sensitivity=\"$sensitivity\"";
          }

          if ($hash->{HELPER}{MOTDETSC_PROP2}) {
              # der Wert für Bewegungserkennung SVS -> Schwellwert ist gesetzt
              my $threshold = delete $hash->{HELPER}{MOTDETSC_PROP2};
              $url .= "&threshold=\"$threshold\"";
          }
      }
      # Optionswerte in Hash sichern für Logausgabe in Befehlsauswertung
      $hash->{HELPER}{MOTDETOPTIONS} = \%motdetoptions;
   
   } elsif ($OpMode eq "getmotionenum") {
      $url = "http://$serveraddr:$serverport/webapi/$apicameventpath?api=\"$apicamevent\"&version=\"$apicameventmaxver\"&method=\"MotionEnum\"&camId=\"$camid\"&_sid=\"$sid\"";   
   
   } elsif ($OpMode eq "extevent") {
      Log3($name, 4, "$name - trigger external event \"$hash->{HELPER}{EVENTID}\"");
      $url = "http://$serveraddr:$serverport/webapi/$apiextevtpath?api=$apiextevt&version=$apiextevtmaxver&method=Trigger&eventId=$hash->{HELPER}{EVENTID}&eventName=$hash->{HELPER}{EVENTID}&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "runliveview" && $hash->{HELPER}{RUNVIEW} !~ m/snap|^live_.*hls$/) {    
      if ($hash->{HELPER}{RUNVIEW} =~ m/live/) {
          $hash->{HELPER}{AUDIOLINK} = "http://$serveraddr:$serverport/webapi/$apiaudiostmpath?api=$apiaudiostm&version=$apiaudiostmmaxver&method=Stream&cameraId=$camid&_sid=$sid"; 
          # externe URL in Reading setzen
          $exturl = AttrVal($name, "livestreamprefix", "http://$serveraddr:$serverport");
          $exturl .= "/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsmaxver&method=Stream&cameraId=$camid&format=mjpeg&_sid=$sid"; 
          readingsSingleUpdate($hash,"LiveStreamUrl", $exturl, 1) if(AttrVal($name, "showStmInfoFull", undef));
          # interne URL
          $url = "http://$serveraddr:$serverport/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsmaxver&method=Stream&cameraId=$camid&format=mjpeg&_sid=$sid"; 
      } else {
          # Abspielen der letzten Aufnahme (EventId)
          # externe URL in Reading setzen
          $exturl = AttrVal($name, "livestreamprefix", "http://$serveraddr:$serverport");
          $exturl .= "/webapi/$apistmpath?api=$apistm&version=$apistmmaxver&method=EventStream&eventId=$hash->{HELPER}{CAMLASTRECID}&timestamp=1&_sid=$sid"; 
          readingsSingleUpdate($hash,"LiveStreamUrl", $exturl, 1) if(AttrVal($name, "showStmInfoFull", undef));
          # interne URL          
          $url = "http://$serveraddr:$serverport/webapi/$apistmpath?api=$apistm&version=$apistmmaxver&method=EventStream&eventId=$hash->{HELPER}{CAMLASTRECID}&timestamp=1&_sid=$sid";   
      }
       
      # Liveview-Link in Hash speichern
      $hash->{HELPER}{LINK} = $url;
 
      Log3($name, 4, "$name - Set Streaming-URL: $url");
      
      # livestream sofort in neuem Browsertab öffnen
      if ($hash->{HELPER}{OPENWINDOW}) {
          $winname = $name."_view";
          $attr = AttrVal($name, "htmlattr", "");
          
          # öffnen streamwindow für die Instanz die "VIEWOPENROOM" oder Attr "room" aktuell geöffnet hat
          if ($hash->{HELPER}{VIEWOPENROOM}) {
              $room = $hash->{HELPER}{VIEWOPENROOM};
              map {FW_directNotify("FILTER=room=$room", "#FHEMWEB:$_", "window.open ('$url','$winname','$attr')", "")} devspec2array("WEB.*");
          } else {
              map {FW_directNotify("#FHEMWEB:$_", "window.open ('$url','$winname','$attr')", "")} devspec2array("WEB.*");
          }
      }
           
	  SSCam_refresh($hash,0,1,1);    # kein Room-Refresh, Longpoll SSCam, Longpoll SSCamSTRM
      
	  $hash->{HELPER}{ACTIVE} = "off";
      if (AttrVal($name,"debugactivetoken",0)) {
          Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
      }
      return;
	  
   } elsif ($OpMode eq "runliveview" && $hash->{HELPER}{RUNVIEW} =~ /snap/) {
      # den letzten Schnappschuß live anzeigen
	  my $limit   = 1;                # nur 1 Snap laden, für lastsnap_fw 
	  my $imgsize = 2;                # full size image, für lastsnap_fw 
	  my $keyword = $hash->{CAMNAME}; # nur Snaps von $camname selektieren, für lastsnap_fw   
      $url = "http://$serveraddr:$serverport/webapi/$apitakesnappath?api=\"$apitakesnap\"&method=\"List\"&version=\"$apitakesnapmaxver\"&keyword=\"$keyword\"&imgSize=\"$imgsize\"&limit=\"$limit\"&_sid=\"$sid\"";
   
   } elsif (($OpMode eq "runliveview" && $hash->{HELPER}{RUNVIEW} =~ m/^live_.*hls$/) || $OpMode eq "activate_hls") {
      # HLS Livestreaming aktivieren
      $httptimeout = $httptimeout+90; # aktivieren HLS dauert lange !
      $url = "http://$serveraddr:$serverport/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsmaxver&method=Open&cameraId=$camid&format=hls&_sid=$sid"; 
   
   } elsif ($OpMode eq "stopliveview_hls" || $OpMode eq "reactivate_hls") {
      # HLS Livestreaming deaktivieren
      $url = "http://$serveraddr:$serverport/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsmaxver&method=Close&cameraId=$camid&format=hls&_sid=$sid"; 
   
   } elsif ($OpMode eq "getstreamformat") {
      # aktuelles Streamformat abfragen
      $url = "http://$serveraddr:$serverport/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsmaxver&method=Query&cameraId=$camid&_sid=$sid"; 
   }
   
   Log3($name, 4, "$name - Call-Out now: $url");
   
   $param = {
            url      => $url,
            timeout  => $httptimeout,
            hash     => $hash,
            method   => "GET",
            header   => "Accept: application/json",
            callback => \&SSCam_camop_parse
            };
   
   HttpUtils_NonblockingGet ($param);   
} 
  
###################################################################################  
#      Check ob Kameraoperation erfolgreich wie in "OpMOde" definiert 
###################################################################################
sub SSCam_camop_parse ($) {  
   my ($param, $err, $myjson) = @_;
   my $hash               = $param->{hash};
   my $name               = $hash->{NAME};
   my $camname            = $hash->{CAMNAME};
   my $OpMode             = $hash->{OPMODE};
   my $serveraddr         = $hash->{SERVERADDR};
   my $serverport         = $hash->{SERVERPORT};
   my $camid              = $hash->{CAMID};
   my $apivideostms       = $hash->{HELPER}{APIVIDEOSTMS};
   my $apivideostmspath   = $hash->{HELPER}{APIVIDEOSTMSPATH};
   my $apivideostmsmaxver = $hash->{HELPER}{APIVIDEOSTMSMAXVER};
   my $apicammaxver       = $hash->{HELPER}{APICAMMAXVER}; 
   my $sid                = $hash->{HELPER}{SID};
   my ($rectime,$data,$success);
   my ($error,$errorcode);
   my ($snapid,$camLiveMode,$update_time);
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
   my ($deviceType,$camStatus);
   my ($patrolcnt,$patrolid,$patrolname,@patrolkeys,$patrollist);
   my ($recStatus,$exposuremode,$exposurecontrol);
   my ($userPriv,$verbose,$motdetsc);
   my ($sensitivity_camCap,$sensitivity_value,$sensitivity_ssCap);
   my ($threshold_camCap,$threshold_value,$threshold_ssCap);
   my ($percentage_camCap,$percentage_value,$percentage_ssCap);
   my ($objectSize_camCap,$objectSize_value,$objectSize_ssCap);
   
   # Einstellung für Logausgabe Pollinginfos
   # wenn "pollnologging" = 1 -> logging nur bei Verbose=4, sonst 3 
   if (AttrVal($name, "pollnologging", 0) == 1) {
       $verbose = 4;
   } else {
       $verbose = 3;
   }
   
   if ($err ne "") {
        # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
        Log3($name, 2, "$name - error while requesting ".$param->{url}." - $err");
        
        readingsSingleUpdate($hash, "Error", $err, 1);                                     	       
        
		# ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
		$hash->{HELPER}{ACTIVE} = "off";
        if (AttrVal($name,"debugactivetoken",0)) {
            Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
        }
        return;
   
   } elsif ($myjson ne "") {    
        # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash,$success,$myjson) = SSCam_evaljson($hash,$myjson);
        
        unless ($success) {
            Log3($name, 4, "$name - Data returned: ".$myjson);
			
			# ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
            $hash->{HELPER}{ACTIVE} = "off";
            if (AttrVal($name,"debugactivetoken",0)) {
                Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
            }
            return;
        }
        
        $data = decode_json($myjson);
        
        # Logausgabe decodierte JSON Daten
        Log3($name, 5, "$name - JSON returned: ". Dumper $data);
   
        $success = $data->{'success'};

        if ($success) {       
            # Kameraoperation entsprechend "OpMode" war erfolgreich                
            
            if ($OpMode eq "Start") {                             
                # Die Aufnahmezeit setzen
                # wird "set <name> on [rectime]" verwendet -> dann [rectime] nutzen, 
                # sonst Attribut "rectime" wenn es gesetzt ist, falls nicht -> "RECTIME_DEF"
                if (defined($hash->{HELPER}{RECTIME_TEMP})) {
                    $rectime = delete $hash->{HELPER}{RECTIME_TEMP};
                } else {
                    $rectime = AttrVal($name, "rectime", $hash->{HELPER}{RECTIME_DEF});
                }
                
                if ($rectime == "0") {
					Log3($name, 3, "$name - Camera $camname endless Recording started  - stop it by stop-command !");
                } else {
                    if (ReadingsVal("$name", "Record", "Stop") eq "Start") {
                        # Aufnahme läuft schon und wird verlängert
                        Log3($name, 3, "$name - running recording renewed to $rectime s");
                    } else {
                        Log3($name, 3, "$name - Camera $camname Recording with Recordtime $rectime s started");
                    }
                }
                       
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Record","Start");
                readingsBulkUpdate($hash,"state","on");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                
                if ($rectime != 0) {
                    # Stop der Aufnahme nach Ablauf $rectime, wenn rectime = 0 -> endlose Aufnahme
                    RemoveInternalTimer($hash, "SSCam_camstoprec");
                    InternalTimer(gettimeofday()+$rectime, "SSCam_camstoprec", $hash);
                }      
                
                SSCam_refresh($hash,0,0,1);    # kein Room-Refresh, kein Longpoll SSCam, Longpoll SSCamSTRM
            
			} elsif ($OpMode eq "Stop") {                
			
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Record","Stop");
                readingsBulkUpdate($hash,"state","off");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
       
                # Logausgabe
                Log3($name, 3, "$name - Camera $camname Recording stopped");
                
                SSCam_refresh($hash,0,0,1);    # kein Room-Refresh, kein Longpoll SSCam, Longpoll SSCamSTRM
                
                # Aktualisierung Eventlist der letzten Aufnahme
                SSCam_geteventlist($hash);
            
			} elsif ($OpMode eq "ExpMode") {              

                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
       
                # Logausgabe
                Log3($name, 3, "$name - Camera $camname exposure mode was set to \"$hash->{HELPER}{EXPMODE}\"");
            
			} elsif ($OpMode eq "sethomemode") {              

                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
       
                Log3($name, 3, "$name - HomeMode was set to \"$hash->{HELPER}{HOMEMODE}\" ");
				
				# Token freigeben vor nächstem Kommando
                $hash->{HELPER}{ACTIVE} = "off";
  
                # neuen HomeModeState abrufen	
                SSCam_gethomemodestate($hash);
            
			} elsif ($OpMode eq "gethomemodestate") {  
                my $hmst = $data->{'data'}{'on'}; 
                my $hmststr = ($hmst == 1)?"on":"off";				

                readingsBeginUpdate($hash);
				readingsBulkUpdate($hash,"HomeModeState",$hmststr);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
            
			} elsif ($OpMode eq "getsvslog") { 
                my $lec = $data->{'data'}{'total'};    # abgerufene Anzahl von Log-Einträgen

                my $log  = '<html>';
				my $log0 = "";
				my $i = 0;
                while ($data->{'data'}->{'log'}->[$i]) {
                    my $id = $data->{'data'}->{'log'}->[$i]{'id'};
			        my $un = $data->{'data'}->{'log'}->[$i]{'user_name'};
			        my $desc = $data->{'data'}->{'log'}->[$i]{'desc'};
					my $level = $data->{'data'}->{'log'}->[$i]{'type'};
					$level = ($level == 3)?"Error":($level == 2)?"Warning":"Information";
					my $time = $data->{'data'}->{'log'}->[$i]{'time'};
					$time = FmtDateTime($time);
					$log0 = $time." - ".$level." - ".$desc if($i == 0);
			        $log .= "$time - $level - $desc<br>";
					$i++;
                }	
				$log = "<html><b>Surveillance Station Server \"$hash->{SERVERADDR}\" Log</b> ( $i/$lec entries are displayed )<br><br>$log</html>";
						        
				# asyncOutput kann normalerweise etwa 100k uebertragen (siehe fhem.pl/addToWritebuffer() fuer Details)
	            # bzw. https://forum.fhem.de/index.php/topic,77310.0.html
				# $log = "Too much log data were selected. Please reduce amount of data by specifying all or one of 'severity', 'limit', 'match'" if (length($log) >= 102400);				
				
                readingsBeginUpdate($hash);
				readingsBulkUpdate($hash,"LastLogEntry",$log0) if(!$hash->{HELPER}{CL}{1});  # Datenabruf im Hintergrund;
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
				
				# Ausgabe Popup der Log-Daten (nach readingsEndUpdate positionieren sonst "Connection lost, trying reconnect every 5 seconds" wenn > 102400 Zeichen)	    
				asyncOutput($hash->{HELPER}{CL}{1},"$log");
				delete($hash->{HELPER}{CL});
            
			} elsif ($OpMode eq "getPresets") {  
                my %ap = ();
				my $i  = 0;
                while ($data->{'data'}->{'preset'}->[$i]) {
                    my $pname  = $data->{'data'}->{'preset'}->[$i]{'name'};
			        my $ptype  = $data->{'data'}->{'preset'}->[$i]{'type'};
			        my $ppos   = $data->{'data'}->{'preset'}->[$i]{'position'};
					my $pspeed = $data->{'data'}->{'preset'}->[$i]{'speed'};
                    my $pextra = $data->{'data'}->{'preset'}->[$i]{'extra'};
                    $ptype     = ($ptype == 1)?"Home":"Normal";
                    $ap{$ppos} = "Name: $pname, Speed: $pspeed, Type: $ptype";
					$i++;
                }	
                
                my $enum;
                foreach my $key (sort{$a <=>$b}keys%ap) { 
                    $enum .= $key." => ".$ap{$key}."<br>";                 
		        }
                
				$enum = "<html><b>Preset positions saved of camera \"$hash->{CAMNAME}\" </b> ".
                        "(PresetNumber => Name: ..., Speed: ..., Type: ...) <br><br>$enum</html>";
						        
				# asyncOutput kann normalerweise etwa 100k uebertragen (siehe fhem.pl/addToWritebuffer() fuer Details)
	            # bzw. https://forum.fhem.de/index.php/topic,77310.0.html				
				
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
				
				# Ausgabe Popup der Daten (nach readingsEndUpdate positionieren sonst 
                # "Connection lost, trying reconnect every 5 seconds" wenn > 102400 Zeichen)	    
				asyncOutput($hash->{HELPER}{CL}{1},"$enum");
				delete($hash->{HELPER}{CL});
            
			} elsif ($OpMode eq "setPreset") {              
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                
                my $pnumber = delete($hash->{HELPER}{PNUMBER});
                my $pname   = delete($hash->{HELPER}{PNAME});
                my $pspeed  = delete($hash->{HELPER}{PSPEED});                
                $pspeed     = $pspeed?$pspeed:"not set";
                # Logausgabe
                Log3($name, 3, "$name - Camera \"$camname\" preset \"$pname\" was saved to number $pnumber with speed $pspeed");
                SSCam_getptzlistpreset($hash);
            
			} elsif ($OpMode eq "delPreset") {              
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                
                my $dp = $hash->{HELPER}{DELPRESETNAME};               
                Log3($name, 3, "$name - Preset \"$dp\" of camera \"$camname\" was deleted successfully");
                SSCam_getptzlistpreset($hash);
            
			} elsif ($OpMode eq "setHome") {              
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                
                my $sh = $hash->{HELPER}{SETHOME};               
                Log3($name, 3, "$name - Preset \"$sh\" of camera \"$camname\" was set as Home position");
                SSCam_getptzlistpreset($hash);
            
			} elsif ($OpMode eq "setoptpar") { 
                my $rid  = $data->{'data'}{'id'};    # Cam ID return wenn i.O.
				my $ropt = $rid == $hash->{CAMID}?"none":"error in operation";
				
				delete($hash->{HELPER}{NTPSERV});
				delete($hash->{HELPER}{MIRROR});
                delete($hash->{HELPER}{FLIP});
				delete($hash->{HELPER}{ROTATE});
				delete($hash->{HELPER}{CHKLIST});
				
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error",$ropt);
                readingsEndUpdate($hash, 1);

				# Token freigeben vor Abruf caminfo
                $hash->{HELPER}{ACTIVE} = "off";
                RemoveInternalTimer($hash, "SSCam_getcaminfo");
                InternalTimer(gettimeofday()+0.5, "SSCam_getcaminfo", $hash, 0);
				
			} elsif ($OpMode eq "MotDetSc") {              

                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
       
                # Logausgabe
                my $sensitivity;
                if ($hash->{HELPER}{MOTDETSC} eq "SVS" && keys %{$hash->{HELPER}{MOTDETOPTIONS}}) {
                    # Optionen für "SVS" sind gesetzt
                    $sensitivity    = ($hash->{HELPER}{MOTDETOPTIONS}{SENSITIVITY}) ? ($hash->{HELPER}{MOTDETOPTIONS}{SENSITIVITY}) : "-";
                    my $threshold   = ($hash->{HELPER}{MOTDETOPTIONS}{THRESHOLD}) ? ($hash->{HELPER}{MOTDETOPTIONS}{THRESHOLD}) : "-";
                    
                    Log3($name, 3, "$name - Camera $camname motion detection source set to \"$hash->{HELPER}{MOTDETSC}\" with options sensitivity: $sensitivity, threshold: $threshold");
                
                } elsif ($hash->{HELPER}{MOTDETSC} eq "camera" && keys %{$hash->{HELPER}{MOTDETOPTIONS}}) {
                    # Optionen für "camera" sind gesetzt
                    $sensitivity    = ($hash->{HELPER}{MOTDETOPTIONS}{SENSITIVITY}) ? ($hash->{HELPER}{MOTDETOPTIONS}{SENSITIVITY}) : "-";
                    my $objectSize  = ($hash->{HELPER}{MOTDETOPTIONS}{OBJECTSIZE}) ? ($hash->{HELPER}{MOTDETOPTIONS}{OBJECTSIZE}) : "-";
                    my $percentage  = ($hash->{HELPER}{MOTDETOPTIONS}{PERCENTAGE}) ? ($hash->{HELPER}{MOTDETOPTIONS}{PERCENTAGE}) : "-";
                    
                    Log3($name, 3, "$name - Camera $camname motion detection source set to \"$hash->{HELPER}{MOTDETSC}\" with options sensitivity: $sensitivity, objectSize: $objectSize, percentage: $percentage");
 
                } else {
                    # keine Optionen Bewegungserkennung wurden gesetzt
                    Log3($name, 3, "$name - Camera $camname motion detection source set to \"$hash->{HELPER}{MOTDETSC}\" ");
                }
            
			} elsif ($OpMode eq "Snap") {
                # ein Schnapschuß wurde aufgenommen
                # falls Aufnahme noch läuft -> state = on setzen
	            # my $st;
	            # (ReadingsVal("$name", "Record", "") eq "Start")?$st="on":$st="off";
	            # readingsSingleUpdate($hash,"state", $st, 0);
                SSCam_refresh($hash,0,0,0);     # kein Room-Refresh, kein Longpoll SSCam, kein Longpoll SSCamSTRM	
                
                $snapid = $data->{data}{'id'};
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                Log3($name, 3, "$name - Snapshot of Camera $camname has been done successfully");
                
				# Token freigeben vor nächstem Kommando
                $hash->{HELPER}{ACTIVE} = "off";
  
                # Schnappschußgalerie abrufen (snapGalleryBoost) oder nur Info des letzten Snaps
                my ($slim,$ssize) = SSCam_snaplimsize($hash);		
                RemoveInternalTimer("SSCam_getsnapinfo"); 
                InternalTimer(gettimeofday()+0.6, "SSCam_getsnapinfo", "$name:$slim:$ssize", 0);
            
			} elsif ($OpMode eq "getsnapinfo" || $OpMode eq "getsnapgallery" || ($OpMode eq "runliveview" && $hash->{HELPER}{RUNVIEW} =~ /snap/)) {
                # Informationen zu einem oder mehreren Schnapschüssen wurde abgerufen bzw. Lifeanzeige Schappschuß              			
				my $lsid   = exists($data->{data}{data}[0]{id})?$data->{data}{data}[0]{id}:"n.a.";
				my $lfname = exists($data->{data}{data}[0]{fileName})?$data->{data}{data}[0]{fileName}:"n.a.";
				
				my $lstime;
				if(exists($data->{data}{data}[0]{createdTm})) {
				    $lstime = $data->{data}{data}[0]{createdTm};
				    my @t = split(" ", FmtDateTime($lstime));
					my @d = split("-", $t[0]);
					$lstime = "$d[2].$d[1].$d[0] / $t[1]";
				} else {
				    $lstime = "n.a.";	
				}
				
				Log3($name,4, "$name - Snap [0]: ID => $lsid, File => $lfname, Created => $lstime");
				 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsBulkUpdate($hash,"LastSnapId",$lsid);
				readingsBulkUpdate($hash,"LastSnapFilename", $lfname);
				readingsBulkUpdate($hash,"LastSnapTime", $lstime);
                readingsEndUpdate($hash, 1);
					
				# Schnapschuss soll als liveView angezeigt werden (mindestens 1 Bild vorhanden)
				Log3($name, 3, "$name - There is no snapshot of camera $camname to display ! Take one snapshot before.") 
				   if(exists($hash->{HELPER}{RUNVIEW}) && $hash->{HELPER}{RUNVIEW} =~ /snap/ && !exists($data->{'data'}{'data'}[0]{imageData}));
			    
				if (exists($hash->{HELPER}{RUNVIEW}) && $hash->{HELPER}{RUNVIEW} =~ /snap/ && exists($data->{'data'}{'data'}[0]{imageData})) {
				    delete $hash->{HELPER}{RUNVIEW};
                    # Aufnahmestatus in state abbilden
	                my $st;
	                # (ReadingsVal("$name", "Record", "") eq "Start")?$st="on":$st="off";
	                # readingsSingleUpdate($hash,"state", $st, 0); 
					
					$hash->{HELPER}{LINK} = $data->{data}{data}[0]{imageData};
                    SSCam_refresh($hash,0,0,1);     # kein Room-Refresh, kein Longpoll SSCam, Longpoll SSCamSTRM					
				}

                if($OpMode eq "getsnapgallery") {
				    # es soll eine Schnappschußgallerie bereitgestellt (Attr snapGalleryBoost=1) bzw. gleich angezeigt werden (Attr snapGalleryBoost=0)
				    my $i = 0;
				    my $sn = 0;
                    my %allsnaps = ();  # Schnappschuss Hash wird leer erstellt
                     
					$hash->{HELPER}{TOTALCNT} = $data->{data}{total};  # total Anzahl Schnappschüsse
					
					while ($data->{'data'}{'data'}[$i]) {
		                if($data->{'data'}{'data'}[$i]{'camName'} ne $camname) {
			                $i += 1;
				            next;
			            }
			            $snapid = $data->{data}{data}[$i]{id};
			            my $createdTm = $data->{data}{data}[$i]{createdTm};
                        my $fileName  = $data->{data}{data}[$i]{fileName};
					    my $imageData = $data->{data}{data}[$i]{imageData};  # Image data of snapshot in base64 format 
			        
			            $allsnaps{$sn}{snapid} = $snapid;
					    my @t = split(" ", FmtDateTime($createdTm));
					    my @d = split("-", $t[0]);
					    $createdTm = "$d[2].$d[1].$d[0] / $t[1]";
                        $allsnaps{$sn}{createdTm}  = $createdTm;
			            $allsnaps{$sn}{fileName}   = $fileName;
					    $allsnaps{$sn}{imageData}  = $imageData;
						Log3($name,4, "$name - Snap '$sn' added to gallery hash: ID => $allsnaps{$sn}{snapid}, File => $allsnaps{$sn}{fileName}, Created => $allsnaps{$sn}{createdTm}");
                        $sn += 1;
					    $i += 1;
                    }
	                
					# Hash der Schnapschüsse erstellen
					$hash->{HELPER}{".SNAPHASH"} = \%allsnaps;
                    
					# Direktausgabe Snaphash wenn nicht gepollt wird
					if(!AttrVal($name, "snapGalleryBoost",0)) {		    
						my $htmlCode = composegallery($name);
                        
					    for (my $k=1; (defined($hash->{HELPER}{CL}{$k})); $k++ ) {
                            asyncOutput($hash->{HELPER}{CL}{$k},"$htmlCode");						
		                }
						delete($hash->{HELPER}{".SNAPHASH"});               # Snaphash löschen wenn nicht gepollt wird
						delete($hash->{HELPER}{CL});
					}

					delete($hash->{HELPER}{GETSNAPGALLERY}); # Steuerbit getsnapgallery statt getsnapinfo
				}		
                Log3($name, $verbose, "$name - Snapinfos of camera $camname retrieved");
            
			} elsif ($OpMode eq "runliveview" && $hash->{HELPER}{RUNVIEW} =~ m/^live_.*hls$/) {
                # HLS Streaming wurde aktiviert
                $hash->{HELPER}{HLSSTREAM} = "active";
                # externe LivestreamURL setzen
                my $exturl = AttrVal($name, "livestreamprefix", "http://$serveraddr:$serverport");
                $exturl .= "/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsmaxver&method=Stream&cameraId=$camid&format=hls&_sid=$sid"; 
                readingsSingleUpdate($hash,"LiveStreamUrl", $exturl, 1) if(AttrVal($name, "showStmInfoFull", undef));
                
                my $url = "http://$serveraddr:$serverport/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsmaxver&method=Stream&cameraId=$camid&format=hls&_sid=$sid"; 
                # Liveview-Link in Hash speichern und Aktivitätsstatus speichern
                $hash->{HELPER}{LINK}      = $url;
                Log3($name, 4, "$name - HLS Streaming of camera \"$name\" activated, Streaming-URL: $url") if(AttrVal($name,"verbose",3) == 4);
                Log3($name, 3, "$name - HLS Streaming of camera \"$name\" activated") if(AttrVal($name,"verbose",3) == 3);
                
                SSCam_refresh($hash,0,1,1);   # kein Room-Refresh, Longpoll SSCam, Longpoll SSCamSTRM
                
            } elsif ($OpMode eq "stopliveview_hls") {
                # HLS Streaming wurde deaktiviert, Aktivitätsstatus speichern
                $hash->{HELPER}{HLSSTREAM} = "inactive";
                Log3($name, 3, "$name - HLS Streaming of camera \"$name\" deactivated");
                               
                SSCam_refresh($hash,0,1,1);   # kein Room-Refresh, Longpoll SSCam, Longpoll SSCamSTRM
                
            } elsif ($OpMode eq "reactivate_hls") {
                # HLS Streaming wurde deaktiviert, Aktivitätsstatus speichern
                $hash->{HELPER}{HLSSTREAM} = "inactive";
                Log3($name, 4, "$name - HLS Streaming of camera \"$name\" deactivated for streaming device");

				# Token freigeben vor hlsactivate
                $hash->{HELPER}{ACTIVE} = "off";
                SSCam_hlsactivate($hash);
                
            } elsif ($OpMode eq "activate_hls") {
                # HLS Streaming wurde aktiviert, Aktivitätsstatus speichern
                $hash->{HELPER}{HLSSTREAM} = "active"; 
                Log3($name, 4, "$name - HLS Streaming of camera \"$name\" activated for streaming device");
                
                SSCam_refresh($hash,0,1,1);   # kein Room-Refresh, Longpoll SSCam, Longpoll SSCamSTRM
                                
            } elsif ($OpMode eq "getsnapfilename") {
                # den Filenamen eines Schnapschusses ermitteln
                $snapid = ReadingsVal("$name", "LastSnapId", " ");
                           
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsBulkUpdate($hash,"LastSnapFilename", $data->{'data'}{'data'}[0]{'fileName'});
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                Log3($name, 4, "$name - Filename of Snap-ID $snapid is \"$data->{'data'}{'data'}[0]{'fileName'}\"") if($data->{'data'}{'data'}[0]{'fileName'});
            
			} elsif ($OpMode eq "getstreamformat") {
                # aktuelles Streamformat abgefragt
                my $sformat = SSCam_jboolmap($data->{'data'}->{'format'});
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsBulkUpdate($hash,"CamStreamFormat", uc($sformat)) if($sformat);
                readingsEndUpdate($hash, 1);                
            
			} elsif ($OpMode eq "gopreset") {
                # eine Presetposition wurde angefahren
                # falls Aufnahme noch läuft -> state = on setzen
                my $st = (ReadingsVal("$name", "Record", "Stop") eq "Start")?"on":"off";    
                readingsSingleUpdate($hash,"state", $st, 0); 
                DoTrigger($name,"move stop");
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                Log3($name, 3, "$name - Camera $camname has been moved to position \"$hash->{HELPER}{GOPRESETNAME}\"");
            
			} elsif ($OpMode eq "runpatrol") {
                # eine Tour wurde gestartet
                # falls Aufnahme noch läuft -> state = on setzen
                my $st = (ReadingsVal("$name", "Record", "Stop") eq "Start")?"on":"off";    
                readingsSingleUpdate($hash,"state", $st, 0); 
                DoTrigger($name,"patrol started"); 
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                Log3($name, 3, "$name - Patrol \"$hash->{HELPER}{GOPATROLNAME}\" of camera $camname has been started successfully");
            
			} elsif ($OpMode eq "goabsptz") {
                # eine absolute PTZ-Position wurde angefahren
                # falls Aufnahme noch läuft -> state = on setzen
                my $st = (ReadingsVal("$name", "Record", "Stop") eq "Start")?"on":"off";    
                readingsSingleUpdate($hash,"state", $st, 0); 
                DoTrigger($name,"move stop");
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                Log3($name, 3, "$name - Camera $camname has been moved to absolute position \"posX=$hash->{HELPER}{GOPTZPOSX}\" and \"posY=$hash->{HELPER}{GOPTZPOSY}\"");
            
			} elsif ($OpMode eq "startTrack") {
                # Object Tracking wurde eingeschaltet
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                Log3($name, 3, "$name - Object tracking of Camera $camname has been switched on");
            
			} elsif ($OpMode eq "stopTrack") {
                # Object Tracking wurde eingeschaltet
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                Log3($name, 3, "$name - Object tracking of Camera $camname has been stopped");
            
			} elsif ($OpMode eq "movestart") {
                # ein "Move" in eine bestimmte Richtung wird durchgeführt                 
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                Log3($name, 3, "$name - Camera $camname started move to direction \"$hash->{HELPER}{GOMOVEDIR}\" with duration of $hash->{HELPER}{GOMOVETIME} s");
                
                RemoveInternalTimer($hash, "SSCam_movestop");
                InternalTimer(gettimeofday()+($hash->{HELPER}{GOMOVETIME}), "SSCam_movestop", $hash);
            
			} elsif ($OpMode eq "movestop") {
                # ein "Move" in eine bestimmte Richtung wurde durchgeführt 
                # falls Aufnahme noch läuft -> state = on setzen
                my $st = (ReadingsVal("$name", "Record", "Stop") eq "Start")?"on":"off";    
                readingsSingleUpdate($hash,"state", $st, 0); 
                DoTrigger($name,"move stop");
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                Log3($name, 3, "$name - Camera $camname stopped move to direction \"$hash->{HELPER}{GOMOVEDIR}\"");
        
            } elsif ($OpMode eq "Enable") {
                # Kamera wurde aktiviert, sonst kann nichts laufen -> "off"                

                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Availability","enabled");
                readingsBulkUpdate($hash,"state","off");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                   
                # Logausgabe
                Log3($name, 3, "$name - Camera $camname has been enabled successfully");
            
			} elsif ($OpMode eq "Disable") {
                # Kamera wurde deaktiviert

                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Availability","disabled");
                readingsBulkUpdate($hash,"state","disabled");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                   
                # Logausgabe
                Log3($name, 3, "$name - Camera $camname has been disabled successfully");
            
			} elsif ($OpMode eq "getsvsinfo") {
                # Parse SVS-Infos
                $userPriv = $data->{'data'}{'userPriv'};
                if (defined($userPriv)) {
                    if ($userPriv eq "0") {
                        $userPriv = "No Access";
                    } elsif ($userPriv eq "1") {
                        $userPriv = "Admin";
                    } elsif ($userPriv eq "2") {
                        $userPriv = "Manager";
                    } elsif ($userPriv eq "4") {
                        $userPriv = "Viewer";
                    }
                }                    
                # "my" nicht am Anfang deklarieren, sonst wird Hash %version wieder geleert !
                my %version = (
                              MAJOR => $data->{'data'}{'version'}{'major'},
                              MINOR => $data->{'data'}{'version'}{'minor'},
							  SMALL => $data->{'data'}{'version'}{'small'},
                              BUILD => $data->{'data'}{'version'}{'build'}
                              );
                # Werte in $hash zur späteren Auswertung einfügen 
                $hash->{HELPER}{SVSVERSION} = \%version;
				my $major = $version{"MAJOR"};
				my $minor = $version{"MINOR"};
				my $small = $version{"SMALL"};
				my $build = $version{"BUILD"};
                
                # simulieren einer anderen SVS-Version
                if (AttrVal($name, "simu_SVSversion", undef)) {
                    Log3($name, 4, "$name - another SVS-version ".AttrVal($name, "simu_SVSversion", undef)." will be simulated");
					#delete $version{"SMALL"} if ($version{"SMALL"});
                    my @vl = split (/\.|-/,AttrVal($name, "simu_SVSversion", ""));
                    $major = $vl[0];
                    $minor = $vl[1];
					$small = ($vl[2] =~ /\d/)?$vl[2]:undef;
                    $build = "xxxx-simu";
                }
                
                if (!exists($data->{'data'}{'customizedPortHttp'})) {
                    delete $defs{$name}{READINGS}{SVScustomPortHttp};
                }             
               
                if (!exists($data->{'data'}{'customizedPortHttps'})) {
                    delete $defs{$name}{READINGS}{SVScustomPortHttps};
                }
                                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"SVScustomPortHttp",$data->{'data'}{'customizedPortHttp'});
                readingsBulkUpdate($hash,"SVScustomPortHttps",$data->{'data'}{'customizedPortHttps'});
                readingsBulkUpdate($hash,"SVSlicenseNumber",$data->{'data'}{'liscenseNumber'});
                readingsBulkUpdate($hash,"SVSuserPriv",$userPriv);
				if(defined($small)) {
				    readingsBulkUpdate($hash,"SVSversion",$major.".".$minor.".".$small."-".$build);
				} else {
				    readingsBulkUpdate($hash,"SVSversion",$major.".".$minor."-".$build);
				}
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                     
                Log3($name, $verbose, "$name - Informations related to Surveillance Station retrieved");
            
			} elsif ($OpMode eq "getStmUrlPath") {
                # Parse SVS-Infos
				my($camforcemcast,$mjpegHttp,$multicst,$mxpegHttp,$unicastOverHttp,$unicastPath);
				if($apicammaxver < 9) {
                    $camforcemcast   = SSCam_jboolmap($data->{'data'}{'pathInfos'}[0]{'forceEnableMulticast'});
                    $mjpegHttp       = $data->{'data'}{'pathInfos'}[0]{'mjpegHttpPath'};
                    $multicst        = $data->{'data'}{'pathInfos'}[0]{'multicstPath'};
                    $mxpegHttp       = $data->{'data'}{'pathInfos'}[0]{'mxpegHttpPath'};
                    $unicastOverHttp = $data->{'data'}{'pathInfos'}[0]{'unicastOverHttpPath'};
                    $unicastPath     = $data->{'data'}{'pathInfos'}[0]{'unicastPath'};
				}
				if($apicammaxver >= 9) {
                    $mjpegHttp        = $data->{'data'}[0]{'mjpegHttpPath'};
                    $multicst         = $data->{'data'}[0]{'multicstPath'};
                    $mxpegHttp        = $data->{'data'}[0]{'mxpegHttpPath'};
                    $unicastOverHttp  = $data->{'data'}[0]{'rtspOverHttpPath'};
                    $unicastPath      = $data->{'data'}[0]{'rtspPath'};
				}		
                
                # Rewrite Url's falls livestreamprefix ist gesetzt
                if (AttrVal($name, "livestreamprefix", undef)) {
                    my @mjh = split(/\//, $mjpegHttp, 4);
                    $mjpegHttp = AttrVal($name, "livestreamprefix", undef)."/".$mjh[3];
                    my @mxh = split(/\//, $mxpegHttp, 4);
                    $mxpegHttp = AttrVal($name, "livestreamprefix", undef)."/".$mxh[3];
					if($unicastPath) {
                        my @ucp = split(/[@\|:]/, $unicastPath);
                        my @lspf = split(/[\/\/\|:]/, AttrVal($name, "livestreamprefix", undef));
                        $unicastPath = $ucp[0].":".$ucp[1].":".$ucp[2]."@".$lspf[3].":".$ucp[4];
					}
                }
                
                # StmKey extrahieren
                my @sk = split(/&StmKey=/, $mjpegHttp);
                my $stmkey = $sk[1];
                $stmkey =~ tr/"//d;
				# Quotes in StmKey entfernen falls noQuotesForSID gesezt 
				$mjpegHttp =~ tr/"//d if(AttrVal($name, "noQuotesForSID",0));
                
                # Readings löschen falls sie nicht angezeigt werden sollen (showStmInfoFull)
                if (!AttrVal($name,"showStmInfoFull",0)) {
                    delete($defs{$name}{READINGS}{StmKeymjpegHttp});
                    delete($defs{$name}{READINGS}{StmKeyUnicst});
					delete($defs{$name}{READINGS}{StmKeyUnicstOverHttp});
                }
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"CamForceEnableMulticast",$camforcemcast) if($camforcemcast);
                readingsBulkUpdate($hash,"StmKey",$stmkey);
                readingsBulkUpdate($hash,"StmKeymjpegHttp",$mjpegHttp)  if(AttrVal($name,"showStmInfoFull",0));
                # readingsBulkUpdate($hash,"StmKeymxpegHttp",$mxpegHttp);
				readingsBulkUpdate($hash,"StmKeyUnicstOverHttp",$unicastOverHttp) if(AttrVal($name,"showStmInfoFull",0) && $unicastOverHttp);
                readingsBulkUpdate($hash,"StmKeyUnicst",$unicastPath) if(AttrVal($name,"showStmInfoFull",0) && $unicastPath);
				readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                     
                # Logausgabe
                Log3($name, $verbose, "$name - Stream-URLs of camera $camname retrieved");
            
			} elsif ($OpMode eq "Getcaminfo") {
                # Parse Caminfos
                $camLiveMode = $data->{'data'}->{'cameras'}->[0]->{'camLiveMode'};
                if ($camLiveMode eq "0") {$camLiveMode = "Liveview from DS";}elsif ($camLiveMode eq "1") {$camLiveMode = "Liveview from Camera";}
                
                # $update_time = $data->{'data'}->{'cameras'}->[0]->{'update_time'};
                ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
                $update_time = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;
                
                $deviceType = $data->{'data'}->{'cameras'}->[0]->{'deviceType'};
                if ($deviceType eq "1") {
                    $deviceType = "Camera";
                } elsif ($deviceType eq "2") {
                    $deviceType = "Video_Server";
                } elsif ($deviceType eq "4") {
                    $deviceType = "PTZ";
                } elsif ($deviceType eq "8") {
                    $deviceType = "Fisheye"; 
                }
                
                $camStatus = $data->{'data'}->{'cameras'}->[0]->{'camStatus'};
                if ($camStatus eq "1") {
                    $camStatus = "enabled";
                    
                    # falls Aufnahme noch läuft -> STATE = on setzen
                    if (ReadingsVal("$name", "Record", "Stop") eq "Start") {
                        readingsSingleUpdate($hash,"state", "on", 0); 
                    } else {
                        readingsSingleUpdate($hash,"state", "off", 0); 
                    }
                
				} elsif ($camStatus eq "3") {
                    $camStatus = "disconnected";
                    readingsSingleUpdate($hash,"state", "disconnected", 0);
                } elsif ($camStatus eq "7") {
                    $camStatus = "disabled";
                    readingsSingleUpdate($hash,"state", "disabled", 0); 
                } else {
                    $camStatus = "other";
                }
               
                $recStatus = $data->{'data'}->{'cameras'}->[0]->{'recStatus'};
                if ($recStatus ne "0") {
                    $recStatus = "Start";
                } else {
                    $recStatus = "Stop";
                }
				
				my $rotate = $data->{'data'}->{'cameras'}->[0]->{'video_rotation'};
				$rotate = $rotate == 1?"true":"false";
                
                $exposuremode = SSCam_jboolmap($data->{'data'}->{'cameras'}->[0]->{'exposure_mode'});
                if ($exposuremode == 0) {
                    $exposuremode = "Auto";
                } elsif ($exposuremode == 1) {
                    $exposuremode = "Day";
                } elsif ($exposuremode == 2) {
                    $exposuremode = "Night";
                } elsif ($exposuremode == 3) {
                    $exposuremode = "Schedule";
                } elsif ($exposuremode == 4) {
                    $exposuremode = "Unknown";
                }
                    
                $exposurecontrol = SSCam_jboolmap($data->{'data'}->{'cameras'}->[0]->{'exposure_control'});
                if ($exposurecontrol == 0) {
                    $exposurecontrol = "Auto";
                } elsif ($exposurecontrol == 1) {
                    $exposurecontrol = "50HZ";
                } elsif ($exposurecontrol == 2) {
                    $exposurecontrol = "60HZ";
                } elsif ($exposurecontrol == 3) {
                    $exposurecontrol = "Hold";
                } elsif ($exposurecontrol == 4) {
                    $exposurecontrol = "Outdoor";
                } elsif ($exposurecontrol == 5) {
                    $exposurecontrol = "None";
                } elsif ($exposurecontrol == 6) {
                    $exposurecontrol = "Unknown";
                }
                
                my $camaudiotype = SSCam_jboolmap($data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camAudioType'});
                if ($camaudiotype == 0) {
                    $camaudiotype = "Unknown";
                } elsif ($camaudiotype == 1) {
                    $camaudiotype = "PCM";
                } elsif ($camaudiotype == 2) {
                    $camaudiotype = "G711";
                } elsif ($camaudiotype == 3) {
                    $camaudiotype = "G726";
                } elsif ($camaudiotype == 4) {
                    $camaudiotype = "AAC";
                } elsif ($camaudiotype == 5) {
                    $camaudiotype = "AMR";
                }           
                    
                $data->{'data'}->{'cameras'}->[0]->{'video_flip'}    = SSCam_jboolmap($data->{'data'}->{'cameras'}->[0]->{'video_flip'});
                $data->{'data'}->{'cameras'}->[0]->{'video_mirror'}  = SSCam_jboolmap($data->{'data'}->{'cameras'}->[0]->{'video_mirror'});
                $data->{'data'}->{'cameras'}->[0]->{'blPresetSpeed'} = SSCam_jboolmap($data->{'data'}->{'cameras'}->[0]->{'blPresetSpeed'});
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"CamAudioType",$camaudiotype);
                readingsBulkUpdate($hash,"CamLiveMode",$camLiveMode);
                readingsBulkUpdate($hash,"CamExposureMode",$exposuremode);
                readingsBulkUpdate($hash,"CamExposureControl",$exposurecontrol);
                readingsBulkUpdate($hash,"CamModel",$data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camModel'});
                readingsBulkUpdate($hash,"CamRecShare",$data->{'data'}->{'cameras'}->[0]->{'camRecShare'});
                readingsBulkUpdate($hash,"CamRecVolume",$data->{'data'}->{'cameras'}->[0]->{'camRecVolume'});
                readingsBulkUpdate($hash,"CamIP",$data->{'data'}->{'cameras'}->[0]->{'host'});
				readingsBulkUpdate($hash,"CamNTPServer",$data->{'data'}->{'cameras'}->[0]->{'time_server'}) if($data->{'data'}->{'cameras'}->[0]->{'time_server'}); 
                readingsBulkUpdate($hash,"CamVendor",$data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camVendor'});
                readingsBulkUpdate($hash,"CamVideoType",$data->{'data'}->{'cameras'}->[0]->{'camVideoType'});
                readingsBulkUpdate($hash,"CamPreRecTime",$data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camPreRecTime'});
                readingsBulkUpdate($hash,"CamPort",$data->{'data'}->{'cameras'}->[0]->{'port'});
                readingsBulkUpdate($hash,"CamPtSpeed",$data->{'data'}->{'cameras'}->[0]->{'ptSpeed'});
                readingsBulkUpdate($hash,"CamblPresetSpeed",$data->{'data'}->{'cameras'}->[0]->{'blPresetSpeed'});
                readingsBulkUpdate($hash,"CamVideoMirror",$data->{'data'}->{'cameras'}->[0]->{'video_mirror'});
                readingsBulkUpdate($hash,"CamVideoFlip",$data->{'data'}->{'cameras'}->[0]->{'video_flip'});
				readingsBulkUpdate($hash,"CamVideoRotate",$rotate);
                readingsBulkUpdate($hash,"Availability",$camStatus);
                readingsBulkUpdate($hash,"DeviceType",$deviceType);
                readingsBulkUpdate($hash,"LastUpdateTime",$update_time);
                readingsBulkUpdate($hash,"Record",$recStatus);
                readingsBulkUpdate($hash,"UsedSpaceMB",$data->{'data'}->{'cameras'}->[0]->{'volume_space'});
                readingsBulkUpdate($hash,"VideoFolder",AttrVal($name, "videofolderMap", undef) ? AttrVal($name, "videofolderMap", undef) : $data->{'data'}->{'cameras'}->[0]->{'folder'});
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                   
                $hash->{MODEL} = ReadingsVal($name,"CamVendor","")." - ".ReadingsVal($name,"CamModel","CAM") if(SSCam_IsModelCam($hash));                   
                Log3($name, $verbose, "$name - Informations of camera $camname retrieved");
            
			} elsif ($OpMode eq "geteventlist") {              
                my $eventnum    = $data->{'data'}{'total'};
                my $lastrecord  = $data->{'data'}{'events'}[0]{name};
                $hash->{HELPER}{CAMLASTRECID} = $data->{'data'}{'events'}[0]{'eventId'}; 
                
                my ($lastrecstarttime,$lastrecstoptime);
                
                if ($eventnum > 0) {
                    $lastrecstarttime = $data->{'data'}{'events'}[0]{startTime};
                    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($lastrecstarttime);
                    $lastrecstarttime = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;
                
                    $lastrecstoptime = $data->{'data'}{'events'}[0]{stopTime};
                    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($lastrecstoptime);
                    $lastrecstoptime = sprintf "%02d:%02d:%02d" , $hour , $min , $sec ;
                }
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"CamEventNum",$eventnum);
                readingsBulkUpdate($hash,"CamLastRec",$lastrecord);               
                if ($lastrecstarttime) {readingsBulkUpdate($hash,"CamLastRecTime",$lastrecstarttime." - ". $lastrecstoptime);}                
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
       
                # Logausgabe
                Log3($name, $verbose, "$name - Query eventlist of camera $camname retrieved");
            
			} elsif ($OpMode eq "getmotionenum") {              
                
				$motdetsc = $data->{'data'}{'MDParam'}{'source'};
                
                $sensitivity_camCap = $data->{'data'}{'MDParam'}{'sensitivity'}{'camCap'};
                $sensitivity_value  = $data->{'data'}{'MDParam'}{'sensitivity'}{'value'};
                $sensitivity_ssCap  = $data->{'data'}{'MDParam'}{'sensitivity'}{'ssCap'};
                
                $threshold_camCap   = $data->{'data'}{'MDParam'}{'threshold'}{'camCap'};
                $threshold_value    = $data->{'data'}{'MDParam'}{'threshold'}{'value'};
                $threshold_ssCap    = $data->{'data'}{'MDParam'}{'threshold'}{'ssCap'};

                $percentage_camCap  = $data->{'data'}{'MDParam'}{'percentage'}{'camCap'};
                $percentage_value   = $data->{'data'}{'MDParam'}{'percentage'}{'value'};
                $percentage_ssCap   = $data->{'data'}{'MDParam'}{'percentage'}{'ssCap'};
                
                $objectSize_camCap  = $data->{'data'}{'MDParam'}{'objectSize'}{'camCap'};
                $objectSize_value   = $data->{'data'}{'MDParam'}{'objectSize'}{'value'};
                $objectSize_ssCap   = $data->{'data'}{'MDParam'}{'objectSize'}{'ssCap'};
                
                
                if ($motdetsc == -1) {
                    $motdetsc = "disabled";
                }
                elsif ($motdetsc == 0) {
                    $motdetsc = "Camera";
                    
                    if ($sensitivity_camCap) {
                        $motdetsc .= ", sensitivity: $sensitivity_value";
                    }
                    if ($threshold_camCap) {
                        $motdetsc .= ", threshold: $threshold_value";
                    }
                    if ($percentage_camCap) {
                        $motdetsc .= ", percentage: $percentage_value";
                    }
                    if ($objectSize_camCap) {
                        $motdetsc .= ", objectSize: $objectSize_value";
                    }
                }
                elsif ($motdetsc == 1) {
                    $motdetsc = "SVS";
                    
                    if ($sensitivity_ssCap) {
                        $motdetsc .= ", sensitivity: $sensitivity_value";
                    }
                    if ($threshold_ssCap) {
                        $motdetsc .= ", threshold: $threshold_value";
                    }
                    if ($percentage_ssCap) {
                        $motdetsc .= ", percentage: $percentage_value";
                    }
                    if ($objectSize_ssCap) {
                        $motdetsc .= ", objectSize: $objectSize_value";
                    }
                }
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"CamMotDetSc",$motdetsc);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
       
                # Logausgabe
                Log3($name, $verbose, "$name - Enumerate motion detection parameters of camera $camname retrieved");
            
			} elsif ($OpMode eq "Getcapabilities") {
                # Parse Infos
                my $ptzfocus = $data->{'data'}{'ptzFocus'};
                if ($ptzfocus eq "0") {
                    $ptzfocus = "false";
                    }
                    elsif ($ptzfocus eq "1") {
                    $ptzfocus = "support step operation";
                    }
                    elsif ($ptzfocus eq "2") {
                    $ptzfocus = "support continuous operation";
                    }
                    
                my $ptztilt = $data->{'data'}{'ptzTilt'};
                if ($ptztilt eq "0") {
                    $ptztilt = "false";
                    }
                    elsif ($ptztilt eq "1") {
                    $ptztilt = "support step operation";
                    }
                    elsif ($ptztilt eq "2") {
                    $ptztilt = "support continuous operation";
                    }
                    
                my $ptzzoom = $data->{'data'}{'ptzZoom'};
                if ($ptzzoom eq "0") {
                    $ptzzoom = "false";
                    }
                    elsif ($ptzzoom eq "1") {
                    $ptzzoom = "support step operation";
                    }
                    elsif ($ptzzoom eq "2") {
                    $ptzzoom = "support continuous operation";
                    }
                    
                my $ptzpan = $data->{'data'}{'ptzPan'};
                if ($ptzpan eq "0") {
                    $ptzpan = "false";
                    }
                    elsif ($ptzpan eq "1") {
                    $ptzpan = "support step operation";
                    }
                    elsif ($ptzpan eq "2") {
                    $ptzpan = "support continuous operation";
                    }
                
                my $ptziris = $data->{'data'}{'ptzIris'};
                if ($ptziris eq "0") {
                    $ptziris = "false";
                    }
                    elsif ($ptziris eq "1") {
                    $ptziris = "support step operation";
                    }
                    elsif ($ptziris eq "2") {
                    $ptziris = "support continuous operation";
                    }
                
                $data->{'data'}{'ptzHasObjTracking'} = SSCam_jboolmap($data->{'data'}{'ptzHasObjTracking'});
                $data->{'data'}{'audioOut'}          = SSCam_jboolmap($data->{'data'}{'audioOut'});
                $data->{'data'}{'ptzSpeed'}          = SSCam_jboolmap($data->{'data'}{'ptzSpeed'});
                $data->{'data'}{'ptzAbs'}            = SSCam_jboolmap($data->{'data'}{'ptzAbs'});
                $data->{'data'}{'ptzAutoFocus'}      = SSCam_jboolmap($data->{'data'}{'ptzAutoFocus'});
                $data->{'data'}{'ptzHome'}           = SSCam_jboolmap($data->{'data'}{'ptzHome'});
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"CapPTZAutoFocus",$data->{'data'}{'ptzAutoFocus'});
                readingsBulkUpdate($hash,"CapAudioOut",$data->{'data'}{'audioOut'});
                readingsBulkUpdate($hash,"CapChangeSpeed",$data->{'data'}{'ptzSpeed'});
                readingsBulkUpdate($hash,"CapPTZHome",$data->{'data'}{'ptzHome'});
                readingsBulkUpdate($hash,"CapPTZAbs",$data->{'data'}{'ptzAbs'});
                readingsBulkUpdate($hash,"CapPTZDirections",$data->{'data'}{'ptzDirection'});
                readingsBulkUpdate($hash,"CapPTZFocus",$ptzfocus);
                readingsBulkUpdate($hash,"CapPTZIris",$ptziris);
                readingsBulkUpdate($hash,"CapPTZObjTracking",$data->{'data'}{'ptzHasObjTracking'});
                readingsBulkUpdate($hash,"CapPTZPan",$ptzpan);
                readingsBulkUpdate($hash,"CapPTZPresetNumber",$data->{'data'}{'ptzPresetNumber'});
                readingsBulkUpdate($hash,"CapPTZTilt",$ptztilt);
                readingsBulkUpdate($hash,"CapPTZZoom",$ptzzoom);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                  
                # Logausgabe
                Log3($name, $verbose, "$name - Capabilities of camera $camname retrieved");
            
			} elsif ($OpMode eq "Getptzlistpreset") {
                # Parse PTZ-ListPresets
                my $presetcnt = $data->{'data'}->{'total'};
                my $cnt = 0;
         
                # alle Presets der Kamera mit Id's in Assoziatives Array einlesen
                # "my" nicht am Anfang deklarieren, sonst wird Hash %allpresets wieder geleert !
                my %allpresets;
                my $home = "not set";
                while ($cnt < $presetcnt) {
                    # my $presid = $data->{'data'}->{'presets'}->[$cnt]->{'id'};
                    my $presid   = $data->{'data'}->{'presets'}->[$cnt]->{'position'};
                    my $presname = $data->{'data'}->{'presets'}->[$cnt]->{'name'};
                    $allpresets{$presname} = "$presid";
                    my $ptype = $data->{'data'}->{'presets'}->[$cnt]->{'type'};
                    if ($ptype) {
                        $home = $presname;
                    }
                    $cnt += 1;
                }
                    
                # Presethash in $hash einfügen
                $hash->{HELPER}{ALLPRESETS} = \%allpresets;

                my @preskeys = sort(keys(%allpresets));
                my $presetlist = join(",",@preskeys);

                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Presets",$presetlist);
                readingsBulkUpdate($hash,"PresetHome",$home);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                
                # spezifische Attribute für PTZ-Cams verfügbar machen
                SSCam_addptzattr($name);
                             
                # Logausgabe
                Log3($name, $verbose, "$name - PTZ Presets of camera $camname retrieved");
            
			} elsif ($OpMode eq "Getptzlistpatrol") {
                # Parse PTZ-ListPatrols
                $patrolcnt = $data->{'data'}->{'total'};
                my $cnt = 0;
         
                # alle Patrols der Kamera mit Id's in Assoziatives Array einlesen
                # "my" nicht am Anfang deklarieren, sonst wird Hash %allpatrols wieder geleert !
                my %allpatrols = ();
                while ($cnt < $patrolcnt) {
                    $patrolid = $data->{'data'}->{'patrols'}->[$cnt]->{'id'};
                    $patrolname = $data->{'data'}->{'patrols'}->[$cnt]->{'name'};
                    $allpatrols{$patrolname} = $patrolid;
                    $cnt += 1;
                }
                    
                # Presethash in $hash einfügen
                $hash->{HELPER}{ALLPATROLS} = \%allpatrols;

                @patrolkeys = sort(keys(%allpatrols));
                $patrollist = join(",",@patrolkeys);
                
                # print "ID von Tour1 ist : ". %allpatrols->{Tour1};
                # print "aus Hash: ".$hash->{HELPER}{ALLPRESETS}{Tour1};

                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Patrols",$patrollist);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                     
                # Logausgabe
                Log3($name, $verbose, "$name - PTZ Patrols of camera $camname retrieved");
            }
            
       } else {
            # die API-Operation war fehlerhaft
            # Errorcode aus JSON ermitteln
            $errorcode = $data->{'error'}->{'code'};

            # Fehlertext zum Errorcode ermitteln
            $error = SSCam_experror($hash,$errorcode);
			
            # Setreading 
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode",$errorcode);
            readingsBulkUpdate($hash,"Error",$error);
            readingsEndUpdate($hash, 1);
			
		    if ($errorcode =~ /(105|401)/) {
			   Log3($name, 2, "$name - ERROR - $errorcode - $error in operation $OpMode -> try new login");
		       return SSCam_login($hash,'SSCam_getapisites');
		    }
       
            # Logausgabe
            Log3($name, 2, "$name - ERROR - Operation $OpMode of Camera $camname was not successful. Errorcode: $errorcode - $error");
       }
   }
  
  # Token freigeben   
  $hash->{HELPER}{ACTIVE} = "off";

  if (AttrVal($name,"debugactivetoken",0)) {
      Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
  }

return;
}

#############################################################################################################################
#########              Ende Kameraoperationen mit NonblockingGet (nicht blockierender HTTP-Call)                #############
#############################################################################################################################



#############################################################################################################################
#########                                               Hilfsroutinen                                           #############
#############################################################################################################################



####################################################################################  
#   Login in SVS wenn kein oder ungültige Session-ID vorhanden ist
sub SSCam_login ($$) {
  my ($hash,$fret) = @_;
  my $name          = $hash->{NAME};
  my $serveraddr    = $hash->{SERVERADDR};
  my $serverport    = $hash->{SERVERPORT};
  my $apiauth       = $hash->{HELPER}{APIAUTH};
  my $apiauthpath   = $hash->{HELPER}{APIAUTHPATH};
  my $apiauthmaxver = $hash->{HELPER}{APIAUTHMAXVER};
  my $lrt = AttrVal($name,"loginRetries",3);
  my ($url,$param);
  
  delete $hash->{HELPER}{SID} if($hash->{HELPER}{SID});
    
  # Login und SID ermitteln
  Log3($name, 4, "$name - --- Begin Function SSCam_login ---");
  
  # Credentials abrufen
  my ($success, $username, $password) = SSCam_getcredentials($hash,0);
  
  unless ($success) {
      Log3($name, 2, "$name - Credentials couldn't be retrieved successfully - make sure you've set it with \"set $name credentials <username> <password>\"");
      
      $hash->{HELPER}{ACTIVE} = "off";
      if (AttrVal($name,"debugactivetoken",0)) {
          Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
      }      
      return;
  }
  
  if($hash->{HELPER}{LOGINRETRIES} >= $lrt) {
      # login wird abgebrochen, Freigabe Funktionstoken
      $hash->{HELPER}{ACTIVE} = "off"; 
      if (AttrVal($name,"debugactivetoken",0)) {
          Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
      }
	  Log3($name, 2, "$name - ERROR - Login or privilege of user $username unsuccessful"); 
      return;
  }

  my $httptimeout = AttrVal($name,"httptimeout",4);
  Log3($name, 5, "$name - HTTP-Call login will be done with httptimeout-Value: $httptimeout s");
  
  my $urlwopw;      # nur zur Anzeige bei verbose >= 4 und "showPassInLog" == 0
  
  # sid in Quotes einschliessen oder nicht -> bei Problemen mit 402 - Permission denied
  my $sid = AttrVal($name, "noQuotesForSID", "0") == 1 ? "sid" : "\"sid\"";
  
  if (AttrVal($name,"session","DSM") eq "SurveillanceStation") {
      $url = "http://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Login&account=$username&passwd=$password&session=SurveillanceStation&format=$sid";
      $urlwopw = "http://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Login&account=$username&passwd=*****&session=SurveillanceStation&format=$sid";
  } else {
      $url = "http://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Login&account=$username&passwd=$password&format=$sid"; 
      $urlwopw = "http://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Login&account=$username&passwd=*****&format=$sid";
  }
  
  AttrVal($name, "showPassInLog", "0") == 1 ? Log3($name, 4, "$name - Call-Out now: $url") : Log3($name, 4, "$name - Call-Out now: $urlwopw");
  $hash->{HELPER}{LOGINRETRIES}++;
  
  $param = {
               url      => $url,
               timeout  => $httptimeout,
               hash     => $hash,
			   user     => $username,
			   funcret  => $fret,
               method   => "GET",
               header   => "Accept: application/json",
               callback => \&SSCam_login_return
           };
   HttpUtils_NonblockingGet ($param);
}

sub SSCam_login_return ($) {
  my ($param, $err, $myjson) = @_;
  my $hash     = $param->{hash};
  my $name     = $hash->{NAME};
  my $username = $param->{user};
  my $fret     = $param->{funcret};
  my $subref   = \&$fret;
  my $success; 

  # Verarbeitung der asynchronen Rückkehrdaten aus sub "login_nonbl"
  if ($err ne "") {
      # ein Fehler bei der HTTP Abfrage ist aufgetreten
      Log3($name, 2, "$name - error while requesting ".$param->{url}." - $err");
        
      readingsSingleUpdate($hash, "Error", $err, 1);                               
        
      return SSCam_login($hash,$fret);
   
   } elsif ($myjson ne "") {
        # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)   
        
		# Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, $success) = SSCam_evaljson($hash,$myjson);
        unless ($success) {
            Log3($name, 4, "$name - no JSON-Data returned: ".$myjson);
            $hash->{HELPER}{ACTIVE} = "off";
            
            if (AttrVal($name,"debugactivetoken",0)) {
                Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
            }
            return;
        }
        
        my $data = decode_json($myjson);
        
        # Logausgabe decodierte JSON Daten
        Log3($name, 5, "$name - JSON decoded: ". Dumper $data);
   
        $success = $data->{'success'};
        
        if ($success) {
            # login war erfolgreich		
            my $sid = $data->{'data'}->{'sid'};
             
            # Session ID in hash eintragen
            $hash->{HELPER}{SID} = $sid;
       
            # Setreading 
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode","none");
            readingsBulkUpdate($hash,"Error","none");
            readingsEndUpdate($hash, 1);
       
            # Logausgabe
            Log3($name, 4, "$name - Login of User $username successful - SID: $sid");
			
			return &$subref($hash);
        
		} else {          
            # Errorcode aus JSON ermitteln
            my $errorcode = $data->{'error'}->{'code'};
       
            # Fehlertext zum Errorcode ermitteln
            my $error = SSCam_experrorauth($hash,$errorcode);

            # Setreading 
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode",$errorcode);
            readingsBulkUpdate($hash,"Error",$error);
            readingsEndUpdate($hash, 1);
       
            # Logausgabe
            Log3($name, 3, "$name - Login of User $username unsuccessful. Code: $errorcode - $error - try again"); 
             
            return SSCam_login($hash,$fret);
       }
   }
return SSCam_login($hash,$fret);
}

###################################################################################  
#      Funktion logout
###################################################################################
sub SSCam_logout ($) {
   my ($hash) = @_;
   my $name             = $hash->{NAME};
   my $serveraddr       = $hash->{SERVERADDR};
   my $serverport       = $hash->{SERVERPORT};
   my $apiauth          = $hash->{HELPER}{APIAUTH};
   my $apiauthpath      = $hash->{HELPER}{APIAUTHPATH};
   my $apiauthmaxver    = $hash->{HELPER}{APIAUTHMAXVER};
   my $sid              = $hash->{HELPER}{SID};
   my $url;
   my $param;
   my $httptimeout;
    
   Log3($name, 4, "$name - ####################################################"); 
   Log3($name, 4, "$name - ###    start cam operation $hash->{OPMODE}          "); 
   Log3($name, 4, "$name - ####################################################"); 
   Log3($name, 4, "$name - --- Begin Function SSCam_logout nonblocking ---");
    
   $httptimeout = AttrVal($name,"httptimeout",4);
   Log3($name, 5, "$name - HTTP-Call will be done with httptimeout-Value: $httptimeout s");
  
   if (AttrVal($name,"session","DSM") eq "SurveillanceStation") {
       $url = "http://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Logout&session=SurveillanceStation&_sid=$sid";
   } else {
       $url = "http://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Logout&_sid=$sid";
   }

   $param = {
            url      => $url,
            timeout  => $httptimeout,
            hash     => $hash,
            method   => "GET",
            header   => "Accept: application/json",
            callback => \&SSCam_logout_return
            };
   
   HttpUtils_NonblockingGet ($param);
}

sub SSCam_logout_return ($) {  
   my ($param, $err, $myjson) = @_;
   my $hash                   = $param->{hash};
   my $name                   = $hash->{NAME};
   my $sid                    = $hash->{HELPER}{SID};
   my ($success, $username)   = SSCam_getcredentials($hash,0);
   my $OpMode                 = $hash->{OPMODE};
   my $data;
   my $error;
   my $errorcode;
  
   if($err ne "") {
       # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
       Log3($name, 2, "$name - error while requesting ".$param->{url}." - $err");
        
       readingsSingleUpdate($hash, "Error", $err, 1);                                     	      
   } elsif($myjson ne "") {
       # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
       Log3($name, 4, "$name - URL-Call: ".$param->{url});
        
       # Evaluiere ob Daten im JSON-Format empfangen wurden
       ($hash, $success) = SSCam_evaljson($hash,$myjson);
        
       unless ($success) {
           Log3($name, 4, "$name - Data returned: ".$myjson);
            
           $hash->{HELPER}{ACTIVE} = "off";
            
           if (AttrVal($name,"debugactivetoken",0)) {
               Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
           }
           return;
       }
        
       $data = decode_json($myjson);
        
       # Logausgabe decodierte JSON Daten
       Log3($name, 4, "$name - JSON returned: ". Dumper $data);
   
       $success = $data->{'success'};

       if ($success) {
           # die Logout-URL konnte erfolgreich aufgerufen werden                        
           Log3($name, 4, "$name - Session of User $username has ended - SID: \"$sid\" has been deleted");
             
       } else {
           # Errorcode aus JSON ermitteln
           $errorcode = $data->{'error'}->{'code'};

           # Fehlertext zum Errorcode ermitteln
           $error = &SSCam_experrorauth($hash,$errorcode);

           Log3($name, 2, "$name - ERROR - Logout of User $username was not successful, however SID: \"$sid\" has been deleted. Errorcode: $errorcode - $error");
       }
   }   
   # Session-ID aus Helper-hash löschen
   delete $hash->{HELPER}{SID};
   
   # ausgeführte Funktion ist erledigt (auch wenn logout nicht erfolgreich), Freigabe Funktionstoken
   $hash->{HELPER}{ACTIVE} = "off";  
   
   if (AttrVal($name,"debugactivetoken",0)) {
       Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
   }
return;
}

###############################################################################
#   Test ob JSON-String empfangen wurde
###############################################################################
sub SSCam_evaljson($$) { 
  my ($hash,$myjson) = @_;
  my $OpMode  = $hash->{OPMODE};
  my $name    = $hash->{NAME};
  my $success = 1;
  
  eval {decode_json($myjson)} or do 
  {
      if($hash->{HELPER}{RUNVIEW} =~ m/^live_.*hls$/ || $OpMode =~ m/^.*_hls$/) {
          # HLS aktivate/deaktivate bringt kein JSON wenn bereits aktiviert/deaktiviert
          Log3($name, 5, "$name - HLS-activation data return: $myjson");
          if ($myjson =~ m/{"success":true}/) {
              $success = 1;
              $myjson  = '{"success":true}';    
          } 
      } else {
          $success = 0;
          # Setreading 
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash,"Errorcode","none");
          readingsBulkUpdate($hash,"Error","malformed JSON string received");
          readingsEndUpdate($hash, 1);  
      }
  };
  
return($hash,$success,$myjson);
}

######################################################################################################
#      Refresh eines Raumes aus $hash->{HELPER}{STRMROOM}
#      bzw. Longpoll von SSCam bzw. eines SSCamSTRM Devices wenn
#      $hash->{HELPER}{STRMDEV} gefüllt 
#      $hash, $pload (1=Page reload), $longpoll SSCam(1=Event), $longpoll SSCamSTRM (1=Event)
######################################################################################################
sub SSCam_refresh($$$$) { 
  my ($hash,$pload,$lpoll_scm,$lpoll_strm) = @_;
  my $name = $hash->{NAME};
  my $fpr  = 0;
  
  # Kontext des SSCamSTRM-Devices speichern für SSCam_refresh
  my $sd  = defined($hash->{HELPER}{STRMDEV})?$hash->{HELPER}{STRMDEV}:"\"not defined\"";       # Name des aufrufenden SSCamSTRM-Devices
  my $sr  = defined($hash->{HELPER}{STRMROOM})?$hash->{HELPER}{STRMROOM}:"\"not defined\"";     # Raum aus dem das SSCamSTRM-Device die Funktion aufrief
  my $sl  = defined($hash->{HELPER}{STRMDETAIL})?$hash->{HELPER}{STRMDETAIL}:"\"not defined\""; # Name des SSCamSTRM-Devices (wenn Detailansicht)
  $fpr    = AttrVal($hash->{HELPER}{STRMDEV},"forcePageRefresh",0) if(defined $hash->{HELPER}{STRMDEV});
  Log3($name, 4, "$name - SSCam_refresh - caller: $sd, callerroom: $sr, detail: $sl, forcePageRefresh: $fpr");
  
  if($pload && defined($hash->{HELPER}{STRMROOM}) && defined($hash->{HELPER}{STRMDETAIL})) {
      if($hash->{HELPER}{STRMROOM} && !$hash->{HELPER}{STRMDETAIL} && !$fpr) {
          # trifft zu wenn in einer Raumansicht
	      my @rooms = split(",",$hash->{HELPER}{STRMROOM});
	      foreach (@rooms) {
	          my $room = $_;
              { map { FW_directNotify("FILTER=room=$room", "#FHEMWEB:$_", "location.reload('true')", "") } devspec2array("TYPE=FHEMWEB") } 
	      }
      } elsif ( !$hash->{HELPER}{STRMROOM} || $hash->{HELPER}{STRMDETAIL} || $fpr ) {
          # trifft zu bei Detailansicht oder im FLOORPLAN bzw. Dashboard oder wenn Seitenrefresh mit dem 
          # SSCamSTRM-Attribut "forcePageRefresh" erzwungen wird
          { map { FW_directNotify("#FHEMWEB:$_", "location.reload('true')", "") } devspec2array("TYPE=FHEMWEB") }
      } 
  }
  
  # Aufnahmestatus in state abbilden & Longpoll SSCam-Device wenn Event 1
  my $st = (ReadingsVal($name, "Record", "") eq "Start")?"on":"off";  
  if($lpoll_scm) {
      readingsSingleUpdate($hash,"state", $st, 1);
  } else {
      readingsSingleUpdate($hash,"state", $st, 0);  
  }
  
  # Longpoll des SSCamSTRM-Device
  if($hash->{HELPER}{STRMDEV}) {
      my $strmhash = $defs{$hash->{HELPER}{STRMDEV}};  
      if($lpoll_strm) {
          readingsSingleUpdate($strmhash,"state", $st, 1);
      } else {
          readingsSingleUpdate($strmhash,"state", $st, 0);  
      } 
  }
  
return;
}

###############################################################################
#               Test ob MODEL=SVS (sonst ist es eine Cam)
###############################################################################
sub SSCam_IsModelCam($){ 
  my ($hash)= @_;
  my $m = ($hash->{MODEL} ne "SVS")?1:0;
return($m);
}

###############################################################################
#               JSON Boolean Test und Mapping
###############################################################################
sub SSCam_jboolmap($){ 
  my ($bool)= @_;
  
  if(JSON::is_bool($bool)) {
      $bool = $bool?"true":"false";
  }
  
return $bool;
}

###############################################################################
# Schnappschußgalerie abrufen (snapGalleryBoost) o. nur Info des letzten Snaps
###############################################################################
sub SSCam_snaplimsize ($) {      
  my ($hash)= @_;
  my $name  = $hash->{NAME};
  my ($slim,$ssize);
  
  if(!AttrVal($name,"snapGalleryBoost",0)) {
      $slim  = 1;
      $ssize = 0;			
  } else {
      $hash->{HELPER}{GETSNAPGALLERY} = 1;
	  $slim = AttrVal($name,"snapGalleryNumber",$SSCam_slim);    # Anzahl der abzurufenden Snaps
	  my $sg = AttrVal($name,"snapGallerySize","Icon");          # Auflösung Image
	  $ssize = ($sg eq "Icon")?1:2;
  }	
return ($slim,$ssize);
}

###############################################################################
#              Helper für listLog-Argumente extrahieren 
###############################################################################
sub SSCam_extlogargs ($$) { 
  my ($hash,$a) = @_;

  $hash->{HELPER}{LISTLOGSEVERITY} = (split("severity:",$a))[1] if(lc($a) =~ m/^severity:.*/);
  $hash->{HELPER}{LISTLOGLIMIT}    = (split("limit:",$a))[1] if(lc($a) =~ m/^limit:.*/);
  $hash->{HELPER}{LISTLOGMATCH}    = (split("match:",$a))[1] if(lc($a) =~ m/^match:.*/);
  
return;
}

###############################################################################
#              Helper für optimizeParams-Argumente extrahieren 
###############################################################################
sub SSCam_extoptpar ($$$) { 
  my ($hash,$a,$cpcl) = @_;

  $hash->{HELPER}{MIRROR}   = (split("mirror:",$a))[1] if(lc($a) =~ m/^mirror:.*/);
  $hash->{HELPER}{FLIP}     = (split("flip:",$a))[1] if(lc($a) =~ m/^flip:.*/);
  $hash->{HELPER}{ROTATE}   = (split("rotate:",$a))[1] if(lc($a) =~ m/^rotate:.*/);
  $hash->{HELPER}{NTPSERV}  = (split("ntp:",$a))[1] if(lc($a) =~ m/^ntp:.*/);
  
  $hash->{HELPER}{CHKLIST}  = ($hash->{HELPER}{NTPSERV}?$cpcl->{ntp}:0)+
                              ($hash->{HELPER}{MIRROR}?$cpcl->{mirror}:0)+
                              ($hash->{HELPER}{FLIP}?$cpcl->{flip}:0)+
							  ($hash->{HELPER}{ROTATE}?$cpcl->{rotate}:0);
  
return;
}

###############################################################################
# Clienthash übernehmen oder zusammenstellen
# Identifikation ob über FHEMWEB ausgelöst oder nicht -> erstellen $hash->CL
sub SSCam_getclhash ($;$$) {      
  my ($hash,$nobgd)= @_;
  my $name  = $hash->{NAME};
  my $ret;
  
  if($nobgd) {
      # nur übergebenen CL-Hash speichern, 
	  # keine Hintergrundverarbeitung bzw. synthetische Erstellung CL-Hash
	  $hash->{HELPER}{CL}{1} = $hash->{CL};
	  return undef;
  }

  if (!defined($hash->{CL})) {
      # Clienthash wurde nicht übergeben und wird erstellt (FHEMWEB Instanzen mit canAsyncOutput=1 analysiert)
	  my $outdev;
	  my @webdvs = devspec2array("TYPE=FHEMWEB:FILTER=canAsyncOutput=1:FILTER=STATE=Connected");
	  my $i = 1;
      foreach (@webdvs) {
          $outdev = $_;
          next if(!$defs{$outdev});
		  $hash->{HELPER}{CL}{$i}->{NAME} = $defs{$outdev}{NAME};
          $hash->{HELPER}{CL}{$i}->{NR}   = $defs{$outdev}{NR};
		  $hash->{HELPER}{CL}{$i}->{COMP} = 1;
          $i++;				  
      }
  } else {
      # übergebenen CL-Hash in Helper eintragen
	  $hash->{HELPER}{CL}{1} = $hash->{CL};
  }
	  
  # Clienthash auflösen zur Fehlersuche (aufrufende FHEMWEB Instanz
  if (defined($hash->{HELPER}{CL}{1})) {
      for (my $k=1; (defined($hash->{HELPER}{CL}{$k})); $k++ ) {
	      Log3($name, 4, "$name - Clienthash number: $k");
          while (my ($key,$val) = each(%{$hash->{HELPER}{CL}{$k}})) {
              $val = $val?$val:" ";
              Log3($name, 4, "$name - Clienthash: $key -> $val");
          }
	  }
  } else {
      Log3($name, 2, "$name - Clienthash was neither delivered nor created !");
	  $ret = "Clienthash was neither delivered nor created. Can't use asynchronous output for function.";
  }
  
return ($ret);
}

###############################################################################
#     konvertiere alle ptzPanel_rowXX-attribute zu html-Code für 
#     das generierte Widget und das weblink-Device ptzpanel_$name
###############################################################################
sub SSCam_ptzpanel($;$$) {
  my ($name,$ptzcdev,$ptzcontrol)     = @_; 
  my $hash       = $defs{$name};
  my $iconpath   = AttrVal("$name","ptzPanel_iconPath","www/images/sscam");
  my $iconprefix = AttrVal("$name","ptzPanel_iconPrefix","black_btn_");
  my $rowisset   = 0;
  my $ptz_ret;
  my $row;
  
  my @vl = split (/\.|-/,ReadingsVal($name, "SVSversion", ""));
  if(@vl) {
      my $actvs = $vl[0];
      $actvs   .= $vl[1];
      return "" if($actvs <= 71);
  }
  
  $ptz_ret = "<div class=\"ptzpanel\">";
  $ptz_ret.= '<table class="rc_body">';

  foreach my $rownr (0..9) {
      $rownr = sprintf("%2.2d",$rownr);
      $row   = AttrVal("$name","ptzPanel_row$rownr",undef);
      next if (!$row);
      $rowisset = 1;
      $ptz_ret .= "<tr>";
      my @btn = split (",",$row);                    # die Anzahl Buttons in einer Reihe
      
      foreach my $btnnr (0..$#btn) {                 
          $ptz_ret .= '<td class="rc_button">';
          if ($btn[$btnnr] ne "") {
              my $cmd;
              my $img;
              if ($btn[$btnnr] =~ /(.*?):(.*)/) {    # enthält Komando -> <command>:<image>
                  $cmd = $1;
                  $img = $2;
              } else {                               # button has format <command> or is empty
                  $cmd = $btn[$btnnr];
                  $img = $btn[$btnnr];
              }
		      if ($img =~ m/\.svg/) {                # Verwendung für SVG's
		          $img = FW_makeImage($img, $cmd, "rc-button");
		      } else {
                  $img = "<img src=\"$FW_ME/$iconpath/$iconprefix$img\">";                      # $FW_ME = URL-Pfad unter dem der FHEMWEB-Server via HTTP erreichbar ist, z.B. /fhem
		      }
              if ($cmd || $cmd eq "0") {
                  # $cmd = "cmd.$name=set $name $cmd";
                  $cmd = "cmd=set $name $cmd";
                  $ptz_ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmd')\">$img</a>";  # $FW_subdir = Sub-path in URL, used by FLOORPLAN/weblink
              } else {
                  $ptz_ret .= $img;
              }
          }
          $ptz_ret .= "</td>";
          $ptz_ret .= "\n";    
      }
      $ptz_ret .= "</tr>\n";
  }
  
  $ptz_ret .= "</table>";
  $ptz_ret .= "</div>";
  
  if ($rowisset) {
      return $ptz_ret;
  } else {
      return "";
  }
}

###############################################################################
#     spezielle Attribute für PTZ-ControlPanel verfügbar machen
###############################################################################
sub SSCam_addptzattr($) {
  my ($name) = @_;
  my $hash   = $defs{$name};
  my $actvs;
  
  my @vl = split (/\.|-/,ReadingsVal($name, "SVSversion", ""));
  if(@vl) {
      $actvs = $vl[0];
      $actvs.= $vl[1];
  }
  return if(ReadingsVal($name,"DeviceType","Camera") ne "PTZ" || $actvs <= 71);
  
  foreach my $n (0..9) { 
      $n = sprintf("%2.2d",$n);
      addToDevAttrList($name, "ptzPanel_row$n");
  }
  if(ReadingsVal("$name","Presets","") ne "") {
      $attr{$name}{userattr} =~ s/ptzPanel_Home:$hash->{HELPER}{OLDPRESETS}//g if($hash->{HELPER}{OLDPRESETS} && ReadingsVal("$name","Presets","") ne $hash->{HELPER}{OLDPRESETS});
      $hash->{HELPER}{OLDPRESETS} = ReadingsVal("$name","Presets","");
      addToDevAttrList($name, "ptzPanel_Home:".ReadingsVal("$name","Presets",""));
  }
  addToDevAttrList($name, "ptzPanel_iconPrefix");
  addToDevAttrList($name, "ptzPanel_iconPath");
  addToDevAttrList($name, "ptzPanel_use:0,1");
  
  # PTZ Panel Widget initial generieren
  my $upleftfast    = "move upleft";
  my $upfast        = "move up";
  my $uprightfast   = "move upright";
  my $upleft        = "move upleft 0.5";
  my $up            = "move up 0.5";
  my $upright       = "move upright 0.5";
  my $leftfast      = "move left";
  my $left          = "move left 0.5";
  my $home          = "goPreset ".AttrVal($name,"ptzPanel_Home",ReadingsVal($name,"PresetHome",""));  
  my $right         = "move right 0.5";
  my $rightfast     = "move right";
  my $downleft      = "move downleft 0.5";                       
  my $down          = "move down 0.5";
  my $downright     = "move downright 0.5";
  my $downleftfast  = "move downleft";
  my $downfast      = "move down";
  my $downrightfast = "move downright";
  
  $attr{$name}{ptzPanel_row00} = "$upleftfast:CAMUPLEFTFAST.png,:CAMBLANK.png,$upfast:CAMUPFAST.png,:CAMBLANK.png,$uprightfast:CAMUPRIGHTFAST.png" 
      if(!AttrVal($name,"ptzPanel_row00",undef));
  $attr{$name}{ptzPanel_row01} = ":CAMBLANK.png,$upleft:CAMUPLEFT.png,$up:CAMUP.png,$upright:CAMUPRIGHT.png"
      if(!AttrVal($name,"ptzPanel_row01",undef));  
  $attr{$name}{ptzPanel_row02} = "$leftfast:CAMLEFTFAST.png,$left:CAMLEFT.png,$home:CAMHOME.png,$right:CAMRIGHT.png,$rightfast:CAMRIGHTFAST.png"
      if(!AttrVal($name,"ptzPanel_row02",undef) || $home ne $hash->{HELPER}{OLDPTZHOME});  
  $attr{$name}{ptzPanel_row03} = ":CAMBLANK.png,$downleft:CAMDOWNLEFT.png,$down:CAMDOWN.png,$downright:CAMDOWNRIGHT.png"
      if(!AttrVal($name,"ptzPanel_row03",undef));  
  $attr{$name}{ptzPanel_row04} = "$downleftfast:CAMDOWNLEFTFAST.png,:CAMBLANK.png,$downfast:CAMDOWNFAST.png,:CAMBLANK.png,$downrightfast:CAMDOWNRIGHTFAST.png"
      if(!AttrVal($name,"ptzPanel_row04",undef));
      
  $hash->{HELPER}{OLDPTZHOME} = $home;
  $hash->{".ptzhtml"} = "";     # SSCam_ptzpanel wird neu durchlaufen
  
return;
}

######################################################################################
#              Stream einer Kamera - Kamera Liveview weblink device
#              API: SYNO.SurveillanceStation.VideoStreaming
#              Methode: GetLiveViewPath
######################################################################################
sub SSCam_StreamDev($$$) {
  my ($camname,$strmdev,$fmt) = @_; 
  my $hash               = $defs{$camname};
  my $wltype             = $hash->{HELPER}{WLTYPE}; 
  my $serveraddr         = $hash->{SERVERADDR};
  my $serverport         = $hash->{SERVERPORT};
  my $apivideostm        = $hash->{HELPER}{APIVIDEOSTM};
  my $apivideostmpath    = $hash->{HELPER}{APIVIDEOSTMPATH};
  my $apivideostmmaxver  = $hash->{HELPER}{APIVIDEOSTMMAXVER}; 
  my $apiaudiostm        = $hash->{HELPER}{APIAUDIOSTM};
  my $apiaudiostmpath    = $hash->{HELPER}{APIAUDIOSTMPATH};
  my $apiaudiostmmaxver  = $hash->{HELPER}{APIAUDIOSTMMAXVER};
  my $apivideostms       = $hash->{HELPER}{APIVIDEOSTMS};  
  my $apivideostmspath   = $hash->{HELPER}{APIVIDEOSTMSPATH};
  my $apivideostmsmaxver = $hash->{HELPER}{APIVIDEOSTMSMAXVER};
  my $camid              = $hash->{CAMID};
  my $sid                = $hash->{HELPER}{SID};
  my ($cause,$ret,$link,$audiolink,$devWlink,$wlhash,$alias,$wlalias);
  
  # Kontext des SSCamSTRM-Devices speichern für SSCam_refresh
  $hash->{HELPER}{STRMDEV}    = $strmdev;                   # Name des aufrufenden SSCamSTRM-Devices
  $hash->{HELPER}{STRMROOM}   = $FW_room?$FW_room:"";       # Raum aus dem das SSCamSTRM-Device die Funktion aufrief
  $hash->{HELPER}{STRMDETAIL} = $FW_detail?$FW_detail:"";   # Name des SSCamSTRM-Devices (wenn Detailansicht)
  
  # Definition Tasten
  my $cmdstop       = "cmd=set $camname stopView";                                                      # Stream deaktivieren
  my $imgstop       = "<img src=\"$FW_ME/www/images/default/remotecontrol/black_btn_POWEROFF3.png\">";
  my $cmdhlsreact   = "cmd=set $camname hlsreactivate";                                                 # HLS Stream reaktivieren
  my $imghlsreact   = "<img src=\"$FW_ME/www/images/default/remotecontrol/black_btn_BACKDroid.png\">";
  my $cmdmjpegrun   = "cmd=set $camname runView live_fw";                                               # MJPEG Stream aktivieren  
  my $imgmjpegrun   = "<img src=\"$FW_ME/www/images/sscam/black_btn_MJPEG.png\">";
  my $cmdhlsrun     = "cmd=set $camname runView live_fw_hls";                                           # HLS Stream aktivieren  
  my $imghlsrun     = "<img src=\"$FW_ME/www/images/sscam/black_btn_HLS.png\">";
  my $cmdlrirun     = "cmd=set $camname runView lastrec_fw";                                            # Last Record IFrame  
  my $imglrirun     = "<img src=\"$FW_ME/www/images/sscam/black_btn_LASTRECIFRAME.png\">";
  my $cmdlh264run   = "cmd=set $camname runView lastrec_fw_MPEG4/H.264";                                # Last Record H.264  
  my $imglh264run   = "<img src=\"$FW_ME/www/images/sscam/black_btn_LRECH264.png\">";
  my $cmdlmjpegrun  = "cmd=set $camname runView lastrec_fw_MJPEG";                                      # Last Record MJPEG  
  my $imglmjpegrun  = "<img src=\"$FW_ME/www/images/sscam/black_btn_LRECMJPEG.png\">";
  my $cmdlsnaprun   = "cmd=set $camname runView lastsnap_fw";                                           # Last SNAP  
  my $imglsnaprun   = "<img src=\"$FW_ME/www/images/sscam/black_btn_LSNAP.png\">";
  my $cmdrecendless = "cmd=set $camname on 0";                                                          # Endlosaufnahme Start  
  my $imgrecendless = "<img src=\"$FW_ME/www/images/sscam/black_btn_RECSTART.png\">";
  my $cmdrecstop    = "cmd=set $camname off";                                                           # Aufnahme Stop  
  my $imgrecstop    = "<img src=\"$FW_ME/www/images/sscam/black_btn_RECSTOP.png\">";
  my $cmddosnap     = "cmd=set $camname snap";                                                          # Snapshot auslösen 
  my $imgdosnap     = "<img src=\"$FW_ME/www/images/sscam/black_btn_DOSNAP.png\">";
  
  my $ha     = AttrVal($camname, "htmlattr", 'width="500" height="325"');   # HTML Attribute der Cam
  $ha        = AttrVal($strmdev, "htmlattr", $ha);                          # htmlattr mit htmattr Streaming-Device übersteuern 
  my $hlslfw = (ReadingsVal($camname,"CamStreamFormat","MJPEG") eq "HLS")?"live_fw_hls,":undef;
  my $StmKey = ReadingsVal($camname,"StmKey",undef);
  
  $ret  = "<div class=\"makeTable wide\">";
  $ret .= '<table class="block wide internals">';
  $ret .= '<tbody>';
  $ret .= '<tr class="odd">';  

  if(!$StmKey || ReadingsVal($camname, "Availability", "") ne "enabled" || IsDisabled($camname)) {
      # Ausgabe bei Fehler
      my $cam = AttrVal($camname, "alias", $camname);
      $cause = !$StmKey?"Cam $cam has no Reading \"StmKey\" set !":"Cam \"$cam\" is disabled";
      $cause = "Cam \"$cam\" is disabled" if(IsDisabled($camname));
      $ret .= "<td> <br> <b> $cause </b> <br><br></td>";
      $ret .= '</tr>';
      $ret .= '</tbody>';
      $ret .= '</table>';
      $ret .= '</div>';
      return $ret; 
  }
  
  if($fmt =~ /mjpeg/) {  
      $link      = "http://$serveraddr:$serverport/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsmaxver&method=Stream&cameraId=$camid&format=mjpeg&_sid=$sid"; 
      $audiolink = "http://$serveraddr:$serverport/webapi/$apiaudiostmpath?api=$apiaudiostm&version=$apiaudiostmmaxver&method=Stream&cameraId=$camid&_sid=$sid"; 
      $ret .= "<td><img src=$link $ha> </td>"; 
      if(AttrVal($camname,"ptzPanel_use",1)) {
          my $ptz_ret = SSCam_ptzpanel($camname);
          if($ptz_ret) { 
              $ret .= "<td>$ptz_ret</td>";
          }
      }
      if($audiolink && ReadingsVal($camname, "CamAudioType", "Unknown") !~ /Unknown/) {
          $ret .= '</tr>';
          $ret .= '<tr class="odd">';
          $ret .= "<td><audio src=$audiolink preload='none' volume='0.5' controls>
                       Your browser does not support the audio element.      
                       </audio></td>";
      }      
  
  } elsif($fmt =~ /switched/) {
      my $wltype = $hash->{HELPER}{WLTYPE};
      $link = $hash->{HELPER}{LINK};
      
      if($link && $wltype =~ /image|iframe|video|base64img|embed|hls/) {
          if($wltype =~ /image/) {
              $ret .= "<td><img src=$link $ha><br>";
              $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdstop')\">$imgstop </a>"; 
              if(ReadingsVal($camname, "Record", "Stop") eq "Stop") {
                  # Aufnahmebutton endlos Start
                  $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdrecendless')\">$imgrecendless </a>";
              }	else {
                  # Aufnahmebutton Stop
                  $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdrecstop')\">$imgrecstop </a>";
              }	      
              $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmddosnap')\">$imgdosnap </a>";               
              $ret .= "</td>";
              if(AttrVal($camname,"ptzPanel_use",1)) {
                  my $ptz_ret = SSCam_ptzpanel($camname);
                  if($ptz_ret) { 
                      $ret .= "<td>$ptz_ret</td>";
                  }
              }
              if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($camname, "CamAudioType", "Unknown") !~ /Unknown/) {
                  $ret .= '<tr class="odd">';
                  $ret .= "<td><audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>
                               Your browser does not support the audio element.      
                               </audio>";
              }         
          
          } elsif ($wltype =~ /iframe/) {
              $ret .= "<td><iframe src=$link $ha controls autoplay>
                       Iframes disabled
                       </iframe><br>";
              $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdstop')\">$imgstop </a>";               
              $ret .= "</td>";
              if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($camname, "CamAudioType", "Unknown") !~ /Unknown/) {
                  $ret .= '</tr>';
                  $ret .= '<tr class="odd">';
                  $ret .= "<td><audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>
                               Your browser does not support the audio element.      
                               </audio></td>";
              }
          
          } elsif ($wltype =~ /video/) {
              $ret .= "<td><video $ha controls autoplay> 
                       <source src=$link type=\"video/mp4\"> 
                       <source src=$link type=\"video/ogg\">
                       <source src=$link type=\"video/webm\">
                       Your browser does not support the video tag
                       </video><br>";
              $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdstop')\">$imgstop </a>"; 
              $ret .= "</td>";
              if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($camname, "CamAudioType", "Unknown") !~ /Unknown/) {
                  $ret .= '<tr class="odd">';
                  $ret .= "<td><audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>
                               Your browser does not support the audio element.      
                               </audio></td>";
                  $ret .= '</tr>';
              }
          } elsif($wltype =~ /base64img/) {
              $ret .= "<td><img src='data:image/jpeg;base64,$link' $ha><br>";
              $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdstop')\">$imgstop </a>";
              $ret .= "</td>";
		  
          } elsif($wltype =~ /embed/) {
              $ret .= "<td><embed src=$link $ha></td>";
          
          } elsif($wltype =~ /hls/) {
              $ret .= "<td><video $ha controls autoplay>
                       <source src=$link type=\"application/x-mpegURL\">
                       <source src=$link type=\"video/MP2T\">
                       Your browser does not support the video tag
                       </video><br>";
              $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdstop')\">$imgstop </a>";
              $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdhlsreact')\">$imghlsreact </a>";
              if(ReadingsVal($camname, "Record", "Stop") eq "Stop") {
                  # Aufnahmebutton endlos Start
                  $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdrecendless')\">$imgrecendless </a>";
              }	else {
                  # Aufnahmebutton Stop
                  $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdrecstop')\">$imgrecstop </a>";
              }		
              $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmddosnap')\">$imgdosnap </a>";                   
              $ret .= "</td>";
              if(AttrVal($camname,"ptzPanel_use",1)) {
                  my $ptz_ret = SSCam_ptzpanel($camname);
                  if($ptz_ret) { 
                      $ret .= "<td>$ptz_ret</td>";
                  }
              }
          } 
      } else {
          my $cam = AttrVal($camname, "alias", $camname);
          $cause = "Playback cam \"$cam\" switched off";
          $ret .= "<td> <br> <b> $cause </b> <br><br>";
          $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdmjpegrun')\">$imgmjpegrun </a>";
          $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdhlsrun')\">$imghlsrun </a>" if($hlslfw);  
          $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdlrirun')\">$imglrirun </a>"; 
          $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdlh264run')\">$imglh264run </a>";
          $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdlmjpegrun')\">$imglmjpegrun </a>";
          $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdlsnaprun')\">$imglsnaprun </a>";            
          $ret .= "</td>";    
      }
  } else {
      $cause = "Videoformat not supported";
      $ret .= "<td> <br> <b> $cause </b> <br><br></td>";  
  }
  
  $ret .= '</tr>';
  $ret .= '</tbody>';
  $ret .= '</table>';
  $ret .= '</div>';

return $ret;
}

###############################################################################
#                   Schnappschußgalerie zusammenstellen
###############################################################################
sub composegallery ($;$$) { 
  my ($name,$strmdev,$model) = @_;
  my $hash     = $defs{$name};
  my $camname  = $hash->{CAMNAME};
  my $allsnaps = $hash->{HELPER}{".SNAPHASH"}; # = \%allsnaps
  my $sgc      = AttrVal($name,"snapGalleryColumns",3);          # Anzahl der Images in einer Tabellenzeile
  my $lss      = ReadingsVal($name, "LastSnapTime", " ");        # Zeitpunkt neueste Aufnahme
  my $lang     = AttrVal("global","language","EN");              # Systemsprache       
  my $limit    = $hash->{HELPER}{SNAPLIMIT};                     # abgerufene Anzahl Snaps
  my $totalcnt = $hash->{HELPER}{TOTALCNT};                      # totale Anzahl Snaps
  $limit       = $totalcnt if ($limit > $totalcnt);              # wenn weniger Snaps vorhanden sind als $limit -> Text in Anzeige korrigieren
  my $lupt     = ((ReadingsTimestamp($name,"LastSnapTime"," ") gt ReadingsTimestamp($name,"LastUpdateTime"," ")) 
                 ? ReadingsTimestamp($name,"LastSnapTime"," ") 
				 : ReadingsTimestamp($name,"LastUpdateTime"," "));  # letzte Aktualisierung
  $lupt =~ s/ / \/ /;
  
  my $ha = AttrVal($name, "snapGalleryHtmlAttr", AttrVal($name, "htmlattr", 'width="500" height="325"'));
  
  # falls "composegallery" durch ein mit "createSnapGallery" angelegtes Device aufgerufen wird
  my ($devWlink);
  if ($strmdev) {
      if($defs{$strmdev}{TYPE} ne "SSCamSTRM") {
          # Abfrage wegen Kompatibilität zu "alten" compose mit weblink-Modul
          my $sdalias = AttrVal($strmdev, "alias", $strmdev);   # Linktext als Aliasname oder Devicename setzen
          $devWlink   = "<a href=\"/fhem?detail=$strmdev\">$sdalias</a><br>"; 
      }   
      my $wlha = AttrVal($strmdev, "htmlattr", undef); 
      $ha      = (defined($wlha))?$wlha:$ha;             # htmlattr vom weblink-Device übernehmen falls von wl-Device aufgerufen und gesetzt   
  } else {
      $devWlink = " ";
  }
  
  # wenn Weblink genutzt wird und attr "snapGalleryBoost" nicht gesetzt ist -> Warnung in Gallerie ausgeben
  my $sgbnote = " ";
  if($strmdev && !AttrVal($name,"snapGalleryBoost",0)) {
      $sgbnote = "<b>CAUTION</b> - No snapshots can be retrieved. Please set the attribute \"snapGalleryBoost=1\" in device <a href=\"/fhem?detail=$name\">$name</a>" if ($lang eq "EN");
	  $sgbnote = "<b>ACHTUNG</b> - Es können keine Schnappschüsse abgerufen werden. Bitte setzen sie das Attribut \"snapGalleryBoost=1\" im Device <a href=\"/fhem?detail=$name\">$name</a>" if ($lang eq "DE");
  }
  
  my $header;
  if ($lang eq "EN") {
      $header  = "Snapshots ($limit/$totalcnt) of camera <b>$camname</b> - newest Snapshot: $lss<br>";
	  $header .= " (Possibly another snapshots are available. Last recall: $lupt)<br>" if(AttrVal($name,"snapGalleryBoost",0));
  } else {
      $header  = "Schnappschüsse ($limit/$totalcnt) von Kamera <b>$camname</b> - neueste Aufnahme: $lss <br>";
	  $header .= " (Eventuell sind neuere Aufnahmen verfügbar. Letzter Abruf: $lupt)<br>" if(AttrVal($name,"snapGalleryBoost",0));
  }
  $header .= $sgbnote;
  
  my $gattr  = (AttrVal($name,"snapGallerySize","Icon") eq "Full")?$ha:" ";    
  
  my @as = sort{$a <=>$b}keys%{$allsnaps};
  
  # Ausgabetabelle erstellen
  my ($htmlCode,$ct);
  $htmlCode  = "<html>";
  $htmlCode .= sprintf("$devWlink <div class=\"makeTable wide\"; style=\"text-align:center\"> $header <br>");
  $htmlCode .= "<table class=\"block wide internals\">";
  $htmlCode .= "<tbody>";
  $htmlCode .= "<tr class=\"odd\">";
  my $cell   = 1;
  
  foreach my $key (@as) {
      $ct = $allsnaps->{$key}{createdTm};
	  my $html = sprintf("<td>$ct<br /> <img $gattr src=\"data:image/jpeg;base64,$allsnaps->{$key}{imageData}\" /> </td>" );

      $cell++;

      if ( $cell == $sgc+1 ) {
        $htmlCode .= $html;
        $htmlCode .= "</tr>";
        $htmlCode .= "<tr class=\"odd\">";
        $cell = 1;
      } else {
        $htmlCode .= $html;
      }
  }

  if ( $cell == 2 ) {
    $htmlCode .= "<td> </td>";
  }

  $htmlCode .= "</tr>";
  $htmlCode .= "</tbody>";
  $htmlCode .= "</table>";
  $htmlCode .= "</div>";
  $htmlCode .= "</html>";
  				
return $htmlCode;
}

##############################################################################
#              Auflösung Errorcodes bei Login / Logout
##############################################################################
sub SSCam_experrorauth {
  # Übernahmewerte sind $hash, $errorcode
  my ($hash,@errorcode) = @_;
  my $device = $hash->{NAME};
  my $errorcode = shift @errorcode;
  my $error;
  
  unless (exists($SSCam_errauthlist{"$errorcode"})) {$error = "Message of errorcode \"$errorcode\" not found. Please turn to Synology Web API-Guide."; return ($error);}

  # Fehlertext aus Hash-Tabelle %errorauthlist ermitteln
  $error = $SSCam_errauthlist{"$errorcode"};
return ($error);
}

##############################################################################
#  Auflösung Errorcodes SVS API

sub SSCam_experror {
  # Übernahmewerte sind $hash, $errorcode
  my ($hash,@errorcode) = @_;
  my $device = $hash->{NAME};
  my $errorcode = shift @errorcode;
  my $error;
  
  unless (exists($SSCam_errlist{"$errorcode"})) {$error = "Message of errorcode $errorcode not found. Please turn to Synology Web API-Guide."; return ($error);}

  # Fehlertext aus Hash-Tabelle %errorlist ermitteln
  $error = $SSCam_errlist{"$errorcode"};
  return ($error);
}


1;

=pod
=item summary    Camera module to control the Synology Surveillance Station
=item summary_DE Kamera-Modul für die Steuerung der Synology Surveillance Station
=begin html

<a name="SSCam"></a>
<h3>SSCam</h3>
<ul>
  Using this Module you are able to operate cameras which are defined in Synology Surveillance Station (SVS) and execute 
  functions of the SVS. It is based on the SVS API and supports the SVS version 7 and above.<br>
  
  At present the following functions are available: <br><br>
   <ul>
    <ul>
       <li>Start a Recording</li>
       <li>Stop a Recording (using command or automatically after the &lt;RecordTime&gt; period</li>
       <li>Trigger a Snapshot </li>
       <li>Deaktivate a Camera in Synology Surveillance Station</li>
       <li>Activate a Camera in Synology Surveillance Station</li>
       <li>Control of the exposure modes day, night and automatic </li>
       <li>switchover the motion detection by camera, by SVS or deactivate it </li>
       <li>control of motion detection parameters sensitivity, threshold, object size and percentage for release </li>
       <li>Retrieval of Camera Properties (also by Polling) as well as informations about the installed SVS-package</li>
       <li>Move to a predefined Preset-position (at PTZ-cameras) </li>
       <li>Start a predefined Patrol (at PTZ-cameras) </li>
       <li>Positioning of PTZ-cameras to absolute X/Y-coordinates  </li>
       <li>continuous moving of PTZ-camera lense   </li>
       <li>trigger of external events 1-10 (action rules in SVS)   </li>
       <li>start and stop of camera livestreams incl. audio replay, show the last recording and snapshot </li>
       <li>fetch of livestream-Url's with key (login not needed in that case)   </li>
       <li>playback of last recording and playback the last snapshot  </li>
	   <li>switch the Surveillance Station HomeMode on/off and retrieve the HomeModeState </li>
	   <li>show the stored credentials of a device </li>
	   <li>fetch the Surveillance Station Logs, exploit the newest entry as reading  </li>
	   <li>create a gallery of the last 1-10 snapshots (as Popup or in a discrete device)  </li>
	   <li>Start/Stop Object Tracking (only supported PTZ-Cams with this capability)  </li>
       <li>set/delete a Preset (at PTZ-cameras)  </li>
       <li>set a Preset or current position as Home Preset (at PTZ-cameras)  </li>
       <li>provides a panel for camera control (at PTZ-cameras)  </li>
	   <li>create a discrete device for streaming (createStreamDev)  </li>
    </ul>
   </ul>
   <br>
   The recordings and snapshots will be stored in Synology Surveillance Station (SVS) and are managed like the other (normal) recordings / snapshots defined by Surveillance Station rules.<br>
   For example the recordings are stored for a defined time in Surveillance Station and will be deleted after that period.<br><br>
    
   If you like to discuss or help to improve this module please use FHEM-Forum with link: <br>
   <a href="http://forum.fhem.de/index.php/topic,45671.msg374390.html#msg374390">49_SSCam: Fragen, Hinweise, Neuigkeiten und mehr rund um dieses Modul</a>.<br><br>
  
<b> Prerequisites </b> <br><br>
    This module uses the Perl-module JSON. <br>
	On Debian-Linux based systems this module can be installed by: <br><br>
    
    <code>sudo apt-get install libjson-perl</code> <br><br>
	
    SSCam is completely using the nonblocking functions of HttpUtils respectively HttpUtils_NonblockingGet. <br> 
    In DSM respectively in Synology Surveillance Station an User has to be created. The login credentials are needed later when using a set-command to assign the login-data to a device. <br> 
    Further informations could be find among <a href="#SSCam_Credentials">Credentials</a>.  <br><br>
    
    Overview which Perl-modules SSCam is using: <br><br>
    
    JSON            <br>
    Data::Dumper    <br>                  
    MIME::Base64    <br>
    Time::HiRes     <br>
    HttpUtils       (FHEM-module) <br><br>
    

  <a name="SSCamdefine"></a>
  <b>Define</b>
  <ul>
  <br>
    There is a distinction between the definition of a camera-device and the definition of a Surveillance Station (SVS) 
    device, that means the application on the discstation itself. 
    Dependend on the type of defined device the internal MODEL will be set to "&lt;vendor&gt; - &lt;camera type&gt;" 
    or "SVS" and a proper subset of the described set/get-commands are assigned to the device. <br>
	The scope of application of set/get-commands is denoted to every particular command (valid for CAM, SVS, CAM/SVS).
	<br><br>
	
    A camera-device is defined by: <br><br>
	<ul>
      <b><code>define &lt;name&gt; SSCAM &lt;camera name in SVS&gt; &lt;ServerAddr&gt; [Port] </code></b> <br><br>
    </ul>
    
    At first the devices have to be set up and has to be operable in Synology Surveillance Station 7.0 and above. <br><br>
	
	A SVS-device to control functions of the Surveillance Station (SVS) is defined by: <br><br>
	<ul>
	  <b><code>define &lt;name&gt; SSCAM SVS &lt;ServerAddr&gt; [Port] </code></b> <br><br>
    </ul>
	
    In that case the term &lt;camera name in SVS&gt; become replaced by <b>SVS</b> only. <br><br>
    
    The Modul SSCam ist based on functions of Synology Surveillance Station API. <br>
    
    Currently the HTTP-protocol is supported to call Synology Disk Station. <br><br>  

    The parameters are in detail:
   <br>
   <br>    
     
   <table>
    <colgroup> <col width=15%> <col width=85%> </colgroup>
    <tr><td>name:         </td><td>the name of the new device to use in FHEM</td></tr>
    <tr><td>Cameraname:   </td><td>camera name as defined in Synology Surveillance Station if camera-device, "SVS" if SVS-Device. Spaces are not allowed in camera name. </td></tr>
    <tr><td>ServerAddr:   </td><td>IP-address of Synology Surveillance Station Host. <b>Note:</b> avoid using hostnames because of DNS-Calls are not unblocking in FHEM </td></tr>
    <tr><td>Port:         </td><td>optional - the port of synology surveillance station, if not set the default of 5000 (HTTP only) is used</td></tr>
   </table>

    <br><br>

    <b>Example:</b>
     <pre>
      <code>define CamCP SSCAM Carport 192.168.2.20 [5000]</code>
      creates a new camera device CamCP

      <code>define DS1 SSCAM SVS 192.168.2.20 [5000]</code>
      creares a new SVS device DS1	  
    </pre>
    
    When a new Camera is defined, as a start the recordingtime of 15 seconds will be assigned to the device.<br>
    Using the <a href="#SSCamattr">attribute</a> "rectime" you can adapt the recordingtime for every camera individually.<br>
    The value of "0" for rectime will lead to an endless recording which has to be stopped by a "set &lt;name&gt; off" command.<br>
    Due to a Log-Entry with a hint to that circumstance will be written. <br><br>
    
    If the <a href="#SSCamattr">attribute</a> "rectime" would be deleted again, the default-value for recording-time (15s) become active.<br><br>

    With <a href="#SSCamset">command</a> <b>"set &lt;name&gt; on [rectime]"</b> a temporary recordingtime is determinded which would overwrite the dafault-value of recordingtime <br>
    and the attribute "rectime" (if it is set) uniquely. <br><br>

    In that case the command <b>"set &lt;name&gt; on 0"</b> leads also to an endless recording as well.<br><br>
    
    If you have specified a pre-recording time in SVS it will be considered too. <br><br>
    
    If the module recognizes the defined camera as a PTZ-device (Reading "DeviceType = PTZ"), then a control panel is  
    created automatically in the detal view. This panel requires SVS >= 7.1. The properties and the behave of the  
    panel can be affected by <a href="#SSCamattr">attributes</a> "ptzPanel_.*". <br>
    Please see also <a href="#SSCamset">command</a> <b>"set &lt;name&gt; createPTZcontrol"</b> in this context.
    <br><br><br>
    </ul>
    
    <a name="SSCam_Credentials"></a>
    <b>Credentials </b><br><br>
    
    <ul>
    After a camera-device is defined, firstly it is needed to save the credentials. This will be done with command:
   
    <pre> 
     set &lt;name&gt; credentials &lt;username&gt; &lt;password&gt;
    </pre>
    
    The password length has a maximum of 20 characters. <br> 
	The operator can, dependend on what functions are planned to execute, create an user in DSM respectively in Synology Surveillance Station as well. <br>
    If the user is member of admin-group, he has access to all module functions. Without this membership the user can only execute functions with lower need of rights. <br>
    The required minimum rights to execute functions are listed in a table further down. <br>
    
    Alternatively to DSM-user a user created in SVS can be used. Also in that case a user of type "manager" has the right to execute all functions, <br>
    whereat the access to particular cameras can be restricted by the privilege profile (please see help function in SVS for details).  <br>
    As best practice it is proposed to create an user in DSM as well as in SVS too:  <br><br>
    
    <ul>
    <li>DSM-User as member of admin group: unrestricted test of all module functions -&gt; session: DSM  </li>
    <li>SVS-User as Manager or observer: adjusted privilege profile -&gt; session: SurveillanceStation  </li>
    </ul>
    <br>
    
    Using the <a href="#SSCamattr">Attribute</a> "session" can be selected, if the session should be established to DSM or the SVS instead. <br>
    If the session will be established to DSM, SVS Web-API methods are available as well as further API methods of other API's what possibly needed for processing. <br><br>
    
    After device definition the default is "login to DSM", that means credentials with admin rights can be used to test all camera-functions firstly. <br>
    After this the credentials can be switched to a SVS-session with a restricted privilege profile as needed on dependency what module functions are want to be executed. <br><br>
    
    The following list shows the minimum rights what the particular module function needs. <br><br>
    <ul>
      <table>
      <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td><li>set ... on                 </td><td> session: ServeillanceStation - observer with enhanced privilege "manual recording" </li></td></tr>
      <tr><td><li>set ... off                </td><td> session: ServeillanceStation - observer with enhanced privilege "manual recording" </li></td></tr>
      <tr><td><li>set ... snap               </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>set ... delPreset          </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>set ... disable            </td><td> session: ServeillanceStation - manager       </li></td></tr>
      <tr><td><li>set ... enable             </td><td> session: ServeillanceStation - manager       </li></td></tr>
      <tr><td><li>set ... expmode            </td><td> session: ServeillanceStation - manager       </li></td></tr>
      <tr><td><li>set ... extevent           </td><td> session: DSM - user as member of admin-group   </li></td></tr>
      <tr><td><li>set ... goPreset           </td><td> session: ServeillanceStation - observer with privilege objective control of camera  </li></td></tr>
      <tr><td><li>set ... homeMode           </td><td> ssession: ServeillanceStation - observer with privilege Home Mode switch  </li></td></tr>
	  <tr><td><li>set ... motdetsc           </td><td> session: ServeillanceStation - manager       </li></td></tr>
	  <tr><td><li>set ... runPatrol          </td><td> session: ServeillanceStation - observer with privilege objective control of camera  </li></td></tr>
      <tr><td><li>set ... goAbsPTZ           </td><td> session: ServeillanceStation - observer with privilege objective control of camera  </li></td></tr>
      <tr><td><li>set ... move               </td><td> session: ServeillanceStation - observer with privilege objective control of camera  </li></td></tr>
      <tr><td><li>set ... runView            </td><td> session: ServeillanceStation - observer with privilege liveview of camera </li></td></tr>
	  <tr><td><li>set ... setHome            </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>set ... setPreset          </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>set ... snap               </td><td> session: ServeillanceStation - observer    </li></td></tr>      
      <tr><td><li>set ... snapGallery        </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>set ... stopView           </td><td> -                                          </li></td></tr>
      <tr><td><li>set ... credentials        </td><td> -                                          </li></td></tr>
      <tr><td><li>get ... caminfo[all]       </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>get ... eventlist          </td><td> session: ServeillanceStation - observer    </li></td></tr>
	  <tr><td><li>get ... listLog            </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>get ... listPresets        </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>get ... scanVirgin         </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>get ... svsinfo            </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>get ... snapfileinfo       </td><td> session: ServeillanceStation - observer    </li></td></tr>
	  <tr><td><li>get ... snapinfo           </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>get ... stmUrlPath         </td><td> session: ServeillanceStation - observer    </li></td></tr>      
      </table>
    </ul>
      <br><br>
    
    <a name="SSCam_HTTPTimeout"></a>
    <b>HTTP-Timeout Settings</b><br><br>
    
    All functions of SSCam use HTTP-calls to SVS Web API. <br>
    The default-value of HTTP-Timeout amounts 4 seconds. You can set the <a href="#SSCamattr">attribute</a> "httptimeout" > 0 to adjust the value as needed in your technical environment. <br>
    
  </ul>
  <br><br><br>
  
  
<a name="SSCamset"></a>
<b>Set </b>
  <ul>  
  <br>
  The specified set-commands are available for CAM/SVS-devices or only valid for CAM-devices or rather for SVS-Devices. 
  They can be selected in the drop-down-menu of the particular device. <br><br>
  
  <ul>
  <a name="SSCamcreateStreamDev"></a>
  <li><b> set &lt;name&gt; createStreamDev [mjpeg | switched] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  A separate streaming device (type SSCamSTRM) will be created. This device can be used as a discrete device in a dashboard for example.
  The current room of the parent camera device is assigned to the new device if it is set there. 
  You can control the design with HTML tags in <a href="#SSCamattr">attribute</a> "htmlattr" of the camera device or by the 
  specific attributes of the SSCamSTRM-device itself. <br>
  In "switched"-Devices are buttons provided for mode control. <br>
  If HLS (HTTP Live Streaming) is used in Streaming-Device of type "switched", then the camera has to be set to video format
  H.264 in the Synology Surveillance Station. Therefore the selection button for "HLS" is only provided in Streaming-Device 
  if the Reading "CamStreamFormat" contains HLS". <br>
  HTTP Live Streaming is currently onla available on Mac Safari or modern mobile iOS/Android devices.
  <br><br>
  
    <ul>
    <table>
    <colgroup> <col width=10%> <col width=90%> </colgroup>
      <tr><td>mjpeg     </td><td>- the streaming device permanent playback a MJPEG video stream (Streamkey method) </td></tr>
      <tr><td>switched  </td><td>- playback of different streaming types. Buttons for mode control are provided. </td></tr>
    </table>
    </ul>
    <br><br>
  </ul>
  
  
  <ul>
  <li><b> set &lt;name&gt; createPTZcontrol </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for PTZ-CAM)</li> <br>
  
  A separate PTZ-control panel will be created (type SSCamSTRM). The current room of the parent camera device is 
  assigned if it is set there.  
  With the "ptzPanel_.*"-<a href="#SSCamattr">attributes</a> or respectively the specific attributes of the SSCamSTRM-device
  the properties of the control panel can be affected. <br> 
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; createSnapGallery </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  A snapshot gallery will be created as a separate device (type SSCamSTRM). The device will be provided in 
  room "SnapGallery".
  With the "snapGallery..."-<a href="#SSCamattr">attributes</a> respectively the specific attributes of the SSCamSTRM-device
  you are able to manipulate the properties of the new snapshot gallery device. <br> 
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; credentials &lt;username&gt; &lt;password&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM/SVS)</li> <br>
  
  set username / password combination for access the Synology Surveillance Station. 
  See <a href="#SSCam_Credentials">Credentials</a><br> for further informations.
  
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; delPreset &lt;PresetName&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for PTZ-CAM)</li> <br>
  
  Deletes a preset "&lt;PresetName&gt;". In FHEMWEB a drop-down list with current available presets is provieded.

  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; [enable|disable] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  For <b>deactivating / activating</b> a list of cameras or all cameras by Regex-expression, subsequent two 
  examples using "at":
  <pre>
     define a13 at 21:46 set CamCP1,CamFL,CamHE1,CamTER disable (enable)
     define a14 at 21:46 set Cam.* disable (enable)
  </pre>
  
  A bit more convenient is it to use a dummy-device for enable/disable all available cameras in Surveillance Station.<br>
  At first the Dummy will be created.
  <pre>
     define allcams dummy
     attr allcams eventMap on:enable off:disable
     attr allcams room Cams
     attr allcams webCmd enable:disable
  </pre>
  
  With combination of two created notifies, respectively one for "enable" and one for "diasble", you are able to switch all cameras into "enable" or "disable" state at the same time if you set the dummy to "enable" or "disable". 
  <pre>
     define all_cams_disable notify allcams:.*off set CamCP1,CamFL,CamHE1,CamTER disable
     attr all_cams_disable room Cams

     define all_cams_enable notify allcams:on set CamCP1,CamFL,CamHE1,CamTER enable
     attr all_cams_enable room Cams
  </pre>
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; expmode [day|night|auto] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  With this command you are able to control the exposure mode and can set it to day, night or automatic mode. 
  Thereby, for example, the behavior of camera LED's will be suitable controlled. 
  The successful switch will be reported by the reading CamExposureMode (command "get ... caminfoall"). <br><br>
  
  <b> Note: </b><br>
  The successfully execution of this function depends on if SVS supports that functionality of the connected camera.
  Is the field for the Day/Night-mode shown greyed in SVS -&gt; IP-camera -&gt; optimization -&gt; exposure mode, this function will be probably unsupported.  
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; extevent [ 1-10 ] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for SVS)</li> <br>
  
  This command triggers an external event (1-10) in SVS. 
  The actions which will are used have to be defined in the actionrule editor of SVS at first. There are the events 1-10 possible.
  In the message application of SVS you may select Email, SMS or Mobil (DS-Cam) messages to release if an external event has been triggerd.
  Further informations can be found in the online help of the actionrule editor.
  The used user needs to be a member of the admin-group and DSM-session is needed too.
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; goAbsPTZ [ X Y | up | down | left | right ] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  This command can be used to move a PTZ-camera to an arbitrary absolute X/Y-coordinate, or to absolute position using up/down/left/right. 
  The option is only available for cameras which are having the Reading "CapPTZAbs=true". The property of a camera can be requested with "get &lt;name&gt; caminfoall" .
  <br><br>

  Example for a control to absolute X/Y-coordinates: <br>

  <pre>
    set &lt;name&gt; goAbsPTZ 120 450
  </pre>
 
  In this example the camera lense moves to position X=120 und Y=450. <br>
  The valuation is:

  <pre>
    X = 0 - 640      (0 - 319 moves lense left, 321 - 640 moves lense right, 320 don't move lense)
    Y = 0 - 480      (0 - 239 moves lense down, 241 - 480 moves lense up, 240 don't move lense) 
  </pre>

  The lense can be moved in smallest steps to very large steps into the desired direction.
  If necessary the procedure has to be repeated to bring the lense into the desired position. <br><br>

  If the motion should be done with the largest possible increment the following command can be used for simplification:

  <pre>
   set &lt;name&gt; goAbsPTZ up [down|left|right]
  </pre>

  In this case the lense will be moved with largest possible increment into the given absolute position.
  Also in this case the procedure has to be repeated to bring the lense into the desired position if necessary. 
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; goPreset &lt;Preset&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  Using this command you can move PTZ-cameras to a predefined position. <br>
  The Preset-positions have to be defined first of all in the Synology Surveillance Station. This usually happens in the PTZ-control of IP-camera setup in SVS.
  The Presets will be read ito FHEM with command "get &lt;name&gt; caminfoall" (happens automatically when FHEM restarts). The import process can be repeated regular by camera polling.
  A long polling interval is recommendable in this case because of the Presets are only will be changed if the user change it in the IP-camera setup itself. 
  <br><br>
  
  Here it is an example of a PTZ-control depended on IR-motiondetector event:
  
  <pre>
    define CamFL.Preset.Wandschrank notify MelderTER:on.* set CamFL goPreset Wandschrank, ;; define CamFL.Preset.record at +00:00:10 set CamFL on 5 ;;;; define s3 at +*{3}00:00:05 set CamFL snap ;; define CamFL.Preset.back at +00:00:30 set CamFL goPreset Home
  </pre>
  
  Operating Mode: <br>
  
  The IR-motiondetector registers a motion. Hereupon the camera "CamFL" moves to Preset-posion "Wandschrank". A recording with the length of 5 seconds starts 10 seconds later. 
  Because of the prerecording time of the camera is set to 10 seconds (cf. Reading "CamPreRecTime"), the effectice recording starts when the camera move begins. <br>
  When the recording starts 3 snapshots with an interval of 5 seconds will be taken as well. <br>
  After a time of 30 seconds in position "Wandschrank" the camera moves back to postion "Home". <br><br>
  
  An extract of the log illustrates the process:
  
  <pre>  
   2016.02.04 15:02:14 2: CamFL - Camera Flur_Vorderhaus has moved to position "Wandschrank"
   2016.02.04 15:02:24 2: CamFL - Camera Flur_Vorderhaus Recording with Recordtime 5s started
   2016.02.04 15:02:29 2: CamFL - Snapshot of Camera Flur_Vorderhaus has been done successfully
   2016.02.04 15:02:30 2: CamFL - Camera Flur_Vorderhaus Recording stopped
   2016.02.04 15:02:34 2: CamFL - Snapshot of Camera Flur_Vorderhaus has been done successfully
   2016.02.04 15:02:39 2: CamFL - Snapshot of Camera Flur_Vorderhaus has been done successfully
   2016.02.04 15:02:44 2: CamFL - Camera Flur_Vorderhaus has moved to position "Home"
  </pre>
  </ul>
  <br><br>

  <ul>
  <li><b> set &lt;name&gt; homeMode [on|off] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for SVS)</li> <br>
  
  Switch the HomeMode of the Surveillance Station on or off. 
  Further informations about HomeMode you can find in the <a href="https://www.synology.com/en-global/knowledgebase/Surveillance/help/SurveillanceStation/home_mode">Synology Onlinehelp</a>.
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; motdetsc [camera|SVS|disable] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  The command "motdetsc" (stands for "motion detection source") switchover the motion detection to the desired mode.
  If motion detection will be done by camera / SVS without any parameters, the original camera motion detection settings are kept.
  The successful execution of that opreration one can retrace by the state in SVS -&gt; IP-camera -&gt; event detection -&gt; motion. <br><br>
  
  For the motion detection further parameter can be specified. The available options for motion detection by SVS are "sensitivity" and "threshold". <br><br>
  
  <ul>
  <table>
  <colgroup> <col width=50%> <col width=50%> </colgroup>
      <tr><td>set &lt;name&gt; motdetsc SVS [sensitivity] [threshold]  </td><td># command pattern  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc SVS 91 30                      </td><td># set the sensitivity to 91 and threshold to 30  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc SVS 0 40                       </td><td># keep the old value of sensitivity, set threshold to 40  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc SVS 15                         </td><td># set the sensitivity to 15, threshold keep unchanged  </td></tr>
  </table>
  </ul>
  <br><br>
  
  If the motion detection is used by camera, there are the options "sensitivity", "object size", "percentage for release" available. <br><br>
  
  <ul>
  <table>
  <colgroup> <col width=50%> <col width=50%> </colgroup>
      <tr><td>set &lt;name&gt; motdetsc camera [sensitivity] [threshold] [percentage] </td><td># command pattern  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc camera 89 0 20                                </td><td># set the sensitivity to 89, percentage to 20  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc camera 0 40 10                                </td><td># keep old value for sensitivity, set threshold to 40, percentage to 10  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc camera 30                                     </td><td># set the sensitivity to 30, other values keep unchanged  </td></tr>
      </table>
  </ul>
  <br><br>
  
  Please consider always the sequence of parameters. Unwanted options have to be set to "0" if further options which have to be changed are follow (see example above).
  The numerical values are between 1 - 99 (except special case "0"). <br><br>
  
  The each available options are dependend of camera type respectively the supported functions by SVS. Only the options can be used they are available in 
  SVS -&gt; edit camera -&gt; motion detection. Further informations please read in SVS online help. <br><br>
  
  With the command "get &lt;name&gt; caminfoall" the <a href="#SSCamreadings">Reading</a> "CamMotDetSc" also will be updated which documents the current setup of motion detection. 
  Only the parameters and parameter values supported by SVS at present will be shown. The camera itself may offer further  options to adjust. <br><br>
  
  Example:
  <pre>
   CamMotDetSc    SVS, sensitivity: 76, threshold: 55
  </pre>
  </ul>
  <br><br>
    
  <ul>
  <li><b> set &lt;name&gt; move [ right | up | down | left | dir_X ] [Sekunden] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM up to SVS version 7.1)</li>
      <b> set &lt;name&gt; move [ right | upright | up | upleft | left | downleft | down | downright ] [Sekunden] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM and SVS Version 7.2 and above) <br><br>
  
  With this command a continuous move of a PTZ-camera will be started. In addition to the four basic directions up/down/left/right is it possible to use angular dimensions 
  "dir_X". The grain size of graduation depends on properties of the camera and can be identified by the Reading "CapPTZDirections". <br><br>

  The radian measure of 360 degrees will be devided by the value of "CapPTZDirections" and describes the move drections starting with "0=right" counterclockwise. 
  That means, if a camera Reading is "CapPTZDirections = 8" it starts with dir_0 = right, dir_2 = top, dir_4 = left, dir_6 = bottom and respectively dir_1, dir_3, dir_5 and dir_7 
  the appropriate directions between. The possible moving directions of cameras with "CapPTZDirections = 32" are correspondingly divided into smaller sections. <br><br>

  In opposite to the "set &lt;name&gt; goAbsPTZ"-command starts "set &lt;name&gt; move" a continuous move until a stop-command will be received.
  The stop-command will be generated after the optional assignable time of [seconds]. If that retention period wouldn't be set by the command, a time of 1 second will be set implicit. <br><br>
  
  Examples: <br>
  
  <pre>
    set &lt;name&gt; move up 0.5      : moves PTZ 0,5 Sek. (plus processing time) to the top
    set &lt;name&gt; move dir_1 1.5   : moves PTZ 1,5 Sek. (plus processing time) to top-right 
    set &lt;name&gt; move dir_20 0.7  : moves PTZ 1,5 Sek. (plus processing time) to left-bottom ("CapPTZDirections = 32)"
  </pre>
  </ul>
  <br><br>
  
  <ul>
  <li><b>set &lt;name&gt; [on [&lt;rectime&gt;] | off] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
   
  The command "set &lt;name&gt; on" starts a recording. The default recording time takes 15 seconds. It can be changed by 
  the <a href="#SSCamattr">attribute</a> "rectime" individualy. 
  With the <a href="#SSCamattr">attribute</a> (respectively the default value) provided recording time can be overwritten 
  once by "set &lt;name&gt; on &lt;rectime&gt;".
  The recording will be stopped after processing time "rectime"automatically.<br>

  A special case is start recording by "set &lt;name&gt; on 0" respectively the attribute value "rectime = 0". In that case 
  a endless-recording will be started. One have to stop this recording by command "set &lt;name&gt; off" explicitely.<br>

  The recording behavior can be impacted with <a href="#SSCamattr">attribute</a> "recextend" furthermore as explained as follows.<br><br>

  <b>Attribute "recextend = 0" or not set (default):</b><br><br>
  <ul>
  <li> if, for example, a recording with rectimeme=22 is started, no other startcommand (for a recording) will be accepted until this started recording is finished.
  A hint will be logged in case of verboselevel = 3. </li>
  </ul>
  <br>

  <b>Attribute "recextend = 1" is set:</b><br><br>
  <ul>
  <li> a before started recording will be extend by the recording time "rectime" if a new start command is received. That means, the timer for the automatic stop-command will be
  renewed to "rectime" given bei the command, attribute or default value. This procedure will be repeated every time a new start command for recording is received. 
  Therefore a running recording will be extended until no start command will be get. </li>

  <li> a before started endless-recording will be stopped after recordingtime 2rectime" if a new "set <name> on"-command is received (new set of timer). If it is unwanted make sure you 
  don't set the <a href="#SSCamattr">attribute</a> "recextend" in case of endless-recordings. </li>
  </ul>
  <br>
  
  Examples for simple <b>Start/Stop a Recording</b>: <br><br>

  <table>
  <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td>set &lt;name&gt; on [rectime]  </td><td>starts a recording of camera &lt;name&gt;, stops automatically after [rectime] (default 15s or defined by <a href="#SSCamattr">attribute</a>) </td></tr>
      <tr><td>set &lt;name&gt; off           </td><td>stops the recording of camera &lt;name&gt;</td></tr>
  </table>
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; optimizeParams [mirror:&lt;value&gt;] [flip:&lt;value&gt;] [rotate:&lt;value&gt;] [ntp:&lt;value&gt;]</b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Set one or several properties of the camera. The video can be mirrored (mirror), turned upside down (flip) or 
  rotated (rotate). Specified properties must be supported by the camera type. With "ntp" you can set a time server the camera 
  use for time synchronization. <br><br>
  
  &lt;value&gt; can be for: <br>
    <ul>
    <li> <b>mirror, flip, rotate: </b> true | false  </li>
	<li> <b>ntp: </b> the name or the IP-address of time server </li> 
	</ul>
	<br><br>
	
  <b>Examples:</b> <br>
  <code> set &lt;name&gt; optimizeParams mirror:true flip:true ntp:time.windows.com </code><br>
  # The video will be mirrored, turned upside down and the time server is set to "time.windows.com".<br>
  <code> set &lt;name&gt; optimizeParams ntp:Surveillance%20Station </code><br>
  # The Surveillance Station is set as time server. (NTP-service has to be activated in DSM) <br>
  <code> set &lt;name&gt; optimizeParams mirror:true flip:false rotate:true </code><br>
  # The video will be mirrored and rotated round 90 degrees. <br>
    
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; runPatrol &lt;Patrolname&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  This commans starts a predefined patrol (tour) of a PTZ-camera. <br>
  At first the patrol has to be predefined in the Synology Surveillance Station. It can be done in the PTZ-control of IP-Kamera Setup -&gt; PTZ-control -&gt; patrol.
  The patrol tours will be read with command "get &lt;name&gt; caminfoall" which is be executed automatically when FHEM restarts.
  The import process can be repeated regular by camera polling. A long polling interval is recommendable in this case because of the patrols are only will be changed 
  if the user change it in the IP-camera setup itself. 
  Further informations for creating patrols you can get in the online-help of Surveillance Station.
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; runView [live_fw | live_link | live_open [&lt;room&gt;] | lastrec_fw | lastrec_fw_MJPEG | lastrec_fw_MPEG4/H.264 | lastrec_open [&lt;room&gt;] | lastsnap_fw]  </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  <ul>
  <table>
  <colgroup> <col width=25%> <col width=75%> </colgroup>
      <tr><td>live_fw                     </td><td>- MJPEG-Livestream. Audio playback is provided if possible. </td></tr>
      <tr><td>live_fw_hls                 </td><td>- HLS-Livestream (currently only Mac Safari Browser and mobile iOS/Android-Devices) </td></tr>
      <tr><td>live_link                   </td><td>- Link of a MJPEG-Livestream </td></tr>
      <tr><td>live_open [&lt;room&gt;]    </td><td>- opens MJPEG-Livestream in separate Browser window </td></tr>
      <tr><td>lastrec_fw                  </td><td>- playback last recording as iFrame object </td></tr>
      <tr><td>lastrec_fw_MJPEG            </td><td>- usable if last recording has format MJPEG </td></tr>
      <tr><td>lastrec_fw_MPEG4/H.264      </td><td>- usable if last recording has format MPEG4/H.264 </td></tr>
      <tr><td>lastrec_open [&lt;room&gt;] </td><td>- playback last recording in a separate Browser window </td></tr>
      <tr><td>lastsnap_fw                 </td><td>- playback last snapshot </td></tr>
  </table>
  </ul>
  <br><br>
  
  With <b>"live_fw, live_link"</b> a MJPEG-Livestream will be started, either as an embedded image 
  or as a generated link. <br>
  The option <b>"live_open"</b> starts a new browser window with a MJPEG-Livestream. If the optional "&lt;room&gt;" is set, the 
  window will only be started if the specified room is currently opened in a FHEMWEB-session. <br>
  If a HLS-Stream by <b>"live_fw_hls"</b> is requested, the camera has to be setup to video format H.264 (not MJPEG) in the 
  Synology Surveillance Station. Therefore this possibility is only present if the Reading "CamStreamFormat" is set to "HLS".
  <br><br> 
  
  Access to the last recording of a camera can be done using <b>"lastrec_fw.*"</b> respectively <b>"lastrec_open"</b>.
  By <b>"lastrec_fw"</b> the recording will be opened in an iFrame. There are some control elements provided if available. <br>
  The <b>"lastrec_open"</b> command can be extended optionally by a room. In this case the new window opens only, if the 
  room is the same as a FHEMWEB-session has currently opened. <br>  
  The command <b>"set &lt;name&gt; runView lastsnap_fw"</b> shows the last snapshot of the camera embedded. <br>
  The Streaming-Device properties can be affected by HTML-tags in <a href="#SSCamattr">attribute</a> "htmlattr". 
  <br><br>
  
  <b>Examples:</b><br>
  <pre>
    attr &lt;name&gt; htmlattr width="500" height="375"
    attr &lt;name&gt; htmlattr width="700",height="525",top="200",left="300"
  </pre>
  
  The command <b>"set &lt;name&gt; runView live_open"</b> starts the stream immediately in a new browser window. 
  A browser window will be initiated to open for every FHEMWEB-session which is active. If you want to change this behavior, 
  you can use command <b>"set &lt;name&gt; runView live_open &lt;room&gt;"</b>. In this case the new window opens only, if the 
  room is the same as a FHEMWEB-session has currently opened. <br>  
  The settings of <a href="#SSCamattr">attribute</a> "livestreamprefix" overwrite the data for protocol, servername and 
  port in <a href="#SSCamreadings">reading</a> "LiveStreamUrl".
  By "livestreamprefix" the LivestreamURL (is shown if <a href="#SSCamattr">attribute</a> "showStmInfoFull" is set) can 
  be modified and used for distribution and external access to the Livestream. <br><br>
  
  <b>Example:</b><br>
  <pre>
    attr &lt;name&gt; livestreamprefix https://&lt;Servername&gt;:&lt;Port&gt;
  </pre>
  
  The livestream can be stopped again by command <b>"set &lt;name&gt; stopView"</b>.
  The "runView" function also switches Streaming-Devices of type "switched" into the appropriate mode. <br><br>
  
  <b>Note for HLS (HTTP Live Streaming):</b> <br>
  The video starts with a technology caused delay. Every stream will be segemented into some little video files 
  (with a lenth of approximately 10 seconds) and is than delivered to the client. 
  The video format of the camera has to be set to H.264 in the Synology Surveillance Station and not every camera type is
  a proper device for HLS-Streaming.
  At the time only the Mac Safari Browser and modern mobile iOS/Android-Devices are able to playback HLS-Streams. 
  
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; setHome &lt;PresetName&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for PTZ-CAM)</li> <br>
  
  Set the Home-preset to a predefined preset name "&lt;PresetName&gt;" or the current position of the camera.

  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; setPreset &lt;PresetNumber&gt; [&lt;PresetName&gt;] [&lt;Speed&gt;] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for PTZ-CAM)</li> <br>
  
  Sets a Preset with name "&lt;PresetName&gt;" to the current postion of the camera. The speed can be defined 
  optionally (&lt;Speed&gt;). If no PresetName is specified, the PresetNummer is used as name.
  For this reason &lt;PresetName&gt; is defined as optional, but should usually be set.

  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; snap </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  A snapshot can be triggered with:
  <pre> 
     set &lt;name&gt; snap 
  </pre>

  Subsequent some Examples for <b>taking snapshots</b>: <br><br>
  
  If a serial of snapshots should be released, it can be done using the following notify command.
  For the example a serial of snapshots are to be triggerd if the recording of a camera starts. <br>
  When the recording of camera "CamHE1" starts (Attribut event-on-change-reading -> "Record" has to be set), then 3 snapshots at intervals of 2 seconds are triggered.

  <pre>
     define he1_snap_3 notify CamHE1:Record.*on define h3 at +*{3}00:00:02 set CamHE1 snap 
  </pre>

  Release of 2 Snapshots of camera "CamHE1" at intervals of 6 seconds after the motion sensor "MelderHE1" has sent an event, <br>
  can be done e.g. with following notify-command:

  <pre>
     define he1_snap_2 notify MelderHE1:on.* define h2 at +*{2}00:00:06 set CamHE1 snap 
  </pre>

  The ID and the filename of the last snapshot will be displayed as value of variable "LastSnapId" respectively "LastSnapFilename" in the device-Readings. <br><br>
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; snapGallery [1-10] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  The command is only available if the attribute "snapGalleryBoost=1" is set. <br>
  It creates an output of the last [x] snapshots as well as "get ... snapGallery".  But differing from "get" with
  <a href="#SSCamattr">attribute</a> "snapGalleryBoost=1" no popup will be created. The snapshot gallery will be depicted as
  an browserpage instead. All further functions and attributes are appropriate the <a href="#SSCamget">"get &lt;name&gt; snapGallery"</a>
  command. <br>
  If you want create a snapgallery output by triggering, e.g. with an "at" or "notify", you should use the 
  <a href="#SSCamget">"get &lt;name&gt; snapGallery"</a> command instead of "set".
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; startTracking </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM with tracking capability)</li> <br>
  
  Starts object tracking of camera.
  The command is only available if surveillance station has recognised the object tracking capability of camera
  (Reading "CapPTZObjTracking").
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; stopTracking </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM with tracking capability)</li> <br>
  
  Stops object tracking of camera.
  The command is only available if surveillance station has recognised the object tracking capability of camera
  (Reading "CapPTZObjTracking").
  </ul>
  <br><br>
  
 </ul>
<br>


<a name="SSCamget"></a>
<b>Get</b>
 <ul>
  <br>
  With SSCam the properties of SVS and defined Cameras could be retrieved. <br>
  The specified get-commands are available for CAM/SVS-devices or only valid for CAM-devices or rather for SVS-Devices. 
  They can be selected in the drop-down-menu of the particular device. <br><br>

  <ul>
  <li><b> get &lt;name&gt; caminfoall </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM/SVS)</li> 
      <b> get &lt;name&gt; caminfo </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM) <br><br>
	  
  Dependend of the type of camera (e.g. Fix- or PTZ-Camera) the available properties are retrieved and provided as Readings.<br>
  For example the Reading "Availability" will be set to "disconnected" if the camera would be disconnected from Synology 
  Surveillance Station and can't be used for further processing like creating events. <br>
  "getcaminfo" retrieves a subset of "getcaminfoall".
  </ul>
  <br><br>  
  
  <ul>
  <li><b> get &lt;name&gt; eventlist </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  The <a href="#SSCamreadings">Reading</a> "CamEventNum" and "CamLastRecord" will be refreshed which containes the total number 
  of in SVS registered camera events and the path/name of the last recording. 
  This command will be implicit executed when "get &lt;name&gt; caminfoall" is running. <br>
  The <a href="#SSCamattr">attribute</a> "videofolderMap" replaces the content of reading "VideoFolder". You can use it for 
  example if you have mounted the videofolder of SVS under another name or path and want to access by your local pc. 
  </ul>
  <br><br>

  <ul>
  <li><b> get &lt;name&gt; homeModeState </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for SVS)</li> <br>
  
  HomeMode-state of the Surveillance Station will be retrieved.  
  </ul>
  <br><br>

  <ul>
  <li><b> get &lt;name&gt; listLog [severity:&lt;Loglevel&gt;] [limit:&lt;Number of lines&gt;] [match:&lt;Searchstring&gt;] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for SVS)</li> <br>
  
  Fetches the Surveillance Station Log from Synology server. Without any further options the whole log will be retrieved. <br>
  You can specify all or any of the following options: <br><br>
  
  <ul>
  <li> &lt;Loglevel&gt; - Information, Warning or Error. Only datasets having this severity are retrieved (default: all) </li>
  <li> &lt;Number of lines&gt; - the specified number of lines  (newest) of the log are retrieved (default: all) </li>
  <li> &lt;Searchstring&gt; - only log entries containing the searchstring are retrieved (Note: no Regex possible, the searchstring will be given into the call to SVS) </li>
  </ul>
  <br>
  
  <b>Examples</b> <br>
  <ul>
  <code>get &lt;name&gt; listLog severity:Error limit:5 </code> <br>
  Reports the last 5 Log entries with severity "Error" <br>
  <code>get &lt;name&gt; listLog severity:Information match:Carport </code> <br>
  Reports all Log entries with severity "Information" and containing the string "Carport" <br>
  <code>get &lt;name&gt; listLog severity:Warning </code> <br>
  Reports all Log entries with severity "Warning" <br><br>
  </ul>
  
  
  If the polling of SVS is activated by setting the <a href="#SSCamattr">attribute</a> "pollcaminfoall", the <a href="#SSCamreadings">reading</a> 
  "LastLogEntry" will be created. <br>
  In the protocol-setup of the SVS you can adjust what data you want to log. For further informations please have a look at
  <a href="https://www.synology.com/en-uk/knowledgebase/Surveillance/help/SurveillanceStation/log_advanced">Synology Online-Help</a>.
  </ul>
  <br><br>  

  <ul>
  <li><b> get &lt;name&gt; listPresets </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for PTZ-CAM)</li> <br>
  
  Get a popup with a lists of presets saved for the camera.
  </ul>
  <br><br>   
  
  <ul>
  <li><b> get &lt;name&gt; scanVirgin </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM/SVS)</li> <br>
  
  This command is similar to get caminfoall, informations relating to SVS and the camera will be retrieved. 
  In difference to caminfoall in either case a new session ID will be generated (do a new login), the camera ID will be
  new identified and all necessary API-parameters will be new investigated.  
  </ul>
  <br><br> 
  
  <ul>
  <li><b> get &lt;name&gt; snapGallery [1-10] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  A popup with the last [x] snapshots will be created. If the <a href="#SSCamattr">attribute</a> "snapGalleryBoost" is set, 
  the last snapshots (default 3) are requested by polling and they will be stored in the FHEM-servers main memory. 
  This method is helpful to speed up the output especially in case of full size images, but it can be possible 
  that NOT the newest snapshots are be shown if they have not be initialized by the SSCAm-module itself. <br>
  The function can also be triggered, e.g. by an "at" or "notify". In that case the snapshotgallery will be displayed on all 
  connected FHEMWEB instances as a popup. <br><br>
  
  To control this function behavior there are further <a href="#SSCamattr">attributes</a>: <br><br>
  
  <ul>
     <li>snapGalleryBoost   </li> 
	 <li>snapGalleryColumns   </li> 
	 <li>snapGalleryHtmlAttr   </li> 
	 <li>snapGalleryNumber   </li> 
	 <li>snapGallerySize   </li> 
  </ul> <br>
  available.
  </ul> <br>
  
        <ul>
		<b>Note:</b><br>
        Depended from quantity and resolution (quality) of the snapshot images adequate CPU and/or main memory
		ressources are needed.
        </ul>
		<br><br>
  
  <ul>
  <li><b> get &lt;name&gt; snapfileinfo </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  The filename of the last snapshot will be retrieved. This command will be executed with <b>"get &lt;name&gt; snap"</b> 
  automatically.
  </ul>
  <br><br>  
  
  <ul>
  <li><b> get &lt;name&gt; snapinfo </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  Informations about snapshots will be retrieved. Heplful if snapshots are not triggerd by SSCam, but by motion detection of the camera or surveillance
  station instead.
  </ul>
  <br><br> 
  
  <ul>
  <li><b> get &lt;name&gt; stmUrlPath </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  This command is to fetch the streamkey information and streamurl using that streamkey. The reading "StmKey" will be filled when this command will be executed and can be used 
  to send it and run by your own application like a browser (see example).
  If the <a href="#SSCamattr">attribute</a> "showStmInfoFull" is set, additional stream readings like "StmKeyUnicst", "StmKeymjpegHttp" will be shown and can be used to run the 
  appropriate livestream without session id. Is the attribute "livestreamprefix" (usage: "http(s)://&lt;hostname&gt;&lt;port&gt;) used, the servername / port will be replaced if necessary.
  The strUrlPath function will be included automatically if polling is used.
  <br><br>
  
  Example to create an http-call to a livestream using StmKey: <br>
  
  <pre>
http(s)://&lt;hostname&gt;&lt;port&gt;/webapi/entry.cgi?api=SYNO.SurveillanceStation.VideoStreaming&version=1&method=Stream&format=mjpeg&cameraId=5&StmKey="31fd87279976d89bb98409728cced890"
  </pre>
  
  cameraId (Internal CAMID) and StmKey has to be replaced by valid values. <br><br>
  
  <b>Note:</b> <br>
  
  If you use the stream-call from external and replace hostname / port with valid values and open your router ip ports, please 
  make shure that no unauthorized person could get this sensible data !  
  </ul>
  <br><br>
  
  <ul>
  <li><b> get &lt;name&gt; storedCredentials </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM/SVS)</li> <br>
  
  Shows the stored login credentials in a popup as plain text.
  </ul>
  <br><br>  
  
  <ul>
  <li><b> get &lt;name&gt; svsinfo </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM/SVS)</li> <br>
  
  Determines common informations about the installed SVS-version and other properties. <br>
  </ul>
  <br><br>  
  
  
  <b>Polling of Camera/SVS-Properties</b><br><br>
  <ul>
  Retrieval of Camera-Properties can be done automatically if the attribute "pollcaminfoall" will be set to a value &gt; 10. <br>
  As default that attribute "pollcaminfoall" isn't be set and the automatic polling isn't be active. <br>
  The value of that attribute determines the interval of property-retrieval in seconds. If that attribute isn't be set or &lt; 10 the automatic polling won't be started <br>
  respectively stopped when the value was set to &gt; 10 before. <br><br>

  The attribute "pollcaminfoall" is monitored by a watchdog-timer. Changes of the attribute-value will be checked every 90 seconds and transact corresponding. <br>
  Changes of the pollingstate and pollinginterval will be reported in FHEM-Logfile. The reporting can be switched off by setting the attribute "pollnologging=1". <br>
  Thereby the needless growing of the logfile can be avoided. But if verbose level is set to 4 or above even though the attribute "pollnologging" is set as well, the polling <br>
  will be actived due to analysis purposes. <br><br>

  If FHEM will be restarted, the first data retrieval will be done within 60 seconds after start. <br><br>

  The state of automatic polling will be displayed by reading "PollState": <br><br>
  
  <ul>
    <li><b> PollState = Active </b>     -    automatic polling will be executed with interval correspondig value of attribute "pollcaminfoall" </li>
    <li><b> PollState = Inactive </b>   -    automatic polling won't be executed </li>
  </ul>
  <br>
  
  The readings are described <a href="#SSCamreadings">here</a>. <br><br>

  <b>Notes:</b> <br><br>

  If polling is used, the interval should be adjusted only as short as needed due to the detected camera values are predominantly static. <br>
  A feasible guide value for attribute "pollcaminfoall" could be between 600 - 1800 (s). <br>
  Per polling call and camera approximately 10 - 20 Http-calls will are stepped against Surveillance Station. <br>
  Because of that if HTTP-Timeout (pls. refer <a href="#SSCamattr">Attribut</a> "httptimeout") is set to 4 seconds, the theoretical processing time couldn't be higher than 80 seconds. <br>
  Considering a safety margin, in that example you shouldn't set the polling interval lower than 160 seconds. <br><br>

  If several Cameras are defined in SSCam, attribute "pollcaminfoall" of every Cameras shouldn't be set exactly to the same value to avoid processing bottlenecks <br>
  and thereby caused potential source of errors during request Synology Surveillance Station. <br>
  A marginal difference between the polling intervals of the defined cameras, e.g. 1 second, can already be faced as 
  sufficient value. <br><br>
  </ul>  
</ul>


<a name="SSCaminternals"></a>
<b>Internals</b> <br><br>
 <ul>
 The meaning of used Internals is depicted in following list: <br><br>
  <ul>
  <li><b>CAMID</b> - the ID of camera defined in SVS, the value will be retrieved automatically on the basis of SVS-cameraname </li>
  <li><b>CAMNAME</b> - the name of the camera in SVS </li>
  <li><b>CREDENTIALS</b> - the value is "Set" if Credentials are set </li> 
  <li><b>NAME</b> - the cameraname in FHEM </li>
  <li><b>MODEL</b> - distinction between camera device (CAM) and Surveillance Station device (SVS) </li>
  <li><b>OPMODE</b> - the last executed operation of the module </li>  
  <li><b>SERVERADDR</b> - IP-Address of SVS Host </li>
  <li><b>SERVERPORT</b> - SVS-Port </li>
  <br><br>
  </ul>
 </ul>

<a name="SSCamattr"></a>
<b>Attributes</b>
  <br><br>
  
  <ul>
  <ul>
  <li><b>debugactivetoken</b><br>
    if set the state of active token will be logged - only for debugging, don't use it in normal operation ! </li><br>
  
  <li><b>disable</b><br>
    deactivates the device definition </li><br>
  
  <li><b>httptimeout</b><br>
    Timeout-Value of HTTP-Calls to Synology Surveillance Station, Default: 4 seconds (if httptimeout = "0" 
	or not set) </li><br>
  
  <li><b>htmlattr</b><br>
    additional specifications to inline oictures to manipulate the behavior of stream, e.g. size of the image.	</li><br>
	
	    <ul>
		<b>Example:</b><br>
        attr &lt;name&gt; htmlattr width="500" height="325" top="200" left="300"
        </ul>
		<br>
  
  <li><b>livestreamprefix</b><br>
    overwrites the specifications of protocol, servername and port for further use of the livestream address, e.g. 
	as an link to external use. It has to be specified as "http(s)://&lt;servername&gt;:&lt;port&gt;"  </li><br>

  <li><b>loginRetries</b><br>
    set the amount of login-repetitions in case of failure (default = 1)   </li><br>
  
  <li><b>noQuotesForSID</b><br>
    this attribute may be helpfull in some cases to avoid errormessage "402 - permission denied" and makes login 
	possible.  </li><br>
  
  <li><b>pollcaminfoall</b><br>
    Interval of automatic polling the Camera properties (if <= 10: no polling, if &gt; 10: polling with interval) </li><br>

  <li><b>pollnologging</b><br>
    "0" resp. not set = Logging device polling active (default), "1" = Logging device polling inactive</li><br>
    
  <li><b>ptzPanel_Home</b><br>
    In the PTZ-control panel the Home-Icon (in attribute "ptzPanel_row02") is automatically assigned to the value of 
    Reading "PresetHome".
    With "ptzPanel_Home" you can change the assignment to another preset from the available Preset list. </li><br> 
    
  <li><b>ptzPanel_iconPath</b><br>
    Path for icons used in PTZ-control panel, default is "www/images/sscam". 
    The attribute value will be used for all icon-files except *.svg. </li><br> 

  <li><b>ptzPanel_iconPrefix</b><br>
    Prefix for icons used in PTZ-control panel, default is "black_btn_". 
    The attribute value will be used for all icon-files except *.svg. <br>
    If the used icon-files begin with e.g. "black_btn_" ("black_btn_CAMDOWN.png"), the icon needs to be defined in
    attributes "ptzPanel_row[00-09]" just with the subsequent part of name, e.g. "CAMDOWN.png".
    </li><br>   

  <li><b>ptzPanel_row[00-09] &lt;command&gt;:&lt;icon&gt;,&lt;command&gt;:&lt;icon&gt;,... </b><br>
    For PTZ-cameras the attributes "ptzPanel_row00" to "ptzPanel_row04" are created automatically for usage by 
    the PTZ-control panel. <br>
    The attributes contain a comma spareated list of command:icon-combinations (buttons) each panel line. 
    One panel line can contain a random number of buttons. The attributes "ptzPanel_row00" to "ptzPanel_row04" can't be 
    deleted because of they are created automatically again in that case.
    The user can change or complement the attribute values. These changes are conserved. <br>
    If needed the assignment for Home-button in "ptzPanel_row02" can be changed by attribute "ptzPanel_Home". <br>
    The icons are searched in path "ptzPanel_iconPath". The value of "ptzPanel_iconPrefix" is prepend to the icon filename.
    Own extensions of the PTZ-control panel can be done using the attributes "ptzPanel_row05" to "ptzPanel_row09". 
    For creation of own icons a template is provided in the SVN: 
    <a href="https://svn.fhem.de/trac/browser/trunk/fhem/contrib/sscam">contrib/sscam/black_btn_CAM_Template.pdn</a>. This
    template can be edited by e.g. Paint.Net.  <br><br>
    
    <b>Note:</b> <br>
    For an empty field please use ":CAMBLANK.png" respectively ":CAMBLANK.png,:CAMBLANK.png,:CAMBLANK.png,..." for an empty 
    line.
    <br><br>
    
        <ul>
		<b>Example:</b><br>
        attr &lt;name&gt; ptzPanel_row00 move upleft:CAMUPLEFTFAST.png,:CAMBLANK.png,move up:CAMUPFAST.png,:CAMBLANK.png,move upright:CAMUPRIGHTFAST.png <br>
        # The command "move upleft" is transmitted to the camera by pressing the button(icon) "CAMUPLEFTFAST.png".  <br>
        </ul>
		<br>
    </li><br>      

  <li><b>ptzPanel_use</b><br>
    Switch the usage of a PTZ-control panel in detail view respectively a created StreamDevice off or on 
    (default: on). </li><br> 
  
  <li><b>rectime</b><br>
   determines the recordtime when a recording starts. If rectime = 0 an endless recording will be started. If 
   it isn't defined, the default recordtime of 15s is activated </li><br>
  
  <li><b>recextend</b><br>
    "rectime" of a started recording will be set new. Thereby the recording time of the running recording will be 
	extended </li><br>
  
  <li><b>session</b><br>
    selection of login-Session. Not set or set to "DSM" -&gt; session will be established to DSM (Sdefault). 
	"SurveillanceStation" -&gt; session will be established to SVS </li><br>
  
  <li><b>simu_SVSversion</b><br>
    simulates another SVS version. (only a lower version than the installed one is possible !)  </li><br>
	
  <li><b>snapGalleryBoost</b><br>
    If set, the last snapshots (default 3) will be retrieved by Polling, will be stored in the FHEM-servers main memory
    and can be displayed by the "set/get ... snapGallery" command. <br>
	This mode is helpful if many or full size images shall be displayed. 
	If the attribute is set, you can't specify arguments in addition to the "set/get ... snapGallery" command. 
    (see also attribut "snapGalleryNumber") </li><br>
  
  <li><b>snapGalleryColumns</b><br>
    The number of snapshots which shall appear in one row of the gallery popup (default 3). </li><br>
	
  <li><b>snapGalleryHtmlAttr</b><br>
    the image parameter can be controlled by this attribute. <br>
	If the attribute isn't set, the value of attribute "htmlattr" will be used. <br>
	If  "htmlattr" is also not set, default parameters are used instead (width="500" height="325"). <br><br>
	
        <ul>
		<b>Example:</b><br>
        attr &lt;name&gt; snapGalleryHtmlAttr width="325" height="225"
        </ul>
		<br>
        </li>
		
  <li><b>snapGalleryNumber</b><br>
    The number of snapshots to retrieve (default 3). </li><br>
	
  <li><b>snapGallerySize</b><br>
     By this attribute the quality of the snapshot images can be controlled (default "Icon"). <br>
	 If mode "Full" is set, the images are retrieved with their original available resolution. That requires more ressources 
	 and may slow down the display. By setting attribute "snapGalleryBoost=1" the display may accelerated, because in that case
	 the images will be retrieved by continuous polling and need only bring to display. </li><br>
  
  <li><b>showStmInfoFull</b><br>
    additional stream informations like LiveStreamUrl, StmKeyUnicst, StmKeymjpegHttp will be created  </li><br>
  
  <li><b>showPassInLog</b><br>
    if set the used password will be shown in logfile with verbose 4. (default = 0) </li><br>
  
  <li><b>videofolderMap</b><br>
    replaces the content of reading "VideoFolder", Usage if e.g. folders are mountet with different names than original 
	(SVS) </li><br>
  
  <li><b>verbose</b></li><br>
  
  <ul>
     Different Verbose-Level are supported.<br>
     Those are in detail:
   
   <table>  
   <colgroup> <col width=5%> <col width=95%> </colgroup>
     <tr><td> 0  </td><td>- Start/Stop-Event will be logged </td></tr>
     <tr><td> 1  </td><td>- Error messages will be logged </td></tr>
     <tr><td> 2  </td><td>- messages according to important events were logged </td></tr>
     <tr><td> 3  </td><td>- sended commands will be logged </td></tr> 
     <tr><td> 4  </td><td>- sended and received informations will be logged </td></tr>
     <tr><td> 5  </td><td>- all outputs will be logged for error-analyses. <b>Caution:</b> a lot of data could be written into logfile ! </td></tr>
   </table>
   </ul>     
   <br>   
   <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   
  </ul>  
  </ul>
  <br><br>
 
<a name="SSCamreadings"></a>
<b>Readings</b>
 <ul>
  <br>
  Using the polling mechanism or retrieval by "get"-call readings are provieded, The meaning of the readings are listed in subsequent table: <br>
  The transfered Readings can be deversified dependend on the type of camera.<br><br>
  <ul>
  <table>  
  <colgroup> <col width=5%> <col width=95%> </colgroup>
    <tr><td><li>CamAudioType</li>       </td><td>- Indicating audio type  </td></tr>
    <tr><td><li>Availability</li>       </td><td>- Availability of Camera (disabled, enabled, disconnected, other)  </td></tr>
    <tr><td><li>CamEventNum</li>        </td><td>- delivers the total number of in SVS registered events of the camera  </td></tr>
    <tr><td><li>CamExposureControl</li> </td><td>- indicating type of exposure control  </td></tr>
    <tr><td><li>CamExposureMode</li>    </td><td>- current exposure mode (Day, Night, Auto, Schedule, Unknown)  </td></tr>
    <tr><td><li>CamForceEnableMulticast</li>  </td><td>- Is the camera forced to enable multicast.  </td></tr>
    <tr><td><li>CamIP</li>              </td><td>- IP-Address of Camera  </td></tr>
    <tr><td><li>CamLastRec</li>         </td><td>- Path / name of the last recording   </td></tr>
    <tr><td><li>CamLastRecTime</li>     </td><td>- date / starttime / endtime of the last recording   </td></tr>
    <tr><td><li>CamLiveMode</li>        </td><td>- Source of Live-View (DS, Camera)  </td></tr>
    <tr><td><li>CamModel</li>           </td><td>- Model of camera  </td></tr>
    <tr><td><li>CamMotDetSc</li>        </td><td>- state of motion detection source (disabled, by camera, by SVS) and their parameter </td></tr>
    <tr><td><li>CamNTPServer</li>       </td><td>- set time server  </td></tr>
    <tr><td><li>CamPort</li>            </td><td>- IP-Port of Camera  </td></tr>
    <tr><td><li>CamPreRecTime</li>      </td><td>- Duration of Pre-Recording (in seconds) adjusted in SVS  </td></tr>
    <tr><td><li>CamRecShare</li>        </td><td>- shared folder on disk station for recordings </td></tr>
    <tr><td><li>CamRecVolume</li>       </td><td>- Volume on disk station for recordings  </td></tr>
    <tr><td><li>CamStreamFormat</li>    </td><td>- the current format of video streaming  </td></tr>
    <tr><td><li>CamVideoType</li>       </td><td>- Indicating video type  </td></tr>
    <tr><td><li>CamVendor</li>          </td><td>- Identifier of camera producer  </td></tr>
    <tr><td><li>CamVideoFlip</li>       </td><td>- Is the video flip  </td></tr>
    <tr><td><li>CamVideoMirror</li>     </td><td>- Is the video mirror  </td></tr>
	<tr><td><li>CamVideoRotate</li>     </td><td>- Is the video rotate  </td></tr>
    <tr><td><li>CapAudioOut</li>        </td><td>- Capability to Audio Out over Surveillance Station (false/true)  </td></tr>
    <tr><td><li>CapChangeSpeed</li>     </td><td>- Capability to various motion speed  </td></tr>
    <tr><td><li>CapPTZAbs</li>          </td><td>- Capability to perform absolute PTZ action  </td></tr>
    <tr><td><li>CapPTZAutoFocus</li>    </td><td>- Capability to perform auto focus action  </td></tr>
    <tr><td><li>CapPTZDirections</li>   </td><td>- the PTZ directions that camera support  </td></tr>
    <tr><td><li>CapPTZFocus</li>        </td><td>- mode of support for focus action  </td></tr>
    <tr><td><li>CapPTZHome</li>         </td><td>- Capability to perform home action  </td></tr>
    <tr><td><li>CapPTZIris</li>         </td><td>- mode of support for iris action  </td></tr>
    <tr><td><li>CapPTZObjTracking</li>  </td><td>- Capability to perform objekt-tracking </td></tr>
    <tr><td><li>CapPTZPan</li>          </td><td>- Capability to perform pan action  </td></tr>
    <tr><td><li>CapPTZPresetNumber</li> </td><td>- The maximum number of preset supported by the model. 0 stands for preset incapability  </td></tr>
    <tr><td><li>CapPTZTilt</li>         </td><td>- mode of support for tilt action  </td></tr>
    <tr><td><li>CapPTZZoom</li>         </td><td>- Capability to perform zoom action  </td></tr>
    <tr><td><li>DeviceType</li>         </td><td>- device type (Camera, Video_Server, PTZ, Fisheye)  </td></tr>
    <tr><td><li>Error</li>              </td><td>- message text of last error  </td></tr>
    <tr><td><li>Errorcode</li>          </td><td>- error code of last error  </td></tr>
	<tr><td><li>HomeModeState</li>      </td><td>- HomeMode-state (SVS-version 8.1.0 and above)   </td></tr>
	<tr><td><li>LastLogEntry</li>       </td><td>- the neweset entry of Surveillance Station Log (only if SVS-device and if attribute pollcaminfoall is set)   </td></tr>
    <tr><td><li>LastSnapFilename</li>   </td><td>- the filename of the last snapshot   </td></tr>
    <tr><td><li>LastSnapId</li>         </td><td>- the ID of the last snapshot   </td></tr>    
    <tr><td><li>LastSnapTime</li>       </td><td>- timestamp of the last snapshot   </td></tr> 
    <tr><td><li>LastUpdateTime</li>     </td><td>- date / time the last update of readings by "caminfoall"  </td></tr> 
    <tr><td><li>LiveStreamUrl </li>     </td><td>- the livestream URL if stream is started (is shown if <a href="#SSCamattr">attribute</a> "showStmInfoFull" is set) </td></tr> 
    <tr><td><li>Patrols</li>            </td><td>- in Synology Surveillance Station predefined patrols (at PTZ-Cameras)  </td></tr>
    <tr><td><li>PollState</li>          </td><td>- shows the state of automatic polling  </td></tr>    
    <tr><td><li>PresetHome</li>         </td><td>- Name of Home-position (at PTZ-Cameras)  </td></tr>
    <tr><td><li>Presets</li>            </td><td>- in Synology Surveillance Station predefined Presets (at PTZ-Cameras)  </td></tr>
    <tr><td><li>Record</li>             </td><td>- if recording is running = Start, if no recording is running = Stop  </td></tr> 
    <tr><td><li>StmKey</li>             </td><td>- current streamkey. it can be used to open livestreams without session id    </td></tr> 
    <tr><td><li>StmKeyUnicst</li>       </td><td>- Uni-cast stream path of the camera. (<a href="#SSCamattr">attribute</a> "showStmInfoFull" has to be set)  </td></tr> 
    <tr><td><li>StmKeymjpegHttp</li>    </td><td>- Mjpeg stream path(over http) of the camera (<a href="#SSCamattr">attribute</a> "showStmInfoFull" has to be set)  </td></tr> 
    <tr><td><li>SVScustomPortHttp</li>  </td><td>- Customized port of Surveillance Station (HTTP) (to get with "svsinfo")  </td></tr> 
    <tr><td><li>SVScustomPortHttps</li> </td><td>- Customized port of Surveillance Station (HTTPS) (to get with "svsinfo")  </td></tr>
    <tr><td><li>SVSlicenseNumber</li>   </td><td>- The total number of installed licenses (to get with "svsinfo")  </td></tr>
    <tr><td><li>SVSuserPriv</li>        </td><td>- The effective rights of the user used for log in (to get with "svsinfo")  </td></tr>
    <tr><td><li>SVSversion</li>         </td><td>- package version of the installed Surveillance Station (to get with "svsinfo")  </td></tr>
    <tr><td><li>UsedSpaceMB</li>        </td><td>- used disk space of recordings by Camera  </td></tr>
    <tr><td><li>VideoFolder</li>        </td><td>- Path to the recorded video  </td></tr>
  </table>
  </ul>
  <br><br>    
 </ul>

</ul>


=end html
=begin html_DE

<a name="SSCam"></a>
<h3>SSCam</h3>
<ul>
    Mit diesem Modul können Operationen von in der Synology Surveillance Station (SVS) definierten Kameras und Funktionen 
	der SVS ausgeführt werden. Es basiert auf der SVS API und unterstützt die SVS ab Version 7. <br>
    Zur Zeit werden folgende Funktionen unterstützt: <br><br>
    <ul>
     <ul>
      <li>Start einer Aufnahme</li>
      <li>Stop einer Aufnahme (per Befehl bzw. automatisch nach Ablauf der Aufnahmedauer) </li>
      <li>Aufnehmen eines Schnappschusses und Ablage in der Synology Surveillance Station </li>
      <li>Deaktivieren einer Kamera in Synology Surveillance Station</li>
      <li>Aktivieren einer Kamera in Synology Surveillance Station</li>
      <li>Steuerung der Belichtungsmodi Tag, Nacht bzw. Automatisch </li>
      <li>Umschaltung der Ereigniserkennung durch Kamera, durch SVS oder deaktiviert  </li>
      <li>steuern der Erkennungsparameterwerte Empfindlichkeit, Schwellwert, Objektgröße und Prozentsatz für Auslösung </li>
      <li>Abfrage von Kameraeigenschaften (auch mit Polling) sowie den Eigenschaften des installierten SVS-Paketes</li>
      <li>Bewegen an eine vordefinierte Preset-Position (bei PTZ-Kameras) </li>
      <li>Start einer vordefinierten Überwachungstour (bei PTZ-Kameras)  </li>
      <li>Positionieren von PTZ-Kameras zu absoluten X/Y-Koordinaten  </li>
      <li>kontinuierliche Bewegung von PTZ-Kameras   </li>
      <li>auslösen externer Ereignisse 1-10 (Aktionsregel SVS)   </li>
      <li>starten und beenden von Kamera-Livestreams incl. Audiowiedergabe, anzeigen der letzten Aufnahme oder des letzten Schnappschusses  </li>
      <li>Abruf und Ausgabe der Kamera Streamkeys sowie Stream-Urls (Nutzung von Kamera-Livestreams ohne Session Id)  </li>
      <li>abspielen der letzten Aufnahme bzw. Anzeige des letzten Schnappschusses  </li>
	  <li>anzeigen der gespeicherten Anmeldeinformationen (Credentials)  </li>
	  <li>Ein- bzw. Ausschalten des Surveillance Station HomeMode und abfragen des HomeMode-Status </li>
	  <li>abrufen des Surveillance Station Logs, auswerten des neuesten Eintrags als Reading  </li>
	  <li>erzeugen einer Gallerie der letzten 1-10 Schnappschüsse (als Popup oder permanentes Device)  </li>
      <li>Start bzw. Stop Objekt Tracking (nur unterstützte PTZ-Kameras mit dieser Fähigkeit)  </li>
      <li>Setzen/Löschen eines Presets (bei PTZ-Kameras)  </li>
      <li>Setzen der Home-Position (bei PTZ-Kameras)  </li>
      <li>erstellen eines Paneels zur Kamera-Steuerung. (bei PTZ-Kameras)  </li>
	  <li>erzeugen eines separaten Streaming-Devices (createStreamDev)  </li>
     </ul> 
    </ul>
    <br>
    
    Die Aufnahmen stehen in der Synology Surveillance Station (SVS) zur Verfügung und unterliegen, wie jede andere Aufnahme, den in der Synology Surveillance Station eingestellten Regeln. <br>
    So werden zum Beispiel die Aufnahmen entsprechend ihrer Archivierungsfrist gespeichert und dann gelöscht. <br><br>
    
    Wenn sie über dieses Modul diskutieren oder zur Verbesserung des Moduls beitragen möchten, ist im FHEM-Forum ein Sammelplatz unter:<br>
    <a href="http://forum.fhem.de/index.php/topic,45671.msg374390.html#msg374390">49_SSCam: Fragen, Hinweise, Neuigkeiten und mehr rund um dieses Modul</a>.<br><br>

    Weitere Infomationen zum Modul sind im FHEM-Wiki zu finden:<br>
    <a href="http://www.fhemwiki.de/wiki/SSCAM_-_Steuerung_von_Kameras_in_Synology_Surveillance_Station">SSCAM - Steuerung von Kameras in Synology Surveillance Station</a>.<br><br>
    
    
    <b>Vorbereitung </b> <br><br>
    
    <ul>
    Dieses Modul nutzt das Perl-Modul JSON. <br>
	Auf Debian-Linux basierenden Systemen kann es installiert werden mit: <br><br>
    
    <code>sudo apt-get install libjson-perl</code> <br><br>
	
    Das Modul verwendet für HTTP-Calls die nichtblockierenden Funktionen von HttpUtils bzw. HttpUtils_NonblockingGet. <br> 
    Im DSM bzw. der Synology Surveillance Station muß ein Nutzer angelegt sein. Die Zugangsdaten werden später über ein Set-Kommando dem angelegten Gerät zugewiesen. <br>
    Nähere Informationen dazu unter <a href="#SSCam_Credentials">Credentials</a><br><br>
        
    Überblick über die Perl-Module welche von SSCam genutzt werden: <br><br>
    
    JSON            <br>
    Data::Dumper    <br>                  
    MIME::Base64    <br>
    Time::HiRes     <br>
    HttpUtils       (FHEM-Modul) <br><br>
    </ul>

<a name="SSCamdefine"></a>
<b>Definition</b>
  <ul>
  <br>
    Bei der Definition wird zwischen einer Kamera-Definition und der Definition einer Surveillance Station (SVS), d.h.
    der Applikation selbst auf der Diskstation, unterschieden. 
    Abhängig von der Art des definierten Devices wird das Internal MODEL auf "&lt;Hersteller&gt; - &lt;Kameramodell&gt;" oder 
    SVS gesetzt und eine passende Teilmenge der beschriebenen set/get-Befehle dem Device zugewiesen. <br>
	Der Gültigkeitsbereich von set/get-Befehlen ist nach dem jeweiligen Befehl angegeben "gilt für CAM, SVS, CAM/SVS".
	<br><br>
	
    Eine Kamera wird definiert durch: <br><br>
	<ul>
      <b><code>define &lt;name&gt; SSCAM &lt;Kameraname in SVS&gt; &lt;ServerAddr&gt; [Port] </code></b> <br><br>
    </ul>
    
    Zunächst muß diese Kamera in der Synology Surveillance Station 7.0 oder höher eingebunden sein und entsprechend 
	funktionieren. <br><br>
	
	Ein SVS-Device zur Steuerung von Funktionen der Surveillance Station wird definiert mit: <br><br>
	<ul>
	  <b><code>define &lt;name&gt; SSCAM SVS &lt;ServerAddr&gt; [Port] </code></b> <br><br>
	</ul>
    
    In diesem Fall wird statt &lt;Kameraname in SVS&gt; nur <b>SVS</b> angegeben. <br><br>
	
	Das Modul SSCam basiert auf Funktionen der Synology Surveillance Station API. <br>
    Momentan wird nur das HTTP-Protokoll unterstützt um die Web-Services der Synology DS aufzurufen. <br><br>  
    
    Die Parameter beschreiben im Einzelnen:
    <br>
    <br>    
    
    <table>
    <colgroup> <col width=15%> <col width=85%> </colgroup>
    <tr><td>name:           </td><td>der Name des neuen Gerätes in FHEM</td></tr>
    <tr><td>Kameraname:     </td><td>Kameraname wie er in der Synology Surveillance Station angegeben ist für Kamera-Device, "SVS" für SVS-Device. Leerzeichen im Namen sind nicht erlaubt. </td></tr>
    <tr><td>ServerAddr:     </td><td>die IP-Addresse des Synology Surveillance Station Host. Hinweis: Es sollte kein Servername verwendet werden weil DNS-Aufrufe in FHEM blockierend sind.</td></tr>
    <tr><td>Port:           </td><td>optional - der Port der Synology Surveillance Station. Wenn nicht angegeben wird der Default-Port 5000 (nur HTTP) gesetzt </td></tr>
    </table>

    <br><br>

    <b>Beispiel:</b>
     <pre>
      <code>define CamCP SSCAM Carport 192.168.2.20 [5000] </code>
      erstellt ein neues Kamera-Device CamCP

      <code>define DS1 SSCAM SVS 192.168.2.20 [5000] </code>
      erstellt ein neues SVS-Device DS1
     </pre>
     
    Wird eine neue Kamera definiert, wird diesem Device zunächst eine Standardaufnahmedauer von 15 zugewiesen. <br>
    Über das <a href="#SSCamattr">Attribut</a> "rectime" kann die Aufnahmedauer für jede Kamera individuell angepasst werden. Der Wert "0" für "rectime" führt zu einer Endlosaufnahme, die durch "set &lt;name&gt; off" wieder gestoppt werden muß. <br>
    Ein Logeintrag mit einem entsprechenden Hinweis auf diesen Umstand wird geschrieben. <br><br>

    Wird das <a href="#SSCamattr">Attribut</a> "rectime" gelöscht, greift wieder der Default-Wert (15s) für die Aufnahmedauer. <br><br>

    Mit dem <a href="#SSCamset">Befehl</a> <b>"set &lt;name&gt; on [rectime]"</b> wird die Aufnahmedauer temporär festgelegt und überschreibt einmalig sowohl den Defaultwert als auch den Wert des gesetzten Attributs "rectime". <br>
    Auch in diesem Fall führt <b>"set &lt;name&gt; on 0"</b> zu einer Daueraufnahme. <br><br>

    Eine eventuell in der SVS eingestellte Dauer der Voraufzeichnung wird weiterhin berücksichtigt. <br><br>
    
    Erkennt das Modul die definierte Kamera als PTZ-Device (Reading "DeviceType = PTZ"), wird automatisch ein 
    Steuerungspaneel in der Detailansicht erstellt. Dieses Paneel setzt SVS >= 7.1 voraus. Die Eigenschaften und das 
    Verhalten des Paneels können mit den <a href="#SSCamattr">Attributen</a> "ptzPanel_.*" beeinflusst werden. <br>
    Siehe dazu auch den <a href="#SSCamset">Befehl</a> <b>"set &lt;name&gt; createPTZcontrol"</b>.
    
    <br><br><br>
    </ul>
    
    <a name="SSCam_Credentials"></a>
    <b>Credentials </b><br><br>
    
    <ul>
    Nach dem Definieren des Gerätes müssen zuerst die Zugangsparameter gespeichert werden. Das geschieht mit dem Befehl:
   
    <pre> 
     set &lt;name&gt; credentials &lt;Username&gt; &lt;Passwort&gt;
    </pre>
    
	Die Passwortlänge beträgt maximal 20 Zeichen. <br> 
    Der Anwender kann in Abhängigkeit der beabsichtigten einzusetzenden Funktionen einen Nutzer im DSM bzw. in der Surveillance Station einrichten. <br>
    Ist der DSM-Nutzer der Gruppe Administratoren zugeordnet, hat er auf alle Funktionen Zugriff. Ohne diese Gruppenzugehörigkeit können nur Funktionen mit niedrigeren <br>
    Rechtebedarf ausgeführt werden. Die benötigten Mindestrechte der Funktionen sind in der Tabelle weiter unten aufgeführt. <br>
    
    Alternativ zum DSM-Nutzer kann ein in der SVS angelegter Nutzer verwendet werden. Auch in diesem Fall hat ein Nutzer vom Typ Manager das Recht alle Funktionen  <br>
    auszuführen, wobei der Zugriff auf bestimmte Kameras/ im Privilegienprofil beschränkt werden kann (siehe Hilfefunktion in SVS). <br>
    Als Best Practice wird vorgeschlagen jeweils einen User im DSM und einen in der SVS anzulegen: <br><br>
    
    <ul>
    <li>DSM-User als Mitglied der Admin-Gruppe: uneingeschränkter Test aller Modulfunktionen -> session:DSM  </li>
    <li>SVS-User als Manager oder Betrachter: angepasstes Privilegienprofil -> session: SurveillanceStation  </li>
    </ul>
    <br>
    
    Über das <a href="#SSCamattr">Attribut</a> "session" kann ausgewählt werden, ob die Session mit dem DSM oder der SVS augebaut werden soll. <br>
    Erfolgt der Session-Aufbau mit dem DSM, stehen neben der SVS Web-API auch darüber hinaus gehende API-Zugriffe zur Verfügung die unter Umständen zur Verarbeitung benötigt werden. <br><br>
    
    Nach der Gerätedefinition ist die Grundeinstellung "Login in das DSM", d.h. es können Credentials mit Admin-Berechtigungen genutzt werden um zunächst alle <br>
    Funktionen der Kameras testen zu können. Danach können die Credentials z.B. in Abhängigkeit der benötigten Funktionen auf eine SVS-Session mit entsprechend beschränkten Privilegienprofil umgestellt werden. <br><br>
    
    Die nachfolgende Aufstellung zeigt die Mindestanforderungen der jeweiligen Modulfunktionen an die Nutzerrechte. <br><br>
    <ul>
      <table>
      <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td><li>set ... credentials        </td><td> -                                            </li></td></tr>
      <tr><td><li>set ... delPreset          </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      <tr><td><li>set ... disable            </td><td> session: ServeillanceStation - Manager       </li></td></tr>
      <tr><td><li>set ... enable             </td><td> session: ServeillanceStation - Manager       </li></td></tr>
      <tr><td><li>set ... expmode            </td><td> session: ServeillanceStation - Manager       </li></td></tr>
      <tr><td><li>set ... extevent           </td><td> session: DSM - Nutzer Mitglied von Admin-Gruppe     </li></td></tr>
	  <tr><td><li>set ... goPreset           </td><td> session: ServeillanceStation - Betrachter mit Privileg Objektivsteuerung der Kamera  </li></td></tr>
      <tr><td><li>set ... homeMode           </td><td> session: ServeillanceStation - Betrachter mit Privileg Home-Modus schalten     </li></td></tr>
	  <tr><td><li>set ... goAbsPTZ           </td><td> session: ServeillanceStation - Betrachter mit Privileg Objektivsteuerung der Kamera  </li></td></tr>
	  <tr><td><li>set ... move               </td><td> session: ServeillanceStation - Betrachter mit Privileg Objektivsteuerung der Kamera  </li></td></tr>
      <tr><td><li>set ... motdetsc           </td><td> session: ServeillanceStation - Manager       </li></td></tr>
	  <tr><td><li>set ... on                 </td><td> session: ServeillanceStation - Betrachter mit erweiterten Privileg "manuelle Aufnahme" </li></td></tr>
      <tr><td><li>set ... off                </td><td> session: ServeillanceStation - Betrachter mit erweiterten Privileg "manuelle Aufnahme" </li></td></tr>
	  <tr><td><li>set ... runView            </td><td> session: ServeillanceStation - Betrachter mit Privileg Liveansicht für Kamera        </li></td></tr>
      <tr><td><li>set ... runPatrol          </td><td> session: ServeillanceStation - Betrachter mit Privileg Objektivsteuerung der Kamera  </li></td></tr>
	  <tr><td><li>set ... setHome            </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      <tr><td><li>set ... setPreset          </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      <tr><td><li>set ... snap               </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
	  <tr><td><li>set ... snapGallery        </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
	  <tr><td><li>set ... stopView           </td><td> -                                            </li></td></tr>
      <tr><td><li>get ... caminfo[all]       </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      <tr><td><li>get ... eventlist          </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      <tr><td><li>get ... listLog            </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      <tr><td><li>get ... listPresets        </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
	  <tr><td><li>get ... scanVirgin         </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      <tr><td><li>get ... svsinfo            </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      <tr><td><li>get ... snapfileinfo       </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
	  <tr><td><li>get ... snapGallery        </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
	  <tr><td><li>get ... snapinfo           </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      <tr><td><li>get ... stmUrlPath         </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      </table>
    </ul>
      <br><br>
    
    
    <a name="SSCam_HTTPTimeout"></a>
    <b>HTTP-Timeout setzen</b><br><br>
    
    Alle Funktionen dieses Moduls verwenden HTTP-Aufrufe gegenüber der SVS Web API. <br>
    Der Standardwert für den HTTP-Timeout beträgt 4 Sekunden. Durch Setzen des <a href="#SSCamattr">Attributes</a> "httptimeout" > 0 kann dieser Wert bei Bedarf entsprechend den technischen Gegebenheiten angepasst werden. <br>
     
    
  </ul>
  <br><br><br>
  
<a name="SSCamset"></a>
<b>Set </b>
<ul>
  <br>
  Die aufgeführten set-Befehle sind für CAM/SVS-Devices oder nur für CAM-Devices bzw. nur für SVS-Devices gültig. Sie stehen im 
  Drop-Down-Menü des jeweiligen Devices zur Auswahl zur Verfügung. <br><br>
  
  <ul>
  <a name="SSCamcreateStreamDev"></a>
  <li><b> set &lt;name&gt; createStreamDev [mjpeg | switched] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Es wird ein separates Streaming-Device (Type SSCamSTRM) erstellt. Dieses Device kann z.B. als separates Device 
  in einem Dashboard genutzt werden.
  Dem Streaming-Device wird der aktuelle Raum des Kameradevice zugewiesen sofern dort gesetzt. 
  Die Gestaltung kann durch HTML-Tags im <a href="#SSCamattr">Attribut</a> "htmlattr" im Kameradevice oder mit den 
  spezifischen Attributen im Streaming-Device beeinflusst werden. <br>
  Soll ein HLS-Stream im Streaming-Device vom Typ "switched" gestartet werden, muss die Kamera in der Synology Surveillance Station 
  auf das Videoformat H.264 eingestellt sein. Diese Auswahltaste wird deshalb im nur im Streaming-Device angeboten wenn das 
  Reading "CamStreamFormat = HLS" beinhaltet. <br>
  HLS (HTTP Live Streaming) kann momentan nur auf Mac Safari oder mobilen iOS/Android-Geräten wiedergegeben werden. <br>
  Im "switched"-Device werden Drucktasten zur Steuerung angeboten.
  <br><br>
  
    <ul>
    <table>
    <colgroup> <col width=10%> <col width=90%> </colgroup>
      <tr><td>mjpeg     </td><td>- das Streaming-Device gibt einen permanenten MJPEG Kamerastream wieder (Streamkey Methode) </td></tr>
      <tr><td>switched  </td><td>- Wiedergabe unterschiedlicher Streamtypen. Drucktasten zur Steuerung werden angeboten. </td></tr>
    </table>
    </ul>
    <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; createPTZcontrol </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für PTZ-CAM)</li> <br>
  
  Es wird ein separates PTZ-Steuerungspaneel (Type SSCamSTRM) erstellt. Es wird der aktuelle Raum des Kameradevice 
  zugewiesen sofern dort gesetzt.  
  Mit den "ptzPanel_.*"-<a href="#SSCamattr">Attributen</a> bzw. den spezifischen Attributen des erzeugten 
  SSCamSTRM-Devices können die Eigenschaften des PTZ-Paneels beeinflusst werden. <br> 
  <br><br>
  </ul>
    
  <ul>
  <li><b> set &lt;name&gt; createSnapGallery </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Es wird eine Schnappschußgallerie als separates Device (Type SSCamSTRM) erzeugt. Das Device wird im Raum 
  "SnapGallery" erstellt.
  Mit den "snapGallery..."-<a href="#SSCamattr">Attributen</a> bzw. den spezifischen Attributen des erzeugten SSCamSTRM-Devices 
  können die Eigenschaften der Schnappschußgallerie beeinflusst werden. <br> 
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; credentials &lt;username&gt; &lt;password&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM/SVS)</li> <br>
  
  Setzt Username / Passwort für den Zugriff auf die Synology Surveillance Station. 
  Siehe <a href="#SSCam_Credentials">Credentials</a><br>
  
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; delPreset &lt;PresetName&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für PTZ-CAM)</li> <br>
  
  Löscht einen Preset "&lt;PresetName&gt;". Im FHEMWEB wird eine Drop-Down Liste der aktuell vorhandenen 
  Presets angeboten.

  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; [enable|disable] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Aktviviert / deaktiviert eine Kamera. <br>
  Um eine Liste von Kameras oder alle Kameras (mit Regex) zum Beispiel um 21:46 zu <b>deaktivieren</b> / zu <b>aktivieren</b> zwei Beispiele mit at:
  <pre>
     define a13 at 21:46 set CamCP1,CamFL,CamHE1,CamTER disable (enable)
     define a14 at 21:46 set Cam.* disable (enable)
  </pre>
  
  Etwas komfortabler gelingt das Schalten aller Kameras über einen Dummy. Zunächst wird der Dummy angelegt:
  <pre>
     define allcams dummy
     attr allcams eventMap on:enable off:disable
     attr allcams room Cams
     attr allcams webCmd enable:disable
  </pre>
  
  Durch Verknüpfung mit zwei angelegten notify, jeweils ein notify für "enable" und "disable", kann man durch Schalten des Dummys auf "enable" bzw. "disable" alle Kameras auf einmal aktivieren bzw. deaktivieren.
  <pre>
     define all_cams_disable notify allcams:.*off set CamCP1,CamFL,CamHE1,CamTER disable
     attr all_cams_disable room Cams

     define all_cams_enable notify allcams:on set CamCP1,CamFL,CamHE1,CamTER enable
     attr all_cams_enable room Cams
  </pre>
  </ul>
  <br>
  
  <ul>
  <li><b> set &lt;name&gt; expmode [day|night|auto] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Mit diesem Befehl kann der Belichtungsmodus der Kameras gesetzt werden. Dadurch wird z.B. das Verhalten der Kamera-LED's entsprechend gesteuert. 
  Die erfolgreiche Umschaltung wird durch das Reading CamExposureMode ("get ... caminfoall") reportet. <br><br>
  
  <b> Hinweis: </b> <br>
  Die erfolgreiche Ausführung dieser Funktion ist davon abhängig ob die SVS diese Funktionalität der Kamera unterstützt. 
  Ist in SVS -&gt; IP-Kamera -&gt; Optimierung -&gt; Belichtungsmodus das Feld für den Tag/Nachtmodus grau hinterlegt, ist nicht von einer lauffähigen Unterstützung dieser 
  Funktion auszugehen. 
  <br><br>
  </ul>

  <ul>
  <li><b> set &lt;name&gt; extevent [ 1-10 ] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für SVS)</li> <br>
  
  Dieses Kommando triggert ein externes Ereignis (1-10) in der SVS. 
  Die Aktionen, die dieses Ereignis auslöst, sind zuvor in dem Aktionsregeleditor der SVS einzustellen. Es stehen die Ereignisse 
  1-10 zur Verfügung.
  In der Benachrichtigungs-App der SVS können auch Email, SMS oder Mobil (DS-Cam) Nachrichten ausgegeben werden wenn ein externes 
  Ereignis ausgelöst wurde.
  Nähere Informationen dazu sind in der Hilfe zum Aktionsregeleditor zu finden.
  Der verwendete User benötigt Admin-Rechte in einer DSM-Session.
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; goAbsPTZ [ X Y | up | down | left | right ] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Mit diesem Kommando wird eine PTZ-Kamera in Richtung einer wählbaren absoluten X/Y-Koordinate bewegt, oder zur maximalen Absolutposition in Richtung up/down/left/right. 
  Die Option ist nur für Kameras verfügbar die das Reading "CapPTZAbs=true" (die Fähigkeit für PTZAbs-Aktionen) besitzen. Die Eigenschaften der Kamera kann mit "get &lt;name&gt; caminfoall" abgefragt werden.
  <br><br>

  Beispiel für Ansteuerung absoluter X/Y-Koordinaten: <br>

  <pre>
    set &lt;name&gt; goAbsPTZ 120 450
  </pre>
 
  Dieses Beispiel bewegt die Kameralinse in die Position X=120 und Y=450. <br>
  Der Wertebereich ist dabei:

  <pre>
    X = 0 - 640      (0 - 319 bewegt nach links, 321 - 640 bewegt nach rechts, 320 bewegt die Linse nicht)
    Y = 0 - 480      (0 - 239 bewegt nach unten, 241 - 480 bewegt nach oben, 240 bewegt die Linse nicht) 
  </pre>

  Die Linse kann damit in kleinsten bis sehr großen Schritten in die gewünschte Richtung bewegt werden. 
  Dieser Vorgang muß ggf. mehrfach wiederholt werden um die Kameralinse in die gewünschte Position zu bringen. <br><br>

  Soll die Bewegung mit der maximalen Schrittweite erfolgen, kann zur Vereinfachung der Befehl:

  <pre>
   set &lt;name&gt; goAbsPTZ [up|down|left|right]
  </pre>

  verwendet werden. Die Optik wird in diesem Fall mit der größt möglichen Schrittweite zur Absolutposition in der angegebenen Richtung bewegt. 
  Auch in diesem Fall muß der Vorgang ggf. mehrfach wiederholt werden um die Kameralinse in die gewünschte Position zu bringen.
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; goPreset &lt;Preset&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Mit diesem Kommando können PTZ-Kameras in eine vordefininierte Position bewegt werden. <br>
  Die Preset-Positionen müssen dazu zunächst in der Synology Surveillance Station angelegt worden sein. Das geschieht in der PTZ-Steuerung im IP-Kamera Setup.
  Die Presets werden über das Kommando "get &lt;name&gt; caminfoall" eingelesen (geschieht bei restart von FHEM automatisch). Der Einlesevorgang kann durch ein Kamerapolling
  regelmäßig wiederholt werden. Ein langes Pollingintervall ist in diesem Fall empfehlenswert, da sich die Presetpositionen nur im Fall der Neuanlage bzw. Änderung verändern werden. 
  <br><br>
  
  Hier ein Beispiel einer PTZ-Steuerung in Abhängigkeit eines IR-Melder Events:
  
  <pre>
    define CamFL.Preset.Wandschrank notify MelderTER:on.* set CamFL goPreset Wandschrank, ;; define CamFL.Preset.record at +00:00:10 set CamFL on 5 ;;;; define s3 at +*{3}00:00:05 set CamFL snap ;; define CamFL.Preset.back at +00:00:30 set CamFL goPreset Home
  </pre>
  
  Funktionsweise: <br>
  Der IR-Melder "MelderTER" registriert eine Bewegung. Daraufhin wird die Kamera CamFL in die Preset-Position "Wandschrank" gebracht. Eine Aufnahme mit Dauer von 5 Sekunden startet 10 Sekunden
  später. Da die Voraufnahmezeit der Kamera 10s beträgt (vgl. Reading "CamPreRecTime"), startet die effektive Aufnahme wenn der Kameraschwenk beginnt. <br>
  Mit dem Start der Aufnahme werden drei Schnappschüsse im Abstand von 5 Sekunden angefertigt. <br>
  Nach einer Zeit von 30 Sekunden fährt die Kamera wieder zurück in die "Home"-Position. <br><br>
  
  Ein Auszug aus dem Log verdeutlicht den Ablauf:
  
  <pre>  
   2016.02.04 15:02:14 2: CamFL - Camera Flur_Vorderhaus has moved to position "Wandschrank"
   2016.02.04 15:02:24 2: CamFL - Camera Flur_Vorderhaus Recording with Recordtime 5s started
   2016.02.04 15:02:29 2: CamFL - Snapshot of Camera Flur_Vorderhaus has been done successfully
   2016.02.04 15:02:30 2: CamFL - Camera Flur_Vorderhaus Recording stopped
   2016.02.04 15:02:34 2: CamFL - Snapshot of Camera Flur_Vorderhaus has been done successfully
   2016.02.04 15:02:39 2: CamFL - Snapshot of Camera Flur_Vorderhaus has been done successfully
   2016.02.04 15:02:44 2: CamFL - Camera Flur_Vorderhaus has moved to position "Home"
  </pre>
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; homeMode [on|off] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für SVS)</li> <br>
  
  Schaltet den HomeMode der Surveillance Station ein bzw. aus. 
  Informationen zum HomeMode sind in der <a href="https://www.synology.com/de-de/knowledgebase/Surveillance/help/SurveillanceStation/home_mode">Synology Onlinehilfe</a> 
  enthalten.
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; motdetsc [camera|SVS|disable] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Der Befehl "motdetsc" (steht für motion detection source) schaltet die Bewegungserkennung in den gewünschten Modus. 
  Wird die Bewegungserkennung durch die Kamera / SVS ohne weitere Optionen eingestellt, werden die momentan gültigen Bewegungserkennungsparameter der 
  Kamera / SVS beibehalten. Die erfolgreiche Ausführung der Operation lässt sich u.a. anhand des Status von SVS -&gt; IP-Kamera -&gt; Ereigniserkennung -&gt; 
  Bewegung nachvollziehen. <br><br>
  Für die Bewegungserkennung durch SVS bzw. durch Kamera können weitere Optionen angegeben werden. Die verfügbaren Optionen bezüglich der Bewegungserkennung 
  durch SVS sind "Empfindlichkeit" und "Schwellwert". <br><br>
  <ul>
  <table>
  <colgroup> <col width=50%> <col width=50%> </colgroup>
      <tr><td>set &lt;name&gt; motdetsc SVS [Empfindlichkeit] [Schwellwert]  </td><td># Befehlsmuster  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc SVS 91 30                            </td><td># setzt die Empfindlichkeit auf 91 und den Schwellwert auf 30  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc SVS 0 40                             </td><td># behält gesetzten Wert für Empfindlichkeit bei, setzt Schwellwert auf 40  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc SVS 15                               </td><td># setzt die Empfindlichkeit auf 15, Schwellwert bleibt unverändert   </td></tr>
  </table>
  </ul>
  <br><br>
  
  Wird die Bewegungserkennung durch die Kamera genutzt, stehen die Optionen "Empfindlichkeit", "Objektgröße" und "Prozentsatz für Auslösung" zur Verfügung. <br><br>
  <ul>
  <table>
  <colgroup> <col width=50%> <col width=50%> </colgroup>
      <tr><td>set &lt;name&gt; motdetsc camera [Empfindlichkeit] [Schwellwert] [Prozentsatz] </td><td># Befehlsmuster  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc camera 89 0 20                                       </td><td># setzt die Empfindlichkeit auf 89, Prozentsatz auf 20  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc camera 0 40 10                                      </td><td># behält gesetzten Wert für Empfindlichkeit bei, setzt Schwellwert auf 40, Prozentsatz auf 10  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc camera 30                                            </td><td># setzt die Empfindlichkeit auf 30, andere Werte bleiben unverändert  </td></tr>
      </table>
  </ul>
  <br><br>

  Es ist immer die Reihenfolge der Optionswerte zu beachten. Nicht gewünschte Optionen sind mit "0" zu besetzen sofern danach Optionen folgen 
  deren Werte verändert werden sollen (siehe Beispiele oben). Der Zahlenwert der Optionen beträgt 1 - 99 (außer Sonderfall "0"). <br><br>
  
  Die jeweils verfügbaren Optionen unterliegen der Funktion der Kamera und der Unterstützung durch die SVS. Es können jeweils nur die Optionen genutzt werden die in 
  SVS -&gt; Kamera bearbeiten -&gt; Ereigniserkennung zur Verfügung stehen. Weitere Infos sind der Online-Hilfe zur SVS zu entnehmen. <br><br>
  
  Über den Befehl "get &lt;name&gt; caminfoall" wird auch das <a href="#SSCamreadings">Reading</a> "CamMotDetSc" aktualisiert welches die gegenwärtige Einstellung der Bewegungserkennung dokumentiert. 
  Es werden nur die Parameter und Parameterwerte angezeigt, welche die SVS aktiv unterstützt. Die Kamera selbst kann weiterführende Einstellmöglichkeiten besitzen. <br><br>
  
  Beipiel:
  <pre>
  CamMotDetSc    SVS, sensitivity: 76, threshold: 55
  </pre>
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; move [ right | up | down | left | dir_X ] [Sekunden] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM bis SVS Version 7.1)</li> 
      <b> set &lt;name&gt; move [ right | upright | up | upleft | left | downleft | down | downright ] [Sekunden] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM ab SVS Version 7.2) <br><br>
  
  Mit diesem Kommando wird eine kontinuierliche Bewegung der PTZ-Kamera gestartet. Neben den vier Grundrichtungen up/down/left/right stehen auch 
  Zwischenwinkelmaße "dir_X" zur Verfügung. Die Feinheit dieser Graduierung ist von der Kamera abhängig und kann dem Reading "CapPTZDirections" entnommen werden. <br><br>

  Das Bogenmaß von 360 Grad teilt sich durch den Wert von "CapPTZDirections" und beschreibt die Bewegungsrichtungen beginnend mit "0=rechts" entgegen dem 
  Uhrzeigersinn. D.h. bei einer Kamera mit "CapPTZDirections = 8" bedeutet dir_0 = rechts, dir_2 = oben, dir_4 = links, dir_6 = unten bzw. dir_1, dir_3, dir_5 und dir_7 
  die entsprechenden Zwischenrichtungen. Die möglichen Bewegungsrichtungen bei Kameras mit "CapPTZDirections = 32" sind dementsprechend kleinteiliger. <br><br>

  Im Gegensatz zum "set &lt;name&gt; goAbsPTZ"-Befehl startet der Befehl "set &lt;name&gt; move" eine kontinuierliche Bewegung bis ein Stop-Kommando empfangen wird. 
  Das Stop-Kommando wird nach Ablauf der optional anzugebenden Zeit [Sekunden] ausgelöst. Wird diese Laufzeit nicht angegeben, wird implizit Sekunde = 1 gesetzt. <br><br>
  
  <b>Beispiele: </b><br>
  
  <pre> 
    set &lt;name&gt; move up 0.5      : bewegt PTZ 0,5 Sek. (zzgl. Prozesszeit) nach oben
    set &lt;name&gt; move dir_1 1.5   : bewegt PTZ 1,5 Sek. (zzgl. Prozesszeit) nach rechts-oben 
    set &lt;name&gt; move dir_20 0.7  : bewegt PTZ 1,5 Sek. (zzgl. Prozesszeit) nach links-unten ("CapPTZDirections = 32)"
  </pre>
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; [on [&lt;rectime&gt;] | off] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li><br>

  Der Befehl "set &lt;name&gt; on" startet eine Aufnahme. Die Standardaufnahmedauer beträgt 15 Sekunden. Sie kann mit dem 
  Attribut "rectime" individuell festgelegt werden. 
  Die im Attribut (bzw. im Standard) hinterlegte Aufnahmedauer kann einmalig mit "set &lt;name&gt; on &lt;rectime&gt;" 
  überschrieben werden.
  Die Aufnahme stoppt automatisch nach Ablauf der Zeit "rectime".<br>

  Ein Sonderfall ist der Start einer Daueraufnahme mit "set &lt;name&gt; on 0" bzw. dem Attributwert "rectime = 0". 
  In diesem Fall wird eine Daueraufnahme gestartet, die explizit wieder mit dem Befehl "set &lt;name&gt; off" gestoppt 
  werden muß.<br>

  Das Aufnahmeverhalten kann weiterhin mit dem Attribut "recextend" beeinflusst werden.<br><br>

  <b>Attribut "recextend = 0" bzw. nicht gesetzt (Standard):</b><br><br>
  <ul>
  <li> wird eine Aufnahme mit z.B. rectime=22 gestartet, wird kein weiterer Startbefehl für eine Aufnahme akzeptiert bis diese gestartete Aufnahme nach 22 Sekunden
  beendet ist. Ein Hinweis wird bei verbose=3 im Logfile protokolliert. </li>
  </ul>
  <br>

  <b>Attribut "recextend = 1" gesetzt:</b><br>
  <ul>
  <li> eine zuvor gestartete Aufnahme wird bei einem erneuten "set <name> on" -Befehl um die Aufnahmezeit "rectime" verlängert. Das bedeutet, dass der Timer für 
  den automatischen Stop auf den Wert "rectime" neu gesetzt wird. Dieser Vorgang wiederholt sich mit jedem Start-Befehl. Dadurch verlängert sich eine laufende 
  Aufnahme bis kein Start-Inpuls mehr registriert wird. </li>

  <li> eine zuvor gestartete Endlos-Aufnahme wird mit einem erneuten "set <name> on"-Befehl nach der Aufnahmezeit "rectime" gestoppt (Timerneustart). Ist dies 
  nicht gewünscht, ist darauf zu achten dass bei der Verwendung einer Endlos-Aufnahme das Attribut "recextend" nicht verwendet wird. </li>
  </ul>
  <br>
  
  Beispiele für einfachen <b>Start/Stop einer Aufnahme</b>: <br><br>

  <table>
  <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td>set &lt;name&gt; on [rectime]  </td><td>startet die Aufnahme der Kamera &lt;name&gt;, automatischer Stop der Aufnahme nach Ablauf der Zeit [rectime] (default 15s oder wie im <a href="#SSCamattr">Attribut</a> "rectime" angegeben)</td></tr>
      <tr><td>set &lt;name&gt; off   </td><td>stoppt die Aufnahme der Kamera &lt;name&gt;</td></tr>
  </table>
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; optimizeParams [mirror:&lt;value&gt;] [flip:&lt;value&gt;] [rotate:&lt;value&gt;] [ntp:&lt;value&gt;]</b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Setzt eine oder mehrere Eigenschaften für die Kamera. Das Video kann gespiegelt (mirror), auf den Kopf gestellt (flip) oder 
  gedreht (rotate) werden. Die jeweiligen Eigenschaften müssen von der Kamera unterstützt werden. Mit "ntp" wird der Zeitserver 
  eingestellt den die Kamera zur Zeitsynchronisation verwendet. <br><br>
  
  &lt;value&gt; kann sein für: <br>
    <ul>
    <li> <b>mirror, flip, rotate: </b> true | false  </li>
	<li> <b>ntp: </b> der Name oder die IP-Adresse des Zeitservers </li> 
	</ul>
	<br><br>
	
  <b>Beispiele:</b> <br>
  <code> set &lt;name&gt; optimizeParams mirror:true flip:true ntp:time.windows.com </code><br>
  # Das Bild wird gespiegelt, auf den Kopf gestellt und der Zeitserver auf "time.windows.com" eingestellt.<br>
  <code> set &lt;name&gt; optimizeParams ntp:Surveillance%20Station </code><br>
  # Die Surveillance Station wird als Zeitserver eingestellt. (NTP-Dienst muss im DSM aktiviert sein) <br>
  <code> set &lt;name&gt; optimizeParams mirror:true flip:false rotate:true </code><br>
  # Das Bild wird gespiegelt und um 90 Grad gedreht. <br>
    
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; runPatrol &lt;Patrolname&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Dieses Kommando startet die vordefinierterte Überwachungstour einer PTZ-Kamera. <br>
  Die Überwachungstouren müssen dazu zunächst in der Synology Surveillance Station angelegt worden sein. 
  Das geschieht in der PTZ-Steuerung im IP-Kamera Setup -&gt; PTZ-Steuerung -&gt; Überwachung.
  Die Überwachungstouren (Patrols) werden über das Kommando "get &lt;name&gt; caminfoall" eingelesen, welches beim Restart von FHEM automatisch abgearbeitet wird. 
  Der Einlesevorgang kann durch ein Kamerapolling regelmäßig wiederholt werden. Ein langes Pollingintervall ist in diesem Fall empfehlenswert, da sich die 
  Überwachungstouren nur im Fall der Neuanlage bzw. Änderung verändern werden.
  Nähere Informationen zur Anlage von Überwachungstouren sind in der Hilfe zur Surveillance Station enthalten. 
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; runView [live_fw | live_fw_hls | live_link | live_open [&lt;room&gt;] | lastrec_fw | lastrec_fw_MJPEG | lastrec_fw_MPEG4/H.264 | lastrec_open [&lt;room&gt;] | lastsnap_fw]  </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  <ul>
  <table>
  <colgroup> <col width=25%> <col width=75%> </colgroup>
      <tr><td>live_fw                     </td><td>- MJPEG-LiveStream. Audiowiedergabe wird mit angeboten wenn verfügbar. </td></tr>
      <tr><td>live_fw_hls                 </td><td>- HLS-LiveStream (aktuell nur Mac Safari und mobile iOS/Android-Geräte) </td></tr>
      <tr><td>live_link                   </td><td>- Link zu einem MJPEG-Livestream </td></tr>
      <tr><td>live_open [&lt;room&gt;]    </td><td>- öffnet MJPEG-Stream in separatem Browser-Fenster </td></tr>
      <tr><td>lastrec_fw                  </td><td>- letzte Aufnahme als iFrame Objekt </td></tr>
      <tr><td>lastrec_fw_MJPEG            </td><td>- nutzbar wenn Aufnahme im Format MJPEG vorliegt </td></tr>
      <tr><td>lastrec_fw_MPEG4/H.264      </td><td>- nutzbar wenn Aufnahme im Format MPEG4/H.264 vorliegt </td></tr>
      <tr><td>lastrec_open [&lt;room&gt;] </td><td>- letzte Aufnahme wird in separatem Browser-Fenster geöffnet </td></tr>
      <tr><td>lastsnap_fw                 </td><td>- letzter Schnappschuss wird dargestellt </td></tr>
  </table>
  </ul>
  <br><br>
  
  Mit <b>"live_fw, live_link, live_open"</b> wird ein MJPEG-Livestream, entweder als eingebettetes Image 
  oder als generierter Link, gestartet. <br>
  Der Befehl <b>"live_open"</b> öffnet ein separates Browserfenster mit dem MJPEG-Livestream. Wird dabei optional der Raum mit
  angegeben, wird das Browserfenster nur dann gestartet, wenn dieser Raum aktuell im Browser geöffnet ist. <br>
  Soll mit <b>"live_fw_hls"</b> ein HLS-Stream verwendet werden, muss die Kamera in der Synology Surveillance Station auf
  das Videoformat H.264 (nicht MJPEG) eingestellt sein. Diese Möglichkeit wird deshalb nur dann angeboten wenn das Reading 
  "CamStreamFormat" den Wert "HLS" hat.
  <br><br> 
    
  Der Zugriff auf die letzte Aufnahme einer Kamera kann über die Optionen <b>"lastrec_fw.*"</b> bzw. <b>"lastrec_open"</b> erfolgen.
  Bei Verwendung von <b>"lastrec_fw.*"</b> wird die letzte Aufnahme als eingebettetes iFrame-Objekt abgespielt. Es werden entsprechende
  Steuerungselemente zur Wiedergabegeschwindigkeit usw. angeboten wenn verfügbar. <br><br>
  
  Der Befehl <b>"set &lt;name&gt; runView lastsnap_fw"</b> zeigt den letzten Schnappschuss der Kamera eingebettet an. <br>
  Durch Angabe des optionalen Raumes bei <b>"lastrec_open"</b> erfolgt die gleiche Einschränkung wie bei "live_open". <br>
  Die Gestaltung der Fenster im FHEMWEB kann durch HTML-Tags im <a href="#SSCamattr">Attribut</a> "htmlattr" beeinflusst werden. 
  <br><br>
  
  <b>Beispiel:</b><br>
  <pre>
    attr &lt;name&gt; htmlattr width="500" height="375"
    attr &lt;name&gt; htmlattr width="500" height="375" top="200" left="300"
  </pre>
    
  Wird der Stream als live_fw gestartet, ändert sich die Größe entsprechend der Angaben von Width und Hight. <br>
  Das Kommando <b>"set &lt;name&gt; runView live_open"</b> startet den Livestreamlink sofort in einem neuen 
  Browserfenster. 
  Dabei wird für jede aktive FHEMWEB-Session eine Fensteröffnung initiiert. Soll dieses Verhalten geändert werden, kann 
  <b>"set &lt;name&gt; runView live_open &lt;room&gt;"</b> verwendet werden um das Öffnen des Browserfensters in einem 
  beliebigen, in einer FHEMWEB-Session aktiven Raum "&lt;room&gt;", zu initiieren.<br>
  Das gesetzte <a href="#SSCamattr">Attribut</a> "livestreamprefix" überschreibt im <a href="#SSCamreadings">Reading</a> "LiveStreamUrl" 
  die Angaben für Protokoll, Servername und Port. Damit kann z.B. die LiveStreamUrl für den Versand und externen Zugriff 
  auf die SVS modifiziert werden. <br><br>
  
  <b>Beispiel:</b><br>
  <pre>
    attr &lt;name&gt; livestreamprefix https://&lt;Servername&gt;:&lt;Port&gt;
  </pre>
  
  Der Livestream wird über das Kommando <b>"set &lt;name&gt; stopView"</b> wieder beendet. <br>
  Die "runView" Funktion schaltet ebenfalls Streaming-Devices vom Typ "switched" in den entsprechenden Modus. <br><br>
  
  <b>Hinweis zu HLS (HTTP Live Streaming):</b> <br>
  Das Video startet mit einer technologisch bedingten Verzögerung. Jeder Stream wird in eine Reihe sehr kleiner Videodateien 
  (mit etwa 10 Sekunden Länge) segmentiert und an den Client ausgeliefert. 
  Die Kamera muss in der SVS auf das Videoformat H.264 eingestellt sein und nicht jeder Kameratyp ist gleichermassen für 
  HLS-Streaming geeignet.
  Momentan kann HLS nur durch den Mac Safari Browser sowie auf mobilen iOS/Android-Geräten wiedergegeben werden.
    
  </ul>
  <br><br>
  
  
  <ul>
  <li><b> set &lt;name&gt; setHome &lt;PresetName&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für PTZ-CAM)</li> <br>
  
  Setzt die Home-Position der Kamera auf einen vordefinierten Preset "&lt;PresetName&gt;" oder auf die aktuell angefahrene 
  Position.

  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; setPreset &lt;PresetNummer&gt; [&lt;PresetName&gt;] [&lt;Speed&gt;] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für PTZ-CAM)</li> <br>
  
  Setzt einen Preset mit dem Namen "&lt;PresetName&gt;" auf die aktuell angefahrene Position der Kamera. Optional kann die
  Geschwindigkeit angegeben werden (&lt;Speed&gt;). Ist kein PresetName angegeben, wird die PresetNummer als Name verwendet.
  Aus diesem Grund ist &lt;PresetName&gt; optional definiert, sollte jedoch im Normalfall gesetzt werden.

  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; snap </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Ein <b>Schnappschuß</b> kann ausgelöst werden mit:
  <pre> 
     set &lt;name&gt; snap 
  </pre>
  
  Nachfolgend einige Beispiele für die <b>Auslösung von Schnappschüssen</b>. <br><br>
  
  Soll eine Reihe von Schnappschüssen ausgelöst werden wenn eine Aufnahme startet, kann das z.B. durch folgendes notify geschehen. <br>
  Sobald der Start der Kamera CamHE1 ausgelöst wird (Attribut event-on-change-reading -> "Record" setzen), werden abhängig davon 3 Snapshots im Abstand von 2 Sekunden getriggert.

  <pre>
     define he1_snap_3 notify CamHE1:Record.*Start define h3 at +*{3}00:00:02 set CamHE1 snap
  </pre>
  
  Triggern von 2 Schnappschüssen der Kamera "CamHE1" im Abstand von 6 Sekunden nachdem der Bewegungsmelder "MelderHE1" einen Event gesendet hat, <br>
  kann z.B. mit folgendem notify geschehen:

  <pre>
     define he1_snap_2 notify MelderHE1:on.* define h2 at +*{2}00:00:06 set CamHE1 snap 
  </pre>

  Es wird die ID und der Filename des letzten Snapshots als Wert der Variable "LastSnapId" bzw. "LastSnapFilename" in den Readings der Kamera ausgegeben. <br><br>
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; snapGallery [1-10] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Der Befehl ist nur vorhanden wenn das Attribut "snapGalleryBoost=1" gesetzt wurde.
  Er erzeugt eine Ausgabe der letzten [x] Schnappschüsse ebenso wie <a href="#SSCamget">"get &lt;name&gt; snapGallery"</a>.  Abweichend von "get" wird mit Attribut
  <a href="#SSCamattr">Attribut</a> "snapGalleryBoost=1" kein Popup erzeugt, sondern die Schnappschußgalerie als Browserseite
  dargestellt. Alle weiteren Funktionen und Attribute entsprechen dem "get &lt;name&gt; snapGallery" Kommando. <br>
  Wenn die Ausgabe einer Schnappschußgalerie, z.B. über ein "at oder "notify", getriggert wird, sollte besser das  
  <a href="#SSCamget">"get &lt;name&gt; snapGallery"</a> Kommando anstatt "set" verwendet werden.
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; startTracking </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM mit Tracking Fähigkeit)</li> <br>
  
  Startet Objekt Tracking der Kamera.
  Der Befehl ist nur vorhanden wenn die Surveillance Station die Fähigkeit der Kamera zum Objekt Tracking erkannt hat
  (Reading "CapPTZObjTracking").
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; stopTracking </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM mit Tracking Fähigkeit)</li> <br>
  
  Stoppt Objekt Tracking der Kamera.
  Der Befehl ist nur vorhanden wenn die Surveillance Station die Fähigkeit der Kamera zum Objekt Tracking erkannt hat
  (Reading "CapPTZObjTracking").
  </ul>
  <br><br>

  </ul>
  <br>

<a name="SSCamget"></a>
<b>Get</b>
 <ul>
  <br>
  Mit SSCam können die Eigenschaften der Surveillance Station und der Kameras abgefragt werden. <br>
  Die aufgeführten get-Befehle sind für CAM/SVS-Devices oder nur für CAM-Devices bzw. nur für SVS-Devices gültig. Sie stehen im 
  Drop-Down-Menü des jeweiligen Devices zur Auswahl zur Verfügung. <br><br>
  
  <ul>
  <li><b> get &lt;name&gt; caminfoall </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM/SVS)</li>
      <b> get &lt;name&gt; caminfo </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM) <br><br>
  
  Es werden SVS-Parameter und abhängig von der Art der Kamera (z.B. Fix- oder PTZ-Kamera) die verfügbaren Kamera-Eigenschaften 
  ermittelt und als Readings zur Verfügung gestellt. <br>
  So wird zum Beispiel das Reading "Availability" auf "disconnected" gesetzt falls die Kamera von der Surveillance Station 
  getrennt ist. <br>
  "getcaminfo" ruft eine Teilmenge von "getcaminfoall" ab.
  </ul>
  <br><br> 
  
  <ul>
  <li><b> get &lt;name&gt; eventlist </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Es wird das <a href="#SSCamreadings">Reading</a> "CamEventNum" und "CamLastRec" 
  aktualisiert, welches die Gesamtanzahl der registrierten Kameraevents und den Pfad / Namen der letzten Aufnahme enthält.
  Dieser Befehl wird implizit mit "get &lt;name&gt; caminfoall" ausgeführt. <br>
  Mit dem <a href="#SSCamattr">Attribut</a> "videofolderMap" kann der Inhalt des Readings "VideoFolder" überschrieben werden. 
  Dies kann von Vortel sein wenn das Surveillance-Verzeichnis der SVS an dem lokalen PC unter anderem Pfadnamen gemountet ist 
  und darüber der Zugriff auf die Aufnahmen erfolgen soll (z.B. Verwendung bei Email-Versand). <br><br>
  
  Ein DOIF-Beispiel für den Email-Versand von Snapshot und Aufnahmelink per non-blocking sendmail:
  <pre>
     define CamHE1.snap.email DOIF ([CamHE1:"LastSnapFilename"]) 
     ({DebianMailnbl ('Recipient@Domain','Bewegungsalarm CamHE1','Eine Bewegung wurde an der Haustür registriert. Aufnahmelink: \  
     \[CamHE1:VideoFolder]\[CamHE1:CamLastRec]','/media/sf_surveillance/@Snapshot/[CamHE1:LastSnapFilename]')})
  </pre>
  </ul>
  
  <ul>
  <li><b> get &lt;name&gt; homeModeState </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für SVS)</li> <br>
  
  HomeMode-Status der Surveillance Station wird abgerufen.  
  </ul>
  <br><br> 
  
  <ul>
  <li><b> get &lt;name&gt; listLog [severity:&lt;Loglevel&gt;] [limit:&lt;Zeilenzahl&gt;] [match:&lt;Suchstring&gt;] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für SVS)</li> <br>
  
  Ruft das Surveillance Station Log vom Synology Server ab. Ohne Angabe der optionalen Zusätze wird das gesamte Log abgerufen. <br>
  Es können alle oder eine Auswahl der folgenden Optionen angegeben werden: <br><br>
  
  <ul>
  <li> &lt;Loglevel&gt; - Information, Warning oder Error. Nur Sätze mit dem Schweregrad werden abgerufen (default: alle) </li>
  <li> &lt;Zeilenzahl&gt; - die angegebene Anzahl der Logzeilen (neueste) wird abgerufen (default: alle) </li>
  <li> &lt;Suchstring&gt; - nur Logeinträge mit dem angegeben String werden abgerufen (Achtung: kein Regex, der Suchstring wird im Call an die SVS mitgegeben) </li>
  </ul>
  <br>
  
  <b>Beispiele</b> <br>
  <ul>
  <code>get &lt;name&gt; listLog severity:Error limit:5 </code> <br>
  Zeigt die letzten 5 Logeinträge mit dem Schweregrad "Error" <br>  
  <code>get &lt;name&gt; listLog severity:Information match:Carport </code> <br>
  Zeigt alle Logeinträge mit dem Schweregrad "Information" die den String "Carport" enthalten <br>  
  <code>get &lt;name&gt; listLog severity:Warning </code> <br>
  Zeigt alle Logeinträge mit dem Schweregrad "Warning" <br><br>
  </ul>
  
  
  Wurde mit dem <a href="#SSCamattr">Attribut</a> "pollcaminfoall" das Polling der SVS aktiviert, wird das <a href="#SSCamreadings">Reading</a> 
  "LastLogEntry" erstellt. <br>
  Im Protokoll-Setup der SVS kann man einstellen was protokolliert werden soll. Für weitere Informationen 
  siehe <a href="https://www.synology.com/de-de/knowledgebase/Surveillance/help/SurveillanceStation/log_advanced">Synology Online-Hlfe</a>.
  </ul>
  <br><br> 
  
  <ul>
  <li><b> get &lt;name&gt; listPresets </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für PTZ-CAM)</li> <br>
  
  Die für die Kamera gespeicherten Presets werden in einem Popup ausgegeben.
  </ul>
  <br><br> 
  
  <ul>
  <li><b> get &lt;name&gt; scanVirgin </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM/SVS)</li> <br>
  
  Wie mit get caminfoall werden alle Informationen der SVS und Kamera abgerufen. Allerdings wird in jedem Fall eine 
  neue Session ID generiert (neues Login), die Kamera-ID neu ermittelt und es werden alle notwendigen API-Parameter neu 
  eingelesen.  
  </ul>
  <br><br> 
  
  <ul>
  <li><b> get &lt;name&gt; snapGallery [1-10] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Es wird ein Popup mit den letzten [x] Schnapschüssen erzeugt. Ist das <a href="#SSCamattr">Attribut</a> "snapGalleryBoost" gesetzt, 
  werden die letzten Schnappschüsse (default 3) über Polling abgefragt und im Speicher gehalten. Das Verfahren hilft die Ausgabe zu beschleunigen,
  kann aber möglicherweise nicht den letzten Schnappschuß anzeigen, falls dieser NICHT über das Modul ausgelöst wurde. <br>
  Diese Funktion kann ebenfalls, z.B. mit "at" oder "notify", getriggert werden. Dabei wird die Schnappschußgalerie auf allen 
  verbundenen FHEMWEB-Instanzen als Popup angezeigt. <br><br>
  
  Zur weiteren Steuerung dieser Funktion stehen die <a href="#SSCamattr">Attribute</a>: <br><br>
  
  <ul>
     <li>snapGalleryBoost   </li> 
	 <li>snapGalleryColumns   </li> 
	 <li>snapGalleryHtmlAttr   </li> 
	 <li>snapGalleryNumber   </li> 
	 <li>snapGallerySize   </li> 
  </ul> <br>
  zur Verfügung.
  </ul> <br>
  
        <ul>
		<b>Hinweis:</b><br>
        Abhängig von der Anzahl und Auflösung (Qualität) der Schnappschuß-Images werden entsprechend ausreichende CPU und/oder
		RAM-Ressourcen benötigt.
        </ul>
		<br><br>
  
  <ul>
  <li><b> get &lt;name&gt; snapfileinfo </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Es wird der Filename des letzten Schnapschusses ermittelt. Der Befehl wird implizit mit <b>"get &lt;name&gt; snap"</b> 
  ausgeführt.
  </ul>
  <br><br> 
  
  <ul>
  <li><b> get &lt;name&gt; snapinfo </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Es werden Schnappschussinformationen gelesen. Hilfreich wenn Schnappschüsse nicht durch SSCam, sondern durch die Bewegungserkennung der Kamera 
  oder Surveillance Station erzeugt werden.
  </ul>
  <br><br> 
  
  <ul>
  <li><b> get &lt;name&gt; stmUrlPath </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Mit diesem Kommando wird der aktuelle Streamkey der Kamera abgerufen und das Reading mit dem Key-Wert gefüllt. 
  Dieser Streamkey kann verwendet werden um eigene Aufrufe eines Livestreams aufzubauen (siehe Beispiel).
  Wenn das <a href="#SSCamattr">Attribut</a> "showStmInfoFull" gesetzt ist, werden zusaätzliche Stream-Informationen wie "StmKeyUnicst", "StmKeymjpegHttp" ausgegeben.
  Diese Readings enthalten die gültigen Stream-Pfade zu einem Livestream und können z.B. versendet und von einer entsprechenden Anwendung ohne session Id geöffnet werden. 
  Wenn das Attribut "livestreamprefix" (Format: "http(s)://&lt;hostname&gt;&lt;port&gt;) gesetzt ist, wird der Servername und Port überschrieben soweit es sinnvoll ist.
  Wird Polling der Kameraeigenschaften genutzt, wird die stmUrlPath-Funktion automatisch mit ausgeführt.
  <br><br>
  
  Beispiel für den Aufbau eines Http-Calls zu einem Livestream mit StmKey: 
  
  <pre>
http(s)://&lt;hostname&gt;&lt;port&gt;/webapi/entry.cgi?api=SYNO.SurveillanceStation.VideoStreaming&version=1&method=Stream&format=mjpeg&cameraId=5&StmKey="31fd87279976d89bb98409728cced890"
  </pre>
  
  cameraId (Internal CAMID), StmKey müssen durch gültige Werte ersetzt werden. <br><br>
  
  <b>Hinweis:</b> <br>
  
  Falls der Stream-Aufruf versendet und von extern genutzt wird sowie hostname / port durch gültige Werte ersetzt und die 
  Routerports entsprechend geöffnet werden, ist darauf zu achten, dass diese sensiblen Daten nicht durch unauthorisierte Personen 
  für den Zugriff genutzt werden können !

  </ul>
  <br><br>
  
  <ul>
  <li><b> get &lt;name&gt; storedCredentials </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM/SVS)</li> <br>
  
  Die gespeicherten Anmeldeinformationen (Credentials) werden in einem Popup als Klartext angezeigt.
  </ul>
  <br><br> 
  
  <ul>
  <li><b> get &lt;name&gt; svsinfo </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM/SVS)</li> <br>
  
  Ermittelt allgemeine Informationen zur installierten SVS-Version und andere Eigenschaften. <br>
  </ul>
  <br><br> 
  
  </ul>
  <br><br>

  <b>Polling der Kamera/SVS-Eigenschaften:</b><br><br>

  Die Abfrage der Kameraeigenschaften erfolgt automatisch, wenn das Attribut "pollcaminfoall" (siehe Attribute) mit einem Wert &gt; 10 gesetzt wird. <br>
  Per Default ist das Attribut "pollcaminfoall" nicht gesetzt und das automatische Polling nicht aktiv. <br>
  Der Wert dieses Attributes legt das Intervall der Abfrage in Sekunden fest. Ist das Attribut nicht gesetzt oder &lt; 10 wird kein automatisches Polling <br>
  gestartet bzw. gestoppt wenn vorher der Wert &gt; 10 gesetzt war. <br><br>

  Das Attribut "pollcaminfoall" wird durch einen Watchdog-Timer überwacht. Änderungen des Attributwertes werden alle 90 Sekunden ausgewertet und entsprechend umgesetzt. <br>
  Eine Änderung des Pollingstatus / Pollingintervalls wird im FHEM-Logfile protokolliert. Diese Protokollierung kann durch Setzen des Attributes "pollnologging=1" abgeschaltet werden.<br>
  Dadurch kann ein unnötiges Anwachsen des Logs vermieden werden. Ab verbose=4 wird allerdings trotz gesetzten "pollnologging"-Attribut ein Log des Pollings <br>
  zu Analysezwecken aktiviert. <br><br>

  Wird FHEM neu gestartet, wird bei aktivierten Polling der ersten Datenabruf innerhalb 60s nach dem Start ausgeführt. <br><br>

  Der Status des automatischen Pollings wird durch das Reading "PollState" signalisiert: <br><br>
  
  <ul>
    <li><b> PollState = Active </b>    -    automatisches Polling wird mit Intervall entsprechend "pollcaminfoall" ausgeführt </li>
    <li><b> PollState = Inactive </b>  -    automatisches Polling wird nicht ausgeführt </li>
  </ul>
  <br>
 
  Die Bedeutung der Readingwerte ist unter <a href="#SSCamreadings">Readings</a> beschrieben. <br><br>

  <b>Hinweise:</b> <br><br>

  Wird Polling eingesetzt, sollte das Intervall nur so kurz wie benötigt eingestellt werden da die ermittelten Werte überwiegend statisch sind. <br>
  Das eingestellte Intervall sollte nicht kleiner sein als die Summe aller HTTP-Verarbeitungszeiten.
  Pro Pollingaufruf und Kamera werden ca. 10 - 20 Http-Calls gegen die Surveillance Station abgesetzt.<br><br>
  Bei einem eingestellten HTTP-Timeout (siehe <a href="#SSCamattr">Attribut</a>) "httptimeout") von 4 Sekunden kann die theoretische Verarbeitungszeit nicht höher als 80 Sekunden betragen. <br>
  In dem Beispiel sollte man das Pollingintervall mit einem Sicherheitszuschlag auf nicht weniger 160 Sekunden setzen. <br>
  Ein praktikabler Richtwert könnte zwischen 600 - 1800 (s) liegen. <br>

  Sind mehrere Kameras in SSCam definiert, sollte "pollcaminfoall" nicht bei allen Kameras auf exakt den gleichen Wert gesetzt werden um Verarbeitungsengpässe <br>
  und dadurch versursachte potentielle Fehlerquellen bei der Abfrage der Synology Surveillance Station zu vermeiden. <br>
  Ein geringfügiger Unterschied zwischen den Pollingintervallen der definierten Kameras von z.B. 1s kann bereits als ausreichend angesehen werden. <br><br> 


<a name="SSCaminternals"></a>
<b>Internals</b> <br><br>
 <ul>
 Die Bedeutung der verwendeten Internals stellt die nachfolgende Liste dar: <br><br>
  <ul>
  <li><b>CAMID</b> - die ID der Kamera in der SVS, der Wert wird automatisch anhand des SVS-Kameranamens ermittelt. </li>
  <li><b>CAMNAME</b> - der Name der Kamera in der SVS </li>
  <li><b>CREDENTIALS</b> - der Wert ist "Set" wenn die Credentials gesetzt wurden </li>
  <li><b>MODEL</b> - Unterscheidung von Kamera-Device (Hersteller - Kameratyp) und Surveillance Station Device (SVS) </li>
  <li><b>NAME</b> - der Kameraname in FHEM </li>
  <li><b>OPMODE</b> - die zuletzt ausgeführte Operation des Moduls </li> 
  <li><b>SERVERADDR</b> - IP-Adresse des SVS Hostes </li>
  <li><b>SERVERPORT</b> - der SVS-Port </li>
  
  <br><br>
  </ul>
 </ul>


<a name="SSCamattr"></a>
<b>Attribute</b>
  <br><br>
  
  <ul>
  <ul>
  <li><b>debugactivetoken</b><br> 
    wenn gesetzt wird der Status des Active-Tokens gelogged - nur für Debugging, nicht im 
    normalen Betrieb benutzen ! </li><br>
  
  <li><b>disable</b><br>
    deaktiviert das Gerätemodul bzw. die Gerätedefinition </li><br>
  
  <li><b>httptimeout</b><br>
    Timeout-Wert für HTTP-Aufrufe zur Synology Surveillance Station, Default: 4 Sekunden (wenn 
    httptimeout = "0" oder nicht gesetzt) </li><br>
  
  <li><b>htmlattr</b><br>
  ergänzende Angaben zur Inline-Bilddarstellung um das Verhalten wie Bildgröße zu beeinflussen. <br><br> 
  
        <ul>
		<b>Beispiel:</b><br>
        attr &lt;name&gt; htmlattr width="500" height="325" top="200" left="300"
        </ul>
		<br>
        </li>
  
  <li><b>livestreamprefix</b><br>
    überschreibt die Angaben zu Protokoll, Servernamen und Port zur Weiterverwendung der 
    Livestreamadresse als z.B. externer Link. Anzugeben in der Form 
	"http(s)://&lt;servername&gt;:&lt;port&gt;"   </li><br>
  
  <li><b>loginRetries</b><br>
    setzt die Anzahl der Login-Wiederholungen im Fehlerfall (default = 1)   </li><br>
  
  <li><b>noQuotesForSID</b><br>
    dieses Attribut kann in bestimmten Fällen die Fehlermeldung "402 - permission denied" 
    vermeiden und ein login ermöglichen.  </li><br>                      
  
  <li><b>pollcaminfoall</b><br>
    Intervall der automatischen Eigenschaftsabfrage (Polling) einer Kamera (kleiner/gleich 10: kein 
    Polling, größer 10: Polling mit Intervall) </li><br>

  <li><b>pollnologging</b><br>
    "0" bzw. nicht gesetzt = Logging Gerätepolling aktiv (default), "1" = Logging 
    Gerätepolling inaktiv </li><br>
    
  <li><b>ptzPanel_Home</b><br>
    Im PTZ-Steuerungspaneel wird dem Home-Icon (im Attribut "ptzPanel_row02") automatisch der Wert des Readings 
    "PresetHome" zugewiesen.
    Mit "ptzPanel_Home" kann diese Zuweisung mit einem Preset aus der verfügbaren Preset-Liste geändert werden. </li><br> 
    
  <li><b>ptzPanel_iconPath</b><br>
    Pfad für Icons im PTZ-Steuerungspaneel, default ist "www/images/sscam". 
    Der Attribut-Wert wird für alle Icon-Dateien außer *.svg verwendet. </li><br> 

  <li><b>ptzPanel_iconPrefix</b><br>
    Prefix für Icon-Dateien im PTZ-Steuerungspaneel, default ist "black_btn_". 
    Der Attribut-Wert wird für alle Icon-Dateien außer *.svg verwendet. <br>
    Beginnen die verwendeten Icon-Dateien z.B. mit "black_btn_" ("black_btn_CAMDOWN.png"), braucht das Icon in den
    Attributen "ptzPanel_row[00-09]" nur noch mit dem darauf folgenden Teilstring, z.B. "CAMDOWN.png" benannt zu werden.
    </li><br>    

  <li><b>ptzPanel_row[00-09] &lt;command&gt;:&lt;icon&gt;,&lt;command&gt;:&lt;icon&gt;,... </b><br>
    Für PTZ-Kameras werden automatisch die Attribute "ptzPanel_row00" bis "ptzPanel_row04" zur Verwendung im
    PTZ-Steuerungspaneel angelegt. <br>
    Die Attribute enthalten eine Komma-separarierte Liste von Befehl:Icon-Kombinationen (Tasten) je Paneelzeile. 
    Eine Paneelzeile kann beliebig viele Tasten enthalten. Die Attribute "ptzPanel_row00" bis "ptzPanel_row04" können nicht
    gelöscht werden da sie in diesem Fall automatisch wieder angelegt werden. Der User kann die Attribute ändern und ergänzen.
    Diese Änderungen bleiben erhalten. <br>
    Bei Bedarf kann die Belegung der Home-Taste in "ptzPanel_row02" geändert werden mit dem Attribut "ptzPanel_Home". <br>
    Die Icons werden im Pfad "ptzPanel_iconPath" gesucht. Dem Icon-Namen wird "ptzPanel_iconPrefix" vorangestellt.
    Eigene Erweiterungen des PTZ-Steuerungspaneels können über die Attribute "ptzPanel_row05" bis "ptzPanel_row09" 
    vorgenommen werden. Zur Erstellung eigener Icons gibt es eine Vorlage im SVN: 
    <a href="https://svn.fhem.de/trac/browser/trunk/fhem/contrib/sscam">contrib/sscam/black_btn_CAM_Template.pdn</a>. Diese
    Vorlage kann zum Beispiel mit Paint.Net bearbeitet werden.    <br><br>
    
    <b>Hinweis</b> <br>
    Für eine Leerfeld verwenden sie bitte ":CAMBLANK.png" bzw. ":CAMBLANK.png,:CAMBLANK.png,:CAMBLANK.png,..." für eine 
    Leerzeile.
    <br><br>
    
        <ul>
		<b>Beispiel:</b><br>
        attr &lt;name&gt; ptzPanel_row00 move upleft:CAMUPLEFTFAST.png,:CAMBLANK.png,move up:CAMUPFAST.png,:CAMBLANK.png,move upright:CAMUPRIGHTFAST.png <br>
        # Der Befehl "move upleft" wird der Kamera beim Druck auf Tastenicon "CAMUPLEFTFAST.png" übermittelt.  <br>
        </ul>
		<br>
    </li><br>  

  <li><b>ptzPanel_use</b><br>
    Die Anzeige des PTZ-Steuerungspaneels in der Detailanzeige bzw. innerhalb eines generierten Streamdevice wird 
    ein- bzw. ausgeschaltet (default ein). </li><br>    
    
  <li><b>rectime</b><br>
    festgelegte Aufnahmezeit wenn eine Aufnahme gestartet wird. Mit rectime = 0 wird eine 
    Endlosaufnahme gestartet. Ist "rectime" nicht gesetzt, wird der Defaultwert von 15s 
	verwendet.</li><br>
  
  <li><b>recextend</b><br>
    "rectime" einer gestarteten Aufnahme wird neu gesetzt. Dadurch verlängert sich die 
    Aufnahemzeit einer laufenden Aufnahme </li><br>
  
  <li><b>session</b><br>
    Auswahl der Login-Session. Nicht gesetzt oder "DSM" -> session wird mit DSM aufgebaut 
    (Standard). "SurveillanceStation" -> Session-Aufbau erfolgt mit SVS </li><br>
  
  <li><b>simu_SVSversion</b><br>
    Simuliert eine andere SVS-Version. (es ist nur eine niedrigere als die installierte SVS 
    Version möglich !) </li><br>
	
  <li><b>snapGalleryBoost</b><br>
    Wenn gesetzt, werden die letzten Schnappschüsse (default 3) über Polling im Speicher gehalten und mit "set/get snapGallery" 
	aufbereitet angezeigt. Dieser Modus bietet sich an wenn viele bzw. Fullsize Images angezeigt werden sollen. 
	Ist das Attribut eingeschaltet, können bei "set/get snapGallery" keine Argumente mehr mitgegeben werden. 
    (siehe Attribut "snapGalleryNumber") </li><br>
  
  <li><b>snapGalleryColumns</b><br>
    Die Anzahl der Snaps die in einer Reihe im Popup erscheinen sollen (default 3). </li><br>
	
  <li><b>snapGalleryHtmlAttr</b><br>
    hiermit kann die Bilddarstellung beeinflusst werden. <br>
	Ist das Attribut nicht gesetzt, wird das Attribut "htmlattr" verwendet. <br>
	Ist auch dieses nicht gesetzt, wird eine Standardvorgabe verwendet (width="500" height="325"). <br><br>
	
        <ul>
		<b>Beispiel:</b><br>
        attr &lt;name&gt; snapGalleryHtmlAttr width="325" height="225"
        </ul>
		<br>
        </li>
		
  <li><b>snapGalleryNumber</b><br>
    Die Anzahl der abzurufenden Schnappschüsse (default 3). </li><br>
	
  <li><b>snapGallerySize</b><br>
     Mit diesem Attribut kann die Qualität der Images eingestellt werden (default "Icon"). <br>
	 Im Modus "Full" wird die original vorhandene Auflösung der Images abgerufen. Dies erfordert mehr Ressourcen und kann die 
	 Anzeige verlangsamen. Mit "snapGalleryBoost=1" kann die Ausgabe beschleunigt werden, da in diesem Fall die Aufnahmen über 
	 Polling abgerufen und nur noch zur Anzeige gebracht werden. </li><br>
	
  <li><b>showStmInfoFull</b><br>
    zusaätzliche Streaminformationen wie LiveStreamUrl, StmKeyUnicst, StmKeymjpegHttp werden 
    ausgegeben</li><br>
  
  <li><b>showPassInLog</b><br>
    wenn gesetzt wird das verwendete Passwort im Logfile (verbose 4) angezeigt. 
    (default = 0) </li><br>
  
  <li><b>videofolderMap</b><br>
    ersetzt den Inhalt des Readings "VideoFolder", Verwendung z.B. bei gemounteten 
    Verzeichnissen </li><br>
  
  <li><b>verbose</b> </li><br>
  
  <ul>
   Es werden verschiedene Verbose-Level unterstützt.
   Dies sind im Einzelnen:
   
    <table>  
    <colgroup> <col width=5%> <col width=95%> </colgroup>
      <tr><td> 0  </td><td>- Start/Stop-Ereignisse werden geloggt </td></tr>
      <tr><td> 1  </td><td>- Fehlermeldungen werden geloggt </td></tr>
      <tr><td> 2  </td><td>- Meldungen über wichtige Ereignisse oder Alarme </td></tr>
      <tr><td> 3  </td><td>- gesendete Kommandos werden geloggt </td></tr>
      <tr><td> 4  </td><td>- gesendete und empfangene Daten werden geloggt </td></tr>
      <tr><td> 5  </td><td>- alle Ausgaben zur Fehleranalyse werden geloggt. <b>ACHTUNG:</b> möglicherweise werden sehr viele Daten in das Logfile geschrieben! </td></tr>
    </table>
   </ul>     
   <br>
   <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   <br><br>
  </ul>

<a name="SSCamreadings"></a>
<b>Readings</b>
 <ul>
  <br>
  Über den Pollingmechanismus bzw. durch Abfrage mit "Get" werden Readings bereitgestellt, deren Bedeutung in der nachfolgenden Tabelle dargestellt sind. <br>
  Die übermittelten Readings können in Abhängigkeit des Kameratyps variieren.<br><br>
  <ul>
  <table>  
  <colgroup> <col width=5%> <col width=95%> </colgroup>
    <tr><td><li>CamAudioType</li>       </td><td>- listet den eingestellten Audiocodec auf wenn verwendet  </td></tr>
    <tr><td><li>Availability</li>       </td><td>- Verfügbarkeit der Kamera (disabled, enabled, disconnected, other)  </td></tr>
    <tr><td><li>CamEventNum</li>        </td><td>- liefert die Gesamtanzahl der in SVS registrierten Events der Kamera  </td></tr>
    <tr><td><li>CamExposureControl</li> </td><td>- zeigt den aktuell eingestellten Typ der Belichtungssteuerung  </td></tr>
    <tr><td><li>CamExposureMode</li>    </td><td>- aktueller Belichtungsmodus (Day, Night, Auto, Schedule, Unknown)  </td></tr>
    <tr><td><li>CamForceEnableMulticast</li> </td><td>- sagt aus ob die Kamera verpflichet ist Multicast einzuschalten.  </td></tr>
    <tr><td><li>CamIP</li>              </td><td>- IP-Adresse der Kamera  </td></tr>
    <tr><td><li>CamLastRec</li>         </td><td>- Pfad / Name der letzten Aufnahme   </td></tr>
    <tr><td><li>CamLastRecTime</li>     </td><td>- Datum / Startzeit - Stopzeit der letzten Aufnahme   </td></tr>
    <tr><td><li>CamLiveMode</li>        </td><td>- Quelle für Live-Ansicht (DS, Camera)  </td></tr>
    <tr><td><li>CamModel</li>           </td><td>- Kameramodell  </td></tr>
    <tr><td><li>CamMotDetSc</li>        </td><td>- Status der Bewegungserkennung (disabled, durch Kamera, durch SVS) und deren Parameter </td></tr>
    <tr><td><li>CamNTPServer</li>       </td><td>- eingestellter Zeitserver  </td></tr>
    <tr><td><li>CamPort</li>            </td><td>- IP-Port der Kamera  </td></tr>
    <tr><td><li>CamPreRecTime</li>      </td><td>- Dauer der der Voraufzeichnung in Sekunden (Einstellung in SVS)  </td></tr>
    <tr><td><li>CamRecShare</li>        </td><td>- gemeinsamer Ordner auf der DS für Aufnahmen  </td></tr>
    <tr><td><li>CamRecVolume</li>       </td><td>- Volume auf der DS für Aufnahmen  </td></tr>
    <tr><td><li>CamStreamFormat</li>    </td><td>- aktuelles Format des Videostream  </td></tr>
    <tr><td><li>CamVideoType</li>       </td><td>- listet den eingestellten Videocodec auf </td></tr>
    <tr><td><li>CamVendor</li>          </td><td>- Kamerahersteller Bezeichnung  </td></tr>
    <tr><td><li>CamVideoFlip</li>       </td><td>- Ist das Video gedreht  </td></tr>
    <tr><td><li>CamVideoMirror</li>     </td><td>- Ist das Video gespiegelt  </td></tr>
	<tr><td><li>CamVideoRotate</li>     </td><td>- Ist das Video gedreht  </td></tr>
    <tr><td><li>CapAudioOut</li>        </td><td>- Fähigkeit der Kamera zur Audioausgabe über Surveillance Station (false/true)  </td></tr>
    <tr><td><li>CapChangeSpeed</li>     </td><td>- Fähigkeit der Kamera verschiedene Bewegungsgeschwindigkeiten auszuführen  </td></tr>
    <tr><td><li>CapPTZAbs</li>          </td><td>- Fähigkeit der Kamera für absolute PTZ-Aktionen   </td></tr>
    <tr><td><li>CapPTZAutoFocus</li>    </td><td>- Fähigkeit der Kamera für Autofokus Aktionen  </td></tr>
    <tr><td><li>CapPTZDirections</li>   </td><td>- die verfügbaren PTZ-Richtungen der Kamera  </td></tr>
    <tr><td><li>CapPTZFocus</li>        </td><td>- Art der Kameraunterstützung für Fokussierung  </td></tr>
    <tr><td><li>CapPTZHome</li>         </td><td>- Unterstützung der Kamera für Home-Position  </td></tr>
    <tr><td><li>CapPTZIris</li>         </td><td>- Unterstützung der Kamera für Iris-Aktion  </td></tr>
    <tr><td><li>CapPTZObjTracking</li>  </td><td>- Unterstützung der Kamera für Objekt-Tracking </td></tr>
    <tr><td><li>CapPTZPan</li>          </td><td>- Unterstützung der Kamera für Pan-Aktion  </td></tr>
    <tr><td><li>CapPTZPresetNumber</li> </td><td>- die maximale Anzahl unterstützter Presets. 0 steht für keine Preset-Unterstützung </td></tr>
    <tr><td><li>CapPTZTilt</li>         </td><td>- Unterstützung der Kamera für Tilt-Aktion  </td></tr>
    <tr><td><li>CapPTZZoom</li>         </td><td>- Unterstützung der Kamera für Zoom-Aktion  </td></tr>
    <tr><td><li>DeviceType</li>         </td><td>- Kameratyp (Camera, Video_Server, PTZ, Fisheye)  </td></tr>
    <tr><td><li>Error</li>              </td><td>- Meldungstext des letzten Fehlers  </td></tr>
    <tr><td><li>Errorcode</li>          </td><td>- Fehlercode des letzten Fehlers   </td></tr>
	<tr><td><li>HomeModeState</li>      </td><td>- HomeMode-Status (ab SVS-Version 8.1.0)   </td></tr>
	<tr><td><li>LastLogEntry</li>       </td><td>- der neueste Eintrag des Surveillance Station Logs (nur SVS-Device und wenn Attribut pollcaminfoall gesetzt)   </td></tr>
    <tr><td><li>LastSnapFilename</li>   </td><td>- der Filename des letzten Schnapschusses   </td></tr>
    <tr><td><li>LastSnapId</li>         </td><td>- die ID des letzten Schnapschusses   </td></tr>
	<tr><td><li>LastSnapTime</li>       </td><td>- Zeitstempel des letzten Schnapschusses   </td></tr>
    <tr><td><li>LastUpdateTime</li>     </td><td>- Datum / Zeit der letzten Aktualisierung durch "caminfoall" </td></tr> 
    <tr><td><li>LiveStreamUrl </li>     </td><td>- die LiveStream-Url wenn der Stream gestartet ist. (<a href="#SSCamattr">Attribut</a> "showStmInfoFull" muss gesetzt sein) </td></tr> 
    <tr><td><li>Patrols</li>            </td><td>- in Surveillance Station voreingestellte Überwachungstouren (bei PTZ-Kameras)  </td></tr>
    <tr><td><li>PollState</li>          </td><td>- zeigt den Status des automatischen Pollings an  </td></tr>
    <tr><td><li>PresetHome</li>         </td><td>- Name der Home-Position (bei PTZ-Kameras)  </td></tr>    
    <tr><td><li>Presets</li>            </td><td>- in Surveillance Station voreingestellte Positionen (bei PTZ-Kameras)  </td></tr>
    <tr><td><li>Record</li>             </td><td>- Aufnahme läuft = Start, keine Aufnahme = Stop  </td></tr> 
    <tr><td><li>StmKey</li>             </td><td>- aktueller StreamKey. Kann zum öffnen eines Livestreams ohne Session Id genutzt werden.    </td></tr> 
    <tr><td><li>StmKeyUnicst</li>       </td><td>- Uni-cast Stream Pfad der Kamera. (<a href="#SSCamattr">Attribut</a> "showStmInfoFull" muss gesetzt sein)  </td></tr> 
    <tr><td><li>StmKeymjpegHttp</li>    </td><td>- Mjpeg Stream Pfad (über http) der Kamera. (<a href="#SSCamattr">Attribut</a> "showStmInfoFull" muss gesetzt sein)  </td></tr>
    <tr><td><li>SVScustomPortHttp</li>  </td><td>- benutzerdefinierter Port der Surveillance Station (HTTP) im DSM-Anwendungsportal (get mit "svsinfo")  </td></tr> 
    <tr><td><li>SVScustomPortHttps</li> </td><td>- benutzerdefinierter Port der Surveillance Station (HTTPS) im DSM-Anwendungsportal (get mit "svsinfo") </td></tr>
    <tr><td><li>SVSlicenseNumber</li>   </td><td>- die Anzahl der installierten Kameralizenzen (get mit "svsinfo") </td></tr>
    <tr><td><li>SVSuserPriv</li>        </td><td>- die effektiven Rechte des verwendeten Users nach dem Login (get mit "svsinfo") </td></tr>
    <tr><td><li>SVSversion</li>         </td><td>- die Paketversion der installierten Surveillance Station (get mit "svsinfo") </td></tr>
    <tr><td><li>UsedSpaceMB</li>        </td><td>- durch Aufnahmen der Kamera belegter Plattenplatz auf dem Volume  </td></tr>
    <tr><td><li>VideoFolder</li>        </td><td>- Pfad zu den aufgenommenen Videos  </td></tr>
  </table>
  </ul>
  <br><br>    
 </ul>
  
 </ul>
 <br><br>
</ul>

=end html_DE
=cut
