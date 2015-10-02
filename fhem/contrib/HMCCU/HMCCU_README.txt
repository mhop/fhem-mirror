Content:
-------

1    HMCCU Introduction
1.1    HMCCU Description
1.2    HMCCU Requirements
2    HMCCU Usage
2.1  HMCCU Set Commands
2.2  HMCCU Get Commands
2.3  HMCCU Attributes
2.4  HMCCU Parameter File

------------------------------------
1 HMCCU Introduction
------------------------------------
------------------------------------
1.1 HMCCU Description
------------------------------------

The modules HMCCU and HMCCUDEV provide a simple interface between FHEM and
a Homematic CCU2. HMCCU is the IO device for the communication with the CCU.
HMCCUDEV is used to define client devices.
The states and values of CCU devices and variables are not updated automatically.
You have to define an AT device to update the values.

------------------------------------
1.2 HMCCU Requirements
------------------------------------

The module HMCCU requires the XML-API CCU addon (version >= 1.10). The FHEM
Perl module requires the package XML::Simple.


------------------------------------
2 HMCCU Usage
------------------------------------

Define a new IO device for communication with Homematic CCU:

   define <name> HMCCU <hostname_or_IP>


--------------------
 HMCCU Set commands
--------------------

If attribute stateval is set the specified string substitutions are applied
before setting the device state or variable or datapoint values.

Set state of a CCU device:

   set <name> devstate <ccudev>:<channel> <value>

Set value of a CCU device datapoint:

   set <name> datapoint <ccudev>:<channel>.<datapoint> <value>

Set value of a CCU system variable:

   set <name> var <variable> <value>

   The variable must exist in CCU.

Execute CCU program:

   set <name> execute <program>

   The program is executed even it's deactivated in CCU.

Clear CCU alarms:

   set <name> clearmsg


--------------------
 HMCCU Get commands
--------------------

If attribute ccureadings is set to 1 the results of the get commands
are stored in readings. The reading names correspond to the CCU data-
points, including device and channel. The format of the reading names
is device:channel.datapoint.
If attribute ccureadings is set to 0 the results of the get commands
are displayed in the browser window.
Some get commands allow an optional parameter reading. If this para-
meter is specified the CCU value is stored using this reading name.
With attribute 'substitute' you can define expression which are sub-
stitute by strings before CCU values are stored in readings.

Get values of channel datapoints:

   get <name> channel <channel>[.<datapoint_exp>] 

   If datapoint is not specified all datapoints will be read. The 
   commands accepts a regular expression as parameter datapoint.

Get value of datapoint:

   get <name> datapoint <ccudevice>:<channel>.<datapoint> [<reading>]

Get state of channel:

   get <name> devstate <ccudevice>:<channel> [<reading>]

   Specified channel must contain a datapoint 'STATE'.

Get multiple devices / channels / datapoints:

   get <name> parfile [<parfile>]

   If attribute 'parfile' is set parameter <parfile> can be omitted.
   See parameter file description below.

Get CCU variable values:

   get <name> vars <varname_exp>

   Variable name can be a regular expression.


------------------
 HMCCU Attributes
------------------

Control reading creation (default is 1):

   attr <name> ccureadings { 0 | 1 }

Remove character from CCU device or variable specification in set
commands:

   attr <name> stripchar <character>

Specify name of parameter file for command 'get parfile':

   attr <name> parfile <parfile>

Specify text substitutions for values in set commands:

   attr <name> stateval <text1>:<subtext1>[,...]

Specify text substitutions for values returned by  get commands:

   attr <name> substitute <regexp1>:<text1>[,...]


-----------------------
 HMCCU Parameter files
-----------------------

A parameter file contain a list of CCU datapoint channel or datapoint
definitions. Each line can contain a text substitution rule. The format
is:

  <ccudevice>:<channel>[.<datapoint_exp>] [<regexp1>:<subtext1>[,...]]

Empty lines and lines starting with a '#' are ignored.

