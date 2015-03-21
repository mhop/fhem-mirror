##############################################
##############################################
# $Id: 98_ModbusAttr.pm 
#
# generisches fhem Modul für Geräte mit Modbus-Interface
# verwendet Modbus.pm als Basismodul für die eigentliche Implementation des Protokolls.
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
#   2015-03-09  initial release
#

package main;
use strict;
use warnings;


#####################################
sub
ModbusAttr_Initialize($)
{
    my ($modHash) = @_;

    require "$attr{global}{modpath}/FHEM/98_Modbus.pm";

    ModbusLD_Initialize($modHash);                          # Generic function of the Modbus module does the rest
    
    $modHash->{AttrList} = $modHash->{AttrList} . " " .     # Standard Attributes like IODEv etc 
        $modHash->{ObjAttrList} . " " .                     # Attributes to add or overwrite parseInfo definitions
        $modHash->{DevAttrList};                            # Attributes to add or overwrite devInfo definitions
}


1;

=pod
=begin html

<a name="ModbusAttr"></a>
<h3>ModbusAttr</h3>
<ul>
    ModbusAttr uses the low level Modbus module 98_Modbus.pm to provide a generic Modbus module for devices that can be defined by attributes similar to the way HTTPMOD works for devices with a web interface.
    <br><br>
    <b>Prerequisites</b>
    <ul>
        <li>
          This module requires the basic Modbus module which itsef DevIO which again requires Device::SerialPort or Win32::SerialPort module.
        </li>
    </ul>
    <br>

    <a name="ModbusAttrDefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; ModbusAttr &lt;Id&gt; &lt;Interval&gt;</code><br>
        or<br>
        <code>define &lt;name&gt; ModbusAttr &lt;Id&gt; &lt;Interval&gt; &lt;Address:Port&gt; &lt;RTU|TCP&gt;</code><br>
        <br>
        The module connects to the Modbus device with Modbus Id &lt;Id&gt; through an already defined modbus device 
        or directly through Modbus TCP or Modbus RTU over TCP and actively requests data from that device every &lt;Interval&gt; seconds <br>
        <br>
        Examples:<br>
        <br>
        <ul><code>define WP ModbusAttr 1 60</code></ul><br>
        to go through a serial interface managed by an already defined basic modbus device.<br>
        or <br>
        <ul><code>define WP ModbusAttr 5 60 192.168.1.122:504 TCP</code></ul><br>
        to talk Modbus TCP <br>
        or <br>
        <ul><code>define WP ModbusAttr 3 60 192.168.1.122:8000 RTU</code></ul><br>
        to talk Modbus RTU over TCP<br>
    </ul>
    <br>

    <a name="ModbusAttrConfiguration"></a>
    <b>Configuration of the module</b><br><br>
    <ul>
        The data objects (holding registers, input registers, coils or discrete inputs) of the device to be queried are defined using attributes. The attributes assign objects with their address to readings inside fhem and control
        how these readings are calculated from the raw values and how they are formatted.<br>
        Objects can also be written to the device and attributes define how this is done.<br><br>
        
        Example:<br>
        <pre>
        define PWP ModbusAttr 5 30
        attr PWP obj-h256-reading Temp_Wasser_ein
        attr PWP obj-h256-expr $val/10

        attr PWP obj-h258-reading Temp_Wasser_Aus
        attr PWP obj-h258-expr $val/10

        attr PWP obj-h262-reading Temp_Luft
        attr PWP obj-h262-expr $val / 10

        attr PWP obj-h770-reading Temp_Soll
        attr PWP obj-h770-expr $val / 10
        attr PWP obj-h770-set 1
        attr PWP obj-h770-setexpr $val * 10
        attr PWP obj-h770-max 32
        attr PWP obj-h770-min 10
        attr PWP obj-h770-hint 8,10,20,25,28,29,30,30.5,31,31.5,32

        attr PWP dev-h-combine 5
        attr PWP dev-h-defPoll 1

        attr PWP room Pool-WP
        attr PWP stateFormat {sprintf("%.1f Grad", ReadingsVal($name,"Temp_Wasser_Ein",0))}
        attr PWP webCmd Temp_Soll
        </pre>
        
        Attributes to define data objects start with obj- followed by a code that identifies the type and address
        of the data object. <br>
        Modbus devices offer the following types of data objects: holding registers (16 bit objects that can be read and written), input registers (16 bit objects that can only be read), coils (single bit objects that can be read and written) or discrete inputs (single bit objects that can only be read). <br>
        The module uses the first character of these data object types to define attributes. Thus h770 refers to a holding register with the decimal address 770 and c120 refers to a coil with address 120. The address has to be specified as pure decimal number without any leading zeros or spaces.<br><br>
        
        <code>attr PWP obj-h258-reading Temp_Wasser_Aus</code> defines a reading with the name Temp_Wasser_Aus that is read from the Modbus holding register at address 258.<br>
        With the attribute ending on <code>-expr</code> you can define a perl expression to do some conversion or calculation on the raw value read from the device. In the above example the raw value has to be devided by 10 to get the real value.<br><br>
        
        An object attribute ending on <code>-set</code> creates a fhem set option. In the above example the reading Temp_Soll can be changed to 12 degrees by the user with the fhem command <code>set PWP Temp_Soll 12</code><br>
        The object attributes ending on <code>-min</code> and <code>-max</code> define min and max values for input validation and the attribute ending on <code>-hint</code> will tell fhem to create a selection list so the user can graphically select the defined values.<br><br>
        
        To define general properties of the device you can specify attributes starting with <code>dev-</code>. E.g. with <code>dev-timing-timeout</code> you can specify the timeout when waiting for a response from the device. With <code>dev-h-</code> you can specify several default values or general settings for all holding registers like the function code to be used when reading or writing holding registers. These attributes are optional and the module will use defaults that work in most cases. <br>
        <code>dev-h-combine 5</code> for example allows the module to combine read requests to objects having an address that differs 5 or less into one read request. Without setting this attribute the module will start individual read requests for each object. Typically the documentation for the modbus interface of a given device states the maximum number of objects that can be read in one function code 3 request.      
    </ul>

    <a name="ModbusAttrSet"></a>
    <b>Set-Commands</b><br>
    <ul>
        are created based on the attributes defining the data objects.<br>
        Every object for which an attribute like <code>obj-xy-set</code> is set to 1 will create a valid set option.
    </ul>
    <br>
    <a name="ModbusAttrGet"></a>
    <b>Get-Commands</b><br>
    <ul>
        All readings are also available as Get commands. Internally a Get command triggers the corresponding 
        request to the device and then interprets the data and returns the right field value. To avoid huge option lists in FHEMWEB, the objects visible as Get in FHEMWEB can be defined by setting an attribute <code>obj-xy-showget</code> to 1. 
    </ul>
    <br>
    <a name="ModbusAttrattr"></a>
    <b>Attributes</b><br><br>
    <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br>
        the following list of attributes can be applied to any data object by specifying the objects type and address in the variable part. 
        For many attributes you can also specify default values per object type (see dev- attributes later) or you can specify an object attribute without type and address (e.g. obj-len) which then applies as default for all objects:
        <li><b>obj-[cdih][1-9][0-9]*-reading</b></li> 
            define the name of a reading that corresponds to the modbus data object of type c,d,i or h and a decimal address (e.g. obj-h225-reading).
            <br>
        <li><b>obj-[cdih][1-9][0-9]*-name</b></li> 
            defines an optional internal name of this data object (this has no meaning for fhem and serves mainly documentation purposes.
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-set</b></li> 
            if set to 1 then this data object can be changed (works only for holding registers and coils since discrete inputs and input registers can not be modified by definition.
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-min</b></li> 
            defines a lower limit to the value that can be written to this data object. This ist just used for input validation.
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-max</b></li> 
            defines an upper limit to the value that can be written to this data object. This ist just used for input validation.
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-hint</b></li> 
            this is used for set options and tells fhemweb what selection to display for the set option (list or slider etc.)
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-expr</b></li> 
            defines a perl expression that converts the raw value read from the device.
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-map</b></li> 
            defines a map to convert values read from the device to more convenient values when the raw value is read from the device or back when the value to write has to be converted from the user value to a raw value that can be written. Example: 0:mittig, 1:oberhalb, 2:unterhalb 
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-setexpr</b></li> 
            defines a perl expression that converts the user specified value in a set to a raw value that can be sent to the device. This is typically the inversion of -expr above.
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-format</b></li> 
            defines a format string to format the value read e.g. %.1f
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-len</b></li> 
            defines the length of the data object in registers. It defaults to 1. Some devices store 32 bit floating point values in two registers. In this case you can set this attribute to two.
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-unpack</b></li> 
            defines the unpack code to convert the raw data string read from the device to a reading. For an unsigned integer in big endian format this would be "n", for a signed 16 bit integer in big endian format this would be "s>" and for a 32 bit big endian float value this would be "f>". (see the perl documentation of the pack function).
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-showget</b></li> 
            every reading can also be requested by a get command. However these get commands are not automatically offered in fhemweb. By specifying this attribute, the get will be visible in fhemweb.
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-poll</b></li>
            if set to 1 then this obeject is included in the cyclic update request as specified in the define command. If not set, then the object can manually be requested with a get command, but it is not automatically updated each interval. Note that this setting can also be specified as default for all objects with the dev- atributes described later.
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-polldelay</b></li> 
            this attribute allows to poll objects at a lower rate than the interval specified in the define command. you can either specify a time in seconds or number prefixed by "x" which means a multiple of the interval of the define command.<br>
            if you specify a normal numer then it is interpreted as minimal time between the last read and another automatic read. Please note that this does not create an individual interval timer. Instead the normal interval timer defined by the interval of the define command will check if this reading is due or not yet. So the effective interval will always be a multiple of the interval of the define.
        <br>
        <br>
        <li><b>dev-([cdih]-)*read</b></li> 
            specifies the function code to use for reading this type of object. The default is 3 for holding registers, 1 for coils, 2 for discrete inputs and 4 for input registers.
        <br>
        <li><b>dev-([cdih]-)*write</b></li> 
            specifies the function code to use for writing this type of object. The default is 6 for holding registers and 5 for coils. Discrete inputs and input registers can not be written by definition.
        <br>
        <li><b>dev-([cdih]-)*combine</b></li> 
            defines how many adjacent objects can be read in one request. If not specified, the default is 1
        <br>
        <li><b>dev-([cdih]-)*defLen</b></li> 
            defines the default length for this object type. If not specified, the default is 1
        <br>
        <li><b>dev-([cdih]-)*defFormat</b></li> 
            defines a default format string to use for this object type in a sprintf function on the values read from the device.
        <br>
        <li><b>dev-([cdih]-)*defUnpack</b></li> 
            defines the default unpack code for this object type. 
        <br>
        <li><b>dev-([cdih]-)*defPoll</b></li> 
            if set to 1 then all objects of this type will be included in the cyclic update by default. 
        <br>
        <li><b>dev-([cdih]-)*defShowGet</b></li> 
            if set to 1 then all objects of this type will have a visible get by default. 
        <br>
        <li><b>dev-timing-timeout</b></li> 
            timeout for the device (defaults to 2 seconds)
        <br>
        <li><b>dev-timing-sendDelay</b></li> 
            delay to enforce between sending two requests to the device. Default ist 0.1 seconds.
        <br>
        <li><b>dev-timing-commDelay</b></li> 
            delay between the last read and a next request. Default ist 0.1 seconds.
        <br>
        </ul>
    <br>
</ul>

=end html
=cut
