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

# use lib qw(/opt/fhem/FHEM);                                             # für Syntaxcheck mit: perl -c /opt/fhem/lib/FHEM/SynoModules/SMUtils.pm
use GPUtils qw( GP_Import GP_Export ); 
use Carp qw(croak carp);

use version; our $VERSION = version->declare('1.2.0');

use Exporter ('import');
our @EXPORT_OK   = qw(
                       getClHash 
                       trim
                       sortVersion
                       setVersionInfo
                       jboolmap
                       setCredentials
                       getCredentials
                       evaljson
                     );
                     
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import( 
      qw(
          AttrVal
          Log3
          defs
          modules
          devspec2array
          setKeyValue
          getKeyValue
          readingsBeginUpdate
          readingsBulkUpdate
          readingsEndUpdate
        )
  );  
};

###############################################################################
# Clienthash übernehmen oder zusammenstellen
# Identifikation ob über FHEMWEB ausgelöst oder nicht -> erstellen $hash->CL
###############################################################################
sub getClHash {      
  my $hash  = shift // carp "got no hash value !" && return;
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
      for (@webdvs) {
          $outdev = $_;
          next if(!$defs{$outdev});
          $hash->{HELPER}{CL}{$i}->{NAME} = $defs{$outdev}{NAME};
          $hash->{HELPER}{CL}{$i}->{NR}   = $defs{$outdev}{NR};
          $hash->{HELPER}{CL}{$i}->{COMP} = 1;
          $i++;               
      }
      
  } else {                                                          # übergebenen CL-Hash in Helper eintragen
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
  
  } else {
      Log3 ($name, 2, "$name - Clienthash was neither delivered nor created !");
      $ret = "Clienthash was neither delivered nor created. Can't use asynchronous output for function.";
  }
  
return $ret;
}

###############################################################################
#             Leerzeichen am Anfang / Ende eines strings entfernen           
###############################################################################
sub trim {
  my $str = shift;
  $str    =~ s/^\s+|\s+$//gx;

return $str;
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
#                          Versionierungen des Moduls setzen
#                  Die Verwendung von Meta.pm und Packages wird berücksichtigt
#############################################################################################
sub setVersionInfo {
  my $hash  = shift  // carp "got no hash value !"         && return;
  my $notes = shift  // carp "got no vNotesIntern value !" && return;
  my $name  = $hash->{NAME};

  my $v                    = (sortVersion("desc",keys %{$notes}))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;
  
  $hash->{HELPER}{VERSION_API}     = FHEM::SynoModules::API->VERSION()     // "unused";
  $hash->{HELPER}{VERSION_SMUtils} = FHEM::SynoModules::SMUtils->VERSION() // "unused";
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {          # META-Daten sind vorhanden
      $modules{$type}{META}{version} = "v".$v;                                           # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{<TYPE>}{META}}
      
      if($modules{$type}{META}{x_version}) {                                             # {x_version} ( nur gesetzt wenn $Id$ im Kopf komplett! vorhanden )
          $modules{$type}{META}{x_version} =~ s/1\.1\.1/$v/gx;
      } else {
          $modules{$type}{META}{x_version} = $v; 
      }
      return $@ unless (FHEM::Meta::SetInternals($hash));                                # FVERSION wird gesetzt ( nur gesetzt wenn $Id$ im Kopf komplett! vorhanden )
      
      if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {                         # es wird mit Packages gearbeitet -> mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
          use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );          ## no critic 'VERSION Reused'                                      
      }
  
  } else {                                                                               # herkömmliche Modulstruktur
      $hash->{VERSION} = $v;
  }
  
return;
}

###############################################################################
#                       JSON Boolean Test und Mapping
###############################################################################
sub jboolmap { 
  my $bool = shift // carp "got no value to check if bool !" && return;
  
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
    my $hash = shift // carp "got no hash value !"       && return;
    my $ao   = shift // carp "got no credentials type !" && return;
    my $user = shift // carp "got no user name !"        && return;
    my $pass = shift // carp "got no password !"         && return;
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
    
    } else {
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
    my $hash = shift // carp "got no hash value !"       && return;
    my $boot = shift;
    my $ao   = shift // carp "got no credentials type !" && return;
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
    
    } else {                                                                # boot = 0 -> Credentials aus RAM lesen, decoden und zurückgeben
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
        
        } else {
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
  my $hash    = shift // carp "got no hash value !"           && return;
  my $myjson  = shift // carp "got no string for JSON test !" && return;
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
      
      } else {
          $success = 0;

          readingsBeginUpdate ($hash);
          readingsBulkUpdate  ($hash, "Errorcode", "none");
          readingsBulkUpdate  ($hash, "Error",     "malformed JSON string received");
          readingsEndUpdate   ($hash, 1);  
      }
  };
  
return ($success,$myjson);
}

1;