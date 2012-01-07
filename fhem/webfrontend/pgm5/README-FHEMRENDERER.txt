Description of the 02_FHEMRENDERER Module:

(c) Olaf Droegehorn
    o.droegehorn@dhs-computertechnik.de
    www.dhs-computertechnik.de

#################################################################################
#  Copyright notice
#
#  (c) 2008-2011
#  Copyright: Dr. Olaf Droegehorn
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
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
#  This copyright notice MUST APPEAR in all copies of the script!
#################################################################################

Versions:

V1.0: Initial Version
V1.1: Bugfix: Enabled multiple RENERER Instances
V1.2: Bugfix: Corrected Function-Names to avoid collision with PGM2

General Description:

The FHEMRENDERER module is intended to render (draw) graphics based on the FHEM Log-Files.
This can be done either based on a timer (used in the module) or based on a direct call of GET.
The rendered graphics will be stored in a pre-defined directory with a predefined prefix of the files.

The FHEMRENDERER uses attributes to control the behaviour:
		plotmode	gnuplot	
		plotsize	800,200
		refresh		00:10:00
		room		Unsorted
		status		off
		tmpfile		/tmp/

These attributes have the following meaning:
plotmode, plotsize: 	Control gnuplot and the desired output
refresh: 		type HH:MM:SS, is the time-interval in which the re-rendering is done
status:  		Tells if the timer-based re-rendering is on/off
tmpfile:		Is the path (and prefix, if given) of the graphic-files, that will be rendered

NOTE: The timer-based rendering renders ONLY those fileplots, for which you have defined a WebLink !
      See WebLink for more details on how to define.

NOTE: At the moment the renderer supports only GNUPLOT, meaning gnuplot is used to draw the graphics. The supported
modes are (gnuplot and gnuplot-scroll).


Supported commands are:

define/set/get/attributes



DEFINE

      define <name> <type> <type-specific>

      Define a device. You need devices if you want to manipulate them (e.g. set on/off).
      Use "define <name> ?" to get a list of possible types.

      Type FHEMRENDERER

	define <name> FHEMRENDERER [global]

	This defines a new "device", that is of type FHEMRENDERER. The option 'global' can be used if needed for sorting reasons. 
        Otherwise this option has no real meaning for FHEMRENDERER.

        As a side-effect of defining this "device" the following attributes will be set for this "device":
		plotmode	gnuplot	
		plotsize	800,200
		refresh		00:10:00
		room		Unsorted
		status		off
		tmpfile		/tmp/

        
        NOTE: The Logfile will report (with LogLevel 2) that the FHEMRENDERER has been defined.

        Examples:
          define renderer FHEMRENDERER

SET

      set <name> <type-specific>

      Set parameters of a device / send signals to a device. You can get a list of possible commands by
      set <name> ?

      Type FHEMRENDERER:
            set FHEMRENDERER on/off

	This switches the timer-based rendering on/off. The attribute 'status' will be modified accordingly.
	NOTE: only WebLink based graphics will be rendered.

GET
      get <name> <type-specific>

      Ask a value directly from the device, and wait for an answer. In general, you can get a list of possible commands by
      get <device> ?
      
      Type FHEMRENDERER:
	get FHEMRENDERER [[file-name] device type logfile [pos=zoom=XX&off=YYY]]

	the get function supports different sets of arguments:
	Arguments:
		NONE:	all WebLink based FilePlots will be rerendered
			The resulting filename will be '<attr-tmpfile><weblinkname>.png'
		THREE:	'<device> <type> <logfile>'
			In this case only one specific graphic will be rendered:
			A graphic will be rendered for 'device', where device is a FileLog, based on the type 'type' based on the given 'logfile'
			The resulting filename will be '<attr-tmpfile>logfile.png'
		FOUR:	'<file-name> <device> <type> <logfile>'
			In this case only one specific graphic will be rendered:
			A graphic will be rendered for 'device', where device is a FileLog, based on the type 'type' based on the given 'logfile'
			The resulting filename will be '<attr-tmpfile><file-name>.png'
		FIVE:	'<file-name> <device> <type> <logfile> pos=zoom=XX&off=YYY'
			In this case only one specific graphic will be rendered assuming that plotmode is 'gnuplot-scroll':
			A graphic will be rendered for 'device', where device is a FileLog, based on the type 'type' based on the given 'logfile'
			The 'zoom' will be either qday/day/week/month/year (same as used in FHEMWEB).
			The offset 'off' is either 0 (then the second part can be omitted, or -1/-2.... to jump back in time.
			The resulting filename will be '<attr-tmpfile><file-name>.png'

			NOTE: If you want to use zoom AND offset then you have to concatenate via '&' !!

		NOTE: combinations are possible in limited ranges:
			meaning: you can add the 'pos=zoom=XX&off=YY' to any of the first three sets. 
                                 This may e.g. result in rendering all WebLinks with a specific zoom or offset 
				 (if you just pass the 'pos=zoom=xx&off=yy' parameter);

	Any rendered image (one or all WebLinks) will be stored in <attr-tmpfile> followed by a filename'.png'. The filename will be
	either derived (from weblink-name or logfile-name) or, for single files, can be assigend.

	Examples:
		get FHEMRENDERER
		get FHEMRENDERER pos=zoom=week&off=-1
		get FHEMRENDERER azlog fht az-2008-38.log pos=zoom=0
		get FHEMRENDERER livingroomgraphics wzlog fht wz-2008-38.log pos=zoom=0


ATTR

      attr <name> <attrname> <value>

      Set an attribute to something defined by define. 
      Use "attr <name> ?" to get a list of possible attributes.
	
      Type FHEMRENDERER:
	attr FHEMRENDERER <attrname> <value>

	Attributes:		<Values>
		plotmode	gnuplot	/ gnuplot-scroll
		plotsize	Dimension of graphic e.g. 800,200
		refresh		Timer-Interval for rerendering (HH:MM:SS)
		status		Status of the Timer (off/on)
		tmpfile		Path and prefix of for the rendered graphics (e.g. /tmp/)




Installation:
Copy the file pgm5/02_FHEMRENDERER.pm to the installed FHEM directory.
This gives you a graphic rendering engine (gnuplot & gnuplot-scroll at the moment), which can be configured to renderer images in intervals.

The *.gplot files should be reused from the built-in FHEMWEB and should reside in the installed FHEM directory. Here we don't provide specific *.gplot files as the mechanisms are exactly the same.

If you want to have access to plotted logs, then make sure that gnuplot is installed and set the logtype for the FileLog device (see commandref.html and example/04_log). 
Copy the file contrib/99_weblink.pm to the installed FHEM directory.

