#########################################################################################################################
# $Id$
#########################################################################################################################
#       49_SSCam.pm
#
#       (c) 2015-2017 by Heiko Maaz
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
# 2.3.2  28.07.2017    code change of getcaminfo (params of Interaltimer)
# 2.3.1  28.07.2017    code review creating log entries when pollnologging is set/unset
# 2.3.0  27.07.2017    new "get snapinfo" command, minor fixes
# 2.2.4  25.07.2017    avoid error "Operation Getptzlistpreset of Camera ... was not successful" if cam is disabled
# 2.2.3  30.06.2017    fix if SVSversion small "0", create events for "snap"
# 2.2.2  11.06.2017    bugfix sscam_login, sscam_login_return, 
#                      Forum: https://forum.fhem.de/index.php/topic,45671.msg646701.html#msg646701
# 2.2.1  15.05.2017    avoid FW_detailFn because of FW_deviceOverview is active (double streams in detailview if on)
# 2.2.0  10.05.2017    check if JSON module has been loaded successfully, DeviceOverview available, options of 
#                      runView changed image->live_fw, link->live_link, link_open->live_open, lastrec ->lastrec_fw,
#                      commandref revised
# 2.1.4  08.05.2017    commandref changed
# 2.1.3  05.05.2017    issue of operation error if CAMID is set and SID isn't valid, more login-errorcodes evaluation
# 2.1.2  04.05.2017    default login retries increased to 3
# 2.1.1  17.04.2017    runliveview routine changed, {HELPER}{SID_STRM} deleted
# 2.1.0  12.04.2017    some codereview, getapisites cached, CAMID cached, rewrite logs from verbose 4 to 5,
#                      get scanVirgin, commandref replenished
# 2.0.0  10.04.2017    redesign login procedure, fix Reading SVSversion use SMALL version, new attr loginRetries
# 1.42   15.03.2017    sscam_camop changed to get all cam id's and names
# 1.41   15.03.2017    minor bugfix of blank character in state "disabled" (row 3383)
# 1.40   21.01.2017    downgrade of API apicammaxver in SVS 8.0.0
# 1.39   20.01.2017    compatibility to SVS 8.0.0, Version in Internals, execute getsvsinfo after set credentials
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
#                      run "geteventlist" automatically after recording-stop
# 1.20.2 14.03.2016    change: routine "initonboot" changed
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
#  1.5    04.01.2016   Function "Get" for creating Camera-Readings integrated,
#                      Attributs pollcaminfoall, pollnologging  added,
#                      Function for Polling Cam-Infos added.
#  1.4    23.12.2015   function "enable" and "disable" for SS-Cams added,
#                      changed timout of Http-calls to a higher value
#  1.3    19.12.2015   function "snap" for taking snapshots added,
#                      fixed a bug that functions may impact each other 
#  1.2    14.12.2015   improve usage of verbose-modes
#  1.1    13.12.2015   use of InternalTimer instead of fhem(sleep)
#  1.0    12.12.2015   changed completly to HttpUtils_NonblockingGet for calling websites nonblocking, 
#                      LWP is not needed anymore
#
#
# Definition: define <name> SSCam <camname> <ServerAddr> [ServerPort] 
# 
# Example: define CamCP1 SSCAM Carport 192.168.2.20 [5000]
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

my $SSCamVersion = "2.8.0";

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
 $hash->{FW_summaryFn} = "SSCam_FWview";
 # $hash->{FW_detailFn}  = "SSCam_FWview";
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
         "debugactivetoken:1 ".
         "rectime ".
         "recextend:1,0 ".
         "noQuotesForSID:1,0 ".
         "session:SurveillanceStation,DSM ".
         "showPassInLog:1,0 ".
         "showStmInfoFull:1,0 ".
         "simu_SVSversion:7.2-xxxx,7.1-xxxx ".
         "webCmd ".
         $readingFnAttributes;   
         
return undef;   
}

sub SSCam_Define {
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
  
  $hash->{SERVERADDR}       = $serveraddr;
  $hash->{SERVERPORT}       = $serverport;
  $hash->{CAMNAME}          = $camname;
  $hash->{VERSION}          = $SSCamVersion;
 
  # benötigte API's in $hash einfügen
  $hash->{HELPER}{APIINFO}        = "SYNO.API.Info";                             # Info-Seite für alle API's, einzige statische Seite !                                                    
  $hash->{HELPER}{APIAUTH}        = "SYNO.API.Auth"; 
  $hash->{HELPER}{APISVSINFO}     = "SYNO.SurveillanceStation.Info"; 
  $hash->{HELPER}{APIEVENT}       = "SYNO.SurveillanceStation.Event"; 
  $hash->{HELPER}{APIEXTREC}      = "SYNO.SurveillanceStation.ExternalRecording"; 
  $hash->{HELPER}{APIEXTEVT}      = "SYNO.SurveillanceStation.ExternalEvent";
  $hash->{HELPER}{APICAM}         = "SYNO.SurveillanceStation.Camera";
  $hash->{HELPER}{APISNAPSHOT}    = "SYNO.SurveillanceStation.SnapShot";
  $hash->{HELPER}{APIPTZ}         = "SYNO.SurveillanceStation.PTZ";
  $hash->{HELPER}{APICAMEVENT}    = "SYNO.SurveillanceStation.Camera.Event";
  $hash->{HELPER}{APIVIDEOSTM}    = "SYNO.SurveillanceStation.VideoStreaming";
  $hash->{HELPER}{APISTM}         = "SYNO.SurveillanceStation.Streaming";
  $hash->{HELPER}{APIHM}          = "SYNO.SurveillanceStation.HomeMode";
  
  # Startwerte setzen
  $attr{$name}{webCmd}                 = "on:off:snap:enable:disable";                            # initiale Webkommandos setzen
  $hash->{HELPER}{ACTIVE}              = "off";                                                   # Funktionstoken "off", Funktionen können sofort starten
  $hash->{HELPER}{OLDVALPOLLNOLOGGING} = "0";                                                     # Loggingfunktion für Polling ist an
  $hash->{HELPER}{RECTIME_DEF}         = "15";                                                    # Standard für rectime setzen, überschreibbar durch Attribut "rectime" bzw. beim "set .. on-for-time"
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"Availability", "???");                                                # Verfügbarkeit ist unbekannt
  readingsBulkUpdate($hash,"PollState","Inactive");                                               # es ist keine Gerätepolling aktiv
  readingsBulkUpdate($hash,"state", "off");                                                       # Init für "state" , Problemlösung für setstate, Forum #308
  readingsEndUpdate($hash,1);                                          
  
  getcredentials($hash,1);                                                                        # Credentials lesen und in RAM laden ($boot=1)      
  
  # initiale Routinen nach Restart ausführen   , verzögerter zufälliger Start
  RemoveInternalTimer($hash, "initonboot");
  InternalTimer(gettimeofday()+int(rand(30)), "initonboot", $hash, 0);

return undef;
}

################################################################
sub SSCam_Undef {
    my ($hash, $arg) = @_;
    logout_nonbl($hash);
    RemoveInternalTimer($hash);
return undef;
}

################################################################
sub SSCam_Delete {
    my ($hash, $arg) = @_;
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_credentials";
    
    # gespeicherte Credentials löschen
    setKeyValue($index, undef);
	
	# löschen snapGallerie-Device falls vorhanden
	my $sgdev = "SSCam.$hash->{NAME}.snapgallery";
    CommandDelete($hash->{CL},"$sgdev");
    
return undef;
}

################################################################
sub SSCam_Attr {
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};
    my $do;
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    
    if ($aName eq "disable") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        my $val   = ($do == 1 ?  "inactive" : "off");
    
        readingsSingleUpdate($hash, "state", $val, 1);
        readingsSingleUpdate($hash, "PollState", "Inactive", 1) if($do == 1);
        readingsSingleUpdate($hash, "Availability", "???", 1) if($do == 1);
    }
    
    if ($aName eq "showStmInfoFull") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");

        if ($do == 0) {
            delete($defs{$name}{READINGS}{StmKeymjpegHttp}) if ($defs{$name}{READINGS}{StmKeymjpegHttp});
            delete($defs{$name}{READINGS}{StmKeyUnicst}) if ($defs{$name}{READINGS}{StmKeyUnicst});
            delete($defs{$name}{READINGS}{LiveStreamUrl}) if ($defs{$name}{READINGS}{LiveStreamUrl});         
        }
    }

    if ($aName eq "snapGallerySize") {
        if($cmd eq "set") {
            $do = ($aVal eq "Icon")?1:2;
        }
        $do = 0 if($cmd eq "del");

        if ($do == 0) {
            delete($hash->{HELPER}{SNAPHASH}) if(AttrVal($name,"snapGalleryBoost",0));  # Snaphash nur löschen wenn Snaps gepollt werden   
            Log3($name, 4, "$name - Snapshot hash deleted");
		} elsif (AttrVal($name,"snapGalleryBoost",0)) {
		    # snap-Infos abhängig ermitteln wenn gepollt werden soll
		    my ($slim,$ssize);
            $hash->{HELPER}{GETSNAPGALLERY} = 1;
		    $slim  = AttrVal($name,"snapGalleryNumber",$SSCam_slim);    # Anzahl der abzurufenden Snaps
			$ssize = $do;
			RemoveInternalTimer($hash, "getsnapinfo");
			InternalTimer(gettimeofday()+0.7, "getsnapinfo", "$name:$slim:$ssize", 0);
		}
    }     
	
    if ($aName eq "snapGalleryBoost") {
        if($cmd eq "set") {
            $do = ($aVal == 1)?1:0;
        }
        $do = 0 if($cmd eq "del");

        if ($do == 0) {
            delete($hash->{HELPER}{SNAPHASH});  # Snaphash löschen
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
			RemoveInternalTimer($hash, "getsnapinfo");
			InternalTimer(gettimeofday()+0.7, "getsnapinfo", "$name:$slim:$ssize", 0);
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
		RemoveInternalTimer($hash, "getsnapinfo");
		InternalTimer(gettimeofday()+0.7, "getsnapinfo", "$name:$slim:$ssize", 0);
	}
    
    if ($aName eq "simu_SVSversion") {
	    delete $hash->{HELPER}{APIPARSET};
        getsvsinfo($hash);
    }
                         
    if ($cmd eq "set") {
        if ($aName =~ m/httptimeout|snapGalleryColumns|rectime|pollcaminfoall/ ) {
            unless ($aVal =~ /^\d+$/) { return " The Value for $aName is not valid. Use only figures 1-9 !";}
        }   
    }

    if ($cmd eq "del") {
        if ($aName =~ m/pollcaminfoall/ ) {
		    # Polling nicht ausschalten wenn snapGalleryBoost ein (regelmäßig neu einlesen)
			return "Please switch off \"snapGalleryBoost\" first if you want to deactivate \"pollcaminfoall\" because the functionality of \"snapGalleryBoost\" depends on retrieving snapshots periodical." 
		       if(AttrVal($name,"snapGalleryBoost",1));
        }   
    }
	
	
return undef;
}

################################################################
sub SSCam_Set {
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
  
  $setlist = "Unknown argument $opt, choose one of ".
             "credentials ".
             "expmode:auto,day,night ".
			 ($hash->{HELPER}{APIHMMAXVER}?"homeMode:on,off ": "").
             "on ".
             "off ".
             "motdetsc:disable,camera,SVS ".
             "snap ".
			 (AttrVal($name, "snapGalleryBoost",0)?(AttrVal($name,"snapGalleryNumber",undef) || AttrVal($name,"snapGalleryBoost",0))?"snapGallery:noArg ":"snapGallery:$SSCAM_snum ":" ").
			 "createSnapGallery:noArg ".
             "enable ".
             "disable ".
             "runView:live_fw,live_link,live_open,lastrec_fw,lastrec_open,lastsnap_fw ".
             "stopView:noArg ".
             "extevent:1,2,3,4,5,6,7,8,9,10 ".
             ((ReadingsVal("$name", "CapPTZPan", "false") ne "false") ? "runPatrol:".ReadingsVal("$name", "Patrols", "")." " : "").
             ((ReadingsVal("$name", "CapPTZPan", "false") ne "false") ? "goPreset:".ReadingsVal("$name", "Presets", "")." " : "").
             ((ReadingsVal("$name", "CapPTZAbs", "false")) ? "goAbsPTZ"." " : ""). 
             ((ReadingsVal("$name", "CapPTZDirections", "0") > 0) ? "move"." " : "");
           

  if ($opt eq "on") {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
            
      if (defined($prop)) {
          unless ($prop =~ /^\d+$/) { return " The Value for \"$opt\" is not valid. Use only figures 0-9 without decimal places !";}
          $hash->{HELPER}{RECTIME_TEMP} = $prop;
      }
      camstartrec($hash);
 
  } elsif ($opt eq "off") {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      camstoprec($hash);
        
  } elsif ($opt eq "snap") {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      camsnap($hash);
        
  } elsif ($opt eq "snapGallery") {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      my $ret = getclhash($hash);
      return $ret if($ret);
  
	  if(!AttrVal($name, "snapGalleryBoost",0)) {
	      # Snaphash ist nicht vorhanden und wird neu abgerufen und ausgegeben
		  $hash->{HELPER}{GETSNAPGALLERY} = 1;
        
		  # snap-Infos für Gallerie abrufen
		  my ($sg,$slim,$ssize); 
		  $slim  = $prop?AttrVal($name,"snapGalleryNumber",$prop):AttrVal($name,"snapGalleryNumber",$SSCam_slim);  # Anzahl der abzurufenden Snapshots
		  $ssize = (AttrVal($name,"snapGallerySize","Icon") eq "Icon")?1:2;                                        # Image Size 1-Icon, 2-Full		
        
		  getsnapinfo("$name:$slim:$ssize");
		
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
	  
  } elsif ($opt eq "createSnapGallery") {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      my ($ret,$sgdev);
      return "When you want use \"$opt\", you have to set the attribute \"snapGalleryBoost\" first because the functionality depends on retrieving snapshots automatically." 
		       if(!AttrVal($name,"snapGalleryBoost",0));
	  $sgdev = "SSCam.$name.snapgallery";
      $ret = CommandDefine($hash->{CL},"$sgdev weblink htmlCode {composegallery('$name','$sgdev')}");
	  return $ret if($ret);
	  my $wlname = "SSCam.$name.snapgallery";
	  my $room   = "SnapGallery";
	  CommandAttr($hash->{CL},$wlname." room ".$room);
	  return "<html>Snapgallery device \"$sgdev\" was created successfully. Please have a look to room <a href=\"/fhem?room=$room\">$room</a>.<br> You can now assign it to another room if you want. Don't rename this new device ! </html>";
      
  } elsif ($opt eq "enable") {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      camenable($hash);
        
  } elsif ($opt eq "disable") {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      camdisable($hash);
       
  } elsif ($opt eq "motdetsc") {
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
      cammotdetsc($hash);
        
  } elsif ($opt eq "credentials") {
      return "Credentials are incomplete, use username password" if (!$prop || !$prop1);
	  return "Password is too long. It is limited up to and including 20 characters." if (length $prop1 > 20);
      delete $hash->{HELPER}{SID} if($hash->{HELPER}{SID});          
      ($success) = setcredentials($hash,$prop,$prop1);
      $hash->{HELPER}{ACTIVE} = "off";  
	  
	  if($success) {
	      getsvsinfo($hash);
		  return "Username and Password saved successfully";
	  } else {
		   return "Error while saving Username / Password - see logfile for details";
	  }
			
  } elsif ($opt eq "expmode") {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      unless ($prop) { return " \"$opt\" needs one of those arguments: auto, day, night !";}
            
      $hash->{HELPER}{EXPMODE} = $prop;
      camexpmode($hash);
        
  } elsif ($opt eq "homeMode") {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      unless ($prop) { return " \"$opt\" needs one of those arguments: on, off !";}
            
      $hash->{HELPER}{HOMEMODE} = $prop;
      sethomemode($hash);
        
  } elsif ($opt eq "goPreset") {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      if (!$prop) {return "Function \"goPreset\" needs a \"Presetname\" as an argument";}
            
      @prop = split(/;/, $prop);
      $prop = $prop[0];
      @prop = split(/,/, $prop);
      $prop = $prop[0];
      $hash->{HELPER}{GOPRESETNAME} = $prop;
      $hash->{HELPER}{PTZACTION}    = "gopreset";
      doptzaction($hash);
        
  } elsif ($opt eq "runPatrol") {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      if (!$prop) {return "Function \"runPatrol\" needs a \"Patrolname\" as an argument";}
            
      @prop = split(/;/, $prop);
      $prop = $prop[0];
      @prop = split(/,/, $prop);
      $prop = $prop[0];
      $hash->{HELPER}{GOPATROLNAME} = $prop;
      $hash->{HELPER}{PTZACTION}    = "runpatrol";
      doptzaction($hash);
        
  } elsif ($opt eq "goAbsPTZ") {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}

      if ($prop eq "up" || $prop eq "down" || $prop eq "left" || $prop eq "right") {
          if ($prop eq "up")    {$hash->{HELPER}{GOPTZPOSX} = 320; $hash->{HELPER}{GOPTZPOSY} = 480;}
          if ($prop eq "down")  {$hash->{HELPER}{GOPTZPOSX} = 320; $hash->{HELPER}{GOPTZPOSY} = 0;}
          if ($prop eq "left")  {$hash->{HELPER}{GOPTZPOSX} = 0; $hash->{HELPER}{GOPTZPOSY} = 240;}    
          if ($prop eq "right") {$hash->{HELPER}{GOPTZPOSX} = 640; $hash->{HELPER}{GOPTZPOSY} = 240;} 
                
          $hash->{HELPER}{PTZACTION} = "goabsptz";
          doptzaction($hash);
          return undef;
            
	  } else {
          if ($prop !~ /\d+/ || $prop1 !~ /\d+/ || abs($prop) > 640 || abs($prop1) > 480) {
              return "Function \"goAbsPTZ\" needs two coordinates, posX=0-640 and posY=0-480, as arguments or use up, down, left, right instead";
          }
                
          $hash->{HELPER}{GOPTZPOSX} = abs($prop);
          $hash->{HELPER}{GOPTZPOSY} = abs($prop1);
                
          $hash->{HELPER}{PTZACTION}  = "goabsptz";
          doptzaction($hash);
                
          return undef;
                
      } 
          return "Function \"goAbsPTZ\" needs two coordinates, posX=0-640 and posY=0-480, as arguments or use up, down, left, right instead";

  } elsif ($opt eq "move") {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}

      if (!defined($prop) || ($prop ne "up" && $prop ne "down" && $prop ne "left" && $prop ne "right" && $prop !~ m/dir_\d/)) {return "Function \"move\" needs an argument like up, down, left, right or dir_X (X = 0 to CapPTZDirections-1)";}
            
      $hash->{HELPER}{GOMOVEDIR} = $prop;
      $hash->{HELPER}{GOMOVETIME} = defined($prop1) ? $prop1 : 1;
            
      $hash->{HELPER}{PTZACTION}  = "movestart";
      doptzaction($hash);
        
  } elsif ($opt eq "runView") {
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
      }  elsif ($prop eq "lastrec_fw") {
          $hash->{HELPER}{OPENWINDOW} = 0;
          $hash->{HELPER}{WLTYPE}     = "iframe"; 
	      $hash->{HELPER}{ALIAS}      = " ";
		  $hash->{HELPER}{RUNVIEW}    = "lastrec";
      } elsif ($prop eq "live_fw") {
          $hash->{HELPER}{OPENWINDOW} = 0;
          $hash->{HELPER}{WLTYPE}     = "image"; 
		  $hash->{HELPER}{ALIAS}      = " ";
		  $hash->{HELPER}{RUNVIEW}    = "live_fw";
      } elsif ($prop eq "lastsnap_fw") {
          $hash->{HELPER}{OPENWINDOW}  = 0;
          $hash->{HELPER}{WLTYPE}      = "base64img"; 
		  $hash->{HELPER}{ALIAS}       = " ";
		  $hash->{HELPER}{RUNVIEW}     = "lastsnap_fw";
      } else {
          return "$prop isn't a valid option of runview, use one of live_fw, live_link, live_open, lastrec_fw, lastrec_open, lastsnap_fw";
      }
      runliveview($hash); 
            
  } elsif ($opt eq "extevent") {
      if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
                                   
      $hash->{HELPER}{EVENTID} = $prop;
      extevent($hash);
        
  } elsif ($opt eq "stopView") {
      stopliveview($hash);            
        
  } else {
      return "$setlist";
  }  
  
return;
}

################################################################
sub SSCam_Get {
    my ($hash, @a) = @_;
    return "\"get X\" needs at least an argument" if ( @a < 2 );
    my $name = shift @a;
    my $opt = shift @a;
	my $arg = shift @a;
	my $ret = "";

	my $getlist = "Unknown argument $opt, choose one of ".
                  "caminfoall:noArg ".
				  ((AttrVal($name,"snapGalleryNumber",undef) || AttrVal($name,"snapGalleryBoost",0))
				      ?"snapGallery:noArg ":"snapGallery:$SSCAM_snum ").
				  "snapinfo:noArg ".
                  "svsinfo:noArg ".
                  "snapfileinfo:noArg ".
                  "eventlist:noArg ".
	        	  "stmUrlPath:noArg ".
				  "scanVirgin:noArg "
                  ;
				  
    return if(IsDisabled($name));             
        
    if ($opt eq "caminfoall") {
        # "1" ist Statusbit für manuelle Abfrage, kein Einstieg in Pollingroutine
		if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        getcaminfoall($hash,1);
                
    } elsif ($opt eq "svsinfo") {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        getsvsinfo($hash);
                
    } elsif ($opt eq "snapGallery") {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
	    my $ret = getclhash($hash);
        return $ret if($ret);

		if(!AttrVal($name, "snapGalleryBoost",0)) {	
            # Snaphash ist nicht vorhanden und wird abgerufen		
		    $hash->{HELPER}{GETSNAPGALLERY} = 1;
        
		    # snap-Infos für Gallerie abrufen
		    my ($sg,$slim,$ssize); 
		    $slim  = $arg?AttrVal($name,"snapGalleryNumber",$arg):AttrVal($name,"snapGalleryNumber",$SSCam_slim);  # Anzahl der abzurufenden Snapshots
		    $ssize = (AttrVal($name,"snapGallerySize","Icon") eq "Icon")?1:2;                                      # Image Size 1-Icon, 2-Full		
        
		    getsnapinfo("$name:$slim:$ssize");
		
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

    } elsif ($opt eq "snapinfo") {
        # Schnappschußgalerie abrufen (snapGalleryBoost) oder nur Info des letzten Snaps
		if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        my ($slim,$ssize) = snaplimsize($hash);		
        getsnapinfo("$name:$slim:$ssize");
                
    } elsif ($opt eq "snapfileinfo") {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        if (!ReadingsVal("$name", "LastSnapId", undef)) {return "Reading LastSnapId is empty - please take a snapshot before !"}
        getsnapfilename($hash);
                
    } elsif ($opt eq "eventlist") {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        geteventlist ($hash);
                
    } elsif ($opt eq "stmUrlPath") {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        getStmUrlPath ($hash);
            
	} elsif ($opt eq "scanVirgin") {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        delete $hash->{HELPER}{APIPARSET};
	    delete $hash->{HELPER}{SID};
		delete $hash->{CAMID};
		# "1" ist Statusbit für manuelle Abfrage, kein Einstieg in Pollingroutine
        getcaminfoall($hash,1);
    
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
sub SSCam_FWview ($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_;   # pageHash is set for summaryFn in FHEMWEB
  my $hash          = $defs{$d};
  my $name          = $hash->{NAME};
  my $link          = $hash->{HELPER}{LINK};
  my $wltype        = $hash->{HELPER}{WLTYPE};
  my $ret;
  my $alias;
    
  return if(!$hash->{HELPER}{LINK} || ReadingsVal("$name", "state", "") =~ /^dis.*/ || IsDisabled($name));
  
  my $attr = AttrVal($d, "htmlattr", " ");
  Log3($name, 4, "$name - SSCam_FWview called - FW_wname: $FW_wname, device: $d, room: $room, attributes: $attr");
  
  if($wltype eq "image") {
    $ret = "<img src=$link $attr><br>".weblink_FwDetail($d);
  
  } elsif($wltype eq "iframe") {
    $ret = "<iframe src=$link $attr>Iframes disabled</iframe>".weblink_FwDetail($d);
           
  } elsif($wltype eq "link") {
    $alias = $hash->{HELPER}{ALIAS};
    $ret = "<a href=$link $attr>$alias</a><br>";     

  } elsif($wltype eq "base64img") {
    $alias = $hash->{HELPER}{ALIAS};
    $ret = "<img $attr alt='$alias' src='data:image/jpeg;base64,$link'><br>";
  }

  # FW_directNotify("FILTER=room=$room", "#FHEMWEB:$FW_wname", "location.reload('true')", "") if($d eq $name);
return $ret;
}

######################################################################################
#                   initiale Startroutinen nach Restart FHEM
######################################################################################
sub initonboot ($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  if ($init_done == 1) {
     
     RemoveInternalTimer($hash);                                                                     # alle Timer löschen
     
     delete($defs{$name}{READINGS}{LiveStreamUrl}) if($defs{$name}{READINGS}{LiveStreamUrl});        # LiveStream URL zurücksetzen
     
     # check ob alle Recordings = "Stop" nach Reboot -> sonst stoppen
     if (ReadingsVal($hash->{NAME}, "Record", "Stop") eq "Start") {
         Log3($name, 2, "$name - Recording of $hash->{CAMNAME} seems to be still active after FHEM restart - try to stop it now");
         camstoprec($hash);
     }
         
     # Konfiguration der Synology Surveillance Station abrufen
     if (!$hash->{CREDENTIALS}) {
         Log3($name, 2, "$name - Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"");
     } else {
         # allg. SVS-Eigenschaften abrufen
         getsvsinfo($hash);
         # Kameraspezifische Infos holen
         getcaminfo($hash);
		 
         # Schnappschußgalerie abrufen (snapGalleryBoost) oder nur Info des letzten Snaps
         my ($slim,$ssize) = snaplimsize($hash);		
         getsnapinfo("$name:$slim:$ssize");

         getcapabilities($hash);
         # Preset/Patrollisten in Hash einlesen zur PTZ-Steuerung
         getptzlistpreset($hash);
         getptzlistpatrol($hash);
     }
         
     # Subroutine Watchdog-Timer starten (sollen Cam-Infos regelmäßig abgerufen werden ?), verzögerter zufälliger Start 0-30s 
     RemoveInternalTimer($hash, "watchdogpollcaminfo");
     InternalTimer(gettimeofday()+int(rand(30)), "watchdogpollcaminfo", $hash, 0);
  
  } else {
      RemoveInternalTimer($hash, "initonboot");
      InternalTimer(gettimeofday()+1, "initonboot", $hash, 0);
  }
return;
}

######################################################################################
#                            Username / Paßwort speichern
######################################################################################
sub setcredentials ($@) {
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
        getcredentials($hash,1);        # Credentials nach Speicherung lesen und in RAM laden ($boot=1) 
        $success = 1;
    }

return ($success);
}

######################################################################################
#                             Username / Paßwort abrufen
######################################################################################
sub getcredentials ($$) {
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
sub watchdogpollcaminfo ($) {
    # Überwacht die Wert von Attribut "pollcaminfoall" und Reading "PollState"
    # wenn Attribut "pollcaminfoall" > 10 und "PollState"=Inactive -> start Polling
    my ($hash)   = @_;
    my $name     = $hash->{NAME};
    my $camname  = $hash->{CAMNAME};
    my $watchdogtimer = 90;
    
    if (defined($attr{$name}{pollcaminfoall}) and $attr{$name}{pollcaminfoall} > 10 and ReadingsVal("$name", "PollState", "Active") eq "Inactive" and !IsDisabled($name)) {
        
        # Polling ist jetzt aktiv
        readingsSingleUpdate($hash,"PollState","Active",0);
            
        Log3($name, 3, "$name - Polling Camera $camname is activated - Pollinginterval: ".$attr{$name}{pollcaminfoall}."s");
        
        # in $hash eintragen für späteren Vergleich (Changes von pollcaminfoall)
        $hash->{HELPER}{OLDVALPOLL} = $attr{$name}{pollcaminfoall};
        
        &getcaminfoall($hash);           
    }
    
    if (defined($hash->{HELPER}{OLDVALPOLL}) and defined($attr{$name}{pollcaminfoall}) and $attr{$name}{pollcaminfoall} > 10) {
        if ($hash->{HELPER}{OLDVALPOLL} != $attr{$name}{pollcaminfoall}) {
        
            Log3($name, 3, "$name - Polling Camera $camname was changed to new Pollinginterval: ".$attr{$name}{pollcaminfoall}."s");
            
            $hash->{HELPER}{OLDVALPOLL} = $attr{$name}{pollcaminfoall};
            }
    }
    
    if (defined($attr{$name}{pollnologging})) {
        if ($hash->{HELPER}{OLDVALPOLLNOLOGGING} ne $attr{$name}{pollnologging}) {
        
            if ($attr{$name}{pollnologging} == "1") {
            
                Log3($name, 3, "$name - Log of Polling Camera $camname is deactivated");
                
                # in $hash eintragen für späteren Vergleich (Changes von pollnologging)
                $hash->{HELPER}{OLDVALPOLLNOLOGGING} = $attr{$name}{pollnologging};
                
            } else {
            
                Log3($name, 3, "$name - Log of Polling Camera $camname is activated");
                
                # in $hash eintragen für späteren Vergleich (Changes von pollnologging)
                $hash->{HELPER}{OLDVALPOLLNOLOGGING} = $attr{$name}{pollnologging};
            }
        }
    } else {
    
        # alter Wert von "pollnologging" war 1 -> Logging war deaktiviert
        if ($hash->{HELPER}{OLDVALPOLLNOLOGGING} == "1") {

            Log3($name, 3, "$name - Log of Polling Camera $camname is activated");
            
            $hash->{HELPER}{OLDVALPOLLNOLOGGING} = "0";            
        }
    }
RemoveInternalTimer($hash, "watchdogpollcaminfo");
InternalTimer(gettimeofday()+$watchdogtimer, "watchdogpollcaminfo", $hash, 0);
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
sub camstartrec ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = experror($hash,$errorcode);

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
        
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        sscam_getapisites($hash);
    
	} else {
        RemoveInternalTimer($hash, "camstartrec");
        InternalTimer(gettimeofday()+0.3, "camstartrec", $hash);
    }
}

###############################################################################
#                           Kamera Aufnahme stoppen
###############################################################################
sub camstoprec ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = experror($hash,$errorcode);

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
		
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }  
        sscam_getapisites($hash);
		
    } else {
        RemoveInternalTimer($hash, "camstoprec");
        InternalTimer(gettimeofday()+0.3, "camstoprec", $hash, 0);
    }
}

###############################################################################
#                   Kamera Auto / Day / Nightmode setzen
###############################################################################
sub camexpmode ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = experror($hash,$errorcode);

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
		
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        sscam_getapisites($hash);
		
    } else {
        RemoveInternalTimer($hash, "camexpmode");
        InternalTimer(gettimeofday()+0.5, "camexpmode", $hash, 0);
    }
}

###############################################################################
#                    Art der Bewegungserkennung setzen
###############################################################################
sub cammotdetsc ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = experror($hash,$errorcode);

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
		
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }    
        sscam_getapisites($hash);
		
    } else {
        RemoveInternalTimer($hash, "cammotdetsc");
        InternalTimer(gettimeofday()+0.5, "cammotdetsc", $hash, 0);
    }
}

###############################################################################
#                       Kamera Schappschuß aufnehmen
###############################################################################
sub camsnap ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = experror($hash,$errorcode);

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
		
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        
        sscam_getapisites($hash);
		
    } else {
        RemoveInternalTimer($hash, "camsnap");
        InternalTimer(gettimeofday()+0.3, "camsnap", $hash, 0);
    }    
}

###############################################################################
#                         Kamera Liveview starten
###############################################################################
sub runliveview ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    return if(IsDisabled($name));
    
    if (ReadingsVal("$name", "state", "") =~ /^dis.*/) {
        if (ReadingsVal("$name", "state", "") eq "disabled") {
            $errorcode = "402";
        } elsif (ReadingsVal("$name", "state", "") eq "disconnected") {
            $errorcode = "502";
        }
        
        # Fehlertext zum Errorcode ermitteln
        $error = &experror($hash,$errorcode);
        # Setreading 
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
        
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        readingsSingleUpdate($hash,"state","startview",1); 
        sscam_getapisites($hash);
    
	} else {
        RemoveInternalTimer($hash, "runliveview");
        InternalTimer(gettimeofday()+0.5, "runliveview", $hash, 0);
    }    
}

###############################################################################
#                         Kamera Liveview stoppen
###############################################################################
sub stopliveview ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
   
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        
        # Liveview stoppen           
        $hash->{OPMODE} = "stopliveview";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        
        # Link aus Helper-hash löschen
        delete $hash->{HELPER}{LINK};
        
        # Reading LiveStreamUrl löschen
        delete($defs{$name}{READINGS}{LiveStreamUrl}) if ($defs{$name}{READINGS}{LiveStreamUrl});
		# Longpoll refresh
        readingsSingleUpdate($hash,"state","stopview",1); 
		
        # Aufnahmestatus im state abbilden
	    my $st;
	    (ReadingsVal("$name", "Record", "") eq "Start")?$st="on":$st="off";
	    readingsSingleUpdate($hash,"state", $st, 1);        
        
		$hash->{HELPER}{ACTIVE} = "off";  
		if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
        }
	
	} else {
        RemoveInternalTimer($hash, "stopliveview");
        InternalTimer(gettimeofday()+0.5, "stopliveview", $hash, 0);
    }    
}

###############################################################################
#                       external Event 1-10 auslösen
###############################################################################
sub extevent ($) {
    my ($hash)   = @_;
    my $name     = $hash->{NAME};
    
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE} = "extevent";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        sscam_getapisites($hash);
		
    } else {
        RemoveInternalTimer($hash, "extevent");
        InternalTimer(gettimeofday()+0.5, "extevent", $hash, 0);
    }    
}

###############################################################################
#                      PTZ-Kamera auf Position fahren
###############################################################################
sub doptzaction ($) {
    my ($hash)             = @_;
    my $camname            = $hash->{CAMNAME};
    my $name               = $hash->{NAME};
    my $errorcode;
    my $error;
    
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
            $error = experror($hash,$errorcode);
        
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
            $error = experror($hash,$errorcode);
        
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
        $error = experror($hash,$errorcode);

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
 
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
    
        $hash->{OPMODE} = $hash->{HELPER}{PTZACTION};
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
 
        sscam_getapisites($hash);
 
    } else {
        RemoveInternalTimer($hash, "doptzaction");
        InternalTimer(gettimeofday()+0.5, "doptzaction", $hash, 0);
    }    
}

###############################################################################
#                         stoppen continoues move
###############################################################################
sub movestop ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE} = "movestop";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");;
        }
        sscam_getapisites($hash);
   
    } else {
        RemoveInternalTimer($hash, "movestop");
        InternalTimer(gettimeofday()+0.3, "movestop", $hash, 0);
    }    
}

###############################################################################
#                           Kamera aktivieren
###############################################################################
sub camenable ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    return if(IsDisabled($name));
    
    # if (ReadingsVal("$name", "Availability", "disabled") eq "enabled") {return;}       # Kamera ist bereits enabled
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        # eine Kamera aktivieren
        Log3($name, 4, "$name - Enable Camera $camname");
                        
        $hash->{OPMODE} = "Enable";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        sscam_getapisites($hash);
    
	} else {
        RemoveInternalTimer($hash, "camenable");
        InternalTimer(gettimeofday()+0.5, "camenable", $hash, 0);
    }    
}

###############################################################################
#                            Kamera deaktivieren
###############################################################################
sub camdisable ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    return if(IsDisabled($name));
    
    # if (ReadingsVal("$name", "Availability", "enabled") eq "disabled") {return;}       # Kamera ist bereits disabled
    
    if ($hash->{HELPER}{ACTIVE} eq "off" and ReadingsVal("$name", "Record", "Start") ne "Start") {
        # eine Kamera deaktivieren
        Log3($name, 4, "$name - Disable Camera $camname");
                        
        $hash->{OPMODE} = "Disable";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        sscam_getapisites($hash);
		
    } else {
        RemoveInternalTimer($hash, "camdisable");
        InternalTimer(gettimeofday()+0.5, "camdisable", $hash, 0);
    }    
}

###############################################################################
#      Kamera alle Informationen abrufen (Get) bzw. Einstieg Polling
###############################################################################
sub getcaminfoall {
    my ($hash,$mode)   = @_;
    my $camname        = $hash->{CAMNAME};
    my $name           = $hash->{NAME};
    my ($now,$new);
    
    return if(IsDisabled($name));
    
    geteventlist($hash);
    RemoveInternalTimer($hash, "getcaminfo");
    InternalTimer(gettimeofday()+0.4, "getcaminfo", $hash, 0);
    	
    # Schnappschußgalerie abrufen (snapGalleryBoost) oder nur Info des letzten Snaps
    my ($slim,$ssize) = snaplimsize($hash);
    RemoveInternalTimer($hash, "getsnapinfo");
    InternalTimer(gettimeofday()+0.6, "getsnapinfo", "$name:$slim:$ssize", 0);
    
	RemoveInternalTimer($hash, "getmotionenum");
    InternalTimer(gettimeofday()+0.8, "getmotionenum", $hash, 0);
    RemoveInternalTimer($hash, "getcapabilities");
    InternalTimer(gettimeofday()+1.3, "getcapabilities", $hash, 0);
    RemoveInternalTimer($hash, "getptzlistpreset");
    InternalTimer(gettimeofday()+1.6, "getptzlistpreset", $hash, 0);
    RemoveInternalTimer($hash, "getptzlistpatrol");
    InternalTimer(gettimeofday()+1.9, "getptzlistpatrol", $hash, 0);
    RemoveInternalTimer($hash, "getStmUrlPath");
    InternalTimer(gettimeofday()+2.1, "getStmUrlPath", $hash, 0);
    
    # wenn gesetzt = manuelle Abfrage,
    if ($mode) {
        getsvsinfo($hash);
        return;
    }
    
    if (defined($attr{$name}{pollcaminfoall}) and $attr{$name}{pollcaminfoall} > 10) {
        # Pollen wenn pollcaminfo > 10, sonst kein Polling
        
        $new = gettimeofday()+$attr{$name}{pollcaminfoall}; 
        InternalTimer($new, "getcaminfoall", $hash, 0);
        
        if (!$attr{$name}{pollnologging}) {
            $now = FmtTime(gettimeofday());
            $new = FmtTime(gettimeofday()+$attr{$name}{pollcaminfoall});

            Log3($name, 3, "$name - Polling now: $now , next Polling: $new");
        }
    
	} else {
        # Beenden Polling aller Caminfos
        readingsSingleUpdate($hash,"PollState","Inactive",0);
        Log3($name, 3, "$name - Polling of Camera $camname is deactivated");
    }
return;
}

###########################################################################
#  Infos zu Snaps abfragen (z.B. weil nicht über SSCam ausgelöst)
###########################################################################
sub getsnapinfo ($) {
    my ($str)   = @_;
	my ($name,$slim,$ssize) = split(":",$str);
	my $hash = $defs{$name};
    my $camname  = $hash->{CAMNAME};
    
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {               
        $hash->{OPMODE} = "getsnapinfo";
		$hash->{OPMODE} = "getsnapgallery" if(exists($hash->{HELPER}{GETSNAPGALLERY}));
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		$hash->{HELPER}{SNAPLIMIT}    = $slim;   # 0-alle Snapshots werden abgerufen und ausgewertet, sonst $slim
		$hash->{HELPER}{SNAPIMGSIZE}  = $ssize;  # 0-Do not append image, 1-Icon size, 2-Full size
		$hash->{HELPER}{KEYWORD}      = $camname;
		
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        sscam_getapisites($hash);
		
    } else {
        RemoveInternalTimer($hash, "getsnapinfo");
        InternalTimer(gettimeofday()+0.7, "getsnapinfo", "$name:$slim:$ssize", 0);
    }
}

###############################################################################
#                     Filename zu Schappschuß ermitteln
###############################################################################
sub getsnapfilename ($) {
    my ($hash)   = @_;
    my $name     = $hash->{NAME};
    
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {    
        $hash->{OPMODE} = "getsnapfilename";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        sscam_getapisites($hash);
    
	} else {
        RemoveInternalTimer($hash, "getsnapfilename");
        InternalTimer(gettimeofday()+0.5, "getsnapfilename", $hash, 0);
    }    
}

###########################################################################
#       allgemeine Infos über Synology Surveillance Station
###########################################################################
sub getsvsinfo ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE} = "getsvsinfo";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        sscam_getapisites($hash);
		
    } else {
        RemoveInternalTimer($hash, "getsvsinfo");
        InternalTimer(gettimeofday()+1, "getsvsinfo", $hash, 0);
    }
}

###########################################################################
#                                HomeMode setzen 
###########################################################################
sub sethomemode ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE} = "sethomemode";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        sscam_getapisites($hash);
		
    } else {
        RemoveInternalTimer($hash, "sethomemode");
        InternalTimer(gettimeofday()+0.6, "sethomemode", $hash, 0);
    }
}

###########################################################################
#   Kamera allgemeine Informationen abrufen (Get), sub von getcaminfoall
###########################################################################
sub getcaminfo ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE} = "Getcaminfo";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        } 
        sscam_getapisites($hash);
		
    } else {
        RemoveInternalTimer($hash, "getcaminfo");
        InternalTimer(gettimeofday()+2, "getcaminfo", $hash, 0);
    } 
}

################################################################################
#       Kamera Stream Urls abrufen (Get), Aufruf aus getcaminfoall
################################################################################
sub getStmUrlPath ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        # Stream-Urls abrufen              
        $hash->{OPMODE} = "getStmUrlPath";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        sscam_getapisites($hash);
		
    } else {
        RemoveInternalTimer($hash, "getStmUrlPath");
        InternalTimer(gettimeofday()+2, "getStmUrlPath", $hash, 0);
    }
}

###########################################################################
#          query SVS-Event information , sub von getcaminfoall
###########################################################################
sub geteventlist ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {      
        $hash->{OPMODE} = "geteventlist";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        sscam_getapisites($hash);
		
    } else {
        RemoveInternalTimer($hash, "geteventlist");
        InternalTimer(gettimeofday()+2, "geteventlist", $hash, 0);
    } 
}

###########################################################################
#     Enumerate motion detection parameters, sub von getcaminfoall
###########################################################################
sub getmotionenum ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {   
        $hash->{OPMODE} = "getmotionenum";
        $hash->{HELPER}{ACTIVE} = "on";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        sscam_getapisites($hash);
		
    } else {
        RemoveInternalTimer($hash, "getmotionenum");
        InternalTimer(gettimeofday()+2, "getmotionenum", $hash, 0);
    }
    
}

##########################################################################
#    Capabilities von Kamera abrufen (Get), sub von getcaminfoall
##########################################################################
sub getcapabilities ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                       
        $hash->{OPMODE} = "Getcapabilities";
        $hash->{HELPER}{ACTIVE} = "on";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        sscam_getapisites($hash);
		
    } else {
        RemoveInternalTimer($hash, "getcapabilities");
        InternalTimer(gettimeofday()+2, "getcapabilities", $hash, 0);
    }
}

##########################################################################
#   PTZ Presets abrufen (Get), sub von getcaminfoall
##########################################################################
sub getptzlistpreset ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    return if(IsDisabled($name) || ReadingsVal("$name", "Availability", "enabled") =~ /disabled/);
    
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
		
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        sscam_getapisites($hash);
		
    } else {
        RemoveInternalTimer($hash, "getptzlistpreset");
        InternalTimer(gettimeofday()+2, "getptzlistpreset", $hash, 0);
    }
}

##########################################################################
#          PTZ Patrols abrufen (Get), sub von getcaminfoall
##########################################################################
sub getptzlistpatrol ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
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
        
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token was set by OPMODE: $hash->{OPMODE}");
        }
        sscam_getapisites($hash);
		
    } else {
        RemoveInternalTimer($hash, "getptzlistpatrol");
        InternalTimer(gettimeofday()+2, "getptzlistpatrol", $hash, 0);
    }
}

#############################################################################################################################
#######    Begin Kameraoperationen mit NonblockingGet (nicht blockierender HTTP-Call)                                 #######
#############################################################################################################################
sub sscam_getapisites {
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
   my $apisvsinfo  = $hash->{HELPER}{APISVSINFO};
   my $apicamevent = $hash->{HELPER}{APICAMEVENT};
   my $apievent    = $hash->{HELPER}{APIEVENT};
   my $apivideostm = $hash->{HELPER}{APIVIDEOSTM};
   my $apistm      = $hash->{HELPER}{APISTM};
   my $apihm       = $hash->{HELPER}{APIHM};    
   my $url;
   my $param;
  
   # API-Pfade und MaxVersions ermitteln 
   Log3($name, 4, "$name - ####################################################"); 
   Log3($name, 4, "$name - ###    start cam operation $hash->{OPMODE}          "); 
   Log3($name, 4, "$name - ####################################################"); 
   Log3($name, 4, "$name - --- Begin Function sscam_getapisites nonblocking ---");
   
   if ($hash->{HELPER}{APIPARSET}) {
       # API-Hashwerte sind bereits gesetzt -> Abruf überspringen
	   Log3($name, 4, "$name - API hashvalues already set - ignore get apisites");
       return sscam_checksid($hash);
   }

   my $httptimeout = $attr{$name}{httptimeout} ? $attr{$name}{httptimeout} : "4";
   Log3($name, 5, "$name - HTTP-Call will be done with httptimeout-Value: $httptimeout s");

   # URL zur Abfrage der Eigenschaften der  API's
   $url = "http://$serveraddr:$serverport/webapi/query.cgi?api=$apiinfo&method=Query&version=1&query=$apiauth,$apiextrec,$apicam,$apitakesnap,$apiptz,$apisvsinfo,$apicamevent,$apievent,$apivideostm,$apiextevt,$apistm,$apihm";

   Log3($name, 4, "$name - Call-Out now: $url");
   
   $param = {
               url      => $url,
               timeout  => $httptimeout,
               hash     => $hash,
               method   => "GET",
               header   => "Accept: application/json",
               callback => \&sscam_getapisites_parse
            };
   HttpUtils_NonblockingGet ($param);  
} 

####################################################################################  
#      Auswertung Abruf apisites
####################################################################################
sub sscam_getapisites_parse ($) {
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
   my $apisvsinfo  = $hash->{HELPER}{APISVSINFO};
   my $apicamevent = $hash->{HELPER}{APICAMEVENT};
   my $apievent    = $hash->{HELPER}{APIEVENT};
   my $apivideostm = $hash->{HELPER}{APIVIDEOSTM};
   my $apistm      = $hash->{HELPER}{APISTM};
   my $apihm       = $hash->{HELPER}{APIHM};
   my ($apicammaxver,$apicampath);
  
    if ($err ne "") {
	    # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
        Log3($name, 2, "$name - error while requesting ".$param->{url}." - $err");
       
        readingsSingleUpdate($hash, "Error", $err, 1);

        # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
        $hash->{HELPER}{ACTIVE} = "off"; 
        
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
        }
        return;
		
    } elsif ($myjson ne "") {          
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, my $success) = &evaljson($hash,$myjson,$param->{url});
        
        unless ($success) {
            Log3($name, 4, "$name - Data returned: $myjson");
            $hash->{HELPER}{ACTIVE} = "off";
            
            if ($attr{$name}{debugactivetoken}) {
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
        
		
            # aktuelle oder simulierte SVS-Version für Fallentscheidung setzen
            no warnings 'uninitialized'; 
            my $major = $hash->{HELPER}{SVSVERSION}{MAJOR};
            my $minor = $hash->{HELPER}{SVSVERSION}{MINOR};
			my $small = $hash->{HELPER}{SVSVERSION}{SMALL};
            my $build = $hash->{HELPER}{SVSVERSION}{BUILD}; 
            my $actvs = $major.$minor.$small.$build;
            Log3($name, 4, "$name - saved SVS version is: $actvs");
            use warnings; 
                        
            if(!$actvs and AttrVal($name, "simu_SVSversion", undef)) {
                my @vl = split (/\.|-/,AttrVal($name, "simu_SVSversion", ""));
                $actvs = $vl[0];
                $actvs .= $vl[1];
                $actvs .= $vl[2]."-simu" if($vl[2]);
            }
                        
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
                }
            
			} else {
                Log3($name, 4, "$name - no simulations done !");
            } 
            Log3($name, 4, "$name - ------- End of simulation section -------");  
                        
            # Downgrades für nicht kompatible API-Versionen
            Log3($name, 4, "$name - ------- Begin of adaption section -------");
            $apiptzmaxver = 4;
            Log3($name, 4, "$name - MaxVersion of $apiptz adapted to: $apiptzmaxver");
            $apicammaxver = 8;
            Log3($name, 4, "$name - MaxVersion of $apicam adapted to: $apicammaxver");
            Log3($name, 4, "$name - ------- End of adaption section -------");
       
            # ermittelte Werte in $hash einfügen
            $hash->{HELPER}{APIAUTHPATH}       = $apiauthpath;
            $hash->{HELPER}{APIAUTHMAXVER}     = $apiauthmaxver;
            $hash->{HELPER}{APIEXTRECPATH}     = $apiextrecpath;
            $hash->{HELPER}{APIEXTRECMAXVER}   = $apiextrecmaxver;
            $hash->{HELPER}{APICAMPATH}        = $apicampath;
            $hash->{HELPER}{APICAMMAXVER}      = $apicammaxver;
            $hash->{HELPER}{APITAKESNAPPATH}   = $apitakesnappath;
            $hash->{HELPER}{APITAKESNAPMAXVER} = $apitakesnapmaxver;
            $hash->{HELPER}{APIPTZPATH}        = $apiptzpath;
            $hash->{HELPER}{APIPTZMAXVER}      = $apiptzmaxver;
            $hash->{HELPER}{APISVSINFOPATH}    = $apisvsinfopath;
            $hash->{HELPER}{APISVSINFOMAXVER}  = $apisvsinfomaxver;
            $hash->{HELPER}{APICAMEVENTPATH}   = $apicameventpath;
            $hash->{HELPER}{APICAMEVENTMAXVER} = $apicameventmaxver;
            $hash->{HELPER}{APIEVENTPATH}      = $apieventpath;
            $hash->{HELPER}{APIEVENTMAXVER}    = $apieventmaxver;
            $hash->{HELPER}{APIVIDEOSTMPATH}   = $apivideostmpath;
            $hash->{HELPER}{APIVIDEOSTMMAXVER} = $apivideostmmaxver;
            $hash->{HELPER}{APIEXTEVTPATH}     = $apiextevtpath;
            $hash->{HELPER}{APIEXTEVTMAXVER}   = $apiextevtmaxver;
            $hash->{HELPER}{APISTMPATH}        = $apistmpath;
            $hash->{HELPER}{APISTMMAXVER}      = $apistmmaxver;
            $hash->{HELPER}{APIHMPATH}         = $apihmpath;
            $hash->{HELPER}{APIHMMAXVER}       = $apihmmaxver;
       
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
                        
            if ($attr{$name}{debugactivetoken}) {
                Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
            }
            return;
        }
	}
return sscam_checksid($hash);
}

#############################################################################################
#                        Check ob Session ID gesetzt ist - ggf. login
#############################################################################################
sub sscam_checksid ($) {  
   my ($hash) = @_;
   my $name   = $hash->{NAME};
    
   # SID holen bzw. login
   my $sid = $hash->{HELPER}{SID};
   if(!$sid) {
       Log3($name, 3, "$name - no session ID found - get new one");
	   sscam_login($hash,'sscam_getcamid');
	   return;
   }
return sscam_getcamid($hash);
}

#############################################################################################
#                             Abruf der installierten Cams
#############################################################################################
sub sscam_getcamid ($) {  
   my ($hash) = @_;
   my $name   = $hash->{NAME};
   my $serveraddr        = $hash->{SERVERADDR};
   my $serverport        = $hash->{SERVERPORT};
   my $apicam            = $hash->{HELPER}{APICAM};
   my $apicampath        = $hash->{HELPER}{APICAMPATH};
   my $apicammaxver      = $hash->{HELPER}{APICAMMAXVER};
   my $sid               = $hash->{HELPER}{SID};
    
   # die Kamera-Id wird aus dem Kameranamen (Surveillance Station) ermittelt
   Log3($name, 4, "$name - --- Begin Function sscam_getcamid nonblocking ---");
	
   if ($hash->{CAMID}) {
       # Camid ist bereits ermittelt -> Abruf überspringen
	   Log3($name, 4, "$name - CAMID already set - ignore get camid");
       return sscam_camop($hash);
   }
    
   my $httptimeout = $attr{$name}{httptimeout} ? $attr{$name}{httptimeout} : "4";
   Log3($name, 5, "$name - HTTP-Call will be done with httptimeout-Value: $httptimeout s");
  
   my $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=List&basic=true&streamInfo=true&camStm=true&_sid=\"$sid\"";
 
   Log3($name, 4, "$name - Call-Out now: $url");
  
   my $param = {
               url      => $url,
               timeout  => $httptimeout,
               hash     => $hash,
               method   => "GET",
               header   => "Accept: application/json",
               callback => \&sscam_getcamid_parse
               };
   
   HttpUtils_NonblockingGet($param);
}  

#############################################################################################
#               Auswertung installierte Cams, Selektion Cam , Ausführung Operation
#############################################################################################
sub sscam_getcamid_parse ($) {  
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
       return sscam_login($hash,'sscam_getapisites');
   
   } elsif ($myjson ne "") {
       # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)   
       # evaluiere ob Daten im JSON-Format empfangen wurden, Achtung: sehr viele Daten mit verbose=5
       ($hash, $success) = evaljson($hash,$myjson,$param->{url});
        
       unless ($success) {
           Log3($name, 4, "$name - Data returned: ".$myjson);
		   
           $hash->{HELPER}{ACTIVE} = "off";
           if ($attr{$name}{debugactivetoken}) {
               Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
           }
           return; 
       }
        
       $data = decode_json($myjson);
        
       # lesbare Ausgabe der decodierten JSON-Daten
       Log3($name, 5, "$name - JSON returned: ". Dumper $data);
   
       $success = $data->{'success'};
                
       if ($success) {
           # die Liste aller Kameras konnte ausgelesen werden, Anzahl der definierten Kameras ist in Var "total"	   
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
               if ($attr{$name}{debugactivetoken}) {
                   Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
               }
               return;
           }
      
	  } else {
           # Errorcode aus JSON ermitteln
           $errorcode = $data->{'error'}->{'code'};

           # Fehlertext zum Errorcode ermitteln
           $error = experror($hash,$errorcode);
       
           readingsBeginUpdate($hash);
           readingsBulkUpdate($hash,"Errorcode",$errorcode);
           readingsBulkUpdate($hash,"Error",$error);
           readingsEndUpdate($hash, 1);
           
		   if ($errorcode =~ /(105|401)/) {
		       # neue Login-Versuche
			   Log3($name, 2, "$name - ERROR - $errorcode - $error -> try new login");
		       return sscam_login($hash,'sscam_getapisites');
		   
		   } else {
		       # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
               $hash->{HELPER}{ACTIVE} = "off";
               if ($attr{$name}{debugactivetoken}) {
                   Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
               }
			   Log3($name, 2, "$name - ERROR - ID of Camera $camname couldn't be selected. Errorcode: $errorcode - $error");
               return;
		   }
      }
  }
return sscam_camop($hash);
}

#############################################################################################
#               Auswertung installierte Cams, Selektion Cam , Ausführung Operation
#############################################################################################
sub sscam_camop ($) {  
   my ($hash) = @_;
   my $name              = $hash->{NAME};
   my $serveraddr        = $hash->{SERVERADDR};
   my $serverport        = $hash->{SERVERPORT};
   my $apicam            = $hash->{HELPER}{APICAM};
   my $apicampath        = $hash->{HELPER}{APICAMPATH};
   my $apicammaxver      = $hash->{HELPER}{APICAMMAXVER};  
   my $apiextrec         = $hash->{HELPER}{APIEXTREC};
   my $apiextrecpath     = $hash->{HELPER}{APIEXTRECPATH};
   my $apiextrecmaxver   = $hash->{HELPER}{APIEXTRECMAXVER};
   my $apiextevt         = $hash->{HELPER}{APIEXTEVT};
   my $apiextevtpath     = $hash->{HELPER}{APIEXTEVTPATH};
   my $apiextevtmaxver   = $hash->{HELPER}{APIEXTEVTMAXVER};
   my $apitakesnap       = $hash->{HELPER}{APISNAPSHOT};
   my $apitakesnappath   = $hash->{HELPER}{APITAKESNAPPATH};
   my $apitakesnapmaxver = $hash->{HELPER}{APITAKESNAPMAXVER};
   my $apiptz            = $hash->{HELPER}{APIPTZ};
   my $apiptzpath        = $hash->{HELPER}{APIPTZPATH};
   my $apiptzmaxver      = $hash->{HELPER}{APIPTZMAXVER};
   my $apisvsinfo        = $hash->{HELPER}{APISVSINFO};
   my $apisvsinfopath    = $hash->{HELPER}{APISVSINFOPATH};
   my $apisvsinfomaxver  = $hash->{HELPER}{APISVSINFOMAXVER};
   my $apicamevent       = $hash->{HELPER}{APICAMEVENT};
   my $apicameventpath   = $hash->{HELPER}{APICAMEVENTPATH};
   my $apicameventmaxver = $hash->{HELPER}{APICAMEVENTMAXVER};
   my $apievent          = $hash->{HELPER}{APIEVENT};
   my $apieventpath      = $hash->{HELPER}{APIEVENTPATH};
   my $apieventmaxver    = $hash->{HELPER}{APIEVENTMAXVER};
   my $apivideostm       = $hash->{HELPER}{APIVIDEOSTM};
   my $apivideostmpath   = $hash->{HELPER}{APIVIDEOSTMPATH};
   my $apivideostmmaxver = $hash->{HELPER}{APIVIDEOSTMMAXVER};
   my $apistm            = $hash->{HELPER}{APISTM};
   my $apistmpath        = $hash->{HELPER}{APISTMPATH};
   my $apistmmaxver      = $hash->{HELPER}{APISTMMAXVER};
   my $apihm             = $hash->{HELPER}{APIHM};
   my $apihmpath         = $hash->{HELPER}{APIHMPATH};
   my $apihmmaxver       = $hash->{HELPER}{APIHMMAXVER};
   my $sid               = $hash->{HELPER}{SID};
   my $OpMode            = $hash->{OPMODE};
   my $camid             = $hash->{CAMID};
   my ($livestream,$winname,$attr,$room,$param);
   my ($url,$snapid,$httptimeout,$expmode,$motdetsc);
       
   Log3($name, 4, "$name - --- Begin Function $OpMode nonblocking ---");

   $httptimeout = $attr{$name}{httptimeout} ? $attr{$name}{httptimeout} : "4";
   
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
   
   }elsif ($OpMode eq "gopreset") {
      # Preset wird angefahren
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"GoPreset\"&position=\"$hash->{HELPER}{ALLPRESETS}{$hash->{HELPER}{GOPRESETNAME}}\"&cameraId=\"$camid\"&_sid=\"$sid\"";
      readingsSingleUpdate($hash,"state", "moving", 0); 
   
   } elsif ($OpMode eq "runpatrol") {
      # eine Überwachungstour starten
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"RunPatrol\"&patrolId=\"$hash->{HELPER}{ALLPATROLS}{$hash->{HELPER}{GOPATROLNAME}}\"&cameraId=\"$camid\"&_sid=\"$sid\"";
      readingsSingleUpdate($hash,"state", "moving", 0);
   
   } elsif ($OpMode eq "goabsptz") {
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"AbsPtz\"&cameraId=\"$camid\"&posX=\"$hash->{HELPER}{GOPTZPOSX}\"&posY=\"$hash->{HELPER}{GOPTZPOSY}\"&_sid=\"$sid\"";
      readingsSingleUpdate($hash,"state", "moving", 0); 
   
   } elsif ($OpMode eq "movestart") {
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"Move\"&cameraId=\"$camid\"&direction=\"$hash->{HELPER}{GOMOVEDIR}\"&speed=\"3\"&moveType=\"Start\"&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "movestop") {
      Log3($name, 4, "$name - Stop Camera $hash->{CAMNAME} moving to direction \"$hash->{HELPER}{GOMOVEDIR}\" now");
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"Move\"&cameraId=\"$camid\"&direction=\"$hash->{HELPER}{GOMOVEDIR}\"&moveType=\"Stop\"&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "Enable") {
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=Enable&cameraIds=$camid&_sid=\"$sid\"";     
   
   } elsif ($OpMode eq "Disable") {
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=Disable&cameraIds=$camid&_sid=\"$sid\"";     
   
   } elsif ($OpMode eq "sethomemode") {
      my $sw = $hash->{HELPER}{HOMEMODE};     # HomeMode on,off
	  $sw  = ($sw eq "on")?"true":"false";
      $url = "http://$serveraddr:$serverport/webapi/$apihmpath?on=$sw&api=$apihm&method=Switch&version=$apihmmaxver&_sid=\"$sid\"";     
   
   } elsif ($OpMode eq "getsvsinfo") {
      $url = "http://$serveraddr:$serverport/webapi/$apisvsinfopath?api=\"$apisvsinfo\"&version=\"$apisvsinfomaxver\"&method=\"GetInfo\"&_sid=\"$sid\"";   
   
   } elsif ($OpMode eq "Getcaminfo") {
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&version=\"$apicammaxver\"&method=\"GetInfo\"&cameraIds=\"$camid\"&deviceOutCap=\"true\"&streamInfo=\"true\"&ptz=\"true\"&basic=\"true\"&camAppInfo=\"true\"&optimize=\"true\"&fisheye=\"true\"&eventDetection=\"true\"&_sid=\"$sid\"";   
   
   } elsif ($OpMode eq "getStmUrlPath") {
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&version=\"$apicammaxver\"&method=\"GetStmUrlPath\"&cameraIds=\"$camid\"&_sid=\"$sid\"";   
   
   } elsif ($OpMode eq "geteventlist") {
      # Abruf der Events einer Kamera
      $url = "http://$serveraddr:$serverport/webapi/$apieventpath?api=\"$apievent\"&version=\"$apieventmaxver\"&method=\"List\"&cameraIds=\"$camid\"&locked=\"0\"&blIncludeSnapshot=\"false\"&reason=\"\"&limit=\"2\"&includeAllCam=\"false\"&_sid=\"$sid\"";   
   
   } elsif ($OpMode eq "Getptzlistpreset") {
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=$apiptz&version=$apiptzmaxver&method=ListPreset&cameraId=$camid&_sid=\"$sid\"";   
   
   } elsif ($OpMode eq "Getcapabilities") {
      # Capabilities einer Cam werden abgerufen
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=GetCapabilityByCamId&cameraId=$camid&_sid=\"$sid\"";   
   
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
   
   } elsif ($OpMode eq "runliveview" && $hash->{HELPER}{RUNVIEW} !~ /snap/) {    
      if ($hash->{HELPER}{RUNVIEW} =~ m/live/) {
          # externe URL
          $livestream = !AttrVal($name, "livestreamprefix", undef) ? "http://$serveraddr:$serverport" : AttrVal($name, "livestreamprefix", undef);
          $livestream .= "/webapi/$apivideostmpath?api=$apivideostm&version=$apivideostmmaxver&method=Stream&cameraId=$camid&format=mjpeg&_sid=\"$sid\"";
          # interne URL
          $url = "http://$serveraddr:$serverport/webapi/$apivideostmpath?api=$apivideostm&version=$apivideostmmaxver&method=Stream&cameraId=$camid&format=mjpeg&_sid=\"$sid\""; 
      
          readingsSingleUpdate($hash,"LiveStreamUrl", $livestream, 1) if(AttrVal($name, "showStmInfoFull", undef));
      } else {
          # Abspielen der letzten Aufnahme (EventId) 
          $url = "http://$serveraddr:$serverport/webapi/$apistmpath?api=$apistm&version=$apistmmaxver&method=EventStream&eventId=$hash->{HELPER}{CAMLASTRECID}&_sid=$sid";   
      }
       
      # Liveview-Link in Hash speichern -> Anzeige über SSCam_FWview, in Reading setzen für Linkversand
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
      
      # Aufnahmestatus in state abbilden mit Longpoll refresh
	  my $st;
	  (ReadingsVal("$name", "Record", "") eq "Start")?$st="on":$st="off";
	  readingsSingleUpdate($hash,"state", $st, 1); 
      
      $hash->{HELPER}{ACTIVE} = "off";
      if ($attr{$name}{debugactivetoken}) {
          Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
      }
      return;
	  
   } elsif ($OpMode eq "runliveview" && $hash->{HELPER}{RUNVIEW} =~ /snap/) {
      # den letzten Schnappschuß live anzeigen
	  my $limit   = 1;                # nur 1 Snap laden, für lastsnap_fw 
	  my $imgsize = 2;                # full size image, für lastsnap_fw 
	  my $keyword = $hash->{CAMNAME}; # nur Snaps von $camname selektieren, für lastsnap_fw   
      $url = "http://$serveraddr:$serverport/webapi/$apitakesnappath?api=\"$apitakesnap\"&method=\"List\"&version=\"$apitakesnapmaxver\"&keyword=\"$keyword\"&imgSize=\"$imgsize\"&limit=\"$limit\"&_sid=\"$sid\"";
   }
   
   Log3($name, 4, "$name - Call-Out now: $url");
   
   $param = {
            url      => $url,
            timeout  => $httptimeout,
            hash     => $hash,
            method   => "GET",
            header   => "Accept: application/json",
            callback => \&sscam_camop_parse
            };
   
   HttpUtils_NonblockingGet ($param);   
} 
  
###################################################################################  
#      Check ob Kameraoperation erfolgreich wie in "OpMOde" definiert 
#      danach Verarbeitung Nutzdaten und weiter zum Logout
###################################################################################
sub sscam_camop_parse ($) {  
   my ($param, $err, $myjson) = @_;
   my $hash             = $param->{hash};
   my $name             = $hash->{NAME};
   my $camname          = $hash->{CAMNAME};
   my $OpMode           = $hash->{OPMODE};
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
        if ($attr{$name}{debugactivetoken}) {
            Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
        }
        return;
   
   } elsif ($myjson ne "") {    
        # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, $success) = &evaljson($hash,$myjson,$param->{url});
        
        unless ($success) {
            Log3($name, 4, "$name - Data returned: ".$myjson);
			
			# ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
            $hash->{HELPER}{ACTIVE} = "off";
            if ($attr{$name}{debugactivetoken}) {
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
                    if (defined($attr{$name}{rectime}) && AttrVal($name,"rectime", undef) == 0) {
                        $rectime = 0;
                    } else {
                        $rectime = AttrVal($name, "rectime", undef) ? AttrVal($name, "rectime", undef) : $hash->{HELPER}{RECTIME_DEF};
                    }
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
                    RemoveInternalTimer($hash, "camstoprec");
                    InternalTimer(gettimeofday()+$rectime, "camstoprec", $hash);
                }      
            
			} elsif ($OpMode eq "Stop") {                
			
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Record","Stop");
                readingsBulkUpdate($hash,"state","off");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
       
                # Logausgabe
                Log3($name, 3, "$name - Camera $camname Recording stopped");
                
                # Aktualisierung Eventlist der letzten Aufnahme
                geteventlist($hash);
            
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
       
                # Logausgabe
                Log3($name, 3, "$name - HomeMode was set to \"$hash->{HELPER}{HOMEMODE}\" (all Cameras!)");
            
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
	            my $st;
	            (ReadingsVal("$name", "Record", "") eq "Start")?$st="on":$st="off";
	            readingsSingleUpdate($hash,"state", $st, 0);
                
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
                my ($slim,$ssize) = snaplimsize($hash);		
                RemoveInternalTimer($hash, "getsnapinfo");
                InternalTimer(gettimeofday()+0.6, "getsnapinfo", "$name:$slim:$ssize", 0);
            
			} elsif ($OpMode eq "getsnapinfo" || $OpMode eq "getsnapgallery" || $OpMode eq "runliveview") {
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
	                (ReadingsVal("$name", "Record", "") eq "Start")?$st="on":$st="off";
	                readingsSingleUpdate($hash,"state", $st, 1); 
					
					$hash->{HELPER}{LINK} = $data->{data}{data}[0]{imageData};
					# Longpoll refresh 
                    DoTrigger($name,"startview");					
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
					$hash->{HELPER}{SNAPHASH} = \%allsnaps;
                    
					# Direktausgabe Snaphash wenn nicht gepollt wird
					if(!AttrVal($name, "snapGalleryBoost",0)) {		    
						my $htmlCode = composegallery($name);
                        
					    for (my $k=1; (defined($hash->{HELPER}{CL}{$k})); $k++ ) {
                            asyncOutput($hash->{HELPER}{CL}{$k}, "$htmlCode");						
		                }
						delete($hash->{HELPER}{SNAPHASH});               # Snaphash löschen wenn nicht gepollt wird
						delete($hash->{HELPER}{CL});
					}

					delete($hash->{HELPER}{GETSNAPGALLERY}); # Steuerbit getsnapgallery statt getsnapinfo
				}		
				
                Log3($name, $verbose, "$name - Snapinfos of camera $camname retrieved");
            
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
            
			} elsif ($OpMode eq "gopreset") {
                # eine Presetposition wurde angefahren
                # falls Aufnahme noch läuft -> state = on setzen
                if (ReadingsVal("$name", "Record", "Stop") eq "Start") {
                    readingsSingleUpdate($hash,"state", "on", 0); 
                } else {
                    readingsSingleUpdate($hash,"state", "off", 0); 
                }
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                Log3($name, 3, "$name - Camera $camname has been moved to position \"$hash->{HELPER}{GOPRESETNAME}\"");
            
			} elsif ($OpMode eq "runpatrol") {
                # eine Tour wurde gestartet
                # falls Aufnahme noch läuft -> state = on setzen
                if (ReadingsVal("$name", "Record", "Stop") eq "Start") {
                    readingsSingleUpdate($hash,"state", "on", 0); 
                } else {
                    readingsSingleUpdate($hash,"state", "off", 0); 
                }
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                Log3($name, 3, "$name - Patrol \"$hash->{HELPER}{GOPATROLNAME}\" of camera $camname has been started successfully");
            
			} elsif ($OpMode eq "goabsptz") {
                # eine absolute PTZ-Position wurde angefahren
                # falls Aufnahme noch läuft -> state = on setzen
                if (ReadingsVal("$name", "Record", "Stop") eq "Start") {
                    readingsSingleUpdate($hash,"state", "on", 0); 
                } else {
                    readingsSingleUpdate($hash,"state", "off", 0); 
                }
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                Log3($name, 3, "$name - Camera $camname has been moved to absolute position \"posX=$hash->{HELPER}{GOPTZPOSX}\" and \"posY=$hash->{HELPER}{GOPTZPOSY}\"");
            
			} elsif ($OpMode eq "movestart") {
                # ein "Move" in eine bestimmte Richtung wird durchgeführt                 

                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"state","moving");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                Log3($name, 3, "$name - Camera $camname started move to direction \"$hash->{HELPER}{GOMOVEDIR}\" with duration of $hash->{HELPER}{GOMOVETIME} s");
                
                RemoveInternalTimer($hash, "movestop");
                InternalTimer(gettimeofday()+($hash->{HELPER}{GOMOVETIME}), "movestop", $hash);
            
			} elsif ($OpMode eq "movestop") {
                # ein "Move" in eine bestimmte Richtung wurde durchgeführt 
                # falls Aufnahme noch läuft -> state = on setzen
                
                if (ReadingsVal("$name", "Record", "Stop") eq "Start") {
                    readingsSingleUpdate($hash,"state", "on", 0); 
                } else {
                    readingsSingleUpdate($hash,"state", "off", 0); 
                }
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
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
                
                # simulieren einer anderen SVS-Version
                if (AttrVal($name, "simu_SVSversion", undef)) {
                    Log3($name, 4, "$name - another SVS-version ".AttrVal($name, "simu_SVSversion", undef)." will be simulated");
					delete $version{"SMALL"} if ($version{"SMALL"});
                    my @vl = split (/\.|-/,AttrVal($name, "simu_SVSversion", ""));
                    $version{"MAJOR"} = $vl[0];
                    $version{"MINOR"} = $vl[1];
                    $version{"BUILD"} = $vl[2]."-simu" if($vl[2]);
                }
                
                # Werte in $hash zur späteren Auswertung einfügen 
                $hash->{HELPER}{SVSVERSION} = \%version;
                
                if (!exists($data->{'data'}{'customizedPortHttp'})) {
                    delete $defs{$name}{READINGS}{SVScustomPortHttp};
                }             
               
                if (!exists($data->{'data'}{'customizedPortHttps'})) {
                    delete $defs{$name}{READINGS}{SVScustomPortHttps};
                }
                                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"SVScustomPortHttp",$data->{'data'}{'customizedPortHttp'});
                readingsBulkUpdate($hash,"SVScustomPortHttps",$data->{'data'}{'customizedPortHttps'});
                readingsBulkUpdate($hash,"SVSlicenseNumber",$data->{'data'}{'liscenseNumber'});
                readingsBulkUpdate($hash,"SVSuserPriv",$userPriv);
				if(defined($version{"SMALL"})) {
				    readingsBulkUpdate($hash,"SVSversion",$version{"MAJOR"}.".".$version{"MINOR"}.".".$version{"SMALL"}."-".$version{"BUILD"});
				} else {
				    readingsBulkUpdate($hash,"SVSversion",$version{"MAJOR"}.".".$version{"MINOR"}."-".$version{"BUILD"});
				}
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                     
                Log3($name, $verbose, "$name - Informations related to Surveillance Station retrieved");
            
			} elsif ($OpMode eq "getStmUrlPath") {
                # Parse SVS-Infos
                my $camforcemcast   = $data->{'data'}{'pathInfos'}[0]{'forceEnableMulticast'};
                my $mjpegHttp       = $data->{'data'}{'pathInfos'}[0]{'mjpegHttpPath'};
                my $multicst        = $data->{'data'}{'pathInfos'}[0]{'multicstPath'};
                my $mxpegHttp       = $data->{'data'}{'pathInfos'}[0]{'mxpegHttpPath'};
                my $unicastOverHttp = $data->{'data'}{'pathInfos'}[0]{'unicastOverHttpPath'};
                my $unicastPath     = $data->{'data'}{'pathInfos'}[0]{'unicastPath'};
                
                # Rewrite Url's falls livestreamprefix ist gesetzt
                if (AttrVal($name, "livestreamprefix", undef)) {
                    my @mjh = split(/\//, $mjpegHttp, 4);
                    $mjpegHttp = AttrVal($name, "livestreamprefix", undef)."/".$mjh[3];
                    my @mxh = split(/\//, $mxpegHttp, 4);
                    $mxpegHttp = AttrVal($name, "livestreamprefix", undef)."/".$mxh[3];
                    my @ucp = split(/[@\|:]/, $unicastPath);
                    my @lspf = split(/[\/\/\|:]/, AttrVal($name, "livestreamprefix", undef));
                    $unicastPath = $ucp[0].":".$ucp[1].":".$ucp[2]."@".$lspf[3].":".$ucp[4];
                }
                
                # StmKey extrahieren
                my @sk = split(/&StmKey=/, $mjpegHttp);
                my $stmkey = $sk[1];
                $stmkey =~ tr/"//d;
                
                # Readings löschen falls sie nicht angezeigt werden sollen (showStmInfoFull)
                if (!AttrVal($name, "showStmInfoFull", undef)) {
                    delete($defs{$name}{READINGS}{StmKeymjpegHttp}) if ($defs{$name}{READINGS}{StmKeymjpegHttp});
                    delete($defs{$name}{READINGS}{StmKeyUnicst}) if ($defs{$name}{READINGS}{StmKeyUnicst});
                }
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"CamForceEnableMulticast",$camforcemcast);
                readingsBulkUpdate($hash,"StmKey",$stmkey);
                readingsBulkUpdate($hash,"StmKeymjpegHttp",$mjpegHttp)  if (AttrVal($name, "showStmInfoFull", undef));
                # readingsBulkUpdate($hash,"StmKeymxpegHttp",$mxpegHttp);
                readingsBulkUpdate($hash,"StmKeyUnicst",$unicastPath) if (AttrVal($name, "showStmInfoFull", undef));
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
                
                $exposuremode = $data->{'data'}->{'cameras'}->[0]->{'exposure_mode'};
                if ($exposuremode == 0) {
                    $exposuremode = "Auto";
                    }
                    elsif ($exposuremode == 1) {
                    $exposuremode = "Day";
                    }
                    elsif ($exposuremode == 2) {
                    $exposuremode = "Night";
                    }
                    elsif ($exposuremode == 3) {
                    $exposuremode = "Schedule";
                    }
                    elsif ($exposuremode == 4) {
                    $exposuremode = "Unknown";
                    }
                    
                $exposurecontrol = $data->{'data'}->{'cameras'}->[0]->{'exposure_control'};
                if ($exposurecontrol == 0) {
                    $exposurecontrol = "Auto";
                    }
                    elsif ($exposurecontrol == 1) {
                    $exposurecontrol = "50HZ";
                    }
                    elsif ($exposurecontrol == 2) {
                    $exposurecontrol = "60HZ";
                    }
                    elsif ($exposurecontrol == 3) {
                    $exposurecontrol = "Hold";
                    }
                    elsif ($exposurecontrol == 4) {
                    $exposurecontrol = "Outdoor";
                    }
                    elsif ($exposurecontrol == 5) {
                    $exposurecontrol = "None";
                    }
                    elsif ($exposurecontrol == 6) {
                    $exposurecontrol = "Unknown";
                    }
                    
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"CamLiveMode",$camLiveMode);
                readingsBulkUpdate($hash,"CamExposureMode",$exposuremode);
                readingsBulkUpdate($hash,"CamExposureControl",$exposurecontrol);
                readingsBulkUpdate($hash,"CamModel",$data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camModel'});
                readingsBulkUpdate($hash,"CamRecShare",$data->{'data'}->{'cameras'}->[0]->{'camRecShare'});
                readingsBulkUpdate($hash,"CamRecVolume",$data->{'data'}->{'cameras'}->[0]->{'camRecVolume'});
                readingsBulkUpdate($hash,"CamIP",$data->{'data'}->{'cameras'}->[0]->{'host'});
                readingsBulkUpdate($hash,"CamVendor",$data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camVendor'});
                readingsBulkUpdate($hash,"CamPreRecTime",$data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camPreRecTime'});
                readingsBulkUpdate($hash,"CamPort",$data->{'data'}->{'cameras'}->[0]->{'port'});
                readingsBulkUpdate($hash,"CamPtSpeed",$data->{'data'}->{'cameras'}->[0]->{'ptSpeed'});
                readingsBulkUpdate($hash,"CamblPresetSpeed",$data->{'data'}->{'cameras'}->[0]->{'blPresetSpeed'});
                readingsBulkUpdate($hash,"CamVideoMirror",$data->{'data'}->{'cameras'}->[0]->{'video_mirror'});
                readingsBulkUpdate($hash,"CamVideoFlip",$data->{'data'}->{'cameras'}->[0]->{'video_flip'});
                readingsBulkUpdate($hash,"Availability",$camStatus);
                readingsBulkUpdate($hash,"DeviceType",$deviceType);
                readingsBulkUpdate($hash,"LastUpdateTime",$update_time);
                readingsBulkUpdate($hash,"Record",$recStatus);
                readingsBulkUpdate($hash,"UsedSpaceMB",$data->{'data'}->{'cameras'}->[0]->{'volume_space'});
                readingsBulkUpdate($hash,"VideoFolder",AttrVal($name, "videofolderMap", undef) ? AttrVal($name, "videofolderMap", undef) : $data->{'data'}->{'cameras'}->[0]->{'folder'});
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                            
                # Logausgabe
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
                
                # Setreading 
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
                readingsBulkUpdate($hash,"CapPTZPan",$ptzpan);
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
                while ($cnt < $presetcnt) {
                    # my $presid = $data->{'data'}->{'presets'}->[$cnt]->{'id'};
                    my $presid = $data->{'data'}->{'presets'}->[$cnt]->{'position'};
                    my $presname = $data->{'data'}->{'presets'}->[$cnt]->{'name'};
                    $allpresets{$presname} = "$presid";
                    $cnt += 1;
                }
                    
                # Presethash in $hash einfügen
                $hash->{HELPER}{ALLPRESETS} = \%allpresets;

                my @preskeys = sort(keys(%allpresets));
                my $presetlist = join(",",@preskeys);

                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Presets",$presetlist);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                  
                            
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
            $error = experror($hash,$errorcode);
			
		    if ($errorcode =~ /(105|401)/) {
			   Log3($name, 2, "$name - ERROR - $errorcode - $error in operation $OpMode -> try new login");
		       return sscam_login($hash,'sscam_getapisites');
		    }

            # Setreading 
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode",$errorcode);
            readingsBulkUpdate($hash,"Error",$error);
            readingsEndUpdate($hash, 1);
       
            # Logausgabe
            Log3($name, 2, "$name - ERROR - Operation $OpMode of Camera $camname was not successful. Errorcode: $errorcode - $error");
       }
   }
  
  # Token freigeben   
  $hash->{HELPER}{ACTIVE} = "off";

  if ($attr{$name}{debugactivetoken}) {
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
sub sscam_login ($$) {
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
  Log3($name, 4, "$name - --- Begin Function sscam_login ---");
  
  # Credentials abrufen
  my ($success, $username, $password) = getcredentials($hash,0);
  
  unless ($success) {
      Log3($name, 2, "$name - Credentials couldn't be retrieved successfully - make sure you've set it with \"set $name credentials <username> <password>\"");
      
      $hash->{HELPER}{ACTIVE} = "off";
      if ($attr{$name}{debugactivetoken}) {
          Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
      }      
      return;
  }
  
  if($hash->{HELPER}{LOGINRETRIES} >= $lrt) {
      # login wird abgebrochen, Freigabe Funktionstoken
      $hash->{HELPER}{ACTIVE} = "off"; 
      if ($attr{$name}{debugactivetoken}) {
          Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
      }
	  Log3($name, 2, "$name - ERROR - Login of User $username unsuccessful"); 
      return;
  }

  my $httptimeout = $attr{$name}{httptimeout} ? $attr{$name}{httptimeout} : "4";
  
  Log3($name, 5, "$name - HTTP-Call login will be done with httptimeout-Value: $httptimeout s");
  
  my $urlwopw;      # nur zur Anzeige bei verbose >= 4 und "showPassInLog" == 0
  
  # sid in Quotes einschliessen oder nicht -> bei Problemen mit 402 - Permission denied
  my $sid = AttrVal($name, "noQuotesForSID", "0") == 1 ? "sid" : "\"sid\"";
  
  if (defined($attr{$name}{session}) and $attr{$name}{session} eq "SurveillanceStation") {
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
               callback => \&sscam_login_return
           };
   HttpUtils_NonblockingGet ($param);
}

sub sscam_login_return ($) {
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
        
      return sscam_login($hash,$fret);
   
   } elsif ($myjson ne "") {
        # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)   
        
		# Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, $success) = evaljson($hash,$myjson,$param->{url});
        unless ($success) {
            Log3($name, 4, "$name - no JSON-Data returned: ".$myjson);
            $hash->{HELPER}{ACTIVE} = "off";
            
            if ($attr{$name}{debugactivetoken}) {
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
            my $error = experrorauth($hash,$errorcode);

            # Setreading 
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode",$errorcode);
            readingsBulkUpdate($hash,"Error",$error);
            readingsEndUpdate($hash, 1);
       
            # Logausgabe
            Log3($name, 3, "$name - Login of User $username unsuccessful. Code: $errorcode - $error - try again"); 
             
            return sscam_login($hash,$fret);
       }
   }
return sscam_login($hash,$fret);
}

###################################################################################  
#      Funktion logout

sub logout_nonbl ($) {
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
    
    # logout wird ausgeführt, Rückkehr wird mit "logoutret_nonbl" verarbeitet

    Log3($name, 4, "$name - --- Begin Function logout nonblocking ---");
    
    $httptimeout = $attr{$name}{httptimeout} ? $attr{$name}{httptimeout} : "4";
    
    Log3($name, 5, "$name - HTTP-Call will be done with httptimeout-Value: $httptimeout s");
  
    if (defined($attr{$name}{session}) and $attr{$name}{session} eq "SurveillanceStation") {
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
                callback => \&logout_return
             };
   
    HttpUtils_NonblockingGet ($param);
}

sub logout_return ($) {  
   my ($param, $err, $myjson) = @_;
   my $hash                   = $param->{hash};
   my $name                   = $hash->{NAME};
   my $sid                    = $hash->{HELPER}{SID};
   my ($success, $username)   = getcredentials($hash,0);
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
       ($hash, $success) = &evaljson($hash,$myjson,$param->{url});
        
       unless ($success) {
           Log3($name, 4, "$name - Data returned: ".$myjson);
            
           $hash->{HELPER}{ACTIVE} = "off";
            
           if ($attr{$name}{debugactivetoken}) {
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
           # Session-ID aus Helper-hash löschen
           delete $hash->{HELPER}{SID};
             
           # Logausgabe
           Log3($name, 4, "$name - Session of User $username has ended - SID: $sid has been deleted");
             
       } else {
           # Errorcode aus JSON ermitteln
           $errorcode = $data->{'error'}->{'code'};

           # Fehlertext zum Errorcode ermitteln
           $error = &experrorauth($hash,$errorcode);
    
           # Logausgabe
           Log3($name, 2, "$name - ERROR - Logout of User $username was not successful. Errorcode: $errorcode - $error");
       }
   }   
   # ausgeführte Funktion ist erledigt (auch wenn logout nicht erfolgreich), Freigabe Funktionstoken
   $hash->{HELPER}{ACTIVE} = "off";  
   
   if ($attr{$name}{debugactivetoken}) {
       Log3($name, 3, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
   }
return;
}

###############################################################################
#   Test ob JSON-String empfangen wurde
sub evaljson { 
  my ($hash,$myjson,$url)= @_;
  my $success = 1;
  my $e;
  
  eval {decode_json($myjson)} or do 
  {
      $success = 0;
      $e = $@;
  
      # Setreading 
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,"Errorcode","none");
      readingsBulkUpdate($hash,"Error","malformed JSON string received");
      readingsEndUpdate($hash, 1);  
  };
return($hash,$success);
}

###############################################################################
# Schnappschußgalerie abrufen (snapGalleryBoost) oder nur Info des letzten Snaps
sub snaplimsize ($) {      
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
# Clienthash übernehmen oder zusammenstellen
# Identifikation ob über FHEMWEB ausgelöst oder nicht -> erstellen $hash->CL
sub getclhash ($) {      
  my ($hash)= @_;
  my $name  = $hash->{NAME};
  my $ret;

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
              Log3($name, 4, "$name - snapGallery Clienthash: $key -> $val");
          }
	  }
  } else {
      Log3($name, 2, "$name - snapGallery Clienthash was neither delivered nor created !");
	  $ret = "Clienthash was neither delivered nor created. Can't use asynchronous output for snapGallery.";
  }
  
return ($ret);
}


###############################################################################
#   Schnappschußgalerie zusammenstellen
sub composegallery ($;$$) { 
  my ($name,$wlname) = @_;
  my $hash     = $defs{$name};
  my $camname  = $hash->{CAMNAME};
  my $allsnaps = $hash->{HELPER}{SNAPHASH}; # = \%allsnaps
  my $sgc      = AttrVal($name,"snapGalleryColumns",3);          # Anzahl der Images in einer Tabellenzeile
  my $lss      = ReadingsVal($name, "LastSnapTime", " ");        # Zeitpunkt neueste Aufnahme
  my $lang     = AttrVal("global","language","EN");              # Systemsprache       
  my $limit    = $hash->{HELPER}{SNAPLIMIT};                     # abgerufene Anzahl Snaps
  my $totalcnt = $hash->{HELPER}{TOTALCNT};                      # totale Anzahl Snaps
  $limit       = $totalcnt if ($limit > $totalcnt);              # wenn weniger Snaps vorhanden sind als $limit -> Text in Anzeige korrigieren
  my $lupt     = ((ReadingsTimestamp($name,"LastSnapTime"," ") gt ReadingsTimestamp($name,"LastUpdateTime"," ")) 
                 ? ReadingsTimestamp($name, "LastSnapTime", " ") 
				 : ReadingsTimestamp($name, "LastUpdateTime", " "));  # letzte Aktualisierung
  $lupt =~ s/ / \/ /;
  
  my $ha = AttrVal($name, "snapGalleryHtmlAttr", undef)?AttrVal($name, "snapGalleryHtmlAttr", undef):AttrVal($name, "htmlattr", 'width="500" height="325"');

  # falls "composegallery" durch ein mit mit "createSnapGallery" angelegtes Device aufgerufen wird
  my ($devWlink,$wlhash,$wlha,$wlalias);
  if ($wlname) {
      $wlalias  = $attr{$wlname}{alias}?$attr{$wlname}{alias}:$wlname;   # Linktext als Aliasname oder Devicename setzen
      $devWlink = "<a href=\"/fhem?detail=$wlname\">$wlalias</a>"; 
      $wlhash   = $defs{$wlname};
      $wlha     = $attr{$wlname}{htmlattr}; 
      $ha       = (defined($wlha))?$wlha:$ha;  # htmlattr vom weblink-Device übernehmen falls von wl-Device aufgerufen und gesetzt   
  } else {
      $devWlink = " ";
  }
  
  # wenn Weblink genutzt wird und attr "snapGalleryBoost" nicht gesetzt ist -> Warnung in Gallerie ausgeben
  my $sgbnote = " ";
  if($wlname && !AttrVal($name,"snapGalleryBoost",0)) {
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
  $htmlCode .= sprintf( "$devWlink<br> <div class=\"makeTable wide\"; style=\"text-align:center\"> $header <br>");
  $htmlCode .= "<table class=\"block wide internals\">";
  $htmlCode .= "<tbody>";
  $htmlCode .= "<tr class=\"odd\">";
  my $cell   = 1;
  
  foreach my $key (@as) {
      $ct = $allsnaps->{$key}{createdTm};
	  my $html = sprintf( "<td>$ct<br /> <img $gattr src=\"data:image/jpeg;base64,$allsnaps->{$key}{imageData}\" /> </td>" );

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
#  Auflösung Errorcodes bei Login / Logout
sub experrorauth {
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

sub experror {
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
=item summary    operates surveillance cameras defined in Synology Surveillance Station
=item summary_DE steuert Kameras welche der Synology Surveillance Station
=begin html

<a name="SSCam"></a>
<h3>SSCam</h3>
<ul>
  Using this Module you are able to operate cameras which are defined in Synology Surveillance Station (SVS). <br>
  At present the following functions are available: <br><br>
   <ul>
    <ul>
       <li>Start a Recording</li>
       <li>Stop a Recording (using command or automatically after the &lt;RecordTime&gt; period</li>
       <li>Trigger a Snapshot </li>
       <li>Deaktivate a Camera in Synology Surveillance Station</li>
       <li>Activate a Camera in Synology Surveillance Station</li>
       <li>Control of the exposure modes day, night and automatic </li>
       <li>switchover the motion detection by camera, by SVS or to deactivate  </li>
       <li>control of motion detection parameters sensitivity, threshold, object size and percentage for release </li>
       <li>Retrieval of Camera Properties (also by Polling) as well as informations about the installed SVS-package</li>
       <li>Move to a predefined Preset-position (at PTZ-cameras) </li>
       <li>Start a predefined Patrol (at PTZ-cameras) </li>
       <li>Positioning of PTZ-cameras to absolute X/Y-coordinates  </li>
       <li>continuous moving of PTZ-camera lense   </li>
       <li>trigger of external events 1-10 (action rules in SVS)   </li>
       <li>start and stop of camera livestreams, show the last recording and snapshot embedded </li>
       <li>fetch of livestream-Url's with key (login not needed in that case)   </li>
       <li>playback of last recording and playback the last snapshot  </li>
	   <li>switch the Surveillance Station HomeMode on / off  </li>
	   <li>create a gallery of the last 1-10 snapshots (as a Popup or permanent weblink-Device)  </li><br>
    </ul>
   </ul>
   The recordings and snapshots will be stored in Synology Surveillance Station (SVS) and are managed like the other (normal) recordings / snapshots defined by Surveillance Station rules.<br>
   For example the recordings are stored for a defined time in Surveillance Station and will be deleted after that period.<br><br>
    
   If you like to discuss or help to improve this module please use FHEM-Forum with link: <br>
   <a href="http://forum.fhem.de/index.php/topic,45671.msg374390.html#msg374390">49_SSCam: Fragen, Hinweise, Neuigkeiten und mehr rund um dieses Modul</a>.<br><br>
  
<b> Prerequisites </b> <br><br>
    This module uses the CPAN-module JSON. Please consider to install this package (Debian: libjson-perl).<br>
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
    <code>define &lt;name&gt; SSCAM &lt;Cameraname in SVS&gt; &lt;ServerAddr&gt; [Port]  </code><br>
    <br>
    Defines a new camera device for SSCam. At first the devices have to be set up and operable in Synology Surveillance Station 7.0 and above. <br><br>
    
    The Modul SSCam ist based on functions of Synology Surveillance Station API. <br>
    Please refer the <a href="http://global.download.synology.com/download/Document/DeveloperGuide/Surveillance_Station_Web_API_v2.0.pdf">Web API Guide</a>. <br><br>
    
    Currently only HTTP-protocol is supported to call Synology DS. <br><br>  

    The parameters are in detail:
   <br>
   <br>    
     
   <table>
    <colgroup> <col width=15%> <col width=85%> </colgroup>
    <tr><td>name:         </td><td>the name of the new device to use in FHEM</td></tr>
    <tr><td>Cameraname:   </td><td>Cameraname as defined in Synology Surveillance Station, Spaces are not allowed in Cameraname !</td></tr>
    <tr><td>ServerAddr:   </td><td>IP-address of Synology Surveillance Station Host. <b>Note:</b> avoid using hostnames because of DNS-Calls are not unblocking in FHEM </td></tr>
    <tr><td>Port:         </td><td>optional - the port of synology surveillance station, if not set the default of 5000 (HTTP only) is used</td></tr>
   </table>

    <br><br>

    <b>Example:</b>
     <pre>
      define CamCP SSCAM Carport 192.168.2.20 [5000]  
    </pre>
    
    
    When a new Camera is defined, as a start the recordingtime of 15 seconds will be assigned to the device.<br>
    Using the <a href="#SSCamattr">attribute</a> "rectime" you can adapt the recordingtime for every camera individually.<br>
    The value of "0" for rectime will lead to an endless recording which has to be stopped by a "set &lt;name&gt; off" command.<br>
    Due to a Log-Entry with a hint to that circumstance will be written. <br><br>
    
    If the <a href="#SSCamattr">attribute</a> "rectime" would be deleted again, the default-value for recording-time (15s) become active.<br><br>

    With <a href="#SSCamset">command</a> <b>"set &lt;name&gt; on [rectime]"</b> a temporary recordingtime is determinded which would overwrite the dafault-value of recordingtime <br>
    and the attribute "rectime" (if it is set) uniquely. <br><br>

    In that case the command <b>"set &lt;name&gt; on 0"</b> leads also to an endless recording as well.<br><br>
    
    If you have specified a pre-recording time in SVS it will be considered too. <br><br><br>
    
    
    <a name="SSCam_Credentials"></a>
    <b>Credentials </b><br><br>
    
    After a camera-device is defined, firstly it is needed to save the credentials. This will be done with command:
   
    <pre> 
     set &lt;name&gt; credentials &lt;username&gt; &lt;password&gt;
    </pre>
    
    The password lenth has a maximum of 20 characters. <br> 
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
      <tr><td><li>set ... disable            </td><td> session: ServeillanceStation - manager       </li></td></tr>
      <tr><td><li>set ... enable             </td><td> session: ServeillanceStation - manager       </li></td></tr>
      <tr><td><li>set ... expmode            </td><td> session: ServeillanceStation - manager       </li></td></tr>
      <tr><td><li>set ... motdetsc           </td><td> session: ServeillanceStation - manager       </li></td></tr>
      <tr><td><li>set ... goPreset           </td><td> session: ServeillanceStation - observer with privilege objective control of camera  </li></td></tr>
      <tr><td><li>set ... runPatrol          </td><td> session: ServeillanceStation - observer with privilege objective control of camera  </li></td></tr>
      <tr><td><li>set ... goAbsPTZ           </td><td> session: ServeillanceStation - observer with privilege objective control of camera  </li></td></tr>
      <tr><td><li>set ... move               </td><td> session: ServeillanceStation - observer with privilege objective control of camera  </li></td></tr>
      <tr><td><li>set ... runView            </td><td> session: ServeillanceStation - observer with privilege liveview of camera </li></td></tr>
      <tr><td><li>set ... snapGallery        </td><td> session: ServeillanceStation - observer    </li></td></tr>
	  <tr><td><li>set ... extevent           </td><td> session: DSM - user as member of admin-group   </li></td></tr>
      <tr><td><li>set ... stopView           </td><td> -                                          </li></td></tr>
      <tr><td><li>set ... credentials        </td><td> -                                          </li></td></tr>
      <tr><td><li>get ... caminfoall         </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>get ... eventlist          </td><td> session: ServeillanceStation - observer    </li></td></tr>
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
    
  Currently there are the following options for "Set &lt;name&gt; ..."  : <br><br>

  <table>
  <colgroup> <col width=35%> <col width=65%> </colgroup>
      <tr><td>"on [rectime]":                                      </td><td>starts a recording. The recording will be stopped automatically after a period of [rectime] </td></tr>
      <tr><td>                                                     </td><td>if [rectime] = 0 an endless recording will be started </td></tr>
      <tr><td>"off" :                                              </td><td>stopps a running recording manually or using other events (e.g. with at, notify)</td></tr>
      <tr><td>"snap":                                              </td><td>triggers a snapshot of the relevant camera and store it into Synology Surveillance Station</td></tr>
      <tr><td>"disable":                                           </td><td>deactivates a camera in Synology Surveillance Station</td></tr>
      <tr><td>"enable":                                            </td><td>activates a camera in Synology Surveillance Station</td></tr>
      <tr><td>"createSnapGallery":                                 </td><td>creates a snapshot gallery as a permanent (weblink)Device</td></tr>      
	  <tr><td>"credentials &lt;username&gt; &lt;password&gt;":     </td><td>save a set of credentils </td></tr>
      <tr><td>"expmode [ day | night | auto ]":                    </td><td>set the exposure mode to day, night or auto </td></tr>
      <tr><td>"extevent [ 1-10 ]":                                 </td><td>triggers the external event 1-10 (see actionrule editor in SVS) </td></tr>
      <tr><td>"motdetsc [ camera | SVS | disable ]":               </td><td>set motion detection to the desired mode </td></tr>
      <tr><td>"goPreset &lt;Presetname&gt;":                       </td><td>moves a PTZ-camera to a predefinied Preset-position  </td></tr>
      <tr><td>"runPatrol &lt;Patrolname&gt;":                      </td><td>starts a predefinied patrol (PTZ-cameras)  </td></tr>
      <tr><td>"snapGallery [1-10]":                                </td><td>creates an output of the last [n] snapshots  </td></tr>      
	  <tr><td>"goAbsPTZ [ X Y | up | down | left | right ]":       </td><td>moves a PTZ-camera to a absolute X/Y-coordinate or to direction up/down/left/right  </td></tr>
      <tr><td>"move [ up | down | left | right | dir_X ]":         </td><td>starts a continuous move of PTZ-camera to direction up/down/left/right or dir_X  </td></tr> 
      <tr><td>"runView [image | lastrec | lastrec_open | link | link_open &lt;room&gt; ]":  </td><td>starts a livestream as embedded image or link  </td></tr> 
      <tr><td>"stopView":                                          </td><td>stops a camera livestream  </td></tr> 
  </table>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; credentials &lt;username&gt; &lt;password&gt; </b></li> <br>
  
  set username / password combination for access the Synology Surveillance Station. 
  See <a href="#SSCam_Credentials">Credentials</a><br> for further informations.
  
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; createSnapGallery </b></li> <br>
  
  A snapshot gallery will be created as a permanent (weblink)Device. The device will be provided in room "SnapGallery".
  With the "snapGallery..."-<a href="#SSCamattr">attributes</a> respectively the weblink-device specific attributes (what was created)
  you are able to manipulate the properties of the new snapshot gallery device. <br> 
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; [enable|disable] </b></li> <br>
  
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
  <li><b> set &lt;name&gt; expmode [day|night|auto] </b></li> <br>
  
  With this command you are able to control the exposure mode and can set it to day, night or automatic mode. 
  Thereby, for example, the behavior of camera LED's will be suitable controlled. 
  The successful switch will be reported by the reading CamExposureMode (command "get ... caminfoall"). <br><br>
  
  <b> Note: </b><br>
  The successfully execution of this function depends on if SVS supports that functionality of the connected camera.
  Is the field for the Day/Night-mode shown greyed in SVS -&gt; IP-camera -&gt; optimization -&gt; exposure mode, this function will be probably unsupported.  
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; extevent [ 1-10 ] </b></li> <br>
  
  This command triggers an external event (1-10) in SVS. 
  The actions which will are used have to be defined in the actionrule editor of SVS at first. There are the events 1-10 possible.
  In the message application of SVS you may select Email, SMS or Mobil (DS-Cam) messages to release if an external event has been triggerd.
  Further informations can be found in the online help of the actionrule editor.
  The used user needs to be a member of the admin-group and DSM-session is needed too.
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; goAbsPTZ [ X Y | up | down | left | right ] </b></li> <br>
  
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
  <li><b> set &lt;name&gt; goPreset &lt;Preset&gt; </b></li> <br>
  
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
  <li><b> set &lt;name&gt; homeMode [on | off] </b></li> <br>
  
  Switch the HomeMode of the Surveillance Station on or off. 
  Further informations about HomeMode you can find in the <a href="https://www.synology.com/en-global/knowledgebase/Surveillance/help/SurveillanceStation/home_mode">Synology Onlinehelp</a>.
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; motdetsc [camera|SVS|disable] </b></li> <br>
  
  The command "motdetsc" (stands for "motion detection source") switchover the motion detection to the desired mode.
  If motion detection will be done by camera / SVS without any parameters, the original camera motion detection settings are kept.
  The successful execution of that opreration one can retrace by the state in SVS -&gt; IP-camera -&gt; event detection -&gt; motion. <br><br>
  
  For the motion detection further parameter can be specified. The available options for motion detection by SVS are "sensitivity" and "threshold". <br><br>
  
  <ul>
  <table>
  <colgroup> <col width=50%> <col width=50%> </colgroup>
      <tr><td>set <name> motdetsc SVS [sensitivity] [threshold]  </td><td># command pattern  </td></tr>
      <tr><td>set <name> motdetsc SVS 91 30                      </td><td># set the sensitivity to 91 and threshold to 30  </td></tr>
      <tr><td>set <name> motdetsc SVS 0 40                       </td><td># keep the old value of sensitivity, set threshold to 40  </td></tr>
      <tr><td>set <name> motdetsc SVS 15                         </td><td># set the sensitivity to 15, threshold keep unchanged  </td></tr>
  </table>
  </ul>
  <br><br>
  
  If the motion detection is used by camera, there are the options "sensitivity", "object size", "percentage for release" available. <br><br>
  
  <ul>
  <table>
  <colgroup> <col width=50%> <col width=50%> </colgroup>
      <tr><td>set <name> motdetsc camera [sensitivity] [threshold] [percentage] </td><td># command pattern  </td></tr>
      <tr><td>set <name> motdetsc camera 89 0 20                                </td><td># set the sensitivity to 89, percentage to 20  </td></tr>
      <tr><td>set <name> motdetsc camera 0 40 10                                </td><td># keep old value for sensitivity, set threshold to 40, percentage to 10  </td></tr>
      <tr><td>set <name> motdetsc camera 30                                     </td><td># set the sensitivity to 30, other values keep unchanged  </td></tr>
      </table>
  </ul>
  <br><br>
  
  Please consider always the sequence of parameters. Unwanted options have to be set to "0" if further options which have to be changed are follow (see example above).
  The numerical values are between 1 - 99 (except special case "0"). <br><br>
  
  The each available options are dependend of camera type respectively the supported functions by SVS. Only the options can be used they are available in 
  SVS -&gt; edit camera -&gt; motion detection. Further informations please read in SVS online help. <br><br>
  
  With the command "get ... caminfoall" the <a href="#SSCamreadings">Reading</a> "CamMotDetSc" also will be updated which documents the current setup of motion detection. 
  Only the parameters and parameter values supported by SVS at present will be shown. The camera itself may offer further  options to adjust. <br><br>
  
  Example:
  <pre>
   CamMotDetSc    SVS, sensitivity: 76, threshold: 55
  </pre>
  </ul>
  <br><br>
    
  <ul>
  <li><b> set &lt;name&gt; move [ up | down | left | right | dir_X ] [seconds] </b></li> <br>
  
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
  <li><b>set &lt;name&gt; [on|off] </b></li> <br>
   
  The command "set &lt;name&gt; on" starts a recording. The default recording time takes 15 seconds. It can be changed by the <a href="#SSCamattr">attribute</a> "rectime" individualy. 
  With the <a href="#SSCamattr">attribute</a> (respectively the default value) provided recording time can be overwritten once by "set &lt;name&gt; on [rectime]".
  The recording will be stopped after processing time "rectime"automatically.<br>

  A special case is the start using "set &lt;name&gt; on 0" respectively the attribute value "rectime = 0". In that case a endless-recording will be started. One have to stop this recording
  by command "set &lt;name&gt; off" explicitely.<br>

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
  <li><b> set &lt;name&gt; runPatrol &lt;Patrolname&gt; </b></li> <br>
  
  This commans starts a predefined patrol (tour) of a PTZ-camera. <br>
  At first the patrol has to be predefined in the Synology Surveillance Station. It can be done in the PTZ-control of IP-Kamera Setup -&gt; PTZ-control -&gt; patrol.
  The patrol tours will be read with command "get &lt;name&gt; caminfoall" which is be executed automatically when FHEM restarts.
  The import process can be repeated regular by camera polling. A long polling interval is recommendable in this case because of the patrols are only will be changed 
  if the user change it in the IP-camera setup itself. 
  Further informations for creating patrols you can get in the online-help of Surveillance Station.
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; runView [live_fw | live_link | live_open [&lt;room&gt;] | lastrec_fw | lastrec_open [&lt;room&gt;] | lastsnap_fw]  </b></li> <br>
  
  With "live_fw, live_link, live_open" a livestream (mjpeg-stream) of a camera will be started, either as embedded image 
  or as a generated link. <br>
  The option "live_open" starts a new browser window. If the optional &lt;room&gt; was set, the window will only be
  started if the specified room is currently opend in a browser session. <br><br> 
  
  The command <b>"set &lt;name&gt; runView lastsnap_fw"</b> shows the last snapshot of the camera embedded in room- or detailview. <br><br>
  
  Access to the last recording of a camera can be done using "lastrec_fw" respectively "lastrec_open".
  The recording will be opened in iFrame. So there are some control elements available, e.g. to increase/descrease 
  reproduce speed. <br>
  
  The kind of windows in FHEMWEB can be affected by HTML-tags in <a href="#SSCamattr">attribute</a> "htmlattr". 
  <br><br>
  
  <b>Examples:</b><br>
  <pre>
    attr &lt;name&gt; htmlattr width="500" height="375"
    attr &lt;name&gt; htmlattr width="700",height="525",top="200",left="300"
  </pre>
  
  The command <b>"set &lt;name&gt; runView live_open"</b> starts the stream immediately in a new browser window (longpoll=1 
  must be set for WEB). 
  A browser window will be initiated to open for every FHEM session which is active. If you want to change this behavior, 
  you can use command <b>"set &lt;name&gt; runView live_open &lt;room&gt;"</b>. It initiates open a browser window in that 
  FHEM session which has just opend the room &lt;room&gt;.
  
  The settings of <a href="#SSCamattr">attribute</a> "livestreamprefix" overwrites the data for protocol, servername and 
  port in <a href="#SSCamreadings">reading</a> "LiveStreamUrl".
  By "livestreamprefix" the LivestreamURL (is shown if <a href="#SSCamattr">attribute</a> "showStmInfoFull" is set) can 
  be modified and used for distribution and external access to SVS livestream. <br><br>
  
  <b>Example:</b><br>
  <pre>
    attr &lt;name&gt; livestreamprefix https://&lt;Servername&gt;:&lt;Port&gt;
  </pre>
  
  The livestream can be stopped again by command <b>"set &lt;name&gt; stopView"</b>.
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; snap </b></li> <br>
  
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
  <li><b> set &lt;name&gt; snapGallery [1-10] </b></li> <br>
  
  The command is only available if the attribute "snapGalleryBoost=1" is set. <br>
  It creates an output of the last [x] snapshots as well as "get ... snapGallery".  But differing from "get" with
  <a href="#SSCamattr">attribute</a> "snapGalleryBoost=1" no popup will be created. The snapshot gallery will be depicted as
  an browserpage instead. All further functions and attributes are appropriate the <a href="#SSCamget">"get &lt;name&gt; snapGallery"</a>
  command. <br>
  If you want create a snapgallery output by triggering, e.g. with an "at" or "notify", you should use the 
  <a href="#SSCamget">"get &lt;name&gt; snapGallery"</a> command instead of "set".
  </ul>
  <br><br>
  
 </ul>
<br>


<a name="SSCamget"></a>
<b>Get</b>
 <ul>
  With SSCam the properties of SVS and defined Cameras could be retrieved. Actually it could be done by following commands:
  <pre>
      get &lt;name&gt; caminfoall
      get &lt;name&gt; eventlist
      get &lt;name&gt; scanVirgin
      get &lt;name&gt; snapGallery
      get &lt;name&gt; stmUrlPath
      get &lt;name&gt; svsinfo
      get &lt;name&gt; snapfileinfo
      get &lt;name&gt; snapinfo
  </pre>
  
  With command <b>"get &lt;name&gt; caminfoall"</b> dependend of the type of Camera (e.g. Fix- or PTZ-Camera) the available properties will be retrieved and provided as Readings.<br>
  For example the Reading "Availability" will be set to "disconnected" if the Camera would be disconnected from Synology Surveillance Station and can be used for further 
  processing like creating events. <br>
  By command <b>"get &lt;name&gt; eventlist"</b> the <a href="#SSCamreadings">Reading</a> "CamEventNum" and "CamLastRecord" will be refreshed which containes the total number of in SVS 
  registered camera events and the path / name of the last recording. 
  This command will be implicit executed when "get ... caminfoall" is running. <br>
  The <a href="#SSCamattr">attribute</a> "videofolderMap" replaces the content of reading "VideoFolder". You can use it for example if you have mounted the videofolder of SVS 
  under another name or path and want to access by your local pc.
  Using <b>"get &lt;name&gt; snapfileinfo"</b> the filename of the last snapshot will be retrieved. This command will be executed with <b>"get &lt;name&gt; snap"</b> automatically. <br>
  The command <b>"get &lt;name&gt; svsinfo"</b> is not really dependend on a camera, but rather a command to determine common informations about the installed SVS-version and other properties. <br>
  The functions "caminfoall" and "svsinfo" will be executed automatically once-only after FHEM restarts to collect some relevant informations for camera control. <br>
  Please consider to save the <a href="#SSCam_Credentials">credentials</a> what will be used for login to DSM or SVS !
  <br><br>

  <ul>
  <li><b> get &lt;name&gt; scanVirgin </b></li> <br>
  
  This command is similar to get caminfoall, informations relating to SVS and the camera will be retrieved. 
  In difference to caminfoall in either case a new session ID will be generated (do a new login), the camera ID will be
  new identified and all necessary API-parameters will be new investigated.  
  </ul>
  <br><br> 
  
  <ul>
  <li><b> get &lt;name&gt; snapGallery [1-10] </b></li> <br>
  
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
  <li><b> get &lt;name&gt; snapinfo </b></li> <br>
  
  Informations about snapshots will be retrieved. Heplful if snapshots are not triggerd by SSCam, but by motion detection of the camera or surveillance
  station instead.
  </ul>
  <br><br> 
  
  <ul>
  <li><b> get &lt;name&gt; stmUrlPath </b></li> <br>
  
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
  
  cameraId (INTERNAL), StmKey has to be replaced by valid values. <br><br>
  
  <b>Note:</b> <br>
  
  If you use the stream-call from external and replace hostname / port with valid values and open your router ip ports, please make shure that no
  unauthorized person could get this sensible data !  <br><br> 
  </ul>
  
  
  <b>Polling of Camera-Properties:</b><br><br>
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
    deactivates the module (device definition) </li><br>
  
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
        </li>
  
  <li><b>livestreamprefix</b><br>
    overwrites the specifications of protocol, servername and port for further use of the livestream address, e.g. 
	as an link to external use. It has to be specified as "http(s)://&lt;servername&gt;:&lt;port&gt;"  </li><br>

  <li><b>loginRetries</b><br>
    set the amount of login-repetitions in case of failure (default = 1)   </li><br>
  
  <li><b>noQuotesForSID</b><br>
    this attribute may be helpfull in some cases to avoid errormessage "402 - permission denied" and makes login 
	possible.  </li><br>
  
  <li><b>pollcaminfoall</b><br>
    Interval of automatic polling the Camera properties (if < 10: no polling, if &gt; 10: polling with interval) </li><br>

  <li><b>pollnologging</b><br>
    "0" resp. not set = Logging device polling active (default), "1" = Logging device polling inactive</li><br>
  
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
    <tr><td><li>CamPort</li>            </td><td>- IP-Port of Camera  </td></tr>
    <tr><td><li>CamPreRecTime</li>      </td><td>- Duration of Pre-Recording (in seconds) adjusted in SVS  </td></tr>
    <tr><td><li>CamRecShare</li>        </td><td>- shared folder on disk station for recordings </td></tr>
    <tr><td><li>CamRecVolume</li>       </td><td>- Volume on disk station for recordings  </td></tr>
    <tr><td><li>CamVendor</li>          </td><td>- Identifier of camera producer  </td></tr>
    <tr><td><li>CamVideoFlip</li>       </td><td>- Is the video flip  </td></tr>
    <tr><td><li>CamVideoMirror</li>     </td><td>- Is the video mirror  </td></tr>
    <tr><td><li>CapAudioOut</li>        </td><td>- Capability to Audio Out over Surveillance Station (false/true)  </td></tr>
    <tr><td><li>CapChangeSpeed</li>     </td><td>- Capability to various motion speed  </td></tr>
    <tr><td><li>CapPTZAbs</li>          </td><td>- Capability to perform absolute PTZ action  </td></tr>
    <tr><td><li>CapPTZAutoFocus</li>    </td><td>- Capability to perform auto focus action  </td></tr>
    <tr><td><li>CapPTZDirections</li>   </td><td>- the PTZ directions that camera support  </td></tr>
    <tr><td><li>CapPTZFocus</li>        </td><td>- mode of support for focus action  </td></tr>
    <tr><td><li>CapPTZHome</li>         </td><td>- Capability to perform home action  </td></tr>
    <tr><td><li>CapPTZIris</li>         </td><td>- mode of support for iris action  </td></tr>
    <tr><td><li>CapPTZPan</li>          </td><td>- Capability to perform pan action  </td></tr>
    <tr><td><li>CapPTZTilt</li>         </td><td>- mode of support for tilt action  </td></tr>
    <tr><td><li>CapPTZZoom</li>         </td><td>- Capability to perform zoom action  </td></tr>
    <tr><td><li>DeviceType</li>         </td><td>- device type (Camera, Video_Server, PTZ, Fisheye)  </td></tr>
    <tr><td><li>Error</li>              </td><td>- message text of last error  </td></tr>
    <tr><td><li>Errorcode</li>          </td><td>- error code of last error  </td></tr>
    <tr><td><li>LastSnapFilename</li>   </td><td>- the filename of the last snapshot   </td></tr>
    <tr><td><li>LastSnapId</li>         </td><td>- the ID of the last snapshot   </td></tr>    
    <tr><td><li>LastSnapTime</li>       </td><td>- timestamp of the last snapshot   </td></tr> 
    <tr><td><li>LastUpdateTime</li>     </td><td>- date / time the last update of readings by "caminfoall"  </td></tr> 
    <tr><td><li>LiveStreamUrl </li>     </td><td>- the livestream URL if stream is started (is shown if <a href="#SSCamattr">attribute</a> "showStmInfoFull" is set) </td></tr> 
    <tr><td><li>Patrols</li>            </td><td>- in Synology Surveillance Station predefined patrols (at PTZ-Cameras)  </td></tr>
    <tr><td><li>PollState</li>          </td><td>- shows the state of automatic polling  </td></tr>    
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
    Mit diesem Modul können Operationen von in der Synology Surveillance Station (SVS) definierten Kameras ausgeführt werden. <br>
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
      <li>starten und beenden von Kamera-Livestreams, anzeigen der letzten Aufnahme oder des letzten Schnappschusses  </li>
      <li>Abruf und Ausgabe der Kamera Streamkeys sowie Stream-Urls (Nutzung von Kamera-Livestreams ohne Session Id)  </li>
      <li>abspielen der letzten Aufnahme bzw. Anzeige des letzten Schnappschusses  </li>
	  <li>Ein- bzw. Ausschalten des Surveillance Station HomeMode  </li>
	  <li>erzeugen einer Gallerie der letzten 1-10 Schnappschüsse (als Popup oder permanentes Device)  </li><br>
     </ul> 
    </ul>
    Die Aufnahmen stehen in der Synology Surveillance Station (SVS) zur Verfügung und unterliegen, wie jede andere Aufnahme, den in der Synology Surveillance Station eingestellten Regeln. <br>
    So werden zum Beispiel die Aufnahmen entsprechend ihrer Archivierungsfrist gespeichert und dann gelöscht. <br><br>
    
    Wenn sie über dieses Modul diskutieren oder zur Verbesserung des Moduls beitragen möchten, ist im FHEM-Forum ein Sammelplatz unter:<br>
    <a href="http://forum.fhem.de/index.php/topic,45671.msg374390.html#msg374390">49_SSCam: Fragen, Hinweise, Neuigkeiten und mehr rund um dieses Modul</a>.<br><br>

    Weitere Infomationen zum Modul sind im FHEM-Wiki zu finden:<br>
    <a href="http://www.fhemwiki.de/wiki/SSCAM_-_Steuerung_von_Kameras_in_Synology_Surveillance_Station">SSCAM - Steuerung von Kameras in Synology Surveillance Station</a>.<br><br>
    
    
    <b>Vorbereitung </b> <br><br>
    Dieses Modul nutzt das CPAN Module JSON. Bitte darauf achten dieses Paket zu installieren. (Debian: libjson-perl). <br>
    Das Modul verwendet für HTTP-Calls die nichtblockierenden Funktionen von HttpUtils bzw. HttpUtils_NonblockingGet. <br> 
    Im DSM bzw. der Synology Surveillance Station muß ein Nutzer angelegt sein. Die Zugangsdaten werden später über ein Set-Kommando dem angelegten Gerät zugewiesen. <br>
    Nähere Informationen dazu unter <a href="#SSCam_Credentials">Credentials</a><br><br>
        
    Überblick über die Perl-Module welche von SSCam genutzt werden: <br><br>
    
    JSON            <br>
    Data::Dumper    <br>                  
    MIME::Base64    <br>
    Time::HiRes     <br>
    HttpUtils       (FHEM-Modul) <br><br>

<a name="SSCamdefine"></a>
<b>Definition</b>
  <ul>
  <br>
    <code>define &lt;name&gt; SSCAM &lt;Kameraname in SVS&gt; &lt;ServerAddr&gt; [Port] </code><br>
    <br>
    
    Definiert eine neue Kamera für SSCam. Zunächst muß diese Kamera in der Synology Surveillance Station 7.0 oder höher eingebunden sein und entsprechend funktionieren.<br><br>
    Das Modul SSCam basiert auf Funktionen der Synology Surveillance Station API. <br>
    Weitere Informationen unter: <a href="http://global.download.synology.com/download/Document/DeveloperGuide/Surveillance_Station_Web_API_v2.0.pdf">Web API Guide</a>. <br><br>
    
    Momentan wird nur das HTTP-Protokoll unterstützt um die Web-Services der Synology DS aufzurufen. <br><br>  
    
    Die Parameter beschreiben im Einzelnen:
   <br>
   <br>    
    
    <table>
    <colgroup> <col width=15%> <col width=85%> </colgroup>
    <tr><td>name:           </td><td>der Name des neuen Gerätes in FHEM</td></tr>
    <tr><td>Kameraname:     </td><td>Kameraname wie er in der Synology Surveillance Station angegeben ist. Leerzeichen im Namen sind nicht erlaubt !</td></tr>
    <tr><td>ServerAddr:     </td><td>die IP-Addresse des Synology Surveillance Station Host. Hinweis: Es sollte kein Servername verwendet werden weil DNS-Aufrufe in FHEM blockierend sind.</td></tr>
    <tr><td>Port:           </td><td>optional - der Port der Synology Surveillance Station. Wenn nicht angegeben wird der Default-Port 5000 (nur HTTP) gesetzt </td></tr>
    </table>

    <br><br>

    <b>Beispiel:</b>
     <pre>
      define CamCP SSCAM Carport 192.168.2.20 [5000]      
     </pre>
     
    
    Wird eine neue Kamera definiert, wird diesem Device zunächst eine Standardaufnahmedauer von 15 zugewiesen. <br>
    Über das <a href="#SSCamattr">Attribut</a> "rectime" kann die Aufnahmedauer für jede Kamera individuell angepasst werden. Der Wert "0" für "rectime" führt zu einer Endlosaufnahme, die durch "set &lt;name&gt; off" wieder gestoppt werden muß. <br>
    Ein Logeintrag mit einem entsprechenden Hinweis auf diesen Umstand wird geschrieben. <br><br>

    Wird das <a href="#SSCamattr">Attribut</a> "rectime" gelöscht, greift wieder der Default-Wert (15s) für die Aufnahmedauer. <br><br>

    Mit dem <a href="#SSCamset">Befehl</a> <b>"set &lt;name&gt; on [rectime]"</b> wird die Aufnahmedauer temporär festgelegt und überschreibt einmalig sowohl den Defaultwert als auch den Wert des gesetzten Attributs "rectime". <br>
    Auch in diesem Fall führt <b>"set &lt;name&gt; on 0"</b> zu einer Daueraufnahme. <br><br>

    Eine eventuell in der SVS eingestellte Dauer der Voraufzeichnung wird weiterhin berücksichtigt. <br><br><br>
    
    
    <a name="SSCam_Credentials"></a>
    <b>Credentials </b><br><br>
    
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
      <tr><td><li>set ... on                 </td><td> session: ServeillanceStation - Betrachter mit erweiterten Privileg "manuelle Aufnahme" </li></td></tr>
      <tr><td><li>set ... off                </td><td> session: ServeillanceStation - Betrachter mit erweiterten Privileg "manuelle Aufnahme" </li></td></tr>
      <tr><td><li>set ... snap               </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      <tr><td><li>set ... disable            </td><td> session: ServeillanceStation - Manager       </li></td></tr>
      <tr><td><li>set ... enable             </td><td> session: ServeillanceStation - Manager       </li></td></tr>
      <tr><td><li>set ... expmode            </td><td> session: ServeillanceStation - Manager       </li></td></tr>
      <tr><td><li>set ... motdetsc           </td><td> session: ServeillanceStation - Manager       </li></td></tr>
      <tr><td><li>set ... goPreset           </td><td> session: ServeillanceStation - Betrachter mit Privileg Objektivsteuerung der Kamera  </li></td></tr>
      <tr><td><li>set ... runPatrol          </td><td> session: ServeillanceStation - Betrachter mit Privileg Objektivsteuerung der Kamera  </li></td></tr>
      <tr><td><li>set ... snapGallery        </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
	  <tr><td><li>set ... goAbsPTZ           </td><td> session: ServeillanceStation - Betrachter mit Privileg Objektivsteuerung der Kamera  </li></td></tr>
      <tr><td><li>set ... move               </td><td> session: ServeillanceStation - Betrachter mit Privileg Objektivsteuerung der Kamera  </li></td></tr>
      <tr><td><li>set ... runView            </td><td> session: ServeillanceStation - Betrachter mit Privileg Liveansicht für Kamera        </li></td></tr>
      <tr><td><li>set ... stopView           </td><td> -                                            </li></td></tr>
      <tr><td><li>set ... credentials        </td><td> -                                            </li></td></tr>
      <tr><td><li>set ... extevent           </td><td> session: DSM - Nutzer Mitglied von Admin-Gruppe     </li></td></tr>
      <tr><td><li>get ... caminfoall         </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      <tr><td><li>get ... eventlist          </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
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
    
  Es gibt zur Zeit folgende Optionen für "set &lt;name&gt; ...": <br><br>

  <table>
  <colgroup> <col width=30%> <col width=70%> </colgroup>
      <tr><td>"on [rectime]":                                      </td><td>startet eine Aufnahme. Die Aufnahme wird automatisch nach Ablauf der Zeit [rectime] gestoppt.</td></tr>
      <tr><td>                                                     </td><td>Mit rectime = 0 wird eine Daueraufnahme gestartet die durch "set &lt;name&gt; off" wieder gestoppt werden muß.</td></tr>
      <tr><td>"off" :                                              </td><td>stoppt eine laufende Aufnahme manuell oder durch die Nutzung anderer Events (z.B. über at, notify)</td></tr>
      <tr><td>"snap":                                              </td><td>löst einen Schnappschuß der entsprechenden Kamera aus und speichert ihn in der Synology Surveillance Station</td></tr>
      <tr><td>"disable":                                           </td><td>deaktiviert eine Kamera in der Synology Surveillance Station</td></tr>
      <tr><td>"enable":                                            </td><td>aktiviert eine Kamera in der Synology Surveillance Station</td></tr>
      <tr><td>"createSnapGallery":                                 </td><td>erzeugt eine Schnappschußgallerie als (weblink)Device</td></tr>
	  <tr><td>"credentials &lt;username&gt; &lt;password&gt;":     </td><td>speichert die Zugangsinformationen</td></tr>
      <tr><td>"expmode [ day | night | auto ]":                    </td><td>aktiviert den Belichtungsmodus Tag, Nacht oder Automatisch </td></tr>
      <tr><td>"extevent [ 1-10 ]":                                 </td><td>löst das externe Ereignis 1-10 aus (Aktionsregel in SVS) </td></tr>
      <tr><td>"motdetsc [ camera | SVS | disable ]":               </td><td>schaltet die Bewegungserkennung in den gewünschten Modus (durch Kamera, SVS, oder deaktiviert) </td></tr>
      <tr><td>"goPreset &lt;Presetname&gt;":                       </td><td>bewegt eine PTZ-Kamera zu einer vordefinierten Preset-Position  </td></tr>
      <tr><td>"runPatrol &lt;Patrolname&gt;":                      </td><td>startet eine vordefinierte Überwachungstour einer PTZ-Kamera  </td></tr>
      <tr><td>"snapGallery [1-10]":                                </td><td>erzeugt eine Ausgabe der letzten [n] Schnappschüsse  </td></tr>
	  <tr><td>"goAbsPTZ [ X Y | up | down | left | right ]":       </td><td>positioniert eine PTZ-camera zu einer absoluten X/Y-Koordinate oder maximalen up/down/left/right-position  </td></tr>
      <tr><td>"move [ up | down | left | right | dir_X ]":         </td><td>startet kontinuerliche Bewegung einer PTZ-Kamera in Richtung up/down/left/right bzw. dir_X  </td></tr> 
      <tr><td>"runView live_fw | live_link | live_open [&lt;room&gt;] | lastrec_fw | lastrec_open [&lt;room&gt;]":  </td><td>startet einen Livestream als eingbettetes Image, IFrame bzw. Link  </td></tr>
      <tr><td>"stopView":                                          </td><td>stoppt einen Kamera-Livestream  </td></tr>
  </table>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; credentials &lt;username&gt; &lt;password&gt; </b></li> <br>
  
  Setzt Username / Passwort für den Zugriff auf die Synology Surveillance Station. 
  Siehe <a href="#SSCam_Credentials">Credentials</a><br>
  
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; createSnapGallery </b></li> <br>
  
  Es wird eine Schnappschußgallerie als permanentes (weblink)Device erzeugt. Das Device wird im Raum "SnapGallery" erstellt.
  Mit den "snapGallery..."-<a href="#SSCamattr">Attributen</a> bzw. den spezifischen Attributen des entstandenen Weblink-Devices 
  können die Eigenschaften der Schnappschußgallerie beeinflusst werden. <br> 
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; [enable|disable] </b></li> <br>
  
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
  <li><b> set &lt;name&gt; expmode [day|night|auto] </b></li> <br>
  
  Mit diesem Befehl kann der Belichtungsmodus der Kameras gesetzt werden. Dadurch wird z.B. das Verhalten der Kamera-LED's entsprechend gesteuert. 
  Die erfolgreiche Umschaltung wird durch das Reading CamExposureMode ("get ... caminfoall") reportet. <br><br>
  
  <b> Hinweis: </b> <br>
  Die erfolgreiche Ausführung dieser Funktion ist davon abhängig ob die SVS diese Funktionalität der Kamera unterstützt. 
  Ist in SVS -&gt; IP-Kamera -&gt; Optimierung -&gt; Belichtungsmodus das Feld für den Tag/Nachtmodus grau hinterlegt, ist nicht von einer lauffähigen Unterstützung dieser 
  Funktion auszugehen. 
  <br><br>
  </ul>

  <ul>
  <li><b> set &lt;name&gt; extevent [ 1-10 ] </b></li> <br>
  
  Dieses Kommando triggert ein externes Ereignis (1-10) in der SVS. 
  Die Aktionen, die dieses Ereignis auslöst, sind zuvor in dem Aktionsregeleditor der SVS einzustellen. Es stehen die Ereignisse 1-10 zur Verfügung.
  In der Banchrichtigungs-App der SVS können auch Email, SMS oder Mobil (DS-Cam) Nachrichten ausgegeben werden wenn ein externes Ereignis ausgelöst wurde.
  Nähere Informationen dazu sind in der Hilfe zum Aktionsregeleditor zu finden.
  Der verwendete User benötigt Admin-Rechte in einer DSM-Session.
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; goAbsPTZ [ X Y | up | down | left | right ] </b></li> <br>
  
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
   set &lt;name&gt; goAbsPTZ up [down|left|right]
  </pre>

  verwendet werden. Die Optik wird in diesem Fall mit der größt möglichen Schrittweite zur Absolutposition in der angegebenen Richtung bewegt. 
  Auch in diesem Fall muß der Vorgang ggf. mehrfach wiederholt werden um die Kameralinse in die gewünschte Position zu bringen.
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; goPreset &lt;Preset&gt; </b></li> <br>
  
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
  <li><b> set &lt;name&gt; homeMode [on | off] </b></li> <br>
  
  Schaltet den HomeMode der Surveillance Station ein bzw. aus. 
  Informationen zum HomeMode sind in der <a href="https://www.synology.com/de-de/knowledgebase/Surveillance/help/SurveillanceStation/home_mode">Synology Onlinehilfe</a> 
  enthalten.
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; motdetsc [camera|SVS|disable] </b></li> <br>
  
  Der Befehl "motdetsc" (steht für motion detection source) schaltet die Bewegungserkennung in den gewünschten Modus. 
  Wird die Bewegungserkennung durch die Kamera / SVS ohne weitere Optionen eingestellt, werden die momentan gültigen Bewegungserkennungsparameter der 
  Kamera / SVS beibehalten. Die erfolgreiche Ausführung der Operation lässt sich u.a. anhand des Status von SVS -&gt; IP-Kamera -&gt; Ereigniserkennung -&gt; 
  Bewegung nachvollziehen. <br><br>
  Für die Bewegungserkennung durch SVS bzw. durch Kamera können weitere Optionen angegeben werden. Die verfügbaren Optionen bezüglich der Bewegungserkennung 
  durch SVS sind "Empfindlichkeit" und "Schwellwert". <br><br>
  <ul>
  <table>
  <colgroup> <col width=50%> <col width=50%> </colgroup>
      <tr><td>set <name> motdetsc SVS [Empfindlichkeit] [Schwellwert]  </td><td># Befehlsmuster  </td></tr>
      <tr><td>set <name> motdetsc SVS 91 30                            </td><td># setzt die Empfindlichkeit auf 91 und den Schwellwert auf 30  </td></tr>
      <tr><td>set <name> motdetsc SVS 0 40                             </td><td># behält gesetzten Wert für Empfindlichkeit bei, setzt Schwellwert auf 40  </td></tr>
      <tr><td>set <name> motdetsc SVS 15                               </td><td># setzt die Empfindlichkeit auf 15, Schwellwert bleibt unverändert   </td></tr>
  </table>
  </ul>
  <br><br>
  
  Wird die Bewegungserkennung durch die Kamera genutzt, stehen die Optionen "Empfindlichkeit", "Objektgröße" und "Prozentsatz für Auslösung" zur Verfügung. <br><br>
  <ul>
  <table>
  <colgroup> <col width=50%> <col width=50%> </colgroup>
      <tr><td>set <name> motdetsc camera [Empfindlichkeit] [Schwellwert] [Prozentsatz] </td><td># Befehlsmuster  </td></tr>
      <tr><td>set <name> motdetsc camera 89 0 20                                       </td><td># setzt die Empfindlichkeit auf 89, Prozentsatz auf 20  </td></tr>
      <tr><td>set <name> motdetsc camera 0 40 10                                      </td><td># behält gesetzten Wert für Empfindlichkeit bei, setzt Schwellwert auf 40, Prozentsatz auf 10  </td></tr>
      <tr><td>set <name> motdetsc camera 30                                            </td><td># setzt die Empfindlichkeit auf 30, andere Werte bleiben unverändert  </td></tr>
      </table>
  </ul>
  <br><br>

  Es ist immer die Reihenfolge der Optionswerte zu beachten. Nicht gewünschte Optionen sind mit "0" zu besetzen sofern danach Optionen folgen 
  deren Werte verändert werden sollen (siehe Beispiele oben). Der Zahlenwert der Optionen beträgt 1 - 99 (außer Sonderfall "0"). <br><br>
  
  Die jeweils verfügbaren Optionen unterliegen der Funktion der Kamera und der Unterstützung durch die SVS. Es können jeweils nur die Optionen genutzt werden die in 
  SVS -&gt; Kamera bearbeiten -&gt; Ereigniserkennung zur Verfügung stehen. Weitere Infos sind der Online-Hilfe zur SVS zu entnehmen. <br><br>
  
  Über den Befehl "get ... caminfoall" wird auch das <a href="#SSCamreadings">Reading</a> "CamMotDetSc" aktualisiert welches die gegenwärtige Einstellung der Bewegungserkennung dokumentiert. 
  Es werden nur die Parameter und Parameterwerte angezeigt, welche die SVS aktiv unterstützt. Die Kamera selbst kann weiterführende Einstellmöglichkeiten besitzen. <br><br>
  
  Beipiel:
  <pre>
  CamMotDetSc    SVS, sensitivity: 76, threshold: 55
  </pre>
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; move [ up | down | left | right | dir_X ] [Sekunden] </b></li> <br>
  
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
  <li><b> set &lt;name&gt; [on | off] </b></li><br>

  Der Befehl "set &lt;name&gt; on" startet eine Aufnahme. Die Standardaufnahmedauer beträgt 15 Sekunden. Sie kann mit dem Attribut "rectime" individuell festgelegt werden. 
  Die im Attribut (bzw. im Standard) hinterlegte Aufnahmedauer kann einmalig mit "set &lt;name&gt; on [rectime]" überschrieben werden.
  Die Aufnahme stoppt automatisch nach Ablauf der Zeit "rectime".<br>

  Ein Sonderfall ist der Start einer Daueraufnahme mit "set &lt;name&gt; on 0" bzw. dem Attributwert "rectime = 0". In diesem Fall wird eine Daueraufnahme gestartet die 
  explizit wieder mit dem Befehl "set &lt;name&gt; off" gestoppt werden muß.<br>

  Das Aufnahmeverhalten kann weiterhin mit dem Attribut "recextend" wie folgt beeinflusst werden.<br><br>

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
  <li><b> set &lt;name&gt; runPatrol &lt;Patrolname&gt; </b></li> <br>
  
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
  <li><b> set &lt;name&gt; runView [live_fw | live_link | live_open [&lt;room&gt;] | lastrec_fw | lastrec_open [&lt;room&gt;] | lastsnap_fw]  </b></li> <br>
  
  Mit "live_fw, live_link, live_open" wird ein Livestream (mjpeg-Stream) der Kamera, entweder als eingebettetes Image 
  oder als generierter Link, gestartet. <br>
  Die Option "live_open" startet ein separates Browserfenster mit dem Lifestream. Wird dabei optional der Raum mit
  angegeben, wird das Browserfenster nur gestartet wenn dieser Raum aktuell im Browser geöffnet ist. <br><br> 
    
  Der Zugriff auf die letzte Aufnahme einer Kamera kann über die Optionen "lastrec_fw" bzw. "lastrec_open" erfolgen.
  Bei Verwendung von "lastrec_fw" wird die letzte Aufnahme als eingebettetes iFrame-Objekt abgespielt. Es stehen entsprechende
  Steuerungselemente zur Wiedergabegeschwindigkeit usw. zur Verfügung. <br><br>
  Der Befehl <b>"set &lt;name&gt; runView lastsnap_fw"</b> zeigt den letzten Schnappschuss der Kamera eingebettet an. <br><br>
  Durch Angabe des optionalen Raumes bei "lastrec_open" erfolgt die gleiche Einschränkung wie bei "live_open". <br><br>
  
  Die Gestaltung der Fenster im FHEMWEB kann durch HTML-Tags im <a href="#SSCamattr">Attribut</a> "htmlattr" beeinflusst werden. <br><br>
  
  <b>Beispiel:</b><br>
  <pre>
    attr &lt;name&gt; htmlattr width="500" height="375"
    attr &lt;name&gt; htmlattr width="500" height="375" top="200" left="300"
  </pre>
    
  Wird der Stream als live_fw gestartet, ändert sich die Größe entsprechend der Angaben von Width und Hight. <br>
  Das Kommando <b>"set &lt;name&gt; runView live_open"</b> startet den Livestreamlink sofort in einem neuen 
  Browserfenster (longpoll=1 muß für WEB gesetzt sein). 
  Dabei wird für jede aktive FHEM-Session eine Fensteröffnung initiiert. Soll dieses Verhalten geändert werden, kann 
  <b>"set &lt;name&gt; runView live_open &lt;room&gt;"</b> verwendet werden um das Öffnen des Browserwindows in einem 
  beliebigen, in einer FHEM-Session angezeigten Raum &lt;room&gt;, zu initiieren.<br>
  Das gesetzte <a href="#SSCamattr">Attribut</a> "livestreamprefix" überschreibt im <a href="#SSCamreadings">Reading</a> "LiveStreamUrl" 
  die Angaben für Protokoll, Servername und Port. Damit kann z.B. die LiveStreamUrl für den Versand und externen Zugriff 
  auf die SVS modifiziert werden. <br><br>
  
  <b>Beispiel:</b><br>
  <pre>
    attr &lt;name&gt; livestreamprefix https://&lt;Servername&gt;:&lt;Port&gt;
  </pre>
  
  Der Livestream wird über das Kommando <b>"set &lt;name&gt; stopView"</b> wieder beendet.
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; snap </b></li> <br>
  
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
  <li><b> set &lt;name&gt; snapGallery [1-10] </b></li> <br>
  
  Der Befehl ist nur vorhanden wenn das Attribut "snapGalleryBoost=1" gesetzt wurde.
  Er erzeugt eine Ausgabe der letzten [x] Schnappschüsse ebenso wie <a href="#SSCamget">"get &lt;name&gt; snapGallery"</a>.  Abweichend von "get" wird mit Attribut
  <a href="#SSCamattr">Attribut</a> "snapGalleryBoost=1" kein Popup erzeugt, sondern die Schnappschußgalerie als Browserseite
  dargestellt. Alle weiteren Funktionen und Attribute entsprechen dem "get &lt;name&gt; snapGallery" Kommando. <br>
  Wenn die Ausgabe einer Schnappschußgalerie, z.B. über ein "at oder "notify", getriggert wird, sollte besser das  
  <a href="#SSCamget">"get &lt;name&gt; snapGallery"</a> Kommando anstatt "set" verwendet werden.
  </ul>
  <br><br>

  </ul>
  <br>

<a name="SSCamget"></a>
<b>Get</b>
 <ul>
  Mit SSCam können die Eigenschaften der Surveillance Station und der Kameras abgefragt werden. Zur Zeit stehen dazu 
  folgende Befehle zur Verfügung:
  <pre>
      get &lt;name&gt; caminfoall
      get &lt;name&gt; eventlist
      get &lt;name&gt; scanVirgin
      get &lt;name&gt; snapfileinfo
      get &lt;name&gt; snapGallery
      get &lt;name&gt; snapinfo
      get &lt;name&gt; stmUrlPath
      get &lt;name&gt; svsinfo
  </pre>
  
  Mit dem Befehl <b>"get &lt;name&gt; caminfoall"</b> werden abhängig von der Art der Kamera (z.B. Fix- oder PTZ-Kamera) die 
  verfügbaren Eigenschaften ermittelt und als Readings zur Verfügung gestellt. <br>
  So wird zum Beispiel das Reading "Availability" auf "disconnected" gesetzt falls die Kamera von der Surveillance Station 
  getrennt wird und kann für weitere Verarbeitungen genutzt werden. <br>
  Durch <b>"get &lt;name&gt; eventlist"</b> wird das <a href="#SSCamreadings">Reading</a> "CamEventNum" und "CamLastRec" 
  aktualisiert, welches die Gesamtanzahl der registrierten Kameraevents und den Pfad / Namen der letzten Aufnahme enthält.
  Dieser Befehl wird implizit mit "get ... caminfoall" ausgeführt. <br>
  
  Mit dem <a href="#SSCamattr">Attribut</a> "videofolderMap" kann der Inhalt des Readings "VideoFolder" überschrieben werden. 
  Dies kann von Vortel sein wenn das Surveillance-Verzeichnis der SVS an dem lokalen PC unter anderem Pfadnamen gemountet ist und darüber der Zugriff auf die Aufnahmen
  erfolgen soll (z.B. Verwendung Email-Versand). <br><br>
  
  Ein DOIF-Beispiel für den Email-Versand von Snapshot und Aufnahmelink per Non-blocking sendmail:
  <pre>
     define CamHE1.snap.email DOIF ([CamHE1:"LastSnapFilename"]) 
     ({DebianMailnbl ('Recipient@Domain','Bewegungsalarm CamHE1','Eine Bewegung wurde an der Haustür registriert. Aufnahmelink: \  
     \[CamHE1:VideoFolder]\[CamHE1:CamLastRec]','/media/sf_surveillance/@Snapshot/[CamHE1:LastSnapFilename]')})
  </pre>
  
  Mit <b>"get &lt;name&gt; snapfileinfo"</b> wird der Filename des letzten Schnapschusses ermittelt. Der Befehl wird implizit mit <b>"get &lt;name&gt; snap"</b> ausgeführt. <br>
  Der Befehl <b>"get &lt;name&gt; svsinfo"</b> ist eigentlich nicht von der Kamera abhängig, sondern ermittelt vielmehr allgemeine Informationen zur installierten SVS-Version und andere Eigenschaften. <br>
  Die Funktionen "caminfoall" und "svsinfo" werden einmalig automatisch beim Start von FHEM ausgeführt um steuerungsrelevante Informationen zu sammeln.<br>
  Es ist darauf zu achten dass die <a href="#SSCam_Credentials">Credentials</a> gespeichert wurden !
  <br><br>
  
  <ul>
  <li><b> get &lt;name&gt; scanVirgin </b></li> <br>
  
  Wie mit get caminfoall werden alle Informationen der SVS und Kamera abgerufen. Allerdings wird in jedem Fall eine 
  neue Session ID generiert (neues Login), die Kamera-ID neu ermittelt und es werden alle notwendigen API-Parameter neu 
  eingelesen.  
  </ul>
  <br><br> 
  
  <ul>
  <li><b> get &lt;name&gt; snapGallery [1-10] </b></li> <br>
  
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
        Abhängig von der Anzahl und Auflösung (Qualität) der Schnappschuß-Images werden entsprechende ausreichende CPU und/oder
		RAM-Ressourcen benötigt.
        </ul>
		<br><br>
  
  <ul>
  <li><b> get &lt;name&gt; snapinfo </b></li> <br>
  
  Es werden Schnappschussinformationen gelesen. Hilfreich wenn Schnappschüsse nicht durch SSCam, sondern durch die Bewegungserkennung der Kamera 
  oder Surveillance Station erzeugt werden.
  </ul>
  <br><br> 
  
  <ul>
  <li><b> get &lt;name&gt; stmUrlPath </b></li> <br>
  
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
  
  cameraId (INTERNAL), StmKey müssen durch gültige Werte ersetzt werden. <br><br>
  
  <b>Hinweis:</b> <br>
  
  Falls der Stream-Aufruf versendet und von extern genutzt wird sowie hostname / port durch gültige Werte ersetzt und die Routerports entsprechend geöffnet
  werden, ist darauf zu achten dass diese sensiblen Daten nicht durch unauthorisierte Personen für den Zugriff genutzt werden können !  <br><br><br>
  </ul>
  <br><br>

  <b>Polling der Kameraeigenschaften:</b><br><br>

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
</ul>


<a name="SSCaminternals"></a>
<b>Internals</b> <br><br>
 <ul>
 Die Bedeutung der verwendeten Internals stellt die nachfolgende Liste dar: <br><br>
  <ul>
  <li><b>CAMID</b> - die ID der Kamera in der SVS, der Wert wird automatisch anhand des SVS-Kameranamens ermittelt. </li>
  <li><b>CAMNAME</b> - der Name der Kamera in der SVS </li>
  <li><b>CREDENTIALS</b> - der Wert ist "Set" wenn die Credentials gesetzt wurden </li>
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
    Intervall der automatischen Eigenschaftsabfrage (Polling) einer Kamera (kleiner 10: kein 
    Polling, größer 10: Polling mit Intervall) </li><br>

  <li><b>pollnologging</b><br>
    "0" bzw. nicht gesetzt = Logging Gerätepolling aktiv (default), "1" = Logging 
    Gerätepolling inaktiv </li><br>
  
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
    <tr><td><li>CamPort</li>            </td><td>- IP-Port der Kamera  </td></tr>
    <tr><td><li>CamPreRecTime</li>      </td><td>- Dauer der der Voraufzeichnung in Sekunden (Einstellung in SVS)  </td></tr>
    <tr><td><li>CamRecShare</li>        </td><td>- gemeinsamer Ordner auf der DS für Aufnahmen  </td></tr>
    <tr><td><li>CamRecVolume</li>       </td><td>- Volume auf der DS für Aufnahmen  </td></tr>
    <tr><td><li>CamVendor</li>          </td><td>- Kamerahersteller Bezeichnung  </td></tr>
    <tr><td><li>CamVideoFlip</li>       </td><td>- Ist das Video gedreht  </td></tr>
    <tr><td><li>CamVideoMirror</li>     </td><td>- Ist das Video gespiegelt  </td></tr>
    <tr><td><li>CapAudioOut</li>        </td><td>- Fähigkeit der Kamera zur Audioausgabe über Surveillance Station (false/true)  </td></tr>
    <tr><td><li>CapChangeSpeed</li>     </td><td>- Fähigkeit der Kamera verschiedene Bewegungsgeschwindigkeiten auszuführen  </td></tr>
    <tr><td><li>CapPTZAbs</li>          </td><td>- Fähigkeit der Kamera für absolute PTZ-Aktionen   </td></tr>
    <tr><td><li>CapPTZAutoFocus</li>    </td><td>- Fähigkeit der Kamera für Autofokus Aktionen  </td></tr>
    <tr><td><li>CapPTZDirections</li>   </td><td>- die verfügbaren PTZ-Richtungen der Kamera  </td></tr>
    <tr><td><li>CapPTZFocus</li>        </td><td>- Art der Kameraunterstützung für Fokussierung  </td></tr>
    <tr><td><li>CapPTZHome</li>         </td><td>- Unterstützung der Kamera für Home-Position  </td></tr>
    <tr><td><li>CapPTZIris</li>         </td><td>- Unterstützung der Kamera für Iris-Aktion  </td></tr>
    <tr><td><li>CapPTZPan</li>          </td><td>- Unterstützung der Kamera für Pan-Aktion  </td></tr>
    <tr><td><li>CapPTZTilt</li>         </td><td>- Unterstützung der Kamera für Tilt-Aktion  </td></tr>
    <tr><td><li>CapPTZZoom</li>         </td><td>- Unterstützung der Kamera für Zoom-Aktion  </td></tr>
    <tr><td><li>DeviceType</li>         </td><td>- Kameratyp (Camera, Video_Server, PTZ, Fisheye)  </td></tr>
    <tr><td><li>Error</li>              </td><td>- Meldungstext des letzten Fehlers  </td></tr>
    <tr><td><li>Errorcode</li>          </td><td>- Fehlercode des letzten Fehlers   </td></tr>
    <tr><td><li>LastSnapFilename</li>   </td><td>- der Filename des letzten Schnapschusses   </td></tr>
    <tr><td><li>LastSnapId</li>         </td><td>- die ID des letzten Schnapschusses   </td></tr>
	<tr><td><li>LastSnapTime</li>       </td><td>- Zeitstempel des letzten Schnapschusses   </td></tr>
    <tr><td><li>LastUpdateTime</li>     </td><td>- Datum / Zeit der letzten Aktualisierung durch "caminfoall" </td></tr> 
    <tr><td><li>LiveStreamUrl </li>     </td><td>- die LiveStream-Url wenn der Stream gestartet ist. (<a href="#SSCamattr">Attribut</a> "showStmInfoFull" muss gesetzt sein) </td></tr> 
    <tr><td><li>Patrols</li>            </td><td>- in Surveillance Station voreingestellte Überwachungstouren (bei PTZ-Kameras)  </td></tr>
    <tr><td><li>PollState</li>          </td><td>- zeigt den Status des automatischen Pollings an  </td></tr>    
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
