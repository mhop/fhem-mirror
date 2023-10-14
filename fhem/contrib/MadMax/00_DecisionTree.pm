########################################################################################################################
# $Id$
#########################################################################################################################
#       00_DecisionTree.pm
#
#       (c) 2023 
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
#  Leerzeichen entfernen: sed -i 's/[[:space:]]*$//' 00_DecisionTree.pm
#
#########################################################################################################################
package FHEM::DecisionTree;                              ## no critic 'package'

use strict;
use warnings;
use POSIX;
use GPUtils qw(GP_Import GP_Export);                                                 # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use Time::HiRes qw(gettimeofday tv_interval);

eval "use FHEM::Meta;1"                   or my $modMetaAbsent = 1;                  ## no critic 'eval'
eval "use FHEM::Utility::CTZ qw(:all);1;" or my $ctzAbsent     = 1;                  ## no critic 'eval'

use Encode;
use Color;
use utf8;
use HttpUtils;
eval "use JSON;1;"                           or my $jsonabs = 'JSON';                ## no critic 'eval' # Debian: sudo apt-get install libjson-perl
eval "use Algorithm::DecisionTree;1;"        or my $aidtabs = 'Algorithm::DecisionTree';    ## no critic 'eval'
                           
use FHEM::SynoModules::SMUtils qw(
                                   evaljson
                                   getClHash
                                   delClHash
                                   moduleVersion
                                   trim
                                 );                                                  # Hilfsroutinen Modul

use Data::Dumper;
use Blocking;
use Storable qw(dclone freeze thaw nstore store retrieve); 
use MIME::Base64;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import(
      qw(
          attr
          asyncOutput
          AnalyzePerlCommand
          AnalyzeCommandChain
          AttrVal
          AttrNum
          BlockingCall
          BlockingKill
          CommandAttr
          CommandGet
          CommandSet
          CommandSetReading
          data
          defs
          delFromDevAttrList
          delFromAttrList
          devspec2array
          deviceEvents
          DoTrigger
          Debug
          fhemTimeLocal
          fhemTimeGm
          fhem
          FileWrite
          FileRead
          FileDelete
          FmtTime
          FmtDateTime
          FW_makeImage
          getKeyValue
          HttpUtils_NonblockingGet
          init_done
          InternalTimer
          IsDisabled
          Log
          Log3
          modules
          parseParams
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsDelete
          readingsEndUpdate
          ReadingsNum
          ReadingsTimestamp
          ReadingsVal
          RemoveInternalTimer
          readingFnAttributes
          setKeyValue
          sortTopicNum
          FW_cmd
          FW_directNotify
          FW_ME
          FW_subdir
          FW_room
          FW_detail
          FW_wname
        )
  );

  # Export to main context with different name
  #     my $pkg  = caller(0);
  #     my $main = $pkg;
  #     $main =~ s/^(?:.+::)?([^:]+)$/main::$1\_/g;
  #     foreach (@_) {
  #         *{ $main . $_ } = *{ $pkg . '::' . $_ };
  #     }
  GP_Export(
      qw(
          Initialize
          pageAsHtml
          NexthoursVal
        )
  );

}

# Versions History intern
my %vNotesIntern = (
  "0.1.0"  => "14.10.2023  initial Version "
);

## Konstanten
###############
my $aitrained      = $attr{global}{modpath}."/FHEM/FhemUtils/DecisionTree_tra_"; # Filename-Fragment für AI Trainingsdaten (wird mit Devicename ergänzt)
my $airaw          = $attr{global}{modpath}."/FHEM/FhemUtils/DecisionTree_raw_"; # Filename-Fragment für AI Input Daten = Raw Trainigsdaten

my $aitrblto       = 7200;                                                          # KI Training BlockingCall Timeout
my $aibcthhld      = 0.2;                                                           # Schwelle der KI Trainigszeit ab der BlockingCall benutzt wird
my $aistdudef      = 1095;                                                          # default Haltezeit KI Raw Daten (Tage)

################################################################
#               Init Fn
################################################################
sub Initialize {
  my $hash = shift;

  my $fwd  = join ",", devspec2array("TYPE=FHEMWEB:FILTER=STATE=Initialized");

  $hash->{DefFn}              = \&Define;
  $hash->{UndefFn}            = \&Undef;
  $hash->{GetFn}              = \&Get;
  $hash->{SetFn}              = \&Set;
  $hash->{DeleteFn}           = \&Delete;
  $hash->{FW_summaryFn}       = \&FwFn;
  $hash->{FW_detailFn}        = \&FwFn;
  $hash->{ShutdownFn}         = \&Shutdown;
  $hash->{DbLog_splitFn}      = \&DbLogSplit;
  $hash->{AttrFn}             = \&Attr;
  $hash->{NotifyFn}           = \&Notify;                                             
  $hash->{AttrList}           = "".
                                $readingFnAttributes;

 # $hash->{AttrRenameMap} = { ""
                          # };

  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };     ## no critic 'eval'

return;
}

###############################################################
#                  DecisionTree Define
###############################################################
sub Define {
  my ($hash, $def) = @_;

  my @a = split(/\s+/x, $def);

  return "Error: Perl module ".$jsonabs." is missing. Install it on Debian with: sudo apt-get install libjson-perl" if($jsonabs);
  return "Error: Perl module ".$aidtabs." is missing. Install it on Debian with: cpanm Algorithm::DecisionTree" if($aidtabs);
  

  # my $name                       = $hash->{NAME};
  # my $type                       = $hash->{TYPE};
  # $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                           # Modul Meta.pm nicht vorhanden

  # my $params = {
      # hash        => $hash,
      # name        => $hash->{NAME},
      # type        => $hash->{TYPE},
      # notes       => \%vNotesIntern,
  # };
  
  # $params->{file}       = $aitrained.$name;                                        # AI Cache File einlesen wenn vorhanden
  # $params->{cachename}  = 'aitrained';
  # _readCacheFile ($params); 
  
  # $params->{file}       = $airaw.$name;                                            # AI Rawdaten File einlesen wenn vorhanden
  # $params->{cachename}  = 'airaw';
  # _readCacheFile ($params);

return;
}

################################################################
#                   Cachefile lesen
################################################################
sub _readCacheFile {
  my $paref     = shift;
  my $hash      = $paref->{hash};
  my $name      = $paref->{name};
  my $type      = $paref->{type};
  my $file      = $paref->{file};
  my $cachename = $paref->{cachename};
  
  if ($cachename eq 'aitrained') {      
      my ($err, $dtree) = fileRetrieve ($file);
      
      if (!$err && $dtree) {
          my $valid = $dtree->isa('AI::DecisionTree');
          
          if ($valid) {
              $data{$type}{$name}{aidectree}{aitrained}  = $dtree;
              $data{$type}{$name}{current}{aitrainstate} = 'ok';
              Log3($name, 3, qq{$name - cached data "$cachename" restored}); 
          }
      }     

      return;      
  }
  
  if ($cachename eq 'airaw') {      
      my ($err, $data) = fileRetrieve ($file);
      
      if (!$err && $data) {          
          $data{$type}{$name}{aidectree}{airaw}     = $data;
          $data{$type}{$name}{current}{aitrawstate} = 'ok';
          Log3($name, 3, qq{$name - cached data "$cachename" restored}); 
      }     

      return;      
  }

  my ($error, @content) = FileRead ($file);

  if(!$error) {
      my $json      = join "", @content;
      my ($success) = evaljson ($hash, $json);

      if($success) {
           $data{$hash->{TYPE}}{$name}{$cachename} = decode_json ($json);
           Log3($name, 3, qq{$name - cached data "$cachename" restored});
      }
      else {
          Log3($name, 2, qq{$name - WARNING - The content of file "$file" is not readable and may be corrupt});
      }
  }

return;
}

################################################################
#  Funktion um mit Storable eine Struktur in ein File  
#  zu schreiben
################################################################
sub fileStore {
  my $obj  = shift;
  my $file = shift;

  my $err;
  my $ret = eval { nstore ($obj, $file) };                            
  
  if (!$ret || $@) {
      $err = $@ ? $@ : 'I/O problems or other internal error';
  } 

return $err;
}

################################################################
#  Funktion um mit Storable eine Struktur aus einem File  
#  zu lesen
################################################################
sub fileRetrieve {
  my $file = shift;
     
  my ($err, $obj);
  
  if (-e $file) {
      eval { $obj = retrieve ($file) };
      
      if (!$obj || $@) {
          $err = $@ ? $@ : 'I/O error while reading';
      }
  }  

return ($err, $obj);
}

###############################################################
#                  DecisionTree Set
###############################################################
sub Set {
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name  = shift @a;
  my $opt   = shift @a;
  my @args  = @a;
  my $arg   = join " ", map { my $p = $_; $p =~ s/\s//xg; $p; } @a;     ## no critic 'Map blocks'
  my $prop  = shift @a;
  my $prop1 = shift @a;
  my $prop2 = shift @a;

  return if(IsDisabled($name));
  my ($setlist);
  
  $setlist .= "aiDecTree:addInstances,addRawData,train ";

return "$setlist";
}

###############################################################
#                       Getter aiDecTree
###############################################################
sub _getaiDecTree {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $arg   = $paref->{arg} // return;
  
  my $ret;

  if($arg eq 'aiRawData') {
      $ret = listDataPool   ($hash, 'aiRawData');   
  }
  
  if($arg eq 'aiRuleStrings') {
      $ret = __getaiRuleStrings ($hash);  
  }
  
  $ret .= lineFromSpaces ($ret, 5);

return $ret;
}

################################################################
#  Gibt eine Liste von Zeichenketten zurück, die den AI 
#  Entscheidungsbaum in Form von Regeln beschreiben
################################################################
sub __getaiRuleStrings {                 ## no critic "not used"
  my $hash = shift;
  
  return 'the AI usage is not prepared' if(!isPrepared4AI ($hash));  
  
  my $dtree = AiDetreeVal ($hash, 'aitrained', undef);
  
  if (!$dtree) {
      return 'AI trained object is missed';
  }
  
  my $rs = 'no rules delivered';
  my @rsl;
                                     
  eval { @rsl = $dtree->rule_statements() 
       }
       or do { return $@;
             };
                   
  if (@rsl) {
      my $l = scalar @rsl;
      $rs   = "<b>Number of rules: ".$l."</b>";
      $rs  .= "\n\n";
      $rs  .= join "\n", @rsl;
  }

return $rs;
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

  if($aName eq 'disable') {
      if($cmd eq 'set') {
          $do = $aVal ? 1 : 0;
      }
      $do  = 0 if($cmd eq 'del');
      $val = ($do == 1 ? 'disabled' : 'initialized');
      singleUpdateState ( {hash => $hash, state => $val, evt => 1} );
  }

  my $params = {
      hash  => $hash,
      name  => $name,
      type  => $hash->{TYPE},
      cmd   => $cmd,
      aName => $aName,
      aVal  => $aVal
  };

return;
}

################################################################
#             Daten in File wegschreiben
################################################################
sub writeCacheToFile {
  my $hash      = shift;
  my $cachename = shift;
  my $file      = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  my @data;
  my ($error, $err, $lw);
  
  if ($cachename eq 'aitrained') {      
      my $dtree = AiDetreeVal ($hash, 'aitrained', '');
      return if(ref $dtree ne 'AI::DecisionTree');
      
      $error = fileStore ($dtree, $file);
      
      if ($error) {
          $err = qq{ERROR while writing AI data to file "$file": $error};
          Log3 ($name, 1, "$name - $err");
          return $err;
      }
      
      $lw                 = gettimeofday();
      $hash->{LCACHEFILE} = "last write time: ".FmtTime($lw)." File: $file";
      singleUpdateState ( {hash => $hash, state => "wrote cachefile $cachename successfully", evt => 1} );
     
      return;      
  }
  
  if ($cachename eq 'airaw') {      
      my $data = AiRawdataVal ($hash, '', '', '');
      
      if ($data) {
          $error = fileStore ($data, $file);
      }
      
      if ($error) {
          $err = qq{ERROR while writing AI data to file "$file": $error};
          Log3 ($name, 1, "$name - $err");
          return $err;
      }
      
      $lw                 = gettimeofday();
      $hash->{LCACHEFILE} = "last write time: ".FmtTime($lw)." File: $file";
      singleUpdateState ( {hash => $hash, state => "wrote cachefile $cachename successfully", evt => 1} );
     
      return;      
  }

  if ($cachename eq 'plantconfig') {
      @data = _savePlantConfig ($hash);
      return 'Plant configuration is empty, no data where written' if(!@data);
  }
  else {
      return if(!$data{$type}{$name}{$cachename});
      my $json = encode_json ($data{$type}{$name}{$cachename});
      push @data, $json;
  }

  $error = FileWrite ($file, @data);

  if ($error) {
      $err = qq{ERROR writing cache file "$file": $error};
      Log3 ($name, 1, "$name - $err");
      return $err;
  }

  $lw                 = gettimeofday();
  $hash->{LCACHEFILE} = "last write time: ".FmtTime($lw)." File: $file";
  singleUpdateState ( {hash => $hash, state => "wrote cachefile $cachename successfully", evt => 1} );

return;
}

################################################################
#  Voraussetzungen zur Nutzung der KI prüfen, Status setzen 
#  und Prüfungsergebnis (0/1) zurückgeben
################################################################
sub isPrepared4AI {
  my $hash = shift;
  my $full = shift // q{};                   # wenn true -> auch Auswertung ob on_.*_ai gesetzt ist
  
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $acu  = isAutoCorrUsed ($name);

  my $err;

  if(!isDWDUsed ($hash)) {
      $err = qq(The selected DecisionTree model cannot use AI support);
  }
  elsif ($aidtabs) {
      $err = qq(The Perl module AI::DecisionTree is missing. Please install it with e.g. "sudo apt-get install libai-decisiontree-perl" for AI support);
  }
  elsif ($full && $acu !~ /ai/xs) {
      $err = 'The setting of pvCorrectionFactor_Auto does not contain AI support';
  }  
  
  if ($err) {
      $data{$type}{$name}{current}{aicanuse} = $err;
      return 0;      
  }
 
  $data{$type}{$name}{current}{aicanuse} = 'ok';

return 1;
}

###################################################################################################
# Wert AI::DecisionTree Objects zurückliefern
# Usage:
# AiDetreeVal ($hash, key, $def)                        
#
# key: object     - das AI Object
#      aitrained  - AI trainierte Daten
#      airaw      - Rohdaten für AI Input = Raw Trainigsdaten
#
# $def:  Defaultwert
#
###################################################################################################
sub AiDetreeVal {                   
  my $hash = shift;
  my $key  = shift;
  my $def  = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  if (defined $data{$type}{$name}{aidectree}   &&
      defined $data{$type}{$name}{aidectree}{$key}) {
      return  $data{$type}{$name}{aidectree}{$key};
  }

return $def;
}

################################################################
#       AI Instanz für die abgeschlossene Stunde hinzufügen
################################################################
sub _addHourAiRawdata {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $chour = $paref->{chour};
  my $daref = $paref->{daref};

  for my $h (1..23) {
      next if(!$chour || $h > $chour);
      
      my $rho = sprintf "%02d", $h;
      my $sr  = ReadingsVal ($name, ".signaldone_".$rho, "");
      
      next if($sr eq "done");
      
      $paref->{ood} = 1;
      $paref->{rho} = $rho;
      
      aiAddRawData ($paref);                                          # Raw Daten für AI hinzufügen und sichern
      
      delete $paref->{ood};
      delete $paref->{rho};     
  
      push @$daref, ".signaldone_".sprintf("%02d",$h)."<>done";
  }
  
return;
}

###############################################################
#    Eintritt in den KI Train Prozess normal/Blocking
###############################################################
sub manageTrain {
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};

 delete $hash->{HELPER}{AIBLOCKRUNNING} if(defined $hash->{HELPER}{AIBLOCKRUNNING}{pid} && $hash->{HELPER}{AIBLOCKRUNNING}{pid} =~ /DEAD/xs);

 if (defined $hash->{HELPER}{AIBLOCKRUNNING}{pid}) {
	 Log3 ($name, 3, qq{$name - another AI Training with PID "$hash->{HELPER}{AIBLOCKRUNNING}{pid}" is already running ... start Training aborted});
	 return;
 }

 $paref->{block} = 1;
 
 $hash->{HELPER}{AIBLOCKRUNNING} = BlockingCall ( "FHEM::DecisionTree::aiTrain",
												  $paref,
												  "FHEM::DecisionTree::finishTrain",
												  $aitrblto,
												  "FHEM::DecisionTree::abortTrain",
												  $hash
												);


 if (defined $hash->{HELPER}{AIBLOCKRUNNING}) {
	 $hash->{HELPER}{AIBLOCKRUNNING}{loglevel} = 3;                                                       # Forum https://forum.fhem.de/index.php/topic,77057.msg689918.html#msg689918

	 debugLog ($paref, 'aiProcess', qq{AI Training BlockingCall PID "$hash->{HELPER}{AIBLOCKRUNNING}{pid}" with Timeout "$aitrblto" started});
 }

return;
}

###############################################################
#    Restaufgaben nach Update
###############################################################
sub finishTrain {
  my $serial = decode_base64 (shift);

  my $paref = eval { thaw ($serial) };                                             # Deserialisierung  
  my $name  = $paref->{name};
  my $hash  = $defs{$name};
  my $type  = $hash->{TYPE};
  
  delete($hash->{HELPER}{AIBLOCKRUNNING}) if(defined $hash->{HELPER}{AIBLOCKRUNNING});
  
  my $aicanuse       = $paref->{aicanuse};
  my $aiinitstate    = $paref->{aiinitstate};
  my $aitrainstate   = $paref->{aitrainstate};
  my $runTimeTrainAI = $paref->{runTimeTrainAI};
  
  $data{$type}{$name}{current}{aicanuse}            = $aicanuse       if(defined $aicanuse);
  $data{$type}{$name}{current}{aiinitstate}         = $aiinitstate    if(defined $aiinitstate);
  $data{$type}{$name}{circular}{99}{runTimeTrainAI} = $runTimeTrainAI if(defined $runTimeTrainAI);  # !! in Circular speichern um zu persistieren, setTimeTracking speichert zunächst in Current !!
  
  if ($aitrainstate eq 'ok') {
      _readCacheFile ({ hash      => $hash,
                        name      => $name,
                        type      => $type,
                        file      => $aitrained.$name,
                        cachename => 'aitrained'
                      }
                     );
  }

return;
}

####################################################################################################
#                    Abbruchroutine BlockingCall Timeout
####################################################################################################
sub abortTrain {
  my $hash   = shift;
  my $cause  = shift // "Timeout: process terminated";
  my $name   = $hash->{NAME};
  my $type   = $hash->{TYPE};

  Log3 ($name, 1, "$name -> BlockingCall $hash->{HELPER}{AIBLOCKRUNNING}{fn} pid:$hash->{HELPER}{AIBLOCKRUNNING}{pid} aborted: $cause");
  
  delete($hash->{HELPER}{AIBLOCKRUNNING});
  
  $data{$type}{$name}{current}{aitrainstate} = 'Traing (Child) process timed out';

return;
}

################################################################
#     KI Instanz(en) aus Raw Daten Hash
#     $data{$type}{$name}{aidectree}{airaw} hinzufügen
################################################################
sub aiAddInstance {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $taa   = $paref->{taa};          # do train after add
  
  return if(!isPrepared4AI ($hash));
  
  my $err;
  my $dtree = AiDetreeVal ($hash, 'object', undef);
  
  if (!$dtree) {
      $err = aiInit ($paref);
      return if($err);
      $dtree = AiDetreeVal ($hash, 'object', undef);
  }
  
  for my $idx (sort keys %{$data{$type}{$name}{aidectree}{airaw}}) {
      next if(!$idx);      
      
      my $pvrl = AiRawdataVal ($hash, $idx, 'pvrl', undef);
      next if(!defined $pvrl);
      
      my $hod  = AiRawdataVal ($hash, $idx, 'hod', undef);
      next if(!defined $hod);
      
      my $rad1h = AiRawdataVal ($hash, $idx, 'rad1h', 0);
      next if($rad1h <= 0);
      
      my $temp  = AiRawdataVal ($hash, $idx, 'temp', 20);
      my $wcc   = AiRawdataVal ($hash, $idx, 'wcc',   0);
      my $wrp   = AiRawdataVal ($hash, $idx, 'wrp',   0);
      
      eval { $dtree->add_instance (attributes => { rad1h => $rad1h,
                                                   temp  => $temp,
                                                   wcc   => $wcc,
                                                   wrp   => $wrp,
                                                   hod   => $hod
                                                 },
                                                 result => $pvrl
                                  )
           }
           or do { Log3 ($name, 1, "$name - aiAddInstance ERROR: $@");
                   $data{$type}{$name}{current}{aiaddistate} = $@;
                   return;
                 };
      
      debugLog ($paref, 'aiProcess', qq{AI Instance added - hod: $hod, rad1h: $rad1h, pvrl: $pvrl, wcc: $wcc, wrp: $wrp, temp: $temp}); 
  }
  
  $data{$type}{$name}{aidectree}{object}    = $dtree;
  $data{$type}{$name}{current}{aiaddistate} = 'ok';
  
  if ($taa) {
      manageTrain ($paref);
  }
  
return;
}

################################################################
#     KI trainieren
################################################################
sub aiTrain {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $block = $paref->{block} // 0;
  
  my $serial;
  
  if (!isPrepared4AI ($hash)) {
      my $err = CurrentVal ($hash, 'aicanuse', '');
      $serial = encode_base64 (Serialize ( {name => $name, aicanuse => $err} ), "");
      $block ? return ($serial) : return \&finishTrain ($serial);
  }
  
  my $cst = [gettimeofday];                                           # Zyklus-Startzeit
  
  my $err;
  my $dtree = AiDetreeVal ($hash, 'object', undef);
  
  if (!$dtree) {
      $err = aiInit ($paref);
      
      if ($err) {      
          $serial = encode_base64 (Serialize ( {name => $name, aiinitstate => $err} ), "");
          $block ? return ($serial) : return \&finishTrain ($serial);
      }
      
      $dtree = AiDetreeVal ($hash, 'object', undef);
  }
  
  eval { $dtree->train
       }
       or do { Log3 ($name, 1, "$name - aiTrain ERROR: $@");
               $data{$type}{$name}{current}{aitrainstate} = $@;
               $serial = encode_base64 (Serialize ( {name => $name, aitrainstate => $@} ), "");
               $block ? return ($serial) : return \&finishTrain ($serial);
             };
  
  $data{$type}{$name}{aidectree}{aitrained} = $dtree;
  $err                                      = writeCacheToFile ($hash, 'aitrained', $aitrained.$name); 
  
  if (!$err) {
      debugLog ($paref, 'aiData',    qq{AI trained: }.Dumper $data{$type}{$name}{aidectree}{aitrained});
      debugLog ($paref, 'aiProcess', qq{AI trained and saved data into file: }.$aitrained.$name);
      debugLog ($paref, 'aiProcess', qq{Training instances and their associated information where purged from the AI object});
      $data{$type}{$name}{current}{aitrainstate} = 'ok';
  }
  
  setTimeTracking ($hash, $cst, 'runTimeTrainAI');                   # Zyklus-Laufzeit ermitteln
  
  $serial = encode_base64 (Serialize ( {name           => $name, 
                                        aitrainstate   => CurrentVal ($hash, 'aitrainstate',   ''),
                                        runTimeTrainAI => CurrentVal ($hash, 'runTimeTrainAI', '')
                                       } 
                                     )
                                     , "");

  delete $data{$type}{$name}{current}{runTimeTrainAI};                                    
                                     
  $block ? return ($serial) : return \&finishTrain ($serial);
  
return;
}

################################################################
#     AI Ergebnis für ermitteln
################################################################
sub aiGetResult {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $hod   = $paref->{hod};
  my $nhidx = $paref->{nhidx};
  
  return 'the AI usage is not prepared' if(!isPrepared4AI ($hash, 'full')); 
  
  my $dtree = AiDetreeVal ($hash, 'aitrained', undef);
  
  if (!$dtree) {
      return 'AI trained object is missed';
  }
  
  my $rad1h = NexthoursVal ($hash, $nhidx, "rad1h", 0);
  return "no rad1h for hod: $hod" if($rad1h <= 0);
  
  my $wcc  = NexthoursVal ($hash, $nhidx, "cloudcover",  0);
  my $wrp  = NexthoursVal ($hash, $nhidx, "rainprob",    0);
  my $temp = NexthoursVal ($hash, $nhidx, "temp",       20);
  
  my $tbin = temp2bin  ($temp);
  my $cbin = cloud2bin ($wcc);
  my $rbin = rain2bin  ($wrp);
  
  my $pvaifc;
                                     
  eval { $pvaifc = $dtree->get_result (attributes => { rad1h => $rad1h,
                                                       temp  => $tbin,
                                                       wcc   => $cbin,
                                                       wrp   => $rbin,
                                                       hod   => $hod
                                                     }
                                      );
       };
                   
  if ($@) {
      Log3 ($name, 1, "$name - aiGetResult ERROR: $@");
      return $@;
  }
                                  
  if (defined $pvaifc) {
      debugLog ($paref, 'aiData', qq{result AI: pvaifc: $pvaifc (hod: $hod, rad1h: $rad1h, wcc: $wcc, wrp: $rbin, temp: $tbin)});
      return ('', $pvaifc);
  }

return 'no decition delivered';
}

################################################################
#     KI initialisieren
################################################################
sub aiInit {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  
  if (!isPrepared4AI ($hash)) {
      my $err = CurrentVal ($hash, 'aicanuse', '');
      
      debugLog ($paref, 'aiProcess', $err);
      
      $data{$type}{$name}{current}{aiinitstate} = $err;
      return $err;      
  }
  
  my $dtree = new AI::DecisionTree ( verbose => 0, noise_mode => 'pick_best' );
                
  $data{$type}{$name}{aidectree}{object}    = $dtree;
  $data{$type}{$name}{current}{aiinitstate} = 'ok';
  
  Log3 ($name, 3, "$name - AI::DecisionTree initialized");
  
return;
}

################################################################
#    Daten der Raw Datensammlung hinzufügen
################################################################
sub aiAddRawData {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  my $ood   = $paref->{ood} // 0;     # only one (current) day
  my $rho   = $paref->{rho};          # only this hour of day
  
  delete $data{$type}{$name}{current}{aitrawstate};
  
  my ($err, $dosave);
  
  for my $pvd (sort keys %{$data{$type}{$name}{pvhist}}) {
      next if(!$pvd);
      if ($ood) {
          next if($pvd ne $paref->{day});
      }
      
      for my $hod (sort keys %{$data{$type}{$name}{pvhist}{$pvd}}) {
          next if(!$hod || $hod eq '99' || ($rho && $hod ne $rho));
          
          my $rad1h = HistoryVal ($hash, $pvd, $hod, 'rad1h', undef);
          next if(!$rad1h || $rad1h <= 0);
          
          my $pvrl  = HistoryVal ($hash, $pvd, $hod, 'pvrl', undef);
          next if(!$pvrl || $pvrl <= 0);
          
          my $ridx = _aiMakeIdxRaw ($pvd, $hod);
          
          my $temp = HistoryVal ($hash, $pvd, $hod, 'temp', 20);
          my $wcc  = HistoryVal ($hash, $pvd, $hod, 'wcc',   0);
          my $wrp  = HistoryVal ($hash, $pvd, $hod, 'wrp',   0);
          
          my $tbin = temp2bin  ($temp);
          my $cbin = cloud2bin ($wcc);
          my $rbin = rain2bin  ($wrp);
          
          $data{$type}{$name}{aidectree}{airaw}{$ridx}{rad1h} = $rad1h;
          $data{$type}{$name}{aidectree}{airaw}{$ridx}{temp}  = $tbin;
          $data{$type}{$name}{aidectree}{airaw}{$ridx}{wcc}   = $cbin;
          $data{$type}{$name}{aidectree}{airaw}{$ridx}{wrp}   = $rbin;
          $data{$type}{$name}{aidectree}{airaw}{$ridx}{hod}   = $hod;
          $data{$type}{$name}{aidectree}{airaw}{$ridx}{pvrl}  = $pvrl;
          
          $dosave = 1;
          
          debugLog ($paref, 'aiProcess', qq{AI Raw data added - idx: $ridx, day: $pvd, hod: $hod, rad1h: $rad1h, pvrl: $pvrl, wcc: $cbin, wrp: $rbin, temp: $tbin}); 
      }
  }
  
  if ($dosave) {
      $err = writeCacheToFile ($hash, 'airaw', $airaw.$name);
      
      if (!$err) {
          $data{$type}{$name}{current}{aitrawstate} = 'ok';
          debugLog ($paref, 'aiProcess', qq{AI raw data saved into file: }.$airaw.$name);
      }
  }
  
return;
}

################################################################
#    Daten aus Raw Datensammlung löschen welche die maximale
#    Haltezeit (Tage) überschritten haben
################################################################
sub aiDelRawData {                   
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $type  = $paref->{type};
  
  if (!keys %{$data{$type}{$name}{aidectree}{airaw}}) {
      return;
  }
  
  my $hd   = AttrVal ($name, 'ctrlAIdataStorageDuration', $aistdudef);          # Haltezeit KI Raw Daten (Tage)
  my $ht   = time - ($hd * 86400);
  my $day  = strftime "%d", localtime($ht);
  my $didx = _aiMakeIdxRaw ($day, '00', $ht);                                   # Daten mit idx <= $didx löschen
  
  debugLog ($paref, 'aiProcess', qq{AI Raw delete data equal or less than index >$didx<}); 
  
  delete $data{$type}{$name}{current}{aitrawstate};
  
  my ($err, $dosave);
  
  for my $idx (sort keys %{$data{$type}{$name}{aidectree}{airaw}}) {
      next if(!$idx || $idx > $didx);
      delete $data{$type}{$name}{aidectree}{airaw}{$idx};
      
      $dosave = 1;
      
      debugLog ($paref, 'aiProcess', qq{AI Raw data deleted - idx: $idx}); 
  }
  
  if ($dosave) {
      $err = writeCacheToFile ($hash, 'airaw', $airaw.$name);
      
      if (!$err) {
          $data{$type}{$name}{current}{aitrawstate} = 'ok';
          debugLog ($paref, 'aiProcess', qq{AI raw data saved into file: }.$airaw.$name);
      }
  }
  
return;
}

################################################################
#  den Index für AI raw Daten erzeugen
################################################################
sub _aiMakeIdxRaw {
  my $day = shift; 
  my $hod = shift;
  my $t   = shift // time;

  my $ridx = strftime "%Y%m", localtime($t);
  $ridx   .= $day.$hod;

return $ridx;
}

###################################################################################################
# Wert AI Raw Data zurückliefern
# Usage:
# AiRawdataVal ($hash, $idx, $key, $def)   
# AiRawdataVal ($hash, '', '', $def)      -> den gesamten Hash airaw lesen
#
# $idx:            - Index
# $key: rad1h      - Strahlungsdaten
#       temp       - Temeperatur als Bin
#       wcc        - Bewölkung als Bin
#       wrp        - Regenwert als Bin
#       hod        - Stunde des Tages
#       pvrl       - reale PV Erzeugung
#
# $def:  Defaultwert
#
###################################################################################################
sub AiRawdataVal {                   
  my $hash = shift;
  my $idx  = shift;
  my $key  = shift;
  my $def  = shift;

  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  if (!$idx && !$key) {
      if (defined $data{$type}{$name}{aidectree}{airaw}) {
          return  $data{$type}{$name}{aidectree}{airaw};
      }   
  }

  if (defined $data{$type}{$name}{aidectree}{airaw}          &&
      defined $data{$type}{$name}{aidectree}{airaw}{$idx}    &&
      defined $data{$type}{$name}{aidectree}{airaw}{$idx}{$key}) {
      return  $data{$type}{$name}{aidectree}{airaw}{$idx}{$key};
  }

return $def;
}

1;

=pod
=item summary    Visualization of solar predictions for PV systems and Consumer control
=item summary_DE Visualisierung von solaren Vorhersagen für PV Anlagen und Verbrauchersteuerung

=begin html

<a id="DecisionTree"></a>
<h3>DecisionTree</h3>
<br>

=end html
=begin html_DE

<a id="DecisionTree"></a>
<h3>DecisionTree</h3>
<br>


=end html_DE

=for :application/json;q=META.json 76_SolarForecast.pm
{
  "abstract": "Creation of solar forecasts of PV systems including consumption forecasts and consumer management",
  "x_lang": {
    "de": {
      "abstract": "Erstellung solarer Vorhersagen von PV Anlagen inklusive Verbrauchsvorhersagen und Verbrauchermanagement"
    }
  },
  "keywords": [
    "inverter",
    "photovoltaik",
    "electricity",
    "forecast",
    "graphics",
    "Autarky",
    "Consumer",
    "PV"
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
        "POSIX": 0,
        "GPUtils": 0,
        "Encode": 0,
        "Blocking": 0,
        "Color": 0,
        "utf8": 0,
        "HttpUtils": 0,
        "JSON": 4.020,
        "FHEM::SynoModules::SMUtils": 1.0220,
        "Time::HiRes": 0,
        "MIME::Base64": 0,
        "Storable": 0        
      },
      "recommends": {
        "FHEM::Meta": 0,
        "FHEM::Utility::CTZ": 1.00,
        "DateTime": 0,
        "DateTime::Format::Strptime": 0,
        "AI::DecisionTree": 0,
        "Data::Dumper": 0
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "x_wiki": {
      "web": "https://wiki.fhem.de/wiki/SolarForecast_-_Solare_Prognose_(PV_Erzeugung)_und_Verbrauchersteuerung",
      "title": "DecisionTree - Solare Prognose (PV Erzeugung) und Verbrauchersteuerung"
    },
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter/76_SolarForecast.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/fhem/trunk/fhem/contrib/DS_Starter/76_SolarForecast.pm"
      }
    }
  }
}
=end :application/json;q=META.json

=cut
