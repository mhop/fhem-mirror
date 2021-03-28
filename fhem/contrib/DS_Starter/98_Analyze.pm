########################################################################################################################
# $Id: $
#########################################################################################################################
#       98_Analyze.pm
#
#       (c) 2020 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This Module analyzes the data structure size in FHEM
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
# 
# Definition: define <name> Analyze
# 
# Example: define anaData Analyze
#
package FHEM::Analyze;                                                                                    ## no critic 'package'

use strict;                           
use warnings;
use utf8;
eval "use Devel::Size::Report qw(report_size track_size track_sizes entries_per_element hide_tracks); 1;" ## no critic 'eval'    
    or my $modReportAbsent = "Devel::Size::Report";                                                      
use Data::Dumper;                                                                                         # Perl Core module
use GPUtils qw(GP_Import GP_Export);                                                                      # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt

use FHEM::SynoModules::SMUtils qw( moduleVersion delReadings );                                           # Hilfsroutinen Modul

no if $] >= 5.017011, warnings => 'experimental::smartmatch';
eval "use FHEM::Meta;1" or my $modMetaAbsent = 1;                                                         ## no critic 'eval'
                                                    
# no if $] >= 5.017011, warnings => 'experimental';

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import( 
      qw(     
          attr   
          modules         
          AttrVal
          Debug
          data
          defs
          IsDisabled
          Log3 
          modules
          CommandAttr
          devspec2array
          parseParams         
          ReadingsVal
          RemoveInternalTimer
          readingsBeginUpdate
          readingsBulkUpdate
          readingsEndUpdate
          readingsSingleUpdate
          readingFnAttributes         
        )
  );
  
  # Export to main context with different name
  #     my $pkg  = caller(0);
  #     my $main = $pkg;
  #     $main =~ s/^(?:.+::)?([^:]+)$/main::$1\_/gx;
  #     foreach (@_) {
  #         *{ $main . $_ } = *{ $pkg . '::' . $_ };
  #     }
  GP_Export(
      qw(
          Initialize
        )
  );  
}

# Versions History intern
  my %vNotesIntern = (
    "0.1.0"  => "25.11.2020  initial "
  );

# Voreinstellungen
  my %hset = (                                                                                           # Hash der Set-Funktion
    allDevices   => { fn => \&_setDeviceType   },
    deviceType   => { fn => \&_setDeviceType   },   
    xHashDetail  => { fn => \&_setxHashDetail  },
    mainHash     => { fn => \&_setMainHash     },  
  );
  
  my %hexcl = (                                                                                          # Hash der excudierten Modultypen wegen Crash Devel::Size
    TelegramBot => 1,      
  );

################################################################
sub Initialize {
 my ($hash) = @_;
 $hash->{DefFn}                 = \&Define;
 $hash->{UndefFn}               = \&Undef;
 $hash->{DeleteFn}              = \&Delete; 
 $hash->{SetFn}                 = \&Set;
 $hash->{AttrFn}                = \&Attr;
 
 $hash->{FW_deviceOverview}     = 1;
 
 $hash->{AttrList} = "analyzeObject ".
                     "disable:1,0 ".
                     "largeObjectNum ".
                     "noOutput:1,0 ".
                     $readingFnAttributes;   
         
 FHEM::Meta::InitMod( __FILE__, $hash ) if(!$modMetaAbsent);  # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)

return;   
}

################################################################
#                 Define
################################################################
sub Define {
  my ($hash, $def) = @_;
  
  my $name = $hash->{NAME};
  
  return qq{ERROR - Perl module "$modReportAbsent" is missing. You need to install it first.} if($modReportAbsent);
  
  my @a                          = split(/\s+/x, $def);  
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                                              # Modul Meta.pm nicht vorhanden  
  
  CommandAttr(undef, "$name room SYSTEM");

  my $params = {
      hash        => $hash,
      notes       => \%vNotesIntern,
      useSMUtils  => 1
  };
  use version 0.77; our $VERSION = moduleVersion ($params);                                           # Versionsinformationen setzen
  
  readingsBeginUpdate($hash);   
  readingsBulkUpdate ($hash, "state", "Initialized");                                                 # Init state
  readingsEndUpdate  ($hash,1);
  
return;
}

################################################################
# Die Undef-Funktion wird aufgerufen wenn ein Gerät mit delete 
# gelöscht wird oder bei der Abarbeitung des Befehls rereadcfg, 
# der ebenfalls alle Geräte löscht und danach das 
# Konfigurationsfile neu einliest. 
# Funktion: typische Aufräumarbeiten wie das 
# saubere Schließen von Verbindungen oder das Entfernen von 
# internen Timern, sofern diese im Modul zum Pollen verwendet 
# wurden.
################################################################
sub Undef {
  my $hash = shift;
  my $arg  = shift;
   
return;
}

#######################################################################################################
# Mit der X_DelayedShutdown Funktion kann eine Definition das Stoppen von FHEM verzögern um asynchron 
# hinter sich aufzuräumen.  
# Je nach Rückgabewert $delay_needed wird der Stopp von FHEM verzögert (0|1).
# Sobald alle nötigen Maßnahmen erledigt sind, muss der Abschluss mit CancelDelayedShutdown($name) an 
# FHEM zurückgemeldet werden. 
#######################################################################################################
sub DelayedShutdown {
  my $hash = shift;
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
return 0;
}

#################################################################
# Wenn ein Gerät in FHEM gelöscht wird, wird zuerst die Funktion 
# X_Undef aufgerufen um offene Verbindungen zu schließen, 
# anschließend wird die Funktion X_Delete aufgerufen. 
# Funktion: Aufräumen von dauerhaften Daten, welche durch das 
# Modul evtl. für dieses Gerät spezifisch erstellt worden sind. 
# Es geht hier also eher darum, alle Spuren sowohl im laufenden 
# FHEM-Prozess, als auch dauerhafte Daten bspw. im physikalischen 
# Gerät zu löschen die mit dieser Gerätedefinition zu tun haben. 
#################################################################
sub Delete {
  my $hash  = shift;
  my $arg   = shift;
      
return;
}

################################################################
sub Attr {                             
    my $cmd   = shift;
    my $name  = shift;
    my $aName = shift;
    my $aVal  = shift;
    
    my $hash  = $defs{$name};
    
    my ($do,$val);
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    
    if ($aName eq "disable") {
        if($cmd eq "set") {
            $do = $aVal ? 1 : 0;
        }
        $do  = 0 if($cmd eq "del");
        $val = ($do ? "disabled" : "initialized");
        
        if ($do) {
            delReadings ($name, 0);
        }
    
        readingsBeginUpdate($hash); 
        readingsBulkUpdate ($hash, "state", $val);                    
        readingsEndUpdate  ($hash, 1); 
    }
    
    if ($cmd eq "set") {
        if ($aName =~ m/largeObjectNum/x) {
            unless ($aVal =~ /^[0-9]+$/x) { return qq{The value of $aName is not valid. Use only integers 0 ... 9 !}; }
        }         
    }
    
return;
}

#############################################################################################
#                                      Setter
#############################################################################################
sub Set {                                                           
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name  = shift @a;
  my $opt   = shift @a;
  my $arg   = join " ", map { my $p = $_; $p =~ s/\s//xg; $p; } @a;     ## no critic 'Map blocks'
  my $prop  = shift @a;
        
  return if(IsDisabled($name));
  
  my $mods    = join ",", sort keys (%modules);
  my $noout   = AttrVal ($name, "noOutput", 0);
  my $ml      = AttrVal ($name, "largeObjectNum", 5);
  my $l       = length $ml;                                             # Anzahl Stellen (Länge) von largeObjectNum
  
  my $setlist = "Unknown argument $opt, choose one of ";
  
  $setlist   .= "allDevices:noArg ".
                "deviceType:$mods ".
                "xHashDetail ".
                "mainHash:\$data,\$attr,\$cmds "
                ;
  my %sizes;                                                            # Hash zur Erstellung der Readings
  
  my $params = {
      hash  => $hash,
      name  => $name,
      opt   => $opt,
      arg   => $arg,
      prop  => $prop,
      sizes => \%sizes
  };
   
  if($hset{$opt} && defined &{$hset{$opt}{fn}}) {
      my $ret = q{};  
      $ret    = &{$hset{$opt}{fn}} ($params);
      
      hide_tracks();
      
      if(%sizes) {
          delReadings ($name, 0);
          my $k = 1;
          
          readingsBeginUpdate ($hash);
          for my $key (sort {$b <=> $a} keys %sizes) {
              last if($k > $ml);
              readingsBulkUpdate ($hash, sprintf("%0${l}d", $k)."_largestObject", "$key, $sizes{$key}");
              $k++;
          }
          readingsBulkUpdate ($hash, "state", "done");
          readingsEndUpdate ($hash,1);
      }
      
      undef %sizes;
      return $ret if(!$noout);
      return;
  }
  
return "$setlist"; 
}

######################################################################################
#                                   Setter deviceType
######################################################################################
sub _setDeviceType {
  my $paref = shift;
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop};
  my $sizes = $paref->{sizes};                          # Hash zur Erstellung der Readings
  
  my $allt  = $prop // ".*";
    
  my @devs  = devspec2array ("TYPE=$allt");
  my $ret   = q{};
  
  my $params = {
      checkpars => { terse => 1 },
      name      => $name,
      sizes     => $sizes,
  };
  
  for my $dev (@devs) {
      next if(!$defs{$dev});
      $params->{txt} = "\$defs{$dev}";
      $params->{obj} = $defs{$dev};
      
      my $type = $defs{$dev}{TYPE};
      my $excl = checkExcludes ($type);                # problematische Module excludieren
      if($excl) {
          $ret .= $excl."\n";
          next;
      }
  
      $ret .= check ($params);    
  }
  
return $ret;
}

######################################################################################
#                                   Setter xHashDetail
######################################################################################
sub _setxHashDetail {
  my $paref = shift;
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};
  my $sizes = $paref->{sizes};                         # Hash zur Erstellung der Readings
  
  $arg      = AttrVal($name, "analyzeObject", $arg);
  
  return qq{The command "$opt" needs an argument.} if (!$arg);
  
  my ($a,$h)  = parseParams($arg);
  my ($htype) = @$a[0] =~ /^\$(.*?)(\{.*)?$/x;
  $htype      = $htype // "defs";
  
  my $params = {
      checkpars => { terse => 0 },
      name      => $name,
      sizes     => $sizes,
      aref      => $a,
      htype     => $htype,
  };
  
  my $ret = analyzeHashref ($params);
  
return $ret;
}

######################################################################################
#                                   Setter mainHash
######################################################################################
sub _setMainHash {
  my $paref = shift;
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $arg   = $paref->{arg};
  my $sizes = $paref->{sizes};                         # Hash zur Erstellung der Readings
  
  return qq{The command "$opt" needs an argument.} if (!$arg);
  
  my ($a,$h) = parseParams($arg);
  
  my $htype  = substr @$a[0], 1;
  
  my $params = {
      checkpars => { terse => 0 },
      name      => $name,
      sizes     => $sizes,
      aref      => $a,
      htype     => $htype,
  };
  
  my $ret = analyzeHashref ($params);
  
return $ret;
}

######################################################################################
#                   analysiere eine Hash Referenz
######################################################################################
sub analyzeHashref {
  my $paref     = shift;
  my $name      = $paref->{name};
  my $checkpars = $paref->{checkpars};
  my $sizes     = $paref->{sizes};                                       # Hash zur Erstellung der Readings
  my $aref      = $paref->{aref};                                        # Referenz zum auszuwertenden Objekt
  my $htype     = $paref->{htype} // return "got no Hash type";          # Typ des übergebenen Hash (defs, attr, ...)
  
  Log3($name, 4, "$name - Hash type recognized: $htype");

  my $ret    = q{};
  my @o      = @$aref;
  my ($ref,$txt);
  
  if($o[0] =~ m/^\$$htype/x) {
      $txt  = $o[0];
      $o[0] =~ s/^\$$htype//x;
      $o[0] =~ s/^\{//x;
      $o[0] =~ s/}$//x;
      @o    =  split /}\{/x, $o[0];
  }
  else {
      $txt = "\$$htype";
      
      for my $i (0 .. $#o) {
          $txt .= "{".$o[$i]."}";
      }
  }
  
  no strict "refs";                                            ## no critic 'NoStrict'  
  *{'FHEM::Analyze::'.$htype} = *{'main::'.$htype};
  use strict;
    
  no strict "refs";                                            ## no critic 'NoStrict'  
  $ref = \%{$htype};
  use strict;
  
  $ret = checkRef ($name, $ref);
  return $ret if($ret);
          
  for my $a (0 .. $#o) {
      $ret = checkRef ($name, $ref, $o[$a]);
      return $ret if($ret);

      $ref = $ref->{$o[$a]};
  }
  
  $paref->{txt} = $txt;
  $paref->{obj} = $ref;
  
return check ($paref);
}

################################################################
#                Analysesubroutine
################################################################
sub check {
  my $paref     = shift;
  my $obj       = $paref->{obj};
  my $name      = $paref->{name};
  my $checkpars = $paref->{checkpars};
  my $txt       = $paref->{txt};
  my $sizes     = $paref->{sizes};             # Hashref zur Erstellung Readings 
    
  my @ret;
  my $hash = $defs{$name};
  my $ref  = ref $obj; 
  
  my $rs       = report_size ($obj, $checkpars);
  my @elements = track_size  ($obj);                                            # für eigenes Parsing
  my $entries  = entries_per_element();
    
  my $r        = qq{Analyze result of object "$txt" (type: $ref) -> \n\n}.$rs;
  push @ret,$r."\n";
  
  my (%compnames,$compose);
  
  for (my $i=0; $i<scalar(@elements); $i+=$entries) {
      my ($rlvl, $rtype, $rsize, $roverh, $rname, $raddr, $rclass) = ($elements[$i+0],
                                                                      $elements[$i+1],
                                                                      $elements[$i+2],
                                                                      $elements[$i+3],
                                                                      $elements[$i+4],
                                                                      $elements[$i+5],
                                                                      $elements[$i+6]);
                                                                      
      Log3($name, 5, "$name - $rlvl, type: $rtype, size: $rsize, overhead: $roverh, name: ".($rname // q{})." , addr: $raddr, class: ".($rclass // q{}));
      
      if(!$rlvl) {
          undef %compnames;
      }          
          
      $compnames{$rlvl} = $rname // $txt;
      
      for (my $k=0; $k<=$rlvl; $k++) {
          $compose  = $compnames{0} if($k == 0);
          $compose .= "{".$compnames{$k}."}" if($k > 0);           
      } 
      
      $sizes->{$rsize} = $compose if($ref);
  }
    
return join("",@ret);
};

######################################################################################
#                   check evtl. excludierte Typen 
######################################################################################
sub checkExcludes {
  my $type = shift;

  if($hexcl{$type}) {
      return qq{Sorry, devices of TYPE "$type" cannot be analyzed at the moment because of Devel::Size error.};
  }
  
return;
}

######################################################################################
#                   check valide Referenz
#                  return undef wenn Referenz ok.
######################################################################################
sub checkRef {
  my $name = shift;
  my $oref = shift;
  my $obj  = shift;
  
  my $ref  = q{};
  
  if ($obj) {
      eval {$ref = ref $oref->{$obj}};
  }
  else {
      eval {$ref = ref $oref};
  }
  
  return if($ref ne q{});                   # Referenz ok
  
  my $ret = "no ref found. Dumper value:\n".Dumper $obj ? $oref->{$obj} : $oref;
  Log3($name, 4, "$name - $ret");
  
return $ret;
}

1;

=pod
=item summary    Module to check the size of FHEM data structure
=item summary_DE Modul zur Überprüfung der Größe der FHEM-Datenstruktur

=begin html

<a name="Analyze"></a>
<h3>Analyze</h3>
<ul>

</ul>

=end html
=begin html_DE

<a name="Analyze"></a>
<h3>Analyze</h3>
<ul>
 
</ul>

=end html_DE

=for :application/json;q=META.json 98_Analyze.pm
{
  "abstract": "Module to check the size of FHEM data structure.",
  "x_lang": {
    "de": {
      "abstract": "Modul zur Überprüfung der Größe der FHEM-Datenstruktur."
    }
  },
  "keywords": [
    "Analyze",
    "Cannot fork",
    "Memory",
    "Data",
    "Crash"
  ],
  "version": "v1.1.1",
  "release_status": "testing",
  "author": [
    "Heiko Maaz <heiko.maaz@t-online.de>"
  ],
  "x_fhem_maintainer": [
    "DS_Starter"
  ],
  "x_fhem_maintainer_github": [
    "nasseeder1"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014,
        "Data::Dumper": 0,
        "FHEM::SynoModules::SMUtils": 0,
        "GPUtils": 0,
        "Devel::Size::Report": 0,
        "utf8": 0
      },
      "recommends": {
        "FHEM::Meta": 0
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "x_wiki": {
      "web": "https://wiki.fhem.de/wiki/Analyze_-_Analyse_von_FHEM_Datenstrukturen",
      "title": "Analyze - Analyse von FHEM Datenstrukturen"
    },
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter/98_Analyze.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/fhem/trunk/fhem/contrib/DS_Starter/98_Analyze.pm"
      }      
    }
  }
}
=end :application/json;q=META.json

=cut
