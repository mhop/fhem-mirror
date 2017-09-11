##############################################
##############################################
# $Id$
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
#   2015-07-22  added documentation for new features introduced in the base module 98_Modbus.pm
#               that can be used here.
#   2016-04-16  Load Modbus base module instead of require - avoids messages when fhem reloads Modbus 
#               because a serial Modbus device is defined afterwards
#   2016-06-18  added documentation for alignTime and enableControlSet (implemented in the base module 98_Modbus.pm)
#   2016-07-07  added documentatoin for nextOpenDelay
#   2016-10-02  fixed typo in documentation (showget has to be showGet)
#   2016-11-26  added missing documentation pieces
#   2016-12-18  documentation added
#   2016-12-24  documentation added
#   2017-01-02  allowShortResponses documented
#   2017-01-25  documentation for ignoreExpr
#   2017-03-12  fixed documentation for logical attrs that were wrongly defined as physical ones
#   2017-07-15  added documentation for new attributes
#   2017-07-25  documentation for data type attributes
#

package main;
use strict;
use warnings;

#####################################
sub
ModbusAttr_Initialize($)
{
    my ($modHash) = @_;

    #require "$attr{global}{modpath}/FHEM/98_Modbus.pm";
    LoadModule "Modbus";
    require "$attr{global}{modpath}/FHEM/DevIo.pm";

    ModbusLD_Initialize($modHash);                          # Generic function of the Modbus module does the rest
    
    $modHash->{AttrList} = $modHash->{AttrList} . " " .     # Standard Attributes like IODEv etc 
        $modHash->{ObjAttrList} . " " .                     # Attributes to add or overwrite parseInfo definitions
        $modHash->{DevAttrList};                            # Attributes to add or overwrite devInfo definitions
}


1;

=pod
=item device
=item summary module for devices with Modbus Interface
=item summary_DE Modul für Geräte mit Modbus-Interface
=begin html

<a name="ModbusAttr"></a>
<h3>ModbusAttr</h3>
<ul>
    ModbusAttr uses the low level Modbus module 98_Modbus.pm to provide a generic Modbus module for devices that can be defined by attributes similar to the way HTTPMOD works for devices with a web interface.
    <br><br>
    <b>Prerequisites</b>
    <ul>
        <li>
          This module requires the basic Modbus module which itsef requires DevIO which again requires Device::SerialPort or Win32::SerialPort module if you connect devices to a serial port.
        </li>
    </ul>
    <br>

    <a name="ModbusAttrDefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; ModbusAttr &lt;Id&gt; &lt;Interval&gt;</code><br>
        or<br>
        <code>define &lt;name&gt; ModbusAttr &lt;Id&gt; &lt;Interval&gt; &lt;Address:Port&gt; &lt;RTU|ASCII|TCP&gt;</code><br>
        <br>
        The module connects to the Modbus device with Modbus Id &lt;Id&gt; through an already defined serial modbus device (RS232 or RS485) or directly through Modbus TCP or Modbus RTU or ASCII over TCP and actively requests data from that device every &lt;Interval&gt; seconds <br>
        <br>
        Examples:<br>
        <br>
        <ul><code>define WP ModbusAttr 1 60</code></ul><br>
        to go through a serial interface managed by an already defined basic modbus device. The protocol defaults to Modbus RTU<br>
        or <br>
        <ul><code>define WP ModbusAttr 20 0 ASCII</code></ul><br>
        to go through a serial interface managed by an already defined basic modbus device with Modbus ASCII. Use Modbus Id 20 and don't query the device in a defined interval. Instead individual SET / GET options have to be used for communication.<br>
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
        The data objects (holding registers, input registers, coils or discrete inputs) of the device to be queried are defined using attributes. 
        The attributes assign objects with their address to readings inside fhem and control
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
        
        Modbus devices offer the following types of data objects: 
        <ul>
        <li> holding registers (16 bit objects that can be read and written)</li>
        <li> input registers (16 bit objects that can only be read)</li>
        <li> coils (single bit objects that can be read and written)</li>
        <li> discrete inputs (single bit objects that can only be read)</li>
        </ul>       
        <br>
        
        The module uses the first character of these data object types to define attributes. 
        Thus h770 refers to a holding register with the decimal address 770 and c120 refers to a coil with address 120. 
        The address has to be specified as pure decimal number. The address counting starts at address 0<br><br>
        
        <code>attr PWP obj-h258-reading Temp_Wasser_Aus</code> defines a reading with the name Temp_Wasser_Aus that is read from the Modbus holding register at address 258.<br>
        With the attribute ending on <code>-expr</code> you can define a perl expression to do some conversion or calculation on the raw value read from the device. 
        In the above example the raw value has to be devided by 10 to get the real value. If the raw value is also the final value then no <code>-expr</code> attribute is necessary. <br><br>
        
        An object attribute ending on <code>-set</code> creates a fhem set option. 
        In the above example the reading Temp_Soll can be changed to 12 degrees by the user with the fhem command <code>set PWP Temp_Soll 12</code><br>
        The object attributes ending on <code>-min</code> and <code>-max</code> define min and max values for input validation 
        and the attribute ending on <code>-hint</code> will tell fhem to create a selection list so the user can graphically select the defined values.<br><br>
        
        To define general properties of the device you can specify attributes starting with <code>dev-</code>. 
        E.g. with <code>dev-timing-timeout</code> you can specify the timeout when waiting for a response from the device. 
        With <code>dev-h-</code> you can specify several default values or general settings for all holding registers 
        like the function code to be used when reading or writing holding registers. 
        These attributes are optional and the module will use defaults that work in most cases. <br>
        <code>dev-h-combine 5</code> for example allows the module to combine read requests to objects having an address that differs 5 or less into one read request. 
        Without setting this attribute the module will start individual read requests for each object. 
        Typically the documentation for the modbus interface of a given device states the maximum number of objects that can be read in one function code 3 request.      
    </ul>

    <a name="ModbusAttrSet"></a>
    <b>Set-Commands</b><br>
    <ul>
        are created based on the attributes defining the data objects.<br>
        Every object for which an attribute like <code>obj-xy-set</code> is set to 1 will create a valid set option.<br>
        Additionally the attribute <code>enableControlSet</code> enables the set options <code>interval</code>, <code>stop</code>, <code>start</code>, <code>reread</code> as well as <code>scanModbusObjects</code>, <code>scanStop</code> and <code>scanModbusIds</code> (for devices connected with RTU / ASCII over a serial line).
        <ul>
            <li><code>interval &lt;Interval&gt;</code></li>
                modifies the interval that was set during define. 
            <li><code>stop</code></li>
                stops the interval timer that is used to automatically poll objects through modbus.
            <li><code>start</code></li>
                starts the interval timer that is used to automatically poll objects through modbus. If an interval is specified during the define command then the interval timer is started automatically. However if you stop it with the command <code>set &lt;mydevice&gt; stop</code> then you can start it again with <code>set &lt;mydevice&gt; start</code>.
            <li><code>reread</code></li>
                causes a read of all objects that are set to be polled in the defined interval. The interval timer is not modified.
            <br>
            <li><code>scanModbusObjects &lt;startObj&gt; - &lt;endObj&gt; &lt;reqLen&gt;</code></li>
                scans the device objects and automatically creates attributes for each reply it gets. This might be useful for exploring devices without proper documentation. The following example starts a scan and queries the
                holding registers with addresses between 100 and 120. <br>
                <code>set MyModbusAttrDevice scanModbusObjects h100-120</code><br>
                For each reply it gets, the module creates a reading like<br>
                <code>scan-h100 hex=0021, string=.!, s=8448, s>=33, S=8448, S>=33</code><br>
                the representation of the result as hex is 0021 and
                the ASCII representation is .!. s, s>, S and S> are different representations with their Perl pack-code.
            <li><code>scanModbusIds &lt;startId&gt; - &lt;endId&gt; &lt;knownObj&gt;</code></li>
                scans for Modbus Ids on an RS485 Bus. The following set command for example starts a scan:<br>
                <code>set Device scanModbusId 1-7 h770</code><br>
                since many modbus devices don't reply at all if an object is requested that does not exist, scanModbusId 
                needs the adress of an object that is known to exist.
                If a device with Id 5 replies to a read request for holding register 770, a reading like the following will be created:<br>
                <code>scanId-5-Response-h770 hex=0064, string=.d, s=25600, s>=100, S=25600, S>=100</code>
            <li><code>scanStop</code></li>
                stops any running scans.
            <li><code>saveAsModule &lt;name&gt;</code></li>
                experimental: saves the definitions of obj- and dev- attributes in a new fhem module file as /tmp/98_ModbusGen&lt;name&gt;.pm.<br>
                if this file is copied into the fhem module subdirectory (e.g. /opt/fhem/FHEM) and fhem is restarted then instead of defining a device
                as ModbusAttr with all the attributes to define objects, you can just define a device of the new type ModbusGen&lt;name&gt; and all the 
                objects will be there by default. However all definitions can still be changed / overriden with the attribues defined in ModbusAttr if needed.
        </ul>
    </ul>
    <br>
    <a name="ModbusAttrGet"></a>
    <b>Get-Commands</b><br>
    <ul>
        All readings are also available as Get commands. Internally a Get command triggers the corresponding 
        request to the device and then interprets the data and returns the right field value. 
        To avoid huge option lists in FHEMWEB, the objects visible as Get in FHEMWEB can be defined by setting an attribute <code>obj-xy-showGet</code> to 1. 
    </ul>
    <br>
    <a name="ModbusAttrattr"></a>
    <b>Attributes</b><br><br>
    <ul>
        <li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br>
        <li><b>alignTime</b></li>
            Aligns each periodic read request for the defined interval to this base time. This is typcally something like 00:00 (see the Fhem at command)
        <li><b>enableControlSet</b></li>
            enables the built in set commands like interval, stop, start and reread (see above)        
        <br>
        
        please also notice the attributes for the physical modbus interface as documented in 98_Modbus.pm
        <br>
        
        the following list of attributes can be applied to any data object by specifying the objects type and address in the variable part. 
        For many attributes you can also specify default values per object type (see dev- attributes later) or you can specify an object attribute without type and address 
        (e.g. obj-len) which then applies as default for all objects:
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
        <li><b>obj-[cdih][1-9][0-9]*-ignoreExpr</b></li> 
            defines a perl expression that returns 1 if a value should be ignored and the existing reading should not be modified
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-map</b></li> 
            defines a map to convert values read from the device to more convenient values when the raw value is read from the device 
            or back when the value to write has to be converted from the user value to a raw value that can be written. 
            Example: 0:mittig, 1:oberhalb, 2:unterhalb 
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-setexpr</b></li> 
            defines a perl expression that converts the user specified value in a set to a raw value that can be sent to the device. 
            This is typically the inversion of -expr above.
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-format</b></li> 
            defines a format string to format the value read e.g. %.1f
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-len</b></li> 
            defines the length of the data object in registers. It defaults to 1. 
            Some devices store 32 bit floating point values in two registers. In this case you should set this attribute to two.
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-unpack</b></li> 
            defines the unpack code to convert the raw data string read from the device to a reading. 
            For an unsigned integer in big endian format this would be "n", 
            for a signed 16 bit integer in big endian format this would be "s>" 
            and for a 32 bit big endian float value this would be "f>". (see the perl documentation of the pack function).<br>
            Please note that you also have to set a -len attribute (for this object or for the device) if you specify an unpack code that consumes data from more than one register.<br>
            For a 32 bit float len should be at least 2.
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-revRegs</b></li> 
            this is only applicable to objects that span several input registers or holding registers. <br>
            when they are read then the order of the registers will be reversed before 
            further interpretation / unpacking of the raw register string. The same happens before the object is written with a set command.
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-bswapRegs</b></li>
            this is applicable to objects that span several input or holding registers. <br>
            After the registers have been read and before they are writtem, all 16-bit values are treated big-endian and are reversed to little-endian by swapping the two 8 bit bytes. 
            This functionality is most likely used for reading (ASCII) strings from the device that are stored as big-endian 16-bit values. <br>
            example: original reading is "324d3130203a57577361657320722020". After applying bswapRegs, the value will be "4d3230313a2057576173736572202020"
            which will result in the ASCII string "M201: WWasser   ". Should be used with "(a*)" as -unpack value.
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-decode</b></li> 
            defines an encoding to be used in a call to the perl function decode to convert the raw data string read from the device to a reading. 
            This can be used if the device delivers strings in an encoding like cp850 instead of utf8.
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-encode</b></li> 
            defines an encoding to be used in a call to the perl function encode to convert the raw data string read from the device to a reading. 
            This can be used if the device delivers strings in an encoding like cp850 and after decoding it you want to reencode it to e.g. utf8.
        <br>
        <li><b>obj-[ih][1-9][0-9]*-type</b></li> 
            defines that this object has a user defined data type. Data types can be defined using the dev-type- attribues.<br>
            If a device with many objects uses for example floating point values that span two swapped registers with the unpack code f>, then instead of specifying the -unpack, -revRegs, -len, -format and other attributes over and over again, you could define a data type with attributes that start with dev-type-VT_R4- and then 
            use this definition for each object as e.g. obj-h1234-type VT_R4<br>
            example:<br>
            <pre>
            attr WP dev-type-VT_R4-format %.1f
            attr WP dev-type-VT_R4-len 2
            attr WP dev-type-VT_R4-revRegs 1
            attr WP dev-type-VT_R4-unpack f>
            
            attr WP obj-h1234-reading Temp_Ist
            attr WP obj-h1234-type VT_R4
            </pre>
        <br>
        
        <li><b>obj-[cdih][1-9][0-9]*-showGet</b></li> 
            every reading can also be requested by a get command. However these get commands are not automatically offered in fhemweb. 
            By specifying this attribute, the get will be visible in fhemweb.
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-poll</b></li>
            if set to 1 then this obeject is included in the cyclic update request as specified in the define command. 
            If not set, then the object can manually be requested with a get command, but it is not automatically updated each interval. 
            Note that this setting can also be specified as default for all objects with the dev- atributes described later.
        <br>
        <li><b>obj-[cdih][1-9][0-9]*-polldelay</b></li> 
            this attribute allows to poll objects at a lower rate than the interval specified in the define command. 
            You can either specify a time in seconds or number prefixed by "x" which means a multiple of the interval of the define command.<br>
            If you specify a normal numer then it is interpreted as minimal time between the last read and another automatic read. 
            Please note that this does not create an additional interval timer. 
            Instead the normal interval timer defined by the interval of the define command will check if this reading is due or not yet. 
            So the effective interval will always be a multiple of the interval of the define.
        <br>
        <br>
        <li><b>dev-([cdih]-)*read</b></li> 
            specifies the function code to use for reading this type of object. 
            The default is 3 for holding registers, 1 for coils, 2 for discrete inputs and 4 for input registers.
        <br>
        <li><b>dev-([cdih]-)*write</b></li> 
            specifies the function code to use for writing this type of object. 
            The default is 6 for holding registers and 5 for coils. Discrete inputs and input registers can not be written by definition.
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
        <li><b>dev-([cdih]-)*defExpr</b></li> 
            defines a default Perl expression to use for this object type to convert raw values read.
        <br>
        <li><b>dev-([cdih]-)*defIgnoreExpr</b></li> 
            defines a default Perl expression to decide when values should be ignored.
        <br>
        <li><b>dev-([cdih]-)*defUnpack</b></li> 
            defines the default unpack code for this object type. 
        <br>
        <li><b>dev-([cdih]-)*defRevRegs</b></li> 
            defines that the order of registers for objects that span several registers will be reversed before 
            further interpretation / unpacking of the raw register string
        <br>
        <li><b>dev-([cdih]-)*defBswapRegs</b></li> 
            per device default for swapping the bytes in Registers (see obj-bswapRegs above)
        <br>
        <li><b>dev-([cdih]-)*defDecode</b></li> 
            defines a default for decoding the strings read from a different character set e.g. cp850
        <br>
        <li><b>dev-([cdih]-)*defEncode</b></li> 
            defines a default for encoding the strings read (or after decoding from a different character set) e.g. utf8
        <br>

        <li><b>dev-([cdih]-)*defPoll</b></li> 
            if set to 1 then all objects of this type will be included in the cyclic update by default. 
        <br>
        <li><b>dev-([cdih]-)*defShowGet</b></li> 
            if set to 1 then all objects of this type will have a visible get by default. 
        <br>
        
        <li><b>dev-type-XYZ-unpack, -len, -encode, -decode, -revRegs, -bswapRegs, -format, -expr, -map</b></li> 
            define the unpack code, length and other details of a user defined data type. XYZ has to be replaced with the name of a user defined data type.
            use obj-h123-type XYZ to assign this type to an object.
        <br>
        
        <li><b>dev-([cdih]-)*allowShortResponses</b></li> 
            if set to 1 the module will accept a response with valid checksum but data lengh < lengh in header
        <br>
        <li><b>dev-h-brokenFC3</b></li> 
            if set to 1 the module will change the parsing of function code 3 and 4 responses for devices that 
            send the register address instead of the length in the response
        <br>
        <li><b>dev-c-brokenFC5</b></li> 
            if set the module will use the hex value specified here instead of ff00 as value 1 for setting coils
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
        <li><b>queueMax</b></li> 
            max length of the send queue, defaults to 100
        <br>
        <li><b>nextOpenDelay</b></li> 
            delay for Modbus-TCP connections. This defines how long the module should wait after a failed TCP connection attempt before the next reconnection attempt. This defaults to 60 seconds.
        <li><b>openTimeout</b></li>     
            timeout to be used when opening a Modbus TCP connection (defaults to 3)
        <li><b>timeoutLogLevel</b></li> 
            log level that is used when logging a timeout. Defaults to 3. 
        <li><b>silentReconnect</b></li> 
            if set to 1, then it will set the loglevel for "disconnected" and "reappeared" messages to 4 instead of 3
        <li><b>maxTimeoutsToReconnect</b></li> 
            this attribute is only valid for TCP connected devices. In such cases a disconnected device might stay undetected and lead to timeouts until the TCP connection is reopened. This attribute specifies after how many timeouts an automatic reconnect is tried.
        <li><b>nonPrioritizedSet</b></li> 
            if set to 1, then set commands will not be sent on the bus before other queued requests and the response will not be waited for.
        <li><b>sortUpdate</b></li> 
            if set to 1, the requests during a getUpdate cycle will be sorted before queued.
            
        <li><b>disable</b></li>
            stop communication with the device while this attribute is set to 1. For Modbus over TCP this also closes the TCP connection.
        <br>
        </ul>
    <br>
</ul>

=end html
=cut
