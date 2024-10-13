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

  $hash->{DefFn}        = \&FHEM::Devices::AMConnect::Common::Define;
  $hash->{GetFn}        = \&FHEM::Devices::AMConnect::Common::Get;
  $hash->{UndefFn}      = \&FHEM::Devices::AMConnect::Common::Undefine;
  $hash->{DeleteFn}     = \&FHEM::Devices::AMConnect::Common::Delete;
  $hash->{ShutdownFn}   = \&FHEM::Devices::AMConnect::Common::Shutdown;
  $hash->{RenameFn}     = \&FHEM::Devices::AMConnect::Common::Rename;
  $hash->{FW_detailFn}  = \&FHEM::Devices::AMConnect::Common::FW_detailFn;
  # $hash->{FW_summaryFn} = \&FHEM::Devices::AMConnect::Common::FW_summaryFn;
  $hash->{ReadFn}       = \&FHEM::Devices::AMConnect::Common::wsRead; 
  $hash->{ReadyFn}      = \&FHEM::Devices::AMConnect::Common::wsReady;
  $hash->{SetFn}        = \&FHEM::Devices::AMConnect::Common::Set;
  $hash->{AttrFn}       = \&FHEM::Devices::AMConnect::Common::Attr;
  $hash->{AttrList}     = "disable:1,0 " .
                          "disabledForIntervals " .
                          "mapImagePath " .
                          "mapImageWidthHeight " .
                          "mapImageCoordinatesToRegister:textField-long " .
                          "mapImageCoordinatesUTM:textField-long " .
                          "mapImageZoom " .
                          "mapBackgroundColor " .
                          "mapDesignAttributes:textField-long " .
                          "mapZones:textField-long " .
                          "chargingStationCoordinates " .
                          "chargingStationImagePosition:left,top,right,bottom,center " .
                          "mowerCuttingWidth " .
                          "mowerPanel:textField-long,85 " .
                          "mowerSchedule:textField-long " .
                          "mowingAreaLimits:textField-long " .
                          "mowingAreaHull:textField-long " .
                          "mowerAutoSyncTime:1,0 " .
                          "propertyLimits:textField-long " .
                          "scaleToMeterXY " .
                          "showMap:1,0 " .
                          "weekdaysToResetWayPoints " .
                          "numberOfWayPointsToDisplay " .
                          "addPollingMinInterval " .
                          "addPositionPolling:1,0 " .
                          $::readingFnAttributes;

  $::data{FWEXT}{AutomowerConnect}{SCRIPT} = 'automowerconnect.js';

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
    <li>The property limits can be registered manually.</li>
    <li>The mowing area limits can be registered manually.</li>
    <li>The mowing area limits can be calculated, alternatively.</li>
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
    <br>
    <li>The module downloads third party software from external server necessary to calculate the hull of mowing area.</li>
    <br>
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

  <a id='AutomowerConnect-Hints'></a>
  <b>Hints</b>
  <ul>
    <li>The available setter, attributes, Readings and and the map depend on the mower capabilities ( cutting height, headlights, position, stay out zones, work areas ).</li>
    <br>
  </ul>

  <b>Button</b>
  <ul>
    <li><a id='AutomowerConnect-button-mowerschedule'>Mower Schedule</a><br>
      The Button <button >Mower Schedule</button> opens GUI to maintain the mower schedule..<br>
      Add/change entry: fill out the schedule fields and press <button >&plusmn;</button>.<br>
      Delete entry: unselect each weekday and press <button >&plusmn;</button>.<br>
      Reset entry: fill any time field with -- and press <button >&plusmn;</button>.</li>
  </ul>

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

    <li><a id='AutomowerConnect-set-dateTime'>dateTime</a><br>
      <code>set &lt;name&gt; dateTime &lt;timestamp / s&gt;</code><br>
      Syncronize the mower time to timestamp. The default (empty Input field) timestamp is for local time of the machine the mower is defined.</li>

    <li><a id='AutomowerConnect-set-confirmError'>confirmError</a><br>
      <code>set &lt;name&gt; confirmError</code><br>
      Testing: Confirm current error on the mower. Will only work if current error is considered confirmable by the mower. Available for models 405X, 415X, 435X AWD and 535 AWD. Also available on all Ceora, EPOS and NERA models.</li>

    <li><a id='AutomowerConnect-set-StartInWorkArea'>StartInWorkArea</a><br>
      <code>set &lt;name&gt; StartInWorkArea &lt;workAreaId|name&gt; [&lt;number of minutes&gt;]</code><br>
      Testing: Starts immediately in &lt;workAreaId|name&gt; for &lt;number of minutes&gt;.<br>
      If &lt;number of minutes&gt; is empty or 0 is selected in the widget the mower will continue forever.<br>
       Work area name must not include space.</li>

    <li><a id='AutomowerConnect-set-chargingStationPositionToAttribute'>chargingStationPositionToAttribute</a><br>
      <code>set &lt;name&gt; chargingStationPositionToAttribute</code><br>
      Sets the calculated charging station coordinates to the corresponding attributes.</li>

    <li><a id='AutomowerConnect-set-client_secret'>client_secret</a><br>
      <code>set &lt;name&gt; client_secret &lt;application secret&gt;</code><br>
      Sets the mandatory application secret (client secret)</li>

    <li><a id='AutomowerConnect-set-cuttingHeight'>cuttingHeight</a><br>
      <code>set &lt;name&gt; cuttingHeight &lt;1..9&gt;</code><br>
      Sets the cutting height. NOTE: Do not use for 550 EPOS and Ceora.</li>

    <li><a id='AutomowerConnect-set-cuttingHeightInWorkArea'>cuttingHeightInWorkArea</a><br>
      <code>set &lt;name&gt; cuttingHeightInWorkArea &lt;Id|name&gt; &lt;0..100&gt;</code><br>
      Testing: Sets the cutting height for Id or zone name from 0 to 100. Zone name must not include space and contain at least one alphabetic character.</li>

    <li><a id='AutomowerConnect-set-stayOutZone'>stayOutZone</a><br>
      <code>set &lt;name&gt; stayOutZone &lt;Id|name&gt; &lt;enable|disable&gt;</code><br>
      Testing: Enables or disables stay out zone by Id or zone name. Zone name must not include space and contain at least one alphabetic character.</li>

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
      <code>set &lt;name&gt; defaultDesignAttributesToAttribute</code><br>
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
      Lists all mower data with its hash path exept positon array. The hash path can be used for generating userReadings. The trigger is e.g. <i>device_state: connected</i> or <i>mower_wsEvent: &lt;status-event|positions-event|settings-event&gt;</i>.<br>
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
      Load the list of attributes by <code>set &lt;name&gt; defaultDesignAttributesToAttribute</code> to change its values. Design attributes with changed default values are mandatory in this attribute.<br>
      Default values:
      <ul>
      <code>
        areaLimitsColor="#ff8000"<br>
        areaLimitsLineWidth="1"<br>
        areaLimitsConnector=""<br>
        hullColor="#0066ff"<br>
        hullLineWidth="1"<br>
        hullConnector="1"<br>
        hullResolution="40"<br>
        hullCalculate="1"<br>
        hullSubtract=""<br>
        propertyLimitsColor="#33cc33"<br>
        propertyLimitsLineWidth="1"<br>
        propertyLimitsConnector="1"<br>
        errorBackgroundColor="#3d3d3d"<br>
        errorFont="14px Courier New"<br>
        errorFontColor="#ff8000"<br>
        errorPathLineColor="#ff00bf"<br>
        errorPathLineDash=""<br>
        errorPathLineWidth="2"<br>
        chargingStationPathLineColor="#999999"<br>
        chargingStationPathLineDash="6,2"<br>
        chargingStationPathLineWidth="1"<br>
        chargingStationPathDotWidth="2"<br>
        otherActivityPathLineColor="#999999"<br>
        otherActivityPathLineDash="6,2"<br>
        otherActivityPathLineWidth="1"<br>
        otherActivityPathDotWidth="2"<br>
        leavingPathLineColor="#33cc33"<br>
        leavingPathLineDash="6,2"<br>
        leavingPathLineWidth="1"<br>
        leavingPathDotWidth="2"<br>
        goingHomePathLineColor="#0099ff"<br>
        goingHomePathLineDash="6,2"<br>
        goingHomePathLineWidth="1"<br>
        goingHomePathDotWidth="2"<br>
        mowingPathDisplayStart=""<br>
        mowingPathLineColor="#ff0000"<br>
        mowingPathLineDash="6,2"<br>
        mowingPathLineWidth="1"<br>
        mowingPathDotWidth="2"<br>
        mowingPathUseDots=""<br>
        mowingPathShowCollisions=""<br>
        hideSchedulerButton=""
      </code>
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

    <li><a id='AutomowerConnect-attr-mowerAutoSyncTime'>mowerAutoSyncTime</a><br>
      <code>attr &lt;name&gt; mowerAutoSyncTime &lt;<b>0</b>,1&gt;</code><br>
      Synchronizes mower time if DST changes, on (1) or not (0 default).</li>

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
      This attribute provides the possebility to edit the mower schedule in form of an JSON array.<br>The actual schedule can be loaded with the command <code>set &lt;name&gt; mowerScheduleToAttribute</code>. <br>The command <code>set &lt;name&gt; sendScheduleFromAttributeToMower</code> sends the schedule to the mower. The maximum of array elements is 14 and 2 each day, so every day of a week can have 2 time spans. Each array element consists of 7 day values (<code>monday</code> to <code>sunday</code>) which can be <code>true</code> or <code>false</code>, a <code>start</code> and <code>duration</code> value in minutes. Start time counts from midnight.  NOTE: Do not use for 550 EPOS and Ceora. Delete the attribute after the schedule is successfully uploaded.</li>

    <li><a id='AutomowerConnect-attr-mowingAreaLimits'>mowingAreaLimits</a><br>
      <code>attr &lt;name&gt; mowingAreaLimits &lt;positions list&gt;</code><br>
      List of position describing the area to mow. Format: linewise longitude and latitude values separated by 1 space. The lines are splitted by (<code>/\s|\R$/</code>).<br>The position values could be taken from Google Earth KML file, but whithout the altitude values.</li>

    <li><a id='AutomowerConnect-attr-propertyLimits'>propertyLimits</a><br>
      <code>attr &lt;name&gt; propertyLimits &lt;positions list&gt;</code><br>
      List of position describing the property limits. Format: linewise of longitude and latitude values separated by 1 space. The lines are splitted by (<code>/\s|\R$/</code>).The position values could be taken from <a href"https://www.geoportal.de/Anwendungen/Geoportale%20der%20L%C3%A4nder.html"></a>. For converting UTM32 meter to ETRS89 / WGS84 decimal degree you can use the BKG-Geodatenzentrum <a href"https://gdz.bkg.bund.de/koordinatentransformation">BKG-Geodatenzentrum</a>.</li>

    <li><a id='AutomowerConnect-attr-numberOfWayPointsToDisplay'>numberOfWayPointsToDisplay</a><br>
      <code>attr &lt;name&gt; numberOfWayPointsToDisplay &lt;number of way points&gt;</code><br>
      Set the number of way points stored and displayed, default is 5000 at least 100. The way points are shifted through the dedicated stack.</li>

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
      These Zones are provided by the Modul and are not related to Husqvarnas work areas.<br>
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

    <li><a id='AutomowerConnect-attr-mowingAreaHull'>mowingAreaHull</a><br>
      <code>attr &lt;name&gt; mowingAreaHull &lt;use button 'mowingAreaHullToAttribute' to fill the attribute&gt;</code><br>
      Contains the calculated hull coordinates as JSON string and is set by button 'mowingAreaHullToAttribute' under the dislpayed map.<br>
      The stored hull polygon is displayed like the other limits.<br>
      Use the design attribute 'hullResolution' to change the number of fractions &#8469;<br>.
      The hull polygon is calculated when the design attribut is set to 1 <code>hullCalculate="1"</code> and there are more than 50 Points for activity MOWING.<br>
      The calculation is done only after site reload.<br>
      The calculation of hull is stopped when the attribute ist set and starts again when attribute is deleted.<br>
      The attribute <code>weekdaysToResetWayPoints</code> should be set to - and also the design attribute <code>mowingPathUseDots</code> should be set to "1" until the hull is sufficient.
      If there is a polygon in attribute, it can be changed.<br>
      The design attribute <code>hullSubtract</code> can be set to a natural number {&#8469;}, it depicts the recursion depth in which polygon points removed from way points.<br>
      This reduces spikes in border region.<br>
      <code>hullSubtract=""</code> removes the button 'Subtract Hull'.<br>
    </li>

    <li><a id='AutomowerConnect-attr-mowerPanel'>mowerPanel</a><br>
      <code>attr &lt;name&gt; mowerPanel &lt;html code&gt;</code><br>
      Shows user defined html beneath the map. usefull for a panel with shortcuts<br>
      The command attribute has to contain the mower command, without set &lt;name&gt;<br>
      <code>command="Start 210"</code> stands for <code>set &lt;name&gt; Start 210</code><br>
      A directive as comment in the first line allows positioning.<br>
      <ul>
        <li>
          &lt;!-- ON_TOP --&gt; shows html above map</li>
      </ul>
      Panel has to be enclosed by a div-tag with a mandatory HTML-attribute <code>data-amc_panel_inroom=&lt;"1"|""&gt;</code>. Panel is shown in room view, i.e. for uiTable, weblink, etc., for value  "1" and hidden for value "" look at example.<br>
      Example:<br>
      <code>
        &lt;style&gt;<br>
          .amc_panel_button {height:50px; width:150px;}<br>
          .amc_panel_div {position:relative; left:348px; top:-330px;  z-index: 2; width:150px; height:1px}<br>
        &lt;/style&gt;<br>
        &lt;div class="amc_panel_div" data-amc_panel_inroom="1" &gt;<br>
          &lt;button class="amc_panel_button" command="Start 210" &gt;Start für 3 1/2 h&lt;/button&gt;<br>
          &lt;button class="amc_panel_button" command="Pause" &gt;Pause bis auf Weiteres&lt;/button&gt;<br>
          &lt;button class="amc_panel_button" command="ResumeSchedule" &gt;Weiter nach Plan&lt;/button&gt;<br>
          &lt;button class="amc_panel_button" command="ParkUntilNextSchedule" &gt;Parken bis nächsten Termin&lt;/button&gt;<br>
          &lt;button class="amc_panel_button" command="ParkUntilNextSchedule" &gt;Parken bis auf Weiteres&lt;/button&gt;<br>
        &lt;/div&gt;<br>
      </code>
    </li>

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

    <li><a id='AutomowerConnect-attr-testing'>testing</a><br>
      <code>attr &lt;name&gt; testing 1</code><br>
     Enables commands taged as Testing</li><br>

    <br><br>
  </ul>


  <a id="AutomowerConnectEvents"></a>
  <b>additional Events</b>
  <ul>
  A List of Events generated besides readings events.<br>
  
    <li><code>&lt;device name&gt;:AUTHENTICATION ERROR</code> Error during Authentification.</li>
    <li><code>&lt;device name&gt;:MOWERAPI ERROR</code> Error while Connecting AutomowerConnect API.</li>
    <li><code>&lt;device name&gt;:WEBSOCKET ERROR</code> Error related to websocket connection.</li>
  </ul>
  <br>


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
    <li>mower_inactiveReason - They are NONE, PLANNING, SEARCHING_FOR_SATELLITES.</li>
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
    <li>third_party_library - notice about downloaded JS library. Deleting the reading has no side effects.</li>

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
    <li>Die Grundstücksgrenze kann manuell eingetragen werden.</li>
    <li>Die Die Mähflächengrenze kann manuell eingetragen werden.</li>
    <li>Alternativ kann die Mähflächengrenze berechnet werden.</li>
    <li>Es ist möglich alles was die API anbietet zu steuern, z.B. Mähplan,Scheinwerfer, Schnitthöhe und Aktionen wie, Start, Pause, Parken usw. </li>
    <li>Zonen können selbst definiert werden. </li>
    <li>Die Schnitthöhe kann je selbstdefinierter Zone eingestellt werden. </li>
    <li>Die Daten aus der API sind im Gerätehash gespeichert, Mit <code>{Dumper $defs{&lt;device name&gt;}}</code> in der Befehlezeile können die Daten angezeigt werden und daraus userReadings erstellt werden.</li>
  <br>
  </ul>
  <u><b>Anforderungen</b></u>
  <br><br>
  <ul>
    <li>Für den Zugriff auf die API muss eine Application im <a target="_blank" href="https://developer.husqvarnagroup.cloud/docs/get-started">Husqvarna Developer Portal</a> angelegt und mit der Automower Connect API verbunden werden.</li>
    <li>Währenddessen wird ein Application Key (client_id) und ein Application Secret (client secret) bereitgestellt. Diese Angaben sind im Zusammenhang mit der Definition eines Gerätes erforderlich.</li>
    <li>Das Modul nutzt Client Credentials als Granttype zur Authorisierung.</li>
    <br>
    <li>Das Modul läd Drittsoftware, die zur Berechnung der Hüllkurve des Mähbereiches erforderlich ist, von einem externem Server.</li>
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
    <code>set myMower client_secret &lt;client secret&gt;</code><br>
  </ul>
  <br>

  <a id='AutomowerConnect-Hints'></a>
  <b>Hinweise</b>
  <ul>
    <li> Die verfügbaren Setter, Attribute und Readings, so wie die Karte, werden durch die im Mähertyp vorhandenen Fähigkeiten ( cutting height, headlights, position, stay out zones, work areas ) bestimmt.</li>
    <br>
  </ul>

  <b>Button</b>
  <ul>
    <li><a id='AutomowerConnect-button-mowerschedule'>Mower Schedule</a><br>
      Über den Button <button >Mower Schedule</button> kann eine Benutzeroberfläche zur Bearbeitung des Mähplans geöffnet werden.<br>
      Eintrag zufügen/ändern: Die gewünschten Angaben eintragen und <button >&plusmn;</button> betätigen.<br>
      Eintrag löschen: Alle Wochentage abwählen und <button >&plusmn;</button> betätigen.<br>
      Eintrag zurücksetzen: Irgend ein Zeitfeld mit -- füllen und <button >&plusmn;</button> betätigen.</li>
  </ul>

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
      Startet im geplanten Intervall den Mäher sofort, sonst zum nächsten geplanten Zeitpunkt</li>

    <li><a id='AutomowerConnect-set-Start'>Start</a><br>
      <code>set &lt;name&gt; Start &lt;number of minutes&gt;</code><br>
      Startet sofort für &lt;number of minutes&gt;</li>

    <li><a id='AutomowerConnect-set-StartInWorkArea'>StartInWorkArea</a><br>
      <code>set &lt;name&gt; StartInWorkArea &lt;workAreaId|zone name&gt; [&lt;number of minutes&gt;]</code><br>
      Testing: Startet sofort in &lt;workAreaId|name&gt; für &lt;number of minutes&gt;<br>
      Wenn &lt;number of minutes&gt; nicht angegeben wird oder im Auswahlfeld 0 gewählt wird, dann wird der Mähvorgang bis auf Weiteres fortgesetzt.<br>
      Der Name der WorkArea darf keine Leerzeichen beinhalten und muss mindestens einen Buchstaben enthalten.</li>

    <li><a id='AutomowerConnect-set-chargingStationPositionToAttribute'>chargingStationPositionToAttribute</a><br>
      <code>set &lt;name&gt; chargingStationPositionToAttribute</code><br>
      Setzt die berechneten Koordinaten der LS in das entsprechende Attribut.</li>

    <li><a id='AutomowerConnect-set-client_secret'>client_secret</a><br>
      <code>set &lt;name&gt; client_secret &lt;application secret&gt;</code><br>
      Setzt das erforderliche Application Secret (client secret)</li>

     <li><a id='AutomowerConnect-set-cuttingHeight'>cuttingHeight</a><br>
      <code>set &lt;name&gt; cuttingHeight &lt;1..9&gt;</code><br>
      Setzt die Schnitthöhe. HINWEIS: Nicht für 550 EPOS und Ceora geeignet.</li>

    <li><a id='AutomowerConnect-set-cuttingHeightInWorkArea'>cuttingHeightInWorkArea</a><br>
      <code>set &lt;name&gt; cuttingHeightInWorkArea &lt;Id|name&gt; &lt;0..100&gt;</code><br>
      Testing: Setzt die Schnitthöhe für Id oder Zonennamen von 0 bis 100. Der Zonenname darf keine Leerzeichen beinhalten und muss mindestens einen Buchstaben enthalten.</li>

    <li><a id='AutomowerConnect-set-stayOutZone'>stayOutZone</a><br>
      <code>set &lt;name&gt; stayOutZone &lt;Id|name&gt; &lt;enable|disable&gt;</code><br>
      Testing: Schaltet stayOutZone ein oder aus, für die Id oder den Namen der Zone.<br>
      Der Zonenname darf keine Leerzeichen beinhalten und muss mindestens einen Buchstaben enthalten.</li>

    <li><a id='AutomowerConnect-set-dateTime'>dateTime</a><br>
      <code>set &lt;name&gt; dateTime &lt;timestamp / s&gt;</code><br>
      Synchronisiert die Zeit im Mäher. Timestamp, ist die Zeit in Sekunden seit  1. Januar 1970, 00:00 Uhr UTC unter Berücksichtigung der Zeitzone und DST.
      Der Standardwert (leeres Eingabefeld) verwendet die lokale Zeit des Rechners auf dem der Mäher definiert ist, siehe auch <a href="#AutomowerConnect-attr-mowerAutoSyncTime">mowerAutoSyncTime</a></li>

    <li><a id='AutomowerConnect-set-confirmError'>confirmError</a><br>
      <code>set &lt;name&gt; confirmError</code><br>
      Testing: Bestätigt den letzten Fehler im Mäher, wenn der Mäher es zulässt. Verfügbar für 405X, 415X, 435X AWD and 535 AWD und alle Ceora, EPOS and NERA.</li>

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
      Schreibt den Mähplan ins Attribut <code>mowerSchedule</code>.</li>

     <li><a id='AutomowerConnect-set-sendScheduleFromAttributeToMower'>sendScheduleFromAttributeToMower</a><br>
      <code>set &lt;name&gt; sendScheduleFromAttributeToMower</code><br>
      Sendet den Mähplan zum Mäher. HINWEIS: Nicht für 550 EPOS und Ceora geeignet.</li>

     <li><a id='AutomowerConnect-set-mapZonesTemplateToAttribute'>mapZonesTemplateToAttribute</a><br>
      <code>set &lt;name&gt; mapZonesTemplateToAttribute</code><br>
      Läd das Beispiel aus der Befehlsreferenz in das Attribut mapZones.</li>

     <li><a id='AutomowerConnect-set-defaultDesignAttributesToAttribute'>defaultDesignAttributesToAttribute</a><br>
      <code>set &lt;name&gt; defaultDesignAttributesToAttribute</code><br>
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
      Listet alle Daten des Mähers einschließlich Hashpfad auf, ausgenommen das Positonsarray. Der Hashpfad kann zur Erzeugung von userReadings genutzt werden, getriggert wird durch e.g. <i>device_state: connected</i> oder <i>mower_wsEvent: &lt;status-event|positions-event|settings-event&gt;</i>.<br>
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
      Lade die Attributliste mit <code>set &lt;name&gt; defaultDesignAttributesToAttribute</code> um die Werte zu ändern. Nur Designattribute mit geänderten Standartwerten müssen in diesem Attribut enthalten sein.<br>
      Vorgabe Werte:
      <ul>
      <code>
        areaLimitsColor="#ff8000"<br>
        areaLimitsLineWidth="1"<br>
        areaLimitsConnector=""<br>
        hullColor="#0066ff"<br>
        hullLineWidth="1"<br>
        hullConnector="1"<br>
        hullResolution="40"<br>
        hullCalculate="1"<br>
        hullSubtract=""<br>
        propertyLimitsColor="#33cc33"<br>
        propertyLimitsLineWidth="1"<br>
        propertyLimitsConnector="1"<br>
        errorBackgroundColor="#3d3d3d"<br>
        errorFont="14px Courier New"<br>
        errorFontColor="#ff8000"<br>
        errorPathLineColor="#ff00bf"<br>
        errorPathLineDash=""<br>
        errorPathLineWidth="2"<br>
        chargingStationPathLineColor="#999999"<br>
        chargingStationPathLineDash="6,2"<br>
        chargingStationPathLineWidth="1"<br>
        chargingStationPathDotWidth="2"<br>
        otherActivityPathLineColor="#999999"<br>
        otherActivityPathLineDash="6,2"<br>
        otherActivityPathLineWidth="1"<br>
        otherActivityPathDotWidth="2"<br>
        leavingPathLineColor="#33cc33"<br>
        leavingPathLineDash="6,2"<br>
        leavingPathLineWidth="2"<br>
        leavingPathDotWidth="2"<br>
        goingHomePathLineColor="#0099ff"<br>
        goingHomePathLineDash="6,2"<br>
        goingHomePathLineWidth="2"<br>
        goingHomePathDotWidth="2"<br>
        mowingPathDisplayStart=""<br>
        mowingPathLineColor="#ff0000"<br>
        mowingPathLineDash="6,2"<br>
        mowingPathLineWidth="1"<br>
        mowingPathDotWidth="2"<br>
        mowingPathUseDots=""<br>
        mowingPathShowCollisions=""<br>
        hideSchedulerButton=""
      </code>
      </ul>
    </li>

    <li><a id='AutomowerConnect-attr-mapImageCoordinatesToRegister'>mapImageCoordinatesToRegister</a><br>
      <code>attr &lt;name&gt; mapImageCoordinatesToRegister &lt;upper left longitude&gt;&lt;space&gt;&lt;upper left latitude&gt;&lt;line feed&gt;&lt;lower right longitude&gt;&lt;space&gt;&lt;lower right latitude&gt;</code><br>
      Obere linke und untere rechte Ecke der Fläche auf der Erde, die durch das Bild dargestellt wird, um das Bild auf der Fläche zu registrieren (oder einzupassen).<br>
      Format: Zeilenweise Paare von Longitude- u. Latitudewerten getrennt durch 1 Leerzeichen. Die Zeilen werden aufgeteilt durch (<code>/\s|\R$/</code>).<br>
      Angabe der WGS84 (GPS) Koordinaten muss als Dezimalgrad erfolgen.</li>

    <li><a id='AutomowerConnect-attr-mapImageCoordinatesUTM'>mapImageCoordinatesUTM</a><br>
      <code>attr &lt;name&gt; mapImageCoordinatesUTM &lt;upper left longitude&gt;&lt;space&gt;&lt;upper left latitude&gt;&lt;line feed&gt;&lt;lower right longitude&gt;&lt;space&gt;&lt;lower right latitude&gt;</code><br>
      Obere linke und untere rechte Ecke der Fläche auf der Erde, die durch das Bild dargestellt wird, um das Bild auf der Fläche zu registrieren (oder einzupassen).<br>
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

    <li><a id='AutomowerConnect-attr-mowerAutoSyncTime'>mowerAutoSyncTime</a><br>
      <code>attr &lt;name&gt; mowerAutoSyncTime &lt;<b>0</b>,1&gt;</code><br>
      Synchronisiert die Zeit im Mäher, bei einer Zeitumstellung, ein (1) aus (0 Standard).</li>

    <li><a id='AutomowerConnect-attr-mowerCuttingWidth'>mowerCuttingWidth</a><br>
      <code>attr &lt;name&gt; mowerCuttingWidth &lt;cutting width&gt;</code><br>
      Schnittbreite in Meter zur Berechnung der gemähten Fläche. default: 0.24</li>

    <li><a id='AutomowerConnect-attr-mowerSchedule'>mowerSchedule</a><br>
      <code>attr &lt;name&gt; mowerSchedule &lt;schedule array&gt;</code><br>
      Dieses Attribut bietet die Möglichkeit den Mähplan zu ändern, er liegt als JSON Array vor.<br>Der aktuelle Mähplan kann mit dem Befehl <code>set &lt;name&gt; mowerScheduleToAttrbute</code> ins Attribut geschrieben werden. <br>Der Befehl <code>set &lt;name&gt; sendScheduleFromAttributeToMower</code> sendet den Mähplan an den Mäher. Das Maximum der Arrayelemente beträgt 14, 2 für jeden Tag, so daß jeden Tag zwei Intervalle geplant werden können. Jedes Arrayelement besteht aus 7 Tageswerten (<code>monday</code> bis <code>sunday</code>) die auf <code>true</code> oder <code>false</code> gesetzt werden können, einen <code>start</code> Wert und einen <code>duration</code> Wert in Minuten. Die Startzeit <code>start</code> wird von Mitternacht an gezählt.  HINWEIS: Nicht für 550 EPOS und Ceora geeignet.</li>

    <li><a id='AutomowerConnect-attr-mowingAreaLimits'>mowingAreaLimits</a><br>
      <code>attr &lt;name&gt; mowingAreaLimits &lt;positions list&gt;</code><br>
      Liste von Positionen, die den Mähbereich beschreiben. Format: Zeilenweise Paare von Longitude- u. Latitudewerten getrennt durch 1 Leerzeichen. Die Zeilen werden aufgeteilt durch (<code>/\s|\R$/</code>).<br>Die Liste der Positionen kann aus einer mit Google Earth erzeugten KML-Datei entnommen werden, aber ohne Höhenangaben.</li>

    <li><a id='AutomowerConnect-attr-propertyLimits'>propertyLimits</a><br>
      <code>attr &lt;name&gt; propertyLimits &lt;positions list&gt;</code><br>
      Liste von Positionen, um die Grundstücksgrenze zu beschreiben. Format: Zeilenweise Paare von Longitude- u. Latitudewerten getrennt durch 1 Leerzeichen. Eine Zeile wird aufgeteilt durch (<code>/\s|\R$/</code>).<br>Die genaue Position der Grenzpunkte kann man über die <a target="_blank" href="https://geoportal.de/Anwendungen/Geoportale%20der%20L%C3%A4nder.html">Geoportale der Länder</a> finden. Eine Umrechnung der UTM32 Daten in Meter nach ETRS89 in Dezimalgrad kann über das <a target="_blank" href="https://gdz.bkg.bund.de/koordinatentransformation">BKG-Geodatenzentrum</a> erfolgen.</li>

    <li><a id='AutomowerConnect-attr-numberOfWayPointsToDisplay'>numberOfWayPointsToDisplay</a><br>
      <code>attr &lt;name&gt; numberOfWayPointsToDisplay &lt;number of way points&gt;</code><br>
      Legt die Anzahl der gespeicherten und und anzuzeigenden Wegpunkte fest, Standartwert ist 5000 und Mindestwert ist 100. Die Wegpunkte werden durch den zugeteilten Wegpunktspeicher geschoben.</li>

    <li><a id='AutomowerConnect-attr-weekdaysToResetWayPoints'>weekdaysToResetWayPoints</a><br>
      <code>attr &lt;name&gt; weekdaysToResetWayPoints &lt;any combination of weekday numbers, space or minus [0123456 -]&gt;</code><br>
      Eine Kombination von Wochentagnummern an denen der Wegpunktspeicher gelöscht wird. Keine Löschung bei Leer- oder Minuszeichen, Standard 1.</li>

     <li><a id='AutomowerConnect-attr-scaleToMeterXY'>scaleToMeterXY</a><br>
      <code>attr &lt;name&gt; scaleToMeterXY &lt;scale factor longitude&gt;&lt;seperator&gt;&lt;scale factor latitude&gt;</code><br>
      Der Skalierfaktor hängt vom Standort ab und muss daher für kurze Strecken berechnet werden. &lt;seperator&gt; ist 1 Leerzeichen.<br>
      Longitude: <code>(LongitudeMeter_1 - LongitudeMeter_2) / (LongitudeDegree_1 - LongitudeDegree_2)</code><br>
      Latitude: <code>(LatitudeMeter_1 - LatitudeMeter_2) / (LatitudeDegree_1 - LatitudeDegree_2)</code></li>

    <li><a id='AutomowerConnect-attr-mapZones'>mapZones</a><br>
      <code>attr &lt;name&gt; mapZones &lt;JSON string with zone names in alpabetical order and valid perl condition to seperate the zones&gt;</code><br>
      Die Zonen werden vom Modul bereit gestellt, sie stehen in keinem Zusammenhang mit Husquvarnas Work Areas<br>
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

    <li><a id='AutomowerConnect-attr-mowingAreaHull'>mowingAreaHull</a><br>
      <code>attr &lt;name&gt; mowingAreaHull &lt;use button 'mowingAreaHullToAttribute' to fill the attribute&gt;</code><br><br>
      Enthält die berechneten Hüllenkooordinaten als JSON String und wird gesetzt durch den Button 'mowingAreaHullToAttribute' unterhalb der angezeigten Karte.<br>
      Das gespeicherte Hüllenpolygon wird wie die anderen Grenzen angezeigt.<br>
      Mit dem Designattribut 'hullResolution' kann die Anzahl der Brechungen beeinflusst werden &#8469;, Default 40.<br>
      Das Hüllenpolygon wird berechnet wenn das Designattribute gesetzt ist, <code>hullCalculate="1"</code> und es mehr als 50 Wegpunkte der Aktivität MOWING gibt.<br>
      Die Berechnung wird beim Laden oder Wiederladen der Website ausgeführt.<br>
      Die Berechnung stopt wenn dieses Attribut gesetzt ist und startet wenn das Attibut gelöscht wird.<br>
      Das Attribut <code>weekdaysToResetWayPoints</code> sollte auf <code>-</code> und das Designattribut <code>mowingPathUseDots</code> sollte auf <code>"1"</code> gesetzt werden.<br>
      Befindet sich ein Polygon im Attribut, besteht die Möglichkeit das Polygon anzupassen.<br>
      Das Designattribut <code>hullSubtract</code> kann auf eine natürliche Zahl {&#8469;} gesetzt werden, die angibt in welcher Rekursionstiefe Polygonpunkte aus der Menge der Wegpunkte entfernt werden.<br>
      Das reduziert Ausreißer im Randbereich der vom Polygon umschlossenen Fläche.<br>
      Wenn <code>hullSubtract=""</code> gesetzt wird, dann wird der Button 'Subtract Hull' entfernt.<br>
    </li>

    <li><a id='AutomowerConnect-attr-mowerPanel'>mowerPanel</a><br>
      <code>attr &lt;name&gt; mowerPanel &lt;html code&gt;</code><br>
      Zeigt HTML Kode unterhalb der Karte z.B. für ein Panel mit Kurzbefehlen.<br>
      Das command Attribut beinhaltet den Mäherbefehl, ohne set &lt;name&gt;<br>
      <code>command="Start 210"</code> steht für <code>set &lt;name&gt; Start 210</code><br>
      Eine Direktive als Kommentar in der ersten Zeile erlaubt die Positionierung:<br>
      <ul>
        <li>
          &lt;!-- ON_TOP --&gt; zeigt das Panel über der Karte an.</li>
      </ul>
      Das Panel muss in einem div-Element eingebettet sein das ein HTML-Attribut <code>data-amc_panel_inroom=&lt;"1"|""&gt;</code> enthält. Das Panel wird in der Raumansicht, z.B. bei uiTable, weblink, usw., angezeigt wenn der Wert "1" ist und versteckt falls der Wert "" ist, s. Bsp.<br>
      Beispiel:<br>
      <code>
        &lt;style&gt;<br>
          .amc_panel_button {height:50px; width:150px;}<br>
          .amc_panel_div {position:relative; left:348px; top:-330px;  z-index: 2; width:150px; height:1px}<br>
        &lt;/style&gt;<br>
        &lt;div class="amc_panel_div" data-amc_panel_inroom="1" &gt;<br>
          &lt;button class="amc_panel_button" command="Start 210" &gt;Start für 3 1/2 h&lt;/button&gt;<br>
          &lt;button class="amc_panel_button" command="Pause" &gt;Pause bis auf Weiteres&lt;/button&gt;<br>
          &lt;button class="amc_panel_button" command="ResumeSchedule" &gt;Weiter nach Plan&lt;/button&gt;<br>
          &lt;button class="amc_panel_button" command="ParkUntilNextSchedule" &gt;Parken bis nächsten Termin&lt;/button&gt;<br>
          &lt;button class="amc_panel_button" command="ParkUntilNextSchedule" &gt;Parken bis auf Weiteres&lt;/button&gt;<br>
        &lt;/div&gt;<br>
      </code>
    </li>

    <li><a href="disable">disable</a></li>

    <li><a href="disabledForIntervals">disabledForIntervals</a></li>
    <br>
  </ul>


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

    <li><a id='AutomowerConnect-attr-testing'>testing</a><br>
      <code>attr &lt;name&gt; testing 1</code><br>
     Macht Befehle verfügbar, die mit Testing markiert sind.</li><br>

  </ul>


  <a id="AutomowerConnectEvents"></a>
  <b>zusätzliche Events</b>
  <ul>
  Eine Liste von Events zusätzlich zu den Readingsevents.<br>
  
    <li><code>&lt;device name&gt;:AUTHENTICATION ERROR</code> Fehler bei der Authentifizierung.</li>
    <li><code>&lt;device name&gt;:MOWERAPI ERROR</code> Fehler bei der Verbindung zur AutomowerConnect API.</li>
    <li><code>&lt;device name&gt;:WEBSOCKET ERROR</code> Fehler bei der Websocketverbindung.</li>
  </ul>
  <br>


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
    <li>mower_inactiveReason - Gründe für Inaktivität: NONE, PLANNING, SEARCHING_FOR_SATELLITES.</li>
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
    <li>third_party_library - Info, dass die JS-Bibliothek geladen wurde. Das Reading kann bedenkenlos gelöscht werden.</li>
  </ul>
</ul>

=end html_DE
