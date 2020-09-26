########################################################################################################################
# $Id$
#########################################################################################################################
#       SMUtils.pm
#
#       (c) 2020 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This Module provides routines for FHEM modules developed for Synology use cases.
# 
#       This script is part of fhem.
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
#       along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#########################################################################################################################

package FHEM::SynoModules::SMUtils;                                          

use strict;           
use warnings;
use utf8;
use MIME::Base64;
eval "use JSON;1;" or my $nojsonmod = 1;                                  ## no critic 'eval'
use Data::Dumper;

# use lib qw(/opt/fhem/FHEM  /opt/fhem/lib);                              # für Syntaxcheck mit: perl -c /opt/fhem/lib/FHEM/SynoModules/SMUtils.pm

use FHEM::SynoModules::ErrCodes qw(:all);                                 # Error Code Modul
use GPUtils qw( GP_Import GP_Export ); 
use Carp qw(croak carp);

use version; our $VERSION = version->declare('1.10.0');

use Exporter ('import');
our @EXPORT_OK = qw(
                     getClHash
                     delClHash
                     trim
                     moduleVersion
                     sortVersion
                     showModuleInfo
                     jboolmap
                     setCredentials
                     getCredentials
                     evaljson
                     login
                     logout
                     setActiveToken
                     delActiveToken
                     delCallParts
					 setReadingErrorNone
					 setReadingErrorState
                     addSendqueueEntry
                     listSendqueue
                     purgeSendqueue
                     updQueueLength
                   );
                     
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import( 
      qw(
          AttrVal
          Log3
          data
          defs
          modules
          CancelDelayedShutdown
          devspec2array
          FmtDateTime
          setKeyValue
          getKeyValue
          readingsSingleUpdate
          readingsBeginUpdate
          readingsBulkUpdate
		  readingsBulkUpdateIfChanged
          readingsEndUpdate
          HttpUtils_NonblockingGet
        )
  );  
};

# Standardvariablen
my $carpnohash = "got no hash value";
my $carpnoname = "got no name value";
my $carpnoctyp = "got no credentials type";
my $carpnoapir = "got no API reference";

###############################################################################
# Clienthash übernehmen oder zusammenstellen
# Identifikation ob über FHEMWEB ausgelöst oder nicht -> erstellen $hash->CL
###############################################################################
sub getClHash {      
  my $hash  = shift // carp $carpnohash && return;
  my $nobgd = shift;
  my $name  = $hash->{NAME};
  my $ret;
  
  if($nobgd) {                                                      # nur übergebenen CL-Hash speichern, keine Hintergrundverarbeitung bzw. synthetische Erstellung CL-Hash
      $hash->{HELPER}{CL}{1} = $hash->{CL};
      return;
  }

  if (!defined($hash->{CL})) {                                      # Clienthash wurde nicht übergeben und wird erstellt (FHEMWEB Instanzen mit canAsyncOutput=1 analysiert)
      my $outdev;
      my @webdvs = devspec2array("TYPE=FHEMWEB:FILTER=canAsyncOutput=1:FILTER=STATE=Connected");
      my $i = 1;
      
      for my $outdev (@webdvs) {
          next if(!$defs{$outdev});
          $hash->{HELPER}{CL}{$i}->{NAME} = $defs{$outdev}{NAME};
          $hash->{HELPER}{CL}{$i}->{NR}   = $defs{$outdev}{NR};
          $hash->{HELPER}{CL}{$i}->{COMP} = 1;
          $i++;               
      }   
  } 
  else {                                                            # übergebenen CL-Hash in Helper eintragen
      $hash->{HELPER}{CL}{1} = $hash->{CL};
  }
      
  if (defined($hash->{HELPER}{CL}{1})) {                            # Clienthash auflösen zur Fehlersuche (aufrufende FHEMWEB Instanz)
      for (my $k=1; (defined($hash->{HELPER}{CL}{$k})); $k++ ) {
          Log3 ($name, 4, "$name - Clienthash number: $k");
          while (my ($key,$val) = each(%{$hash->{HELPER}{CL}{$k}})) {
              $val = $val // q{};
              Log3 ($name, 4, "$name - Clienthash: $key -> $val");
          }
      }
  } 
  else {
      Log3 ($name, 2, "$name - Clienthash was neither delivered nor created !");
      $ret = "Clienthash was neither delivered nor created. Can't use asynchronous output for function.";
  }
  
return $ret;
}

####################################################################################
#                            Clienthash löschen
####################################################################################
sub delClHash {
  my $name = shift;
  my $hash = $defs{$name};
  
  delete($hash->{HELPER}{CL});
  
return;
}

###############################################################################
#             Leerzeichen am Anfang / Ende eines strings entfernen           
###############################################################################
sub trim {
  my $str = shift;
  $str    =~ s/^\s+|\s+$//gx;

return $str;
}

#############################################################################################
#     liefert die Versionierung des Moduls zurück
#     Verwendung mit Packages:  use version 0.77; our $VERSION = moduleVersion ($params)
#     Verwendung ohne Packages: moduleVersion ($params)
#  
#     Die Verwendung von Meta.pm und Packages wird berücksichtigt
#
#     Variablen $useAPI, $useSMUtils, $useErrCodes enthalten die Versionen von SynoModules
#     wenn verwendet und sind in diesem Fall zu übergeben. 
#############################################################################################
sub moduleVersion {
  my $paref       = shift; 
  my $hash        = $paref->{hash}      // carp $carpnohash                          && return; 
  my $notes       = $paref->{notes}     // carp "got no reference of a version hash" && return;
  my $useAPI      = $paref->{useAPI};
  my $useSMUtils  = $paref->{useSMUtils};
  my $useErrCodes = $paref->{useErrCodes}; 

  my $type        = $hash->{TYPE};
  my $package     = (caller)[0];                                                         # das PACKAGE des aufrufenden Moduls          
  
  $hash->{HELPER}{VERSION_API}      = $useAPI      ? FHEM::SynoModules::API->VERSION()      : "unused";
  $hash->{HELPER}{VERSION_SMUtils}  = $useSMUtils  ? FHEM::SynoModules::SMUtils->VERSION()  : "unused";
  $hash->{HELPER}{VERSION_ErrCodes} = $useErrCodes ? FHEM::SynoModules::ErrCodes->VERSION() : "unused";

  my $v                    = (sortVersion("desc",keys %{$notes}))[0];                    # die Modulversion aus Versionshash selektieren
  $hash->{HELPER}{VERSION} = $v;
  $hash->{HELPER}{PACKAGE} = $package;
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {          # META-Daten sind vorhanden
      $modules{$type}{META}{version} = "v".$v;                                           # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{<TYPE>}{META}}
      
      if($modules{$type}{META}{x_version}) {                                             # {x_version} nur gesetzt wenn $Id$ im Kopf komplett! vorhanden
          $modules{$type}{META}{x_version} =~ s/1\.1\.1/$v/gx;
      } 
      else {
          $modules{$type}{META}{x_version} = $v; 
      }
      
      FHEM::Meta::SetInternals($hash);                                                   # FVERSION wird gesetzt ( nur gesetzt wenn $Id$ im Kopf komplett! vorhanden )
  } 
  else {                                                                                 # herkömmliche Modulstruktur
      $hash->{VERSION} = $v;                                                             # Internal VERSION setzen
  }
  
  if($package =~ /FHEM::$type/x || $package eq $type) {                                  # es wird mit Packages gearbeitet -> mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
      return $v;         
  }
  
return;
}

################################################################
# sortiert eine Liste von Versionsnummern x.x.x
# Schwartzian Transform and the GRT transform
# Übergabe: "asc | desc",<Liste von Versionsnummern>
################################################################
sub sortVersion {
  my ($sseq,@versions) = @_;

  my @sorted = map {$_->[0]}
               sort {$a->[1] cmp $b->[1]}
               map {[$_, pack "C*", split /\./x]} @versions;
             
  @sorted = map {join ".", unpack "C*", $_}
            sort
            map {pack "C*", split /\./x} @versions;
  
  if($sseq eq "desc") {
      @sorted = reverse @sorted;
  }
  
return @sorted;
}

#############################################################################################
#                 gibt die angeforderten Hinweise / Release Notes als 
#                 HTML-Tabelle zurück
#############################################################################################
sub showModuleInfo {                 
  my $paref        = shift;
  my $arg          = $paref->{arg};
  my $vHintsExt_de = $paref->{hintextde};                       # Referenz zum deutschen Hinweis-Hash
  my $vHintsExt_en = $paref->{hintexten};                       # Referenz zum englischen Hinweis-Hash
  my $vNotesExtern = $paref->{notesext};                        # Referenz zum Hash der Modul Release Notes
   
  my $header  = "<b>Module release information</b><br>";
  my $header1 = "<b>Helpful hints</b><br>";
  my $ret     = "";
  
  my (%hs,$val0,$val1,$i);
  
  $ret = "<html>";
  
  # Hints
  if(!$arg || $arg =~ /hints/x || $arg =~ /[\d]+/x) {
      $ret .= sprintf("<div class=\"makeTable wide\"; style=\"text-align:left\">$header1 <br>");
      $ret .= "<table class=\"block wide internals\">";
      $ret .= "<tbody>";
      $ret .= "<tr class=\"even\">";  
      
      if($arg && $arg =~ /[\d]+/x) {
          my @hints = split ",", $arg;
          
          for my $hint (@hints) {
              if(AttrVal("global","language","EN") eq "DE") {
                  $hs{$hint} = $vHintsExt_de->{$hint};
              } 
              else {
                  $hs{$hint} = $vHintsExt_en->{$hint};
              }
          }                      
      } 
      else {
          if(AttrVal("global","language","EN") eq "DE") {
              %hs = %{$vHintsExt_de};
          } 
          else {
              %hs = %{$vHintsExt_en}; 
          }
      }          
      
      $i = 0;
      for my $key (sortVersion("desc",keys %hs)) {
          $val0 = $hs{$key};
          $ret .= sprintf("<td style=\"vertical-align:top\"><b>$key</b>  </td><td style=\"vertical-align:top\">$val0</td>" );
          $ret .= "</tr>";
          $i++;
          
          if ($i & 1) {                                         # $i ist ungerade
              $ret .= "<tr class=\"odd\">";
          } 
          else {
              $ret .= "<tr class=\"even\">";
          }
      }
      $ret .= "</tr>";
      $ret .= "</tbody>";
      $ret .= "</table>";
      $ret .= "</div>";
  }
  
  # Notes
  if(!$arg || $arg =~ /rel/x) {
      $ret .= sprintf("<div class=\"makeTable wide\"; style=\"text-align:left\">$header <br>");
      $ret .= "<table class=\"block wide internals\">";
      $ret .= "<tbody>";
      $ret .= "<tr class=\"even\">";
      
      $i = 0;
      for my $key (sortVersion("desc", keys %{$vNotesExtern})) {
          ($val0,$val1) = split /\s/x, $vNotesExtern->{$key}, 2;
          $ret .= sprintf("<td style=\"vertical-align:top\"><b>$key</b>  </td><td style=\"vertical-align:top\">$val0  </td><td>$val1</td>" );
          $ret .= "</tr>";
          $i++;
          
          if ($i & 1) {                                       # $i ist ungerade
              $ret .= "<tr class=\"odd\">";
          } 
          else {
              $ret .= "<tr class=\"even\">";
          }
      }
      
      $ret .= "</tr>";
      $ret .= "</tbody>";
      $ret .= "</table>";
      $ret .= "</div>";
  }
  
  $ret .= "</html>";
                    
return $ret;
}

###############################################################################
#                       JSON Boolean Test und Mapping
###############################################################################
sub jboolmap { 
  my $bool = shift // carp "got no value to check if bool" && return;
  
  my $is_boolean = JSON::is_bool($bool);
  
  if($is_boolean) {
      $bool = $bool ? "true" : "false";
  }
  
return $bool;
}

######################################################################################
#                            Username / Paßwort speichern
#   $ao = "credentials"     -> Standard Credentials
#   $ao = "SMTPcredentials" -> Credentials für Mailversand
######################################################################################
sub setCredentials {
    my $hash = shift // carp $carpnohash        && return;
    my $ao   = shift // carp $carpnoctyp        && return;
    my $user = shift // carp "got no user name" && return;
    my $pass = shift // carp "got no password"  && return;
    my $name = $hash->{NAME};
    
    my $success;
    
    my $credstr = encode_base64 ("$user:$pass");
    
    # Beginn Scramble-Routine
    my @key = qw(1 3 4 5 6 3 2 1 9);
    my $len = scalar @key;  
    my $i   = 0;  
    $credstr = join "", map { $i = ($i + 1) % $len; chr((ord($_) + $key[$i]) % 256) } split //, $credstr;   ## no critic 'Map blocks';
    # End Scramble-Routine    
       
    my $index   = $hash->{TYPE}."_".$hash->{NAME}."_".$ao;
    my $retcode = setKeyValue($index, $credstr);
    
    if ($retcode) { 
        Log3($name, 2, "$name - Error while saving the Credentials - $retcode");
        $success = 0;
    } 
    else {
        getCredentials($hash,1,$ao);                                                            # Credentials nach Speicherung lesen und in RAM laden ($boot=1), $ao = credentials oder SMTPcredentials
        $success = 1;
    }

return ($success);
}

######################################################################################
#                             Username / Paßwort abrufen
#   $ao = "credentials"     -> Standard Credentials
#   $ao = "SMTPcredentials" -> Credentials für Mailversand
######################################################################################
sub getCredentials {
    my $hash = shift // carp $carpnohash && return;
    my $boot = shift;
    my $ao   = shift // carp $carpnoctyp && return;
    my $name = $hash->{NAME};
    my ($success, $username, $passwd, $index, $retcode, $credstr);
    my (@key,$len,$i);
    
    my $pp;
    
    if ($boot) {                                                            # mit $boot=1 Credentials von Platte lesen und als scrambled-String in RAM legen
        $index               = $hash->{TYPE}."_".$hash->{NAME}."_".$ao;
        ($retcode, $credstr) = getKeyValue($index);
    
        if ($retcode) {
            Log3($name, 2, "$name - Unable to read password from file: $retcode");
            $success = 0;
        }  

        if ($credstr) {
            if($ao eq "credentials") {                                      # beim Boot scrambled Credentials in den RAM laden
                $hash->{HELPER}{CREDENTIALS} = $credstr;
                $hash->{CREDENTIALS}         = "Set";                       # "Credentials" wird als Statusbit ausgewertet. Wenn nicht gesetzt -> Warnmeldung und keine weitere Verarbeitung
                $success                     = 1;
            
            } elsif ($ao eq "SMTPcredentials") {                            # beim Boot scrambled Credentials in den RAM laden
                $hash->{HELPER}{SMTPCREDENTIALS} = $credstr;
                $hash->{SMTPCREDENTIALS}         = "Set";                   # "Credentials" wird als Statusbit ausgewertet. Wenn nicht gesetzt -> Warnmeldung und keine weitere Verarbeitung
                $success                         = 1;                
            }
        }
    } 
    else {                                                                  # boot = 0 -> Credentials aus RAM lesen, decoden und zurückgeben
        if ($ao eq "credentials") {
            $credstr = $hash->{HELPER}{CREDENTIALS};
            $pp      = q{};
        
        } elsif ($ao eq "SMTPcredentials") {
            $pp      = q{SMTP};
            $credstr = $hash->{HELPER}{SMTPCREDENTIALS};
        }
        
        if($credstr) {
            # Beginn Descramble-Routine
            @key = qw(1 3 4 5 6 3 2 1 9); 
            $len = scalar @key;  
            $i = 0;  
            $credstr = join "",  
            map { $i = ($i + 1) % $len; chr((ord($_) - $key[$i] + 256) % 256) } split //, $credstr;    ## no critic 'Map blocks';  
            # Ende Descramble-Routine
            
            ($username, $passwd) = split ":",decode_base64($credstr);
            
            my $logpw = AttrVal($name, "showPassInLog", 0) ? $passwd : "********";
        
            Log3($name, 4, "$name - ".$pp."Credentials read from RAM: $username $logpw");
        } 
        else {
            Log3($name, 2, "$name - ".$pp."Credentials not set in RAM !");
        }
    
        $success = (defined $passwd) ? 1 : 0;
    }

return ($success, $username, $passwd);        
}


###############################################################################
#                        Test ob JSON-String vorliegt
###############################################################################
sub evaljson { 
  my $hash    = shift // carp $carpnohash                   && return;
  my $myjson  = shift // carp "got no string for JSON test" && return;
  my $OpMode  = $hash->{OPMODE};
  my $name    = $hash->{NAME};
  
  my $success = 1;
  
  if($nojsonmod) {
      $success = 0;
      Log3($name, 1, "$name - ERROR: Perl module 'JSON' is missing. You need to install it.");
      return ($success,$myjson);
  }
  
  eval {decode_json($myjson)} or do {
      if( ($hash->{HELPER}{RUNVIEW} && $hash->{HELPER}{RUNVIEW} =~ m/^live_.*hls$/x) || 
              $OpMode =~ m/^.*_hls$/x ) {                                                    # SSCam: HLS aktivate/deaktivate bringt kein JSON wenn bereits aktiviert/deaktiviert
          Log3($name, 5, "$name - HLS-activation data return: $myjson");
          
          if ($myjson =~ m/{"success":true}/x) {
              $success = 1;
              $myjson  = '{"success":true}';    
          }
      } 
      else {
          $success = 0;

          readingsBeginUpdate ($hash);
          readingsBulkUpdate  ($hash, "Errorcode", "none");
          readingsBulkUpdate  ($hash, "Error",     "malformed JSON string received");
          readingsEndUpdate   ($hash, 1);  
      }
  };
  
return ($success,$myjson);
}

####################################################################################  
#         Login wenn keine oder ungültige Session-ID vorhanden ist
#         $apiref = Referenz zum API Hash
#         $fret   = Rückkehrfunktion nach erfolgreichen Login
####################################################################################
sub login {
  my $hash         = shift  // carp $carpnohash                        && return;
  my $apiref       = shift  // carp $carpnoapir                        && return;
  my $fret         = shift  // carp "got no return function reference" && return;
  my $name         = $hash->{NAME};
  my $serveraddr   = $hash->{SERVERADDR};
  my $serverport   = $hash->{SERVERPORT};
  my $apiauth      = $apiref->{AUTH}{NAME};
  my $apiauthpath  = $apiref->{AUTH}{PATH};
  my $apiauthver   = $apiref->{AUTH}{VER};
  my $proto        = $hash->{PROTOCOL};
  my $type         = $hash->{TYPE};

  my ($url,$param,$urlwopw);
  
  delete $hash->{HELPER}{SID};
    
  Log3($name, 4, "$name - --- Begin Function login ---");
  
  my ($success, $username, $password) = getCredentials($hash,0,"credentials");                      # Credentials abrufen
  
  if (!$success) {
      Log3($name, 2, "$name - Credentials couldn't be retrieved successfully - make sure you've set it with \"set $name credentials <username> <password>\"");
      delActiveToken($hash) if($type eq "SSCam");      
      return;
  }
  
  my $lrt = AttrVal($name,"loginRetries",3);
  
  if($hash->{HELPER}{LOGINRETRIES} >= $lrt) {                                               # Max Versuche erreicht -> login wird abgebrochen, Freigabe Funktionstoken
      delActiveToken($hash) if($type eq "SSCam");  
      Log3($name, 2, "$name - ERROR - Login or privilege of user $username unsuccessful"); 
      return;
  }

  my $timeout     = AttrVal($name,"timeout",60);                                            # Kompatibilität zu Modulen die das Attr "timeout" verwenden
  my $httptimeout = AttrVal($name,"httptimeout",$timeout);
  $httptimeout    = 60 if($httptimeout < 60);
  Log3($name, 4, "$name - HTTP-Call login will be done with httptimeout-Value: $httptimeout s");                                                                             
  
  my $sid = AttrVal($name, "noQuotesForSID", 0) ? "sid" : qq{"sid"};                        # sid in Quotes einschliessen oder nicht -> bei Problemen mit 402 - Permission denied
  
  if (AttrVal($name,"session","DSM") eq "DSM") {
      $url     = "$proto://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthver&method=Login&account=$username&passwd=$password&format=$sid"; 
      $urlwopw = "$proto://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthver&method=Login&account=$username&passwd=*****&format=$sid";
  } 
  else {
      $url     = "$proto://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthver&method=Login&account=$username&passwd=$password&session=SurveillanceStation&format=$sid";
      $urlwopw = "$proto://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthver&method=Login&account=$username&passwd=*****&session=SurveillanceStation&format=$sid";
  }
  
  my $printurl = AttrVal($name, "showPassInLog", 0) ? $url : $urlwopw;
  
  Log3($name, 4, "$name - Call-Out now: $printurl");
  $hash->{HELPER}{LOGINRETRIES}++;
  
  $param = {
      url      => $url,
      timeout  => $httptimeout,
      hash     => $hash,
      user     => $username,
      funcret  => $fret,
	  apiref   => $apiref,
      method   => "GET",
      header   => "Accept: application/json",
      callback => \&loginReturn
  };
  
  HttpUtils_NonblockingGet ($param);
   
return;
}

sub loginReturn {
  my $param    = shift;
  my $err      = shift;
  my $myjson   = shift;
  my $hash     = $param->{hash};
  my $name     = $hash->{NAME};
  my $username = $param->{user};
  my $fret     = $param->{funcret};
  my $apiref   = $param->{apiref};
  my $type     = $hash->{TYPE};
  
  my $success; 

  if ($err ne "") {                                                                # ein Fehler bei der HTTP Abfrage ist aufgetreten
      Log3($name, 2, "$name - error while requesting ".$param->{url}." - $err");
        
      readingsSingleUpdate($hash, "Error", $err, 1);                               
        
      return login($hash,$apiref,$fret);
   
   } elsif ($myjson ne "") {                                                       # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)   
        ($success) = evaljson($hash,$myjson);                                      # Evaluiere ob Daten im JSON-Format empfangen wurden
        if (!$success) {
            Log3($name, 4, "$name - no JSON-Data returned: ".$myjson);
            delActiveToken($hash) if($type eq "SSCam");
            return;
        }
        
        my $data = decode_json($myjson);
        
        Log3($name, 5, "$name - JSON decoded: ". Dumper $data);
   
        $success = $data->{'success'};
        
        if ($success) {                                                            # login war erfolgreich     
            my $sid = $data->{'data'}->{'sid'};
             
            $hash->{HELPER}{SID} = $sid;                                           # Session ID in hash eintragen
       
            readingsBeginUpdate ($hash);
            readingsBulkUpdate  ($hash,"Errorcode","none");
            readingsBulkUpdate  ($hash,"Error","none");
            readingsEndUpdate   ($hash, 1);
       
            Log3($name, 4, "$name - Login of User $username successful - SID: $sid");
            
            return &$fret($hash);
        } 
        else {          
            my $errorcode = $data->{'error'}->{'code'};                           # Errorcode aus JSON ermitteln
            my $error     = expErrorsAuth($hash,$errorcode);                      # Fehlertext zum Errorcode ermitteln

            readingsBeginUpdate ($hash);
            readingsBulkUpdate  ($hash,"Errorcode",$errorcode);
            readingsBulkUpdate  ($hash,"Error",$error);
            readingsEndUpdate   ($hash, 1);
       
            Log3($name, 3, "$name - Login of User $username unsuccessful. Code: $errorcode - $error - try again"); 
             
            return login($hash,$apiref,$fret);
       }
   }
   
return login($hash,$apiref,$fret);
}

###################################################################################  
#      Funktion logout
###################################################################################
sub logout {
   my $hash        = shift  // carp $carpnohash && return;
   my $apiref      = shift  // carp $carpnoapir && return;
   my $name        = $hash->{NAME};
   my $serveraddr  = $hash->{SERVERADDR};
   my $serverport  = $hash->{SERVERPORT};
   my $apiauth     = $apiref->{AUTH}{NAME};
   my $apiauthpath = $apiref->{AUTH}{PATH};
   my $apiauthver  = $apiref->{AUTH}{VER};
   my $sid         = $hash->{HELPER}{SID};
   my $proto       = $hash->{PROTOCOL};
   
   my $url;
     
   Log3($name, 4, "$name - --- Start Synology logout ---");
    
   my $httptimeout = AttrVal($name,"httptimeout",4);
   Log3($name, 5, "$name - HTTP-Call will be done with httptimeout-Value: $httptimeout s");
  
   if (AttrVal($name,"session","DSM") eq "DSM") {
       $url = "$proto://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthver&method=Logout&_sid=$sid";    
   } 
   else {
       $url = "$proto://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthver&method=Logout&session=SurveillanceStation&_sid=$sid";
   }

   my $param = {
       url      => $url,
       timeout  => $httptimeout,
       hash     => $hash,
       method   => "GET",
       header   => "Accept: application/json",
       callback => \&logoutReturn
   };
   
   HttpUtils_NonblockingGet ($param);

return;
}

sub logoutReturn {  
   my $param  = shift;
   my $err    = shift;
   my $myjson = shift;
   my $hash   = $param->{hash};
   my $name   = $hash->{NAME};
   my $sid    = $hash->{HELPER}{SID};
   my $type   = $hash->{TYPE};
   
   my ($success, $username) = getCredentials($hash,0,"credentials");
  
   if ($err ne "") {                                                                                          # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
       Log3($name, 2, "$name - error while requesting ".$param->{url}." - $err"); 
       readingsSingleUpdate($hash, "Error", $err, 1);                                             
   
   } elsif ($myjson ne "") {                                                                                  # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
       Log3($name, 4, "$name - URL-Call: ".$param->{url});
        
       ($success) = evaljson($hash,$myjson);                                                                  # Evaluiere ob Daten im JSON-Format empfangen wurden
        
       if (!$success) {
           Log3($name, 4, "$name - Data returned: ".$myjson);
           delActiveToken($hash) if($type eq "SSCam");
           return;
       }
        
       my $data = decode_json($myjson);
       
       Log3($name, 4, "$name - JSON returned: ". Dumper $data);                   
   
       $success = $data->{'success'};

       if ($success) {                                                                                        # die Logout-URL konnte erfolgreich aufgerufen werden                        
           Log3($name, 2, "$name - Session of User \"$username\" terminated - session ID \"$sid\" deleted");      
       } 
       else {
           my $errorcode = $data->{'error'}->{'code'};                                                        # Errorcode aus JSON ermitteln
           my $error     = expErrorsAuth($hash,$errorcode);                                                   # Fehlertext zum Errorcode ermitteln

           Log3($name, 2, "$name - ERROR - Logout of User $username was not successful, however SID: \"$sid\" has been deleted. Errorcode: $errorcode - $error");
       }
   }   
   
   delete $hash->{HELPER}{SID};                                                                               # Session-ID aus Helper-hash löschen
   
   delActiveToken($hash);                                                                                     # ausgeführte Funktion ist erledigt (auch wenn logout nicht erfolgreich), Freigabe Funktionstoken
   
   CancelDelayedShutdown($name);
   
return;
}

#############################################################################################
#                                   Token setzen
#############################################################################################
sub setActiveToken { 
   my $hash = shift // carp $carpnohash && return;
   my $name = $hash->{NAME};
               
   $hash->{HELPER}{ACTIVE} = "on";
   
   if (AttrVal($name,"debugactivetoken",0)) {
       Log3($name, 1, "$name - Active-Token set by OPMODE: $hash->{OPMODE}");
   } 
   
return;
} 

#############################################################################################
#                                   Token freigeben
#############################################################################################
sub delActiveToken { 
   my $hash = shift // carp $carpnohash && return;
   my $name = $hash->{NAME};
               
   $hash->{HELPER}{ACTIVE} = "off";
   
   delCallParts ($hash);
   
   if (AttrVal($name,"debugactivetoken",0)) {
       Log3($name, 1, "$name - Active-Token deleted by OPMODE: $hash->{OPMODE}");
   }  
   
return;
} 

#############################################################################################
#                     lösche Helper der erstellten CALL / ACALL Teile
#        CALL / ACALL werden bei auslösen einer Aktion durch Set/Get erstellt
#############################################################################################
sub delCallParts { 
   my $hash = shift;

   delete $hash->{HELPER}{CALL};
   delete $hash->{HELPER}{ACALL};
   
return;
}

#############################################################################################
#            Readings Error & Errorcode auf 
#            Standard "none" setzen
#            $evt: 1 -> Event, 0/nicht gesetzt -> kein Event
#############################################################################################
sub setReadingErrorNone {                     
  my $hash = shift // carp $carpnohash && return;
  my $evt  = shift;
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate ($hash, "Errorcode", "none");
  readingsBulkUpdate ($hash, "Error"    , "none");
  readingsEndUpdate  ($hash, $evt);

return;
}

####################################################################################
#       zentrale Funktion Error State in Readings setzen
#       $error   = Fehler als Text
#       $errcode = Fehlercode
####################################################################################
sub setReadingErrorState {                   
    my $hash    = shift // carp $carpnohash && return;
    my $error   = shift;
    my $errcode = shift // "none";
    
    readingsBeginUpdate         ($hash); 
    readingsBulkUpdateIfChanged ($hash, "Error",     $error);
    readingsBulkUpdateIfChanged ($hash, "Errorcode", $errcode);
    readingsBulkUpdate          ($hash, "state",     "Error");                    
    readingsEndUpdate           ($hash,1);

return;
}

#############################################################################################
#                        fügt den Eintrag $entry zur Sendequeue hinzu
#############################################################################################
sub addSendqueueEntry {                 
  my $hash  = shift // carp $carpnohash                             && return;
  my $entry = shift // carp "got no entry for adding to send queue" && return;
  my $name  = $hash->{NAME};
  
  my $type  = $hash->{TYPE};
    
  $data{$type}{$name}{sendqueue}{index}++;
  my $index = $data{$type}{$name}{sendqueue}{index};
    
  Log3($name, 5, "$name - Add Item to queue - Index $index: \n".Dumper $entry);
                      
  $data{$type}{$name}{sendqueue}{entries}{$index} = $entry;  

  updQueueLength ($hash);                                                       # update Länge der Sendequeue 
      
return;
}

#############################################################################################
#                       liefert aktuelle Einträge der Sendequeue zurück
#############################################################################################
sub listSendqueue {                 
  my $paref = shift;
  my $hash  = $paref->{hash} // carp $carpnohash && return; 
  my $name  = $paref->{name} // carp $carpnoname && return;
  
  my $type  = $hash->{TYPE};
  
  my $sub = sub { 
      my $idx = shift;
      my $ret;          
      for my $key (reverse sort keys %{$data{$type}{$name}{sendqueue}{entries}{$idx}}) {
          $ret .= ", " if($ret);
          $ret .= $key."=>".$data{$type}{$name}{sendqueue}{entries}{$idx}{$key};
      }
      return $ret;
  };
        
  if (!keys %{$data{$type}{$name}{sendqueue}{entries}}) {
      return qq{SendQueue is empty.};
  }
  
  my $sq;
  for my $idx (sort{$a<=>$b} keys %{$data{$type}{$name}{sendqueue}{entries}}) {
      $sq .= $idx." => ".$sub->($idx)."\n";             
  }
      
return $sq;
}

#############################################################################################
#                       löscht Einträge aus der Sendequeue
#############################################################################################
sub purgeSendqueue {                 
  my $paref = shift;
  my $hash  = $paref->{hash} // carp $carpnohash                      && return; 
  my $name  = $paref->{name} // carp $carpnoname                      && return;
  my $prop  = $paref->{prop} // carp "got no purgeSendqueue argument" && return;
  
  my $type  = $hash->{TYPE};
  
  if($prop eq "-all-") {
      delete $hash->{OPIDX};
      delete $data{$type}{$name}{sendqueue}{entries};
      $data{$type}{$name}{sendqueue}{index} = 0;
      return "All entries of SendQueue are deleted";
  } 
  elsif($prop eq "-permError-") {
      for my $idx (keys %{$data{$type}{$name}{sendqueue}{entries}}) { 
          delete $data{$type}{$name}{sendqueue}{entries}{$idx} 
              if($data{$type}{$name}{sendqueue}{entries}{$idx}{forbidSend});            
      }
      return qq{All entries with state "permanent send error" are deleted};
  } 
  else {
      delete $data{$type}{$name}{sendqueue}{entries}{$prop};
      return qq{SendQueue entry with index "$prop" deleted};
  }
      
return;
}

#############################################################################################
#                        Länge Senedequeue updaten          
#############################################################################################
sub updQueueLength {
  my $hash = shift // carp $carpnohash && return; 
  my $rst  = shift;
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $ql   = keys %{$data{$type}{$name}{sendqueue}{entries}};
  
  readingsBeginUpdate         ($hash);                                             
  readingsBulkUpdateIfChanged ($hash, "QueueLenth", $ql);                          # Länge Sendqueue updaten
  readingsEndUpdate           ($hash,1);
  
  my $head = "next planned SendQueue start:";
  
  if($rst) {                                                                       # resend Timer gesetzt
      $hash->{RESEND} = $head." ".FmtDateTime($rst);
  } 
  else {
      $hash->{RESEND} = $head." immediately by next entry";
  }

return;
}

1;