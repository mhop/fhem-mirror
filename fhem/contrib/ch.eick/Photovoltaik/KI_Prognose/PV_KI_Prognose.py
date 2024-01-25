#!/usr/bin/python3
# coding: utf-8

# Version die eine Vorhersage auf Basis der Messwerte - Analyseversion
# Analyse via Random Forest Regressor

import fhem
import json

# Einlesen der Übergabeparameter
import sys
DbLog    = sys.argv[1]
web      = sys.argv[2]
webport  = 8083
DbRep    = sys.argv[3]
WRname   = sys.argv[4]
WRread   = sys.argv[5]


try:
    with open('/opt/fhem/python/pwd_fhem.json', 'r') as f:
        credentials=json.load(f)
    fhem_user = credentials["username"]
    fhem_pass = credentials["password"]
    fh = fhem.Fhem(web, protocol="http", port=webport, username=fhem_user, password=fhem_pass)
    print("PV_KI_Prognose  running - start")
    fh.send_cmd("setreading "+DbRep+" PV_KI_Prognose running start")
except Exception as e:

    print('Something went wrong: {}'.format(e))


try:
    with open('/opt/fhem/python/pwd_sql.json', 'r') as f:
        credentials=json.load(f)
except Exception as e:

    print('Something went wrong: {}'.format(e))


verbose = fh.get_device_attribute(DbRep, "verbose")

if (verbose >= 4):
    print("PV_KI_Prognose  running - start")
    print("PV_KI_Prognose  DbLog ",DbLog,"/fhem")
    print("PV_KI_Prognose  Fhem  ",web,":",webport)


Inverter_Max_Power = fh.get_device_reading("WR_1_Speicher_1_ExternControl", "SpeicherMidday_Inverter_Max_Power")
# Inverter_Max_Power = fh.get_device_reading(WRname, "SpeicherMidday_Inverter_Max_Power")

if (verbose >= 4):
    print("Inverter_Max_Power {}".format(Inverter_Max_Power["Value"]))


import pandas as pd
import numpy  as np
from sqlalchemy import create_engine
import pymysql

# betrifft beide relevanten Tabellen
db_connection_str = 'mysql+pymysql://'+credentials["username"]+':'+credentials["password"]+'@'+DbLog+'/fhem'
db_connection     = create_engine(db_connection_str)

if (verbose >= 3):
    print("PV_KI_Prognose  running - connected to "+DbLog)
    fh.send_cmd("setreading "+DbRep+" PV_KI_Prognose running connected to "+DbLog)

import datetime
from datetime import date, timedelta

today = datetime.datetime.now()
de = today.strftime("%Y-%m-%d 00:00:00")
# print(de)

# alle Wetterdaten ohne den start Tag der Prognose
dflern = pd.read_sql('SELECT * FROM dwdfull WHERE TIMESTAMP <  '+"'"+de+"'", con=db_connection)
dfask  = pd.read_sql('SELECT * FROM dwdfull WHERE TIMESTAMP >= '+"'"+de+"'", con=db_connection)

dfhour_start = pd.read_sql('SELECT min(hour(TIMESTAMP)) AS VALUE FROM dwdfull WHERE date(TIMESTAMP) = '+"'"+today.strftime("%Y-%m-%d")+"'", con=db_connection)
dfhour_stop  = pd.read_sql('SELECT max(hour(TIMESTAMP)) AS VALUE FROM dwdfull WHERE date(TIMESTAMP) = '+"'"+today.strftime("%Y-%m-%d")+"'", con=db_connection)
dfhours      = dfhour_stop['VALUE'].values[0] - dfhour_start['VALUE'].values[0] +1

if (verbose >= 3):
    print("PV_KI_Prognose  running - dwdfull read from DbLog "+DbLog)
    fh.send_cmd("setreading "+DbRep+" PV_KI_Prognose running dwdfull read from DbLog "+DbLog)

# Rad1h = Globale Einstrahlung
# TTT 	= Temperature 2m above surface [°C]
# Neff  = Effektive Wolkendecke
# R101  = Niederschlagswahrscheinlichkeit> 0,1 mm während der letzten Stunde
# SunD1 = Sonnenscheindauer während der letzten Stunde
# VV    = Sichtweite
# N     = Gesamte Wolkendecke
# DD    = Windrichtung
# RRS1c = Schneeregen-Äquivalent während der letzten Stunde

columns = ['Rad1h','Neff','R101','TTT','DD','SunAz','SunAlt','SunD1','VV','N','RRS1c']

# jetzt gehen wir die Analyse an
from sklearn.ensemble import RandomForestRegressor

if (verbose >= 3):
    print("PV_KI_Prognose  running - RandomForestRegressor loading")
    fh.send_cmd("setreading "+DbRep+" PV_KI_Prognose running RandomForestRegressor loading")

clf = RandomForestRegressor(n_estimators = 4000, bootstrap=True, random_state = 42)

if (verbose >= 3):
    print("PV_KI_Prognose  running - RandomForestRegressor loaded")
    fh.send_cmd("setreading "+DbRep+" PV_KI_Prognose running RandomForestRegressor loaded")

# train the model
df = dflern[:]

if (verbose >= 3):
    print("PV_KI_Prognose  running - RandomForestRegressor trained")
    fh.send_cmd("setreading "+DbRep+" PV_KI_Prognose running RandomForestRegressor trained")

# bring das gelernte in Bezug zum yield
clf.fit(df[columns], df['yield'])

if (verbose >= 3):
    print("PV_KI_Prognose  running - RandomForestRegressor fitted with yield")
    fh.send_cmd("setreading "+DbRep+" PV_KI_Prognose running RandomForestRegressor fitted with yield")

if (verbose >= 4):
    print("PV_KI_Prognose  running - RandomForestRegressor read statistics")
    # Auslesen und Anzeigen von Statistiken
    # Get numerical feature importances
    importances = list(clf.feature_importances_)
    # List of tuples with variable and importance
    feature_importances = [(feature, round(importance, 2)) for feature, importance in zip(columns, importances)]
    # Sort the feature importances by most important first
    feature_importances = sorted(feature_importances, key = lambda x: x[1], reverse = True)
    # Print out the feature and importances
    [print('Variable: {:20} Importance: {}'.format(*pair)) for pair in feature_importances]

# Immer einen Forecast für heute und morgen erstellen
start_date = datetime.datetime.now()
delta      = timedelta(days=1)
end_date   = start_date + delta

Prognose_faktor      = 1                             # Falls die Prognose generell daneben liegt kann der Faktor verwendet werden

loop_hour            = 0
loop_date            = start_date
loop_count           = 0
 

while loop_date <= end_date:
    # Daten Tagesmaximum
    middayhigh           = 0                         # Ein Merker, ob das Tagesmaximum überschritten wird
    middayhigh_start     = "00:00"
    middayhigh_stop      = "00:00"
    middayhigh_tmp       = 0
    middayhigh_start_tmp = 0
    middayhigh_stop_tmp  = 0

    # Pro Prognosetag die Tages Zähler zurück setzen
    Prognose_max         = 0
    Prognose_pre         = 0
    Prognose_4h          = 0
    Prognose_rest        = 0
    Prognose_morning     = 0
    Prognose_afternoon   = 0
    Prognose_day         = 0

    # Löschen der bisherigen Prognose von diesem
    sql = "DELETE FROM history WHERE DEVICE = '"+WRname+"' AND TIMESTAMP >= '"+str(loop_date.strftime("%Y-%m-%d"))+" 00:00:00' AND READING = '"+WRread+str(loop_count)+"' ;"
    db_connection.execute(str(sql))

    if (verbose >= 3):
        print("PV_KI_Prognose  running - old forecast deleted")
        fh.send_cmd("setreading "+DbRep+" PV_KI_Prognose running old forecast deleted")

    New_year  = str(loop_date.year)
    New_month = str(loop_date.month)
    New_day   = str(loop_date.day)
    New_hour  = loop_date.hour

    if (verbose >= 4):
        print("--------------------------------------------")
        print("Forecast fc%d     %s" % (loop_count,loop_date.strftime("%Y-%m-%d")))

    fcolumns = columns[:]
    fcolumns.insert(0, 'TIMESTAMP')
    fcolumns.append('yield')

    # hole die Werte für den Tag, der bearbeitet wird
    query   = 'year == "'+New_year+'" and month == "'+New_month+'" and day == "'+New_day+'"'
    dfq     = dfask.query(query)[fcolumns].reset_index()

    # erstelle die Prognose für den Tag
    predict = clf.predict(dfq[columns])

    # bearbeite jede einzelne Stunde der Prognose

    Prognose_pre = 0

    if (verbose >= 3):
        print("PV_KI_Prognose  running - start forecast")
        fh.send_cmd("setreading "+DbRep+" PV_KI_Prognose running start forecast")

    for loop_hour in range(dfhours):

        parms = dfq.iloc[loop_hour].values
        list  = parms.reshape(1, -1)
        date  = loop_date.strftime("%Y-%m-%d")

        # Hier wird die Prognose noch etwas angehoben, da bisher zu niedrige Werte prognostiziert werden.
        # Das kann sich mit mehr Vergleichsdaten noch ändern
        #
        # Zusätzlich wird noch interpoliert, wodurch die Summen korrekter erscheinen
        Prognose     = int(round((Prognose_pre + predict[loop_hour]*Prognose_faktor)/2))
        Prognose_pre = int(round(predict[loop_hour]*Prognose_faktor))

        # Zu kleine Werte werden verworfen
        if (Prognose < 20):
            if (verbose >= 4):
                print("Forecast value to smale")
            Prognose = 0

        # Zu große Werte werden limitiert
        # Achtung, die yield Prognose Werte sind Angaben zum Ende der Stunde
        if (Prognose > 0):
          timestamp = date+" %02d:00:00" % (dfhour_start['VALUE'].values[0]+loop_hour)
          Limit = int(round(dfask.loc[dfask['TIMESTAMP'] == timestamp].yield_max.values[0],0))
          if (verbose >= 4):
            # Hier wird beim Anzeigen der Wert um eine Stunde vorher angezeigt
            print(dfhour_start['VALUE'].values[0]+loop_hour-1,Prognose,Limit)

          if (Prognose > Limit):
            if (verbose >= 4):
                print("Forecast value to high : " + str(Prognose)+" > " + str(Limit))
            Prognose = Limit

        ## hier beginnt die Ermittung für das Mittagshoch
        if ( middayhigh == 0 and Prognose > Inverter_Max_Power["Value"] ):
            middayhigh           = 1
            # der Start wird auf eine Stunde vorher vorverlegt
            middayhigh_start_tmp = loop_hour-1
        ## einige Durchläufe später endet hier das Mittagshoch
        if ( middayhigh == 1 and Prognose < Inverter_Max_Power["Value"] and middayhigh_stop_tmp == 0 ):
            middayhigh_stop_tmp = loop_hour
        ## prüfen, ob es einen kurzen Leistungseinbruch gegeben hat, der soll übersprungen werden
        if ( middayhigh == 1 and Prognose > Inverter_Max_Power["Value"] and middayhigh_stop != "00:00" ):
            # da war ein kurzer Einbruch, es sollte noch länger sein.
            middayhigh_stop_tmp = 0

        ## hier ist dann das richtige Ende vom Mittagshoch
        if (             middayhigh == 1
            and middayhigh_stop_tmp != 0
            and middayhigh_stop_tmp == loop_hour):

            ## Wie lang ist das gefundene Mittagshoch
            middayhigh_tmp = middayhigh_stop_tmp - middayhigh_start_tmp
            if ( middayhigh_tmp > 4 ):                                           # das Middayhigh wird zu lang
                if (verbose >= 4):                                               # die bisherigen Zeiten ausgeben
                    print("Middayhigh        to long-------------------")
                    print("Middayhigh_start %02d:00" % (dfhour_start['VALUE'].values[0]+middayhigh_start_tmp))
                    print("Middayhigh_stop  %02d:00" % (dfhour_start['VALUE'].values[0]+middayhigh_stop_tmp))
                    print("--------------------------------------------")
                ## jetzt wird die Zeit vom Mittagshoch verkürzt
                ## beim Start etwas mehr kürzen, als zum Ende hin
                middayhigh_start_tmp = middayhigh_start_tmp +  round(middayhigh_tmp/3-0.2)    # es wird um ganze Stunden verkürzt
                middayhigh_stop_tmp  = middayhigh_stop_tmp  -  round(middayhigh_tmp/6-0.2)  
                if (verbose >= 4):                                               # melde die Verkürzung
                    print("Middayhigh       cut about %d h" % (round(middayhigh_tmp/3-0.2)+round(middayhigh_tmp/6-0.2)) )

            ## Die neuen Mittagshochzeiten formatieren
            middayhigh_start = "%02d:00" % (dfhour_start['VALUE'].values[0]+middayhigh_start_tmp)
            middayhigh_stop  = "%02d:00" % (dfhour_start['VALUE'].values[0]+middayhigh_stop_tmp)

        ## End if (middayhigh == 1...

        ### Bildung der Prognose Summen ###

        if (Prognose > Prognose_max):
            Prognose_max      = Prognose
            Prognose_max_time = "%02d:00" % (dfhour_start['VALUE'].values[0]+loop_hour-1)

        # Hier wird die Summe der nächsten 4 h gebildet
        if (    dfhour_start['VALUE'].values[0]+loop_hour >  New_hour
            and dfhour_start['VALUE'].values[0]+loop_hour <= New_hour+3):
            Prognose_4h   += Prognose

        # Hier wird die Summe für den Resttag gebildet
        if (dfhour_start['VALUE'].values[0]+loop_hour > New_hour):
            Prognose_rest += Prognose

        # Hier wird die Summe für den Vormittag gebildet
        if (dfhour_start['VALUE'].values[0]+loop_hour < 13):
            Prognose_morning += Prognose

        # Hier wird die Summe für den Nachmittag gebildet
        if (dfhour_start['VALUE'].values[0]+loop_hour >= 13):
            Prognose_afternoon += Prognose

        # Summe für den ganzen Tag
        Prognose_day += Prognose

        ######################################################################

        # Die Prognose anzeigen und in die dwdfull Tabelle eintragen
        if (loop_hour-1 >= 0):

            # Achtung, der Wert wird um eine Stunde früher in die Datenbank eingetragen
            timestamp = date+" "+"%02d:00:00" % (dfhour_start['VALUE'].values[0]+loop_hour-1)
            sql = "UPDATE dwdfull SET forecast ="+str(Prognose)+" WHERE TIMESTAMP = '"+timestamp+"' AND hour ="+str(dfhour_start['VALUE'].values[0]+loop_hour-1)+";"
            db_connection.execute(str(sql))

            sql = "INSERT INTO history (TIMESTAMP, DEVICE, TYPE ,READING ,VALUE) VALUES('"+timestamp+"','"+WRname+"','addlog','"+WRread+str(loop_count)+"','"+str(Prognose)+"') ;"
            db_connection.execute(str(sql))

            # Die Prognose Werte ins FHEM schreiben
            reading = WRread+str(loop_count)+"_%02d" % (dfhour_start['VALUE'].values[0]+loop_hour-1)
            fh.send_cmd("setreading "+WRname+" "+reading+" "+str(Prognose))

            if (verbose >= 3):
                print("%s  %02d %d" % (reading,dfhour_start['VALUE'].values[0]+loop_hour-1,Prognose))

        # Zum Ende der Prognose alle Werte in die readings schreiben
        if (loop_hour == dfhours-1):
            if (loop_date.day == start_date.day):
                # Für den aktuellen Tag diese Werte schreiben 
                fh.send_cmd("setreading "+WRname+" "+WRread+str(loop_count)+"_max "+str(Prognose_max))
                fh.send_cmd("setreading "+WRname+" "+WRread+str(loop_count)+"_max_time "+str(Prognose_max_time))
                fh.send_cmd("setreading "+WRname+" "+WRread+str(loop_count)+"_middayhigh "+str(middayhigh))
                fh.send_cmd("setreading "+WRname+" "+WRread+str(loop_count)+"_middayhigh_start "+str(middayhigh_start))
                fh.send_cmd("setreading "+WRname+" "+WRread+str(loop_count)+"_middayhigh_stop "+str(middayhigh_stop))
                fh.send_cmd("setreading "+WRname+" "+WRread+str(loop_count)+"_4h "+str(Prognose_4h))
                fh.send_cmd("setreading "+WRname+" "+WRread+str(loop_count)+"_rest "+str(Prognose_rest))
                fh.send_cmd("setreading "+WRname+" "+WRread+str(loop_count)+"_morning "+str(Prognose_morning))
                fh.send_cmd("setreading "+WRname+" "+WRread+str(loop_count)+"_afternoon "+str(Prognose_afternoon))
                fh.send_cmd("setreading "+WRname+" "+WRread+str(loop_count)+"_day "+str(Prognose_day))

            if (loop_date.day != start_date.day):
                # für weiter Prognosen sind nur diese Werte relevant
                fh.send_cmd("setreading "+WRname+" "+WRread+str(loop_count)+"_max "+str(Prognose_max))
                fh.send_cmd("setreading "+WRname+" "+WRread+str(loop_count)+"_max_time "+str(Prognose_max_time))
                fh.send_cmd("setreading "+WRname+" "+WRread+str(loop_count)+"_middayhigh "+str(middayhigh))
                fh.send_cmd("setreading "+WRname+" "+WRread+str(loop_count)+"_middayhigh_start "+str(middayhigh_start))
                fh.send_cmd("setreading "+WRname+" "+WRread+str(loop_count)+"_middayhigh_stop "+str(middayhigh_stop))
                fh.send_cmd("setreading "+WRname+" "+WRread+str(loop_count)+"_morning "+str(Prognose_morning))
                fh.send_cmd("setreading "+WRname+" "+WRread+str(loop_count)+"_afternoon "+str(Prognose_afternoon))
                fh.send_cmd("setreading "+WRname+" "+WRread+str(loop_count)+"_day "+str(Prognose_day))

            if (verbose >= 3):
                # für das Logging noch etwas formatieren
                print("--------------------------------------------")
                print("max       off/at",Prognose_max,Prognose_max_time)
                print("Middayhigh_start",middayhigh_start)
                print("Middayhigh_stop ",middayhigh_stop)
                print("4h              ",Prognose_4h)
                print("rest            ",Prognose_rest)
                print("morning         ",Prognose_morning)
                print("afternoon       ",Prognose_afternoon)
                print("day             ",Prognose_day)
                print("--------------------------------------------")

            if (verbose >= 3):
                print("PV_KI_Prognose  running - forecast written to FHEM")
                fh.send_cmd("setreading "+DbRep+" PV_KI_Prognose running forecast written")

    loop_date  += delta
    loop_count += 1


if (verbose >= 3):
    print("PV_KI_Prognose  done")

# Zum Schluss noch einen Trigger ins FHEM schreiben
fh.send_cmd("setreading "+DbRep+" PV_KI_Prognose done")

