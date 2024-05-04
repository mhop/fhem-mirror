widget_automowerconnect.js      Widget für TabletUI Version 2
98_AMConnectTools.pm            Tool zur Erhöhung der Eventrate der Websocketverbindung zur Husqvarna Cloud

Beispiel zum Laden des Moduls 98_AMConnectTools.pm für die FHEM Befehlszeile, siehe auch: https://wiki.fhem.de/wiki/Update#Einzelne_Dateien_aus_dem_SVN_holen

{ Svn_GetFile('contrib/AutomowerConnect/98_AMConnectTools.pm', 'FHEM/98_AMConnectTools.pm') }


Zum Testen, falls vorhanden:

74_AutomowerConnect.pm
Common.pm
automowerconnect.js

Laden mit:
{ Svn_GetFile('contrib/AutomowerConnect/74_AutomowerConnect.pm', 'FHEM/74_AutomowerConnect.pm') }
{ Svn_GetFile('contrib/AutomowerConnect/Common.pm', 'lib/FHEM/Devices/AMConnect/Common.pm') }
{ Svn_GetFile('contrib/AutomowerConnect/automowerconnect.js', 'www/pgm2/automowerconnect.js') }

Alle Pfade gelten für eine Standardinstallation und sind ggf. anzupassen.
