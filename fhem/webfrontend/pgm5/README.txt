Description of the pgm5 webfrontend:

(c) Olaf Droegehorn
    o.droegehorn@dhs-computertechnik.de
    www.dhs-computertechnik.de

#################################################################################
#  Copyright notice
#
#  (c) 2008-2012
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

General description:

Web frontend 5 (webfrontend/pgm5) (known upto FHEM 4.2 as pgm2):

This frontend is CGI/CSS based. It has support for rooms, and  FHT/KS300 logs.

This webfrontend is an update of the former know pgm2 (up to 4.2):
It resides in YOUR HTTP server, and doesn't provide an own, like the FHEMWEB module does.

Why to use this:
1) If you want to stick with your Web-Servers (due to restrictions, 
   ports or any other reason)
2) If you have a NAS (Network attached storage) and limited CPU-Power. 
   This frontend can render the graphics in the background (in 
   intervals) and sends only the rendered graphics to the HTML-Page.
3) If you need the FHEMRENDERER to render the images for other/own   
   pages.

How it works:
The WebFrontend works as usual and well known from before.
Main difference:
It creates and uses an instance of FHEMRENDERER (called renderer).
The renderer has plotmode, plotsize, tmpfile, status, refresh as attributes.
With this you can control, how it works (and when in renders: refresh: 00:15:00 means every 15 minutes it will render an update).

What will be rendered: All FileLogs for which you have set a WebLink will be rendered in the given intervals.
The GET method of the renderer is also able to render specific graphics only for single use on request.

The PGM5 webfrontend does all this for you, but if you want to use the FHEMRENDERER for own things, you can use it directly.


INSTALLATION:
Copy the file fhemweb.pl and *.css to your cgi-bin directory (/home/httpd/cgi-bin), the icons (*.gif) to your httpd icons (/home/httpd/icons), and commandref.html to the html directory (/home/httpd/html) (or also to cgi-bin directory).

The *.gplot files should be reused from the built-in FHEMWEB and should reside in the installed FHEM directory. Here we don't provide specific *.gplot files as the mechanisms are exactly the same.

Note: The program looks for icons in the following order: 
<device-name>.<state>, <device-name>, <device-type>.<state>, <device-type>

If you want to have access to plotted logs, then make sure that gnuplot is installed and set the logtype for the FileLog device (see commandref.html and example/04_log). 
Copy the file contrib/99_weblink.pm to the installed FHEM directory.

Copy the file pgm5/02_FHEMRENDERER.pm to the installed FHEM directory.
This gives you a grphic rendering engine (gnuplot & gnuplot-scroll at the moment), which can be configured to renderer images in intervals.

Call <your-site>/cgi-bin/fhemweb.pl 

If you want to show only a part of your devices on a single screen
(i.e divide them into separate rooms), then assign each device the
room attribute in the config file:

  attr ks300     room garden
  attr ks300-log room garden

The attribute title of the global device will be used as title on the first
screen, which shows the list of all rooms. Devices in the room
"hidden" will not be shown. Devices without a room attribute go
to the room "misc".

To configure the absicondir and relicondir correctly, look into the
httpd.conf file (probably /etc/httpd/conf/httpd.conf), and check the
line which looks like:
 Alias /icons/ "/home/httpd/icons/"
relicondir will then be /icons, and absicondir /home/httpd/icons.

