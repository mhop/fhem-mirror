#####################################################################################################
#       49_SSCam.pm
#
#       Copyright by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This Modul is used to manage Cameras defined in Synology Surveillance Station 7.0 or higher
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
#
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


sub
SSCam_Initialize($)
{
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
  $hash->{HELPER}{APIINFO}   = "SYNO.API.Info";                             # Info-Seite für alle API's, einzige statische Seite !                                                    
  $hash->{HELPER}{APIAUTH}   = "SYNO.API.Auth";                                                  
  $hash->{HELPER}{APIEXTREC} = "SYNO.SurveillanceStation.ExternalRecording";                     
  $hash->{HELPER}{APICAM}    = "SYNO.SurveillanceStation.Camera"; 

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
	my $device = shift @a;
	my $opt = shift @a;
	my %SSCam_sets = (
	                 on => "on",
	                 off => "off");
	my $camname = $hash->{CAMNAME};
	my $logstr;
	my @cList;
	
	# ist die angegebene Option verfügbar ?
	if(!defined($SSCam_sets{$opt})) {
		@cList = keys %SSCam_sets; 
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
                } else {
                          
                # Aufnahme starten
                if ($opt eq "on") 
                        {
                        $logstr = "Recording of Camera $camname should be started now";
                        &printlog($hash,$logstr,"4");
                        
                        $hash->{OPMODE} = "Start";
                        &getapisites_nonbl($hash);
                        }
                    
                    
                # Aufnahme stoppen
                if ($opt eq "off") 
                        {
                        $logstr = "Recording of Camera $camname should be stopped now";
                        &printlog($hash,$logstr,"4");
                        
                        $hash->{OPMODE} = "Stop";
                        &getapisites_nonbl($hash);
                        }
                }          
}


#############################################################################################################################
#######    Begin Kameraoperationen mit NonblockingGet (nicht blockierender HTTP-Call)                                 #######
#######                                                                                                               #######
#######    Ablauflogik:                                                                                               #######
#######                                                                                                               #######
#######    getapisites_nonbl -> login_nonbl ->  getcamid_nonbl  -> camop_nonbl ->  camret_nonbl -> logout_nonbl       #######
#######                                                             |       |                                         #######
#######                                                           Start    Stop                                       #######
#######                                                                                                               #######
#############################################################################################################################

sub getapisites_nonbl {
   my ($hash) = @_;
   my $servername = $hash->{SERVERNAME};
   my $serverport = $hash->{SERVERPORT};
   my $apiinfo    = $hash->{HELPER}{APIINFO};                         # Info-Seite für alle API's, einzige statische Seite !
   my $apiauth    = $hash->{HELPER}{APIAUTH};                         # benötigte API-Pfade für Funktionen,  
   my $apiextrec  = $hash->{HELPER}{APIEXTREC};                       # in der Abfrage-Url an Parameter "&query="
   my $apicam     = $hash->{HELPER}{APICAM};                          # mit Komma getrennt angeben
   my $logstr;
   my $url;
   my $param;
  
   #### API-Pfade und MaxVersions ermitteln #####
   # Logausgabe
   $logstr = "--- Begin Function getapisites nonblocking ---";
   &printlog($hash,$logstr,"4");
   
   # URL zur Abfrage der Eigenschaften von API SYNO.SurveillanceStation.ExternalRecording,$apicam
   $url = "http://$servername:$serverport/webapi/query.cgi?api=$apiinfo&method=Query&version=1&query=$apiauth,$apiextrec,$apicam";
   
   $param = {
               url      => $url,
               timeout  => 5,
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
   my $hash       = $param->{hash};
   my $device     = $hash->{NAME};
   my $servername = $hash->{SERVERNAME};
   my $serverport = $hash->{SERVERPORT};
   my $username   = $hash->{USERNAME};
   my $password   = $hash->{HELPER}{PASSWORD};
   my $apiauth    = $hash->{HELPER}{APIAUTH};
   my $apiextrec  = $hash->{HELPER}{APIEXTREC};
   my $apicam     = $hash->{HELPER}{APICAM};
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
   my $error;
  
    # Verarbeitung der asynchronen Rückkehrdaten aus sub "getapisites_nonbl"
    if ($err ne "")                                                                                    # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
    {
        $logstr = "error while requesting ".$param->{url}." - $err";
        &printlog($hash,$logstr,"1");	                                                             
        $logstr = "--- End Function getapisites nonblocking with error ---";
        &printlog($hash,$logstr,"4");
        readingsSingleUpdate($hash, "Error", $err, 1);                                     	       # Readings erzeugen
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
       
			# maximale Version ermitteln
			$apiauthmaxver = $data->{'data'}->{$apiauth}->{'maxVersion'}; 
       
			$logstr = "Path of $apiauth selected: $apiauthpath";
			&printlog($hash, $logstr,"4");
			$logstr = "MaxVersion of $apiauth selected: $apiauthmaxver";
			&printlog($hash, $logstr,"4");
       
			# Pfad und Maxversion von "SYNO.SurveillanceStation.ExternalRecording" ermitteln
       
			$apiextrecpath = $data->{'data'}->{$apiextrec}->{'path'};
			# Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
			$apiextrecpath =~ tr/_//d;
       
			# maximale Version ermitteln
			$apiextrecmaxver = $data->{'data'}->{$apiextrec}->{'maxVersion'}; 
       
			$logstr = "Path of $apiextrec selected: $apiextrecpath";
			&printlog($hash, $logstr,"4");
			$logstr = "MaxVersion of $apiextrec selected: $apiextrecmaxver";
			&printlog($hash, $logstr,"4");
       
			# Pfad und Maxversion von "SYNO.SurveillanceStation.Camera" ermitteln
       		        $apicampath = $data->{'data'}->{$apicam}->{'path'};
			# Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
			$apicampath =~ tr/_//d;
       
			# maximale Version ermitteln
			$apicammaxver = $data->{'data'}->{$apicam}->{'maxVersion'};
			# um 1 verringern - Fehlerprävention
			if (defined $apicammaxver) {$apicammaxver -= 1};
       
			$logstr = "Path of $apicam selected: $apicampath";
			&printlog($hash, $logstr,"4");
			$logstr = "MaxVersion of $apicam (optimized): $apicammaxver";
			&printlog($hash, $logstr,"4");
       
			# ermittelte Werte in $hash einfügen
			$hash->{HELPER}{APIAUTHPATH}     = $apiauthpath;
			$hash->{HELPER}{APIAUTHMAXVER}   = $apiauthmaxver;
			$hash->{HELPER}{APIEXTRECPATH}   = $apiextrecpath;
			$hash->{HELPER}{APIEXTRECMAXVER} = $apiextrecmaxver;
			$hash->{HELPER}{APICAMPATH}      = $apicampath;
			$hash->{HELPER}{APICAMMAXVER}    = $apicammaxver;
       
       
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
               timeout  => 5,
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
               timeout  => 5,
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
   my $hash            = $param->{hash};
   my $servername      = $hash->{SERVERNAME};
   my $serverport      = $hash->{SERVERPORT};
   my $camname         = $hash->{CAMNAME};
   my $apiextrec       = $hash->{HELPER}{APIEXTREC};
   my $apiextrecpath   = $hash->{HELPER}{APIEXTRECPATH};
   my $apiextrecmaxver = $hash->{HELPER}{APIEXTRECMAXVER};
   my $sid             = $hash->{HELPER}{SID};
   my $OpMode          = $hash->{OPMODE};
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
                 return;
              }
       }
       else 
       {
            # die Abfrage konnte nicht ausgeführt werden
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
  
   $param = {
                url      => $url,
                timeout  => 5,
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
   my $device           = $hash->{NAME};
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
  
   # Verarbeitung der asynchronen Rückkehrdaten aus sub "camop_nonbl"
   if ($err ne "")                                                                                     # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
   {
        $logstr = "error while requesting ".$param->{url}." - $err";
        &printlog($hash,$logstr,"1");		                                                      # Eintrag fürs Log
        $logstr = "--- End Function cam: $OpMode nonblocking with error ---";
        &printlog($hash,$logstr,"4");
        readingsSingleUpdate($hash, "Error", $err, 1);                                     	       # Readings erzeugen
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
       
                # Generiert das Ereignis "on", bedingt Browseraktualisierung und Status der "Lampen" wenn kein longpoll=1
                # { fhem "trigger $device on" }
                
                # Logausgabe
                $logstr = "Time for Recording is set to: $rectime";
                &printlog($hash,$logstr,"4");
                
                # Stop der Aufnahme wird eingeleitet
                $logstr = "Recording of Camera $camname should be stopped in $rectime seconds";
                &printlog($hash,$logstr,"4");
                $hash->{OPMODE} = "Stop";
                InternalTimer(gettimeofday()+$rectime, "getapisites_nonbl", $hash, 0);
                                  

            }
            elsif ($OpMode eq "Stop") 
            {
                $hash->{STATE} = "off";
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Record","Stop");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
            
                # Generiert das Ereignis "off", bedingt Browseraktualisierung und Status der "Lampen" wenn kein longpoll=1
                # { fhem "trigger $device off" }
                
                RemoveInternalTimer($hash);
       
                # Logausgabe
                $logstr = "Camera $camname Recording stopped";
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
            $logstr = "ERROR - Operationmode $OpMode of Camera $camname was not successful. Errorcode: $errorcode - $error";
            &printlog($hash,$logstr,"1");
            $logstr = "--- End Function cam: $OpMode nonblocking with error ---";
            &printlog($hash,$logstr,"4");
            return;

       }
    # logout wird ausgeführt, Rückkehr wird mit "logout_nonbl" verarbeitet
    # Logausgabe
    $logstr = "--- Begin Function logout nonblocking ---";
    &printlog($hash,$logstr,"4");
  
    $url = "http://$servername:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Logout&session=SurveillanceStation&_sid=$sid"; 

    $param = {
                url      => $url,
                timeout  => 5,
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
  
   # Verarbeitung der asynchronen Rückkehrdaten aus sub "camop_nonbl"
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
  418 => "Object is not exist / The VisualStation ID does not exist",
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
    Using this Modul you are able to start and stop recordings of cameras which are defined in Synology Surveillance Station. <br>
    The recordings are stored in Synology Surveillance Station and are managed like the other (normal) recordings defined by Surveillance Station rules.<br>
    For example the recordings are stored for a defined time in Surveillance Station and will be deleted after that period.<br><br>
  
<b> Prerequisites </b> <br><br>
    This module uses the CPAN-module JSON. Consider to install these package (Debian: libjson-perl).<br>
    You don't need to install LWP anymore, because of SSCam is now completely using the nonblocking functions of HttpUtils respectively HttpUtils_NonblockingGet. <br> 
    You also need to add an user in Synology DSM as member of Administrators group for using in this module. <br><br>
    

  <a name="SCamdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SSCam &lt;Servername&gt; &lt;Port&gt; &lt;Username&gt; &lt;Password&gt; &lt;Cameraname&gt; &lt;RecordTime&gt;</code><br>
    <br>
    Defines a new camera device for SSCam. At first the devices have to be set up and operable in Synology Surveillance Station 7.0 and above. <br><br>
    
    The parameter "RecordTime" describes the minimum Recordtime. Dependend on other factors like the performance of you Synology Diskstation and <br>
    Surveillance Station the effective Recordtime could be longer.
    
    The Modul SSCam ist based on functions of Synology Surveillance Station API. <br>
    Please refer the <a href="http://global.download.synology.com/download/Document/DeveloperGuide/Surveillance_Station_Web_API_v2.0.pdf">Web API Guide</a>. <br><br>
    
    At present only HTTP-Protokoll is supported to call Synology DS. <br><br>  

    The parameters are in detail:
   <br>
   <br>    
    
    <table>
    <tr><td>name   :</td><td>the name of the new device to use in FHEM</td></tr>
    <tr><td>Servername   :</td><td>the name or IP-address of Synology Surveillance Station Host. If Servername is used, make sure the name can be discovered in network by DNS </td></tr>
    <tr><td>Port   :</td><td>the Port Synology surveillance Station Host, normally 5000 (HTTP only)</td></tr>
    <tr><td>Username   :</td><td>Username defined in the Diskstation. Has to be a member of Admin-group</td></tr>
    <tr><td>Password   :</td><td>the Password for the User</td></tr>
    <tr><td>Cameraname   :</td><td>Cameraname as defined in Synology Surveillance Station, Spaces are not allowed in Cameraname !</td></tr>
    <tr><td>Recordtime   :</td><td>it's the time for recordings </td></tr>
    </table>

    <br><br>

    Examples:
     <pre>
      define CamDoor SSCAM ds1.myds.ds 5000 apiuser apipass Door 10      
    </pre>
  </ul>
  <br>
  <a name="SSCamset"></a>
  <b>Set </b>
  <ul>
    
    There are two options for set.<br><br>
    
    "on"    :   starts a recording. The recording will be stopped after the period given by the value of &lt;RecordTime&gt; in device definition.
    <pre>            
                Command: set &lt;name&gt on
    </pre>            
    "off"   :   stops a running recording manually or other event (for example by using <a href="#at">at</a>, <a href="#notify">notify</a> or others).
    <pre>            
                Command: set &lt;name&gt off
    </pre>
  </ul>
  <br>

  <a name="SSCamattr"></a>
  <b>Attributes</b>
  <ul>
  
   Different Verbose-Level are supported.<br>
   Those are in detail:<br>
   
<pre>
    0   -   Start/Stop-Event will be logged
    1   -   Error messages will be logged
    3   -   sended commands will be logged
    4   -   sended and received informations will be logged
    5   -   all outputs will be logged for error-analyses. Please use it carefully, a lot of data could be written into the logfile !
</pre>

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
    Mit diesem Modul kann die Aufnahme von in der Synology Surveillance Station definierten Kameras gestartet bzw. gestoppt werden.  <br>
    Die Aufnahmen stehen in der Synology Surveillance Station zur Verfügung und unterliegen, wie jede andere Aufnahme, den in der Synology Surveillance Station eingestellten Regeln. <br>
    So werden zum Beispiel die Aufnahmen entsprechend ihrer Archivierungsfrist gehalten und dann gelöscht.<br><br>

<b>Vorbereitung </b> <br><br>
    Dieses Modul nutzt das CPAN Module JSON. Bitte darauf achten dieses Paket zu installieren. (Debian: libjson-perl). <br>
    Das CPAN-Modul LWP wird für SSCam nicht mehr benötigt. Das Modul verwendet für HTTP-Calls die nichtblockierenden Funktionen von HttpUtils bzw. HttpUtils_NonblockingGet. <br> 
    Im DSM muß ebenfalls ein Nutzer als Mitglied der Administratorgruppe angelegt sein. Die Daten werden beim define des Gerätes benötigt.<br><br>

  <a name="SCamdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SSCam &lt;Servername&gt; &lt;Port&gt; &lt;Username&gt; &lt;Password&gt; &lt;Cameraname&gt; &lt;RecordTime&gt;</code><br>
    <br>
    
    Definiert eine neue Kamera für SSCam. Zunächst muß diese Kamera in der Synology Surveillance Station 7.0 oder höher eingebunden sein und entsprechend funktionieren.<br><br>
    
    Der Parameter "RecordTime" beschreibt die Mindestaufnahmezeit. Abhängig von Faktoren wie Performance der Synology Diskstation und der Surveillance Station <br>
    kann die effektive Aufnahmezeit geringfügig länger sein.<br><br>
    
    Das Modul SSCam basiert auf Funktionen der Synology Surveillance Station API. <br>
    Weitere Inforamtionen unter: <a href="http://global.download.synology.com/download/Document/DeveloperGuide/Surveillance_Station_Web_API_v2.0.pdf">Web API Guide</a>. <br><br>
    
    Es müssen die Perl-Module LWP (Debian: libwww-perl) und JSON (Debian: libjson-perl) installiert sein.
    Momentan wird nur das HTTP-Protokoll unterstützt um die Web-Services der Synology DS aufzurufen. <br><br>  
    
    Die Parameter beschreiben im Einzelnen:
   <br>
   <br>    
    
    <table>
    <tr><td>name   :</td><td>der Name des neuen Gerätes in FHEM</td></tr>
    <tr><td>Servername   :</td><td>der Name oder die IP-Addresse des Synology Surveillance Station Host. Wenn der Servername benutzt wird ist sicherzustellen dass der Name im Netzwerk aufgelöst werden kann.</td></tr>
    <tr><td>Port   :</td><td>der Port des Synology Surveillance Station Host. Normalerweise ist das 5000 (nur HTTP)</td></tr>
    <tr><td>Username   :</td><td>Name des in der Diskstation definierten Nutzers. Er muß ein Mitglied der Admin-Gruppe sein</td></tr>
    <tr><td>Password   :</td><td>das Passwort des Nutzers</td></tr>
    <tr><td>Cameraname   :</td><td>Kameraname wie er in der Synology Surveillance Station angegeben ist. Leerzeichen im Namen sind nicht erlaubt !</td></tr>
    <tr><td>Recordtime   :</td><td>die definierte Aufnahmezeit</td></tr>
    </table>

    <br><br>

    Beispiel:
     <pre>
      define CamTür SSCAM ds1.myds.ds 5000 apiuser apipass Tür 10      
     </pre>
  </ul>
  
  <a name="SSCamset"></a>
  <b>Set </b>
  <ul>
    
    Es gibt zur Zeit zwei Optionen für "Set".<br><br>
    

    "on"    :   startet eine Aufnahme. Die Aufnahme wird automatisch nach Ablauf der Zeit &lt;RecordTime&gt; gestoppt.
    <pre>            
                Befehl: set &lt;name&gt on     
    </pre>            
    "off"   :   stoppt eine laufende Aufnahme manuell oder durch die Nutzung anderer Events (z.B. durch <a href="#at">at</a>, <a href="#notify">notify</a> oder andere)
    <pre>  
                Befehl: set &lt;name&gt off
    </pre> 

  </ul>
  <br>

  <a name="SSCamattr"></a>
  <b>Attributes</b>
  <ul>
  
   Es werden verschiedene Verbose-Level unterstützt.<br>
   Dies sind im Einzelnen:<br>
   
<pre>
    0   -   Start/Stop-Ereignisse werden geloggt
    1   -   Fehlermeldungen werden geloggt
    3   -   gesendete Kommandos werden geloggt
    4   -   gesendete und empfangene Daten werden geloggt
    5   -   alle Ausgaben zur Fehleranalyse werden geloggt. ACHTUNG: unter Umständen sehr viele Daten im Logfile !
</pre>

   <br><br>
        
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>

=end html_DE
=cut

