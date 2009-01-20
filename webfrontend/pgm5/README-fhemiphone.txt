Description of the pgm5-iphone webfrontend:

(c) Olaf Droegehorn
    o.droegehorn@dhs-computertechnik.de
    www.dhs-computertechnik.de

General description:

Web frontend 5 (webfrontend/pgm5) (known upto FHEM 4.2 as pgm2):

This frontend is CGI/CSS based. It has support for rooms, and  FHT/KS300 logs.

This webfrontend is an updated version for the iPhone(R):
It resides in YOUR HTTP server, and doesn't provide an own, like the FHEMWEB module does.

How it works:
The iPhone-WebFrontend works the same way as PGM5.

This is a VERY FIRST BETA !!!
Most of the things are for observing ONLY at the moment!
Changeing states is in progress, but not supported for now. !!!



INSTALLATION:
Copy the file fhemiphone.pl and the whole subdir "icons" to your cgi-bin directory (/home/httpd/cgi-bin), and commandref.html to the html directory (/home/httpd/html) (or also to cgi-bin directory).

The *.gplot files should be reused from the built-in FHEMWEB and should reside in the installed FHEM directory. Here we don't provide specific *.gplot files as the mechanisms are exactly the same.

Note: The program looks for icons in the following order: 
<device-name>.<state>, <device-name>, <device-type>.<state>, <device-type>


NOTE: This is based on IUI (wich is part of the icons-subdir)


Copy the file pgm5/02_FHEMRENDERER.pm to the installed FHEM directory.
This gives you a graphic rendering engine (gnuplot & gnuplot-scroll at the moment), which can be configured to renderer images in intervals.

Call <your-site>/cgi-bin/fhemiphone.pl 

If you want to show only a part of your devices on a single screen
(i.e divide them into separate rooms), then assign each device the
room attribute in the config file:

  attr ks300     room garden
  attr ks300-log room garden

The attribute title of the global device will be used as title on the first
screen, which shows the list of all rooms. Devices in the room
"hidden" will not be shown. Devices without a room attribute go
to the room "misc".

