
  =======================================================================
   *** HMCCU/HMCCUDEV - Modules for FHEM - Homematic CCU integration ***
  =======================================================================

* Document covers HMCCU/HMCCUDEV version 1.9.
* Please read carefully before using the modules.

------------------------------------
 Content

1    HMCCU Introduction
1.1    HMCCU Description
1.2    HMCCU Requirements

2    HMCCU Usage
2.1    HMCCU Set Commands
2.2    HMCCU Get Commands
2.3    HMCCU Attributes
2.4    HMCCU Parameter File

3    HMCCUDEV Introduction
3.1    HMCCUDEV Description
3.2    HMCCUDEV Requirements

4    HMCCUDEV Usage
4.1    HMCCUDEV Set Commands
4.2    HMCCUDEV Get Commands
4.3    HMCCUDEV Attributes

5    Hints and Tips
5.1    Requesting information from CCU
5.2    Executing FHEM commands on CCU

------------------------------------


------------------------------------
 1 HMCCU Introduction
------------------------------------
------------------------------------
 1.1 HMCCU Description
------------------------------------

The modules HMCCU and HMCCUDEV provide a simple interface between FHEM and
a Homematic CCU2. HMCCU is the IO device for the communication with the CCU.
The states and values of CCU channels and variables are not updated automatically
in FHEM. You have to define an AT device with a HMCCU get command to ensure a
continuous update of CCU readings in FHEM.

------------------------------------
 1.2 HMCCU Requirements
------------------------------------

The module HMCCU requires the XML-API CCU addon (version >= 1.10). The FHEM
module requires the packages XML::Simple and File::Queue.
The module 88_HMCCU.pm must be copied into folder FHEM under the FHEM installation
directory.


------------------------------------
 2 HMCCU Usage
------------------------------------

Define a new IO device for communication with Homematic CCU:

   define <name> HMCCU <hostname_or_IP>

The only parameter is the name or the IP address of the Homematic CCU. All
other adjustments are done by setting attributes.
Some commands use channel or datapoint addresses. A channel address has the
following format:

   [<interface>.]<device-address>:<channel-number>
   
The default value for <interface> is BidCoS-RF. A datapoint is identified by

   [<interface>.]<device-address>:<channel-number>.<datapoint-name>
   
or

   <channel-name>.<datapoint-name>
   
IMPORTANT NOTE: During device definition HMCCU reads the available CCU devices
and channels via XML-API. After a reload of the module this must be repeated
by using command 'get devicelist'. Otherwise HMCCU and HMCCUDEV won't work
correctly. It's recommended to define an automatic device synchronization 
with AT and 'get devicelist'.


------------------------------------
 2.1 HMCCU Set commands
------------------------------------

If attribute 'stateval' is set the specified string substitutions are applied
before setting the device state, a variable or a datapoint value. This is
important because CCU states are often 'true' or 'false' while in FHEM one like
to use 'on' or 'off'. So setting 'stateval' to 'on:true,off:false' will ensure
that FHEM commands 'on' and 'off' are replaced by 'true' and 'false' before
transmitting them to the CCU.

Set state of a CCU channel:

   set <name> devstate {<channel-name>|<channel-address>} <value> [...]

   Parameters <channel-name> or <channel-address> refer to the CCU device
   channel with datapoint STATE. If more than one <value> is specified the
   values are concatinated by blanks to a single value.

Set value of a CCU device datapoint:

   set <name> datapoint {<channel-name>|<channel-address>.<datapoint> <value> [...]

   Parameters are the same as with 'devstate' command. In addition the name
   of a CCU channel datapoint must be specified.

Set value of a CCU system variable:

   set <name> var <variable> <value> [...]

   The variable must exist in CCU. It's not created automatically.

Execute CCU program:

   set <name> execute <program>

   The program is executed even it's deactivated in CCU.

Clear CCU alarms:

   set <name> clearmsg


------------------------------------
 2.2 HMCCU Get commands
------------------------------------

If attribute 'ccureadings' is set to 1 (default) the results of the get 
commands are stored in readings. The reading names by default correspond
to the CCU datapoints, including the channel-name. By setting the attribute
'ccureadingformat' reading names can be changed to channel-address and
datapoint name. The attribute 'ccureadingformat' is ignored if the same
attribute is defined in a client device.
If attribute 'ccureadings' is set to 0 the results of the get commands
are displayed in the browser window. No readings will be set in this case.
Some get commands allow an optional parameter <reading>. If this parameter
is specified the CCU value is stored in FHEM using this reading name.
With attribute 'substitute' you can define expressions which are substituted
by strings before CCU values are stored in readings. For example if CCU
reports device states as 'true' or 'false' these values can be replaced with
'open' or 'closed' by setting 'substitute' to 'true:open,false:closed'.
The attribute 'substitute' is ignored if the same attribute is defined
in a client device.

Get values of channel datapoints:

   get <name> channel {<channel-name>|<channel-address>}[.<datapoint_exp>] 

   Attention: There's no blank between channel and datapoint. If datapoint
   is not specified all datapoints will be read. The command accepts a
   regular expression as parameter datapoint.

Get value of datapoint:

   get <name> datapoint {<channel-name>|<channel-address>}.<datapoint>
   
Read list of devices and channels from CCU:

   get <name> devicelist

Get state of channel:

   get <name> devstate {<channel-name>|<channel-address>} [<reading>]

   Specified channel must contain the datapoint 'STATE'.

Get multiple channels and datapoints:

   get <name> parfile [<parfile>]

   If attribute 'parfile' is set parameter <parfile> can be omitted.
   See parameter file description below.

Get CCU variable values:

   get <name> vars <varname_exp>

   Variable name can be a regular expression. Variables are stored
   as readings with same name as in CCU.


------------------------------------
 2.3 HMCCU Attributes
------------------------------------

Set reading name format (default is 'name'):

   attr <name> ccureadingformat { name | address }
   
Control reading creation (default is 1):

   attr <name> ccureadings { 0 | 1 }

Remove character from CCU device or variable specification in set
commands:

   attr <name> stripchar <character>

   If a variable name ends with the specified character this
   character will be removed.

Specify name of parameter file for command 'get parfile':

   attr <name> parfile <parfile>

Specify text substitutions for values in set commands:

   attr <name> stateval <text1>:<subtext1>[,...]

Specify text substitutions for values returned by get commands:

   attr <name> substitute <regexp1>:<text1>[,...]


------------------------------------
 2.4 HMCCU Parameter files
------------------------------------

A parameter file contains a list of CCU channel or datapoint
definitions. Each line can contain a text substitution rule. A parameter
file is used by command 'get parfile'.
The format of a parfile entry is:

  <channel-name>|<channel-address>[.<datapoint_exp>] [<regexp1>:<subtext1>[,...]]

First part corresponds to command 'get channel'. Empty lines and lines starting
with a '#' are ignored.


------------------------------------
 3 HMCCUDEV Introduction
------------------------------------
------------------------------------
 3.1 HMCCUDEV Description
------------------------------------

HMCCUDEV is used to define client devices. HMCCU can be used standalone (without
defining client devices).

------------------------------------
 3.2 HMCCUDEV Requirements
------------------------------------

See 1.2 HMCCU Requirements. The module 88_HMCCUDEV.pm must be copied into folder
FHEM under the FHEM installation directory.


------------------------------------
 4 HMCCUDEV Usage
------------------------------------

Define a new client device:

   define <name> HMCCUDEV {<Device-Name>|<Device-Address>} [<StateChannel>] [readonly]
   
Parameter <Device-Address> is the CCU device address without the channel number.
The CCU device must be known by HMCCU. If the device can't be found the device 
list of the HMCCU device must be updated with command 'get devicelist'.
The Parameter <StateChannel> is the number of the channel which contains the
datapoint 'STATE'. Because not every CCU device has a 'STATE' datapoint this 
parameter is optional. The state channel number can also be set with the attribute
command.
The keyword 'readonly' declares a device as read only (i.e. a sensor). For read
only devices no set command is available.

------------------------------------
 4.1 HMCCUDEV Set Commands
------------------------------------

Set value of datapoint:

   set <name> datapoint <channel-number>.<datapoint-name> <value> [...]
   
Set state of device:

   set <name> devstate <value>
   set <name> <state-value>

   If attribute 'statevals' is defined 'devstate' can be ommitted. The channel
   number which contains datapoint 'STATE' must be set during device definition
   or via attribute 'statechannel'. If no state channel is specified the command
   is not available.
   
------------------------------------
 4.2 HMCCUDEV Get Commands
------------------------------------

Get value of datapoint:

   get <name> datapoint <channel-number>.<datapoint-name>
   
Get state of device:

   get <name> devstate
   
   Requires the specification of the channel number which contains datapoint
   'STATE'. See also command 'set devstate'.
   
------------------------------------
 4.3 HMCCUDEV Attributes
------------------------------------

Client device attributes overwrite corresponding HMCCU attributes!

Set reading name format (default is 'name'):

   attr <name> ccureadingformat { name | address | datapoint }
   
   If set to 'datapoint' the reading name is the datapoint name without channel.
   
Control reading creation (default is 1):

   attr <name> ccureadings { 0 | 1 }
   
Specify IO device for client device:

   attr <name> IODev <HMCCU-Device>
   
   Normally this is set automatically during HMCCUDEV device definition.
   
Specify channel number of STATE datapoint:

   attr <name> statechannel <channel-number>
   
   If no statechannel is set the command set devstate fails.

Specify text substitutions for values in set commands:

   attr <name> stateval <text1>:<subtext1>[,...]
   
   The values <textn> are available as set commands, i.e.
      attr switch1 stateval on:true,off:false
	  set switch1 on
	  set switch1 off
	  set switch1 devstate on

Specify text substitutions for values returned by get commands:

   attr <name> substitute <regexp1>:<text1>[,...]

   
------------------------------------
 5.2 Requesting information from CCU
------------------------------------

By using XML-API one can query device names, channel names, channel addresses
and datapoint names from CCU. The following request queries device and channel
information:

   http://ccuname-or-ip/config/xmlapi/devicelist.cgi?show_internal=1

The following request returns a list of datapoints with current values:

   http://ccuname-or-ip/config/xmlapi/statelist.cgi?show_internal=1
   
   
------------------------------------
 5.1 Executing FHEM commands on CCU
------------------------------------

It's possible to execute FHEM commands from CCU via the FHEM telnet port.
The following shell script encapsulates the necessary commands. It can
be placed somewhere under /etc/config/addons directory in CCU. The script
requires the installation of the netcat command (nc) on CCU (search for
the binary in google and install it somewhere in /etc/config/addons).

--- Start of script ---
#!/bin/sh

# Set name or IP address and port of FHEM server
FHEM_SERVER="myfhem"
FHEM_PORT=7072

# Set path to nc command
NCCMD="/etc/config/addons/scripts"

if [ $# -ne 1 ]; then
	echo "Usage: $0 Command"
	exit 1
fi

echo -e "$1\nquit\n" | $NCCMD/nc $FHEM_SERVER $FHEM_PORT
--- End of script ---

The script should be called from a CCU program by using the CUXD exec object
(requires installation of CUxD). If FHEM command contains blanks it should be
enclosed in double quotes.


*** Have fun! zap ***

