###############################################################################
#
# $Id$
# 
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
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
#
#
# Husqvarnas Open API is used
# based on some ideas from HusqvarnaAutomower and BOTVAC module
# 
################################################################################

package FHEM::AutomowerConnect;
our $cvsid = '$Id$';
use strict;
use warnings;
use POSIX;

# wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use GPUtils qw(:all);

GP_Export(
    qw(
      Initialize
      )
);

require FHEM::Devices::AMConnect::Common;

##############################################################
sub Initialize() {
  my ($hash) = @_;

  $hash->{DefFn}      = \&FHEM::Devices::AMConnect::Common::Define;
  $hash->{GetFn}      = \&FHEM::Devices::AMConnect::Common::Get;
  $hash->{UndefFn}    = \&FHEM::Devices::AMConnect::Common::Undefine;
  $hash->{DeleteFn}   = \&FHEM::Devices::AMConnect::Common::Delete;
  $hash->{ShutdownFn} = \&FHEM::Devices::AMConnect::Common::Shutdown;
  $hash->{RenameFn}   = \&FHEM::Devices::AMConnect::Common::Rename;
  $hash->{FW_detailFn}= \&FHEM::Devices::AMConnect::Common::FW_detailFn;
  $hash->{ReadFn}     = \&FHEM::Devices::AMConnect::Common::wsRead; 
  $hash->{ReadyFn}    = \&FHEM::Devices::AMConnect::Common::wsReady;
  $hash->{SetFn}      = \&FHEM::Devices::AMConnect::Common::Set;
  $hash->{AttrFn}     = \&FHEM::Devices::AMConnect::Common::Attr;
  $hash->{AttrList}   = "disable:1,0 " .
                        "debug:1,0 " .
                        "disabledForIntervals " .
                        "mapImagePath " .
                        "mapImageWidthHeight " .
                        "mapImageCoordinatesToRegister:textField-long " .
                        "mapImageCoordinatesUTM:textField-long " .
                        "mapImageZoom " .
                        "mapBackgroundColor " .
                        "mapDesignAttributes:textField-long " .
                        "mapZones:textField-long " .
                        "showMap:1,0 " .
                        "chargingStationCoordinates " .
                        "chargingStationImagePosition:left,top,right,bottom,center " .
                        "scaleToMeterXY " .
                        "mowerCuttingWidth " .
                        "mowerSchedule:textField-long " .
                        "mowingAreaLimits:textField-long " .
                        "propertyLimits:textField-long " .
                        "weekdaysToResetWayPoints " .
                        "numberOfWayPointsToDisplay " .
                        "addPollingMinInterval " .
                        "addPositionPolling:1,0 " .
                        $::readingFnAttributes;

  $::data{FWEXT}{AutomowerConnect}{SCRIPT} = "automowerconnect.js";

  return undef;
}

##############################################################


1;

__END__

=pod

=item device
=item summary    Module to control Husqvarnas robotic lawn mowers with Connect Module (SIM) 
=item summary_DE Modul zur Steuerung von Husqvarnas Mähroboter mit Connect Modul (SIM)

=begin html

<a id="AutomowerConnect" ></a>
<h3>AutomowerConnect</h3>
<ul>
  <u><b>FHEM-FORUM:</b></u> <a target="_blank" href="https://forum.fhem.de/index.php/topic,131661.0.html"> AutomowerConnect</a><br>
  <u><b>FHEM-Wiki:</b></u> <a target="_blank" href="https://wiki.fhem.de/wiki/AutomowerConnect"> AutomowerConnect: Wie erstellt man eine Karte des Mähbereiches?</a>
  <br><br>
  <u><b>Introduction</b></u>
  <br><br>
  <ul>
    <li>This module allows the communication between the Husqvarna Cloud and FHEM to control Husqvarna Automower equipped with a Connect Module (SIM).</li>
    <li>It acts as Device for one mower. Use this Module for aditional mower registered in the API. Provide a different application key and application secret each mower</li>
    <li>The mower path is shown in the detail view.</li>
    <li>An arbitrary map can be used as background for the mower path.</li>
    <li>The map has to be a raster image in webp, png or jpg format.</li>
    <li>It's possible to control everything the API offers, e.g. schedule, headlight, cutting height and actions like start, pause, park etc. </li>
    <li>Zones are definable. </li>
    <li>Cutting height can be set for each zone differently. </li>
    <li>All API data is stored in the device hash. Use <code>{Dumper $defs{&lt;name&gt;}}</code> in the commandline to find the data and build userReadings out of it.</li><br>
  </ul>
  <u><b>Requirements</b></u>
  <br><br>
  <ul>
    <li>To get access to the API an application has to be created in the <a target="_blank" href="https://developer.husqvarnagroup.cloud/docs/get-started">Husqvarna Developer Portal</a>. The application has to be connected with the AutomowerConnect API.</li>
    <li>During registration an application key (client_id) and an application secret (client secret) is provided. Use these for the module.</li>
    <li>The module uses client credentials as grant type for authorization.</li>
  </ul>
  <br>
  <a id="AutomowerConnectDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;device name&gt; AutomowerConnect &lt;application key&gt; [&lt;mower number&gt;]</code><br>
    Example:<br>
    <code>define myMower AutomowerConnect 123456789012345678901234567890123456</code> First device: the default mower number is 0.<br>
    It has to be set a <b>client_secret</b>. It's the application secret from the <a target="_blank" href="https://developer.husqvarnagroup.cloud/docs/get-started">Husqvarna Developer Portal</a>.<br>
    <code>set myMower &lt;client secret&gt;</code>
    <br><br>
  </ul>
  <br>

  <a id="AutomowerConnectSet"></a>
  <b>Set</b>
  <ul>
    <li><a id='AutomowerConnect-set-Park'>Park</a><br>
      <code>set &lt;name&gt; Park &lt;number of minutes&gt;</code><br>
      Parks mower in charging station for &lt;number of minutes&gt;</li>

    <li><a id='AutomowerConnect-set-ParkUntilFurtherNotice'>ParkUntilFurtherNotice</a><br>
      <code>set &lt;name&gt; ParkUntilFurtherNotice</code><br>
      Parks mower in charging station until further notice</li>

    <li><a id='AutomowerConnect-set-ParkUntilNextSchedule'>ParkUntilNextSchedule</a><br>
      <code>set &lt;name&gt; ParkUntilNextSchedule</code><br>
      Parks mower in charging station and starts with next planned start</li>

    <li><a id='AutomowerConnect-set-Pause'>Pause</a><br>
      <code>set &lt;name&gt; Pause</code><br>
      Pauses mower immediately at current position</li>

    <li><a id='AutomowerConnect-set-ResumeSchedule'>ResumeSchedule</a><br>
      <code>set &lt;name&gt; ResumeSchedule</code><br>
      Starts immediately if in planned intervall, otherwise with next scheduled start&gt;</li>

    <li><a id='AutomowerConnect-set-Start'>Start</a><br>
      <code>set &lt;name&gt; Start &lt;number of minutes&gt;</code><br>
      Starts immediately for &lt;number of minutes&gt;</li>

    <li><a id='AutomowerConnect-set-chargingStationPositionToAttribute'>chargingStationPositionToAttribute</a><br>
      <code>set &lt;name&gt; chargingStationPositionToAttribute</code><br>
      Sets the calculated charging station coordinates to the corresponding attributes.</li>

    <li><a id='AutomowerConnect-set-client_secret'>client_secret</a><br>
      <code>set &lt;name&gt; client_secret &lt;application secret&gt;</code><br>
      Sets the mandatory application secret (client secret)</li>

    <li><a id='AutomowerConnect-set-cuttingHeight'>cuttingHeight</a><br>
      <code>set &lt;name&gt; cuttingHeight &lt;1..9&gt;</code><br>
      Sets the cutting height. NOTE: Do not use for 550 EPOS and Ceora.</li>

    <li><a id='AutomowerConnect-set-getNewAccessToken'>getNewAccessToken</a><br>
      <code>set &lt;name&gt; getNewAccessToken</code><br>
      For debug purpose only.</li>

    <li><a id='AutomowerConnect-set-getUpdate'>getUpdate</a><br>
      <code>set &lt;name&gt; getUpdate</code><br>
      For debug purpose only.</li>

    <li><a id='AutomowerConnect-set-headlight'>headlight</a><br>
      <code>set &lt;name&gt; headlight &lt;ALWAYS_OFF|ALWAYS_ON|EVENIG_ONLY|EVENING_AND_NIGHT&gt;</code><br>
    </li>

    <li><a id='AutomowerConnect-set-mowerScheduleToAttribute'>mowerScheduleToAttribute</a><br>
      <code>set &lt;name&gt; mowerScheduleToAttribute</code><br>
      Writes the schedule in to the attribute <code>moverSchedule</code>.</li>

    <li><a id='AutomowerConnect-set-sendScheduleFromAttributeToMower'>sendScheduleFromAttributeToMower</a><br>
      <code>set &lt;name&gt; sendScheduleFromAttributeToMower</code><br>
      Sends the schedule to the mower. NOTE: Do not use for 550 EPOS and Ceora.</li>

    <li><a id='AutomowerConnect-set-mapZonesTemplateToAttribute'>mapZonesTemplateToAttribute</a><br>
      <code>set &lt;name&gt; mapZonesTemplateToAttribute</code><br>
      Load the command reference example into the attribute mapZones.</li>

    <li><a id='AutomowerConnect-set-defaultDesignAttributesToAttribute'>defaultDesignAttributesToAttribute</a><br>
      <code>set &lt;name&gt; mapZonesTemplateToAttribute</code><br>
      Load default design attributes.</li>
    <br><br>
  </ul>
  <br>

  <a id="AutomowerConnectGet"></a>
  <b>Get</b>
  <ul>
    <li><a id='AutomowerConnect-get-html'>html</a><br>
      <code>get &lt;name&gt; html</code><br>
      Returns the mower area image as html code. For use in uiTable, TabletUI, Floorplan, readingsGroup, weblink etc.</li>

    <li><a id='AutomowerConnect-get-InternalData'>InternalData</a><br>
      <code>get &lt;name&gt; InternalData</code><br>
      Lists some device internal data</li>

    <li><a id='AutomowerConnect-get-MowerData'>MowerData</a><br>
      <code>get &lt;name&gt; MowerData</code><br>
      Lists all mower data with its hash path exept positon array. The hash path can be used for generating userReadings. The trigger is <i>connected</i>.<br>
      Example: created reading <code>serialnumber</code> with hash path <code>$hash->{helper}{mower}{attributes}{system}{serialNumber}</code><br><br>
      <code>attr &lt;name&gt; userReadings serialnumber:connected {$defs{$name}->{helper}{mower}{attributes}{system}{serialNumber}}</code></li>

    <li><a id='AutomowerConnect-get-StatisticsData'>StatisticsData</a><br>
      <code>get &lt;name&gt; StatisticsData</code><br>
      Lists statistics data with its hash path. The hash path can be used for generating userReadings. The trigger is e.g. <i>device_state: connected</i> or <i>mower_wsEvent: &lt;status-event|positions-event|settings-event&gt;</i>.</li>

    <li><a id='AutomowerConnect-get-errorCodes'>errorCodes</a><br>
      <code>get &lt;name&gt; errorCodes</code><br>
      Lists API response status codes and mower error codes</li>

    <li><a id='AutomowerConnect-get-errorStack'>errorStack</a><br>
      <code>get &lt;name&gt; errorStack</code><br>
      Lists error stack.</li>
    <br><br>
  </ul>
  <br>

  <a id="AutomowerConnectAttributes"></a>
  <b>Attributes</b>
  <ul>
    <li><a id='AutomowerConnect-attr-mapImagePath'>mapImagePath</a><br>
      <code>attr &lt;name&gt; mapImagePath &lt;path to image&gt;</code><br>
      Path of a raster image file for an area the mower path has to be drawn to.<br>
      If the image name implies the image size by containing a part which matches <code>/(\d+)x(\d+)/</code><br>
      the corresponding attribute will be set to <code>mapImageWidthHeight = '$1 $2'</code><br>
      Image name example: <code>map740x1300.webp</code></li>

    <li><a id='AutomowerConnect-attr-mapImageWidthHeight'>mapImageWidthHeight</a><br>
      <code>attr &lt;name&gt; mapImageWidthHeight &lt;width in pixel&gt;&lt;separator&gt;&lt;height in pixel&gt;</code><br>
      Width and Height in pixel of a raster image file for an area image the mower path has to be drawn to. &lt;separator&gt; is one space character.</li>

    <li><a id='AutomowerConnect-attr-mapImageZoom'>mapImageZoom</a><br>
      <code>attr &lt;name&gt; mapImageZoom &lt;zoom factor&gt;</code><br>
      Zoom of a raster image for an area the mower path has to be drawn to.</li>

    <li><a id='AutomowerConnect-attr-mapBackgroundColor'>mapBackgroundColor</a><br>
      <code>attr &lt;name&gt; mapBackgroundColor &lt;background-color&gt;</code><br>
      The value is used as background-color.</li>

    <li><a id='AutomowerConnect-attr-mapDesignAttributes'>mapDesignAttributes</a><br>
      <code>attr &lt;name&gt; mapDesignAttributes &lt;complete list of design-attributes&gt;</code><br>
      Load the list of attributes by <code>set &lt;name&gt; defaultDesignAttributesToAttribute</code> to change its values. Some default values are 
      <ul>
        <li>mower path for activity MOWING: red</li>
        <li>path in CS, activity CHARGING,PARKED_IN_CS: grey</li>
        <li>path for activity LEAVING: green</li>
        <li>path for activity GOING_HOME: blue</li>
        <li>path for interval with error (all activities with error): kind of magenta</li>
        <li>all other activities: grey</li>
      </ul>
    </li>

    <li><a id='AutomowerConnect-attr-mapImageCoordinatesToRegister'>mapImageCoordinatesToRegister</a><br>
      <code>attr &lt;name&gt; mapImageCoordinatesToRegister &lt;upper left longitude&gt;&lt;space&gt;&lt;upper left latitude&gt;&lt;line feed&gt;&lt;lower right longitude&gt;&lt;space&gt;&lt;lower right latitude&gt;</code><br>
      Upper left and lower right coordinates to register (or to fit to earth) the image. Format: linewise longitude and latitude values separated by 1 space.<br>
      The lines are splitted by (<code>/\s|\R$/</code>). Use WGS84 (GPS) coordinates in decimal degree notation.</li>

    <li><a id='AutomowerConnect-attr-mapImageCoordinatesUTM'>mapImageCoordinatesUTM</a><br>
      <code>attr &lt;name&gt; mapImageCoordinatesUTM &lt;upper left longitude&gt;&lt;space&gt;&lt;upper left latitude&gt;&lt;line feed&gt;&lt;lower right longitude&gt;&lt;space&gt;&lt;lower right latitude&gt;</code><br>
      Upper left and lower right coordinates to register (or to fit to earth) the image. Format: linewise longitude and latitude values separated by 1 space.<br>
      The lines are splitted by (<code>/\s|\R$/</code>). Use UTM coordinates in meter notation.<br>
      This attribute has to be set after the attribute mapImageCoordinatesToRegister. The values are used to calculate the scale factors and the attribute scaleToMeterXY is set accordingly.</li>

    <li><a id='AutomowerConnect-attr-showMap'>showMap</a><br>
      <code>attr &lt;name&gt; showMap &lt;<b>1</b>,0&gt;</code><br>
      Shows Map on (1 default) or not (0).</li>

   <li><a id='AutomowerConnect-attr-chargingStationCoordinates'>chargingStationCoordinates</a><br>
      <code>attr &lt;name&gt; chargingStationCoordinates &lt;longitude&gt;&lt;separator&gt;&lt;latitude&gt;</code><br>
      Longitude and latitude of the charging station. Use WGS84 (GPS) coordinates in decimal degree notation. &lt;separator&gt; is one space character</li>

    <li><a id='AutomowerConnect-attr-chargingStationImagePosition'>chargingStationImagePosition</a><br>
      <code>attr &lt;name&gt; chargingStationImagePosition &lt;<b>right</b>, bottom, left, top, center&gt;</code><br>
      Position of the charging station image relative to its coordinates.</li>

    <li><a id='AutomowerConnect-attr-mowerCuttingWidth'>mowerCuttingWidth</a><br>
      <code>attr &lt;name&gt; mowerCuttingWidth &lt;cutting width&gt;</code><br>
      mower cutting width in meter to calculate the mowed area. default: 0.24</li>

    <li><a id='AutomowerConnect-attr-mowerSchedule'>mowerSchedule</a><br>
      <code>attr &lt;name&gt; mowerSchedule &lt;schedule array&gt;</code><br>
      This attribute provides the possebility to edit the mower schedule in form of an JSON array.<br>The actual schedule can be loaded with the command <code>set &lt;name&gt; mowerScheduleToAttribute</code>. <br>The command <code>set &lt;name&gt; sendScheduleFromAttributeToMower</code> sends the schedule to the mower. The maximum of array elements is 14 and 2 each day, so every day of a week can have 2 time spans. Each array element consists of 7 unsorted day values (<code>monday</code> to <code>sunday</code>) which can be <code>true</code> or <code>false</code>, a <code>start</code> and <code>duration</code> value in minutes. Start time counts from midnight.  NOTE: Do not use for 550 EPOS and Ceora. Delete the attribute after the schedule is successfully uploaded.</li>

    <li><a id='AutomowerConnect-attr-mowingAreaLimits'>mowingAreaLimits</a><br>
      <code>attr &lt;name&gt; mowingAreaLimits &lt;positions list&gt;</code><br>
      List of position describing the area to mow. Format: linewise longitude and latitude values separated by 1 space. The lines are splitted by (<code>/\s|\R$/</code>).<br>The position values could be taken from Google Earth KML file, but whithout the altitude values.</li>

    <li><a id='AutomowerConnect-attr-propertyLimits'>propertyLimits</a><br>
      <code>attr &lt;name&gt; propertyLimits &lt;positions list&gt;</code><br>
      List of position describing the property limits. Format: linewise of longitude and latitude values separated by 1 space. The lines are splitted by (<code>/\s|\R$/</code>).The position values could be taken from <a href"https://www.geoportal.de/Anwendungen/Geoportale%20der%20L%C3%A4nder.html"></a>. For converting UTM32 meter to ETRS89 / WGS84 decimal degree you can use the BKG-Geodatenzentrum <a href"https://gdz.bkg.bund.de/koordinatentransformation">BKG-Geodatenzentrum</a>.</li>

    <li><a id='AutomowerConnect-attr-numberOfWayPointsToDisplay'>numberOfWayPointsToDisplay</a><br>
      <code>attr &lt;name&gt; numberOfWayPointsToDisplay &lt;number of way points&gt;</code><br>
      Set the number of way points stored and displayed, default and at least 5000. The way points are shifted through the dedicated stack.</li>

    <li><a id='AutomowerConnect-attr-weekdaysToResetWayPoints'>weekdaysToResetWayPoints</a><br>
      <code>attr &lt;name&gt; weekdaysToResetWayPoints &lt;any combination of weekday numbers, space or minus [0123456 -]&gt;</code><br>
      A combination of weekday numbers when the way point stack will be reset. No reset for space or minus. Default 1.</li>

     <li><a id='AutomowerConnect-attr-scaleToMeterXY'>scaleToMeterXY</a><br>
      <code>attr &lt;name&gt; scaleToMeterXY &lt;scale factor longitude&gt;&lt;seperator&gt;&lt;scale factor latitude&gt;</code><br>
      The scale factor depends from the Location on earth, so it has to be calculated for short ranges only. &lt;seperator&gt; is one space character.<br>
      Longitude: <code>(LongitudeMeter_1 - LongitudeMeter_2) / (LongitudeDegree_1 - LongitudeDegree _2)</code><br>
      Latitude: <code>(LatitudeMeter_1 - LatitudeMeter_2) / (LatitudeDegree_1 - LatitudeDegree _2)</code></li>

    <li><a id='AutomowerConnect-attr-mapZones'>mapZones</a><br>
      <code>attr &lt;name&gt; mapZones &lt;valid perl condition to separate Zones&gt;</code><br>
      Provide the zones with conditions as JSON-String:<br>
      The waypoints are accessable by the variables $longitude und $latitude.<br>
      Zones have have to be separated by conditions in alphabetical order of their names.<br>
      The last zone is determined by the remaining waypoints.<br>
      Syntactical example:<br>
      <code>
      '{<br>
        &emsp;&emsp;&emsp;&emsp;"&lt;name_1&gt;" : {<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"condition"  : "&lt;condition to separate name_1 from other zones&gt;",<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"cuttingHeight"  : "&lt;cutting height for the first zone&gt;"<br>
        &emsp;&emsp;},<br>
        &emsp;&emsp;&emsp;&emsp;"&lt;name_2&gt;" : {<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"condition"  : "&lt;condition to separate name_2 from other zones, except name_1&gt;",<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"cuttingHeight"  : "&lt;cutting height for the second zone&gt;"<br>
        &emsp;&emsp;},<br>
        &emsp;&emsp;&emsp;&emsp;"&lt;name_3&gt;" : {<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"condition"  : "&lt;condition to separate name_3 from other zones, except name_1 and name_2&gt;",<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"cuttingHeight"  : "&lt;cutting height for the third zone&gt;"<br>
        &emsp;&emsp;},<br>
        &emsp;&emsp;&emsp;&emsp;"&lt;name_n-1&gt;" : {<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"condition"  : "&lt;condition to separate name_n-1 from other zones ,except the zones already seperated&gt;",<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"cuttingHeight"  : "&lt;cutting height for the nth-1 zone&gt;"<br>
        &emsp;&emsp;},<br>
        &emsp;&emsp;&emsp;&emsp;"&lt;name n&gt;" : {<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"condition"  : "Use 'undef' because the last zone remains.",<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"cuttingHeight"  : "&lt;cutting height for the nth zone&gt;"<br>
        &emsp;&emsp;}<br>
      }'<br>
      </code><br>
      Example with two Zones and virtual lines defined by latitude 52.6484600648553, 52.64839739580418 (horizontal) and longitude 9.54799477359984 (vertikal). all way points above 52.6484600648553 or all way points above 52.64839739580418 and all way points to the right of 9.54799477359984 belong to zone 01_oben. All other way points belong to zone 02_unten.<br>
      There are different cutting heightts each zone
      <code>
      '{<br>
        &emsp;&emsp;&emsp;&emsp;"01_oben" : {<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"condition"  : "$latitude > 52.6484600648553 || $longitude > 9.54799477359984 && $latitude > 52.64839739580418",<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"cuttingHeight"  : "7"<br>
        &emsp;&emsp;},<br>
        &emsp;&emsp;&emsp;&emsp;"02_unten" : {<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"condition"  : "undef",<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"cuttingHeight"  : "3"<br>
        &emsp;&emsp;}<br>
      }'<br>
      </code></li>

    <li><a id='AutomowerConnect-attr-addPollingMinInterval'>addPollingMinInterval</a><br>
      <code>attr &lt;name&gt; addPollingMinInterval &lt;interval in seconds&gt;</code><br>
      Set minimum intervall for additional polling triggered by status-event, default 0 (no polling). Gets periodically statistics data from mower. Make sure to be within API limits (10000 calls per month).</li>

    <li><a id='AutomowerConnect-attr-addPositionPolling'>addPositionPolling</a><br>
      <code>attr &lt;name&gt; addPositionPolling &lt;[1|<b>0</b>]&gt;</code><br>
      Set position polling, default 0 (no position polling). Gets periodically position data from mower, instead from websocket. It has no effect without setting attribute addPollingMinInterval.</li>

    <li><a href="disable">disable</a></li>

    <li><a href="disabledForIntervals">disabledForIntervals</a></li>
    <br><br>
  </ul>
  <br>


  <a id="AutomowerConnectUserAttr"></a>
  <b>userattr</b><br>
  <ul>
  The following user attributes are taken into account.<br>

    <li><a id='AutomowerConnect-attr-loglevelDevIo'>loglevelDevIo</a><br>
      <code>attr &lt;name&gt; loglevelDevIo &lt;[012345]&gt;</code><br>
      Set internal deviologlevel, <a target="_blank" href="https://wiki.fhem.de/wiki/DevIo#Wichtige_Internals_zur_Konfiguration"> DevIo: Wichtige_Internals_zur_Konfiguration</a> </li>

    <li><a id='AutomowerConnect-attr-timeoutGetMower'>timeoutGetMower</a><br>
      <code>attr &lt;name&gt; timeoutGetMower &lt;[6 to 60]&gt;</code><br>
      Set timeout for API call, default 5 s. </li>

    <li><a id='AutomowerConnect-attr-timeoutApiAuth'>timeoutApiAuth</a><br>
      <code>attr &lt;name&gt; timeoutApiAuth &lt;[6 to 60]&gt;</code><br>
      Set timeout for API call, default 5 s. </li>

    <li><a id='AutomowerConnect-attr-timeoutCMD'>timeoutCMD</a><br>
      <code>attr &lt;name&gt; timeoutCMD &lt;[6 to 60]&gt;</code><br>
      Set timeout for API call, default 5 s. </li><br>
  The response time is meassured and logged if a timeout ist set to 60 s.

    <br><br>
  </ul>


  <a id="AutomowerConnectReadings"></a>
  <b>Readings</b>
  <ul>
    <li>api_MowerFound - all mower registered under the application key (client_id) </li>
    <li>api_callsThisMonth - counts monthly API calls, if attribute addPollingMinInterval is set.</li>
    <li>api_token_expires - date when session of Husqvarna Cloud expires</li>
    <li>batteryPercent - battery state of charge in percent</li>
    <li>mower_activity - current activity "UNKNOWN" | "NOT_APPLICABLE" | "MOWING" | "GOING_HOME" | "CHARGING" | "LEAVING" | "PARKED_IN_CS" | "STOPPED_IN_GARDEN"</li>
    <li>mower_commandSend - Last successfull sent command</li>
    <li>mower_commandStatus - Status of the last sent command cleared each status update</li>
    <li>mower_currentZone - Zone name with activity MOWING in the last status time stamp interval and number of way points in parenthesis.</li>
    <li>mower_wsEvent - websocket connection events (status-event, positions-event, settings-event)</li>
    <li>mower_errorCode - last error code</li>
    <li>mower_errorCodeTimestamp - last error code time stamp</li>
    <li>mower_errorDescription - error description</li>
    <li>mower_mode - current working mode "MAIN_AREA" | "SECONDARY_AREA" | "HOME" | "DEMO" | "UNKNOWN"</li>
    <li>mower_state - current status "UNKNOWN" | "NOT_APPLICABLE" | "PAUSED" | "IN_OPERATION" | "WAIT_UPDATING" | "WAIT_POWER_UP" | "RESTRICTED" | "OFF" | "STOPPED" | "ERROR" | "FATAL_ERROR" |"ERROR_AT_POWER_UP"</li>
    <li>planner_nextStart - next start time</li>
    <li>planner_restrictedReason - reason for parking NOT_APPLICABLE, NONE, WEEK_SCHEDULE, PARK_OVERRIDE, SENSOR, DAILY_LIMIT, FOTA, FROST</li>
    <li>planner_overrideAction - reason for override a planned action NOT_ACTIVE, FORCE_PARK, FORCE_MOW</li>
    <li>state - state of websocket connection</li>
    <li>device_state - status of connection FHEM to Husqvarna Cloud API and device state(e.g.  defined, authorization, authorized, connected, error, update)</li>
    <li>settings_cuttingHeight - actual cutting height from API</li>
    <li>settings_headlight - actual headlight mode from API</li>
    <li>statistics_newGeoDataSets - number of new data sets between the last two different time stamps</li>
    <li>statistics_numberOfCollisions - Number of collisions (current day/last day/all days)</li>
    <li>status_connected - state of connetion between mower and Husqvarna Cloud.</li>
    <li>status_statusTimestamp - local time of last status update</li>
    <li>status_statusTimestampDiff - time difference in seconds between the last and second last status update</li>
    <li>system_name - name of the mower</li>

  </ul>
</ul>

=end html



=begin html_DE

<a id="AutomowerConnect"></a>
<h3>AutomowerConnect</h3>
<ul>
  <u><b>FHEM-FORUM:</b></u> <a target="_blank" href="https://forum.fhem.de/index.php/topic,131661.0.html"> AutomowerConnect</a><br>
  <u><b>FHEM-Wiki:</b></u> <a target="_blank" href="https://wiki.fhem.de/wiki/AutomowerConnect"> AutomowerConnect: Wie erstellt man eine Karte des Mähbereiches?</a>
  <br><br>
  <u><b>Einleitung</b></u>
  <br><br>
  <ul>
    <li>Dieses Modul etabliert eine Kommunikation zwischen der Husqvarna Cloud and FHEM, um einen Husqvarna Automower zu steuern, der mit einem Connect Modul (SIM) ausgerüstet ist.</li>
    <li>Es arbeitet als Device für einen Mähroboter. Für jeden in der API registrierten Mähroboter ist ein extra Appilcation Key mit Application Secret zu verwenden.</li>
    <li>Der Pfad des Mähroboters wird in der Detailansicht des FHEMWEB Frontends angezeigt.</li>
    <li>Der Pfad kann mit einer beliebigen Karte hinterlegt werden.</li>
    <li>Die Karte muss als Rasterbild im webp, png oder jpg Format vorliegen.</li>
    <li>Es ist möglich alles was die API anbietet zu steuern, z.B. Mähplan,Scheinwerfer, Schnitthöhe und Aktionen wie, Start, Pause, Parken usw. </li>
    <li>Zonen können selbst definiert werden. </li>
    <li>Die Schnitthöhe kann je selbstdefinierter Zone eingestellt werden. </li>
    <li>Die Daten aus der API sind im Gerätehash gespeichert, Mit <code>{Dumper $defs{&lt;device name&gt;}}</code> in der Befehlezeile können die Daten angezeigt werden und daraus userReadings erstellt werden.</li>
  <br>
  </ul>
  <u><b>Anforderungen</b></u>
  <br><br>
  <ul>
    <li>Für den Zugriff auf die API muss eine Application angelegt werden, im <a target="_blank" href="https://developer.husqvarnagroup.cloud/docs/get-started">Husqvarna Developer Portal</a>angelegt und mit der Automower Connect API verbunden werden.</li>
    <li>Währenddessen wird ein Application Key (client_id) und ein Application Secret (client secret) bereitgestellt. Diese sind für dieses Modul zu nutzen.</li>
    <li>Das Modul nutzt Client Credentials als Granttype zur Authorisierung.</li>
  <br>
  </ul>
  <br>
  <a id="AutomowerConnectDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;device name&gt; AutomowerConnect &lt;application key&gt; [&lt;mower number&gt;]</code><br>
    Beispiel:<br>
    <code>define myMower AutomowerConnect 123456789012345678901234567890123456</code> Erstes Gerät: die Defaultmähernummer ist 0.<br>
    Es muss ein <b>client_secret</b> gesetzt werden. Es ist das Application Secret vom <a target="_blank" href="https://developer.husqvarnagroup.cloud/docs/get-started">Husqvarna Developer Portal</a>.<br>
    <code>set myMower &lt;client secret&gt;</code><br>
    <br>
  </ul>
  <br>

    <a id="AutomowerConnectSet"></a>
    <b>Set</b>
  <ul>
    <li><a id='AutomowerConnect-set-Park'>Park</a><br>
      <code>set &lt;name&gt; Park &lt;number of minutes&gt;</code><br>
      Parkt den Mäher in der Ladestation (LS) für &lt;number of minutes&gt;</li>

    <li><a id='AutomowerConnect-set-ParkUntilFurtherNotice'>ParkUntilFurtherNotice</a><br>
      <code>set &lt;name&gt; ParkUntilFurtherNotice</code><br>
      Parkt den Mäher bis auf Weiteres in der LS</li>

    <li><a id='AutomowerConnect-set-ParkUntilNextSchedule'>ParkUntilNextSchedule</a><br>
      <code>set &lt;name&gt; ParkUntilNextSchedule</code><br>
      Parkt den Mäher bis auf Weiteres in der LS und startet zum nächsten geplanten Zeitpunkt</li>

    <li><a id='AutomowerConnect-set-Pause'>Pause</a><br>
      <code>set &lt;name&gt; Pause</code><br>
      Pausiert den Mäher sofort am aktuellen Standort</li>

    <li><a id='AutomowerConnect-set-ResumeSchedule'>ResumeSchedule</a><br>
      <code>set &lt;name&gt; ResumeSchedule</code><br>
      Startet im geplanten Interval den Mäher sofort, sonst zum nächsten geplanten Zeitpunkt</li>

    <li><a id='AutomowerConnect-set-Start'>Start</a><br>
      <code>set &lt;name&gt; Start &lt;number of minutes&gt;</code><br>
      Startet sofort für &lt;number of minutes&gt;</li>

    <li><a id='AutomowerConnect-set-chargingStationPositionToAttribute'>chargingStationPositionToAttribute</a><br>
      <code>set &lt;name&gt; chargingStationPositionToAttribute</code><br>
      Setzt die berechneten Koordinaten der LS in das entsprechende Attribut.</li>

    <li><a id='AutomowerConnect-set-client_secret'>client_secret</a><br>
      <code>set &lt;name&gt; client_secret &lt;application secret&gt;</code><br>
      Setzt das erforderliche Application Secret (client secret)</li>

     <li><a id='AutomowerConnect-set-cuttingHeight'>cuttingHeight</a><br>
      <code>set &lt;name&gt; cuttingHeight &lt;1..9&gt;</code><br>
      Setzt die Schnitthöhe. HINWEIS: Nicht für 550 EPOS und Ceora geeignet.</li>

     <li><a id='AutomowerConnect-set-getNewAccessToken'>getNewAccessToken</a><br>
      <code>set &lt;name&gt; getNewAccessToken</code><br>
      Nur zur Fehlerbehebung.</li>

    <li><a id='AutomowerConnect-set-getUpdate'>getUpdate</a><br>
      <code>set &lt;name&gt; getUpdate</code><br>
      Nur zur Fehlerbehebung.</li>

     <li><a id='AutomowerConnect-set-headlight'>headlight</a><br>
      <code>set &lt;name&gt; headlight &lt;ALWAYS_OFF|ALWAYS_ON|EVENIG_ONLY|EVENING_AND_NIGHT&gt;</code><br>
      Setzt den Scheinwerfermode</li>

     <li><a id='AutomowerConnect-set-mowerScheduleToAttribute'>mowerScheduleToAttribute</a><br>
      <code>set &lt;name&gt; mowerScheduleToAttribute</code><br>
      Schreibt den Mähplan  ins Attribut <code>moverSchedule</code>.</li>

     <li><a id='AutomowerConnect-set-sendScheduleFromAttributeToMower'>sendScheduleFromAttributeToMower</a><br>
      <code>set &lt;name&gt; sendScheduleFromAttributeToMower</code><br>
      Sendet den Mähplan zum Mäher. HINWEIS: Nicht für 550 EPOS und Ceora geeignet.</li>

     <li><a id='AutomowerConnect-set-mapZonesTemplateToAttribute'>mapZonesTemplateToAttribute</a><br>
      <code>set &lt;name&gt; mapZonesTemplateToAttribute</code><br>
      Läd das Beispiel aus der Befehlsreferenz in das Attribut mapZones.</li>

     <li><a id='AutomowerConnect-set-defaultDesignAttributesToAttribute'>defaultDesignAttributesToAttribute</a><br>
      <code>set &lt;name&gt; mapZonesTemplateToAttribute</code><br>
      Läd die Standartdesignattribute.</li>
      <br>
  </ul>
  <br>

  <a id="AutomowerConnectGet"></a>
  <b>Get</b>
  <ul>
    <li><a id='AutomowerConnect-get-html'>html</a><br>
      <code>get &lt;name&gt; html </code><br>
      Gibt das Bild des Mäherbereiches html kodiert zurück, zur Verwendung in uiTable, TabletUI, Floorplan, readingsGroup, weblink usw.</li>

    <li><a id='AutomowerConnect-get-errorCodes'>errorCodes</a><br>
      <code>get &lt;name&gt; errorCodes</code><br>
      Listet die Statuscode der API-Anfrage und die Fehlercodes des Mähroboters auf.</li>

    <li><a id='AutomowerConnect-get-InternalData'>InternalData</a><br>
      <code>get &lt;name&gt; InternalData</code><br>
      Listet einige Daten des FHEM-Gerätes auf.</li>

    <li><a id='AutomowerConnect-get-MowerData'>MowerData</a><br>
      <code>get &lt;name&gt; MowerData</code><br>
      Listet alle Daten des Mähers einschließlich Hashpfad auf ausgenommen das Positonsarray. Der Hashpfad kann zur Erzeugung von userReadings genutzt werden, getriggert wird durch <i>connected</i>.<br>
      Beispiel: erzeugen des Reading <code>serialnumber</code> mit dem Hashpfad <code>$hash->{helper}{mower}{attributes}{system}{serialNumber}</code><br><br>
      <code>attr &lt;name&gt; userReadings serialnumber:connected {$defs{$name}->{helper}{mower}{attributes}{system}{serialNumber}}</code></li>

    <li><a id='AutomowerConnect-get-StatisticsData'>StatisticsData</a><br>
      <code>get &lt;name&gt; StatisticsData</code><br>
      Listet statistische Daten mit ihrem Hashpfad auf. Der Hashpfad kann zur Erzeugung von userReadings genutzt werden, getriggert wird z.B. durch <i>device_state: connected</i> oder <i>mower_wsEvent: &lt;status-event|positions-event|settings-event&gt;</i></li>

    <li><a id='AutomowerConnect-get-errorStack'>errorStack</a><br>
      <code>get &lt;name&gt; errorStack</code><br>
      Listet die gespeicherten Fehler auf.</li>
    <br>
  </ul>
  <br>

    <a id="AutomowerConnectAttributes"></a>
    <b>Attributes</b>
  <ul>
    <li><a id='AutomowerConnect-attr-mapImagePath'>mapImagePath</a><br>
      <code>attr &lt;name&gt; mapImagePath &lt;path to image&gt;</code><br>
      Pfad zur Bilddatei. Auf das Bild werden Pfad, Anfangs- u. Endpunkte gezeichnet.<br>
      Wenn der Bildname die Bildgröße impliziert indem er zu dem regulären Ausdruck <code>/(\d+)x(\d+)/</code> passt,<br>
      wird das zugehörige Attribut gesetzt <code>mapImageWidthHeight = '$1 $2'</code><br>
      Beispiel Bildname: <code>map740x1300.webp</code></li>

    <li><a id='AutomowerConnect-attr-mapImageWidthHeight'>mapImageWidthHeight</a><br>
      <code>attr &lt;name&gt; mapImageWidthHeight &lt;width in pixel&gt;&lt;separator&gt;&lt;height in pixel&gt;</code><br>
      Bildbreite in Pixel des Bildes auf das Pfad, Anfangs- u. Endpunkte gezeichnet werden. &lt;separator&gt; ist 1 Leerzeichen.</li>

    <li><a id='AutomowerConnect-attr-mapImageZoom'>mapImageZoom</a><br>
      <code>attr &lt;name&gt; mapImageZoom &lt;zoom factor&gt;</code><br>
      Zoomfaktor zur Salierung des Bildes auf das Pfad, Anfangs- u. Endpunkte gezeichnet werden. Standard: 0.5</li>

    <li><a id='AutomowerConnect-attr-mapBackgroundColor'>mapBackgroundColor</a><br>
      <code>attr &lt;name&gt; mapBackgroundColor &lt;color value&gt;</code><br>
      Der Wert wird als Hintergrungfarbe benutzt.</li>

    <li><a id='AutomowerConnect-attr-mapDesignAttributes'>mapDesignAttributes</a><br>
      <code>attr &lt;name&gt; mapDesignAttributes &lt;complete list of design-attributes&gt;</code><br>
      Lade die Attributliste mit <code>set &lt;name&gt; defaultDesignAttributesToAttribute</code> um die Werte zu ändern. Einige Vorgabewerte:
      <ul>
        <li>Pfad beim mähen, Aktivität MOWING: rot</li>
        <li>In der Ladestation, Aktivität CHARGING,PARKED_IN_CS: grau</li>
        <li>Pfad für die Aktivität LEAVING: grün</li>
        <li>Pfad für Aktivität GOING_HOME: blau</li>
        <li>Pfad eines Intervalls mit Fehler (alle Aktivitäten with error): Eine Art Magenta</li>
        <li>Pfad aller anderen Aktivitäten: grau</li>
      </ul>
    </li>

    <li><a id='AutomowerConnect-attr-mapImageCoordinatesToRegister'>mapImageCoordinatesToRegister</a><br>
      <code>attr &lt;name&gt; mapImageCoordinatesToRegister &lt;upper left longitude&gt;&lt;space&gt;&lt;upper left latitude&gt;&lt;line feed&gt;&lt;lower right longitude&gt;&lt;space&gt;&lt;lower right latitude&gt;</code><br>
      Obere linke und untere rechte Ecke der Fläche auf der Erde, die durch das Bild dargestellt wird um das Bild auf der Fläche zu registrieren (oder einzupassen).<br>
      Format: Zeilenweise Paare von Longitude- u. Latitudewerten getrennt durch 1 Leerzeichen. Die Zeilen werden aufgeteilt durch (<code>/\s|\R$/</code>).<br>
      Angabe der WGS84 (GPS) Koordinaten muss als Dezimalgrad erfolgen.</li>

    <li><a id='AutomowerConnect-attr-mapImageCoordinatesUTM'>mapImageCoordinatesUTM</a><br>
      <code>attr &lt;name&gt; mapImageCoordinatesUTM &lt;upper left longitude&gt;&lt;space&gt;&lt;upper left latitude&gt;&lt;line feed&gt;&lt;lower right longitude&gt;&lt;space&gt;&lt;lower right latitude&gt;</code><br>
      Obere linke und untere rechte Ecke der Fläche auf der Erde, die durch das Bild dargestellt wird um das Bild auf der Fläche zu registrieren (oder einzupassen).<br>
      Format: Zeilenweise Paare von Longitude- u. Latitudewerten getrennt durch 1 Leerzeichen. Die Zeilen werden aufgeteilt durch (<code>/\s|\R$/</code>).<br>
      Die Angabe der UTM Koordinaten muss als Dezimalzahl in Meter erfolgen.<br>
      Das Attribut muss nach dem Attribut mapImageCoordinatesToRegister gesetzt werden.<br>
      Dieses Attribut berechnet die Skalierungsfaktoren. Das Attribut scaleToMeterXY wird entsprechend gesetzt.</li>

    <li><a id='AutomowerConnect-attr-showMap'>showMap</a><br>
      <code>attr &lt;name&gt; showMap &lt;<b>1</b>,0&gt;</code><br>
      Zeigt die Karte an (1 default) oder nicht (0).</li>

   <li><a id='AutomowerConnect-attr-chargingStationCoordinates'>chargingStationCoordinates</a><br>
      <code>attr &lt;name&gt; chargingStationCoordinates &lt;longitude&gt;&lt;separator&gt;&lt;latitude&gt;</code><br>
      Longitude und Latitude der Ladestation als WGS84 (GPS) Koordinaten als Deimalzahl. &lt;separator&gt; ist 1 Leerzeichen.</li>

    <li><a id='AutomowerConnect-attr-chargingStationImagePosition'>chargingStationImagePosition</a><br>
      <code>attr &lt;name&gt; chargingStationImagePosition &lt;<b>right</b>, bottom, left, top, center&gt;</code><br>
      Position der Ladestation relativ zu ihren Koordinaten.</li>

    <li><a id='AutomowerConnect-attr-mowerCuttingWidth'>mowerCuttingWidth</a><br>
      <code>attr &lt;name&gt; mowerCuttingWidth &lt;cutting width&gt;</code><br>
      Schnittbreite in Meter zur Berechnung der gemähten Fläche. default: 0.24</li>

    <li><a id='AutomowerConnect-attr-mowerSchedule'>mowerSchedule</a><br>
      <code>attr &lt;name&gt; mowerSchedule &lt;schedule array&gt;</code><br>
      Dieses Attribut bietet die Möglichkeit den Mähplan zu ändern, er liegt als JSON Array vor.<br>Der aktuelleMähplan kann mit dem Befehl <code>set &lt;name&gt; mowerScheduleToAttrbute</code> ins Attribut geschrieben werden. <br>Der Befehl <code>set &lt;name&gt; sendScheduleFromAttributeToMower</code> sendet den Mähplan an den Mäher. Das Maximum der Arrayelemente beträgt 14, 2 für jeden Tag, so daß jeden Tag zwei Intervalle geplant werden können. Jedes Arrayelement besteht aus 7 unsortierten Tageswerten (<code>monday</code> bis <code>sunday</code>) die auf <code>true</code> oder <code>false</code> gesetzt werden können, einen <code>start</code> Wert und einen <code>duration</code> Wert in Minuten. Die Startzeit <code>start</code> wird von Mitternacht an gezählt.  HINWEIS: Nicht für 550 EPOS und Ceora geeignet.</li>

    <li><a id='AutomowerConnect-attr-mowingAreaLimits'>mowingAreaLimits</a><br>
      <code>attr &lt;name&gt; mowingAreaLimits &lt;positions list&gt;</code><br>
      Liste von Positionen, die den Mähbereich beschreiben. Format: Zeilenweise Paare von Longitude- u. Latitudewerten getrennt durch 1 Leerzeichen. Die Zeilen werden aufgeteilt durch (<code>/\s|\R$/</code>).<br>Die Liste der Positionen kann aus einer mit Google Earth erzeugten KML-Datei entnommen werden, aber ohne Höhenangaben.</li>

    <li><a id='AutomowerConnect-attr-propertyLimits'>propertyLimits</a><br>
      <code>attr &lt;name&gt; propertyLimits &lt;positions list&gt;</code><br>
      Liste von Positionen, um die Grundstücksgrenze zu beschreiben. Format: Zeilenweise Paare von Longitude- u. Latitudewerten getrennt durch 1 Leerzeichen. Eine Zeile wird aufgeteilt durch (<code>/\s|\R$/</code>).<br>Die genaue Position der Grenzpunkte kann man über die <a target="_blank" href="https://geoportal.de/Anwendungen/Geoportale%20der%20L%C3%A4nder.html">Geoportale der Länder</a> finden. Eine Umrechnung der UTM32 Daten in Meter nach ETRS89 in Dezimalgrad kann über das <a target="_blank" href="https://gdz.bkg.bund.de/koordinatentransformation">BKG-Geodatenzentrum</a> erfolgen.</li>

    <li><a id='AutomowerConnect-attr-numberOfWayPointsToDisplay'>numberOfWayPointsToDisplay</a><br>
      <code>attr &lt;name&gt; numberOfWayPointsToDisplay &lt;number of way points&gt;</code><br>
      Legt die Anzahl der gespeicherten und und anzuzeigenden Wegpunkte fest, Standart und Mindestwert 5000. Die Wegpunkte werden durch den zugeteilten Wegpunktspeicher geschoben.</li>

    <li><a id='AutomowerConnect-attr-weekdaysToResetWayPoints'>weekdaysToResetWayPoints</a><br>
      <code>attr &lt;name&gt; weekdaysToResetWayPoints &lt;any combination of weekday numbers, space or minus [0123456 -]&gt;</code><br>
      Eine Kombination von Wochentagnummern an denen der Wegpunktspeicher gelöscht wird. Keine Löschung bei Leer- oder Minuszeichen, Standard 1.</li>

     <li><a id='AutomowerConnect-attr-scaleToMeterXY'>scaleToMeterXY</a><br>
      <code>attr &lt;name&gt; scaleToMeterXY &lt;scale factor longitude&gt;&lt;seperator&gt;&lt;scale factor latitude&gt;</code><br>
      Der Skalierfaktor hängt vom Standort ab und muss daher für kurze Strecken berechnet werden. &lt;seperator&gt; ist 1 Leerzeichen.<br>
      Longitude: <code>(LongitudeMeter_1 - LongitudeMeter_2) / (LongitudeDegree_1 - LongitudeDegree _2)</code><br>
      Latitude: <code>(LatitudeMeter_1 - LatitudeMeter_2) / (LatitudeDegree_1 - LatitudeDegree _2)</code></li>

    <li><a id='AutomowerConnect-attr-mapZones'>mapZones</a><br>
      <code>attr &lt;name&gt; mapZones &lt;JSON string with zone names in alpabetical order and valid perl condition to seperate the zones&gt;</code><br>
      Die Wegpunkte stehen über die Perlvariablen $longitude und $latitude zur Verfügung.<br>
      Die Zonennamen und Bedingungen müssen als JSON-String angegeben werden.<br>
      Die Zonennamen müssen in alphabetischer Reihenfolge durch Bedingungen abgegrenzt werden.<br>
      Die letzte Zone ergibt sich aus den übrig gebliebenen Wegpunkten.<br>
      Syntaxbeispiel:<br>
      <code>
      '{<br>
        &emsp;&emsp;&emsp;&emsp;"&lt;name_1&gt;" : {<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"condition"  : "&lt;condition to separate name_1 from other zones&gt;",<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"cuttingHeight"  : "&lt;cutting height for the first zone&gt;"<br>
        &emsp;&emsp;},<br>
        &emsp;&emsp;&emsp;&emsp;"&lt;name_2&gt;" : {<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"condition"  : "&lt;condition to separate name_2 from other zones, except name_1&gt;",<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"cuttingHeight"  : "&lt;cutting height for the second zone&gt;"<br>
        &emsp;&emsp;},<br>
        &emsp;&emsp;&emsp;&emsp;"&lt;name_3&gt;" : {<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"condition"  : "&lt;condition to separate name_3 from other zones, except name_1 and name_2&gt;",<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"cuttingHeight"  : "&lt;cutting height for the third zone&gt;"<br>
        &emsp;&emsp;},<br>
        &emsp;&emsp;&emsp;&emsp;"&lt;name_n-1&gt;" : {<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"condition"  : "&lt;condition to separate name_n-1 from other zones ,except the zones already seperated&gt;",<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"cuttingHeight"  : "&lt;cutting height for the nth-1 zone&gt;"<br>
        &emsp;&emsp;},<br>
        &emsp;&emsp;&emsp;&emsp;"&lt;name n&gt;" : {<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"condition"  : "Use 'undef' because the last zone remains.",<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"cuttingHeight"  : "&lt;cutting height for the nth zone&gt;"<br>
        &emsp;&emsp;}<br>
      }'<br>
      </code><br>
      Beispiel mit zwei Zonen und gedachten Linien bestimmt durch die Punkte Latitude 52.6484600648553, 52.64839739580418 (horizontal) und 9.54799477359984 (vertikal). Alle Wegpunkte deren Latitude über einer horizontalen Linie mit der Latitude 52.6484600648553 liegen oder alle Wegpunkte deren Latitude über einer horizontalen Linie mit der Latitude 52.64839739580418 liegen und deren Longitude rechts von einer vertikale Linie mit der Longitude 9.54799477359984 liegen, gehören zur Zone 01_oben. Alle anderen Wegpunkte gehören zur Zone 02_unten.<br>
      In den Zonen sind unterschiedliche Schnitthöhen eingestellt.<br>

      <code>
      '{<br>
        &emsp;&emsp;&emsp;&emsp;"01_oben" : {<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"condition"  : "$latitude > 52.6484600648553 || $longitude > 9.54799477359984 && $latitude > 52.64839739580418",<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"cuttingHeight"  : "7"<br>
        &emsp;&emsp;},<br>
        &emsp;&emsp;&emsp;&emsp;"02_unten" : {<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"condition"  : "undef",<br>
          &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;"cuttingHeight"  : "3"<br>
        &emsp;&emsp;}<br>
      }'<br>
      </code></li>

    <li><a id='AutomowerConnect-attr-addPollingMinInterval'>addPollingMinInterval</a><br>
      <code>attr &lt;name&gt; addPollingMinInterval &lt;interval in seconds&gt;</code><br>
      Setzt das Mindestintervall für zusätzliches Polling der API nach einem status-event, default 0 (kein Polling). Liest periodisch zusätzlich statistische Daten vom Mäher. Es muss sichergestellt werden, das die API Begrenzung (10000 Anfragen pro Monat) eingehalten wird.</li>

    <li><a id='AutomowerConnect-attr-addPositionPolling'>addPositionPolling</a><br>
      <code>attr &lt;name&gt; addPositionPolling &lt;[1|<b>0</b>]&gt;</code><br>
      Setzt das Positionspolling, default 0 (kein Positionpolling). Liest periodisch Positiondaten des Mähers, an Stelle der über Websocket gelieferten Daten. Das Attribut ist nur wirksam, wenn durch das Attribut addPollingMinInterval das Polling eingeschaltet ist.</li>

     <li><a href="disable">disable</a></li>

     <li><a href="disabledForIntervals">disabledForIntervals</a></li>
  <br>
  </ul>
  <br>


  <a id="AutomowerConnectUserAttr"></a>
  <b>userattr</b><br>
  <ul>
  Die folgenden Benutzerattribute werden unterstützt.<br>

    <li><a id='AutomowerConnect-attr-loglevelDevIo'>loglevelDevIo</a><br>
      <code>attr &lt;name&gt; loglevelDevIo &lt;[012345]&gt;</code><br>
      Setzt das Internal deviologlevel, <a target="_blank" href="https://wiki.fhem.de/wiki/DevIo#Wichtige_Internals_zur_Konfiguration"> DevIo: Wichtige_Internals_zur_Konfiguration</a> </li>

    <li><a id='AutomowerConnect-attr-timeoutGetMower'>timeoutGetMower</a><br>
      <code>attr &lt;name&gt; timeoutGetMower &lt;[6 to 60]&gt;</code><br>
      Setzt den Timeout für das Lesen der Mäherdaten, default 5 s. </li>

    <li><a id='AutomowerConnect-attr-timeoutApiAuth'>timeoutApiAuth</a><br>
      <code>attr &lt;name&gt; timeoutApiAuth &lt;[6 to 60]&gt;</code><br>
      Setzt den Timeout für die Authentifikation, default 5 s. </li>

    <li><a id='AutomowerConnect-attr-timeoutCMD'>timeoutCMD</a><br>
      <code>attr &lt;name&gt; timeoutCMD &lt;[6 to 60]&gt;</code><br>
      Setzt den Timeout für Befehl senden, default 15 s. </li><br>
  Wird ein Timeout auf 60 s gesetzt, wird die Antwortzeit gemessen und geloggt.

    <br><br>
  </ul>


  <a id="AutomowerConnectReadings"></a>
  <b>Readings</b>
  <ul>
    <li>api_MowerFound - Alle Mähroboter, die unter dem genutzten Application Key (client_id) registriert sind.</li>
    <li>api_callsThisMonth - Zählt die im Monat erfolgten API Aufrufe, wenn das Attribut addPollingMinInterval gesetzt ist.</li>
    <li>api_token_expires - Datum wann die Session der Husqvarna Cloud abläuft</li>
    <li>batteryPercent - Batterieladung in Prozent</li>
    <li>mower_activity - aktuelle Aktivität "UNKNOWN" | "NOT_APPLICABLE" | "MOWING" | "GOING_HOME" | "CHARGING" | "LEAVING" | "PARKED_IN_CS" | "STOPPED_IN_GARDEN"</li>
    <li>mower_commandSend - Letzter erfolgreich gesendeter Befehl.</li>
    <li>mower_commandStatus - Status des letzten uebermittelten Kommandos wird duch Statusupdate zurückgesetzt.</li>
    <li>mower_currentZone - Name der Zone im aktuell abgefragten Intervall der Statuszeitstempel , in der der Mäher gemäht hat und Anzahl der Wegpunkte in der Zone in Klammern.</li>
    <li>mower_wsEvent - Events der Websocketverbindung (status-event, positions-event, settings-event)</li>
    <li>mower_errorCode - last error code</li>
    <li>mower_errorCodeTimestamp - last error code time stamp</li>
    <li>mower_errorDescription - error description</li>
    <li>mower_mode - aktueller Arbeitsmodus "MAIN_AREA" | "SECONDARY_AREA" | "HOME" | "DEMO" | "UNKNOWN"</li>
    <li>mower_state - aktueller Status "UNKNOWN" | "NOT_APPLICABLE" | "PAUSED" | "IN_OPERATION" | "WAIT_UPDATING" | "WAIT_POWER_UP" | "RESTRICTED" | "OFF" | "STOPPED" | "ERROR" | "FATAL_ERROR" |"ERROR_AT_POWER_UP"</li>
    <li>planner_nextStart - nächste Startzeit</li>
    <li>planner_restrictedReason - Grund für Parken NOT_APPLICABLE, NONE, WEEK_SCHEDULE, PARK_OVERRIDE, SENSOR, DAILY_LIMIT, FOTA, FROST</li>
    <li>planner_overrideAction -   Grund für vorrangige Aktion NOT_ACTIVE, FORCE_PARK, FORCE_MOW</li>
    <li>state - Status der Websocketverbindung der Husqvarna API.</li>
    <li>device_state - Status der Verbindung des FHEM-Gerätes zur Husqvarna Cloud API (defined, authentification, authentified, connected, error, update).</li>
    <li>settings_cuttingHeight - aktuelle Schnitthöhe aus der API</li>
    <li>settings_headlight - aktueller Scheinwerfermode aus der API</li>
    <li>statistics_newGeoDataSets - Anzahl der neuen Datensätze zwischen den letzten zwei unterschiedlichen Zeitstempeln</li>
    <li>statistics_numberOfCollisions - Anzahl der Kollisionen (laufender Tag/letzter Tag/alle Tage)</li>
    <li>status_connected - Status der Verbindung zwischen dem Automower und der Husqvarna Cloud.</li>
    <li>status_statusTimestamp - Lokalzeit des letzten Statusupdates in der API</li>
    <li>status_statusTimestampDiff - Zeitdifferenz zwischen dem letzten und vorletzten Statusupdate.</li>
    <li>system_name - Name des Automowers</li>
  </ul>
</ul>

=end html_DE
