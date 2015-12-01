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

use LWP::Simple;                       # From CPAN , Debian libwww-perl
use JSON qw( decode_json );            # From CPAN,, Debian libjson-perl  
use strict;                            # Good practice
use warnings;                          # Good practice


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
  $hash->{PASSWORD} = $password;
  $hash->{CAMNAME} = $camname;
  $hash->{RECTIME} = $rectime;  
   
  return undef;
}


sub SSCam_Undef {
  my ($hash, $arg) = @_;
  return undef;
}

sub SSCam_Attr { 
}
 
sub SSCam_Set {
        my ( $hash, @a ) = @_;
        return "\"set X\" needs at least an argument" if ( @a < 2 );
	my $name = shift @a;
	my $opt = shift @a;
	my $value = join("", @a);
	my %SSCam_sets = (
	                 on => "on",
	                 off => "off");
	my $errorcode;
	my $s;
	my $logstr;
	my @cList;
	
	# ist die angegebene Option verfügbar ?
	if(!defined($SSCam_sets{$opt})) {
		@cList = keys %SSCam_sets; 
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
                } else {
                          
                # Aufnahme starten
                if ($opt eq "on") {
                      # wegen Syno-105-Fehler mehrfaches durchlaufen bis kein 105-Fehler mehr oder Aufgabe nach x Durchläufen ($s = Schleifendurchlauf)
                      $errorcode = "105";
                      $s = 30;
                      while ($errorcode eq "105" && $s > 0) {
                        &camstart($hash);
                        $errorcode = ReadingsVal("$name","Errorcode","none");
                        # Logausgabe
                        $logstr = "Readingsval $name".":Errorcode is: $errorcode";
                        $logstr = "Readingsval $name".":Errorcode is still $errorcode but end of loop reached, giving up!" if ($s == 1);
                        &printlog($hash,$logstr,"5");
                        $s -=1;
                      }
                }
                    
                    
                # Aufnahme stoppen
                if ($opt eq "off") {
                      # wegen Syno-105-Fehler mehrfaches durchlaufen bis kein 105-Fehler mehr oder Aufgabe nach x Durchläufen ($s = Schleifendurchlauf)
                      $errorcode = "105";
                      $s = 30;
                      while ($errorcode eq "105" && $s > 0) {
                        &camstop($hash);
                        $errorcode = ReadingsVal("$name","Errorcode","none");
                        # Logausgabe
                        $logstr = "Readingsval $name".":Errorcode is: $errorcode";
                        $logstr = "Readingsval $name".":Errorcode is still $errorcode but end of loop reached, giving up!" if ($s == 1);
                        &printlog($hash,$logstr,"5");
                        $s -=1;
                      }
                }
              }
}


###############################################################################
####     Starten einer Kameraaufnahme

sub camstart {
  # Übernahmewerte sind $username, $password,$camname, $servername, $serverport
  my ($hash) = @_;
  my $servername = $hash->{SERVERNAME};
  my $serverport = $hash->{SERVERPORT};
  my $username = $hash->{USERNAME};
  my $password = $hash->{PASSWORD};
  my $camname = $hash->{CAMNAME};
  my $device = $hash->{NAME};
  my $rectime = $hash->{RECTIME};
  my $logstr;
  my $validurl;
  my $success;
  my $sid;
  my $camid;
  my $apiextrecpath;
  my $apiextrecmaxver;
  my $errorcode;
  my $url;
  my $myjson;
  my $data;
  my $error;
  
  # Logausgabe
  $logstr = "--- Begin Function camstart ---";
  &printlog($hash,$logstr,"5");
  
  $logstr = "Recording of Camera $camname should be started now";
  &printlog($hash,$logstr,"5");
  
  # Erreichbarkeit Disk Station Url testen
  $validurl = &validurl($hash);
  unless ($validurl eq "true") {return};
  
  # API-Pfade und MaxVersions ermitteln
  ($hash, $success) = &getapisites($hash);
  unless ($success eq "true") {return};
  
  # Login und SID ermitteln
  ($sid, $success)  = &serverlogin($hash);
  unless ($success eq "true") {return};

  # Kamera-ID anhand des Kamaeranamens ermitteln
  ($camid, $success) = &getcamid($hash,$sid);
  unless ($success eq "true") {&serverlogout($hash,$sid); return};

  # Start der Aufnahme
  $apiextrecpath   = $hash->{APIEXTRECPATH};
  $apiextrecmaxver = $hash->{APIEXTRECMAXVER};
  $errorcode       = "";
  $url = "http://$servername:$serverport/webapi/$apiextrecpath?api=SYNO.SurveillanceStation.ExternalRecording&method=Record&version=$apiextrecmaxver&cameraId=$camid&action=start&session=SurveillanceStation&_sid=\"$sid\""; 
  $myjson = get $url;
  
  # Evaluiere ob Daten im JSON-Format empfangen
  ($hash, $success) = &evaljson($hash,$myjson,$url);
  unless ($success eq "true") {&serverlogout($hash,$sid); return};
  
  # Logausgabe
  $logstr = "URL call: $url";
  &printlog($hash,$logstr,"4");
  $logstr = "JSON response: $myjson";
  &printlog($hash,$logstr,"4");
  
  # dekodiere Response aus JSON Format
  $data = decode_json($myjson);
  $success = $data->{'success'};
  
 
  if ($success eq "true") {
       
       # die URL konnte erfolgreich aufgerufen werden
       # Setreading 
       readingsBeginUpdate($hash);
       readingsBulkUpdate($hash,"Record","Start");
       readingsBulkUpdate($hash,"Errorcode","none");
       readingsBulkUpdate($hash,"Error","none");
       readingsEndUpdate($hash, 1);
       $hash->{STATE} = "on";
       
       # Generiert das Ereignis "on", bedingt Browseraktualisierung und Status der "Lampen"
       { fhem "trigger $device on" }
       
       # Logausgabe
       $logstr = "Camera $camname with Recordtime $rectime"."s started";
       &printlog($hash,$logstr,"3");
       
       # FHEM Sleep Kommando, kein blockieren von FHEM 
       {fhem("sleep $rectime;set $device off")};
       $logstr = "Autostop command: {fhem(\"sleep $rectime quiet;set $device off\")}";
       &printlog($hash,$logstr,"5");
      
       }
       else {
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
       $logstr = "ERROR - Start Recording of Camera $camname not possible. Errorcode: $errorcode - $error";
       &printlog($hash,$logstr,"1");
       }
  &serverlogout($hash,$sid);

  # Logausgabe
  $logstr = "--- End Function camstart ---";
  &printlog($hash,$logstr,"5");
  
return;
}

##############################################################################
###      Stoppen Kameraaufnahme

sub camstop {
  # Übernahmewerte sind $username, $password,$camname, $servername, $serverport
  my ($hash) = @_;
  my $servername      = $hash->{SERVERNAME};
  my $serverport      = $hash->{SERVERPORT};
  my $username        = $hash->{USERNAME};
  my $password        = $hash->{PASSWORD};
  my $camname         = $hash->{CAMNAME};
  my $device          = $hash->{NAME};
  my $logstr;
  my $validurl;
  my $success;
  my $sid;
  my $camid;
  my $apiextrecpath;
  my $apiextrecmaxver;
  my $errorcode;
  my $url;
  my $myjson;
  
  # Logausgabe
  $logstr = "--- Begin Function camstop ---";
  &printlog($hash,$logstr,"5");  
  
  $logstr = "Recording of Camera $camname should be stopped now";
  &printlog($hash,$logstr,"5");

  # Erreichbarkeit Disk Station Url testen
  $validurl = &validurl($hash);
  unless ($validurl eq "true") {return};
  
  # API-Pfade und MaxVersions ermitteln
  ($hash, $success) = &getapisites($hash);
  unless ($success eq "true") {return};
  
  # SID ermitteln nach Login
  ($sid, $success)  = &serverlogin($hash);
  unless ($success eq "true") {return};

  ($camid, $success) = &getcamid($hash,$sid);
  unless ($success eq "true") {&serverlogout($hash,$sid); return};

  $apiextrecpath   = $hash->{APIEXTRECPATH};
  $apiextrecmaxver = $hash->{APIEXTRECMAXVER};
 
  $errorcode = "";
  $url = "http://$servername:$serverport/webapi/$apiextrecpath?api=SYNO.SurveillanceStation.ExternalRecording&method=Record&version=$apiextrecmaxver&cameraId=$camid&action=stop&session=SurveillanceStation&_sid=\"$sid\"";
  $myjson = get $url;
  
  # Evaluiere ob Daten im JSON-Format empfangen
  ($hash, $success) = &evaljson($hash,$myjson,$url);
  unless ($success eq "true") {&serverlogout($hash,$sid); return};
  
  # Logausgabe
  $logstr = "URL call: $url";
  &printlog($hash,$logstr,"4");
  $logstr = "JSON response: $myjson";
  &printlog($hash,$logstr,"4");  
  
  # dekodiere Response aus JSON Format
  my $data = decode_json($myjson);
  $success = $data->{'success'};

  if ($success eq "true") {
       # die URL konnte erfolgreich aufgerufen werden
       
       # Setreading 
       readingsBeginUpdate($hash);
       readingsBulkUpdate($hash,"Record","Stop");
       readingsBulkUpdate($hash,"Errorcode","none");
       readingsBulkUpdate($hash,"Error","none");
       readingsEndUpdate($hash, 1);
       $hash->{STATE} = "off";
       
       # Generiert das Ereignis "on", bedingt Browseraktualisierung und Status der "Lampen"
       { fhem "trigger $device off" }
       
       # Logausgabe
       $logstr = "Camera $camname Recording stopped";
       &printlog($hash,$logstr,"3");
       }
       else {
       # die URL konnte nicht erfolgreich aufgerufen werden
       # Errorcode aus JSON ermitteln
       $errorcode = $data->{'error'}->{'code'};

       # Fehlertext zum Errorcode ermitteln
       my $error = &experror($hash,$errorcode);
       
       # Setreading 
       readingsBeginUpdate($hash);
       readingsBulkUpdate($hash,"Errorcode",$errorcode);
       readingsBulkUpdate($hash,"Error",$error);
       readingsEndUpdate($hash, 1);     

       # Logausgabe
       my $logstr = "ERROR - Stop Recording Camera $camname not possible. Errorcode: $errorcode - $error";
       &printlog($hash,$logstr,"1");
       }

   &serverlogout($hash,$sid);

   # Logausgabe
   $logstr = "--- End Function camstop ---";
   &printlog($hash,$logstr,"5");
   
return;
}

############################################################################
####   Login auf SS Server und ermitteln _sid

sub serverlogin {
  my ($hash) = @_;
  my $servername    = $hash->{SERVERNAME};
  my $serverport    = $hash->{SERVERPORT};
  my $username      = $hash->{USERNAME};
  my $password      = $hash->{PASSWORD};
  my $apiauthpath   = $hash->{APIAUTHPATH};
  my $apiauthmaxver = $hash->{APIAUTHMAXVER};
  my $sid = "";
  my $logstr;
  my $loginurl;
  my $myjson;
  my $success;
  my $data;
  my $errorcode;
  my $error;
  
  
  # Logausgabe
  $logstr = "--- Begin Function serverlogin ---";
  &printlog($hash,$logstr,"5");  
 
  $loginurl = "http://$servername:$serverport/webapi/$apiauthpath?api=SYNO.API.Auth&version=$apiauthmaxver&method=Login&account=$username&passwd=$password&session=SurveillanceStation&format=sid";
  $myjson = get $loginurl;
  
  # Evaluiere ob Daten im JSON-Format empfangen
  ($hash, $success) = &evaljson($hash,$myjson,$loginurl);
  unless ($success eq "true") {return($sid, $success)};
  
  # Logausgabe
  $logstr = "URL call: $loginurl";
  &printlog($hash,$logstr,"4");
  $logstr = "JSON response: $myjson";
  &printlog($hash,$logstr,"4");  
  
  # die Response wird im JSON Format geliefert, Beispiel: {"data":{"sid":"zvJraLU.5Yg6E14A0MIN235902"},"success":true} 
  $data = decode_json($myjson);
  $success = $data->{'success'};
  
  # der login war erfolgreich
  if ($success eq "true") {
       $sid = $data->{'data'}->{'sid'};
       
       # Setreading 
       readingsBeginUpdate($hash);
       readingsBulkUpdate($hash,"Errorcode","none");
       readingsBulkUpdate($hash,"Error","none");
       readingsEndUpdate($hash, 1);
       
       # Logausgabe
       $logstr = "Login of User $username successful - SID: $sid";
       &printlog($hash,$logstr,"5");
       } else {
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
       }
   
   # Logausgabe
   $logstr = "--- End Function serverlogin ---";
   &printlog($hash,$logstr,"5");    
   
return ($sid, $success);
}


############################################################################
### Logout Session 

sub serverlogout {
 # Übernahmewerte sind Session-id: $sid, $servername, $serverport
 my ($hash,@sid) = @_;
 my $servername    = $hash->{SERVERNAME};
 my $serverport    = $hash->{SERVERPORT};
 my $apiauthpath   = $hash->{APIAUTHPATH};
 my $apiauthmaxver = $hash->{APIAUTHMAXVER};
 my $username      = $hash->{USERNAME};
 my $sid = shift @sid;
 my $logstr;
 my $logouturl;
 my $myjson;
 my $success;
 my $data;
 my $errorcode;
 my $error; 
 
 
 # Logausgabe
 $logstr = "--- Begin Function serverlogout ---";
 &printlog($hash,$logstr,"5"); 
 
 $logouturl = "http://$servername:$serverport/webapi/$apiauthpath?api=SYNO.API.Auth&version=$apiauthmaxver&method=Logout&session=SurveillanceStation&_sid=$sid";
 $myjson = get $logouturl;
 
 # Evaluiere ob Daten im JSON-Format empfangen
 ($hash, $success) = &evaljson($hash,$myjson,$logouturl);
 unless ($success eq "true") {return};
 
 # Logausgabe
 $logstr = "URL call: $logouturl";
 &printlog($hash,$logstr,"4");
 $logstr = "JSON response: $myjson";
 &printlog($hash,$logstr,"4");

 # Response erfolgt im JSON Format der Art: {"success":true} 
 $data = decode_json($myjson);
 $success = $data->{'success'};

 if ($success eq "true")  {
    # die URL konnte erfolgreich aufgerufen werden
    
    # Logausgabe
    $logstr = "Session of User $username quit - SID: $sid.";
    &printlog($hash,$logstr,"5");
    } else {
    # Errorcode aus JSON ermitteln
    $errorcode = $data->{'error'}->{'code'};

    # Fehlertext zum Errorcode ermitteln
    $error = &experrorauth($hash,$errorcode);
    
    # Logausgabe
    $logstr = "ERROR - Logout of User $username was not successful. Errorcode: $errorcode - $error";
    &printlog($hash,$logstr,"1");
    }
  # Logausgabe
  $logstr = "--- End Function serverlogout ---";
  &printlog($hash,$logstr,"5");
    
return;
}

###############################################################################
###   Test ob JSON-String empfangen wurde
  
sub evaljson { 
  my ($hash,$myjson,$url)= @_;
  my $success = "true";
  my $e;
  my $logstr;
  
  eval {decode_json($myjson);1;} or do 
  {
  $success = "false";
  $e = $@;
  
  # Setreading 
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"Errorcode","none");
  readingsBulkUpdate($hash,"Error","malformed JSON string received");
  readingsEndUpdate($hash, 1);
  
  # Logausgabe
  $logstr = "URL call: $url";
  &printlog($hash,$logstr,"4");
  $logstr = "Output eval: ERROR - $e";
  &printlog($hash,$logstr,"3");
  };
return($hash,$success);
}


###############################################################################
###      Id für einen Kameranamen ermitteln

sub getcamid {
  # Übernahmewerte sind Session-id $sid, Kameraname: $camname, $servername, $serverport
  my ($hash,@sid)     = @_;
  my $servername      = $hash->{SERVERNAME};
  my $serverport      = $hash->{SERVERPORT};
  my $camname         = $hash->{CAMNAME};
  my $apicampath      = $hash->{APICAMPATH};
  my $apicammaxver    = $hash->{APICAMMAXVER};
  my $sid = shift @sid;
  my $camid = "";
  my $logstr;
  my $url;
  my $myjson;
  my $success;
  my $data;
  my $camcount;
  my $i;
  my %allcams;
  my $name;
  my $id;
  my $errorcode;
  my $error;
    
  # Logausgabe
  $logstr = "--- Begin Function getcamid ---";
  &printlog($hash,$logstr,"5");
  
  # einlesen aller Kameras
  $url = "http://$servername:$serverport/webapi/$apicampath?api=SYNO.SurveillanceStation.Camera&version=$apicammaxver&method=List&session=SurveillanceStation&_sid=\"$sid\"";
  $myjson = get $url;

  # Evaluiere ob Daten im JSON-Format empfangen
  ($hash, $success) = &evaljson($hash,$myjson,$url);
  unless ($success eq "true") {return($camid,$success)};
  
  # Logausgabe
  $logstr = "URL call: $url";
  &printlog($hash,$logstr,"4");
  # $logstr = "JSON response: $myjson";
  # &printlog($hash,$logstr,"5");
  
  # Response erfolgt im JSON Format der Art: {"success":true} 
  $data = decode_json($myjson);
  $success = $data->{'success'};
  

       if ($success eq "true") {
       # die Liste aller Kameras konnte ausgelesen werden
       # Anzahl der definierten Kameras ist in Var "total"
       $camcount = $data->{'data'}->{'total'};

       $i = 0;
         # Namen aller installierten Kameras mit Id's in Hash (Assoziatives Array) einlesen
         %allcams = ();
         while ($i < $camcount) {
             $name = $data->{'data'}->{'cameras'}->[$i]->{'name'};
             $id = $data->{'data'}->{'cameras'}->[$i]->{'id'};
             $allcams{"$name"} = "$id";
             $i += 1;
             }
             # Ist der gesuchte Kameraname im Hash enhalten (in SS eingerichtet ?)
             if (exists($allcams{$camname})) {
                 $camid = $allcams{$camname};
                 } else {
                 # Kameraname nicht gefunden, id = ""
                 
                 # Setreading 
                 readingsBeginUpdate($hash);
                 readingsBulkUpdate($hash,"Errorcode","none");
                 readingsBulkUpdate($hash,"Error","Kamera(ID) nicht gefunden");
                 readingsEndUpdate($hash, 1);
                                  
                 # Logausgabe
                 $logstr = "ERROR - Cameraname $camname wasn't found in Surveillance Station. Check Cameraname and Spelling.";
                 &printlog($hash,$logstr,"1");
                 $success = "false";
                 }
       }
       else {
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
       }
   # Logausgabe
   $logstr = "--- End Function getcamid ---";
   &printlog($hash,$logstr,"5");
   
return ($camid,$success);  
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
  unless (exists ($errorlist {$errorcode})) {$error = "Meldung nicht gefunden. (bitte API-Guide konsultieren)"; return ($error);}

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
  unless (exists ($errorlist {$errorcode})) {$error = "Meldung nicht gefunden. (bitte API-Guide konsultieren)"; return ($error);}

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

############################################################################
###  ist die angegebene URL erreichbar ?

sub validurl {
  # Übernahmewerte ist $hash
  my ($hash)= @_;
  my $servername = $hash->{SERVERNAME};
  my $serverport = $hash->{SERVERPORT};
  my $validurl = " ";
  my $url;
  my $logstr;
  
  # Seite zum testen
  $url = "http://$servername:$serverport";

  # Logausgabe
  $logstr = "--- Begin Function validurl ---";
  &printlog($hash,$logstr,"5");  
  
  if (head($url)) {
        
    # Setreading 
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"Errorcode","none");
    readingsBulkUpdate($hash,"Error","none");
    readingsEndUpdate($hash, 1);
    
    # Logausgabe
    $logstr = "Site http://$servername:$serverport reachable";
    &printlog($hash,$logstr,"5");
    $validurl = "true";
    
    } else {
    
    # Setreading 
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"Errorcode","none");
    readingsBulkUpdate($hash,"Error","Site http://$servername:$serverport not reachable");
    readingsEndUpdate($hash, 1);
    
    #Logausgabe 
    $logstr = "ERROR - Site http://$servername:$serverport not reachable. Check Servername / IP-Adresse and Port";
    &printlog($hash,$logstr,"1");
    $validurl = "false";
    }
  
  # Logausgabe
  $logstr = "--- End Function validurl ---";
  &printlog($hash,$logstr,"5");  
    
return($validurl);
}

############################################################################
####    Ermittlung der Web API -Pfade und MaxVersionen

sub getapisites {
   # Übernahmewerte sind $servername, $serverport
   my ($hash) = @_;
   my $servername = $hash->{SERVERNAME};
   my $serverport = $hash->{SERVERPORT};
   my $success = " ";
   my $apiauth;
   my $apiextrec;
   my $apicam;
   my $logstr;
   my $url;
   my $myjson;
   my $data;
   my $apiauthpath;
   my $apiauthmaxver;
   my $apiextrecpath;
   my $apiextrecmaxver;
   my $apicampath;
   my $apicammaxver;
   my $error;
   
     
   # benötigte API-Pfade, in der Abfrage-Url an Parameter "&query=" mit Komma getrennt angeben
   $apiauth   = "SYNO.API.Auth";
   $apiextrec = "SYNO.SurveillanceStation.ExternalRecording";
   $apicam    = "SYNO.SurveillanceStation.Camera";
   
   # Logausgabe
   $logstr = "--- Begin Function getapisites ---";
   &printlog($hash,$logstr,"5");   
   
   # Abfrage der Eigenschaften von API SYNO.SurveillanceStation.ExternalRecording,$apicam
   $url = "http://$servername:$serverport/webapi/query.cgi?api=SYNO.API.Info&method=Query&version=1&query=$apiauth,$apiextrec,$apicam";
   $myjson = get $url;
   
   # Evaluiere ob Daten im JSON-Format empfangen
   ($hash, $success) = &evaljson($hash,$myjson,$url);
   unless ($success eq "true") {return($hash,$success)};
   
   # Logausgabe
   $logstr = "URL call: $url";
   &printlog($hash,$logstr,"4");
   $logstr = "JSON response: $myjson";
   &printlog($hash,$logstr,"4");   
  
   # Response erfolgt im JSON Format 
   $data = decode_json($myjson);
   $success = $data->{'success'};
   
   
   if ($success eq "true") {
       
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
       $logstr = "MaxVersion of $apicam: $apicammaxver";
       &printlog($hash, $logstr,"4");
       
       # ermittelte Werte in $hash einfügen
       $hash->{APIAUTHPATH} = $apiauthpath;
       $hash->{APIAUTHMAXVER} = $apiauthmaxver;
       $hash->{APIEXTRECPATH} = $apiextrecpath;
       $hash->{APIEXTRECMAXVER} = $apiextrecmaxver;
       $hash->{APICAMPATH} = $apicampath;
       $hash->{APICAMMAXVER} = $apicammaxver;
       
       
       # Setreading 
       readingsBeginUpdate($hash);
       readingsBulkUpdate($hash,"Errorcode","none");
       readingsBulkUpdate($hash,"Error","none");
       readingsEndUpdate($hash, 1);
       
       } else {
       
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
       }
   # Logausgabe
   $logstr = "--- End Function getapisites ---";
   &printlog($hash,$logstr,"5");

return($hash,$success);          
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
    This module uses other CPAN-modules LWP and JSON. Consider to install these packages (Debian: libwww-perl, libjson-perl).<br>
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
    </table>
  </ul>
  <br>
  <a name="SSCamset"></a>
  <b>Set </b>
  <ul>
    
    There are two options for set.<br><br>
    
<pre>
    "on"    :   triggers start of record.
    "off"   :   triggers stop of record.
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
    5   -   further outputs will be logged due to error-analyses
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
    Dieses Modul nutzt weitere CPAN Module LWP und JSON. Bitte darauf achten diese Pakete zu installieren. (Debian: libwww-perl, libjson-perl). <br>
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

    Examples:
     <pre>
      define CamTür SSCAM ds1.myds.ds 5000 apiuser apipass Tür 10      
    </table>
  </ul>
  
  <a name="SSCamset"></a>
  <b>Set </b>
  <ul>
    
    Es gibt zur Zeit zwei Optionen für "Set".<br><br>
    
<pre>
    "on"    :   startet die Aufnahme.
    "off"   :   stoppt die Aufnahme.
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
    5   -   weitere Ausgaben zur Fehleranalyse werden geloggt
</pre>

   <br><br>
        
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>

=end html_DE
=cut

