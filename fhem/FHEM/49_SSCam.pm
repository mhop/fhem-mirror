##########################################################################################################
# $Id$
##########################################################################################################
#       49_SSCam.pm
#
#       written by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This Module can be used to operate Cameras defined in Synology Surveillance Station 7.0 or higher.
#       It's based on Synology Surveillance Station API Guide 2.0
# 
#       This file is part of fhem.
#
#       Fhem is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 2 of the License, or
#       (at your option) any later version.
#
#       Fhem is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with fhem.  If not, see <http://www.gnu.org/licenses/>.# 
#
##########################################################################################################
#  Versions History:
#
# 1.8    25.01.2016    changed define in order to remove credentials from string,
#                      added "set credentials" command to save username/password,
#                      added Attribute "session" to make login-session selectable,
#                      Note: You have to adapt your define-strings !!
#                      Refere to commandref or look in forum at: 
#                      http://forum.fhem.de/index.php/topic,45671.msg397449.html#msg397449
# 1.7    18.01.2016    Attribute "httptimeout" added
# 1.6    16.01.2016    Change the define-string related to rectime.
#                      Note: See all changes to rectime usage in commandref or here:
#                      http://forum.fhem.de/index.php/topic,45671.msg391664.html#msg391664
# 1.5.1  11.01.2016    Vars "USERNAME" and "RECTIME" removed from internals,
#                      Var (Internals) "SERVERNAME" changed to "SERVERADDR",
#                      minor change of Log messages,
#                      Note: use rereadcfg in order to activate the changes
#  1.5    04.01.2016   Function "Get" for creating Camera-Readings integrated,
#                      Attributs pollcaminfoall, pollnologging  added,
#                      Function for Polling Cam-Infos added.
#  1.4    23.12.2015   function "enable" and "disable" for SS-Cams added,
#                      changed timout of Http-calls to a higher value
#  1.3    19.12.2015   function "snap" for taking snapshots added,
#                      fixed a bug that functions may impact each other 
#  1.2    14.12.2015   improve usage of verbose-modes
#  1.1    13.12.2015   use of InternalTimer instead of fhem(sleep)
#  1.0    12.12.2015   changed completly to HttpUtils_NonblockingGet for calling websites nonblocking, 
#                      LWP is not needed anymore
#
#
# Definition: define <name> SSCam <camname> <ServerAddr> <ServerPort> 
# 
# Example: define CamCP1 SSCAM Carport 192.168.2.20 5000
#


package main;

use JSON qw( decode_json );            # From CPAN,, Debian libjson-perl 
use Data::Dumper;                      # Perl Core module
use strict;                           
use warnings;
use MIME::Base64;
use HttpUtils;


sub SSCam_Initialize($) {
 # die Namen der Funktionen, die das Modul implementiert und die fhem.pl aufrufen soll
 my ($hash) = @_;
 $hash->{DefFn}     = "SSCam_Define";
 $hash->{UndefFn}   = "SSCam_Undef";
 $hash->{SetFn}     = "SSCam_Set";
 $hash->{GetFn}     = "SSCam_Get";
 $hash->{AttrFn}    = "SSCam_Attr";
 
 
 $hash->{AttrList} =
         "httptimeout ".
         "pollcaminfoall ".
         "pollnologging:1,0 ".
         "rectime ".
         "session:SurveillanceStation,DSM ".
         "webCmd ".
         $readingFnAttributes;

         return undef;
}

sub SSCam_Define {
  # Die Define-Funktion eines Moduls wird von Fhem aufgerufen wenn der Define-Befehl für ein Gerät ausgeführt wird 
  # Welche und wie viele Parameter akzeptiert werden ist Sache dieser Funktion. Die Werte werden nach dem übergebenen Hash in ein Array aufgeteilt
  # define CamCP1 SSCAM Carport 192.168.2.20 5000 
  #       ($hash)  [1]    [2]        [3]      [4]  
  #
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  
  my @a = split("[ \t][ \t]*", $def);
  
  if(int(@a) < 5) {
        return "You need to specify more parameters.\n". "Format: define <name> SSCAM <Cameraname> <ServerAddress> <Port>";
        }
        
  my $camname    = $a[2];
  my $serveraddr = $a[3];
  my $serverport = $a[4];
  
  $hash->{SERVERADDR}       = $serveraddr;
  $hash->{SERVERPORT}       = $serverport;
  $hash->{CAMNAME}          = $camname;
 
  # benötigte API's in $hash einfügen
  $hash->{HELPER}{APIINFO}        = "SYNO.API.Info";                             # Info-Seite für alle API's, einzige statische Seite !                                                    
  $hash->{HELPER}{APIAUTH}        = "SYNO.API.Auth";                                                  
  $hash->{HELPER}{APIEXTREC}      = "SYNO.SurveillanceStation.ExternalRecording";                     
  $hash->{HELPER}{APICAM}         = "SYNO.SurveillanceStation.Camera";
  $hash->{HELPER}{APISNAPSHOT}    = "SYNO.SurveillanceStation.SnapShot";
  $hash->{HELPER}{APIPTZ}         = "SYNO.SurveillanceStation.PTZ";
  
  # Startwerte setzen
  $attr{$name}{webCmd}                 = "on:off:snap:enable:disable";                            # initiale Webkommandos setzen
  $hash->{HELPER}{ACTIVE}              = "off";                                                   # Funktionstoken "off", Funktionen können sofort starten
  $hash->{HELPER}{OLDVALPOLLNOLOGGING} = "0";                                                     # Loggingfunktion für Polling ist an
  $hash->{STATE}                       = "initialized";                                           # Anfangsstatus der Geräte
  $hash->{HELPER}{RECTIME_DEF}         = "15";                                                    # Standard für rectime setzen, überschreibbar durch Attribut "rectime" bzw. beim "set .. on-for-time"
  readingsSingleUpdate($hash,"Record","Stop",0);                                                  # Recordings laufen nicht
  readingsSingleUpdate($hash,"Availability", "", 0);                                              # Verfügbarkeit ist unbekannt
  readingsSingleUpdate($hash,"PollState","Inactive",0);                                           # es ist keine Gerätepolling aktiv
  getcredentials($hash,1);                                                                        # Credentials lesen und in RAM laden ($boot=1)  
  RemoveInternalTimer($hash);                                                                     # alle Timer löschen
  
  
  # Subroutine Watchdog-Timer starten (sollen Cam-Infos abgerufen werden ?), verzögerter zufälliger Start 0-60s 
  InternalTimer(gettimeofday()+int(rand(60)), "watchdogpollcaminfo", $hash, 0);

  
return undef;
}


sub SSCam_Undef {
    my ($hash, $arg) = @_;
    RemoveInternalTimer($hash);
return undef;
}

sub SSCam_Attr {
    my ($cmd,$name,$aName,$aVal) = @_;
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
   if ($cmd eq "set") {
        if ($aName eq "pollcaminfoall") {
           unless ($aVal =~ /^\d+$/) { return " The Value for $aName is not valid. Use only figures 0-9 without decimal places !";}
           }
        if ($aName eq "rectime") {
           unless ($aVal =~ /^\d+$/) { return " The Value for $aName is not valid. Use only figures 0-9 without decimal places !";}
           }
        if ($aName eq "httptimeout") {
           unless ($aVal =~ /^[0-9]+$/) { return " The Value for $aName is not valid. Use only figures 1-9 !";}
           }            
   }
return undef;
}
 
sub SSCam_Set {
        my ($hash, @a) = @_;
        return "\"set X\" needs at least an argument" if ( @a < 2 );
        my $name  = $a[0];
        my $opt   = $a[1];
        my $prop  = $a[2];
        my $prop1 = $a[3];
        
        my %SSCam_sets = (
                         "credentials"       => "credentials",
                         "on"                => "on",
                         "off"               => "off",
                         "snap"              => "snap:",
                         "enable"            => "enable",
                         "disable"           => "disable",
                         # presets         => "presets",
                         );

#        my $list .= "on off snap enable disable on-for-timer";
#        return SetExtensions($hash, $list, $name, $opt) if( $opt eq "?" );
#        return SetExtensions($hash, $list, $name, $opt) if( !grep( $_ =~ /^\Q$opt\E($|:)/, split( ' ', $list ) ) );
        
        
        my $camname = $hash->{CAMNAME}; 
        my $success;
        my $logstr;
        my @cList;
       
               
        # ist die angegebene Option verfügbar ?
        if(!defined($SSCam_sets{$opt})) 
                {
                    @cList = keys(%SSCam_sets); 
                    return "Unknown argument $opt, choose one of " . join(" ", @cList);
                  
                } 
                else 
                {
                    if ($opt ne "credentials" and !$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
                    
                    if ($opt eq "on") 
                    {
                        
                        if (defined($prop)) {
                            unless ($prop =~ /^\d+$/) { return " The Value for \"$opt\" is not valid. Use only figures 0-9 without decimal places !";}
                            $hash->{HELPER}{RECTIME_TEMP} = $prop;
                            }
                        
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
                    elsif ($opt eq "credentials") 
                    {
                        return "Credentials are incomplete, use username password" if (!$prop || !$prop1);
                        
                        ($success) = setcredentials($hash,$prop,$prop1);
                        return $success ? "Username and Password saved successfully" : "Error while saving Username / Password - see logfile for details";
                    }


                }  
return undef;
}


sub SSCam_Get {
    my ($hash, @a) = @_;
    return "\"get X\" needs at least an argument" if ( @a < 2 );
    my $name = shift @a;
    my $opt = shift @a;
    my %SSCam_gets = (
                     caminfoall    => "caminfoall",
                     );
    my @cList;

    # ist die angegebene Option verfügbar ?
    if(!defined($SSCam_gets{$opt})) 
        {
            @cList = keys %SSCam_gets; 
            return "Unknown argument $opt, choose one of " . join(" ", @cList);
        } 
        else 
        {
            # hier die Verarbeitung starten
            if ($opt eq "caminfoall") 
                {
                    &getcaminfoall($hash);
                }

        }
return undef;
}

######################################################################################
###  Username / Paßwort speichern

sub setcredentials ($@) {
    my ($hash, @credentials) = @_;
    my $logstr;
    my $success;
    my $credstr;
    my $index;
    my $retcode;
    my (@key,$len,$i);
    
    $credstr = encode_base64(join(':', @credentials));
    
    # Beginn Scramble-Routine
    @key = qw(1 3 4 5 6 3 2 1 9);
    $len = scalar @key;  
    $i = 0;  
    $credstr = join "",  
            map { $i = ($i + 1) % $len;  
            chr((ord($_) + $key[$i]) % 256) } split //, $credstr; 
    # End Scramble-Routine    
       
    $index = $hash->{TYPE}."_".$hash->{NAME}."_credentials";
    $retcode = setKeyValue($index, $credstr);
    
    if ($retcode) { 
        $logstr = "Error while saving the Credentials - $retcode";
        &printlog($hash,$logstr,"1");
        $success = 0;
        }
        else
        {
        getcredentials($hash,1);        # Credentials nach Speicherung lesen und in RAM laden ($boot=1) 
        $success = 1;
        }

return ($success);
}

######################################################################################
###  Username / Paßwort abrufen

sub getcredentials ($$) {
    my ($hash,$boot) = @_;
    my $logstr;
    my $success;
    my $username;
    my $passwd;
    my $index;
    my ($retcode, $credstr);
    my (@key,$len,$i);
    
    if ($boot eq 1) {
        # mit $boot=1 Credentials von Platte lesen und als scrambled-String in RAM legen
        $index = $hash->{TYPE}."_".$hash->{NAME}."_credentials";
        ($retcode, $credstr) = getKeyValue($index);
    
        if ($retcode) {
            $logstr = "Unable to read password from file: $retcode";
            &printlog($hash,$logstr,"1");
            $success = 0;
            }  

        if ($credstr) {
     
            # beim Boot scrambled Credentials in den RAM laden
            $hash->{HELPER}{CREDENTIALS} = $credstr;
        
            # "Credentials" wird als Statusbit ausgewertet. Wenn nicht gesetzt -> Warnmeldung und keine weitere Verarbeitung
            $hash->{CREDENTIALS} = "Set";
            $success = 1;
            }
    }
    else
    {
    # boot = 0 -> Credentials aus RAM lesen, decoden und zurückgeben
    $credstr = $hash->{HELPER}{CREDENTIALS};
    
    # Beginn Descramble-Routine
    @key = qw(1 3 4 5 6 3 2 1 9); 
    $len = scalar @key;  
    $i = 0;  
    $credstr = join "",  
    map { $i = ($i + 1) % $len;  
        chr((ord($_) - $key[$i] + 256) % 256) }  
        split //, $credstr;   
    # Ende Descramble-Routine
    
    ($username, $passwd) = split(":",decode_base64($credstr));
    
    $logstr = "Credentials read from RAM: $username $passwd";
    &printlog($hash,$logstr,"4");
    
    $success = (defined($passwd)) ? 1 : 0;
    }
    
return ($success, $username, $passwd);        
}



######################################################################################
###  Polling Überwachung

sub watchdogpollcaminfo ($) {
    # Überwacht die Wert von Attribut "pollcaminfoall" und Reading "PollState"
    # wenn Attribut "pollcaminfoall" > 10 und "PollState"=Inactive -> start Polling
    my ($hash)   = @_;
    my $name     = $hash->{NAME};
    my $camname  = $hash->{CAMNAME};
    my $logstr;
    my $watchdogtimer = 90;
    
    if (defined(AttrVal($name, "pollcaminfoall", undef)) and AttrVal($name, "pollcaminfoall", undef) > 10 and ReadingsVal("$name", "PollState", "Active") eq "Inactive") {
        
        # Polling ist jetzt aktiv
        readingsSingleUpdate($hash,"PollState","Active",0);
            
        $logstr = "Polling Camera $camname is currently activated - Pollinginterval: ".AttrVal($name, "pollcaminfoall", undef)."s";
        &printlog($hash,$logstr,"2");
        
        # in $hash eintragen für späteren Vergleich (Changes von pollcaminfoall)
        $hash->{HELPER}{OLDVALPOLL} = AttrVal($name, "pollcaminfoall", undef);
        
        # Pollingroutine aufrufen
        &getcaminfoall($hash);           
    }
    
    if (defined($hash->{HELPER}{OLDVALPOLL}) and defined(AttrVal($name, "pollcaminfoall", undef)) and AttrVal($name, "pollcaminfoall", undef) > 10) {
        if ($hash->{HELPER}{OLDVALPOLL} != AttrVal($name, "pollcaminfoall", undef)) {
            
            $logstr = "Polling Camera $camname was changed to new Pollinginterval: ".AttrVal($name, "pollcaminfoall", undef)."s";
            &printlog($hash,$logstr,"2");
            
            $hash->{HELPER}{OLDVALPOLL} = AttrVal($name, "pollcaminfoall", undef);
            &getcaminfoall($hash);
            }
    }
    
    if (defined(AttrVal($name, "pollnologging", undef))) {
        if ($hash->{HELPER}{OLDVALPOLLNOLOGGING} ne AttrVal($name, "pollnologging", undef)) {
            if (AttrVal($name, "pollnologging", undef) == "1") {
                $logstr = "Log of Polling Camera $camname is currently deactivated";
                &printlog($hash,$logstr,"2");
                # in $hash eintragen für späteren Vergleich (Changes von pollnologging)
                $hash->{HELPER}{OLDVALPOLLNOLOGGING} = AttrVal($name, "pollnologging", undef);
            } else {
                $logstr = "Log of Polling Camera $camname is currently activated";
                &printlog($hash,$logstr,"2");
                # in $hash eintragen für späteren Vergleich (Changes von pollnologging)
                $hash->{HELPER}{OLDVALPOLLNOLOGGING} = AttrVal($name, "pollnologging", undef);
            }
        }
    } else {
        # alter Wert von "pollnologging" war 1 -> Logging war deaktiviert
        if ($hash->{HELPER}{OLDVALPOLLNOLOGGING} == "1") {
            $logstr = "Log of Polling Camera $camname is currently activated";
            &printlog($hash,$logstr,"2");
            # in $hash eintragen für späteren Vergleich (Changes von pollnologging)
            $hash->{HELPER}{OLDVALPOLLNOLOGGING} = "0";            
        }
    }
InternalTimer(gettimeofday()+$watchdogtimer, "watchdogpollcaminfo", $hash, 0);
return undef;
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
        $logstr = "Recording of Camera $camname will be started now";
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
        $logstr = "Recording of Camera $camname will be stopped now";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "Stop";
        $hash->{HELPER}{ACTIVE} = "on";
        
        &getapisites_nonbl($hash);
    }
    else
    {
    InternalTimer(gettimeofday()+0.2, "camstoprec", $hash, 0);
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
    InternalTimer(gettimeofday()+0.3, "camsnap", $hash, 0);
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
    InternalTimer(gettimeofday()+0.4, "camenable", $hash, 0);
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
    InternalTimer(gettimeofday()+0.4, "camdisable", $hash, 0);
    }    
}

###############################################################################
###   Kamera alle Informationen abrufen (Get) bzw. Einstieg Polling

sub getcaminfoall ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    
    if ($hash->{HELPER}{ACTIVE} ne "on") {
                        
        &getcaminfo($hash);
        &getcapabilities($hash);
        &getptzlistpreset($hash);
        &getptzlistpatrol($hash);

    }
    else
    {
        InternalTimer(gettimeofday()+0.5, "getcaminfoall", $hash, 0);
    }
    
    if (defined(AttrVal($name, "pollcaminfoall", undef)) and AttrVal($name, "pollcaminfoall", undef) > 10) {
        # Pollen wenn pollcaminfo > 10, sonst kein Polling
        InternalTimer(gettimeofday()+AttrVal($name, "pollcaminfoall", undef), "getcaminfoall", $hash, 0); 
        }
        else 
        {
        # Beenden Polling aller Caminfos
        readingsSingleUpdate($hash,"PollState","Inactive",0);
        
        $logstr = "Polling of Camera $camname is deactivated now";
        &printlog($hash,$logstr,"2");

        }
}

###########################################################################
###   Kamera allgemeine Informationen abrufen (Get), sub von getcaminfoall

sub getcaminfo ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    
    if ($hash->{HELPER}{ACTIVE} ne "on") {
        # Kamerainfos abrufen
        $logstr = "Retrieval Camera-Informations of $camname starts now";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "Getcaminfo";
        $hash->{HELPER}{ACTIVE} = "on";
        
        &getapisites_nonbl($hash);
      }
    else
    {
        InternalTimer(gettimeofday()+0.6, "getcaminfo", $hash, 0);
    }
    
}

##########################################################################
###  Capabilities von Kamera abrufen (Get), sub von getcaminfoall

sub getcapabilities ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    
        if ($hash->{HELPER}{ACTIVE} ne "on") {
        # PTZ-ListPresets abrufen
        $logstr = "Retrieval Capabilities of Camera $camname starts now";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "Getcapabilities";
        $hash->{HELPER}{ACTIVE} = "on";
        
        &getapisites_nonbl($hash);
    }
    else
    {
        InternalTimer(gettimeofday()+0.7, "getcapabilities", $hash, 0);
    }
    
}

##########################################################################
###   PTZ Presets abrufen (Get), sub von getcaminfoall

sub getptzlistpreset ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    
    if (defined(ReadingsVal("$name", "DeviceType", undef)) and ReadingsVal("$name", "DeviceType", undef) ne "PTZ") {
        $logstr = "Retrieval of Presets for $camname can't be executed - $camname is not a PTZ-Camera";
        &printlog($hash,$logstr,"4");
        return;
        }

        if ($hash->{HELPER}{ACTIVE} ne "on") {
        # PTZ-ListPresets abrufen
        $logstr = "Retrieval PTZ-ListPresets of $camname starts now";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "Getptzlistpreset";
        $hash->{HELPER}{ACTIVE} = "on";
        
        &getapisites_nonbl($hash);
    }
    else
    {
        InternalTimer(gettimeofday()+0.8, "getptzlistpreset", $hash, 0);
    }
    
}


##########################################################################
###   PTZ Patrols abrufen (Get), sub von getcaminfoall

sub getptzlistpatrol ($) {
    my ($hash)   = @_;
    my $camname  = $hash->{CAMNAME};
    my $name     = $hash->{NAME};
    my $logstr;
    
    if (defined(ReadingsVal("$name", "DeviceType", undef)) and ReadingsVal("$name", "DeviceType", undef) ne "PTZ") {
        $logstr = "Retrieval of Patrols for $camname can't be executed - $camname is not a PTZ-Camera";
        &printlog($hash,$logstr,"4");
        return;
        }

        if ($hash->{HELPER}{ACTIVE} ne "on") {
        # PTZ-ListPatrols abrufen
        $logstr = "Retrieval PTZ-ListPatrols of $camname starts now";
        &printlog($hash,$logstr,"4");
                        
        $hash->{OPMODE} = "Getptzlistpatrol";
        $hash->{HELPER}{ACTIVE} = "on";
        
        &getapisites_nonbl($hash);
    }
    else
    {
        InternalTimer(gettimeofday()+0.9, "getptzlistpatrol", $hash, 0);
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
   my $serveraddr  = $hash->{SERVERADDR};
   my $serverport  = $hash->{SERVERPORT};
   my $name        = $hash->{NAME};
   my $apiinfo     = $hash->{HELPER}{APIINFO};                         # Info-Seite für alle API's, einzige statische Seite !
   my $apiauth     = $hash->{HELPER}{APIAUTH};                         # benötigte API-Pfade für Funktionen,  
   my $apiextrec   = $hash->{HELPER}{APIEXTREC};                       # in der Abfrage-Url an Parameter "&query="
   my $apicam      = $hash->{HELPER}{APICAM};                          # mit Komma getrennt angeben
   my $apitakesnap = $hash->{HELPER}{APISNAPSHOT};
   my $apiptz      = $hash->{HELPER}{APIPTZ};
   my $logstr;
   my $url;
   my $param;
   my $httptimeout;
  
   #### API-Pfade und MaxVersions ermitteln #####
   # Logausgabe
   $logstr = "--- Begin Function getapisites nonblocking ---";
   &printlog($hash,$logstr,"4");
   
   $httptimeout = AttrVal($name, "httptimeout",undef) ? AttrVal($name, "httptimeout",undef) : "4";
   # Logausgabe
   $logstr = "HTTP-Call will be done with httptimeout-Value: $httptimeout s";
   &printlog($hash,$logstr,"5");

   
   # URL zur Abfrage der Eigenschaften der  API's
   $url = "http://$serveraddr:$serverport/webapi/query.cgi?api=$apiinfo&method=Query&version=1&query=$apiauth,$apiextrec,$apicam,$apitakesnap,$apiptz";
   
   $param = {
               url      => $url,
               timeout  => $httptimeout,
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
   my $name        = $hash->{NAME};
   my $serveraddr  = $hash->{SERVERADDR};
   my $serverport  = $hash->{SERVERPORT};
   my $username    = $hash->{HELPER}{USERNAME};
   my $password    = $hash->{HELPER}{PASSWORD};
   my $apiauth     = $hash->{HELPER}{APIAUTH};
   my $apiextrec   = $hash->{HELPER}{APIEXTREC};
   my $apicam      = $hash->{HELPER}{APICAM};
   my $apitakesnap = $hash->{HELPER}{APISNAPSHOT};
   my $apiptz      = $hash->{HELPER}{APIPTZ};
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
   my $apiptzpath;
   my $apiptzmaxver;
   my $error;
   my $httptimeout;
  
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
        unless ($success) {$logstr = "Data returned: ".$myjson; &printlog($hash,$logstr,"4"); $hash->{HELPER}{ACTIVE} = "off"; return($hash,$success)};
        
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
                        $apiauthpath =~ tr/_//d if (defined($apiauthpath));
                        $apiauthmaxver = $data->{'data'}->{$apiauth}->{'maxVersion'}; 
       
                        $logstr = defined($apiauthpath) ? "Path of $apiauth selected: $apiauthpath" : "Path of $apiauth undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
                        $logstr = defined($apiauthmaxver) ? "MaxVersion of $apiauth selected: $apiauthmaxver" : "MaxVersion of $apiauth undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
       
                     # Pfad und Maxversion von "SYNO.SurveillanceStation.ExternalRecording" ermitteln
       
                        $apiextrecpath = $data->{'data'}->{$apiextrec}->{'path'};
                        # Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
                        $apiextrecpath =~ tr/_//d if (defined($apiextrecpath));
                        $apiextrecmaxver = $data->{'data'}->{$apiextrec}->{'maxVersion'}; 
       
                        $logstr = defined($apiextrecpath) ? "Path of $apiextrec selected: $apiextrecpath" : "Path of $apiextrec undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
                        $logstr = defined($apiextrecmaxver) ? "MaxVersion of $apiextrec selected: $apiextrecmaxver" : "MaxVersion of $apiextrec undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
       
                     # Pfad und Maxversion von "SYNO.SurveillanceStation.Camera" ermitteln
              
                        $apicampath = $data->{'data'}->{$apicam}->{'path'};
                        # Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
                        $apicampath =~ tr/_//d if (defined($apicampath));
                        $apicammaxver = $data->{'data'}->{$apicam}->{'maxVersion'};
                               
                        $logstr = defined($apicampath) ? "Path of $apicam selected: $apicampath" : "Path of $apicam undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
                        $logstr = defined($apiextrecmaxver) ? "MaxVersion of $apicam: $apicammaxver" : "MaxVersion of $apicam undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
       
                     # Pfad und Maxversion von "SYNO.SurveillanceStation.SnapShot" ermitteln
              
                        $apitakesnappath = $data->{'data'}->{$apitakesnap}->{'path'};
                        # Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
                        $apitakesnappath =~ tr/_//d if (defined($apitakesnappath));
                        $apitakesnapmaxver = $data->{'data'}->{$apitakesnap}->{'maxVersion'};
                            
                        $logstr = defined($apitakesnappath) ? "Path of $apitakesnap selected: $apitakesnappath" : "Path of $apitakesnap undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
                        $logstr = defined($apitakesnapmaxver) ? "MaxVersion of $apitakesnap: $apitakesnapmaxver" : "MaxVersion of $apitakesnap undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
						
                     # Pfad und Maxversion von "SYNO.SurveillanceStation.PTZ" ermitteln
              
                        $apiptzpath = $data->{'data'}->{$apiptz}->{'path'};
                        # Unterstriche im Ergebnis z.B.  "_______entry.cgi" eleminieren
                        $apiptzpath =~ tr/_//d if (defined($apiptzpath));
                        $apiptzmaxver = $data->{'data'}->{$apiptz}->{'maxVersion'};
                            
                        $logstr = defined($apiptzpath) ? "Path of $apiptz selected: $apiptzpath" : "Path of $apiptz undefined - Surveillance Station may be stopped";
                        &printlog($hash, $logstr,"4");
                        $logstr = defined($apiptzmaxver) ? "MaxVersion of $apiptz: $apiptzmaxver" : "MaxVersion of $apiptz undefined - Surveillance Station may be stopped";
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
                        $hash->{HELPER}{APIPTZPATH}        = $apiptzpath;
                        $hash->{HELPER}{APIPTZMAXVER}      = $apiptzmaxver;
       
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
  
  # Credentials abrufen
  ($success, $username, $password) = getcredentials($hash,0);
  unless ($success) {$logstr = "Credentials couldn't be retrieved successfully - make sure you've set it with \"set $name credentials <username> <password>\""; &printlog($hash,$logstr,"1"); $hash->{HELPER}{ACTIVE} = "off"; return($hash,$success)};
  
  $httptimeout = AttrVal($name, "httptimeout",undef) ? AttrVal($name, "httptimeout",undef) : "4";
  
  # Logausgabe
  $logstr = "HTTP-Call will be done with httptimeout-Value: $httptimeout s";
  &printlog($hash,$logstr,"5");  
 
  if (AttrVal($name, "session", undef) eq "SurveillanceStation") {
      $url = "http://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Login&account=$username&passwd=$password&session=SurveillanceStation&format=\"sid\"";
      }
      else
      {
      $url = "http://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Login&account=$username&passwd=$password&format=\"sid\""; 
      }
  
  $param = {
               url      => $url,
               timeout  => $httptimeout,
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
   my $hash                            = $param->{hash};
   my $name                            = $hash->{NAME};
   my $serveraddr                      = $hash->{SERVERADDR};
   my $serverport                      = $hash->{SERVERPORT};
   my $apicam                          = $hash->{HELPER}{APICAM};
   my $apicampath                      = $hash->{HELPER}{APICAMPATH};
   my $apicammaxver                    = $hash->{HELPER}{APICAMMAXVER};
   my ($success, $username)            = getcredentials($hash,0);   
   my $url;
   my $data;
   my $logstr;
   my $sid;
   my $error;
   my $errorcode;
   my $httptimeout;  
  
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
        unless ($success) {$logstr = "Data returned: ".$myjson; &printlog($hash,$logstr,"4"); $hash->{HELPER}{ACTIVE} = "off"; return($hash,$success)};
        
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
  
  $httptimeout = AttrVal($name, "httptimeout",undef) ? AttrVal($name, "httptimeout",undef) : "4";
  # Logausgabe
  $logstr = "HTTP-Call will be done with httptimeout-Value: $httptimeout s";
  &printlog($hash,$logstr,"5");  
  
  # einlesen aller Kameras - Auswertung in Rückkehrfunktion "camop_nonbl"
  # $apicammaxver um 1 verringern - Issue in API !
  # if (defined $apicammaxver) {$apicammaxver -= 1};
  $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=List&basic=true&streamInfo=true&camStm=true&_sid=\"$sid\"";

  $param = {
               url      => $url,
               timeout  => $httptimeout,
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
   my $name              = $hash->{NAME};
   my $serveraddr        = $hash->{SERVERADDR};
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
   my $apiptz            = $hash->{HELPER}{APIPTZ};
   my $apiptzpath        = $hash->{HELPER}{APIPTZPATH};
   my $apiptzmaxver      = $hash->{HELPER}{APIPTZMAXVER};
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
   my $n;
   my $id;
   my $httptimeout;
  
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
        
        # Evaluiere ob Daten im JSON-Format empfangen wurden, Achtung: sehr viele Daten mit verbose=5
        ($hash, $success) = &evaljson($hash,$myjson,$param->{url});
        unless ($success) {$logstr = "Data returned: ".$myjson; &printlog($hash,$logstr,"4"); $hash->{HELPER}{ACTIVE} = "off"; return($hash,$success)};
        
        $data = decode_json($myjson);
   
        $success = $data->{'success'};
                
        if ($success)                                                                       # die Liste aller Kameras konnte ausgelesen werden, Anzahl der definierten Kameras ist in Var "total"
        {
             # lesbare Ausgabe der decodierten JSON-Daten
             $logstr = "JSON returned: ". Dumper $data;                                     # Achtung: SEHR viele Daten !                                              
             &printlog($hash,$logstr,"5");
                    
             $camcount = $data->{'data'}->{'total'};
             $i = 0;
         
             # Namen aller installierten Kameras mit Id's in Assoziatives Array einlesen
             %allcams = ();
             while ($i < $camcount) 
                 {
                 $n = $data->{'data'}->{'cameras'}->[$i]->{'name'};
                 $id = $data->{'data'}->{'cameras'}->[$i]->{'id'};
                 $allcams{"$n"} = "$id";
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
                 $logstr = "ERROR - Cameraname $camname wasn't found in Surveillance Station. Check Userrights, Cameraname and Spelling.";
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

   $httptimeout = AttrVal($name, "httptimeout",undef) ? AttrVal($name, "httptimeout",undef) : "4";
   # Logausgabe
   $logstr = "HTTP-Call will be done with httptimeout-Value: $httptimeout s";
   &printlog($hash,$logstr,"5");
   
   if ($OpMode eq "Start") 
   {
      # die Aufnahme wird gestartet, Rückkehr wird mit "camret_nonbl" verarbeitet
      $url = "http://$serveraddr:$serverport/webapi/$apiextrecpath?api=$apiextrec&method=Record&version=$apiextrecmaxver&cameraId=$camid&action=start&_sid=\"$sid\""; 
   } 
   elsif ($OpMode eq "Stop")
   {
      # die Aufnahme wird gestoppt, Rückkehr wird mit "camret_nonbl" verarbeitet
      $url = "http://$serveraddr:$serverport/webapi/$apiextrecpath?api=$apiextrec&method=Record&version=$apiextrecmaxver&cameraId=$camid&action=stop&_sid=\"$sid\"";
   }
   elsif ($OpMode eq "Snap")
   {
      # ein Schnappschuß wird ausgelöst und in SS gespeichert, Rückkehr wird mit "camret_nonbl" verarbeitet
      $url = "http://$serveraddr:$serverport/webapi/$apitakesnappath?api=\"$apitakesnap\"&dsId=0&method=\"TakeSnapshot\"&version=\"$apitakesnapmaxver\"&camId=$camid&blSave=true&_sid=\"$sid\"";
      $hash->{STATE} = "snap";
      readingsSingleUpdate($hash, "LastSnapId", "", 1);
   }
   elsif ($OpMode eq "Enable")
   {
      # eine Kamera wird aktiviert, Rückkehr wird mit "camret_nonbl" verarbeitet
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=Enable&cameraIds=$camid&_sid=\"$sid\"";     
   }
   elsif ($OpMode eq "Disable")
   {
      # eine Kamera wird aktiviert, Rückkehr wird mit "camret_nonbl" verarbeitet
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=Disable&cameraIds=$camid&_sid=\"$sid\"";     
   }
   elsif ($OpMode eq "Getcaminfo")
   {
      # Infos einer Kamera werden abgerufen, Rückkehr wird mit "camret_nonbl" verarbeitet  
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=\"$apicam\"&version=\"$apicammaxver\"&method=\"GetInfo\"&cameraIds=\"$camid\"&deviceOutCap=true&streamInfo=true&ptz=true&basic=true&camAppInfo=true&optimize=true&fisheye=true&eventDetection=true&_sid=\"$sid\"";   
   }
   elsif ($OpMode eq "Getptzlistpreset")
   {
      # PTZ-ListPresets werden abgerufen, Rückkehr wird mit "camret_nonbl" verarbeitet
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=$apiptz&version=$apiptzmaxver&method=ListPreset&cameraId=$camid&_sid=\"$sid\"";   
   } 
   elsif ($OpMode eq "Getcapabilities")
   {
      # Capabilities einer Cam werden abgerufen, Rückkehr wird mit "camret_nonbl" verarbeitet
      $url = "http://$serveraddr:$serverport/webapi/$apicampath?api=$apicam&version=$apicammaxver&method=GetCapabilityByCamId&cameraId=$camid&_sid=\"$sid\"";   
   }
   elsif ($OpMode eq "Getptzlistpatrol")
   {
      # PTZ-ListPatrol werden abgerufen, Rückkehr wird mit "camret_nonbl" verarbeitet
      $url = "http://$serveraddr:$serverport/webapi/$apiptzpath?api=$apiptz&version=$apiptzmaxver&method=ListPatrol&cameraId=$camid&_sid=\"$sid\"";   
   }    

   
   $param = {
                url      => $url,
                timeout  => $httptimeout,
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
####      danach Verarbeitung Nutzdaten und weiter zum Logout
  
sub camret_nonbl ($) {  
   my ($param, $err, $myjson) = @_;
   my $hash             = $param->{hash};
   my $name             = $hash->{NAME};
   my $serveraddr       = $hash->{SERVERADDR};
   my $serverport       = $hash->{SERVERPORT};
   my $camname          = $hash->{CAMNAME};
   my $apiauth          = $hash->{HELPER}{APIAUTH};
   my $apiauthpath      = $hash->{HELPER}{APIAUTHPATH};
   my $apiauthmaxver    = $hash->{HELPER}{APIAUTHMAXVER};
   my $sid              = $hash->{HELPER}{SID};
   my $OpMode           = $hash->{OPMODE};
   my $rectime;
   my $url;
   my $data;
   my $logstr;
   my $success;
   my ($error,$errorcode);
   my $snapid;
   my $camLiveMode;
   my $update_time;
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
   my $deviceType;
   my $camStatus;
   my ($presetcnt,$cnt,%allpresets,$presid,$presname,@preskeys,$presetlist);
   my $verbose;
   my $httptimeout;
   
   # Die Aufnahmezeit setzen
   # wird "set <name> on-for-timer [rectime]" verwendet -> dann [rectime] nutzen, 
   # sonst Attribut "rectime" wenn es gesetzt ist, falls nicht -> "RECTIME_DEF"
   if (defined($hash->{HELPER}{RECTIME_TEMP})) {
       $rectime = delete $hash->{HELPER}{RECTIME_TEMP};
       }
       else
       {
       $rectime = AttrVal($name, "rectime",undef) ? AttrVal($name, "rectime",undef) : $hash->{HELPER}{RECTIME_DEF};
       }
   
  
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
        unless ($success) {$logstr = "Data returned: ".$myjson; &printlog($hash,$logstr,"4"); $hash->{HELPER}{ACTIVE} = "off"; return($hash,$success)};
        
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
                $logstr = $rectime != "0" ? "Camera $camname Recording with Recordtime $rectime"."s started" : "Camera $camname endless Recording started  - stop it manually or by stop-command !";
                &printlog($hash,$logstr,"2");  
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");                
       
                # Logausgabe
                $logstr = "Time for Recording is set to: $rectime";
                &printlog($hash,$logstr,"4");
                
                if ($rectime != "0") {
                    # Stop der Aufnahme nach Ablauf $rectime, wenn rectime = 0 -> endlose Aufnahme
                    InternalTimer(gettimeofday()+$rectime, "camstoprec", $hash, 0);
                    }              

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
                &printlog($hash,$logstr,"2");
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
                &printlog($hash,$logstr,"2");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "Enable") 
            {
                # Kamera wurde aktiviert, sonst kann nichts laufen -> "off"
                $hash->{STATE} = "off";
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Availability","enabled");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                   
                # Logausgabe
                $logstr = "Camera $camname has been enabled successfully";
                &printlog($hash,$logstr,"2");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "Disable") 
            {
                # Kamera wurde deaktiviert
                $hash->{STATE} = "disabled";
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Availability","disabled");
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                   
                # Logausgabe
                $logstr = "Camera $camname has been disabled successfully";
                &printlog($hash,$logstr,"2");
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "Getcaminfo") 
            {
                # Parse Caminfos
                $camLiveMode = $data->{'data'}->{'cameras'}->[0]->{'camLiveMode'};
                if ($camLiveMode eq "0") {$camLiveMode = "Liveview from DS";}elsif ($camLiveMode eq "1") {$camLiveMode = "Liveview from Camera";}
                
                $update_time = $data->{'data'}->{'cameras'}->[0]->{'update_time'};
                ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($update_time);
                $update_time = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;
                
                $deviceType = $data->{'data'}->{'cameras'}->[0]->{'deviceType'};
                if ($deviceType eq "1") {
                    $deviceType = "Camera";
                    }
                    elsif ($deviceType eq "2") {
                    $deviceType = "Video_Server";
                    }
                    elsif ($deviceType eq "4") {
                    $deviceType = "PTZ";
                    }
                    elsif ($deviceType eq "8") {
                    $deviceType = "Fisheye";
                    }
                
                $camStatus = $data->{'data'}->{'cameras'}->[0]->{'camStatus'};
                if ($camStatus eq "1") {
                    $camStatus = "enabled";
                    
                    # falls Aufnahme noch läuft -> STATE = on setzen
                    if (ReadingsVal("$name", "Record", "Stop") eq "Start") {
                        $hash->{STATE} = "on";
                        }
                        else
                        {
                        $hash->{STATE} = "off";
                        }
                    }
                    elsif ($camStatus eq "3") {
                    $camStatus = "disconnected";
                    }
                    elsif ($camStatus eq "7") {
                    $camStatus = "disabled";
                    $hash->{STATE} = "disable";
                    }
                    else {
                    $camStatus = "other";
                    }
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"CamLiveMode",$camLiveMode);
                readingsBulkUpdate($hash,"CamRecShare",$data->{'data'}->{'cameras'}->[0]->{'camRecShare'});
                readingsBulkUpdate($hash,"CamRecVolume",$data->{'data'}->{'cameras'}->[0]->{'camRecVolume'});
                readingsBulkUpdate($hash,"CamIP",$data->{'data'}->{'cameras'}->[0]->{'host'});
                readingsBulkUpdate($hash,"CamPort",$data->{'data'}->{'cameras'}->[0]->{'port'});
                readingsBulkUpdate($hash,"Availability",$camStatus);
                readingsBulkUpdate($hash,"DeviceType",$deviceType);
                readingsBulkUpdate($hash,"LastUpdateTime",$update_time);
                readingsBulkUpdate($hash,"UsedSpaceMB",$data->{'data'}->{'cameras'}->[0]->{'volume_space'});
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                            
                # Logausgabe
                $logstr = "Camera-Informations of $camname retrieved";
                # wenn "pollnologging" = 1 -> logging nur bei Verbose=4, sonst 2 
                if (defined(AttrVal($name, "pollnologging", undef)) and AttrVal($name, "pollnologging", undef) eq "1") {
                    $verbose = 4;
                    }
                    else
                    {
                    $verbose = 2;
                    }
                &printlog($hash,$logstr,$verbose);
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "Getcapabilities") 
            {
                # Parse Infos
                my $ptzfocus = $data->{'data'}{'ptzFocus'};
                if ($ptzfocus eq "0") {
                    $ptzfocus = "false";
                    }
                    elsif ($ptzfocus eq "1") {
                    $ptzfocus = "support step operation";
                    }
                    elsif ($ptzfocus eq "2") {
                    $ptzfocus = "support continuous operation";
                    }
                    
                my $ptztilt = $data->{'data'}{'ptzTilt'};
                if ($ptztilt eq "0") {
                    $ptztilt = "false";
                    }
                    elsif ($ptztilt eq "1") {
                    $ptztilt = "support step operation";
                    }
                    elsif ($ptztilt eq "2") {
                    $ptztilt = "support continuous operation";
                    }
                    
                my $ptzzoom = $data->{'data'}{'ptzZoom'};
                if ($ptzzoom eq "0") {
                    $ptzzoom = "false";
                    }
                    elsif ($ptzzoom eq "1") {
                    $ptzzoom = "support step operation";
                    }
                    elsif ($ptzzoom eq "2") {
                    $ptzzoom = "support continuous operation";
                    }
                    
                my $ptzpan = $data->{'data'}{'ptzPan'};
                if ($ptzpan eq "0") {
                    $ptzpan = "false";
                    }
                    elsif ($ptzpan eq "1") {
                    $ptzpan = "support step operation";
                    }
                    elsif ($ptzpan eq "2") {
                    $ptzpan = "support continuous operation";
                    }
                
                my $ptziris = $data->{'data'}{'ptzIris'};
                if ($ptziris eq "0") {
                    $ptziris = "false";
                    }
                    elsif ($ptziris eq "1") {
                    $ptziris = "support step operation";
                    }
                    elsif ($ptziris eq "2") {
                    $ptziris = "support continuous operation";
                    }
                
                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"CapPTZAutoFocus",$data->{'data'}{'ptzAutoFocus'});
                readingsBulkUpdate($hash,"CapAudioOut",$data->{'data'}{'audioOut'});
                readingsBulkUpdate($hash,"CapChangeSpeed",$data->{'data'}{'ptzSpeed'});
                readingsBulkUpdate($hash,"CapPTZHome",$data->{'data'}{'ptzHome'});
                readingsBulkUpdate($hash,"CapPTZAbs",$data->{'data'}{'ptzAbs'});
                readingsBulkUpdate($hash,"CapPTZDirections",$data->{'data'}{'ptzDirection'});
                readingsBulkUpdate($hash,"CapPTZFocus",$ptzfocus);
                readingsBulkUpdate($hash,"CapPTZIris",$ptziris);
                readingsBulkUpdate($hash,"CapPTZPan",$ptzpan);
                readingsBulkUpdate($hash,"CapPTZTilt",$ptztilt);
                readingsBulkUpdate($hash,"CapPTZZoom",$ptzzoom);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                  
                # Logausgabe
                $logstr = "Capabilities of Camera $camname retrieved";
                # wenn "pollnologging" = 1 -> logging nur bei Verbose=4, sonst 2 
                if (defined(AttrVal($name, "pollnologging", undef)) and AttrVal($name, "pollnologging", undef) eq "1") {
                    $verbose = 4;
                    }
                    else
                    {
                    $verbose = 2;
                    }
                &printlog($hash,$logstr,$verbose);
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }            
            elsif ($OpMode eq "Getptzlistpreset") 
            {
                # Parse PTZ-ListPresets
                $presetcnt = $data->{'data'}->{'total'};
                $cnt = 0;
         
                # alle Presets der Kamera mit Id's in Assoziatives Array einlesen
                %allpresets = ();
                while ($cnt < $presetcnt) 
                    {
                    $presid = $data->{'data'}->{'presets'}->[$cnt]->{'id'};
                    $presname = $data->{'data'}->{'presets'}->[$cnt]->{'name'};
                    $allpresets{$presname} = "$presid";
                    $cnt += 1;
                    }
                    
                # Presethash in $hash einfügen
                $hash->{HELPER}{ALLPRESETS} = \%allpresets;

                @preskeys = sort(keys(%allpresets));
                $presetlist = join(",",@preskeys);
                
                # print "ID von Home ist : ". %allpresets->{"home"};
                # print "aus Hash: ".$hash->{HELPER}{ALLPRESETS}{home};

                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Presets",$presetlist);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                  
                            
                # Logausgabe
                $logstr = "PTZ Presets of $camname retrieved";
                # wenn "pollnologging" = 1 -> logging nur bei Verbose=4, sonst 2 
                if (defined(AttrVal($name, "pollnologging", undef)) and AttrVal($name, "pollnologging", undef) eq "1") {
                    $verbose = 4;
                    }
                    else
                    {
                    $verbose = 2;
                    }
                &printlog($hash,$logstr,$verbose);
                $logstr = "--- End Function cam: $OpMode nonblocking ---";
                &printlog($hash,$logstr,"4");
            }
            elsif ($OpMode eq "Getptzlistpatrol") 
            {
                # Parse PTZ-ListPatrols
                my $patrolcnt = $data->{'data'}->{'total'};
                $cnt = 0;
         
                # alle Patrols der Kamera mit Id's in Assoziatives Array einlesen
                my %allpatrols = ();
                while ($cnt < $patrolcnt) 
                    {
                    my $patrolid = $data->{'data'}->{'patrols'}->[$cnt]->{'id'};
                    my $patrolname = $data->{'data'}->{'patrols'}->[$cnt]->{'name'};
                    $allpatrols{$patrolname} = $patrolid;
                    $cnt += 1;
                    }
                    
                # Presethash in $hash einfügen
                $hash->{HELPER}{ALLPATROLS} = \%allpatrols;

                my @patrolkeys = sort(keys(%allpatrols));
                my $patrollist = join(",",@patrolkeys);
                
                # print "ID von Tour1 ist : ". %allpatrols->{Tour1};
                # print "aus Hash: ".$hash->{HELPER}{ALLPRESETS}{Tour1};

                # Setreading 
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Patrols",$patrollist);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);
                  
                            
                # Logausgabe
                $logstr = "PTZ Patrols of $camname retrieved";
                # wenn "pollnologging" = 1 -> logging nur bei Verbose=4, sonst 2 
                if (defined(AttrVal($name, "pollnologging", undef)) and AttrVal($name, "pollnologging", undef) eq "1") {
                    $verbose = 4;
                    }
                    else
                    {
                    $verbose = 2;
                    }
                &printlog($hash,$logstr,$verbose);
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
    
    $httptimeout = AttrVal($name, "httptimeout",undef) ? AttrVal($name, "httptimeout",undef) : "4";
    # Logausgabe
    $logstr = "HTTP-Call will be done with httptimeout-Value: $httptimeout s";
    &printlog($hash,$logstr,"5");    
  
    if (AttrVal($name, "session", undef) eq "SurveillanceStation") {
        $url = "http://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Logout&session=SurveillanceStation&_sid=$sid";
        }
        else
        {
        $url = "http://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthmaxver&method=Logout&_sid=$sid";
        }

    $param = {
                url      => $url,
                timeout  => $httptimeout,
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
   my $hash                            = $param->{hash};
   my $sid                             = $hash->{HELPER}{SID};
   my ($success, $username)            = getcredentials($hash,0);
   my $data;
   my $logstr;
   my $error;
   my $errorcode;
  
   if($err ne "")                                                                                     # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
   {
        $logstr = "error while requesting ".$param->{url}." - $err";
        &printlog($hash,$logstr,"1");		                                                      # Eintrag fürs Log
        $logstr = "--- End Function logout nonblocking with error ---";
        &printlog($hash,$logstr,"4");
        
        readingsSingleUpdate($hash, "Error", $err, 1);                                     	       # Readings erzeugen 

   }
   elsif($myjson ne "")                                                                                # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
   {
        $logstr = "URL-Call: ".$param->{url};                                                          
        &printlog($hash,$logstr,"4");
        
        # An dieser Stelle die Antwort parsen / verarbeiten mit $myjson 
        
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, $success) = &evaljson($hash,$myjson,$param->{url});
        unless ($success) {$logstr = "Data returned: ".$myjson; &printlog($hash,$logstr,"4"); $hash->{HELPER}{ACTIVE} = "off"; return($hash,$success)};
        
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
# ausgeführte Funktion ist erledigt (auch wenn logout nicht erfolgreich), Freigabe Funktionstoken
$hash->{HELPER}{ACTIVE} = "off";   

return;
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
  402 => "Permission denied - make sure user is member of Admin-group if DSM-Session is used",
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
  104 => "This API version is not supported",
  105 => "Insufficient user privilege",
  106 => "Connection time out",
  107 => "Multiple login detected",
  117 => "need manager rights in SurveillanceStation for operation",
  400 => "Execution failed",
  401 => "Parameter invalid",
  402 => "Camera disabled",
  403 => "Insufficient license",
  404 => "Codec activation failed",
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
  Using this Module you are able to operate with cameras which are defined in Synology Surveillance Station (SVS). <br>
  At present the following functions are available: <br><br>
   <ul>
    <ul>
       <li>Start a Recording</li>
       <li>Stop a Recording (using command or automatically after the &lt;RecordTime&gt; period</li>
       <li>Trigger a Snapshot </li>
       <li>Deaktivate a Camera in Synology Surveillance Station</li>
       <li>Activate a Camera in Synology Surveillance Station</li>
       <li>Retrieval of Camera Properties (Polling)</li><br>
    </ul>
   </ul>
   The recordings and snapshots will be stored in Synology Surveillance Station (SVS) and are managed like the other (normal) recordings / snapshots defined by Surveillance Station rules.<br>
   For example the recordings are stored for a defined time in Surveillance Station and will be deleted after that period.<br><br>
    
   If you like to discuss or help to improve this module please use FHEM-Forum with link: <br>
   <a href="http://forum.fhem.de/index.php/topic,45671.msg374390.html#msg374390">49_SSCam: Fragen, Hinweise, Neuigkeiten und mehr rund um dieses Modul</a>.<br><br>
  
<b> Prerequisites </b> <br><br>
    This module uses the CPAN-module JSON. Please consider to install this package (Debian: libjson-perl).<br>
    You don't need to install LWP anymore, because of SSCam is completely using the nonblocking functions of HttpUtils respectively HttpUtils_NonblockingGet now. <br> 
    In DSM respectively in Synology Surveillance Station an User has to be created. The login credentials are needed later when using a set-command to assign the login-data to a device. <br> 
    Further informations could be find among <a href="#Credentials">Credentials</a>.  <br><br>
    

  <a name="SCamdefine"></a>
  <b>Define</b>
  <ul>
  <br>
    <code>define &lt;name&gt; SSCAM &lt;Cameraname in SVS&gt; &lt;ServerAddr&gt; &lt;Port&gt;  </code><br>
    <br>
    Defines a new camera device for SSCam. At first the devices have to be set up and operable in Synology Surveillance Station 7.0 and above. <br><br>
    
    The Modul SSCam ist based on functions of Synology Surveillance Station API. <br>
    Please refer the <a href="http://global.download.synology.com/download/Document/DeveloperGuide/Surveillance_Station_Web_API_v2.0.pdf">Web API Guide</a>. <br><br>
    
    Currently only HTTP-protocol is supported to call Synology DS. <br><br>  

    The parameters are in detail:
   <br>
   <br>    
     
   <table>
    <colgroup> <col width=15%> <col width=85%> </colgroup>
    <tr><td>name:         </td><td>the name of the new device to use in FHEM</td></tr>
    <tr><td>Cameraname:   </td><td>Cameraname as defined in Synology Surveillance Station, Spaces are not allowed in Cameraname !</td></tr>
    <tr><td>ServerAddr:   </td><td>IP-address of Synology Surveillance Station Host. <b>Note:</b> avoid using hostnames because of DNS-Calls are not unblocking in FHEM </td></tr>
    <tr><td>Port:         </td><td>the Port Synology surveillance Station Host, normally 5000 (HTTP only)</td></tr>
   </table>

    <br><br>

    <b>Example:</b>
     <pre>
      define CamCP SSCAM Carport 192.168.2.20 5000  
    </pre>
    
    
    When a new Camera is defined, as a start the recordingtime of 15 seconds will be assigned to the device.<br>
    Using the <a href="#SSCamattr">attribute</a> "rectime" you can adapt the recordingtime for every camera individually.<br>
    The value of "0" for rectime will lead to an endless recording which has to be stopped by a "set &lt;name&gt; off" command.<br>
    Due to a Log-Entry with a hint to that circumstance will be written. <br><br>
    
    If the <a href="#SSCamattr">attribute</a> "rectime" would be deleted again, the default-value for recording-time (15s) become active.<br><br>

    With <a href="#SSCamset">command</a> <b>"set &lt;name&gt; on [rectime]"</b> a temporary recordingtime is determinded which would overwrite the dafault-value of recordingtime <br>
    and the attribute "rectime" (if it is set) uniquely. <br><br>

    In that case the command <b>"set &lt;name&gt; on 0"</b> leads also to an endless recording.<br><br>
    
    If you have specified a pre-recording time in SVS it will be considered too. <br><br><br>
    
    
    <a name="Credentials"></a>
    <b>Credentials </b><br><br>
    
    After a camera-device is defined, firstly it is needed to save the credentials. This will be done with command:
   
    <pre> 
     set &lt;name&gt; credentials &lt;username&gt; &lt;password&gt;
    </pre>
    
    The operator can, dependend on what functions are planned to execute, create an user in DSM respectively in Synology Surveillance Station as well. <br>
    If the user is member of admin-group, he has access to all module functions. Without this membership the user can only execute functions with lower need of rights. <br>
    The required minimum rights to execute functions are listed in a table further down. <br>
    
    Alternatively to DSM-user a user created in SVS can be used. Also in that case a user of type "manager" has the right to execute all functions, <br>
    whereat the access to particular cameras can be restricted by the privilege profile (please see help function in SVS for details).  <br>
    As best practice it is proposed to create an user in DSM as well as in SVS too:  <br><br>
    
    <ul>
    <li>DSM-User as member of admin group: unrestricted test of all module functions -&gt; session: DSM  </li>
    <li>SVS-User as Manager or observer: adjusted privilege profile -&gt; session: SurveillanceStation  </li>
    </ul>
    <br>
    
    Using the <a href="#SSCamattr">Attribute</a> "session" can be selected, if the session should be established to DSM or the SVS instead. <br>
    If the session will be established to DSM, SVS Web-API methods are available as well as further API methods of other API's what possibly needed for processing. <br><br>
    
    After device definition the default is "login to DSM", that means credentials with admin rights can be used to test all camera-functions firstly. <br>
    After this the credentials can be switched to a SVS-session with a restricted privilege profile as needed on dependency what module functions are want to be executed. <br><br>
    
    The following list shows the minimum rights what the particular module function needs. <br><br>
    <ul>
      <table>
      <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td><li>set ... on                 </td><td> session: ServeillanceStation - observer with enhanced privilege "manual recording" </li></td></tr>
      <tr><td><li>set ... off                </td><td> session: ServeillanceStation - observer with enhanced privilege "manual recording" </li></td></tr>
      <tr><td><li>set ... snap               </td><td> session: ServeillanceStation - observer    </li></td></tr>
      <tr><td><li>set ... disable            </td><td> session: ServeillanceStation - manager       </li></td></tr>
      <tr><td><li>set ... enable             </td><td> session: ServeillanceStation - manager       </li></td></tr>
      <tr><td><li>set ... credentials        </td><td> -                                            </li></td></tr>
      <tr><td><li>get ... caminfoall         </td><td> session: ServeillanceStation - observer    </li></td></tr>
      </table>
    </ul>
      <br><br>
    

    <b>HTTP-Timeout Settings</b><br><br>
    All functions of the SSCam-Module are using HTTP-Calls to the SVS Web API. <br>
    The Default-Value of the HTTP-Timeout amounts 4 seconds. You can set the <a href="#SSCamattr">Attribute</a> "httptimeout" > 0 to adjust the value as needed in your technical environment. <br>
    
  </ul>
  <br><br><br>
  
  
<a name="SSCamset"></a>
<b>Set </b>
  <ul>
    
  Currently there are the following options for "Set &lt;name&gt; ..."  : <br><br>

  <table>
  <colgroup> <col width=15%> <col width=85%> </colgroup>
      <tr><td>"on [rectime]":  </td><td>starts a recording. The recording will be stopped automatically after a period of [rectime] </td></tr>
      <tr><td>                 </td><td>if [rectime] = 0 an endless recording will be started </td></tr>
      <tr><td>"off" :          </td><td>stopps a running recording manually or using other events (e.g. with at, notify)</td></tr>
      <tr><td>"snap":          </td><td>triggers a snapshot of the relevant camera and store it into Synology Surveillance Station</td></tr>
      <tr><td>"disable":       </td><td>deactivates a camera in Synology Surveillance Station</td></tr>
      <tr><td>"enable":        </td><td>activates a camera in Synology Surveillance Station</td></tr>
  </table>
  <br><br>
        
  Examples for simple <b>Start/Stop a Recording</b>: <br><br>

  <table>
  <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td>set &lt;name&gt; on [rectime]  </td><td>starts a recording of camera &lt;name&gt;, stops automatically after [rectime] (default 15s or defined by <a href="#SSCamattr">attribute</a>) </td></tr>
      <tr><td>set &lt;name&gt; off           </td><td>stops the recording of camera &lt;name&gt;</td></tr>
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
     define he1_snap_3 notify CamHE1:Record.*on define h3 at +*{3}00:00:02 set CamHE1 snap 
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


<a name="SSCamget"></a>
<b>Get</b>
 <ul>
  With SSCam the properties of defined Cameras could be retrieved. It could be done by using the command:
  <pre>
      get &lt;name&gt; caminfoall
  </pre>
  
  Dependend from the type of Camera (e.g. Fix- or PTZ-Camera) the available properties will be retrieved and provided as Readings.<br>
  For example the Reading "Availability" will be set to "disconnected" if the Camera would be disconnected from Synology Surveillance Station and can be used for further <br>
  processing like crearing events. <br><br>

  <b>Polling of Camera-Properties:</b><br><br>

  Retrieval of Camera-Properties can be done automatically if the attribute "pollcaminfoall" will be set to a value &gt; 10. <br>
  As default that attribute "pollcaminfoall" isn't be set and the automatic polling isn't be active. <br>
  The value of that attribute determines the interval of property-retrieval in seconds. If that attribute isn't be set or &lt; 10 the automatic polling won't be started <br>
  respectively stopped when the value was set to &gt; 10 before. <br><br>

  The attribute "pollcaminfoall" is monitored by a watchdog-timer. Changes of th attributevalue will be checked every 90 seconds and transact correspondig. <br>
  Changes of the pollingstate and pollinginterval will be reported in FHEM-Logfile. The reporting can be switched off by setting the attribute "pollnologging=1". <br>
  Thereby the needless growing of the logfile can be avoided. But if verbose is set to 4 or above even though the attribute "pollnologging" is set as well, the polling <br>
  will be actived due to analysis purposes. <br><br>

  If FHEM will be restarted, the first data retrieval will be done within 60 seconds after start. <br><br>

  The state of automatic polling will be displayed by reading "PollState": <br><br>
  
  <ul>
    <li><b> PollState = Active </b>     -    automatic polling will be executed with interval correspondig value of attribute "pollcaminfoall" </li>
    <li><b> PollState = Inactive </b>   -    automatic polling won't be executed </li>
  </ul>
  <br>
  
  The meaning of reading values is described under <a href="#SSCamreadings">Readings</a> . <br><br>

  <b>Notes:</b> <br><br>

  If polling is used, the interval should be adjusted only as short as needed due to the detected camera values are predominantly static. <br>
  A feasible guide value for attribute "pollcaminfoall" could be between 600 - 1800 (s). <br>
  Per polling call and camera approximately 10 - 20 Http-calls will are stepped against Surveillance Station. <br>
  Because of that if HTTP-Timeout (pls. refer <a href="#SSCamattr">Attribut</a> "httptimeout") is set to 4 seconds, the theoretical processing time couldn't be higher than 80 seconds. <br>
  Considering a safety margin, in that example you shouldn't set the polling interval lower than 160 seconds. <br><br>

  If several Cameras are defined in SSCam, attribute "pollcaminfoall" of every Cameras shouldn't be set exactly to the same value to avoid processing bottlenecks <br>
  and thereby caused potential source of errors during request Synology Surveillance Station. <br>
  A marginal difference between the polling intervals of the defined cameras, e.g. 1 second, can already be faced as sufficient value. <br><br> 
</ul>

<a name="SSCaminternals"></a>
<b>Internals</b> <br>
 <ul>
 The meaning of used Internals is depicted in following list: <br><br>
  <ul>
  <li><b>CAMID</b> - the ID of camera defined in SVS, the value will be retrieved automatically on the basis of SVS-cameraname </li>
  <li><b>CAMNAME</b> - the name of the camera in SVS </li>
  <li><b>CREDENTIALS</b> - the value is "Set" if Credentials are set </li> 
  <li><b>NAME</b> - the cameraname in FHEM </li>
  <li><b>OPMODE</b> - the last executed operation of the module </li>  
  <li><b>SERVERADDR</b> - IP-Address of SVS Host </li>
  <li><b>SERVERPORT</b> - SVS-Port </li>
  
  <br><br>
  </ul>
 </ul>

<a name="SSCamreadings"></a>
<b>Readings</b>
 <ul>
  <br>
  Using the polling mechanism or retrieval by "get"-call readings are provieded, The meaning of the readings are listed in subsequent table: <br>
  The transfered Readings can be deversified dependend on the type of camera.<br><br>
  <ul>
  <table>  
  <colgroup> <col width=5%> <col width=95%> </colgroup>
    <tr><td><li>Availability</li>       </td><td>- Availability of Camera (disabled, enabled, disconnected, other)  </td></tr>
    <tr><td><li>CamIP</li>              </td><td>- IP-Address of Camera  </td></tr>
    <tr><td><li>CamLiveMode</li>        </td><td>- Source of Live-View (DS, Camera)  </td></tr>
    <tr><td><li>CamPort</li>            </td><td>- IP-Port of Camera  </td></tr>
    <tr><td><li>CamRecShare</li>        </td><td>- shared folder on disk station for recordings </td></tr>
    <tr><td><li>CamRecVolume</li>       </td><td>- Volume on disk station for recordings  </td></tr>
    <tr><td><li>CapAudioOut</li>        </td><td>- Capability to Audio Out over Surveillance Station (false/true)  </td></tr>
    <tr><td><li>CapChangeSpeed</li>     </td><td>- Capability to various motion speed  </td></tr>
    <tr><td><li>CapPTZAbs</li>          </td><td>- Capability to perform absolute PTZ action  </td></tr>
    <tr><td><li>CapPTZAutoFocus</li>    </td><td>- Capability to perform auto focus action  </td></tr>
    <tr><td><li>CapPTZDirections</li>   </td><td>- the PTZ directions that camera support  </td></tr>
    <tr><td><li>CapPTZFocus</li>        </td><td>- mode of support for focus action  </td></tr>
    <tr><td><li>CapPTZHome</li>         </td><td>- Capability to perform home action  </td></tr>
    <tr><td><li>CapPTZIris</li>         </td><td>- mode of support for iris action  </td></tr>
    <tr><td><li>CapPTZPan</li>          </td><td>- Capability to perform pan action  </td></tr>
    <tr><td><li>CapPTZTilt</li>         </td><td>- mode of support for tilt action  </td></tr>
    <tr><td><li>CapPTZZoom</li>         </td><td>- Capability to perform zoom action  </td></tr>
    <tr><td><li>DeviceType</li>         </td><td>- device type (Camera, Video_Server, PTZ, Fisheye)  </td></tr>
    <tr><td><li>Error</li>              </td><td>- message text of last error  </td></tr>
    <tr><td><li>Errorcode</li>          </td><td>- error code of last error  </td></tr>
    <tr><td><li>LastUpdateTime</li>     </td><td>- date / time of last update of Camera in Synology Surrveillance Station  </td></tr>   
    <tr><td><li>Patrols</li>            </td><td>- in Synology Surveillance Station predefined patrols (at PTZ-Cameras)  </td></tr>
    <tr><td><li>PollState</li>          </td><td>- shows the state of automatic polling  </td></tr>    
    <tr><td><li>Presets</li>            </td><td>- in Synology Surveillance Station predefined Presets (at PTZ-Cameras)  </td></tr>
    <tr><td><li>Record</li>             </td><td>- if recording is running = Start, if no recording is running = Stop  </td></tr>   
    <tr><td><li>UsedSpaceMB</li>        </td><td>- used disk space of recordings by Camera  </td></tr>
  </table>
  </ul>
  <br><br>    
  
 </ul>

 
<a name="SSCamattr"></a>
<b>Attributes</b>
  <br><br>
  <ul>
  <ul>
  <li><b>httptimeout</b> - Timeout-Value of HTTP-Calls to Synology Surveillance Station, Default: 4 seconds (if httptimeout = "0" or not set) </li>
  
  <li><b>pollcaminfoall</b> - Interval of automatic polling the Camera properties (if < 10: no polling, if &gt; 10: polling with interval) </li>

  <li><b>pollnologging</b> - "0" resp. not set = Logging device polling active (default), "1" = Logging device polling inactive</li>
  
  <li><b>rectime</b> - the determined recordtime when a recording starts. If rectime = 0 an endless recording will be started. If it isn't defined, the default recordtime of 15s is activated </li>
  
  <li><b>session</b>  - selection of login-Session. Not set or set to "DSM" -&gt; session will be established to DSM (Sdefault). "SurveillanceStation" -&gt; session will be established to SVS </li><br>
  
  <li><b>verbose</b></li><br>
  
  <ul>
     Different Verbose-Level are supported.<br>
     Those are in detail:
   
   <table>  
   <colgroup> <col width=5%> <col width=95%> </colgroup>
     <tr><td> 0  </td><td>- Start/Stop-Event will be logged </td></tr>
     <tr><td> 1  </td><td>- Error messages will be logged </td></tr>
     <tr><td> 2  </td><td>- messages according to important events were logged </td></tr>
     <tr><td> 3  </td><td>- sended commands will be logged </td></tr> 
     <tr><td> 4  </td><td>- sended and received informations will be logged </td></tr>
     <tr><td> 5  </td><td>- all outputs will be logged for error-analyses. <b>Caution:</b> a lot of data could be written into logfile ! </td></tr>
   </table>
   </ul>     
   <br><br>
  
   <b>further Attributes:</b><br><br>
   
   <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>  
  </ul>
  <br><br>
</ul>


=end html
=begin html_DE

<a name="SSCam"></a>
<h3>SSCam</h3>
<ul>
    Mit diesem Modul können Operationen von in der Synology Surveillance Station (SVS) definierten Kameras ausgeführt werden. <br>
    Zur Zeit werden folgende Funktionen unterstützt: <br><br>
    <ul>
     <ul>
      <li>Start einer Aufnahme</li>
      <li>Stop einer Aufnahme (per Befehl bzw. automatisch nach Ablauf der Aufnahmedauer) </li>
      <li>Aufnehmen eines Schnappschusses und Ablage in der Synology Surveillance Station </li>
      <li>Deaktivieren einer Kamera in Synology Surveillance Station</li>
      <li>Aktivieren einer Kamera in Synology Surveillance Station</li>
      <li>Abfrage von Kameraeigenschaften (Polling)</li><br>
     </ul> 
    </ul>
    Die Aufnahmen stehen in der Synology Surveillance Station (SVS) zur Verfügung und unterliegen, wie jede andere Aufnahme, den in der Synology Surveillance Station eingestellten Regeln. <br>
    So werden zum Beispiel die Aufnahmen entsprechend ihrer Archivierungsfrist gespeichert und dann gelöscht. <br><br>
    
    Wenn sie über dieses Modul diskutieren oder zur Verbesserung des Moduls beitragen möchten, ist im FHEM-Forum ein Sammelplatz unter:<br>
    <a href="http://forum.fhem.de/index.php/topic,45671.msg374390.html#msg374390">49_SSCam: Fragen, Hinweise, Neuigkeiten und mehr rund um dieses Modul</a>.<br><br>

<b>Vorbereitung </b> <br><br>
    Dieses Modul nutzt das CPAN Module JSON. Bitte darauf achten dieses Paket zu installieren. (Debian: libjson-perl). <br>
    Das CPAN-Modul LWP wird für SSCam nicht mehr benötigt. Das Modul verwendet für HTTP-Calls die nichtblockierenden Funktionen von HttpUtils bzw. HttpUtils_NonblockingGet. <br> 
    Im DSM bzw. der Synology Surveillance Station muß ein Nutzer angelegt sein. Die Zugangsdaten werden später über ein Set-Kommando dem angelegten Gerät zugewiesen. <br>
    Nähere Informationen dazu unter <a href="#Credentials">Credentials</a><br><br>

<a name="SSCamdefine"></a>
<b>Definition</b>
  <ul>
  <br>
    <code>define &lt;name&gt; SSCAM &lt;Kameraname in SVS&gt; &lt;ServerAddr&gt; &lt;Port&gt; </code><br>
    <br>
    
    Definiert eine neue Kamera für SSCam. Zunächst muß diese Kamera in der Synology Surveillance Station 7.0 oder höher eingebunden sein und entsprechend funktionieren.<br><br>
    Das Modul SSCam basiert auf Funktionen der Synology Surveillance Station API. <br>
    Weitere Informationen unter: <a href="http://global.download.synology.com/download/Document/DeveloperGuide/Surveillance_Station_Web_API_v2.0.pdf">Web API Guide</a>. <br><br>
    
    Momentan wird nur das HTTP-Protokoll unterstützt um die Web-Services der Synology DS aufzurufen. <br><br>  
    
    Die Parameter beschreiben im Einzelnen:
   <br>
   <br>    
    
    <table>
    <colgroup> <col width=15%> <col width=85%> </colgroup>
    <tr><td>name:           </td><td>der Name des neuen Gerätes in FHEM</td></tr>
    <tr><td>Kameraname:     </td><td>Kameraname wie er in der Synology Surveillance Station angegeben ist. Leerzeichen im Namen sind nicht erlaubt !</td></tr>
    <tr><td>ServerAddr:     </td><td>die IP-Addresse des Synology Surveillance Station Host. Hinweis: Es sollte kein Servername verwendet werden weil DNS-Aufrufe in FHEM blockierend sind.</td></tr>
    <tr><td>Port:           </td><td>der Port des Synology Surveillance Station Host. Normalerweise ist das 5000 (nur HTTP)</td></tr>
    </table>

    <br><br>

    <b>Beispiel:</b>
     <pre>
      define CamCP SSCAM Carport 192.168.2.20 5000      
     </pre>
     
    
    Wird eine neue Kamera definiert, wird diesem Device zunächst eine Standardaufnahmedauer von 15 zugewiesen. <br>
    Über das <a href="#SSCamattr">Attribut</a> "rectime" kann die Aufnahmedauer für jede Kamera individuell angepasst werden. Der Wert "0" für "rectime" führt zu einer Endlosaufnahme, die durch "set &lt;name&gt; off" wieder gestoppt werden muß. <br>
    Ein Logeintrag mit einem entsprechenden Hinweis auf diesen Umstand wird geschrieben. <br><br>

    Wird das <a href="#SSCamattr">Attribut</a> "rectime" gelöscht, greift wieder der Default-Wert (15s) für die Aufnahmedauer. <br><br>

    Mit dem <a href="#SSCamset">Befehl</a> <b>"set &lt;name&gt; on [rectime]"</b> wird die Aufnahmedauer temporär festgelegt und überschreibt einmalig sowohl den Defaultwert als auch den Wert des gesetzten Attributs "rectime". <br>
    Auch in diesem Fall führt <b>"set &lt;name&gt; on 0"</b> zu einer Daueraufnahme. <br><br>

    Eine eventuell in der SVS eingestellte Dauer der Voraufzeichnung wird weiterhin berücksichtigt. <br><br><br>
    
    
    <a name="Credentials"></a>
    <b>Credentials </b><br><br>
    
    Nach dem Definieren des Gerätes müssen zuerst die Zugangsrechte gespeichert werden. Das geschieht mit dem Befehl:
   
    <pre> 
     set &lt;name&gt; credentials &lt;username&gt; &lt;password&gt;
    </pre>
    
    Der Anwender kann in Abhängigkeit der beabsichtigten einzusetzenden Funktionen einen Nutzer im DSM bzw. in der Surveillance Station einrichten. <br>
    Ist der DSM-Nutzer der Gruppe Administratoren zugeordnet, hat er auf alle Funktionen Zugriff. Ohne diese Gruppenzugehörigkeit können nur Funktionen mit niedrigeren <br>
    Rechtebedarf ausgeführt werden. Die benötigten Mindestrechte der Funktionen sind in der Tabelle weiter unten aufgeführt. <br>
    
    Alternativ zum DSM-Nutzer kann ein in der SVS angelegter Nutzer verwendet werden. Auch in diesem Fall hat ein Nutzer vom Typ Manager das Recht alle Funktionen  <br>
    auszuführen, wobei der Zugriff auf bestimmte Kameras/ im Privilegienprofil beschränkt werden kann (siehe Hilfefunktion in SVS). <br>
    Als Best Practice wird vorgeschlagen jeweils einen User im DSM und einen in der SVS anzulegen: <br><br>
    
    <ul>
    <li>DSM-User als Mitglied der Admin-Gruppe: uneingeschränkter Test aller Modulfunktionen -> session:DSM  </li>
    <li>SVS-User als Manager oder Betrachter: angepasstes Privilegienprofil -> session: SurveillanceStation  </li>
    </ul>
    <br>
    
    Über das <a href="#SSCamattr">Attribut</a> "session" kann ausgewählt werden, ob die Session mit dem DSM oder der SVS augebaut werden soll. <br>
    Erfolgt der Session-Aufbau mit dem DSM, stehen neben der SVS Web-API auch darüber hinaus gehende API-Zugriffe zur Verfügung die unter Umständen zur Verarbeitung benötigt werden. <br><br>
    
    Nach der Gerätedefinition ist die Grundeinstellung "Login in das DSM", d.h. es können Credentials mit Admin-Berechtigungen genutzt werden um zunächst alle <br>
    Funktionen der Kameras testen zu können. Danach können die Credentials z.B. in Abhängigkeit der benötigten Funktionen auf eine SVS-Session mit entsprechend beschränkten Privilegienprofil umgestellt werden. <br><br>
    
    Die nachfolgende Aufstellung zeigt die Mindestanforderungen der jeweiligen Modulfunktionen an die Nutzerrechte. <br><br>
    <ul>
      <table>
      <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td><li>set ... on                 </td><td> session: ServeillanceStation - Betrachter mit erweiterten Privileg "manuelle Aufnahme" </li></td></tr>
      <tr><td><li>set ... off                </td><td> session: ServeillanceStation - Betrachter mit erweiterten Privileg "manuelle Aufnahme" </li></td></tr>
      <tr><td><li>set ... snap               </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      <tr><td><li>set ... disable            </td><td> session: ServeillanceStation - Manager       </li></td></tr>
      <tr><td><li>set ... enable             </td><td> session: ServeillanceStation - Manager       </li></td></tr>
      <tr><td><li>set ... credentials        </td><td> -                                            </li></td></tr>
      <tr><td><li>get ... caminfoall         </td><td> session: ServeillanceStation - Betrachter    </li></td></tr>
      </table>
    </ul>
      <br><br>
    
    
    
    <b>HTTP-Timeout setzen</b><br><br>
    Alle Funktionen dieses Moduls verwenden HTTP-Aufrufe gegenüber der SVS Web API. <br>
    Der Standardwert für den HTTP-Timeout beträgt 4 Sekunden. Durch Setzen des <a href="#SSCamattr">Attributes</a> "httptimeout" > 0 kann dieser Wert bei Bedarf entsprechend den technischen Gegebenheiten angepasst werden. <br>
     
    
  </ul>
  <br><br><br>
  
<a name="SSCamset"></a>
<b>Set </b>
<ul>
    
    Es gibt zur Zeit folgende Optionen für "Set &lt;name&gt; ...": <br><br>

  <table>
  <colgroup> <col width=30%> <col width=70%> </colgroup>
      <tr><td>"on [rectime]":                        </td><td>startet eine Aufnahme. Die Aufnahme wird automatisch nach Ablauf der Zeit [rectime] gestoppt.</td></tr>
      <tr><td>                                       </td><td>Mit rectime = 0 wird eine Daueraufnahme gestartet die durch "set &lt;name&gt; off" wieder gestoppt werden muß.</td></tr>
      <tr><td>"off" :                                </td><td>stoppt eine laufende Aufnahme manuell oder durch die Nutzung anderer Events (z.B. über at, notify)</td></tr>
      <tr><td>"snap":                                </td><td>löst einen Schnappschuß der entsprechenden Kamera aus und speichert ihn in der Synology Surveillance Station</td></tr>
      <tr><td>"disable":                             </td><td>deaktiviert eine Kamera in der Synology Surveillance Station</td></tr>
      <tr><td>"enable":                              </td><td>aktiviert eine Kamera in der Synology Surveillance Station</td></tr>
      <tr><td>"credentials &lt;username&gt; &lt;password&gt;":   </td><td>speichert die Zugangsinformationen</td></tr>
  </table>
  <br><br>
        
  Beispiele für einfachen <b>Start/Stop einer Aufnahme</b>: <br><br>

  <table>
  <colgroup> <col width=20%> <col width=80%> </colgroup>
      <tr><td>set &lt;name&gt; on [rectime]  </td><td>startet die Aufnahme der Kamera &lt;name&gt;, automatischer Stop der Aufnahme nach Ablauf der Zeit [rectime] (default 15s oder wie im <a href="#SSCamattr">Attribut</a> "rectime" angegeben)</td></tr>
      <tr><td>set &lt;name&gt; off   </td><td>stoppt die Aufnahme der Kamera &lt;name&gt;</td></tr>
  </table>
  <br>

  Ein <b>Schnappschuß</b> kann ausgelöst werden mit:
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

<a name="SSCamget"></a>
<b>Get</b>
 <ul>
  Mit SSCam können die Eigenschaften der Kameras aus der Surveillance Station abgefragt werden. Dazu steht der Befehl zur Verfügung:
  <pre>
      get &lt;name&gt; caminfoall
  </pre>
  
  Abhängig von der Art der Kamera (z.B. Fix- oder PTZ-Kamera) werden die verfügbaren Eigenschaften ermittelt und als Readings zur Verfügung gestellt. <br>
  So wird zum Beispiel das Reading "Availability" auf "disconnected" gesetzt falls die Kamera von der Surveillance Station getrennt wird und kann für weitere <br>
  Verarbeitungen genutzt werden. <br><br>

  <b>Polling der Kameraeigenschaften:</b><br><br>

  Die Abfrage der Kameraeigenschaften erfolgt automatisch, wenn das Attribut "pollcaminfoall" (siehe Attribute) mit einem Wert &gt; 10 gesetzt wird. <br>
  Per Default ist das Attribut "pollcaminfoall" nicht gesetzt und das automatische Polling nicht aktiv. <br>
  Der Wert dieses Attributes legt das Intervall der Abfrage in Sekunden fest. Ist das Attribut nicht gesetzt oder &lt; 10 wird kein automatisches Polling <br>
  gestartet bzw. gestoppt wenn vorher der Wert &gt; 10 gesetzt war. <br><br>

  Das Attribut "pollcaminfoall" wird durch einen Watchdog-Timer überwacht. Änderungen des Attributwertes werden alle 90 Sekunden ausgewertet und entsprechend umgesetzt. <br>
  Eine Änderung des Pollingstatus / Pollingintervalls wird im FHEM-Logfile protokolliert. Diese Protokollierung kann durch Setzen des Attributes "pollnologging=1" abgeschaltet werden.<br>
  Dadurch kann ein unnötiges Anwachsen des Logs vermieden werden. Ab verbose=4 wird allerdings trotz gesetzten "pollnologging"-Attribut ein Log des Pollings <br>
  zu Analysezwecken aktiviert. <br><br>

  Wird FHEM neu gestartet, wird bei aktivierten Polling der ersten Datenabruf innerhalb 60s nach dem Start ausgeführt. <br><br>

  Der Status des automatischen Pollings wird durch das Reading "PollState" signalisiert: <br><br>
  
  <ul>
    <li><b> PollState = Active </b>    -    automatisches Polling wird mit Intervall entsprechend "pollcaminfoall" ausgeführt </li>
    <li><b> PollState = Inactive </b>  -    automatisches Polling wird nicht ausgeführt </li>
  </ul>
  <br>
 
  Die Bedeutung der Readingwerte ist unter <a href="#SSCamreadings">Readings</a> beschrieben. <br><br>

  <b>Hinweise:</b> <br><br>

  Wird Polling eingesetzt, sollte das Intervall nur so kurz wie benötigt eingestellt werden da die ermittelten Werte überwiegend statisch sind. <br>
  Das eingestellte Intervall sollte nicht kleiner sein als die Summe aller HTTP-Verarbeitungszeiten.
  Pro Pollingaufruf und Kamera werden ca. 10 - 20 Http-Calls gegen die Surveillance Station abgesetzt.<br><br>
  Bei einem eingestellten HTTP-Timeout (siehe <a href="#SSCamattr">Attribut</a>) "httptimeout") von 4 Sekunden kann die theoretische Verarbeitungszeit nicht höher als 80 Sekunden betragen. <br>
  In dem Beispiel sollte man das Pollingintervall mit einem Sicherheitszuschlag auf nicht weniger 160 Sekunden setzen. <br>
  Ein praktikabler Richtwert könnte zwischen 600 - 1800 (s) liegen. <br>

  Sind mehrere Kameras in SSCam definiert, sollte "pollcaminfoall" nicht bei allen Kameras auf exakt den gleichen Wert gesetzt werden um Verarbeitungsengpässe <br>
  und dadurch versursachte potentielle Fehlerquellen bei der Abfrage der Synology Surveillance Station zu vermeiden. <br>
  Ein geringfügiger Unterschied zwischen den Pollingintervallen der definierten Kameras von z.B. 1s kann bereits als ausreichend angesehen werden. <br><br> 
</ul>

<a name="SSCaminternals"></a>
<b>Internals</b> <br>
 <ul>
 Die Bedeutung der verwendeten Internals stellt die nachfolgende Liste dar: <br><br>
  <ul>
  <li><b>CAMID</b> - die ID der Kamera in der SVS, der Wert wird automatisch anhand des SVS-Kameranamens ermittelt. </li>
  <li><b>CAMNAME</b> - der Name der Kamera in der SVS </li>
  <li><b>CREDENTIALS</b> - der Wert ist "Set" wenn die Credentials gesetzt wurden </li>
  <li><b>NAME</b> - der Kameraname in FHEM </li>
  <li><b>OPMODE</b> - die zuletzt ausgeführte Operation des Moduls </li> 
  <li><b>SERVERADDR</b> - IP-Adresse des SVS Hostes </li>
  <li><b>SERVERPORT</b> - der SVS-Port </li>
  
  <br><br>
  </ul>
 </ul>


<a name="SSCamreadings"></a>
<b>Readings</b>
 <ul>
  <br>
  Über den Pollingmechanismus bzw. durch Abfrage mit "Get" werden Readings bereitgestellt, deren Bedeutung in der nachfolgenden Tabelle dargestellt sind. <br>
  Die übermittelten Readings können in Abhängigkeit des Kameratyps variieren.<br><br>
  <ul>
  <table>  
  <colgroup> <col width=5%> <col width=95%> </colgroup>
    <tr><td><li>Availability</li>       </td><td>- Verfügbarkeit der Kamera (disabled, enabled, disconnected, other)  </td></tr>
    <tr><td><li>CamIP</li>              </td><td>- IP-Adresse der Kamera  </td></tr>
    <tr><td><li>CamLiveMode</li>        </td><td>- Quelle für Live-Ansicht (DS, Camera)  </td></tr>
    <tr><td><li>CamPort</li>            </td><td>- IP-Port der Kamera  </td></tr>
    <tr><td><li>CamRecShare</li>        </td><td>- gemeinsamer Ordner auf der DS für Aufnahmen  </td></tr>
    <tr><td><li>CamRecVolume</li>       </td><td>- Volume auf der DS für Aufnahmen  </td></tr>
    <tr><td><li>CapAudioOut</li>        </td><td>- Fähigkeit der Kamera zur Audioausgabe über Surveillance Station (false/true)  </td></tr>
    <tr><td><li>CapChangeSpeed</li>     </td><td>- Fähigkeit der Kamera verschiedene Bewegungsgeschwindigkeiten auszuführen  </td></tr>
    <tr><td><li>CapPTZAbs</li>          </td><td>- Fähigkeit der Kamera für absolute PTZ-Aktionen   </td></tr>
    <tr><td><li>CapPTZAutoFocus</li>    </td><td>- Fähigkeit der Kamera für Autofokus Aktionen  </td></tr>
    <tr><td><li>CapPTZDirections</li>   </td><td>- die verfügbaren PTZ-Richtungen der Kamera  </td></tr>
    <tr><td><li>CapPTZFocus</li>        </td><td>- Art der Kameraunterstützung für Fokussierung  </td></tr>
    <tr><td><li>CapPTZHome</li>         </td><td>- Unterstützung der Kamera für Home-Position  </td></tr>
    <tr><td><li>CapPTZIris</li>         </td><td>- Unterstützung der Kamera für Iris-Aktion  </td></tr>
    <tr><td><li>CapPTZPan</li>          </td><td>- Unterstützung der Kamera für Pan-Aktion  </td></tr>
    <tr><td><li>CapPTZTilt</li>         </td><td>- Unterstützung der Kamera für Tilt-Aktion  </td></tr>
    <tr><td><li>CapPTZZoom</li>         </td><td>- Unterstützung der Kamera für Zoom-Aktion  </td></tr>
    <tr><td><li>DeviceType</li>         </td><td>- Kameratyp (Camera, Video_Server, PTZ, Fisheye)  </td></tr>
    <tr><td><li>Error</li>              </td><td>- Meldungstext des letzten Fehlers  </td></tr>
    <tr><td><li>Errorcode</li>          </td><td>- Fehlercode des letzten Fehlers   </td></tr>
    <tr><td><li>LastUpdateTime</li>     </td><td>- Datum / Zeit der letzten Aktualisierung der Kamera in der Surrveillance Station  </td></tr>   
    <tr><td><li>Patrols</li>            </td><td>- in Surveillance Station voreingestellte Überwachungstouren (bei PTZ-Kameras)  </td></tr>
    <tr><td><li>PollState</li>          </td><td>- zeigt den Status des automatischen Pollings an  </td></tr>    
    <tr><td><li>Presets</li>            </td><td>- in Surveillance Station voreingestellte Positionen (bei PTZ-Kameras)  </td></tr>
    <tr><td><li>Record</li>             </td><td>- Aufnahme läuft = Start, keine Aufnahme = Stop  </td></tr>   
    <tr><td><li>UsedSpaceMB</li>        </td><td>- durch Aufnahmen der Kamera belegter Plattenplatz auf dem Volume  </td></tr>
  </table>
  </ul>
  <br><br>    
  
 </ul>


<a name="SSCamattr"></a>
<b>Attribute</b>
  <br><br>
  <ul>
  <ul>
  <li><b>httptimeout</b> - Timeout-Wert für HTTP-Aufrufe zur Synology Surveillance Station, Default: 4 Sekunden (wenn httptimeout = "0" oder nicht gesetzt) </li>
  
  <li><b>pollcaminfoall</b> - Intervall der automatischen Eigenschaftsabfrage (Polling) einer Kamera (kleiner 10: kein Polling, größer 10: Polling mit Intervall) </li>

  <li><b>pollnologging</b> - "0" bzw. nicht gesetzt = Logging Gerätepolling aktiv (default), "1" = Logging Gerätepolling inaktiv </li>
  
  <li><b>rectime</b> - festgelegte Aufnahmezeit wenn eine Aufnahme gestartet wird. Mit rectime = 0 wird eine Endlosaufnahme gestartet. Ist "rectime" nicht gesetzt, wird der Defaultwert von 15s verwendet.</li>

  <li><b>session</b>  - Auswahl der Login-Session. Nicht gesetzt oder "DSM" -> session wird mit DSM aufgebaut (Standard). "SurveillanceStation" -> Session-Aufbau erfolgt mit SVS </li><br>
  
  <li><b>verbose</b> </li><br>
  
  <ul>
   Es werden verschiedene Verbose-Level unterstützt.
   Dies sind im Einzelnen:
   
    <table>  
    <colgroup> <col width=5%> <col width=95%> </colgroup>
      <tr><td> 0  </td><td>- Start/Stop-Ereignisse werden geloggt </td></tr>
      <tr><td> 1  </td><td>- Fehlermeldungen werden geloggt </td></tr>
      <tr><td> 2  </td><td>- Meldungen über wichtige Ereignisse oder Alarme </td></tr>
      <tr><td> 3  </td><td>- gesendete Kommandos werden geloggt </td></tr>
      <tr><td> 4  </td><td>- gesendete und empfangene Daten werden geloggt </td></tr>
      <tr><td> 5  </td><td>- alle Ausgaben zur Fehleranalyse werden geloggt. <b>ACHTUNG:</b> möglicherweise werden sehr viele Daten in das Logfile geschrieben! </td></tr>
    </table>
   </ul>     
   <br><br>
  
   <b>weitere Attribute:</b><br><br>
   
   <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>  
  </ul>
  <br><br>
</ul>

=end html_DE
=cut

