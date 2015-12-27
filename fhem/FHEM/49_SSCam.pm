#####################################################################################################
# $Id
#####################################################################################################
#       49_SSCam.pm
#
#       written by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This Modul can be used to operate Cameras defined in Synology Surveillance Station 7.0 or higher.
#       It's based on Synology Surveillance Station API Guide 2.0
# 
#	This file is part of fhem.
#
#	Fhem is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 2 of the License, or
#	(at your option) any later version.
#
#	Fhem is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with fhem.  If not, see <http://www.gnu.org/licenses/>.# 
#
######################################################################################################
#  Versionshistorie:
#  1.4  23.12.2015 function "enable" and "disable" for SS-Cams added,
#                  changed timout of Http-calls to a higher value
#  1.3  19.12.2015 function "snap" for taking snapshots added,
#                  fixed a bug that functions may impact each other 
#  1.2  14.12.2015 improve usage of verbose-modes
#  1.1  13.12.2015 use of InternalTimer instead of fhem(sleep)
#  1.0  12.12.2015 changed completly to HttpUtils_NonblockingGet for calling websites nonblocking, 
#                  LWP is not needed anymore
#
#
# Definition: define <name> SSCam <servername> <serverport> <username> <password> <camname> <rectime> 
# 
# Beispiel: define CamCP1 SSCAM dd.myds.net 5000 apiuser apipw Carport 5
#
# Parameters:
#       
# $servername = "";          # DS-Sername oder IP
# $serverport = "";          # DS Port
# $username   = "";          # User für login auf DS
# $password   = "";          # Passwort für User login
# $camname    = "";          # Name der Kamera
# $rectime    = "";          # Dauer der Aufnahme in Sekunden 
  

package main;

use JSON qw( decode_json );            # From CPAN,, Debian libjson-perl 
use Data::Dumper;                      # Perl Core module
use strict;                           
use warnings;                         
use HttpUtils;


sub SSCam_Initialize($) {
 # die Namen der Funktionen, die das Modul implementiert und die fhem.pl aufrufen soll
 my ($hash) = @_;
 $hash->{DefFn}     = "SSCam_Define";
 $hash->{UndefFn}   = "SSCam_Undef";
 $hash->{SetFn}     = "SSCam_Set";
 # $hash->{AttrFn}    = "SSCam_Attr";
 
 
 $hash->{AttrList} = 
         "webCmd ".
         $readingFnAttributes;
 
}

sub SSCam_Define {
  # Die Define-Funktion eines Moduls wird von Fhem aufgerufen wenn der Define-Befehl für ein Gerät ausgeführt wird 
  # Welche und wie viele Parameter akzeptiert werden ist Sache dieser Funktion. Die Werte werden nach dem übergebenen Hash in ein Array aufgeteilt
  # define CamCP1 SSCAM sds1.myds.me 5000 apiuser Support4me Carport 5
  #        ($hash) [1]     [2]        [3]   [4]     [5]       [6]   [7]  
  #
  my ($hash, $def) = @_;
  
  my @a = split("[ \t][ \t]*", $def);
  
  if(int(@a) < 8) {
        return "You need to specify more parameters.\n". "Format: define <name> SSCAM <Servername> <Port> <User> <Password> <Cameraname> <Recordtime>";
        }
        
  my $servername = $a[2];
  my $serverport = $a[3];
  my $username   = $a[4];  
  my $password   = $a[5];
  my $camname    = $a[6];
  my $rectime    = $a[7];
  
  
  unless ($rectime =~ /^\d+$/) { return " The given Recordtime is not valid. Use only figures 0-9 without decimal places !";}
  # führende Nullen entfernen
  $rectime =~ s/^0+//;
  
  $hash->{SERVERNAME} = $servername;
  $hash->{SERVERPORT} = $serverport;
  $hash->{USERNAME} = $username;
  $hash->{HELPER}{PASSWORD} = $password;
  $hash->{CAMNAME} = $camname;
  $hash->{RECTIME} = $rectime; 
  
  # benötigte API's in $hash einfügen
  $hash->{HELPER}{APIINFO}        = "SYNO.API.Info";                             # Info-Seite für alle API's, einzige statische Seite !                                                    
  $hash->{HELPER}{APIAUTH}        = "SYNO.API.Auth";                                                  
  $hash->{HELPER}{APIEXTREC}      = "SYNO.SurveillanceStation.ExternalRecording";                     
  $hash->{HELPER}{APICAM}         = "SYNO.SurveillanceStation.Camera";
  $hash->{HELPER}{APISNAPSHOT}    = "SYNO.SurveillanceStation.SnapShot";
  
  # Anfangswerte setzen
  $hash->{HELPER}{ACTIVE} = "off";
  readingsSingleUpdate($hash,"Record","Stop",0);
  readingsSingleUpdate($hash, "Availability", "", 0); 
  
  return undef;
}


sub SSCam_Undef {
    my ($hash, $arg) = @_;
    RemoveInternalTimer($hash);
    return undef;
}

sub SSCam_Attr { 
}
 
sub SSCam_Set {
        my ( $hash, @a ) = @_;
        return "\"set X\" needs at least an argument" if ( @a < 2 );
	my $name = shift @a;
	my $opt = shift @a;
	my %SSCam_sets = (
	                 on        => "on",
	                 off       => "off",
	                 snap      => "snap",
	                 enable    => "enable",
	                 disable   => "disable"
	                 );
	
	my $camname = $hash->{CAMNAME};  
	my $logstr;
	my @cList;
	
	# ist die angegebene Option verfügbar ?
	if(!defined($SSCam_sets{$opt})) 
	        {
		    @cList = keys %SSCam_sets; 
		    return "Unknown argument $opt, choose one of " . join(" ", @cList);
                } 
                else 
                {
                    if ($opt eq "on") 
                    {
                        &camstartrec($hash);
                    }
                    elsif ($opt eq "off") 
                    {
                        &camstoprec($hash);
                    }
                    elsif ($opt eq "snap") 
                    {
                        &camsnap($hash);
                    }
                    elsif ($opt eq "enable") 
                    {
                        &camenable($hash);
                    }
                    elsif ($opt eq "disable") 
                    {
                        &camdisable($hash);
                    }

                }          
}


#############################################################################################################################
#########                                        OpMode-Startroutinen                                           #############
#########   $hash->{HELPER}{ACTIVE} = Funktionstoken                                                            #############
#########   $hash->{HELPER}{ACTIVE} = "on"    ->  eine Routine läuft, Start anderer Routine erst wenn "off".    #############
#########   $hash->{HELPER}{ACTIVE} = "off"   ->  keine andere Routine läuft, sofortiger Start möglich          #############
#############################################################################################################################

###############################################################################
###   Kamera Aufnahme starten

sub camstartrec ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    my $errorcode;
    my $error;
    
    if (ReadingsVal("$name", "Availability", "enabled") eq "disabled") {
        # wenn Kamera disabled ist ....
        $errorcode = "402";
        
        # Fehlertext zum Errorcode ermitteln
        $error = &experror($hash,$errorcode);

        # Setreading 
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        $logstr = "ERROR - Start Recording of Camera $camname can't be executed - $error" ;
        &printlog($hash,$logstr,"1");
        return;
        }
    
    if ($hash->{HELPER}{ACTIVE} ne "on" and ReadingsVal("$name", "Record", "Start") ne "Start") {
        # Aufnahme starten
        $logstr = "Recording of Camera $camname should be started now";
        &printlog($hash,$logstr,"4");
                           
        $hash->{OPMODE} = "Start";
        $hash->{HELPER}{ACTIVE} = "on";
        
        &getapisites_nonbl($hash);
    }
    else
    {
    InternalTimer(gettimeofday()+0.1, "camstartrec", $hash, 0);
    }
}

###############################################################################
###   Kamera Aufnahme stoppen

sub camstoprec ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    my $errorcode;
    my $error;
    
    if (ReadingsVal("$name", "Availability", "enabled") eq "disabled") {
        # wenn Kamera disabled ist ....
        $errorcode = "402";
        
        # Fehlertext zum Errorcode ermitteln
        $error = &experror($hash,$errorcode);

        # Setreading 
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        $logstr = "ERROR - Stop Recording of Camera $camname can't be executed - $error" ;
        &printlog($hash,$logstr,"1");
        return;
        }
    
    if ($hash->{HELPER}{ACTIVE} ne "on" and ReadingsVal("$name", "Record", "Stop") ne "Stop") {
        # Aufnahme stoppen
        $logstr = "Recording of Camera $camname should be stopped now";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "Stop";
        $hash->{HELPER}{ACTIVE} = "on";
        
        &getapisites_nonbl($hash);
    }
    else
    {
    InternalTimer(gettimeofday()+0.1, "camstoprec", $hash, 0);
    }
}

###############################################################################
###   Kamera Schappschuß aufnehmen

sub camsnap ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    my $errorcode;
    my $error;
    
    if (ReadingsVal("$name", "Availability", "enabled") eq "disabled") {
        # wenn Kamera disabled ist ....
        $errorcode = "402";
        
        # Fehlertext zum Errorcode ermitteln
        $error = &experror($hash,$errorcode);

        # Setreading 
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"Errorcode",$errorcode);
        readingsBulkUpdate($hash,"Error",$error);
        readingsEndUpdate($hash, 1);
    
        $logstr = "ERROR - Snapshot of Camera $camname can't be executed - $error" ;
        &printlog($hash,$logstr,"1");
        return;
        }
    
    if ($hash->{HELPER}{ACTIVE} ne "on") {
        # einen Schnappschuß aufnehmen
        $logstr = "Take Snapshot of Camera $camname";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "Snap";
        $hash->{HELPER}{ACTIVE} = "on";
        
        &getapisites_nonbl($hash);
    }
    else
    {
    InternalTimer(gettimeofday()+0.1, "camsnap", $hash, 0);
    }    
}

###############################################################################
###   Kamera aktivieren

sub camenable ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    
    if (ReadingsVal("$name", "Availability", "disabled") eq "enabled") {return;}       # Kamera ist bereits enabled
    
    if ($hash->{HELPER}{ACTIVE} ne "on") {
        # eine Kamera aktivieren
        $logstr = "Enable Camera $camname";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "Enable";
        $hash->{HELPER}{ACTIVE} = "on";
        
        &getapisites_nonbl($hash);
    }
    else
    {
    InternalTimer(gettimeofday()+0.1, "camenable", $hash, 0);
    }    
}

###############################################################################
###   Kamera deaktivieren

sub camdisable ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    
    if (ReadingsVal("$name", "Availability", "enabled") eq "disabled") {return;}       # Kamera ist bereits disabled
    
    if ($hash->{HELPER}{ACTIVE} ne "on" and ReadingsVal("$name", "Record", "Start") ne "Start") {
        # eine Kamera deaktivieren
        $logstr = "Disable Camera $camname";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "Disable";
        $hash->{HELPER}{ACTIVE} = "on";
        
        &getapisites_nonbl($hash);
    }
    else
    {
    InternalTimer(gettimeofday()+0.2, "camdisable", $hash, 0);
    }    
}


#############################################################################################################################
#######    Begin Kameraoperationen mit NonblockingGet (nicht blockierender HTTP-Call)                                 #######
#######                                                                                                               #######
#######    Ablauflogik:                                                                                               #######
#######                                                                                                               #######
#######                                                                                                               #######
#######    OpMode-Startroutine                                                                                        #######
#######            |                                                                                                  #######
#######    getapisites_nonbl -> login_nonbl ->  getcamid_nonbl  -> camop_nonbl ->  camret_nonbl -> logout_nonbl       #######
#######                                                                 |                                             #######
#######                                                               OpMode                                          #######
#######                                                                                                               #######
#############################################################################################################################

sub getapisites_nonbl {
   my ($hash) = @_;
   my $servername  = $hash->{SERVERNAME};
   my $serverport  = $hash->{SERVERPORT};
   my $apiinfo     = $hash->{HELPER}{APIINFO};                         # Info-Seite für alle API's, einzige statische Seite !
   my $apiauth     = $hash->{HELPER}{APIAUTH};                         # benötigte API-Pfade für Funktionen,  
   my $apiextrec   = $hash->{HELPER}{APIEXTREC};                       # in der Abfrage-Url an Parameter "&query="
   my $apicam      = $hash->{HELPER}{APICAM};                          # mit Komma getrennt angeben
   my $apitakesnap = $hash->{HELPER}{APISNAPSHOT};
   my $logstr;
   my $url;
   my $param;
  
   #### API-Pfade und MaxVersions ermitteln #####
   # Logausgabe
   $logstr = "--- Begin Function getapisites nonblocking ---";
   &printlog($hash,$logstr,"4");
   
   # URL zur Abfrage der Eigenschaften der  API's
   $url = "http://$servername:$serverport/webapi/query.cgi?api=$apiinfo&method=Query&version=1&query=$apiauth,$apiextrec,$apicam,$apitakesnap";
   
   $param = {
               url      => $url,
               timeout  => 10,
               hash     => $hash,
               method   => "GET",
               header   => "Accept: application/json",
               callback => \&login_nonbl
            };
   
   # API-Sites werden abgefragt und mit Routine "login_nonbl" verarbeitet
   HttpUtils_NonblockingGet ($param);  
} 
    

####################################################################################  
####      Rückkehr aus Funktion API-Pfade und MaxVersions ermitteln,  
####      nach erfolgreicher Verarbeitung wird login ausgeführt und $sid ermittelt

sub login_nonbl ($) {
   my ($param, $err, $myjson) = @_;
   my $hash        = $param->{hash};
   my $device      = $hash->{NAME};
   my $servername  = $hash->{SERVERNAME};
   my $serverport  = $hash->{SERVERPORT};
   my $username    = $hash->{USERNAME};
   my $password    = $hash->{HELPER}{PASSWORD};
   my $apiauth     = $hash->{HELPER}{APIAUTH};
   my $apiextrec   = $hash->{HELPER}{APIEXTREC};
   my $apicam      = $hash->{HELPER}{APICAM};
   my $apitakesnap = $hash->{HELPER}{APISNAPSHOT};
   my $data;
   my $logstr;
   my $url;
   my $success;
   my $apiauthpath;
   my $apiauthmaxver;
   my $apiextrecpath;
   my $apiextrecmaxver;
   my $apicampath;
   my $apicammaxver;
   my $apitakesnappath;
   my $apitakesnapmaxver;
   my $error;
  
    # Verarbeitung der asynchronen Rückkehrdaten aus sub "getapisites_nonbl"
    if ($err ne "")                                                                                    # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
    {
        $logstr = "error while requesting ".$param->{url}." - $err";
        &printlog($hash,$logstr,"1");	                                                             
        $logstr = "--- End Function getapisites nonblocking with error ---";
        &printlog($hash,$logstr,"4");
       
        readingsSingleUpdate($hash, "Error", $err, 1);                                     	       # Readings erzeugen

        # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
        $hash->{HELPER}{ACTIVE} = "off"; 

        return;
    }

    elsif ($myjson ne "")                                                                               # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
    {
        $logstr = "URL-Call: ".$param->{url};                                                          
        &printlog($hash,$logstr,"4");
          
        # An dieser Stelle die Antwort parsen / verarbeiten mit $myjson
        
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, $success) = &evaljson($hash,$myjson,$param->{url});
        unless ($success) {$logstr = "Data returned: ".$myjson; &printlog($hash,$logstr,"4"); return($hash,$success)};
        
        $data = decode_json($myjson);
   
        $success = $data->{'success'};
    
                if ($success) 
                     {
                        # Logausgabe decodierte JSON Daten
                        $logstr = "JSON returned: ". Dumper $data;                                                         
                        &printlog($hash,$logstr,"4");
                        
                     # Pfad und Maxversion von "SYNO.API.Auth" ermitteln
       
                        $apiauthpath = $data->{'data'}->{$apiauth}->{'path'};
                        # Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
                        $apiauthpath =~ tr/_//d;
                        $apiauthmaxver = $data->{'data'}->{$apiauth}->{'maxVersion'}; 
       
                        $logstr = "Path of $apiauth selected: $apiauthpath";
                        &printlog($hash, $logstr,"4");
                        $logstr = "MaxVersion of $apiauth selected: $apiauthmaxver";
                        &printlog($hash, $logstr,"4");
       
                     # Pfad und Maxversion von "SYNO.SurveillanceStation.ExternalRecording" ermitteln
       
                        $apiextrecpath = $data->{'data'}->{$apiextrec}->{'path'};
                        # Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
                        $apiextrecpath =~ tr/_//d;
                        $apiextrecmaxver = $data->{'data'}->{$apiextrec}->{'maxVersion'}; 
       
                        $logstr = "Path of $apiextrec selected: $apiextrecpath";
                        &printlog($hash, $logstr,"4");
                        $logstr = "MaxVersion of $apiextrec selected: $apiextrecmaxver";
                        &printlog($hash, $logstr,"4");
       
                     # Pfad und Maxversion von "SYNO.SurveillanceStation.Camera" ermitteln
              
                        $apicampath = $data->{'data'}->{$apicam}->{'path'};
                        # Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
                        $apicampath =~ tr/_//d;
                        $apicammaxver = $data->{'data'}->{$apicam}->{'maxVersion'};
                        # um 1 verringern - Fehlerprävention
                        if (defined $apicammaxver) {$apicammaxver -= 1};
       
                        $logstr = "Path of $apicam selected: $apicampath";
                        &printlog($hash, $logstr,"4");
                        $logstr = "MaxVersion of $apicam (optimized): $apicammaxver";
                        &printlog($hash, $logstr,"4");
       
                     # Pfad und Maxversion von "SYNO.SurveillanceStation.SnapShot" ermitteln
              
                        $apitakesnappath = $data->{'data'}->{$apitakesnap}->{'path'};
                        # Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
                        $apitakesnappath =~ tr/_//d;
                        $apitakesnapmaxver = $data->{'data'}->{$apitakesnap}->{'maxVersion'};
                            
                        $logstr = "Path of $apitakesnap selected: $apitakesnappath";
                        &printlog($hash, $logstr,"4");
                        $logstr = "MaxVersion of $apitakesnap: $apitakesnapmaxver";
                        &printlog($hash, $logstr,"4");

       
                        # ermittelte Werte in $hash einfügen
                        $hash->{HELPER}{APIAUTHPATH}       = $apiauthpath;
                        $hash->{HELPER}{APIAUTHMAXVER}     = $apiauthmaxver;
                        $hash->{HELPER}{APIEXTRECPATH}     = $apiextrecpath;
                        $hash->{HELPER}{APIEXTRECMAXVER}   = $apiextrecmaxver;
                        $hash->{HELPER}{APICAMPATH}        = $apicampath;
                        $hash->{HELPER}{APICAMMAXVER}      = $apicammaxver;
                        $hash->{HELPER}{APITAKESNAPPATH}   = $apitakesnappath;
                        $hash->{HELPER}{APITAKESNAPMAXVER} = $apitakesnapmaxver;
       
       
                        # Setreading 
                        readingsBeginUpdate($hash);
                        readingsBulkUpdate($hash,"Errorcode","none");
                        readingsBulkUpdate($hash,"Error","none");
                        readingsEndUpdate($hash,1);

                        # Logausgabe
                        $logstr = "--- End Function getapisites nonblocking ---";
                        &printlog($hash,$logstr,"4");
                    } 
                    else 
                    {
                        # Fehlertext setzen
                        $error = "couldn't call API-Infosite";
       
                        # Setreading 
                        readingsBeginUpdate($hash);
                        readingsBulkUpdate($hash,"Errorcode","none");
                        readingsBulkUpdate($hash,"Error",$error);
                        readingsEndUpdate($hash, 1);

                        # Logausgabe
                        $logstr = "ERROR - the API-Query couldn't be executed successfully";
                        &printlog($hash,$logstr,"1");

                        $logstr = "--- End Function getapisites nonblocking with error ---";
                        &printlog($hash,$logstr,"4");
                        
                        # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
                        $hash->{HELPER}{ACTIVE} = "off"; 
                        
                        return;
                     }
    }
  
  # Login und SID ermitteln
  # Logausgabe
  $logstr = "--- Begin Function serverlogin nonblocking ---";
  &printlog($hash,$logstr,"4");  
 
  $url = "http://$servername:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Login&account=$username&passwd=$password&session=SurveillanceStation&format=sid";
   
  
  $param = {
               url      => $url,
               timeout  => 10,
               hash     => $hash,
               method   => "GET",
               header   => "Accept: application/json",
               callback => \&getcamid_nonbl
           };
   
   # login wird ausgeführt, $sid ermittelt und mit Routine "getcamid_nonbl" verarbeitet
   HttpUtils_NonblockingGet ($param);
  
  
}  
  
###############################################################################  
####      Rückkehr aus Funktion login und $sid ermitteln,  
####      nach erfolgreicher Verarbeitung wird Kamera-ID ermittelt 
  
sub getcamid_nonbl ($) {  
  
   my ($param, $err, $myjson) = @_;
   my $hash         = $param->{hash};
   my $servername   = $hash->{SERVERNAME};
   my $serverport   = $hash->{SERVERPORT};
   my $username     = $hash->{USERNAME};
   my $apicam       = $hash->{HELPER}{APICAM};
   my $apicampath   = $hash->{HELPER}{APICAMPATH};
   my $apicammaxver = $hash->{HELPER}{APICAMMAXVER};
   my $url;
   my $data;
   my $logstr;
   my $success;
   my $sid;
   my $error;
   my $errorcode;
   
   
  
   # Verarbeitung der asynchronen Rückkehrdaten aus sub "login_nonbl"
   if ($err ne "")                                                                                      # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
   {
        $logstr = "error while requesting ".$param->{url}." - $err";
        &printlog($hash,$logstr,"1");		                                                       # Eintrag fürs Log
        $logstr = "--- End Function serverlogin nonblocking with error ---";
        &printlog($hash,$logstr,"4");
        
        readingsSingleUpdate($hash, "Error", $err, 1);                                      	       # Readings erzeugen
        
        # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
        $hash->{HELPER}{ACTIVE} = "off"; 

        return;
   }
   elsif ($myjson ne "")                                                                                # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
   {
        $logstr = "URL-Call: ".$param->{url};                                                          # Eintrag fürs Log
        &printlog($hash,$logstr,"4");
          
        # An dieser Stelle die Antwort parsen / verarbeiten mit $myjson
        
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, $success) = &evaljson($hash,$myjson,$param->{url});
        unless ($success) {$logstr = "Data returned: ".$myjson; &printlog($hash,$logstr,"4"); return($hash,$success)};
        
        $data = decode_json($myjson);
   
        $success = $data->{'success'};
        
        # Fall login war erfolgreich
        if ($success) 
        {
             # Logausgabe decodierte JSON Daten
             $logstr = "JSON returned: ". Dumper $data;                                                         
             &printlog($hash,$logstr,"4");
             
             $sid = $data->{'data'}->{'sid'};
             
             # Session ID in hash eintragen
             $hash->{HELPER}{SID} = $sid;
       
             # Setreading 
             readingsBeginUpdate($hash);
             readingsBulkUpdate($hash,"Errorcode","none");
             readingsBulkUpdate($hash,"Error","none");
             readingsEndUpdate($hash, 1);
       
             # Logausgabe
             $logstr = "Login of User $username successful - SID: $sid";
             &printlog($hash,$logstr,"4");
             $logstr = "--- End Function serverlogin nonblocking ---";
             &printlog($hash,$logstr,"4");    
       } 
       else 
       {
             # Errorcode aus JSON ermitteln
             $errorcode = $data->{'error'}->{'code'};
       
             # Fehlertext zum Errorcode ermitteln
             $error = &experrorauth($hash,$errorcode);

             # Setreading 
             readingsBeginUpdate($hash);
             readingsBulkUpdate($hash,"Errorcode",$errorcode);
             readingsBulkUpdate($hash,"Error",$error);
             readingsEndUpdate($hash, 1);
       
             # Logausgabe
             $logstr = "ERROR - Login of User $username unsuccessful. Errorcode: $errorcode - $error";
             &printlog($hash,$logstr,"1");
             
             $logstr = "--- End Function serverlogin nonblocking with error ---";
             &printlog($hash,$logstr,"4"); 
             
             # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
             $hash->{HELPER}{ACTIVE} = "off"; 
             
             return;
       }
   }
  
  
  # die Kamera-Id wird aus dem Kameranamen (Surveillance Station) ermittelt und mit Routine "camop_nonbl" verarbeitet
  # Logausgabe
  $logstr = "--- Begin Function getcamid nonblocking ---";
  &printlog($hash,$logstr,"4");
  
  # einlesen aller Kameras - Auswertung in Rückkehrfunktion "camop_nonbl"
  $url = "http://$servername:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=List&session=SurveillanceStation&_sid=\"$sid\"";

  $param = {
               url      => $url,
               timeout  => 10,
               hash     => $hash,
               method   => "GET",
               header   => "Accept: application/json",
               callback => \&camop_nonbl
           };
   
  HttpUtils_NonblockingGet ($param);
  
} 



#############################################################################################
####      Rückkehr aus Funktion Kamera-ID ermitteln (getcamid_nonbl),  
####      nach erfolgreicher Verarbeitung wird Kameraoperation entspr. "OpMode" ausgeführt
  
sub camop_nonbl ($) {  
   my ($param, $err, $myjson) = @_;
   my $hash              = $param->{hash};
   my $servername        = $hash->{SERVERNAME};
   my $serverport        = $hash->{SERVERPORT};
   my $camname           = $hash->{CAMNAME};
   my $apicam            = $hash->{HELPER}{APICAM};
   my $apicampath        = $hash->{HELPER}{APICAMPATH};
   my $apicammaxver      = $hash->{HELPER}{APICAMMAXVER};
   my $apiextrec         = $hash->{HELPER}{APIEXTREC};
   my $apiextrecpath     = $hash->{HELPER}{APIEXTRECPATH};
   my $apiextrecmaxver   = $hash->{HELPER}{APIEXTRECMAXVER};
   my $apitakesnap       = $hash->{HELPER}{APISNAPSHOT};
   my $apitakesnappath   = $hash->{HELPER}{APITAKESNAPPATH};
   my $apitakesnapmaxver = $hash->{HELPER}{APITAKESNAPMAXVER};
   my $sid               = $hash->{HELPER}{SID};
   my $OpMode            = $hash->{OPMODE};
   my $url;
   my $camid;
   my $data;
   my $logstr;
   my $success;
   my $error;
   my $errorcode;
   my $camcount;
   my $i;
   my %allcams;
   my $name;
   my $id;
  
   # Verarbeitung der asynchronen Rückkehrdaten aus sub "getcamid_nonbl"
   if ($err ne "")                                                                         # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
   {
        $logstr = "error while requesting ".$param->{url}." - $err";
        &printlog($hash,$logstr,"1");		                                           # Eintrag fürs Log
        $logstr = "--- End Function getcamid nonblocking with error ---";
        &printlog($hash,$logstr,"4");
        readingsSingleUpdate($hash, "Error", $err, 1);                                     # Readings erzeugen
 
        # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
        $hash->{HELPER}{ACTIVE} = "off"; 

        return;
   }
   elsif ($myjson ne "")                                                                   # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
   {
        $logstr = "URL-Call: ".$param->{url};                                                          
        &printlog($hash,$logstr,"4");                                          
         
        # An dieser Stelle die Antwort parsen / verarbeiten mit $myjson 
        
        # Evaluiere ob Daten im JSON-Format empfangen wurden, Achtung: sehr viele Daten mit verbose=5
        ($hash, $success) = &evaljson($hash,$myjson,$param->{url});
        unless ($success) {$logstr = "Data returned: ".$myjson; &printlog($hash,$logstr,"5"); return($hash,$success)};
        
        $data = decode_json($myjson);
   
        $success = $data->{'success'};
                
        if ($success)                                                                       # die Liste aller Kameras konnte ausgelesen werden, Anzahl der definierten Kameras ist in Var "total"
        {
             # lesbare Ausgabe der decodierten JSON-Daten
             $logstr = "JSON returned: ". Dumper $data;                                     # Achtung: SEHR viele Daten !                                              
             &printlog($hash,$logstr,"5");
                    
             $camcount = $data->{'data'}->{'total'};
             $i = 0;
         
             # Namen aller installierten Kameras mit Id's in Hash (Assoziatives Array) einlesen
             %allcams = ();
             while ($i < $camcount) 
                 {
                 $name = $data->{'data'}->{'cameras'}->[$i]->{'name'};
                 $id = $data->{'data'}->{'cameras'}->[$i]->{'id'};
                 $allcams{"$name"} = "$id";
                 $i += 1;
                 }
             
             # Ist der gesuchte Kameraname im Hash enhalten (in SS eingerichtet ?)
             if (exists($allcams{$camname})) 
             {
                 $camid = $allcams{$camname};
                 # in hash eintragen
                 $hash->{CAMID} = $camid;
                 
                 # Logausgabe
                 $logstr = "Detection Camid successful - $camname ID: $camid";
                 &printlog($hash,$logstr,"4");
                 $logstr = "--- End Function getcamid nonblocking ---";
                 &printlog($hash,$logstr,"4");  
             } 
             else 
             {
                 # Kameraname nicht gefunden, id = ""
                 
                 # Setreading 
                 readingsBeginUpdate($hash);
                 readingsBulkUpdate($hash,"Errorcode","none");
                 readingsBulkUpdate($hash,"Error","Camera(ID) not found in Surveillance Station");
                 readingsEndUpdate($hash, 1);
                                  
                 # Logausgabe
                 $logstr = "ERROR - Cameraname $camname wasn't found in Surveillance Station. Check Cameraname and Spelling.";
                 &printlog($hash,$logstr,"1");
                 $logstr = "--- End Function getcamid nonblocking with error ---";
                 &printlog($hash,$logstr,"4");
                 
                 # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
                 $hash->{HELPER}{ACTIVE} = "off"; 
           
                 return;
              }
       }
       else 
       {
            # Errorcode aus JSON ermitteln
            $errorcode = $data->{'error'}->{'code'};

            # Fehlertext zum Errorcode ermitteln
            $error = &experror($hash,$errorcode);
       
            # Setreading 
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode",$errorcode);
            readingsBulkUpdate($hash,"Error",$error);
            readingsEndUpdate($hash, 1);

            # Logausgabe
            $logstr = "ERROR - ID of Camera $camname couldn't be selected. Errorcode: $errorcode - $error";
            &printlog($hash,$logstr,"1");
            $logstr = "--- End Function getcamid nonblocking with error ---";
            &printlog($hash,$logstr,"4");
            
            # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
            $hash->{HELPER}{ACTIVE} = "off"; 
            
            return;
       }
       
   # Logausgabe
   $logstr = "--- Begin Function cam: $OpMode nonblocking ---";
   &printlog($hash,$logstr,"4");

   if ($OpMode eq "Start") 
   {
      # die Aufnahme wird gestartet, Rückkehr wird mit "camret_nonbl" verarbeitet
      $url = "http://$servername:$serverport/webapi/$apiextrecpath?api=$apiextrec&method=Record&version=$apiextrecmaxver&cameraId=$camid&action=start&session=SurveillanceStation&_sid=\"$sid\""; 
   } 
   elsif ($OpMode eq "Stop")
   {
      # die Aufnahme wird gestoppt, Rückkehr wird mit "camret_nonbl" verarbeitet
      $url = "http://$servername:$serverport/webapi/$apiextrecpath?api=$apiextrec&method=Record&version=$apiextrecmaxver&cameraId=$camid&action=stop&session=SurveillanceStation&_sid=\"$sid\"";
   }
   elsif ($OpMode eq "Snap")
   {
      # ein Schnappschuß wird ausgelöst und in SS gespeichert, Rückkehr wird mit "camret_nonbl" verarbeitet
      $url = "http://$servername:$serverport/webapi/$apitakesnappath?api=\"$apitakesnap\"&dsId=0&method=\"TakeSnapshot\"&version=\"$apitakesnapmaxver\"&camId=$camid&blSave=true&_sid=\"$sid\"";
      $hash->{STATE} = "snap";
      readingsSingleUpdate($hash, "LastSnapId", "", 1);
   }
   elsif ($OpMode eq "Enable")
   {
      # eine Kamera wird aktiviert, Rückkehr wird mit "camret_nonbl" verarbeitet
      $url = "http://$servername:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=Enable&cameraIds=$camid&_sid=\"$sid\"";     
   }
   elsif ($OpMode eq "Disable")
   {
      # eine Kamera wird aktiviert, Rückkehr wird mit "camret_nonbl" verarbeitet
      $url = "http://$servername:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=Disable&cameraIds=$camid&_sid=\"$sid\"";     
   }
  
   $param = {
                url      => $url,
                timeout  => 10,
                hash     => $hash,
                method   => "GET",
                header   => "Accept: application/json",
                callback => \&camret_nonbl
            };
   
   HttpUtils_NonblockingGet ($param);   

   } 
} 
  
  
###################################################################################  
####      Rückkehr aus Funktion camop_nonbl,  
####      Check ob Kameraoperation erfolgreich wie in "OpMOde" definiert 
####      danach logout
  
sub camret_nonbl ($) {  
   my ($param, $err, $myjson) = @_;
   my $hash             = $param->{hash};
   my $name             = $hash->{NAME};
   my $servername       = $hash->{SERVERNAME};
   my $serverport       = $hash->{SERVERPORT};
   my $camname          = $hash->{CAMNAME};
   my $rectime          = $hash->{RECTIME};
   my $apiauth          = $hash->{HELPER}{APIAUTH};
   my $apiauthpath      = $hash->{HELPER}{APIAUTHPATH};
   my $apiauthmaxver    = $hash->{HELPER}{APIAUTHMAXVER};
   my $sid              = $hash->{HELPER}{SID};
   my $OpMode           = $hash->{OPMODE};
   my $url;
   my $data;
   my $logstr;
   my $success;
   my $error;
   my $errorcode;
   my $snapid;
  
   # Verarbeitung der asynchronen Rückkehrdaten aus sub "camop_nonbl"
   if ($err ne "")                                                                                     # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
   {
        $logstr = "error while requesting ".$param->{url}." - $err";
        &printlog($hash,$logstr,"1");		                                                      # Eintrag fürs Log
        $logstr = "--- End Function cam: $OpMode nonblocking with error ---";
        &printlog($hash,$logstr,"4");
        
        readingsSingleUpdate($hash, "Error", $err, 1);                                     	       # Readings erzeugen
        
        # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
        $hash->{HELPER}{ACTIVE} = "off"; 

        return;
   }
   elsif ($myjson ne "")                                                                                # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
   {
        $logstr = "URL-Call: ".$param->{url};                                                          
        &printlog($hash,$logstr,"4");
  
        # An dieser Stelle die Antwort parsen / verarbeiten mit $myjson 
      
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, $success) = &evaljson($hash,$myjson,$param->{url});
        unless ($success) {$logstr = "Data returned: ".$myjson; &printlog($hash,$logstr,"4"); return($hash,$success)};
        
        $data = decode_json($myjson);
   
        $success = $data->{'success'};

        if ($success) 
        {       
            # Kameraoperation entsprechend "OpMode" war erfolgreich
            
            # Logausgabe decodierte JSON Daten
            $logstr = "JSON returned: ". Dumper $data;                                                        
            &printlog($hash,$logstr,"4");
                
            if ($OpMode eq "Start") 
            {  
                # bedingt Browseraktualisierung und Status der "Lampen" 
                $hash->{STATE} = "on";
                               
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Record","Start");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                $logstr = "Camera $camname with Recordtime $rectime"."s started";
                &printlog($hash,$logstr,"3");  
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");                
       
                # Logausgabe
                $logstr = "Time for Recording is set to: $rectime";
                &printlog($hash,$logstr,"4");
                
                # Stop der Aufnahme nach Ablauf $rectime
                InternalTimer(gettimeofday()+$rectime, "camstoprec", $hash, 0);
                                  

            }
            elsif ($OpMode eq "Stop") 
            {
                # bedingt Browseraktualisierung und Status der "Lampen" 
                $hash->{STATE} = "off";
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Record","Stop");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
            
                # RemoveInternalTimer($hash);
       
                # Logausgabe
                $logstr = "Camera $camname Recording stopped";
                &printlog($hash,$logstr,"3");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "Snap") 
            {
                # ein Schnapschuß wurde aufgenommen
                # falls Aufnahme noch läuft -> STATE = on setzen
                if (ReadingsVal("$name", "Record", "Stop") eq "Start") {
                    $hash->{STATE} = "on";
                    }
                    else
                    {
                    $hash->{STATE} = "off";
                    }
                
                $snapid = $data->{data}{'id'};
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsBulkUpdate($hash,"LastSnapId",$snapid);
                readingsEndUpdate($hash, 1);
                                
                # Logausgabe
                $logstr = "Snapshot of Camera $camname has been done successfully";
                &printlog($hash,$logstr,"3");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "Enable") 
            {
                # Kamera wurde aktiviert
                $hash->{STATE} = "enable";
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Availability","enabled");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                   
                # Logausgabe
                $logstr = "Camera $camname has been enabled successfully";
                &printlog($hash,$logstr,"3");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "Disable") 
            {
                # Kamera wurde deaktiviert
                $hash->{STATE} = "disable";
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Availability","disabled");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                   
                # Logausgabe
                $logstr = "Camera $camname has been disabled successfully";
                &printlog($hash,$logstr,"3");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
       }
       else 
       {
            # die URL konnte nicht erfolgreich aufgerufen werden
            # Errorcode aus JSON ermitteln
            $errorcode = $data->{'error'}->{'code'};

            # Fehlertext zum Errorcode ermitteln
            $error = &experror($hash,$errorcode);

            # Setreading 
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode",$errorcode);
            readingsBulkUpdate($hash,"Error",$error);
            readingsEndUpdate($hash, 1);
       
            # Logausgabe
            $logstr = "ERROR - Operation $OpMode of Camera $camname was not successful. Errorcode: $errorcode - $error";
            &printlog($hash,$logstr,"1");
            $logstr = "--- End Function cam: $OpMode nonblocking with error ---";
            &printlog($hash,$logstr,"4");
            
            # ausgeführte Funktion ist abgebrochen, Freigabe Funktionstoken
            $hash->{HELPER}{ACTIVE} = "off"; 
           
            return;

       }
    # logout wird ausgeführt, Rückkehr wird mit "logout_nonbl" verarbeitet
    # Logausgabe
    $logstr = "--- Begin Function logout nonblocking ---";
    &printlog($hash,$logstr,"4");
  
    $url = "http://$servername:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Logout&session=SurveillanceStation&_sid=$sid"; 

    $param = {
                url      => $url,
                timeout  => 10,
                hash     => $hash,
                method   => "GET",
                header   => "Accept: application/json",
                callback => \&logout_nonbl
             };
   
    HttpUtils_NonblockingGet ($param);
   }
}


###################################################################################  
####      Rückkehr aus Funktion camret_nonbl,  
####      check Funktion logout
  
sub logout_nonbl ($) {  
   my ($param, $err, $myjson) = @_;
   my $hash            = $param->{hash};
   my $username        = $hash->{USERNAME};
   my $sid             = $hash->{HELPER}{SID};
   my $data;
   my $logstr;
   my $success;
   my $error;
   my $errorcode;
  
   # ausgeführte Funktion ist erledigt (auch wenn logout nicht erfolgreich), Freigabe Funktionstoken
   $hash->{HELPER}{ACTIVE} = "off";   
   
   if($err ne "")                                                                                     # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
   {
        $logstr = "error while requesting ".$param->{url}." - $err";
        &printlog($hash,$logstr,"1");		                                                      # Eintrag fürs Log
        $logstr = "--- End Function logout nonblocking with error ---";
        &printlog($hash,$logstr,"4");
        
        readingsSingleUpdate($hash, "Error", $err, 1);                                     	       # Readings erzeugen 

        return;
   }
   elsif($myjson ne "")                                                                                # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
   {
        $logstr = "URL-Call: ".$param->{url};                                                          
        &printlog($hash,$logstr,"4");
        
        # An dieser Stelle die Antwort parsen / verarbeiten mit $myjson 
        
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, $success) = &evaljson($hash,$myjson,$param->{url});
        unless ($success) {$logstr = "Data returned: ".$myjson; &printlog($hash,$logstr,"4"); return($hash,$success)};
        
        $data = decode_json($myjson);
   
        $success = $data->{'success'};

        if ($success)  
        {
             # die Logout-URL konnte erfolgreich aufgerufen werden
             # Logausgabe decodierte JSON Daten
             $logstr = "JSON returned: ". Dumper $data;                                                        
             &printlog($hash,$logstr,"4");
                        
             # Session-ID aus Helper-hash löschen
             delete $hash->{HELPER}{SID};
             
             # Logausgabe
             $logstr = "Session of User $username has ended - SID: $sid has been deleted";
             &printlog($hash,$logstr,"4");
             $logstr = "--- End Function logout nonblocking ---";
             &printlog($hash,$logstr,"4");
             
        } 
        else 
        {
             # Errorcode aus JSON ermitteln
             $errorcode = $data->{'error'}->{'code'};

             # Fehlertext zum Errorcode ermitteln
             $error = &experrorauth($hash,$errorcode);
    
             # Logausgabe
             $logstr = "ERROR - Logout of User $username was not successful. Errorcode: $errorcode - $error";
             &printlog($hash,$logstr,"1");
             $logstr = "--- End Function logout nonblocking with error ---";
             &printlog($hash,$logstr,"4");
         }
   }
}

#############################################################################################################################
#########              Ende Kameraoperationen mit NonblockingGet (nicht blockierender HTTP-Call)                #############
#############################################################################################################################



#############################################################################################################################
#########                                               Hilfsroutinen                                           #############
#############################################################################################################################

###############################################################################
###   Test ob JSON-String empfangen wurde
  
sub evaljson { 
  my ($hash,$myjson,$url)= @_;
  my $success = 1;
  my $e;
  my $logstr;
  
  eval {decode_json($myjson);1;} or do 
  {
      $success = 0;
      $e = $@;
  
      # Setreading 
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,"Errorcode","none");
      readingsBulkUpdate($hash,"Error","malformed JSON string received");
      readingsEndUpdate($hash, 1);
  };
return($hash,$success);
}

##############################################################################
###  Auflösung Errorcodes bei Login / Logout

sub experrorauth {
  # Übernahmewerte sind $hash, $errorcode
  my ($hash,@errorcode) = @_;
  my $device = $hash->{NAME};
  my $errorcode = shift @errorcode;
  my %errorlist;
  my $error;
  
  # Aufbau der Errorcode-Liste (siehe Surveillance_Station_Web_API_v2.0.pdf)
  %errorlist = (
  100 => "Unknown error",
  101 => "The account parameter is not specified",
  102 => "API does not exist",
  400 => "Invalid user or password",
  401 => "Guest or disabled account",
  402 => "Permission denied",
  403 => "One time password not specified",
  404 => "One time password authenticate failed",
  );
  unless (exists ($errorlist {$errorcode})) {$error = "Message for Errorode $errorcode not found. Please turn to Synology Web API-Guide."; return ($error);}

  # Fehlertext aus Hash-Tabelle oben ermitteln
  $error = $errorlist {$errorcode};
return ($error);
}

##############################################################################
###  Auflösung Errorcodes SS API

sub experror {
  # Übernahmewerte sind $hash, $errorcode
  my ($hash,@errorcode) = @_;
  my $device = $hash->{NAME};
  my $errorcode = shift @errorcode;
  my %errorlist;
  my $error;
  
  # Aufbau der Errorcode-Liste (siehe Surveillance_Station_Web_API_v2.0.pdf)
  %errorlist = (
  100 => "Unknown error",
  101 => "Invalid parameters",
  102 => "API does not exist",
  103 => "Method does not exist",
  104 => "This API version is not supporte",
  105 => "Insufficient user privilege",
  106 => "Connection time out",
  107 => "Multiple login detected",
  400 => "Execution failed",
  401 => "Parameter invalid",
  402 => "Camera disabled",
  403 => "Insufficient license",
  404 => "Codec acitvation failed",
  405 => "CMS server connection failed",
  407 => "CMS closed",
  410 => "Service is not enabled",
  412 => "Need to add license",
  413 => "Reach the maximum of platform",
  414 => "Some events not exist",
  415 => "message connect failed",
  417 => "Test Connection Error",
  418 => "Object is not exist",
  419 => "Visualstation name repetition",
  439 => "Too many items selected",
  );
  unless (exists ($errorlist {$errorcode})) {$error = "Message for Errorode $errorcode not found. Please turn to Synology Web API-Guide."; return ($error);}

  # Fehlertext aus Hash-Tabelle oben ermitteln
  $error = $errorlist {$errorcode};
  return ($error);
}

############################################################################
###  Logausgabe

sub printlog {
  # Übernahmewerte ist $hash, $logstr, $verb (Verbose-Level)
  my ($hash,$logstr,$verb)= @_;
  my $name = $hash->{NAME};
  
  Log3 ($name, $verb, "$name - $logstr");
return;
}


1;

=pod
=begin html

<a name="SSCam"></a>
<h3>SSCam</h3>
<ul>
  <br>
    Using this Module you are able to operate with cameras which are defined in Synology Surveillance Station. <br>
    At present the following functions are available: <br><br>
    <ul>
     <ul>
        <li>Start a Rocording</li>
        <li>Stop a Recording</li>
        <li>Trigger a Snapshot </li>
        <li>Deaktivate a Camera in Synology Surveillance Station</li>
        <li>Activate a Camera in Synology Surveillance Station</li><br>
     </ul>
    </ul>
    The recordings and snapshots will be stored in Synology Surveillance Station and are managed like the other (normal) recordings / snapshots defined by Surveillance Station rules.<br>
    For example the recordings are stored for a defined time in Surveillance Station and will be deleted after that period.<br><br>
    
    If you like to discuss or help to improve this module please use FHEM-Forum with link: <br>
    <a href="http://forum.fhem.de/index.php/topic,45671.msg374390.html#msg374390">49_SSCam: Fragen, Hinweise, Neuigkeiten und mehr rund um dieses Modul</a>.<br><br>
  
<b> Prerequisites </b> <br><br>
    This module uses the CPAN-module JSON. Please consider to install this package (Debian: libjson-perl).<br>
    You don't need to install LWP anymore, because of SSCam is completely using the nonblocking functions of HttpUtils respectively HttpUtils_NonblockingGet now. <br> 
    You also need to add an user in Synology DSM as member of Administrators group. <br><br>
    

  <a name="SCamdefine"></a>
  <b>Define</b>
  <ul>
  <br>
    <code>define &lt;name&gt; SSCam &lt;Servername&gt; &lt;Port&gt; &lt;Username&gt; &lt;Password&gt; &lt;Cameraname&gt; &lt;RecordTime&gt;</code><br>
    <br>
    Defines a new camera device for SSCam. At first the devices have to be set up and operable in Synology Surveillance Station 7.0 and above. <br><br>
    
    The parameter &lt;RecordTime&gt; describes the minimum Recordtime. Dependend on other factors like the performance of your Synology Diskstation and <br>
    Surveillance Station the effective Recordtime could be longer.
    
    The Modul SSCam ist based on functions of Synology Surveillance Station API. <br>
    Please refer the <a href="http://global.download.synology.com/download/Document/DeveloperGuide/Surveillance_Station_Web_API_v2.0.pdf">Web API Guide</a>. <br><br>
    
    At present only HTTP-protocol is supported to call Synology DS. <br><br>  

    The parameters are in detail:
   <br>
   <br>    
    
    <table>
    <colgroup> <col width=15%> <col width=85%> </colgroup>
    <tr><td>name   :</td><td>the name of the new device to use in FHEM</td></tr>
    <tr><td>Servername   :</td><td>the name or IP-address of Synology Surveillance Station Host. If Servername is used, make sure the name can be discovered in network by DNS </td></tr>
    <tr><td>Port   :</td><td>the Port Synology surveillance Station Host, normally 5000 (HTTP only)</td></tr>
    <tr><td>Username   :</td><td>Username defined in the Diskstation. Has to be a member of Admin-group</td></tr>
    <tr><td>Password   :</td><td>the Password for the User</td></tr>
    <tr><td>Cameraname   :</td><td>Cameraname as defined in Synology Surveillance Station, Spaces are not allowed in Cameraname !</td></tr>
    <tr><td>Recordtime   :</td><td>it's the time for recordings </td></tr>
    </table>

    <br><br>

    <b>Examples:</b>
     <pre>
      define CamDoor SSCAM ds1.myds.ds 5000 apiuser apipass Door 10      
    </pre>
  </ul>
  <br>
  
  
<a name="SSCamset"></a>
<b>Set </b>
  <ul>
    
    There are the following options for "Set" at present: <br><br>

  <table>
  <colgroup> <col width=15%> <col width=85%> </colgroup>
      <tr><td>"on":          </td><td>starts a recording. The recording will be stopped automatically after a period of &lt;RecordTime&gt; as determined</td></tr>
      <tr><td>"off" :        </td><td>stopps a running recording manually or using other events (e.g. with at, notify)</td></tr>
      <tr><td>"snap":        </td><td>triggers a snapshot of the relevant camera and store it into Synology Surveillance Station</td></tr>
      <tr><td>"disable":     </td><td>deactivates a camera in Synology Surveillance Station</td></tr>
      <tr><td>"enable":      </td><td>activates a camera in Synology Surveillance Station</td></tr>

  </table>
  <br><br>
        
  Example for simple <b>Start/Stop of a Recording</b>: <br><br>

  <table>
  <colgroup> <col width=15%> <col width=85%> </colgroup>
      <tr><td>set &lt;name&gt; on   </td><td>starts a recording of camera &lt;name&gt;, stops automatically after the time &lt;RecordTime&gt; as determined in device-definition </td></tr>
      <tr><td>set &lt;name&gt; off   </td><td>stops the recording of camera &lt;name&gt;</td></tr>
  </table>
  <br>

  A snapshot can be triggered with:
  <pre> 
     set &lt;name&gt; snap 
  </pre>

  Subsequent some Examples for <b>taking snapshots</b>: <br><br>
  
  If a serial of snapshots should be released, it can be done using the following notify command.
  For the example a serial of snapshots are to be triggerd if the recording of a camera starts. <br>
  When the recording of camera "CamHE1" starts (Attribut event-on-change-reading -> "Record" has to be set), then 3 snapshots at intervals of 2 seconds are triggered.

  <pre>
     define he1_snap_3 notify CamHE1:Record.*Start define h3 at +*{3}00:00:02 set CamHE1 snap 
  </pre>

  Release of 2 Snapshots of camera "CamHE1" at intervals of 6 seconds after the motion sensor "MelderHE1" has sent an event, <br>
  can be done e.g. with following notify-command:

  <pre>
     define he1_snap_2 notify MelderHE1:on.* define h2 at +*{2}00:00:06 set CamHE1 snap 
  </pre>

  The ID of the last snapshot will be displayed as value of variable "LastSnapId" in the device-Readings. <br><br>
  
  For <br>deactivating / activating</br> a list of cameras or all cameras using a Regex-expression, subsequent two examples using "at":
  <pre>
     define a13 at 21:46 set CamCP1,CamFL,CamHE1,CamTER disable (enable)
     define a14 at 21:46 set Cam.* disable (enable)
  </pre>
  
  A bit more convenient is it to use a dummy-device for enable/disable all available cameras in Surveillance Station.<br>
  At first the Dummy will be created.
  <pre>
     define allcams dummy
     attr allcams eventMap on:enable off:disable
     attr allcams room Cams
     attr allcams webCmd enable:disable
  </pre>
  
  With combination of two created notifies, respectively one for "enable" and one for "diasble", you are able to switch all cameras into "enable" or "disable" state at the same time if you set the dummy to "enable" or "disable". 
  <pre>
     define all_cams_disable notify allcams:.*off set CamCP1,CamFL,CamHE1,CamTER disable
     attr all_cams_disable room Cams

     define all_cams_enable notify allcams:on set CamCP1,CamFL,CamHE1,CamTER enable
     attr all_cams_enable room Cams
  </pre>
  
 </ul>
<br>

  
  
<a name="SSCamattr"></a>
<b>Attributes</b>
<ul>
  
   Different Verbose-Level are supported.<br>
   Those are in detail:<br><br>
   
   <table>  
   <colgroup> <col width=5%> <col width=95%> </colgroup>
     <tr><td> 0  </td><td> Start/Stop-Event will be logged </td></tr>
     <tr><td> 1  </td><td> Error messages will be logged <td></tr>
     <tr><td> 3  </td><td> sended commands will be logged <td></tr> 
     <tr><td> 4  </td><td> sended and received informations will be logged <td></tr>
     <tr><td> 5  </td><td> all outputs will be logged for error-analyses. <b>Caution:</b> a lot of data could be written into the logfile ! <td></tr>
   <table>  

   <br><br>
  
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>


=end html
=begin html_DE

<a name="SSCam"></a>
<h3>SSCam</h3>
<ul>
  <br>
    Mit diesem Modul können Operationen von in der Synology Surveillance Station definierten Kameras ausgeführt werden. <br>
    Zur Zeit werden folgende Funktionen unterstützt: <br><br>
    <ul>
     <ul>
      <li>Start einer Aufnahme</li>
      <li>Stop einer Aufnahme</li>
      <li>Aufnehmen eines Schnappschusses und Ablage in der Synology Surveillance Station </li>
      <li>Deaktivieren einer Kamera in Synology Surveillance Station</li>
      <li>Aktivieren einer Kamera in Synology Surveillance Station</li><br>
     </ul> 
    </ul>
    Die Aufnahmen stehen in der Synology Surveillance Station zur Verfügung und unterliegen, wie jede andere Aufnahme, den in der Synology Surveillance Station eingestellten Regeln. <br>
    So werden zum Beispiel die Aufnahmen entsprechend ihrer Archivierungsfrist gehalten und dann gelöscht. <br><br>
    
    Wenn du über dieses Modul diskutieren oder zur Verbesserung des Moduls beitragen möchtest ist im FHEM-Forum ein Sammelplatz unter:<br>
    <a href="http://forum.fhem.de/index.php/topic,45671.msg374390.html#msg374390">49_SSCam: Fragen, Hinweise, Neuigkeiten und mehr rund um dieses Modul</a>.<br><br>

<b>Vorbereitung </b> <br><br>
    Dieses Modul nutzt das CPAN Module JSON. Bitte darauf achten dieses Paket zu installieren. (Debian: libjson-perl). <br>
    Das CPAN-Modul LWP wird für SSCam nicht mehr benötigt. Das Modul verwendet für HTTP-Calls die nichtblockierenden Funktionen von HttpUtils bzw. HttpUtils_NonblockingGet. <br> 
    Im DSM muß ebenfalls ein Nutzer als Mitglied der Administratorgruppe angelegt sein. Die Daten werden bei der Definition des Gerätes benötigt.<br><br>

<a name="SCamdefine"></a>
<b>Define</b>
  <ul>
  <br>
    <code>define &lt;name&gt; SSCam &lt;Servername&gt; &lt;Port&gt; &lt;Username&gt; &lt;Password&gt; &lt;Kameraname in SS&gt; &lt;RecordTime&gt;</code><br>
    <br>
    
    Definiert eine neue Kamera für SSCam. Zunächst muß diese Kamera in der Synology Surveillance Station 7.0 oder höher eingebunden sein und entsprechend funktionieren.<br><br>
    
    Der Parameter "&lt;RecordTime&gt; beschreibt die Mindestaufnahmezeit. Abhängig von Faktoren wie Performance der Synology Diskstation und der Surveillance Station <br>
    kann die effektive Aufnahmezeit geringfügig länger sein.<br><br>
    
    Das Modul SSCam basiert auf Funktionen der Synology Surveillance Station API. <br>
    Weitere Informationen unter: <a href="http://global.download.synology.com/download/Document/DeveloperGuide/Surveillance_Station_Web_API_v2.0.pdf">Web API Guide</a>. <br><br>
    
    Momentan wird nur das HTTP-Protokoll unterstützt um die Web-Services der Synology DS aufzurufen. <br><br>  
    
    Die Parameter beschreiben im Einzelnen:
   <br>
   <br>    
    
    <table>
    <colgroup> <col width=15%> <col width=85%> </colgroup>
    <tr><td>name:           </td><td>der Name des neuen Gerätes in FHEM</td></tr>
    <tr><td>Servername:     </td><td>der Name oder die IP-Addresse des Synology Surveillance Station Host. Wenn der Servername benutzt wird ist sicherzustellen dass der Name im Netzwerk aufgelöst werden kann.</td></tr>
    <tr><td>Port:           </td><td>der Port des Synology Surveillance Station Host. Normalerweise ist das 5000 (nur HTTP)</td></tr>
    <tr><td>Username:       </td><td>Name des in der Diskstation definierten Nutzers. Er muß ein Mitglied der Admin-Gruppe sein</td></tr>
    <tr><td>Password:       </td><td>das Passwort des Nutzers</td></tr>
    <tr><td>Cameraname:     </td><td>Kameraname wie er in der Synology Surveillance Station angegeben ist. Leerzeichen im Namen sind nicht erlaubt !</td></tr>
    <tr><td>Recordtime:     </td><td>die definierte Aufnahmezeit</td></tr>
    </table>

    <br><br>

    <b>Beispiel:</b>
     <pre>
      define CamTür SSCAM ds1.myds.ds 5000 apiuser apipass Tür 10      
     </pre>
  </ul>
  
  
<a name="SSCamset"></a>
<b>Set </b>
<ul>
    
    Es gibt zur Zeit folgende Optionen für "Set": <br><br>

  <table>
  <colgroup> <col width=15%> <col width=85%> </colgroup>
      <tr><td>"on":          </td><td>startet eine Aufnahme. Die Aufnahme wird automatisch nach Ablauf der Zeit &lt;RecordTime&gt; gestoppt.</td></tr>
      <tr><td>"off" :        </td><td>stoppt eine laufende Aufnahme manuell oder durch die Nutzung anderer Events (z.B. über at, notify)</td></tr>
      <tr><td>"snap":        </td><td>löst einen Schnappschuß der entsprechenden Kamera aus und speichert ihn in der Synology Surveillance Station</td></tr>
      <tr><td>"disable":     </td><td>deaktiviert eine Kamera in der Synology Surveillance Station</td></tr>
      <tr><td>"enable":      </td><td>aktiviert eine Kamera in der Synology Surveillance Station</td></tr>
  </table>
  <br><br>
        
  Beispiele für einfachen <b>Start/Stop einer Aufnahme</b>: <br><br>

  <table>
  <colgroup> <col width=15%> <col width=85%> </colgroup>
      <tr><td>set &lt;name&gt; on   </td><td>startet die Aufnahme der Kamera &lt;name&gt;, automatischer Stop der Aufnahme nach Ablauf der Zeit &lt;RecordTime&gt; wie im define angegeben</td></tr>
      <tr><td>set &lt;name&gt; off   </td><td>stoppt die Aufnahme der Kamera &lt;name&gt;</td></tr>
  </table>
  <br>

  Ein <b>Schnappschuß</b> kann ausgelöst werden durch:
  <pre> 
     set &lt;name&gt; snap 
  </pre>
  
  Nachfolgend einige Beispiele für die <b>Auslösung von Schnappschüssen</b>. <br><br>
  
  Soll eine Reihe von Schnappschüssen ausgelöst werden wenn eine Aufnahme startet, kann das z.B. durch folgendes notify geschehen. <br>
  Sobald der Start der Kamera CamHE1 ausgelöst wird (Attribut event-on-change-reading -> "Record" setzen), werden abhängig davon 3 Snapshots im Abstand von 2 Sekunden getriggert.

  <pre>
     define he1_snap_3 notify CamHE1:Record.*Start define h3 at +*{3}00:00:02 set CamHE1 snap
  </pre>
  
  Triggern von 2 Schnappschüssen der Kamera "CamHE1" im Abstand von 6 Sekunden nachdem der Bewegungsmelder "MelderHE1" einen Event gesendet hat, <br>
  kann z.B. mit folgendem notify geschehen:

  <pre>
     define he1_snap_2 notify MelderHE1:on.* define h2 at +*{2}00:00:06 set CamHE1 snap 
  </pre>

  Es wird die ID des letzten Snapshots als Wert der Variable "LastSnapId" in den Readings der Kamera ausgegeben. <br><br>
  
  Um eine Liste von Kameras oder alle Kameras (mit Regex) zum Beispiel um 21:46 zu <b>deaktivieren</b> / zu <b>aktivieren</b> zwei Beispiele mit at:
  <pre>
     define a13 at 21:46 set CamCP1,CamFL,CamHE1,CamTER disable (enable)
     define a14 at 21:46 set Cam.* disable (enable)
  </pre>
  
  Etwas komfortabler gelingt das Schalten aller Kameras über einen Dummy. Zunächst wird der Dummy angelegt:
  <pre>
     define allcams dummy
     attr allcams eventMap on:enable off:disable
     attr allcams room Cams
     attr allcams webCmd enable:disable
  </pre>
  
  Durch Verknüpfung mit zwei angelegten notify, jeweils ein notify für "enable" und "disable", kann man durch Schalten des Dummys auf "enable" bzw. "disable" alle Kameras auf einmal aktivieren bzw. deaktivieren.
  <pre>
     define all_cams_disable notify allcams:.*off set CamCP1,CamFL,CamHE1,CamTER disable
     attr all_cams_disable room Cams

     define all_cams_enable notify allcams:on set CamCP1,CamFL,CamHE1,CamTER enable
     attr all_cams_enable room Cams
  </pre>


</ul>
  <br>

  
  
<a name="SSCamattr"></a>
<b>Attribute</b>
  <ul>
  
   Es werden verschiedene Verbose-Level unterstützt.<br>
   Dies sind im Einzelnen:<br><br>
   
   <table>  
   <colgroup> <col width=5%> <col width=95%> </colgroup>
     <tr><td> 0  </td><td> Start/Stop-Ereignisse werden geloggt </td></tr>
     <tr><td> 1  </td><td> Fehlermeldungen werden geloggt </td></tr>
     <tr><td> 3  </td><td> gesendete Kommandos werden geloggt </td></tr>
     <tr><td> 4  </td><td> gesendete und empfangene Daten werden geloggt </td></tr>
     <tr><td> 5  </td><td> alle Ausgaben zur Fehleranalyse werden geloggt. <b>ACHTUNG:</b> möglicherweise werden sehr viele Daten in das Logfile geschrieben! </td></tr>
   </table>

   <br><br>
        
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>

=end html_DE
=cut

