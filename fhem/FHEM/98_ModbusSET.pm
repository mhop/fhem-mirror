################################################################################
# $Id$
#
# fhem Modul für Wärmepumpen der Silent Serie von SET mit Modbus-Interface
# verwendet Modbus.pm als Basismodul für die eigentliche Implementation des Protokolls.
#
# Siehe ModbusExample.pm für eine ausführlichere Infos zur Verwendung des Moduls 
# 98_Modbus.pm 
#
#   
#     This file is part of fhem.
# 
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
# 
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
# 
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
#   Changelog:
#
#   2014-07-12  initial release
#   2015-01-25  changes in sync with the changes in 98_Modbus.pm
#   2015-01-26  more examples / comments on the keys in the parseInfo hash:
#                   - unpack for packing and unpacking the values / data types in the Modbus frames
#                   - len (for values like floats that span two registers)
#                   - format
#   2015-01-27  defLen im Modul-hash des logischen Moduls als Default
#               maxLen als Max für die Länge bei function code 3 (laut Standard 125)
#   2015-01-31  new deviceInfo hash to bundle defaults and function code specific settings
#               added defaultpolldelay to parseInfo
#   2015-02-16  added defPoll,defShowGet to deviceInfo, 
#               defaultpoll in parseInfo, defPoll in deviceInfo und das entsprechende Attribut können auch auf "once"
#               gesetzt werden,
#               defaultpolldelay 
#               defaultpolldelay bzw. das Attribut kann mit x beginnen und ist dann Multiplikator des Intervalls
#   2015-02-17  Initialize, Define und Undef in das Basismodul verlagert
#               Abhängigkeit von Client-Definitionen entfernt.
#
#   2015-02-26  defaultpoll und defaultpolldelay umbenannt
#               attribute für timing umbenannt
#   2017-05-09  added documentation summary
#

package main;
use strict;
use warnings;

sub ModbusSET_Initialize($);

my %SET10parseInfo = (
    "h256"  =>  {   reading => "Temp_Wasser_Ein",   # name of the reading for this value
                    name    => "Pb1",               # internal name of this register in the hardware doc
                    expr    => '$val / 10',         # conversion of raw value to visible value 
                },
    "h258"  =>  {   reading => "Temp_Wasser_Aus",
                    name    => "Pb2",
                    expr    => '$val / 10',
                },
    "h260"  =>  {   reading => "Temp_Verdampfer",
                    name    => "Pb3",
                    expr    => '$val / 10',
                },
    "h262"  =>  {   reading => "Temp_Luft",
                    name    => "Pb4",
                    expr    => '$val / 10',
                },
    "h770"  =>  {   reading => "Temp_Soll", 
                    name    => "ST03",
                    expr    => '$val / 10',
                    setexpr => '$val * 10',         # expression to convert a set value to the internal value 
                    min     => 10,                  # input validation for set: min value
                    max     => 32,                  # input validation for set: max value
                    hint    => "8,10,20,25,28,29,30,30.5,31,31.5,32",
                    set     => 1,                   # this value can be set
                },
    "h771"  =>  {   reading => "Hysterese",         # Hex Adr 303
                    name    => "ST04",
                    expr    => '$val / 10',
                    setexpr => '$val * 10',
                    poll    => "once",              # only poll once (or after a set)
                    min     => 0.5,
                    max     => 3,
                    set     => 1,
                },
    "h777"  =>  {   reading => "Hyst_Mode",         # Hex Adr 0309
                    name    => "ST10",
                    map     => "0:mittig, 1:über, 2:unterhalb", 
                    poll    => "once",              # only poll once (or after a set)
                    set     => 1,
                },
    "h801"  =>  {   reading => "Temp_Wasser_Ein_Off",
                    name    => "CF24",
                    expr    => '$val / 10',
                    poll    => 0,       
                    setexpr => '$val * 10',
                    set     => 1,
                },
    "h802"  =>  {   reading => "Temp_Wasser_Aus_Off",
                    name    => "CF25",
                    expr    => '$val / 10',
                    poll    => 0,
                    setexpr => '$val * 10',
                    set     => 1,
                },
    "h803"  =>  {   reading => "Temp_Verdampfer_Off",
                    name    => "CF26",
                    expr    => '$val / 10',
                    poll    => 0,
                    setexpr => '$val * 10',
                    set     => 1,
                },
    "h804"  =>  {   reading => "Temp_Luft_Off",
                    name    => "CF27",
                    expr    => '$val / 10',
                    poll    => 0,
                    setexpr => '$val * 10',
                    set     => 1,
                },
);


my %SET10deviceInfo = (
    "timing"    => {
            timeout     =>  2,      
            commDelay   =>  0.7,    
            sendDelay   =>  0.7,     
            }, 
    "h"     =>  {               
            combine     =>  5,      
            defShowGet  =>  1,      
            defPoll     =>  1,
            defUnpack   =>  "s>",   
            },
);



#####################################
sub
ModbusSET_Initialize($)
{
    my ($modHash) = @_;

    require "$attr{global}{modpath}/FHEM/98_Modbus.pm";

    $modHash->{parseInfo}  = \%SET10parseInfo;  # defines registers, inputs, coils etc. for this Modbus Defive
    
    $modHash->{deviceInfo} = \%SET10deviceInfo; # defines properties of the device like 
                                                # defaults and supported function codes

    ModbusLD_Initialize($modHash);              # Generic function of the Modbus module does the rest
    
    $modHash->{AttrList} = $modHash->{AttrList} . " " .     # Standard Attributes like IODEv etc 
        $modHash->{ObjAttrList} . " " .                     # Attributes to add or overwrite parseInfo definitions
        $modHash->{DevAttrList} . " " .                     # Attributes to add or overwrite devInfo definitions
        "poll-.* " .                                        # overwrite poll with poll-ReadingName
        "polldelay-.* ";                                    # overwrite polldelay with polldelay-ReadingName
}


1;

=pod
=item device
=item summary Module for heat pumps from SET or others using iChill IC121
=item summary_DE Modul für SET Wärmepumpen und andere mit iChill IC121
=begin html

<a name="ModbusSET"></a>
<h3>ModbusSET</h3>
<ul>
    ModbusSET uses the low level Modbus module to provide a way to communicate with Silent 10 heat pumps from SET.
    It probably works with other heat pumps from SET as well and since the control device used in these heat pumps 
    is an iChill IC121 from Dixell, it could even work for other heat pumps with this controller as well or with few
    changes. It defines the modbus holding registers for the temperature sensors and reads them in a defined interval.
    
    <br>
    <b>Prerequisites</b>
    <ul>
        <li>
          This module requires the basic Modbus module which itsef requires Device::SerialPort or Win32::SerialPort module.
        </li>
    </ul>
    <br>

    <a name="ModbusSETDefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; ModbusSET &lt;Id&gt; &lt;Interval&gt;</code>
        <br><br>
        The module connects to the heat pump with Modbus Id &lt;Id&gt; through an already defined modbus device and actively requests data from the heat pump every &lt;Interval&gt; seconds <br>
        <br>
        Example:<br>
        <br>
        <ul><code>define WP ModbusSET 1 60</code></ul>
    </ul>
    <br>

    <a name="ModbusSETConfiguration"></a>
    <b>Configuration of the module</b><br><br>
    <ul>
        apart from the modbus id and the interval which both are specified in the define command there is nothing that needs to be defined.
        However there are some attributes that can optionally be used to modify the behavior of the module. <br><br>
        
        The attributes that control which messages are sent / which data is requested every &lt;Interval&gt; seconds are:

        <pre>
        poll-Hyst_Mode
        poll-Temp_Luft
        poll-Temp_Wasser_Aus_Off
        poll-Temp_Wasser_Ein_Off
        poll-Temp_Wasser_Aus
        poll-Hysterese
        poll-Temp_Wasser_Ein
        poll-Temp_Soll
        poll-Temp_Luft_Off
        poll-Temp_Verdampfer
        poll-Temp_Verdampfer_Off
        </pre>
        
        if the attribute is set to 1, the corresponding data is requested every &lt;Interval&gt; seconds. If it is set to 0, then the data is not requested.
        by default the temperatures are requested if no attributes are set.<br>
        if some readings should be polled, but less frequently than the normal interval, you can specify a pollDelay- 
        Attribute for the reading. <br>
        The pollDelay attribute allows to poll objects at a lower rate than the interval specified in the define command. you can either specify a time in seconds or number prefixed by "x" which means a multiple of the interval of the define command.<br>
        if you specify a normal numer then it is interpreted as minimal time between the last read and another automatic read. Please note that this does not create an individual interval timer. Instead the normal interval timer defined by the interval of the define command will check if this reading is due or not yet. So the effective interval will always be a multiple of the interval of the define.
        <br><br>
        Example:
        <pre>
        define WP ModbusSET 1 60
        attr WP poll-Temp_Soll 0
        attr WP pollDelay-Hysterese 300
        </pre>
    </ul>

    <a name="ModbusSETSet"></a>
    <b>Set-Commands</b><br>
    <ul>
        The following set options are available:
        <pre>
        Hysterese (defines the hysterese in Kelvin)
        Hyst_Mode (defines the interpretation of hysterese for the heating and can be set to mittig, oberhalb or unterhalb)
        Temp_Wasser_Aus_Off (offset of sensor in Kelvin - used to kalibrate)
        Temp_Wasser_Ein_Off (offset of sensor in Kelvin - used to kalibrate)
        Temp_Luft_Off (offset of sensor in Kelvin - used to kalibrate)
        Temp_Verdampfer_Off (offset of sensor in Kelvin - used to kalibrate)
        Temp_Soll (target temperature of the heating pump)
        </pre>
    </ul>
    <br>
    <a name="ModbusSETGet"></a>
    <b>Get-Commands</b><br>
    <ul>
        All readings are also available as Get commands. Internally a Get command triggers the corresponding 
        request to the device and then interprets the data and returns the right field value. To avoid huge option lists in FHEMWEB, only the most important Get options
        are visible in FHEMWEB. However this can easily be changed since all the readings and protocol messages are internally defined in the modue in a data structure 
        and to make a Reading visible as Get option only a little option (e.g. <code>showget => 1</code> has to be added to this data structure
    </ul>
    <br>
    <a name="ModbusSETattr"></a>
    <b>Attributes</b><br><br>
    <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br>
        <li><b>poll-Hyst_Mode</b></li> 
        <li><b>poll-Temp_Luft</b></li> 
        <li><b>poll-Temp_Wasser_Aus_Off</b></li> 
        <li><b>poll-Temp_Wasser_Ein_Off</b></li> 
        <li><b>poll-Temp_Wasser_Aus</b></li> 
        <li><b>poll-Hysterese</b></li> 
        <li><b>poll-Temp_Wasser_Ein</b></li> 
        <li><b>poll-Temp_Soll</b></li> 
        <li><b>poll-Temp_Luft_Off</b></li> 
        <li><b>poll-Temp_Verdampfer</b></li> 
        <li><b>poll-Temp_Verdampfer_Off</b></li> 
            include a read request for the corresponding registers when sending requests every interval seconds <br>
        <li><b>pollDelay-*</b></li>     
            set a delay for polling individual Readings. In case some readings should be polled less frequently than the
            normal delay specified during define. Specifying a pollDelay will not create an individual timer for 
            polling this reading but check if the delay is over when the normal update interval is handled.<br>
            You can either specify a time in seconds or number prefixed by "x" which means a multiple of the interval of the define command.<br>
            If you specify a normal numer then it is interpreted as minimal time between the last read and another automatic read. Please note that this does not create an individual interval timer. Instead the normal interval timer defined by the interval of the define command will check if this reading is due or not yet. So the effective interval will always be a multiple of the interval of the define.
        <li><b>dev-timing-timeout</b></li> 
            set the timeout for reads, defaults to 2 seconds <br>
        <li><b>dev-timing-minSendDelay</b></li> 
            minimal delay between two requests sent to this device
        <li><b>dev-timing-minCommDelay</b></li>  
            minimal delay between requests or receptions to/from this device
    </ul>
    <br>
</ul>

=end html
=cut
