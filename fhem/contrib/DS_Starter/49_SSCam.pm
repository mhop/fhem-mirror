########################################################################################################################
# $Id: 49_SSCam.pm 20152 2019-09-12 20:37:17Z DS_Starter $
#########################################################################################################################
#       49_SSCam.pm
#
#       (c) 2015-2019 by Heiko Maaz
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

package main;

use strict;                           
use warnings;
eval "use JSON;1;" or my $SScamMMDBI = "JSON";                    # Debian: apt-get install libjson-perl
use Data::Dumper;                                                 # Perl Core module
use MIME::Base64;
use Time::HiRes;
use HttpUtils;
use Blocking;                                                     # für EMail-Versand
use Encode;
eval "use FHEM::Meta;1" or my $modMetaAbsent = 1;                                                    
# no if $] >= 5.017011, warnings => 'experimental';

# Versions History intern
our %SSCam_vNotesIntern = (
  "8.18.0" => "13.09.2019  change usage of own hashes to central %data hash, release unnecessary allocated memory ",
  "8.17.0" => "12.09.2019  fix warnings, support hide buttons in streaming device, change handle delete SNAPHASHOLD ",
  "8.16.3" => "13.08.2019  commandref revised ",
  "8.16.2" => "17.07.2019  change function SSCam_ptzpanel using css stylesheet ",
  "8.16.1" => "16.07.2019  fix warnings ",
  "8.16.0" => "14.07.2019  change detail link generation from SSCamSTRM to SSCam ",
  "8.15.2" => "14.07.2019  fix order of snaps in snapgallery when adding new snaps, fix english date formating in composegallery, ".
                           "align center of FTUI table, set compatibility to 8.2.5 ",
  "8.15.1" => "11.07.2019  enhancement and bugfixes for refresh of SSCamSTRM devices (integrate FUUID) ",
  "8.15.0" => "09.07.2019  support of SSCamSTRM get function and FTUI widget ",
  "8.14.2" => "28.06.2019  increase get SID timeout to at least 60 s, set compatibility to SVS 8.2.4, improve disable/enable behavior ",
  "8.14.1" => "23.06.2019  Presets and Patrols containing spaces in its names are replaced by \"_\", deletion of Presets corrected ".
                           "bugfix userattr when changing Prests ",
  "8.14.0" => "01.06.2019  Link to Cam/SVS-Setup Screen and online help in Detailview ",
  "8.13.6" => "26.05.2019  enhanced log entries of snapinfos with debugactivetoken ",
  "8.13.5" => "23.05.2019  StmKey quoted depending on attr noQuotesForSID (Forum: https://forum.fhem.de/index.php/topic,45671.msg938236.html#msg938236), ".
                           "autoplay muted of hls-StreamDev",
  "8.13.4" => "21.05.2019  rec/snapemailtxt, rec/snaptelegramtxt can contain \":\", commandref revised ", 
  "8.13.3" => "28.04.2019  don't save private hash refs in central hash, \"repository\" added in Meta.json ",
  "8.13.2" => "07.04.2019  fix perl warning Forum: https://forum.fhem.de/index.php/topic,45671.msg927912.html#msg927912",
  "8.13.1" => "06.04.2019  verbose level in X_DelayedShutdown changed ",
  "8.13.0" => "27.03.2019  add Meta.pm support ",
  "8.12.0" => "25.03.2019  FHEM standard function X_DelayedShutdown implemented, delay FHEM shutdown as long as sessions ".
              "are not terminated. ",
  "8.11.5" => "24.03.2019  fix possible overload Synology DS during shutdown restart ",
  "8.11.4" => "11.03.2019  make module ready for SVS version 8.2.3-5829 ",
  "8.11.3" => "08.03.2019  avoid possible JSON errors, fix fhem is hanging while restart or get snapinfo - Forum: #45671.msg915546.html#msg915546 ",
  "8.11.2" => "04.03.2019  bugfix no snapinfos when snap was done by SVS itself, Forum: https://forum.fhem.de/index.php/topic,45671.msg914685.html#msg914685",
  "8.11.1" => "28.02.2019  commandref revised, minor fixes ",
  "8.11.0" => "25.02.2019  changed compatibility check, compatibility to SVS version 8.2.3, Popup possible for \"generic\"-Streamdevices, ".
              "support for \"genericStrmHtmlTag\" in streaming devices ",
  "8.10.1" => "19.02.2019  fix warning when starting fhem, and Forum:#97706",
  "8.10.0" => "15.02.2019  send recordings integrated by telegram, a lot of internal changes for send telegrams ",
  "8.9.2"  => "05.02.2019  sub SSCam_sendTelegram changed ",
  "8.9.1"  => "05.02.2019  sub SSCam_snaplimsize changed ",
  "8.9.0"  => "05.02.2019  new streaming device type \"lastsnap\" ",
  "8.8.1"  => "04.02.2019  fix need attr snapGalleryBoost / snapGallerySize for ending a snap by telegramBot ",
  "8.8.0"  => "03.02.2019  send snapshots integrated by telegram ",
  "8.7.2"  => "30.01.2019  code change for snapCams (SVS) ",
  "8.7.1"  => "30.01.2019  fix refresh snapgallery device if snap was done by itself ",
  "8.7.0"  => "27.01.2019  send recording by email ",
  "8.6.2"  => "25.01.2019  fix version numbering ",
  "8.6.1"  => "21.01.2019  time format in readings and galleries depends from global language attribute, minor bug fixes ",
  "8.6.0"  => "20.01.2019  new attribute snapReadingRotate ",
  "8.5.0"  => "17.01.2019  SVS device has \"snapCams\" command ",
  "8.4.5"  => "15.01.2019  fix event generation after request snapshots ",
  "8.4.4"  => "14.01.2019  change: generate event of every snapfile,id etc. if snap was called with arguments, Forum:#45671 #msg887484  ",
  "8.4.3"  => "11.01.2019  fix blocking Active-Token if snap was done with arguments and snapEmailTxt not set, Forum:#45671 #msg885475 ",
  "8.4.2"  => "10.01.2019  snapEmailTxt can use placeholders \$DATE, \$TIME ",
  "8.4.1"  => "09.01.2019  Transaction of snap and getsnapinfo implemented, debugactive token verbose level changed ",
  "8.4.0"  => "07.01.2019  command snap extended to \"snap [number] [lag] [snapEmailTxt:\"subject => <Betreff-Text>, body => ".
              "<Mitteilung-Text>\"]\", SID-hash is deleted if attr \"session\" is set ",
  "8.3.2"  => "03.01.2019  fix Process died prematurely if Can't locate object method \"get_sslversion\" via package \"Net::SMTP::SSL\" ",
  "8.3.1"  => "02.01.2019  fix SMTP usage for older Net::SMTP, new attribute \"smtpSSLPort\"",
  "8.3.0"  => "02.01.2019  CAMLASTRECID replaced by Reading CamLastRecId, \"SYNO.SurveillanceStation.Recording\" added, ".
                           "new get command \"saveRecording\"",
  "8.2.0"  => "02.01.2019  store SMTP credentials with \"smtpcredentials\", SMTP Email integrated ",
  "8.1.0"  => "19.12.2018  tooltipps in camera device for control buttons, commandref revised ",
  "8.0.0"  => "13.12.2018  HLS with sscam_hls.js integrated for SSCamSTRM type hls, realize tooltipps in streaming devices, minor fixes",
  "7.7.1"  => "12.12.2018  change autocreateCams: define new device only if ne device with Internal CAMNAME is defined, ".
              "fix getsnapinfo function get wrong snapid or none if cam is new defined ",
  "7.7.0"  => "10.12.2018  SVS-Device: autocreateCams command added, some other fixes and improvements, minor code rewrite, ".
              "save Stream in \$streamHash->{HELPER}{STREAM} for popupStream in SSCamSTRM-Device ",
  "7.6.0"  => "02.12.2018  sub SSCam_ptzpanel completed by Preset and Patrol, minor fixes ",
  "7.5.0"  => "02.12.2018  sub SSCam_StreamDev and SSCam_composegallery changed to use popup window ",
  "7.4.1"  => "26.11.2018  sub composegallery deleted, SSCam_composegallery changed to get information for SSCam_refresh ",
  "7.4.0"  => "24.11.2018  new set command \"createReadingsGroup\", versionNotes can process lists like \"2,6\", changed compatibility check, use SnapId when get information after took snapshot and sscam state-event ",
  "7.3.3"  => "18.11.2018  change rights decsption in commandRef ",
  "7.3.2"  => "12.11.2018  fix Warning in line 4954, set COMPATIBILITY to 8.2.2 ",
  "7.3.1"  => "31.10.2018  fix connection lost failure if several SSCamSTRM devices are defined and updated by longpoll from same parent device ",
  "7.3.0"  => "28.10.2018  usage of attribute \"livestreamprefix\" changed, exec SSCam_getStmUrlPath on boot ",
  "7.2.1"  => "23.10.2018  new routine SSCam_versionCheck, COMPATIBILITY changed to 8.2.1 ",
  "7.2.0"  => "20.10.2018  direct help for attributes, new get versionNotes command, fix PERL WARNING: Use of uninitialized value \$small, get versionNotes ",
  "7.1.1"  => "18.10.2018  Message of \"Your current/simulated SVS-version...\" changed, commandref corrected ",
  "7.1.0"  => "02.09.2018  PIR Sensor enable/disable, SSCam_Set/SSCam_Get optimized ",
  "7.0.1"  => "27.08.2018  enable/disable issue (https://forum.fhem.de/index.php/topic,45671.msg830869.html#msg830869) ",
  "7.0.0"  => "27.07.2018  compatibility to API v2.8 ",
  "6.0.1"  => "04.07.2018  Reading CamFirmware ",
  "6.0.0"  => "03.07.2018  HTTPS Support, buttons for refresh SSCamSTRM-devices ",
  "5.3.0"  => "29.06.2018  changes regarding to \"createStreamDev ... generic\", refresh reading parentState of all, SSCamSTRM devices with PARENT=SSCam-device, control elements for runView within fhemweb, new CamLive.*-Readings, minor fixes ",
  "5.2.7"  => "26.06.2018  fix state turns to \"off\" even though cam is disabled ",
  "5.2.6"  => "20.06.2018  running stream as human readable entry for SSCamSTRM-Device, goAbsPTZ fix set-entry für non-PTZ ",
  "5.2.5"  => "18.06.2018  trigger lastsnap_fw to SSCamSTRM-Device only if snap was done by it. ",
  "5.2.4"  => "17.06.2018  SSCam_composegallery added and write warning if old composegallery-weblink device is used  ",
  "5.2.3"  => "16.06.2018  no SSCamSTRM refresh when snapgetinfo was running without taken a snap by SSCamSTRM-Device ",
  "5.2.2"  => "16.06.2018  compatibility to SSCamSTRM V 1.1.0 ",
  "5.2.1"  => "14.06.2018  design change of SSCam_StreamDev, change in event generation for SSCam_StreamDev, fix global vars ",
  "5.2.0"  => "14.06.2018  support longpoll refresh of SSCamSTRM-Devices ",
  "5.1.0"  => "13.06.2018  more control elements (Start/Stop Recording, Take Snapshot) in func SSCam_StreamDev, control of detaillink is moved to SSCamSTRM-device ",
  "5.0.1"  => "12.06.2018  control of page refresh improved (for e.g. Floorplan,Dashboard) ",
  "5.0.0"  => "11.06.2018  HLS Streaming, Buttons for Streaming-Devices, use of module SSCamSTRM for Streaming-Devices, deletion of Streaming-devices if SSCam-device is deleted, some more improvements, minor bugfixes ",
  "4.3.0"  => "27.05.2018  HLS preparation changed ",
  "4.2.0"  => "22.05.2018  PTZ-Panel integrated to created StreamDevice ",
  "4.1.0"  => "05.05.2018  use SYNO.SurveillanceStation.VideoStream instead of SYNO.SurveillanceStation.VideoStreaming, preparation for hls ",
  "4.0.0"  => "01.05.2018  AudioStream possibility added ",
  "3.10.0" => "24.04.2018  createStreamDev added, new features lastrec_fw_MJPEG, lastrec_fw_MPEG4/H.264 added to playback MPEG4/H.264 videos ",
  "3.9.2"  => "21.04.2018  minor fixes ",
  "3.9.1"  => "20.04.2018  Attribute ptzPanel_use, initial webcommands in DeviceOverview changed, minor fixes ptzPanel ",
  "3.9.0"  => "17.04.2018  control panel & PTZcontrol weblink device for PTZ cams ",
  "3.8.4"  => "06.04.2018  Internal MODEL changed to SVS or \"CamVendor - CamModel\" for Cams ",
  "3.8.3"  => "05.04.2018  bugfix V3.8.2, \$OpMode \"Start\" changed, composegallery changed ",
  "3.8.2"  => "04.04.2018  \$attr replaced by AttrVal, SSCam_wdpollcaminfo redesigned ",
  "3.8.1"  => "04.04.2018  some codereview like new sub SSCam_jboolmap ",
  "3.8.0"  => "03.04.2018  new reading PresetHome, setHome command, minor fixes ",
  "3.7.0"  => "26.03.2018  minor details of setPreset changed, new command delPreset ",
  "3.6.0"  => "25.03.2018  setPreset command, changed SSCam_wdpollcaminfo, SSCam_getcaminfoall ",
  "3.5.0"  => "22.03.2018  new get command listPresets ",
  "3.4.0"  => "21.03.2018  new commands startTracking, stopTracking ",
  "3.3.1"  => "20.03.2018  new readings CapPTZObjTracking, CapPTZPresetNumber ",
  "3.3.0"  => "25.02.2018  code review, API bug fix of runview lastrec, commandref revised (forum:#84953) ",
  "1.0.0"  => "12.12.2015  initial, changed completly to HttpUtils_NonblockingGet "
);

# Versions History extern
our %SSCam_vNotesExtern = (
  "8.15.0" => "09.07.2019 support of integrating Streaming-Devices in a SSCam FTUI widget ",
  "8.14.0" => "01.06.2019 In detailview are buttons provided to open the camera native setup screen or Synology Surveillance Station and the Synology Surveillance Station online help. ",
  "8.12.0" => "25.03.2019 Delay FHEM shutdown as long as sessions are not terminated, but not longer than global attribute \"maxShutdownDelay\". ",
  "8.11.0" => "25.02.2019 compatibility set to SVS version 8.2.3, Popup possible for streaming devices of type \"generic\", ".
              "support for \"genericStrmHtmlTag\" in streaming devices ",
  "8.10.0" => "15.02.2019 Possibility of send recordings by telegram is integrated as well as sending snapshots ",
  "8.9.0"  => "05.02.2019 A new streaming device type \"lastsnap\" was implemented. You can create such device with \"set ... createStreamDev lastsnap\". ".
                          "This streaming device shows the newest snapshot which was taken. ",
  "8.8.0"  => "01.02.2019 Snapshots can now be sent by telegramBot ",
  "8.7.0"  => "27.01.2019 SMTP Email delivery of recordings implemented. You can send a recording after it was created subsequentely ".
                          "with the integrated Email client. You have to store SMTP credentials with \"smtpcredentials\" before. ",
  "8.6.2"  => "25.01.2019 fix version numbering ",
  "8.6.1"  => "21.01.2019 new attribute \"snapReadingRotate\" to activate versioning of snap data, ".
              "time format in readings and galleries depends from global language attribute ",
  "8.5.0"  => "17.01.2019 SVS device has \"snapCams\" command. Now are able to take snapshots of all defined cameras and may ".
              "optionally send them alltogether by Email.",
  "8.4.0"  => "07.01.2019 Command snap is extended to syntax \"snap [number] [lag] [snapEmailTxt:\"subject => &lt;Betreff-Text&gt;, body => ".
              "&lt;Mitteilung-Text&gt;\"]\". Now you are able to trigger several number of ".
              "snapshots by only one snap-command. The triggered snapshots can be shipped alltogether with the internal email client. ",
  "8.3.0"  => "02.01.2019 new get command \"saveRecording\"",
  "8.2.0"  => "02.01.2019 SMTP Email delivery of snapshots implemented. You can send snapshots after it was created subsequentely ".
                          "with the integrated Email client. You have to store SMTP credentials with \"smtpcredentials\" before. ",
  "8.1.0"  => "19.12.2018 Tooltipps added to camera device control buttons.",
  "8.0.0"  => "18.12.2018 HLS is integrated using sscam_hls.js in Streaming device types \"hls\". HLS streaming is now available ".
              "for all common used browser types. Tooltipps are added to streaming devices and snapgallery.",
  "7.7.0"  => "10.12.2018 autocreateCams command added to SVS device. By this command all cameras installed in SVS can be ".
              "defined automatically. <br>".
              "In SSCamSTRM devices the \"set &lt;name&gt; popupStream\" command is implemented which may open a popup window with the ".
              "active streaming content. ",
  "7.6.0"  => "02.12.2018 The PTZ panel is completed by \"Preset\" and \"Patrol\" (only for PTZ cameras) ",
  "7.5.0"  => "02.12.2018 A click on suitable content in a stream- or snapgallery device opens a popup window. ".
               "The popup size can be adjusted by attribute \"popupWindowSize\". ",
  "7.4.0"  => "20.11.2018 new command \"createReadingsGroup\". By this command a ReadingsGroup with a name of your choice (or use the default name) can be created. ".
              "Procedure changes of taking snapshots avoid inaccuracies if camera names in SVS very similar. ",
  "7.3.2"  => "12.11.2018 fix Warning if 'livestreamprefix' is set to DEF, COMPATIBILITY set to 8.2.2 ",
  "7.3.0"  => "28.10.2018 In attribute \"livestreamprefix\" can now \"DEF\" be specified to overwrite livestream address by specification from device definition ",
  "7.2.1"  => "23.10.2018 COMPATIBILITY changed to 8.2.1 ",
  "7.2.0"  => "20.10.2018 direct help for attributes, new get versionNotes command, please see commandref for details ",
  "7.1.1"  => "18.10.2018 Message of \"current/simulated SVS-version...\" changed, commandref corrected ",
  "7.1.0"  => "02.09.2018 PIR Sensor enable/disable, SSCam_Set/SSCam_Get optimized ",
  "7.0.1"  => "27.08.2018 enable/disable issue (https://forum.fhem.de/index.php/topic,45671.msg830869.html#msg830869) ",
  "7.0.0"  => "27.07.2018 compatibility to API v2.8 ",
  "6.0.1"  => "04.07.2018 Reading CamFirmware ",
  "6.0.0"  => "03.07.2018 HTTPS Support, buttons for refresh SSCamSTRM-devices ",
  "5.2.7"  => "26.06.2018 fix state turns to \"off\" even though cam is disabled ",
  "5.2.5"  => "18.06.2018 trigger lastsnap_fw to SSCamSTRM-Device only if snap was done by it. ",
  "5.2.4"  => "17.06.2018 SSCam_composegallery added and write warning if old composegallery-weblink device is used  ",
  "5.2.2"  => "16.06.2018 compatibility to SSCamSTRM V 1.1.0 ",
  "5.2.1"  => "14.06.2018 design change of SSCam_StreamDev, change in event generation for SSCam_StreamDev, fix global vars ",
  "5.2.0"  => "14.06.2018 support longpoll refresh of SSCamSTRM-Devices ",
  "5.1.0"  => "13.06.2018 more control elements (Start/Stop Recording, Take Snapshot) in func SSCam_StreamDev, control of detaillink is moved to SSCamSTRM-device ",
  "5.0.1"  => "12.06.2018 control of page refresh improved (for e.g. Floorplan,Dashboard) ",
  "4.2.0"  => "22.05.2018 PTZ-Panel integrated to created StreamDevice ",
  "4.0.0"  => "01.05.2018 AudioStream possibility added ",
  "3.10.0" => "24.04.2018 createStreamDev added, new features lastrec_fw_MJPEG, lastrec_fw_MPEG4/H.264 added to playback MPEG4/H.264 videos ",
  "3.9.1"  => "20.04.2018 Attribute ptzPanel_use, initial webcommands in DeviceOverview changed, minor fixes ptzPanel ",
  "3.9.0"  => "17.04.2018 control panel & PTZcontrol weblink device for PTZ cams ",
  "3.8.4"  => "06.04.2018 Internal MODEL changed to SVS or \"CamVendor - CamModel\" for Cams ",
  "3.8.3"  => "05.04.2018 bugfix V3.8.2, \$OpMode \"Start\" changed, composegallery changed ",
  "3.6.0"  => "25.03.2018 setPreset command ",
  "3.5.0"  => "22.03.2018 new get command listPresets ",
  "3.4.0"  => "21.03.2018 new commands startTracking, stopTracking ",
  "3.3.1"  => "20.03.2018 new readings CapPTZObjTracking, CapPTZPresetNumber ",
  "3.3.0"  => "25.02.2018 code review, API bug fix of runview lastrec, commandref revised (forum:#84953) ",
  "3.2.4"  => "18.11.2017 fix bug don't retrieve SSCam_getptzlistpreset if cam is disabled ",
  "3.2.3"  => "08.10.2017 set optimizeParams, get caminfo (simple), minor bugfix, commandref revised ",
  "3.2.0"  => "27.09.2017 new command get listLog, change to \$hash->{HELPER}{\".SNAPHASH\"} for avoid huge \"list\"-report ",
  "3.1.0"  => "26.09.2017 move extevent from CAM to SVS model, Reading PollState enhanced for CAM-Model, minor fixes ",
  "3.0.0"  => "23.09.2017 Internal MODEL SVS or CAM -> distinguish/support Cams and SVS in different devices new comand get storedCredentials, commandref revised ",
  "2.9.0"  => "20.09.2017 new function get homeModeState, minor fixes at simu_SVSversion, commandref revised ",
  "2.6.0"  => "06.08.2017 new command createSnapGallery ",
  "2.5.4"  => "05.08.2017 analyze \$hash->{CL} in SetFn bzw. GetFn, set snapGallery only if snapGalleryBoost=1 is set, some snapGallery improvements and fixes ",
  "2.5.3"  => "02.08.2017 implement snapGallery as set-command ",
  "2.2.2"  => "11.06.2017 bugfix SSCam_login, SSCam_login_return, Forum: https://forum.fhem.de/index.php/topic,45671.msg646701.html#msg646701 ",
  "1.39.0"  => "20.01.2017 compatibility to SVS 8.0.0, Version in Internals, execute SSCam_getsvsinfo after set credentials ",
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
  "1.7.0"  => "18.01.2016 Attribute \"httptimeout\" added ",
  "1.6.0"  => "16.01.2016 Change the define-string related to rectime. (http://forum.fhem.de/index.php/topic,45671.msg391664.html#msg391664)   ",                
  "1.5.1"  => "11.01.2016 Vars \"USERNAME\" and \"RECTIME\" removed from internals, Var (Internals) \"SERVERNAME\" changed to \"SERVERADDR\" ",
  "1.5.0"  => "04.01.2016 Function \"Get\" for creating Camera-Readings integrated, Attributs pollcaminfoall, pollnologging added, Function for Polling Cam-Infos added. ",
  "1.4.0"  => "23.12.2015 function \"enable\" and \"disable\" for SS-Cams added, changed timout of Http-calls to a higher value ",
  "1.3.0"  => "19.12.2015 function \"snap\" for taking snapshots added, fixed a bug that functions may impact each other  ",
  "1.0.0"  => "12.12.2015 initial, changed completly to HttpUtils_NonblockingGet "
);

# getestete SVS-Version
my $compstat = "8.2.5";

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
  406 => "OTP code enforced",
  407 => "Max Tries (if auto blocking is set to true) - make sure FHEM-Server IP won't be blocked in DSM automated blocking list",
  408 => "Password Expired Can not Change",
  409 => "Password Expired",
  410 => "Password must change (when first time use or after reset password by admin)",
  411 => "Account Locked (when account max try exceed)",
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

# Tooltipps Textbausteine (http://www.walterzorn.de/tooltip/tooltip.htm#download), §NAME§ wird durch Kameranamen ersetzt 
our %SSCam_ttips_en = (
    ttrefresh   => "The playback of streaming content of camera of &quot;§NAME§&quot; will be restartet.",
    ttrecstart  => "Start an endless recording of camera &quot;§NAME§&quot;.<br>You have to stop the recording manually.",
    ttrecstop   => "Stopp the recording of camera &quot;§NAME§&quot;.",
    ttsnap      => "Take a snapshot of camera &quot;§NAME§&quot;.",
    ttcmdstop   => "Stopp playback of camera &quot;§NAME§&quot;",
    tthlsreact  => "Reactivate HTTP Livestreaming Interface of camera &quot;§NAME§&quot;.<br>The camera is enforced to restart HLS transmission.",
    ttmjpegrun  => "Playback the MJPEG Livestream of camera &quot;§NAME§&quot;.",
    tthlsrun    => "Playback the native HTTP Livestream of camera &quot;§NAME§&quot;. The browser must have native support for HLS streaming.",
    ttlrrun     => "Playback of last recording of camera &quot;§NAME§&quot; in an iFrame.<br>Both MJPEG and H.264 recordings are rendered.",
    tth264run   => "Playback of last H.264 recording of camera &quot;§NAME§&quot;.<br>It only starts if the recording is type H.264",
    ttlmjpegrun => "Playback of last MJPEG recording of camera &quot;§NAME§&quot;.<br>It only starts if the recording is type MJPEG",
    ttlsnaprun  => "Playback of last snapshot of camera &quot;§NAME§&quot;.",
    confcam     => "The configuration menu of camera &quot;§NAME§&quot; will be opened in a new Browser page",
    confsvs     => "The configuration page of Synology Surveillance Station will be opened in a new Browser page",
    helpsvs     => "The online help page of Synology Surveillance Station will be opened in a new Browser page",
);
	  
our %SSCam_ttips_de = (
    ttrefresh   => "Die Wiedergabe des Streams von Kamera &quot;§NAME§&quot; wird neu gestartet.",
    ttrecstart  => "Startet eine Endlosaufnahme von Kamera &quot;§NAME§&quot;.<br>Die Aufnahme muß manuell gestoppt werden.",
    ttrecstop   => "Stoppt die laufende Aufnahme von Kamera &quot;§NAME§&quot;.",
    ttsnap      => "Ein Schnappschuß von Kamera &quot;§NAME§&quot; wird aufgenommen.", 
    ttcmdstop   => "Stopp Wiedergabe von Kamera &quot;§NAME§&quot;",
    tthlsreact  => "Reaktiviert das HTTP Livestreaming Interface von Kamera &quot;§NAME§&quot;.<br>Die Kamera wird aufgefordert die HLS Übertragung zu restarten.",     
    ttmjpegrun  => "Wiedergabe des MJPEG Livestreams von Kamera &quot;§NAME§&quot;",
    tthlsrun    => "Wiedergabe des HTTP Livestreams von Kamera &quot;§NAME§&quot;.<br>Es wird die HLS Funktion der Synology Surveillance Station verwendet. (der Browser muss HLS nativ unterstützen)",
    ttlrrun     => "Wiedergabe der letzten Aufnahme von Kamera &quot;§NAME§&quot; in einem iFrame.<br>Es werden sowohl MJPEG als auch H.264 Aufnahmen wiedergegeben.",
    tth264run   => "Wiedergabe der letzten H.264 Aufnahme von Kamera &quot;§NAME§&quot;.<br>Die Wiedergabe startet nur wenn die Aufnahme vom Typ H.264 ist.",
    ttlmjpegrun => "Wiedergabe der letzten MJPEG Aufnahme von Kamera &quot;§NAME§&quot;.<br>Die Wiedergabe startet nur wenn die Aufnahme vom Typ MJPEG ist.", 
    ttlsnaprun  => "Wiedergabe des letzten Schnappschusses von Kamera &quot;§NAME§&quot;.",
    confcam     => "Das Konfigurationsmenü von Kamera &quot;§NAME§&quot; wird in einer neuen Browserseite geöffnet",
    confsvs     => "Die Konfigurationsseite der Synology Surveillance Station wird in einer neuen Browserseite geöffnet",
    helpsvs     => "Die Onlinehilfe der Synology Surveillance Station wird in einer neuen Browserseite geöffnet",
);

# Standardvariablen und Forward-Deklaration
my $SSCam_slim  = 3;                                    # default Anzahl der abzurufenden Schnappschüsse mit snapGallery
my $SSCAM_snum  = "1,2,3,4,5,6,7,8,9,10";               # mögliche Anzahl der abzurufenden Schnappschüsse mit snapGallery

use vars qw($FW_ME);                                    # webname (default is fhem), used by 97_GROUP/weblink
use vars qw($FW_subdir);                                # Sub-path in URL, used by FLOORPLAN/weblink
use vars qw($FW_room);                                  # currently selected room
use vars qw($FW_detail);                                # currently selected device for detail view
use vars qw($FW_wname);                                 # Web instance
sub FW_pH(@);                                           # add href
use vars qw(%SSCam_vHintsExt_en);
use vars qw(%SSCam_vHintsExt_de);
sub SSCam_TBotSendIt($$$$$$$;$$$);

################################################################
sub SSCam_Initialize($) {
 my ($hash) = @_;
 $hash->{DefFn}             = "SSCam_Define";
 $hash->{UndefFn}           = "SSCam_Undef";
 $hash->{DeleteFn}          = "SSCam_Delete"; 
 $hash->{SetFn}             = "SSCam_Set";
 $hash->{GetFn}             = "SSCam_Get";
 $hash->{AttrFn}            = "SSCam_Attr";
 $hash->{DelayedShutdownFn} = "SSCam_DelayedShutdown";
 # Aufrufe aus FHEMWEB
 $hash->{FW_summaryFn}      = "SSCam_FWsummaryFn";
 $hash->{FW_detailFn}       = "SSCam_FWdetailFn";
 $hash->{FW_deviceOverview} = 1;
 
 $hash->{AttrList} =
         "disable:1,0 ".
         "genericStrmHtmlTag ".
         "hlsNetScript:1,0 ".
         "hlsStrmObject ".
         "httptimeout ".
         "htmlattr ".
         "livestreamprefix ".
		 "loginRetries:1,2,3,4,5,6,7,8,9,10 ".
         "videofolderMap ".
         "pollcaminfoall ".
		 "smtpCc ".
		 "smtpDebug:1,0 ".
		 "smtpFrom ".
		 "smtpHost ".
         "smtpPort ".
         "smtpSSLPort ".
		 "smtpTo ".
		 "smtpNoUseSSL:1,0 ".
         "snapEmailTxt ".
         "snapTelegramTxt ".
		 "snapGalleryBoost:0,1 ".
		 "snapGallerySize:Icon,Full ".
		 "snapGalleryNumber:$SSCAM_snum ".
		 "snapGalleryColumns ".
		 "snapGalleryHtmlAttr ".
         "snapReadingRotate:0,1,2,3,4,5,6,7,8,9,10 ".
         "pollnologging:1,0 ".
         "debugactivetoken:1,0 ".
         "recEmailTxt ".
         "recTelegramTxt ".
         "rectime ".
         "recextend:1,0 ".
         "noQuotesForSID:1,0 ".
         "session:SurveillanceStation,DSM ".
         "showPassInLog:1,0 ".
         "showStmInfoFull:1,0 ".
         "simu_SVSversion:7.2-xxxx,7.1-xxxx,8.0.0-xxxx,8.1.5-xxxx,8.2.0-xxxx ".
         "webCmd ".
         $readingFnAttributes;   
         
 eval { FHEM::Meta::InitMod( __FILE__, $hash ) };           # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)

return;   
}

################################################################
sub SSCam_Define($@) {
  # Die Define-Funktion eines Moduls wird von Fhem aufgerufen wenn der Define-Befehl für ein Gerät ausgeführt wird 
  # Welche und wie viele Parameter akzeptiert werden ist Sache dieser Funktion. Die Werte werden nach dem übergebenen Hash in ein Array aufgeteilt
  # define CamCP1 SSCAM Carport 192.168.2.20 [5000] 
  #       ($hash)  [1]    [2]        [3]      [4]  
  #
  my ($hash, $def) = @_;
  my $name         = $hash->{NAME};
  
 return "Error: Perl module ".$SScamMMDBI." is missing. Install it on Debian with: sudo apt-get install libjson-perl" if($SScamMMDBI);
  
  my @a = split("[ \t][ \t]*", $def);
  
  if(int(@a) < 4) {
        return "You need to specify more parameters.\n". "Format: define <name> SSCAM <Cameraname> <ServerAddress> [Port]";
        }
        
  my $camname    = $a[2];
  my $serveraddr = $a[3];
  my $serverport = $a[4] ? $a[4] : 5000;
  my $proto      = $a[5] ? lc($a[5]) : "http";
  
  $hash->{SERVERADDR}            = $serveraddr;
  $hash->{SERVERPORT}            = $serverport;
  $hash->{CAMNAME}               = $camname;
  $hash->{MODEL}                 = ($camname =~ m/^SVS$/i)?"SVS":"CAM";          # initial, CAM wird später ersetzt durch CamModel
  $hash->{PROTOCOL}              = $proto;
  $hash->{COMPATIBILITY}         = $compstat;                                    # getestete SVS-version Kompatibilität 
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                         # Modul Meta.pm nicht vorhanden
  
  # benötigte API's in $hash einfügen
  $hash->{HELPER}{APIINFO}        = "SYNO.API.Info";                             # Info-Seite für alle API's, einzige statische Seite !                                                    
  $hash->{HELPER}{APIAUTH}        = "SYNO.API.Auth";                             # API used to perform session login and logout
  $hash->{HELPER}{APISVSINFO}     = "SYNO.SurveillanceStation.Info"; 
  $hash->{HELPER}{APIEVENT}       = "SYNO.SurveillanceStation.Event"; 
  $hash->{HELPER}{APIEXTREC}      = "SYNO.SurveillanceStation.ExternalRecording"; 
  $hash->{HELPER}{APIEXTEVT}      = "SYNO.SurveillanceStation.ExternalEvent";
  $hash->{HELPER}{APICAM}         = "SYNO.SurveillanceStation.Camera";           # stark geändert ab API v2.8
  $hash->{HELPER}{APISNAPSHOT}    = "SYNO.SurveillanceStation.SnapShot";         # This API provides functions on snapshot, including taking, editing and deleting snapshots.
  $hash->{HELPER}{APIPTZ}         = "SYNO.SurveillanceStation.PTZ";
  $hash->{HELPER}{APIPRESET}      = "SYNO.SurveillanceStation.PTZ.Preset";
  $hash->{HELPER}{APICAMEVENT}    = "SYNO.SurveillanceStation.Camera.Event";
  $hash->{HELPER}{APIVIDEOSTM}    = "SYNO.SurveillanceStation.VideoStreaming";   # verwendet in Response von "SYNO.SurveillanceStation.Camera: GetLiveViewPath" -> StreamKey-Methode
  # $hash->{HELPER}{APISTM}         = "SYNO.SurveillanceStation.Streaming";        # provides methods to get Live View or Event video stream, removed in API v2.8
  $hash->{HELPER}{APISTM}         = "SYNO.SurveillanceStation.Stream";           # Beschreibung ist falsch und entspricht "SYNO.SurveillanceStation.Streaming" auch noch ab v2.8
  $hash->{HELPER}{APIHM}          = "SYNO.SurveillanceStation.HomeMode";
  $hash->{HELPER}{APILOG}         = "SYNO.SurveillanceStation.Log";
  $hash->{HELPER}{APIAUDIOSTM}    = "SYNO.SurveillanceStation.AudioStream";      # Audiostream mit SID, removed in API v2.8 (noch undokumentiert verfügbar)
  $hash->{HELPER}{APIVIDEOSTMS}   = "SYNO.SurveillanceStation.VideoStream";      # Videostream mit SID, removed in API v2.8 (noch undokumentiert verfügbar)
  $hash->{HELPER}{APIREC}         = "SYNO.SurveillanceStation.Recording";        # This API provides method to query recording information.
  
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
  $hash->{HELPER}{SNAPLIMIT}           = 0;                                      # abgerufene Anzahl Snaps
  $hash->{HELPER}{TOTALCNT}            = 0;                                      # totale Anzahl Snaps
  
  # Versionsinformationen setzen
  SSCam_setVersionInfo($hash);
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"PollState","Inactive");                              # es ist keine Gerätepolling aktiv  
  if(SSCam_IsModelCam($hash)) {
      readingsBulkUpdate($hash,"Availability", "???");                           # Verfügbarkeit ist unbekannt
      readingsBulkUpdate($hash,"state", "off");                                  # Init für "state" , Problemlösung für setstate, Forum #308
  } else {
      readingsBulkUpdate($hash,"state", "Initialized");                          # Init für "state" wenn SVS  
  }
  readingsEndUpdate($hash,1);                                          
  
  SSCam_getcredentials($hash,1,"svs");                                           # Credentials lesen und in RAM laden ($boot=1)      
  SSCam_getcredentials($hash,1,"smtp");
  
  # initiale Routinen nach Restart ausführen   , verzögerter zufälliger Start
  RemoveInternalTimer($hash, "SSCam_initonboot");
  InternalTimer(gettimeofday()+int(rand(30)), "SSCam_initonboot", $hash, 0);

return undef;
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
sub SSCam_Undef($$) {
  my ($hash, $arg) = @_;
  
  RemoveInternalTimer($hash);
   
return undef;
}

#######################################################################################################
# Mit der X_DelayedShutdown Funktion kann eine Definition das Stoppen von FHEM verzögern um asynchron 
# hinter sich aufzuräumen.  
# Je nach Rückgabewert $delay_needed wird der Stopp von FHEM verzögert (0|1).
# Sobald alle nötigen Maßnahmen erledigt sind, muss der Abschluss mit CancelDelayedShutdown($name) an 
# FHEM zurückgemeldet werden. 
#######################################################################################################
sub SSCam_DelayedShutdown($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  
  Log3($name, 2, "$name - Quit session due to shutdown ...");
  $hash->{HELPER}{ACTIVE} = "on";                              # keine weiteren Aktionen erlauben
  SSCam_logout($hash);

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
    
    if ($aName eq "session") {
	    delete $hash->{HELPER}{SID};
    }
    
    if ($aName =~ /hlsNetScript/ && SSCam_IsModelCam($hash)) {            
        return " The attribute \"$aName\" is only valid for devices of type \"SVS\"! Please set this attribute in a device of this type.";
    }
    
    if ($aName =~ /snapReadingRotate/ && !SSCam_IsModelCam($hash)) {            
        return " The attribute \"$aName\" is not valid for devices of type \"SVS\"!.";
    }
    
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
		
		if ($do == 1) {
		    RemoveInternalTimer($hash);
		} else {
		    InternalTimer(gettimeofday()+int(rand(30)), "SSCam_initonboot", $hash, 0);
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
            delete($hash->{HELPER}{".SNAPHASH"}) if(AttrVal($name,"snapGalleryBoost",0));  # Snaphash nur löschen wenn Snaps gepollt werden   
            Log3($name, 4, "$name - Snapshot hash deleted");
		} elsif (AttrVal($name,"snapGalleryBoost",0)) {
		    # snap-Infos abhängig ermitteln wenn gepollt werden soll
		    my ($slim,$ssize);
            $hash->{HELPER}{GETSNAPGALLERY} = 1;   
		    $slim  = AttrVal($name,"snapGalleryNumber",$SSCam_slim);    # Anzahl der abzurufenden Snaps
			$ssize = $do;
			RemoveInternalTimer($hash, "SSCam_getsnapinfo"); 
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
			RemoveInternalTimer($hash, "SSCam_getsnapinfo"); 
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
        
        delete($hash->{HELPER}{".SNAPHASH"});              # bestehenden Snaphash löschen
		$hash->{HELPER}{GETSNAPGALLERY} = 1;
		my $sg = AttrVal($name,"snapGallerySize","Icon");  # Auflösung Image
		$ssize = ($sg eq "Icon")?1:2;
		RemoveInternalTimer($hash, "SSCam_getsnapinfo"); 
		InternalTimer(gettimeofday()+0.7, "SSCam_getsnapinfo", "$name:$slim:$ssize", 0);
	}
    
    if ($aName eq "snapReadingRotate") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        if(!$do) {$aVal = 0}
        for my $i (1..10) { 
            if($i>$aVal) {
                readingsDelete($hash, "LastSnapFilename$i");
                readingsDelete($hash, "LastSnapId$i");
                readingsDelete($hash, "LastSnapTime$i");  
            }
        }
    }
    
    if ($aName eq "simu_SVSversion") {
	    delete $hash->{HELPER}{APIPARSET};
	    delete $hash->{HELPER}{SID};
		delete $hash->{CAMID};
        RemoveInternalTimer($hash, "SSCam_getcaminfoall");
        InternalTimer(gettimeofday()+0.5, "SSCam_getcaminfoall", $hash, 0);
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
        
  return if(IsDisabled($name));
 
  if(!$hash->{CREDENTIALS}) {
      # initiale setlist für neue Devices
      $setlist = "Unknown argument $opt, choose one of ".
	             "credentials "
                 ;  
  } elsif(SSCam_IsModelCam($hash)) {
      # selist für Cams
      my $hlslfw = SSCam_IsHLSCap($hash)?",live_fw_hls,":",";
      $setlist = "Unknown argument $opt, choose one of ".
                 "credentials ".
                 "smtpcredentials ".
                 ((ReadingsVal("$name", "CapPTZPan", "false") ne "false") ? "delPreset:".ReadingsVal("$name","Presets","")." " : "").
                 "expmode:auto,day,night ".
                 "on ".
                 "off:noArg ".
                 "motdetsc:disable,camera,SVS ".
                 "snap ".
	     		 (AttrVal($name, "snapGalleryBoost",0)?(AttrVal($name,"snapGalleryNumber",undef) || AttrVal($name,"snapGalleryBoost",0))?"snapGallery:noArg ":"snapGallery:$SSCAM_snum ":" ").
	     		 "createReadingsGroup ".
                 "createSnapGallery:noArg ".
                 "createStreamDev:generic,hls,lastsnap,mjpeg,switched ".
                 ((ReadingsVal("$name", "CapPTZPan", "false") ne "false") ? "createPTZcontrol:noArg ": "").
                 "enable:noArg ".
                 "disable:noArg ".
				 "optimizeParams ".
                 ((ReadingsVal("$name", "CapPIR", "false") ne "false") ? "pirSensor:activate,deactivate ": "").
                 "runView:live_fw".$hlslfw."live_link,live_open,lastrec_fw,lastrec_fw_MJPEG,lastrec_fw_MPEG4/H.264,lastrec_open,lastsnap_fw ".
                 ((ReadingsVal("$name", "CapPTZPan", "false") ne "false") ? "setPreset ": "").
                 ((ReadingsVal("$name", "CapPTZPan", "false") ne "false") ? "setHome:---currentPosition---,".ReadingsVal("$name","Presets","")." " : "").
                 "stopView:noArg ".
                 ((ReadingsVal("$name", "CapPTZObjTracking", "false") ne "false") ? "startTracking:noArg " : "").
                 ((ReadingsVal("$name", "CapPTZObjTracking", "false") ne "false") ? "stopTracking:noArg " : "").
                 ((ReadingsVal("$name", "CapPTZDirections", 0) > 0) ? "move"." " : "").
                 ((ReadingsVal("$name", "CapPTZPan", "false") ne "false") ? "runPatrol:".ReadingsVal("$name", "Patrols", "")." " : "").
                 ((ReadingsVal("$name", "CapPTZPan", "false") ne "false") ? "goPreset:".ReadingsVal("$name", "Presets", "")." " : "").
                 ((ReadingsVal("$name", "CapPTZAbs", "false") ne "false") ? "goAbsPTZ"." " : ""). 
                 ((ReadingsVal("$name", "CapPTZDirections", 0) > 0) ? "move"." " : "");
  } else {
      # setlist für SVS Devices
      $setlist = "Unknown argument $opt, choose one of ".
                 "autocreateCams:noArg ".
	             "credentials ".
                 "smtpcredentials ".
				 "createReadingsGroup ".
				 "extevent:1,2,3,4,5,6,7,8,9,10 ".
		     	 ($hash->{HELPER}{APIHMMAXVER}?"homeMode:on,off ": "").
                 "snapCams ";
  }  

  if ($opt eq "credentials") {
      return "Credentials are incomplete, use username password" if (!$prop || !$prop1);
	  return "Password is too long. It is limited up to and including 20 characters." if (length $prop1 > 20);
      delete $hash->{HELPER}{SID};          
      ($success) = SSCam_setcredentials($hash,"svs",$prop,$prop1);
      $hash->{HELPER}{ACTIVE} = "off";  
	  
	  if($success) {
	      SSCam_getcaminfoall($hash,0);
          RemoveInternalTimer($hash, "SSCam_getptzlistpreset");
          InternalTimer(gettimeofday()+11, "SSCam_getptzlistpreset", $hash, 0);
          RemoveInternalTimer($hash, "SSCam_getptzlistpatrol");
          InternalTimer(gettimeofday()+12, "SSCam_getptzlistpatrol", $hash, 0);
          SSCam_versionCheck($hash);
		  return "Username and Password saved successfully";
	  } else {
		   return "Error while saving Username / Password - see logfile for details";
	  }
			
  }   
  
  if ($opt eq "smtpcredentials") {
      return "Credentials are incomplete, use username password" if (!$prop || !$prop1);        
      ($success) = SSCam_setcredentials($hash,"smtp",$prop,$prop1);
	  
	  if($success) {
		  return "SMTP-Username and SMTP-Password saved successfully";
	  } else {
		   return "Error while saving SMTP-Username / SMTP-Password - see logfile for details";
	  }		
  }
  
  if ($opt eq "on" && SSCam_IsModelCam($hash)) {            
	  if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      if (defined($prop) && $prop =~ /^\d+$/) {
          $hash->{HELPER}{RECTIME_TEMP} = $prop;
      }
	  
      my $spec = join(" ",@a);
      if($spec =~ /STRM:/) {
          $spec =~ m/.*STRM:(.*).*/i;                                  # Aufnahme durch SSCamSTRM-Device
          $hash->{HELPER}{INFORM} = $1;
      }	
      
      my $emtxt = AttrVal($name, "recEmailTxt", "");
      if($spec =~ /recEmailTxt:/) {
          $spec =~ m/.*recEmailTxt:"(.*)".*/i;
          $emtxt = $1;
      }
      
      if($emtxt) {
          # Recording soll nach Erstellung per Email versendet werden
          # recEmailTxt muss sein:  subject => <Subject-Text>, body => <Body-Text>
          if (!$hash->{SMTPCREDENTIALS}) {return "Due to \"recEmailTxt\" is set, you want to send recordings by email but SMTP credentials are not set - make sure you've set credentials with \"set $name smtpcredentials username password\"";}
          $hash->{HELPER}{SMTPRECMSG} = $emtxt;
      }
      
      my $teletxt = AttrVal($name, "recTelegramTxt", "");
      if($spec =~ /recTelegramTxt:/) {
          $spec =~ m/.*recTelegramTxt:"(.*)".*/i;
          $teletxt = $1;
      }
      
      if ($teletxt) {
	      # Recording soll nach Erstellung per TelegramBot versendet werden
		  # Format $teletxt muss sein: recTelegramTxt:"tbot => <teleBot Device>, peers => <peer1 peer2 ..>, subject => <Beschreibungstext>"
          $hash->{HELPER}{TELERECMSG} = $teletxt;
      }

      SSCam_camstartrec($hash);
 
  } elsif ($opt eq "off" && SSCam_IsModelCam($hash)) {
	  if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      my $emtxt   = $hash->{HELPER}{SMTPRECMSG}?delete $hash->{HELPER}{SMTPRECMSG}:"";
      my $teletxt = $hash->{HELPER}{TELERECMSG}?delete $hash->{HELPER}{TELERECMSG}:"";
	  
      my $spec = join(" ",@a);
      if($spec =~ /STRM:/) {
          $spec =~ m/.*STRM:(.*).*/i;                                  # Aufnahmestop durch SSCamSTRM-Device
          $hash->{HELPER}{INFORM} = $1;
      }
	  
      SSCam_camstoprec("$name!_!$emtxt!_!$teletxt");
        
  } elsif ($opt eq "snap" && SSCam_IsModelCam($hash)) {
	  if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      
      my ($num,$lag,$ncount) = (1,2,1);     
      if($prop && $prop =~ /^\d+$/) {                                  # Anzahl der Schnappschüsse zu triggern (default: 1)
          $num    = $prop;
          $ncount = $prop;
      }
      if($prop1 && $prop1 =~ /^\d+$/) {                                # Zeit zwischen zwei Schnappschüssen (default: 2 Sekunden)
          $lag = $prop1;
      }
      
      Log3($name, 4, "$name - Trigger snapshots - Number: $num, Lag: $lag");   
	  
      my $spec = join(" ",@a);
      if($spec =~ /STRM:/) {
          $spec =~ m/.*STRM:(.*).*/i;                                  # Snap by SSCamSTRM-Device
          $hash->{HELPER}{INFORM} = $1;
      }	
       
      my $emtxt = AttrVal($name, "snapEmailTxt", "");
      if($spec =~ /snapEmailTxt:/) {
          $spec =~ m/.*snapEmailTxt:"(.*)".*/i;
          $emtxt = $1;
      }
      
      if ($emtxt) {
          # Snap soll nach Erstellung per Email versendet werden
          # Format $emtxt muss sein: snapEmailTxt:"subject => <Subject-Text>, body => <Body-Text>"
          if (!$hash->{SMTPCREDENTIALS}) {return "It seems you want to send snapshots by email but SMTP credentials are not set - make sure you've set credentials with \"set $name smtpcredentials username password\"";}
          $hash->{HELPER}{SMTPMSG} = $emtxt;
      }
	  
      my $teletxt = AttrVal($name, "snapTelegramTxt", "");
      if($spec =~ /snapTelegramTxt:/) {
          $spec =~ m/.*snapTelegramTxt:"(.*)".*/i;
          $teletxt = $1;
      }
      
      if ($teletxt) {
	      # Snap soll nach Erstellung per TelegramBot versendet werden
		  # Format $teletxt muss sein: snapTelegramTxt:"tbot => <teleBot Device>, peers => <peer1 peer2 ..>, subject => <Beschreibungstext>"
          $hash->{HELPER}{TELEMSG} = $teletxt;
      }
	  
      SSCam_camsnap("$name!_!$num!_!$lag!_!$ncount!_!$emtxt!_!$teletxt");
              
  } elsif ($opt eq "snapCams" && !SSCam_IsModelCam($hash)) {
	  if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      
      my ($num,$lag,$ncount) = (1,2,1);
      my $cams  = "all";
      if($prop && $prop =~ /^\d+$/) {                                  # Anzahl der Schnappschüsse zu triggern (default: 1)
          $num    = $prop;
          $ncount = $prop;
      }
      if($prop1 && $prop1 =~ /^\d+$/) {                                # Zeit zwischen zwei Schnappschüssen (default: 2 Sekunden)
          $lag = $prop1;
      }      
      
      my $at = join(" ",@a);
      if($at =~ /CAM:/i) {
          $at =~ m/.*CAM:"(.*)".*/i;
          $cams = $1;
          $cams =~ s/\s//g;
      }
      
      my @camdvs;                                                  
      if($cams eq "all") {                                                  # alle nicht disabled Kameras auslösen, sonst nur die gewählten
          @camdvs = devspec2array("TYPE=SSCam:FILTER=MODEL!=SVS");
          foreach (@camdvs) {
              if($defs{$_} && !IsDisabled($_)) {           
                  $hash->{HELPER}{ALLSNAPREF}{$_} = "";                     # Schnappschuss Hash für alle Cams -> Schnappschußdaten sollen hinein  
              }
          }
      } else {
          @camdvs = split(",",$cams);
          foreach (@camdvs) {
              if($defs{$_} && !IsDisabled($_)) {           
                  $hash->{HELPER}{ALLSNAPREF}{$_} = "";
              }              
          }
      }
      
      return "No valid camera devices are specified for trigger snapshots" if(!$hash->{HELPER}{ALLSNAPREF});
      
      my $emtxt;
	  my $teletxt = "";
      my $rawet = AttrVal($name, "snapEmailTxt", "");
      my $bt = join(" ",@a);
      if($bt =~ /snapEmailTxt:/) {
          $bt =~ m/.*snapEmailTxt:"(.*)".*/i;
          $rawet = $1;
      }
      if($rawet) {
          $hash->{HELPER}{CANSENDSNAP} = 1;                                # zentraler Schnappschußversand wird aktiviert
          $hash->{HELPER}{SMTPMSG} = $rawet;   
      }
      
      my ($csnap,$cmail) = ("","");
      foreach my $key (keys%{$hash->{HELPER}{ALLSNAPREF}}) {
          if(!AttrVal($key, "snapEmailTxt", "")) {
              delete $hash->{HELPER}{ALLSNAPREF}->{$key};                  # Snap dieser Kamera auslösen aber nicht senden
              $csnap .= $csnap?", $key":$key;
              $emtxt  = "";
          } else {
              $cmail .= $cmail?", $key":$key;
              $emtxt  = $rawet;
          }
          SSCam_camsnap("$key!_!$num!_!$lag!_!$ncount!_!$emtxt!_!$teletxt");
      }
      Log3($name, 4, "$name - Trigger snapshots by SVS - Number: $num, Lag: $lag, Snap only: \"$csnap\", Snap and send: \"$cmail\" ");
      
              
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
          $hash->{HELPER}{SNAPLIMIT} = AttrVal($name,"snapGalleryNumber",$SSCam_slim);
		  my $htmlCode = SSCam_composegallery($name);
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
      $ret = CommandDefine($hash->{CL},"$sgdev SSCamSTRM {SSCam_composegallery('$name','$sgdev','snapgallery')}");
	  return $ret if($ret);
	  my $room = "SSCam";
      $attr{$sgdev}{room}  = $room;
	  return "Snapgallery device \"$sgdev\" created and assigned to room \"$room\".";
      
  } elsif ($opt eq "createPTZcontrol" && SSCam_IsModelCam($hash)) {
	  if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
	  my $ptzcdev = "SSCamSTRM.$name.PTZcontrol";
      my $ret     = CommandDefine($hash->{CL},"$ptzcdev SSCamSTRM {SSCam_ptzpanel('$name','$ptzcdev','ptzcontrol')}");
	  return $ret if($ret);
	  my $room    = AttrVal($name,"room","SSCam");
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
      if($prop =~ /generic/) {
          $livedev = "SSCamSTRM.$name.generic";
          $ret = CommandDefine($hash->{CL},"$livedev SSCamSTRM {SSCam_StreamDev('$name','$livedev','generic')}");
	      return $ret if($ret);
      } 
      if($prop =~ /hls/) {
          $livedev = "SSCamSTRM.$name.hls";
          $ret = CommandDefine($hash->{CL},"$livedev SSCamSTRM {SSCam_StreamDev('$name','$livedev','hls')}");
	      return $ret if($ret);
          my $c = "The device needs to set attribute \"hlsStrmObject\" in camera device \"$name\" to a valid HLS videostream";
          CommandAttr($hash->{CL},"$livedev comment $c");
      }  
      if($prop =~ /lastsnap/) {
          $livedev = "SSCamSTRM.$name.lastsnap";
          $ret = CommandDefine($hash->{CL},"$livedev SSCamSTRM {SSCam_StreamDev('$name','$livedev','lastsnap')}");
	      return $ret if($ret);
          my $c = "The device shows the last snapshot of camera device \"$name\". \n".
                  "If you always want to see the newest snapshot, please set attribute \"pollcaminfoall\" in camera device \"$name\".\n".
                  "Set also attribute \"snapGallerySize = Full\" in camera device \"$name\" to retrieve snapshots in original resolution.";
          CommandAttr($hash->{CL},"$livedev comment $c");
      }      
      if($prop =~ /switched/) {
          $livedev = "SSCamSTRM.$name.switched";
          $ret = CommandDefine($hash->{CL},"$livedev SSCamSTRM {SSCam_StreamDev('$name','$livedev','switched')}");
	      return $ret if($ret);
      }
      
	  my $room = AttrVal($name,"room","SSCam");
      $attr{$livedev}{room}  = $room;
	  return "Livestream device \"$livedev\" created and assigned to room \"$room\".";
  
  } elsif ($opt eq "createReadingsGroup") {
	  if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
	  my $rgdev = $prop?$prop:"RG.SSCam";
      
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
                     '  "'.$rgdev.'.Start"      => "set %DEVICE runView live_fw",'."\n".
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
	      
	  
      return "readingsGroup device \"$rgdev\" created and assigned to room \"$room\".";
  
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
        
  } elsif ($opt eq "autocreateCams" && !SSCam_IsModelCam($hash)) {
	  if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
            
      SSCam_setAutocreate($hash);
        
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
                
  } elsif ($opt eq "pirSensor" && SSCam_IsModelCam($hash)) {
	  if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      if(ReadingsVal("$name", "CapPIR", "false") eq "false") {return "Function \"$opt\" not possible. Camera \"$name\" don't have a PIR sensor."}
      if(!$prop) {return "Function \"$opt\" needs an argument";}
      $hash->{HELPER}{PIRACT} = ($prop eq "activate")?0:($prop eq "deactivate")?-1:5;
      if($hash->{HELPER}{PIRACT} == 5) {return " Illegal argument for \"$opt\" detected, use \"activate\" or \"activate\" !";}
      SSCam_piract($hash);
        
  } elsif ($opt eq "runPatrol" && SSCam_IsModelCam($hash)) {
	  if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      if (!$prop) {return "Function \"$opt\" needs a \"Patrolname\" as an argument";}
            
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
      
      my $spec = join(" ",@a);
      if($spec =~ /STRM:/) {
          $spec =~ m/.*STRM:(.*).*/i;                                  # Call by SSCamSTRM-Device
          $hash->{HELPER}{INFORM} = $1;
      }	
	  
	  if ($prop eq "live_open") {
          if ($prop1) {$hash->{HELPER}{VIEWOPENROOM} = $prop1;} else {delete $hash->{HELPER}{VIEWOPENROOM};}
          $hash->{HELPER}{OPENWINDOW} = 1;
          $hash->{HELPER}{WLTYPE}     = "link";    
		  $hash->{HELPER}{ALIAS}      = "LiveView";
		  $hash->{HELPER}{RUNVIEW}    = "live_open";
          $hash->{HELPER}{ACTSTRM}    = "";		                # sprechender Name des laufenden Streamtyps für SSCamSTRM
      } elsif ($prop eq "live_link") {
          $hash->{HELPER}{OPENWINDOW} = 0;
          $hash->{HELPER}{WLTYPE}     = "link"; 
		  $hash->{HELPER}{ALIAS}      = "LiveView";
		  $hash->{HELPER}{RUNVIEW}    = "live_link";
		  $hash->{HELPER}{ACTSTRM}    = "";		                # sprechender Name des laufenden Streamtyps für SSCamSTRM
      } elsif ($prop eq "lastrec_open") {
          if ($prop1) {$hash->{HELPER}{VIEWOPENROOM} = $prop1;} else {delete $hash->{HELPER}{VIEWOPENROOM};}
          $hash->{HELPER}{OPENWINDOW} = 1;
          $hash->{HELPER}{WLTYPE}     = "link"; 
	      $hash->{HELPER}{ALIAS}      = "LastRecording";
		  $hash->{HELPER}{RUNVIEW}    = "lastrec_open";
		  $hash->{HELPER}{ACTSTRM}    = "";		                # sprechender Name des laufenden Streamtyps für SSCamSTRM
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
          return "API \"SYNO.SurveillanceStation.VideoStream\" is not available or Reading \"CamStreamFormat\" is not \"HLS\". May be your API version is 2.8 or higher." if(!SSCam_IsHLSCap($hash));
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
      
      my $spec = join(" ",@a);
      if($spec =~ /STRM:/) {
          $spec =~ m/.*STRM:(.*).*/i;                                  # Call by SSCamSTRM-Device
          $hash->{HELPER}{INFORM} = $1;
      }
	  SSCam_hlsactivate($hash);
        
  } elsif ($opt eq "refresh" && SSCam_IsModelCam($hash)) {
      # ohne SET-Menüeintrag
      my $spec = join(" ",@a);
      if($spec =~ /STRM:/) {
          $spec =~ m/.*STRM:(.*).*/i;                                  # Refresh by SSCamSTRM-Device
          $hash->{HELPER}{INFORM} = $1;
		  SSCam_refresh($hash,0,0,1);                                  # kein Room-Refresh, kein SSCam-state-Event, SSCamSTRM-Event
      }
      
  } elsif ($opt eq "extevent" && !SSCam_IsModelCam($hash)) {                                   
	  if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
      $hash->{HELPER}{EVENTID} = $prop;
      SSCam_extevent($hash);
        
  } elsif ($opt eq "stopView" && SSCam_IsModelCam($hash)) {
	  if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}

      my $spec = join(" ",@a);
      if($spec =~ /STRM:/) {
          $spec =~ m/.*STRM:(.*).*/i;                                  # Stop by SSCamSTRM-Device
          $hash->{HELPER}{INFORM} = $1;
      }	
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

    if(!$hash->{CREDENTIALS}) {
        return;
        
	} elsif(SSCam_IsModelCam($hash)) {
	    # getlist für Cams
	    $getlist = "Unknown argument $opt, choose one of ".
                   "caminfoall:noArg ".
				   "caminfo:noArg ".
		 		   ((AttrVal($name,"snapGalleryNumber",undef) || AttrVal($name,"snapGalleryBoost",0))
				       ?"snapGallery:noArg ":"snapGallery:$SSCAM_snum ").
                   ((ReadingsVal("$name", "CapPTZPresetNumber", 0) != 0) ? "listPresets:noArg " : "").
				   "snapinfo:noArg ".
                   "svsinfo:noArg ".
                   "saveRecording ".
                   "snapfileinfo:noArg ".
                   "eventlist:noArg ".
	        	   "stmUrlPath:noArg ".
				   "storedCredentials:noArg ".
				   "scanVirgin:noArg ".
                   "versionNotes " 
                   ;
	} else {
        # getlist für SVS Devices
	    $getlist = "Unknown argument $opt, choose one of ".
		           "caminfoall:noArg ".
				   ($hash->{HELPER}{APIHMMAXVER}?"homeModeState:noArg ": "").
                   "svsinfo:noArg ".
				   "listLog ".
				   "storedCredentials:noArg ".
				   "scanVirgin:noArg ".
                   "versionNotes "
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
                
    } elsif ($opt eq "saveRecording") {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        $hash->{HELPER}{RECSAVEPATH} = $arg if($arg);
        SSCam_getsaverec($hash);
                
    } elsif ($opt eq "svsinfo") {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        SSCam_getsvsinfo($hash);
                
    } elsif ($opt eq "storedCredentials") {
	    if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        # Credentials abrufen
        my ($success, $username, $password) = SSCam_getcredentials($hash,0,"svs");
        unless ($success) {return "Credentials couldn't be retrieved successfully - see logfile"};
        
        my ($smtpsuccess, $smtpuname, $smtpword) = SSCam_getcredentials($hash,0,"smtp");
        my $so;
        if($smtpsuccess) {
            $so = "SMTP-Username: $smtpuname, SMTP-Password: $smtpword";
        } else {
            $so = "SMTP credentials are not set";
        }
        return "Stored Credentials to access surveillance station or DSM:\n".
               "=========================================================\n".
               "Username: $username, Password: $password\n".
               "\n".
               "Stored Credentials to access SMTP server:\n".
               "=========================================\n".
               "$so\n";
                
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
            $hash->{HELPER}{SNAPLIMIT} = AttrVal($name,"snapGalleryNumber",$SSCam_slim);
			my $htmlCode = SSCam_composegallery($name);
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
        # Schnappschußgalerie abrufen oder nur Info des letzten Snaps
		if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
        my ($slim,$ssize) = SSCam_snaplimsize($hash,1);	    # Force-Bit, es wird $hash->{HELPER}{GETSNAPGALLERY} gesetzt !
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
        # alte Readings außer state löschen
        my @allrds = keys%{$defs{$name}{READINGS}};
        foreach my $key(@allrds) {
            # Log3 ($name, 1, "DbRep $name - Reading Schlüssel: $key");
            delete($defs{$name}{READINGS}{$key}) if($key ne "state");
        }
		# "1" ist Statusbit für manuelle Abfrage, kein Einstieg in Pollingroutine
        SSCam_getcaminfoall($hash,1);
    
	} elsif ($opt =~ /versionNotes/) {
	  my $header  = "<b>Module release information</b><br>";
      my $header1 = "<b>Helpful hints</b><br>";
      my %hs;
	  
	  # Ausgabetabelle erstellen
	  my ($ret,$val0,$val1);
      my $i = 0;
	  
      $ret  = "<html>";
      
      # Hints
      if(!$arg || $arg =~ /hints/ || $arg =~ /[\d]+/) {
          $ret .= sprintf("<div class=\"makeTable wide\"; style=\"text-align:left\">$header1 <br>");
          $ret .= "<table class=\"block wide internals\">";
          $ret .= "<tbody>";
          $ret .= "<tr class=\"even\">";  
          if($arg && $arg =~ /[\d]+/) {
              my @hints = split(",",$arg);
              foreach (@hints) {
                  if(AttrVal("global","language","EN") eq "DE") {
                      $hs{$_} = $SSCam_vHintsExt_de{$_};
                  } else {
                      $hs{$_} = $SSCam_vHintsExt_en{$_};
                  }
              }                      
          } else {
              if(AttrVal("global","language","EN") eq "DE") {
                  %hs = %SSCam_vHintsExt_de;
              } else {
                  %hs = %SSCam_vHintsExt_en; 
              }
          }          
          $i = 0;
          foreach my $key (SSCam_sortVersion("desc",keys %hs)) {
              $val0 = $hs{$key};
              $ret .= sprintf("<td style=\"vertical-align:top\"><b>$key</b>  </td><td style=\"vertical-align:top\">$val0</td>" );
              $ret .= "</tr>";
              $i++;
              if ($i & 1) {
                  # $i ist ungerade
                  $ret .= "<tr class=\"odd\">";
              } else {
                  $ret .= "<tr class=\"even\">";
              }
          }
          $ret .= "</tr>";
          $ret .= "</tbody>";
          $ret .= "</table>";
          $ret .= "</div>";
      }
	  
      # Notes
      if(!$arg || $arg =~ /rel/) {
          $ret .= sprintf("<div class=\"makeTable wide\"; style=\"text-align:left\">$header <br>");
          $ret .= "<table class=\"block wide internals\">";
          $ret .= "<tbody>";
          $ret .= "<tr class=\"even\">";
          $i = 0;
          foreach my $key (SSCam_sortVersion("desc",keys %SSCam_vNotesExtern)) {
              ($val0,$val1) = split(/\s/,$SSCam_vNotesExtern{$key},2);
              $ret .= sprintf("<td style=\"vertical-align:top\"><b>$key</b>  </td><td style=\"vertical-align:top\">$val0  </td><td>$val1</td>" );
              $ret .= "</tr>";
              $i++;
              if ($i & 1) {
                  # $i ist ungerade
                  $ret .= "<tr class=\"odd\">";
              } else {
                  $ret .= "<tr class=\"even\">";
              }
          }
          $ret .= "</tr>";
          $ret .= "</tbody>";
          $ret .= "</table>";
          $ret .= "</div>";
	  }
      
      $ret .= "</html>";
					
	  return $ret;
  
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
  my $ret    = "";
  my $alias;
    
  return if(!$hash->{HELPER}{LINK} || ReadingsVal($d, "state", "") =~ /^dis.*/ || IsDisabled($name));
  
  # Definition Tasten
  my $imgblank      = "<img src=\"$FW_ME/www/images/sscam/black_btn_CAMBLANK.png\">";                   # nicht sichtbare Leertaste
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
  Log3($name, 4, "$name - SSCam_FWsummaryFn called - FW_wname: $FW_wname, device: $d, room: $room, attributes: $attr");
  
  # Javascript Bibliothek für Tooltips (http://www.walterzorn.de/tooltip/tooltip.htm#download) und Texte
  my $calias = $hash->{CAMNAME};                                            # Alias der Kamera
  my $ttjs   = "/fhem/pgm2/sscam_tooltip.js"; 
  my ($ttrefresh, $ttrecstart, $ttrecstop, $ttsnap, $ttcmdstop, $tthlsreact, $ttmjpegrun, $tthlsrun, $ttlrrun, $tth264run, $ttlmjpegrun, $ttlsnaprun);
  if(AttrVal("global","language","EN") =~ /EN/) {
      $ttrecstart = $SSCam_ttips_en{"ttrecstart"}; $ttrecstart =~ s/§NAME§/$calias/g;
      $ttrecstop  = $SSCam_ttips_en{"ttrecstop"}; $ttrecstop =~ s/§NAME§/$calias/g;
      $ttsnap     = $SSCam_ttips_en{"ttsnap"}; $ttsnap =~ s/§NAME§/$calias/g;
      $ttcmdstop  = $SSCam_ttips_en{"ttcmdstop"}; $ttcmdstop =~ s/§NAME§/$calias/g;
      $tthlsreact = $SSCam_ttips_en{"tthlsreact"}; $tthlsreact =~ s/§NAME§/$calias/g;
  } else {
      $ttrecstart = $SSCam_ttips_de{"ttrecstart"}; $ttrecstart =~ s/§NAME§/$calias/g;
      $ttrecstop  = $SSCam_ttips_de{"ttrecstop"}; $ttrecstop =~ s/§NAME§/$calias/g;
      $ttsnap     = $SSCam_ttips_de{"ttsnap"}; $ttsnap =~ s/§NAME§/$calias/g;
      $ttcmdstop  = $SSCam_ttips_de{"ttcmdstop"}; $ttcmdstop =~ s/§NAME§/$calias/g;
      $tthlsreact = $SSCam_ttips_de{"tthlsreact"}; $tthlsreact =~ s/§NAME§/$calias/g;
  }
  
  $ret .= "<script type=\"text/javascript\" src=\"$ttjs\"></script>";
  
  if($wltype eq "image") {
    if(ReadingsVal($name, "SVSversion", "8.2.3-5828") eq "8.2.3-5828" && ReadingsVal($name, "CamVideoType", "") !~ /MJPEG/) {             
      $ret .= "<td> <br> <b> Because SVS version 8.2.3-5828 is running you cannot see the MJPEG-Stream. Please upgrade to a higher SVS version ! </b> <br><br>";
    } else {
      $ret .= "<img src=$link $attr><br>";
    }
    $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdstop')\" onmouseover=\"Tip('$ttcmdstop')\" onmouseout=\"UnTip()\">$imgstop </a>";
    $ret .= $imgblank;  
    if($hash->{HELPER}{RUNVIEW} =~ /live_fw/) {
      if(ReadingsVal($d, "Record", "Stop") eq "Stop") {
        # Aufnahmebutton endlos Start
        $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdrecendless')\" onmouseover=\"Tip('$ttrecstart')\" onmouseout=\"UnTip()\">$imgrecendless </a>";
      } else {
        # Aufnahmebutton Stop
        $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdrecstop')\" onmouseover=\"Tip('$ttrecstop')\" onmouseout=\"UnTip()\">$imgrecstop </a>";
      }	      
    $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmddosnap')\" onmouseover=\"Tip('$ttsnap')\" onmouseout=\"UnTip()\">$imgdosnap </a>"; 
    }      
    $ret .= "<br>";
    if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($d, "CamAudioType", "Unknown") !~ /Unknown/) {
        $ret .= "<audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>
                 Your browser does not support the audio element.      
                 </audio>";
    }
    
  } elsif($wltype eq "iframe") {
    $ret .= "<iframe src=$link $attr controls autoplay>
             Iframes disabled
             </iframe>";
    $ret .= "<br>";
    $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdstop')\" onmouseover=\"Tip('$ttcmdstop')\" onmouseout=\"UnTip()\">$imgstop </a>";
    if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($d, "CamAudioType", "Unknown") !~ /Unknown/) {
        $ret .= "<audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>
                 Your browser does not support the audio element.      
                 </audio>";
    }
           
  } elsif($wltype eq "embed") {
    $ret .= "<embed src=$link $attr>";
    if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($d, "CamAudioType", "Unknown") !~ /Unknown/) {
        $ret .= "<audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>
                 Your browser does not support the audio element.      
                 </audio>";
    }
           
  } elsif($wltype eq "link") {
    $alias = $hash->{HELPER}{ALIAS};
    $ret .= "<a href=$link $attr>$alias</a><br>";     

  } elsif($wltype eq "base64img") {
    $alias = $hash->{HELPER}{ALIAS};
    $ret .= "<img $attr alt='$alias' src='data:image/jpeg;base64,$link'><br>";
    $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdstop')\" onmouseover=\"Tip('$ttcmdstop')\" onmouseout=\"UnTip()\">$imgstop </a>";
    $ret .= $imgblank;
    $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmddosnap')\" onmouseover=\"Tip('$ttsnap')\" onmouseout=\"UnTip()\">$imgdosnap </a>"; 
    
  } elsif($wltype eq "hls") {
    $alias = $hash->{HELPER}{ALIAS};
    $ret  .= "<video $attr controls autoplay>
             <source src=$link type=\"application/x-mpegURL\">
             <source src=$link type=\"video/MP2T\">
             Your browser does not support the video tag
             </video>";
    $ret .= "<br>";
    $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdstop')\" onmouseover=\"Tip('$ttcmdstop')\" onmouseout=\"UnTip()\">$imgstop </a>";
    $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdhlsreact')\" onmouseover=\"Tip('$tthlsreact')\" onmouseout=\"UnTip()\">$imghlsreact </a>";
    $ret .= $imgblank;
    if(ReadingsVal($d, "Record", "Stop") eq "Stop") {
        # Aufnahmebutton endlos Start
        $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdrecendless')\" onmouseover=\"Tip('$ttrecstart')\" onmouseout=\"UnTip()\">$imgrecendless </a>";
    } else {
        # Aufnahmebutton Stop
        $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdrecstop')\" onmouseover=\"Tip('$ttrecstop')\" onmouseout=\"UnTip()\">$imgrecstop </a>";
    }		
    $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmddosnap')\" onmouseover=\"Tip('$ttsnap')\" onmouseout=\"UnTip()\">$imgdosnap </a>";                 
  
  } elsif($wltype eq "video") {
    $ret .= "<video $attr controls autoplay> 
             <source src=$link type=\"video/mp4\"> 
             <source src=$link type=\"video/ogg\">
             <source src=$link type=\"video/webm\">
             Your browser does not support the video tag.
             </video>"; 
    $ret .= "<br>";
    $ret .= "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmdstop')\" onmouseover=\"Tip('$ttcmdstop')\" onmouseout=\"UnTip()\">$imgstop </a>";
    $ret .= "<br>";
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
  my $ret = "";
  
  $hash->{".setup"} = SSCam_FWconfCam($d,$room);
  if($hash->{".setup"} ne "") {
      $ret .= $hash->{".setup"};
  }
  
  $hash->{".ptzhtml"} = SSCam_ptzpanel($d,$d) if($hash->{".ptzhtml"} eq "");

  if($hash->{".ptzhtml"} ne "" && AttrVal($d,"ptzPanel_use",1)) {
      $ret .= $hash->{".ptzhtml"};
  } 

return $ret;
}

###############################################################################
#                        Aufruf Konfigseite Kamera
###############################################################################
sub SSCam_FWconfCam($$) {
  my ($name,$room) = @_; 
  my $hash    = $defs{$name};
  my $cip     = ReadingsVal("$name","CamIP","");
  my $svsip   = $hash->{SERVERADDR};
  my $svsport = $hash->{SERVERPORT};
  my $svsprot = $hash->{PROTOCOL};
  my $ttjs    = "/fhem/pgm2/sscam_tooltip.js"; 
  my $attr    = AttrVal($name, "htmlattr", "");
  my $alias   = AttrVal($name, "alias", $name);    
  my $winname = $name."_view";
  my $cicon   = 'edit_settings.svg';                                    # Icon für Cam/SVS Setup-Screen
  my $hicon   = 'info_info.svg';                                        # Icon für SVS Hilfeseite
  my $w       = 150;
  my ($ret,$cexpl,$hexpl) = ("","","");
  my ($cs,$bs,$ch,$bh,);
  
  if(SSCam_IsModelCam($hash)) {                                         # Camera Device
      return $ret if(!$cip);
      if(AttrVal("global","language","EN") =~ /DE/) {
          $cexpl = $SSCam_ttips_de{confcam}; $cexpl =~ s/§NAME§/$alias/g; $cexpl =~ s/\s+/&nbsp;/g;
      } else {
          $cexpl = $SSCam_ttips_en{confcam}; $cexpl =~ s/§NAME§/$alias/g; $cexpl =~ s/\s+/&nbsp;/g;
      }
      $cs = "window.open('http://$cip')";
  
  } else {                                                              # SVS-Device
      return $ret if(!$svsip);
      if(AttrVal("global","language","EN") =~ /DE/) {
          $cexpl = $SSCam_ttips_de{confsvs}; $cexpl =~ s/§NAME§/$alias/g; $cexpl =~ s/\s+/&nbsp;/g;
      } else {
          $cexpl = $SSCam_ttips_en{confsvs}; $cexpl =~ s/§NAME§/$alias/g; $cexpl =~ s/\s+/&nbsp;/g;
      }    
      $cs = "window.open('$svsprot://$svsip:$svsport/cam')";      
  }
  
  if(AttrVal("global","language","EN") =~ /DE/) {
      $hexpl = $SSCam_ttips_de{"helpsvs"}; $hexpl =~ s/\s/&nbsp;/g; 
      $ch    = "window.open('https://www.synology.com/de-de/knowledgebase/Surveillance/help')"; 
  } else {
      $hexpl = $SSCam_ttips_en{"helpsvs"}; $hexpl =~ s/\s/&nbsp;/g; 
      $ch = "window.open('https://www.synology.com/en-global/knowledgebase/Surveillance/help')"; 
  }   
  
  $cicon = FW_makeImage($cicon); $hicon = FW_makeImage($hicon);
  $bs    = "Tip(`$cexpl`)";
  $bh    = "Tip(`$hexpl`)";
  
  $ret .= "<script type=\"text/javascript\" src=\"$ttjs\"></script>";
  $ret .= "<style>TD.confcam {text-align: center; padding-left:1px; padding-right:1px; margin:0px;}</style>";
  $ret .= "<table class='roomoverview' width='$w' style='width:".$w."px'>";
  $ret .= '<tbody>';  
  $ret .= "<td>"; 
  
  $ret .= "<a onClick=$cs onmouseover=$bs onmouseout=\"UnTip()\"> $cicon </a>";  
  
  $ret .= "</td><td>";  
  
  $ret .= "<a onClick=$ch onmouseover=$bh onmouseout=\"UnTip()\"> $hicon </a>";  
 
  $ret .= "</td>";
  $ret .= "</tr>";
  $ret .= '</tbody>';
  $ret .= "</table>";  
  $ret .= "<br>";
  
return $ret;
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
         my ($emtxt,$teletxt) = ("","");
         SSCam_camstoprec("$name!_!$emtxt!_!$teletxt");
     }
         
     # Konfiguration der Synology Surveillance Station abrufen
     if (!$hash->{CREDENTIALS}) {
         Log3($name, 2, "$name - Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"");
     } else {
         readingsSingleUpdate($hash, "compstate", "true", 0);                                        # Anfangswert f. versionCheck setzen
         # allg. SVS-Eigenschaften abrufen
         SSCam_getsvsinfo($hash);
         
		 if(SSCam_IsModelCam($hash)) {
		     # Kameraspezifische Infos holen
             SSCam_getcaminfo($hash);           
             SSCam_getcapabilities($hash);
             SSCam_getStmUrlPath($hash);
             
			 # Preset/Patrollisten in Hash einlesen zur PTZ-Steuerung
             SSCam_getptzlistpreset($hash);
             SSCam_getptzlistpatrol($hash);

             # Schnappschußgalerie abrufen oder nur Info des letzten Snaps
             my ($slim,$ssize) = SSCam_snaplimsize($hash,1);   # Force-Bit, es wird $hash->{HELPER}{GETSNAPGALLERY} erzwungen !
             RemoveInternalTimer($hash, "SSCam_getsnapinfo"); 
             InternalTimer(gettimeofday()+0.9, "SSCam_getsnapinfo", "$name:$slim:$ssize", 0); 
		 }
         SSCam_versionCheck($hash);                                                                  # Einstieg in regelmäßigen Check Kompatibilität
     }
         
     # Subroutine Watchdog-Timer starten (sollen Cam-Infos regelmäßig abgerufen werden ?), verzögerter zufälliger Start 0-30s 
     RemoveInternalTimer($hash, "SSCam_wdpollcaminfo");
     InternalTimer(gettimeofday()+int(rand(30)), "SSCam_wdpollcaminfo", $hash, 0);
  
  } else {
      InternalTimer(gettimeofday()+3, "SSCam_initonboot", $hash, 0);
  }
return;
}

###############################################################################
#          Dauerschleife Kompatibilitätscheck SSCam <-> SVS
###############################################################################
sub SSCam_versionCheck($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  my $rc     = 21600;
  
  RemoveInternalTimer($hash, "SSCam_versionCheck");
  return if(IsDisabled($name));

  my $cs = ReadingsVal($name, "compstate", "true");
  if($cs eq "false") {
      Log3($name, 2, "$name - WARNING - The current/simulated SVS-version ".ReadingsVal($name, "SVSversion", "").
       " may be incompatible with SSCam version $hash->{HELPER}{VERSION}. ".
       "For further information execute \"get $name versionNotes 4\".");
  }
  
InternalTimer(gettimeofday()+$rc, "SSCam_versionCheck", $hash, 0);

return; 
}

###############################################################################
#          Liefert die bereinigte SVS-Version dreistellig xxx
###############################################################################
sub SSCam_myVersion($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  my $actvs  = 0; 

  my @vl = split (/-/,ReadingsVal($name, "SVSversion", ""),2);
  if(@vl) {
      $actvs = $vl[0];
      $actvs =~ s/\.//g;
  }
  
return $actvs; 
}

######################################################################################
#                            Username / Paßwort speichern
#   $cre = "svs"  -> Credentials für SVS und Cams
#   $cre = "smtp" -> Credentials für Mailversand
######################################################################################
sub SSCam_setcredentials ($$@) {
    my ($hash, $cre, @credentials) = @_;
    my $name                       = $hash->{NAME};
    my ($success, $credstr, $index, $retcode);
    my (@key,$len,$i);
    my $ao = ($cre eq "svs")?"credentials":"SMTPcredentials";
    
    
    $credstr = encode_base64(join(':', @credentials));
    
    # Beginn Scramble-Routine
    @key = qw(1 3 4 5 6 3 2 1 9);
    $len = scalar @key;  
    $i = 0;  
    $credstr = join "",  
            map { $i = ($i + 1) % $len;  
            chr((ord($_) + $key[$i]) % 256) } split //, $credstr; 
    # End Scramble-Routine    
       
    $index = $hash->{TYPE}."_".$hash->{NAME}."_".$ao;
    $retcode = setKeyValue($index, $credstr);
    
    if ($retcode) { 
        Log3($name, 2, "$name - Error while saving the Credentials - $retcode");
        $success = 0;
    } else {
        SSCam_getcredentials($hash,1,$cre);        # Credentials nach Speicherung lesen und in RAM laden ($boot=1), $ao = credentials oder SMTPcredentials
        $success = 1;
    }

return ($success);
}

######################################################################################
#                             Username / Paßwort abrufen
#   $cre = "svs"  -> Credentials für SVS und Cams
#   $cre = "smtp" -> Credentials für Mailversand
######################################################################################
sub SSCam_getcredentials ($$$) {
    my ($hash,$boot, $cre) = @_;
    my $name               = $hash->{NAME};
    my ($success, $username, $passwd, $index, $retcode, $credstr);
    my (@key,$len,$i);
    my $ao = ($cre eq "svs")?"credentials":"SMTPcredentials";
    my $pp = "";
    
    if ($boot) {
        # mit $boot=1 Credentials von Platte lesen und als scrambled-String in RAM legen
        $index = $hash->{TYPE}."_".$hash->{NAME}."_".$ao;
        ($retcode, $credstr) = getKeyValue($index);
    
        if ($retcode) {
            Log3($name, 2, "$name - Unable to read password from file: $retcode");
            $success = 0;
        }  

        if ($credstr) {
            if($cre eq "svs") {
                # beim Boot scrambled Credentials in den RAM laden
                $hash->{HELPER}{CREDENTIALS} = $credstr;
        
                # "Credentials" wird als Statusbit ausgewertet. Wenn nicht gesetzt -> Warnmeldung und keine weitere Verarbeitung
                $hash->{CREDENTIALS} = "Set";
                $success = 1;
            
            } elsif ($cre eq "smtp") {
                # beim Boot scrambled Credentials in den RAM laden
                $hash->{HELPER}{SMTPCREDENTIALS} = $credstr;
        
                # "Credentials" wird als Statusbit ausgewertet. Wenn nicht gesetzt -> Warnmeldung und keine weitere Verarbeitung
                $hash->{SMTPCREDENTIALS} = "Set";  
                $success = 1;                
            }
        }
    } else {
        # boot = 0 -> Credentials aus RAM lesen, decoden und zurückgeben
        if ($cre eq "svs") {
            $credstr = $hash->{HELPER}{CREDENTIALS};
        } elsif ($cre eq "smtp") {
            $pp = "SMTP";
            $credstr = $hash->{HELPER}{SMTPCREDENTIALS};
        }
        
        if($credstr) {
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
        
            Log3($name, 4, "$name - ".$pp."Credentials read from RAM: $username $logpw");
        
        } else {
            Log3($name, 2, "$name - ".$pp."Credentials not set in RAM !");
        }
    
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
    my $watchdogtimer = 60+rand(30);
    my $lang     = AttrVal("global","language","EN");
    
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
        
        my $lupd = ReadingsVal($name, "LastUpdateTime", "1970-01-01 / 01:00:00");
        my ($year,$month,$mday,$hour,$min,$sec);
        if ($lupd =~ /(\d+)\.(\d+)\.(\d+).*/) {
            ($mday, $month, $year, $hour, $min, $sec) = ($lupd =~ /(\d+)\.(\d+)\.(\d+) \/ (\d+):(\d+):(\d+)/);
        } else {
            ($year, $month, $mday, $hour, $min, $sec) = ($lupd =~ /(\d+)-(\d+)-(\d+) \/ (\d+):(\d+):(\d+)/);        
        }
        $lupd = fhemTimeLocal($sec, $min, $hour, $mday, $month-=1, $year-=1900);
        if( gettimeofday() > ($lupd + $pcia + 20) ) {
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
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        SSCam_setActiveToken($hash);
        SSCam_getapisites($hash);
    
	} else {
        InternalTimer(gettimeofday()+0.3, "SSCam_camstartrec", $hash);
    }
}

###############################################################################
#                           Kamera Aufnahme stoppen
###############################################################################
sub SSCam_camstoprec ($) {
    my ($str)                  = @_;
	my ($name,$emtxt,$teletxt) = split("!_!",$str);
	my $hash                   = $defs{$name};
    my $camname                = $hash->{CAMNAME};
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
        $hash->{HELPER}{LOGINRETRIES} = 0;
		if($emtxt || $teletxt) {
            $hash->{HELPER}{CANSENDREC} = 1 if($emtxt);                  # Versand Aufnahme soll per Email erfolgen
            $hash->{HELPER}{CANTELEREC} = 1 if($teletxt);                # Versand Aufnahme soll per TelegramBot erfolgen
            $hash->{HELPER}{SMTPRECMSG} = $emtxt if($emtxt);             # Text für Email-Versand
            $hash->{HELPER}{TELERECMSG} = $teletxt if($teletxt);         # Text für Telegram-Versand
        }
               
        SSCam_setActiveToken($hash);  
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+0.3, "SSCam_camstoprec", "$name!_!$emtxt!_!$teletxt", 0);
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
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        SSCam_setActiveToken($hash);
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
        $hash->{HELPER}{LOGINRETRIES} = 0;
	
        SSCam_setActiveToken($hash);    
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+0.5, "SSCam_cammotdetsc", $hash, 0);
    }
}

###############################################################################
#                       Kamera Schappschuß aufnehmen
#   $num    = Anzahl der Schnappschüsse
#   $lag    = Zeit zwischen zwei Schnappschüssen
#   $ncount = Anzahl der Schnappschüsse zum rnterzählen
###############################################################################
sub SSCam_camsnap($) {
    my ($str)            = @_;
	my ($name,$num,$lag,$ncount,$emtxt,$teletxt,$tac) = split("!_!",$str);
	my $hash             = $defs{$name};
    my $camname          = $hash->{CAMNAME};
    my $errorcode;
    my $error;
    
    $tac   = (defined $tac)?$tac:5000;
    my $ta = $hash->{HELPER}{TRANSACTION};
    
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
    
    if ($hash->{HELPER}{ACTIVE} eq "off" || ((defined $ta) && $ta == $tac)) { 
        # einen Schnappschuß aufnehmen              
        $hash->{OPMODE} = "Snap";
        $hash->{HELPER}{LOGINRETRIES} = 0;
        $hash->{HELPER}{CANSENDSNAP}  = 1 if($emtxt);                              # Versand Schnappschüsse soll per Email erfolgen
		$hash->{HELPER}{CANTELESNAP}  = 1 if($teletxt);                            # Versand Schnappschüsse soll per TelegramBot erfolgen
        $hash->{HELPER}{SNAPNUM}      = $num if($num);                             # Gesamtzahl der auszulösenden Schnappschüsse
        $hash->{HELPER}{SNAPLAG}      = $lag if($lag);                             # Zeitverzögerung zwischen zwei Schnappschüssen
        $hash->{HELPER}{SNAPNUMCOUNT} = $ncount if($ncount);                       # Restzahl der auszulösenden Schnappschüsse  (wird runtergezählt)
        $hash->{HELPER}{SMTPMSG}      = $emtxt if($emtxt);                         # Text für Email-Versand
        
        SSCam_setActiveToken($hash); 
        SSCam_getapisites($hash);
		
    } else {
        $tac = (defined $tac)?$tac:"";
        InternalTimer(gettimeofday()+0.3, "SSCam_camsnap", "$name!_!$num!_!$lag!_!$ncount!_!$emtxt!_!$teletxt!_!$tac", 0);
    }    
}

###############################################################################
#                     Kamera gemachte Aufnahme abrufen
###############################################################################
sub SSCam_getrec($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_getrec");
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
    
        Log3($name, 2, "$name - ERROR - Save Recording of Camera $camname in local file can't be executed - $error");
        
        return;
    }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {              
        $hash->{OPMODE} = "GetRec";
        $hash->{HELPER}{LOGINRETRIES} = 0;

        SSCam_setActiveToken($hash); 
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+0.3, "SSCam_getrec", $hash, 0);
    }    
}

###############################################################################
#                     Kamera gemachte Aufnahme lokal speichern
###############################################################################
sub SSCam_getsaverec($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_getsaverec");
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
    
        Log3($name, 2, "$name - ERROR - Save Recording of Camera $camname in local file can't be executed - $error");
        
        return;
    }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {              
        $hash->{OPMODE} = "SaveRec";
        $hash->{HELPER}{LOGINRETRIES} = 0;

        SSCam_setActiveToken($hash); 
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+0.3, "SSCam_getsaverec", $hash, 0);
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
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        SSCam_setActiveToken($hash);
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
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        SSCam_setActiveToken($hash);
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
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        SSCam_setActiveToken($hash);
        
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
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        SSCam_setActiveToken($hash);
        
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
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        SSCam_setActiveToken($hash);
        
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
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        SSCam_setActiveToken($hash);
        
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+1.2, "SSCam_setHome", $hash, 0);
    }    
}

###############################################################################
#                       PIR Sensor aktivieren/deaktivieren
###############################################################################
sub SSCam_piract($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_piract");
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
        $hash->{OPMODE} = "piract";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        SSCam_setActiveToken($hash);
        
        SSCam_getapisites($hash);
		
    } else {
        InternalTimer(gettimeofday()+1.2, "SSCam_piract", $hash, 0);
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
        $error = SSCam_experror($hash,$errorcode);

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
		$hash->{HELPER}{LOGINRETRIES} = 0; 
		# erzwingen die Camid zu ermitteln und bei login-Fehler neue SID zu holen
		delete $hash->{CAMID};  
        
        SSCam_setActiveToken($hash);
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
        $error = SSCam_experror($hash,$errorcode);

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
		$hash->{HELPER}{LOGINRETRIES} = 0;   
        
        SSCam_setActiveToken($hash);
        SSCam_getapisites($hash);
    
	} else {
        InternalTimer(gettimeofday()+0.3, "SSCam_hlsactivate", $hash, 0);
    }    
}

###############################################################################
#                         Kameras mit Autocreate erstellen
###############################################################################
sub SSCam_setAutocreate($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $errorcode;
    my $error;
    
    RemoveInternalTimer($hash, "SSCam_setAutocreate");
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
    
        Log3($name, 2, "$name - ERROR - autocreate cameras - $error");
        return;
    }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {            
        $hash->{OPMODE} = "Autocreate";
		$hash->{HELPER}{LOGINRETRIES} = 0;   
        
        SSCam_setActiveToken($hash);
        SSCam_getapisites($hash);
    
	} else {
        InternalTimer(gettimeofday()+2.1, "SSCam_setAutocreate", $hash, 0);
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
        $error = SSCam_experror($hash,$errorcode);

        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        Log3($name, 2, "$name - ERROR - HLS-Stream of Camera $camname can't be activated - $error");
        return;
    }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {             
        $hash->{OPMODE} = "reactivate_hls";
		$hash->{HELPER}{LOGINRETRIES} = 0;   
        
        SSCam_setActiveToken($hash);
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
        $hash->{OPMODE}               = "stopliveview";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        SSCam_setActiveToken($hash);
        
        # Link aus Helper-hash löschen
        delete $hash->{HELPER}{LINK};
        delete $hash->{HELPER}{AUDIOLINK};
		delete $hash->{HELPER}{ACTSTRM};    # sprechender Name des laufenden Streamtyps für SSCamSTRM
        
        # Reading LiveStreamUrl löschen
        delete($defs{$name}{READINGS}{LiveStreamUrl}) if ($defs{$name}{READINGS}{LiveStreamUrl});
        
        readingsSingleUpdate($hash,"state","stopview",1);           
        
        if($hash->{HELPER}{WLTYPE} eq "hls") {
            # HLS Stream war aktiv, Streaming beenden
            $hash->{OPMODE} = "stopliveview_hls";
            SSCam_getapisites($hash);
        } else {
            # kein HLS Stream
			SSCam_refresh($hash,0,1,1);    # kein Room-Refresh, SSCam-state-Event, SSCamSTRM-Event
            SSCam_delActiveToken($hash);
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
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        SSCam_setActiveToken($hash);
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
     
        $hash->{OPMODE} = $hash->{HELPER}{PTZACTION};
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        SSCam_setActiveToken($hash);
 
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
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        SSCam_setActiveToken($hash);
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
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {
        # eine Kamera aktivieren
        Log3($name, 4, "$name - Enable Camera $camname");
                        
        $hash->{OPMODE} = "Enable";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        SSCam_setActiveToken($hash);
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
    
    if ($hash->{HELPER}{ACTIVE} eq "off" and ReadingsVal("$name", "Record", "Start") ne "Start") {
        # eine Kamera deaktivieren
        Log3($name, 4, "$name - Disable Camera $camname");
                        
        $hash->{OPMODE} = "Disable";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        SSCam_setActiveToken($hash);
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
        my ($slim,$ssize) = SSCam_snaplimsize($hash,1);       # Force-Bit, es wird $hash->{HELPER}{GETSNAPGALLERY} erzwungen !
        RemoveInternalTimer($hash, "SSCam_getsnapinfo"); 
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
#
#  $slim  = Anzahl der abzurufenden Snapinfos (snaps)
#  $ssize = Snapgröße
#  $tac   = Transaktionscode (für gemeinsamen Versand)
###########################################################################
sub SSCam_getsnapinfo ($) {
    my ($str)   = @_;
	my ($name,$slim,$ssize,$tac) = split(":",$str);
	my $hash = $defs{$name};
    my $camname  = $hash->{CAMNAME};
    
    $tac   = (defined $tac)?$tac:5000;
    my $ta = $hash->{HELPER}{TRANSACTION};
    
    RemoveInternalTimer($hash, "SSCam_getsnapinfo"); 
    return if(IsDisabled($name));
    
    if ($hash->{HELPER}{ACTIVE} eq "off" || ((defined $ta) && $ta == $tac)) {               
        $hash->{OPMODE}               = "getsnapinfo";
		$hash->{OPMODE}               = "getsnapgallery" if(exists($hash->{HELPER}{GETSNAPGALLERY}));
        $hash->{HELPER}{LOGINRETRIES} = 0;
		$hash->{HELPER}{SNAPLIMIT}    = $slim;   # 0-alle Snapshots werden abgerufen und ausgewertet, sonst $slim
		$hash->{HELPER}{SNAPIMGSIZE}  = $ssize;  # 0-Do not append image, 1-Icon size, 2-Full size
		$hash->{HELPER}{KEYWORD}      = $camname;
		
        SSCam_setActiveToken($hash);
        SSCam_getapisites($hash);
		
    } else {
        $tac = (defined $tac)?$tac:"";
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
        $hash->{OPMODE}               = "getsnapfilename";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        SSCam_setActiveToken($hash);
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
        $hash->{OPMODE}               = "getsvsinfo";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        SSCam_setActiveToken($hash);
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
        $hash->{OPMODE}               = "sethomemode";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        SSCam_setActiveToken($hash);
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
        $hash->{OPMODE}               = "setoptpar";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        SSCam_setActiveToken($hash);
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
        $hash->{OPMODE}               = "gethomemodestate";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        SSCam_setActiveToken($hash);
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
        $hash->{OPMODE}               = "getsvslog";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        SSCam_setActiveToken($hash);
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
        
        SSCam_setActiveToken($hash);
        SSCam_logout($hash);
		
    } else {
        InternalTimer(gettimeofday()+1.1, "SSCam_sessionoff", $hash, 0);
    }
}

###########################################################################
#               Kamera allgemeine Informationen abrufen (Get) 
###########################################################################
sub SSCam_getcaminfo($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    
    RemoveInternalTimer($hash, "SSCam_getcaminfo");
    return if(IsDisabled($name));

    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE}               = "Getcaminfo";
        $hash->{HELPER}{LOGINRETRIES} = 0;	
        
        SSCam_setActiveToken($hash); 
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
    my $apivideostmsmaxver = $hash->{HELPER}{APIVIDEOSTMSMAXVER};
    return if(IsDisabled($name));  
    
    if(!$apivideostmsmaxver) {
        # keine API "SYNO.SurveillanceStation.VideoStream" mehr ab API v2.8
        readingsSingleUpdate($hash,"CamStreamFormat", "no API", 1);
        return;
    }
    
    if ($hash->{HELPER}{ACTIVE} eq "off") {                        
        $hash->{OPMODE}               = "getstreamformat";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        SSCam_setActiveToken($hash); 
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
        $hash->{OPMODE}               = "getStmUrlPath";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        SSCam_setActiveToken($hash);
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
        $hash->{OPMODE}               = "geteventlist";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        SSCam_setActiveToken($hash);
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
        $hash->{OPMODE}               = "getmotionenum";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        SSCam_setActiveToken($hash);
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
        $hash->{OPMODE}               = "Getcapabilities";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        SSCam_setActiveToken($hash);
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
        $hash->{OPMODE}               = "Getptzlistpreset";
        $hash->{HELPER}{LOGINRETRIES} = 0;
		
        SSCam_setActiveToken($hash);
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
        $hash->{OPMODE}               = "Getptzlistpatrol";
		$hash->{HELPER}{LOGINRETRIES} = 0;
        
        SSCam_setActiveToken($hash);
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
   my $apirec      = $hash->{HELPER}{APIREC};
   my $proto       = $hash->{PROTOCOL};   
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
   $url = "$proto://$serveraddr:$serverport/webapi/query.cgi?api=$apiinfo&method=Query&version=1&query=$apiauth,$apiextrec,$apicam,$apitakesnap,$apiptz,$apipreset,$apisvsinfo,$apicamevent,$apievent,$apivideostm,$apiextevt,$apistm,$apihm,$apilog,$apiaudiostm,$apivideostms,$apirec";

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
   my $apirec      = $hash->{HELPER}{APIREC};
   my ($apicammaxver,$apicampath);
  
    if ($err ne "") {
	    # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
        Log3($name, 2, "$name - error while requesting ".$param->{url}." - $err");
       
        readingsSingleUpdate($hash, "Error", $err, 1);

        # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
        SSCam_delActiveToken($hash);
        return;
		
    } elsif ($myjson ne "") {          
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, my $success) = SSCam_evaljson($hash,$myjson);
        
        unless ($success) {
            SSCam_delActiveToken($hash);
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
            
          # Pfad und Maxversion von "SYNO.SurveillanceStation.Recording" ermitteln
            my $apirecpath = $data->{'data'}->{$apirec}->{'path'};
            $apirecpath =~ tr/_//d if (defined($apirecpath));
            my $apirecmaxver = $data->{'data'}->{$apirec}->{'maxVersion'}; 
       
   	        $logstr = defined($apirecpath) ? "Path of $apirec selected: $apirecpath" : "Path of $apirec undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($apirecmaxver) ? "MaxVersion of $apirec selected: $apirecmaxver" : "MaxVersion of $apirec undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
		
            # aktuelle oder simulierte SVS-Version für Fallentscheidung setzen
            no warnings 'uninitialized'; 
            my $major = $hash->{HELPER}{SVSVERSION}{MAJOR};
            my $minor = $hash->{HELPER}{SVSVERSION}{MINOR};
			my $small = $hash->{HELPER}{SVSVERSION}{SMALL};
            my $build = $hash->{HELPER}{SVSVERSION}{BUILD}; 
            my $actvs = $major.$minor.$small.$build;
            my $avsc  = $major.$minor.$small;                                # Variable zum Version Kompatibilitätscheck
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
                } elsif ($actvs =~ /^815/) {
                    $apicammaxver = 9;
                    Log3($name, 4, "$name - MaxVersion of $apicam adapted to: $apicammaxver");
                    $apiauthmaxver = 6;
                    Log3($name, 4, "$name - MaxVersion of $apiauth adapted to: $apiauthmaxver");
                    $apiextrecmaxver = 3;
                    Log3($name, 4, "$name - MaxVersion of $apiextrec adapted to: $apiextrecmaxver");
                    $apiptzmaxver    = 5;
                    Log3($name, 4, "$name - MaxVersion of $apiptz adapted to: $apiptzmaxver");                               
                } elsif ($actvs =~ /^820/) {
                    # ab API v2.8 kein "SYNO.SurveillanceStation.VideoStream", "SYNO.SurveillanceStation.AudioStream",
                    # "SYNO.SurveillanceStation.Streaming" mehr enthalten
                    $apivideostmsmaxver = 0;
                    Log3($name, 4, "$name - MaxVersion of $apivideostms adapted to: $apivideostmsmaxver");
                    $apiaudiostmmaxver = 0;
                    Log3($name, 4, "$name - MaxVersion of $apiaudiostm adapted to: $apiaudiostmmaxver");                              
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
            $hash->{HELPER}{APIAUDIOSTMPATH}    = $apiaudiostmpath?$apiaudiostmpath:"undefinded";
            $hash->{HELPER}{APIAUDIOSTMMAXVER}  = $apiaudiostmmaxver?$apiaudiostmmaxver:0;
            $hash->{HELPER}{APIEXTEVTPATH}      = $apiextevtpath;
            $hash->{HELPER}{APIEXTEVTMAXVER}    = $apiextevtmaxver;
            $hash->{HELPER}{APISTMPATH}         = $apistmpath;
            $hash->{HELPER}{APISTMMAXVER}       = $apistmmaxver;
            $hash->{HELPER}{APIHMPATH}          = $apihmpath;
            $hash->{HELPER}{APIHMMAXVER}        = $apihmmaxver;
            $hash->{HELPER}{APILOGPATH}         = $apilogpath;
            $hash->{HELPER}{APILOGMAXVER}       = $apilogmaxver;
            $hash->{HELPER}{APIVIDEOSTMSPATH}   = $apivideostmspath?$apivideostmspath:"undefinded";
            $hash->{HELPER}{APIVIDEOSTMSMAXVER} = $apivideostmsmaxver?$apivideostmsmaxver:0;
            $hash->{HELPER}{APIRECPATH}         = $apirecpath;
            $hash->{HELPER}{APIRECMAXVER}       = $apirecmaxver;
            
       
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
            SSCam_delActiveToken($hash);
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
   
   if(SSCam_IsModelCam($hash) || $hash->{OPMODE} eq "Autocreate") {
       # Normalverarbeitung für Cams oder Autocreate Cams
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
   my $proto        = $hash->{PROTOCOL};
   
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
  
   $url = "$proto://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=List&basic=true&streamInfo=true&camStm=true&_sid=\"$sid\"";
   if ($apicammaxver >= 9) {
       $url = "$proto://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=\"List\"&basic=true&streamInfo=true&camStm=0&_sid=\"$sid\"";
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
   my $OpMode            = $hash->{OPMODE};   
   my ($data,$success,$error,$errorcode,$camid);
   my ($i,$n,$id,$errstate,$camdef,$nrcreated);
   my $cdall = "";
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
           SSCam_delActiveToken($hash);
           return; 
       }
        
       $data = decode_json($myjson);
        
       # lesbare Ausgabe der decodierten JSON-Daten
       Log3($name, 5, "$name - JSON returned: ". Dumper $data);
   
       $success = $data->{'success'};
                
       if ($success) {
           # die Liste aller Kameras konnte ausgelesen werden	   
           ($i,$nrcreated) = (0,0);
         
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
               
               if ($OpMode eq "Autocreate") {
                   # Cam autocreate
                   ($err,$camdef) = SSCam_Autocreate($hash,$n);
                   if($camdef) {
                       $cdall = $cdall.($cdall?", ":"").$camdef;
                       $nrcreated++;
                   }
                   $errstate = $err if($err);  
               }
               
           }
           
           if ($OpMode eq "Autocreate") {
               # Cam autocreate
               Log3($name, 3, "$name - Cameras defined by autocreate: $cdall") if($cdall);
               
               $errstate = $errstate?$errstate:"none";
               readingsBeginUpdate($hash); 
               readingsBulkUpdate($hash,"NumberAutocreatedCams",$nrcreated);
               readingsBulkUpdate($hash,"Errorcode","none");
               readingsBulkUpdate($hash,"Error",$errstate);
               readingsBulkUpdate($hash,"state","autocreate finished");
               readingsEndUpdate($hash, 1);
           
               CommandSave(undef, undef) if($errstate eq "none" && $nrcreated && AttrVal("global","autosave", 1));

		       # Freigabe Funktionstoken
               SSCam_delActiveToken($hash);
               return;
           }
             
           # Ist der gesuchte Kameraname im Hash enhalten (in SVS eingerichtet ?)
           if (exists($allcams{$camname})) {
               $camid = $allcams{$camname};
               $hash->{CAMID} = $camid;
                 
               Log3($name, 4, "$name - Detection Camid successful - $camname ID: $camid");
           
		   } else {
               # Kameraname nicht gefunden, id = ""
               readingsBeginUpdate($hash);
               readingsBulkUpdate($hash,"Errorcode","none");
               readingsBulkUpdate($hash,"Error","Camera(ID) not found in Surveillance Station");
               readingsEndUpdate($hash, 1);
                                  
               Log3($name, 2, "$name - ERROR - Cameraname $camname wasn't found in Surveillance Station. Check Userrights, Cameraname and Spelling");		   
               SSCam_delActiveToken($hash);
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
               SSCam_delActiveToken($hash);
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
   my $apirec             = $hash->{HELPER}{APIREC};
   my $apirecpath         = $hash->{HELPER}{APIRECPATH};
   my $apirecmaxver       = $hash->{HELPER}{APIRECMAXVER};   
   my $sid                = $hash->{HELPER}{SID};
   my $OpMode             = $hash->{OPMODE};
   my $camid              = $hash->{CAMID};
   my $proto              = $hash->{PROTOCOL};
   my $serveraddr         = $hash->{SERVERADDR};
   my $serverport         = $hash->{SERVERPORT};
   my ($exturl,$winname,$attr,$room,$param);
   my ($url,$snapid,$httptimeout,$expmode,$motdetsc);
       
   Log3($name, 4, "$name - --- Begin Function $OpMode nonblocking ---");

   $httptimeout = AttrVal($name, "httptimeout", 4);
   $httptimeout = $httptimeout+90 if($OpMode =~ /setoptpar|Disable/);                          # setzen der Optimierungsparameter/Disable dauert lange !
   
   Log3($name, 5, "$name - HTTP-Call will be done with httptimeout-Value: $httptimeout s");
   
   if ($OpMode eq "Start") {
      $url = "$proto://$serveraddr:$serverport/webapi/$apiextrecpath?api=$apiextrec&method=Record&version=$apiextrecmaxver&cameraId=$camid&action=start&_sid=\"$sid\"";
      if($apiextrecmaxver >= 3) {
          $url = "$proto://$serveraddr:$serverport/webapi/$apiextrecpath?api=$apiextrec&method=Record&version=$apiextrecmaxver&cameraIds=$camid&action=start&_sid=\"$sid\"";
      }
   } elsif ($OpMode eq "Stop") {
      $url = "$proto://$serveraddr:$serverport/webapi/$apiextrecpath?api=$apiextrec&method=Record&version=$apiextrecmaxver&cameraId=$camid&action=stop&_sid=\"$sid\"";
      if($apiextrecmaxver >= 3) {
          $url = "$proto://$serveraddr:$serverport/webapi/$apiextrecpath?api=$apiextrec&method=Record&version=$apiextrecmaxver&cameraIds=$camid&action=stop&_sid=\"$sid\"";
      }   
   
   } elsif ($OpMode eq "Snap") {
      # ein Schnappschuß wird ausgelöst
      $url = "$proto://$serveraddr:$serverport/webapi/$apitakesnappath?api=\"$apitakesnap\"&dsId=\"0\"&method=\"TakeSnapshot\"&version=\"$apitakesnapmaxver\"&camId=\"$camid\"&blSave=\"true\"&_sid=\"$sid\"";
      readingsSingleUpdate($hash,"state", "snap", 1); 
   
   } elsif ($OpMode eq "SaveRec" || $OpMode eq "GetRec") {
      # eine Aufnahme soll in lokalem File (.mp4) gespeichert werden
      my $recid = ReadingsVal("$name", "CamLastRecId", 0);
      if($recid) {
          $url = "$proto://$serveraddr:$serverport/webapi/$apirecpath?api=\"$apirec\"&id=$recid&mountId=0&version=\"$apirecmaxver\"&method=\"Download\"&_sid=\"$sid\"";
      } else {
          Log3($name, 2, "$name - WARNING - Can't fetch recording due to no recording available.");
          SSCam_delActiveToken($hash);
          return;      
      }
      
   } elsif ($OpMode eq "getsnapinfo" || $OpMode eq "getsnapgallery") {
      # Informationen über den letzten oder mehrere Schnappschüsse ermitteln
	  my $limit   = $hash->{HELPER}{SNAPLIMIT};
	  my $imgsize = $hash->{HELPER}{SNAPIMGSIZE};
	  my $keyword = $hash->{HELPER}{KEYWORD};
      my $snapid  = ReadingsVal("$name", "LastSnapId", " ");
      if($OpMode eq "getsnapinfo" && $snapid =~/\d+/) {
          # getsnapinfo UND Reading LastSnapId gesetzt
	      Log3($name,4, "$name - Call getsnapinfo with params: Image numbers => $limit, Image size => $imgsize, Id => $snapid");
          $url = "$proto://$serveraddr:$serverport/webapi/$apitakesnappath?api=\"$apitakesnap\"&method=\"List\"&version=\"$apitakesnapmaxver\"&idList=\"$snapid\"&imgSize=\"$imgsize\"&limit=\"$limit\"&_sid=\"$sid\"";      
      } else {
          # snapgallery oder kein Reading LastSnapId gesetzt
	      Log3($name,4, "$name - Call getsnapinfo with params: Image numbers => $limit, Image size => $imgsize, Keyword => $keyword");
          $url = "$proto://$serveraddr:$serverport/webapi/$apitakesnappath?api=\"$apitakesnap\"&method=\"List\"&version=\"$apitakesnapmaxver\"&keyword=\"$keyword\"&imgSize=\"$imgsize\"&limit=\"$limit\"&_sid=\"$sid\"";
      }
      
   } elsif ($OpMode eq "getsnapfilename") {
      # der Filename der aktuellen Schnappschuß-ID wird ermittelt
      $snapid = ReadingsVal("$name", "LastSnapId", "");
      Log3($name, 4, "$name - Get filename of present Snap-ID $snapid");
      $url = "$proto://$serveraddr:$serverport/webapi/$apitakesnappath?api=\"$apitakesnap\"&method=\"List\"&version=\"$apitakesnapmaxver\"&imgSize=\"0\"&idList=\"$snapid\"&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "gopreset") {
      # Preset wird angefahren
      $apiptzmaxver = ($apiptzmaxver >= 5)?4:$apiptzmaxver;
	  $url = "$proto://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"GoPreset\"&position=\"$hash->{HELPER}{ALLPRESETS}{$hash->{HELPER}{GOPRESETNAME}}\"&cameraId=\"$camid\"&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "getPresets") {
      # Liste der Presets abrufen
	  $url = "$proto://$serveraddr:$serverport/webapi/$apipresetpath?api=\"$apipreset\"&version=\"$apipresetmaxver\"&method=\"Enum\"&cameraId=\"$camid\"&_sid=\"$sid\""; 
   
   } elsif ($OpMode eq "piract") {
      # PIR Sensor aktivieren/deaktivieren
      my $piract = $hash->{HELPER}{PIRACT};
      $url = "$proto://$serveraddr:$serverport/webapi/$apicameventpath?api=\"$apicamevent\"&version=\"$apicameventmaxver\"&method=\"PDParamSave\"&keep=true&source=$piract&camId=\"$camid\"&_sid=\"$sid\""; 
   
   } elsif ($OpMode eq "setPreset") {
      # einen Preset setzen
      my $pnumber = $hash->{HELPER}{PNUMBER};
      my $pname   = $hash->{HELPER}{PNAME};
      my $pspeed  = $hash->{HELPER}{PSPEED};
      if ($pspeed) {
	      $url = "$proto://$serveraddr:$serverport/webapi/$apipresetpath?api=\"$apipreset\"&version=\"$apipresetmaxver\"&method=\"SetPreset\"&position=$pnumber&name=\"$pname\"&speed=\"$pspeed\"&cameraId=\"$camid\"&_sid=\"$sid\""; 
      } else {
	      $url = "$proto://$serveraddr:$serverport/webapi/$apipresetpath?api=\"$apipreset\"&version=\"$apipresetmaxver\"&method=\"SetPreset\"&position=$pnumber&name=\"$pname\"&cameraId=\"$camid\"&_sid=\"$sid\"";       
      }
      
   } elsif ($OpMode eq "delPreset") {
      # einen Preset löschen
	  $url = "$proto://$serveraddr:$serverport/webapi/$apipresetpath?api=\"$apipreset\"&version=\"$apipresetmaxver\"&method=\"DelPreset\"&position=\"$hash->{HELPER}{ALLPRESETS}{$hash->{HELPER}{DELPRESETNAME}}\"&cameraId=\"$camid\"&_sid=\"$sid\""; 
   
   } elsif ($OpMode eq "setHome") {
      # aktuelle Position als Home setzen
      if($hash->{HELPER}{SETHOME} eq "---currentPosition---") {
          $url = "$proto://$serveraddr:$serverport/webapi/$apipresetpath?api=\"$apipreset\"&version=\"$apipresetmaxver\"&method=\"SetHome\"&cameraId=\"$camid\"&_sid=\"$sid\""; 
      } else {
          my $bindpos = $hash->{HELPER}{ALLPRESETS}{$hash->{HELPER}{SETHOME}};
	      $url = "$proto://$serveraddr:$serverport/webapi/$apipresetpath?api=\"$apipreset\"&version=\"$apipresetmaxver\"&method=\"SetHome\"&bindPosition=\"$bindpos\"&cameraId=\"$camid\"&_sid=\"$sid\""; 
      }
      
   } elsif ($OpMode eq "startTrack") {
      # Object Tracking einschalten
	  $url = "$proto://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"ObjTracking\"&cameraId=\"$camid\"&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "stopTrack") {
      # Object Tracking stoppen
	  $url = "$proto://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"ObjTracking\"&moveType=\"Stop\"&cameraId=\"$camid\"&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "runpatrol") {
      # eine Überwachungstour starten
      $url = "$proto://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"RunPatrol\"&patrolId=\"$hash->{HELPER}{ALLPATROLS}{$hash->{HELPER}{GOPATROLNAME}}\"&cameraId=\"$camid\"&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "goabsptz") {
      $url = "$proto://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"AbsPtz\"&cameraId=\"$camid\"&posX=\"$hash->{HELPER}{GOPTZPOSX}\"&posY=\"$hash->{HELPER}{GOPTZPOSY}\"&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "movestart") {
      $url = "$proto://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"Move\"&cameraId=\"$camid\"&direction=\"$hash->{HELPER}{GOMOVEDIR}\"&speed=\"3\"&moveType=\"Start\"&_sid=\"$sid\"";
      
   } elsif ($OpMode eq "movestop") {
      Log3($name, 4, "$name - Stop Camera $hash->{CAMNAME} moving to direction \"$hash->{HELPER}{GOMOVEDIR}\" now");
      $url = "$proto://$serveraddr:$serverport/webapi/$apiptzpath?api=\"$apiptz\"&version=\"$apiptzmaxver\"&method=\"Move\"&cameraId=\"$camid\"&direction=\"$hash->{HELPER}{GOMOVEDIR}\"&moveType=\"Stop\"&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "Enable") {
      $url = "$proto://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=Enable&cameraIds=$camid&_sid=\"$sid\"";     
      if($apicammaxver >= 9) {
	      $url = "$proto://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&version=$apicammaxver&method=\"Enable\"&idList=\"$camid\"&_sid=\"$sid\"";     
	  }
   
   } elsif ($OpMode eq "Disable") {
      $url = "$proto://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=Disable&cameraIds=$camid&_sid=\"$sid\"";     
      if($apicammaxver >= 9) {
	      $url = "$proto://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&version=$apicammaxver&method=\"Disable\"&idList=\"$camid\"&_sid=\"$sid\"";     
	  }
	  
   } elsif ($OpMode eq "sethomemode") {
      my $sw = $hash->{HELPER}{HOMEMODE};     # HomeMode on,off
	  $sw  = ($sw eq "on")?"true":"false";
      $url = "$proto://$serveraddr:$serverport/webapi/$apihmpath?on=$sw&api=$apihm&method=Switch&version=$apihmmaxver&_sid=\"$sid\"";     
   
   } elsif ($OpMode eq "gethomemodestate") {
      $url = "$proto://$serveraddr:$serverport/webapi/$apihmpath?api=$apihm&method=GetInfo&version=$apihmmaxver&_sid=\"$sid\"";     
   
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
	  
	  $url = "$proto://$serveraddr:$serverport/webapi/$apilogpath?api=$apilog&version=\"2\"&method=\"List\"&time2String=\"no\"&level=\"$sev\"&limit=\"$lim\"&keyword=\"$mco\"&_sid=\"$sid\"";     

	  delete($hash->{HELPER}{LISTLOGSEVERITY});
	  delete($hash->{HELPER}{LISTLOGLIMIT});
	  delete($hash->{HELPER}{LISTLOGMATCH});
	  
   } elsif ($OpMode eq "getsvsinfo") {
      $url = "$proto://$serveraddr:$serverport/webapi/$apisvsinfopath?api=\"$apisvsinfo\"&version=\"$apisvsinfomaxver\"&method=\"GetInfo\"&_sid=\"$sid\"";   
   
   } elsif ($OpMode eq "setoptpar") {
      my $mirr = $hash->{HELPER}{MIRROR}?$hash->{HELPER}{MIRROR}:ReadingsVal("$name","CamVideoMirror","");
	  my $flip = $hash->{HELPER}{FLIP}?$hash->{HELPER}{FLIP}:ReadingsVal("$name","CamVideoFlip","");
	  my $rot  = $hash->{HELPER}{ROTATE}?$hash->{HELPER}{ROTATE}:ReadingsVal("$name","CamVideoRotate","");
	  my $ntp  = $hash->{HELPER}{NTPSERV}?$hash->{HELPER}{NTPSERV}:ReadingsVal("$name","CamNTPServer","");
	  my $clst = $hash->{HELPER}{CHKLIST}?$hash->{HELPER}{CHKLIST}:"";
	  $apicammaxver = ($apicammaxver >= 9)?8:$apicammaxver;
      $url = "$proto://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&version=\"$apicammaxver\"&method=\"SaveOptimizeParam\"&vdoMirror=$mirr&vdoRotation=$rot&vdoFlip=$flip&timeServer=\"$ntp\"&camParamChkList=$clst&cameraIds=\"$camid\"&_sid=\"$sid\"";  
             
   } elsif ($OpMode eq "Getcaminfo") {
      $apicammaxver = ($apicammaxver >= 9)?8:$apicammaxver;
      $url = "$proto://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&version=\"$apicammaxver\"&method=\"GetInfo\"&cameraIds=\"$camid\"&deviceOutCap=\"true\"&streamInfo=\"true\"&ptz=\"true\"&basic=\"true\"&camAppInfo=\"true\"&optimize=\"true\"&fisheye=\"true\"&eventDetection=\"true\"&_sid=\"$sid\"";   
   
   } elsif ($OpMode eq "getStmUrlPath") {
      $url = "$proto://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&version=\"$apicammaxver\"&method=\"GetStmUrlPath\"&cameraIds=\"$camid\"&_sid=\"$sid\"";   
      if($apicammaxver >= 9) {
	      $url = "$proto://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&method=\"GetLiveViewPath\"&version=$apicammaxver&idList=\"$camid\"&_sid=\"$sid\"";   
	  }
   
   } elsif ($OpMode eq "geteventlist") {
      # Abruf der Events einer Kamera
      $url = "$proto://$serveraddr:$serverport/webapi/$apieventpath?api=\"$apievent\"&version=\"$apieventmaxver\"&method=\"List\"&cameraIds=\"$camid\"&locked=\"0\"&blIncludeSnapshot=\"false\"&reason=\"\"&limit=\"2\"&includeAllCam=\"false\"&_sid=\"$sid\"";   
   
   } elsif ($OpMode eq "Getptzlistpreset") {
      $url = "$proto://$serveraddr:$serverport/webapi/$apiptzpath?api=$apiptz&version=$apiptzmaxver&method=ListPreset&cameraId=$camid&_sid=\"$sid\"";   
   
   } elsif ($OpMode eq "Getcapabilities") {
      # Capabilities einer Cam werden abgerufen
	  $apicammaxver = ($apicammaxver >= 9)?8:$apicammaxver;
      $url = "$proto://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=\"GetCapabilityByCamId\"&cameraId=$camid&_sid=\"$sid\"";    
   
   } elsif ($OpMode eq "Getptzlistpatrol") {
      # PTZ-ListPatrol werden abgerufen
      $url = "$proto://$serveraddr:$serverport/webapi/$apiptzpath?api=$apiptz&version=$apiptzmaxver&method=ListPatrol&cameraId=$camid&_sid=\"$sid\"";   
   
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
      $url = "$proto://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&version=\"$apicammaxver\"&method=\"SaveOptimizeParam\"&cameraIds=\"$camid\"&expMode=\"$expmode\"&camParamChkList=32&_sid=\"$sid\"";   
   
   } elsif ($OpMode eq "MotDetSc") {
      # Hash für Optionswerte sichern für Logausgabe in Befehlsauswertung
      my %motdetoptions = ();    
        
      if ($hash->{HELPER}{MOTDETSC} eq "disable") {
          $motdetsc = "-1";
          $url = "$proto://$serveraddr:$serverport/webapi/$apicameventpath?api=\"$apicamevent\"&version=\"$apicameventmaxver\"&method=\"MDParamSave\"&camId=\"$camid\"&source=$motdetsc&keep=true&_sid=\"$sid\"";
      } elsif ($hash->{HELPER}{MOTDETSC} eq "camera") {
          $motdetsc = "0";
          
          $motdetoptions{SENSITIVITY} = $hash->{HELPER}{MOTDETSC_PROP1} if ($hash->{HELPER}{MOTDETSC_PROP1});
          $motdetoptions{OBJECTSIZE}  = $hash->{HELPER}{MOTDETSC_PROP2} if ($hash->{HELPER}{MOTDETSC_PROP2});
          $motdetoptions{PERCENTAGE}  = $hash->{HELPER}{MOTDETSC_PROP3} if ($hash->{HELPER}{MOTDETSC_PROP3});
          
          $url = "$proto://$serveraddr:$serverport/webapi/$apicameventpath?api=\"$apicamevent\"&version=\"$apicameventmaxver\"&method=\"MDParamSave\"&camId=\"$camid\"&source=$motdetsc&_sid=\"$sid\"";
          
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
          
          $motdetoptions{SENSITIVITY} = $hash->{HELPER}{MOTDETSC_PROP1} if ($hash->{HELPER}{MOTDETSC_PROP1});
          $motdetoptions{THRESHOLD}   = $hash->{HELPER}{MOTDETSC_PROP2} if ($hash->{HELPER}{MOTDETSC_PROP2});
      
          # nur Umschaltung, alte Werte beibehalten
          $url = "$proto://$serveraddr:$serverport/webapi/$apicameventpath?api=\"$apicamevent\"&version=\"$apicameventmaxver\"&method=\"MDParamSave\"&camId=\"$camid\"&source=$motdetsc&keep=true&_sid=\"$sid\"";

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
      $url = "$proto://$serveraddr:$serverport/webapi/$apicameventpath?api=\"$apicamevent\"&version=\"$apicameventmaxver\"&method=\"MotionEnum\"&camId=\"$camid\"&_sid=\"$sid\"";   
   
   } elsif ($OpMode eq "extevent") {
      Log3($name, 4, "$name - trigger external event \"$hash->{HELPER}{EVENTID}\"");
      $url = "$proto://$serveraddr:$serverport/webapi/$apiextevtpath?api=$apiextevt&version=$apiextevtmaxver&method=Trigger&eventId=$hash->{HELPER}{EVENTID}&eventName=$hash->{HELPER}{EVENTID}&_sid=\"$sid\"";
   
   } elsif ($OpMode eq "runliveview" && $hash->{HELPER}{RUNVIEW} !~ m/snap|^live_.*hls$/) {
      $exturl = AttrVal($name, "livestreamprefix", "$proto://$serveraddr:$serverport");
      $exturl = ($exturl eq "DEF")?"$proto://$serveraddr:$serverport":$exturl;      
      if ($hash->{HELPER}{RUNVIEW} =~ m/live/) {
	      if($apiaudiostmmaxver) {   # API "SYNO.SurveillanceStation.AudioStream" vorhanden ? (removed ab API v2.8)
              $hash->{HELPER}{AUDIOLINK} = "$proto://$serveraddr:$serverport/webapi/$apiaudiostmpath?api=$apiaudiostm&version=$apiaudiostmmaxver&method=Stream&cameraId=$camid&_sid=$sid"; 
          } else {
              delete $hash->{HELPER}{AUDIOLINK} if($hash->{HELPER}{AUDIOLINK});
          }
		  
          if($apivideostmsmaxver) {  # API "SYNO.SurveillanceStation.VideoStream" vorhanden ? (removed ab API v2.8)
              # externe URL in Reading setzen
              $exturl .= "/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsmaxver&method=Stream&cameraId=$camid&format=mjpeg&_sid=$sid"; 
              
              # interne URL
              $url = "$proto://$serveraddr:$serverport/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsmaxver&method=Stream&cameraId=$camid&format=mjpeg&_sid=$sid"; 
          } elsif ($hash->{HELPER}{STMKEYMJPEGHTTP}) {
              $url = $hash->{HELPER}{STMKEYMJPEGHTTP};
          }
          readingsSingleUpdate($hash,"LiveStreamUrl", $exturl, 1) if(AttrVal($name, "showStmInfoFull", undef));
      
      } else {
          # Abspielen der letzten Aufnahme (EventId)
          my $lrecid = ReadingsVal("$name", "CamLastRecId", 0);
          if($lrecid) {
              # externe URL in Reading setzen
              $exturl .= "/webapi/$apistmpath?api=$apistm&version=$apistmmaxver&method=EventStream&eventId=$lrecid&timestamp=1&_sid=$sid"; 
              # interne URL          
              $url = "$proto://$serveraddr:$serverport/webapi/$apistmpath?api=$apistm&version=$apistmmaxver&method=EventStream&eventId=$lrecid&timestamp=1&_sid=$sid";   
              readingsSingleUpdate($hash,"LiveStreamUrl", $exturl, 1) if(AttrVal($name, "showStmInfoFull", 0));
          }
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
              map {FW_directNotify("FILTER=room=$room", "#FHEMWEB:$_", "window.open ('$url','$winname','$attr')", "")} devspec2array("TYPE=FHEMWEB");
          } else {
              map {FW_directNotify("#FHEMWEB:$_", "window.open ('$url','$winname','$attr')", "")} devspec2array("TYPE=FHEMWEB");
          }
      }
           
	  SSCam_refresh($hash,0,1,1);    # kein Room-Refresh, SSCam-state-Event, SSCamSTRM-Event
      
      SSCam_delActiveToken($hash);
      return;
	  
   } elsif ($OpMode eq "runliveview" && $hash->{HELPER}{RUNVIEW} =~ /snap/) {
      # den letzten Schnappschuß live anzeigen
	  my $limit   = 1;                # nur 1 Snap laden, für lastsnap_fw 
	  my $imgsize = 2;                # full size image, für lastsnap_fw 
	  my $keyword = $hash->{CAMNAME}; # nur Snaps von $camname selektieren, für lastsnap_fw   
      $url = "$proto://$serveraddr:$serverport/webapi/$apitakesnappath?api=\"$apitakesnap\"&method=\"List\"&version=\"$apitakesnapmaxver\"&keyword=\"$keyword\"&imgSize=\"$imgsize\"&limit=\"$limit\"&_sid=\"$sid\"";
   
   } elsif (($OpMode eq "runliveview" && $hash->{HELPER}{RUNVIEW} =~ m/^live_.*hls$/) || $OpMode eq "activate_hls") {
      # HLS Livestreaming aktivieren
      $httptimeout = $httptimeout+90; # aktivieren HLS dauert lange !
      $url = "$proto://$serveraddr:$serverport/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsmaxver&method=Open&cameraId=$camid&format=hls&_sid=$sid"; 
   
   } elsif ($OpMode eq "stopliveview_hls" || $OpMode eq "reactivate_hls") {
      # HLS Livestreaming deaktivieren
      $url = "$proto://$serveraddr:$serverport/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsmaxver&method=Close&cameraId=$camid&format=hls&_sid=$sid"; 
   
   } elsif ($OpMode eq "getstreamformat") {
      # aktuelles Streamformat abfragen
      $url = "$proto://$serveraddr:$serverport/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsmaxver&method=Query&cameraId=$camid&_sid=$sid"; 
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
   my $proto              = $hash->{PROTOCOL};
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
   
   my $lang = AttrVal("global","language","EN");
   
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
        SSCam_delActiveToken($hash);
        return;
   
   } elsif ($myjson ne "") {    
        # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
        # Evaluiere ob Daten im JSON-Format empfangen wurden 
        if($OpMode !~ /SaveRec|GetRec/) {                                # "SaveRec/GetRec" liefern MP4-Daten und kein JSON   
            ($hash,$success,$myjson) = SSCam_evaljson($hash,$myjson);        
            unless ($success) {
                Log3($name, 4, "$name - Data returned: ".$myjson);
                SSCam_delActiveToken($hash);
                return;
            }
            
            $data = decode_json($myjson);
            
            # Logausgabe decodierte JSON Daten
            Log3($name, 5, "$name - JSON returned: ". Dumper $data);
       
            $success = $data->{'success'};
        } else {
            $success = 1; 
        }

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
                        Log3($name, 3, "$name - Camera $camname recording with recording time $rectime s started");
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
                    my $emtxt   = $hash->{HELPER}{SMTPRECMSG}?$hash->{HELPER}{SMTPRECMSG}:"";
                    my $teletxt = $hash->{HELPER}{TELERECMSG}?$hash->{HELPER}{TELERECMSG}:"";
                    RemoveInternalTimer($hash, "SSCam_camstoprec");
                    InternalTimer(gettimeofday()+$rectime, "SSCam_camstoprec", "$name!_!$emtxt!_!$teletxt");
                }      
                
                SSCam_refresh($hash,0,0,1);    # kein Room-Refresh, kein SSCam-state-Event, SSCamSTRM-Event
            
			} elsif ($OpMode eq "Stop") {                
			
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Record","Stop");
                readingsBulkUpdate($hash,"state","off");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
       
                # Logausgabe
                Log3($name, 3, "$name - Camera $camname Recording stopped");
                
                SSCam_refresh($hash,0,0,1);    # kein Room-Refresh, kein SSCam-state-Event, SSCamSTRM-Event
                
                # Aktualisierung Eventlist der letzten Aufnahme
                SSCam_geteventlist($hash);
            
			} elsif ($OpMode eq "ExpMode") {              

                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
       
                # Logausgabe
                Log3($name, 3, "$name - Camera $camname exposure mode was set to \"$hash->{HELPER}{EXPMODE}\"");
            
			} elsif ($OpMode eq "GetRec") {              
                my $recid     = ReadingsVal("$name", "CamLastRecId", "");
                my $createdTm = ReadingsVal("$name", "CamLastRecTime", "");
                my $lrec      = ReadingsVal("$name", "CamLastRec", "");
                my $fileName  = (split("/",$lrec))[1];
                my $sn        = 0;
                
                $hash->{HELPER}{TRANSACTION} = "fake_recsend";          # fake Transaction Device setzen
                my $tac = SSCam_openOrgetTrans($hash);                  # Transaktion vorhandenen Code (fake_recsend)              
                
                $data{SSCam}{$name}{SENDRECS}{$tac}{$sn}{$recid}       = $recid;
                $data{SSCam}{$name}{SENDRECS}{$tac}{$sn}{createdTm}    = $createdTm;
				$data{SSCam}{$name}{SENDRECS}{$tac}{$sn}{fileName}     = $fileName;
				$data{SSCam}{$name}{SENDRECS}{$tac}{$sn}{".imageData"} = $myjson;
				Log3($name,4, "$name - Recording '$sn' added to send recording hash: ID => $recid, File => $fileName, Created => $createdTm");
                
                # prüfen ob Recording als Email / Telegram versendet werden soll                
				SSCam_prepareSendData ($hash, $OpMode, $data{SSCam}{$name}{SENDRECS}{$tac});
                
                SSCam_closeTrans ($hash);                               # Transaktion beenden
                        
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error",$err);
                readingsEndUpdate($hash, 1);
       
            
			} elsif ($OpMode eq "SaveRec") {              

                my $lrec = ReadingsVal("$name", "CamLastRec", "");
                $lrec    = (split("/",$lrec))[1]; 
                my $sp   = $hash->{HELPER}{RECSAVEPATH}?$hash->{HELPER}{RECSAVEPATH}:$attr{global}{modpath};
                my $file = $sp."/$lrec";
                delete $hash->{HELPER}{RECSAVEPATH};
                
                if(open (FH, '>', $file)) {           
                    binmode FH;
                    print FH $myjson;
                    close(FH);
                    $err = "none";
                    Log3($name, 3, "$name - Recording was saved to local file \"$file\"");
                } else {
                    $err = "Can't open file \"$file\": $!";
                    Log3($name, 2, "$name - $err");
                }
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error",$err);
                readingsEndUpdate($hash, 1);
       
            
			} elsif ($OpMode eq "sethomemode") {              

                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
       
                Log3($name, 3, "$name - HomeMode was set to \"$hash->{HELPER}{HOMEMODE}\" ");
				
				# Token freigeben vor nächstem Kommando
                SSCam_delActiveToken($hash);
  
                # neuen HomeModeState abrufen	
                SSCam_gethomemodestate($hash);
            
			} elsif ($OpMode eq "gethomemodestate") {  
                my $hmst = $data->{'data'}{'on'}; 
                my $hmststr = ($hmst == 1)?"on":"off";

                ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
                if($lang eq "DE") {
                    $update_time = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;
                } else {
                    $update_time = sprintf "%04d-%02d-%02d / %02d:%02d:%02d" , $year+=1900 , $mon+=1 , $mday , $hour , $min , $sec ;
                }				

                readingsBeginUpdate($hash);
				readingsBulkUpdate($hash,"HomeModeState",$hmststr);
                readingsBulkUpdate($hash,"LastUpdateTime",$update_time);
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

                Log3($name, 3, "$name - Camera \"$camname\" preset \"$pname\" was saved to number $pnumber with speed $pspeed");
                SSCam_getptzlistpreset($hash);
            
			} elsif ($OpMode eq "delPreset") {              
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                
                my $dp = $hash->{HELPER}{DELPRESETNAME};
                delete $hash->{HELPER}{ALLPRESETS}{$dp};                
                Log3($name, 3, "$name - Preset \"$dp\" of camera \"$camname\" has been deleted");
                SSCam_getptzlistpreset($hash);
            
			} elsif ($OpMode eq "piract") {              

                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
       
                my $piract = ($hash->{HELPER}{PIRACT} == 0)?"activated":"deactivated";
                Log3($name, 3, "$name - PIR sensor $piract");
            
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
                SSCam_delActiveToken($hash);
                RemoveInternalTimer($hash, "SSCam_getcaminfo");
                InternalTimer(gettimeofday()+0.5, "SSCam_getcaminfo", $hash, 0);
				
			} elsif ($OpMode eq "MotDetSc") {              

                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
       
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
                SSCam_refresh($hash,0,1,0);                   # kein Room-Refresh, SSCam-state-Event, kein SSCamSTRM-Event

                my $tac = "";
                if($hash->{HELPER}{CANSENDSNAP} || $hash->{HELPER}{CANTELESNAP}) { 
                    $tac = SSCam_openOrgetTrans($hash);       # Transaktion starten oder vorhandenen Code holen
                }
                
                $snapid = $data->{data}{'id'};
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                if ($snapid) {
                    Log3($name, 3, "$name - Snapshot of Camera $camname created. ID: $snapid");
                } else {
                    Log3($name, 1, "$name - Snapshot of Camera $camname probably not created. No ID was delivered.");
                }
                
                
                my $num     = $hash->{HELPER}{SNAPNUM};                              # Gesamtzahl der auszulösenden Schnappschüsse
                my $ncount  = $hash->{HELPER}{SNAPNUMCOUNT};                         # Restzahl der auszulösenden Schnappschüsse 
                if (AttrVal($name,"debugactivetoken",0)) {
                    Log3($name, 1, "$name - Snapshot number ".($num-$ncount+1)." (ID: $snapid) of total $num snapshots with transaction-ID: $tac done");
                }
                $ncount--;                                                           # wird vermindert je Snap
                my $lag     = $hash->{HELPER}{SNAPLAG};                              # Zeitverzögerung zwischen zwei Schnappschüssen
                my $emtxt   = $hash->{HELPER}{SMTPMSG}?$hash->{HELPER}{SMTPMSG}:"";  # Text für Email-Versand
				my $teletxt = $hash->{HELPER}{TELEMSG}?$hash->{HELPER}{TELEMSG}:"";  # Text für TelegramBot-Versand
                if($ncount > 0) {
                    InternalTimer(gettimeofday()+$lag, "SSCam_camsnap", "$name!_!$num!_!$lag!_!$ncount!_!$emtxt!_!$teletxt!_!$tac", 0);
                    if(!$tac) {
					    SSCam_delActiveToken($hash);                               # Token freigeben wenn keine Transaktion läuft
					}
                    return;
                }
  
                # Anzahl und Size für Schnappschußabruf bestimmen
                my ($slim,$ssize) = SSCam_snaplimsize($hash);
                if (AttrVal($name,"debugactivetoken",0)) {
                    Log3($name, 1, "$name - start get snapinfo of last $slim snapshots with transaction-ID: $tac");
                }

                if(!$hash->{HELPER}{TRANSACTION}) {                  
                    # Token freigeben vor nächstem Kommando wenn keine Transaktion läuft
                    SSCam_delActiveToken($hash);                        
                }
                
                RemoveInternalTimer($hash, "SSCam_getsnapinfo");                
                InternalTimer(gettimeofday()+0.6, "SSCam_getsnapinfo", "$name:$slim:$ssize:$tac", 0);
                return;
            
			} elsif ($OpMode eq "getsnapinfo" || 
                     $OpMode eq "getsnapgallery" || 
                     ($OpMode eq "runliveview" && $hash->{HELPER}{RUNVIEW} =~ /snap/)
                    ) {
				
	            Log3($name, $verbose, "$name - Snapinfos of camera $camname retrieved");
                $hash->{HELPER}{".LASTSNAP"} = $data->{data}{data}[0]{imageData};         # aktuellster Snap zur Anzeige im StreamDev "lastsnap"
        
                my %snaps  = ( 0 => {'createdTm' => 'n.a.', 'fileName' => 'n.a.','snapid' => 'n.a.'} );  # Hilfshash 
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
                        } else {
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
                
                my @as;
                my $rotnum = AttrVal($name,"snapReadingRotate",0);
                my $o      = ReadingsVal($name,"LastSnapId","n.a."); 
                if($rotnum && "$o" ne "$snaps{0}{snapid}") {
                    @as = sort{$b<=>$a}keys%snaps;
                    foreach my $key (@as) {
                        SSCam_rotateReading($hash,"LastSnapId",$snaps{$key}{snapid},$rotnum,1);
                        SSCam_rotateReading($hash,"LastSnapFilename",$snaps{$key}{fileName},$rotnum,1);
                        SSCam_rotateReading($hash,"LastSnapTime",$snaps{$key}{createdTm},$rotnum,1);                    
                    }
                } else {
                    @as = sort{$a<=>$b}keys%snaps;
                    SSCam_rotateReading($hash,"LastSnapId",$snaps{$as[0]}{snapid},$rotnum,1);
                    SSCam_rotateReading($hash,"LastSnapFilename",$snaps{$as[0]}{fileName},$rotnum,1);
                    SSCam_rotateReading($hash,"LastSnapTime",$snaps{$as[0]}{createdTm},$rotnum,1);                  
                }
					
				#####  ein Schnapschuss soll als liveView angezeigt werden  #####
				Log3($name, 3, "$name - There is no snapshot of camera $camname to display ! Take one snapshot before.") 
				   if(exists($hash->{HELPER}{RUNVIEW}) && $hash->{HELPER}{RUNVIEW} =~ /snap/ && !exists($data->{'data'}{'data'}[0]{imageData}));
			    
				if (exists($hash->{HELPER}{RUNVIEW}) && $hash->{HELPER}{RUNVIEW} =~ /snap/ && exists($data->{'data'}{'data'}[0]{imageData})) {
				    delete $hash->{HELPER}{RUNVIEW};					
					$hash->{HELPER}{LINK} = $data->{data}{data}[0]{imageData};					
				}

				#####  eine Schnapschussgalerie soll angezeigt oder als Bulk versendet werden  #####
                my $tac = SSCam_openOrgetTrans($hash);       # Transaktion vorhandenen Code holen
                if($OpMode eq "getsnapgallery") {
				    if($hash->{HELPER}{CANSENDSNAP} || $hash->{HELPER}{CANTELESNAP}) {
					    # es sollen die Anzahl "$hash->{HELPER}{SNAPNUM}" Schnappschüsse versendet werden
						my $i = 0;
						my $sn = 0;

                        if($hash->{HELPER}{".SNAPHASH"}) {
                        	foreach my $key (sort(keys%{$hash->{HELPER}{".SNAPHASH"}})) {
                                $hash->{HELPER}{".SNAPHASHOLD"}{$key} = delete($hash->{HELPER}{".SNAPHASH"}{$key});
	                        }    
                        }
                            
						while ($data->{'data'}{'data'}[$i]) {
							if(!$data->{'data'}{'data'}[$i]{'camName'} || $data->{'data'}{'data'}[$i]{'camName'} ne $camname) {    # Forum:#97706
								$i += 1;
								next;
							}
							$snapid = $data->{data}{data}[$i]{id};
                            my @t = split(" ", FmtDateTime($data->{data}{data}[$i]{createdTm}));
                            my @d = split("-", $t[0]);
                            my $createdTm;
                            if($lang eq "DE") {
                                $createdTm = "$d[2].$d[1].$d[0] / $t[1]";
                            } else {
                                $createdTm = "$d[0]-$d[1]-$d[2] / $t[1]";
                            }
							my $fileName  = $data->{data}{data}[$i]{fileName};
							my $imageData = $data->{data}{data}[$i]{imageData};  # Image data of snapshot in base64 format 
						    
                            # Schnappschuss Hash zum Versand wird erstellt
							$data{SSCam}{$name}{SENDSNAPS}{$tac}{$sn}{snapid}       = $snapid;
							$data{SSCam}{$name}{SENDSNAPS}{$tac}{$sn}{createdTm}    = $createdTm;
							$data{SSCam}{$name}{SENDSNAPS}{$tac}{$sn}{fileName}     = $fileName;
							$data{SSCam}{$name}{SENDSNAPS}{$tac}{$sn}{".imageData"} = $imageData;
							Log3($name,4, "$name - Snap '$sn' added to send gallery hash: ID => $snapid, File => $fileName, Created => $createdTm");
                        
                            # Snaphash erstellen 
                            $hash->{HELPER}{".SNAPHASH"}{$sn}{snapid}     = $snapid;
                            $hash->{HELPER}{".SNAPHASH"}{$sn}{createdTm}  = $createdTm;
                            $hash->{HELPER}{".SNAPHASH"}{$sn}{fileName}   = $fileName;
                            $hash->{HELPER}{".SNAPHASH"}{$sn}{imageData}  = $imageData;
                            Log3($name,4, "$name - Snap '$sn' added to gallery hash: ID => $snapid, File => $fileName, Created => $createdTm");                        													
                            
                            $sn += 1;
							$i += 1;
						}
                        
                        my $sgn = AttrVal($name,"snapGalleryNumber",3);
                        my $ss  = $sn;
                        $sn     = 0;
                                               													
                        if($hash->{HELPER}{".SNAPHASHOLD"} && $sgn > $ss) {
                            for my $kn ($ss..($sgn-1)) {
                                $hash->{HELPER}{".SNAPHASH"}{$kn}{snapid}     = delete $hash->{HELPER}{".SNAPHASHOLD"}{$sn}{snapid};
                                $hash->{HELPER}{".SNAPHASH"}{$kn}{createdTm}  = delete $hash->{HELPER}{".SNAPHASHOLD"}{$sn}{createdTm};
                                $hash->{HELPER}{".SNAPHASH"}{$kn}{fileName}   = delete $hash->{HELPER}{".SNAPHASHOLD"}{$sn}{fileName};
                                $hash->{HELPER}{".SNAPHASH"}{$kn}{imageData}  = delete $hash->{HELPER}{".SNAPHASHOLD"}{$sn}{imageData}; 
                                $sn += 1;                            
                            }
                        }
                        
					    # prüfen ob Schnappschuß versendet werden soll
				        SSCam_prepareSendData ($hash, $OpMode, $data{SSCam}{$name}{SENDSNAPS}{$tac});
						
					} else {
                        # es soll eine Schnappschußgalerie bereitgestellt (Attr snapGalleryBoost=1) bzw. gleich angezeigt 
                        # werden (Attr snapGalleryBoost=0)
                        my $i = 0;
                        my $sn = 0;
                         
                        $hash->{HELPER}{TOTALCNT} = $data->{data}{total};  # total Anzahl Schnappschüsse
                        
                        if($hash->{HELPER}{".SNAPHASH"}) {
                        	foreach my $key (sort(keys%{$hash->{HELPER}{".SNAPHASH"}})) {
                                $hash->{HELPER}{".SNAPHASHOLD"}{$key} = delete($hash->{HELPER}{".SNAPHASH"}{$key});
	                        }
                        }
                        
                        while ($data->{'data'}{'data'}[$i]) {
							if(!$data->{'data'}{'data'}[$i]{'camName'} || $data->{'data'}{'data'}[$i]{'camName'} ne $camname) {    # Forum:#97706
								$i += 1;
								next;
							}	
                            $snapid = $data->{data}{data}[$i]{id};
                            my $createdTm = $data->{data}{data}[$i]{createdTm};
                            my $fileName  = $data->{data}{data}[$i]{fileName};
                            my $imageData = $data->{data}{data}[$i]{imageData};  # Image data of snapshot in base64 format 
                        
                            my @t = split(" ", FmtDateTime($data->{data}{data}[$i]{createdTm}));
                            my @d = split("-", $t[0]);
                            if($lang eq "DE") {
                                $createdTm = "$d[2].$d[1].$d[0] / $t[1]";
                            } else {
                                $createdTm = "$d[0]-$d[1]-$d[2] / $t[1]";
                            }
                            
                            # Snaphash erstellen
                            $hash->{HELPER}{".SNAPHASH"}{$sn}{snapid}     = $snapid;
                            $hash->{HELPER}{".SNAPHASH"}{$sn}{createdTm}  = $createdTm;
                            $hash->{HELPER}{".SNAPHASH"}{$sn}{fileName}   = $fileName;
                            $hash->{HELPER}{".SNAPHASH"}{$sn}{imageData}  = $imageData;
                            Log3($name,4, "$name - Snap '$sn' added to gallery hash: ID => $hash->{HELPER}{\".SNAPHASH\"}{$sn}{snapid}, File => $hash->{HELPER}{\".SNAPHASH\"}{$sn}{fileName}, Created => $hash->{HELPER}{\".SNAPHASH\"}{$sn}{createdTm}");
                            
                            $sn += 1;
                            $i += 1;
                        }
                        
                        my $sgn = AttrVal($name,"snapGalleryNumber",3);
                        my $ss  = $sn;
                        $sn     = 0; 
                        if($hash->{HELPER}{".SNAPHASHOLD"} && $sgn > $ss) {
                            for my $kn ($ss..($sgn-1)) {
                                $hash->{HELPER}{".SNAPHASH"}{$kn}{snapid}     = delete $hash->{HELPER}{".SNAPHASHOLD"}{$sn}{snapid};
                                $hash->{HELPER}{".SNAPHASH"}{$kn}{createdTm}  = delete $hash->{HELPER}{".SNAPHASHOLD"}{$sn}{createdTm};
                                $hash->{HELPER}{".SNAPHASH"}{$kn}{fileName}   = delete $hash->{HELPER}{".SNAPHASHOLD"}{$sn}{fileName};
                                $hash->{HELPER}{".SNAPHASH"}{$kn}{imageData}  = delete $hash->{HELPER}{".SNAPHASHOLD"}{$sn}{imageData}; 
                                $sn += 1;                            
                            }
                        }
                        
                        # Direktausgabe Snaphash wenn nicht gepollt wird
                        if(!AttrVal($name, "snapGalleryBoost",0)) {		    
                            my $htmlCode = SSCam_composegallery($name);
                            
                            for (my $k=1; (defined($hash->{HELPER}{CL}{$k})); $k++ ) {
                                asyncOutput($hash->{HELPER}{CL}{$k},"$htmlCode");						
                            }
                            delete($hash->{HELPER}{".SNAPHASH"});               # Snaphash Referenz löschen                            %allsnaps = ();
                            delete($hash->{HELPER}{CL});
                        }
                    }
                }
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);                
                
				delete($hash->{HELPER}{GETSNAPGALLERY});                        # Steuerbit getsnapgallery statt getsnapinfo				
                delete $hash->{HELPER}{".SNAPHASHOLD"};
                SSCam_closeTrans($hash);                                        # Transaktion beenden
                
				########  fallabhängige Eventgenerierung  ########
                if ($hash->{HELPER}{INFORM} || $hash->{HELPER}{LSNAPBYSTRMDEV}) {
                    # Snap durch SSCamSTRM-Device ausgelöst
                    SSCam_refresh($hash,0,0,1);     # kein Room-Refresh, kein SSCam-state-Event, SSCamSTRM-Event
                    delete $hash->{HELPER}{LSNAPBYSTRMDEV};
                } elsif ($hash->{HELPER}{LSNAPBYDEV}) {
                    SSCam_refresh($hash,0,1,0);     # kein Room-Refresh, SSCam-state-Event, kein SSCamSTRM-Event
                    delete $hash->{HELPER}{LSNAPBYDEV};
                } else {
                    SSCam_refresh($hash,0,0,0);     # kein Room-Refresh, SSCam-state-Event, SSCamSTRM-Event
                } 
            
			} elsif ($OpMode eq "runliveview" && $hash->{HELPER}{RUNVIEW} =~ m/^live_.*hls$/) {
                # HLS Streaming wurde aktiviert
                $hash->{HELPER}{HLSSTREAM} = "active";
                # externe LivestreamURL setzen
                my $exturl = AttrVal($name, "livestreamprefix", "$proto://$serveraddr:$serverport");
                $exturl .= "/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsmaxver&method=Stream&cameraId=$camid&format=hls&_sid=$sid"; 
                readingsSingleUpdate($hash,"LiveStreamUrl", $exturl, 1) if(AttrVal($name, "showStmInfoFull", undef));
                
                my $url = "$proto://$serveraddr:$serverport/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsmaxver&method=Stream&cameraId=$camid&format=hls&_sid=$sid"; 
                # Liveview-Link in Hash speichern und Aktivitätsstatus speichern
                $hash->{HELPER}{LINK}      = $url;
                Log3($name, 4, "$name - HLS Streaming of camera \"$name\" activated, Streaming-URL: $url") if(AttrVal($name,"verbose",3) == 4);
                Log3($name, 3, "$name - HLS Streaming of camera \"$name\" activated") if(AttrVal($name,"verbose",3) == 3);
                
                SSCam_refresh($hash,0,1,1);   # kein Room-Refresh, SSCam-state-Event, SSCamSTRM-Event
                
            } elsif ($OpMode eq "stopliveview_hls") {
                # HLS Streaming wurde deaktiviert, Aktivitätsstatus speichern
                $hash->{HELPER}{HLSSTREAM} = "inactive";
                Log3($name, 3, "$name - HLS Streaming of camera \"$name\" deactivated");
                               
                SSCam_refresh($hash,0,1,1);   # kein Room-Refresh, SSCam-state-Event, SSCamSTRM-Event
                
            } elsif ($OpMode eq "reactivate_hls") {
                # HLS Streaming wurde deaktiviert, Aktivitätsstatus speichern
                $hash->{HELPER}{HLSSTREAM} = "inactive";
                Log3($name, 4, "$name - HLS Streaming of camera \"$name\" deactivated for streaming device");

				# Token freigeben vor hlsactivate
                SSCam_delActiveToken($hash);
                SSCam_hlsactivate($hash);
                return;
                
            } elsif ($OpMode eq "activate_hls") {
                # HLS Streaming wurde aktiviert, Aktivitätsstatus speichern
                $hash->{HELPER}{HLSSTREAM} = "active"; 
                Log3($name, 4, "$name - HLS Streaming of camera \"$name\" activated for streaming device");
                
                SSCam_refresh($hash,0,1,1);   # kein Room-Refresh, SSCam-state-Event, SSCamSTRM-Event
                                
            } elsif ($OpMode eq "getsnapfilename") {
                # den Filenamen eines Schnapschusses ermitteln
                $snapid = ReadingsVal("$name", "LastSnapId", "");

                if(!$snapid) {
                   Log3($name, 2, "$name - Snap-ID \"LastSnapId\" isn't set. Filename can't be retrieved"); 
                   return;
                }               
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsBulkUpdate($hash,"LastSnapFilename", $data->{'data'}{'data'}[0]{'fileName'});
                readingsEndUpdate($hash, 1);

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
                                
                Log3($name, 3, "$name - Camera $camname has been moved to absolute position \"posX=$hash->{HELPER}{GOPTZPOSX}\" and \"posY=$hash->{HELPER}{GOPTZPOSY}\"");
            
			} elsif ($OpMode eq "startTrack") {
                # Object Tracking wurde eingeschaltet
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                Log3($name, 3, "$name - Object tracking of Camera $camname has been switched on");
            
			} elsif ($OpMode eq "stopTrack") {
                # Object Tracking wurde eingeschaltet
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                Log3($name, 3, "$name - Object tracking of Camera $camname has been stopped");
            
			} elsif ($OpMode eq "movestart") {
                # ein "Move" in eine bestimmte Richtung wird durchgeführt                 
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
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

                # Werte in $hash zur späteren Auswertung einfügen 
                $hash->{HELPER}{SVSVERSION}{MAJOR} = $data->{'data'}{'version'}{'major'};
                $hash->{HELPER}{SVSVERSION}{MINOR} = $data->{'data'}{'version'}{'minor'};
				$hash->{HELPER}{SVSVERSION}{SMALL} = $data->{'data'}{'version'}{'small'};
                $hash->{HELPER}{SVSVERSION}{BUILD} = $data->{'data'}{'version'}{'build'};

				my $major = $hash->{HELPER}{SVSVERSION}{MAJOR};
				my $minor = $hash->{HELPER}{SVSVERSION}{MINOR};
				my $small = $hash->{HELPER}{SVSVERSION}{SMALL};
				my $build = $hash->{HELPER}{SVSVERSION}{BUILD};
                
                # simulieren einer anderen SVS-Version
                if (AttrVal($name, "simu_SVSversion", undef)) {
                    Log3($name, 4, "$name - another SVS-version ".AttrVal($name, "simu_SVSversion", undef)." will be simulated");
					#delete $version{"SMALL"} if ($version{"SMALL"});
                    my @vl = split (/\.|-/,AttrVal($name, "simu_SVSversion", ""));
                    $major = $vl[0];
                    $minor = $vl[1];
					$small = ($vl[2] =~ /\d/)?$vl[2]:'';
                    $build = "xxxx-simu";
                }
                
                # Kompatibilitätscheck
                my $avsc   = $major.$minor.(($small=~/\d/)?$small:0);
                my $avcomp = $hash->{COMPATIBILITY};
                $avcomp    =~ s/\.//g;
                
                my $compstate;
                if($avsc <= $avcomp) {
                    $compstate = "true";
                } else {
                    $compstate = "false";
                }
                readingsSingleUpdate($hash, "compstate", $compstate, 1);
                
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
                    my $exturl = AttrVal($name, "livestreamprefix", "$proto://$serveraddr:$serverport");
                    $exturl = ($exturl eq "DEF")?"$proto://$serveraddr:$serverport":$exturl;
                    my @mjh = split(/\//, $mjpegHttp, 4);
                    $mjpegHttp = $exturl."/".$mjh[3];
                    my @mxh = split(/\//, $mxpegHttp, 4);
                    $mxpegHttp = $exturl."/".$mxh[3];
					if($unicastPath) {
                        my @ucp = split(/[@\|:]/, $unicastPath);
                        my @lspf = split(/[\/\/\|:]/, $exturl);
                        $unicastPath = $ucp[0].":".$ucp[1].":".$ucp[2]."@".$lspf[3].":".$ucp[4];
					}
                }
                
                # StmKey extrahieren
                my @sk = split(/&StmKey=/, $mjpegHttp);
                my $stmkey = $sk[1];
                
				# Quotes in StmKey entfernen falls noQuotesForSID gesetzt 
                if(AttrVal($name, "noQuotesForSID",0)) {   # Forum: https://forum.fhem.de/index.php/topic,45671.msg938236.html#msg938236
				    $mjpegHttp =~ tr/"//d;
                    $mxpegHttp =~ tr/"//d;
                    $stmkey    =~ tr/"//d;
                }
                
                # Streaminginfos in Helper speichern
                $hash->{HELPER}{STMKEYMJPEGHTTP}      = $mjpegHttp if($mjpegHttp);
                $hash->{HELPER}{STMKEYMXPEGHTTP}      = $mxpegHttp if($mxpegHttp);
                $hash->{HELPER}{STMKEYUNICSTOVERHTTP} = $unicastOverHttp if($unicastOverHttp);
                $hash->{HELPER}{STMKEYUNICST}         = $unicastPath if($unicastPath);
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"CamForceEnableMulticast",$camforcemcast) if($camforcemcast);
                readingsBulkUpdate($hash,"StmKey",$stmkey);
                readingsBulkUpdate($hash,"StmKeymjpegHttp",$mjpegHttp) if(AttrVal($name,"showStmInfoFull",0));
                readingsBulkUpdate($hash,"StmKeymxpegHttp",$mxpegHttp) if(AttrVal($name,"showStmInfoFull",0));
				readingsBulkUpdate($hash,"StmKeyUnicstOverHttp",$unicastOverHttp) if(AttrVal($name,"showStmInfoFull",0) && $unicastOverHttp);
                readingsBulkUpdate($hash,"StmKeyUnicst",$unicastPath) if(AttrVal($name,"showStmInfoFull",0) && $unicastPath);
				readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);

                Log3($name, $verbose, "$name - Stream-URLs of camera $camname retrieved");
            
			} elsif ($OpMode eq "Getcaminfo") {
                # Parse Caminfos
                $camLiveMode = $data->{'data'}->{'cameras'}->[0]->{'camLiveMode'};
                if ($camLiveMode eq "0") {$camLiveMode = "Liveview from DS";}elsif ($camLiveMode eq "1") {$camLiveMode = "Liveview from Camera";}
                
                ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
                if($lang eq "DE") {
                    $update_time = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;
                } else {
                    $update_time = sprintf "%04d-%02d-%02d / %02d:%02d:%02d" , $year+=1900 , $mon+=1 , $mday , $hour , $min , $sec ;
                }
                
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
                
                $camStatus = SSCam_jboolmap($data->{'data'}->{'cameras'}->[0]->{'camStatus'});
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
                    
                my $pdcap = SSCam_jboolmap($data->{'data'}->{'cameras'}->[0]->{'PDCap'});
                if (!$pdcap || $pdcap == 0) {
                    $pdcap = "false";
                } else {
                    $pdcap = "true";
                }
                
                $data->{'data'}->{'cameras'}->[0]->{'video_flip'}    = SSCam_jboolmap($data->{'data'}->{'cameras'}->[0]->{'video_flip'});
                $data->{'data'}->{'cameras'}->[0]->{'video_mirror'}  = SSCam_jboolmap($data->{'data'}->{'cameras'}->[0]->{'video_mirror'});
                $data->{'data'}->{'cameras'}->[0]->{'blPresetSpeed'} = SSCam_jboolmap($data->{'data'}->{'cameras'}->[0]->{'blPresetSpeed'});
                
                my $clstrmno = $data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camLiveStreamNo'};
                $clstrmno++ if($clstrmno == 0);
                
                my $fw = $data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camFirmware'};
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"CamAudioType",$camaudiotype);
                readingsBulkUpdate($hash,"CamFirmware",$fw) if($fw);
                readingsBulkUpdate($hash,"CamLiveMode",$camLiveMode);
                readingsBulkUpdate($hash,"CamLiveFps",$data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camLiveFps'});
                readingsBulkUpdate($hash,"CamLiveResolution",$data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camLiveResolution'});
                readingsBulkUpdate($hash,"CamLiveQuality",$data->{'data'}->{'cameras'}->[0]->{'detailInfo'}{'camLiveQuality'});
                readingsBulkUpdate($hash,"CamLiveStreamNo",$clstrmno);
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
                readingsBulkUpdate($hash,"CamPtSpeed",$data->{'data'}->{'cameras'}->[0]->{'ptSpeed'}) if($deviceType =~ /PTZ/);
                readingsBulkUpdate($hash,"CamblPresetSpeed",$data->{'data'}->{'cameras'}->[0]->{'blPresetSpeed'});
                readingsBulkUpdate($hash,"CamVideoMirror",$data->{'data'}->{'cameras'}->[0]->{'video_mirror'});
                readingsBulkUpdate($hash,"CamVideoFlip",$data->{'data'}->{'cameras'}->[0]->{'video_flip'});
				readingsBulkUpdate($hash,"CamVideoRotate",$rotate);
                readingsBulkUpdate($hash,"CapPIR",$pdcap);
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
                my $eventnum  = $data->{'data'}{'total'};
                my $lrec      = $data->{'data'}{'events'}[0]{name};
                my $lrecid    = $data->{'data'}{'events'}[0]{'eventId'}; 
                
                my ($lastrecstarttime,$lastrecstoptime);
                
                if ($eventnum > 0) {
                    $lastrecstarttime = $data->{'data'}{'events'}[0]{startTime};
                    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($lastrecstarttime);
                    if($lang eq "DE") {
                        $lastrecstarttime = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;
                    } else {
                        $lastrecstarttime = sprintf "%04d-%02d-%02d / %02d:%02d:%02d" , $year+=1900 , $mon+=1 , $mday , $hour , $min , $sec ;
                    }
                    $lastrecstoptime = $data->{'data'}{'events'}[0]{stopTime};
                    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($lastrecstoptime);
                    $lastrecstoptime = sprintf "%02d:%02d:%02d" , $hour , $min , $sec ;
                }
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"CamEventNum",$eventnum);
                readingsBulkUpdate($hash,"CamLastRec",$lrec) if($lrec); 
                readingsBulkUpdate($hash,"CamLastRecId",$lrecid) if($lrecid);                 
                readingsBulkUpdate($hash,"CamLastRecTime",$lastrecstarttime." - ". $lastrecstoptime) if($lastrecstarttime);                
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
       
                Log3($name, $verbose, "$name - Query eventlist of camera $camname retrieved");
                
                # Versand Aufnahme initiieren
                if($hash->{HELPER}{CANSENDREC} || $hash->{HELPER}{CANTELEREC}) {
                    SSCam_getrec($hash);
                }
            
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
                  
                Log3($name, $verbose, "$name - Capabilities of camera $camname retrieved");
            
			} elsif ($OpMode eq "Getptzlistpreset") {
                # Parse PTZ-ListPresets
                my $presetcnt = $data->{'data'}->{'total'};
                my $cnt = 0;
         
                # alle Presets der Kamera mit Id's in Assoziatives Array einlesen
                delete $hash->{HELPER}{ALLPRESETS};                                      # besetehende Presets löschen und neu einlesen
                my $home = "not set";
                while ($cnt < $presetcnt) {
                    # my $presid = $data->{'data'}->{'presets'}->[$cnt]->{'id'};
                    my $presid   = $data->{'data'}->{'presets'}->[$cnt]->{'position'};
                    my $presname = $data->{'data'}->{'presets'}->[$cnt]->{'name'};
                    $presname    =~ s/\s+/_/g;                                           # Leerzeichen im Namen ersetzen falls vorhanden  
                    $hash->{HELPER}{ALLPRESETS}{$presname} = "$presid";
                    my $ptype = $data->{'data'}->{'presets'}->[$cnt]->{'type'};
                    if ($ptype) {
                        $home = $presname;
                    }
                    $cnt += 1;
                }

                my @preskeys = sort(keys(%{$hash->{HELPER}{ALLPRESETS}}));
                my $presetlist = join(",",@preskeys);

                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Presets",$presetlist);
                readingsBulkUpdate($hash,"PresetHome",$home);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                
                # spezifische Attribute für PTZ-Cams verfügbar machen
                SSCam_addptzattr($name);
                             
                Log3($name, $verbose, "$name - PTZ Presets of camera $camname retrieved");
            
			} elsif ($OpMode eq "Getptzlistpatrol") {
                # Parse PTZ-ListPatrols
                $patrolcnt = $data->{'data'}->{'total'};
                my $cnt = 0;
         
                # alle Patrols der Kamera mit Id's in Assoziatives Array einlesen
                delete $hash->{HELPER}{ALLPATROLS};
                while ($cnt < $patrolcnt) {
                    $patrolid = $data->{'data'}->{'patrols'}->[$cnt]->{'id'};
                    $patrolname = $data->{'data'}->{'patrols'}->[$cnt]->{'name'};
                    $patrolname =~ s/\s+/_/g;                                            # Leerzeichen im Namen ersetzen falls vorhanden
                    $hash->{HELPER}{ALLPATROLS}{$patrolname} = $patrolid;
                    $cnt += 1;
                }

                @patrolkeys = sort(keys(%{$hash->{HELPER}{ALLPATROLS}}));
                $patrollist = join(",",@patrolkeys);

                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Patrols",$patrollist);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                     
                Log3($name, $verbose, "$name - PTZ Patrols of camera $camname retrieved");
            }
            
       } else {
            # die API-Operation war fehlerhaft
            # Errorcode aus JSON ermitteln
            $errorcode = $data->{'error'}->{'code'};

            # Fehlertext zum Errorcode ermitteln
            $error = SSCam_experror($hash,$errorcode);
			
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode",$errorcode);
            readingsBulkUpdate($hash,"Error",$error);
            readingsEndUpdate($hash, 1);
			
		    if ($errorcode =~ /105/) {
			   Log3($name, 2, "$name - ERROR - $errorcode - $error in operation $OpMode -> try new login");
		       return SSCam_login($hash,'SSCam_getapisites');
		    }
       
            Log3($name, 2, "$name - ERROR - Operation $OpMode of Camera $camname was not successful. Errorcode: $errorcode - $error");
       }
   }
  
  # Token freigeben   
  SSCam_delActiveToken($hash);

return;
}


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
  my $proto         = $hash->{PROTOCOL};
  my $lrt = AttrVal($name,"loginRetries",3);
  my ($url,$param);
  
  delete $hash->{HELPER}{SID};
    
  # Login und SID ermitteln
  Log3($name, 4, "$name - --- Begin Function SSCam_login ---");
  
  # Credentials abrufen
  my ($success, $username, $password) = SSCam_getcredentials($hash,0,"svs");
  
  unless ($success) {
      Log3($name, 2, "$name - Credentials couldn't be retrieved successfully - make sure you've set it with \"set $name credentials <username> <password>\"");
      SSCam_delActiveToken($hash);      
      return;
  }
  
  if($hash->{HELPER}{LOGINRETRIES} >= $lrt) {
      # login wird abgebrochen, Freigabe Funktionstoken
      SSCam_delActiveToken($hash);
	  Log3($name, 2, "$name - ERROR - Login or privilege of user $username unsuccessful"); 
      return;
  }

  my $httptimeout = AttrVal($name,"httptimeout",60);
  $httptimeout    = 60 if($httptimeout < 60);
  Log3($name, 4, "$name - HTTP-Call login will be done with httptimeout-Value: $httptimeout s");
  
  my $urlwopw;      # nur zur Anzeige bei verbose >= 4 und "showPassInLog" == 0
  
  # sid in Quotes einschliessen oder nicht -> bei Problemen mit 402 - Permission denied
  my $sid = AttrVal($name, "noQuotesForSID", "0") == 1 ? "sid" : "\"sid\"";
  
  if (AttrVal($name,"session","DSM") eq "SurveillanceStation") {
      $url = "$proto://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Login&account=$username&passwd=$password&session=SurveillanceStation&format=$sid";
      $urlwopw = "$proto://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Login&account=$username&passwd=*****&session=SurveillanceStation&format=$sid";
  } else {
      $url = "$proto://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Login&account=$username&passwd=$password&format=$sid"; 
      $urlwopw = "$proto://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Login&account=$username&passwd=*****&format=$sid";
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
            SSCam_delActiveToken($hash);
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
       
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode","none");
            readingsBulkUpdate($hash,"Error","none");
            readingsEndUpdate($hash, 1);
       
            Log3($name, 4, "$name - Login of User $username successful - SID: $sid");
			
			return &$subref($hash);
        
		} else {          
            # Errorcode aus JSON ermitteln
            my $errorcode = $data->{'error'}->{'code'};
       
            # Fehlertext zum Errorcode ermitteln
            my $error = SSCam_experrorauth($hash,$errorcode);

            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode",$errorcode);
            readingsBulkUpdate($hash,"Error",$error);
            readingsEndUpdate($hash, 1);
       
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
   my $proto            = $hash->{PROTOCOL};
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
       $url = "$proto://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Logout&session=SurveillanceStation&_sid=$sid";
   } else {
       $url = "$proto://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Logout&_sid=$sid";
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
   my ($success, $username)   = SSCam_getcredentials($hash,0,"svs");
   my $OpMode                 = $hash->{OPMODE};
   my $data;
   my $error;
   my $errorcode;
  
   if ($err ne "") {
       # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
       Log3($name, 2, "$name - error while requesting ".$param->{url}." - $err"); 
       readingsSingleUpdate($hash, "Error", $err, 1);                                     	      
   
   } elsif ($myjson ne "") {
       # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
       Log3($name, 4, "$name - URL-Call: ".$param->{url});
        
       # Evaluiere ob Daten im JSON-Format empfangen wurden
       ($hash, $success) = SSCam_evaljson($hash,$myjson);
        
       unless ($success) {
           Log3($name, 4, "$name - Data returned: ".$myjson);
           SSCam_delActiveToken($hash);
           return;
       }
        
       $data = decode_json($myjson);
        
       # Logausgabe decodierte JSON Daten
       Log3($name, 4, "$name - JSON returned: ". Dumper $data);
   
       $success = $data->{'success'};

       if ($success) {
           # die Logout-URL konnte erfolgreich aufgerufen werden                        
           Log3($name, 2, "$name - Session of User \"$username\" terminated - session ID \"$sid\" deleted");
             
       } else {
           # Errorcode aus JSON ermitteln
           $errorcode = $data->{'error'}->{'code'};

           # Fehlertext zum Errorcode ermitteln
           $error = SSCam_experrorauth($hash,$errorcode);

           Log3($name, 2, "$name - ERROR - Logout of User $username was not successful, however SID: \"$sid\" has been deleted. Errorcode: $errorcode - $error");
       }
   }   
   # Session-ID aus Helper-hash löschen
   delete $hash->{HELPER}{SID};
   
   # ausgeführte Funktion ist erledigt (auch wenn logout nicht erfolgreich), Freigabe Funktionstoken
   SSCam_delActiveToken($hash);
   
   CancelDelayedShutdown($name);
return;
}

#############################################################################################
#                                   Autocreate für Kameras
#                                   $sn = Name der Kamera in SVS
#############################################################################################
sub SSCam_Autocreate ($$) { 
   my ($hash,$sn) = @_;
   my $name = $hash->{NAME};
   my $type = $hash->{TYPE};
   
   my ($cmd, $err, $camname, $camhash);
   
   my $dcn  = (devspec2array("TYPE=SSCam:FILTER=CAMNAME=$sn"))[0];  # ist das Device aus der SVS bereits angelegt ?
   $camhash = $defs{$dcn} if($dcn);                                 # existiert ein Hash des Devices ?

   if(!$camhash) {
       $camname = "SSCam.".makeDeviceName($sn);                     # erlaubten Kameranamen für FHEM erzeugen
       my $arg = $hash->{SERVERADDR}." ".$hash->{SERVERPORT};
       $cmd = "$camname $type $sn $arg";
       Log3($name, 2, "$name - Autocreate camera: define $cmd");
       $err = CommandDefine(undef, $cmd);
       
       if($err) {
           Log3($name, 1, "ERROR: $err");
       } else {
           my $room = AttrVal($name, "room", "SSCam");
           my $session =  AttrVal($name, "session", "DSM");
           CommandAttr(undef,"$camname room $room");
           CommandAttr(undef,"$camname session $session");
           CommandAttr(undef,"$camname icon it_camera");
           CommandAttr(undef,"$camname devStateIcon .*isable.*:set_off .*nap:li_wht_on");
           CommandAttr(undef,"$camname pollcaminfoall 210");
           CommandAttr(undef,"$camname pollnologging 1");	
           CommandAttr(undef,"$camname httptimeout 20");

           # Credentials abrufen und setzen
           my ($success, $username, $password) = SSCam_getcredentials($hash,0,"svs");
           if($success) {
               CommandSet(undef, "$camname credentials $username $password");   
           }
       }
       
   } else {
       Log3($name, 4, "$name - Autocreate - SVS camera \"$sn\" already defined by \"$dcn\" ");
       $camname = "";
   }  
   
return ($err,$camname);
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
      if( ($hash->{HELPER}{RUNVIEW} && $hash->{HELPER}{RUNVIEW} =~ m/^live_.*hls$/) || $OpMode =~ m/^.*_hls$/ ) {
          # HLS aktivate/deaktivate bringt kein JSON wenn bereits aktiviert/deaktiviert
          Log3($name, 5, "$name - HLS-activation data return: $myjson");
          if ($myjson =~ m/{"success":true}/) {
              $success = 1;
              $myjson  = '{"success":true}';    
          } 
      } else {
          $success = 0;

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
#      $hash, $pload (1=Page reload), SSCam-state-Event(1=Event), SSCamSTRM-Event (1=Event)
######################################################################################################
sub SSCam_refresh($$$$) { 
  my ($hash,$pload,$lpoll_scm,$lpoll_strm) = @_;
  my ($name,$st);
  if (ref $hash ne "HASH")
  {
    ($name,$pload,$lpoll_scm,$lpoll_strm) = split ",",$hash;
    $hash = $defs{$name};
  } else {
    $name = $hash->{NAME};
  }
  my $fpr  = 0;
  
  # SSCamSTRM-Device mit hinterlegter FUUID ($hash->{HELPER}{INFORM}) selektieren
  my @spgs = devspec2array("TYPE=SSCamSTRM");
  my $room = "";
  foreach(@spgs) {   
      if($defs{$_}{PARENT} eq $name) {
          next if(IsDisabled($defs{$_}{NAME}) || !$hash->{HELPER}{INFORM} || $hash->{HELPER}{INFORM} ne $defs{$_}{FUUID});
		  $fpr  = AttrVal($defs{$_}{NAME},"forcePageRefresh",0);
          $room = AttrVal($defs{$_}{NAME},"room","");
		  Log3($name, 4, "$name - SSCam_refresh - pagerefresh: $defs{$_}{NAME}") if($fpr);
      }
  }
  
  # Page-Reload
  if($pload && $room) {
      if(!$fpr) {
          # nur Räume mit dem SSCamSTRM-Device reloaden
	      my @rooms = split(",",$room);
	      foreach (@rooms) {
	          my $r = $_;
              { map { FW_directNotify("FILTER=room=$r", "#FHEMWEB:$_", "location.reload('true')", "") } devspec2array("TYPE=FHEMWEB") } 
	      }
      }
  } elsif ($pload || $fpr) {
      # trifft zu bei Detailansicht oder im FLOORPLAN bzw. Dashboard oder wenn Seitenrefresh mit dem 
      # SSCamSTRM-Attribut "forcePageRefresh" erzwungen wird
      { map { FW_directNotify("#FHEMWEB:$_", "location.reload('true')", "") } devspec2array("TYPE=FHEMWEB") }
  } 
  
  # Aufnahmestatus/Disabledstatus in state abbilden & SSCam-Device state setzen (mit/ohne Event)
  $st = (ReadingsVal($name, "Availability", "enabled") eq "disabled")?"disabled":(ReadingsVal($name, "Record", "") eq "Start")?"on":"off";  
  if($lpoll_scm) {
      readingsSingleUpdate($hash,"state", $st, 1);
  } else {
      readingsSingleUpdate($hash,"state", $st, 0);  
  }
  
  # parentState des SSCamSTRM-Device updaten
  $st = ReadingsVal($name, "state", "initialized");  
  foreach(@spgs) {   
      if($defs{$_}{PARENT} eq $name) {
          next if(IsDisabled($defs{$_}{NAME}) || !$hash->{HELPER}{INFORM} || $hash->{HELPER}{INFORM} ne $defs{$_}{FUUID});
          readingsBeginUpdate($defs{$_});
          readingsBulkUpdate($defs{$_},"parentState", $st);
          readingsBulkUpdate($defs{$_},"state", "updated");
          readingsEndUpdate($defs{$_}, 1);
		  Log3($name, 4, "$name - SSCam_refresh - caller: $_, FUUID: $hash->{HELPER}{INFORM}");
		  delete $hash->{HELPER}{INFORM};
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
#                       JSON Boolean Test und Mapping
###############################################################################
sub SSCam_jboolmap($){ 
  my ($bool)= @_;
  
  if(JSON::is_bool($bool)) {
      $bool = $bool?"true":"false";
  }
  
return $bool;
}

###############################################################################
#      Ermittlung Anzahl und Größe der abzurufenden Schnappschußdaten
#
#      $force = wenn auf jeden Fall der/die letzten Snaps von der SVS
#               abgerufen werden sollen unabhängig ob LastSnapId vorhanden ist
###############################################################################
sub SSCam_snaplimsize ($;$) {      
  my ($hash,$force) = @_;
  my $name  = $hash->{NAME};
  my ($slim,$ssize);
  
  if(!AttrVal($name,"snapGalleryBoost",0)) {
      $slim  = 1;
      $ssize = 0;
  } else {
      $hash->{HELPER}{GETSNAPGALLERY} = 1;
	  $slim = AttrVal($name,"snapGalleryNumber",$SSCam_slim);               # Anzahl der abzurufenden Snaps
  }
  
  if(AttrVal($name,"snapGallerySize","Icon") eq "Full") {
      $ssize = 2;                                                           # Full Size
  } else {
      $ssize = 1;                                                           # Icon Size
  }

  if($hash->{HELPER}{CANSENDSNAP} || $hash->{HELPER}{CANTELESNAP}) {
      # Versand Schnappschuß darf erfolgen falls gewünscht 
      $ssize = 2;                                                           # Full Size für EMail/Telegram -Versand
  }
  
  if($hash->{HELPER}{SNAPNUM}) {
      $slim = delete $hash->{HELPER}{SNAPNUM};                              # enthält die Anzahl der ausgelösten Schnappschüsse
      $hash->{HELPER}{GETSNAPGALLERY} = 1;                                  # Steuerbit für Snap-Galerie bzw. Daten mehrerer Schnappschüsse abrufen
  }
  
  my @strmdevs = devspec2array("TYPE=SSCamSTRM:FILTER=PARENT=$name:FILTER=MODEL=lastsnap");
  if(scalar(@strmdevs) >= 1) {
      Log3($name, 4, "$name - Streaming devs of type \"lastsnap\": @strmdevs");
  }
  
  $hash->{HELPER}{GETSNAPGALLERY} = 1 if($force);                           # Bugfix 04.03.2019 Forum:https://forum.fhem.de/index.php/topic,45671.msg914685.html#msg914685
  
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
sub SSCam_extoptpar($$$) { 
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
#  Helper für HLS Lieferfähigkeit
#  HLS kann geliefert werden wenn "SYNO.SurveillanceStation.VideoStream" 
#  existiert und Reading CamStreamFormat "HLS" ist   
###############################################################################
sub SSCam_IsHLSCap($) { 
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  my $ret    = 0;
  my $api    = $hash->{HELPER}{APIVIDEOSTMSMAXVER};
  my $csf    = (ReadingsVal($name,"CamStreamFormat","MJPEG") eq "HLS")?1:0;
  
  $ret = 1 if($api && $csf);
  
return $ret;
}

###############################################################################
# Clienthash übernehmen oder zusammenstellen
# Identifikation ob über FHEMWEB ausgelöst oder nicht -> erstellen $hash->CL
sub SSCam_getclhash($;$$) {      
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
sub SSCam_ptzpanel(@) {
  my ($name,$ptzcdev,$ptzcontrol,$ftui) = @_; 
  my $hash        = $defs{$name};
  my $iconpath    = AttrVal("$name","ptzPanel_iconPath","www/images/sscam");
  my $iconprefix  = AttrVal("$name","ptzPanel_iconPrefix","black_btn_");
  my $valPresets  = ReadingsVal("$name","Presets","");
  my $valPatrols  = ReadingsVal("$name","Patrols","");
  my $rowisset    = 0;
  my ($pbs,$pbsf) = ("","");
  my ($row,$ptz_ret);
  
  return "" if(SSCam_myVersion($hash) <= 71);
  
  $pbs      = AttrVal($ptzcdev,"ptzButtonSize", 100);                                                     # Größe der Druckbuttons in %
  $pbsf     = AttrVal($ptzcdev,"ptzButtonSizeFTUI", 100);                                                 # Größe der Druckbuttons im FTUI in %
 
  $ptz_ret  = "";
  $ptz_ret .= "<style>TD.ptzcontrol {padding: 5px 7px;}</style>";
  $ptz_ret .= "<style>.defsize { font-size:16px; } </style>";
  $ptz_ret .= '<table class="rc_body defsize">';

  foreach my $rownr (0..9) {
      $rownr = sprintf("%2.2d",$rownr);
      $row   = AttrVal("$name","ptzPanel_row$rownr",undef);
      next if (!$row);
      $rowisset = 1;
      $ptz_ret .= "<tr>";
      my @btn = split (",",$row);                                                                            # die Anzahl Buttons in einer Reihe
      
      foreach my $btnnr (0..$#btn) {                 
          $ptz_ret .= '<td class="ptzcontrol">';
          if ($btn[$btnnr] ne "") {
              my $cmd;
              my $img;
              if ($btn[$btnnr] =~ /(.*?):(.*)/) {                                                            # enthält Komando -> <command>:<image>
                  $cmd = $1;
                  $img = $2;
              } else {                                                                                       # button has format <command> or is empty
                  $cmd = $btn[$btnnr];
                  $img = $btn[$btnnr];
              }
		      if ($img =~ m/\.svg/) {                                                                        # Verwendung für SVG's
		          $img = FW_makeImage($img, $cmd, "rc-button");
		      } else {                                                                                       # $FW_ME = URL-Pfad unter dem der FHEMWEB-Server via HTTP erreichbar ist, z.B. /fhem
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
  
  ########################
  # add Preset & Patrols
  if(!$ftui) {
      my ($Presets,$Patrols,$fn);
      my $cmdPreset = "goPreset";
      my $cmdPatrol = "runPatrol";
      
      foreach $fn (sort keys %{$data{webCmdFn}}) {
          no strict "refs";
          $Presets = &{$data{webCmdFn}{$fn}}($FW_wname,$name,"",$cmdPreset,$valPresets);
          use strict "refs";
          last if(defined($Presets));
      }
      if($Presets) {
          $Presets =~ s,^<td[^>]*>(.*)</td>$,$1,;
      } else {
          $Presets = FW_pH "cmd.$name=set $name $cmdPreset", $cmdPreset, 0, "", 1, 1;
      }

      foreach $fn (sort keys %{$data{webCmdFn}}) {
          no strict "refs";
          $Patrols = &{$data{webCmdFn}{$fn}}($FW_wname,$name,"",$cmdPatrol,$valPatrols);
          use strict "refs";
          last if(defined($Patrols));
      }
      
      if($Patrols) {
          $Patrols =~ s,^<td[^>]*>(.*)</td>$,$1,;
      } else {
          $Patrols = FW_pH "cmd.$name=set $name $cmdPatrol", $cmdPatrol, 0, "", 1, 1;
      }
      
      $ptz_ret .= '<table class="rc_body defsize">';
      
      $ptz_ret .= "<tr>";
      $ptz_ret .= "<td>Preset: </td><td>$Presets</td>";  
      $ptz_ret .= "</tr>";
      
      $ptz_ret .= "<tr>";
      $ptz_ret .= "<td>Patrol: </td><td>$Patrols</td>";
      $ptz_ret .= "</tr>";

      $ptz_ret .= "</table>";
  }
  
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
  
  my $p = ReadingsVal("$name","Presets","");
  if($p ne "") {
      my @h;
      my $arg = "ptzPanel_Home";
      my @ua  = split(" ", $attr{$name}{userattr});
      foreach (@ua) { 
          push(@h,$_) if($_ !~ m/$arg.*/);
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
#      Funktion für SSCamSTRM-Devices - Kamera Liveview weblink device
#      API: SYNO.SurveillanceStation.VideoStreaming
#      Methode: GetLiveViewPath
#
#      $camname = Name der Kamaera (Parent-Device)
#      $strmdev = Name des Streaming-Devices
#      $fmt     = Streaming Format
#
######################################################################################
sub SSCam_StreamDev($$$;$) {
  my ($camname,$strmdev,$fmt,$ftui) = @_; 
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
  my $proto              = $hash->{PROTOCOL};
  $ftui                  = ($ftui && $ftui eq "ftui")?1:0;
  my $hdrAlign           = "center";
  my ($cause,$ret,$link,$audiolink,$devWlink,$wlhash,$wlalias);
  
  # Kontext des SSCamSTRM-Devices speichern für SSCam_refresh
  $hash->{HELPER}{STRMDEV}    = $strmdev;                   # Name des aufrufenden SSCamSTRM-Devices
  $hash->{HELPER}{STRMROOM}   = $FW_room?$FW_room:"";       # Raum aus dem das SSCamSTRM-Device die Funktion aufrief
  $hash->{HELPER}{STRMDETAIL} = $FW_detail?$FW_detail:"";   # Name des SSCamSTRM-Devices (wenn Detailansicht)
  my $streamHash              = $defs{$strmdev};            # Hash des SSCamSTRM-Devices
  my $uuid                    = $streamHash->{FUUID};       # eindeutige UUID des Streamingdevices
  delete $streamHash->{HELPER}{STREAM};
  delete $streamHash->{HELPER}{STREAMACTIVE};               # Statusbit ob ein Stream aktiviert ist
  
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
  
  my $ha  = AttrVal($camname, "htmlattr", 'width="500" height="325"');      # HTML Attribute der Cam
  $ha     = AttrVal($strmdev, "htmlattr", $ha);                             # htmlattr mit htmlattr Streaming-Device übersteuern 
  if($ftui) {
      $ha = AttrVal($strmdev, "htmlattrFTUI", $ha);                         # wenn aus FTUI aufgerufen divers setzen 
  }
  
  my $hf  = AttrVal($strmdev, "hideButtons", 0);                            # Drucktasten im unteren Bereich ausblenden ?
  
  my $pws = AttrVal($strmdev, "popupWindowSize", "");                       # Größe eines Popups
  $pws    =~ s/"//g if($pws);
  
  my $show = $defs{$streamHash->{PARENT}}->{HELPER}{ACTSTRM} if($streamHash->{MODEL} =~ /switched/);
  $show = $show?"($show)":"";
  
  my $alias  = AttrVal($strmdev, "alias", $strmdev);                        # Linktext als Aliasname oder Devicename setzen
  my $dlink  = "<a href=\"/fhem?detail=$strmdev\">$alias</a>";
  
  my $StmKey = ReadingsVal($camname,"StmKey",undef);
  
  # Javascript Bibliothek für Tooltips (http://www.walterzorn.de/tooltip/tooltip.htm#download) und Texte
  my $calias = $hash->{CAMNAME};                                            # Alias der Kamera
  my $ttjs   = "/fhem/pgm2/sscam_tooltip.js"; 
  my ($ttrefresh, $ttrecstart, $ttrecstop, $ttsnap, $ttcmdstop, $tthlsreact, $ttmjpegrun, $tthlsrun, $ttlrrun, $tth264run, $ttlmjpegrun, $ttlsnaprun);
  if(AttrVal("global","language","EN") =~ /EN/) {
	  $ttrefresh  = $SSCam_ttips_en{"ttrefresh"}; $ttrefresh =~ s/§NAME§/$calias/g;
      $ttrecstart = $SSCam_ttips_en{"ttrecstart"}; $ttrecstart =~ s/§NAME§/$calias/g;
      $ttrecstop  = $SSCam_ttips_en{"ttrecstop"}; $ttrecstop =~ s/§NAME§/$calias/g;
      $ttsnap     = $SSCam_ttips_en{"ttsnap"}; $ttsnap =~ s/§NAME§/$calias/g;
      $ttcmdstop  = $SSCam_ttips_en{"ttcmdstop"}; $ttcmdstop =~ s/§NAME§/$calias/g;
      $tthlsreact = $SSCam_ttips_en{"tthlsreact"}; $tthlsreact =~ s/§NAME§/$calias/g;
      $ttmjpegrun = $SSCam_ttips_en{"ttmjpegrun"}; $ttmjpegrun =~ s/§NAME§/$calias/g;
      $tthlsrun   = $SSCam_ttips_en{"tthlsrun"}; $tthlsrun =~ s/§NAME§/$calias/g;
      $ttlrrun    = $SSCam_ttips_en{"ttlrrun"}; $ttlrrun =~ s/§NAME§/$calias/g;
      $tth264run  = $SSCam_ttips_en{"tth264run"}; $tth264run =~ s/§NAME§/$calias/g;	  
      $ttlmjpegrun= $SSCam_ttips_en{"ttlmjpegrun"}; $ttlmjpegrun =~ s/§NAME§/$calias/g;
	  $ttlsnaprun = $SSCam_ttips_en{"ttlsnaprun"}; $ttlsnaprun =~ s/§NAME§/$calias/g;
  } else {
	  $ttrefresh  = $SSCam_ttips_de{"ttrefresh"}; $ttrefresh =~ s/§NAME§/$calias/g;
      $ttrecstart = $SSCam_ttips_de{"ttrecstart"}; $ttrecstart =~ s/§NAME§/$calias/g;
      $ttrecstop  = $SSCam_ttips_de{"ttrecstop"}; $ttrecstop =~ s/§NAME§/$calias/g;
      $ttsnap     = $SSCam_ttips_de{"ttsnap"}; $ttsnap =~ s/§NAME§/$calias/g;
      $ttcmdstop  = $SSCam_ttips_de{"ttcmdstop"}; $ttcmdstop =~ s/§NAME§/$calias/g;
      $tthlsreact = $SSCam_ttips_de{"tthlsreact"}; $tthlsreact =~ s/§NAME§/$calias/g;
      $ttmjpegrun = $SSCam_ttips_de{"ttmjpegrun"}; $ttmjpegrun =~ s/§NAME§/$calias/g;
      $tthlsrun   = $SSCam_ttips_de{"tthlsrun"}; $tthlsrun =~ s/§NAME§/$calias/g;
      $ttlrrun    = $SSCam_ttips_de{"ttlrrun"}; $ttlrrun =~ s/§NAME§/$calias/g;
      $tth264run  = $SSCam_ttips_de{"tth264run"}; $tth264run =~ s/§NAME§/$calias/g;	  
      $ttlmjpegrun= $SSCam_ttips_de{"ttlmjpegrun"}; $ttlmjpegrun =~ s/§NAME§/$calias/g;
	  $ttlsnaprun = $SSCam_ttips_de{"ttlsnaprun"}; $ttlsnaprun =~ s/§NAME§/$calias/g;
  }
  
  $ret  = "";
  $ret .= "<script type=\"text/javascript\" src=\"$ttjs\"></script>";               
  $ret .= '<table class="block wide internals" style="margin-left:auto;margin-right:auto">';
  if($ftui) {
      $ret .= "<span align=\"$hdrAlign\">$dlink $show </span><br>"  if(!AttrVal($strmdev,"hideDisplayNameFTUI",0));
  } else {
      $ret .= "<span align=\"$hdrAlign\">$dlink $show </span><br>"  if(!AttrVal($strmdev,"hideDisplayName",0));
  }  
  $ret .= '<tbody>';
  $ret .= '<tr class="odd">';  

  if(!$StmKey || ReadingsVal($camname, "Availability", "") ne "enabled" || IsDisabled($camname)) {
      # Ausgabe bei Fehler
      my $cam = AttrVal($camname, "alias", $camname);                         # Linktext als Aliasname oder Devicename setzen
      $cause  = !$StmKey?"Camera $cam has no Reading \"StmKey\" set !":"Cam \"$cam\" is disabled";
      $cause  = "Camera \"$cam\" is disabled" if(IsDisabled($camname));
      $ret   .= "<td> <br> <b> $cause </b> <br><br></td>";
      $ret   .= '</tr>';
      $ret   .= '</tbody>';
      $ret   .= '</table>';
      $ret   .= '</div>';
      return $ret; 
  }
  
  if ($fmt =~ /mjpeg/) {
      if(ReadingsVal($camname, "SVSversion", "8.2.3-5828") eq "8.2.3-5828" && ReadingsVal($camname, "CamVideoType", "") !~ /MJPEG/) {  
          $ret .= "<td> <br> <b> Because SVS version 8.2.3-5828 is running you cannot see the MJPEG-Stream. Please upgrade to a higher SVS version ! </b> <br><br>";
      } else {
          if($apivideostmsmaxver) {                                  
              $link = "$proto://$serveraddr:$serverport/webapi/$apivideostmspath?api=$apivideostms&version=$apivideostmsmaxver&method=Stream&cameraId=$camid&format=mjpeg&_sid=$sid"; 
          } elsif ($hash->{HELPER}{STMKEYMJPEGHTTP}) {
              $link = $hash->{HELPER}{STMKEYMJPEGHTTP};
          }
          if($apiaudiostmmaxver) {                                   
              $audiolink = "$proto://$serveraddr:$serverport/webapi/$apiaudiostmpath?api=$apiaudiostm&version=$apiaudiostmmaxver&method=Stream&cameraId=$camid&_sid=$sid"; 
          }
          if(!$ftui) {
              $ret .= "<td><img src=$link $ha onClick=\"FW_okDialog('<img src=$link $pws>')\"><br>";
          } else {
              $ret .= "<td><img src=$link $ha><br>";
          }
          $streamHash->{HELPER}{STREAM}       = "<img src=$link $pws>";    # Stream für "get <SSCamSTRM-Device> popupStream" speichern
          $streamHash->{HELPER}{STREAMACTIVE} = 1 if($link);               # Statusbit wenn ein Stream aktiviert ist      
      }
      if(!$hf) {
          if(ReadingsVal($camname, "Record", "Stop") eq "Stop") {
                 # Aufnahmebutton endlos Start
                 $ret .= "<a onClick=\"$cmdrecendless\" onmouseover=\"Tip('$ttrecstart')\" onmouseout=\"UnTip()\">$imgrecendless </a>";
              }	else {
                 # Aufnahmebutton Stop
                 $ret .= "<a onClick=\"$cmdrecstop\" onmouseover=\"Tip('$ttrecstop')\" onmouseout=\"UnTip()\">$imgrecstop </a>";
              }	      
          $ret .= "<a onClick=\"$cmddosnap\" onmouseover=\"Tip('$ttsnap')\" onmouseout=\"UnTip()\">$imgdosnap </a>"; 
      }      
      $ret .= "</td>";      
      if(AttrVal($camname,"ptzPanel_use",1)) {
          my $ptz_ret = SSCam_ptzpanel($camname,$strmdev,'',$ftui);
          if($ptz_ret) {         
              $ret .= "<td>$ptz_ret</td>";
          }
      }
      if($audiolink && ReadingsVal($camname, "CamAudioType", "Unknown") !~ /Unknown/) {
          $ret .= '</tr>';
          $ret .= '<tr class="odd">';
          $ret .= "<td><audio src=$audiolink preload='none' volume='0.5' controls>
                       Your browser does not support the audio element.      
                       </audio>";
          $ret .= "</td>";
          $ret .= "<td></td>" if(AttrVal($camname,"ptzPanel_use",0));
      }      
  
  } elsif ($fmt =~ /lastsnap/) { 
      $link     = $hash->{HELPER}{".LASTSNAP"};
      my $gattr = (AttrVal($camname,"snapGallerySize","Icon") eq "Full")?$ha:""; 
      if($link) {
          if(!$ftui) {
              $ret .= "<td><img src='data:image/jpeg;base64,$link' $gattr onClick=\"FW_okDialog('<img src=data:image/jpeg;base64,$link $pws>')\"><br>";
          } else {
              $ret .= "<td><img src='data:image/jpeg;base64,$link' $gattr><br>";
          }
          if(!$hf) {
              $ret .= "<a onClick=\"$cmddosnap\" onmouseover=\"Tip('$ttsnap')\" onmouseout=\"UnTip()\">$imgdosnap </a>";
          }
          $ret .= "</td>";
          $streamHash->{HELPER}{STREAM} = "<img src=data:image/jpeg;base64,$link $pws>";      # Stream für "get <SSCamSTRM-Device> popupStream" speichern
          $streamHash->{HELPER}{STREAMACTIVE} = 1 if($link);                                  # Statusbit wenn ein Stream aktiviert ist
      } else {
          $cause = "no snapshot available to display";
          $cause = "kein Schnappschuss zur Anzeige vorhanden" if(AttrVal("global","language","EN") =~ /DE/i);
          $ret .= "<td> <br> <b> $cause </b> <br><br></td>";       
      }
  
  } elsif ($fmt =~ /generic/) {  
      my $htag  = AttrVal($strmdev,"genericStrmHtmlTag",AttrVal($camname,"genericStrmHtmlTag",""));
      
      if( $htag =~ m/^\s*(.*)\s*$/s ) {
          $htag = $1;
          $htag =~ s/\$NAME/$camname/g;
          $htag =~ s/\$HTMLATTR/$ha/g;
          $htag =~ s/\$PWS/$pws/g;
      }

      if(!$htag) {
          $ret .= "<td> <br> <b> Set attribute \"genericStrmHtmlTag\" in device <a href=\"/fhem?detail=$camname\">$camname</a> or in device <a href=\"/fhem?detail=$strmdev\">$strmdev</a></b> <br><br></td>";
          $ret .= '</tr>';
          $ret .= '</tbody>';
          $ret .= '</table>';
          $ret .= '</div>';
          return $ret; 
      }
      $ret .= "<td>";
      $ret .= "$htag";
      if($htag) {
          # Popup-Tag um den Popup-Teil bereinigen 
          my $ptag = $htag;
          $ptag    =~ m/^(\s+)?(?<b><)(\s+)?(?<heart>.*)(\s+)?(?<nh>onClick=.*)(\s+)?(?<e>>)(\s+)?$/s;
          $ptag    = $+{heart}?$+{b}.$+{heart}.$+{e}:$ptag;
          $streamHash->{HELPER}{STREAM}       = "$ptag";   # Stream für "set <SSCamSTRM-Device> popupStream" speichern
          $streamHash->{HELPER}{STREAM}       =~ s/["']//g;
          $streamHash->{HELPER}{STREAM}       =~ s/\s+/ /g;
          $streamHash->{HELPER}{STREAMACTIVE} = 1;         # Statusbit wenn ein Stream aktiviert ist
      }
      $ret .= "<br>";
      Log3($strmdev, 4, "$strmdev - generic Stream params:\n$htag");
      if(!$hf) {
          $ret .= "<a onClick=\"$cmdrefresh\" onmouseover=\"Tip('$ttrefresh')\" onmouseout=\"UnTip()\">$imgrefresh </a>";
          $ret .= $imgblank;
          if(ReadingsVal($camname, "Record", "Stop") eq "Stop") {
                 # Aufnahmebutton endlos Start
                 $ret .= "<a onClick=\"$cmdrecendless\" onmouseover=\"Tip('$ttrecstart')\" onmouseout=\"UnTip()\">$imgrecendless </a>";
              }	else {
                 # Aufnahmebutton Stop
                 $ret .= "<a onClick=\"$cmdrecstop\" onmouseover=\"Tip('$ttrecstop')\" onmouseout=\"UnTip()\">$imgrecstop </a>";
              }	      
          $ret .= "<a onClick=\"$cmddosnap\" onmouseover=\"Tip('$ttsnap')\" onmouseout=\"UnTip()\">$imgdosnap </a>";
      }      
      $ret .= "</td>";      
      if(AttrVal($camname,"ptzPanel_use",1)) {
          my $ptz_ret = SSCam_ptzpanel($camname,$strmdev,'',$ftui);
          if($ptz_ret) { 
              $ret .= "<td>$ptz_ret</td>";
          }
      }    
  
  } elsif ($fmt =~ /hls/) {
      # es ist ein .m3u8-File bzw. ein Link dorthin zu übergeben
      my $cam  = AttrVal($camname, "alias", $camname);
      my $m3u8 = AttrVal($camname, "hlsStrmObject", "");

      if( $m3u8 =~ m/^\s*(.*)\s*$/s ) {
          $m3u8 = $1;
          $m3u8 =~ s/\$NAME/$camname/g;
      }  
      my $d = $camname;
      $d =~ s/\./_/;          # Namensableitung zur javascript Codeanpassung
      
      if(!$m3u8) {
          $cause = "You have to specify attribute \"hlsStrmObject\" in Camera $cam !";
          $ret .= "<td> <br> <b> $cause </b> <br><br></td>";
          $ret .= '</tr>';
          $ret .= '</tbody>';
          $ret .= '</table>';
          $ret .= '</div>';
      return $ret; 
      }      
      
      $ret .= "<td><video $ha id=video_$d controls autoplay muted></video><br>";
      $ret .= SSCam_bindhlsjs ($camname, $strmdev, $m3u8, $d); 
      
      $streamHash->{HELPER}{STREAM} = "<video $pws id=video_$d></video>";  # Stream für "set <SSCamSTRM-Device> popupStream" speichern   
      $streamHash->{HELPER}{STREAMACTIVE} = 1;                             # Statusbit wenn ein Stream aktiviert ist
      if(!$hf) {
          $ret .= "<a onClick=\"$cmdrefresh\" onmouseover=\"Tip('$ttrefresh')\" onmouseout=\"UnTip()\">$imgrefresh </a>";
          $ret .= $imgblank;
          if(ReadingsVal($camname, "Record", "Stop") eq "Stop") {
                 # Aufnahmebutton endlos Start
                 $ret .= "<a onClick=\"$cmdrecendless\" onmouseover=\"Tip('$ttrecstart')\" onmouseout=\"UnTip()\">$imgrecendless </a>";
              }	else {
                 # Aufnahmebutton Stop
                 $ret .= "<a onClick=\"$cmdrecstop\" onmouseover=\"Tip('$ttrecstop')\" onmouseout=\"UnTip()\">$imgrecstop </a>";
              }	      
          $ret .= "<a onClick=\"$cmddosnap\" onmouseover=\"Tip('$ttsnap')\" onmouseout=\"UnTip()\">$imgdosnap </a>"; 
      }      
      $ret .= "</td>";      
      if(AttrVal($camname,"ptzPanel_use",1)) {
          my $ptz_ret = SSCam_ptzpanel($camname,$strmdev,'',$ftui);
          if($ptz_ret) { 
              $ret .= "<td>$ptz_ret</td>";
          }
      }  
  
  } elsif ($fmt =~ /switched/) {
      my $wltype = $hash->{HELPER}{WLTYPE};
      $link = $hash->{HELPER}{LINK};
      
      if($link && $wltype =~ /image|iframe|video|base64img|embed|hls/) {
          if($wltype =~ /image/) {
              if(ReadingsVal($camname, "SVSversion", "8.2.3-5828") eq "8.2.3-5828" && ReadingsVal($camname, "CamVideoType", "") !~ /MJPEG/) {             
                  $ret .= "<td> <br> <b> Because SVS version 8.2.3-5828 is running you cannot see the MJPEG-Stream. Please upgrade to a higher SVS version ! </b> <br><br>";
              } else {
                  if(!$ftui) {
                      $ret .= "<td><img src=$link $ha onClick=\"FW_okDialog('<img src=$link $pws>')\"><br>" if($link);
                  } else {
                      $ret .= "<td><img src=$link $ha><br>" if($link);
                  }
                  $streamHash->{HELPER}{STREAM} = "<img src=$link $pws>";    # Stream für "set <SSCamSTRM-Device> popupStream" speichern
                  $streamHash->{HELPER}{STREAMACTIVE} = 1 if($link);         # Statusbit wenn ein Stream aktiviert ist
              }    
              $ret .= "<a onClick=\"$cmdstop\" onmouseover=\"Tip('$ttcmdstop')\" onmouseout=\"UnTip()\">$imgstop </a>";
              $ret .= $imgblank;              
              if($hash->{HELPER}{RUNVIEW} =~ /live_fw/) {              
                  if(ReadingsVal($camname, "Record", "Stop") eq "Stop") {
                      # Aufnahmebutton endlos Start
                      $ret .= "<a onClick=\"$cmdrecendless\" onmouseover=\"Tip('$ttrecstart')\" onmouseout=\"UnTip()\">$imgrecendless </a>";
                  }	else {
                      # Aufnahmebutton Stop
                      $ret .= "<a onClick=\"$cmdrecstop\" onmouseover=\"Tip('$ttrecstop')\" onmouseout=\"UnTip()\">$imgrecstop </a>";
                  }	      
                  $ret .= "<a onClick=\"$cmddosnap\" onmouseover=\"Tip('$ttsnap')\" onmouseout=\"UnTip()\">$imgdosnap </a>";
              }              
              $ret .= "</td>";
              if(AttrVal($camname,"ptzPanel_use",1) && $hash->{HELPER}{RUNVIEW} =~ /live_fw/) {
                  my $ptz_ret = SSCam_ptzpanel($camname,$strmdev,'',$ftui);
                  if($ptz_ret) { 
                      $ret .= "<td>$ptz_ret</td>";
                  }
              }
              if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($camname, "CamAudioType", "Unknown") !~ /Unknown/) {
                  $ret .= "</tr>";
                  $ret .= '<tr class="odd">';
                  $ret .= "<td><audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>
                               Your browser does not support the audio element.      
                               </audio>";
                  $ret .= "</td>";
                  $ret .= "<td></td>" if(AttrVal($camname,"ptzPanel_use",0));
              }         
          
          } elsif ($wltype =~ /iframe/) {
              if(!$ftui) {
                  $ret .= "<td><iframe src=$link $ha controls autoplay onClick=\"FW_okDialog('<img src=$link $pws>')\">
                           Iframes disabled
                           </iframe><br>" if($link);
              } else {
                  $ret .= "<td><iframe src=$link $ha controls autoplay>
                           Iframes disabled
                           </iframe><br>" if($link);              
              }
              $streamHash->{HELPER}{STREAM} = "<iframe src=$link $pws controls autoplay>".
                                              "Iframes disabled".
                                              "</iframe>";                # Stream für "set <SSCamSTRM-Device> popupStream" speichern
              $streamHash->{HELPER}{STREAMACTIVE} = 1 if($link);          # Statusbit wenn ein Stream aktiviert ist
              $ret .= "<a onClick=\"$cmdstop\" onmouseover=\"Tip('$ttcmdstop')\" onmouseout=\"UnTip()\">$imgstop </a>";
              $ret .= "<a onClick=\"$cmdrefresh\" onmouseover=\"Tip('$ttrefresh')\" onmouseout=\"UnTip()\">$imgrefresh </a>";              
              $ret .= "</td>";
              if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($camname, "CamAudioType", "Unknown") !~ /Unknown/) {
                  $ret .= '</tr>';
                  $ret .= '<tr class="odd">';
                  $ret .= "<td><audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>
                               Your browser does not support the audio element.      
                               </audio>";
                  $ret .= "</td>";
                  $ret .= "<td></td>" if(AttrVal($camname,"ptzPanel_use",0));
              }
          
          } elsif ($wltype =~ /video/) {
              $ret .= "<td><video $ha controls autoplay>
                       <source src=$link type=\"video/mp4\"> 
                       <source src=$link type=\"video/ogg\">
                       <source src=$link type=\"video/webm\">
                       Your browser does not support the video tag
                       </video><br>";
              $streamHash->{HELPER}{STREAM} = "<video $pws controls autoplay>".
                                              "<source src=$link type=\"video/mp4\">". 
                                              "<source src=$link type=\"video/ogg\">".
                                              "<source src=$link type=\"video/webm\">".
                                              "Your browser does not support the video tag".
                                              "</video>";                # Stream für "set <SSCamSTRM-Device> popupStream" speichern              
              $streamHash->{HELPER}{STREAMACTIVE} = 1 if($link);         # Statusbit wenn ein Stream aktiviert ist
              $ret .= "<a onClick=\"$cmdstop\" onmouseover=\"Tip('$ttcmdstop')\" onmouseout=\"UnTip()\">$imgstop </a>"; 
              $ret .= "</td>";
              if($hash->{HELPER}{AUDIOLINK} && ReadingsVal($camname, "CamAudioType", "Unknown") !~ /Unknown/) {
                  $ret .= '</tr>';
                  $ret .= '<tr class="odd">';
                  $ret .= "<td><audio src=$hash->{HELPER}{AUDIOLINK} preload='none' volume='0.5' controls>
                               Your browser does not support the audio element.      
                               </audio>";
                  $ret .= "</td>";
                  $ret .= "<td></td>" if(AttrVal($camname,"ptzPanel_use",0));
              }
          } elsif($wltype =~ /base64img/) {
              if(!$ftui) {
                  $ret .= "<td><img src='data:image/jpeg;base64,$link' $ha onClick=\"FW_okDialog('<img src=data:image/jpeg;base64,$link $pws>')\"><br>" if($link);
              } else {
                  $ret .= "<td><img src='data:image/jpeg;base64,$link' $ha><br>" if($link);
              }
              $streamHash->{HELPER}{STREAM}       = "<img src=data:image/jpeg;base64,$link $pws>";    # Stream für "get <SSCamSTRM-Device> popupStream" speichern
              $streamHash->{HELPER}{STREAMACTIVE} = 1 if($link);                                      # Statusbit wenn ein Stream aktiviert ist
              $ret .= "<a onClick=\"$cmdstop\" onmouseover=\"Tip('$ttcmdstop')\" onmouseout=\"UnTip()\">$imgstop </a>";
              $ret .= $imgblank;
              $ret .= "<a onClick=\"$cmddosnap\" onmouseover=\"Tip('$ttsnap')\" onmouseout=\"UnTip()\">$imgdosnap </a>";
              $ret .= "</td>";
		  
          } elsif($wltype =~ /embed/) {
              if(!$ftui) {
                  $ret .= "<td><embed src=$link $ha onClick=\"FW_okDialog('<img src=$link $pws>')\"></td>" if($link);
              } else {
                  $ret .= "<td><embed src=$link $ha></td>" if($link);
              }
              $streamHash->{HELPER}{STREAM} = "<embed src=$link $pws>";    # Stream für "set <SSCamSTRM-Device> popupStream" speichern
              $streamHash->{HELPER}{STREAMACTIVE} = 1 if($link);           # Statusbit wenn ein Stream aktiviert ist
              
          } elsif($wltype =~ /hls/) {
              $ret .= "<td><video $ha controls autoplay>
                       <source src=$link type=\"application/x-mpegURL\">
                       <source src=$link type=\"video/MP2T\">
                       Your browser does not support the video tag
                       </video><br>";
              $streamHash->{HELPER}{STREAM} = "<video $pws controls autoplay>".
                                              "<source src=$link type=\"application/x-mpegURL\">".
                                              "<source src=$link type=\"video/MP2T\">".
                                              "Your browser does not support the video tag".
                                              "</video>";                # Stream für "set <SSCamSTRM-Device> popupStream" speichern
              $streamHash->{HELPER}{STREAMACTIVE} = 1 if($link);         # Statusbit wenn ein Stream aktiviert ist
              $ret .= "<a onClick=\"$cmdstop\" onmouseover=\"Tip('$ttcmdstop')\" onmouseout=\"UnTip()\">$imgstop </a>";
              $ret .= "<a onClick=\"$cmdrefresh\" onmouseover=\"Tip('$ttrefresh')\" onmouseout=\"UnTip()\">$imgrefresh </a>";
              $ret .= "<a onClick=\"$cmdhlsreact\" onmouseover=\"Tip('$tthlsreact')\" onmouseout=\"UnTip()\">$imghlsreact </a>";
              $ret .= $imgblank;
              if(ReadingsVal($camname, "Record", "Stop") eq "Stop") {
                  # Aufnahmebutton endlos Start
                  $ret .= "<a onClick=\"$cmdrecendless\" onmouseover=\"Tip('$ttrecstart')\" onmouseout=\"UnTip()\">$imgrecendless </a>";
              }	else {
                  # Aufnahmebutton Stop
                  $ret .= "<a onClick=\"$cmdrecstop\" onmouseover=\"Tip('$ttrecstop')\" onmouseout=\"UnTip()\">$imgrecstop </a>";
              }		
              $ret .= "<a onClick=\"$cmddosnap\" onmouseover=\"Tip('$ttsnap')\" onmouseout=\"UnTip()\">$imgdosnap </a>";                   
              $ret .= "</td>";
              if(AttrVal($camname,"ptzPanel_use",1)) {
                  my $ptz_ret = SSCam_ptzpanel($camname,$strmdev,'',$ftui);
                  if($ptz_ret) { 
                      $ret .= "<td>$ptz_ret</td>";
                  }
              }
              
          } 
          
      } else {
          my $cam = AttrVal($camname, "alias", $camname);
          $cause = "Playback cam \"$cam\" switched off";
          $ret .= "<td> <br> <b> $cause </b> <br><br>";
          $ret .= "<a onClick=\"$cmdmjpegrun\" onmouseover=\"Tip('$ttmjpegrun')\" onmouseout=\"UnTip()\">$imgmjpegrun </a>";
          $ret .= "<a onClick=\"$cmdhlsrun\" onmouseover=\"Tip('$tthlsrun')\" onmouseout=\"UnTip()\">$imghlsrun </a>" if(SSCam_IsHLSCap($hash));  
          $ret .= "<a onClick=\"$cmdlrirun\" onmouseover=\"Tip('$ttlrrun')\" onmouseout=\"UnTip()\">$imglrirun </a>"; 
          $ret .= "<a onClick=\"$cmdlh264run\" onmouseover=\"Tip('$tth264run')\" onmouseout=\"UnTip()\">$imglh264run </a>";
          $ret .= "<a onClick=\"$cmdlmjpegrun\" onmouseover=\"Tip('$ttlmjpegrun')\" onmouseout=\"UnTip()\">$imglmjpegrun </a>";
          $ret .= "<a onClick=\"$cmdlsnaprun\" onmouseover=\"Tip('$ttlsnaprun')\" onmouseout=\"UnTip()\">$imglsnaprun </a>";            
          $ret .= "</td>";    
      }
  } else {
      $cause = "Videoformat not supported";
      $ret .= "<td> <br> <b> $cause </b> <br><br></td>";  
  }
  
  $ret .= '</tr>';
  $ret .= '</tbody>';
  $ret .= '</table>';
  Log3($strmdev, 4, "$strmdev - Link called: $link") if($link);

return $ret;
}

#############################################################################################
#    hls.js laden für Streamimgdevice Typen HLS, RTSP
#    $m3u8 - ein .m3u8-File oder ein entsprechender Link
#    $d    - ein Unique-Name zur Codeableitung (darf keinen . enthalten)
#############################################################################################
sub SSCam_bindhlsjs ($$$$) { 
   my ($camname, $strmdev, $m3u8, $d) = @_;
   my $hlsjs = "sscam_hls.js";                      # hls.js Release von Projekteite https://github.com/video-dev/hls.js/releases
   my $ret;
   
   $ret .= "<meta charset=\"utf-8\"/>
            <!--script src=\"https://cdn.jsdelivr.net/npm/hls.js\@latest\"></script-->   
           ";
           
   my $dcs = (devspec2array("TYPE=SSCam:FILTER=MODEL=SVS"))[0];  # ist ein SVS-Device angelegt ?
   my $uns = AttrVal($dcs,"hlsNetScript",0) if($dcs);            # ist in einem SVS Device die Nutzung hls.js auf Projektseite ausgewählt ?
            
   if($uns) {
       my $lib = "https://cdn.jsdelivr.net/npm/hls.js\@latest";
       $ret .= "<script src=\"$lib\"></script>";
       Log3($strmdev, 4, "$strmdev - HLS Streaming use net library \"$lib\" ");
   } else {
       $ret .= "<script type=\"text/javascript\" src=\"/fhem/pgm2/$hlsjs\"></script>";
       Log3($strmdev, 4, "$strmdev - HLS Streaming use local file \"/fhem/pgm2/$hlsjs\" ");
   }
      
   $ret .= "<script>
            if (Hls.isSupported()) {
                var video_$d = document.getElementById('video_$d');
                var hls = new Hls();
                // bind them together
                hls.attachMedia(video_$d);
                hls.on(Hls.Events.MEDIA_ATTACHED, function () {
                    console.log(\"video and hls.js are now bound together !\");
                    hls.loadSource(\"$m3u8\");
                    hls.on(Hls.Events.MANIFEST_PARSED, function (event, data) {
                        console.log(\"manifest loaded, found \" + data.levels.length + \" quality level\");
                        video_$d.play();
                    });
                });
            }
            </script>";
   
return $ret;
}

###############################################################################
#                   Schnappschußgalerie zusammenstellen
#                   Verwendung durch SSCamSTRM-Devices
###############################################################################
sub SSCam_composegallery ($;$$$) { 
  my ($name,$strmdev,$model,$ftui) = @_;
  my $hash     = $defs{$name};
  my $camname  = $hash->{CAMNAME};
  my $allsnaps = $hash->{HELPER}{".SNAPHASH"};                                                # = %allsnaps
  my $sgc      = AttrVal($name,"snapGalleryColumns",3);                                       # Anzahl der Images in einer Tabellenzeile
  my $lss      = ReadingsVal($name, "LastSnapTime", "");                                      # Zeitpunkt neueste Aufnahme
  my $lang     = AttrVal("global","language","EN");                                           # Systemsprache       
  my $limit    = $hash->{HELPER}{SNAPLIMIT};                                                  # abgerufene Anzahl Snaps
  my $totalcnt = $hash->{HELPER}{TOTALCNT};                                                   # totale Anzahl Snaps
  $limit       = $totalcnt if ($limit > $totalcnt);                                           # wenn weniger Snaps vorhanden sind als $limit -> Text in Anzeige korrigieren
  $ftui        = ($ftui && $ftui eq "ftui")?1:0;
  my $uuid     = "";
  my $hdrAlign = "center";
  my $lupt     = ((ReadingsTimestamp($name,"LastSnapTime"," ") gt ReadingsTimestamp($name,"LastUpdateTime"," ")) 
                 ? ReadingsTimestamp($name,"LastSnapTime"," ") 
				 : ReadingsTimestamp($name,"LastUpdateTime"," "));  # letzte Aktualisierung
  $lupt =~ s/ / \/ /;
  my ($alias,$dlink,$hf) = ("","","");
  
  # Kontext des SSCamSTRM-Devices speichern für SSCam_refresh
  $hash->{HELPER}{STRMDEV}    = $strmdev;                                                     # Name des aufrufenden SSCamSTRM-Devices
  $hash->{HELPER}{STRMROOM}   = $FW_room?$FW_room:"";                                         # Raum aus dem das SSCamSTRM-Device die Funktion aufrief
  $hash->{HELPER}{STRMDETAIL} = $FW_detail?$FW_detail:"";                                     # Name des SSCamSTRM-Devices (wenn Detailansicht)
  
  if($strmdev) {
	  my $streamHash = $defs{$strmdev};                                                       # Hash des SSCamSTRM-Devices
	  $uuid = $streamHash->{FUUID};                                                           # eindeutige UUID des Streamingdevices
	  delete $streamHash->{HELPER}{STREAM};
      $alias  = AttrVal($strmdev, "alias", $strmdev);                                         # Linktext als Aliasname oder Devicename setzen
      $dlink  = "<a href=\"/fhem?detail=$strmdev\">$alias</a>";  
  }
  
  my $cmddosnap     = "FW_cmd('$FW_ME$FW_subdir?XHR=1&cmd=set $name snap 1 2 STRM:$uuid')";   # Snapshot auslösen mit Kennzeichnung "by STRM-Device"
  my $imgdosnap     = "<img src=\"$FW_ME/www/images/sscam/black_btn_DOSNAP.png\">";
  
  # bei Aufruf durch FTUI Kommandosyntax anpassen
  if($ftui) {
      $cmddosnap = "ftui.setFhemStatus('set $name snap 1 2 STRM:$uuid')";     
  }
 
  my $ha = AttrVal($name, "snapGalleryHtmlAttr", AttrVal($name, "htmlattr", 'width="500" height="325"'));
    
  # falls "SSCam_composegallery" durch ein SSCamSTRM-Device aufgerufen wird
  my $pws      = "";
  if ($strmdev) {
      $pws = AttrVal($strmdev, "popupWindowSize", "");                                        # Größe eines Popups (umgelegt: Forum:https://forum.fhem.de/index.php/topic,45671.msg927912.html#msg927912)
      $pws =~ s/"//g if($pws);
      $ha  = AttrVal($strmdev, "htmlattr", $ha);                                              # htmlattr vom SSCamSTRM-Device übernehmen falls von SSCamSTRM-Device aufgerufen und gesetzt                                                 
      $hf  = AttrVal($strmdev, "hideButtons", 0);                            # Drucktasten im unteren Bereich ausblenden ?
      if($ftui) {
          $ha = AttrVal($strmdev, "htmlattrFTUI", $ha);                                       # wenn aus FTUI aufgerufen divers setzen 
      }
  }
  
  # wenn SSCamSTRM-device genutzt wird und attr "snapGalleryBoost" nicht gesetzt ist -> Warnung in Gallerie ausgeben
  my $sgbnote = " ";
  if($strmdev && !AttrVal($name,"snapGalleryBoost",0)) {
      $sgbnote = "<b>CAUTION</b> - No snapshots can be retrieved. Please set the attribute \"snapGalleryBoost=1\" in device <a href=\"/fhem?detail=$name\">$name</a>" if ($lang eq "EN");
	  $sgbnote = "<b>ACHTUNG</b> - Es können keine Schnappschüsse abgerufen werden. Bitte setzen sie das Attribut \"snapGalleryBoost=1\" im Device <a href=\"/fhem?detail=$name\">$name</a>" if ($lang eq "DE");
  }
  
  # Javascript Bibliothek für Tooltips (http://www.walterzorn.de/tooltip/tooltip.htm#download) und Texte
  my $ttjs   = "/fhem/pgm2/sscam_tooltip.js"; 
  
  my $ttsnap = $SSCam_ttips_en{"ttsnap"}; $ttsnap =~ s/§NAME§/$camname/g;
  if(AttrVal("global","language","EN") =~ /DE/) {
      $ttsnap = $SSCam_ttips_de{"ttsnap"}; $ttsnap =~ s/§NAME§/$camname/g;
  }
  
  # Header Generierung
  my $header;  
  if($ftui) {
      $header .= "$dlink <br>"  if(!AttrVal($strmdev,"hideDisplayNameFTUI",0));
  } else {
      $header .= "$dlink <br>"  if(!AttrVal($strmdev,"hideDisplayName",0));
  } 
  if ($lang eq "EN") {
      $header .= "Snapshots ($limit/$totalcnt) of camera <b>$camname</b> - newest Snapshot: $lss<br>";
	  $header .= " (Possibly another snapshots are available. Last recall: $lupt)<br>" if(AttrVal($name,"snapGalleryBoost",0));
  } else {
      $header .= "Schnappschüsse ($limit/$totalcnt) von Kamera <b>$camname</b> - neueste Aufnahme: $lss <br>";
      $lupt    =~ /(\d+)-(\d\d)-(\d\d)\s+(.*)/;
	  $lupt    = "$3.$2.$1 $4";
	  $header .= " (Eventuell sind neuere Aufnahmen verfügbar. Letzter Abruf: $lupt)<br>" if(AttrVal($name,"snapGalleryBoost",0));
  }
  $header .= $sgbnote;
  
  my $gattr  = (AttrVal($name,"snapGallerySize","Icon") eq "Full")?$ha:"";    
  my @as     = sort{$a<=>$b}keys %{$allsnaps};
  
  # Ausgabetabelle erstellen
  my ($htmlCode,$ct);
  $htmlCode  = "<html>";
  $htmlCode .= "<script type=\"text/javascript\" src=\"$ttjs\"></script>";
  $htmlCode .= "<div class=\"makeTable wide\"; style=\"text-align:$hdrAlign\"> $header <br>";
  $htmlCode .= '<table class="block wide internals" style="margin-left:auto;margin-right:auto">';
  $htmlCode .= "<tbody>";
  $htmlCode .= "<tr class=\"odd\">";
  my $cell   = 1;
  
  foreach my $key (@as) {
      $ct = $allsnaps->{$key}{createdTm};
      my $idata = "";
      if(!$ftui) {
          $idata = "onClick=\"FW_okDialog('<img src=data:image/jpeg;base64,$allsnaps->{$key}{imageData} $pws>')\"" if(AttrVal($name,"snapGalleryBoost",0));
	  }
      my $html = sprintf("<td>$ct<br> <img src=\"data:image/jpeg;base64,$allsnaps->{$key}{imageData}\" $gattr $idata> </td>" );
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
  if(!$hf) {
      $htmlCode .= "<a onClick=\"$cmddosnap\" onmouseover=\"Tip('$ttsnap')\" onmouseout=\"UnTip()\">$imgdosnap </a>" if($strmdev);
  }
  $htmlCode .= "</html>";

return $htmlCode;
}

##############################################################################
#              Auflösung Errorcodes bei Login / Logout
#              Übernahmewerte sind $hash, $errorcode
##############################################################################
sub SSCam_experrorauth ($$) {
  my ($hash,$errorcode) = @_;
  my $device = $hash->{NAME};
  my $error;
  
  unless (exists($SSCam_errauthlist{"$errorcode"})) {$error = "Message of errorcode \"$errorcode\" not found. Please turn to Synology Web API-Guide."; return ($error);}

  # Fehlertext aus Hash-Tabelle %errorauthlist ermitteln
  $error = $SSCam_errauthlist{"$errorcode"};

return ($error);
}

##############################################################################
#  Auflösung Errorcodes SVS API
#  Übernahmewerte sind $hash, $errorcode
##############################################################################
sub SSCam_experror ($$) {
  my ($hash,$errorcode) = @_;
  my $device = $hash->{NAME};
  my $error;
  
  unless (exists($SSCam_errlist{"$errorcode"})) {$error = "Message of errorcode \"$errorcode\" not found. Please turn to Synology Web API-Guide."; return ($error);}

  # Fehlertext aus Hash-Tabelle %errorlist ermitteln
  $error = $SSCam_errlist{"$errorcode"};
  
return ($error);
}

################################################################
# sortiert eine Liste von Versionsnummern x.x.x
# Schwartzian Transform and the GRT transform
# Übergabe: "asc | desc",<Liste von Versionsnummern>
################################################################
sub SSCam_sortVersion (@){
  my ($sseq,@versions) = @_;

  my @sorted = map {$_->[0]}
			   sort {$a->[1] cmp $b->[1]}
			   map {[$_, pack "C*", split /\./]} @versions;
			 
  @sorted = map {join ".", unpack "C*", $_}
            sort
            map {pack "C*", split /\./} @versions;
  
  if($sseq eq "desc") {
      @sorted = reverse @sorted;
  }
  
return @sorted;
}

##############################################################################
# Zusätzliche Redings in Rotation erstellen
# Sub ($hash,<readingName>,<Wert>,<Rotationszahl>,<Trigger[0|1]>)
##############################################################################
sub SSCam_rotateReading ($$$$$) {
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
              } else {
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
sub SSCam_prepareSendData ($$;$) { 
   my ($hash, $OpMode, $dat) = @_;
   my $name   = $hash->{NAME};
   my $calias = AttrVal($name,"alias",$hash->{CAMNAME});              # Alias der Kamera wenn gesetzt oder Originalname aus SVS
   my ($ret,$sdat,$vdat,$fname,$snapid,$lsnaptime,$tac) = ('','','','','','');
      
   ### prüfen ob Schnappschnüsse aller Kameras durch ein SVS-Device angefordert wurde,
   ### Bilddaten werden erst zum Versand weitergeleitet wenn Schnappshußhash komplett gefüllt ist
   my $asref;
   my @allsvs = devspec2array("TYPE=SSCam:FILTER=MODEL=SVS");
   foreach (@allsvs) {
       next if(!AttrVal($_, "snapEmailTxt", ""));                      # Schnappschüsse senden NICHT durch SVS ausgelöst -> Snaps der Cams NICHT gemeinsam versenden
       my $svshash = $defs{$_};
       if($svshash->{HELPER}{ALLSNAPREF}) { 
           $asref = $svshash->{HELPER}{ALLSNAPREF};                    # Hashreferenz zum summarischen Snaphash
           foreach my $key (keys%{$asref}) {
               if($key eq $name) {                                     # Kamera Key im Bildhash matcht -> Bilddaten übernehmen
                    foreach my $pkey (keys%{$dat}) {
                        my $nkey = time()+int(rand(1000));
                        $asref->{$nkey.$pkey}{createdTm}    = $dat->{$pkey}{createdTm};     # Aufnahmezeit der Kamera werden im summarischen Snaphash eingefügt
                        $asref->{$nkey.$pkey}{".imageData"} = $dat->{$pkey}{".imageData"};  # Bilddaten der Kamera werden im summarischen Snaphash eingefügt
                        $asref->{$nkey.$pkey}{fileName}     = $dat->{$pkey}{fileName};      # Filenamen der Kamera werden im summarischen Snaphash eingefügt
                    }
                    delete $hash->{HELPER}{CANSENDSNAP};               
                    delete $asref->{$key};                             # ursprünglichen Key (Kameranamen) löschen
               }
           }
           $asref = $svshash->{HELPER}{ALLSNAPREF};                    # Hashreferenz zum summarischen Snaphash
           foreach my $key (keys%{$asref}) {                           # prüfen ob Bildhash komplett ?
               if(!$asref->{$key}) {
                   return;                                             # Bildhash noch nicht komplett                                 
               }
           }
       
           delete $svshash->{HELPER}{ALLSNAPREF};                      # ALLSNAPREF löschen -> gemeinsamer Versand beendet
           $hash   = $svshash;                                         # Hash durch SVS-Hash ersetzt
           $name   = $svshash->{NAME};                                 # Name des auslösenden SVS-Devices wird eingesetzt                                        
           delete $data{SSCam}{RS};
           foreach my $key (keys%{$asref}) {                           # Referenz zum summarischen Hash einsetzen        
               $data{SSCam}{RS}{$key} = delete $asref->{$key};                                         
           }   
           $dat    = $data{SSCam}{RS};                                 # Referenz zum summarischen Hash einsetzen
           $calias = AttrVal($name,"alias",$hash->{NAME});             # Alias des SVS-Devices 
           $hash->{HELPER}{TRANSACTION} = "multiple_snapsend";         # fake Transaction im SVS Device setzen 
           last;                                                       # Schleife verlassen und mit Senden weiter
       }
   }
   
   my $sp       = AttrVal($name, "smtpPort", 25); 
   my $nousessl = AttrVal($name, "smtpNoUseSSL", 0); 
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
   my $date = sprintf "%02d.%02d.%04d" , $mday , $mon+=1 ,$year+=1900; 
   my $time = sprintf "%02d:%02d:%02d" , $hour , $min , $sec;   
   
   my $sslfrominit = 0;
   my $smtpsslport = 465;
   if(AttrVal($name,"smtpSSLPort",0)) {
       $sslfrominit = 1;
       $smtpsslport = AttrVal($name,"smtpSSLPort",0);
   }
   
   $tac = $hash->{HELPER}{TRANSACTION};               # Code der laufenden Transaktion
   
   ### Schnappschüsse als Email versenden wenn $hash->{HELPER}{CANSENDSNAP} definiert ist
   if($OpMode =~ /^getsnap/ && $hash->{HELPER}{CANSENDSNAP}) {     
       delete $hash->{HELPER}{CANSENDSNAP};
       my $mt = delete $hash->{HELPER}{SMTPMSG};
       $mt    =~ s/['"]//g;   
       
       my($subj,$body)   = split(",", $mt, 2);
       my($subjk,$subjt) = split("=>", $subj);
       my($bodyk,$bodyt) = split("=>", $body);
       $subjk = SSCam_trim($subjk);
       $subjt = SSCam_trim($subjt);
       $subjt =~ s/\$CAM/$calias/g;
       $subjt =~ s/\$DATE/$date/g;
       $subjt =~ s/\$TIME/$time/g;
       $bodyk = SSCam_trim($bodyk);
       $bodyt = SSCam_trim($bodyt);
       $bodyt =~ s/\$CAM/$calias/g;
       $bodyt =~ s/\$DATE/$date/g;
       $bodyt =~ s/\$TIME/$time/g;
       my %smtpmsg = ();
       $smtpmsg{$subjk} = "$subjt";
       $smtpmsg{$bodyk} = "$bodyt";
       
       $sdat = $dat;       
       $ret = SSCam_sendEmail($hash, {'subject'      => $smtpmsg{subject},   
                                      'part1txt'     => $smtpmsg{body}, 
                                      'part2type'    => 'image/jpeg',
                                      'smtpport'     => $sp,
                                      'sdat'         => $sdat,
                                      'opmode'       => $OpMode,
                                      'smtpnousessl' => $nousessl,
                                      'sslfrominit'  => $sslfrominit,
                                      'smtpsslport'  => $smtpsslport, 
                                      'tac'          => $tac,                                  
                                     }
                             );
   }
   
   ### Aufnahmen als Email versenden wenn $hash->{HELPER}{CANSENDREC} definiert ist
   if($OpMode =~ /^GetRec/ && $hash->{HELPER}{CANSENDREC}) {     
       delete $hash->{HELPER}{CANSENDREC};
       my $mt  = delete $hash->{HELPER}{SMTPRECMSG};
       $mt     =~ s/['"]//g;   
       
       my($subj,$body)   = split(",", $mt, 2);
       my($subjk,$subjt) = split("=>", $subj);
       my($bodyk,$bodyt) = split("=>", $body);
       $subjk = SSCam_trim($subjk);
       $subjt = SSCam_trim($subjt);
       $subjt =~ s/\$CAM/$calias/g;
       $subjt =~ s/\$DATE/$date/g;
       $subjt =~ s/\$TIME/$time/g;
       $bodyk = SSCam_trim($bodyk);
       $bodyt = SSCam_trim($bodyt);
       $bodyt =~ s/\$CAM/$calias/g;
       $bodyt =~ s/\$DATE/$date/g;
       $bodyt =~ s/\$TIME/$time/g;
       my %smtpmsg = ();
       $smtpmsg{$subjk} = "$subjt";
       $smtpmsg{$bodyk} = "$bodyt";
       
       $vdat = $dat;        
       $ret = SSCam_sendEmail($hash, {'subject'      => $smtpmsg{subject},   
                                      'part1txt'     => $smtpmsg{body}, 
                                      'part2type'    => 'video/mpeg',
                                      'smtpport'     => $sp,
                                      'vdat'         => $vdat,
                                      'opmode'       => $OpMode,
                                      'smtpnousessl' => $nousessl,
                                      'sslfrominit'  => $sslfrominit,
                                      'smtpsslport'  => $smtpsslport,
                                      'tac'          => $tac,                                      
                                     }
                             );
   }

   ### Schnappschüsse mit Telegram versenden
   if($OpMode =~ /^getsnap/ && $hash->{HELPER}{CANTELESNAP}) {     
       # snapTelegramTxt aus $hash->{HELPER}{TELEMSG}
       # Format in $hash->{HELPER}{TELEMSG} muss sein: tbot => <teleBot Device>, peers => <peer1 peer2 ..>, subject => <Beschreibungstext>
       delete $hash->{HELPER}{CANTELESNAP};
       my $mt = delete $hash->{HELPER}{TELEMSG};
       $mt    =~ s/['"]//g;
             
       my($telebot,$peers,$subj) = split(",", $mt, 3);
       my($tbotk,$tbott)   = split("=>", $telebot) if($telebot);
       my($peerk,$peert)   = split("=>", $peers) if($peers);
       my($subjk,$subjt)   = split("=>", $subj) if($subj);

       $tbotk = SSCam_trim($tbotk) if($tbotk);
       $tbott = SSCam_trim($tbott) if($tbott);
       $peerk = SSCam_trim($peerk) if($peerk);
       $peert = SSCam_trim($peert) if($peert);
       $subjk = SSCam_trim($subjk) if($subjk);
       if($subjt) {
           $subjt = SSCam_trim($subjt);
           $subjt =~ s/\$CAM/$calias/g;
           $subjt =~ s/\$DATE/$date/g;
           $subjt =~ s/\$TIME/$time/g;
       }       
       
       my %telemsg = ();
	   $telemsg{$tbotk} = "$tbott" if($tbott);
	   $telemsg{$peerk} = "$peert" if($peert);
       $telemsg{$subjk} = "$subjt" if($subjt);
       
       $sdat = $dat;  
       $ret = SSCam_sendTelegram($hash, {'subject'      => $telemsg{subject},
                                         'part2type'    => 'image/jpeg',
                                         'sdat'         => $sdat,
                                         'opmode'       => $OpMode,
                                         'tac'          => $tac, 
                                         'telebot'      => $telemsg{$tbotk}, 
                                         'peers'        => $telemsg{$peerk},                                      
                                         'MediaStream'  => '-1',                       # Code für MediaStream im TelegramBot (png/jpg = -1)
                                        }
                                );                   
   }

   ### Aufnahmen mit Telegram versenden
   if($OpMode =~ /^GetRec/ && $hash->{HELPER}{CANTELEREC}) {   
       # recTelegramTxt aus $hash->{HELPER}{TELERECMSG}
       # Format in $hash->{HELPER}{TELEMSG} muss sein: tbot => <teleBot Device>, peers => <peer1 peer2 ..>, subject => <Beschreibungstext>
       delete $hash->{HELPER}{CANTELEREC};
       my $mt = delete $hash->{HELPER}{TELERECMSG};
       $mt    =~ s/['"]//g;
             
       my($telebot,$peers,$subj) = split(",", $mt, 3);
       my($tbotk,$tbott)   = split("=>", $telebot) if($telebot);
       my($peerk,$peert)   = split("=>", $peers) if($peers);
       my($subjk,$subjt)   = split("=>", $subj) if($subj);

       $tbotk = SSCam_trim($tbotk) if($tbotk);
       $tbott = SSCam_trim($tbott) if($tbott);
       $peerk = SSCam_trim($peerk) if($peerk);
       $peert = SSCam_trim($peert) if($peert);
       $subjk = SSCam_trim($subjk) if($subjk);
       if($subjt) {
           $subjt = SSCam_trim($subjt);
           $subjt =~ s/\$CAM/$calias/g;
           $subjt =~ s/\$DATE/$date/g;
           $subjt =~ s/\$TIME/$time/g;
       }       
       
       my %telemsg = ();
	   $telemsg{$tbotk} = "$tbott" if($tbott);
	   $telemsg{$peerk} = "$peert" if($peert);
       $telemsg{$subjk} = "$subjt" if($subjt);
       
       $vdat = $dat;  
       $ret = SSCam_sendTelegram($hash, {'subject'      => $telemsg{subject},
                                         'vdat'         => $vdat,
                                         'opmode'       => $OpMode, 
                                         'telebot'      => $telemsg{$tbotk}, 
                                         'peers'        => $telemsg{$peerk},
                                         'tac'          => $tac,                                         
                                         'MediaStream'  => '-30',                       # Code für MediaStream im TelegramBot (png/jpg = -1)
                                        }
                                );                   
   }
   
return;
}

#############################################################################################
#                                   Telegram-Versand
#############################################################################################
sub SSCam_sendTelegram ($$) { 
   my ($hash, $extparamref) = @_;
   my $name = $hash->{NAME};
   my $ret;
   
   Log3($name, 4, "$name - ####################################################"); 
   Log3($name, 4, "$name - ###      start send snapshot by TelegramBot         "); 
   Log3($name, 4, "$name - ####################################################");
   
   my %SSCam_teleparams = (
       'subject'      => {                       'default'=>'',                          'required'=>0, 'set'=>1},
       'part1type'    => {                       'default'=>'text/plain; charset=UTF-8', 'required'=>1, 'set'=>1},
       'part1txt'     => {                       'default'=>'',                          'required'=>0, 'set'=>1},
       'part2type'    => {                       'default'=>'',                          'required'=>0, 'set'=>1},
       'sdat'         => {                       'default'=>'',                          'required'=>0, 'set'=>1},  # (Hash)Daten base64 codiert, wenn gesetzt muss 'part2type' auf 'image/jpeg' gesetzt sein
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
   
   foreach my $key (keys %SSCam_teleparams) {
       $data{SSCam}{$name}{PARAMS}{$tac}{$key} = AttrVal($name, $SSCam_teleparams{$key}->{attr}, $SSCam_teleparams{$key}->{default}) 
                                                   if(exists $SSCam_teleparams{$key}->{attr}); 
	   if($SSCam_teleparams{$key}->{set}) {       
           $data{SSCam}{$name}{PARAMS}{$tac}{$key} = $extparamref->{$key} if(exists $extparamref->{$key});
           $data{SSCam}{$name}{PARAMS}{$tac}{$key} = $SSCam_teleparams{$key}->{default} if (!$extparamref->{$key} && !$SSCam_teleparams{$key}->{attr});
	   }
       Log3($name, 4, "$name - param $key is now \"".$data{SSCam}{$name}{PARAMS}{$tac}{$key}."\" ") if($key !~ /[sv]dat/);
       Log3($name, 4, "$name - param $key is set") if($key =~ /[sv]dat/ && $data{SSCam}{$name}{PARAMS}{$tac}{$key} ne '');
   }
   
   $data{SSCam}{$name}{PARAMS}{$tac}{name} = $name;
   
   my @err = ();
   foreach my $key (keys(%SSCam_teleparams)) {
       push(@err, $key) if ($SSCam_teleparams{$key}->{required} && !$data{SSCam}{$name}{PARAMS}{$tac}{$key});
   }
   if ($#err >= 0) {
       $ret = "Missing at least one required parameter or attribute: ".join(', ',@err);
       Log3($name, 2, "$name - $ret");
       readingsBeginUpdate($hash);
       readingsBulkUpdate($hash,"sendTeleState",$ret);
       readingsEndUpdate($hash, 1);
       return $ret;
   }
   
   my $telebot            = $data{SSCam}{$name}{PARAMS}{$tac}{telebot};
   my $peers              = $data{SSCam}{$name}{PARAMS}{$tac}{peers}; 
   my $sdat               = $data{SSCam}{$name}{PARAMS}{$tac}{sdat};                     # Hash von Imagedaten base64 codiert
   my $vdat               = $data{SSCam}{$name}{PARAMS}{$tac}{vdat};                     # Hashref der Videodaten   
   
   if(!$defs{$telebot}) {
       $ret = "No TelegramBot device \"$telebot\" available";
       readingsSingleUpdate($hash, "sendTeleState", $ret, 1);
       Log3($name, 2, "$name - $ret");
       return;
   }
  
   if(!$peers) {
       $peers = AttrVal($telebot,"defaultPeer", "");
       if(!$peers) {
           $ret = "No peers of TelegramBot device \"$telebot\" found";
           readingsSingleUpdate($hash, "sendTeleState", $ret, 1);
           Log3($name, 2, "$name - $ret");
           return;       
       }
   }   
                                    
  no strict "refs";
  my ($msg,$subject,$MediaStream,$fname);
  if($sdat) {
      ### Images liegen in einem Hash (Ref in $sdat) base64-codiert vor
      my @as = sort{$b<=>$a}keys%{$sdat};
      foreach my $key (@as) {
           ($msg,$subject,$MediaStream,$fname) = SSCam_extractForTelegram($name,$key,$data{SSCam}{$name}{PARAMS}{$tac});
		   $ret = SSCam_TBotSendIt($defs{$telebot}, $name, $fname, $peers, $msg, $subject, $MediaStream, undef, "");
		   if($ret) {
			   readingsSingleUpdate($hash, "sendTeleState", $ret, 1);
			   Log3($name, 2, "$name - ERROR: $ret");
		   } else {
			   $ret = "Telegram message successfully sent to \"$peers\" by \"$telebot\" ";
			   readingsSingleUpdate($hash, "sendTeleState", $ret, 1);
			   Log3($name, 3, "$name - $ret");
		   }
	  }
  }
  
  if($vdat) {
      ### Aufnahmen liegen in einem Hash-Ref in $vdat vor
      my $key = 0;
      ($msg,$subject,$MediaStream,$fname) = SSCam_extractForTelegram($name,$key,$data{SSCam}{$name}{PARAMS}{$tac});
      $ret = SSCam_TBotSendIt($defs{$telebot}, $name, $fname, $peers, $msg, $subject, $MediaStream, undef, "");
	  if($ret) {
	      readingsSingleUpdate($hash, "sendTeleState", $ret, 1);
	      Log3($name, 2, "$name - ERROR: $ret");
      } else {
          $ret = "Telegram message successfully sent to \"$peers\" by \"$telebot\" ";
          readingsSingleUpdate($hash, "sendTeleState", $ret, 1);
	      Log3($name, 3, "$name - $ret");
	  }
  }
  
  use strict "refs";
  
return;
}

####################################################################################################
#                                Bilddaten extrahieren für Telegram Versand
####################################################################################################
sub SSCam_extractForTelegram($$$) {
  my ($name,$key,$paref) = @_;
  my $hash               = $defs{$name};
  my $subject            = $paref->{subject};
  my $MediaStream        = $paref->{MediaStream};
  my $sdat               = $paref->{sdat};                     # Hash von Imagedaten base64 codiert
  my $vdat               = $paref->{vdat};                     # Hashref der Videodaten   
  my ($data,$fname,$ct);
  
  if($sdat) {
      $ct     = $paref->{sdat}{$key}{createdTm};
      my $img = $paref->{sdat}{$key}{".imageData"};
      $fname  = SSCam_trim($paref->{sdat}{$key}{fileName});
      $data   = MIME::Base64::decode_base64($img); 
      Log3($name, 4, "$name - image data decoded for TelegramBot prepare");
  } 
  
  if($vdat) {
      $ct    = $paref->{vdat}{$key}{createdTm};
      $data  = $paref->{vdat}{$key}{".imageData"};
      $fname = SSCam_trim($paref->{vdat}{$key}{fileName});
  }
  
  $subject =~ s/\$FILE/$fname/g;
  $subject =~ s/\$CTIME/$ct/g;
 
return ($data,$subject,$MediaStream,$fname);
}

####################################################################################################
#                  Telegram Send Foto & Aufnahmen
#                  Adaption der Sub "SendIt" aus TelegramBot
#                  $hash    = Hash des verwendeten TelegramBot-Devices !
#                  $isMedia = -1 wenn Foto, -30 wenn Aufnahme
####################################################################################################
sub SSCam_TBotSendIt($$$$$$$;$$$) {
  my ($hash, $camname, $fname, @args) = @_;
  my ($peers, $msg, $addPar, $isMedia, $replyid, $options, $retryCount) = @args;
  my $name = $hash->{NAME};
  my $SSCam_TBotHeader      = "agent: TelegramBot/1.0\r\nUser-Agent: TelegramBot/1.0\r\nAccept: application/json\r\nAccept-Charset: utf-8";
  my $SSCam_TBotArgRetrycnt = 6;
  
  $retryCount = 0 if (!defined($retryCount));
  $options    = "" if (!defined($options));
  
  # increase retrycount for next try
  $args[$SSCam_TBotArgRetrycnt] = $retryCount+1;
  
  Log3($camname, 5, "$camname - SSCam_TBotSendIt: called ");

  # ignore all sends if disabled
  return if (AttrVal($name,"disable",0));

  # ensure sentQueue exists
  $hash->{sentQueue} = [] if (!defined($hash->{sentQueue}));

  if ((defined( $hash->{sentMsgResult})) && ($hash->{sentMsgResult} =~ /^WAITING/) && ($retryCount == 0) ){
      # add to queue
      Log3($camname, 4, "$camname - SSCam_TBotSendIt: add send to queue :$peers: -:".
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
      $sepoptions    =~ s/-msgid-//;
      SSCam_TBotSendIt($hash,$camname,$fname,$peers,$msg,$addPar,$isMedia,undef,$sepoptions);
  }
  
  Log3($camname, 5, "$camname - SSCam_TBotSendIt: try to send message to :$peer: -:".
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
  $hash->{HU_DO_PARAMS}->{header} = $SSCam_TBotHeader;
  delete( $hash->{HU_DO_PARAMS}->{args} );
  delete( $hash->{HU_DO_PARAMS}->{boundary} );

  
  my $timeout = AttrVal($name,'cmdTimeout',30);
  $hash->{HU_DO_PARAMS}->{timeout}  = $timeout;
  $hash->{HU_DO_PARAMS}->{loglevel} = 4;
  
  # Start Versand
  if (!defined($ret)) {
      # add chat / user id (no file) --> this will also do init
      $ret = SSCam_TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "chat_id", undef, $peer2, 0 ) if ( $peer );
      
      if (abs($isMedia) == 1) {
          # Foto send    
          $hash->{sentMsgText}         = "Image: ".TelegramBot_MsgForLog($msg,($isMedia<0)).((defined($addPar))?" - ".$addPar:"");
          $hash->{HU_DO_PARAMS}->{url} = TelegramBot_getBaseURL($hash)."sendPhoto";

          # add caption
          if (defined($addPar)) {
              $addPar =~ s/(?<![\\])\\n/\x0A/g;
              $addPar =~ s/(?<![\\])\\t/\x09/g;

              $ret = SSCam_TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "caption", undef, $addPar, 0 ) if (!defined($ret));
              $addPar = undef;
          }
      
          # add msg or file or stream
          Log3($camname, 4, "$camname - SSCam_TBotSendIt: Filename for image file :".
            TelegramBot_MsgForLog($msg, ($isMedia<0) ).":");
          $ret = SSCam_TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "photo", undef, $msg, $isMedia) if(!defined($ret));
      
      } elsif ( abs($isMedia) == 30 ) {
          # Video send    
          $hash->{sentMsgText}         = "Image: ".TelegramBot_MsgForLog($msg,($isMedia<0)).((defined($addPar))?" - ".$addPar:"");
          $hash->{HU_DO_PARAMS}->{url} = TelegramBot_getBaseURL($hash)."sendVideo";

          # add caption
          if (defined( $addPar) ) {
              $addPar =~ s/(?<![\\])\\n/\x0A/g;
              $addPar =~ s/(?<![\\])\\t/\x09/g;

              $ret = SSCam_TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "caption", undef, $addPar, 0) if(!defined($ret));
              $addPar = undef;
          }
      
          # add msg or file or stream
          Log3($camname, 4, "$camname - SSCam_TBotSendIt: Filename for image file :".$fname.":");
          $ret = SSCam_TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "video", undef, $msg, $isMedia) if(!defined($ret));
      
      } else {
          # nur Message senden
          $msg = "No media File was created by SSCam. Can't send it.";
          $hash->{HU_DO_PARAMS}->{url} = TelegramBot_getBaseURL($hash)."sendMessage";
      
          my $parseMode = TelegramBot_AttrNum($name,"parseModeSend","0" );
        
          if ($parseMode == 1) {
              $parseMode = "Markdown";
        
          } elsif ($parseMode == 2) {
              $parseMode = "HTML";
        
          } elsif ($parseMode == 3) {
              $parseMode = 0;
              if ($msg =~ /^markdown(.*)$/i) {
                  $msg = $1;
                  $parseMode = "Markdown";
              } elsif ($msg =~ /^HTML(.*)$/i) {
                  $msg = $1;
                  $parseMode = "HTML";
              }
        
          } else {
              $parseMode = 0;
          }
      
          Log3($camname, 4, "$camname - SSCam_TBotSendIt: parseMode $parseMode");
    
          if (length($msg) > 1000) {
              $hash->{sentMsgText} = substr($msg, 0, 1000)."...";
          } else {
              $hash->{sentMsgText} = $msg;
          }
        
          $msg =~ s/(?<![\\])\\n/\x0A/g;
          $msg =~ s/(?<![\\])\\t/\x09/g;

          # add msg (no file)
          $ret = SSCam_TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "text", undef, $msg, 0) if(!defined($ret));

          # add parseMode
          $ret = SSCam_TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "parse_mode", undef, $parseMode, 0) if((!defined($ret)) && ($parseMode));

          # add disable_web_page_preview       
          $ret = SSCam_TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "disable_web_page_preview", undef, \1, 0) 
            if ((!defined($ret))&&(!AttrVal($name,'webPagePreview',1)));            
      }

      if (defined($replyid)) {
          $ret = SSCam_TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "reply_to_message_id", undef, $replyid, 0) if(!defined($ret));
      }

      if (defined($addPar)) {
          $ret = SSCam_TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "reply_markup", undef, $addPar, 0) if(!defined($ret));
      } elsif ($options =~ /-force_reply-/) {
          $ret = SSCam_TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "reply_markup", undef, "{\"force_reply\":true}", 0 ) if(!defined($ret));
      }

      if ($options =~ /-silent-/) {
          $ret = SSCam_TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, "disable_notification", undef, "true", 0) if(!defined($ret));
      }

      # finalize multipart 
      $ret = SSCam_TBotAddMultipart($hash, $fname, $hash->{HU_DO_PARAMS}, undef, undef, undef, 0) if(!defined($ret));

  }
  
  if (defined($ret)) {
      Log3($camname, 3, "$camname - SSCam_TBotSendIt: Failed with :$ret:");
      TelegramBot_Callback($hash->{HU_DO_PARAMS}, $ret, "");

  } else {
      $hash->{HU_DO_PARAMS}->{args} = \@args;
    
      # if utf8 is set on string this will lead to length wrongly calculated in HTTPUtils (char instead of bytes) for some installations
      if ((AttrVal($name,'utf8Special',0)) && (utf8::is_utf8($hash->{HU_DO_PARAMS}->{data}))) {
          Log3 $camname, 4, "$camname - SSCam_TBotSendIt: utf8 encoding for data in message ";
          utf8::downgrade($hash->{HU_DO_PARAMS}->{data}); 
      }
    
      Log3($camname, 4, "$camname - SSCam_TBotSendIt: timeout for sent :".$hash->{HU_DO_PARAMS}->{timeout}.": ");
      HttpUtils_NonblockingGet($hash->{HU_DO_PARAMS});
  }
  
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
sub SSCam_TBotAddMultipart($$$$$$$) {
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
  $parheader .= "\r\n" if ((length($parheader) > 0) && ($parheader !~ /\r\n$/));

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
          my ($im, $ext)   = SSCam_TBotIdentifyStream($hash, $parcontent);
          $fname           =~ s/.mp4$/.$ext/;
          $parheader       = "Content-Disposition: form-data; name=\"".$parname."\"; filename=\"".$fname."\"\r\n".$parheader."\r\n";
          $finalcontent    = $parcontent;
      
      } else {
          $parheader    = "Content-Disposition: form-data; name=\"".$parname."\"\r\n".$parheader."\r\n";
          $finalcontent = $parcontent;
      }
    
      $params->{data} .= $parheader.$finalcontent."\r\n";
    
  } else {
      return( "No content defined for multipart" ) if ( length( $params->{data} ) == 0 );
      $params->{data} .= "--".$params->{boundary}."--";     
  }

return undef;
}

####################################################################################################
#                  Telegram Media Identifikation
#                  Adaption der Sub "IdentifyStream" aus TelegramBot
#                  $hash    = Hash des verwendeten TelegramBot-Devices !
####################################################################################################
sub SSCam_TBotIdentifyStream($$) {
  my ($hash, $msg) = @_;

  # signatures for media files are documented here --> https://en.wikipedia.org/wiki/List_of_file_signatures
  # seems sometimes more correct: https://wangrui.wordpress.com/2007/06/19/file-signatures-table/
  # Video Signatur aus: https://www.garykessler.net/library/file_sigs.html
  return (-1,"png") if ( $msg =~ /^\x89PNG\r\n\x1a\n/ );                       # PNG
  return (-1,"jpg") if ( $msg =~ /^\xFF\xD8\xFF/ );                            # JPG not necessarily complete, but should be fine here
  return (-30,"mpg") if ( $msg =~ /^....\x66\x74\x79\x70\x69\x73\x6f\x6d/ );   # mp4     

return (0,undef);
}

#############################################################################################
#                                   SMTP EMail-Versand
#############################################################################################
sub SSCam_sendEmail ($$) { 
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
   my $sslfb = 0;                # Flag für Verwendung altes Net::SMTP::SSL
   
   my ($vm1,$vm2,$vm3);
   eval { require Net::SMTP;              
          Net::SMTP->import; 
		  $vm1 = $Net::SMTP::VERSION;
          
          # Version von Net::SMTP prüfen, wenn < 3.00 dann Net::SMTP::SSL verwenden 
          # (libnet-3.06 hat SSL inkludiert)
          my $sv = $vm1;
          $sv =~ s/[^0-9.].*$//;
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
       readingsBulkUpdate($hash,"sendEmailState",$ret);
       readingsEndUpdate($hash, 1);
                
       return $ret;
   }
   
   Log3($name, 4, "$name - version of loaded module \"$m1\" is \"$vm1\"");
   Log3($name, 4, "$name - version of \"$m1\" is too old. Use SSL-fallback module \"$m3\" with version \"$vm3\"") if($sslfb && $vm3);
   Log3($name, 4, "$name - version of loaded module \"$m2\" is \"$vm2\"");
   
   my %SSCam_mailparams = (
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
       'sdat'         => {                       'default'=>'',                          'required'=>0, 'set'=>1},  # (Hash)Daten base64 codiert, wenn gesetzt muss 'part2type' auf 'image/jpeg' gesetzt sein
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
   
   foreach my $key (keys %SSCam_mailparams) {
       $data{SSCam}{$name}{PARAMS}{$tac}{$key} = AttrVal($name, $SSCam_mailparams{$key}->{attr}, $SSCam_mailparams{$key}->{default}) 
                                                   if(exists $SSCam_mailparams{$key}->{attr}); 
	   if($SSCam_mailparams{$key}->{set}) {       
           $data{SSCam}{$name}{PARAMS}{$tac}{$key} = $extparamref->{$key} if (exists $extparamref->{$key});
           $data{SSCam}{$name}{PARAMS}{$tac}{$key} = $SSCam_mailparams{$key}->{default} if (!$extparamref->{$key} && !$SSCam_mailparams{$key}->{attr});
	   }
       Log3($name, 4, "$name - param $key is now \"".$data{SSCam}{$name}{PARAMS}{$tac}{$key}."\" ") if($key !~ /sdat/);
       Log3($name, 4, "$name - param $key is set") if($key =~ /sdat/ && $data{SSCam}{$name}{PARAMS}{$tac}{$key} ne '');
   }
   
   $data{SSCam}{$name}{PARAMS}{$tac}{name} = $name;
   
   my @err = ();
   foreach my $key (keys(%SSCam_mailparams)) {
       push(@err, $key) if ($SSCam_mailparams{$key}->{required} && !$data{SSCam}{$name}{PARAMS}{$tac}{$key});
   }
   if ($#err >= 0) {
       $ret = "Missing at least one required parameter or attribute: ".join(', ',@err);
       Log3($name, 2, "$name - $ret");
       readingsBeginUpdate($hash);
       readingsBulkUpdate($hash,"sendEmailState",$ret);
       readingsEndUpdate($hash, 1);
       return $ret;
   }
   
   $hash->{HELPER}{RUNNING_PID} = BlockingCall("SSCam_sendEmailblocking", $data{SSCam}{$name}{PARAMS}{$tac}, "SSCam_sendEmaildone", $timeout, "SSCam_sendEmailto", $hash);
   $hash->{HELPER}{RUNNING_PID}{loglevel} = 5 if($hash->{HELPER}{RUNNING_PID});  # Forum #77057
      
return;
}

####################################################################################################
#                                 nichtblockierendes Send EMail
####################################################################################################
sub SSCam_sendEmailblocking($) {
  my ($paref)      = @_;
  my $name         = $paref->{name};
  my $cc           = $paref->{smtpCc};
  my $from         = $paref->{smtpFrom};
  my $part1type    = $paref->{part1type};
  my $part1txt     = $paref->{part1txt};
  my $part2type    = $paref->{part2type};
  my $smtphost     = $paref->{smtphost};
  my $smtpport     = $paref->{smtpport};
  my $smtpsslport  = $paref->{smtpsslport};
  my $smtpnousessl = $paref->{smtpnousessl};             # SSL Verschlüsselung soll NICHT genutzt werden
  my $subject      = $paref->{subject};
  my $to           = $paref->{smtpTo};
  my $msgtext      = $paref->{msgtext}; 
  my $smtpdebug    = $paref->{smtpdebug}; 
  my $sdat         = $paref->{sdat};                     # Hash von Imagedaten base64 codiert
  my $image        = $paref->{image};                    # Image, wenn gesetzt muss 'part2type' auf 'image/jpeg' gesetzt sein
  my $fname        = $paref->{fname};                    # Filename -> verwendet wenn $image ist gesetzt
  my $lsnaptime    = $paref->{lsnaptime};                # Zeit des letzten Schnappschusses wenn gesetzt
  my $opmode       = $paref->{opmode};                   # aktueller Operation Mode
  my $sslfb        = $paref->{sslfb};                    # Flag für Verwendung altes Net::SMTP::SSL
  my $sslfrominit  = $paref->{sslfrominit};              # SSL soll sofort ! aufgebaut werden
  my $tac          = $paref->{tac};                      # übermittelter Transaktionscode der ausgewerteten Transaktion
  my $vdat         = $paref->{vdat};                     # Videodaten, wenn gesetzt muss 'part2type' auf 'video/mpeg' gesetzt sein
  
  my $hash   = $defs{$name};
  my $sslver = "";
  my ($err,$fh,$smtp,@as);
  
  # Credentials abrufen
  my ($success, $username, $password) = SSCam_getcredentials($hash,0,"smtp");
  
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
  
  no strict "refs";
  if($sdat) {
      ### Images liegen in einem Hash (Ref in $sdat) base64-codiert vor und werden dekodiert in ein "in-memory IO" gespeichert (snap)
      my ($ct,$img,$decoded);
      @as = sort{$a<=>$b}keys%{$sdat};
      foreach my $key (@as) {
		  $ct      = $sdat->{$key}{createdTm};
		  $img     = $sdat->{$key}{".imageData"};
		  $fname   = $sdat->{$key}{fileName};
		  $fh      = '$fh'.$key;
		  $decoded = MIME::Base64::decode_base64($img); 
		  my $mh   = '';
		  if(open ($fh, '>', \$mh)) {            # in-memory IO Handle
			  binmode $fh;
			  print $fh $decoded;
			  close $fh;
			  open ($fh, '<', \$mh);
			  Log3($name, 4, "$name - image data were saved into memory handle for smtp prepare");
		  } else {
			  $err = "Can't open memory handle: $!";
			  Log3($name, 2, "$name - $err");
			  $err = encode_base64($err,"");
			  return "$name|$err|''";
		  }
		  $mailmsg->attach(
			  Type        => $part2type,
			  FH          => $fh,
			  Filename    => $fname,
			  Disposition => 'attachment',
		  );
      }
  }
  
  if($vdat) {
      ### Videodaten (mp4) wurden geliefert und werden in ein "in-memory IO" gespeichert
      my ($ct,$video);
      @as = sort{$a<=>$b}keys%{$vdat};
      foreach my $key (@as) {
		  $ct      = $vdat->{$key}{createdTm};
		  $video   = $vdat->{$key}{".imageData"};
		  $fname   = $vdat->{$key}{fileName};
		  $fh      = '$fh'.$key;
		  my $mh   = '';
		  if(open ($fh, '>', \$mh)) {            # in-memory IO Handle
			  binmode $fh;
			  print $fh $video;
			  close $fh;
			  open ($fh, '<', \$mh);
			  Log3($name, 4, "$name - video data were saved into memory handle for smtp prepare");
		  } else {
			  $err = "Can't open memory handle: $!";
			  Log3($name, 2, "$name - $err");
			  $err = encode_base64($err,"");
			  return "$name|$err|''";
		  }
		  $mailmsg->attach(
			  Type        => $part2type,
			  FH          => $fh,
			  Filename    => $fname,
			  Disposition => 'attachment',
		  );
      }
  }
  
  $mailmsg->attr('content-type.charset' => 'UTF-8');

  #####  SMTP-Connection #####
  # login to SMTP Host
  if($sslfb) {
      # Verwendung altes Net::SMTP::SSL <= 3.00 -> immer direkter SSL-Aufbau, Attribut "smtpNoUseSSL" wird ignoriert
      Log3($name, 3, "$name - Attribute \"smtpNoUseSSL\" will be ignored due to usage of Net::SMTP::SSL") if(AttrVal($name,"smtpNoUseSSL",0));
      $smtp = Net::SMTP::SSL->new(Host => $smtphost, Port => $smtpsslport, Debug => $smtpdebug);
  } else {
      # Verwendung neues Net::SMTP::SSL > 3.00
      if($sslfrominit) {
          # sofortiger SSL connect
          $smtp = Net::SMTP->new(Host => $smtphost, Port => $smtpsslport, SSL => 1, Debug => $smtpdebug);
      } else {
          # erst unverschlüsselt, danach switch zu encrypted
          $smtp = Net::SMTP->new(Host => $smtphost, Port => $smtpport, SSL => 0, Debug => $smtpdebug);
      }
  }
      
  if(!$smtp) {
      $err = "SMTP Error: Can't connect to host $smtphost";
      Log3($name, 2, "$name - $err");
      $err = encode_base64($err,"");
      return "$name|$err|''";   
  }
      
  if(!$sslfb && !$sslfrominit) {  
      # Aufbau unverschlüsselt -> switch zu verschlüsselt wenn nicht untersagt  
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
      } else {
          Log3($name, 3, "$name - SMTP-Host $smtphost use unencrypted connection !");
      }
  } else {
      eval { $sslver = $smtp->get_sslversion(); };   # Forum: https://forum.fhem.de/index.php/topic,45671.msg880602.html#msg880602
      $sslver = $sslver?$sslver:"n.a.";
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
  
  if($sdat || $vdat) {
      # handles schließen
      foreach my $key (@as) {
          close '$fh'.$key;
      }
  }
  
  use strict "refs";
  
  # Daten müssen als Einzeiler zurückgegeben werden
  $ret = encode_base64($ret,"");
 
return "$name|''|$ret";
}

####################################################################################################
#                   Auswertungsroutine nichtblockierendes Send EMail
####################################################################################################
sub SSCam_sendEmaildone($) {
  my ($string) = @_;
  my @a        = split("\\|",$string);
  my $hash     = $defs{$a[0]};
  my $err      = $a[1]?decode_base64($a[1]):undef;
  my $ret      = $a[2]?decode_base64($a[2]):undef;
  
  if ($err) {
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,"sendEmailState",$err);
      readingsEndUpdate($hash, 1);
      delete($hash->{HELPER}{RUNNING_PID});
      return;
  } 
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"sendEmailState",$ret);
  readingsEndUpdate($hash, 1);
      
  delete($hash->{HELPER}{RUNNING_PID});
                  
return;
}

####################################################################################################
#                               Abbruchroutine Send EMail
####################################################################################################
sub SSCam_sendEmailto(@) {
  my ($hash,$cause) = @_;
  my $name = $hash->{NAME}; 
  
  $cause = $cause?$cause:"Timeout: process terminated";
  Log3 ($name, 1, "$name -> BlockingCall $hash->{HELPER}{RUNNING_PID}{fn} pid:$hash->{HELPER}{RUNNING_PID}{pid} $cause");    
  
  readingsBeginUpdate($hash);
  readingsBulkUpdateIfChanged($hash,"sendEmailState",$cause);
  readingsEndUpdate($hash, 1);
  
  delete($hash->{HELPER}{RUNNING_PID});

return;
}

#############################################################################################
#                                   Token setzen
#############################################################################################
sub SSCam_setActiveToken ($) { 
   my ($hash) = @_;
   my $name = $hash->{NAME};
               
   $hash->{HELPER}{ACTIVE} = "on";
   if (AttrVal($name,"debugactivetoken",0)) {
       Log3($name, 1, "$name - Active-Token set by OPMODE: $hash->{OPMODE}");
   } 
   
return;
}

#############################################################################################
#                                   Token freigeben
#############################################################################################
sub SSCam_delActiveToken ($) { 
   my ($hash) = @_;
   my $name = $hash->{NAME};
               
   $hash->{HELPER}{ACTIVE} = "off";
   if (AttrVal($name,"debugactivetoken",0)) {
       Log3($name, 1, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
   }  
   
return;
}  

#############################################################################################
#              Transaktion starten oder vorhandenen TA Code zurück liefern
#############################################################################################
sub SSCam_openOrgetTrans ($) { 
   my ($hash) = @_;
   my $name = $hash->{NAME};
   my $tac  = ""; 
   
   if(!$hash->{HELPER}{TRANSACTION}) {                
       $tac = int(rand(4500));                      # Transaktionscode erzeugen und speichern
       $hash->{HELPER}{TRANSACTION} = $tac;
       if (AttrVal($name,"debugactivetoken",0)) {
           Log3($name, 1, "$name - Transaction opened, TA-code: $tac");
       } 
   } else {
       $tac = $hash->{HELPER}{TRANSACTION};         # vorhandenen Transaktionscode zurück liefern
   }
   
return $tac;
}

#############################################################################################
#                                 Transaktion freigeben
#############################################################################################
sub SSCam_closeTrans ($) { 
   my ($hash) = @_;
   my $name = $hash->{NAME};
   
   return if(!defined $hash->{HELPER}{TRANSACTION});  
   my $tac = delete $hash->{HELPER}{TRANSACTION};            # Transaktion beenden   
   if (AttrVal($name,"debugactivetoken",0)) {
       Log3($name, 1, "$name - Transaction \"$tac\" closed");
   }
   
   SSCam_cleanData($name,$tac);                              # $data Hash bereinigen
   
return;
}

####################################################################################################
#                               $data Hash bereinigen
####################################################################################################
sub SSCam_cleanData($;$) {
  my ($name,$tac) = @_;
  my $del = 0;
  
  delete $data{SSCam}{RS};
  
  if($tac) {
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
          Log3($name, 1, "$name - Data Hash (SENDRECS/SENDSNAPS/PARAMS) of Transaction \"$tac\" deleted");
      }
  } else {
      delete $data{SSCam}{$name}{SENDRECS};
      delete $data{SSCam}{$name}{SENDSNAPS};
      delete $data{SSCam}{$name}{PARAMS};
      if (AttrVal($name,"debugactivetoken",0)) {
          Log3($name, 1, "$name - Data Hash (SENDRECS/SENDSNAPS/PARAMS) deleted");
      }      
  }

return;
}

#############################################################################################
#             Leerzeichen am Anfang / Ende eines strings entfernen           
#############################################################################################
sub SSCam_trim ($) {
 my $str = shift;
 $str =~ s/^\s+|\s+$//g;
return ($str);
}

#############################################################################################
#                          Versionierungen des Moduls setzen
#                  Die Verwendung von Meta.pm und Packages wird berücksichtigt
#############################################################################################
sub SSCam_setVersionInfo($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (SSCam_sortVersion("desc",keys %SSCam_vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {
	  # META-Daten sind vorhanden
	  $modules{$type}{META}{version} = "v".$v;              # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{SMAPortal}{META}}
	  if($modules{$type}{META}{x_version}) {                                                                             # {x_version} ( nur gesetzt wenn $Id: 49_SSCam.pm 20152 2019-09-12 20:37:17Z DS_Starter $ im Kopf komplett! vorhanden )
		  $modules{$type}{META}{x_version} =~ s/1.1.1/$v/g;
	  } else {
		  $modules{$type}{META}{x_version} = $v; 
	  }
	  return $@ unless (FHEM::Meta::SetInternals($hash));                                                                # FVERSION wird gesetzt ( nur gesetzt wenn $Id: 49_SSCam.pm 20152 2019-09-12 20:37:17Z DS_Starter $ im Kopf komplett! vorhanden )
	  if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {
	      # es wird mit Packages gearbeitet -> Perl übliche Modulversion setzen
		  # mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
	      use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );                                          
      }
  } else {
	  # herkömmliche Modulstruktur
	  $hash->{VERSION} = $v;
  }
  
return;
}

#############################################################################################
#                                       Hint Hash EN           
#############################################################################################
%SSCam_vHintsExt_en = (
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
         "The compatible SVS-Version is printed out in the Internal COMPATIBILITY.\n".
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
%SSCam_vHintsExt_de = (
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
         "wurde oder (teilweise) mit dieser Version nicht kompatibel ist. Die kompatible SVS-Version ist im Internal COMPATIBILITY ersichtlich.\n".
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
       <li>Trigger of snapshots and optionally send them alltogether by Email/TelegramBot using the integrated Email client </li>
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
       <li>save the last recording of camera locally </li>
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
    Further informations could be find among <a href="#SSCam_Credentials">Credentials</a>.  <br><br>
    
    Overview which Perl-modules SSCam is using: <br><br>
    
    JSON            <br>
    Data::Dumper    <br>                  
    MIME::Base64    <br>
    Time::HiRes     <br>
    Encode          <br>
    HttpUtils       (FHEM-module) <br>
	BlockingCall    (FHEM-module) <br>
	Net::SMTP       (if integrated send Email is used) <br>
	MIME::Lite      (if integrated send Email is used) 
    
	<br><br>
    
    The PTZ panel (only PTZ cameras) in SSCam use its own icons. 
    Thereby the system find the icons, in FHEMWEB device the attribute "iconPath" has to be completed by "sscam" 
    (e.g. "attr WEB iconPath default:fhemSVG:openautomation:sscam").
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
    
    <a name="SSCam_Credentials"></a>
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
    
<a name="SSCam_HTTPTimeout"></a>
<b>HTTP-Timeout Settings</b><br><br>
    
  <ul>  
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
  <li><b> set &lt;name&gt; autocreateCams </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for SVS)</li> <br>
  
  If a SVS device is defined, all in SVS integrated cameras are able to be created automatically in FHEM by this command. If the camera is already defined, 
  it is overleaped. 
  The new created camera devices are created in the same room as the used SVS device (default SSCam). Further helpful attributes are preset as well. 
  <br><br>
  </ul>
  
  <ul>
  <a name="SSCamcreateStreamDev"></a>
  <li><b> set &lt;name&gt; createStreamDev [generic | hls | lastsnap | mjpeg | switched] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  A separate Streaming-Device (type SSCamSTRM) will be created. This device can be used as a discrete device in a dashboard 
  for example.
  The current room of the parent camera device is assigned to the new device if it is set there.
  <br><br>
  
    <ul>
    <table>
    <colgroup> <col width=10%> <col width=90%> </colgroup>
      <tr><td>generic   </td><td>- the streaming device playback a content determined by attribute "genericStrmHtmlTag" </td></tr>
      <tr><td>hls       </td><td>- the streaming device playback a permanent HLS video stream </td></tr>
      <tr><td>lastsnap  </td><td>- the streaming device playback the newest snapshot </td></tr>
      <tr><td>mjpeg     </td><td>- the streaming device playback a permanent MJPEG video stream (Streamkey method) </td></tr>
      <tr><td>switched  </td><td>- playback of different streaming types. Buttons for mode control are provided. </td></tr>
    </table>
    </ul>
    <br><br>  
 
  You can control the design with HTML tags in <a href="#SSCamattr">attribute</a> "htmlattr" of the camera device or by 
  specific attributes of the SSCamSTRM-device itself. <br><br>
  
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
  <br>
  </ul>
  <br><br>   
  
  <ul>
  <li><b> set &lt;name&gt; createPTZcontrol </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for PTZ-CAM)</li> <br>
  
  A separate PTZ control panel will be created (type SSCamSTRM). The current room of the parent camera device is 
  assigned if it is set there (default "SSCam").  
  With the "ptzPanel_.*"-<a href="#SSCamattr">attributes</a> or respectively the specific attributes of the SSCamSTRM-device
  the properties of the control panel can be affected. <br> 
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; createReadingsGroup [&lt;name of readingsGroup&gt;]</b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM/SVS)</li> <br>
  
  This command creates a readingsGroup device to display an overview of all defined SSCam devices. 
  A name for the new readingsGroup device can be specified. Is no own name specified, the readingsGroup device will be 
  created with name "RG.SSCam".
  <br> 
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; createSnapGallery </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
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
  <br>
  
  <ul>
  <li><b> set &lt;name&gt; off  </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li><br>

  Stops the current recording. 
  </ul>
  <br><br>
  
  <ul>
  <li><b>set &lt;name&gt; on [&lt;rectime&gt;] [recEmailTxt:"subject => &lt;subject text&gt;, body => &lt;message text&gt;"] [recTelegramTxt:"tbot => &lt;TelegramBot device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;subject text&gt;]"]  </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
   
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
  <li><b> set &lt;name&gt; pirSensor [activate | deactivate] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  Activates / deactivates the infrared sensor of the camera (only posible if the camera has got a PIR sensor).  
  </ul>
  <br><br>
  
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
  <li><b> set &lt;name&gt; snap [&lt;number&gt;] [&lt;time difference&gt;] [snapEmailTxt:"subject => &lt;subject text&gt;, body => &lt;message text&gt;"] [snapTelegramTxt:"tbot => &lt;TelegramBot device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;subject text&gt;]"] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  One or multiple snapshots are triggered. The number of snapshots to trigger and the time difference (in seconds) between
  each snapshot can be optionally specified. Without any specification only one snapshot is triggered. <br>
  The ID and the filename of the last snapshot will be displayed in Reading "LastSnapId" respectively 
  "LastSnapFilename". <br>
  To get data of the last 1-10 snapshots in various versions, the <a href="#SSCamattr">attribute</a> "snapReadingRotate"
  can be used.
  <br><br>
  
  The snapshot <b>Email shipping</b> can be activated by setting <a href="#SSCamattr">attribute</a> "snapEmailTxt". 
  Before you have to prepare the Email shipping as described in section <a href="#SSCamEmail">Setup Email shipping</a>. 
  (for further information execute "<b>get &lt;name&gt; versionNotes 7</b>") <br>
  If you want temporary overwrite the message text set in attribute "snapEmailTxt", you can optionally specify the 
  "snapEmailTxt:"-tag as shown above. If the attribute "snapEmailTxt" is not set, the Email shipping is
  activated one-time. (the tag-syntax is equivalent to the "snapEmailTxt" attribut) <br><br>
  
  A snapshot shipping by <b>Telegram</b> can be permanntly activated by setting <a href="#SSCamattr">attribute</a> 
  "snapTelegramTxt". Of course, the <a href="http://fhem.de/commandref.html#TelegramBot">TelegramBot device</a> which is 
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
  </pre>
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; snapCams [&lt;number&gt;] [&lt;time difference&gt;] [CAM:"&lt;camera&gt;, &lt;camera&gt, ..."]</b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for SVS)</li> <br>
  
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
  <li><b> set &lt;name&gt; snapGallery [1-10] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
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
  <li><b> get &lt;name&gt; saveRecording [&lt;path&gt;] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM)</li> <br>
  
  The current recording present in Reading "CamLastRec" is saved lcally as a MP4 file. Optionally you can specify the path 
  for the file to save (default: modpath in global device). <br>
  The name of the saved local file is the same as displayed in Reading "CamLastRec". <br><br>
  
  <ul>
    <b>Beispiel:</b> <br><br>
    get &lt;name&gt; saveRecording /opt/fhem/log
  </ul>
  
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
		ressources are needed. The camera names in Synology SVS should not be very similar, otherwise the retrieval of 
        snapshots could come to inaccuracies.
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

  <ul>
  <li><b> get &lt;name&gt; versionNotes [hints | rel | &lt;key&gt;] </b> &nbsp;&nbsp;&nbsp;&nbsp;(valid for CAM/SVS)</li> <br>
  
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
      <tr><td style="vertical-align:top"> <b>snapEmailTxt</b> <td>- <b>Activates the Email shipping of snapshots.</b> This attribute has the format: <br>
                                                                  <code>subject => &lt;subject text&gt;, body => &lt;message text&gt; </code><br> 
                                                                  The placeholder $CAM, $DATE and $TIME can be used. <br> 
																  Optionally you can specify the "snapEmailTxt:"-tag when trigger a snapshot with the "snap"-command.
                                                                  In this case the Email shipping is activated one-time for the snapshot or the tag-text 
                                                                  is used instead of the text defined in the "snapEmailTxt"-attribute. </td></tr>
      <tr><td style="vertical-align:top"> <b>recEmailTxt</b> <td>- <b>Activates the Email shipping of recordings.</b> This attribute has the format: <br>
                                                                  <code>subject => &lt;subject text&gt;, body => &lt;message text&gt; </code><br> 
                                                                  The placeholder $CAM, $DATE and $TIME can be used. <br> 
                                                                  Optionally you can specify the "recEmailTxt:"-tag when start recording with the "on"-command.
                                                                  In this case the Email shipping is activated one-time for the started recording or the tag-text 
                                                                  is used instead of the text defined in the "recEmailTxt"-attribute. </td></tr>
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
  <a name="debugactivetoken"></a>
  <li><b>debugactivetoken</b><br>
    if set the state of active token will be logged - only for debugging, don't use it in normal operation ! </li><br>
  
  <a name="disable"></a>
  <li><b>disable</b><br>
    deactivates the device definition </li><br>
    
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
        attr &lt;name&gt; hlsStrmObject https://video-dev.github.io/streams/x36xhzz/x36xhzz.m3u8  <br>
        # a video stream used for testing the streaming device function (internet connection is needed) <br><br>
        attr &lt;name&gt; hlsStrmObject http://192.168.2.10:32000/CamHE1.m3u8  <br>
        # playback a HLS video stream of a camera witch is delivered by e.g. a ffmpeg conversion process   <br><br>
        attr &lt;name&gt; hlsStrmObject http://192.168.2.10:32000/$NAME.m3u8  <br>
        # Same as example above, but use the replacement with variable $NAME for "CamHE1"     
        </ul>
		<br>
  </li>
  
  <a name="httptimeout"></a>
  <li><b>httptimeout</b><br>
    Timeout-Value of HTTP-Calls to Synology Surveillance Station, Default: 4 seconds (if httptimeout = "0" 
	or not set) </li><br>
  
  <a name="htmlattr"></a>
  <li><b>htmlattr</b><br>
    additional specifications to inline oictures to manipulate the behavior of stream, e.g. size of the image.	</li><br>
	
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
    Insufficient user privilege" and makes login possible.  </li><br>
  
  <a name="pollcaminfoall"></a>
  <li><b>pollcaminfoall</b><br>
    Interval of automatic polling the Camera properties (if <= 10: no polling, if &gt; 10: polling with interval) </li><br>

   <a name="pollnologging"></a>
  <li><b>pollnologging</b><br>
    "0" resp. not set = Logging device polling active (default), "1" = Logging device polling inactive</li><br>
   
  <a name="ptzPanel_Home"></a>
  <li><b>ptzPanel_Home</b><br>
    In the PTZ-control panel the Home-Icon (in attribute "ptzPanel_row02") is automatically assigned to the value of 
    Reading "PresetHome".
    With "ptzPanel_Home" you can change the assignment to another preset from the available Preset list. </li><br> 
  
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
  
  <a name="snapEmailTxt"></a>
  <li><b>snapEmailTxt subject => &lt;subject text&gt;, body => &lt;message text&gt; </b><br>
    Activates the Email shipping of snapshots after whose creation. <br>
    The attribute has to be definied in the form as described. <br>
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
    replaces the content of reading "VideoFolder", Usage if e.g. folders are mountet with different names than original 
	(SVS) </li><br>
  
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
      <li>Auslösen von Schnappschnüssen und optional gemeinsamer Email/TelegramBot-Versand mittels integrierten Email-Client </li>
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
      <li>lokales Abspeichern der letzten Kamera-Aufnahme </li>
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
    Nähere Informationen dazu unter <a href="#SSCam_Credentials">Credentials</a><br><br>
        
    Überblick über die Perl-Module welche von SSCam genutzt werden: <br><br>
    
    JSON            <br>
    Data::Dumper    <br>                  
    MIME::Base64    <br>
    Time::HiRes     <br>
    Encode          <br>
    HttpUtils       (FHEM-Modul) <br>
	BlockingCall    (FHEM-Modul) <br>
	Net::SMTP       (wenn Email-Versand verwendet) <br>
	MIME::Lite      (wenn Email-Versand verwendet)
    
    <br><br>
	
    Das PTZ-Paneel (nur PTZ Kameras) in SSCam benutzt einen eigenen Satz Icons. 
    Damit das System sie findet, ist im FHEMWEB Device das Attribut "iconPath" um "sscam" zu ergänzen 
    (z.B. "attr WEB iconPath default:fhemSVG:openautomation:sscam").
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
    
    <a name="SSCam_Credentials"></a>
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
    
<a name="SSCam_HTTPTimeout"></a>
<b>HTTP-Timeout setzen</b><br><br>
    
    <ul>
    Alle Funktionen dieses Moduls verwenden HTTP-Aufrufe gegenüber der SVS Web API. <br>
    Der Standardwert für den HTTP-Timeout beträgt 4 Sekunden. Durch Setzen des 
    <a href="#SSCamattr">Attributes</a> "httptimeout" > 0 kann dieser Wert bei Bedarf entsprechend den technischen 
    Gegebenheiten angepasst werden. <br> 
    
  </ul>
  <br><br><br>
  
<a name="SSCamset"></a>
<b>Set </b>
<ul>
  <br>
  Die aufgeführten set-Befehle sind für CAM/SVS-Devices oder nur für CAM-Devices bzw. nur für SVS-Devices gültig. Sie stehen im 
  Drop-Down-Menü des jeweiligen Devices zur Auswahl zur Verfügung. <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; autocreateCams </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für SVS)</li> <br>
  
  Ist ein SVS-Device definiert, können mit diesem Befehl alle in der SVS integrierten Kameras automatisiert angelegt werden. Bereits definierte 
  Kameradevices werden übersprungen. 
  Die neu erstellten Kameradevices werden im gleichen Raum wie das SVS-Device definiert (default SSCam). Weitere sinnvolle Attribute werden ebenfalls 
  voreingestellt. 
  <br><br>
  </ul>
  
  <ul>
  <a name="SSCamcreateStreamDev"></a>
  <li><b> set &lt;name&gt; createStreamDev [generic | hls | lastsnap | mjpeg | switched] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>

  Es wird ein separates Streaming-Device (Typ SSCamSTRM) erstellt. Dieses Device kann z.B. als separates Device 
  in einem Dashboard genutzt werden.
  Dem Streaming-Device wird der aktuelle Raum des Kameradevice zugewiesen sofern dort gesetzt. 
  <br><br>
  
    <ul>
    <table>
    <colgroup> <col width=10%> <col width=90%> </colgroup>
      <tr><td>generic   </td><td>- das Streaming-Device gibt einen durch das Attribut "genericStrmHtmlTag" bestimmten Content wieder </td></tr>
      <tr><td>hls       </td><td>- das Streaming-Device gibt einen permanenten HLS Datenstrom wieder </td></tr>
      <tr><td>lastsnap  </td><td>- das Streaming-Device zeigt den neuesten Schnappschuß an </td></tr>
      <tr><td>mjpeg     </td><td>- das Streaming-Device gibt einen permanenten MJPEG Kamerastream wieder (Streamkey Methode) </td></tr>
      <tr><td>switched  </td><td>- Wiedergabe unterschiedlicher Streamtypen. Drucktasten zur Steuerung werden angeboten. </td></tr>
    </table>
    </ul>
    <br><br>
  
  Die Gestaltung kann durch HTML-Tags im <a href="#SSCamattr">Attribut</a> "htmlattr" im Kameradevice oder mit den 
  spezifischen Attributen im Streaming-Device beeinflusst werden. <br><br>
  
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
  <br>
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; createPTZcontrol </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für PTZ-CAM)</li> <br>
  
  Es wird ein separates PTZ-Steuerungspaneel (Type SSCamSTRM) erstellt. Es wird der aktuelle Raum des Kameradevice 
  zugewiesen sofern dort gesetzt (default "SSCam").  
  Mit den "ptzPanel_.*"-<a href="#SSCamattr">Attributen</a> bzw. den spezifischen Attributen des erzeugten 
  SSCamSTRM-Devices können die Eigenschaften des PTZ-Paneels beeinflusst werden. <br> 
  <br><br>
  </ul>
  
  <ul>
  <li><b> set &lt;name&gt; createReadingsGroup [&lt;Name der readingsGroup&gt;]</b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM/SVS)</li> <br>
  
  Es wird ein readingsGroup-Device zur Übersicht aller vorhandenen SSCam-Devices erstellt. Es kann ein eigener Name angegeben 
  werden. Ist kein Name angegeben, wird eine readingsGroup mit dem Namen "RG.SSCam" erzeugt.
  <br> 
  <br><br>
  </ul>
    
  <ul>
  <li><b> set &lt;name&gt; createSnapGallery </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
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
  <br>
  
  <ul>
  <li><b> set &lt;name&gt; off  </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li><br>

  Stoppt eine laufende Aufnahme. 
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; on [&lt;rectime&gt;] [recEmailTxt:"subject => &lt;Betreff-Text&gt;, body => &lt;Mitteilung-Text&gt;"] [recTelegramTxt:"tbot => &lt;TelegramBot-Device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;Betreff-Text&gt;]"] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li><br>

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
  <li><b> set &lt;name&gt; pirSensor [activate | deactivate] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Aktiviert / deaktiviert den Infrarot-Sensor der Kamera (sofern die Kamera einen PIR-Sensor enthält).  
  </ul>
  <br><br>
  
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
  <li><b> set &lt;name&gt; smtpcredentials &lt;user&gt; &lt;password&gt; </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Setzt die Credentials für den Zugang zum Postausgangsserver wenn Email-Versand genutzt wird.

  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; snap [&lt;Anzahl&gt;] [&lt;Zeitabstand&gt;] [snapEmailTxt:"subject => &lt;Betreff-Text&gt;, body => &lt;Mitteilung-Text&gt;"] [snapTelegramTxt:"tbot => &lt;TelegramBot-Device&gt;, peers => [&lt;peer1 peer2 ...&gt;], subject => [&lt;Betreff-Text&gt;]"]   </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
  Ein oder mehrere Schnappschüsse werden ausgelöst. Es kann die Anzahl der auszulösenden Schnappschüsse und deren zeitlicher
  Abstand in Sekunden optional angegeben werden. Ohne Angabe wird ein Schnappschuß getriggert. <br>
  Es wird die ID und der Filename des letzten Snapshots als Wert der Readings "LastSnapId" bzw. "LastSnapFilename" in  
  der Kamera gespeichert. <br>
  Um die Daten der letzen 1-10 Schnappschüsse zu versionieren, kann das <a href="#SSCamattr">Attribut</a> "snapReadingRotate"
  verwendet werden.
  <br><br>
  
  Ein <b>Email-Versand</b> der Schnappschüsse kann durch Setzen des <a href="#SSCamattr">Attributs</a> "snapEmailTxt" permanent aktiviert
  werden. Zuvor ist der Email-Versand, wie im Abschnitt <a href="#SSCamEmail">Einstellung Email-Versand</a> beschrieben,
  einzustellen. (Für weitere Informationen "<b>get &lt;name&gt; versionNotes 7</b>" ausführen) <br>
  Der Text im Attribut "snapEmailTxt" kann durch die Spezifikation des optionalen "snapEmailTxt:"-Tags, wie oben 
  gezeigt, temporär überschrieben bzw. geändert werden. Sollte das Attribut "snapEmailTxt" nicht gesetzt sein, wird durch Angabe dieses Tags
  der Email-Versand einmalig aktiviert. (die Tag-Syntax entspricht dem "snapEmailTxt"-Attribut) <br><br>
  
  Ein <b>Telegram-Versand</b> der Schnappschüsse kann durch Setzen des <a href="#SSCamattr">Attributs</a> "snapTelegramTxt" permanent aktiviert
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
  </pre>
  </ul>
  <br><br>
  
  <ul>
  <li><b> set &lt;name&gt; snapCams [&lt;Anzahl&gt;] [&lt;Zeitabstand&gt;] [CAM:"&lt;Kamera&gt;, &lt;Kamera&gt, ..."]</b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für SVS)</li> <br>
  
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
  <li><b> set &lt;name&gt; snapGallery [1-10] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
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
  <li><b> get &lt;name&gt; saveRecording [&lt;Pfad&gt;] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM)</li> <br>
  
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
		RAM-Ressourcen benötigt. Die Namen der Kameras in der SVS sollten sich nicht stark ähneln, da es ansonsten zu 
        Ungnauigkeiten beim Abruf der Schnappschußgallerie kommen kann.
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
  
  <ul>
  <li><b> get &lt;name&gt; versionNotes [hints | rel | &lt;key&gt;] </b> &nbsp;&nbsp;&nbsp;&nbsp;(gilt für CAM/SVS)</li> <br>
  
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
  Ist das Attribut "smtpSSLPort" definiert, erfolgt der Verbindungsaufbau zum Email-Server sofort verschlüsselt. 
  <br><br>
  
  Optionale Attribute sind gekennzeichnet: <br><br>
  
  <ul>   
    <table>  
    <colgroup> <col width=12%> <col width=88%> </colgroup>
      <tr><td style="vertical-align:top"> <b>snapEmailTxt</b> <td>- <b>Aktiviert den Email-Versand von Schnappschüssen</b>. 
                                                                  Das Attribut hat das Format: <br>
                                                                  <ul>
                                                                  <code>subject => &lt;Betreff-Text&gt;, body => &lt;Mitteilung-Text&gt;</code><br>
                                                                  </ul>
                                                                  Es können die Platzhalter $CAM, $DATE und $TIME verwendet werden. <br>
																  Der Email-Versand des letzten Schnappschusses wird einmalig aktiviert falls der "snapEmailTxt:"-Tag 
																  beim "snap"-Kommando verwendet wird bzw. der in diesem Tag definierte Text statt des Textes im 
																  Attribut "snapEmailTxt" verwendet. </td></tr>
      
      <tr><td style="vertical-align:top"> <b>recEmailTxt</b> <td>- <b>Aktiviert den Email-Versand von Aufnahmen</b>. 
                                                                  Das Attribut hat das Format: <br>
                                                                  <ul>
                                                                  <code>subject => &lt;Betreff-Text&gt;, body => &lt;Mitteilung-Text&gt;</code><br>
                                                                  </ul>
                                                                  Es können die Platzhalter $CAM, $DATE und $TIME verwendet werden. <br>
                                                                  Der Email-Versand der letzten Aufnahme wird einamlig aktiviert falls der "recEmailTxt:"-Tag beim 
                                                                  "on"-Kommando verwendet wird bzw. der in diesem Tag definierte Text statt des Textes im 
																  Attribut "recEmailTxt" verwendet. </td></tr>
																  
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
  <a name="debugactivetoken"></a>
  <li><b>debugactivetoken</b><br> 
    wenn gesetzt wird der Status des Active-Tokens gelogged - nur für Debugging, nicht im 
    normalen Betrieb benutzen ! </li><br>
  
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
    Timeout-Wert für HTTP-Aufrufe zur Synology Surveillance Station, Default: 4 Sekunden (wenn 
    httptimeout = "0" oder nicht gesetzt) </li><br>
    
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
        attr &lt;name&gt; hlsStrmObject https://video-dev.github.io/streams/x36xhzz/x36xhzz.m3u8  <br>
        # ein Beispielstream der zum Test des Streaming Devices verwendet werden kann (Internetverbindung nötig) <br><br>
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
    Intervall der automatischen Eigenschaftsabfrage (Polling) einer Kamera (kleiner/gleich 10: kein 
    Polling, größer 10: Polling mit Intervall) </li><br>
  
  <a name="pollnologging"></a>
  <li><b>pollnologging</b><br>
    "0" bzw. nicht gesetzt = Logging Gerätepolling aktiv (default), "1" = Logging 
    Gerätepolling inaktiv </li><br>
  
  <a name="ptzPanel_Home"></a>  
  <li><b>ptzPanel_Home</b><br>
    Im PTZ-Steuerungspaneel wird dem Home-Icon (im Attribut "ptzPanel_row02") automatisch der Wert des Readings 
    "PresetHome" zugewiesen.
    Mit "ptzPanel_Home" kann diese Zuweisung mit einem Preset aus der verfügbaren Preset-Liste geändert werden. </li><br> 
  
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
	Wurde "peer" leer gelassen, wird der Default-Peer des TelegramBot-Device verwendet. <br><br>
    
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
    ersetzt den Inhalt des Readings "VideoFolder", Verwendung z.B. bei gemounteten 
    Verzeichnissen </li><br>
  
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
        "HttpUtils": 0,
        "Blocking": 0,
        "Encode": 0        
      },
      "recommends": {
        "FHEM::Meta": 0
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
