##############################################################################################################################
# $Id: 93_DbLog.pm 28085 2023-10-22 14:22:29Z DS_Starter $
##############################################################################################################################
# 93_DbLog.pm
# written by Dr. Boris Neubert 2007-12-30
# e-mail: omega at online dot de
#
# modified and maintained by Tobias Faust since 2012-06-26 until 2016
# e-mail: tobias dot faust at online dot de
#
# redesigned and maintained 2016-2023 by DS_Starter
# e-mail: heiko dot maaz at t-online dot de
#
# reduceLog() created by Claudiu Schuster (rapster) adapted by DS_Starter
#       
# This script is part of fhem.
#
# Fhem is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# Fhem is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
# This copyright notice MUST APPEAR in all copies of the script!
#
##############################################################################################################################
#
#  Leerzeichen entfernen: sed -i 's/[[:space:]]*$//' 93_DbLog.pm
#
##############################################################################################################################

package main;
use strict;
use warnings;
eval "use DBI;1;"                                or my $DbLogMMDBI    = "DBI";              ## no critic 'eval'
eval "use FHEM::Meta;1;"                         or my $modMetaAbsent = 1;                  ## no critic 'eval'
eval "use FHEM::Utility::CTZ qw(:all);1;"        or my $ctzAbsent     = 1;                  ## no critic 'eval'
eval "use Storable qw(freeze thaw);1;"           or my $storabs       = "Storable";         ## no critic 'eval'

#use Data::Dumper;
use Scalar::Util qw(looks_like_number);
use Time::HiRes qw(gettimeofday tv_interval usleep);
use Time::Local;
use Encode qw(encode_utf8);
use HttpUtils;
use SubProcess;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

# Version History intern by DS_Starter:
my %DbLog_vNotesIntern = (
  "5.9.4"   => "27.12.2023 make EVENT writable ",
  "5.9.3"   => "09.10.2023 new attribute colType ",
  "5.9.2"   => "09.10.2023 edit commandref, Forum: https://forum.fhem.de/index.php?msg=1288840 ",
  "5.9.1"   => "15.08.2023 possible use of alternative tables in _DbLog_plotData Forum:134547, fix warnings in ".
                           "_DbLog_SBP_onRun_LogSequential Forum:https://forum.fhem.de/index.php?msg=1284228 ",
  "5.9.0"   => "16.05.2023 Server shutdown -> write cachefile if database connect can't be done during delayed shutdown ". 
                           "Forum: https://forum.fhem.de/index.php?topic=133599.0 ",
  "5.8.8"   => "11.05.2023 _DbLog_ParseEvent changed default splitting, Forum: https://forum.fhem.de/index.php?topic=133537.0 ",
  "5.8.7"   => "01.05.2023 new Events FRAME_INITIALIZED, SUBPROC_INITIALIZED, SUBPROC_DISCONNECTED, SUBPROC_STOPPED ".
                           "Forum: https://forum.fhem.de/index.php?topic=133403.0, minor fixes ",
  "5.8.6"   => "25.03.2023 change _DbLog_plotData (intx), Plot Editor: include functions delta-h, delta-h, ...".
                           "remove setter deleteOldDaysNbl, reduceLogNbl ",
  "5.8.5"   => "16.03.2023 fix using https in configCheck after SVN server change ",
  "5.8.4"   => "20.02.2023 new attr plotInputFieldLength, improve Plot Editor, delete attr noNotifyDev ".
                           "move notifyRegexpChanged from Define to initOnStart ",
  "5.8.3"   => "19.02.2023 adapt DbLog_configcheck, new get ... configCheck, commandref edited ",
  "5.8.2"   => "18.02.2023 adapt DbLog_configcheck, Forum: https://forum.fhem.de/index.php/topic,132163.msg1264320.html#msg1264320 ",
  "5.8.1"   => "13.02.2023 change field type of DbLogInclude, DbLogExclude to textField-long, configCheck evaluate collation ".
                           "_DbLog_SBP_connectDB: UTF8 -> evaluate DB character/collation set and use it for ".
                           "setting names connection collation ",
  "5.8.0"   => "30.01.2023 new Get menu for a selection of getters, fix creation of new subprocess during shutdown sequence ",
  "5.7.0"   => "25.01.2023 send Log3() data back ro parent process, improve _DbLog_dbReadings function ",
  "5.6.2"   => "22.01.2023 check Syntax of DbLogValueFn attribute with Log output, Forum:#131777 ",
  "5.6.1"   => "16.01.2023 rewrite sub _DbLog_SBP_connectDB, rewrite sub DbLog_ExecSQL, _DbLog_SBP_onRun_deleteOldDays ",
  "5.6.0"   => "11.01.2023 rename attribute 'bulkInsert' to 'insertMode' ",
  "5.5.12"  => "10.01.2023 changed routine _DbLog_SBP_onRun_LogSequential, edit CommandRef ",
  "5.5.11"  => "09.01.2023 more code rework / structured subroutines ",
  "5.5.10"  => "07.01.2023 more code rework (_DbLog_SBP_checkDiscDelpars) and others, use dbh quote in _DbLog_SBP_onRun_LogSequential ".
                           "configCheck changed to use only one db connect + measuring the connection time, universal DBHU ",
  "5.5.9"   => "28.12.2022 optimize \$hash->{HELPER}{TH}, \$hash->{HELPER}{TC}, mode in Define ".
                           "Forum: https://forum.fhem.de/index.php/topic,130588.msg1254073.html#msg1254073 ",
  "5.5.8"   => "27.12.2022 two-line output of long state messages, define LONGRUN_PID threshold ",
  "5.5.7"   => "20.12.2022 cutted _DbLog_SBP_onRun_Log into _DbLog_SBP_onRun_LogArray and _DbLog_SBP_onRun_LogSequential ".
               "__DbLog_SBP_onRun_LogCurrent, __DbLog_SBP_fieldArrays, some bugfixes, add drivers to configCheck, edit comref ",
  "5.5.6"   => "12.12.2022 Serialize with Storable instead of JSON, more code rework ",
  "5.5.5"   => "11.12.2022 Array Log -> may be better error processing ",
  "5.5.4"   => "11.12.2022 Array Log -> print out all cache not saved, DbLog_DelayedShutdown processing changed ",
  "5.5.3"   => "10.12.2022 more internal code rework ",
  "5.5.2"   => "09.12.2022 _DbLog_ConnectPush function removed ",
  "5.5.1"   => "09.12.2022 commit inserted lines in array insert though some lines are faulty ",
  "5.5.0"   => "08.12.2022 implement commands with SBP: reduceLog, reduceLogNbL, attr timeout adapted ",
  "5.4.0"   => "07.12.2022 implement commands with SBP: importCacheFile ",
  "5.3.0"   => "05.12.2022 activate func _DbLog_SBP_onRun_Log, implement commands with SBP: count(Nbl), deleteOldDays(Nbl) ".
                           "userCommand, exportCache ",
  "5.2.0"   => "05.12.2022 LONGRUN_PID, \$hash->{prioSave}, rework SetFn ",
  "5.1.0"   => "03.12.2022 implement SubProcess for logging data in synchron Mode ",
  "5.0.0"   => "02.12.2022 implement SubProcess for logging data in asynchron Mode, delete attr traceHandles ",
  "4.13.3"  => "26.11.2022 revise commandref ",
  "4.13.2"  => "06.11.2022 Patch Delta calculation (delta-d,delta-h) https://forum.fhem.de/index.php/topic,129975.msg1242272.html#msg1242272 ",
  "4.13.1"  => "16.10.2022 edit commandref ",
  "4.13.0"  => "15.04.2022 new Attr convertTimezone, minor fixes in reduceLog(NbL) ",
  "4.12.7"  => "08.03.2022 \$data{firstvalX} doesn't work, forum: https://forum.fhem.de/index.php/topic,126631.0.html ",
  "4.12.6"  => "17.01.2022 change log message deprecated to outdated, forum:#topic,41089.msg1201261.html#msg1201261 ",
  "4.12.5"  => "31.12.2021 standard unit assignment for readings beginning with 'temperature' and removed, forum:#125087 ",
  "4.12.4"  => "27.12.2021 change ParseEvent for FBDECT, warning messages for deprecated commands added ",
  "4.12.3"  => "20.04.2021 change sub _DbLog_getNewDBHandle for SQLITE, change error Logging in DbLog_writeFileIfCacheOverflow ",
  "4.12.2"  => "08.04.2021 change standard splitting ",
  "4.12.1"  => "07.04.2021 improve escaping the pipe ",
  "4.12.0"  => "29.03.2021 new attributes SQLiteCacheSize, SQLiteJournalMode ",
  "4.11.0"  => "20.02.2021 new attr cacheOverflowThreshold, reading CacheOverflowLastNum/CacheOverflowLastState, ".
                           "remove prototypes, new subs DbLog_writeFileIfCacheOverflow, DbLog_setReadingstate ",
  "4.10.2"  => "23.06.2020 configCheck changed for SQLite again ",
  "4.10.1"  => "22.06.2020 configCheck changed for SQLite ",
  "4.10.0"  => "22.05.2020 improve configCheck, new vars \$LASTTIMESTAMP and \$LASTVALUE in valueFn / DbLogValueFn, Forum:#111423 ",
  "4.9.13"  => "12.05.2020 commandRef changed, AutoInactiveDestroy => 1 for dbh ",
  "4.9.12"  => "28.04.2020 fix line breaks in set function, Forum: #110673 ",
  "4.9.11"  => "22.03.2020 logfile entry if DBI module not installed, Forum: #109382 ",
  "4.9.10"  => "31.01.2020 fix warning, Forum: #107950 ",
  "4.9.9"   => "21.01.2020 default ParseEvent changed again, Forum: #106769 ",
  "4.9.8"   => "17.01.2020 adjust configCheck with plotEmbed check. Forum: #107383 ",
  "4.9.7"   => "13.01.2020 change datetime pattern in valueFn of DbLog_addCacheLine. Forum: #107285 ",
  "4.9.6"   => "04.01.2020 fix change off 4.9.4 in default splitting. Forum: #106992 ",
  "4.9.5"   => "01.01.2020 do not reopen database connection if device is disabled (fix) ",
  "4.9.4"   => "08.01.2023 all version informationen from v 1.8.1 to v 4.9.4 deleted ",
  "1.7.1"   => "15.12.2016 initial rework "
);

# Steuerhashes
###############

my %DbLog_hset = (                                                                # Hash der Set-Funktion
  listCache        => { fn => \&_DbLog_setlistCache       },
  clearReadings    => { fn => \&_DbLog_setclearReadings   },
  eraseReadings    => { fn => \&_DbLog_seteraseReadings   },
  stopSubProcess   => { fn => \&_DbLog_setstopSubProcess  },
  purgeCache       => { fn => \&_DbLog_setpurgeCache      },
  commitCache      => { fn => \&_DbLog_setcommitCache     },
  configCheck      => { fn => \&DbLog_configcheck         },
  reopen           => { fn => \&_DbLog_setreopen          },
  rereadcfg        => { fn => \&_DbLog_setrereadcfg       },
  addLog           => { fn => \&_DbLog_setaddLog          },
  addCacheLine     => { fn => \&_DbLog_setaddCacheLine    },
  count            => { fn => \&_DbLog_setcount           },
  countNbl         => { fn => \&_DbLog_setcount           },
  deleteOldDays    => { fn => \&_DbLog_setdeleteOldDays   },
  deleteOldDaysNbl => { fn => \&_DbLog_setdeleteOldDays   },
  userCommand      => { fn => \&_DbLog_setuserCommand     },
  exportCache      => { fn => \&_DbLog_setexportCache     },
  importCachefile  => { fn => \&_DbLog_setimportCachefile },
  reduceLog        => { fn => \&_DbLog_setreduceLog       },
  reduceLogNbl     => { fn => \&_DbLog_setreduceLog       },
);

my %DbLog_hget = (                                                                # Hash der Get-Funktion
  ReadingsVal             => { fn => \&_DbLog_dbReadings   },
  ReadingsTimestamp       => { fn => \&_DbLog_dbReadings   },
  ReadingsValTimestamp    => { fn => \&_DbLog_dbReadings   },
  ReadingsMaxVal          => { fn => \&_DbLog_dbReadings   },
  ReadingsMaxValTimestamp => { fn => \&_DbLog_dbReadings   },
  ReadingsMinVal          => { fn => \&_DbLog_dbReadings   },
  ReadingsMinValTimestamp => { fn => \&_DbLog_dbReadings   },
  ReadingsAvgVal          => { fn => \&_DbLog_dbReadings   },
  webchart                => { fn => \&_DbLog_chartQuery   },
  plotdata                => { fn => \&_DbLog_plotData     },
  retrieve                => { fn => \&_DbLog_chartQuery   },
  configCheck             => { fn => \&DbLog_configcheck   },
);

my %DbLog_columns = ("DEVICE"  => 64,
                     "TYPE"    => 64,
                     "EVENT"   => 512,
                     "READING" => 64,
                     "VALUE"   => 128,
                     "UNIT"    => 32
                    );

# Defaultwerte
###############
my $dblog_cachedef = 500;                                                       # default Größe cacheLimit bei asynchronen Betrieb
my $dblog_cmdef    = 'basic_ta:on';                                             # default commitMode
my $dblog_todef    = 86400;                                                     # default timeout Sekunden
my $dblog_lrpth    = 0.8;                                                       # Schwellenwert für LONGRUN_PID ab dem "Another operation is in progress...." im state ausgegeben wird
my $dblog_pifl     = 40;                                                        # default Breite Eingabefelder im Plot Editor
my $dblog_svgfnset = ',delta-d,delta-h,delta-ts,int,int1,int2,int3,int4,int5';  # Funktionen für SVG sampleDataFn

################################################################
sub DbLog_Initialize {
  my $hash = shift;

  $hash->{DefFn}             = "DbLog_Define";
  $hash->{UndefFn}           = "DbLog_Undef";
  $hash->{NotifyFn}          = "DbLog_Log";
  $hash->{SetFn}             = "DbLog_Set";
  $hash->{GetFn}             = "DbLog_Get";
  $hash->{AttrFn}            = "DbLog_Attr";
  $hash->{ReadFn}            = "DbLog_SBP_Read";
  $hash->{SVG_regexpFn}      = "DbLog_regexpFn";
  $hash->{DelayedShutdownFn} = "DbLog_DelayedShutdown";
  $hash->{ShutdownFn}        = "DbLog_Shutdown";
  $hash->{AttrList}          = "addStateEvent:0,1 ".
                               "asyncMode:1,0 ".
                               "commitMode:basic_ta:on,basic_ta:off,ac:on_ta:on,ac:on_ta:off,ac:off_ta:on ".
                               "cacheEvents:2,1,0 ".
                               "cacheLimit ".
                               "cacheOverflowThreshold ".
                               "colEvent ".
                               "colReading ".
                               "colType ".
                               "colValue ".
                               "convertTimezone:UTC,none ".
                               "DbLogSelectionMode:Exclude,Include,Exclude/Include ".
                               "DbLogType:Current,History,Current/History,SampleFill/History ".
                               "dbSchema ".
                               "defaultMinInterval:textField-long ".
                               "disable:1,0 ".
                               "excludeDevs ".
                               "expimpdir ".
                               "exportCacheAppend:1,0 ".
                               "insertMode:1,0 ".
                               "noSupportPK:1,0 ".
                               "plotInputFieldLength ".
                               "showproctime:1,0 ".
                               "suppressAddLogV3:1,0 ".
                               "suppressUndef:0,1 ".
                               "syncEvents:1,0 ".
                               "syncInterval ".
                               "showNotifyTime:1,0 ".
                               "SQLiteJournalMode:WAL,off ".
                               "SQLiteCacheSize ".
                               "traceFlag:SQL,CON,ENC,DBD,TXN,ALL ".
                               "traceLevel:0,1,2,3,4,5,6,7 ".
                               "timeout ".
                               "useCharfilter:0,1 ".
                               "valueFn:textField-long ".
                               "verbose4Devs ".
                               $readingFnAttributes;

  addToAttrList("DbLogInclude:textField-long");
  addToAttrList("DbLogExclude:textField-long");
  addToAttrList("DbLogValueFn:textField-long");

  $hash->{FW_detailFn}      = "DbLog_fhemwebFn";
  $hash->{SVG_sampleDataFn} = "DbLog_sampleDataFn";
  $hash->{prioSave}         = 1;                             # Prio-Flag für save Reihenfolge, Forum: https://forum.fhem.de/index.php/topic,130588.msg1249277.html#msg1249277

 $hash->{AttrRenameMap} = { "bulkInsert" => "insertMode",
                          };

  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };           # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)

return;
}

###############################################################
sub DbLog_Define {
  my ($hash, $def) = @_;
  my $name         = $hash->{NAME};
  my @a            = split "[ \t][ \t]*", $def;

  my $err;

  if($DbLogMMDBI) {
      $err = "Perl module ".$DbLogMMDBI." is missing. On Debian you can install it with: sudo apt-get install libdbi-perl";
      Log3 ($name, 1, "$name - ERROR - $err");
      return "Error: $err";
  }

  if ($storabs) {
      $err = "Perl module ".$storabs." is missing. On Debian you can install it with: sudo apt-get install libstorable-perl";
      Log3 ($name, 1, "$name - ERROR - $err");
      return "Error: $err";
  }

  return "wrong syntax: define <name> DbLog configuration regexp" if(int(@a) != 4);

  $hash->{CONFIGURATION} = $a[2];
  my $regexp             = $a[3];

  eval { "Hallo" =~ m/^$regexp$/ };
  return "Bad regexp: $@" if($@);

  $hash->{REGEXP}                = $regexp;
  $hash->{MODE}                  = AttrVal ($name, 'asyncMode', 0) ? 'asynchronous' : 'synchronous';          # Mode setzen Forum:#76213
  $hash->{HELPER}{OLDSTATE}      = 'initialized';
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                                                      # Modul Meta.pm nicht vorhanden

  DbLog_setSchemeTable ($hash, '');                                                                           # Tabellen initial setzen
  DbLog_setVersionInfo ($hash);                                                                               # Versionsinformationen setzen

  $hash->{PID}                      = $$;                                                                     # remember PID for plotfork
  $data{DbLog}{$name}{cache}{index} = 0;                                                                      # CacheIndex für Events zum asynchronen Schreiben in DB

  my $ret = DbLog_readCfg($hash);                                                                             # read configuration data

  if ($ret) {                                                                                                 # return on error while reading configuration
      Log3($name, 1, "$name - Error while reading $hash->{CONFIGURATION}: '$ret' ");
      return $ret;
  }

  DbLog_setReadingstate  ($hash, 'waiting for connection');
  DbLog_SBP_CheckAndInit ($hash, 1);                                                                          # SubProcess starten - direkt nach Define !! um wenig Speicher zu allokieren
  _DbLog_initOnStart     ($hash);                                                                             # von init_done abhängige Prozesse initialisieren

return;
}

###################################################################################
#  Startroutine
#  alle zeitgesteuerten Prozesse initialisieren die von init_done abhängen
###################################################################################
sub _DbLog_initOnStart {
  my $hash = shift;

  RemoveInternalTimer($hash, '_DbLog_initOnStart');

  if($init_done != 1) {
      InternalTimer(gettimeofday()+2, '_DbLog_initOnStart', $hash, 0);
      return;
  }

  my $name = $hash->{NAME};

  my @rdel = qw ( CacheUsage
                  userCommandResult
                  lastCachefile
                  reduceLogState
                  lastRowsDeleted
                  countCurrent
                  countHistory
                );

  for my $r (@rdel) {
      readingsDelete ($hash, $r);
  }

  DbLog_setSchemeTable         ($hash);                                 # Tabellenschema nach Laden Attr neu setzen
  notifyRegexpChanged          ($hash, $hash->{REGEXP});                # nur Events dieser Devices an NotifyFn weiterleiten, NOTIFYDEV wird gesetzt wenn möglich
  DbLog_setinternalcols        ($hash);                                 # verwendete Feldlängen setzen
  
  DoTrigger                    ($name, 'FRAME_INITIALIZED', 1);
  
  DbLog_SBP_CheckAndInit       ($hash);
  DbLog_SBP_sendConnectionData ($hash);                                 # Verbindungsdaten an SubProzess senden
  DbLog_execMemCacheAsync      ($hash);                                 # InternalTimer DbLog_execMemCacheAsync starten

return;
}

################################################################
# Die Undef-Funktion wird aufgerufen wenn ein Gerät mit delete
# gelöscht wird oder bei der Abarbeitung des Befehls rereadcfg,
# der ebenfalls alle Geräte löscht und danach das
# Konfigurationsfile neu einliest. Entsprechend müssen in der
# Funktion typische Aufräumarbeiten durchgeführt werden wie das
# saubere Schließen von Verbindungen oder das Entfernen von
# internen Timern.
################################################################
sub DbLog_Undef {
  my $hash = shift;
  my $name = shift;

   my $dbh = $hash->{DBHU};
   __DbLog_SBP_disconnectOnly ($name, $dbh);
   delete $hash->{DBHU};

  delete $hash->{HELPER}{LONGRUN_PID};

  RemoveInternalTimer($hash);
  delete $data{DbLog}{$name};

  DbLog_SBP_CleanUp ($hash);

return;
}

#######################################################################################################
# Mit der X_DelayedShutdown Funktion kann eine Definition das Stoppen von FHEM verzögern um asynchron
# hinter sich aufzuräumen.
# Je nach Rückgabewert $delay_needed wird der Stopp von FHEM verzögert (0 | 1).
# Sobald alle nötigen Maßnahmen erledigt sind, muss der Abschluss mit CancelDelayedShutdown($name) an
# FHEM zurückgemeldet werden.
#######################################################################################################
sub DbLog_DelayedShutdown {
  my $hash   = shift;
  my $name   = $hash->{NAME};

  $hash->{HELPER}{SHUTDOWNSEQ} = 1;

  DbLog_execMemCacheAsync ($hash);

  my $delay_needed = IsDisabled($name)                    ? 0 :
                     defined $hash->{HELPER}{LONGRUN_PID} ? 1 :
                     0;

  if ($delay_needed) {
      Log3 ($name, 2, "$name - Wait for last database cycle due to shutdown ...");

  }

return $delay_needed;
}

###################################################################################
#  Mit der X_Shutdown Funktion kann ein Modul Aktionen durchführen bevor FHEM
#  gestoppt wird. Dies kann z.B. der ordnungsgemäße Verbindungsabbau mit dem
#  physikalischen Gerät sein (z.B. Session beenden, Logout, etc.). Nach der
#  Ausführung der Shutdown-Fuktion wird FHEM sofort beendet.
###################################################################################
sub DbLog_Shutdown {
  my $hash = shift;

  DbLog_SBP_CleanUp ($hash);

return;
}

#####################################################
#   DelayedShutdown abschließen
#   letzte Aktivitäten vor Freigabe des Shutdowns
#####################################################
sub _DbLog_finishDelayedShutdown {
  my $hash = shift;
  my $name = $hash->{NAME};

  CancelDelayedShutdown ($name);

return;
}

################################################################
#
# Wird bei jeder Aenderung eines Attributes dieser
# DbLog-Instanz aufgerufen
#
################################################################
sub DbLog_Attr {
  my($cmd,$name,$aName,$aVal) = @_;

  my $hash = $defs{$name};
  my $do   = 0;

  if ($aName =~ /^(traceHandles|noNotifyDev)$/xs) {
      my $msg = "$name - The attribute >$aName< is deprecated and is not set anymore.";
      Log3 ($name, 1, "$name $msg");
      return $msg;
  }

  if($cmd eq "set") {
      if ($aName eq "syncInterval"           ||
          $aName eq "cacheLimit"             ||
          $aName eq "cacheOverflowThreshold" ||
          $aName eq "SQLiteCacheSize"        ||
          $aName eq "plotInputFieldLength"   ||
          $aName eq "timeout") {
          if ($aVal !~ /^[0-9]+$/) { return "The Value of $aName is not valid. Use only figures 0-9 !";}
      }

      if ($hash->{MODEL} !~ /MYSQL|POSTGRESQL/ && $aName =~ /dbSchema/) {
           return qq{"$aName" is not valid for database model "$hash->{MODEL}"};
      }

      if($aName =~ /[Vv]alueFn/) {
          my ($err, $func) = DbLog_checkSyntaxValueFn ($name, $aVal);
          return $err if($err);
      }

      if ($aName eq "convertTimezone") {
          return "The library FHEM::Utility::CTZ is missed. Please update FHEM completely." if($ctzAbsent);

          my $rmf = reqModFail();
          return "You have to install the required perl module: ".$rmf if($rmf);
      }
  }

  if ($aName =~ /SQLite/xs) {
      if ($init_done == 1) {
          DbLog_SBP_sendDbDisconnect ($hash, 1);                                            # DB Verbindung und Verbindungsdaten im SubProzess löschen
          InternalTimer(gettimeofday()+0.8, 'DbLog_SBP_sendConnectionData', $hash, 0);      # neue Verbindungsdaten an SubProzess senden
      }
  }

  if($aName =~ /^col[ERTV]/xs) {
      if ($cmd eq "set" && $aVal) {
          unless ($aVal =~ /^[0-9]+$/) { return " The Value of $aName is not valid. Use only figures 0-9 !";}
      }
      
      if ($init_done) {
          InternalTimer(gettimeofday()+0.8, "DbLog_setinternalcols", $hash, 0);
      }
  }

  if($aName eq 'asyncMode') {
      if ($cmd eq "set" && $aVal) {
          $hash->{MODE} = 'asynchronous';
          InternalTimer(gettimeofday()+0.8, 'DbLog_execMemCacheAsync', $hash, 0);
      }
      else {
          $hash->{MODE} = 'synchronous';

          delete($defs{$name}{READINGS}{NextSync});
          delete($defs{$name}{READINGS}{CacheUsage});
          delete($defs{$name}{READINGS}{CacheOverflowLastNum});
          delete($defs{$name}{READINGS}{CacheOverflowLastState});

          InternalTimer(gettimeofday()+5, "DbLog_execMemCacheAsync", $hash, 0);
      }
  }

  if($aName eq "commitMode") {
      my $dbh = $hash->{DBHU};
      __DbLog_SBP_disconnectOnly ($name, $dbh);
      delete $hash->{DBHU};

      if ($init_done == 1) {
           DbLog_SBP_sendDbDisconnect ($hash, 1);                                            # DB Verbindung und Verbindungsdaten im SubProzess löschen

          InternalTimer(gettimeofday()+0.8, 'DbLog_SBP_sendConnectionData', $hash, 0);       # neue Verbindungsdaten an SubProzess senden
      }
  }

  if($aName eq "showproctime") {
      if ($cmd ne "set" || !$aVal) {
          delete($defs{$name}{READINGS}{background_processing_time});
          delete($defs{$name}{READINGS}{sql_processing_time});
      }
  }

  if($aName eq "showNotifyTime") {
      if ($cmd ne "set" || !$aVal) {
          delete($defs{$name}{READINGS}{notify_processing_time});
      }
  }

  if ($aName eq "disable") {
      my $async = AttrVal($name, 'asyncMode', 0);

      if($cmd eq "set") {
          $do = $aVal ? 1 : 0;
      }

      $do     = 0 if($cmd eq "del");
      my $val = $do == 1 ? 'disabled' : 'active';

      DbLog_execMemCacheAsync ($hash)          if($do == 1);                            # letzter CacheSync vor disablen
      DbLog_setReadingstate   ($hash, $val);

      if ($do == 0) {
          InternalTimer(gettimeofday()+1.8, "_DbLog_initOnStart", $hash, 0);
      }
  }

  if ($aName eq "dbSchema") {
      if($cmd eq "set") {
          $do = $aVal ? 1 : 0;
      }

      $do = 0 if($cmd eq "del");

      if ($do == 1) {
          DbLog_setSchemeTable ($hash, $aVal);
      }
      else {
          DbLog_setSchemeTable ($hash, '');
      }

      if ($init_done == 1) {
           DbLog_SBP_sendDbDisconnect ($hash, 1);                                            # DB Verbindung und Verbindungsdaten im SubProzess löschen

          InternalTimer(gettimeofday()+0.8, 'DbLog_SBP_sendConnectionData', $hash, 0);       # neue Verbindungsdaten an SubProzess senden
      }
  }

return;
}

################################################################
sub DbLog_Set {
    my ($hash, @a) = @_;

    return qq{"set X" needs at least an argument} if ( @a < 2 );

    my $name  = shift @a;
    my $opt   = shift @a;
    my @args  = @a;
    my $arg   = join " ", map { my $p = $_; $p =~ s/\s//xg; $p; } @a;     ## no critic 'Map blocks'
    my $prop  = shift @a;
    my $prop1 = shift @a;

    return if(IsDisabled ($name));

    my $async = AttrVal($name, 'asyncMode', 0);

    my $usage = "Unknown argument, choose one of ".
                "addCacheLine ".
                "addLog ".
                "clearReadings:noArg ".
                "count:noArg ".
                "configCheck:noArg ".
                "countNbl:noArg ".
                "deleteOldDays ".
                "eraseReadings:noArg ".
                "listCache:noArg ".
                "reduceLog ".
                "rereadcfg:noArg ".
                "reopen ".
                "stopSubProcess:noArg ".
                "userCommand "
                ;

    if ($async) {
        $usage .= "commitCache:noArg ".
                  "exportCache:nopurge,purgecache ".
                  "purgeCache:noArg "
                  ;
    }

    my (@logs,$dir,$ret,$trigger);

    my $dirdef = AttrVal('global', 'logdir', $attr{global}{modpath}.'/log/');
    $dir       = AttrVal($name,    'expimpdir',                     $dirdef);
    $dir       = $dir.'/' if($dir !~ /.*\/$/);

    opendir(DIR,$dir);
    my $sd = 'cache_'.$name.'_';

    while (my $file = readdir(DIR)) {
        next unless (-f "$dir/$file");
        next unless ($file =~ /^$sd/);
        push @logs,$file;
    }
    closedir(DIR);

    my $cj = q{};
    $cj    = join(",",reverse(sort @logs)) if (@logs);

    if (@logs) {
        $usage .= 'importCachefile:'.$cj.' ';
    }
    else {
        $usage .= 'importCachefile ';
    }

    my $db  = (split(/;|=/, $hash->{dbconn}))[1];

    my $params = {
        hash    => $hash,
        name    => $name,
        dbname  => $db,
        arg     => $arg,
        argsref => \@args,
        logsref => \@logs,
        dir     => $dir,
        opt     => $opt,
        prop    => $prop,
        prop1   => $prop1
    };

    if($DbLog_hset{$opt} && defined &{$DbLog_hset{$opt}{fn}}) {
        $ret            = q{};
        ($ret,$trigger) = &{$DbLog_hset{$opt}{fn}} ($params);
        return ($ret,$trigger);
    }

return $usage;
}

################################################################
#                      Setter listCache
################################################################
sub _DbLog_setlistCache {                ## no critic "not used"
  my $paref = shift;
  my $name  = $paref->{name};

  my $cache;

  if (!scalar(keys %{$data{DbLog}{$name}{cache}{memcache}})) {
      return 'Memory Cache is empty';
  }

  for my $key (sort{$a <=>$b}keys %{$data{DbLog}{$name}{cache}{memcache}}) {
      $cache .= $key." => ".$data{DbLog}{$name}{cache}{memcache}{$key}."\n";
  }

return $cache;
}

################################################################
#                      Setter clearReadings
################################################################
sub _DbLog_setclearReadings {            ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};

  my @allrds = keys%{$defs{$name}{READINGS}};

  for my $key(@allrds) {
      next if($key =~ m/state/ || $key =~ m/CacheUsage/ || $key =~ m/NextSync/);
      readingsSingleUpdate($hash, $key, ' ', 0);
  }

return;
}

################################################################
#                      Setter eraseReadings
################################################################
sub _DbLog_seteraseReadings {            ## no critic "not used"
  my $paref = shift;
  my $name  = $paref->{name};

  my @allrds = keys%{$defs{$name}{READINGS}};

  for my $key(@allrds) {
      delete($defs{$name}{READINGS}{$key}) if($key !~ m/^state$/);
  }

return;
}

################################################################
#                      Setter stopSubProcess
################################################################
sub _DbLog_setstopSubProcess {           ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};

  DbLog_SBP_CleanUp ($hash);                                              # SubProcess beenden

  my $ret = 'SubProcess stopped and will be automatically restarted if needed';

  DbLog_setReadingstate ($hash, $ret);

return $ret;
}

################################################################
#                      Setter purgeCache
################################################################
sub _DbLog_setpurgeCache {               ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};

  delete $data{DbLog}{$name}{cache};
  readingsSingleUpdate($hash, 'CacheUsage', 0, 1);

return 'Memory Cache purged';
}

################################################################
#                      Setter commitCache
################################################################
sub _DbLog_setcommitCache {              ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};

  DbLog_execMemCacheAsync ($hash);

return;
}

################################################################
#                      Setter reopen
################################################################
sub _DbLog_setreopen {                   ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop};

  my $ret;

  my $dbh = $hash->{DBHU};
  __DbLog_SBP_disconnectOnly ($name, $dbh);                            # lokal
  delete $hash->{DBHU};

  DbLog_SBP_sendDbDisconnect ($hash);                                  # an SBP

  if (!$prop) {
      Log3 ($name, 3, "$name - Reopen requested");

      if($hash->{HELPER}{REOPEN_RUNS}) {
          delete $hash->{HELPER}{REOPEN_RUNS};
          delete $hash->{HELPER}{REOPEN_RUNS_UNTIL};
          RemoveInternalTimer($hash, "DbLog_reopen");
      }

      DbLog_execMemCacheAsync ($hash) if(AttrVal($name, 'asyncMode', 0));
      $ret = "Reopen executed.";
  }
  else {
      unless ($prop =~ /^[0-9]+$/) {
          return " The Value of $opt time is not valid. Use only figures 0-9 !";
      }

      $hash->{HELPER}{REOPEN_RUNS} = $prop;                                              # Statusbit "Kein Schreiben in DB erlauben" wenn reopen mit Zeitangabe

      delete $hash->{HELPER}{LONGRUN_PID};

      my $ts = (split " ",FmtDateTime(gettimeofday()+$prop))[1];
      Log3 ($name, 2, "$name - Connection closed until $ts ($prop seconds).");

      DbLog_setReadingstate ($hash, "closed until $ts ($prop seconds)");

      InternalTimer(gettimeofday()+$prop, "DbLog_reopen", $hash, 0);

      $hash->{HELPER}{REOPEN_RUNS_UNTIL} = $ts;
  }

return $ret;
}

################################################################
#                      Setter rereadcfg
################################################################
sub _DbLog_setrereadcfg {                ## no critic "not used"
  my $paref = shift;
  my $hash  = $paref->{hash};
  my $name  = $paref->{name};

  Log3 ($name, 3, "$name - Rereadcfg requested.");

  my $ret = DbLog_readCfg($hash);
  return $ret if $ret;

  my $dbh = $hash->{DBHU};
  __DbLog_SBP_disconnectOnly ($name, $dbh);                         # lokal
  delete $hash->{DBHU};

  DbLog_SBP_sendDbDisconnect ($hash, 1);                            # DB Verbindung und Verbindungsdaten im SubProzess löschen

  my $rst = DbLog_SBP_sendConnectionData ($hash);                   # neue Verbindungsdaten an SubProzess senden

  if (!$rst) {
      Log3 ($name, 3, "$name - new DB connection parameters are transmitted ...");
  }

  $ret = "Rereadcfg executed.";

return $ret;
}

################################################################
#                      Setter addLog
################################################################
sub _DbLog_setaddLog {                   ## no critic "not used"
  my $paref   = shift;

  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $opt     = $paref->{opt};
  my $prop    = $paref->{prop};
  my $argsref = $paref->{argsref};

  unless ($prop) {
      return "$opt needs an argument. Please check commandref.";
  }

  my @args = @{$argsref};

  my $nce = ("\!useExcludes" ~~ @args) ? 1 : 0;

  map (s/\!useExcludes//g, @args);

  my $cn;

  if(/CN=/ ~~ @args) {
      my $t = join " ", @args;
      ($cn) = ($t =~ /^.*CN=(\w+).*$/);
      map(s/CN=$cn//g, @args);
  }

  my $params = { hash      => $hash,
                 devrdspec => $args[0],
                 value     => $args[1],
                 nce       => $nce,
                 cn        => $cn
               };

  DbLog_AddLog ($params);

  my $skip_trigger = 1;                                         # kein Event erzeugen falls addLog device/reading not found aber Abarbeitung erfolgreich

return undef,$skip_trigger;
}

################################################################
#                      Setter addCacheLine
################################################################
sub _DbLog_setaddCacheLine {              ## no critic "not used"
  my $paref   = shift;

  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $opt     = $paref->{opt};
  my $prop    = $paref->{prop};
  my $argsref = $paref->{argsref};

  if(!$prop) {
      return "Syntax error in set $opt command. Use this line format: YYYY-MM-DD HH:MM:SS|<device>|<type>|<event>|<reading>|<value>|[<unit>] ";
  }

  my @b = @{$argsref};

  my $aa;

  for my $k (@b) {
      $aa .= "$k ";
  }

  chop($aa);                                                                      #letztes Leerzeichen entfernen
  $aa = DbLog_charfilter($aa) if(AttrVal($name, "useCharfilter",0));

  my ($i_timestamp, $i_dev, $i_type, $i_evt, $i_reading, $i_val, $i_unit) = split "\\|", $aa;

  if($i_timestamp !~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/ || !$i_dev || !$i_reading) {
      return "Syntax error in set $opt command. Use this line format: YYYY-MM-DD HH:MM:SS|<device>|<type>|<event>|<reading>|<value>|[<unit>] ";
  }

  my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($i_timestamp =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
  eval { my $ts = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };

  if ($@) {
      my @l = split /at/, $@;
      return "Timestamp is out of range - $l[0]";
  }

  DbLog_addCacheLine ( { hash        => $hash,
                         i_timestamp => $i_timestamp,
                         i_dev       => $i_dev,
                         i_type      => $i_type,
                         i_evt       => $i_evt,
                         i_reading   => $i_reading,
                         i_val       => $i_val,
                         i_unit      => $i_unit
                       }
                     );

return;
}

################################################################
#                      Setter count
################################################################
sub _DbLog_setcount {              ## no critic "not used"
  my $paref = shift;

  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};

  if($hash->{HELPER}{REOPEN_RUNS}) {                                          # return wenn "reopen" mit Ablaufzeit gestartet ist
      return "Connection to database is closed until ".$hash->{HELPER}{REOPEN_RUNS_UNTIL};
  }

  if (defined $hash->{HELPER}{LONGRUN_PID}) {
      return 'Another operation is in progress, try again a little later.';
  }

  my $err = DbLog_SBP_CheckAndInit ($hash);                                   # Subprocess checken und ggf. initialisieren
  return $err if($err);

  Log3 ($name, 2, qq{$name - WARNING - "$opt" is outdated. Please consider use of DbRep "set <Name> countEntries" instead.});
  Log3 ($name, 4, "$name - Records count requested.");

  DbLog_SBP_sendCommand ($hash, 'count');

return;
}

################################################################
#                      Setter deleteOldDays
################################################################
sub _DbLog_setdeleteOldDays {            ## no critic "not used"
  my $paref = shift;

  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $db    = $paref->{dbname};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop};

  if($hash->{HELPER}{REOPEN_RUNS}) {                                          # return wenn "reopen" mit Ablaufzeit gestartet ist
      return "Connection to database is closed until ".$hash->{HELPER}{REOPEN_RUNS_UNTIL};
  }

  if (defined $hash->{HELPER}{LONGRUN_PID}) {
      return 'Another operation is in progress, try again a little later.';
  }

  my $err = DbLog_SBP_CheckAndInit ($hash);                                   # Subprocess checken und ggf. initialisieren
  return $err if($err);

  Log3 ($name, 2, qq{$name - WARNING - "$opt" is outdated. Please consider use of DbRep "set <Name> delEntries" instead.});
  Log3 ($name, 3, "$name - Deletion of records older than $prop days in database $db requested");

  DbLog_SBP_sendCommand ($hash, 'deleteOldDays', $prop);

return;
}

################################################################
#                      Setter userCommand
################################################################
sub _DbLog_setuserCommand {              ## no critic "not used"
  my $paref = shift;

  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $sql   = $paref->{arg};

  if($hash->{HELPER}{REOPEN_RUNS}) {                                          # return wenn "reopen" mit Ablaufzeit gestartet ist
      return "Connection to database is closed until ".$hash->{HELPER}{REOPEN_RUNS_UNTIL};
  }

  if (defined $hash->{HELPER}{LONGRUN_PID}) {
      return 'Another operation is in progress, try again a little later.';
  }

  my $err = DbLog_SBP_CheckAndInit ($hash);                                   # Subprocess checken und ggf. initialisieren
  return $err if($err);

  Log3 ($name, 2, qq{$name - WARNING - "$opt" is outdated. Please consider use of DbRep "set <Name> sqlCmd" instead.});

  DbLog_SBP_sendCommand ($hash, 'userCommand', $sql);

return;
}

################################################################
#                      Setter exportCache
################################################################
sub _DbLog_setexportCache {              ## no critic "not used"
  my $paref   = shift;

  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $argsref = $paref->{argsref};
  my $logsref = $paref->{logsref};
  my $dir     = $paref->{dir};

  # return "Device is not in asynch working mode" if(!AttrVal($name, 'asyncMode', 0));

  my $cln;
  my $crows = 0;
  my @args  = @{$argsref};
  my @logs  = @{$logsref};
  my $now   = strftime('%Y-%m-%d_%H-%M-%S',localtime);

  my ($out,$outfile,$error);

  if(@logs && AttrVal($name, 'exportCacheAppend', 0)) {              # exportiertes Cachefile existiert und es soll an das neueste angehängt werden
      $outfile = $dir.pop(@logs);
      $out     = ">>$outfile";
  }
  else {
      $outfile = $dir."cache_".$name."_".$now;
      $out     = ">$outfile";
  }

  if(open(FH, $out)) {
      binmode (FH);
  }
  else {
      readingsSingleUpdate ($hash, 'lastCachefile', $outfile.' - Error - '.$!, 1);
      $error = 'could not open '.$outfile.': '.$!;
  }

  if(!$error) {
      for my $key (sort(keys %{$data{DbLog}{$name}{cache}{memcache}})) {
          $cln = $data{DbLog}{$name}{cache}{memcache}{$key}."\n";
          print FH $cln ;
          $crows++;
      }

      close(FH);
      readingsSingleUpdate ($hash, 'lastCachefile', $outfile.' ('.$crows.' cache rows exported)', 1);
  }

  my $state = $error // $hash->{HELPER}{OLDSTATE};
  DbLog_setReadingstate ($hash, $state);

  return $error if($error);

  Log3 ($name, 3, "$name - $crows Cache rows exported to $outfile");

  if (lc($args[-1]) =~ m/^purgecache/i) {
      delete $data{DbLog}{$name}{cache};
      readingsSingleUpdate ($hash, 'CacheUsage', 0, 1);

      Log3 ($name, 3, "$name - Cache purged after exporting rows to $outfile.");
  }

return;
}

################################################################
#                      Setter importCachefile
################################################################
sub _DbLog_setimportCachefile {          ## no critic "not used"
  my $paref   = shift;

  my $hash    = $paref->{hash};
  my $name    = $paref->{name};
  my $prop    = $paref->{prop};
  my $dir     = $paref->{dir};

  my $infile;

  readingsDelete($hash, 'lastCachefile');

  if (!$prop) {
      return "Wrong function-call. Use set <name> importCachefile <file> without directory (see attr expimpdir)." ;
  }
  else {
      $infile = $dir.$prop;
  }

  if($hash->{HELPER}{REOPEN_RUNS}) {                                          # return wenn "reopen" mit Ablaufzeit gestartet ist
      return "Connection to database is closed until ".$hash->{HELPER}{REOPEN_RUNS_UNTIL};
  }

  if (defined $hash->{HELPER}{LONGRUN_PID}) {
      return 'Another operation is in progress, try again a little later.';
  }

  my $err = DbLog_SBP_CheckAndInit ($hash);                                   # Subprocess checken und ggf. initialisieren
  return $err if($err);

  DbLog_SBP_sendCommand ($hash, 'importCachefile', $infile);

return;
}

################################################################
#                      Setter reduceLog
################################################################
sub _DbLog_setreduceLog {                ## no critic "not used"
  my $paref = shift;

  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my $opt   = $paref->{opt};
  my $prop  = $paref->{prop};
  my $prop1 = $paref->{prop1};
  my $arg   = $paref->{arg};

  Log3($name, 2, qq{$name - WARNING - "$opt" is outdated. Please consider use of DbRep "set <Name> reduceLog" instead.});

  my ($od,$nd) = split ":", $prop;                                 # $od - Tage älter als , $nd - Tage neuer als

  if ($nd && $nd <= $od) {
      return "The second day value must be greater than the first one!";
  }

  if (defined($prop1) && $prop1 !~ /^average$|^average=.+|^EXCLUDE=.+$|^INCLUDE=.+$/i) {
      return "reduceLog syntax error in set command. Please see commandref for help.";
  }

  if (defined $prop && $prop =~ /(^\d+$)|(^\d+:\d+$)/) {
      if($hash->{HELPER}{REOPEN_RUNS}) {                                          # return wenn "reopen" mit Ablaufzeit gestartet ist
          return "Connection to database is closed until ".$hash->{HELPER}{REOPEN_RUNS_UNTIL};
      }

      if (defined $hash->{HELPER}{LONGRUN_PID}) {
          return 'Another operation is in progress, try again a little later.';
      }

      my $err = DbLog_SBP_CheckAndInit ($hash);                                   # Subprocess checken und ggf. initialisieren
      return $err if($err);

      DbLog_SBP_sendCommand ($hash, 'reduceLog', $arg);
  }
  else {
      Log3 ($name, 2, "$name: reduceLog error, no <days> given.");
      return "reduceLog syntax error, no <days> given.";
  }

return;
}

##################################################################################################################
#
# Hauptroutine zum Loggen. Wird bei jedem Eventchange
# aufgerufen
#
##################################################################################################################
# Es werden nur die Events von Geräten verarbeitet die im Hash $hash->{NOTIFYDEV} gelistet sind (wenn definiert).
# Dadurch kann die Menge der Events verringert werden. In sub DbRep_Define angeben.
# Beispiele:
# $hash->{NOTIFYDEV} = "global";
# $hash->{NOTIFYDEV} = "global,Definition_A,Definition_B";
# $hash is my entry, $dev_hash is the entry of the changed device

sub DbLog_Log {
  my $hash     = shift;
  my $dev_hash = shift;
  my $name     = $hash->{NAME};
  my $dev_name = $dev_hash->{NAME};
  my $dev_type = uc($dev_hash->{TYPE});

  return if(IsDisabled($name) || !$hash->{HELPER}{COLSET} || $init_done != 1);

  my ($net,$force);

  my $nst = [gettimeofday];                                                     # Notify-Routine Startzeit

  my $events = deviceEvents($dev_hash, AttrVal($name, "addStateEvent", 1));
  return if(!$events);

  my $max      = int(@{$events});
  my $vb4show  = 0;
  my @vb4devs  = split ",", AttrVal ($name, 'verbose4Devs', '');                # verbose4 Logs nur für Devices in Attr "verbose4Devs"

  if (!@vb4devs) {
      $vb4show = 1;
  }
  else {
      for (@vb4devs) {
          if($dev_name =~ m/$_/i) {
              $vb4show = 1;
              last;
          }
      }
  }

  my $log4rel = $vb4show && !defined $hash->{HELPER}{LONGRUN_PID} ? 1 : 0;

  if(AttrVal ($name, 'verbose', 3) > 3) {
      if($log4rel) {
          Log3 ($name, 4, "$name - ################################################################");
          Log3 ($name, 4, "$name - ###              start of new Logcycle                       ###");
          Log3 ($name, 4, "$name - ################################################################");
          Log3 ($name, 4, "$name - number of events received: $max of device: $dev_name");
      }
  }

  my ($event,$reading,$value,$unit,$err,$DoIt);

  my $memcount           = 0;
  my $re                 = $hash->{REGEXP};
  my $ts_0               = TimeNow();                                                  # timestamp in SQL format YYYY-MM-DD hh:mm:ss
  my $now                = gettimeofday();                                             # get timestamp in seconds since epoch
  my $DbLogExclude       = AttrVal ($dev_name, 'DbLogExclude',          undef);
  my $DbLogInclude       = AttrVal ($dev_name, 'DbLogInclude',          undef);
  my $DbLogValueFn       = AttrVal ($dev_name, 'DbLogValueFn',             '');
  my $DbLogSelectionMode = AttrVal ($name,     'DbLogSelectionMode','Exclude');
  my $value_fn           = AttrVal ($name,     'valueFn',                  '');
  my $ctz                = AttrVal ($name,     'convertTimezone',      'none');        # convert time zone
  my $async              = AttrVal ($name,     'asyncMode',                 0);
  my $clim               = AttrVal ($name,     'cacheLimit',  $dblog_cachedef);
  my $ce                 = AttrVal ($name,     'cacheEvents',               0);

  ($err, $DbLogValueFn) = DbLog_checkSyntaxValueFn ($name, $DbLogValueFn, $dev_name);  # Funktion aus Device spezifischer DbLogValueFn validieren
  $DbLogValueFn = '' if($err);

  ($err, $value_fn) = DbLog_checkSyntaxValueFn ($name, $value_fn);                     # Funktion aus Attr valueFn validieren
  $value_fn = '' if($err);

  eval {                                                                               # one Transaction
      for (my $i = 0; $i < $max; $i++) {
          my $next  = 0;
          my $event = $events->[$i];
          $event    = '' if(!defined($event));
          $event    = DbLog_charfilter($event) if(AttrVal($name, "useCharfilter",0));

          Log3 ($name, 4, "$name - check Device: $dev_name , Event: $event") if($log4rel);

          if($dev_name =~ m/^$re$/ || "$dev_name:$event" =~ m/^$re$/ || $DbLogSelectionMode eq 'Include') {
              my $timestamp = $ts_0;
              $timestamp    = $dev_hash->{CHANGETIME}[$i] if(defined($dev_hash->{CHANGETIME}[$i]));

              if($ctz ne 'none') {
                  my $params = {
                      name      => $name,
                      dtstring  => $timestamp,
                      tzcurrent => 'local',
                      tzconv    => $ctz,
                      writelog  => 0
                  };

                  ($err, $timestamp) = convertTimeZone ($params);

                  if ($err) {
                      Log3 ($name, 1, "$name - ERROR while converting time zone: $err - exit log loop !");
                      last;
                  }
              }

              $event =~ s/\|/_ESC_/gxs;                                                                # escape Pipe "|"

              my @r = _DbLog_ParseEvent($name,$dev_name, $dev_type, $event);
              $reading = $r[0];
              $value   = $r[1];
              $unit    = $r[2];
              if(!defined $reading)             {$reading = "";}
              if(!defined $value)               {$value = "";}
              if(!defined $unit || $unit eq "") {$unit = AttrVal("$dev_name", "unit", "");}

              $unit = DbLog_charfilter($unit) if(AttrVal($name, "useCharfilter",0));

              # Devices / Readings ausschließen durch Attribut "excludeDevs"
              # attr <device> excludeDevs [<devspec>#]<Reading1>,[<devspec>#]<Reading2>,[<devspec>#]<Reading..>
              my ($exc,@excldr,$ds,$rd,@exdvs);
              $exc = AttrVal($name, "excludeDevs", "");

              if($exc) {
                  $exc    =~ s/[\s\n]/,/g;
                  @excldr = split ',', $exc;

                  for my $excl (@excldr) {
                      ($ds,$rd) = split '#', $excl;
                      @exdvs    = devspec2array($ds);

                      if(@exdvs) {
                          for my $ed (@exdvs) {
                              if($rd) {
                                  if("$dev_name:$reading" =~ m/^$ed:$rd$/) {
                                      Log3 ($name, 4, "$name - Device:Reading \"$dev_name:$reading\" global excluded from logging by attribute \"excludeDevs\" ") if($log4rel);
                                      $next = 1;
                                  }
                              }
                              else {
                                  if($dev_name =~ m/^$ed$/) {
                                      Log3 ($name, 4, "$name - Device \"$dev_name\" global excluded from logging by attribute \"excludeDevs\" ") if($log4rel);
                                      $next = 1;
                                  }
                              }
                          }
                      }
                  }

                  next if($next);
              }

              Log3 ($name, 5, "$name - parsed Event: $dev_name , Event: $event") if($log4rel);

              if($log4rel) {
                  Log3 ($name, 5, qq{$name - DbLogExclude of "$dev_name": $DbLogExclude}) if($DbLogExclude);
                  Log3 ($name, 5, qq{$name - DbLogInclude of "$dev_name": $DbLogInclude}) if($DbLogInclude);
              }

              # Je nach DBLogSelectionMode muss das vorgegebene Ergebnis der Include-, bzw. Exclude-Pruefung
              # entsprechend unterschiedlich vorbelegt sein.
              # keine Readings loggen die in DbLogExclude explizit ausgeschlossen sind
              $DoIt = 0;
              $DoIt = 1 if($DbLogSelectionMode =~ m/Exclude/ );

              if($DbLogExclude && $DbLogSelectionMode =~ m/Exclude/) {                                        # Bsp: "(temperature|humidity):300,battery:3600:force"
                  my @v1 = DbLog_attrLong2Array ($DbLogExclude, ',');

                  for (my $i = 0; $i < int(@v1); $i++) {
                      my @v2 = split /:/, $v1[$i];
                      $DoIt  = 0 if(!$v2[1] && $reading =~ m,^$v2[0]$,);                                      # Reading matcht auf Regexp, kein MinIntervall angegeben

                      if(($v2[1] && $reading =~ m,^$v2[0]$,) && ($v2[1] =~ m/^(\d+)$/)) {                     # Regexp matcht und MinIntervall ist angegeben
                          my $lt = $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{TIME};
                          my $lv = $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{VALUE};
                          $lt    = 0  if(!$lt);
                          $lv    = "" if(!defined $lv);                                                       # Forum: #100344
                          $force = ($v2[2] && $v2[2] =~ /force/i) ? 1 : 0;                                    # Forum: #97148

                          if(($now-$lt < $v2[1]) && ($lv eq $value || $force)) {                              # innerhalb MinIntervall und LastValue=Value
                              $DoIt = 0;
                          }
                      }
                  }
              }

              # Hier ggf. zusätzlich noch dbLogInclude pruefen, falls bereits durch DbLogExclude ausgeschlossen
              # Im Endeffekt genau die gleiche Pruefung, wie fuer DBLogExclude, lediglich mit umgegkehrtem Ergebnis.
              if($DoIt == 0) {
                  if($DbLogInclude && ($DbLogSelectionMode =~ m/Include/)) {
                      my @v1 = DbLog_attrLong2Array ($DbLogInclude, ',');

                      for (my $i = 0; $i < int(@v1); $i++) {
                          my @v2 = split /:/, $v1[$i];
                          $DoIt  = 1 if($reading =~ m,^$v2[0]$,);                                               # Reading matcht auf Regexp

                          if(($v2[1] && $reading =~ m,^$v2[0]$,) && ($v2[1] =~ m/^(\d+)$/)) {                   # Regexp matcht und MinIntervall ist angegeben
                              my $lt = $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{TIME};
                              my $lv = $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{VALUE};
                              $lt    = 0  if(!$lt);
                              $lv    = '' if(!defined $lv);                                                     # Forum: #100344
                              $force = ($v2[2] && $v2[2] =~ /force/i)?1:0;                                      # Forum: #97148

                              if(($now-$lt < $v2[1]) && ($lv eq $value || $force)) {                            # innerhalb MinIntervall und LastValue=Value
                                  $DoIt = 0;
                              }
                          }
                      }
                  }
              }

              next if($DoIt == 0);

              $DoIt = _DbLog_checkDefMinInt ({                                                                 # check auf defaultMinInterval
                                              name     => $name,
                                              dev_name => $dev_name,
                                              now      => $now,
                                              reading  => $reading,
                                              value    => $value
                                             }
                                            );

              if ($DoIt) {
                  my $lastt = $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{TIME};                          # patch Forum:#111423
                  my $lastv = $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{VALUE};

                  $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{TIME}  = $now;
                  $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{VALUE} = $value;

                  if($DbLogValueFn ne '') {                                                                    # Device spezifische DbLogValueFn-Funktion anwenden
                      my $TIMESTAMP     = $timestamp;
                      my $LASTTIMESTAMP = $lastt // 0;                                                         # patch Forum:#111423
                      my $DEVICE        = $dev_name;
                      my $EVENT         = $event;
                      my $READING       = $reading;
                      my $VALUE         = $value;
                      my $LASTVALUE     = $lastv // "";                                                        # patch Forum:#111423
                      my $UNIT          = $unit;
                      my $IGNORE        = 0;
                      my $CN            = " ";

                      eval $DbLogValueFn;
                      if($@) {
                          Log3 ($name, 2, "$name - error device \"$dev_name\" specific DbLogValueFn: ".$@);
                      }

                      if ($IGNORE) {                                                                                       # aktueller Event wird nicht geloggt wenn $IGNORE=1 gesetzt
                          $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{TIME}  = $lastt if($lastt);                     # patch Forum:#111423
                          $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{VALUE} = $lastv if(defined $lastv);

                          if($log4rel) {
                              Log3 ($name, 4, "$name - Event ignored by device \"$dev_name\" specific DbLogValueFn - TS: $timestamp, Device: $dev_name, Type: $dev_type, Event: $event, Reading: $reading, Value: $value, Unit: $unit");
                          }

                          next;
                      }

                      my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($TIMESTAMP =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);

                      eval { my $epoch_seconds_begin = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };
                      if (!$@) {
                          $timestamp = $TIMESTAMP;
                      }
                      else {
                          Log3 ($name, 2, "$name - TIMESTAMP got from DbLogValueFn in $dev_name is invalid: $TIMESTAMP");
                      }

                      $reading = $READING  if($READING ne '');
                      $value   = $VALUE    if(defined $VALUE);
                      $unit    = $UNIT     if(defined $UNIT);
                  }

                  if($value_fn ne '') {                                                                                 # zentrale valueFn im DbLog-Device abarbeiten
                      my $NAME          = $name;
                      my $TIMESTAMP     = $timestamp;
                      my $LASTTIMESTAMP = $lastt // 0;                                                                  # patch Forum:#111423
                      my $DEVICE        = $dev_name;
                      my $DEVICETYPE    = $dev_type;
                      my $EVENT         = $event;
                      my $READING       = $reading;
                      my $VALUE         = $value;
                      my $LASTVALUE     = $lastv // "";                                                                 # patch Forum:#111423
                      my $UNIT          = $unit;
                      my $IGNORE        = 0;
                      my $CN            = " ";

                      eval $value_fn;
                      if ($@) {
                          Log3 ($name, 2, "$name - error valueFn: ".$@);
                      }

                      if ($IGNORE) {                                                                                    # aktueller Event wird nicht geloggt wenn $IGNORE=1 gesetzt
                          $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{TIME}  = $lastt if($lastt);                  # patch Forum:#111423
                          $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{VALUE} = $lastv if(defined $lastv);

                          if($log4rel) {
                              Log3 ($name, 4, "$name - Event ignored by valueFn - TS: $timestamp, Device: $dev_name, Type: $dev_type, Event: $event, Reading: $reading, Value: $value, Unit: $unit");
                          }

                          next;
                      }

                      my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($TIMESTAMP =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);

                      eval { my $epoch_seconds_begin = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };
                      if (!$@) {
                          $timestamp = $TIMESTAMP;
                      }
                      else {
                          Log3 ($name, 2, "$name - Parameter TIMESTAMP got from valueFn is invalid: $TIMESTAMP");
                      }

                      $dev_name  = $DEVICE     if($DEVICE ne '');
                      $dev_type  = $DEVICETYPE if($DEVICETYPE ne '');
                      $reading   = $READING    if($READING ne '');
                      $value     = $VALUE      if(defined $VALUE);
                      $unit      = $UNIT       if(defined $UNIT);
                      $event     = $EVENT      if(defined $EVENT);
                  }

                  # Daten auf maximale Länge beschneiden
                  ($dev_name,$dev_type,$event,$reading,$value,$unit) = DbLog_cutCol ($hash, $dev_name, $dev_type, $event, $reading, $value, $unit);

                  my $row = $timestamp."|".$dev_name."|".$dev_type."|".$event."|".$reading."|".$value."|".$unit;

                  if($log4rel) {
                    Log3 ($name, 4, "$name - added event - Timestamp: $timestamp, Device: $dev_name, Type: $dev_type, Event: $event, Reading: $reading, Value: $value, Unit: $unit");
                  }

                  $memcount = DbLog_addMemCacheRow ($name, $row);                            # Datensatz zum Memory Cache hinzufügen
              }
          }
      }
  };

  if (!$memcount) {
      $net = tv_interval($nst);                                                              # Notify-Routine Laufzeit ermitteln

      if(AttrVal($name, 'showNotifyTime', 0)) {
          readingsSingleUpdate($hash, 'notify_processing_time', sprintf("%.4f",$net), 1);
      }

      return;
  }

  if($async) {                                                                               # asynchoner non-blocking Mode
      readingsSingleUpdate($hash, 'CacheUsage', $memcount, ($ce == 1 ? 1 : 0)) if($DoIt);

      if($memcount >= $clim) {                                                           # asynchrone Schreibroutine aufrufen wenn Füllstand des Cache erreicht ist
          my $lmlr     = $hash->{HELPER}{LASTLIMITRUNTIME};
          my $syncival = AttrVal($name, "syncInterval", 30);

          if(!$lmlr || gettimeofday() > $lmlr+($syncival/2)) {

              Log3 ($name, 4, "$name - Number of cache entries reached cachelimit $clim - start database sync.");

              DbLog_execMemCacheAsync ($hash);

              $hash->{HELPER}{LASTLIMITRUNTIME} = gettimeofday();
          }
      }
  }

  if(!$async) {                                                                         # synchroner non-blocking Mode
      return if(defined $hash->{HELPER}{SHUTDOWNSEQ});                                  # Shutdown Sequenz läuft
      return if($hash->{HELPER}{REOPEN_RUNS});                                          # return wenn "reopen" mit Ablaufzeit gestartet ist

      readingsSingleUpdate($hash, 'CacheUsage', $memcount, ($ce == 1 ? 1 : 0)) if($DoIt);

      $err = DbLog_execMemCacheSync ($hash);
      DbLog_setReadingstate ($hash, $err) if($err);
  }

  $net = tv_interval($nst);                                                             # Notify-Routine Laufzeit ermitteln

  if(AttrVal($name, 'showNotifyTime', 0)) {
      readingsSingleUpdate($hash, 'notify_processing_time', sprintf("%.4f",$net), 1);
  }

return;
}

################################################################
# Parsefunktion, abhaengig vom Devicetyp
################################################################
sub _DbLog_ParseEvent {
  my ($name,$device, $type, $event)= @_;
  my (@result,$reading,$value,$unit);

  # Splitfunktion der Eventquelle aufrufen (ab 2.9.1)
  ($reading, $value, $unit) = CallInstanceFn($device, "DbLog_splitFn", $event, $device);
  # undef bedeutet, Modul stellt keine DbLog_splitFn bereit
  if($reading) {
      return ($reading, $value, $unit);
  }

  # split the event into reading, value and unit
  # "day-temp: 22.0 (Celsius)" -> "day-temp", "22.0 (Celsius)"
  my @parts = split /: /, $event;
  
  if(scalar @parts == 2) {                                               # V 5.8.8 default Splitting komplett umgebaut
      $reading = shift @parts;
      my $tail = shift @parts;
      @parts   = split " ", $tail;
      
      $value = $tail;
      $unit  = q{};
    
      if (scalar @parts <= 2 && looks_like_number($parts[0])) {
          $value = $parts[0];
          $unit  = $parts[1] // q{};            
      }
  }

  if(!defined($reading)) { $reading = ""; }
  if(!defined($value))   { $value   = ""; }
  if($value eq "") {                                                     
      if($event =~ /:\s/) {                                              # 21.01.20 Forum: #106769
          ($reading,$value) = split /: /, $event, 2;
      }
      else {
          $reading = "state";
          $value   = $event;
      }
  }

  # globales Abfangen von                                                 # changed in Version 4.12.5
  # - humidity
  if($reading =~ m(^humidity))    { $unit = "%"; }                        # wenn reading mit humidity beginnt


  # the interpretation of the argument depends on the device type
  # EMEM, M232Counter, M232Voltage return plain numbers
  if(($type eq "M232Voltage") ||
     ($type eq "M232Counter") ||
     ($type eq "EMEM")) {
  }
  #OneWire
  elsif(($type eq "OWMULTI")) {
      if(int(@parts) > 1) {
          $reading = "data";
          $value   = $event;
      }
      else {
          @parts = split(/\|/, AttrVal($device, $reading."VUnit", ""));
          $unit  = $parts[1] if($parts[1]);
          if(lc($reading) =~ m/temp/) {
              $value =~ s/ \(Celsius\)//;
              $value =~ s/([-\.\d]+).*/$1/;
              $unit  = "°C";
          } 
          elsif (lc($reading) =~ m/(humidity|vwc)/) {
              $value =~ s/ \(\%\)//;
             $unit  = "%";
          }
      }
  }
  # Onewire
  elsif(($type eq "OWAD") || ($type eq "OWSWITCH")) {
      if(int(@parts)>1) {
        $reading = "data";
        $value   = $event;
      }
      else {
        @parts = split(/\|/, AttrVal($device, $reading."Unit", ""));
        $unit  = $parts[1] if($parts[1]);
      }
  }

  # ZWAVE                                                             # V 5.8.8 rausgenommen
  #elsif ($type eq "ZWAVE") {
  #    if ( $value =~/([-\.\d]+)\s([a-z].*)/i ) {
  #        $value = $1;
  #        $unit  = $2;
  #    }
  #}

  # FBDECT
  elsif ($type eq "FBDECT") {
      if ( $value =~/([-\.\d]+)\s([a-z].*)/i ) {
          $value = $1;
          $unit  = $2;
      }
  }

  # MAX
  elsif(($type eq "MAX")) {
      $unit = "°C" if(lc($reading) =~ m/temp/);
      $unit = "%"  if(lc($reading) eq "valveposition");
  }

  # FS20
  elsif(($type eq "FS20") || ($type eq "X10")) {
      if($reading =~ m/^dim(\d+).*/o) {
          $value   = $1;
          $reading = "dim";
          $unit    = "%";
      } 
      elsif(!defined($value) || $value eq "") {
          $value   = $reading;
          $reading = "data";
      }
  }

  # FHT
  elsif($type eq "FHT") {
      if($reading =~ m(-from[12]\ ) || $reading =~ m(-to[12]\ )) {
          @parts   = split(/ /,$event);
          $reading = $parts[0];
          $value   = $parts[1];
          $unit    = "";
      } 
      elsif($reading =~ m(-temp)) {
          $value =~ s/ \(Celsius\)//; $unit= "°C";
      } 
      elsif($reading =~ m(temp-offset)) {
          $value =~ s/ \(Celsius\)//; $unit= "°C";
      } 
      elsif($reading =~ m(^actuator[0-9]*)) {
          if($value eq "lime-protection") {
              $reading = "actuator-lime-protection";
              undef $value;
          } 
          elsif($value =~ m(^offset:)) {
              $reading = "actuator-offset";
              @parts   = split(/: /,$value);
              $value   = $parts[1];
              if(defined $value) {
                  $value =~ s/%//; $value = $value*1.; $unit = "%";
              }
          } 
          elsif($value =~ m(^unknown_)) {
              @parts   = split(/: /,$value);
              $reading = "actuator-" . $parts[0];
              $value   = $parts[1];
              if(defined $value) {
                  $value =~ s/%//; $value = $value*1.; $unit = "%";
              }
          } 
          elsif($value =~ m(^synctime)) {
              $reading = "actuator-synctime";
              undef $value;
          } 
          elsif($value eq "test") {
              $reading = "actuator-test";
              undef $value;
          } 
          elsif($value eq "pair") {
              $reading = "actuator-pair";
              undef $value;
          }
          else {
              $value =~ s/%//; $value = $value*1.; $unit = "%";
          }
      }
  }
  # KS300
  elsif($type eq "KS300") {
      if($event =~ m(T:.*))            { $reading = "data"; $value = $event; }
      elsif($event =~ m(avg_day))      { $reading = "data"; $value = $event; }
      elsif($event =~ m(avg_month))    { $reading = "data"; $value = $event; }
      elsif($reading eq "temperature") { $value   =~ s/ \(Celsius\)//; $unit = "°C"; }
      elsif($reading eq "wind")        { $value   =~ s/ \(km\/h\)//; $unit = "km/h"; }
      elsif($reading eq "rain")        { $value   =~ s/ \(l\/m2\)//; $unit = "l/m2"; }
      elsif($reading eq "rain_raw")    { $value   =~ s/ \(counter\)//; $unit = ""; }
      elsif($reading eq "humidity")    { $value   =~ s/ \(\%\)//; $unit = "%"; }
      elsif($reading eq "israining") {
        $value =~ s/ \(yes\/no\)//;
        $value =~ s/no/0/;
        $value =~ s/yes/1/;
      }
  }
  # HMS
  elsif($type eq "HMS" || $type eq "CUL_WS" || $type eq "OWTHERM") {
      if($event =~ m(T:.*)) {
          $reading = "data"; $value= $event;
      } 
      elsif($reading eq "temperature") {
          $value =~ s/ \(Celsius\)//;
          $value =~ s/([-\.\d]+).*/$1/; #OWTHERM
          $unit  = "°C";
      } 
      elsif($reading eq "humidity") {
          $value =~ s/ \(\%\)//; $unit= "%";
      } 
      elsif($reading eq "battery") {
          $value =~ s/ok/1/;
          $value =~ s/replaced/1/;
          $value =~ s/empty/0/;
      }
  }
  # CUL_HM
  elsif ($type eq "CUL_HM") {
      $value =~ s/ \%$//;                           # remove trailing %
  }

  # BS
  elsif($type eq "BS") {
      if($event =~ m(brightness:.*)) {
          @parts   = split(/ /,$event);
          $reading = "lux";
          $value   = $parts[4]*1.;
          $unit    = "lux";
      }
  }

  # RFXTRX Lighting
  elsif($type eq "TRX_LIGHT") {
      if($reading =~ m/^level (\d+)/) {
          $value   = $1;
          $reading = "level";
      }
  }

  # RFXTRX Sensors
  elsif($type eq "TRX_WEATHER") {
      if($reading eq "energy_current") {
          $value =~ s/ W//;
      } 
      elsif($reading eq "energy_total") {
          $value =~ s/ kWh//;
      } 
      elsif($reading eq "battery") {
          if ($value =~ m/(\d+)\%/) {
              $value = $1;
          }
          else {
              $value = ($value eq "ok");
          }
      }
  }

  # Weather
  elsif($type eq "WEATHER") {
      if($event =~ m(^wind_condition)) {
          @parts = split(/ /,$event); # extract wind direction from event
          if(defined $parts[0]) {
              $reading = "wind_condition";
              $value   = "$parts[1] $parts[2] $parts[3]";
          }
      }
      if($reading eq "wind_condition")      { $unit = "km/h"; }
      elsif($reading eq "wind_chill")       { $unit = "°C"; }
      elsif($reading eq "wind_direction")   { $unit = ""; }
      elsif($reading =~ m(^wind))           { $unit = "km/h"; }      # wind, wind_speed
      elsif($reading =~ m(^temperature))    { $unit = "°C"; }        # wenn reading mit temperature beginnt
      elsif($reading =~ m(^humidity))       { $unit = "%"; }
      elsif($reading =~ m(^pressure))       { $unit = "hPa"; }
      elsif($reading =~ m(^pressure_trend)) { $unit = ""; }
  }

  # FHT8V
  elsif($type eq "FHT8V") {
      if($reading =~ m(valve)) {
          @parts   = split(/ /,$event);
          $reading = $parts[0];
          $value   = $parts[1];
          $unit    = "%";
      }
  }

  # Dummy
  elsif($type eq "DUMMY")  {
      if( $value eq "" ) {
          $reading = "data";
          $value   = $event;
      }
      $unit = "";
  }

  @result = ($reading,$value,$unit);

return @result;
}

#################################################################################################
#
# check zentrale Angabe von defaultMinInterval für alle Devices/Readings
# (kein Überschreiben spezifischer Angaben von DbLogExclude / DbLogInclude in den Quelldevices)
#
#################################################################################################
sub _DbLog_checkDefMinInt {
  my $paref    = shift;

  my $name     = $paref->{name};
  my $dev_name = $paref->{dev_name};
  my $now      = $paref->{now};
  my $reading  = $paref->{reading};
  my $value    = $paref->{value};

  my $force;
  my $DoIt = 1;

  my $defminint = AttrVal ($name, "defaultMinInterval", undef);
  return $DoIt if(!$defminint);                                                        # Attribut "defaultMinInterval" nicht im DbLog gesetzt -> kein ToDo

  my $DbLogExclude = AttrVal ($dev_name, "DbLogExclude", undef);
  $DbLogExclude    = join ",", DbLog_attrLong2Array ($DbLogExclude, ',');

  my $DbLogInclude = AttrVal ($dev_name, "DbLogInclude", undef);
  $DbLogInclude    = join ",", DbLog_attrLong2Array ($DbLogInclude, ',');

  $defminint       =~ s/[\s\n]/,/g;
  my @adef         = split /,/, $defminint;
  my $inex         = ($DbLogExclude ? $DbLogExclude."," : "").($DbLogInclude ? $DbLogInclude : "");

  if($inex) {                                                                          # Quelldevice hat DbLogExclude und/oder DbLogInclude gesetzt
      my @ie = split /,/, $inex;

      for (my $k = 0; $k < int(@ie); $k++) {                                           # Bsp. für das auszuwertende Element
          my @rif = split /:/, $ie[$k];                                                # "(temperature|humidity):300:force"

          if($reading =~ m,^$rif[0]$, && $rif[1]) {                                    # aktuelles Reading matcht auf Regexp und minInterval ist angegeben
              return $DoIt;                                                            # Reading wurde bereits geprüft -> kein Überschreiben durch $defminint
          }
      }
  }

  for (my $l = 0; $l < int(@adef); $l++) {
      my @adefelem = split "::", $adef[$l];                                             # Bsp. für ein defaulMInInterval Element:
      my @dvs      = devspec2array ($adefelem[0]);                                      # device::interval[::force]

      if(@dvs) {
          for (@dvs) {
              if($dev_name =~ m,^$_$,) {                                               # aktuelles Device matcht auf Regexp
                  my $lt = $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{TIME};     # device,reading wird gegen "defaultMinInterval" geprüft
                  my $lv = $defs{$dev_name}{Helper}{DBLOG}{$reading}{$name}{VALUE};    # "defaultMinInterval" gilt für alle Readings des devices
                  $lt    = 0  if(!$lt);
                  $lv    = "" if(!defined $lv);                                        # Forum: #100344
                  $force = ($adefelem[2] && $adefelem[2] =~ /force/i) ? 1 : 0;         # Forum: #97148

                  if(($now-$lt < $adefelem[1]) && ($lv eq $value || $force)) {         # innerhalb defaultMinInterval und LastValue=Value oder force-Option
                      $DoIt = 0;                                                       # Log3 ($name, 1, "$name - defaulMInInterval - device \"$dev_name\", reading \"$reading\" inside of $adefelem[1] seconds (force: $force) -> don't log it !");
                      return $DoIt;
                  }
              }
          }
      }
  }

return $DoIt;
}

##########################################################################################
#  Einen Datensatz zum Memory Cache hinzufügen, gibt die Anzahl Datensätze im Memory
#  Cache zurück ($memcount)
#
#  $row hat die Form:
#  $timestamp."|".$dev_name."|".$dev_type."|".$event."|".$reading."|".$value."|".$unit
##########################################################################################
sub DbLog_addMemCacheRow {
  my $name = shift;
  my $row  = shift;

  if ($row) {
      $data{DbLog}{$name}{cache}{index}++;
      my $index                                    = $data{DbLog}{$name}{cache}{index};
      $data{DbLog}{$name}{cache}{memcache}{$index} = $row;
  }

  my $memcount = defined $data{DbLog}{$name}{cache}{memcache}         ?
                 scalar(keys %{$data{DbLog}{$name}{cache}{memcache}}) :
                 0;

return $memcount;
}

#################################################################################################
#    MemCache auswerten und Schreibroutine asynchron non-blocking ausführen
#################################################################################################
sub DbLog_execMemCacheAsync {
  my $hash       = shift;
  my $name       = $hash->{NAME};

  my $async      = AttrVal($name, 'asyncMode', 0);

  RemoveInternalTimer($hash, 'DbLog_execMemCacheAsync');

  if(!$async || IsDisabled($name) || $init_done != 1) {
      InternalTimer(gettimeofday()+5, 'DbLog_execMemCacheAsync', $hash, 0);
      return;
  }

  my $nextsync = gettimeofday() + AttrVal($name, 'syncInterval', 30);
  my $se       = AttrVal ($name, 'syncEvents', undef) ? 1 : 0;
  my $clim     = AttrVal ($name, "cacheLimit", $dblog_cachedef);

  readingsSingleUpdate($hash, 'NextSync', FmtDateTime ($nextsync). " or when CacheUsage ".$clim." is reached", $se);

  DbLog_SBP_CheckAndInit ($hash);                                                            # Subprocess checken und ggf. initialisieren
  return if(!defined $hash->{".fhem"}{subprocess});

  my $ce       = AttrVal ($name, 'cacheEvents', 0);
  my $memcount = defined $data{DbLog}{$name}{cache}{memcache}         ?
                 scalar(keys %{$data{DbLog}{$name}{cache}{memcache}}) :
                 0;

  readingsSingleUpdate ($hash, 'CacheUsage', $memcount, ($ce == 2 ? 1 : 0));

  my $params   = {
      hash     => $hash,
      clim     => $clim,
      memcount => $memcount
  };

  if($hash->{HELPER}{REOPEN_RUNS}) {                                                         # return wenn "reopen" mit Zeitangabe läuft
      DbLog_writeFileIfCacheOverflow ($params);                                              # Cache exportieren bei Overflow
      return;
  }

  my $err;
  my $verbose = AttrVal ($name, 'verbose', 3);
  my $dolog   = $memcount ? 1 : 0;

  if(defined $hash->{HELPER}{LONGRUN_PID}) {
      $dolog = 0;
  }

  if($verbose > 3 && $dolog) {
      Log3 ($name, 4, "$name - ################################################################");
      Log3 ($name, 4, "$name - ###      New database processing cycle - SBP asynchronous    ###");
      Log3 ($name, 4, "$name - ################################################################");
      Log3 ($name, 4, "$name - MemCache contains $memcount entries to process");
      Log3 ($name, 4, "$name - DbLogType is: ".AttrVal($name, 'DbLogType', 'History'));
  }

  if($dolog) {
      my $wrotefile = DbLog_writeFileIfCacheOverflow ($params);                            # Cache exportieren bei Overflow
      return if($wrotefile);

      DbLog_logHashContent ( {name => $name, href => $data{DbLog}{$name}{cache}{memcache}, level => 5, logtxt => 'MemCache contains: '} );

      my $memc = _DbLog_copyCache      ($name);
      $err     = DbLog_SBP_sendLogData ($hash, 'log_asynch', $memc);                       # Subprocess Prozessdaten senden, Log-Daten sind in $memc->{cdata} gespeichert
  }
  else {
      if(defined $hash->{HELPER}{LONGRUN_PID}) {
          $err = 'Another operation is in progress - resync at NextSync';
          DbLog_writeFileIfCacheOverflow ($params);                                        # Cache exportieren bei Overflow
      }
      else {
          if(defined $hash->{HELPER}{SHUTDOWNSEQ}) {
              Log3 ($name, 2, "$name - no data for last database write cycle");
              _DbLog_finishDelayedShutdown ($hash);
          }
      }
  }

  DbLog_setReadingstate ($hash, $err);

  InternalTimer($nextsync, 'DbLog_execMemCacheAsync', $hash, 0);

return;
}

#################################################################################################
#        MemCache auswerten und Schreibroutine synchron non-blocking ausführen
#################################################################################################
sub DbLog_execMemCacheSync {
  my $hash = shift;

  my $err = DbLog_SBP_CheckAndInit ($hash);                                                    # Subprocess checken und ggf. initialisieren
  return $err if($err);

  if(defined $hash->{HELPER}{LONGRUN_PID}) {
      if (gettimeofday() - $hash->{HELPER}{LONGRUN_PID} > $dblog_lrpth) {
          $err = 'Another operation is in progress. <br>Data is stored temporarily.';
          DbLog_setReadingstate ($hash, $err);
      }
      return;
  }

  my $name    = $hash->{NAME};
  my $verbose = AttrVal ($name, 'verbose', 3);

  if($verbose > 3) {
      Log3 ($name, 4, "$name - ################################################################");
      Log3 ($name, 4, "$name - ###      New database processing cycle - SBP synchronous     ###");
      Log3 ($name, 4, "$name - ################################################################");
  }

  DbLog_logHashContent ( {name => $name, href => $data{DbLog}{$name}{cache}{memcache}, level => 5, logtxt => 'TempStore contains: '} );

  my $memc = _DbLog_copyCache ($name);

  readingsSingleUpdate($hash, 'CacheUsage', 0, 0);

  $err = DbLog_SBP_sendLogData ($hash, 'log_synch', $memc);                               # Subprocess Prozessdaten senden, Log-Daten sind in $memc->{cdata} gespeichert
  return $err if($err);

return;
}

#################################################################################################
#        Memory Cache kopieren und löschen
#################################################################################################
sub _DbLog_copyCache {
  my $name = shift;

  my $memc;

  while (my ($key, $val) = each %{$data{DbLog}{$name}{cache}{memcache}} ) {
      $memc->{cdata}{$key} = $val;                                              # Subprocess Daten, z.B.:  2022-11-29 09:33:32|SolCast|SOLARFORECAST||nextCycletime|09:33:47|
  }

  $memc->{cdataindex} = $data{DbLog}{$name}{cache}{index};                      # aktuellen Index an Subprozess übergeben

  undef %{$data{DbLog}{$name}{cache}{memcache}};                                # Löschen mit Memory freigeben: https://perlmaven.com/undef-on-perl-arrays-and-hashes , bzw. https://www.effectiveperlprogramming.com/2018/09/undef-a-scalar-to-release-its-memory/

return $memc;
}

#################################################################
# SubProcess - Hauptprozess gestartet durch _DbLog_SBP_Init
# liest Daten vom Parentprozess mit
# $subprocess->readFromParent()
#
# my $parent = $subprocess->parent();
#
# $store    - semipermanenter Datenspeicher
# $logstore - temporärer Logdatenspeicher
# $memc     - Operationsspeicher
#
#################################################################
sub DbLog_SBP_onRun {
  my $subprocess = shift;
  my $name       = $subprocess->{name};
  my $store;                                                                      # semipermanenter Datenspeicher
  my $logstore;                                                                   # temporärer Logdatenspeicher

  while (1) {
      my $serial = $subprocess->readFromParent();

      if(defined $serial) {
          my $memc        = eval { thaw ($serial) };                              # Operationsspeicher

          my $dbstorepars = $memc->{dbstorepars};                                 # 1 -> DB Parameter werden zum Speichern übermittelt, sonst 0
          my $dbdelpars   = $memc->{dbdelpars};                                   # 1 -> gespeicherte DB Parameter sollen gelöscht werden
          my $dbdisconn   = $memc->{dbdisconn};                                   # 1 -> die Datenbankverbindung lösen/löschen

          my $verbose     = $memc->{verbose};                                     # verbose Level
          my $operation   = $memc->{operation} // 'unknown';                      # aktuell angeforderte Operation (log, etc.)
          my $cdata       = $memc->{cdata};                                       # Log Daten, z.B.: 3399 => 2022-11-29 09:33:32|SolCast|SOLARFORECAST||nextCycletime|09:33:47|

          my $error       = q{};
          my $doNext      = 0;
          my $ret;

          ##  Vorbereitungen
          ####################

          $attr{$name}{verbose} = $verbose if(defined $verbose);                      # verbose Level übergeben
          my $bst               = [gettimeofday];                                     # Background-Startzeit
                                                                                      # prüfen ob Datenbankverbindung beendet werden soll
          $doNext = _DbLog_SBP_checkDiscDelpars ({ subprocess => $subprocess,
                                                   name       => $name,
                                                   memc       => $memc,
                                                   store      => $store
                                                 }
                                                );

          if ($doNext) {
              next;
          }

          if ($dbstorepars) {                                                     # DB Verbindungsparameter speichern
              _DbLog_SBP_Log3Parent ( { name       => $name,
                                        level      => 3,
                                        msg        => qq(DB connection parameters are stored in SubProcess),
                                        oper       => 'log3parent',
                                        subprocess => $subprocess
                                      }
                                    );

              $store->{dbparams}{dbconn}      = $memc->{dbconn};
              $store->{dbparams}{dbname}      = (split /;|=/, $memc->{dbconn})[1];
              $store->{dbparams}{dbuser}      = $memc->{dbuser};
              $store->{dbparams}{dbpassword}  = $memc->{dbpassword};
              $store->{dbparams}{utf8}        = $memc->{utf8};                    # Database UTF8 0|1
              $store->{dbparams}{model}       = $memc->{model};                   # DB Model
              $store->{dbparams}{sltjm}       = $memc->{sltjm};                   # SQLiteJournalMode
              $store->{dbparams}{sltcs}       = $memc->{sltcs};                   # SQLiteCacheSize
              $store->{dbparams}{cm}          = $memc->{cm};                      # Commit Mode
              $store->{dbparams}{history}     = $memc->{history};                 # Name history-Tabelle
              $store->{dbparams}{current}     = $memc->{current};                 # Name current-Tabelle
              $store->{dbparams}{dbstorepars} = $memc->{dbstorepars};             # Status Speicherung DB Parameter 0|1
              $store->{dbparams}{cofaults}    = 0;                                # Anzahl Connectfehler seit letztem erfolgreichen Connect


              DbLog_logHashContent ( {name => $name, href => $store->{dbparams}, level => 5, subprocess => $subprocess} );

              $ret = {
                  name => $name,
                  msg  => 'Connection parameters saved into SubProcess. <br>Connection to DB is established when it is needed.',
                  oper => $operation,
                  ot   => 0
              };

              __DbLog_SBP_sendToParent ($subprocess, $ret);

              next;
          }

          if (!defined $store->{dbparams}{dbstorepars}) {
              $error = qq{DB connection params havn't yet been passed to the subprocess. Data is stored temporarily.};

              _DbLog_SBP_Log3Parent ( { name       => $name,
                                        level      => 3,
                                        msg        => $error,
                                        oper       => 'log3parent',
                                        subprocess => $subprocess
                                      }
                                    );

              for my $idx (sort {$a<=>$b} keys %{$cdata}) {
                  $logstore->{$idx} = $cdata->{$idx};

                  _DbLog_SBP_Log3Parent ( { name       => $name,
                                            level      => 4,
                                            msg        => "stored: $idx -> ".$logstore->{$idx},
                                            oper       => 'log3parent',
                                            subprocess => $subprocess
                                          }
                                        );
              }

              _DbLog_SBP_Log3Parent ( { name       => $name,
                                        level      => 3,
                                        msg        => qq(DB Connection parameters were requested ...),
                                        oper       => 'log3parent',
                                        subprocess => $subprocess
                                      }
                                    );

              $ret = {
                  name     => $name,
                  msg      => $error,
                  ot       => 0,
                  oper     => $operation,
                  reqdbdat => 1                                                                  # Request Übertragung DB Verbindungsparameter
              };

              __DbLog_SBP_sendToParent ($subprocess, $ret);

              next;
          }

          my $cm             = $store->{dbparams}{cm};
          my ($useac,$useta) = DbLog_commitMode ($name, $cm);

          ## Verbindungsaufbau Datenbank
          ################################
          $doNext = _DbLog_SBP_manageDBconnect ({ subprocess => $subprocess,
                                                  name       => $name,
                                                  memc       => $memc,
                                                  store      => $store,
                                                  operation  => $operation,
                                                  useac      => $useac
                                                }
                                               );

          if ($doNext) {
              _DbLog_SBP_doWait (1000000);
              next;
          }

          ##  Event Logging
          #########################################################
          if ($operation =~ /log_/xs) {
              my $im = $memc->{im};                                          # Insert-Mode 0|1

              if ($im) {
                  _DbLog_SBP_onRun_LogSequential ( { subprocess => $subprocess,
                                                     name       => $name,
                                                     memc       => $memc,
                                                     store      => $store,
                                                     logstore   => $logstore,
                                                     useta      => $useta,
                                                     bst        => $bst
                                                   }
                                                 );
              }
              else {
                  _DbLog_SBP_onRun_LogArray ( { subprocess => $subprocess,
                                                name       => $name,
                                                memc       => $memc,
                                                store      => $store,
                                                logstore   => $logstore,
                                                useta      => $useta,
                                                bst        => $bst
                                              }
                                            );
              }
          }

          ##  Kommando: count
          #########################################################
          if ($operation =~ /count/xs) {
              _DbLog_SBP_onRun_Count ( { subprocess => $subprocess,
                                         name       => $name,
                                         memc       => $memc,
                                         store      => $store,
                                         bst        => $bst
                                       }
                                     );
          }

          ##  Kommando: deleteOldDays
          #########################################################
          if ($operation =~ /deleteOldDays/xs) {
              _DbLog_SBP_onRun_deleteOldDays ( { subprocess => $subprocess,
                                                 name       => $name,
                                                 memc       => $memc,
                                                 store      => $store,
                                                 bst        => $bst
                                               }
                                             );
          }

          ##  Kommando: userCommand
          #########################################################
          if ($operation =~ /userCommand/xs) {
              _DbLog_SBP_onRun_userCommand ( { subprocess => $subprocess,
                                               name       => $name,
                                               memc       => $memc,
                                               store      => $store,
                                               bst        => $bst
                                               }
                                             );
          }

          ##  Kommando: importCachefile
          #########################################################
          if ($operation =~ /importCachefile/xs) {
              _DbLog_SBP_onRun_importCachefile ( { subprocess => $subprocess,
                                                   name       => $name,
                                                   memc       => $memc,
                                                   store      => $store,
                                                   logstore   => $logstore,
                                                   bst        => $bst
                                                 }
                                               );
          }

          ##  Kommando: reduceLog
          #########################################################
          if ($operation =~ /reduceLog/xs) {
              _DbLog_SBP_onRun_reduceLog ( { subprocess => $subprocess,
                                             name       => $name,
                                             memc       => $memc,
                                             store      => $store,
                                             bst        => $bst
                                           }
                                         );
          }
      }

  _DbLog_SBP_doWait ();
  }

return;
}

###################################################################################
#   prüfen ob Datenbankverbindung beendet werden soll und ob die
#   gespeicherten Verbindungsparameter gelöscht werden sollen
###################################################################################
sub _DbLog_SBP_checkDiscDelpars {
  my $paref      = shift;

  my $subprocess = $paref->{subprocess};
  my $name       = $paref->{name};
  my $memc       = $paref->{memc};
  my $store      = $paref->{store};                                        # Datenspeicher

  my $dbdelpars  = $memc->{dbdelpars};                                     # 1 -> gespeicherte DB Parameter sollen gelöscht werden
  my $dbdisconn  = $memc->{dbdisconn};                                     # 1 -> die Datenbankverbindung lösen/löschen
  my $operation  = $memc->{operation} // 'unknown';
  my $doNext     = 0;

  if ($dbdisconn) {
      if (defined $store->{dbh}) {
          my $dbh = delete $store->{dbh};
          $dbh->disconnect();
      }

      if ($dbdelpars) {
          delete $store->{dbparams};
      }

      my $msg0 = $dbdelpars ? ' <br>Stored DB params in SubProcess were deleted.' : '';
      my $msg1 = 'Database disconnected by request.'.$msg0;
      my $msg2 = $msg1;
      $msg2    =~ s/<br>//xs;

      _DbLog_SBP_Log3Parent ( { name       => $name,
                                level      => 3,
                                msg        => $msg2,
                                oper       => 'log3parent',
                                subprocess => $subprocess
                              }
                            );

      my $ret = {
            name => $name,
            msg  => $msg1,
            oper => $operation,
            ot   => 0
      };

      __DbLog_SBP_sendToParent ($subprocess, $ret);

      $doNext = 1;
  }

return $doNext;
}

#################################################################
#          Wartezeit blockierend
#          reduziert CPU Last im "Leerlauf"
#################################################################
sub _DbLog_SBP_doWait {
  my $wtus = shift // 300000;       # Mikrosekunden

  usleep($wtus);

return;
}

###################################################################################
#   Verbindungsmanagement Datenbank
###################################################################################
sub _DbLog_SBP_manageDBconnect {
  my $paref      = shift;

  my $subprocess = $paref->{subprocess};
  my $name       = $paref->{name};
  my $memc       = $paref->{memc};
  my $store      = $paref->{store};                                           # Datenspeicher
  my $useac      = $paref->{useac};
  my $operation  = $paref->{operation};

  my $isNew      = 0;                                                         # wurde Database Handle neu erstellt ?
  my $doNext     = 0;

  my ($err, $dbh, $ret);

  my $params = { name       => $name,
                 dbconn     => $store->{dbparams}{dbconn},
                 dbname     => $store->{dbparams}{dbname},
                 dbuser     => $store->{dbparams}{dbuser},
                 dbpassword => $store->{dbparams}{dbpassword},
                 utf8       => $store->{dbparams}{utf8},
                 useac      => $useac,
                 model      => $store->{dbparams}{model},
                 sltjm      => $store->{dbparams}{sltjm},
                 sltcs      => $store->{dbparams}{sltcs},
                 cofaults   => $store->{dbparams}{cofaults},
                 subprocess => $subprocess
               };

  if (!defined $store->{dbh}) {
      ($err, $dbh) = _DbLog_SBP_connectDB ($params);

      if ($err) {
          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 4,
                                    msg        => qq(Database Connection impossible. Transferred data is returned to the cache.),
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );

          $ret = {
              name     => $name,
              msg      => $err,
              ot       => 0,
              oper     => $operation,
              rowlback => $memc->{cdata}                                     # Rückgabe aller übergebenen Log-Daten
          };

          $doNext = 1;

          $store->{dbparams}{cofaults}++;
          __DbLog_SBP_sendToParent ($subprocess, $ret);

          return $doNext;
      }

      $store->{dbparams}{cofaults} = 0;
      $isNew                       = 1;
      $store->{dbh}                = $dbh;

      _DbLog_SBP_Log3Parent ( { name       => $name,
                                level      => 3,
                                msg        => qq(SubProcess connected to $store->{dbparams}{dbname}),
                                oper       => 'log3parent',
                                subprocess => $subprocess
                              }
                            );
  }

  $dbh = $store->{dbh};

  if (!$isNew) {                                                                           # kein neuer Database Handle

      my $bool = _DbLog_SBP_pingDB ( {name => $name, dbh => $dbh, subprocess => $subprocess} );

      if (!$bool) {                                                                        # DB Session dead
          delete $store->{dbh};

          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 4,
                                    msg        => qq(Database Connection dead. Try reconnect ...),
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );

          ($err, $dbh) = _DbLog_SBP_connectDB ($params);

          if ($err) {
              _DbLog_SBP_Log3Parent ( { name       => $name,
                                        level      => 4,
                                        msg        => qq(Database Reconnect impossible. Transferred data is returned to the cache.),
                                        oper       => 'log3parent',
                                        subprocess => $subprocess
                                      }
                                    );

              $ret = {
                  name     => $name,
                  msg      => $err,
                  ot       => 0,
                  oper     => $operation,
                  rowlback => $memc->{cdata}                                               # Rückgabe aller übergebenen Log-Daten
              };

              $doNext = 1;

              $store->{dbparams}{cofaults}++;
              __DbLog_SBP_sendToParent ($subprocess, $ret);

              return $doNext;
          }

          $store->{dbparams}{cofaults} = 0;
          $store->{dbh}                = $dbh;
      }
  }

return $doNext;
}

###################################################################################
#               neue Datenbankverbindung im SubProcess
#
#   RaiseError - handle attribute (which tells DBI to call the Perl die( )
#                function upon error
#   PrintError - handle attribute tells DBI to call the Perl warn( ) function
#                (which typically results in errors being printed to the screen
#                when encountered)
#
# For maximum reliability and for robustness against database corruption,
# SQLite should always be run with its default synchronous setting of FULL.
# https://sqlite.org/howtocorrupt.html
###################################################################################
sub _DbLog_SBP_connectDB {
  my $paref      = shift;

  my $name       = $paref->{name};
  my $dbconn     = $paref->{dbconn};
  my $dbuser     = $paref->{dbuser};
  my $dbpassword = $paref->{dbpassword};
  my $utf8       = $paref->{utf8};
  my $useac      = $paref->{useac};
  my $model      = $paref->{model};
  my $sltjm      = $paref->{sltjm};
  my $sltcs      = $paref->{sltcs};
  my $cofaults   = $paref->{cofaults}   // 0;              # Anzahl Connectfehler seit letztem erfolgreichen Connect
  my $subprocess = $paref->{subprocess} // q{};

  my $dbh = q{};
  my $err = q{};

  eval { if (!$useac) {
             $dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError          => 0,
                                                                        RaiseError          => 1,
                                                                        AutoCommit          => 0,
                                                                        ShowErrorStatement  => 1,
                                                                        AutoInactiveDestroy => 1
                                                                      }
                                );
         }
         elsif ($useac == 1) {
             $dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError          => 0,
                                                                        RaiseError          => 1,
                                                                        AutoCommit          => 1,
                                                                        ShowErrorStatement  => 1,
                                                                        AutoInactiveDestroy => 1
                                                                      }
                                );
         }
         else {                                                                                          # Server default
             $dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0,
                                                                        RaiseError => 1,
                                                                        ShowErrorStatement  => 1,
                                                                        AutoInactiveDestroy => 1
                                                                      }
                                );
         }
         1;
      }
      or do { $err = $@;
              if ($cofaults <= 10) {
                  _DbLog_SBP_Log3Parent ( { name       => $name,
                                            level      => 2,
                                            msg        => qq(ERROR: $err),
                                            oper       => 'log3parent',
                                            subprocess => $subprocess
                                          }
                                        );
              }

              if ($cofaults == 10) {
                  _DbLog_SBP_Log3Parent ( { name       => $name,
                                            level      => 2,
                                            msg        => qq(There seems to be a permanent connection error to the database. Further error messages are suppressed.),
                                            oper       => 'log3parent',
                                            subprocess => $subprocess
                                          }
                                        );
              }

              return $err;
            };

  return $DBI::errstr if($DBI::errstr);

  if($utf8) {
      if($model eq "MYSQL") {
          $dbh->{mysql_enable_utf8} = 1;

          ($err, my @se) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW VARIABLES LIKE 'collation_database'");
          return ($err, q{}) if($err);

          my $dbcharset = @se ? $se[1] : 'noresult';

          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 4,
                                    msg        => qq(Database Character set is >$dbcharset<),
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );

          if ($dbcharset !~ /noresult|ucs2|utf16|utf32/ixs) {                                                                 # Impermissible Client Character Sets -> https://dev.mysql.com/doc/refman/8.0/en/charset-connection.html
              my $collation = $dbcharset;
              $dbcharset    = (split '_', $collation, 2)[0];

              ($err, undef) = _DbLog_SBP_dbhDo ($name, $dbh, qq(set names "$dbcharset" collate "$collation"), $subprocess);   # set names utf8 collate utf8_general_ci
              return ($err, q{}) if($err);
          }
      }

      if($model eq "SQLITE") {
        ($err, undef) = _DbLog_SBP_dbhDo ($name, $dbh, 'PRAGMA encoding="UTF-8"', $subprocess);
        return ($err, q{}) if($err);
      }
  }

  if ($model eq 'SQLITE') {
      my @dos = ("PRAGMA temp_store=MEMORY",
                 "PRAGMA synchronous=FULL",
                 "PRAGMA journal_mode=$sltjm",
                 "PRAGMA cache_size=$sltcs"
                );

      for my $do (@dos) {
          ($err, undef) = _DbLog_SBP_dbhDo ($name, $dbh, $do, $subprocess);
          return ($err, q{}) if($err);
      }
  }

return ($err, $dbh);
}

####################################################################################################
#  einfaches Sdbh->do, return ERROR-String wenn Fehler bzw. die Anzahl der betroffenen Zeilen
####################################################################################################
sub _DbLog_SBP_dbhDo {
  my $name       = shift;
  my $dbh        = shift;
  my $sql        = shift;
  my $subprocess = shift // q{};
  my $info       = shift // "simple do statement: $sql";

  my $err = q{};
  my $rv  = q{};

  Log3 ($name, 4, "$name - $info");

  eval{ $rv = $dbh->do($sql);
        1;
      }
      or do { $err = $@;
              _DbLog_SBP_Log3Parent ( { name       => $name,
                                        level      => 2,
                                        msg        => qq(ERROR - $err),
                                        oper       => 'log3parent',
                                        subprocess => $subprocess
                                      }
                                    );
            };

return ($err, $rv);
}

############################################################################
#          Datenbank Ping
# ohne alarm (timeout) bleibt ping hängen wenn DB nicht
# errichbar ist
# https://perldoc.perl.org/functions/alarm
#
# andere: Variante (hat nicht funktioniert):
# local $SIG{ALRM} = sub { die "Timeout\n" };
# -> https://blogs.perl.org/users/leon_timmermans/2012/01/what-you-should-know-about-signal-based-timeouts.html
############################################################################
sub _DbLog_SBP_pingDB {
  my $paref      = shift;

  my $name       = $paref->{name};
  my $dbh        = $paref->{dbh};
  my $to         = $paref->{to}         // 10;
  my $subprocess = $paref->{subprocess} // q{};

  my $bool;

  eval {
      POSIX::sigaction(SIGALRM, POSIX::SigAction->new(sub {die "Timeout"}));

      alarm $to;

      eval { $bool = $dbh->ping;
           };

      alarm 0;

      if ($@ && $@ =~ /Timeout/xs) {
          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 2,
                                    msg        => qq(Database Ping Timeout of >$to seconds< reached),
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );
      }

  };

  alarm 0;                                                                              # Schutz vor Race Condition

return $bool;
}

############################################################################
# DBH set
# PrintError = 1, RaiseError = 0
############################################################################
sub _DbLog_SBP_dbhPrintError {
  my $dbh = shift;

  $dbh->{PrintError} = 1;
  $dbh->{RaiseError} = 0;

return;
}

############################################################################
# DBH set
# PrintError = 0, RaiseError = 1
############################################################################
sub _DbLog_SBP_dbhRaiseError {
  my $dbh = shift;

  $dbh->{PrintError} = 0;
  $dbh->{RaiseError} = 1;

return;
}

#################################################################
# SubProcess - Log-Routine
# Bulk-Insert
#################################################################
sub _DbLog_SBP_onRun_LogSequential {
  my $paref       = shift;

  my $subprocess  = $paref->{subprocess};
  my $name        = $paref->{name};
  my $memc        = $paref->{memc};
  my $store       = $paref->{store};                                      # Datenspeicher
  my $logstore    = $paref->{logstore};                                   # temporärer Logdatenspeicher
  my $useta       = $paref->{useta};
  my $bst         = $paref->{bst};

  my $DbLogType   = $memc->{DbLogType};                                   # Log-Ziele
  my $nsupk       = $memc->{nsupk};                                       # No Support PK 0|1
  my $tl          = $memc->{tl};                                          # traceLevel
  my $tf          = $memc->{tf};                                          # traceFlag
  my $operation   = $memc->{operation} // 'unknown';                      # aktuell angeforderte Operation (log, etc.)
  my $cdata       = $memc->{cdata};                                       # Log Daten, z.B.: 3399 => 2022-11-29 09:33:32|SolCast|SOLARFORECAST||nextCycletime|09:33:47|
  my $index       = $memc->{cdataindex};                                  # aktueller Cache-Index

  my $dbh         = $store->{dbh};
  my $dbconn      = $store->{dbparams}{dbconn};
  my $model       = $store->{dbparams}{model};
  my $history     = $store->{dbparams}{history};
  my $current     = $store->{dbparams}{current};

  my $error       = q{};
  my $rowlback    = {};                                                   # Hashreferenz Eventliste für Rückgabe wenn Fehler
  my $nins_hist   = 0;

  my $ret;

  if ($tl) {                                                              # Tracelevel setzen
      $dbh->{TraceLevel} = "$tl|$tf";
  }
  else {
      $dbh->{TraceLevel} = '0';
  }

  __DbLog_SBP_logLogmodes ($paref);

  my ($usepkh,$usepkc,$pkh,$pkc);

  if (!$nsupk) {                                                                      # check ob PK verwendet wird, @usepkx?Anzahl der Felder im PK:0 wenn kein PK, $pkx?Namen der Felder:none wenn kein PK
      ($usepkh,$usepkc,$pkh,$pkc) = DbLog_checkUsePK ( { name     => $name,
                                                         dbh      => $dbh,
                                                         dbconn   => $dbconn,
                                                         history  => $history,
                                                         current  => $current
                                                       }
                                                     );
  }
  else {
      _DbLog_SBP_Log3Parent ( { name       => $name,
                                level      => 5,
                                msg        => qq(Primary Key usage suppressed by attribute noSupportPK),
                                oper       => 'log3parent',
                                subprocess => $subprocess
                              }
                            );
  }

  my $ln = scalar keys %{$logstore};

  if ($ln) {                                                                         # temporär gespeicherte Daten hinzufügen
      for my $index (sort {$a<=>$b} keys %{$logstore}) {
          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 4,
                                    msg        => qq(add stored data: $index -> ).$logstore->{$index},
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );

          $cdata->{$index} = delete $logstore->{$index};
      }

      undef %{$logstore};

      _DbLog_SBP_Log3Parent ( { name       => $name,
                                level      => 4,
                                msg        => qq(logstore deleted - $ln stored datasets added for processing),
                                oper       => 'log3parent',
                                subprocess => $subprocess
                              }
                            );
  }

  my $faref    = __DbLog_SBP_fieldArrays ($name, $cdata, $subprocess);               # Feldarrays erstellen mit Logausgabe
  my $ceti     = scalar keys %{$cdata};
  my $ins_hist = 0;                                                                  # Forum: https://forum.fhem.de/index.php?msg=1284228
  my $rv       = 0;

  my (@ins,$st,$sth_ih);

  if (lc($DbLogType) =~ m(history)) {                                                # insert history mit/ohne primary key
      for my $key (sort {$a<=>$b} keys %{$cdata}) {
          my $row = $cdata->{$key};
          push @ins, $row;
      }
  }

  $st = [gettimeofday];                                                              # SQL-Startzeit

  if (lc($DbLogType) =~ m(history)) {                                                # insert history mit/ohne primary key
      ($error, $sth_ih) = __DbLog_SBP_sthInsTable ( { table => $history,
                                                      dbh   => $dbh,
                                                      model => $model,
                                                      usepk => $usepkh
                                                    }
                                                  );

      if ($error) {                                                                  # Eventliste zurückgeben wenn z.B. Disk I/O Error bei SQLITE
          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 2,
                                    msg        => qq(ERROR - $error),
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );

          __DbLog_SBP_disconnectOnly ($name, $dbh, $subprocess);
          delete $store->{dbh};

          $ret = {
              name     => $name,
              msg      => $error,
              ot       => 0,
              oper     => $operation,
              rowlback => $cdata
          };

          __DbLog_SBP_sendToParent ($subprocess, $ret);
          return;
      }

      if ($tl) {                                                                     # Tracelevel setzen
          $sth_ih->{TraceLevel} = "$tl|$tf";
      }
      else {
          $sth_ih->{TraceLevel} = '0';
      }

      $error = __DbLog_SBP_beginTransaction ($name, $dbh, $useta, $subprocess);

      if(!$useta) {                                                                  # keine Transaktion: generate errstr, keine Ausnahme
          _DbLog_SBP_dbhPrintError ($dbh);
      }

      eval { for my $ds (@ins) {
                 my @ao = split '\\|', $ds;
                 s/_ESC_/\|/gxs for @ao;                                             # escaped Pipe back to "|"

                 unless ($rv = $sth_ih->execute ($ao[0], $ao[1], $ao[2], $ao[3], $ao[4], $ao[5], $ao[6])) {
                     _DbLog_SBP_Log3Parent ( { name       => $name,
                                               level      => 2,
                                               msg        => "ERROR in >$operation< - ".$sth_ih->errstr,
                                               oper       => 'log3parent',
                                               subprocess => $subprocess
                                             }
                                           );
                 }
                 else {
                     $ins_hist += $rv;
                 }
             }
             1;
           }
           or do { $error = $@;
                   _DbLog_SBP_Log3Parent ( { name       => $name,
                                             level      => 2,
                                             msg        => "ERROR table $history - $error",
                                             oper       => 'log3parent',
                                             subprocess => $subprocess
                                           }
                                         );

                   if($useta) {
                       $rowlback = $cdata;                                          # nicht gespeicherte Datensätze nur zurück geben wenn Transaktion ein

                       _DbLog_SBP_Log3Parent ( { name       => $name,
                                                 level      => 4,
                                                 msg        => "Transaction is switched on. Transferred data is returned to the cache.",
                                                 oper       => 'log3parent',
                                                 subprocess => $subprocess
                                               }
                                             );
                   }
                   else {
                       _DbLog_SBP_Log3Parent ( { name       => $name,
                                                 level      => 2,
                                                 msg        => "Transaction is switched off. Transferred data is lost.",
                                                 oper       => 'log3parent',
                                                 subprocess => $subprocess
                                               }
                                             );
                   }

                   _DbLog_SBP_dbhRaiseError ($dbh);
                   __DbLog_SBP_rollbackOnly ($name, $dbh, $history, $subprocess);

                   $ret = {
                       name     => $name,
                       msg      => $error,
                       ot       => 0,
                       oper     => $operation,
                       rowlback => $rowlback
                   };

                   __DbLog_SBP_sendToParent ($subprocess, $ret);

                   return;
                 };

      _DbLog_SBP_dbhRaiseError ($dbh);
      __DbLog_SBP_commitOnly   ($name, $dbh, $history, $subprocess);

      if($ins_hist == $ceti) {
          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 4,
                                    msg        => "$ins_hist of $ceti events inserted into table >$history<".($usepkh ? " using PK on columns $pkh" : ""),
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );
      }
      else {
          if($usepkh) {
              _DbLog_SBP_Log3Parent ( { name       => $name,
                                        level      => 3,
                                        msg        => "INFO - ".$ins_hist." of $ceti events inserted into table >$history< due to PK on columns $pkh",
                                        oper       => 'log3parent',
                                        subprocess => $subprocess
                                      }
                                    );
          }
          else {
              _DbLog_SBP_Log3Parent ( { name       => $name,
                                        level      => 2,
                                        msg        => "WARNING - only ".$ins_hist." of $ceti events inserted into table >$history<",
                                        oper       => 'log3parent',
                                        subprocess => $subprocess
                                      }
                                    );
          }
      }
  }

  if ($operation eq 'importCachefile') {
      return ($error, $nins_hist, $rowlback);
  }

  if (lc($DbLogType) =~ m(current)) {
      $error = __DbLog_SBP_onRun_LogCurrent ( { subprocess => $subprocess,
                                                name       => $name,
                                                memc       => $memc,
                                                store      => $store,
                                                useta      => $useta,
                                                usepkc     => $usepkc,
                                                pkc        => $pkc,
                                                ceti       => $ceti,
                                                faref      => $faref
                                              }
                                            );
  }

  my $rt  = tv_interval($st);                                     # SQL-Laufzeit ermitteln
  my $brt = tv_interval($bst);                                    # Background-Laufzeit ermitteln
  my $ot  = $rt.",".$brt;

  $ret = {
      name     => $name,
      msg      => $error,
      ot       => $ot,
      oper     => $operation,
      rowlback => $rowlback
  };

  __DbLog_SBP_sendToParent ($subprocess, $ret);

return;
}

#################################################################
# SubProcess - Log-Routine
# Array-Insert
#################################################################
sub _DbLog_SBP_onRun_LogArray {
  my $paref       = shift;

  my $subprocess  = $paref->{subprocess};
  my $name        = $paref->{name};
  my $memc        = $paref->{memc};
  my $store       = $paref->{store};                                      # Datenspeicher
  my $logstore    = $paref->{logstore};                                   # temporärer Logdatenspeicher
  my $useta       = $paref->{useta};
  my $bst         = $paref->{bst};

  my $DbLogType   = $memc->{DbLogType};                                   # Log-Ziele
  my $nsupk       = $memc->{nsupk};                                       # No Support PK 0|1
  my $tl          = $memc->{tl};                                          # traceLevel
  my $tf          = $memc->{tf};                                          # traceFlag
  my $operation   = $memc->{operation} // 'unknown';                      # aktuell angeforderte Operation (log, etc.)
  my $cdata       = $memc->{cdata};                                       # Log Daten, z.B.: 3399 => 2022-11-29 09:33:32|SolCast|SOLARFORECAST||nextCycletime|09:33:47|
  my $index       = $memc->{cdataindex};                                  # aktueller Cache-Index

  my $dbh         = $store->{dbh};
  my $dbconn      = $store->{dbparams}{dbconn};
  my $model       = $store->{dbparams}{model};
  my $history     = $store->{dbparams}{history};
  my $current     = $store->{dbparams}{current};

  my $error       = q{};
  my $rowlback    = {};                                                   # Hashreferenz Eventliste für Rückgabe wenn Fehler
  my $nins_hist   = 0;

  my $ret;

  if ($tl) {                                                              # Tracelevel setzen
      $dbh->{TraceLevel} = "$tl|$tf";
  }
  else {
      $dbh->{TraceLevel} = '0';
  }

  __DbLog_SBP_logLogmodes ($paref);

  my ($usepkh,$usepkc,$pkh,$pkc);

  if (!$nsupk) {                                                                      # check ob PK verwendet wird, @usepkx?Anzahl der Felder im PK:0 wenn kein PK, $pkx?Namen der Felder:none wenn kein PK
      ($usepkh,$usepkc,$pkh,$pkc) = DbLog_checkUsePK ( { name     => $name,
                                                         dbh      => $dbh,
                                                         dbconn   => $dbconn,
                                                         history  => $history,
                                                         current  => $current
                                                       }
                                                     );
  }
  else {
      _DbLog_SBP_Log3Parent ( { name       => $name,
                                level      => 5,
                                msg        => qq(Primary Key usage suppressed by attribute noSupportPK),
                                oper       => 'log3parent',
                                subprocess => $subprocess
                              }
                            );
  }

  my $ln = scalar keys %{$logstore};

  if ($ln) {                                                                          # temporär gespeicherte Daten hinzufügen
      for my $index (sort {$a<=>$b} keys %{$logstore}) {
          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 4,
                                    msg        => "add stored data: $index -> ".$logstore->{$index},
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );

          $cdata->{$index} = delete $logstore->{$index};
      }

      undef %{$logstore};

      _DbLog_SBP_Log3Parent ( { name       => $name,
                                level      => 4,
                                msg        => "logstore deleted - $ln stored datasets added for processing",
                                oper       => 'log3parent',
                                subprocess => $subprocess
                              }
                            );
  }

  my $faref = __DbLog_SBP_fieldArrays ($name, $cdata, $subprocess);
  my $ceti  = scalar keys %{$cdata};

  my ($st,$sth_ih,$sth_ic,$sth_uc,$sqlins,$ins_hist);
  my ($tuples, $rows);
  my @tuple_status;

  my @timestamp = @{$faref->{timestamp}};
  my @device    = @{$faref->{device}};
  my @type      = @{$faref->{type}};
  my @event     = @{$faref->{event}};
  my @reading   = @{$faref->{reading}};
  my @value     = @{$faref->{value}};
  my @unit      = @{$faref->{unit}};

  $st = [gettimeofday];                                                              # SQL-Startzeit

  if (lc($DbLogType) =~ m(history)) {                                                # insert history mit/ohne primary key
      ($error, $sth_ih) = __DbLog_SBP_sthInsTable ( { table => $history,
                                                      dbh   => $dbh,
                                                      model => $model,
                                                      usepk => $usepkh
                                                    }
                                                  );

      if ($error) {                                                                  # Eventliste zurückgeben wenn z.B. Disk I/O Error bei SQLITE
          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 2,
                                    msg        => "Error: $error",
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );

          __DbLog_SBP_disconnectOnly ($name, $dbh, $subprocess);
          delete $store->{dbh};

          $ret = {
              name     => $name,
              msg      => $error,
              ot       => 0,
              oper     => $operation,
              rowlback => $cdata
          };

          __DbLog_SBP_sendToParent ($subprocess, $ret);
          return;
      }

      if ($tl) {                                                                     # Tracelevel setzen
          $sth_ih->{TraceLevel} = "$tl|$tf";
      }
      else {
          $sth_ih->{TraceLevel} = '0';
      }

      $sth_ih->bind_param_array (1, [@timestamp]);
      $sth_ih->bind_param_array (2, [@device]);
      $sth_ih->bind_param_array (3, [@type]);
      $sth_ih->bind_param_array (4, [@event]);
      $sth_ih->bind_param_array (5, [@reading]);
      $sth_ih->bind_param_array (6, [@value]);
      $sth_ih->bind_param_array (7, [@unit]);

      my @n2hist;
      my $rowhref;

      $error = __DbLog_SBP_beginTransaction ($name, $dbh, $useta, $subprocess);

      if(!$useta) {                                                                  # keine Transaktion: generate errstr, keine Ausnahme
          _DbLog_SBP_dbhPrintError ($dbh);
      }

      eval {  ($tuples, $rows) = $sth_ih->execute_array( { ArrayTupleStatus => \@tuple_status } );
              1;
           }
           or do {
               $error     = $@;
               $nins_hist = $ceti;

               _DbLog_SBP_Log3Parent ( { name       => $name,
                                         level      => 2,
                                         msg        => "Error table $history - $error",
                                         oper       => 'log3parent',
                                         subprocess => $subprocess
                                       }
                                     );

               if($useta) {
                   $rowlback = $cdata;                                                # nicht gespeicherte Datensätze nur zurück geben wenn Transaktion ein

                   _DbLog_SBP_Log3Parent ( { name       => $name,
                                             level      => 4,
                                             msg        => "Transaction is switched on. Transferred data is returned to the cache.",
                                             oper       => 'log3parent',
                                             subprocess => $subprocess
                                           }
                                         );
               }
               else {
                   _DbLog_SBP_Log3Parent ( { name       => $name,
                                             level      => 4,
                                             msg        => "Transaction is switched off. Some or all of the transferred data will be lost. Note the following information.",
                                             oper       => 'log3parent',
                                             subprocess => $subprocess
                                           }
                                         );
               }

               _DbLog_SBP_dbhRaiseError ($dbh);
               __DbLog_SBP_rollbackOnly ($name, $dbh, $history, $subprocess);

               $ret = {
                   name     => $name,
                   msg      => $error,
                   ot       => 0,
                   oper     => $operation,
                   rowlback => $rowlback
               };

               __DbLog_SBP_sendToParent ($subprocess, $ret);

               return;
           };

      _DbLog_SBP_dbhRaiseError ($dbh);
      __DbLog_SBP_commitOnly   ($name, $dbh, $history, $subprocess);

      no warnings 'uninitialized';

      for my $tuple (0..$ceti-1) {
          my $status = $tuple_status[$tuple];
          $status    = 0 if($status eq "0E0");

          next if($status);                                                      # $status ist "1" wenn insert ok

          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 4,
                                    msg        => "Insert into $history rejected".($usepkh ? " (possible PK violation) " : " ")."->\nTS: $timestamp[$tuple], Device: $device[$tuple], Reading: $reading[$tuple]",
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );

          $event[$tuple]   =~ s/\|/_ESC_/gxs;                                    # escape Pipe "|"
          $reading[$tuple] =~ s/\|/_ESC_/gxs;
          $value[$tuple]   =~ s/\|/_ESC_/gxs;
          $unit[$tuple]    =~ s/\|/_ESC_/gxs;

          my $nlh = $timestamp[$tuple]."|".$device[$tuple]."|".$type[$tuple]."|".$event[$tuple]."|".$reading[$tuple]."|".$value[$tuple]."|".$unit[$tuple];

          push @n2hist, $nlh;

          $nins_hist++;
      }

      use warnings;

      if(!$nins_hist) {
          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 4,
                                    msg        => "$ceti of $ceti events inserted into table $history".($usepkh ? " using PK on columns $pkh" : ""),
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );
      }
      else {
          if($usepkh) {
              _DbLog_SBP_Log3Parent ( { name       => $name,
                                        level      => 3,
                                        msg        => "INFO - ".($ceti-$nins_hist)." of $ceti events inserted into table history due to PK on columns $pkh",
                                        oper       => 'log3parent',
                                        subprocess => $subprocess
                                      }
                                    );
          }
          else {
              _DbLog_SBP_Log3Parent ( { name       => $name,
                                        level      => 2,
                                        msg        => "WARNING - only ".($ceti-$nins_hist)." of $ceti events inserted into table $history",
                                        oper       => 'log3parent',
                                        subprocess => $subprocess
                                      }
                                    );

              my $bkey = 1;

              for my $line (@n2hist) {
                  $rowhref->{$bkey} = $line;
                  $bkey++;
              }
          }
      }

      if (defined $rowhref) {                                                           # nicht gespeicherte Datensätze ausgeben
          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 2,
                                    msg        => "The following data was not saved due to causes that may have been previously displayed:",
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );

          DbLog_logHashContent ( {name => $name, href => $rowhref, level => 2, subprocess => $subprocess} );
      }
  }

  if ($operation eq 'importCachefile') {
      return ($error, $nins_hist, $rowlback);
  }

  if (lc($DbLogType) =~ m(current)) {
      $error = __DbLog_SBP_onRun_LogCurrent ( { subprocess => $subprocess,
                                                name       => $name,
                                                memc       => $memc,
                                                store      => $store,
                                                useta      => $useta,
                                                usepkc     => $usepkc,
                                                pkc        => $pkc,
                                                ceti       => $ceti,
                                                faref      => $faref
                                              }
                                            );
  }

  my $rt  = tv_interval($st);                                     # SQL-Laufzeit ermitteln
  my $brt = tv_interval($bst);                                    # Background-Laufzeit ermitteln
  my $ot  = $rt.",".$brt;

  $ret = {
      name     => $name,
      msg      => $error,
      ot       => $ot,
      oper     => $operation,
      rowlback => $rowlback
  };

  __DbLog_SBP_sendToParent ($subprocess, $ret);

return;
}

#################################################################
# SubProcess - Log-Routine Insert/Update current Tabelle
# Array-Insert wird auch bei Bulk verwendet weil im Bulk-Mode
# die nicht upgedateten Sätze nicht identifiziert werden können
#################################################################
sub __DbLog_SBP_onRun_LogCurrent {
  my $paref       = shift;

  my $subprocess  = $paref->{subprocess};
  my $name        = $paref->{name};
  my $memc        = $paref->{memc};
  my $store       = $paref->{store};                                      # Datenspeicher
  my $useta       = $paref->{useta};
  my $usepkc      = $paref->{usepkc};
  my $pkc         = $paref->{pkc};
  my $ceti        = $paref->{ceti};
  my $faref       = $paref->{faref};

  my $tl          = $memc->{tl};                                          # traceLevel
  my $tf          = $memc->{tf};                                          # traceFlag
  my $operation   = $memc->{operation} // 'unknown';                      # aktuell angeforderte Operation (log, etc.)
  my $cdata       = $memc->{cdata};                                       # Log Daten, z.B.: 3399 => 2022-11-29 09:33:32|SolCast|SOLARFORECAST||nextCycletime|09:33:47|

  my $dbh         = $store->{dbh};
  my $model       = $store->{dbparams}{model};
  my $current     = $store->{dbparams}{current};

  my $error       = q{};
  my $doins       = 0;                                                    # Hilfsvariable, wenn "1" sollen inserts in Tabelle current erfolgen (updates schlugen fehl)

  my $ret;

  my @timestamp = @{$faref->{timestamp}};
  my @device    = @{$faref->{device}};
  my @type      = @{$faref->{type}};
  my @event     = @{$faref->{event}};
  my @reading   = @{$faref->{reading}};
  my @value     = @{$faref->{value}};
  my @unit      = @{$faref->{unit}};

  my (@timestamp_cur,@device_cur,@type_cur,@event_cur,@reading_cur,@value_cur,@unit_cur);
  my ($tuples,$rows,$sth_ic,$sth_uc);
  my @tuple_status;

  ($error, $sth_ic) = __DbLog_SBP_sthInsTable ( { table => $current,
                                                  dbh   => $dbh,
                                                  model => $model,
                                                  usepk => $usepkc
                                                }
                                              );

  return $error if ($error);

  ($error, $sth_uc) = __DbLog_SBP_sthUpdTable ( { table => $current,          # Statement Handle "Update" current erstellen
                                                  dbh   => $dbh,
                                                  model => $model,
                                                  usepk => $usepkc,
                                                  pk    => $pkc
                                                }
                                              );

  return $error if ($error);

  if ($tl) {                                                                  # Tracelevel setzen
      $sth_uc->{TraceLevel} = "$tl|$tf";
      $sth_ic->{TraceLevel} = "$tl|$tf";
  }
  else {
      $sth_uc->{TraceLevel} = '0';
      $sth_ic->{TraceLevel} = '0';
  }

  $sth_uc->bind_param_array (1, [@timestamp]);
  $sth_uc->bind_param_array (2, [@type]);
  $sth_uc->bind_param_array (3, [@event]);
  $sth_uc->bind_param_array (4, [@value]);
  $sth_uc->bind_param_array (5, [@unit]);
  $sth_uc->bind_param_array (6, [@device]);
  $sth_uc->bind_param_array (7, [@reading]);

  $error = __DbLog_SBP_beginTransaction ($name, $dbh, $useta, $subprocess);

  eval { ($tuples, $rows) = $sth_uc->execute_array( { ArrayTupleStatus => \@tuple_status } );
       };

  my $nupd_cur = 0;

  for my $tuple (0..$ceti-1) {
      my $status = $tuple_status[$tuple];
      $status    = 0 if($status eq "0E0");

      next if($status);                                                     # $status ist "1" wenn update ok

      _DbLog_SBP_Log3Parent ( { name       => $name,
                                level      => 5,
                                msg        => "Failed to update in $current - TS: $timestamp[$tuple], Device: $device[$tuple], Reading: $reading[$tuple], Status = $status",
                                oper       => 'log3parent',
                                subprocess => $subprocess
                              }
                            );

      push @timestamp_cur, $timestamp[$tuple];
      push @device_cur,    $device[$tuple];
      push @type_cur,      $type[$tuple];
      push @event_cur,     $event[$tuple];
      push @reading_cur,   $reading[$tuple];
      push @value_cur,     $value[$tuple];
      push @unit_cur,      $unit[$tuple];

      $nupd_cur++;
  }

  if(!$nupd_cur) {
      _DbLog_SBP_Log3Parent ( { name       => $name,
                                level      => 4,
                                msg        => "$ceti of $ceti events updated in table $current".($usepkc ? " using PK on columns $pkc" : ""),
                                oper       => 'log3parent',
                                subprocess => $subprocess
                              }
                            );
  }
  else {
      _DbLog_SBP_Log3Parent ( { name       => $name,
                                level      => 4,
                                msg        => "$nupd_cur of $ceti events not updated in table $current. Try to insert ".($usepkc ? " using PK on columns $pkc " : " ")."...",
                                oper       => 'log3parent',
                                subprocess => $subprocess
                              }
                            );
      $doins = 1;
  }

  if ($doins) {                                                             # events die nicht in Tabelle current updated wurden, werden in current neu eingefügt
      $sth_ic->bind_param_array (1, [@timestamp_cur]);
      $sth_ic->bind_param_array (2, [@device_cur]);
      $sth_ic->bind_param_array (3, [@type_cur]);
      $sth_ic->bind_param_array (4, [@event_cur]);
      $sth_ic->bind_param_array (5, [@reading_cur]);
      $sth_ic->bind_param_array (6, [@value_cur]);
      $sth_ic->bind_param_array (7, [@unit_cur]);

      undef @tuple_status;

      eval { ($tuples, $rows) = $sth_ic->execute_array( { ArrayTupleStatus => \@tuple_status } );
           };

      my $nins_cur = 0;

      for my $tuple (0..$#device_cur) {
          my $status = $tuple_status[$tuple];
          $status    = 0 if($status eq "0E0");

          next if($status);                                                # $status ist "1" wenn insert ok

          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 3,
                                    msg        => "Insert into $current rejected - TS: $timestamp[$tuple], Device: $device_cur[$tuple], Reading: $reading_cur[$tuple], Status = $status",
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );

          $nins_cur++;
      }

      if(!$nins_cur) {
          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 4,
                                    msg        => ($#device_cur+1)." of ".($#device_cur+1)." events inserted into table $current ".($usepkc ? " using PK on columns $pkc" : ""),
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );
      }
      else {
          Log3 ($name, 4, "$name - ".($#device_cur+1-$nins_cur)." of ".($#device_cur+1)." events inserted into table $current".($usepkc ? " using PK on columns $pkc" : ""));
          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 4,
                                    msg        => ($#device_cur+1-$nins_cur)." of ".($#device_cur+1)." events inserted into table $current".($usepkc ? " using PK on columns $pkc" : ""),
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );
      }
  }

  $error = __DbLog_SBP_commitOnly ($name, $dbh, $current, $subprocess);

return;
}

#################################################################
#    Aufteilung der Logdaten auf Arrays für jedes
#    Datenbankfeld (für Array-Insert)
#################################################################
sub __DbLog_SBP_fieldArrays {
  my $name       = shift;
  my $cdata      = shift;                                                  # Referenz zu Log Daten Hash
  my $subprocess = shift;

  my (@timestamp,@device,@type,@event,@reading,@value,@unit);

  no warnings 'uninitialized';

  for my $key (sort {$a<=>$b} keys %{$cdata}) {
      my $row = $cdata->{$key};
      my @a   = split "\\|", $row;
      s/_ESC_/\|/gxs for @a;                                               # escaped Pipe back to "|"

      push @timestamp, $a[0];
      push @device,    $a[1];
      push @type,      $a[2];
      push @event,     $a[3];
      push @reading,   $a[4];
      push @value,     $a[5];
      push @unit,      $a[6];

      _DbLog_SBP_Log3Parent ( { name       => $name,
                                level      => 5,
                                msg        => "processing $key -> TS: $a[0], Dev: $a[1], Type: $a[2], Event: $a[3], Reading: $a[4], Val: $a[5], Unit: $a[6]",
                                oper       => 'log3parent',
                                subprocess => $subprocess
                              }
                            );
  }

  use warnings;

  my $faref = {
      timestamp => \@timestamp,
      device    => \@device,
      type      => \@type,
      event     => \@event,
      reading   => \@reading,
      value     => \@value,
      unit      => \@unit
  };

return $faref;
}

#################################################################
#          Ausgabe Logging Modes
#################################################################
sub __DbLog_SBP_logLogmodes {
  my $paref       = shift;

  my $subprocess  = $paref->{subprocess};
  my $store       = $paref->{store};                                      # Datenspeicher
  my $memc        = $paref->{memc};

  my $name        = $paref->{name};
  my $useta       = $paref->{useta};
  my $dbh         = $store->{dbh};
  my $im          = $memc->{im};                                          # Insert-Mode 0|1
  my $DbLogType   = $memc->{DbLogType};                                   # Log-Ziele
  my $operation   = $memc->{operation} // 'unknown';                      # aktuell angeforderte Operation (log, etc.)

  my $ac = $dbh->{AutoCommit} ? "ON" : "OFF";
  my $tm = $useta             ? "ON" : "OFF";

  _DbLog_SBP_Log3Parent ( { name       => $name,
                            level      => 4,
                            msg        => "Operation: $operation",
                            oper       => 'log3parent',
                            subprocess => $subprocess
                          }
                        );

  _DbLog_SBP_Log3Parent ( { name       => $name,
                            level      => 5,
                            msg        => "DbLogType: $DbLogType",
                            oper       => 'log3parent',
                            subprocess => $subprocess
                          }
                        );

  _DbLog_SBP_Log3Parent ( { name       => $name,
                            level      => 4,
                            msg        => "AutoCommit: $ac, Transaction: $tm",
                            oper       => 'log3parent',
                            subprocess => $subprocess
                          }
                        );

  _DbLog_SBP_Log3Parent ( { name       => $name,
                            level      => 4,
                            msg        => "Insert mode: ".($im ? "Sequential" : "Array"),
                            oper       => 'log3parent',
                            subprocess => $subprocess
                          }
                        );

return;
}

#################################################################
# SubProcess - Count-Routine
#################################################################
sub _DbLog_SBP_onRun_Count {
  my $paref       = shift;

  my $subprocess  = $paref->{subprocess};
  my $name        = $paref->{name};
  my $memc        = $paref->{memc};
  my $store       = $paref->{store};                                          # Datenspeicher
  my $bst         = $paref->{bst};

  my $dbh         = $store->{dbh};
  my $history     = $store->{dbparams}{history};
  my $current     = $store->{dbparams}{current};

  my $operation   = $memc->{operation} // 'unknown';                          # aktuell angeforderte Operation (log, etc.)

  my $error       = q{};

  my $st          = [gettimeofday];                                           # SQL-Startzeit

  my $ch          = $dbh->selectrow_array("SELECT count(*) FROM $history");
  my $cc          = $dbh->selectrow_array("SELECT count(*) FROM $current");

  my $rt  = tv_interval($st);                                                 # SQL-Laufzeit ermitteln
  my $brt = tv_interval($bst);                                                # Background-Laufzeit ermitteln
  my $ot  = $rt.",".$brt;

  my $ret = {
      name     => $name,
      msg      => $error,
      ot       => $ot,
      oper     => $operation,
      ch       => $ch,
      cc       => $cc
  };

  __DbLog_SBP_sendToParent ($subprocess, $ret);

return;
}

#################################################################
# SubProcess - deleteOldDays-Routine
#################################################################
sub _DbLog_SBP_onRun_deleteOldDays {
  my $paref       = shift;

  my $subprocess  = $paref->{subprocess};
  my $name        = $paref->{name};
  my $memc        = $paref->{memc};
  my $store       = $paref->{store};                                          # Datenspeicher
  my $bst         = $paref->{bst};

  my $dbh         = $store->{dbh};
  my $history     = $store->{dbparams}{history};
  my $model       = $store->{dbparams}{model};
  my $db          = $store->{dbparams}{dbname};

  my $operation   = $memc->{operation} // 'unknown';                          # aktuell angeforderte Operation (log, etc.)
  my $args        = $memc->{arguments};

  my $error       = q{};
  my $numdel      = 0;
  my $ret;

  my $cmd         = "delete from $history where TIMESTAMP < ";

  if ($model eq 'SQLITE') {
      $cmd .= "datetime('now', '-$args days')";
  }
  elsif ($model eq 'MYSQL') {
      $cmd .= "DATE_SUB(CURDATE(),INTERVAL $args DAY)";
  }
  elsif ($model eq 'POSTGRESQL') {
      $cmd .= "NOW() - INTERVAL '$args' DAY";
  }
  else  {
      $cmd   = undef;
      $error = 'Unknown database type. Maybe you can try userCommand anyway';
  }

  my $st = [gettimeofday];                                           # SQL-Startzeit

  if(defined ($cmd)) {
      (my $err, $numdel) = _DbLog_SBP_dbhDo ($name, $dbh, $cmd, $subprocess);

      if ($err) {
          $dbh->disconnect();
          delete $store->{dbh};

          $ret = {
              name     => $name,
              msg      => $err,
              ot       => 0,
              oper     => $operation
          };

          __DbLog_SBP_sendToParent ($subprocess, $ret);
          return;
      }

      $numdel = 0 if($numdel == 0E0);
      $error  = __DbLog_SBP_commitOnly ($name, $dbh, $history, $subprocess);

      _DbLog_SBP_Log3Parent ( { name       => $name,
                                level      => 3,
                                msg        => "deleteOldDays finished. $numdel entries of database $db deleted.",
                                oper       => 'log3parent',
                                subprocess => $subprocess
                              }
                            );
  }

  my $rt  = tv_interval($st);                                                 # SQL-Laufzeit ermitteln
  my $brt = tv_interval($bst);                                                # Background-Laufzeit ermitteln
  my $ot  = $rt.",".$brt;

  $ret = {
      name     => $name,
      msg      => $error,
      ot       => $ot,
      oper     => $operation,
      numdel   => $numdel
  };

  __DbLog_SBP_sendToParent ($subprocess, $ret);

return;
}

#################################################################
# SubProcess - userCommand-Routine
#################################################################
sub _DbLog_SBP_onRun_userCommand {
  my $paref       = shift;

  my $subprocess  = $paref->{subprocess};
  my $name        = $paref->{name};
  my $memc        = $paref->{memc};
  my $store       = $paref->{store};                                          # Datenspeicher
  my $bst         = $paref->{bst};

  my $dbh         = $store->{dbh};

  my $operation   = $memc->{operation} // 'unknown';                          # aktuell angeforderte Operation (log, etc.)
  my $sql         = $memc->{arguments};

  my $error       = q{};
  my $res;
  my $ret;

  _DbLog_SBP_Log3Parent ( { name       => $name,
                            level      => 4,
                            msg        => qq{$name - userCommand requested: "$sql"},
                            oper       => 'log3parent',
                            subprocess => $subprocess
                          }
                        );

  my $st = [gettimeofday];                                                    # SQL-Startzeit

  eval { $res = $dbh->selectrow_array($sql);
         1;
       }
       or do { $error = $@;
              _DbLog_SBP_Log3Parent ( { name       => $name,
                                        level      => 2,
                                        msg        => "Error - $error",
                                        oper       => 'log3parent',
                                        subprocess => $subprocess
                                      }
                                    );

               $dbh->disconnect();
               delete $store->{dbh};

               $ret = {
                   name     => $name,
                   msg      => $error,
                   ot       => 0,
                   oper     => $operation
               };

               __DbLog_SBP_sendToParent ($subprocess, $ret);
               return;
             };

  $res = defined $res ? $res : 'no result';

  _DbLog_SBP_Log3Parent ( { name       => $name,
                            level      => 4,
                            msg        => qq{$name - userCommand result: "$res"},
                            oper       => 'log3parent',
                            subprocess => $subprocess
                          }
                        );

  my $rt  = tv_interval($st);                                                 # SQL-Laufzeit ermitteln
  my $brt = tv_interval($bst);                                                # Background-Laufzeit ermitteln
  my $ot  = $rt.",".$brt;

  $ret = {
      name     => $name,
      msg      => $error,
      ot       => $ot,
      oper     => $operation,
      res      => $res
  };

  __DbLog_SBP_sendToParent ($subprocess, $ret);

return;
}

#################################################################
# SubProcess - importCachefile-Routine
# must:
# $memc->{arguments} -> $infile
# $memc->{operation} -> 'importCachefile'
# $memc->{DbLogType} -> 'history'
# $memc->{im}        -> 0
#
#################################################################
sub _DbLog_SBP_onRun_importCachefile {
  my $paref       = shift;

  my $subprocess  = $paref->{subprocess};
  my $name        = $paref->{name};
  my $memc        = $paref->{memc};
  my $store       = $paref->{store};                                          # Datenspeicher
  my $logstore    = $paref->{logstore};                                       # temporärer Logdatenspeicher
  my $bst         = $paref->{bst};

  my $operation   = $memc->{operation} // 'unknown';                          # aktuell angeforderte Operation (log, etc.)
  my $infile      = $memc->{arguments};

  my $error       = q{};
  my $rowlback    = q{};
  my $crows       = 0;
  my $nins_hist   = 0;
  my $ret;

  if (open(FH, $infile)) {
      binmode (FH);
  }
  else {
      $ret = {
          name     => $name,
          msg      => "could not open $infile: ".$!,
          ot       => 0,
          oper     => $operation
      };

      __DbLog_SBP_sendToParent ($subprocess, $ret);
      return;
  }

  my $st = [gettimeofday];                                                    # SQL-Startzeit

  while (<FH>) {
      my $row   = $_;
      $row      = DbLog_charfilter($row)    if(AttrVal($name, 'useCharfilter', 0));

      $logstore->{$crows} = $row;

      $crows++;
  }

  close(FH);

  my $msg = "$crows rows read from $infile into temporary Memory store";

  _DbLog_SBP_Log3Parent ( { name       => $name,
                            level      => 3,
                            msg        => $msg,
                            oper       => 'log3parent',
                            subprocess => $subprocess
                          }
                        );

  $memc->{DbLogType} = 'history';                                                          # nur history-Insert !
  $memc->{im}        = 0;                                                                  # Array-Insert !

  ($error, $nins_hist, $rowlback) = _DbLog_SBP_onRun_LogArray ( { subprocess => $subprocess,
                                                                  name       => $name,
                                                                  memc       => $memc,
                                                                  store      => $store,
                                                                  logstore   => $logstore,
                                                                  useta      => 0,              # keine Transaktion !
                                                                  bst        => $bst
                                                                }
                                                              );

  if (!$error && $nins_hist && keys %{$rowlback}) {
      _DbLog_SBP_Log3Parent ( { name       => $name,
                                level      => 2,
                                msg        => "WARNING - $nins_hist datasets from $infile were not imported:",
                                oper       => 'log3parent',
                                subprocess => $subprocess
                              }
                            );

      for my $index (sort {$a<=>$b} keys %{$rowlback}) {
          chomp $rowlback->{$index};

          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 2,
                                    msg        => "$index -> ".$rowlback->{$index},
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );
      }
  }

  my $improws = 'unknown';

  if (!$error) {
      $improws    = $crows - $nins_hist;

      my @parts   = split "/", $infile;
      $infile     = pop @parts;
      my $dir     = (join "/", @parts).'/';

      unless (rename ($dir.$infile, $dir."impdone_".$infile)) {
          $error = "cachefile $dir$infile couldn't be renamed after import: ".$!;

          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 2,
                                    msg        => "ERROR - $error",
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );
      }
      else {
          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 3,
                                    msg        => "cachefile $dir$infile renamed to: ".$dir."impdone_".$infile,
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );
      }
  }

  my $rt  = tv_interval($st);                                                 # SQL-Laufzeit ermitteln
  my $brt = tv_interval($bst);                                                # Background-Laufzeit ermitteln
  my $ot  = $rt.",".$brt;

  $ret = {
      name     => $name,
      msg      => $error,
      ot       => $ot,
      oper     => $operation,
      res      => $improws
  };

  __DbLog_SBP_sendToParent ($subprocess, $ret);

return;
}

#################################################################
# SubProcess - reduceLog-Routine
#################################################################
sub _DbLog_SBP_onRun_reduceLog {
  my $paref       = shift;

  my $subprocess  = $paref->{subprocess};
  my $name        = $paref->{name};
  my $memc        = $paref->{memc};
  my $store       = $paref->{store};                                          # Datenspeicher
  my $bst         = $paref->{bst};
  my $useta       = 1;                                                        # immer Transaktion ein !

  my $dbh         = $store->{dbh};
  my $model       = $store->{dbparams}{model};
  my $history     = $store->{dbparams}{history};

  my $operation   = $memc->{operation} // 'unknown';                          # aktuell angeforderte Operation (log, etc.)
  my $arg         = $memc->{arguments};

  my $error       = q{};
  my $res;
  my $ret;

  my @a = split " ", $arg;

  my ($row,$filter,$exclude,$c,$day,$hour,$lastHour,$updDate,$updHour,$average,$processingDay);
  my ($lastUpdH,%hourlyKnown,%averageHash,@excludeRegex,@dayRows,@averageUpd,@averageUpdD);
  my ($startTime,$currentHour,$currentDay,$deletedCount,$updateCount,$sum,$rowCount,$excludeCount) = (time(),99,0,0,0,0,0,0);

  if ($a[-1] =~ /^EXCLUDE=(.+:.+)+/i) {
      ($filter)     = $a[-1] =~ /^EXCLUDE=(.+)/i;
      @excludeRegex = split ',', $filter;
  }
  elsif ($a[-1] =~ /^INCLUDE=.+:.+$/i) {
      $filter = 1;
  }

  if (defined($a[1])) {
      $average = $a[1] =~ /average=day/i ? "AVERAGE=DAY"  :
                 $a[1] =~ /average/i     ? "AVERAGE=HOUR" :
                 0;
  }

  my $log = "reduceLog requested with DAYS=$a[0]"
           .(($average || $filter) ? ', ' : '').($average ? "$average" : '')
           .(($average && $filter) ? ", " : '').($filter  ? uc((split '=', $a[-1])[0]).'='.(split '=', $a[-1])[1] : '');

  _DbLog_SBP_Log3Parent ( { name       => $name,
                            level      => 3,
                            msg        => $log,
                            oper       => 'log3parent',
                            subprocess => $subprocess
                          }
                        );

  my $ac = $dbh->{AutoCommit} ? "ON" : "OFF";
  my $tm = $useta             ? "ON" : "OFF";

  _DbLog_SBP_Log3Parent ( { name       => $name,
                            level      => 4,
                            msg        => qq(AutoCommit mode: $ac, Transaction mode: $tm),
                            oper       => 'log3parent',
                            subprocess => $subprocess
                          }
                        );

  my ($od,$nd) = split ":", $a[0];                                             # $od - Tage älter als , $nd - Tage neuer als
  my ($ots,$nts);

  if ($model eq 'SQLITE') {
      $ots = "datetime('now', '-$od days')";
      $nts = "datetime('now', '-$nd days')" if($nd);
  }
  elsif ($model eq 'MYSQL') {
      $ots = "DATE_SUB(CURDATE(),INTERVAL $od DAY)";
      $nts = "DATE_SUB(CURDATE(),INTERVAL $nd DAY)" if($nd);
  }
  elsif ($model eq 'POSTGRESQL') {
      $ots = "NOW() - INTERVAL '$od' DAY";
      $nts = "NOW() - INTERVAL '$nd' DAY" if($nd);
  }
  else {
      $ret = 'Unknown database type.';
  }

  if ($ret || !$od) {
      $error  = $ret    if($ret);
      $error .= " and " if($error);
      $error .= "the <no> older days are not set for reduceLog command" if(!$od);

      _DbLog_SBP_Log3Parent ( { name       => $name,
                                level      => 2,
                                msg        => qq(ERROR - $error),
                                oper       => 'log3parent',
                                subprocess => $subprocess
                              }
                            );

      $ret = {
          name  => $name,
          msg   => $error,
          ot    => 0,
          oper  => $operation
      };

      __DbLog_SBP_sendToParent ($subprocess, $ret);
      return;
  }

  my ($sth_del, $sth_upd, $sth_delD, $sth_updD, $sth_get);
  eval { $sth_del  = $dbh->prepare_cached("DELETE FROM $history WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?) AND (VALUE=?)");
         $sth_upd  = $dbh->prepare_cached("UPDATE $history SET TIMESTAMP=?, EVENT=?, VALUE=? WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?) AND (VALUE=?)");
         $sth_delD = $dbh->prepare_cached("DELETE FROM $history WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?)");
         $sth_updD = $dbh->prepare_cached("UPDATE $history SET TIMESTAMP=?, EVENT=?, VALUE=? WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?)");
         $sth_get  = $dbh->prepare("SELECT TIMESTAMP,DEVICE,'',READING,VALUE FROM $history WHERE "
                     .($a[-1] =~ /^INCLUDE=(.+):(.+)$/i ? "DEVICE like '$1' AND READING like '$2' AND " : '')
                     ."TIMESTAMP < $ots".($nts?" AND TIMESTAMP >= $nts ":" ")."ORDER BY TIMESTAMP ASC");                        # '' was EVENT, no longer in use
         1;
       }
       or do { $error = $@;
              _DbLog_SBP_Log3Parent ( { name       => $name,
                                        level      => 2,
                                        msg        => qq(ERROR - $error),
                                        oper       => 'log3parent',
                                        subprocess => $subprocess
                                      }
                                    );

               $dbh->disconnect();
               delete $store->{dbh};

               $ret = {
                   name     => $name,
                   msg      => $error,
                   ot       => 0,
                   oper     => $operation
               };

               __DbLog_SBP_sendToParent ($subprocess, $ret);
               return;
             };

  eval { $sth_get->execute();
         1;
       }
       or do { $error = $@;
              _DbLog_SBP_Log3Parent ( { name       => $name,
                                        level      => 2,
                                        msg        => qq(ERROR - $error),
                                        oper       => 'log3parent',
                                        subprocess => $subprocess
                                      }
                                    );

               $dbh->disconnect();
               delete $store->{dbh};

               $ret = {
                   name     => $name,
                   msg      => $error,
                   ot       => 0,
                   oper     => $operation
               };

               __DbLog_SBP_sendToParent ($subprocess, $ret);
               return;
             };

  my $st = [gettimeofday];                                                                           # SQL-Startzeit

  do {
      $row         = $sth_get->fetchrow_arrayref || ['0000-00-00 00:00:00','D','','R','V'];          # || execute last-day dummy
      $ret         = 1;
      ($day,$hour) = $row->[0] =~ /-(\d{2})\s(\d{2}):/;

      $rowCount++ if($day != 00);

      if ($day != $currentDay) {
          if ($currentDay) {                                                                         # false on first executed day
              if (scalar @dayRows) {
                  ($lastHour) = $dayRows[-1]->[0] =~ /(.*\d+\s\d{2}):/;
                  $c          = 0;

                  for my $delRow (@dayRows) {
                      $c++ if($day != 00 || $delRow->[0] !~ /$lastHour/);
                  }

                  if($c) {
                      $deletedCount += $c;

                      _DbLog_SBP_Log3Parent ( { name       => $name,
                                                level      => 3,
                                                msg        => qq(reduceLog deleting $c records of day: $processingDay),
                                                oper       => 'log3parent',
                                                subprocess => $subprocess
                                              }
                                            );

                      $dbh->{RaiseError} = 1;
                      $dbh->{PrintError} = 0;

                      $error = __DbLog_SBP_beginTransaction ($name, $dbh, $useta, $subprocess);

                      if ($error) {
                          _DbLog_SBP_Log3Parent ( { name       => $name,
                                                    level      => 2,
                                                    msg        => qq(reduceLog - $error),
                                                    oper       => 'log3parent',
                                                    subprocess => $subprocess
                                                  }
                                                );
                      }

                      $error = q{};

                      eval {
                          my $i  = 0;
                          my $k  = 1;
                          my $th = ($#dayRows <= 2000)  ? 100  :
                                   ($#dayRows <= 30000) ? 1000 :
                                   10000;

                          for my $delRow (@dayRows) {
                              if($day != 00 || $delRow->[0] !~ /$lastHour/) {
                                  _DbLog_SBP_Log3Parent ( { name       => $name,
                                                            level      => 4,
                                                            msg        => "DELETE FROM $history WHERE (DEVICE=$delRow->[1]) AND (READING=$delRow->[3]) AND (TIMESTAMP=$delRow->[0]) AND (VALUE=$delRow->[4])",
                                                            oper       => 'log3parent',
                                                            subprocess => $subprocess
                                                          }
                                                        );

                                  $sth_del->execute(($delRow->[1], $delRow->[3], $delRow->[0], $delRow->[4]));
                                  $i++;

                                  if($i == $th) {
                                      my $prog = $k * $i;

                                      _DbLog_SBP_Log3Parent ( { name       => $name,
                                                                level      => 3,
                                                                msg        => "reduceLog deletion progress of day: $processingDay is: $prog",
                                                                oper       => 'log3parent',
                                                                subprocess => $subprocess
                                                              }
                                                            );

                                      $i = 0;
                                      $k++;
                                  }
                              }
                          }
                      };
                      if ($@) {
                          $error = $@;
                          _DbLog_SBP_Log3Parent ( { name       => $name,
                                                    level      => 2,
                                                    msg        => "reduceLog ! FAILED ! for day $processingDay: $error",
                                                    oper       => 'log3parent',
                                                    subprocess => $subprocess
                                                  }
                                                );

                          $error = __DbLog_SBP_rollbackOnly ($name, $dbh, $history, $subprocess);

                          if ($error) {
                              _DbLog_SBP_Log3Parent ( { name       => $name,
                                                        level      => 2,
                                                        msg        => "reduceLog - $error",
                                                        oper       => 'log3parent',
                                                        subprocess => $subprocess
                                                      }
                                                    );
                          }

                          $error = q{};
                          $ret   = 0;
                      }
                      else {
                          $error = __DbLog_SBP_commitOnly ($name, $dbh, $history, $subprocess);

                          if ($error) {
                              _DbLog_SBP_Log3Parent ( { name       => $name,
                                                        level      => 2,
                                                        msg        => "reduceLog - $error",
                                                        oper       => 'log3parent',
                                                        subprocess => $subprocess
                                                      }
                                                    );
                          }

                          $error = q{};
                      }

                      $dbh->{RaiseError} = 0;
                      $dbh->{PrintError} = 1;
                  }

                  @dayRows = ();
              }

              if ($ret && defined($a[1]) && $a[1] =~ /average/i) {
                  $dbh->{RaiseError} = 1;
                  $dbh->{PrintError} = 0;

                  $error = __DbLog_SBP_beginTransaction ($name, $dbh, $useta, $subprocess);

                  if ($error) {
                      _DbLog_SBP_Log3Parent ( { name       => $name,
                                                level      => 2,
                                                msg        => "reduceLog - $error",
                                                oper       => 'log3parent',
                                                subprocess => $subprocess
                                              }
                                            );
                  }

                  $error = q{};

                  eval {
                      push(@averageUpd, {%hourlyKnown}) if($day != 00);

                      $c = 0;
                      for my $hourHash (@averageUpd) {                                               # Only count for logging...
                          for my $hourKey (keys %$hourHash) {
                              $c++ if ($hourHash->{$hourKey}->[0] && scalar(@{$hourHash->{$hourKey}->[4]}) > 1);
                          }
                      }

                      $updateCount += $c;

                      _DbLog_SBP_Log3Parent ( { name       => $name,
                                                level      => 3,
                                                msg        => "reduceLog (hourly-average) updating $c records of day: $processingDay",
                                                oper       => 'log3parent',
                                                subprocess => $subprocess
                                              }
                                            ) if($c); # else only push to @averageUpdD

                      my $i  = 0;
                      my $k  = 1;
                      my $th = ($c <= 2000)  ? 100  :
                               ($c <= 30000) ? 1000 :
                               10000;

                      for my $hourHash (@averageUpd) {
                          for my $hourKey (keys %$hourHash) {
                              if ($hourHash->{$hourKey}->[0]) {                                                # true if reading is a number
                                  ($updDate,$updHour) = $hourHash->{$hourKey}->[0] =~ /(.*\d+)\s(\d{2}):/;

                                  if (scalar(@{$hourHash->{$hourKey}->[4]}) > 1) {                             # true if reading has multiple records this hour
                                      for (@{$hourHash->{$hourKey}->[4]}) {
                                          $sum += $_;
                                      }

                                      $average = sprintf('%.3f', $sum/scalar(@{$hourHash->{$hourKey}->[4]}) );
                                      $sum     = 0;

                                      _DbLog_SBP_Log3Parent ( { name       => $name,
                                                                level      => 4,
                                                                msg        => "UPDATE $history SET TIMESTAMP=$updDate $updHour:30:00, EVENT='rl_av_h', VALUE=$average WHERE DEVICE=$hourHash->{$hourKey}->[1] AND READING=$hourHash->{$hourKey}->[3] AND TIMESTAMP=$hourHash->{$hourKey}->[0] AND VALUE=$hourHash->{$hourKey}->[4]->[0]",
                                                                oper       => 'log3parent',
                                                                subprocess => $subprocess
                                                              }
                                                            );

                                      $sth_upd->execute("$updDate $updHour:30:00", 'rl_av_h', $average, $hourHash->{$hourKey}->[1], $hourHash->{$hourKey}->[3], $hourHash->{$hourKey}->[0], $hourHash->{$hourKey}->[4]->[0]);

                                      $i++;
                                      if($i == $th) {
                                          my $prog = $k * $i;

                                          _DbLog_SBP_Log3Parent ( { name       => $name,
                                                                    level      => 3,
                                                                    msg        => "reduceLog (hourly-average) updating progress of day: $processingDay is: $prog",
                                                                    oper       => 'log3parent',
                                                                    subprocess => $subprocess
                                                                  }
                                                                );

                                          $i = 0;
                                          $k++;
                                      }
                                      push(@averageUpdD, ["$updDate $updHour:30:00", 'rl_av_h', $average, $hourHash->{$hourKey}->[1], $hourHash->{$hourKey}->[3], $updDate]) if (defined($a[1]) && $a[1] =~ /average=day/i);
                                  }
                                  else {
                                      push(@averageUpdD, [$hourHash->{$hourKey}->[0], $hourHash->{$hourKey}->[2], $hourHash->{$hourKey}->[4]->[0], $hourHash->{$hourKey}->[1], $hourHash->{$hourKey}->[3], $updDate]) if (defined($a[1]) && $a[1] =~ /average=day/i);
                                  }
                              }
                          }
                      }
                  };

                  if ($@) {
                      $error = $@;
                      _DbLog_SBP_Log3Parent ( { name       => $name,
                                                level      => 2,
                                                msg        => "reduceLog average=hour ! FAILED ! for day $processingDay: $error",
                                                oper       => 'log3parent',
                                                subprocess => $subprocess
                                              }
                                            );

                      $error = __DbLog_SBP_rollbackOnly ($name, $dbh, $history, $subprocess);

                      if ($error) {
                          _DbLog_SBP_Log3Parent ( { name       => $name,
                                                    level      => 2,
                                                    msg        => "reduceLog - $error",
                                                    oper       => 'log3parent',
                                                    subprocess => $subprocess
                                                  }
                                                );
                      }

                      $error = q{};
                      @averageUpdD = ();
                  }
                  else {
                      $error = __DbLog_SBP_commitOnly ($name, $dbh, $history, $subprocess);

                      if ($error) {
                          _DbLog_SBP_Log3Parent ( { name       => $name,
                                                    level      => 2,
                                                    msg        => "reduceLog - $error",
                                                    oper       => 'log3parent',
                                                    subprocess => $subprocess
                                                  }
                                                );
                      }

                      $error = q{};
                  }

                  $dbh->{RaiseError} = 0;
                  $dbh->{PrintError} = 1;

                  @averageUpd = ();
              }

              if (defined($a[1]) && $a[1] =~ /average=day/i && scalar(@averageUpdD) && $day != 00) {
                  $dbh->{RaiseError} = 1;
                  $dbh->{PrintError} = 0;

                  $error = __DbLog_SBP_beginTransaction ($name, $dbh, $useta, $subprocess);

                  if ($error) {
                      _DbLog_SBP_Log3Parent ( { name       => $name,
                                                level      => 2,
                                                msg        => "reduceLog - $error",
                                                oper       => 'log3parent',
                                                subprocess => $subprocess
                                              }
                                            );
                  }

                  $error = q{};

                  eval {
                      for (@averageUpdD) {
                          push(@{$averageHash{$_->[3].$_->[4]}->{tedr}}, [$_->[0], $_->[1], $_->[3], $_->[4]]);
                          $averageHash{$_->[3].$_->[4]}->{sum} += $_->[2];
                          $averageHash{$_->[3].$_->[4]}->{date} = $_->[5];
                      }

                      $c = 0;
                      for (keys %averageHash) {
                          if(scalar @{$averageHash{$_}->{tedr}} == 1) {
                              delete $averageHash{$_};
                          }
                          else {
                              $c += (scalar(@{$averageHash{$_}->{tedr}}) - 1);
                          }
                      }

                      $deletedCount += $c;
                      $updateCount  += keys(%averageHash);

                      my ($id,$iu) = (0,0);
                      my ($kd,$ku) = (1,1);
                      my $thd      = ($c <= 2000)  ? 100  :
                                     ($c <= 30000) ? 1000 :
                                     10000;
                      my $thu      = ((keys %averageHash) <= 2000)  ? 100  :
                                     ((keys %averageHash) <= 30000) ? 1000 :
                                     10000;

                      _DbLog_SBP_Log3Parent ( { name       => $name,
                                                level      => 3,
                                                msg        => "reduceLog (daily-average) updating ".(keys %averageHash).", deleting $c records of day: $processingDay",
                                                oper       => 'log3parent',
                                                subprocess => $subprocess
                                              }
                                            ) if(keys %averageHash);

                      for my $reading (keys %averageHash) {
                          $average  = sprintf('%.3f', $averageHash{$reading}->{sum}/scalar(@{$averageHash{$reading}->{tedr}}));
                          $lastUpdH = pop @{$averageHash{$reading}->{tedr}};

                          for (@{$averageHash{$reading}->{tedr}}) {
                              _DbLog_SBP_Log3Parent ( { name       => $name,
                                                        level      => 5,
                                                        msg        => "DELETE FROM $history WHERE DEVICE='$_->[2]' AND READING='$_->[3]' AND TIMESTAMP='$_->[0]'",
                                                        oper       => 'log3parent',
                                                        subprocess => $subprocess
                                                      }
                                                    );

                              $sth_delD->execute(($_->[2], $_->[3], $_->[0]));

                              $id++;
                              if($id == $thd) {
                                  my $prog = $kd * $id;

                                  _DbLog_SBP_Log3Parent ( { name       => $name,
                                                            level      => 3,
                                                            msg        => "reduceLog (daily-average) deleting progress of day: $processingDay is: $prog",
                                                            oper       => 'log3parent',
                                                            subprocess => $subprocess
                                                          }
                                                        );
                                  $id = 0;
                                  $kd++;
                              }
                          }

                          _DbLog_SBP_Log3Parent ( { name       => $name,
                                                    level      => 4,
                                                    msg        => "UPDATE $history SET TIMESTAMP=$averageHash{$reading}->{date} 12:00:00, EVENT='rl_av_d', VALUE=$average WHERE (DEVICE=$lastUpdH->[2]) AND (READING=$lastUpdH->[3]) AND (TIMESTAMP=$lastUpdH->[0])",
                                                    oper       => 'log3parent',
                                                    subprocess => $subprocess
                                                  }
                                                );

                          $sth_updD->execute(($averageHash{$reading}->{date}." 12:00:00", 'rl_av_d', $average, $lastUpdH->[2], $lastUpdH->[3], $lastUpdH->[0]));

                          $iu++;

                          if($iu == $thu) {
                              my $prog = $ku * $id;

                              _DbLog_SBP_Log3Parent ( { name       => $name,
                                                        level      => 3,
                                                        msg        => "reduceLog (daily-average) updating progress of day: $processingDay is: $prog",
                                                        oper       => 'log3parent',
                                                        subprocess => $subprocess
                                                      }
                                                    );

                              $iu = 0;
                              $ku++;
                          }
                      }
                  };
                  if ($@) {
                      _DbLog_SBP_Log3Parent ( { name       => $name,
                                                level      => 3,
                                                msg        => "reduceLog average=day ! FAILED ! for day $processingDay",
                                                oper       => 'log3parent',
                                                subprocess => $subprocess
                                              }
                                            );

                      $error = __DbLog_SBP_rollbackOnly ($name, $dbh, $history, $subprocess);

                      if ($error) {
                          _DbLog_SBP_Log3Parent ( { name       => $name,
                                                    level      => 2,
                                                    msg        => "reduceLog - $error",
                                                    oper       => 'log3parent',
                                                    subprocess => $subprocess
                                                  }
                                                );
                      }

                      $error = q{};
                  }
                  else {
                      $error = __DbLog_SBP_commitOnly ($name, $dbh, $history, $subprocess);

                      if ($error) {
                          _DbLog_SBP_Log3Parent ( { name       => $name,
                                                    level      => 2,
                                                    msg        => "reduceLog - $error",
                                                    oper       => 'log3parent',
                                                    subprocess => $subprocess
                                                  }
                                                );
                      }

                      $error = q{};
                  }

                  $dbh->{RaiseError} = 0;
                  $dbh->{PrintError} = 1;
              }

              %averageHash = ();
              %hourlyKnown = ();
              @averageUpd  = ();
              @averageUpdD = ();
              $currentHour = 99;
          }

          $currentDay = $day;
      }

      if ($hour != $currentHour) {                                                            # forget records from last hour, but remember these for average
          if (defined($a[1]) && $a[1] =~ /average/i && keys(%hourlyKnown)) {
              push(@averageUpd, {%hourlyKnown});
          }

          %hourlyKnown = ();
          $currentHour = $hour;
      }
      if (defined $hourlyKnown{$row->[1].$row->[3]}) {                                        # remember first readings for device per h, other can be deleted
          push(@dayRows, [@$row]);
          if (defined($a[1]) && $a[1] =~ /average/i && defined($row->[4]) && $row->[4] =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/ && $hourlyKnown{$row->[1].$row->[3]}->[0]) {
              if ($hourlyKnown{$row->[1].$row->[3]}->[0]) {
                  push(@{$hourlyKnown{$row->[1].$row->[3]}->[4]}, $row->[4]);
              }
          }
      }
      else {
          $exclude = 0;
          for (@excludeRegex) {
              $exclude = 1 if("$row->[1]:$row->[3]" =~ /^$_$/);
          }

          if ($exclude) {
              $excludeCount++ if($day != 00);
          }
          else {
              $hourlyKnown{$row->[1].$row->[3]} = (defined($row->[4]) && $row->[4] =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/) ? [$row->[0],$row->[1],$row->[2],$row->[3],[$row->[4]]] : [0];
          }
      }
      $processingDay = (split(' ',$row->[0]))[0];

  } while( $day != 00 );

  $res  = "reduceLog finished. ";
  $res .= "Rows processed: $rowCount, deleted: $deletedCount"
          .((defined($a[1]) && $a[1] =~ /average/i)? ", updated: $updateCount" : '')
          .(($excludeCount)? ", excluded: $excludeCount" : '')
          .", time: ".sprintf('%.2f',time() - $startTime)."sec";

  _DbLog_SBP_Log3Parent ( { name       => $name,
                            level      => 3,
                            msg        => $res,
                            oper       => 'log3parent',
                            subprocess => $subprocess
                          }
                        );

  my $rt  = tv_interval($st);                                                 # SQL-Laufzeit ermitteln
  my $brt = tv_interval($bst);                                                # Background-Laufzeit ermitteln
  my $ot  = $rt.",".$brt;

  $ret = {
      name     => $name,
      msg      => $error,
      ot       => $ot,
      oper     => $operation,
      res      => $res
  };

  __DbLog_SBP_sendToParent ($subprocess, $ret);

return;
}

####################################################################################################
#       nur Datenbank "begin transaction"
####################################################################################################
sub __DbLog_SBP_beginTransaction {
  my $name       = shift;
  my $dbh        = shift;
  my $useta      = shift;
  my $subprocess = shift;
  my $info       = shift // "begin Transaction";

  my $err        = q{};

  eval{ if($useta && $dbh->{AutoCommit}) {
           $dbh->begin_work();

          _DbLog_SBP_Log3Parent ( { name       => $name,
                                    level      => 4,
                                    msg        => $info,
                                    oper       => 'log3parent',
                                    subprocess => $subprocess
                                  }
                                );
        };
        1;
      }
      or do { $err = $@;
              _DbLog_SBP_Log3Parent ( { name       => $name,
                                        level      => 2,
                                        msg        => "ERROR - $err",
                                        oper       => 'log3parent',
                                        subprocess => $subprocess
                                      }
                                    );
            };

return $err;
}

#################################################################
#          nur Datenbank "commit"
#################################################################
sub __DbLog_SBP_commitOnly {
  my $name       = shift;
  my $dbh        = shift;
  my $table      = shift;
  my $subprocess = shift // q{};

  my $err  = q{};

  eval{ if(!$dbh->{AutoCommit}) {
            $dbh->commit();

            if ($subprocess) {
                _DbLog_SBP_Log3Parent ( { name       => $name,
                                          level      => 4,
                                          msg        => qq(commit inserted data table >$table<),
                                          oper       => 'log3parent',
                                          subprocess => $subprocess
                                        }
                                      );
            }
            else {
                Log3 ($name, 4, qq{$name - commit inserted data table >$table<});
            }
        }
        else {
            if ($subprocess) {
                _DbLog_SBP_Log3Parent ( { name       => $name,
                                          level      => 4,
                                          msg        => qq(insert table >$table< committed by autocommit),
                                          oper       => 'log3parent',
                                          subprocess => $subprocess
                                        }
                                      );
            }
            else {
                Log3 ($name, 4, qq{$name - insert table >$table< committed by autocommit});
            }
        }
        1;
      }
      or do { $err = $@;
              if ($subprocess) {
                  _DbLog_SBP_Log3Parent ( { name       => $name,
                                            level      => 2,
                                            msg        => qq(ERROR commit table >$table<: $err),
                                            oper       => 'log3parent',
                                            subprocess => $subprocess
                                          }
                                        );
              }
              else {
                  Log3 ($name, 2, qq{$name - ERROR commit table >$table<: $err});
              }
            };

return $err;
}

#################################################################
#          nur Datenbank "rollback"
#################################################################
sub __DbLog_SBP_rollbackOnly {
  my $name       = shift;
  my $dbh        = shift;
  my $table      = shift;
  my $subprocess = shift // q{};

  my $err  = q{};

  eval{ if(!$dbh->{AutoCommit}) {
            $dbh->rollback();

            if ($subprocess) {
                _DbLog_SBP_Log3Parent ( { name       => $name,
                                          level      => 4,
                                          msg        => qq(Transaction rollback table >$table<),
                                          oper       => 'log3parent',
                                          subprocess => $subprocess
                                        }
                                      );
            }
            else {
                Log3 ($name, 4, "$name - Transaction rollback table >$table<");
            }
        }
        else {
            if ($subprocess) {
                _DbLog_SBP_Log3Parent ( { name       => $name,
                                          level      => 4,
                                          msg        => qq(data auto rollback table >$table<),
                                          oper       => 'log3parent',
                                          subprocess => $subprocess
                                        }
                                      );
            }
            else {
                Log3 ($name, 4, "$name - data auto rollback table >$table<");
            }
        }
        1;
      }
      or do { $err = $@;
              if ($subprocess) {
                  _DbLog_SBP_Log3Parent ( { name       => $name,
                                            level      => 2,
                                            msg        => qq(ERROR - $err),
                                            oper       => 'log3parent',
                                            subprocess => $subprocess
                                          }
                                        );
              }
              else {
                  Log3 ($name, 2, "$name - ERROR - $err");
              }
            };

return $err;
}

####################################################################################################
#       nur Datenbank disconnect
####################################################################################################
sub __DbLog_SBP_disconnectOnly {
  my $name       = shift;
  my $dbh        = shift;
  my $subprocess = shift // q{};

  my $err = q{};

  eval{ $dbh->disconnect() if(defined $dbh);
        1;
      }
      or do { $err = $@;
              if ($subprocess) {
                  _DbLog_SBP_Log3Parent ( { name       => $name,
                                            level      => 2,
                                            msg        => qq(ERROR - $err),
                                            oper       => 'log3parent',
                                            subprocess => $subprocess
                                          }
                                        );
              }
              else {
                  Log3 ($name, 2, "$name - ERROR - $err");
              }
            };

return $err;
}

#################################################################
#          nur Datenbank "selectrow_array"
#################################################################
sub __DbLog_SBP_selectrowArray {
  my $dbh = shift;
  my $sql = shift;

  my $err = q{};
  my @res = ();

  eval { @res = $dbh->selectrow_array($sql);
         1;
       }
       or do { $err = $@ };

return ($err, @res);
}

#################################################################
#  einfaches Query prepare, Rückgabe Statement Handle
#################################################################
sub __DbLog_SBP_prepareOnly {
  my $name       = shift;
  my $dbh        = shift;
  my $query      = shift;
  my $subprocess = shift // q{};

  my $err = q{};
  my $sth;

  eval{ $sth = $dbh->prepare ($query);
        1;
      }
      or do { $err = $@;
              _DbLog_SBP_Log3Parent ( { name       => $name,
                                        level      => 2,
                                        msg        => qq(ERROR - $err),
                                        oper       => 'log3parent',
                                        subprocess => $subprocess
                                      }
                                    );
            };

return ($err, $sth);
}

#################################################################
#  einfaches Query execute
#################################################################
sub __DbLog_SBP_executeOnly {
  my $name       = shift;
  my $sth        = shift;
  my $subprocess = shift // q{};

  my $err = q{};
  my $result;

  eval{ $result = $sth->execute();
        1;
      }
      or do { $err = $@;
              _DbLog_SBP_Log3Parent ( { name       => $name,
                                        level      => 2,
                                        msg        => qq(ERROR - $err),
                                        oper       => 'log3parent',
                                        subprocess => $subprocess
                                      }
                                    );
            };

return ($err, $sth, $result);
}

#################################################################
#    erstellt Statement Handle für Insert Daten in die
#    angegebene Tabelle
#################################################################
sub __DbLog_SBP_sthInsTable {
  my $paref = shift;

  my $table = $paref->{table};
  my $dbh   = $paref->{dbh};
  my $model = $paref->{model};
  my $usepk = $paref->{usepk};                      # nutze PK ?

  my $err   = q{};
  my $sth;

  eval { if ($usepk && $model eq 'MYSQL') {
             $sth = $dbh->prepare("INSERT IGNORE INTO $table (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)");
         }
         elsif ($usepk && $model eq 'SQLITE') {
             $sth = $dbh->prepare("INSERT OR IGNORE INTO $table (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)");
         }
         elsif ($usepk && $model eq 'POSTGRESQL') {
             $sth = $dbh->prepare("INSERT INTO $table (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING");
         }
         else {
             $sth = $dbh->prepare("INSERT INTO $table (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)");
         }
         1;
       }
       or do { $err = $@;
             };

return ($err, $sth);
}

#################################################################
#    erstellt Statement Handle für Update Daten in die
#    angegebene Tabelle
#################################################################
sub __DbLog_SBP_sthUpdTable {
  my $paref  = shift;

  my $table  = $paref->{table};
  my $dbh    = $paref->{dbh};
  my $model  = $paref->{model};
  my $usepk  = $paref->{usepk};              # nutze PK ?
  my $pk     = $paref->{pk};

  my $err    = q{};
  my $sth;

  eval { if ($usepk && $model eq 'MYSQL') {
             $sth = $dbh->prepare("REPLACE INTO $table (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?)");
         }
         elsif ($usepk && $model eq 'SQLITE') {
             $sth = $dbh->prepare("INSERT OR REPLACE INTO $table (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?)");
         }
         elsif ($usepk && $model eq 'POSTGRESQL') {
             $sth = $dbh->prepare("INSERT INTO $table (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?) ON CONFLICT ($pk)
                                               DO UPDATE SET TIMESTAMP=EXCLUDED.TIMESTAMP, DEVICE=EXCLUDED.DEVICE, TYPE=EXCLUDED.TYPE, EVENT=EXCLUDED.EVENT, READING=EXCLUDED.READING,
                                               VALUE=EXCLUDED.VALUE, UNIT=EXCLUDED.UNIT");
         }
         else {
             $sth = $dbh->prepare("UPDATE $table SET TIMESTAMP=?, TYPE=?, EVENT=?, VALUE=?, UNIT=? WHERE (DEVICE=?) AND (READING=?)");
         }
         1;
       }
       or do { $err = $@;
             };

return ($err, $sth);
}

###################################################################################
#   Daten zur Verbeitung mit Log3() im Parent-Prozess senden
###################################################################################
sub _DbLog_SBP_Log3Parent {
  my $paref = shift;

  my $level   = $paref->{level};
  my $name    = $paref->{name};
  my $verbose = AttrVal ($name, 'verbose', $attr{global}{verbose});

  return if($level > $verbose);

  my $msg        = $paref->{msg};
  my $subprocess = $paref->{subprocess};

  if ($subprocess) {
      __DbLog_SBP_sendToParent ( $subprocess,
                                 { name    => $name,
                                   level   => $level,                             # Loglevel
                                   msg     => $msg,                               # Nutzdaten zur Ausgabe mit Log3() im Parentprozess
                                   oper    => 'log3parent'
                                 }
                               );
  }
  else {
      Log3 ($name, $level, qq{$name - $msg});
  }

return;
}

#################################################################
#   Information an Parent Prozess senden, Verarbeitung in
#   read Schleife DbLog_SBP_Read
#################################################################
sub __DbLog_SBP_sendToParent {
  my $subprocess = shift;
  my $data       = shift;

  my $serial = eval { freeze ($data) };
  $subprocess->writeToParent ($serial);

return;
}

#####################################################
##   Subprocess wird beendet
#####################################################
sub DbLog_SBP_onExit {
    my $subprocess = shift;
    my $name       = $subprocess->{name};

    Log3 ($name, 1, "$name - SubProcess EXITED!");

return;
}

#####################################################
#   Subprocess prüfen und ggf. neu starten
#####################################################
sub DbLog_SBP_CheckAndInit {
  my $hash = shift;
  my $nscd = shift // 0;                                                        # 1 - kein senden Connectiondata direkt nach Start Subprozess

  return "Shutdown sequence running" if(defined $hash->{HELPER}{SHUTDOWNSEQ});  # Shutdown Sequenz läuft

  my $name = $hash->{NAME};

  my $err = q{};

  if (defined $hash->{SBP_PID} && defined $hash->{HELPER}{LONGRUN_PID}) {       # Laufzeit des letzten Kommandos prüfen -> timeout
      my $to = AttrVal ($name, 'timeout', $dblog_todef);
      my $rt = gettimeofday() - $hash->{HELPER}{LONGRUN_PID};                   # aktuelle Laufzeit

      if ($rt >= $to) {                                                         # SubProcess beenden, möglicherweise tot
          Log3 ($name, 2, qq{$name - The Subprocess >$hash->{SBP_PID}< has exceeded the timeout of $to seconds});

          DbLog_SBP_CleanUp ($hash);

          Log3 ($name, 2, qq{$name - The last running operation was canceled});
      }
  }

  if (!defined $hash->{SBP_PID}) {
      $err = _DbLog_SBP_Init ($hash, $nscd);
      return $err if($err);
  }

  my $pid = $hash->{SBP_PID};

  if (kill 0, $pid) {                                                     # SubProcess mit $pid lebt
      $hash->{SBP_STATE} = 'running';
  }
  else {
      $hash->{SBP_STATE} = "dead (".$hash->{SBP_PID}.")";
      delete $hash->{SBP_PID};
      delete $hash->{HELPER}{LONGRUN_PID};                                # Statusbit laufende Verarbeitung löschen
      $err = _DbLog_SBP_Init ($hash, $nscd);
  }

return $err;
}

#####################################################
#   Datenbankverbindung im SubProcess
#   beenden
#####################################################
sub DbLog_SBP_sendDbDisconnect {
  my $hash    = shift;
  my $delpars = shift // 0;      # 1 - die im SubProzess gespeicherten Daten sollen gelöscht werden

  my $name = $hash->{NAME};

  my $subprocess = $hash->{".fhem"}{subprocess};
  my $err        = q{};

  if(!defined $subprocess) {
      $err = qq{SubProcess isn't available. Disconnect command couldn't be sent};
      Log3 ($name, 1, "$name - ERROR - $err");
      return $err;
  }

  my $memc;

  $memc->{dbstorepars} = 0;
  $memc->{dbdelpars}   = $delpars;
  $memc->{dbdisconn}   = 1;                              # Statusbit command disconnect
  $memc->{operation}   = 'dbDisconnect';

  $err = _DbLog_SBP_sendToChild ($name, $subprocess, $memc);
  return $err if($err);

return;
}

#####################################################
#   Datenbank Verbindungsparameter an SubProcess
#   senden und dort speichern
#####################################################
sub DbLog_SBP_sendConnectionData {
  my $hash = shift;
  my $name = $hash->{NAME};

  my $subprocess = $hash->{".fhem"}{subprocess};
  my $err        = q{};

  if(!defined $subprocess) {
      $err = qq{SubProcess isn't running, DB connection data couldn't be sent};
      Log3 ($name, 1, "$name - ERROR - $err");
      return $err;
  }

  my $memc;

  $memc->{dbstorepars} = 1;                                                  # Signalbit "Daten speichern"
  $memc->{dbdisconn}   = 0;
  $memc->{dbconn}      = $hash->{dbconn};
  $memc->{dbuser}      = $hash->{dbuser};
  $memc->{dbpassword}  = $attr{"sec$name"}{secret};
  $memc->{model}       = $hash->{MODEL};
  $memc->{cm}          = AttrVal ($name, 'commitMode', $dblog_cmdef);
  $memc->{verbose}     = AttrVal ($name, 'verbose',    $attr{global}{verbose});
  $memc->{utf8}        = defined ($hash->{UTF8}) ? $hash->{UTF8} : 0;
  $memc->{history}     = $hash->{HELPER}{TH};
  $memc->{current}     = $hash->{HELPER}{TC};
  $memc->{operation}   = 'sendDbConnectData';

  if ($hash->{MODEL} eq 'SQLITE') {
      $memc->{sltjm} = AttrVal ($name, 'SQLiteJournalMode', 'WAL');
      $memc->{sltcs} = AttrVal ($name, 'SQLiteCacheSize',    4000);
  }

  $err = _DbLog_SBP_sendToChild ($name, $subprocess, $memc);
  return $err if($err);

return;
}

#####################################################
#   die zu verarbeitenden Log-Daten an SubProcess
#   senden
#   die Prozessdaten werden in Hashreferenz $memc
#   übergeben
#####################################################
sub DbLog_SBP_sendLogData {
  my $hash = shift;
  my $oper = shift;                                                   # angeforderte Operation
  my $memc = shift;

  my $name       = $hash->{NAME};
  my $subprocess = $hash->{".fhem"}{subprocess};

  if(!defined $subprocess) {
      Log3 ($name, 1, "$name - ERROR - SubProcess isn't running, processing data couldn't be sent");
      return 'no SubProcess is running';
  }

  $memc->{DbLogType} = AttrVal ($name, 'DbLogType',   'History');
  $memc->{nsupk}     = AttrVal ($name, 'noSupportPK',         0);
  $memc->{tl}        = AttrVal ($name, 'traceLevel',          0);
  $memc->{tf}        = AttrVal ($name, 'traceFlag',       'SQL');
  $memc->{im}        = AttrVal ($name, 'insertMode',          0);
  $memc->{verbose}   = AttrVal ($name, 'verbose', $attr{global}{verbose});
  $memc->{operation} = $oper;

  my $err = _DbLog_SBP_sendToChild ($name, $subprocess, $memc);
  return $err if($err);

  $hash->{HELPER}{LONGRUN_PID} = gettimeofday();                      # Statusbit laufende Verarbeitung mit Startzeitstempel;

return;
}

#####################################################
#   ein Kommando zur Ausführung an SubProcess senden
#   z.B.
#   $oper = count
#   $oper = deleteOldDays
#   etc.
#
#   $arg -> Argumente von $oper
#####################################################
sub DbLog_SBP_sendCommand {
  my $hash = shift;
  my $oper = shift;                                                   # angeforderte Operation
  my $arg  = shift // q{};

  my $name       = $hash->{NAME};
  my $subprocess = $hash->{".fhem"}{subprocess};

  if(!defined $subprocess) {
      Log3 ($name, 1, "$name - ERROR - SubProcess isn't running, processing data couldn't be sent");
      return 'no SubProcess is running';
  }

  my $memc;

  $memc->{nsupk}     = AttrVal ($name, 'noSupportPK',    0);
  $memc->{tl}        = AttrVal ($name, 'traceLevel',     0);
  $memc->{tf}        = AttrVal ($name, 'traceFlag',  'SQL');
  $memc->{im}        = AttrVal ($name, 'insertMode',     0);
  $memc->{verbose}   = AttrVal ($name, 'verbose', $attr{global}{verbose});
  $memc->{operation} = $oper;
  $memc->{arguments} = $arg;

  my $err = _DbLog_SBP_sendToChild ($name, $subprocess, $memc);
  return $err if($err);

  $hash->{HELPER}{LONGRUN_PID} = gettimeofday();                       # Statusbit laufende Verarbeitung mit Startzeitstempel;

  DbLog_setReadingstate ($hash, "operation '$oper' is running");

return;
}

#################################################################
#   Information Serialisieren und an Child Prozess senden
#################################################################
sub _DbLog_SBP_sendToChild {
  my $name       = shift;
  my $subprocess = shift;
  my $data       = shift;

  my $serial = eval { freeze ($data);
                    }
                    or do { my $err = $@;
                            _DbLog_SBP_Log3Parent ( { name       => $name,
                                                      level      => 1,
                                                      msg        => qq(Serialization error: $err),
                                                      oper       => 'log3parent',
                                                      subprocess => $subprocess
                                                    }
                                                  );
                            return $err;
                          };

  $subprocess->writeToChild ($serial);

return;
}

#####################################################
##   Subprocess initialisieren
#####################################################
sub _DbLog_SBP_Init {
  my $hash = shift;
  my $nscd = shift // 0;                                                        # 1 - kein senden Connectiondata direkt nach Start Subprozess

  my $name = $hash->{NAME};

  $hash->{".fhem"}{subprocess} = undef;

  my $subprocess = SubProcess->new( { onRun  => \&DbLog_SBP_onRun,
                                      onExit => \&DbLog_SBP_onExit
                                    }
                                  );

  # Hier eigenen Variablen wie folgt festlegen:
  $subprocess->{name} = $name;

  # Sobald der Unterprozess gestartet ist, leben Eltern- und Kindprozess
  # in getrennten Prozessen und können keine Daten mehr gemeinsam nutzen - die Änderung von Variablen im
  # Elternprozess haben keine Auswirkungen auf die Variablen im Kindprozess und umgekehrt.

  my $pid = $subprocess->run();

  if (!defined $pid) {
      my $err = "$name - Cannot create subprocess for non-blocking operation";
      Log3 ($name, 1, $err);

      DbLog_SBP_CleanUp     ($hash);
      DbLog_setReadingstate ($hash, $err);

      return 'no SubProcess PID created';
  }

  Log3 ($name, 2, qq{$name - Subprocess >$pid< initialized ... ready for non-blocking operation});

  $hash->{".fhem"}{subprocess} = $subprocess;
  $hash->{FD}                  = fileno $subprocess->child();

  delete($readyfnlist{"$name.$pid"});

  $selectlist{"$name.$pid"} = $hash;
  $hash->{SBP_PID}          = $pid;
  $hash->{SBP_STATE}        = 'running';

  if (!$nscd) {
      my $rst = DbLog_SBP_sendConnectionData ($hash);                                        # Verbindungsdaten übertragen
      if (!$rst) {
          Log3 ($name, 3, "$name - requested DB connection parameters are transmitted");
      }
  }

return;
}

#####################################################
##   Subprocess beenden
#####################################################
sub DbLog_SBP_CleanUp {
  my $hash = shift;
  my $name = $hash->{NAME};

  my $subprocess = $hash->{".fhem"}{subprocess};
  return if(!defined $subprocess);

  my $pid = $subprocess->pid();
  return if(!defined $pid);

  Log3 ($name, 2, qq{$name - stopping SubProcess PID >$pid< ...});

  #$subprocess->terminate();
  #$subprocess->wait();

  kill 'SIGKILL', $pid;
  waitpid ($pid, 0);

  Log3 ($name, 2, qq{$name - SubProcess PID >$pid< stopped});

  delete ($selectlist{"$name.$pid"});
  delete $hash->{FD};
  delete $hash->{SBP_PID};
  delete $hash->{HELPER}{LONGRUN_PID};

  $hash->{SBP_STATE} = "Stopped";
  
  DoTrigger ($name, 'SUBPROC_STOPPED', 1);

return;
}

################################################################################
# called from the global loop, when the select for hash->{FD} reports data
# geschrieben durch "onRun" Funktion
################################################################################
sub DbLog_SBP_Read {
  my $hash = shift;
  #my $name = $hash->{NAME};

  my $subprocess = $hash->{".fhem"}{subprocess};
  my $retserial  = $subprocess->readFromChild();                                              # hier lesen wir aus der globalen Select-Schleife, was in der onRun-Funktion geschrieben wurde

  if(defined $retserial) {
      my $ret = eval { thaw ($retserial) };

      return if(defined($ret) && ref($ret) ne "HASH");

      my $name     = $ret->{name};
      my $msg      = $ret->{msg};
      my $ot       = $ret->{ot};
      my $reqdbdat = $ret->{reqdbdat};                                                        # 1 = Request Übertragung DB Verbindungsparameter
      my $oper     = $ret->{oper};                                                            # aktuell ausgeführte Operation

      ## Log3Parent - Log3() Ausgabe
      ################################
      if ($oper eq 'log3parent') {
          my $level = $ret->{level};
          Log3 ($name, $level, "$name - ".$msg);
          return;
      }

      delete $hash->{HELPER}{LONGRUN_PID};
      delete $hash->{HELPER}{LASTLIMITRUNTIME} if(!$msg);

      my $ce = AttrVal ($name, 'cacheEvents', 0);

      # Log3 ($name, 1, "$name - Read result of operation: $oper");
      # Log3 ($name, 1, "$name - DbLog_SBP_Read: name: $name, msg: $msg, ot: $ot, rowlback: ".Dumper $rowlback);

      if($reqdbdat) {                                                                         # Übertragung DB Verbindungsparameter ist requested
          my $rst = DbLog_SBP_sendConnectionData ($hash);
          if (!$rst) {
              Log3 ($name, 3, "$name - requested DB connection parameters are transmitted");
          }
      }

      ## Log - Read
      ###############
      if ($oper =~ /log_/xs) {
          my $rowlback = $ret->{rowlback};

          if($rowlback) {                                                                                  
              my $memcount;

              eval {                                                                                         # one Transaction
                  for my $key (sort {$a <=>$b} keys %{$rowlback}) {
                      $memcount = DbLog_addMemCacheRow ($name, $rowlback->{$key});                           # Datensatz zum Memory Cache hinzufügen

                      Log3 ($name, 5, "$name - row back to Cache: $key -> ".$rowlback->{$key});
                  }
                  
                  if ($hash->{HELPER}{SHUTDOWNSEQ} && $memcount) {
                      Log3 ($name, 2, "$name - an error occurred during the last write cycle to the database, the data is exported to a file instead ... ......");
                      
                      my $error = CommandSet (undef, qq{$name exportCache purgecache});

                      if ($error) {                                                                          # Fehler beim Export Cachefile
                          Log3 ($name, 1, "$name - ERROR - while exporting Cache file: $error");
                      }                    
                  }
              };

              readingsSingleUpdate ($hash, 'CacheUsage', $memcount, ($ce == 1 ? 1 : 0));
          }
      }

      ## Count - Read
      #################
      if ($oper =~ /count/xs) {
          my $ch = $ret->{ch} // 'unknown';
          my $cc = $ret->{cc} // 'unknown';

          readingsBeginUpdate ($hash);
          readingsBulkUpdate  ($hash, 'countHistory', $ch);
          readingsBulkUpdate  ($hash, 'countCurrent', $cc);
          readingsEndUpdate   ($hash, 1);
      }

      ## deleteOldDays - Read
      #########################
      if ($oper =~ /deleteOldDays/xs) {
          readingsSingleUpdate($hash, 'lastRowsDeleted', $ret->{numdel}, 1);
      }

      ## userCommand - Read
      #########################
      if ($oper =~ /userCommand/xs) {
          readingsSingleUpdate($hash, 'userCommandResult', $ret->{res}, 1);
      }

      ## importCachefile - Read
      ###########################
      if ($oper =~ /importCachefile/xs) {
          my $improws = $ret->{res};
          $msg        = $msg ? $msg : "$oper finished, $improws datasets were imported";
      }

      ## reduceLog - Read
      #########################
      if ($oper =~ /reduceLog/xs) {
          readingsSingleUpdate($hash, 'reduceLogState', $ret->{res}, 1) if($ret->{res});
      }
      
      ## sendDbConnectData - Read
      #############################
      if ($oper =~ /sendDbConnectData/xs) {
          Log3 ($name, 3, "$name - DB connection parameters are initialized in the SubProcess");
          
          DoTrigger ($name, 'SUBPROC_INITIALIZED', 1);
      }
      
      ## dbDisconnect - Read
      ########################
      if ($oper =~ /dbDisconnect/xs) {
          DoTrigger ($name, 'SUBPROC_DISCONNECTED', 1);
      }

      if(AttrVal($name, 'showproctime', 0) && $ot) {
          my ($rt,$brt) = split ",", $ot;

          readingsBeginUpdate ($hash);
          readingsBulkUpdate  ($hash, 'background_processing_time', sprintf("%.4f",$brt));
          readingsBulkUpdate  ($hash, 'sql_processing_time',        sprintf("%.4f",$rt) );
          readingsEndUpdate   ($hash, 1);
      }

      my $state = IsDisabled($name) ? 'disabled' :
                  $msg              ? $msg       :
                  'connected';

      DbLog_setReadingstate ($hash, $state);

      if ($hash->{HELPER}{SHUTDOWNSEQ}) {
          Log3 ($name, 2, "$name - Last database write cycle done");
          _DbLog_finishDelayedShutdown ($hash);
      }
  }

return;
}

################################################################
#     wenn Cache Overflow vorhanden ist und die Behandlung mit
#     dem Attr "cacheOverflowThreshold" eingeschaltet ist,
#     wirde der Cache in ein File weggeschrieben
#     Gibt "1" zurück wenn File geschrieben wurde
################################################################
sub DbLog_writeFileIfCacheOverflow {
  my $paref    = shift;

  my $hash     = $paref->{hash};
  my $clim     = $paref->{clim};
  my $memcount = $paref->{memcount};

  my $name    = $hash->{NAME};
  my $success = 0;
  my $coft    = AttrVal($name, 'cacheOverflowThreshold', 0);                                 # Steuerung exportCache statt schreiben in DB
  $coft       = ($coft && $coft < $clim) ? $clim : $coft;                                    # cacheOverflowThreshold auf cacheLimit setzen wenn kleiner als cacheLimit

  my $overflowstate = "normal";
  my $overflownum;

  if($coft) {
      $overflownum = $memcount >= $coft ? $memcount-$coft : 0;
  }
  else {
      $overflownum = $memcount >= $clim ? $memcount-$clim : 0;
  }

  $overflowstate = "exceeded" if($overflownum);

  readingsBeginUpdate($hash);
  readingsBulkUpdate          ($hash, "CacheOverflowLastNum",   $overflownum     );
  readingsBulkUpdateIfChanged ($hash, "CacheOverflowLastState", $overflowstate, 1);
  readingsEndUpdate($hash, 1);

  if($coft && $memcount >= $coft) {
      Log3 ($name, 2, "$name - WARNING - Cache is exported to file instead of logging it to database");
      my $error = CommandSet (undef, qq{$name exportCache purgecache});

      if($error) {                                                                          # Fehler beim Export Cachefile
          Log3 ($name, 1, "$name - ERROR - while exporting Cache file: $error");
          DbLog_setReadingstate ($hash, $error);
          return $success;
      }

      DbLog_setReadingstate ($hash, qq{Cache exported to "lastCachefile" due to Cache overflow});
      delete $hash->{HELPER}{LASTLIMITRUNTIME};
      $success = 1;
  }

return $success;
}

################################################################
#             Reading state setzen
################################################################
sub DbLog_setReadingstate {
  my $hash = shift;
  my $val  = shift // $hash->{HELPER}{OLDSTATE};

  my $evt  = $val eq $hash->{HELPER}{OLDSTATE} ? 0 : 1;
  my $out  = $val =~ /<br>/xs ? '<html>'.$val.'</html>' : $val;

  readingsSingleUpdate($hash, 'state', $out, $evt);

  $hash->{HELPER}{OLDSTATE} = $val;

return;
}

################################################################
#
# zerlegt uebergebenes FHEM-Datum in die einzelnen Bestandteile
# und fuegt noch Defaultwerte ein
# uebergebenes SQL-Format: YYYY-MM-DD HH24:MI:SS
#
################################################################
sub DbLog_explode_datetime {
  my ($t, %def) = @_;
  my %retv;

  my (@datetime, @date, @time);
  @datetime = split(" ", $t); #Datum und Zeit auftrennen
  @date     = split("-", $datetime[0]);
  @time     = split(":", $datetime[1]) if ($datetime[1]);

  if ($date[0]) {$retv{year}   = $date[0];} else {$retv{year}   = $def{year};}
  if ($date[1]) {$retv{month}  = $date[1];} else {$retv{month}  = $def{month};}
  if ($date[2]) {$retv{day}    = $date[2];} else {$retv{day}    = $def{day};}
  if ($time[0]) {$retv{hour}   = $time[0];} else {$retv{hour}   = $def{hour};}
  if ($time[1]) {$retv{minute} = $time[1];} else {$retv{minute} = $def{minute};}
  if ($time[2]) {$retv{second} = $time[2];} else {$retv{second} = $def{second};}

  $retv{datetime} = DbLog_implode_datetime($retv{year}, $retv{month}, $retv{day}, $retv{hour}, $retv{minute}, $retv{second});

  # Log 1, Dumper(%retv);
  return %retv
}

sub DbLog_implode_datetime($$$$$$) {
  my ($year, $month, $day, $hour, $minute, $second) = @_;
  my $retv = $year."-".$month."-".$day." ".$hour.":".$minute.":".$second;

return $retv;
}

###################################################################################
#                            Verbindungen zur DB aufbauen
###################################################################################
sub DbLog_readCfg {
  my $hash = shift;
  my $name = $hash->{NAME};

  my $configfilename= $hash->{CONFIGURATION};
  my %dbconfig;

  # use generic fileRead to get configuration data
  my ($err, @config) = FileRead($configfilename);
  return $err if($err);

  eval join("\n", @config);

  return "could not read connection" if (!defined $dbconfig{connection});
  $hash->{dbconn} = $dbconfig{connection};
  return "could not read user" if (!defined $dbconfig{user});
  $hash->{dbuser} = $dbconfig{user};
  return "could not read password" if (!defined $dbconfig{password});
  $attr{"sec$name"}{secret} = $dbconfig{password};

  #check the database model
  if($hash->{dbconn} =~ m/pg:/i) {
      $hash->{MODEL}="POSTGRESQL";
  }
  elsif ($hash->{dbconn} =~ m/mysql:/i) {
      $hash->{MODEL}="MYSQL";
  }
  elsif ($hash->{dbconn} =~ m/oracle:/i) {
      $hash->{MODEL}="ORACLE";
  }
  elsif ($hash->{dbconn} =~ m/sqlite:/i) {
      $hash->{MODEL}="SQLITE";
  }
  else {
      $hash->{MODEL}="unknown";

      Log3 $name, 1, "Unknown database model found in configuration file $configfilename.";
      Log3 $name, 1, "Only MySQL/MariaDB, PostgreSQL, Oracle, SQLite are fully supported.";

      return "unknown database type";
  }

  if($hash->{MODEL} eq "MYSQL") {
      $hash->{UTF8} = defined($dbconfig{utf8}) ? $dbconfig{utf8} : 0;
  }

return;
}

#################################################################
#    DBHU Verwaltung im Hauptprozess (Universal DB Handle)
#
#    Vorhandensein DBHU prüfen, Validität prüfen und verwenden
#    ggf. DBHU neu erstellen
#
#    $hash->{DBHU} - universeller DB Handle
#################################################################
sub _DbLog_manageDBHU {
  my $hash = shift;

  my $name = $hash->{NAME};

  my $dbh;

  if (defined $hash->{DBHU}) {
      $dbh     = $hash->{DBHU};
      my $bool = _DbLog_SBP_pingDB ( {name => $name, dbh => $dbh} );

      if (!$bool) {
          delete $hash->{DBHU};
          $dbh          = _DbLog_getNewDBHandle ($hash) || return "Can't connect to database.";
          $hash->{DBHU} = $dbh;

          Log3 ($name, 4, "$name - Created new DBHU for PID: $$");
      }
  }
  else {
      $dbh          = _DbLog_getNewDBHandle ($hash) || return "Can't connect to database.";
      $hash->{DBHU} = $dbh;

      Log3 ($name, 4, "$name - Created new DBHU for PID: $$");
  }

return;
}

###################################################################################
# Neuer DB Handle zur allgemeinen Verwendung
###################################################################################
sub _DbLog_getNewDBHandle {
  my $hash = shift;
  my $name = $hash->{NAME};

  my ($useac,$useta) = DbLog_commitMode ($name, AttrVal($name, 'commitMode', $dblog_cmdef));

  my $params = { name       => $name,
                 dbconn     => $hash->{dbconn},
                 dbname     => (split /;|=/, $hash->{dbconn})[1],
                 dbuser     => $hash->{dbuser},
                 dbpassword => $attr{"sec$name"}{secret},
                 utf8       => defined($hash->{UTF8}) ? $hash->{UTF8} : 0,
                 useac      => $useac,
                 model      => $hash->{MODEL},
                 sltjm      => AttrVal ($name, 'SQLiteJournalMode', 'WAL'),
                 sltcs      => AttrVal ($name, 'SQLiteCacheSize',    4000)
               };


  my ($error, $dbh) = _DbLog_SBP_connectDB ($params);

  return $dbh if(!$error);

return;
}

####################################################################################################
#          SQL Query evaluieren und return ein Ergebnis-Array bei Erfolg
####################################################################################################
sub _DbLog_prepExecQueryOnly {
  my $name = shift;
  my $dbh  = shift;
  my $sql  = shift;
  my $info = shift // "SQL execute: $sql";

  my $err  = q{};
  my @sr   = ();

  my ($sth,$result);

  Log3 ($name, 4, "$name - Executing SQL: $sql");

  eval{ $sth = $dbh->prepare($sql);
        $sth->execute;
        1;
      }
      or do { $err = $@;
              Log3 ($name, 2, "$name - ERROR - $err");
              return $err;
            };

  @sr = $sth->fetchrow_array;

  no warnings 'uninitialized';
  Log3 ($name, 4, "$name - SQL result: ".join ' ', @sr);
  use warnings;

return ($err, @sr);
}

##########################################################################
#
# Prozedur zum Ausfuehren von SQL-Statements durch externe Module
#
# param1: DbLog-hash
# param2: SQL-Statement
#
##########################################################################
sub DbLog_ExecSQL {
  my $hash = shift;
  my $sql  = shift;

  my $err = _DbLog_manageDBHU ($hash);
  return $err if($err);

  my $dbh  = $hash->{DBHU};
  my $name = $hash->{NAME};

  Log3 ($name, 4, "$name - Backdoor executing: $sql");

  ($err, my $sth) = _DbLog_SBP_dbhDo ($name, $dbh, $sql, '');
  $sth = 0 if($err);

  __DbLog_SBP_commitOnly     ($name, $dbh, 'unspecified');
  __DbLog_SBP_disconnectOnly ($name, $dbh);

return $sth;
}

################################################################
#
# GET Funktion
# wird zb. zur Generierung der Plots implizit aufgerufen
# in : [-|current|history]
# out: [-|ALL|INT|WEBCHART]
#
################################################################
sub DbLog_Get {
  my ($hash, @a) = @_;

  return qq{"get X" needs at least an argument} if(@a < 2);

  my $name = $hash->{NAME};
  @a       = (map { my $p = $_; $p =~ s/\s//xg; $p; } @a);

  shift @a;                                                                    # Device Name wird entfernt

  my $opt = $a[0];                                                             # Kommando spezifizieren / ableiten
  $opt    = 'plotdata' if(lc($a[0]) =~ /^(-|current|history|table_.*)$/ixs);   # table_ als Kennung für Benutzung alternativer Tabellen ab V 5.9.1
  $opt    = 'webchart' if($a[1] && lc($a[1]) eq 'webchart');

  my $params = {
      hash  => $hash,
      name  => $name,
      opt   => $opt,
      aref  => \@a
  };

  if($DbLog_hget{$opt} && defined &{$DbLog_hget{$opt}{fn}}) {
      return &{$DbLog_hget{$opt}{fn}} ($params);
  }

  my $getlist = "Unknown argument $opt, choose one of ".
                "configCheck:noArg ".
                "ReadingsVal: ".
                "ReadingsTimestamp ".
                "ReadingsValTimestamp ".
                "ReadingsMaxVal ".
                "ReadingsMaxValTimestamp ".
                "ReadingsMinVal ".
                "ReadingsMinValTimestamp ".
                "ReadingsAvgVal ".
                "retrieve: "
                ;

return $getlist;
}

########################################################################################
# get <dbLog> ReadingsVal               <device> <reading> <default>
# get <dbLog> ReadingsTimestamp         <device> <reading> <default>
# get <dbLog> ReadingsValTimestamp      <device> <reading> <default>
# get <dbLog> ReadingsMaxVal[Timestamp] <device> <reading> <default>
# get <dbLog> ReadingsMinVal[Timestamp] <device> <reading> <default>
# get <dbLog> ReadingsAvgVal            <device> <reading> <default>
########################################################################################
sub _DbLog_dbReadings {
  my $paref   = shift;

  my $hash    = $paref->{hash};
  my @args    = @{$paref->{aref}};
  my $history = $hash->{HELPER}{TH};

  my $err = _DbLog_manageDBHU ($hash);
  return $err if($err);

  my $dbh = $hash->{DBHU};

  return 'Wrong Syntax for getting Reading values!' unless defined($args[3]);

  my $cmd     = $args[0];
  my $device  = $args[1];
  my $reading = $args[2];
  my $def     = $args[3];

  my $query = q{};

  if ($cmd =~ /ReadingsMaxVal(Timestamp)?$/xs) {
      $query = "select MAX(VALUE),TIMESTAMP from $history where DEVICE= '$device' and READING= '$reading';";
  }
  elsif ($cmd =~ /ReadingsMinVal(Timestamp)?$/xs) {
      $query = "select MIN(VALUE),TIMESTAMP from $history where DEVICE= '$device' and READING= '$reading';";
  }
  elsif ($cmd =~ /ReadingsAvgVal/xs) {
      $query = "select AVG(VALUE) from $history where DEVICE= '$device' and READING= '$reading';";
  }
  elsif ($cmd =~ /Readings(Val|ValTimestamp|Timestamp)$/xs) {
      $query = "select VALUE,TIMESTAMP from $history where DEVICE= '$device' and READING= '$reading' order by TIMESTAMP desc limit 1;";
  }

  return ">$cmd< isn't valid!" if(!$query);

  ($err, my $val, my $timestamp) = __DbLog_SBP_selectrowArray ($dbh, $query);
  return "error-> $err" if($err);

  $val       = defined $val       ? $val       : $def;
  $timestamp = defined $timestamp ? $timestamp : $def;

  if ($cmd =~ /Readings(Max|Min|Avg)?Val$/xs) {
      return $val;
  }
  elsif ($cmd eq 'ReadingsTimestamp') {
      return $timestamp;
  }
  else {
      return ("$val , $timestamp");
  }

return;
}

################################################################
#     Getter für chartQuery
################################################################
sub _DbLog_chartQuery {
  my $paref = shift;

  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my @a     = @{$paref->{aref}};
  my $opt   = $paref->{opt};

  if ($opt eq 'webchart') {
      return "Usage: \n".
             "get $name &lt;in&gt; &lt;out&gt; &lt;from&gt; &lt;to&gt; &lt;column_spec&gt;...\n".
             "where column_spec is &lt;device&gt;:&lt;reading&gt;:&lt;default&gt;:&lt;fn&gt;\n".
             "(see the #DbLog entries in the .gplot files)\n".
             "\n".
             "Notes:\n".
             "&lt;in&gt; is not used, only for compatibility for FileLog, please use '-' for &lt;in&gt; \n".
             "&lt;out&gt; is a prefix, '-' means stdout\n"
             if(int(@a) < 4);
  }

  my ($sql, $countsql) = _DbLog_createQuerySql ($paref);

  if ($sql eq "error") {
     return DbLog_jsonError("Could not setup SQL String. Check your input data.");
  }
  elsif ($sql eq "errordb") {
     return DbLog_jsonError("The Database Type is not supported!");
  }

  my $err = _DbLog_manageDBHU ($hash);
  return $err if($err);

  my $dbh = $hash->{DBHU};

  my $totalcount;

  if (defined $countsql && $countsql ne "") {
      ($err, my $query_handle) = __DbLog_SBP_prepareOnly ($name, $dbh, $countsql);
      return DbLog_jsonError("Could not prepare statement: " .$err. ", SQL was: " .$countsql) if($err);

      ($err, $query_handle) = __DbLog_SBP_executeOnly ($name, $query_handle);
      return DbLog_jsonError("Could not execute statement: " . $err) if($err);

      my @data = $query_handle->fetchrow_array();
      $totalcount = join ", ", @data;
  }

  ($err, my $query_handle) = __DbLog_SBP_prepareOnly ($name, $dbh, $sql);
  return DbLog_jsonError("Could not prepare statement: " .$err. ", SQL was: " .$sql) if($err);

  ($err, $query_handle) = __DbLog_SBP_executeOnly ($name, $query_handle);
  return DbLog_jsonError("Could not execute statement: " . $err) if($err);

  my $columns = $query_handle->{'NAME'};
  my $columncnt;

  if($columns) {                                                                  # When columns are empty but execution was successful, we have done a successful INSERT, UPDATE or DELETE
      $columncnt = scalar @$columns;
  }
  else {
      return '{"success": "true", "msg":"All ok"}';
  }

  my $i          = 0;
  my $jsonstring = q({);
  $jsonstring   .= q("success": "true", ) if($opt eq 'retrieve');
  $jsonstring   .= q("data":[);

  while ( my @data = $query_handle->fetchrow_array()) {
      if($i == 0) {
          $jsonstring .= '{';
      }
      else {
          $jsonstring .= ',{';
      }

      for ($i = 0; $i < $columncnt; $i++) {
          $jsonstring .= q(");
          $jsonstring .= uc($query_handle->{NAME}->[$i]);
          $jsonstring .= q(":);

          if (defined $data[$i]) {
              my $fragment =  substr $data[$i], 0, 1;

              if ($fragment eq "{") {
                  $jsonstring .= $data[$i];
              }
              else {
                  $jsonstring .= '"'.$data[$i].'"';
              }
          }
          else {
              $jsonstring .= '""'
          }

          if($i != ($columncnt -1)) {
             $jsonstring .= q(,);
          }
      }

      $jsonstring .= q(});
  }

  $jsonstring .= q(]);

  if (defined $totalcount && $totalcount ne "") {
      $jsonstring .= ',"totalCount": '.$totalcount.'}';
  }
  else {
      $jsonstring .= q(});
  }

return $jsonstring;
}

################################################################
#                Prepare the SQL String
################################################################
sub _DbLog_createQuerySql {
    my $paref = shift;

    my $opt   = $paref->{opt};
    my $hash  = $paref->{hash};
    my @a     = @{$paref->{aref}};

    my $starttime       = $a[2];                        # <from>
    my $endtime         = $a[3];                        # <to>
    my $device          = $a[4];                        # <device>
    my $querytype       = $a[5];                        # <querytype>
    my $xaxis           = $a[6];                        # ein Datenbankfeld wie TIMESTAMP, READING, DEVICE, UNIT, EVENT
    my $reading         = $a[7];                        # ein Reading Name (<yaxis>)
    my $savename        = $a[8];                        # <savename>
    my $jsonChartConfig = $a[9];                        # <chartconfig>
    my $offset          = $a[10];                       # <pagingstart>
    my $limit           = $a[11];                       # <paginglimit>

    my $dbmodel         = $hash->{MODEL};
    my $history         = $hash->{HELPER}{TH};
    my $current         = $hash->{HELPER}{TC};

    if ($opt eq 'retrieve') {
        $querytype = $a[1];
        $device    = $a[2];
        $reading   = $a[3];
        $starttime = $a[4];
        $endtime   = $a[5];
        $offset    = $a[6];
        $limit     = $a[7];
        $xaxis     = 'TIMESTAMP';

        if ($querytype eq 'last') {
            $limit = '10' if(!$limit);
        }
    }

    $starttime =~ s/_/ / if($starttime);
    $endtime   =~ s/_/ / if($endtime);

    my ($sql, $jsonstring, $countsql);

    my ($hourstats, $daystats, $weekstats, $monthstats, $yearstats) = ('error', 'error', 'error', 'error', 'error');

    if ($device && $reading && $starttime && $endtime) {
        if ($dbmodel eq "POSTGRESQL") {
            ### POSTGRESQL Queries for Statistics ###
            ### hour:
            $hourstats  = "SELECT to_char(timestamp, 'YYYY-MM-DD HH24:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
            $hourstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
            $hourstats .= "COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$reading' AND DEVICE = '$device' ";
            $hourstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

            ### day:
            $daystats  = "SELECT to_char(timestamp, 'YYYY-MM-DD 00:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
            $daystats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
            $daystats .= "COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$reading' AND DEVICE = '$device' ";
            $daystats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

            ### week:
            $weekstats  = "SELECT date_trunc('week',timestamp) AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
            $weekstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
            $weekstats .= "COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$reading' AND DEVICE = '$device' ";
            $weekstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

            ### month:
            $monthstats  = "SELECT to_char(timestamp, 'YYYY-MM-01 00:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
            $monthstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
            $monthstats .= "COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$reading' AND DEVICE = '$device' ";
            $monthstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

            ### year:
            $yearstats  = "SELECT to_char(timestamp, 'YYYY-01-01 00:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
            $yearstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
            $yearstats .= "COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$reading' AND DEVICE = '$device' ";
            $yearstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";
        }
        elsif ($dbmodel eq "MYSQL") {
            ### MYSQL Queries for Statistics ###
            ### hour:
            $hourstats  = "SELECT date_format(timestamp, '%Y-%m-%d %H:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
            $hourstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
            $hourstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$reading' ";
            $hourstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

            ### day:
            $daystats  = "SELECT date_format(timestamp, '%Y-%m-%d 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
            $daystats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
            $daystats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$reading' ";
            $daystats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

            ### week:
            $weekstats  = "SELECT date_format(timestamp, '%Y-%m-%d 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
            $weekstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
            $weekstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$reading' ";
            $weekstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' ";
            $weekstats .= "GROUP BY date_format(timestamp, '%Y-%u 00:00:00') ORDER BY 1;";

            ### month:
            $monthstats  = "SELECT date_format(timestamp, '%Y-%m-01 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
            $monthstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
            $monthstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$reading' ";
            $monthstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

            ### year:
            $yearstats  = "SELECT date_format(timestamp, '%Y-01-01 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
            $yearstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
            $yearstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$reading' ";
            $yearstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";
        }
        elsif ($dbmodel eq "SQLITE") {
            ### SQLITE Queries for Statistics ###
            ### hour:
            $hourstats  = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
            $hourstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
            $hourstats .= "FROM $history WHERE READING = '$reading' AND DEVICE = '$device' ";
            $hourstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%m-%d %H:00:00', TIMESTAMP);";

            ### day:
            $daystats  = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
            $daystats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
            $daystats .= "FROM $history WHERE READING = '$reading' AND DEVICE = '$device' ";
            $daystats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%m-%d 00:00:00', TIMESTAMP);";

            ### week:
            $weekstats  = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
            $weekstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
            $weekstats .= "FROM $history WHERE READING = '$reading' AND DEVICE = '$device' ";
            $weekstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%W 00:00:00', TIMESTAMP);";

            ### month:
            $monthstats  = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
            $monthstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
            $monthstats .= "FROM $history WHERE READING = '$reading' AND DEVICE = '$device' ";
            $monthstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%m 00:00:00', TIMESTAMP);";

            ### year:
            $yearstats  = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
            $yearstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
            $yearstats .= "FROM $history WHERE READING = '$reading' AND DEVICE = '$device' ";
            $yearstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y 00:00:00', TIMESTAMP);";
        }
        else {
            $sql = "errordb";
        }
    }

    $sql = 'error';

    if ($querytype eq 'getdevices' || $querytype eq 'alldevices') {
        $sql = "SELECT distinct(device) FROM $history";
    }
    elsif ($querytype eq 'getreadings' || $querytype eq 'allreadings') {
        if ($device) {
            $sql = "SELECT distinct(reading) FROM $history WHERE device = '$device'";
        }
    }
    elsif ($querytype eq 'last') {
        $sql = "SELECT TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT from $history ORDER BY TIMESTAMP DESC LIMIT $limit";
    }
    elsif ($querytype eq 'count') {
        if ($device) {
            my $table = $device;
            $sql      = "SELECT COUNT(*) AS COUNT_".$table." from $table";
        }
    }
    elsif ($querytype eq 'timerange') {
        if ($device && $reading && $starttime && $endtime) {
            $sql = "SELECT ".$xaxis.", VALUE FROM $history WHERE READING = '$reading' AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' ORDER BY TIMESTAMP;";
        }
    }
    elsif ($querytype eq 'hourstats') {
        $sql = $hourstats;
    }
    elsif ($querytype eq 'daystats') {
        $sql = $daystats;
    }
    elsif ($querytype eq 'weekstats') {
        $sql = $weekstats;
    }
    elsif ($querytype eq 'monthstats') {
        $sql = $monthstats;
    }
    elsif ($querytype eq 'yearstats') {
        $sql = $yearstats;
    }
    elsif ($querytype eq 'savechart') {
        $sql = "INSERT INTO frontend (TYPE, NAME, VALUE) VALUES ('savedchart', '$savename', '$jsonChartConfig')";
    }
    elsif ($querytype eq 'renamechart') {
        $sql = "UPDATE frontend SET NAME = '$savename' WHERE ID = '$jsonChartConfig'";
    }
    elsif ($querytype eq 'deletechart') {
        $sql = "DELETE FROM frontend WHERE TYPE = 'savedchart' AND ID = '".$savename."'";
    }
    elsif ($querytype eq 'updatechart') {
        $sql = "UPDATE frontend SET VALUE = '$jsonChartConfig' WHERE ID = '".$savename."'";
    }
    elsif ($querytype eq 'getcharts') {
        $sql = "SELECT * FROM frontend WHERE TYPE = 'savedchart'";
    }
    elsif ($querytype eq 'getTableData' || $querytype eq 'fetchrows') {
        if ($device ne '""' && $reading ne '""') {
            $sql       = "SELECT * FROM $history WHERE READING = '$reading' AND DEVICE = '$device' ";
            $sql      .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
            $sql      .= " LIMIT '$limit' OFFSET '$offset'";

            $countsql  = "SELECT count(*) FROM $history WHERE READING = '$reading' AND DEVICE = '$device' ";
            $countsql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
        }
        elsif ($device ne '""' && $reading eq '""') {
            $sql       = "SELECT * FROM $history WHERE DEVICE = '$device' ";
            $sql      .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
            $sql      .= " LIMIT '$limit' OFFSET '$offset'";

            $countsql  = "SELECT count(*) FROM $history WHERE DEVICE = '$device' ";
            $countsql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
        }
        elsif ($device eq '""' && $reading ne '""') {
            $sql       = "SELECT * FROM $history WHERE READING = '$reading' ";
            $sql      .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
            $sql      .= " LIMIT '$limit' OFFSET '$offset'";

            $countsql  = "SELECT count(*) FROM $history WHERE READING = '$reading' ";
            $countsql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
        }
        else {
            $sql       = "SELECT * FROM $history";
            $sql      .= " WHERE TIMESTAMP Between '$starttime' AND '$endtime'";
            $sql      .= " LIMIT '$limit' OFFSET '$offset'";

            $countsql  = "SELECT count(*) FROM $history";
            $countsql .= " WHERE TIMESTAMP Between '$starttime' AND '$endtime'";
        }

        return ($sql, $countsql);
    }

return $sql;
}

################################################################
#     Getter für SVG Plotgenerierung
################################################################
sub _DbLog_plotData {
  my $paref = shift;

  my $hash  = $paref->{hash};
  my $name  = $paref->{name};
  my @a     = @{$paref->{aref}};

  return "Usage: \n".
         "get $name &lt;in&gt; &lt;out&gt; &lt;from&gt; &lt;to&gt; &lt;column_spec&gt;...\n".
         "where column_spec is &lt;device&gt;:&lt;reading&gt;:&lt;default&gt;:&lt;fn&gt;\n".
         "(see the #DbLog entries in the .gplot files)\n".
         "\n".
         "Notes:\n".
         "&lt;in&gt; is not used, only for compatibility for FileLog, please use '-' for &lt;in&gt; \n".
         "&lt;out&gt; is a prefix, '-' means stdout\n"
         if(int(@a) < 4);

  my ($dbh,$err);
  my ($internal, @fld);

  my $utf8    = defined($hash->{UTF8}) ? $hash->{UTF8} : 0;
  my $history = $hash->{HELPER}{TH} // 'history';
  my $current = $hash->{HELPER}{TC} // 'current';
  my $inf     = lc(shift @a);
  my $outf    = lc(shift @a);               # Wert ALL:   get all colums from table, including a header
                                            # Wert Array: get the columns as array of hashes
                                            # Wert INT:   internally used by generating plots
  my $from    = shift @a;
  my $to      = shift @a;                   # Now @a contains the list of column_specs
  my $table   = $history;

  if ($inf eq "-") {
      $table = $history;
  }
  
  if ($inf =~ /table_/xs) {
      $table = (split "_", $inf)[1];        # alternative Tabelle ab V 5.9.1
  }

  if ($outf eq "int" && $inf eq "current") {
      $table = $history;
      Log3 $name, 3, "Defining DbLog SVG-Plots with :CURRENT is deprecated. Please define DbLog SVG-Plots with :HISTORY instead of :CURRENT. (define <mySVG> SVG <DbLogDev>:<gplotfile>:HISTORY)";
  }

  if($outf eq "int") {
      $outf     = "-";
      $internal = 1;
  }
  elsif ($outf eq "array") {

  }

  my (%sqlspec, %from_datetime, %to_datetime);

  my @readings = ();
  my $verbose  = AttrVal ($name, 'verbose', $attr{global}{verbose});

  # uebergebenen Timestamp anpassen
  # moegliche Formate: YYYY | YYYY-MM | YYYY-MM-DD | YYYY-MM-DD_HH24
  $from          =~ s/_/\ /g;
  $to            =~ s/_/\ /g;
  %from_datetime = DbLog_explode_datetime ($from, DbLog_explode_datetime("2000-01-01 00:00:00", ()));
  %to_datetime   = DbLog_explode_datetime ($to,   DbLog_explode_datetime("2099-01-01 00:00:00", ()));
  $from          = $from_datetime{datetime};
  $to            = $to_datetime{datetime};

  $err = DbLog_checkTimeformat($from);                                     # Forum: https://forum.fhem.de/index.php/topic,101005.0.html
  if($err) {
      Log3 ($name, 1, "$name - wrong date/time format (from: $from) requested by SVG: $err");
      return;
  }

  $err = DbLog_checkTimeformat($to);                                       # Forum: https://forum.fhem.de/index.php/topic,101005.0.html
  if($err) {
      Log3 ($name, 1, "$name - wrong date/time format (to: $to) requested by SVG: $err");
      return;
  }

  if($to =~ /(\d{4})-(\d{2})-(\d{2}) 23:59:59/) {
     # 03.09.2018 : https://forum.fhem.de/index.php/topic,65860.msg815640.html#msg815640
     $to =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/;
     my $tc = timelocal($6, $5, $4, $3, $2-1, $1-1900);
     $tc++;
     $to = strftime "%Y-%m-%d %H:%M:%S", localtime($tc);
  }

  my ($retval,$retvaldummy,$hour,$sql_timestamp, $sql_device, $sql_reading, $sql_value, $type, $event, $unit) = "";
  my @ReturnArray;
  my $writeout = 0;
  my (@min, @max, @sum, @cnt, @firstv, @firstd, @lastv, @lastd, @mind, @maxd);
  my (%tstamp, %lasttstamp, $out_tstamp, $out_value, $minval, $maxval, $deltacalc);   # fuer delta-h/d Berechnung

  # extract the Device:Reading arguments into @readings array
  # Ausgangspunkt ist z.B.: KS300:temperature KS300:rain::delta-h KS300:rain::delta-d
  for (my $i = 0; $i < int(@a); $i++) {
      @fld             = split ":", $a[$i], 5;
      $readings[$i][0] = $fld[0];                                   # Device
      $readings[$i][1] = $fld[1];                                   # Reading
      $readings[$i][2] = $fld[2];                                   # Default
      $readings[$i][3] = $fld[3];                                   # function
      $readings[$i][4] = $fld[4];                                   # regexp

      $readings[$i][1] = "%" if(!$readings[$i][1] || length($readings[$i][1])==0);   # falls Reading nicht gefuellt setze Joker
  }

  if ($verbose > 3) {
      Log3 ($name, 4, "$name - ################################################################");
      Log3 ($name, 4, "$name - ###                  new get data for SVG                    ###");
      Log3 ($name, 4, "$name - ################################################################");
      Log3 ($name, 4, "$name - main PID: $hash->{PID}, secondary PID: $$");
  }

  my $samePID = $hash->{PID} == $$ ? 1 : 0;

  if ($samePID) {
      $err = _DbLog_manageDBHU ($hash);
      return $err if($err);

      $dbh = $hash->{DBHU};
  }
  else {
      $dbh = _DbLog_getNewDBHandle($hash) || return "Can't connect to database.";

      Log3 ($name, 4, "$name - Created new DBHU for PID: $$");
  }

  # vorbereiten der DB-Abfrage, DB-Modell-abhaengig
  if ($hash->{MODEL} eq "POSTGRESQL") {
      $sqlspec{get_timestamp}  = "TO_CHAR(TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')";
      $sqlspec{from_timestamp} = "TO_TIMESTAMP('$from', 'YYYY-MM-DD HH24:MI:SS')";
      $sqlspec{to_timestamp}   = "TO_TIMESTAMP('$to', 'YYYY-MM-DD HH24:MI:SS')";
      $sqlspec{order_by_hour}  = "TO_CHAR(TIMESTAMP, 'YYYY-MM-DD HH24')";
      $sqlspec{max_value}      = "MAX(VALUE)";
      $sqlspec{day_before}     = "($sqlspec{from_timestamp} - INTERVAL '1 DAY')";
  }
  elsif ($hash->{MODEL} eq "ORACLE") {
      $sqlspec{get_timestamp}  = "TO_CHAR(TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')";
      $sqlspec{from_timestamp} = "TO_TIMESTAMP('$from', 'YYYY-MM-DD HH24:MI:SS')";
      $sqlspec{to_timestamp}   = "TO_TIMESTAMP('$to', 'YYYY-MM-DD HH24:MI:SS')";
      $sqlspec{order_by_hour}  = "TO_CHAR(TIMESTAMP, 'YYYY-MM-DD HH24')";
      $sqlspec{max_value}      = "MAX(VALUE)";
      $sqlspec{day_before}     = "DATE_SUB($sqlspec{from_timestamp},INTERVAL 1 DAY)";
  }
  elsif ($hash->{MODEL} eq "MYSQL") {
      $sqlspec{get_timestamp}  = "DATE_FORMAT(TIMESTAMP, '%Y-%m-%d %H:%i:%s')";
      $sqlspec{from_timestamp} = "STR_TO_DATE('$from', '%Y-%m-%d %H:%i:%s')";
      $sqlspec{to_timestamp}   = "STR_TO_DATE('$to', '%Y-%m-%d %H:%i:%s')";
      $sqlspec{order_by_hour}  = "DATE_FORMAT(TIMESTAMP, '%Y-%m-%d %H')";
      $sqlspec{max_value}      = "MAX(VALUE)";                                           # 12.04.2019 Forum: https://forum.fhem.de/index.php/topic,99280.0.html
      $sqlspec{day_before}     = "DATE_SUB($sqlspec{from_timestamp},INTERVAL 1 DAY)";
  }
  elsif ($hash->{MODEL} eq "SQLITE") {
      $sqlspec{get_timestamp}  = "TIMESTAMP";
      $sqlspec{from_timestamp} = "'$from'";
      $sqlspec{to_timestamp}   = "'$to'";
      $sqlspec{order_by_hour}  = "strftime('%Y-%m-%d %H', TIMESTAMP)";
      $sqlspec{max_value}      = "MAX(VALUE)";
      $sqlspec{day_before}     = "date($sqlspec{from_timestamp},'-1 day')";
  }
  else {
      $sqlspec{get_timestamp}  = "TIMESTAMP";
      $sqlspec{from_timestamp} = "'$from'";
      $sqlspec{to_timestamp}   = "'$to'";
      $sqlspec{order_by_hour}  = "strftime('%Y-%m-%d %H', TIMESTAMP)";
      $sqlspec{max_value}      = "MAX(VALUE)";
      $sqlspec{day_before}     = "date($sqlspec{from_timestamp},'-1 day')";
  }

  if($outf =~ m/(all|array)/) {
      $sqlspec{all}      = ",TYPE,EVENT,UNIT";
      $sqlspec{all_max}  = ",MAX(TYPE) AS TYPE,MAX(EVENT) AS EVENT,MAX(UNIT) AS UNIT";
  }
  else {
      $sqlspec{all}      = "";
      $sqlspec{all_max}  = "";
  }

  for (my $i = 0; $i < int(@readings); $i++) {                # ueber alle Readings Variablen initialisieren
      $min[$i]    =  (~0 >> 1);
      $max[$i]    = -(~0 >> 1);
      $sum[$i]    = 0;
      $cnt[$i]    = 0;
      $firstv[$i] = 0;
      $firstd[$i] = "undef";
      $lastv[$i]  = 0;
      $lastd[$i]  = "undef";
      $mind[$i]   = "undef";
      $maxd[$i]   = "undef";
      $minval     =  (~0 >> 1);                               # ist "9223372036854775807"
      $maxval     = -(~0 >> 1);                               # ist "-9223372036854775807"
      $deltacalc  = 0;

      if($readings[$i]->[3] && ($readings[$i]->[3] eq "delta-h" || $readings[$i]->[3] eq "delta-d")) {
          $deltacalc = 1;

          if ($verbose > 3) {
              Log3 ($name, 4, "$name - deltacalc: hour") if($readings[$i]->[3] eq "delta-h");   # geändert V4.8.0 / 14.10.2019
              Log3 ($name, 4, "$name - deltacalc: day")  if($readings[$i]->[3] eq "delta-d");   # geändert V4.8.0 / 14.10.2019
          }
      }

      my ($stm);

      if($deltacalc) {
          $stm  = "SELECT Z.TIMESTAMP, Z.DEVICE, Z.READING, Z.VALUE from ";

          $stm .= "(SELECT $sqlspec{get_timestamp} AS TIMESTAMP,
                    DEVICE AS DEVICE,
                    READING AS READING,
                    VALUE AS VALUE ";

          $stm .= "FROM $table ";

          $stm .= "WHERE 1=1 ";

          $stm .= "AND DEVICE  = '".$readings[$i]->[0]."' "   if ($readings[$i]->[0] !~ m(\%));
          $stm .= "AND DEVICE LIKE '".$readings[$i]->[0]."' " if(($readings[$i]->[0] !~ m(^\%$)) && ($readings[$i]->[0] =~ m(\%)));

          $stm .= "AND READING = '".$readings[$i]->[1]."' "    if ($readings[$i]->[1] !~ m(\%));
          $stm .= "AND READING LIKE '".$readings[$i]->[1]."' " if(($readings[$i]->[1] !~ m(^%$)) && ($readings[$i]->[1] =~ m(\%)));

          $stm .= "AND TIMESTAMP < $sqlspec{from_timestamp} ";
          $stm .= "AND TIMESTAMP > $sqlspec{day_before} ";

          $stm .= "ORDER BY TIMESTAMP DESC LIMIT 1 ) AS Z
                   UNION ALL " if($readings[$i]->[3] eq "delta-h");

          $stm .= "ORDER BY TIMESTAMP) AS Z
                   UNION ALL " if($readings[$i]->[3] eq "delta-d");

          $stm .= "SELECT
                   MAX($sqlspec{get_timestamp}) AS TIMESTAMP,
                   MAX(DEVICE) AS DEVICE,
                   MAX(READING) AS READING,
                   $sqlspec{max_value}
                   $sqlspec{all_max} ";

          $stm .= "FROM $table ";

          $stm .= "WHERE 1=1 ";

          $stm .= "AND DEVICE  = '".$readings[$i]->[0]."' "    if ($readings[$i]->[0] !~ m(\%));
          $stm .= "AND DEVICE LIKE '".$readings[$i]->[0]."' "  if(($readings[$i]->[0] !~ m(^\%$)) && ($readings[$i]->[0] =~ m(\%)));

          $stm .= "AND READING = '".$readings[$i]->[1]."' "    if ($readings[$i]->[1] !~ m(\%));
          $stm .= "AND READING LIKE '".$readings[$i]->[1]."' " if(($readings[$i]->[1] !~ m(^%$)) && ($readings[$i]->[1] =~ m(\%)));

          $stm .= "AND TIMESTAMP >= $sqlspec{from_timestamp} ";
          $stm .= "AND TIMESTAMP <= $sqlspec{to_timestamp} ";           # 03.09.2018 : https://forum.fhem.de/index.php/topic,65860.msg815640.html#msg815640

          $stm .= "GROUP BY $sqlspec{order_by_hour} " if($deltacalc);
          $stm .= "ORDER BY TIMESTAMP";
      }
      else {                                                            # kein deltacalc
          $stm =  "SELECT
                      $sqlspec{get_timestamp},
                      DEVICE,
                      READING,
                      VALUE
                      $sqlspec{all} ";

          $stm .= "FROM $table ";

          $stm .= "WHERE 1=1 ";

          $stm .= "AND DEVICE = '".$readings[$i]->[0]."' "     if ($readings[$i]->[0] !~ m(\%));
          $stm .= "AND DEVICE LIKE '".$readings[$i]->[0]."' "  if(($readings[$i]->[0] !~ m(^\%$)) && ($readings[$i]->[0] =~ m(\%)));

          $stm .= "AND READING = '".$readings[$i]->[1]."' "    if ($readings[$i]->[1] !~ m(\%));
          $stm .= "AND READING LIKE '".$readings[$i]->[1]."' " if(($readings[$i]->[1] !~ m(^%$)) && ($readings[$i]->[1] =~ m(\%)));

          $stm .= "AND TIMESTAMP >= $sqlspec{from_timestamp} ";
          $stm .= "AND TIMESTAMP <= $sqlspec{to_timestamp} ";           # 03.09.2018 : https://forum.fhem.de/index.php/topic,65860.msg815640.html#msg815640
          $stm .= "ORDER BY TIMESTAMP";
      }

      Log3 ($name, 4, "$name - PID: $$, Processing Statement:\n$stm");

      my $sth = $dbh->prepare($stm) || return "Cannot prepare statement $stm: $DBI::errstr";
      my $rc  = $sth->execute()     || return "Cannot execute statement $stm: $DBI::errstr";

      if($outf =~ m/(all|array)/) {
          $sth->bind_columns(undef, \$sql_timestamp, \$sql_device, \$sql_reading, \$sql_value, \$type, \$event, \$unit);
      }
      else {
          $sth->bind_columns(undef, \$sql_timestamp, \$sql_device, \$sql_reading, \$sql_value);
      }

      if ($outf =~ m/(all)/) {
          $retval .= "Timestamp: Device, Type, Event, Reading, Value, Unit\n";
          $retval .= "=====================================================\n";
      }

      ####################################################################################
      #                              Select Auswertung
      ####################################################################################
      my $rv = 0;

      while ($sth->fetch()) {
          $rv++;

          no warnings 'uninitialized';                                                                     # geändert V4.8.0 / 14.10.2019
          my $ds = "PID: $$, TS: $sql_timestamp, DEV: $sql_device, RD: $sql_reading, VAL: $sql_value";     # geändert V4.8.0 / 14.10.2019

          Log3 ($name, 5, "$name - SQL-result -> $ds");

          use warnings;                                                                                    # geändert V4.8.0 / 14.10.2019

          $writeout = 0;                                                                                   # eingefügt V4.8.0 / 14.10.2019

          ############ Auswerten des 5. Parameters: Regexp ###################
          # die Regexep wird vor der Function ausgewertet und der Wert im Feld
          # Value angepasst.
          # z.B.: KS300:temperature KS300:rain::delta-h KS300:rain::delta-d
          #                            0    1  2  3
          # $readings[$i][0] = Device
          # $readings[$i][1] = Reading
          # $readings[$i][2] = Default
          # $readings[$i][3] = function
          # $readings[$i][4] = regexp
          ####################################################################
          if($readings[$i]->[4]) {
              #evaluate
              my $val = $sql_value;
              my $ts  = $sql_timestamp;

              eval("$readings[$i]->[4]");
              $sql_value     = $val;
              $sql_timestamp = $ts;

              if ($@) {
                  Log3 ($name, 3, "DbLog: Error in inline function: <".$readings[$i]->[4].">, Error: $@");
              }
          }

          if ($sql_timestamp lt $from && $deltacalc) {
              if (Scalar::Util::looks_like_number($sql_value)) {                                 # nur setzen wenn numerisch
                  $minval    = $sql_value if($sql_value < $minval || ($minval =  (~0 >> 1)) );   # geändert V4.8.0 / 14.10.2019
                  $maxval    = $sql_value if($sql_value > $maxval || ($maxval = -(~0 >> 1)) );   # geändert V4.8.0 / 14.10.2019
                  $lastv[$i] = $sql_value;
              }
          }
          else {
              $writeout    = 0;
              $out_value   = "";
              $out_tstamp  = "";
              $retvaldummy = "";

              if ($readings[$i]->[4]) {
                  $out_tstamp = $sql_timestamp;
                  $writeout   = 1 if(!$deltacalc);
              }

              ############ Auswerten des 4. Parameters: Funktion ###################
              ######################################################################
              if ($readings[$i]->[3] && $readings[$i]->[3] eq "int") {                        # nur den integerwert uebernehmen falls zb value=15°C
                  $out_value  = $1 if($sql_value =~ m/^(\d+).*/o);
                  $out_tstamp = $sql_timestamp;
                  $writeout   = 1;
              }
              elsif ($readings[$i]->[3] && $readings[$i]->[3] =~ m/^int(\d+).*/o) {           # Uebernehme den Dezimalwert mit den angegebenen Stellen an Nachkommastellen
                  $readings[$i]->[3] =~ m/^int(\d+).*/xs;
                  my $dnum    = $1;
                  #$out_value  = $1 if($sql_value =~ m/^([-\.\d]+).*/o);         
                  $out_value  = $1 if($sql_value =~ m/^(-?\d+\.?\d{1,$dnum}).*/xs);           # V5.8.6
                  $out_tstamp = $sql_timestamp;
                  $writeout   = 1;
              }
              elsif ($readings[$i]->[3] && $readings[$i]->[3] eq "delta-ts" && lc($sql_value) !~ m(ignore)) {
                  # Berechung der vergangen Sekunden seit dem letzten Logeintrag
                  # zb. die Zeit zwischen on/off
                  my @a = split("[- :]", $sql_timestamp);
                  my $akt_ts = mktime($a[5],$a[4],$a[3],$a[2],$a[1]-1,$a[0]-1900,0,0,-1);

                  if ($lastd[$i] ne "undef") {
                      @a = split("[- :]", $lastd[$i]);
                  }

                  my $last_ts = mktime($a[5],$a[4],$a[3],$a[2],$a[1]-1,$a[0]-1900,0,0,-1);
                  $out_tstamp = $sql_timestamp;
                  $out_value  = sprintf("%02d", $akt_ts - $last_ts);

                  if (lc($sql_value) =~ m(hide)) {
                      $writeout = 0;
                  }
                  else {
                      $writeout = 1;
                  }
              }
              elsif ($readings[$i]->[3] && $readings[$i]->[3] eq "delta-h") {                # Berechnung eines Delta-Stundenwertes
                  %tstamp = DbLog_explode_datetime($sql_timestamp, ());

                  if ($lastd[$i] eq "undef") {
                      %lasttstamp       = DbLog_explode_datetime($sql_timestamp, ());
                      $lasttstamp{hour} = "00";
                  }
                  else {
                      %lasttstamp = DbLog_explode_datetime($lastd[$i], ());
                  }

                  if ("$tstamp{hour}" ne "$lasttstamp{hour}") {
                      # Aenderung der Stunde, Berechne Delta
                      # wenn die Stundendifferenz größer 1 ist muss ein Dummyeintrag erstellt werden
                      $retvaldummy = "";

                      if (($tstamp{hour}-$lasttstamp{hour}) > 1) {
                          for (my $j = $lasttstamp{hour}+1; $j < $tstamp{hour}; $j++) {
                              $out_value  = "0";
                              $hour       = $j;
                              $hour       = '0'.$j if $j<10;
                              $cnt[$i]++;
                              $out_tstamp = DbLog_implode_datetime($tstamp{year}, $tstamp{month}, $tstamp{day}, $hour, "30", "00");

                              if ($outf =~ m/(all)/) {                                         # Timestamp: Device, Type, Event, Reading, Value, Unit
                                  $retvaldummy .= sprintf("%s: %s, %s, %s, %s, %s, %s\n", $out_tstamp, $sql_device, $type, $event, $sql_reading, $out_value, $unit);
                              } 
                              elsif ($outf =~ m/(array)/) {
                                  push(@ReturnArray, {"tstamp" => $out_tstamp, "device" => $sql_device, "type" => $type, "event" => $event, "reading" => $sql_reading, "value" => $out_value, "unit" => $unit});
                              }
                              else {
                                  $out_tstamp   =~ s/\ /_/g;                                   #needed by generating plots
                                  $retvaldummy .= "$out_tstamp $out_value\n";
                              }
                          }
                      }

                      if (($tstamp{hour}-$lasttstamp{hour}) < 0) {
                          for (my $j = 0; $j < $tstamp{hour}; $j++) {
                              $out_value  = "0";
                              $hour       = $j;
                              $hour       = '0'.$j if $j<10;
                              $cnt[$i]++;
                              $out_tstamp = DbLog_implode_datetime($tstamp{year}, $tstamp{month}, $tstamp{day}, $hour, "30", "00");

                              if ($outf =~ m/(all)/) {                                        # Timestamp: Device, Type, Event, Reading, Value, Unit
                                  $retvaldummy .= sprintf("%s: %s, %s, %s, %s, %s, %s\n", $out_tstamp, $sql_device, $type, $event, $sql_reading, $out_value, $unit);
                              }
                              elsif ($outf =~ m/(array)/) {
                                  push(@ReturnArray, {"tstamp" => $out_tstamp, "device" => $sql_device, "type" => $type, "event" => $event, "reading" => $sql_reading, "value" => $out_value, "unit" => $unit});
                              }
                              else {
                                  $out_tstamp =~ s/\ /_/g;                                    # needed by generating plots
                                  $retvaldummy .= "$out_tstamp $out_value\n";
                              }
                          }
                      }

                      $writeout   = 1 if($minval != (~0 >> 1) && $maxval != -(~0 >> 1));      # geändert V4.8.0 / 14.10.2019
                      $out_value  = ($writeout == 1) ? sprintf("%g", $maxval - $minval) : 0;  # if there was no previous reading in the selected time range, produce a null delta, %g - a floating-point number

                      $sum[$i]   += $out_value;
                      $cnt[$i]++;
                      $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, $lasttstamp{hour}, "30", "00");

                      $minval     = $maxval if($maxval != -(~0 >> 1));                        # only use the current range's maximum as the new minimum if a proper value was found

                      Log3 ($name, 5, "$name - Output delta-h -> TS: $tstamp{hour}, LASTTS: $lasttstamp{hour}, OUTTS: $out_tstamp, OUTVAL: $out_value, WRITEOUT: $writeout");
                  }
              }
              elsif ($readings[$i]->[3] && $readings[$i]->[3] eq "delta-d") {                 # Berechnung eines Tages-Deltas
                  %tstamp = DbLog_explode_datetime($sql_timestamp, ());

                  if ($lastd[$i] eq "undef") {
                      %lasttstamp = DbLog_explode_datetime($sql_timestamp, ());
                  }
                  else {
                      %lasttstamp = DbLog_explode_datetime($lastd[$i], ());
                  }

                  if ("$tstamp{day}" ne "$lasttstamp{day}") {                                 # Aenderung des Tages, berechne Delta
                      $writeout  = 1 if($minval != (~0 >> 1) && $maxval != -(~0 >> 1));       # geändert V4.8.0 / 14.10.2019
                      $out_value = ($writeout == 1) ? sprintf("%g", $maxval - $minval) : 0;   # if there was no previous reading in the selected time range, produce a null delta, %g - a floating-point number
                      $sum[$i]  += $out_value;
                      $cnt[$i]++;

                      $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, "12", "00", "00");
                      $minval     = $maxval if($maxval != -(~0 >> 1));                        # only use the current range's maximum as the new minimum if a proper value was found

                      Log3 ($name, 5, "$name - Output delta-d -> TS: $tstamp{day}, LASTTS: $lasttstamp{day}, OUTTS: $out_tstamp, OUTVAL: $out_value, WRITEOUT: $writeout");
                  }
              }
              else {
                  $out_value  = $sql_value;
                  $out_tstamp = $sql_timestamp;
                  $writeout   = 1;
              }

              # Wenn Attr SuppressUndef gesetzt ist, dann ausfiltern aller undef-Werte
              $writeout = 0 if (!defined($sql_value) && AttrVal($name, 'suppressUndef', 0));

              ###################### Ausgabe ###########################
              if($writeout) {
                  if ($outf =~ m/(all)/) {
                      # Timestamp: Device, Type, Event, Reading, Value, Unit
                      $retval .= sprintf("%s: %s, %s, %s, %s, %s, %s\n", $out_tstamp, $sql_device, $type, $event, $sql_reading, $out_value, $unit);
                      $retval .= $retvaldummy;
                  }
                  elsif ($outf =~ m/(array)/) {
                      push(@ReturnArray, {"tstamp" => $out_tstamp, "device" => $sql_device, "type" => $type, "event" => $event, "reading" => $sql_reading, "value" => $out_value, "unit" => $unit});
                  }
                  else {                                                         # generating plots
                      $out_tstamp =~ s/\ /_/g;                                   # needed by generating plots
                      $retval    .= "$out_tstamp $out_value\n";
                      $retval    .= $retvaldummy;
                  }
              }

              if (Scalar::Util::looks_like_number($sql_value)) {                  # nur setzen wenn numerisch
                  if ($deltacalc) {
                      if (Scalar::Util::looks_like_number($out_value)) {
                          if ($out_value < $min[$i]) {
                              $min[$i]  = $out_value;
                              $mind[$i] = $out_tstamp;
                          }

                          if ($out_value > $max[$i]) {
                              $max[$i]  = $out_value;
                              $maxd[$i] = $out_tstamp;
                          }
                      }

                      $maxval = $sql_value;
                  }
                  else {
                      if ($firstd[$i] eq "undef") {
                          $firstv[$i] = $sql_value;
                          $firstd[$i] = $sql_timestamp;
                      }

                      if ($sql_value < $min[$i]) {
                          $min[$i]  = $sql_value;
                          $mind[$i] = $sql_timestamp;
                      }

                      if ($sql_value > $max[$i]) {
                          $max[$i]  = $sql_value;
                          $maxd[$i] = $sql_timestamp;
                      }

                      $sum[$i] += $sql_value;
                      $minval   = $sql_value if($sql_value < $minval);
                      $maxval   = $sql_value if($sql_value > $maxval);
                  }
              }
              else {
                  $min[$i] = 0;
                  $max[$i] = 0;
                  $sum[$i] = 0;
                  $minval  = 0;
                  $maxval  = 0;
              }

              if (!$deltacalc) {
                  $cnt[$i]++;
                  $lastv[$i] = $sql_value;
              }
              else {
                  $lastv[$i] = $out_value if($out_value);
              }

              $lastd[$i] = $sql_timestamp;
          }
      }                                                        #### while fetchrow Ende #####

      Log3 ($name, 4, "$name - PID: $$, rows count: $rv");

      ######## den letzten Abschlusssatz rausschreiben ##########

      if ($readings[$i]->[3] && ($readings[$i]->[3] eq "delta-h" || $readings[$i]->[3] eq "delta-d")) {
          if ($lastd[$i] eq "undef") {
              $out_value  = "0";
              $out_tstamp = DbLog_implode_datetime($from_datetime{year}, $from_datetime{month}, $from_datetime{day}, $from_datetime{hour}, "30", "00") if($readings[$i]->[3] eq "delta-h");
              $out_tstamp = DbLog_implode_datetime($from_datetime{year}, $from_datetime{month}, $from_datetime{day}, "12", "00", "00") if($readings[$i]->[3] eq "delta-d");
          }
          else {
              %lasttstamp = DbLog_explode_datetime($lastd[$i], ());
              $out_value  = ($minval != (~0 >> 1) && $maxval != -(~0 >> 1)) ? sprintf("%g", $maxval - $minval) : 0;       # if there was no previous reading in the selected time range, produce a null delta
              $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, $lasttstamp{hour}, "30", "00") if($readings[$i]->[3] eq "delta-h");
              $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, "12", "00", "00") if($readings[$i]->[3] eq "delta-d");
          }

          $sum[$i] += $out_value;
          $cnt[$i]++;

          if ($outf =~ m/(all)/) {
              $retval .= sprintf("%s: %s %s %s %s %s %s\n", $out_tstamp, $sql_device, $type, $event, $sql_reading, $out_value, $unit);
          }
          elsif ($outf =~ m/(array)/) {
              push(@ReturnArray, {"tstamp" => $out_tstamp, "device" => $sql_device, "type" => $type, "event" => $event, "reading" => $sql_reading, "value" => $out_value, "unit" => $unit});
          }
          else {
             $out_tstamp =~ s/\ /_/g;                                                      #needed by generating plots
             $retval    .= "$out_tstamp $out_value\n";
          }

          Log3 ($name, 5, "$name - Output last DS -> OUTTS: $out_tstamp, OUTVAL: $out_value, WRITEOUT: implicit ");
      }

      # Datentrenner setzen
      $retval .= "#$readings[$i]->[0]";
      $retval .= ":";
      $retval .= "$readings[$i]->[1]" if($readings[$i]->[1]);
      $retval .= ":";
      $retval .= "$readings[$i]->[2]" if($readings[$i]->[2]);
      $retval .= ":";
      $retval .= "$readings[$i]->[3]" if($readings[$i]->[3]);
      $retval .= ":";
      $retval .= "$readings[$i]->[4]" if($readings[$i]->[4]);
      $retval .= "\n";

  }                                                                # Ende for @readings-Schleife über alle Readinggs im get

  # Ueberfuehren der gesammelten Werte in die globale Variable %data
  for (my $j = 0; $j < int(@readings); $j++) {
      $min[$j] = 0 if ($min[$j] == (~0 >> 1));                     # if min/max values could not be calculated due to the lack of query results, set them to 0
      $max[$j] = 0 if ($max[$j] == -(~0 >> 1));

      my $k = $j+1;
      $data{"min$k"}       = $min[$j];
      $data{"max$k"}       = $max[$j];
      $data{"avg$k"}       = $cnt[$j] ? sprintf("%0.2f", $sum[$j]/$cnt[$j]) : 0;
      $data{"sum$k"}       = $sum[$j];
      $data{"cnt$k"}       = $cnt[$j];
      $data{"firstval$k"}  = $firstv[$j];
      $data{"firstdate$k"} = $firstd[$j];
      $data{"currval$k"}   = $lastv[$j];
      $data{"currdate$k"}  = $lastd[$j];
      $data{"mindate$k"}   = $mind[$j];
      $data{"maxdate$k"}   = $maxd[$j];
  }

  if (!$samePID) {
      __DbLog_SBP_disconnectOnly ($name, $dbh);
      delete $hash->{DBHU};
  }

  if ($internal) {
      $internal_data = \$retval;
      return undef;
  }
  elsif ($outf =~ m/(array)/) {
      return @ReturnArray;
  }
  else {
      $retval = Encode::encode_utf8($retval) if($utf8);
      return $retval;
  }
}

###############################################################################################
#
# Exrahieren des Filters aus der ColumnsSpec (gplot-Datei)
#
# Die grundlegend idee ist das jeder svg plot einen filter hat der angibt
# welches device und reading dargestellt wird so das der plot sich neu
# lädt wenn es ein entsprechendes event gibt.
#
# Parameter: Quell-Instanz-Name, und alle FileLog-Parameter, die diese Instanz betreffen.
# Quelle: http://forum.fhem.de/index.php/topic,40176.msg325200.html#msg325200
###############################################################################################
sub DbLog_regexpFn {
  my $name   = shift;
  my $filter = shift;

  my $ret;

  my @a = split( ' ', $filter );

  for(my $i = 0; $i < int(@a); $i++) {
      my @fld = split(":", $a[$i]);

      $ret .= '|' if( $ret );
      no warnings 'uninitialized';            # Forum:74690, bug unitialized
      $ret .=  $fld[0] .'.'. $fld[1];
      use warnings;
  }

return $ret;
}

##########################################################################
#
#        Konfigurationscheck DbLog <-> Datenbank
#
##########################################################################
sub DbLog_configcheck {
  my $paref   = shift;
  my $hash    = $paref->{hash};

  my $name    = $hash->{NAME};
  my $dbmodel = $hash->{MODEL};
  my $dbconn  = $hash->{dbconn};
  my $dbname  = (split(/;|=/, $dbconn))[1];
  my $history = $hash->{HELPER}{TH};
  my $current = $hash->{HELPER}{TC};

  my ($check, $rec, $err, $upd, $msg, @config, %dbconfig);

  Log3 ($name, 4, "$name - ###  Start configCheck   ###");

  my $ok   = FW_makeImage('10px-kreis-gruen.png',     '');
  my $nok  = FW_makeImage('10px-kreis-rot.png',       '');
  my $warn = FW_makeImage('message_attention@orange', '');
  my $info = FW_makeImage('message_info',             '');

  ### verfügbare Treiber
  ########################
  my @ary = DBI->available_drivers('true');
  my $dlst;

  for my $drv (@ary) {
      $dlst .= ', ' if($dlst);
      $dlst .= 'DBD::'.$drv;
  }

  $check  = "<html>";
  $check .= "<u><b>Available Drivers in your system</u></b><br><br>";
  $check .= $dlst ? $dlst : 'no drivers found';
  $check .= "<br><br>";

  ### Version check
  ###################
  my $pv      = sprintf("%vd",$^V);                                              # Perl Version
  my $dbi     = $DBI::VERSION;                                                   # DBI Version
  my %drivers = DBI->installed_drivers();
  my $dv      = "";

  if ($dbmodel =~ /MYSQL/xi) {
      for (keys %drivers) {
          $dv = $_ if($_ =~ /mysql|mariadb/x);
      }
  }

  my $dbd = ($dbmodel =~ /POSTGRESQL/xi)   ? "Pg: ".$DBD::Pg::VERSION         :  # DBD Version
            ($dbmodel =~ /MYSQL/xi && $dv) ? "$dv: ".$DBD::mysql::VERSION     :
            ($dbmodel =~ /SQLITE/xi)       ? "SQLite: ".$DBD::SQLite::VERSION :
            "Undefined";

  my $dbdhint = "";
  my $dbdupd  = 0;

  if ($dbmodel =~ /MYSQL/xi && $dv) {                                             # check DBD Mindest- und empfohlene Version
      my $dbdver = $DBD::mysql::VERSION * 1;                                      # String to Zahl Konversion
      if($dbdver < 4.032) {
          $dbdhint = "<b>Caution:</b> Your DBD version doesn't support UTF8. ";
          $dbdupd  = 1;
      }
      elsif ($dbdver < 4.042) {
          $dbdhint = "<b>Caution:</b> Full UTF-8 support exists from DBD version 4.032, but installing DBD version 4.042 is highly suggested. ";
          $dbdupd  = 1;
      }
      else {
          $dbdhint = "Your DBD version fulfills UTF8 support, no need to update DBD.";
      }
  }

  $check .= "<html>";
  $check .= "<u><b>Result of version check</u></b><br><br>";
  $check .= "Used Perl version: $pv <br>";
  $check .= "Used DBI (Database independent interface) version: $dbi <br>";
  $check .= "Used DBD (Database driver) version $dbd <br>";

  ($err, $upd, $msg, $rec) = _DbLog_checkModVer($name);                            # DbLog Version

  $check .= "Used DbLog version: $hash->{HELPER}{VERSION} <br>$msg <br>";

  if ($err) {
      $check .= "Rating: ".$nok."<br>";
  }
  elsif ($upd) {
      $check .= "Rating: ".$warn."<br>";
  }
  else {
      $check .= "Rating: ".$ok."<br>";
  }

  $check .= "<b>Recommendation:</b> $rec <br>$dbdhint <br><br>";

  ### Configuration read check
  #######################################################################
  $check  .= "<u><b>Result of configuration read check</u></b><br><br>";
  my $cpst = configDBUsed() ? qq{configDB (don't forget upload configuration file if changed. Use "configdb filelist" and look for your configuration file.)} : "file";
  $check  .= "Connection parameter store type: $cpst <br>";

  ($err, @config) = FileRead($hash->{CONFIGURATION});

  if (!$err) {
      eval join("\n", @config);
      $rec  = "parameter: ";
      $rec .= "Connection -> could not read, "            if (!defined $dbconfig{connection});
      $rec .= "Connection -> ".$dbconfig{connection}.", " if (defined $dbconfig{connection});
      $rec .= "User -> could not read, "                  if (!defined $dbconfig{user});
      $rec .= "User -> ".$dbconfig{user}.", "             if (defined $dbconfig{user});
      $rec .= "Password -> could not read "               if (!defined $dbconfig{password});
      $rec .= "Password -> read o.k. "                    if (defined $dbconfig{password});
  }
  else {
      $rec = $err;
  }
  $check .= "Connection $rec <br>";
  $check .= defined $dbconfig{connection} && defined $dbconfig{user} && defined $dbconfig{password} ?
            "Rating: ".$ok."<br>" :
            "Rating: ".$nok."<br>";
  $check .= "<br>";

  ### Connection und Collation check
  #######################################################################
  my $st  = [gettimeofday];                                                                        # Startzeit
  my $dbh = _DbLog_getNewDBHandle ($hash) || return "Can't connect to database.";
  my $ct  = sprintf("%.4f", tv_interval($st));                                                     # Laufzeit ermitteln

  Log3 ($name, 4, "$name - Time required to establish the database connection: ".$ct);

  my (@ce,@se);
  my ($chutf8mod,$chutf8dat);

  if ($dbmodel =~ /MYSQL/) {
      ($err, @ce) = _DbLog_prepExecQueryOnly ($name, $dbh, qq(SHOW VARIABLES LIKE 'collation_connection'));      # character_set_connection
      $chutf8mod  = @ce ? uc($ce[1]) : "no result";

      ($err, @se) = _DbLog_prepExecQueryOnly ($name, $dbh, qq(SHOW VARIABLES LIKE 'collation_database'));        # character_set_database
      $chutf8dat  = @se ? uc($se[1]) : "no result";

      if ($chutf8dat =~ /utf8mb4/xsi && $chutf8mod eq $chutf8dat) {
          $rec = "settings o.k.";
      }
      elsif ($chutf8dat !~ /utf8mb4/xsi && $chutf8mod eq $chutf8dat) {
          $rec  = "The collation of the database should be changed to 'utf8mb4_bin' so that umlauts and all special characters can be stored. <br>";
          $rec .= "You can easy do that with the DbRep command <b>set &lt;DbRep-Device&gt; migrateCollation utf8mb4_bin</b>. <br>";
      }
      else {
          $rec = "Both encodings should be identical. You can adjust the usage of UTF8 connection by setting the UTF8 parameter in file '$hash->{CONFIGURATION}' to the right value. ";
      }

      if ($chutf8mod !~ /utf8/xsi) {
          $dbdhint = "";
      }
      else {
          $dbdhint .= " If you want use UTF8 database option, you must update DBD (Database driver) to at least version 4.032. " if($dbdupd);
      }

  }

  if ($dbmodel =~ /POSTGRESQL/) {
      ($err, @ce) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW CLIENT_ENCODING");
      $chutf8mod  = @ce ? uc($ce[0]) : "no result";

      ($err, @se) = _DbLog_prepExecQueryOnly ($name, $dbh, "select character_set_name from information_schema.character_sets");
      $chutf8dat  = @se ? uc($se[0]) : "no result";

      if($chutf8mod eq $chutf8dat) {
          $rec = "settings o.k.";
      }
      else {
          $rec = "This is only an information. PostgreSQL supports automatic character set conversion between server and client for certain character set combinations. The conversion information is stored in the pg_conversion system catalog. PostgreSQL comes with some predefined conversions.";
      }
  }

  if ($dbmodel =~ /SQLITE/) {
      ($err, @ce) = _DbLog_prepExecQueryOnly ($name, $dbh, "PRAGMA encoding");
      $chutf8dat  = @ce ? uc($ce[0]) : "no result";

      ($err, @se) = _DbLog_prepExecQueryOnly ($name, $dbh, "PRAGMA table_info($history)");
      $rec        = "This is only an information about text encoding used by the main database.";
  }

  $check .= "<u><b>Result of connection check</u></b><br><br>";

  if (!$err && @ce && @se) {
      $check .= "Connection to database $dbname successfully done. <br>";
      $check .= "The time required to establish the connection was $ct seconds. <br>";

      if ($ct > 5.0) {
          $check .= "Rating: ".$nok."<br>";
          $check .= "<b>Recommendation:</b> The time to establish a connection is much too long. There are connection problems that can massively affect the operation. <br><br>";
      }
      elsif ($ct > 1.5) {
          $check .= "Rating: ".$nok."<br>";
          $check .= "<b>Recommendation:</b> The time to establish a connection is too long. There are connection problems that can hinder operation. <br><br>";
      }
      elsif ($ct > 0.3) {
          $check .= "Rating: ".$warn."<br>";
          $check .= "<b>Recommendation:</b> The time to establish a connection is relatively long. This could be an indication of performance problems and should be taken into account. <br><br>";
      }
      else {
          $check .= "Rating: ".$ok."<br>";
          $check .= "<b>Recommendation:</b> settings o.k. <br><br>";
      }
  }

  if ($err || !@ce || !@se) {
      $check .= "Connection to database was not successful. <br>";
      $check .= "Rating: ".$ok."<br>";
      $check .= "<b>Recommendation:</b> Plese check logfile for further information. <br><br>";
      $check .= "</html>";
      return $check;
  }

  $check .= "<u><b>Result of collation check</u></b><br><br>";
  $check .= "Collation used by Client (connection): $chutf8mod <br>" if($dbmodel !~ /SQLITE/);
  $check .= "Collation used by DB $dbname: $chutf8dat <br>";
  $check .= $dbmodel =~ /SQLITE/       ? "Rating: ".$ok."<br>" :
            $rec =~ /settings\so.k./xs ? "Rating: ".$ok."<br>" :
            "Rating: ".$warn."<br>";
  $check .= "<b>Recommendation:</b> $rec $dbdhint <br><br>";

  ### Check Betriebsmodus
  #######################################################################
  my $mode = $hash->{MODE};
  my $im   = AttrVal($name,    'insertMode',   0);
  my $sfx  = AttrVal("global", 'language',  'EN');
  $sfx     = $sfx eq "EN" ? "" : "_$sfx";

  $check .= "<u><b>Result of insert mode check</u></b><br><br>";

  if (!$im) {
      $im     = "Array";
      $check .= "Insert mode of DbLog-device $name is: $im <br>";
      $check .= "Rating: ".$ok."<br>";
      $rec    = "settings o.k.";
  }
  else {
      $im     = "Sequential";
      $check .= "Insert mode of DbLog-device $name is: $im <br>";
      $check .= "Rating: ".$ok."<br>";
      $rec    = qq(Setting attribute "insertMode" to "0" (or delete it) may result a higher write performance in most cases. );
      $rec   .= "Feel free to try this mode.";
  }
  $check .= "<b>Recommendation:</b> $rec <br><br>";

  ### Check Plot Erstellungsmodus
  #######################################################################
  $check      .= "<u><b>Result of plot generation method check</u></b><br><br>";
  my @webdvs   = devspec2array("TYPE=FHEMWEB:FILTER=STATE=Initialized");
  my $forks    = 1;
  my $lpseb    = 1;
  my $noemb    = 1;
  my $wall     = "";

  for my $web (@webdvs) {
      my $pf  = AttrVal ($web, 'plotfork',    0);
      my $lps = AttrVal ($web, 'longpollSVG', 0);
      my $pe  = AttrVal ($web, 'plotEmbed',   0);

      $forks  = 0 if(!$pf);
      $lpseb  = 0 if($lps && $pe != 1);
      $noemb  = 0 if($pf && !$pe);

      if (!$pf || ($lps && $pe != 1) || ($pf && !$pe)) {
          $wall .= "<b>".$web.": plotfork=".$pf." / plotEmbed=".$pe." / longpollSVG=".$lps."</b><br>";
      }
      else {
          $wall .= $web.": plotfork=".$pf." / plotEmbed=".$pe." / longpollSVG=".$lps."<br>";
      }
  }

  if (!$forks || !$lpseb || !$noemb) {
      $rec = q{};

      if (!$forks) {
          $check .= "WARNING - at least one of your FHEMWEB devices has attribute 'plotfork = 1' not set. <br>";
      }

      if (!$lpseb) {
          $check .= "WARNING - at least one of your FHEMWEB devices has attribute 'longpollSVG = 1' but not 'plotEmbed = 1' set. <br>";
      }
      
      if (!$noemb) {
          $check .= "WARNING - at least one of your FHEMWEB devices has attribute 'plotEmbed' not set. <br>";
      }

      $check .= "<br>";
      $check .= $wall;
      $check .= "<br>";
      $check .= "Rating: ".$warn."<br>";

      if (!$forks) {
          $rec .= "You should set attribute 'plotfork = 1' in relevant devices. ".
                 "If this attribute is not set, blocking situations may occure when creating plots. <br>".
                 "(Note: Your system must have sufficient memory to handle parallel running Perl processes.) ".
                 "See also global attribute <a href=\"http://fhem.de/commandref.html#blockingCallMax\">blockingCallMax</a>. <br>"
      }

      if (!$noemb) {
          $rec .= "You should set attribute 'plotEmbed = (1 | 2)' in relevant devices. ".
                  "If this attribute is not set, blocking situations may occure when creating plots. <br>".
                  "Refer to <a href=\"http://fhem.de/commandref.html#FHEMWEB-attr-plotEmbed\">plotEmbed</a> for further information.<br>";
      }
      
      if (!$lpseb) {
          $rec .= "You have to set the attribute 'plotEmbed = 1' in FHEMWEB devices where 'longpollSVG' should be used. ".
                  "Refer to <a href=\"http://fhem.de/commandref.html#FHEMWEB-attr-longpollSVG\">longpollSVG</a> for further information.<br>";
      }
  }
  else {
      $check .= $wall;
      $check .= "<br>";
      $check .= "Rating: ".$ok."<br>";
      $rec    = "settings o.k.";
  }

  $check .= "<b>Recommendation:</b> $rec <br><br>";

  ### Check Spaltenbreite history
  #######################################################################
  my (@sr_dev,@sr_typ,@sr_evt,@sr_rdg,@sr_val,@sr_unt);
  my ($cdat_dev,$cdat_typ,$cdat_evt,$cdat_rdg,$cdat_val,$cdat_unt);
  my ($cmod_dev,$cmod_typ,$cmod_evt,$cmod_rdg,$cmod_val,$cmod_unt);

  if ($dbmodel =~ /MYSQL/) {
      ($err, @sr_dev) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW FIELDS FROM $history where FIELD='DEVICE'");
      ($err, @sr_typ) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW FIELDS FROM $history where FIELD='TYPE'");
      ($err, @sr_evt) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW FIELDS FROM $history where FIELD='EVENT'");
      ($err, @sr_rdg) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW FIELDS FROM $history where FIELD='READING'");
      ($err, @sr_val) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW FIELDS FROM $history where FIELD='VALUE'");
      ($err, @sr_unt) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW FIELDS FROM $history where FIELD='UNIT'");
  }

  if ($dbmodel =~ /POSTGRESQL/) {
      my $sch = AttrVal($name, "dbSchema", "");
      my $h   = "history";

      if ($sch) {
          ($err, @sr_dev) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$h' and table_schema='$sch' and column_name='device'");
          ($err, @sr_typ) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$h' and table_schema='$sch' and column_name='type'");
          ($err, @sr_evt) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$h' and table_schema='$sch' and column_name='event'");
          ($err, @sr_rdg) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$h' and table_schema='$sch' and column_name='reading'");
          ($err, @sr_val) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$h' and table_schema='$sch' and column_name='value'");
          ($err, @sr_unt) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$h' and table_schema='$sch' and column_name='unit'");
      }
      else {
          ($err, @sr_dev) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$h' and column_name='device'");
          ($err, @sr_typ) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$h' and column_name='type'");
          ($err, @sr_evt) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$h' and column_name='event'");
          ($err, @sr_rdg) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$h' and column_name='reading'");
          ($err, @sr_val) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$h' and column_name='value'");
          ($err, @sr_unt) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$h' and column_name='unit'");
      }
  }

  if ($dbmodel =~ /SQLITE/) {
      my @dev;
      ($err, @dev) = _DbLog_prepExecQueryOnly ($name, $dbh, "SELECT sql FROM sqlite_master WHERE name = '$history'");

      $cdat_dev   = $dev[0] // "no result";
      $cdat_typ   = $cdat_evt = $cdat_rdg = $cdat_val = $cdat_unt = $cdat_dev;
      ($cdat_dev) = $cdat_dev =~ /DEVICE.varchar\(([\d]+)\)/x;
      ($cdat_typ) = $cdat_typ =~ /TYPE.varchar\(([\d]+)\)/x;
      ($cdat_evt) = $cdat_evt =~ /EVENT.varchar\(([\d]+)\)/x;
      ($cdat_rdg) = $cdat_rdg =~ /READING.varchar\(([\d]+)\)/x;
      ($cdat_val) = $cdat_val =~ /VALUE.varchar\(([\d]+)\)/x;
      ($cdat_unt) = $cdat_unt =~ /UNIT.varchar\(([\d]+)\)/x;
  }

  if ($dbmodel !~ /SQLITE/)  {
      $cdat_dev = @sr_dev ? ($sr_dev[1]) : "no result";
      $cdat_dev =~ tr/varchar\(|\)//d if($cdat_dev ne "no result");
      $cdat_typ = @sr_typ ? ($sr_typ[1]) : "no result";
      $cdat_typ =~ tr/varchar\(|\)//d if($cdat_typ ne "no result");
      $cdat_evt = @sr_evt ? ($sr_evt[1]) : "no result";
      $cdat_evt =~ tr/varchar\(|\)//d if($cdat_evt ne "no result");
      $cdat_rdg = @sr_rdg ? ($sr_rdg[1]) : "no result";
      $cdat_rdg =~ tr/varchar\(|\)//d if($cdat_rdg ne "no result");
      $cdat_val = @sr_val ? ($sr_val[1]) : "no result";
      $cdat_val =~ tr/varchar\(|\)//d if($cdat_val ne "no result");
      $cdat_unt = @sr_unt ? ($sr_unt[1]) : "no result";
      $cdat_unt =~ tr/varchar\(|\)//d if($cdat_unt ne "no result");
  }

  $cmod_dev = $hash->{HELPER}{DEVICECOL};
  $cmod_typ = $hash->{HELPER}{TYPECOL};
  $cmod_evt = $hash->{HELPER}{EVENTCOL};
  $cmod_rdg = $hash->{HELPER}{READINGCOL};
  $cmod_val = $hash->{HELPER}{VALUECOL};
  $cmod_unt = $hash->{HELPER}{UNITCOL};

  if ($cdat_dev >= $cmod_dev && $cdat_typ >= $cmod_typ && $cdat_evt >= $cmod_evt && $cdat_rdg >= $cmod_rdg && $cdat_val >= $cmod_val && $cdat_unt >= $cmod_unt) {
      $rec = "settings o.k.";
  }
  else {
      if ($dbmodel !~ /SQLITE/)  {
          $rec  = "The relation between column width in table $history and the field width used in device $name don't meet the requirements. ";
          $rec .= "Please make sure that the width of database field definition is equal or larger than the field width used by the module. Compare the given results.<br>";
          $rec .= "Currently the default values for field width are: <br><br>";
          $rec .= "DEVICE: $DbLog_columns{DEVICE} <br>";
          $rec .= "TYPE: $DbLog_columns{TYPE} <br>";
          $rec .= "EVENT: $DbLog_columns{EVENT} <br>";
          $rec .= "READING: $DbLog_columns{READING} <br>";
          $rec .= "VALUE: $DbLog_columns{VALUE} <br>";
          $rec .= "UNIT: $DbLog_columns{UNIT} <br><br>";
          $rec .= "You can change the column width in database by a statement like <b>'alter table $history modify VALUE varchar(128);</b>' (example for changing field 'VALUE'). ";
          $rec .= "You can do it for example by executing 'sqlCmd' in DbRep or in a SQL-Editor of your choice. (switch $name to asynchron mode for non-blocking). <br>";
          $rec .= "Alternatively the field width used by $name can be adjusted by setting attributes 'colEvent', 'colReading', 'colType', 'colValue'. (pls. refer to commandref)";
      }
      else {
          $rec  = "WARNING - The relation between column width in table $history and the field width used by device $name should be equal but it differs.";
          $rec .= "The field width used by $name can be adjusted by setting attributes 'colEvent', 'colReading', 'colType', 'colValue'. (pls. refer to commandref)";
          $rec .= "Because you use SQLite this is only a warning. Normally the database can handle these differences. ";
      }
  }

  $check .= "<u><b>Result of table '$history' check</u></b><br><br>";
  $check .= "Column width set in table $history: 'DEVICE' = $cdat_dev, 'TYPE' = $cdat_typ, 'EVENT' = $cdat_evt, 'READING' = $cdat_rdg, 'VALUE' = $cdat_val, 'UNIT' = $cdat_unt <br>";
  $check .= "Column width used by device $name: 'DEVICE' = $cmod_dev, 'TYPE' = $cmod_typ, 'EVENT' = $cmod_evt, 'READING' = $cmod_rdg, 'VALUE' = $cmod_val, 'UNIT' = $cmod_unt <br>";
  $check .= $rec =~ /WARNING/xs                                           ? "Rating: ".$warn."<br>" :
            $rec =~ /make\ssure\sthat\sthe\swidth\sof\sdatabase\sfield/xs ? "Rating: ".$nok."<br>"  :
            "Rating: ".$ok."<br>";
  $check .= "<b>Recommendation:</b> $rec <br><br>";

  ### Check Spaltenbreite current
  #######################################################################
  if ($dbmodel =~ /MYSQL/) {
      ($err, @sr_dev) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW FIELDS FROM $current where FIELD='DEVICE'");
      ($err, @sr_typ) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW FIELDS FROM $current where FIELD='TYPE'");
      ($err, @sr_evt) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW FIELDS FROM $current where FIELD='EVENT'");
      ($err, @sr_rdg) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW FIELDS FROM $current where FIELD='READING'");
      ($err, @sr_val) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW FIELDS FROM $current where FIELD='VALUE'");
      ($err, @sr_unt) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW FIELDS FROM $current where FIELD='UNIT'");
  }

  if ($dbmodel =~ /POSTGRESQL/) {
      my $sch = AttrVal($name, "dbSchema", "");
      my $c   = "current";

      if ($sch) {
          ($err, @sr_dev) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$c' and table_schema='$sch' and column_name='device'");
          ($err, @sr_typ) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$c' and table_schema='$sch' and column_name='type'");
          ($err, @sr_evt) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$c' and table_schema='$sch' and column_name='event'");
          ($err, @sr_rdg) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$c' and table_schema='$sch' and column_name='reading'");
          ($err, @sr_val) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$c' and table_schema='$sch' and column_name='value'");
          ($err, @sr_unt) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$c' and table_schema='$sch' and column_name='unit'");
      }
      else {
          ($err, @sr_dev) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$c' and column_name='device'");
          ($err, @sr_typ) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$c' and column_name='type'");
          ($err, @sr_evt) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$c' and column_name='event'");
          ($err, @sr_rdg) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$c' and column_name='reading'");
          ($err, @sr_val) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$c' and column_name='value'");
          ($err, @sr_unt) = _DbLog_prepExecQueryOnly ($name, $dbh, "select column_name,character_maximum_length from information_schema.columns where table_name='$c' and column_name='unit'");
      }
  }

  if ($dbmodel =~ /SQLITE/) {
      my @dev;
      ($err, @dev) = _DbLog_prepExecQueryOnly ($name, $dbh, "SELECT sql FROM sqlite_master WHERE name = '$current'");

      $cdat_dev   = $dev[0] // "no result";
      $cdat_typ   = $cdat_evt = $cdat_rdg = $cdat_val = $cdat_unt = $cdat_dev;
      ($cdat_dev) = $cdat_dev =~ /DEVICE.varchar\(([\d]+)\)/x;
      ($cdat_typ) = $cdat_typ =~ /TYPE.varchar\(([\d]+)\)/x;
      ($cdat_evt) = $cdat_evt =~ /EVENT.varchar\(([\d]+)\)/x;
      ($cdat_rdg) = $cdat_rdg =~ /READING.varchar\(([\d]+)\)/x;
      ($cdat_val) = $cdat_val =~ /VALUE.varchar\(([\d]+)\)/x;
      ($cdat_unt) = $cdat_unt =~ /UNIT.varchar\(([\d]+)\)/x;
  }

  if ($dbmodel !~ /SQLITE/)  {
      $cdat_dev = @sr_dev ? ($sr_dev[1]) : "no result";
      $cdat_dev =~ tr/varchar\(|\)//d if($cdat_dev ne "no result");
      $cdat_typ = @sr_typ ? ($sr_typ[1]) : "no result";
      $cdat_typ =~ tr/varchar\(|\)//d if($cdat_typ ne "no result");
      $cdat_evt = @sr_evt ? ($sr_evt[1]) : "no result";
      $cdat_evt =~ tr/varchar\(|\)//d if($cdat_evt ne "no result");
      $cdat_rdg = @sr_rdg ? ($sr_rdg[1]) : "no result";
      $cdat_rdg =~ tr/varchar\(|\)//d if($cdat_rdg ne "no result");
      $cdat_val = @sr_val ? ($sr_val[1]) : "no result";
      $cdat_val =~ tr/varchar\(|\)//d if($cdat_val ne "no result");
      $cdat_unt = @sr_unt ? ($sr_unt[1]) : "no result";
      $cdat_unt =~ tr/varchar\(|\)//d if($cdat_unt ne "no result");
  }

  $cmod_dev = $hash->{HELPER}{DEVICECOL};
  $cmod_typ = $hash->{HELPER}{TYPECOL};
  $cmod_evt = $hash->{HELPER}{EVENTCOL};
  $cmod_rdg = $hash->{HELPER}{READINGCOL};
  $cmod_val = $hash->{HELPER}{VALUECOL};
  $cmod_unt = $hash->{HELPER}{UNITCOL};

  if ($cdat_dev >= $cmod_dev && $cdat_typ >= $cmod_typ && $cdat_evt >= $cmod_evt && $cdat_rdg >= $cmod_rdg && $cdat_val >= $cmod_val && $cdat_unt >= $cmod_unt) {
      $rec = "settings o.k.";
  }
  else {
      if ($dbmodel !~ /SQLITE/)  {
          $rec  = "The relation between column width in table $current and the field width used in device $name don't meet the requirements. ";
          $rec .= "Please make sure that the width of database field definition is equal or larger than the field width used by the module. Compare the given results.<br>";
          $rec .= "Currently the default values for field width are: <br><br>";
          $rec .= "DEVICE: $DbLog_columns{DEVICE} <br>";
          $rec .= "TYPE: $DbLog_columns{TYPE} <br>";
          $rec .= "EVENT: $DbLog_columns{EVENT} <br>";
          $rec .= "READING: $DbLog_columns{READING} <br>";
          $rec .= "VALUE: $DbLog_columns{VALUE} <br>";
          $rec .= "UNIT: $DbLog_columns{UNIT} <br><br>";
          $rec .= "You can change the column width in database by a statement like <b>'alter table $current modify VALUE varchar(128);</b>' (example for changing field 'VALUE'). ";
          $rec .= "You can do it for example by executing 'sqlCmd' in DbRep or in a SQL-Editor of your choice. (switch $name to asynchron mode for non-blocking). <br>";
          $rec .= "Alternatively the field width used by $name can be adjusted by setting attributes 'colEvent', 'colReading', 'colType', 'colValue'. (pls. refer to commandref)";
      }
      else {
          $rec  = "WARNING - The relation between column width in table $current and the field width used by device $name should be equal but it differs. ";
          $rec .= "The field width used by $name can be adjusted by setting attributes 'colEvent', 'colReading', 'colType', 'colValue'. (pls. refer to commandref)";
          $rec .= "Because you use SQLite this is only a warning. Normally the database can handle these differences. ";
      }
  }

  $check .= "<u><b>Result of table '$current' check</u></b><br><br>";
  $check .= "Column width set in table $current: 'DEVICE' = $cdat_dev, 'TYPE' = $cdat_typ, 'EVENT' = $cdat_evt, 'READING' = $cdat_rdg, 'VALUE' = $cdat_val, 'UNIT' = $cdat_unt <br>";
  $check .= "Column width used by device $name: 'DEVICE' = $cmod_dev, 'TYPE' = $cmod_typ, 'EVENT' = $cmod_evt, 'READING' = $cmod_rdg, 'VALUE' = $cmod_val, 'UNIT' = $cmod_unt <br>";
  $check .= $rec =~ /WARNING/xs                                           ? "Rating: ".$warn."<br>" :
            $rec =~ /make\ssure\sthat\sthe\swidth\sof\sdatabase\sfield/xs ? "Rating: ".$nok."<br>"  :
            "Rating: ".$ok."<br>";
  $check .= "<b>Recommendation:</b> $rec <br><br>";

  ### Check Vorhandensein Search_Idx mit den empfohlenen Spalten
  #######################################################################
  my (@six,@six_dev,@six_rdg,@six_tsp);
  my ($idef,$idef_dev,$idef_rdg,$idef_tsp);
  $check .= "<u><b>Result of check 'Search_Idx' availability</u></b><br><br>";

  if ($dbmodel =~ /MYSQL/) {
      ($err, @six) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW INDEX FROM $history where Key_name='Search_Idx'");

      if (!@six) {
          $check .= "The index 'Search_Idx' is missing. <br>";
          $rec    = "You can create the index by the DbRep command <b>set &lt;DbRep-Device&gt; index recreate_Search_Idx</b> <br>";
          $rec   .= "Depending on your database size this command may running a long time. <br>";
          $rec   .= "Please make sure the device '$name' is operating in asynchronous mode to avoid FHEM from blocking when creating the index. <br>";
          $rec   .= "<b>Note:</b> If you have just created another index which covers the same fields and order as suggested (e.g. a primary key) you don't need to create the 'Search_Idx' as well ! <br>";
      }
      else {
          ($err, @six_dev) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW INDEX FROM $history where Key_name='Search_Idx' and Column_name='DEVICE'");
          ($err, @six_rdg) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW INDEX FROM $history where Key_name='Search_Idx' and Column_name='READING'");
          ($err, @six_tsp) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW INDEX FROM $history where Key_name='Search_Idx' and Column_name='TIMESTAMP'");

          if (@six_dev && @six_rdg && @six_tsp) {
              $check .= "Index 'Search_Idx' exists and contains recommended fields 'DEVICE', 'TIMESTAMP', 'READING'. <br>";
              $rec    = "settings o.k.";
          }
          else {
              $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'DEVICE'. <br>"    if (!@six_dev);
              $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'READING'. <br>"   if (!@six_rdg);
              $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'TIMESTAMP'. <br>" if (!@six_tsp);
              $rec    = "The index should contain the fields 'DEVICE', 'TIMESTAMP', 'READING'. ";
              $rec   .= "You can change the index by executing e.g. <br>";
              $rec   .= "<b>'ALTER TABLE `$history` DROP INDEX `Search_Idx`, ADD INDEX `Search_Idx` (`DEVICE`, `READING`, `TIMESTAMP`) USING BTREE;'</b> <br>";
              $rec   .= "The DbRep command <b>set &lt;DbRep-Device&gt; index recreate_Search_Idx</b> is doing the same for you. <br>";
              $rec   .= "Depending on your database size this command may running a long time. <br>";
          }
      }
  }

  if ($dbmodel =~ /POSTGRESQL/) {
      ($err, @six) = _DbLog_prepExecQueryOnly ($name, $dbh, "SELECT * FROM pg_indexes WHERE tablename='$history' and indexname ='Search_Idx'");

      if (!@six) {
          $check .= "The index 'Search_Idx' is missing. <br>";
          $rec    = "You can create the index by the DbRep command <b>set &lt;DbRep-Device&gt; index recreate_Search_Idx</b> <br>";
          $rec   .= "Depending on your database size this command may running a long time. <br>";
          $rec   .= "Please make sure the device '$name' is operating in asynchronous mode to avoid FHEM from blocking when creating the index. <br>";
          $rec   .= "<b>Note:</b> If you have just created another index which covers the same fields and order as suggested (e.g. a primary key) you don't need to create the 'Search_Idx' as well ! <br>";
      }
      else {
          $idef     = $six[4];
          $idef_dev = 1 if($idef =~ /device/);
          $idef_rdg = 1 if($idef =~ /reading/);
          $idef_tsp = 1 if($idef =~ /timestamp/);

          if ($idef_dev && $idef_rdg && $idef_tsp) {
              $check .= "Index 'Search_Idx' exists and contains recommended fields 'DEVICE', 'READING', 'TIMESTAMP'. <br>";
              $rec    = "settings o.k.";
          }
          else {
              $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'DEVICE'. <br>"    if (!$idef_dev);
              $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'READING'. <br>"   if (!$idef_rdg);
              $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'TIMESTAMP'. <br>" if (!$idef_tsp);
              $rec    = "The index should contain the fields 'DEVICE', 'READING', 'TIMESTAMP'. ";
              $rec   .= "You can change the index by executing e.g. <br>";
              $rec   .= "the DbRep command <b>set &lt;DbRep-Device&gt; index recreate_Search_Idx</b> <br>";
              $rec   .= "Depending on your database size this command may running a long time. <br>";
          }
      }
  }

  if ($dbmodel =~ /SQLITE/) {
      ($err, @six) = _DbLog_prepExecQueryOnly ($name, $dbh, "SELECT name,sql FROM sqlite_master WHERE type='index' AND name='Search_Idx'");

      if (!$six[0]) {
          $check .= "The index 'Search_Idx' is missing. <br>";
          $rec    = "You can create the index by the DbRep command <b>set &lt;DbRep-Device&gt; index recreate_Search_Idx</b> <br>";
          $rec   .= "Depending on your database size this command may running a long time. <br>";
          $rec   .= "Please make sure the device '$name' is operating in asynchronous mode to avoid FHEM from blocking when creating the index. <br>";
          $rec   .= "<b>Note:</b> If you have just created another index which covers the same fields and order as suggested (e.g. a primary key) you don't need to create the 'Search_Idx' as well ! <br>";
      }
      else {
          $idef     = $six[1];
          $idef_dev = 1 if(lc($idef) =~ /device/);
          $idef_rdg = 1 if(lc($idef) =~ /reading/);
          $idef_tsp = 1 if(lc($idef) =~ /timestamp/);

          if ($idef_dev && $idef_rdg && $idef_tsp) {
              $check .= "Index 'Search_Idx' exists and contains recommended fields 'DEVICE', 'READING', 'TIMESTAMP'. <br>";
              $rec    = "settings o.k.";
          }
          else {
              $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'DEVICE'. <br>"    if (!$idef_dev);
              $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'READING'. <br>"   if (!$idef_rdg);
              $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'TIMESTAMP'. <br>" if (!$idef_tsp);
              $rec    = "The index should contain the fields 'DEVICE', 'READING', 'TIMESTAMP'. ";
              $rec   .= "You can change the index by executing e.g. <br>";
              $rec   .= "the DbRep command <b>set &lt;DbRep-Device&gt; index recreate_Search_Idx</b> <br>";
              $rec   .= "Depending on your database size this command may running a long time. <br>";
          }
      }
  }

  $check .= !@six || !$six[0]          ? "Rating: ".$nok."<br>" :
            $rec =~ /settings\so.k./xs ? "Rating: ".$ok."<br>"  :
            "Rating: ".$warn."<br>";

  $check .= "<b>Recommendation:</b> $rec <br><br>";

  ### Check Index Report_Idx für DbRep-Device falls DbRep verwendet wird
  #######################################################################
  my (@dix,@dix_rdg,@dix_tsp,$irep_rdg,$irep_tsp,$irep);
  my $isused = 0;
  my @repdvs = devspec2array("TYPE=DbRep");
  $check    .= "<u><b>Result of check 'Report_Idx' availability for DbRep-devices</u></b><br><br>";

  for my $dbrp (@repdvs) {
      if (!$defs{$dbrp}) {
          Log3 ($name, 2, "$name - Device '$dbrp' found by configCheck doesn't exist !");
          next;
      }

      if ($defs{$dbrp}->{DEF} eq $name) {                                      # DbRep Device verwendet aktuelles DbLog-Device
          Log3 ($name, 5, "$name - DbRep-Device '$dbrp' uses $name.");
          $isused = 1;
      }
  }

  if ($isused) {
      if ($dbmodel =~ /MYSQL/) {
          ($err, @dix) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW INDEX FROM $history where Key_name='Report_Idx'");

          if (!@dix) {
              $check .= "At least one DbRep-device assigned to $name is used, but the recommended index 'Report_Idx' is missing. <br>";
              $rec    = "You can create the index by the DbRep command <b>set &lt;DbRep-Device&gt; index recreate_Report_Idx</b> <br>";
              $rec   .= "Depending on your database size this command may running a long time. <br>";
              $rec   .= "Please make sure the device '$name' is operating in asynchronous mode to avoid FHEM from blocking when creating the index. <br>";
              $rec   .= "<b>Note:</b> If you have just created another index which covers the same fields and order as suggested (e.g. a primary key) you don't need to create the 'Report_Idx' as well ! <br>";
          }
          else {
              ($err, @dix_rdg) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW INDEX FROM $history where Key_name='Report_Idx' and Column_name='READING'");
              ($err, @dix_tsp) = _DbLog_prepExecQueryOnly ($name, $dbh, "SHOW INDEX FROM $history where Key_name='Report_Idx' and Column_name='TIMESTAMP'");

              if (@dix_rdg && @dix_tsp) {
                  $check .= "At least one DbRep-device assigned to $name is used. ";
                  $check .= "Index 'Report_Idx' exists and contains recommended fields 'TIMESTAMP', 'READING'. <br>";
                  $rec    = "settings o.k.";
              }
              else {
                  $check .= "You use at least one DbRep-device assigned to $name. ";
                  $check .= "Index 'Report_Idx' exists but doesn't contain recommended field 'READING'. <br>" if (!@dix_rdg);
                  $check .= "Index 'Report_Idx' exists but doesn't contain recommended field 'TIMESTAMP'. <br>" if (!@dix_tsp);
                  $rec    = "The index should contain the fields 'TIMESTAMP', 'READING'. ";
                  $rec   .= "You can change the index by executing e.g. <br>";
                  $rec   .= "the DbRep command <b>set &lt;DbRep-Device&gt; index recreate_Report_Idx</b> <br>";
                  $rec   .= "Depending on your database size this command may running a long time. <br>";
              }
          }
      }

      if ($dbmodel =~ /POSTGRESQL/) {
          ($err, @dix) = _DbLog_prepExecQueryOnly ($name, $dbh, "SELECT * FROM pg_indexes WHERE tablename='$history' and indexname ='Report_Idx'");

          if (!@dix) {
              $check .= "You use at least one DbRep-device assigned to $name, but the recommended index 'Report_Idx' is missing. <br>";
              $rec    = "You can create the index by the DbRep command <b>set &lt;DbRep-Device&gt; index recreate_Report_Idx</b> <br>";
              $rec   .= "Depending on your database size this command may running a long time. <br>";
              $rec   .= "Please make sure the device '$name' is operating in asynchronous mode to avoid FHEM from blocking when creating the index. <br>";
              $rec   .= "<b>Note:</b> If you have just created another index which covers the same fields and order as suggested (e.g. a primary key) you don't need to create the 'Report_Idx' as well ! <br>";
          }
          else {
              $irep     = $dix[4];
              $irep_rdg = 1 if($irep =~ /reading/);
              $irep_tsp = 1 if($irep =~ /timestamp/);

              if ($irep_rdg && $irep_tsp) {
                  $check .= "Index 'Report_Idx' exists and contains recommended fields 'TIMESTAMP', 'READING'. <br>";
                  $rec    = "settings o.k.";
              }
              else {
                  $check .= "Index 'Report_Idx' exists but doesn't contain recommended field 'READING'. <br>" if (!$irep_rdg);
                  $check .= "Index 'Report_Idx' exists but doesn't contain recommended field 'TIMESTAMP'. <br>" if (!$irep_tsp);
                  $rec    = "The index should contain the fields 'TIMESTAMP', 'READING'. ";
                  $rec   .= "You can change the index by executing e.g. <br>";
                  $rec   .= "the DbRep command <b>set &lt;DbRep-Device&gt; index recreate_Report_Idx</b> <br>";
                  $rec   .= "Depending on your database size this command may running a long time. <br>";
              }
          }
      }

      if ($dbmodel =~ /SQLITE/) {
          ($err, @dix) = _DbLog_prepExecQueryOnly ($name, $dbh, "SELECT name,sql FROM sqlite_master WHERE type='index' AND name='Report_Idx'");

          if (!$dix[0]) {
              $check .= "The index 'Report_Idx' is missing. <br>";
              $rec    = "You can create the index by the DbRep command <b>set &lt;DbRep-Device&gt; index recreate_Report_Idx</b> <br>";
              $rec   .= "Depending on your database size this command may running a long time. <br>";
              $rec   .= "Please make sure the device '$name' is operating in asynchronous mode to avoid FHEM from blocking when creating the index. <br>";
              $rec   .= "<b>Note:</b> If you have just created another index which covers the same fields and order as suggested (e.g. a primary key) you don't need to create the 'Search_Idx' as well ! <br>";
          }
          else {
              $irep     = $dix[1];
              $irep_rdg = 1 if(lc($irep) =~ /reading/);
              $irep_tsp = 1 if(lc($irep) =~ /timestamp/);

              if ($irep_rdg && $irep_tsp) {
                  $check .= "Index 'Report_Idx' exists and contains recommended fields 'TIMESTAMP', 'READING'. <br>";
                  $rec    = "settings o.k.";
              }
              else {
                  $check .= "Index 'Report_Idx' exists but doesn't contain recommended field 'READING'. <br>" if (!$irep_rdg);
                  $check .= "Index 'Report_Idx' exists but doesn't contain recommended field 'TIMESTAMP'. <br>" if (!$irep_tsp);
                  $rec    = "The index should contain the fields 'TIMESTAMP', 'READING'. ";
                  $rec   .= "You can change the index by executing e.g. <br>";
                  $rec   .= "the DbRep command <b>set &lt;DbRep-Device&gt; index recreate_Report_Idx</b> <br>";
                  $rec   .= "Depending on your database size this command may running a long time. <br>";
              }
          }
      }

  }
  else {
      $check .= "No DbRep-device assigned to $name is used. Hence an index for DbRep isn't needed. <br>";
      $rec    = "settings o.k.";
  }

  $check .= !@dix || !$dix[0]          ? "Rating: ".$warn."<br>" :
            $rec =~ /settings\so.k./xs ? "Rating: ".$ok."<br>"  :
            "Rating: ".$warn."<br>";

  $check .= "<b>Recommendation:</b> $rec <br><br>";
  $check .= "</html>";

  __DbLog_SBP_disconnectOnly ($name, $dbh);

return $check;
}

############################################################################################################
#                  check Modul Aktualität fhem.de <-> local
#  return:  0|1 (Err-State), 0-kein Update nötig od. feststellbar/ 1-Update nötig, Message, Recommendation
############################################################################################################
sub _DbLog_checkModVer {
  my $name = shift;
  my $src  = "https://fhem.de/fhemupdate/controls_fhem.txt";

  my $msg  = q{};
  my $rec  = q{};

  if($src !~ m,^(.*)/([^/]*)$,) {
      $msg = "Cannot parse $src, probably not a valid http control file";
      $rec = "Please inform the DbLog Maintainer about the Error Message.";
      return (1, 0, $msg, $rec);
  }

  my $basePath     = $1;
  my $ctrlFileName = $2;

  my ($err, $remCtrlFile) = __DbLog_updGetUrl($name, $src);

  if ($err) {
      $msg = "Check of SVN DbLog version not possible: ".$err;
      $rec = "Try to execute the configCheck later again. Inform the DbLog Maintainer if it seems to be a permanent problem.";
      return (1, 0, $msg, $rec);
  }

  if (!$remCtrlFile) {
      $msg = "Check of SVN DbLog version not possible: no valid SVN control file available.";
      $rec = "Try to execute the configCheck later again. Inform the DbLog Maintainer if it seems to be a permanent problem.";
      return (1, 0, $msg, $rec);
  }

  my @remList = split /\R/, $remCtrlFile;
  my $root    = $attr{global}{modpath};

  Log3 ($name, 4, "$name - configCheck: Got SVN $ctrlFileName with ".int(@remList)." entries.");

  open (FD, "$root/FHEM/$ctrlFileName") or do { $msg = "Automatic check of SVN DbLog version not possible: $!";
                                                $rec = "Try to solve the problem that has occurred. Compare your local DbLog version with the public version manually.";
                                                return (1, 0, $msg, $rec);
                                              };

  my @locList = map { $_ =~ s/[\r\n]//; $_ } <FD>;
  close(FD);

  Log3 ($name, 4, "$name - configCheck: Got local $ctrlFileName with ".int(@locList)." entries.");

  my %lh;

  for my $l (@locList) {
      my @l = split " ", $l, 4;
      next if($l[0] ne "UPD" || $l[3] !~ /93_DbLog/);
      $lh{$l[3]}{TS}  = $l[1];
      $lh{$l[3]}{LEN} = $l[2];

      Log3 ($name, 4, "$name - configCheck: local version from last update - creation time: ".$lh{$l[3]}{TS}." - bytes: ".$lh{$l[3]}{LEN});
  }

  for my $rem (@remList) {
      my @r = split " ", $rem, 4;
      next if($r[0] ne "UPD" || $r[3] !~ /93_DbLog/);

      my $fName  = $r[3];
      my $fPath  = "$root/$fName";
      my $fileOk = ($lh{$fName} && $lh{$fName}{TS} eq $r[1] && $lh{$fName}{LEN} eq $r[2]);

      if (!$fileOk) {
          Log3 ($name, 4, "$name - configCheck: New SVN version of $fName found - creation time: $r[1] ($r[2] Bytes)");

          $msg = "A new DbLog version is available (creation time: $r[1], size: $r[2] bytes)";
          $rec = "You should update FHEM to get the recent DbLog version from repository.";
          return (0, 1, $msg, $rec);
      }

      my $sz = -s $fPath;

      if ($fileOk && defined($sz) && $sz ne $r[2]) {
          Log3 ($name, 4, "$name - configCheck: SVN version of $fName creation time: $r[1] ($r[2] Bytes) differs from local one ($sz Bytes)");

          $msg = "Your local DbLog module is modified. The SVN version of $fName has creation time: $r[1] ($r[2] Bytes)";
          $rec = "You should update FHEM to get the recent DbLog version from repository.";
          return (0, 1, $msg, $rec);
      }

      last;
  }

  $msg = "Your local DbLog module is up to date.";
  $rec = "Update of DbLog is not needed.";

return (0, 0, $msg, $rec);
}

###################################
sub __DbLog_updGetUrl {
  my ($name,$url) = @_;

  my %upd_connecthash;

  $url                        =~ s/%/%25/g;
  $upd_connecthash{url}       = $url;
  $upd_connecthash{keepalive} = $url =~ m/localUpdate/ ? 0 : 1;                                   # Forum #49798

  my ($err, $data) = HttpUtils_BlockingGet(\%upd_connecthash);

  if($err) {
      Log3 ($name, 1, "$name - configCheck: ERROR while connecting to fhem.de:  $err");

      return ($err, "");
  }

  if(!$data) {
      Log3 ($name, 1, "$name - configCheck: ERROR $url: empty file received");

      $err = 1;
      return ($err, "");
  }

return ("", $data);
}

#########################################################################################
#
# Addlog - einfügen des Readingwertes eines gegebenen Devices
#
#########################################################################################
sub DbLog_AddLog {
  my $paref     = shift;

  my $hash      = $paref->{hash};
  my $devrdspec = $paref->{devrdspec};
  my $value     = $paref->{value};
  my $nce       = $paref->{nce};
  my $cn        = $paref->{cn};

  my $name      = $hash->{NAME};
  my $async     = AttrVal ($name, 'asyncMode',   0);
  my $value_fn  = AttrVal ($name, 'valueFn',    '');
  my $ce        = AttrVal ($name, 'cacheEvents', 0);

  my ($dev_type,$dev_name,$dev_reading,$read_val,$event,$ut);
  my $memcount;
  my $ts;

  return if(IsDisabled($name) || !$hash->{HELPER}{COLSET} || $init_done != 1);

  if( $value_fn =~ m/^\s*(\{.*\})\s*$/s ) {                                     # Funktion aus Attr valueFn validieren
      $value_fn = $1;
  }
  else {
      $value_fn = '';
  }

  my $now     = gettimeofday();
  my $rdspec  = (split ":",$devrdspec)[-1];
  my @dc      = split(":",$devrdspec);
  pop @dc;
  my $devspec = join(':',@dc);
  my @exdvs   = devspec2array($devspec);

  Log3 ($name, 4, "$name - Addlog known devices by devspec: @exdvs");

  for (@exdvs) {
      $dev_name = $_;

      if(!$defs{$dev_name}) {
          Log3 ($name, 2, "$name - Device '$dev_name' used by addLog doesn't exist !");
          next;
      }

      my $r            = $defs{$dev_name}{READINGS};
      my $DbLogExclude = AttrVal ($dev_name, "DbLogExclude", undef);
      my $DbLogInclude = AttrVal ($dev_name, "DbLogInclude", undef);
      my $found        = 0;
      my @exrds;

      for my $rd (sort keys %{$r}) {                                          # jedes Reading des Devices auswerten
           my $do = 1;
           $found = 1 if($rd =~ m/^$rdspec$/);                                # Reading gefunden

           if($DbLogExclude && !$nce) {
               my @v1 = DbLog_attrLong2Array ($DbLogExclude, ',');

               for (my $i = 0; $i < int(@v1); $i++) {
                   my @v2 = split /:/, $v1[$i];                               # MinInterval wegschneiden, Bsp: "(temperature|humidity):600,battery:3600"

                   if($rd =~ m,^$v2[0]$,) {                                   # Reading matcht $DbLogExclude -> ausschließen vom addLog
                       $do = 0;

                       if($DbLogInclude) {
                           my @v3 = DbLog_attrLong2Array ($DbLogInclude, ',');

                           for (my $i = 0; $i < int(@v3); $i++) {
                               my @v4 = split /:/, $v3[$i];
                               $do    = 1 if($rd =~ m,^$v4[0]$,);             # Reading matcht $DbLogInclude -> wieder in addLog einschließen
                           }
                       }

                       Log3 ($name, 2, "$name - Device: \"$dev_name\", reading: \"$v2[0]\" excluded by attribute DbLogExclude from addLog !") if($do == 0 && $rd =~ m/^$rdspec$/);
                   }
               }
           }

           next if(!$do);
           push @exrds, $rd if($rd =~ m/^$rdspec$/);
      }

      Log3 $name, 4, "$name - Readings extracted from Regex: @exrds";

      if(!$found) {
          if(goodReadingName($rdspec) && defined($value)) {
              Log3 $name, 3, "$name - addLog WARNING - Device: '$dev_name' -> Reading '$rdspec' not found - add it as new reading.";
              push @exrds,$rdspec;
          }
          elsif (goodReadingName($rdspec) && !defined($value)) {
              Log3 $name, 2, "$name - addLog WARNING - Device: '$dev_name' -> new Reading '$rdspec' has no value - can't add it !";
          }
          else {
              Log3 $name, 2, "$name - addLog WARNING - Device: '$dev_name' -> Readingname '$rdspec' is no valid or regexp - can't add regexp as new reading !";
          }
      }

      no warnings 'uninitialized';

      for (@exrds) {
          $dev_reading = $_;
          $read_val    = $value ne '' ? $value : ReadingsVal($dev_name, $dev_reading, '');
          $dev_type    = uc($defs{$dev_name}{TYPE});
          $event       = $dev_reading.": ".$read_val;                                                        # dummy-Event zusammenstellen

          my @r        = _DbLog_ParseEvent($name, $dev_name, $dev_type, $event);                             # den zusammengestellten Event parsen lassen (evtl. Unit zuweisen)
          $dev_reading = $r[0];
          $read_val    = $r[1];
          $ut          = $r[2];

          if(!defined $dev_reading)     {$dev_reading = '';}
          if(!defined $read_val)        {$read_val = '';}
          if(!defined $ut || $ut eq "") {$ut = AttrVal($dev_name, 'unit', '');}

          $event = 'addLog';

          $defs{$dev_name}{Helper}{DBLOG}{$dev_reading}{$name}{TIME}  = $now;
          $defs{$dev_name}{Helper}{DBLOG}{$dev_reading}{$name}{VALUE} = $read_val;

          $ts     = TimeNow();
          my $ctz = AttrVal($name, 'convertTimezone', 'none');                                               # convert time zone

          if($ctz ne 'none') {
              my $err;
              my $params = {
                  name      => $name,
                  dtstring  => $ts,
                  tzcurrent => 'local',
                  tzconv    => $ctz,
                  writelog  => 0
              };

              ($err, $ts) = convertTimeZone ($params);

              if ($err) {
                  Log3 ($name, 1, "$name - ERROR while converting time zone: $err - exit log loop !");
                  last;
              }
          }

          if($value_fn ne '') {                                                                  # Anwender spezifische Funktion anwenden
              my $lastt         = $defs{$dev_name}{Helper}{DBLOG}{$dev_reading}{$name}{TIME};    # patch Forum:#111423
              my $lastv         = $defs{$dev_name}{Helper}{DBLOG}{$dev_reading}{$name}{VALUE};
              
              my $NAME          = $name;
              my $TIMESTAMP     = $ts;
              my $LASTTIMESTAMP = $lastt // 0;                                                   # patch Forum:#111423
              my $DEVICE        = $dev_name;
              my $DEVICETYPE    = $dev_type;
              my $EVENT         = $event;
              my $READING       = $dev_reading;
              my $VALUE         = $read_val;
              my $LASTVALUE     = $lastv // '';                                                  # patch Forum:#111423
              my $UNIT          = $ut;
              my $IGNORE        = 0;
              my $CN            = $cn ? $cn : '';

              eval $value_fn;

              Log3 ($name, 2, "$name - error valueFn: ".$@) if($@);

              if($IGNORE) {                                                                                # aktueller Event wird nicht geloggt wenn $IGNORE=1 gesetzt
                 $defs{$dev_name}{Helper}{DBLOG}{$dev_reading}{$name}{TIME}  = $lastt if($lastt);          # patch Forum:#111423
                 $defs{$dev_name}{Helper}{DBLOG}{$dev_reading}{$name}{VALUE} = $lastv if(defined $lastv);
                 next;
              }

              my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($TIMESTAMP =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);

              eval { my $epoch_seconds_begin = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };
              if (!$@) {
                  $ts = $TIMESTAMP;
              }
              else {
                  Log3 ($name, 2, "$name - Parameter TIMESTAMP got from valueFn is invalid: $TIMESTAMP");
              }

              $dev_name     = $DEVICE     if($DEVICE ne '');
              $dev_type     = $DEVICETYPE if($DEVICETYPE ne '');
              $dev_reading  = $READING    if($READING ne '');
              $read_val     = $VALUE      if(defined $VALUE);
              $ut           = $UNIT       if(defined $UNIT);
              $event        = $EVENT      if(defined $EVENT);
          }

          # Daten auf maximale Länge beschneiden
          ($dev_name,$dev_type,$event,$dev_reading,$read_val,$ut) = DbLog_cutCol ($hash, $dev_name, $dev_type, $event, $dev_reading, $read_val, $ut);

          if (AttrVal($name, 'useCharfilter', 0)) {
              $dev_reading = DbLog_charfilter($dev_reading);
              $read_val    = DbLog_charfilter($read_val);
          }

          my $row = $ts."|".$dev_name."|".$dev_type."|".$event."|".$dev_reading."|".$read_val."|".$ut;

          if (!AttrVal($name, 'suppressAddLogV3', 0)) {
              Log3 $name, 3, "$name - addLog created - TS: $ts, Device: $dev_name, Type: $dev_type, Event: $event, Reading: $dev_reading, Value: $read_val, Unit: $ut";
          }

          $memcount = DbLog_addMemCacheRow ($name, $row);                                # Datensatz zum Memory Cache hinzufügen

          if($async) {                                                                   # asynchoner non-blocking Mode
              readingsSingleUpdate($hash, 'CacheUsage', $memcount, ($ce == 1 ? 1 : 0));
          }
      }
      use warnings;
  }

  if(!$async) {                                                                          # synchoner Mode
      if($memcount) {
          return if($hash->{HELPER}{REOPEN_RUNS});                                       # return wenn "reopen" mit Ablaufzeit gestartet ist

          my $err = DbLog_execMemCacheSync ($hash);
          DbLog_setReadingstate ($hash, $err) if($err);
      }
  }

return;
}

#########################################################################################
#
# Subroutine addCacheLine - einen Datensatz zum Cache hinzufügen
#
#########################################################################################
sub DbLog_addCacheLine {
  my $paref       = shift;

  my $hash        = $paref->{hash};
  my $i_timestamp = $paref->{i_timestamp};
  my $i_dev       = $paref->{i_dev};
  my $i_type      = $paref->{i_type};
  my $i_evt       = $paref->{i_evt};
  my $i_reading   = $paref->{i_reading};
  my $i_val       = $paref->{i_val};
  my $i_unit      = $paref->{i_unit};

  my $name        = $hash->{NAME};
  my $ce          = AttrVal ($name, 'cacheEvents',  0);
  my $value_fn    = AttrVal ($name, 'valueFn',     '');
  my $async       = AttrVal ($name, 'asyncMode',    0);

  if( $value_fn =~ m/^\s*(\{.*\})\s*$/s ) {                  # Funktion aus Attr valueFn validieren
      $value_fn = $1;
  }
  else {
      $value_fn = '';
  }

  if($value_fn ne '') {
      my $lastt;
      my $lastv;

      if($defs{$i_dev}) {
          $lastt = $defs{$i_dev}{Helper}{DBLOG}{$i_reading}{$name}{TIME};
          $lastv = $defs{$i_dev}{Helper}{DBLOG}{$i_reading}{$name}{VALUE};
      }

      my $NAME          = $name;
      my $TIMESTAMP     = $i_timestamp;
      my $LASTTIMESTAMP = $lastt // 0;                       # patch Forum:#111423
      my $DEVICE        = $i_dev;
      my $DEVICETYPE    = $i_type;
      my $EVENT         = $i_evt;
      my $READING       = $i_reading;
      my $VALUE         = $i_val;
      my $LASTVALUE     = $lastv // '';                      # patch Forum:#111423
      my $UNIT          = $i_unit;
      my $IGNORE        = 0;
      my $CN            = " ";

      eval $value_fn;
      Log3 ($name, 2, "$name - error valueFn: ".$@) if($@);

      if ($IGNORE) {                                                                                              # kein add wenn $IGNORE=1 gesetzt
          $defs{$i_dev}{Helper}{DBLOG}{$i_reading}{$name}{TIME}  = $lastt if($defs{$i_dev} && $lastt);            # patch Forum:#111423
          $defs{$i_dev}{Helper}{DBLOG}{$i_reading}{$name}{VALUE} = $lastv if($defs{$i_dev} && defined $lastv);

          Log3 ($name, 4, "$name - Event ignored by valueFn - TS: $i_timestamp, Device: $i_dev, Type: $i_type, Event: $i_evt, Reading: $i_reading, Value: $i_val, Unit: $i_unit");

          next;
      }

      my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($TIMESTAMP =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);

      eval { my $epoch_seconds_begin = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };
      if (!$@) {
          $i_timestamp = $TIMESTAMP;
      }
      else {
          Log3 ($name, 2, "$name - Parameter TIMESTAMP got from valueFn is invalid: $TIMESTAMP");
      }

      $i_dev     = $DEVICE     if($DEVICE ne '');
      $i_type    = $DEVICETYPE if($DEVICETYPE ne '');
      $i_reading = $READING    if($READING ne '');
      $i_val     = $VALUE      if(defined $VALUE);
      $i_unit    = $UNIT       if(defined $UNIT);
      $i_evt     = $EVENT      if(defined $EVENT);
  }

  no warnings 'uninitialized';                                                      # Daten auf maximale Länge beschneiden
  ($i_dev,$i_type,$i_evt,$i_reading,$i_val,$i_unit) = DbLog_cutCol ($hash, $i_dev, $i_type, $i_evt, $i_reading, $i_val, $i_unit);

  my $row = $i_timestamp."|".$i_dev."|".$i_type."|".$i_evt."|".$i_reading."|".$i_val."|".$i_unit;
  $row    = DbLog_charfilter($row) if(AttrVal($name, "useCharfilter",0));

  Log3 ($name, 4, "$name - added by addCacheLine - TS: $i_timestamp, Device: $i_dev, Type: $i_type, Event: $i_evt, Reading: $i_reading, Value: $i_val, Unit: $i_unit");

  use warnings;

  eval {                                                                            # one Transaction
      my $memcount = DbLog_addMemCacheRow ($name, $row);                            # Datensatz zum Memory Cache hinzufügen

      if ($async) {
          readingsSingleUpdate($hash, 'CacheUsage', $memcount, ($ce == 1 ? 1 : 0));
      }
  };

return;
}

#########################################################################################
#
# Subroutine cutCol - Daten auf maximale Länge beschneiden
#
#########################################################################################
sub DbLog_cutCol {
  my ($hash,$dn,$dt,$evt,$rd,$val,$unit) = @_;
  
  my $name       = $hash->{NAME};
  my $colevent   = AttrVal ($name, 'colEvent',   undef);
  my $colreading = AttrVal ($name, 'colReading', undef);
  my $coltype    = AttrVal ($name, 'colType',    undef);
  my $colvalue   = AttrVal ($name, 'colValue',   undef);

  if ($hash->{MODEL} ne 'SQLITE' || defined($colevent) || defined($colreading) || defined($coltype) || defined($colvalue) ) {
      $dn   = substr($dn,  0, $hash->{HELPER}{DEVICECOL});
      $dt   = substr($dt,  0, $hash->{HELPER}{TYPECOL});
      $evt  = substr($evt, 0, $hash->{HELPER}{EVENTCOL});
      $rd   = substr($rd,  0, $hash->{HELPER}{READINGCOL});
      $val  = substr($val, 0, $hash->{HELPER}{VALUECOL});
      $unit = substr($unit,0, $hash->{HELPER}{UNITCOL}) if($unit);
  }
return ($dn,$dt,$evt,$rd,$val,$unit);
}

###############################################################################
#   liefert zurück ob Autocommit ($useac) bzw. Transaktion ($useta)
#   verwendet werden soll
#
#   basic_ta:on   - Autocommit Servereinstellung / Transaktion ein
#   basic_ta:off  - Autocommit Servereinstellung / Transaktion aus
#   ac:on_ta:on   - Autocommit ein / Transaktion ein
#   ac:on_ta:off  - Autocommit ein / Transaktion aus
#   ac:off_ta:on  - Autocommit aus / Transaktion ein (AC aus impliziert TA ein)
#
#   Autocommit:   0/1/2 = aus/ein/Servereinstellung
#   Transaktion:  0/1   = aus/ein
###############################################################################
sub DbLog_commitMode {
  my $name = shift;
  my $cm   = shift;

  my $useac  = 2;      # default Servereinstellung
  my $useta  = 1;      # default Transaktion ein

  my ($ac,$ta) = split "_", $cm;

  $useac = $ac =~ /off/xs ? 0 :
           $ac =~ /on/xs  ? 1 :
           2;

  $useta = 0 if($ta =~ /off/);

return ($useac,$useta);
}

###############################################################################
#              Zeichen von Feldevents filtern
###############################################################################
sub DbLog_charfilter {
  my $txt = shift;

  my ($p,$a);

  # nur erwünschte Zeichen ASCII %d32-126 und Sonderzeichen
  $txt =~ s/ß/ss/g;
  $txt =~ s/ä/ae/g;
  $txt =~ s/ö/oe/g;
  $txt =~ s/ü/ue/g;
  $txt =~ s/Ä/Ae/g;
  $txt =~ s/Ö/Oe/g;
  $txt =~ s/Ü/Ue/g;
  $txt =~ s/€/EUR/g;
  $txt =~ s/\xb0/1degree1/g;

  $txt =~ tr/ A-Za-z0-9!"#$%&'()*+,-.\/:;<=>?@[\\]^_`{|}~//cd;

  $txt =~ s/1degree1/°/g;

return($txt);
}

###############################################################################
#   Einen Attributinhalt vom Typ textField-long splitten und als
#   Array zurückgeben
#   Optional kann das Split-Zeichen, default ',', angegeben werden.
###############################################################################
sub DbLog_attrLong2Array {
  my $content = shift;
  my $sptchar = shift // q{,};

  return if(!$content);

  my @v = map { my $p = $_; $p =~ s/\s//xg; $p; } split /$sptchar/xs, $content;                ## no critic 'Map blocks'

return @v;
}

################################################################
# benutzte DB-Feldlängen in Helper und Internals setzen
################################################################
sub DbLog_setinternalcols {
  my $hash = shift;
  my $name = $hash->{NAME};

  $hash->{HELPER}{DEVICECOL}   = $DbLog_columns{DEVICE};
  $hash->{HELPER}{TYPECOL}     = AttrVal($name, 'colType',       $DbLog_columns{TYPE});
  $hash->{HELPER}{EVENTCOL}    = AttrVal($name, 'colEvent',     $DbLog_columns{EVENT});
  $hash->{HELPER}{READINGCOL}  = AttrVal($name, 'colReading', $DbLog_columns{READING});
  $hash->{HELPER}{VALUECOL}    = AttrVal($name, 'colValue',     $DbLog_columns{VALUE});
  $hash->{HELPER}{UNITCOL}     = $DbLog_columns{UNIT};

  $hash->{COLUMNS}        = "field length used for Device: $hash->{HELPER}{DEVICECOL}, Type: $hash->{HELPER}{TYPECOL}, Event: $hash->{HELPER}{EVENTCOL}, Reading: $hash->{HELPER}{READINGCOL}, Value: $hash->{HELPER}{VALUECOL}, Unit: $hash->{HELPER}{UNITCOL} ";
  $hash->{HELPER}{COLSET} = 1;                                        # Statusbit "Columns sind gesetzt"

return;
}

#################################################################
#    einen Hashinhalt mit Schlüssel ausgeben
#    $href    - Referenz auf den Hash
#    $level   - Level für Logausgabe
#################################################################
sub DbLog_logHashContent {
  my $paref      = shift;

  my $name       = $paref->{name};
  my $verbose    = AttrVal ($name, 'verbose', $attr{global}{verbose});
  my $level      = $paref->{level};

  return if($level > $verbose);

  my $href       = $paref->{href};
  my $logtxt     = $paref->{logtxt}     // q{};
  my $subprocess = $paref->{subprocess} // q{};

  no warnings 'numeric';

  for my $key (sort {$a<=>$b} keys %{$href}) {
      next if(!defined $href->{$key});

      _DbLog_SBP_Log3Parent ( { name       => $name,
                                level      => $level,
                                msg        => qq($logtxt $key -> $href->{$key}),
                                oper       => 'log3parent',
                                subprocess => $subprocess
                              }
                            );
  }

  use warnings;

return;
}

################################################################
# reopen DB-Connection nach Ablauf set ... reopen [n] seconds
################################################################
sub DbLog_reopen {
  my $hash  = shift;
  my $name  = $hash->{NAME};
  my $async = AttrVal($name, 'asyncMode', 0);

  RemoveInternalTimer($hash, "DbLog_reopen");

  my $delay = delete $hash->{HELPER}{REOPEN_RUNS};                           # Statusbit "Kein Schreiben in DB erlauben" löschen
  delete $hash->{HELPER}{REOPEN_RUNS_UNTIL};

  if($delay) {
      Log3 ($name, 2, "$name - Database connection reopened (it was $delay seconds closed).");
  }

  DbLog_setReadingstate   ($hash, 'reopened');
  DbLog_execMemCacheAsync ($hash) if($async);

return;
}

################################################################
# check ob primary key genutzt wird
################################################################
sub DbLog_checkUsePK {
  my $paref   = shift;

  my $name    = $paref->{name};
  my $dbh     = $paref->{dbh};
  my $dbconn  = $paref->{dbconn};
  my $history = $paref->{history};
  my $current = $paref->{current};

  my $upkh    = 0;
  my $upkc    = 0;

  my (@pkh,@pkc);

  my $db = (split("=",(split(";",$dbconn))[0]))[1];

  eval {@pkh = $dbh->primary_key( undef, undef, 'history' );};
  eval {@pkc = $dbh->primary_key( undef, undef, 'current' );};

  my $pkh = (!@pkh || @pkh eq "") ? "none" : join(",",@pkh);
  my $pkc = (!@pkc || @pkc eq "") ? "none" : join(",",@pkc);
  $pkh    =~ tr/"//d;
  $pkc    =~ tr/"//d;
  $upkh   = 1 if(@pkh && @pkh ne "none");
  $upkc   = 1 if(@pkc && @pkc ne "none");

  Log3 ($name, 4, "$name - Primary Key used in $history: $pkh");
  Log3 ($name, 4, "$name - Primary Key used in $current: $pkc");

return ($upkh,$upkc,$pkh,$pkc);
}

################################################################
# Syntaxcheck von Attr valueFn und DbLogValueFn
# Rückgabe von Error oder der gesäuberten Funktion
################################################################
sub DbLog_checkSyntaxValueFn {
  my $name     = shift;
  my $func     = shift;
  my $devname  = shift // q{};

  my $err = q{};

  if ($func !~ m/^\s*(\{.*\})\s*$/s) {
      return "Error while syntax checking. The function has to be enclosed by curly brackets.";
  }

  my %specials= (
     "%NAME"          => $name,
     "%TIMESTAMP"     => $name,
     "%LASTTIMESTAMP" => $name,
     "%DEVICE"        => $name,
     "%DEVICETYPE"    => $name,
     "%EVENT"         => $name,
     "%READING"       => $name,
     "%VALUE"         => $name,
     "%LASTVALUE"     => $name,
     "%UNIT"          => $name,
     "%IGNORE"        => $name,
     "%CN"            => $name
  );

  $err = perlSyntaxCheck ($func, %specials);

  Log3 ($name, 1, "$name - Syntaxcheck <$devname> attribute DbLogValueFn: \n".$err) if($err && $devname);

  $func =~ s/^\s*(\{.*\})\s*$/$1/s;

return ($err, $func);
}

################################################################
#  Routine für FHEMWEB Detailanzeige
################################################################
sub DbLog_fhemwebFn {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.

  my $ret;
  my $newIdx = 1;

  while($defs{"SVG_${d}_$newIdx"}) {
      $newIdx++;
  }

  my $name = "SVG_${d}_$newIdx";
  $ret    .= FW_pH("cmd=define $name SVG $d:templateDB:HISTORY;".
                   "set $name copyGplotFile&detail=$name",
                   "<div class=\"dval\">Create SVG plot from DbLog</div>", 0, "dval", 1);
return $ret;
}

############################################################################################
#  Dropdown-Menü current-Tabelle SVG-Editor
#  Datenlieferung für SVG EDitor
#
#  <device>:<reading>:<default>:<fn>:<regexp>
#  Beispiel Input Zeile: sysmon:ram::delta-h:$val=~s/^Total..([\d.]*).*/$1/eg
#                          0     1 2 3       4
#  $ret .= SVG_txt("par_${r}_0", "", $f[0], 40); # Device  (Column bei FileLog)
#  $ret .= SVG_txt("par_${r}_1", "", $f[1], 40); # Reading (RegExp bei FileLog)
#  $ret .= SVG_txt("par_${r}_2", "", $f[2], 1);  # Default not yet implemented
#  $ret .= SVG_txt("par_${r}_3", "", $f[3], 10); # Function
#  $ret .= SVG_txt("par_${r}_4", "", $f[4], 10); # RegExp (int, delta-h, delta-d, delta-ts)
#############################################################################################
sub DbLog_sampleDataFn {
  my $dlName  = shift;
  my $dlog    = shift;
  my $max     = shift;
  my $conf    = shift;
  my $wName   = shift;

  my $desc    = "";                                                                         # Beschreibung über Eingabezeile
  my $hash    = $defs{$dlName};
  my $current = $hash->{HELPER}{TC};
  my $history = $hash->{HELPER}{TH};

  my @htmlArr;
  my @example;
  my @colregs;
  my $counter;

  my $err = _DbLog_manageDBHU ($defs{$dlName});
  return if($err);

  my $dbh    = $hash->{DBHU};
  my $ccount = 0;
  my $dblt   = AttrVal ($dlName, 'DbLogType',              'History');
  my $pifl   = AttrVal ($dlName, 'plotInputFieldLength', $dblog_pifl);

  if ($dblt =~ m/Current|SampleFill/xs) {
      $ccount = eval {$dbh->selectrow_array("select count(*) from $current");} || 0;
  }

  if ($ccount) {                                                                           # Table Current present, use it for sample data
      $desc = "Device:Reading [Function]".
              "<br>[RegExp] &lt;unused&gt;";                                               # Beschreibung über Eingabezeile

      my $query = "select device,reading from $current where device <> '' group by device,reading";
      my $sth   = $dbh->prepare( $query );
      $sth->execute();

      while (my @line = $sth->fetchrow_array()) {
          $counter++;
          push @example, (join ":", @line).' [Function]<br>[RegExp]' if($counter <= 4);    # show max 4 examples
          push @colregs, "$line[0]:$line[1]";                                              # push all eventTypes to selection list
      }

      my $cols = join ",", sort { "\L$a" cmp "\L$b" } @colregs;

      for (my $r = 0; $r < $max; $r++) {
          my @f   = split ":", ($dlog->[$r] ? $dlog->[$r] : "::::"), 5;                    # Beispiel Input Zeile > sysmon:ram::delta-h:$val=~s/^Total..([\d.]*).*/$1/eg          
          my $ret = q{};                                                                   #                           0   1  2 3       4

          no warnings 'uninitialized';                                                     # Forum:74690, bug unitialized
          $ret .= SVG_sel ("par_${r}_0", $cols, "$f[0]:$f[1]");                            # par_<Zeile>_<Spalte>, <Auswahl>, <Vorbelegung>

          $ret .= SVG_sel ("par_${r}_3", $dblog_svgfnset, $f[3]);                          # Funktionsauswahl

          $f[4] =~ /^(:+)?(.*)/xs;
          $ret .= SVG_txt ("par_${r}_4", "<br>", "$2", $pifl);                             # RegExp (z.B. $val=~s/^Total..([\d.]*).*/$1/eg)

          $ret .= SVG_txt ("par_${r}_2", "", $f[2], 1);                                    # der Defaultwert (nicht ausgewertet)
          use warnings;
          
          push @htmlArr, $ret;
      }
  }
  else {                                                                                   # Table Current not present, so create an empty input field
      push @example, '&lt;Device&gt;:&lt;Reading&gt;::[Function]<br>[RegExp]';

      $desc = "Device:Reading::[Function]".
              "<br>RegExp";                                                                # Beschreibung über Eingabezeile

      for (my $r = 0; $r < $max; $r++) {
          my @f   = split ":", ($dlog->[$r] ? $dlog->[$r] : "::::"), 5;
          my $ret = q{};

          no warnings 'uninitialized';                                                     # Forum:74690, bug unitialized
          $ret .= SVG_txt ("par_${r}_0", "", "$f[0]:$f[1]::$f[3]", $pifl);                 # letzter Wert -> Breite der Eingabezeile

          $f[4] =~ /^(:+)?(.*)/xs;
          $ret .= SVG_txt ("par_${r}_3", "<br>", "$2", $pifl);                             # RegExp (z.B. $val=~s/^Total..([\d.]*).*/$1/eg)
          use warnings;
          
          push @htmlArr, $ret;
      }
  }

return ($desc, \@htmlArr, join("<br>", @example));
}

################################################################
#           Error handling, returns a JSON String
################################################################
sub DbLog_jsonError {
  my $errormsg = $_[0];

  my $json = '{"success": "false", "msg":"'.$errormsg.'"}';

return $json;
}

################################################################
#     Tabellenname incl. Schema erstellen
################################################################
sub DbLog_setSchemeTable {
  my $hash   = shift;
  my $scheme = shift // AttrVal($hash->{NAME}, 'dbSchema', '');

 if ($scheme) {
      $hash->{HELPER}{TH} = $scheme.'.history';
      $hash->{HELPER}{TC} = $scheme.'.current';
  }
  else {
      $hash->{HELPER}{TH} = 'history';
      $hash->{HELPER}{TC} = 'current';
  }

return;
}

################################################################
#              Check Zeitformat
#              Zeitformat: YYYY-MM-DD HH:MI:SS
################################################################
sub DbLog_checkTimeformat {
  my ($t) = @_;

  my (@datetime, @date, @time);
  @datetime = split(" ", $t);                                   # Datum und Zeit auftrennen
  @date     = split("-", $datetime[0]);
  @time     = split(":", $datetime[1]);

  eval { timelocal($time[2], $time[1], $time[0], $date[2], $date[1]-1, $date[0]-1900); };

  if ($@) {
      my $err = (split(" at ", $@))[0];
      return $err;
  }

return;
}

################################################################
#               Versionierungen des Moduls setzen
#  Die Verwendung von Meta.pm und Packages wird berücksichtigt
################################################################
sub DbLog_setVersionInfo {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (sortTopicNum("desc",keys %DbLog_vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;

  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {       # META-Daten sind vorhanden
      $modules{$type}{META}{version} = "v".$v;                                        # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{DbLog}{META}}
      if($modules{$type}{META}{x_version}) {                                          # {x_version} ( nur gesetzt wenn $Id: 93_DbLog.pm 28085 2023-10-22 14:22:29Z DS_Starter $ im Kopf komplett! vorhanden )
          $modules{$type}{META}{x_version} =~ s/1\.1\.1/$v/xsg;
      }
      else {
          $modules{$type}{META}{x_version} = $v;
      }
      return $@ unless (FHEM::Meta::SetInternals($hash));                             # FVERSION wird gesetzt ( nur gesetzt wenn $Id: 93_DbLog.pm 28085 2023-10-22 14:22:29Z DS_Starter $ im Kopf komplett! vorhanden )
      if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {
          # es wird mit Packages gearbeitet -> Perl übliche Modulversion setzen
          # mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
          use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );
      }
  }
  else {
      # herkömmliche Modulstruktur
      $hash->{VERSION} = $v;
  }

return;
}

1;

=pod
=item helper
=item summary    logs events into a database
=item summary_DE loggt Events in eine Datenbank
=begin html

<a id="DbLog"></a>
<h3>DbLog</h3>
<br>

<ul>
  With DbLog events can be stored in a database. SQLite, MySQL/MariaDB and PostgreSQL are supported databases. <br><br>

  <b>Prereqisites</b> <br><br>

    The Perl-modules <code>DBI</code> and <code>DBD::&lt;dbtype&gt;</code> are needed to be installed (use <code>cpan -i &lt;module&gt;</code>
    if your distribution does not have it).
    <br><br>

    On a debian based system you may install these modules for instance by: <br><br>

    <ul>
    <table>
    <colgroup> <col width=5%> <col width=95%> </colgroup>
      <tr><td> <b>DBI</b>         </td><td>: <code> sudo apt-get install libdbi-perl </code> </td></tr>
      <tr><td> <b>MySQL</b>       </td><td>: <code> sudo apt-get install [mysql-server] mysql-client libdbd-mysql libdbd-mysql-perl </code> (mysql-server only if you use a local MySQL-server installation) </td></tr>
      <tr><td> <b>SQLite</b>      </td><td>: <code> sudo apt-get install sqlite3 libdbi-perl libdbd-sqlite3-perl </code> </td></tr>
      <tr><td> <b>PostgreSQL</b>  </td><td>: <code> sudo apt-get install libdbd-pg-perl </code> </td></tr>
    </table>
    </ul>
    <br>
    <br>

  <b>Preparations</b> <br><br>

  At first you need to install and setup the database.
  The installation of database system itself is not described here, please refer to the installation instructions of your
  database. <br><br>

  <b>Note:</b> <br>
  In case of fresh installed MySQL/MariaDB system don't forget deleting the anonymous "Everyone"-User with an admin-tool if
  existing.
  <br><br>

  Sample code and Scripts to prepare a MySQL/PostgreSQL/SQLite database you can find in
  <a href="https://svn.fhem.de/trac/browser/trunk/fhem/contrib/dblog">SVN -&gt; contrib/dblog/db_create_&lt;DBType&gt;.sql</a>. <br>
  (<b>Caution:</b> The local FHEM-Installation subdirectory ./contrib/dblog doesn't contain the freshest scripts!)
  <br><br>

  The default installation of the MySQL/MariaDB database provides for the use of the <b>utf8_bin</b> collation.
  With this setting, characters up to 3 bytes long can be stored, which is generally sufficient.
  However, if characters with a length of 4 bytes (e.g. emojis) are to be stored in the database, the <b>utf8mb4</b>
  character set must be used. <br>
  Accordingly, in this case the MySQL/MariaDB database would be created with the following statement: <br><br>

  <ul>
   <code> CREATE DATABASE `fhem` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin; </code>
  </ul>
  <br>

  In the configuration file (see below) utf8 support must be enabled with the key <b>utf8 => 1</b> if utf8 is to be
  used. <br><br>

  The database contains two tables: <code>current</code> and <code>history</code>. <br>
  The latter contains all events whereas the former only contains the last event for any given reading and device.
  Please consider the <a href="#DbLog-attr-DbLogType">DbLogType</a> implicitly to determine the usage of tables
  <code>current</code> and <code>history</code>.
  <br><br>

  The columns have the following meaning: <br><br>

    <ul>
    <table>
    <colgroup> <col width=5%> <col width=95%> </colgroup>
      <tr><td> TIMESTAMP </td><td>: timestamp of event, e.g. <code>2007-12-30 21:45:22</code> </td></tr>
      <tr><td> DEVICE    </td><td>: device name, e.g. <code>Wetterstation</code> </td></tr>
      <tr><td> TYPE      </td><td>: device type, e.g. <code>KS300</code> </td></tr>
      <tr><td> EVENT     </td><td>: event specification as full string, e.g. <code>humidity: 71 (%)</code> </td></tr>
      <tr><td> READING   </td><td>: name of reading extracted from event, e.g. <code>humidity</code> </td></tr>
      <tr><td> VALUE     </td><td>: actual reading extracted from event, e.g. <code>71</code> </td></tr>
      <tr><td> UNIT      </td><td>: unit extracted from event, e.g. <code>%</code> </td></tr>
    </table>
    </ul>
    <br>
    <br>

  <b>create index</b> <br>
  Due to reading performance, e.g. on creation of SVG-plots, it is very important that the <b>index "Search_Idx"</b>
  or a comparable index (e.g. a primary key) is applied.
  A sample code for creation of that index is also available in mentioned scripts of
  <a href="https://svn.fhem.de/trac/browser/trunk/fhem/contrib/dblog">SVN -&gt; contrib/dblog/db_create_&lt;DBType&gt;.sql</a>.
  <br><br>

  The index "Search_Idx" can be created, e.g. in database 'fhem', by these statements (also subsequently): <br><br>

    <ul>
    <table>
    <colgroup> <col width=5%> <col width=95%> </colgroup>
      <tr><td> <b>MySQL</b>       </td><td>: <code> CREATE INDEX Search_Idx ON `fhem`.`history` (DEVICE, READING, TIMESTAMP); </code> </td></tr>
      <tr><td> <b>SQLite</b>      </td><td>: <code> CREATE INDEX Search_Idx ON `history` (DEVICE, READING, TIMESTAMP); </code> </td></tr>
      <tr><td> <b>PostgreSQL</b>  </td><td>: <code> CREATE INDEX "Search_Idx" ON history USING btree (device, reading, "timestamp"); </code> </td></tr>
    </table>
    </ul>
    <br>

  For the connection to the database a <b>configuration file</b> is used.
  The configuration file is copied e.g. to /opt/fhem and has the structure shown below.
  The specifications are to be adapted according to the used environment (uncomment and change corresponding lines): 
  <br><br>

    <pre>
    ####################################################################################
    # database configuration file
    #
    # NOTE:
    # If you don't use a value for user / password please delete the leading hash mark
    # and write 'user => ""' respectively 'password => ""' instead !
    #
    #
    ## for MySQL
    ####################################################################################
    #%dbconfig= (
    #    connection => "mysql:database=fhem;host=&lt;database host&gt;;port=3306",
    #    # if want communication over socket-file instead of TCP/IP transport, use:
    #    # connection => "mysql:database=fhem;mysql_socket=&lt;/patch/socket-file&gt;",
    #    user => "fhemuser",
    #    password => "fhempassword",
    #    # optional enable(1) / disable(0) UTF-8 support
    #    # (full UTF-8 support exists from DBD::mysql version 4.032, but installing
    #    # 4.042 is highly suggested)
    #    utf8 => 1
    #);
    ####################################################################################
    #
    ## for PostgreSQL
    ####################################################################################
    #%dbconfig= (
    #    connection => "Pg:database=fhem;host=&lt;database host&gt;",
    #    user => "fhemuser",
    #    password => "fhempassword"
    #);
    ####################################################################################
    #
    ## for SQLite (username and password stay empty for SQLite)
    ####################################################################################
    #%dbconfig= (
    #    connection => "SQLite:dbname=/opt/fhem/fhem.db",
    #    user => "",
    #    password => ""
    #);
    ####################################################################################
    </pre>
    If configDB is used, the configuration file has to be uploaded into the configDB ! <br><br>

    <b>Note about special characters:</b><br>
    If special characters, e.g. @,$ or % which have a meaning in the perl programming
    language are used in a password, these special characters have to be escaped.
    That means in this example you have to use: \@,\$ respectively \%.
    <br>
    <br>
    
    <b>DbLog specific events</b> <br><br>
    
    DbLog generates events depending on the initialisation status of the DbLog device: 
    <br>
    <br>
    
      <ul>
       <table>
       <colgroup> <col width=20%> <col width=80%> </colgroup>
       <tr><td> FRAME_INITIALIZED    </td><td>- The basic framework is initialised. Blocking (Get) commands can be executed.                     </td></tr>
       <tr><td> SUBPROC_INITIALIZED  </td><td>- The SupProcess is ready for use. Non-blocking (set) commands and Data logging can be executed.   </td></tr>
       <tr><td> SUBPROC_DISCONNECTED </td><td>- The SupProcess was separated from the DB.                                                        </td></tr>
       <tr><td> SUBPROC_STOPPED      </td><td>- The SupProcess has been stopped.                                                                 </td></tr>
       </table>
      </ul>
    
    <br>
    <br>
    <br>


  <a id="DbLog-define"></a>
  <b>Define</b>
  <br>
  <br>

  <ul>

    <b>define &lt;name&gt; DbLog &lt;configfilename&gt; &lt;regexp&gt; </b> <br><br>

    <code>&lt;configfilename&gt;</code> is the prepared <b>configuration file</b>. <br>
    <code>&lt;regexp&gt;</code> is identical to the specification of regex in the <a href="https://fhem.de/commandref.html#FileLog">FileLog</a> definition.
    <br><br>

    <b>Example:</b>
    <ul>
        <code>define myDbLog DbLog /etc/fhem/db.conf .*:.*</code><br>
        all events will stored into the database
    </ul>
    <br>

    After you have defined your DbLog-device it is recommended to run the <b>configuration check</b> <br><br>
    <ul>
        <code>get &lt;name&gt; configCheck</code> <br>
    </ul>
    <br>

    This check reports some important settings and gives recommendations back to you if proposals are indentified.
    <br><br>

    DbLog distinguishes between the synchronous (default) and asynchronous logmode. The logmode is adjustable by the
    <a href="#DbLog-attr-asyncMode">asyncMode</a>. Since version 2.13.5 DbLog is supporting primary key (PK) set in table
    current or history. If you want use PostgreSQL with PK it has to be at lest version 9.5.
    <br><br>

    The content of VALUE will be optimized for automated post-processing, e.g. <code>yes</code> is translated
    to <code>1</code>
    <br><br>

    The stored values can be retrieved by the following code like FileLog:<br>
    <ul>
      <code>get myDbLog - - 2012-11-10 2012-11-10 KS300:temperature::</code>
    </ul>
    <br>

    <b>transfer FileLog-data to DbLog </b> <br><br>
    There is the special module 98_FileLogConvert.pm available to transfer filelog-data to the DbLog-database. <br>
    The module can be downloaded <a href="https://svn.fhem.de/trac/browser/trunk/fhem/contrib/98_FileLogConvert.pm"> here</a>
    or from directory ./contrib instead.
    Further information and help you can find in the corresponding <a href="https://forum.fhem.de/index.php/topic,66383.0.html">
    Forumthread </a>. <br><br><br>

    <b>Reporting and Management of DbLog database content</b> <br><br>
    By using <a href="https://fhem.de/commandref.html#SVG">SVG</a> database content can be visualized. <br>
    Beyond that the module <a href="https://fhem.de/commandref.html#DbRep">DbRep</a> can be used to prepare tabular
    database reports or you can manage the database content with available functions of that module.
    <br><br><br>

    <b>Troubleshooting</b> <br><br>
    If after successful definition the DbLog-device doesn't work as expected, the following notes may help:
    <br><br>

    <ul>
    <li> Have the preparatory steps as described in commandref been done ? (install software components, create tables and index) </li>
    <li> Was "get &lt;name&gt; configCheck" executed after definition and potential errors fixed or rather the hints implemented ? </li>
    <li> If configDB is used ... has the database configuration file been imported into configDB (e.g. by "configDB fileimport ./db.conf") ? </li>
    <li> When creating a SVG-plot and no drop-down list with proposed values appear -> set attribute "DbLogType" to "Current/History". </li>
    </ul>
    <br>

    If the notes don't lead to success, please increase verbose level of the DbLog-device to 4 or 5 and observe entries in
    logfile relating to the DbLog-device.

    For problem analysis please post the output of "list &lt;name&gt;", the result of "get &lt;name&gt; configCheck" and the
    logfile entries of DbLog-device to the forum thread.
    <br><br>

  </ul>
  <br>

  <a id="DbLog-set"></a>
  <b>Set</b>
  <br>
  <br>

  <ul>
    <li>
    <a id="DbLog-set-addCacheLine"></a>
    <b>set &lt;name&gt; addCacheLine YYYY-MM-DD HH:MM:SS|&lt;device&gt;|&lt;type&gt;|&lt;event&gt;|&lt;reading&gt;|&lt;value&gt;|[&lt;unit&gt;]  </b> <br><br>

    <ul>
    In asynchronous mode a new dataset is inserted to the Cache and will be processed at the next database sync cycle.
    <br><br>

      <b>Example:</b> <br>
      set &lt;name&gt; addCacheLine 2017-12-05 17:03:59|MaxBathRoom|MAX|valveposition: 95|valveposition|95|% <br>

    </li>
    </ul>
    <br>

    <li>
    <a id="DbLog-set-addLog"></a>
    <b>set &lt;name&gt; addLog &lt;devspec&gt;:&lt;Reading&gt; [Value] [CN=&lt;caller name&gt;] [!useExcludes] </b> <br><br>

    <ul>
    Inserts an additional log entry of a device/reading combination into the database. <br>
    Any readings specified in the "DbLogExclude" attribute (in the source device) will not be logged, unless
    they are included in the "DbLogInclude" attribute or the addLog call was made with the "!useExcludes" option.
    <br><br>

      <table>
       <colgroup> <col width=20%> <col width=80%> </colgroup>
       <tr><td> <b>&lt;devspec&gt;:&lt;Reading&gt;</b>   </td><td>The device can be specified as <a href="#devspec">device specification</a>.                      </td></tr>
       <tr><td>                                          </td><td>The specification of "Reading" is evaluated as a regular expression.                             </td></tr>
       <tr><td>                                          </td><td>If the reading does not exist and the value "Value" is specified, the reading                    </td></tr>
       <tr><td>                                          </td><td>will be inserted into the DB if it is not a regular expression and a valid reading name.         </td></tr>
       <tr><td>                                          </td><td>                                                                                                 </td></tr>
       <tr><td>                                          </td><td>                                                                                                 </td></tr>
       <tr><td> <b>Value</b>                             </td><td>Optionally, "Value" can be specified for the reading value.                                      </td></tr>
       <tr><td>                                          </td><td>If Value is not specified, the current value of the reading is inserted into the DB.             </td></tr>
       <tr><td>                                          </td><td>                                                                                                 </td></tr>
       <tr><td>                                          </td><td>                                                                                                 </td></tr>
       <tr><td> <b>CN=&lt;caller name&gt;</b>            </td><td>With the key "CN=" (<b>C</b>aller <b>N</b>ame) a string, e.g. the name of the calling device,    </td></tr>
       <tr><td>                                          </td><td>can be added to the addLog call.                                                                 </td></tr>
       <tr><td>                                          </td><td>With the help of the function stored in the attribute <a href="#DbLog-attr-valueFn">valueFn</a>  </td></tr>
       <tr><td>                                          </td><td>this key can be evaluated via the variable $CN.                                                  </td></tr>
       <tr><td>                                          </td><td>                                                                                                 </td></tr>
       <tr><td> <b>!useExcludes</b>                      </td><td>addLog by default takes into account the readings excluded with the "DbLogExclude" attribute.    </td></tr>
       <tr><td>                                          </td><td>With the keyword "!useExcludes" the set attribute "DbLogExclude" is ignored.                     </td></tr>
      </table>
      <br>

      The database field "EVENT" is automatically filled with "addLog". <br>
      There will be <b>no</b> additional event created in the system!   <br><br>

      <b>Examples:</b> <br>
      set &lt;name&gt; addLog SMA_Energymeter:Bezug_Wirkleistung        <br>
      set &lt;name&gt; addLog TYPE=SSCam:state                          <br>
      set &lt;name&gt; addLog MyWetter:(fc10.*|fc8.*)                   <br>
      set &lt;name&gt; addLog MyWetter:(wind|wind_ch.*) 20 !useExcludes <br>
      set &lt;name&gt; addLog TYPE=CUL_HM:FILTER=model=HM-CC-RT-DN:FILTER=subType!=(virtual|):(measured-temp|desired-temp|actuator) <br><br>

      set &lt;name&gt; addLog USV:state CN=di.cronjob <br><br>

      In the valueFn function the caller "di.cronjob" is evaluated via the variable $CN and depending on this the
      timestamp of this addLog is corrected: <br><br>

      valueFn = if($CN eq "di.cronjob" and $TIMESTAMP =~ m/\s00:00:[\d:]+/) { $TIMESTAMP =~ s/\s([^\s]+)/ 23:59:59/ }
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-clearReadings"></a>
    <b>set &lt;name&gt; clearReadings </b> <br><br>
    <ul>
      This function clears readings which were created by different DbLog-functions.
    </li>
    </ul>
    <br>

    <li>
    <a id="DbLog-set-commitCache"></a>
    <b>set &lt;name&gt; commitCache </b> <br><br>
    <ul>
      In asynchronous mode (<a href="#DbLog-attr-asyncMode">asyncMode=1</a>), the cached data in memory will be written
      into the database and subsequently the cache will be cleared. <br>
      Thereby the internal timer for the asynchronous mode Modus will be set new.
    </li>
    </ul>
    <br>

    <li>
    <a id="DbLog-set-configCheck"></a>
    <b>set &lt;name&gt; configCheck </b> <br><br>
    <ul>
      Checks some important settings and give recommendations back to you if proposals are identified. <br>
      (<b>Note:</b> This command is deprecated and will be removed in next releases. Use "get &lt;name&gt; configCheck" instead.)
    </li>
    </ul>
    <br>

    <li>
    <a id="DbLog-set-count"></a>
    <b>set &lt;name&gt; count </b> <br><br>
    <ul>
      Determines the number of records in the tables current and history and writes the results to the readings
      countCurrent and countHistory.
      <br><br>

      <b>Note</b> <br>
      During the runtime of the command, data to be logged are temporarily stored in the memory cache and written to the
      database written to the database after the command is finished.
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-countNbl"></a>
    <b>set &lt;name&gt; countNbl </b> <br><br>
      <ul>
      The function is identical to "set &lt;name&gt; count" and will be removed soon.
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-deleteOldDays"></a>
    <b>set &lt;name&gt; deleteOldDays &lt;n&gt; </b> <br><br>
    <ul>
      Deletes records older than &lt;n&gt; days in table history.
      The number of deleted records is logged in Reading lastRowsDeleted.
      <br><br>

      <b>Note</b> <br>
      During the runtime of the command, data to be logged are temporarily stored in the memory cache and written to the
      database written to the database after the command is finished.
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-eraseReadings"></a>
    <b>set &lt;name&gt; eraseReadings </b> <br><br>
    <ul>
      This function deletes all readings except reading "state".
    </li>
    </ul>
    <br>

    <li>
    <a id="DbLog-set-exportCache"></a>
    <b>set &lt;name&gt; exportCache [nopurge | purgecache] </b> <br><br>
    <ul>
      If DbLog is operated in asynchronous mode, the cache can be written to a text file with this command. <br>
      The file is created by default in the directory (global->modpath)/log/. The destination directory can be changed with
      the <a href="#DbLog-attr-expimpdir">expimpdir</a> attribute. <br><br>

      The name of the file is generated automatically and contains the prefix "cache_&lt;name&gt;" followed by
      the current timestamp. <br><br>

      <b>Example </b> <br>
      cache_LogDB_2017-03-23_22-13-55 <br><br>

      The "nopurge" and "purgecache" options determine whether or not the cache contents are to be deleted after the export.
      With "nopurge" (default) the cache content is preserved. <br>
      The <a href="#DbLog-attr-exportCacheAppend">exportCacheAppend</a> attribute determines whether with each export
      operation a new export file is created (default) or the cache content is appended to the latest existing export file.
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-importCachefile"></a>
    <b>set &lt;name&gt; importCachefile &lt;file&gt; </b> <br><br>
      <ul>
      Imports a file written with "exportCache" into the database. <br>
      The available files are searched by default in the directory (global->modpath)/log/ and a drop-down list is generated
      with the files are found. <br>
      The source directory can be changed with the <a href="#DbLog-attr-expimpdir">expimpdir</a> attribute. <br>
      Only the files matching the pattern "cache_&lt;name&gt;" are displayed. <br><br>

      <b>Example </b><br>
      cache_LogDB_2017-03-23_22-13-55 <br>
      if the DbLog device is called "LogDB". <br><br>

      After a successful import the file is prefixed with "impdone_" and no longer appears in the drop-down list.
      If a cache file is to be imported into a database other than the source database, the name of the
      DbLog device in the file name can be adjusted so that this file appears in the drop-down list.
      <br><br>

      <b>Note</b> <br>
      During the runtime of the command, data to be logged are temporarily stored in the memory cache and written
      to the database after the command is finished.
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-listCache"></a>
    <b>set &lt;name&gt; listCache </b> <br><br>
    <ul>
      Lists the data cached in the memory cache.
    </li>
    </ul>
    <br>

    <li>
    <a id="DbLog-set-purgeCache"></a>
    <b>set &lt;name&gt; purgeCache </b> <br><br>
    <ul>
      In asynchronous mode (<a href="#DbLog-attr-asyncMode">asyncMode=1</a>), the in memory cached data will be deleted.
      With this command data won't be written from cache into the database.
    </li>
    </ul>
    <br>

    <li>
    <a id="DbLog-set-reduceLog"></a>
    <b>set &lt;name&gt; reduceLog &lt;no&gt;[:&lt;nn&gt;] [average[=day]] [exclude=device1:reading1,device2:reading2,...] </b> <br><br>
    <ul>
      Reduces historical records older than &lt;no&gt; days and (optionally) newer than &lt;nn&gt; days
      to one record (the first) per hour per device & reading.<br>
      Inside device/reading <b>SQL wildcards "%" and "_"</b> can be used. <br><br>

      The optional specification of 'average' or 'average=day' not only cleans the database, but also reduces all
      numerical values of an hour or a day are reduced to a single average value. <br><br>

      Optionally, the last parameter "exclude=device1:reading1,device2:reading2,...." can be specified
      to exclude device/reading combinations from reduceLog. <br>
      Instead of "exclude", "include=device:reading" can be specified as the last parameter in order to
      limit the SELECT query executed on the database. This reduces the RAM load and increases performance.
      The option "include" can only be specified with a device:reading combination. <br><br>

      <ul>
        <b>Examples: </b> <br>
        set &lt;name&gt; reduceLog 270 average include=Luftdaten_remote:% <br>
        set &lt;name&gt; reduceLog 100:200 average exclude=SMA_Energymeter:Bezug_Wirkleistung
      </ul>
      <br>

      <b>Note</b> <br>
      During the runtime of the command, data to be logged is temporarily stored in the memory cache and written to
      the database after the command is finished.
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-reopen"></a>
    <b>set &lt;name&gt; reopen [n] </b> <br><br>
    <ul>
      Closes the database and then immediately opens it again if no time [n] in seconds has been specified. <br>
      If an optional delay time [n] in seconds has been specified, the connection to the database will be closed and
      reconnected only after [n] seconds have elapsed. <br>
      During the time of the database closure, events to be logged are stored in the memory cache and written to the
      database after the reconnect.
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-rereadcfg"></a>
    <b>set &lt;name&gt; rereadcfg </b> <br><br>
    <ul>
      The configuration file is read in again. <br>
      After reading, an existing database connection is terminated and re-established with the configured connection data.
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-stopSubProcess"></a>
    <b>set &lt;name&gt; stopSubProcess </b> <br><br>
    <ul>
      A running SubProcess is terminated. <br>
      As soon as a new subprocess is required by a Log operation, an automatic reinitialization of a process takes place.
      <br><br>

      <b>Note</b> <br>
      The re-initialization of the sub-process during runtime causes an increased RAM consumption until
      to a FHEM restart .
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-userCommand"></a>
    <b>set &lt;name&gt; userCommand &lt;validSelectStatement&gt; </b> <br><br>
    <ul>
      Executes simple SQL Select commands on the database. <br>
      The result of the statement is written to the reading "userCommandResult".
      The result can be only one line. <br>
      The execution of SQL commands in DbLog is deprecated.
      The <a href=https://fhem.de/commandref_DE.html#DbRep>DbRep</a> evaluation module should be used for this
      purpose. <br><br>

      <b>Note</b> <br>
      During the runtime of the command, data to be logged are temporarily stored in the memory cache and written to the
      database written to the database after the command is finished.
    </ul>
    </li>
    <br>

  </ul>
  <br>

  <a id="DbLog-get"></a>
  <b>Get</b>
  <br>
  <br>
  <ul>

    <li>
    <a id="DbLog-get-configCheck"></a>
    <b>get &lt;name&gt; configCheck </b> <br><br>
      <ul>
        A number of key settings are reviewed and recommendations are made if potential improvements are identified.
      </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-get-ReadingsMaxVal" data-pattern="ReadingsMaxVal.*"></a>
    <b>get &lt;name&gt; ReadingsMaxVal[Timestamp] &lt;Device&gt; &lt;Reading&gt; &lt;default&gt; </b>
    <br>
    <ul>
      Determines the record with the largest value of the specified Device / Reading combination from the history table. <br>
      Only the value or the combination of value and timestamp is returned as string
      "&lt;Wert&gt; , &lt;Timestamp&gt;". <br>
      &lt;default&gt; specifies a defined return value if no value can be determined.
      <br>
      <br>

      <b>Note:</b> <br>
      This database retrieval works blocking and influences FHEM if the database does not respond or not responds
      sufficiently fast. For non-blocking database queries is referred to the module DbRep.
      .
    </ul>
  </ul>
  </li>
  <br>

  <ul>
    <li>
    <a id="DbLog-get-ReadingsMinVal" data-pattern="ReadingsMinVal.*"></a>
    <b>get &lt;name&gt; ReadingsMinVal[Timestamp] &lt;Device&gt; &lt;Reading&gt; &lt;default&gt; </b> <br><br>
    
    <ul>
      Determines the record with the smallest value of the specified device / reading combination from the history table. <br>
      Only the value or the combination of value and timestamp is returned as string
      "&lt;Wert&gt; , &lt;Timestamp&gt;". <br>
      &lt;default&gt; specifies a defined return value if no value can be determined.
      <br>
      <br>

      <b>Note:</b> <br>
      This database retrieval works blocking and influences FHEM if the database does not respond or not responds
      sufficiently fast. For non-blocking database queries is referred to the module DbRep.
    </ul>
  </ul>
  </li>
  <br>

  <ul>
    <li>
    <a id="DbLog-get-ReadingsAvgVal"></a>
    <b>get &lt;name&gt; ReadingsAvgVal &lt;Device&gt; &lt;Reading&gt; &lt;default&gt; </b> <br><br>
    
    <ul>
      Determines the average value of the specified Device / Reading combination from the history table. <br>
      The simple arithmetic average value is returned. <br>
      &lt;default&gt; specifies a defined return value if no value can be determined.
      <br>
      <br>

      <b>Note:</b> <br>
      This database retrieval works blocking and influences FHEM if the database does not respond or not responds
      sufficiently fast. For non-blocking database queries is referred to the module DbRep.
    </ul>
  </ul>
  </li>
  <br>

  <ul>
    <li>
    <a id="DbLog-get-ReadingsVal" data-pattern="ReadingsVal.*"></a>
    <b>get &lt;name&gt; ReadingsVal[Timestamp] &lt;Device&gt; &lt;Reading&gt; &lt;default&gt; </b> <br><br>
    
    <ul>
      Reads the last (newest) record stored in the history table of the specified Device / Reading
      combination. <br>
      Only the value or the combination of value and timestamp is returned as string
      "&lt;Wert&gt; , &lt;Timestamp&gt;". <br>
      &lt;default&gt; specifies a defined return value if no value can be determined.
      <br>
      <br>

      <b>Note:</b> <br>
      This database retrieval works blocking and influences FHEM if the database does not respond or not responds
      sufficiently fast. For non-blocking database queries is referred to the module DbRep.
    </ul>
  </ul>
  </li>
  <br>

  <ul>
    <li>
    <a id="DbLog-get-ReadingsTimestamp"></a>
    <b>get &lt;name&gt; ReadingsTimestamp &lt;Device&gt; &lt;Reading&gt; &lt;default&gt; </b> <br><br>
    
    <ul>
      Reads the timestamp of the last (newest) record stored in the history table of the specified
      Device/Reading combination and returns this value. <br>
      &lt;default&gt; specifies a defined return value if no value is found in the database.
      <br>
      <br>

      <b>Note:</b> <br>
      This database retrieval works blocking and influences FHEM if the database does not respond or not responds
      sufficiently fast. For non-blocking database queries is referred to the module DbRep.
    </ul>
  </ul>
  </li>
  <br>

  <ul>
    <li>
    <a id="DbLog-get-retrieve"></a>
    <b>get &lt;name&gt; retrieve &lt;querytype&gt; &lt;device|table&gt; &lt;reading&gt; &lt;from&gt; &lt;to&gt; &lt;offset&gt; &lt;limit&gt; </b> <br><br>

    <ul>
      Reads data from the database table history and returns the results formatted as JSON. <br>
      The query method or the desired query result is determined by the specified &lt;querytype&gt;. <br>
      Each &lt;querytype&gt; may require additional parameters according to the following table. Parameters not entered
      must always be entered as "" if another parameter is entered afterwards.
      <br>
      <br>

      <ul>
       <table>
       <colgroup> <col width=15%> <col width=85%> </colgroup>
       <tr><td><b>alldevices</b>   </td><td>Determines all devices stored in the database.                                           </td></tr>
       <tr><td><b>allreadings</b>  </td><td>Determines all readings stored in the database for a specific device.                    </td></tr>
       <tr><td>                    </td><td>required parameters: &lt;device&gt;                                                      </td></tr>
       <tr><td><b>count</b>        </td><td>Returns the number of records of the specified table.                                    </td></tr>
       <tr><td>                    </td><td>required parameters: &lt;table&gt; (history or current)                                  </td></tr>
       <tr><td><b>fetchrows</b>    </td><td>Determines the stored records of a certain period.                                       </td></tr>
       <tr><td>                    </td><td>The number of records in the defined period is returned as the "totalcount" key.         </td></tr>
       <tr><td>                    </td><td>required parameters: &lt;from&gt;, &lt;to&gt;, &lt;offset&gt;, &lt;limit&gt;             </td></tr>
       <tr><td><b>last</b>         </td><td>Lists the last 10 saved events.                                                          </td></tr>
       <tr><td>                    </td><td>possible parameters: &lt;limit&gt; (overwrites the default 10)                           </td></tr>
       <tr><td><b>timerange</b>    </td><td>Determines the stored data sets of the specified Device / Reading combination.           </td></tr>
       <tr><td>                    </td><td>required parameters: &lt;device&gt;, &lt;reading&gt;, &lt;from&gt;, &lt;to&gt;           </td></tr>
       <tr><td><b>hourstats</b>    </td><td>Calculates the statistics SUM, AVG, MIN, MAX, COUNT for one hour.                        </td></tr>
       <tr><td>                    </td><td>required parameters: &lt;device&gt;, &lt;reading&gt;, &lt;from&gt;, &lt;to&gt;           </td></tr>
       <tr><td><b>daystats</b>     </td><td>Calculates the statistics SUM, AVG, MIN, MAX, COUNT for one day.                         </td></tr>
       <tr><td>                    </td><td>required parameters: &lt;device&gt;, &lt;reading&gt;, &lt;from&gt;, &lt;to&gt;           </td></tr>
       <tr><td><b>weekstats</b>    </td><td>Calculates the statistics SUM, AVG, MIN, MAX, COUNT for one week.                        </td></tr>
       <tr><td>                    </td><td>required parameters: &lt;device&gt;, &lt;reading&gt;, &lt;from&gt;, &lt;to&gt;           </td></tr>
       <tr><td><b>monthstats</b>   </td><td>Calculates the statistics SUM, AVG, MIN, MAX, COUNT for one month.                       </td></tr>
       <tr><td>                    </td><td>required parameters: &lt;device&gt;, &lt;reading&gt;, &lt;from&gt;, &lt;to&gt;           </td></tr>
       <tr><td><b>yearstats</b>    </td><td>Calculates the statistics SUM, AVG, MIN, MAX, COUNT for one year.                        </td></tr>
       <tr><td>                    </td><td>required parameters: &lt;device&gt;, &lt;reading&gt;, &lt;from&gt;, &lt;to&gt;           </td></tr>
       </table>
      </ul>
      <br>

      <b>Note:</b> <br>
      This database retrieval works blocking and influences FHEM if the database does not respond or not responds
      sufficiently fast. For non-blocking database queries is referred to the module DbRep.
      <br>
      <br>

      <b>Examples:</b>
      <ul>
        <li><code>get LogSQLITE3 retrieve alldevices </code>
        </li>

        <li><code>get LogSQLITE3 retrieve allreadings MySTP_5000 </code>
        </li>

        <li><code>get LogSQLITE3 retrieve last "" "" "" "" "" 50 </code>
        </li>

        <li><code>get LogSQLITE3 retrieve count history </code>
        </li>

        <li><code>get LogSQLITE3 retrieve timerange MySTP_5000 etotal 2023-01-01_00:00:00 2023-01-25_00:00:00 </code>
        </li>

        <li><code>get LogSQLITE3 retrieve fetchrows MySTP_5000 "" 2023-01-01_00:00:00 2023-01-25_00:00:00 0 100 </code>
        </li>

        <li><code>get LogSQLITE3 retrieve fetchrows "" etotal 2023-01-01_00:00:00 2023-01-25_00:00:00 0 100 </code>
        </li>

        <li><code>get LogSQLITE3 retrieve hourstats MySTP_5000 etotal 2023-01-01_00:00:00 2023-01-25_00:00:00 </code>
        </li>
      </ul>
    </ul>
  </ul>
  </li>
  <br>
  <br>

<b>Get</b> for the use of SVG plots
  <br>
  <br>

  <ul>
    <li><b>get &lt;name&gt; &lt;in&gt; &lt;out&gt; &lt;from&gt; &lt;to&gt; &lt;column_spec&gt; </b> <br><br>

    Read data from the Database used by frontends to plot data without direct access to the Database. <br>
    <br>

    <ul>
      <li>&lt;in&gt;<br>
        A parameter to establish compatibility with Filelog. <br>
        In the definition of an SVG device this parameter corresponds to the specification of :&lt;logfile&gt; at the end of the definition.<br>
        The following characteristics are allowed:<br>
        <ul>
          <li>current: the values are read from the "current" table.                                                    </li>
          <li>history: the values are read from the "history" table.                                                    </li>
          <li>table_&lt;table&gt;: the values are read from the specified alternative table. The table (name)
                                   must be created in the database with lowercase letters. <br>
                                   (example: table_energy, "energy" is the alternative table created in the database)   </li>
          <li>-: identical as "history                                                                                  </li>
        </ul>
      </li>
      <br>

      <li>&lt;out&gt;<br>
        A dummy parameter for FileLog compatibility. Setting by default to <code>-</code>
        to check the output for plot-computing.<br>
        Set it to the special keyword
        <code>all</code> to get all columns from Database.
        <ul>
          <li>ALL: get all colums from table, including a header</li>
          <li>Array: get the columns as array of hashes</li>
          <li>INT: internally used by generating plots</li>
          <li>-: default</li>
        </ul>
      </li>
      <br>

      <li>&lt;from&gt; / &lt;to&gt;<br>
        Used to select the data. Please use the following timeformat or
        an initial substring of it:<br>
        <ul>
          <code>YYYY-MM-DD_HH24:MI:SS</code>
        </ul>
      </li>
      <br>

      <li>&lt;column_spec&gt;<br>
        For each column_spec return a set of data separated by
        a comment line on the current connection.<br>
        <br>

        <b>Syntax:</b> &lt;device&gt;:&lt;reading&gt;:&lt;default&gt;:&lt;fn&gt;:&lt;regexp&gt; <br>
        <br>

        <ul>
          <li>&lt;device&gt;<br>
            The name of the device. Case sensitive. Using a the joker "%" is supported.
          </li>
          <br>

          <li>&lt;reading&gt;<br>
            The reading of the given device to select. Case sensitive. Using a the joker "%" is supported.
          </li>
          <br>

          <li>&lt;default&gt;<br>
            no implemented yet
          </li>
          <br>

          <li>&lt;fn&gt;
            One of the following:
            <ul>
              <li>int<br>
                Extract the integer at the beginning of the string. Used e.g.
                for constructs like 10%
              </li>
              <br>

              <li>int&lt;digit&gt;<br>
                Extract the decimal digits including negative character and
                decimal point at the beginning og the string. Used e.g.
                for constructs like 15.7&deg;C
              </li>
              <br>

              <li>delta-h / delta-d<br>
                Return the delta of the values for a given hour or a given day.
                Used if the column contains a counter, as is the case for the
                KS300 rain column.
              </li>
              <br>

              <li>delta-ts<br>
                Replaced the original value with a measured value of seconds since
                the last and the actual logentry.
              </li>
              <br>

            </ul>
            </li>

            <li>&lt;regexp&gt;<br>
              The string is evaluated as a perl expression.  The regexp is executed
              before &lt;fn&gt; parameter.<br>
              Note: The string/perl expression cannot contain spaces,
              as the part after the space will be considered as the
              next column_spec.<br>
              <br>

              <b>Keywords</b>
              <li>$val is the current value returned from the Database.</li>
              <li>$ts is the current timestamp returned from the Database.</li>
              <li>This Logentry will not print out if $val contains th keyword "hide".</li>
              <li>This Logentry will not print out and not used in the following processing
                  if $val contains th keyword "ignore". </li>
            </li>
        </ul>
        </li>
      </ul>
    <br><br>

    Examples:
      <ul>
        <li>
          <code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature</code>
        </li>
        <br>

        <li><code>get myDbLog current ALL - - %:temperature</code><br>
            you will get all actual readings "temperature" from all logged devices.
            Be careful by using "history" as inputfile because a long execution time will be expected!
        </li>
        <br>

        <li><code>get myDbLog - - 2012-11-10_10 2012-11-10_20 KS300:temperature::int1</code><br>
           like from 10am until 08pm at 10.11.2012
        </li>
        <br>

        <li>
          <code>get myDbLog - all 2012-11-10 2012-11-20 KS300:temperature</code>
        </li>
        <br>

        <li>
          <code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature KS300:rain::delta-h KS300:rain::delta-d</code>
        </li>
        <br>

        <li><code>get myDbLog - - 2012-11-10 2012-11-20 MyFS20:data:::$val=~s/(on|off).*/$1eq"on"?1:0/eg</code><br>
           return 1 for all occurance of on* (on|on-for-timer etc) and 0 for all off*
        </li>
        <br>

        <li><code>get myDbLog - - 2012-11-10 2012-11-20 Bodenfeuchte:data:::$val=~s/.*B:\s([-\.\d]+).*/$1/eg</code><br>
           Example of OWAD: value like this: <code>"A: 49.527 % B: 66.647 % C: 9.797 % D: 0.097 V"</code><br>
           and output for port B is like this: <code>2012-11-20_10:23:54 66.647</code>
        </li>
        <br>

        <li><code>get DbLog - - 2013-05-26 2013-05-28 Pumpe:data::delta-ts:$val=~s/on/hide/</code><br>
           Setting up a "Counter of Uptime". The function delta-ts gets the seconds between the last and the
           actual logentry. The keyword "hide" will hide the logentry of "on" because this time
           is a "counter of Downtime"
        </li>

      </ul>
    </li>
    </ul>
    <br>

  <b>Get</b> when used for webcharts
  <br>
  <br>

  <ul>
    <li><b>get &lt;name&gt; &lt;in&gt; &lt;out&gt; &lt;from&gt;
          &lt;to&gt; &lt;device&gt; &lt;querytype&gt; &lt;xaxis&gt; &lt;yaxis&gt; &lt;savename&gt; &lt;chartconfig&gt; &lt;pagingstart&gt; &lt;paginglimit&gt; </b> <br><br>

    Query the Database to retrieve JSON-Formatted Data, which is used by the charting frontend
    (<a href="https://wiki.fhem.de/wiki/Neues_Charting_Frontend">German Wiki: Neues Charting Frontend</a>).
    <br>
    <br>

    <ul>
      <li>&lt;name&gt;<br>
        The name of the defined DbLog, like it is given in fhem.cfg.</li>
      <br>

      <li>&lt;in&gt;<br>
        Always set to <code>-</code></li>
      <br>

      <li>&lt;out&gt;<br>
        Is to be set to <code>webchart</code>.
      </li>
      <br>

      <li>&lt;from&gt; / &lt;to&gt;<br>
        Used to select the data. Please use the following timeformat:<br>
        <ul><code>YYYY-MM-DD_HH24:MI:SS</code></ul></li>
      <br>

      <li>&lt;device&gt;<br>
        A string which represents the device to query.</li>
      <br>

      <li>&lt;querytype&gt;<br>
        A string which represents the method the query should use. Actually supported values are: <br>
        <code>getreadings</code> to retrieve the possible readings for a given device<br>
        <code>getdevices</code> to retrieve all available devices<br>
        <code>timerange</code> to retrieve charting data, which requires a given xaxis, yaxis, device, to and from<br>
        <code>savechart</code> to save a chart configuration in the database. Requires a given xaxis, yaxis, device, to and from, and a 'savename' used to save the chart<br>
        <code>deletechart</code> to delete a saved chart. Requires a given id which was set on save of the chart<br>
        <code>getcharts</code> to get a list of all saved charts.<br>
        <code>getTableData</code> to get jsonformatted data from the database. Uses paging Parameters like start and limit.<br>
        <code>hourstats</code> to get statistics for a given value (yaxis) for an hour.<br>
        <code>daystats</code> to get statistics for a given value (yaxis) for a day.<br>
        <code>weekstats</code> to get statistics for a given value (yaxis) for a week.<br>
        <code>monthstats</code> to get statistics for a given value (yaxis) for a month.<br>
        <code>yearstats</code> to get statistics for a given value (yaxis) for a year.<br>
      </li>
      <br>

      <li>&lt;xaxis&gt;<br>
        A string which represents the xaxis. It must be a valid field name, typically 'TIMESTAMP', of the history table.
      </li>
      <br>

      <li>&lt;yaxis&gt;<br>
         A string representing the Y-axis to be set to the name of the reading to be evaluated.
      </li>
      <br>

      <li>&lt;savename&gt;<br>
         A string which represents the name a chart will be saved with.
      </li>
      <br>

      <li>&lt;chartconfig&gt;<br>
         A jsonstring which represents the chart to save.
      </li>
      <br>

      <li>&lt;pagingstart&gt;<br>
         An integer used to determine the start for the sql used for query 'getTableData'.
      </li>
      <br>

      <li>&lt;paginglimit&gt;<br>
         An integer used to set the limit for the sql used for query 'getTableData'.
      </li>
      <br>
    </ul>

    <b>Examples:</b>
      <ul>
        <li><code>get logdb - webchart "" "" "" getcharts</code><br>
            Retrieves all saved charts from the Database</li>
            <br>
        <li><code>get logdb - webchart "" "" "" getdevices</code><br>
            Retrieves all available devices from the Database</li>
            <br>
        <li><code>get logdb - webchart "" "" ESA2000_LED_011e getreadings</code><br>
            Retrieves all available Readings for a given device from the Database</li>
            <br>
        <li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e timerange TIMESTAMP day_kwh</code><br>
            Retrieves charting data, which requires a given xaxis, yaxis, device, to and from<br>
            Will ouput a JSON like this: <code>[{'TIMESTAMP':'2013-02-11 00:10:10','VALUE':'0.22431388090756'},{'TIMESTAMP'.....}]</code></li>
            <br>
        <li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e savechart TIMESTAMP day_kwh tageskwh</code><br>
            Will save a chart in the database with the given name and the chart configuration parameters</li>
            <br>
        <li><code>get logdb - webchart "" "" "" deletechart "" "" 7</code><br>
            Will delete a chart from the database with the given id</li>
      </ul>
    </li>
    </ul>
    <br>

  <a id="DbLog-attr"></a>
  <b>Attributes</b>
  <br>
  <br>

  <ul>
    <a id="DbLog-attr-addStateEvent"></a>
    <li><b>addStateEvent [0|1] </b> <br><br>
    <ul>

      As you probably know the event associated with the state Reading is special, as the "state: "
      string is stripped, i.e event is not "state: on" but just "on". <br>
      Mostly it is desireable to get the complete event without "state: " stripped, so it is the default behavior of DbLog.
      That means you will get state-event complete as "state: xxx". <br>
      In some circumstances, e.g. older or special modules, it is a good idea to set addStateEvent to "0".
      Try it if you have trouble with the default adjustment.
      <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-asyncMode"></a>
    <li><b>asyncMode [0|1] </b> <br><br>
    <ul>

      This attribute sets the processing procedure according to which the DbLog device writes the data to the database. <br>
      DbLog uses a sub-process to write the log data into the database and processes the data
      generally not blocking for FHEM. <br>
      Thus, the writing process to the database is generally not blocking and FHEM is not affected in the case
      the database is not performing or is not available (maintenance, error condition). <br>
      (default: 0)
      <br><br>

      <ul>
       <table>
       <colgroup> <col width=5%> <col width=95%> </colgroup>
       <tr><td> 0 - </td><td><b>Synchronous log mode.</b> The data to be logged is only briefly cached and immediately                                              </td></tr>
       <tr><td>     </td><td>written to the database.                                                                                                               </td></tr>
       <tr><td>     </td><td><b>Advantages:</b>                                                                                                                     </td></tr>
       <tr><td>     </td><td>In principle, the data is immediately available in the database.                                                                       </td></tr>
       <tr><td>     </td><td>Very little to no data is lost when FHEM crashes.                                                                                      </td></tr>
       <tr><td>     </td><td><b>Disadvantages:</b>                                                                                                                  </td></tr>
       <tr><td>     </td><td>An alternative storage in the file system (in case of database problems) is not supported.                                             </td></tr>
       <tr><td>     </td><td>                                                                                                                                       </td></tr>
       <tr><td> 1 - </td><td><b>Asynchroner Log-Modus.</b> The data to be logged is first cached in a memory cache and written to the database                      </td></tr>
       <tr><td>     </td><td>depending on a <a href="#DbLog-attr-syncInterval">time interval</a> or <a href="#DbLog-attr-cacheLimit">fill level</a> of the cache.   </td></tr>
       <tr><td>     </td><td><b>Advantages:</b>                                                                                                                     </td></tr>
       <tr><td>     </td><td>The data is cached and will not be lost if the database is unavailable or malfunctions.                                                </td></tr>
       <tr><td>     </td><td>The alternative storage of data in the file system is supported.                                                                       </td></tr>
       <tr><td>     </td><td><b>Disadvantages:</b>                                                                                                                  </td></tr>
       <tr><td>     </td><td>The data is available in the database with a time delay.                                                                               </td></tr>
       <tr><td>     </td><td>If FHEM crashes, all data cached in the memory will be lost.                                                                           </td></tr>
       </table>
      </ul>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-commitMode"></a>
    <li><b>commitMode [basic_ta:on | basic_ta:off | ac:on_ta:on | ac:on_ta:off | ac:off_ta:on] </b> <br><br>
    <ul>

      Change the usage of database autocommit- and/or transaction- behavior. <br>
      If transaction "off" is used, not saved datasets are not returned to cache in asynchronous mode. <br>
      This attribute is an advanced feature and should only be used in a concrete situation or support case. <br><br>

      <ul>
      <li>basic_ta:on   - autocommit server basic setting / transaktion on (default) </li>
      <li>basic_ta:off  - autocommit server basic setting / transaktion off </li>
      <li>ac:on_ta:on   - autocommit on / transaktion on </li>
      <li>ac:on_ta:off  - autocommit on / transaktion off </li>
      <li>ac:off_ta:on  - autocommit off / transaktion on (autocommit "off" set transaktion "on" implicitly) </li>
      </ul>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-cacheEvents"></a>
    <li><b>cacheEvents [2|1|0] </b> <br><br>
    <ul>

      <ul>
       <table>
       <colgroup> <col width=5%> <col width=95%> </colgroup>
       <tr><td> 0 - </td><td>No events are generated for CacheUsage.                                                            </td></tr>
       <tr><td> 1 - </td><td>Events are generated for the Reading CacheUsage when a new record is added to the cache.           </td></tr>
       <tr><td> 2 - </td><td>Events are generated for the Reading CacheUsage when the write cycle to the database starts in     </td></tr>
       <tr><td>     </td><td>asynchronous mode. CacheUsage contains the number of records in the cache at this time.            </td></tr>
       </table>
      </ul>

      (default: 0) <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-cacheLimit"></a>
     <li><b>cacheLimit &lt;n&gt; </b> <br><br>
     <ul>

       In asynchronous logging mode the content of cache will be written into the database and cleared if the number &lt;n&gt; datasets
       in cache has reached. Thereby the timer of asynchronous logging mode will be set new to the value of
       attribute "syncInterval". In case of error the next write attempt will be started at the earliest after
       syncInterval/2. <br>
       (default: 500)
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-cacheOverflowThreshold"></a>
     <li><b>cacheOverflowThreshold &lt;n&gt; </b> <br><br>
     <ul>

       In asynchronous log mode, sets the threshold of &lt;n&gt; records above which the cache contents are exported to a
       file instead of writing the data to the database. <br>
       The executed function corresponds to the set command "exportCache purgecache" and uses its settings.
       <br><br>

       This attribute can be used to prevent an overload of the server memory if the database is not available for a
       longer period of time (e.g. in case of error or maintenance). If the attribute value is less than or equal to the
       value of the cacheLimit attribute, the value of cacheLimit is used for cacheOverflowThreshold. <br>
       In this case the cache will <b>always</b> be written to a file instead of to the database if the threshold value
       has been reached. <br>
       With this setting, the data can be written to one or more files in order to import them into the database
       at a later time with the set command "importCachefile".
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-colEvent"></a>
     <li><b>colEvent &lt;n&gt; </b> <br><br>
     <ul>

       The field length of database field EVENT is adapted user-specifically. The attribute can be used to change the 
       default value in the module if the field length in the database was changed manually. 
       With colEvent=0 the database field EVENT is not filled. <br>
       <b>Note:</b> <br>
       With set attribute all field length limits are also valid for SQLite DB as shown in Internal COLUMNS! <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-colReading"></a>
     <li><b>colReading &lt;n&gt; </b> <br><br>
     <ul>

       The field length of database field READING is adapted user-specifically. BThe attribute can be used to change the 
       default value in the module if the field length in the database was changed manually. 
       With colReading=0 the database field READING is not filled. <br>
       <b>Note:</b> <br>
       With set attribute all field length limits are also valid for SQLite DB as shown in Internal COLUMNS! <br>
     </ul>
     </li>
  </ul>
  <br>
  
  <ul>
     <a id="DbLog-attr-colType"></a>
     <li><b>colType &lt;n&gt; </b> <br><br>

     <ul>
       The field length for the database field TYPE is adapted user-specifically. The attribute can be used to change the 
       default value in the module if the field length in the database was changed manually. 
       With colType=0 the database field TYPE is not filled. <br>
       <b>Note:</b> <br>
       With set attribute all field length limits are also valid for SQLite DB as shown in Internal COLUMNS! <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-colValue"></a>
     <li><b>colValue &lt;n&gt; </b> <br><br>
     <ul>

       The field length of database field VALUE is adapted user-specifically. The attribute can be used to change the 
       default value in the module if the field length in the database was changed manually. 
       With colValue=0 the database field VALUE is not filled. <br>
       <b>Note:</b> <br>
       With set attribute all field length limits are also valid for SQLite DB as shown in Internal COLUMNS! <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-convertTimezone"></a>
     <li><b>convertTimezone [UTC | none] </b> <br><br>
     <ul>

       UTC - the local timestamp of the event will be converted to UTC. <br>
       (default: none) <br><br>

       <b>Note:</b> <br>
       The Perl modules 'DateTime' and 'DateTime::Format::Strptime' must be installed!
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-DbLogType"></a>
     <li><b>DbLogType [Current|History|Current/History] </b> <br><br>
     <ul>

       This attribute determines which table or which tables in the database are wanted to use. If the attribute isn't set,
       the adjustment <i>history</i> will be used as default. <br>


       The meaning of the adjustments in detail are: <br><br>

       <ul>
       <table>
       <colgroup> <col width=10%> <col width=90%> </colgroup>
       <tr><td> <b>Current</b>            </td><td>Events are only logged into the current-table.
                                                   The entries of current-table will evaluated with SVG-creation.  </td></tr>
       <tr><td> <b>History</b>            </td><td>Events are only logged into the history-table. No dropdown list with proposals will created with the
                                                   SVG-creation.   </td></tr>
       <tr><td> <b>Current/History</b>    </td><td>Events will be logged both the current- and the history-table.
                                                   The entries of current-table will evaluated with SVG-creation.  </td></tr>
       <tr><td> <b>SampleFill/History</b> </td><td>Events are only logged into the history-table. The entries of current-table will evaluated with SVG-creation
                                                   and can be filled up with a customizable extract of the history-table by using a
                                                   <a href="http://fhem.de/commandref.html#DbRep">DbRep-device</a> command
                                                   "set &lt;DbRep-name&gt; tableCurrentFillup"  (advanced feature).  </td></tr>
       </table>
       </ul>
       <br>
       <br>

       <b>Note:</b> <br>
       The current-table has to be used to get a Device:Reading-DropDown list when a SVG-Plot will be created. <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-DbLogSelectionMode"></a>
    <li><b>DbLogSelectionMode [Exclude|Include|Exclude/Include] </b> <br><br>
    <ul>

      This attribute, specific to DbLog devices, influences how the device-specific attributes
      <a href="#DbLog-attr-DbLogExclude">DbLogExclude</a> and <a href="#DbLog-attr-DbLogInclude">DbLogInclude</a>
      are evaluated. DbLogExclude and DbLogInclude are set in the source devices. <br>
      If the DbLogSelectionMode attribute is not set, "Exclude" is the default.
      <br><br>

      <ul>
        <li><b>Exclude:</b> Readings are logged if they match the regex specified in the DEF. Excluded are
                            the readings that match the regex in the DbLogExclude attribute. <br>
                            The DbLogInclude attribute is not considered in this case.
                            </li>
                            <br>
        <li><b>Include:</b> Only readings are logged which are included via the regex in the attribute DbLogInclude
                            are included. <br>
                            The DbLogExclude attribute is not considered in this case, nor is the regex in DEF.
                            </li>
                            <br>
        <li><b>Exclude/Include:</b> Works basically like "Exclude", except that both the attribute DbLogExclude
                                    attribute and the DbLogInclude attribute are checked.
                                    Readings that were excluded by DbLogExclude, but are included by DbLogInclude
                                    are therefore still included in the logging.
                                    </li>
         </ul>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-DbLogInclude"></a>
    <li><b>DbLogInclude Regex[:MinInterval][:force],[Regex[:MinInterval][:force]], ... </b> <br><br>
    <ul>

      The DbLogInclude attribute defines the readings to be stored in the database. <br>
      The definition of the readings to be stored is done by a regular expression and all readings that match the regular
      expression are stored in the database. <br>

      The optional &lt;MinInterval&gt; addition specifies that a value is saved when at least &lt;MinInterval&gt;
      seconds have passed since the last save. <br>

      Regardless of the expiration of the interval, the reading is saved if the value of the reading has changed. <br>
      With the optional modifier "force" the specified interval &lt;MinInterval&gt; can be forced to be kept even
      if the value of the reading has changed since the last storage.
      <br><br>

      <ul>
      <pre>
        | <b>Modifier</b> |            <b>within interval</b>           | <b>outside interval</b> |
        |          | Value equal        | Value changed   |                  |
        |----------+--------------------+-----------------+------------------|
        | &lt;none&gt;   | ignore             | store           | store            |
        | force    | ignore             | ignore          | store            |
      </pre>
      </ul>

      <br>
      <b>Notes: </b> <br>
      The DbLogInclude attribute is propagated in all devices when DbLog is used. <br>
      The <a href="#DbLog-attr-DbLogSelectionMode">DbLogSelectionMode</a> attribute must be set accordingly
      to enable DbLogInclude. <br>
      With the <a href="#DbLog-attr-defaultMinInterval">defaultMinInterval</a> attribute a default for
      &lt;MinInterval&gt; can be specified.
      <br><br>

      <b>Example</b> <br>
      <code>attr MyDevice1 DbLogInclude .*</code> <br>
      <code>attr MyDevice2 DbLogInclude state,(floorplantext|MyUserReading):300,battery:3600</code> <br>
      <code>attr MyDevice2 DbLogInclude state,(floorplantext|MyUserReading):300:force,battery:3600:force</code>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-DbLogExclude"></a>
    <li><b>DbLogExclude Regex[:MinInterval][:force],[regex[:MinInterval][:force]] ... </b> <br><br>
    <ul>

      The DbLogExclude attribute defines the readings that <b>should not</b> be stored in the database. <br>

      The definition of the readings to be excluded is done via a regular expression and all readings matching the
      regular expression are excluded from logging to the database. <br>

      Readings that have not been excluded via the regex are logged in the database. The behavior of the
      storage is controlled with the following optional specifications. <br>
      The optional &lt;MinInterval&gt; addition specifies that a value is saved when at least &lt;MinInterval&gt;
      seconds have passed since the last storage. <br>

      Regardless of the expiration of the interval, the reading is saved if the value of the reading has changed. <br>
      With the optional modifier "force" the specified interval &lt;MinInterval&gt; can be forced to be kept even
      if the value of the reading has changed since the last storage.
      <br><br>

      <ul>
      <pre>
        | <b>Modifier</b> |            <b>within interval</b>           | <b>outside interval</b> |
        |          | Value equal        | Value changed   |                  |
        |----------+--------------------+-----------------+------------------|
        | &lt;none&gt;   | ignore             | store           | store            |
        | force    | ignore             | ignore          | store            |
      </pre>
      </ul>

      <br>
      <b>Notes: </b> <br>
      The DbLogExclude attribute is propagated in all devices when DbLog is used. <br>
      The <a href="#DbLog-attr-DbLogSelectionMode">DbLogSelectionMode</a> attribute can be set appropriately
      to disable DbLogExclude. <br>
      With the <a href="#DbLog-attr-defaultMinInterval">defaultMinInterval</a> attribute a default for
      &lt;MinInterval&gt; can be specified.
      <br><br>

      <b>Example</b> <br>
      <code>attr MyDevice1 DbLogExclude .*</code> <br>
      <code>attr MyDevice2 DbLogExclude state,(floorplantext|MyUserReading):300,battery:3600</code> <br>
      <code>attr MyDevice2 DbLogExclude state,(floorplantext|MyUserReading):300:force,battery:3600:force</code>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-DbLogValueFn"></a>
     <li><b>DbLogValueFn {} </b> <br><br>
     <ul>

       If DbLog is used, the <i>DbLogValueFn</i> attribute is propagated in all devices.
       This attribute is set in the <b>source devices</b> and allows to change the values before logging
       or exclude the record from logging. <br><br>

       The variables $TIMESTAMP, $READING, $VALUE (value of the reading) and $UNIT (unit of the reading value)
       can be accessed and modified before logging to the database. <br>
       Read access is available to $DEVICE (the name of the source device), $EVENT, $LASTTIMESTAMP, and $LASTVALUE. <br><br>

       The variables $LASTTIMESTAMP and $LASTVALUE contain time and value of the last logged record of
       $DEVICE / $READING. <br>
       If $TIMESTAMP is to be changed, the form "yyyy-mm-dd hh:mm:ss" must be followed.
       Otherwise the changed $TIMESTAMP variable will not be applied.
       By setting the variable "$IGNORE=1" the record is excluded from logging. <br><br>

       The device specific function in "DbLogValueFn" is applied to the record before the function in the "valueFn"
       attribute of the DbLog device.
       <br><br>

       <b>Example</b> <br>
<pre>
attr SMA_Energymeter DbLogValueFn
{
  if ($READING eq "Bezug_WirkP_Kosten_Diff") {
    $UNIT="Diff-W";
  }
  if ($READING =~ /Einspeisung_Wirkleistung_Zaehler/ && $VALUE < 2) {
    $IGNORE=1;
  }
}
</pre>
     </ul>
     </li>
  </ul>

  <ul>
    <a id="DbLog-attr-dbSchema"></a>
    <li><b>dbSchema &lt;schema&gt; </b> <br><br>
    <ul>

      This attribute is available for database types MySQL/MariaDB and PostgreSQL. The table names (current/history) are
      extended by its database schema. It is an advanced feature and normally not necessary to set.
      <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-defaultMinInterval"></a>
    <li><b>defaultMinInterval &lt;devspec&gt;::&lt;MinInterval&gt;[::force],[&lt;devspec&gt;::&lt;MinInterval&gt;[::force]] ... </b> <br><br>
    <ul>

      With this attribute a default minimum interval for <a href="http://fhem.de/commandref.html#devspec">devspec</a> is defined.
      If a defaultMinInterval is set, the logentry is dropped if the defined interval is not reached <b>and</b> the value vs.
      lastvalue is equal. <br>
      If the optional parameter "force" is set, the logentry is also dropped even though the value is not
      equal the last one and the defined interval is not reached. <br>
      Potential set DbLogExclude / DbLogInclude specifications in source devices are having priority over defaultMinInterval
      and are <b>not</b> overwritten by this attribute. <br>
      This attribute can be specified as multiline input. <br><br>

      <b>Examples</b> <br>
      <code>attr dblog defaultMinInterval .*::120::force </code> <br>
      # Events of all devices are logged only in case of 120 seconds are elapsed to the last log entry (reading specific) independent of a possible value change. <br>
      <code>attr dblog defaultMinInterval (Weather|SMA)::300 </code> <br>
      # Events of devices "Weather" and "SMA" are logged only in case of 300 seconds are elapsed to the last log entry (reading specific) and the value is equal to the last logged value. <br>
      <code>attr dblog defaultMinInterval TYPE=CUL_HM::600::force </code> <br>
      # Events of all devices of Type "CUL_HM" are logged only in case of 600 seconds are elapsed to the last log entry (reading specific) independent of a possible value change.
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-excludeDevs"></a>
     <li><b>excludeDevs &lt;devspec1&gt;[#Reading],&lt;devspec2&gt;[#Reading],&lt;devspec...&gt; </b> <br><br>
     <ul>

       The device/reading-combinations "devspec1#Reading", "devspec2#Reading" up to "devspec.." are globally excluded from
       logging into the database. <br>
       The specification of a reading is optional. <br>
       Thereby devices are explicit and consequently excluded from logging without consideration of another excludes or
       includes (e.g. in DEF).
       The devices to exclude can be specified as <a href="#devspec">device-specification</a>.
       <br><br>

       <b>Examples</b> <br>
       <code>
       attr &lt;device&gt; excludeDevs global,Log.*,Cam.*,TYPE=DbLog
       </code><br>
       # The devices global respectively devices starting with "Log" or "Cam" and devices with Type=DbLog are excluded from database logging. <br>
       <code>
       attr &lt;device&gt; excludeDevs .*#.*Wirkleistung.*
       </code><br>
       # All device/reading-combinations which contain "Wirkleistung" in reading are excluded from logging. <br>
       <code>
       attr &lt;device&gt; excludeDevs SMA_Energymeter#Bezug_WirkP_Zaehler_Diff
       </code><br>
       # The event containing device "SMA_Energymeter" and reading "Bezug_WirkP_Zaehler_Diff" are excluded from logging. <br>
       </ul>
  </ul>
  </li>
  <br>

  <ul>
     <a id="DbLog-attr-expimpdir"></a>
     <li><b>expimpdir &lt;directory&gt; </b> <br><br>
     <ul>

       If the cache content will be exported by <a href="#DbLog-set-exportCache">exportCache</a> command,
       the file will be written into or read from that directory. The default directory is
       "(global->modpath)/log/".
       Make sure the specified directory is existing and writable.
       <br><br>

      <b>Example</b> <br>
      <code>
      attr &lt;device&gt; expimpdir /opt/fhem/cache/
      </code><br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-exportCacheAppend"></a>
     <li><b>exportCacheAppend [1|0] </b> <br><br>
     <ul>

       If set, the export of cache ("set &lt;device&gt; exportCache") appends the content to the newest available
       export file. If there is no exististing export file, it will be new created. <br>
       If the attribute not set, every export process creates a new export file . (default)<br/>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-insertMode"></a>
    <li><b>insertMode [1|0] </b> <br><br>
    <ul>

      Toggles the insert mode of the database interface. <br><br>

      <ul>
       <table>
       <colgroup> <col width=5%> <col width=95%> </colgroup>
       <tr><td> 0 - </td><td>The data is passed as an array to the database interface.                                               </td></tr>
       <tr><td>     </td><td>It is in most cases the most performant way to insert a lot of data into the database at once.          </td></tr>
       <tr><td> 1 - </td><td>The records are passed sequentially to the database interface and inserted into the DB.                 </td></tr>
       </table>
      </ul>
      <br>

      (default: 0)
    </ul>
  </ul>
  </li>
  <br>

  <ul>
     <a id="DbLog-attr-noSupportPK"></a>
     <li><b>noSupportPK [1|0] </b> <br><br>
     <ul>
       Deactivates the support of a set primary key by the module.<br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-plotInputFieldLength"></a>
     <li><b>plotInputFieldLength &lt;Ganzzahl&gt; </b> <br><br>
     <ul>
        Width of the Plot Editor input fields for Device:Reading and Function. <br>
        If the drop-down list is used as input help for Device:Reading, the width of the field is
        set automatically. <br>
        (default: 40)
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-SQLiteCacheSize"></a>
     <li><b>SQLiteCacheSize &lt;number of memory pages used for caching&gt; </b> <br><br>
     <ul>
       The default is about 4MB of RAM to use for caching (page_size=1024bytes, cache_size=4000).<br>
       Embedded devices with scarce amount of RAM can go with 1000 pages or less. This will impact
       the overall performance of SQLite. <br>
       (default: 4000)
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-SQLiteJournalMode"></a>
     <li><b>SQLiteJournalMode [WAL|off] </b> <br><br>
     <ul>

       Determines how SQLite databases are opened. Generally the Write-Ahead-Log (<b>WAL</b>) is the best choice for robustness
       and data integrity.<br>
       Since WAL about doubles the spaces requirements on disk it might not be the best fit for embedded devices
       using a RAM backed disk. <b>off</b> will turn the journaling off. In case of corruption, the database probably
       won't be possible to repair and has to be recreated! <br>
       (default: WAL)
     </ul>
     </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-syncEvents"></a>
    <li><b>syncEvents [1|0] </b> <br><br>
    <ul>

      events of reading syncEvents will be created. <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-showproctime"></a>
    <li><b>showproctime [1|0] </b> <br><br>
    <ul>

      If set, the reading "sql_processing_time" shows the required processing time (in seconds) for the
      SQL execution of the executed function.
      This does not consider a single SQL statement, but the sum of all executed SQL commands within the
      respective function is considered. <br>
      The reading "background_processing_time" shows the time used in the SubProcess.
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-showNotifyTime"></a>
    <li><b>showNotifyTime [1|0] </b> <br><br>
    <ul>

      If set, the reading "notify_processing_time" shows the required processing time (in seconds) for the
      processing of the DbLog notify function. <br>
      The attribute is suitable for performance analyses and also helps to determine the differences
      in the time required for event processing in synchronous or asynchronous mode. <br>
      (default: 0)
      <br><br>

      <b>Hinweis:</b> <br>
      The reading "notify_processing_time" generates a lot of events and burdens the system. Therefore, when using the
      the event generation should be limited by setting the attribute "event-min-interval" to e.g.
      "notify_processing_time:30".
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-syncInterval"></a>
    <li><b>syncInterval &lt;n&gt; </b> <br><br>
    <ul>

      If the asynchronous mode is set in the DbLog device (asyncMode=1), this attribute sets the interval (seconds) for
      writing data to the database. <br>
      (default: 30)

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-suppressAddLogV3"></a>
    <li><b>suppressAddLogV3 [1|0] </b> <br><br>
    <ul>

      If set, verbose 3 Logfileentries done by the addLog-function will be suppressed.  <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-suppressUndef"></a>
    <li><b>suppressUndef </b> <br><br>
    <ul>

      Suppresses all undef values when returning data from the DB via get.

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-timeout"></a>
    <li><b>timeout &lt;n&gt; </b> <br><br>
    <ul>

      Sets the timeout value for the operations in the SubProcess in seconds. <br>
      If a started operation (logging, command) is not finished within the timeout value,
      the running subprocess is terminated and a new process is started. <br>
      (default: 86400)
    </ul>
  </ul>
  </li>
  <br>

  <ul>
    <a id="DbLog-attr-traceFlag"></a>
    <li><b>traceFlag &lt;ALL|SQL|CON|ENC|DBD|TXN&gt; </b> <br><br>
    <ul>

      Trace flags are used to enable tracing of specific activities within the DBI and drivers. The attribute is only used for
      tracing of errors in case of support. <br><br>

       <ul>
       <table>
       <colgroup> <col width=10%> <col width=90%> </colgroup>
       <tr><td> <b>ALL</b>            </td><td>turn on all DBI and driver flags  </td></tr>
       <tr><td> <b>SQL</b>            </td><td>trace SQL statements executed (Default) </td></tr>
       <tr><td> <b>CON</b>            </td><td>trace connection process  </td></tr>
       <tr><td> <b>ENC</b>            </td><td>trace encoding (unicode translations etc)  </td></tr>
       <tr><td> <b>DBD</b>            </td><td>trace only DBD messages  </td></tr>
       <tr><td> <b>TXN</b>            </td><td>trace transactions  </td></tr>

       </table>
       </ul>
       <br>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-traceLevel"></a>
    <li><b>traceLevel &lt;0|1|2|3|4|5|6|7&gt; </b> <br><br>
    <ul>

      Switch on the tracing function of the module. <br>
      <b>Caution !</b> The attribute is only used for tracing errors or in case of support. If switched on <b>very much entries</b>
                       will be written into the FHEM Logfile ! <br><br>

       <ul>
       <table>
       <colgroup> <col width=5%> <col width=95%> </colgroup>
       <tr><td> <b>0</b>            </td><td>Trace disabled. (Default)  </td></tr>
       <tr><td> <b>1</b>            </td><td>Trace top-level DBI method calls returning with results or errors. </td></tr>
       <tr><td> <b>2</b>            </td><td>As above, adding tracing of top-level method entry with parameters.  </td></tr>
       <tr><td> <b>3</b>            </td><td>As above, adding some high-level information from the driver
                                             and some internal information from the DBI.  </td></tr>
       <tr><td> <b>4</b>            </td><td>As above, adding more detailed information from the driver. </td></tr>
       <tr><td> <b>5-7</b>          </td><td>As above but with more and more internal information.  </td></tr>

       </table>
       </ul>
       <br>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-useCharfilter"></a>
    <li><b>useCharfilter [0|1] </b> <br><br>
    <ul>

      If set, only ASCII characters from 32 to 126 are accepted in event.
      That are the characters " A-Za-z0-9!"#$%&'()*+,-.\/:;<=>?@[\\]^_`{|}~" .<br>
      Mutated vowel and "€" are transcribed (e.g. ä to ae). (default: 0). <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-valueFn"></a>
     <li><b>valueFn {} </b> <br><br>
     <ul>

      This attribute is set in the <b>DbLog device</b> and allows to modify the values before logging
      or exclude the record from logging. <br><br>

      It is possible to access the variables $TIMESTAMP, $DEVICE (source device), $DEVICETYPE, $EVENT, $READING, 
      $VALUE (reading value) and $UNIT (unit of reading value) can be accessed and modified before logging to the database. <br>
      Read only access exists to $LASTTIMESTAMP, $LASTVALUE and $NAME (Name of the DbLog Device). <br><br>

      The variables $LASTTIMESTAMP and $LASTVALUE contain time and value of the last logged record of
      $DEVICE / $READING. <br>
      If $TIMESTAMP is to be changed, the form "yyyy-mm-dd hh:mm:ss" must be followed.
      Otherwise the changed $TIMESTAMP variable will not be applied.
      By setting the variable "$IGNORE=1" the record is excluded from logging.
      <br><br>

      <b>Examples</b> <br>
      <code>
      attr &lt;device&gt; valueFn {if ($DEVICE eq "living_Clima" && $VALUE eq "off" ){$VALUE=0;} elsif ($DEVICE eq "e-power"){$VALUE= sprintf "%.1f", $VALUE;}}
      </code> <br>
      # change value "off" to "0" of device "living_Clima" and rounds value of e-power to 1f <br><br>
      <code>
      attr &lt;device&gt; valueFn {if ($DEVICE eq "SMA_Energymeter" && $READING eq "state"){$IGNORE=1;}}
      </code><br>
      # don't log the dataset of device "SMA_Energymeter" if the reading is "state"  <br><br>
      <code>
      attr &lt;device&gt; valueFn {if ($DEVICE eq "Dum.Energy" && $READING eq "TotalConsumption"){$UNIT="W";}}
      </code><br>
      # set the unit of device "Dum.Energy" to "W" if reading is "TotalConsumption" <br><br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-verbose4Devs"></a>
     <li><b>verbose4Devs &lt;device1&gt;,&lt;device2&gt;,&lt;device..&gt; </b> <br><br>
     <ul>

       If verbose level 4/5 is used, only output of devices set in this attribute will be reported in FHEM central logfile.
       If this attribute isn't set, output of all relevant devices will be reported if using verbose level 4/5.
       The given devices are evaluated as Regex. <br><br>

      <b>Example</b> <br>
      <code>
      attr &lt;device&gt; verbose4Devs sys.*,.*5000.*,Cam.*,global
      </code><br>
      # The devices starting with "sys", "Cam" respectively devices are containing "5000" in its name and the device "global" will be reported in FHEM
      central Logfile if verbose=4 is set. <br>
     </ul>
     </li>
  </ul>
  <br>

</ul>

=end html
=begin html_DE

<a id="DbLog"></a>
<h3>DbLog</h3>
<br>

<ul>
  Mit DbLog werden Events in einer Datenbank gespeichert. Es wird SQLite, MySQL/MariaDB und PostgreSQL unterstützt. <br><br>

  <b>Voraussetzungen</b> <br><br>

    Die Perl-Module <code>DBI</code> und <code>DBD::&lt;dbtype&gt;</code> müssen installiert werden (use <code>cpan -i &lt;module&gt;</code>
    falls die eigene Distribution diese nicht schon mitbringt).
    <br><br>

    Auf einem Debian-System können diese Module z.Bsp. installiert werden mit: <br><br>

    <ul>
    <table>
    <colgroup> <col width=5%> <col width=95%> </colgroup>
      <tr><td> <b>DBI</b>         </td><td>: <code> sudo apt-get install libdbi-perl </code> </td></tr>
      <tr><td> <b>MySQL</b>       </td><td>: <code> sudo apt-get install [mysql-server] mysql-client libdbd-mysql libdbd-mysql-perl </code> (mysql-server nur bei lokaler MySQL-Server-Installation) </td></tr>
      <tr><td> <b>SQLite</b>      </td><td>: <code> sudo apt-get install sqlite3 libdbi-perl libdbd-sqlite3-perl </code> </td></tr>
      <tr><td> <b>PostgreSQL</b>  </td><td>: <code> sudo apt-get install libdbd-pg-perl </code> </td></tr>
    </table>
    </ul>
    <br>
    <br>

  <b>Vorbereitungen</b> <br><br>

  Zunächst muss die Datenbank installiert und angelegt werden.
  Die Installation des Datenbanksystems selbst wird hier nicht beschrieben. Dazu bitte nach den Installationsvorgaben des
  verwendeten Datenbanksystems verfahren. <br><br>

  <b>Hinweis:</b> <br>
  Im Falle eines frisch installierten MySQL/MariaDB Systems bitte nicht vergessen die anonymen "Jeder"-Nutzer mit einem
  Admin-Tool (z.B. phpMyAdmin) zu löschen falls sie existieren.
  <br><br>

  Beispielcode bzw. Scripts zum Erstellen einer MySQL/PostgreSQL/SQLite Datenbank ist im
  <a href="https://svn.fhem.de/trac/browser/trunk/fhem/contrib/dblog">SVN -&gt; contrib/dblog/db_create_&lt;DBType&gt;.sql</a>
  enthalten. <br>
  (<b>Achtung:</b> Die lokale FHEM-Installation enthält im Unterverzeichnis ./contrib/dblog nicht die aktuellsten
  Scripte!) <br><br>

  Die Standardinstallation der MySQL/MariaDB Datenbank sieht die Nutzung der Collation <b>utf8_bin</b> vor.
  Mit dieser Einstellung können Zeichen bis 3 Byte Länge gespeichert werden was im Allgemeinen ausreichend ist.
  Sollen jedoch Zeichen mit 4 Byte Länge (z.B. Emojis) in der Datenbank gespeichert werden, ist der Zeichensatz
  <b>utf8mb4</b> zu verwenden. <br>
  Dementsprechend wäre in diesem Fall die MySQL/MariaDB Datenbank mit folgendem Statement anzulegen: <br><br>

  <ul>
   <code> CREATE DATABASE `fhem` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin; </code>
  </ul>
  <br>

  In der Konfigurationsdatei (siehe unten) ist die utf8-Unterstützung mit dem Schlüssel <b>utf8 => 1</b> einzuschalten
  sofern utf8 genutzt werden soll. <br><br>

  Die Datenbank beinhaltet 2 Tabellen: <code>current</code> und <code>history</code>. <br>
  Die Tabelle <code>current</code> enthält den letzten Stand pro Device und Reading. <br>
  In der Tabelle <code>history</code> sind alle Events historisch gespeichert. <br>
  Beachten sie bitte unbedingt das <a href="#DbLog-attr-DbLogType">DbLogType</a> um die Benutzung der Tabellen
  <code>current</code> und <code>history</code> festzulegen.
  <br><br>

  Die Tabellenspalten haben folgende Bedeutung: <br><br>

    <ul>
    <table>
    <colgroup> <col width=5%> <col width=95%> </colgroup>
      <tr><td> TIMESTAMP </td><td>: Zeitpunkt des Events, z.B. <code>2007-12-30 21:45:22</code> </td></tr>
      <tr><td> DEVICE    </td><td>: Name des Devices, z.B. <code>Wetterstation</code> </td></tr>
      <tr><td> TYPE      </td><td>: Type des Devices, z.B. <code>KS300</code> </td></tr>
      <tr><td> EVENT     </td><td>: das auftretende Event als volle Zeichenkette, z.B. <code>humidity: 71 (%)</code> </td></tr>
      <tr><td> READING   </td><td>: Name des Readings, ermittelt aus dem Event, z.B. <code>humidity</code> </td></tr>
      <tr><td> VALUE     </td><td>: aktueller Wert des Readings, ermittelt aus dem Event, z.B. <code>71</code> </td></tr>
      <tr><td> UNIT      </td><td>: Einheit, ermittelt aus dem Event, z.B. <code>%</code> </td></tr>
    </table>
    </ul>
    <br>
    <br>

  <b>Index anlegen</b> <br>
  Für die Leseperformance, z.B. bei der Erstellung von SVG-PLots, ist es von besonderer Bedeutung dass der <b>Index "Search_Idx"</b>
  oder ein vergleichbarer Index (z.B. ein Primary Key) angelegt ist. <br><br>

  Der Index "Search_Idx" kann mit diesen Statements, z.B. in der Datenbank 'fhem', angelegt werden (auch nachträglich): <br><br>

    <ul>
    <table>
    <colgroup> <col width=5%> <col width=95%> </colgroup>
      <tr><td> <b>MySQL</b>       </td><td>: <code> CREATE INDEX Search_Idx ON `fhem`.`history` (DEVICE, READING, TIMESTAMP); </code> </td></tr>
      <tr><td> <b>SQLite</b>      </td><td>: <code> CREATE INDEX Search_Idx ON `history` (DEVICE, READING, TIMESTAMP); </code> </td></tr>
      <tr><td> <b>PostgreSQL</b>  </td><td>: <code> CREATE INDEX "Search_Idx" ON history USING btree (device, reading, "timestamp"); </code> </td></tr>
    </table>
    </ul>
    <br>

  Der Code zur Anlage ist ebenfalls in den Scripten
  <a href="https://svn.fhem.de/trac/browser/trunk/fhem/contrib/dblog">SVN -&gt; contrib/dblog/db_create_&lt;DBType&gt;.sql</a>
  enthalten. <br><br>

  Für die Verbindung zur Datenbank wird eine <b>Konfigurationsdatei</b> verwendet.
  Die Konfigurationsdatei wird z.B. nach /opt/fhem kopiert und hat den nachfolgend dargestellten Aufbau.
  Die Angaben sind entsprechend der verwendeten Umgebung anzupassen (entsprechende Zeilen entkommentieren und ändern): 
  <br><br>

    <pre>
    ####################################################################################
    # database configuration file
    #
    # NOTE:
    # If you don't use a value for user / password please delete the leading hash mark
    # and write 'user => ""' respectively 'password => ""' instead !
    #
    #
    ## for MySQL
    ####################################################################################
    #%dbconfig= (
    #    connection => "mysql:database=fhem;host=&lt;database host&gt;;port=3306",
    #    # if want communication over socket-file instead of TCP/IP transport, use:
    #    # connection => "mysql:database=fhem;mysql_socket=&lt;/patch/socket-file&gt;",
    #    user => "fhemuser",
    #    password => "fhempassword",
    #    # optional enable(1) / disable(0) UTF-8 support
    #    # (full UTF-8 support exists from DBD::mysql version 4.032, but installing
    #    # 4.042 is highly suggested)
    #    utf8 => 1
    #);
    ####################################################################################
    #
    ## for PostgreSQL
    ####################################################################################
    #%dbconfig= (
    #    connection => "Pg:database=fhem;host=&lt;database host&gt;",
    #    user => "fhemuser",
    #    password => "fhempassword"
    #);
    ####################################################################################
    #
    ## for SQLite (username and password stay empty for SQLite)
    ####################################################################################
    #%dbconfig= (
    #    connection => "SQLite:dbname=/opt/fhem/fhem.db",
    #    user => "",
    #    password => ""
    #);
    ####################################################################################
    </pre>

    Wird configDB genutzt, ist das Konfigurationsfile in die configDB hochzuladen ! <br><br>

    <b>Hinweis zu Sonderzeichen:</b><br>
    Werden Sonderzeichen, wie z.B. @, $ oder %, welche eine programmtechnische Bedeutung in Perl haben im Passwort verwendet,
    sind diese Zeichen zu escapen.
    Das heißt in diesem Beispiel wäre zu verwenden: \@,\$ bzw. \%.
    <br>
    <br>
    
    <b>DbLog spezifische Events</b> <br><br>
    
    DbLog generiert Events abhängig vom Initialisierungsstatus des DbLog-Devices: 
    <br>
    <br>
    
      <ul>
       <table>
       <colgroup> <col width=20%> <col width=80%> </colgroup>
       <tr><td> FRAME_INITIALIZED    </td><td>- Das grundlegende Rahmenwerk ist initialisiert. Blockierend arbeitende (Get)-Kommandos können ausgeführt werden.           </td></tr>
       <tr><td> SUBPROC_INITIALIZED  </td><td>- Der SupProcess ist einsatzbereit. Nichtblockierend arbeitende (Set)-Kommandos und Daten Logging können ausgeführt werden. </td></tr>
       <tr><td> SUBPROC_DISCONNECTED </td><td>- Der SupProcess wurde von der DB getrennt.                                                                                 </td></tr>
       <tr><td> SUBPROC_STOPPED      </td><td>- Der SupProcess wurde gestoppt.                                                                                            </td></tr>
       </table>
      </ul>
    
    <br>
    <br>
    <br>

  <a id="DbLog-define"></a>
  <b>Define</b>
  <br><br>

  <ul>
    <code>define &lt;name&gt; DbLog &lt;configfilename&gt; &lt;regexp&gt;</code>
    <br><br>

    <code>&lt;configfilename&gt;</code> ist die vorbereitete <b>Konfigurationsdatei</b>. <br>
    <code>&lt;regexp&gt;</code> ist identisch <a href="https://fhem.de/commandref_DE.html#FileLog">FileLog</a> der Filelog-Definition.
    <br><br>

    <b>Beispiel:</b>
    <ul>
        <code>define myDbLog DbLog /etc/fhem/db.conf .*:.*</code><br>
        speichert alles in der Datenbank
    </ul>
    <br>

    Nachdem das DbLog-Device definiert wurde, ist empfohlen einen <b>Konfigurationscheck</b> auszuführen: <br><br>
    <ul>
        <code>get &lt;name&gt; configCheck</code> <br>
    </ul>
    <br>
    Dieser Check prüft einige wichtige Einstellungen des DbLog-Devices und gibt Empfehlungen für potentielle Verbesserungen.
    <br><br>
    <br>

    DbLog unterscheidet den synchronen (default) und asynchronen Logmodus. Der Logmodus ist über das
    <a href="#DbLog-attr-asyncMode">asyncMode</a> einstellbar. Ab Version 2.13.5 unterstützt DbLog einen gesetzten
    Primary Key (PK) in den Tabellen Current und History. Soll PostgreSQL mit PK genutzt werden, muss PostgreSQL mindestens
    Version 9.5 sein.
    <br><br>

    Der gespeicherte Wert des Readings wird optimiert für eine automatisierte Nachverarbeitung, z.B. <code>yes</code> wird
    transformiert nach <code>1</code>. <br><br>

    Die gespeicherten Werte können mittels GET Funktion angezeigt werden:
    <ul>
      <code>get myDbLog - - 2012-11-10 2012-11-10 KS300:temperature</code>
    </ul>
    <br>

    <b>FileLog-Dateien nach DbLog übertragen</b> <br><br>
    Zur Übertragung von vorhandenen Filelog-Daten in die DbLog-Datenbank steht das spezielle Modul 98_FileLogConvert.pm
    zur Verfügung. <br>
    Dieses Modul kann <a href="https://svn.fhem.de/trac/browser/trunk/fhem/contrib/98_FileLogConvert.pm"> hier</a>
    bzw. aus dem Verzeichnis ./contrib geladen werden.
    Weitere Informationen und Hilfestellung gibt es im entsprechenden <a href="https://forum.fhem.de/index.php/topic,66383.0.html">
    Forumthread </a>. <br><br><br>

    <b>Reporting und Management von DbLog-Datenbankinhalten</b> <br><br>
    Mit Hilfe <a href="https://fhem.de/commandref_DE.html#SVG">SVG</a> können Datenbankinhalte visualisiert werden. <br>
    Darüber hinaus kann das Modul <a href="https://fhem.de/commandref_DE.html#DbRep">DbRep</a> genutzt werden um tabellarische
    Datenbankauswertungen anzufertigen oder den Datenbankinhalt mit den zur Verfügung stehenden Funktionen zu verwalten.
    <br><br><br>

    <b>Troubleshooting</b> <br><br>
    Wenn nach der erfolgreichen Definition das DbLog-Device nicht wie erwartet arbeitet,
    können folgende Hinweise hilfreich sein: <br><br>

    <ul>
    <li> Wurden die vorbereitenden Schritte gemacht, die in der commandref beschrieben sind ? (Softwarekomponenten installieren, Tabellen, Index anlegen) </li>
    <li> Wurde ein "get &lt;name&gt; configCheck" nach dem Define durchgeführt und eventuelle Fehler beseitigt bzw. Empfehlungen umgesetzt ? </li>
    <li> Falls configDB in Benutzung ... wurde das DB-Konfigurationsfile in configDB importiert (z.B. mit "configDB fileimport ./db.conf") ? </li>
    <li> Beim Anlegen eines SVG-Plots erscheint keine Drop-Down Liste mit Vorschlagswerten -> Attribut "DbLogType" auf "Current/History" setzen. </li>
    </ul>
    <br>

    Sollten diese Hinweise nicht zum Erfolg führen, bitte den verbose-Level im DbLog Device auf 4 oder 5 hochsetzen und
    die Einträge bezüglich des DbLog-Device im Logfile beachten.

    Zur Problemanalyse bitte die Ausgabe von "list &lt;name&gt;", das Ergebnis von "get &lt;name&gt; configCheck" und die
    Ausgaben des DbLog-Device im Logfile im Forumthread posten.
    <br><br>

  </ul>
  <br>
  <br>

  <a id="DbLog-set"></a>
  <b>Set</b>
  <br>
  <br>

  <ul>
    <li>
    <a id="DbLog-set-addCacheLine"></a>
    <b>set &lt;name&gt; addCacheLine YYYY-MM-DD HH:MM:SS|&lt;device&gt;|&lt;type&gt;|&lt;event&gt;|&lt;reading&gt;|&lt;value&gt;|[&lt;unit&gt;]  </b> <br><br>

    <ul>
    Im asynchronen Modus wird ein neuer Datensatz in den Cache eingefügt und beim nächsten Synclauf mit abgearbeitet.
    <br><br>

      <b>Beispiel:</b> <br>
      set &lt;name&gt; addCacheLine 2017-12-05 17:03:59|MaxBathRoom|MAX|valveposition: 95|valveposition|95|% <br>
    </li>
    </ul>
    <br>

    <li>
    <a id="DbLog-set-addLog"></a>
    <b>set &lt;name&gt; addLog &lt;devspec&gt;:&lt;Reading&gt; [Value] [CN=&lt;caller name&gt;] [!useExcludes] </b> <br><br>

    <ul>
    Fügt einen zusätzlichen Logeintrag einer Device/Reading-Kombination in die Datenbank ein. <br>
    Die eventuell im Attribut "DbLogExclude" spezifizierten Readings (im Quellendevice) werden nicht geloggt, es sei denn
    sie sind im Attribut "DbLogInclude" enthalten bzw. der addLog Aufruf erfolgte mit der Option "!useExcludes".
    <br><br>

      <table>
       <colgroup> <col width=20%> <col width=80%> </colgroup>
       <tr><td> <b>&lt;devspec&gt;:&lt;Reading&gt;</b>   </td><td>Das Device kann als <a href="#devspec">Geräte-Spezifikation</a> angegeben werden.                </td></tr>
       <tr><td>                                          </td><td>Die Angabe von "Reading" wird als regulärer Ausdruck ausgewertet.                                </td></tr>
       <tr><td>                                          </td><td>Ist das Reading nicht vorhanden und der Wert "Value" angegeben, wird das Reading                 </td></tr>
       <tr><td>                                          </td><td>in die DB eingefügt wenn es kein regulärer Ausdruck und ein valider Readingname ist.             </td></tr>
       <tr><td>                                          </td><td>                                                                                                 </td></tr>
       <tr><td>                                          </td><td>                                                                                                 </td></tr>
       <tr><td> <b>Value</b>                             </td><td>Optional kann "Value" für den Readingwert angegeben werden.                                      </td></tr>
       <tr><td>                                          </td><td>Ist Value nicht angegeben, wird der aktuelle Wert des Readings in die DB eingefügt.              </td></tr>
       <tr><td>                                          </td><td>                                                                                                 </td></tr>
       <tr><td>                                          </td><td>                                                                                                 </td></tr>
       <tr><td> <b>CN=&lt;caller name&gt;</b>            </td><td>Mit dem Schlüssel "CN=" (<b>C</b>aller <b>N</b>ame) kann dem addLog-Aufruf ein String,           </td></tr>
       <tr><td>                                          </td><td>z.B. der Name des aufrufenden Devices, mitgegeben werden.                                        </td></tr>
       <tr><td>                                          </td><td>Mit Hilfe der im Attribut <a href="#DbLog-attr-valueFn">valueFn</a> hinterlegten Funktion kann   </td></tr>
       <tr><td>                                          </td><td>dieser Schlüssel über die Variable $CN ausgewertet werden.                                       </td></tr>
       <tr><td>                                          </td><td>                                                                                                 </td></tr>
       <tr><td>                                          </td><td>                                                                                                 </td></tr>
       <tr><td> <b>!useExcludes</b>                      </td><td>addLog berücksichtigt per default die mit dem Attribut "DbLogExclude" ausgeschlossenen Readings. </td></tr>
       <tr><td>                                          </td><td>Mit dem Schüsselwort "!useExcludes" wird das gesetzte Attribut "DbLogExclude" ignoriert.         </td></tr>
      </table>
      <br>

      Das Datenbankfeld "EVENT" wird automatisch mit "addLog" belegt. <br>
      Es wird <b>kein</b> zusätzlicher Event im System erzeugt!       <br><br>

      <b>Beispiele:</b> <br>
      set &lt;name&gt; addLog SMA_Energymeter:Bezug_Wirkleistung        <br>
      set &lt;name&gt; addLog TYPE=SSCam:state                          <br>
      set &lt;name&gt; addLog MyWetter:(fc10.*|fc8.*)                   <br>
      set &lt;name&gt; addLog MyWetter:(wind|wind_ch.*) 20 !useExcludes <br>
      set &lt;name&gt; addLog TYPE=CUL_HM:FILTER=model=HM-CC-RT-DN:FILTER=subType!=(virtual|):(measured-temp|desired-temp|actuator) <br><br>

      set &lt;name&gt; addLog USV:state CN=di.cronjob <br><br>

      In der valueFn-Funktion wird der Aufrufer "di.cronjob" über die Variable $CN ausgewertet und davon abhängig der
      Timestamp dieses addLog korrigiert: <br><br>

      valueFn = if($CN eq "di.cronjob" and $TIMESTAMP =~ m/\s00:00:[\d:]+/) { $TIMESTAMP =~ s/\s([^\s]+)/ 23:59:59/ }
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-clearReadings"></a>
    <b>set &lt;name&gt; clearReadings </b> <br><br>

    <ul>
      Leert Readings die von verschiedenen DbLog-Funktionen angelegt wurden.
    </li>
    </ul>
    <br>

    <li>
    <a id="DbLog-set-eraseReadings"></a>
    <b>set &lt;name&gt; eraseReadings </b> <br><br>
      <ul>
      Löscht alle Readings außer dem Reading "state".
    </li>
    </ul>
    <br>

    <li>
    <a id="DbLog-set-commitCache"></a>
    <b>set &lt;name&gt; commitCache </b> <br><br>

    <ul>
      Im asynchronen Modus (<a href="#DbLog-attr-asyncMode">asyncMode=1</a>), werden die im Cache gespeicherten
      Daten in die Datenbank geschrieben und danach der Cache geleert. <br>
      Der interne Timer des asynchronen Modus wird dabei neu gesetzt.
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-configCheck"></a>
    <b>set &lt;name&gt; configCheck </b> <br><br>

    <ul>
      Es werden einige wichtige Einstellungen geprüft und Empfehlungen gegeben falls potentielle Verbesserungen
      identifiziert wurden. <br>
      (<b>Hinweis:</b> Dieser Befehl ist abgekündigt und wird in den nächsten Versionen entfernt werden. Verwenden Sie stattdessen "get &lt;name&gt; configCheck".)
    </li>
    </ul>
    <br>

    <li>
    <a id="DbLog-set-count"></a>
    <b>set &lt;name&gt; count </b> <br><br>

    <ul>
      Ermittelt die Anzahl der Datensätze in den Tabellen current und history und schreibt die Ergebnisse in die Readings
      countCurrent und countHistory.
      <br><br>

      <b>Hinweis</b> <br>
      Während der Laufzeit des Befehls werden zu loggende Daten temporär im Memory Cache gespeichert und nach Beendigung
      des Befehls in die Datenbank geschrieben.
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-countNbl"></a>
    <b>set &lt;name&gt; countNbl </b> <br><br>
      <ul>
      Die Funktion ist identisch zu "set &lt;name&gt; count" und wird demnächst entfernt.
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-deleteOldDays"></a>
    <b>set &lt;name&gt; deleteOldDays &lt;n&gt; </b> <br><br>

    <ul>
      Löscht Datensätze älter als &lt;n&gt; Tage in Tabelle history.
      Die Anzahl der gelöschten Datens&auml;tze wird im Reading lastRowsDeleted protokolliert.
      <br><br>

      <b>Hinweis</b> <br>
      Während der Laufzeit des Befehls werden zu loggende Daten temporär im Memory Cache gespeichert und nach Beendigung
      des Befehls in die Datenbank geschrieben.
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-exportCache"></a>
    <b>set &lt;name&gt; exportCache [nopurge | purgecache] </b> <br><br>

    <ul>
      Wenn DbLog im asynchronen Modus betrieben wird, kann der Cache mit diesem Befehl in ein Textfile geschrieben
      werden. <br>
      Das File wird per default im Verzeichnis (global->modpath)/log/ erstellt. Das Zielverzeichnis kann mit
      dem <a href="#DbLog-attr-expimpdir">expimpdir</a> Attribut geändert werden. <br><br>

      Der Name des Files wird automatisch generiert und enthält den Präfix "cache_&lt;name&gt;", gefolgt von
      dem aktuellen Zeitstempel. <br><br>

      <b>Beispiel </b> <br>
      cache_LogDB_2017-03-23_22-13-55 <br><br>

      Mit den Optionen "nopurge" bzw. "purgecache" wird festgelegt, ob der Cacheinhalt nach dem Export gelöscht werden
      soll oder nicht. Mit "nopurge" (default) bleibt der Cacheinhalt erhalten. <br>
      Das <a href="#DbLog-attr-exportCacheAppend">exportCacheAppend</a> Attribut bestimmt ob mit jedem Exportvorgang
      ein neues Exportfile angelegt wird (default) oder der Cacheinhalt an das neuste vorhandene Exportfile angehängt wird.
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-importCachefile"></a>
    <b>set &lt;name&gt; importCachefile &lt;file&gt; </b> <br><br>

    <ul>
      Importiert ein mit "exportCache" geschriebenes File in die Datenbank. <br>
      Die verfügbaren Dateien werden per Default im Verzeichnis (global->modpath)/log/ gesucht und eine Drop-Down Liste
      erzeugt sofern Dateien gefunden werden. <br>
      Das Quellenverzeichnis kann mit dem <a href="#DbLog-attr-expimpdir">expimpdir</a> Attribut geändert werden. <br>
      Es werden nur die Dateien angezeigt, die dem Muster "cache_&lt;name&gt;" entsprechen. <br><br>

      <b>Beispiel </b><br>
      cache_LogDB_2017-03-23_22-13-55 <br>
      wenn das DbLog Device "LogDB" heißt. <br><br>

      Nach einem erfolgreichen Import wird das File mit dem Präfix "impdone_" versehen und erscheint nicht mehr
      in der Drop-Down Liste. Soll ein Cachefile in eine andere als die Quellendatenbank importiert werden, kann der
      Name des DbLog Device im Filenamen angepasst werden damit dieses File in der Drop-Down Liste erscheint.
      <br><br>

      <b>Hinweis</b> <br>
      Während der Laufzeit des Befehls werden zu loggende Daten temporär im Memory Cache gespeichert und nach Beendigung
      des Befehls in die Datenbank geschrieben.
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-listCache"></a>
    <b>set &lt;name&gt; listCache </b> <br><br>

    <ul>
      Listet die im Memory Cache zwischengespeicherten Daten auf.
    </li>
    </ul>
    <br>

    <li>
    <a id="DbLog-set-purgeCache"></a>
    <b>set &lt;name&gt; purgeCache </b> <br><br>
      <ul>
      Im asynchronen Modus (<a href="#DbLog-attr-asyncMode">asyncMode=1</a>), werden die im Speicher zwischengespeicherten
      Daten gelöscht.
      Es werden keine Daten aus dem Cache in die Datenbank geschrieben.
    </li>
    </ul>
    <br>

    <li>
    <a id="DbLog-set-reduceLog"></a>
    <b>set &lt;name&gt; reduceLog &lt;no&gt;[:&lt;nn&gt;] [average[=day]] [exclude=device1:reading1,device2:reading2,...] </b> <br><br>

    <ul>
      Reduziert historische Datensätze, die älter sind als &lt;no&gt; Tage und (optional) neuer sind als &lt;nn&gt; Tage
      auf einen Eintrag (den ersten) pro Stunde je Device & Reading.<br>
      Innerhalb von device/reading können <b>SQL-Wildcards "%" und "_"</b> verwendet werden. <br><br>

      Durch die optionale Angabe von 'average' bzw. 'average=day' wird nicht nur die Datenbank bereinigt, sondern alle
      numerischen Werte einer Stunde bzw. eines Tages werden auf einen einzigen Mittelwert reduziert. <br><br>

      Optional kann als letzer Parameter "exclude=device1:reading1,device2:reading2,...."
      angegeben werden um device/reading Kombinationen von reduceLog auszuschließen. <br>
      Anstatt "exclude" kann als letzer Parameter "include=device:reading" angegeben werden um
      die auf die Datenbank ausgeführte SELECT-Abfrage einzugrenzen. Dadurch wird die RAM-Belastung verringert und die
      Performance erhöht. Die Option "include" kann nur mit einer device:reading Kombination angegeben werden. <br><br>

      <ul>
        <b>Beispiele: </b> <br>
        set &lt;name&gt; reduceLog 270 average include=Luftdaten_remote:% <br>
        set &lt;name&gt; reduceLog 100:200 average exclude=SMA_Energymeter:Bezug_Wirkleistung
      </ul>
      <br>

      <b>Hinweis</b> <br>
      Während der Laufzeit des Befehls werden zu loggende Daten temporär im Memory Cache gespeichert und nach Beendigung
      des Befehls in die Datenbank geschrieben.
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-reopen"></a>
    <b>set &lt;name&gt; reopen [n] </b> <br><br>

    <ul>
      Schließt die Datenbank und öffnet sie danach sofort wieder wenn keine Zeit [n] in Sekunden angegeben wurde. <br>
      Wurde eine optionale Verzögerungszeit [n] in Sekunden angegeben, wird die Verbindung zur Datenbank geschlossen und
      erst nach Ablauf von [n] Sekunden wieder neu verbunden. <br>
      Während der Zeit der Datenbankschließung werden zu loggende Events im Memory Cache gespeichert und nach dem
      Reconnect in die Datenbank geschrieben.
    </li>
    </ul>
    <br>

    <li>
    <a id="DbLog-set-rereadcfg"></a>
    <b>set &lt;name&gt; rereadcfg </b> <br><br>

    <ul>
      Die Konfigurationsdatei wird neu eingelesen. <br>
      Nach dem Einlesen wird eine bestehende Datenbankverbindung beendet und mit den konfigurierten Verbindungsdaten
      neu aufgebaut.
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-stopSubProcess"></a>
    <b>set &lt;name&gt; stopSubProcess </b> <br><br>

    <ul>
      Ein laufender SubProzess wird beendet. <br>
      Sobald durch eine Operation ein neuer SubProzess benötigt wird, erfolgt die automatische Neuinitialisierung
      eines SubProzesses.
      <br><br>

      <b>Hinweis</b> <br>
      Die Neuinitialisierung des SubProzesses während der Laufzeit verursacht einen erhöhten RAM Verbrauch bis
      zu einem FHEM Neustart .
    </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-set-userCommand"></a>
    <b>set &lt;name&gt; userCommand &lt;validSelectStatement&gt; </b> <br><br>

    <ul>
      Führt einfache SQL Select Befehle auf der Datenbank aus. <br>
      Das Ergebnis des Statements wird in das Reading "userCommandResult" geschrieben.
      Das Ergebnis kann nur einzeilig sein. <br>
      Die Ausführung von SQL-Befehlen in DbLog ist veraltet. Dafür sollte das Auswertungsmodul
      <a href=https://fhem.de/commandref_DE.html#DbRep>DbRep</a> genutzt werden. <br><br>

      <b>Hinweis</b> <br>
      Während der Laufzeit des Befehls werden zu loggende Daten temporär im Memory Cache gespeichert und nach Beendigung
      des Befehls in die Datenbank geschrieben.
    </ul>
    </li>
    <br>

  </ul>
  <br>

  <a id="DbLog-get"></a>
  <b>Get</b>
  <br>
  <br>
  <ul>

    <li>
    <a id="DbLog-get-configCheck"></a>
    <b>get &lt;name&gt; configCheck </b> <br><br>

      <ul>
        Es werden einige wichtige Einstellungen geprüft und Empfehlungen gegeben falls potentielle Verbesserungen
        identifiziert wurden.
      </ul>
    </li>
    <br>

    <li>
    <a id="DbLog-get-ReadingsMaxVal" data-pattern="ReadingsMaxVal.*"></a>
    <b>get &lt;name&gt; ReadingsMaxVal[Timestamp] &lt;Device&gt; &lt;Reading&gt; &lt;default&gt; </b> <br><br>

    <ul>
      Ermittelt den Datensatz mit dem größten Wert der angegebenen Device / Reading Kombination aus der history Tabelle. <br>
      Zurück gegeben wird nur der Wert oder die Kombination aus Wert und Timestamp als String
      "&lt;Wert&gt; , &lt;Timestamp&gt;". <br>
      &lt;default&gt; gibt einen definierten Rückgabewert an, wenn kein Wert ermittelt werden kann.
      <br>
      <br>

      <b>Hinweis:</b> <br>
      Dieser Datenbankabruf arbeitet blockierend und beeinflusst FHEM wenn die Datenbank nicht oder nicht
      hinreichend schnell antwortet. Für nicht-blockierende Datenbankabfragen wird auf das Modul DbRep
      verwiesen.
    </ul>
  </ul>
  </li>
  <br>

  <ul>
    <li>
    <a id="DbLog-get-ReadingsMinVal" data-pattern="ReadingsMinVal.*"></a>
    <b>get &lt;name&gt; ReadingsMinVal[Timestamp] &lt;Device&gt; &lt;Reading&gt; &lt;default&gt; </b> <br><br>

    <ul>
      Ermittelt den Datensatz mit dem kleinsten Wert der angegebenen Device / Reading Kombination aus der history Tabelle. <br>
      Zurück gegeben wird nur der Wert oder die Kombination aus Wert und Timestamp als String
      "&lt;Wert&gt; , &lt;Timestamp&gt;". <br>
      &lt;default&gt; gibt einen definierten Rückgabewert an, wenn kein Wert ermittelt werden kann.
      <br>
      <br>

      <b>Hinweis:</b> <br>
      Dieser Datenbankabruf arbeitet blockierend und beeinflusst FHEM wenn die Datenbank nicht oder nicht
      hinreichend schnell antwortet. Für nicht-blockierende Datenbankabfragen wird auf das Modul DbRep
      verwiesen.
    </ul>
  </ul>
  </li>
  <br>

  <ul>
    <li>
    <a id="DbLog-get-ReadingsAvgVal"></a>
    <b>get &lt;name&gt; ReadingsAvgVal &lt;Device&gt; &lt;Reading&gt; &lt;default&gt; </b> <br><br>

    <ul>
      Ermittelt den Durchschnittswert der angegebenen Device / Reading Kombination aus der history Tabelle. <br>
      Zurück gegeben wird der einfache arithmetische Durchschnittswert. <br>
      &lt;default&gt; gibt einen definierten Rückgabewert an, wenn kein Wert ermittelt werden kann.
      <br>
      <br>

      <b>Hinweis:</b> <br>
      Dieser Datenbankabruf arbeitet blockierend und beeinflusst FHEM wenn die Datenbank nicht oder nicht
      hinreichend schnell antwortet. Für nicht-blockierende Datenbankabfragen wird auf das Modul DbRep
      verwiesen.
    </ul>
  </ul>
  </li>
  <br>

  <ul>
    <li>
    <a id="DbLog-get-ReadingsVal" data-pattern="ReadingsVal.*"></a>
    <b>get &lt;name&gt; ReadingsVal[Timestamp] &lt;Device&gt; &lt;Reading&gt; &lt;default&gt; </b> <br><br>

    <ul>
      Liest den letzten (neuesten) in der history Tabelle gespeicherten Datensatz der angegebenen Device / Reading
      Kombination. <br>
      Zurück gegeben wird nur der Wert oder die Kombination aus Wert und Timestamp als String
      "&lt;Wert&gt; , &lt;Timestamp&gt;". <br>
      &lt;default&gt; gibt einen definierten Rückgabewert an, wenn kein Wert ermittelt werden kann.
      <br>
      <br>

      <b>Hinweis:</b> <br>
      Dieser Datenbankabruf arbeitet blockierend und beeinflusst FHEM wenn die Datenbank nicht oder nicht
      hinreichend schnell antwortet. Für nicht-blockierende Datenbankabfragen wird auf das Modul DbRep
      verwiesen.
    </ul>
  </ul>
  </li>
  <br>

  <ul>
    <li>
    <a id="DbLog-get-ReadingsTimestamp"></a>
    <b>get &lt;name&gt; ReadingsTimestamp &lt;Device&gt; &lt;Reading&gt; &lt;default&gt; </b> <br><br>

    <ul>
      Liest den Zeitstempel des letzten (neuesten) in der history Tabelle gespeicherten Datensatzes der angegebenen
      Device/Reading Kombination und gibt diesen Wert zurück. <br>
      &lt;default&gt; gibt einen definierten Rückgabewert an, wenn kein Wert in der Datenbank gefunden wird.
      <br>
      <br>

      <b>Hinweis:</b> <br>
      Dieser Datenbankabruf arbeitet blockierend und beeinflusst FHEM wenn die Datenbank nicht oder nicht
      hinreichend schnell antwortet. Für nicht-blockierende Datenbankabfragen wird auf das Modul DbRep
      verwiesen.
    </ul>
  </ul>
  </li>
  <br>

  <ul>
    <li>
    <a id="DbLog-get-retrieve"></a>
    <b>get &lt;name&gt; retrieve &lt;querytype&gt; &lt;device|table&gt; &lt;reading&gt; &lt;from&gt; &lt;to&gt; &lt;offset&gt; &lt;limit&gt; </b> <br><br>

    <ul>
      Liest Daten aus der Datenbank Tabelle history und gibt die Ergebnisse als JSON formatiert zurück. <br>
      Die Abfragemethode bzw. das gewünschte Abfrageergebnis wird durch den angegebenen &lt;querytype&gt; bestimmt. <br>
      Jeder &lt;querytype&gt; verlangt evtl. weitere Parameter gemäß der folgenden Tabelle. Nicht eingegebene Parameter sind
      immer als "" anzugeben sofern danach noch ein weiterer Parameter eingegeben wird.
      <br>
      <br>

      <ul>
       <table>
       <colgroup> <col width=15%> <col width=85%> </colgroup>
       <tr><td><b>alldevices</b>   </td><td>Ermittelt alle in der Datenbank gespeicherten Devices.                                            </td></tr>
       <tr><td><b>allreadings</b>  </td><td>Ermittelt alle in der Datenbank gespeicherten Readings für ein bestimmtes Device.                 </td></tr>
       <tr><td>                    </td><td>benötigte Parameter: &lt;device&gt;                                                               </td></tr>
       <tr><td><b>count</b>        </td><td>Liefert die Anzahl Datensätze der angegebenen Tabelle.                                            </td></tr>
       <tr><td>                    </td><td>benötigte Parameter: &lt;table&gt; (history oder current)                                         </td></tr>
       <tr><td><b>fetchrows</b>    </td><td>Ermittelt die gespeicherten Datensätze eines bestimmten Zeitraumes.                               </td></tr>
       <tr><td>                    </td><td>Die Anzahl der Datensätze im definierten Zeitraum wird als Schlüssel "totalcount" zurückgegeben.  </td></tr>
       <tr><td>                    </td><td>benötigte Parameter: &lt;from&gt;, &lt;to&gt;, &lt;offset&gt;, &lt;limit&gt;                      </td></tr>
       <tr><td><b>last</b>         </td><td>Listet die letzten 10 gespeicherten Events auf.                                                   </td></tr>
       <tr><td>                    </td><td>mögliche Parameter: &lt;limit&gt; (überschreibt den Standard 10)                                  </td></tr>
       <tr><td><b>timerange</b>    </td><td>Ermittelt die gespeicherten Datensätze der angegebenen Device / Reading Kombination.              </td></tr>
       <tr><td>                    </td><td>benötigte Parameter: &lt;device&gt;, &lt;reading&gt;, &lt;from&gt;, &lt;to&gt;                    </td></tr>
       <tr><td><b>hourstats</b>    </td><td>Errechnet die Statistiken SUM, AVG, MIN, MAX, COUNT für eine Stunde.                              </td></tr>
       <tr><td>                    </td><td>benötigte Parameter: &lt;device&gt;, &lt;reading&gt;, &lt;from&gt;, &lt;to&gt;                    </td></tr>
       <tr><td><b>daystats</b>     </td><td>Errechnet die Statistiken SUM, AVG, MIN, MAX, COUNT für einen Tag.                                </td></tr>
       <tr><td>                    </td><td>benötigte Parameter: &lt;device&gt;, &lt;reading&gt;, &lt;from&gt;, &lt;to&gt;                    </td></tr>
       <tr><td><b>weekstats</b>    </td><td>Errechnet die Statistiken SUM, AVG, MIN, MAX, COUNT für eine Woche.                               </td></tr>
       <tr><td>                    </td><td>benötigte Parameter: &lt;device&gt;, &lt;reading&gt;, &lt;from&gt;, &lt;to&gt;                    </td></tr>
       <tr><td><b>monthstats</b>   </td><td>Errechnet die Statistiken SUM, AVG, MIN, MAX, COUNT für einen Monat.                              </td></tr>
       <tr><td>                    </td><td>benötigte Parameter: &lt;device&gt;, &lt;reading&gt;, &lt;from&gt;, &lt;to&gt;                    </td></tr>
       <tr><td><b>yearstats</b>    </td><td>Errechnet die Statistiken SUM, AVG, MIN, MAX, COUNT für ein Jahr.                                 </td></tr>
       <tr><td>                    </td><td>benötigte Parameter: &lt;device&gt;, &lt;reading&gt;, &lt;from&gt;, &lt;to&gt;                    </td></tr>
       </table>
      </ul>
      <br>

      <b>Hinweis:</b> <br>
      Dieser Datenbankabruf arbeitet blockierend und beeinflusst FHEM wenn die Datenbank nicht oder nicht
      hinreichend schnell antwortet. Für nicht-blockierende Datenbankabfragen wird auf das Modul DbRep
      verwiesen.
      <br>
      <br>

      <b>Beispiele:</b>
      <ul>
        <li><code>get LogSQLITE3 retrieve alldevices </code>
        </li>

        <li><code>get LogSQLITE3 retrieve allreadings MySTP_5000 </code>
        </li>

        <li><code>get LogSQLITE3 retrieve last "" "" "" "" "" 50 </code>
        </li>

        <li><code>get LogSQLITE3 retrieve count history </code>
        </li>

        <li><code>get LogSQLITE3 retrieve timerange MySTP_5000 etotal 2023-01-01_00:00:00 2023-01-25_00:00:00 </code>
        </li>

        <li><code>get LogSQLITE3 retrieve fetchrows MySTP_5000 "" 2023-01-01_00:00:00 2023-01-25_00:00:00 0 100 </code>
        </li>

        <li><code>get LogSQLITE3 retrieve fetchrows "" etotal 2023-01-01_00:00:00 2023-01-25_00:00:00 0 100 </code>
        </li>

        <li><code>get LogSQLITE3 retrieve hourstats MySTP_5000 etotal 2023-01-01_00:00:00 2023-01-25_00:00:00 </code>
        </li>
      </ul>
    </ul>
  </ul>
  </li>
  <br>
  <br>

<b>Get</b> für die Nutzung von SVG-Plots
  <br>
  <br>

  <ul>
    <li><b>get &lt;name&gt; &lt;in&gt; &lt;out&gt; &lt;from&gt; &lt;to&gt; &lt;column_spec&gt; </b> <br><br>

    Liesst Daten aus der Datenbank. Wird durch die Frontends benutzt um Plots
    zu generieren ohne selbst auf die Datenank zugreifen zu müssen.
    <br>

    <ul>
      <li>&lt;in&gt;<br>
        Ein Parameter um eine Kompatibilität zu Filelog herzustellen. <br>
        In der Definition eines SVG Devices entspricht dieser Paramter der Angabe von :&lt;logfile&gt; am Ende der Definition.<br>
        Folgende Ausprägungen sind zugelassen:<br>
        <ul>
          <li>current: die Werte werden aus der Tabelle "current" gelesen.                                                   </li>
          <li>history: die Werte werden aus der Tabelle "history" gelesen.                                                   </li>
          <li>table_&lt;Tabelle&gt;: die Werte werden aus der angegeben alternativen Tabelle gelesen. Die Tabelle (Name)
                                     ist in der Datenbank mit Kleinbuchstaben anzulegen.  <br>
                                     (Beispiel: table_energy, "energy" ist die in der Datenbank angelegte Alternativtabelle) </li>
          <li>-: identisch wie "history"                                                                                     </li>
        </ul>
      </li>
      <br>

      <li>&lt;out&gt;<br>
        Ein Parameter um eine Kompatibilität zum Filelog herzustellen.
        Dieser Parameter ist per default immer auf <code>-</code> zu setzen um die
        Ermittlung der Daten aus der Datenbank für die Plotgenerierung zu prüfen.<br>
        Folgende Ausprägungen sind zugelassen:<br>
        <ul>
          <li>ALL: Es werden alle Spalten der Datenbank ausgegeben. Inclusive einer Überschrift.</li>
          <li>Array: Es werden alle Spalten der Datenbank als Hash ausgegeben. Alle Datensätze als Array zusammengefasst.</li>
          <li>INT: intern zur Plotgenerierung verwendet</li>
          <li>-: default</li>
        </ul>
      </li>
      <br>

      <li>&lt;from&gt; / &lt;to&gt;<br>
        Wird benutzt um den Zeitraum der Daten einzugrenzen. Es ist das folgende
        Zeitformat oder ein Teilstring davon zu benutzen:<br>

        <ul>
          <code>YYYY-MM-DD_HH24:MI:SS</code>
        </ul>
      </li>
      <br>

      <li>&lt;column_spec&gt;<br>
        Für jede column_spec Gruppe wird ein Datenset zurückgegeben welches
        durch einen Kommentar getrennt wird. Dieser Kommentar repräsentiert
        die column_spec. <br>
        <br>
        <b>Syntax:</b> &lt;device&gt;:&lt;reading&gt;:&lt;default&gt;:&lt;fn&gt;:&lt;regexp&gt; <br>
        <br>

        <ul>
          <li>&lt;device&gt;<br>
            Der Name des Devices. Achtung: Gross/Kleinschreibung beachten!<br>
            Es kann ein % als Jokerzeichen angegeben werden.
          </li>
          <br>

          <li>&lt;reading&gt;<br>
            Das Reading des angegebenen Devices zur Datenselektion.<br>
            Es kann ein % als Jokerzeichen angegeben werden.<br>
            Achtung: Gross/Kleinschreibung beachten!
          </li>
          <br>

          <li>&lt;default&gt;<br>
            Zur Zeit noch nicht implementiert.
          </li>
          <br>

          <li>&lt;fn&gt;
            Angabe einer speziellen Funktion:
            <ul>
              <li>int<br>
                Ermittelt den Zahlenwert ab dem Anfang der Zeichenkette aus der
                Spalte "VALUE". Benutzt z.B. für Ausprägungen wie 10%.
              </li>
              <li>int&lt;digit&gt;<br>
                Ermittelt den Zahlenwert ab dem Anfang der Zeichenkette aus der
                Spalte "VALUE", inclusive negativen Vorzeichen und Dezimaltrenner.
                Benutzt z.B. für Auspägungen wie -5.7&deg;C.
              </li>
              <li>delta-h / delta-d<br>
                Ermittelt die relative Veränderung eines Zahlenwertes pro Stunde
                oder pro Tag. Wird benutzt z.B. für Spalten die einen
                hochlaufenden Zähler enthalten wie im Falle für ein KS300 Regenzähler
                oder dem 1-wire Modul OWCOUNT.
              </li>
              <li>delta-ts<br>
                Ermittelt die vergangene Zeit zwischen dem letzten und dem aktuellen Logeintrag
                in Sekunden und ersetzt damit den originalen Wert.
              </li>
            </ul>
          </li>
          <br>

            <li>&lt;regexp&gt;<br>
              Diese Zeichenkette wird als Perl Befehl ausgewertet.
              Die regexp wird vor dem angegebenen &lt;fn&gt; Parameter ausgeführt.
              <br>
              Bitte zur Beachtung: Diese Zeichenkette darf keine Leerzeichen
              enthalten da diese sonst als &lt;column_spec&gt; Trennung
              interpretiert werden und alles nach dem Leerzeichen als neue
              &lt;column_spec&gt; gesehen wird. <br>
              <br>

              <b>Schlüsselwörter</b>

              <li>$val ist der aktuelle Wert die die Datenbank für ein Device/Reading ausgibt.</li>
              <li>$ts ist der aktuelle Timestamp des Logeintrages.</li>
              <li>Wird als $val das Schlüsselwort "hide" zurückgegeben, so wird dieser Logeintrag nicht
                  ausgegeben, trotzdem aber für die Zeitraumberechnung verwendet.</li>
              <li>Wird als $val das Schlüsselwort "ignore" zurückgegeben, so wird dieser Logeintrag
                  nicht für eine Folgeberechnung verwendet.</li>
            </li>
        </ul>
        </li>

      </ul>
    <br><br>
    <b>Beispiele:</b>
      <ul>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature</code></li><br>

        <li><code>get myDbLog current ALL - - %:temperature</code> <br>
            Damit erhält man alle aktuellen Readings "temperature" von allen in der DB geloggten Devices.
            Achtung: bei Nutzung von Jokerzeichen auf die history-Tabelle kann man sein FHEM aufgrund langer Laufzeit lahmlegen!
        </li>
        <br>

        <li><code>get myDbLog - - 2012-11-10_10 2012-11-10_20 KS300:temperature::int1</code><br>
           gibt Daten aus von 10Uhr bis 20Uhr am 10.11.2012
        </li>
        <br>

        <li><code>get myDbLog - all 2012-11-10 2012-11-20 KS300:temperature</code>
        </li>
        <br>

        <li><code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature KS300:rain::delta-h KS300:rain::delta-d</code>
        </li>
        <br>

        <li><code>get myDbLog - - 2012-11-10 2012-11-20 MyFS20:data:::$val=~s/(on|off).*/$1eq"on"?1:0/eg</code><br>
           gibt 1 zurück für alle Ausprägungen von on* (on|on-for-timer etc) und 0 für alle off*
        </li>
        <br>

        <li><code>get myDbLog - - 2012-11-10 2012-11-20 Bodenfeuchte:data:::$val=~s/.*B:\s([-\.\d]+).*/$1/eg</code><br>
           Beispiel von OWAD: Ein Wert wie z.B.: <code>"A: 49.527 % B: 66.647 % C: 9.797 % D: 0.097 V"</code><br>
           und die Ausgabe ist für das Reading B folgende: <code>2012-11-20_10:23:54 66.647</code>
        </li>
        <br>

        <li><code>get DbLog - - 2013-05-26 2013-05-28 Pumpe:data::delta-ts:$val=~s/on/hide/</code><br>
           Realisierung eines Betriebsstundenzählers. Durch delta-ts wird die Zeit in Sek zwischen den Log-
           Einträgen ermittelt. Die Zeiten werden bei den on-Meldungen nicht ausgegeben welche einer Abschaltzeit
           entsprechen würden.
        </li>
        <br>
      </ul>
  </li>
  </ul>
  <br>

  <b>Get</b> für die Nutzung von webcharts
  <br>
  <br>

  <ul>
  <li><b>get &lt;name&gt; &lt;in&gt; &lt;out&gt; &lt;from&gt;
          &lt;to&gt; &lt;device&gt; &lt;querytype&gt; &lt;xaxis&gt; &lt;yaxis&gt; &lt;savename&gt; &lt;chartconfig&gt; &lt;pagingstart&gt; &lt;paginglimit&gt; </b> <br><br>

    Liest Daten aus der Datenbank aus und gibt diese in JSON formatiert aus. Wird für das Charting Frontend
    (<a href="https://wiki.fhem.de/wiki/Neues_Charting_Frontend">Wiki: Neues Charting Frontend</a>) genutzt.
    <br>
    <br>

    <ul>
      <li>&lt;name&gt;<br>
        Der Name des definierten DbLog Devices, so wie er in der fhem.cfg angegeben wurde.
      </li>
      <br>

      <li>&lt;in&gt;<br>
        Dieser Parameter ist immer auf <code>-</code> zu setzen.
      </li>
      <br>

      <li>&lt;out&gt;<br>
        Dieser Parameter ist auf <code>webchart</code> zu setzen.
      </li>
      <br>

      <li>&lt;from&gt; / &lt;to&gt;<br>
        Wird benutzt um den Zeitraum der Daten einzugrenzen. Es ist das folgende
        Zeitformat zu benutzen:<br>

        <ul>
          <code>YYYY-MM-DD_HH24:MI:SS</code>
        </ul>
      </li>
      <br>

      <li>&lt;device&gt;<br>
        Ein String, der das abzufragende Device darstellt.
      </li>
      <br>

      <li>&lt;querytype&gt;<br>
        Ein String, der die zu verwendende Abfragemethode darstellt. Zur Zeit unterstützte Werte sind: <br>
          <code>getreadings</code> um für ein bestimmtes device alle Readings zu erhalten<br>
          <code>getdevices</code> um alle verfügbaren devices zu erhalten<br>
          <code>timerange</code> um Chart-Daten abzufragen. Es werden die Parameter 'xaxis', 'yaxis', 'device', 'to' und 'from' benötigt<br>
          <code>savechart</code> um einen Chart unter Angabe eines 'savename' und seiner zugehörigen Konfiguration abzuspeichern<br>
          <code>deletechart</code> um einen zuvor gespeicherten Chart unter Angabe einer id zu löschen<br>
          <code>getcharts</code> um eine Liste aller gespeicherten Charts zu bekommen.<br>
          <code>getTableData</code> um Daten aus der Datenbank abzufragen und in einer Tabelle darzustellen. Benötigt paging Parameter wie start und limit.<br>
          <code>hourstats</code> um Statistiken für einen Wert (yaxis) für eine Stunde abzufragen.<br>
          <code>daystats</code> um Statistiken für einen Wert (yaxis) für einen Tag abzufragen.<br>
          <code>weekstats</code> um Statistiken für einen Wert (yaxis) für eine Woche abzufragen.<br>
          <code>monthstats</code> um Statistiken für einen Wert (yaxis) für einen Monat abzufragen.<br>
          <code>yearstats</code> um Statistiken für einen Wert (yaxis) für ein Jahr abzufragen.<br>
      </li>
      <br>

      <li>&lt;xaxis&gt;<br>
        Ein String, der die X-Achse repräsentiert. Es muß ein gültiger Feldname, typisch 'TIMESTAMP', der history-Tabelle sein.
      </li>
      <br>

      <li>&lt;yaxis&gt;<br>
         Ein String, der die Y-Achse repräsentiert und auf den Namen des auszuwertenden Readings zu setzen ist.
      </li>
      <br>

      <li>&lt;savename&gt;<br>
         Ein String, unter dem ein Chart in der Datenbank gespeichert werden soll.
      </li>
      <br>

      <li>&lt;chartconfig&gt;<br>
         Ein jsonstring der den zu speichernden Chart repräsentiert.
      </li>
      <br>

      <li>&lt;pagingstart&gt;<br>
         Ein Integer um den Startwert für die Abfrage 'getTableData' festzulegen.
      </li>
      <br>

      <li>&lt;paginglimit&gt;<br>
         Ein Integer um den Limitwert für die Abfrage 'getTableData' festzulegen.
      </li>
      <br>
      </ul>
    <br>

    <b>Beispiele:</b>
      <ul>
        <li><code>get logdb - webchart "" "" "" getcharts</code><br>
            Liefert alle gespeicherten Charts aus der Datenbank</li>
            <br>
        <li><code>get logdb - webchart "" "" "" getdevices</code><br>
            Liefert alle verfügbaren Devices aus der Datenbank</li>
            <br>
        <li><code>get logdb - webchart "" "" ESA2000_LED_011e getreadings</code><br>
            Liefert alle verfügbaren Readings aus der Datenbank unter Angabe eines Gerätes</li>
            <br>
        <li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e timerange TIMESTAMP day_kwh</code><br>
            Liefert Chart-Daten, die auf folgenden Parametern basieren: 'xaxis', 'yaxis', 'device', 'to' und 'from'<br>
            Die Ausgabe erfolgt als JSON, z.B.: <code>[{'TIMESTAMP':'2013-02-11 00:10:10','VALUE':'0.22431388090756'},{'TIMESTAMP'.....}]</code></li>
            <br>
        <li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e savechart TIMESTAMP day_kwh tageskwh</code><br>
            Speichert einen Chart unter Angabe eines 'savename' und seiner zugehörigen Konfiguration</li>
            <br>
        <li><code>get logdb - webchart "" "" "" deletechart "" "" 7</code><br>
            Löscht einen zuvor gespeicherten Chart unter Angabe einer id</li>
      </ul>
    <br>
    <br>
  </ul>
  </li>


  <a id="DbLog-attr"></a>
  <b>Attribute</b>
  <br>
  <br>

  <ul>
    <a id="DbLog-attr-addStateEvent"></a>
    <li><b>addStateEvent [0|1] </b> <br><br>
    <ul>

      Bekanntlich wird normalerweise bei einem Event mit dem Reading "state" der state-String entfernt, d.h.
      der Event ist nicht zum Beispiel "state: on" sondern nur "on". <br>
      Meistens ist es aber hilfreich in DbLog den kompletten Event verarbeiten zu können. Deswegen übernimmt DbLog per Default
      den Event inklusive dem Reading-String "state". <br>
      In einigen Fällen, z.B. alten oder speziellen Modulen, ist es allerdings wünschenswert den state-String wie gewöhnlich
      zu entfernen. In diesen Fällen bitte addStateEvent = "0" setzen.
      Versuchen sie bitte diese Einstellung, falls es mit dem Standard Probleme geben sollte.
      <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-asyncMode"></a>
    <li><b>asyncMode [0|1] </b> <br><br>

    <ul>
      Dieses Attribut stellt den Verarbeitungsprozess ein nach dessen Verfahren das DbLog Device die Daten in die
      Datenbank schreibt. <br>
      DbLog verwendet zum Schreiben der Log-Daten in die Datenbank einen SubProzess und verarbeitet die Daten
      generell nicht blockierend für FHEM. <br>
      Dadurch erfolgt der Schreibprozess in die Datenbank generell nicht blockierend und FHEM wird in dem Fall,
      dass die Datenbank nicht performant arbeitet oder nicht verfügbar ist (Wartung, Fehlerzustand, etc.),
      nicht beeinträchtigt.<br>
      (default: 0)
      <br><br>

      <ul>
       <table>
       <colgroup> <col width=5%> <col width=95%> </colgroup>
       <tr><td> 0 - </td><td><b>Synchroner Log-Modus.</b> Die zu loggenden Daten werden nur kurz im Cache zwischengespeichert und sofort           </td></tr>
       <tr><td>     </td><td>in die Datenbank geschrieben.                                                                                         </td></tr>
       <tr><td>     </td><td><b>Vorteile:</b>                                                                                                      </td></tr>
       <tr><td>     </td><td>Die Daten stehen im Prinzip sofort in der Datenbank zur Verfügung.                                                    </td></tr>
       <tr><td>     </td><td>Bei einem Absturz von FHEM gehen sehr wenige bis keine Daten verloren.                                                </td></tr>
       <tr><td>     </td><td><b>Nachteile:</b>                                                                                                     </td></tr>
       <tr><td>     </td><td>Eine alternative Speicherung im Filesystem (bei Datenbankproblemen) wird nicht unterstützt.                           </td></tr>
       <tr><td>     </td><td>                                                                                                                      </td></tr>
       <tr><td>     </td><td>                                                                                                                      </td></tr>
       <tr><td> 1 - </td><td><b>Asynchroner Log-Modus.</b> Die zu loggenden Daten werden zunächst in einem Memory Cache zwischengespeichert        </td></tr>
       <tr><td>     </td><td>und abhängig von einem <a href="#DbLog-attr-syncInterval">Zeitintervall</a> bzw. <a href="#DbLog-attr-cacheLimit">Füllgrad</a> des Caches in die Datenbank geschrieben.   </td></tr>
       <tr><td>     </td><td><b>Vorteile:</b>                                                                                                      </td></tr>
       <tr><td>     </td><td>Die Daten werden zwischengespeichert und gehen nicht verloren wenn die Datenbank nicht verfügbar ist                  </td></tr>
       <tr><td>     </td><td>oder fehlerhaft arbeitet. Die alternative Speicherung im Filesystem wird unterstützt.                                 </td></tr>
       <tr><td>     </td><td><b>Nachteile:</b>                                                                                                     </td></tr>
       <tr><td>     </td><td>Die Daten stehen zeitlich verzögert in der Datenbank zur Verfügung.                                                   </td></tr>
       <tr><td>     </td><td>Bei einem Absturz von FHEM gehen alle im Memory Cache zwischengespeicherten Daten verloren.                           </td></tr>
       </table>
      </ul>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-cacheEvents"></a>
    <li><b>cacheEvents [2|1|0] </b> <br><br>

    <ul>
      <ul>
       <table>
       <colgroup> <col width=5%> <col width=95%> </colgroup>
       <tr><td> 0 - </td><td>Es werden keine Events für CacheUsage erzeugt.                                                             </td></tr>
       <tr><td> 1 - </td><td>Es werden Events für das Reading CacheUsage erzeugt wenn ein neuer Datensatz zum Cache hinzugefügt wurde.  </td></tr>
       <tr><td> 2 - </td><td>Es werden Events für das Reading CacheUsage erzeugt wenn im asynchronen Mode der Schreibzyklus in die      </td></tr>
       <tr><td>     </td><td>Datenbank beginnt. CacheUsage enthält zu diesem Zeitpunkt die Anzahl der im Cache befindlichen             </td></tr>
       <tr><td>     </td><td>Datensätze.                                                                                                </td></tr>
       </table>
      </ul>

      (default: 0) <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-cacheLimit"></a>
     <li><b>cacheLimit &lt;n&gt; </b> <br><br>

     <ul>
       Im asynchronen Logmodus wird der Cache in die Datenbank weggeschrieben und geleert wenn die Anzahl &lt;n&gt; Datensätze
       im Cache erreicht ist. <br>
       Der Timer des asynchronen Logmodus wird dabei neu auf den Wert des Attributs "syncInterval"
       gesetzt. Im Fehlerfall wird ein erneuter Schreibversuch frühestens nach syncInterval/2 gestartet. <br>
       (default: 500)
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-cacheOverflowThreshold"></a>
     <li><b>cacheOverflowThreshold &lt;n&gt; </b> <br><br>

     <ul>
       Legt im asynchronen Logmodus den Schwellenwert von &lt;n&gt; Datensätzen fest, ab dem der Cacheinhalt in ein File
       exportiert wird anstatt die Daten in die Datenbank zu schreiben. <br>
       Die ausgeführte Funktion entspricht dem Set-Kommando "exportCache purgecache" und verwendet dessen Einstellungen.
       <br><br>

       Mit diesem Attribut kann eine Überlastung des Serverspeichers verhindert werden falls die Datenbank für eine längere
       Zeit nicht verfügbar ist (z.B. im Fehler- oder Wartungsfall). Ist der Attributwert kleiner oder gleich dem Wert des
       Attributs "cacheLimit", wird der Wert von "cacheLimit" für "cacheOverflowThreshold" verwendet. <br>
       In diesem Fall wird der Cache <b>immer</b> in ein File geschrieben anstatt in die Datenbank sofern der Schwellenwert
       erreicht wurde. <br>
       So können die Daten mit dieser Einstellung gezielt in ein oder mehrere Dateien geschreiben werden, um sie zu einem
       späteren Zeitpunkt mit dem Set-Befehl "importCachefile" in die Datenbank zu importieren.
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-colEvent"></a>
     <li><b>colEvent &lt;n&gt; </b> <br><br>

     <ul>
       Die Feldlänge für das DB-Feld EVENT wird userspezifisch angepasst. Mit dem Attribut kann der Default-Wert im Modul
       verändert werden wenn die Feldlänge in der Datenbank manuell geändert wurde. 
       Mit colEvent=0 wird das Datenbankfeld EVENT nicht gefüllt. <br>
       <b>Hinweis:</b> <br>
       Mit gesetztem Attribut gelten alle Feldlängenbegrenzungen auch für SQLite DB wie im Internal COLUMNS angezeigt!  <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-colReading"></a>
     <li><b>colReading &lt;n&gt; </b> <br><br>

     <ul>
       Die Feldlänge für das DB-Feld READING wird userspezifisch angepasst. Mit dem Attribut kann der Default-Wert im Modul
       verändert werden wenn die Feldlänge in der Datenbank manuell geändert wurde. 
       Mit colReading=0 wird das Datenbankfeld READING nicht gefüllt. <br>
       <b>Hinweis:</b> <br>
       Mit gesetztem Attribut gelten alle Feldlängenbegrenzungen auch für SQLite DB wie im Internal COLUMNS angezeigt!  <br>
     </ul>
     </li>
  </ul>
  <br>
  
  <ul>
     <a id="DbLog-attr-colType"></a>
     <li><b>colType &lt;n&gt; </b> <br><br>

     <ul>
       Die Feldlänge für das DB-Feld TYPE wird userspezifisch angepasst. Mit dem Attribut kann der Default-Wert im Modul
       verändert werden wenn die Feldlänge in der Datenbank manuell geändert wurde. 
       Mit colType=0 wird das Datenbankfeld TYPE nicht gefüllt. <br>
       <b>Hinweis:</b> <br>
       Mit gesetztem Attribut gelten alle Feldlängenbegrenzungen auch für SQLite DB wie im Internal COLUMNS angezeigt!  <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-colValue"></a>
     <li><b>colValue &lt;n&gt; </b> <br><br>

     <ul>
       Die Feldlänge für das DB-Feld VALUE wird userspezifisch angepasst. Mit dem Attribut kann der Default-Wert im Modul
       verändert werden wenn die Feldlänge in der Datenbank manuell geändert wurde. 
       Mit colValue=0 wird das Datenbankfeld VALUE nicht gefüllt. <br>
       <b>Hinweis:</b> <br>
       Mit gesetztem Attribut gelten alle Feldlängenbegrenzungen auch für SQLite DB wie im Internal COLUMNS angezeigt!  <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-commitMode"></a>
    <li><b>commitMode [basic_ta:on | basic_ta:off | ac:on_ta:on | ac:on_ta:off | ac:off_ta:on] </b> <br><br>

    <ul>
      Ändert die Verwendung der Datenbank Autocommit- und/oder Transaktionsfunktionen.
      Wird Transaktion "aus" verwendet, werden im asynchronen Modus nicht gespeicherte Datensätze nicht an den Cache zurück
      gegeben.
      Dieses Attribut ist ein advanced feature und sollte nur im konkreten Bedarfs- bzw. Supportfall geändert werden.<br><br>

      <ul>
      <li>basic_ta:on   - Autocommit Servereinstellung / Transaktion ein (default) </li>
      <li>basic_ta:off  - Autocommit Servereinstellung / Transaktion aus </li>
      <li>ac:on_ta:on   - Autocommit ein / Transaktion ein </li>
      <li>ac:on_ta:off  - Autocommit ein / Transaktion aus </li>
      <li>ac:off_ta:on  - Autocommit aus / Transaktion ein (Autocommit "aus" impliziert Transaktion "ein") </li>
      </ul>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-convertTimezone"></a>
     <li><b>convertTimezone [UTC | none] </b> <br><br>

     <ul>
       UTC - der lokale Timestamp des Events wird nach UTC konvertiert. <br>
       (default: none) <br><br>

       <b>Hinweis:</b> <br>
       Die Perl-Module 'DateTime' und 'DateTime::Format::Strptime' müssen installiert sein !
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-DbLogType"></a>
     <li><b>DbLogType [Current|History|Current/History|SampleFill/History] </b> <br><br>

     <ul>
       Dieses Attribut legt fest, welche Tabelle oder Tabellen in der Datenbank genutzt werden sollen. Ist dieses Attribut nicht gesetzt, wird
       per default die Einstellung <i>history</i> verwendet. <br><br>

       Bedeutung der Einstellungen sind: <br><br>

       <ul>
       <table>
       <colgroup> <col width=10%> <col width=90%> </colgroup>
       <tr><td> <b>Current</b>            </td><td>Events werden nur in die current-Tabelle geloggt.
                                                   Die current-Tabelle wird bei der SVG-Erstellung ausgewertet.  </td></tr>
       <tr><td> <b>History</b>            </td><td>Events werden nur in die history-Tabelle geloggt. Es wird keine DropDown-Liste mit Vorschlägen bei der SVG-Erstellung
                                                   erzeugt.   </td></tr>
       <tr><td> <b>Current/History</b>    </td><td>Events werden sowohl in die current- also auch in die hitory Tabelle geloggt.
                                                   Die current-Tabelle wird bei der SVG-Erstellung ausgewertet.</td></tr>
       <tr><td> <b>SampleFill/History</b> </td><td>Events werden nur in die history-Tabelle geloggt. Die current-Tabelle wird bei der SVG-Erstellung ausgewertet und
                                                   kann zur Erzeugung einer DropDown-Liste mittels einem
                                                   <a href="#DbRep">DbRep-Device</a> <br> "set &lt;DbRep-Name&gt; tableCurrentFillup" mit
                                                   einem einstellbaren Extract der history-Tabelle gefüllt werden (advanced Feature).  </td></tr>
       </table>
       </ul>
       <br>
       <br>

       <b>Hinweis:</b> <br>
       Die Current-Tabelle muß genutzt werden um eine Device:Reading-DropDownliste zur Erstellung eines
       SVG-Plots zu erhalten.   <br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-DbLogSelectionMode"></a>
    <li><b>DbLogSelectionMode [Exclude|Include|Exclude/Include] </b> <br><br>

    <ul>
      Dieses für DbLog-Devices spezifische Attribut beeinflußt, wie die Device-spezifischen Attribute
      <a href="#DbLog-attr-DbLogExclude">DbLogExclude</a> und <a href="#DbLog-attr-DbLogInclude">DbLogInclude</a>
      ausgewertet werden. DbLogExclude und DbLogInclude werden in den Quellen-Devices gesetzt. <br>
      Ist das Attribut DbLogSelectionMode nicht gesetzt, ist "Exclude" der Default.
      <br><br>

      <ul>
        <li><b>Exclude:</b> Readings werden geloggt wenn sie auf den im DEF angegebenen Regex matchen. Ausgeschlossen werden
                            die Readings, die auf den Regex im Attribut DbLogExclude matchen. <br>
                            Das Attribut DbLogInclude wird in diesem Fall nicht berücksichtigt.
                            </li>
                            <br>
        <li><b>Include:</b> Es werden nur Readings geloggt welche über den Regex im Attribut DbLogInclude
                            eingeschlossen werden. <br>
                            Das Attribut DbLogExclude wird in diesem Fall ebenso wenig berücksichtigt wie der Regex im DEF.
                            </li>
                            <br>
        <li><b>Exclude/Include:</b> Funktioniert im Wesentlichen wie "Exclude", nur dass sowohl das Attribut DbLogExclude
                                    als auch das Attribut DbLogInclude geprüft wird.
                                    Readings die durch DbLogExclude zwar ausgeschlossen wurden, mit DbLogInclude aber
                                    wiederum eingeschlossen werden, werden somit dennoch beim Logging berücksichtigt.
                                    </li>
      </ul>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-DbLogInclude"></a>
    <li><b>DbLogInclude Regex[:MinInterval][:force],[Regex[:MinInterval][:force]], ...  </b> <br><br>

    <ul>
      Mit dem Attribut DbLogInclude werden die Readings definiert, die in der Datenbank gespeichert werden sollen. <br>
      Die Definition der zu speichernden Readings erfolgt über einen regulären Ausdruck und alle Readings, die mit dem
      regulären Ausdruck matchen, werden in der Datenbank gespeichert. <br>

      Der optionale Zusatz &lt;MinInterval&gt; gibt an, dass ein Wert dann gespeichert wird wenn mindestens &lt;MinInterval&gt;
      Sekunden seit der letzten Speicherung vergangen sind. <br>

      Unabhängig vom Ablauf des Intervalls wird das Reading gespeichert wenn sich der Wert des Readings verändert hat. <br>
      Mit dem optionalen Modifier "force" kann erzwungen werden das angegebene Intervall &lt;MinInterval&gt; einzuhalten auch
      wenn sich der Wert des Readings seit der letzten Speicherung verändert hat.
      <br><br>

      <ul>
      <pre>
        | <b>Modifier</b> |         <b>innerhalb Intervall</b>          | <b>außerhalb Intervall</b> |
        |          | Wert gleich        | Wert geändert   |                     |
        |----------+--------------------+-----------------+---------------------|
        | &lt;none&gt;   | ignorieren         | speichern       | speichern           |
        | force    | ignorieren         | ignorieren      | speichern           |
      </pre>
      </ul>

      <br>
      <b>Hinweise: </b> <br>
      Das Attribut DbLogInclude wird in allen Devices propagiert wenn DbLog verwendet wird. <br>
      Das Attribut <a href="#DbLog-attr-DbLogSelectionMode">DbLogSelectionMode</a> muss entsprechend gesetzt sein
      um DbLogInclude zu aktivieren. <br>
      Mit dem Attribut <a href="#DbLog-attr-defaultMinInterval">defaultMinInterval</a> kann ein Default für
      &lt;MinInterval&gt; vorgegeben werden.
      <br><br>

      <b>Beispiele: </b> <br>
      <code>attr MyDevice1 DbLogInclude .*</code> <br>
      <code>attr MyDevice2 DbLogInclude state,(floorplantext|MyUserReading):300,battery:3600</code> <br>
      <code>attr MyDevice2 DbLogInclude state,(floorplantext|MyUserReading):300:force,battery:3600:force</code>
    </ul>

  </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-DbLogExclude"></a>
    <li><b>DbLogExclude Regex[:MinInterval][:force],[regex[:MinInterval][:force]] ... </b> <br><br>

    <ul>
      Mit dem Attribut DbLogExclude werden die Readings definiert, die <b>nicht</b> in der Datenbank gespeichert werden
      sollen. <br>
      Die Definition der auszuschließenden Readings erfolgt über einen regulären Ausdruck und alle Readings, die mit dem
      regulären Ausdruck matchen, werden vom Logging in die Datenbank ausgeschlossen. <br>

      Readings, die nicht über den Regex ausgeschlossen wurden, werden in der Datenbank geloggt. Das Verhalten der
      Speicherung wird mit den nachfolgenden optionalen Angaben gesteuert. <br>
      Der optionale Zusatz &lt;MinInterval&gt; gibt an, dass ein Wert dann gespeichert wird wenn mindestens &lt;MinInterval&gt;
      Sekunden seit der letzten Speicherung vergangen sind. <br>

      Unabhängig vom Ablauf des Intervalls wird das Reading gespeichert wenn sich der Wert des Readings verändert hat. <br>
      Mit dem optionalen Modifier "force" kann erzwungen werden das angegebene Intervall &lt;MinInterval&gt; einzuhalten auch
      wenn sich der Wert des Readings seit der letzten Speicherung verändert hat.
      <br><br>

      <ul>
      <pre>
        | <b>Modifier</b> |         <b>innerhalb Intervall</b>          | <b>außerhalb Intervall</b> |
        |          | Wert gleich        | Wert geändert   |                     |
        |----------+--------------------+-----------------+---------------------|
        | &lt;none&gt;   | ignorieren         | speichern       | speichern           |
        | force    | ignorieren         | ignorieren      | speichern           |
      </pre>
      </ul>

      <br>
      <b>Hinweise: </b> <br>
      Das Attribut DbLogExclude wird in allen Devices propagiert wenn DbLog verwendet wird. <br>
      Das Attribut <a href="#DbLog-attr-DbLogSelectionMode">DbLogSelectionMode</a> kann entsprechend gesetzt werden
      um DbLogExclude zu deaktivieren. <br>
      Mit dem Attribut <a href="#DbLog-attr-defaultMinInterval">defaultMinInterval</a> kann ein Default für
      &lt;MinInterval&gt; vorgegeben werden.
      <br><br>

      <b>Beispiel</b> <br>
      <code>attr MyDevice1 DbLogExclude .*</code> <br>
      <code>attr MyDevice2 DbLogExclude state,(floorplantext|MyUserReading):300,battery:3600</code> <br>
      <code>attr MyDevice2 DbLogExclude state,(floorplantext|MyUserReading):300:force,battery:3600:force</code>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-DbLogValueFn"></a>
     <li><b>DbLogValueFn {} </b> <br><br>

     <ul>
       Wird DbLog genutzt, wird in allen Devices das Attribut <i>DbLogValueFn</i> propagiert.
       Dieses Attribut wird in den <b>Quellendevices</b> gesetzt und erlaubt die Veränderung der Werte vor dem Logging
       oder den Ausschluß des Datensatzes vom Logging. <br><br>

       Es kann auf die Variablen $TIMESTAMP, $READING, $VALUE (Wert des Readings) und $UNIT (Einheit des Readingswert)
       zugegriffen und diese vor dem Loggen in die Datenbank verändert werden. <br>
       Nur Lesezugriff besteht auf $DEVICE (den Namen des Quellengeräts), $EVENT, $LASTTIMESTAMP und $LASTVALUE. <br><br>

       Die Variablen $LASTTIMESTAMP und $LASTVALUE enthalten Zeit und Wert des zuletzt protokollierten Datensatzes von
       $DEVICE / $READING. <br>
       Soll $TIMESTAMP verändert werden, muss die Form "yyyy-mm-dd hh:mm:ss" eingehalten werden.
       Anderenfalls wird die geänderte $TIMESTAMP Variable nicht übernommen.
       Durch Setzen der Variable "$IGNORE=1" wird der Datensatz vom Logging ausgeschlossen. <br><br>

       Die devicespezifische Funktion in "DbLogValueFn" wird vor der eventuell im DbLog-Device vorhandenen Funktion im Attribut
       "valueFn" auf den Datensatz angewendet.
       <br><br>

       <b>Beispiel</b> <br>
<pre>
attr SMA_Energymeter DbLogValueFn
{
  if ($READING eq "Bezug_WirkP_Kosten_Diff") {
    $UNIT="Diff-W";
  }
  if ($READING =~ /Einspeisung_Wirkleistung_Zaehler/ && $VALUE < 2) {
    $IGNORE=1;
  }
}
</pre>
     </ul>
     </li>
  </ul>

  <ul>
    <a id="DbLog-attr-dbSchema"></a>
    <li><b>dbSchema &lt;schema&gt; </b> <br><br>

    <ul>
      Dieses Attribut ist setzbar für die Datenbanken MySQL/MariaDB und PostgreSQL. Die Tabellennamen (current/history) werden
      durch das angegebene Datenbankschema ergänzt. Das Attribut ist ein advanced Feature und nomalerweise nicht nötig zu setzen.
      <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-defaultMinInterval"></a>
    <li><b>defaultMinInterval &lt;devspec&gt;::&lt;MinInterval&gt;[::force],[&lt;devspec&gt;::&lt;MinInterval&gt;[::force]] ... </b> <br><br>
    <ul>
      Mit diesem Attribut wird ein Standard Minimum Intervall für <a href="http://fhem.de/commandref_DE.html#devspec">devspec</a> festgelegt.
      Ist defaultMinInterval angegeben, wird der Logeintrag nicht geloggt, wenn das Intervall noch nicht erreicht <b>und</b> der
      Wert des Readings sich <b>nicht</b> verändert hat. <br>
      Ist der optionale Parameter "force" hinzugefügt, wird der Logeintrag auch dann nicht geloggt, wenn sich der
      Wert des Readings verändert hat. <br>
      Eventuell im Quelldevice angegebene Spezifikationen DbLogExclude / DbLogInclude haben Vorrag und werden durch
      defaultMinInterval <b>nicht</b> überschrieben. <br>
      Die Eingabe kann mehrzeilig erfolgen. <br><br>

      <b>Beispiele</b> <br>
      <code>attr dblog defaultMinInterval .*::120::force </code> <br>
      # Events aller Devices werden nur geloggt, wenn 120 Sekunden zum letzten Logeintrag vergangen sind ist (Reading spezifisch) unabhängig von einer eventuellen Änderung des Wertes. <br>
      <code>attr dblog defaultMinInterval (Weather|SMA)::300 </code> <br>
      # Events der Devices "Weather" und "SMA" werden nur geloggt wenn 300 Sekunden zum letzten Logeintrag vergangen sind (Reading spezifisch) und sich der Wert nicht geändert hat. <br>
      <code>attr dblog defaultMinInterval TYPE=CUL_HM::600::force </code> <br>
      # Events aller Devices des Typs "CUL_HM" werden nur geloggt, wenn 600 Sekunden zum letzten Logeintrag vergangen sind (Reading spezifisch) unabhängig von einer eventuellen Änderung des Wertes.
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-excludeDevs"></a>
     <li><b>excludeDevs &lt;devspec1&gt;[#Reading],&lt;devspec2&gt;[#Reading],&lt;devspec...&gt; </b> <br><br>

     <ul>
       Die Device/Reading-Kombinationen "devspec1#Reading", "devspec2#Reading" bis "devspec..." werden vom Logging in die
       Datenbank global ausgeschlossen. <br>
       Die Angabe eines auszuschließenden Readings ist optional. <br>
       Somit können Device/Readings explizit bzw. konsequent vom Logging ausgeschlossen werden ohne Berücksichtigung anderer
       Excludes oder Includes (z.B. im DEF).
       Die auszuschließenden Devices können als <a href="#devspec">Geräte-Spezifikation</a> angegeben werden.
       Für weitere Details bezüglich devspec siehe <a href="#devspec">Geräte-Spezifikation</a>.  <br><br>

      <b>Beispiel</b> <br>
      <code>
      attr &lt;device&gt; excludeDevs global,Log.*,Cam.*,TYPE=DbLog
      </code><br>
      # Es werden die Devices global bzw. Devices beginnend mit "Log" oder "Cam" bzw. Devices vom Typ "DbLog" vom Logging ausgeschlossen. <br>
      <code>
      attr &lt;device&gt; excludeDevs .*#.*Wirkleistung.*
      </code><br>
      # Es werden alle Device/Reading-Kombinationen mit "Wirkleistung" im Reading vom Logging ausgeschlossen. <br>
      <code>
      attr &lt;device&gt; excludeDevs SMA_Energymeter#Bezug_WirkP_Zaehler_Diff
      </code><br>
      # Es wird der Event mit Device "SMA_Energymeter" und Reading "Bezug_WirkP_Zaehler_Diff" vom Logging ausgeschlossen. <br>

      </ul>
      </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-expimpdir"></a>
     <li><b>expimpdir &lt;directory&gt; </b> <br><br>

     <ul>
       In diesem Verzeichnis wird das Cachefile beim Export angelegt bzw. beim Import gesucht. Siehe set-Kommandos
       <a href="#DbLog-set-exportCache">exportCache</a> bzw. <a href="#DbLog-set-importCachefile">importCachefile</a>.
       Das Default-Verzeichnis ist "(global->modpath)/log/".
       Das im Attribut angegebene Verzeichnis muss vorhanden und beschreibbar sein. <br><br>

      <b>Beispiel</b> <br>
      <code>
      attr &lt;device&gt; expimpdir /opt/fhem/cache/
      </code><br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-exportCacheAppend"></a>
     <li><b>exportCacheAppend [1|0] </b> <br><br>

     <ul>
       Wenn gesetzt, wird beim Export des Cache ("set &lt;device&gt; exportCache") der Cacheinhalt an das neueste bereits vorhandene
       Exportfile angehängt. Ist noch kein Exportfile vorhanden, wird es neu angelegt. <br>
       Ist das Attribut nicht gesetzt, wird bei jedem Exportvorgang ein neues Exportfile angelegt. (default)<br/>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-insertMode"></a>
    <li><b>insertMode [1|0] </b> <br><br>

    <ul>
      Schaltet den Insert-Modus der Datenbankschnittstelle um. <br><br>

      <ul>
       <table>
       <colgroup> <col width=5%> <col width=95%> </colgroup>
       <tr><td> 0 - </td><td>Die Daten werden als Array der Datenbankschnittstelle übergeben.                                                 </td></tr>
       <tr><td>     </td><td>Es ist in den meisten Fällen der performanteste Weg viele Daten auf einmal in die Datenbank einzufügen.          </td></tr>
       <tr><td> 1 - </td><td>Die Datensätze werden sequentiell der Datenbankschnittstelle übergeben und in die DB eingefügt.                  </td></tr>
       </table>
      </ul>
      <br>

      (default: 0)
    </ul>
  </ul>
  </li>
  <br>

  <ul>
     <a id="DbLog-attr-noSupportPK"></a>
     <li><b>noSupportPK [1|0] </b> <br><br>

     <ul>
       Deaktiviert die programmtechnische Unterstützung eines gesetzten Primary Key durch das Modul.<br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-plotInputFieldLength"></a>
     <li><b>plotInputFieldLength &lt;Ganzzahl&gt; </b> <br><br>

     <ul>
        Breite der Plot Editor Eingabefelder für Device:Reading und Funktion. <br>
        Wird die Drop-Down Liste als Eingabehilfe für Device:Reading verwendet, wird die Breite des Feldes
        automatisch eingestellt. <br>
        (default: 40)
     </ul>
     </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-showproctime"></a>
    <li><b>showproctime [1|0] </b> <br><br>

    <ul>
      Wenn gesetzt, zeigt das Reading "sql_processing_time" die benötigte Abarbeitungszeit (in Sekunden) für die
      SQL-Ausführung der durchgeführten Funktion.
      Dabei wird nicht ein einzelnes SQL-Statement, sondern die Summe aller ausgeführten SQL-Kommandos innerhalb der
      jeweiligen Funktion betrachtet. <br>
      Das Reading "background_processing_time" zeigt die im SubProcess verbrauchte Zeit.
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-showNotifyTime"></a>
    <li><b>showNotifyTime [1|0] </b> <br><br>

    <ul>
      Wenn gesetzt, zeigt das Reading "notify_processing_time" die benötigte Abarbeitungszeit (in Sekunden) für die
      Abarbeitung der DbLog Notify-Funktion. <br>
      Das Attribut ist für Performance Analysen geeignet und hilft auch die Unterschiede
      im Zeitbedarf der Eventverarbeitung im synchronen bzw. asynchronen Modus festzustellen. <br>
      (default: 0)
      <br><br>

      <b>Hinweis:</b> <br>
      Das Reading "notify_processing_time" erzeugt sehr viele Events und belasted das System. Deswegen sollte bei Benutzung
      des Attributes die Eventerzeugung durch das Setzen von Attribut "event-min-interval" auf
      z.B. "notify_processing_time:30" deutlich begrenzt werden.
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-SQLiteCacheSize"></a>
     <li><b>SQLiteCacheSize &lt;Anzahl Memory Pages für Cache&gt; </b> <br><br>

     <ul>
       Standardmäßig werden ca. 4MB RAM für Caching verwendet (page_size=1024bytes, cache_size=4000).<br>
       Bei Embedded Devices mit wenig RAM genügen auch 1000 Pages - zu Lasten der Performance. <br>
       (default: 4000)
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-SQLiteJournalMode"></a>
     <li><b>SQLiteJournalMode [WAL|off] </b> <br><br>

     <ul>
       Moderne SQLite Datenbanken werden mit einem Write-Ahead-Log (<b>WAL</b>) geöffnet, was optimale Datenintegrität
       und gute Performance gewährleistet.<br>
       Allerdings benötigt WAL zusätzlich ungefähr den gleichen Festplattenplatz wie die eigentliche Datenbank. Bei knappem
       Festplattenplatz (z.B. eine RAM Disk in Embedded Devices) kann das Journal deaktiviert werden (<b>off</b>).
       Im Falle eines Datenfehlers kann die Datenbank aber wahrscheinlich nicht repariert werden, und muss neu erstellt
       werden! <br>
       (default: WAL)
     </ul>
     </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-syncEvents"></a>
    <li><b>syncEvents [1|0] </b> <br><br>

    <ul>
      es werden Events für Reading NextSync erzeugt. <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-syncInterval"></a>
    <li><b>syncInterval &lt;n&gt; </b> <br><br>

    <ul>
      Wenn im DbLog-Device der asynchrone Modus eingestellt ist (asyncMode=1), wird mit diesem Attribut das Intervall
      (Sekunden) zum Wegschreiben der zwischengespeicherten Daten in die Datenbank festgelegt. <br>
      (default: 30)
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-suppressAddLogV3"></a>
    <li><b>suppressAddLogV3 [1|0] </b> <br><br>

    <ul>
      Wenn gesetzt werden verbose 3 Logeinträge durch die addLog-Funktion unterdrückt.  <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-suppressUndef"></a>
    <li><b>suppressUndef</b> <br><br>

    <ul>
      Unterdrückt alle undef Werte die durch eine Get-Anfrage, z.B. Plot, aus der Datenbank selektiert werden.
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-timeout"></a>
    <li><b>timeout &lt;n&gt; </b> <br><br>

    <ul>
      Setzt den Timeout-Wert für die Operationen im SubProzess in Sekunden. <br>
      Ist eine gestartete Operation (Logging, Kommando) nicht innerhalb des Timeout-Wertes beendet,
      wird der laufende SubProzess abgebrochen und ein neuer Prozess gestartet. <br>
      (default: 86400)
    </ul>
  </ul>
  </li>
  <br>

  <ul>
    <a id="DbLog-attr-traceFlag"></a>
    <li><b>traceFlag &lt;ALL|SQL|CON|ENC|DBD|TXN&gt; </b> <br><br>

    <ul>
      Bestimmt das Tracing von bestimmten Aktivitäten innerhalb des Datenbankinterfaces und Treibers. Das Attribut ist nur
      für den Fehler- bzw. Supportfall gedacht. <br><br>

       <ul>
       <table>
       <colgroup> <col width=10%> <col width=90%> </colgroup>
       <tr><td> <b>ALL</b>            </td><td>schaltet alle DBI- und Treiberflags an.  </td></tr>
       <tr><td> <b>SQL</b>            </td><td>verfolgt die SQL Statement Ausführung. (Default) </td></tr>
       <tr><td> <b>CON</b>            </td><td>verfolgt den Verbindungsprozess.  </td></tr>
       <tr><td> <b>ENC</b>            </td><td>verfolgt die Kodierung (Unicode Übersetzung etc).  </td></tr>
       <tr><td> <b>DBD</b>            </td><td>verfolgt nur DBD Nachrichten.  </td></tr>
       <tr><td> <b>TXN</b>            </td><td>verfolgt Transaktionen.  </td></tr>

       </table>
       </ul>
       <br>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-traceLevel"></a>
    <li><b>traceLevel &lt;0|1|2|3|4|5|6|7&gt; </b> <br><br>

    <ul>
      Schaltet die Trace-Funktion des Moduls ein. <br>
      <b>Achtung !</b> Das Attribut ist nur für den Fehler- bzw. Supportfall gedacht. Es werden <b>sehr viele Einträge</b> in
      das FHEM Logfile vorgenommen ! <br><br>

       <ul>
       <table>
       <colgroup> <col width=5%> <col width=95%> </colgroup>
       <tr><td> <b>0</b>            </td><td>Tracing ist disabled. (Default)  </td></tr>
       <tr><td> <b>1</b>            </td><td>Tracing von DBI Top-Level Methoden mit deren Ergebnissen und Fehlern </td></tr>
       <tr><td> <b>2</b>            </td><td>Wie oben. Zusätzlich Top-Level Methodeneintäge mit Parametern.  </td></tr>
       <tr><td> <b>3</b>            </td><td>Wie oben. Zusätzliche werden einige High-Level Informationen des Treibers und
                                             einige interne Informationen des DBI hinzugefügt.  </td></tr>
       <tr><td> <b>4</b>            </td><td>Wie oben. Zusätzlich werden mehr detaillierte Informationen des Treibers
                                             eingefügt. </td></tr>
       <tr><td> <b>5-7</b>          </td><td>Wie oben, aber mit mehr und mehr internen Informationen.  </td></tr>

       </table>
       </ul>
       <br>

    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a id="DbLog-attr-useCharfilter"></a>
    <li><b>useCharfilter [0|1] </b> <br><br>

    <ul>
      wenn gesetzt, werden nur ASCII Zeichen von 32 bis 126 im Event akzeptiert. (default: 0) <br>
      Das sind die Zeichen " A-Za-z0-9!"#$%&'()*+,-.\/:;<=>?@[\\]^_`{|}~". <br>
      Umlaute und "€" werden umgesetzt (z.B. ä nach ae, € nach EUR).  <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-valueFn"></a>
     <li><b>valueFn {} </b> <br><br>

     <ul>
       Dieses Attribut wird im <b>DbLog-Device</b> gesetzt und erlaubt die Veränderung der Werte vor dem Logging
       oder den Ausschluß des Datensatzes vom Logging. <br><br>

       Es kann auf die Variablen $TIMESTAMP, $DEVICE (Quellendevice), $DEVICETYPE, $EVENT, $READING, $VALUE 
       (Wert des Readings) und $UNIT (Einheit des Readingswert) zugegriffen und diese vor dem Loggen in die Datenbank 
       verändert werden. <br>
       Nur Lesezugriff besteht auf $LASTTIMESTAMP, $LASTVALUE und $NAME (Name des DbLog Devices). <br><br>

       Die Variablen $LASTTIMESTAMP und $LASTVALUE enthalten Zeit und Wert des zuletzt protokollierten Datensatzes von
       $DEVICE / $READING. <br>
       Soll $TIMESTAMP verändert werden, muss die Form "yyyy-mm-dd hh:mm:ss" eingehalten werden.
       Anderenfalls wird die geänderte $TIMESTAMP Variable nicht übernommen.
       Durch Setzen der Variable "$IGNORE=1" wird der Datensatz vom Logging ausgeschlossen.
       <br><br>

      <b>Beispiele</b> <br>
      <code>
      attr &lt;device&gt; valueFn {if ($DEVICE eq "living_Clima" && $VALUE eq "off" ){$VALUE=0;} elsif ($DEVICE eq "e-power"){$VALUE= sprintf "%.1f", $VALUE;}}
      </code> <br>
      # ändert den Reading-Wert des Gerätes "living_Clima" von "off" zu "0" und rundet den Wert vom Gerät "e-power" <br><br>
      <code>
      attr &lt;device&gt; valueFn {if ($DEVICE eq "SMA_Energymeter" && $READING eq "state"){$IGNORE=1;}}
      </code><br>
      # der Datensatz wird nicht geloggt wenn Device = "SMA_Energymeter" und das Reading = "state" ist  <br><br>
      <code>
      attr &lt;device&gt; valueFn {if ($DEVICE eq "Dum.Energy" && $READING eq "TotalConsumption"){$UNIT="W";}}
      </code><br>
      # setzt die Einheit des Devices "Dum.Energy" auf "W" wenn das Reading = "TotalConsumption" ist <br><br>
     </ul>
     </li>
  </ul>
  <br>

  <ul>
     <a id="DbLog-attr-verbose4Devs"></a>
     <li><b>verbose4Devs &lt;device1&gt;,&lt;device2&gt;,&lt;device..&gt; </b> <br><br>

     <ul>
       Mit verbose Level 4/5 werden nur Ausgaben bezüglich der in diesem Attribut aufgeführten Devices im Logfile
       protokolliert. Ohne dieses Attribut werden mit verbose 4/5 Ausgaben aller relevanten Devices im Logfile protokolliert.
       Die angegebenen Devices werden als Regex ausgewertet. <br><br>

      <b>Beispiel</b> <br>
      <code>
      attr &lt;device&gt; verbose4Devs sys.*,.*5000.*,Cam.*,global
      </code><br>
      # Es werden Devices beginnend mit "sys", "Cam" bzw. Devices die "5000" enthalten und das Device "global" protokolliert falls verbose=4
      eingestellt ist. <br>
     </ul>
     </li>
  </ul>
  <br>

</ul>

=end html_DE

=for :application/json;q=META.json 93_DbLog.pm
{
  "abstract": "logs events into a database",
  "x_lang": {
    "de": {
      "abstract": "loggt Events in eine Datenbank"
    }
  },
  "keywords": [
    "dblog",
    "database",
    "events",
    "logging",
    "asynchronous"
  ],
  "version": "v1.1.1",
  "release_status": "stable",
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
        "DBI": 0,
        "Time::HiRes": 0,
        "Time::Local": 0,
        "HttpUtils": 0,
        "Encode": 0,
        "SubProcess": 0,
        "Storable": 0
      },
      "recommends": {
        "FHEM::Meta": 0,
        "DateTime": 0,
        "DateTime::Format::Strptime": 0,
        "FHEM::Utility::CTZ": 0
      },
      "suggests": {
        "Data::Dumper": 0,
        "DBD::Pg": 0,
        "DBD::mysql": 0,
        "DBD::SQLite": 0
      }
    }
  },
  "resources": {
    "x_wiki": {
      "web": "https://wiki.fhem.de/wiki/DbLog",
      "title": "DbLog"
    },
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter/93_DbLog.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/fhem/trunk/fhem/contrib/DS_Starter/93_DbLog.pm"
      }
    }
  }
}
=end :application/json;q=META.json

=cut