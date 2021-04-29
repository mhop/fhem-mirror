###############################################################################
#
# Developed with Kate
#
#  (c) 2018-2020 Copyright: Marko Oldenburg (fhemdevelopment at cooltux dot net)
#  All rights reserved
#
#   Special thanks goes to:
#       - Bernd (Cluni) this module is based on the logic of his script "Rollladensteuerung für HM/ROLLO inkl. Abschattung und Komfortfunktionen in Perl" (https://forum.fhem.de/index.php/topic,73964.0.html)
#       - Beta-User for many tests, many suggestions and good discussions
#       - pc1246 write english commandref
#       - FunkOdyssey commandref style
#       - sledge fix many typo in commandref
#       - many User that use with modul and report bugs
#       - Christoph (christoph.kaiser.in) Patch that expand RegEx for Window Events
#       - Julian (Loredo) expand Residents Events for new Residents functions
#       - Christoph (Christoph Morrison) for fix Commandref, many suggestions and good discussions
#
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License,or
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
# $Id$
#
###############################################################################

### Notizen
# !!!!! - Innerhalb einer Shutterschleife kein CommandAttr verwenden. Bring Fehler!!! Kommen Raumnamen in die Shutterliste !!!!!!
#

package FHEM::AutoShuttersControl;

use strict;
use warnings;
use utf8;
use FHEM::Meta;

use FHEM::Automation::ShuttersControl;
use GPUtils qw(GP_Import GP_Export);

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {
    # Import from main context
    GP_Import(
        qw(
          readingFnAttributes
          )
    );

    #-- Export to main context with different name
    GP_Export(
        qw(
          Initialize
          )
    );
}

sub Initialize {
    my $hash = shift;

## Da ich mit package arbeite müssen in die Initialize für die jeweiligen hash Fn Funktionen der Funktionsname
    #  und davor mit :: getrennt der eigentliche package Name des Modules
    $hash->{SetFn}      = \&FHEM::Automation::ShuttersControl::Set;
    $hash->{GetFn}      = \&FHEM::Automation::ShuttersControl::Get;
    $hash->{DefFn}      = \&FHEM::Automation::ShuttersControl::Define;
    $hash->{NotifyFn}   = \&FHEM::Automation::ShuttersControl::Notify;
    $hash->{UndefFn}    = \&FHEM::Automation::ShuttersControl::Undef;
    $hash->{DeleteFn}   = \&FHEM::Automation::ShuttersControl::Delete;
    $hash->{ShutdownFn} = \&FHEM::Automation::ShuttersControl::Shutdown;
    $hash->{AttrList}   =
        'ASC_tempSensor '
      . 'ASC_brightnessDriveUpDown '
      . 'ASC_autoShuttersControlMorning:on,off '
      . 'ASC_autoShuttersControlEvening:on,off '
      . 'ASC_autoShuttersControlComfort:on,off '
      . 'ASC_residentsDev '
      . 'ASC_rainSensor '
      . 'ASC_autoAstroModeMorning:REAL,CIVIL,NAUTIC,ASTRONOMIC,HORIZON '
      . 'ASC_autoAstroModeMorningHorizon:-9,-8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,6,7,8,9 '
      . 'ASC_autoAstroModeEvening:REAL,CIVIL,NAUTIC,ASTRONOMIC,HORIZON '
      . 'ASC_autoAstroModeEveningHorizon:-9,-8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,6,7,8,9 '
      . 'ASC_freezeTemp:-5,-4,-3,-2,-1,0,1,2,3,4,5 '
      . 'ASC_shuttersDriveDelay '
      . 'ASC_twilightDevice '
      . 'ASC_windSensor '
      . 'ASC_expert:1 '
      . 'ASC_blockAscDrivesAfterManual:0,1 '
      . 'ASC_debug:1 '
      . 'ASC_advDate:DeadSunday,FirstAdvent '
      . $readingFnAttributes;
    $hash->{NotifyOrderPrefix} = '51-';    # Order Nummer für NotifyFn
    $hash->{FW_detailFn} =
      \&FHEM::Automation::ShuttersControl::ShuttersInformation;
    $hash->{parseParams} = 1;

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

1;

=pod
=item device
=item summary       Module for controlling shutters depending on various conditions
=item summary_DE    Modul zur automatischen Rolladensteuerung auf Basis bestimmter Ereignisse


=begin html

<a name="AutoShuttersControl"></a>
<h3>AutoShuttersControl</h3>
<ul>
    <p>
        AutoShuttersControl (<abbr>ASC</abbr>) provides a complete automation for shutters with comprehensive
        configuration options, <abbr>e.g.</abbr> open or close shutters depending on the sunrise or sunset,
        by outdoor brightness or randomly for simulate presence.
        <br /><strong>
        So that ASC can drive the blinds on the basis of the astronomical times, it is very important to
        correctly set the location (latitude, longitude) in the device "global".</strong>
    </p>
    <p>
        After telling <abbr>ASC</abbr> which shutters should be controlled, several in-depth configuration options
        are provided. With these and in combination with a resident presence state, complex scenarios are possible:
        For example, shutters could be opened if a resident awakes from sleep and the sun is already rosen. Or if a
        closed window with shutters down is tilted, the shutters could be half opened for ventilation.
        Many more is possible.
    </p>
    <a name="AutoShuttersControlDefine"></a>
    <strong>Define</strong>
    <ul>
        <p>
            <code>define &lt;name&gt; AutoShuttersControl</code>
        </p>

        Usage:
        <p>
            <ul>
                <code>define myASControl AutoShuttersControl</code><br/>
            </ul>
        </p>
        <p>
            This creates an new AutoShuttersControl device, called <em>myASControl</em>.<br/>
            Now was the new global attribute <var>ASC</var> added to the <abbr>FHEM</abbr> installation.
            Each shutter that is to be controlled by AutoShuttersControl must now have the attribute ASC set to 1 or 2.
            The value 1 is to be used with devices whose state is given as position (i.e. ROLLO or Siro, shutters
            openend is 0, shutters closed is 100), 2 with devices whose state is given as percent closed (i.e. HomeMatic,
            shutters opened is 100, closed is 0).
        </p>
        <p>
            After setting the attributes to all devices who should be controlled, the automatic scan at the main device
            can be started for example with <br/>
            <code>set myASControl scanForShutters</code>
        </p>
    </ul>
    <br/>
    <a name="AutoShuttersControlReadings"></a>
    <strong>Readings</strong>
    <ul>
        <p>Within the ASC device:</p>
        <ul>
            <li><strong>..._nextAstroTimeEvent</strong> - Next astro event: sunrise, sunset or fixed time</li>
            <li><strong>..._PosValue</strong> - current position</li>
            <li><strong>..._lastPosValue</strong> - shutters last position</li>
            <li><strong>..._lastDelayPosValue</strong> - last specified order, will be executed with the next matching
                event
            </li>
            <li><strong>partyMode on|off</strong> - is working mode set to part?y</li>
            <li><strong>ascEnable on|off</strong> - are the associated shutters control by ASC completely?</li>
            <li><strong>controlShading on|off</strong> - are the associated shutters controlled for shading by ASC?
            </li>
            <li><strong>hardLockOut on|off</strong> - switch for preventing a global hard lock out</li>
            <li><strong>room_...</strong> - list of every found shutter for every room: room_Sleeping: Patio</li>
            <li><strong>selfDefense</strong> - state of the self defense mode</li>
            <li><strong>state</strong> - state of the ASC device: active, enabled, disabled or other state information
            </li>
            <li><strong>sunriseTimeWeHoliday on|off</strong> - state of the weekend and holiday support</li>
            <li><strong>userAttrList</strong> - ASC sets some user defined attributes (<abbr><em>userattr</em></abbr>)
                for the shutter devices. This readings shows the current state of the given user attributes to the
                shutter devices.
            </li>
        </ul>

        <p>Within the shutter devices:</p>
        <ul>
            <li><strong>ASC_Enable on|off</strong> - shutter is controlled by ASC or not</li>
            <li><strong>ASC_Time_DriveUp</strong> - if the astro mode is used, the next sunrise is shown.
                If the brightness or time mode is used, the value from <em>ASC_Time_Up_Late</em> is shown.
            </li>
            <li><strong>ASC_Time_DriveDown</strong> - if the astro mode is used, the next sunset is shown.
                If the brightness or time mode is used, the value from <em>ASC_TASC_Time_Down_Lateime_Up_Late</em> is
                shown.
            </li>
            <li><strong>ASC_ShuttersLastDrive</strong> - initiator for the last action</li>
        </ul>
    </ul>
    <br/><br/>
    <a name="AutoShuttersControlSet"></a>
    <strong>Set</strong>
    <ul>
        <li><strong>ascEnable on|off</strong> - enable or disable the global control by ASC</li>
        <li><strong>controlShading on|off</strong> - enable or disable the global shading control by ASC</li>
        <li><strong>createNewNotifyDev</strong> - re-creates the internal structure for NOTIFYDEV. Is only present if
            the
            <em>ASC_Expert</em> attribute is set to 1.
        </li>
        <li><strong>hardLockOut on|off</strong> - <li><strong>hardLockOut - on/off</strong> - Aktiviert den hardwareseitigen Aussperrschutz f&uuml;r die Rolll&auml;den, bei denen das Attributs <em>ASC_LockOut</em> entsprechend auf hard gesetzt ist. Mehr Informationen in der Beschreibung bei den Attributen f&uuml;r die Rollladenger&auml;ten.</li>
        </li>
        <li><strong>partyMode on|off</strong> - controls the global party mode for shutters. Every shutters whose
            <em>ASC_Partymode</em> attribute is set to <em>on</em>, is not longer controlled by ASC. The last saved
            working command send to the device, i.e. by a event, created by a window or presence event, will be executed
            once the party mode is disabled.
        </li>
        <li><strong>renewAllTimer</strong> - resets the sunrise and sunset timers for every associated
            shutter device and creates new internal FHEM timers.
        </li>
        <li><strong>renewTimer</strong> - resets the sunrise and sunset timers for selected shutter
            device and creates new internal FHEM timers.
        </li>
        <li><strong>scanForShutters</strong> - scans the whole FHEM installation for (new) devices whose <em>ASC</em>
            attribute is set (to 1 or 2, see above).
        </li>
        <li><strong>selfDefense on|off</strong> - controls the self defense function. This function listens for
            example on a residents device. If this device is set to <em>absent</em> and a window is still open, ASC will close
            the shutter for a rudimentary burglary protection.
        </li>
        <li><strong>shutterASCenableToggle on|off</strong> - controls if the ASC controls are shown at a associated
            shutter device.
        </li>
        <li><strong>sunriseTimeWeHoliday on|off</strong> - controls the weekend and holiday support. If enabled, the
            <em>ASC_Time_Up_WE_Holiday</em> attribute is considered.
        </li>
        <li><strong>wiggle</strong> - wiggles a device for a given value (default 5%, controlled by
            <em>ASC_WiggleValue</em>) up or down and back after a minute. Useful as a deterrence in combination with
            alarm system.
        </li>
    </ul>
    <br/><br/>
    <a name="AutoShuttersControlGet"></a>
    <strong>Get</strong>
    <ul>
        <li><strong>showNotifyDevsInformations</strong> - shows the generated <em>NOTIFYDEV</em> structure. Useful for
            debugging and only shown if the <em>ASC_expert</em> attribute is set to 1.
        </li>
    </ul>
    <br/><br/>
    <a name="AutoShuttersControlAttributes"></a>
    <strong>Attributes</strong>
    <ul>
        <p>At the global <abbr>ASC</abbr> device:</p>

        <ul>
            <a name="ASC_autoAstroModeEvening"></a>
            <li><strong>ASC_autoAstroModeEvening</strong> - REAL, CIVIL, NAUTIC, ASTRONOMIC or HORIZON</li>
            <a name="ASC_autoAstroModeEveningHorizon"></a>
            <li><strong>ASC_autoAstroModeEveningHorizon</strong> - Height above the horizon. Is only considered
                if the <em>ASC_autoAstroModeEvening</em> attribute is set to <em>HORIZON</em>. Defaults to <em>0</em>.
            </li>
            <a name="ASC_autoAstroModeMorning"></a>
            <li><strong>ASC_autoAstroModeMorning</strong> - REAL, CIVIL, NAUTIC, ASTRONOMIC or HORIZON</li>
            <a name="ASC_autoAstroModeMorningHorizon"></a>
            <li><strong>ASC_autoAstroModeMorningHorizon</strong> - Height above the horizon. Is only considered
                if the <em>ASC_autoAstroModeMorning</em> attribute is set to <em>HORIZON</em>. Defaults to <em>0</em>.
            </li>
            <a name="ASC_autoShuttersControlComfort"></a>
            <li><strong>ASC_autoShuttersControlComfort - on|off</strong> -
                Controls the comfort functions: If a three state sensor, like the <abbr>HmIP-SRH</abbr> window handle
                sensor, is installed, <abbr>ASC</abbr> will open the window if the sensor signals open position. The
                <em>ASC_ComfortOpen_Pos</em> attribute has to be set for the shutter to <em>on</em>, defaults to <em>off</em>.
            </li>
            <a name="ASC_autoShuttersControlEvening"></a>
            <li><strong>ASC_autoShuttersControlEvening - on|off</strong> - Enables the automatic control by <abbr>ASC</abbr>
                at the evenings.
            </li>
            <a name="ASC_autoShuttersControlMorning"></a>
            <li><strong>ASC_autoShuttersControlMorning - on|off</strong> - Enables the automatic control by <abbr>ASC</abbr>
                at the mornings.
            </li>
            <a name="ASC_blockAscDrivesAfterManual"></a>
            <li><strong>ASC_blockAscDrivesAfterManual 0|1</strong> - If set to <em>1</em>, <abbr>ASC</abbr> will not
                automatically control a shutter if there was an manual control to the shutter. To be considered, the
                <em>ASC_ShuttersLastDrive</em> reading has to contain the value <em>manual</em> and the shutter is in
                an unknown (i.e. not otherwise configured in <abbr>ASC</abbr>) position.
            </li>
            <a name="ASC_brightnessDriveUpDown"></a>
            <li><strong>ASC_brightnessDriveUpDown - VALUE-MORNING:VALUE-EVENING</strong> - Drive the shutters by
                brightness. <em>VALUE-MORNING</em> sets the brightness threshold for the morning. If the value is
                reached in the morning, the shutter will go up. Vice versa in the evening. This is a global setting
                and can be overwritte per device with the <em>ASC_BrightnessSensor</em> attribute (see below).
            </li>
            <a name="ASC_debug"></a>
            <li><strong>ASC_debug</strong> -
                Extendend logging for debugging purposes
            </li>
            <a name="ASC_expert"></a>
            <li><strong>ASC_expert</strong> - Switches the export mode on. Currently, if set to <em>1</em>, <em>get</em>
                and <em>set</em> will contain additional functions regarding the NOTIFYDEFs.
            </li>
            <a name="ASC_freezeTemp"></a>
            <li><strong>ASC_freezeTemp</strong> - Temperature threshold for the freeze protection. The freeze protection
                prevents the shutter to be operated by <abbr>ASC</abbr>. Last operating order will be kept.
            </li>
            <a name="ASC_advDate"></a>
            <li><strong>ASC_advDate</strong> - Advent Season, selected FirstAdvent or DeadSunday.
            </li>
            <a name="ASC_rainSensor"></a>
            <li><strong>ASC_rainSensor DEVICENAME[:READINGNAME] MAXTRIGGER[:HYSTERESE] [CLOSEDPOS]</strong> - Contains
                settings for the rain protection. <em>DEVICNAME</em> specifies a rain sensor, the optional
                <em>READINGNAME</em> the name of the reading at the <em>DEVICENAME</em>. The <em>READINGNAME</em>
                should contain the values <em>rain</em> and <em>dry</em> or a numeral rain amount. <em>MAXTRIGGER</em>
                sets the threshold for the amount of rain for when the shutter is driven to <em>CLOSEDPOS</em> as soon
                the threshold is reached. <em>HYSTERESE</em> sets a hysteresis for <em>MAXTRIGGER</em>.
            </li>
            <a name="ASC_residentsDev"></a>
            <li><strong>ASC_residentsDev DEVICENAME[:READINGNAME]</strong> - <em>DEVICENAME</em> points to a device
                for presence, e.g. of type <em>RESIDENTS</em>. <em>READINGNAME</em> points to a reading at
                <em>DEVICENAME</em> which contains a presence state, e.g. <em>rgr_Residents:state</em>. The target
                should contain values alike the <em>RESIDENTS</em> family.
            </li>
            <a name="ASC_shuttersDriveDelay"></a>
            <li><strong>ASC_shuttersDriveDelay</strong> - Maximum random drive delay in seconds for calculating
                the operating time. <em>0</em> equals to no delay.
            </li>
            <a name="ASC_tempSensor"></a>
            <li><strong>ASC_tempSensor DEVICENAME[:READINGNAME]</strong> - <em>DEVICENAME</em> points to a device
                with a temperature, <em>READINGNAME</em> to a reading located at the <em>DEVICENAME</em>, for example
                <em>OUTDOOR_TEMP:measured-temp</em>. <em>READINGNAME</em> defaults to <em>temperature</em>.
            </li>
            <a name="ASC_twilightDevice"></a>
            <li><strong>ASC_twilightDevice</strong> - points to a <em>DEVICENAME</em> containing values regarding
                the sun position. Supports currently devices of type <em>Twilight</em> or <em>Astro</em>.
            </li>
            <a name="ASC_windSensor"></a>
            <li><strong>ASC_windSensor DEVICENAME[:READINGNAME]</strong> - <em>DEVICENAME</em> points to a device
                containing a wind speed. Reads from the <em>wind</em> reading, if not otherwise specified by
                <em>READINGNAME</em>.
            </li>
        </ul>
        <br/>
        <p>At shutter devices, controlled by <abbr>ASC</abbr>:</p>
        <ul>
            <li><strong>ASC - 0|1|2</strong>
                <ul>
                    <li>0 - don't create attributes for <abbr>ASC</abbr> at the first scan and don't be controlled
                    by <abbr>ASC</abbr></li>
                    <li>1 - inverse or venetian type blind mode. Shutter is open equals to 0, shutter is closed equals
                    to 100, is controlled by <em>position</em> values.</li>
                    <li>2 - <q>HomeMatic</q> mode. Shutter is open equals to 100, shutter is closed equals to 0, is
                    controlled by <em><abbr>pct</abbr></em> values.</li>
                </ul>
            </li>
            <li><strong>ASC_Antifreeze - soft|am|pm|hard|off</strong> - Freeze protection.
                <ul>
                    <li>soft - see <em>ASC_Antifreeze_Pos</em>.</li>
                    <li>hard / <abbr>am</abbr> / <abbr>pm</abbr> - freeze protection will be active (everytime,
                    ante meridiem or post meridiem).</li>
                    <li>off - freeze protection is disabled, default value</li>
                </ul>
            </li>
            <li><strong>ASC_Antifreeze_Pos</strong> - Position to be operated if the shutter should be closed,
                but <em>ASC_Antifreeze</em> is not set to <em>off</em>. (Default: dependent on attribut<em>ASC</em> 85/15).
            </li>
            <li><strong>ASC_AutoAstroModeEvening</strong> - Can be set to <em>REAL</em>, <em>CIVIL</em>,
                <em>NAUTIC</em>, <em>ASTRONOMIC</em> or <em>HORIZON</em>. Defaults to none of those.</li>
            <li><strong>ASC_AutoAstroModeEveningHorizon</strong> - If this value is reached by the sun, a sunset is
                presumed. Is used if <em>ASC_autoAstroModeEvening</em> is set to <em>HORIZON</em>. Defaults to none.
            </li>
            <li><strong>ASC_AutoAstroModeMorning</strong> - Can be set to <em>REAL</em>, <em>CIVIL</em>,
                <em>NAUTIC</em>, <em>ASTRONOMIC</em> or <em>HORIZON</em>. Defaults to none of those.</li>
            <li><strong>ASC_AutoAstroModeMorningHorizon</strong> - If this value is reached by the sun, a sunrise is
                presumed. Is used if <em>ASC_AutoAstroModeMorning</em> is set to <em>HORIZON</em>. Defaults to none.
            </li>
            <li><strong>ASC_Shutter_IdleDetection</strong> - indicates the Reading which gives information about the running status of the roller blind, as well as secondly the value in the Reading which says that the roller blind does not run.
            </li>
            <li><strong>ASC_BlockingTime_afterManual</strong> - Time in which operations by <abbr>ASC</abbr> are blocked
                after the last manual operation in seconds. Defaults to 1200 (20 minutes).
            </li>
            <li><strong>ASC_BlockingTime_beforDayOpen</strong> - Time in which no closing operation is made by
                <abbr>ASC</abbr> after opening at the morning in seconds. Defaults to 3600 (one hour).
            </li>
            <li><strong>ASC_BlockingTime_beforNightClose</strong> - Time in which no closing operation is made by
                <abbr>ASC</abbr> before closing at the evening in seconds. Defaults to 3600 (one hour).
            </li>
            <li><strong>ASC_BrightnessSensor - DEVICE[:READING] MORNING-VALUE:EVENING-VALUE</strong> -
                Drive this shutter by brightness. <em>MORNING-VALUE</em> sets the brightness threshold for the morning.
                If the value is reached in the morning, the shutter will go up. Vice versa in the evening, specified by
                <em>EVENING-VALUE</em>. Gets the brightness from <em>DEVICE</em>, reads by default from the
                <em>brightness</em> reading, unless <em>READING</em> is specified. Defaults to <em>none</em>.
            </li>
            <li><strong>ASC_Closed_Pos</strong> - The closed position value from 0 to 100 percent in increments of 10.
                (Default: dependent on attribut<em>ASC</em> 100/0).
            </li>
            <li><strong>ASC_ComfortOpen_Pos</strong> - The comfort opening position, ranging
                from 0 to 100 percent in increments of 10. (Default: dependent on attribut<em>ASC</em> 20/80).
            </li>
            <li><strong>ASC_Down - astro|time|brightness|roommate</strong> - Drive the shutter depending on this setting:
                <ul>
                    <li>astro - drive down at sunset</li>
                    <li>time - drive at <em>ASC_Time_Down_Early</em></li>
                    <li>brightness - drive between <em>ASC_Time_Down_Early</em> and <em>ASC_Time_Down_Late</em>,
                        depending on the settings of <em>ASC_BrightnessSensor</em> (see above).</li>
                    <li>roommate - no drive by time or brightness, roommate trigger only</li>
                </ul>
                Defaults to <em>astro</em>.
            </li>
            <li><strong>ASC_DriveUpMaxDuration</strong> - Drive up duration of the shutter plus 5 seconds. Defaults
                to 60 seconds if not set.
            </li>
            <li><strong>ASC_LockOut soft|hard|off</strong> - Configures the lock out protection for the current
                shutter. Values are:
                <ul>
                    <li>soft - works if the global lock out protection <em>lockOut soft</em> is set and a sensor
                        specified by <em>ASC_WindowRec</em> is set. If the sensor is set to open, the shutter will not
                        be closed. Affects only commands issued by <abbr>ASC</abbr>.
                    </li>
                    <li>
                        hard - see soft, but <abbr>ASC</abbr> tries also to block manual issued commands by a switch.
                    </li>
                    <li>
                        off - lock out protection is disabled. Default.
                    </li>
                </ul>
            </li>
            <li><strong>ASC_LockOut_Cmd inhibit|blocked|protection</strong> - Configures the lock out command for
                <em>ASC_LockOut</em> if hard is chosen as a value. Defaults to none.
            </li>
            <li><strong>ASC_Mode_Down always|home|absent|off</strong> - When will a shutter be driven down:
                <ul>
                    <li>always - <abbr>ASC</abbr> will drive always. Default value.</li>
                    <li>off - don't drive</li>
                    <li>home / absent - considers a residents status set by <em>ASC_residentsDev</em>. If no
                    resident is configured and this attribute is set to absent, <abbr>ASC</abbr> will not
                    operate the shutter.</li>
                </ul>
            </li>
            <li><strong>ASC_Mode_Up always|home|absent|off</strong> - When will a shutter be driven up:
                <ul>
                    <li>always - <abbr>ASC</abbr> will drive always. Default value.</li>
                    <li>off - don't drive</li>
                    <li>home / absent - considers a residents status set by <em>ASC_residentsDev</em>. If no
                        resident is configured and this attribute is set to absent, <abbr>ASC</abbr> will not
                        operate the shutter.</li>
                </ul>
            </li>
            <li><strong>ASC_Open_Pos</strong> - The opening position value from 0 to 100 percent in increments of 10.
                (Default: dependent on attribut<em>ASC</em> 0/100).
            </li>
            <li><strong>ASC_Sleep_Pos</strong> - The opening position value from 0 to 100 percent in increments of 10.
                (Default: dependent on attribut<em>ASC</em> 75/25).
            </li>
            <li><strong>ASC_Partymode on|off</strong> - Party mode. If configured to on, driving orders for the
                shutter by <abbr>ASC</abbr> will be queued if <em>partyMode</em> is set to <em>on</em> at the
                global <abbr>ASC</abbr> device. Will execute the driving orders after <em>partyMode</em> is disabled.
                Defaults to off.
            </li>
            <li><strong>ASC_Pos_Reading</strong> - Points to the reading name, which contains the current
                position for the shutter in percent. Will be used for <em>set</em> at devices of unknown kind.
            </li>
            <li><strong>ASC_PrivacyDownValue_beforeNightClose</strong> - How many seconds is the privacy mode activated
                before the shutter is closed in the evening. For Brightness, in addition to the time value,
                the Brightness value must also be specified. 1800:300 means 30 min before night close or above a brightness
                value of 300. -1 is the default
                value.
            </li>
            <li><strong>ASC_PrivacyDown_Pos</strong> -
                Position in percent for privacy mode, defaults to 50.
            </li>
            <li><strong>ASC_PrivacyUpValue_beforeDayOpen</strong> - How many seconds is the privacy mode activated
                before the shutter is open in the morning. For Brightness, in addition to the time value,
                the Brightness value must also be specified. 1800:600 means 30 min before day open or above a brightness
                value of 600. -1 is the default
                value.
            </li>
            <li><strong>ASC_PrivacyUp_Pos</strong> -
                Position in percent for privacy mode, defaults to 50.
            </li>
            <li><strong>ASC_WindProtection on|off</strong> - Shutter is protected by the wind protection. Defaults
                to off.
            </li>
            <li><strong>ASC_RainProtection on|off</strong> - Shutter is protected by the rain protection. Defaults
                to off.
            </li>
            <li><strong>ASC_Roommate_Device</strong> - Comma separated list of <em>ROOMMATE</em> devices, representing
                the inhabitants of the room to which the shutter belongs. Especially useful for bedrooms. Defaults
                to none.
            </li>
            <li><strong>ASC_Roommate_Reading</strong> - Specifies a reading name to <em>ASC_Roommate_Device</em>.
                Defaults to <em>state</em>.
            </li>
            <li><strong>ASC_Self_Defense_Mode - absent/gone/off</strong> - which Residents status Self Defense should become 
                active without the window being open. (default: gone) off exclude from self defense
            </li>
            <li><strong>ASC_Self_Defense_AbsentDelay</strong> - um wie viele Sekunden soll das fahren in Selfdefense bei
                Residents absent verz&ouml;gert werden. (default: 300)
            </li>
            <li><strong>ASC_ShuttersPlace window|terrace</strong> - If set to <em>terrace</em>, and the
                residents device is set to <em>gone</em>, and <em>selfDefense</em> is activated, the shutter will
                be closed. If set to window, will not. Defaults to window.
            </li>
            <li><strong>ASC_Time_Down_Early</strong> - Will not drive before time is <em>ASC_Time_Down_Early</em>
                or later, even the sunset occurs earlier. To be set in military time. Defaults to 16:00.
            </li>
            <li><strong>ASC_Time_Down_Late</strong> - Will not drive after time is <em>ASC_Time_Down_Late</em>
                or earlier, even the sunset occurs later. To be set in military time. Defaults to 22:00.
            </li>
            <li><strong>ASC_Time_Up_Early</strong> - Will not drive before time is <em>ASC_Time_Up_Early</em>
                or earlier, even the sunrise occurs earlier. To be set in military time. Defaults to 05:00.
            </li>
            <li><strong>ASC_Time_Up_Late</strong> - Will not drive after time is <em>ASC_Time_Up_Late</em>
                or earlier, even the sunrise occurs later. To be set in military time. Defaults to 08:30.
            </li>
            <li><strong>ASC_Time_Up_WE_Holiday</strong> - Will not drive before time is <em>ASC_Time_Up_WE_Holiday</em>
                on weekends and holidays (<em>holiday2we</em> is considered). Defaults to 08:00. <strong>Warning!</strong>
                If <em>ASC_Up</em> set to <em>brightness</em>, the time for <em>ASC_Time_Up_WE_Holiday</em>
                must be earlier then <em>ASC_Time_Up_Late</em>.
            </li>
            <li><strong>ASC_Up astro|time|brightness|roommate</strong> - Drive the shutter depending on this setting:
                <ul>
                    <li>astro - drive up at sunrise</li>
                    <li>time - drive at <em>ASC_Time_Up_Early</em></li>
                    <li>brightness - drive between <em>ASC_Time_Up_Early</em> and <em>ASC_Time_Up_Late</em>,
                        depending on the settings of <em>ASC_BrightnessSensor</em> (see above).</li>
                    <li>roommate - no drive by time or brightness, roommate trigger only</li>
                </ul>
                Defaults to <em>astro</em>.
            </li>
            <li><strong>ASC_Ventilate_Pos</strong> - The opening position value for ventilation
                from 0 to 100 percent in increments of 10. (Default: dependent on attribut<em>ASC</em> 70/30).
            </li>
            <li><strong>ASC_Ventilate_Window_Open on|off</strong> - Drive to ventilation position as window is opened
                or tilted, even when the current shutter position is lower than the <em>ASC_Ventilate_Pos</em>.
                Defaults to on.
            </li>
            <li><strong>ASC_WiggleValue</strong> - How many percent should the shutter be driven if a wiggle drive
                is operated. Defaults to 5.
            </li>
            <li><strong>ASC_WindParameters THRESHOLD-ON[:THRESHOLD-OFF] [DRIVEPOSITION]</strong> -
                Threshold for when the shutter is driven to the wind protection position. Optional
                <em>THRESHOLD-OFF</em> sets the complementary value when the wind protection is disabled. Disabled
                if <em>THRESHOLD-ON</em> is set to -1. Defaults to <q>50:20 <em>ASC_Closed_Pos</em></q>.
            </li>
            <li><strong>ASC_WindowRec</strong> - WINDOWREC:[READING], Points to the window contact device, associated with the shutter.
                Defaults to none. Reading is optional
            </li>
            <li><strong>ASC_WindowRec_subType</strong> - Model type of the used <em>ASC_WindowRec</em>:
                <ul>
                    <li><strong>twostate</strong> - optical or magnetical sensors with two states: opened or closed</li>
                    <li><strong>threestate</strong> - sensors with three states: opened, tilted, closed</li>
                </ul>
                Defaults to twostate.
            </li>
            <li><strong>ASC_WindowRec_PosAfterDayClosed</strong> - open,lastManual / auf welche Position soll das Rollo nach dem schlie&szlig;en am Tag fahren. Open Position oder letzte gespeicherte manuelle Position (default: open)</li>
            <blockquote>
                <p>
                    <strong><u>Shading</u></strong>
                </p>
                <p>
                    Shading is only available if the following prerequests are met:
                <ul>
                    <li>
                        The <em>controlShading</em> reading is set to on, and there is a device
                        of type Astro or Twilight configured to <em>ASC_twilightDevice</em>, and <em>ASC_tempSensor</em>
                        is set.
                    </li>
                    <li>
                        <em>ASC_BrightnessSensor</em> is configured to any shutter device.
                    </li>
                    <li>
                        All other attributes are optional and the default value for them is used, if they are not
                        otherwise configured. Please review the settings carefully, especially the values for
                        <em>StateChange_Cloudy</em> and <em>StateChange_Sunny</em>.
                    </li>
                </ul>
                </p>
                <p>
                    The following attributes are available:
                </p>
                <ul>
                    <li><strong>ASC_Shading_InOutAzimuth</strong> - Azimuth value from which shading is to be used when shading is exceeded and shading when undershooting is required.
                        Defaults to 95:265.
                    </li>
                    <li><strong>ASC_Shading_MinMax_Elevation</strong> - Shading starts as min point of sun elevation is
                        reached and end as max point of sun elevation is reached, depending also on other sensor values. Defaults to 25.0:100.0.
                    </li>
                    <li><strong>ASC_Shading_Min_OutsideTemperature</strong> - Shading starts at this outdoor temperature,
                        depending also on other sensor values. Defaults to 18.0.
                    </li>
                    <li><strong>ASC_Shading_Mode absent|always|off|home</strong> - see <em>ASC_Mode_Down</em> above,
                        but for shading. Defaults to off.
                    </li>
                    <li><strong>ASC_Shading_Pos</strong> - Shading position in percent. (Default: dependent on attribut<em>ASC</em> 85/15)</li>
                    <li><strong>ASC_Shading_StateChange_Cloudy</strong> - Shading <strong>ends</strong> at this
                        outdoor brightness, depending also on other sensor values. Defaults to 20000.
                    </li>
                    <li><strong>ASC_Shading_StateChange_SunnyCloudy</strong> - Shading <strong>starts/stops</strong> at this
                        outdoor brightness, depending also on other sensor values. An optional parameter specifies how many successive brightness reading values should be used to average the brightness value. Defaults to 35000:20000 [3].
                    </li>
                    <li><strong>ASC_Shading_WaitingPeriod</strong> - Waiting time in seconds before additional sensor values
                        to <em>ASC_Shading_StateChange_Sunny</em> or <em>ASC_Shading_StateChange_Cloudy</em>
                        are used for shading. Defaults to 120.
                    </li>
                </ul>
            </blockquote>
        </ul>
    </ul>
    <p>
        <strong><u>AutoShuttersControl <abbr>API</abbr> description</u></strong>
    </p>
    <p>
        It's possible to access internal data of the <abbr>ASC</abbr> module by calling the <abbr>API</abbr> function.
    </p>
    <u>Data points of a shutter device, controlled by <abbr>ASC</abbr></u>
    <p>
        <pre><code>{ ascAPIget('Getter','SHUTTERS_DEVICENAME') }</code></pre>
    </p>
    <table>
        <tr>
            <th>Getter</th>
            <th>Description</th>
        </tr>
        <tr>
            <td>FreezeStatus</td>
            <td>1 = soft, 2 = daytime, 3 = hard</td>
        </tr>
        <tr>
            <td>NoDelay</td>
            <td>Was the offset handling deactivated (e.g. by operations triggered by a window event)</td>
        </tr>
        <tr>
            <td>LastDrive</td>
            <td>Reason for the last action caused by <abbr>ASC</abbr></td>
        </tr>
        <tr>
            <td>LastPos</td>
            <td>Last position of the shutter</td>
        </tr>
        <tr>
            <td>LastPosTimestamp</td>
            <td>Timestamp of the last position</td>
        </tr>
        <tr>
            <td>LastManPos</td>
            <td>Last position manually set of the shutter</td>
        </tr>
        <tr>
            <td>LastManPosTimestamp</td>
            <td>Timestamp of the last position manually set</td>
        </tr>
        <tr>
            <td>SunsetUnixTime</td>
            <td>Calculated sunset time in seconds since the <abbr>UNIX</abbr> epoche</td>
        </tr>
        <tr>
            <td>Sunset</td>
            <td>1 = operation in the evening was made, 0 = operation in the evening was not yet made</td>
        </tr>
        <tr>
            <td>SunriseUnixTime</td>
            <td>Calculated sunrise time in seconds since the <abbr>UNIX</abbr> epoche</td>
        </tr>
        <tr>
            <td>Sunrise</td>
            <td>1 = operation in the morning was made, 0 = operation in the morning was not yet made</td>
        </tr>
        <tr>
            <td>RoommatesStatus</td>
            <td>Current state of the room mate set for this shutter</td>
        </tr>
        <tr>
            <td>RoommatesLastStatus</td>
            <td>Last state of the room mate set for this shutter</td>
        </tr>
        <tr>
            <td>ShadingStatus</td>
            <td>Value of the current shading state. Can hold <em>in</em>, <em>out</em>, <em>in reserved</em> or
                <em>out reserved</em></td>
        </tr>
        <tr>
            <td>ShadingStatusTimestamp</td>
            <td>Timestamp of the last shading state</td>
        </tr>
        <tr>
            <td>IfInShading</td>
            <td>Is the shutter currently in shading (depends on the shading mode)</td>
        </tr>
        <tr>
            <td>WindProtectionStatus</td>
            <td>Current state of the wind protection. Can hold <em>protection</em> or <em>unprotection</em></td>
        </tr>
        <tr>
            <td>RainProtectionStatus</td>
            <td>Current state of the rain protection. Can hold <em>protection</em> or <em>unprotection</em></td>
        </tr>
        <tr>
            <td>DelayCmd</td>
            <td>Last operation order in the waiting queue. Set for example by the party mode</td>
        </tr>
        <tr>
            <td>Status</td>
            <td>Position of the shutter</td>
        </tr>
        <tr>
            <td>ASCenable</td>
            <td>Does <abbr>ASC</abbr> control the shutter?</td>
        </tr>
        <tr>
            <td>PrivacyDownStatus</td>
            <td>Is the shutter currently in privacyDown mode</td>
        </tr>
        <tr>
            <td>outTemp</td>
            <td>Current temperature of a configured temperature device, return -100 is no device configured</td>
        </tr>
    </table>
    </p>
    <u>&Uuml;bersicht f&uuml;r das Rollladen-Device mit Parameter&uuml;bergabe</u>
    <ul>
        <code>{ ascAPIget('Getter','ROLLODEVICENAME',VALUE) }</code><br>
    </ul>
    <table>
        <tr>
            <th>Getter</th><th>Erl&auml;uterung</th>
        </tr>
        <tr>
            <td>QueryShuttersPos</td><td>R&uuml;ckgabewert 1 bedeutet das die aktuelle Position des Rollos unterhalb der Valueposition ist. 0 oder nichts bedeutet oberhalb der Valueposition.</td>
        </tr>
    </table>
    </p>
    <u>Data points of the <abbr>ASC</abbr> device</u>
        <p>
            <code>{ ascAPIget('Getter') }</code><br>
        </p>
        <table>
            <tr>
                <th>Getter</th>
                <th>Description</th>
            </tr>
            <tr>
                <td>OutTemp</td>
                <td>Current temperature of a configured temperature device, return -100 is no device configured</td>
            </tr>
            <tr>
                <td>ResidentsStatus</td>
                <td>Current state of a configured resident device</td>
            </tr>
            <tr>
                <td>ResidentsLastStatus</td>
                <td>Last state of a configured resident device</td>
            </tr>
            <tr>
                <td>Azimuth</td>
                <td>Current azimuth of the sun</td>
            </tr>
            <tr>
                <td>Elevation</td>
                <td>Current elevation of the sun</td>
            </tr>
            <tr>
                <td>ASCenable</td>
                <td>Is <abbr>ASC</abbr> globally activated?</td>
            </tr>
        </table>
</ul>

=end html

=begin html_DE

<a name="AutoShuttersControl"></a>
<h3>AutoShuttersControl</h3>
<ul>
    <p>AutoShuttersControl (ASC) erm&ouml;glicht eine vollst&auml;ndige Automatisierung der vorhandenen Rolll&auml;den. Das Modul bietet umfangreiche Konfigurationsm&ouml;glichkeiten, um Rolll&auml;den bspw. nach Sonnenauf- und untergangszeiten, nach Helligkeitswerten oder rein zeitgesteuert zu steuern.
    <br /><strong>Damit ASC auf Basis der astronomischen Zeiten die Rollos fahren kann, ist es ganz wichtig im Device "global" die Location (Latitude,Longitude) korrekt zu setzen.</strong>
    </p>
    <p>
        Man kann festlegen, welche Rolll&auml;den von ASC in die Automatisierung mit aufgenommen werden sollen. Daraufhin stehen diverse Attribute zur Feinkonfiguration zur Verf&uuml;gung. So sind unter anderem komplexe L&ouml;sungen wie Fahrten in Abh&auml;ngigkeit des Bewohnerstatus einfach umsetzbar. Beispiel: Hochfahren von Rolll&auml;den, wenn der Bewohner erwacht ist und drau&szlig;en bereits die Sonne aufgegangen ist. Weiterhin ist es m&ouml;glich, dass der geschlossene Rollladen z.B. nach dem Ankippen eines Fensters in eine L&uuml;ftungsposition f&auml;hrt. Und vieles mehr.
    </p>
    <a name="AutoShuttersControlDefine"></a>
    <strong>Define</strong>
    <ul>
        <code>define &lt;name&gt; AutoShuttersControl</code>
        <br /><br />
        Beispiel:
        <ul>
            <br />
            <code>define myASControl AutoShuttersControl</code><br />
        </ul>
        <br />
        Der Befehl erstellt ein AutoShuttersControl Device mit Namen <em>myASControl</em>.<br />
        Nachdem das Device angelegt wurde, muss in allen Rolll&auml;den Devices, welche gesteuert werden sollen, das Attribut ASC mit Wert 1 oder 2 gesetzt werden.
        Dabei bedeutet 1 = "Prozent geschlossen" (z.B. ROLLO oder Siro Modul) - Rollo Oben 0, Rollo Unten 100, 2 = "Prozent ge&ouml;ffnet" (z.B. Homematic) - Rollo Oben 100, Rollo Unten 0.
        Die Voreinstellung f&uuml;r den Befehl zum prozentualen Fahren ist in beiden F&auml;llen unterschiedlich. 1="position" und 2="pct". Dies kann, soweit erforderlich, zu sp&auml;terer Zeit noch angepasst werden.
        Habt Ihr das Attribut gesetzt, k&ouml;nnt Ihr den automatischen Scan nach den Devices ansto&szlig;en.
    </ul>
    <br />
    <a name="AutoShuttersControlReadings"></a>
    <strong>Readings</strong>
    <ul>
        <u>Im ASC-Device</u>
        <ul>
            <li><strong>..._nextAstroTimeEvent</strong> - Uhrzeit des n&auml;chsten Astro-Events: Sonnenauf- oder Sonnenuntergang oder feste Zeit</li>
            <li><strong>..._PosValue</strong> - aktuelle Position des Rollladens</li>
            <li><strong>..._lastPosValue</strong> - letzte Position des Rollladens</li>
            <li><strong>..._lastDelayPosValue</strong> - letzter abgesetzter Fahrbefehl, welcher beim n&auml;chsten zul&auml;ssigen Event ausgef&uuml;hrt wird.</li>
            <li><strong>partyMode - on/off</strong> - Partymodus-Status</li>
            <li><strong>ascEnable - on/off</strong> - globale ASC Steuerung bei den Rollläden aktiv oder inaktiv</li>
            <li><strong>controlShading - on/off</strong> - globale Beschattungsfunktion aktiv oder inaktiv</li>
            <li><strong>hardLockOut - on/off</strong> - Status des hardwareseitigen Aussperrschutzes / gilt nur f&uuml;r Roll&auml;den mit dem Attribut bei denen das Attributs <em>ASC_LockOut</em> entsprechend auf hard gesetzt ist</li>
            <li><strong>room_...</strong> - Auflistung aller Rolll&auml;den, die in den jeweiligen R&auml;men gefunden wurde. Beispiel: room_Schlafzimmer: Terrasse</li>
            <li><strong>selfDefense</strong> - Selbstschutz-Status</li>
            <li><strong>state</strong> - Status des ASC-Devices: active, enabled, disabled oder weitere Statusinformationen</li>
            <li><strong>sunriseTimeWeHoliday - on/off</strong> - Status der Wochenendunterst&uuml;tzung</li>
            <li><strong>userAttrList</strong> - Das ASC-Modul verteilt an die gesteuerten Rollladen-Geräte diverse Benutzerattribute <em>(userattr)</em>. In diesem Reading kann der Status dieser Verteilung gepr&uuml;ft werden.</li>
        </ul><br />
        <u>In den Rolll&auml;den-Ger&auml;ten</u>
        <ul>
            <li><strong>ASC_Enable - on/off</strong> - wird der Rollladen &uuml;ber ASC gesteuert oder nicht</li>
            <li><strong>ASC_Time_DriveUp</strong> - Im Astro-Modus ist hier die Sonnenaufgangszeit f&uuml;r das Rollo gespeichert. Im Brightnessmodus ist hier der Zeitpunkt aus dem Attribut <em>ASC_Time_Up_Late</em> gespeichert. Im Timemodus ist hier der Zeitpunkt aus dem Attribut <em>ASC_Time_Up_Early</em> gespeichert.</li>
            <li><strong>ASC_Time_DriveDown</strong>  - Im Astro-Modus ist hier die Sonnenuntergangszeit f&uuml;r das Rollo gespeichert. Im Brightnessmodus ist hier der Zeitpunkt aus dem Attribut <em>ASC_Time_Down_Late</em> gespeichert. Im Timemodus ist hier der Zeitpunkt aus dem Attribut <em>ASC_Time_Down_Early</em> gespeichert.</li>
            <li><strong>ASC_ShuttersLastDrive</strong>  - Grund der letzten Fahrt vom Rollladen</li>
            <li><strong>ASC_ShadingMessage</strong>  - </li>
            <li><strong>ASC_Time_PrivacyDriveDown</strong>  - </li>
            <li><strong>ASC_Time_PrivacyDriveUp</strong>  - </li>
        </ul>
    </ul>
    <br /><br />
    <a name="AutoShuttersControlSet"></a>
    <strong>Set</strong>
    <ul>
        <li><strong>advDriveDown</strong> - holt bei allen Rolll&auml;den durch ASC_Adv on ausgesetzte Fahrten nach.</li>
        <li><strong>ascEnable - on/off</strong> - Aktivieren oder deaktivieren der globalen ASC Steuerung</li>
        <li><strong>controlShading - on/off</strong> - Aktiviert oder deaktiviert die globale Beschattungssteuerung</li>
        <li><strong>createNewNotifyDev</strong> - Legt die interne Struktur f&uuml;r NOTIFYDEV neu an. Diese Funktion steht nur zur Verf&uuml;gung, wenn Attribut ASC_expert auf 1 gesetzt ist.</li>
        <li><strong>hardLockOut - on/off</strong> - Aktiviert den hardwareseitigen Aussperrschutz f&uuml;r die Rolll&auml;den, bei denen das Attributs <em>ASC_LockOut</em> entsprechend auf hard gesetzt ist. Mehr Informationen in der Beschreibung bei den Attributen f&uuml;r die Rollladenger&auml;ten.</li>
        <li><strong>partyMode - on/off</strong> - Aktiviert den globalen Partymodus. Alle Rollladen-Ger&auml;ten, in welchen das Attribut <em>ASC_Partymode</em> auf <em>on</em> gesetzt ist, werden durch ASC nicht mehr gesteuert. Der letzte Schaltbefehl, der bspw. durch ein Fensterevent oder Wechsel des Bewohnerstatus an die Rolll&auml;den gesendet wurde, wird beim Deaktivieren des Partymodus ausgef&uuml;hrt</li>
        <li><strong>renewTimer</strong> - erneuert beim ausgew&auml;hlten Rollladen die Zeiten f&uuml;r Sonnenauf- und -untergang und setzt die internen Timer neu.</li>
        <li><strong>renewAllTimer</strong> - erneuert bei allen Rolll&auml;den die Zeiten f&uuml;r Sonnenauf- und -untergang und setzt die internen Timer neu.</li>
        <li><strong>scanForShutters</strong> - Durchsucht das System nach Ger&auml;tenRo mit dem Attribut <em>ASC = 1</em> oder <em>ASC = 2</em></li>
        <li><strong>selfDefense - on/off</strong> - Aktiviert bzw. deaktiviert die Selbstschutzfunktion. Beispiel: Wenn das Residents-Ger&auml;t <em>absent</em> meldet, die Selbstschutzfunktion aktiviert wurde und ein Fenster im Haus noch ge&ouml;ffnet ist, so wird an diesem Fenster der Rollladen deaktivieren dann heruntergefahren.</li>
        <li><strong>shutterASCenableToggle - on/off</strong> - Aktivieren oder deaktivieren der ASC Kontrolle beim einzelnen Rollladens</li>
        <li><strong>sunriseTimeWeHoliday - on/off</strong> - Aktiviert die Wochenendunterst&uuml;tzung und somit, ob im Rollladenger&auml;t das Attribut <em>ASC_Time_Up_WE_Holiday</em> beachtet werden soll oder nicht.</li>
        <li><strong>wiggle</strong> - bewegt einen oder mehrere Rolll&auml;den um einen definierten Wert (Default: 5%) und nach einer Minute wieder zur&uuml;ck in die Ursprungsposition. Diese Funktion k&ouml;nnte bspw. zur Abschreckung in einem Alarmsystem eingesetzt werden.</li>
    </ul>
    <br /><br />
    <a name="AutoShuttersControlGet"></a>
    <strong>Get</strong>
    <ul>
        <li><strong>showNotifyDevsInformations</strong> - zeigt eine &Uuml;bersicht der abgelegten NOTIFYDEV Struktur. Diese Funktion wird prim&auml;r f&uuml;rs Debugging genutzt. Hierzu ist das Attribut <em>ASC_expert = 1</em> zu setzen.</li>
    </ul>
    <br /><br />
    <a name="AutoShuttersControlAttributes"></a>
    <strong>Attributes</strong>
    <ul>
        <u>Im ASC-Device</u>
        <ul>
            <a name="ASC_autoAstroModeEvening"></a>
            <li><strong>ASC_autoAstroModeEvening</strong> - REAL, CIVIL, NAUTIC, ASTRONOMIC oder HORIZON</li>
            <a name="ASC_autoAstroModeEveningHorizon"></a>
            <li><strong>ASC_autoAstroModeEveningHorizon</strong> - H&ouml;he &uuml;ber dem Horizont. Wird nur ber&uuml;cksichtigt, wenn im Attribut <em>ASC_autoAstroModeEvening</em> der Wert <em>HORIZON</em> ausgew&auml;hlt wurde. (default: 0)</li>
            <a name="ASC_autoAstroModeMorning"></a>
            <li><strong>ASC_autoAstroModeMorning</strong> - REAL, CIVIL, NAUTIC, ASTRONOMIC oder HORIZON</li>
            <a name="ASC_autoAstroModeMorningHorizon"></a>
            <li><strong>ASC_autoAstroModeMorningHorizon</strong> - H&ouml;he &uuml;ber dem Horizont. Wird nur ber&uuml;cksichtigt, wenn im Attribut <em>ASC_autoAstroModeMorning</em> der Wert <em>HORIZON</em> ausgew&auml;hlt wurde. (default: 0)</li>
            <a name="ASC_autoShuttersControlComfort"></a>
            <li><strong>ASC_autoShuttersControlComfort - on/off</strong> - schaltet die Komfortfunktion an. Bedeutet, dass ein Rollladen mit einem threestate-Sensor am Fenster beim &Ouml;ffnen in eine Offenposition f&auml;hrt. Hierzu muss beim Rollladen das Attribut <em>ASC_ComfortOpen_Pos</em> entsprechend konfiguriert sein. (default: off)</li>
            <a name="ASC_autoShuttersControlEvening"></a>
            <li><strong>ASC_autoShuttersControlEvening - on/off</strong> - Aktiviert die automatische Steuerung durch das ASC-Modul am Abend.</li>
            <a name="ASC_autoShuttersControlMorning"></a>
            <li><strong>ASC_autoShuttersControlMorning - on/off</strong> - Aktiviert die automatische Steuerung durch das ASC-Modul am Morgen.</li>
            <a name="ASC_blockAscDrivesAfterManual"></a>
            <li><strong>ASC_blockAscDrivesAfterManual - 0,1</strong> - wenn dieser Wert auf 1 gesetzt ist, dann werden Rolll&auml;den vom ASC-Modul nicht mehr gesteuert, wenn zuvor manuell eingegriffen wurde. Voraussetzung hierf&uuml;r ist jedoch, dass im Reading <em>ASC_ShuttersLastDrive</em> der Status <em>manual</em> enthalten ist und sich der Rollladen auf eine unbekannte (nicht in den Attributen anderweitig konfigurierte) Position befindet.</li>
            <a name="ASC_brightnessDriveUpDown"></a>
            <li><strong>ASC_brightnessDriveUpDown - WERT-MORGENS:WERT-ABENDS</strong> - Werte bei dem Schaltbedingungen f&uuml;r Sonnenauf- und -untergang gepr&uuml;ft werden sollen. Diese globale Einstellung kann durch die WERT-MORGENS:WERT-ABENDS Einstellung von ASC_BrightnessSensor im Rollladen selbst &uuml;berschrieben werden.</li>
            <a name="ASC_debug"></a>
            <li><strong>ASC_debug</strong> - Aktiviert die erweiterte Logausgabe f&uuml;r Debugausgaben</li>
            <a name="ASC_expert"></a>
            <li><strong>ASC_expert</strong> - ist der Wert 1, so werden erweiterte Informationen bez&uuml;glich des NotifyDevs unter set und get angezeigt</li>
            <a name="ASC_freezeTemp"></a>
            <li><strong>ASC_freezeTemp</strong> - Temperatur, ab welcher der Frostschutz greifen soll und der Rollladen nicht mehr f&auml;hrt. Der letzte Fahrbefehl wird gespeichert.</li>
            <a name="ASC_advDate"></a>
            <li><strong>ASC_advDate</strong> - Adventszeit, Auswahl ab wann die Adventszeit beginnen soll.</li>
            <a name="ASC_rainSensor"></a>
            <li><strong>ASC_rainSensor - DEVICENAME[:READINGNAME] MAXTRIGGER[:HYSTERESE] [CLOSEDPOS:[WAITINGTIME]]</strong> - der Inhalt ist eine Kombination aus Devicename, Readingname, Wert ab dem getriggert werden soll, Hysterese Wert ab dem der Status Regenschutz aufgehoben werden soll und der "wegen Regen geschlossen Position", sowie der Wartezeit bis dann tats&auml;chlich die aktion ausgeführt wird.</li>
            <a name="ASC_residentsDev"></a>
            <li><strong>ASC_residentsDev - DEVICENAME[:READINGNAME]</strong> - der Inhalt ist eine Kombination aus Devicenamen und Readingnamen des Residents-Device der obersten Ebene (z.B. rgr_Residents:state)</li>
            <a name="ASC_shuttersDriveDelay"></a>
            <li><strong>ASC_shuttersDriveDelay</strong> - maximale Zufallsverz&ouml;gerung in Sekunden bei der Berechnung der Fahrzeiten. 0 bedeutet keine Verz&ouml;gerung</li>
            <a name="ASC_tempSensor"></a>
            <li><strong>ASC_tempSensor - DEVICENAME[:READINGNAME]</strong> - der Inhalt ist eine Kombination aus Device und Reading f&uuml;r die Au&szlig;entemperatur</li>
            <a name="ASC_twilightDevice"></a>
            <li><strong>ASC_twilightDevice</strong> - das Device, welches die Informationen zum Sonnenstand liefert. Wird unter anderem f&uuml;r die Beschattung verwendet.</li>
            <a name="ASC_windSensor"></a>
            <li><strong>ASC_windSensor - DEVICE[:READING]</strong> - Sensor f&uuml;r die Windgeschwindigkeit. Kombination aus Device und Reading.</li>
        </ul>
        <br />
        <br />
        <u> In den Rolll&auml;den-Ger&auml;ten</u>
        <ul>
            <li><strong>ASC - 0/1/2</strong> 0 = "kein Anlegen der Attribute beim ersten Scan bzw. keine Beachtung eines Fahrbefehles",1 = "Inverse oder Rollo - Bsp.: Rollo oben 0, Rollo unten 100 und der Befehl zum prozentualen Fahren ist position",2 = "Homematic Style - Bsp.: Rollo oben 100, Rollo unten 0 und der Befehl zum prozentualen Fahren ist pct</li>
            <li><strong>ASC_Antifreeze - soft/am/pm/hard/off</strong> - Frostschutz, wenn soft f&auml;hrt der Rollladen in die ASC_Antifreeze_Pos und wenn hard/am/pm wird gar nicht oder innerhalb der entsprechenden Tageszeit nicht gefahren (default: off)</li>
            <li><strong>ASC_Antifreeze_Pos</strong> - Position die angefahren werden soll, wenn der Fahrbefehl komplett schlie&szlig;en lautet, aber der Frostschutz aktiv ist (Default: ist abh&auml;ngig vom Attribut<em>ASC</em> 85/15) !!!Verwendung von Perlcode ist m&ouml;glich, dieser muss in {} eingeschlossen sein. R&uuml;ckgabewert muss eine positive Zahl/Dezimalzahl sein!!!</li>
            <li><strong>ASC_AutoAstroModeEvening</strong> - aktuell REAL,CIVIL,NAUTIC,ASTRONOMIC (default: none)</li>
            <li><strong>ASC_AutoAstroModeEveningHorizon</strong> - H&ouml;he &uuml;ber Horizont, wenn beim Attribut ASC_autoAstroModeEvening HORIZON ausgew&auml;hlt (default: none)</li>
            <li><strong>ASC_AutoAstroModeMorning</strong> - aktuell REAL,CIVIL,NAUTIC,ASTRONOMIC (default: none)</li>
            <li><strong>ASC_AutoAstroModeMorningHorizon</strong> - H&ouml;he &uuml;ber Horizont,a wenn beim Attribut ASC_autoAstroModeMorning HORIZON ausgew&auml;hlt (default: none)</li>
            <li><strong>ASC_BlockingTime_afterManual</strong> - wie viel Sekunden soll die Automatik nach einer manuellen Fahrt aussetzen. (default: 1200)</li>
            <li><strong>ASC_BlockingTime_beforDayOpen</strong> - wie viel Sekunden vor dem morgendlichen &ouml;ffnen soll keine schlie&szlig;en Fahrt mehr stattfinden. (default: 3600)</li>
            <li><strong>ASC_BlockingTime_beforNightClose</strong> - wie viel Sekunden vor dem n&auml;chtlichen schlie&szlig;en soll keine &ouml;ffnen Fahrt mehr stattfinden. (default: 3600)</li>
            <li><strong>ASC_BrightnessSensor - DEVICE[:READING] WERT-MORGENS:WERT-ABENDS</strong> / 'Sensorname[:brightness [400:800]]' Angaben zum Helligkeitssensor mit (Readingname, optional) f&uuml;r die Beschattung und dem Fahren der Rollladen nach brightness und den optionalen Brightnesswerten f&uuml;r Sonnenauf- und Sonnenuntergang. (default: none)</li>
            <li><strong>ASC_Down - astro/time/brightness</strong> - bei astro wird Sonnenuntergang berechnet, bei time wird der Wert aus ASC_Time_Down_Early als Fahrzeit verwendet und bei brightness muss ASC_Time_Down_Early und ASC_Time_Down_Late korrekt gesetzt werden. Der Timer l&auml;uft dann nach ASC_Time_Down_Late Zeit, es wird aber in der Zeit zwischen ASC_Time_Down_Early und ASC_Time_Down_Late geschaut, ob die als Attribut im Moduldevice hinterlegte ASC_brightnessDriveUpDown der Down Wert erreicht wurde. Wenn ja, wird der Rollladen runter gefahren (default: astro)</li>
            <ul></p>
                <strong><u>Beschreibung der besonderen Positionsattribute</u></strong>
                <li><strong>ASC_Closed_Pos</strong> - in 10 Schritten von 0 bis 100 (Default: ist abh&auml;ngig vom Attribut<em>ASC</em> 0/100)</li>
                <li><strong>ASC_Open_Pos</strong> -  in 10 Schritten von 0 bis 100 (default: ist abh&auml;ngig vom Attribut<em>ASC</em> 100/0)</li>
                <li><strong>ASC_Sleep_Pos</strong> -  in 10 Schritten von 0 bis 100 (default: ist abh&auml;ngig vom Attribut<em>ASC</em> 75/25) !!!Verwendung von Perlcode ist m&ouml;glich, dieser muss in {} eingeschlossen sein. R&uuml;ckgabewert muss eine positive Zahl/Dezimalzahl sein!!!</li>
                <li><strong>ASC_ComfortOpen_Pos</strong> - in 10 Schritten von 0 bis 100 (Default: ist abh&auml;ngig vom Attribut<em>ASC</em> 20/80) !!!Verwendung von Perlcode ist m&ouml;glich, dieser muss in {} eingeschlossen sein. R&uuml;ckgabewert muss eine positive Zahl/Dezimalzahl sein!!!</li>
                <li><strong>ASC_Shading_Pos</strong> - Position des Rollladens f&uuml;r die Beschattung (Default: ist abh&auml;ngig vom Attribut<em>ASC</em> 80/20) !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss eine positive Zahl/Dezimalzahl sein!!!</li>
                <li><strong>ASC_Ventilate_Pos</strong> -  in 10 Schritten von 0 bis 100 (default: ist abh&auml;ngig vom Attribut <em>ASC</em> 70/30) !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss eine positive Zahl/Dezimalzahl sein!!!</li>
                </p>
                <strong>In Bezug auf die Verwendung mit Lamellen gibt es folgende erg&auml;nzende Parameter</strong>.
                <ul>
                    <li>Wird die gesamte Position inklusive der Lamellen mit Hilfe einer "festen Zurdnung" angefahren, so z.B. <em>set ROLLONAME Beschattung</em> dann wird hinter dem Positionswert mittels : getrennt die "feste Zuordnung" geschrieben. Beispiel: <em>attr ROLLONAME ASC_Shading_Pos 30:Beschattung</em></li>
                    <li>Wird hingegen ein ander Command verwendet z.B. slatPct oder &auml;hnliches dann muss hinter der normalen Positionsangebe noch die Position f&uuml;r die Lamellen mit angegeb werden. Beispiel: <em>attr ROLLONAME ASC_Shading_Pos 30:75</em>. <strong>Bitte beachtet in diesem Zusammenhang auch das Attribut ASC_SlatPosCmd_SlatDevice wo mindesten die Angabe des SlatPosCMD Voraussetzung ist.</strong></li>
                </ul>
            </p></ul>
            <li><strong>ASC_Shutter_IdleDetection</strong> - <strong>READING:VALUE</strong> gibt das Reading an welches Auskunft &uuml;ber den Fahrstatus des Rollos gibt, sowie als zweites den Wert im Reading welcher aus sagt das das Rollo <strong>nicht</strong> f&auml;hrt</li>
            <li><strong>ASC_DriveUpMaxDuration</strong> - die Dauer des Hochfahrens des Rollladens plus 5 Sekunden (default: 60)</li>
            <li><strong>ASC_Drive_Delay</strong> - maximaler Wert f&uuml;r einen zuf&auml;llig ermittelte Verz&ouml;gerungswert in Sekunden bei der Berechnung der Fahrzeiten.</li>
            <li><strong>ASC_Drive_DelayStart</strong> - in Sekunden verz&ouml;gerter Wert ab welchen das Rollo gefahren werden soll.</li>
            <li><strong>ASC_LockOut - soft/hard/off</strong> - stellt entsprechend den Aussperrschutz ein. Bei global aktivem Aussperrschutz (set ASC-Device lockOut soft) und einem Fensterkontakt open bleibt dann der Rollladen oben. Dies gilt nur bei Steuerbefehlen &uuml;ber das ASC Modul. Stellt man global auf hard, wird bei entsprechender M&ouml;glichkeit versucht den Rollladen hardwareseitig zu blockieren. Dann ist auch ein Fahren &uuml;ber die Taster nicht mehr m&ouml;glich. (default: off)</li>
            <li><strong>ASC_LockOut_Cmd - inhibit/blocked/protection</strong> - set Befehl f&uuml;r das Rollladen-Device zum Hardware sperren. Dieser Befehl wird gesetzt werden, wenn man "ASC_LockOut" auf hard setzt (default: none)</li>
            <li><strong>ASC_Mode_Down - always/home/absent/off</strong> - Wann darf die Automatik steuern. immer, niemals, bei Abwesenheit des Roommate (ist kein Roommate und absent eingestellt, wird gar nicht gesteuert) (default: always)</li>
            <li><strong>ASC_Mode_Up - always/home/absent/off</strong> - Wann darf die Automatik steuern. immer, niemals, bei Abwesenheit des Roommate (ist kein Roommate und absent eingestellt, wird gar nicht gesteuert) (default: always)</li>
            <li><strong>ASC_Partymode -  on/off</strong> - schaltet den Partymodus an oder aus. Wird am ASC Device set ASC-DEVICE partyMode on geschalten, werden alle Fahrbefehle an den Rolll&auml;den, welche das Attribut auf on haben, zwischengespeichert und sp&auml;ter erst ausgef&uuml;hrt (default: off)</li>
            <li><strong>ASC_Pos_Reading</strong> - Name des Readings, welches die Position des Rollladen in Prozent an gibt; wird bei unbekannten Device Typen auch als set Befehl zum fahren verwendet</li>
            <li><strong>ASC_PrivacyUpValue_beforeDayOpen</strong> - wie viele Sekunden vor dem morgendlichen &ouml;ffnen soll der Rollladen in die Sichtschutzposition fahren, oder bei Brightness ab welchem minimum Brightnesswert soll das Rollo in die Privacy Position fahren. Bei Brightness muss zusätzlich zum Zeitwert der Brightnesswert mit angegeben werden 1800:600 bedeutet 30 min vor day open oder bei über einem Brightnesswert von 600 (default: -1)</li>
            <li><strong>ASC_PrivacyDownValue_beforeNightClose</strong> - wie viele Sekunden vor dem abendlichen schlie&szlig;en soll der Rollladen in die Sichtschutzposition fahren, oder bei Brightness ab welchem minimum Brightnesswert soll das Rollo in die Privacy Position fahren. Bei Brightness muss zusätzlich zum Zeitwert der Brightnesswert mit angegeben werden 1800:300 bedeutet 30 min vor night close oder bei unter einem Brightnesswert von 300 (default: -1)</li>
            <li><strong>ASC_PrivacyUp_Pos</strong> - Position den Rollladens f&uuml;r den morgendlichen Sichtschutz (default: 50) !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss eine positive Zahl/Dezimalzahl sein!!!</li>
            <li><strong>ASC_PrivacyDown_Pos</strong> - Position den Rollladens f&uuml;r den abendlichen Sichtschutz (default: 50) !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss eine positive Zahl/Dezimalzahl sein!!!</li>
            <li><strong>ASC_ExternalTrigger</strong> - DEVICE:READING VALUEACTIVE:VALUEINACTIVE POSACTIVE:[POSINACTIVE VALUEACTIVE2:POSACTIVE2], Beispiel: "WohnzimmerTV:state on:off 66:100" bedeutet das wenn ein "state:on" Event kommt soll das Rollo in Position 66 fahren, kommt ein "state:off" Event soll es in Position 100 fahren. Es ist m&ouml;glich die POSINACTIVE weg zu lassen dann f&auml;hrt das Rollo in LastStatus Position.</li>
            <li><strong>ASC_WindProtection - on/off</strong> - soll der Rollladen beim Windschutz beachtet werden. on=JA, off=NEIN. (default off)</li>
            <li><strong>ASC_RainProtection - on/off</strong> - soll der Rollladen beim Regenschutz beachtet werden. on=JA, off=NEIN. (default off)</li>
            <li><strong>ASC_Roommate_Device</strong> - mit Komma getrennte Namen des/der Roommate Device/s, welche den/die Bewohner des Raumes vom Rollladen wiedergibt. Es macht nur Sinn in Schlaf- oder Kinderzimmern (default: none)</li>
            <li><strong>ASC_Adv - on/off</strong> bei on wird das runterfahren des Rollos w&auml;hrend der Weihnachtszeit (1. Advent bis 6. Januar) ausgesetzt! Durch set ASCDEVICE advDriveDown werden alle ausgesetzten Fahrten nachgeholt.</li>
            <li><strong>ASC_Roommate_Reading</strong> - das Reading zum Roommate Device, welches den Status wieder gibt (default: state)</li>
            <li><strong>ASC_Self_Defense_Mode - absent/gone/off</strong> - ab welchen Residents Status soll Selfdefense aktiv werden ohne das Fenster auf sind. (default: gone)</li>
            <li><strong>ASC_Self_Defense_AbsentDelay</strong> - um wie viele Sekunden soll das fahren in Selfdefense bei Residents absent verz&ouml;gert werden. (default: 300)</li>
            <li><strong>ASC_Self_Defense_Exclude - on/off</strong> - bei on Wert wird dieser Rollladen bei aktiven Self Defense und offenen Fenster nicht runter gefahren, wenn Residents absent ist. (default: off), off bedeutet das es ausgeschlossen ist vom Self Defense</li></p>
            <ul>
                <strong><u>Beschreibung der Beschattungsfunktion</u></strong>
                </br>Damit die Beschattung Funktion hat, m&uuml;ssen folgende Anforderungen erf&uuml;llt sein.
                </br><strong>Im ASC Device</strong> das Reading "controlShading" mit dem Wert on, sowie ein Astro/Twilight Device im Attribut "ASC_twilightDevice" und das Attribut "ASC_tempSensor".
                </br><strong>In den Rollladendevices</strong> ben&ouml;tigt ihr ein Helligkeitssensor als Attribut "ASC_BrightnessSensor", sofern noch nicht vorhanden. Findet der Sensor nur f&uuml;r die Beschattung Verwendung ist der Wert DEVICENAME[:READING] ausreichend.
                </br>Alle weiteren Attribute sind optional und wenn nicht gesetzt mit Default-Werten belegt. Ihr solltet sie dennoch einmal anschauen und entsprechend Euren Gegebenheiten setzen. Die Werte f&uuml;r die Fensterposition und den Vor- Nachlaufwinkel sowie die Grenzwerte f&uuml;r die StateChange_Cloudy und StateChange_Sunny solltet ihr besondere Beachtung dabei schenken.
                <li><strong>ASC_Shading_InOutAzimuth</strong> - Azimut Wert ab dem bei &Uuml;berschreiten Beschattet und bei Unterschreiten Endschattet werden soll. (default: 95:265)</li>
                <li><strong>ASC_Shading_MinMax_Elevation</strong> - ab welcher min H&ouml;he des Sonnenstandes soll beschattet und ab welcher max H&ouml;he wieder beendet werden, immer in Abh&auml;ngigkeit der anderen einbezogenen Sensorwerte (default: 25.0:100.0)</li>
                <li><strong>ASC_Shading_Min_OutsideTemperature</strong> - ab welcher Temperatur soll Beschattet werden, immer in Abh&auml;ngigkeit der anderen einbezogenen Sensorwerte (default: 18)</li>
                <li><strong>ASC_Shading_Mode - absent,always,off,home</strong> / wann soll die Beschattung nur stattfinden. (default: off)</li>
                <li><strong>ASC_Shading_Pos</strong> - Position des Rollladens f&uuml;r die Beschattung (Default: ist abh&auml;ngig vom Attribut<em>ASC</em> 80/20) !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss eine positive Zahl/Dezimalzahl sein!!!</li>
                <li><strong>ASC_Shading_StateChange_SunnyCloudy</strong> - Brightness Wert ab welchen die Beschattung stattfinden und aufgehoben werden soll, immer in Abh&auml;ngigkeit der anderen einbezogenen Sensorwerte. Ein optionaler dritter Wert gibt an wie, viele Brightnesswerte für den aktuellen Brightness-Durchschnitt berücksichtigt werden. Standard ist 3, es sollten nicht mehr als 5 ber&uuml;cksichtigt werden. (default: 35000:20000 [3])</li>
                <li><strong>ASC_Shading_WaitingPeriod</strong> - wie viele Sekunden soll gewartet werden bevor eine weitere Auswertung der Sensordaten f&uuml;r die Beschattung stattfinden soll (default: 1200)</li>
                <li><strong>ASC_Shading_BetweenTheTime</strong> - das fahren in die Beschattung erfolgt bei Angabe nur innerhalb des Zeitraumes, Bsp: 9:00-13:00 11:25-15:30</li>
            </ul></p>
            <li><strong>ASC_ShuttersPlace - window/terrace/awning</strong> - Wenn dieses Attribut auf terrace gesetzt ist, das Residence Device in den Status "gone" geht und SelfDefense aktiv ist (ohne das das Reading selfDefense gesetzt sein muss), wird das Rollo geschlossen. awning steht für Markise und wirkt sich auf die Beschattungssteuerung aus. (default: window)</li>
            <li><strong>ASC_Time_Down_Early</strong> - Sonnenuntergang fr&uuml;hste Zeit zum Runterfahren (default: 16:00) !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss ein Zeitformat in Form HH:MM[:SS] sein!!!</li>
            <li><strong>ASC_Time_Down_Late</strong> - Sonnenuntergang sp&auml;teste Zeit zum Runterfahren (default: 22:00) !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss ein Zeitformat in Form HH:MM[:SS] sein!!!</li>
            <li><strong>ASC_Time_Up_Early</strong> - Sonnenaufgang fr&uuml;hste Zeit zum Hochfahren (default: 05:00) !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss ein Zeitformat in Form HH:MM[:SS] sein!!!</li>
            <li><strong>ASC_Time_Up_Late</strong> - Sonnenaufgang sp&auml;teste Zeit zum Hochfahren (default: 08:30) !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss ein Zeitformat in Form HH:MM[:SS] sein!!!</li>
            <li><strong>ASC_Time_Up_WE_Holiday</strong> - Sonnenaufgang fr&uuml;hste Zeit zum Hochfahren am Wochenende und/oder Urlaub (holiday2we wird beachtet). (default: 08:00) ACHTUNG!!! in Verbindung mit Brightness f&uuml;r <em>ASC_Up</em> muss die Uhrzeit kleiner sein wie die Uhrzeit aus <em>ASC_Time_Up_Late</em> !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss ein Zeitformat in Form HH:MM[:SS] sein!!!</li>
            <li><strong>ASC_Up - astro/time/brightness</strong> - bei astro wird Sonnenaufgang berechnet, bei time wird der Wert aus ASC_Time_Up_Early als Fahrzeit verwendet und bei brightness muss ASC_Time_Up_Early und ASC_Time_Up_Late korrekt gesetzt werden. Der Timer l&auml;uft dann nach ASC_Time_Up_Late Zeit, es wird aber in der Zeit zwischen ASC_Time_Up_Early und ASC_Time_Up_Late geschaut, ob die als Attribut im Moduldevice hinterlegte Down Wert von ASC_brightnessDriveUpDown erreicht wurde. Wenn ja, wird der Rollladen hoch gefahren (default: astro)</li>
            <li><strong>ASC_Ventilate_Window_Open</strong> - auf l&uuml;ften, wenn das Fenster gekippt/ge&ouml;ffnet wird und aktuelle Position unterhalb der L&uuml;ften-Position ist (default: on)</li>
            <li><strong>ASC_WiggleValue</strong> - Wert um welchen sich die Position des Rollladens &auml;ndern soll (default: 5)</li>
            <li><strong>ASC_WindParameters - TRIGGERMAX[:HYSTERESE] [DRIVEPOSITION]</strong> / Angabe von Max Wert ab dem f&uuml;r Wind getriggert werden soll, Hytsrese Wert ab dem der Windschutz aufgehoben werden soll TRIGGERMAX - HYSTERESE / Ist es bei einigen Rolll&auml;den nicht gew&uuml;nscht das gefahren werden soll, so ist der TRIGGERMAX Wert mit -1 an zu geben. (default: '50:20 ClosedPosition')</li>
            <li><strong>ASC_WindowRec_PosAfterDayClosed</strong> - open,lastManual / auf welche Position soll das Rollo nach dem schlie&szlig;en am Tag fahren. Open Position oder letzte gespeicherte manuelle Position (default: open)</li>
            <li><strong>ASC_WindowRec</strong> - WINDOWREC:[READING], Name des Fensterkontaktes, an dessen Fenster der Rollladen angebracht ist (default: none). Reading ist optional</li>
            <li><strong>ASC_WindowRec_subType</strong> - Typ des verwendeten Fensterkontaktes: twostate (optisch oder magnetisch) oder threestate (Drehgriffkontakt) (default: twostate)</li>
            <li><strong>ASC_SlatPosCmd_SlatDevice</strong> - Angaben zu einem Slat (Lamellen) CMD und sofern diese Lamellen &uuml;ber ein anderes Device gesteuert werden zum Slat Device. Beispiel: attr ROLLO ASC_SlatPosCmd_SlatDevice slatPct[:ROLLOSLATDEVICE] [ ] bedeutet optinal. Kann also auch weg gelassen werden. Wenn Ihr das SLAT Device mit angibt dann bitte ohne []. Beispiel: attr ROLLO ASC_SlatPosCmd_SlatDevice slatPct:ROLLOSLATDEVICE. Damit das ganze dann auch greift muss in den 6 Positionsangaben ASC_Open_Pos, ASC_Closed_Pos, ASC_Ventilate_Pos, ASC_ComfortOpen_Pos, ASC_Shading_Pos und ASC_Sleep_Pos ein weiterer Parameter f&uuml;r die Lamellenstellung mit angegeben werden.</li>
        </ul>
    </ul>
    </p>
    <strong><u>Beschreibung der AutoShuttersControl API</u></strong>
    </br>Mit dem Aufruf der API Funktion und &Uuml;bergabe der entsprechenden Parameter ist es m&ouml;glich auf interne Daten zu zu greifen.
    </p>
    <u>&Uuml;bersicht f&uuml;r das Rollladen-Device Getter</u>
    <ul>
        <code>{ ascAPIget('GETTER','ROLLODEVICENAME') }</code><br>
    </ul>
    <table>
        <tr><th>Getter</th><th>Erl&auml;uterung</th></tr>
        <tr><td>FreezeStatus</td><td>1=soft, 2=Daytime, 3=hard</td></tr>
        <tr><td>AntiFreezePos</td><td>konfigurierte Position beim AntiFreeze Status</td></tr>
        <tr><td>AntiFreezePosAssignment</td><td>konfigurierte Lamellen Position bei der AntiFreeze Position</td></tr>
        <tr><td>AntiFreeze</td><td>aktuelle Konfiguration f&uuml;r AntiFreeze</td></tr>
        <tr><td>ShuttersPlace</td><td>aktuelle Konfiguration an welchem Platz sich das Rollo befindet, Fenster oder Terrasse</td></tr>
        <tr><td>SlatPosCmd</td><td>welcher PosCmd ist aktuell f&uuml;r den Lamellen Befehl konfiguriert</td></tr>
        <tr><td>SlatDevice</td><td>welches Device aktuell f&uuml;r die Lamellen Steuerung konfiguriert ist</td></tr>
        <tr><td>PrivacyUpTime</td><td>Privacy Zeit in Sekunden zum fahren in die Privacy Pos vor dem vollen &ouml;ffnen</td></tr>
        <tr><td>PrivacyUpBrightnessVal</td><td>Privacy Brightness Wert zum fahren in die Privacy Pos</td></tr>
        <tr><td>PrivacyUpPos</td><td>Position f&uuml;r die Privacy Up Fahrt</td></tr>
        <tr><td>PrivacyUpPositionAssignment</td><td>Position f&uuml;r die Lamellenfahrt von Privacy Up</td></tr>
        <tr><td>PrivacyDownTime</td><td>Privacy Zeit in Sekunden zum fahren in die Privacy Pos vor dem vollen schlie&szlig;</td></tr>
        <tr><td>PrivacyDownBrightnessVal</td><td>Privacy Brightness Wert zum fahren in die Privacy Pos</td></tr>
        <tr><td>PrivacyDownPos</td><td>Position f&uuml;r die Privacy Down Fahrt</td></tr>
        <tr><td>PrivacyDownPositionAssignment</td><td>Position f&uuml;r die Lamellenfahrt von Privacy Down</td></tr>
        <tr><td>SelfDefenseMode</td><td>Modus f&uuml;r den SelfDefense</td></tr>
        <tr><td>SelfDefenseAbsentDelay</td><td>Verz&ouml;gerungszeit der SelfDefense Fahrt bei absent</td></tr>
        <tr><td>WiggleValue</td><td>um welchen Wert soll das Rollo bei einer wiggle Fahrt fahren</td></tr>
        <tr><td>Adv</td><td>Ist es in der definierten Weihnachtszeit</td></tr>
        <tr><td>ShadingPos</td><td>konfigurierte Position f&uuml;r die Beschattungsfahrt</td></tr>
        <tr><td>ShadingPositionAssignment</td><td>Position f&uuml;r die Lamellenfahrt f&uuml;r die Beschattungsfahrt</td></tr>
        <tr><td>ShadingMode</td><td>welcher aktuelle Modus f&uuml;r das Beschatten ist konfiguriert</td></tr>
        <tr><td>IdleDetectionValue</td><td>welcher Wert im IdleDetectionRading zeigt an dass das Rollo aktuell nicht in Bewegung ist</td></tr>
        <tr><td>ShadingAzimuthLeft</td><td>ab welchem Azimut beginnt die Beschattung</td></tr>
        <tr><td>ShadingAzimuthRight</td><td>ab welchem Azimut endet die Beschattung</td></tr>
        <tr><td>ShadingMinOutsideTemperature</td><td>&uuml;ber welchem Temperaturwert beginnt die Beschattung</td></tr>
        <tr><td>ShadingMinElevation</td><td>&uuml;ber welchem Elevationwert beginnt die Beschattung</td></tr>
        <tr><td>ShadingMaxElevation</td><td>&uuml;ber welchem Elevationwert endet die Beschattung</td></tr>
        <tr><td>ShadingStateChangeSunny</td><td>&uuml;ber welchem Brightnesswert beginnt die Beschattung</td></tr>
        <tr><td>ShadingStateChangeCloudy</td><td>unter welchem Brightnesswert endet die Beschattung</td></tr>
        <tr><td>ShadingWaitingPeriod</td><td>nach welcher Wartezeit werden Beschattungsrelevante Sensorwerte wieder beachtet und die Beschattungsroutine abgearbeitet</td></tr>
        <tr><td>ExternalTriggerDevice</td><td>konfiguriertes Triggerdevice</td></tr>
        <tr><td>ExternalTriggerReading</td><td>kofiguriertes Triggerdevice Reading</td></tr>
        <tr><td>ExternalTriggerValueActive</td><td>Wert mit welchen der externe Trigger Prozess ausgel&uoml;st werden soll.</td></tr>
        <tr><td>ExternalTriggerValueActive2</td><td>weiterer Wert mit welchen der externe zweite Trigger Prozess ausgel&uoml;st werden soll.</td></tr>
        <tr><td>ExternalTriggerValueInactive</td><td>Wert mit welchen der externe Trigger Prozess beendet werden soll</td></tr>
        <tr><td>ExternalTriggerPosActive</td><td>Rolloposition welche angefahren werden soll wenn der erste externe Trigger aktiv wird.</td></tr>
        <tr><td>ExternalTriggerPosActive2</td><td>Rolloposition welche angefahren werden soll wenn der zweite externe Trigger aktiv wird.</td></tr>
        <tr><td>ExternalTriggerPosInactive</td><td>Rolloposition welche angefahren werden soll wenn der externe Trigger inaktiv wird.</td></tr>
        <tr><td>ExternalTriggerStatus</td><td>aktueller Status des externen Triggers, 0 oder 1</td></tr>
        <tr><td>Delay</td><td>konfigurierte Verz&ouml;gerungswert welcher f&uuml;r die Zufallsberechnung werwendet werden soll</td></tr>
        <tr><td>DelayStart</td><td>konfigurierter fester Verz&ouml;gerungswert</td></tr>
        <tr><td>BlockingTimeAfterManual</td><td>konfigurierte Blockzeit nach einer manuellen Fahrt</td></tr>
        <tr><td>BlockingTimeBeforNightClose</td><td>konfigurierte Blockzeit vor dem n&auml;chtlichen schlie&szlig;en</td></tr>
        <tr><td>BlockingTimeBeforDayOpen</td><td>konfigurierte Blockzeit vor dem morgendlichen &ouml;ffnen</td></tr>
        <tr><td>PosCmd</td><td>welches Kommando wird zum fahren der Rollos verwendet (pct, position?)</td></tr>
        <tr><td>OpenPos</td><td>Position f&uuml;r Rollo ganz auf</td></tr>
        <tr><td>OpenPositionAssignment</td><td>Slat-Position f&uuml;r Rollo ganz auf</td></tr> 
        <tr><td>VentilatePos</td><td>L&uuml;ften Position</td></tr>
        <tr><td>VentilatePositionAssignment</td><td>L&uuml;ften Slat-Position</td></tr>
        <tr><td>VentilatePosAfterDayClosed</td><td>Position des Rollos beim schlie&szlig;en des Fensters am Tag</td></tr>
        <tr><td>ClosedPos</td><td>Position f&uuml;r Rollo ganz geschlossen</td></tr>
        <tr><td>ClosedPositionAssignment</td><td>Slat-Position f&uuml;r Rollo ganz geschlossen</td></tr>
        <tr><td>SleepPos</td><td>Position f&uuml;r schlafen</td></tr>
        <tr><td>SleepPositionAssignment</td><td>Slat-Position f&uuml;r schlafen</td></tr>
        <tr><td>VentilateOpen</td><td>L&uuml;ften aktiv?</td></tr>
        <tr><td>ComfortOpenPos</td><td>Comfort Position</td></tr>
        <tr><td>ComfortOpenPositionAssignment</td><td>Slat-Comfort Position</td></tr>
        <tr><td>PartyMode</td><td>Abfrage Party Mode</td></tr>
        <tr><td>Roommates</td><td>Abfrage Roommates / Antwort als String</td></tr>
        <tr><td>RoommatesReading</td><td>Roommates Reading</td></tr>
        <tr><td>RoommatesStatus</td><td>Roommates Status unter Ber&uuml;cksichtigung aller Roommates und dessen Status</td></tr>
        <tr><td>RoommatesLastStatus</td><td>Roommates letzter Status unter Ber&uuml;cksichtigung aller Roommates und dessen letzten Status</td></tr>
        <tr><td>WindPos</td><td>Rollo Position bei Windtrigger</td></tr>
        <tr><td>WindMax</td><td>Wert über dem die Windprotection aktiviert werden soll</td></tr>
        <tr><td>WindMin</td><td>Wert unter dem die Windprotection aufgehoben werden soll</td></tr>
        <tr><td>WindProtection</td><td>Windprotection soll aktiv sein oder nicht</td></tr>
        <tr><td>WindProtectionStatus</td><td>aktueller Status der Wind Protection „protected“ oder „unprotected“</td></tr>
        <tr><td>RainProtection</td><td>Rain Protection soll aktiv sein oder nicht</td></tr>
        <tr><td>RainProtectionStatus</td><td>aktueller Status der Regen Protection „unprotected“ oder „unprotected“</td></tr>
        <tr><td>ModeUp</td><td>aktuelle Einstellung f&uuml;r den Modus des Morgens hoch fahren</td></tr>
        <tr><td>ModeDown</td><td>aktuelle Einstellung f&uuml;r den Modus des Abends runter fahren</td></tr>
        <tr><td>LockOut</td><td>aktuelle Einstellung f&uuml;r den Aussperrschutz</td></tr>
        <tr><td>LockOutCmd</td><td>Aussperrschutz Kommando am Aktor</td></tr>
        <tr><td>AutoAstroModeMorning</td><td>aktuell engestellter Wert f&uuml;r Astro Morgens</td></tr>
        <tr><td>AutoAstroModeEvening</td><td>aktuell engestellter Wert f&uuml;r Astro Abends</td></tr>
        <tr><td>AutoAstroModeMorningHorizon</td><td>HORIZON Wert Morgens</td></tr>
        <tr><td>AutoAstroModeEveningHorizon</td><td>HORIZON Wert Abends</td></tr>
        <tr><td>Up</td><td>aktueller Wert f&uuml;r Morgenfahrten</td></tr>
        <tr><td>Down</td><td>aktueller Wert f&uuml;r Abendfahrten</td></tr>
        <tr><td>TimeUpEarly</td><td>aktueller Wert f&uuml;r fr&uuml;hste Morgenfahrt</td></tr>
        <tr><td>TimeUpLate</td><td>aktueller Wert f&uuml;r sp&auml;teste Morgenfahrt</td></tr>
        <tr><td>TimeDownEarly</td><td>aktueller Wert f&uuml;r fr&uuml;hste Abendfahrt</td></tr>
        <tr><td>TimeDownLate</td><td>aktueller Wert f&uuml;r sp&auml;teste Abendfahrt</td></tr>
        <tr><td>TimeUpWeHoliday</td><td>aktueller Wert f&uuml;r Wochenende und Feiertags Morgenfahrten</td></tr>
        <tr><td>BrightnessMinVal</td><td>   </td></tr>
        <tr><td>BrightnessMaxVal</td><td>   </td></tr>
        <tr><td>DriveUpMaxDuration</td><td>   </td></tr>
        <tr><td>Homemode</td><td>   </td></tr>
        <tr><td>PrivacyDownStatus</td><td>   </td></tr>
        <tr><td>PrivacyUpStatus</td><td>   </td></tr>
        <tr><td>IsDay</td><td>   </td></tr>
        <tr><td>SelfDefenseState</td><td>   </td></tr>
        <tr><td>LastDrive</td><td>   </td></tr>
        <tr><td>LastPos</td><td>   </td></tr>
        <tr><td>Sunset</td><td>   </td></tr>
        <tr><td>Sunrise</td><td>   </td></tr>
        <tr><td>OutTemp</td><td>   </td></tr>
        <tr><td>IdleDetection</td><td>   </td></tr>
        <tr><td>BrightnessAverage</td><td>Nur f&uuml;r die Beschattung relevant</td></tr>
        <tr><td>ShadingStatus</td><td>   </td></tr>
        <tr><td>ShadingLastStatus</td><td>   </td></tr>
        <tr><td>ShadingManualDriveStatus</td><td>   </td></tr>
        <tr><td>IfInShading</td><td>   </td></tr>
        <tr><td>WindProtectionStatus</td><td>   </td></tr>
        <tr><td>RainProtectionStatus</td><td>   </td></tr>
        <tr><td>Brightness</td><td>   </td></tr>
        <tr><td>WindStatus</td><td>   </td></tr>
        <tr><td>Status</td><td>aktuelle Position des Rollos   </td></tr>
        <tr><td>DelayCmd</td><td>Status der Query von ausgesetzten Fahrten wegen PartyMod oder offnen Fenster   </td></tr>
        <tr><td>ASCenable</td><td>Status der ASC Steuerung vom Rollo   </td></tr>
        <tr><td>SubTyp</td><td>Subtype vom Rollo   </td></tr>
        <tr><td>WinDevReading</td><td>   </td></tr>
        <tr><td>WinDev</td><td>   </td></tr>
        <tr><td>WinStatus</td><td>   </td></tr>
        <tr><td>NoDelay</td><td>Wurde die Behandlung von Offset deaktiviert (Beispiel bei Fahrten &uuml;ber Fensterevents)</td></tr>
        <tr><td>LastDrive</td><td>Grund des letzten Fahrens</td></tr>
        <tr><td>LastPos</td><td>die letzte Position des Rollladens</td></tr>
        <tr><td>LastPosTimestamp</td><td>Timestamp der letzten festgestellten Position</td></tr>
        <tr><td>LastManPos</td><td>Position der letzten manuellen Fahrt</td></tr>
        <tr><td>LastManPosTimestamp</td><td>Timestamp der letzten manuellen Position</td></tr>
        <tr><td>SunsetUnixTime</td><td>berechnete Unixzeit f&uuml;r Abends (Sonnenuntergang)</td></tr>
        <tr><td>Sunset</td><td>1=Abendfahrt wurde durchgef&uuml;hrt, 0=noch keine Abendfahrt durchgef&uuml;hrt</td></tr>
        <tr><td>SunriseUnixTime</td><td>berechnete Unixzeit f&uuml;r Morgens (Sonnenaufgang)</td></tr>
        <tr><td>Sunrise</td><td>1=Morgenfahrt wurde durchgef&uuml;hrt, 0=noch keine Morgenfahrt durchgef&uuml;hrt</td></tr>
        <tr><td>RoommatesStatus</td><td>aktueller Status der/des Roommate/s f&uuml;r den Rollladen</td></tr>
        <tr><td>RoommatesLastStatus</td><td>letzter Status der/des Roommate/s f&uuml;r den Rollladen</td></tr>
        <tr><td>ShadingStatus</td><td>Ausgabe des aktuellen Shading Status, „in“, „out“, „in reserved“, „out reserved“</td></tr>
        <tr><td>ShadingStatusTimestamp</td><td>Timestamp des letzten Beschattungsstatus</td></tr>
        <tr><td>IfInShading</td><td>Befindet sich der Rollladen, in Abh&auml;ngigkeit des Shading Mode, in der Beschattung</td></tr>
        <tr><td>DelayCmd</td><td>letzter Fahrbefehl welcher in die Warteschlange kam. Grund z.B. Partymodus.</td></tr>
        <tr><td>Status</td><td>Position des Rollladens</td></tr>
        <tr><td>ASCenable</td><td>Abfrage ob f&uuml;r den Rollladen die ASC Steuerung aktiv ist.</td></tr>
        <tr><td>IsDay</td><td>Abfrage ob das Rollo im Tag oder Nachtmodus ist. Also nach Sunset oder nach Sunrise</td></tr>
        <tr><td>PrivacyDownStatus</td><td>Abfrage ob das Rollo aktuell im PrivacyDown Status steht</td></tr>
        <tr><td>OutTemp</td><td>aktuelle Au&szlig;entemperatur sofern ein Sensor definiert ist, wenn nicht kommt -100 als Wert zur&uuml;ck</td></tr>
        <tr><td>ShadingBetweenTheTime</td><td>Konfiguration f&uuml;r die Zeit der Beschattung</td></tr>
    </table>
    </p>
    <u>&Uuml;bersicht f&uuml;r das Rollladen-Device mit Parameter&uuml;bergabe Getter</u>
    <ul>
        <code>{ ascAPIget('GETTER','ROLLODEVICENAME',VALUE) }</code><br>
    </ul>
    <table>
        <tr><th>Getter</th><th>Erl&auml;uterung</th></tr>
        <tr><td>QueryShuttersPos</td><td>R&uuml;ckgabewert 1 bedeutet das die aktuelle Position des Rollos unterhalb der Valueposition ist. 0 oder nichts bedeutet oberhalb der Valueposition.</td></tr>
    </table>
    </p>
    <u>&Uuml;bersicht f&uuml;r das Rollladen-Device Setter</u>
    <ul>
        <code>{ ascAPIset('SETTER','ROLLODEVICENAME','VALUE') }</code><br>
    </ul>
    <table>
        <tr><th>Setter</th><th>Erl&auml;uterung</th></tr>
        <tr><td>AntiFreezePos</td><td>setzt die Position f&uuml;r Antifreeze</td></tr>
        <tr><td>AntiFreeze</td><td>setzt den Wert f&uuml;r Antifreeze - off/soft/hard/am/pm</td></tr>
        <tr><td>ShuttersPlace</td><td>setzt den Standort des Rollos - window/terrace</td></tr>
        <tr><td>SlatPosCmd</td><td>setzt Command f&uuml;r das fahren der Lamellen</td></tr>
        <tr><td>PrivacyUpTime</td><td>setzt die Zeit f&uuml;r die morgendliche privacy Fahrt</td></tr>
        <tr><td>PrivacyDownTime</td><td>etzt die Zeit f&uuml;r die abendliche privacy Fahrt</td></tr>
        <tr><td>PrivacyDownPos</td><td>setzt die Position f&uuml;r eine abendliche privacy Fahrt</td></tr>
        <tr><td>PrivacyUpPos</td><td>setzt die Position f&uuml;r eine morgendliche privacy Fahrt</td></tr>
        <tr><td>SelfDefenseMode</td><td>setzt den Modus f&uuml;r SelfDefense</td></tr>
        <tr><td>SelfDefenseAbsentDelay</td><td>setzt den Verz&ouml;gerungswert f&uuml;r SelfDefense</td></tr>
        <tr><td>WiggleValue</td><td>setzen der Werte f&uuml;r Wiggle</td></tr>
        <tr><td>Adv</td><td>setzt die Unterst&uuml;tzung f&uuml;r Weihnachten - on/off</td></tr>
        <tr><td>ShadingPos</td><td>setzt den Wert der Beschattungsposition</td></tr>
        <tr><td>ShadingMode</td><td>setzt den Modus der Beschattung - absent/always/off/home</td></tr>
        <tr><td>ShadingMinOutsideTemperature</td><td>setzt den mininmal Temperaturwert zur Beschattung</td></tr>
        <tr><td>ShadingWaitingPeriod</td><td>setzt den Wert der Beschattungswartezeit</td></tr>
        <tr><td>Delay</td><td>setzt den Zufallswert zur verz&ouml;gerten Fahrt</td></tr>
        <tr><td>DelayStart</td><td>setzen den festen Wert zur verz&ouml;gerten Fahrt</td></tr>
        <tr><td>BlockingTimeAfterManual</td><td>setzt den Wert in Sekunden zur Blockade nach einer manuellen Fahrt</td></tr>
        <tr><td>BlockingTimeBeforNightClose</td><td>setzt den Wert in Sekunden zur Blockade vor der Nachtfahrt</td></tr>
        <tr><td>BlockingTimeBeforDayOpen</td><td>setzt den Wert in Sekunden zur Blockade vor der Tagfahrt</td></tr>
        <tr><td>PosCmd</td><td>setzt den Readingnamen zur Positionserkennung des Rollos</td></tr>
        <tr><td>OpenPos</td><td>setzt den Wert f&uuml;r die offen Position</td></tr>
        <tr><td>VentilatePos</td><td>setzt den Wert f&uuml;r die ventilate Position</td></tr>
        <tr><td>VentilatePosAfterDayClosed</td><td>was soll passieren wenn am Tag das Fenster geschlossen wird - open/lastManual</td></tr>
        <tr><td>ClosedPos</td><td>setzt den Wert f&uuml;r die geschlossen Position</td></tr>
        <tr><td>SleepPos</td><td>setzt den Wert f&uuml;r die schlafen Position</td></tr>
        <tr><td>VentilateOpen</td><td>setzt den Wert f&uuml;r VentilateOpen Position</td></tr>
        <tr><td>ComfortOpenPos</td><td>setzt den Wert f&uuml;r ComfortOpen Position</td></tr>
        <tr><td>PartyMode</td><td>Wert f&uuml;r den PartyMode - on/off</td></tr>
        <tr><td>Roommates</td><td>setzt den Wert f&uuml;r Roommates als String, mehrere Roommates durch Komma getrennt</td></tr>
        <tr><td>RoommatesReading</td><td>setzt das Reading f&uuml;r die Roommates</td></tr>
        <tr><td>WindProtection</td><td>setzt/&uuml;berschreibt die WindProtection - protected/unprotected</td></tr>
        <tr><td>RainProtection</td><td>setzt/&uuml;berschreibt die RainProtection - protected/unprotected</td></tr>
        <tr><td>ModeUp</td><td>setzt den Modus f&uuml;r die morgendliche Fahrt - absent/always/off/home</td></tr>
        <tr><td>ModeDown</td><td>setzt den Modus f&uuml;r die abendliche Fahrt - absent/always/off/home</td></tr>
        <tr><td>LockOut</td><td>setzt den zu ber&uuml;cksichtigen LockOut Modus - off/soft/hard</td></tr>
        <tr><td>LockOutCmd</td><td>setzt das Kommando f&uuml;r den LockOut des Rollos</td></tr>
        <tr><td>AutoAstroModeMorning</td><td>   </td></tr>
        <tr><td>AutoAstroModeEvening</td><td>   </td></tr>
        <tr><td>AutoAstroModeMorningHorizon</td><td>   </td></tr>
        <tr><td>AutoAstroModeEveningHorizon</td><td>   </td></tr>
        <tr><td>Up</td><td>   </td></tr>
        <tr><td>Down</td><td>   </td></tr>
        <tr><td>TimeUpEarly</td><td>   </td></tr>
        <tr><td>TimeUpLate</td><td>   </td></tr>
        <tr><td>TimeDownEarly</td><td>   </td></tr>
        <tr><td>TimeDownLate</td><td>   </td></tr>
        <tr><td>TimeUpWeHoliday</td><td>   </td></tr>
        <tr><td>DriveUpMaxDuration</td><td>   </td></tr>
        <tr><td>SubTyp</td><td>   </td></tr>
        <tr><td>WinDev</td><td>   </td></tr>
        <tr><td>ShadingBetweenTheTime</td><td>Konfiguration f&uuml;r die Zeit der Beschattung, Beispiel: 09:00-13:00 WICHTIG!!!! Immer bei einstelligen Stunden die 0 davor setzen</td></tr>
    </table>
    </p>
    <u>&Uuml;bersicht f&uuml;r das ASC Device Getter</u>
    <ul>
        <code>{ ascAPIget('GETTER') }</code><br>
    </ul>
    <table>
        <tr><th>Getter</th><th>Erl&auml;uterung</th></tr>
        <tr><td>OutTemp </td><td>aktuelle Au&szlig;entemperatur sofern ein Sensor definiert ist, wenn nicht kommt -100 als Wert zur&uuml;ck</td></tr>
        <tr><td>ResidentsStatus</td><td>aktueller Status des Residents Devices</td></tr>
        <tr><td>ResidentsLastStatus</td><td>letzter Status des Residents Devices</td></tr>
        <tr><td>Azimuth</td><td>Azimut Wert</td></tr>
        <tr><td>Elevation</td><td>Elevation Wert</td></tr>
        <tr><td>ASCenable</td><td>ist die ASC Steuerung global aktiv?</td></tr>
        <tr><td>PartyMode</td><td>Party Mode Reading   </td></tr>
        <tr><td>HardLockOut</td><td>Hard Lock Out Reading   </td></tr>
        <tr><td>SunriseTimeWeHoliday</td><td>Feiertags und Wochenend Sunrise Zeiten beachten   </td></tr>
        <tr><td>AutoShuttersControlShading</td><td>globale Beschattung on/off   </td></tr>
        <tr><td>SelfDefense</td><td>global Self Defense on/off   </td></tr>
        <tr><td>ShuttersOffset</td><td>globales Drive Delay   </td></tr>
        <tr><td>BrightnessMinVal</td><td>Brightness Wert f&uuml;r Sonnenuntergang   </td></tr>
        <tr><td>BrightnessMaxVal</td><td>Brightness Wert f&uuml;r Sonnenaufgang   </td></tr>
        <tr><td>AutoAstroModeEvening</td><td>   </td></tr>
        <tr><td>AutoAstroModeEveningHorizon</td><td>   </td></tr>
        <tr><td>AutoAstroModeMorning</td><td>   </td></tr>
        <tr><td>AutoAstroModeMorningHorizon</td><td>   </td></tr>
        <tr><td>AutoShuttersControlMorning</td><td>   </td></tr>
        <tr><td>AutoShuttersControlEvening</td><td>   </td></tr>
        <tr><td>AutoShuttersControlComfort</td><td>   </td></tr>
        <tr><td>FreezeTemp</td><td>   </td></tr>
        <tr><td>RainTriggerMax</td><td>   </td></tr>
        <tr><td>RainTriggerMin</td><td>   </td></tr>
        <tr><td>RainSensorShuttersClosedPos</td><td>   </td></tr>
        <tr><td>RainWaitingTime</td><td>   </td></tr>
        <tr><td>BlockAscDrivesAfterManual</td><td>   </td></tr>
    </table>
</ul>

=end html_DE

=for :application/json;q=META.json 73_AutoShuttersControl.pm
{
  "abstract": "Module for controlling shutters depending on various conditions",
  "x_lang": {
    "de": {
      "abstract": "Modul zur Automatischen Rolladensteuerung auf Basis bestimmter Ereignisse"
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "Shutter",
    "Automation",
    "Rollladen",
    "Rollo",
    "Control"
  ],
  "release_status": "stable",
  "license": "GPL_2",
  "version": "v0.10.13",
  "author": [
    "Marko Oldenburg <fhemdevelopment@cooltux.net>"
  ],
  "x_fhem_maintainer": [
    "CoolTux"
  ],
  "x_fhem_maintainer_github": [
    "LeonGaultier"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.016, 
        "Meta": 0,
        "JSON": 0,
        "Date::Parse": 0
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=cut
