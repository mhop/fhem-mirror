#
# Beispiel fuer eine HMCCU Parameterdatei
# Setzen mit attr <name> parfile <Datei>
# oder Angabe bei get <name> parfile <Datei>
#
# Tueren und Fenster
# Zustaende der CCU Geräte werden in den FHEM
# Readings ersetzt (false=closed,true=open).
#
TF-AZ-Fenster1:1.STATE false:closed,true:open
TF-AZ-Fenster2:1.STATE false:closed,true:open
TF-BE-Fenster:1.STATE false:closed,true:open
TF-BO-Fenster:1.STATE false:closed,true:open
TF-FL-Haustuer:1.STATE false:closed,true:open
TF-GA-Fenster:1.STATE false:closed,true:open
TF-GZ-Fenster1:1.STATE false:closed,true:open
TF-SZ-Fenster1:1.STATE false:closed,true:open
TF-SZ-Fenster2:1.STATE false:closed,true:open
TF-WZ-Balkon:1.STATE false:closed,true:open
TF-WZ-Terrasse:1.STATE false:closed,true:open
#
# Schalter
#
ST-HR-Pumpe:1.STATE false:off,true:on
ST-WZ-Bass:1.STATE false:off,true:on
#
# Temperatur und Luftfeuchte Sensoren
# Angabe Datenpunkt fehlt => Es werden alle Datenpunkte
# abgeholt (TEMPERATURE, HUMIDITY) 
#
KL-SZ-THX:1
KL-AZ-THX:1
KL-GA-THX:1
KL-BO-THX:1
KL-WZ-THX-1:1
