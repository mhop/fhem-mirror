
  =======================================================================
   *** HMCCU/HMCCUDEV - Modules for FHEM - Homematic CCU integration ***
  =======================================================================

* Document covers HMCCU/HMCCUDEV/HMCCUCHN version 2.8
* Please read carefully before using the modules.
* Last modified: 24.02.2016

----------------------------------------------
 Content
----------------------------------------------
1    HMCCU Introduction
1.1    HMCCU Description
1.2    HMCCU Requirements & Installation

2    HMCCU Usage
2.1    HMCCU Set Commands
2.2    HMCCU Get Commands
2.3    HMCCU Attributes
2.4    HMCCU Parameter File
2.5    RPC daemon
2.6    Events

3    HMCCUDEV Introduction
3.1    HMCCUDEV Description
3.2    HMCCUDEV Requirements

4    HMCCUDEV Usage
4.1    HMCCUDEV Set Commands
4.2    HMCCUDEV Get Commands
4.3    HMCCUDEV Attributes

5    HMCCUCHN Usage
5.1    HMCCUCHN Set Commands
5.2    HMCCUCHN Get Commands
5.3    HMCCUCHN Attributes

6    Hints and Tips
6.1    Requesting information from CCU
6.2    Executing FHEM commands on CCU
6.3    Use RAM disk for /tmp on Raspbian
----------------------------------------------


====================================
 1 HMCCU Introduction
====================================
------------------------------------
 1.1 HMCCU Description
------------------------------------

The modules HMCCU, HMCCUDEV and HMCCUCHN provide a simple interface between FHEM
and a Homematic CCU2. HMCCU is the IO device for the communication with the CCU.
The states and values of CCU channels and variables are not updated automatically
in FHEM. You have to define AT devices with get commands to ensure a continuous
update of CCU readings in FHEM or use the external RPC server.

NOTE: Because FHEM doesn't support the same set of special characters for devices
and channels some characters are replaced automatically when storing CCU values
as readings in FHEM. The character ':' is replaced by '.'. All characters which
are not matching the expression [A-Za-z\d_\.-] are replaced by '_'.

--------------------------------------
 1.2 HMCCU Requirements & Installation
--------------------------------------

The module HMCCU no longer requires the XML-API CCU addon. The FHEM module requires
the packages LWP::UserAgent, Time::HiRes, RPC::XML::Client  and RPCQueue.
The RPC server ccurpcd.pl requires the packages RPC::XML::Server, RPC::XML::Client,
RPCQueue and IO::Socket::INET.
All module files 88_HMCCU*, RPCQueue.pm  and the RPC daemon ccurpcd.pl must be copied
into the folder FHEM under the FHEM installation directory. 

NOTE: RPCQueue.pm is a bug fixed copy of File::Queue and part of the HMCCU installation
package. It's not available via CPAN!


====================================
 2 HMCCU Usage
====================================

Define a new IO device for communication with Homematic CCU:

   define <name> HMCCU <hostname_or_IP>

The only parameter is the name or the IP address of the Homematic CCU. All
other adjustments are done by setting attributes.
Some commands use device, channel or datapoint addresses. A channel address has
the following format:

   [<interface>.]<device-address>:<channel-number>

A device address is a channel address without the channel number. The default
value for <interface> is "BidCoS-RF". A datapoint is identified by

   <channel-address>.<datapoint-name>
   
or

   <channel-name>.<datapoint-name>

A <channel-name> or a <device-name> is the alias for an device or channel defined
in the CCU.

If a command allows parameters <device> or <channel> either name or address can
be used.

IMPORTANT NOTE: During device definition HMCCU reads the available CCU devices.
This request must be repeated by using command 'get devicelist' after a reload
of the module or after modification or definition of devices in the CCU. Otherwise
HMCCU, HMCCUDEV and HMCCUCHN won't work correctly. It's recommended to define
an automatic daily device synchronization with AT and command 'get <name> devicelist'.

------------------------------------
 2.1 HMCCU Set commands
------------------------------------

If attribute 'stateval' is set the specified string substitutions are applied
for values before setting the device state, a variable or a datapoint value.
This is important because CCU states are often 'true' or 'false' while in FHEM
one like to use 'on' or 'off'. So i.e. setting 'stateval' to 'on:true,off:false'
will ensure that FHEM commands 'on' and 'off' are replaced by 'true' and 'false'
before transmitting them to the CCU.

Set configuration parameters of CCU device or channel:

   set <name> config {<device>|<channel>} [<rpcport>] <parameter>=<value> [...]

   Set configuration parameters via RPC set request. If <rpcport> is not specified
   port 2001 (BidCos) is used.
   NOTE: Some parameter sets (i.e. time schedules for thermostat devices) must
   always be set completely (at least for one day). Otherwise command is not
   executed.

Set state of a CCU channel:

   set <name> devstate <channel> <value> [...]

   Parameter <channel> refers to the CCU device channel with datapoint STATE.
   This default datapoint can be changed by setting attribute 'statedatapoint'.
   If more than one <value> is specified the values are concatinated by blanks
   to one text string.

Set value of a CCU device datapoint:

   set <name> datapoint <channel>.<datapoint> <value> [...]

   Parameters correspond to 'devstate' command. In addition the name of a CCU
   channel datapoint must be specified.

Set value of a CCU system variable:

   set <name> var <variable> <value> [...]

   The variable must exist in CCU. It's not created automatically.

Execute CCU program:

   set <name> execute <program>

   The program is executed even if it's deactivated in CCU.

Execute Homematic script:

   set <name> hmscript <script-file>
   
   If script returns parameter=value pairs separated by newlines via standard
   output these values are stored as readings.

Restart RPC server:

   set <name> restartrpc

   The command will fail if RPC server is not running. The restart may take up
   to 4 minutes. During this time HMCCU devices cannot be used.
   
 
------------------------------------
 2.2 HMCCU Get commands
------------------------------------

If attribute 'ccureadings' is set to 1 (default) the results of the get commands
are stored in readings. By default the reading names correspond to the CCU
datapoints, including the channel-name. This behaviour can be changed by setting
the attribute 'ccureadingformat'. If attribute 'ccureadings' is set to 0 the
results of the get commands are displayed in the browser window. No readings will
be set in this case. Some get commands allow an optional parameter <reading>. If
this parameter is specified the CCU value is stored in FHEM using this reading name.

The attribute 'updatemode' controls wether readings are updated in the IO device,
in client devices only or both in IO device and client devices.

With attribute 'substitute' one can define expressions which are substituted by
strings before CCU values are stored in readings. For example if CCU reports
device states as "true" or "false" these values can be replaced by "open" or
"closed" by setting 'substitute' to "true:open,false:closed". The attribute
'substitute' is ignored if the same attribute is defined in a client device.

If substitutions should apply only to some datapoints the datapoint name can be
added as a prefix to the substitution rules. Several rules can be separated by
a semicolon. Example: define 2 datapoint related rules and 1 standard rule:

STATE!(1|true):on,(0|false):off;LOWBAT!(1|true):yes,(0|false):no;true:ok,false:error

For datapoint STATE 1/true and 0/false are replaced by on and off. For datapoint
LOWBAT 1/true and 0/false are replaced by yes and no. For all other datapoints
true and false are subsituted by ok and error.

Get values of channel datapoints (supports multiple channels):

   get <name> channel <channel>[.<datapoint_exp>] [...]

   Attention: There's no blank between channel and datapoint. If no regular
   expression datapoint_exp is specified all datapoints will be read.

Get value of datapoint:

   get <name> datapoint <channel>.<datapoint> [<reading>]
   
Display list of channels and datapoints of a device:

   get <name> deviceinfo <device>

Read list of devices and channels from CCU:

   get <name> devicelist [dump]
   
   This command must be executed after HMCCU is reloaded or after devices are
   defined, modified or deleted in the CCU. Otherwise HMCCU does not know
   the alias names of CCU devices and most of the get/set commands will fail.
   With option 'dump' all devices/channels are displayed in browser window.

Get state of channel:

   get <name> devstate <channel> [<reading>]

   Specified channel must contain the datapoint 'STATE'. This default datapoint
   can be modified by setting attribute 'statedatapoint'.

Update all client device datapoints / readings:

   get <name> update [<devexp> [{ State | Value }]]

   If parameter <devexp> is specified only client devices with device name
   matching regular expression will be updated. A client device is only updated
   if its attribute 'ccureadings' is set to 1.
   For more information about 'State' and 'Value' see description of attribute
   'ccuget' in HMCCU section.

Get multiple channels and datapoints:

   get <name> parfile [<parfile>]

   If attribute 'parfile' is set parameter <parfile> can be omitted. See
   parameter file description below.

Get CCU variable values:

   get <name> vars <varname_exp>

   Variable name can be a regular expression. Variables are stored as readings
   with same name as in CCU.

Check if RPC server process is running:

   get <name> rpcstate

   The state of the RPC process(es) is displayed in browser window.


------------------------------------
 2.3 HMCCU Attributes
------------------------------------

Set filter for datapoint readings (default is '.*'):

   attr <name> ccureadingfilter <rule>[,...]

   Only datapoints matching the specified expression will be stored as
   readings. Filter is ignored by commands 'get datapoint' and 'get channel'.
   Filter is used by command 'get update' and for RPC server events.
   The syntax of a filter rule is:

   [<channel-name-exp>!]<datapoint-exp>

   If a regular expression for channel name is specified the rule applies
   only to datapoints of this channel. Example: A virtual device group contains
   channels and datapoints of different devices. For channel G_Heat we want
   to get datapoint CONTROL_MODE. For all channels starting with D_Heat we 
   want to get datapoints LOWBAT and every datapoint witch match TEMP:

   attr <name> ccureadingfilter G_Heat!CONTROL_MODE,^D_Heat!(LOWBAT|TEMP)

Set query method for CCU device datapoints (default is 'Value'):

   attr <name> ccuget { State | Value }

   Datapoint values can be queried by State() or Value(). The Value() method
   returns the datapoint value stored in the CCU. The State() method queries
   the device directly. The response time of State() is slightly higher and
   it will consume battery power of the queried device because a connection
   is established. But in some cases it can be necessary to use State(). In
   those cases one should set the 'ccuget' attribute in the affected client
   device. Setting this attribute in the IO device will slow down the
   communication between FHEM and CCU because this setting applies to all
   client devices. Set commands always use State().

Set reading name format (default is 'name'):

   attr <name> ccureadingformat { name | address }

Enable tracing of get commands:

   attr <name> ccutrace <expression>

   Enable tracing (loglevel 1) for devices / channels where CCU device name
   or device address matches specified expression. Using '.*' as expression
   is not a good idea because it will generate a lot of log data ;-)

Control reading update in IO and client devices (default is 'hmccu'):

   attr <name> updatemode { hmccu | both | client }

   NOTE: If one use client devices this attribute should be set to 'client'.
   Otherwise all readings of client devices will be stored in the IO device
   too. As an alternative one can set attribute 'ccureadings' to 0.

Control reading creation (default is 1):

   attr <name> ccureadings { 0 | 1 }

   If one uses the IO device only for communication of client devices with
   CCU set this attribute to 0.

Set datapoint for "get/set devstate" commands (default is 'STATE'):

   attr <name> statedatapoint <datapoint>

   The value of this datapoint is stored in internal STATE of the FHEM device
   and in reading 'state'.
   
Remove character from CCU device or variable specification in set commands:

   attr <name> stripchar <character>

   If a variable name ends with the specified character this character will be
   removed.

Specify name of parameter file for command "get parfile":

   attr <name> parfile <parfile>

Set interval for RPC event processing:

   attr <name> rpcinterval { 3 | 5 | 10 }
   
   Set interval in seconds for reading RPC events from RPC event queue. 
   
Set port(s) of CCU RPC interface (default is 2001):

   attr <name> rpcport <port>[,...]

   For each port specified a separate instance of the RPC server process will
   be started when setting attribute 'rpcserver' to 'on'.
   Usual ports: 2000=Wired, 2001=BidCos-RF

Set RPC event queue file (default is /tmp/ccuqueue):

   attr <name> rpcqueue <filename>
   
   Parameter <filename> is a prefix. The RPC event queue consists of two files
   with extension .idx and .dat. The RPC port is part of the names too.

Start/stop RPC server:

   attr <name> rpcserver { on | off }

   After starting the RPC server it takes 3 minutes until events from CCU arrive.
   Stopping RPC server can take up to 30 seconds.

Specify text substitutions for values in set commands:

   attr <name> statevals <text>:<subtext>[,...]
   
   NOTE: Parameter <text> is not a regular expression. Example: set datapoint to
   true/false if on/off is specified in set command:

   attr <name> statevals on:true,off:false

Set format of readings with floating point numbers (default is 0):

   attr <name> stripnumber { 0 | 1 | 2 }

   0 = Floating point numbers are stored as read from CCU.
   1 = Trailing zeros are stripped except one digit.
   2 = All trailing zeros and the decimal point are stripped.

Specify text substitution rules for values returned by get commands:

   attr <name> substitute <subst_rule>[;...]

   The substitution rules are applied to values read from CCU before they are
   stored as readings. The syntax of a substitution rule is:

   [<datapoint>!]<regexp>:<subtext>[,...]

   If a datapoint is specified the rule applies only to values of this datapoint.

   NOTE: Floating point numbers are ignored. Integer numbers are only substituted
   if they match the complete regular expression.

   Example: Substitute values of datapoints STATE and LOWBAT.

   STATE!(1|true):on,(0|false):off;LOWBAT!(1|true):yes,(0|false):no

   NOTE: get commands return true/false for boolean values while RPC server 
   returns 1/0. 


------------------------------------
 2.4 HMCCU Parameter files
------------------------------------

A parameter file contains a list of CCU channel or datapoint definitions. Each
line can contain a text substitution rule. A parameter file is used by command
"get parfile". The format of a parfile entry is:

  <channel>[.<datapoint_exp>] [<substitution_rule>[;...]]

First part corresponds to command 'get channel'. Empty lines and lines starting
with a '#' are ignored.

------------------------------------
 2.5 RPC daemon
------------------------------------

Because of several restrictions of FHEM regarding socket communication and
forking external processes the RPC daemon is realized as a standalone process.
The communication between ccurpcd and FHEM happens by using a file based FIFO
queue. On systems running on SD cards like Raspberry PI it's recommended to
set the attribute 'rpcqueue' pointing to a file located on a RAM disk (see 
section 6.3 for more information about setting up a RAM disk on Raspbian).

ccurpcd is started under user 'fhem'. So this user must have the permission to
read and write data on from/into queue file and also write log file entries in
the standard FHEM log directory. The daemon writes error messages to file
ccurpcd_<port>.log in the FHEM log directory.

The RPC daemon is controlled via attribute 'rpcserver'. After setting this 
attribute to "on" the HMCCU module will start ccurpcd as a separate process.
The RPC process is started even if attribute 'rpcserver' is already set to
"on".
The PID of ccurpcd is stored in the INTERNAL  "RPCPID". After start of ccurpcd
it takes 3 minnutes until first events from CCU arrive in FHEM (don't know
why - ask EQ-3 ;-)

The RPC daemon is stopped when setting 'rpcserver' to "off" or by sending a
signal "INT" to the process. Because ccurpcd will gracefully shutdown the 
CCU interface it can take some time until process disappears. After process
has been terminated the internal "RPCPID" is deleted.

The current state of the RPC process is stored in the INTERNAL 'RPCState':

  starting = RPC server is starting. This phase can take 3 minutes.
  running  = RPC server is started an waiting for CCU events.
  stopping = RPC server is shutting down. Signal SIGINT sent to process.
  stopped  = RPC server stopped.
  restarting = RPC server is restarting.

For more information see attributes 'rpcport', 'rpcserver', 'rpcqueue' and
'rpcinterval'.

------------------------------------
 2.6 Events
------------------------------------

In some situations HMCCU will trigger events:

  "RPC server restarting"
  "RPC server starting"
  "RPC server running"
  "RPC server stopped"
  "No events from CCU since 300 seconds"
  "n devices deleted in CCU"
  "n devices added in CCU"

FHEM can react on these events by using command 'notify'. Example: If new
devices added in CCU the IO device should execute command 'get devicelist'
to enable the usage of the new devices in FHEM.


====================================
 3 HMCCUDEV Introduction
====================================
------------------------------------
 3.1 HMCCUDEV Description
------------------------------------

HMCCUDEV is used to define HMCCU client devices for CCU devices. NOTE: HMCCU
can be used standalone without defining client devices but it's highly
recommended to use client devices because every Homematic device type has
its own functionality which must be handled different.

------------------------------------
 3.2 HMCCUDEV Requirements
------------------------------------

See 1.2 HMCCU Requirements. The module 88_HMCCUDEV.pm must be copied into folder
FHEM under the FHEM installation directory. An IO device of type HMCCU must be 
defined before defining any client devices.


====================================
 4 HMCCUDEV Usage
====================================

Define a new client device:

   define <name> HMCCUDEV <device> [<state-channel>] [readonly]

Define a new client device group:

   define <name> HMCCUDEV <ccu-group-device> [<state-channel>] [readonly]
      {group={<device>|<channel>}[,...]|groupexp=<expression>}

Define a new virtual device:

   define <name> HMCCUDEV virtual
      {group={<device>|<channel>}[,...]|groupexp=<expression>}
   
The parameter <device> is the CCU device name or address. The CCU device must
be known by HMCCU. If the device can't be found the device list of the HMCCU
device must be updated with command 'get devicelist'.
The default channel number for devstate commands can be specified with parameter
<state-channel> or via attribute 'statechannel'. The keyword 'readonly' declares
a device as read only (i.e. a sensor). For read only devices no set command is
available.
HMCCUDEV also supports CCU group devices (i.e. groups of heating controls). The
member devices of a CCU group device must be specified with options 'group' or
'groupexp'. If readings of the member devices are updated the readings in the
group devices will be updated too.
Virtual devices are a special kind of group devices. A virtual device is a group
of client devices which only exists in FHEM. The only available command for
virtual devices is 'get update'.

------------------------------------
 4.1 HMCCUDEV Set Commands
------------------------------------

Set value of control datapoint:

   set <name> control <value>

   Attribute 'controldatapoint' must be set.

Set value of datapoint:

   set <name> datapoint <channel-number>.<datapoint-name> <value> [...]
   
Set state of device:

   set <name> devstate <value>
   set <name> <state-value>

   If attribute 'statevals' is defined 'devstate' can be ommitted. The channel
   number which contains datapoint 'STATE' must be set via attribute 'statechannel'.
   If no state channel is specified the command is not available. The default
   datapoint 'STATE' can be modified by setting attribute 'statedatapoint'.

Toggle device state:

   set <name> toggle

   This command requires that attribute 'statevals' contains at least 2 states.
   

------------------------------------
 4.2 HMCCUDEV Get Commands
------------------------------------

Get value of datapoint:

   get <name> datapoint <channel-number>[.<datapoint-name>]
   
   If no datapoibt is specified all datapoints for specified channel are read.

Get multiple datapoints of channel (supports multiple channels):

   get <name> channel <channel-number>[.<datapoint-expr>] [...]

   Parameter <datapoint-expr> is a regular expression. Default is .* (query all
   datapoints of a channel).
   
Display list of channels and datapoints of a device:

   get <name> deviceinfo

Get state of device:

   get <name> devstate
   
   Requires the specification of the channel number which contains datapoint
   "STATE" by using attribute 'statechannel'. The default datapoint "STATE"
   can be modified by setting attribute 'statedatapoint'.
   
Update all datapoints / readings of channel:

   get <name> update [{ State | Value }]

   For more information about 'State' and 'Value' see description of attribute
   'ccuget' in HMCCU section.

------------------------------------
 4.3 HMCCUDEV Attributes
------------------------------------

Client device attributes overwrite corresponding HMCCU attributes!

Set query method for CCU device datapoints (default is 'Value'):

   attr <name> ccuget { State | Value }

   For more information see description of attribute 'ccuget' in HMCCU section.

Force IO device to verify set commands by get commands (default is 0):

   attr <name> ccuverify { 0 | 1 }

   Note: This won't work if set/get datapoints are different. i.e. auto operation
   modes of thermostat devices is set with datapoint AUTO_MODE but for reading
   the operation mode datapoint CONTROL_MODE must be used. In this case command
   verification will fail.

Set filter for datapoint readings (default is '.*'):

   attr <name> ccureadingfilter <datapoint-expr>

   Only datapoints matching the specified expression will be stored as
   readings. Filter is ignored by commands 'get datapoint' and 'get channel'.
   Filter is used by command 'get update' and for RPC server events.

Set reading name format (default is 'name'):

   attr <name> ccureadingformat { name | address | datapoint }
   
   If set to 'datapoint' the reading name is the datapoint name without channel.
   
Control reading creation (default is 1):

   attr <name> ccureadings { 0 | 1 }

Enable support for FHEM UI widgets like sliders:

   attr <name> controldatapoint <channel-number>.<datapoint-name>

   The following example demonstrates how to define a slider for setting the
   destination temperature of a thermostat device in range from 10 up to 25
   degrees:

      attr mythermodev controldatapoint 2.SET_TEMPERATURE
      attr mythermodev webCmd control
      attr mythermodev widgetOverride control:slider,10,1,25

   When this attribute is set HMCCU inserts a new reading 'control'. This is
   necessary to set widget to current value of the datapoint.

Set datapoint for 'devstate' command (default is "STATE"):
   
   attr <name> statedatapoint <datapoint>
   
Set format of internal STATE:

   attr <name> ccustate <format-string>

   The parameter <format-string> is identical to standard attribute 'stateFormat'.
   In addition attribute 'stateFormat' must be set to {HMCCU_State()}.
   
Specify IO device for client device:

   attr <name> IODev <HMCCU-Device>
   
   Normally this is set automatically during HMCCUDEV device definition.
   
Specify channel number of STATE datapoint:

   attr <name> statechannel <channel-number>
   
   If no statechannel is set the commands 'get/set devstate' are not available.

Specify text substitutions for values in set commands:

   attr <name> stateval <text1>:<subtext1>[,...]
   
   The values <textn> are available as set commands, i.e.
      attr switch1 stateval on:true,off:false
	  set switch1 on
	  set switch1 off
	  set switch1 devstate on

Set format of readings with floating point numbers (default is 0):

   attr <name> stripnumber { 0 | 1 | 2 }

   0 = Floating point numbers are stored as read from CCU (i.e. with trailing zeros).
   1 = Trailing zeros are stripped from floating point numbers except one digit.
   2 = All trailing zeros are stripped from floating point numbers.

Specify text substitutions for values returned by get commands:

   attr <name> substitute <substitution_rule>[;...]

   For detailed information see description of HMCCU attribute 'substitute'.
   
   
====================================
 5 HMCCUCHN Usage
====================================

Define a new client device:

   define <name> HMCCUCHN {<Channel-Name>|<Channel-Address>} [readonly]
   
Parameter <Channel-Address> is the CCU channel address including the channel
number. If <Channel-Name> is specified it must be known by HMCCU. If the channel
can't be found the device list of the HMCCU device must be updated with command
'get devicelist'. The keyword 'readonly' declares a channel as read only (i.e.
a sensor). For read only channels no set command is available.

------------------------------------
 5.1 HMCCUCHN Set Commands
------------------------------------

Set value of control datapoint:

   set <name> control <value>

   Attribute 'controldatapoint' must be set.

Set value of datapoint:

   set <name> datapoint <datapoint-name> <value> [...]
   
Set state of channel:

   set <name> devstate <value>
   set <name> <state-value>

   If attribute 'statevals' is defined 'devstate' can be ommitted. The default
   datapoint "STATE" can be modified by setting attribute 'statedatapoint'.

Toggle channel state:

   set <name> toggle

   This command requires that attribute 'statevals' contains at least 2 states.

   
------------------------------------
 4.2 HMCCUCHN Get Commands
------------------------------------

Get value of datapoint:

   get <name> datapoint [<datapoint-name>]
   
   If no datapoint is specified all datapoints are read.
   
Get multiple datapoints:

   get <name> channel [<datapoint-exp>]
   
   Parameter <datapoint-expr> is a regular expression. Default is .* (query all
   datapoints of a channel).
   
Get state of device:

   get <name> devstate
   
   The default datapoint "STATE" can be modified by setting attribute
   'statedatapoint'.

Update all datapoints / readings of channel:

   get <name> update [{ State | Value }]

   For more information about 'State' and 'Value' see description of attribute
   'ccuget' in HMCCU section.
   
------------------------------------
 4.3 HMCCUCHN Attributes
------------------------------------

Client device attributes overwrite corresponding HMCCU attributes!

Set query method for CCU device datapoints (default is 'Value'):

   attr <name> ccuget { State | Value }

   For more information see description of attribute 'ccuget' in HMCCU section.

Force IO device to verify set commands by get commands (default is 0):

   attr <name> ccuverify { 0 | 1 }

   Note: This won't work if set/get datapoints are different. i.e. auto operation
   modes of thermostat devices is set with datapoint AUTO_MODE but for reading
   the operation mode datapoint CONTROL_MODE must be used. In this case command
   verification will fail.

Set filter for datapoint readings (default is '.*'):

   attr <name> ccureadingfilter <datapoint-expr>

   Only datapoints matching the specified expression will be stored as
   readings. Filter is ignored by commands 'get datapoint' and 'get channel'.
   Filter is used by command 'get update' and for RPC server events.

Set reading name format (default is 'name'):

   attr <name> ccureadingformat { name | address | datapoint }
   
   If set to 'datapoint' the reading name is the datapoint name without channel.
   
Control reading creation (default is 1):

   attr <name> ccureadings { 0 | 1 }

Enable support for FHEM UI widgets like sliders:

   attr <name> controldatapoint <datapoint-name>

   The following example demonstrates how to define a slider for setting the
   destination temperature of a thermostat device in range from 10 up to 25
   degrees:

      attr mythermodev controldatapoint SET_TEMPERATURE
      attr mythermodev webCmd control
      attr mythermodev widgetOverride control:slider,10,1,25

   When this attribute is set HMCCU inserts a new reading 'control'. This is
   necessary to set widget to current value of the datapoint.

Set datapoint for "devstate" command (default is "STATE"):
   
   attr <name> statedatapoint <datapoint>

Set format of internal STATE:

   attr <name> ccustate <format-string>

   The parameter <format-string> is identical to standard attribute 'stateFormat'.
   In addition attribute 'stateFormat' must be set to {HMCCU_State()}.
   
Specify IO device for client device:

   attr <name> IODev <HMCCU-Device>
   
   Normally this is set automatically during HMCCUDEV device definition.
   
Specify text substitutions for values in set commands:

   attr <name> stateval <text1>:<subtext1>[,...]
   
   The values <textn> are available as set commands, i.e.
      attr switch1 stateval on:true,off:false
	  set switch1 on
	  set switch1 off
	  set switch1 devstate on

Set format of readings with floating point numbers (default is 0):

   attr <name> stripnumber { 0 | 1 | 2 }

   0 = Floating point numbers are stored as read from CCU (i.e. with trailing zeros).
   1 = Trailing zeros are stripped from floating point numbers except one digit.
   2 = All trailing zeros are stripped from floating point numbers.

Specify text substitutions for values returned by get commands:

   attr <name> substitute <substitution_rule>[;...]

   For detailed information see description of HMCCU attribute 'substitute'.

   
====================================
 6 Hints and tipps
====================================
------------------------------------
 6.1 Requesting information from CCU
------------------------------------

By using XML-API one can query device names, channel names, channel addresses
and datapoint names from CCU. The following request queries device and channel
information:

   http://ccuname-or-ip/config/xmlapi/devicelist.cgi?show_internal=1

The following request returns a list of datapoints with current values:

   http://ccuname-or-ip/config/xmlapi/statelist.cgi?show_internal=1
     
------------------------------------
 6.2 Executing FHEM commands on CCU
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

--------------------------------------
 6.3 Use RAM disk for /tmp on Raspbian
--------------------------------------

By default ccurpcd creates the queue files in directory /tmp. On systems which
are running on a SD card like Raspbian this can shorten the lifetime of the 
SD card. To avoid this /tmp can be moved to a RAM disk:

   1) Edit file /etc/fstab as user 'root' and append the following line
   
      tmpfs /tmp tmpfs nodev,nosuid,relatime,size=100M 0 0
	  
	  This will define /tmp as a RAM disk with a size of 100 MByte.
	  
   2) Restart the system.
   
   

*** Have fun! zap ***

