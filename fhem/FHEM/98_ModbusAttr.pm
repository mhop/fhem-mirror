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
#   2018-08-24  started documenting the new features of the base Modbus module version 4
#   2018-11-10  fixed doku for defSetexpr
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
=item summary module for Modbus (as master, slave, relay, or for passive listening)
=item summary_DE Modul für Modbus (als Master, Slave, Relay oder zum Mitlesen)
=begin html


<a name="ModbusAttr"></a>
<h3>ModbusAttr</h3>
<ul>
    ModbusAttr uses the low level Modbus module 98_Modbus.pm to provide a generic Modbus module (as master, slave, relay or passive listener) <br>
    that can be configured by attributes similar to the way HTTPMOD works for devices with a web interface. <br>
    ModbusAttr can be used as a Modbus master that queries data from other devices over a serial RS232 / RS485 or TCP connection, <br>
    it can be used as a Modbus slave that can make readings of Fhem devices available via Modbus to external Modbus masters,<br>
    it can act as aModbus relay that receives requests over one connection and forwards them over another connection (e.g. from Modbus TCP to serial Modbus RTU)<br>
    or it can passively listen to other devices that communicate over a serial RS485 connection and extract readings from the objects it sees.<br>
    The supported protocols are Modbus RTU, Modbus ASCII or Modbus TCP.<br>
    There are several attributes that modify the way data objects are converted before they are stored in readings or sent to a device. Data can be modified by a perl expression defined in an atribute, formatted with a format string defined in another attribute or mapped to a table defined in an attribute.<br>
    Readings can directly correspond to one data object or they can span several objects. A float value for example might be stored in two input or holding registers in the Modbus device. By specifying attributes that define the length of a reading in objects and by specifying the unpack code to get from a raw string to perl variables, all these cases can be described by attributes and no perl coding is necessary.

    <br><br>
    <b>Prerequisites</b>
    <ul>
        <li>
          This module requires the basic Modbus module which itsef requires DevIO which again requires Device::SerialPort or Win32::SerialPort module if you connect devices to a serial port (RS232 or RS485).
        </li>
    </ul>
    <br>

    <a name="ModbusAttrDefine"></a>
    <b>Define as Modbus master</b>
    <ul>
        <code>
        define <iodevice> Modbus /dev/device@baudrate,bits,parity,stop<br>
        define &lt;name&gt; ModbusAttr &lt;Id&gt; &lt;Interval&gt;
        </code><br>
        or<br>
        <code>
        define &lt;name&gt; ModbusAttr &lt;Id&gt; &lt;Interval&gt; &lt;Address:Port&gt; &lt;RTU|ASCII|TCP&gt;
        </code><br>
        
        In the first case the module connects to the external Modbus device with Modbus Id &lt;Id&gt; through the serial modbus device (RS232 or RS485). Therefore a physical [[Modbus]] device is defined first<br>
        In the second case the module connects directly through Modbus TCP or Modbus RTU or ASCII over TCP.<br>
        If &lt;Interval&gt; is not 0 then the module actively requests data from the external device every &lt;Interval&gt; seconds <br>
        The objects that the module should request and the readings it should create from these objects have to be defined with attributes (see below). <br>
        These attributes will define a mapping from so called "coils", "digital inputs", "input registers" or "holding registers" of the external device to readings inside Fhem together with the data type and format of the values.<br>
        Interval can be 0 in which case the Module only requests data when it is triggered with a Fhem get-Command.<br>
        With this mode a Fhem installation can for example query sensor data from a heating system, energy meter or solar power installation if these systems offer a Modbus interface.
        <br>
        Examples:<br>
        <br>
        <ul><code>
        define ModbusLine Modbus /dev/ttyUSB1@9600<br>
        define WP ModbusAttr 1 60       
        </code></ul><br>
        Define WP as a Modbus master that communicates through the Modbus serial interface device named ModbusLine. The protocol defaults to Modbus RTU<br>
        or <br>
        <ul><code>
        define ModbusLine Modbus /dev/ttyUSB1@9600<br>
        define WP ModbusAttr 20 0 ASCII
        </code></ul><br>
        
        Define WP as a Modbus master that communicates through the Modbus serial interface device named ModbusLine with Modbus ASCII. 
        Use Modbus Id 20 and don't query the device in a defined interval. Instead individual SET / GET options have to be used for communication.<br>
        or <br>
        <ul><code>define WP ModbusAttr 5 60 192.168.1.122:502 TCP</code></ul><br>
        to talk Modbus TCP to a device with IP-Address 192.168.1.122 and the reserved port for Modbus TCP 502<br>
        Note that for Modbus over a TCP connection you don't need a basic Modbus device for the interface like ModbusLine above. <br>
        or <br>
        <ul><code>define WP ModbusAttr 3 60 192.168.1.122:8000 RTU</code></ul><br>
        to talk Modbus RTU over TCP and use the port number 8000<br>
    </ul>
    <br>

    <b>Define as Modbus slave</b>
    <ul>
        <code>define &lt;name&gt; ModbusAttr &lt;Id&gt; slave</code><br>
        or<br>
        <code>define &lt;name&gt; ModbusAttr &lt;Id&gt; slave &lt;Address:Port&gt; &lt;RTU|ASCII|TCP&gt;</code><br>
        <br>
        The module waits for connections from other Modbus masters. It will respond to their requests if the requests contain the given Modbus &lt;Id&gt;<br>
        To provide data with Modbus to external Modbus masters a mapping needs to be defined using attributes. 
        These attributes will define a mapping from Readings inside Fhem to so called "coils", "digital inputs", "input registers" or "holding registers" and their Modbus object address together with the data type and format of the values.<br>
        With this mode a Fhem installation can for example supply data to a PLC that actively reads data from Fhem or writes data to Fhem readings.
        <br>
        Examples:<br>
        <br>
        <ul><code>define MRS485 Modbus /dev/ttyUSB2@9600,8,E,1<br>
                  define Data4PLC ModbusAttr 1 slave</code></ul><br>
        Define Data4PLC as a Modbus slave that communicates through the Modbus serial interface device named MRS485 to listen for Modbus requests with Id 1. The protocol defaults to Modbus RTU<br>
        or <br>
        <ul><code>define MRS485 Modbus /dev/ttyUSB2@9600,8,E,1<br>
                  define Data4PLC ModbusAttr 20 slave ASCII</code></ul><br>
        to listen for Modbus requests with Id 20 with Modbus ASCII. <br>
        or <br>
        <ul><code>define Data4PLC ModbusAttr 5 slave 192.168.1.2:502 TCP</code></ul><br>
        to start listening to TCP port 502 on the local address 192.168.1.2. Modbus TCP will be used as protocol and Requests with Modbus Id 5 will be answered.<br>
        Please be aware that opening a port number smaller than 1024 needs root permissions on Unix devices. So it is probably better to use a non standard port number above 1024 instead.<br>
        or <br>
        <ul><code>define Data4PLC ModbusAttr 3 slave 192.168.1.2:8000 RTU</code></ul><br>
        to listen to the local port 8000 and talk Modbus RTU over TCP<br>
    </ul>
    <br>

    <b>Define as Modbus passive listener</b>
    <ul>
        <code>define &lt;name&gt; ModbusAttr &lt;Id&gt; passive &lt;RTU|ASCII|TCP&gt;</code><br>
        <br>
        The module listens on a serial (RS485) connection for modbus communication with the given Modbus &lt;Id&gt; and extracts readings. It does not send requests by itself but waits for another master to communicate with a slave. So only objects that the other master requests can be seen by Fhem in this configuration. <br>
        The objects that the module recognizes and the readings that it should create from these objects have to be defined with attributes (see below) in the same way as for a Modbus master. <br>
        These attributes will define a mapping from so called "coils", "digital inputs", "input registers" or "holding registers" of the external device to readings inside Fhem together with the data type and format of the values.<br>
        With this mode a Fhem installation can for example Listen to the communication between an energy counter as slave and a solar control system as master if they use Modbus RTU over RS485. Since only one Master is allowed when using Modbus over serial lines, Fhem can not be master itself. As a passive listener it can however see when the master queries e.g. the current power consumption and then also see the reply from the energy meter and store the value in a Fhem reading.
        <br>
        Examples:<br>
        <br>
        <ul><code>define MB-485 Modbus /dev/ttyUSB2<br>
                  define WP ModbusAttr 1 passive</code></ul><br>
        to passively listen for Modbus requests and replies with Id 1 over a serial interface managed by an already defined basic modbus device named MB-485. The protocol defaults to Modbus RTU<br>
        or <br>
        <ul><code>define MB-485 Modbus /dev/ttyUSB2<br>
                  define WP ModbusAttr 20 passive ASCII</code></ul><br>
        to passivel listen for Modbus requests / replies with Id 20 and Modbus ASCII. <br>
    </ul>
    <br>

    <b>Define as Modbus relay</b>
    <ul>
        <code>define &lt;name&gt; ModbusAttr &lt;Id&gt; relay to &lt;FhemMasterDevice&gt;</code><br>
        or<br>
        <code>define &lt;name&gt; ModbusAttr &lt;Id&gt; relay &lt;Address:Port&gt; &lt;RTU|ASCII|TCP&gt; to &lt;FhemMasterDevice&gt;</code><br>
        <br>
        The module waits for connections from other Modbus masters. It will forward requests if they match the given Modbus &lt;Id&gt; to an already defined Modbus Master device inside Fhem which will send them to its defined slave, take the reply and the pass it back to the original Master.<br>
        With this mode a Fhem installation can for example be used in front of a device that only speaks Modbus RTU over RS485 to make it available via Modbus TCP over the local network. 
        <br>
        Examples:<br>
        <br>
        <ul><code>define MB-485 Modbus /dev/ttyUSB2<br>
                  define Heating ModbusAttr 22 0<br>
                  define Relay ModbusAttr 33 relay 192.168.1.2:1502 TCP to Heating</code></ul><br>
        Defines MB-485 as a base device for the RS-485 communication with a heating system, <br>
        defines Heating as a Modbus Master to communicate with the Heating and its Modbus ID 22, <br>
        and then defines the relay which listens to the local IP address 192.168.1.2, TCP port 1502, Modbus Id 33 and protocol Modbus-TCP.<br>
        Requests coming in through Modbus TCP and port 1502 are then translated to Modbus RTU and forwarded via RS-485 to the heating system with Modbus Id 22. <br>
        or (unlikely)<br>
        <ul><code>define MB-232 Modbus /dev/ttyUSB2@19200<br>
                  define Solar ModbusAttr 7 0 192.168.1.122:502 RTU<br>
                  define PLC2NetRelay ModbusAttr 1 ASCII relay to Solar</code></ul><br>
        Defines MB-232 as a base device for the RS-232 communication with a PLC as Modbus master, <br>
        defines Solar as a Modbus Master to communicate with Modbus TCP to a Solar power system at IP Adrress 192.168.1.122 and its Modbus ID 7, <br>
        and then defines the PLC2NetRelay as a relay which listens to Modbus-ASCII requests over the serial RS-232 link from a PLC to Modbus ID 1.<br>
        Requests to Modbus Id 1 coming in through the serial link are then translated to Modbus TCP and forwarded over the network to the solar power system with Modbus Id 7. <br>
    </ul>
    <br>
    
    
    <a name="ModbusAttrConfiguration"></a>
    <b>Configuration of the module as master or passive listener</b>
    <ul>
        Data objects (holding registers, input registers, coils or discrete inputs) are defined using attributes. 
        If Fhem is Modbus master or passive listener, the attributes assign data objects of external devices (heating systems, power meters, PLCs or other) with their register addresses to readings inside fhem and control how these readings are calculated from the raw values and how they are formatted.<br>
        Please be aware that Modbus does not define common data types so the representation of a value can be very different from device to device. One device might make a temperature value avaliable as a floating point value that is stored in two holding resgisters, another device might store the temperature multiplied with 10 as an signed integer in one register. Even the order of bytes can vary.<br>
        Therefore it is typically necessary to specify the data representation as a Perl unpack code.<br>
        A Modbus master can also write values to Objects in the device and attributes define how this is done.<br><br>
        
        Example for a Modbus master or passive configuration:<br>
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
        attr PWP dev-h-defUnpack n

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
        
        Please note that the documentation for devices sometimes uses different numbering. They might start counting with one instead of zero so if a voltage value is stored in input register number 107 according to the documentation of the device, it might technically mean register number 106 (in the Modbus protocol specification addresses start with 0).<br>
        Also some vendors use hexadecimal descriptions of their register addresses. So input register 107 might be noted as hex and means 263 or even 262 as decimal address.<br>
        
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
        Typically the documentation for the modbus interface of a given device states the maximum number of objects that can be read in one function code 3 request.<br>
        <code>dev-h-defUnpack n</code> means that the values in this example that the values are stored as unsigned short (16-bit) in "network" (big-endian) order. This is only one possibility of many. An integer value might be signed instead of unsigned or it might use different byte ordering (e.g. unpack codes v or s).<br> 
    </ul>
    <br>
    
    <a name="ModbusAttrDataTypes"></a>
    <b>Handling Data Types</b>
    <ul>
        The Modbus protocol does not define data types. If the documentation of a device states that for example the current temperature is stored in holding register 102 this leaves room for many interpretations. Not only can the address 102 mean different things (actually decimal 102 or rather 101 if the vendor starts counting at 1 instead of 0 or even 257 or 258 if the vendor used hexadecimal addresses in his documentation ) also the data representation can be many different things. As in every programming language, there are many ways to represent numbers. They can be stored signed or unsigned, they can be integers or floating point numbers, the byte-order can be "big endian" or "small endian", the value can be stored in one holding register or in two holding registers (floating point numbers typically take four bytes which means two holding registers).<br>
        The Modbus module allows flexible configuration of data representations be assigning a Perl unpack-code, a length, a Perl Expression, and the register ordering. The following example illustrates how this can be done:<br>        
        <pre>
        attr PWP obj-h338-reading Pressure
        attr PWP obj-h338-len 2
        attr PWP obj-h338-unpack f>
        attr PWP obj-h338-revRegs 1
        attr PWP obj-h338-format %.2f
        </pre>
        In This example a floating point value for the reading "Pressure" is read from the holding registers starting at address 338. 
        The value occupies 32 Bits and is therefore stored in two registers. The Perl pack code to use is f> which means a native single precision float in big endian format (byte order). With revRegs the module is instructed to reverse the order of the registers directly after reading. The format specification then defines how the value is formatted into a reading - in this case with two digits after the comma. See http://perldoc.perl.org/functions/pack.html for Perl pack / unpack codes and http://perldoc.perl.org/functions/sprintf.html for format specifications.<br>
        <br>
        If you need to read / write many objects for a device, defining all these parameters each time is not elegant. The Modbus module therefore offers twi ways to simplify this task: <br>
        You can define defaults for every type of object or you can define your own data types once and then refer to them.<br>
        This exampe shows how defaults can be specified for holding registers and input registers:<br>
        <pre>
        attr PWP dev-h-defUnpack f>
        attr PWP dev-h-defLen 2
        attr PWP dev-h-defRevRegs 1
        attr PWP dev-h-defFormat %.2f
        
        attr PWP dev-i-defUnpack n
        attr PWP dev-i-defLen 1
        </pre>
        <br>
        The next example shows how you can define your own data types and then apply them to objects:<br>
        <pre>
        attr WP dev-type-VT_R4-format %.1f
        attr WP dev-type-VT_R4-len 2
        attr WP dev-type-VT_R4-revRegs 1
        attr WP dev-type-VT_R4-unpack f>
        
        attr WP obj-h1234-reading Temp_In
        attr WP obj-h1234-type VT_R4
        attr WP obj-h1236-reading Temp_Out
        attr WP obj-h1236-type VT_R4
        </pre>
        This example defines a data type with the name VT_R4 which uses an unpack code of f>, length 2 and reversed register ordering. It then assigns this Type to the objects Temp_In and Temp_Out.<br>
        <br>
    </ul>
    <br>
    
    <a name="ModbusAttrConfigurationSlave"></a>
    <b>Configuration of the module as Modbus slave</b>
    <ul>
        Data objects that the module offers to external Modbus masters (holding registers, input registers, coils or discrete inputs) are defined using attributes. 
        If Fhem is Modbus slave, the attributes assign readings of Fhem devices to Modbus objects with their addresses and control how these objects are calculated from the reading values that exist in Fhem.<br>
        It is also possible to allow an external Modbus master to send write function codes and change the value of readings inside Fhem.
        
        Example for a Modbus slave configuration:<br>
        <pre>
        define MRS485 Modbus /dev/ttyUSB2@9600,8,E,1
        define Data4PLC ModbusAttr 1 slave
        attr Data4PLC IODev MRS485
        
        attr Data4PLC obj-h256-reading THSensTerrasse:temperature
        attr Data4PLC obj-h256-unpack f
        attr Data4PLC obj-h256-len 2
        
        attr Data4PLC obj-h258-reading THSensTerrasse:humidity
        attr Data4PLC obj-h258-unpack f
        attr Data4PLC obj-h258-len 2
        
        attr Data4PLC obj-h260-reading myDummy:limit
        attr Data4PLC obj-h260-unpack n
        attr Data4PLC obj-h260-len 1
        attr Data4PLC obj-h260-allowWrite 1
        </pre>
        
        In this example Fhem allows an external Modbus master to read the temperature of a Fhem device named THSensTerrasse through holding register 256 and the humidity of that Fhem device through holding register 258. Both are encoded as floting point values that span two registers. <br>
        The master can also read but also write the reading named limit of the device myDummy.
        
    </ul>
    <br>    
    
    <a name="ModbusAttrSet"></a>
    <b>Set-Commands for Fhem as Modbus master operation</b>
    <ul>
        are created based on the attributes defining the data objects.<br>
        Every object for which an attribute like <code>obj-xy-set</code> is set to 1 will create a valid set option.<br>
        Additionally the attribute <code>enableControlSet</code> enables the set options <code>interval</code>, <code>stop</code>, <code>start</code>, <code>reread</code> as well as <code>scanModbusObjects</code>, <code>scanStop</code> and <code>scanModbusIds</code> (for devices connected with RTU / ASCII over a serial line).<br>
        Starting with Version 4 of the Modbus module enableControlSet defaults to 1.<br>
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
    <b>Get-Commands for Modbus master operation</b><br>
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
            enables the built in set commands like interval, stop, start and reread (see above).<br>
            Starting with Version 4 of the Modbus module enableControlSet defaults to 1. This attribute can however be used to disable the set commands by setting the attribute to 0<br>
        <br>
        
        please also notice the attributes for the physical modbus interface as documented in 98_Modbus.pm
        <br>
        
        the following list of attributes can be applied to any data object by specifying the objects type and address in the variable part. 
        For many attributes you can also specify default values per object type (see dev- attributes later) or you can specify an object attribute without type and address 
        (e.g. obj-len) which then applies as default for all objects:
        <li><b>obj-[cdih][1-9][0-9]*-reading</b></li> 
            define the name of a reading that corresponds to the modbus data object of type c,d,i or h and a decimal address (e.g. obj-h225-reading).<br>
            For master or passive operation this reading name will be used to create a reading for the modbus device itself. <br>
            For slave operation this can also be specified as deviceName:readingName to refer to the reading of another device inside Fhem whose value can be queried by an external Modbus master with the goven type and address.<br>
        <li><b>obj-[cdih][1-9][0-9]*-name</b></li> 
            defines an optional internal name of this data object (this has no meaning for fhem and serves mainly documentation purposes.<br>
        <li><b>obj-[cdih][1-9][0-9]*-set</b></li> 
            if set to 1 then this data object can be changed with a Fhem set command 
            which results in a modbus write request sent to the external slave device.<br>
            (works only if this device is a modbus master and for holding registers and coils 
            since discrete inputs and input registers can not be modified by definition).<br>
        <li><b>obj-[cdih][1-9][0-9]*-min</b></li> 
            this defines a lower limit to the value of this data object<br>
            If in master mode this applies to values written with a Fhem set command to an external slave device and is used for input validation.<br>
            If in slave mode this applies to values written by an external master device to Fhem readings.<br>
        <li><b>obj-[cdih][1-9][0-9]*-max</b></li> 
            this defines an upper limit to the value of this data object<br>
            If in master mode this applies to values written with a Fhem set command to an external slave device and is used for input validation.<br>
            If in slave mode this applies to values written by an external master device to Fhem readings.<br>
        <li><b>obj-[cdih][1-9][0-9]*-hint</b></li> 
            this is used in master mode for set options and tells fhemweb what selection to display for the set option (list or slider etc.)<br>
        <li><b>obj-[cdih][1-9][0-9]*-expr</b></li> 
            In master mode this defines a perl expression that converts the raw value read from an external slave device into a value that is stored in a Fhem reading.<br>
            In slave mode this defines a perl expression that converts the raw value written from an external master device into a value that is stored in a Fhem reading.<br>
            Inside the expression you can use $val to get the value or the array @val in case there are several values (e.g. when unpack produces more than one value)<br>
        <li><b>obj-[cdih][1-9][0-9]*-setexpr</b></li> 
            In master mode this defines a perl expression that converts the user specified value from the set command 
            to a raw value that can be sent to the external slave device with a write function code.<br>
            In slave mode this defines a perl expression that converts the value of a reading inside Fhem to a raw value that can be sent to the device 
            as a response to the read function code received from the external master device.<br>
            This is typically the inversion of -expr above.<br
            Inside the expression you can use $val to get the value or the array @val in case there are several values (e.g. when unpack produces more than one value)<br>
        <li><b>obj-[cdih][1-9][0-9]*-allowWrite</b></li> 
            this only applies to a Fhem Modbus device in slave mode. 
            If set to 1 it defines that a reading can be changed with a write function code by an external modbus master.<br>
        <li><b>obj-[cdih][1-9][0-9]*-ignoreExpr</b></li> 
            defines a perl expression that returns 1 if a value should be ignored and the existing reading should not be modified<br>
            In master mode this applies to values read from an external slave device.<br>
            In slave mode this applies to values written to Fhem readings by an external master device.<br>
            Inside the expression you can use $val to get the value or the array @val in case there are several values (e.g. when unpack produces more than one value)<br>
        <li><b>obj-[cdih][1-9][0-9]*-map</b></li> 
            In master mode defines a map to convert raw values read from an external device to more convenient strings that are then stored in Fhem readings
            or back (as reversed map) when a value to write has to be converted from the user set value to a raw value that can be written.<br>
            In slave mode defines a map to convert raw values received from an external device with a write function code to more convenient strings that are then stored in Fhem readings<br>
            or back (as reversed map) when a value to read has to be converted from the Fhem reading value to a raw value that can be sent back as response.<br>
            Example: 0:mittig, 1:oberhalb, 2:unterhalb<br>
        <li><b>obj-[cdih][1-9][0-9]*-format</b></li> 
            In master mode this defines a format string (see Perl sprintf) to format a value read from an external slave device before it is stored in a reading e.g. %.1f <br>
            In slave mode this defines a format string to format a value from a Fhem reading before it is sent back in a response to an external master <br>
        <li><b>obj-[cdih][1-9][0-9]*-len</b></li> 
            defines the length of the data object in registers. It defaults to 1. <br>
            Some devices store e.g. 32 bit floating point values in two registers. In this case you should set this attribute to two.<br>
            This setting is relevant both in master and in slave mode. The lenght has to match the length implied by the unpack code.
        <li><b>obj-[cdih][1-9][0-9]*-unpack</b></li> 
            defines the pack / unpack code to convert data types.<br>
            In master mode it converts the raw data string read from the external slave device to a reading or to convert from a reading to a raw format when a write request is sent to the external slave device.<br>
            In slave mode it converts the value of a reading in Fhem to a raw format that can be sent as a response to an external Modbus master or it converts the raw data string read from the external master device to a reading when the master is using a write function code and writing has been allowed.<br>
            For an unsigned integer in big endian format this would be "n", <br>
            for a signed 16 bit integer in big endian format this would be "s>", in little endian format it would be "s<" <br>
            and for a 32 bit big endian float value this would be e.g. "f>". (see the perl documentation of the pack function for more codes and details).<br>
            Please note that you also have to set a -len attribute (for this object or for the device) if you specify an unpack code that consumes data from more than one register.<br>
            For a 32 bit float e.g. len should be 2.<br>
        <li><b>obj-[cdih][1-9][0-9]*-revRegs</b></li> 
            this is only applicable to objects that span several input registers or holding registers. <br>
            When they are received from an external device then the order of the registers will be reversed before further interpretation / unpacking of the raw register string. The same happens before data is sent to an external device<br>
        <li><b>obj-[cdih][1-9][0-9]*-bswapRegs</b></li>
            After registers have been received and before they are sent, the byte order of all 16-bit values are swapped. This changes big-endian to little-endian or vice versa. This functionality is most likely used for reading (ASCII) strings from devices where they are stored as big-endian 16-bit values. <br>
            Example: original reading is "324d3130203a57577361657320722020". After applying bswapRegs, the value will be "4d3230313a2057576173736572202020"
            which will result in the ASCII string "M201: WWasser   ". Should be used with "(a*)" as -unpack value.<br>
        <li><b>obj-[cdih][1-9][0-9]*-decode</b></li> 
            defines an encoding to be used in a call to the perl function decode to convert the raw data string received from a device. 
            This can be used if the device delivers strings in an encoding like cp850 instead of utf8.<br>
        <li><b>obj-[cdih][1-9][0-9]*-encode</b></li> 
            defines an encoding to be used in a call to the perl function encode to convert raw data strings received from a device. 
            This can be used if the device delivers strings in an encoding like cp850 and after decoding it you want to reencode it to e.g. utf8.<br>
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
            </pre><br>
        
        <li><b>obj-[cdih][1-9][0-9]*-showGet</b></li> 
            If the Fhem Modbus device is in master mode, every reading can also be requested by a get command. However these get commands are not automatically offered in fhemweb. By specifying this attribute, the get will be visible in fhemweb.<br>
        <li><b>obj-[cdih][1-9][0-9]*-poll</b></li>
            If the Fhem Modbus device is in master mode, Fhem automatically creates read requests to the external modbus slave.
            If this attribute is set to 1 for an object then this obeject is included in the cyclic update request as specified in the define command for a Modbus master. 
            If not set, then the object can manually be requested with a get command, but it is not automatically updated each interval. 
            Note that this setting can also be specified as default for all objects with the dev- atributes described later.<br>
            This attribute is ignored in slave mode.<br>
        <li><b>obj-[cdih][1-9][0-9]*-polldelay</b></li> 
            this applies only to master mode. It allows to poll objects at a lower rate than the interval specified in the define command. 
            You can either specify a time in seconds or number prefixed by "x" which means a multiple of the interval of the define command.<br>
            If you specify a normal numer then it is interpreted as minimal time between the last read and another automatic read.<br>
            Please note that this does not create an additional interval timer. 
            Instead the normal interval timer defined by the interval of the define command will check if this reading is due or not yet. 
            So the effective interval will always be a multiple of the interval of the define.<br>
            <br>
            
        <li><b>dev-([cdih]-)*read</b></li> 
            specifies the function code to use for reading this type of object in master mode.
            The default is 3 for holding registers, 1 for coils, 2 for discrete inputs and 4 for input registers.<br>
        <li><b>dev-([cdih]-)*write</b></li> 
            specifies the function code (decimal) to use for writing this type of object in master mode. 
            The default is 6 for holding registers and 5 for coils. Discrete inputs and input registers can not be written by definition.<br>
            Some slave devices might need function code 16 for writing holding registers. In this case dev-h-write can be set to 16.
        <li><b>dev-([cdih]-)*combine</b></li> 
            This applies only to master mode. It defines how many adjacent objects of an external slave device can be read in one request. If not specified, the default is 1<br>

        <li><b>dev-([cdih]-)*addressErrCode</b></li> 
            This applies only if the Fhem Modbus device is in slave mode.
            defines which error code to send back to a master that requests an object with an address that is not configured in Fhem.<br>
            If nothing is specified, the error code 2 is used. If 0 is specified, then no error is sent back.<br>
        <li><b>dev-([cdih]-)*valueErrCode</b></li> 
            This applies only if the Fhem Modbus device is in slave mode.
            It defines which error code to send back to a master that tries to write a value to an object / reading where the value is lower than the specified minimum value or higher than the specified maximum value. (this feature is not implemented yet)<br>
            If nothing is specified, the error code 1 is used. If 0 is specified, then no error is sent back.<br>
        <li><b>dev-([cdih]-)*notAllowedErrCode</b></li> 
            This applies only if the Fhem Modbus device is in slave mode.
            It defines which error code to send back to a master that tries to write to an object / reading where writing has not been allowed with the .<br>
            If nothing is specified, the error code 1 is used. If 0 is specified, then no error is sent back.<br>
            
        <li><b>dev-([cdih]-)*defLen</b></li> 
            defines the default length for this object type. If not specified, the default is 1<br>
        <li><b>dev-([cdih]-)*defFormat</b></li> 
            defines a default format string to use for this object type in a sprintf function on the values read from the device.<br>
        <li><b>dev-([cdih]-)*defExpr</b></li> 
            defines a default Perl expression to use for this object type to convert raw values read. (see obj-...-expr)<br>
        <li><b>dev-([cdih]-)*defSetexpr</b></li> 
            defines a default Perl expression to use like -setexpr (see obj-...-setexpr)<br>
        <li><b>dev-[cdih][1-9][0-9]*-defAllowWrite</b></li> 
            this only applies to a Fhem Modbus device in slave mode. <br>
            If set to 1 it defines that readings can be changed with a write function code by an external modbus master.<br>

        <li><b>dev-([cdih]-)*defIgnoreExpr</b></li> 
            defines a default Perl expression to decide when values should be ignored.<br>
        <li><b>dev-([cdih]-)*defUnpack</b></li> 
            defines the default unpack code for this object type. <br>
        <li><b>dev-([cdih]-)*defRevRegs</b></li> 
            defines that the order of registers for objects that span several registers will be reversed before 
            further interpretation / unpacking of the raw register string<br>
        <li><b>dev-([cdih]-)*defBswapRegs</b></li> 
            per device default for swapping the bytes in Registers (see obj-bswapRegs above)<br>
        <li><b>dev-([cdih]-)*defDecode</b></li> 
            defines a default for decoding the strings read from a different character set e.g. cp850<br>
        <li><b>dev-([cdih]-)*defEncode</b></li> 
            defines a default for encoding the strings read (or after decoding from a different character set) e.g. utf8<br>
        <li><b>dev-([cdih]-)*defPoll</b></li> 
            if set to 1 then all objects of this type will be included in the cyclic update by default. <br>
        <li><b>dev-([cdih]-)*defShowGet</b></li> 
            if set to 1 then all objects of this type will have a visible get by default. <br>
        <li><b>dev-type-XYZ-unpack, -len, -encode, -decode, -revRegs, -bswapRegs, -format, -expr, -map</b></li> 
            define the unpack code, length and other details of a user defined data type. XYZ has to be replaced with the name of a user defined data type.
            use obj-h123-type XYZ to assign this type to an object.<br>
        <li><b>dev-([cdih]-)*allowShortResponses</b></li> 
            if set to 1 the module will accept a response with valid checksum but data lengh < lengh in header<br>
        <li><b>dev-h-brokenFC3</b></li> 
            if set to 1 the module will change the parsing of function code 3 and 4 responses for devices that 
            send the register address instead of the length in the response<br>
        <li><b>dev-c-brokenFC5</b></li> 
            if set the module will use the hex value specified here instead of ff00 as value 1 for setting coils<br>
        <li><b>dev-timing-timeout</b></li> 
            timeout for the device (defaults to 2 seconds)<br>
        <li><b>dev-timing-sendDelay</b></li> 
            delay to enforce between sending two requests to the device. Default ist 0.1 seconds.<br>
        <li><b>dev-timing-commDelay</b></li> 
            delay between the last read and a next request. Default ist 0.1 seconds.<br>
        <li><b>queueMax</b></li>
            max length of the queue for sending modbus requests as master, defaults to 200. <br>
            This atribute should be used with devices connected through TCP or on physical 
            devices that are connected via serial lines but not on logical modbus devices that use another physical device as IODev.<br>
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
