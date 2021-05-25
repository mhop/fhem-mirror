########################################################################################################################
# $Id$
#########################################################################################################################
#       SMUtils.pm
#
#       (c) 2020-2021 by Heiko Maaz
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

# Version History
# 1.23.0   new sub evalDecodeJSON
# 1.22.0   new sub addCHANGED
# 1.21.0   new sub timestringToTimestamp / createReadingsFromArray
# 1.20.7   change to defined ... in sub _addSendqueueSimple
# 1.20.6   delete $hash->{OPMODE} in checkSendRetry

package FHEM::SynoModules::SMUtils;                                          

use strict;           
use warnings;
use utf8;
use MIME::Base64;
use Time::HiRes qw(gettimeofday);
eval "use JSON;1;" or my $nojsonmod = 1;                                  ## no critic 'eval'
use Data::Dumper;
use Encode;

# use lib qw(/opt/fhem/FHEM  /opt/fhem/lib);                              # für Syntaxcheck mit: perl -c /opt/fhem/lib/FHEM/SynoModules/SMUtils.pm

use FHEM::SynoModules::ErrCodes qw(:all);                                 # Error Code Modul
use GPUtils qw( GP_Import GP_Export ); 
use Carp qw(croak carp);

use version; our $VERSION = version->declare('1.22.0');

use Exporter ('import');
our @EXPORT_OK = qw(
                     getClHash
                     delClHash
                     delReadings
                     createReadingsFromArray
                     addCHANGED
                     trim
                     slurpFile
                     moduleVersion
                     sortVersion
                     showModuleInfo
					 convertHashToTable
                     jboolmap
                     smUrlEncode
                     plotPngToFile
                     completeAPI
                     showAPIinfo
                     setCredentials
                     getCredentials
                     showStoredCredentials
                     evaljson
                     evalDecodeJSON
                     login
                     logout
                     setActiveToken
                     delActiveToken
                     delCallParts
					 setReadingErrorNone
					 setReadingErrorState
                     addSendqueue
                     listSendqueue
                     startFunctionDelayed
                     checkSendRetry
                     purgeSendqueue
                     updQueueLength
                     timestringToTimestamp
                   );
                     
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import( 
      qw(
          attr
          AttrVal
          asyncOutput
          Log3
          data
          defs
          modules
          CancelDelayedShutdown
          devspec2array
          FmtDateTime
          fhemTimeLocal
          setKeyValue
          getKeyValue
          InternalTimer
          plotAsPng
          RemoveInternalTimer
          ReadingsVal
          ReadingsTimestamp
          readingsSingleUpdate
          readingsBeginUpdate
          readingsBulkUpdate
		  readingsBulkUpdateIfChanged
          readingsEndUpdate
          readingsDelete
          HttpUtils_NonblockingGet
        )
  );  
};

# Standardvariablen
my $splitdef    = ":";                                                      # Standard Character für split ...

my $carpnohash  = "got no hash value";
my $carpnoname  = "got no name value";
my $carpnoctyp  = "got no Credentials type code";
my $carpnoapir  = "got no API Hash reference";
my $carpnotfn   = "got no function name";
my $carpnotfarg = "got no Timer function argument";
my $carpnoaddr  = "got no server address from hash";
my $carpnoport  = "got no server port from hash";
my $carpnoprot  = "got no protocol from hash";

my %hasqhandler = (                                                         # Hash addSendqueue Handler
  SSCal     => { fn => \&_addSendqueueSimple,   },                     
  SSFile    => { fn => \&_addSendqueueSimple,   },
  SSChatBot => { fn => \&_addSendqueueExtended, },
);

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

####################################################################################
#    alle Readings außer excludierte löschen
#    $respts -> Respect Timestamp 
#               wenn gesetzt, wird Reading nicht gelöscht
#               wenn Updatezeit identisch zu "lastUpdate"
####################################################################################
sub delReadings {      
  my $name   = shift // carp $carpnoname && return;
  my $respts = shift;
  
  my $hash   = $defs{$name};
  my $type   = $hash->{TYPE};
  
  my ($lu,$rts,$excl);
  
  $excl  = "Error|Errorcode|QueueLength|state|nextUpdate";            # Blacklist
  $excl .= "|lastUpdate" if($respts);
  
  my @allrds = keys%{$defs{$name}{READINGS}};
  for my $key(@allrds) {
      if($respts) {
          $lu  = $data{$type}{$name}{lastUpdate};
          $rts = ReadingsTimestamp($name, $key, $lu);
          next if($rts eq $lu);
      }
      readingsDelete($hash, $key) if($key !~ m/^$excl$/x);
  }
  
return;
}

###############################################################################
#             Leerzeichen am Anfang / Ende eines strings entfernen           
###############################################################################
sub trim {
  my $str = shift;
  
  return if(!$str);
  
  $str =~ s/^\s+|\s+$//gx;

return $str;
}

###############################################################################
#                     File in einem Gang einlesen (schlürfen)          
###############################################################################
sub slurpFile {
  my $name = shift // carp $carpnoname                && return 417;
  my $file = shift // carp "got no filename to slurp" && return 417;
  
  my $errorcode = 0;
  my $content   = q{};
  my $fh;
  
  open $fh, "<", encode("iso_8859_1", "$file") or do { Log3($name, 2, qq{$name - cannot open local File "$file": $!});
                                                       close ($fh) if($fh);
                                                       $errorcode = 9002;                                    
                                                     };
  if(!$errorcode) {
      local $/ = undef;                              # enable slurp mode, locally
      $content = <$fh>;
       
      close ($fh);
  }

return ($errorcode, $content);
}

###############################################################################
#  einen Zeitstring YYYY-MM-TT hh:mm:ss in einen Unix 
#  Timestamp umwandeln
###############################################################################
sub timestringToTimestamp {            
  my $hash    = shift // carp $carpnohash                     && return; 
  my $tstring = shift // carp "got no time string to convert" && return;
  my $name    = $hash->{NAME};

  my($y, $mo, $d, $h, $m, $s) = $tstring =~ /([0-9]{4})-([0-9]{2})-([0-9]{2})\s([0-9]{2}):([0-9]{2}):([0-9]{2})/xs;
  return if(!$mo || !$y);
  
  my $timestamp = fhemTimeLocal($s, $m, $h, $d, $mo-1, $y-1900);
  
return $timestamp;
}

###############################################################################
#                   Readings aus Array erstellen
#       $daref:  Referenz zum Array der zu erstellenden Readings
#                muß Paare <Readingname>:<Wert> enthalten
#       $doevt:  1-Events erstellen, 0-keine Events erstellen
###############################################################################
sub createReadingsFromArray {
  my $hash  = shift // carp $carpnohash                      && return;
  my $daref = shift // carp "got no reading array reference" && return;
  my $doevt = shift // 0;  
  
  readingsBeginUpdate($hash);
  
  for my $elem (@$daref) {
      my ($rn,$rval) = split ":", $elem, 2;
      readingsBulkUpdate($hash, $rn, $rval);      
  }

  readingsEndUpdate($hash, $doevt);
  
return;
}

################################################################
#     Zusätzliche Events im CHANGED Hash eintragen
#     $val - Wert für Trigger Event
#     $ts  - Timestamp für Trigger Event
################################################################
sub addCHANGED {
  my $hash = shift // carp $carpnohash                          && return;
  my $val  = shift // carp "got no value for event trigger"     && return;
  my $ts   = shift // carp "got no timestamp for event trigger" && return;
  
  if($hash->{CHANGED}) {
      push @{$hash->{CHANGED}}, $val;
  } 
  else {
      $hash->{CHANGED}[0] = $val;
  }
  
  if($hash->{CHANGETIME}) {
      push @{$hash->{CHANGETIME}}, $ts;
  } 
  else {
      $hash->{CHANGETIME}[0] = $ts;
  }
  
return;
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
#
#     Beispiel für Übergabe Parameter:
#     my $params = {
#         hash        => $hash,
#         notes       => \%vNotesIntern,
#         useAPI      => 1,
#         useSMUtils  => 1,
#         useErrCodes => 1
#    };
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
#        Gibt die erste Key-Ebene eines Hash als Tabelle formatiert zurück 
#    $headl:  Überschrift über Tabelle
#    $thead:  String der Elemente des Tabellenkopfes (Komma getrennt), z.B.
#             "local Object,remote Object,Date,Time"
#    $datah:  Referenz zum Hashobjekt mit Daten zur Konvertierung in eine Tabelle
#############################################################################################
sub convertHashToTable {                 
  my $paref = shift;
  my $hash  = $paref->{hash}  // carp $carpnohash && return; 
  my $datah = $paref->{datah} // carp "got no hash ref of data for table convert" && return;
  my $headl = $paref->{headl} // q{};
  my $thead = $paref->{thead} // q{};
  
  my $name  = $hash->{NAME};
  
  my $sub = sub { 
      my $idx = shift;
      my @ret;          
      for my $key (sort keys %{$datah->{$idx}}) {
		  push @ret, $datah->{$idx}{$key};
      }
      return @ret;
  };
  
  my $out  = "<html>";
  $out .= "<div class=\"makeTable wide\"; style=\"text-align:left\"><b>$headl</b> <br>";
  $out .= "<table class=\"block wide internals\">";
  $out .= "<tbody>";
  $out .= "<tr class=\"odd\">"; 
  
  if ($thead) {
      my @hd = split ",", $thead;
      for my $elem (@hd) {
	      $out .= "<td> <b>$elem</b> </td>";
	  }
  }

  $out .= "</tr>";
  
  my $i = 0;
  for my $idx (sort keys %{$datah}) {
      my @sq = $sub->($idx);
	  next if(!@sq);
      
      if ($i & 1) {                                            # $i ist ungerade
          $out .= "<tr class=\"odd\">";
      } 
      else {
          $out .= "<tr class=\"even\">";
      }
      $i++;
	  
	  $out .= "<td style=\"vertical-align:top\"> $idx </td>";
	  
	  for my $he (@sq) {
	      $out .= "<td style=\"vertical-align:top\"> $he </td>";
	  }

      $out .= "</tr>";
  }
  
  $out .= "</tbody>";
  $out .= "</table>";
  $out .= "</div>";
  $out .= "</html>";
      
return $out;
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
#   $var  = Variante der boolean Auswertung:
#           "char": Rückgabe von true / false für wahr / falsch
#           "bin" : Rückgabe von 1 / 0 für wahr / falsch
###############################################################################
sub jboolmap { 
  my $bool = shift // carp "got no value to check if bool" && return;
  my $var  = shift // "char";
  
  my $true  = ($var eq "char") ? "true"  : 1;
  my $false = ($var eq "char") ? "false" : 0;
  
  my $is_boolean = JSON::is_bool($bool);
  
  if($is_boolean) {
      $bool = $bool ? $true : $false;
  }
  
return $bool;
}

#############################################################################################
#             Zeichen URL encoden
#             $str  : der zu formatierende String
#############################################################################################
sub smUrlEncode {
  my $str = shift // carp "got no string for URL encoding" && return;
  
  my $hextourl     = { map { sprintf("\\x{%02x}", $_) => sprintf( "%%%02X", $_ ) } ( 0 ... 255 ) };    # Standard Hex Codes zu UrlEncode, z.B. \x{c2}\x{b6} -> %C2%B6 -> ¶
    
  my $replacements = {
      "#"       => "%23",
      "&"       => "%26",
      "%"       => "%25",
      "+"       => "%2B",
      " "       => "%20",
  };
  
  %$replacements = (%$replacements, %$hextourl);
  my $pat        = join '|', map { quotemeta; } keys(%$replacements);
  
  $str =~ s/($pat)/$replacements->{$1}/xg;
  
return $str;
}

####################################################################################
#       Ausgabe der SVG-Funktion "plotAsPng" in eine Datei schreiben
#       Die Datei wird im Verzeichnis "/opt/fhem/www/images" erstellt
####################################################################################
sub plotPngToFile {
    my $name   = shift;
    my $svg    = shift;
    my $hash   = $defs{$name};
    my $file   = $name."_SendPlot.png";
    my $path   = $attr{global}{modpath}."/www/images";
    my $err    = "";
    
    my @options = split ",", $svg;
    my $svgdev  = $options[0];
    my $zoom    = $options[1];
    my $offset  = $options[2];
    
    if(!$defs{$svgdev}) {
        $err = qq{SVG device "$svgdev" doesn't exist};
        Log3($name, 1, "$name - ERROR - $err !");
        
        setReadingErrorState ($hash, $err);
        return $err;
    }
    
    open (my $FILE, ">", "$path/$file") or do {
                                                $err = qq{>PlotToFile< can't open $path/$file for write access};
                                                Log3($name, 1, "$name - ERROR - $err !");
                                                setReadingErrorState ($hash, $err);
                                                return $err;
                                              };
    binmode $FILE;
    print   $FILE plotAsPng(@options);
    close   $FILE;

return ($err, $file);
}

###############################################################################
#      vervollständige das übergebene API-Hash mit den Werten aus $data der 
#      JSON-Antwort 
#      $jdata:   Referenz zum $data-Hash der JSON-Antwort
#      $apiref:  Referenz zum instanziierten API-Hash
###############################################################################
sub completeAPI {  
  my $jdata  = shift // carp "got no data Hash reference" && return;
  my $apiref = shift // carp $carpnoapir                  && return;
  
  for my $key (keys %{$apiref}) {
      next if($key =~ /^PARSET$/x); 
      $apiref->{$key}{PATH} = $jdata->{data}{$apiref->{$key}{NAME}}{path}       // return;
      $apiref->{$key}{VER}  = $jdata->{data}{$apiref->{$key}{NAME}}{maxVersion} // return;
      $apiref->{$key}{MOD}  = "no";                                                       # MOD = Version nicht modifiziert
  }

  $apiref->{PARSET} = 1;                                                                  # alle API Hash values erfolgreich gesetzt
  
return 1;
}

###############################################################################
#      zeigt den Inhalt des verwendeten API Hash als Popup
#      $apiref:  Referenz zum instanziierten API-Hash
###############################################################################
sub showAPIinfo { 
  my $hash   = shift // carp $carpnohash  && return;
  my $apiref = shift // carp $carpnoapir  && return;
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  my $out  = "<html>";
  $out    .= "<b>Synology $type API Info</b> <br><br>";
  $out    .= "<table class=\"roomoverview\" style=\"text-align:left; border:1px solid; padding:5px; border-spacing:5px; margin-left:auto; margin-right:auto;\">";
  $out    .= "<tr><td> <b>API</b> </td><td> <b>Path</b> </td><td> <b>Version</b> </td><td> <b>Modified</b> </td></tr>";
  $out    .= "<tr><td>  </td><td> </td><td> </td><td> </td><td> </td><td> </td></tr>";

  for my $key (sort keys %{$apiref}) {
      next if($key =~ /^PARSET$/x);
      my $apiname = $apiref->{$key}{NAME};
      my $apipath = $apiref->{$key}{PATH};
      my $apiver  = $apiref->{$key}{VER};
      my $apimod  = $apiref->{$key}{MOD};

      $out .= "<tr>";
      $out .= "<td> $apiname </td>";
      $out .= "<td> $apipath </td>";
      $out .= "<td style=\"text-align: center\"> $apiver  </td>";
      $out .= "<td style=\"text-align: center\"> $apimod  </td>";
      $out .= "</tr>";
  }

  $out .= "</table>";
  $out .= "</html>";

  asyncOutput($hash->{HELPER}{CL}{1},"$out");
  delClHash  ($name);
  
return;
}

######################################################################################
#                            Credentials / Token speichern
#   $ctc  = Credentials type code:
#           "credentials"     -> Standard Credentials
#           "SMTPcredentials" -> Credentials für Mailversand
#           "botToken"        -> einen Token speichern
#   $sep  = Separator zum Split des $credstr, default ":"
######################################################################################
sub setCredentials {
    my $hash = shift // carp $carpnohash                 && return;
    my $ctc  = shift // carp $carpnoctyp                 && return;
    my $cred = shift // carp "got no user name or Token" && return;
    my $pass = shift;
    my $sep  = shift // $splitdef;
    
    if(!$pass && $ctc ne "botToken") {                                              # botToken hat kein Paßwort
         carp "got no password";           
         return;
    }    
    
    my $name = $hash->{NAME};
    my $type = $hash->{TYPE};
    
    my ($success,$credstr);
    
    if($ctc eq "botToken") {
        $credstr = _enscramble( encode_base64 ($cred) );    
    }
    else {
        $credstr = _enscramble( encode_base64 ($cred.$sep.$pass) );  
    }    
       
    my $index   = $type."_".$name."_".$ctc;
    my $retcode = setKeyValue($index, $credstr);
    
    if ($retcode) { 
        Log3($name, 2, "$name - Error while saving the Credentials or Token - $retcode");
        $success = 0;
    } 
    else {
        getCredentials($hash,1,$ctc,$sep);                                         # Credentials nach Speicherung lesen und in RAM laden ($boot=1), $ao = credentials oder SMTPcredentials
        $success = 1;
    }

return $success;
}

###############################################################################
#                    verscrambelt einen String
###############################################################################
sub _enscramble { 
  my $sstr = shift // carp "got no string to scramble" && return;
    
  my @key = qw(1 3 4 5 6 3 2 1 9);
  my $len = scalar @key;  
  my $i   = 0;  
  my $dstr = join "", map { $i = ($i + 1) % $len; chr((ord($_) + $key[$i]) % 256) } split //, $sstr;   ## no critic 'Map blocks';

return $dstr;
}

######################################################################################
#                 gespeicherte Credentials dekodiert anzeigen
#
#      $coc      = Wert der anzuzeigenden Credentials (Code of Credentials)
#                  Wert 1 : Credentials Synology (default)
#                  Wert 2 : SMTP Credentials
#                  Wert 4 : Token
#
#      $splitstr = String zum Splitten innerhalb getCredentials, default ":"
######################################################################################
sub showStoredCredentials {
  my $hash     = shift // carp $carpnohash && return;
  my $coc      = shift // 1;
  my $splitstr = shift // $splitdef;
  
  my $out;
  
  my $tokval  = 4;
  my $smtpval = 2;
  my $credval = 1;
  
  my $dotok   = int(  $coc                                      /$tokval  );
  my $dosmtp  = int( ($coc-($dotok*$tokval))                    /$smtpval );
  my $docred  = int( ($coc-($dotok*$tokval)-($dosmtp*$smtpval)) /$credval );
  
  if($docred) {
      my ($success, $username, $passwd) = getCredentials($hash, 0, "credentials", $splitstr);               # Credentials

      my $cd = $success ? 
               "Username: $username, Password: $passwd" : 
               "Credentials are not set or couldn't be read";
                  
      $out  .= "Stored Credentials for access the Synology System:\n".
               "==================================================\n".
               "$cd \n";
  }
  
  if($dosmtp) {
      my ($smtpsuccess, $smtpuname, $smtpword) = getCredentials($hash, 0 , "SMTPcredentials", $splitstr);   # SMTP-Credentials
      
      my $csmtp = $smtpsuccess ? 
                  "SMTP-Username: $smtpuname, SMTP-Password: $smtpword" : 
                  "SMTP credentials are not set or couldn't be read";
                  
      $out     .= "\n".
                  "Stored Credentials for access the SMTP Server:\n".
                  "==============================================\n".
                  "$csmtp \n";
  }
  
  if($dotok) {
      my ($toksuccess, $token) = getCredentials($hash, 0 ,"botToken");                                      # Token 
      
      my $ctok  = $toksuccess ? 
                  $token : 
                  "Token is not set or couldn't be read";
                  
      $out     .= "\n".
                  "Stored Token:\n".
                  "=============\n".
                  "$ctok \n";
  }

return $out;
}

######################################################################################
#                          gespeicherte Credentials laden/abrufen
#   $boot = 1 beim erstmaligen laden
#   $ctc  = Credentials type code:
#           "credentials"     -> Standard Credentials
#           "SMTPcredentials" -> Credentials für Mailversand
#           "botToken"        -> gespeicherten Token abfragen
#   $sep  = Separator zum Split des $credstr, default ":"
######################################################################################
sub getCredentials {
  my $hash = shift // carp $carpnohash && return;
  my $boot = shift;
  my $ctc  = shift // carp $carpnoctyp && return;
  my $sep  = shift // $splitdef;
    
  my $getFn = $boot ? \&_readCredOnBoot : \&_readCredFromCache;
  
return &{$getFn} ($hash, $ctc, $sep);
}

######################################################################################
#                     Credentials initial beim Boot laden/abrufen
#
#   $ctc  = Credentials type code:
#           "credentials"     -> Standard Credentials
#           "SMTPcredentials" -> Credentials für Mailversand
#           "botToken"        -> gespeicherten Token abfragen
#   $sep  = Separator zum Split des $credstr, default ":"
######################################################################################
sub _readCredOnBoot {
  my $hash = shift;
  my $ctc  = shift;
  my $sep  = shift;
    
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
    
  my $sc   = q{};
    
  my $index           = $type."_".$name."_".$ctc;
  my ($err, $credstr) = getKeyValue($index);
    
  if($err) {
      Log3($name, 2, "$name - ERROR - Unable to read $ctc from file: $err");
      return;
  }
    
  if(!$credstr) {
     return;
  }
    
  if($ctc eq "botToken") {                                                          # beim Boot scrambled botToken in den RAM laden
      $hash->{HELPER}{TOKEN} = $credstr;
      $hash->{TOKEN}         = "Set";
      return 1;
  }  
   
  my ($username, $passwd) = split "$sep", decode_base64( _descramble($credstr) );
   
  if(!$username || !$passwd) {
      ($err,$sc) = _getCredentialsFromHash ($hash, $ctc);                           # nur Error und Credetials Shortcut lesen !
      $err       = $err ? $err : qq{possible problem in splitting with separator "$sep"};
      Log3($name, 2, "$name - ERROR - ".$sc." not successfully decoded: $err");
      return;
  }

  if($ctc eq "credentials") {                                                       # beim Boot scrambled Credentials in den RAM laden
      $hash->{HELPER}{CREDENTIALS} = $credstr;
      $hash->{CREDENTIALS}         = "Set";                                         # "Credentials" wird als Statusbit ausgewertet. Wenn nicht gesetzt -> Warnmeldung und keine weitere Verarbeitung          
  } 
  elsif ($ctc eq "SMTPcredentials") {                                               # beim Boot scrambled Credentials in den RAM laden
      $hash->{HELPER}{SMTPCREDENTIALS} = $credstr;
      $hash->{SMTPCREDENTIALS}         = "Set";                                     # "Credentials" wird als Statusbit ausgewertet. Wenn nicht gesetzt -> Warnmeldung und keine weitere Verarbeitung                
  }
  else {
      Log3($name, 2, "$name - ERROR - no shortcut found for Credential type code: $ctc");
      return;
  }
    
return 1;
}

######################################################################################
#                  Credentials aus Cache lesen und dekodieren
#
#   $ctc  = Credentials type code:
#           "credentials"     -> Standard Credentials
#           "SMTPcredentials" -> Credentials für Mailversand
#           "botToken"        -> gespeicherten Token abfragen
#   $sep  = Separator zum Split des $credstr, default ":"
######################################################################################
sub _readCredFromCache {
  my $hash = shift;
  my $ctc  = shift;
  my $sep  = shift;
    
  my $name = $hash->{NAME};
    
  my ($err,$sc,$credstr) = _getCredentialsFromHash ($hash, $ctc);
    
  if($err) {
      Log3($name, 2, "$name - ERROR - ".$sc." not set in RAM ! $err");
      return;
  }
    
  if(!$credstr) {
      return;
  }       
    
  if($ctc eq "botToken") {
      my $token  = decode_base64( _descramble($credstr) );
      my $logtok = AttrVal($name, "showTokenInLog", "0") == 1 ? $token : "********";
    
      Log3($name, 4, "$name - botToken read from RAM: $logtok");
      
      return (1, $token);
  }

  my ($username, $passwd) = split "$sep", decode_base64( _descramble($credstr) );
    
  if(!$username || !$passwd) {
      $err = qq{possible problem in splitting with separator "$sep"};
      Log3($name, 2, "$name - ERROR - ".$sc." not successfully decoded ! $err");
        
      if($ctc eq "credentials") {
          delete $hash->{CREDENTIALS};
      }
        
      return;
  }
    
  my $logpw = AttrVal($name, "showPassInLog", 0) ? $passwd // "" : "********";

  Log3($name, 4, "$name - ".$sc." read from RAM: $username $logpw");

return (1, $username, $passwd);
}

###############################################################################
#             entpackt einen mit _enscramble behandelten String
###############################################################################
sub _descramble { 
  my $sstr = shift // carp "got no string to descramble" && return;
    
  my @key = qw(1 3 4 5 6 3 2 1 9); 
  my $len = scalar @key;  
  my $i = 0;  
  my $dstr = join "", map { $i = ($i + 1) % $len; chr((ord($_) - $key[$i] + 256) % 256) } split //, $sstr;    ## no critic 'Map blocks';  

return $dstr;
}

###############################################################################
#   liefert Kürzel eines Credentials und den Credetialstring aus dem Hash 
#   $ctc = Credentials Type Code
#   $sc  = Kürzel / Shortcut
###############################################################################
sub _getCredentialsFromHash {
  my $hash = shift // carp $carpnohash                    && return;    
  my $ctc  = shift // carp "got no Credentials type code" && return;
  
  my $name = $hash->{NAME};
    
  my $credstr = q{}; 
  my $sc      = q{};
  my $found   = 0;
  my $err     = "no shortcut found for Credential type code: $ctc";
  
  if ($ctc eq "credentials") {
      $err     = q{};
      $found   = 1;
      $sc      = q{Credentials};
      $credstr = $hash->{HELPER}{CREDENTIALS};
  } 
  elsif ($ctc eq "SMTPcredentials") {
      $err     = q{};
      $found   = 1;
      $sc      = q{SMTP-Credentials};
      $credstr = $hash->{HELPER}{SMTPCREDENTIALS};
  }
  elsif ($ctc eq "botToken") {
      $err     = q{};
      $found   = 1;
      $sc      = q{Token};
      $credstr = $hash->{HELPER}{TOKEN};
  }

  if($found && !$credstr) {
      Log3($name, 5, qq{$name - The stored value of $ctc is empty});
  }
        
return ($err,$sc,$credstr);
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
              $OpMode =~ m/^.*_hls$/x ) {                                                        # SSCam: HLS aktivate/deaktivate bringt kein JSON wenn bereits aktiviert/deaktiviert
          Log3($name, 5, "$name - HLS-activation data return: $myjson");
          
          if ($myjson =~ m/{"success":true}/x) {
              $success = 1;
              $myjson  = '{"success":true}';    
          }
      } 
      else {
          $success = 0;

          my $errorcode = "9000";         
          my $error     = expErrors($hash,$errorcode);                                          # Fehlertext zum Errorcode ermitteln
            
          setReadingErrorState ($hash, $error, $errorcode);  
      }
  };
  
return ($success,$myjson);
}

###############################################################################
#         testet und decodiert einen übergebenen JSON-String
#         Die dekodierten Daten werden zurück gegeben bzw. im
#         SSCam-Kontext angepasst
###############################################################################
sub evalDecodeJSON { 
  my $hash    = shift // carp $carpnohash                   && return;
  my $myjson  = shift // carp "got no string for JSON test" && return;
  my $OpMode  = $hash->{OPMODE};
  my $name    = $hash->{NAME};
  
  my $success = 1;
  my $decoded = q{};
  
  if($nojsonmod) {
      $success = 0;
      Log3($name, 1, "$name - ERROR: Perl module 'JSON' is missing. You need to install it.");
      return ($success,$myjson);
  }
  
  eval {$decoded = decode_json($myjson)} or do {
      if( ($hash->{HELPER}{RUNVIEW} && $hash->{HELPER}{RUNVIEW} =~ m/^live_.*hls$/x) || 
              $OpMode =~ m/^.*_hls$/x ) {                                                        # SSCam: HLS aktivate/deaktivate bringt kein JSON wenn bereits aktiviert/deaktiviert
          Log3($name, 5, "$name - HLS-activation data return: $myjson");
          
          if ($myjson =~ m/{"success":true}/x) {
              $success = 1;
              $myjson  = '{"success":true}';
              $decoded = decode_json($myjson);             
          }
      } 
      else {
          $success = 0;
          $decoded = q{};
          
          my $errorcode = "9000";         
          my $error     = expErrors($hash,$errorcode);                                          # Fehlertext zum Errorcode ermitteln
            
          setReadingErrorState ($hash, $error, $errorcode);  
      }
  };
  
return ($success,$decoded);
}

####################################################################################  
#         Login wenn keine oder ungültige Session-ID vorhanden ist
#    $apiref  = Referenz zum API Hash
#    $fret    = Referenz zur Rückkehrfunktion nach erfolgreichen Login
#    $fretarg = Argument für Rückkehrfunktion, default: $hash
#    $sep     = Separator für split Credentials in getCredentials, default ":"
####################################################################################
sub login {
  my $hash         = shift               // carp $carpnohash                        && return;
  my $apiref       = shift               // carp $carpnoapir                        && return;
  my $fret         = shift               // carp "got no return function reference" && return;
  my $fretarg      = shift               // $hash;
  my $sep          = shift               // $splitdef;
  
  my $serveraddr   = $hash->{SERVERADDR} // carp $carpnoaddr                        && return;
  my $serverport   = $hash->{SERVERPORT} // carp $carpnoport                        && return;
  my $proto        = $hash->{PROTOCOL}   // carp $carpnoprot                        && return;
  my $name         = $hash->{NAME};
  my $apiauth      = $apiref->{AUTH}{NAME};
  my $apiauthpath  = $apiref->{AUTH}{PATH};
  my $apiauthver   = $apiref->{AUTH}{VER};
  my $type         = $hash->{TYPE};

  my ($url,$param,$urlwopw);
  
  delete $hash->{HELPER}{SID};
    
  Log3($name, 4, "$name - --- Begin Function login ---");
  
  my ($success, $username, $password) = getCredentials($hash,0,"credentials",$sep);                      # Credentials abrufen
  
  if (!$success) {
      Log3($name, 2, qq{$name - Credentials couldn't be retrieved successfully - make sure you've set it with "set $name credentials <username> <password>"});
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
      fret     => $fret,
      fretarg  => $fretarg,
      sep      => $sep,
	  apiref   => $apiref,
      method   => "GET",
      header   => "Accept: application/json",
      callback => \&_loginReturn
  };
  
  HttpUtils_NonblockingGet ($param);
   
return;
}

sub _loginReturn {
  my $param    = shift;
  my $err      = shift;
  my $myjson   = shift;
  my $hash     = $param->{hash};
  
  my $name     = $hash->{NAME};
  my $username = $param->{user};
  my $fret     = $param->{fret};
  my $fretarg  = $param->{fretarg};
  my $sep      = $param->{sep};  
  my $apiref   = $param->{apiref};
  my $type     = $hash->{TYPE};
  
  my $success; 

  if ($err ne "") {                                                                # ein Fehler bei der HTTP Abfrage ist aufgetreten
      Log3($name, 2, "$name - error while requesting ".$param->{url}." - $err");
        
      readingsSingleUpdate($hash, "Error", $err, 1);                               
        
      return login($hash,$apiref,$fret,$fretarg,$sep);
   
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
            readingsBulkUpdate  ($hash, "Errorcode", "none");
            readingsBulkUpdate  ($hash, "Error",     "none");
            readingsEndUpdate   ($hash, 1);
       
            Log3($name, 4, "$name - Login of User $username successful - SID: $sid");
            
            return &$fret($fretarg);
        } 
        else {          
            my $errorcode = $data->{'error'}->{'code'};                           # Errorcode aus JSON ermitteln
            my $error     = expErrorsAuth($hash,$errorcode);                      # Fehlertext zum Errorcode ermitteln
            
            readingsBeginUpdate ($hash);
            readingsBulkUpdate  ($hash, "Errorcode", $errorcode   );
            readingsBulkUpdate  ($hash, "Error",     $error       );
            readingsBulkUpdate  ($hash, "state",     "login Error");
            readingsEndUpdate   ($hash, 1);
       
            Log3($name, 3, "$name - Login of User $username unsuccessful. Code: $errorcode - $error - try again"); 
             
            return login($hash,$apiref,$fret,$fretarg,$sep);
       }
   }
   
return login($hash,$apiref,$fret,$fretarg,$sep);
}

###################################################################################  
#      Funktion logout
#    $apiref  = Referenz zum API Hash
#    $sep     = Separator für split Credentials in getCredentials, default ":"
###################################################################################
sub logout {
   my $hash        = shift  // carp $carpnohash && return;
   my $apiref      = shift  // carp $carpnoapir && return;
   my $sep         = shift  // $splitdef;
   
   my $name        = $hash->{NAME};
   my $serveraddr  = $hash->{SERVERADDR};
   my $serverport  = $hash->{SERVERPORT};
   my $proto       = $hash->{PROTOCOL};
   my $type        = $hash->{TYPE};
   
   my $apiauth     = $apiref->{AUTH}{NAME};
   my $apiauthpath = $apiref->{AUTH}{PATH};
   my $apiauthver  = $apiref->{AUTH}{VER};
   
   my $sid         = delete $hash->{HELPER}{SID} // q{};
   
   my $url;
     
   Log3($name, 4, "$name - --- Start Synology logout ---");
   
   my ($success, $username) = getCredentials($hash,0,"credentials",$sep);
   
   if(!$sid) {
       if($username) {
           Log3($name, 2, qq{$name - User "$username" has no valid session, logout is cancelled});
       }

       readingsBeginUpdate ($hash);
       readingsBulkUpdate  ($hash, "Errorcode", "none");
       readingsBulkUpdate  ($hash, "Error",     "none");
       readingsBulkUpdate  ($hash, "state",     "logout done");
       readingsEndUpdate   ($hash, 1);

       delActiveToken        ($hash) if($type eq "SSCam");                                                   # ausgeführte Funktion ist erledigt (auch wenn logout nicht erfolgreich), Freigabe Funktionstoken
       CancelDelayedShutdown ($name);
       return;
   }
    
   my $timeout = AttrVal($name,"timeout",60);
   $timeout    = 60 if($timeout < 60);
   Log3($name, 5, "$name - Call logout will be done with timeout value: $timeout s");
  
   if (AttrVal($name,"session","DSM") eq "DSM") {
       $url = "$proto://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthver&method=Logout&_sid=$sid";    
   } 
   else {
       $url = "$proto://$serveraddr:$serverport/webapi/$apiauthpath?api=$apiauth&version=$apiauthver&method=Logout&session=SurveillanceStation&_sid=$sid";
   }

   my $param = {
       url      => $url,
       timeout  => $timeout,
       hash     => $hash,
       sid      => $sid,
       username => $username,
       method   => "GET",
       header   => "Accept: application/json",
       callback => \&_logoutReturn
   };
   
   HttpUtils_NonblockingGet ($param);

return;
}

sub _logoutReturn {  
   my $param    = shift;
   my $err      = shift;
   my $myjson   = shift;
   my $hash     = $param->{hash};
   my $sid      = $param->{sid};
   my $username = $param->{username};
   
   my $name     = $hash->{NAME};
   my $type     = $hash->{TYPE};
  
   if ($err ne "") {                                                                                          # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
       Log3($name, 2, "$name - error while requesting ".$param->{url}." - $err"); 
       readingsSingleUpdate($hash, "Error", $err, 1);                                             
   
   } elsif ($myjson ne "") {                                                                                  # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
       Log3($name, 4, "$name - URL-Call: ".$param->{url});
        
       my ($success) = evaljson($hash,$myjson);                                                                  # Evaluiere ob Daten im JSON-Format empfangen wurden
        
       if (!$success) {
           Log3($name, 4, "$name - Data returned: ".$myjson);
           delActiveToken ($hash) if($type eq "SSCam");
           return;
       }
        
       my $data = decode_json($myjson);
       
       Log3($name, 4, "$name - JSON returned: ". Dumper $data);                   
   
       $success = $data->{'success'};

       if ($success) {                                                                                        # die Logout-URL konnte erfolgreich aufgerufen werden                        
           readingsBeginUpdate ($hash);
           readingsBulkUpdate  ($hash, "Errorcode", "none");
           readingsBulkUpdate  ($hash, "Error",     "none");
           readingsBulkUpdate  ($hash, "state",     "logout done");
           readingsEndUpdate   ($hash, 1);
           
           Log3($name, 2, qq{$name - Session of User "$username" terminated - session ID "$sid" deleted});      
       } 
       else {
           my $errorcode = $data->{'error'}->{'code'};                                                        # Errorcode aus JSON ermitteln
           my $error     = expErrorsAuth($hash,$errorcode);                                                   # Fehlertext zum Errorcode ermitteln

           Log3($name, 2, qq{$name - ERROR - Logout of User $username was not successful, however SID: "$sid" has been deleted. Errorcode: $errorcode - $error});
       }
   }
   
   delActiveToken        ($hash) if($type eq "SSCam");                                                        # ausgeführte Funktion ist erledigt (auch wenn logout nicht erfolgreich), Freigabe Funktionstoken
   CancelDelayedShutdown ($name);
   
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
  my $evt  = shift // 0;
  
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
    
    readingsBeginUpdate($hash); 
    readingsBulkUpdate ($hash, "Error",     $error);
    readingsBulkUpdate ($hash, "Errorcode", $errcode);
    readingsBulkUpdate ($hash, "state",     "Error");                    
    readingsEndUpdate  ($hash,1);

return;
}

######################################################################################
#                       Eintrag an SendQueue des Modultyps anhängen
#       die Unterroutinen werden in Abhängigkeit des auslösenden Moduls angesprungen
######################################################################################
sub addSendqueue {
   my $paref = shift;
   my $name  = $paref->{name} // carp $carpnoname && return;
   
   my $hash  = $defs{$name};
   my $type  = $hash->{TYPE}; 

   if($hasqhandler{$type}) {
       &{$hasqhandler{$type}{fn}} ($paref);
       return;
   }   
      
   Log3($name, 1, qq{$name - ERROR - no module specific add Sendqueue handler for type "$type" found});
   
return;
}

######################################################################################
#    Eintrag zur SendQueue hinzufügen (Standard Parametersatz ohne Prüfung)
#
#    $name   = Name (Kalender)device
#    $opmode = operation mode
#    $api    = API-Referenz (z.B. $data{SSCal}{$name}{calapi})
#    $method = auszuführende API-Methode 
#    $params = spezifische API-Parameter für GET
#
#    Weitere Parameter hinzufügen falls vorhanden. 
######################################################################################
sub _addSendqueueSimple {
   my $paref    = shift;
   my $name     = $paref->{name};
   my $opmode   = $paref->{opmode};
   my $api      = $paref->{api};
   my $method   = $paref->{method};
   my $params   = $paref->{params};
   my $dest     = $paref->{dest};
   my $reqtype  = $paref->{reqtype};
   my $header   = $paref->{header};
   my $postdata = $paref->{postdata};
   my $lclFile  = $paref->{lclFile};
   my $remFile  = $paref->{remFile};
   my $remDir   = $paref->{remDir};
   my $timeout  = $paref->{timeout};
   
   my $hash     = $defs{$name};
   
   my $entry = {
       'opmode'     => $opmode, 
       'api'        => $api,   
       'method'     => $method, 
       'retryCount' => 0               
   };
   
   # optionale Zusatzfelder 
   $entry->{params}   = $params    if(defined $params);
   $entry->{dest}     = $dest      if(defined $dest);
   $entry->{reqtype}  = $reqtype   if(defined $reqtype);
   $entry->{header}   = $header    if(defined $header);
   $entry->{postdata} = $postdata  if(defined $postdata);
   $entry->{lclFile}  = $lclFile   if(defined $lclFile);
   $entry->{remFile}  = $remFile   if(defined $remFile);
   $entry->{remDir}   = $remDir    if(defined $remDir);
   $entry->{timeout}  = $timeout   if(defined $timeout);
   
   __addSendqueueEntry ($hash, $entry);                          # den Datensatz zur Sendqueue hinzufügen                                                       # updaten Länge der Sendequeue     
   
return;
}

######################################################################################
#    Eintrag zur SendQueue hinzufügen (erweiterte Parameter mit Prüfung)
#
#    $name    = Name des Devices
#    $opmode  = operation Mode
#    $method  = auszuführende API-Methode 
#    $userid  = ID des (Chat)users
#    $text    = zu übertragender Text
#    $fileUrl = opt. zu übertragendes File
#    $channel = opt. Channel
#
######################################################################################
sub _addSendqueueExtended {
    my $paref      = shift;
    my $name       = $paref->{name};
    my $hash       = $defs{$name};
    my $opmode     = $paref->{opmode}  // do {my $err = qq{internal ERROR -> opmode is empty}; Log3($name, 1, "$name - $err"); setReadingErrorState ($hash, $err); return};
    my $method     = $paref->{method}  // do {my $err = qq{internal ERROR -> method is empty}; Log3($name, 1, "$name - $err"); setReadingErrorState ($hash, $err); return};
    my $userid     = $paref->{userid}  // do {my $err = qq{internal ERROR -> userid is empty}; Log3($name, 1, "$name - $err"); setReadingErrorState ($hash, $err); return};
    my $text       = $paref->{text};
    my $fileUrl    = $paref->{fileUrl};
    my $channel    = $paref->{channel};
    my $attachment = $paref->{attachment};
    
    if(!$text && $opmode !~ /chatUserlist|chatChannellist|apiInfo/x) {
        my $err = qq{can't add message to queue: "text" is empty};
        Log3($name, 2, "$name - ERROR - $err");
        
        setReadingErrorState ($hash, $err);      

        return;        
    }
      
    my $entry = {
        'opmode'     => $opmode,   
        'method'     => $method, 
        'userid'     => $userid,
        'channel'    => $channel,
        'text'       => $text,
        'attachment' => $attachment,
        'fileUrl'    => $fileUrl,  
        'retryCount' => 0             
    };
              
    __addSendqueueEntry ($hash, $entry);                          # den Datensatz zur Sendqueue hinzufügen    
   
return;
}

#############################################################################################
#                        fügt den Eintrag $entry zur Sendequeue hinzu
#############################################################################################
sub __addSendqueueEntry {                 
  my $hash  = shift // carp $carpnohash                             && return;
  my $entry = shift // carp "got no entry for adding to send queue" && return;
  my $name  = $hash->{NAME};
  
  my $type  = $hash->{TYPE};
    
  $data{$type}{$name}{sendqueue}{index}++;
  my $index = $data{$type}{$name}{sendqueue}{index};
    
  Log3($name, 5, "$name - Add Item to queue - Index $index: \n".Dumper $entry);
                      
  $data{$type}{$name}{sendqueue}{entries}{$index} = $entry;  

  updQueueLength ($hash, "", 0);                                  # update Länge der Sendequeue ohne Event
      
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
#     Funktion Zeitplan löschen und neu planen
#     $rst     = Zeit für Funktionseinplanung
#     $startfn = Funktion (Name incl. Paket) deren Timer gelöscht und neu gestartet wird
#     $arg     = Argument für die Timer Funktion
#############################################################################################
sub startFunctionDelayed {                   
  my $name    = shift // carp $carpnoname                  && return;
  my $rst     = shift // carp "got no restart Timer value" && return;
  my $startfn = shift // carp $carpnotfn                   && return;
  my $arg     = shift // carp $carpnotfarg                 && return;

  RemoveInternalTimer ($arg, $startfn);
  InternalTimer       ($rst, $startfn, $arg, 0);   
                    
return;
}

#############################################################################################
#      Erfolg der Abarbeitung eines Queueeintrags checken und ggf. Retry ausführen
#      bzw. den SendQueue-Eintrag bei Erfolg löschen
#      $name       =   Name des Devices
#      $retry      =   0 -> Opmode erfolgreich (DS löschen), 
#                      1 -> Opmode nicht erfolgreich (Abarbeitung nach ckeck errorcode
#                           eventuell verzögert wiederholen)
#      $startfn    = Funktion (Name incl. Paket) die nach Check ggf. gestartet werden soll
#############################################################################################
sub checkSendRetry {  
  my $name       = shift // carp $carpnoname           && return;
  my $retry      = shift // carp "got no opmode state" && return;
  my $startfn    = shift // carp $carpnotfn            && return;
  my $hash       = $defs{$name};  
  my $idx        = $hash->{OPIDX};
  my $opmode     = $hash->{OPMODE};
  my $type       = $hash->{TYPE};
  
  $hash->{OPMODE} = q{};
  
  my $forbidSend = q{};
  my $startfnref = \&{$startfn};
  
  my @forbidlist = qw(100 101 103 117 120 400 401 407 408 409 410 414 418 419 420 800 900
                      1000 1001 1002 1003 1004 1006 1007 1100 1101 1200 1300 1301 1400
                      1401 1402 1403 1404 1405 1800 1801 1802 1803 1804 1805 2000 2001    
                      2002 9002);                                                         # bei diesen Errorcodes den Queueeintrag nicht wiederholen, da dauerhafter Fehler !
  
  if(!keys %{$data{$type}{$name}{sendqueue}{entries}}) {
      Log3($name, 4, "$name - SendQueue is empty. Nothing to do ..."); 
      updQueueLength ($hash);
      return;  
  } 
  
  if(!$retry) {                                                                           # Befehl erfolgreich, Senden nur neu starten wenn weitere Einträge in SendQueue
      delete $hash->{OPIDX};
      delete $data{$type}{$name}{sendqueue}{entries}{$idx};
      Log3($name, 4, qq{$name - Opmode "$opmode" finished successfully, Sendqueue index "$idx" deleted.});
      updQueueLength ($hash);
      
      if(keys %{$data{$type}{$name}{sendqueue}{entries}}) {
          Log3($name, 4, "$name - Start next SendQueue entry..."); 
          return &$startfnref ($name);                                                    # nächsten Eintrag abarbeiten (wenn SendQueue nicht leer)
      }  
  } 
  else {                                                                                  # Befehl nicht erfolgreich, (verzögertes) Senden einplanen
      $data{$type}{$name}{sendqueue}{entries}{$idx}{retryCount}++;
      my $rc = $data{$type}{$name}{sendqueue}{entries}{$idx}{retryCount};
  
      my $errorcode = ReadingsVal($name, "Errorcode", 0);
      
      if($errorcode =~ /119/x) {                                                          # Session wird neu requestet und Queue-Eintrag wiederholt
          delete $hash->{HELPER}{SID};
      }
      
      if(grep { $_ eq $errorcode } @forbidlist) {                              
          $forbidSend = expErrors($hash,$errorcode);                                      # Fehlertext zum Errorcode ermitteln
          $data{$type}{$name}{sendqueue}{entries}{$idx}{forbidSend} = $forbidSend;
          
          Log3($name, 2, qq{$name - ERROR - "$opmode" SendQueue index "$idx" not executed. It seems to be a permanent error. Exclude it from new send attempt !});
          
          delete $hash->{OPIDX};
          
          updQueueLength ($hash);                                                         # updaten Länge der Sendequeue
          
          return &$startfnref ($name);                                                    # nächsten Eintrag abarbeiten (wenn SendQueue nicht leer);
      }
      
      if(!$forbidSend) {
          my $rs = 0;
          $rs = $rc <= 1 ? 5 
              : $rc <  3 ? 20
              : $rc <  5 ? 60
              : $rc <  7 ? 1800
              : $rc < 30 ? 3600
              : 86400
              ;
          
          Log3($name, 2, qq{$name - ERROR - "$opmode" SendQueue index "$idx" not executed. Restart SendQueue in $rs s (retryCount $rc).});
          
          my $rst = gettimeofday()+$rs;                                                  # resend Timer 
          updQueueLength       ($hash, $rst);                                            # updaten Länge der Sendequeue mit resend Timer
          startFunctionDelayed ($name, $rst, $startfn, $name);
      }
  }

return
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
  my $ret   = q{};
  
  if($prop eq "-all-") {
      delete $hash->{OPIDX};
      delete $data{$type}{$name}{sendqueue}{entries};
      $data{$type}{$name}{sendqueue}{index} = 0;
      $ret = "All entries of SendQueue are deleted";
  } 
  elsif($prop eq "-permError-") {
      for my $idx (keys %{$data{$type}{$name}{sendqueue}{entries}}) { 
          delete $data{$type}{$name}{sendqueue}{entries}{$idx} 
              if($data{$type}{$name}{sendqueue}{entries}{$idx}{forbidSend});            
      }
      $ret = qq{All entries with state "permanent send error" are deleted};
  } 
  else {
      delete $data{$type}{$name}{sendqueue}{entries}{$prop};
      $ret = qq{SendQueue entry with index "$prop" deleted};
  }
  
  updQueueLength ($hash);
      
return $ret;
}

#############################################################################################
#                        Länge Senedequeue updaten 
#     $rst:   Resend Timestamp
#     $evtt:  Eventtyp  0 - kein Event
#                       1 - immer Event (Standard)
#                       2 - Event nur bei fallendem QueueLength-Zähler
#                       3 - Event nur bei steigendem QueueLength-Zähler
#############################################################################################
sub updQueueLength {
  my $hash = shift // carp $carpnohash && return; 
  my $rst  = shift;
  my $evtt = shift // 1;
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $ql   = keys %{$data{$type}{$name}{sendqueue}{entries}};
  
  readingsDelete ($hash, "QueueLenth");                                            # entferne Reading mit Typo
  
  my $evt  = $evtt;
  my $oql  = ReadingsVal($name, "QueueLength", 0);
  
  if ($evtt == 2) {                                                                # Events nur bei Herabzählen der Queue
      $evt = $oql > $ql ? 1 : 0;
  }
 
  if ($evtt == 3) {                                                                # Events nur bei Heraufzählen der Queue
      $evt = $ql > $oql ? 1 : 0;
  } 
  
  readingsBeginUpdate         ($hash);                                             
  readingsBulkUpdateIfChanged ($hash, "QueueLength", $ql);                         # Länge Sendqueue updaten
  readingsEndUpdate           ($hash, $evt);
  
  my $head        = "next planned SendQueue start:";
   
  $hash->{RESEND} = $rst ? $head." ".FmtDateTime($rst) : $head." immediately by next entry";

return;
}

1;