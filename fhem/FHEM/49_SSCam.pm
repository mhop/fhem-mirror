########################################################################################################################
# $Id$
#########################################################################################################################
#       49_SSCam.pm
#
#       (c) 2015-2021 by Heiko Maaz
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
# 
# Definition: define <name> SSCam <camname> <ServerAddr> [ServerPort] [Protocol]
# 
# Example of defining a Cam-device: define CamCP1 SSCAM Carport 192.168.2.20 [5000] [HTTP(S)]
# Example of defining a SVS-device: define SDS1 SSCAM SVS 192.168.2.20 [5000] [HTTP(S)]
#

package FHEM::SSCam;                                                               ## no critic 'package'

use strict;                           
use warnings;
use GPUtils qw( GP_Import GP_Export );                                             # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt

use FHEM::SynoModules::API qw(:all);                                               # API Modul
use FHEM::SynoModules::ErrCodes qw(:all);                                          # Error Code Modul
use FHEM::SynoModules::SMUtils qw(
                                  getClHash
                                  delClHash
                                  trim
                                  moduleVersion
                                  sortVersion
                                  showModuleInfo
                                  jboolmap
                                  completeAPI
                                  showAPIinfo
                                  setCredentials
                                  getCredentials
                                  showStoredCredentials
                                  evaljson
                                  login
                                  logout
                                  setActiveToken
                                  delActiveToken
                                  delCallParts
                                  setReadingErrorNone
                                  setReadingErrorState
                                 );                                                # Hilfsroutinen Modul
use Data::Dumper;                                                                
use MIME::Base64;
use Time::HiRes qw( gettimeofday tv_interval );
use HttpUtils;
use Blocking;                                                                      # für EMail-Versand
use Encode;
eval "use JSON;1;"               or my $MMJSON            = "JSON";                ## no critic 'eval' # Debian: apt-get install libjson-perl
eval "use FHEM::Meta;1"          or my $modMetaAbsent     = 1;                     ## no critic 'eval'

# Cache 
eval "use CHI;1;"                or my $SScamMMCHI        = "CHI";                 ## no critic 'eval' # cpanm CHI
eval "use CHI::Driver::Redis;1;" or my $SScamMMCHIRedis   = "CHI::Driver::Redis";  ## no critic 'eval' # cpanm CHI::Driver::Redis
eval "use Cache::Cache;1;"       or my $SScamMMCacheCache = "Cache::Cache";        ## no critic 'eval' # cpanm Cache::Cache
                                                    
# no if $] >= 5.017011, warnings => 'experimental';

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import( 
      qw(
          attr
          data
          defs
          AnalyzePerlCommand
          AttrVal
          AttrNum
          addToDevAttrList
          addToAttrList
          asyncOutput
          BlockingCall
          BlockingKill
          BlockingInformParent
          CancelDelayedShutdown
          CommandAttr
          CommandDefine
          CommandDeleteAttr
          CommandDeleteReading
          CommandSave
          CommandDelete
          CommandSet
          delFromDevAttrList
          delFromAttrList
          devspec2array
          deviceEvents
          Debug
          DoTrigger
          FmtDateTime
          FmtTime
          fhemTzOffset
          fhemTimeGm
          fhemTimeLocal
          getKeyValue
          gettimeofday
          genUUID
          HttpUtils_NonblockingGet
          init_done
          InternalTimer
          IsDisabled
          Log
          Log3    
          makeReadingName  
          makeDeviceName          
          modules          
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsDelete
          readingsEndUpdate
          ReadingsNum
          ReadingsTimestamp
          ReadingsVal
          RemoveInternalTimer
          readingFnAttributes
          setKeyValue
          sortTopicNum
          TimeNow
          Value
          json2nameValue
          FW_cmd
          FW_directNotify
          FW_ME      
          FW_makeImage
          FW_iconPath
          FW_icondir
          FW_widgetFallbackFn
          FW_pH          
          FW_subdir                                 
          FW_room                                  
          FW_detail                                 
          FW_wname  
          TelegramBot_MsgForLog    
          TelegramBot_GetIdForPeer    
          TelegramBot_GetFullnameForContact   
          TelegramBot_getBaseURL  
          TelegramBot_AttrNum     
          TelegramBot_Callback     
          TelegramBot_BinaryFileRead  
          FHEM::SSChatBot::formString          
          FHEM::SSChatBot::addSendqueue
          FHEM::SSChatBot::getApiSites
        )
  );
  
  # Export to main context with different name
  #     my $pkg  = caller(0);
  #     my $main = $pkg;
  #     $main =~ s/^(?:.+::)?([^:]+)$/main::$1\_/gx;
  #     for (@_) {
  #         *{ $main . $_ } = *{ $pkg . '::' . $_ };
  #     }
  GP_Export(
      qw(
          Initialize
        )
  );  
  
}

# Versions History intern
my %vNotesIntern = (
  "9.9.0"  => "21.05.2021  new get command saveLastSnap ",
  "9.8.5"  => "22.02.2021  remove sscam_tooltip.js, substitute /fhem by \$FW_ME ",
  "9.8.4"  => "20.02.2021  sub Define minor fix ",
  "9.8.3"  => "29.11.2020  fix cannot send snaps/recs if snapTelegramTxt + snapChatTxt and no cacheType (cacheType=internal) is set ",
  "9.8.2"  => "04.10.2020  use showStoredCredentials from SMUtils ",
  "9.8.1"  => "28.09.2020  align getApiSites_Parse to other syno modules ",
  "9.8.0"  => "27.09.2020  optimize getApiSites_Parse, new getter apiInfo ",
  "9.7.26" => "26.09.2020  use moduleVersion and other from SMUtils ",
  "9.7.25" => "25.09.2020  change FHEM::SSChatBot::addQueue to FHEM::SSChatBot::addSendqueue ",
  "9.7.24" => "24.09.2020  optimize prepareSendData ",
  "9.7.23" => "23.09.2020  setVersionInfo back from SMUtils, separate prepareSendData ",
  "9.7.22" => "22.09.2020  bugfix error condition if try new login in some cases ",
  "9.7.21" => "21.09.2020  control parse function by the hparse hash step 4 ",
  "9.7.20" => "20.09.2020  control parse function by the hparse hash step 3 (refactored getsnapinfo, getsnapgallery, runView Snap) ",
  "9.7.19" => "18.09.2020  control parse function by the hparse hash step 2 ",
  "9.7.18" => "16.09.2020  control parse function by the hparse hash ",
  "9.7.17" => "13.09.2020  optimize _Oprunliveview ",
  "9.7.16" => "12.09.2020  function _Oprunliveview to execute livestream (no snap / HLS) in new camOp variant ",
  "9.7.15" => "12.09.2020  changed audiolink handling to new execution variant in camOp ",
  "9.7.14" => "10.09.2020  bugfix in reactivation HLS streaming ",
  "9.7.13" => "10.09.2020  optimize liveview handling ",
  "9.7.12" => "09.09.2020  implement new getApiSites usage, httptimeout default value increased to 20s, fix setting motdetsc ",
  "9.7.11" => "07.09.2020  implement new camOp control ",
  "9.7.10" => "06.09.2020  rebuild timer sequences, minor fixes ",
  "9.7.9"  => "05.09.2020  more refactoring according PBP ",
  "9.7.8"  => "02.09.2020  refactored setter: pirSensor runPatrol goAbsPTZ move runView hlsreactivate hlsactivate refresh ".
                           "extevent stopView setPreset setHome, camOP_parse for extevent, use setReadingErrorNone from SMUtils ".
                           "fix setting CamNTPServer",
  "9.7.7"  => "01.09.2020  minor fixes, refactored setter: createReadingsGroup enable disable motdetsc expmode homeMode ".
                           "autocreateCams goPreset optimizeParams ",
  "9.7.6"  => "31.08.2020  refactored setter: snapGallery createSnapGallery createPTZcontrol createStreamDev, minor bugfixes ",
  "9.7.5"  => "30.08.2020  some more code review and optimisation, exitOnDis with fix check Availability instead of state ",
  "9.7.4"  => "29.08.2020  some code changes ",
  "9.7.3"  => "29.08.2020  move login, loginReturn, logout, logoutReturn, setActiveToken, delActiveToken to SMUtils.pm ".
                           "move expErrorsAuth, expErrors to ErrCodes.pm",
  "9.7.2"  => "26.08.2020  move setCredentials, getCredentials, evaljson to SMUtils.pm ",
  "9.7.1"  => "25.08.2020  switch to lib/FHEM/SynoModules/API.pm and lib/FHEM/SynoModules/SMUtils.pm ".
                           "move __getPtzPresetList, __getPtzPatrolList to return path of OpMOde Getcaminfo ",
  "9.7.0"  => "17.08.2020  compatibility to SSChatBot version 1.10.0 ",
  "9.6.1"  => "13.08.2020  avoid warnings during FHEM shutdown/restart ",
  "9.6.0"  => "12.08.2020  new attribute ptzNoCapPrePat ",
  "9.5.3"  => "27.07.2020  fix warning: Use of uninitialized value in subroutine dereference at ... ",
  "9.5.2"  => "26.07.2020  more changes according PBP level 3, minor fixes ",
  "9.5.1"  => "24.07.2020  set compatibility to 8.2.8, some changes according PBP level 3 ",
  "9.5.0"  => "15.07.2020  streamDev master type added, comref revised ",
  "9.4.5"  => "15.07.2020  fix crash while autocreate CommandDelete, CommandSave is missing ",
  "9.4.4"  => "14.07.2020  fix crash while autocreate makeDeviceName is missing ",
  "9.4.3"  => "13.07.2020  streamDev refactored, comref revised ",
  "9.4.2"  => "11.07.2020  more changes according PBP level 3, headline PTZ Control, revised comref ",
  "9.4.1"  => "05.07.2020  new Zoom icons ", 
  "9.4.0"  => "01.07.2020  switch to packages, much more changes according PBP ",  
  "9.3.0"  => "21.06.2020  SVS device 'inctive' if disabled, add zoom capability, much more internal code changes ",
  "9.2.3"  => "30.05.2020  change SSChatBot_formText to SSChatBot_formString ",
  "9.2.2"  => "14.04.2020  increase read timeout of Redis server cache, fix autocreate bug with https ",
  "9.2.1"  => "24.02.2020  set compatibility to SVS version 8.2.7 ",
  "9.2.0"  => "10.12.2019  attribute \"recChatTxt\" for sending recordings by SSChatBot ",
  "9.1.0"  => "08.12.2019  attribute \"snapChatTxt\" for sending snapshots by SSChatBot ",
  "9.0.6"  => "26.11.2019  minor code change ",
  "9.0.5"  => "22.11.2019  commandref revised ",
  "9.0.4"  => "18.11.2019  fix FHEM crash when sending data by telegramBot, Forum: https://forum.fhem.de/index.php/topic,105486.0.html ",
  "9.0.3"  => "04.11.2019  change send Telegram routines, undef variables, fix cache and transaction coding, fix __sendEmailblocking ",
  "9.0.2"  => "03.11.2019  change Streamdev type \"lastsnap\" use \$data Hash or CHI cache ",
  "9.0.1"  => "02.11.2019  correct snapgallery number of snaps in case of cache usage, fix display number of retrieved snaps ",
  "9.0.0"  => "26.10.2019  finalize all changes beginning with 8.20.0 and revised commandref ",
  "8.23.0" => "26.10.2019  new attribute \"debugCachetime\" ",
  "8.22.0" => "23.10.2019  implement CacheCache driver for CHI ",
  "8.21.0" => "20.10.2019  implement Redis driver for CHI ",
  "8.20.0" => "19.10.2019  implement caching with CHI, implement {SENDCOUNT} ",
  "8.19.6" => "14.10.2019  optimize memory usage of composeGallery ",
  "8.19.5" => "13.10.2019  change FH to Data in __sendEmailblocking, save variables ",
  "8.19.4" => "11.10.2019  further optimize memory usage when send recordings by email and/or telegram ",
  "8.19.3" => "09.10.2019  optimize memory usage when send images and recordings by email and/or telegram ",
  "8.19.2" => "06.10.2019  delete key/value pairs in __extractForTelegram and sendEmailblocking, ".
                           "change datacontainer of SNAPHASH(OLD) from %defs to %data ",
  "8.19.1" => "26.09.2019  set compatibility to 8.2.6 ",
  "8.19.0" => "21.09.2019  support attr \"hideAudio\" SSCamSTRM-device ",
  "8.18.2" => "19.09.2019  sample streams changed in comref, support of attr noLink in Streaming-Device ",
  "8.18.1" => "18.09.2019  fix warnings, Forum: https://forum.fhem.de/index.php/topic,45671.msg975610.html#msg975610 ",
  "8.18.0" => "13.09.2019  change usage of own hashes to central %data hash, release unnecessary allocated memory ",
  "8.17.0" => "12.09.2019  fix warnings, support hide buttons in streaming device, change handle delete SNAPOLDHASH ",
  "8.16.3" => "13.08.2019  commandref revised ",
  "8.16.2" => "17.07.2019  change function ptzPanel using css stylesheet ",
  "8.16.1" => "16.07.2019  fix warnings ",
  "8.16.0" => "14.07.2019  change detail link generation from SSCamSTRM to SSCam ",
  "8.15.2" => "14.07.2019  fix order of snaps in snapgallery when adding new snaps, fix english date formating in composeGallery, ".
                           "align center of FTUI table, set compatibility to 8.2.5 ",
  "8.15.1" => "11.07.2019  enhancement and bugfixes for refresh of SSCamSTRM devices (integrate FUUID) ",
  "8.15.0" => "09.07.2019  support of SSCamSTRM get function and FTUI widget ",
  "1.0.0"  => "12.12.2015  initial, changed completly to HttpUtils_NonblockingGet "
);

# Versions History extern
my %vNotesExtern = (
  "9.9.0"   => "21.05.2021 The new get command 'saveLastSnap' to save the last snapshot locally is now available. ",
  "9.8.0"   => "27.09.2020 New get command 'apiInfo' retrieves the API information and opens a popup window to show it.  ", 
  "9.6.0"   => "12.08.2020 The new attribute 'ptzNoCapPrePat' is available. It's helpful if your PTZ camera doesn't have the capability ".
                           "to deliver Presets and Patrols. Setting the attribute avoid error log messages in that case. ",      
  "9.5.0"   => "15.07.2020 A new type 'master' supplements the possible createStreamDev command options. The streaming type ".
                           "'master' cannot play back streams itself, but opens up new possibilities by flexibly accepting streams from ".
                           "other defined streaming devices. ".
                           "More information about the possibilities is described in this ".
                           "<a href=\"https://wiki.fhem.de/wiki/SSCAM_-_Steuerung_von_Kameras_in_Synology_Surveillance_Station#Das_Streaming_Master_Device_-_Typ_.22master.22\">Wiki article</a>. ",
  "9.3.0"   => "25.06.2020 Cameras with zoom function can also be controlled by FHEM. With the setter \"setZoom\", the zoom in/out ".
                           "can be triggered in two steps. In the PTZ streaming device or FTUI, pushbuttons are provided for this purpose.",
  "9.1.0"   => "10.12.2019 With the new attribute \"snapChatTxt\" it is possible to send snapshots by the Synology Chat server. ".
                           "Please read more information about the possibilities in the ".
                           "<a href=\"https://wiki.fhem.de/wiki/SSCAM_-_Steuerung_von_Kameras_in_Synology_Surveillance_Station#Versand_von_Aufnahmen_und_Schnappsch.C3.BCssen_mit_Synology_Chat_.28SSChatBot.29\">Wiki</a>. ",
  "9.0.0"   => "06.10.2019 To store image and recording data used by streaming devices or for transmission by email and telegram, ".
                           "several cache types can be used now. So in-memory caches are available or file- and Redis-cache support ".
                           "is intergated. In both latter cases the FHEM-process RAM is released. All transmission processes ".
                           "(send image/recording data by email and telegram) are optimized for less memory footprint. ".
                           "Please see also the new cache-attributes \"cacheType\", \"cacheServerParam\" and \"debugCachetime\". ",
  "8.19.0"  => "21.09.2019 A new attribute \"hideAudio\" in Streaming devices is supportet. Use this attribute to hide the ".
                           "audio control panel in Streaming device. ",
  "8.18.2"  => "19.09.2019 SSCam supports the new attribute \"noLink\" in streaming devices ",
  "8.15.0"  => "09.07.2019 support of integrating Streaming-Devices in a SSCam FTUI widget ",
  "8.14.0"  => "01.06.2019 In detailview are buttons provided to open the camera native setup screen or Synology Surveillance Station and the Synology Surveillance Station online help. ",
  "8.12.0"  => "25.03.2019 Delay FHEM shutdown as long as sessions are not terminated, but not longer than global attribute \"maxShutdownDelay\". ",
  "8.11.0"  => "25.02.2019 compatibility set to SVS version 8.2.3, Popup possible for streaming devices of type \"generic\", ".
                           "support for \"genericStrmHtmlTag\" in streaming devices ",
  "8.10.0"  => "15.02.2019 Possibility of send recordings by telegram is integrated as well as sending snapshots ",
  "8.9.0"   => "05.02.2019 A new streaming device type \"lastsnap\" was implemented. You can create such device with \"set ... createStreamDev lastsnap\". ".
                           "This streaming device shows the newest snapshot which was taken. ",
  "8.8.0"   => "01.02.2019 Snapshots can now be sent by telegramBot ",
  "8.7.0"   => "27.01.2019 SMTP Email delivery of recordings implemented. You can send a recording after it was created subsequentely ".
                           "with the integrated Email client. You have to store SMTP credentials with \"smtpcredentials\" before. ",
  "8.6.2"   => "25.01.2019 fix version numbering ",
  "8.6.1"   => "21.01.2019 new attribute \"snapReadingRotate\" to activate versioning of snap data, ".
               "time format in readings and galleries depends from global language attribute ",
  "8.5.0"   => "17.01.2019 SVS device has \"snapCams\" command. Now are able to take snapshots of all defined cameras and may ".
               "optionally send them alltogether by Email.",
  "8.4.0"   => "07.01.2019 Command snap is extended to syntax \"snap [number] [lag] [snapEmailTxt:\"subject => &lt;Betreff-Text&gt;, body => ".
               "&lt;Mitteilung-Text&gt;\"]\". Now you are able to trigger several number of ".
               "snapshots by only one snap-command. The triggered snapshots can be shipped alltogether with the internal email client. ",
  "8.3.0"   => "02.01.2019 new get command \"saveRecording\"",
  "8.2.0"   => "02.01.2019 SMTP Email delivery of snapshots implemented. You can send snapshots after it was created subsequentely ".
                           "with the integrated Email client. You have to store SMTP credentials with \"smtpcredentials\" before. ",
  "8.1.0"   => "19.12.2018 Tooltipps added to camera device control buttons.",
  "8.0.0"   => "18.12.2018 HLS is integrated using sscam_hls.js in Streaming device types \"hls\". HLS streaming is now available ".
               "for all common used browser types. Tooltipps are added to streaming devices and snapgallery.",
  "7.7.0"   => "10.12.2018 autocreateCams command added to SVS device. By this command all cameras installed in SVS can be ".
               "defined automatically. <br>".
               "In SSCamSTRM devices the \"set &lt;name&gt; popupStream\" command is implemented which may open a popup window with the ".
               "active streaming content. ",
  "7.6.0"   => "02.12.2018 The PTZ panel is completed by \"Preset\" and \"Patrol\" (only for PTZ cameras) ",
  "7.5.0"   => "02.12.2018 A click on suitable content in a stream- or snapgallery device opens a popup window. ".
                "The popup size can be adjusted by attribute \"popupWindowSize\". ",
  "7.4.0"   => "20.11.2018 new command \"createReadingsGroup\". By this command a ReadingsGroup with a name of your choice (or use the default name) can be created. ".
               "Procedure changes of taking snapshots avoid inaccuracies if camera names in SVS very similar. ",
  "7.3.2"   => "12.11.2018 fix Warning if 'livestreamprefix' is set to DEF, COMPATIBILITY set to 8.2.2 ",
  "7.3.0"   => "28.10.2018 In attribute \"livestreamprefix\" can now \"DEF\" be specified to overwrite livestream address by specification from device definition ",
  "7.2.1"   => "23.10.2018 COMPATIBILITY changed to 8.2.1 ",
  "7.2.0"   => "20.10.2018 direct help for attributes, new get versionNotes command, please see commandref for details ",
  "7.1.1"   => "18.10.2018 Message of \"current/simulated SVS-version...\" changed, commandref corrected ",
  "7.1.0"   => "02.09.2018 PIR Sensor enable/disable, Set/Get optimized ",
  "7.0.1"   => "27.08.2018 enable/disable issue (https://forum.fhem.de/index.php/topic,45671.msg830869.html#msg830869) ",
  "7.0.0"   => "27.07.2018 compatibility to API v2.8 ",
  "6.0.1"   => "04.07.2018 Reading CamFirmware ",
  "6.0.0"   => "03.07.2018 HTTPS Support, buttons for refresh SSCamSTRM-devices ",
  "5.2.7"   => "26.06.2018 fix state turns to \"off\" even though cam is disabled ",
  "5.2.5"   => "18.06.2018 trigger lastsnap_fw to SSCamSTRM-Device only if snap was done by it. ",
  "5.2.4"   => "17.06.2018 composeGallery added and write warning if old composeGallery-weblink device is used  ",
  "5.2.2"   => "16.06.2018 compatibility to SSCamSTRM V 1.1.0 ",
  "5.2.1"   => "14.06.2018 design change of streamDev, change in event generation for streamDev, fix global vars ",
  "5.2.0"   => "14.06.2018 support longpoll refresh of SSCamSTRM-Devices ",
  "5.1.0"   => "13.06.2018 more control elements (Start/Stop Recording, Take Snapshot) in func streamDev, control of detaillink is moved to SSCamSTRM-device ",
  "5.0.1"   => "12.06.2018 control of page refresh improved (for e.g. Floorplan,Dashboard) ",
  "4.2.0"   => "22.05.2018 PTZ-Panel integrated to created StreamDevice ",
  "4.0.0"   => "01.05.2018 AudioStream possibility added ",
  "3.10.0"  => "24.04.2018 createStreamDev added, new features lastrec_fw_MJPEG, lastrec_fw_MPEG4/H.264 added to playback MPEG4/H.264 videos ",
  "3.9.1"   => "20.04.2018 Attribute ptzPanel_use, initial webcommands in DeviceOverview changed, minor fixes ptzPanel ",
  "3.9.0"   => "17.04.2018 control panel & PTZcontrol weblink device for PTZ cams ",
  "3.8.4"   => "06.04.2018 Internal MODEL changed to SVS or \"CamVendor - CamModel\" for Cams ",
  "3.8.3"   => "05.04.2018 bugfix V3.8.2, \$OpMode \"Start\" changed, composeGallery changed ",
  "3.6.0"   => "25.03.2018 setPreset command ",
  "3.5.0"   => "22.03.2018 new get command listPresets ",
  "3.4.0"   => "21.03.2018 new commands startTracking, stopTracking ",
  "3.3.1"   => "20.03.2018 new readings CapPTZObjTracking, CapPTZPresetNumber ",
  "3.3.0"   => "25.02.2018 code review, API bug fix of runview lastrec, commandref revised (forum:#84953) ",
  "3.2.4"   => "18.11.2017 fix bug don't retrieve __getPtzPresetList if cam is disabled ",
  "3.2.3"   => "08.10.2017 set optimizeParams, get caminfo (simple), minor bugfix, commandref revised ",
  "3.2.0"   => "27.09.2017 new command get listLog, change to \$hash->{HELPER}{\".SNAPHASH\"} for avoid huge \"list\"-report ",
  "3.1.0"   => "26.09.2017 move extevent from CAM to SVS model, Reading PollState enhanced for CAM-Model, minor fixes ",
  "3.0.0"   => "23.09.2017 Internal MODEL SVS or CAM -> distinguish/support Cams and SVS in different devices new comand get storedCredentials, commandref revised ",
  "2.9.0"   => "20.09.2017 new function get homeModeState, minor fixes at simu_SVSversion, commandref revised ",
  "2.6.0"   => "06.08.2017 new command createSnapGallery ",
  "2.5.4"   => "05.08.2017 analyze \$hash->{CL} in SetFn bzw. GetFn, set snapGallery only if snapGalleryBoost=1 is set, some snapGallery improvements and fixes ",
  "2.5.3"   => "02.08.2017 implement snapGallery as set-command ",
  "2.2.2"   => "11.06.2017 bugfix login, loginReturn, Forum: https://forum.fhem.de/index.php/topic,45671.msg646701.html#msg646701 ",
  "1.39.0"  => "20.01.2017 compatibility to SVS 8.0.0, Version in Internals, execute getSvsInfo after set credentials ",
  "1.37.0"  => "10.10.2016 bugfix Experimental keys on scalar is now forbidden (Perl >= 5.23) (Forum: #msg501709) ",
  "1.34.0"  => "15.09.2016 simu_SVSversion changed, added 407 errorcode message, external recording changed for SVS 7.2 ",
  "1.33.0"  => "21.08.2016 function get stmUrlPath added, fit to new commandref style, attribute showStmInfoFull added ",
  "1.31.0"  => "15.08.2016 Attr \"noQuotesForSID\" added, avoid possible 402 - permission denied problems in some SVS/DS-combinations ",
  "1.28.0"  => "30.06.2016 Attr \"showPassInLog\" added, per default no password will be shown in log ",
  "1.27.0"  => "29.06.2016 Attr \"simu_SVSversion\" added, sub login_nonbl changed, sub camret_nonbl changed (getlistptzpreset) due to 7.2 problem ",
  "1.26.2"  => "05.05.2016 change: get \"snapfileinfo\" will get back an Infomessage if Reading \"LastSnapId\" isn't available ",
  "1.26.1"  => "27.04.2016 bugfix module will not load due to Unknown warnings category 'experimental' when using an older perl version  ",
  "1.26.0"  => "22.04.2016 Attribute \"disable\" to deactivate the module added ",
  "1.25.0"  => "18.04.2016 motion detection parameters can be entered if motion detection by camera or SVS is used ",
  "1.24.0"  => "16.04.2016 behavior of \"set ... on\" changed, Attr \"recextend\" added, bugfix: setstate-warning if FHEM will restarted and SVS is not reachable (Forum: #308) ",
  "1.22.0"  => "27.03.2016 bugfix \"link_open\" doesn't work after last update ",
  "1.21.0"  => "23.03.2016 added \"lastrec\", \"lastrec_open\" to playback last recording  ",
  "1.20.0"  => "09.03.2016 command \"extevent\" added ",
  "1.19.3"  => "07.03.2016 bugfix \"uninitialized value \$lastrecstarttime\", \"uninitialized value \$lastrecstoptime\", new attribute \"videofolderMap\" ",
  "1.19.2"  => "06.03.2016 Reading \"CamLastRec\" added which contains Path/name of last recording ",
  "1.19.1"  => "28.02.2016 enhanced command runView by option \"link_open\" to open a streamlink immediately ",
  "1.19.0"  => "25.02.2016 functions for cam-livestream added ",
  "1.18.1"  => "21.02.2016 fixed a problem that the state is \"disable\" instead of \"disabled\" if a camera is disabled and FHEM will be restarted ",
  "1.18.0"  => "20.02.2016 function \"get ... eventlist\" added, Reading \"CamEventNum\" added which containes total number of camera events, change usage of reading \"LastUpdateTime\"  ",
  "1.17.0"  => "19.02.2016 function \"runPatrol\" added that starts predefined patrols of PTZ-cameras, Reading \"CamDetMotSc\" added ",
  "1.16.0"  => "16.02.2016 set up of motion detection source now possible ",
  "1.15.0"  => "15.02.2016 control of exposure mode day, night & auto is possible now ",
  "1.14.0"  => "14.02.2016 The port in DEF-String is optional now, if not given, default port 5000 is used ",
  "1.13.2"  => "13.02.2016 fixed a problem that manual updates using \"getcaminfoall\" are leading to additional pollingloops if polling is used, attribute \"debugactivetoken\" added for debugging-use  ",
  "1.13.1"  => "12.02.2016 fixed a problem that a usersession won't be destroyed if a function couldn't be executed successfully ",
  "1.12.0"  => "08.02.2016 added function \"move\" for continuous PTZ action ",
  "1.11.0"  => "05.02.2016 added function \"goPreset\" and \"goAbsPTZ\" to control the move of PTZ lense to absolute positions (http://forum.fhem.de/index.php/topic,45671.msg404275.html#msg404275), (http://forum.fhem.de/index.php/topic,45671.msg404892.html#msg404892) ",
  "1.10.0"  => "02.02.2016 added function \"svsinfo\" to get informations about installed SVS-package, if Availability = \"disconnected\" then \"state\"-value will be \"disconnected\" too, saved Credentials were deleted from file if a device will be deleted ",
  "1.7.0"   => "18.01.2016 Attribute \"httptimeout\" added ",
  "1.6.0"   => "16.01.2016 Change the define-string related to rectime. (http://forum.fhem.de/index.php/topic,45671.msg391664.html#msg391664)   ",                
  "1.5.1"   => "11.01.2016 Vars \"USERNAME\" and \"RECTIME\" removed from internals, Var (Internals) \"SERVERNAME\" changed to \"SERVERADDR\" ",
  "1.5.0"   => "04.01.2016 Function \"Get\" for creating Camera-Readings integrated, Attributs pollcaminfoall, pollnologging added, Function for Polling Cam-Infos added. ",
  "1.4.0"   => "23.12.2015 function \"enable\" and \"disable\" for SS-Cams added, changed timout of Http-calls to a higher value ",
  "1.3.0"   => "19.12.2015 function \"snap\" for taking snapshots added, fixed a bug that functions may impact each other  ",
  "1.0.0"   => "12.12.2015 initial, changed completly to HttpUtils_NonblockingGet "
);

# Tooltipps Textbausteine (http://www.walterzorn.de/tooltip/tooltip.htm#download), §NAME§ wird durch Kameranamen ersetzt 
my %ttips_en = (
  ttrefresh   => "The playback of streaming content of camera of &quot;§NAME§&quot; will be restartet.",
  ttrecstart  => "Start an endless recording of camera &quot;§NAME§&quot;.\nYou have to stop the recording manually.",
  ttrecstop   => "Stopp the recording of camera &quot;§NAME§&quot;.",
  ttsnap      => "Take a snapshot of camera &quot;§NAME§&quot;.",
  ttcmdstop   => "Stopp playback of camera &quot;§NAME§&quot;",
  tthlsreact  => "Reactivate HTTP Livestreaming Interface of camera &quot;§NAME§&quot;.\nThe camera is enforced to restart HLS transmission.",
  ttmjpegrun  => "Playback the MJPEG Livestream of camera &quot;§NAME§&quot;.",
  tthlsrun    => "Playback the native HTTP Livestream of camera &quot;§NAME§&quot;. The browser must have native support for HLS streaming.",
  ttlrrun     => "Playback of last recording of camera &quot;§NAME§&quot; in an iFrame.\nBoth MJPEG and H.264 recordings are rendered.",
  tth264run   => "Playback of last H.264 recording of camera &quot;§NAME§&quot;.\nIt only starts if the recording is type H.264",
  ttlmjpegrun => "Playback of last MJPEG recording of camera &quot;§NAME§&quot;.\nIt only starts if the recording is type MJPEG",
  ttlsnaprun  => "Playback of last snapshot of camera &quot;§NAME§&quot;.",
  confcam     => "The configuration menu of camera &quot;§NAME§&quot; will be opened in a new Browser page",
  confsvs     => "The configuration page of Synology Surveillance Station will be opened in a new Browser page",
  helpsvs     => "The online help page of Synology Surveillance Station will be opened in a new Browser page",
);
      
my %ttips_de = (
  ttrefresh   => "Die Wiedergabe des Streams von Kamera &quot;§NAME§&quot; wird neu gestartet.",
  ttrecstart  => "Startet eine Endlosaufnahme von Kamera &quot;§NAME§&quot;.\nDie Aufnahme muß manuell gestoppt werden.",
  ttrecstop   => "Stoppt die laufende Aufnahme von Kamera &quot;§NAME§&quot;.",
  ttsnap      => "Ein Schnappschuß von Kamera &quot;§NAME§&quot; wird aufgenommen.", 
  ttcmdstop   => "Stopp Wiedergabe von Kamera &quot;§NAME§&quot;",
  tthlsreact  => "Reaktiviert das HTTP Livestreaming Interface von Kamera &quot;§NAME§&quot;.\nDie Kamera wird aufgefordert die HLS Übertragung zu restarten.",     
  ttmjpegrun  => "Wiedergabe des MJPEG Livestreams von Kamera &quot;§NAME§&quot;",
  tthlsrun    => "Wiedergabe des HTTP Livestreams von Kamera &quot;§NAME§&quot;.\nEs wird die HLS Funktion der Synology Surveillance Station verwendet. (der Browser muss HLS nativ unterstützen)",
  ttlrrun     => "Wiedergabe der letzten Aufnahme von Kamera &quot;§NAME§&quot; in einem iFrame.\nEs werden sowohl MJPEG als auch H.264 Aufnahmen wiedergegeben.",
  tth264run   => "Wiedergabe der letzten H.264 Aufnahme von Kamera &quot;§NAME§&quot;.\nDie Wiedergabe startet nur wenn die Aufnahme vom Typ H.264 ist.",
  ttlmjpegrun => "Wiedergabe der letzten MJPEG Aufnahme von Kamera &quot;§NAME§&quot;.\nDie Wiedergabe startet nur wenn die Aufnahme vom Typ MJPEG ist.", 
  ttlsnaprun  => "Wiedergabe des letzten Schnappschusses von Kamera &quot;§NAME§&quot;.",
  confcam     => "Das Konfigurationsmenü von Kamera &quot;§NAME§&quot; wird in einer neuen Browserseite geöffnet",
  confsvs     => "Die Konfigurationsseite der Synology Surveillance Station wird in einer neuen Browserseite geöffnet",
  helpsvs     => "Die Onlinehilfe der Synology Surveillance Station wird in einer neuen Browserseite geöffnet",
);

my %hset = (                                                                # Hash für Set-Funktion (needcred => 1: Funktion benötigt gesetzte Credentials)
  credentials         => { fn => "_setcredentials",         needcred => 0 },                     
  smtpcredentials     => { fn => "_setsmtpcredentials",     needcred => 0 },
  on                  => { fn => "_seton",                  needcred => 1 },
  off                 => { fn => "_setoff",                 needcred => 1 },
  snap                => { fn => "_setsnap",                needcred => 1 },
  snapCams            => { fn => "_setsnapCams",            needcred => 1 },
  startTracking       => { fn => "_setstartTracking",       needcred => 1 },
  stopTracking        => { fn => "_setstopTracking",        needcred => 1 },
  setZoom             => { fn => "_setsetZoom",             needcred => 1 },
  snapGallery         => { fn => "_setsnapGallery",         needcred => 1 },
  createSnapGallery   => { fn => "_setcreateSnapGallery",   needcred => 1 },
  createPTZcontrol    => { fn => "_setcreatePTZcontrol",    needcred => 1 },
  createStreamDev     => { fn => "_setcreateStreamDev",     needcred => 1 },
  createReadingsGroup => { fn => "_setcreateReadingsGroup", needcred => 1 },
  enable              => { fn => "_setenable",              needcred => 1 },
  disable             => { fn => "_setdisable",             needcred => 1 },
  motdetsc            => { fn => "_setmotdetsc",            needcred => 1 },
  expmode             => { fn => "_setexpmode",             needcred => 1 },
  homeMode            => { fn => "_sethomeMode",            needcred => 1 },
  autocreateCams      => { fn => "_setautocreateCams",      needcred => 1 },
  goPreset            => { fn => "_setgoPreset",            needcred => 1 },
  optimizeParams      => { fn => "_setoptimizeParams",      needcred => 1 },
  pirSensor           => { fn => "_setpirSensor",           needcred => 1 },
  runPatrol           => { fn => "_setrunPatrol",           needcred => 1 },
  goAbsPTZ            => { fn => "_setgoAbsPTZ",            needcred => 1 },
  move                => { fn => "_setmove",                needcred => 1 },
  runView             => { fn => "_setrunView",             needcred => 1 },
  hlsreactivate       => { fn => "_sethlsreactivate",       needcred => 1 },
  hlsactivate         => { fn => "_sethlsactivate",         needcred => 1 },
  refresh             => { fn => "_setrefresh",             needcred => 0 },
  extevent            => { fn => "_setextevent",            needcred => 1 },
  stopView            => { fn => "_setstopView",            needcred => 1 },
  setPreset           => { fn => "_setsetPreset",           needcred => 1 },
  setHome             => { fn => "_setsetHome",             needcred => 1 },
  delPreset           => { fn => "_setdelPreset",           needcred => 1 },
);

my %hget = (                                                                # Hash für Get-Funktion (needcred => 1: Funktion benötigt gesetzte Credentials)
  apiInfo           => { fn => "_getapiInfo",           needcred => 1 },  
  caminfo           => { fn => "_getcaminfo",           needcred => 1 },
  caminfoall        => { fn => "_getcaminfoall",        needcred => 1 },
  homeModeState     => { fn => "_gethomeModeState",     needcred => 1 },
  listLog           => { fn => "_getlistLog",           needcred => 1 },
  listPresets       => { fn => "_getlistPresets",       needcred => 1 },
  saveRecording     => { fn => "_getsaveRecording",     needcred => 1 },
  saveLastSnap      => { fn => "_getsaveLastSnap",      needcred => 0 },
  svsinfo           => { fn => "_getsvsinfo",           needcred => 1 },
  storedCredentials => { fn => "_getstoredCredentials", needcred => 1 },
  snapGallery       => { fn => "_getsnapGallery",       needcred => 1 },
  snapinfo          => { fn => "_getsnapinfo",          needcred => 1 },
  snapfileinfo      => { fn => "_getsnapfileinfo",      needcred => 1 },
  eventlist         => { fn => "_geteventlist",         needcred => 1 },
  stmUrlPath        => { fn => "_getstmUrlPath",        needcred => 1 },
  scanVirgin        => { fn => "_getscanVirgin",        needcred => 1 },
  versionNotes      => { fn => "_getversionNotes",      needcred => 1 },
);

my %hparse = (                                                              # Hash der Opcode Parse Funktionen
  Start            => { fn => "_parseStart",            },
  Stop             => { fn => "_parseStop",             },
  GetRec           => { fn => "_parseGetRec",           },
  MotDetSc         => { fn => "_parseMotDetSc",         },
  getsvslog        => { fn => "_parsegetsvslog",        },
  SaveRec          => { fn => "_parseSaveRec",          },
  gethomemodestate => { fn => "_parsegethomemodestate", },
  getPresets       => { fn => "_parsegetPresets",       },
  Snap             => { fn => "_parseSnap",             },
  getsvsinfo       => { fn => "_parsegetsvsinfo",       },
  runliveview      => { fn => "_parserunliveview",      },
  getStmUrlPath    => { fn => "_parsegetStmUrlPath",    },
  Getcaminfo       => { fn => "_parseGetcaminfo",       },
  Getptzlistpatrol => { fn => "_parseGetptzlistpatrol", },
  Getptzlistpreset => { fn => "_parseGetptzlistpreset", },
  Getcapabilities  => { fn => "_parseGetcapabilities",  },
  getmotionenum    => { fn => "_parsegetmotionenum",    },
  geteventlist     => { fn => "_parsegeteventlist",     },
  gopreset         => { fn => "_parsegopreset",         },
  getsnapinfo      => { fn => "_parsegetsnapinfo",      },
  getsnapgallery   => { fn => "_parsegetsnapgallery",   },
);

my %hdt = (                                                                 # Delta Timer Hash für Zeitsteuerung der Funktionen
  __camSnap          => 0.2,                                                # ab hier hohe Prio
  __camStartRec      => 0.3,                                                
  __camStopRec       => 0.3,
  __startTrack       => 0.3,
  __stopTrack        => 0.3,
  __moveStop         => 0.3,
  __doPtzAaction     => 0.4,
  __setZoom          => 0.4,
  __getSnapFilename  => 0.5,
  __runLiveview      => 0.5,
  __stopLiveview     => 0.5,
  __extEvent         => 0.5,
  __camEnable        => 0.5,
  __camDisable       => 0.5,
  __setOptParams     => 0.6,                                                # ab hier mittlere Prio
  __setHomeMode      => 0.6,
  __getHomeModeState => 0.7,
  __getRec           => 0.7,
  __getCapabilities  => 0.7,
  __activateHls      => 0.7,
  __reactivateHls    => 0.7,
  __getSvsLog        => 0.8,
  __getRecAndSave    => 0.9,
  __getSvsInfo       => 1.0,
  __camExpmode       => 1.1,
  __getPresets       => 1.2,
  __setPreset        => 1.2,
  __setHome          => 1.2,
  __managePir        => 1.2,
  __delPreset        => 1.4,
  __getStreamFormat  => 1.4,
  __getSnapInfo      => 1.7,                                                # ab hier niedrige Prio
  __camMotDetSc      => 1.8,
  __getStmUrlPath    => 2.0,
  __getEventList     => 2.0,
  __getMotionEnum    => 2.0,
  __getPtzPresetList => 2.0,
  __getPtzPatrolList => 2.0,
  __getCamInfo       => 2.0,
  __camAutocreate    => 2.1,
  __sessionOff       => 2.7,
  __getApiInfo       => 2.7,
);

my %imc = (                                                                 # disbled String modellabhängig (SVS / CAM)
  0 => { 0 => "initialized", 1 => "inactive" },
  1 => { 0 => "off",         1 => "inactive" },              
);

my %hexmo = (                                                               # Hash Exposure Modes
  auto  => 0,
  day   => 1,
  night => 2,
);

my %hrkeys = (                                                              # Hash der möglichen Response Keys 
  camLiveMode      => { 0  => "Liveview from DS", 1 => "Liveview from Camera", },
  source           => { -1 => "disabled",         0 => "Camera",                 1 => "SVS", },   
  deviceType       => { 1  => "Camera",           2 => "Video_Server",           4 => "PTZ",          8 => "Fisheye", },
  camStatus        => { 1  => "enabled",          2 => "deleted",                3 => "disconnected", 4 => "unavailable", 5  => "ready",   6 => "inaccessible", 7 => "disabled", 8 => "unrecognized", 9 => "setting", 10 => "Server disconnected", 11 => "migrating", 12 => "others", 13 => "Storage removed", 14 => "stopping", 15 => "Connect hist failed", 16 => "unauthorized", 17 => "RTSP error", 18 => "No video", },    
  exposure_control => { 0  => "Auto",             1 => "50HZ",                   2 => "60HZ",         3 => "Hold",        4  => "Outdoor", 5 => "None",         6 => "Unknown", }, 
  camAudioType     => { 0  => "Unknown",          1 => "PCM",                    2 => "G711",         3 => "G726",        4  => "AAC",     5 => "AMR", },
  exposure_mode    => { 0  => "Auto",             1 => "Day",                    2 => "Night",        3 => "Schedule",    4  => "Unknown", },
  userPriv         => { 0  => "No Access",        1 => "Admin",                  2 => "Manager",      4 => "Viewer",      FF => "All", },
  ptzFocus         => { 0  => "false",            1 => "support step operation", 2 => "support continuous operation", },
  ptzTilt          => { 0  => "false",            1 => "support step operation", 2 => "support continuous operation", },
  ptzZoom          => { 0  => "false",            1 => "support step operation", 2 => "support continuous operation", },
  ptzPan           => { 0  => "false",            1 => "support step operation", 2 => "support continuous operation", },
  ptzIris          => { 0  => "false",            1 => "support step operation", 2 => "support continuous operation", },
);

my %zd = (                                                                  # Hash der Zoomsteuerung 
  ".++"  => {dir => "in",  sttime => 6,     moveType => "Start", panimg => "Zoom_in_wide_w.png",     },
  "+"    => {dir => "in",  sttime => 0.5,   moveType => "Start", panimg => "Zoom_in_w.png",          },
  "stop" => {dir => undef, sttime => undef, moveType => "Stop" , panimg => "black_btn_CAMBLANK.png", },
  "-"    => {dir => "out", sttime => 0.5,   moveType => "Start", panimg => "Zoom_out_w.png",         },
  "--."  => {dir => "out", sttime => 6,     moveType => "Start", panimg => "Zoom_out_wide_w.png",    }
);

my %sdfn = (                                                               # Funktionshash Streamingdevices
  "mjpeg"    => {fn => "_streamDevMJPEG"    },
  "lastsnap" => {fn => "_streamDevLASTSNAP" },
  "generic"  => {fn => "_streamDevGENERIC"  },
  "hls"      => {fn => "_streamDevHLS"      },
  "switched" => {fn => "_streamDevSWITCHED" },
);

my %sdswfn = (                                                             # Funktionshash Streamingdevices Typ "switched"
  "image"     => {fn => "__switchedIMAGE"     },
  "iframe"    => {fn => "__switchedIFRAME"    },
  "video"     => {fn => "__switchedVIDEO"     },
  "base64img" => {fn => "__switchedBASE64IMG" },
  "embed"     => {fn => "__switchedEMBED"     },
  "hls"       => {fn => "__switchedHLS"       },
);

# Standardvariablen und Forward-Deklaration
my $defSlim           = 3;                                 # default Anzahl der abzurufenden Schnappschüsse mit snapGallery
my $defColumns        = 3;                                 # default Anzahl der Spalten einer snapGallery
my $defSnum           = "1,2,3,4,5,6,7,8,9,10";            # mögliche Anzahl der abzurufenden Schnappschüsse mit snapGallery
my $compstat          = "8.2.8";                           # getestete SVS-Version
my $valZoom           = ".++,+,stop,-,--.";                # Inhalt des Setters "setZoom"
my $shutdownInProcess = 0;                                 # Statusbit shutdown
my $todef             = 20;                                # httptimeout default Wert

#use vars qw($FW_ME);                                      # webname (default is fhem), used by 97_GROUP/weblink
#use vars qw($FW_subdir);                                  # Sub-path in URL, used by FLOORPLAN/weblink
#use vars qw($FW_room);                                    # currently selected room
#use vars qw($FW_detail);                                  # currently selected device for detail view
#use vars qw($FW_wname);                                   # Web instance

#############################################################################################
#                                       Hint Hash EN           
#############################################################################################
my %vHintsExt_en = (
  "9" => "Further infomations about sending snapshots and recordings by Synology Chat server in our ".
         "<a href=\"https://wiki.fhem.de/wiki/SSCAM_-_Steuerung_von_Kameras_in_Synology_Surveillance_Station#Versand_von_Aufnahmen_und_Schnappsch.C3.BCssen_mit_Synology_Chat_.28SSChatBot.29\">Wiki</a>. ".
         "In addition here is provided the link to the <a href=\"https://www.synology.com/en-us/knowledgebase/DSM/help/Chat/chat_desc\">Chat knowledgebase</a>. <br><br>",
  "8" => "Link to official <a href=\"https://community.synology.com/forum/3\">Surveillance Forum</a> in Synology community".
         "<br><br>",
  "7" => "<b>Setup Email Shipping <br>".
         "==================== </b> <br><br>".
         "Snapshots can be sent by <b>Email</b> alltogether after creation. For this purpose the module contains<br>". 
         "its own Email client.<br>". 
         "Before you can use this function you have to install the Perl-module <b>MIME::Lite</b>. On debian systems it can be ". 
         "installed with command:".  
         "<ul>". 
         "<b>sudo apt-get install libmime-lite-perl</b>". 
         "</ul>". 
         "There are some attributes must be set or can be used optionally.<br>". 
         "At first the Credentials for access the Email outgoing server must be set by command <b>\"set &lt;name&gt; smtpcredentials &lt;user&gt; &lt;password&gt;\"</b><br>". 
         "The connection to the server is initially established unencrypted and switches to an encrypted connection if SSL<br>". 
         "encryption is available. In that case the transmission of User/Password takes place encrypted too.<br>". 
         "If attribute \"smtpSSLPort\" is defined, the established connection to the Email server will be encrypted immediately.<br><br>". 
         "Attributes which are optional are marked: <br><br>".
         "<ul>".         
         "<li><b>snapEmailTxt</b> - <b>Activates the Email shipping.</b> This attribute has the format: <br>". 
         "<ul><b>subject => &lt;subject text&gt;, body => &lt;message text&gt;</b></ul>". 
         "The placeholder \$CAM, \$DATE and \$TIME can be used. <br>".  
         "\$CAM is replaced by the device name, device alias or the name of camera in SVS if alias is not defined.<br>".  
         "\$DATE and \$TIME are replaced with the current date and time.</li>". 
         "<li><b>smtpHost</b> - Hostname or IP-address of outgoing Email server (e.g. securesmtp.t-online.de)</li>". 
         "<li><b>smtpFrom</b> - Return address (&lt;name&gt@&lt;domain&gt)</li>". 
         "<li><b>smtpTo</b> - Receiving address(es) (&lt;name&gt@&lt;domain&gt)</li>". 
         "<li><b>smtpPort</b> - (optional) Port of outgoing Email server (default: 25)</li>". 
         "<li><b>smtpCc</b> - (optional) carbon-copy receiving address(es) (&lt;name&gt@&lt;domain&gt)</li>". 
         "<li><b>smtpNoUseSSL</b> - (optional) \"1\" if no SSL encryption should be used for Email shipping (default: 0)</li>". 
         "<li><b>smtpSSLPort</b> - (optional) Port for SSL encrypted connection (default: 465)</li>". 
         "<li><b>smtpDebug</b> - (optional) switch on the debugging of SMTP connection</li>". 
         "</ul>".          
         "For further information please see description of the <a href=\"https://fhem.de/commandref.html#SSCamattr\">attributes</a>.".
         "<br><br>",
  "6" => "There are some Icons in directory www/images/sscam available for SSCam. Thereby the system can use the icons please do: <br>".
         "<ul><li> in FHEMWEB device attribute <b>iconPath</b> complete with \"sscam\". e.g.: attr WEB iconPath default:fhemSVG:openautomation:sscam </li></ul>".
         "After that execute \"rereadicons\" or restart FHEM. ".
         "<br><br>",
  "5" => "Find more Informations about manage users and the appropriate privilege profiles in ".
         "<a href=\"https://www.synology.com/en-global/knowledgebase/Surveillance/help/SurveillanceStation/user\">Surveillance Station online help</a> ".
         "<br><br>",
  "4" => "The message Meldung \"WARNING - The current/simulated SVS-version ... may be incompatible with SSCam version...\" means that ".
         "the used SSCam version was currently not tested or (partially) incompatible with the installed version of Synology Surveillance Station (Reading \"SVSversion\"). ".
         "The compatible SVS-Version is printed out in the Internal COMPATIBILITY. <br>".
         "<b>Actions:</b> At first please update your SSCam version. If the message does appear furthermore, please inform the SSCam Maintainer. ".
         "To ignore this message temporary, you may reduce the verbose level of your SSCam device. ".
         "<br><br>",
  "3" => "Link to SSCam <a href=\"https://fhem.de/commandref.html#SSCam\">english commandRef</a> ".
         "<br><br>",
  "2" => "You can create own PTZ-control icons with a template available in SVN which can be downloaded here: <a href=\"https://svn.fhem.de/trac/browser/trunk/fhem/contrib/sscam\">contrib/sscam/black_btn_CAM_Template.pdn</a>.\n". 
         "This template can be edited with Paint.Net for example. ".
         "<br><br>",
  "1" => "Some helpful <a href=\"https://wiki.fhem.de/wiki/SSCAM_-_Steuerung_von_Kameras_in_Synology_Surveillance_Station\">FHEM-Wiki</a> notes".
         "<br><br>",
);

#############################################################################################
#                                       Hint Hash DE           
#############################################################################################
my %vHintsExt_de = (
  "9" => "Weitere Informationen zum Versand von Schnappschüssen und Aufnahmen mit dem Synology Chat Server findet man im ".
         "<a href=\"https://wiki.fhem.de/wiki/SSCAM_-_Steuerung_von_Kameras_in_Synology_Surveillance_Station#Versand_von_Aufnahmen_und_Schnappsch.C3.BCssen_mit_Synology_Chat_.28SSChatBot.29\">Wiki</a>. ".
         "Ergänzend dazu Hinweise zur Einrichtung und Administration des Synology Chat Servers im ".
         "<a href=\"https://www.synology.com/de-de/knowledgebase/DSM/help/Chat/chat_desc\">Support-Center</a>. <br><br>",
  "8" => "Link zur offiziellen <a href=\"https://community.synology.com/forum/3\">Surveillance Forum</a> Seite innerhalb der Synology Community".
         "<br><br>",
  "7" => "<b>Einstellung Email-Versand <br>".
         "========================= </b> <br><br>".
         "Schnappschüsse können nach der Erstellung per <b>Email</b> gemeinsam versendet werden. Dazu enthält das Modul einen<br>". 
         "eigenen Email-Client.<br>". 
         "Zur Verwendung dieser Funktion muss das Perl-Modul <b>MIME::Lite</b> installiert sein. Auf Debian-Systemen kann ". 
         "es mit".  
         "<ul>". 
         "<b>sudo apt-get install libmime-lite-perl</b>". 
         "</ul>". 
         "installiert werden. <br><br>". 
         "Für die Verwendung des Email-Versands müssen einige Attribute gesetzt oder können optional genutzt werden.<br>". 
         "Die Credentials für den Zugang zum Email-Server müssen mit dem Befehl <b>\"set &lt;name&gt; smtpcredentials &lt;user&gt; &lt;password&gt;\"</b><br>". 
         "gesetzt werden. Der Verbindungsaufbau zum Postausgangsserver erfolgt initial unverschüsselt und wechselt zu einer verschlüsselten<br>". 
         "Verbindung wenn SSL zur Verfügung steht. In diesem Fall erfolgt auch die Übermittlung von User/Password verschlüsselt.<br>". 
         "Ist das Attribut \"smtpSSLPort\" definiert, erfolgt der Verbindungsaufbau zum Email-Server sofort verschlüsselt.<br><br>". 
         "Optionale Attribute sind gekennzeichnet: <br><br>".
         "<ul>".         
         "<li><b>snapEmailTxt</b> - <b>Aktiviert den Email-Versand</b>. Das Attribut hat das Format:<br>". 
         "<ul><b>subject => &lt;Betreff-Text&gt;, body => &lt;Mitteilung-Text&gt;</b></ul>". 
         "Es können die Platzhalter \$CAM, \$DATE und \$TIME verwendet werden. <br>".  
         "\$CAM wird durch den Device-Namen, Device-Alias bzw. den Namen der Kamera in der SVS ersetzt falls der<br>". 
         "Device-Alias nicht gesetzt ist. <br>".  
         "\$DATE und \$TIME werden durch das aktuelle Datum und Zeit ersetzt.</li>". 
         "<li><b>smtpHost</b> - Hostname oder IP-Adresse des Postausgangsservers (z.B. securesmtp.t-online.de)</li>". 
         "<li><b>smtpFrom</b> - Absenderadresse (&lt;name&gt\@&lt;domain&gt)</li>". 
         "<li><b>smtpTo</b> - Empfängeradresse(n) (&lt;name&gt\@&lt;domain&gt)</li>". 
         "<li><b>smtpPort</b> - (optional) Port des Postausgangsservers (default: 25)</li>". 
         "<li><b>smtpCc</b> - (optional) Carbon-Copy Empfängeradresse(n) (&lt;name&gt\@&lt;domain&gt)</li>". 
         "<li><b>smtpNoUseSSL</b> - (optional) \"1\" wenn kein SSL beim Email-Versand verwendet werden soll (default: 0)</li>". 
         "<li><b>smtpSSLPort</b> - (optional) SSL-Port des Postausgangsservers (default: 465)</li>". 
         "<li><b>smtpDebug</b> - (optional) zum Debugging der SMTP-Verbindung setzen</li>". 
         "</ul>".          
         "Zur näheren Erläuterung siehe Beschreibung der <a href=\"https://fhem.de/commandref_DE.html#SSCamattr\">Attribute</a>.".
         "<br><br>",
  "6" => "Für SSCam wird ein Satz Icons im Verzeichnis www/images/sscam zur Verfügung gestellt. Damit das System sie findet bitte setzen: <br>".
         "<ul><li> im FHEMWEB Device Attribut <b>iconPath</b> um \"sscam\" ergänzen. z.B.: attr WEB iconPath default:fhemSVG:openautomation:sscam </li></ul>".
         "Danach ein \"rereadicons\" bzw. einen FHEM restart ausführen.".
         "<br><br>",
  "5" => "Informationen zum Management von Usern und entsprechenden Rechte-Profilen sind in der ".
         "<a href=\"https://www.synology.com/de-de/knowledgebase/Surveillance/help/SurveillanceStation/user\">Surveillance Station Online-Hilfe</a> zu finden.".
         "<br><br>",
  "4" => "Die Meldung \"WARNING - The current/simulated SVS-version ... may be incompatible with SSCam version...\" ist ein Hinweis darauf, dass ".
         "die eingesetzte SSCam Version noch nicht mit der verwendeten Version von Synology Surveillance Station (Reading \"SVSversion\") getestet ".
         "wurde oder (teilweise) mit dieser Version nicht kompatibel ist. Die kompatible SVS-Version ist im Internal COMPATIBILITY ersichtlich.<br>".
         "<b>Maßnahmen:</b> Bitte SSCam zunächst updaten. Sollte die Meldung weiterhin auftreten, bitte den SSCam Maintainer informieren. Zur ".
         "vorübergehenden Ignorierung kann der verbose Level des SSCam-Devices entsprechend reduziert werden. ".
         "<br><br>",
  "3" => "Link zur deutschen SSCam <a href=\"https://fhem.de/commandref_DE.html#SSCam\">commandRef</a> ".
         "<br><br>",
  "2" => "Zur Erstellung eigener PTZ-Steuericons gibt es eine Vorlage im SVN die hier <a href=\"https://svn.fhem.de/trac/browser/trunk/fhem/contrib/sscam\">contrib/sscam/black_btn_CAM_Template.pdn</a> heruntergeladen werden kann.\n".
         "Diese Vorlage kann zum Beispiel mit Paint.Net bearbeitet werden. ".
         "<br><br>",
  "1" => "Hilfreiche Hinweise zu SSCam im <a href=\"https://wiki.fhem.de/wiki/SSCAM_-_Steuerung_von_Kameras_in_Synology_Surveillance_Station\">FHEM-Wiki</a>".
         "<br><br>",
);

################################################################
sub Initialize {
 my $hash = shift;
 
 $hash->{DefFn}             = \&Define;
 $hash->{UndefFn}           = \&Undef;
 $hash->{DeleteFn}          = \&Delete; 
 $hash->{SetFn}             = \&Set;
 $hash->{GetFn}             = \&Get;
 $hash->{AttrFn}            = \&Attr;
 $hash->{DelayedShutdownFn} = \&delayedShutdown;
 # Aufrufe aus FHEMWEB
 $hash->{FW_summaryFn}      = \&FWsummaryFn;
 $hash->{FW_detailFn}       = \&FWdetailFn;
 $hash->{FW_deviceOverview} = 1;
 
 $hash->{AttrList} = "disable:1,0 ".
                     "debugactivetoken:1,0 ".
                     "debugCachetime:1,0 ".
                     "genericStrmHtmlTag ".
                     "hlsNetScript:1,0 ".
                     "hlsStrmObject ".
                     "httptimeout ".
                     "htmlattr ".
                     "livestreamprefix ".
                     "loginRetries:1,2,3,4,5,6,7,8,9,10 ".
                     "pollcaminfoall ".
                     "ptzNoCapPrePat:1,0 ".
                     "recChatTxt ".
                     "recEmailTxt ".
                     "recTelegramTxt ".
                     "rectime ".
                     "recextend:1,0 ".
                     "smtpCc ".
                     "smtpDebug:1,0 ".
                     "smtpFrom ".
                     "smtpHost ".
                     "smtpPort ".
                     "smtpSSLPort ".
                     "smtpTo ".
                     "smtpNoUseSSL:1,0 ".
                     "snapChatTxt ".
                     "snapEmailTxt ".
                     "snapTelegramTxt ".
                     "snapGalleryBoost:0,1 ".
                     "snapGallerySize:Icon,Full ".
                     "snapGalleryNumber:$defSnum ".
                     "snapGalleryColumns ".
                     "snapGalleryHtmlAttr ".
                     "snapReadingRotate:0,1,2,3,4,5,6,7,8,9,10 ".
                     "cacheServerParam ".
                     "cacheType:file,internal,mem,rawmem,redis ".
                     "pollnologging:1,0 ".
                     "noQuotesForSID:1,0 ".
                     "session:SurveillanceStation,DSM ".
                     "showPassInLog:1,0 ".
                     "showStmInfoFull:1,0 ".
                     "simu_SVSversion:7.2-xxxx,7.1-xxxx,8.0.0-xxxx,8.1.5-xxxx,8.2.0-xxxx ".
                     "videofolderMap ".
                     "webCmd ".
                     $readingFnAttributes;   
         
 eval { FHEM::Meta::InitMod( __FILE__, $hash ) };           ## no critic 'eval' # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)

return;   
}

################################################################
sub Define {
  # Die Define-Funktion eines Moduls wird von Fhem aufgerufen wenn der Define-Befehl für ein Gerät ausgeführt wird 
  # Welche und wie viele Parameter akzeptiert werden ist Sache dieser Funktion. Die Werte werden nach dem übergebenen Hash in ein Array aufgeteilt
  # define CamCP1 SSCAM Carport 192.168.2.20 [5000] 
  #       ($hash)  [1]    [2]        [3]      [4]  
  #
  my ($hash, $def) = @_;
  my $name         = $hash->{NAME};
  
 return "Error: Perl module ".$MMJSON." is missing. Install it on Debian with: sudo apt-get install libjson-perl" if($MMJSON);
  
  my @a = split m{\s+}x, $def;
  
  if(int(@a) < 4) {
      return "You need to specify more parameters.\n". "Format: define <name> SSCAM <Cameraname> <ServerAddress> [Port]";
  }
        
  my $camname    = $a[2];
  my $serveraddr = $a[3];
  my $serverport = $a[4] ? $a[4]     : 5000;
  my $proto      = $a[5] ? lc($a[5]) : "http";
  
  $hash->{SERVERADDR}             = $serveraddr;
  $hash->{SERVERPORT}             = $serverport;
  $hash->{CAMNAME}                = $camname;
  $hash->{MODEL}                  = ($camname =~ m/^SVS$/xi) ? "SVS" : "CAM";    # initial, CAM wird später ersetzt durch CamModel
  $hash->{PROTOCOL}               = $proto;
  $hash->{COMPATIBILITY}          = $compstat;                                   # getestete SVS-version Kompatibilität 
  $hash->{HELPER}{MODMETAABSENT}  = 1 if($modMetaAbsent);                        # Modul Meta.pm nicht vorhanden
    
  # Startwerte setzen
  if(IsModelCam($hash)) {                                                        # initiale Webkommandos setzen
      $attr{$name}{webCmd}             = "on:off:snap:enable:disable:runView:stopView";  
  } 
  else {
      $attr{$name}{webCmd}             = "homeMode";
      $attr{$name}{webCmdLabel}        = "HomeMode";
  }
  $hash->{HELPER}{ACTIVE}              = "off";                                  # Funktionstoken "off", Funktionen können sofort starten
  $hash->{HELPER}{OLDVALPOLLNOLOGGING} = "0";                                    # Loggingfunktion für Polling ist an
  $hash->{HELPER}{OLDVALPOLL}          = "0";  
  $hash->{HELPER}{RECTIME_DEF}         = "15";                                   # Standard für rectime setzen, überschreibbar durch Attribut "rectime" bzw. beim "set .. on-for-time"
  $hash->{HELPER}{OLDPTZHOME}          = "";
  $hash->{".ptzhtml"}                  = "";                                     # initial -> es wird ptzpanel neu eingelesen
  $hash->{HELPER}{HLSSTREAM}           = "inactive";                             # Aktivitätsstatus HLS-Streaming
  $hash->{HELPER}{SNAPLIMIT}           = 0;                                      # abgerufene Anzahl Snaps
  $hash->{HELPER}{TOTALCNT}            = 0;                                      # totale Anzahl Snaps
  
  my $params = {
      hash        => $hash,
      notes       => \%vNotesIntern,
      useAPI      => 1,
      useSMUtils  => 1,
      useErrCodes => 1
  };
  use version 0.77; our $VERSION = moduleVersion ($params);                      # Versionsinformationen setzen
  
  readingsBeginUpdate ($hash );
  readingsBulkUpdate  ($hash, "PollState", "Inactive");                          # es ist keine Gerätepolling aktiv  
  
  if(IsModelCam($hash)) {
      readingsBulkUpdate ($hash, "Availability", "???");                         # Verfügbarkeit ist unbekannt
      readingsBulkUpdate ($hash, "state",        "off");                         # Init für "state" , Problemlösung für setstate, Forum #308
  } 
  else {
      readingsBulkUpdate ($hash, "state", "Initialized");                        # Init für "state" wenn SVS  
  }
  
  readingsEndUpdate ($hash,1);                                          
  
  getCredentials ($hash,1, "credentials" );                                      # Credentials lesen und in RAM laden ($boot=1)      
  getCredentials ($hash,1, "SMTPcredentials");
  
  # initiale Routinen zufällig verzögert nach Restart ausführen
  RemoveInternalTimer ($hash,                        "FHEM::SSCam::initOnBoot"          );
  InternalTimer       (gettimeofday()+int(rand(30)), "FHEM::SSCam::initOnBoot", $hash, 0);

return;
}

################################################################
# Die Undef-Funktion wird aufgerufen wenn ein Gerät mit delete 
# gelöscht wird oder bei der Abarbeitung des Befehls rereadcfg, 
# der ebenfalls alle Geräte löscht und danach das 
# Konfigurationsfile neu einliest. 
# Funktion: typische Aufräumarbeiten wie das 
# saubere Schließen von Verbindungen oder das Entfernen von 
# internen Timern, sofern diese im Modul zum Pollen verwendet 
# wurden.
################################################################
sub Undef {
  my $hash = shift;
  my $arg  = shift;
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash);
   
return;
}

#######################################################################################################
# Mit der X_DelayedShutdown Funktion kann eine Definition das Stoppen von FHEM verzögern um asynchron 
# hinter sich aufzuräumen.  
# Je nach Rückgabewert $delay_needed wird der Stopp von FHEM verzögert (0|1).
# Sobald alle nötigen Maßnahmen erledigt sind, muss der Abschluss mit CancelDelayedShutdown($name) an 
# FHEM zurückgemeldet werden. 
#######################################################################################################
sub delayedShutdown {
  my $hash = shift;
  my $name = $hash->{NAME};
  
  $shutdownInProcess = 1;                                       # Statusbit shutdown setzen -> asynchrone Funktionen nicht mehr ausgeführen
  
  Log3($name, 2, "$name - Quit session due to shutdown ...");

  __sessionOff($hash);
  
  if($hash->{HELPER}{CACHEKEY}) {
      cache($name, "c_destroy"); 
  }

return 1;
}

#################################################################
# Wenn ein Gerät in FHEM gelöscht wird, wird zuerst die Funktion 
# X_Undef aufgerufen um offene Verbindungen zu schließen, 
# anschließend wird die Funktion X_Delete aufgerufen. 
# Funktion: Aufräumen von dauerhaften Daten, welche durch das 
# Modul evtl. für dieses Gerät spezifisch erstellt worden sind. 
# Es geht hier also eher darum, alle Spuren sowohl im laufenden 
# FHEM-Prozess, als auch dauerhafte Daten bspw. im physikalischen 
# Gerät zu löschen die mit dieser Gerätedefinition zu tun haben. 
#################################################################
sub Delete {
    my $hash  = shift;
    my $arg   = shift;
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_credentials";
    my $name  = $hash->{NAME};
    
    setKeyValue ($index, undef);                                       # gespeicherte Credentials löschen

    my $sgdev = "SSCam.$hash->{NAME}.snapgallery";                     # löschen snapGallerie-Device falls vorhanden
    CommandDelete($hash->{CL},"$sgdev");
    
    CommandDelete($hash->{CL},"TYPE=SSCamSTRM:FILTER=PARENT=$name");   # alle zugeordneten Streaming-Devices löschen falls vorhanden
    
    delete $data{SSCam}{$name};                                        # internen Cache löschen
    
return;
}

######################################################################################
#                         Kamera Liveview Anzeige in FHEMWEB
######################################################################################
# wird von FW aufgerufen. $FW_wname = aufrufende Webinstanz, $d = aufrufendes 
# Device (z.B. CamCP1)
sub FWsummaryFn {
  my ($FW_wname, $d, $room, $pageHash) = @_;   # pageHash is set for summaryFn in FHEMWEB
  my $hash   = $defs{$d};
  my $name   = $hash->{NAME};
  my $link   = $hash->{HELPER}{LINK};
  my $wltype = $hash->{HELPER}{WLTYPE};
  my $ret    = "";
  my $alias;
    
  return if(!$hash->{HELPER}{LINK} || ReadingsVal($d, "state", "") =~ /^dis/x || IsDisabled($name));
  
  # Definition Tasten
  my $imgblank      = "<img src=\"$FW_ME/www/images/sscam/black_btn_CAMBLANK.png\">";             # nicht sichtbare Leertaste
  my $cmdstop       = "cmd=set $d stopView";                                                      # Stream deaktivieren
  my $imgstop       = "<img src=\"$FW_ME/www/images/default/remotecontrol/black_btn_POWEROFF3.png\">";
  my $cmdhlsreact   = "cmd=set $d hlsreactivate";                                                 # HLS Stream reaktivieren
  my $imghlsreact   = "<img src=\"$FW_ME/www/images/default/remotecontrol/black_btn_BACKDroid.png\">";
  my $cmdmjpegrun   = "cmd=set $d runView live_fw";                                               # MJPEG Stream aktivieren  
  my $imgmjpegrun   = "<img src=\"$FW_ME/www/images/sscam/black_btn_MJPEG.png\">";
  my $cmdhlsrun     = "cmd=set $d runView live_fw_hls";                                           # HLS Stream aktivieren  
  my $imghlsrun     = "<img src=\"$FW_ME/www/images/sscam/black_btn_HLS.png\">";
  my $cmdlrirun     = "cmd=set $d runView lastrec_fw";                                            # Last Record IFrame  
  my $imglrirun     = "<img src=\"$FW_ME/www/images/sscam/black_btn_LASTRECIFRAME.png\">";
  my $cmdlh264run   = "cmd=set $d runView lastrec_fw_MPEG4/H.264";                                # Last Record H.264  
  my $imglh264run   = "<img src=\"$FW_ME/www/images/sscam/black_btn_LRECH264.png\">";
  my $cmdlmjpegrun  = "cmd=set $d runView lastrec_fw_MJPEG";                                      # Last Record MJPEG  
  my $imglmjpegrun  = "<img src=\"$FW_ME/www/images/sscam/black_btn_LRECMJPEG.png\">";
  my $cmdlsnaprun   = "cmd=set $d runView lastsnap_fw STRM";                                      # Last SNAP  
  my $imglsnaprun   = "<img src=\"$FW_ME/www/images/sscam/black_btn_LSNAP.png\">";
  my $cmdrecendless = "cmd=set $d on 0";                                                          # Endlosaufnahme Start  
  my $imgrecendless = "<img src=\"$FW_ME/www/images/sscam/black_btn_RECSTART.png\">";
  my $cmdrecstop    = "cmd=set $d off";                                                           # Aufnahme Stop  
  my $imgrecstop    = "<img src=\"$FW_ME/www/images/sscam/black_btn_RECSTOP.png\">";
  my $cmddosnap     = "cmd=set $d snap 1 2 STRM";                                                 # Snapshot auslösen mit Kennzeichnung "by STRM-Device"
  my $imgdosnap     = "<img src=\"$FW_ME/www/images/sscam/black_btn_DOSNAP.png\">";
 
  my $attr = AttrVal($d, "htmlattr", " ");
  Log3($name, 4, "$name - FWsummaryFn called - FW_wname: $FW_wname, device: $d, room: $room, attributes: $attr");
  
  my $calias = $hash->{CAMNAME};                                            # Alias der Kamera

  my ($ttrefresh, $ttrecstart, $ttrecstop, $ttsnap, $ttcmdstop, $tthlsreact, $ttmjpegrun, $tthlsrun, $ttlrrun, $tth264run, $ttlmjpegrun, $ttlsnaprun);
  if(AttrVal("global","language","EN") =~ /EN/x) {
      $ttrecstart = $ttips_en{"ttrecstart"}; $ttrecstart =~ s/§NAME§/$calias/gx;
      $ttrecstop  = $ttips_en{"ttrecstop"};  $ttrecstop  =~ s/§NAME§/$calias/gx;
      $ttsnap     = $ttips_en{"ttsnap"};     $ttsnap     =~ s/§NAME§/$calias/gx;
      $ttcmdstop  = $ttips_en{"ttcmdstop"};  $ttcmdstop  =~ s/§NAME§/$calias/gx;
      $tthlsreact = $ttips_en{"tthlsreact"}; $tthlsreact =~ s/§NAME§/$calias/gx;
  } 
  else {
      $ttrecstart = $ttips_de{"ttrecstart"}; $ttrecstart =~ s/§NAME§/$calias/gx;
      $ttrecstop  = $ttips_de{"ttrecstop"};  $ttrecstop  =~ s/§NAME§/$calias/gx;
      $ttsnap     = $ttips_de{"ttsnap"};     $ttsnap     =~ s/§NAME§/$calias/gx;
      $ttcmdstop  = $ttips_de{"ttcmdstop"};  $ttcmdstop  =~ s/§NAME§/$calias/gx;
      $tthlsreact = $ttips_de{"tthlsreact"}; $tthlsreact =~ s/§NAME§/$calias/gx;
  }
  
  if($wltype eq "image") {
    if(ReadingsVal($name, "SVSversion", "") eq "8.2.3-5828" && ReadingsVal($name, "CamVideoType", "") !~ /MJPEG/x) {             
      $ret .= "<td> <br> <b> Because SVS version 8.2.3-5828 is running you cannot see the MJPEG-Stream. Please upgrade to a higher SVS version ! </b> <br><br>";
    } 
    else {
      $ret .= "<img src=$link $attr><br>";
    }
    
    $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdstop')\" title=\"$ttcmdstop\")\">$imgstop </a>";
    $ret .= $imgblank; 
    
    if($hash->{HELPER}{RUNVIEW} =~ /live_fw/x) {
      if(ReadingsVal($d, "Record", "Stop") eq "Stop") {
        # Aufnahmebutton endlos Start
        $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdrecendless')\" title=\"$ttrecstart\">$imgrecendless </a>";
      } 
      else {
        # Aufnahmebutton Stop
        $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdrecstop')\" title=\"$ttrecstop\">$imgrecstop </a>";
      }       
    $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmddosnap')\" title=\"$ttsnap\">$imgdosnap </a>"; 
    }
    
    $ret .= "<br>";
    
    if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($d, "CamAudioType", "Unknown") !~ /Unknown/x) {
        $ret .= "<audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>".
                "Your browser does not support the audio element.".
                "</audio>";
    }  
  } 
  elsif($wltype eq "iframe") {
    $ret .= "<iframe src=$link $attr controls autoplay>".
            "Iframes disabled".
            "</iframe>";
    $ret .= "<br>";
    $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdstop')\" title=\"$ttcmdstop\">$imgstop </a>";
    if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($d, "CamAudioType", "Unknown") !~ /Unknown/x) {
        $ret .= "<audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>".
                "Your browser does not support the audio element.".      
                "</audio>";
    }         
  } 
  elsif($wltype eq "embed") {
    $ret .= "<embed src=$link $attr>";
    if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($d, "CamAudioType", "Unknown") !~ /Unknown/x) {
        $ret .= "<audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>".
                "Your browser does not support the audio element.".      
                "</audio>";
    }  
  } 
  elsif($wltype eq "link") {
    $alias = $hash->{HELPER}{ALIAS};
    $ret .= "<a href=$link $attr>$alias</a><br>";     
  } 
  elsif($wltype eq "base64img") {
    $alias = $hash->{HELPER}{ALIAS};
    $ret .= "<img $attr alt='$alias' src='data:image/jpeg;base64,$link'><br>";
    $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdstop')\" title=\"$ttcmdstop\">$imgstop </a>";
    $ret .= $imgblank;
    $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmddosnap')\" title=\"$ttsnap\">$imgdosnap </a>"; 
  } 
  elsif($wltype eq "hls") {
    $alias = $hash->{HELPER}{ALIAS};
    $ret  .= "<video $attr controls autoplay>".
             "<source src=$link type=\"application/x-mpegURL\">".
             "<source src=$link type=\"video/MP2T\">".
             "Your browser does not support the video tag".
             "</video>";
    $ret .= "<br>";
    $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdstop')\" title=\"$ttcmdstop\">$imgstop </a>";
    $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdhlsreact')\" title=\"$tthlsreact\">$imghlsreact </a>";
    $ret .= $imgblank;
    if(ReadingsVal($d, "Record", "Stop") eq "Stop") {                # Aufnahmebutton endlos Start
        $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdrecendless')\" title=\"$ttrecstart\">$imgrecendless </a>";
    } 
    else {                                                           # Aufnahmebutton Stop
        $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdrecstop')\" title=\"$ttrecstop\">$imgrecstop </a>";
    }       
    $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmddosnap')\" title=\"$ttsnap\">$imgdosnap </a>";                 
  
  } 
  elsif($wltype eq "video") {
    $ret .= "<video $attr controls autoplay>".
            "<source src=$link type=\"video/mp4\">".
            "<source src=$link type=\"video/ogg\">".
            "<source src=$link type=\"video/webm\">".
            "Your browser does not support the video tag.".
            "</video>"; 
    $ret .= "<br>";
    $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdstop')\" title=\"$ttcmdstop\">$imgstop </a>";
    $ret .= "<br>";
    if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($d, "CamAudioType", "Unknown") !~ /Unknown/x) {
        $ret .= "<audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>".
                "Your browser does not support the audio element.".    
                "</audio>";
    }             
  } 

return $ret;
}

######################################################################################
#                       Detailanzeige
######################################################################################
sub FWdetailFn {
  my ($FW_wname, $name, $room, $pageHash) = @_;           # pageHash is set for summaryFn.
  my $hash = $defs{$name};
  
  my $ret = "";
  
  checkIconpath ($name, $FW_wname);
  
  $hash->{".setup"} = FWconfCam($name,$room);
  if($hash->{".setup"} ne "") {
      $ret .= $hash->{".setup"};
  }
  
  my %pars = ( 
      linkparent => $name,
      linkname   => $name,
      ftui       => 0
  );
             
  $hash->{".ptzhtml"} = ptzPanel(\%pars) if($hash->{".ptzhtml"} eq "");

  if($hash->{".ptzhtml"} ne "" && AttrVal($name,"ptzPanel_use",1)) {
      $ret .= $hash->{".ptzhtml"};
  } 

return $ret;
}

###############################################################################
#                        Aufruf Konfigseite Kamera
###############################################################################
sub FWconfCam {
  my ($name,$room) = @_; 
  my $hash    = $defs{$name};
  my $cip     = ReadingsVal("$name","CamIP","");
  my $svsip   = $hash->{SERVERADDR};
  my $svsport = $hash->{SERVERPORT};
  my $svsprot = $hash->{PROTOCOL};
  my $attr    = AttrVal($name, "htmlattr", "");
  my $alias   = AttrVal($name, "alias", $name);    
  my $winname = $name."_view";
  my $cicon   = 'edit_settings.svg';                                    # Icon für Cam/SVS Setup-Screen
  my $hicon   = 'info_info.svg';                                        # Icon für SVS Hilfeseite
  my $w       = 150;
  my ($ret,$cexpl,$hexpl) = ("","","");
  my ($cs,$bs,$ch,$bh,);
  
  if(IsModelCam($hash)) {                                         # Camera Device
      return $ret if(!$cip);
      if(AttrVal("global","language","EN") =~ /DE/x) {
          $cexpl = $ttips_de{confcam}; $cexpl =~ s/§NAME§/$alias/gx;
      } 
      else {
          $cexpl = $ttips_en{confcam}; $cexpl =~ s/§NAME§/$alias/gx;
      }
      $cs = "window.open('http://$cip')";
  
  } 
  else {                                                              # SVS-Device
      return $ret if(!$svsip);
      if(AttrVal("global","language","EN") =~ /DE/x) {
          $cexpl = $ttips_de{confsvs}; $cexpl =~ s/§NAME§/$alias/gx;
      } 
      else {
          $cexpl = $ttips_en{confsvs}; $cexpl =~ s/§NAME§/$alias/gx;
      }    
      $cs = "window.open('$svsprot://$svsip:$svsport/cam')";      
  }
  
  if(AttrVal("global","language","EN") =~ /DE/x) {
      $hexpl = $ttips_de{"helpsvs"}; $hexpl =~ s/\s/&nbsp;/gx; 
      $ch    = "window.open('https://www.synology.com/de-de/knowledgebase/Surveillance/help')"; 
  } 
  else {
      $hexpl = $ttips_en{"helpsvs"}; $hexpl =~ s/\s/&nbsp;/gx; 
      $ch    = "window.open('https://www.synology.com/en-global/knowledgebase/Surveillance/help')"; 
  }   
  
  $cicon = FW_makeImage($cicon); $hicon = FW_makeImage($hicon);
  
  $ret .= "<style>TD.confcam {text-align: center; padding-left:1px; padding-right:1px; margin:0px;}</style>";
  $ret .= "<table class='roomoverview' width='$w' style='width:".$w."px'>";
  $ret .= '<tbody>';  
  $ret .= "<td>"; 
  
  $ret .= "<a onClick=$cs title=\"$cexpl\"> $cicon </a>";  
  
  $ret .= "</td><td>";  
  
  $ret .= "<a onClick=$ch title=\"$hexpl\"> $hicon </a>";  
 
  $ret .= "</td>";
  $ret .= "</tr>";
  $ret .= '</tbody>';
  $ret .= "</table>";  
  $ret .= "<br>";
  
return $ret;
}

################################################################
#                            Attr
################################################################
sub Attr {
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash                     = $defs{$name};
    
    my ($do,$val,$cache);
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    
    if ($aName eq "session") {
        delete $hash->{HELPER}{SID};
    }
    
    if ($aName =~ /hlsNetScript/x && IsModelCam($hash)) {            
        return " The attribute \"$aName\" is only valid for devices of type \"SVS\"! Please set this attribute in a device of this type.";
    }
    
    if ($aName =~ /snapReadingRotate/x && !IsModelCam($hash)) {            
        return " The attribute \"$aName\" is not valid for devices of type \"SVS\"!.";
    }
    
    # dynamisch PTZ-Attribute setzen (wichtig beim Start wenn Reading "DeviceType" nicht gesetzt ist)
    if ($cmd eq "set" && ($aName =~ m/ptzPanel_/x)) {
        for my $n (0..9) { 
            $n = sprintf("%2.2d",$n);
            addToDevAttrList($name, "ptzPanel_row$n");
        }
        addToDevAttrList($name, "ptzPanel_iconPrefix");
        addToDevAttrList($name, "ptzPanel_iconPath");
    }
    
    if($aName =~ m/ptzPanel_row|ptzPanel_Home|ptzPanel_use/x) {
        InternalTimer(gettimeofday()+0.7, "FHEM::SSCam::addptzattr", "$name", 0);
    } 
       
    if ($aName eq "disable") {
        my $iscam = IsModelCam($hash); 
        if($cmd eq "set") {
            $do = $aVal ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        
        if ($do == 1) {
            RemoveInternalTimer($hash);
        } 
        else {
            InternalTimer(gettimeofday()+int(rand(30)), "FHEM::SSCam::initOnBoot", $hash, 0);
        }
    
        readingsSingleUpdate($hash, "state",        $imc{$iscam}{$do}, 1);
        readingsSingleUpdate($hash, "PollState",    "Inactive",        1) if($do == 1);
        readingsSingleUpdate($hash, "Availability", "???",             1) if($do == 1 && IsModelCam($hash));
    }
    
    if($aName =~ m/cacheType/) {
        my $type = AttrVal($name,"cacheType","internal");
        if($cmd eq "set") {
            if($aVal ne "internal") {
                if($SScamMMCHI) {
                    return "Perl cache module ".$SScamMMCHI." is missing. You need to install it with the FHEM Installer for example.";
                }
                if($aVal eq "redis") {
                    if($SScamMMCHIRedis) {
                        return "Perl cache module ".$SScamMMCHIRedis." is missing. You need to install it with the FHEM Installer for example.";
                    }
                    if(!AttrVal($name,"cacheServerParam","")) {
                        return "For cacheType \"$aVal\" you must set first attribute \"cacheServerParam\" for Redis server connection: <Redis-server address>:<Redis-server port>";
                    }
                }   
                if($aVal eq "file") {
                    if($SScamMMCacheCache) {
                        return "Perl cache module ".$SScamMMCacheCache." is missing. You need to install it with the FHEM Installer for example.";
                    }
                }                 
            }
            if ($aVal ne $type) {
                if($hash->{HELPER}{CACHEKEY}) {
                    cache($name, "c_destroy");                                                 # CHI-Cache löschen/entfernen    
                } 
                else {
                    delete $data{SSCam}{$name};                                                # internen Cache löschen
                }              
            }        
        } 
        else {
            if($hash->{HELPER}{CACHEKEY}) {
                cache($name, "c_destroy");                                                     # CHI-Cache löschen/entfernen    
            }        
        }        
    } 
    
    if ($aName eq "showStmInfoFull") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");

        if ($do == 0) {
            delete($defs{$name}{READINGS}{StmKeymjpegHttp});
            delete($defs{$name}{READINGS}{LiveStreamUrl}); 
            delete($defs{$name}{READINGS}{StmKeyUnicst});            
            delete($defs{$name}{READINGS}{StmKeyUnicstOverHttp});
            delete($defs{$name}{READINGS}{StmKeymxpegHttp});            
        }
    }

    if ($aName eq "snapGallerySize") {
        if($cmd eq "set") {
            $do = ($aVal eq "Icon")?1:2;
        }
        $do = 0 if($cmd eq "del");                  

        if ($do == 0) {
            delete($hash->{HELPER}{".SNAPHASH"}) if(AttrVal($name,"snapGalleryBoost",0));     # Snaphash nur löschen wenn Snaps gepollt werden   
            Log3($name, 4, "$name - Snapshot hash deleted");
        
        } 
        elsif (AttrVal($name,"snapGalleryBoost",0) && $init_done == 1) {                      # snap-Infos abhängig ermitteln wenn gepollt werden soll
            $hash->{HELPER}{GETSNAPGALLERY} = 1;   
            my $slim                        = AttrVal($name,"snapGalleryNumber",$defSlim);    # Anzahl der abzurufenden Snaps
            my $ssize                       = $do;
            
            RemoveInternalTimer($hash,              "FHEM::SSCam::__getSnapInfo" ); 
            InternalTimer      (gettimeofday()+0.7, "FHEM::SSCam::__getSnapInfo", "$name:$slim:$ssize", 0);
        }
    }     
    
    if ($aName eq "snapGalleryBoost") {
        if($cmd eq "set") {
            $do = ($aVal == 1) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");

        if($do == 0) {
            delete($hash->{HELPER}{".SNAPHASH"});  # Snaphash löschen
            Log3($name, 4, "$name - Snapshot hash deleted");
        
        } 
        elsif ($init_done == 1) {                                                            # snapgallery regelmäßig neu einlesen wenn Polling ein
            return qq{When you want activate "snapGalleryBoost", you have to set the attribute "pollcaminfoall" first because of the functionality depends on retrieving snapshots periodical.} 
               if(!AttrVal($name,"pollcaminfoall",0));
               
            $hash->{HELPER}{GETSNAPGALLERY} = 1;
            my $slim  = AttrVal($name, "snapGalleryNumber", $defSlim);                       # Anzahl der abzurufenden Snaps
            my $sg    = AttrVal($name, "snapGallerySize",   "Icon"  );                       # Auflösung Image
            my $ssize = ($sg eq "Icon") ? 1 : 2;
            
            RemoveInternalTimer ($hash,              "FHEM::SSCam::__getSnapInfo" ); 
            InternalTimer       (gettimeofday()+0.7, "FHEM::SSCam::__getSnapInfo", "$name:$slim:$ssize", 0);
        }
    } 
    
    if ($aName eq "snapGalleryNumber" && AttrVal($name,"snapGalleryBoost",0)) {
        my ($slim,$ssize);    
        if($cmd eq "set") {
            $do = ($aVal != 0) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        
        if ($do == 0) { 
            $slim = 3;
        } 
        else {
            $slim = $aVal;
        }
        
        if($init_done == 1) {
            delete($hash->{HELPER}{".SNAPHASH"});                                               # bestehenden Snaphash löschen
            $hash->{HELPER}{GETSNAPGALLERY} = 1;
            my $sg                          = AttrVal($name,"snapGallerySize","Icon");          # Auflösung Image
            $ssize                          = $sg eq "Icon" ? 1 : 2;
            
            RemoveInternalTimer ($hash,              "FHEM::SSCam::__getSnapInfo" ); 
            InternalTimer       (gettimeofday()+0.7, "FHEM::SSCam::__getSnapInfo", "$name:$slim:$ssize", 0);
        }
    }
    
    if ($aName eq "snapReadingRotate") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        if(!$do) {$aVal = 0}
        for my $i (1..10) { 
            if($i>$aVal) {
                readingsDelete($hash, "LastSnapFilename$i" );
                readingsDelete($hash, "LastSnapId$i"       );
                readingsDelete($hash, "LastSnapTime$i"     );  
            }
        }
    }
    
    if ($aName eq "simu_SVSversion") {
        delete $hash->{HELPER}{API}{PARSET};
        delete $hash->{HELPER}{SID};
        delete $hash->{CAMID};
        RemoveInternalTimer ($hash,              "FHEM::SSCam::__getCaminfoAll" );
        InternalTimer       (gettimeofday()+0.5, "FHEM::SSCam::__getCaminfoAll", $hash, 0);
    }
    
    if($aName =~ m/pollcaminfoall/ && $init_done == 1) {
        RemoveInternalTimer ($hash,              "FHEM::SSCam::__getCaminfoAll"          );
        InternalTimer       (gettimeofday()+1.0, "FHEM::SSCam::__getCaminfoAll", $hash, 0);
        RemoveInternalTimer ($hash,              "FHEM::SSCam::wdpollcaminfo"            );
        InternalTimer       (gettimeofday()+1.5, "FHEM::SSCam::wdpollcaminfo",   $hash, 0);
    }
    
    if($aName =~ m/pollnologging/ && $init_done == 1) {
        RemoveInternalTimer ($hash,              "FHEM::SSCam::wdpollcaminfo"          );
        InternalTimer       (gettimeofday()+1.0, "FHEM::SSCam::wdpollcaminfo", $hash, 0);
    } 
                         
    if ($cmd eq "set") {
        if ($aName =~ m/httptimeout|snapGalleryColumns|rectime|pollcaminfoall/x) {
            unless ($aVal =~ /^\d+$/x) { return " The Value for $aName is not valid. Use only figures 1-9 !";}
        }
        if($aName =~ m/pollcaminfoall/x) {
            return "The value of \"$aName\" has to be greater than 10 seconds." if($aVal <= 10);
        }
        if($aName =~ m/cacheServerParam/x) {
            return "Please provide the Redis server parameters in form: <Redis-server address>:<Redis-server port> or unix:</path/to/sock>" if($aVal !~ /:\d+$|unix:.+$/x);
            my $type = AttrVal($name, "cacheType", "internal");
            if($hash->{HELPER}{CACHEKEY} && $type eq "redis") {
                cache($name, "c_destroy");
            }
        }
        if($aName =~ m/snapChatTxt|recChatTxt/x) {
            return "When you want activate \"$aName\", you have to set first the attribute \"videofolderMap\" to the root folder ".
                   "of recordings and snapshots provided by an URL.\n".
                   "Example: http://server.domain:8081/surveillance "                   
                   if(!AttrVal($name, "videofolderMap", "") && $init_done == 1);

        }  
    }

    if ($cmd eq "del") {
        if ($aName =~ m/pollcaminfoall/x) {
            # Polling nicht ausschalten wenn snapGalleryBoost ein (regelmäßig neu einlesen)
            return "Please switch off \"snapGalleryBoost\" first if you want to deactivate \"pollcaminfoall\" because the functionality of \"snapGalleryBoost\" depends on retrieving snapshots periodical." 
                   if(AttrVal($name,"snapGalleryBoost",0));
        }       
    }

return;
}

################################################################
#                         Set
################################################################
sub Set {
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name    = $a[0];
  my $opt     = $a[1];
  my $prop    = $a[2];
  my $prop1   = $a[3];
  my $prop2   = $a[4];
  my $prop3   = $a[5]; 
  my $success;
  my $setlist;
        
  return if(IsDisabled($name));
 
  if(!$hash->{CREDENTIALS}) {
      # initiale setlist für neue Devices
      $setlist = "Unknown argument $opt, choose one of ".
                 "credentials "
                 ;  
  } elsif(IsModelCam($hash)) {
      # selist für Cams
      my $hlslfw = IsCapHLS($hash) ? ",live_fw_hls," : ",";
      $setlist   = "Unknown argument $opt, choose one of ".
                   "credentials ".
                   "smtpcredentials ".
                   "expmode:auto,day,night ".
                   "on ".
                   "off:noArg ".
                   "motdetsc:disable,camera,SVS ".
                   "snap ".
                   (AttrVal($name, "snapGalleryBoost",0) ? (AttrVal($name,"snapGalleryNumber",undef) || AttrVal($name,"snapGalleryBoost",0)) ? "snapGallery:noArg " : "snapGallery:$defSnum " : " ").
                   "createReadingsGroup ".
                   "createSnapGallery:noArg ".
                   "createStreamDev:generic,hls,lastsnap,mjpeg,switched ".
                   "enable:noArg ".
                   "disable:noArg ".
                   "optimizeParams ".
                   "runView:live_fw".$hlslfw."live_link,live_open,lastrec_fw,lastrec_fw_MJPEG,lastrec_fw_MPEG4/H.264,lastrec_open,lastsnap_fw ".
                   "stopView:noArg ".
                   (IsCapPTZObjTrack($hash) ? "startTracking:noArg " : "").
                   (IsCapPTZObjTrack($hash) ? "stopTracking:noArg " : "").
                   (IsCapPTZPan($hash)      ? "setPreset ": "").
                   (IsCapPTZPan($hash)      ? "setHome:---currentPosition---,".ReadingsVal("$name","Presets","")." " : "").
                   (IsCapPTZPan($hash)      ? "delPreset:".ReadingsVal("$name","Presets","")." " : "").
                   (IsCapPTZPan($hash)      ? "runPatrol:".ReadingsVal("$name", "Patrols", "")." " : "").
                   (IsCapPTZPan($hash)      ? "goPreset:".ReadingsVal("$name", "Presets", "")." " : "").
                   (IsCapPTZ($hash)         ? "createPTZcontrol:noArg " : "").
                   (IsCapPTZAbs($hash)      ? "goAbsPTZ"." " : ""). 
                   (IsCapPTZDir($hash)      ? "move"." " : "").
                   (IsCapPIR($hash)         ? "pirSensor:activate,deactivate " : "").
                   (IsCapZoom($hash)        ? "setZoom:$valZoom " : "").
                   "";
  } 
  else {
      # setlist für SVS Devices
      $setlist = "Unknown argument $opt, choose one of ".
                 "autocreateCams:noArg ".
                 "credentials ".
                 "createStreamDev:master ".
                 "smtpcredentials ".
                 "createReadingsGroup ".
                 "extevent:1,2,3,4,5,6,7,8,9,10 ".
                 ($hash->{HELPER}{API}{HMODE}{VER} ? "homeMode:on,off " : "").
                 "snapCams ";
  }

  my $params = {
      hash  => $hash,
      name  => $name,
      opt   => $opt,
      prop  => $prop,
      prop1 => $prop1,
      prop2 => $prop2,
      prop3 => $prop3,
      aref  => \@a,
  };
  
  no strict "refs";                                                        ## no critic 'NoStrict'  
  if($hset{$opt} && defined &{$hset{$opt}{fn}}) {
      my $ret = q{};
      
      if (!$hash->{CREDENTIALS} && $hset{$opt}{needcred}) {                
          return qq{Credentials of $name are not set. Make sure they are set with "set $name credentials <username> <password>"};
      }
  
      $ret = &{$hset{$opt}{fn}} ($params);
      
      return $ret;
  }
  use strict "refs";  
  
return $setlist;
}

################################################################
#                      Setter credentials
################################################################
sub _setcredentials {                    ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $prop  = $paref->{prop};
  my $prop1 = $paref->{prop1};
  
  return "Credentials are incomplete, use username password" if(!$prop || !$prop1);
  return "Password is too long. It is limited up to and including 20 characters." if(length $prop1 > 20);
  
  delete $hash->{HELPER}{SID};  
  
  my ($success) = setCredentials($hash,"credentials",$prop,$prop1);
  
  $hash->{HELPER}{ACTIVE} = "off";  
  
  if($success) {
      __getCaminfoAll($hash,0);
      versionCheck   ($hash);
      return "Username and Password saved successfully";
  } 
  else {
      return "Error while saving Username / Password - see logfile for details";
  }

return;
}

################################################################
#                      Setter smtpcredentials
################################################################
sub _setsmtpcredentials {                ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $prop  = $paref->{prop};
  my $prop1 = $paref->{prop1};
  
  return "Credentials are incomplete, use username password" if (!$prop || !$prop1);        
  my ($success) = setCredentials($hash,"SMTPcredentials",$prop,$prop1);
  
  if($success) {
      return "SMTP-Username and SMTP-Password saved successfully";
  } 
  else {
      return "Error while saving SMTP-Username / SMTP-Password - see logfile for details";
  }  

return;
}

################################################################
#                      Setter on
################################################################
sub _seton {                             ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop};
  my $aref  = $paref->{aref};
  
  return if(!IsModelCam($hash));
  
  if (defined($prop) && $prop =~ /^\d+$/x) {
      $hash->{HELPER}{RECTIME_TEMP} = $prop;
  }
  
  my $spec = join(" ",@$aref);

  my ($inf)               = $spec =~ m/STRM:(.*)/ix;         # Aufnahme durch SSCamSTRM-Device
  $hash->{HELPER}{INFORM} = $inf if($inf);
  
  my $emtxt = AttrVal($name, "recEmailTxt", "");
  if($spec =~ /recEmailTxt:/x) {
      ($emtxt) = $spec =~ m/recEmailTxt:"(.*)"/xi;
  }
  
  if($emtxt) {                                               # Recording soll per Email versendet werden, recEmailTxt muss sein:  subject => <Subject-Text>, body => <Body-Text>
      if (!$hash->{SMTPCREDENTIALS}) {return "Due to \"recEmailTxt\" is set, you want to send recordings by email but SMTP credentials are not set - make sure you've set credentials with \"set $name smtpcredentials username password\"";}
      $hash->{HELPER}{SMTPRECMSG} = $emtxt;
  }
  
  my $teletxt = AttrVal($name, "recTelegramTxt", "");
  if($spec =~ /recTelegramTxt:/x) {
      ($teletxt) = $spec =~ m/recTelegramTxt:"(.*)"/xi;
  }
  
  if ($teletxt) {                                            # Recording soll per Telegram versendet werden, Format teletxt muss sein: recTelegramTxt:"tbot => <teleBot Device>, peers => <peer1 peer2 ..>, subject => <Beschreibungstext>"
      $hash->{HELPER}{TELERECMSG} = $teletxt;
  }
  
  my $chattxt = AttrVal($name, "recChatTxt", "");
  if($spec =~ /recChatTxt:/x) {
      ($chattxt) = $spec =~ m/recChatTxt:"(.*)"/xi;
  }
  
  if ($chattxt) {                                           # Recording soll per SSChatBot versendet werden, Format $chattxt muss sein: recChatTxt:"chatbot => <SSChatBot Device>, peers => <peer1 peer2 ..>, subject => <Beschreibungstext>"
      $hash->{HELPER}{CHATRECMSG} = $chattxt;
  }

  __camStartRec("$name!_!$emtxt!_!$teletxt!_!$chattxt");

return;
}

################################################################
#                      Setter off
################################################################
sub _setoff {                            ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $aref  = $paref->{aref};
  
  return if(!IsModelCam($hash));
  
  my $spec = join(" ",@$aref);
  
  my ($inf)               = $spec =~ m/STRM:(.*)/ix;         # Aufnahmestop durch SSCamSTRM-Device
  $hash->{HELPER}{INFORM} = $inf if($inf);
      
  __camStopRec($hash);

return;
}

################################################################
#                      Setter snap
################################################################
sub _setsnap {                           ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop}  // q{};
  my $prop1 = $paref->{prop1} // q{};
  my $aref  = $paref->{aref};
  
  return if(!IsModelCam($hash));
        
  my ($num,$lag,$ncount) = (1,2,1);  
  
  if($prop =~ /^\d+$/x) {                                           # Anzahl der Schnappschüsse zu triggern (default: 1)
      $num    = $prop;
      $ncount = $prop;
  }
  
  if($prop1 =~ /^\d+$/x) {                                          # Zeit zwischen zwei Schnappschüssen (default: 2 Sekunden)
      $lag = $prop1;
  }
  
  Log3($name, 4, "$name - Trigger snapshots - Number: $num, Lag: $lag");   
  
  my $spec = join " ",@$aref;
  if($spec =~ /STRM:/x) {
      ($hash->{HELPER}{INFORM}) = $spec =~ m/STRM:(.*)/xi;          # Snap by SSCamSTRM-Device
  } 
   
  my $emtxt = AttrVal($name, "snapEmailTxt", "");
  if($spec =~ /snapEmailTxt:/x) {
      ($emtxt) = $spec =~ m/snapEmailTxt:"(.*)"/xi;
  }
  
  if ($emtxt) {                                                     # Snap soll per Email versendet werden, Format $emtxt muss sein: snapEmailTxt:"subject => <Subject-Text>, body => <Body-Text>"
      if (!$hash->{SMTPCREDENTIALS}) {
          return "It seems you want to send snapshots by email but SMTP credentials are not set. Make sure set credentials with \"set $name smtpcredentials username password\"";
      }
      $hash->{HELPER}{SMTPMSG} = $emtxt;
  }
  
  my $teletxt = AttrVal($name, "snapTelegramTxt", "");
  if($spec =~ /snapTelegramTxt:/x) {
      ($teletxt) = $spec =~ m/snapTelegramTxt:"(.*)"/xi;
  }
  
  if ($teletxt) {                                                   # Snap soll per TelegramBot versendet werden, Format $teletxt muss sein: snapTelegramTxt:"tbot => <teleBot Device>, peers => <peer1 peer2 ..>, subject => <Beschreibungstext>"
      $hash->{HELPER}{TELEMSG} = $teletxt;
  }
  
  my $chattxt = AttrVal($name, "snapChatTxt", "");
  if($spec =~ /snapChatTxt:/x) {
      ($chattxt) = $spec =~ m/snapChatTxt:"(.*)"/xi;
  }
  
  if ($chattxt) {                                                   # Snap soll per SSChatBot versendet werden, Format $chattxt muss sein: snapChatTxt:"chatbot => <SSChatBot Device>, peers => <peer1 peer2 ..>, subject => <Beschreibungstext>"
      $hash->{HELPER}{CHATMSG} = $chattxt;
  }
  
  __camSnap("$name!_!$num!_!$lag!_!$ncount!_!$emtxt!_!$teletxt!_!$chattxt");

return;
}

################################################################
#                      Setter snapCams
################################################################
sub _setsnapCams {                       ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop}  // q{};
  my $prop1 = $paref->{prop1} // q{};
  my $aref  = $paref->{aref};
  
  return if(IsModelCam($hash));
           
  my ($num,$lag,$ncount) = (1,2,1);
  my $cams               = "all";
  
  if($prop =~ /^\d+$/x) {                                              # Anzahl der Schnappschüsse zu triggern (default: 1)
      $num    = $prop;
      $ncount = $prop;
  }
  
  if($prop1 =~ /^\d+$/x) {                                             # Zeit zwischen zwei Schnappschüssen (default: 2 Sekunden)
      $lag = $prop1;
  }      
  
  my $at = join " ",@$aref;
  if($at =~ /CAM:/xi) {
      ($cams) = $at =~ m/CAM:"(.*)"/xi;
      $cams   =~ s/\s//gx;
  }
  
  my @camdvs;                                                  
  if($cams eq "all") {                                                  # alle nicht disabled Kameras auslösen, sonst nur die gewählten
      @camdvs = devspec2array("TYPE=SSCam:FILTER=MODEL!=SVS");
      for (@camdvs) {
          if($defs{$_} && !IsDisabled($_)) {           
              $hash->{HELPER}{ALLSNAPREF}{$_} = "";                     # Schnappschuss Hash für alle Cams -> Schnappschußdaten sollen hinein  
          }
      }
  } 
  else {
      @camdvs = split(",",$cams);
      for (@camdvs) {
          if($defs{$_} && !IsDisabled($_)) {           
              $hash->{HELPER}{ALLSNAPREF}{$_} = "";
          }              
      }
  }
  
  return "No valid camera devices are specified for trigger snapshots" if(!$hash->{HELPER}{ALLSNAPREF});
  
  my $emtxt;
  my $teletxt = "";
  my $rawet   = AttrVal($name, "snapEmailTxt", "");
  my $bt      = join " ",@$aref;
  
  if($bt =~ /snapEmailTxt:/x) {
      ($rawet) = $bt =~ m/snapEmailTxt:"(.*)"/xi;
  }
  
  if($rawet) {
      $hash->{HELPER}{CANSENDSNAP} = 1;                                # zentraler Schnappschußversand wird aktiviert
      $hash->{HELPER}{SMTPMSG} = $rawet;   
  }
  
  my ($csnap,$cmail) = ("","");
  
  for my $key (keys%{$hash->{HELPER}{ALLSNAPREF}}) {
      if(!AttrVal($key, "snapEmailTxt", "")) {
          delete $hash->{HELPER}{ALLSNAPREF}->{$key};                  # Snap dieser Kamera auslösen aber nicht senden
          $csnap .= $csnap?", $key":$key;
          $emtxt  = "";
      } 
      else {
          $cmail .= $cmail?", $key":$key;
          $emtxt  = $rawet;
      }
      __camSnap("$key!_!$num!_!$lag!_!$ncount!_!$emtxt!_!$teletxt");
  }
  
  Log3($name, 4, "$name - Trigger snapshots by SVS - Number: $num, Lag: $lag, Snap only: \"$csnap\", Snap and send: \"$cmail\" ");

return;
}

################################################################
#                      Setter startTracking
################################################################
sub _setstartTracking {                  ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  
  return if(!IsModelCam($hash));
  
  if ($hash->{HELPER}{API}{PTZ}{VER} < 5) {
      return qq{Function "$opt" needs a higher version of Surveillance Station};
  }
  
  __startTrack($hash);
           
return;
}

################################################################
#                      Setter stopTracking
################################################################
sub _setstopTracking {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  
  return if(!IsModelCam($hash));
  
  if ($hash->{HELPER}{API}{PTZ}{VER} < 5) {
      return qq{Function "$opt" needs a higher version of Surveillance Station};
  }
  
  __stopTrack($hash);
           
return;
}

################################################################
#                      Setter setZoom
################################################################
sub _setsetZoom {                        ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop};
  
  return if(!IsModelCam($hash));
  
  $prop = $prop // "+";                         # Korrektur -> "+" in Taste wird als undef geliefert 
  $prop = ".++" if($prop eq ".");               # Korrektur -> ".++" in Taste wird als "." geliefert       
  __setZoom ("$name!_!$prop");
           
return;
}

################################################################
#                      Setter snapGallery
################################################################
sub _setsnapGallery {                    ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop};
  
  return if(!IsModelCam($hash));
  
  my $ret = getClHash($hash);
  return $ret if($ret);

  if(!AttrVal($name, "snapGalleryBoost",0)) {                                     # Snaphash ist nicht vorhanden und wird neu abgerufen und ausgegeben
      $hash->{HELPER}{GETSNAPGALLERY} = 1;
                                              
      my $slim   = $prop // AttrVal($name,"snapGalleryNumber",$defSlim);          # Anzahl der abzurufenden Snapshots
      my $ssize  = AttrVal($name,"snapGallerySize","Icon") eq "Icon" ? 1 : 2;     # Image Size 1-Icon, 2-Full      
    
      __getSnapInfo("$name:$slim:$ssize");
  } 
  else {                                                                          # Snaphash ist vorhanden und wird zur Ausgabe aufbereitet (Polling ist aktiv)
      $hash->{HELPER}{SNAPLIMIT} = AttrVal($name,"snapGalleryNumber",$defSlim);
      
      my %pars = ( linkparent => $name,
                   linkname   => '',
                   ftui       => 0
                 );
                 
      my $htmlCode = composeGallery(\%pars);
      
      for (my $k=1; (defined($hash->{HELPER}{CL}{$k})); $k++ ) {
          if ($hash->{HELPER}{CL}{$k}->{COMP}) {                                  # CL zusammengestellt (Auslösung durch Notify)
              asyncOutput($hash->{HELPER}{CL}{$k}, "$htmlCode");    
          } 
          else {                                                                  # Output wurde über FHEMWEB ausgelöst
              return $htmlCode;
          }
      }
      
      delClHash  ($name);
  }
           
return;
}

################################################################
#                      Setter createSnapGallery
################################################################
sub _setcreateSnapGallery {              ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  
  return if(!IsModelCam($hash));
  
  if(!AttrVal($name,"snapGalleryBoost",0)) {
      return qq{Before you can use "$opt", you must first set the "snapGalleryBoost" attribute, since automatic snapshot retrieval is required.};
  }
  
  my $sgdev = "SSCamSTRM.$name.snapgallery";
  my $ret   = CommandDefine($hash->{CL},"$sgdev SSCamSTRM {FHEM::SSCam::composeGallery('$name','$sgdev','snapgallery')}");
  
  return $ret if($ret);
  
  my $room             = "SSCam";
  $attr{$sgdev}{room}  = $room;
 
return qq{Snapgallery device "$sgdev" created and assigned to room "$room".};
}

################################################################
#                      Setter createPTZcontrol
################################################################
sub _setcreatePTZcontrol {               ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  
  return if(!IsModelCam($hash));
  
  my $ptzcdev = "SSCamSTRM.$name.PTZcontrol";
  my $ret     = CommandDefine($hash->{CL},"$ptzcdev SSCamSTRM {FHEM::SSCam::ptzPanel('$name','$ptzcdev','ptzcontrol')}");
 
  return $ret if($ret);
  
  my $room               = AttrVal($name,"room","SSCam");
  $attr{$ptzcdev}{room}  = $room;
  $attr{$ptzcdev}{group} = $name."_PTZcontrol";
      
return qq{PTZ control device "$ptzcdev" created and assigned to room "$room".};
}

################################################################
#                      Setter createStreamDev
################################################################
sub _setcreateStreamDev {                ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop};
  
  my ($livedev,$ret);
  
  if($prop =~ /mjpeg/x) {
      $livedev = "SSCamSTRM.$name.mjpeg";
      $ret     = CommandDefine($hash->{CL},"$livedev SSCamSTRM {FHEM::SSCam::streamDev('$name','$livedev','mjpeg')}");
      return $ret if($ret);
  }
  
  if($prop =~ /generic/x) {
      $livedev = "SSCamSTRM.$name.generic";
      $ret     = CommandDefine($hash->{CL},"$livedev SSCamSTRM {FHEM::SSCam::streamDev('$name','$livedev','generic')}");
      return $ret if($ret);
  } 
  
  if($prop =~ /hls/x) {
      $livedev = "SSCamSTRM.$name.hls";
      $ret     = CommandDefine($hash->{CL},"$livedev SSCamSTRM {FHEM::SSCam::streamDev('$name','$livedev','hls')}");
      return $ret if($ret);
     
      my $c = qq{The device needs to set attribute "hlsStrmObject" in camera device "$name" to a valid HLS videostream};
      CommandAttr($hash->{CL},"$livedev comment $c");
  } 
  
  if($prop =~ /lastsnap/x) {
      $livedev = "SSCamSTRM.$name.lastsnap";
      $ret     = CommandDefine($hash->{CL},"$livedev SSCamSTRM {FHEM::SSCam::streamDev('$name','$livedev','lastsnap')}");
      return $ret if($ret);
      
      my $c = qq{The device shows the last snapshot of camera device "$name". \n}.
              qq{If you always want to see the newest snapshot, please set attribute "pollcaminfoall" in camera device "$name".\n}.
              qq{Set also attribute "snapGallerySize = Full" in camera device "$name" to retrieve snapshots in original resolution.};
      CommandAttr($hash->{CL},"$livedev comment $c");
  } 
  
  if($prop =~ /switched/x) {
      $livedev = "SSCamSTRM.$name.switched";
      $ret     = CommandDefine($hash->{CL},"$livedev SSCamSTRM {FHEM::SSCam::streamDev('$name','$livedev','switched')}");
      return $ret if($ret);
  }
  
  if($prop =~ /master/x) {
      $livedev = "SSCamSTRM.$name.master";
      $ret     = CommandDefine($hash->{CL},"$livedev SSCamSTRM {FHEM::SSCam::streamDev('$name','$livedev','master')}");
      return $ret if($ret);
  }
  
  my $room              = AttrVal($name,"room","SSCam");
  $attr{$livedev}{room} = $room;
      
return qq{Livestream device "$livedev" created and assigned to room "$room".};
}

################################################################
#                      Setter createReadingsGroup
################################################################
sub _setcreateReadingsGroup {            ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $prop  = $paref->{prop};
  
  my $rgdev = $prop // "RG.SSCam";
  
  my $rgdef = '<%it_camera>,<Kamera<br>On/Offline>,< >,<Status>,< >,<Bewegungs<br>erkennung>,< >,<letzte Aufnahme>,< >,<bel. Platz<br>(MB)>,< >,<letzte Aktualisierung>,< >,<Disable<br>Modul>,< >,<Wiedergabe>'."\n". 
              'TYPE=SSCam:FILTER=MODEL!=SVS:Availability,<&nbsp;>,state,<&nbsp;>,!CamMotDetSc,<&nbsp;>,!CamLastRecTime,<&nbsp;>,!UsedSpaceMB,<&nbsp;>,!LastUpdateTime,<&nbsp;>,?!disable,<&nbsp;>,?!LSnap,?!LRec,?!Start,?!Stop'."\n". 
              '< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >'."\n".
              '< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >'."\n".
              '< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >,< >'."\n".
              '<%it_server>,<HomeMode<br>On/Off>,<&nbsp;>,<Status>,<&nbsp;>,&nbsp;>,<&nbsp;>,<&nbsp;>,<&nbsp;>,<&nbsp;>,&nbsp;>,<&nbsp;>,<&nbsp;>,<&nbsp;>,<&nbsp;>,<&nbsp;>,<&nbsp;>,<&nbsp;>,<&nbsp;>,<&nbsp;>,<&nbsp;>'."\n".
              'TYPE=SSCam:FILTER=MODEL=SVS:!HomeModeState,<&nbsp;>,state,<&nbsp;>,<&nbsp;>,<&nbsp;>,<&nbsp;>,<&nbsp;>,<&nbsp;>,&nbsp;>,<&nbsp;>,<&nbsp;>,<&nbsp;>,?!disable,<&nbsp;>,<&nbsp;>,<&nbsp;>,<&nbsp;>,<&nbsp;>'."\n".
              '';
  
  my $ret     = CommandDefine($hash->{CL},"$rgdev readingsGroup $rgdef");
  return $ret if($ret);
  
  my $room    = AttrVal($name,"room","SSCam");
  CommandAttr($hash->{CL},"$rgdev room $room");
  CommandAttr($hash->{CL},"$rgdev alias Überblick Kameras");
  
  my $cellStyle = '{'."\n". 
                  '  "c:0" => \'style="text-align:left;font-weight:normal"\','."\n".
                  '  "c:1" => \'style="text-align:left;font-weight:normal"\','."\n".
                  '  "c:4" => \'style="text-align:center;font-weight:bold"\','."\n".
                  '  "c:5" => \'style="text-align:center;color:green;font-weight:normal"\','."\n".
                  '  "c:9" => \'style="text-align:center;font-weight:normal"\''."\n".
                  '}';
  CommandAttr($hash->{CL},"$rgdev cellStyle $cellStyle");
                             
  my $commands = '{'."\n".
                 '  "Availability.enabled"  => "set $DEVICE disable",'."\n".
                 '  "Availability.disabled" => "set $DEVICE enable",'."\n".
                 '  "HomeModeState.on"      => "set $DEVICE homeMode off",'."\n".
                 '  "HomeModeState.off"     => "set $DEVICE homeMode on",'."\n".
                 '  "'.$rgdev.'.Start"        => "set %DEVICE runView live_fw",'."\n".
                 '  "Start"                 => "set %DEVICE runView live_fw",'."\n".
                 '  "LRec"                  => "set %DEVICE runView lastrec_fw",'."\n".
                 '  "LSnap"                 => "set %DEVICE runView lastsnap_fw",'."\n".
                 '  "Stop"                  => "set %DEVICE stopView",'."\n".
                 '  "Record"                => "runView:",'."\n".
                 '  "disable"               => "disable:"'."\n".    
                 '}';
  CommandAttr($hash->{CL},"$rgdev commands $commands");
  
  my $nameStyle = 'style = "color:black;font-weight:bold;text-align:center"';
  CommandAttr($hash->{CL},"$rgdev nameStyle $nameStyle");
  
  my $valueColumns = '{'."\n".
                     '  \'Wiedergabe\' => \'colspan="4"\''."\n".    
                     '}';
  CommandAttr($hash->{CL},"$rgdev valueColumns $valueColumns");

  my $valueFormat = '{'."\n". 
                    '  ($READING eq "CamMotDetSc" && $VALUE eq "disabled") ? "external" : $VALUE'."\n". 
                    '}';    
  CommandAttr($hash->{CL},"$rgdev valueFormat $valueFormat");

  my $valueIcon = '{'."\n". 
                  '  "Availability.enabled"  => "remotecontrol/black_btn_GREEN",'."\n".
                  '  "Availability.disabled" => "remotecontrol/black_btn_RED",'."\n".
                  '  "HomeModeState.on"      => "status_available",'."\n".
                  '  "HomeModeState.off"     => "status_away_1\@orange",'."\n".
                  '  "Start"                 => "black_btn_MJPEG",'."\n".
                  '  "LRec"                  => "black_btn_LASTRECIFRAME",'."\n". 
                  '  "LSnap"                 => "black_btn_LSNAP",'."\n".                      
                  '  "Stop"                  => "remotecontrol/black_btn_POWEROFF3",'."\n".                     
                  '  "state.initialized"     => "remotecontrol/black_btn_STOP",'."\n".
                  '  "state"                 => "%devStateIcon"'."\n".
                  '}';
  CommandAttr($hash->{CL},"$rgdev valueIcon $valueIcon");
  
  my $valueStyle = '{'."\n". 
                   '  if($READING eq "Availability" && $VALUE eq "enabled"){ \' style="color:green" \' }'."\n".
                   '  elsif( $READING eq "Availability" && $VALUE eq  "disabled"){ \' style="color:red" \' }'."\n".
                   '  elsif( $READING eq "CamMotDetSc" && $VALUE =~ /SVS.*/ ){ \' style="color:orange" \' }'."\n".
                   '  elsif( $READING eq "CamMotDetSc" && $VALUE eq "disabled"){ \' style="color:LimeGreen" \' }'."\n".
                   '  elsif( $READING eq "CamMotDetSc" && $VALUE =~ /Cam.*/ ){ \' style="color:SandyBrown" \' }'."\n".
                   '}';     
  CommandAttr($hash->{CL},"$rgdev valueStyle $valueStyle");
          
return qq{readingsGroup device "$rgdev" created and assigned to room "$room".};
}

################################################################
#                      Setter enable
################################################################
sub _setenable {                         ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  return if(!IsModelCam($hash));
  
  __camEnable($hash);
          
return;
}

################################################################
#                      Setter disable
################################################################
sub _setdisable {                        ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  return if(!IsModelCam($hash));
  
  __camDisable($hash);
          
return;
}

################################################################
#                      Setter motdetsc
################################################################
sub _setmotdetsc {                       ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop};
  my $prop1 = $paref->{prop1};
  my $prop2 = $paref->{prop2};
  my $prop3 = $paref->{prop3};
  
  return if(!IsModelCam($hash));
  
  if (!$prop || $prop !~ /disable|camera|SVS/x) { 
      return qq{Command "$opt" needs one of those arguments: disable, camera, SVS !}; 
  }
        
  $hash->{HELPER}{MOTDETSC} = $prop;
        
  if ($prop1) {                                                        
      if ($prop1 !~ /^[1-9][0-9]?$/x) {
          return "Invalid value for sensitivity (SVS or camera). Use numbers between 1 - 99";
      }
      $hash->{HELPER}{MOTDETSC_PROP1} = $prop1;
  }
  
  if ($prop2) {                                                        
      if ($prop2 !~ /^[1-9][0-9]?$/x) {
          return "Invalid value for threshold (SVS) / object size (camera). Use numbers between 1 - 99";
      }
      $hash->{HELPER}{MOTDETSC_PROP2} = $prop2;
  }
  
  if ($prop3) {                                                         
      if ($prop3 !~ /^[1-9][0-9]?$/x) {
          return "Invalid value for threshold (SVS) / object size (camera). Use numbers between 1 - 99";
      }
      $hash->{HELPER}{MOTDETSC_PROP3} = $prop3;
  }
  
  __camMotDetSc($hash);
          
return;
}

################################################################
#                      Setter expmode
################################################################
sub _setexpmode {                        ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop};
  
  return if(!IsModelCam($hash));
  
  if(!$prop) {
      return qq{Command "$opt" needs one of those arguments: auto, day, night};
  }
            
  $hash->{HELPER}{EXPMODE} = $prop;
  
  __camExpmode($hash);
          
return;
}

################################################################
#                      Setter homeMode
################################################################
sub _sethomeMode {                       ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop};
  
  return if(IsModelCam($hash));
  
  if(!$prop) {
      return qq{Command "$opt" needs one of those arguments: on, off};
  }
            
  $hash->{HELPER}{HOMEMODE} = $prop;
  
  __setHomeMode($hash);
          
return;
}

################################################################
#                      Setter autocreateCams
################################################################
sub _setautocreateCams {                 ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  return if(IsModelCam($hash));
  
  __camAutocreate($hash);
          
return;
}

################################################################
#                      Setter goPreset
################################################################
sub _setgoPreset {                       ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop};
  
  return if(!IsModelCam($hash));
  
  if (!$prop) {
      return qq{Command "$opt" needs a <Presetname> as an argument};
  }
        
  $hash->{HELPER}{GOPRESETNAME} = $prop;
  $hash->{HELPER}{PTZACTION}    = "gopreset";
  
  __doPtzAaction($hash);
          
return;
}

################################################################
#                      Setter optimizeParams
################################################################
sub _setoptimizeParams {                 ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $aref  = $paref->{aref};
  
  return if(!IsModelCam($hash));
  
  my %cpcl = (ntp => 1, mirror => 2, flip => 4, rotate => 8);
        
  for my $part (@$aref) {
      $hash->{HELPER}{MIRROR}  = (split "mirror:", $part)[1] if(lc($part) =~ m/^mirror:/x);
      $hash->{HELPER}{FLIP}    = (split "flip:",   $part)[1] if(lc($part) =~ m/^flip:/x);
      $hash->{HELPER}{ROTATE}  = (split "rotate:", $part)[1] if(lc($part) =~ m/^rotate:/x);
      $hash->{HELPER}{NTPSERV} = (split "ntp:",    $part)[1] if(lc($part) =~ m/^ntp:/x);      
  }
  
  $hash->{HELPER}{CHKLIST} = ($hash->{HELPER}{NTPSERV} ? $cpcl{ntp}    : 0)+
                             ($hash->{HELPER}{MIRROR}  ? $cpcl{mirror} : 0)+
                             ($hash->{HELPER}{FLIP}    ? $cpcl{flip}   : 0)+
                             ($hash->{HELPER}{ROTATE}  ? $cpcl{rotate} : 0);  
        
  __setOptParams($hash);
          
return;
}

################################################################
#                      Setter pirSensor
################################################################
sub _setpirSensor {                      ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop};
  
  return if(!IsModelCam($hash));

  if(ReadingsVal($name, "CapPIR", "false") eq "false") {
      return qq{Command "$opt" not possible. Camera "$name" don't provide a PIR sensor.};
  }

  if(!$prop) {
      return qq{Command "$opt" needs an argument};
  }
      
  $hash->{HELPER}{PIRACT} = ($prop eq "activate") ? 0 : ($prop eq "deactivate") ? -1 : 5;
      
  if($hash->{HELPER}{PIRACT} == 5) {
      return qq{Illegal argument for "$opt" detected. Use "activate" or "activate".};
  }
   
  __managePir($hash);
          
return;
}

################################################################
#                      Setter runPatrol
################################################################
sub _setrunPatrol {                      ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop};
  
  return if(!IsModelCam($hash));

  if (!$prop) {
      return qq{Command "$opt" needs a <Patrolname> as an argument};
  }
        
  $hash->{HELPER}{GOPATROLNAME} = $prop;
  $hash->{HELPER}{PTZACTION}    = "runpatrol";
  
  __doPtzAaction($hash);
          
return;
}

################################################################
#                      Setter goAbsPTZ
################################################################
sub _setgoAbsPTZ {                       ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop};
  my $prop1 = $paref->{prop1};
  
  return if(!IsModelCam($hash));

  if ($prop eq "up" || $prop eq "down" || $prop eq "left" || $prop eq "right") {
      if ($prop eq "up")    {$hash->{HELPER}{GOPTZPOSX} = 320; $hash->{HELPER}{GOPTZPOSY} = 480;}
      if ($prop eq "down")  {$hash->{HELPER}{GOPTZPOSX} = 320; $hash->{HELPER}{GOPTZPOSY} = 0;  }
      if ($prop eq "left")  {$hash->{HELPER}{GOPTZPOSX} = 0;   $hash->{HELPER}{GOPTZPOSY} = 240;}    
      if ($prop eq "right") {$hash->{HELPER}{GOPTZPOSX} = 640; $hash->{HELPER}{GOPTZPOSY} = 240;} 
            
      $hash->{HELPER}{PTZACTION} = "goabsptz";
      __doPtzAaction($hash);
      return;    
  } 
  else {
      if ($prop !~ /\d+/x || $prop1 !~ /\d+/x || abs($prop) > 640 || abs($prop1) > 480) {
          return qq{Command "$opt" needs two coordinates within limits posX=0-640 and posY=0-480 as arguments or use up, down, left, right instead};
      }
            
      $hash->{HELPER}{GOPTZPOSX} = abs($prop);
      $hash->{HELPER}{GOPTZPOSY} = abs($prop1);
      $hash->{HELPER}{PTZACTION} = "goabsptz";
      __doPtzAaction($hash);
      return;     
  } 
      
return qq{Command "$opt" needs two coordinates, posX=0-640 and posY=0-480, as arguments or use up, down, left, right instead};
}

################################################################
#                      Setter move
################################################################
sub _setmove {                           ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop};
  my $prop1 = $paref->{prop1};
  
  return if(!IsModelCam($hash));

  if(!$hash->{HELPER}{API}{PTZ}{VER}) {
      return qq{PTZ version of Synology API isn't set. Use "get $name scanVirgin" first.}
  };
  
  if($hash->{HELPER}{API}{PTZ}{VER} <= 4) {
      if (!defined($prop) || ($prop !~ /^up$|^down$|^left$|^right$|^dir_\d$/x)) {
          return qq{Command "$opt" needs an argument like up, down, left, right or dir_X (X = 0 to CapPTZDirections-1)};
      }
      $hash->{HELPER}{GOMOVEDIR} = $prop;
  
  } elsif ($hash->{HELPER}{API}{PTZ}{VER} >= 5) {
      if (!defined($prop) || ($prop !~ /^right$|^upright$|^up$|^upleft$|^left$|^downleft$|^down$|^downright$/x)) {
          return qq{Command "$opt" needs an argument like right, upright, up, upleft, left, downleft, down, downright};
      }
      
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
  
  $hash->{HELPER}{GOMOVETIME} = $prop1 // 1;      
  $hash->{HELPER}{PTZACTION}  = "movestart";
  
  __doPtzAaction($hash); 
      
return;
}

################################################################
#                      Setter runView
################################################################
sub _setrunView {                        ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $aref  = $paref->{aref};
  my $prop  = $paref->{prop};
  my $prop1 = $paref->{prop1};
  
  return if(!IsModelCam($hash));

  my $spec = join " ", @$aref;
  if($spec =~ /STRM:/x) {
      ($hash->{HELPER}{INFORM}) = $spec =~ m/STRM:(.*)/xi;  # Call by SSCamSTRM-Device
  } 
  
  if ($prop eq "live_open") {
      if ($prop1) {
          $hash->{HELPER}{VIEWOPENROOM} = $prop1;
      } 
      else {
          delete $hash->{HELPER}{VIEWOPENROOM};
      }
      
      $hash->{HELPER}{OPENWINDOW} = 1;
      $hash->{HELPER}{WLTYPE}     = "link";    
      $hash->{HELPER}{ALIAS}      = "LiveView";
      $hash->{HELPER}{RUNVIEW}    = "live_open";
      $hash->{HELPER}{ACTSTRM}    = "";                     # sprechender Name des laufenden Streamtyps für SSCamSTRM
  
  } elsif ($prop eq "live_link") {
      $hash->{HELPER}{OPENWINDOW} = 0;
      $hash->{HELPER}{WLTYPE}     = "link"; 
      $hash->{HELPER}{ALIAS}      = "LiveView";
      $hash->{HELPER}{RUNVIEW}    = "live_link";
      $hash->{HELPER}{ACTSTRM}    = "";                     # sprechender Name des laufenden Streamtyps für SSCamSTRM
  
  } elsif ($prop eq "lastrec_open") {
      if ($prop1) {
          $hash->{HELPER}{VIEWOPENROOM} = $prop1;
      } 
      else {
          delete $hash->{HELPER}{VIEWOPENROOM};
      }
      
      $hash->{HELPER}{OPENWINDOW} = 1;
      $hash->{HELPER}{WLTYPE}     = "link"; 
      $hash->{HELPER}{ALIAS}      = "LastRecording";
      $hash->{HELPER}{RUNVIEW}    = "lastrec_open";
      $hash->{HELPER}{ACTSTRM}    = "";                     # sprechender Name des laufenden Streamtyps für SSCamSTRM
  
  }  elsif ($prop eq "lastrec_fw") {                        # Video in iFrame eingebettet
      $hash->{HELPER}{OPENWINDOW} = 0;
      $hash->{HELPER}{WLTYPE}     = "iframe"; 
      $hash->{HELPER}{ALIAS}      = " ";
      $hash->{HELPER}{RUNVIEW}    = "lastrec";
      $hash->{HELPER}{ACTSTRM}    = "last Recording";       # sprechender Name des laufenden Streamtyps für SSCamSTRM
  
  } elsif ($prop eq "lastrec_fw_MJPEG") {                   # “video/avi” – MJPEG format event
      $hash->{HELPER}{OPENWINDOW} = 0;
      $hash->{HELPER}{WLTYPE}     = "image"; 
      $hash->{HELPER}{ALIAS}      = " ";
      $hash->{HELPER}{RUNVIEW}    = "lastrec";
      $hash->{HELPER}{ACTSTRM}    = "last Recording";       # sprechender Name des laufenden Streamtyps für SSCamSTRM
  
  } elsif ($prop eq "lastrec_fw_MPEG4/H.264") {             # “video/mp4” – MPEG4/H.264 format event
      $hash->{HELPER}{OPENWINDOW} = 0;
      $hash->{HELPER}{WLTYPE}     = "video"; 
      $hash->{HELPER}{ALIAS}      = " ";
      $hash->{HELPER}{RUNVIEW}    = "lastrec";
      $hash->{HELPER}{ACTSTRM}    = "last Recording";       # sprechender Name des laufenden Streamtyps für SSCamSTRM
  
  } elsif ($prop eq "live_fw") {
      $hash->{HELPER}{OPENWINDOW} = 0;
      $hash->{HELPER}{WLTYPE}     = "image"; 
      $hash->{HELPER}{ALIAS}      = " ";
      $hash->{HELPER}{RUNVIEW}    = "live_fw";
      $hash->{HELPER}{ACTSTRM}    = "MJPEG Livestream";     # sprechender Name des laufenden Streamtyps für SSCamSTRM
  
  } elsif ($prop eq "live_fw_hls") {
      if(!IsCapHLS($hash)) {
          return qq{API "SYNO.SurveillanceStation.VideoStream" is not available or Reading "CamStreamFormat" is not "HLS". May be your API version is 2.8 or lower.};
      }
      
      $hash->{HELPER}{OPENWINDOW} = 0;
      $hash->{HELPER}{WLTYPE}     = "hls"; 
      $hash->{HELPER}{ALIAS}      = "View only on compatible browsers";
      $hash->{HELPER}{RUNVIEW}    = "live_fw_hls";
      $hash->{HELPER}{ACTSTRM}    = "HLS Livestream";       # sprechender Name des laufenden Streamtyps für SSCamSTRM
  
  } elsif ($prop eq "lastsnap_fw") {
      $hash->{HELPER}{LSNAPBYSTRMDEV} = 1 if($prop1);       # Anzeige durch SSCamSTRM-Device ausgelöst
      $hash->{HELPER}{LSNAPBYDEV}     = 1 if(!$prop1);      # Anzeige durch SSCam ausgelöst
      $hash->{HELPER}{OPENWINDOW}     = 0;
      $hash->{HELPER}{WLTYPE}         = "base64img"; 
      $hash->{HELPER}{ALIAS}          = " ";
      $hash->{HELPER}{RUNVIEW}        = "lastsnap_fw";
      $hash->{HELPER}{ACTSTRM}        = "last Snapshot";    # sprechender Name des laufenden Streamtyps für SSCamSTRM
  } 
  else {
      return qq{"$prop" isn't a valid option of runview, use one of live_fw, live_link, live_open, lastrec_fw, lastrec_open, lastsnap_fw};
  }
  
  __runLiveview($hash);
      
return;
}

################################################################
#                      Setter hlsreactivate
#                      ohne SET-Menüeintrag 
################################################################
sub _sethlsreactivate {                  ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  return if(!IsModelCam($hash));

  __reactivateHls($hash);                  
      
return;
}

################################################################
#                      Setter hlsactivate
#                     ohne SET-Menüeintrag 
################################################################
sub _sethlsactivate {                    ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $aref  = $paref->{aref};
  
  return if(!IsModelCam($hash));

      my $spec = join " ", @$aref;
      
      if($spec =~ /STRM:/x) {
          ($hash->{HELPER}{INFORM}) = $spec =~ m/STRM:(.*)/xi;         # Call by SSCamSTRM-Device
      }
      
      __activateHls($hash);                                                   

return;
}

################################################################
#                      Setter refresh
#                   ohne SET-Menüeintrag
################################################################
sub _setrefresh {                        ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $aref  = $paref->{aref};
  
  return if(!IsModelCam($hash));

  my $spec = join " ", @$aref;
  
  if($spec =~ /STRM:/x) {
      ($hash->{HELPER}{INFORM}) = $spec =~ m/STRM:(.*)/xi;         # Refresh by SSCamSTRM-Device
      roomRefresh($hash,0,0,1);                                    # kein Room-Refresh, kein SSCam-state-Event, SSCamSTRM-Event
  }     

return;
}

################################################################
#                      Setter extevent
################################################################
sub _setextevent {                       ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $prop  = $paref->{prop};
  
  return if(IsModelCam($hash));
  
  $hash->{HELPER}{EVENTID} = $prop;
  __extEvent($hash);  

return;
}

################################################################
#                      Setter stopView
################################################################
sub _setstopView {                       ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $aref  = $paref->{aref};
  
  return if(!IsModelCam($hash));
  
  my $spec = join " ", @$aref;
  if($spec =~ /STRM:/x) {
      ($hash->{HELPER}{INFORM}) = $spec =~ m/STRM:(.*)/xi;         # Stop by SSCamSTRM-Device
  } 
  __stopLiveview($hash);

return;
}

################################################################
#                      Setter setPreset
################################################################
sub _setsetPreset {                      ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop};
  my $prop1 = $paref->{prop1};
  my $prop2 = $paref->{prop2};
  
  return if(!IsModelCam($hash));
  
  if (!$prop) {
      return qq{Syntax of Command "$opt" was wrong. Please use "set $name setPreset <PresetNumber> <PresetName> [<Speed>]"};
  }
  
  $hash->{HELPER}{PNUMBER} = $prop;
  $hash->{HELPER}{PNAME}   = $prop1 // $prop;    # wenn keine Presetname angegeben -> Presetnummer als Name verwenden
  $hash->{HELPER}{PSPEED}  = $prop2 if($prop2);
  
  __setPreset($hash);

return;
}

################################################################
#                      Setter setHome
################################################################
sub _setsetHome {                        ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop};
  
  return if(!IsModelCam($hash));
  
  if (!$prop) {
      return qq{Command "$opt" needs a <Presetname> as argument};
  }      
  
  $hash->{HELPER}{SETHOME} = $prop;
  __setHome($hash);

return;
}

################################################################
#                      Setter delPreset
################################################################
sub _setdelPreset {                      ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop};
  
  return if(!IsModelCam($hash));
  
  if (!$prop) {
      return qq{Function "$opt" needs a <Presetname> as argument};
  }
  
  $hash->{HELPER}{DELPRESETNAME} = $prop;
  __delPreset($hash);

return;
}

###############################################################################
#                          Kamera Aufnahme starten
###############################################################################
sub __camStartRec {
    my $str                             = shift;
    my ($name,$emtxt,$teletxt,$chattxt) = split("!_!",$str);
    my $hash                            = $defs{$name};
    my $camname                         = $hash->{CAMNAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    
    return if(IsDisabled($name)); 
    return if(exitOnDis ($name, "Start Recording of Camera $camname can't be executed"));
        
    if (ReadingsVal("$name", "Record", "") eq "Start" && !AttrVal($name, "recextend", "")) {
        Log3($name, 3, "$name - another recording is already running - new start-command will be ignored");
        return;
    } 
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                      
        $hash->{OPMODE}               = "Start"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $str);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY} = "EXTREC";
        $hash->{HELPER}{CALL}{PART} = qq{api=_NAME_&version=_VER_&method=Record&cameraId=_CID_&action=start&_sid="_SID_"};
      
        if($hash->{HELPER}{API}{EXTREC}{VER} >= 3) {
            $hash->{HELPER}{CALL}{PART} = qq{api=_NAME_&version=_VER_&method=Record&cameraIds=_CID_&action=start&_sid="_SID_"};
        }
        
        if($emtxt || $teletxt || $chattxt) {
            $hash->{HELPER}{CANSENDREC} = 1        if($emtxt);           # Versand Aufnahme soll per Email erfolgen
            $hash->{HELPER}{CANTELEREC} = 1        if($teletxt);         # Versand Aufnahme soll per TelegramBot erfolgen
            $hash->{HELPER}{CANCHATREC} = 1        if($chattxt);         # Versand Aufnahme soll per SSChatBot erfolgen
            $hash->{HELPER}{SMTPRECMSG} = $emtxt   if($emtxt);           # Text für Email-Versand
            $hash->{HELPER}{TELERECMSG} = $teletxt if($teletxt);         # Text für Telegram-Versand
            $hash->{HELPER}{CHATRECMSG} = $chattxt if($chattxt);         # Text für Synology Chat-Versand
        }   
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $str);
    }
    
return;
}

###############################################################################
#                           Kamera Aufnahme stoppen
###############################################################################
sub __camStopRec {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    
    return if(IsDisabled($name));
    return if(exitOnDis ($name, "Stop Recording of Camera $camname can't be executed"));        
        
    if (ReadingsVal("$name", "Record", undef) eq "Stop") {
        Log3($name, 3, "$name - recording is already stopped - new stop-command will be ignored");
        return;
    } 
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        $hash->{OPMODE}               = "Stop"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY} = "EXTREC";
        $hash->{HELPER}{CALL}{PART} = qq{api=_NAME_&version=_VER_&method=Record&cameraId=_CID_&action=stop&_sid="_SID_"};
      
        if($hash->{HELPER}{API}{EXTREC}{VER} >= 3) {
            $hash->{HELPER}{CALL}{PART} = qq{api=_NAME_&version=_VER_&method=Record&cameraIds=_CID_&action=stop&_sid="_SID_"};
        }  
               
        setActiveToken($hash);  
        checkSid      ($hash);     
    } 
    else {
        schedule ($name, $hash);
    }
    
return;
}

###############################################################################
#                   Kamera Auto / Day / Nightmode setzen
###############################################################################
sub __camExpmode {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    
    return if(IsDisabled($name));
    return if(exitOnDis ($name, "Setting exposure mode of Camera $camname can't be executed"));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                           
        $hash->{OPMODE}               = "ExpMode"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        my $expmode                   = $hexmo{$hash->{HELPER}{EXPMODE}};
        
        $hash->{HELPER}{CALL}{VKEY}   = "CAM";
        my $ver                       = ($hash->{HELPER}{API}{CAM}{VER} >= 9) ? 8 : $hash->{HELPER}{API}{CAM}{VER};
        $hash->{HELPER}{CALL}{PART}   = qq{api="_NAME_"&version="$ver"&method="SaveOptimizeParam"&cameraIds="_CID_"&expMode="$expmode"&camParamChkList=32&_sid="_SID_"};     
                
        setActiveToken($hash);
        checkSid      ($hash);    
    } 
    else {
        schedule ($name, $hash);
    }
    
return;
}

###############################################################################
#                    Art der Bewegungserkennung setzen
###############################################################################
sub __camMotDetSc {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    
    return if(IsDisabled($name));
    return if(exitOnDis ($name, "Setting of motion detection source of Camera $camname can't be executed"));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {             
        $hash->{OPMODE}               = "MotDetSc"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "CAMEVENT";
        
        my %motdetoptions = ();                                                  # Hash für Optionswerte sichern für Logausgabe in Befehlsauswertung
        my $motdetsc;
        
        if ($hash->{HELPER}{MOTDETSC} eq "disable") {
            $motdetsc                   = "-1";
            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version="_VER_"&method="MDParamSave"&camId="_CID_"&source=$motdetsc&keep=true};
      
        } elsif ($hash->{HELPER}{MOTDETSC} eq "camera") {
            $motdetsc                   = "0";
            $motdetoptions{SENSITIVITY} = $hash->{HELPER}{MOTDETSC_PROP1} if ($hash->{HELPER}{MOTDETSC_PROP1});
            $motdetoptions{OBJECTSIZE}  = $hash->{HELPER}{MOTDETSC_PROP2} if ($hash->{HELPER}{MOTDETSC_PROP2});
            $motdetoptions{PERCENTAGE}  = $hash->{HELPER}{MOTDETSC_PROP3} if ($hash->{HELPER}{MOTDETSC_PROP3});
          
            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version="_VER_"&method="MDParamSave"&camId="_CID_"&source=$motdetsc};
          
            if ($hash->{HELPER}{MOTDETSC_PROP1} || $hash->{HELPER}{MOTDETSC_PROP2} || $hash->{HELPER}{MOTDETSC_PROP3}) {
                $hash->{HELPER}{CALL}{PART} .= qq{&mode=1};                      # umschalten und neue Werte setzen
            } 
            else {                                                               # nur Umschaltung, alte Werte beibehalten
                $hash->{HELPER}{CALL}{PART} .= qq{&mode=0};
            }
 
            if ($hash->{HELPER}{MOTDETSC_PROP1}) {                               # der Wert für Bewegungserkennung Kamera -> Empfindlichkeit ist gesetzt
                my $sensitivity              = delete $hash->{HELPER}{MOTDETSC_PROP1};
                $hash->{HELPER}{CALL}{PART} .= qq{&sensitivity="$sensitivity"};
            }
          
            if ($hash->{HELPER}{MOTDETSC_PROP2}) {                               # der Wert für Bewegungserkennung Kamera -> Objektgröße ist gesetzt
                my $objectsize               = delete $hash->{HELPER}{MOTDETSC_PROP2};
                $hash->{HELPER}{CALL}{PART} .= qq{&objectSize="$objectsize"};
            }
 
            if ($hash->{HELPER}{MOTDETSC_PROP3}) {                               # der Wert für Bewegungserkennung Kamera -> Prozentsatz für Auslösung ist gesetzt
                my $percentage               = delete $hash->{HELPER}{MOTDETSC_PROP3};
                $hash->{HELPER}{CALL}{PART} .= qq{&percentage="$percentage"};
            }          
      
        } elsif ($hash->{HELPER}{MOTDETSC} eq "SVS") {
            $motdetsc                   = "1";
            $motdetoptions{SENSITIVITY} = $hash->{HELPER}{MOTDETSC_PROP1} if ($hash->{HELPER}{MOTDETSC_PROP1});
            $motdetoptions{THRESHOLD}   = $hash->{HELPER}{MOTDETSC_PROP2} if ($hash->{HELPER}{MOTDETSC_PROP2});

            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version="_VER_"&method="MDParamSave"&camId="_CID_"&source=$motdetsc};

            if ($hash->{HELPER}{MOTDETSC_PROP1} || $hash->{HELPER}{MOTDETSC_PROP2}) {
                $hash->{HELPER}{CALL}{PART} .= qq{&mode=1};                      # umschalten und neue Werte setzen
            } 
            else {                                                               # nur Umschaltung, alte Werte beibehalten
                $hash->{HELPER}{CALL}{PART} .= qq{&mode=0};
            }
            
            if ($hash->{HELPER}{MOTDETSC_PROP1}) {                               # der Wert für Bewegungserkennung SVS -> Empfindlichkeit ist gesetzt
                my $sensitivity              = delete $hash->{HELPER}{MOTDETSC_PROP1};
                $hash->{HELPER}{CALL}{PART} .= qq{&sensitivity="$sensitivity"};
            }

            if ($hash->{HELPER}{MOTDETSC_PROP2}) {                               # der Wert für Bewegungserkennung SVS -> Schwellwert ist gesetzt
                my $threshold                = delete $hash->{HELPER}{MOTDETSC_PROP2};
                $hash->{HELPER}{CALL}{PART} .= qq{&threshold="$threshold"};
            }
        }
        
        $hash->{HELPER}{CALL}{PART} .= qq{&_sid="_SID_"};
      
        $hash->{HELPER}{MOTDETOPTIONS} = \%motdetoptions;                        # Optionswerte in Hash sichern für Logausgabe in Befehlsauswertung
     
        setActiveToken($hash);    
        checkSid      ($hash);
        
    } else {
        schedule ($name, $hash);
    }
   
return;
}

###############################################################################
#                       Kamera Schappschuß aufnehmen
#   $num    = Anzahl der Schnappschüsse
#   $lag    = Zeit zwischen zwei Schnappschüssen
#   $ncount = Anzahl der Schnappschüsse zum rnterzählen
###############################################################################
sub __camSnap {
    my $str              = shift;
    my ($name,$num,$lag,$ncount,$emtxt,$teletxt,$chattxt,$tac) = split("!_!",$str);
    my $hash             = $defs{$name};
    my $camname          = $hash->{CAMNAME};
    
    $tac       = $tac // 5000;
    my $ta     = $hash->{HELPER}{TRANSACTION};
    my $caller = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    
    return if(IsDisabled($name));
    return if(exitOnDis ($name, "Snapshot of Camera $camname can't be executed"));
    
    if ($hash->{HELPER}{ACTIVE} eq "off" || (defined $ta && $ta == $tac)) {             
        $hash->{OPMODE}               = "Snap";
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $str);
            return;
        }
        
        $hash->{HELPER}{CANSENDSNAP}  = 1       if($emtxt);                        # Versand Schnappschüsse soll per Email erfolgen
        $hash->{HELPER}{CANTELESNAP}  = 1       if($teletxt);                      # Versand Schnappschüsse soll per TelegramBot erfolgen
        $hash->{HELPER}{CANCHATSNAP}  = 1       if($chattxt);                      # Versand Schnappschüsse soll per SSChatBot erfolgen
        $hash->{HELPER}{SNAPNUM}      = $num    if($num);                          # Gesamtzahl der auszulösenden Schnappschüsse
        $hash->{HELPER}{SNAPLAG}      = $lag    if($lag);                          # Zeitverzögerung zwischen zwei Schnappschüssen
        $hash->{HELPER}{SNAPNUMCOUNT} = $ncount if($ncount);                       # Restzahl der auszulösenden Schnappschüsse  (wird runtergezählt)
        $hash->{HELPER}{SMTPMSG}      = $emtxt  if($emtxt);                        # Text für Email-Versand

        $hash->{HELPER}{CALL}{VKEY}   = "SNAPSHOT";
        $hash->{HELPER}{CALL}{PART}   = qq{api="_NAME_"&version="_VER_"&dsId="0"&method="TakeSnapshot"&blSave="true"&camId="_CID_"&_sid="_SID_"};
        
        readingsSingleUpdate($hash,"state", "snap", 1); 
    
        setActiveToken($hash); 
        checkSid      ($hash);    
    } 
    else {
        $tac = $tac // "";
        schedule ($name, $str);
    } 

return;    
}

###############################################################################
#                     Kamera gemachte Aufnahme abrufen
###############################################################################
sub __getRec {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);

    return if(IsDisabled($name));
    return if(exitOnDis ($name, "Save Recording of Camera $camname in local file can't be executed"));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {              
        $hash->{OPMODE}               = "GetRec"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "REC";
        my $recid                     = ReadingsVal("$name", "CamLastRecId", 0);
      
        if($recid) {
            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version="_VER_"&id=$recid&mountId=0&method="Download"&_sid="_SID_"};      
        } 
        else {
            Log3($name, 2, "$name - WARNING - Can't fetch recording due to no recording available.");
            return;      
        }

        setActiveToken($hash); 
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    } 

return;    
}

###############################################################################
#                     Kamera gemachte Aufnahme lokal speichern
###############################################################################
sub __getRecAndSave {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    
    return if(IsDisabled($name));
    return if(exitOnDis ($name, "Save Recording of Camera $camname in local file can't be executed"));    
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {              
        $hash->{OPMODE}               = "SaveRec"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "REC";
        my $recid                     = ReadingsVal("$name", "CamLastRecId", 0);
      
        if($recid) {
            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version="_VER_"&id=$recid&mountId=0&method="Download"&_sid="_SID_"};      
        } 
        else {
            Log3($name, 2, "$name - WARNING - Can't fetch recording due to no recording available.");
            return;      
        }

        setActiveToken($hash); 
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    } 

return;    
}

###############################################################################
#                       Start Object Tracking
###############################################################################
sub __startTrack {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    
    return if(IsDisabled($name));
    return if(exitOnDis ($name, "Object Tracking of Camera $camname can't switched on"));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {             
        $hash->{OPMODE}               = "startTrack"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "PTZ";
        $hash->{HELPER}{CALL}{PART}   = qq{api="_NAME_"&version="_VER_"&method="ObjTracking"&cameraId="_CID_"&_sid="_SID_"}; 
        
        setActiveToken($hash);
        checkSid      ($hash); 
    } 
    else {
        schedule ($name, $hash);
    } 

return;    
}

###############################################################################
#                       Stopp Object Tracking
###############################################################################
sub __stopTrack {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);

    return if(IsDisabled($name));
    return if(exitOnDis ($name, "Object Tracking of Camera $camname can't switched off"));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {             
        $hash->{OPMODE}               = "stopTrack"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "PTZ";
        $hash->{HELPER}{CALL}{PART}   = qq{api="_NAME_"&version="_VER_"&method="ObjTracking"&moveType="Stop"&cameraId="_CID_"&_sid="_SID_"};     
        
        setActiveToken($hash);
        checkSid      ($hash);    
    } 
    else {
        schedule ($name, $hash);
    } 

return;    
}

###############################################################################
#                 Zoom in / stop / out starten bzw. stoppen
#                              $op = + / stop / -
###############################################################################
sub __setZoom {
    my $str        = shift;
    my ($name,$op) = split("!_!",$str);
    my $hash       = $defs{$name};
    my $camname    = $hash->{CAMNAME};
    
    my $caller     = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);

    return if(IsDisabled($name));
    return if(exitOnDis ($name, "Zoom $op of Camera $camname can't be started"));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        $hash->{OPMODE}                 = "setZoom"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES}   = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $str);
            return;
        }
        
        $hash->{HELPER}{ZOOM}{DIR}      = $zd{$op}{dir} // $hash->{HELPER}{ZOOM}{DIR};     # Richtung (in / out)
        $hash->{HELPER}{ZOOM}{MOVETYPE} = $zd{$op}{moveType};                              # Start / Stop                               
        
        return if(!$hash->{HELPER}{ZOOM}{DIR});                                            # es muss ! eine Richtung gesetzt sein

        my $dir                     = $hash->{HELPER}{ZOOM}{DIR};
        my $moveType                = $hash->{HELPER}{ZOOM}{MOVETYPE};
      
        $hash->{HELPER}{CALL}{VKEY} = "PTZ";                                                                     
        $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version="_VER_"&method="Zoom"&cameraId="_CID_"&control="$dir"&moveType="$moveType"&_sid="_SID_"};
    
        if($hash->{HELPER}{ZOOM}{MOVETYPE} ne "Stop") {
            InternalTimer(gettimeofday()+$zd{$op}{sttime}, "FHEM::SSCam::__setZoom", "$name!_!stop", 0);
        }
        
        setActiveToken($hash);
        checkSid      ($hash); 
    } 
    else {
        schedule ($name, $str);
    }

return;    
}

###############################################################################
#                       einen Preset setzen
###############################################################################
sub __setPreset {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);

    return if(IsDisabled($name));
    return if(exitOnDis ($name, "Preset of Camera $camname can't be set"));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {             
        $hash->{OPMODE}               = "setPreset"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "PRESET";
        
        my $pnumber = $hash->{HELPER}{PNUMBER};
        my $pname   = $hash->{HELPER}{PNAME};
        my $pspeed  = $hash->{HELPER}{PSPEED};
      
        if ($pspeed) {
            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version="_VER_"&method="SetPreset"&position=$pnumber&name="$pname"&speed="$pspeed"&cameraId="_CID_"&_sid="_SID_"};                  
        } 
        else {    
            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version="_VER_"&method="SetPreset"&position=$pnumber&name="$pname"&cameraId="_CID_"&_sid="_SID_"};                          
        }
        
        setActiveToken($hash);
        checkSid      ($hash);    
    } 
    else {
        schedule ($name, $hash);
    } 

return;    
}

###############################################################################
#                       einen Preset löschen
###############################################################################
sub __delPreset {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    
    return if(IsDisabled($name));
    return if(exitOnDis ($name, "Preset of Camera $camname can't be deleted"));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {             
        $hash->{OPMODE}               = "delPreset"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        my $delp                      = $hash->{HELPER}{ALLPRESETS}{$hash->{HELPER}{DELPRESETNAME}};
        $hash->{HELPER}{CALL}{VKEY}   = "PRESET";
        $hash->{HELPER}{CALL}{PART}   = qq{api="_NAME_"&version="_VER_"&method="DelPreset"&position="$delp"&cameraId="_CID_"&_sid="_SID_"};
        
        setActiveToken($hash);
        checkSid      ($hash);  
    } 
    else {
        schedule ($name, $hash);
    }

return;    
}

###############################################################################
#                       Preset Home setzen
###############################################################################
sub __setHome {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    
    return if(IsDisabled($name));
    return if(exitOnDis ($name, "Home preset of Camera $camname can't be set"));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {             
        $hash->{OPMODE}               = "setHome"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "PRESET";
        
        if($hash->{HELPER}{SETHOME} eq "---currentPosition---") {
            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version="_VER_"&method="SetHome"&cameraId="_CID_"&_sid="_SID_"};        
        } 
        else {
            my $bindpos                 = $hash->{HELPER}{ALLPRESETS}{$hash->{HELPER}{SETHOME}}; 
            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version="_VER_"&method="SetHome"&bindPosition="$bindpos"&cameraId="_CID_"&_sid="_SID_"};      
        }
        
        setActiveToken($hash);
        checkSid      ($hash); 
    } 
    else {
        schedule ($name, $hash);
    } 

return;    
}

###########################################################################
#                                HomeMode setzen 
###########################################################################
sub __setHomeMode {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name) || !defined($hash->{HELPER}{API}{HMODE}{VER}));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE}               = "sethomemode"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        my $sw                        = $hash->{HELPER}{HOMEMODE};                 # HomeMode on,off
        $sw                           = ($sw eq "on") ? "true" : "false";
        $hash->{HELPER}{CALL}{VKEY}   = "HMODE";
        $hash->{HELPER}{CALL}{PART}   = qq{api="_NAME_"&version="_VER_"&method=Switch&on=$sw&_sid="_SID_"};
        
        setActiveToken($hash);
        checkSid      ($hash); 
    } 
    else {
        schedule ($name, $hash);
    }
    
return;
}

###########################################################################
#                         Optimierparameter setzen 
###########################################################################
sub __setOptParams {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE}               = "setoptpar"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        my $mirr                    = $hash->{HELPER}{MIRROR}  // ReadingsVal($name, "CamVideoMirror", "");
        my $flip                    = $hash->{HELPER}{FLIP}    // ReadingsVal($name, "CamVideoFlip",   "");
        my $rot                     = $hash->{HELPER}{ROTATE}  // ReadingsVal($name, "CamVideoRotate", "");
        my $ntp                     = $hash->{HELPER}{NTPSERV} // ReadingsVal($name, "CamNTPServer",   "");
      
        $ntp                        = q{} if($ntp eq "none");
        my $clst                    = $hash->{HELPER}{CHKLIST} // "";

        my $ver                     = $hash->{HELPER}{API}{CAM}{VER} >= 9 ? 8 : $hash->{HELPER}{API}{CAM}{VER};        
               
        $hash->{HELPER}{CALL}{VKEY} = "CAM";
        $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version="$ver"&method="SaveOptimizeParam"&vdoMirror=$mirr&vdoRotation=$rot&vdoFlip=$flip&timeServer="$ntp"&camParamChkList=$clst&cameraIds="_CID_"&_sid="_SID_"};  
        $hash->{HELPER}{CALL}{TO}   = 90;                                                # setzen Optimierungsparameter dauert lange !
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    }
    
return;
}

###############################################################################
#                       PIR Sensor aktivieren/deaktivieren
###############################################################################
sub __managePir {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    
    return if(IsDisabled($name));
    return if(exitOnDis ($name, "PIR of camera $camname cannot be managed"));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {             
        $hash->{OPMODE}               = "piract"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "CAMEVENT";
        my $piract                    = $hash->{HELPER}{PIRACT};
        $hash->{HELPER}{CALL}{PART}   = qq{api="_NAME_"&version="_VER_"&method="PDParamSave"&keep=true&source=$piract&camId="_CID_"&_sid="_SID_"};     
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    }

return;    
}

###############################################################################
#                         Kamera Liveview starten
###############################################################################
sub __runLiveview {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    
    return if(IsDisabled($name));
    return if(exitOnDis ($name, "Liveview of Camera $camname can't be started"));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {           
        $hash->{OPMODE}               = "runliveview"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0; 
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        delete $hash->{CAMID};                                                               # erzwingen die Camid zu ermitteln und bei login-Fehler neue SID zu holen
        
        readingsSingleUpdate($hash,"state","runView ".$hash->{HELPER}{RUNVIEW},1); 
        
        if ($hash->{HELPER}{RUNVIEW} =~ /snap/x) {                                           # den letzten Schnappschuß live anzeigen
            my $limit                   = 1;                                                 # nur 1 Snap laden, für lastsnap_fw 
            my $imgsize                 = 2;                                                 # full size image, für lastsnap_fw 
            my $keyword                 = $hash->{CAMNAME};                                  # nur Snaps von $camname selektieren, für lastsnap_fw   
            $hash->{HELPER}{CALL}{VKEY} = "SNAPSHOT";
            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version="_VER_"&method="List"&keyword="$keyword"&imgSize="$imgsize"&limit="$limit"&_sid="_SID_"};
        }
        
        if ($hash->{HELPER}{RUNVIEW} =~ m/^live_.*?hls$/x) {                                 # HLS Livestreaming aktivieren
            $hash->{HELPER}{CALL}{VKEY} = "VIDEOSTMS"; 
            $hash->{HELPER}{CALL}{TO}   = 90;                                                # aktivieren HLS dauert lange !
            $hash->{HELPER}{CALL}{PART} = qq{api=_NAME_&version=_VER_&method=Open&cameraId=_CID_&format=hls&_sid=_SID_};
        }
        
        if ($hash->{HELPER}{RUNVIEW} !~ m/snap|^live_.*hls$/x) {
            if ($hash->{HELPER}{RUNVIEW} =~ m/live/x) {
                if($hash->{HELPER}{API}{AUDIOSTM}{VER}) {                                    # Audio aktivieren                                       
                    $hash->{HELPER}{ACALL}{AKEY}  = "AUDIOSTM"; 
                    $hash->{HELPER}{ACALL}{APART} = qq{api=_ANAME_&version=_AVER_&method=Stream&cameraId=_CID_&_sid=_SID_}; 
                } 
                else {
                    delete $hash->{HELPER}{AUDIOLINK};
                }
                
                if($hash->{HELPER}{API}{VIDEOSTMS}{VER}) {                                   # API "SYNO.SurveillanceStation.VideoStream" vorhanden ? (removed ab API v2.8)
                    $hash->{HELPER}{CALL}{VKEY} = "VIDEOSTMS";
                    $hash->{HELPER}{CALL}{PART} = qq{api=_NAME_&version=_VER_&method=Stream&cameraId=_CID_&format=mjpeg&_sid=_SID_};
                }
            } 
            else {
                my $lrecid                  = ReadingsVal("$name", "CamLastRecId", 0); 
                $hash->{HELPER}{CALL}{VKEY} = "STM";
                $hash->{HELPER}{CALL}{PART} = qq{api=_NAME_&version=_VER_&method=EventStream&eventId=$lrecid&timestamp=1&_sid=_SID_};
            }
        }
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    } 

return;    
}

###############################################################################
#                         Kamera HLS-Stream aktivieren
###############################################################################
sub __activateHls {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    
    return if(IsDisabled($name));
    return if(exitOnDis ($name, "HLS-Stream of Camera $camname can't be activated"));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {            
        $hash->{OPMODE}               = "activate_hls"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;  

        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }       
        
        $hash->{HELPER}{CALL}{VKEY} = "VIDEOSTMS"; 
        $hash->{HELPER}{CALL}{TO}   = 90;                                                # aktivieren HLS dauert lange !
        $hash->{HELPER}{CALL}{PART} = qq{api=_NAME_&version=_VER_&method=Open&cameraId=_CID_&format=hls&_sid=_SID_};
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    }

return;    
}

###############################################################################
#               HLS-Stream reaktivieren (stoppen & starten)
###############################################################################
sub __reactivateHls {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    
    return if(IsDisabled($name));
    return if(exitOnDis ($name, "HLS-Stream of Camera $camname can't be reactivated"));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {             
        $hash->{OPMODE}               = "reactivate_hls"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }

        $hash->{HELPER}{CALL}{VKEY}   = "VIDEOSTMS";
        $hash->{HELPER}{CALL}{PART}   = qq{api=_NAME_&version=_VER_&method=Close&cameraId=_CID_&format=hls&_sid=_SID_};     
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    }  

return;    
}

###############################################################################
#                         Kameras mit Autocreate erstellen
###############################################################################
sub __camAutocreate {
    my $hash = shift;
    my $name = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    
    return if(IsDisabled($name));
    return if(exitOnDis ($name, "autocreate cameras not possible"));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {            
        $hash->{OPMODE}               = "Autocreate"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;  

        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }       
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    }

return;    
}

###############################################################################
#                         Kamera Liveview stoppen
###############################################################################
sub __stopLiveview {
    my $hash = shift;
    my $name = $hash->{NAME};
   
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {           
        $hash->{OPMODE}               = "stopliveview";
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        setActiveToken($hash);
        
        delete $hash->{HELPER}{LINK};                       # Link aus Helper-hash löschen
        delete $hash->{HELPER}{AUDIOLINK};
        delete $hash->{HELPER}{ACTSTRM};                    # sprechender Name des laufenden Streamtyps für SSCamSTRM
        
        delete($defs{$name}{READINGS}{LiveStreamUrl}) if ($defs{$name}{READINGS}{LiveStreamUrl});  # Reading LiveStreamUrl löschen
        
        readingsSingleUpdate($hash,"state","stopview",1);           
        
        if($hash->{HELPER}{WLTYPE} eq "hls") {              # HLS Stream war aktiv, Streaming beenden
            $hash->{OPMODE} = "stopliveview_hls"; 
            
            $hash->{HELPER}{CALL}{VKEY}   = "VIDEOSTMS";
            $hash->{HELPER}{CALL}{PART}   = qq{api=_NAME_&version=_VER_&method=Close&cameraId=_CID_&format=hls&_sid=_SID_}; 
            
            return if(startOrShut($name));
            checkSid ($hash);
        } 
        else {                                              # kein HLS Stream
            roomRefresh   ($hash,0,1,1);                    # kein Room-Refresh, SSCam-state-Event, SSCamSTRM-Event
            delActiveToken($hash);
        }
    } 
    else {
        schedule ($name, $hash);
    } 

return;    
}

###############################################################################
#                       external Event 1-10 auslösen
###############################################################################
sub __extEvent {
    my $hash = shift;
    my $name = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE}               = "extevent"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        my $evtid                     = $hash->{HELPER}{EVENTID};
        $hash->{HELPER}{CALL}{VKEY}   = "EXTEVT";
        $hash->{HELPER}{CALL}{PART}   = qq{api=_NAME_&version=_VER_&method=Trigger&eventId=$evtid&eventName=$evtid&_sid="_SID_"};       
        
        Log3($name, 4, "$name - trigger external event \"$evtid\"");
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    } 

return;    
}

###############################################################################
#                      PTZ-Kamera Aktion ausführen
###############################################################################
sub __doPtzAaction {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my ($errorcode,$error);
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));

    if (!IsCapPTZ($hash)) {
        Log3($name, 2, "$name - ERROR - Operation \"$hash->{HELPER}{PTZACTION}\" is only possible for cameras of DeviceType \"PTZ\" - please compare with device Readings");
        return;
    }
    if ($hash->{HELPER}{PTZACTION} eq "goabsptz" && !IsCapPTZAbs($hash)) {
        Log3($name, 2, "$name - ERROR - Operation \"$hash->{HELPER}{PTZACTION}\" is only possible if camera supports absolute PTZ action - please compare with Reading \"CapPTZAbs\"");
        return;
    }
    if ($hash->{HELPER}{PTZACTION} eq "movestart" && !IsCapPTZDir($hash)) {
        Log3($name, 2, "$name - ERROR - Operation \"$hash->{HELPER}{PTZACTION}\" is only possible if camera supports \"Tilt\" and \"Pan\" operations - please compare with device Reading \"CapPTZDirections\"");
        return;
    }
    
    return if(exitOnDis ($name, "$hash->{HELPER}{PTZACTION} of Camera $camname can't be executed"));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        if ($hash->{HELPER}{PTZACTION} eq "gopreset") {
            if (!defined($hash->{HELPER}{ALLPRESETS}{$hash->{HELPER}{GOPRESETNAME}})) {
                $errorcode = "600";
                $error     = expErrors($hash,$errorcode);                                    # Fehlertext zum Errorcode ermitteln
            
                readingsBeginUpdate ($hash);
                readingsBulkUpdate  ($hash, "Errorcode", $errorcode);
                readingsBulkUpdate  ($hash, "Error",     $error    );
                readingsEndUpdate   ($hash, 1);
        
                Log3($name, 2, "$name - ERROR - goPreset to position \"$hash->{HELPER}{GOPRESETNAME}\" of Camera $camname can't be executed - $error");
                return;        
            }
        }
        
        if ($hash->{HELPER}{PTZACTION} eq "runpatrol") {
            my $patid = $hash->{HELPER}{ALLPATROLS}{$hash->{HELPER}{GOPATROLNAME}};
            if (!defined $patid) {
                $errorcode = "600";
                $error     = expErrors($hash,$errorcode);                                             # Fehlertext zum Errorcode ermitteln
            
                readingsBeginUpdate ($hash);
                readingsBulkUpdate  ($hash, "Errorcode", $errorcode);
                readingsBulkUpdate  ($hash, "Error",     $error    );
                readingsEndUpdate   ($hash, 1);
        
                Log3($name, 2, "$name - ERROR - runPatrol to patrol \"$hash->{HELPER}{GOPATROLNAME}\" of Camera $camname can't be executed - $error");
                return;        
            }
            
            $hash->{HELPER}{CALL}{VKEY} = "PTZ";
            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version="_VER_"&method="RunPatrol"&patrolId="$patid"&cameraId="_CID_"&_sid="_SID_"};

            Log3($name, 4, "$name - Start patrol \"$hash->{HELPER}{GOPATROLNAME}\" with ID \"$hash->{HELPER}{ALLPATROLS}{$hash->{HELPER}{GOPATROLNAME}}\" of Camera $camname now");
        }
        
        if ($hash->{HELPER}{PTZACTION} eq "gopreset") {
            $hash->{HELPER}{CALL}{VKEY} = "PTZ";
            my $ver                     = ($hash->{HELPER}{API}{PTZ}{VER} >= 5) ? 4 : $hash->{HELPER}{API}{PTZ}{VER};
            my $posid                   = $hash->{HELPER}{ALLPRESETS}{$hash->{HELPER}{GOPRESETNAME}};
            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version="$ver"&method="GoPreset"&position="$posid"&cameraId="_CID_"&_sid="_SID_"};

            Log3($name, 4, "$name - Move Camera $camname to position \"$hash->{HELPER}{GOPRESETNAME}\" with ID \"$posid\" now");
        }
        
        if ($hash->{HELPER}{PTZACTION} eq "goabsptz") {
            my $posx                    = $hash->{HELPER}{GOPTZPOSX};
            my $posy                    = $hash->{HELPER}{GOPTZPOSY};
            $hash->{HELPER}{CALL}{VKEY} = "PTZ";
            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version="_VER_"&method="AbsPtz"&cameraId="_CID_"&posX="$posx"&posY="$posy"&_sid="_SID_"};
        
            Log3($name, 4, "$name - Start move Camera $camname to position posX=\"$hash->{HELPER}{GOPTZPOSX}\" and posY=\"$hash->{HELPER}{GOPTZPOSY}\" now");
        } 
        
        if ($hash->{HELPER}{PTZACTION} eq "movestart") {
            my $mdir                    = $hash->{HELPER}{GOMOVEDIR};
            $hash->{HELPER}{CALL}{VKEY} = "PTZ";
            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version="_VER_"&method="Move"&cameraId="_CID_"&direction="$mdir"&speed="3"&moveType="Start"&_sid="_SID_"};

            Log3($name, 4, "$name - Start move Camera $camname to direction \"$hash->{HELPER}{GOMOVEDIR}\" with duration of $hash->{HELPER}{GOMOVETIME} s");
        }
     
        $hash->{OPMODE}               = $hash->{HELPER}{PTZACTION}; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    } 

return;    
}

###############################################################################
#                         stoppen continued move
###############################################################################
sub __moveStop {                                        ## no critic "not used"
    my $hash = shift;
    my $name = $hash->{NAME};
    
    my $caller = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE}               = "movestop"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        my $mdir                      = $hash->{HELPER}{GOMOVEDIR};
        $hash->{HELPER}{CALL}{VKEY}   = "PTZ";
        $hash->{HELPER}{CALL}{PART}   = qq{api="_NAME_"&version="_VER_"&method="Move"&cameraId="_CID_"&direction="$mdir"&moveType="Stop"&_sid="_SID_"};
        
        Log3($name, 4, "$name - Stop Camera $hash->{CAMNAME} moving to direction \"$hash->{HELPER}{GOMOVEDIR}\" now");
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    }

return;    
}

###############################################################################
#                           Kamera aktivieren
###############################################################################
sub __camEnable {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE}               = "Enable"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "CAM";
        $hash->{HELPER}{CALL}{PART}   = qq{api=_NAME_&version=_VER_&method=Enable&cameraIds=_CID_&_sid="_SID_"};     
        
        if($hash->{HELPER}{API}{CAM}{VER} >= 9) {
            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version=_VER_&method="Enable"&idList="_CID_"&_sid="_SID_"};     
        }
        
        Log3($name, 4, "$name - Enable Camera $camname");
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    } 

return;    
}

###############################################################################
#                            Kamera deaktivieren
###############################################################################
sub __camDisable {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off" and ReadingsVal("$name", "Record", "Start") ne "Start") {                       
        $hash->{OPMODE}               = "Disable"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "CAM";
        $hash->{HELPER}{CALL}{TO}     = 90;                                                # Disable dauert lange !
        $hash->{HELPER}{CALL}{PART}   = qq{api=_NAME_&version=_VER_&method=Disable&cameraIds=_CID_&_sid="_SID_"};     
        
        if($hash->{HELPER}{API}{CAM}{VER} >= 9) {
            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version=_VER_&method="Disable"&idList="_CID_"&_sid="_SID_"};     
        }
        
        Log3($name, 4, "$name - Disable Camera $camname");
        
        setActiveToken($hash);
        checkSid      ($hash); 
    } 
    else {
        schedule ($name, $hash);
    } 

return;    
}

################################################################
#                           Get
################################################################
sub Get {
    my ($hash, @a) = @_;
    return "\"get X\" needs at least an argument" if ( @a < 2 );
    my $name = shift @a;
    my $opt  = shift @a;
    my $arg  = shift @a;
    my $arg1 = shift @a;
    my $arg2 = shift @a;
    
    my $getlist = "Unknown argument $opt, choose one of ";

    if(!$hash->{CREDENTIALS}) {
        return;  
    } 
    elsif(IsModelCam($hash)) {                                                        # getlist für Cams
        $getlist .= "caminfo:noArg ".
                    ((AttrVal($name,"snapGalleryNumber",undef) || AttrVal($name,"snapGalleryBoost",0))
                       ? "snapGallery:noArg " : "snapGallery:$defSnum ").
                    (IsCapPTZPan($hash) ? "listPresets:noArg " : "").
                    "snapinfo:noArg ".
                    "saveRecording ".
                    "saveLastSnap ".
                    "snapfileinfo:noArg ".
                    "eventlist:noArg ".
                    "stmUrlPath:noArg " 
                    ;
    } 
    else {                                                                           # getlist für SVS Devices
        $getlist .= ($hash->{HELPER}{API}{HMODE}{VER}?"homeModeState:noArg ": "").
                    "listLog "
                    ;
    }
    
    $getlist .= "caminfoall:noArg ".                                                 # Ergänzend für beiden Device Typen
                "svsinfo:noArg ".
                "scanVirgin:noArg ".
                "storedCredentials:noArg ".
                "versionNotes ".
                "apiInfo:noArg "
                ;
                  
    return if(IsDisabled($name)); 

    my $params = {
        hash  => $hash,
        name  => $name,
        opt   => $opt,
        arg   => $arg,
        arg1  => $arg1,
        arg2  => $arg2,
    };
  
    no strict "refs";                                                        ## no critic 'NoStrict'  
    if($hget{$opt} && defined &{$hget{$opt}{fn}}) {
        my $ret = q{};
      
        if (!$hash->{CREDENTIALS} && $hget{$opt}{needcred}) {                
            return qq{Credentials of $name are not set. Make sure they are set with "set $name credentials <username> <password>"};
        }
  
        $ret = &{$hget{$opt}{fn}} ($params);
      
        return $ret;
    }
    use strict "refs";     
        
return $getlist;
}

################################################################
#        Getter apiInfo - Anzeige die API Infos in Popup
################################################################
sub _getapiInfo {                        ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  getClHash   ($hash,1);
  __getApiInfo($hash);
        
return;
}

################################################################
#                      Getter caminfo
################################################################
sub _getcaminfo {                        ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  __getCamInfo($hash);
        
return;
}

################################################################
#                      Getter caminfoall
################################################################
sub _getcaminfoall {                     ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  __getCaminfoAll($hash,1);                                 # "1" ist Statusbit für manuelle Abfrage, kein Einstieg in Pollingroutine
        
return;
}

################################################################
#                      Getter homeModeState
################################################################
sub _gethomeModeState {                  ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  return if(IsModelCam($hash));
  
  __getHomeModeState($hash);
        
return;
}

################################################################
#                      Getter listLog
################################################################
sub _getlistLog {                        ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $arg   = $paref->{arg};
  my $arg1  = $paref->{arg1};
  my $arg2  = $paref->{arg2};
  
  return if(IsModelCam($hash));
  
  getClHash($hash,1);                                     # übergebenen CL-Hash (FHEMWEB) in Helper eintragen
    
  extlogargs($hash, $arg)  if($arg);
  extlogargs($hash, $arg1) if($arg1);
  extlogargs($hash, $arg2) if($arg2);

  __getSvsLog ($hash);
        
return;
}

################################################################
#                      Getter listPresets
################################################################
sub _getlistPresets {                    ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  return if(!IsModelCam($hash));
  
  getClHash   ($hash,1);                                 # übergebenen CL-Hash (FHEMWEB) in Helper eintragen 
  __getPresets($hash);
        
return;
}

################################################################
#                      Getter saveRecording
################################################################
sub _getsaveRecording {                  ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $arg   = $paref->{arg};
  
  return if(!IsModelCam($hash));
  
  $hash->{HELPER}{RECSAVEPATH} = $arg if($arg);
  __getRecAndSave($hash);
        
return;
}

################################################################
#                      Getter saveLastSnap
#                Letzten Snap in File speichern
################################################################
sub _getsaveLastSnap {                   ## no critic 'not used'                 
  my $paref = shift;
  my $hash  = $paref->{hash}; 
  my $name  = $paref->{name};
  my $path  = $paref->{arg} // $attr{global}{modpath};
  
  return if(!IsModelCam($hash));
  
  my ($imgdata,$err);
   
  my $cache = cache($name, "c_init");                                                            # Cache initialisieren  
  Log3($name, 1, "$name - Fall back to internal Cache due to preceding failure") if(!$cache);                                 
  
  if(!$cache || $cache eq "internal" ) {
      $imgdata = $data{SSCam}{$name}{LASTSNAP};
  } 
  else {
      $imgdata = cache($name, "c_read", "{LASTSNAP}");                           
  }
  
  if(!$imgdata) {
      Log3($name, 2, "$name - No image data available to save locally")
  }
  
  my $fname = ReadingsVal($name, "LastSnapFilename", "");
  my $file  = $path."/$fname";

  open my $fh, '>', $file or do { $err = qq{Can't open file "$file": $!};
                                  Log3($name, 2, "$name - $err");
                                };       

  if(!$err) {
      $err = "none";      
      binmode $fh;
      print $fh MIME::Base64::decode_base64($imgdata);
      close($fh);
      Log3($name, 3, qq{$name - Last Snapshot was saved to local file "$file"});
  }

  readingsBeginUpdate ($hash);
  readingsBulkUpdate  ($hash, "Errorcode", "none");
  readingsBulkUpdate  ($hash, "Error",     $err  );
  readingsEndUpdate   ($hash, 1);
  
return;
}

################################################################
#                      Getter svsinfo
################################################################
sub _getsvsinfo {                        ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  __getSvsInfo($hash);
        
return;
}

################################################################
#                      Getter storedCredentials
################################################################
sub _getstoredCredentials {              ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  my $out = showStoredCredentials ($hash, 3);
  
return $out;
}

################################################################
#                      Getter snapGallery
################################################################
sub _getsnapGallery {                    ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $arg   = $paref->{arg};
  
  return if(!IsModelCam($hash));
  
  my $ret = getClHash($hash);
  return $ret if($ret);

  if(!AttrVal($name, "snapGalleryBoost",0)) {                                                  # Snaphash ist nicht vorhanden und wird abgerufen       
      $hash->{HELPER}{GETSNAPGALLERY} = 1;
                                                                                
      my $slim  = $arg // AttrVal($name,"snapGalleryNumber",$defSlim);                         # Anzahl der abzurufenden Snapshots
      my $ssize = (AttrVal($name,"snapGallerySize","Icon") eq "Icon") ? 1 : 2;                 # Image Size 1-Icon, 2-Full
      
      __getSnapInfo("$name:$slim:$ssize");
  } 
  else {                                                                                       # Snaphash ist vorhanden und wird zur Ausgabe aufbereitet
      $hash->{HELPER}{SNAPLIMIT} = AttrVal($name,"snapGalleryNumber",$defSlim);
      
      my %pars = ( linkparent => $name,
                   linkname   => '',
                   ftui       => 0
                 );
      
      my $htmlCode = composeGallery(\%pars);
      
      for (my $k=1; (defined($hash->{HELPER}{CL}{$k})); $k++ ) {
          if ($hash->{HELPER}{CL}{$k}->{COMP}) {                                               # CL zusammengestellt (Auslösung durch Notify)
              asyncOutput($hash->{HELPER}{CL}{$k}, "$htmlCode");                      
          } 
          else {                                                                               # Output wurde über FHEMWEB ausgelöst
              return $htmlCode;
          }
      }
      
      delClHash  ($name);
  }
        
return;
}

################################################################
#                      Getter snapinfo
# Schnappschußgalerie abrufen oder nur Info des letzten Snaps
################################################################
sub _getsnapinfo {                       ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  
  return if(!IsModelCam($hash));
  
  my ($slim,$ssize) = snapLimSize($hash,1);        # Force-Bit, es wird $hash->{HELPER}{GETSNAPGALLERY} gesetzt !
  __getSnapInfo("$name:$slim:$ssize");
        
return;
}

################################################################
#                      Getter snapfileinfo
################################################################
sub _getsnapfileinfo {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  
  return if(!IsModelCam($hash));
  
  if (!ReadingsVal($name, "LastSnapId", undef)) {
      return "Reading LastSnapId is empty - please take a snapshot before !"
  }
  
  __getSnapFilename($hash);
        
return;
}

################################################################
#                      Getter eventlist
################################################################
sub _geteventlist {                      ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  return if(!IsModelCam($hash));
  
  __getEventList($hash);
        
return;
}

################################################################
#                      Getter stmUrlPath
################################################################
sub _getstmUrlPath {                      ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  
  return if(!IsModelCam($hash));
  
  __getStmUrlPath($hash);
        
return;
}

################################################################
#                      Getter scanVirgin
################################################################
sub _getscanVirgin {                     ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  
  __sessionOff($hash);
  
  delete $hash->{HELPER}{API}{PARSET};
  delete $hash->{CAMID};

  my @allrds = keys%{$defs{$name}{READINGS}};
  for my $key(@allrds) {                                           # vorhandene Readings außer "state" löschen
      delete($defs{$name}{READINGS}{$key}) if($key ne "state");
  }

  __getCaminfoAll($hash,1);                                        # "1" ist Statusbit für manuelle Abfrage, kein Einstieg in Pollingroutine
    
return;
}

################################################################
#                      Getter versionNotes
################################################################
sub _getversionNotes {                   ## no critic "not used"
  my $paref = shift;
  
  $paref->{hintextde} = \%vHintsExt_de;
  $paref->{hintexten} = \%vHintsExt_en;
  $paref->{notesext}  = \%vNotesExtern;
  
  my $ret = showModuleInfo ($paref);
                    
return $ret; 
}

###########################################################################
#              API Infos abfragen und in einem Popup anzeigen
###########################################################################
sub __getApiInfo {
    my $hash   = shift;
    my $name   = $hash->{NAME};
    
    my $caller = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE} = "apiInfo"; 
        
        return if(startOrShut($name));
        
        $hash->{HELPER}{API}{PARSET} = 0;                                                   # Abruf API Infos erzwingen
        
        setActiveToken ($hash);
        getApiSites    ($hash, "", $hash);       
    } 
    else {
        schedule ($name, $hash);
    }
    
return;
}

###########################################################################
#               Kamera allgemeine Informationen abrufen (Get) 
###########################################################################
sub __getCamInfo {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));

    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE}               = "Getcaminfo"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;

        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }

        $hash->{HELPER}{CALL}{VKEY}   = "CAM";
        my $ver                       = ($hash->{HELPER}{API}{CAM}{VER} >= 9) ? 8 : $hash->{HELPER}{API}{CAM}{VER};
        $hash->{HELPER}{CALL}{PART}   = qq{api="_NAME_"&version="$ver"&method="GetInfo"&cameraIds="_CID_"&deviceOutCap="true"&streamInfo="true"&ptz="true"&basic="true"&camAppInfo="true"&optimize="true"&fisheye="true"&eventDetection="true"&_sid="_SID_"};            
        
        setActiveToken($hash); 
        checkSid      ($hash); 
    } 
    else {
        schedule ($name, $hash);
    } 
    
return;
}

###############################################################################
#      Kamera alle Informationen abrufen (Get) bzw. Einstieg Polling
###############################################################################
sub __getCaminfoAll {
    my $hash    = shift;
    my $mode    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));

    if(IsModelCam($hash)) {                                                               # Model ist CAM
        __getCapabilities ($hash);
        __getEventList    ($hash);
        __getMotionEnum   ($hash);
        __getCamInfo      ($hash);
        __getStreamFormat ($hash);
        __getStmUrlPath   ($hash);
        
        my ($slim,$ssize) = snapLimSize($hash,1);                                         
        __getSnapInfo     ("$name:$slim:$ssize");                                         # Schnappschußgalerie abrufen (snapGalleryBoost) oder nur Info des letzten Snaps, Force-Bit -> es wird $hash->{HELPER}{GETSNAPGALLERY} erzwungen !
    } 
    else {                                                                                # Model ist SVS
        __getHomeModeState ($hash);
        __getSvsLog        ($hash);
    }
    
    __getSvsInfo ($hash);
    
    # wenn gesetzt = manuelle Abfrage
    # return if ($mode);                # 24.03.2018 geänd.
    
    my $pcia = AttrVal($name,"pollcaminfoall",0);
    my $pnl  = AttrVal($name,"pollnologging",0);
    if ($pcia) {        
        my $new = gettimeofday()+$pcia; 
        InternalTimer($new, $caller, $hash, 0);
        
        my $now = FmtTime(gettimeofday());
        $new    = FmtTime(gettimeofday()+$pcia);
        readingsSingleUpdate($hash, "state",     "polling",                  1) if(!IsModelCam($hash));  # state für SVS-Device setzen
        readingsSingleUpdate($hash, "PollState", "Active - next time: $new", 1);  
        
        if (!$pnl) {
            Log3($name, 3, "$name - Polling now: $now , next Polling: $new");
        }
    } 
    else {                                                                                               # Beenden Polling aller Caminfos
        readingsSingleUpdate($hash, "PollState", "Inactive",   1);
        readingsSingleUpdate($hash, "state",     "initialized",1) if(!IsModelCam($hash));                # state für SVS-Device setzen
        
        Log3($name, 3, "$name - Polling of $camname is deactivated");
    }
    
return;
}

###########################################################################
#                         HomeMode Status abfragen
###########################################################################
sub __getHomeModeState {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name) || !defined($hash->{HELPER}{API}{HMODE}{VER}));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE}               = "gethomemodestate"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "HMODE";
        $hash->{HELPER}{CALL}{PART}   = qq{api="_NAME_"&version="_VER_"&method=GetInfo&_sid="_SID_"};
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    }
    
return;
}

###########################################################################
#                         SVS Log abrufen
###########################################################################
sub __getSvsLog {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE}               = "getsvslog"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        my $sev                       = delete $hash->{HELPER}{LISTLOGSEVERITY} // "";
        my $lim                       = delete $hash->{HELPER}{LISTLOGLIMIT}    // 0;
        my $mco                       = delete $hash->{HELPER}{LISTLOGMATCH}    // "";
        $lim                          = 1 if(!$hash->{HELPER}{CL}{1});                                   # Datenabruf im Hintergrund
        $mco                          = IsModelCam($hash) ? $hash->{CAMNAME} : $mco;
        $sev                          = (lc($sev) =~ /error/x) ? 3 :(lc($sev) =~ /warning/x) ? 2 :(lc($sev) =~ /info/x) ? 1 : "";
        
        $hash->{HELPER}{CALL}{VKEY}   = "LOG";
        $hash->{HELPER}{CALL}{PART}   = qq{api=_NAME_&version="2"&method="List"&time2String="no"&level="$sev"&limit="$lim"&keyword="$mco"&_sid="_SID_"};
        
        Log3($name,4, "$name - get logList with params: severity => $sev, limit => $lim, matchcode => $mco");
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    }
    
return;
}

###########################################################################
#       allgemeine Infos über Synology Surveillance Station
###########################################################################
sub __getSvsInfo {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE}               = "getsvsinfo"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "SVSINFO";
        $hash->{HELPER}{CALL}{PART}   = qq{api="_NAME_"&version="_VER_"&method="GetInfo"&_sid="_SID_"};
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    }
    
return;
}

###########################################################################
#  Infos zu Snaps abfragen (z.B. weil nicht über SSCam ausgelöst)
#
#  $slim  = Anzahl der abzurufenden Snapinfos (snaps)
#  $ssize = Snapgröße
#  $tac   = Transaktionscode (für gemeinsamen Versand)
###########################################################################
sub __getSnapInfo {
    my $str                      = shift;
    my ($name,$slim,$ssize,$tac) = split(":",$str);
    my $hash                     = $defs{$name};
    my $camname                  = $hash->{CAMNAME};
    
    $tac       = $tac // 5000;
    my $ta     = $hash->{HELPER}{TRANSACTION};
    my $caller = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off" || ((defined $ta) && $ta == $tac)) {               
        $hash->{OPMODE}               = "getsnapinfo";
        $hash->{OPMODE}               = "getsnapgallery" if(exists($hash->{HELPER}{GETSNAPGALLERY}));
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $str);
            return;
        }
        
        my $limit                  = $slim;                                          # 0-alle Snapshots werden abgerufen und ausgewertet, sonst $slim
        $hash->{HELPER}{SNAPLIMIT} = $slim;
        
        my $imgsize = $ssize;                                                        # 0-Do not append image, 1-Icon size, 2-Full size
        my $keyword = $camname;
        my $snapid  = ReadingsVal("$name", "LastSnapId", " ");       
               
        $hash->{HELPER}{CALL}{VKEY} = "SNAPSHOT";
        
        if($hash->{OPMODE} eq "getsnapinfo" && $snapid =~/\d+/x) {                   # getsnapinfo UND Reading LastSnapId gesetzt
            Log3($name,4, "$name - Call getsnapinfo with params: Image numbers => $limit, Image size => $imgsize, Id => $snapid");
            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version="_VER_"&method="List"&idList="$snapid"&imgSize="$imgsize"&limit="$limit"&_sid="_SID_"};      
        } 
        else {                                                                       # snapgallery oder kein Reading LastSnapId gesetzt
            Log3($name,4, "$name - Call getsnapinfo with params: Image numbers => $limit, Image size => $imgsize, Keyword => $keyword");
            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version="_VER_"&method="List"&keyword="$keyword"&imgSize="$imgsize"&limit="$limit"&_sid="_SID_"};
        }
        
        setActiveToken($hash);
        checkSid      ($hash);    
    } 
    else {
        schedule ($name, $str);
    }
    
return;
}

###############################################################################
#                       Liste der Presets abrufen
###############################################################################
sub __getPresets {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);

    return if(IsDisabled($name));
    return if(exitOnDis ($name, "Preset list of Camera $camname can't be get"));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {             
        $hash->{OPMODE}               = "getPresets"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "PRESET";
        $hash->{HELPER}{CALL}{PART}   = qq{api="_NAME_"&version="_VER_"&method="Enum"&cameraId="_CID_"&_sid="_SID_"}; 
           
        setActiveToken($hash);
        checkSid      ($hash); 
    } 
    else {
        schedule ($name, $hash);
    }  

return;    
}

###############################################################################
#        der Filename der aktuellen Schnappschuß-ID wird ermittelt
###############################################################################
sub __getSnapFilename {
    my $hash = shift;
    my $name = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {    
        $hash->{OPMODE}               = "getsnapfilename"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        my $snapid = ReadingsVal("$name", "LastSnapId", "");
        Log3($name, 4, "$name - Get filename of present Snap-ID $snapid");
        
        $hash->{HELPER}{CALL}{VKEY}   = "SNAPSHOT";
        $hash->{HELPER}{CALL}{PART}   = qq{api="_NAME_"&version="_VER_"&method="List"&imgSize="0"&idList="$snapid"&_sid="_SID_"};
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    } 

return;    
}

################################################################################
#                      Kamera Stream Urls abrufen (Get)
################################################################################
sub __getStmUrlPath {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {            
        $hash->{OPMODE}               = "getStmUrlPath"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "CAM";
        $hash->{HELPER}{CALL}{PART}   = qq{api="_NAME_"&version="_VER_"&method="GetStmUrlPath"&cameraIds="_CID_"&_sid="_SID_"};
      
        if($hash->{HELPER}{API}{CAM}{VER} >= 9) {
            $hash->{HELPER}{CALL}{PART} = qq{api="_NAME_"&version=_VER_&method="GetLiveViewPath"&idList="_CID_"&_sid="_SID_"};   
        }
        
        setActiveToken($hash);
        checkSid      ($hash);  
    } 
    else {
        schedule ($name, $hash);
    }
    
return;
}

###########################################################################
#                         query SVS-Event information 
#                        Abruf der Events einer Kamera
###########################################################################
sub __getEventList {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {      
        $hash->{OPMODE}               = "geteventlist"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "EVENT";
        $hash->{HELPER}{CALL}{PART}   = qq{api="_NAME_"&version="_VER_"&method="List"&cameraIds="_CID_"&locked="0"&blIncludeSnapshot="false"&reason=""&limit="2"&includeAllCam="false"&_sid="_SID_"};       
        
        setActiveToken($hash);
        checkSid      ($hash);   
    } 
    else {
        schedule ($name, $hash);
    }

return;    
}

##########################################################################
#             Capabilities von Kamera abrufen (Get)
##########################################################################
sub __getCapabilities {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        $hash->{OPMODE}               = "Getcapabilities";        
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "CAM";
        my $ver                       = ($hash->{HELPER}{API}{CAM}{VER} >= 9) ? 8 : $hash->{HELPER}{API}{CAM}{VER};
        $hash->{HELPER}{CALL}{PART}   = qq{api=_NAME_&version=$ver&method="GetCapabilityByCamId"&cameraId=_CID_&_sid="_SID_"};
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    }
    
return;
}

###########################################################################
#   SYNO.SurveillanceStation.VideoStream query aktuelles Streamformat 
###########################################################################
sub __getStreamFormat {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));  
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE}               = "getstreamformat"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "VIDEOSTMS";
        $hash->{HELPER}{CALL}{PART}   = qq{api=_NAME_&version=_VER_&method=Query&cameraId=_CID_&_sid=_SID_};
        
        setActiveToken($hash); 
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    } 
    
return;
}

###########################################################################
#               Enumerate motion detection parameters
###########################################################################
sub __getMotionEnum {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {   
        $hash->{OPMODE}               = "getmotionenum"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "CAMEVENT";
        $hash->{HELPER}{CALL}{PART}   = qq{api="_NAME_"&version="_VER_"&method="MotionEnum"&camId="_CID_"&_sid="_SID_"};
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    }
   
return;   
}

##########################################################################
#                      PTZ Presets abrufen (Get)
##########################################################################
sub __getPtzPresetList {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));
    
    if(!IsCapPTZ($hash)) {
        Log3($name, 4, "$name - Retrieval of Presets for $camname can't be executed - $camname is not a PTZ-Camera");
        return;
    }
    if(!IsCapPTZTilt($hash) | !IsCapPTZPan($hash)) {
        Log3($name, 4, "$name - Retrieval of Presets for $camname can't be executed - $camname has no capability to tilt/pan");
        return;
    }
    
    if($hash->{HELPER}{ACTIVE} eq "off") {                       
        $hash->{OPMODE}               = "Getptzlistpreset"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "PTZ";
        $hash->{HELPER}{CALL}{PART}   = qq{api="_NAME_"&version="_VER_"&method=ListPreset&cameraId=_CID_&_sid="_SID_"};
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    }
    
return;
}

##########################################################################
#                    PTZ Patrols abrufen (Get)
##########################################################################
sub __getPtzPatrolList {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));
    
    if(!IsCapPTZ($hash)) {
        Log3($name, 4, "$name - Retrieval of Patrols for $camname can't be executed - $camname is not a PTZ-Camera");
        return;
    }
    if(!IsCapPTZTilt($hash) | !IsCapPTZPan($hash)) {
        Log3($name, 4, "$name - Retrieval of Patrols for $camname can't be executed - $camname has no capability to tilt/pan");
        return;
    }

    if($hash->{HELPER}{ACTIVE} ne "on") {                        
        $hash->{OPMODE}               = "Getptzlistpatrol"; 
        return if(startOrShut($name));
        $hash->{HELPER}{LOGINRETRIES} = 0;
        
        if (!$hash->{HELPER}{API}{PARSET}) {
            getApiSites ($hash, $caller, $hash);
            return;
        }
        
        $hash->{HELPER}{CALL}{VKEY}   = "PTZ";
        $hash->{HELPER}{CALL}{PART}   = qq{api=_NAME_&version=_VER_&method=ListPatrol&cameraId=_CID_&_sid="_SID_"};
        
        setActiveToken($hash);
        checkSid      ($hash);
    } 
    else {
        schedule ($name, $hash);
    }
    
return;
}

###########################################################################
#                           Session logout
###########################################################################
sub __sessionOff {
    my $hash    = shift;
    my $camname = $hash->{CAMNAME};
    my $name    = $hash->{NAME};
    
    my $caller  = (caller(0))[3];
    
    RemoveInternalTimer($hash, $caller);
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE} = "logout"; 
        
        setActiveToken($hash);
   
        logout ($hash, $hash->{HELPER}{API});
    } 
    else {
        schedule ($name, $hash);
    }
    
return;
}

##################################################################################
#                           API-Pfade und Versionen ermitteln 
##################################################################################
sub getApiSites {
   my $hash        = shift;
   my $fret        = shift // "";
   my $arg         = shift // "";
   
   my $serveraddr  = $hash->{SERVERADDR};
   my $serverport  = $hash->{SERVERPORT};
   my $name        = $hash->{NAME};
   my $proto       = $hash->{PROTOCOL};   
   
   my ($url,$param);
   
   if($fret) {                                                                           # Activetoken setzen wenn Caller angegeben
       setActiveToken($hash);
   }

   Log3($name, 4, "$name - --- Start getApiSites ---");
   
   if ($hash->{HELPER}{API}{PARSET}) {                                                   # API-Hashwerte sind bereits gesetzt -> Abruf überspringen
       Log3($name, 4, "$name - API hashvalues already set - ignore get apisites");
       checkSid($hash);
       return;
   }

   my $httptimeout = AttrVal($name, "httptimeout", $todef);
   Log3($name, 5, "$name - HTTP-Call will be done with httptimeout-Value: $httptimeout s");

   # API initialisieren und abrufen
   ####################################
   $hash->{HELPER}{API} = apistatic ("surveillance");                                    # API Template im HELPER instanziieren

   Log3 ($name, 4, "$name - API imported:\n".Dumper $hash->{HELPER}{API});
     
   my @ak;
   for my $key (keys %{$hash->{HELPER}{API}}) {
       next if($key =~ /^PARSET$/x);  
       push @ak, $hash->{HELPER}{API}{$key}{NAME};
   }
   my $apis = join ",", @ak;
   
   $url = "$proto://$serveraddr:$serverport/webapi/$hash->{HELPER}{API}{INFO}{PATH}?".
              "api=$hash->{HELPER}{API}{INFO}{NAME}".
              "&method=Query".
              "&version=$hash->{HELPER}{API}{INFO}{VER}".
              "&query=$apis";

   Log3($name, 4, "$name - Call-Out now: $url");
   
   $param = {
       url      => $url,
       timeout  => $httptimeout,
       hash     => $hash,
       fret     => $fret,
       arg      => $arg,
       method   => "GET",
       header   => "Accept: application/json",
       callback => \&getApiSites_Parse
   };
   HttpUtils_NonblockingGet ($param);  
   
return;
} 

####################################################################################  
#                       Auswertung Abruf apisites
####################################################################################
sub getApiSites_Parse {
    my $param  = shift;
    my $err    = shift;
    my $myjson = shift;
   
    my $hash   = $param->{hash};
    my $fret   = $param->{fret};
    my $arg    = $param->{arg};
    my $name   = $hash->{NAME};
    my $opmode = $hash->{OPMODE};
   
    my ($error,$errorcode,$success);
  
    if ($err ne "") {                                                               # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
        Log3($name, 2, "$name - error while requesting ".$param->{url}." - $err");
       
        readingsSingleUpdate($hash, "Error", $err, 1);

        delActiveToken($hash);                                                      # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
        return;
        
    } elsif ($myjson ne "") {                                                       # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($success) = evaljson($hash,$myjson);
        
        if(!$success) {
            delActiveToken($hash);
            return;
        }
        
        my $jdata = decode_json($myjson);
        $success = $jdata->{success};
        
        Log3($name, 5, "$name - JSON returned: ". Dumper $jdata);                    # Logausgabe decodierte JSON Daten
    
        if ($success) {                                       
            my $completed = completeAPI ($jdata, $hash->{HELPER}{API});              # übergibt Referenz zum instanziierten API-Hash
         
            if(!$completed) {
                $errorcode = "9001";
                $error     = expErrors($hash,$errorcode);                            # Fehlertext zum Errorcode ermitteln
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate ($hash, "Errorcode", $errorcode);
                readingsBulkUpdate ($hash, "Error",     $error    );
                readingsEndUpdate  ($hash, 1);
            
                Log3($name, 2, "$name - ERROR - $error");                    
                  
                delActiveToken($hash);                                               # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
                return;               
            }
            
            # aktuelle oder simulierte SVS-Version für Fallentscheidung setzen
            my $major = $hash->{HELPER}{SVSVERSION}{MAJOR} // "";
            my $minor = $hash->{HELPER}{SVSVERSION}{MINOR} // "";
            my $small = $hash->{HELPER}{SVSVERSION}{SMALL} // "";
            my $build = $hash->{HELPER}{SVSVERSION}{BUILD} // "";
            my $actvs = $major.$minor.$small.$build;
            
            Log3($name, 4, "$name - installed SVS version is: $actvs"); 
                        
            if(AttrVal($name,"simu_SVSversion",0)) {
                my @vl  = split (/\.|-/x,AttrVal($name, "simu_SVSversion", ""));
                $actvs  = $vl[0];
                $actvs .= $vl[1];
                $actvs .= ($vl[2] =~ /\d/x) ? $vl[2]."xxxx" : $vl[2];
                $actvs .= "-simu";
            }
            
            # Downgrades für nicht kompatible API-Versionen. Hier nur nutzen wenn API zentral downgraded werden soll            
            Log3($name, 4, "$name - ------- Begin of adaption section -------");
            
            my @sims;
            
            # push @sims, "CAM:8";
            # push @sims, "PTZ:4";
            
            for my $esim (@sims) {
                my($k,$v) = split ":", $esim;
                $hash->{HELPER}{API}{$k}{VER} = $v;
                $hash->{HELPER}{API}{$k}{MOD} = "yes";
                Log3($name, 4, "$name - Version of $hash->{HELPER}{API}{$k}{NAME} adapted to: $hash->{HELPER}{API}{$k}{VER}");
            }
            
            Log3($name, 4, "$name - ------- End of adaption section -------");
                                    
            # Simulation älterer SVS-Versionen
            Log3($name, 4, "$name - ------- Begin of simulation section -------");
            
            if (AttrVal($name, "simu_SVSversion", undef)) {
                my @mods;
                Log3($name, 4, "$name - SVS version $actvs will be simulated");
                
                if ($actvs =~ /^71/x) {
                    push @mods, "CAM:8";
                    push @mods, "AUTH:4";
                    push @mods, "EXTREC:2";
                    push @mods, "PTZ:4";           
                } 
                elsif ($actvs =~ /^72/x) {
                    push @mods, "CAM:8";
                    push @mods, "AUTH:6";
                    push @mods, "EXTREC:3";
                    push @mods, "PTZ:5"; 
                } 
                elsif ($actvs =~ /^800/x) {
                    push @mods, "CAM:9";
                    push @mods, "AUTH:6";
                    push @mods, "EXTREC:3";
                    push @mods, "PTZ:5"; 
                } 
                elsif ($actvs =~ /^815/x) {
                    push @mods, "CAM:9";
                    push @mods, "AUTH:6";
                    push @mods, "EXTREC:3";
                    push @mods, "PTZ:5"; 
                } 
                elsif ($actvs =~ /^820/x) {
                    # ab API v2.8 kein "SYNO.SurveillanceStation.VideoStream", "SYNO.SurveillanceStation.AudioStream",
                    # "SYNO.SurveillanceStation.Streaming" mehr enthalten
                    push @mods, "VIDEOSTMS:0";
                    push @mods, "AUDIOSTM:0";
                }
                
                for my $elem (@mods) {
                    my($k,$v) = split ":", $elem;
                    $hash->{HELPER}{API}{$k}{VER} = $v;
                    $hash->{HELPER}{API}{$k}{MOD} = "yes";
                    Log3($name, 4, "$name - Version of $hash->{HELPER}{API}{$k}{NAME} adapted to: $hash->{HELPER}{API}{$k}{VER}");
                }
            } 
            
            Log3($name, 4, "$name - ------- End of simulation section -------");  
            
            setReadingErrorNone( $hash, 1 );
            
            Log3 ($name, 4, "$name - API completed after retrieval and adaption:\n".Dumper $hash->{HELPER}{API}); 

            if ($opmode eq "apiInfo") {                                             # API Infos in Popup anzeigen                            
                showAPIinfo   ($hash, $hash->{HELPER}{API});                        # übergibt Referenz zum instanziierten API-Hash)              
                delActiveToken($hash);                                              # Freigabe Funktionstoken
                return;
            }            
        } 
        else {
            $errorcode = "806";
            $error     = expErrors($hash,$errorcode);                                # Fehlertext zum Errorcode ermitteln
       
            readingsBeginUpdate($hash);
            readingsBulkUpdate ($hash, "Errorcode", $errorcode);
            readingsBulkUpdate ($hash, "Error",     $error    );
            readingsEndUpdate  ($hash, 1);

            Log3($name, 2, "$name - ERROR - $error");                    
                        
            delActiveToken($hash);                                                  # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
            return;
        }
    }
    
    if($fret) {                                                                     # Caller aufrufen wenn angegeben
        no strict "refs";                                                           ## no critic 'NoStrict' 
        delActiveToken($hash);                                                      # Freigabe Funktionstoken vor Neudurchlauf der aufrufenden Funktion 
        &$fret($arg);
        use strict "refs";
        return;
    }
    
return checkSid($hash);
}

#############################################################################################
#                        Check ob Session ID gesetzt ist - ggf. login
#############################################################################################
sub checkSid {  
   my $hash = shift;
   my $name = $hash->{NAME};
   
   my $subref;
   
   if(IsModelCam($hash)) {                                          # Folgefunktion wenn Cam-Device
       $subref = \&getCamId;  
   } 
   else {                                                           # Folgefunktion wenn SVS-Device
       $subref = \&camOp;
   }
   
   my $sid = $hash->{HELPER}{SID};                                  # SID holen bzw. login
   if(!$sid) {
       Log3($name, 3, "$name - no session ID found - get new one");
       login($hash, $hash->{HELPER}{API}, $subref);
       return;
   }
   
   if(IsModelCam($hash) || $hash->{OPMODE} eq "Autocreate") {       # Normalverarbeitung für Cams oder Autocreate Cams
       return getCamId($hash);
   } 
   else {                                                           # Sprung zu camOp wenn SVS Device
       return camOp($hash);
   }

return;
}

#############################################################################################
#                             Abruf der installierten Cams
#           die Kamera-Id wird aus dem Kameranamen (Surveillance Station) ermittelt
#############################################################################################
sub getCamId {  
   my ($hash)       = @_;
   my $name         = $hash->{NAME};
   my $serveraddr   = $hash->{SERVERADDR};
   my $serverport   = $hash->{SERVERPORT};
   my $apicam       = $hash->{HELPER}{API}{CAM}{NAME};
   my $apicampath   = $hash->{HELPER}{API}{CAM}{PATH};
   my $apicamver    = $hash->{HELPER}{API}{CAM}{VER};
   my $sid          = $hash->{HELPER}{SID};
   my $proto        = $hash->{PROTOCOL};
   
   my $url;
    
   Log3($name, 4, "$name - --- Start getCamId ---");
    
   if ($hash->{CAMID}) {                                                     # Camid ist bereits ermittelt -> Abruf überspringen
       Log3($name, 4, "$name - CAMID already set - ignore get camid");
       return camOp($hash);
   }
    
   my $httptimeout = AttrVal($name, "httptimeout", $todef);
   Log3($name, 5, "$name - HTTP-Call will be done with httptimeout-Value: $httptimeout s");
  
   $url = "$proto://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicamver&method=List&basic=true&streamInfo=true&camStm=true&_sid=\"$sid\"";
   if ($apicamver >= 9) {
       $url = "$proto://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicamver&method=\"List\"&basic=true&streamInfo=true&camStm=0&_sid=\"$sid\"";
   }
 
   Log3($name, 4, "$name - Call-Out now: $url");
  
   my $param = {
       url      => $url,
       timeout  => $httptimeout,
       hash     => $hash,
       method   => "GET",
       header   => "Accept: application/json",
       callback => \&getCamId_Parse
   };
   
   HttpUtils_NonblockingGet($param);
   
return;
}  

#############################################################################################
#               Auswertung installierte Cams, Selektion Cam , Ausführung Operation
#############################################################################################
sub getCamId_Parse {  
   my ($param, $err, $myjson) = @_;
   my $hash              = $param->{hash};
   my $name              = $hash->{NAME};
   my $camname           = $hash->{CAMNAME};
   my $apicamver         = $hash->{HELPER}{API}{CAM}{VER}; 
   my $OpMode            = $hash->{OPMODE};   
   my ($data,$success,$error,$errorcode,$camid);
   my ($i,$n,$id,$errstate,$camdef,$nrcreated);
   my $cdall = "";
   my %allcams;
  
   if ($err ne "") {                                                                          # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
       Log3($name, 2, "$name - error while requesting ".$param->{url}." - $err");
       
       readingsSingleUpdate($hash, "Error", $err, 1);
       return login($hash, $hash->{HELPER}{API}, \&getCamId);
   
   } elsif ($myjson ne "") {                                                                  # Datenabruf erfolgreich
       ($success) = evaljson($hash,$myjson);
        
       if (!$success) {
           Log3($name, 4, "$name - Data returned: ".$myjson);          
           delActiveToken($hash);
           return; 
       }
        
       $data = decode_json($myjson);
        
       Log3($name, 5, "$name - JSON returned: ". Dumper $data);
   
       $success = $data->{'success'};
                
       if ($success) {                                                                        # die Liste aller Kameras konnte ausgelesen werden      
           ($i,$nrcreated) = (0,0);
         
           %allcams = ();                                                                     # Namen aller installierten Kameras mit Id's in Hash einlesen
           while ($data->{'data'}->{'cameras'}->[$i]) {
               if ($apicamver <= 8) {
                   $n = $data->{'data'}->{'cameras'}->[$i]->{'name'};
               } 
               else {
                   $n = $data->{'data'}->{'cameras'}->[$i]->{'newName'};                      # Änderung ab SVS 8.0.0
               }
               $id = $data->{'data'}->{'cameras'}->[$i]->{'id'};
               $allcams{"$n"} = "$id";
               $i += 1;
               
               if ($OpMode eq "Autocreate") {                                                 # Cam autocreate
                   ($err,$camdef) = doAutocreate($hash,$n);
                   if ($camdef) {
                       $cdall = $cdall.($cdall ? ", " : "").$camdef;
                       $nrcreated++;
                   }
                   $errstate = $err if($err);  
               }
               
           }
           
           if ($OpMode eq "Autocreate") {                                                     # Cam autocreate
               Log3($name, 3, "$name - Cameras defined by autocreate: $cdall") if($cdall);
               
               $errstate = $errstate // "none";
               
               readingsBeginUpdate ($hash); 
               readingsBulkUpdate  ($hash, "NumberAutocreatedCams", $nrcreated           );
               readingsBulkUpdate  ($hash, "Errorcode",             "none"               );
               readingsBulkUpdate  ($hash, "Error",                 $errstate            );
               readingsBulkUpdate  ($hash, "state",                 "autocreate finished");
               readingsEndUpdate   ($hash, 1);
           
               CommandSave(undef, undef) if($errstate eq "none" && $nrcreated && AttrVal("global","autosave", 1));

               delActiveToken($hash);                                                         # Freigabe Funktionstoken
               return;
           }
             
           if (exists($allcams{$camname})) {                                                  # Ist der gesuchte Kameraname im Hash enhalten (in SVS eingerichtet ?)
               $camid         = $allcams{$camname};
               $hash->{CAMID} = $camid;
                 
               Log3($name, 4, "$name - Detection Camid successful - $camname ID: $camid");
           } 
           else {                                                                             # Kameraname nicht gefunden, id = ""
               readingsBeginUpdate ($hash);
               readingsBulkUpdate  ($hash, "Errorcode", "none"                                        );
               readingsBulkUpdate  ($hash, "Error",     "Camera(ID) not found in Surveillance Station");
               readingsEndUpdate   ($hash, 1);
                                  
               Log3($name, 2, "$name - ERROR - Cameraname $camname wasn't found in Surveillance Station. Check Userrights, Cameraname and Spelling");          
               delActiveToken($hash);
               return;
           }
      } 
      else {
           $errorcode = $data->{'error'}->{'code'};                                          # Errorcode aus JSON ermitteln
           $error     = expErrors($hash,$errorcode);                                         # Fehlertext zum Errorcode ermitteln
       
           readingsBeginUpdate ($hash);
           readingsBulkUpdate  ($hash, "Errorcode", $errorcode);
           readingsBulkUpdate  ($hash, "Error",     $error    );
           readingsEndUpdate   ($hash, 1);
           
           if ($errorcode =~ /(105|401)/x) {                                                 # neue Login-Versuche
               Log3($name, 2, "$name - ERROR - $errorcode - $error -> try new login");
               return login($hash, $hash->{HELPER}{API}, \&getCamId);
           } 
           else {                                                                            # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
               delActiveToken($hash);
               Log3($name, 2, "$name - ERROR - ID of Camera $camname couldn't be selected. Errorcode: $errorcode - $error");
               return;
           }
      }
  }
  
return camOp($hash);
}

#############################################################################################
#                                     Ausführung Operation
#############################################################################################
sub camOp {  
   my $hash       = shift;
   my $name       = $hash->{NAME};
   my $OpMode     = $hash->{OPMODE};
   my $proto      = $hash->{PROTOCOL};
   my $serveraddr = $hash->{SERVERADDR};
   my $serverport = $hash->{SERVERPORT};

   my ($url,$part,$vkey);
       
   Log3($name, 4, "$name - --- Start $OpMode ---");

   my $httptimeout = AttrVal($name, "httptimeout", $todef);
   
   if($hash->{HELPER}{CALL}) {                                                  # neue camOp Videosteuerung Ausführungsvariante
       $vkey     = $hash->{HELPER}{CALL}{VKEY};                                 # API Key Video Parts
       my $head  = $hash->{HELPER}{CALL}{HEAD};                                 # vom Standard abweichende Serveradresse / Port (z.B. bei external)
       $part     = $hash->{HELPER}{CALL}{PART};                                 # URL-Teilstring ohne Startsequenz (Server, Port, ...) 
       my $to    = $hash->{HELPER}{CALL}{TO} // 0;                              # evtl. zuätzlicher Timeout Add-On
       
       $httptimeout += $to;
       
       $part =~ s/_NAME_/$hash->{HELPER}{API}{$vkey}{NAME}/x;
       $part =~ s/_VER_/$hash->{HELPER}{API}{$vkey}{VER}/x;
       $part =~ s/_CID_/$hash->{CAMID}/x;
       $part =~ s/_SID_/$hash->{HELPER}{SID}/x;
       
       if($head) {
           $url = $head.qq{/webapi/$hash->{HELPER}{API}{$vkey}{PATH}?}.$part;
       } 
       else {       
           $url = qq{$proto://$serveraddr:$serverport/webapi/$hash->{HELPER}{API}{$vkey}{PATH}?}.$part;
       }
   }
   
   if($hash->{HELPER}{ACALL}) {                                                 # neue camOp Audiosteuerung Ausführungsvariante 
       my $akey  = $hash->{HELPER}{ACALL}{AKEY};                                # API Key Audio Parts
       my $apart = $hash->{HELPER}{ACALL}{APART};                               # URL-Teilstring Audio
       
       $apart =~ s/_ANAME_/$hash->{HELPER}{API}{$akey}{NAME}/x;
       $apart =~ s/_AVER_/$hash->{HELPER}{API}{$akey}{VER}/x;
       $apart =~ s/_CID_/$hash->{CAMID}/x;
       $apart =~ s/_SID_/$hash->{HELPER}{SID}/x;  

       $hash->{HELPER}{AUDIOLINK} = qq{$proto://$serveraddr:$serverport/webapi/$hash->{HELPER}{API}{$akey}{PATH}?}.$apart;           
   }
   
   if ($OpMode eq "runliveview" && $hash->{HELPER}{RUNVIEW} !~ m/snap|^live_.*hls$/x) {
      _Oprunliveview ($hash, $part, $vkey);
      return;  
   }  
   
   Log3($name, 5, "$name - HTTP-Call will be done with httptimeout-Value: $httptimeout s");
   Log3($name, 4, "$name - Call-Out now: $url");
   
   my $param = {
       url      => $url,
       timeout  => $httptimeout,
       hash     => $hash,
       method   => "GET",
       header   => "Accept: application/json",
       callback => \&camOp_Parse
   };
   
   HttpUtils_NonblockingGet ($param); 

return;   
} 

################################################################
#                       camOp runliveview
# wird bei runliveview aufgerufen wenn nicht Anzeige Snaps 
# oder kein HLS-Stream aktiviert werden soll
################################################################
sub _Oprunliveview {                   
  my $hash = shift // return;
  my $part = shift // delCallParts($hash) && return;
  my $vkey = shift // delCallParts($hash) && return;
  my $name = $hash->{NAME};
  
  my $proto      = $hash->{PROTOCOL};
  my $serveraddr = $hash->{SERVERADDR};
  my $serverport = $hash->{SERVERPORT};
  
  my $url;

  my $exturl = AttrVal($name, "livestreamprefix", "$proto://$serveraddr:$serverport");                      # externe URL
  $exturl    = ($exturl eq "DEF") ? "$proto://$serveraddr:$serverport" : $exturl;      
  
  if ($hash->{HELPER}{RUNVIEW} =~ m/live/x) {    
      if($part) {                                                                                           # API "SYNO.SurveillanceStation.VideoStream" vorhanden ? (removed ab API v2.8) 
          $exturl .= qq{/webapi/$hash->{HELPER}{API}{$vkey}{PATH}?}.$part;                                   
          $url     = qq{$proto://$serveraddr:$serverport/webapi/$hash->{HELPER}{API}{$vkey}{PATH}?}.$part;  # interne URL
      
      } elsif ($hash->{HELPER}{STMKEYMJPEGHTTP}) {
          $url = $hash->{HELPER}{STMKEYMJPEGHTTP};
      }
  } 
  else {                                                                                                    # Abspielen der letzten Aufnahme (EventId)                       
      $exturl .= qq{/webapi/$hash->{HELPER}{API}{$vkey}{PATH}?}.$part; 
      $url     = qq{$proto://$serveraddr:$serverport/webapi/$hash->{HELPER}{API}{$vkey}{PATH}?}.$part;      # interne URL
  }
  
  readingsSingleUpdate($hash,"LiveStreamUrl", $exturl, 1) if(AttrVal($name, "showStmInfoFull", 0));
   
  $hash->{HELPER}{LINK} = $url;                                                                             # Liveview-Link in Hash speichern

  Log3($name, 4, "$name - Set Streaming-URL: $url");
  
  if ($hash->{HELPER}{OPENWINDOW}) {                                                                        # livestream sofort in neuem Browsertab öffnen
      my $winname = $name."_view";
      my $attr    = AttrVal($name, "htmlattr", "");
      
      if ($hash->{HELPER}{VIEWOPENROOM}) {                                                                  # öffnen streamwindow für die Instanz die "VIEWOPENROOM" oder Attr "room" aktuell geöffnet hat
          my $room = $hash->{HELPER}{VIEWOPENROOM};
          map {FW_directNotify("FILTER=room=$room", "#FHEMWEB:$_", "window.open ('$url','$winname','$attr')", "")} devspec2array("TYPE=FHEMWEB");   ## no critic 'void context'
      } 
      else {
          map {FW_directNotify("#FHEMWEB:$_", "window.open ('$url','$winname','$attr')", "")} devspec2array("TYPE=FHEMWEB");                        ## no critic 'void context'
      }
  }
       
  roomRefresh($hash,0,1,1);                                                                                 # kein Room-Refresh, SSCam-state-Event, SSCamSTRM-Event

  delActiveToken ($hash);

return;
}
  
###################################################################################  
#      Check ob Kameraoperation erfolgreich wie in "OpMOde" definiert 
###################################################################################
sub camOp_Parse {  
   my $param              = shift;
   my $err                = shift;
   my $myjson             = shift;
   
   my $hash               = $param->{hash};
   my $name               = $hash->{NAME};
   my $camname            = $hash->{CAMNAME};
   my $OpMode             = $hash->{OPMODE};
   
   my ($data,$success);
   
   # Einstellung für Logausgabe Pollinginfos
   # wenn "pollnologging" = 1 -> logging nur bei Verbose=4, sonst 3 
   my $verbose = 3;
   if (AttrVal($name, "pollnologging", 0)) {
       $verbose = 4;
   }
   
   if ($err ne "") {                                                                  # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
        Log3($name, 2, "$name - error while requesting ".$param->{url}." - $err");
        readingsSingleUpdate($hash, "Error", $err, 1);                                             
        
        delActiveToken ($hash);                                                       # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
        
        return;
   } 
   elsif ($myjson ne "") {                                                            # wenn die Abfrage erfolgreich war     
        if($OpMode !~ /SaveRec|GetRec/x) {                                            # "SaveRec/GetRec" liefern MP4-Daten und kein JSON   
            ($success,$myjson) = evaljson($hash,$myjson);        
            
            if (!$success) {
                Log3($name, 4, "$name - Data returned: ".$myjson);
                
                delActiveToken ($hash);
                
                return;
            }
            
            $data = decode_json($myjson);
            
            Log3($name, 5, "$name - JSON returned: ". Dumper $data);                  # Logausgabe decodierte JSON Daten
       
            $success = $data->{'success'};    
        } 
        else {
            $success = 1; 
        }

        if ($success) {                                                               # Kameraoperation entsprechend "OpMode" war erfolgreich                
            my $params = {
                hash    => $hash,
                name    => $name,
                camname => $camname,
                OpMode  => $OpMode,
                myjson  => $myjson,
                data    => $data,
                verbose => $verbose,
            };
              
            no strict "refs";                                                        ## no critic 'NoStrict'  
            if($hparse{$OpMode} && defined &{$hparse{$OpMode}{fn}}) {
                my $ret = q{};  
                $ret    = &{$hparse{$OpMode}{fn}} ($params);
                return if($ret);
            }
            use strict "refs";
  
            if ($OpMode eq "ExpMode") {
                Log3               ($name, 3, qq{$name - Camera $camname exposure mode is set to "$hash->{HELPER}{EXPMODE}"} );
                setReadingErrorNone($hash, 1 );
                
                __getCamInfo       ($hash);
            } 
            elsif ($OpMode eq "setZoom") {   
                Log3               ($name, 3, qq{$name - Zoom operation "$hash->{HELPER}{ZOOM}{DIR}:$hash->{HELPER}{ZOOM}{MOVETYPE}" of Camera $camname successfully done} );
                setReadingErrorNone($hash, 1 ); 
            }            
            elsif ($OpMode eq "extevent") {
                Log3               ($name, 3, qq{$name - External Event "$hash->{HELPER}{EVENTID}" successfully triggered} );          
                setReadingErrorNone($hash, 1 );
            } 
            elsif ($OpMode eq "sethomemode") {              
                Log3               ($name, 3, qq{$name - HomeMode was set to "$hash->{HELPER}{HOMEMODE}"} );
                setReadingErrorNone($hash, 1 );
                
                delActiveToken     ($hash);                                           # Token freigeben vor nächstem Kommando
                __getHomeModeState ($hash);                                           # neuen HomeModeState abrufen   
            } 
            elsif ($OpMode eq "setPreset") {              
                my $pnumber = delete($hash->{HELPER}{PNUMBER});
                my $pname   = delete($hash->{HELPER}{PNAME});
                my $pspeed  = delete($hash->{HELPER}{PSPEED});                
                $pspeed     = $pspeed?$pspeed:"not set";

                Log3               ($name, 3, "$name - Camera $camname preset \"$pname\" was saved to number $pnumber with speed $pspeed");
                setReadingErrorNone($hash, 1);
                
                __getPtzPresetList ($hash);
            } 
            elsif ($OpMode eq "delPreset") {                
                my $dp = $hash->{HELPER}{DELPRESETNAME};
                delete $hash->{HELPER}{ALLPRESETS}{$dp};                
                
                Log3               ($name, 3, "$name - Preset \"$dp\" of camera \"$camname\" has been deleted");  
                setReadingErrorNone($hash, 1);
    
                __getPtzPresetList ($hash);
            } 
            elsif ($OpMode eq "piract") {              
                my $piract = ($hash->{HELPER}{PIRACT} == 0)?"activated":"deactivated";
                
                Log3               ($name, 3, "$name - PIR sensor $piract");
                setReadingErrorNone($hash, 1);
            } 
            elsif ($OpMode eq "setHome") {    
                my $sh = $hash->{HELPER}{SETHOME}; 
                
                Log3               ($name, 3, "$name - Preset \"$sh\" of camera \"$camname\" was set as Home position");
                setReadingErrorNone($hash, 1);
                
                __getPtzPresetList ($hash);
            } 
            elsif ($OpMode eq "setoptpar") { 
                my $rid  = $data->{'data'}{'id'};                                                       # Cam ID return wenn i.O.
                my $ropt = $rid == $hash->{CAMID} ? "none" : "error in operation";
                
                delete($hash->{HELPER}{NTPSERV});
                delete($hash->{HELPER}{MIRROR});
                delete($hash->{HELPER}{FLIP});
                delete($hash->{HELPER}{ROTATE});
                delete($hash->{HELPER}{CHKLIST});
                
                readingsBeginUpdate ($hash);
                readingsBulkUpdate  ($hash,"Errorcode","none");
                readingsBulkUpdate  ($hash,"Error",$ropt);
                readingsEndUpdate   ($hash, 1);

                delActiveToken      ($hash);                                                            # Token freigeben vor Abruf caminfo
                __getCamInfo        ($hash);
            } 
            elsif ($OpMode eq "stopliveview_hls") {                                                     # HLS Streaming wurde deaktiviert, Aktivitätsstatus speichern
                $hash->{HELPER}{HLSSTREAM} = "inactive";
                Log3($name, 3, "$name - HLS Streaming of camera \"$name\" deactivated");
                               
                roomRefresh($hash,0,1,1);                                                               # kein Room-Refresh, SSCam-state-Event, SSCamSTRM-Event
            } 
            elsif ($OpMode eq "reactivate_hls") {                                                       # HLS Streaming wurde deaktiviert, Aktivitätsstatus speichern
                $hash->{HELPER}{HLSSTREAM} = "inactive";
                Log3($name, 3, "$name - HLS Streaming of camera \"$name\" deactivated for reactivation");

                delActiveToken ($hash);                                                                 # Token freigeben vor hlsactivate
                __activateHls  ($hash);
                return;
            } 
            elsif ($OpMode eq "activate_hls") {                                                         # HLS Streaming wurde aktiviert, Aktivitätsstatus speichern
                $hash->{HELPER}{HLSSTREAM} = "active"; 
                Log3($name, 3, "$name - HLS Streaming of camera \"$name\" activated");
                
                roomRefresh($hash,0,1,1);                                                               # kein Room-Refresh, SSCam-state-Event, SSCamSTRM-Event                
            } 
            elsif ($OpMode eq "getsnapfilename") {                                                      # den Filenamen eines Schnapschusses ermitteln
                my $snapid = ReadingsVal("$name", "LastSnapId", "");

                if(!$snapid) {
                   Log3($name, 2, "$name - Snap-ID \"LastSnapId\" isn't set. Filename can't be retrieved");
                   delActiveToken ($hash);                                                              # Token freigeben vor hlsactivate
                   return;
                }               

                Log3($name, 4, "$name - Filename of Snap-ID $snapid is \"$data->{'data'}{'data'}[0]{'fileName'}\"") if($data->{'data'}{'data'}[0]{'fileName'});
            
                readingsSingleUpdate($hash, "LastSnapFilename", $data->{'data'}{'data'}[0]{'fileName'}, 1);
                setReadingErrorNone ($hash, 1);            
            } 
            elsif ($OpMode eq "getstreamformat") {                                                      # aktuelles Streamformat abgefragt
                my $sformat = jboolmap($data->{'data'}->{'format'});
                $sformat    = $sformat ? uc($sformat) : "no API";
                
                readingsSingleUpdate($hash, "CamStreamFormat", $sformat, 1);
                setReadingErrorNone ($hash, 1);                
            } 
            elsif ($OpMode eq "runpatrol") {                                                          # eine Tour wurde gestartet
                my $st = (ReadingsVal("$name", "Record", "Stop") eq "Start") ? "on" : "off";          # falls Aufnahme noch läuft -> state = on setzen  
                DoTrigger($name,"patrol started"); 
                               
                Log3                ($name, 3, qq{$name - Patrol "$hash->{HELPER}{GOPATROLNAME}" of camera $camname has been started successfully} );
                readingsSingleUpdate($hash,"state", $st, 0);
                setReadingErrorNone ($hash, 1); 
            } 
            elsif ($OpMode eq "goabsptz") {                                                           # eine absolute PTZ-Position wurde angefahren
                my $st = (ReadingsVal("$name", "Record", "Stop") eq "Start") ? "on" : "off";          # falls Aufnahme noch läuft -> state = on setzen   
                DoTrigger($name,"move stop");
                
                Log3                ($name, 3, qq{$name - Camera $camname has been moved to absolute position "posX=$hash->{HELPER}{GOPTZPOSX}" and "posY=$hash->{HELPER}{GOPTZPOSY}"} );
                readingsSingleUpdate($hash,"state", $st, 0);
                setReadingErrorNone ($hash, 1);
            } 
            elsif ($OpMode eq "startTrack") {                                                                     # Object Tracking wurde eingeschaltet                          
                Log3               ($name, 3, qq{$name - Object tracking of Camera $camname has been switched on} );
                setReadingErrorNone($hash, 1 );      
            } 
            elsif ($OpMode eq "stopTrack") {                                                                      # Object Tracking wurde eingeschaltet             
                Log3               ($name, 3, qq{$name - Object tracking of Camera $camname has been stopped} );
                setReadingErrorNone($hash, 1);           
            } 
            elsif ($OpMode eq "movestart") {                                                                      # ein "Move" in eine bestimmte Richtung wird durchgeführt                 
                Log3               ($name, 3, qq{$name - Camera $camname started move to direction "$hash->{HELPER}{GOMOVEDIR}" with duration of $hash->{HELPER}{GOMOVETIME} s} );
                setReadingErrorNone($hash, 1); 
                
                RemoveInternalTimer($hash, "FHEM::SSCam::__moveStop" );
                InternalTimer      (gettimeofday()+($hash->{HELPER}{GOMOVETIME}), "FHEM::SSCam::__moveStop", $hash );
            } 
            elsif ($OpMode eq "movestop") {                                                                       # ein "Move" in eine bestimmte Richtung wurde durchgeführt 
                my $st = (ReadingsVal("$name", "Record", "Stop") eq "Start") ? "on" : "off";                      # falls Aufnahme noch läuft -> state = on setzen    
                DoTrigger($name,"move stop");
                         
                Log3                ($name, 3, qq{$name - Camera $camname stopped move to direction "$hash->{HELPER}{GOMOVEDIR}"} );
                readingsSingleUpdate($hash,"state", $st, 0);
                setReadingErrorNone ($hash, 1); 
            } 
            elsif ($OpMode eq "Enable") {                                                                         # Kamera wurde aktiviert, sonst kann nichts laufen -> "off"                
                Log3($name, 3, "$name - Camera $camname has been enabled successfully");
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate ($hash, "Availability", "enabled");
                readingsBulkUpdate ($hash, "state",        "off"    );
                readingsEndUpdate  ($hash, 1); 
 
                setReadingErrorNone ($hash, 1);  
            } 
            elsif ($OpMode eq "Disable") {                                                       # Kamera wurde deaktiviert
                Log3($name, 3, "$name - Camera $camname has been disabled successfully");
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate ($hash, "Availability", "disabled");
                readingsBulkUpdate ($hash, "state",        "disabled");
                readingsEndUpdate  ($hash, 1);

                setReadingErrorNone ($hash, 1);                 
            }     
       } 
       else {                                                                 # die API-Operation war fehlerhaft
            my $errorcode = $data->{'error'}->{'code'};                       # Errorcode aus JSON ermitteln
            my $error     = expErrors($hash,$errorcode);                      # Fehlertext zum Errorcode ermitteln
            
            readingsBeginUpdate($hash);
            readingsBulkUpdate ($hash, "Errorcode", $errorcode);
            readingsBulkUpdate ($hash, "Error",     $error    );
            readingsEndUpdate  ($hash, 1);
            
            if ($errorcode =~ /105/x) {
               Log3($name, 2, "$name - ERROR - $errorcode - $error in operation $OpMode -> try new login");
               undef $data;
               undef $myjson;
               return login($hash, $hash->{HELPER}{API}, \&camOp);
            }
       
            Log3($name, 2, "$name - ERROR - Operation $OpMode not successful. Cause: $errorcode - $error");
       }          
       undef $data;
       undef $myjson;
   }

   delActiveToken ($hash);                                                     # Token freigeben

return;
}

###############################################################################
#               Parse OpMode Start
# Die Aufnahmezeit setzen
# wird "set <name> on [rectime]" verwendet -> dann [rectime] nutzen, 
# sonst Attribut "rectime" wenn es gesetzt ist, falls nicht -> "RECTIME_DEF"
###############################################################################
sub _parseStart {                                       ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $camname = $paref->{camname};  
                               
  my $rectime;

  if (defined($hash->{HELPER}{RECTIME_TEMP})) {
      $rectime = delete $hash->{HELPER}{RECTIME_TEMP};
  } 
  else {
      $rectime = AttrVal($name, "rectime", $hash->{HELPER}{RECTIME_DEF});
  }

  if ($rectime == 0) {
      Log3($name, 3, "$name - Camera $camname endless Recording started  - stop it by stop-command !");
  } 
  else {
      if (ReadingsVal("$name", "Record", "Stop") eq "Start") {                                        # Aufnahme läuft schon und wird verlängert
          Log3($name, 3, "$name - running recording renewed to $rectime s");
      } 
      else {
          Log3($name, 3, "$name - Camera $camname recording with recording time $rectime s started");
      }
  }
       
  readingsBeginUpdate($hash);
  readingsBulkUpdate ($hash, "Record",    "Start");
  readingsBulkUpdate ($hash, "state",     "on"   );
  readingsBulkUpdate ($hash, "Errorcode", "none" );
  readingsBulkUpdate ($hash, "Error",     "none" );
  readingsEndUpdate  ($hash, 1);

  if ($rectime != 0) {                                                                                # Stop der Aufnahme nach Ablauf $rectime, wenn rectime = 0 -> endlose Aufnahme
      my $emtxt   = $hash->{HELPER}{SMTPRECMSG} // "";
      my $teletxt = $hash->{HELPER}{TELERECMSG} // "";
    
      RemoveInternalTimer ($hash, "FHEM::SSCam::__camStopRec");
      InternalTimer       (gettimeofday()+$rectime, "FHEM::SSCam::__camStopRec", $hash);
  }      

  roomRefresh($hash,0,0,1);                                                                           # kein Room-Refresh, kein SSCam-state-Event, SSCamSTRM-Event           
        
return;
}

###############################################################################
#               Parse OpMode Stop
###############################################################################
sub _parseStop {                                        ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $camname = $paref->{camname}; 
                               
  readingsBeginUpdate($hash);
  readingsBulkUpdate ($hash, "Record",    "Stop");
  readingsBulkUpdate ($hash, "state",     "off" );
  readingsBulkUpdate ($hash, "Errorcode", "none");
  readingsBulkUpdate ($hash, "Error"    , "none");
  readingsEndUpdate  ($hash, 1);

  Log3($name, 3, "$name - Camera $camname Recording stopped");

  roomRefresh($hash,0,0,1);    # kein Room-Refresh, kein SSCam-state-Event, SSCamSTRM-Event

  # Aktualisierung Eventlist der letzten Aufnahme
  __getEventList($hash);
                
return;
}

###############################################################################
#                       Parse OpMode GetRec
###############################################################################
sub _parseGetRec {                                      ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $camname = $paref->{camname};
  my $OpMode  = $paref->{OpMode};
  my $myjson  = $paref->{myjson};
                               
  my $recid            = ReadingsVal("$name", "CamLastRecId",   "");
  my $createdTm        = ReadingsVal("$name", "CamLastRecTime", "");
  my $lrec             = ReadingsVal("$name", "CamLastRec",     "");
  my ($tdir,$fileName) = split("/",$lrec); 
  my $sn               = 0;

  my $tac = openOrgetTrans($hash);                                                                     # Transaktion starten             

  my $cache;
  if($hash->{HELPER}{CANSENDREC} || $hash->{HELPER}{CANTELEREC} || $hash->{HELPER}{CANCHATREC}) {
      $cache = cache($name, "c_init");                                                                 # Cache initialisieren für Versandhash
      Log3($name, 1, "$name - Fall back to internal Cache due to preceding failure.") if(!$cache);         
      
      if(!$cache || $cache eq "internal" ) {
          $data{SSCam}{$name}{SENDRECS}{$tac}{$sn}{recid}     = $recid;
          $data{SSCam}{$name}{SENDRECS}{$tac}{$sn}{createdTm} = $createdTm;
          $data{SSCam}{$name}{SENDRECS}{$tac}{$sn}{fileName}  = $fileName;
          $data{SSCam}{$name}{SENDRECS}{$tac}{$sn}{tdir}      = $tdir;
          $data{SSCam}{$name}{SENDRECS}{$tac}{$sn}{imageData} = $myjson;
      } 
      else {
          cache($name, "c_write", "{SENDRECS}{$tac}{$sn}{recid}"     ,$recid);
          cache($name, "c_write", "{SENDRECS}{$tac}{$sn}{createdTm}" ,$createdTm);
          cache($name, "c_write", "{SENDRECS}{$tac}{$sn}{fileName}"  ,$fileName);
          cache($name, "c_write", "{SENDRECS}{$tac}{$sn}{tdir}"      ,$tdir);                         
          cache($name, "c_write", "{SENDRECS}{$tac}{$sn}{imageData}" ,$myjson);                         
      }
      
      Log3($name, 4, "$name - Recording '$sn' added to send recording hash: ID => $recid, File => $fileName, Created => $createdTm");
  }

  # Recording als Email / Telegram / Chat versenden 
  if(!$cache || $cache eq "internal" ) {                
      prepareSendData ($hash, $OpMode, $data{SSCam}{$name}{SENDRECS}{$tac});
  } 
  else {
      prepareSendData ($hash, $OpMode, "{SENDRECS}{$tac}");
  }

  closeTrans         ($hash);                                                                        # Transaktion beenden
  setReadingErrorNone( $hash, 1 );
                
return;
}

###############################################################################
#                       Parse OpMode MotDetSc
###############################################################################
sub _parseMotDetSc {                                    ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $camname = $paref->{camname};
                               
  my $sensitivity;
  if ($hash->{HELPER}{MOTDETSC} eq "SVS" && keys %{$hash->{HELPER}{MOTDETOPTIONS}}) {           # Optionen für "SVS" sind gesetzt
      $sensitivity  = ($hash->{HELPER}{MOTDETOPTIONS}{SENSITIVITY}) ? ($hash->{HELPER}{MOTDETOPTIONS}{SENSITIVITY}) : "-";
      my $threshold = ($hash->{HELPER}{MOTDETOPTIONS}{THRESHOLD}) ? ($hash->{HELPER}{MOTDETOPTIONS}{THRESHOLD}) : "-";
    
      Log3($name, 3, "$name - Camera $camname motion detection source set to \"$hash->{HELPER}{MOTDETSC}\" with options sensitivity: $sensitivity, threshold: $threshold");

  } elsif ($hash->{HELPER}{MOTDETSC} eq "camera" && keys %{$hash->{HELPER}{MOTDETOPTIONS}}) {   # Optionen für "camera" sind gesetzt
      $sensitivity   = ($hash->{HELPER}{MOTDETOPTIONS}{SENSITIVITY}) ? ($hash->{HELPER}{MOTDETOPTIONS}{SENSITIVITY}) : "-";
      my $objectSize = ($hash->{HELPER}{MOTDETOPTIONS}{OBJECTSIZE}) ? ($hash->{HELPER}{MOTDETOPTIONS}{OBJECTSIZE}) : "-";
      my $percentage = ($hash->{HELPER}{MOTDETOPTIONS}{PERCENTAGE}) ? ($hash->{HELPER}{MOTDETOPTIONS}{PERCENTAGE}) : "-";
    
      Log3($name, 3, "$name - Camera $camname motion detection source set to \"$hash->{HELPER}{MOTDETSC}\" with options sensitivity: $sensitivity, objectSize: $objectSize, percentage: $percentage");
  } 
  else {                                                                                      # keine Optionen Bewegungserkennung wurden gesetzt
      Log3($name, 3, "$name - Camera $camname motion detection source set to \"$hash->{HELPER}{MOTDETSC}\" ");
  }

  setReadingErrorNone( $hash, 1 );
  
  __getMotionEnum    ($hash);                                                                   # neu gesetzte Parameter abrufen

return;
}

###############################################################################
#                       Parse OpMode getsvslog
###############################################################################
sub _parsegetsvslog {                                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $data  = $paref->{data};
                               
  my $lec = $data->{'data'}{'total'};                                                    # abgerufene Anzahl von Log-Einträgen

  my $log  = q{};
  my $log0 = q{};
  my $i    = 0;

  while ($data->{'data'}->{'log'}->[$i]) {
      my $id    = $data->{'data'}->{'log'}->[$i]{'id'};
      my $un    = $data->{'data'}->{'log'}->[$i]{'user_name'};
      my $desc  = $data->{'data'}->{'log'}->[$i]{'desc'};
      my $level = $data->{'data'}->{'log'}->[$i]{'type'};
      $level    = ($level == 3) ? "Error" : ($level == 2) ? "Warning" : "Information";
      my $time  = FmtDateTime($data->{'data'}->{'log'}->[$i]{'time'});
      $log0     = $time." - ".$level." - ".$desc if($i == 0);
      $log     .= "$time - $level - $desc<br>";
      $i++;
  }   
  
  $log = "<html><b>Surveillance Station Server \"$hash->{SERVERADDR}\" Log</b> ( $i/$lec entries are displayed )<br><br>$log</html>";
                
  # asyncOutput kann normalerweise etwa 100k uebertragen (siehe fhem.pl/addToWritebuffer() fuer Details)
  # bzw. https://forum.fhem.de/index.php/topic,77310.0.html
  # $log = "Too much log data were selected. Please reduce amount of data by specifying all or one of 'severity', 'limit', 'match'" if (length($log) >= 102400);              

  readingsBeginUpdate ($hash);
  readingsBulkUpdate  ($hash,"LastLogEntry",$log0) if(!$hash->{HELPER}{CL}{1});         # Datenabruf im Hintergrund;
  readingsBulkUpdate  ($hash,"Errorcode","none");
  readingsBulkUpdate  ($hash,"Error","none");
  readingsEndUpdate   ($hash, 1);

  # Ausgabe Popup der Log-Daten (nach readingsEndUpdate positionieren sonst "Connection lost, trying reconnect every 5 seconds" wenn > 102400 Zeichen)        
  asyncOutput($hash->{HELPER}{CL}{1},"$log");
  delClHash  ($name);
                
return;
}

###############################################################################
#                       Parse OpMode SaveRec
###############################################################################
sub _parseSaveRec {                                     ## no critic "not used"
  my $paref  = shift;
  my $hash   = $paref->{hash};
  my $name   = $paref->{name};
  my $myjson = $paref->{myjson};
         
  my $err;
  
  my $lrec = ReadingsVal($name, "CamLastRec", "");
  $lrec    = (split("/",$lrec))[1]; 
  my $sp   = $hash->{HELPER}{RECSAVEPATH} // $attr{global}{modpath};
  my $file = $sp."/$lrec";
  
  delete $hash->{HELPER}{RECSAVEPATH};

  open my $fh, '>', $file or do { $err = qq{Can't open file "$file": $!};
                                  Log3($name, 2, "$name - $err");
                                };       

  if(!$err) {
      $err = "none";      
      binmode $fh;
      print $fh $myjson;
      close($fh);
      Log3($name, 3, qq{$name - Recording was saved to local file "$file"});
  }

  readingsBeginUpdate ($hash);
  readingsBulkUpdate  ($hash, "Errorcode", "none");
  readingsBulkUpdate  ($hash, "Error",     $err  );
  readingsEndUpdate   ($hash, 1);
                
return;
}

###############################################################################
#                       Parse OpMode gethomemodestate
###############################################################################
sub _parsegethomemodestate {                            ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $data  = $paref->{data};
         
  my $lang    = AttrVal("global","language","EN");
  my $hmst    = $data->{'data'}{'on'}; 
  my $hmststr = $hmst == 1 ? "on" : "off";
  
  my $update_time;

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
  
  if($lang eq "DE") {
      $update_time = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;
  } 
  else {
      $update_time = sprintf "%04d-%02d-%02d / %02d:%02d:%02d" , $year+=1900 , $mon+=1 , $mday , $hour , $min , $sec ;
  }               

  readingsBeginUpdate ($hash);
  readingsBulkUpdate  ($hash, "HomeModeState",  $hmststr     );
  readingsBulkUpdate  ($hash, "LastUpdateTime", $update_time );
  readingsBulkUpdate  ($hash, "Errorcode",      "none"       );
  readingsBulkUpdate  ($hash, "Error",          "none"       );
  readingsEndUpdate   ($hash, 1);
                
return;
}

###############################################################################
#                       Parse OpMode getPresets
###############################################################################
sub _parsegetPresets {                                  ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $data  = $paref->{data};
         
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
  for my $key (sort{$a <=>$b}keys%ap) { 
      $enum .= $key." => ".$ap{$key}."<br>";                 
  }

  $enum = "<html><b>Preset positions saved of camera \"$hash->{CAMNAME}\" </b> ".
          "(PresetNumber => Name: ..., Speed: ..., Type: ...) <br><br>$enum</html>";
                
  # asyncOutput kann normalerweise etwa 100k uebertragen (siehe fhem.pl/addToWritebuffer() fuer Details)
  # bzw. https://forum.fhem.de/index.php/topic,77310.0.html               

  setReadingErrorNone( $hash, 1 );

  # Ausgabe Popup der Daten (nach readingsEndUpdate positionieren sonst 
  # "Connection lost, trying reconnect every 5 seconds" wenn > 102400 Zeichen)        
  asyncOutput($hash->{HELPER}{CL}{1},"$enum");
  delClHash  ($name);
                
return;
}

###############################################################################
#                       Parse OpMode Snap
# ein Schnapschuß wurde aufgenommen, falls Aufnahme noch läuft -> 
# state = on setzen
###############################################################################
sub _parseSnap {                                        ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $data    = $paref->{data};
  my $camname = $paref->{camname};
         
  roomRefresh($hash,0,1,0);                                            # kein Room-Refresh, SSCam-state-Event, kein SSCamSTRM-Event

  my $tac = "";
  if($hash->{HELPER}{CANSENDSNAP} || $hash->{HELPER}{CANTELESNAP} || $hash->{HELPER}{CANCHATSNAP}) { 
      $tac = openOrgetTrans($hash);                                    # Transaktion starten oder vorhandenen Code holen
  }

  my $snapid = $data->{data}{'id'};

  setReadingErrorNone($hash, 1);
                
  if ($snapid) {
      Log3($name, 3, "$name - Snapshot of Camera $camname created. ID: $snapid");
  } 
  else {
      Log3($name, 1, "$name - Snapshot of Camera $camname probably not created. No ID was delivered.");
      closeTrans    ($hash);                                           # Transaktion beenden falls gestartet
      delActiveToken($hash);
      return 1;
  }

  my $num     = $hash->{HELPER}{SNAPNUM};                              # Gesamtzahl der auszulösenden Schnappschüsse
  my $ncount  = $hash->{HELPER}{SNAPNUMCOUNT};                         # Restzahl der auszulösenden Schnappschüsse 
  
  if (AttrVal($name,"debugactivetoken",0)) {
      Log3($name, 1, "$name - Snapshot number ".($num-$ncount+1)." (ID: $snapid) of total $num snapshots with TA-code: $tac done");
  }
  $ncount--;                                                           # wird vermindert je Snap
  
  my $lag     = $hash->{HELPER}{SNAPLAG};                              # Zeitverzögerung zwischen zwei Schnappschüssen
  my $emtxt   = $hash->{HELPER}{SMTPMSG} // "";                        # Text für Email-Versand
  my $teletxt = $hash->{HELPER}{TELEMSG} // "";                        # Text für TelegramBot-Versand
  my $chattxt = $hash->{HELPER}{CHATMSG} // "";                        # Text für SSChatBot-Versand
  
  if($ncount > 0) {
      InternalTimer(gettimeofday()+$lag, "FHEM::SSCam::__camSnap", "$name!_!$num!_!$lag!_!$ncount!_!$emtxt!_!$teletxt!_!$chattxt!_!$tac", 0);
      if(!$tac) {
          delActiveToken($hash);                                       # Token freigeben wenn keine Transaktion läuft
      }
      return 1;
  }

  my ($slim,$ssize) = snapLimSize($hash);                              # Anzahl und Size für Schnappschußabruf bestimmen
  
  if (AttrVal($name,"debugactivetoken",0)) {
      Log3($name, 1, "$name - start get snapinfo of last $slim snapshots with TA-code: $tac");
  }

  if(!$hash->{HELPER}{TRANSACTION}) {                                  # Token freigeben vor nächstem Kommando wenn keine Transaktion läuft
      delActiveToken($hash);                        
  }

  __getSnapInfo ("$name:$slim:$ssize:$tac");
                
return 1;
}

###############################################################################
#                       Parse OpMode getsvsinfo
#                       Parse SVS-Infos
###############################################################################
sub _parsegetsvsinfo {                                  ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $data    = $paref->{data};
  my $verbose = $paref->{verbose};
         
  my $userPriv = $data->{'data'}{'userPriv'};
  if (defined($userPriv)) {
      $userPriv = $hrkeys{userPriv}{$userPriv};
  }                    

  $hash->{HELPER}{SVSVERSION}{MAJOR} = $data->{'data'}{'version'}{'major'};         # Werte in $hash zur späteren Auswertung einfügen 
  $hash->{HELPER}{SVSVERSION}{MINOR} = $data->{'data'}{'version'}{'minor'};
  $hash->{HELPER}{SVSVERSION}{SMALL} = $data->{'data'}{'version'}{'small'};
  $hash->{HELPER}{SVSVERSION}{BUILD} = $data->{'data'}{'version'}{'build'};

  my $major = $hash->{HELPER}{SVSVERSION}{MAJOR};
  my $minor = $hash->{HELPER}{SVSVERSION}{MINOR};
  my $small = $hash->{HELPER}{SVSVERSION}{SMALL};
  my $build = $hash->{HELPER}{SVSVERSION}{BUILD};

  if (AttrVal($name, "simu_SVSversion", undef)) {                                  # simulieren einer anderen SVS-Version
      Log3($name, 4, "$name - another SVS-version ".AttrVal($name, "simu_SVSversion", undef)." will be simulated");

      my @vl = split (/\.|-/x,AttrVal($name, "simu_SVSversion", ""));
      $major = $vl[0];
      $minor = $vl[1];
      $small = ($vl[2] =~ /\d/x) ? $vl[2] : '';
      $build = "xxxx-simu";
  }

  my $avsc   = $major.$minor.(($small=~/\d/x) ? $small : 0);                      # Kompatibilitätscheck
  my $avcomp = $hash->{COMPATIBILITY};
  $avcomp    =~ s/\.//gx;

  my $compstate = ($avsc <= $avcomp) ? "true" : "false";
  readingsSingleUpdate($hash, "compstate", $compstate, 1);

  if (!exists($data->{'data'}{'customizedPortHttp'})) {
      delete $defs{$name}{READINGS}{SVScustomPortHttp};
  }             

  if (!exists($data->{'data'}{'customizedPortHttps'})) {
      delete $defs{$name}{READINGS}{SVScustomPortHttps};
  }
                
  readingsBeginUpdate ($hash);

  readingsBulkUpdate  ($hash, "SVScustomPortHttp",  $data->{'data'}{'customizedPortHttp'});
  readingsBulkUpdate  ($hash, "SVScustomPortHttps", $data->{'data'}{'customizedPortHttps'});
  readingsBulkUpdate  ($hash, "SVSlicenseNumber",   $data->{'data'}{'liscenseNumber'});
  readingsBulkUpdate  ($hash, "SVSuserPriv",$userPriv);

  if(defined($small)) {
      readingsBulkUpdate($hash, "SVSversion", $major.".".$minor.".".$small."-".$build);
  } 
  else {
      readingsBulkUpdate($hash, "SVSversion", $major.".".$minor."-".$build);
  }

  readingsBulkUpdate ($hash, "Errorcode", "none");
  readingsBulkUpdate ($hash, "Error",     "none");

  readingsEndUpdate  ($hash, 1);
     
  Log3($name, $verbose, "$name - Informations related to Surveillance Station retrieved");
                
return;
}

###############################################################################
#                       Parse OpMode runliveview
###############################################################################
sub _parserunliveview {                                 ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
         
  if($hash->{HELPER}{RUNVIEW} =~ m/^live_.*hls$/x) {                           # HLS Streaming wurde aktiviert
      __parserunliveviewHLS ($paref);
  }
  
  if($hash->{HELPER}{RUNVIEW} =~ m/snap/x) {                                   # Anzeige Schnappschuß aktiviert
      __parserunliveviewSNAP ($paref);
  }

return;
}

###############################################################################
#                       Parse OpMode runliveview HLS
###############################################################################
sub __parserunliveviewHLS {                             ## no critic "not used"
  my $paref            = shift;
  my $hash             = $paref->{hash};
  my $name             = $paref->{name};
  
  my $proto            = $hash->{PROTOCOL};
  my $serveraddr       = $hash->{SERVERADDR};
  my $serverport       = $hash->{SERVERPORT};
  my $camid            = $hash->{CAMID};
  my $apivideostms     = $hash->{HELPER}{API}{VIDEOSTMS}{NAME};
  my $apivideostmspath = $hash->{HELPER}{API}{VIDEOSTMS}{PATH};
  my $apivideostmsver  = $hash->{HELPER}{API}{VIDEOSTMS}{VER};
  my $sid              = $hash->{HELPER}{SID};
         
  $hash->{HELPER}{HLSSTREAM} = "active";

  my $exturl = AttrVal($name, "livestreamprefix", "$proto://$serveraddr:$serverport");    # externe LivestreamURL setzen
  $exturl   .= "/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsver&method=Stream&cameraId=$camid&format=hls&_sid=$sid"; 
  
  if(AttrVal($name, "showStmInfoFull", 0)) {
      readingsSingleUpdate($hash,"LiveStreamUrl", $exturl, 1);
  }

  my $url = "$proto://$serveraddr:$serverport/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsver&method=Stream&cameraId=$camid&format=hls&_sid=$sid"; 

  $hash->{HELPER}{LINK} = $url;                                                           # Liveview-Link in Hash speichern und Aktivitätsstatus speichern

  Log3($name, 4, "$name - HLS Streaming of camera \"$name\" activated, Streaming-URL: $url");
  Log3($name, 3, "$name - HLS Streaming of camera \"$name\" activated");

  roomRefresh($hash,0,1,1);                                                               # kein Room-Refresh, SSCam-state-Event, SSCamSTRM-Event

return;
}

###############################################################################
#                       Parse OpMode runliveview Snap
#                       Schnapschuss liveView Anzeige
###############################################################################
sub __parserunliveviewSNAP {                            ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $data    = $paref->{data};
  my $verbose = $paref->{verbose};
  my $camname = $paref->{camname};
  
  my ($cache,@as);

  Log3($name, $verbose, "$name - Snapinfos of camera $camname retrieved");                

  if (exists($data->{'data'}{'data'}[0]{imageData})) {
      delete $hash->{HELPER}{RUNVIEW};                    
      $hash->{HELPER}{LINK} = $data->{data}{data}[0]{imageData};                  
  }
  else {
      Log3($name, 3, "$name - There is no snapshot of camera $camname to display ! Take one snapshot before.");
  }

  setReadingErrorNone($hash, 1);

  __refreshAfterSnap ($hash);                       # fallabhängige Eventgenerierung

return;
}

###############################################################################
#                       Parse OpMode getStmUrlPath
###############################################################################
sub _parsegetStmUrlPath {                               ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $data    = $paref->{data};
  my $verbose = $paref->{verbose};
  my $camname = $paref->{camname};
  
  my $proto      = $hash->{PROTOCOL};
  my $serveraddr = $hash->{SERVERADDR};
  my $serverport = $hash->{SERVERPORT};
  my $apicamver  = $hash->{HELPER}{API}{CAM}{VER};
         
  my($camforcemcast,$mjpegHttp,$multicst,$mxpegHttp,$unicastOverHttp,$unicastPath);

  if($apicamver < 9) {
      $camforcemcast   = jboolmap($data->{'data'}{'pathInfos'}[0]{'forceEnableMulticast'});
      $mjpegHttp       = $data->{'data'}{'pathInfos'}[0]{'mjpegHttpPath'};
      $multicst        = $data->{'data'}{'pathInfos'}[0]{'multicstPath'};
      $mxpegHttp       = $data->{'data'}{'pathInfos'}[0]{'mxpegHttpPath'};
      $unicastOverHttp = $data->{'data'}{'pathInfos'}[0]{'unicastOverHttpPath'};
      $unicastPath     = $data->{'data'}{'pathInfos'}[0]{'unicastPath'};
  }
  
  if($apicamver >= 9) {
      $mjpegHttp        = $data->{'data'}[0]{'mjpegHttpPath'};
      $multicst         = $data->{'data'}[0]{'multicstPath'};
      $mxpegHttp        = $data->{'data'}[0]{'mxpegHttpPath'};
      $unicastOverHttp  = $data->{'data'}[0]{'rtspOverHttpPath'};
      $unicastPath      = $data->{'data'}[0]{'rtspPath'};
  }       
                
  if (AttrVal($name, "livestreamprefix", undef)) {                                  # Rewrite Url's falls livestreamprefix ist gesetzt  
      my $exturl = AttrVal($name, "livestreamprefix", "$proto://$serveraddr:$serverport");
      $exturl    = ($exturl eq "DEF") ? "$proto://$serveraddr:$serverport" : $exturl;
    
      my @mjh    = split(/\//x, $mjpegHttp, 4);
      $mjpegHttp = $exturl."/".$mjh[3];
    
      my @mxh    = split(/\//x, $mxpegHttp, 4);
      $mxpegHttp = $exturl."/".$mxh[3];
    
      if($unicastPath) {
          my @ucp      = split(/[@\|:]/x, $unicastPath);
          my @lspf     = split(/[\/\/\|:]/x, $exturl);
          $unicastPath = $ucp[0].":".$ucp[1].":".$ucp[2]."@".$lspf[3].":".$ucp[4];
      }
  }

  my @sk     = split(/&StmKey=/x, $mjpegHttp);                                     # StmKey extrahieren
  my $stmkey = $sk[1];

  # Quotes in StmKey entfernen falls noQuotesForSID gesetzt 
  if(AttrVal($name, "noQuotesForSID",0)) {                                         # Forum: https://forum.fhem.de/index.php/topic,45671.msg938236.html#msg938236
      $mjpegHttp =~ tr/"//d;
      $mxpegHttp =~ tr/"//d;
      $stmkey    =~ tr/"//d;
  }

  # Streaminginfos in Helper speichern
  $hash->{HELPER}{STMKEYMJPEGHTTP}      = $mjpegHttp                     if($mjpegHttp);
  $hash->{HELPER}{STMKEYMXPEGHTTP}      = $mxpegHttp                     if($mxpegHttp);
  $hash->{HELPER}{STMKEYUNICSTOVERHTTP} = $unicastOverHttp               if($unicastOverHttp);
  $hash->{HELPER}{STMKEYUNICST}         = $unicastPath                   if($unicastPath);

  readingsBeginUpdate($hash);

  readingsBulkUpdate($hash,"CamForceEnableMulticast", $camforcemcast)    if($camforcemcast);
  readingsBulkUpdate($hash,"StmKey",                  $stmkey);
  readingsBulkUpdate($hash,"StmKeymjpegHttp",         $mjpegHttp)        if(AttrVal($name,"showStmInfoFull",0));
  readingsBulkUpdate($hash,"StmKeymxpegHttp",         $mxpegHttp)        if(AttrVal($name,"showStmInfoFull",0));
  readingsBulkUpdate($hash,"StmKeyUnicstOverHttp",    $unicastOverHttp)  if(AttrVal($name,"showStmInfoFull",0) && $unicastOverHttp);
  readingsBulkUpdate($hash,"StmKeyUnicst",            $unicastPath)      if(AttrVal($name,"showStmInfoFull",0) && $unicastPath);
  readingsBulkUpdate($hash,"Errorcode",               "none");
  readingsBulkUpdate($hash,"Error",                   "none");

  readingsEndUpdate($hash, 1);

  Log3($name, $verbose, "$name - Stream-URLs of camera $camname retrieved");

return;
}

###############################################################################
#                       Parse OpMode Getcaminfo
#                            Parse Caminfos    
###############################################################################
sub _parseGetcaminfo {                                  ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $data    = $paref->{data};
  my $verbose = $paref->{verbose};
  my $camname = $paref->{camname};
  
  my $lang    = AttrVal("global","language","EN");
  
  my $update_time;
  
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;

  if($lang eq "DE") {
      $update_time = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;
  } 
  else {
      $update_time = sprintf "%04d-%02d-%02d / %02d:%02d:%02d" , $year+=1900 , $mon+=1 , $mday , $hour , $min , $sec ;
  }

  my $camLiveMode = $data->{'data'}->{'cameras'}->[0]->{'camLiveMode'};              
  $camLiveMode    = $hrkeys{camLiveMode}{$camLiveMode};

  my $deviceType  = $data->{'data'}->{'cameras'}->[0]->{'deviceType'};                
  $deviceType     = $hrkeys{deviceType}{$deviceType};

  my $camStatus   = jboolmap($data->{'data'}->{'cameras'}->[0]->{'camStatus'});                
  $camStatus      = $hrkeys{camStatus}{$camStatus};

  if ($camStatus eq "enabled") {                                   
      if (ReadingsVal("$name", "Record", "Stop") eq "Start") {                 # falls Aufnahme noch läuft -> STATE = on setzen
          readingsSingleUpdate($hash,"state", "on", 0); 
      } 
      else {
          readingsSingleUpdate($hash,"state", "off", 0); 
      }
  }

  my $recStatus       = $data->{'data'}->{'cameras'}->[0]->{'recStatus'};                
  $recStatus          = $recStatus ne "0" ? "Start" : "Stop";

  my $rotate          = $data->{'data'}->{'cameras'}->[0]->{'video_rotation'};
  $rotate             = $rotate == 1 ? "true" : "false";

  my $exposuremode    = jboolmap($data->{'data'}->{'cameras'}->[0]->{'exposure_mode'});               
  $exposuremode       = $hrkeys{exposure_mode}{$exposuremode};
    
  my $exposurecontrol = jboolmap($data->{'data'}->{'cameras'}->[0]->{'exposure_control'});
  $exposurecontrol    = $hrkeys{exposure_control}{$exposurecontrol};

  my $camaudiotype    = jboolmap($data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camAudioType'});
  $camaudiotype       = $hrkeys{camAudioType}{$camaudiotype};
    
  my $pdcap           = jboolmap($data->{'data'}->{'cameras'}->[0]->{'PDCap'});

  if (!$pdcap || $pdcap == 0) {
      $pdcap = "false";
  } 
  else {
      $pdcap = "true";
  }

  $data->{'data'}->{'cameras'}->[0]->{'video_flip'}    = jboolmap($data->{'data'}->{'cameras'}->[0]->{'video_flip'});
  $data->{'data'}->{'cameras'}->[0]->{'video_mirror'}  = jboolmap($data->{'data'}->{'cameras'}->[0]->{'video_mirror'});
  $data->{'data'}->{'cameras'}->[0]->{'blPresetSpeed'} = jboolmap($data->{'data'}->{'cameras'}->[0]->{'blPresetSpeed'});

  my $clstrmno = $data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camLiveStreamNo'};
  $clstrmno++ if($clstrmno == 0);

  my $fw = $data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camFirmware'};

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "CamAudioType",       $camaudiotype);
  readingsBulkUpdate($hash, "CamFirmware",        $fw) if($fw);
  readingsBulkUpdate($hash, "CamLiveMode",        $camLiveMode);
  readingsBulkUpdate($hash, "CamLiveFps",         $data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camLiveFps'});
  readingsBulkUpdate($hash, "CamLiveResolution",  $data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camLiveResolution'});
  readingsBulkUpdate($hash, "CamLiveQuality",     $data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camLiveQuality'});
  readingsBulkUpdate($hash, "CamLiveStreamNo",    $clstrmno);
  readingsBulkUpdate($hash, "CamExposureMode",    $exposuremode);
  readingsBulkUpdate($hash, "CamExposureControl", $exposurecontrol);
  readingsBulkUpdate($hash, "CamModel",           $data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camModel'});
  readingsBulkUpdate($hash, "CamRecShare",        $data->{'data'}->{'cameras'}->[0]->{'camRecShare'});
  readingsBulkUpdate($hash, "CamRecVolume",       $data->{'data'}->{'cameras'}->[0]->{'camRecVolume'});
  readingsBulkUpdate($hash, "CamIP",              $data->{'data'}->{'cameras'}->[0]->{'host'});
  readingsBulkUpdate($hash, "CamNTPServer",       $data->{'data'}->{'cameras'}->[0]->{'time_server'}); 
  readingsBulkUpdate($hash, "CamVendor",          $data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camVendor'});
  readingsBulkUpdate($hash, "CamVideoType",       $data->{'data'}->{'cameras'}->[0]->{'camVideoType'});
  readingsBulkUpdate($hash, "CamPreRecTime",      $data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camPreRecTime'});
  readingsBulkUpdate($hash, "CamPort",            $data->{'data'}->{'cameras'}->[0]->{'port'});
  readingsBulkUpdate($hash, "CamPtSpeed",         $data->{'data'}->{'cameras'}->[0]->{'ptSpeed'}) if($deviceType =~ /PTZ/x);
  readingsBulkUpdate($hash, "CamblPresetSpeed",   $data->{'data'}->{'cameras'}->[0]->{'blPresetSpeed'});
  readingsBulkUpdate($hash, "CamVideoMirror",     $data->{'data'}->{'cameras'}->[0]->{'video_mirror'});
  readingsBulkUpdate($hash, "CamVideoFlip",       $data->{'data'}->{'cameras'}->[0]->{'video_flip'});
  readingsBulkUpdate($hash, "CamVideoRotate",     $rotate);
  readingsBulkUpdate($hash, "CapPIR",             $pdcap);
  readingsBulkUpdate($hash, "Availability",       $camStatus);
  readingsBulkUpdate($hash, "DeviceType",         $deviceType);
  readingsBulkUpdate($hash, "LastUpdateTime",     $update_time);
  readingsBulkUpdate($hash, "Record",             $recStatus);
  readingsBulkUpdate($hash, "UsedSpaceMB",        $data->{'data'}{'cameras'}[0]{'volume_space'});
  readingsBulkUpdate($hash, "VideoFolder",        AttrVal($name, "videofolderMap", $data->{'data'}{'cameras'}[0]{'folder'}));
  readingsBulkUpdate($hash, "Errorcode",          "none");
  readingsBulkUpdate($hash, "Error",              "none");
  readingsEndUpdate($hash, 1);
   
  $hash->{MODEL} = ReadingsVal($name,"CamVendor","")." - ".ReadingsVal($name,"CamModel","CAM") if(IsModelCam($hash));                   
  Log3($name, $verbose, "$name - Informations of camera $camname retrieved");

  __getPtzPresetList($hash);                               # Preset/Patrollisten in Hash einlesen zur PTZ-Steuerung
  __getPtzPatrolList($hash);

return;
}

###############################################################################
#                       Parse OpMode Getptzlistpatrol
#                            Parse PTZ-ListPatrols    
###############################################################################
sub _parseGetptzlistpatrol {                            ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $data    = $paref->{data};
  my $verbose = $paref->{verbose};
  my $camname = $paref->{camname};
  
  my $patrolcnt = $data->{'data'}->{'total'};
  my $cnt       = 0;

  delete $hash->{HELPER}{ALLPATROLS};
  
  while ($cnt < $patrolcnt) {                                               # alle Patrols der Kamera mit Id's in Hash einlesen
      my $patrolid   = $data->{'data'}->{'patrols'}->[$cnt]->{'id'};
      my $patrolname = $data->{'data'}->{'patrols'}->[$cnt]->{'name'};
      $patrolname    =~ s/\s+/_/gx;                                         # Leerzeichen im Namen ersetzen falls vorhanden
    
      $hash->{HELPER}{ALLPATROLS}{$patrolname} = $patrolid;
      $cnt += 1;
  }

  my @patrolkeys = sort(keys(%{$hash->{HELPER}{ALLPATROLS}}));
  my $patrollist = join ",", @patrolkeys;

  readingsBeginUpdate ($hash);
  readingsBulkUpdate  ($hash, "Patrols",   $patrollist);
  readingsBulkUpdate  ($hash, "Errorcode", "none"     );
  readingsBulkUpdate  ($hash, "Error",     "none"     );
  readingsEndUpdate   ($hash, 1);

  $hash->{".ptzhtml"} = "";                                                 # ptzPanel wird neu eingelesen in FWdetailFn
     
  Log3($name, $verbose, "$name - PTZ Patrols of camera $camname retrieved");

return;
}

###############################################################################
#                       Parse OpMode Getptzlistpreset
#                            Parse PTZ-ListPresets   
###############################################################################
sub _parseGetptzlistpreset {                            ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $data    = $paref->{data};
  my $verbose = $paref->{verbose};
  my $camname = $paref->{camname};
  
  my $presetcnt = $data->{'data'}->{'total'};
  my $cnt       = 0;

  # alle Presets der Kamera mit Id's in Assoziatives Array einlesen
  delete $hash->{HELPER}{ALLPRESETS};                                      # besetehende Presets löschen und neu einlesen
  my $home = "not set";
  
  while ($cnt < $presetcnt) {
      my $presid   = $data->{'data'}->{'presets'}->[$cnt]->{'position'};
      my $presname = $data->{'data'}->{'presets'}->[$cnt]->{'name'};
      $presname    =~ s/\s+/_/gx;                                          # Leerzeichen im Namen ersetzen falls vorhanden  
      $hash->{HELPER}{ALLPRESETS}{$presname} = "$presid";
      my $ptype = $data->{'data'}->{'presets'}->[$cnt]->{'type'};
      
      if ($ptype) {
          $home = $presname;
      }
      
      $cnt += 1;
  }

  my @preskeys   = sort(keys(%{$hash->{HELPER}{ALLPRESETS}}));
  my $presetlist = join(",", @preskeys);

  readingsBeginUpdate ($hash);
  readingsBulkUpdate  ($hash, "Presets",    $presetlist);
  readingsBulkUpdate  ($hash, "PresetHome", $home      );
  readingsBulkUpdate  ($hash, "Errorcode",  "none"     );
  readingsBulkUpdate  ($hash, "Error",      "none"     );
  readingsEndUpdate   ($hash, 1);

  addptzattr($name);                                                        # PTZ Panel neu erstellen
             
  Log3($name, $verbose, "$name - PTZ Presets of camera $camname retrieved");

return;
}

###############################################################################
#                       Parse OpMode Getcapabilities 
###############################################################################
sub _parseGetcapabilities {                             ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $data    = $paref->{data};
  my $verbose = $paref->{verbose};
  my $camname = $paref->{camname};
  
  my $ptzfocus = $data->{'data'}{'ptzFocus'};
  $ptzfocus    = $hrkeys{ptzFocus}{$ptzfocus};
    
  my $ptztilt  = $data->{'data'}{'ptzTilt'};
  $ptztilt     = $hrkeys{ptzTilt}{$ptztilt};
    
  my $ptzzoom  = $data->{'data'}{'ptzZoom'};
  $ptzzoom     = $hrkeys{ptzZoom}{$ptzzoom};
    
  my $ptzpan   = $data->{'data'}{'ptzPan'};
  $ptzpan      = $hrkeys{ptzPan}{$ptzpan};                

  my $ptziris  = $data->{'data'}{'ptzIris'};
  $ptziris     = $hrkeys{ptzIris}{$ptziris};              

  $data->{'data'}{'ptzHasObjTracking'} = jboolmap($data->{'data'}{'ptzHasObjTracking'});
  $data->{'data'}{'audioOut'}          = jboolmap($data->{'data'}{'audioOut'});
  $data->{'data'}{'ptzSpeed'}          = jboolmap($data->{'data'}{'ptzSpeed'});
  $data->{'data'}{'ptzAbs'}            = jboolmap($data->{'data'}{'ptzAbs'});
  $data->{'data'}{'ptzAutoFocus'}      = jboolmap($data->{'data'}{'ptzAutoFocus'});
  $data->{'data'}{'ptzHome'}           = jboolmap($data->{'data'}{'ptzHome'});

  readingsBeginUpdate($hash);
  readingsBulkUpdate ($hash,"CapPTZAutoFocus",    $data->{'data'}{'ptzAutoFocus'}      );
  readingsBulkUpdate ($hash,"CapAudioOut",        $data->{'data'}{'audioOut'}          );
  readingsBulkUpdate ($hash,"CapChangeSpeed",     $data->{'data'}{'ptzSpeed'}          );
  readingsBulkUpdate ($hash,"CapPTZHome",         $data->{'data'}{'ptzHome'}           );
  readingsBulkUpdate ($hash,"CapPTZAbs",          $data->{'data'}{'ptzAbs'}            );
  readingsBulkUpdate ($hash,"CapPTZDirections",   $data->{'data'}{'ptzDirection'}      );
  readingsBulkUpdate ($hash,"CapPTZFocus",        $ptzfocus                            );
  readingsBulkUpdate ($hash,"CapPTZIris",         $ptziris                             );
  readingsBulkUpdate ($hash,"CapPTZObjTracking",  $data->{'data'}{'ptzHasObjTracking'} );
  readingsBulkUpdate ($hash,"CapPTZPan",          $ptzpan                              );
  readingsBulkUpdate ($hash,"CapPTZPresetNumber", $data->{'data'}{'ptzPresetNumber'}   );
  readingsBulkUpdate ($hash,"CapPTZTilt",         $ptztilt                             );
  readingsBulkUpdate ($hash,"CapPTZZoom",         $ptzzoom                             );
  readingsBulkUpdate ($hash,"Errorcode",          "none"                               );
  readingsBulkUpdate ($hash,"Error",              "none"                               );
  readingsEndUpdate  ($hash, 1);
  
  Log3($name, $verbose, "$name - Capabilities of camera $camname retrieved");

return;
}

###############################################################################
#                       Parse OpMode getmotionenum 
###############################################################################
sub _parsegetmotionenum {                               ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $data    = $paref->{data};
  my $verbose = $paref->{verbose};
  my $camname = $paref->{camname};
  
  my $motdetsc           = $data->{'data'}{'MDParam'}{'source'};
  $motdetsc              = $hrkeys{source}{$motdetsc};

  my $sensitivity_camCap = jboolmap($data->{'data'}{'MDParam'}{'sensitivity'}{'camCap'});
  my $sensitivity_value  = $data->{'data'}{'MDParam'}{'sensitivity'}{'value'};
  my $sensitivity_ssCap  = jboolmap($data->{'data'}{'MDParam'}{'sensitivity'}{'ssCap'});

  my $threshold_camCap   = jboolmap($data->{'data'}{'MDParam'}{'threshold'}{'camCap'});
  my $threshold_value    = $data->{'data'}{'MDParam'}{'threshold'}{'value'};
  my $threshold_ssCap    = jboolmap($data->{'data'}{'MDParam'}{'threshold'}{'ssCap'});

  my $percentage_camCap  = jboolmap($data->{'data'}{'MDParam'}{'percentage'}{'camCap'});
  my $percentage_value   = $data->{'data'}{'MDParam'}{'percentage'}{'value'};
  my $percentage_ssCap   = jboolmap($data->{'data'}{'MDParam'}{'percentage'}{'ssCap'});

  my $objectSize_camCap  = jboolmap($data->{'data'}{'MDParam'}{'objectSize'}{'camCap'});
  my $objectSize_value   = $data->{'data'}{'MDParam'}{'objectSize'}{'value'};
  my $objectSize_ssCap   = jboolmap($data->{'data'}{'MDParam'}{'objectSize'}{'ssCap'});

  if ($motdetsc eq "Camera") {                    
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

  if ($motdetsc eq "SVS") {                    
      if ($sensitivity_ssCap) {
          $motdetsc .= ", sensitivity: $sensitivity_value";
      }
      if ($threshold_ssCap) {
          $motdetsc .= ", threshold: $threshold_value";
      }
  }

  readingsBeginUpdate ($hash);
  readingsBulkUpdate  ($hash, "CamMotDetSc", $motdetsc);
  readingsBulkUpdate  ($hash, "Errorcode",   "none"   );
  readingsBulkUpdate  ($hash, "Error",       "none"   );
  readingsEndUpdate   ($hash, 1);

  Log3($name, $verbose, "$name - Enumerate motion detection parameters of camera $camname retrieved");

return;
}

###############################################################################
#                       Parse OpMode geteventlist 
###############################################################################
sub _parsegeteventlist {                                ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $data    = $paref->{data};
  my $verbose = $paref->{verbose};
  my $camname = $paref->{camname};
  
  my $lang      = AttrVal("global","language","EN"); 
  
  my $eventnum  = $data->{'data'}{'total'};
  my $lrec      = $data->{'data'}{'events'}[0]{name};
  my $lrecid    = $data->{'data'}{'events'}[0]{'eventId'}; 

  my ($lastrecstarttime,$lastrecstoptime);

  if ($eventnum > 0) {
      $lastrecstarttime = $data->{'data'}{'events'}[0]{startTime};
      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($lastrecstarttime);
      
      if($lang eq "DE") {
          $lastrecstarttime = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;
      } 
      else {
          $lastrecstarttime = sprintf "%04d-%02d-%02d / %02d:%02d:%02d" , $year+=1900 , $mon+=1 , $mday , $hour , $min , $sec ;
      }
      
      $lastrecstoptime                                      = $data->{'data'}{'events'}[0]{stopTime};
      ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($lastrecstoptime);
      $lastrecstoptime                                      = sprintf "%02d:%02d:%02d" , $hour , $min , $sec ;
  }

  readingsBeginUpdate ($hash);
  readingsBulkUpdate  ($hash, "CamEventNum",    $eventnum);
  readingsBulkUpdate  ($hash, "CamLastRec",     $lrec) if($lrec); 
  readingsBulkUpdate  ($hash, "CamLastRecId",   $lrecid) if($lrecid);                 
  readingsBulkUpdate  ($hash, "CamLastRecTime", $lastrecstarttime." - ". $lastrecstoptime) if($lastrecstarttime);                
  readingsBulkUpdate  ($hash, "Errorcode",      "none");
  readingsBulkUpdate  ($hash, "Error",          "none");
  readingsEndUpdate   ($hash, 1);

  Log3($name, $verbose, "$name - Query eventlist of camera $camname retrieved");

  if($hash->{HELPER}{CANSENDREC} || $hash->{HELPER}{CANTELEREC} || $hash->{HELPER}{CANCHATREC}) {        # Versand Aufnahme initiieren
      __getRec($hash);
  }

return;
}

###############################################################################
#                       Parse OpMode gopreset 
#               eine Presetposition wurde angefahren
###############################################################################
sub _parsegopreset {                                    ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $camname = $paref->{camname};
  
  my $st = (ReadingsVal("$name", "Record", "Stop") eq "Start") ? "on" : "off";           # falls Aufnahme noch läuft -> state = on setzen
  readingsSingleUpdate($hash,"state", $st, 0); 
  DoTrigger($name,"move stop");

  setReadingErrorNone( $hash, 1 );            
  Log3               ( $name, 3, qq{$name - Camera $camname was moved to the "$hash->{HELPER}{GOPRESETNAME}" position} );

return;
}

###############################################################################
#                       Parse OpMode getsnapinfo 
###############################################################################
sub _parsegetsnapinfo {                                 ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $verbose = $paref->{verbose};
  my $camname = $paref->{camname};
  
  my $lang    = AttrVal("global","language","EN");
  
  my ($cache,@as);
  
  $paref->{aref} = \@as;

  Log3($name, $verbose, "$name - Snapinfos of camera $camname retrieved");

  __saveLastSnapToCache ($paref);                                               # aktuellsten Snap in Cache zur Anzeige durch streamDev "lastsnap" speichern                
  __doSnapRotation      ($paref);                                               # Rotationsfeature
  
  setReadingErrorNone   ($hash, 1);               

  closeTrans            ($hash);                                                # Transaktion beenden falls gestartet
  __refreshAfterSnap    ($hash);                                                # fallabhängige Eventgenerierung 

return;
}

###############################################################################
#                       Parse OpMode getsnapgallery 
###############################################################################
sub _parsegetsnapgallery {                              ## no critic "not used"
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $data    = $paref->{data};                                                                              # decodierte JSON Daten
  my $verbose = $paref->{verbose};
  my $camname = $paref->{camname};
  
  my $lang    = AttrVal("global","language","EN");
  
  my @as;
  
  $paref->{aref} = \@as;

  Log3($name, $verbose, "$name - Snapinfos of camera $camname retrieved");
  
  __saveLastSnapToCache ($paref);                                                                            # aktuellsten Snap in Cache zur Anzeige durch streamDev "lastsnap" speichern
  __doSnapRotation      ($paref);                                                                            # Rotationsfeature
  __moveSnapCacheToOld  ($paref);                                                                            # bestehende Schnappschußdaten aus SNAPHASH Cache auf SNAPOLDHASH schreiben und in SNAPHASH löschen
       
       
  #####   transaktionaler Versand der erzeugten Schnappschüsse #####
  ##################################################################                
  if($hash->{HELPER}{CANSENDSNAP} || $hash->{HELPER}{CANTELESNAP} || $hash->{HELPER}{CANCHATSNAP}) {         # es soll die Anzahl "$hash->{HELPER}{SNAPNUM}" Schnappschüsse versendet werden
      my $tac = openOrgetTrans($hash);                                                                       # Transaktion vorhandenen Code holen
      
      $paref->{tac} = $tac;
      my $sn = __insertSnapsToCache ($paref);                                                                # neu erzeugte Snaps in SNAPHASH eintragen

      $paref->{sn} = $sn;
      __copySnapsBackFromOld ($paref);                                                                       # gesicherte Schnappschußdaten aus SNAPOLDHASH an SNAPHASH anhängen
    
      # Schnappschüsse als Email / Telegram / SSChatBot versenden
      ###########################################################
      my $cache = cache($name, "c_init");                                                                    # Cache initialisieren  
      if(!$cache || $cache eq "internal" ) { 
          prepareSendData ($hash, "getsnapgallery", $data{SSCam}{$name}{SENDSNAPS}{$tac});
      } 
      else {
          prepareSendData ($hash, "getsnapgallery", "{SENDSNAPS}{$tac}");
      }  
  } 
  else {
      # Schnappschußgalerie wird bereitgestellt (Attr snapGalleryBoost=1) bzw. gleich angezeigt 
      # (Attr snapGalleryBoost=0)         !!  kein Versand !!
      #########################################################################################     
      $hash->{HELPER}{TOTALCNT} = $data->{data}{total};                                                   # total Anzahl Schnappschüsse
    
      my $sn = __insertSnapsToCache ($paref);                                                             # neu erzeugte Snaps in SNAPHASH eintragen
    
      $paref->{sn} = $sn;
      __copySnapsBackFromOld ($paref);                                                                    # gesicherte Schnappschußdaten aus SNAPOLDHASH an SNAPHASH anhängen
    
      # Direktausgabe Snaphash wenn nicht gepollt wird
      if(!AttrVal($name, "snapGalleryBoost",0)) {  
          my %pars = ( 
              linkparent => $name,
              linkname   => '',
              ftui       => 0
          );
          
          my $htmlCode = composeGallery(\%pars);
        
          for (my $c=1; (defined($hash->{HELPER}{CL}{$c})); $c++ ) {
              asyncOutput($hash->{HELPER}{CL}{$c},"$htmlCode");                       
          }
          
          delete($data{SSCam}{$name}{SNAPHASH});                        # Snaphash Referenz löschen
          delClHash  ($name);
      }
  }

  setReadingErrorNone( $hash, 1 );               

  delete $hash->{HELPER}{GETSNAPGALLERY};                               # Steuerbit getsnapgallery      
  delete $data{SSCam}{$name}{SNAPOLDHASH};
  
  closeTrans         ($hash);                                           # Transaktion beenden
  __refreshAfterSnap ($hash);                                           # fallabhängige Eventgenerierung 

return;
}

###############################################################################
#  aktuellsten Snap in Cache zur Anzeige durch streamDev "lastsnap" speichern 
###############################################################################
sub __saveLastSnapToCache {
  my $paref = shift;
  my $name  = $paref->{name};
  my $data  = $paref->{data};                                                                 # decodierte JSON Daten
  
  my $cache = cache($name, "c_init");                                                         # Cache initialisieren  
  
  Log3($name, 1, "$name - Fall back to internal Cache due to preceding failure.") if(!$cache);                                 

  if(!$cache || $cache eq "internal" ) {
      $data{SSCam}{$name}{LASTSNAP} = $data->{data}{data}[0]{imageData};
  } 
  else {
      cache($name, "c_write", "{LASTSNAP}", $data->{data}{data}[0]{imageData});                           
  }

return;
}

###############################################################################
#           Versionsverwaltung der Snapreadings (Rotationsfeature) 
###############################################################################
sub __doSnapRotation {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $data    = $paref->{data};                                                                                  # decodierte JSON Daten
  my $camname = $paref->{camname};
  my $aref    = $paref->{aref};
  
  my $lang    = AttrVal("global","language","EN");              

  my %snaps  = ( 0 => {'createdTm' => 'n.a.', 'fileName' => 'n.a.','snapid' => 'n.a.'} );                        # Hilfshash 
  my ($k,$l) = (0,0);              

  if($data->{'data'}{'data'}[0]{'createdTm'}) {
      while ($data->{'data'}{'data'}[$k]) {
          
          if(!$data->{'data'}{'data'}[$k]{'camName'} || $data->{'data'}{'data'}[$k]{'camName'} ne $camname) {    # Forum:#97706
              $k += 1;
              next;
          }
        
          my @t = split(" ", FmtDateTime($data->{data}{data}[$k]{createdTm}));
          my @d = split("-", $t[0]);
          
          my $createdTm;
          if($lang eq "DE") {
              $createdTm = "$d[2].$d[1].$d[0] / $t[1]";
          } 
          else {
              $createdTm = "$d[0]-$d[1]-$d[2] / $t[1]";
          }
        
          $snaps{$l}{createdTm} = $createdTm;
          $snaps{$l}{fileName}  = $data->{data}{data}[$k]{fileName};
          $snaps{$l}{snapid}    = $data->{data}{data}[$k]{id};
        
          Log3($name,4, "$name - Snap [$l]: ID => $data->{data}{data}[$k]{id}, File => $data->{data}{data}[$k]{fileName}, Created => $createdTm");
        
          $l += 1;
          $k += 1;
      }   
  }
 
  #####            Verwaltung Schnappschußrotation            #####
  ################################################################# 
  my $rotnum = AttrVal    ($name, "snapReadingRotate", 0     );
  my $o      = ReadingsVal($name, "LastSnapId",        "n.a."); 

  if($rotnum && "$o" ne "$snaps{0}{snapid}") {
      @$aref = sort{$b<=>$a}keys %snaps;
      for my $key (@$aref) {
          rotateReading($hash,"LastSnapId",$snaps{$key}{snapid},$rotnum,1);
          rotateReading($hash,"LastSnapFilename",$snaps{$key}{fileName},$rotnum,1);
          rotateReading($hash,"LastSnapTime",$snaps{$key}{createdTm},$rotnum,1);                    
      }
  } 
  else {
      @$aref = sort{$a<=>$b}keys %snaps;
      rotateReading($hash,"LastSnapId",$snaps{$$aref[0]}{snapid},$rotnum,1);
      rotateReading($hash,"LastSnapFilename",$snaps{$$aref[0]}{fileName},$rotnum,1);
      rotateReading($hash,"LastSnapTime",$snaps{$$aref[0]}{createdTm},$rotnum,1);                  
  }      
  
  undef %snaps;

return;
}

###############################################################################
# bestehende Schnappschußdaten aus SNAPHASH Cache auf SNAPOLDHASH schreiben 
# und in SNAPHASH löschen
###############################################################################
sub __moveSnapCacheToOld {
  my $paref = shift;
  my $name  = $paref->{name};
  my $aref  = $paref->{aref};

  my $cache = cache($name, "c_init");                                                                    # Cache initialisieren  
  
  Log3($name, 1, "$name - Fall back to internal Cache due to preceding failure.") if(!$cache);                                 
  
  if(!$cache || $cache eq "internal" ) {
      if($data{SSCam}{$name}{SNAPHASH}) {
          for my $key (sort(keys%{$data{SSCam}{$name}{SNAPHASH}})) {
              $data{SSCam}{$name}{SNAPOLDHASH}{$key} = delete($data{SSCam}{$name}{SNAPHASH}{$key});
          }
      }
  } 
  else {              
      extractTIDfromCache (                                                                              # alle keys aus vorhandenem SNAPHASH auslesen
                            { name  => $name,                                                           
                              media => "SNAPHASH",
                              mode  => "readkeys",
                              aref  => $aref
                            } 
                          );                            
      
      my (%seen,$g);
      my @unique = sort{$a<=>$b} grep { !$seen{$_}++ } @$aref;
      
      for my $key (@unique) {
          $g = cache($name, "c_read",   "{SNAPHASH}{$key}{snapid}"          );          
          cache     ($name, "c_write",  "{SNAPOLDHASH}{$key}{snapid}",    $g) if(defined $g);    
          cache     ($name, "c_remove", "{SNAPHASH}{$key}{snapid}"          );
          $g = cache($name, "c_read",   "{SNAPHASH}{$key}{createdTm}"       );
          cache     ($name, "c_write",  "{SNAPOLDHASH}{$key}{createdTm}", $g) if(defined $g); 
          cache     ($name, "c_remove", "{SNAPHASH}{$key}{createdTm}"       );
          $g = cache($name, "c_read",   "{SNAPHASH}{$key}{fileName}"        );                               
          cache     ($name, "c_write",  "{SNAPOLDHASH}{$key}{fileName}",  $g) if(defined $g);  
          cache     ($name, "c_remove", "{SNAPHASH}{$key}{fileName}"        );  
          $g = cache($name, "c_read",   "{SNAPHASH}{$key}{imageData}"       );
          cache     ($name, "c_write",  "{SNAPOLDHASH}{$key}{imageData}", $g) if(defined $g);
          cache     ($name, "c_remove", "{SNAPHASH}{$key}{imageData}"       );                                                     
      }
  
      undef $g;
  }

return;
}

###############################################################################
#                neu erzeugte Snaps in Cache eintragen
#                SNAPHASH  = Anzeigehash im Cache für Galerie
#                SENDSNAPS = zu versendende Snaps im Cache Hash
###############################################################################
sub __insertSnapsToCache {
  my $paref   = shift;
  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $data    = $paref->{data};                                                                              # decodierte JSON Daten
  my $camname = $paref->{camname};
  my $tac     = $paref->{tac} // q{};

  my $lang    = AttrVal("global","language","EN");
  
  my $i  = 0;
  my $sn = 0;
  
  my $cache;

  while ($data->{'data'}{'data'}[$i]) {
      
      if(!$data->{'data'}{'data'}[$i]{'camName'} || $data->{'data'}{'data'}[$i]{'camName'} ne $camname) {    # Forum:#97706
          $i += 1;
          next;
      }   
      
      my $snapid    = $data->{data}{data}[$i]{id};
      my $fileName  = $data->{data}{data}[$i]{fileName};
      my $imageData = $data->{data}{data}[$i]{imageData};                                                    # Image data of snapshot in base64 format 

      my @t = split(" ", FmtDateTime($data->{data}{data}[$i]{createdTm}));
      my @d = split("-", $t[0]);
      
      my $createdTm;
      if($lang eq "DE") {
          $createdTm = "$d[2].$d[1].$d[0] / $t[1]";
      } 
      else {
          $createdTm = "$d[0]-$d[1]-$d[2] / $t[1]";
      }
      
      # Schnappschuss Hash zum Versand wird erstellt
      ##############################################
      if($hash->{HELPER}{CANSENDSNAP} || $hash->{HELPER}{CANTELESNAP} || $hash->{HELPER}{CANCHATSNAP}) {
          if($tac) {
              $cache = cache($name, "c_init");                                                               # Cache initialisieren  
              
              Log3($name, 1, "$name - Fall back to internal Cache due to preceding failure.") if(!$cache);                                 
              
              if(!$cache || $cache eq "internal" ) {
                  $data{SSCam}{$name}{SENDSNAPS}{$tac}{$sn}{snapid}    = $snapid;
                  $data{SSCam}{$name}{SENDSNAPS}{$tac}{$sn}{createdTm} = $createdTm;
                  $data{SSCam}{$name}{SENDSNAPS}{$tac}{$sn}{fileName}  = $fileName;
                  $data{SSCam}{$name}{SENDSNAPS}{$tac}{$sn}{imageData} = $imageData;
              } 
              else {
                  cache($name, "c_write", "{SENDSNAPS}{$tac}{$sn}{snapid}"    ,$snapid);
                  cache($name, "c_write", "{SENDSNAPS}{$tac}{$sn}{createdTm}" ,$createdTm);
                  cache($name, "c_write", "{SENDSNAPS}{$tac}{$sn}{fileName}"  ,$fileName); 
                  cache($name, "c_write", "{SENDSNAPS}{$tac}{$sn}{imageData}" ,$imageData);                             
              }
              
              Log3($name,4, "$name - Snap '$sn' (tac: $tac) added to send gallery hash: ID => $snapid, File => $fileName, Created => $createdTm");
          }
          else {
              Log3($name, 1, "$name - ERROR - try to send snapshots without transaction. Send process is discarded.");
          }
      }
  
      # Snaphash erstellen für Galerie
      ################################  
      $cache = cache($name, "c_init");                                                                      # Cache initialisieren  
      
      Log3($name, 1, "$name - Fall back to internal Cache due to preceding failure.") if(!$cache);                                 
      
      if(!$cache || $cache eq "internal" ) {
          $data{SSCam}{$name}{SNAPHASH}{$sn}{snapid}    = $snapid;
          $data{SSCam}{$name}{SNAPHASH}{$sn}{createdTm} = $createdTm;
          $data{SSCam}{$name}{SNAPHASH}{$sn}{fileName}  = $fileName;
          $data{SSCam}{$name}{SNAPHASH}{$sn}{imageData} = $imageData;
      } 
      else {
          cache($name, "c_write", "{SNAPHASH}{$sn}{snapid}",    $snapid   );
          cache($name, "c_write", "{SNAPHASH}{$sn}{createdTm}", $createdTm);
          cache($name, "c_write", "{SNAPHASH}{$sn}{fileName}",  $fileName );  
          cache($name, "c_write", "{SNAPHASH}{$sn}{imageData}", $imageData);                                
      }
      
      Log3($name, 4, "$name - Snap '$sn' added to gallery view hash: SN => $sn, ID => $snapid, File => $fileName, Created => $createdTm");
    
      $sn += 1;
      $i  += 1;
    
      undef $imageData;
      undef $fileName;
      undef $createdTm;
  }

return $sn;
}

###############################################################################
#     gesicherte Schnappschußdaten aus Cache SNAPOLDHASH an 
#     Cache SNAPHASH anhängen
###############################################################################
sub __copySnapsBackFromOld {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $sn    = $paref->{sn};                   # letzte lfd. Nummer aktueller Snaphash
  
  my $snapnum = $hash->{HELPER}{SNAPLIMIT} // $defSlim;
  my $sgn     = AttrVal($name, "snapGalleryNumber", $snapnum);
  my $ss      = $sn;
  $sn         = 0; 

  my $cache   = cache($name, "c_init");                                                                     # Cache initialisieren  
  
  Log3($name, 1, "$name - Fall back to internal Cache due to preceding failure.") if(!$cache);                                 
  
  if(!$cache || $cache eq "internal" ) {
      if($data{SSCam}{$name}{SNAPOLDHASH} && $sgn > $ss) {                        
          for my $kn ($ss..($sgn-1)) {
              $data{SSCam}{$name}{SNAPHASH}{$kn}{snapid}    = delete $data{SSCam}{$name}{SNAPOLDHASH}{$sn}{snapid};
              $data{SSCam}{$name}{SNAPHASH}{$kn}{createdTm} = delete $data{SSCam}{$name}{SNAPOLDHASH}{$sn}{createdTm};
              $data{SSCam}{$name}{SNAPHASH}{$kn}{fileName}  = delete $data{SSCam}{$name}{SNAPOLDHASH}{$sn}{fileName};
              $data{SSCam}{$name}{SNAPHASH}{$kn}{imageData} = delete $data{SSCam}{$name}{SNAPOLDHASH}{$sn}{imageData}; 
              $sn += 1;                            
          }
      }
  } 
  else {
      my $g;      
      for my $kn ($ss..($sgn-1)) {                                                 
          $g = cache($name, "c_read",   "{SNAPOLDHASH}{$sn}{snapid}"    );                       
          cache     ($name, "c_write",  "{SNAPHASH}{$kn}{snapid}",    $g) if(defined $g);
          cache     ($name, "c_remove", "{SNAPOLDHASH}{$sn}{snapid}"    );
          $g = cache($name, "c_read",   "{SNAPOLDHASH}{$sn}{createdTm}" );
          cache     ($name, "c_write",  "{SNAPHASH}{$kn}{createdTm}", $g) if(defined $g);
          cache     ($name, "c_remove", "{SNAPOLDHASH}{$sn}{createdTm}" );
          $g = cache($name, "c_read",   "{SNAPOLDHASH}{$sn}{fileName}"  );
          cache     ($name, "c_write",  "{SNAPHASH}{$kn}{fileName}",  $g) if(defined $g);  
          cache     ($name, "c_remove", "{SNAPOLDHASH}{$sn}{fileName}"  );
          $g = cache($name, "c_read",   "{SNAPOLDHASH}{$sn}{imageData}" );
          cache     ($name, "c_write",  "{SNAPHASH}{$kn}{imageData}", $g) if(defined $g);                                    
          cache     ($name, "c_remove", "{SNAPOLDHASH}{$sn}{imageData}" );
          $sn += 1;                            
      }  

      undef $g;      
  }

return;
}

###############################################################################
#           fallabhängige Eventgenerierung nach Snap Erstellung 
###############################################################################
sub __refreshAfterSnap {
  my $hash   = shift;
  
  if ($hash->{HELPER}{INFORM} || $hash->{HELPER}{LSNAPBYSTRMDEV}) {     # Snap durch SSCamSTRM-Device ausgelöst
      roomRefresh($hash,0,0,1);                                         # kein Room-Refresh, kein SSCam-state-Event, SSCamSTRM-Event
      delete $hash->{HELPER}{LSNAPBYSTRMDEV};
  } 
  elsif ($hash->{HELPER}{LSNAPBYDEV}) {
      roomRefresh($hash,0,1,0);                                         # kein Room-Refresh, SSCam-state-Event, kein SSCamSTRM-Event
      delete $hash->{HELPER}{LSNAPBYDEV};
  } 
  else {
       roomRefresh($hash,0,0,0);                                        # kein Room-Refresh, SSCam-state-Event, SSCamSTRM-Event
  }

return;
}

###############################################################################
#               Eigenschaften des Device liefern
###############################################################################
sub IsModelCam {                                                           # Modelleigenschaft liefern Cam-> 1 , sonst 0
  my $hash = shift;
  
  my $m = ($hash->{MODEL} ne "SVS") ? 1 : 0;
  
return $m;
}

sub IsCapHLS {                                                            # HLS Lieferfähigkeit (existiert "SYNO.SurveillanceStation.VideoStream" & Reading)
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  my $cap    = 0;
  my $api    = $hash->{HELPER}{API}{VIDEOSTMS}{VER};
  my $csf    = (ReadingsVal($name,"CamStreamFormat","MJPEG") eq "HLS")?1:0;
  
  $cap = 1 if($api && $csf);
  
return $cap;
}

sub IsCapZoom {                                                           # PTZ Zoom Eigenschaft
  my $hash = shift;
  my $name = $hash->{NAME};

  my $cap  = ReadingsVal($name, "CapPTZZoom", "false") ne "false" ? 1 : 0;
  
return $cap;
}

sub IsCapPTZ {                                                            # PTZ Directions möglich Eigenschaft
  my $hash = shift;
  my $name = $hash->{NAME};
  
  my $cap  = ReadingsVal($name, "DeviceType", "Camera") eq "PTZ" ? 1 : 0;
  
return $cap;
}

sub IsCapPTZPan {                                                         # PTZ Pan Eigenschaft
  my $hash = shift;
  my $name = $hash->{NAME};
  
  my $cap  = (ReadingsVal($name, "CapPTZPan", "false") ne "false" && !AttrVal($name, "ptzNoCapPrePat", 0)) ? 1 : 0;
  
return $cap;
}

sub IsCapPTZTilt {                                                        # PTZ Tilt Eigenschaft
  my $hash = shift;
  my $name = $hash->{NAME};
  
  my $cap  = ReadingsVal($name, "CapPTZTilt", "false") ne "false" ? 1 : 0;
  
return $cap;
}

sub IsCapPTZObjTrack {                                                    # PTZ Objekt Tracking Eigenschaft
  my $hash = shift;
  my $name = $hash->{NAME};
  
  my $cap  = ReadingsVal($name, "CapPTZObjTracking", "false") ne "false" ? 1 : 0;
  
return $cap;
}

sub IsCapPTZAbs {                                                        # PTZ go to absolute Position Eigenschaft
  my $hash = shift;
  my $name = $hash->{NAME};
  
  my $cap  = ReadingsVal($name, "CapPTZAbs", "false") ne "false" ? 1 : 0;
  
return $cap;
}

sub IsCapPTZDir {                                                        # PTZ Directions möglich Eigenschaft
  my $hash = shift;
  my $name = $hash->{NAME};
  
  my $cap  = ReadingsVal($name, "CapPTZDirections", 0) > 0 ? 1 : 0;
  
return $cap;
}

sub IsCapPIR {                                                           # hat Kamera einen PIR
  my $hash = shift;
  my $name = $hash->{NAME};
  
  my $cap  = ReadingsVal($name, "CapPIR", "false") ne "false" ? 1 : 0;
  
return $cap;
}

sub IsModelMaster {                                                     # ist des Streamdevices MODEL=master                                                          
  my $model = shift;

  my $mm = $model eq "master" ? 1 : 0;
  
return $mm;
}

######################################################################################
#      Funktion für SSCamSTRM-Devices
#
#      $camname = Name der Kamaera (Parent-Device)
#      $strmdev = Name des Streaming-Devices
#      $fmt     = Streaming Format (Vergleich auf "eq" !)
#      $omodel  = originäres MODEL des Streaming Devices (wg. master)
#      $oname   = originäres NAME des Streaming Devices (wg. master)
#
######################################################################################
sub streamDev {                                               ## no critic 'complexity'
  my $paref      = shift;
  my $camname    = $paref->{linkparent}; 
  my $strmdev    = $paref->{linkname}; 
  my $fmt        = $paref->{linkmodel};
  my $omodel     = $paref->{omodel};  
  my $oname      = $paref->{oname}; 
  my $ftui       = $paref->{ftui};
  
  my $hash       = $defs{$camname};
  my $streamHash = $defs{$strmdev};                           # Hash des SSCamSTRM-Devices
  my $uuid       = $streamHash->{FUUID};                      # eindeutige UUID des Streamingdevices
  my $hdrAlign   = "center";
  
  delete $streamHash->{HELPER}{STREAM};
  delete $streamHash->{HELPER}{STREAMACTIVE};                 # Statusbit ob ein Stream aktiviert ist
  
  my ($show,$cause,$ret);
  
  # Definition Tasten
  my $imgblank      = "<img src=\"$FW_ME/www/images/sscam/black_btn_CAMBLANK.png\">";                                # nicht sichtbare Leertaste
  my $cmdstop       = "FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $camname stopView STRM:$uuid')";                       # Stream deaktivieren
  my $imgstop       = "<img src=\"$FW_ME/www/images/default/remotecontrol/black_btn_POWEROFF3.png\">"; 
  my $cmdhlsreact   = "FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $camname hlsreactivate')";                             # HLS Stream reaktivieren
  my $imghlsreact   = "<img src=\"$FW_ME/www/images/default/remotecontrol/black_btn_BACKDroid.png\">";
  my $cmdmjpegrun   = "FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $camname runView live_fw STRM:$uuid')";                # MJPEG Stream aktivieren  
  my $imgmjpegrun   = "<img src=\"$FW_ME/www/images/sscam/black_btn_MJPEG.png\">";
  my $cmdhlsrun     = "FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $camname runView live_fw_hls STRM:$uuid')";            # HLS Stream aktivieren  
  my $imghlsrun     = "<img src=\"$FW_ME/www/images/sscam/black_btn_HLS.png\">"; 
  my $cmdlrirun     = "FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $camname runView lastrec_fw STRM:$uuid')";             # Last Record IFrame  
  my $imglrirun     = "<img src=\"$FW_ME/www/images/sscam/black_btn_LASTRECIFRAME.png\">";
  my $cmdlh264run   = "FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $camname runView lastrec_fw_MPEG4/H.264 STRM:$uuid')"; # Last Record H.264  
  my $imglh264run   = "<img src=\"$FW_ME/www/images/sscam/black_btn_LRECH264.png\">";
  my $cmdlmjpegrun  = "FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $camname runView lastrec_fw_MJPEG STRM:$uuid')";       # Last Record MJPEG  
  my $imglmjpegrun  = "<img src=\"$FW_ME/www/images/sscam/black_btn_LRECMJPEG.png\">";
  my $cmdlsnaprun   = "FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $camname runView lastsnap_fw STRM:$uuid')";            # Last SNAP  
  my $imglsnaprun   = "<img src=\"$FW_ME/www/images/sscam/black_btn_LSNAP.png\">";
  my $cmdrecendless = "FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $camname on 0 STRM:$uuid')";                           # Endlosaufnahme Start  
  my $imgrecendless = "<img src=\"$FW_ME/www/images/sscam/black_btn_RECSTART.png\">";
  my $cmdrecstop    = "FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $camname off STRM:$uuid')";                            # Aufnahme Stop  
  my $imgrecstop    = "<img src=\"$FW_ME/www/images/sscam/black_btn_RECSTOP.png\">";
  my $cmddosnap     = "FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $camname snap 1 2 STRM:$uuid')";                       # Snapshot auslösen mit Kennzeichnung "by STRM-Device"
  my $imgdosnap     = "<img src=\"$FW_ME/www/images/sscam/black_btn_DOSNAP.png\">";
  my $cmdrefresh    = "FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $camname refresh STRM:$uuid')";                        # Refresh in SSCamSTRM-Devices
  my $imgrefresh    = "<img src=\"$FW_ME/www/images/default/Restart.png\">";
  
  # bei Aufruf durch FTUI Kommandosyntax anpassen
  if ($ftui) {
      $cmddosnap     = "ftui.setFhemStatus('set $camname snap 1 2 STRM:$uuid')";  
      $cmdstop       = "ftui.setFhemStatus('set $camname stopView STRM:$uuid')";  
      $cmdhlsreact   = "ftui.setFhemStatus('set $camname hlsreactivate STRM:$uuid')"; 
      $cmdmjpegrun   = "ftui.setFhemStatus('set $camname runView live_fw STRM:$uuid')";   
      $cmdhlsrun     = "ftui.setFhemStatus('set $camname runView live_fw_hls STRM:$uuid')"; 
      $cmdlrirun     = "ftui.setFhemStatus('set $camname runView lastrec_fw STRM:$uuid')";
      $cmdlh264run   = "ftui.setFhemStatus('set $camname runView lastrec_fw_MPEG4/H.264 STRM:$uuid')";
      $cmdlmjpegrun  = "ftui.setFhemStatus('set $camname runView lastrec_fw_MJPEG STRM:$uuid')";     
      $cmdlsnaprun   = "ftui.setFhemStatus('set $camname runView lastsnap_fw STRM STRM:$uuid')";
      $cmdrecendless = "ftui.setFhemStatus('set $camname on 0 STRM:$uuid')";
      $cmdrecstop    = "ftui.setFhemStatus('set $camname off STRM:$uuid')"; 
      $cmdrefresh    = "ftui.setFhemStatus('set $camname refresh STRM:$uuid')";      
  }
  
  my $calias = $hash->{CAMNAME};                                            # Alias der Kamera
  my ($ttrefresh, $ttrecstart, $ttrecstop, $ttsnap, $ttcmdstop, $tthlsreact);
  my ($ttmjpegrun, $tthlsrun, $ttlrrun, $tth264run, $ttlmjpegrun, $ttlsnaprun);
  
  # Hinweis Popups
  if(AttrVal("global","language","EN") =~ /EN/x) {
      $ttrefresh   = $ttips_en{"ttrefresh"};   $ttrefresh   =~ s/§NAME§/$calias/gx;
      $ttrecstart  = $ttips_en{"ttrecstart"};  $ttrecstart  =~ s/§NAME§/$calias/gx;
      $ttrecstop   = $ttips_en{"ttrecstop"};   $ttrecstop   =~ s/§NAME§/$calias/gx;
      $ttsnap      = $ttips_en{"ttsnap"};      $ttsnap      =~ s/§NAME§/$calias/gx;
      $ttcmdstop   = $ttips_en{"ttcmdstop"};   $ttcmdstop   =~ s/§NAME§/$calias/gx;
      $tthlsreact  = $ttips_en{"tthlsreact"};  $tthlsreact  =~ s/§NAME§/$calias/gx;
      $ttmjpegrun  = $ttips_en{"ttmjpegrun"};  $ttmjpegrun  =~ s/§NAME§/$calias/gx;
      $tthlsrun    = $ttips_en{"tthlsrun"};    $tthlsrun    =~ s/§NAME§/$calias/gx;
      $ttlrrun     = $ttips_en{"ttlrrun"};     $ttlrrun     =~ s/§NAME§/$calias/gx;
      $tth264run   = $ttips_en{"tth264run"};   $tth264run   =~ s/§NAME§/$calias/gx;     
      $ttlmjpegrun = $ttips_en{"ttlmjpegrun"}; $ttlmjpegrun =~ s/§NAME§/$calias/gx;
      $ttlsnaprun  = $ttips_en{"ttlsnaprun"};  $ttlsnaprun  =~ s/§NAME§/$calias/gx;
  } 
  else {
      $ttrefresh   = $ttips_de{"ttrefresh"};   $ttrefresh   =~ s/§NAME§/$calias/gx;
      $ttrecstart  = $ttips_de{"ttrecstart"};  $ttrecstart  =~ s/§NAME§/$calias/gx;
      $ttrecstop   = $ttips_de{"ttrecstop"};   $ttrecstop   =~ s/§NAME§/$calias/gx;
      $ttsnap      = $ttips_de{"ttsnap"};      $ttsnap      =~ s/§NAME§/$calias/gx;
      $ttcmdstop   = $ttips_de{"ttcmdstop"};   $ttcmdstop   =~ s/§NAME§/$calias/gx;
      $tthlsreact  = $ttips_de{"tthlsreact"};  $tthlsreact  =~ s/§NAME§/$calias/gx;
      $ttmjpegrun  = $ttips_de{"ttmjpegrun"};  $ttmjpegrun  =~ s/§NAME§/$calias/gx;
      $tthlsrun    = $ttips_de{"tthlsrun"};    $tthlsrun    =~ s/§NAME§/$calias/gx;
      $ttlrrun     = $ttips_de{"ttlrrun"};     $ttlrrun     =~ s/§NAME§/$calias/gx;
      $tth264run   = $ttips_de{"tth264run"};   $tth264run   =~ s/§NAME§/$calias/gx;     
      $ttlmjpegrun = $ttips_de{"ttlmjpegrun"}; $ttlmjpegrun =~ s/§NAME§/$calias/gx;
      $ttlsnaprun  = $ttips_de{"ttlsnaprun"};  $ttlsnaprun  =~ s/§NAME§/$calias/gx;
  }
  
  my $ha  = AttrVal($camname, "htmlattr",       'width="500" height="325"');  # HTML Attribute der Cam
  $ha     = AttrVal($strmdev, "htmlattr",       $ha);                         # htmlattr mit htmlattr Streaming-Device übersteuern 
  $ha     = AttrVal($strmdev, "htmlattrFTUI",   $ha) if($ftui);               # wenn aus FTUI aufgerufen divers setzen  
  my $hb  = AttrVal($strmdev, "hideButtons",      0);                         # Drucktasten im Footer ausblenden ?
  my $hau = AttrVal($strmdev, "hideAudio",        0);                         # Audio Steuerblock im Footer ausblenden ?
  my $pws = AttrVal($strmdev, "popupWindowSize", "");                         # Größe eines Popups
  $pws    =~ s/"//gx if($pws);
  
  $show   = $defs{$streamHash->{PARENT}}->{HELPER}{ACTSTRM} if($streamHash->{MODEL} =~ /switched/x);
  $show   = $show ? "($show)" : "";
  
  my $alias  = AttrVal($strmdev, "alias", $strmdev);                        # Linktext als Aliasname oder Devicename setzen
  my $dlink  = "<a href=\"/fhem?detail=$strmdev\">$alias</a>";
  $dlink     = $alias if(AttrVal($strmdev, "noLink", 0));                   # keine Links im Stream-Dev generieren
  
  my $StmKey = ReadingsVal($camname,"StmKey",undef);
  
  my %params = (
    camname            => $camname,
    strmdev            => $strmdev,
    ftui               => $ftui,
    uuid               => $uuid,
    ha                 => $ha,
    hb                 => $hb,
    hau                => $hau,
    pws                => $pws,
    serveraddr         => $hash->{SERVERADDR},
    serverport         => $hash->{SERVERPORT},
    apivideostm        => $hash->{HELPER}{API}{VIDEOSTM}{NAME},
    apivideostmpath    => $hash->{HELPER}{API}{VIDEOSTM}{PATH},
    apivideostmver     => $hash->{HELPER}{API}{VIDEOSTM}{VER}, 
    apiaudiostm        => $hash->{HELPER}{API}{AUDIOSTM}{NAME},
    apiaudiostmpath    => $hash->{HELPER}{API}{AUDIOSTM}{PATH},
    apiaudiostmver     => $hash->{HELPER}{API}{AUDIOSTM}{VER},
    apivideostms       => $hash->{HELPER}{API}{VIDEOSTMS}{NAME},  
    apivideostmspath   => $hash->{HELPER}{API}{VIDEOSTMS}{PATH},
    apivideostmsver    => $hash->{HELPER}{API}{VIDEOSTMS}{VER},
    camid              => $hash->{CAMID},
    sid                => $hash->{HELPER}{SID},
    proto              => $hash->{PROTOCOL},
    cmdstop            => $cmdstop,
    cmdhlsreact        => $cmdhlsreact, 
    cmdmjpegrun        => $cmdmjpegrun,  
    cmdhlsrun          => $cmdhlsrun, 
    cmdlrirun          => $cmdlrirun,    
    cmdlh264run        => $cmdlh264run,
    cmdlmjpegrun       => $cmdlmjpegrun, 
    cmdlsnaprun        => $cmdlsnaprun,      
    cmdrecendless      => $cmdrecendless,  
    cmdrecstop         => $cmdrecstop, 
    cmddosnap          => $cmddosnap,    
    cmdrefresh         => $cmdrefresh,
    imgblank           => $imgblank,
    imgstop            => $imgstop,       
    imghlsreact        => $imghlsreact,    
    imgmjpegrun        => $imgmjpegrun,    
    imghlsrun          => $imghlsrun,       
    imglrirun          => $imglrirun,   
    imglh264run        => $imglh264run,  
    imglmjpegrun       => $imglmjpegrun,  
    imglsnaprun        => $imglsnaprun,   
    imgrecendless      => $imgrecendless,   
    imgrecstop         => $imgrecstop,     
    imgdosnap          => $imgdosnap,                          
    imgrefresh         => $imgrefresh,
    ttrefresh          => $ttrefresh,
    ttrecstart         => $ttrecstart,  
    ttrecstop          => $ttrecstop,
    ttsnap             => $ttsnap, 
    ttcmdstop          => $ttcmdstop,  
    tthlsreact         => $tthlsreact, 
    ttmjpegrun         => $ttmjpegrun,
    tthlsrun           => $tthlsrun, 
    ttlrrun            => $ttlrrun,   
    tth264run          => $tth264run,       
    ttlmjpegrun        => $ttlmjpegrun,
    ttlsnaprun         => $ttlsnaprun,
  );
  
  $ret  = "";            
  $ret .= '<table class="block wide internals" style="margin-left:auto;margin-right:auto">';
  if($ftui) {
      $ret .= "<span align=\"$hdrAlign\">$dlink $show </span><br>"  if(!AttrVal($strmdev,"hideDisplayNameFTUI",0));
  } 
  else {
      $ret .= "<span align=\"$hdrAlign\">$dlink $show </span><br>"  if(!AttrVal($strmdev,"hideDisplayName",0));
  }  
  $ret .= '<tbody>';
  $ret .= '<tr class="odd">';  
   
  my $ismm = IsModelMaster($omodel);                                          # prüfen ob Streaming Dev ist MODEL = master
  
  if(!$ismm && (!$StmKey || ReadingsVal($camname, "Availability", "") ne "enabled" || IsDisabled($camname))) {
      # Ausgabe bei Fehler
      my $cam = AttrVal($camname, "alias", $camname);                         # Linktext als Aliasname oder Devicename setzen
      $cause  = !$StmKey ? "Camera $cam has no Reading \"StmKey\" set !" : "Cam \"$cam\" is disabled";
      $cause  = "Camera \"$cam\" is disabled" if(IsDisabled($camname));
      $ret   .= "<td> <br> <b> $cause </b> <br><br></td>";
      $ret   .= '</tr>';
      $ret   .= '</tbody>';
      $ret   .= '</table>';
      $ret   .= '</div>';
      return $ret; 
  }
  
  # Streaming ausführen
  no strict "refs";                                                        ## no critic 'NoStrict'  
  if($sdfn{$fmt}) {
      $ret .= &{$sdfn{$fmt}{fn}} (\%params) if(defined &{$sdfn{$fmt}{fn}});  
  } 
  else {
      $cause = qq{Streaming of format "$fmt" is not supported};
      $cause = qq{Select a Streaming client with the "adopt" command.} if($ismm);
      $ret  .= "<td> <br> <b> $cause </b> <br><br></td>";      
  }      
  use strict "refs";
  
  $ret .= '</tr>';
  $ret .= '</tbody>';
  $ret .= '</table>';

return $ret;
}

######################################################################################
#                    Streaming Device Typ: mjpeg
sub _streamDevMJPEG {                               ## no critic 'complexity not used'                                               
  my $params             = shift;
  my $camname            = $params->{camname};
  my $strmdev            = $params->{strmdev};
  
  my $hash               = $defs{$camname};
  my $streamHash         = $defs{$strmdev};
  my $camid              = $params->{camid} // return "";
  my $sid                = $params->{sid}   // return "";
  my $ftui               = $params->{ftui};
  my $proto              = $params->{proto};
  my $pws                = $params->{pws};
  my $ha                 = $params->{ha};
  my $hb                 = $params->{hb};
  my $hau                = $params->{hau};
  
  my $serveraddr         = $params->{serveraddr};
  my $serverport         = $params->{serverport};
  my $apivideostms       = $params->{apivideostms};
  my $apivideostmspath   = $params->{apivideostmspath};
  my $apivideostmsver = $params->{apivideostmsver};
  my $apiaudiostm        = $params->{apiaudiostm};
  my $apiaudiostmpath    = $params->{apiaudiostmpath};
  my $apiaudiostmver  = $params->{apiaudiostmver};
  
  my $cmdrecendless      = $params->{cmdrecendless};
  my $ttrecstart         = $params->{ttrecstart};
  my $imgrecendless      = $params->{imgrecendless};
  my $cmdrecstop         = $params->{cmdrecstop};
  my $ttrecstop          = $params->{ttrecstop};
  my $imgrecstop         = $params->{imgrecstop};
  my $cmddosnap          = $params->{cmddosnap};
  my $ttsnap             = $params->{ttsnap};
  my $imgdosnap          = $params->{imgdosnap};  
  
  my ($link,$audiolink);
  my $ret = "";
  
  if(ReadingsVal($camname, "SVSversion", "") eq "8.2.3-5828" && ReadingsVal($camname, "CamVideoType", "") !~ /MJPEG/x) {  
      $ret .= "<td> <br> <b> Because SVS version 8.2.3-5828 is running you cannot play back MJPEG-Stream. Please upgrade to a higher SVS version ! </b> <br><br>";
      return $ret;
      
  } 
  else {
      if($apivideostmsver) {                                  
          $link = "$proto://$serveraddr:$serverport/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsver&method=Stream&cameraId=$camid&format=mjpeg&_sid=$sid"; 
      
      } elsif ($hash->{HELPER}{STMKEYMJPEGHTTP}) {
          $link = $hash->{HELPER}{STMKEYMJPEGHTTP};
      }
      
      return $ret if(!$link);
      
      if($apiaudiostmver) {                                   
          $audiolink = "$proto://$serveraddr:$serverport/webapi/$apiaudiostmpath?api=$apiaudiostm&version=$apiaudiostmver&method=Stream&cameraId=$camid&_sid=$sid"; 
      }
      
      if(!$ftui) {
          $ret .= "<td><img src=$link $ha onClick=\"FW_okDialog('<img src=$link $pws>')\"><br>";
      } 
      else {
          $ret .= "<td><img src=$link $ha><br>";
      }
      
      $streamHash->{HELPER}{STREAM}       = "<img src=$link $pws>";      # Stream für "get <SSCamSTRM-Device> popupStream" speichern
      $streamHash->{HELPER}{STREAMACTIVE} = 1 if($link);                 # Statusbit wenn ein Stream aktiviert ist      
  }
  
  if(!$hb) {
      if(ReadingsVal($camname, "Record", "Stop") eq "Stop") {            # Aufnahmebutton endlos Start
             $ret .= "<a onClick=\"$cmdrecendless\" title=\"$ttrecstart\">$imgrecendless </a>";
          } 
          else {                                                         # Aufnahmebutton Stop
             $ret .= "<a onClick=\"$cmdrecstop\" title=\"$ttrecstop\">$imgrecstop </a>";
          }       
      $ret .= "<a onClick=\"$cmddosnap\" title=\"$ttsnap\">$imgdosnap </a>"; 
  }    
  
  $ret .= "</td>"; 
  
  if(AttrVal($camname,"ptzPanel_use",1)) {
      my %pars    = ( linkparent => $camname,
                      linkname   => $strmdev,
                      ftui       => $ftui
                    );
      my $ptz_ret = ptzPanel(\%pars);
      if($ptz_ret) {         
          $ret .= "<td>$ptz_ret</td>";
      }
  }
  
  if($audiolink && ReadingsVal($camname, "CamAudioType", "Unknown") !~ /Unknown/x  && !$hau) {
      $ret .= '</tr>';
      $ret .= '<tr class="odd">';
      $ret .= "<td><audio src=$audiolink preload='none' volume='0.5' controls>".
              "Your browser does not support the audio element.".
              "</audio>";
      $ret .= "</td>";
      $ret .= "<td></td>" if(AttrVal($camname,"ptzPanel_use",0));
  } 
  
  Log3($strmdev, 4, "$strmdev - Link called: $link") if($link);
  undef $link;
  
return $ret;
}

######################################################################################
#                    Streaming Device Typ: lastsnap
sub _streamDevLASTSNAP {                                       ## no critic 'not used'                 
  my $params     = shift;
  
  my $camname    = $params->{camname};
  my $strmdev    = $params->{strmdev};
  
  my $hash       = $defs{$camname};
  my $streamHash = $defs{$strmdev};
  my $ftui       = $params->{ftui};
  my $pws        = $params->{pws};
  my $ha         = $params->{ha};
  my $hb         = $params->{hb};
  
  my $cmddosnap  = $params->{cmddosnap};
  my $ttsnap     = $params->{ttsnap};
  my $imgdosnap  = $params->{imgdosnap};  
  
  my ($link,$cause,$ret) = ("","","");
   
  my $cache = cache($camname, "c_init");                                                  # Cache initialisieren  
  Log3($camname, 1, "$camname - Fall back to internal Cache due to preceding failure.") if(!$cache);                                 
  
  if(!$cache || $cache eq "internal" ) {
      $link = $data{SSCam}{$camname}{LASTSNAP};
  } 
  else {
      $link = cache($camname, "c_read", "{LASTSNAP}");                           
  }
  
  my $gattr = (AttrVal($camname,"snapGallerySize","Icon") eq "Full") ? $ha : ""; 
  
  if($link) {
      if(!$ftui) {
          $ret .= "<td><img src='data:image/jpeg;base64,$link' $gattr onClick=\"FW_okDialog('<img src=data:image/jpeg;base64,$link $pws>')\"><br>";
      } 
      else {
          $ret .= "<td><img src='data:image/jpeg;base64,$link' $gattr><br>";
      }
      
      if(!$hb) {
          $ret .= "<a onClick=\"$cmddosnap\" title=\"$ttsnap\">$imgdosnap </a>";
      }
      
      $ret .= "</td>";
      
      $streamHash->{HELPER}{STREAM}       = "<img src=data:image/jpeg;base64,$link $pws>";      # Stream für "get <SSCamSTRM-Device> popupStream" speichern
      $streamHash->{HELPER}{STREAMACTIVE} = 1 if($link);                                        # Statusbit wenn ein Stream aktiviert ist
  } 
  else {
      $cause = "no snapshot available to display";
      $cause = "kein Schnappschuss zur Anzeige vorhanden" if(AttrVal("global","language","EN") =~ /DE/ix);
      $ret .= "<td> <br> <b> $cause </b> <br><br></td>";       
  }
  
  Log3($strmdev, 4, "$strmdev - Link called: $link") if($link);
  undef $link;
  
return $ret;
}

######################################################################################
#                    Streaming Device Typ: generic
sub _streamDevGENERIC {                                        ## no critic 'not used'                    
  my $params        = shift;
  
  my $camname       = $params->{camname};
  my $strmdev       = $params->{strmdev};
  
  my $hash          = $defs{$camname};
  my $streamHash    = $defs{$strmdev};
  my $ftui          = $params->{ftui};
  my $pws           = $params->{pws};
  my $ha            = $params->{ha};
  my $hb            = $params->{hb};
  
  my $cmdrefresh    = $params->{cmdrefresh};
  my $cmdrecendless = $params->{cmdrecendless};
  my $cmdrecstop    = $params->{cmdrecstop};
  my $cmddosnap     = $params->{cmddosnap};
  
  my $imgrecendless = $params->{imgrecendless};
  my $imgrecstop    = $params->{imgrecstop};
  my $imgdosnap     = $params->{imgdosnap}; 
  my $imgrefresh    = $params->{imgrefresh};
  my $imgblank      = $params->{imgblank};
  
  my $ttrefresh     = $params->{ttrefresh};
  my $ttsnap        = $params->{ttsnap};
  my $ttrecstop     = $params->{ttrecstop};  
  my $ttrecstart    = $params->{ttrecstart};
  
  my $ret   = "";
  my $htag  = AttrVal( $strmdev, "genericStrmHtmlTag", AttrVal($camname, "genericStrmHtmlTag", "") );
  
  if($htag =~ m/^\s*(.*)\s*$/sx) {
      $htag = $1;
      $htag =~ s/\$NAME/$camname/xg;
      $htag =~ s/\$HTMLATTR/$ha/xg;
      $htag =~ s/\$PWS/$pws/xg;
  }

  if(!$htag) {
      $ret .= "<td> <br> <b> Set attribute \"genericStrmHtmlTag\" in device <a href=\"/fhem?detail=$camname\">$camname</a> or in device <a href=\"$FW_ME?detail=$strmdev\">$strmdev</a></b> <br><br></td>";
      return $ret; 
  }
  
  $ret .= "<td>";
  $ret .= "$htag";
  
  if($htag) {                                                             # Popup-Tag um den Popup-Teil bereinigen 
      my $ptag = $htag;
      $ptag    =~ m/^\s+?(?<b><)\s+?(?<heart>.*?)\s+?onClick=.*?\s+?(?<e>>)\s+?$/xs;
      $ptag    = $+{heart} ? $+{b}.$+{heart}.$+{e} : $ptag;
      $streamHash->{HELPER}{STREAM}       = "$ptag";                      # Stream für "set <SSCamSTRM-Device> popupStream" speichern
      $streamHash->{HELPER}{STREAM}       =~ s/["']//gx;
      $streamHash->{HELPER}{STREAM}       =~ s/\s+/ /gx;
      $streamHash->{HELPER}{STREAMACTIVE} = 1;                            # Statusbit wenn ein Stream aktiviert ist
  }
  
  $ret .= "<br>";
  
  Log3($strmdev, 4, "$strmdev - generic Stream params:\n$htag");
  
  if(!$hb) {
      $ret .= "<a onClick=\"$cmdrefresh\" title=\"$ttrefresh\">$imgrefresh </a>";
      $ret .= $imgblank;
      
      if(ReadingsVal($camname, "Record", "Stop") eq "Stop") {            # Aufnahmebutton endlos Start
          $ret .= "<a onClick=\"$cmdrecendless\" title=\"$ttrecstart\">$imgrecendless </a>";
      } 
      else {                                                             # Aufnahmebutton Stop
          $ret .= "<a onClick=\"$cmdrecstop\" title=\"$ttrecstop\">$imgrecstop </a>";
      }       
      
      $ret .= "<a onClick=\"$cmddosnap\" title=\"$ttsnap\">$imgdosnap </a>";
  }      
  $ret .= "</td>";
  
  if(AttrVal($camname,"ptzPanel_use",1)) {
      my %pars    = ( linkparent => $camname,
                      linkname   => $strmdev,
                      ftui       => $ftui
                    );
      my $ptz_ret = ptzPanel(\%pars);
      if($ptz_ret) { 
          $ret .= "<td>$ptz_ret</td>";
      }
  }    
  
return $ret;
}

######################################################################################
#                    Streaming Device Typ: hls
sub _streamDevHLS {                                            ## no critic 'not used'            
  my $params        = shift;
  
  my $camname       = $params->{camname};
  my $strmdev       = $params->{strmdev};
  
  my $hash          = $defs{$camname};
  my $streamHash    = $defs{$strmdev};
  my $ftui          = $params->{ftui};
  my $pws           = $params->{pws};
  my $ha            = $params->{ha};
  my $hb            = $params->{hb};
  
  my $cmdrefresh    = $params->{cmdrefresh};
  my $cmdrecendless = $params->{cmdrecendless};
  my $cmdrecstop    = $params->{cmdrecstop};
  my $cmddosnap     = $params->{cmddosnap};
  
  my $imgrecendless = $params->{imgrecendless};
  my $imgrecstop    = $params->{imgrecstop};
  my $imgdosnap     = $params->{imgdosnap}; 
  my $imgrefresh    = $params->{imgrefresh};
  my $imgblank      = $params->{imgblank};  
  
  my $ttrefresh     = $params->{ttrefresh};
  my $ttsnap        = $params->{ttsnap};
  my $ttrecstop     = $params->{ttrecstop};  
  my $ttrecstart    = $params->{ttrecstart};
  
  my ($cause,$ret)  = ("","");
   
  # es ist ein .m3u8-File bzw. ein Link dorthin zu übergeben
  my $cam  = AttrVal($camname, "alias", $camname);
  my $m3u8 = AttrVal($camname, "hlsStrmObject", "");

  if( $m3u8 =~ m/^\s*(.*)\s*$/sx ) {
      $m3u8 = $1;
      $m3u8 =~ s/\$NAME/$camname/gx;
  }  
  
  my $d = $camname;
  $d    =~ s/\./_/x;                                                             # Namensableitung zur javascript Codeanpassung
  
  if(!$m3u8) {
      $cause = qq{You have to specify attribute "hlsStrmObject" in Camera <a href="$FW_ME?detail=$cam">$cam</a> !};
      $ret  .= "<td> <br> <b> $cause </b> <br><br></td>";
      return $ret; 
  }      
  
  $ret .= "<td><video $ha id=video_$d controls autoplay muted></video><br>";
  $ret .= bindhlsjs ($camname, $strmdev, $m3u8, $d); 
  
  $streamHash->{HELPER}{STREAM}       = "<video $pws id=video_$d></video>";     # Stream für "set <SSCamSTRM-Device> popupStream" speichern   
  $streamHash->{HELPER}{STREAMACTIVE} = 1;                                      # Statusbit wenn ein Stream aktiviert ist
  
  if(!$hb) {
      $ret .= "<a onClick=\"$cmdrefresh\" title=\"$ttrefresh\">$imgrefresh </a>";
      $ret .= $imgblank;
      
      if(ReadingsVal($camname, "Record", "Stop") eq "Stop") {                   # Aufnahmebutton endlos Start
          $ret .= "<a onClick=\"$cmdrecendless\" title=\"$ttrecstart\">$imgrecendless </a>";
      } 
      else {                                                                    # Aufnahmebutton Stop
          $ret .= "<a onClick=\"$cmdrecstop\"  title=\"$ttrecstop\">$imgrecstop </a>";
      }       
      
      $ret .= "<a onClick=\"$cmddosnap\" title=\"$ttsnap\">$imgdosnap </a>"; 
  }      
  
  $ret .= "</td>";      
  
  if(AttrVal($camname,"ptzPanel_use",1)) {
      my %pars    = ( linkparent => $camname,
                      linkname   => $strmdev,
                      ftui       => $ftui
                    );
      my $ptz_ret = ptzPanel(\%pars);
      if($ptz_ret) { 
          $ret .= "<td>$ptz_ret</td>";
      }
  }    
  
return $ret;
}

######################################################################################
#                    Streaming Device Typ: switched
sub _streamDevSWITCHED {                                       ## no critic 'not used'                
  my $params        = shift;
  my $camname       = $params->{camname};
  my $strmdev       = $params->{strmdev};
  my $hash          = $defs{$camname};

  my $cmdmjpegrun   = $params->{cmdmjpegrun};
  my $cmdhlsrun     = $params->{cmdhlsrun};
  my $cmdlrirun     = $params->{cmdlrirun};
  my $cmdlh264run   = $params->{cmdlh264run};
  my $cmdlsnaprun   = $params->{cmdlsnaprun};
  my $cmdlmjpegrun  = $params->{cmdlmjpegrun};

  my $imgmjpegrun   = $params->{imgmjpegrun};
  my $imghlsrun     = $params->{imghlsrun};
  my $imglh264run   = $params->{imglh264run};
  my $imglmjpegrun  = $params->{imglmjpegrun};
  my $imglsnaprun   = $params->{imglsnaprun};
  my $imglrirun     = $params->{imglrirun};

  my $ttmjpegrun    = $params->{ttmjpegrun};
  my $tthlsrun      = $params->{tthlsrun};
  my $ttlrrun       = $params->{ttlrrun};
  my $tth264run     = $params->{tth264run};
  my $ttlmjpegrun   = $params->{ttlmjpegrun};
  my $ttlsnaprun    = $params->{ttlsnaprun};
  
  my ($link,$cause,$ret) = ("","","");
   
  my $wltype = $hash->{HELPER}{WLTYPE};
  $link      = $hash->{HELPER}{LINK};
  
  if(!$link) {
      my $cam = AttrVal($camname, "alias", $camname);
      $cause  = "Playback cam \"$cam\" switched off";
      $ret   .= "<td> <br> <b> $cause </b> <br><br>";
      $ret   .= "<a onClick=\"$cmdmjpegrun\" title=\"$ttmjpegrun\">$imgmjpegrun </a>";
      $ret   .= "<a onClick=\"$cmdhlsrun\" title=\"$tthlsrun\">$imghlsrun </a>" if(IsCapHLS($hash));  
      $ret   .= "<a onClick=\"$cmdlrirun\" title=\"$ttlrrun\">$imglrirun </a>"; 
      $ret   .= "<a onClick=\"$cmdlh264run\" title=\"$tth264run\">$imglh264run </a>";
      $ret   .= "<a onClick=\"$cmdlmjpegrun\" title=\"$ttlmjpegrun\">$imglmjpegrun </a>";
      $ret   .= "<a onClick=\"$cmdlsnaprun\" title=\"$ttlsnaprun\">$imglsnaprun </a>";            
      $ret   .= "</td>";
      return $ret;      
  }
  
  # Streaming ausführen
  no strict "refs";                                                        ## no critic 'NoStrict'  
  if($sdswfn{$wltype}) {
      $ret .= &{$sdswfn{$wltype}{fn}} ($params) if(defined &{$sdswfn{$wltype}{fn}});  
  } 
  else {
      $cause = qq{Streaming of format "$wltype" is not supported};
      $ret  .= "<td> <br> <b> $cause </b> <br><br></td>";      
  }      
  use strict "refs";     
  
  Log3($strmdev, 4, "$strmdev - Link called: $link");
  undef $link;
  
return $ret;
}

######################################################################################
#                    Streaming Device Typ: switched image
sub __switchedIMAGE {                                          ## no critic 'not used'                
  my $params        = shift;
  
  my $camname       = $params->{camname};
  my $strmdev       = $params->{strmdev};
  
  my $hash          = $defs{$camname};
  my $streamHash    = $defs{$strmdev};
  my $ftui          = $params->{ftui};
  my $pws           = $params->{pws};
  my $ha            = $params->{ha};
  my $hau           = $params->{hau};
  
  my $cmdrecendless = $params->{cmdrecendless};
  my $cmdrecstop    = $params->{cmdrecstop};
  my $cmddosnap     = $params->{cmddosnap};
  my $cmdstop       = $params->{cmdstop};
  
  my $imgrecendless = $params->{imgrecendless};
  my $imgrecstop    = $params->{imgrecstop};
  my $imgdosnap     = $params->{imgdosnap}; 
  my $imgblank      = $params->{imgblank}; 
  my $imgstop       = $params->{imgstop};
  
  my $ttsnap        = $params->{ttsnap};
  my $ttrecstop     = $params->{ttrecstop};  
  my $ttrecstart    = $params->{ttrecstart};
  my $ttcmdstop     = $params->{ttcmdstop};
  
  my ($link,$ret)   = ("","");
  $link             = $hash->{HELPER}{LINK};
  
  if(ReadingsVal($camname, "SVSversion", "8.2.3-5828") eq "8.2.3-5828" && ReadingsVal($camname, "CamVideoType", "") !~ /MJPEG/x) {             
      $ret .= "<td> <br> <b> Because SVS version 8.2.3-5828 is running you cannot see the MJPEG-Stream. Please upgrade to a higher SVS version ! </b> <br><br>";
  } 
  else {
      if(!$ftui) {
          $ret .= "<td><img src=$link $ha onClick=\"FW_okDialog('<img src=$link $pws>')\"><br>" if($link);
      } 
      else {
          $ret .= "<td><img src=$link $ha><br>" if($link);
      }
      
      $streamHash->{HELPER}{STREAM}       = "<img src=$link $pws>";    # Stream für "set <SSCamSTRM-Device> popupStream" speichern
      $streamHash->{HELPER}{STREAMACTIVE} = 1;                         # Statusbit wenn ein Stream aktiviert ist
  }  
  
  $ret .= "<a onClick=\"$cmdstop\" title=\"$ttcmdstop\">$imgstop </a>";
  $ret .= $imgblank; 
  
  if($hash->{HELPER}{RUNVIEW} =~ /live_fw/x) {              
      if(ReadingsVal($camname, "Record", "Stop") eq "Stop") {          # Aufnahmebutton endlos Start
          $ret .= "<a onClick=\"$cmdrecendless\" title=\"$ttrecstart\">$imgrecendless </a>";
      } 
      else {                                                           # Aufnahmebutton Stop
          $ret .= "<a onClick=\"$cmdrecstop\" title=\"$ttrecstop\">$imgrecstop </a>";
      }  
      
      $ret .= "<a onClick=\"$cmddosnap\" title=\"$ttsnap\">$imgdosnap </a>";
  }   
  
  $ret .= "</td>";
  
  if(AttrVal($camname,"ptzPanel_use",1) && $hash->{HELPER}{RUNVIEW} =~ /live_fw/x) {
      my %pars    = ( linkparent => $camname,
                      linkname   => $strmdev,
                      ftui       => $ftui
                    );
      my $ptz_ret = ptzPanel(\%pars);
      if($ptz_ret) { 
          $ret .= "<td>$ptz_ret</td>";
      }
  }
  
  if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($camname, "CamAudioType", "Unknown") !~ /Unknown/x && !$hau) {
      $ret .= "</tr>";
      $ret .= '<tr class="odd">';
      $ret .= "<td><audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>".
              "Your browser does not support the audio element.".     
              "</audio>";
      $ret .= "</td>";
      $ret .= "<td></td>" if(AttrVal($camname,"ptzPanel_use",0));
  } 
  
return $ret;
}

######################################################################################
#                    Streaming Device Typ: switched iframe
sub __switchedIFRAME {                                         ## no critic 'not used'               
  my $params        = shift;
  
  my $camname       = $params->{camname};
  my $strmdev       = $params->{strmdev};
  
  my $hash          = $defs{$camname};
  my $streamHash    = $defs{$strmdev};
  my $ftui          = $params->{ftui};
  my $pws           = $params->{pws};
  my $ha            = $params->{ha};
  my $hau           = $params->{hau};

  my $cmdstop       = $params->{cmdstop};
  my $cmdrefresh    = $params->{cmdrefresh};
  
  my $imgstop       = $params->{imgstop};
  my $imgrefresh    = $params->{imgrefresh};
  
  my $ttcmdstop     = $params->{ttcmdstop};
  my $ttrefresh     = $params->{ttrefresh};
  
  my ($link,$ret)   = ("","");
  $link             = $hash->{HELPER}{LINK};
  
  if(!$ftui) {
      $ret .= "<td><iframe src=$link $ha controls autoplay onClick=\"FW_okDialog('<img src=$link $pws>')\">".
              "Iframes disabled".
              "</iframe><br>" if($link);
  } 
  else {
      $ret .= "<td><iframe src=$link $ha controls autoplay>".
              "Iframes disabled".
              "</iframe><br>" if($link);              
  }
  $streamHash->{HELPER}{STREAM}       = "<iframe src=$link $pws controls autoplay>".
                                        "Iframes disabled".
                                        "</iframe>";                # Stream für "set <SSCamSTRM-Device> popupStream" speichern
  $streamHash->{HELPER}{STREAMACTIVE} = 1;                          # Statusbit wenn ein Stream aktiviert ist
  
  $ret .= "<a onClick=\"$cmdstop\" title=\"$ttcmdstop\">$imgstop </a>";
  $ret .= "<a onClick=\"$cmdrefresh\" title=\"$ttrefresh\">$imgrefresh </a>";              
  $ret .= "</td>";
  
  if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($camname, "CamAudioType", "Unknown") !~ /Unknown/x  && !$hau) {
      $ret .= "</tr>";
      $ret .= '<tr class="odd">';
      $ret .= "<td><audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>".
              "Your browser does not support the audio element.".      
              "</audio>";
      $ret .= "</td>";
      $ret .= "<td></td>" if(AttrVal($camname,"ptzPanel_use",0));
  }
  
return $ret;
}

######################################################################################
#                    Streaming Device Typ: switched video
sub __switchedVIDEO {                                          ## no critic 'not used'                     
  my $params        = shift;
  
  my $camname       = $params->{camname};
  my $strmdev       = $params->{strmdev};
  
  my $hash          = $defs{$camname};
  my $streamHash    = $defs{$strmdev};
  my $ftui          = $params->{ftui};
  my $pws           = $params->{pws};
  my $ha            = $params->{ha};
  my $hau           = $params->{hau};
  my $cmdstop       = $params->{cmdstop};
  my $imgstop       = $params->{imgstop};
  my $ttcmdstop     = $params->{ttcmdstop};
  
  my ($link,$ret)   = ("","");
  $link             = $hash->{HELPER}{LINK};
  
  $ret .= "<td><video $ha controls autoplay>".
          "<source src=$link type=\"video/mp4\">".
          "<source src=$link type=\"video/ogg\">".
          "<source src=$link type=\"video/webm\">".
          "Your browser does not support the video tag".
          "</video><br>";
  
  $streamHash->{HELPER}{STREAM} = "<video $pws controls autoplay>".
                                  "<source src=$link type=\"video/mp4\">". 
                                  "<source src=$link type=\"video/ogg\">".
                                  "<source src=$link type=\"video/webm\">".
                                  "Your browser does not support the video tag".
                                  "</video>";                                        # Stream für "set <SSCamSTRM-Device> popupStream" speichern              
  
  $streamHash->{HELPER}{STREAMACTIVE} = 1;                                           # Statusbit wenn ein Stream aktiviert ist
  
  $ret .= "<a onClick=\"$cmdstop\" title=\"$ttcmdstop\">$imgstop </a>"; 
  $ret .= "</td>";
  
  if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($camname, "CamAudioType", "Unknown") !~ /Unknown/x  && !$hau) {
      $ret .= "</tr>";
      $ret .= '<tr class="odd">';
      $ret .= "<td><audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>".
              "Your browser does not support the audio element.".    
              "</audio>";
      $ret .= "</td>";
      $ret .= "<td></td>" if(AttrVal($camname,"ptzPanel_use",0));
  }
  
return $ret;
}

######################################################################################
#                    Streaming Device Typ: switched base64img
sub __switchedBASE64IMG {                                      ## no critic 'not used'                          
  my $params        = shift;
  
  my $camname       = $params->{camname};
  my $strmdev       = $params->{strmdev};
  
  my $hash          = $defs{$camname};
  my $streamHash    = $defs{$strmdev};
  my $ftui          = $params->{ftui};
  my $pws           = $params->{pws};
  my $ha            = $params->{ha};

  my $cmdstop       = $params->{cmdstop};
  my $cmddosnap     = $params->{cmddosnap};
  
  my $imgstop       = $params->{imgstop};
  my $imgdosnap     = $params->{imgdosnap};
  my $imgblank      = $params->{imgblank};
  
  my $ttcmdstop     = $params->{ttcmdstop};
  my $ttsnap        = $params->{ttsnap};
  
  my ($link,$ret)   = ("","");
  $link             = $hash->{HELPER}{LINK};
  
  if(!$ftui) {
      $ret .= "<td><img src='data:image/jpeg;base64,$link' $ha onClick=\"FW_okDialog('<img src=data:image/jpeg;base64,$link $pws>')\"><br>" if($link);
  } 
  else {
      $ret .= "<td><img src='data:image/jpeg;base64,$link' $ha><br>" if($link);
  }
  $streamHash->{HELPER}{STREAM}       = "<img src=data:image/jpeg;base64,$link $pws>";    # Stream für "get <SSCamSTRM-Device> popupStream" speichern
  $streamHash->{HELPER}{STREAMACTIVE} = 1;                                                # Statusbit wenn ein Stream aktiviert ist
  
  $ret .= "<a onClick=\"$cmdstop\" title=\"$ttcmdstop\">$imgstop </a>";
  $ret .= $imgblank;
  $ret .= "<a onClick=\"$cmddosnap\" title=\"$ttsnap\">$imgdosnap </a>";
  $ret .= "</td>";

return $ret;
}

######################################################################################
#                    Streaming Device Typ: switched embed
sub __switchedEMBED {                                          ## no critic 'not used'                       
  my $params        = shift;
  
  my $camname       = $params->{camname};
  my $strmdev       = $params->{strmdev};
  
  my $hash          = $defs{$camname};
  my $streamHash    = $defs{$strmdev};
  my $ftui          = $params->{ftui};
  my $pws           = $params->{pws};
  my $ha            = $params->{ha};
  
  my ($link,$ret)   = ("","");
  $link             = $hash->{HELPER}{LINK};
  
  if(!$ftui) {
      $ret .= "<td><embed src=$link $ha onClick=\"FW_okDialog('<img src=$link $pws>')\"></td>" if($link);
  } 
  else {
      $ret .= "<td><embed src=$link $ha></td>" if($link);
  }
  $streamHash->{HELPER}{STREAM}       = "<embed src=$link $pws>";    # Stream für "set <SSCamSTRM-Device> popupStream" speichern
  $streamHash->{HELPER}{STREAMACTIVE} = 1;                           # Statusbit wenn ein Stream aktiviert ist

return $ret;
}

######################################################################################
#                    Streaming Device Typ: switched hls
sub __switchedHLS {                                            ## no critic 'not used'                   
  my $params        = shift;
  
  my $camname       = $params->{camname};
  my $strmdev       = $params->{strmdev};
  
  my $hash          = $defs{$camname};
  my $streamHash    = $defs{$strmdev};
  my $ftui          = $params->{ftui};
  my $pws           = $params->{pws};
  my $ha            = $params->{ha};
  
  my $cmdrecendless = $params->{cmdrecendless};
  my $cmdrecstop    = $params->{cmdrecstop};
  my $cmddosnap     = $params->{cmddosnap};
  my $cmdstop       = $params->{cmdstop};
  my $cmdrefresh    = $params->{cmdrefresh};
  my $cmdhlsreact   = $params->{cmdhlsreact};
  
  my $imgrecendless = $params->{imgrecendless};
  my $imgrecstop    = $params->{imgrecstop};
  my $imgdosnap     = $params->{imgdosnap}; 
  my $imgblank      = $params->{imgblank}; 
  my $imgstop       = $params->{imgstop};
  my $imgrefresh    = $params->{imgrefresh};
  my $imghlsreact   = $params->{imghlsreact};
  
  my $ttsnap        = $params->{ttsnap};
  my $ttrecstop     = $params->{ttrecstop};  
  my $ttrecstart    = $params->{ttrecstart};
  my $ttcmdstop     = $params->{ttcmdstop};
  my $ttrefresh     = $params->{ttrefresh};
  my $tthlsreact    = $params->{tthlsreact};
  
  my ($link,$ret)   = ("","");
  $link             = $hash->{HELPER}{LINK};
  
  $ret .= "<td><video $ha controls autoplay>".
          "<source src=$link type=\"application/x-mpegURL\">".
          "<source src=$link type=\"video/MP2T\">".
          "Your browser does not support the video tag".
          "</video><br>";
           
  $streamHash->{HELPER}{STREAM} = "<video $pws controls autoplay>".
                                  "<source src=$link type=\"application/x-mpegURL\">".
                                  "<source src=$link type=\"video/MP2T\">".
                                  "Your browser does not support the video tag".
                                  "</video>";                # Stream für "set <SSCamSTRM-Device> popupStream" speichern
  
  $streamHash->{HELPER}{STREAMACTIVE} = 1;                   # Statusbit wenn ein Stream aktiviert ist
  
  $ret .= "<a onClick=\"$cmdstop\" title=\"$ttcmdstop\">$imgstop </a>";
  $ret .= "<a onClick=\"$cmdrefresh\" title=\"$ttrefresh\">$imgrefresh </a>";
  $ret .= "<a onClick=\"$cmdhlsreact\" title=\"$tthlsreact\">$imghlsreact </a>";
  $ret .= $imgblank;
  
  if(ReadingsVal($camname, "Record", "Stop") eq "Stop") {    # Aufnahmebutton endlos Start
      $ret .= "<a onClick=\"$cmdrecendless\" title=\"$ttrecstart\">$imgrecendless </a>";
  } 
  else {                                                     # Aufnahmebutton Stop
      $ret .= "<a onClick=\"$cmdrecstop\" title=\"$ttrecstop\">$imgrecstop </a>";
  }     
  
  $ret .= "<a onClick=\"$cmddosnap\" title=\"$ttsnap\">$imgdosnap </a>";                   
  $ret .= "</td>";
  
  if(AttrVal($camname,"ptzPanel_use",1)) {
      my %pars    = ( linkparent => $camname,
                      linkname   => $strmdev,
                      ftui       => $ftui
                    );
      my $ptz_ret = ptzPanel(\%pars);
      if($ptz_ret) { 
          $ret .= "<td>$ptz_ret</td>";
      }
  } 
  
return $ret;
}

#############################################################################################
#                                   Autocreate für Kameras
#                                   $sn = Name der Kamera in SVS
#############################################################################################
sub doAutocreate { 
   my ($hash,$sn) = @_;
   my $name = $hash->{NAME};
   my $type = $hash->{TYPE};
   
   my ($camhash, $err, $camname);
   
   my $dcn  = (devspec2array("TYPE=SSCam:FILTER=CAMNAME=$sn"))[0];                    # ist das Device aus der SVS bereits angelegt ?
   $camhash = $defs{$dcn} if($dcn);                                                   # existiert ein Hash des Devices ?

   if(!$camhash) {
       $camname = "SSCam.".makeDeviceName($sn);                                       # erlaubten Kameranamen für FHEM erzeugen
       my $arg  = $hash->{SERVERADDR}." ".$hash->{SERVERPORT}." ".$hash->{PROTOCOL};
       my $cmd  = "$camname $type $sn $arg";
       
       Log3($name, 2, "$name - Autocreate camera: define $cmd");
       
       $err = CommandDefine(undef, $cmd);
       
       if($err) {
           Log3($name, 1, "ERROR: $err");
       } 
       else {
           my $room    = AttrVal($name, "room",    "SSCam");
           my $session = AttrVal($name, "session", "DSM"  );
           
           CommandAttr (undef,"$camname room $room");
           CommandAttr (undef,"$camname session $session");
           CommandAttr (undef,"$camname icon it_camera");
           CommandAttr (undef,"$camname devStateIcon .*isable.*:set_off .*nap:li_wht_on");
           CommandAttr (undef,"$camname pollcaminfoall 210");
           CommandAttr (undef,"$camname pollnologging 1");  
           CommandAttr (undef,"$camname httptimeout 20");

           # Credentials abrufen und setzen
           my ($success, $username, $password) = getCredentials($hash,0,"credentials");
           if($success) {
               CommandSet(undef, "$camname credentials $username $password");   
           }
       } 
   } 
   else {
       Log3($name, 4, "$name - Autocreate - SVS camera \"$sn\" already defined by \"$dcn\" ");
       $camname = "";
   }  
   
return ($err,$camname);
}

######################################################################################################
#      Refresh eines Raumes
#      $hash, $pload (1=Page reload), SSCam-state-Event(1=Event), SSCamSTRM-Event (1=Event)
######################################################################################################
sub roomRefresh { 
  my ($hash,$pload,$lpoll_scm,$lpoll_strm) = @_;
  my ($name,$st);
  
  if (ref $hash ne "HASH") {
      ($name,$pload,$lpoll_scm,$lpoll_strm) = split ",",$hash;
      $hash = $defs{$name};
  } 
  else {
      $name = $hash->{NAME};
  }
  
  my $fpr  = 0;
  
  # SSCamSTRM-Device mit hinterlegter FUUID ($hash->{HELPER}{INFORM}) selektieren
  my @spgs = devspec2array("TYPE=SSCamSTRM");                                      # alle Streaming Devices !
  my @mstd = devspec2array("TYPE=SSCamSTRM:FILTER=MODEL=master");                  # alle Streaming MODEL=master Devices
  my $room = "";
 
  for my $sd (@spgs) {   
      if($defs{$sd}{LINKPARENT} eq $name) {
          next if(IsDisabled($defs{$sd}{NAME}) || !$hash->{HELPER}{INFORM} || $hash->{HELPER}{INFORM} ne $defs{$sd}{FUUID});
          $fpr  = AttrVal($defs{$sd}{NAME},"forcePageRefresh",0);
          $room = AttrVal($defs{$sd}{NAME},"room","");
          Log3($name, 4, qq{$name - roomRefresh - pagerefresh forced by $defs{$sd}{NAME}}) if($fpr);
      }
  }

  # Page-Reload
  if($pload && $room && !$fpr) {                                          # nur Räume mit dem SSCamSTRM-Device reloaden
      my @rooms = split(",",$room);
      for my $r (@rooms) {
          { map { FW_directNotify("FILTER=room=$r", "#FHEMWEB:$_", "location.reload('true')", "") } devspec2array("TYPE=FHEMWEB") }         ## no critic 'void context'
      }
  
  } elsif ($pload || $fpr) {
      # trifft zu bei Detailansicht oder im FLOORPLAN bzw. Dashboard oder wenn Seitenrefresh mit dem 
      # SSCamSTRM-Attribut "forcePageRefresh" erzwungen wird
      { map { FW_directNotify("#FHEMWEB:$_", "location.reload('true')", "") } devspec2array("TYPE=FHEMWEB") }                               ## no critic 'void context'
  } 
  
  # Aufnahmestatus/Disabledstatus in state abbilden & SSCam-Device state setzen (mit/ohne Event)
  $st = (ReadingsVal($name, "Availability", "enabled") eq "disabled")?"disabled":(ReadingsVal($name, "Record", "") eq "Start")?"on":"off";  
  if($lpoll_scm) {
      readingsSingleUpdate($hash,"state", $st, 1);
  } 
  else {
      readingsSingleUpdate($hash,"state", $st, 0);  
  }
  
  # parentState des SSCamSTRM-Device updaten ($hash->{HELPER}{INFORM} des LINKPARENT Devices muss FUUID des Streaming Devices haben)
  if($lpoll_strm) {
      $st = ReadingsVal($name, "state", "initialized");  
      for my $sp (@spgs) {                                           # $sp = ein Streaming Device aus allen Streaming Devices
          if($defs{$sp}{LINKPARENT} eq $name) {
              next if(IsDisabled($defs{$sp}{NAME}) || !$hash->{HELPER}{INFORM} || $hash->{HELPER}{INFORM} ne $defs{$sp}{FUUID});
              
              readingsBeginUpdate($defs{$sp});
              readingsBulkUpdate ($defs{$sp},"parentState", $st);
              readingsBulkUpdate ($defs{$sp},"state", "updated");
              readingsEndUpdate  ($defs{$sp}, 1);
              
              for my $sm (@mstd) {                                   # Wenn Streaming Device von Streaming Master adoptiert wurde auch den Master updaten 
                  next if($defs{$sm}{LINKNAME} ne $sp);
                  
                  readingsBeginUpdate($defs{$sm});
                  readingsBulkUpdate ($defs{$sm},"parentState", $st);
                  readingsBulkUpdate ($defs{$sm},"state", "updated");
                  readingsEndUpdate  ($defs{$sm}, 1);
                  
                  Log3($name, 4, "$name - roomRefresh - caller: $sp, Master: $sm updated");
              }
              
              Log3($name, 4, "$name - roomRefresh - caller: $sp, FUUID: $hash->{HELPER}{INFORM}");
              delete $hash->{HELPER}{INFORM};
          }
      }
  }
        
return;
}

#############################################################################################
#    hls.js laden für Streamimgdevice Typen HLS, RTSP
#    $m3u8 - ein .m3u8-File oder ein entsprechender Link
#    $d    - ein Unique-Name zur Codeableitung (darf keinen . enthalten)
#############################################################################################
sub bindhlsjs { 
   my ($camname, $strmdev, $m3u8, $d) = @_;
   my $hlsjs = "sscam_hls.js";                      # hls.js Release von Projekteite https://github.com/video-dev/hls.js/releases
   my ($ret,$uns);
   
   $ret .= "<meta charset=\"utf-8\"/>".
           "<!--script src=\"https://cdn.jsdelivr.net/npm/hls.js\@latest\"></script-->"
           ;
           
   my $dcs = (devspec2array("TYPE=SSCam:FILTER=MODEL=SVS"))[0];  # ist ein SVS-Device angelegt ?
   $uns    = AttrVal($dcs,"hlsNetScript",0) if($dcs);            # ist in einem SVS Device die Nutzung hls.js auf Projektseite ausgewählt ?
            
   if($uns) {
       my $lib = "https://cdn.jsdelivr.net/npm/hls.js\@latest";
       $ret .= "<script src=\"$lib\"></script>";
       Log3($strmdev, 4, "$strmdev - HLS Streaming use net library \"$lib\" ");
   } 
   else {
       $ret .= "<script type=\"text/javascript\" src=\"$FW_ME/pgm2/$hlsjs\"></script>";
       Log3($strmdev, 4, "$strmdev - HLS Streaming use local file \"$FW_ME/pgm2/$hlsjs\" ");
   }
      
   my $back = << "END_HLSJS";
            <script>
            if (Hls.isSupported()) {
                var video_$d = document.getElementById('video_$d');
                var hls = new Hls();
                // bind them together
                hls.attachMedia(video_$d);
                hls.on(Hls.Events.MEDIA_ATTACHED, function () {
                    console.log("video and hls.js are now bound together !");
                    hls.loadSource("$m3u8");
                    hls.on(Hls.Events.MANIFEST_PARSED, function (event, data) {
                        console.log("manifest loaded, found " + data.levels.length + " quality level");
                        video_$d.play();
                    });
                });
            }
            </script>
END_HLSJS
            
   $ret .= qq{$back};
   
return $ret;
}

###############################################################################
#                   Schnappschußgalerie zusammenstellen
#                   Verwendung durch SSCamSTRM-Devices
###############################################################################
sub composeGallery { 
  my $paref    = shift;
  my $name     = $paref->{linkparent}; 
  my $strmdev  = $paref->{linkname};  
  my $ftui     = $paref->{ftui};
  
  my $hash     = $defs{$name};
  my $camname  = $hash->{CAMNAME};                                      
  my $sgc      = AttrVal     ($name,    "snapGalleryColumns", $defColumns);                   # Anzahl der Images in einer Tabellenzeile
  my $lss      = ReadingsVal ($name,    "LastSnapTime",       ""         );                   # Zeitpunkt neueste Aufnahme
  my $lang     = AttrVal     ("global", "language",           "EN"       );                   # Systemsprache       
  my $uuid     = "";
  my $hdrAlign = "center";
  
  my $lupt     = ((ReadingsTimestamp($name,"LastSnapTime"," ") gt ReadingsTimestamp($name,"LastUpdateTime"," ")) 
                 ? ReadingsTimestamp($name,"LastSnapTime"," ") 
                 : ReadingsTimestamp($name,"LastUpdateTime"," "));                            # letzte Aktualisierung
  $lupt        =~ s{ }{ / };
  
  my $totalcnt = $hash->{HELPER}{TOTALCNT};                                                   # totale in SVS vorhandene Anzahl Snaps 
  my $limit    = AttrVal($name, "snapGalleryNumber", $hash->{HELPER}{SNAPLIMIT}) // $defSlim; # maximale Anzahl anzuzeigende Schnappschüsse
  $limit       = $totalcnt < $limit ? $totalcnt : $limit;
  
  my ($alias,$dlink,$hb) = ("","","");
  my ($cache,$imgdat,$imgTm);
  
  if($strmdev) {
      my $streamHash = $defs{$strmdev};                                                       # Hash des SSCamSTRM-Devices
      $uuid          = $streamHash->{FUUID};                                                  # eindeutige UUID des Streamingdevices
      delete $streamHash->{HELPER}{STREAM};
      $alias  = AttrVal($strmdev, "alias", $strmdev);                                         # Linktext als Aliasname oder Devicename setzen
      if(AttrVal($strmdev, "noLink", 0)) {      
          $dlink = $alias;                                                                    # keine Links im Stream-Dev generieren
      } 
      else {
          $dlink = "<a href=\"$FW_ME?detail=$strmdev\">$alias</a>"; 
      }
  }
  
  my $cmddosnap = "FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name snap 1 2 STRM:$uuid')";       # Snapshot auslösen mit Kennzeichnung "by STRM-Device"
  my $imgdosnap = "<img src=\"$FW_ME/www/images/sscam/black_btn_DOSNAP.png\">";
  
  # bei Aufruf durch FTUI Kommandosyntax anpassen
  if($ftui) {
      $cmddosnap = "ftui.setFhemStatus('set $name snap 1 2 STRM:$uuid')";     
  }
 
  my $ha = AttrVal($name, "snapGalleryHtmlAttr", AttrVal($name, "htmlattr", 'width="500" height="325"'));
    
  # falls "composeGallery" durch ein SSCamSTRM-Device aufgerufen wird
  my $pws      = "";
  if ($strmdev) {
      $pws = AttrVal($strmdev, "popupWindowSize", "");                                        # Größe eines Popups (umgelegt: Forum:https://forum.fhem.de/index.php/topic,45671.msg927912.html#msg927912)
      $pws =~ s/"//xg if($pws);
      $ha  = AttrVal($strmdev, "htmlattr", $ha);                                              # htmlattr vom SSCamSTRM-Device übernehmen falls von SSCamSTRM-Device aufgerufen und gesetzt                                                 
      $hb  = AttrVal($strmdev, "hideButtons", 0);                                             # Drucktasten im unteren Bereich ausblenden ?
      if($ftui) {
          $ha = AttrVal($strmdev, "htmlattrFTUI", $ha);                                       # wenn aus FTUI aufgerufen divers setzen 
      }
  }
  
  # wenn SSCamSTRM-device genutzt wird und attr "snapGalleryBoost" nicht gesetzt ist -> Warnung in Gallerie ausgeben
  my $sgbnote = " ";
  if($strmdev && !AttrVal($name,"snapGalleryBoost",0)) {
      $sgbnote = "<b>CAUTION</b> - The gallery is not updated automatically. Please set the attribute \"snapGalleryBoost=1\" in device <a href=\"$FW_ME?detail=$name\">$name</a>";
      $sgbnote = "<b>ACHTUNG</b> - Die Galerie wird nicht automatisch aktualisiert. Dazu bitte das Attribut \"snapGalleryBoost=1\" im Device <a href=\"$FW_ME?detail=$name\">$name</a> setzen." if ($lang eq "DE");
  }
  
  my $ttsnap = $ttips_en{"ttsnap"}; $ttsnap =~ s/§NAME§/$camname/xg;
  if(AttrVal("global","language","EN") =~ /DE/x) {
      $ttsnap = $ttips_de{"ttsnap"}; $ttsnap =~ s/§NAME§/$camname/xg;
  }
  
  # Header Generierung
  my $header;
  if($strmdev) {                                                                             # Forum: https://forum.fhem.de/index.php/topic,45671.msg975610.html#msg975610
      if($ftui) {
          $header .= "$dlink <br>"  if(!AttrVal($strmdev,"hideDisplayNameFTUI",0));
      } 
      else {
          $header .= "$dlink <br>"  if(!AttrVal($strmdev,"hideDisplayName",0));
      } 
  } 
  
  if ($lang eq "EN") {
      $header .= "Snapshots (_LIMIT_/$totalcnt) of camera <b>$camname</b> - newest Snapshot: $lss<br>";
      $header .= " (Possibly another snapshots are available. Last recall: $lupt)<br>" if(AttrVal($name,"snapGalleryBoost",0));
  } 
  else {
      $header .= "Schnappschüsse (_LIMIT_/$totalcnt) von Kamera <b>$camname</b> - neueste Aufnahme: $lss <br>";
      $lupt    =~ /(\d+)-(\d\d)-(\d\d)\s+(.*)/x;
      $lupt    = "$3.$2.$1 $4";
      $header .= " (Eventuell sind neuere Aufnahmen verfügbar. Letzter Abruf: $lupt)<br>" if(AttrVal($name,"snapGalleryBoost",0));
  }
  $header .= $sgbnote;
  
  my $gattr  = (AttrVal($name,"snapGallerySize","Icon") eq "Full")?$ha:"";    
  
  # Ausgabetabelle erstellen
  my $htmlCode;
  $htmlCode  = "<html>";
  $htmlCode .= "<div class=\"makeTable wide\"; style=\"text-align:$hdrAlign\"> $header <br>";
  $htmlCode .= '<table class="block wide internals" style="margin-left:auto;margin-right:auto">';
  $htmlCode .= "<tbody>";
  $htmlCode .= "<tr class=\"odd\">";
  
  my $cell  = 1;
  my $idata = "";

  # Bildaten aus Cache abrufen
  ############################
  my $count;
  $cache = cache($name, "c_init");                                                                   # Cache initialisieren  
  
  Log3($name, 1, "$name - Fall back to internal Cache due to preceding failure.") if(!$cache);                                 
  
  if(!$cache || $cache eq "internal" ) {
      $count     = scalar keys %{$data{SSCam}{$name}{SNAPHASH}} // 0;                                # Anzahl Bilddaten im Cache
      $htmlCode  =~ s{_LIMIT_}{$count}xms;                                                           # Platzhalter Snapanzahl im Header mit realem Wert ersetzen
      my $i      = 1;
      
      for my $key (sort{$a<=>$b}keys %{$data{SSCam}{$name}{SNAPHASH}}) {
          if($i > $limit) {
              $count = $limit;
              last;
          }
          
          if(!$ftui) {
              $idata = "onClick=\"FW_okDialog('<img src=data:image/jpeg;base64,$data{SSCam}{$name}{SNAPHASH}{$key}{imageData} $pws>')\"" if(AttrVal($name,"snapGalleryBoost",0));
          }
          $cell++;

          if ( $cell == $sgc+1 ) {
              $htmlCode .= sprintf("<td>$data{SSCam}{$name}{SNAPHASH}{$key}{createdTm}<br> <img src=\"data:image/jpeg;base64,$data{SSCam}{$name}{SNAPHASH}{$key}{imageData}\" $gattr $idata> </td>" );
              $htmlCode .= "</tr>";
              $htmlCode .= "<tr class=\"odd\">";
              $cell = 1;
          } 
          else {
              $htmlCode .= sprintf("<td>$data{SSCam}{$name}{SNAPHASH}{$key}{createdTm}<br> <img src=\"data:image/jpeg;base64,$data{SSCam}{$name}{SNAPHASH}{$key}{imageData}\" $gattr $idata> </td>" );
          }
          
          $idata = "";
          $i++;
      }
  } 
  else {
      my @as;
      for my $ck (cache($name, "c_getkeys")) {                                                      # relevant keys aus allen vorkommenden selektieren
          next if $ck !~ /\{SNAPHASH\}\{\d+\}\{.*\}/x;
          $ck =~ s/\{SNAPHASH\}\{(\d+)\}\{.*\}/$1/x;
          push @as,$ck if($ck =~ /^\d+$/x);
      }
      
      my %seen;
      my @unique = sort{$a<=>$b} grep { !$seen{$_}++ } @as;                                         # distinct / unique the keys 
      $count     = scalar @unique // 0;                                                             # Anzahl Bilddaten im Cache
      $htmlCode  =~ s{_LIMIT_}{$count}xms;                                                          # Platzhalter Snapanzahl im Header mit realem Wert ersetzen     
      my $i      = 1;
      
      for my $key (@unique) {
          if($i > $limit) {
              $count = $limit;
              last;
          }
          
          $imgdat = cache($name, "c_read", "{SNAPHASH}{$key}{imageData}");
          $imgTm  = cache($name, "c_read", "{SNAPHASH}{$key}{createdTm}");
          
          if(!$ftui) {
              $idata = "onClick=\"FW_okDialog('<img src=data:image/jpeg;base64,$imgdat $pws>')\"" if(AttrVal($name,"snapGalleryBoost",0));
          }
          $cell++;

          if ( $cell == $sgc+1 ) {
              $htmlCode .= sprintf("<td>$imgTm<br> <img src=\"data:image/jpeg;base64,$imgdat\" $gattr $idata> </td>" );
              $htmlCode .= "</tr>";
              $htmlCode .= "<tr class=\"odd\">";
              $cell = 1;
          } 
          else {
              $htmlCode .= sprintf("<td>$imgTm<br> <img src=\"data:image/jpeg;base64,$imgdat\" $gattr $idata> </td>" );
          }
          
          $idata = "";
          $i++;
      }  
  }

  if ( $cell == 2 ) {
      $htmlCode .= "<td> </td>";
  }
  
  $htmlCode .= "</tr>";
  
  if(!$hb) {
      $htmlCode .= "<tr>";
      $htmlCode .= "<td style=\"text-align:left\" colspan=10>";
      $htmlCode .= "<a onClick=\"$cmddosnap\" title=\"$ttsnap\">$imgdosnap </a>" if($strmdev);
      $htmlCode .= "</td>";
      $htmlCode .= "</tr>";
  }
    
  $htmlCode .= "</tbody>";
  $htmlCode .= "</table>";
  $htmlCode .= "</div>";
  $htmlCode .= "</html>";
  
  undef $imgdat;
  undef $imgTm;
  undef $idata;
  
return $htmlCode;
}

###############################################################################
#      Ermittlung Anzahl und Größe der abzurufenden Schnappschußdaten
#
#      $force = wenn auf jeden Fall der/die letzten Snaps von der SVS
#               abgerufen werden sollen unabhängig ob LastSnapId vorhanden ist
###############################################################################
sub snapLimSize {      
  my ($hash,$force) = @_;
  my $name  = $hash->{NAME};
  
  my ($slim,$ssize);
  
  if(!AttrVal($name,"snapGalleryBoost",0)) {
      $slim  = 1;
      $ssize = 0;
  } 
  else {
      $hash->{HELPER}{GETSNAPGALLERY} = 1;
      $slim                           = AttrVal($name,"snapGalleryNumber",$defSlim);      # Anzahl der abzurufenden Snaps
  }
  
  if(AttrVal($name,"snapGallerySize","Icon") eq "Full") {
      $ssize = 2;                                                                         # Full Size
  } 
  else {
      $ssize = 1;                                                                         # Icon Size
  }

  if($hash->{HELPER}{CANSENDSNAP} || $hash->{HELPER}{CANTELESNAP} || $hash->{HELPER}{CANCHATSNAP}) {
      # Versand Schnappschuß darf erfolgen falls gewünscht 
      $ssize = 2;                                                                         # Full Size für EMail/Telegram/SSChatBot -Versand
  }
  
  if($hash->{HELPER}{SNAPNUM}) {
      $slim                           = delete $hash->{HELPER}{SNAPNUM};                  # enthält die Anzahl der ausgelösten Schnappschüsse
      $hash->{HELPER}{GETSNAPGALLERY} = 1;                                                # Steuerbit für Snap-Galerie bzw. Daten mehrerer Schnappschüsse abrufen
  }
  
  my @strmdevs = devspec2array("TYPE=SSCamSTRM:FILTER=PARENT=$name:FILTER=MODEL=lastsnap");
  if(scalar(@strmdevs) >= 1) {
      Log3($name, 4, "$name - Streaming devs of type \"lastsnap\": @strmdevs");
  }
  
  $hash->{HELPER}{GETSNAPGALLERY} = 1 if($force);                                         # Bugfix 04.03.2019 Forum:https://forum.fhem.de/index.php/topic,45671.msg914685.html#msg914685
  
return ($slim,$ssize);
}

###############################################################################
#              Helper für listLog-Argumente extrahieren 
###############################################################################
sub extlogargs { 
  my ($hash,$a) = @_;

  $hash->{HELPER}{LISTLOGSEVERITY} = (split("severity:",$a))[1] if(lc($a) =~ m/^severity:/x);
  $hash->{HELPER}{LISTLOGLIMIT}    = (split("limit:",$a))[1]    if(lc($a) =~ m/^limit:/x);
  $hash->{HELPER}{LISTLOGMATCH}    = (split("match:",$a))[1]    if(lc($a) =~ m/^match:/x);
  
return;
}

###############################################################################
#     konvertiere alle ptzPanel_rowXX-attribute zu html-Code für 
#     das generierte Widget und das weblink-Device ptzPanel_$name
###############################################################################
sub ptzPanel {
  my $paref       = shift;
  my $name        = $paref->{linkparent}; 
  my $ptzcdev     = $paref->{linkname}; 
  my $ftui        = $paref->{ftui};  
  
  my $hash        = $defs{$name};
  my $iconpath    = AttrVal    ("$name", "ptzPanel_iconPath",   "www/images/sscam");
  my $iconprefix  = AttrVal    ("$name", "ptzPanel_iconPrefix", "black_btn_"      );
  my $valPresets  = ReadingsVal("$name", "Presets",             ""                );
  my $valPatrols  = ReadingsVal("$name", "Patrols",             ""                );
  my $rowisset    = 0;
  my ($pbs,$pbsf) = ("","");
  my ($row,$ptz_ret);
  
  return "" if(myVersion($hash) <= 71);
  
  $pbs      = AttrVal($ptzcdev,"ptzButtonSize",     100);                                                 # Größe der Druckbuttons in %
  $pbsf     = AttrVal($ptzcdev,"ptzButtonSizeFTUI", 100);                                                 # Größe der Druckbuttons im FTUI in %
 
  $ptz_ret  = "";
  $ptz_ret .= "<style>TD.ptzcontrol {padding: 5px 7px;}</style>";
  $ptz_ret .= "<style>TD.pcenter {text-align: center;} </style>"; 
  $ptz_ret .= "<style>.defsize { font-size:16px; } </style>";
  
  ### PTZ-Elemente
  #########################
  $ptz_ret .= '<table class="rc_body defsize">';
  $ptz_ret .= "<tr>";
  $ptz_ret .= "<td style='text-align:center' colspan=10>PTZ Control</td>";
  $ptz_ret .= "</tr>";
  $ptz_ret .= "<tr>";
  $ptz_ret .= "<td style='text-align:center' colspan=10><hr /></td>";
  $ptz_ret .= "</tr>";

  for my $rownr (0..9) {
      $rownr = sprintf("%2.2d",$rownr);
      $row   = AttrVal("$name","ptzPanel_row$rownr",undef);
      next if (!$row);
      $rowisset = 1;
      $ptz_ret .= "<tr>";
      my @btn = split (",",$row);                                                                            # die Anzahl Buttons in einer Reihe
      
      for my $btnnr (0..$#btn) {                 
          $ptz_ret .= "<td class='ptzcontrol'>";
          if ($btn[$btnnr] ne "") {
              my ($cmd,$img);
              
              if ($btn[$btnnr] =~ /(.*?):(.*)/x) {                                                           # enthält Komando -> <command>:<image>
                  $cmd = $1;
                  $img = $2;            
              } 
              else {                                                                                         # button has format <command> or is empty
                  $cmd = $btn[$btnnr];
                  $img = $btn[$btnnr];
              }
              
              if ($img =~ m/\.svg/x) {                                                                       # Verwendung für SVG's
                  $img = FW_makeImage($img, $cmd, "rc-button");
              } 
              else {                                                                                         # $FW_ME = URL-Pfad unter dem der FHEMWEB-Server via HTTP erreichbar ist, z.B. /fhem                                 
                  if($ftui) {
                      $img = "<img src=\"$FW_ME/$iconpath/$iconprefix$img\" height=\"$pbsf%\" width=\"$pbsf%\">";
                  } else {
                      $img = "<img src=\"$FW_ME/$iconpath/$iconprefix$img\" height=\"$pbs%\" width=\"$pbs%\">";  
                  }
              }
              
              if ($cmd || $cmd eq "0") {
                  my $cmd1  = "FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name $cmd')";                         # $FW_subdir = Sub-path in URL, used by FLOORPLAN/weblink
                  $cmd1     = "ftui.setFhemStatus('set $name $cmd')" if($ftui); 
                  $ptz_ret .= "<a onClick=\"$cmd1\">$img</a>";  
              } 
              else {
                  $ptz_ret .= $img;
              }
          }
          $ptz_ret .= "</td>";
          $ptz_ret .= "\n";    
      }
      $ptz_ret .= "</tr>\n";  
  }
  
  ### Zoom
  ###############################
  if(IsCapZoom($hash)) {                                                                               # wenn Zoom Eigenschaft
      
      $ptz_ret .= "<tr>";
      $ptz_ret .= "<td style='text-align:center' colspan=10><hr /></td>";
      $ptz_ret .= "</tr>";
      $ptz_ret .= "<tr>";

      my @za  = qw(.++ + stop - --.);
      
      for my $cmd (@za) {                 
          $ptz_ret .= "<td class='ptzcontrol'>";
          
          my $img = $zd{$cmd}{panimg};                                                      
          if(!$img) {
              $ptz_ret .= $cmd;
              $ptz_ret .= "</td>"; 
              next;
          }
          
          if ($img =~ m/\.svg/x) {                                                                    # Verwendung für SVG's
              $img = FW_makeImage($img, $cmd, "rc-button");
          } 
          else {                                                                                      # $FW_ME = URL-Pfad unter dem der FHEMWEB-Server via HTTP erreichbar ist, z.B. /fhem
              my $iPath = FW_iconPath($img);                                                          # automatisches Suchen der Icons im FHEMWEB iconPath
              if($iPath) {
                  $iPath = "$FW_ME/$FW_icondir/$iPath";
              } 
              else {
                  $iPath = "$FW_ME/$iconpath/$img";
              }
              
              if($ftui) {
                  $img = "<img src=\"$iPath\" height=\"$pbsf%\" width=\"$pbsf%\">";
              } 
              else {
                  $img = "<img src=\"$iPath\" height=\"$pbs%\" width=\"$pbs%\">";  
              }
          }
          
          my $cmd1  = "FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name setZoom $cmd')";                  # $FW_subdir = Sub-path in URL, used by FLOORPLAN/weblink
          $cmd1     = "ftui.setFhemStatus('set $name setZoom $cmd')" if($ftui); 
          
          $ptz_ret .= "<a onClick=\"$cmd1\">$img</a>";  

          $ptz_ret .= "</td>";  
      }
      
      $ptz_ret .= "</tr>";
  }
  
  $ptz_ret .= "</table>";
  
  ###  add Preset / Patrols
  ###############################
  if(!$ftui) {
      my ($Presets,$Patrols);
      my $cmdPreset = "goPreset";
      my $cmdPatrol = "runPatrol";
      
      ## Presets
      for my $fn (sort keys %{$data{webCmdFn}}) {
          next if($data{webCmdFn}{$fn} ne "FW_widgetFallbackFn");
          no strict "refs";                                                                    ## no critic 'NoStrict'  
          $Presets = &{$data{webCmdFn}{$fn}}($FW_wname,$name,"",$cmdPreset,$valPresets);
          use strict "refs";
          last if(defined($Presets));
      }
      if($Presets) {
          $Presets =~ s,^<td[^>]*>(.*)</td>$,$1,x;
      } 
      else {
          $Presets = FW_pH "cmd.$name=set $name $cmdPreset", $cmdPreset, 0, "", 1, 1;
      }

      ## Patrols
      for my $fn (sort keys %{$data{webCmdFn}}) {
          next if($data{webCmdFn}{$fn} ne "FW_widgetFallbackFn");
          no strict "refs";                                                                    ## no critic 'NoStrict'                     
          $Patrols = &{$data{webCmdFn}{$fn}}($FW_wname,$name,"",$cmdPatrol,$valPatrols);
          use strict "refs";
          last if(defined($Patrols));
      }
      
      if($Patrols) {
          $Patrols =~ s,^<td[^>]*>(.*)</td>$,$1,x;
      } 
      else {
          $Patrols = FW_pH "cmd.$name=set $name $cmdPatrol", $cmdPatrol, 0, "", 1, 1;
      }
           
      ## Ausgabe
      $ptz_ret .= '<table class="rc_body defsize">';
      
      if($valPresets) {
          $ptz_ret .= "<tr>";
          $ptz_ret .= "<td>Preset: </td><td>$Presets</td>";  
          $ptz_ret .= "</tr>"; 
      }
      
      if($valPatrols) {
          $ptz_ret .= "<tr>";
          $ptz_ret .= "<td>Patrol: </td><td>$Patrols</td>";
          $ptz_ret .= "</tr>";
      }

      $ptz_ret .= "</table>";     
  }
  
  if ($rowisset) {
      return $ptz_ret;
  } 
  else {
      return "";
  }
}

###############################################################################
#     spezielle Attribute für PTZ-ControlPanel verfügbar machen
###############################################################################
sub addptzattr {
  my $name = shift;
  my $hash = $defs{$name};
  
  my $actvs;
  
  my @vl = split (/\.|-/x,ReadingsVal($name, "SVSversion", ""));
  if(@vl) {
      $actvs = $vl[0];
      $actvs.= $vl[1];
  }
  return if(ReadingsVal($name,"DeviceType","Camera") ne "PTZ" || $actvs <= 71);
  
  for my $n (0..9) { 
      $n = sprintf("%2.2d",$n);
      addToDevAttrList($name, "ptzPanel_row$n");
  }
  
  my $p = ReadingsVal($name, "Presets", "");
  if($p ne "") {
      my @h;
      my $arg = "ptzPanel_Home";
      my @ua  = split " ", AttrVal($name, "userattr", "");
      for my $part (@ua) { 
          push(@h,$part) if($part !~ m/$arg.*/x);
      }
         
      $attr{$name}{userattr} = join(' ',@h);
      addToDevAttrList($name, "ptzPanel_Home:".$p);
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
  my $leftslow      = "move left 0.5";
  my $home          = "goPreset ".AttrVal($name, "ptzPanel_Home", ReadingsVal($name,"PresetHome",""));  
  my $rightslow     = "move right 0.5";
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
  $attr{$name}{ptzPanel_row02} = "$leftfast:CAMLEFTFAST.png,$leftslow:CAMLEFT.png,$home:CAMHOME.png,$rightslow:CAMRIGHT.png,$rightfast:CAMRIGHTFAST.png"
      if(!AttrVal($name,"ptzPanel_row02",undef) || $home ne $hash->{HELPER}{OLDPTZHOME});  
  $attr{$name}{ptzPanel_row03} = ":CAMBLANK.png,$downleft:CAMDOWNLEFT.png,$down:CAMDOWN.png,$downright:CAMDOWNRIGHT.png"
      if(!AttrVal($name,"ptzPanel_row03",undef));  
  $attr{$name}{ptzPanel_row04} = "$downleftfast:CAMDOWNLEFTFAST.png,:CAMBLANK.png,$downfast:CAMDOWNFAST.png,:CAMBLANK.png,$downrightfast:CAMDOWNRIGHTFAST.png"
      if(!AttrVal($name,"ptzPanel_row04",undef));
      
  $hash->{HELPER}{OLDPTZHOME} = $home;
  $hash->{".ptzhtml"}         = "";                                          # ptzPanel wird neu eingelesen
  
return;
}

##############################################################################
# Zusätzliche Redings in Rotation erstellen
# Sub ($hash,<readingName>,<Wert>,<Rotationszahl>,<Trigger[0|1]>)
##############################################################################
sub rotateReading {
  my ($hash,$readingName,$val,$rotnum,$do_trigger) = @_;
  my $name = $hash->{NAME};

  readingsBeginUpdate($hash);
  
  my $o = ReadingsVal($name,$readingName,"n.a."); 
  if($val ne "n.a." && $rotnum >= 1) {
      if("$o" ne "$val") {     
          for (my $i=$rotnum;$i>0;$i--) {
              my $l = $i-1;
              my $g = ReadingsVal($name,$readingName.$i,"n.a.");
              
              if($l) {
                  $l = ReadingsVal($name,$readingName.$l,"n.a.");
              } 
              else {
                  $l = ReadingsVal($name,$readingName,"n.a.");
              }
              
              if("$l" ne "$g") {
                  readingsBulkUpdate($hash,$readingName.$i,$l);
                  Log3($name, 4, "$name - Rotate \"$readingName.$i\" to value: $l");
              }
          }
      }      
  
  }
  readingsBulkUpdate($hash,$readingName,$val);
  readingsEndUpdate($hash, $do_trigger);
  
return;
}

#############################################################################################
#                              Vorbereitung  SMTP EMail-Versand
#       $OpMode = aktueller Operation Mode zur Unterscheidung was versendet werden soll
#       $dat   = zu versendende Daten, evtl. als Hash Referenz
#############################################################################################
sub prepareSendData { 
   my ($hash, $OpMode, $dat) = @_;
   my $name   = $hash->{NAME};
   my $calias = AttrVal($name,"alias",$hash->{CAMNAME});              # Alias der Kamera wenn gesetzt oder Originalname aus SVS
   my $type   = AttrVal($name,"cacheType","internal");
   my ($ret,$vdat,$fname,$snapid,$tac) = ('','','','','');
   my @as;
      
   # prüfen ob Schnappschnüsse aller Kameras durch ein SVS-Device angefordert wurde,
   # Bilddaten jeder Kamera werden nach Erstellung dem zentralen Schnappshußhash hinzugefügt
   # Bilddaten werden erst zum Versand weitergeleitet wenn Schnappshußhash komplett gefüllt ist
   
   my $asref;
   my @allsvs = devspec2array("TYPE=SSCam:FILTER=MODEL=SVS");
   
   for my $svs (@allsvs) {
       my $svshash;
       $svshash = $defs{$svs} if($defs{$svs});
       next if(!$svshash                          || 
               !AttrVal($svs, "snapEmailTxt", "") ||
               !$svshash->{HELPER}{ALLSNAPREF}    ||        
               !$svshash->{HELPER}{CANSENDSNAP});                                                 # Sammel-Schnappschüsse nur senden wenn CANSENDSNAP und Attribut gesetzt ist
       
       $asref = $svshash->{HELPER}{ALLSNAPREF};                                                   # Hashreferenz zum summarischen Snaphash
       
       for my $key (keys%{$asref}) {
           if($key eq $name) {                                                                    # Kamera Key im Bildhash matcht -> Bilddaten übernehmen
                if($type eq "internal") {
                    
                    for my $pkey (keys%{$dat}) {
                        my $nkey = time()+int(rand(1000));
                        
                        $asref->{$nkey.$pkey}{createdTm} = $dat->{$pkey}{createdTm};              # Aufnahmezeit der Kamera werden im summarischen Snaphash eingefügt
                        $asref->{$nkey.$pkey}{imageData} = $dat->{$pkey}{imageData};              # Bilddaten der Kamera werden im summarischen Snaphash eingefügt
                        $asref->{$nkey.$pkey}{fileName}  = $dat->{$pkey}{fileName};               # Filenamen der Kamera werden im summarischen Snaphash eingefügt
                        
                        Log3($svs, 4, "$svs - Central Snaphash filled up with snapdata of cam \"$name\" and key [".$nkey.$pkey."]");  
                    }
                } 
                else {
                    # alle Serial Numbers "{$sn}" der Transaktion ermitteln
                    # Muster: {SENDSNAPS}{2222}{0}{imageData} 
                    extractTIDfromCache ( { name  => $name,  
                                            media => "SENDSNAPS",
                                            mode  => "serial",
                                            aref  => \@as
                                          } 
                                        );      
                    my %seen;
                    my @unique = sort{$a<=>$b} grep { !$seen{$_}++ } @as;                                           # distinct / unique the keys 

                    for my $pkey (@unique) {
                        next if(!cache($name, "c_isvalidkey", "$dat"."{$pkey}{imageData}")); 
                        my $nkey = time()+int(rand(1000));
                        
                        $asref->{$nkey.$pkey}{createdTm} = cache($name, "c_read", "$dat"."{$pkey}{createdTm}");     # Aufnahmezeit der Kamera werden im summarischen Snaphash eingefügt
                        $asref->{$nkey.$pkey}{imageData} = cache($name, "c_read", "$dat"."{$pkey}{imageData}");     # Bilddaten der Kamera werden im summarischen Snaphash eingefügt
                        $asref->{$nkey.$pkey}{fileName}  = cache($name, "c_read", "$dat"."{$pkey}{fileName}");      # Filenamen der Kamera werden im summarischen Snaphash eingefügt
                        
                        Log3($svs, 4, "$svs - Central Snaphash filled up with snapdata of cam \"$name\" and key [".$nkey.$pkey."]");  
                    }               
                }                    
                
                delete $hash->{HELPER}{CANSENDSNAP};               # Flag im Kamera-Device !! löschen
                delete $asref->{$key};                             # ursprünglichen Key (Kameranamen) löschen
           }
       }
       $asref = $svshash->{HELPER}{ALLSNAPREF};                    # Hashreferenz zum summarischen Snaphash
       
       for my $key (keys%{$asref}) {                               # prüfen ob Bildhash komplett ?
           if(!$asref->{$key}) {
               return;                                             # Bildhash noch nicht komplett                                 
           }
       }
   
       delete $svshash->{HELPER}{ALLSNAPREF};                      # ALLSNAPREF löschen -> gemeinsamer Versand beendet
       $hash = $svshash;                                           # Hash durch SVS-Hash ersetzt
       $name = $svshash->{NAME};                                   # Name des auslösenden SVS-Devices wird eingesetzt  
       
       Log3($name, 4, "$name - Central Snaphash fillup completed by all selected cams. Send it now ...");           
       
       my $cache = cache($name, "c_init");                         # Cache initialisieren (im SVS Device)
       
       if(!$cache || $cache eq "internal" ) {
           delete $data{SSCam}{RS};           
           for my $key (keys%{$asref}) {                           # Referenz zum summarischen Hash einsetzen        
               $data{SSCam}{RS}{$key} = delete $asref->{$key};                     
           }    
           $dat = $data{SSCam}{RS};                                # Referenz zum summarischen Hash einsetzen
       } 
       else {
           cache($name, "c_clear"); 
           for my $key (keys%{$asref}) {
               cache($name, "c_write", "{RS}{multiple_snapsend}{$key}{createdTm}", delete $asref->{$key}{createdTm});
               cache($name, "c_write", "{RS}{multiple_snapsend}{$key}{imageData}", delete $asref->{$key}{imageData});
               cache($name, "c_write", "{RS}{multiple_snapsend}{$key}{fileName}",  delete $asref->{$key}{fileName});  
           }
           $dat = "{RS}{multiple_snapsend}";                       # Referenz zum summarischen Hash einsetzen           
       }
       
       $calias = AttrVal($name,"alias",$hash->{NAME});             # Alias des SVS-Devices 
       $hash->{HELPER}{TRANSACTION} = "multiple_snapsend";         # fake Transaction im SVS Device setzen 
       last;                                                       # Schleife verlassen und mit Senden weiter
   }
   
   my $sp       = AttrVal($name, "smtpPort", 25); 
   my $nousessl = AttrVal($name, "smtpNoUseSSL", 0); 
   
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
   
   my $date     = sprintf "%02d.%02d.%04d" , $mday , $mon+=1 ,$year+=1900; 
   my $time     = sprintf "%02d:%02d:%02d" , $hour , $min , $sec;   
   
   my $sslfrominit = 0;
   my $smtpsslport = 465;
   
   if(AttrVal($name,"smtpSSLPort",0)) {
       $sslfrominit = 1;
       $smtpsslport = AttrVal($name,"smtpSSLPort",0);
   }
   
   $tac                                 = $hash->{HELPER}{TRANSACTION};         # Code der laufenden Transaktion
   
   $data{SSCam}{$name}{SENDCOUNT}{$tac} = 0;                                    # Hilfszähler Senden, init -> +1 , done -> -1, keine Daten
                                                                                # d. Transaktion werden gelöscht bis Zähler wieder 0 !! (siehe closeTrans)
   
   Log3($name, 1, "$name - Send Counter transaction \"$tac\": ".$data{SSCam}{$name}{SENDCOUNT}{$tac}) if(AttrVal($name,"debugactivetoken",0));
   
   ### Schnappschüsse als Email versenden wenn $hash->{HELPER}{CANSENDSNAP} definiert ist
   ######################################################################################
   if($OpMode =~ /^getsnap/x && $hash->{HELPER}{CANSENDSNAP}) {     
       delete $hash->{HELPER}{CANSENDSNAP};
       $data{SSCam}{$name}{SENDCOUNT}{$tac}++;
       
       Log3($name, 1, "$name - Send Counter transaction \"$tac\": ".$data{SSCam}{$name}{SENDCOUNT}{$tac}) if(AttrVal($name,"debugactivetoken",0));
       
       my $mt = delete $hash->{HELPER}{SMTPMSG};  
       
       my $param = {
           hash   => $hash,
           calias => $calias,
           mt     => $mt,
           date   => $date,
           time   => $time,
       };
       my $smtpmsg = _prepSendMail ($param);
           
       $ret = _sendEmail($hash, {
                                 'subject'      => $smtpmsg->{subject},   
                                 'part1txt'     => $smtpmsg->{body}, 
                                 'part2type'    => 'image/jpeg',
                                 'smtpport'     => $sp,
                                 'sdat'         => $dat,
                                 'opmode'       => $OpMode,
                                 'smtpnousessl' => $nousessl,
                                 'sslfrominit'  => $sslfrominit,
                                 'smtpsslport'  => $smtpsslport, 
                                 'tac'          => $tac,                                  
                                }
                        );
                       
       readingsSingleUpdate($hash, "sendEmailState", $ret, 1) if ($ret);
   }
   
   ### Aufnahmen als Email versenden wenn $hash->{HELPER}{CANSENDREC} definiert ist
   ################################################################################
   if($OpMode =~ /^GetRec/x && $hash->{HELPER}{CANSENDREC}) {     
       delete $hash->{HELPER}{CANSENDREC};
       $data{SSCam}{$name}{SENDCOUNT}{$tac}++;
       
       Log3($name, 1, "$name - Send Counter transaction \"$tac\": ".$data{SSCam}{$name}{SENDCOUNT}{$tac}) if(AttrVal($name,"debugactivetoken",0));
       
       my $mt = delete $hash->{HELPER}{SMTPRECMSG};
       
       my $param = {
           hash   => $hash,
           calias => $calias,
           mt     => $mt,
           date   => $date,
           time   => $time,
       };
       my $smtpmsg = _prepSendMail ($param);
            
       $ret = _sendEmail($hash, {
                                 'subject'      => $smtpmsg->{subject},   
                                 'part1txt'     => $smtpmsg->{body}, 
                                 'part2type'    => 'video/mpeg',
                                 'smtpport'     => $sp,
                                 'vdat'         => $dat,
                                 'opmode'       => $OpMode,
                                 'smtpnousessl' => $nousessl,
                                 'sslfrominit'  => $sslfrominit,
                                 'smtpsslport'  => $smtpsslport,
                                 'tac'          => $tac,                                      
                                }
                        );
                       
       readingsSingleUpdate($hash, "sendEmailState", $ret, 1) if ($ret);
   }

   ### Schnappschüsse mit Telegram versenden
   #########################################
   if($OpMode =~ /^getsnap/x && $hash->{HELPER}{CANTELESNAP}) {     
       # snapTelegramTxt aus $hash->{HELPER}{TELEMSG}
       # Format in $hash->{HELPER}{TELEMSG} muss sein: tbot => <teleBot Device>, peers => <peer1 peer2 ..>, subject => <Beschreibungstext>
       delete $hash->{HELPER}{CANTELESNAP};
       $data{SSCam}{$name}{SENDCOUNT}{$tac}++;
       
       Log3($name, 1, "$name - Send Counter transaction \"$tac\": ".$data{SSCam}{$name}{SENDCOUNT}{$tac}) if(AttrVal($name,"debugactivetoken",0));
       
       my $mt = delete $hash->{HELPER}{TELEMSG};
       
       my $param = {
           hash   => $hash,
           calias => $calias,
           mt     => $mt,
           date   => $date,
           time   => $time,
       };
       my $telemsg = _prepSendTelegram ($param);
        
       $ret = _sendTelegram($hash, {
                                    'subject'     => $telemsg->{subject},
                                    'part2type'   => 'image/jpeg',
                                    'sdat'        => $dat,
                                    'opmode'      => $OpMode,
                                    'tac'         => $tac, 
                                    'telebot'     => $telemsg->{tbot}, 
                                    'peers'       => $telemsg->{peers},                                      
                                    'MediaStream' => '-1',                       # Code für MediaStream im TelegramBot (png/jpg = -1)
                                   }
                           );
                          
       readingsSingleUpdate($hash, "sendTeleState", $ret, 1) if ($ret);                                
   }

   ### Aufnahmen mit Telegram versenden
   ####################################
   if($OpMode =~ /^GetRec/x && $hash->{HELPER}{CANTELEREC}) {   
       # recTelegramTxt aus $hash->{HELPER}{TELERECMSG}
       # Format in $hash->{HELPER}{TELEMSG} muss sein: tbot => <teleBot Device>, peers => <peer1 peer2 ..>, subject => <Beschreibungstext>
       delete $hash->{HELPER}{CANTELEREC};
       $data{SSCam}{$name}{SENDCOUNT}{$tac}++;
       
       Log3($name, 1, "$name - Send Counter transaction \"$tac\": ".$data{SSCam}{$name}{SENDCOUNT}{$tac}) if(AttrVal($name,"debugactivetoken",0));
       
       my $mt = delete $hash->{HELPER}{TELERECMSG};
       
       my $param = {
           hash   => $hash,
           calias => $calias,
           mt     => $mt,
           date   => $date,
           time   => $time,
       };
       my $telemsg = _prepSendTelegram ($param);
       
       $vdat = $dat;  
       $ret  = _sendTelegram($hash, {
                                     'subject'     => $telemsg->{subject},
                                     'vdat'        => $vdat,
                                     'opmode'      => $OpMode, 
                                     'telebot'     => $telemsg->{tbot}, 
                                     'peers'       => $telemsg->{peers},
                                     'tac'         => $tac,                                         
                                     'MediaStream' => '-30',                       # Code für MediaStream im TelegramBot (png/jpg = -1)
                                    }
                            );
                           
       readingsSingleUpdate($hash, "sendTeleState", $ret, 1) if ($ret);                                  
   }
   
   ### Schnappschüsse mit Synology Chat versenden
   ##############################################
   if($OpMode =~ /^getsnap/x && $hash->{HELPER}{CANCHATSNAP}) {     
       # snapChatTxt aus $hash->{HELPER}{CHATMSG}
       # Format in $hash->{HELPER}{CHATMSG} muss sein: snapChatTxt:"chatbot => <SSChatBot Device>, peers => <peer1 peer2 ..>, subject => <Beschreibungstext>"
       delete $hash->{HELPER}{CANCHATSNAP};
       $data{SSCam}{$name}{SENDCOUNT}{$tac}++;
       
       Log3($name, 1, "$name - Send Counter transaction \"$tac\": ".$data{SSCam}{$name}{SENDCOUNT}{$tac}) if(AttrVal($name,"debugactivetoken",0));
       
       my $mt = delete $hash->{HELPER}{CHATMSG};
       
       my $param = {
           hash   => $hash,
           calias => $calias,
           mt     => $mt,
           date   => $date,
           time   => $time,
       };
       my $chatmsg = _prepSendChat ($param);
        
       $ret = _sendChat($hash, {
                                'subject' => $chatmsg->{subject},
                                'opmode'  => $OpMode,
                                'tac'     => $tac,
                                'sdat'    => $dat,                                     
                                'chatbot' => $chatmsg->{chatbot}, 
                                'peers'   => $chatmsg->{peers},
                               }
                       );
                      
       readingsSingleUpdate($hash, "sendChatState", $ret, 1) if ($ret);                                
   }
   
   ### Aufnahmen mit Synology Chat versenden
   #########################################
   if($OpMode =~ /^GetRec/x && $hash->{HELPER}{CANCHATREC}) {   
       # recChatTxt aus $hash->{HELPER}{CHATRECMSG}
       # Format in $hash->{HELPER}{CHATRECMSG} muss sein: chatbot => <SSChatBot Device>, peers => <peer1 peer2 ..>, subject => <Beschreibungstext>
       delete $hash->{HELPER}{CANCHATREC};
       $data{SSCam}{$name}{SENDCOUNT}{$tac}++;
       
       Log3($name, 1, "$name - Send Counter transaction \"$tac\": ".$data{SSCam}{$name}{SENDCOUNT}{$tac}) if(AttrVal($name,"debugactivetoken",0));
       
       my $mt = delete $hash->{HELPER}{CHATRECMSG};
       
       my $param = {
           hash   => $hash,
           calias => $calias,
           mt     => $mt,
           date   => $date,
           time   => $time,
       };
       my $chatmsg = _prepSendChat ($param);
       
       $ret = _sendChat($hash, {
                                'subject' => $chatmsg->{subject},
                                'opmode'  => $OpMode, 
                                'tac'     => $tac,  
                                'vdat'    => $dat,
                                'chatbot' => $chatmsg->{chatbot},
                                'peers'   => $chatmsg->{peers},                         
                               }
                       );
                      
       readingsSingleUpdate($hash, "sendChatState", $ret, 1) if ($ret);                                  
   }
   
   closeTrans($hash) if($hash->{HELPER}{TRANSACTION} eq "multiple_snapsend");     # Transaction Sammelversand (SVS) schließen, Daten bereinigen 
   
return;
}

###############################################################################
#                 Vorbereitung Versand Chatnachrichten
###############################################################################
sub _prepSendChat { 
   my $paref  = shift;
   my $hash   = $paref->{hash};
   my $calias = $paref->{calias};
   my $mt     = $paref->{mt};
   my $date   = $paref->{date};
   my $time   = $paref->{time};
   my $name   = $hash->{NAME}; 

   my ($cbott,$peert,$subjt);
   
   $mt =~ s/['"]//gx;
   
   my ($chatbot,$peers,$subj) =  split(",",  $mt, 3  );
   $cbott                     = (split("=>", $chatbot))[1] if($chatbot);
   $peert                     = (split("=>", $peers  ))[1] if($peers);
   $subjt                     = (split("=>", $subj   ))[1] if($subj);

   $cbott = trim($cbott) if($cbott);
   $peert = trim($peert) if($peert);
   
   if($subjt) {
       $subjt = trim($subjt);
       $subjt =~ s/\$CAM/$calias/gx;
       $subjt =~ s/\$DATE/$date/gx;
       $subjt =~ s/\$TIME/$time/gx;
   }     
   
   my %chatmsg       = ();
   $chatmsg{chatbot} = "$cbott" if($cbott);
   $chatmsg{peers}   = "$peert" if($peert);
   $chatmsg{subject} = "$subjt" if($subjt);
   
return \%chatmsg;
}

#############################################################################################
#                                   Synology Chat-Versand
#############################################################################################
sub _sendChat { 
   my ($hash, $extparamref) = @_;
   my $name  = $hash->{NAME};
   my $type  = AttrVal($name,"cacheType","internal");
   my $mtype = "";
   my ($params,$ret,$cache);
   
   Log3($name, 4, "$name - ####################################################"); 
   Log3($name, 4, "$name - ###      start send Snap or Video by SSChatBot      "); 
   Log3($name, 4, "$name - ####################################################");
   
   my %chatparams = (
       'subject'        => {                          'default'=>'', 'required'=>1, 'set'=>1},
       'opmode'         => {                          'default'=>'', 'required'=>1, 'set'=>1},  # OpMode muss gesetzt sein
       'tac'            => {                          'default'=>'', 'required'=>0, 'set'=>1},  # übermittelter Transaktionscode der ausgewerteten Transaktion
       'sdat'           => {                          'default'=>'', 'required'=>0, 'set'=>1},  # Hashref der Bilddaten (Bilddaten base64 codiert)
       'vdat'           => {                          'default'=>'', 'required'=>0, 'set'=>1},  # Hashref der Videodaten
       'chatbot'        => {                          'default'=>'', 'required'=>1, 'set'=>1},  # SSChatBot-Device welches zum Senden verwendet werden soll
       'peers'          => {                          'default'=>'', 'required'=>0, 'set'=>1},  # SSChatBot Peers
       'videofolderMap' => {'attr'=>'videofolderMap', 'default'=>'', 'required'=>1, 'set'=>1},  # Wert des Attributs videofolderMap (muss gesetzt sein !)
       );   
   
   my $tac = $extparamref->{tac};
   
   for my $key (keys %chatparams) {
       $data{SSCam}{$name}{PARAMS}{$tac}{$key} = AttrVal($name, $chatparams{$key}->{attr}, $chatparams{$key}->{default}) 
                                                   if(exists $chatparams{$key}->{attr}); 
       if($chatparams{$key}->{set}) {     
           $data{SSCam}{$name}{PARAMS}{$tac}{$key} = $chatparams{$key}->{default} if (!$extparamref->{$key} && !$chatparams{$key}->{attr});    
           $data{SSCam}{$name}{PARAMS}{$tac}{$key} = delete $extparamref->{$key}  if(exists $extparamref->{$key});
       }

       Log3($name, 4, "$name - param $key is set to \"".($data{SSCam}{$name}{PARAMS}{$tac}{$key} // "")."\" ") if($key !~ /[sv]dat/x);
       Log3($name, 4, "$name - param $key is set")                                                             if($key =~ /[sv]dat/x && $data{SSCam}{$name}{PARAMS}{$tac}{$key} ne '');
   }
   
   $data{SSCam}{$name}{PARAMS}{$tac}{name} = $name;
   
   my @err = ();
   for my $key (keys(%chatparams)) {
       push(@err, $key) if ($chatparams{$key}->{required} && !$data{SSCam}{$name}{PARAMS}{$tac}{$key});
   }
   
   if ($#err >= 0) {
       $ret = "Missing at least one required parameter or attribute: ".join(', ',@err);
       Log3($name, 2, "$name - $ret");
       
       readingsBeginUpdate ($hash);
       readingsBulkUpdate  ($hash,"sendChatState",$ret);
       readingsEndUpdate   ($hash, 1);
       
       $data{SSCam}{$name}{SENDCOUNT}{$tac} -= 1;
       return $ret;
   }
   
   my $chatbot = $data{SSCam}{$name}{PARAMS}{$tac}{chatbot};
   my $peers   = $data{SSCam}{$name}{PARAMS}{$tac}{peers}; 
   my $rootUrl = $data{SSCam}{$name}{PARAMS}{$tac}{videofolderMap};
   
   if(!$defs{$chatbot}) {
       $ret = "No SSChatBot device \"$chatbot\" available";
       readingsSingleUpdate($hash, "sendChatState", $ret, 1);
       Log3($name, 2, "$name - $ret");
       $data{SSCam}{$name}{SENDCOUNT}{$tac} -= 1;
       return;
   }
  
   if(!$peers) {
       $peers = AttrVal($chatbot,"defaultPeer", "");
       if(!$peers) {
           $ret = "No peers of SSChatBot device \"$chatbot\" found";
           readingsSingleUpdate($hash, "sendChatState", $ret, 1);
           Log3($name, 2, "$name - $ret");
           $data{SSCam}{$name}{SENDCOUNT}{$tac} -= 1;
           return;       
       }
   } 
   else {
       $peers = join(",", split(" ", $peers));       
   }

   if(!$data{SSCam}{$name}{PARAMS}{$tac}{sdat} && !$data{SSCam}{$name}{PARAMS}{$tac}{vdat}) {
       $ret = "no video or image data existing for send process by SSChatBot \"$chatbot\" ";
       readingsSingleUpdate($hash, "sendChatState", $ret, 1);
       Log3($name, 2, "$name - $ret");
       $data{SSCam}{$name}{SENDCOUNT}{$tac} -= 1;
       return;   
   } 
                                    
  my ($subject,$fileUrl,$uid,$fname,@as,%seen,@unique);
  
  $cache = cache($name, "c_init");                                                           # Cache initialisieren        
  Log3($name, 1, "$name - Fall back to internal Cache due to preceding failure.") if(!$cache);
  
  if(!$cache || $cache eq "internal" ) {
      if($data{SSCam}{$name}{PARAMS}{$tac}{sdat}) {                                          # Images liegen in einem Hash (Ref in $sdat) base64-codiert vor
          @as    = sort{$b<=>$a}keys%{$data{SSCam}{$name}{PARAMS}{$tac}{sdat}};
          $mtype = "\@Snapshot";
      } 
      elsif($data{SSCam}{$name}{PARAMS}{$tac}{vdat}) {                                       # Aufnahmen liegen in einem Hash-Ref in $vdat vor
          @as    = sort{$b<=>$a}keys%{$data{SSCam}{$name}{PARAMS}{$tac}{vdat}};
          $mtype = $hash->{CAMNAME};
      }
      
      for my $key (@as) {
           ($subject,$fname) = __extractForChat($name,$key,$data{SSCam}{$name}{PARAMS}{$tac});
           
           my @ua = split(",", $peers);                                                     # User aufsplitten und zu jedem die ID ermitteln
           for (@ua) {
               next if(!$_);
               $uid = $defs{$chatbot}{HELPER}{USERS}{$_}{id};
               if(!$uid) {
                   $ret = "The receptor \"$_\" seems to be unknown because its ID coulnd't be found.";
                   readingsSingleUpdate($hash, "sendChatState", $ret, 1);
                   Log3($name, 2, "$name - $ret");
                   $data{SSCam}{$name}{SENDCOUNT}{$tac} -= 1;
                   return; 
               }
               
               # Eintrag zur SendQueue hinzufügen
               # Werte: (name,opmode,method,userid,text,fileUrl,channel,attachment)
               $fileUrl = $rootUrl."/".$mtype."/".$fname;
               $subject = FHEM::SSChatBot::formString ($subject, "text"); 
               
               $params = { 
                   name       => $chatbot,
                   opmode     => "sendItem",
                   method     => "chatbot",
                   userid     => $uid,
                   text       => $subject,
                   fileUrl    => $fileUrl,
                   channel    => "",
                   attachment => ""
               };
               $ret = FHEM::SSChatBot::addSendqueue ($params); 

               if($ret) {
                   readingsSingleUpdate($hash, "sendChatState", $ret, 1);
                   Log3($name, 2, "$name - ERROR: $ret");
               } 
               else {
                   $ret = "Chat message [$key] of transaction \"$tac\" for \"$_\" added to \"$chatbot\" sendqueue";
                   readingsSingleUpdate($hash, "sendChatState", $ret, 1);
                   Log3($name, 3, "$name - $ret");
               }
           }           
      }
      $data{SSCam}{$name}{SENDCOUNT}{$tac} -= 1;
      Log3($name, 1, "$name - Send Counter transaction \"$tac\": ".$data{SSCam}{$name}{SENDCOUNT}{$tac}) if(AttrVal($name,"debugactivetoken",0)); 
  } 
  else {
      # alle Serial Numbers "{$sn}" der Transaktion ermitteln 
      if($data{SSCam}{$name}{PARAMS}{$tac}{sdat}) {                                          # Images liegen in einem Hash (Ref in $sdat) base64-codiert vor
          extractTIDfromCache ( { name  => $name, 
                                  tac   => $tac, 
                                  media => "SENDSNAPS",
                                  mode  => "serial",
                                  aref  => \@as
                                } 
                              );
          $mtype  = "\@Snapshot";   
      } 
      elsif($data{SSCam}{$name}{PARAMS}{$tac}{vdat}) {                                     # Aufnahmen liegen in einem Hash-Ref in $vdat vor
          extractTIDfromCache ( { name  => $name, 
                                  tac   => $tac, 
                                  media => "SENDRECS",
                                  mode  => "serial",
                                  aref  => \@as
                                } 
                              );        
          $mtype  = $hash->{CAMNAME};
      }
      
      @unique = sort{$b<=>$a} grep { !$seen{$_}++ } @as;                                     # distinct / unique the keys
      
      for my $key (@unique) {
           ($subject,$fname) = __extractForChat($name,$key,$data{SSCam}{$name}{PARAMS}{$tac});
           
           my @ua = split(/,/x, $peers);                                                     # User aufsplitten und zu jedem die ID ermitteln
           for (@ua) {
               next if(!$_);
               $uid = $defs{$chatbot}{HELPER}{USERS}{$_}{id};
               if(!$uid) {
                   $ret = "The receptor \"$_\" seems to be unknown because its ID coulnd't be found.";
                   readingsSingleUpdate($hash, "sendChatState", $ret, 1);
                   Log3($name, 2, "$name - $ret");
                   $data{SSCam}{$name}{SENDCOUNT}{$tac} -= 1;
                   return; 
               }
               
               # Eintrag zur SendQueue hinzufügen
               # Werte: (name,opmode,method,userid,text,fileUrl,channel,attachment)
               $fileUrl = $rootUrl."/".$mtype."/".$fname;
               $subject = FHEM::SSChatBot::formString ($subject, "text"); 
               
               $params = { 
                   name       => $chatbot,
                   opmode     => "sendItem",
                   method     => "chatbot",
                   userid     => $uid,
                   text       => $subject,
                   fileUrl    => $fileUrl,
                   channel    => "",
                   attachment => ""
               };
               $ret = FHEM::SSChatBot::addSendqueue ($params);
           
               if($ret) {
                   readingsSingleUpdate($hash, "sendChatState", $ret, 1);
                   Log3($name, 2, "$name - ERROR: $ret");
               } 
               else {
                   $ret = "Chat message [$key] of transaction \"$tac\" for \"$_\" added to \"$chatbot\" sendqueue";
                   readingsSingleUpdate($hash, "sendChatState", $ret, 1);
                   Log3($name, 3, "$name - $ret");
               }
           }           
      }      
      
      $data{SSCam}{$name}{SENDCOUNT}{$tac} -= 1;
      Log3($name, 1, "$name - Send Counter transaction \"$tac\": ".$data{SSCam}{$name}{SENDCOUNT}{$tac}) if(AttrVal($name,"debugactivetoken",0));
  }
  
  FHEM::SSChatBot::getApiSites ($chatbot);                           # Übertragung Sendqueue starten
  
  # use strict "refs";
  undef %chatparams;
  undef %{$extparamref};
  
return;
}

####################################################################################################
#                            Daten extrahieren für SSChatBot Versand
####################################################################################################
sub __extractForChat {
  my $name    = shift;
  my $key     = shift;
  my $paref   = shift;
  my $hash    = $defs{$name};
  my $subject = $paref->{subject};
  my $sdat    = $paref->{sdat};                           # Hash von Imagedaten base64 codiert
  my $vdat    = $paref->{vdat};                           # Hashref der Videodaten   
  
  my ($fname,$tdir,$ct,$cache);
  
  if($sdat) {
      $cache = cache($name, "c_init");                    # Cache initialisieren        
      if(!$cache || $cache eq "internal" ) {
          $ct    = $paref->{sdat}{$key}{createdTm};
          $fname = trim ($paref->{sdat}{$key}{fileName});      
      } 
      else {
          $ct    = cache($name, "c_read", "$sdat"."{$key}{createdTm}");
          $fname = trim( cache($name, "c_read", "$sdat"."{$key}{fileName}") );        
      }
  } 
  
  if($vdat) {
      $cache = cache($name, "c_init");                    # Cache initialisieren        
      if(!$cache || $cache eq "internal" ) {
          $ct    = $paref->{vdat}{$key}{createdTm};
          $fname = trim ($paref->{vdat}{$key}{fileName});
          $tdir  = trim ($paref->{vdat}{$key}{tdir});
      } 
      else {
          $ct    = cache($name, "c_read", "$vdat"."{$key}{createdTm}");  
          $fname = trim( cache($name, "c_read", "$vdat"."{$key}{fileName}") );
          $tdir  = trim( cache($name, "c_read", "$vdat"."{$key}{tdir}") );
      }
      $fname = $tdir."/".$fname;
  }
  
  $subject =~ s/\$FILE/$fname/gx;
  $subject =~ s/\$CTIME/$ct/gx;
 
return ($subject,$fname);
}

###############################################################################
#                 Vorbereitung Versand Telegramnachrichten
###############################################################################
sub _prepSendTelegram { 
   my $paref  = shift;
   my $hash   = $paref->{hash};
   my $calias = $paref->{calias};
   my $mt     = $paref->{mt};
   my $date   = $paref->{date};
   my $time   = $paref->{time};
   my $name   = $hash->{NAME};

   my ($tbott,$peert,$subjt);
   
   $mt    =~ s/['"]//gx;
   
   my ($telebot,$peers,$subj) =  split(",",  $mt, 3  );
   $tbott                     = (split("=>", $telebot))[1] if($telebot);
   $peert                     = (split("=>", $peers  ))[1] if($peers);
   $subjt                     = (split("=>", $subj   ))[1] if($subj);

   $tbott = trim($tbott) if($tbott);
   $peert = trim($peert) if($peert);
   
   if($subjt) {
       $subjt = trim($subjt);
       $subjt =~ s/\$CAM/$calias/gx;
       $subjt =~ s/\$DATE/$date/gx;
       $subjt =~ s/\$TIME/$time/gx;
   }       
   
   my %telemsg       = ();
   $telemsg{tbot}    = "$tbott" if($tbott);
   $telemsg{peers}   = "$peert" if($peert);
   $telemsg{subject} = "$subjt" if($subjt);
   
return \%telemsg;
}

#############################################################################################
#                                   Telegram-Versand
#############################################################################################
sub _sendTelegram { 
   my ($hash, $extparamref) = @_;
   my $name = $hash->{NAME};
   my $type = AttrVal($name,"cacheType","internal");
   my ($ret,$cache);
   
   Log3($name, 4, "$name - ####################################################"); 
   Log3($name, 4, "$name - ###     start send Snap or Video by TelegramBot     "); 
   Log3($name, 4, "$name - ####################################################");
   
   my %teleparams = (
       'subject'      => {                       'default'=>'',                          'required'=>0, 'set'=>1},
       'part1type'    => {                       'default'=>'text/plain; charset=UTF-8', 'required'=>1, 'set'=>1},
       'part1txt'     => {                       'default'=>'',                          'required'=>0, 'set'=>1},
       'part2type'    => {                       'default'=>'',                          'required'=>0, 'set'=>1},
       'sdat'         => {                       'default'=>'',                          'required'=>0, 'set'=>1},  # Hashref der Bilddaten (Bilddaten base64 codiert), wenn gesetzt muss 'part2type' auf 'image/jpeg' gesetzt sein
       'image'        => {                       'default'=>'',                          'required'=>0, 'set'=>1},  # Daten als File, wenn gesetzt muss 'part2type' auf 'image/jpeg' gesetzt sein
       'fname'        => {                       'default'=>'',                          'required'=>0, 'set'=>1},  # Filename für "image"
       'lsnaptime'    => {                       'default'=>'',                          'required'=>0, 'set'=>1},  # Zeitstempel der Bilddaten
       'opmode'       => {                       'default'=>'',                          'required'=>1, 'set'=>1},  # OpMode muss gesetzt sein
       'tac'          => {                       'default'=>'',                          'required'=>0, 'set'=>1},  # übermittelter Transaktionscode der ausgewerteten Transaktion
       'vdat'         => {                       'default'=>'',                          'required'=>0, 'set'=>1},  # Hashref der Videodaten
       'telebot'      => {                       'default'=>'',                          'required'=>1, 'set'=>1},  # TelegramBot-Device welches zum Senden verwendet werden soll
       'peers'        => {                       'default'=>'',                          'required'=>0, 'set'=>1},  # TelegramBot Peers
       'MediaStream'  => {                       'default'=>'',                          'required'=>0, 'set'=>1},  # Code für MediaStream im TelegramBot (png/jpg = -1)
   );   
   
   my $tac = $extparamref->{tac};
   
   for my $key (keys %teleparams) {
       $data{SSCam}{$name}{PARAMS}{$tac}{$key} = AttrVal($name, $teleparams{$key}->{attr}, $teleparams{$key}->{default}) 
                                                   if(exists $teleparams{$key}->{attr}); 
       if($teleparams{$key}->{set}) {     
           $data{SSCam}{$name}{PARAMS}{$tac}{$key} = $teleparams{$key}->{default} if (!$extparamref->{$key} && !$teleparams{$key}->{attr});    
           $data{SSCam}{$name}{PARAMS}{$tac}{$key} = delete $extparamref->{$key}  if(exists $extparamref->{$key});
       }
 
       Log3($name, 4, "$name - param $key is set to \"".($data{SSCam}{$name}{PARAMS}{$tac}{$key} // "")."\" ") if($key !~ /[sv]dat/x);
       Log3($name, 4, "$name - param $key is set")                                                             if($key =~ /[sv]dat/x && $data{SSCam}{$name}{PARAMS}{$tac}{$key} ne '');
   }
   
   $data{SSCam}{$name}{PARAMS}{$tac}{name} = $name;
   
   my @err = ();
   for my $key (keys(%teleparams)) {
       push(@err, $key) if ($teleparams{$key}->{required} && !$data{SSCam}{$name}{PARAMS}{$tac}{$key});
   }
   if ($#err >= 0) {
       $ret = "Missing at least one required parameter or attribute: ".join(', ',@err);
       Log3($name, 2, "$name - $ret");
       readingsBeginUpdate($hash);
       readingsBulkUpdate($hash,"sendTeleState",$ret);
       readingsEndUpdate($hash, 1);
       $data{SSCam}{$name}{SENDCOUNT}{$tac} -= 1;
       return $ret;
   }
   
   my $telebot = $data{SSCam}{$name}{PARAMS}{$tac}{telebot};
   my $peers   = $data{SSCam}{$name}{PARAMS}{$tac}{peers}; 
   
   if(!$defs{$telebot}) {
       $ret = "No TelegramBot device \"$telebot\" available";
       readingsSingleUpdate($hash, "sendTeleState", $ret, 1);
       Log3($name, 2, "$name - $ret");
       $data{SSCam}{$name}{SENDCOUNT}{$tac} -= 1;
       return;
   }
  
   if(!$peers) {
       $peers = AttrVal($telebot,"defaultPeer", "");
       if(!$peers) {
           $ret = "No peers of TelegramBot device \"$telebot\" found";
           readingsSingleUpdate($hash, "sendTeleState", $ret, 1);
           Log3($name, 2, "$name - $ret");
           $data{SSCam}{$name}{SENDCOUNT}{$tac} -= 1;
           return;       
       }
   }

   if(!$data{SSCam}{$name}{PARAMS}{$tac}{sdat} && !$data{SSCam}{$name}{PARAMS}{$tac}{vdat}) {
       $ret = "no video or image data existing for send process by TelegramBot \"$telebot\" ";
       readingsSingleUpdate($hash, "sendTeleState", $ret, 1);
       Log3($name, 2, "$name - $ret");
       $data{SSCam}{$name}{SENDCOUNT}{$tac} -= 1;
       return;   
   } 
                                    
  my ($msg,$subject,$MediaStream,$fname,@as,%seen,@unique);
  
  $cache = cache($name, "c_init");                                                           # Cache initialisieren        
  Log3($name, 1, "$name - Fall back to internal Cache due to preceding failure.") if(!$cache);
  
  if(!$cache || $cache eq "internal" ) {
      if($data{SSCam}{$name}{PARAMS}{$tac}{sdat}) {                                          # Images liegen in einem Hash (Ref in $sdat) base64-codiert vor
          @as = sort{$b<=>$a}keys%{$data{SSCam}{$name}{PARAMS}{$tac}{sdat}};
      } elsif($data{SSCam}{$name}{PARAMS}{$tac}{vdat}) {                                     # Aufnahmen liegen in einem Hash-Ref in $vdat vor
          @as = sort{$b<=>$a}keys%{$data{SSCam}{$name}{PARAMS}{$tac}{vdat}};
      }
      for my $key (@as) {
           ($msg,$subject,$MediaStream,$fname) = __extractForTelegram($name,$key,$data{SSCam}{$name}{PARAMS}{$tac});
           $ret = __TBotSendIt($defs{$telebot}, $name, $fname, $peers, $msg, $subject, $MediaStream, undef, "");
           if($ret) {
               readingsSingleUpdate($hash, "sendTeleState", $ret, 1);
               Log3($name, 2, "$name - ERROR: $ret");
           } 
           else {
               $ret = "Telegram message [$key] of transaction \"$tac\" sent to \"$peers\" by \"$telebot\" ";
               readingsSingleUpdate($hash, "sendTeleState", $ret, 1);
               Log3($name, 3, "$name - $ret");
           }
      }
      $data{SSCam}{$name}{SENDCOUNT}{$tac} -= 1;
      Log3($name, 1, "$name - Send Counter transaction \"$tac\": ".$data{SSCam}{$name}{SENDCOUNT}{$tac}) if(AttrVal($name,"debugactivetoken",0));
      
  } 
  else {
      # alle Serial Numbers "{$sn}" der Transaktion ermitteln 
      if($data{SSCam}{$name}{PARAMS}{$tac}{sdat}) {                                          # Images liegen in einem Hash (Ref in $sdat) base64-codiert vor
          extractTIDfromCache ( { name  => $name, 
                                  tac   => $tac, 
                                  media => "SENDSNAPS",
                                  mode  => "serial",
                                  aref  => \@as
                                } 
                              );
      
      } elsif($data{SSCam}{$name}{PARAMS}{$tac}{vdat}) {                                     # Aufnahmen liegen in einem Hash-Ref in $vdat vor
          extractTIDfromCache ( { name  => $name, 
                                  tac   => $tac, 
                                  media => "SENDRECS",
                                  mode  => "serial",
                                  aref  => \@as
                                } 
                              );         
      }
      
      @unique = sort{$b<=>$a} grep { !$seen{$_}++ } @as;                                 # distinct / unique the keys
      
      for my $key (@unique) {
           ($msg,$subject,$MediaStream,$fname) = __extractForTelegram($name,$key,$data{SSCam}{$name}{PARAMS}{$tac});
           $ret = __TBotSendIt($defs{$telebot}, $name, $fname, $peers, $msg, $subject, $MediaStream, undef, "");
           if($ret) {
               readingsSingleUpdate($hash, "sendTeleState", $ret, 1);
               Log3($name, 2, "$name - ERROR: $ret");
           } 
           else {
               $ret = "Telegram message [$key] of transaction \"$tac\" sent to \"$peers\" by \"$telebot\" ";
               readingsSingleUpdate($hash, "sendTeleState", $ret, 1);
               Log3($name, 3, "$name - $ret");
           }
      }      
      $data{SSCam}{$name}{SENDCOUNT}{$tac} -= 1;
      Log3($name, 1, "$name - Send Counter transaction \"$tac\": ".$data{SSCam}{$name}{SENDCOUNT}{$tac}) if(AttrVal($name,"debugactivetoken",0));
  }
  
  undef %teleparams;
  undef %{$extparamref};
  undef $msg;
  
return;
}

####################################################################################################
#                                Bilddaten extrahieren für Telegram Versand
####################################################################################################
sub __extractForTelegram {
  my ($name,$key,$paref) = @_;
  my $hash               = $defs{$name};
  my $subject            = $paref->{subject};
  my $MediaStream        = $paref->{MediaStream};
  my $sdat               = $paref->{sdat};                           # Hash von Imagedaten base64 codiert
  my $vdat               = $paref->{vdat};                           # Hashref der Videodaten   
  my ($data,$fname,$ct,$img,$cache);
  
  if($sdat) {
      $cache = cache($name, "c_init");              # Cache initialisieren        
      if(!$cache || $cache eq "internal" ) {
          $ct     = $paref->{sdat}{$key}{createdTm};
          $img    = $paref->{sdat}{$key}{imageData};
          $fname  = trim ($paref->{sdat}{$key}{fileName});
          $data   = MIME::Base64::decode_base64($img); 
          Log3($name, 4, "$name - Image data sequence [$key] decoded from internal Cache for TelegramBot prepare");
          undef $img;
          
      } 
      else {
          $ct    = cache($name, "c_read", "$sdat"."{$key}{createdTm}");
          $img   = cache($name, "c_read", "$sdat"."{$key}{imageData}");
          $fname = trim( cache($name, "c_read", "$sdat"."{$key}{fileName}") );
          $data  = MIME::Base64::decode_base64($img); 
          Log3($name, 4, "$name - Image data sequence [$key] decoded from CHI-Cache for TelegramBot prepare");          
      }
  } 
  
  if($vdat) {
      $cache = cache($name, "c_init");              # Cache initialisieren        
      if(!$cache || $cache eq "internal" ) {
          $ct    = $paref->{vdat}{$key}{createdTm};
          $data  = $paref->{vdat}{$key}{imageData};
          $fname = trim ($paref->{vdat}{$key}{fileName});
          Log3($name, 4, "$name - Video data sequence [$key] got from internal Cache for TelegramBot prepare");
      } 
      else {
          $ct    = cache($name, "c_read", "$vdat"."{$key}{createdTm}");  
          $data  = cache($name, "c_read", "$vdat"."{$key}{imageData}");
          $fname = trim( cache($name, "c_read", "$vdat"."{$key}{fileName}") );      
          Log3($name, 4, "$name - Video data sequence [$key] got from CHI-Cache for TelegramBot prepare");          
      }
  }
  
  $subject =~ s/\$FILE/$fname/gx;
  $subject =~ s/\$CTIME/$ct/gx;
 
return ($data,$subject,$MediaStream,$fname);
}

####################################################################################################
#                  Telegram Send Foto & Aufnahmen
#                  Adaption der Sub "SendIt" aus TelegramBot
#                  $hash    = Hash des verwendeten TelegramBot-Devices !
#                  $isMedia = -1 wenn Foto, -30 wenn Aufnahme
####################################################################################################
sub __TBotSendIt {
  my ($hash, $camname, $fname, @args) = @_;
  my ($peers, $msg, $addPar, $isMedia, $replyid, $options, $retryCount) = @args;
  my $name = $hash->{NAME};
  my $TBotHeader      = "agent: TelegramBot/1.0\r\nUser-Agent: TelegramBot/1.0\r\nAccept: application/json\r\nAccept-Charset: utf-8";
  my $TBotArgRetrycnt = 6;
  
  $retryCount = 0 if (!defined($retryCount));
  $options    = "" if (!defined($options));
  
  # increase retrycount for next try
  $args[$TBotArgRetrycnt] = $retryCount+1;
  
  Log3($camname, 5, "$camname - __TBotSendIt: called ");

  # ignore all sends if disabled
  return if (AttrVal($name,"disable",0));

  # ensure sentQueue exists
  $hash->{sentQueue} = [] if (!defined($hash->{sentQueue}));

  if ((defined( $hash->{sentMsgResult})) && ($hash->{sentMsgResult} =~ /^WAITING/x) && ($retryCount == 0) ){
      # add to queue
      Log3($camname, 4, "$camname - __TBotSendIt: add send to queue :$peers: -:".
          TelegramBot_MsgForLog($msg, ($isMedia<0)).": - :".(defined($addPar)?$addPar:"<undef>").":");
      push(@{$hash->{sentQueue}}, \@args);
      return;
  }  
    
  my $ret;
  $hash->{sentMsgResult}  = "WAITING";
  $hash->{sentMsgResult} .= " retry $retryCount" if ($retryCount>0);
  $hash->{sentMsgId}      = "";

  my $peer;
  ($peer,$peers) = split(" ", $peers, 2); 
  
  # handle addtl peers specified (will be queued since WAITING is set already) 
  if (defined( $peers )) {
      # remove msgid from options and also replyid reset
      my $sepoptions = $options;
      $sepoptions    =~ s/-msgid-//x;
      __TBotSendIt($hash,$camname,$fname,$peers,$msg,$addPar,$isMedia,undef,$sepoptions);
  }
  
  Log3($camname, 5, "$camname - __TBotSendIt: try to send message to :$peer: -:".
      TelegramBot_MsgForLog($msg, ($isMedia<0) ).": - add :".(defined($addPar)?$addPar:"<undef>").
      ": - replyid :".(defined($replyid)?$replyid:"<undef>").
      ":".":    options :".$options.":");

  # trim and convert spaces in peer to underline 
  $peer = 0 if ( ! $peer );
  my $peer2 = (!$peer)?$peer:TelegramBot_GetIdForPeer($hash, $peer);

  if (!defined($peer2)) {
      $ret = "FAILED peer not found :$peer:";
      $peer2 = "";
  }
  
  $hash->{sentMsgPeer}    = TelegramBot_GetFullnameForContact($hash,$peer2);
  $hash->{sentMsgPeerId}  = $peer2;
  $hash->{sentMsgOptions} = $options;
  
  # init param hash
  $hash->{HU_DO_PARAMS}->{hash}   = $hash;
  $hash->{HU_DO_PARAMS}->{header} = $TBotHeader;
  delete $hash->{HU_DO_PARAMS}{args};
  delete $hash->{HU_DO_PARAMS}{boundary};
  delete $hash->{HU_DO_PARAMS}{data};

  my $timeout = AttrVal($name,'cmdTimeout',30);
  $hash->{HU_DO_PARAMS}->{timeout}  = $timeout;
  $hash->{HU_DO_PARAMS}->{loglevel} = 4;
  
  # Start Versand
  if (!defined($ret)) {
      # add chat / user id (no file) --> this will also do init
      $ret = __TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "chat_id", undef, $peer2, 0 ) if ( $peer );
      
      if (abs($isMedia) == 1) {
          # Foto send    
          $hash->{sentMsgText}         = "Image: ".TelegramBot_MsgForLog($msg,($isMedia<0)).((defined($addPar))?" - ".$addPar:"");
          $hash->{HU_DO_PARAMS}->{url} = TelegramBot_getBaseURL($hash)."sendPhoto";

          # add caption
          if (defined($addPar)) {
              $addPar =~ s/(?<![\\])\\n/\x0A/gx;
              $addPar =~ s/(?<![\\])\\t/\x09/gx;

              $ret = __TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "caption", undef, $addPar, 0 ) if (!defined($ret));
              $addPar = undef;
          }
      
          # add msg or file or stream
          Log3($camname, 4, "$camname - __TBotSendIt: Filename for image file :".
            TelegramBot_MsgForLog($msg, ($isMedia<0) ).":");
          $ret = __TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "photo", undef, $msg, $isMedia) if(!defined($ret));
      
      } 
      elsif ( abs($isMedia) == 30 ) {
          # Video send    
          $hash->{sentMsgText}         = "Image: ".TelegramBot_MsgForLog($msg,($isMedia<0)).((defined($addPar))?" - ".$addPar:"");
          $hash->{HU_DO_PARAMS}->{url} = TelegramBot_getBaseURL($hash)."sendVideo";

          # add caption
          if (defined( $addPar) ) {
              $addPar =~ s/(?<![\\])\\n/\x0A/gx;
              $addPar =~ s/(?<![\\])\\t/\x09/gx;

              $ret = __TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "caption", undef, $addPar, 0) if(!defined($ret));
              $addPar = undef;
          }
      
          # add msg or file or stream
          Log3($camname, 4, "$camname - __TBotSendIt: Filename for image file :".$fname.":");
          $ret = __TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "video", undef, $msg, $isMedia) if(!defined($ret));
      
      } 
      else {
          # nur Message senden
          $msg = "No media File was created by SSCam. Can't send it.";
          $hash->{HU_DO_PARAMS}->{url} = TelegramBot_getBaseURL($hash)."sendMessage";
      
          my $parseMode = TelegramBot_AttrNum($name,"parseModeSend","0" );
        
          if ($parseMode == 1) {
              $parseMode = "Markdown";
          } 
          elsif ($parseMode == 2) {
              $parseMode = "HTML";
          } 
          elsif ($parseMode == 3) {
              $parseMode = 0;
              if ($msg =~ /^markdown(.*)$/ix) {
                  $msg = $1;
                  $parseMode = "Markdown";
              } elsif ($msg =~ /^HTML(.*)$/ix) {
                  $msg = $1;
                  $parseMode = "HTML";
              }
          } 
          else {
              $parseMode = 0;
          }
      
          Log3($camname, 4, "$camname - __TBotSendIt: parseMode $parseMode");
    
          if (length($msg) > 1000) {
              $hash->{sentMsgText} = substr($msg, 0, 1000)."...";
          } 
          else {
              $hash->{sentMsgText} = $msg;
          }
        
          $msg =~ s/(?<![\\])\\n/\x0A/gx;
          $msg =~ s/(?<![\\])\\t/\x09/gx;

          # add msg (no file)
          $ret = __TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "text", undef, $msg, 0) if(!defined($ret));

          # add parseMode
          $ret = __TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "parse_mode", undef, $parseMode, 0) if((!defined($ret)) && ($parseMode));

          # add disable_web_page_preview       
          $ret = __TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "disable_web_page_preview", undef, \1, 0) 
            if ((!defined($ret))&&(!AttrVal($name,'webPagePreview',1)));            
      }

      if (defined($replyid)) {
          $ret = __TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "reply_to_message_id", undef, $replyid, 0) if(!defined($ret));
      }

      if (defined($addPar)) {
          $ret = __TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "reply_markup", undef, $addPar, 0) if(!defined($ret));
      } elsif ($options =~ /-force_reply-/x) {
          $ret = __TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "reply_markup", undef, "{\"force_reply\":true}", 0 ) if(!defined($ret));
      }

      if ($options =~ /-silent-/x) {
          $ret = __TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "disable_notification", undef, "true", 0) if(!defined($ret));
      }

      # finalize multipart 
      $ret = __TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, undef, undef, undef, 0) if(!defined($ret));

  }
  
  if (defined($ret)) {
      Log3($camname, 3, "$camname - __TBotSendIt: Failed with :$ret:");
      TelegramBot_Callback($hash->{HU_DO_PARAMS}, $ret, "");
  } 
  else {
      $hash->{HU_DO_PARAMS}->{args} = \@args;
    
      # if utf8 is set on string this will lead to length wrongly calculated in HTTPUtils (char instead of bytes) for some installations
      if ((AttrVal($name,'utf8Special',0)) && (utf8::is_utf8($hash->{HU_DO_PARAMS}->{data}))) {
          Log3 $camname, 4, "$camname - __TBotSendIt: utf8 encoding for data in message ";
          utf8::downgrade($hash->{HU_DO_PARAMS}->{data}); 
      }
    
      Log3($camname, 4, "$camname - __TBotSendIt: timeout for sent :".$hash->{HU_DO_PARAMS}->{timeout}.": ");
      HttpUtils_NonblockingGet($hash->{HU_DO_PARAMS});
  }
  
  undef $msg;
  
return $ret;
}

####################################################################################################
#                  Telegram Media zusammenstellen
#                  Adaption der Sub "AddMultipart" aus TelegramBot
#                  
#   Parameter:
#   $hash    = Hash des verwendeten TelegramBot-Devices !
#   params   = (hash for building up the data)
#   paramname --> if not sepecifed / undef - multipart will be finished
#   header for multipart
#   content 
#   isFile to specify if content is providing a file to be read as content
#     
#   returns string in case of error or undef
####################################################################################################
sub __TBotAddMultipart {
  my ($hash, $fname, $params, $parname, $parheader, $parcontent, $isMedia ) = @_;
  my $name = $hash->{NAME};

  my $ret;
  
  # Check if boundary is defined
  if ( ! defined( $params->{boundary} ) ) {
      $params->{boundary} = "TelegramBot_boundary-x0123";
      $params->{header}  .= "\r\nContent-Type: multipart/form-data; boundary=".$params->{boundary};
      $params->{method}   = "POST";
      $params->{data}     = "";
  }
  
  # ensure parheader is defined and add final header new lines
  $parheader  = "" if (!defined($parheader));
  $parheader .= "\r\n" if ((length($parheader) > 0) && ($parheader !~ /\r\n$/x));

  # add content 
  my $finalcontent;
  if (defined($parname)) {
      $params->{data} .= "--".$params->{boundary}."\r\n";
      if ($isMedia > 0) {
          # url decode filename
          $parcontent = uri_unescape($parcontent) if(AttrVal($name,'filenameUrlEscape',0));

          my $baseFilename = basename($parcontent);
          $parheader = "Content-Disposition: form-data; name=\"".$parname."\"; filename=\"".$baseFilename."\"\r\n".$parheader."\r\n";

          return("FAILED file :$parcontent: not found or empty" ) if(! -e $parcontent) ;
          
          my $size = -s $parcontent;
          my $limit = AttrVal($name,'maxFileSize',10485760);
          return("FAILED file :$parcontent: is too large for transfer (current limit: ".$limit."B)") if($size > $limit) ;
          
          $finalcontent = TelegramBot_BinaryFileRead($hash, $parcontent);
          if ($finalcontent eq "") {
            return("FAILED file :$parcontent: not found or empty");
          }
      
      } elsif ($isMedia < 0) {
          my ($im, $ext)   = __TBotIdentifyStream($hash, $parcontent);
          $fname           =~ s/.mp4$/.$ext/x;
          $parheader       = "Content-Disposition: form-data; name=\"".$parname."\"; filename=\"".$fname."\"\r\n".$parheader."\r\n";
          $finalcontent    = $parcontent;
      } 
      else {
          $parheader    = "Content-Disposition: form-data; name=\"".$parname."\"\r\n".$parheader."\r\n";
          $finalcontent = $parcontent;
      }
    
      $params->{data} .= $parheader.$finalcontent."\r\n";
  } 
  else {
      return( "No content defined for multipart" ) if ( length( $params->{data} ) == 0 );
      $params->{data} .= "--".$params->{boundary}."--";     
  }

return;
}

####################################################################################################
#                  Telegram Media Identifikation
#                  Adaption der Sub "IdentifyStream" aus TelegramBot
#                  $hash    = Hash des verwendeten TelegramBot-Devices !
####################################################################################################
sub __TBotIdentifyStream {
  my ($hash, $msg) = @_;

  # signatures for media files are documented here --> https://en.wikipedia.org/wiki/List_of_file_signatures
  # seems sometimes more correct: https://wangrui.wordpress.com/2007/06/19/file-signatures-table/
  # Video Signatur aus: https://www.garykessler.net/library/file_sigs.html
  return (-1,"png")  if ( $msg =~ /^\x89PNG\r\n\x1a\n/x );                       # PNG
  return (-1,"jpg")  if ( $msg =~ /^\xFF\xD8\xFF/x );                            # JPG not necessarily complete, but should be fine here
  return (-30,"mpg") if ( $msg =~ /^....\x66\x74\x79\x70\x69\x73\x6f\x6d/x );    # mp4     

return (0,undef);
}

###############################################################################
#                 Vorbereitung Versand Mail Nachrichten
###############################################################################
sub _prepSendMail { 
   my $paref  = shift;
   my $hash   = $paref->{hash};
   my $calias = $paref->{calias};
   my $mt     = $paref->{mt};
   my $date   = $paref->{date};
   my $time   = $paref->{time};
   my $name   = $hash->{NAME}; 
   
   $mt =~ s/['"]//gx;   
   
   my($subj,$body) =  split(",", $mt, 2);
   my $subjt       = (split("=>", $subj))[1];
   my $bodyt       = (split("=>", $body))[1];
   
   $subjt = trim($subjt);
   $subjt =~ s/\$CAM/$calias/gx;
   $subjt =~ s/\$DATE/$date/gx;
   $subjt =~ s/\$TIME/$time/gx;
   
   $bodyt = trim($bodyt);
   $bodyt =~ s/\$CAM/$calias/gx;
   $bodyt =~ s/\$DATE/$date/gx;
   $bodyt =~ s/\$TIME/$time/gx;
   
   my %smtpmsg       = ();
   $smtpmsg{subject} = "$subjt";
   $smtpmsg{body}    = "$bodyt";
   
return \%smtpmsg;
}

#############################################################################################
#                                   SMTP EMail-Versand
#############################################################################################
sub _sendEmail { 
   my ($hash, $extparamref) = @_;
   my $name = $hash->{NAME};
   my $timeout = 60;
   my $ret;
   
   Log3($name, 4, "$name - ####################################################"); 
   Log3($name, 4, "$name - ###   start send snapshot or recording by email     "); 
   Log3($name, 4, "$name - ####################################################");
   
   my $m1 = "Net::SMTP"; 
   my $m2 = "MIME::Lite"; 
   my $m3 = "Net::SMTP::SSL";
   my $sslfb = 0;                                       # Flag für Verwendung altes Net::SMTP::SSL
   
   my ($vm1,$vm2,$vm3);
   eval { require Net::SMTP;                            ## no critic 'eval not tested'    
          Net::SMTP->import; 
          $vm1 = $Net::SMTP::VERSION;
          
          # Version von Net::SMTP prüfen, wenn < 3.00 dann Net::SMTP::SSL verwenden 
          # (libnet-3.06 hat SSL inkludiert)
          my $sv = $vm1;
          $sv =~ s/[^0-9.].*$//x;
          if($sv < 3.00) {
             require Net::SMTP::SSL;
             Net::SMTP::SSL->import;
             $vm3 = $Net::SMTP::SSL::VERSION;
             $sslfb = 1;
          }
          
          require MIME::Lite; 
          MIME::Lite->import; 
          $vm2 = $MIME::Lite::VERSION;
   };
   
   if(!$vm1 || !$vm2 || ($sslfb && !$vm3)) {
       my $nl = !$vm2?$m2." ":"";
       $nl   .= !$vm1?$m1." ":"";
       $nl   .= ($sslfb && !$vm3)?$m3:"";
       $ret = "required module for sending Email couldn't be loaded. You have to install: $nl";
       Log3($name, 1, "$name - $ret");
       
       readingsBeginUpdate($hash);
       readingsBulkUpdate ($hash,"sendEmailState",$ret);
       readingsEndUpdate  ($hash, 1);
                
       return $ret;
   }
   
   Log3($name, 4, "$name - version of loaded module \"$m1\" is \"$vm1\"");
   Log3($name, 4, "$name - version of \"$m1\" is too old. Use SSL-fallback module \"$m3\" with version \"$vm3\"") if($sslfb && $vm3);
   Log3($name, 4, "$name - version of loaded module \"$m2\" is \"$vm2\"");
   
   my %mailparams = (
       'smtpFrom'     => {'attr'=>'smtpFrom',    'default'=>'',                          'required'=>1, 'set'=>1},
       'smtpTo'       => {'attr'=>'smtpTo',      'default'=>'',                          'required'=>1, 'set'=>1},
       'subject'      => {'attr'=>'subject',     'default'=>'',                          'required'=>1, 'set'=>1},
       'smtpCc'       => {'attr'=>'smtpCc',      'default'=>'',                          'required'=>0, 'set'=>1},
       'part1type'    => {                       'default'=>'text/plain; charset=UTF-8', 'required'=>1, 'set'=>1},
       'part1txt'     => {                       'default'=>'',                          'required'=>0, 'set'=>1},
       'part2type'    => {                       'default'=>'',                          'required'=>0, 'set'=>1},
       'smtphost'     => {'attr'=>'smtpHost',    'default'=>'',                          'required'=>1, 'set'=>0},
       'smtpport'     => {'attr'=>'smtpPort',    'default'=>'25',                        'required'=>1, 'set'=>0},
       'smtpsslport'  => {'attr'=>'smtpSSLPort', 'default'=>'',                          'required'=>0, 'set'=>1},  # SSL-Port, verwendet bei direktem SSL-Aufbau
       'smtpnousessl' => {'attr'=>'smtpNoUseSSL','default'=>'0',                         'required'=>0, 'set'=>1},
       'smtpdebug'    => {'attr'=>'smtpDebug',   'default'=>'0',                         'required'=>0, 'set'=>0},
       'sdat'         => {                       'default'=>'',                          'required'=>0, 'set'=>1},  # Hashref der Bilddaten (Bilddaten base64 codiert), wenn gesetzt muss 'part2type' auf 'image/jpeg' gesetzt sein
       'image'        => {                       'default'=>'',                          'required'=>0, 'set'=>1},  # Daten als File, wenn gesetzt muss 'part2type' auf 'image/jpeg' gesetzt sein
       'fname'        => {                       'default'=>'image.jpg',                 'required'=>0, 'set'=>1},  # Filename für "image"
       'lsnaptime'    => {                       'default'=>'',                          'required'=>0, 'set'=>1},  # Zeitstempel der Bilddaten
       'opmode'       => {                       'default'=>'',                          'required'=>1, 'set'=>1},  # OpMode muss gesetzt sein
       'sslfb'        => {                       'default'=>$sslfb,                      'required'=>0, 'set'=>1},  # Flag für Verwendung altes Net::SMTP::SSL   
       'sslfrominit'  => {                       'default'=>'',                          'required'=>0, 'set'=>1},  # SSL soll sofort ! aufgebaut werden  
       'tac'          => {                       'default'=>'',                          'required'=>0, 'set'=>1},  # übermittelter Transaktionscode der ausgewerteten Transaktion
       'vdat'         => {                       'default'=>'',                          'required'=>0, 'set'=>1},  # Videodaten, wenn gesetzt muss 'part2type' auf 'video/mpeg' gesetzt sein
   );   
   
   my $tac = $extparamref->{tac};
   
   for my $key (keys %mailparams) {
       $data{SSCam}{$name}{PARAMS}{$tac}{$key} = AttrVal($name, $mailparams{$key}->{attr}, $mailparams{$key}->{default}) 
                                                   if(exists $mailparams{$key}->{attr}); 
       if($mailparams{$key}->{set}) { 
           $data{SSCam}{$name}{PARAMS}{$tac}{$key} = $mailparams{$key}->{default} if (!$extparamref->{$key} && !$mailparams{$key}->{attr});    
           $data{SSCam}{$name}{PARAMS}{$tac}{$key} = delete $extparamref->{$key} if (exists $extparamref->{$key});
       }
       Log3($name, 4, "$name - param $key is now \"".$data{SSCam}{$name}{PARAMS}{$tac}{$key}."\" ") if($key !~ /sdat/x);
       Log3($name, 4, "$name - param $key is set") if($key =~ /sdat/x && $data{SSCam}{$name}{PARAMS}{$tac}{$key} ne '');
   }
   
   $data{SSCam}{$name}{PARAMS}{$tac}{name} = $name;
   
   my @err = ();
   for my $key (keys(%mailparams)) {
       push(@err, $key) if ($mailparams{$key}->{required} && !$data{SSCam}{$name}{PARAMS}{$tac}{$key});
   }
   if ($#err >= 0) {
       $ret = "Missing at least one required parameter or attribute: ".join(', ',@err);
       Log3($name, 2, "$name - $ret");
       
       readingsBeginUpdate($hash);
       readingsBulkUpdate ($hash,"sendEmailState",$ret);
       readingsEndUpdate  ($hash, 1);
       
       return $ret;
   }
   
   $hash->{HELPER}{RUNNING_PID}           = BlockingCall("FHEM::SSCam::__sendEmailblocking", $data{SSCam}{$name}{PARAMS}{$tac}, "FHEM::SSCam::__sendEmaildone", $timeout, "FHEM::SSCam::__sendEmailto", $hash);
   $hash->{HELPER}{RUNNING_PID}{loglevel} = 5 if($hash->{HELPER}{RUNNING_PID});  # Forum #77057
      
   undef %mailparams;
   undef %$extparamref;
   
return;
}

####################################################################################################
#                                 nichtblockierendes Send EMail
####################################################################################################
sub __sendEmailblocking {                                                    ## no critic 'not used' 
  my ($paref)      = @_;                                        # der Referent wird in cleanData gelöscht
  my $name         = delete $paref->{name};
  my $cc           = delete $paref->{smtpCc};
  my $from         = delete $paref->{smtpFrom};
  my $part1type    = delete $paref->{part1type};
  my $part1txt     = delete $paref->{part1txt};
  my $part2type    = delete $paref->{part2type};
  my $smtphost     = delete $paref->{smtphost};
  my $smtpport     = delete $paref->{smtpport};
  my $smtpsslport  = delete $paref->{smtpsslport};
  my $smtpnousessl = delete $paref->{smtpnousessl};             # SSL Verschlüsselung soll NICHT genutzt werden
  my $subject      = delete $paref->{subject};
  my $to           = delete $paref->{smtpTo};
  my $msgtext      = delete $paref->{msgtext}; 
  my $smtpdebug    = delete $paref->{smtpdebug}; 
  my $sdat         = delete $paref->{sdat};                     # Hash von Imagedaten base64 codiert
  my $image        = delete $paref->{image};                    # Image, wenn gesetzt muss 'part2type' auf 'image/jpeg' gesetzt sein
  my $fname        = delete $paref->{fname};                    # Filename -> verwendet wenn $image ist gesetzt
  my $lsnaptime    = delete $paref->{lsnaptime};                # Zeit des letzten Schnappschusses wenn gesetzt
  my $opmode       = delete $paref->{opmode};                   # aktueller Operation Mode
  my $sslfb        = delete $paref->{sslfb};                    # Flag für Verwendung altes Net::SMTP::SSL
  my $sslfrominit  = delete $paref->{sslfrominit};              # SSL soll sofort ! aufgebaut werden
  my $tac          = delete $paref->{tac};                      # übermittelter Transaktionscode der ausgewerteten Transaktion
  my $vdat         = delete $paref->{vdat};                     # Videodaten, wenn gesetzt muss 'part2type' auf 'video/mpeg' gesetzt sein
     
  my $hash   = $defs{$name};
  my $sslver = "";
  my ($err,$smtp,@as,$cache);
  
  # Credentials abrufen
  my ($success, $username, $password) = getCredentials($hash,0,"SMTPcredentials");
  
  unless ($success) {
      $err = "SMTP credentials couldn't be retrieved successfully - make sure you've set it with \"set $name smtpcredentials <username> <password>\"";
      Log3($name, 2, "$name - $err");
      $err = encode_base64($err,"");
      return "$name|$err|''";
  } 
 
  $subject = decode_utf8($subject);
  my $mailmsg = MIME::Lite->new(
      From    => $from,
      To      => $to,
      Subject => $subject,
      Type    => 'multipart/mixed',    #'multipart/mixed', # was 'text/plain'
  );
  
  ### Add the text message part:
  ### (Note that "attach" has same arguments as "new"):
  $part1txt = decode_utf8($part1txt);
  $mailmsg->attach(
      Type => $part1type,
      Data => $part1txt,
  );
 
  ### Add image, Das Image liegt bereits als File vor
  if($image) {
      $mailmsg->attach(
          Type        => $part2type,
          Path        => $image,
          Filename    => $fname,
          Disposition => 'attachment',
      );
  }
  
  if($sdat) {
      ### Images liegen in einem Hash (Ref in $sdat) base64-codiert vor
      my ($ct,$img,$decoded);
      $cache = cache($name, "c_init");              # Cache initialisieren        
      if(!$cache || $cache eq "internal" ) {
          @as = sort{$a<=>$b}keys%{$sdat};
          for my $key (@as) {
              $ct      = delete $sdat->{$key}{createdTm};
              $img     = delete $sdat->{$key}{imageData};
              $fname   = delete $sdat->{$key}{fileName};
              $decoded = MIME::Base64::decode_base64($img); 
              $mailmsg->attach(
                  Type        => $part2type,
                  Data        => $decoded,
                  Filename    => $fname,
                  Disposition => 'attachment',
              );
              Log3($name, 4, "$name - Image data sequence [$key] decoded from internal Cache for Email attachment") if($decoded); 
          }
          BlockingInformParent("FHEM::SSCam::subaddFromBlocking", [$name, "-", $tac], 0); 
      } 
      else {
          # alle Serial Numbers "{$sn}" der Transaktion ermitteln          
          extractTIDfromCache ( { name  => $name, 
                                  tac   => $tac, 
                                  media => "SENDSNAPS|RS",
                                  mode  => "serial",
                                  aref  => \@as
                                } 
                              );  
          my %seen;
          my @unique = sort{$a<=>$b} grep { !$seen{$_}++ } @as;                                 # distinct / unique the keys

          for my $key (@unique) {                                                               # attach mail
              next if(!cache($name, "c_isvalidkey", "$sdat"."{$key}{imageData}")); 
              $ct      = cache($name, "c_read", "$sdat"."{$key}{createdTm}");
              $img     = cache($name, "c_read", "$sdat"."{$key}{imageData}");
              $fname   = cache($name, "c_read", "$sdat"."{$key}{fileName}");
              $decoded = MIME::Base64::decode_base64($img); 
              $mailmsg->attach(
                  Type        => $part2type,
                  Data        => $decoded,
                  Filename    => $fname,
                  Disposition => 'attachment',
              );
              Log3($name, 4, "$name - Image data sequence [$key] decoded from CHI-Cache for Email attachment"); 
          }
          BlockingInformParent("FHEM::SSCam::subaddFromBlocking", [$name, "-", $tac], 0);
      }
  }
  
  if($vdat) {                                                      # Videodaten (mp4) wurden geliefert
      my ($ct,$video);
      $cache = cache($name, "c_init");                             # Cache initialisieren        
      if(!$cache || $cache eq "internal" ) {
          @as = sort{$a<=>$b}keys%{$vdat};
          for my $key (@as) {
              $ct      = delete $vdat->{$key}{createdTm};
              $video   = delete $vdat->{$key}{imageData};
              $fname   = delete $vdat->{$key}{fileName};
              $mailmsg->attach(
                  Type        => $part2type,
                  Data        => $video,
                  Filename    => $fname,
                  Disposition => 'attachment',
              );
              Log3($name, 4, "$name - Video data sequence [$key] decoded from internal Cache for Email attachment"); 
          } 
          BlockingInformParent("FHEM::SSCam::subaddFromBlocking", [$name, "-", $tac], 0);              
      } 
      else {
          # alle Serial Numbers "{$sn}" der Transaktion ermitteln
          extractTIDfromCache ( { name  => $name, 
                                  tac   => $tac, 
                                  media => "SENDRECS",
                                  mode  => "serial",
                                  aref  => \@as
                                } 
                              );       
          my %seen;          
          my @unique = sort{$a<=>$b} grep { !$seen{$_}++ } @as;                                 # distinct / unique the keys
          
          # attach mail
          for my $key (@unique) {
              next if(!cache($name, "c_isvalidkey", "$vdat"."{$key}{imageData}")); 
              $ct      = cache($name, "c_read", "$vdat"."{$key}{createdTm}");
              $video   = cache($name, "c_read", "$vdat"."{$key}{imageData}");   
              $fname   = cache($name, "c_read", "$vdat"."{$key}{fileName}"); 
              $mailmsg->attach(
                  Type        => $part2type,
                  Data        => $video,
                  Filename    => $fname,
                  Disposition => 'attachment',
              );
              Log3($name, 4, "$name - Video data sequence [$key] decoded from CHI-Cache for Email attachment"); 
          }
          BlockingInformParent("FHEM::SSCam::subaddFromBlocking", [$name, "-", $tac], 0);     
      }
  }
  
  $mailmsg->attr('content-type.charset' => 'UTF-8');

  #####  SMTP-Connection #####
  # login to SMTP Host
  if($sslfb) {
      # Verwendung altes Net::SMTP::SSL <= 3.00 -> immer direkter SSL-Aufbau, Attribut "smtpNoUseSSL" wird ignoriert
      Log3($name, 3, "$name - Attribute \"smtpNoUseSSL\" will be ignored due to usage of Net::SMTP::SSL") if(AttrVal($name,"smtpNoUseSSL",0));
      $smtp = Net::SMTP::SSL->new(Host => $smtphost, Port => $smtpsslport, Debug => $smtpdebug);
  } 
  else {
      # Verwendung neues Net::SMTP::SSL > 3.00
      if($sslfrominit) {                                                        # sofortiger SSL connect
          $smtp = Net::SMTP->new(Host => $smtphost, Port => $smtpsslport, SSL => 1, Debug => $smtpdebug);
      } 
      else {                                                                    # erst unverschlüsselt, danach switch zu encrypted
          $smtp = Net::SMTP->new(Host => $smtphost, Port => $smtpport, SSL => 0, Debug => $smtpdebug);
      }
  }
      
  if(!$smtp) {
      $err = "SMTP Error: Can't connect to host $smtphost";
      Log3($name, 2, "$name - $err");
      $err = encode_base64($err,"");
      return "$name|$err|''";   
  }
      
  if(!$sslfb && !$sslfrominit) {                                               # Aufbau unverschlüsselt -> switch zu verschlüsselt wenn nicht untersagt  
      if($smtp->can_ssl() && !$smtpnousessl) {                      
          unless( $smtp->starttls ( SSL_verify_mode => 0, 
                                    SSL_version => "TLSv1_2:!TLSv1_1:!SSLv3:!SSLv23:!SSLv2", 
                                  ) ) {
              $err = "SMTP Error while switch to SSL: ".$smtp->message();
              Log3($name, 2, "$name - $err");
              $err = encode_base64($err,"");
              return "$name|$err|''";  
          }  
          
          $sslver = $smtp->get_sslversion();
          Log3($name, 3, "$name - SMTP-Host $smtphost switched to encrypted connection with SSL version: $sslver");
      } 
      else {
          Log3($name, 3, "$name - SMTP-Host $smtphost use unencrypted connection !");
      }
  } 
  else {
      eval { $sslver = $smtp->get_sslversion(); };        ## no critic 'eval not tested' # Forum: https://forum.fhem.de/index.php/topic,45671.msg880602.html#msg880602
      $sslver = $sslver ? $sslver : "n.a.";
      Log3($name, 3, "$name - SMTP-Host $smtphost use immediately encrypted connection with SSL version: $sslver");      
  }

  unless( $smtp->auth($username, $password) ) {
      $err = "SMTP Error authentication: ".$smtp->message();
      Log3($name, 2, "$name - $err");
      $err = encode_base64($err,"");
      return "$name|$err|''";  
  }
  
  unless( $smtp->mail($from) ) {
      $err = "SMTP Error setting sender: ".$smtp->message();
      Log3($name, 2, "$name - $err");
      $err = encode_base64($err,"");
      return "$name|$err|''";  
  }
  
  my @r = split(",", $to);
  unless( $smtp->to(@r) ) {
      $err = "SMTP Error setting receiver: ".$smtp->message();
      Log3($name, 2, "$name - $err");
      $err = encode_base64($err,"");
      return "$name|$err|''";  
  }
  
  if ($cc) {
      my @c = split(",", $cc);
      unless( $smtp->cc(@c) ) {
          $err = "SMTP Error setting carbon-copy $cc: ".$smtp->message();
          Log3($name, 2, "$name - $err");
          $err = encode_base64($err,"");
          return "$name|$err|''";  
      }
  }
  
  unless( $smtp->data() ) {
      $err = "SMTP Error setting data: ".$smtp->message();
      Log3($name, 2, "$name - $err");
      $err = encode_base64($err,"");
      return "$name|$err|''";  
  }
  
  unless( $smtp->datasend(encode('utf8',$mailmsg->as_string)) ) {
      $err = "SMTP Error sending email: ".$smtp->message();
      Log3($name, 2, "$name - $err");
      $err = encode_base64($err,"");
      return "$name|$err|''";  
  }
  
  unless( $smtp->dataend() ) {
      $err = "SMTP Error ending transaction: ".$smtp->message();
      Log3($name, 2, "$name - $err");
      $err = encode_base64($err,"");
      return "$name|$err|''";  
  }  
  
  unless( $smtp->quit() ) {
      $err = "SMTP Error saying good-bye: ".$smtp->message();
      Log3($name, 2, "$name - $err");
      $err = encode_base64($err,"");
      return "$name|$err|''";  
  }   
  
  my $ret = "Email transaction \"$tac\" successfully sent ".( $sslver?"encoded by $sslver":""  ); 
  Log3($name, 3, "$name - $ret To: $to".(($cc)?", CC: $cc":"") );
  
  # Daten müssen als Einzeiler zurückgegeben werden
  $ret = encode_base64($ret,"");
 
return "$name|''|$ret";
}

####################################################################################################
#                   Auswertungsroutine nichtblockierendes Send EMail
####################################################################################################
sub __sendEmaildone {                                                        ## no critic 'not used'
  my $string = shift;
  my @a      = split("\\|",$string);
  my $hash   = $defs{$a[0]};
  my $err    = $a[1] ? trim(decode_base64($a[1])) : undef;
  my $ret    = $a[2] ? trim(decode_base64($a[2])) : undef;
  
  if ($err) {
      readingsBeginUpdate($hash);
      readingsBulkUpdate ($hash,"sendEmailState",$err);
      readingsEndUpdate  ($hash, 1);
      
      delete($hash->{HELPER}{RUNNING_PID});
      return;
  } 
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate ($hash,"sendEmailState",$ret);
  readingsEndUpdate  ($hash, 1);
      
  delete($hash->{HELPER}{RUNNING_PID});
                  
return;
}

####################################################################################################
#                               Abbruchroutine Send EMail
####################################################################################################
sub __sendEmailto {                                                          ## no critic 'not used' 
  my ($hash,$cause) = @_;
  my $name = $hash->{NAME}; 
  
  $cause = $cause // "Timeout: process terminated";
  Log3 ($name, 1, "$name -> BlockingCall $hash->{HELPER}{RUNNING_PID}{fn} pid:$hash->{HELPER}{RUNNING_PID}{pid} $cause");    
  
  readingsBeginUpdate         ($hash);
  readingsBulkUpdateIfChanged ($hash,"sendEmailState",$cause);
  readingsEndUpdate           ($hash, 1);
  
  delete($hash->{HELPER}{RUNNING_PID});

return;
}

#################################################################################################
# Modi:
# 1. serial   - extrahiere Serial Nummer (der Medien) aus Cache für Versand 
#    Schnappschüsse / Ausfnahmen + optionalen Vergleich mit laufender Transaktion
# 2. readkeys - liest alle Schlüssel aus gegebenen Cache aus
#
# Muster Schnappschüsse: {SENDSNAPS}{2222}{0}{imageData}
# Muster Aufnahmen:      {SENDRECS}{305}{0}{imageData}
# Muster multiple:       {SENDSNAPS|RS}{2222|multiple_snapsend}{0|1572995404.125580}{imageData} 
#################################################################################################
sub extractTIDfromCache { 
  my $params = shift;
  my $name   = $params->{name};
  my $tac    = $params->{tac};
  my $media  = $params->{media};
  my $mode   = $params->{mode};
  my $aref   = $params->{aref};
  
  if($mode eq "serial") {                                                                # Serial Nummern auslesen
      for my $ck (cache($name, "c_getkeys")) {                                           
          next if $ck !~ /\{$media\}\{.*?\}\{.*?\}\{.*?\}/x;
          my ($k1,$k2,$k3) = $ck =~ /\{($media)\}\{(.*?)\}\{(.*?)\}\{.*?\}/x;
          if($tac) {
              next if "$k2" ne "$tac";
          }
          push @$aref,$k3 if($k3 =~ /^(\d+|\d+.\d+)$/x);                                 # Serial Nummer in übergebenes Array eintragen 
      }
  }
  
  if($mode eq "readkeys") {                                                              # liest alle Schlüssel aus gegebenen Cache aus                                      
      for my $ck (cache($name, "c_getkeys")) {             
          next if $ck !~ /\{$media\}\{\d+?\}\{.*?\}/x;
          my ($k1) = $ck =~ /\{$media\}\{(\d+?)\}\{.*?\}/x;
          push @$aref,$k1 if($k1 =~ /^\d+$/x);
    }
  }
          
return;
}

#############################################################################################
#              Transaktion starten oder vorhandenen TA Code zurück liefern
#############################################################################################
sub openOrgetTrans { 
   my $hash = shift;
   my $name = $hash->{NAME};
   my $tac  = ""; 
   
   if(!$hash->{HELPER}{TRANSACTION}) {                
       $tac = int(rand(4500));                      # Transaktionscode erzeugen und speichern
       $hash->{HELPER}{TRANSACTION} = $tac;
       if (AttrVal($name,"debugactivetoken",0)) {
           Log3($name, 1, "$name - Transaction opened, TA-code: $tac");
       }    
   } 
   else {
       $tac = $hash->{HELPER}{TRANSACTION};         # vorhandenen Transaktionscode zurück liefern
   }
   
return $tac;
}

#############################################################################################
#                                 Transaktion freigeben
#############################################################################################
sub closeTrans { 
   my $hash = shift;
   my $name = $hash->{NAME};
   
   my $tac = delete $hash->{HELPER}{TRANSACTION};            # diese Transaktion beenden
   $tac    = $tac // q{};
   
   return if(!$tac); 
   cleanData("$name:$tac");                                  # %data Hash & Cache bereinigen
      
   Log3($name, 1, "$name - Transaction \"$tac\" closed") if(AttrVal($name,"debugactivetoken",0));
   
return;
}

####################################################################################################
#                               $data Hash bereinigen
####################################################################################################
sub cleanData {
  my ($str)            = @_;
  my ($name,$tac) = split(":",$str);
  my $hash   = $defs{$name};
  my $del    = 0;
  
  RemoveInternalTimer($hash, "FHEM::SSCam::cleanData"); 
  
  if($data{SSCam}{$name}{SENDCOUNT}{$tac} && $data{SSCam}{$name}{SENDCOUNT}{$tac} > 0) {     # Cacheinhalt erst löschen wenn Sendezähler 0
      InternalTimer(gettimeofday()+1, "FHEM::SSCam::cleanData", "$name:$tac", 0);
      return;
  } 
  
  if(AttrVal($name, "cacheType", "internal") eq "internal") {                                # internes Caching
      if($tac) {
          if($data{SSCam}{RS}{$tac}) {
              delete $data{SSCam}{RS}{$tac};
              $del = 1;
          }
          if($data{SSCam}{$name}{SENDRECS}{$tac}) {
              delete $data{SSCam}{$name}{SENDRECS}{$tac};
              $del = 1;
          }
          if($data{SSCam}{$name}{SENDSNAPS}{$tac}) {
              delete $data{SSCam}{$name}{SENDSNAPS}{$tac};
              $del = 1;
          }
          if($data{SSCam}{$name}{PARAMS}{$tac}) {
              delete $data{SSCam}{$name}{PARAMS}{$tac};
              $del = 1;
          }
          if ($del && AttrVal($name,"debugactivetoken",0)) {
              Log3($name, 1, "$name - Data of Transaction \"$tac\" deleted");
          }
      } 
      else {
          delete $data{SSCam}{RS};
          delete $data{SSCam}{$name}{SENDRECS};
          delete $data{SSCam}{$name}{SENDSNAPS};
          delete $data{SSCam}{$name}{PARAMS};
          if (AttrVal($name,"debugactivetoken",0)) {
              Log3($name, 1, "$name - Data of internal Cache removed");
          }      
      }
  } 
  else {                                                                                   # Caching mit CHI
      my @as = cache($name, "c_getkeys");
      if($tac) {
          for my $k (@as) {
              if ($k =~ /$tac/x) {
                  cache($name, "c_remove", $k);
                  $del = 1;
              }
          }
          if ($del && AttrVal($name,"debugactivetoken",0)) {
              Log3($name, 1, "$name - Data of Transaction \"$tac\" removed");
          }
      
      } 
      else {
          cache($name, "c_clear");
          if (AttrVal($name,"debugactivetoken",0)) {
              Log3($name, 1, "$name - Data of CHI-Cache removed");
          }          
      }
  }

return;
}

#############################################################################################
#         {SENDCOUNT} aus BlockingCall heraus um 1 subtrahieren/addieren
#         $tac = <Transaktionskennung>
#############################################################################################
sub subaddFromBlocking {
  my ($name,$op,$tac) = @_;
  my $hash            = $defs{$name};
  
  if($op eq "-") {
      $data{SSCam}{$name}{SENDCOUNT}{$tac}--;
  }
  
  if($op eq "+") {
      $data{SSCam}{$name}{SENDCOUNT}{$tac}++;
  }
  
  Log3($name, 1, "$name - Send Counter transaction \"$tac\": ".$data{SSCam}{$name}{SENDCOUNT}{$tac}) if(AttrVal($name,"debugactivetoken",0));

return;
}

#############################################################################################
#        Check ob "sscam" im iconpath des FHEMWEB Devices enthalten ist
#############################################################################################
sub checkIconpath {
  my $name     = shift;
  my $FW_wname = shift // return;
  
  my $icpa = AttrVal($FW_wname, "iconPath", "");
  if ($icpa !~ /sscam/x) {
      Log3 ($name, 2, qq{$name - WARNING - add "sscam" to attribute "iconpath" of FHEMWEB device "$FW_wname" to get the SSCam control icons} );
  }
  
return;
}

#############################################################################################
#             Cache Handling  
#             cache ($name, <opcode> [, <Key>, <data>])
#             return 1 = ok , return 0 = nok
#############################################################################################
sub cache {
  my ($name,$op,$key,$dat) = @_;
  my $hash           = $defs{$name};
  my $type           = AttrVal($name,"cacheType","internal");
  my ($server,$port) = split(":",AttrVal($name,"cacheServerParam",""));
  my $path           = $attr{global}{modpath}."/FHEM/FhemUtils/cacheSSCam";       # Dir für FileCache
  my $fuuid          = $hash->{FUUID};
  my ($cache,$r,$bst,$brt);
  
  $bst = [gettimeofday];

  ### Cache Initialisierung ###
  ############################# 
  if($op eq "c_init") {
      if ($type eq "internal") {
          Log3($name, 4, "$name - internal Cache mechanism is used ");
          return $type;
      }  
      
      if($SScamMMCHI) {
          Log3($name, 1, "$name - Perl cache module ".$SScamMMCHI." is missing. You need to install it with the FHEM Installer for example.");
          return 0;
      }
      if($type eq "redis" && $SScamMMCHIRedis) {
          Log3($name, 1, "$name - Perl cache module ".$SScamMMCHIRedis." is missing. You need to install it with the FHEM Installer for example.");
          return 0;
      }
      if($type eq "filecache" && $SScamMMCacheCache) {
          Log3($name, 1, "$name - Perl cache module ".$SScamMMCacheCache." is missing. You need to install it with the FHEM Installer for example.");
          return 0;
      }
      
      if ($hash->{HELPER}{CACHEKEY}) {
          Log3($name, 4, "$name - Cache \"$type\" is already initialized ");
          return $type;
      }
      
      if($type eq "mem") {
          # This cache driver stores data on a per-process basis. This is the fastest of the cache implementations, 
          # but data can not be shared between processes. Data will remain in the cache until cleared, expired, 
          # or the process dies.
          # https://metacpan.org/pod/CHI::Driver::Memory          
          $cache = CHI->new( driver       => 'Memory', 
                             on_set_error => 'warn',
                             on_get_error => 'warn',
                             namespace    => $fuuid,                             
                             global       => 0 
                           );
      }
      
      if($type eq "rawmem") {
          # This is a subclass of CHI::Driver::Memory that stores references to data structures directly instead 
          # of serializing / deserializing. This makes the cache faster at getting and setting complex data structures, 
          # but unlike most drivers, modifications to the original data structure will affect the data structure stored 
          # in the cache.   
          # https://metacpan.org/pod/CHI::Driver::RawMemory
          $cache = CHI->new( driver       => 'RawMemory',
                             on_set_error => 'warn',
                             on_get_error => 'warn', 
                             namespace    => $fuuid,                             
                             global       => 0 
                           );
      }
      
      if($type eq "redis") {
          # A CHI driver that uses Redis to store the data. Care has been taken to not have this module fail in fiery 
          # ways if the cache is unavailable. It is my hope that if it is failing and the cache is not required for your work, 
          # you can ignore its warnings.
          # https://metacpan.org/pod/CHI::Driver::Redis
          if(!$server || !$port) {
              Log3($name, 1, "$name - ERROR in cache Redis definition. Please provide Redis server parameter in form <Redis-server address>:<Redis-server port> ");
              return 0;
          }
          my $cto = 0.5;
          my $rto = 2.0;
          my $wto = 1.0;
          my %Redispars = ( cnx_timeout   => $cto,
                            read_timeout  => $rto,
                            write_timeout => $wto
                          );
                          
          # Redis Construktor for Test Redis server connection (CHI doesn't do it) 
          delete $hash->{HELPER}{REDISKEY};          
          $r = eval { Redis->new( server      => "$server:$port", 
                                  cnx_timeout => $cto,
                                  debug       => 0
                                ); 
                    };
          if ( my $error = $@ ) {
              # Muster: Could not connect to Redis server at 192.168.2.10:6379: Connection refused at ./FHEM/49_SSCam.pm line 9546.
              $error = (split("at ./FHEM",$error))[0];
              Log3($name, 1, "$name - ERROR - $error");
              return 0;
          } 
          else {
              $hash->{HELPER}{REDISKEY} = $r;
          }
           
          # create CHI Redis constructor           
          $cache = CHI->new( driver        => 'Redis',
                             namespace     => $fuuid,
                             server        => "$server:$port",
                             reconnect     => 1,
                             on_set_error  => 'warn',
                             on_get_error  => 'warn',
                             redis_options => \%Redispars,
                             debug         => 0
                           );
      }
      
      if($type eq "file") {
          # This is a filecache using Cache::Cache.  
          # https://metacpan.org/pod/Cache::Cache 
          my $pr = (split('/',reverse($path),2))[1];
          $pr    = reverse($pr);                  
          if(!(-R $pr) || !(-W $pr)) {                                # root-erzeichnis testen
              Log3($name, 1, "$name - ERROR - cannot create \"$type\" Cache in dir \"$pr\": ".$!);
              delete $hash->{HELPER}{CACHEKEY}; 
              return 0;
          }
          if(!(-d $path)) {                                           # Zielverzeichnis anlegen wenn nicht vorhanden
              my $success = mkdir($path,0775);
              if(!$success) {
                  Log3($name, 1, "$name - ERROR - cannot create \"$type\" Cache path \"$path\": ".$!);
                  delete $hash->{HELPER}{CACHEKEY}; 
                  return 0;             
              }
          }
          
          $cache = CHI->new( driver       => 'CacheCache',
                             on_set_error => 'warn',
                             on_get_error => 'warn',
                             cc_class     => 'Cache::FileCache',
                             cc_options   => { cache_root => $path,
                                               namespace  => $fuuid
                                             },
                           );
      }

      if ($cache && $cache =~ /CHI::Driver::Role::Universal/x) {
          Log3($name, 3, "$name - Cache \"$type\" namespace \"$fuuid\" initialized");
          $hash->{HELPER}{CACHEKEY} = $cache;
          $brt = tv_interval($bst);
          Log3($name, 1, "$name - Cache time to create \"$type\": ".$brt) if(AttrVal($name,"debugCachetime",0));
          return $type;
      } 
      else {
          Log3($name, 3, "$name - no cache \"$type\" available.");
      }
      return 0;
  }
  
  ### Test Operationen ###
  ######################## 
  
  if($hash->{HELPER}{CACHEKEY}) {
      $cache = $hash->{HELPER}{CACHEKEY};
  } 
  else {
      return 0;
  }
  
  if($type eq "redis") {
      # Test ob Redis Serververbindung möglich
      my $rc = $hash->{HELPER}{REDISKEY};
      if ($rc) {
          eval { $r = $rc->ping };                      ## no critic 'eval not tested'
          if (!$r || $r ne "PONG") {                    # Verbindungskeys löschen -> Neugenerierung mit "c_init"                   
              Log3($name, 1, "$name - ERROR - connection to Redis server not possible. May be no route to host or port is wrong.");
              delete $hash->{HELPER}{REDISKEY};
              delete $hash->{HELPER}{CACHEKEY}; 
              return 0;          
          }
      } 
      else {
          Log3($name, 1, "$name - ERROR - no constructor for Redis server is created");
          return 0;
      }
  }
  
  if($type eq "file" && (!(-R $path) || !(-W $path))) {
      Log3($name, 1, "$name - ERROR - cannot handle \"$type\" Cache: ".$!);
      delete $hash->{HELPER}{CACHEKEY}; 
      return 0;
  } 
  
  ### Cache Operationen ###
  #########################
  
  # in Cache schreiben
  if($op eq "c_write") {
      if (!defined $dat) {
          Log3($name, 1, "$name - ERROR - No data for Cache with key: $key ");
      }
      
      if($key) {
          $cache->set($key,$dat);
          $brt = tv_interval($bst);
          Log3($name, 1, "$name - Cache time write key \"$key\": ".$brt) if(AttrVal($name,"debugCachetime",0));
          return 1;
      } 
      else {
          Log3($name, 1, "$name - ERROR - no key for \"$type\" cache !");
      }
  }
  
  # aus Cache lesen
  if($op eq "c_read") {
      my $g = $cache->get($key);
      $brt  = tv_interval($bst);
      Log3($name, 1, "$name - Cache time read key \"$key\": ".$brt) if(AttrVal($name,"debugCachetime",0));
      
      if(!$g) {
          return "";     
      } 
      else {      
          return $g;
      }
  }
  
  # einen Key entfernen
  if($op eq "c_remove") {
      $cache->remove($key);
      $brt = tv_interval($bst);
      Log3($name, 1, "$name - Cache time remove key \"$key\": ".$brt) if(AttrVal($name,"debugCachetime",0));  
      Log3($name, 4, "$name - Cache key \"$key\" removed ");
      return 1;   
  }
  
  # alle Einträge aus Cache (Namespace) entfernen
  if($op eq "c_clear") {
      $cache->clear();
      Log3($name, 4, "$name - All entries removed from \"$type\" cache ");     
      return 1;   
  }
  
  # alle Keys aus Cache zurück liefern
  if($op eq "c_getkeys") {
      return $cache->get_keys;
  }
  
  # einen Key im Cache prüfen 
  if($op eq "c_isvalidkey") {
      return $cache->is_valid($key);
  }
  
  # Cache entfernen
  if($op eq "c_destroy") {
      $cache->clear();
      delete $hash->{HELPER}{CACHEKEY};
      Log3($name, 3, "$name - Cache \"$type\" destroyed "); 
      return 1;   
  }
  
return 0;
}

######################################################################################
#                   initiale Startroutinen nach Restart FHEM
######################################################################################
sub initOnBoot {
  my $hash = shift;
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash, "FHEM::SSCam::initOnBoot");
  
  if($init_done == 1) {
     RemoveInternalTimer($hash);                                                                     # alle Timer löschen
     
     delete($defs{$name}{READINGS}{LiveStreamUrl}) if($defs{$name}{READINGS}{LiveStreamUrl});        # LiveStream URL zurücksetzen
     
     if (ReadingsVal($hash->{NAME}, "Record", "Stop") eq "Start") {                                  # check ob alle Recordings = "Stop" nach Reboot -> sonst stoppen
         Log3($name, 2, "$name - Recording of $hash->{CAMNAME} seems to be still active after FHEM restart - try to stop it now");
         __camStopRec($hash);
     }
         
     if (!$hash->{CREDENTIALS}) {                                                                    # Konfiguration der Synology Surveillance Station abrufen
         Log3($name, 2, qq{$name - Credentials of $name are not set - make sure you've set it with "set $name credentials <username> <password>"});
     } 
     else {
         readingsSingleUpdate($hash, "compstate", "true", 0);                                        # Anfangswert f. versionCheck setzen
         __getCaminfoAll($hash,1);                                                                   # "1" ist Statusbit für manuelle Abfrage, kein Einstieg in Pollingroutine
         versionCheck($hash);                                                                        # Einstieg in regelmäßigen Check Kompatibilität
     }
         
     # Subroutine Watchdog-Timer starten (sollen Cam-Infos regelmäßig abgerufen werden ?), verzögerter zufälliger Start 0-30s 
     RemoveInternalTimer($hash, "FHEM::SSCam::wdpollcaminfo");
     InternalTimer      (gettimeofday()+int(rand(30)), "FHEM::SSCam::wdpollcaminfo", $hash, 0);
  
  } 
  else {
      InternalTimer(gettimeofday()+3, "FHEM::SSCam::initOnBoot", $hash, 0);
  }
  
return;
}

###############################################################################
#          Dauerschleife Kompatibilitätscheck SSCam <-> SVS
###############################################################################
sub versionCheck {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $rc   = 21600;
  
  RemoveInternalTimer($hash, "FHEM::SSCam::versionCheck");
  return if(IsDisabled($name));

  my $cs = ReadingsVal($name, "compstate", "true");
  if($cs eq "false") {
      Log3($name, 2, "$name - WARNING - The current/simulated SVS-version ".ReadingsVal($name, "SVSversion", "").
       " may be incompatible with SSCam version $hash->{HELPER}{VERSION}. ".
       "For further information execute \"get $name versionNotes 4\".");
  }
  
InternalTimer(gettimeofday()+$rc, "FHEM::SSCam::versionCheck", $hash, 0);

return; 
}

################################################################
#               return 0 - Startmeldung OpMode im Log 
#               return 1 - wenn Shutdown läuft
################################################################
sub startOrShut {                      
  my $name = shift;
  my $hash = $defs{$name};
  
  if ($shutdownInProcess) {                                                             # shutdown in Proces -> keine weiteren Aktionen
      Log3($name, 3, "$name - Shutdown in process. No more activities allowed.");
      return 1;       
  }
  
  Log3($name, 4, "$name - ####################################################"); 
  Log3($name, 4, "$name - ###    start cam operation $hash->{OPMODE}          "); 
  Log3($name, 4, "$name - ####################################################"); 
          
return 0;
}

###############################################################################
# Err-Status / Log setzen wenn Device Verfügbarkeit disabled oder disconnected          
###############################################################################
sub exitOnDis { 
  my $name = shift;
  my $log  = shift;
  my $hash = $defs{$name};
  
  my $exit = 0;
  
  my $errorcode = "000";
  my $avail     = ReadingsVal($name, "Availability", "");
  
  if ($avail eq "disabled") {
      $errorcode = "402";
      $exit      = 1;
  } elsif ($avail eq "disconnected") {
      $errorcode = "502";
      $exit      = 1;
  }

  if($exit) {
      my $error = expErrors($hash,$errorcode);                      # Fehlertext zum Errorcode ermitteln

      readingsBeginUpdate ($hash);
      readingsBulkUpdate  ($hash, "Errorcode", $errorcode);
      readingsBulkUpdate  ($hash, "Error",     $error    );
      readingsEndUpdate   ($hash, 1);
      
      Log3($name, 2, "$name - ERROR - $log - $error");
  }
  
return $exit;
}

###########################################################################
#    plant die aufrufende Funktion mit einem Delta Time aus dem Hash %hdt
#    neu mit InternalTimer ein
#    $arg = Argument für InternalTimer
###########################################################################
sub schedule {
  my $name = shift;
  my $arg  = shift;
  
  my $pack   = __PACKAGE__;
  my $caller = (caller(1))[3];
  my $sub    = (split /${pack}::/x, $caller)[1];
  my $dt     = $hdt{$sub};

  if(!$dt) {
      $dt = 1;
      Debug (qq{$pack - no delta time found for function "$sub", use default of $dt seconds instead})
  }
  
  InternalTimer(gettimeofday()+$dt, $caller, $arg, 0);
    
  if (AttrVal($name,"debugactivetoken",0)) {
      Log3($name, 1, "$name - Function $caller scheduled again with delta time $dt seconds");  
  }
    
return;           
}

###############################################################################
#          Liefert die bereinigte SVS-Version dreistellig xxx
###############################################################################
sub myVersion {
  my $hash  = shift;
  my $name  = $hash->{NAME};
  my $actvs = 0; 

  my @vl = split (/-/x,ReadingsVal($name, "SVSversion", ""),2);
  if(@vl) {
      $actvs = $vl[0];
      $actvs =~ s/\.//gx;
  }
  
return $actvs; 
}

######################################################################################
#                              Polling Überwachung
# Überwacht die Wert von Attribut "pollcaminfoall" und Reading "PollState"
# wenn Attribut "pollcaminfoall" > 10 und "PollState"=Inactive -> start Polling
######################################################################################
sub wdpollcaminfo {
    my ($hash)   = @_;
    my $name     = $hash->{NAME};
    my $camname  = $hash->{CAMNAME};
    my $pcia     = AttrVal($name,"pollcaminfoall",0); 
    my $pnl      = AttrVal($name,"pollnologging",0); 
    my $watchdogtimer = 60+rand(30);
    my $lang     = AttrVal("global","language","EN");
    
    RemoveInternalTimer($hash, "FHEM::SSCam::wdpollcaminfo");

    if ($hash->{HELPER}{OLDVALPOLLNOLOGGING} != $pnl) {                                             # Poll-Logging prüfen
        $hash->{HELPER}{OLDVALPOLLNOLOGGING} = $pnl;                                                # aktuellen pollnologging-Wert in $hash eintragen für späteren Vergleich
        if ($pnl) {
            Log3($name, 3, "$name - Polling-Log of $camname is deactivated");          
        } 
        else {
            Log3($name, 3, "$name - Polling-Log of $camname is activated");
        }
    }    
    
    if ($pcia && !IsDisabled($name)) {                                                              # Polling prüfen
        if(ReadingsVal($name, "PollState", "Active") eq "Inactive") {
            readingsSingleUpdate($hash,"PollState","Active",1);                                     # Polling ist jetzt aktiv
            readingsSingleUpdate($hash,"state","polling",1) if(!IsModelCam($hash));                 # Polling-state bei einem SVS-Device setzten
            Log3($name, 3, "$name - Polling of $camname is activated - Pollinginterval: $pcia s");
            $hash->{HELPER}{OLDVALPOLL} = $pcia;                                                    # in $hash eintragen für späteren Vergleich (Changes von pollcaminfoall)
            __getCaminfoAll($hash,0);  
        }
        
        my $lupd = ReadingsVal($name, "LastUpdateTime", "1970-01-01 / 01:00:00");
        my ($year,$month,$mday,$hour,$min,$sec);
        
        if ($lupd =~ /(\d+)\.(\d+)\.(\d+)/x) {
            ($mday, $month, $year, $hour, $min, $sec) = ($lupd =~ /(\d+)\.(\d+)\.(\d+)\s\/\s(\d+):(\d+):(\d+)/x);
        } 
        else {
            ($year, $month, $mday, $hour, $min, $sec) = ($lupd =~ /(\d+)-(\d+)-(\d+)\s\/\s(\d+):(\d+):(\d+)/x);        
        }
        
        $lupd = fhemTimeLocal($sec, $min, $hour, $mday, $month-=1, $year-=1900);
        
        if( gettimeofday() > ($lupd + $pcia + 20) ) {
            __getCaminfoAll($hash,0);  
        }
        
    }
    
    if (defined($hash->{HELPER}{OLDVALPOLL}) && $pcia) {
        if ($hash->{HELPER}{OLDVALPOLL} != $pcia) {
            Log3($name, 3, "$name - Pollinginterval of $camname has been changed to: $pcia s");
            $hash->{HELPER}{OLDVALPOLL} = $pcia;
        }
    }

    InternalTimer(gettimeofday()+$watchdogtimer, "FHEM::SSCam::wdpollcaminfo", $hash, 0);
    
return;
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
       <li>Start a recording and send it optionally by Email and/or Telegram </li>
       <li>Stop a recording by command or automatically after an adjustable period </li>
       <li>Trigger of snapshots / recordings and optional send them alltogether by Email using the integrated Email client or by Synology Chat / Telegram </li>
       <li>Trigger snapshots of all defined cams and optionally send them alltogether by Email using the integrated Email client </li>
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
       <li>create different types of discrete Streaming-Devices (createStreamDev)  </li>
       <li>Activation / Deactivation of a camera integrated PIR sensor  </li>
       <li>Creation of a readingsGroup device to display an overview of all defined SSCam devices (createReadingsGroup) </li>
       <li>automatized definition of all in SVS available cameras in FHEM (autocreateCams) </li>
       <li>save the last recording or the last snapshot of camera locally </li>
       <li>Selection of several cache types for image data storage (attribute cacheType) </li>
       <li>execute Zoom actions (only if PTZ camera supports Zoom) </li>
    </ul>
   </ul>
   <br>
   The recordings and snapshots will be stored in Synology Surveillance Station (SVS) and are managed like the other (normal) recordings / snapshots defined by Surveillance Station rules.<br>
   For example the recordings are stored for a defined time in Surveillance Station and will be deleted after that period.<br><br>
    
   If you like to discuss or help to improve this module please use FHEM-Forum with link: <br>
   <a href="http://forum.fhem.de/index.php/topic,45671.msg374390.html#msg374390">49_SSCam: Fragen, Hinweise, Neuigkeiten und mehr rund um dieses Modul</a>.
   <br><br>
   
   <b>Integration into FHEM TabletUI: </b> <br><br>
   There is a widget provided for integration of SSCam-Streaming devices (Type SSCamSTRM) into FTUI. For further information please be informed by the
   (german) FHEM Wiki article: <br>
   <a href="https://wiki.fhem.de/wiki/FTUI_Widget_f%C3%BCr_SSCam_Streaming_Devices_(SSCamSTRM)">FTUI Widget für SSCam Streaming Devices (SSCamSTRM)</a>.
   <br><br><br>
  
  <b>Prerequisites </b> <br><br>
  <ul>
    This module uses the Perl-modules JSON and MIME::Lite which are usually have to be installed in addition. <br>
    On Debian-Linux based systems these modules can be installed by: <br><br>
    
    <code>sudo apt-get install libjson-perl</code>      <br>
    <code>sudo apt-get install libmime-lite-perl</code> <br><br>
    
    SSCam is completely using the nonblocking functions of HttpUtils respectively HttpUtils_NonblockingGet. <br> 
    In DSM respectively in Synology Surveillance Station an User has to be created. The login credentials are needed later when using a set-command to assign the login-data to a device. <br> 
    Further informations could be find among <a href="#Credentials">Credentials</a>.  <br><br>
    
    Overview which Perl-modules SSCam is using: <br><br>
    
    <table>
    <colgroup> <col width=35%> <col width=65%> </colgroup>
    <tr><td>JSON                </td><td>                                                </td></tr>
    <tr><td>Data::Dumper        </td><td>                                                </td></tr>
    <tr><td>MIME::Base64        </td><td>                                                </td></tr>
    <tr><td>Time::HiRes         </td><td>                                                </td></tr>
    <tr><td>Encode              </td><td>                                                </td></tr>
    <tr><td>POSIX               </td><td>                                                </td></tr>
    <tr><td>HttpUtils           </td><td>(FHEM-module)                                   </td></tr>
    <tr><td>Blocking            </td><td>(FHEM-module)                                   </td></tr>
    <tr><td>Meta                </td><td>(FHEM-module)                                   </td></tr>
    <tr><td>Net::SMTP           </td><td>(if integrated image data transmission is used) </td></tr>
    <tr><td>MIME::Lite          </td><td>(if integrated image data transmission is used) </td></tr>
    <tr><td>CHI                 </td><td>(if Cache is used)                              </td></tr>
    <tr><td>CHI::Driver::Redis  </td><td>(if Cache is used)                              </td></tr>
    <tr><td>Cache::Cache        </td><td>(if Cache is used)                              </td></tr>
    </table> 
    
    <br>
    
    SSCam uses its own icons. 
    In order for the system to find the icons, the attribute <b>iconPath</b> must be supplemented with <b>sscam</b> in the FHEMWEB device. <br><br>
    
    <ul>
      <b>Example</b> <br>    
      attr WEB iconPath default:fhemSVG:openautomation:sscam 
    </ul>
    <br><br>
  </ul>  

  <a name="SSCamdefine"></a>
  <b>Define</b>
  <ul>
  <br>
    There is a distinction between the definition of a camera-device and the definition of a Surveillance Station (SVS) 
    device, that means the application on the discstation itself. 
    Dependend on the type of defined device the internal MODEL will be set to "&lt;vendor&gt; - &lt;camera type&gt;" 
    or "SVS" and a proper subset of the described set/get-commands are assigned to the device. <br>
    The scope of application of set/get-commands is denoted to every particular command (valid for CAM, SVS, CAM/SVS). <br>
    The cameras can be defined manually discrete, but alternatively with an automatical procedure by set "autocreateCams" 
    command in a previously defined SVS device.
    <br><br>
    
    A <b>camera device</b> is defined by: <br><br>
    <ul>
      <b><code>define &lt;Name&gt; SSCAM &lt;camera name in SVS&gt; &lt;ServerAddr&gt; [Port] [Protocol]</code></b> <br><br>
    </ul>
    
    At first the devices have to be set up and has to be operable in Synology Surveillance Station 7.0 and above. <br><br>
    
    A <b>SVS-device</b> to control functions of the Surveillance Station (SVS) is defined by: <br><br>
    <ul>
      <b><code>define &lt;Name&gt; SSCAM SVS &lt;ServerAddr&gt; [Port] [Protocol] </code></b> <br><br>
    </ul>
    
    In that case the term &lt;camera name in SVS&gt; become replaced by <b>SVS</b> only. <br>
    Is the SVS defined and after setting the appropriate creadentials ready for use, all cameras available in SVS can be created 
    automatically in FHEM with the set command "autocreateCams". 
    <br><br>
    
    The Modul SSCam ist based on functions of Synology Surveillance Station API. <br><br>

    The parameters are in detail:
   <br>
   <br>    
     
   <table>
    <colgroup> <col width=15%> <col width=85%> </colgroup>
    <tr><td><b>Name</b>         </td><td>the name of the new device to use in FHEM</td></tr>
    <tr><td><b>Cameraname</b>   </td><td>camera name as defined in Synology Surveillance Station if camera-device, "SVS" if SVS-Device. Spaces are not allowed in camera name. </td></tr>
    <tr><td><b>ServerAddr</b>   </td><td>IP-address of Synology Surveillance Station Host. <b>Note:</b> avoid using hostnames because of DNS-Calls are not unblocking in FHEM </td></tr>
    <tr><td><b>Port</b>         </td><td>optional - the port of synology disc station. If not set, the default "5000" is used</td></tr>
    <tr><td><b>Protocol</b>     </td><td>optional - the protocol (http or https) to access the synology disc station. If not set, the default "http" is used</td></tr>   
   </table>

    <br><br>

    <b>Examples:</b>
     <pre>
      <code>define CamCP SSCAM Carport 192.168.2.20 [5000] [http]</code>
      <code>define CamCP SSCAM Carport 192.168.2.20 [5001] [https]</code>
      # creates a new camera device CamCP

      <code>define DS1 SSCAM SVS 192.168.2.20 [5000] [http]</code>
      <code>define DS1 SSCAM SVS 192.168.2.20 [5001] [https]</code>
      # creares a new SVS device DS1      
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
    
    <a name="Credentials"></a>
    <b>Credentials </b><br><br>
    
    <ul>
    After a camera-device is defined, firstly it is needed to save the credentials. This will be done with command:
   
    <pre> 
     set &lt;name&gt; credentials &lt;username&gt; &lt;password&gt;
    </pre>
    
    The password length has a maximum of 20 characters. <br> 
    The operator can, dependend on what functions are planned to execute, create an user in DSM respectively in Synology 
    Surveillance Station as well. <br>
    If the user is member of admin-group, he has access to all module functions. Without this membership the user can only 
    execute functions with lower need of rights. <br>
    Is <a href="https://www.synology.com/en-global/knowledgebase/DSM/tutorial/General/How_to_add_extra_security_to_your_Synology_NAS#t5">2-step verification</a>  
    activated in DSM, the setup to a session with Surveillance Station is necessary (<a href="#SSCamattr">attribute</a> "session = SurveillanceStation"). <br><br>
    The required minimum rights to execute functions are listed in a table further down. <br>
    
    Alternatively to DSM-user a user created in SVS can be used. Also in that case a user of type "manager" has the right to 
    execute all functions, <br>
    whereat the access to particular cameras can be restricted by the privilege profile (please see help function in SVS for 
    details).  <br>
    As best practice it is proposed to create an user in DSM as well as in SVS too:  <br><br>
    
    <ul>
    <li>DSM-User as member of admin group: unrestricted test of all module functions -&gt; session: DSM  </li>
    <li>SVS-User as Manager or observer: adjusted privilege profile -&gt; session: SurveillanceStation  </li>
    </ul>
    <br>
    
    Using the <a href="#SSCamattr">Attribute</a> "session" can be selected, if the session should be established to DSM or the 
    SVS instead. Further informations about user management in SVS are available by execute  
    "get &lt;name&gt; versionNotes 5".<br>
    If the session will be established to DSM, SVS Web-API methods are available as well as further API methods of other API's 
    what possibly needed for processing. <br><br>
    
    After device definition the default is "login to DSM", that means credentials with admin rights can be used to test all camera-functions firstly. <br>
    After this the credentials can be switched to a SVS-session with a restricted privilege profile as needed on dependency what module functions are want to be executed. <br><br>
    
    The following list shows the <b>minimum rights</b> that the particular module function needs. <br><br>
    <ul>
      <table>
      <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td><li>set ... on                 </td><td> session: ServeillanceStation - observer with enhanced privilege "manual recording" </li></td></tr>
      <tr><td><li>set ... off                </td><td> session: ServeillanceStation - observer with enhanced privilege "manual recording" </li></td></tr>
      <tr><td><li>set ... snap               </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>set ... delPreset          </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>set ... disable            </td><td> session: ServeillanceStation - manager with edit camera right      </li></td></tr>
      <tr><td><li>set ... enable             </td><td> session: ServeillanceStation - manager with edit camera right      </li></td></tr>
      <tr><td><li>set ... expmode            </td><td> session: ServeillanceStation - manager       </li></td></tr>
      <tr><td><li>set ... extevent           </td><td> session: DSM - user as member of admin-group   </li></td></tr>
      <tr><td><li>set ... goPreset           </td><td> session: ServeillanceStation - observer with privilege objective control of camera  </li></td></tr>
      <tr><td><li>set ... homeMode           </td><td> ssession: ServeillanceStation - observer with privilege Home Mode switch (valid for <b>SVS-device ! </b>) </li></td></tr>
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
  </ul>
    
<a name="HTTPTimeout"></a>
<b>HTTP-Timeout Settings</b><br><br>
    
  <ul>  
    All functions of SSCam use HTTP-calls to SVS Web API. <br>
    You can set the attribute <a href="#httptimeout">httptimeout</a> &gt; 0 to adjust 
    the value as needed in your technical environment. <br>
    
  </ul>
  <br><br><br>
  
  
<a name="SSCamset"></a>
<b>Set </b>
  <ul>  
  <br>
  The specified set-commands are available for CAM/SVS-devices or only valid for CAM-devices or rather for SVS-Devices. 
  They can be selected in the drop-down-menu of the particular device. <br><br>
  
  <ul>
  <li><b> autocreateCams </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for SVS)</li> <br>
  
  If a SVS device is defined, all in SVS integrated cameras are able to be created automatically in FHEM by this command. If the camera is already defined, 
  it is overleaped. 
  The new created camera devices are created in the same room as the used SVS device (default SSCam). Further helpful attributes are preset as well. 
  <br><br>
  </ul>
  
  <ul>
  <a name="SSCamcreateStreamDev"></a>
  <li><b> createStreamDev [generic | hls | lastsnap | mjpeg | switched] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM) <br>
  respectively <br>
  <b> createStreamDev [master] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for SVS) <br>
  <br>
  
  A separate Streaming-Device (type SSCamSTRM) will be created. This device can be used as a discrete device in a dashboard 
  for example.
  The current room of the parent camera device is assigned to the new device if it is set there.
  <br><br>
  
    <ul>
    <table>
    <colgroup> <col width=10%> <col width=90%> </colgroup>
      <tr><td>generic   </td><td>- the streaming device playback a content determined by attribute <a href="#genericStrmHtmlTag">genericStrmHtmlTag</a> </td></tr>
      <tr><td>hls       </td><td>- the streaming device playback a permanent HLS video stream </td></tr>
      <tr><td>lastsnap  </td><td>- the streaming device playback the newest snapshot </td></tr>
      <tr><td>mjpeg     </td><td>- the streaming device playback a permanent MJPEG video stream (Streamkey method) </td></tr>
      <tr><td>switched  </td><td>- playback of different streaming types. Buttons for mode control are provided. </td></tr>
     <tr><td>master     </td><td>- with the master device another defined streaming device can be adopted and its content displayed </td></tr>
    </table>
    </ul>
    <br><br>  
 
  You can control the design with HTML tags in attribute <a href="#htmlattr">htmlattr</a> of the camera device or by 
  specific attributes of the SSCamSTRM-device itself. <br><br>
  </li>
  
  <b>Streaming device "hls"</b> <br><br>
 
  The Streaming-device of type "hls" uses the library hls.js to playback the video stream and is executable on most current
  browsers with MediaSource extensions (MSE). With <a href="#SSCamattr">attribuet</a> "hlsNetScript" can be specified, whether 
  the local installed version of hls.js (./www/pgm2/sscam_hls.js) or the newest online library version from the hls.js 
  project site should be used. This attribute has to be set centrally in a device of type "SVS" ! <br>
  If this kind of streaming device is used, the <a href="#SSCamattr">attribute</a> "hlsStrmObject" must be set in the parent 
  camera device (see Internal PARENT).
  <br><br>
  
  <b>Streaming device "switched hls"</b> <br><br>
  
  This type of streaming device uses the HLS video stream native delivered by Synology Surveillance Station.
  If HLS (HTTP Live Streaming) is used in Streaming-Device of type "switched", then the camera has to be set to video format
  H.264 in the Synology Surveillance Station and the SVS-Version has to support the HLS format. 
  Therefore the selection button of HLS is only provided by the Streaming-Device if the Reading "CamStreamFormat" contains 
  "HLS". <br>
  HTTP Live Streaming is currently only available on Mac Safari or modern mobile iOS/Android devices. 
  <br><br>

  <b>Streaming device "generic"</b> <br><br>
  
  A streaming device of type "generic" needs the complete definition of HTML-Tags by the attribute "genericStrmHtmlTag". 
  These tags specify the content to playback. <br><br>

    <ul>
      <b>Example:</b>
      <pre>
attr &lt;name&gt; genericStrmHtmlTag &lt;video $HTMLATTR controls autoplay&gt;
                                 &lt;source src='http://192.168.2.10:32000/$NAME.m3u8' type='application/x-mpegURL'&gt;
                               &lt;/video&gt;

attr &lt;name&gt; genericStrmHtmlTag &lt;img $HTMLATTR 
                                 src="http://192.168.2.10:32774"
                                 onClick="FW_okDialog('&lt;img src=http://192.168.2.10:32774 $PWS&gt')"
                               &gt                                 
      </pre>
      The variables $HTMLATTR, $NAME and $PWS are placeholders and absorb the attribute "htmlattr" (if set), the SSCam-Devicename 
      respectively the value of attribute "popupWindowSize" in streamin-device, which specify the windowsize of a popup window.
    </ul>
  <br><br>
    
  <b>Streaming device "lastsnap"</b> <br><br>
  
  This type of streaming device playback the last (newest) snapshot. 
  As default the snapshot is retrieved in a reduced resolution. In order to use the original resolution, the attribute 
  <b>"snapGallerySize = Full"</b> has to be set in the associated camera device (compare Internal PARENT).  
  There also the attribute "pollcaminfoall" should be set to retrieve the newest snapshot regularly.  
  <br><br>  
  
  <b>Streaming Device "master"</b> <br><br>
  
  This type cannot play back streams itself. Switching the playback of the content of another defined 
  Streaming Devices is done by the Set command <b>adopt</b> in the Master Streaming Device.
  <br>
  <br><br>
  </ul> 
  
  <ul>
  <li><b> createPTZcontrol </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for PTZ-CAM)</li> <br>
  
  A separate PTZ control panel will be created (type SSCamSTRM). The current room of the parent camera device is 
  assigned if it is set there (default "SSCam").  
  With the "ptzPanel_.*"-<a href="#SSCamattr">attributes</a> or respectively the specific attributes of the SSCamSTRM-device
  the properties of the control panel can be affected. <br> 
  <br><br>
  <br>
  </ul>
  
  <ul>
  <li><b> createReadingsGroup [&lt;name of readingsGroup&gt;]</b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM/SVS)</li> <br>
  
  This command creates a readingsGroup device to display an overview of all defined SSCam devices. 
  A name for the new readingsGroup device can be specified. Is no own name specified, the readingsGroup device will be 
  created with name "RG.SSCam".
  <br> 
  <br><br>
  </ul>
  
  <ul>
  <li><b> createSnapGallery </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  A snapshot gallery will be created as a separate device (type SSCamSTRM). The device will be provided in 
  room "SSCam".
  With the "snapGallery..."-<a href="#SSCamattr">attributes</a> respectively the specific attributes of the SSCamSTRM-device
  you are able to manipulate the properties of the new snapshot gallery device. 
  <br><br>
  
  <b>Note</b> <br>
  The camera names in Synology SVS should not be very similar, otherwise the retrieval of snapshots could come to inaccuracies.

  <br><br>
  </ul>
  
  <ul>
  <li><b> credentials &lt;username&gt; &lt;password&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM/SVS)</li> <br>
  
  set username / password combination for access the Synology Surveillance Station. 
  See <a href="#Credentials">Credentials</a><br> for further informations.
  
  <br><br>
  </ul>
  
  <ul>
  <li><b> delPreset &lt;PresetName&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for PTZ-CAM)</li> <br>
  
  Deletes a preset "&lt;PresetName&gt;". In FHEMWEB a drop-down list with current available presets is provieded.

  </ul>
  <br><br>
  
  <ul>
  <a name="disable"></a>
  <li><b> disable </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM) <br>
  Disables the camera in Synology Surveillance Station.
  </li>
  </ul>
  <br><br>
  
  <ul>
  <a name="enable"></a>
  <li><b> enable </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM) <br>
  Activate the camera in Synology Surveillance Station.
  </li>
  </ul>
  <br><br>
  
  <ul>
  <li><b> expmode [day|night|auto] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  With this command you are able to control the exposure mode and can set it to day, night or automatic mode. 
  Thereby, for example, the behavior of camera LED's will be suitable controlled. 
  The successful switch will be reported by the reading CamExposureMode (command "get ... caminfoall"). <br><br>
  
  <b> Note: </b><br>
  The successfully execution of this function depends on if SVS supports that functionality of the connected camera.
  Is the field for the Day/Night-mode shown greyed in SVS -&gt; IP-camera -&gt; optimization -&gt; exposure mode, this function will be probably unsupported.  
  </ul>
  <br><br>
  
  <ul>
  <li><b> extevent [ 1-10 ] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for SVS)</li> <br>
  
  This command triggers an external event (1-10) in SVS. 
  The actions which will are used have to be defined in the actionrule editor of SVS at first. There are the events 1-10 possible.
  In the message application of SVS you may select Email, SMS or Mobil (DS-Cam) messages to release if an external event has been triggerd.
  Further informations can be found in the online help of the actionrule editor.
  The used user needs to be a member of the admin-group and DSM-session is needed too.
  </ul>
  <br><br>
  
  <ul>
  <li><b> goAbsPTZ [ X Y | up | down | left | right ] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
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
  <li><b> goPreset &lt;Preset&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
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
  <li><b> homeMode [on|off] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for SVS)</li> <br>
  
  Switch the HomeMode of the Surveillance Station on or off. 
  Further informations about HomeMode you can find in the <a href="https://www.synology.com/en-global/knowledgebase/Surveillance/help/SurveillanceStation/home_mode">Synology Onlinehelp</a>.
  <br><br>
  </ul>
  
  <ul>
  <li><b> motdetsc [camera|SVS|disable] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
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
      <tr><td>set &lt;name&gt; motdetsc camera [sensitivity] [object size] [percentage] </td><td># command pattern  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc camera 89 0 20                                  </td><td># set the sensitivity to 89, percentage to 20  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc camera 0 40 10                                  </td><td># keep old value for sensitivity, set threshold to 40, percentage to 10  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc camera 30                                       </td><td># set the sensitivity to 30, other values keep unchanged  </td></tr>
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
  <li><b> move [ right | up | down | left | dir_X ] [Sekunden] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM up to SVS version 7.1)</li>
      <b> move [ right | upright | up | upleft | left | downleft | down | downright ] [Sekunden] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM and SVS Version 7.2 and above) <br><br>
  
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
  <br>
  
  <ul>
  <li><b> off  </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li><br>

  Stops the current recording. 
  </ul>
  <br><br>
  
  <ul>
  <li><b>set &lt;name&gt; on [&lt;rectime&gt;] <br>
                             [recEmailTxt:"subject => &lt;subject text&gt;, body => &lt;message text&gt;"] <br>
                             [recTelegramTxt:"tbot => &lt;TelegramBot device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;subject text&gt;]"] <br> 
                             [recChatTxt:"chatbot => &lt;SSChatBot device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;subject text&gt;]"] <br> 
                             </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
   
  A recording will be started. The default recording time is 15 seconds. It can be individually changed by 
  the <a href="#SSCamattr">attribute</a> "rectime". 
  The recording time can be overwritten on-time by "set &lt;name&gt; on &lt;rectime&gt;" for the current recording.
  The recording will be stopped after processing time "rectime"automatically.<br>

  A special case is start recording by "set &lt;name&gt; on 0" respectively the attribute value "rectime = 0". In this case 
  an endless-recording will be started. One have to explicitely stop this recording with command "set &lt;name&gt; off".<br>

  Furthermore the recording behavior can be impacted with <a href="#SSCamattr">attribute</a> "recextend" as explained as 
  follows.<br><br>

  <b>Attribute "recextend = 0" or not set (default):</b><br>
  <ul>
  <li> if, for example, a recording with rectimeme=22 is started, no other startcommand (for a recording) will be accepted until this started recording is finished.
  A hint will be logged in case of verboselevel = 3. </li>
  </ul>
  <br>

  <b>Attribute "recextend = 1" is set:</b><br>
  <ul>
  <li> a before started recording will be extend by the recording time "rectime" if a new start command is received. That means, the timer for the automatic stop-command will be
  renewed to "rectime" given bei the command, attribute or default value. This procedure will be repeated every time a new start command for recording is received. 
  Therefore a running recording will be extended until no start command will be get. </li>

  <li> a before started endless-recording will be stopped after recordingtime 2rectime" if a new "set <name> on"-command is received (new set of timer). If it is unwanted make sure you 
  don't set the <a href="#SSCamattr">attribute</a> "recextend" in case of endless-recordings. </li>
  </ul>
  <br>
  
  The shipping of recording by <b>Synology Chat</b> can be activated permanently by setting attribute <a href="#recChatTxt">recChatTxt</a> 
  Of course, the <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers">SSChatBot device</a> which is 
  used for send data, must be defined and fully functional before. <br>
  If you want temporary overwrite the message text as set in attribute "recChatTxt", you can optionally specify the 
  "recChatTxt:"-tag as shown above. If the attribute "recChatTxt" is not set, the shipping by Telegram is
  activated one-time. (the tag-syntax is equivalent to the "recChatTxt" attribute) <br><br>
  
  The <b>Email shipping</b> of recordings can be activated by setting <a href="#SSCamattr">attribute</a> "recEmailTxt". 
  Before you have to prepare the Email shipping as described in section <a href="#SSCamEmail">Setup Email shipping</a>. 
  (for further information execute "<b>get &lt;name&gt; versionNotes 7</b>") <br>
  Alternatively you can activate the Email-shipping one-time when you specify the "recEmailTxt:"-tag in the "on"-command.
  In this case the tag-text is used for creating the Email instead the text specified in "recEmailTxt"-attribute.
  (the tag syntax is identical to the "recEmailTxt" attribute)
  <br><br>
  
  The shipping of the last recording by <b>Telegram</b> can be activated permanently by setting <a href="#SSCamattr">attribute</a> 
  "recTelegramTxt". Of course, the <a href="http://fhem.de/commandref.html#TelegramBot">TelegramBot device</a> which is 
  used, must be defined and fully functional before. <br>
  If you want temporary overwrite the message text as set with attribute "recTelegramTxt", you can optionally specify the 
  "recTelegramTxt:"-tag as shown above. If the attribute "recTelegramTxt" is not set, the shipping by Telegram is
  activated one-time. (the tag-syntax is equivalent to the "recTelegramTxt" attribute) <br><br>
  
  <b>Examples: </b> <br><br>
  set &lt;name&gt; on [rectime]  <br>
  # starts a recording, stops automatically after [rectime] <br>
  <code> set &lt;name&gt; on 0  </code><br>
  # starts a permanent record which must be stopped with the "off"-command. <br>
  <code> set &lt;name&gt; on recEmailTxt:"subject => New recording for $CAM created, body => The last recording of $CAM is atteched."  </code><br>
  # starts a recording and send it after completion by Email. <br>
  <code> set &lt;name&gt; on recTelegramTxt:"tbot => teleBot, peers => @xxxx , subject => Movement alarm by $CAM. The snapshot $FILE was created at $CTIME"  </code><br>
  # starts a recording and send it after completion by Telegram. <br>
  <code> set &lt;name&gt; on recChatTxt:"chatbot => SynChatBot, peers => , subject => Movement alarm by $CAM. The snapshot $FILE was created at $CTIME."  </code><br>
  # starts a recording and send it after completion by Synology Chat. <br>
  </ul>
  <br><br>
  
  <ul>
  <li><b> optimizeParams [mirror:&lt;value&gt;] [flip:&lt;value&gt;] [rotate:&lt;value&gt;] [ntp:&lt;value&gt;]</b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
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
  <li><b> pirSensor [activate | deactivate] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  Activates / deactivates the infrared sensor of the camera (only posible if the camera has got a PIR sensor).  
  </ul>
  <br><br>
  
  <ul>
  <li><b> runPatrol &lt;Patrolname&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  This commans starts a predefined patrol (tour) of a PTZ-camera. <br>
  At first the patrol has to be predefined in the Synology Surveillance Station. It can be done in the PTZ-control of IP-Kamera Setup -&gt; PTZ-control -&gt; patrol.
  The patrol tours will be read with command "get &lt;name&gt; caminfoall" which is be executed automatically when FHEM restarts.
  The import process can be repeated regular by camera polling. A long polling interval is recommendable in this case because of the patrols are only will be changed 
  if the user change it in the IP-camera setup itself. 
  Further informations for creating patrols you can get in the online-help of Surveillance Station.
  </ul>
  <br><br>
  
  <ul>
  <li><b> runView [live_fw | live_link | live_open [&lt;room&gt;] | lastrec_fw | lastrec_fw_MJPEG | lastrec_fw_MPEG4/H.264 | lastrec_open [&lt;room&gt;] | lastsnap_fw]  </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
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
  Synology Surveillance Station and the SVS-Version has to support the HLS format.
  Therefore this possibility is only present if the Reading "CamStreamFormat" is set to "HLS".
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
  
  Dependend of the content to playback, different control buttons are provided: <br><br>
  <ul>   
    <table>  
    <colgroup> <col width=25%> <col width=75%> </colgroup>
      <tr><td> Start Recording </td><td>- starts an endless recording </td></tr>
      <tr><td> Stop Recording  </td><td>- stopps the recording </td></tr>
      <tr><td> Take Snapshot   </td><td>- take a snapshot </td></tr>
      <tr><td> Switch off      </td><td>- stops a running playback </td></tr>
    </table>
   </ul>     
   <br>
  
  <b>Note for HLS (HTTP Live Streaming):</b> <br>
  The video starts with a technology caused delay. Every stream will be segemented into some little video files 
  (with a lenth of approximately 10 seconds) and is than delivered to the client. 
  The video format of the camera has to be set to H.264 in the Synology Surveillance Station and not every camera type is
  a proper device for HLS-Streaming.
  At the time only the Mac Safari Browser and modern mobile iOS/Android-Devices are able to playback HLS-Streams. 
  <br><br>
  
  <b>Note for MJPEG:</b> <br>
  The MJPEG stream is SVS internal transcoded from other codec and is usally only about 1 fps.
  
  </ul>
  <br><br>
  
  <ul>
  <li><b> setHome &lt;PresetName&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for PTZ-CAM)</li> <br>
  
  Set the Home-preset to a predefined preset name "&lt;PresetName&gt;" or the current position of the camera.

  </ul>
  <br><br>
  
  <ul>
  <li><b> setPreset &lt;PresetNumber&gt; [&lt;PresetName&gt;] [&lt;Speed&gt;] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for PTZ-CAM)</li> <br>
  
  Sets a Preset with name "&lt;PresetName&gt;" to the current postion of the camera. The speed can be defined 
  optionally (&lt;Speed&gt;). If no PresetName is specified, the PresetNummer is used as name.
  For this reason &lt;PresetName&gt; is defined as optional, but should usually be set.

  </ul>
  <br><br>
  
  <ul>
  <li><b> setZoom &lt; .++ | + | stop | - | --. &gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for PTZ-CAM)</li> <br>
  
  Provides controls for zoom functions if the camera supports this feature.

  </ul>
  <br><br>
  
  <ul>
  <li><b> snap [&lt;number&gt;] [&lt;time difference&gt;] <br>
  
                                [snapEmailTxt:"subject => &lt;subject text&gt;, body => &lt;message text&gt;"] <br>
                                [snapTelegramTxt:"tbot => &lt;TelegramBot device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;subject text&gt;]"] <br>
                                [snapChatTxt:"chatbot => &lt;SSChatBot device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;subject text&gt;]"]    <br>
                                </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  One or multiple snapshots are triggered. The number of snapshots to trigger and the time difference (in seconds) between
  each snapshot can be optionally specified. Without any specification only one snapshot is triggered. <br>
  The ID and the filename of the last snapshot will be displayed in Reading "LastSnapId" respectively 
  "LastSnapFilename". <br>
  To get data of the last 1-10 snapshots in various versions, the attribute <a href="#snapReadingRotate">snapReadingRotate</a>
  can be used.
  <br><br>
  
  A snapshot shipping by <b>Synology Chat</b> can be permanently activated by setting attribute <a href="#snapChatTxt">snapChatTxt</a>. 
  Of course, the <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers">SSChatBot device</a> which is 
  used must be defined and fully functional before. <br>
  If you want temporary overwrite the subject set in attribute "snapChatTxt", you can optionally specify the 
  "snapChatTxt:"-tag as shown above. If the attribute "snapChatTxt" is not set, the shipping by SSChatBot is
  activated one-time (the tag-syntax is equivalent to the "snapChatTxt" attribute). <br>
  In either case the attribute <a href="#videofolderMap">videofolderMap</a> has to be set before. It must contain an URL to the 
  root directory of recordings and snapshots (e.g. http://server.me:8081/surveillance). <br><br>
  
  The snapshot <b>Email shipping</b> can be activated by setting attribute <a href="#snapEmailTxt">snapEmailTxt</a>. 
  Before you have to prepare the Email shipping as described in section <a href="#SSCamEmail">Setup Email shipping</a>. 
  (for further information execute "<b>get &lt;name&gt; versionNotes 7</b>") <br>
  If you want temporary overwrite the message text set in attribute "snapEmailTxt", you can optionally specify the 
  "snapEmailTxt:"-tag as shown above. If the attribute "snapEmailTxt" is not set, the Email shipping is
  activated one-time. (the tag-syntax is equivalent to the "snapEmailTxt" attribut) <br><br>
  
  A snapshot shipping by <b>Telegram</b> can be permanently activated by setting attribute <a href="#snapTelegramTxt">snapTelegramTxt</a>. 
  Of course, the <a href="http://fhem.de/commandref.html#TelegramBot">TelegramBot device</a> which is 
  used must be defined and fully functional before. <br>
  If you want temporary overwrite the message text set in attribute "snapTelegramTxt", you can optionally specify the 
  "snapTelegramTxt:"-tag as shown above. If the attribute "snapTelegramTxt" is not set, the shipping by Telegram is
  activated one-time. (the tag-syntax is equivalent to the "snapTelegramTxt" attribut) <br><br>
  
  <b>Examples:</b>
  <pre>
    set &lt;name&gt; snap
    set &lt;name&gt; snap 4 
    set &lt;name&gt; snap 3 3 snapEmailTxt:"subject => Movement alarm $CAM, body => A movement was recognised at Carport"
    set &lt;name&gt; snap 2 snapTelegramTxt:"tbot => teleBot, peers => , subject => Movement alarm by $CAM. The snapshot $FILE was created at $CTIME"
    set &lt;name&gt; snap 2 snapChatTxt:"chatbot => SynChatBot , peers => Frodo Sam, subject => Movement alarm by $CAM. At $CTIME the snapshot  $FILE was created. Now it is: $TIME."
  </pre>
  </ul>
  <br><br>
  
  <ul>
  <li><b> snapCams [&lt;number&gt;] [&lt;time difference&gt;] [CAM:"&lt;camera&gt;, &lt;camera&gt, ..."]</b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for SVS)</li> <br>
  
  One or multiple snapshots of denoted cameras are triggered. If no cameras are denoted, the snapshots are triggered in all 
  of the defined cameras in FHEM.
  Optionally the number of snapshots to trigger (default: 1) and the time difference (in seconds) between
  each snapshot (default: 2) can be specified. <br>
  The ID and the filename of the last snapshot will be displayed in Reading "LastSnapId" respectively "LastSnapFilename" of
  the appropriate camera device. <br><br>
  
  The snapshot <b>Email shipping</b> can be activated by setting <a href="#SSCamattr">attribute</a> "snapEmailTxt" in the 
  SVS device <b>AND</b> in the camera devices whose snapshots should be shipped. 
  Before you have to prepare the Email shipping as described in section <a href="#SSCamEmail">Setup Email shipping</a>. 
  (for further information execute "<b>get &lt;name&gt; versionNotes 7</b>") <br>
  Only the message text set in attribute "snapEmailTxt" of the SVS device is used in the created Email. The settings of 
  those attribute in the camera devices is ignored !! <br><br>
  
  <b>Examples:</b>
  <pre>
    set &lt;name&gt; snapCams 4 
    set &lt;name&gt; snapCams 3 3 CAM:"CamHE1, CamCarport"
  </pre>
  </ul>
  <br><br>
  
  <ul>
  <li><b> snapGallery [1-10] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  The command is only available if the attribute "snapGalleryBoost=1" is set. <br>
  It creates an output of the last [x] snapshots as well as "get ... snapGallery".  But differing from "get" with
  <a href="#SSCamattr">attribute</a> "snapGalleryBoost=1" no popup will be created. The snapshot gallery will be depicted as
  an browserpage instead. All further functions and attributes are appropriate the <a href="#SSCamget">"get &lt;name&gt; snapGallery"</a>
  command. <br>
  If you want create a snapgallery output by triggering, e.g. with an "at" or "notify", you should use the 
  <a href="#SSCamget">"get &lt;name&gt; snapGallery"</a> command instead of "set".
  <br><br>
  
  <b>Note</b> <br>
  The camera names in Synology SVS should not be very similar, otherwise the retrieval of snapshots could come to inaccuracies.

  </ul>
  <br><br>
  
  <ul>
  <li><b> startTracking </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM with tracking capability)</li> <br>
  
  Starts object tracking of camera.
  The command is only available if surveillance station has recognised the object tracking capability of camera
  (Reading "CapPTZObjTracking").
  </ul>
  <br><br>
  
  <ul>
  <li><b> stopTracking </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM with tracking capability)</li> <br>
  
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
  <a name="apiInfo"></a>
  <li><b> apiInfo </b> <br>
  
  Retrieves the API information of the Synology Surveillance Station and open a popup window with its data.
  <br>
  </li><br>
  </ul>

  <ul>
  <li><b>  caminfoall </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM/SVS)</li> 
      <b>  caminfo </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM) <br><br>
      
  Dependend of the type of camera (e.g. Fix- or PTZ-Camera) the available properties are retrieved and provided as Readings.<br>
  For example the Reading "Availability" will be set to "disconnected" if the camera would be disconnected from Synology 
  Surveillance Station and can't be used for further processing like creating events. <br>
  "getcaminfo" retrieves a subset of "getcaminfoall".
  </ul>
  <br><br>  
  
  <ul>
  <li><b>  eventlist </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  The <a href="#SSCamreadings">Reading</a> "CamEventNum" and "CamLastRecord" will be refreshed which containes the total number 
  of in SVS registered camera events and the path/name of the last recording. 
  This command will be implicit executed when "get &lt;name&gt; caminfoall" is running. <br>
  The <a href="#SSCamattr">attribute</a> "videofolderMap" replaces the content of reading "VideoFolder". You can use it for 
  example if you have mounted the videofolder of SVS under another name or path and want to access by your local pc. 
  </ul>
  <br><br>

  <ul>
  <li><b>  homeModeState </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for SVS)</li> <br>
  
  HomeMode-state of the Surveillance Station will be retrieved.  
  </ul>
  <br><br>

  <ul>
    <a name="listLog"></a>
    <li><b>  listLog [severity:&lt;Loglevel&gt;] [limit:&lt;Number of lines&gt;] [match:&lt;Searchstring&gt;] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for SVS) <br>
  
    Fetches the Surveillance Station Log from Synology server. Without any further options the whole log will be retrieved. <br>
    You can specify all or any of the following options: <br><br>
  
    <ul>
      <li> &lt;Loglevel&gt; - Information, Warning or Error. Only datasets having this severity are retrieved (default: all) </li>
      <li> &lt;Number of lines&gt; - the specified number of lines  (newest) of the log are retrieved (default: all) </li>
      <li> &lt;Searchstring&gt; - only log entries containing the searchstring are retrieved (Note: no Regex possible, the searchstring will be given into the call to SVS) </li>
    </ul>
    <br>
    </li>
  
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
  <li><b>  listPresets </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for PTZ-CAM)</li> <br>
  
  Get a popup with a lists of presets saved for the camera.
  </ul>
  <br><br>
  
  <ul>
  <li><b>  saveLastSnap [&lt;Pfad&gt;] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  The (last) snapshot currently specified in the reading "LastSnapId" is saved locally as a jpg file. 
  Optionally, the path to save the file can be specified in the command (default: modpath in global Device). <br>
  The file is locally given the same name as contained in the reading "LastSnapFilename". <br>
  The resolution of the snapshot is determined by the attribute "snapGallerySize".
  
  <br><br>
  
  <ul>
    <b>Example:</b> <br><br>
    get &lt;name&gt; saveLastSnap /opt/fhem/log
  </ul>
  
  </ul>
  <br><br>

  <ul>
  <li><b>  saveRecording [&lt;path&gt;] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  The current recording present in Reading "CamLastRec" is saved lcally as a MP4 file. Optionally you can specify the path 
  for the file to save (default: modpath in global device). <br>
  The name of the saved local file is the same as displayed in Reading "CamLastRec". <br><br>
  
  <ul>
    <b>Example:</b> <br><br>
    get &lt;name&gt; saveRecording /opt/fhem/log
  </ul>
  
  </ul>
  <br><br>   
  
  <ul>
  <li><b>  scanVirgin </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM/SVS)</li> <br>
  
  This command is similar to get caminfoall, informations relating to SVS and the camera will be retrieved. 
  In difference to caminfoall in either case a new session ID will be generated (do a new login), the camera ID will be
  new identified and all necessary API-parameters will be new investigated.  
  </ul>
  <br><br> 
  
  <ul>
  <li><b>  snapGallery [1-10] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
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
        ressources are needed. The camera names in Synology SVS should not be very similar, otherwise the retrieval of 
        snapshots could come to inaccuracies.
        </ul>
        <br><br>
  
  <ul>
  <li><b>  snapfileinfo </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  The filename of the last snapshot will be retrieved. This command will be executed with <b>"get &lt;name&gt; snap"</b> 
  automatically.
  </ul>
  <br><br>  
  
  <ul>
  <li><b>  snapinfo </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  Informations about snapshots will be retrieved. Heplful if snapshots are not triggerd by SSCam, but by motion detection of the camera or surveillance
  station instead.
  </ul>
  <br><br> 
  
  <ul>
  <li><b>  stmUrlPath </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
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
  <li><b>  storedCredentials </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM/SVS)</li> <br>
  
  Shows the stored login credentials in a popup as plain text.
  </ul>
  <br><br>  
  
  <ul>
  <li><b>  svsinfo </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM/SVS)</li> <br>
  
  Determines common informations about the installed SVS-version and other properties. <br>
  </ul>
  <br><br> 

  <ul>
  <li><b>  versionNotes [hints | rel | &lt;key&gt;] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM/SVS)</li> <br>
  
  Shows realease informations and/or hints about the module. It contains only main release informations for module users. <br>
  If no options are specified, both release informations and hints will be shown. "rel" shows only release informations and
  "hints" shows only hints. By the &lt;key&gt;-specification only the hint with the specified number is shown.
  </ul>
  <br><br> 

  <a name="SSCamEmail"></a>
  <b>Setup Email shipping</b> <br><br>
  
  <ul>
  Snapshots and recordings can be sent by <b>Email</b> after creation. For this purpose the module contains its 
  own Email client. Before you can use this function you have to install the Perl-module <b>MIME::Lite</b>. On debian 
  systems it can be installed with command: <br><br>
   
   <ul>
    sudo apt-get install libmime-lite-perl
   </ul>
   <br>
  
  There are some attributes must be set or can be used optionally. <br>
  At first the Credentials for access the Email outgoing server must be set by command <b>"set &lt;name&gt; smtpcredentials &lt;user&gt; &lt;password&gt;"</b>.
  The connection establishment to the server is initially done unencrypted and switches to an encrypted connection if SSL 
  encryption is available. In that case the transmission of User/Password takes place encrypted too. 
  If attribute "smtpSSLPort" is defined, the established connection to the Email server will be encrypted immediately.
  Attributes which are optional are marked: <br><br>
  
  <ul>   
    <table>  
    <colgroup> <col width=12%> <col width=88%> </colgroup>
      <tr><td> <b>snapEmailTxt</b>                     </td><td>- <b>Activates the Email shipping of snapshots.</b> This attribute has the format: <br>
                                                                   <ul>
                                                                   <code>subject => &lt;subject text&gt;, body => &lt;message text&gt; </code>
                                                                   </ul>
                                                                  The placeholder $CAM, $DATE and $TIME can be used. <br> 
                                                                  Optionally you can specify the "snapEmailTxt:"-tag when trigger a snapshot with the "snap"-command.
                                                                  In this case the Email shipping is activated one-time for the snapshot or the tag-text 
                                                                  is used instead of the text defined in the "snapEmailTxt"-attribute. </td></tr>
      <tr><td> </td><td> </td></tr>
      <tr><td> </td><td> </td></tr>
      <tr><td> <b>recEmailTxt</b>                      </td><td>- <b>Activates the Email shipping of recordings.</b> This attribute has the format: <br>
                                                                  <ul>
                                                                  <code>subject => &lt;subject text&gt;, body => &lt;message text&gt; </code>
                                                                  </ul>
                                                                  The placeholder $CAM, $DATE and $TIME can be used. <br> 
                                                                  Optionally you can specify the "recEmailTxt:"-tag when start recording with the "on"-command.
                                                                  In this case the Email shipping is activated one-time for the started recording or the tag-text 
                                                                  is used instead of the text defined in the "recEmailTxt"-attribute. </td></tr>
      <tr><td> </td><td> </td></tr>
      <tr><td> </td><td> </td></tr>
      <tr><td>                            <b>smtpHost</b>     </td><td>- Hostname of outgoing Email server (e.g. securesmtp.t-online.de) </td></tr>
      <tr><td>                            <b>smtpFrom</b>     </td><td>- Return address (&lt;name&gt@&lt;domain&gt) </td></tr>
      <tr><td>                            <b>smtpTo</b>       </td><td>- Receiving address(es) (&lt;name&gt@&lt;domain&gt) </td></tr>
      <tr><td>                            <b>smtpPort</b>     </td><td>- (optional) Port of outgoing Email server (default: 25) </td></tr>
      <tr><td>                            <b>smtpCc</b>       </td><td>- (optional) carbon-copy receiving address(es) (&lt;name&gt@&lt;domain&gt) </td></tr>
      <tr><td>                            <b>smtpNoUseSSL</b> </td><td>- (optional) "1" if no SSL encryption should be used for Email shipping (default: 0) </td></tr>
      <tr><td>                            <b>smtpSSLPort</b>  </td><td>- (optional) Port for SSL encrypted connection (default: 465) </td></tr>
      <tr><td>                            <b>smtpDebug</b>    </td><td>- (optional) switch on the debugging of SMTP connection </td></tr>
    </table>
   </ul>     
   <br>
   
   For further information please see description of the <a href="#SSCamattr">attributes</a>. <br><br>
  
   Description of the placeholders: <br><br>
    
   <ul>   
   <table>  
   <colgroup> <col width=10%> <col width=90%> </colgroup>
     <tr><td> $CAM   </td><td>- Device alias respectively the name of the camera in SVS if the device alias isn't set </td></tr>
     <tr><td> $DATE  </td><td>- current date </td></tr>
     <tr><td> $TIME  </td><td>- current time </td></tr>
     <tr><td> $FILE  </td><td>- name of the snapshot file </td></tr>
     <tr><td> $CTIME </td><td>- creation time of the snapshot </td></tr>
   </table>
   </ul>     
   <br> 
  </ul>    
  <br><br> 
  
  <a name="SSCamPolling"></a>
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
  Because of that if HTTP-Timeout (pls. refer attribute <a href="#httptimeout">httptimeout</a>) is set to 4 seconds, the theoretical processing time couldn't be higher than 80 seconds. <br>
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
  <li><b>COMPATIBILITY</b> - information up to which SVS-version the module version is currently released/tested (see also Reading "compstate") </li>
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
  
  <a name="cacheServerParam"></a>
  <li><b>cacheServerParam</b><br> 
    Specification of connection parameters to a central data cache. <br><br>

    <table>  
    <colgroup> <col width=10%> <col width=90%> </colgroup>
     <tr><td> <b>redis    </b> </td><td>: if network connection is used: &lt;IP-address&gt;:&lt;port&gt; / if Unix-Socket is used: &lt;unix&gt;:&lt;/path/to/socket&gt; </td></tr>
    </table>
    
    <br>
  </li><br> 
  
  <a name="cacheType"></a>
  <li><b>cacheType</b><br>
    Defines the used Cache for storage of snapshots, recordings und other mass data.  
    (Default: internal). <br>
    Maybe further perl modules have to be installed, e.g. with help of the <a href="http://fhem.de/commandref.html#Installer">FHEM Installer</a>. <br>
    The data are saved in "Namespaces" to permit the usage of central Caches (e.g. redis). <br>
    The cahe types "file" and "redis" are convenient if the data shouldn't be hold in the RAM of the FHEM-Server. 
    For the usage of Redis at first a the Redis Key-Value Store has to be provide, e.g. in a Docker image on the
    Synology Diskstation (<a href="https://hub.docker.com/_/redis">redis</a>). <br><br>

    <table>  
    <colgroup> <col width=10%> <col width=90%> </colgroup>
     <tr><td> <b>internal </b> </td><td>: use the module internal storage (Default) </td></tr>
     <tr><td> <b>mem      </b> </td><td>: very fast Cache, copy data into the RAM </td></tr>
     <tr><td> <b>rawmem   </b> </td><td>: fastest Cache for complex data, stores references into the RAM </td></tr>
     <tr><td> <b>file     </b> </td><td>: create and use a file structure in subdirectory "FhemUtils" </td></tr>
     <tr><td> <b>redis    </b> </td><td>: use a external Redis Key-Value Store over TCP/IP or Unix-Socket. Please see also attribute "cacheServerParam". </td></tr>
    </table>
    
    <br>
  </li><br> 
  
  <a name="debugactivetoken"></a>
  <li><b>debugactivetoken</b><br>
    If set, the state of active token will be logged - only for debugging, don't use it in normal operation ! 
  </li><br>
  
  <a name="debugCachetime"></a>
  <li><b>debugCachetime</b><br> 
    Shows the consumed time of cache operations. 
  </li><br>
  
  <a name="disable"></a>
  <li><b>disable</b><br>
    deactivates the device definition 
  </li><br>
    
  <a name="genericStrmHtmlTag"></a>
  <li><b>genericStrmHtmlTag</b><br>
  This attribute contains HTML-Tags for video-specification in a Streaming-Device of type "generic". 
  (see also "set &lt;name&gt; createStreamDev generic") <br><br> 
  
    <ul>
      <b>Examples:</b>
      <pre>
attr &lt;name&gt; genericStrmHtmlTag &lt;video $HTMLATTR controls autoplay&gt;
                                 &lt;source src='http://192.168.2.10:32000/$NAME.m3u8' type='application/x-mpegURL'&gt;
                               &lt;/video&gt; 
                               
attr &lt;name&gt; genericStrmHtmlTag &lt;img $HTMLATTR 
                                 src="http://192.168.2.10:32774"
                                 onClick="FW_okDialog('&lt;img src=http://192.168.2.10:32774 $PWS&gt')"
                               &gt  
      </pre>
      The variables $HTMLATTR, $NAME and $PWS are placeholders and absorb the attribute "htmlattr" (if set), the SSCam-Devicename 
      respectively the value of attribute "popupWindowSize" in streaming-device, which specify the windowsize of a popup window.
    </ul>
    <br><br>
    </li>
    
  <a name="hlsNetScript"></a>
  <li><b>hlsNetScript</b> &nbsp;&nbsp;&nbsp;&nbsp;(settable in device model "SVS") <br>
    If set, the latest hls.js library version from the project site is used (internet connection is needed). 
    <br>
    In default the local installed library version (./www/pgm2/sscam_hls.js) is uses for playback in all streaming devices  
    of type "hls" (please see also "set &lt;name&gt; createStreamDev hls").
    This attribute has to be set in a device model "SVS" and applies to all streaming devices !
  </li><br>
    
  <a name="hlsStrmObject"></a>
  <li><b>hlsStrmObject</b><br>
  If a streaming device was defined by "set &lt;name&gt; createStreamDev hls", this attribute has to be set and must contain the 
  link to the video object to play back. <br>
  The attribute must specify a HTTP Live Streaming object with the extension ".m3u8". <br>
  The variable $NAME can be used as a placeholder and will be replaced by the camera device name.
  <br><br> 
  
        <ul>
        <b>Examples:</b><br>
        attr &lt;name&gt; hlsStrmObject https://bitdash-a.akamaihd.net/content/MI201109210084_1/m3u8s/f08e80da-bf1d-4e3d-8899-f0f6155f6efa.m3u8  <br>
        attr &lt;name&gt; hlsStrmObject https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8  <br>
        # Sample video streams used for testing the streaming device function (internet connection is needed) <br><br>
        
        attr &lt;name&gt; hlsStrmObject http://192.168.2.10:32000/CamHE1.m3u8  <br>
        # playback a HLS video stream of a camera witch is delivered by e.g. a ffmpeg conversion process   <br><br>
        
        attr &lt;name&gt; hlsStrmObject http://192.168.2.10:32000/$NAME.m3u8  <br>
        # Same as example above, but use the replacement with variable $NAME for "CamHE1"     
        </ul>
        <br>
  </li>
  
  <a name="httptimeout"></a>
  <li><b>httptimeout</b><br>
    Timeout-Value of HTTP-Calls to Synology Surveillance Station. <br> 
    (default: 20 seconds) </li><br>
  
  <a name="htmlattr"></a>
  <li><b>htmlattr</b><br>
    additional specifications to inline oictures to manipulate the behavior of stream, e.g. size of the image.  </li><br>
    
        <ul>
        <b>Example:</b><br>
        attr &lt;name&gt; htmlattr width="500" height="325" top="200" left="300"
        </ul>
        <br>
  
  <a name="livestreamprefix"></a>
  <li><b>livestreamprefix</b><br>
    Overwrites the specifications of protocol, servername and port for further use in livestream address and 
    StmKey.*-readings , e.g. as a link for external use. <br>
    It can be specified of two ways as follows: <br><br> 

    <table>  
    <colgroup> <col width=25%> <col width=75%> </colgroup>
     <tr><td> <b>DEF</b>                                        </td><td>: the protocol, servername and port as specified in device 
                                                                           definition is used </td></tr>
     <tr><td> <b>http(s)://&lt;servername&gt;:&lt;port&gt;</b>  </td><td>: your own address specification is used </td></tr>
    </table>
    <br>

    Servername can be the name or the IP-address of your Synology Surveillance Station.    
    </li><br>

  <a name="loginRetries"></a>
  <li><b>loginRetries</b><br>
    set the amount of login-repetitions in case of failure (default = 3)   </li><br>
  
  <a name="noQuotesForSID"></a>
  <li><b>noQuotesForSID</b><br>
    This attribute delete the quotes for SID and for StmKeys.  
    The attribute may be helpful in some cases to avoid errormessages "402 - permission denied" or "105 - 
    Insufficient user privilege" and makes login possible.  
  </li><br>
  
  <a name="pollcaminfoall"></a>
  <li><b>pollcaminfoall</b><br>
    Interval of automatic polling the Camera properties (&lt;= 10: no polling, &gt; 10: polling with interval) 
  </li><br>

  <a name="pollnologging"></a>
  <li><b>pollnologging</b><br>
    "0" resp. not set = Logging device polling active (default), "1" = Logging device polling inactive
  </li><br>
    
  <a name="ptzNoCapPrePat"></a>  
  <li><b>ptzNoCapPrePat</b><br>
    Some PTZ cameras cannot store presets and patrols despite their PTZ capabilities. 
    To avoid errors and corresponding log messages, the attribute ptzNoCapPrePat can be set in these cases. 
    The system will be notified of a missing preset / patrol capability.
  </li><br> 
   
  <a name="ptzPanel_Home"></a>
  <li><b>ptzPanel_Home</b><br>
    In the PTZ-control panel the Home-Icon (in attribute "ptzPanel_row02") is automatically assigned to the value of 
    Reading "PresetHome".
    With "ptzPanel_Home" you can change the assignment to another preset from the available Preset list. 
  </li><br> 
  
  <a name="ptzPanel_iconPath"></a>  
  <li><b>ptzPanel_iconPath</b><br>
    Path for icons used in PTZ-control panel, default is "www/images/sscam". 
    The attribute value will be used for all icon-files except *.svg. <br>
    For further information execute "get &lt;name&gt; versionNotes 2,6".
  </li><br> 

  <a name="ptzPanel_iconPrefix"></a>
  <li><b>ptzPanel_iconPrefix</b><br>
    Prefix for icons used in PTZ-control panel, default is "black_btn_". 
    The attribute value will be used for all icon-files except *.svg. <br>
    If the used icon-files begin with e.g. "black_btn_" ("black_btn_CAMDOWN.png"), the icon needs to be defined in
    attributes "ptzPanel_row[00-09]" just with the subsequent part of name, e.g. "CAMDOWN.png".
    </li><br>   

  <a name="ptzPanel_row00"></a>
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
    For creation of own icons a template is provided in the SVN. Further information can be get by "get &lt;name&gt; versionNotes 2". 
    <br><br>
    
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

  <a name="ptzPanel_use"></a>
  <li><b>ptzPanel_use</b><br>
    Switch the usage of a PTZ-control panel in detail view respectively a created StreamDevice off or on 
    (default: on). <br>
    The PTZ panel use its own icons. 
    Thereby the system find the icons, in FHEMWEB device the attribute "iconPath" has to be completed by "sscam" 
    (e.g. "attr WEB iconPath default:fhemSVG:openautomation:sscam").    
  </li><br> 
  
  <a name="recChatTxt"></a>
  <li><b>recChatTxt chatbot => &lt;SSChatBot device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;subject text&gt;]  </b><br>
    Activates the permanent shipping of recordings by Synology Chat after its creation. <br>
    Before activating the attribute <a href="#videofolderMap">videofolderMap</a> has to be set. It must contain an URL to the 
    root directory of your SVS recordings and snapshots ( e.g. http://server.me:8081/surveillance ). <br>
    The attribute recChatTxt has to be defined in the form as described. With key "chatbot" the SSChatBot device is specified, 
    which is used for sending the data. Of course, the <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers">SSChatBot device</a> 
    must be available and work well. <br>    
    The setting of "peers" is optional, but the keys must be (empty) specified. 
    If "peer" is empty, the defaultPeer of the SSChatBot device is used. <br><br>
    
    You can use the following placeholders within "subject". <br><br>
    
        <ul>   
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> $CAM   </td><td>- Device alias respectively the name of the camera in SVS if the device alias isn't set </td></tr>
          <tr><td> $DATE  </td><td>- current date </td></tr>
          <tr><td> $TIME  </td><td>- current time </td></tr>
          <tr><td> $FILE  </td><td>- Name of recording file </td></tr>
          <tr><td> $CTIME </td><td>- recording creation time </td></tr>
        </table>
        </ul>     
        <br>    
    
    <b>Examples:</b><br>
    attr &lt;device&gt; recChatTxt chatbot =&gt; teleBot, peers =&gt; , subject =&gt; Motion alarm ($FILE)  <br>
    attr &lt;device&gt; recChatTxt chatbot =&gt; teleBot, peers =&gt; Frodo Sam Gollum, subject =&gt; Motion alarm <br>
    attr &lt;device&gt; recChatTxt chatbot =&gt; teleBot, peers =&gt; , subject =&gt; Motion alarm <br>
    attr &lt;device&gt; recChatTxt chatbot =&gt; teleBot, peers =&gt; , subject =&gt; Motion alarm from $CAM. At $CTIME the recording $FILE was created. Now it is $TIME. <br>
    <br>
  </li><br> 
  
  <a name="recEmailTxt"></a>
  <li><b>recEmailTxt subject => &lt;subject text&gt;, body => &lt;message text&gt; </b><br>
    Activates the Email shipping of recordings after whose creation. <br>
    The attribute has to be definied in the form as described. <br>    
    You can use the following placeholders in "subject" and "body". <br><br>
    
        <ul>   
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> $CAM   </td><td>- Device alias respectively the name of the camera in SVS if the device alias isn't set </td></tr>
          <tr><td> $DATE  </td><td>- current date </td></tr>
          <tr><td> $TIME  </td><td>- aktuelle time </td></tr>
        </table>
        </ul>     
        <br>
    
       <ul>
        <b>Example:</b><br>
        recEmailTxt subject => New recording $CAM, body => A new recording of $CAM is created and atteched.
      </ul>
      <br>
  </li>
  
  <a name="recTelegramTxt"></a>
  <li><b>recTelegramTxt tbot => &lt;TelegramBot device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;subject text&gt;]  </b><br>
    Activates the permanent shipping of recordings by TelegramBot after their creation. <br>
    The attribute has to be definied in the form as described. With key "tbot" the TelegramBot device is specified, 
    which is used for shipping the data. Of course, the <a href="http://fhem.de/commandref.html#TelegramBot">TelegramBot device</a> 
    must be available and has to be running well. <br>
    The setting of "peers" and "subject" is optional, but the keys must (empty) specified. 
    If "peer" is empty, the default peer of the TelegramBot device is used. <br><br>
    
    You can use the following placeholders within "subject". <br><br>
    
        <ul>   
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> $CAM   </td><td>- Device alias respectively the name of the camera in SVS if the device alias isn't set </td></tr>
          <tr><td> $DATE  </td><td>- current date </td></tr>
          <tr><td> $TIME  </td><td>- current time </td></tr>
          <tr><td> $FILE  </td><td>- Name of recording file </td></tr>
          <tr><td> $CTIME </td><td>- recording creation time </td></tr>
        </table>
        </ul>     
        <br>    
    
    <b>Examples:</b><br>
    attr &lt;device&gt; recTelegramTxt tbot =&gt; teleBot, peers =&gt; , subject =&gt; Motion alarm ($FILE)  <br>
    attr &lt;device&gt; recTelegramTxt tbot =&gt; teleBot, peers =&gt; @nabuko @foo @bar, subject =&gt;  <br>
    attr &lt;device&gt; recTelegramTxt tbot =&gt; teleBot, peers =&gt; #nabugroup, subject =&gt;  <br>
    attr &lt;device&gt; recTelegramTxt tbot =&gt; teleBot, peers =&gt; -123456, subject =&gt;  <br>
    attr &lt;device&gt; recTelegramTxt tbot =&gt; teleBot, peers =&gt; , subject =&gt;  <br>
    attr &lt;device&gt; recTelegramTxt tbot =&gt; teleBot, peers =&gt; , subject =&gt; Motion alarm from $CAM. At $CTIME the recording $FILE was created. Now it is $TIME. <br>
    <br>
  </li><br>  
  
  <a name="rectime"></a>
  <li><b>rectime</b><br>
   determines the recordtime when a recording starts. If rectime = 0 an endless recording will be started. If 
   it isn't defined, the default recordtime of 15s is activated </li><br>
  
  <a name="recextend"></a>
  <li><b>recextend</b><br>
    "rectime" of a started recording will be set new. Thereby the recording time of the running recording will be 
    extended </li><br>
  
  <a name="session"></a>
  <li><b>session</b><br>
    selection of login-Session. Not set or set to "DSM" -&gt; session will be established to DSM (Sdefault). 
    "SurveillanceStation" -&gt; session will be established to SVS. <br>
    For establish a sesion with Surveillance Station you have to create a user with suitable privilege profile in SVS.
    If you need more infomations please execute "get &lt;name&gt; versionNotes 5".    </li><br>
  
  <a name="simu_SVSversion"></a>
  <li><b>simu_SVSversion</b><br>
    simulates another SVS version. (only a lower version than the installed one is possible !)  </li><br>
    
  <a name="smtpHost"></a>
  <li><b>smtpHost &lt;Hostname&gt; </b><br>
    The name or IP-address of outgoing email server (e.g. securesmtp.t-online.de).
  </li>
  <br>

  <a name="smtpCc"></a>
  <li><b>smtpCc &lt;name&gt;@&lt;domain&gt;[, &lt;name&gt;@&lt;domain&gt;][, &lt;name&gt;@&lt;domain&gt;]... </b><br>
    Optional you can enter a carbon-copy receiving address. Several receiving addresses are separated by ",".
  </li>
  <br>
  
  <a name="smtpDebug"></a>
  <li><b>smtpDebug </b><br>
    Switch the debugging mode for SMTP connection on (if Email shipping is used).
  </li>
  <br>
  
  <a name="smtpFrom"></a>
  <li><b>smtpFrom &lt;name&gt;@&lt;domain&gt; </b><br>
    Return address if Email shipping is used.
  </li>
  <br>
  
  <a name="smtpPort"></a>
  <li><b>smtpPort &lt;Port&gt; </b><br>
    Optional setting of default SMTP port of outgoing email server (default: 25).
  </li>
  <br>
  
  <a name="smtpSSLPort"></a>
  <li><b>smtpSSLPort &lt;Port&gt; </b><br>
    Optional setting of SSL port of outgoing email server (default: 465). If set, the established connection to the Email 
    server will be encrypted immediately.
  </li>
  <br>
  
  <a name="smtpTo"></a>
  <li><b>smtpTo &lt;name&gt;@&lt;domain&gt;[, &lt;name&gt;@&lt;domain&gt;][, &lt;name&gt;@&lt;domain&gt;]... </b><br>
    Receiving address for emal shipping. Several receiving addresses are separated by ",".
  </li>
  <br>
  
  <a name="smtpNoUseSSL"></a>
  <li><b>smtpNoUseSSL </b><br>
    If no Email SSL encryption should be used, set this attribute to "1" (default: 0).
  </li>
  <br>
  
  <a name="snapChatTxt"></a>
  <li><b>snapChatTxt chatbot => &lt;SSChatBot-Device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;subject text&gt;]  </b><br>
    Activates the permanent shipping of snapshots by Synology Chat after their creation. If several snapshots were triggert, 
    they will be sequentially delivered.<br>
    Before activating the attribute <a href="#videofolderMap">videofolderMap</a> has to be set. It must contain an URL to the 
    root directory of your SVS recordings and snapshots ( e.g. http://server.me:8081/surveillance ). <br>
    The attribute snapChatTxt has to be defined in the form as described. With key "chatbot" the SSChatBot device is specified, 
    which is used for sending the data. Of course, the <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers">SSChatBot device</a> 
    must be available and work well. <br>
    The key "peers" contains valid names of Synology Chat Users who should receive the message. <br>
    The setting of "peers" is optional, but the keys must (empty) specified. 
    If "peer" is empty, the defaultPeer of the SSChatBot device is used. <br><br>
    
    You can use the following placeholders within "subject". <br><br>
    
        <ul>   
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> $CAM   </td><td>- Device alias respectively the name of the camera in SVS if the device alias isn't set </td></tr>
          <tr><td> $DATE  </td><td>- current date </td></tr>
          <tr><td> $TIME  </td><td>- current time </td></tr>
          <tr><td> $FILE  </td><td>- Name of snapshot file </td></tr>
          <tr><td> $CTIME </td><td>- creation time of the snapshot </td></tr>
        </table>
        </ul>     
        <br>    

    <b>Examples:</b><br>
    attr &lt;device&gt; snapChatTxt chatbot =&gt; SynChatBot, peers =&gt; , subject =&gt; Motion alarm ($FILE)  <br>
    attr &lt;device&gt; snapChatTxt chatbot =&gt; SynChatBot, peers =&gt; Aragorn Frodo Sam, subject =&gt; A snapshot has been done <br>
    attr &lt;device&gt; snapChatTxt chatbot =&gt; SynChatBot, peers =&gt; , subject =&gt; Caution ! <br>
    attr &lt;device&gt; snapChatTxt chatbot =&gt; SynChatBot, peers =&gt; Frodo, subject =&gt; Motion alarm from $CAM. At $CTIME the snapshot $FILE was created <br>
    <br>
  </li><br> 
  
  <a name="snapEmailTxt"></a>
  <li><b>snapEmailTxt subject => &lt;subject text&gt;, body => &lt;message text&gt; </b><br>
    Activates the Email shipping of snapshots after whose creation. <br>
    The attribute has to be defined in the form as described. <br>
    You can use the following placeholders in "subject" and "body". <br><br>
    
        <ul>   
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> $CAM   </td><td>- Device alias respectively the name of the camera in SVS if the device alias isn't set </td></tr>
          <tr><td> $DATE  </td><td>- current date </td></tr>
          <tr><td> $TIME  </td><td>- current time </td></tr>
        </table>
        </ul>     
        <br>
    
       <ul>
        <b>Example:</b><br>
        snapEmailTxt subject => Motion alarm $CAM, body => A motion was recognized at $CAM.
      </ul>
      <br><br>
  </li>  

  <a name="snapTelegramTxt"></a>
  <li><b>snapTelegramTxt tbot => &lt;TelegramBot device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;subject text&gt;]  </b><br>
    Activates the permanent shipping of snapshots by TelegramBot after their creation. If several snapshots were triggert, 
    they will be sequentially delivered.<br>
    The attribute has to be defined in the form as described. With key "tbot" the TelegramBot device is specified, 
    which is used for shipping the data. Of course, the <a href="http://fhem.de/commandref.html#TelegramBot">TelegramBot device</a> 
    must be available and has to be running well. <br>
    The setting of "peers" and "subject" is optional, but the keys must (empty) specified. 
    If "peer" is empty, the default peer of the TelegramBot device is used. <br><br>
    
    You can use the following placeholders within "subject". <br><br>
    
        <ul>   
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> $CAM   </td><td>- Device alias respectively the name of the camera in SVS if the device alias isn't set </td></tr>
          <tr><td> $DATE  </td><td>- current date </td></tr>
          <tr><td> $TIME  </td><td>- current time </td></tr>
          <tr><td> $FILE  </td><td>- Name of snapshot file </td></tr>
          <tr><td> $CTIME </td><td>- creation time of the snapshot </td></tr>
        </table>
        </ul>     
        <br>    

    <b>Examples:</b><br>
    attr &lt;device&gt; snapTelegramTxt tbot =&gt; teleBot, peers =&gt; , subject =&gt; Motion alarm ($FILE)  <br>
    attr &lt;device&gt; snapTelegramTxt tbot =&gt; teleBot, peers =&gt; @nabuko @foo @bar, subject =&gt;  <br>
    attr &lt;device&gt; snapTelegramTxt tbot =&gt; teleBot, peers =&gt; #nabugroup, subject =&gt;  <br>
    attr &lt;device&gt; snapTelegramTxt tbot =&gt; teleBot, peers =&gt; -123456, subject =&gt;  <br>
    attr &lt;device&gt; snapTelegramTxt tbot =&gt; teleBot, peers =&gt; , subject =&gt;  <br>
    attr &lt;device&gt; snapTelegramTxt tbot =&gt; teleBot, peers =&gt; , subject =&gt; Motion alarm from $CAM. At $CTIME the snapshot $FILE was created <br>
    <br>
  </li><br>   
    
  <a name="snapGalleryBoost"></a>
  <li><b>snapGalleryBoost</b><br>
    If set, the last snapshots (default 3) will be retrieved by Polling, will be stored in the FHEM-servers main memory
    and can be displayed by the "set/get ... snapGallery" command. <br>
    This mode is helpful if many or full size images shall be displayed. 
    If the attribute is set, you can't specify arguments in addition to the "set/get ... snapGallery" command. 
    (see also attribut "snapGalleryNumber") </li><br>
  
  <a name="snapGalleryColumns"></a>
  <li><b>snapGalleryColumns</b><br>
    The number of snapshots which shall appear in one row of the gallery popup (default 3). </li><br>
    
  <a name="snapGalleryHtmlAttr"></a>
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
    
  <a name="snapGalleryNumber"></a>  
  <li><b>snapGalleryNumber</b><br>
    The number of snapshots to retrieve (default 3). </li><br>
    
  <a name="snapGallerySize"></a>
  <li><b>snapGallerySize</b><br>
     By this attribute the quality of the snapshot images can be controlled (default "Icon"). <br>
     If mode "Full" is set, the images are retrieved with their original available resolution. That requires more ressources 
     and may slow down the display. By setting attribute "snapGalleryBoost=1" the display may accelerated, because in that case
     the images will be retrieved by continuous polling and need only bring to display. </li><br>
     
  <a name="snapReadingRotate"></a>
  <li><b>snapReadingRotate 0...10</b><br>
    Activates the version control of snapshot readings (default: 0). A consecutive number of readings "LastSnapFilename", 
    "LastSnapId" and "LastSnapTime" until to the specified value of snapReadingRotate will be created and contain the data
    of the last X snapshots. </li><br>
  
  <a name="showStmInfoFull"></a>
  <li><b>showStmInfoFull</b><br>
    additional stream informations like LiveStreamUrl, StmKeyUnicst, StmKeymjpegHttp will be created  </li><br>
  
  <a name="showPassInLog"></a>
  <li><b>showPassInLog</b><br>
    if set the used password will be shown in logfile with verbose 4. (default = 0) </li><br>
  
  <a name="videofolderMap"></a>
  <li><b>videofolderMap</b><br>
    Replaces the content of reading "VideoFolder". Use it if e.g. folders are mountet with different names than original 
    in SVS or providing an URL for acces the snapshots / recordings by a web server. </li><br>
  
  <a name="verbose"></a>
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
    <tr><td><li>CamLastRec</li>         </td><td>- Path / name of last recording   </td></tr>
    <tr><td><li>CamLastRecId</li>       </td><td>- the ID of last recording   </td></tr>
    <tr><td><li>CamLastRecTime</li>     </td><td>- date / starttime - endtime of the last recording (format depends of global attribute "language")  </td></tr>
    <tr><td><li>CamLiveFps</li>         </td><td>- Frames per second of Live-Stream  </td></tr>
    <tr><td><li>CamLiveMode</li>        </td><td>- Source of Live-View (DS, Camera)  </td></tr>
    <tr><td><li>camLiveQuality</li>     </td><td>- Live-Stream quality set in SVS  </td></tr>
    <tr><td><li>camLiveResolution</li>  </td><td>- Live-Stream resolution set in SVS  </td></tr>
    <tr><td><li>camLiveStreamNo</li>    </td><td>- used Stream-number for Live-Stream  </td></tr>
    <tr><td><li>CamModel</li>           </td><td>- Model of camera  </td></tr>
    <tr><td><li>CamMotDetSc</li>        </td><td>- state of motion detection source (disabled, by camera, by SVS) and their parameter </td></tr>
    <tr><td><li>CamNTPServer</li>       </td><td>- set time server  </td></tr>
    <tr><td><li>CamPort</li>            </td><td>- IP-Port of Camera  </td></tr>
    <tr><td><li>CamPreRecTime</li>      </td><td>- Duration of Pre-Recording (in seconds) adjusted in SVS  </td></tr>
    <tr><td><li>CamPtSpeed</li>         </td><td>- adjusted value of Pan/Tilt-activities (setup in SVS)  </td></tr>
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
    <tr><td><li>CapPIR</li>             </td><td>- has the camera a PIR sensor feature </td></tr>
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
    <tr><td><li>LastSnapFilename[x]</li></td><td>- the filename of the last snapshot or snapshots   </td></tr>
    <tr><td><li>LastSnapId[x]</li>      </td><td>- the ID of the last snapshot or snapshots   </td></tr>    
    <tr><td><li>LastSnapTime[x]</li>    </td><td>- timestamp of the last snapshot or snapshots (format depends of global attribute "language")  </td></tr> 
    <tr><td><li>LastUpdateTime</li>     </td><td>- date / time the last update of readings by "caminfoall" (format depends of global attribute "language") </td></tr> 
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
    <tr><td><li>compstate</li>          </td><td>- state of compatibility (compares current/simulated SVS-version with Internal COMPATIBILITY)  </td></tr>
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
      <li>Start einer Aufnahme und optionaler Versand per Email und/oder Telegram </li>
      <li>Stop einer Aufnahme per Befehl bzw. automatisch nach Ablauf einer einstellbaren Dauer </li>
      <li>Auslösen von Schnappschnüssen / Aufnahmen und optional gemeinsamer Email-Versand mit dem integrierten Email-Client oder Synology Chat / Telegram </li>
      <li>Auslösen von Schnappschnüssen aller definierten Kameras und optionaler gemeinsamer Email-Versand mittels integrierten Email-Client </li>
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
      <li>erzeugen unterschiedlicher Typen von separaten Streaming-Devices (createStreamDev)  </li>
      <li>Aktivierung / Deaktivierung eines kamerainternen PIR-Sensors </li>
      <li>Erzeugung einer readingsGroup zur Anzeige aller definierten SSCam-Devices (createReadingsGroup) </li>
      <li>Automatisiertes Anlegen aller in der SVS vorhandenen Kameras in FHEM (autocreateCams) </li>
      <li>lokales Abspeichern der letzten Kamera-Aufnahme bzw. des letzten Schnappschusses </li>
      <li>Auswahl unterschiedlicher Cache-Typen zur Bilddatenspeicherung (Attribut cacheType) </li>
      <li>ausführen von Zoom-Aktionen (bei PTZ-Kameras die Zoom unterstützen) </li>
     </ul> 
    </ul>
    <br>
    
    Die Aufnahmen stehen in der Synology Surveillance Station (SVS) zur Verfügung und unterliegen, wie jede andere Aufnahme, den in der Synology Surveillance Station eingestellten Regeln. <br>
    So werden zum Beispiel die Aufnahmen entsprechend ihrer Archivierungsfrist gespeichert und dann gelöscht. <br><br>
    
    Wenn sie über dieses Modul diskutieren oder zur Verbesserung des Moduls beitragen möchten, ist im FHEM-Forum ein Sammelplatz unter:<br>
    <a href="http://forum.fhem.de/index.php/topic,45671.msg374390.html#msg374390">49_SSCam: Fragen, Hinweise, Neuigkeiten und mehr rund um dieses Modul</a>.<br><br>

    Weitere Infomationen zum Modul sind im FHEM-Wiki zu finden:<br>
    <a href="http://www.fhemwiki.de/wiki/SSCAM_-_Steuerung_von_Kameras_in_Synology_Surveillance_Station">SSCAM - Steuerung von Kameras in Synology Surveillance Station</a>.
    <br><br>
    
    <b>Integration in FHEM TabletUI: </b> <br><br>
    Zur Integration von SSCam Streaming Devices (Typ SSCamSTRM) wird ein Widget bereitgestellt. 
    Für weitere Information dazu bitte den Artikel im Wiki durchlesen: <br>
    <a href="https://wiki.fhem.de/wiki/FTUI_Widget_f%C3%BCr_SSCam_Streaming_Devices_(SSCamSTRM)">FTUI Widget für SSCam Streaming Devices (SSCamSTRM)</a>.
    <br><br><br>
    
    
    <b>Vorbereitung </b> <br><br>
    
    <ul>
    Dieses Modul nutzt die Perl-Module JSON und MIME::Lite die üblicherweise nachinstalliert werden müssen. <br>
    Auf Debian-Linux basierenden Systemen können sie installiert werden mit: <br><br>
    
    <code>sudo apt-get install libjson-perl</code>      <br>
    <code>sudo apt-get install libmime-lite-perl</code> <br><br>
    
    Das Modul verwendet für HTTP-Calls die nichtblockierenden Funktionen von HttpUtils bzw. HttpUtils_NonblockingGet. <br> 
    Im DSM bzw. der Synology Surveillance Station muß ein Nutzer angelegt sein. Die Zugangsdaten werden später über ein Set-Kommando dem 
    angelegten Gerät zugewiesen. <br>
    Nähere Informationen dazu unter <a href="#Credentials">Credentials</a><br><br>
        
    Überblick über die Perl-Module welche von SSCam genutzt werden: <br><br>
    
    <table>
    <colgroup> <col width=35%> <col width=65%> </colgroup>
    <tr><td>JSON                </td><td>                                   </td></tr>
    <tr><td>Data::Dumper        </td><td>                                   </td></tr>
    <tr><td>MIME::Base64        </td><td>                                   </td></tr>
    <tr><td>Time::HiRes         </td><td>                                   </td></tr>
    <tr><td>Encode              </td><td>                                   </td></tr>
    <tr><td>POSIX               </td><td>                                   </td></tr>
    <tr><td>HttpUtils           </td><td>(FHEM-Modul)                       </td></tr>
    <tr><td>Blocking            </td><td>(FHEM-Modul)                       </td></tr>
    <tr><td>Meta                </td><td>(FHEM-Modul)                       </td></tr>
    <tr><td>Net::SMTP           </td><td>(wenn Bilddaten-Versand verwendet) </td></tr>
    <tr><td>MIME::Lite          </td><td>(wenn Bilddaten-Versand verwendet) </td></tr>
    <tr><td>CHI                 </td><td>(wenn Cache verwendet wird)        </td></tr>
    <tr><td>CHI::Driver::Redis  </td><td>(wenn Cache verwendet wird)        </td></tr>
    <tr><td>Cache::Cache        </td><td>(wenn Cache verwendet wird)        </td></tr>
    </table>
    
    <br>
    
    SSCam benutzt einen eigenen Satz Icons. 
    Damit das System sie findet, ist im FHEMWEB Device das Attribut <b>iconPath</b> um <b>sscam</b> zu ergänzen. <br><br>

      <ul>
        <b>Beispiel</b> <br>
        attr WEB iconPath default:fhemSVG:openautomation:sscam
      </ul>
    <br><br>       
    </ul>

<a name="SSCamdefine"></a>
<b>Definition</b>
  <ul>
  <br>
    Bei der Definition wird zwischen einer Kamera-Definition und der Definition einer Surveillance Station (SVS), d.h.
    der Applikation selbst auf der Diskstation, unterschieden. 
    Abhängig von der Art des definierten Devices wird das Internal MODEL auf "&lt;Hersteller&gt; - &lt;Kameramodell&gt;" oder 
    SVS gesetzt und eine passende Teilmenge der beschriebenen set/get-Befehle dem Device zugewiesen. <br>
    Der Gültigkeitsbereich von set/get-Befehlen ist nach dem jeweiligen Befehl angegeben "gilt für CAM, SVS, CAM/SVS". <br>
    Die Kameras können einzeln manuell, alternativ auch automatisiert mittels einem vorher definierten SVS-Device angelegt werden.
    <br><br>
    
    Eine <b>Kamera</b> wird definiert mit: <br><br>
    <ul>
      <b><code>define &lt;Name&gt; SSCAM &lt;Kameraname in SVS&gt; &lt;ServerAddr&gt; [Port] [Protocol]</code></b> <br><br>
    </ul>
    
    Zunächst muß diese Kamera in der Synology Surveillance Station 7.0 oder höher eingebunden sein und entsprechend 
    funktionieren. <br><br>
    
    Ein <b>SVS-Device</b> zur Steuerung von Funktionen der Surveillance Station wird definiert mit: <br><br>
    <ul>
      <b><code>define &lt;Name&gt; SSCAM SVS &lt;ServerAddr&gt; [Port] [Protocol]</code></b> <br><br>
    </ul>
    
    In diesem Fall wird statt &lt;Kameraname in SVS&gt; nur <b>SVS</b> angegeben. 
    Ist das SVS-Device definiert und nach dem Setzen der Credentials einsatzbereit, können alle in der SVS vorhandenen Kameras mit dem Set-Befehl 
    "autocreateCams" in FHEM automatisiert angelegt werden. <br><br>
    
    Das Modul SSCam basiert auf Funktionen der Synology Surveillance Station API. <br><br> 
    
    Die Parameter beschreiben im Einzelnen:
    <br>
    <br>    
    
    <table>
    <colgroup> <col width=15%> <col width=85%> </colgroup>
    <tr><td><b>Name</b>           </td><td>der Name des neuen Gerätes in FHEM</td></tr>
    <tr><td><b>Kameraname</b>     </td><td>Kameraname wie er in der Synology Surveillance Station angegeben ist für Kamera-Device, "SVS" für SVS-Device. Leerzeichen im Namen sind nicht erlaubt. </td></tr>
    <tr><td><b>ServerAddr</b>     </td><td>die IP-Addresse des Synology Surveillance Station Host. Hinweis: Es sollte kein Servername verwendet werden weil DNS-Aufrufe in FHEM blockierend sind.</td></tr>
    <tr><td><b>Port</b>           </td><td>optional - der Port der Synology Disc Station. Wenn nicht angegeben, wird der Default-Port "5000" genutzt </td></tr>
    <tr><td><b>Protocol</b>       </td><td>optional - das Protokoll (http oder https) zum Funktionsaufruf. Wenn nicht angegeben, wird der Default "http" genutzt </td></tr>
    </table>

    <br><br>

    <b>Beispiel:</b>
     <pre>
      <code>define CamCP SSCAM Carport 192.168.2.20 [5000] [http] </code>
      <code>define CamCP SSCAM Carport 192.168.2.20 [5001] [https]</code>
      # erstellt ein neues Kamera-Device CamCP

      <code>define DS1 SSCAM SVS 192.168.2.20 [5000] [http] </code>
      <code>define DS1 SSCAM SVS 192.168.2.20 [5001] [https] </code>
      # erstellt ein neues SVS-Device DS1
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
    
    <a name="Credentials"></a>
    <b>Credentials </b><br><br>
    
    <ul>
    Nach dem Definieren des Gerätes müssen zuerst die Zugangsparameter gespeichert werden. Das geschieht mit dem Befehl:
   
    <pre> 
     set &lt;name&gt; credentials &lt;Username&gt; &lt;Passwort&gt;
    </pre>
    
    Die Passwortlänge beträgt maximal 20 Zeichen. <br> 
    Der Anwender kann in Abhängigkeit der beabsichtigten einzusetzenden Funktionen einen Nutzer im DSM bzw. in der Surveillance 
    Station einrichten. Sollte im DSM die <a href="https://www.synology.com/de-de/knowledgebase/DSM/tutorial/General/How_to_add_extra_security_to_your_Synology_NAS#t5">2-Stufen Verifizierung</a>  
    aktiviert sein, ist die Session mit der Surveillance Station aufzubauen (<a href="#SSCamattr">Attribut</a> "session = SurveillanceStation"). <br><br>
    Ist der DSM-Nutzer der Gruppe Administratoren zugeordnet, hat er auf alle Funktionen Zugriff. Ohne diese Gruppenzugehörigkeit 
    können nur Funktionen mit niedrigeren Rechtebedarf ausgeführt werden. Die benötigten Mindestrechte der Funktionen sind in 
    der Tabelle weiter unten aufgeführt. <br>
    
    Alternativ zum DSM-Nutzer kann ein in der SVS angelegter Nutzer verwendet werden. Auch in diesem Fall hat ein Nutzer vom 
    Typ Manager das Recht alle Funktionen auszuführen, wobei der Zugriff auf bestimmte Kameras/Funktionen im Privilegienprofil beschränkt 
    werden kann (siehe Hilfefunktion in SVS). <br>
    Als Best Practice wird vorgeschlagen, jeweils einen User im DSM und einen in der SVS anzulegen: <br><br>
    
    <ul>
    <li>DSM-User als Mitglied der Admin-Gruppe: uneingeschränkter Test aller Modulfunktionen -> session: DSM  </li>
    <li>SVS-User als Manager oder Betrachter: angepasstes Privilegienprofil -> session: SurveillanceStation  </li>
    </ul>
    <br>
    
    Über das <a href="#SSCamattr">Attribut</a> "session" kann ausgewählt werden, ob die Session mit dem DSM oder der SVS 
    aufgebaut werden soll. Weitere Informationen zum Usermanagement in der SVS sind verfügbar mit 
    "get &lt;name&gt; versionNotes 5".<br>
    Erfolgt der Session-Aufbau mit dem DSM, stehen neben der SVS Web-API auch darüber hinausgehende API-Zugriffe zur Verfügung,
    die unter Umständen zur Verarbeitung benötigt werden. <br><br>
    
    Nach der Gerätedefinition ist die Grundeinstellung "Login in das DSM", d.h. es können Credentials mit Admin-Berechtigungen 
    genutzt werden um zunächst alle Funktionen der Kameras testen zu können. Danach können die Credentials z.B. in Abhängigkeit 
    der benötigten Funktionen auf eine SVS-Session mit entsprechend beschränkten Privilegienprofil umgestellt werden. <br><br>
    
    Die nachfolgende Aufstellung zeigt die <b>Mindestanforderungen</b> der jeweiligen Modulfunktionen an die Nutzerrechte. <br><br>
    <ul>
      <table>
      <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td><li>set ... credentials        </td><td> -                                            </li></td></tr>
      <tr><td><li>set ... delPreset          </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      <tr><td><li>set ... disable            </td><td> session: ServeillanceStation - Manager mit dem Kamera bearbeiten Recht      </li></td></tr>
      <tr><td><li>set ... enable             </td><td> session: ServeillanceStation - Manager mit dem Kamera bearbeiten Recht      </li></td></tr>
      <tr><td><li>set ... expmode            </td><td> session: ServeillanceStation - Manager       </li></td></tr>
      <tr><td><li>set ... extevent           </td><td> session: DSM - Nutzer Mitglied von Admin-Gruppe     </li></td></tr>
      <tr><td><li>set ... goPreset           </td><td> session: ServeillanceStation - Betrachter mit Privileg Objektivsteuerung der Kamera  </li></td></tr>
      <tr><td><li>set ... homeMode           </td><td> session: ServeillanceStation - Betrachter mit Privileg Home-Modus schalten ( gilt für <b>SVS-Device !</b> )  </li></td></tr>
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
    </ul>
    
<a name="HTTPTimeout"></a>
<b>HTTP-Timeout setzen</b><br><br>
    
    <ul>
    Alle Funktionen dieses Moduls verwenden HTTP-Aufrufe gegenüber der SVS Web API. <br>
    Durch Setzen des Attributes <a href="#httptimeout">httptimeout</a> &gt; 0 kann dieser Wert bei Bedarf entsprechend 
    den technischen Gegebenheiten angepasst werden. <br> 
    
  </ul>
  <br><br><br>
  
<a name="SSCamset"></a>
<b>Set </b>
<ul>
  <br>
  Die aufgeführten set-Befehle sind für CAM/SVS-Devices oder nur für CAM-Devices bzw. nur für SVS-Devices gültig. Sie stehen im 
  Drop-Down-Menü des jeweiligen Devices zur Auswahl zur Verfügung. <br><br>
  
  <ul>
  <li><b> autocreateCams </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für SVS)</li> <br>
  
  Ist ein SVS-Device definiert, können mit diesem Befehl alle in der SVS integrierten Kameras automatisiert angelegt werden. Bereits definierte 
  Kameradevices werden übersprungen. 
  Die neu erstellten Kameradevices werden im gleichen Raum wie das SVS-Device definiert (default SSCam). Weitere sinnvolle Attribute werden ebenfalls 
  voreingestellt. 
  <br><br>
  </ul>
  
  <ul>
  <a name="SSCamcreateStreamDev"></a>
  <li><b> createStreamDev [generic | hls | lastsnap | mjpeg | switched] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM) <br>
  bzw. <br>
  <b> createStreamDev [master] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für SVS) <br>
  <br>

  Es wird ein separates Streaming-Device (Typ SSCamSTRM) erstellt. Dieses Device kann z.B. als separates Device 
  in einem Dashboard genutzt werden.
  Dem Streaming-Device wird der aktuelle Raum des Kameradevice zugewiesen sofern dort gesetzt. 
  <br><br>
  
    <ul>
    <table>
    <colgroup> <col width=10%> <col width=90%> </colgroup>
      <tr><td>generic   </td><td>- das Streaming-Device gibt einen durch das Attribut <a href="#genericStrmHtmlTag">genericStrmHtmlTag</a> bestimmten Content wieder </td></tr>
      <tr><td>hls       </td><td>- das Streaming-Device gibt einen permanenten HLS Datenstrom wieder </td></tr>
      <tr><td>lastsnap  </td><td>- das Streaming-Device zeigt den neuesten Schnappschuß an </td></tr>
      <tr><td>mjpeg     </td><td>- das Streaming-Device gibt einen permanenten MJPEG Kamerastream wieder (Streamkey Methode) </td></tr>
      <tr><td>switched  </td><td>- Wiedergabe unterschiedlicher Streamtypen. Drucktasten zur Steuerung werden angeboten. </td></tr>
      <tr><td>master    </td><td>- mit dem Master Device kann ein anderes definiertes Streaming Device adoptiert und dessen Content angezeigt werden </td></tr>
    </table>
    </ul>
    <br>
  
  Die Gestaltung kann durch HTML-Tags im Attribut <a href="#htmlattr">htmlattr</a> im Kameradevice oder mit den 
  spezifischen Attributen im Streaming-Device beeinflusst werden. <br><br>
  </li> 
  
  <b>Streaming Device "hls"</b> <br><br>
  
  Das Streaming-Device vom Typ "hls" verwendet die Bibliothek hls.js zur Bildverarbeitung und ist auf allen Browsern mit
  MediaSource extensions (MSE) lauffähig. Mit dem <a href="#SSCamattr">Attribut</a> "hlsNetScript" kann bestimmt werden, ob 
  die lokal installierte hls.js (./www/pgm2/sscam_hls.js) oder immer die aktuellste Bibliotheksversion von der hls.js Projektseite 
  verwendet werden soll. Dieses Attribut ist zentral in einem Device vom Typ "SVS" zu setzen ! <br>
  Bei Verwendung dieses Streamingdevices ist zwingend das <a href="#SSCamattr">Attribut</a> "hlsStrmObject" im verbundenen 
  Kamera-Device (siehe Internal PARENT) anzugeben.
  <br><br>
  
  <b>Streaming Device "switched hls"</b> <br><br>
  
  Dieser Typ nutzt den von der Synology Surveillance Station gelieferten HLS Videostream.
  Soll ein HLS-Stream im Streaming-Device vom Typ "switched" gestartet werden, muss die Kamera in der Synology Surveillance 
  Station auf das Videoformat H.264 eingestellt und HLS von der eingesetzten SVS-Version unterstützt sein. 
  Diese Auswahltaste wird deshalb im nur dann im Streaming-Device angeboten, wenn das Reading "CamStreamFormat = HLS" beinhaltet. <br>
  HLS (HTTP Live Streaming) kann momentan nur auf Mac Safari oder mobilen iOS/Android-Geräten wiedergegeben werden. 
  <br><br>
  
  <b>Streaming Device "generic"</b> <br><br>
  
  Ein Streaming-Device vom Typ "generic" benötigt die Angabe von HTML-Tags im Attribut "genericStrmHtmlTag". Diese Tags
  spezifizieren den wiederzugebenden Content. <br><br>
  
    <ul>
      <b>Beispiele:</b>
      <pre>
attr &lt;name&gt; genericStrmHtmlTag &lt;video $HTMLATTR controls autoplay&gt;
                                 &lt;source src='http://192.168.2.10:32000/$NAME.m3u8' type='application/x-mpegURL'&gt;
                               &lt;/video&gt;

attr &lt;name&gt; genericStrmHtmlTag &lt;img $HTMLATTR 
                                 src="http://192.168.2.10:32774"
                                 onClick="FW_okDialog('&lt;img src=http://192.168.2.10:32774 $PWS &gt')"
                               &gt                              
      </pre>
      Die Variablen $HTMLATTR, $NAME und $PWS sind Platzhalter und übernehmen ein gesetztes Attribut "htmlattr", den SSCam-
      Devicenamen bzw. das Attribut "popupWindowSize" im Streaming-Device, welches die Größe eines Popup-Windows festlegt.
    </ul>
  <br><br>
  
  <b>Streaming Device "lastsnap"</b> <br><br>
  
  Dieser Typ gibt den neuesten Schnappschuß wieder. Der Schnappschuss wird per default als Icon, d.h. in einer verminderten
  Auflösung abgerufen. Um die Originalauflösung zu verwenden, ist im zugehörigen Kameradevice (Internal PARENT) das Attribut 
  <b>"snapGallerySize = Full"</b> zu setzen.  
  Dort sollte ebenfalls das Attribut "pollcaminfoall" gesetzt sein, um regelmäßig die neuesten Schnappschußdaten abzurufen.
  <br><br>
  
  <b>Streaming Device "master"</b> <br><br>
  
  Dieser Typ kann selbst keine Streams wiedergeben. Die Umschaltung der Wiedergabe des Contents eines anderen definierten 
  Streaming Devices erfolgt durch den Set-Befehl <b>adopt</b> im Master Streaming Device.
  <br>
  <br><br>
  </ul>
  
  <ul>
  <li><b> createPTZcontrol </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für PTZ-CAM)</li> <br>
  
  Es wird ein separates PTZ-Steuerungspaneel (Type SSCamSTRM) erstellt. Es wird der aktuelle Raum des Kameradevice 
  zugewiesen sofern dort gesetzt (default "SSCam").  
  Mit den "ptzPanel_.*"-<a href="#SSCamattr">Attributen</a> bzw. den spezifischen Attributen des erzeugten 
  SSCamSTRM-Devices können die Eigenschaften des PTZ-Paneels beeinflusst werden. <br> 
  <br><br>
  </ul>
  
  <ul>
  <li><b> createReadingsGroup [&lt;Name der readingsGroup&gt;]</b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM/SVS)</li> <br>
  
  Es wird ein readingsGroup-Device zur Übersicht aller vorhandenen SSCam-Devices erstellt. Es kann ein eigener Name angegeben 
  werden. Ist kein Name angegeben, wird eine readingsGroup mit dem Namen "RG.SSCam" erzeugt.
  <br> 
  <br><br>
  </ul>
    
  <ul>
  <li><b> createSnapGallery </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Es wird eine Schnappschußgallerie als separates Device (Type SSCamSTRM) erzeugt. Das Device wird im Raum 
  "SSCam" erstellt.
  Mit den "snapGallery..."-<a href="#SSCamattr">Attributen</a> bzw. den spezifischen Attributen des erzeugten SSCamSTRM-Devices 
  können die Eigenschaften der Schnappschußgallerie beeinflusst werden. 
  <br><br>

  <b>Hinweis</b> <br>
  Die Namen der Kameras in der SVS sollten sich nicht stark ähneln, da es ansonsten zu Ungenauigkeiten beim Abruf der 
  Schnappschußgallerie kommen kann.
  <br>
  
  <br><br>
  </ul>
  
  <ul>
  <li><b> credentials &lt;username&gt; &lt;password&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM/SVS)</li> <br>
  
  Setzt Username / Passwort für den Zugriff auf die Synology Surveillance Station. 
  Siehe <a href="#Credentials">Credentials</a><br>
  
  <br><br>
  </ul>
  
  <ul>
  <li><b> delPreset &lt;PresetName&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für PTZ-CAM)</li> <br>
  
  Löscht einen Preset "&lt;PresetName&gt;". Im FHEMWEB wird eine Drop-Down Liste der aktuell vorhandenen 
  Presets angeboten.

  </ul>
  <br><br>
  
  <ul>
  <a name="disable"></a>
  <li><b> disable </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM) <br>
    Deaktiviert die Kamera in der Synology Surveillance Station.
  </li>
  </ul>
  <br><br>
  
  <ul>
  <a name="enable"></a>
  <li><b> enable </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM) <br>
    Aktiviert die Kamera in der Synology Surveillance Station.
  </li>
  </ul>
  <br><br>
  
  <ul>
  <li><b> expmode [day|night|auto] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Mit diesem Befehl kann der Belichtungsmodus der Kameras gesetzt werden. Dadurch wird z.B. das Verhalten der Kamera-LED's entsprechend gesteuert. 
  Die erfolgreiche Umschaltung wird durch das Reading CamExposureMode ("get ... caminfoall") reportet. <br><br>
  
  <b> Hinweis: </b> <br>
  Die erfolgreiche Ausführung dieser Funktion ist davon abhängig ob die SVS diese Funktionalität der Kamera unterstützt. 
  Ist in SVS -&gt; IP-Kamera -&gt; Optimierung -&gt; Belichtungsmodus das Feld für den Tag/Nachtmodus grau hinterlegt, ist nicht von einer lauffähigen Unterstützung dieser 
  Funktion auszugehen. 
  <br><br>
  </ul>

  <ul>
  <li><b> extevent [ 1-10 ] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für SVS)</li> <br>
  
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
    <a name=goAbsPTZ></a>
    <li><b> goAbsPTZ [ X Y | up | down | left | right ] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM) <br>
  
    Mit diesem Kommando wird eine PTZ-Kamera in Richtung einer wählbaren absoluten X/Y-Koordinate bewegt, oder zur maximalen 
    Absolutposition in Richtung up/down/left/right. 
    Die Option ist nur für Kameras verfügbar die das Reading "CapPTZAbs=true" (die Fähigkeit für PTZAbs-Aktionen) besitzen. Die 
    Eigenschaften der Kamera kann mit "get &lt;name&gt; caminfoall" abgefragt werden.
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
    Dieser Vorgang muß ggf. mehrfach wiederholt werden um die Kameralinse in die gewünschte Position zu bringen. 
    </li>
    <br><br>

    Soll die Bewegung mit der maximalen Schrittweite erfolgen, kann zur Vereinfachung der Befehl:

    <pre>
      set &lt;name&gt; goAbsPTZ [up|down|left|right]
    </pre>

    verwendet werden. Die Optik wird in diesem Fall mit der größt möglichen Schrittweite zur Absolutposition in der angegebenen Richtung bewegt. 
    Auch in diesem Fall muß der Vorgang ggf. mehrfach wiederholt werden um die Kameralinse in die gewünschte Position zu bringen.
  </ul>
  <br><br>
  
  <ul>
  <li><b> goPreset &lt;Preset&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
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
  <li><b> homeMode [on|off] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für SVS)</li> <br>
  
  Schaltet den HomeMode der Surveillance Station ein bzw. aus. 
  Informationen zum HomeMode sind in der <a href="https://www.synology.com/de-de/knowledgebase/Surveillance/help/SurveillanceStation/home_mode">Synology Onlinehilfe</a> 
  enthalten.
  <br><br>
  </ul>
  
  <ul>
  <a name="motdetsc"></a>
  <li><b> motdetsc [camera [&lt;options&gt;] | SVS [&lt;options&gt;] | disable] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM) <br>
  
  Der Befehl schaltet die Bewegungserkennung in den gewünschten Modus. 
  Wird die Bewegungserkennung durch die Kamera / SVS ohne weitere Optionen eingestellt, werden die momentan gültigen Bewegungserkennungsparameter der 
  Kamera / SVS beibehalten. Optionen können in einem Script verwendet werden.
  </li>
  <br><br>
  
  Für die Bewegungserkennung durch SVS bzw. durch Kamera können weitere Optionen angegeben werden. 
  Die verfügbaren Optionen bezüglich der Bewegungserkennung durch SVS sind "Empfindlichkeit" und "Schwellenwert". <br><br>
  
  <ul>
  <table>
  <colgroup> <col width=50%> <col width=50%> </colgroup>
      <tr><td>set &lt;name&gt; motdetsc SVS [Empfindlichkeit] [Schwellenwert]  </td><td># Befehlsmuster  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc SVS 91 30                              </td><td># setzt die Empfindlichkeit auf 91 und den Schwellwert auf 30  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc SVS 0 40                               </td><td># behält gesetzten Wert für Empfindlichkeit bei, setzt Schwellwert auf 40  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc SVS 15                                 </td><td># setzt die Empfindlichkeit auf 15, Schwellenwert bleibt unverändert   </td></tr>
  </table>
  </ul>
  <br><br>
  
  Wird die Bewegungserkennung durch die Kamera genutzt, stehen die Optionen "Empfindlichkeit", "Objektgröße" und "Prozentsatz für Auslösung" zur Verfügung. <br><br>
  <ul>
  <table>
  <colgroup> <col width=50%> <col width=50%> </colgroup>
      <tr><td>set &lt;name&gt; motdetsc camera [Empfindlichkeit] [Objektgröße] [Prozentsatz]   </td><td># Befehlsmuster  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc camera 89 0 20                                         </td><td># setzt die Empfindlichkeit auf 89, Prozentsatz auf 20  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc camera 0 40 10                                         </td><td># behält gesetzten Wert für Empfindlichkeit bei, setzt Schwellwert auf 40, Prozentsatz auf 10  </td></tr>
      <tr><td>set &lt;name&gt; motdetsc camera 30                                              </td><td># setzt die Empfindlichkeit auf 30, andere Werte bleiben unverändert  </td></tr>
      </table>
  </ul> 
  <br><br>

  Es ist immer die Reihenfolge der Optionswerte zu beachten. Nicht gewünschte Optionen sind mit "0" zu besetzen sofern danach Optionen folgen 
  deren Werte verändert werden sollen (siehe Beispiele oben). Der Zahlenwert der Optionen beträgt 1 - 99 (außer Sonderfall "0"). <br><br>
  
  Die jeweils verfügbaren Optionen unterliegen der Funktion der Kamera und der Unterstützung durch die SVS. Es können jeweils nur die Optionen genutzt werden die in 
  SVS -&gt; Kamera bearbeiten -&gt; Ereigniserkennung zur Verfügung stehen. Weitere Infos sind der Online-Hilfe zur SVS zu entnehmen. <br><br>
  
  Über den Befehl "get &lt;name&gt; caminfoall" wird auch das <a href="#SSCamreadings">Reading</a> "CamMotDetSc" aktualisiert welches die gegenwärtige Einstellung der Bewegungserkennung dokumentiert. 
  Es werden nur die Parameter und Parameterwerte angezeigt, welche die SVS aktiv unterstützt. Die Kamera selbst kann weiterführende Einstellmöglichkeiten besitzen. <br><br>
  
  <b>Beipiel:</b>
  <pre>
  CamMotDetSc    SVS, sensitivity: 76, threshold: 55
  </pre>
  <br><br>
  </ul>
  
  <ul>
  <li><b> move [ right | up | down | left | dir_X ] [Sekunden] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM bis SVS Version 7.1)</li> 
      <b> move [ right | upright | up | upleft | left | downleft | down | downright ] [Sekunden] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM ab SVS Version 7.2) <br><br>
  
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
  <br>
  
  <ul>
  <li><b> off  </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li><br>

  Stoppt eine laufende Aufnahme. 
  </ul>
  <br><br>
  
  <ul>
  <li><b> on [&lt;rectime&gt;] <br>
                              [recEmailTxt:"subject => &lt;Betreff-Text&gt;, body => &lt;Mitteilung-Text&gt;"] <br>
                              [recTelegramTxt:"tbot => &lt;TelegramBot-Device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;Betreff-Text&gt;]"] <br>
                              [recChatTxt:"chatbot => &lt;SSChatBot-Device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;Betreff-Text&gt;]"] <br> </b>
                              &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li><br>

  Startet eine Aufnahme. Die Standardaufnahmedauer beträgt 15 Sekunden. Sie kann mit dem 
  Attribut "rectime" individuell festgelegt werden. 
  Die im Attribut (bzw. im Standard) hinterlegte Aufnahmedauer kann einmalig mit "set &lt;name&gt; on &lt;rectime&gt;" 
  überschrieben werden.
  Die Aufnahme stoppt automatisch nach Ablauf der Zeit "rectime".<br>

  Ein Sonderfall ist der Start einer Daueraufnahme mit "set &lt;name&gt; on 0" bzw. dem Attributwert "rectime = 0". 
  In diesem Fall wird eine Daueraufnahme gestartet, die explizit wieder mit dem Befehl "set &lt;name&gt; off" gestoppt 
  werden muß.<br>

  Das Aufnahmeverhalten kann weiterhin mit dem Attribut "recextend" beeinflusst werden.<br><br>

  <b>Attribut "recextend = 0" bzw. nicht gesetzt (Standard):</b><br>
  <ul>
  <li> Wird eine Aufnahme mit z.B. rectime=22 gestartet, wird kein weiterer Startbefehl für eine Aufnahme akzeptiert bis diese gestartete Aufnahme nach 22 Sekunden
  beendet ist. Ein Hinweis wird bei verbose=3 im Logfile protokolliert. </li>
  </ul>
  <br>

  <b>Attribut "recextend = 1" gesetzt:</b><br>
  <ul>
  <li> Eine zuvor gestartete Aufnahme wird bei einem erneuten "set <name> on" -Befehl um die Aufnahmezeit "rectime" verlängert. Das bedeutet, dass der Timer für 
  den automatischen Stop auf den Wert "rectime" neu gesetzt wird. Dieser Vorgang wiederholt sich mit jedem Start-Befehl. Dadurch verlängert sich eine laufende 
  Aufnahme bis kein Start-Inpuls mehr registriert wird. </li>

  <li> eine zuvor gestartete Endlos-Aufnahme wird mit einem erneuten "set <name> on"-Befehl nach der Aufnahmezeit "rectime" gestoppt (Timerneustart). Ist dies 
  nicht gewünscht, ist darauf zu achten dass bei der Verwendung einer Endlos-Aufnahme das Attribut "recextend" nicht verwendet wird. </li>
  </ul>
  <br>
  
  Ein <b>Synology Chat Versand</b> der Aufnahme kann durch Setzen des <a href="#SSCamattr">recChatTxt</a> Attributs permanent aktiviert
  werden. Das zu verwendende <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers">SSChatBot-Device</a> muss natürlich 
  funktionstüchtig eingerichtet sein. <br>
  Der Text im Attribut "recChatTxt" kann durch die Spezifikation des optionalen "recChatTxt:"-Tags, wie oben 
  gezeigt, temporär überschrieben bzw. geändert werden. Sollte das Attribut "recChatTxt" nicht gesetzt sein, wird durch Angabe dieses Tags
  der Versand mit Synology Chat einmalig aktiviert. (die Tag-Syntax entspricht dem "recChatTxt"-Attribut) <br><br>
  
  Ein <b>Email-Versand</b> der letzten Aufnahme kann durch Setzen des <a href="#SSCamattr">Attributs</a> "recEmailTxt" 
  aktiviert werden. Zuvor ist der Email-Versand, wie im Abschnitt <a href="#SSCamEmail">Einstellung Email-Versand</a> beschrieben,
  einzustellen. (Für weitere Informationen "<b>get &lt;name&gt; versionNotes 7</b>" ausführen) <br>
  Alternativ kann durch Verwendung des optionalen "recEmailTxt:"-Tags der Email-Versand der gestarteten Aufnahme nach deren
  Beendigung aktiviert werden. Sollte das Attribut "recEmailTxt" bereits gesetzt sein, wird der Text des "recEmailTxt:"-Tags  
  anstatt des Attribut-Textes verwendet. <br><br>
  
  Ein <b>Telegram-Versand</b> der letzten Aufnahme kann durch Setzen des <a href="#SSCamattr">Attributs</a> "recTelegramTxt" permanent aktiviert
  werden. Das zu verwendende <a href="http://fhem.de/commandref_DE.html#TelegramBot">TelegramBot-Device</a> muss natürlich 
  funktionstüchtig eingerichtet sein. <br>
  Der Text im Attribut "recTelegramTxt" kann durch die Spezifikation des optionalen "recTelegramTxt:"-Tags, wie oben 
  gezeigt, temporär überschrieben bzw. geändert werden. Sollte das Attribut "recTelegramTxt" nicht gesetzt sein, wird durch Angabe dieses Tags
  der Telegram-Versand einmalig aktiviert. (die Tag-Syntax entspricht dem "recTelegramTxt"-Attribut) <br><br>
  
  <b>Beispiele </b>: <br>
  <code> set &lt;name&gt; on [rectime] </code><br>
  # startet die Aufnahme der Kamera &lt;name&gt;, automatischer Stop der Aufnahme nach Ablauf der Zeit [rectime] 
  (default 15s oder wie im <a href="#SSCamattr">Attribut</a> "rectime" angegeben) <br>
  <code> set &lt;name&gt; on 0  </code><br>
  # startet eine Daueraufnahme die mit "off" gestoppt werden muss. <br>
  <code> set &lt;name&gt; on recEmailTxt:"subject => Neue Aufnahme $CAM, body => Die aktuelle Aufnahme von $CAM ist angehängt."  </code><br>
  # startet eine Aufnahme und versendet sie nach Beendigung per Email. <br>
  <code> set &lt;name&gt; on recTelegramTxt:"tbot => teleBot, peers => @xxxx , subject => Bewegungsalarm bei $CAM. Es wurde $CTIME die Aufnahme $FILE erstellt"  </code><br>
  # startet eine Aufnahme und versendet sie nach Beendigung per Telegram. <br>
  <code> set &lt;name&gt; on recChatTxt:"chatbot => SynChatBot, peers => , subject => Bewegungsalarm bei $CAM. Es wurde $CTIME die Aufnahme $FILE erstellt. Jetzt ist es $TIME."  </code><br>
  # startet eine Aufnahme und versendet sie nach Beendigung per Synology Chat. <br>

  </ul>
  <br><br>
  
  <ul>
  <li><b> optimizeParams [mirror:&lt;value&gt;] [flip:&lt;value&gt;] [rotate:&lt;value&gt;] [ntp:&lt;value&gt;]</b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
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
  <li><b> pirSensor [activate | deactivate] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Aktiviert / deaktiviert den Infrarot-Sensor der Kamera (sofern die Kamera einen PIR-Sensor enthält).  
  </ul>
  <br><br>
  
  <ul>
  <li><b> runPatrol &lt;Patrolname&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
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
  <li><b> runView [live_fw | live_fw_hls | live_link | live_open [&lt;room&gt;] | lastrec_fw | lastrec_fw_MJPEG | lastrec_fw_MPEG4/H.264 | lastrec_open [&lt;room&gt;] | lastsnap_fw]  </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
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
  das Videoformat H.264 (nicht MJPEG) eingestellt und HLS durch die eingesetzte SVS-Version unterstützt sein. 
  Diese Möglichkeit wird deshalb nur dann angeboten wenn das Reading "CamStreamFormat" den Wert "HLS" hat.
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
  
  Abhängig vom wiedergegebenen Content werden unterschiedliche Steuertasten angeboten: <br><br>
  <ul>   
    <table>  
    <colgroup> <col width=25%> <col width=75%> </colgroup>
      <tr><td> Start Recording </td><td>- startet eine Endlosaufnahme </td></tr>
      <tr><td> Stop Recording  </td><td>- stoppt eine Aufnahme </td></tr>
      <tr><td> Take Snapshot   </td><td>- löst einen Schnappschuß aus </td></tr>
      <tr><td> Switch off      </td><td>- stoppt eine laufende Wiedergabe </td></tr>
    </table>
   </ul>     
   <br>
  
  <b>Hinweis zu HLS (HTTP Live Streaming):</b> <br>
  Das Video startet mit einer technologisch bedingten Verzögerung. Jeder Stream wird in eine Reihe sehr kleiner Videodateien 
  (mit etwa 10 Sekunden Länge) segmentiert und an den Client ausgeliefert. 
  Die Kamera muss in der SVS auf das Videoformat H.264 eingestellt sein und nicht jeder Kameratyp ist gleichermassen für 
  HLS-Streaming geeignet.
  Momentan kann HLS nur durch den Mac Safari Browser sowie auf mobilen iOS/Android-Geräten wiedergegeben werden.
  <br><br>
  
  <b>Hinweis zu MJPEG:</b> <br>
  Der MJPEG Stream wird innerhalb der SVS aus anderen Codecs (H.264) transkodiert und beträgt normalerweise ca. 1 Fps.
    
  </ul>
  <br><br>
  
  
  <ul>
  <li><b> setHome &lt;PresetName&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für PTZ-CAM)</li> <br>
  
  Setzt die Home-Position der Kamera auf einen vordefinierten Preset "&lt;PresetName&gt;" oder auf die aktuell angefahrene 
  Position.

  </ul>
  <br><br>
  
  <ul>
  <li><b> setPreset &lt;PresetNummer&gt; [&lt;PresetName&gt;] [&lt;Speed&gt;] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für PTZ-CAM)</li> <br>
  
  Setzt einen Preset mit dem Namen "&lt;PresetName&gt;" auf die aktuell angefahrene Position der Kamera. Optional kann die
  Geschwindigkeit angegeben werden (&lt;Speed&gt;). Ist kein PresetName angegeben, wird die PresetNummer als Name verwendet.
  Aus diesem Grund ist &lt;PresetName&gt; optional definiert, sollte jedoch im Normalfall gesetzt werden.

  </ul>
  <br><br>
  
  <ul>
  <li><b> setZoom &lt; .++ | + | stop | - | --. &gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für PTZ-CAM)</li> <br>
  
  Stellt Bedienelemte für Zoomfunktionen zur Verfügung sofern die Kamera dieses Merkmal unterstützt.

  </ul>
  <br><br>
  
  <ul>
  <li><b> smtpcredentials &lt;user&gt; &lt;password&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Setzt die Credentials für den Zugang zum Postausgangsserver wenn Email-Versand genutzt wird.

  </ul>
  <br><br>
  
  <ul>
  <li><b> snap [&lt;Anzahl&gt;] [&lt;Zeitabstand&gt;] <br>
                                [snapEmailTxt:"subject => &lt;Betreff-Text&gt;, body => &lt;Mitteilung-Text&gt;"] <br>
                                [snapTelegramTxt:"tbot => &lt;TelegramBot-Device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;Betreff-Text&gt;]"] <br>
                                [snapChatTxt:"chatbot => &lt;SSChatBot-Device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;Betreff-Text&gt;]"]    <br>
                                </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Ein oder mehrere Schnappschüsse werden ausgelöst. Es kann die Anzahl der auszulösenden Schnappschüsse und deren zeitlicher
  Abstand in Sekunden optional angegeben werden. Ohne Angabe wird ein Schnappschuß getriggert. <br>
  Es wird die ID und der Filename des letzten Snapshots als Wert der Readings "LastSnapId" bzw. "LastSnapFilename" in  
  der Kamera gespeichert. <br>
  Um die Daten der letzen 1-10 Schnappschüsse zu versionieren, kann das <a href="#SSCamattr">Attribut</a> "snapReadingRotate"
  verwendet werden.
  <br><br>
  
  Ein <b>Synology Chat Versand</b> der Schnappschüsse kann durch Setzen des Attributs <a href="#snapChatTxt">snapChatTxt</a> permanent aktiviert
  werden. Das zu verwendende <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers">SSChatBot-Device</a> muss natürlich 
  funktionstüchtig eingerichtet sein. <br>
  Der Text im Attribut "snapChatTxt" kann durch die Spezifikation des optionalen "snapChatTxt:"-Tags, wie oben 
  gezeigt, temporär überschrieben bzw. geändert werden. Sollte das Attribut "snapChatTxt" nicht gesetzt sein, wird durch Angabe dieses Tags
  der SSChatBot-Versand einmalig aktiviert (die Syntax entspricht dem "snapChatTxt"-Attribut). <br>
  In jedem Fall ist vorher das Attribut <a href="#videofolderMap">videofolderMap</a> zu setzen. Es muß eine URL zum 
  root-Verzeichnis der Aufnahmen und Schnappschüssen enthalten ( z.B. http://server.mein:8081/surveillance ).  <br><br>
  
  Ein <b>Email-Versand</b> der Schnappschüsse kann durch Setzen des Attributs <a href="#snapEmailTxt">snapEmailTxt</a> permanent aktiviert
  werden. Zuvor ist der Email-Versand, wie im Abschnitt <a href="#SSCamEmail">Einstellung Email-Versand</a> beschrieben,
  einzustellen. (Für weitere Informationen "<b>get &lt;name&gt; versionNotes 7</b>" ausführen) <br>
  Der Text im Attribut "snapEmailTxt" kann durch die Spezifikation des optionalen "snapEmailTxt:"-Tags, wie oben 
  gezeigt, temporär überschrieben bzw. geändert werden. Sollte das Attribut "snapEmailTxt" nicht gesetzt sein, wird durch Angabe dieses Tags
  der Email-Versand einmalig aktiviert. (die Tag-Syntax entspricht dem "snapEmailTxt"-Attribut) <br><br>
  
  Ein <b>Telegram-Versand</b> der Schnappschüsse kann durch Setzen des Attributs <a href="#snapTelegramTxt">snapTelegramTxt</a> permanent aktiviert
  werden. Das zu verwendende <a href="http://fhem.de/commandref_DE.html#TelegramBot">TelegramBot-Device</a> muss natürlich 
  funktionstüchtig eingerichtet sein. <br>
  Der Text im Attribut "snapTelegramTxt" kann durch die Spezifikation des optionalen "snapTelegramTxt:"-Tags, wie oben 
  gezeigt, temporär überschrieben bzw. geändert werden. Sollte das Attribut "snapTelegramTxt" nicht gesetzt sein, wird durch Angabe dieses Tags
  der Telegram-Versand einmalig aktiviert. (die Tag-Syntax entspricht dem "snapTelegramTxt"-Attribut) <br><br>
  
  <b>Beispiele:</b>
  <pre>
    set &lt;name&gt; snap
    set &lt;name&gt; snap 4 
    set &lt;name&gt; snap 3 3 snapEmailTxt:"subject => Bewegungsalarm $CAM, body => Eine Bewegung wurde am Carport registriert"
    set &lt;name&gt; snap 2 snapTelegramTxt:"tbot => teleBot, peers => , subject => Bewegungsalarm bei $CAM. Es wurde $CTIME der Schnappschuss $FILE erstellt"
    set &lt;name&gt; snap 2 snapChatTxt:"chatbot => SynChatBot , peers => Frodo Sam, subject => Bewegungsalarm bei $CAM. Es wurde $CTIME der Schnappschuss $FILE erstellt. Jetzt ist es: $TIME."
  </pre>
  </ul>
  <br><br>
  
  <ul>
  <li><b> snapCams [&lt;Anzahl&gt;] [&lt;Zeitabstand&gt;] [CAM:"&lt;Kamera&gt;, &lt;Kamera&gt, ..."]</b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für SVS)</li> <br>
  
  Ein oder mehrere Schnappschüsse der angegebenen Kamera-Devices werden ausgelöst. Sind keine Kamera-Devices angegeben, 
  werden die Schnappschüsse bei allen in FHEM definierten Kamera-Devices getriggert.  
  Optional kann die Anzahl der auszulösenden Schnappschüsse (default: 1) und deren zeitlicher Abstand in Sekunden
  (default: 2) angegeben werden. <br>
  Es wird die ID und der Filename des letzten Snapshots als Wert der Readings "LastSnapId" bzw. "LastSnapFilename"  
  der entsprechenden Kamera gespeichert. <br><br>
  Ein <b>Email-Versand</b> der Schnappschüsse kann durch Setzen des <a href="#SSCamattr">Attributs</a> <b>"snapEmailTxt"</b> im 
  SVS-Device <b>UND</b> in den Kamera-Devices, deren Schnappschüsse versendet werden sollen, aktiviert werden. 
  Bei Kamera-Devices die kein Attribut "snapEmailTxt" gesetzt haben, werden die Schnappschüsse ausgelöst, aber nicht versendet.
  Zuvor ist der Email-Versand, wie im Abschnitt <a href="#SSCamEmail">Einstellung Email-Versand</a> beschrieben,
  einzustellen. (Für weitere Informationen "<b>get &lt;name&gt; versionNotes 7</b>" ausführen) <br>
  Es wird ausschließlich der im Attribut "snapEmailTxt" des SVS-Devices hinterlegte Email-Text in der erstellten Email 
  verwendet. Der Text im Attribut "snapEmailTxt" der einzelnen Kameras wird ignoriert !! <br><br>
  
  <b>Beispiele:</b>
  <pre>
    set &lt;name&gt; snapCams 4 
    set &lt;name&gt; snapCams 3 3 CAM:"CamHE1, CamCarport"
  </pre>
  
  </ul>
  <br><br>
  
  <ul>
  <li><b> snapGallery [1-10] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Der Befehl ist nur vorhanden wenn das Attribut "snapGalleryBoost=1" gesetzt wurde.
  Er erzeugt eine Ausgabe der letzten [x] Schnappschüsse ebenso wie <a href="#SSCamget">"get &lt;name&gt; snapGallery"</a>.  Abweichend von "get" wird mit Attribut
  <a href="#SSCamattr">Attribut</a> "snapGalleryBoost=1" kein Popup erzeugt, sondern die Schnappschußgalerie als Browserseite
  dargestellt. Alle weiteren Funktionen und Attribute entsprechen dem "get &lt;name&gt; snapGallery" Kommando. <br>
  Wenn die Ausgabe einer Schnappschußgalerie, z.B. über ein "at oder "notify", getriggert wird, sollte besser das  
  <a href="#SSCamget">"get &lt;name&gt; snapGallery"</a> Kommando anstatt "set" verwendet werden.
  <br><br>
  
  <b>Hinweis</b> <br>
  Die Namen der Kameras in der SVS sollten sich nicht stark ähneln, da es ansonsten zu Ungenauigkeiten beim Abruf der 
  Schnappschußgallerie kommen kann.
  
  </ul>
  <br><br>
  
  <ul>
  <li><b> startTracking </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM mit Tracking Fähigkeit)</li> <br>
  
  Startet Objekt Tracking der Kamera.
  Der Befehl ist nur vorhanden wenn die Surveillance Station die Fähigkeit der Kamera zum Objekt Tracking erkannt hat
  (Reading "CapPTZObjTracking").
  </ul>
  <br><br>
  
  <ul>
  <li><b> stopTracking </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM mit Tracking Fähigkeit)</li> <br>
  
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
  <a name="apiInfo"></a>
  <li><b> apiInfo </b> <br>
  
  Ruft die API Informationen der Synology Surveillance Station ab und öffnet ein Popup mit diesen Informationen.
  <br>
  </li><br>
  </ul>
  
  <ul>
  <li><b>  caminfoall </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM/SVS)</li>
      <b>  caminfo </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM) <br><br>
  
  Es werden SVS-Parameter und abhängig von der Art der Kamera (z.B. Fix- oder PTZ-Kamera) die verfügbaren Kamera-Eigenschaften 
  ermittelt und als Readings zur Verfügung gestellt. <br>
  So wird zum Beispiel das Reading "Availability" auf "disconnected" gesetzt falls die Kamera von der Surveillance Station 
  getrennt ist. <br>
  "getcaminfo" ruft eine Teilmenge von "getcaminfoall" ab.
  </ul>
  <br><br> 
  
  <ul>
  <li><b>  eventlist </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
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
  <li><b>  homeModeState </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für SVS)</li> <br>
  
  HomeMode-Status der Surveillance Station wird abgerufen.  
  </ul>
  <br><br> 
  
  <ul>
    <a name="listLog"></a>
    <li><b>  listLog [severity:&lt;Loglevel&gt;] [limit:&lt;Zeilenzahl&gt;] [match:&lt;Suchstring&gt;] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für SVS) <br>
  
    Ruft das Surveillance Station Log vom Synology Server ab. Ohne Angabe der optionalen Zusätze wird das gesamte Log abgerufen. <br>
    Es können alle oder eine Auswahl der folgenden Optionen angegeben werden: <br><br>
      
    <ul>
      <li> &lt;Loglevel&gt; - Information, Warning oder Error. Nur Sätze mit dem Schweregrad werden abgerufen (default: alle) </li>
      <li> &lt;Zeilenzahl&gt; - die angegebene Anzahl der Logzeilen (neueste) wird abgerufen (default: alle) </li>
      <li> &lt;Suchstring&gt; - nur Logeinträge mit dem angegeben String werden abgerufen (Achtung: kein Regex, der Suchstring wird im Call an die SVS mitgegeben) </li>
    </ul>
    <br>
    </li>
  
    <b>Beispiele</b> <br>
    <ul>
      <code>get &lt;name&gt; listLog severity:Error limit:5 </code> <br>
      Zeigt die letzten 5 Logeinträge mit dem Schweregrad "Error" <br>  
      <code>get &lt;name&gt; listLog severity:Information match:Carport </code> <br>
      Zeigt alle Logeinträge mit dem Schweregrad "Information" die den String "Carport" enthalten <br>  
      <code>get &lt;name&gt; listLog severity:Warning </code> <br>
      Zeigt alle Logeinträge mit dem Schweregrad "Warning" <br><br>
    </ul>
  
  
    Wurde mit dem Attribut <a href="#pollcaminfoall">pollcaminfoall</a> das Polling der SVS aktiviert, wird das <a href="#SSCamreadings">Reading</a> 
    "LastLogEntry" erstellt. <br>
    Im Protokoll-Setup der SVS kann man einstellen was protokolliert werden soll. Für weitere Informationen 
    siehe <a href="https://www.synology.com/de-de/knowledgebase/Surveillance/help/SurveillanceStation/log_advanced">Synology Online-Hlfe</a>.
  </ul>
  <br><br> 
  
  <ul>
  <li><b>  listPresets </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für PTZ-CAM)</li> <br>
  
  Die für die Kamera gespeicherten Presets werden in einem Popup ausgegeben.
  </ul>
  <br><br> 
  
  <ul>
  <li><b>  saveLastSnap [&lt;Pfad&gt;] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Der aktuell im Reading "LastSnapId" angegebene (letzte) Schnappschuß wird lokal als jpg-File gespeichert. 
  Optional kann der Pfad zur Speicherung des Files im Befehl angegeben werden (default: modpath im global Device). <br>
  Das File erhält lokal den gleichen Namen wie im Reading "LastSnapFilename" enthalten. <br>
  Die Auflösung des Schnappschusses wird durch das Attribut "snapGallerySize" bestimmt.
  
  <br><br>
  
  <ul>
    <b>Beispiel:</b> <br><br>
    get &lt;name&gt; saveLastSnap /opt/fhem/log
  </ul>
  
  </ul>
  <br><br> 
  
  <ul>
  <li><b>  saveRecording [&lt;Pfad&gt;] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Die aktuell im Reading "CamLastRec" angegebene Aufnahme wird lokal als MP4-File gespeichert. Optional kann der Pfad zur 
  Speicherung des Files im Befehl angegeben werden (default: modpath im global Device). <br>
  Das File erhält lokal den gleichen Namen wie im Reading "CamLastRec" angegeben. <br><br>
  
  <ul>
    <b>Beispiel:</b> <br><br>
    get &lt;name&gt; saveRecording /opt/fhem/log
  </ul>
  
  </ul>
  <br><br>

  <ul>
  <li><b>  scanVirgin </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM/SVS)</li> <br>
  
  Wie mit get caminfoall werden alle Informationen der SVS und Kamera abgerufen. Allerdings wird in jedem Fall eine 
  neue Session ID generiert (neues Login), die Kamera-ID neu ermittelt und es werden alle notwendigen API-Parameter neu 
  eingelesen.  
  </ul>
  <br><br> 
  
  <ul>
  <li><b>  snapGallery [1-10] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
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
        RAM-Ressourcen benötigt. Die Namen der Kameras in der SVS sollten sich nicht stark ähneln, da es ansonsten zu 
        Ungnauigkeiten beim Abruf der Schnappschußgallerie kommen kann.
        </ul>
        <br><br>
  
  <ul>
  <li><b>  snapfileinfo </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Es wird der Filename des letzten Schnapschusses ermittelt. Der Befehl wird implizit mit <b>"get &lt;name&gt; snap"</b> 
  ausgeführt.
  </ul>
  <br><br> 
  
  <ul>
  <li><b>  snapinfo </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Es werden Schnappschussinformationen gelesen. Hilfreich wenn Schnappschüsse nicht durch SSCam, sondern durch die Bewegungserkennung der Kamera 
  oder Surveillance Station erzeugt werden.
  </ul>
  <br><br> 
  
  <ul>
  <li><b>  stmUrlPath </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
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
  <li><b>  storedCredentials </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM/SVS)</li> <br>
  
  Die gespeicherten Anmeldeinformationen (Credentials) werden in einem Popup als Klartext angezeigt.
  </ul>
  <br><br> 
  
  <ul>
  <li><b>  svsinfo </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM/SVS)</li> <br>
  
  Ermittelt allgemeine Informationen zur installierten SVS-Version und andere Eigenschaften. <br>
  </ul>
  <br><br> 
  
  <ul>
  <li><b>  versionNotes [hints | rel | &lt;key&gt;] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM/SVS)</li> <br>
  
  Zeigt Release Informationen und/oder Hinweise zum Modul an. Es sind nur Release Informationen mit Bedeutung für den 
  Modulnutzer enthalten. <br>
  Sind keine Optionen angegben, werden sowohl Release Informationen als auch Hinweise angezeigt. "rel" zeigt nur Release
  Informationen und "hints" nur Hinweise an. Mit der &lt;key&gt;-Angabe wird der Hinweis mit der angegebenen Nummer 
  angezeigt.
  Ist das Attribut "language = DE" im global Device gesetzt, erfolgt die Ausgabe der Hinweise in deutscher Sprache.
  </ul>
  <br><br> 
  
  </ul>
  <br><br>
  
  <a name="SSCamEmail"></a>
  <b>Einstellung Email-Versand </b> <br><br>
  <ul>
  Schnappschüsse und Aufnahmen können nach der Erstellung per <b>Email</b> versendet werden. Dazu enthält das 
  Modul einen eigenen Email-Client. 
  Zur Verwendung dieser Funktion muss das Perl-Modul <b>MIME::Lite</b> installiert sein. Auf Debian-Systemen kann 
  es mit <br><br>
   
   <ul>
    sudo apt-get install libmime-lite-perl
   </ul>
   <br>
   
  installiert werden. <br><br>
  
  Für die Verwendung des Email-Versands müssen einige Attribute gesetzt oder können optional genutzt werden. <br>
  Die Credentials für den Zugang zum Email-Server müssen mit dem Befehl <b>"set &lt;name&gt; smtpcredentials &lt;user&gt; &lt;password&gt;"</b>
  hinterlegt werden. Der Verbindungsaufbau zum Postausgangsserver erfolgt initial unverschüsselt und wechselt zu einer verschlüsselten
  Verbindung wenn SSL zur Verfügung steht. In diesem Fall erfolgt auch die Übermittlung von User/Password verschlüsselt.
  Ist das Attribut <a href="#smtpSSLPort">smtpSSLPort</a> definiert, erfolgt der Verbindungsaufbau zum Email-Server sofort verschlüsselt. 
  <br><br>
  
  Optionale Attribute sind gekennzeichnet: <br><br>
  
  <ul>   
    <table>  
    <colgroup> <col width=12%> <col width=88%> </colgroup>
      <tr><td> <b>snapEmailTxt</b>                       </td><td>- <b>Aktiviert den Email-Versand von Schnappschüssen</b>. 
                                                                  Das Attribut hat das Format: <br>
                                                                  <ul>
                                                                  <code>subject => &lt;Betreff-Text&gt;, body => &lt;Mitteilung-Text&gt;</code><br>
                                                                  </ul>
                                                                  Es können die Platzhalter $CAM, $DATE und $TIME verwendet werden. <br>
                                                                  Der Email-Versand des letzten Schnappschusses wird einmalig aktiviert falls der "snapEmailTxt:"-Tag 
                                                                  beim "snap"-Kommando verwendet wird bzw. der in diesem Tag definierte Text statt des Textes im 
                                                                  Attribut "snapEmailTxt" verwendet. </td></tr>
      <tr><td> </td><td> </td></tr>
      <tr><td> </td><td> </td></tr>
      <tr><td> <b>recEmailTxt</b>                        </td><td>- <b>Aktiviert den Email-Versand von Aufnahmen</b>. 
                                                                  Das Attribut hat das Format: <br>
                                                                  <ul>
                                                                  <code>subject => &lt;Betreff-Text&gt;, body => &lt;Mitteilung-Text&gt;</code><br>
                                                                  </ul>
                                                                  Es können die Platzhalter $CAM, $DATE und $TIME verwendet werden. <br>
                                                                  Der Email-Versand der letzten Aufnahme wird einamlig aktiviert falls der "recEmailTxt:"-Tag beim 
                                                                  "on"-Kommando verwendet wird bzw. der in diesem Tag definierte Text statt des Textes im 
                                                                  Attribut "recEmailTxt" verwendet. </td></tr>
      <tr><td> </td><td> </td></tr>
      <tr><td> </td><td> </td></tr>   
      <tr><td>                            <b>smtpHost</b>     </td><td>- Hostname oder IP-Adresse des Postausgangsservers (z.B. securesmtp.t-online.de) </td></tr>
      <tr><td>                            <b>smtpFrom</b>     </td><td>- Absenderadresse (&lt;name&gt@&lt;domain&gt) </td></tr>
      <tr><td>                            <b>smtpTo</b>       </td><td>- Empfängeradresse(n) (&lt;name&gt@&lt;domain&gt) </td></tr>
      <tr><td>                            <b>smtpPort</b>     </td><td>- (optional) Port des Postausgangsservers (default: 25) </td></tr>
      <tr><td>                            <b>smtpCc</b>       </td><td>- (optional) Carbon-Copy Empfängeradresse(n) (&lt;name&gt@&lt;domain&gt) </td></tr>
      <tr><td>                            <b>smtpNoUseSSL</b> </td><td>- (optional) "1" wenn kein SSL beim Email-Versand verwendet werden soll (default: 0) </td></tr>
      <tr><td>                            <b>smtpSSLPort</b>  </td><td>- (optional) SSL-Port des Postausgangsservers (default: 465) </td></tr>
      <tr><td>                            <b>smtpDebug</b>    </td><td>- (optional) zum Debugging der SMTP-Verbindung setzen </td></tr>
    </table>
   </ul>     
   <br>
   
   Zur näheren Erläuterung siehe Beschreibung der <a href="#SSCamattr">Attribute</a>. <br><br>

   Erläuterung der Platzhalter: <br><br>
    
   <ul>   
   <table>  
   <colgroup> <col width=10%> <col width=90%> </colgroup>
     <tr><td> $CAM   </td><td>- Device-Alias bzw. den Namen der Kamera in der SVS ersetzt falls der Device-Alias nicht vorhanden ist </td></tr>
     <tr><td> $DATE  </td><td>- aktuelles Datum </td></tr>
     <tr><td> $TIME  </td><td>- aktuelle Zeit </td></tr>
     <tr><td> $FILE  </td><td>- Filename des Schnappschusses </td></tr>
     <tr><td> $CTIME </td><td>- Erstellungszeit des Schnappschusses </td></tr>
   </table>
   </ul>     
   <br>
  </ul>   
  <br><br>
  
  <a name="SSCamPolling"></a>
  <b>Polling der Kamera/SVS-Eigenschaften:</b><br><br>
  <ul>
  Die Abfrage der Kameraeigenschaften erfolgt automatisch, wenn das Attribut <a href="#pollcaminfoall">pollcaminfoall</a> mit einem Wert &gt; 10 gesetzt wird. <br>
  Per Default ist das Attribut <a href="#pollcaminfoall">pollcaminfoall</a> nicht gesetzt und das automatische Polling nicht aktiv. <br>
  Der Wert dieses Attributes legt das Intervall der Abfrage in Sekunden fest. Ist das Attribut nicht gesetzt oder &lt; 10 wird kein automatisches Polling <br>
  gestartet bzw. gestoppt wenn vorher der Wert &gt; 10 gesetzt war. <br><br>

  Das Attribut <a href="#pollcaminfoall">pollcaminfoall</a> wird durch einen Watchdog-Timer überwacht. Änderungen des Attributwertes werden alle 90 Sekunden ausgewertet und entsprechend umgesetzt. <br>
  Eine Änderung des Pollingstatus / Pollingintervalls wird im FHEM-Logfile protokolliert. Diese Protokollierung kann durch Setzen des Attributes <a href="#pollnologging">pollnologging=1</a> abgeschaltet werden.<br>
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
  Bei einem eingestellten HTTP-Timeout (siehe <a href="#httptimeout">httptimeout</a>) von 4 Sekunden kann die theoretische Verarbeitungszeit nicht höher als 80 Sekunden betragen. <br>
  In dem Beispiel sollte man das Pollingintervall mit einem Sicherheitszuschlag auf nicht weniger 160 Sekunden setzen. <br>
  Ein praktikabler Richtwert könnte zwischen 600 - 1800 (s) liegen. <br>

  Sind mehrere Kameras in SSCam definiert, sollte "pollcaminfoall" nicht bei allen Kameras auf exakt den gleichen Wert gesetzt werden um Verarbeitungsengpässe <br>
  und dadurch versursachte potentielle Fehlerquellen bei der Abfrage der Synology Surveillance Station zu vermeiden. <br>
  Ein geringfügiger Unterschied zwischen den Pollingintervallen der definierten Kameras von z.B. 1s kann bereits als ausreichend angesehen werden. 
  </ul>
  <br><br> 

<a name="SSCaminternals"></a>
<b>Internals</b> <br><br>
 <ul>
 Die Bedeutung der verwendeten Internals stellt die nachfolgende Liste dar: <br><br>
  <ul>
  <li><b>CAMID</b> - die ID der Kamera in der SVS, der Wert wird automatisch anhand des SVS-Kameranamens ermittelt. </li>
  <li><b>CAMNAME</b> - der Name der Kamera in der SVS </li>
  <li><b>COMPATIBILITY</b> - Information bis zu welcher SVS-Version das Modul kompatibel bzw. zur Zeit getestet ist (siehe Reading "compstate")</li>
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
  
  <a name="cacheServerParam"></a>
  <li><b>cacheServerParam</b><br> 
    Angabe der Verbindungsparameter zu einem zentralen Datencache. <br><br>

    <table>  
    <colgroup> <col width=10%> <col width=90%> </colgroup>
     <tr><td> <b>redis    </b> </td><td>: bei Netzwerkverbindung: &lt;IP-Adresse&gt;:&lt;Port&gt; / bei Unix-Socket: &lt;unix&gt;:&lt;/path/zum/socket&gt; </td></tr>
    </table>
    
    <br>
  </li><br> 
  
  <a name="cacheType"></a>
  <li><b>cacheType</b><br> 
    Legt den zu verwendenden Cache für die Speicherung von Schnappschüssen, Aufnahmen und anderen Massendaten fest. 
    (Default: internal). <br>
    Es müssen eventuell weitere Module installiert werden, z.B. mit Hilfe des <a href="http://fhem.de/commandref.html#Installer">FHEM Installers</a>. <br>
    Die Daten werden in "Namespaces" gespeichert um die Nutzung zentraler Caches (redis) zu ermöglichen. <br>
    Die Cache Typen "file" und "redis" bieten sich an, wenn die Daten nicht im RAM des FHEM-Servers gehalten werden sollen. 
    Für die Verwendung von Redis ist zunächst ein Redis Key-Value Store bereitzustellen, z.B. in einem Docker-Image auf
    der Synology Diskstation (<a href="https://hub.docker.com/_/redis">redis</a>). <br><br>

    <table>  
    <colgroup> <col width=10%> <col width=90%> </colgroup>
     <tr><td> <b>internal </b> </td><td>: verwendet modulinterne Speicherung (Default) </td></tr>
     <tr><td> <b>mem      </b> </td><td>: sehr schneller Cache, kopiert Daten in den RAM </td></tr>
     <tr><td> <b>rawmem   </b> </td><td>: schnellster Cache bei komplexen Daten, speichert Referenzen im RAM </td></tr>
     <tr><td> <b>file     </b> </td><td>: erstellt und verwendet eine Verzeichnisstruktur im Directory "FhemUtils" </td></tr>
     <tr><td> <b>redis    </b> </td><td>: Verwendet einen externen Redis Key-Value Store per TCP oder Unix-Socket. Siehe dazu Attribut "cacheServerParam". </td></tr>
    </table>
    
    <br>
  </li><br> 
  
  <a name="debugactivetoken"></a>
  <li><b>debugactivetoken</b><br> 
    Wenn gesetzt, wird der Status des Active-Tokens gelogged - nur für Debugging, nicht im 
    normalen Betrieb benutzen ! 
  </li><br>
  
  <a name="debugCachetime"></a>
  <li><b>debugCachetime</b><br> 
    Zeigt die verbrauchte Zeit für Cache-Operationen an. 
  </li><br>
  
  <a name="disable"></a>
  <li><b>disable</b><br>
    deaktiviert das Gerätemodul bzw. die Gerätedefinition </li><br>
  
  <a name="genericStrmHtmlTag"></a>  
  <li><b>genericStrmHtmlTag</b><br>
  Das Attribut enthält HTML-Tags zur Video-Spezifikation in einem Streaming-Device von Typ "generic". 
  (siehe "set &lt;name&gt; createStreamDev generic") <br><br> 
  
    <ul>
      <b>Beispiele:</b>
      <pre>
attr &lt;name&gt; genericStrmHtmlTag &lt;video $HTMLATTR controls autoplay&gt;
                                 &lt;source src='http://192.168.2.10:32000/$NAME.m3u8' type='application/x-mpegURL'&gt;
                               &lt;/video&gt;
                               
attr &lt;name&gt; genericStrmHtmlTag &lt;img $HTMLATTR 
                                 src="http://192.168.2.10:32774"
                                 onClick="FW_okDialog('&lt;img src=http://192.168.2.10:32774 $PWS &gt')"
                               &gt                              
      </pre>
      Die Variablen $HTMLATTR, $NAME und $PWS sind Platzhalter und übernehmen ein gesetztes Attribut "htmlattr", den SSCam-
      Devicenamen bzw. das Attribut "popupWindowSize" im Streaming-Device, welches die Größe eines Popup-Windows festlegt.    
    </ul>
    <br><br>
    </li>
  
  <a name="httptimeout"></a>
  <li><b>httptimeout</b><br>
    Timeout-Wert für HTTP-Aufrufe zur Synology Surveillance Station. <br> 
    (default: 20 Sekunden) </li><br>
    
  <a name="hlsNetScript"></a>
  <li><b>hlsNetScript</b> &nbsp;&nbsp;&nbsp;&nbsp;(setzbar in Device Model "SVS") <br>
    Wenn gesetzt, wird die aktuellste hls.js Version von der Projektseite verwendet (Internetverbindung nötig). 
    <br>
    Im Standard wird die lokal installierte Version (./fhem/www/pgm2/sscam_hls.js) zur Wiedergabe von Daten in allen 
    Streaming Devices vom Typ "hls" genutzt (siehe "set &lt;name&gt; createStreamDev hls").
    Dieses Attribut wird in einem Device vom Model "SVS" gesetzt und gilt zentral für alle Streaming Devices !
  </li><br>
    
  <a name="hlsStrmObject"></a>
  <li><b>hlsStrmObject</b><br>
  Wurde ein Streaming Device mit "set &lt;name&gt; createStreamDev hls" definiert, muss mit diesem Attribut der Link zum 
  Wiedergabeobjekt bekannt gemacht werden. <br>
  Die Angabe muss ein HTTP Live Streaming Objekt mit der Endung ".m3u8" enthalten. <br>
  Die Variable $NAME kann als Platzhalter genutzt werden und übernimmt den SSCam-Devicenamen.
  <br><br> 
  
        <ul>
        <b>Beispiele:</b><br>
        attr &lt;name&gt; hlsStrmObject https://bitdash-a.akamaihd.net/content/MI201109210084_1/m3u8s/f08e80da-bf1d-4e3d-8899-f0f6155f6efa.m3u8  <br>
        attr &lt;name&gt; hlsStrmObject https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8  <br>
        # Beispielstreams der zum Test des Streaming Devices verwendet werden kann (Internetverbindung nötig) <br><br>
        
        attr &lt;name&gt; hlsStrmObject http://192.168.2.10:32000/CamHE1.m3u8  <br>
        # Wiedergabe eines Kamera HLS-Streams der z.B. durch ffmpeg bereitgestellt wird  <br><br>
        
        attr &lt;name&gt; hlsStrmObject http://192.168.2.10:32000/$NAME.m3u8  <br>
        # Wie obiges Beispiel mit der Variablennutzung für "CamHE1"     
        </ul>
        <br>
        </li>
        
  
  <a name="htmlattr"></a>
  <li><b>htmlattr</b><br>
  ergänzende Angaben zur Inline-Bilddarstellung um das Verhalten wie Bildgröße zu beeinflussen. <br><br> 
  
        <ul>
        <b>Beispiel:</b><br>
        attr &lt;name&gt; htmlattr width="500" height="325" top="200" left="300"
        </ul>
        <br>
        </li>
  
  <a name="livestreamprefix"></a>
  <li><b>livestreamprefix</b><br>
    Überschreibt die Angaben zu Protokoll, Servernamen und Port in StmKey.*-Readings bzw. der Livestreamadresse zur 
    Weiterverwendung z.B. als externer Link. <br>
    Die Spezifikation kann auf zwei Arten erfolgen: <br><br> 

    <table>  
    <colgroup> <col width=25%> <col width=75%> </colgroup>
     <tr><td> <b>DEF</b>                                        </td><td>: es wird Protokoll, Servername und Port aus der Definition
                                                                           des SSCam-Devices verwendet </td></tr>
     <tr><td> <b>http(s)://&lt;servername&gt;:&lt;port&gt;</b>  </td><td>: eine eigene Adressenangabe wird verwendet </td></tr>
    </table>
    <br>

    Servername kann der Name oder die IP-Adresse der Synology Surveillance Station sein.
    
    </li><br>
  
  <a name="loginRetries"></a>
  <li><b>loginRetries</b><br>
    Setzt die Anzahl der Login-Wiederholungen im Fehlerfall (default = 3)   </li><br>
  
  <a name="noQuotesForSID"></a>
  <li><b>noQuotesForSID</b><br>
    Dieses Attribut entfernt Quotes für SID bzw. der StmKeys. 
    Es kann in bestimmten Fällen die Fehlermeldung "402 - permission denied" oder "105 - Insufficient user privilege"
    vermeiden und ein login ermöglichen.  </li><br>                      
  
  <a name="pollcaminfoall"></a>
  <li><b>pollcaminfoall</b><br>
    Intervall der automatischen Eigenschaftsabfrage (Polling) einer Kamera (&lt;= 10: kein Polling, &gt; 10: Polling mit Intervall) </li><br>
  
  <a name="pollnologging"></a>
  <li><b>pollnologging</b><br>
    "0" bzw. nicht gesetzt = Logging Gerätepolling aktiv (default), "1" = Logging 
    Gerätepolling inaktiv </li><br>
  
  <a name="ptzNoCapPrePat"></a>  
  <li><b>ptzNoCapPrePat</b><br>
    Manche PTZ-Kameras können trotz ihrer PTZ-Fähigkeiten keine Presets und Patrols speichern. 
    Um Fehler und entsprechende Logmeldungen zu vermeiden, kann in diesen Fällen das Attribut ptzNoCapPrePat gesetzt 
    werden. Dem System wird eine fehlende Preset / Patrol Fähigkeit mitgeteilt. 
  </li><br>  
  
  <a name="ptzPanel_Home"></a>  
  <li><b>ptzPanel_Home</b><br>
    Im PTZ-Steuerungspaneel wird dem Home-Icon (im Attribut "ptzPanel_row02") automatisch der Wert des Readings 
    "PresetHome" zugewiesen.
    Mit "ptzPanel_Home" kann diese Zuweisung mit einem Preset aus der verfügbaren Preset-Liste geändert werden. 
  </li><br> 
  
  <a name="ptzPanel_iconPath"></a>  
  <li><b>ptzPanel_iconPath</b><br>
    Pfad für Icons im PTZ-Steuerungspaneel, default ist "www/images/sscam". 
    Der Attribut-Wert wird für alle Icon-Dateien außer *.svg verwendet. <br>
    Für weitere Information bitte "get &lt;name&gt; versionNotes 2,6" ausführen.
  </li><br> 

  <a name="ptzPanel_iconPrefix"></a>
  <li><b>ptzPanel_iconPrefix</b><br>
    Prefix für Icon-Dateien im PTZ-Steuerungspaneel, default ist "black_btn_". 
    Der Attribut-Wert wird für alle Icon-Dateien außer *.svg verwendet. <br>
    Beginnen die verwendeten Icon-Dateien z.B. mit "black_btn_" ("black_btn_CAMDOWN.png"), braucht das Icon in den
    Attributen "ptzPanel_row[00-09]" nur noch mit dem darauf folgenden Teilstring, z.B. "CAMDOWN.png" benannt zu werden.
    </li><br>    

  <a name="ptzPanel_row00"></a>
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
    vorgenommen werden. Zur Erstellung eigener Icons gibt es eine Vorlage im SVN. Für weitere Informationen bitte
    "get &lt;name&gt; versionNotes 2" ausführen.
    <br><br>
    
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

  <a name="ptzPanel_use"></a>
  <li><b>ptzPanel_use</b><br>
    Die Anzeige des PTZ-Steuerungspaneels in der Detailanzeige bzw. innerhalb eines generierten Streamdevice wird 
    ein- bzw. ausgeschaltet (default ein). <br>
    Das PTZ-Panel benutzt einen eigenen Satz Icons. 
    Damit das System sie finden kann, ist im FHEMWEB Device das Attribut "iconPath" um "sscam" zu ergänzen 
    (z.B. "attr WEB iconPath default:fhemSVG:openautomation:sscam").
  </li><br>  
  
  <a name="recChatTxt"></a>
  <li><b>recChatTxt chatbot => &lt;SSChatBot-Device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;Betreff-Text&gt;]  </b><br>
    Aktiviert den permanenten Versand von Aufnahmen nach deren Erstellung per Synology Chat. <br>
    Vor der Aktivierung ist das Attribut <a href="#videofolderMap">videofolderMap</a> zu setzen. Es muß eine URL zum 
    root-Verzeichnis der Aufnahmen und Schnappschüsse enthalten ( z.B. http://server.mein:8081/surveillance ). <br>
    Das Attribut recChatTxt muß in der angegebenen Form definiert werden. Im Schlüssel "chatbot" ist das SSChatBot-Device 
    anzugeben, welches für den Versand der Daten verwendet werden soll.
    Das <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers">SSChatBot-Device</a> muss natürlich vorhanden und funktionstüchtig sein. <br>
    Der Schlüssel "peers" enthält gültige Namen von Synology Chat Nutzern an die die Nachricht gesendet werden soll. <br>
    Die Angabe von "peers" ist optional, jedoch muß der Schlüssel (leer) angegeben werden. 
    Wurde "peers" leer gelassen, wird der defaultPeer des SSChatBot-Devices verwendet. <br><br>
    
    Es können die folgenden Platzhalter im subject verwendet werden. <br><br>
    
        <ul>   
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> $CAM   </td><td>- Device-Alias bzw. den Namen der Kamera in der SVS ersetzt falls der Device-Alias nicht vorhanden ist </td></tr>
          <tr><td> $DATE  </td><td>- aktuelles Datum </td></tr>
          <tr><td> $TIME  </td><td>- aktuelle Zeit </td></tr>
          <tr><td> $FILE  </td><td>- Filename </td></tr>
          <tr><td> $CTIME </td><td>- Erstellungszeit der Aufnahme </td></tr>
        </table>
        </ul>     
        <br>    
    
    <b>Beispiele:</b><br>
    attr &lt;device&gt; recChatTxt chatbot =&gt; SynChatBot, peers =&gt; , subject =&gt; Bewegungsalarm ($FILE)  <br>
    attr &lt;device&gt; recChatTxt chatbot =&gt; SynChatBot, peers =&gt; Frodo Sam Gollum, subject =&gt; Achtung <br>
    attr &lt;device&gt; recChatTxt chatbot =&gt; SynChatBot, peers =&gt; , subject =&gt; Achtung Aufnahme <br>
    attr &lt;device&gt; recChatTxt chatbot =&gt; SynChatBot, peers =&gt; , subject =&gt; Bewegungsalarm bei $CAM. Es wurde $CTIME die Aufnahme $FILE erstellt. Jetzt ist es $TIME. <br>
    <br>
  </li><br>

  <a name="recEmailTxt"></a>
  <li><b>recEmailTxt subject => &lt;Betreff-Text&gt;, body => &lt;Mitteilung-Text&gt; </b><br>
    Aktiviert den Emailversand von Aufnahmen nach deren Erstellung. <br>
    Das Attribut muß in der angegebenen Form definiert werden. <br>
    Es können die folgenden Platzhalter im subject und body verwendet werden. <br><br>
    
        <ul>   
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> $CAM   </td><td>- Device-Alias bzw. der Name der Kamera in der SVS falls der Device-Alias nicht vorhanden ist </td></tr>
          <tr><td> $DATE  </td><td>- aktuelles Datum </td></tr>
          <tr><td> $TIME  </td><td>- aktuelle Zeit </td></tr>
        </table>
        </ul>     
        <br>
    
       <ul>
        <b>Beispiel:</b><br>
        recEmailTxt subject => Neue Aufnahme $CAM, body => Die aktuelle Aufnahme von $CAM ist angehängt.
      </ul>
      <br>
  </li>  
  
  <a name="recTelegramTxt"></a>
  <li><b>recTelegramTxt tbot => &lt;TelegramBot-Device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;Betreff-Text&gt;]  </b><br>
    Aktiviert den permanenten Versand von Aufnahmen nach deren Erstellung per TelegramBot. <br>
    Das Attribut muß in der angegebenen Form definiert werden. Im Schlüssel "tbot" ist das TelegramBot-Device 
    anzugeben, welches für den Versand der Daten verwendet werden soll. 
    Das <a href="http://fhem.de/commandref_DE.html#TelegramBot">TelegramBot-Device</a> muss natürlich vorhanden und funktionstüchtig sein. <br>
    Die Angabe von "peers" und "subject" ist optional, jedoch muß der Schlüssel (leer) angegeben werden. 
    Wurde "peers" leer gelassen, wird der Default-Peer des TelegramBot-Device verwendet. <br><br>
    
    Es können die folgenden Platzhalter im subject verwendet werden. <br><br>
    
        <ul>   
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> $CAM   </td><td>- Device-Alias bzw. den Namen der Kamera in der SVS ersetzt falls der Device-Alias nicht vorhanden ist </td></tr>
          <tr><td> $DATE  </td><td>- aktuelles Datum </td></tr>
          <tr><td> $TIME  </td><td>- aktuelle Zeit </td></tr>
          <tr><td> $FILE  </td><td>- Filename </td></tr>
          <tr><td> $CTIME </td><td>- Erstellungszeit der Aufnahme </td></tr>
        </table>
        </ul>     
        <br>    
    
    <b>Beispiele:</b><br>
    attr &lt;device&gt; recTelegramTxt tbot =&gt; teleBot, peers =&gt; , subject =&gt; Bewegungsalarm ($FILE)  <br>
    attr &lt;device&gt; recTelegramTxt tbot =&gt; teleBot, peers =&gt; @nabuko @foo @bar, subject =&gt;  <br>
    attr &lt;device&gt; recTelegramTxt tbot =&gt; teleBot, peers =&gt; #nabugroup, subject =&gt;  <br>
    attr &lt;device&gt; recTelegramTxt tbot =&gt; teleBot, peers =&gt; -123456, subject =&gt;  <br>
    attr &lt;device&gt; recTelegramTxt tbot =&gt; teleBot, peers =&gt; , subject =&gt;  <br>
    attr &lt;device&gt; recTelegramTxt tbot =&gt; teleBot, peers =&gt; , subject =&gt; Bewegungsalarm bei $CAM. Es wurde $CTIME die Aufnahme $FILE erstellt. Jetzt ist es $TIME. <br>
      <br>
  </li><br>
  
  <a name="rectime"></a>  
  <li><b>rectime</b><br>
    festgelegte Aufnahmezeit wenn eine Aufnahme gestartet wird. Mit rectime = 0 wird eine 
    Endlosaufnahme gestartet. Ist "rectime" nicht gesetzt, wird der Defaultwert von 15s 
    verwendet.</li><br>
  
  <a name="recextend"></a>
  <li><b>recextend</b><br>
    "rectime" einer gestarteten Aufnahme wird neu gesetzt. Dadurch verlängert sich die 
    Aufnahemzeit einer laufenden Aufnahme </li><br>
  
  <a name="session"></a>
  <li><b>session</b><br>
    Auswahl der Login-Session. Nicht gesetzt oder "DSM" -> session wird mit DSM aufgebaut 
    (Standard). "SurveillanceStation" -> Session-Aufbau erfolgt mit SVS. <br>
    Um eine Session mit der Surveillance Station aufzubauen muss ein Nutzer mit passenden Privilegien Profil in der SVS
    angelegt werden. Für weitere Informationen bitte "get &lt;name&gt; versionNotes 5" ausführen.  </li><br>
  
  <a name="simu_SVSversion"></a>
  <li><b>simu_SVSversion</b><br>
    Simuliert eine andere SVS-Version. (es ist nur eine niedrigere als die installierte SVS 
    Version möglich !) </li><br>
  
  <a name="smtpHost"></a>
  <li><b>smtpHost &lt;Hostname&gt; </b><br>
    Gibt den Hostnamen oder die IP-Adresse des Postausgangsservers für den Emailversand an (z.B. securesmtp.t-online.de).
  </li>
  <br>
  
  <a name="smtpCc"></a>
  <li><b>smtpCc &lt;name&gt;@&lt;domain&gt;[, &lt;name&gt;@&lt;domain&gt;][, &lt;name&gt;@&lt;domain&gt;]... </b><br>
    Optionale zusätzliche Empfängeradresse(n) für den Email-Versand. Mehrere Adressen müssen durch "," getrennt werden.
  </li>
  <br>
  
  <a name="smtpDebug"></a>
  <li><b>smtpDebug </b><br>
    Schaltet den Debugging-Modus der Verbindung zum Email-Server ein (wenn Email Versand verwendet wird).
  </li>
  <br>
  
  <a name="smtpFrom"></a>
  <li><b>smtpFrom &lt;name&gt;@&lt;domain&gt; </b><br>
    Absenderadresse bei Verwendung des Emailversands.
  </li>
  <br>
  
  <a name="smtpPort"></a>
  <li><b>smtpPort &lt;Port&gt; </b><br>
    Optionale Angabe Standard-SMTP-Port des Postausgangsservers (default: 25).
  </li>
  <br>
  
  <a name="smtpSSLPort"></a>
  <li><b>smtpSSLPort &lt;Port&gt; </b><br>
    Optionale Angabe SSL Port des Postausgangsservers (default: 465). Ist dieses Attribut gesetzt, erfolgt die Verbindung zum
    Email-Server sofort verschlüsselt.
  </li>
  <br> 
  
  <a name="smtpTo"></a>
  <li><b>smtpTo &lt;name&gt;@&lt;domain&gt;[, &lt;name&gt;@&lt;domain&gt;][, &lt;name&gt;@&lt;domain&gt;]... </b><br>
    Empfängeradresse(n) für den Email-Versand. Mehrere Adressen müssen durch "," getrennt werden.
  </li>
  <br>
  
  <a name="smtpNoUseSSL"></a>
  <li><b>smtpNoUseSSL </b><br>
    Soll keine Email SSL-Verschlüsselung genutzt werden, ist dieses Attribut auf "1" zu setzen (default: 0).
  </li>
  <br>
  
  <a name="snapChatTxt"></a>
  <li><b>snapChatTxt chatbot => &lt;SSChatBot-Device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;Betreff-Text&gt;]  </b><br>
    Aktiviert den permanenten Versand von Schnappschüssen nach deren Erstellung per Synology Chat. Wurden mehrere Schnappschüsse ausgelöst, 
    werden sie sequentiell versendet.<br>
    Vor der Aktivierung ist das Attribut <a href="#videofolderMap">videofolderMap</a> zu setzen. Es muß eine URL zum 
    root-Verzeichnis der Aufnahmen und Schnappschüsse enthalten ( z.B. http://server.mein:8081/surveillance ). <br>
    Das Attribut snapChatTxt muß in der angegebenen Form definiert werden. Im Schlüssel "chatbot" ist das SSChatBot-Device 
    anzugeben, welches für den Versand der Daten verwendet werden soll. 
    Das <a href="https://wiki.fhem.de/wiki/SSChatBot_-_Integration_des_Synology_Chat_Servers">SSChatBot-Device</a> muss natürlich vorhanden und funktionstüchtig sein. <br>
    Der Schlüssel "peers" enthält gültige Namen von Synology Chat Nutzern an die die Nachricht gesendet werden soll. <br>
    Die Angabe von "peers" ist optional, jedoch muß der Schlüssel (leer) angegeben werden. 
    Wurde "peers" leer gelassen, wird der defaultPeer des SSChatBot-Devices verwendet. <br><br>
    
    Es können folgende Platzhalter im subject verwendet werden. <br><br>
    
        <ul>   
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> $CAM   </td><td>- Device-Alias bzw. den Namen der Kamera in der SVS ersetzt falls der Device-Alias nicht vorhanden ist </td></tr>
          <tr><td> $DATE  </td><td>- aktuelles Datum </td></tr>
          <tr><td> $TIME  </td><td>- aktuelle Zeit </td></tr>
          <tr><td> $FILE  </td><td>- Filename des Schnappschusses </td></tr>
          <tr><td> $CTIME </td><td>- Erstellungszeit des Schnappschusses </td></tr>
        </table>
        </ul>     
        <br>    
    
    <b>Beispiele:</b><br>
    attr &lt;device&gt; snapChatTxt chatbot =&gt; SynChatBot, peers =&gt; , subject =&gt; Bewegungsalarm ($FILE)  <br>
    attr &lt;device&gt; snapChatTxt chatbot =&gt; SynChatBot, peers =&gt; Aragorn Frodo Sam, subject =&gt; Ein Schnappschuss wurde ausgelöst <br>
    attr &lt;device&gt; snapChatTxt chatbot =&gt; SynChatBot, peers =&gt; , subject =&gt; Achtung ! <br>
    attr &lt;device&gt; snapChatTxt chatbot =&gt; SynChatBot, peers =&gt; Frodo, subject =&gt; Bewegungsalarm bei $CAM. Es wurde $CTIME der Schnappschuss $FILE erstellt <br>
    <br>
  </li><br>
  
  <a name="snapEmailTxt"></a>
  <li><b>snapEmailTxt subject => &lt;Betreff-Text&gt;, body => &lt;Mitteilung-Text&gt; </b><br>
    Aktiviert den Emailversand von Schnappschüssen nach deren Erstellung. Wurden mehrere Schnappschüsse ausgelöst, 
    werden sie gemeinsam in einer Mail versendet. <br>
    Das Attribut muß in der angegebenen Form definiert werden. <br>
    Es können die folgenden Platzhalter im subject und body verwendet werden. <br><br>
    
        <ul>   
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> $CAM   </td><td>- Device-Alias bzw. der Name der Kamera in der SVS falls der Device-Alias nicht vorhanden ist </td></tr>
          <tr><td> $DATE  </td><td>- aktuelles Datum </td></tr>
          <tr><td> $TIME  </td><td>- aktuelle Zeit </td></tr>
        </table>
        </ul>     
        <br>    
    
       <ul>
        <b>Beispiel:</b><br>
        snapEmailTxt subject => Bewegungsalarm $CAM, body => Eine Bewegung wurde an der $CAM registriert.
      </ul>
      <br>
  </li>
  
  <a name="snapTelegramTxt"></a>
  <li><b>snapTelegramTxt tbot => &lt;TelegramBot-Device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;Betreff-Text&gt;]  </b><br>
    Aktiviert den permanenten Versand von Schnappschüssen nach deren Erstellung per TelegramBot. Wurden mehrere Schnappschüsse ausgelöst, 
    werden sie sequentiell versendet.<br>
    Das Attribut muß in der angegebenen Form definiert werden. Im Schlüssel "tbot" ist das TelegramBot-Device 
    anzugeben, welches für den Versand der Daten verwendet werden soll. 
    Das <a href="http://fhem.de/commandref_DE.html#TelegramBot">TelegramBot-Device</a> muss natürlich vorhanden und funktionstüchtig sein. <br>
    Die Angabe von "peers" und "subject" ist optional, jedoch muß der Schlüssel (leer) angegeben werden. 
    Wurde "peer" leer gelassen, wird der Default-Peer des TelegramBot-Devices verwendet. <br><br>
    
    Es können folgende Platzhalter im subject verwendet werden. <br><br>
    
        <ul>   
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
          <tr><td> $CAM   </td><td>- Device-Alias bzw. den Namen der Kamera in der SVS ersetzt falls der Device-Alias nicht vorhanden ist </td></tr>
          <tr><td> $DATE  </td><td>- aktuelles Datum </td></tr>
          <tr><td> $TIME  </td><td>- aktuelle Zeit </td></tr>
          <tr><td> $FILE  </td><td>- Filename des Schnappschusses </td></tr>
          <tr><td> $CTIME </td><td>- Erstellungszeit des Schnappschusses </td></tr>
        </table>
        </ul>     
        <br>    
    
    <b>Beispiele:</b><br>
    attr &lt;device&gt; snapTelegramTxt tbot =&gt; teleBot, peers =&gt; , subject =&gt; Bewegungsalarm ($FILE)  <br>
    attr &lt;device&gt; snapTelegramTxt tbot =&gt; teleBot, peers =&gt; @nabuko @foo @bar, subject =&gt;  <br>
    attr &lt;device&gt; snapTelegramTxt tbot =&gt; teleBot, peers =&gt; #nabugroup, subject =&gt;  <br>
    attr &lt;device&gt; snapTelegramTxt tbot =&gt; teleBot, peers =&gt; -123456, subject =&gt;  <br>
    attr &lt;device&gt; snapTelegramTxt tbot =&gt; teleBot, peers =&gt; , subject =&gt;  <br>
    attr &lt;device&gt; snapTelegramTxt tbot =&gt; teleBot, peers =&gt; , subject =&gt; Bewegungsalarm bei $CAM. Es wurde $CTIME der Schnappschuss $FILE erstellt <br>
    <br>
  </li><br>
    
  <a name="snapGalleryBoost"></a>
  <li><b>snapGalleryBoost</b><br>
    Wenn gesetzt, werden die letzten Schnappschüsse (default 3) über Polling im Speicher gehalten und mit "set/get snapGallery" 
    aufbereitet angezeigt. Dieser Modus bietet sich an wenn viele bzw. Fullsize Images angezeigt werden sollen. 
    Ist das Attribut eingeschaltet, können bei "set/get snapGallery" keine Argumente mehr mitgegeben werden. 
    (siehe Attribut "snapGalleryNumber") </li><br>
  
  <a name="snapGalleryColumns"></a>
  <li><b>snapGalleryColumns</b><br>
    Die Anzahl der Snaps die in einer Reihe im Popup erscheinen sollen (default 3). </li><br>
    
  <a name="snapGalleryHtmlAttr"></a>
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
        
  <a name="snapGalleryNumber"></a>
  <li><b>snapGalleryNumber</b><br>
    Die Anzahl der abzurufenden Schnappschüsse (default 3). </li><br>
    
  <a name="snapGallerySize"></a>  
  <li><b>snapGallerySize</b><br>
     Mit diesem Attribut kann die Qualität der Images eingestellt werden (default "Icon"). <br>
     Im Modus "Full" wird die original vorhandene Auflösung der Images abgerufen. Dies erfordert mehr Ressourcen und kann die 
     Anzeige verlangsamen. Mit "snapGalleryBoost=1" kann die Ausgabe beschleunigt werden, da in diesem Fall die Aufnahmen über 
     Polling abgerufen und nur noch zur Anzeige gebracht werden. </li><br>

  <a name="snapReadingRotate"></a>
  <li><b>snapReadingRotate 0...10</b><br>
    Aktiviert die Versionierung von Schnappschußreadings (default: 0). Es wird eine fortlaufende Nummer der Readings 
    "LastSnapFilename", "LastSnapId" und "LastSnapTime" bis zum eingestellten Wert von snapReadingRotate erzeugt und enthält 
    die Daten der letzten X Schnappschüsse. </li><br>
    
  <a name="showStmInfoFull"></a>
  <li><b>showStmInfoFull</b><br>
    zusaätzliche Streaminformationen wie LiveStreamUrl, StmKeyUnicst, StmKeymjpegHttp werden 
    ausgegeben</li><br>
  
  <a name="showPassInLog"></a>
  <li><b>showPassInLog</b><br>
    Wenn gesetzt, wird das verwendete Passwort im Logfile mit verbose 4 angezeigt. 
    (default = 0) </li><br>
  
  <a name="videofolderMap"></a>
  <li><b>videofolderMap</b><br>
    Ersetzt den Inhalt des Readings "VideoFolder". Verwendung z.B. bei gemounteten 
    Verzeichnissen oder URL-Bereitstellung durch einen Webserver. </li><br>
  
  <a name="verbose"></a>
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
    <tr><td><li>CamLastRecId</li>       </td><td>- die ID der letzten Aufnahme   </td></tr>
    <tr><td><li>CamLastRecTime</li>     </td><td>- Datum / Startzeit - Stopzeit der letzten Aufnahme (Format abhängig vom global Attribut "language")  </td></tr>
    <tr><td><li>CamLiveFps</li>         </td><td>- Frames pro Sekunde des Live-Streams  </td></tr>    
    <tr><td><li>CamLiveMode</li>        </td><td>- Quelle für Live-Ansicht (DS, Camera)  </td></tr>
    <tr><td><li>camLiveQuality</li>     </td><td>- in SVS eingestellte Live-Stream Qualität  </td></tr>
    <tr><td><li>camLiveResolution</li>  </td><td>- in SVS eingestellte Live-Stream Auflösung  </td></tr>
    <tr><td><li>camLiveStreamNo</li>    </td><td>- verwendete Stream-Nummer für Live-Stream  </td></tr>
    <tr><td><li>CamModel</li>           </td><td>- Kameramodell  </td></tr>
    <tr><td><li>CamMotDetSc</li>        </td><td>- Status der Bewegungserkennung (disabled, durch Kamera, durch SVS) und deren Parameter </td></tr>
    <tr><td><li>CamNTPServer</li>       </td><td>- eingestellter Zeitserver  </td></tr>
    <tr><td><li>CamPort</li>            </td><td>- IP-Port der Kamera  </td></tr>
    <tr><td><li>CamPreRecTime</li>      </td><td>- Dauer der der Voraufzeichnung in Sekunden (Einstellung in SVS)  </td></tr>
    <tr><td><li>CamPtSpeed</li>         </td><td>- eingestellter Wert für Schwenken/Neige-Aktionen (Einstellung in SVS)  </td></tr>
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
    <tr><td><li>CapPIR</li>             </td><td>- besitzt die Kamera einen PIR-Sensor  </td></tr>
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
    <tr><td><li>LastSnapFilename[x]</li></td><td>- der Filename des/der letzten Schnapschüsse   </td></tr>
    <tr><td><li>LastSnapId[x]</li>      </td><td>- die ID des/der letzten Schnapschüsse   </td></tr>
    <tr><td><li>LastSnapTime[x]</li>    </td><td>- Zeitstempel des/der letzten Schnapschüsse (Format abhängig vom global Attribut "language") </td></tr>
    <tr><td><li>LastUpdateTime</li>     </td><td>- Datum / Zeit der letzten Aktualisierung durch "caminfoall" (Format abhängig vom global Attribut "language")</td></tr> 
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
    <tr><td><li>compstate</li>          </td><td>- Kompatibilitätsstatus (Vergleich von eingesetzter/simulierter SVS-Version zum Internal COMPATIBILITY)  </td></tr>
  </table>
  </ul>
  <br><br>    
 </ul>
  
 </ul>
 <br><br>
</ul>

=end html_DE

=for :application/json;q=META.json 49_SSCam.pm
{
  "abstract": "Module to control cameras as well as other functions of the Synology Surveillance Station.",
  "x_lang": {
    "de": {
      "abstract": "Modul zur Steuerung von Kameras und anderen Funktionen der Synology Surveillance Station."
    }
  },
  "keywords": [
    "camera",
    "control",
    "PTZ",
    "Synology Surveillance Station",
    "Cloudfree",
    "official API",
    "MJPEG",
    "HLS",
    "RTSP"
  ],
  "version": "v1.1.1",
  "release_status": "stable",
  "author": [
    "Heiko Maaz <heiko.maaz@t-online.de>"
  ],
  "x_fhem_maintainer": [
    "DS_Starter"
  ],
  "x_fhem_maintainer_github": [
    "nasseeder1"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014,
        "POSIX": 0,
        "JSON": 0,
        "Data::Dumper": 0,
        "MIME::Base64": 0,
        "Time::HiRes": 0,
        "GPUtils": 0,
        "HttpUtils": 0,
        "Blocking": 0,
        "Encode": 0,
        "FHEM::SynoModules::API": 0,  
        "FHEM::SynoModules::SMUtils": 0, 
        "FHEM::SynoModules::ErrCodes": 0        
      },
      "recommends": {
        "FHEM::Meta": 0,
        "CHI": 0,
        "CHI::Driver::Redis": 0,
        "Cache::Cache": 0
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "x_wiki": {
      "web": "https://wiki.fhem.de/wiki/SSCAM_-_Steuerung_von_Kameras_in_Synology_Surveillance_Station",
      "title": "SSCAM - Steuerung von Kameras in Synology Surveillance Station"
    },
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter/49_SSCam.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/fhem/trunk/fhem/contrib/DS_Starter/49_SSCam.pm"
      }      
    }
  }
}
=end :application/json;q=META.json

=cut
