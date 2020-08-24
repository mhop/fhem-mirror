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

# use lib qw(/opt/fhem/FHEM);                                   # für Syntaxcheck mit: perl -c /opt/fhem/lib/FHEM/SynoModules/SMUtils.pm
use GPUtils qw( GP_Import GP_Export ); 
use Carp qw(croak carp);

use version; our $VERSION = qv('1.0.0');

use Exporter ('import');
our @EXPORT_OK   = qw(
                       getClHash 
                       trim
                       sortVersion
                       setVersionInfo
                     );
                     
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import( 
      qw(
          Log3
          defs
          modules
          devspec2array
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
              $val = $val // " ";
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
  my $hash  = shift  // carp "got no hash value !" && return;
  my $notes = shift  // carp "got no vNotesIntern value !" && return;
  my $name  = $hash->{NAME};

  my $v                    = (sortVersion("desc",keys %{$notes}))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {          # META-Daten sind vorhanden
      $modules{$type}{META}{version} = "v".$v;                                           # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{<TYPE>}{META}}
      
      if($modules{$type}{META}{x_version}) {                                             # {x_version} ( nur gesetzt wenn $Id$ im Kopf komplett! vorhanden )
          $modules{$type}{META}{x_version} =~ s/1\.1\.1/$v/gx;
      } else {
          $modules{$type}{META}{x_version} = $v; 
      }
      return $@ unless (FHEM::Meta::SetInternals($hash));                                # FVERSION wird gesetzt ( nur gesetzt wenn $Id$ im Kopf komplett! vorhanden )
      
      if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {                         # es wird mit Packages gearbeitet -> mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
          use version; our $VERSION = FHEM::Meta::Get( $hash, 'version' );               ## no critic 'VERSION Reused'                                      
      }
  
  } else {                                                                               # herkömmliche Modulstruktur
      $hash->{VERSION} = $v;
  }
  
return;
}

1;