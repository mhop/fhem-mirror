############################################################################################################################################
# $Id$
#
# 93_DbLog.pm
# written by Dr. Boris Neubert 2007-12-30
# e-mail: omega at online dot de
#
# modified and maintained by Tobias Faust since 2012-06-26 until 2016
# e-mail: tobias dot faust at online dot de
#
# redesigned and maintained 2016-2019 by DS_Starter with credits by: JoeAllb, DeeSpe
# e-mail: heiko dot maaz at t-online dot de
#
# reduceLog() created by Claudiu Schuster (rapster)
#
############################################################################################################################################

package main;
use strict;
use warnings;
eval "use DBI;1" or my $DbLogMMDBI = "DBI";
eval "use FHEM::Meta;1" or my $modMetaAbsent = 1;
use Data::Dumper;
use Blocking;
use Time::HiRes qw(gettimeofday tv_interval);
use Time::Local;
use Encode qw(encode_utf8);
use HttpUtils;
no if $] >= 5.017011, warnings => 'experimental::smartmatch'; 

# Version History intern by DS_Starter:
our %DbLog_vNotesIntern = (
  "4.7.5"   => "07.10.2019 fix warning \"error valueFn: Global symbol \$CN requires ...\" in DbLog_addCacheLine ".
                           "enhanced configCheck by insert mode check ",
  "4.7.4"   => "03.10.2019 bugfix test of TIMESTAMP got from DbLogValueFn or valueFn in DbLog_Log and DbLog_AddLog",
  "4.7.3"   => "02.10.2019 improved log out entries of DbLog_Get for SVG ",
  "4.7.2"   => "28.09.2019 change cache from %defs to %data ",
  "4.7.1"   => "10.09.2019 release the memcache memory: https://www.effectiveperlprogramming.com/2018/09/undef-a-scalar-to-release-its-memory/ in asynchron mode: https://www.effectiveperlprogramming.com/2018/09/undef-a-scalar-to-release-its-memory/ ",
  "4.7.0"   => "04.09.2019 attribute traceHandles, extract db driver versions in configCheck ",
  "4.6.0"   => "03.09.2019 add-on parameter \"force\" for MinInterval, Forum: #97148 ",
  "4.5.0"   => "28.08.2019 consider attr global logdir in set exportCache ",
  "4.4.0"   => "21.08.2019 configCheck changed: check if new DbLog version is available or the local one is modified ",
  "4.3.0"   => "14.08.2019 new attribute dbSchema, add database schema to subroutines ",
  "4.2.0"   => "25.07.2019 DbLogValueFn as device specific function propagated in devices if dblog is used ",
  "4.1.1"   => "25.05.2019 fix ignore MinInterval if value is \"0\", Forum: #100344 ",
  "4.1.0"   => "17.04.2019 DbLog_Get: change reconnect for MySQL (Forum: #99719), change index suggestion in DbLog_configcheck ",
  "4.0.0"   => "14.04.2019 rewrite DbLog_PushAsync / DbLog_Push / DbLog_Connectxx, new attribute \"bulkInsert\" ",
  "3.14.1"  => "12.04.2019 DbLog_Get: change select of MySQL Forum: https://forum.fhem.de/index.php/topic,99280.0.html ",
  "3.14.0"  => "05.04.2019 add support for Meta.pm and X_DelayedShutdownFn, attribute shutdownWait removed, ".
                           "direct attribute help in FHEMWEB ",
  "3.13.3"  => "04.03.2019 addLog better Log3 Outputs ",
  "3.13.2"  => "09.02.2019 Commandref revised ",
  "3.13.1"  => "27.11.2018 DbLog_ExecSQL log output changed ",
  "3.13.0"  => "12.11.2018 adding attributes traceFlag, traceLevel ",
  "3.12.7"  => "10.11.2018 addLog considers DbLogInclude (Forum:#92854) ",
  "3.12.6"  => "22.10.2018 fix timer not deleted if reopen after reopen xxx (Forum: https://forum.fhem.de/index.php/topic,91869.msg848433.html#msg848433) ",
  "3.12.5"  => "12.10.2018 charFilter: \"\\xB0C\" substitution by \"°C\" added and usage in DbLog_Log changed ",
  "3.12.4"  => "10.10.2018 return non-saved datasets back in asynch mode only if transaction is used ",
  "3.12.3"  => "08.10.2018 Log output of recuceLogNbl enhanced, some functions renamed ",
  "3.12.2"  => "07.10.2018 \$hash->{HELPER}{REOPEN_RUNS_UNTIL} contains the time the DB is closed  ",
  "3.12.1"  => "19.09.2018 use Time::Local (forum:#91285) ",
  "3.12.0"  => "04.09.2018 corrected SVG-select (https://forum.fhem.de/index.php/topic,65860.msg815640.html#msg815640) ",
  "3.11.0"  => "02.09.2018 reduceLog, reduceLogNbl - optional \"days newer than\" part added ",
  "3.10.10" => "05.08.2018 commandref revised reducelogNbl ",
  "3.10.9"  => "23.06.2018 commandref added hint about special characters in passwords ",
  "3.10.8"  => "21.04.2018 addLog - not available reading can be added as new one (forum:#86966) ",
  "3.10.7"  => "16.04.2018 fix generate addLog-event if device or reading was not found by addLog ",
  "3.10.6"  => "13.04.2018 verbose level in addlog changed if reading not found ",
  "3.10.5"  => "12.04.2018 fix warnings ",
  "3.10.4"  => "11.04.2018 fix addLog if no valueFn is used ",
  "3.10.3"  => "10.04.2018 minor fixes in addLog ",
  "3.10.2"  => "09.04.2018 add qualifier CN=<caller name> to addlog ",
  "3.10.1"  => "04.04.2018 changed event parsing of Weather ",
  "3.10.0"  => "02.04.2018 addLog consider DbLogExclude in Devices, keyword \"!useExcludes\" to switch off considering ".
                           "DbLogExclude in addLog, DbLogExclude & DbLogInclude can handle \"/\" in Readingname ".
                           "commandref (reduceLog) revised ",
  "3.9.0"   => "17.03.2018 DbLog_ConnectPush state-handling changed, attribute excludeDevs enhanced in DbLog_Log ",
  "3.8.9"   => "10.03.2018 commandref revised ",
  "3.8.8"   => "05.03.2018 fix device doesn't exit if configuration couldn't be read ",
  "3.8.7"   => "28.02.2018 changed DbLog_sampleDataFn - no change limits got fron SVG, commandref revised ",
  "3.8.6"   => "25.02.2018 commandref revised (forum:#84953) ",
  "3.8.5"   => "16.02.2018 changed ParseEvent for Zwave ",
  "3.8.4"   => "07.02.2018 minor fixes of \"\$\@\", code review, eval for userCommand, DbLog_ExecSQL1 (forum:#83973) ",
  "3.8.3"   => "03.02.2018 call execmemcache only syncInterval/2 if cacheLimit reached and DB is not reachable, fix handling of ".
                           "\"\$\@\" in DbLog_PushAsync ", 
  "3.8.2"   => "31.01.2018 RaiseError => 1 in DbLog_ConnectPush, DbLog_ConnectNewDBH, configCheck improved ",
  "3.8.1"   => "29.01.2018 Use of uninitialized value \$txt if addlog has no value ",
  "3.8.0"   => "26.01.2018 escape \"\|\" in events to log events containing it ",
  "3.7.1"   => "25.01.2018 fix typo in commandref ",
  "3.7.0"   => "21.01.2018 parsed event with Log 5 added, configCheck enhanced by configuration read check ",
  "3.6.5"   => "19.01.2018 fix lot of logentries if disabled and db not available ",
  "3.6.4"   => "17.01.2018 improve DbLog_Shutdown, extend configCheck by shutdown preparation check ",
  "3.6.3"   => "14.01.2018 change verbose level of addlog \"no Reading of device ...\" message from 2 to 4  ",
  "3.6.2"   => "07.01.2018 new attribute \"exportCacheAppend\", change function exportCache to respect attr exportCacheAppend, ".
                           "fix DbLog_execmemcache verbose 5 message ",
  "3.6.1"   => "04.01.2018 change SQLite PRAGMA from NORMAL to FULL (Default Value of SQLite) ",
  "3.6.0"   => "20.12.2017 check global blockingCallMax in configCheck, configCheck now available for SQLITE ",
  "3.5.0"   => "18.12.2017 importCacheFile, addCacheLine uses useCharfilter option, filter only \$event by charfilter  ",
  "3.4.0"   => "10.12.2017 avoid print out {RUNNING_PID} by \"list device\" ",
  "3.3.0"   => "07.12.2017 avoid print out the content of cache by \"list device\" ",
  "3.2.0"   => "06.12.2017 change attribute \"autocommit\" to \"commitMode\", activate choice of autocommit/transaction in logging ".
                           "Addlog/addCacheLine change \$TIMESTAMP check ".
                           "rebuild DbLog_Push/DbLog_PushAsync due to bugfix in update current (Forum:#80519) ". 
                           "new attribute \"useCharfilter\" for Characterfilter usage ",
  "3.1.1"   => "05.12.2017 Characterfilter added to avoid unwanted characters what may destroy transaction  ",
  "3.1.0"   => "05.12.2017 new set command addCacheLine ",
  "3.0.0"   => "03.12.2017 set begin_work depending of AutoCommit value, new attribute \"autocommit\", some minor corrections, ".
                           "report working progress of reduceLog,reduceLogNbl in logfile (verbose 3), enhanced log output ".
                           "(e.g. of execute_array) ",
  "2.22.15" => "28.11.2017 some Log3 verbose level adapted ",
  "2.22.14" => "18.11.2017 create state-events if state has been changed (Forum:#78867) ",
  "2.22.13" => "20.10.2017 output of reopen command improved ",
  "2.22.12" => "19.10.2017 avoid illegible messages in \"state\" ",
  "2.22.11" => "13.10.2017 DbLogType expanded by SampleFill, DbLog_sampleDataFn adapted to sort case insensitive, commandref revised ",
  "2.22.10" => "04.10.2017 Encode::encode_utf8 of \$error, DbLog_PushAsyncAborted adapted to use abortArg (Forum:77472) ",
  "2.22.9"  => "04.10.2017 added hint to SVG/DbRep in commandref ",
  "2.22.8"  => "29.09.2017 avoid multiple entries in Dopdown-list when creating SVG by group Device:Reading in DbLog_sampleDataFn ",
  "2.22.7"  => "24.09.2017 minor fixes in configcheck ",
  "2.22.6"  => "22.09.2017 commandref revised ",
  "2.22.5"  => "05.09.2017 fix Internal MODE isn't set correctly after DEF is edited, nextsynch is not renewed if reopen is ".
                           "set manually after reopen was set with a delay Forum:#76213, Link to 98_FileLogConvert.pm added ",
  "2.22.4"  => "27.08.2017 fhem chrashes if database DBD driver is not installed (Forum:#75894) ",
  "2.22.1"  => "07.08.2017 attribute \"suppressAddLogV3\" to suppress verbose3-logentries created by DbLog_AddLog  ",
  "2.22.0"  => "25.07.2017 attribute \"addStateEvent\" added ",
  "2.21.3"  => "24.07.2017 commandref revised ",
  "2.21.2"  => "19.07.2017 changed readCfg to report more error-messages ",
  "2.21.1"  => "18.07.2017 change configCheck for DbRep Report_Idx ",
  "2.21.0"  => "17.07.2017 standard timeout increased to 86400, enhanced explaination in configCheck  ",
  "2.20.0"  => "15.07.2017 state-Events complemented with state by using \$events = deviceEvents(\$dev_hash,1) ",
  "2.19.0"  => "11.07.2017 replace {DBMODEL} by {MODEL} completely ",
  "2.18.3"  => "04.07.2017 bugfix (links with \$FW_ME deleted), MODEL as Internal (for statistic) ",
  "2.18.2"  => "29.06.2017 check of index for DbRep added ",
  "2.18.1"  => "25.06.2017 DbLog_configCheck/ DbLog_sqlget some changes, commandref revised ",
  "2.18.0"  => "24.06.2017 configCheck added (MySQL, PostgreSQL) ",
  "2.17.1"  => "17.06.2017 fix log-entries \"utf8 enabled\" if SVG's called, commandref revised, enable UTF8 for DbLog_get ",
  "2.17.0"  => "15.06.2017 enable UTF8 for MySQL (entry in configuration file necessary) ",
  "2.16.11" => "03.06.2017 execmemcache changed for SQLite avoid logging if deleteOldDaysNbl or reduceLogNbL is running  ",
  "2.16.10" => "15.05.2017 commandref revised ",
  "2.16.9.1"=> "11.05.2017 set userCommand changed - Forum: https://forum.fhem.de/index.php/topic,71808.msg633607.html#msg633607 ",
  "2.16.9"  => "07.05.2017 addlog syntax changed to \"addLog devspec:Reading [Value]\" ",
  "2.16.8"  => "06.05.2017 in valueFN \$VALUE and \$UNIT can now be set to '' or 0 ",
  "2.16.7"  => "20.04.2017 fix \$now at addLog ",
  "2.16.6"  => "18.04.2017 AddLog set lasttime, lastvalue of dev_name, dev_reading ",
  "2.16.5"  => "16.04.2017 DbLog_checkUsePK changed again, new attribute noSupportPK ",
  "2.16.4"  => "15.04.2017 commandref completed, DbLog_checkUsePK changed (\@usepkh = \"\", \@usepkc = \"\") ",
  "2.16.3"  => "07.04.2017 evaluate reading in DbLog_AddLog as regular expression ",
  "2.16.0"  => "03.04.2017 new set-command addLog ",
  "2.15.0"  => "03.04.2017 new attr valueFn using for perl expression which may change variables and skip logging ".
                           "unwanted datasets, change DbLog_ParseEvent for ZWAVE, ".
                           "change DbLogExclude / DbLogInclude in DbLog_Log to \"\$lv = \"\" if(!defined(\$lv));\" ",
  "2.14.4"  => "28.03.2017 pre-connection check in DbLog_execmemcache deleted (avoid possible blocking), attr excludeDevs ".
                           "can be specified as devspec ",
  "2.14.3"  => "24.03.2017 DbLog_Get, DbLog_Push changed for better plotfork-support ",
  "2.14.2"  => "23.03.2017 new reading \"lastCachefile\" ",
  "2.14.1"  => "22.03.2017 cacheFile will be renamed after successful import by set importCachefile                  ",
  "2.14.0"  => "19.03.2017 new set-commands exportCache, importCachefile, new attr expimpdir, all cache relevant set-commands ".
                           "only in drop-down list when asynch mode is used, minor fixes ",
  "2.13.6"  => "13.03.2017 plausibility check in set reduceLog(Nbl) enhanced, minor fixes ",
  "2.13.5"  => "20.02.2017 check presence of table current in DbLog_sampleDataFn ",
  "2.13.3"  => "18.02.2017 default timeout of DbLog_PushAsync increased to 1800, ".
                           "delete {HELPER}{xx_PID} in reopen function ",
  "2.13.2"  => "16.02.2017 deleteOldDaysNbl added (non-blocking implementation of deleteOldDays) ",
  "2.13.1"  => "15.02.2017 clearReadings limited to readings which won't be recreated periodicly in asynch mode and set readings only blank, ".
                           "eraseReadings added to delete readings except reading \"state\", ".
                           "countNbl non-blocking by DeeSPe, ".
                           "rename reduceLog non-blocking to reduceLogNbl and implement the old reduceLog too ",
  "2.13.0"  => "13.02.2017 made reduceLog non-blocking by DeeSPe ",
  "2.12.5"  => "11.02.2017 add support for primary key of PostgreSQL DB (Rel. 9.5) in both modes for current table ",
  "2.12.4"  => "09.02.2017 support for primary key of PostgreSQL DB (Rel. 9.5) in both modes only history table ",
  "2.12.3"  => "07.02.2017 set command clearReadings added ",
  "2.12.2"  => "07.02.2017 support for primary key of SQLITE DB in both modes ",
  "2.12.1"  => "05.02.2017 support for primary key of MySQL DB in synch mode ",
  "2.12"    => "04.02.2017 support for primary key of MySQL DB in asynch mode ",
  "2.11.4"  => "03.02.2017 check of missing modules added ",
  "2.11.3"  => "01.02.2017 make errorlogging of DbLog_PushAsync more identical to DbLog_Push ",
  "2.11.2"  => "31.01.2017 if attr colEvent, colReading, colValue is set, the limitation of fieldlength is also valid ".
                           "for SQLite databases ",
  "2.11.1"  => "30.01.2017 output to central logfile enhanced for DbLog_Push ",
  "2.11"    => "28.01.2017 DbLog_connect substituted by DbLog_connectPush completely ",
  "2.10.8"  => "27.01.2017 DbLog_setinternalcols delayed at fhem start ",
  "2.10.7"  => "25.01.2017 \$hash->{HELPER}{COLSET} in DbLog_setinternalcols, DbLog_Push changed due to ".
                           "issue Turning on AutoCommit failed ",
  "2.10.6"  => "24.01.2017 DbLog_connect changed \"connect_cashed\" to \"connect\", DbLog_Get, DbLog_chartQuery now uses ".
                           "DbLog_ConnectNewDBH, Attr asyncMode changed -> delete reading cacheusage reliable if mode was switched ",
  "2.10.5"  => "23.01.2017 count, userCommand, deleteOldDays now uses DbLog_ConnectNewDBH ".
                           "DbLog_Push line 1107 changed ",
  "2.10.4"  => "22.01.2017 new sub DbLog_setinternalcols, new attributes colEvent, colReading, colValue ",
  "2.10.3"  => "21.01.2017 query of cacheEvents changed, attr timeout adjustable ",
  "2.10.2"  => "19.01.2017 ReduceLog now uses DbLog_ConnectNewDBH -> makes start of ReduceLog stable ",
  "2.10.1"  => "19.01.2017 commandref edited, cache events don't get lost even if other errors than \"db not available\" occure ",
  "2.10"    => "18.10.2017 new attribute cacheLimit, showNotifyTime ",
  "2.9.3"   => "17.01.2017 new sub DbLog_ConnectNewDBH (own new dbh for separate use in functions except logging functions), ".
                           "DbLog_sampleDataFn, DbLog_dbReadings now use DbLog_ConnectNewDBH ",
  "2.9.2"   => "16.01.2017 new bugfix for SQLite issue SVGs, DbLog_Log changed to \$dev_hash->{CHANGETIME}, DbLog_Push ".
                           "changed (db handle new separated) ",
  "2.9.1"   => "14.01.2017 changed DbLog_ParseEvent to CallInstanceFn, renamed flushCache to purgeCache, ".
                           "renamed syncCache to commitCache, attr cacheEvents changed to 0,1,2 ",
  "2.8.9"   => "11.01.2017 own \$dbhp (new DbLog_ConnectPush) for synchronous logging, delete \$hash->{HELPER}{RUNNING_PID} ".
                           "if DEAD, add func flushCache, syncCache ",
  "2.8.8"   => "10.01.2017 connection check in Get added, avoid warning \"commit/rollback ineffective with AutoCommit enabled\" ",
  "2.8.7"   => "10.01.2017 bugfix no dropdown list in SVG if asynchronous mode activated (func DbLog_sampleDataFn) ",
  "2.8.6"   => "09.01.2017 Workaround for Warning begin_work failed: Turning off AutoCommit failed, start new timer of ".
                           "DbLog_execmemcache after reducelog ",
  "2.8.5"   => "08.01.2017 attr syncEvents, cacheEvents added to minimize events ",
  "2.8.4"   => "08.01.2017 \$readingFnAttributes added ",
  "2.8.3"   => "08.01.2017 set NOTIFYDEV changed to use notifyRegexpChanged (Forum msg555619), attr noNotifyDev added ",
  "2.8.2"   => "06.01.2017 commandref maintained to cover new functions ",
  "2.8.1"   => "05.01.2017 use Time::HiRes qw(gettimeofday tv_interval), bugfix \$hash->{HELPER}{RUNNING_PID} ",
  "2.4.4"   => "28.12.2016 Attribut \"excludeDevs\" to exclude devices from db-logging (only if \$hash->{NOTIFYDEV} eq \"\.\*\") ",
  "2.4.3"   => "28.12.2016 function DbLog_Log: changed separators of \@row_array -> better splitting ",
  "2.4.2"   => "28.12.2016 Attribut \"verbose4Devs\" to restrict verbose4 loggings of specific devices  ",
  "2.4.1"   => "27.12.2016 DbLog_Push: improved update/insert into current, analyze execute_array -> ArrayTupleStatus ",
  "2.3.1"   => "23.12.2016 fix due to https://forum.fhem.de/index.php/topic,62998.msg545541.html#msg545541 ",
  "1.9.3"   => "17.12.2016 \$hash->{NOTIFYDEV} added to process only events from devices are in Regex ",
  "1.9.2"   => "17.12.2016 some improvemnts DbLog_Log, DbLog_Push ",
  "1.9.1"   => "16.12.2016 DbLog_Log no using encode_base64 ",
  "1.8.1"   => "16.12.2016 DbLog_Push changed ",
  "1.7.1"   => "15.12.2016 attr procedure of \"disabled\" changed"
);

my %columns = ("DEVICE"  => 64,
               "TYPE"    => 64,
               "EVENT"   => 512,
               "READING" => 64,
               "VALUE"   => 128,
               "UNIT"    => 32
              );
					 
sub DbLog_dbReadings($@);
sub DbLog_showChildHandles($$$$);

################################################################
sub DbLog_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}             = "DbLog_Define";
  $hash->{UndefFn}           = "DbLog_Undef";
  $hash->{NotifyFn}          = "DbLog_Log";
  $hash->{SetFn}             = "DbLog_Set";
  $hash->{GetFn}             = "DbLog_Get";
  $hash->{AttrFn}            = "DbLog_Attr";
  $hash->{SVG_regexpFn}      = "DbLog_regexpFn";
  $hash->{DelayedShutdownFn} = "DbLog_DelayedShutdown";
  $hash->{AttrList}          = "addStateEvent:0,1 ".
							   "asyncMode:1,0 ".
                               "bulkInsert:1,0 ".
                               "commitMode:basic_ta:on,basic_ta:off,ac:on_ta:on,ac:on_ta:off,ac:off_ta:on ".
							   "cacheEvents:2,1,0 ".
							   "cacheLimit ".
                               "colEvent ".
                               "colReading ".
							   "colValue ".
                               "DbLogSelectionMode:Exclude,Include,Exclude/Include ".
                               "DbLogType:Current,History,Current/History,SampleFill/History ".
                               "dbSchema ".
                               "disable:1,0 ".
							   "excludeDevs ".
							   "expimpdir ".
                               "exportCacheAppend:1,0 ".
							   "noSupportPK:1,0 ".
							   "noNotifyDev:1,0 ".
							   "showproctime:1,0 ".
							   "suppressAddLogV3:1,0 ".
                               "suppressUndef:0,1 ".
							   "syncEvents:1,0 ".
							   "syncInterval ".
							   "showNotifyTime:1,0 ".
                               "traceFlag:SQL,CON,ENC,DBD,TXN,ALL ".
                               "traceLevel:0,1,2,3,4,5,6,7 ".
                               "traceHandles ".
							   "timeout ".
							   "useCharfilter:0,1 ".
							   "valueFn:textField-long ".
		                       "verbose4Devs ".
							   $readingFnAttributes;  

  addToAttrList("DbLogInclude");
  addToAttrList("DbLogExclude");
  addToAttrList("DbLogValueFn:textField-long");

  $hash->{FW_detailFn}      = "DbLog_fhemwebFn";
  $hash->{SVG_sampleDataFn} = "DbLog_sampleDataFn";
 
  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };           # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)
  
return;
}

###############################################################
sub DbLog_Define($@) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  
  return "Error: Perl module ".$DbLogMMDBI." is missing. 
        Install it on Debian with: sudo apt-get install libdbi-perl" if($DbLogMMDBI);  

  return "wrong syntax: define <name> DbLog configuration regexp"
    if(int(@a) != 4);
  
  my $name               = $hash->{NAME};
  $hash->{CONFIGURATION} = $a[2];
  my $regexp             = $a[3];

  eval { "Hallo" =~ m/^$regexp$/ };
  return "Bad regexp: $@" if($@);
  
  $hash->{REGEXP}                = $regexp;
  $hash->{MODE}                  = AttrVal($hash->{NAME}, "asyncMode", undef)?"asynchronous":"synchronous";   # Mode setzen Forum:#76213
  $hash->{HELPER}{OLDSTATE}      = "initialized";
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                                                      # Modul Meta.pm nicht vorhanden
  $hash->{HELPER}{TH}            = "history";                                                                 # Tabelle history (wird ggf. durch Datenbankschema ergänzt)
  $hash->{HELPER}{TC}            = "current";                                                                 # Tabelle current (wird ggf. durch Datenbankschema ergänzt)

  # Versionsinformationen setzen
  DbLog_setVersionInfo($hash);
  
  # nur Events dieser Devices an NotifyFn weiterleiten, NOTIFYDEV wird gesetzt wenn möglich
  notifyRegexpChanged($hash, $regexp);
  
  #remember PID for plotfork
  $hash->{PID} = $$;
  
  # CacheIndex für Events zum asynchronen Schreiben in DB
  $data{DbLog}{$name}{cache}{index} = 0;

  # read configuration data
  my $ret = DbLog_readCfg($hash);
  if ($ret) {
      # return on error while reading configuration
	  Log3($hash->{NAME}, 1, "DbLog $hash->{NAME} - Error while reading $hash->{CONFIGURATION}: '$ret' ");
      return $ret; 
  }
  
  # set used COLUMNS
  InternalTimer(gettimeofday()+2, "DbLog_setinternalcols", $hash, 0);

  readingsSingleUpdate($hash, 'state', 'waiting for connection', 1);
  DbLog_ConnectPush($hash);

  # initial execution of DbLog_execmemcache
  DbLog_execmemcache($hash);
  
return undef;
}

################################################################
sub DbLog_Undef($$) {
  my ($hash, $name) = @_;
  my $dbh= $hash->{DBHP};
  BlockingKill($hash->{HELPER}{".RUNNING_PID"}) if($hash->{HELPER}{".RUNNING_PID"});
  BlockingKill($hash->{HELPER}{REDUCELOG_PID}) if($hash->{HELPER}{REDUCELOG_PID});
  BlockingKill($hash->{HELPER}{COUNT_PID}) if($hash->{HELPER}{COUNT_PID});
  BlockingKill($hash->{HELPER}{DELDAYS_PID}) if($hash->{HELPER}{DELDAYS_PID});
  $dbh->disconnect() if(defined($dbh));
  RemoveInternalTimer($hash);
  delete $data{DbLog}{$name};
  
return undef;
}

#######################################################################################################
# Mit der X_DelayedShutdown Funktion kann eine Definition das Stoppen von FHEM verzögern um asynchron 
# hinter sich aufzuräumen.   
# Je nach Rückgabewert $delay_needed wird der Stopp von FHEM verzögert (0 | 1).
# Sobald alle nötigen Maßnahmen erledigt sind, muss der Abschluss mit CancelDelayedShutdown($name) an 
# FHEM zurückgemeldet werden. 
#######################################################################################################
sub DbLog_DelayedShutdown($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  my $async  = AttrVal($name, "asyncMode", "");
  
  return 0 if(IsDisabled($name));
  
  $hash->{HELPER}{SHUTDOWNSEQ} = 1;
  # return 0 if(!$async && !$hash->{HELPER}{PUSHISRUNNING});
  Log3($name, 2, "DbLog $name - Last database write cycle due to shutdown ...");
  DbLog_execmemcache($hash);

return 1;
}

################################################################
#
# Wird bei jeder Aenderung eines Attributes dieser
# DbLog-Instanz aufgerufen
#
################################################################
sub DbLog_Attr(@) {
  my($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};
  my $dbh  = $hash->{DBHP};
  my $do = 0;

  if($cmd eq "set") {
      if ($aName eq "syncInterval" || $aName eq "cacheLimit" || $aName eq "timeout") {
          unless ($aVal =~ /^[0-9]+$/) { return " The Value of $aName is not valid. Use only figures 0-9 !";}
      }
      
	  if ($hash->{MODEL} !~ /MYSQL|POSTGRESQL/ && $aName =~ /dbSchema/) {
           return "\"$aName\" is not valid for database model \"$hash->{MODEL}\"";
	  }
	  
      if( $aName eq 'valueFn' ) {
	      my %specials= (
             "%TIMESTAMP" => $name,
             "%DEVICE" => $name,
			 "%DEVICETYPE" => $name,
			 "%EVENT" => $name,
             "%READING" => $name,
             "%VALUE" => $name,
             "%UNIT" => $name,
			 "%IGNORE" => $name,
             "%CN" => $name,
          );
          my $err = perlSyntaxCheck($aVal, %specials);
          return $err if($err);
      }

      if ($aName eq "shutdownWait") {
         return "DbLog $name - The attribute $aName is deprecated and has been removed !";
      }      
  }
 
  if($aName eq "colEvent" || $aName eq "colReading" || $aName eq "colValue") {
      if ($cmd eq "set" && $aVal) {
          unless ($aVal =~ /^[0-9]+$/) { return " The Value of $aName is not valid. Use only figures 0-9 !";}
	  }
	  InternalTimer(gettimeofday()+0.5, "DbLog_setinternalcols", $hash, 0);
  }
  
  if($aName eq "asyncMode") {
      if ($cmd eq "set" && $aVal) {
          $hash->{MODE} = "asynchronous";
		  InternalTimer(gettimeofday()+2, "DbLog_execmemcache", $hash, 0);
      } else {
	      $hash->{MODE} = "synchronous";
          delete($defs{$name}{READINGS}{NextSync});
		  delete($defs{$name}{READINGS}{CacheUsage});
		  InternalTimer(gettimeofday()+5, "DbLog_execmemcache", $hash, 0);
	  }
  }
  
  if($aName eq "commitMode") {
      if ($dbh) {
          $dbh->commit() if(!$dbh->{AutoCommit});
          $dbh->disconnect();
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
  
  if($aName eq "noNotifyDev") {
      my $regexp = $hash->{REGEXP};
      if ($cmd eq "set" && $aVal) {
	      delete($hash->{NOTIFYDEV});
	  } else {
	      notifyRegexpChanged($hash, $regexp);  
	  }
  }
  
  if ($aName eq "disable") {
      my $async = AttrVal($name, "asyncMode", 0);
      if($cmd eq "set") {
          $do = ($aVal) ? 1 : 0;
      }
      $do = 0 if($cmd eq "del");
      my $val   = ($do == 1 ?  "disabled" : "active");
      
	  # letzter CacheSync vor disablen
	  DbLog_execmemcache($hash) if($do == 1);
	  
      readingsSingleUpdate($hash, "state", $val, 1);
	  $hash->{HELPER}{OLDSTATE} = $val;
        
      if ($do == 0) {
          InternalTimer(gettimeofday()+2, "DbLog_execmemcache", $hash, 0) if($async);
          InternalTimer(gettimeofday()+2, "DbLog_ConnectPush", $hash, 0) if(!$async);
      }
  }
  
  if ($aName eq "traceHandles") {
      if($cmd eq "set") {
          unless ($aVal =~ /^[0-9]+$/) {return " The Value of $aName is not valid. Use only figures 0-9 without decimal places !";}
	  }
      RemoveInternalTimer($hash, "DbLog_startShowChildhandles");
      if($cmd eq "set") {
          $do = ($aVal) ? 1 : 0;
      }
      $do = 0 if($cmd eq "del");
      if($do) { 
          InternalTimer(gettimeofday()+5, "DbLog_startShowChildhandles", "$name:Main", 0);
      }
  }
  
  if ($aName eq "dbSchema") {
      if($cmd eq "set") {
          $do = ($aVal) ? 1 : 0;
      }
      $do = 0 if($cmd eq "del");
           
      if ($do == 1) {
          $hash->{HELPER}{TH}       = $aVal.".history";         
          $hash->{HELPER}{TC}       = $aVal.".current";         

      } else {
          $hash->{HELPER}{TH}       = "history";         
          $hash->{HELPER}{TC}       = "current";         
      }
  }

return undef;
}

################################################################
sub DbLog_Set($@) {
    my ($hash, @a) = @_;
	my $name  = $hash->{NAME};
	my $async = AttrVal($name, "asyncMode", undef);
	my $usage = "Unknown argument, choose one of reduceLog reduceLogNbl reopen rereadcfg:noArg count:noArg countNbl:noArg 
	             deleteOldDays deleteOldDaysNbl userCommand clearReadings:noArg 
				 eraseReadings:noArg addLog ";
	$usage .= "listCache:noArg addCacheLine purgeCache:noArg commitCache:noArg exportCache:nopurge,purgecache " if (AttrVal($name, "asyncMode", undef));
    $usage .= "configCheck:noArg ";
    my $history = $hash->{HELPER}{TH};
    my $current = $hash->{HELPER}{TC};
	my (@logs,$dir);
	
    my $dirdef = AttrVal("global", "logdir", $attr{global}{modpath}."/log/");
    $dir       = AttrVal($name, "expimpdir", $dirdef);
    $dir       = $dir."/" if($dir !~ /.*\/$/);
	
	opendir(DIR,$dir);
	my $sd = "cache_".$name."_";
    while (my $file = readdir(DIR)) {
        next unless (-f "$dir/$file");
        next unless ($file =~ /^$sd/);
        push @logs,$file;
    }
    closedir(DIR);
	my $cj = join(",",reverse(sort @logs)) if (@logs);
	
	if (@logs) {
	    $usage .= "importCachefile:".$cj." ";
	} else {
	    $usage .= "importCachefile ";
	}
	
	return $usage if(int(@a) < 2);
	my $dbh  = $hash->{DBHP};
	my $db   = (split(/;|=/, $hash->{dbconn}))[1]; 
	my $ret;

    if ($a[1] eq 'reduceLog') {
        my ($od,$nd) = split(":",$a[2]);         # $od - Tage älter als , $nd - Tage neuer als
        if ($nd && $nd <= $od) {return "The second day value must be greater than the first one ! ";}
	    if (defined($a[3]) && $a[3] !~ /^average$|^average=.+|^EXCLUDE=.+$|^INCLUDE=.+$/i) {
            return "ReduceLog syntax error in set command. Please see commandref for help.";
        }
        if (defined $a[2] && $a[2] =~ /(^\d+$)|(^\d+:\d+$)/) {
            $ret = DbLog_reduceLog($hash,@a);
			InternalTimer(gettimeofday()+5, "DbLog_execmemcache", $hash, 0);
        } else {
            Log3($name, 1, "DbLog $name: reduceLog error, no <days> given.");
            $ret = "reduceLog error, no <days> given.";
        }
    }
	elsif ($a[1] eq 'reduceLogNbl') {
        my ($od,$nd) = split(":",$a[2]);         # $od - Tage älter als , $nd - Tage neuer als
        if ($nd && $nd <= $od) {return "The second day value must be greater than the first one ! ";}
	    if (defined($a[3]) && $a[3] !~ /^average$|^average=.+|^EXCLUDE=.+$|^INCLUDE=.+$/i) {
            return "ReduceLogNbl syntax error in set command. Please see commandref for help.";
        }
        if (defined $a[2] && $a[2] =~ /(^\d+$)|(^\d+:\d+$)/) {
            if ($hash->{HELPER}{REDUCELOG_PID} && $hash->{HELPER}{REDUCELOG_PID}{pid} !~ m/DEAD/) {  
                $ret = "reduceLogNbl already in progress. Please wait until the running process is finished.";
            } else {
			    delete $hash->{HELPER}{REDUCELOG_PID};
			    my @b = @a;
			    shift(@b);
			    readingsSingleUpdate($hash,"reduceLogState","@b started",1);
                $hash->{HELPER}{REDUCELOG} = \@a;
                $hash->{HELPER}{REDUCELOG_PID} = BlockingCall("DbLog_reduceLogNbl","$name","DbLog_reduceLogNbl_finished");
                return;
            }
        } else {
            Log3($name, 1, "DbLog $name: reduceLogNbl syntax error, no <days>[:<days>] given.");
            $ret = "reduceLogNbl error, no <days> given.";
        }
    }
	elsif ($a[1] eq 'clearReadings') {		
        my @allrds = keys%{$defs{$name}{READINGS}};
		foreach my $key(@allrds) {
		    next if($key =~ m/state/ || $key =~ m/CacheUsage/ || $key =~ m/NextSync/);
			readingsSingleUpdate($hash,$key," ",0);
        }
    }
	elsif ($a[1] eq 'eraseReadings') {		
        my @allrds = keys%{$defs{$name}{READINGS}};
		foreach my $key(@allrds) {
            delete($defs{$name}{READINGS}{$key}) if($key !~ m/^state$/);
        }
    }	
	elsif ($a[1] eq 'addLog') {		
        unless ($a[2]) { return "The argument of $a[1] is not valid. Please check commandref.";}
        my $nce = ("\!useExcludes" ~~ @a)?1:0;
        map(s/\!useExcludes//g, @a);
        my $cn;
        if(/CN=/ ~~ @a) {
            my $t = join(" ",@a);
            ($cn) = ($t =~ /^.*CN=(\w+).*$/);
            map(s/CN=$cn//g, @a);
        }
		DbLog_AddLog($hash,$a[2],$a[3],$nce,$cn);
        my $skip_trigger = 1;   # kein Event erzeugen falls addLog device/reading not found aber Abarbeitung erfolgreich
        return undef,$skip_trigger;
	}
    elsif ($a[1] eq 'reopen') {		
		if ($dbh) {
            eval {$dbh->commit() if(!$dbh->{AutoCommit});};
             if ($@) {
                 Log3($name, 2, "DbLog $name -> Error commit $history - $@");
             }            
            $dbh->disconnect();
        }
		if (!$a[2]) {
		    Log3($name, 3, "DbLog $name: Reopen requested.");
            DbLog_ConnectPush($hash);
            if($hash->{HELPER}{REOPEN_RUNS}) {
			    delete $hash->{HELPER}{REOPEN_RUNS};
                delete $hash->{HELPER}{REOPEN_RUNS_UNTIL};
                RemoveInternalTimer($hash, "DbLog_reopen");
            }
			DbLog_execmemcache($hash) if($async);
            $ret = "Reopen executed.";
		} else {
			unless ($a[2] =~ /^[0-9]+$/) { return " The Value of $a[1]-time is not valid. Use only figures 0-9 !";}
		    # Statusbit "Kein Schreiben in DB erlauben" wenn reopen mit Zeitangabe
            $hash->{HELPER}{REOPEN_RUNS} = $a[2];
			
			# falls ein hängender Prozess vorhanden ist -> löschen
			BlockingKill($hash->{HELPER}{".RUNNING_PID"}) if($hash->{HELPER}{".RUNNING_PID"});
            BlockingKill($hash->{HELPER}{REDUCELOG_PID}) if($hash->{HELPER}{REDUCELOG_PID});
            BlockingKill($hash->{HELPER}{COUNT_PID}) if($hash->{HELPER}{COUNT_PID});
            BlockingKill($hash->{HELPER}{DELDAYS_PID}) if($hash->{HELPER}{DELDAYS_PID});
			delete $hash->{HELPER}{".RUNNING_PID"};     
			delete $hash->{HELPER}{COUNT_PID};
			delete $hash->{HELPER}{DELDAYS_PID};
			delete $hash->{HELPER}{REDUCELOG_PID};
			
			my $ts = (split(" ",FmtDateTime(gettimeofday()+$a[2])))[1];
			Log3($name, 2, "DbLog $name: Connection closed until $ts ($a[2] seconds).");
			readingsSingleUpdate($hash, "state", "closed until $ts ($a[2] seconds)", 1);
            InternalTimer(gettimeofday()+$a[2], "DbLog_reopen", $hash, 0);
            $hash->{HELPER}{REOPEN_RUNS_UNTIL} = $ts;			
		}
    }
    elsif ($a[1] eq 'rereadcfg') {
        Log3($name, 3, "DbLog $name: Rereadcfg requested.");
        
        if ($dbh) {
            $dbh->commit() if(!$dbh->{AutoCommit});
            $dbh->disconnect();
        }
        $ret = DbLog_readCfg($hash);
        return $ret if $ret;
        DbLog_ConnectPush($hash);
        $ret = "Rereadcfg executed.";
    }
	elsif ($a[1] eq 'purgeCache') {
	    delete $data{DbLog}{$name}{cache};
        readingsSingleUpdate($hash, 'CacheUsage', 0, 1);		
	}
	elsif ($a[1] eq 'commitCache') {
	    DbLog_execmemcache($hash);		
	}
	elsif ($a[1] eq 'listCache') {
	    my $cache;
	    foreach my $key (sort{$a <=>$b}keys %{$data{DbLog}{$name}{cache}{memcache}}) { 
            $cache .= $key." => ".$data{DbLog}{$name}{cache}{memcache}{$key}."\n"; 			
		}
	    return $cache;
	}
	elsif ($a[1] eq 'addCacheLine') {
	    if(!$a[2]) {
            return "Syntax error in set $a[1] command. Use this line format: YYYY-MM-DD HH:MM:SS|<device>|<type>|<event>|<reading>|<value>|[<unit>] ";
        }
		my @b = @a;
		shift @b;
		shift @b;
		my $aa;
		foreach my $k (@b) {
		    $aa .= "$k ";
		}
		chop($aa); #letztes Leerzeichen entfernen
		$aa = DbLog_charfilter($aa) if(AttrVal($name, "useCharfilter",0));
		
		my ($i_timestamp, $i_dev, $i_type, $i_evt, $i_reading, $i_val, $i_unit) = split("\\|",$aa);        
		if($i_timestamp !~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/ || !$i_dev || !$i_reading) {
            return "Syntax error in set $a[1] command. Use this line format: YYYY-MM-DD HH:MM:SS|<device>|<type>|<event>|<reading>|<value>|[<unit>] ";
        } 
        my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($i_timestamp =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);     
        eval { my $ts = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };
           
        if ($@) {
            my @l = split (/at/, $@);
           return " Timestamp is out of range - $l[0]";         
        } 
		DbLog_addCacheLine($hash,$i_timestamp,$i_dev,$i_type,$i_evt,$i_reading,$i_val,$i_unit);
		
	}
	elsif ($a[1] eq 'configCheck') {
		my $check = DbLog_configcheck($hash);
	    return $check;
	}
	elsif ($a[1] eq 'exportCache') {
	    my $cln;
		my $crows = 0;
		my ($out,$outfile,$error);
		my $now = strftime('%Y-%m-%d_%H-%M-%S',localtime);
		
		# return wenn "reopen" mit Ablaufzeit gestartet ist oder disabled, nicht im asynch-Mode
	    return if(IsDisabled($name) || $hash->{HELPER}{REOPEN_RUNS});
		return if(!AttrVal($name, "asyncMode", undef));
        
        if(@logs && AttrVal($name, "exportCacheAppend", 0)) {
            # exportiertes Cachefile existiert und es soll an das neueste angehängt werden
            $outfile = $dir.pop(@logs);
            $out     = ">>$outfile";
        } else {
            $outfile = $dir."cache_".$name."_".$now;
            $out     = ">$outfile";
        }
        if(open(FH, $out)) {
            binmode (FH);
        } else {
		    readingsSingleUpdate($hash, "lastCachefile", $outfile." - Error - ".$!, 1);
            $error = "could not open ".$outfile.": ".$!;
        }
        
        if(!$error) {
	        foreach my $key (sort(keys %{$data{DbLog}{$name}{cache}{memcache}})) {
                $cln = $data{DbLog}{$name}{cache}{memcache}{$key}."\n";
                print FH $cln ;
                $crows++; 			
		    }
		    close(FH);
            readingsSingleUpdate($hash, "lastCachefile", $outfile." (".$crows." cache rows exported)", 1);
        }
		
		# readingsSingleUpdate($hash, "state", $crows." cache rows exported to ".$outfile, 1);
        
        my $state  = $error?$error:(IsDisabled($name))?"disabled":"connected";
        my $evt    = ($state eq $hash->{HELPER}{OLDSTATE})?0:1;
        readingsSingleUpdate($hash, "state", $state, $evt);
        $hash->{HELPER}{OLDSTATE} = $state;
		
        Log3($name, 3, "DbLog $name: $crows cache rows exported to $outfile.");
		
		if (lc($a[-1]) =~ m/^purgecache/i) {
	        delete $data{DbLog}{$name}{cache};
            readingsSingleUpdate($hash, 'CacheUsage', 0, 1);
			Log3($name, 3, "DbLog $name: Cache purged after exporting rows to $outfile.");
		}
	    return;
	}
	elsif ($a[1] eq 'importCachefile') {
	    my $cln;
		my $crows = 0;
		my $infile;
		my @row_array;
		readingsSingleUpdate($hash, "lastCachefile", "", 0);
	    
		# return wenn "reopen" mit Ablaufzeit gestartet ist oder disabled
	    return if(IsDisabled($name) || $hash->{HELPER}{REOPEN_RUNS});
		
		if (!$a[2]) {
		    return "Wrong function-call. Use set <name> importCachefile <file> without directory (see attr expimpdir)." ;
		} else {
		    $infile = $dir.$a[2];
		}
		
        if (open(FH, "$infile")) {
            binmode (FH);
        } else {
            return "could not open ".$infile.": ".$!;
        }
        while (<FH>) {
		    my $row = $_;
		    $row = DbLog_charfilter($row) if(AttrVal($name, "useCharfilter",0));
			push(@row_array, $row);
			$crows++;
	    }
		close(FH);
		
        if(@row_array) {
            my $error = DbLog_Push($hash, 1, @row_array);
		    if($error) {
			    readingsSingleUpdate($hash, "lastCachefile", $infile." - Error - ".$!, 1);
                readingsSingleUpdate($hash, "state", $error, 1);
				Log3 $name, 5, "DbLog $name -> DbLog_Push Returncode: $error";
		    } else {
			    unless(rename($dir.$a[2], $dir."impdone_".$a[2])) {
				    Log3($name, 2, "DbLog $name: cachefile $infile couldn't be renamed after import !");
				}
				readingsSingleUpdate($hash, "lastCachefile", $infile." import successful", 1);
		        readingsSingleUpdate($hash, "state", $crows." cache rows processed from ".$infile, 1);
			    Log3($name, 3, "DbLog $name: $crows cache rows processed from $infile.");
		    }
        } else {
		    readingsSingleUpdate($hash, "state", "no rows in ".$infile, 1);
	        Log3($name, 3, "DbLog $name: $infile doesn't contain any rows - no imports done.");
		}
		
	    return;
	}
    elsif ($a[1] eq 'count') {
        $dbh = DbLog_ConnectNewDBH($hash);
        if(!$dbh) {
            Log3($name, 1, "DbLog $name: DBLog_Set - count - DB connect not possible");
			return;
        } else {
            Log3($name, 4, "DbLog $name: Records count requested.");
			my $c = $dbh->selectrow_array("SELECT count(*) FROM $history");
            readingsSingleUpdate($hash, 'countHistory', $c ,1);
            $c = $dbh->selectrow_array("SELECT count(*) FROM $current");
            readingsSingleUpdate($hash, 'countCurrent', $c ,1);
		    $dbh->disconnect();
			
            InternalTimer(gettimeofday()+5, "DbLog_execmemcache", $hash, 0);			
		}
    }
	elsif ($a[1] eq 'countNbl') {
        if ($hash->{HELPER}{COUNT_PID} && $hash->{HELPER}{COUNT_PID}{pid} !~ m/DEAD/){  
            $ret = "DbLog count already in progress. Please wait until the running process is finished.";
        } else {
            delete $hash->{HELPER}{COUNT_PID};
            $hash->{HELPER}{COUNT_PID} = BlockingCall("DbLog_countNbl","$name","DbLog_countNbl_finished");
            return;
        }			
    }
    elsif ($a[1] eq 'deleteOldDays') {
        Log3 ($name, 3, "DbLog $name -> Deletion of records older than $a[2] days in database $db requested");
        my ($c, $cmd);
        
        $dbh = DbLog_ConnectNewDBH($hash);
        if(!$dbh) {
            Log3($name, 1, "DbLog $name: DBLog_Set - deleteOldDays - DB connect not possible");
			return;
        } else {
            $cmd = "delete from $history where TIMESTAMP < ";
        
            if ($hash->{MODEL} eq 'SQLITE')        { $cmd .= "datetime('now', '-$a[2] days')"; }
            elsif ($hash->{MODEL} eq 'MYSQL')      { $cmd .= "DATE_SUB(CURDATE(),INTERVAL $a[2] DAY)"; }
            elsif ($hash->{MODEL} eq 'POSTGRESQL') { $cmd .= "NOW() - INTERVAL '$a[2]' DAY"; }
            else { $cmd = undef; $ret = 'Unknown database type. Maybe you can try userCommand anyway.'; }

            if(defined($cmd)) {
                $c = $dbh->do($cmd);
				$c = 0 if($c == 0E0);
				eval {$dbh->commit() if(!$dbh->{AutoCommit});};
				$dbh->disconnect();
				Log3 ($name, 3, "DbLog $name -> deleteOldDays finished. $c entries of database $db deleted.");
                readingsSingleUpdate($hash, 'lastRowsDeleted', $c ,1);
            }
			
			InternalTimer(gettimeofday()+5, "DbLog_execmemcache", $hash, 0);
        }
    }
	elsif ($a[1] eq 'deleteOldDaysNbl') {
        if (defined $a[2] && $a[2] =~ /^\d+$/) {
            if ($hash->{HELPER}{DELDAYS_PID} && $hash->{HELPER}{DELDAYS_PID}{pid} !~ m/DEAD/) {  
                $ret = "deleteOldDaysNbl already in progress. Please wait until the running process is finished.";
            } else {
			    delete $hash->{HELPER}{DELDAYS_PID};
                $hash->{HELPER}{DELDAYS} = $a[2];
				Log3 ($name, 3, "DbLog $name -> Deletion of records older than $a[2] days in database $db requested");
                $hash->{HELPER}{DELDAYS_PID} = BlockingCall("DbLog_deldaysNbl","$name","DbLog_deldaysNbl_done");
                return;
            }
        } else {
            Log3($name, 1, "DbLog $name: deleteOldDaysNbl error, no <days> given.");
            $ret = "deleteOldDaysNbl error, no <days> given.";
        }
    }
    elsif ($a[1] eq 'userCommand') {
        $dbh = DbLog_ConnectNewDBH($hash);
        if(!$dbh) {
            Log3($name, 1, "DbLog $name: DBLog_Set - userCommand - DB connect not possible");
			return;
        } else {
            Log3($name, 4, "DbLog $name: userCommand execution requested.");
            my ($c, @cmd, $sql);
            @cmd = @a;
            shift(@cmd); shift(@cmd);
            $sql = join(" ",@cmd);
            readingsSingleUpdate($hash, 'userCommand', $sql, 1);
            $dbh->{RaiseError} = 1; 
            $dbh->{PrintError} = 0;
            my $error;
            eval { $c = $dbh->selectrow_array($sql); };
			if($@) {
                $error = $@;
                Log3($name, 1, "DbLog $name: DBLog_Set - $error");               
            }
            
            my $res = $error?$error:(defined($c))?$c:"no result";
			Log3($name, 4, "DbLog $name: DBLog_Set - userCommand - result: $res");
            readingsSingleUpdate($hash, 'userCommandResult', $res ,1);
			$dbh->disconnect();
			
			InternalTimer(gettimeofday()+5, "DbLog_execmemcache", $hash, 0);
        }
    }
    else { $ret = $usage; }

return $ret;
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
sub DbLog_regexpFn($$) {                            
  my ($name, $filter) = @_;
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

################################################################
# Parsefunktion, abhaengig vom Devicetyp
################################################################
sub DbLog_ParseEvent($$$) {
  my ($device, $type, $event)= @_;
  my (@result,$reading,$value,$unit);

  # Splitfunktion der Eventquelle aufrufen (ab 2.9.1)
  ($reading, $value, $unit) = CallInstanceFn($device, "DbLog_splitFn", $event, $device);
  # undef bedeutet, Modul stellt keine DbLog_splitFn bereit
  if($reading) {
      return ($reading, $value, $unit);
  }

  # split the event into reading, value and unit
  # "day-temp: 22.0 (Celsius)" -> "day-temp", "22.0 (Celsius)"
  my @parts = split(/: /,$event);
  $reading  = shift @parts;
  if(@parts == 2) { 
    $value = $parts[0];
    $unit  = $parts[1];
  } else {
    $value = join(": ", @parts);
    $unit  = "";
  } 

  #default
  if(!defined($reading)) { $reading = ""; }
  if(!defined($value))   { $value   = ""; }
  if( $value eq "" ) {
    $reading = "state";
    $value   = $event;
  }

  #globales Abfangen von 
  # - temperature
  # - humidity
  if   ($reading =~ m(^temperature)) { $unit= "°C"; } # wenn reading mit temperature beginnt
  elsif($reading =~ m(^humidity)) { $unit= "%"; }

  # the interpretation of the argument depends on the device type
  # EMEM, M232Counter, M232Voltage return plain numbers
  if(($type eq "M232Voltage") ||
     ($type eq "M232Counter") ||
     ($type eq "EMEM")) {
  }
  #OneWire 
  elsif(($type eq "OWMULTI")) {
    if(int(@parts)>1) {
      $reading = "data";
      $value = $event;
    } else {
      @parts = split(/\|/, AttrVal($device, $reading."VUnit", ""));
      $unit = $parts[1] if($parts[1]);
      if(lc($reading) =~ m/temp/) {
        $value=~ s/ \(Celsius\)//;
        $value=~ s/([-\.\d]+).*/$1/;
        $unit= "°C";
      }
      elsif(lc($reading) =~ m/(humidity|vwc)/) { 
        $value=~ s/ \(\%\)//; 
        $unit= "%"; 
      }
    }
  }
  # Onewire
  elsif(($type eq "OWAD") ||
        ($type eq "OWSWITCH")) {
      if(int(@parts)>1) {
        $reading = "data";
        $value = $event;
      } else {
        @parts = split(/\|/, AttrVal($device, $reading."Unit", ""));
        $unit = $parts[1] if($parts[1]);
      }
  }
  
  # ZWAVE
  elsif ($type eq "ZWAVE") {
    if ( $value=~/([-\.\d]+)\s([a-z].*)/i ) {
     $value = $1;
     $unit  = $2;
    }
  }

  # FBDECT
  elsif ($type eq "FBDECT") {
    if ( $value=~/([\.\d]+)\s([a-z].*)/i ) {
     $value = $1;
     $unit  = $2;
    }
  }
  
  # MAX
  elsif(($type eq "MAX")) {
    $unit= "°C" if(lc($reading) =~ m/temp/);
    $unit= "%"   if(lc($reading) eq "valveposition");
  }

  # FS20
  elsif(($type eq "FS20") || ($type eq "X10")) {
    if($reading =~ m/^dim(\d+).*/o) {
      $value = $1;
      $reading= "dim";
      $unit= "%";
    }
    elsif(!defined($value) || $value eq "") {
      $value= $reading;
      $reading= "data";
    }
  }

  # FHT
  elsif($type eq "FHT") {
    if($reading =~ m(-from[12]\ ) || $reading =~ m(-to[12]\ )) {
      @parts= split(/ /,$event);
      $reading= $parts[0];
      $value= $parts[1];
      $unit= "";
    }
    elsif($reading =~ m(-temp)) { $value=~ s/ \(Celsius\)//; $unit= "°C"; }
    elsif($reading =~ m(temp-offset)) { $value=~ s/ \(Celsius\)//; $unit= "°C"; }
    elsif($reading =~ m(^actuator[0-9]*)) {
      if($value eq "lime-protection") {
        $reading= "actuator-lime-protection";
        undef $value;
      }
      elsif($value =~ m(^offset:)) {
        $reading= "actuator-offset";
        @parts= split(/: /,$value);
        $value= $parts[1];
        if(defined $value) {
          $value=~ s/%//; $value= $value*1.; $unit= "%";
        }
      }
      elsif($value =~ m(^unknown_)) {
        @parts= split(/: /,$value);
        $reading= "actuator-" . $parts[0];
        $value= $parts[1];
        if(defined $value) {
          $value=~ s/%//; $value= $value*1.; $unit= "%";
        }
      }
      elsif($value =~ m(^synctime)) {
        $reading= "actuator-synctime";
        undef $value;
      }
      elsif($value eq "test") {
        $reading= "actuator-test";
        undef $value;
      }
      elsif($value eq "pair") {
        $reading= "actuator-pair";
        undef $value;
      }
      else {
        $value=~ s/%//; $value= $value*1.; $unit= "%";
      }
    }
  }
  # KS300
  elsif($type eq "KS300") {
    if($event =~ m(T:.*)) { $reading= "data"; $value= $event; }
    elsif($event =~ m(avg_day)) { $reading= "data"; $value= $event; }
    elsif($event =~ m(avg_month)) { $reading= "data"; $value= $event; }
    elsif($reading eq "temperature") { $value=~ s/ \(Celsius\)//; $unit= "°C"; }
    elsif($reading eq "wind") { $value=~ s/ \(km\/h\)//; $unit= "km/h"; }
    elsif($reading eq "rain") { $value=~ s/ \(l\/m2\)//; $unit= "l/m2"; }
    elsif($reading eq "rain_raw") { $value=~ s/ \(counter\)//; $unit= ""; }
    elsif($reading eq "humidity") { $value=~ s/ \(\%\)//; $unit= "%"; }
    elsif($reading eq "israining") {
      $value=~ s/ \(yes\/no\)//;
      $value=~ s/no/0/;
      $value=~ s/yes/1/;
    }
  }
  # HMS
  elsif($type eq "HMS" ||
        $type eq "CUL_WS" ||
        $type eq "OWTHERM") {
    if($event =~ m(T:.*)) { $reading= "data"; $value= $event; }
    elsif($reading eq "temperature") {
      $value=~ s/ \(Celsius\)//; 
      $value=~ s/([-\.\d]+).*/$1/; #OWTHERM
      $unit= "°C"; 
    }
    elsif($reading eq "humidity") { $value=~ s/ \(\%\)//; $unit= "%"; }
    elsif($reading eq "battery") {
      $value=~ s/ok/1/;
      $value=~ s/replaced/1/;
      $value=~ s/empty/0/;
    }
  }
  # CUL_HM
  elsif ($type eq "CUL_HM") {
    # remove trailing %  
    $value=~ s/ \%$//;
  }

  # BS
  elsif($type eq "BS") {
    if($event =~ m(brightness:.*)) {
      @parts= split(/ /,$event);
      $reading= "lux";
      $value= $parts[4]*1.;
      $unit= "lux";
    }
  }

  # RFXTRX Lighting
  elsif($type eq "TRX_LIGHT") {
    if($reading =~ m/^level (\d+)/) {
        $value = $1;
        $reading= "level";
    }
  }

  # RFXTRX Sensors
  elsif($type eq "TRX_WEATHER") {
    if($reading eq "energy_current") { $value=~ s/ W//; }
    elsif($reading eq "energy_total") { $value=~ s/ kWh//; }
#    elsif($reading eq "temperature") {TODO}
#    elsif($reading eq "temperature")  {TODO
    elsif($reading eq "battery") {
      if ($value=~ m/(\d+)\%/) { 
        $value= $1; 
      }
      else {
        $value= ($value eq "ok");
      }
    }
  }

  # Weather
  elsif($type eq "WEATHER") {
    if($event =~ m(^wind_condition)) {
      @parts= split(/ /,$event); # extract wind direction from event
      if(defined $parts[0]) {
        $reading = "wind_condition";
        $value= "$parts[1] $parts[2] $parts[3]";
      }
    }
    if($reading eq "wind_condition") { $unit= "km/h"; }
    elsif($reading eq "wind_chill") { $unit= "°C"; }
    elsif($reading eq "wind_direction") { $unit= ""; }
    elsif($reading =~ m(^wind)) { $unit= "km/h"; } # wind, wind_speed
    elsif($reading =~ m(^temperature)) { $unit= "°C"; } # wenn reading mit temperature beginnt
    elsif($reading =~ m(^humidity)) { $unit= "%"; }
    elsif($reading =~ m(^pressure)) { $unit= "hPa"; }
    elsif($reading =~ m(^pressure_trend)) { $unit= ""; }
  }

  # FHT8V
  elsif($type eq "FHT8V") {
    if($reading =~ m(valve)) {
      @parts= split(/ /,$event);
      $reading= $parts[0];
      $value= $parts[1];
      $unit= "%";
    }
  }

  # Dummy
  elsif($type eq "DUMMY")  {
    if( $value eq "" ) {
      $reading= "data";
      $value= $event;
    }
    $unit= "";
  }

  @result= ($reading,$value,$unit);
  return @result;
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

sub DbLog_Log($$) {
  # $hash is my entry, $dev_hash is the entry of the changed device
  my ($hash, $dev_hash) = @_;
  my $name     = $hash->{NAME};
  my $dev_name = $dev_hash->{NAME};
  my $dev_type = uc($dev_hash->{TYPE});
  my $async    = AttrVal($name, "asyncMode", undef);
  my $clim     = AttrVal($name, "cacheLimit", 500);
  my $ce       = AttrVal($name, "cacheEvents", 0);
  my ($net,$force);

  return if(IsDisabled($name) || !$hash->{HELPER}{COLSET} || $init_done != 1);

  # Notify-Routine Startzeit
  my $nst = [gettimeofday];
  
  my $events = deviceEvents($dev_hash, AttrVal($name, "addStateEvent", 1));  
  return if(!$events);
  
  my $max = int(@{$events});
  
  # verbose4 Logs nur für Devices in Attr "verbose4Devs"
  my $vb4show  = 0;
  my @vb4devs  = split(",", AttrVal($name, "verbose4Devs", ""));
  if (!@vb4devs) {
      $vb4show = 1;
  } else {
      foreach (@vb4devs) {
	      if($dev_name =~ m/$_/i) {
		      $vb4show = 1;
			  last;
		  }
	  }
  }
  
  if($vb4show && !$hash->{HELPER}{".RUNNING_PID"}) {
      Log3 $name, 4, "DbLog $name -> ################################################################";
      Log3 $name, 4, "DbLog $name -> ###              start of new Logcycle                       ###";
      Log3 $name, 4, "DbLog $name -> ################################################################";
      Log3 $name, 4, "DbLog $name -> number of events received: $max for device: $dev_name";
  }
    
  my $re                 = $hash->{REGEXP};
  my @row_array;
  my ($event,$reading,$value,$unit);
  my $ts_0               = TimeNow();                                    # timestamp in SQL format YYYY-MM-DD hh:mm:ss
  my $now                = gettimeofday();                               # get timestamp in seconds since epoch
  my $DbLogExclude       = AttrVal($dev_name, "DbLogExclude", undef);
  my $DbLogInclude       = AttrVal($dev_name, "DbLogInclude",undef);
  my $DbLogValueFn       = AttrVal($dev_name, "DbLogValueFn","");
  my $DbLogSelectionMode = AttrVal($name, "DbLogSelectionMode","Exclude");
  my $value_fn           = AttrVal( $name, "valueFn", "" );  
  
  # Funktion aus Device spezifischer DbLogValueFn validieren
  if( $DbLogValueFn =~ m/^\s*(\{.*\})\s*$/s ) {
      $DbLogValueFn = $1;
  } else {
      $DbLogValueFn = '';
  }
  
  # Funktion aus Attr valueFn validieren
  if( $value_fn =~ m/^\s*(\{.*\})\s*$/s ) {
      $value_fn = $1;
  } else {
      $value_fn = '';
  }
    
  #one Transaction
  eval {  
      for (my $i = 0; $i < $max; $i++) {
          my $next = 0;
          my $event = $events->[$i];
          $event = "" if(!defined($event));
		  $event = DbLog_charfilter($event) if(AttrVal($name, "useCharfilter",0));
          Log3 $name, 4, "DbLog $name -> check Device: $dev_name , Event: $event" if($vb4show && !$hash->{HELPER}{".RUNNING_PID"});  
	  
	      if($dev_name =~ m/^$re$/ || "$dev_name:$event" =~ m/^$re$/ || $DbLogSelectionMode eq 'Include') {
			  my $timestamp = $ts_0;
              $timestamp = $dev_hash->{CHANGETIME}[$i] if(defined($dev_hash->{CHANGETIME}[$i]));
              $event =~ s/\|/_ESC_/g;    # escape Pipe "|"
              
              my @r = DbLog_ParseEvent($dev_name, $dev_type, $event);
			  $reading = $r[0];
              $value   = $r[1];
              $unit    = $r[2];
              if(!defined $reading) {$reading = "";}
              if(!defined $value) {$value = "";}
              if(!defined $unit || $unit eq "") {$unit = AttrVal("$dev_name", "unit", "");}
              
              $unit = DbLog_charfilter($unit) if(AttrVal($name, "useCharfilter",0));
              
              # Devices / Readings ausschließen durch Attribut "excludeDevs"
              # attr <device> excludeDevs [<devspec>#]<Reading1>,[<devspec>#]<Reading2>,[<devspec>#]<Reading..>
              my ($exc,@excldr,$ds,$rd,@exdvs);
              $exc = AttrVal($name, "excludeDevs", "");
              if($exc) {
                  $exc    =~ s/[\s\n]/,/g;
                  @excldr = split(",",$exc);
                  foreach my $excl (@excldr) {
                      ($ds,$rd) = split("#",$excl);
	                  @exdvs = devspec2array($ds);
	                  if(@exdvs) {
                          # Log3 $name, 3, "DbLog $name -> excludeDevs: @exdvs";
	                      foreach (@exdvs) {
                              if($rd) {
		                          if("$dev_name:$reading" =~ m/^$_:$rd$/) {
	                                  Log3 $name, 4, "DbLog $name -> Device:Reading \"$dev_name:$reading\" global excluded from logging by attribute \"excludeDevs\" " if($vb4show && !$hash->{HELPER}{".RUNNING_PID"});
                                      $next = 1;
		                          }
                              } else {
		                          if($dev_name =~ m/^$_$/) {
	                                  Log3 $name, 4, "DbLog $name -> Device \"$dev_name\" global excluded from logging by attribute \"excludeDevs\" " if($vb4show && !$hash->{HELPER}{".RUNNING_PID"});
                                      $next = 1;
		                          }                          
                              }
		                  }
	                  }
                  }
                  next if($next); 
              }
			  	  
			  Log3 $name, 5, "DbLog $name -> parsed Event: $dev_name , Event: $event" if($vb4show && !$hash->{HELPER}{".RUNNING_PID"});  
		      Log3 $name, 5, "DbLog $name -> DbLogExclude of \"$dev_name\": $DbLogExclude" if($vb4show && !$hash->{HELPER}{".RUNNING_PID"} && $DbLogExclude);
		      Log3 $name, 5, "DbLog $name -> DbLogInclude of \"$dev_name\": $DbLogInclude" if($vb4show && !$hash->{HELPER}{".RUNNING_PID"} && $DbLogInclude);
              
              #Je nach DBLogSelectionMode muss das vorgegebene Ergebnis der Include-, bzw. Exclude-Pruefung
              #entsprechend unterschiedlich vorbelegt sein.
              #keine Readings loggen die in DbLogExclude explizit ausgeschlossen sind
              my $DoIt = 0;
              $DoIt = 1 if($DbLogSelectionMode =~ m/Exclude/ );
          
		      if($DbLogExclude && $DbLogSelectionMode =~ m/Exclude/) {
                  # Bsp: "(temperature|humidity):300,battery:3600"
                  my @v1 = split(/,/, $DbLogExclude);
              
			      for (my $i=0; $i<int(@v1); $i++) {
                      my @v2 = split(/:/, $v1[$i]);
                      $DoIt = 0 if(!$v2[1] && $reading =~ m,^$v2[0]$,); #Reading matcht auf Regexp, kein MinIntervall angegeben
                  
				      if(($v2[1] && $reading =~ m,^$v2[0]$,) && ($v2[1] =~ m/^(\d+)$/)) {
                          #Regexp matcht und MinIntervall ist angegeben
                          my $lt = $defs{$dev_hash->{NAME}}{Helper}{DBLOG}{$reading}{$hash->{NAME}}{TIME};
                          my $lv = $defs{$dev_hash->{NAME}}{Helper}{DBLOG}{$reading}{$hash->{NAME}}{VALUE};
                          $lt    = 0  if(!$lt);         
                          $lv    = "" if(!defined $lv);                   # Forum: #100344
                          $force = ($v2[2] && $v2[2] =~ /force/i)?1:0;    # Forum: #97148

                          if(($now-$lt < $v2[1]) && ($lv eq $value || $force)) {
                              # innerhalb MinIntervall und LastValue=Value
                              $DoIt = 0;
                          }
                      }
                  }
              }
        
		      #Hier ggf. zusätzlich noch dbLogInclude pruefen, falls bereits durch DbLogExclude ausgeschlossen
              #Im Endeffekt genau die gleiche Pruefung, wie fuer DBLogExclude, lediglich mit umgegkehrtem Ergebnis.
              if($DoIt == 0) {
                  if($DbLogInclude && ($DbLogSelectionMode =~ m/Include/)) {
                      my @v1 = split(/,/, $DbLogInclude);
              
			          for (my $i=0; $i<int(@v1); $i++) {
                          my @v2 = split(/:/, $v1[$i]);
                          $DoIt = 1 if($reading =~ m,^$v2[0]$,); #Reading matcht auf Regexp
                  
				          if(($v2[1] && $reading =~ m,^$v2[0]$,) && ($v2[1] =~ m/^(\d+)$/)) {
                              #Regexp matcht und MinIntervall ist angegeben
                              my $lt = $defs{$dev_hash->{NAME}}{Helper}{DBLOG}{$reading}{$hash->{NAME}}{TIME};
                              my $lv = $defs{$dev_hash->{NAME}}{Helper}{DBLOG}{$reading}{$hash->{NAME}}{VALUE};
                              $lt    = 0  if(!$lt);
                              $lv    = "" if(!defined $lv);                   # Forum: #100344
                              $force = ($v2[2] && $v2[2] =~ /force/i)?1:0;    # Forum: #97148
       
                              if(($now-$lt < $v2[1]) && ($lv eq $value || $force)) {
                                  # innerhalb MinIntervall und LastValue=Value
                                  $DoIt = 0;
                              }
                          }
                      }
                  }
              }
              next if($DoIt == 0);
		
	    	  if ($DoIt) {
                  $defs{$dev_name}{Helper}{DBLOG}{$reading}{$hash->{NAME}}{TIME}  = $now;
                  $defs{$dev_name}{Helper}{DBLOG}{$reading}{$hash->{NAME}}{VALUE} = $value;
                  
			      # Device spezifische DbLogValueFn-Funktion anwenden
 		  	      if($DbLogValueFn ne '') {
 				      my $TIMESTAMP  = $timestamp;
 				      my $EVENT      = $event;
 				      my $READING    = $reading;
 		  	          my $VALUE 	 = $value;
 				      my $UNIT   	 = $unit;
					  my $IGNORE     = 0;
                      my $CN         = " ";

 				      eval $DbLogValueFn;
					  Log3 $name, 2, "DbLog $name -> error device \"$dev_name\" specific DbLogValueFn: ".$@ if($@);
                      
					  if($IGNORE) {
					      # aktueller Event wird nicht geloggt wenn $IGNORE=1 gesetzt in $DbLogValueFn
						  Log3 $hash->{NAME}, 4, "DbLog $name -> Event ignored by device \"$dev_name\" specific DbLogValueFn - TS: $timestamp, Device: $dev_name, Type: $dev_type, Event: $event, Reading: $reading, Value: $value, Unit: $unit"
						                          if($vb4show && !$hash->{HELPER}{".RUNNING_PID"});
					      next;  
					  }
					  
                      my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($TIMESTAMP =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
                      eval { my $epoch_seconds_begin = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };
                      if (!$@) {
                          $timestamp = $TIMESTAMP;
                      } else {
                          Log3 ($name, 2, "DbLog $name -> TIMESTAMP got from DbLogValueFn in $dev_name is invalid: $TIMESTAMP");
                      }
 				      $reading   = $READING    if($READING ne '');
 		  	          $value     = $VALUE      if(defined $VALUE);
 				      $unit      = $UNIT       if(defined $UNIT);
                  }
				  
			      # zentrale valueFn im DbLog-Device abarbeiten
 		  	      if($value_fn ne '') {
 				      my $TIMESTAMP  = $timestamp;
 				      my $DEVICE     = $dev_name;
 				      my $DEVICETYPE = $dev_type;
 				      my $EVENT      = $event;
 				      my $READING    = $reading;
 		  	          my $VALUE 	 = $value;
 				      my $UNIT   	 = $unit;
					  my $IGNORE     = 0;
                      my $CN         = " ";

 				      eval $value_fn;
					  Log3 $name, 2, "DbLog $name -> error valueFn: ".$@ if($@);
                      
					  if($IGNORE) {
					      # aktueller Event wird nicht geloggt wenn $IGNORE=1 gesetzt in $value_fn
						  Log3 $hash->{NAME}, 4, "DbLog $name -> Event ignored by valueFn - TS: $timestamp, Device: $dev_name, Type: $dev_type, Event: $event, Reading: $reading, Value: $value, Unit: $unit"
						                          if($vb4show && !$hash->{HELPER}{".RUNNING_PID"});
					      next;  
					  }
                      my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($TIMESTAMP =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
                      eval { my $epoch_seconds_begin = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };
                      if (!$@) {
                          $timestamp = $TIMESTAMP;
                      } else {
                          Log3 ($name, 2, "DbLog $name -> Parameter TIMESTAMP got from valueFn is invalid: $TIMESTAMP");
                      }
 				      $dev_name  = $DEVICE     if($DEVICE ne '');
 				      $dev_type  = $DEVICETYPE if($DEVICETYPE ne '');
 				      $reading   = $READING    if($READING ne '');
 		  	          $value     = $VALUE      if(defined $VALUE);
 				      $unit      = $UNIT       if(defined $UNIT);
                  }

				  # Daten auf maximale Länge beschneiden
                  ($dev_name,$dev_type,$event,$reading,$value,$unit) = DbLog_cutCol($hash,$dev_name,$dev_type,$event,$reading,$value,$unit);
  
			      my $row = ($timestamp."|".$dev_name."|".$dev_type."|".$event."|".$reading."|".$value."|".$unit);
				  Log3 $hash->{NAME}, 4, "DbLog $name -> added event - Timestamp: $timestamp, Device: $dev_name, Type: $dev_type, Event: $event, Reading: $reading, Value: $value, Unit: $unit"
				                          if($vb4show && !$hash->{HELPER}{".RUNNING_PID"});	
                  
				  if($async) {
				      # asynchoner non-blocking Mode
					  # Cache & CacheIndex für Events zum asynchronen Schreiben in DB
					  $data{DbLog}{$name}{cache}{index}++;
				      my $index = $data{DbLog}{$name}{cache}{index};
				      $data{DbLog}{$name}{cache}{memcache}{$index} = $row;
					  
					  my $memcount = $data{DbLog}{$name}{cache}{memcache}?scalar(keys %{$data{DbLog}{$name}{cache}{memcache}}):0;
	                  if($ce == 1) {
                          readingsSingleUpdate($hash, "CacheUsage", $memcount, 1); 
	                  } else {
	                      readingsSingleUpdate($hash, 'CacheUsage', $memcount, 0); 
	                  }
					  # asynchrone Schreibroutine aufrufen wenn Füllstand des Cache erreicht ist
					  if($memcount >= $clim) {
                          my $lmlr     = $hash->{HELPER}{LASTLIMITRUNTIME};
                          my $syncival = AttrVal($name, "syncInterval", 30);
                          if(!$lmlr || gettimeofday() > $lmlr+($syncival/2)) {
					          Log3 $hash->{NAME}, 4, "DbLog $name -> Number of cache entries reached cachelimit $clim - start database sync.";
					          DbLog_execmemcache($hash);
                              $hash->{HELPER}{LASTLIMITRUNTIME} = gettimeofday();
                          }
					  }
					  # Notify-Routine Laufzeit ermitteln
                      $net = tv_interval($nst);
				  } else {
				      # synchoner Mode
				      push(@row_array, $row);		
				  }  
              }		  
          }
      }
  }; 
  if(!$async) {  
      if(@row_array) {
	      # synchoner Mode
          return if($hash->{HELPER}{REOPEN_RUNS});              # return wenn "reopen" mit Ablaufzeit gestartet ist          
          my $error = DbLog_Push($hash, $vb4show, @row_array);
          Log3 ($name, 5, "DbLog $name -> DbLog_Push Returncode: $error") if($vb4show);
          CancelDelayedShutdown($name) if($hash->{HELPER}{SHUTDOWNSEQ});
          Log3 ($name, 2, "DbLog $name - Last database write cycle done") if(delete $hash->{HELPER}{SHUTDOWNSEQ});
          my $state = $error?$error:(IsDisabled($name))?"disabled":"connected";
          my $evt   = ($state eq $hash->{HELPER}{OLDSTATE})?0:1;
          readingsSingleUpdate($hash, "state", $state, $evt);
          $hash->{HELPER}{OLDSTATE} = $state;
		  
		  # Notify-Routine Laufzeit ermitteln
          $net = tv_interval($nst);
      } else {
          CancelDelayedShutdown($name) if($hash->{HELPER}{SHUTDOWNSEQ});
          Log3 ($name, 2, "DbLog $name - no data for last database write cycle") if(delete $hash->{HELPER}{SHUTDOWNSEQ});
      }
  }
  if($net && AttrVal($name, "showNotifyTime", undef)) {
      readingsSingleUpdate($hash, "notify_processing_time", sprintf("%.4f",$net), 1);
  }
return;
}

#################################################################################################
# Schreibroutine Einfügen Werte in DB im Synchronmode 
#################################################################################################
sub DbLog_Push(@) {
  my ($hash, $vb4show, @row_array) = @_;
  my $name      = $hash->{NAME};
  my $DbLogType = AttrVal($name, "DbLogType", "History");
  my $supk      = AttrVal($name, "noSupportPK", 0);
  my $tl        = AttrVal($name, "traceLevel", 0);
  my $tf        = AttrVal($name, "traceFlag", "SQL");
  my $bi        = AttrVal($name, "bulkInsert", 0);
  my $history   = $hash->{HELPER}{TH};
  my $current   = $hash->{HELPER}{TC};
  my $errorh    = 0;
  my $error     = 0;
  my $doins     = 0;  # Hilfsvariable, wenn "1" sollen inserts in Tabelle current erfolgen (updates schlugen fehl) 
  my $dbh;
  
  my $nh = ($hash->{MODEL} ne 'SQLITE')?1:0;
  # Unterscheidung $dbh um Abbrüche in Plots (SQLite) zu vermeiden und 
  # andererseite kein "MySQL-Server has gone away" Fehler
  if ($nh) {
      $dbh = DbLog_ConnectNewDBH($hash);
	  return if(!$dbh);
  } else {
      $dbh = $hash->{DBHP};
      eval {
          if ( !$dbh || not $dbh->ping ) {
              # DB Session dead, try to reopen now !
              DbLog_ConnectPush($hash,1);
          }  
      };
      if ($@) {
          Log3($name, 1, "DbLog $name: DBLog_Push - DB Session dead! - $@");
	      return $@;
      } else {
          $dbh = $hash->{DBHP};
      }
  } 
  
  $dbh->{RaiseError} = 1; 
  $dbh->{PrintError} = 0;
  
  if($tl) {
      # Tracelevel setzen  
      $dbh->{TraceLevel} = "$tl|$tf";       
  } 
  
  my ($useac,$useta) = DbLog_commitMode($hash);
  my $ac = ($dbh->{AutoCommit})?"ON":"OFF";
  my $tm = ($useta)?"ON":"OFF";
  
  Log3 $name, 4, "DbLog $name -> ################################################################";
  Log3 $name, 4, "DbLog $name -> ###         New database processing cycle - synchronous      ###";
  Log3 $name, 4, "DbLog $name -> ################################################################";
  Log3 $name, 4, "DbLog $name -> DbLogType is: $DbLogType";
  Log3 $name, 4, "DbLog $name -> AutoCommit mode: $ac, Transaction mode: $tm";
  Log3 $name, 4, "DbLog $name -> Insert mode: ".($bi?"Bulk":"Array");
  
  # check ob PK verwendet wird, @usepkx?Anzahl der Felder im PK:0 wenn kein PK, $pkx?Namen der Felder:none wenn kein PK 
  my ($usepkh,$usepkc,$pkh,$pkc);
  if (!$supk) {
      ($usepkh,$usepkc,$pkh,$pkc) = DbLog_checkUsePK($hash,$dbh);
  } else {
      Log3 $hash->{NAME}, 5, "DbLog $name -> Primary Key usage suppressed by attribute noSupportPK";
  }
  
  my (@timestamp,@device,@type,@event,@reading,@value,@unit);
  my (@timestamp_cur,@device_cur,@type_cur,@event_cur,@reading_cur,@value_cur,@unit_cur);
  my ($st,$sth_ih,$sth_ic,$sth_uc,$sqlins);
  my ($tuples, $rows);
  
  no warnings 'uninitialized';
  
  my $ceti = $#row_array+1;
  
  foreach my $row (@row_array) {
      my @a = split("\\|",$row);
      s/_ESC_/\|/g for @a;                    # escaped Pipe return to "|"
	  push(@timestamp, "$a[0]"); 
	  push(@device, "$a[1]");   
	  push(@type, "$a[2]");  
	  push(@event, "$a[3]");  
	  push(@reading, "$a[4]"); 
	  push(@value, "$a[5]"); 
	  push(@unit, "$a[6]"); 
	  Log3 $hash->{NAME}, 4, "DbLog $name -> processing event Timestamp: $a[0], Device: $a[1], Type: $a[2], Event: $a[3], Reading: $a[4], Value: $a[5], Unit: $a[6]"
							 if($vb4show);
  }	  
  use warnings;
 
  if($bi) {
      #######################
      # Bulk-Insert
      #######################
      $st = [gettimeofday];               # SQL-Startzeit
      
      if (lc($DbLogType) =~ m(history)) { 
          ########################################      
          # insert history mit/ohne primary key
          if ($usepkh && $hash->{MODEL} eq 'MYSQL') {
              $sqlins = "INSERT IGNORE INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES ";
          } elsif ($usepkh && $hash->{MODEL} eq 'SQLITE') {
              $sqlins = "INSERT OR IGNORE INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES ";
          } elsif ($usepkh && $hash->{MODEL} eq 'POSTGRESQL') {
              $sqlins = "INSERT INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES ";
          } else {
              # ohne PK
              $sqlins = "INSERT INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES ";
          } 
          
          no warnings 'uninitialized';          
          foreach my $row (@row_array) {
              my @a = split("\\|",$row);       
              s/_ESC_/\|/g for @a;                    # escaped Pipe return to "|"
              Log3 $hash->{NAME}, 5, "DbLog $name -> processing event Timestamp: $a[0], Device: $a[1], Type: $a[2], Event: $a[3], Reading: $a[4], Value: $a[5], Unit: $a[6]";
              $a[3] =~ s/'/''/g;                      # escape ' with ''
              $a[5] =~ s/'/''/g;                      # escape ' with ''
              $a[6] =~ s/'/''/g;                      # escape ' with ''
              $sqlins .= "('$a[0]','$a[1]','$a[2]','$a[3]','$a[4]','$a[5]','$a[6]'),";
          }	  
          use warnings;
          
          chop($sqlins);
          
          if ($usepkh && $hash->{MODEL} eq 'POSTGRESQL') {
              $sqlins .= " ON CONFLICT DO NOTHING";
          }
          
          eval { $dbh->begin_work() if($useta && $dbh->{AutoCommit}); };   # Transaktion wenn gewünscht und autocommit ein
          if ($@) {
              Log3($name, 2, "DbLog $name -> Error start transaction for $history - $@");
          }
          eval { $sth_ih = $dbh->prepare($sqlins);
                 if($tl) {
                     # Tracelevel setzen       
                     $sth_ih->{TraceLevel} = "$tl|$tf";
                 }            
                 my $ins_hist = $sth_ih->execute();
                 $ins_hist = 0 if($ins_hist eq "0E0");
                 
                 if($ins_hist == $ceti) {
                     Log3 $hash->{NAME}, 4, "DbLog $name -> $ins_hist of $ceti events inserted into table $history".($usepkh?" using PK on columns $pkh":"");
                 } else {
                     if($usepkh) {
                         Log3 $hash->{NAME}, 3, "DbLog $name -> INFO - ".$ins_hist." of $ceti events inserted into table $history due to PK on columns $pkh";    			  
                     } else {
                         Log3 $hash->{NAME}, 2, "DbLog $name -> WARNING - only ".$ins_hist." of $ceti events inserted into table $history";    			  
                     }
                 }               
                 eval {$dbh->commit() if(!$dbh->{AutoCommit});};          # Data commit
                 if ($@) {
                     Log3($name, 2, "DbLog $name -> Error commit $history - $@");
                 } else {
                     if(!$dbh->{AutoCommit}) {
                         Log3($name, 4, "DbLog $name -> insert table $history committed");
                     } else {
                         Log3($name, 4, "DbLog $name -> insert table $history committed by autocommit");
                     }
                 }               
          };
           
          if ($@) {
              $errorh = $@;
              Log3 $hash->{NAME}, 2, "DbLog $name -> Error table $history - $errorh";
              eval {$dbh->rollback() if(!$dbh->{AutoCommit});};  # issue Turning on AutoCommit failed
              if ($@) {
                  Log3($name, 2, "DbLog $name -> Error rollback $history - $@");
              } else {
                  Log3($name, 4, "DbLog $name -> insert $history rolled back");
              }
          } 
      }   

      if (lc($DbLogType) =~ m(current)) {
          #################################################################
          # insert current mit/ohne primary key 
          # Array-Insert wird auch bei Bulk verwendet weil im Bulk-Mode 
          # die nicht upgedateten Sätze nicht identifiziert werden können          
          if ($usepkc && $hash->{MODEL} eq 'MYSQL') {
              eval { $sth_ic = $dbh->prepare("INSERT IGNORE INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };	  
          } elsif ($usepkc && $hash->{MODEL} eq 'SQLITE') {
              eval { $sth_ic = $dbh->prepare("INSERT OR IGNORE INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          } elsif ($usepkc && $hash->{MODEL} eq 'POSTGRESQL') {
              eval { $sth_ic = $dbh->prepare("INSERT INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"); };
          } else {
              # ohne PK
              eval { $sth_ic = $dbh->prepare("INSERT INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          }
          if ($@) {
              return $@;
          }
          
          if ($usepkc && $hash->{MODEL} eq 'MYSQL') {
              $sth_uc = $dbh->prepare("REPLACE INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?)"); 
          } elsif ($usepkc && $hash->{MODEL} eq 'SQLITE') {  
              $sth_uc = $dbh->prepare("INSERT OR REPLACE INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?)");
          } elsif ($usepkc && $hash->{MODEL} eq 'POSTGRESQL') {  
              $sth_uc = $dbh->prepare("INSERT INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?) ON CONFLICT ($pkc) 
                                       DO UPDATE SET TIMESTAMP=EXCLUDED.TIMESTAMP, DEVICE=EXCLUDED.DEVICE, TYPE=EXCLUDED.TYPE, EVENT=EXCLUDED.EVENT, READING=EXCLUDED.READING, 
                                       VALUE=EXCLUDED.VALUE, UNIT=EXCLUDED.UNIT");
          } else {	  
              $sth_uc = $dbh->prepare("UPDATE $current SET TIMESTAMP=?, TYPE=?, EVENT=?, VALUE=?, UNIT=? WHERE (DEVICE=?) AND (READING=?)");
          }
          
          if($tl) {
              # Tracelevel setzen       
              $sth_uc->{TraceLevel} = "$tl|$tf";
              $sth_ic->{TraceLevel} = "$tl|$tf";
          }
      
          $sth_uc->bind_param_array(1, [@timestamp]);
          $sth_uc->bind_param_array(2, [@type]);
          $sth_uc->bind_param_array(3, [@event]);
          $sth_uc->bind_param_array(4, [@value]);
          $sth_uc->bind_param_array(5, [@unit]);
          $sth_uc->bind_param_array(6, [@device]);
          $sth_uc->bind_param_array(7, [@reading]);
      
          eval { $dbh->begin_work() if($useta && $dbh->{AutoCommit}); };   # Transaktion wenn gewünscht und autocommit ein
          if ($@) {
              Log3($name, 2, "DbLog $name -> Error start transaction for $current - $@");
          }
          eval {
              ($tuples, $rows) = $sth_uc->execute_array( { ArrayTupleStatus => \my @tuple_status } );
              my $nupd_cur = 0;
              for my $tuple (0..$#row_array) {
                  my $status = $tuple_status[$tuple];
                  $status = 0 if($status eq "0E0");
                  next if($status);         # $status ist "1" wenn update ok
                  Log3 $hash->{NAME}, 4, "DbLog $name -> Failed to update in $current, try to insert - TS: $timestamp[$tuple], Device: $device[$tuple], Reading: $reading[$tuple], Status = $status";
                  push(@timestamp_cur, "$timestamp[$tuple]"); 
                  push(@device_cur, "$device[$tuple]");   
                  push(@type_cur, "$type[$tuple]");  
                  push(@event_cur, "$event[$tuple]");  
                  push(@reading_cur, "$reading[$tuple]"); 
                  push(@value_cur, "$value[$tuple]"); 
                  push(@unit_cur, "$unit[$tuple]");
                  $nupd_cur++;
              }
              if(!$nupd_cur) {
                  Log3 $hash->{NAME}, 4, "DbLog $name -> $ceti of $ceti events updated in table $current".($usepkc?" using PK on columns $pkc":"");
              } else {
                  Log3 $hash->{NAME}, 4, "DbLog $name -> $nupd_cur of $ceti events not updated and try to insert into table $current".($usepkc?" using PK on columns $pkc":"");
                  $doins = 1;
              }
              
              if ($doins) {
                  # events die nicht in Tabelle current updated wurden, werden in current neu eingefügt
                  $sth_ic->bind_param_array(1, [@timestamp_cur]);
                  $sth_ic->bind_param_array(2, [@device_cur]);
                  $sth_ic->bind_param_array(3, [@type_cur]);
                  $sth_ic->bind_param_array(4, [@event_cur]);
                  $sth_ic->bind_param_array(5, [@reading_cur]);
                  $sth_ic->bind_param_array(6, [@value_cur]);
                  $sth_ic->bind_param_array(7, [@unit_cur]);
                  
                  ($tuples, $rows) = $sth_ic->execute_array( { ArrayTupleStatus => \my @tuple_status } );
                  my $nins_cur = 0;
                  for my $tuple (0..$#device_cur) {
                      my $status = $tuple_status[$tuple];
                      $status = 0 if($status eq "0E0");
                      next if($status);         # $status ist "1" wenn insert ok
                      Log3 $hash->{NAME}, 3, "DbLog $name -> Insert into $current rejected - TS: $timestamp[$tuple], Device: $device_cur[$tuple], Reading: $reading_cur[$tuple], Status = $status";
                      $nins_cur++;
                  }
                  if(!$nins_cur) {
                      Log3 $hash->{NAME}, 4, "DbLog $name -> ".($#device_cur+1)." of ".($#device_cur+1)." events inserted into table $current ".($usepkc?" using PK on columns $pkc":"");
                  } else {
                      Log3 $hash->{NAME}, 4, "DbLog $name -> ".($#device_cur+1-$nins_cur)." of ".($#device_cur+1)." events inserted into table $current".($usepkc?" using PK on columns $pkc":"");
                  }
              }
              eval {$dbh->commit() if(!$dbh->{AutoCommit});};    # issue Turning on AutoCommit failed
              if ($@) {
                  Log3($name, 2, "DbLog $name -> Error commit table $current - $@");
              } else {
                  if(!$dbh->{AutoCommit}) {
                      Log3($name, 4, "DbLog $name -> insert / update table $current committed");
                  } else {
                      Log3($name, 4, "DbLog $name -> insert / update table $current committed by autocommit");
                  }
              }
          };      
      }
      
  } else {
      #######################
      # Array-Insert
      #######################   
      
      $st = [gettimeofday];               # SQL-Startzeit    
      
      if (lc($DbLogType) =~ m(history)) {
          ########################################      
          # insert history mit/ohne primary key
          if ($usepkh && $hash->{MODEL} eq 'MYSQL') {
              eval { $sth_ih = $dbh->prepare("INSERT IGNORE INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          } elsif ($usepkh && $hash->{MODEL} eq 'SQLITE') {
              eval { $sth_ih = $dbh->prepare("INSERT OR IGNORE INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          } elsif ($usepkh && $hash->{MODEL} eq 'POSTGRESQL') {
              eval { $sth_ih = $dbh->prepare("INSERT INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"); };
          } else {
              # ohne PK
              eval { $sth_ih = $dbh->prepare("INSERT INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          }
          if ($@) {
              return $@;
          }

          if($tl) {
              # Tracelevel setzen       
              $sth_ih->{TraceLevel} = "$tl|$tf";
          }   
          
          $sth_ih->bind_param_array(1, [@timestamp]);
          $sth_ih->bind_param_array(2, [@device]);
          $sth_ih->bind_param_array(3, [@type]);
          $sth_ih->bind_param_array(4, [@event]);
          $sth_ih->bind_param_array(5, [@reading]);
          $sth_ih->bind_param_array(6, [@value]);
          $sth_ih->bind_param_array(7, [@unit]);     

          eval { $dbh->begin_work() if($useta && $dbh->{AutoCommit}); };   # Transaktion wenn gewünscht und autocommit ein
          if ($@) {
              Log3($name, 2, "DbLog $name -> Error start transaction for $history - $@");
          }
          eval {
              ($tuples, $rows) = $sth_ih->execute_array( { ArrayTupleStatus => \my @tuple_status } );
              my $nins_hist = 0;
              for my $tuple (0..$#row_array) {
                  my $status = $tuple_status[$tuple];
                  $status = 0 if($status eq "0E0");
                  next if($status);         # $status ist "1" wenn insert ok          
                  Log3 $hash->{NAME}, 3, "DbLog $name -> Insert into $history rejected".($usepkh?" (possible PK violation) ":" ")."- TS: $timestamp[$tuple], Device: $device[$tuple], Event: $event[$tuple]";
                  my $nlh = ($timestamp[$tuple]."|".$device[$tuple]."|".$type[$tuple]."|".$event[$tuple]."|".$reading[$tuple]."|".$value[$tuple]."|".$unit[$tuple]);
                  $nins_hist++;
              }
              if(!$nins_hist) {
                  Log3 $hash->{NAME}, 4, "DbLog $name -> $ceti of $ceti events inserted into table $history".($usepkh?" using PK on columns $pkh":"");
              } else {
                  if($usepkh) {
                      Log3 $hash->{NAME}, 3, "DbLog $name -> INFO - ".($ceti-$nins_hist)." of $ceti events inserted into table $history due to PK on columns $pkh";    			  
                  } else {
                      Log3 $hash->{NAME}, 2, "DbLog $name -> WARNING - only ".($ceti-$nins_hist)." of $ceti events inserted into table $history";    			  
                  } 			  
              }
              eval {$dbh->commit() if(!$dbh->{AutoCommit});};          # Data commit
              if ($@) {
                  Log3($name, 2, "DbLog $name -> Error commit $history - $@");
              } else {
                  if(!$dbh->{AutoCommit}) {
                      Log3($name, 4, "DbLog $name -> insert table $history committed");
                  } else {
                      Log3($name, 4, "DbLog $name -> insert table $history committed by autocommit");
                  }
              }
          };
          
          if ($@) {
              $errorh = $@;
              Log3 $hash->{NAME}, 2, "DbLog $name -> Error table $history - $errorh";
              eval {$dbh->rollback() if(!$dbh->{AutoCommit});};  # issue Turning on AutoCommit failed
              if ($@) {
                  Log3($name, 2, "DbLog $name -> Error rollback $history - $@");
              } else {
                  Log3($name, 4, "DbLog $name -> insert $history rolled back");
              }
          }          
      } 
      
      if (lc($DbLogType) =~ m(current)) {
          ########################################
          # insert current mit/ohne primary key      
          if ($usepkc && $hash->{MODEL} eq 'MYSQL') {
              eval { $sth_ic = $dbh->prepare("INSERT IGNORE INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };	  
          } elsif ($usepkc && $hash->{MODEL} eq 'SQLITE') {
              eval { $sth_ic = $dbh->prepare("INSERT OR IGNORE INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          } elsif ($usepkc && $hash->{MODEL} eq 'POSTGRESQL') {
              eval { $sth_ic = $dbh->prepare("INSERT INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"); };
          } else {
              # ohne PK
              eval { $sth_ic = $dbh->prepare("INSERT INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          }
          if ($@) {
              return $@;
          }
          
          if ($usepkc && $hash->{MODEL} eq 'MYSQL') {
              $sth_uc = $dbh->prepare("REPLACE INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?)"); 
          } elsif ($usepkc && $hash->{MODEL} eq 'SQLITE') {  
              $sth_uc = $dbh->prepare("INSERT OR REPLACE INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?)");
          } elsif ($usepkc && $hash->{MODEL} eq 'POSTGRESQL') {  
              $sth_uc = $dbh->prepare("INSERT INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?) ON CONFLICT ($pkc) 
                                       DO UPDATE SET TIMESTAMP=EXCLUDED.TIMESTAMP, DEVICE=EXCLUDED.DEVICE, TYPE=EXCLUDED.TYPE, EVENT=EXCLUDED.EVENT, READING=EXCLUDED.READING, 
                                       VALUE=EXCLUDED.VALUE, UNIT=EXCLUDED.UNIT");
          } else {	  
              $sth_uc = $dbh->prepare("UPDATE $current SET TIMESTAMP=?, TYPE=?, EVENT=?, VALUE=?, UNIT=? WHERE (DEVICE=?) AND (READING=?)");
          }
          
          if($tl) {
              # Tracelevel setzen       
              $sth_uc->{TraceLevel} = "$tl|$tf";
              $sth_ic->{TraceLevel} = "$tl|$tf";
          }
      
          $sth_uc->bind_param_array(1, [@timestamp]);
          $sth_uc->bind_param_array(2, [@type]);
          $sth_uc->bind_param_array(3, [@event]);
          $sth_uc->bind_param_array(4, [@value]);
          $sth_uc->bind_param_array(5, [@unit]);
          $sth_uc->bind_param_array(6, [@device]);
          $sth_uc->bind_param_array(7, [@reading]);
      
          eval { $dbh->begin_work() if($useta && $dbh->{AutoCommit}); };   # Transaktion wenn gewünscht und autocommit ein
          if ($@) {
              Log3($name, 2, "DbLog $name -> Error start transaction for $current - $@");
          }
          eval {
              ($tuples, $rows) = $sth_uc->execute_array( { ArrayTupleStatus => \my @tuple_status } );
              my $nupd_cur = 0;
              for my $tuple (0..$#row_array) {
                  my $status = $tuple_status[$tuple];
                  $status = 0 if($status eq "0E0");
                  next if($status);         # $status ist "1" wenn update ok
                  Log3 $hash->{NAME}, 4, "DbLog $name -> Failed to update in $current, try to insert - TS: $timestamp[$tuple], Device: $device[$tuple], Reading: $reading[$tuple], Status = $status";
                  push(@timestamp_cur, "$timestamp[$tuple]"); 
                  push(@device_cur, "$device[$tuple]");   
                  push(@type_cur, "$type[$tuple]");  
                  push(@event_cur, "$event[$tuple]");  
                  push(@reading_cur, "$reading[$tuple]"); 
                  push(@value_cur, "$value[$tuple]"); 
                  push(@unit_cur, "$unit[$tuple]");
                  $nupd_cur++;
              }
              if(!$nupd_cur) {
                  Log3 $hash->{NAME}, 4, "DbLog $name -> $ceti of $ceti events updated in table $current".($usepkc?" using PK on columns $pkc":"");
              } else {
                  Log3 $hash->{NAME}, 4, "DbLog $name -> $nupd_cur of $ceti events not updated and try to insert into table $current".($usepkc?" using PK on columns $pkc":"");
                  $doins = 1;
              }
              
              if ($doins) {
                  # events die nicht in Tabelle current updated wurden, werden in current neu eingefügt
                  $sth_ic->bind_param_array(1, [@timestamp_cur]);
                  $sth_ic->bind_param_array(2, [@device_cur]);
                  $sth_ic->bind_param_array(3, [@type_cur]);
                  $sth_ic->bind_param_array(4, [@event_cur]);
                  $sth_ic->bind_param_array(5, [@reading_cur]);
                  $sth_ic->bind_param_array(6, [@value_cur]);
                  $sth_ic->bind_param_array(7, [@unit_cur]);
                  
                  ($tuples, $rows) = $sth_ic->execute_array( { ArrayTupleStatus => \my @tuple_status } );
                  my $nins_cur = 0;
                  for my $tuple (0..$#device_cur) {
                      my $status = $tuple_status[$tuple];
                      $status = 0 if($status eq "0E0");
                      next if($status);         # $status ist "1" wenn insert ok
                      Log3 $hash->{NAME}, 3, "DbLog $name -> Insert into $current rejected - TS: $timestamp[$tuple], Device: $device_cur[$tuple], Reading: $reading_cur[$tuple], Status = $status";
                      $nins_cur++;
                  }
                  if(!$nins_cur) {
                      Log3 $hash->{NAME}, 4, "DbLog $name -> ".($#device_cur+1)." of ".($#device_cur+1)." events inserted into table $current ".($usepkc?" using PK on columns $pkc":"");
                  } else {
                      Log3 $hash->{NAME}, 4, "DbLog $name -> ".($#device_cur+1-$nins_cur)." of ".($#device_cur+1)." events inserted into table $current".($usepkc?" using PK on columns $pkc":"");
                  }
              }
              eval {$dbh->commit() if(!$dbh->{AutoCommit});};    # issue Turning on AutoCommit failed
              if ($@) {
                  Log3($name, 2, "DbLog $name -> Error commit table $current - $@");
              } else {
                  if(!$dbh->{AutoCommit}) {
                      Log3($name, 4, "DbLog $name -> insert / update table $current committed");
                  } else {
                      Log3($name, 4, "DbLog $name -> insert / update table $current committed by autocommit");
                  }
              }
          };      
      }
  }
  
  # SQL-Laufzeit ermitteln
  my $rt = tv_interval($st);
  
  if(AttrVal($name, "showproctime", 0)) {
      readingsBeginUpdate($hash);    
      readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt));
      readingsEndUpdate($hash, 0);
  }

  if ($errorh) {
      $error = $errorh;
  }
  if(!$tl) {
      # Trace ausschalten
      $dbh->{TraceLevel} = "0";  
      $sth_ih->{TraceLevel} = "0";        
  }
  
  $dbh->{RaiseError} = 0; 
  $dbh->{PrintError} = 1;
  $dbh->disconnect if ($nh);

return Encode::encode_utf8($error);
}

#################################################################################################
#
# MemCache auswerten und Schreibroutine asynchron und non-blocking aufrufen
#
#################################################################################################
sub DbLog_execmemcache ($) {
  my ($hash) = @_;
  my $name       = $hash->{NAME}; 
  my $syncival   = AttrVal($name, "syncInterval", 30);
  my $clim       = AttrVal($name, "cacheLimit", 500);
  my $async      = AttrVal($name, "asyncMode", undef);
  my $ce         = AttrVal($name, "cacheEvents", 0);
  my $timeout    = AttrVal($name, "timeout", 86400);
  my $DbLogType  = AttrVal($name, "DbLogType", "History");
  my $dbconn     = $hash->{dbconn};
  my $dbuser     = $hash->{dbuser};
  my $dbpassword = $attr{"sec$name"}{secret};
  my $dolog      = 1;
  my $error      = 0;  
  my (@row_array,$memcount,$dbh);
  
  RemoveInternalTimer($hash, "DbLog_execmemcache");
	
  if($init_done != 1) {
      InternalTimer(gettimeofday()+5, "DbLog_execmemcache", $hash, 0);
	  return;
  }
  
  # return wenn "reopen" mit Zeitangabe läuft, oder kein asynchroner Mode oder wenn disabled
  if(!$async || IsDisabled($name) || $hash->{HELPER}{REOPEN_RUNS}) {
	  return;
  }
    
  # tote PID's löschen
  if($hash->{HELPER}{".RUNNING_PID"} && $hash->{HELPER}{".RUNNING_PID"}{pid} =~ m/DEAD/) {
      delete $hash->{HELPER}{".RUNNING_PID"};
  }
  if($hash->{HELPER}{REDUCELOG_PID} && $hash->{HELPER}{REDUCELOG_PID}{pid} =~ m/DEAD/) {
      delete $hash->{HELPER}{REDUCELOG_PID};
  }
  if($hash->{HELPER}{DELDAYS_PID} && $hash->{HELPER}{DELDAYS_PID}{pid} =~ m/DEAD/) {
      delete $hash->{HELPER}{DELDAYS_PID};
  }
  
  # bei SQLite Sperrverwaltung Logging wenn andere schreibende Zugriffe laufen
  if($hash->{MODEL} eq "SQLITE") {
      if($hash->{HELPER}{DELDAYS_PID}) {
	      $error = "deleteOldDaysNbl is running - resync at NextSync";
		  $dolog = 0;
	  }
      if($hash->{HELPER}{REDUCELOG_PID}) {
	      $error = "reduceLogNbl is running - resync at NextSync";
		  $dolog = 0;
	  }
	  if($hash->{HELPER}{".RUNNING_PID"}) {
	      $error = "Commit already running - resync at NextSync";
		  $dolog = 0;
	  }
  }
  
  $memcount = $data{DbLog}{$name}{cache}{memcache}?scalar(keys %{$data{DbLog}{$name}{cache}{memcache}}):0;
  if($ce == 2) {
      readingsSingleUpdate($hash, "CacheUsage", $memcount, 1);
  } else {
      readingsSingleUpdate($hash, 'CacheUsage', $memcount, 0);
  }
	
  if($memcount && $dolog && !$hash->{HELPER}{".RUNNING_PID"}) {		
      Log3 $name, 4, "DbLog $name -> ################################################################";
      Log3 $name, 4, "DbLog $name -> ###      New database processing cycle - asynchronous        ###";
      Log3 $name, 4, "DbLog $name -> ################################################################";
	  Log3 $name, 4, "DbLog $name -> MemCache contains $memcount entries to process";
	  Log3 $name, 4, "DbLog $name -> DbLogType is: $DbLogType"; 
		  
	  foreach my $key (sort(keys %{$data{DbLog}{$name}{cache}{memcache}})) {
          Log3 $hash->{NAME}, 5, "DbLog $name -> MemCache contains: ".$data{DbLog}{$name}{cache}{memcache}{$key};
		  push(@row_array, delete($data{DbLog}{$name}{cache}{memcache}{$key})); 
	  }  
      undef $data{DbLog}{$name}{cache}{memcache};                                           # sicherheitshalber Memory freigeben: https://perlmaven.com/undef-on-perl-arrays-and-hashes, bzw. https://www.effectiveperlprogramming.com/2018/09/undef-a-scalar-to-release-its-memory/

	  my $rowlist = join('§', @row_array);
	  $rowlist = encode_base64($rowlist,"");
	  $hash->{HELPER}{".RUNNING_PID"} = BlockingCall (
	                                 "DbLog_PushAsync", 
	                                 "$name|$rowlist", 
			                         "DbLog_PushAsyncDone", 
							         $timeout, 
							         "DbLog_PushAsyncAborted", 
							         $hash );
      $hash->{HELPER}{".RUNNING_PID"}{loglevel} = 4;
      Log3 $hash->{NAME}, 5, "DbLog $name -> DbLog_PushAsync called with timeout: $timeout";
  } else {
      if($dolog && $hash->{HELPER}{".RUNNING_PID"}) {
	      $error = "Commit already running - resync at NextSync";
	  } else {
          CancelDelayedShutdown($name) if($hash->{HELPER}{SHUTDOWNSEQ});
          Log3 ($name, 2, "DbLog $name - no data for last database write cycle") if(delete $hash->{HELPER}{SHUTDOWNSEQ});
      }
  }
  
  my $nextsync = gettimeofday()+$syncival;
  my $nsdt     = FmtDateTime($nextsync);
	  
  if(AttrVal($name, "syncEvents", undef)) {
      readingsSingleUpdate($hash, "NextSync", $nsdt. " or if CacheUsage ".$clim." reached", 1); 
  } else {
      readingsSingleUpdate($hash, "NextSync", $nsdt. " or if CacheUsage ".$clim." reached", 0); 
  }
  
  my $state = $error?$error:$hash->{HELPER}{OLDSTATE};
  my $evt   = ($state eq $hash->{HELPER}{OLDSTATE})?0:1;
  readingsSingleUpdate($hash, "state", $state, $evt);
  $hash->{HELPER}{OLDSTATE} = $state;
  
  InternalTimer($nextsync, "DbLog_execmemcache", $hash, 0);

return;
}

#################################################################################################
#
# Schreibroutine Einfügen Werte in DB asynchron non-blocking
#
#################################################################################################
sub DbLog_PushAsync(@) {
  my ($string) = @_;
  my ($name,$rowlist) = split("\\|", $string);
  my $hash        = $defs{$name};
  my $dbconn      = $hash->{dbconn};
  my $dbuser      = $hash->{dbuser};
  my $dbpassword  = $attr{"sec$name"}{secret};
  my $DbLogType   = AttrVal($name, "DbLogType", "History");
  my $supk        = AttrVal($name, "noSupportPK", 0);
  my $tl          = AttrVal($name, "traceLevel", 0);
  my $tf          = AttrVal($name, "traceFlag", "SQL");
  my $bi          = AttrVal($name, "bulkInsert", 0);
  my $utf8        = defined($hash->{UTF8})?$hash->{UTF8}:0;
  my $history     = $hash->{HELPER}{TH};
  my $current     = $hash->{HELPER}{TC};
  my $errorh      = 0;
  my $error       = 0;
  my $doins       = 0;  # Hilfsvariable, wenn "1" sollen inserts in Tabelle current erfolgen (updates schlugen fehl) 
  my $dbh;
  my $rowlback    = 0;  # Eventliste für Rückgabe wenn Fehler
  
  Log3 ($name, 5, "DbLog $name -> Start DbLog_PushAsync");
  Log3 ($name, 5, "DbLog $name -> DbLogType is: $DbLogType");
  
  # Background-Startzeit
  my $bst = [gettimeofday];
  
  my ($useac,$useta) = DbLog_commitMode($hash);
  eval {
      if(!$useac) {
          $dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 0, mysql_enable_utf8 => $utf8 });
      } elsif($useac == 1) {
          $dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1, mysql_enable_utf8 => $utf8 });
      } else {
          # Server default
          $dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, mysql_enable_utf8 => $utf8 });
      }
  };
  if ($@) {
      $error = encode_base64($@,"");
      Log3 ($name, 2, "DbLog $name - Error: $@");
      Log3 ($name, 5, "DbLog $name -> DbLog_PushAsync finished");
      return "$name|$error|0|$rowlist";
  }
  
  if($tl) {
      # Tracelevel setzen  
      $dbh->{TraceLevel} = "$tl|$tf";       
  }  
  
  my $ac = ($dbh->{AutoCommit})?"ON":"OFF";
  my $tm = ($useta)?"ON":"OFF";
  Log3 $hash->{NAME}, 4, "DbLog $name -> AutoCommit mode: $ac, Transaction mode: $tm";
  Log3 $hash->{NAME}, 4, "DbLog $name -> Insert mode: ".($bi?"Bulk":"Array");
  
  # check ob PK verwendet wird, @usepkx?Anzahl der Felder im PK:0 wenn kein PK, $pkx?Namen der Felder:none wenn kein PK 
  my ($usepkh,$usepkc,$pkh,$pkc);
  if (!$supk) {
      ($usepkh,$usepkc,$pkh,$pkc) = DbLog_checkUsePK($hash,$dbh);
  } else {
      Log3 $hash->{NAME}, 5, "DbLog $name -> Primary Key usage suppressed by attribute noSupportPK";
  }
  
  my $rowldec   = decode_base64($rowlist);
  my @row_array = split('§', $rowldec);
  my $ceti      = $#row_array+1;
  
  my (@timestamp,@device,@type,@event,@reading,@value,@unit);
  my (@timestamp_cur,@device_cur,@type_cur,@event_cur,@reading_cur,@value_cur,@unit_cur);
  my ($st,$sth_ih,$sth_ic,$sth_uc,$sqlins);
  my ($tuples, $rows);
  
  no warnings 'uninitialized';
  foreach my $row (@row_array) {
      my @a = split("\\|",$row);       
      s/_ESC_/\|/g for @a;                    # escaped Pipe return to "|"
      push(@timestamp, "$a[0]"); 
      push(@device, "$a[1]");   
      push(@type, "$a[2]");  
      push(@event, "$a[3]");  
      push(@reading, "$a[4]"); 
      push(@value, "$a[5]"); 
      push(@unit, "$a[6]"); 
      Log3 $hash->{NAME}, 5, "DbLog $name -> processing event Timestamp: $a[0], Device: $a[1], Type: $a[2], Event: $a[3], Reading: $a[4], Value: $a[5], Unit: $a[6]";
  }	  
  use warnings; 
	
  if($bi) {
      #######################
      # Bulk-Insert
      #######################
      $st = [gettimeofday];               # SQL-Startzeit
      
      if (lc($DbLogType) =~ m(history)) { 
          ########################################      
          # insert history mit/ohne primary key
          if ($usepkh && $hash->{MODEL} eq 'MYSQL') {
              $sqlins = "INSERT IGNORE INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES ";
          } elsif ($usepkh && $hash->{MODEL} eq 'SQLITE') {
              $sqlins = "INSERT OR IGNORE INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES ";
          } elsif ($usepkh && $hash->{MODEL} eq 'POSTGRESQL') {
              $sqlins = "INSERT INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES ";
          } else {
              # ohne PK
              $sqlins = "INSERT INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES ";
          } 
          no warnings 'uninitialized';          
          foreach my $row (@row_array) {
              my @a = split("\\|",$row);       
              s/_ESC_/\|/g for @a;                    # escaped Pipe return to "|"
              Log3 $hash->{NAME}, 5, "DbLog $name -> processing event Timestamp: $a[0], Device: $a[1], Type: $a[2], Event: $a[3], Reading: $a[4], Value: $a[5], Unit: $a[6]";
              $a[3] =~ s/'/''/g;                      # escape ' with ''
              $a[5] =~ s/'/''/g;                      # escape ' with ''
              $a[6] =~ s/'/''/g;                      # escape ' with ''
              $sqlins .= "('$a[0]','$a[1]','$a[2]','$a[3]','$a[4]','$a[5]','$a[6]'),";
          }	  
          use warnings;
          
          chop($sqlins);
          
          if ($usepkh && $hash->{MODEL} eq 'POSTGRESQL') {
              $sqlins .= " ON CONFLICT DO NOTHING";
          }
          
          eval { $dbh->begin_work() if($useta && $dbh->{AutoCommit}); };   # Transaktion wenn gewünscht und autocommit ein
          if ($@) {
              Log3($name, 2, "DbLog $name -> Error start transaction for $history - $@");
          }
          eval { $sth_ih = $dbh->prepare($sqlins);
                 if($tl) {
                     # Tracelevel setzen       
                     $sth_ih->{TraceLevel} = "$tl|$tf";
                 }            
                 my $ins_hist = $sth_ih->execute();
                 $ins_hist = 0 if($ins_hist eq "0E0");
                 
                 if($ins_hist == $ceti) {
                     Log3 $hash->{NAME}, 4, "DbLog $name -> $ins_hist of $ceti events inserted into table $history".($usepkh?" using PK on columns $pkh":"");
                 } else {
                     if($usepkh) {
                         Log3 $hash->{NAME}, 3, "DbLog $name -> INFO - ".$ins_hist." of $ceti events inserted into table $history due to PK on columns $pkh";    			  
                     } else {
                         Log3 $hash->{NAME}, 2, "DbLog $name -> WARNING - only ".$ins_hist." of $ceti events inserted into table $history";    			  
                     }
                 }               
                 eval {$dbh->commit() if(!$dbh->{AutoCommit});};          # Data commit
                 if ($@) {
                     Log3($name, 2, "DbLog $name -> Error commit $history - $@");
                 } else {
                     if(!$dbh->{AutoCommit}) {
                         Log3($name, 4, "DbLog $name -> insert table $history committed");
                     } else {
                         Log3($name, 4, "DbLog $name -> insert table $history committed by autocommit");
                     }
                 }               
          };
           
          if ($@) {
              $errorh = $@;
              Log3 $hash->{NAME}, 2, "DbLog $name -> Error table $history - $errorh";
              $error = encode_base64($errorh,"");
              $rowlback = $rowlist if($useta);	# nicht gespeicherte Datensätze nur zurück geben wenn Transaktion ein
          }
      }   

      if (lc($DbLogType) =~ m(current)) {
          #################################################################
          # insert current mit/ohne primary key 
          # Array-Insert wird auch bei Bulk verwendet weil im Bulk-Mode 
          # die nicht upgedateten Sätze nicht identifiziert werden können          
          if ($usepkc && $hash->{MODEL} eq 'MYSQL') {
              eval { $sth_ic = $dbh->prepare("INSERT IGNORE INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };	  
          } elsif ($usepkc && $hash->{MODEL} eq 'SQLITE') {
              eval { $sth_ic = $dbh->prepare("INSERT OR IGNORE INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          } elsif ($usepkc && $hash->{MODEL} eq 'POSTGRESQL') {
              eval { $sth_ic = $dbh->prepare("INSERT INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"); };
          } else {
              # ohne PK
              eval { $sth_ic = $dbh->prepare("INSERT INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          }
          if ($@) {
              $error = encode_base64($@,"");
              Log3 ($name, 2, "DbLog $name - Error: $@");
              Log3 ($name, 5, "DbLog $name -> DbLog_PushAsync finished");
              $dbh->disconnect();
              return "$name|$error|0|";
          }
          
          if ($usepkc && $hash->{MODEL} eq 'MYSQL') {
              $sth_uc = $dbh->prepare("REPLACE INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?)"); 
          } elsif ($usepkc && $hash->{MODEL} eq 'SQLITE') {  
              $sth_uc = $dbh->prepare("INSERT OR REPLACE INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?)");
          } elsif ($usepkc && $hash->{MODEL} eq 'POSTGRESQL') {  
              $sth_uc = $dbh->prepare("INSERT INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?) ON CONFLICT ($pkc) 
                                       DO UPDATE SET TIMESTAMP=EXCLUDED.TIMESTAMP, DEVICE=EXCLUDED.DEVICE, TYPE=EXCLUDED.TYPE, EVENT=EXCLUDED.EVENT, READING=EXCLUDED.READING, 
                                       VALUE=EXCLUDED.VALUE, UNIT=EXCLUDED.UNIT");
          } else {	  
              $sth_uc = $dbh->prepare("UPDATE $current SET TIMESTAMP=?, TYPE=?, EVENT=?, VALUE=?, UNIT=? WHERE (DEVICE=?) AND (READING=?)");
          }
          
          if($tl) {
              # Tracelevel setzen       
              $sth_uc->{TraceLevel} = "$tl|$tf";
              $sth_ic->{TraceLevel} = "$tl|$tf";
          }
      
          $sth_uc->bind_param_array(1, [@timestamp]);
          $sth_uc->bind_param_array(2, [@type]);
          $sth_uc->bind_param_array(3, [@event]);
          $sth_uc->bind_param_array(4, [@value]);
          $sth_uc->bind_param_array(5, [@unit]);
          $sth_uc->bind_param_array(6, [@device]);
          $sth_uc->bind_param_array(7, [@reading]);
      
          eval { $dbh->begin_work() if($useta && $dbh->{AutoCommit}); };   # Transaktion wenn gewünscht und autocommit ein
          if ($@) {
              Log3($name, 2, "DbLog $name -> Error start transaction for $current - $@");
          }
          eval {
              ($tuples, $rows) = $sth_uc->execute_array( { ArrayTupleStatus => \my @tuple_status } );
              my $nupd_cur = 0;
              for my $tuple (0..$#row_array) {
                  my $status = $tuple_status[$tuple];
                  $status = 0 if($status eq "0E0");
                  next if($status);         # $status ist "1" wenn update ok
                  Log3 $hash->{NAME}, 4, "DbLog $name -> Failed to update in $current, try to insert - TS: $timestamp[$tuple], Device: $device[$tuple], Reading: $reading[$tuple], Status = $status";
                  push(@timestamp_cur, "$timestamp[$tuple]"); 
                  push(@device_cur, "$device[$tuple]");   
                  push(@type_cur, "$type[$tuple]");  
                  push(@event_cur, "$event[$tuple]");  
                  push(@reading_cur, "$reading[$tuple]"); 
                  push(@value_cur, "$value[$tuple]"); 
                  push(@unit_cur, "$unit[$tuple]");
                  $nupd_cur++;
              }
              if(!$nupd_cur) {
                  Log3 $hash->{NAME}, 4, "DbLog $name -> $ceti of $ceti events updated in table $current".($usepkc?" using PK on columns $pkc":"");
              } else {
                  Log3 $hash->{NAME}, 4, "DbLog $name -> $nupd_cur of $ceti events not updated and try to insert into table $current".($usepkc?" using PK on columns $pkc":"");
                  $doins = 1;
              }
              
              if ($doins) {
                  # events die nicht in Tabelle current updated wurden, werden in current neu eingefügt
                  $sth_ic->bind_param_array(1, [@timestamp_cur]);
                  $sth_ic->bind_param_array(2, [@device_cur]);
                  $sth_ic->bind_param_array(3, [@type_cur]);
                  $sth_ic->bind_param_array(4, [@event_cur]);
                  $sth_ic->bind_param_array(5, [@reading_cur]);
                  $sth_ic->bind_param_array(6, [@value_cur]);
                  $sth_ic->bind_param_array(7, [@unit_cur]);
                  
                  ($tuples, $rows) = $sth_ic->execute_array( { ArrayTupleStatus => \my @tuple_status } );
                  my $nins_cur = 0;
                  for my $tuple (0..$#device_cur) {
                      my $status = $tuple_status[$tuple];
                      $status = 0 if($status eq "0E0");
                      next if($status);         # $status ist "1" wenn insert ok
                      Log3 $hash->{NAME}, 3, "DbLog $name -> Insert into $current rejected - TS: $timestamp[$tuple], Device: $device_cur[$tuple], Reading: $reading_cur[$tuple], Status = $status";
                      $nins_cur++;
                  }
                  if(!$nins_cur) {
                      Log3 $hash->{NAME}, 4, "DbLog $name -> ".($#device_cur+1)." of ".($#device_cur+1)." events inserted into table $current ".($usepkc?" using PK on columns $pkc":"");
                  } else {
                      Log3 $hash->{NAME}, 4, "DbLog $name -> ".($#device_cur+1-$nins_cur)." of ".($#device_cur+1)." events inserted into table $current".($usepkc?" using PK on columns $pkc":"");
                  }
              }
              eval {$dbh->commit() if(!$dbh->{AutoCommit});};    # issue Turning on AutoCommit failed
              if ($@) {
                  Log3($name, 2, "DbLog $name -> Error commit table $current - $@");
              } else {
                  if(!$dbh->{AutoCommit}) {
                      Log3($name, 4, "DbLog $name -> insert / update table $current committed");
                  } else {
                      Log3($name, 4, "DbLog $name -> insert / update table $current committed by autocommit");
                  }
              }
          };      
      }
      
  } else {
      #######################
      # Array-Insert
      #######################   
      
      $st = [gettimeofday];               # SQL-Startzeit    
      
      if (lc($DbLogType) =~ m(history)) {
          ########################################      
          # insert history mit/ohne primary key
          if ($usepkh && $hash->{MODEL} eq 'MYSQL') {
              eval { $sth_ih = $dbh->prepare("INSERT IGNORE INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          } elsif ($usepkh && $hash->{MODEL} eq 'SQLITE') {
              eval { $sth_ih = $dbh->prepare("INSERT OR IGNORE INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          } elsif ($usepkh && $hash->{MODEL} eq 'POSTGRESQL') {
              eval { $sth_ih = $dbh->prepare("INSERT INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"); };
          } else {
              # ohne PK
              eval { $sth_ih = $dbh->prepare("INSERT INTO $history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          }
          if ($@) {
              # Eventliste zurückgeben wenn z.B. Disk I/O Error bei SQLITE
              $error = encode_base64($@,"");
              Log3 ($name, 2, "DbLog $name - Error: $@");
              Log3 ($name, 5, "DbLog $name -> DbLog_PushAsync finished");
              $dbh->disconnect();
              return "$name|$error|0|$rowlist";
          }

          if($tl) {
              # Tracelevel setzen       
              $sth_ih->{TraceLevel} = "$tl|$tf";
          }   
          
          $sth_ih->bind_param_array(1, [@timestamp]);
          $sth_ih->bind_param_array(2, [@device]);
          $sth_ih->bind_param_array(3, [@type]);
          $sth_ih->bind_param_array(4, [@event]);
          $sth_ih->bind_param_array(5, [@reading]);
          $sth_ih->bind_param_array(6, [@value]);
          $sth_ih->bind_param_array(7, [@unit]);     

          eval { $dbh->begin_work() if($useta && $dbh->{AutoCommit}); };   # Transaktion wenn gewünscht und autocommit ein
          if ($@) {
              Log3($name, 2, "DbLog $name -> Error start transaction for $history - $@");
          }
          eval {
              ($tuples, $rows) = $sth_ih->execute_array( { ArrayTupleStatus => \my @tuple_status } );
              my $nins_hist = 0;
              my @n2hist;
              for my $tuple (0..$#row_array) {
                  my $status = $tuple_status[$tuple];
                  $status = 0 if($status eq "0E0");
                  next if($status);         # $status ist "1" wenn insert ok          
                  Log3 $hash->{NAME}, 3, "DbLog $name -> Insert into $history rejected".($usepkh?" (possible PK violation) ":" ")."- TS: $timestamp[$tuple], Device: $device[$tuple], Event: $event[$tuple]";
                  my $nlh = ($timestamp[$tuple]."|".$device[$tuple]."|".$type[$tuple]."|".$event[$tuple]."|".$reading[$tuple]."|".$value[$tuple]."|".$unit[$tuple]);
                  push(@n2hist, "$nlh");
                  $nins_hist++;
              }
              if(!$nins_hist) {
                  Log3 $hash->{NAME}, 4, "DbLog $name -> $ceti of $ceti events inserted into table $history".($usepkh?" using PK on columns $pkh":"");
              } else {
                  if($usepkh) {
                      Log3 $hash->{NAME}, 3, "DbLog $name -> INFO - ".($ceti-$nins_hist)." of $ceti events inserted into table history due to PK on columns $pkh";    			  
                  } else {
                      Log3 $hash->{NAME}, 2, "DbLog $name -> WARNING - only ".($ceti-$nins_hist)." of $ceti events inserted into table $history";    			  
                  }
                  s/\|/_ESC_/g for @n2hist;       # escape Pipe "|"
                  $rowlist = join('§', @n2hist);
                  $rowlist = encode_base64($rowlist,""); 			  
              }
              eval {$dbh->commit() if(!$dbh->{AutoCommit});};          # Data commit
              if ($@) {
                  Log3($name, 2, "DbLog $name -> Error commit $history - $@");
              } else {
                  if(!$dbh->{AutoCommit}) {
                      Log3($name, 4, "DbLog $name -> insert table $history committed");
                  } else {
                      Log3($name, 4, "DbLog $name -> insert table $history committed by autocommit");
                  }
              }
          };
          
          if ($@) {
              $errorh = $@;
              Log3 $hash->{NAME}, 2, "DbLog $name -> Error table $history - $errorh";
              $error = encode_base64($errorh,"");
              $rowlback = $rowlist if($useta);	# nicht gespeicherte Datensätze nur zurück geben wenn Transaktion ein
          }           
      } 
      
      if (lc($DbLogType) =~ m(current)) {
          ########################################
          # insert current mit/ohne primary key      
          if ($usepkc && $hash->{MODEL} eq 'MYSQL') {
              eval { $sth_ic = $dbh->prepare("INSERT IGNORE INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };	  
          } elsif ($usepkc && $hash->{MODEL} eq 'SQLITE') {
              eval { $sth_ic = $dbh->prepare("INSERT OR IGNORE INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          } elsif ($usepkc && $hash->{MODEL} eq 'POSTGRESQL') {
              eval { $sth_ic = $dbh->prepare("INSERT INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"); };
          } else {
              # ohne PK
              eval { $sth_ic = $dbh->prepare("INSERT INTO $current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          }
          if ($@) {
              # Eventliste zurückgeben wenn z.B. Disk I/O error bei SQLITE
              $error = encode_base64($@,"");
              Log3 ($name, 2, "DbLog $name - Error: $@");
              Log3 ($name, 5, "DbLog $name -> DbLog_PushAsync finished");
              $dbh->disconnect();
              return "$name|$error|0|$rowlist";
          }
          
          if ($usepkc && $hash->{MODEL} eq 'MYSQL') {
              $sth_uc = $dbh->prepare("REPLACE INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?)"); 
          } elsif ($usepkc && $hash->{MODEL} eq 'SQLITE') {  
              $sth_uc = $dbh->prepare("INSERT OR REPLACE INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?)");
          } elsif ($usepkc && $hash->{MODEL} eq 'POSTGRESQL') {  
              $sth_uc = $dbh->prepare("INSERT INTO $current (TIMESTAMP, TYPE, EVENT, VALUE, UNIT, DEVICE, READING) VALUES (?,?,?,?,?,?,?) ON CONFLICT ($pkc) 
                                       DO UPDATE SET TIMESTAMP=EXCLUDED.TIMESTAMP, DEVICE=EXCLUDED.DEVICE, TYPE=EXCLUDED.TYPE, EVENT=EXCLUDED.EVENT, READING=EXCLUDED.READING, 
                                       VALUE=EXCLUDED.VALUE, UNIT=EXCLUDED.UNIT");
          } else {	  
              $sth_uc = $dbh->prepare("UPDATE $current SET TIMESTAMP=?, TYPE=?, EVENT=?, VALUE=?, UNIT=? WHERE (DEVICE=?) AND (READING=?)");
          }
          
          if($tl) {
              # Tracelevel setzen       
              $sth_uc->{TraceLevel} = "$tl|$tf";
              $sth_ic->{TraceLevel} = "$tl|$tf";
          }
      
          $sth_uc->bind_param_array(1, [@timestamp]);
          $sth_uc->bind_param_array(2, [@type]);
          $sth_uc->bind_param_array(3, [@event]);
          $sth_uc->bind_param_array(4, [@value]);
          $sth_uc->bind_param_array(5, [@unit]);
          $sth_uc->bind_param_array(6, [@device]);
          $sth_uc->bind_param_array(7, [@reading]);
      
          eval { $dbh->begin_work() if($useta && $dbh->{AutoCommit}); };   # Transaktion wenn gewünscht und autocommit ein
          if ($@) {
              Log3($name, 2, "DbLog $name -> Error start transaction for $current - $@");
          }
          eval {
              ($tuples, $rows) = $sth_uc->execute_array( { ArrayTupleStatus => \my @tuple_status } );
              my $nupd_cur = 0;
              for my $tuple (0..$#row_array) {
                  my $status = $tuple_status[$tuple];
                  $status = 0 if($status eq "0E0");
                  next if($status);         # $status ist "1" wenn update ok
                  Log3 $hash->{NAME}, 4, "DbLog $name -> Failed to update in $current, try to insert - TS: $timestamp[$tuple], Device: $device[$tuple], Reading: $reading[$tuple], Status = $status";
                  push(@timestamp_cur, "$timestamp[$tuple]"); 
                  push(@device_cur, "$device[$tuple]");   
                  push(@type_cur, "$type[$tuple]");  
                  push(@event_cur, "$event[$tuple]");  
                  push(@reading_cur, "$reading[$tuple]"); 
                  push(@value_cur, "$value[$tuple]"); 
                  push(@unit_cur, "$unit[$tuple]");
                  $nupd_cur++;
              }
              if(!$nupd_cur) {
                  Log3 $hash->{NAME}, 4, "DbLog $name -> $ceti of $ceti events updated in table $current".($usepkc?" using PK on columns $pkc":"");
              } else {
                  Log3 $hash->{NAME}, 4, "DbLog $name -> $nupd_cur of $ceti events not updated and try to insert into table $current".($usepkc?" using PK on columns $pkc":"");
                  $doins = 1;
              }
              
              if ($doins) {
                  # events die nicht in Tabelle current updated wurden, werden in current neu eingefügt
                  $sth_ic->bind_param_array(1, [@timestamp_cur]);
                  $sth_ic->bind_param_array(2, [@device_cur]);
                  $sth_ic->bind_param_array(3, [@type_cur]);
                  $sth_ic->bind_param_array(4, [@event_cur]);
                  $sth_ic->bind_param_array(5, [@reading_cur]);
                  $sth_ic->bind_param_array(6, [@value_cur]);
                  $sth_ic->bind_param_array(7, [@unit_cur]);
                  
                  ($tuples, $rows) = $sth_ic->execute_array( { ArrayTupleStatus => \my @tuple_status } );
                  my $nins_cur = 0;
                  for my $tuple (0..$#device_cur) {
                      my $status = $tuple_status[$tuple];
                      $status = 0 if($status eq "0E0");
                      next if($status);         # $status ist "1" wenn insert ok
                      Log3 $hash->{NAME}, 3, "DbLog $name -> Insert into $current rejected - TS: $timestamp[$tuple], Device: $device_cur[$tuple], Reading: $reading_cur[$tuple], Status = $status";
                      $nins_cur++;
                  }
                  if(!$nins_cur) {
                      Log3 $hash->{NAME}, 4, "DbLog $name -> ".($#device_cur+1)." of ".($#device_cur+1)." events inserted into table $current ".($usepkc?" using PK on columns $pkc":"");
                  } else {
                      Log3 $hash->{NAME}, 4, "DbLog $name -> ".($#device_cur+1-$nins_cur)." of ".($#device_cur+1)." events inserted into table $current".($usepkc?" using PK on columns $pkc":"");
                  }
              }
              eval {$dbh->commit() if(!$dbh->{AutoCommit});};    # issue Turning on AutoCommit failed
              if ($@) {
                  Log3($name, 2, "DbLog $name -> Error commit table $current - $@");
              } else {
                  if(!$dbh->{AutoCommit}) {
                      Log3($name, 4, "DbLog $name -> insert / update table $current committed");
                  } else {
                      Log3($name, 4, "DbLog $name -> insert / update table $current committed by autocommit");
                  }
              }
          };      
      }
  }
  
  $dbh->disconnect();
  
  # SQL-Laufzeit ermitteln
  my $rt = tv_interval($st);
  
  Log3 ($name, 5, "DbLog $name -> DbLog_PushAsync finished");

  # Background-Laufzeit ermitteln
  my $brt = tv_interval($bst);

  $rt = $rt.",".$brt;
 
return "$name|$error|$rt|$rowlback";
}

#############################################################################################
#         Auswertung non-blocking asynchron DbLog_PushAsync
#############################################################################################
sub DbLog_PushAsyncDone ($) {
 my ($string)   = @_;
 my @a          = split("\\|",$string);
 my $name       = $a[0];
 my $hash       = $defs{$name};
 my $error      = $a[1]?decode_base64($a[1]):0;
 my $bt         = $a[2];
 my $rowlist    = $a[3];
 my $asyncmode  = AttrVal($name, "asyncMode", undef);
 my $memcount;

 Log3 ($name, 5, "DbLog $name -> Start DbLog_PushAsyncDone");
  
 if($rowlist) {
     $rowlist = decode_base64($rowlist);
     my @row_array = split('§', $rowlist);
	 
	 #one Transaction
     eval { 
	   foreach my $row (@row_array) {
	       # Cache & CacheIndex für Events zum asynchronen Schreiben in DB
		   $data{DbLog}{$name}{cache}{index}++;
		   my $index = $data{DbLog}{$name}{cache}{index};
		   $data{DbLog}{$name}{cache}{memcache}{$index} = $row;
	   }
	   $memcount = scalar(keys %{$data{DbLog}{$name}{cache}{memcache}});
	 };                                                 
  }

  $memcount = $data{DbLog}{$name}{cache}{memcache}?scalar(keys %{$data{DbLog}{$name}{cache}{memcache}}):0;
  readingsSingleUpdate($hash, 'CacheUsage', $memcount, 0);
 
  if(AttrVal($name, "showproctime", undef) && $bt) {
      my ($rt,$brt) = split(",", $bt);
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt));     
      readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt));
      readingsEndUpdate($hash, 1);
  }
  
  my $state = $error?$error:(IsDisabled($name))?"disabled":"connected";
  my $evt   = ($state eq $hash->{HELPER}{OLDSTATE})?0:1;
  readingsSingleUpdate($hash, "state", $state, $evt);
  $hash->{HELPER}{OLDSTATE} = $state;
 
  if(!$asyncmode) {
      delete($defs{$name}{READINGS}{NextSync});
	  delete($defs{$name}{READINGS}{background_processing_time});
	  delete($defs{$name}{READINGS}{sql_processing_time});
	  delete($defs{$name}{READINGS}{CacheUsage});
  }
  delete $hash->{HELPER}{".RUNNING_PID"};
  delete $hash->{HELPER}{LASTLIMITRUNTIME} if(!$error);
  Log3 ($name, 5, "DbLog $name -> DbLog_PushAsyncDone finished"); 
  
  Log3 ($name, 2, "DbLog $name - Last database write cycle done") if(delete $hash->{HELPER}{SHUTDOWNSEQ});
  CancelDelayedShutdown($name);
  
return;
}
 
#############################################################################################
#           Abbruchroutine Timeout non-blocking asynchron DbLog_PushAsync
#############################################################################################
sub DbLog_PushAsyncAborted(@) {
  my ($hash,$cause) = @_;
  my $name = $hash->{NAME};
  $cause = $cause?$cause:"Timeout: process terminated";
  
  Log3 ($name, 2, "DbLog $name -> ".$hash->{HELPER}{".RUNNING_PID"}{fn}." ".$cause) if(!$hash->{HELPER}{SHUTDOWNSEQ});
  readingsSingleUpdate($hash,"state",$cause, 1);
  delete $hash->{HELPER}{".RUNNING_PID"};
  delete $hash->{HELPER}{LASTLIMITRUNTIME};
  
  Log3 ($name, 2, "DbLog $name - Last database write cycle done") if(delete $hash->{HELPER}{SHUTDOWNSEQ});
  CancelDelayedShutdown($name);
  
return;
}

################################################################
#
# zerlegt uebergebenes FHEM-Datum in die einzelnen Bestandteile
# und fuegt noch Defaultwerte ein
# uebergebenes SQL-Format: YYYY-MM-DD HH24:MI:SS
#
################################################################
sub DbLog_explode_datetime($%) {
  my ($t, %def) = @_;
  my %retv;
  
  my (@datetime, @date, @time);
  @datetime = split(" ", $t); #Datum und Zeit auftrennen
  @date = split("-", $datetime[0]);
  @time = split(":", $datetime[1]) if ($datetime[1]);
  
  if ($date[0]) {$retv{year}  = $date[0];} else {$retv{year}  = $def{year};}
  if ($date[1]) {$retv{month} = $date[1];} else {$retv{month} = $def{month};}
  if ($date[2]) {$retv{day}   = $date[2];} else {$retv{day}   = $def{day};}
  if ($time[0]) {$retv{hour}  = $time[0];} else {$retv{hour}  = $def{hour};}
  if ($time[1]) {$retv{minute}= $time[1];} else {$retv{minute}= $def{minute};}
  if ($time[2]) {$retv{second}= $time[2];} else {$retv{second}= $def{second};}

  $retv{datetime}=DbLog_implode_datetime($retv{year}, $retv{month}, $retv{day}, $retv{hour}, $retv{minute}, $retv{second});
  
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
sub DbLog_readCfg($){
  my ($hash)= @_;
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
  } elsif ($hash->{dbconn} =~ m/mysql:/i) {
    $hash->{MODEL}="MYSQL";
  } elsif ($hash->{dbconn} =~ m/oracle:/i) {
    $hash->{MODEL}="ORACLE";
  } elsif ($hash->{dbconn} =~ m/sqlite:/i) {
    $hash->{MODEL}="SQLITE";
  } else {
    $hash->{MODEL}="unknown";
    Log3 $hash->{NAME}, 1, "Unknown database model found in configuration file $configfilename.";
    Log3 $hash->{NAME}, 1, "Only MySQL/MariaDB, PostgreSQL, Oracle, SQLite are fully supported.";
	return "unknown database type";
  }
    
  if($hash->{MODEL} eq "MYSQL") {
	$hash->{UTF8} = defined($dbconfig{utf8})?$dbconfig{utf8}:0;
  }
	
return;
}

sub DbLog_ConnectPush($;$$) {
  # own $dbhp for synchronous logging and dblog_get 
  my ($hash,$get)= @_;
  my $name = $hash->{NAME};
  my $dbconn     = $hash->{dbconn};
  my $dbuser     = $hash->{dbuser};
  my $dbpassword = $attr{"sec$name"}{secret};
  my $utf8       = defined($hash->{UTF8})?$hash->{UTF8}:0;
  my ($dbhp,$state,$evt,$err);
  
  return 0 if(IsDisabled($name));
  
  if($init_done != 1) {
      InternalTimer(gettimeofday()+5, "DbLog_ConnectPush", $hash, 0);
	  return;
  }
  
  Log3 $hash->{NAME}, 3, "DbLog $name - Creating Push-Handle to database $dbconn with user $dbuser" if(!$get);

  my ($useac,$useta) = DbLog_commitMode($hash);
  eval {
      if(!$useac) {
          $dbhp = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 0, mysql_enable_utf8 => $utf8 });
      } elsif($useac == 1) {
          $dbhp = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1, mysql_enable_utf8 => $utf8 });
      } else {
          # Server default
          $dbhp = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, mysql_enable_utf8 => $utf8 });
      }
  };  
   
  if($@) {
      $err = $@;
	  Log3 $hash->{NAME}, 2, "DbLog $name - Error: $@";
  }
  
  if(!$dbhp) {
    RemoveInternalTimer($hash, "DbLog_ConnectPush");
    Log3 $hash->{NAME}, 4, "DbLog $name - Trying to connect to database";
    
    $state = $err?$err:(IsDisabled($name))?"disabled":"disconnected";
    $evt   = ($state eq $hash->{HELPER}{OLDSTATE})?0:1;
    readingsSingleUpdate($hash, "state", $state, $evt);
    $hash->{HELPER}{OLDSTATE} = $state;  
    
    InternalTimer(gettimeofday()+5, 'DbLog_ConnectPush', $hash, 0);
    Log3 $hash->{NAME}, 4, "DbLog $name - Waiting for database connection";
    return 0;
  }
  
  $dbhp->{RaiseError} = 0; 
  $dbhp->{PrintError} = 1;

  Log3 $hash->{NAME}, 3, "DbLog $name - Push-Handle to db $dbconn created" if(!$get);
  Log3 $hash->{NAME}, 3, "DbLog $name - UTF8 support enabled" if($utf8 && $hash->{MODEL} eq "MYSQL" && !$get);
  if(!$get) {
      $state = "connected";
	  $evt   = ($state eq $hash->{HELPER}{OLDSTATE})?0:1;
      readingsSingleUpdate($hash, "state", $state, $evt);
      $hash->{HELPER}{OLDSTATE} = $state;
  }

  $hash->{DBHP}= $dbhp;
  
  if ($hash->{MODEL} eq "SQLITE") {
    $dbhp->do("PRAGMA temp_store=MEMORY");
    $dbhp->do("PRAGMA synchronous=FULL");    # For maximum reliability and for robustness against database corruption, 
                                             # SQLite should always be run with its default synchronous setting of FULL.
                                             # https://sqlite.org/howtocorrupt.html
    $dbhp->do("PRAGMA journal_mode=WAL");
    $dbhp->do("PRAGMA cache_size=4000");
  }
 
  return 1;
}

sub DbLog_ConnectNewDBH($) {
  # new dbh for common use (except DbLog_Push and get-function)
  my ($hash)     = @_;
  my $name       = $hash->{NAME};
  my $dbconn     = $hash->{dbconn};
  my $dbuser     = $hash->{dbuser};
  my $dbpassword = $attr{"sec$name"}{secret};
  my $utf8       = defined($hash->{UTF8})?$hash->{UTF8}:0;
  my $dbh;
 
  my ($useac,$useta) = DbLog_commitMode($hash);
  eval {
      if(!$useac) {
          $dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 0, mysql_enable_utf8 => $utf8 });
      } elsif($useac == 1) {
          $dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1, mysql_enable_utf8 => $utf8 });
      } else {
          # Server default
          $dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, mysql_enable_utf8 => $utf8 });
      } 
  };
      
  if($@) {
    Log3($name, 2, "DbLog $name - $@");
    my $state = $@?$@:(IsDisabled($name))?"disabled":"disconnected";
    my $evt   = ($state eq $hash->{HELPER}{OLDSTATE})?0:1;
    readingsSingleUpdate($hash, "state", $state, $evt);
    $hash->{HELPER}{OLDSTATE} = $state;
  }
  
  if($dbh) {
      $dbh->{RaiseError} = 0; 
      $dbh->{PrintError} = 1;
      return $dbh;
  } else {
      return 0;
  }
}

##########################################################################
#
# Prozedur zum Ausfuehren von SQL-Statements durch externe Module
#
# param1: DbLog-hash
# param2: SQL-Statement
#
##########################################################################
sub DbLog_ExecSQL($$) {
  my ($hash,$sql)= @_;
  my $name = $hash->{NAME};
  my $dbh  = DbLog_ConnectNewDBH($hash);
  
  Log3($name, 4, "DbLog $name - Backdoor executing: $sql");
  
  return if(!$dbh);
  my $sth = DbLog_ExecSQL1($hash,$dbh,$sql);
  if(!$sth) {
    #retry
    $dbh->disconnect();
    $dbh = DbLog_ConnectNewDBH($hash);
    return if(!$dbh);
    
    Log3($name, 2, "DbLog $name - Backdoor retry: $sql");
    $sth = DbLog_ExecSQL1($hash,$dbh,$sql);
    if(!$sth) {
      Log3($name, 2, "DbLog $name - Backdoor retry failed");
	  $dbh->disconnect();
      return 0;
    }
    Log3($name, 2, "DbLog $name - Backdoor retry ok");
  }
  eval {$dbh->commit() if(!$dbh->{AutoCommit});};
  $dbh->disconnect();

return $sth;
}

sub DbLog_ExecSQL1($$$) {
  my ($hash,$dbh,$sql)= @_;
  my $name = $hash->{NAME};
  
  $dbh->{RaiseError} = 1; 
  $dbh->{PrintError} = 0;
  
  my $sth;
  eval { $sth = $dbh->do($sql); };
  if($@) {
    Log3($name, 2, "DbLog $name - ERROR: $@");
    return 0;
  }
  
return $sth;
}

################################################################
#
# GET Funktion
# wird zb. zur Generierung der Plots implizit aufgerufen
# infile : [-|current|history]
# outfile: [-|ALL|INT|WEBCHART]
#
################################################################
sub DbLog_Get($@) {
  my ($hash, @a) = @_;
  my $name    = $hash->{NAME};
  my $utf8    = defined($hash->{UTF8})?$hash->{UTF8}:0;
  my $history = $hash->{HELPER}{TH};
  my $current = $hash->{HELPER}{TC};
  my $dbh;
  
  return DbLog_dbReadings($hash,@a) if $a[1] =~ m/^Readings/;

  return "Usage: get $a[0] <in> <out> <from> <to> <column_spec>...\n".
     "  where column_spec is <device>:<reading>:<default>:<fn>\n" .
     "  see the #DbLog entries in the .gplot files\n" .
     "  <in> is not used, only for compatibility for FileLog, please use - \n" .
     "  <out> is a prefix, - means stdout\n"
     if(int(@a) < 5);
  
  shift @a;
  my $inf  = lc(shift @a);
  my $outf = lc(shift @a);               # Wert ALL: get all colums from table, including a header
                                         # Wert Array: get the columns as array of hashes
                                         # Wert INT: internally used by generating plots
  my $from = shift @a;
  my $to   = shift @a;                   # Now @a contains the list of column_specs
  my ($internal, @fld);

  if($inf eq "-") {
      $inf = "history";
  }

  if($outf eq "int" && $inf eq "current") {
      $inf = "history";
      Log3 $hash->{NAME}, 3, "Defining DbLog SVG-Plots with :CURRENT is deprecated. Please define DbLog SVG-Plots with :HISTORY instead of :CURRENT. (define <mySVG> SVG <DbLogDev>:<gplotfile>:HISTORY)";
  }

  if($outf eq "int") {
      $outf = "-";
      $internal = 1;
  } elsif($outf eq "array") {

  } elsif(lc($outf) eq "webchart") {
      # redirect the get request to the DbLog_chartQuery function
      return DbLog_chartQuery($hash, @_);
  }

  ########################
  # getter für SVG 
  ########################
  my @readings = ();
  my (%sqlspec, %from_datetime, %to_datetime);

  #uebergebenen Timestamp anpassen
  #moegliche Formate: YYYY | YYYY-MM | YYYY-MM-DD | YYYY-MM-DD_HH24
  $from =~ s/_/\ /g;
  $to   =~ s/_/\ /g;
  %from_datetime = DbLog_explode_datetime($from, DbLog_explode_datetime("2000-01-01 00:00:00", ()));
  %to_datetime   = DbLog_explode_datetime($to, DbLog_explode_datetime("2099-01-01 00:00:00", ()));
  $from = $from_datetime{datetime};
  $to = $to_datetime{datetime};
  
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
  my (@min, @max, @sum, @cnt, @lastv, @lastd, @mind, @maxd);
  my (%tstamp, %lasttstamp, $out_tstamp, $out_value, $minval, $maxval, $deltacalc);   # fuer delta-h/d Berechnung

  # extract the Device:Reading arguments into @readings array
  # Ausgangspunkt ist z.B.: KS300:temperature KS300:rain::delta-h KS300:rain::delta-d
  for(my $i = 0; $i < int(@a); $i++) {
      @fld = split(":", $a[$i], 5);
      $readings[$i][0] = $fld[0]; # Device
      $readings[$i][1] = $fld[1]; # Reading
      $readings[$i][2] = $fld[2]; # Default
      $readings[$i][3] = $fld[3]; # function
      $readings[$i][4] = $fld[4]; # regexp

      $readings[$i][1] = "%" if(!$readings[$i][1] || length($readings[$i][1])==0);   # falls Reading nicht gefuellt setze Joker
  }

  Log3 $name, 4, "DbLog $name -> ################################################################";
  Log3 $name, 4, "DbLog $name -> ###                  new get data for SVG                    ###";
  Log3 $name, 4, "DbLog $name -> ################################################################";
  Log3($name, 4, "DbLog $name -> main PID: $hash->{PID}, secondary PID: $$");
  
  my $nh = ($hash->{MODEL} ne 'SQLITE')?1:0;
  # $hash->{PID} != $$ -> create new connection for plotfork
  if ($nh || $hash->{PID} != $$) {                                # 17.04.2019 Forum: https://forum.fhem.de/index.php/topic,99719.0.html
      $dbh = DbLog_ConnectNewDBH($hash);
	  return "Can't connect to database." if(!$dbh);
  
  } else {
      $dbh = $hash->{DBHP};
      eval {
          if ( !$dbh || not $dbh->ping ) {
              # DB Session dead, try to reopen now !
              DbLog_ConnectPush($hash,1);
          }  
      };
      if ($@) {
          Log3($name, 1, "DbLog $name: DBLog_Push - DB Session dead! - $@");
	      return $@;
      } else {
          $dbh = $hash->{DBHP};
      }
  } 

  # vorbereiten der DB-Abfrage, DB-Modell-abhaengig
  if ($hash->{MODEL} eq "POSTGRESQL") {
      $sqlspec{get_timestamp}  = "TO_CHAR(TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')";
      $sqlspec{from_timestamp} = "TO_TIMESTAMP('$from', 'YYYY-MM-DD HH24:MI:SS')";
      $sqlspec{to_timestamp}   = "TO_TIMESTAMP('$to', 'YYYY-MM-DD HH24:MI:SS')";
      #$sqlspec{reading_clause} = "(DEVICE || '|' || READING)";
      $sqlspec{order_by_hour}  = "TO_CHAR(TIMESTAMP, 'YYYY-MM-DD HH24')";
      $sqlspec{max_value}      = "MAX(VALUE)";
      $sqlspec{day_before}     = "($sqlspec{from_timestamp} - INTERVAL '1 DAY')";
  } elsif ($hash->{MODEL} eq "ORACLE") {
      $sqlspec{get_timestamp}  = "TO_CHAR(TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')";
      $sqlspec{from_timestamp} = "TO_TIMESTAMP('$from', 'YYYY-MM-DD HH24:MI:SS')";
      $sqlspec{to_timestamp}   = "TO_TIMESTAMP('$to', 'YYYY-MM-DD HH24:MI:SS')";
      $sqlspec{order_by_hour}  = "TO_CHAR(TIMESTAMP, 'YYYY-MM-DD HH24')";
      $sqlspec{max_value}      = "MAX(VALUE)";
      $sqlspec{day_before}     = "DATE_SUB($sqlspec{from_timestamp},INTERVAL 1 DAY)";
  } elsif ($hash->{MODEL} eq "MYSQL") {
      $sqlspec{get_timestamp}  = "DATE_FORMAT(TIMESTAMP, '%Y-%m-%d %H:%i:%s')";
      $sqlspec{from_timestamp} = "STR_TO_DATE('$from', '%Y-%m-%d %H:%i:%s')";
      $sqlspec{to_timestamp}   = "STR_TO_DATE('$to', '%Y-%m-%d %H:%i:%s')";
      $sqlspec{order_by_hour}  = "DATE_FORMAT(TIMESTAMP, '%Y-%m-%d %H')";
      $sqlspec{max_value}      = "MAX(VALUE)";                                           # 12.04.2019 Forum: https://forum.fhem.de/index.php/topic,99280.0.html
      $sqlspec{day_before}     = "DATE_SUB($sqlspec{from_timestamp},INTERVAL 1 DAY)";
  } elsif ($hash->{MODEL} eq "SQLITE") {
      $sqlspec{get_timestamp}  = "TIMESTAMP";
      $sqlspec{from_timestamp} = "'$from'";
      $sqlspec{to_timestamp}   = "'$to'";
      $sqlspec{order_by_hour}  = "strftime('%Y-%m-%d %H', TIMESTAMP)";
      $sqlspec{max_value}      = "MAX(VALUE)";
      $sqlspec{day_before}     = "date($sqlspec{from_timestamp},'-1 day')";
  } else {
      $sqlspec{get_timestamp}  = "TIMESTAMP";
      $sqlspec{from_timestamp} = "'$from'";
      $sqlspec{to_timestamp}   = "'$to'";
      $sqlspec{order_by_hour}  = "strftime('%Y-%m-%d %H', TIMESTAMP)";
      $sqlspec{max_value}      = "MAX(VALUE)";
      $sqlspec{day_before}     = "date($sqlspec{from_timestamp},'-1 day')";
  }

  if($outf =~ m/(all|array)/) {
      $sqlspec{all}  = ",TYPE,EVENT,UNIT";
      $sqlspec{all_max}  = ",MAX(TYPE) AS TYPE,MAX(EVENT) AS EVENT,MAX(UNIT) AS UNIT";
  } else {
      $sqlspec{all}  = "";
      $sqlspec{all_max}  = "";
  }

  for(my $i=0; $i<int(@readings); $i++) {
      # ueber alle Readings
      # Variablen initialisieren
      $min[$i]   =  (~0 >> 1);
      $max[$i]   = -(~0 >> 1);
      $sum[$i]   = 0;
      $cnt[$i]   = 0;
      $lastv[$i] = 0;
      $lastd[$i] = "undef";
      $mind[$i]  = "undef";
      $maxd[$i]  = "undef";
      $minval    =  (~0 >> 1);
      $maxval    = -(~0 >> 1);
      $deltacalc = 0;

      if($readings[$i]->[3] && ($readings[$i]->[3] eq "delta-h" || $readings[$i]->[3] eq "delta-d")) {
          $deltacalc = 1;
      }

      my $stm;
      my $stm2;
      my $stmdelta;
      $stm =  "SELECT
                  MAX($sqlspec{get_timestamp}) AS TIMESTAMP,
                  MAX(DEVICE) AS DEVICE,
                  MAX(READING) AS READING,
                  $sqlspec{max_value}
                  $sqlspec{all_max} ";

      $stm .= "FROM $current " if($inf eq "current");
      $stm .= "FROM $history " if($inf eq "history");

      $stm .= "WHERE 1=1 ";
    
      $stm .= "AND DEVICE  = '".$readings[$i]->[0]."' "   if ($readings[$i]->[0] !~ m(\%));
      $stm .= "AND DEVICE LIKE '".$readings[$i]->[0]."' " if(($readings[$i]->[0] !~ m(^\%$)) && ($readings[$i]->[0] =~ m(\%)));

      $stm .= "AND READING = '".$readings[$i]->[1]."' "    if ($readings[$i]->[1] !~ m(\%));
      $stm .= "AND READING LIKE '".$readings[$i]->[1]."' " if(($readings[$i]->[1] !~ m(^%$)) && ($readings[$i]->[1] =~ m(\%)));

      $stmdelta = $stm;

      $stm .= "AND TIMESTAMP < $sqlspec{from_timestamp} ";
      $stm .= "AND TIMESTAMP > $sqlspec{day_before} ";

      $stm .= "UNION ALL ";

      $stm2 =  "SELECT
                  $sqlspec{get_timestamp},
                  DEVICE,
                  READING,
                  VALUE
                  $sqlspec{all} ";

      $stm2 .= "FROM $current " if($inf eq "current");
      $stm2 .= "FROM $history " if($inf eq "history");

      $stm2 .= "WHERE 1=1 ";

      $stm2 .= "AND DEVICE  = '".$readings[$i]->[0]."' "   if ($readings[$i]->[0] !~ m(\%));
      $stm2 .= "AND DEVICE LIKE '".$readings[$i]->[0]."' " if(($readings[$i]->[0] !~ m(^\%$)) && ($readings[$i]->[0] =~ m(\%)));

      $stm2 .= "AND READING = '".$readings[$i]->[1]."' "    if ($readings[$i]->[1] !~ m(\%));
      $stm2 .= "AND READING LIKE '".$readings[$i]->[1]."' " if(($readings[$i]->[1] !~ m(^%$)) && ($readings[$i]->[1] =~ m(\%)));

      $stm2 .= "AND TIMESTAMP >= $sqlspec{from_timestamp} ";
      $stm2 .= "AND TIMESTAMP <= $sqlspec{to_timestamp} ";           # 03.09.2018 : https://forum.fhem.de/index.php/topic,65860.msg815640.html#msg815640            
      $stm2 .= "ORDER BY TIMESTAMP";

      if($deltacalc) {
          $stmdelta .= "AND TIMESTAMP >= $sqlspec{from_timestamp} ";
          $stmdelta .= "AND TIMESTAMP <= $sqlspec{to_timestamp} ";     # 03.09.2018 : https://forum.fhem.de/index.php/topic,65860.msg815640.html#msg815640    

          $stmdelta .= "GROUP BY $sqlspec{order_by_hour} " if($deltacalc);
          $stmdelta .= "ORDER BY TIMESTAMP";
          $stm .= $stmdelta;
      } else {
          $stm = $stm2;
      }

      Log3 ($name, 4, "$name - Processing Statement: $stm");

      my $sth = $dbh->prepare($stm) || return "Cannot prepare statement $stm: $DBI::errstr";
      my $rc  = $sth->execute()     || return "Cannot execute statement $stm: $DBI::errstr";

      if($outf =~ m/(all|array)/) {
          $sth->bind_columns(undef, \$sql_timestamp, \$sql_device, \$sql_reading, \$sql_value, \$type, \$event, \$unit);
      } else {
          $sth->bind_columns(undef, \$sql_timestamp, \$sql_device, \$sql_reading, \$sql_value);
      }

      if ($outf =~ m/(all)/) {
          $retval .= "Timestamp: Device, Type, Event, Reading, Value, Unit\n";
          $retval .= "=====================================================\n";
      }
    
      ################################
      #        Select Auswertung      
      ################################    
      while($sth->fetch()) {
          no warnings 'uninitialized';
          my $ds = "TS: $sql_timestamp, DEV: $sql_device, RD: $sql_reading, VAL: $sql_value";
          Log3 ($name, 5, "$name - SQL-result -> $ds");
          use warnings;
          
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
              $sql_value = $val;
              $sql_timestamp = $ts;
              if($@) {Log3 $hash->{NAME}, 3, "DbLog: Error in inline function: <".$readings[$i]->[4].">, Error: $@";}
          }

          if($sql_timestamp lt $from && $deltacalc) {
              if(Scalar::Util::looks_like_number($sql_value)) {
                  # nur setzen wenn numerisch
                  $minval    = $sql_value if($sql_value < $minval);
                  $maxval    = $sql_value if($sql_value > $maxval);
                  $lastv[$i] = $sql_value;
              }
          
          } else {
              $writeout    = 0;
              $out_value   = "";
              $out_tstamp  = "";
              $retvaldummy = "";

              if($readings[$i]->[4]) {
                  $out_tstamp = $sql_timestamp;
                  $writeout   = 1 if(!$deltacalc);
              }

              ############ Auswerten des 4. Parameters: function ###################
              if($readings[$i]->[3] && $readings[$i]->[3] eq "int") {                  # nur den integerwert uebernehmen falls zb value=15°C
                  $out_value  = $1 if($sql_value =~ m/^(\d+).*/o);
                  $out_tstamp = $sql_timestamp;
                  $writeout   = 1;

              } elsif ($readings[$i]->[3] && $readings[$i]->[3] =~ m/^int(\d+).*/o) {  # Uebernehme den Dezimalwert mit den angegebenen Stellen an Nachkommastellen
                  $out_value  = $1 if($sql_value =~ m/^([-\.\d]+).*/o);
                  $out_tstamp = $sql_timestamp;
                  $writeout   = 1;

              } elsif ($readings[$i]->[3] && $readings[$i]->[3] eq "delta-ts" && lc($sql_value) !~ m(ignore)) {
                  # Berechung der vergangen Sekunden seit dem letzten Logeintrag
                  # zb. die Zeit zwischen on/off
                  my @a = split("[- :]", $sql_timestamp);
                  my $akt_ts = mktime($a[5],$a[4],$a[3],$a[2],$a[1]-1,$a[0]-1900,0,0,-1);
                  if($lastd[$i] ne "undef") {
                      @a = split("[- :]", $lastd[$i]);
                  }
                  my $last_ts = mktime($a[5],$a[4],$a[3],$a[2],$a[1]-1,$a[0]-1900,0,0,-1);
                  $out_tstamp = $sql_timestamp;
                  $out_value  = sprintf("%02d", $akt_ts - $last_ts);
              
                  if(lc($sql_value) =~ m(hide)) {
                      $writeout = 0;
                  } else {
                      $writeout = 1;
                  }

              } elsif ($readings[$i]->[3] && $readings[$i]->[3] eq "delta-h") {       # Berechnung eines Delta-Stundenwertes
                  %tstamp = DbLog_explode_datetime($sql_timestamp, ());
                  if($lastd[$i] eq "undef") {
                      %lasttstamp = DbLog_explode_datetime($sql_timestamp, ());
                      $lasttstamp{hour} = "00";
                  } else {
                      %lasttstamp = DbLog_explode_datetime($lastd[$i], ());
                  }
                  #    04                   01
                  #    06                   23
                  if("$tstamp{hour}" ne "$lasttstamp{hour}") {
                      # Aenderung der Stunde, Berechne Delta
                      # wenn die Stundendifferenz größer 1 ist muss ein Dummyeintrag erstellt werden
                      $retvaldummy = "";
                    
                      if(($tstamp{hour}-$lasttstamp{hour}) > 1) {
                          for (my $j=$lasttstamp{hour}+1; $j < $tstamp{hour}; $j++) {
                              $out_value  = "0";
                              $hour       = $j;
                              $hour       = '0'.$j if $j<10;
                              $cnt[$i]++;
                              $out_tstamp = DbLog_implode_datetime($tstamp{year}, $tstamp{month}, $tstamp{day}, $hour, "30", "00");
                              if ($outf =~ m/(all)/) {
                                  # Timestamp: Device, Type, Event, Reading, Value, Unit
                                  $retvaldummy .= sprintf("%s: %s, %s, %s, %s, %s, %s\n", $out_tstamp, $sql_device, $type, $event, $sql_reading, $out_value, $unit);
                  
                              } elsif ($outf =~ m/(array)/) {
                                  push(@ReturnArray, {"tstamp" => $out_tstamp, "device" => $sql_device, "type" => $type, "event" => $event, "reading" => $sql_reading, "value" => $out_value, "unit" => $unit});
                 
                              } else {
                                  $out_tstamp   =~ s/\ /_/g; #needed by generating plots
                                  $retvaldummy .= "$out_tstamp $out_value\n";
                              }
                          }
                      }
                    
                      if(($tstamp{hour}-$lasttstamp{hour}) < 0) {
                          for (my $j=0; $j < $tstamp{hour}; $j++) {
                              $out_value  = "0";
                              $hour       = $j;
                              $hour       = '0'.$j if $j<10;
                              $cnt[$i]++;
                              $out_tstamp = DbLog_implode_datetime($tstamp{year}, $tstamp{month}, $tstamp{day}, $hour, "30", "00");
                              if ($outf =~ m/(all)/) {
                                  # Timestamp: Device, Type, Event, Reading, Value, Unit
                                  $retvaldummy .= sprintf("%s: %s, %s, %s, %s, %s, %s\n", $out_tstamp, $sql_device, $type, $event, $sql_reading, $out_value, $unit);
                              } elsif ($outf =~ m/(array)/) {
                                  push(@ReturnArray, {"tstamp" => $out_tstamp, "device" => $sql_device, "type" => $type, "event" => $event, "reading" => $sql_reading, "value" => $out_value, "unit" => $unit});
                              } else {
                                  $out_tstamp =~ s/\ /_/g;                        # needed by generating plots
                                  $retvaldummy .= "$out_tstamp $out_value\n";
                              }
                          }
                      }
                    
                      $out_value = sprintf("%g", $maxval - $minval);
                      $sum[$i]  += $out_value;
                      $cnt[$i]++;
                      $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, $lasttstamp{hour}, "30", "00");
                      # $minval =  (~0 >> 1);
                      $minval = $maxval;
                      # $maxval = -(~0 >> 1);
                      $writeout = 1;
                       
                      Log3 ($name, 5, "$name - Output delta-h -> TS: $tstamp{hour}, LASTTS: $lasttstamp{hour}, OUTTS: $out_tstamp, OUTVAL: $out_value");
                  }
            
              } elsif ($readings[$i]->[3] && $readings[$i]->[3] eq "delta-d") {      # Berechnung eines Tageswertes
                  %tstamp = DbLog_explode_datetime($sql_timestamp, ());
                
                  if($lastd[$i] eq "undef") {
                      %lasttstamp = DbLog_explode_datetime($sql_timestamp, ());
                  } else {
                      %lasttstamp = DbLog_explode_datetime($lastd[$i], ());
                  }
              
                  if("$tstamp{day}" ne "$lasttstamp{day}") {
                      # Aenderung des Tages, Berechne Delta
                      $out_value = sprintf("%g", $maxval - $minval);
                      $sum[$i] += $out_value;
                      $cnt[$i]++;
                      $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, "12", "00", "00");
                      # $minval =  (~0 >> 1);
                      $minval = $maxval;
                      # $maxval = -(~0 >> 1);
                      $writeout = 1;
                      
                      Log3 ($name, 5, "$name - Output delta-d -> TS: $tstamp{day}, LASTTS: $lasttstamp{day}, OUTTS: $out_tstamp, OUTVAL: $out_value");
                  }
            
              } else {
                  $out_value  = $sql_value;
                  $out_tstamp = $sql_timestamp;
                  $writeout   = 1;
              }

              # Wenn Attr SuppressUndef gesetzt ist, dann ausfiltern aller undef-Werte
              $writeout = 0 if (!defined($sql_value) && AttrVal($hash->{NAME}, "suppressUndef", 0));
     
              ###################### Ausgabe ###########################
              if($writeout) {
                  if ($outf =~ m/(all)/) {
                      # Timestamp: Device, Type, Event, Reading, Value, Unit
                      $retval .= sprintf("%s: %s, %s, %s, %s, %s, %s\n", $out_tstamp, $sql_device, $type, $event, $sql_reading, $out_value, $unit);
                      $retval .= $retvaldummy;
                
                  } elsif ($outf =~ m/(array)/) {
                      push(@ReturnArray, {"tstamp" => $out_tstamp, "device" => $sql_device, "type" => $type, "event" => $event, "reading" => $sql_reading, "value" => $out_value, "unit" => $unit});
                  
                  } else {                                                       # generating plots
                      $out_tstamp =~ s/\ /_/g;                                   # needed by generating plots
                      $retval .= "$out_tstamp $out_value\n";
                      $retval .= $retvaldummy;
                  }
              }  

              if(Scalar::Util::looks_like_number($sql_value)) {
                  # nur setzen wenn numerisch
                  if($deltacalc) {
                      if(Scalar::Util::looks_like_number($out_value)) {
                          if($out_value < $min[$i]) {
                              $min[$i]  = $out_value;
                              $mind[$i] = $out_tstamp;
                          }
                          if($out_value > $max[$i]) {
                              $max[$i]  = $out_value;
                              $maxd[$i] = $out_tstamp;
                          }
                      }
                      $maxval = $sql_value;
              
                  } else {
                      if($sql_value < $min[$i]) {
                          $min[$i] = $sql_value;
                          $mind[$i] = $sql_timestamp;
                      }
                      if($sql_value > $max[$i]) {
                          $max[$i] = $sql_value;
                          $maxd[$i] = $sql_timestamp;
                      }
                      $sum[$i] += $sql_value;
                      $minval = $sql_value if($sql_value < $minval);
                      $maxval = $sql_value if($sql_value > $maxval);
                  }
            
              } else {
                  $min[$i] = 0;
                  $max[$i] = 0;
                  $sum[$i] = 0;
                  $minval  = 0;
                  $maxval  = 0;
              }
            
              if(!$deltacalc) {
                  $cnt[$i]++;
                  $lastv[$i] = $sql_value;
              } else {
                  $lastv[$i] = $out_value if($out_value);
              }
              $lastd[$i] = $sql_timestamp;
          }
      }                                                                   # while fetchrow Ende 

      ######## den letzten Abschlusssatz rausschreiben ##########
      if($readings[$i]->[3] && ($readings[$i]->[3] eq "delta-h" || $readings[$i]->[3] eq "delta-d")) {
          if($lastd[$i] eq "undef") {
              $out_value  = "0";
              $out_tstamp = DbLog_implode_datetime($from_datetime{year}, $from_datetime{month}, $from_datetime{day}, $from_datetime{hour}, "30", "00") if($readings[$i]->[3] eq "delta-h");
              $out_tstamp = DbLog_implode_datetime($from_datetime{year}, $from_datetime{month}, $from_datetime{day}, "12", "00", "00") if($readings[$i]->[3] eq "delta-d");
          } else {
              %lasttstamp = DbLog_explode_datetime($lastd[$i], ());
              $out_value = sprintf("%g", $maxval - $minval);
              $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, $lasttstamp{hour}, "30", "00") if($readings[$i]->[3] eq "delta-h");
              $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, "12", "00", "00") if($readings[$i]->[3] eq "delta-d");
          }  
          $sum[$i] += $out_value;
          $cnt[$i]++;
          if($outf =~ m/(all)/) {
              $retval .= sprintf("%s: %s %s %s %s %s %s\n", $out_tstamp, $sql_device, $type, $event, $sql_reading, $out_value, $unit);
      
          } elsif ($outf =~ m/(array)/) {
              push(@ReturnArray, {"tstamp" => $out_tstamp, "device" => $sql_device, "type" => $type, "event" => $event, "reading" => $sql_reading, "value" => $out_value, "unit" => $unit});
          
          } else {
             $out_tstamp =~ s/\ /_/g; #needed by generating plots
             $retval .= "$out_tstamp $out_value\n";
          }
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
  for(my $j=0; $j<int(@readings); $j++) {
      my $k = $j+1;
      $data{"min$k"}      = $min[$j];
      $data{"max$k"}      = $max[$j];
      $data{"avg$k"}      = $cnt[$j] ? sprintf("%0.2f", $sum[$j]/$cnt[$j]) : 0;
      $data{"sum$k"}      = $sum[$j];
      $data{"cnt$k"}      = $cnt[$j];
      $data{"currval$k"}  = $lastv[$j];
      $data{"currdate$k"} = $lastd[$j];
      $data{"mindate$k"}  = $mind[$j];
      $data{"maxdate$k"}  = $maxd[$j];
  }

  # cleanup (plotfork) connection
  # $dbh->disconnect() if( $hash->{PID} != $$ );
  
  $dbh->disconnect() if($nh || $hash->{PID} != $$);

  if($internal) {
      $internal_data = \$retval;
      return undef;

  } elsif($outf =~ m/(array)/) {
      return @ReturnArray;
  
  } else {
      $retval = Encode::encode_utf8($retval) if($utf8);
      # Log3 $name, 5, "DbLog $name -> Result of get:\n$retval";
      return $retval;
  }
}

##########################################################################
#
#        Konfigurationscheck DbLog <-> Datenbank
#
##########################################################################
sub DbLog_configcheck($) {
  my ($hash)= @_;
  my $name = $hash->{NAME};
  my $dbmodel = $hash->{MODEL};
  my $dbconn  = $hash->{dbconn};
  my $dbname  = (split(/;|=/, $dbconn))[1];
  my $history = $hash->{HELPER}{TH};
  my $current = $hash->{HELPER}{TC};
  my ($check, $rec,%dbconfig);
  
  ### Version check
  ####################################################################### 
  my $pv      = sprintf("%vd",$^V);                                              # Perl Version
  my $dbi     = $DBI::VERSION;                                                   # DBI Version
  my %drivers = DBI->installed_drivers();
  my $dv      = "";
  if($dbmodel =~ /MYSQL/i) {
      for (keys %drivers) {
          $dv = $_ if($_ =~ /mysql|mariadb/);
      }
  }
  my $dbd = ($dbmodel =~ /POSTGRESQL/i)?"Pg: ".$DBD::Pg::VERSION:                # DBD Version
            ($dbmodel =~ /MYSQL/i && $dv)?"$dv: ".$DBD::mysql::VERSION:
            ($dbmodel =~ /SQLITE/i)?"SQLite: ".$DBD::SQLite::VERSION:"Undefined";
            
  my ($errcm,$supd,$uptb) = DbLog_checkModVer($name);                            # DbLog Version
  
  $check  = "<html>";
  $check .= "<u><b>Result of version check</u></b><br><br>";
  $check .= "Used Perl version: $pv <br>";
  $check .= "Used DBI (Database independent interface) version: $dbi <br>";
  $check .= "Used DBD (Database driver) version $dbd <br>";
  if($errcm) {
      $check .= "<b>Recommendation:</b> ERROR - $errcm <br><br>";
  }
  if($supd) {
      $check .= "Used DbLog version: $hash->{HELPER}{VERSION}.<br>$uptb <br>";
	  $check .= "<b>Recommendation:</b> You should update FHEM to get the freshest DbLog version ! <br><br>";
  } else {
      $check .= "Used DbLog version: $hash->{HELPER}{VERSION}.<br>$uptb <br>";
	  $check .= "<b>Recommendation:</b> No update of DbLog is needed. <br><br>";  
  }
  
  ### Configuration read check
  #######################################################################
  $check .= "<u><b>Result of configuration read check</u></b><br><br>";
  my $st  = configDBUsed()?"configDB (don't forget upload configuration file if changed. Use \"configdb filelist\" and look for your configuration file.)":"file";
  $check .= "Connection parameter store type: $st <br>";
  my ($err, @config) = FileRead($hash->{CONFIGURATION});
  if (!$err) {
      eval join("\n", @config);
      $rec  = "parameter: ";
      $rec .= "Connection -> could not read, " if (!defined $dbconfig{connection});
      $rec .= "Connection -> ".$dbconfig{connection}.", " if (defined $dbconfig{connection});
      $rec .= "User -> could not read, " if (!defined $dbconfig{user});
      $rec .= "User -> ".$dbconfig{user}.", " if (defined $dbconfig{user});
      $rec .= "Password -> could not read " if (!defined $dbconfig{password});
      $rec .= "Password -> read o.k. " if (defined $dbconfig{password});
  } else {
      $rec = $err;
  }
  $check .= "Connection $rec <br><br>";
  
  ### Connection und Encoding check
  #######################################################################
  my (@ce,@se);
  my ($chutf8mod,$chutf8dat);
  if($dbmodel =~ /MYSQL/) {
      @ce = DbLog_sqlget($hash,"SHOW VARIABLES LIKE 'character_set_connection'");
	  $chutf8mod = @ce?uc($ce[1]):"no result";
	  @se = DbLog_sqlget($hash,"SHOW VARIABLES LIKE 'character_set_database'");
      $chutf8dat = @se?uc($se[1]):"no result";
	  if($chutf8mod eq $chutf8dat) {
          $rec = "settings o.k.";
      } else {
          $rec = "Both encodings should be identical. You can adjust the usage of UTF8 connection by setting the UTF8 parameter in file '$hash->{CONFIGURATION}' to the right value. ";
      }
  }
  if($dbmodel =~ /POSTGRESQL/) {
      @ce = DbLog_sqlget($hash,"SHOW CLIENT_ENCODING");
	  $chutf8mod = @ce?uc($ce[0]):"no result";
	  @se = DbLog_sqlget($hash,"select character_set_name from information_schema.character_sets");
      $chutf8dat = @se?uc($se[0]):"no result";
	  if($chutf8mod eq $chutf8dat) {
          $rec = "settings o.k.";
      } else {
          $rec = "This is only an information. PostgreSQL supports automatic character set conversion between server and client for certain character set combinations. The conversion information is stored in the pg_conversion system catalog. PostgreSQL comes with some predefined conversions.";
      }
  }  
  if($dbmodel =~ /SQLITE/) {
      @ce = DbLog_sqlget($hash,"PRAGMA encoding");
	  $chutf8dat = @ce?uc($ce[0]):"no result";
	  @se = DbLog_sqlget($hash,"PRAGMA table_info($history)");
      $rec = "This is only an information about text encoding used by the main database.";
  }  
  
  $check .= "<u><b>Result of connection check</u></b><br><br>";
  
  if(@ce && @se) {
      $check .= "Connection to database $dbname successfully done. <br>";
      $check .= "<b>Recommendation:</b> settings o.k. <br><br>";
  }
  
  if(!@ce || !@se) {
      $check .= "Connection to database was not successful. <br>";
      $check .= "<b>Recommendation:</b> Plese check logfile for further information. <br><br>";
	  $check .= "</html>";
      return $check;
  }
  $check .= "<u><b>Result of encoding check</u></b><br><br>";
  $check .= "Encoding used by Client (connection): $chutf8mod <br>" if($dbmodel !~ /SQLITE/);
  $check .= "Encoding used by DB $dbname: $chutf8dat <br>";
  $check .= "<b>Recommendation:</b> $rec <br><br>";
        
  ### Check Betriebsmodus
  #######################################################################
  my $mode = $hash->{MODE};
  my $bi   = AttrVal($name, "bulkInsert", 0);
  my $sfx = AttrVal("global", "language", "EN");
  $sfx = ($sfx eq "EN" ? "" : "_$sfx");
  
  $check .= "<u><b>Result of logmode check</u></b><br><br>";
  $check .= "Logmode of DbLog-device $name is: $mode <br>";
  if($mode =~ /asynchronous/) {
      my $max = AttrVal("global", "blockingCallMax", 0);
      if(!$max || $max >= 6) {
	      $rec = "settings o.k.";
	  } else {
	      $rec = "WARNING - you are running asynchronous mode that is recommended, but the value of global device attribute \"blockingCallMax\" is set quite small. <br>";
	      $rec .= "This may cause problems in operation. It is recommended to <b>increase</b> the <b>global blockingCallMax</b> attribute."; 
	  } 
  } else {
      $rec  = "Switch $name to the asynchronous logmode by setting the 'asyncMode' attribute. The advantage of this mode is to log events non-blocking. <br>";
	  $rec .= "There are attributes 'syncInterval' and 'cacheLimit' relevant for this working mode. <br>";
	  $rec .= "Please refer to commandref for further information about these attributes.";
  }
  $check .= "<b>Recommendation:</b> $rec <br><br>";

  $check .= "<u><b>Result of insert mode check</u></b><br><br>";
  if(!$bi) {
      $bi     = "Array";
      $check .= "Insert mode of DbLog-device $name is: $bi <br>";
      $rec    = "Setting attribute \"bulkInsert\" to \"1\" may result a higher write performance in most cases. ";
      $rec   .= "Feel free to try this mode.";
  } else {
      $bi     = "Bulk";
      $check .= "Insert mode of DbLog-device $name is: $bi <br>"; 
      $rec    = "settings o.k.";   
  }  
  $check .= "<b>Recommendation:</b> $rec <br><br>";
  
  ### Check Plot Erstellungsmodus
  #######################################################################
      $check .= "<u><b>Result of plot generation method check</u></b><br><br>";
	  my @webdvs = devspec2array("TYPE=FHEMWEB:FILTER=STATE=Initialized");
	  my $forks = 1;
	  my $wall;
      foreach (@webdvs) {
	      my $web = $_;
		  $wall  .= $web.": plotfork=".AttrVal($web,"plotfork",0)."<br>";
		  $forks  = 0 if(!AttrVal($web,"plotfork",0));
	  }
      if(!$forks) {
	      $check .= "WARNING - at least one of your FHEMWEB devices have attribute \"plotfork = 1\" not set. This may cause blocking situations when creating plots. <br>";
		  $check .= $wall;
		  $rec    = "You should set attribute \"plotfork = 1\" in relevant devices";
	  } else {
		  $check .= $wall;
	      $rec = "settings o.k.";
	  }	         
	  $check .= "<b>Recommendation:</b> $rec <br><br>"; 
  
  ### Check Spaltenbreite history
  #######################################################################
  my (@sr_dev,@sr_typ,@sr_evt,@sr_rdg,@sr_val,@sr_unt);
  my ($cdat_dev,$cdat_typ,$cdat_evt,$cdat_rdg,$cdat_val,$cdat_unt);
  my ($cmod_dev,$cmod_typ,$cmod_evt,$cmod_rdg,$cmod_val,$cmod_unt);
  	  
  if($dbmodel =~ /MYSQL/) {
      @sr_dev = DbLog_sqlget($hash,"SHOW FIELDS FROM $history where FIELD='DEVICE'");
	  @sr_typ = DbLog_sqlget($hash,"SHOW FIELDS FROM $history where FIELD='TYPE'");
	  @sr_evt = DbLog_sqlget($hash,"SHOW FIELDS FROM $history where FIELD='EVENT'");
	  @sr_rdg = DbLog_sqlget($hash,"SHOW FIELDS FROM $history where FIELD='READING'");
	  @sr_val = DbLog_sqlget($hash,"SHOW FIELDS FROM $history where FIELD='VALUE'");
	  @sr_unt = DbLog_sqlget($hash,"SHOW FIELDS FROM $history where FIELD='UNIT'");
  }
  if($dbmodel =~ /POSTGRESQL/) {
      my $sch = AttrVal($name, "dbSchema", "");
      my $h   = "history";
      if($sch) {
          @sr_dev = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and table_schema='$sch' and column_name='device'");
          @sr_typ = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and table_schema='$sch' and column_name='type'");
          @sr_evt = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and table_schema='$sch' and column_name='event'");
          @sr_rdg = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and table_schema='$sch' and column_name='reading'");
          @sr_val = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and table_schema='$sch' and column_name='value'");
          @sr_unt = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and table_schema='$sch' and column_name='unit'");
      } else {
          @sr_dev = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and column_name='device'");
          @sr_typ = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and column_name='type'");
          @sr_evt = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and column_name='event'");
          @sr_rdg = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and column_name='reading'");
          @sr_val = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and column_name='value'");
          @sr_unt = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$h' and column_name='unit'");
      
      }
  }
  if($dbmodel =~ /SQLITE/) {
      my $dev = (DbLog_sqlget($hash,"SELECT sql FROM sqlite_master WHERE name = '$history'"))[0];
	  $cdat_dev = $dev?$dev:"no result";
	  $cdat_typ = $cdat_evt = $cdat_rdg = $cdat_val = $cdat_unt = $cdat_dev;
	  $cdat_dev =~ s/.*DEVICE.varchar\(([\d]*)\).*/$1/e;
	  $cdat_typ =~ s/.*TYPE.varchar\(([\d]*)\).*/$1/e;
	  $cdat_evt =~ s/.*EVENT.varchar\(([\d]*)\).*/$1/e;
	  $cdat_rdg =~ s/.*READING.varchar\(([\d]*)\).*/$1/e;
	  $cdat_val =~ s/.*VALUE.varchar\(([\d]*)\).*/$1/e;
	  $cdat_unt =~ s/.*UNIT.varchar\(([\d]*)\).*/$1/e;
  }
  if ($dbmodel !~ /SQLITE/)  {  
      $cdat_dev = @sr_dev?($sr_dev[1]):"no result";
      $cdat_dev =~ tr/varchar\(|\)//d if($cdat_dev ne "no result");  
      $cdat_typ = @sr_typ?($sr_typ[1]):"no result";
      $cdat_typ =~ tr/varchar\(|\)//d if($cdat_typ ne "no result");
      $cdat_evt = @sr_evt?($sr_evt[1]):"no result";
      $cdat_evt =~ tr/varchar\(|\)//d if($cdat_evt ne "no result");
      $cdat_rdg = @sr_rdg?($sr_rdg[1]):"no result";
      $cdat_rdg =~ tr/varchar\(|\)//d if($cdat_rdg ne "no result");
      $cdat_val = @sr_val?($sr_val[1]):"no result";
      $cdat_val =~ tr/varchar\(|\)//d if($cdat_val ne "no result");
      $cdat_unt = @sr_unt?($sr_unt[1]):"no result";
      $cdat_unt =~ tr/varchar\(|\)//d if($cdat_unt ne "no result");
  }
  $cmod_dev = $hash->{HELPER}{DEVICECOL};
  $cmod_typ = $hash->{HELPER}{TYPECOL};
  $cmod_evt = $hash->{HELPER}{EVENTCOL};
  $cmod_rdg = $hash->{HELPER}{READINGCOL};
  $cmod_val = $hash->{HELPER}{VALUECOL};
  $cmod_unt = $hash->{HELPER}{UNITCOL};
  
  if($cdat_dev >= $cmod_dev && $cdat_typ >= $cmod_typ && $cdat_evt >= $cmod_evt && $cdat_rdg >= $cmod_rdg && $cdat_val >= $cmod_val && $cdat_unt >= $cmod_unt) {
      $rec = "settings o.k.";
  } else {
      if ($dbmodel !~ /SQLITE/)  {
          $rec  = "The relation between column width in table $history and the field width used in device $name don't meet the requirements. ";
	      $rec .= "Please make sure that the width of database field definition is equal or larger than the field width used by the module. Compare the given results.<br>";
	      $rec .= "Currently the default values for field width are: <br><br>";
	      $rec .= "DEVICE: $columns{DEVICE} <br>";
	      $rec .= "TYPE: $columns{TYPE} <br>";
	      $rec .= "EVENT: $columns{EVENT} <br>";
	      $rec .= "READING: $columns{READING} <br>";
	      $rec .= "VALUE: $columns{VALUE} <br>";
	      $rec .= "UNIT: $columns{UNIT} <br><br>";
          $rec .= "You can change the column width in database by a statement like <b>'alter table $history modify VALUE varchar(128);</b>' (example for changing field 'VALUE'). ";
          $rec .= "You can do it for example by executing 'sqlCmd' in DbRep or in a SQL-Editor of your choice. (switch $name to asynchron mode for non-blocking). <br>";
	      $rec .= "Alternatively the field width used by $name can be adjusted by setting attributes 'colEvent', 'colReading', 'colValue'. (pls. refer to commandref)";
      } else {
	      $rec  = "WARNING - The relation between column width in table $history and the field width used by device $name should be equal but it differs.";
		  $rec .= "The field width used by $name can be adjusted by setting attributes 'colEvent', 'colReading', 'colValue'. (pls. refer to commandref)";
		  $rec .= "Because you use SQLite this is only a warning. Normally the database can handle these differences. ";
	  }
  }
  
  $check .= "<u><b>Result of table '$history' check</u></b><br><br>";
  $check .= "Column width set in DB $history: 'DEVICE' = $cdat_dev, 'TYPE' = $cdat_typ, 'EVENT' = $cdat_evt, 'READING' = $cdat_rdg, 'VALUE' = $cdat_val, 'UNIT' = $cdat_unt <br>";
  $check .= "Column width used by $name: 'DEVICE' = $cmod_dev, 'TYPE' = $cmod_typ, 'EVENT' = $cmod_evt, 'READING' = $cmod_rdg, 'VALUE' = $cmod_val, 'UNIT' = $cmod_unt <br>";
  $check .= "<b>Recommendation:</b> $rec <br><br>";

  ### Check Spaltenbreite current
  #######################################################################
  if($dbmodel =~ /MYSQL/) {
      @sr_dev = DbLog_sqlget($hash,"SHOW FIELDS FROM $current where FIELD='DEVICE'");
	  @sr_typ = DbLog_sqlget($hash,"SHOW FIELDS FROM $current where FIELD='TYPE'");
	  @sr_evt = DbLog_sqlget($hash,"SHOW FIELDS FROM $current where FIELD='EVENT'");
	  @sr_rdg = DbLog_sqlget($hash,"SHOW FIELDS FROM $current where FIELD='READING'");
	  @sr_val = DbLog_sqlget($hash,"SHOW FIELDS FROM $current where FIELD='VALUE'");
	  @sr_unt = DbLog_sqlget($hash,"SHOW FIELDS FROM $current where FIELD='UNIT'");
  }
  
  if($dbmodel =~ /POSTGRESQL/) {
      my $sch = AttrVal($name, "dbSchema", "");
      my $c   = "current";
      if($sch) {
          @sr_dev = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and table_schema='$sch' and column_name='device'");
          @sr_typ = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and table_schema='$sch' and column_name='type'");
          @sr_evt = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and table_schema='$sch' and column_name='event'");
          @sr_rdg = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and table_schema='$sch' and column_name='reading'");
          @sr_val = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and table_schema='$sch' and column_name='value'");
          @sr_unt = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and table_schema='$sch' and column_name='unit'");
      } else {
          @sr_dev = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and column_name='device'");
          @sr_typ = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and column_name='type'");
          @sr_evt = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and column_name='event'");
          @sr_rdg = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and column_name='reading'");
          @sr_val = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and column_name='value'");
          @sr_unt = DbLog_sqlget($hash,"select column_name,character_maximum_length from information_schema.columns where table_name='$c' and column_name='unit'");
      
      }
  }
  if($dbmodel =~ /SQLITE/) {
      my $dev = (DbLog_sqlget($hash,"SELECT sql FROM sqlite_master WHERE name = '$current'"))[0];
	  $cdat_dev = $dev?$dev:"no result";
	  $cdat_typ = $cdat_evt = $cdat_rdg = $cdat_val = $cdat_unt = $cdat_dev;
	  $cdat_dev =~ s/.*DEVICE.varchar\(([\d]*)\).*/$1/e;
	  $cdat_typ =~ s/.*TYPE.varchar\(([\d]*)\).*/$1/e;
	  $cdat_evt =~ s/.*EVENT.varchar\(([\d]*)\).*/$1/e;
	  $cdat_rdg =~ s/.*READING.varchar\(([\d]*)\).*/$1/e;
	  $cdat_val =~ s/.*VALUE.varchar\(([\d]*)\).*/$1/e;
	  $cdat_unt =~ s/.*UNIT.varchar\(([\d]*)\).*/$1/e;
  }
  if ($dbmodel !~ /SQLITE/)  { 
      $cdat_dev = @sr_dev?($sr_dev[1]):"no result";
      $cdat_dev =~ tr/varchar\(|\)//d if($cdat_dev ne "no result"); 
      $cdat_typ = @sr_typ?($sr_typ[1]):"no result";
      $cdat_typ =~ tr/varchar\(|\)//d if($cdat_typ ne "no result"); 
      $cdat_evt = @sr_evt?($sr_evt[1]):"no result";
      $cdat_evt =~ tr/varchar\(|\)//d if($cdat_evt ne "no result"); 
      $cdat_rdg = @sr_rdg?($sr_rdg[1]):"no result";
      $cdat_rdg =~ tr/varchar\(|\)//d if($cdat_rdg ne "no result"); 
      $cdat_val = @sr_val?($sr_val[1]):"no result";
      $cdat_val =~ tr/varchar\(|\)//d if($cdat_val ne "no result"); 
      $cdat_unt = @sr_unt?($sr_unt[1]):"no result";
      $cdat_unt =~ tr/varchar\(|\)//d if($cdat_unt ne "no result"); 
  }
      $cmod_dev = $hash->{HELPER}{DEVICECOL};
      $cmod_typ = $hash->{HELPER}{TYPECOL};
      $cmod_evt = $hash->{HELPER}{EVENTCOL};
      $cmod_rdg = $hash->{HELPER}{READINGCOL};
      $cmod_val = $hash->{HELPER}{VALUECOL};
      $cmod_unt = $hash->{HELPER}{UNITCOL};
  
      if($cdat_dev >= $cmod_dev && $cdat_typ >= $cmod_typ && $cdat_evt >= $cmod_evt && $cdat_rdg >= $cmod_rdg && $cdat_val >= $cmod_val && $cdat_unt >= $cmod_unt) {
          $rec = "settings o.k.";
      } else {
	      if ($dbmodel !~ /SQLITE/)  {
              $rec  = "The relation between column width in table $current and the field width used in device $name don't meet the requirements. ";
	          $rec .= "Please make sure that the width of database field definition is equal or larger than the field width used by the module. Compare the given results.<br>";
	          $rec .= "Currently the default values for field width are: <br><br>";
	          $rec .= "DEVICE: $columns{DEVICE} <br>";
	          $rec .= "TYPE: $columns{TYPE} <br>";
	          $rec .= "EVENT: $columns{EVENT} <br>";
	          $rec .= "READING: $columns{READING} <br>";
	          $rec .= "VALUE: $columns{VALUE} <br>";
	          $rec .= "UNIT: $columns{UNIT} <br><br>";
              $rec .= "You can change the column width in database by a statement like <b>'alter table $current modify VALUE varchar(128);</b>' (example for changing field 'VALUE'). ";
              $rec .= "You can do it for example by executing 'sqlCmd' in DbRep or in a SQL-Editor of your choice. (switch $name to asynchron mode for non-blocking). <br>";
	          $rec .= "Alternatively the field width used by $name can be adjusted by setting attributes 'colEvent', 'colReading', 'colValue'. (pls. refer to commandref)";
          } else {
	          $rec  = "WARNING - The relation between column width in table $current and the field width used by device $name should be equal but it differs. ";
		      $rec .= "The field width used by $name can be adjusted by setting attributes 'colEvent', 'colReading', 'colValue'. (pls. refer to commandref)";
		      $rec .= "Because you use SQLite this is only a warning. Normally the database can handle these differences. ";
	      }
	  }
  
      $check .= "<u><b>Result of table '$current' check</u></b><br><br>";
      $check .= "Column width set in DB $current: 'DEVICE' = $cdat_dev, 'TYPE' = $cdat_typ, 'EVENT' = $cdat_evt, 'READING' = $cdat_rdg, 'VALUE' = $cdat_val, 'UNIT' = $cdat_unt <br>";
      $check .= "Column width used by $name: 'DEVICE' = $cmod_dev, 'TYPE' = $cmod_typ, 'EVENT' = $cmod_evt, 'READING' = $cmod_rdg, 'VALUE' = $cmod_val, 'UNIT' = $cmod_unt <br>";
      $check .= "<b>Recommendation:</b> $rec <br><br>";
#}
  
  ### Check Vorhandensein Search_Idx mit den empfohlenen Spalten
  #######################################################################
  my (@six,@six_dev,@six_rdg,@six_tsp);
  my ($idef,$idef_dev,$idef_rdg,$idef_tsp);
  $check .= "<u><b>Result of check 'Search_Idx' availability</u></b><br><br>";
	
  if($dbmodel =~ /MYSQL/) {
      @six = DbLog_sqlget($hash,"SHOW INDEX FROM $history where Key_name='Search_Idx'");
	  if (!@six) {
	      $check .= "The index 'Search_Idx' is missing. <br>";
	      $rec    = "You can create the index by executing statement <b>'CREATE INDEX Search_Idx ON `$history` (DEVICE, READING, TIMESTAMP) USING BTREE;'</b> <br>";
		  $rec   .= "Depending on your database size this command may running a long time. <br>";
		  $rec   .= "Please make sure the device '$name' is operating in asynchronous mode to avoid FHEM from blocking when creating the index. <br>";
		  $rec   .= "<b>Note:</b> If you have just created another index which covers the same fields and order as suggested (e.g. a primary key) you don't need to create the 'Search_Idx' as well ! <br>";
	  } else {
          @six_dev = DbLog_sqlget($hash,"SHOW INDEX FROM $history where Key_name='Search_Idx' and Column_name='DEVICE'");
          @six_rdg = DbLog_sqlget($hash,"SHOW INDEX FROM $history where Key_name='Search_Idx' and Column_name='READING'");
          @six_tsp = DbLog_sqlget($hash,"SHOW INDEX FROM $history where Key_name='Search_Idx' and Column_name='TIMESTAMP'");
          if (@six_dev && @six_rdg && @six_tsp) {
              $check .= "Index 'Search_Idx' exists and contains recommended fields 'DEVICE', 'TIMESTAMP', 'READING'. <br>";
              $rec    = "settings o.k.";
          } else {  
	          $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'DEVICE'. <br>" if (!@six_dev);
		      $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'READING'. <br>" if (!@six_rdg);
		      $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'TIMESTAMP'. <br>" if (!@six_tsp);
		      $rec    = "The index should contain the fields 'DEVICE', 'TIMESTAMP', 'READING'. ";
			  $rec   .= "You can change the index by executing e.g. <br>";
			  $rec   .= "<b>'ALTER TABLE `$history` DROP INDEX `Search_Idx`, ADD INDEX `Search_Idx` (`DEVICE`, `READING`, `TIMESTAMP`) USING BTREE;'</b> <br>";
			  $rec   .= "Depending on your database size this command may running a long time. <br>";
	      }
	  }
  }
  if($dbmodel =~ /POSTGRESQL/) {
      @six = DbLog_sqlget($hash,"SELECT * FROM pg_indexes WHERE tablename='$history' and indexname ='Search_Idx'");
	  if (!@six) {
	      $check .= "The index 'Search_Idx' is missing. <br>";
	      $rec    = "You can create the index by executing statement <b>'CREATE INDEX \"Search_Idx\" ON $history USING btree (device, reading, \"timestamp\")'</b> <br>";
		  $rec   .= "Depending on your database size this command may running a long time. <br>";
		  $rec   .= "Please make sure the device '$name' is operating in asynchronous mode to avoid FHEM from blocking when creating the index. <br>";
          $rec   .= "<b>Note:</b> If you have just created another index which covers the same fields and order as suggested (e.g. a primary key) you don't need to create the 'Search_Idx' as well ! <br>";
	  } else {
          $idef     = $six[4];
		  $idef_dev = 1 if($idef =~ /device/);
		  $idef_rdg = 1 if($idef =~ /reading/);
		  $idef_tsp = 1 if($idef =~ /timestamp/);
          if ($idef_dev && $idef_rdg && $idef_tsp) {
              $check .= "Index 'Search_Idx' exists and contains recommended fields 'DEVICE', 'READING', 'TIMESTAMP'. <br>";
              $rec    = "settings o.k.";
          } else {  
	          $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'DEVICE'. <br>" if (!$idef_dev);
		      $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'READING'. <br>" if (!$idef_rdg);
		      $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'TIMESTAMP'. <br>" if (!$idef_tsp);
		      $rec    = "The index should contain the fields 'DEVICE', 'READING', 'TIMESTAMP'. ";
			  $rec   .= "You can change the index by executing e.g. <br>";
			  $rec   .= "<b>'DROP INDEX \"Search_Idx\"; CREATE INDEX \"Search_Idx\" ON $history USING btree (device, reading, \"timestamp\")'</b> <br>";
			  $rec   .= "Depending on your database size this command may running a long time. <br>";
	      }
	  }
  }
  if($dbmodel =~ /SQLITE/) {
      @six = DbLog_sqlget($hash,"SELECT name,sql FROM sqlite_master WHERE type='index' AND name='Search_Idx'");
	  if (!$six[0]) {
	      $check .= "The index 'Search_Idx' is missing. <br>";
	      $rec    = "You can create the index by executing statement <b>'CREATE INDEX Search_Idx ON `$history` (DEVICE, READING, TIMESTAMP)'</b> <br>";
		  $rec   .= "Depending on your database size this command may running a long time. <br>";
		  $rec   .= "Please make sure the device '$name' is operating in asynchronous mode to avoid FHEM from blocking when creating the index. <br>";
          $rec   .= "<b>Note:</b> If you have just created another index which covers the same fields and order as suggested (e.g. a primary key) you don't need to create the 'Search_Idx' as well ! <br>";
	  } else {
          $idef     = $six[1];
		  $idef_dev = 1 if(lc($idef) =~ /device/);
		  $idef_rdg = 1 if(lc($idef) =~ /reading/);
		  $idef_tsp = 1 if(lc($idef) =~ /timestamp/);
          if ($idef_dev && $idef_rdg && $idef_tsp) {
              $check .= "Index 'Search_Idx' exists and contains recommended fields 'DEVICE', 'READING', 'TIMESTAMP'. <br>";
              $rec    = "settings o.k.";
          } else {  
	          $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'DEVICE'. <br>" if (!$idef_dev);
		      $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'READING'. <br>" if (!$idef_rdg);
		      $check .= "Index 'Search_Idx' exists but doesn't contain recommended field 'TIMESTAMP'. <br>" if (!$idef_tsp);
		      $rec    = "The index should contain the fields 'DEVICE', 'READING', 'TIMESTAMP'. ";
			  $rec   .= "You can change the index by executing e.g. <br>";
			  $rec   .= "<b>'DROP INDEX \"Search_Idx\"; CREATE INDEX Search_Idx ON `$history` (DEVICE, READING, TIMESTAMP)'</b> <br>";
			  $rec   .= "Depending on your database size this command may running a long time. <br>";
	      }
	  }
  }
  
  $check .= "<b>Recommendation:</b> $rec <br><br>";
  
  ### Check Index Report_Idx für DbRep-Device falls DbRep verwendet wird
  #######################################################################
  my ($dbrp,$irep,);
  my (@dix,@dix_rdg,@dix_tsp,$irep_rdg,$irep_tsp);
  my $isused = 0;
  my @repdvs = devspec2array("TYPE=DbRep");
  $check .= "<u><b>Result of check 'Report_Idx' availability for DbRep-devices</u></b><br><br>";
  
  foreach (@repdvs) {
      $dbrp = $_;
      if(!$defs{$dbrp}) {
          Log3 ($name, 2, "DbLog $name -> Device '$dbrp' found by configCheck doesn't exist !");
	      next;
      }
	  if ($defs{$dbrp}->{DEF} eq $name) {
	      # DbRep Device verwendet aktuelles DbLog-Device
          Log3 ($name, 5, "DbLog $name -> DbRep-Device '$dbrp' uses $name.");
          $isused = 1;		  
      }
  }
  if ($isused) {
	  if($dbmodel =~ /MYSQL/) {
          @dix = DbLog_sqlget($hash,"SHOW INDEX FROM $history where Key_name='Report_Idx'");
	      if (!@dix) {
	          $check .= "At least one DbRep-device assigned to $name is used, but the recommended index 'Report_Idx' is missing. <br>";
	          $rec    = "You can create the index by executing statement <b>'CREATE INDEX Report_Idx ON `$history` (TIMESTAMP,READING) USING BTREE;'</b> <br>";
		      $rec   .= "Depending on your database size this command may running a long time. <br>";
		      $rec   .= "Please make sure the device '$name' is operating in asynchronous mode to avoid FHEM from blocking when creating the index. <br>";
		      $rec   .= "<b>Note:</b> If you have just created another index which covers the same fields and order as suggested (e.g. a primary key) you don't need to create the 'Report_Idx' as well ! <br>";
	      } else {
              @dix_rdg = DbLog_sqlget($hash,"SHOW INDEX FROM $history where Key_name='Report_Idx' and Column_name='READING'");
              @dix_tsp = DbLog_sqlget($hash,"SHOW INDEX FROM $history where Key_name='Report_Idx' and Column_name='TIMESTAMP'");
              if (@dix_rdg && @dix_tsp) {
			      $check .= "At least one DbRep-device assigned to $name is used. ";
                  $check .= "Index 'Report_Idx' exists and contains recommended fields 'TIMESTAMP', 'READING'. <br>";
                  $rec    = "settings o.k.";
              } else {  
			      $check .= "You use at least one DbRep-device assigned to $name. ";
		          $check .= "Index 'Report_Idx' exists but doesn't contain recommended field 'READING'. <br>" if (!@dix_rdg);
		          $check .= "Index 'Report_Idx' exists but doesn't contain recommended field 'TIMESTAMP'. <br>" if (!@dix_tsp);
		          $rec    = "The index should contain the fields 'TIMESTAMP', 'READING'. ";
		          $rec   .= "You can change the index by executing e.g. <br>";
		          $rec   .= "<b>'ALTER TABLE `$history` DROP INDEX `Report_Idx`, ADD INDEX `Report_Idx` (`TIMESTAMP`, `READING`) USING BTREE'</b> <br>";
		          $rec   .= "Depending on your database size this command may running a long time. <br>";
	          }
	      }
      }
	  if($dbmodel =~ /POSTGRESQL/) {
          @dix = DbLog_sqlget($hash,"SELECT * FROM pg_indexes WHERE tablename='$history' and indexname ='Report_Idx'");
	      if (!@dix) {
	          $check .= "You use at least one DbRep-device assigned to $name, but the recommended index 'Report_Idx' is missing. <br>";
	          $rec    = "You can create the index by executing statement <b>'CREATE INDEX \"Report_Idx\" ON $history USING btree (\"timestamp\", reading)'</b> <br>";
		      $rec   .= "Depending on your database size this command may running a long time. <br>";
		      $rec   .= "Please make sure the device '$name' is operating in asynchronous mode to avoid FHEM from blocking when creating the index. <br>";
		      $rec   .= "<b>Note:</b> If you have just created another index which covers the same fields and order as suggested (e.g. a primary key) you don't need to create the 'Report_Idx' as well ! <br>";
	      } else {
              $irep     = $dix[4];
		      $irep_rdg = 1 if($irep =~ /reading/);
		      $irep_tsp = 1 if($irep =~ /timestamp/);
              if ($irep_rdg && $irep_tsp) {
                  $check .= "Index 'Report_Idx' exists and contains recommended fields 'TIMESTAMP', 'READING'. <br>";
                  $rec    = "settings o.k.";
              } else {  
		          $check .= "Index 'Report_Idx' exists but doesn't contain recommended field 'READING'. <br>" if (!$irep_rdg);
		          $check .= "Index 'Report_Idx' exists but doesn't contain recommended field 'TIMESTAMP'. <br>" if (!$irep_tsp);
		          $rec    = "The index should contain the fields 'TIMESTAMP', 'READING'. ";
			      $rec   .= "You can change the index by executing e.g. <br>";
			      $rec   .= "<b>'DROP INDEX \"Report_Idx\"; CREATE INDEX \"Report_Idx\" ON $history USING btree (\"timestamp\", reading)'</b> <br>";
			      $rec   .= "Depending on your database size this command may running a long time. <br>";
	          }
	      }
      }
      if($dbmodel =~ /SQLITE/) {
          @dix = DbLog_sqlget($hash,"SELECT name,sql FROM sqlite_master WHERE type='index' AND name='Report_Idx'");
	      if (!$dix[0]) {
	          $check .= "The index 'Report_Idx' is missing. <br>";
	          $rec    = "You can create the index by executing statement <b>'CREATE INDEX Report_Idx ON `$history` (TIMESTAMP,READING)'</b> <br>";
		      $rec   .= "Depending on your database size this command may running a long time. <br>";
		      $rec   .= "Please make sure the device '$name' is operating in asynchronous mode to avoid FHEM from blocking when creating the index. <br>";
              $rec   .= "<b>Note:</b> If you have just created another index which covers the same fields and order as suggested (e.g. a primary key) you don't need to create the 'Search_Idx' as well ! <br>";
	      } else {
              $irep     = $dix[1];
		      $irep_rdg = 1 if(lc($irep) =~ /reading/);
		      $irep_tsp = 1 if(lc($irep) =~ /timestamp/);
              if ($irep_rdg && $irep_tsp) {
                  $check .= "Index 'Report_Idx' exists and contains recommended fields 'TIMESTAMP', 'READING'. <br>";
                  $rec    = "settings o.k.";
              } else {
		          $check .= "Index 'Report_Idx' exists but doesn't contain recommended field 'READING'. <br>" if (!$irep_rdg);
		          $check .= "Index 'Report_Idx' exists but doesn't contain recommended field 'TIMESTAMP'. <br>" if (!$irep_tsp);
		          $rec    = "The index should contain the fields 'TIMESTAMP', 'READING'. ";
			      $rec   .= "You can change the index by executing e.g. <br>";
			      $rec   .= "<b>'DROP INDEX \"Report_Idx\"; CREATE INDEX Report_Idx ON `$history` (TIMESTAMP,READING)'</b> <br>";
			      $rec   .= "Depending on your database size this command may running a long time. <br>";
	          }
	      }
      }
  } else {
      $check .= "No DbRep-device assigned to $name is used. Hence an index for DbRep isn't needed. <br>";
      $rec    = "settings o.k.";
  }
  $check .= "<b>Recommendation:</b> $rec <br><br>";
  
  $check .= "</html>";

return $check;
}

#########################################################################################
#                  check Modul Aktualität fhem.de <-> local
#########################################################################################
sub DbLog_checkModVer($) {
  my ($name) = @_;
  my $src    = "http://fhem.de/fhemupdate/controls_fhem.txt";

  if($src !~ m,^(.*)/([^/]*)$,) {
    Log3 $name, 1, "DbLog $name -> configCheck: Cannot parse $src, probably not a valid http control file";
    return ("check of new DbLog version not possible, see logfile.");
  }
  
  my $basePath     = $1;
  my $ctrlFileName = $2;

  my ($remCtrlFile, $err) = DbLog_updGetUrl($name,$src);
  return ("check of new DbLog version not possible: $err") if($err);
  
  if(!$remCtrlFile) {
      Log3 $name, 1, "DbLog $name -> configCheck: No valid remote control file";
      return ("check of new DbLog version not possible, see logfile.");
  }
  
  my @remList = split(/\R/, $remCtrlFile);
  Log3 $name, 4, "DbLog $name -> configCheck: Got remote $ctrlFileName with ".int(@remList)." entries.";

  my $root = $attr{global}{modpath};

  my @locList;
  if(open(FD, "$root/FHEM/$ctrlFileName")) {
      @locList = map { $_ =~ s/[\r\n]//; $_ } <FD>;
      close(FD);
      Log3 $name, 4, "DbLog $name -> configCheck: Got local $ctrlFileName with ".int(@locList)." entries.";
  } else {
      Log3 $name, 1, "DbLog $name -> configCheck: can't open $root/FHEM/$ctrlFileName: $!";
      return ("check of new DbLog version not possible, see logfile.");  
  }
  
  my %lh;
  foreach my $l (@locList) {
      my @l = split(" ", $l, 4);
      next if($l[0] ne "UPD" || $l[3] !~ /93_DbLog/);
      $lh{$l[3]}{TS} = $l[1];
      $lh{$l[3]}{LEN} = $l[2];
      Log3 $name, 4, "DbLog $name -> configCheck: local version from last update - creation time: ".$lh{$l[3]}{TS}." - bytes: ".$lh{$l[3]}{LEN};
  }
  
  my $noSzCheck = AttrVal("global", "updateNoFileCheck", configDBUsed());
  foreach my $rem (@remList) {
      my @r = split(" ", $rem, 4);
      next if($r[0] ne "UPD" || $r[3] !~ /93_DbLog/);
      my $fName  = $r[3];
      my $fPath  = "$root/$fName";
      my $fileOk = ($lh{$fName} && $lh{$fName}{TS} eq $r[1] && $lh{$fName}{LEN} eq $r[2]);
      if(!$fileOk) {
          Log3 $name, 4, "DbLog $name -> configCheck: New remote version of $fName found - creation time: ".$r[1]." - bytes: ".$r[2];
          return ("",1,"A new DbLog version is available (creation time: $r[1], size: $r[2] bytes)");
      }
      if(!$noSzCheck) {
          my $sz = -s $fPath;
          if($fileOk && defined($sz) && $sz ne $r[2]) {
              Log3 $name, 4, "DbLog $name -> configCheck: remote version of $fName (creation time: $r[1], bytes: $r[2]) differs from local one (bytes: $sz)";
              return ("",1,"Your local DbLog module is modified.");
          }
      }
      last;
  }
  
return ("",0,"Your local DbLog module is up to date.");
}

###################################
sub DbLog_updGetUrl($$) {
  my ($name,$url) = @_;
  my %upd_connecthash;
  $url =~ s/%/%25/g;
  $upd_connecthash{url} = $url;
  $upd_connecthash{keepalive} = ($url =~ m/localUpdate/ ? 0 : 1); # Forum #49798
  
  my ($err, $data) = HttpUtils_BlockingGet(\%upd_connecthash);
  if($err) {
      Log3 $name, 1, "DbLog $name -> configCheck: ERROR while connecting to fhem.de:  $err";
      return ("",$err);
  }
  if(!$data) {
      Log3 $name, 1, "DbLog $name -> configCheck: ERROR $url: empty file received";
      $err = 1;
      return ("",$err);
  }
  
return ($data,"");
}

#########################################################################################
#                  Einen (einfachen) Datensatz aus DB lesen
#########################################################################################
sub DbLog_sqlget($$) {
  my ($hash,$sql)= @_;
  my $name = $hash->{NAME};
  my ($dbh,$sth,@sr);
  
  Log3 ($name, 4, "DbLog $name - Executing SQL: $sql");
  
  $dbh = DbLog_ConnectNewDBH($hash);
  return if(!$dbh);
  
  eval { $sth = $dbh->prepare("$sql");                     
         $sth->execute;
	   };
  if($@) {
      $dbh->disconnect if($dbh);
      Log3 ($name, 2, "DbLog $name - $@");
      return @sr;
  }
  
  @sr = $sth->fetchrow; 
  
  $sth->finish;
  $dbh->disconnect;
  no warnings 'uninitialized';
  Log3 ($name, 4, "DbLog $name - SQL result: @sr");
  use warnings;
  
return @sr;
}

#########################################################################################
#
# Addlog - einfügen des Readingwertes eines gegebenen Devices
#
#########################################################################################
sub DbLog_AddLog($$$$$) {
  my ($hash,$devrdspec,$value,$nce,$cn)= @_;
  my $name     = $hash->{NAME};
  my $async    = AttrVal($name, "asyncMode", undef);
  my $value_fn = AttrVal( $name, "valueFn", "" );
  my $ce       = AttrVal($name, "cacheEvents", 0);
  my ($dev_type,$dev_name,$dev_reading,$read_val,$event,$ut);  
  my @row_array;  
  my $ts;

  return if(IsDisabled($name) || !$hash->{HELPER}{COLSET} || $init_done != 1);
  
  # Funktion aus Attr valueFn validieren
  if( $value_fn =~ m/^\s*(\{.*\})\s*$/s ) {
      $value_fn = $1;
  } else {
      $value_fn = '';
  }
  
  my $now  = gettimeofday(); 
  
  my $rdspec = (split ":",$devrdspec)[-1];
  my @dc = split(":",$devrdspec);
  pop @dc;
  my $devspec = join(':',@dc);

  my @exdvs = devspec2array($devspec);
  Log3 $name, 4, "DbLog $name -> Addlog known devices by devspec: @exdvs";
  foreach (@exdvs) {
      $dev_name = $_;
      if(!$defs{$dev_name}) {
          Log3 $name, 2, "DbLog $name -> Device '$dev_name' used by addLog doesn't exist !";
	      next;
      }
	  
	  my $r            = $defs{$dev_name}{READINGS};
      my $DbLogExclude = AttrVal($dev_name, "DbLogExclude", undef);
	  my $DbLogInclude = AttrVal($dev_name, "DbLogInclude", undef);
	  my @exrds;
      my $found = 0;
	  foreach my $rd (sort keys %{$r}) {                                      # jedes Reading des Devices auswerten           
           my $do = 1;
           $found = 1 if($rd =~ m/^$rdspec$/);                                # Reading gefunden
		   if($DbLogExclude && !$nce) {
               my @v1 = split(/,/, $DbLogExclude);
               for (my $i=0; $i<int(@v1); $i++) {
                   my @v2 = split(/:/, $v1[$i]);                              # MinInterval wegschneiden, Bsp: "(temperature|humidity):600,battery:3600"
                   if($rd =~ m,^$v2[0]$,) {                                   # Reading matcht $DbLogExclude -> ausschließen vom addLog  
			           $do = 0;
					   if($DbLogInclude) {
						   my @v3 = split(/,/, $DbLogInclude);
						   for (my $i=0; $i<int(@v3); $i++) {
							   my @v4 = split(/:/, $v3[$i]);
							   $do = 1 if($rd =~ m,^$v4[0]$,);                # Reading matcht $DbLogInclude -> wieder in addLog einschließen  
						   }
					   }                       				   
					   Log3 $name, 2, "DbLog $name -> Device: \"$dev_name\", reading: \"$v2[0]\" excluded by attribute DbLogExclude from addLog !" if($do == 0 && $rd =~ m/^$rdspec$/);        	   
				   }
               }
           }
           next if(!$do);
		   push @exrds,$rd if($rd =~ m/^$rdspec$/);    
	  }
	  Log3 $name, 4, "DbLog $name -> Readings extracted from Regex: @exrds";

	  if(!$found) {
          if(goodReadingName($rdspec) && defined($value)) {
              Log3 $name, 3, "DbLog $name -> addLog WARNING - Device: '$dev_name' -> Reading '$rdspec' not found - add it as new reading.";
              push @exrds,$rdspec;
          } elsif (goodReadingName($rdspec) && !defined($value)) {
              Log3 $name, 2, "DbLog $name -> addLog WARNING - Device: '$dev_name' -> new Reading '$rdspec' has no value - can't add it !";
          } else {
              Log3 $name, 2, "DbLog $name -> addLog WARNING - Device: '$dev_name' -> Readingname '$rdspec' is no valid or regexp - can't add regexp as new reading !";
          }
      }
      
      no warnings 'uninitialized'; 
	  foreach (@exrds) {
	      $dev_reading = $_;
          $read_val = $value ne ""?$value:ReadingsVal($dev_name,$dev_reading,"");
	      $dev_type = uc($defs{$dev_name}{TYPE});
          
          # dummy-Event zusammenstellen
	      $event = $dev_reading.": ".$read_val; 

	      # den zusammengestellten Event parsen lassen (evtl. Unit zuweisen)
          my @r = DbLog_ParseEvent($dev_name, $dev_type, $event);
          $dev_reading = $r[0];
          $read_val    = $r[1];
          $ut          = $r[2];
          if(!defined $dev_reading) {$dev_reading = "";}
          if(!defined $read_val) {$read_val = "";}
          if(!defined $ut || $ut eq "") {$ut = AttrVal("$dev_name", "unit", "");}   
          $event       = "addLog";
		  
		  $defs{$dev_name}{Helper}{DBLOG}{$dev_reading}{$hash->{NAME}}{TIME}  = $now;
          $defs{$dev_name}{Helper}{DBLOG}{$dev_reading}{$hash->{NAME}}{VALUE} = $read_val;
          $ts = TimeNow();
	      # Anwender spezifische Funktion anwenden 
          if($value_fn ne '') {
              my $TIMESTAMP  = $ts;
 	          my $DEVICE     = $dev_name;
 	          my $DEVICETYPE = $dev_type;
     	      my $EVENT      = $event;
 	          my $READING    = $dev_reading;
 	          my $VALUE 	 = $read_val;
 	          my $UNIT   	 = $ut;
	          my $IGNORE     = 0;
              my $CN         = $cn?$cn:"";

 	          eval $value_fn;
	          Log3 $name, 2, "DbLog $name -> error valueFn: ".$@ if($@);
	          next if($IGNORE);  # aktueller Event wird nicht geloggt wenn $IGNORE=1 gesetzt in $value_fn
              
              my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($TIMESTAMP =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
              eval { my $epoch_seconds_begin = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };
              if (!$@) {
                  $ts = $TIMESTAMP;
              } else {
                  Log3 ($name, 2, "DbLog $name -> Parameter TIMESTAMP got from valueFn is invalid: $TIMESTAMP");
              }
 	          $dev_name     = $DEVICE     if($DEVICE ne '');
	          $dev_type     = $DEVICETYPE if($DEVICETYPE ne '');
 	          $dev_reading  = $READING    if($READING ne '');
 		  	  $read_val     = $VALUE      if(defined $VALUE);
 			  $ut           = $UNIT       if(defined $UNIT);
          }
	   
          # Daten auf maximale Länge beschneiden
          ($dev_name,$dev_type,$event,$dev_reading,$read_val,$ut) = DbLog_cutCol($hash,$dev_name,$dev_type,$event,$dev_reading,$read_val,$ut);
          
          if(AttrVal($name, "useCharfilter",0)) {
              $dev_reading = DbLog_charfilter($dev_reading);
              $read_val    = DbLog_charfilter($read_val);
          }
          
          my $row = ($ts."|".$dev_name."|".$dev_type."|".$event."|".$dev_reading."|".$read_val."|".$ut);
          Log3 $hash->{NAME}, 3, "DbLog $name -> addLog created - TS: $ts, Device: $dev_name, Type: $dev_type, Event: $event, Reading: $dev_reading, Value: $read_val, Unit: $ut"
		      if(!AttrVal($name, "suppressAddLogV3",0));
  
          if($async) {
              # asynchoner non-blocking Mode
	          # Cache & CacheIndex für Events zum asynchronen Schreiben in DB
	          $data{DbLog}{$name}{cache}{index}++;
	          my $index = $data{DbLog}{$name}{cache}{index};
	          $data{DbLog}{$name}{cache}{memcache}{$index} = $row;
		      my $memcount = $data{DbLog}{$name}{cache}{memcache}?scalar(keys %{$data{DbLog}{$name}{cache}{memcache}}):0;
	          if($ce == 1) {
                  readingsSingleUpdate($hash, "CacheUsage", $memcount, 1); 
	          } else {
	              readingsSingleUpdate($hash, 'CacheUsage', $memcount, 0); 
	          }
          } else {
              # synchoner Mode	
	          push(@row_array, $row);
          }
	  }
      use warnings;
  }
  if(!$async) {    
      if(@row_array) {
	      # synchoner Mode
		  # return wenn "reopen" mit Ablaufzeit gestartet ist
          return if($hash->{HELPER}{REOPEN_RUNS});	  
          my $error = DbLog_Push($hash, 1, @row_array);

          my $state  = $error?$error:(IsDisabled($name))?"disabled":"connected";
          my $evt    = ($state eq $hash->{HELPER}{OLDSTATE})?0:1;
          readingsSingleUpdate($hash, "state", $state, $evt);
          $hash->{HELPER}{OLDSTATE} = $state;
		  
          Log3 $name, 5, "DbLog $name -> DbLog_Push Returncode: $error";
      }
  }
return;
}

#########################################################################################
#
# Subroutine addCacheLine - einen Datensatz zum Cache hinzufügen
#
#########################################################################################
sub DbLog_addCacheLine($$$$$$$$) {
  my ($hash,$i_timestamp,$i_dev,$i_type,$i_evt,$i_reading,$i_val,$i_unit) = @_;
  my $name     = $hash->{NAME};
  my $ce       = AttrVal($name, "cacheEvents", 0);
  my $value_fn = AttrVal( $name, "valueFn", "" );  
               
  # Funktion aus Attr valueFn validieren
  if( $value_fn =~ m/^\s*(\{.*\})\s*$/s ) {
      $value_fn = $1;
  } else {
      $value_fn = '';
  }
  if($value_fn ne '') {
      my $TIMESTAMP  = $i_timestamp;
      my $DEVICE     = $i_dev;
 	  my $DEVICETYPE = $i_type;
 	  my $EVENT      = $i_evt;
 	  my $READING    = $i_reading;
 	  my $VALUE 	 = $i_val;
 	  my $UNIT   	 = $i_unit;
	  my $IGNORE     = 0;
      my $CN         = " ";

 	  eval $value_fn;
	  Log3 $name, 2, "DbLog $name -> error valueFn: ".$@ if($@);
	  if($IGNORE) {
          # aktueller Event wird nicht geloggt wenn $IGNORE=1 gesetzt in $value_fn
		  Log3 $hash->{NAME}, 4, "DbLog $name -> Event ignored by valueFn - TS: $i_timestamp, Device: $i_dev, Type: $i_type, Event: $i_evt, Reading: $i_reading, Value: $i_val, Unit: $i_unit";
		  next;  
	  }
					  
	  $i_timestamp = $TIMESTAMP  if($TIMESTAMP =~ /(19[0-9][0-9]|2[0-9][0-9][0-9])-(0[1-9]|1[1-2])-(0[1-9]|1[0-9]|2[0-9]|3[0-1]) (0[0-9]|1[1-9]|2[0-3]):([0-5][0-9]):([0-5][0-9])/);
 	  $i_dev       = $DEVICE     if($DEVICE ne '');
 	  $i_type      = $DEVICETYPE if($DEVICETYPE ne '');
 	  $i_reading   = $READING    if($READING ne '');
 	  $i_val       = $VALUE      if(defined $VALUE);
 	  $i_unit      = $UNIT       if(defined $UNIT);
  }
		
  no warnings 'uninitialized'; 
  # Daten auf maximale Länge beschneiden
  ($i_dev,$i_type,$i_evt,$i_reading,$i_val,$i_unit) = DbLog_cutCol($hash,$i_dev,$i_type,$i_evt,$i_reading,$i_val,$i_unit);
  
  my $row = ($i_timestamp."|".$i_dev."|".$i_type."|".$i_evt."|".$i_reading."|".$i_val."|".$i_unit);
  $row    = DbLog_charfilter($row) if(AttrVal($name, "useCharfilter",0));
  Log3 $hash->{NAME}, 3, "DbLog $name -> added by addCacheLine - TS: $i_timestamp, Device: $i_dev, Type: $i_type, Event: $i_evt, Reading: $i_reading, Value: $i_val, Unit: $i_unit";
  use warnings;
  
  eval {         # one transaction
      $data{DbLog}{$name}{cache}{index}++;
	  my $index = $data{DbLog}{$name}{cache}{index};
	  $data{DbLog}{$name}{cache}{memcache}{$index} = $row;
					  
      my $memcount = $data{DbLog}{$name}{cache}{memcache}?scalar(keys %{$data{DbLog}{$name}{cache}{memcache}}):0;
	  if($ce == 1) {
          readingsSingleUpdate($hash, "CacheUsage", $memcount, 1); 
	  } else {
	      readingsSingleUpdate($hash, 'CacheUsage', $memcount, 0); 
	  }
  };

return;
}


#########################################################################################
#
# Subroutine cutCol - Daten auf maximale Länge beschneiden
#
#########################################################################################
sub DbLog_cutCol($$$$$$$) {
  my ($hash,$dn,$dt,$evt,$rd,$val,$unit)= @_;
  my $name       = $hash->{NAME};  
  my $colevent   = AttrVal($name, 'colEvent', undef);
  my $colreading = AttrVal($name, 'colReading', undef);
  my $colvalue   = AttrVal($name, 'colValue', undef);
   
  if ($hash->{MODEL} ne 'SQLITE' || defined($colevent) || defined($colreading) || defined($colvalue) ) {
      $dn   = substr($dn,0, $hash->{HELPER}{DEVICECOL});
      $dt   = substr($dt,0, $hash->{HELPER}{TYPECOL});
      $evt  = substr($evt,0, $hash->{HELPER}{EVENTCOL});
      $rd   = substr($rd,0, $hash->{HELPER}{READINGCOL});
      $val  = substr($val,0, $hash->{HELPER}{VALUECOL});
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
sub DbLog_commitMode ($) { 
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  my $useac  = 2;      # default Servereinstellung
  my $useta  = 1;      # default Transaktion ein
  
  my $cm       = AttrVal($name, "commitMode", "basic_ta:on");
  my ($ac,$ta) = split("_",$cm);
  $useac       = ($ac =~ /off/)?0:($ac =~ /on/)?1:2;
  $useta       = 0 if($ta =~ /off/);
  
return($useac,$useta);
}

###############################################################################
#              Zeichen von Feldevents filtern 
###############################################################################
sub DbLog_charfilter ($) { 
  my ($txt) = @_;
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

#########################################################################################
### DBLog - Historische Werte ausduennen (alte blockiernde Variante) > Forum #41089
#########################################################################################
sub DbLog_reduceLog($@) {
    my ($hash,@a) = @_;
    my $history   = $hash->{HELPER}{TH};
    my $current   = $hash->{HELPER}{TC};
    my ($ret,$row,$err,$filter,$exclude,$c,$day,$hour,$lastHour,$updDate,$updHour,$average,$processingDay,$lastUpdH,%hourlyKnown,%averageHash,@excludeRegex,@dayRows,@averageUpd,@averageUpdD);
    my ($name,$startTime,$currentHour,$currentDay,$deletedCount,$updateCount,$sum,$rowCount,$excludeCount) = ($hash->{NAME},time(),99,0,0,0,0,0,0);
    my $dbh = DbLog_ConnectNewDBH($hash);
    return if(!$dbh);
  
    if ($a[-1] =~ /^EXCLUDE=(.+:.+)+/i) {
        ($filter) = $a[-1] =~ /^EXCLUDE=(.+)/i;
        @excludeRegex = split(',',$filter);
    } elsif ($a[-1] =~ /^INCLUDE=.+:.+$/i) {
        $filter = 1;
    }
    if (defined($a[3])) {
        $average = ($a[3] =~ /average=day/i) ? "AVERAGE=DAY" : ($a[3] =~ /average/i) ? "AVERAGE=HOUR" : 0;
    }
    Log3($name, 3, "DbLog $name: reduceLog requested with DAYS=$a[2]"
        .(($average || $filter) ? ', ' : '').(($average) ? "$average" : '')
        .(($average && $filter) ? ", " : '').(($filter) ? uc((split('=',$a[-1]))[0]).'='.(split('=',$a[-1]))[1] : ''));
		
    my ($useac,$useta) = DbLog_commitMode($hash);
    my $ac = ($dbh->{AutoCommit})?"ON":"OFF";
    my $tm = ($useta)?"ON":"OFF";
    Log3 $hash->{NAME}, 4, "DbLog $name -> AutoCommit mode: $ac, Transaction mode: $tm";
    
    my ($od,$nd) = split(":",$a[2]);         # $od - Tage älter als , $nd - Tage neuer als
    my ($ots,$nts);
    if ($hash->{MODEL} eq 'SQLITE') { 
        $ots = "datetime('now', '-$od days')";
        $nts = "datetime('now', '-$nd days')" if($nd);
    } elsif ($hash->{MODEL} eq 'MYSQL') { 
        $ots = "DATE_SUB(CURDATE(),INTERVAL $od DAY)"; 
        $nts = "DATE_SUB(CURDATE(),INTERVAL $nd DAY)" if($nd); 
    } elsif ($hash->{MODEL} eq 'POSTGRESQL') { 
        $ots = "NOW() - INTERVAL '$od' DAY"; 
        $nts = "NOW() - INTERVAL '$nd' DAY" if($nd);
    } else { 
        $ret = 'Unknown database type.'; 
    }
    
    if ($ots) {
	    my ($sth_del, $sth_upd, $sth_delD, $sth_updD, $sth_get);
        eval { $sth_del  = $dbh->prepare_cached("DELETE FROM $history WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?) AND (VALUE=?)");
               $sth_upd  = $dbh->prepare_cached("UPDATE $history SET TIMESTAMP=?, EVENT=?, VALUE=? WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?) AND (VALUE=?)");
               $sth_delD = $dbh->prepare_cached("DELETE FROM $history WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?)");
               $sth_updD = $dbh->prepare_cached("UPDATE $history SET TIMESTAMP=?, EVENT=?, VALUE=? WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?)");
               $sth_get  = $dbh->prepare("SELECT TIMESTAMP,DEVICE,'',READING,VALUE FROM $history WHERE "
                           .($a[-1] =~ /^INCLUDE=(.+):(.+)$/i ? "DEVICE like '$1' AND READING like '$2' AND " : '')
                           ."TIMESTAMP < $ots".($nts?" AND TIMESTAMP >= $nts ":" ")."ORDER BY TIMESTAMP ASC");  # '' was EVENT, no longer in use
		     };
        
        $sth_get->execute();
        
        do {
            $row = $sth_get->fetchrow_arrayref || ['0000-00-00 00:00:00','D','','R','V'];  # || execute last-day dummy
            $ret = 1;
            ($day,$hour) = $row->[0] =~ /-(\d{2})\s(\d{2}):/;
            $rowCount++ if($day != 00);
            if ($day != $currentDay) {
                if ($currentDay) { # false on first executed day
                    if (scalar @dayRows) {
                        ($lastHour) = $dayRows[-1]->[0] =~ /(.*\d+\s\d{2}):/;
                        $c = 0;
                        for my $delRow (@dayRows) {
                            $c++ if($day != 00 || $delRow->[0] !~ /$lastHour/);
                        }
                        if($c) {
                            $deletedCount += $c;
                            Log3($name, 3, "DbLog $name: reduceLog deleting $c records of day: $processingDay");
                            $dbh->{RaiseError} = 1;
                            $dbh->{PrintError} = 0; 
                            eval {$dbh->begin_work() if($dbh->{AutoCommit});};
                            eval {
							    my $i = 0;
								my $k = 1;
								my $th = ($#dayRows <= 2000)?100:($#dayRows <= 30000)?1000:10000;
                                for my $delRow (@dayRows) {
                                    if($day != 00 || $delRow->[0] !~ /$lastHour/) {
                                        Log3($name, 5, "DbLog $name: DELETE FROM $history WHERE (DEVICE=$delRow->[1]) AND (READING=$delRow->[3]) AND (TIMESTAMP=$delRow->[0]) AND (VALUE=$delRow->[4])");
                                        $sth_del->execute(($delRow->[1], $delRow->[3], $delRow->[0], $delRow->[4]));
										$i++;
										if($i == $th) {
										    my $prog = $k * $i; 
										    Log3($name, 3, "DbLog $name: reduceLog deletion progress of day: $processingDay is: $prog");
											$i = 0;
											$k++;
										}
                                    }
                                }
                            };
                            if ($@) {
                                Log3($hash->{NAME}, 3, "DbLog $name: reduceLog ! FAILED ! for day $processingDay");
                                eval {$dbh->rollback() if(!$dbh->{AutoCommit});};
                                $ret = 0;
                            } else {
                                eval {$dbh->commit() if(!$dbh->{AutoCommit});};
                            }
                            $dbh->{RaiseError} = 0; 
                            $dbh->{PrintError} = 1;
                        }
                        @dayRows = ();
                    }
                    
                    if ($ret && defined($a[3]) && $a[3] =~ /average/i) {
                        $dbh->{RaiseError} = 1;
                        $dbh->{PrintError} = 0; 
                        eval {$dbh->begin_work() if($dbh->{AutoCommit});};
                        eval {
                            push(@averageUpd, {%hourlyKnown}) if($day != 00);
                            
                            $c = 0;
                            for my $hourHash (@averageUpd) {  # Only count for logging...
                                for my $hourKey (keys %$hourHash) {
                                    $c++ if ($hourHash->{$hourKey}->[0] && scalar(@{$hourHash->{$hourKey}->[4]}) > 1);
                                }
                            }
                            $updateCount += $c;
                            Log3($name, 3, "DbLog $name: reduceLog (hourly-average) updating $c records of day: $processingDay") if($c); # else only push to @averageUpdD

							my $i = 0;
							my $k = 1;
							my $th = ($c <= 2000)?100:($c <= 30000)?1000:10000;
                            for my $hourHash (@averageUpd) {
                                for my $hourKey (keys %$hourHash) {
                                    if ($hourHash->{$hourKey}->[0]) { # true if reading is a number 
                                        ($updDate,$updHour) = $hourHash->{$hourKey}->[0] =~ /(.*\d+)\s(\d{2}):/;
                                        if (scalar(@{$hourHash->{$hourKey}->[4]}) > 1) {  # true if reading has multiple records this hour
                                            for (@{$hourHash->{$hourKey}->[4]}) { $sum += $_; }
                                            $average = sprintf('%.3f', $sum/scalar(@{$hourHash->{$hourKey}->[4]}) );
                                            $sum = 0;
                                            Log3($name, 5, "DbLog $name: UPDATE $history SET TIMESTAMP=$updDate $updHour:30:00, EVENT='rl_av_h', VALUE=$average WHERE DEVICE=$hourHash->{$hourKey}->[1] AND READING=$hourHash->{$hourKey}->[3] AND TIMESTAMP=$hourHash->{$hourKey}->[0] AND VALUE=$hourHash->{$hourKey}->[4]->[0]");
                                            $sth_upd->execute(("$updDate $updHour:30:00", 'rl_av_h', $average, $hourHash->{$hourKey}->[1], $hourHash->{$hourKey}->[3], $hourHash->{$hourKey}->[0], $hourHash->{$hourKey}->[4]->[0]));
                                            
											$i++;
								            if($i == $th) {
								                my $prog = $k * $i; 
									            Log3($name, 3, "DbLog $name: reduceLog (hourly-average) updating progress of day: $processingDay is: $prog");
									            $i = 0;
									            $k++;
								            } 
											push(@averageUpdD, ["$updDate $updHour:30:00", 'rl_av_h', $average, $hourHash->{$hourKey}->[1], $hourHash->{$hourKey}->[3], $updDate]) if (defined($a[3]) && $a[3] =~ /average=day/i);
                                        } else {
                                            push(@averageUpdD, [$hourHash->{$hourKey}->[0], $hourHash->{$hourKey}->[2], $hourHash->{$hourKey}->[4]->[0], $hourHash->{$hourKey}->[1], $hourHash->{$hourKey}->[3], $updDate]) if (defined($a[3]) && $a[3] =~ /average=day/i);
                                        }
                                    } 
                                }
                            }
                        };
                        if ($@) {
                            $err = $@;
                            Log3($hash->{NAME}, 2, "DbLog $name - reduceLogNbl ! FAILED ! for day $processingDay: $err");
                            eval {$dbh->rollback() if(!$dbh->{AutoCommit});};
                            @averageUpdD = ();
                        } else {
                            eval {$dbh->commit() if(!$dbh->{AutoCommit});};
                        }
                        $dbh->{RaiseError} = 0; 
                        $dbh->{PrintError} = 1;
                        @averageUpd = ();
                    }
                    
                    if (defined($a[3]) && $a[3] =~ /average=day/i && scalar(@averageUpdD) && $day != 00) {
                        $dbh->{RaiseError} = 1;
                        $dbh->{PrintError} = 0;
                        eval {$dbh->begin_work() if($dbh->{AutoCommit});};
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
                                } else {
                                    $c += (scalar(@{$averageHash{$_}->{tedr}}) - 1);
                                }
                            }
                            $deletedCount += $c;
                            $updateCount += keys(%averageHash);
							
							my ($id,$iu) = 0;
							my ($kd,$ku) = 1;
							my $thd = ($c <= 2000)?100:($c <= 30000)?1000:10000;   
							my $thu = ((keys %averageHash) <= 2000)?100:((keys %averageHash) <= 30000)?1000:10000;							
                            Log3($name, 3, "DbLog $name: reduceLog (daily-average) updating ".(keys %averageHash).", deleting $c records of day: $processingDay") if(keys %averageHash);
                            for my $reading (keys %averageHash) {
                                $average = sprintf('%.3f', $averageHash{$reading}->{sum}/scalar(@{$averageHash{$reading}->{tedr}}));
                                $lastUpdH = pop @{$averageHash{$reading}->{tedr}};
                                for (@{$averageHash{$reading}->{tedr}}) {
                                    Log3($name, 5, "DbLog $name: DELETE FROM $history WHERE DEVICE='$_->[2]' AND READING='$_->[3]' AND TIMESTAMP='$_->[0]'");
                                    $sth_delD->execute(($_->[2], $_->[3], $_->[0]));
									
									$id++;
								    if($id == $thd) {
								        my $prog = $kd * $id; 
									    Log3($name, 3, "DbLog $name: reduceLog (daily-average) deleting progress of day: $processingDay is: $prog");
									    $id = 0;
									    $kd++;
								    }
                                }
                                Log3($name, 5, "DbLog $name: UPDATE $history SET TIMESTAMP=$averageHash{$reading}->{date} 12:00:00, EVENT='rl_av_d', VALUE=$average WHERE (DEVICE=$lastUpdH->[2]) AND (READING=$lastUpdH->[3]) AND (TIMESTAMP=$lastUpdH->[0])");
                                $sth_updD->execute(($averageHash{$reading}->{date}." 12:00:00", 'rl_av_d', $average, $lastUpdH->[2], $lastUpdH->[3], $lastUpdH->[0]));
                            
								$iu++;
								if($iu == $thu) {
								    my $prog = $ku * $id; 
									Log3($name, 3, "DbLog $name: reduceLog (daily-average) updating progress of day: $processingDay is: $prog");
									$iu = 0;
									$ku++;
								}							
							}
                        };
                        if ($@) {
                            $err = $@;
                            Log3($hash->{NAME}, 2, "DbLog $name - reduceLogNbl ! FAILED ! for day $processingDay: $err");
                            eval {$dbh->rollback() if(!$dbh->{AutoCommit});};
                        } else {
                            eval {$dbh->commit() if(!$dbh->{AutoCommit});};
                        }
                        $dbh->{RaiseError} = 0; 
                        $dbh->{PrintError} = 1;
                    }
                    %averageHash = ();
                    %hourlyKnown = ();
                    @averageUpd = ();
                    @averageUpdD = ();
                    $currentHour = 99;
                }
                $currentDay = $day;
            }
            
            if ($hour != $currentHour) { # forget records from last hour, but remember these for average
                if (defined($a[3]) && $a[3] =~ /average/i && keys(%hourlyKnown)) {
                    push(@averageUpd, {%hourlyKnown});
                }
                %hourlyKnown = ();
                $currentHour = $hour;
            }
            if (defined $hourlyKnown{$row->[1].$row->[3]}) { # remember first readings for device per h, other can be deleted
                push(@dayRows, [@$row]);
                if (defined($a[3]) && $a[3] =~ /average/i && defined($row->[4]) && $row->[4] =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/ && $hourlyKnown{$row->[1].$row->[3]}->[0]) {
                    if ($hourlyKnown{$row->[1].$row->[3]}->[0]) {
                        push(@{$hourlyKnown{$row->[1].$row->[3]}->[4]}, $row->[4]);
                    }
                }
            } else {
                $exclude = 0;
                for (@excludeRegex) {
                    $exclude = 1 if("$row->[1]:$row->[3]" =~ /^$_$/);
                }
                if ($exclude) {
                    $excludeCount++ if($day != 00);
                } else {
                    $hourlyKnown{$row->[1].$row->[3]} = (defined($row->[4]) && $row->[4] =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/) ? [$row->[0],$row->[1],$row->[2],$row->[3],[$row->[4]]] : [0];
                }
            }
            $processingDay = (split(' ',$row->[0]))[0];
        } while( $day != 00 );
        
        my $result = "Rows processed: $rowCount, deleted: $deletedCount"
                   .((defined($a[3]) && $a[3] =~ /average/i)? ", updated: $updateCount" : '')
                   .(($excludeCount)? ", excluded: $excludeCount" : '')
                   .", time: ".sprintf('%.2f',time() - $startTime)."sec";
        Log3($name, 3, "DbLog $name: reduceLog executed. $result");
		readingsSingleUpdate($hash,"reduceLogState",$result,1);
        $ret = "reduceLog executed. $result";
    }
    $dbh->disconnect(); 
    return $ret;
}

#########################################################################################
### DBLog - Historische Werte ausduennen non-blocking > Forum #41089
#########################################################################################
sub DbLog_reduceLogNbl($) {
    my ($name)     = @_;
    my $hash       = $defs{$name};
    my $dbconn     = $hash->{dbconn};
    my $dbuser     = $hash->{dbuser};
    my $dbpassword = $attr{"sec$name"}{secret};
    my @a          = @{$hash->{HELPER}{REDUCELOG}};
	my $utf8       = defined($hash->{UTF8})?$hash->{UTF8}:0;
    my $history    = $hash->{HELPER}{TH};
    my $current    = $hash->{HELPER}{TC};
    delete $hash->{HELPER}{REDUCELOG};
    my ($ret,$row,$filter,$exclude,$c,$day,$hour,$lastHour,$updDate,$updHour,$average,$processingDay,$lastUpdH,%hourlyKnown,%averageHash,@excludeRegex,@dayRows,@averageUpd,@averageUpdD);
    my ($startTime,$currentHour,$currentDay,$deletedCount,$updateCount,$sum,$rowCount,$excludeCount) = (time(),99,0,0,0,0,0,0);
    my ($dbh,$err);
	
	Log3 ($name, 5, "DbLog $name -> Start DbLog_reduceLogNbl");
	
    my ($useac,$useta) = DbLog_commitMode($hash);
    if(!$useac) {
        eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 0 });};
    } elsif($useac == 1) {
        eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1 });};
    } else {
        # Server default
        eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1 });};
    }
    if ($@) {
        $err = encode_base64($@,"");
        Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
        Log3 ($name, 5, "DbLog $name -> DbLog_reduceLogNbl finished");
        return "$name|''|$err";
    }
  
    if ($a[-1] =~ /^EXCLUDE=(.+:.+)+/i) {
        ($filter) = $a[-1] =~ /^EXCLUDE=(.+)/i;
        @excludeRegex = split(',',$filter);
    } elsif ($a[-1] =~ /^INCLUDE=.+:.+$/i) {
        $filter = 1;
    }
    if (defined($a[3])) {
        $average = ($a[3] =~ /average=day/i) ? "AVERAGE=DAY" : ($a[3] =~ /average/i) ? "AVERAGE=HOUR" : 0;
    }
    
    Log3($name, 3, "DbLog $name: reduceLogNbl requested with DAYS=$a[2]"
        .(($average || $filter) ? ', ' : '').(($average) ? "$average" : '')
        .(($average && $filter) ? ", " : '').(($filter) ? uc((split('=',$a[-1]))[0]).'='.(split('=',$a[-1]))[1] : ''));
    
    my $ac = ($dbh->{AutoCommit})?"ON":"OFF";
    my $tm = ($useta)?"ON":"OFF";
    Log3 $hash->{NAME}, 4, "DbLog $name -> AutoCommit mode: $ac, Transaction mode: $tm";

    my ($od,$nd) = split(":",$a[2]);         # $od - Tage älter als , $nd - Tage neuer als
    my ($ots,$nts);
    if ($hash->{MODEL} eq 'SQLITE') { 
        $ots = "datetime('now', '-$od days')";
        $nts = "datetime('now', '-$nd days')" if($nd);
    } elsif ($hash->{MODEL} eq 'MYSQL') { 
        $ots = "DATE_SUB(CURDATE(),INTERVAL $od DAY)"; 
        $nts = "DATE_SUB(CURDATE(),INTERVAL $nd DAY)" if($nd); 
    } elsif ($hash->{MODEL} eq 'POSTGRESQL') { 
        $ots = "NOW() - INTERVAL '$od' DAY"; 
        $nts = "NOW() - INTERVAL '$nd' DAY" if($nd);
    } else { 
        $ret = 'Unknown database type.'; 
    }
    
    if ($ots) {
	    my ($sth_del, $sth_upd, $sth_delD, $sth_updD, $sth_get);
        eval { $sth_del  = $dbh->prepare_cached("DELETE FROM $history WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?) AND (VALUE=?)");
               $sth_upd  = $dbh->prepare_cached("UPDATE $history SET TIMESTAMP=?, EVENT=?, VALUE=? WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?) AND (VALUE=?)");
               $sth_delD = $dbh->prepare_cached("DELETE FROM $history WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?)");
               $sth_updD = $dbh->prepare_cached("UPDATE $history SET TIMESTAMP=?, EVENT=?, VALUE=? WHERE (DEVICE=?) AND (READING=?) AND (TIMESTAMP=?)");
               $sth_get  = $dbh->prepare("SELECT TIMESTAMP,DEVICE,'',READING,VALUE FROM $history WHERE "
                           .($a[-1] =~ /^INCLUDE=(.+):(.+)$/i ? "DEVICE like '$1' AND READING like '$2' AND " : '')
                           ."TIMESTAMP < $ots".($nts?" AND TIMESTAMP >= $nts ":" ")."ORDER BY TIMESTAMP ASC");  # '' was EVENT, no longer in use
		     };
        if ($@) {
            $err = encode_base64($@,"");
            Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
            Log3 ($name, 5, "DbLog $name -> DbLog_reduceLogNbl finished");
            return "$name|''|$err";
        }
		
		eval { $sth_get->execute(); };
        if ($@) {
            $err = encode_base64($@,"");
            Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
            Log3 ($name, 5, "DbLog $name -> DbLog_reduceLogNbl finished");
            return "$name|''|$err";
        }
        
        do {
            $row = $sth_get->fetchrow_arrayref || ['0000-00-00 00:00:00','D','','R','V'];  # || execute last-day dummy
            $ret = 1;
            ($day,$hour) = $row->[0] =~ /-(\d{2})\s(\d{2}):/;
            $rowCount++ if($day != 00);
            if ($day != $currentDay) {
                if ($currentDay) { # false on first executed day
                    if (scalar @dayRows) {
                        ($lastHour) = $dayRows[-1]->[0] =~ /(.*\d+\s\d{2}):/;
                        $c = 0;
                        for my $delRow (@dayRows) {
                            $c++ if($day != 00 || $delRow->[0] !~ /$lastHour/);
                        }
                        if($c) {
                            $deletedCount += $c;
                            Log3($name, 3, "DbLog $name: reduceLogNbl deleting $c records of day: $processingDay");
                            $dbh->{RaiseError} = 1;
                            $dbh->{PrintError} = 0; 
                            eval {$dbh->begin_work() if($dbh->{AutoCommit});};
						    if ($@) {
                                Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
                            }
                            eval {
							    my $i = 0;
								my $k = 1;
								my $th = ($#dayRows <= 2000)?100:($#dayRows <= 30000)?1000:10000;
                                for my $delRow (@dayRows) {
                                    if($day != 00 || $delRow->[0] !~ /$lastHour/) {
                                        Log3($name, 4, "DbLog $name: DELETE FROM $history WHERE (DEVICE=$delRow->[1]) AND (READING=$delRow->[3]) AND (TIMESTAMP=$delRow->[0]) AND (VALUE=$delRow->[4])");
                                        $sth_del->execute(($delRow->[1], $delRow->[3], $delRow->[0], $delRow->[4]));
										$i++;
										if($i == $th) {
										    my $prog = $k * $i; 
										    Log3($name, 3, "DbLog $name: reduceLogNbl deletion progress of day: $processingDay is: $prog");
											$i = 0;
											$k++;
										}
                                    }
                                }
                            };
                            if ($@) {
                                $err = $@;
                                Log3($hash->{NAME}, 2, "DbLog $name - reduceLogNbl ! FAILED ! for day $processingDay: $err");
                                eval {$dbh->rollback() if(!$dbh->{AutoCommit});};
								if ($@) {
                                    Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
                                }
                                $ret = 0;
                            } else {
                                eval {$dbh->commit() if(!$dbh->{AutoCommit});};
								if ($@) {
                                    Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
                                }
                            }
                            $dbh->{RaiseError} = 0; 
                            $dbh->{PrintError} = 1;
                        }
                        @dayRows = ();
                    }
                    
                    if ($ret && defined($a[3]) && $a[3] =~ /average/i) {
                        $dbh->{RaiseError} = 1;
                        $dbh->{PrintError} = 0; 
                        eval {$dbh->begin_work() if($dbh->{AutoCommit});};
						if ($@) {
                            Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
                        }
                        eval {
                            push(@averageUpd, {%hourlyKnown}) if($day != 00);
                            
                            $c = 0;
                            for my $hourHash (@averageUpd) {  # Only count for logging...
                                for my $hourKey (keys %$hourHash) {
                                    $c++ if ($hourHash->{$hourKey}->[0] && scalar(@{$hourHash->{$hourKey}->[4]}) > 1);
                                }
                            }
                            $updateCount += $c;
                            Log3($name, 3, "DbLog $name: reduceLogNbl (hourly-average) updating $c records of day: $processingDay") if($c); # else only push to @averageUpdD
                            
							my $i = 0;
							my $k = 1;
							my $th = ($c <= 2000)?100:($c <= 30000)?1000:10000;
                            for my $hourHash (@averageUpd) {
                                for my $hourKey (keys %$hourHash) {
                                    if ($hourHash->{$hourKey}->[0]) { # true if reading is a number 
                                        ($updDate,$updHour) = $hourHash->{$hourKey}->[0] =~ /(.*\d+)\s(\d{2}):/;
                                        if (scalar(@{$hourHash->{$hourKey}->[4]}) > 1) {  # true if reading has multiple records this hour
                                            for (@{$hourHash->{$hourKey}->[4]}) { $sum += $_; }
                                            $average = sprintf('%.3f', $sum/scalar(@{$hourHash->{$hourKey}->[4]}) );
                                            $sum = 0;
                                            Log3($name, 4, "DbLog $name: UPDATE $history SET TIMESTAMP=$updDate $updHour:30:00, EVENT='rl_av_h', VALUE=$average WHERE DEVICE=$hourHash->{$hourKey}->[1] AND READING=$hourHash->{$hourKey}->[3] AND TIMESTAMP=$hourHash->{$hourKey}->[0] AND VALUE=$hourHash->{$hourKey}->[4]->[0]");
                                            $sth_upd->execute(("$updDate $updHour:30:00", 'rl_av_h', $average, $hourHash->{$hourKey}->[1], $hourHash->{$hourKey}->[3], $hourHash->{$hourKey}->[0], $hourHash->{$hourKey}->[4]->[0]));
			                                
											$i++;
								            if($i == $th) {
								                my $prog = $k * $i; 
									            Log3($name, 3, "DbLog $name: reduceLogNbl (hourly-average) updating progress of day: $processingDay is: $prog");
									            $i = 0;
									            $k++;
								            } 
                                            push(@averageUpdD, ["$updDate $updHour:30:00", 'rl_av_h', $average, $hourHash->{$hourKey}->[1], $hourHash->{$hourKey}->[3], $updDate]) if (defined($a[3]) && $a[3] =~ /average=day/i);
                                        } else {
                                            push(@averageUpdD, [$hourHash->{$hourKey}->[0], $hourHash->{$hourKey}->[2], $hourHash->{$hourKey}->[4]->[0], $hourHash->{$hourKey}->[1], $hourHash->{$hourKey}->[3], $updDate]) if (defined($a[3]) && $a[3] =~ /average=day/i);
                                        }
                                    }                              							
								}
                            }
                        };
                        if ($@) {
                            $err = $@;
                            Log3($hash->{NAME}, 2, "DbLog $name - reduceLogNbl average=hour ! FAILED ! for day $processingDay: $err");
                            eval {$dbh->rollback() if(!$dbh->{AutoCommit});};
							if ($@) {
                                Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
                            }
                            @averageUpdD = ();
                        } else {
                            eval {$dbh->commit() if(!$dbh->{AutoCommit});};
							if ($@) {
                                Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
                            }							
                        }
                        $dbh->{RaiseError} = 0; 
                        $dbh->{PrintError} = 1;
                        @averageUpd = ();
                    }
                    
                    if (defined($a[3]) && $a[3] =~ /average=day/i && scalar(@averageUpdD) && $day != 00) {
                        $dbh->{RaiseError} = 1;
                        $dbh->{PrintError} = 0;
                        eval {$dbh->begin_work() if($dbh->{AutoCommit});};
						if ($@) {
                            Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
                        }
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
                                } else {
                                    $c += (scalar(@{$averageHash{$_}->{tedr}}) - 1);
                                }
                            }
                            $deletedCount += $c;
                            $updateCount += keys(%averageHash);
                            
							my ($id,$iu) = 0;
							my ($kd,$ku) = 1;
							my $thd = ($c <= 2000)?100:($c <= 30000)?1000:10000;
							my $thu = ((keys %averageHash) <= 2000)?100:((keys %averageHash) <= 30000)?1000:10000;
                            Log3($name, 3, "DbLog $name: reduceLogNbl (daily-average) updating ".(keys %averageHash).", deleting $c records of day: $processingDay") if(keys %averageHash);
                            for my $reading (keys %averageHash) {
                                $average = sprintf('%.3f', $averageHash{$reading}->{sum}/scalar(@{$averageHash{$reading}->{tedr}}));
                                $lastUpdH = pop @{$averageHash{$reading}->{tedr}};
                                for (@{$averageHash{$reading}->{tedr}}) {
                                    Log3($name, 5, "DbLog $name: DELETE FROM $history WHERE DEVICE='$_->[2]' AND READING='$_->[3]' AND TIMESTAMP='$_->[0]'");
                                    $sth_delD->execute(($_->[2], $_->[3], $_->[0]));
							        
									$id++;
								    if($id == $thd) {
								        my $prog = $kd * $id; 
									    Log3($name, 3, "DbLog $name: reduceLogNbl (daily-average) deleting progress of day: $processingDay is: $prog");
									    $id = 0;
									    $kd++;
								    }
                                }
                                Log3($name, 4, "DbLog $name: UPDATE $history SET TIMESTAMP=$averageHash{$reading}->{date} 12:00:00, EVENT='rl_av_d', VALUE=$average WHERE (DEVICE=$lastUpdH->[2]) AND (READING=$lastUpdH->[3]) AND (TIMESTAMP=$lastUpdH->[0])");
                                $sth_updD->execute(($averageHash{$reading}->{date}." 12:00:00", 'rl_av_d', $average, $lastUpdH->[2], $lastUpdH->[3], $lastUpdH->[0]));
							
								$iu++;
								if($iu == $thu) {
								    my $prog = $ku * $id; 
									Log3($name, 3, "DbLog $name: reduceLogNbl (daily-average) updating progress of day: $processingDay is: $prog");
									$iu = 0;
									$ku++;
								}							
							}
                        };
                        if ($@) {
                            Log3($hash->{NAME}, 3, "DbLog $name: reduceLogNbl average=day ! FAILED ! for day $processingDay");
                            eval {$dbh->rollback() if(!$dbh->{AutoCommit});};
							if ($@) {
                                Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
                            }
                        } else {
                            eval {$dbh->commit() if(!$dbh->{AutoCommit});};
							if ($@) {
                                Log3 ($name, 2, "DbLog $name -> DbLog_reduceLogNbl - $@");
                            }
                        }
                        $dbh->{RaiseError} = 0; 
                        $dbh->{PrintError} = 1;
                    }
                    %averageHash = ();
                    %hourlyKnown = ();
                    @averageUpd = ();
                    @averageUpdD = ();
                    $currentHour = 99;
                }
                $currentDay = $day;
            }
            
            if ($hour != $currentHour) { # forget records from last hour, but remember these for average
                if (defined($a[3]) && $a[3] =~ /average/i && keys(%hourlyKnown)) {
                    push(@averageUpd, {%hourlyKnown});
                }
                %hourlyKnown = ();
                $currentHour = $hour;
            }
            if (defined $hourlyKnown{$row->[1].$row->[3]}) { # remember first readings for device per h, other can be deleted
                push(@dayRows, [@$row]);
                if (defined($a[3]) && $a[3] =~ /average/i && defined($row->[4]) && $row->[4] =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/ && $hourlyKnown{$row->[1].$row->[3]}->[0]) {
                    if ($hourlyKnown{$row->[1].$row->[3]}->[0]) {
                        push(@{$hourlyKnown{$row->[1].$row->[3]}->[4]}, $row->[4]);
                    }
                }
            } else {
                $exclude = 0;
                for (@excludeRegex) {
                    $exclude = 1 if("$row->[1]:$row->[3]" =~ /^$_$/);
                }
                if ($exclude) {
                    $excludeCount++ if($day != 00);
                } else {
                    $hourlyKnown{$row->[1].$row->[3]} = (defined($row->[4]) && $row->[4] =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/) ? [$row->[0],$row->[1],$row->[2],$row->[3],[$row->[4]]] : [0];
                }
            }
            $processingDay = (split(' ',$row->[0]))[0];
        } while( $day != 00 );
        
        my $result = "Rows processed: $rowCount, deleted: $deletedCount"
                   .((defined($a[3]) && $a[3] =~ /average/i)? ", updated: $updateCount" : '')
                   .(($excludeCount)? ", excluded: $excludeCount" : '')
                   .", time: ".sprintf('%.2f',time() - $startTime)."sec";
        Log3($name, 3, "DbLog $name: reduceLogNbl finished. $result");
        $ret = $result;
        $ret = "reduceLogNbl finished. $result";
    }
    
	$dbh->disconnect();
    $ret = encode_base64($ret,"");
	Log3 ($name, 5, "DbLog $name -> DbLog_reduceLogNbl finished");
	
return "$name|$ret|0";
}

#########################################################################################
# DBLog - reduceLogNbl non-blocking Rückkehrfunktion
#########################################################################################
sub DbLog_reduceLogNbl_finished($) {
  my ($string)    = @_;
  my @a           = split("\\|",$string);
  my $name        = $a[0];
  my $hash        = $defs{$name};
  my $ret         = decode_base64($a[1]);
  my $err         = decode_base64($a[2]) if ($a[2]);
  
  readingsSingleUpdate($hash,"reduceLogState",$err?$err:$ret,1);
  delete $hash->{HELPER}{REDUCELOG_PID};
return;
}

#########################################################################################
# DBLog - count non-blocking
#########################################################################################
sub DbLog_countNbl($) {
  my ($name)  = @_;
  my $hash    = $defs{$name};
  my $history = $hash->{HELPER}{TH};
  my $current = $hash->{HELPER}{TC};
  my ($cc,$hc,$bst,$st,$rt);
  
  # Background-Startzeit
  $bst = [gettimeofday];
  
  my $dbh = DbLog_ConnectNewDBH($hash);
  if (!$dbh) {
    my $err = encode_base64("DbLog $name: DBLog_Set - count - DB connect not possible","");
    return "$name|0|0|$err|0";
  } else {
    Log3 $name,4,"DbLog $name: Records count requested.";
	# SQL-Startzeit
    $st = [gettimeofday];
    $hc = $dbh->selectrow_array("SELECT count(*) FROM $history");
    $cc = $dbh->selectrow_array("SELECT count(*) FROM $current");
    $dbh->disconnect();
	# SQL-Laufzeit ermitteln
    $rt = tv_interval($st);
  }
  
  # Background-Laufzeit ermitteln
  my $brt = tv_interval($bst);
  $rt = $rt.",".$brt;
return "$name|$cc|$hc|0|$rt";
}

#########################################################################################
# DBLog - count non-blocking Rückkehrfunktion
#########################################################################################
sub DbLog_countNbl_finished($) {
  my ($string) = @_;
  my @a        = split("\\|",$string);
  my $name     = $a[0];
  my $hash     = $defs{$name};
  my $cc       = $a[1];
  my $hc       = $a[2];
  my $err      = decode_base64($a[3]) if ($a[3]);
  my $bt       = $a[4] if($a[4]);  

  readingsSingleUpdate($hash,"state",$err,1) if($err);
  readingsSingleUpdate($hash,"countHistory",$hc,1) if ($hc);
  readingsSingleUpdate($hash,"countCurrent",$cc,1) if ($cc);
  
  if(AttrVal($name, "showproctime", undef) && $bt) {
      my ($rt,$brt)  = split(",", $bt);
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt));     
      readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt));
      readingsEndUpdate($hash, 1);
  }
  delete $hash->{HELPER}{COUNT_PID};
  
return;
}

#########################################################################################
# DBLog - deleteOldDays non-blocking
#########################################################################################
sub DbLog_deldaysNbl($) {
  my ($name)     = @_;
  my $hash       = $defs{$name};
  my $dbconn     = $hash->{dbconn};
  my $dbuser     = $hash->{dbuser};
  my $dbpassword = $attr{"sec$name"}{secret};
  my $days       = delete($hash->{HELPER}{DELDAYS});
  my $history    = $hash->{HELPER}{TH};
  my $current    = $hash->{HELPER}{TC};
  my ($cmd,$dbh,$rows,$error,$sth,$ret,$bst,$brt,$st,$rt);
  
  Log3 ($name, 5, "DbLog $name -> Start DbLog_deldaysNbl $days");
  
  # Background-Startzeit
  $bst = [gettimeofday];

  my ($useac,$useta) = DbLog_commitMode($hash);
  if(!$useac) {
      eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 0 });};
  } elsif($useac == 1) {
      eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1 });};
  } else {
      # Server default
      eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1 });};
  }
  if ($@) {
      $error = encode_base64($@,"");
      Log3 ($name, 2, "DbLog $name - Error: $@");
      Log3 ($name, 5, "DbLog $name -> DbLog_deldaysNbl finished");
      return "$name|0|0|$error"; 
  }
  
  my $ac = ($dbh->{AutoCommit})?"ON":"OFF";
  my $tm = ($useta)?"ON":"OFF";
  Log3 $hash->{NAME}, 4, "DbLog $name -> AutoCommit mode: $ac, Transaction mode: $tm";
  
  $cmd = "delete from $history where TIMESTAMP < ";
  if ($hash->{MODEL} eq 'SQLITE') { 
      $cmd .= "datetime('now', '-$days days')"; 
  } elsif ($hash->{MODEL} eq 'MYSQL') { 
      $cmd .= "DATE_SUB(CURDATE(),INTERVAL $days DAY)"; 
  } elsif ($hash->{MODEL} eq 'POSTGRESQL') { 
      $cmd .= "NOW() - INTERVAL '$days' DAY"; 
  } else {  
	  $ret = 'Unknown database type. Maybe you can try userCommand anyway.';
	  $error = encode_base64($ret,"");
	  Log3 ($name, 2, "DbLog $name - Error: $ret");
      Log3 ($name, 5, "DbLog $name -> DbLog_deldaysNbl finished");
      return "$name|0|0|$error";  
  }
  
  # SQL-Startzeit
  $st = [gettimeofday];
    
  eval { 
      $sth = $dbh->prepare($cmd); 
      $sth->execute();
  };

  if ($@) {
      $error = encode_base64($@,"");
      Log3 ($name, 2, "DbLog $name - $@");
      $dbh->disconnect;
      Log3 ($name, 4, "DbLog $name -> BlockingCall DbLog_deldaysNbl finished");
      return "$name|0|0|$error"; 
 } else {
     $rows = $sth->rows;
     $dbh->commit() if(!$dbh->{AutoCommit});
     $dbh->disconnect;
 } 

 # SQL-Laufzeit ermitteln
 $rt = tv_interval($st);

 # Background-Laufzeit ermitteln
 $brt = tv_interval($bst);
 $rt = $rt.",".$brt;
  
  Log3 ($name, 5, "DbLog $name -> DbLog_deldaysNbl finished");
return "$name|$rows|$rt|0"; 
}

#########################################################################################
# DBLog - deleteOldDays non-blocking Rückkehrfunktion
#########################################################################################
sub DbLog_deldaysNbl_done($) {
  my ($string) = @_;
  my @a        = split("\\|",$string);
  my $name     = $a[0];
  my $hash     = $defs{$name};
  my $rows     = $a[1];
  my $bt       = $a[2] if($a[2]); 
  my $err      = decode_base64($a[3]) if ($a[3]);
 
  Log3 ($name, 5, "DbLog $name -> Start DbLog_deldaysNbl_done");
  
  if ($err) {
      readingsSingleUpdate($hash,"state",$err,1);
	  delete $hash->{HELPER}{DELDAYS_PID};
      Log3 ($name, 5, "DbLog $name -> DbLog_deldaysNbl_done finished");
      return;
  } else {
      if(AttrVal($name, "showproctime", undef) && $bt) {
          my ($rt,$brt)  = split(",", $bt);
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt));     
          readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt));
          readingsEndUpdate($hash, 1);
	  }
	  readingsSingleUpdate($hash, "lastRowsDeleted", $rows ,1);
  }
  my $db = (split(/;|=/, $hash->{dbconn}))[1];
  Log3 ($name, 3, "DbLog $name -> deleteOldDaysNbl finished. $rows entries of database $db deleted.");
  delete $hash->{HELPER}{DELDAYS_PID};
  Log3 ($name, 5, "DbLog $name -> DbLog_deldaysNbl_done finished");
return;
}

################################################################
# benutzte DB-Feldlängen in Helper und Internals setzen
################################################################
sub DbLog_setinternalcols ($){
  my ($hash)= @_;
  my $name = $hash->{NAME};

  $hash->{HELPER}{DEVICECOL}   = $columns{DEVICE};
  $hash->{HELPER}{TYPECOL}     = $columns{TYPE};
  $hash->{HELPER}{EVENTCOL}    = AttrVal($name, "colEvent", $columns{EVENT});
  $hash->{HELPER}{READINGCOL}  = AttrVal($name, "colReading", $columns{READING});
  $hash->{HELPER}{VALUECOL}    = AttrVal($name, "colValue", $columns{VALUE});
  $hash->{HELPER}{UNITCOL}     = $columns{UNIT};
  
  $hash->{COLUMNS} = "field length used for Device: $hash->{HELPER}{DEVICECOL}, Type: $hash->{HELPER}{TYPECOL}, Event: $hash->{HELPER}{EVENTCOL}, Reading: $hash->{HELPER}{READINGCOL}, Value: $hash->{HELPER}{VALUECOL}, Unit: $hash->{HELPER}{UNITCOL} ";

  # Statusbit "Columns sind gesetzt"
  $hash->{HELPER}{COLSET} = 1;

return;
}

################################################################
# reopen DB-Connection nach Ablauf set ... reopen [n] seconds
################################################################
sub DbLog_reopen ($){
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  my $async  = AttrVal($name, "asyncMode", undef);
  
  RemoveInternalTimer($hash, "DbLog_reopen");
  
  if(DbLog_ConnectPush($hash)) {
      # Statusbit "Kein Schreiben in DB erlauben" löschen
      my $delay = delete $hash->{HELPER}{REOPEN_RUNS};
      delete $hash->{HELPER}{REOPEN_RUNS_UNTIL};
	  Log3($name, 2, "DbLog $name: Database connection reopened (it was $delay seconds closed).") if($delay);
	  readingsSingleUpdate($hash, "state", "reopened", 1);
	  $hash->{HELPER}{OLDSTATE} = "reopened";
	  DbLog_execmemcache($hash) if($async);
  } else {
      InternalTimer(gettimeofday()+30, "DbLog_reopen", $hash, 0);		
  }
  
return;
}

################################################################
# check ob primary key genutzt wird
################################################################
sub DbLog_checkUsePK ($$){
  my ($hash,$dbh) = @_;
  my $name    = $hash->{NAME};
  my $dbconn  = $hash->{dbconn};
  my $history = $hash->{HELPER}{TH};
  my $current = $hash->{HELPER}{TC};
  my $upkh = 0;
  my $upkc = 0;
  my (@pkh,@pkc);
  
  my $db = (split("=",(split(";",$dbconn))[0]))[1];
  eval {@pkh = $dbh->primary_key( undef, undef, 'history' );};
  eval {@pkc = $dbh->primary_key( undef, undef, 'current' );};
  my $pkh = (!@pkh || @pkh eq "")?"none":join(",",@pkh);
  my $pkc = (!@pkc || @pkc eq "")?"none":join(",",@pkc);
  $pkh =~ tr/"//d;
  $pkc =~ tr/"//d;
  $upkh = 1 if(@pkh && @pkh ne "none");
  $upkc = 1 if(@pkc && @pkc ne "none");
  Log3 $hash->{NAME}, 4, "DbLog $name -> Primary Key used in $history: $pkh";
  Log3 $hash->{NAME}, 4, "DbLog $name -> Primary Key used in $current: $pkc";

return ($upkh,$upkc,$pkh,$pkc);
}

################################################################
#  Routine für FHEMWEB Detailanzeige
################################################################
sub DbLog_fhemwebFn($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.

  my $ret;
  my $newIdx=1;
  while($defs{"SVG_${d}_$newIdx"}) {
      $newIdx++;
  }
  my $name = "SVG_${d}_$newIdx";
  $ret .= FW_pH("cmd=define $name SVG $d:templateDB:HISTORY;".
                 "set $name copyGplotFile&detail=$name",
                 "<div class=\"dval\">Create SVG plot from DbLog</div>", 0, "dval", 1);
return $ret;
}

################################################################
#  Dropdown-Menü cuurent-Tabelle SVG-Editor
################################################################
sub DbLog_sampleDataFn($$$$$) {
  my ($dlName, $dlog, $max, $conf, $wName) = @_;
  my $desc    = "Device:Reading";
  my $hash    = $defs{$dlName};
  my $current = $hash->{HELPER}{TC};
  my @htmlArr;
  my @example;
  my @colregs;
  my $counter;
  my $currentPresent = AttrVal($dlName,'DbLogType','History');  
  
  my $dbhf = DbLog_ConnectNewDBH($defs{$dlName});
  return if(!$dbhf);

  # check presence of table current
  # avoids fhem from crash if table 'current' is not present and attr DbLogType is set to /Current/
  my $prescurr = eval {$dbhf->selectrow_array("select count(*) from $current");} || 0;
  Log3($dlName, 5, "DbLog $dlName: Table $current present : $prescurr (0 = not present or no content)");
  
  if($currentPresent =~ m/Current|SampleFill/ && $prescurr) {
    # Table Current present, use it for sample data
    my $query = "select device,reading from $current where device <> '' group by device,reading";
    my $sth = $dbhf->prepare( $query );  
    $sth->execute();
    while (my @line = $sth->fetchrow_array()) {
      $counter++;
      push (@example, join (" ",@line)) if($counter <= 8);   # show max 8 examples
      push (@colregs, "$line[0]:$line[1]");                  # push all eventTypes to selection list
    }
	$dbhf->disconnect(); 
    my $cols = join(",", sort { "\L$a" cmp "\L$b" } @colregs);

    # $max = 8 if($max > 8);                                 # auskommentiert 27.02.2018, Notwendigkeit unklar (forum:#76008)
    for(my $r=0; $r < $max; $r++) {
      my @f = split(":", ($dlog->[$r] ? $dlog->[$r] : ":::"), 4);
      my $ret = "";
      $ret .= SVG_sel("par_${r}_0", $cols, "$f[0]:$f[1]");
#      $ret .= SVG_txt("par_${r}_2", "", $f[2], 1); # Default not yet implemented
#      $ret .= SVG_txt("par_${r}_3", "", $f[3], 3); # Function
#      $ret .= SVG_txt("par_${r}_4", "", $f[4], 3); # RegExp
      push @htmlArr, $ret;
    }

  } else {
  # Table Current not present, so create an empty input field
    push @example, "No sample data due to missing table '$current'";

    # $max = 8 if($max > 8);                                 # auskommentiert 27.02.2018, Notwendigkeit unklar (forum:#76008)
    for(my $r=0; $r < $max; $r++) {
      my @f = split(":", ($dlog->[$r] ? $dlog->[$r] : ":::"), 4);
      my $ret = "";
      no warnings 'uninitialized';                           # Forum:74690, bug unitialized
      $ret .= SVG_txt("par_${r}_0", "", "$f[0]:$f[1]:$f[2]:$f[3]", 20);   
	  use warnings;
#      $ret .= SVG_txt("par_${r}_2", "", $f[2], 1); # Default not yet implemented
#      $ret .= SVG_txt("par_${r}_3", "", $f[3], 3); # Function
#      $ret .= SVG_txt("par_${r}_4", "", $f[4], 3); # RegExp
      push @htmlArr, $ret;
    }

  }

return ($desc, \@htmlArr, join("<br>", @example));
}

################################################################
#
# Charting Specific functions start here
#
################################################################

################################################################
#
# Error handling, returns a JSON String
#
################################################################
sub DbLog_jsonError($) {
  my $errormsg = $_[0]; 
  my $json = '{"success": "false", "msg":"'.$errormsg.'"}';
  return $json;
}


################################################################
#
# Prepare the SQL String
#
################################################################
sub DbLog_prepareSql(@) {
    my ($hash, @a) = @_;
    my $starttime       = $_[5];
    $starttime          =~ s/_/ /;
    my $endtime         = $_[6];
    $endtime            =~ s/_/ /;
    my $device          = $_[7];
    my $userquery       = $_[8];
    my $xaxis           = $_[9]; 
    my $yaxis           = $_[10]; 
    my $savename        = $_[11]; 
    my $jsonChartConfig = $_[12];
    my $pagingstart     = $_[13]; 
    my $paginglimit     = $_[14]; 
    my $dbmodel         = $hash->{MODEL};
    my $history         = $hash->{HELPER}{TH};
    my $current         = $hash->{HELPER}{TC};
    my ($sql, $jsonstring, $countsql, $hourstats, $daystats, $weekstats, $monthstats, $yearstats);

    if ($dbmodel eq "POSTGRESQL") {
        ### POSTGRESQL Queries for Statistics ###
        ### hour:
        $hourstats = "SELECT to_char(timestamp, 'YYYY-MM-DD HH24:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $hourstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $hourstats .= "COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $hourstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### day:
        $daystats = "SELECT to_char(timestamp, 'YYYY-MM-DD 00:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $daystats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $daystats .= "COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $daystats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### week:
        $weekstats = "SELECT date_trunc('week',timestamp) AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $weekstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $weekstats .= "COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $weekstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### month:
        $monthstats = "SELECT to_char(timestamp, 'YYYY-MM-01 00:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $monthstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $monthstats .= "COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $monthstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### year:
        $yearstats = "SELECT to_char(timestamp, 'YYYY-01-01 00:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $yearstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $yearstats .= "COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $yearstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";
   
    } elsif ($dbmodel eq "MYSQL") {
        ### MYSQL Queries for Statistics ###
        ### hour:
        $hourstats = "SELECT date_format(timestamp, '%Y-%m-%d %H:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $hourstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $hourstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' ";
        $hourstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### day:
        $daystats = "SELECT date_format(timestamp, '%Y-%m-%d 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $daystats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $daystats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' ";
        $daystats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### week:
        $weekstats = "SELECT date_format(timestamp, '%Y-%m-%d 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $weekstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $weekstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' ";
        $weekstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' ";
        $weekstats .= "GROUP BY date_format(timestamp, '%Y-%u 00:00:00') ORDER BY 1;";

        ### month:
        $monthstats = "SELECT date_format(timestamp, '%Y-%m-01 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $monthstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $monthstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' ";
        $monthstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### year:
        $yearstats = "SELECT date_format(timestamp, '%Y-01-01 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $yearstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $yearstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM $history WHERE READING = '$yaxis' ";
        $yearstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

    } elsif ($dbmodel eq "SQLITE") {
        ### SQLITE Queries for Statistics ###
        ### hour:
        $hourstats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $hourstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $hourstats .= "FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $hourstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%m-%d %H:00:00', TIMESTAMP);";
  
        ### day:
        $daystats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $daystats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $daystats .= "FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $daystats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%m-%d 00:00:00', TIMESTAMP);";

        ### week:
        $weekstats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $weekstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $weekstats .= "FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $weekstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%W 00:00:00', TIMESTAMP);";

        ### month:
        $monthstats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $monthstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $monthstats .= "FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $monthstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%m 00:00:00', TIMESTAMP);";

        ### year:
        $yearstats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $yearstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $yearstats .= "FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $yearstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y 00:00:00', TIMESTAMP);";

    } else {
        $sql = "errordb";
    }

    if($userquery eq "getreadings") {
        $sql = "SELECT distinct(reading) FROM $history WHERE device = '".$device."'";
    } elsif($userquery eq "getdevices") {
        $sql = "SELECT distinct(device) FROM $history";
    } elsif($userquery eq "timerange") {
        $sql = "SELECT ".$xaxis.", VALUE FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' ORDER BY TIMESTAMP;";
    } elsif($userquery eq "hourstats") {
        $sql = $hourstats;
    } elsif($userquery eq "daystats") {
        $sql = $daystats;
    } elsif($userquery eq "weekstats") {
        $sql = $weekstats;
    } elsif($userquery eq "monthstats") {
        $sql = $monthstats;
    } elsif($userquery eq "yearstats") {
        $sql = $yearstats;
    } elsif($userquery eq "savechart") {
        $sql = "INSERT INTO frontend (TYPE, NAME, VALUE) VALUES ('savedchart', '$savename', '$jsonChartConfig')";
    } elsif($userquery eq "renamechart") {
        $sql = "UPDATE frontend SET NAME = '$savename' WHERE ID = '$jsonChartConfig'";
    } elsif($userquery eq "deletechart") {
        $sql = "DELETE FROM frontend WHERE TYPE = 'savedchart' AND ID = '".$savename."'";
    } elsif($userquery eq "updatechart") {
        $sql = "UPDATE frontend SET VALUE = '$jsonChartConfig' WHERE ID = '".$savename."'";
    } elsif($userquery eq "getcharts") {
        $sql = "SELECT * FROM frontend WHERE TYPE = 'savedchart'";
    } elsif($userquery eq "getTableData") {
        if ($device ne '""' && $yaxis ne '""') {
            $sql = "SELECT * FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
            $sql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
            $sql .= " LIMIT '$paginglimit' OFFSET '$pagingstart'"; 
            $countsql = "SELECT count(*) FROM $history WHERE READING = '$yaxis' AND DEVICE = '$device' "; 
            $countsql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'"; 
        } elsif($device ne '""' && $yaxis eq '""') {  
            $sql = "SELECT * FROM $history WHERE DEVICE = '$device' ";
            $sql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
            $sql .= " LIMIT '$paginglimit' OFFSET '$pagingstart'";
            $countsql = "SELECT count(*) FROM $history WHERE DEVICE = '$device' ";
            $countsql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
        } else {
            $sql = "SELECT * FROM $history";
            $sql .= " WHERE TIMESTAMP Between '$starttime' AND '$endtime'"; 
            $sql .= " LIMIT '$paginglimit' OFFSET '$pagingstart'";
            $countsql = "SELECT count(*) FROM $history"; 
            $countsql .= " WHERE TIMESTAMP Between '$starttime' AND '$endtime'"; 
        }
        return ($sql, $countsql);
    } else {
        $sql = "error";
    }

    return $sql;
}

################################################################
#
# Do the query
#
################################################################
sub DbLog_chartQuery($@) {

    my ($sql, $countsql) = DbLog_prepareSql(@_);

    if ($sql eq "error") {
       return DbLog_jsonError("Could not setup SQL String. Maybe the Database is busy, please try again!");
    } elsif ($sql eq "errordb") {
       return DbLog_jsonError("The Database Type is not supported!");
    }

    my ($hash, @a) = @_;
	my $dbhf = DbLog_ConnectNewDBH($hash);
    return if(!$dbhf);

    my $totalcount;
    
    if (defined $countsql && $countsql ne "") {
        my $query_handle = $dbhf->prepare($countsql) 
        or return DbLog_jsonError("Could not prepare statement: " . $dbhf->errstr . ", SQL was: " .$countsql);
        
        $query_handle->execute() 
        or return DbLog_jsonError("Could not execute statement: " . $query_handle->errstr);

        my @data = $query_handle->fetchrow_array();
        $totalcount = join(", ", @data);
        
    }

    # prepare the query
    my $query_handle = $dbhf->prepare($sql) 
        or return DbLog_jsonError("Could not prepare statement: " . $dbhf->errstr . ", SQL was: " .$sql);
    
    # execute the query
    $query_handle->execute() 
        or return DbLog_jsonError("Could not execute statement: " . $query_handle->errstr);
    
    my $columns = $query_handle->{'NAME'};
    my $columncnt;

    # When columns are empty but execution was successful, we have done a successful INSERT, UPDATE or DELETE
    if($columns) {
        $columncnt = scalar @$columns;
    } else {
        return '{"success": "true", "msg":"All ok"}';
    }

    my $i = 0;
    my $jsonstring = '{"data":[';

    while ( my @data = $query_handle->fetchrow_array()) {

        if($i == 0) {
            $jsonstring .= '{';
        } else {
            $jsonstring .= ',{';
        } 
 
        for ($i = 0; $i < $columncnt; $i++) {
            $jsonstring .= '"';
            $jsonstring .= uc($query_handle->{NAME}->[$i]); 
            $jsonstring .= '":';

            if (defined $data[$i]) {
                my $fragment =  substr($data[$i],0,1);
                if ($fragment eq "{") {
                    $jsonstring .= $data[$i];
                } else {
                    $jsonstring .= '"'.$data[$i].'"';
                }
            } else {
                $jsonstring .= '""'
            }
            
            if($i != ($columncnt -1)) {
               $jsonstring .= ','; 
            }
        }
        $jsonstring .= '}'; 
    }
	$dbhf->disconnect();
    $jsonstring .= ']';
    if (defined $totalcount && $totalcount ne "") {
        $jsonstring .= ',"totalCount": '.$totalcount.'}';
    } else {
        $jsonstring .= '}';
    }
return $jsonstring;
}

################################################################
# get <dbLog> ReadingsVal       <device> <reading> <default>
# get <dbLog> ReadingsTimestamp <device> <reading> <default>
################################################################
sub DbLog_dbReadings($@) {
  my($hash,@a) = @_;
  my $history  = $hash->{HELPER}{TH};
  my $current  = $hash->{HELPER}{TC};
  
  my $dbhf = DbLog_ConnectNewDBH($hash);
  return if(!$dbhf);
  
  return 'Wrong Syntax for ReadingsVal!' unless defined($a[4]);
  my $DbLogType = AttrVal($a[0],'DbLogType','current');
  my $query;
  if (lc($DbLogType) =~ m(current) ) {
    $query = "select VALUE,TIMESTAMP from $current where DEVICE= '$a[2]' and READING= '$a[3]'";
  } else {
    $query = "select VALUE,TIMESTAMP from $history where DEVICE= '$a[2]' and READING= '$a[3]' order by TIMESTAMP desc limit 1";
  }
  my ($reading,$timestamp) = $dbhf->selectrow_array($query);
  $dbhf->disconnect(); 
  
  $reading = (defined($reading)) ? $reading : $a[4];
  $timestamp = (defined($timestamp)) ? $timestamp : $a[4];
  return $reading   if $a[1] eq 'ReadingsVal';
  return $timestamp if $a[1] eq 'ReadingsTimestamp';
  return "Syntax error: $a[1]";
}

################################################################
#               Versionierungen des Moduls setzen
#  Die Verwendung von Meta.pm und Packages wird berücksichtigt
################################################################
sub DbLog_setVersionInfo($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (sortTopicNum("desc",keys %DbLog_vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {
	  # META-Daten sind vorhanden
	  $modules{$type}{META}{version} = "v".$v;                                        # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{DbLog}{META}}
	  if($modules{$type}{META}{x_version}) {                                          # {x_version} ( nur gesetzt wenn $Id$ im Kopf komplett! vorhanden )
		  $modules{$type}{META}{x_version} =~ s/1.1.1/$v/g;
	  } else {
		  $modules{$type}{META}{x_version} = $v; 
	  }
	  return $@ unless (FHEM::Meta::SetInternals($hash));                             # FVERSION wird gesetzt ( nur gesetzt wenn $Id$ im Kopf komplett! vorhanden )
	  if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {
	      # es wird mit Packages gearbeitet -> Perl übliche Modulversion setzen
		  # mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
	      use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );                                          
      }
  } else {
	  # herkömmliche Modulstruktur
	  $hash->{VERSION} = $v;
  }
  
return;
}

#########################################################################
#               Trace of Childhandles
# dbh    Database handle object
# sth    Statement handle object
# drh    Driver handle object (rarely seen or used in applications)
# h      Any of the handle types above ($dbh, $sth, or $drh)
#########################################################################
sub DbLog_startShowChildhandles ($) {
    my ($str)       = @_;
    my ($name,$sub) = split(":",$str);
    my $hash        = $defs{$name};
    
    RemoveInternalTimer($hash, "DbLog_startShowChildhandles"); 
    my $iv = AttrVal($name, "traceHandles", 0);
    return if(!$iv);
    
    my %drivers = DBI->installed_drivers();    
    DbLog_showChildHandles($name,$drivers{$_}, 0, $_) for (keys %drivers);
    
    InternalTimer(gettimeofday()+$iv, "DbLog_startShowChildhandles", "$name:$sub", 0) if($iv);
return;
}
      
sub DbLog_showChildHandles ($$$$) {
    my ($name,$h, $level, $key) = @_;
    
    my $t = $h->{Type}."h";
    $t = ($t=~/drh/)?"DriverHandle   ":($t=~/dbh/)?"DatabaseHandle ":($t=~/sth/)?"StatementHandle":"Undefined";
    Log3($name, 1, "DbLog $name - traceHandles (system wide) - Driver: ".$key.", ".$t.": ".("\t" x $level).$h);
    DbLog_showChildHandles($name, $_, $level + 1, $key)
        for (grep { defined } @{$h->{ChildHandles}});
}

1;

=pod
=item helper
=item summary    logs events into a database
=item summary_DE loggt Events in eine Datenbank
=begin html

<a name="DbLog"></a>
<h3>DbLog</h3>
<ul>
  <br>
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
  existing ! 
  <br><br>  
  
  Sample code and Scripts to prepare a MySQL/PostgreSQL/SQLite database you can find in 
  <a href="https://svn.fhem.de/trac/browser/trunk/fhem/contrib/dblog">SVN -&gt; contrib/dblog/db_create_&lt;DBType&gt;.sql</a>. <br>
  (<b>Caution:</b> The local FHEM-Installation subdirectory ./contrib/dblog doesn't contain the freshest scripts !!) 
  <br><br>
  
  The database contains two tables: <code>current</code> and <code>history</code>. <br>
  The latter contains all events whereas the former only contains the last event for any given reading and device. 
  Please consider the <a href="#DbLogattr">attribute</a> DbLogType implicitly to determine the usage of tables  
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
  The configuration is stored in a separate file to avoid storing the password in the main configuration file and to have it
  visible in the output of the <a href="https://fhem.de/commandref.html#list">list</a> command.
  <br><br>
	
  The <b>configuration file</b> should be copied e.g. to /opt/fhem and has the following structure you have to customize 
  suitable to your conditions (decomment the appropriate raws and adjust it): <br><br>
	
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
    #    user => "fhemuser",                                          
    #    password => "fhempassword",
    #    # optional enable(1) / disable(0) UTF-8 support (at least V 4.042 is necessary) 	
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
    <br>

  <a name="DbLogdefine"></a>
  <b>Define</b>  
  <ul>
  <br>
  
    <code>define &lt;name&gt; DbLog &lt;configfilename&gt; &lt;regexp&gt;</code>
    <br><br>

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
        <code>set &lt;name&gt; configCheck</code> <br>
    </ul>
	<br>
	
	This check reports some important settings and gives recommendations back to you if proposals are indentified. 
	<br><br>
		
	DbLog distinguishes between the synchronous (default) and asynchronous logmode. The logmode is adjustable by the  
	<a href="#DbLogattr">attribute</a> asyncMode. Since version 2.13.5 DbLog is supporting primary key (PK) set in table 
	current	or history. If you want use PostgreSQL with PK it has to be at lest version 9.5.  
    <br><br>
	
    The content of VALUE will be optimized for automated post-processing, e.g. <code>yes</code> is translated to <code>1</code>
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
    <li> Was "set &lt;name&gt; configCheck" executed after definition and potential errors fixed or rather the hints implemented ? </li>
    <li> If configDB is used ... has the database configuration file been imported into configDB (e.g. by "configDB fileimport ./db.conf") ? </li>
    <li> When creating a SVG-plot and no drop-down list with proposed values appear -> set attribute "DbLogType" to "Current/History". </li>
    </ul>
    <br>
    
    If the notes don't lead to success, please increase verbose level of the DbLog-device to 4 or 5 and observe entries in
	logfile relating to the DbLog-device.
    
    For problem analysis please post the output of "list &lt;name&gt;", the result of "set &lt;name&gt; configCheck" and the 
    logfile entries of DbLog-device to the forum thread.
	<br><br>
	
  </ul>
  <br>
  <br>


  <a name="DbLogset"></a>
  <b>Set</b> 
  <ul>
    <code>set &lt;name&gt; addCacheLine YYYY-MM-DD HH:MM:SS|&lt;device&gt;|&lt;type&gt;|&lt;event&gt;|&lt;reading&gt;|&lt;value&gt;|[&lt;unit&gt;]  </code><br><br>
    <ul> In asynchronous mode a new dataset is inserted to the Cache and will be processed at the next database sync cycle.
    <br><br>
      
	  <b>Example:</b> <br>
	  set &lt;name&gt; addCacheLine 2017-12-05 17:03:59|MaxBathRoom|MAX|valveposition: 95|valveposition|95|% <br>
    </ul><br>
    
    <code>set &lt;name&gt; addLog &lt;devspec&gt;:&lt;Reading&gt; [Value] [CN=&lt;caller name&gt;] [!useExcludes] </code><br><br>
    <ul> Inserts an additional log entry of a device/reading combination into the database. Readings which are possibly specified
    in attribute "DbLogExclude" (in source device) are not logged, unless they are enclosed in attribute "DbLogInclude" 
    or addLog was called with option "!useExcludes". <br><br>
      
      <ul>
      <li> <b>&lt;devspec&gt;:&lt;Reading&gt;</b> - The device can be declared by a <a href="#devspec">device specification 
                                                    (devspec)</a>. "Reading" will be evaluated as regular expression. If
                                                    The reading isn't available and the value "Value" is specified, the
                                                    reading will be added to database as new one if it isn't a regular 
                                                    expression and the readingname is valid.  </li>
      <li> <b>Value</b> - Optionally you can enter a "Value" that is used as reading value in the dataset. If the value isn't 
                          specified (default), the current value of the specified reading will be inserted into the database. </li>  
      <li> <b>CN=&lt;caller name&gt;</b> - By the key "CN=" (<b>C</b>aller <b>N</b>ame) you can specify an additional string, 
                                           e.g. the name of a calling device (for example an at- or notify-device).
                                           Via the function defined in <a href="#DbLogattr">attribute</a> "valueFn" this key can be analyzed
                                           by the variable $CN. Thereby it is possible to control the behavior of the addLog dependend from
                                           the calling source. </li> 
      <li> <b>!useExcludes</b> - The function considers attribute "DbLogExclude" in the source device if it is set. If the optional 
                                 keyword "!useExcludes" is set, the attribute "DbLogExclude" isn't considered. </li>
      </ul>
      <br>
      
      The database field "EVENT" will be filled with the string "addLog" automatically. <br>
	  The addLog-command dosn't create an additional event in your system !<br><br>
      
	  <b>Examples:</b> <br>
	  set &lt;name&gt; addLog SMA_Energymeter:Bezug_Wirkleistung <br>
	  set &lt;name&gt; addLog TYPE=SSCam:state <br>
	  set &lt;name&gt; addLog MyWetter:(fc10.*|fc8.*) <br>
	  set &lt;name&gt; addLog MyWetter:(wind|wind_ch.*) 20 !useExcludes <br>
	  set &lt;name&gt; addLog TYPE=CUL_HM:FILTER=model=HM-CC-RT-DN:FILTER=subType!=(virtual|):(measured-temp|desired-temp|actuator) <br><br>
      
      set &lt;name&gt; addLog USV:state CN=di.cronjob <br>
      In the valueFn-function the caller "di.cronjob" is evaluated via the variable $CN and the timestamp is corrected: <br><br>
      valueFn = if($CN eq "di.cronjob" and $TIMESTAMP =~ m/\s00:00:[\d:]+/) { $TIMESTAMP =~ s/\s([^\s]+)/ 23:59:59/ }      
      
    </ul><br>
	
    <code>set &lt;name&gt; clearReadings </code><br><br>
      <ul> This function clears readings which were created by different DbLog-functions. </ul><br>

    <code>set &lt;name&gt; commitCache </code><br><br>
      <ul>In asynchronous mode (<a href="#DbLogattr">attribute</a> asyncMode=1), the cached data in memory will be written into the database 
	  and subsequently the cache will be cleared. Thereby the internal timer for the asynchronous mode Modus will be set new.
      The command can be usefull in case of you want to write the cached data manually or e.g. by an AT-device on a defined 
	  point of time into the database. </ul><br>

    <code>set &lt;name&gt; configCheck </code><br><br>
      <ul>This command checks some important settings and give recommendations back to you if proposals are identified. 
	  </ul><br>
	  
    <code>set &lt;name&gt; count </code><br/><br/>
      <ul>Count records in tables current and history and write results into readings countCurrent and countHistory.</ul><br/>

    <code>set &lt;name&gt; countNbl </code><br/><br/>
      <ul>The non-blocking execution of "set &lt;name&gt; count".</ul><br/>
	    
    <code>set &lt;name&gt; deleteOldDays &lt;n&gt;</code><br/><br/>
      <ul>Delete records from history older than &lt;n&gt; days. Number of deleted records will be written into reading 
      lastRowsDeleted.
      </ul><br>
	  
    <code>set &lt;name&gt; deleteOldDaysNbl &lt;n&gt;</code><br/><br/>
      <ul>
      Is identical to function "deleteOldDays" 	whereupon deleteOldDaysNbl will be executed non-blocking. 
      <br><br>
      
      <b>Note:</b> <br>
      Even though the function itself is non-blocking, you have to set DbLog into the asynchronous mode (attr asyncMode = 1) to
      avoid a blocking situation of FHEM !
      
      </ul>
      <br>	

    <code>set &lt;name&gt; eraseReadings </code><br><br>
      <ul> This function deletes all readings except reading "state". </ul><br>

	<a name="DbLogsetexportCache"></a>
    <code>set &lt;name&gt; exportCache [nopurge | purgecache] </code><br><br>
      <ul>If DbLog is operating in asynchronous mode, it's possible to exoprt the cache content into a textfile.
	  The file will be written to the directory (global->modpath)/log/ by default setting. The detination directory can be
	  changed by the <a href="#DbLogattr">attribute</a> expimpdir. <br>
	  The filename will be generated automatically and is built by a prefix "cache_", followed by DbLog-devicename and the
	  present timestmp, e.g. "cache_LogDB_2017-03-23_22-13-55". <br>
      There are two options possible, "nopurge" respectively "purgecache". The option determines whether the cache content 
	  will be deleted after export or not.
	  Using option "nopurge" (default) the cache content will be preserved. <br>
      The <a href="#DbLogattr">attribute</a> "exportCacheAppend" defines, whether every export process creates a new export file 
      (default) or the cache content is appended to an existing (newest) export file.  
      </ul><br>
		  
    <code>set &lt;name&gt; importCachefile &lt;file&gt; </code><br><br>
      <ul>Imports an textfile into the database which has been written by the "exportCache" function. 
	  The allocatable files will be searched in directory (global->modpath)/log/ by default and a drop-down list will be 
      generated from the files which are found in the directory.
	  The source directory can be changed by the <a href="#DbLogattr">attribute</a> expimpdir. <br>
	  Only that files will be shown which are correlate on pattern starting with "cache_", followed by the DbLog-devicename. <br> 
	  For example a file with the name "cache_LogDB_2017-03-23_22-13-55", will match if Dblog-device has name "LogDB". <br>
      After the import has been successfully done, a prefix "impdone_" will be added at begin of the filename and this file 
      ddoesn't appear on the drop-down list anymore. <br>
	  If you want to import a cachefile from another source database, you may adapt the filename so it fits the search criteria 
      "DbLog-Device" in its name. After renaming the file appeares again on the drop-down list. </ul><br>

	  <code>set &lt;name&gt; listCache </code><br><br>
      <ul>If DbLog is set to asynchronous mode (attribute asyncMode=1), you can use that command to list the events are cached in memory.</ul><br>

    <code>set &lt;name&gt; purgeCache </code><br><br>
      <ul>In asynchronous mode (<a href="#DbLogattr">attribute</a> asyncMode=1), the in memory cached data will be deleted. 
      With this command data won't be written from cache into the database. </ul><br>
	  
    <code>set &lt;name&gt; reduceLog &lt;no&gt;[:&lt;nn&gt;] [average[=day]] [exclude=device1:reading1,device2:reading2,...]</code> <br><br>
      <ul>Reduces records older than &lt;no&gt; days and (optional) newer than &lt;nn&gt; days to one record (the 1st) each hour per device & reading. <br>
          Within the device/reading name <b>SQL-Wildcards "%" and "_"</b> can be used. <br><br>
          
		  With the optional argument 'average' not only the records will be reduced, but all numerical values of an hour 
		  will be reduced to a single average. <br>
          With the optional argument 'average=day' not only the records will be reduced, but all numerical values of a 
		  day will be reduced to a single average. (implies 'average') <br><br>
         
          You can optional set the last argument to "exclude=device1:reading1,device2:reading2,..." to exclude 
          device/readings from reduceLog. <br>          
          Also you can optional set the last argument to "include=device:reading" to delimit the SELECT statement which 
          is executed on the database. This may reduce the system RAM load and increases the performance. <br><br>
          
          <ul>
          <b>Example: </b> <br>
          set &lt;name&gt; reduceLog 270 average include=Luftdaten_remote:% <br>
          </ul>
          <br>
      
          <b>CAUTION:</b> It is strongly recommended to check if the default INDEX 'Search_Idx' exists on the table 'history'! <br>
		  The execution of this command may take (without INDEX) extremely long. FHEM will be <b>blocked completely</b> after issuing the command to completion ! <br><br>
          
      </ul><br>
	  
    <code>set &lt;name&gt; reduceLogNbl &lt;no&gt;[:&lt;nn&gt;] [average[=day]] [exclude=device1:reading1,device2:reading2,...]</code> <br><br>
      <ul>Same function as "set &lt;name&gt; reduceLog" but FHEM won't be blocked due to this function is implemented 
      non-blocking ! <br><br>
      
      <b>Note:</b> <br>
      Even though the function itself is non-blocking, you have to set DbLog into the asynchronous mode (attr asyncMode = 1) to
      avoid a blocking situation of FHEM !
      
      </ul><br>

    <code>set &lt;name&gt; reopen [n] </code><br/><br/>
      <ul>Perform a database disconnect and immediate reconnect to clear cache and flush journal file if no time [n] was set. <br>
	  If optionally a delay time of [n] seconds was set, the database connection will be disconnect immediately but it was only reopened 
	  after [n] seconds. In synchronous mode the events won't saved during that time. In asynchronous mode the events will be
	  stored in the memory cache and saved into database after the reconnect was done. </ul><br/>

    <code>set &lt;name&gt; rereadcfg </code><br/><br/>
      <ul>Perform a database disconnect and immediate reconnect to clear cache and flush journal file.<br/>
      Probably same behavior als reopen, but rereadcfg will read the configuration data before reconnect.</ul><br/>
	  
    <code>set &lt;name&gt; userCommand &lt;validSqlStatement&gt;</code><br/><br/>
      <ul>
        Performs simple sql select statements on the connected database. Usercommand and result will be written into 
		corresponding readings.</br>
		The result can only be a single line. 
        The execution of SQL-Statements in DbLog is deprecated. Therefore the analysis module 
        <a href=https://fhem.de/commandref.html#DbRep>DbRep</a> should be used.</br>
      </ul><br/>

  </ul><br>

  <a name="DbLogget"></a>
  <b>Get</b>
  <ul>
  <code>get &lt;name&gt; ReadingsVal&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; &lt;device&gt; &lt;reading&gt; &lt;default&gt;</code><br/>
  <code>get &lt;name&gt; ReadingsTimestamp &lt;device&gt; &lt;reading&gt; &lt;default&gt;</code><br/>
  <br/>
  Retrieve one single value, use and syntax are similar to ReadingsVal() and ReadingsTimestamp() functions.<br/>
  </ul>
  <br/>
  <br/>
  <ul>
    <code>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;column_spec&gt; </code>
    <br><br>
    Read data from the Database, used by frontends to plot data without direct
    access to the Database.<br>

    <ul>
      <li>&lt;in&gt;<br>
        A dummy parameter for FileLog compatibility. Sessing by defaultto <code>-</code><br>
        <ul>
          <li>current: reading actual readings from table "current"</li>
          <li>history: reading history readings from table "history"</li>
          <li>-: identical to "history"</li>
        </ul> 
      </li>
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
      <li>&lt;from&gt; / &lt;to&gt;<br>
        Used to select the data. Please use the following timeformat or
        an initial substring of it:<br>
        <ul><code>YYYY-MM-DD_HH24:MI:SS</code></ul></li>
      <li>&lt;column_spec&gt;<br>
        For each column_spec return a set of data separated by
        a comment line on the current connection.<br>
        Syntax: &lt;device&gt;:&lt;reading&gt;:&lt;default&gt;:&lt;fn&gt;:&lt;regexp&gt;<br>
        <ul>
          <li>&lt;device&gt;<br>
            The name of the device. Case sensitive. Using a the joker "%" is supported.</li>
          <li>&lt;reading&gt;<br>
            The reading of the given device to select. Case sensitive. Using a the joker "%" is supported.
            </li>
          <li>&lt;default&gt;<br>
            no implemented yet
            </li>
          <li>&lt;fn&gt;
            One of the following:
            <ul>
              <li>int<br>
                Extract the integer at the beginning of the string. Used e.g.
                for constructs like 10%</li>
              <li>int&lt;digit&gt;<br>
                Extract the decimal digits including negative character and
                decimal point at the beginning og the string. Used e.g.
                for constructs like 15.7&deg;C</li>
              <li>delta-h / delta-d<br>
                Return the delta of the values for a given hour or a given day.
                Used if the column contains a counter, as is the case for the
                KS300 rain column.</li>
              <li>delta-ts<br>
                Replaced the original value with a measured value of seconds since
                the last and the actual logentry.
              </li>
            </ul></li>
            <li>&lt;regexp&gt;<br>
              The string is evaluated as a perl expression.  The regexp is executed
              before &lt;fn&gt; parameter.<br>
              Note: The string/perl expression cannot contain spaces,
              as the part after the space will be considered as the
              next column_spec.<br>
              <b>Keywords</b>
              <li>$val is the current value returned from the Database.</li>
              <li>$ts is the current timestamp returned from the Database.</li>
              <li>This Logentry will not print out if $val contains th keyword "hide".</li>
              <li>This Logentry will not print out and not used in the following processing
                  if $val contains th keyword "ignore".</li>
            </li>
        </ul></li>
      </ul>
    <br><br>
    Examples:
      <ul>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature</code></li>
        <li><code>get myDbLog current ALL - - %:temperature</code></li><br>
            you will get all actual readings "temperature" from all logged devices. 
            Be careful by using "history" as inputfile because a long execution time will be expected!
        <li><code>get myDbLog - - 2012-11-10_10 2012-11-10_20 KS300:temperature::int1</code><br>
           like from 10am until 08pm at 10.11.2012</li>
        <li><code>get myDbLog - all 2012-11-10 2012-11-20 KS300:temperature</code></li>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature KS300:rain::delta-h KS300:rain::delta-d</code></li>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 MyFS20:data:::$val=~s/(on|off).*/$1eq"on"?1:0/eg</code><br>
           return 1 for all occurance of on* (on|on-for-timer etc) and 0 for all off*</li>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 Bodenfeuchte:data:::$val=~s/.*B:\s([-\.\d]+).*/$1/eg</code><br>
           Example of OWAD: value like this: <code>"A: 49.527 % B: 66.647 % C: 9.797 % D: 0.097 V"</code><br>
           and output for port B is like this: <code>2012-11-20_10:23:54 66.647</code></li>
        <li><code>get DbLog - - 2013-05-26 2013-05-28 Pumpe:data::delta-ts:$val=~s/on/hide/</code><br>
           Setting up a "Counter of Uptime". The function delta-ts gets the seconds between the last and the
           actual logentry. The keyword "hide" will hide the logentry of "on" because this time 
           is a "counter of Downtime"</li>

      </ul>
    <br><br>
  </ul>

  <b>Get</b> when used for webcharts
  <ul>
    <code>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;device&gt; &lt;querytype&gt; &lt;xaxis&gt; &lt;yaxis&gt; &lt;savename&gt; </code>
    <br><br>
    Query the Database to retrieve JSON-Formatted Data, which is used by the charting frontend.
    <br>

    <ul>
      <li>&lt;name&gt;<br>
        The name of the defined DbLog, like it is given in fhem.cfg.</li>
      <li>&lt;in&gt;<br>
        A dummy parameter for FileLog compatibility. Always set to <code>-</code></li>
      <li>&lt;out&gt;<br>
        A dummy parameter for FileLog compatibility. Set it to <code>webchart</code>
        to use the charting related get function.
      </li>
      <li>&lt;from&gt; / &lt;to&gt;<br>
        Used to select the data. Please use the following timeformat:<br>
        <ul><code>YYYY-MM-DD_HH24:MI:SS</code></ul></li>
      <li>&lt;device&gt;<br>
        A string which represents the device to query.</li>
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
      <li>&lt;xaxis&gt;<br>
        A string which represents the xaxis</li>
      <li>&lt;yaxis&gt;<br>
         A string which represents the yaxis</li>
      <li>&lt;savename&gt;<br>
         A string which represents the name a chart will be saved with</li>
      <li>&lt;chartconfig&gt;<br>
         A jsonstring which represents the chart to save</li>
      <li>&lt;pagingstart&gt;<br>
         An integer used to determine the start for the sql used for query 'getTableData'</li>
      <li>&lt;paginglimit&gt;<br>
         An integer used to set the limit for the sql used for query 'getTableData'</li>
      </ul>
    <br><br>
    <b>Examples:</b>
      <ul>
        <li><code>get logdb - webchart "" "" "" getcharts</code><br>
            Retrieves all saved charts from the Database</li>
        <li><code>get logdb - webchart "" "" "" getdevices</code><br>
            Retrieves all available devices from the Database</li>
        <li><code>get logdb - webchart "" "" ESA2000_LED_011e getreadings</code><br>
            Retrieves all available Readings for a given device from the Database</li>
        <li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e timerange TIMESTAMP day_kwh</code><br>
            Retrieves charting data, which requires a given xaxis, yaxis, device, to and from<br>
            Will ouput a JSON like this: <code>[{'TIMESTAMP':'2013-02-11 00:10:10','VALUE':'0.22431388090756'},{'TIMESTAMP'.....}]</code></li>
        <li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e savechart TIMESTAMP day_kwh tageskwh</code><br>
            Will save a chart in the database with the given name and the chart configuration parameters</li>      
        <li><code>get logdb - webchart "" "" "" deletechart "" "" 7</code><br>
            Will delete a chart from the database with the given id</li>
      </ul>
    <br><br>
  </ul>
  
  <a name="DbLogattr"></a>
  <b>Attributes</b> 
  <br><br>
   
  <ul>
    <a name="addStateEvent"></a>
    <li><b>addStateEvent</b>
    <ul>
	  <code>attr &lt;device&gt; addStateEvent [0|1]
	  </code><br>
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
    <a name="asyncMode"></a>
    <li><b>asyncMode</b>
    <ul>
	  <code>attr &lt;device&gt; asyncMode [1|0]
	  </code><br>
	  
      This attribute determines the operation mode of DbLog. If asynchronous mode is active (asyncMode=1), the events which should be saved 
	  at first will be cached in memory. After synchronisation time cycle (attribute syncInterval), or if the count limit of datasets in cache 
	  is reached (attribute cacheLimit), the cached events get saved into the database using bulk insert.
	  If the database isn't available, the events will be cached in memeory furthermore, and tried to save into database again after 
	  the next synchronisation time cycle if the database is available. <br>
	  In asynchronous mode the data insert into database will be executed non-blocking by a background process. 
	  You can adjust the timeout value for this background process by attribute "timeout" (default 86400s). <br>
	  In synchronous mode (normal mode) the events won't be cached im memory and get saved into database immediately. If the database isn't
	  available the events are get lost. <br>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="bulkInsert"></a>
    <li><b>bulkInsert</b>
    <ul>
	  <code>attr &lt;device&gt; bulkInsert [1|0]
	  </code><br>
	  
      Toggles the Insert mode between Array (default) and Bulk. This Bulk insert mode increase the write performance 
      into the history table significant in case of plenty of data to insert, especially if asynchronous mode is
      used.      
      To get the whole improved performance, the attribute "DbLogType" should <b>not</b> contain the current table
      in this use case. <br>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="commitMode"></a>
    <li><b>commitMode</b>
    <ul>
	  <code>attr &lt;device&gt; commitMode [basic_ta:on | basic_ta:off | ac:on_ta:on | ac:on_ta:off | ac:off_ta:on]
	  </code><br>
	  
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
    <a name="cacheEvents"></a>
    <li><b>cacheEvents</b>
    <ul>
	  <code>attr &lt;device&gt; cacheEvents [2|1|0]
	  </code><br>
	  <ul>
      <li>cacheEvents=1: creates events of reading CacheUsage at point of time when a new dataset has been added to the cache. </li>
	  <li>cacheEvents=2: creates events of reading CacheUsage at point of time when in aychronous mode a new write cycle to the 
	                     database starts. In that moment CacheUsage contains the number of datasets which will be written to 
						 the database. </li><br>
	  </ul>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
     <a name="cacheLimit"></a>
     <li><b>cacheLimit</b>
     <ul>
	   <code>
	   attr &lt;device&gt; cacheLimit &lt;n&gt; 
	   </code><br>
	 
       In asynchronous logging mode the content of cache will be written into the database and cleared if the number &lt;n&gt; datasets
	   in cache has reached (default: 500). Thereby the timer of asynchronous logging mode will be set new to the value of 
	   attribute "syncInterval". In case of error the next write attempt will be started at the earliest after syncInterval/2. <br>
     </ul>
     </li>
  </ul>
  <br>
  
  <ul>
     <a name="colEvent"></a>
     <li><b>colEvent</b>
     <ul>
	   <code>
	   attr &lt;device&gt; colEvent &lt;n&gt; 
	   </code><br>
	 
	   The field length of database field EVENT will be adjusted. By this attribute the default value in the DbLog-device can be
	   adjusted if the field length in the databse was changed nanually. If colEvent=0 is set, the database field  
	   EVENT won't be filled . <br>
	   <b>Note:</b> <br>
	   If the attribute is set, all of the field length limits are valid also for SQLite databases as noticed in Internal COLUMNS !  <br>
     </ul>
     </li>
  </ul>
  <br>
  
  <ul>
     <a name="colReading"></a>
     <li><b>colReading</b>
     <ul>
	   <code>
	   attr &lt;device&gt; colReading &lt;n&gt; 
	   </code><br>
	 
	   The field length of database field READING will be adjusted. By this attribute the default value in the DbLog-device can be
	   adjusted if the field length in the databse was changed nanually. If colReading=0 is set, the database field  
	   READING won't be filled . <br>
	   <b>Note:</b> <br>
	   If the attribute is set, all of the field length limits are valid also for SQLite databases as noticed in Internal COLUMNS !  <br>
     </ul>
     </li>
  </ul>
  <br>
  
  <ul>
     <a name="colValue"></a>
     <li><b>colValue</b>
     <ul>
	   <code>
	   attr &lt;device&gt; colValue &lt;n&gt; 
	   </code><br>
	 
	   The field length of database field VALUE will be adjusted. By this attribute the default value in the DbLog-device can be
	   adjusted if the field length in the databse was changed nanually. If colEvent=0 is set, the database field  
	   VALUE won't be filled . <br>
	   <b>Note:</b> <br>
	   If the attribute is set, all of the field length limits are valid also for SQLite databases as noticed in Internal COLUMNS !  <br>
     </ul>
     </li>
  </ul>
  <br>
  
  <ul>
     <a name="DbLogType"></a>
     <li><b>DbLogType</b>
     <ul>
	   <code>
	   attr &lt;device&gt; DbLogType [Current|History|Current/History]
	   </code><br>
	 
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
    <a name="DbLogSelectionMode"></a>
    <li><b>DbLogSelectionMode</b>
    <ul>
	  <code>
	  attr &lt;device&gt; DbLogSelectionMode [Exclude|Include|Exclude/Include]
	  </code><br>
	  
      Thise DbLog-Device-Attribute specifies how the device specific Attributes DbLogExclude and DbLogInclude are handled.
      If this Attribute is missing it defaults to "Exclude". <br><br>
         <ul>
            <li>Exclude: DbLog behaves just as usual. This means everything specified in the regex in DEF will be logged by default and anything excluded
                         via the DbLogExclude attribute will not be logged</li>
            <li>Include: Nothing will be logged, except the readings specified via regex in the DbLogInclude attribute 
                         (in source devices). 
                         Neither the Regex set in DEF will be considered nor the device name of the source device itself. </li>
            <li>Exclude/Include: Just almost the same as Exclude, but if the reading matches the DbLogExclude attribute, then
                       it will further be checked against the regex in DbLogInclude whicht may possibly re-include the already 
                       excluded reading. </li>
         </ul>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a name="DbLogInclude"></a>
    <li><b>DbLogInclude</b>
    <ul>
      <code>
      attr &lt;device&gt; DbLogInclude regex:MinInterval[:force],[regex:MinInterval[:force]] ...
      </code><br>
	  
      A new Attribute DbLogInclude will be propagated to all Devices if DBLog is used. 
      DbLogInclude works just like DbLogExclude but to include matching readings.
      If a MinInterval is set, the logentry is dropped if the defined interval is not reached <b>and</b> the value vs. 
      last value is equal. If the optional parameter "force" is set, the logentry is also dropped even though the value is not 
      equal the last one and the defined interval is not reached.
      is not reached and the 
      See also DbLogSelectionMode-Attribute of DbLog device which takes influence on how DbLogExclude and DbLogInclude 
      are handled. <br><br>
	
	  <b>Example</b> <br>
      <code>attr MyDevice1 DbLogInclude .*</code> <br>
      <code>attr MyDevice2 DbLogInclude state,(floorplantext|MyUserReading):300,battery:3600</code> <br>
      <code>attr MyDevice2 DbLogInclude state,(floorplantext|MyUserReading):300:force,battery:3600:force</code>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="DbLogExclude"></a>
    <li><b>DbLogExclude</b>
    <ul>
      <code>
      attr &lt;device&gt; DbLogExclude regex:MinInterval[:force],[regex:MinInterval[:force]] ...
      </code><br>
	  
      A new attribute DbLogExclude will be propagated to all devices if DBLog is used. 
	  DbLogExclude will work as regexp to exclude defined readings to log. Each individual regexp-group are separated by 
      comma. 
      If a MinInterval is set, the logentry is dropped if the defined interval is not reached <b>and</b> the value vs. 
      lastvalue is equal. If the optional parameter "force" is set, the logentry is also dropped even though the value is not 
      equal the last one and the defined interval is not reached.
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
     <a name="DbLogValueFn"></a>
     <li><b>DbLogValueFn</b>
     <ul>
	   <code>
	   attr &lt;device&gt; DbLogValueFn {}
	   </code><br>
       
       The attribute <i>DbLogValueFn</i> will be propagated to all devices if DbLog is used. 
	   This attribute contains a Perl expression that can use and change values of $TIMESTAMP, $READING, $VALUE (value of 
       reading) and $UNIT (unit of reading value). That means the changed values are logged.
       You also have readonly-access to $EVENT for evaluation in your expression. <br>
	   If $TIMESTAMP should be changed, it must meet the condition "yyyy-mm-dd hh:mm:ss", otherwise the $timestamp wouldn't 
	   be changed.
	   In addition you can set the variable $IGNORE=1 if you want skip a dataset from logging. <br>

       The device specific function in "DbLogValueFn" is applied to the dataset before the potential existing attribute 
       "valueFn" in the DbLog device.
       <br><br>
	   
	   <b>Example</b> <br>
       <pre>
attr SMA_Energymeter DbLogValueFn
{ 
  if ($READING eq "Bezug_WirkP_Kosten_Diff"){
    $UNIT="Diff-W";
  }
  if ($READING =~ /Einspeisung_Wirkleistung_Zaehler/ && $VALUE < 2){
    $IGNORE=1;
  }
}
	   </pre>
     </ul>
     </li>
  </ul>
  
  <ul>
    <a name="dbSchema"></a>
    <li><b>dbSchema</b>
    <ul>
      <code>
      attr &lt;device&gt; dbSchema &lt;schema&gt;
      </code><br>
	  
      This attribute is available for database types MySQL/MariaDB and PostgreSQL. The table names (current/history) are 
      extended by its database schema. It is an advanced feature and normally not necessary to set.
      <br>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="disable"></a>
    <li><b>disable</b>
    <ul>
      <code>
      attr &lt;device&gt; disable [0|1]
      </code><br>
	  
      Disables the DbLog device (1) or enables it (0). 
      <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a name="excludeDevs"></a>
     <li><b>excludeDevs</b>
     <ul>
	   <code>
	   attr &lt;device&gt; excludeDevs &lt;devspec1&gt;[#Reading],&lt;devspec2&gt;[#Reading],&lt;devspec...&gt; 
	   </code><br>
      
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
     <a name="expimpdir"></a>
     <li><b>expimpdir</b>
     <ul>
	   <code>
	   attr &lt;device&gt; expimpdir &lt;directory&gt; 
	   </code><br>
      
	   If the cache content will be exported by <a href="#DbLogsetexportCache">"exportCache"</a> or the "importCachefile"
	   command, the file will be written into or read from that directory. The default directory is 
	   "(global->modpath)/log/". 
	   Make sure the specified directory is existing and writable. <br><br>
	   
	  <b>Example</b> <br>
      <code>
	  attr &lt;device&gt; expimpdir /opt/fhem/cache/
	  </code><br>
     </ul>
     </li>
  </ul>
  <br>
  
  <ul>
     <a name="exportCacheAppend"></a>
     <li><b>exportCacheAppend</b>
     <ul>
	   <code>
	   attr &lt;device&gt; exportCacheAppend [1|0]
	   </code><br>
	   
       If set, the export of cache ("set &lt;device&gt; exportCache") appends the content to the newest available
       export file. If there is no exististing export file, it will be new created. <br>
       If the attribute not set, every export process creates a new export file . (default)<br/>
     </ul>
     </li>
  </ul>
  <br>
  
  <ul>
     <a name="noNotifyDev"></a>
     <li><b>noNotifyDev</b>
     <ul>
	   <code>
	   attr &lt;device&gt; noNotifyDev [1|0]
	   </code><br>
	   
       Enforces that NOTIFYDEV won't set and hence won't used. <br>
     </ul>
     </li>
  </ul>
  <br>
  
  <ul>
     <a name="noSupportPK"></a>
     <li><b>noSupportPK</b>
     <ul>
	   <code>
	   attr &lt;device&gt; noSupportPK [1|0]
	   </code><br>
	   
       Deactivates the support of a set primary key by the module.<br>
     </ul>
     </li>
  </ul>
  <br>
  
  <ul>
    <a name="syncEvents"></a>
    <li><b>syncEvents</b>
    <ul>
	  <code>attr &lt;device&gt; syncEvents [1|0]
	  </code><br>
	  
      events of reading syncEvents will be created. <br>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="showproctime"></a>
    <li><b>showproctime</b>
    <ul>
	  <code>attr &lt;device&gt; [1|0]
	  </code><br>
	  
      If set, the reading "sql_processing_time" shows the required execution time (in seconds) for the sql-requests. This is not calculated 
	  for a single sql-statement, but the summary of all sql-statements necessary for within an executed DbLog-function in background. 
	  The reading "background_processing_time" shows the total time used in background.  <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a name="showNotifyTime"></a>
    <li><b>showNotifyTime</b>
    <ul>
	  <code>attr &lt;device&gt; showNotifyTime [1|0]
	  </code><br>
	  
	  If set, the reading "notify_processing_time" shows the required execution time (in seconds) in the DbLog 
	  Notify-function. This attribute is practical for performance analyses and helps to determine the differences of time
      required when the operation mode was switched from synchronous to the asynchronous mode. <br>
	  
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="syncInterval"></a>
    <li><b>syncInterval</b>
    <ul>
	  <code>attr &lt;device&gt; syncInterval &lt;n&gt;
	  </code><br>
	  
      If DbLog is set to asynchronous operation mode (attribute asyncMode=1), with this attribute you can setup the interval in seconds
      used for storage the in memory cached events into the database. THe default value is 30 seconds. <br>
	  
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="suppressAddLogV3"></a>
    <li><b>suppressAddLogV3</b>
    <ul>
	  <code>attr &lt;device&gt; suppressAddLogV3 [1|0]
	  </code><br>
	  
      If set, verbose 3 Logfileentries done by the addLog-function will be suppressed.  <br>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="suppressUndef"></a>
    <li><b>suppressUndef</b>
    <ul>
	  <code>
	  attr &lt;device&gt; suppressUndef <n>
	  </code><br>
      suppresses all undef values when returning data from the DB via get <br><br>

	  <b>Example</b> <br>
      <code>#DbLog eMeter:power:::$val=($val>1500)?undef:$val</code>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
    <a name="timeout"></a>
    <li><b>timeout</b>
    <ul>
	  <code>
	  attr &lt;device&gt; timeout &lt;n&gt;
	  </code><br>
      setup timeout of the write cycle into database in asynchronous mode (default 86400s) <br>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="traceFlag"></a>
    <li><b>traceFlag</b>
    <ul>
	  <code>
	  attr &lt;device&gt; traceFlag &lt;ALL|SQL|CON|ENC|DBD|TXN&gt;
	  </code><br>
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
    <a name="traceHandles"></a>
    <li><b>traceHandles</b>
    <ul>
	  <code>attr &lt;device&gt; traceHandles &lt;n&gt;
	  </code><br>
	  
      If set, every &lt;n&gt; seconds the system wide existing database handles are printed out into the logfile.
      This attribute is only relevant in case of support. (default: 0 = switch off) <br>
	  
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="traceLevel"></a>
    <li><b>traceLevel</b>
    <ul>
	  <code>
	  attr &lt;device&gt; traceLevel &lt;0|1|2|3|4|5|6|7&gt;
	  </code><br>
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
    <a name="useCharfilter"></a>
    <li><b>useCharfilter</b>
    <ul>
	  <code>
	  attr &lt;device&gt; useCharfilter [0|1] <n>
	  </code><br>
      If set, only ASCII characters from 32 to 126 are accepted in event. 
	  That are the characters " A-Za-z0-9!"#$%&'()*+,-.\/:;<=>?@[\\]^_`{|}~" .<br>
	  Mutated vowel and "€" are transcribed (e.g. ä to ae). (default: 0). <br>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
     <a name="valueFn"></a>
     <li><b>valueFn</b>
     <ul>
	   <code>
	   attr &lt;device&gt; valueFn {}
	   </code><br>
      
	   The attribute contains a Perl expression that can use and change values of $TIMESTAMP, $DEVICE, $DEVICETYPE, $READING, 
       $VALUE (value of reading) and $UNIT (unit of reading value).
       You also have readonly-access to $EVENT for evaluation in your expression. <br>
	   If $TIMESTAMP should be changed, it must meet the condition "yyyy-mm-dd hh:mm:ss", otherwise the $timestamp wouldn't 
	   be changed.
	   In addition you can set the variable $IGNORE=1 if you want skip a dataset from logging. <br><br>
	   
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
     <a name="verbose4Devs"></a>
     <li><b>verbose4Devs</b>
     <ul>
	   <code>
	   attr &lt;device&gt; verbose4Devs &lt;device1&gt;,&lt;device2&gt;,&lt;device..&gt; 
	   </code><br>
      
	   If verbose level 4 is used, only output of devices set in this attribute will be reported in FHEM central logfile. If this attribute
	   isn't set, output of all relevant devices will be reported if using verbose level 4.
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

<a name="DbLog"></a>
<h3>DbLog</h3>
<ul>
  <br>
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
  Admin-Tool (z.B. phpMyAdmin) zu löschen falls sie existieren ! 
  <br><br>
  
  Beispielcode bzw. Scripts zum Erstellen einer MySQL/PostgreSQL/SQLite Datenbank ist im 
  <a href="https://svn.fhem.de/trac/browser/trunk/fhem/contrib/dblog">SVN -&gt; contrib/dblog/db_create_&lt;DBType&gt;.sql</a>
  enthalten. <br>
  (<b>Achtung:</b> Die lokale FHEM-Installation enthält im Unterverzeichnis ./contrib/dblog nicht die aktuellsten 
  Scripte !!) <br><br>
  
  Die Datenbank beinhaltet 2 Tabellen: <code>current</code> und <code>history</code>. <br>
  Die Tabelle <code>current</code> enthält den letzten Stand pro Device und Reading. <br>
  In der Tabelle <code>history</code> sind alle Events historisch gespeichert. <br>
  Beachten sie bitte unbedingt das <a href="#DbLogattr">Attribut</a> DbLogType um die Benutzung der Tabellen 
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
  Die Konfiguration ist in einer sparaten Datei abgelegt um das Datenbankpasswort nicht in Klartext in der 
  FHEM-Haupt-Konfigurationsdatei speichern zu müssen.
  Ansonsten wäre es mittels des <a href="https://fhem.de/commandref_DE.html#list">list</a> Befehls einfach auslesbar.
  <br><br>
	
  Die <b>Konfigurationsdatei</b> wird z.B. nach /opt/fhem kopiert und hat folgenden Aufbau, den man an seine Umgebung 
  anpassen muß (entsprechende Zeilen entkommentieren und anpassen): <br><br>
	
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
    #    user => "fhemuser",                                          
    #    password => "fhempassword",
    #    # optional enable(1) / disable(0) UTF-8 support (at least V 4.042 is necessary) 	
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
    <br>

  <a name="DbLogdefine"></a>
  <b>Define</b>
  <ul>
    <br>
	
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
        <code>set &lt;name&gt; configCheck</code> <br>
    </ul>
	<br>
	Dieser Check prüft einige wichtige Einstellungen des DbLog-Devices und gibt Empfehlungen für potentielle Verbesserungen. 
	<br><br>
	<br>
		
	DbLog unterscheidet den synchronen (Default) und asynchronen Logmodus. Der Logmodus ist über das 
	<a href="#DbLogattr">Attribut</a> asyncMode einstellbar. Ab Version 2.13.5 unterstützt DbLog einen gesetzten
	Primary Key (PK) in den Tabellen Current und History. Soll PostgreSQL mit PK genutzt werden, muss PostgreSQL mindestens
	Version 9.5 sein.
    <br><br>
	
    Der gespeicherte Wert des Readings wird optimiert für eine automatisierte Nachverarbeitung, z.B. <code>yes</code> wird transformiert 
	nach <code>1</code>. <br><br>
    
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
    <li> Wurde ein "set &lt;name&gt; configCheck" nach dem Define durchgeführt und eventuelle Fehler beseitigt bzw. Empfehlungen umgesetzt ? </li>
    <li> Falls configDB in Benutzung ... wurde das DB-Konfigurationsfile in configDB importiert (z.B. mit "configDB fileimport ./db.conf") ? </li>
    <li> Beim Anlegen eines SVG-Plots erscheint keine Drop-Down Liste mit Vorschlagswerten -> Attribut "DbLogType" auf "Current/History" setzen. </li>
    </ul>
    <br>
    
    Sollten diese Hinweise nicht zum Erfolg führen, bitte den verbose-Level im DbLog Device auf 4 oder 5 hochsetzen und 
    die Einträge bezüglich des DbLog-Device im Logfile beachten.
    
    Zur Problemanalyse bitte die Ausgabe von "list &lt;name&gt;", das Ergebnis von "set &lt;name&gt; configCheck" und die 
    Ausgaben des DbLog-Device im Logfile im Forumthread posten.
	<br><br>
	
  </ul>
  <br>
  <br>


  <a name="DbLogset"></a>
  <b>Set</b> 
  <ul>
    <code>set &lt;name&gt; addCacheLine YYYY-MM-DD HH:MM:SS|&lt;device&gt;|&lt;type&gt;|&lt;event&gt;|&lt;reading&gt;|&lt;value&gt;|[&lt;unit&gt;]  </code><br><br>
    <ul> Im asynchronen Modus wird ein neuer Datensatz in den Cache eingefügt und beim nächsten Synclauf mit abgearbeitet.
    <br><br>
      
	  <b>Beispiel:</b> <br>
	  set &lt;name&gt; addCacheLine 2017-12-05 17:03:59|MaxBathRoom|MAX|valveposition: 95|valveposition|95|% <br>
    </ul><br>
	
    <code>set &lt;name&gt; addLog &lt;devspec&gt;:&lt;Reading&gt; [Value] [CN=&lt;caller name&gt;] [!useExcludes] </code><br><br>
    <ul> Fügt einen zusätzlichen Logeintrag einer Device/Reading-Kombination in die Datenbank ein. Die eventuell im Attribut 
    "DbLogExclude" spezifizierten Readings (im Quelldevice) werden nicht geloggt, es sei denn sie sind im Attribut 
    "DbLogInclude"  enthalten bzw. der addLog-Aufruf erfolgte mit der Option "!useExcludes".  <br><br>
      
      <ul>
      <li> <b>&lt;devspec&gt;:&lt;Reading&gt;</b> - Das Device kann als <a href="#devspec">Geräte-Spezifikation</a> angegeben werden. <br>
                                                    Die Angabe von "Reading" wird als regulärer Ausdruck ausgewertet. Ist
                                                    das Reading nicht vorhanden und der Wert "Value" angegeben, wird das Reading
                                                    in die DB eingefügt wenn es kein regulärer Ausdruck und ein valider 
                                                    Readingname ist. </li>
      <li> <b>Value</b> - Optional kann "Value" für den Readingwert angegeben werden. Ist Value nicht angegeben, wird der aktuelle
                          Wert des Readings in die DB eingefügt. </li>  
      <li> <b>CN=&lt;caller name&gt;</b> - Mit dem Schlüssel "CN=" (<b>C</b>aller <b>N</b>ame) kann dem addLog-Aufruf ein String, 
                                           z.B. der Name des aufrufenden Devices (z.B. eines at- oder notify-Devices), mitgegeben 
                                           werden. Mit Hilfe der im <a href="#DbLogattr">Attribut</a> "valueFn" hinterlegten 
                                           Funktion kann dieser Schlüssel über die Variable $CN ausgewertet werden. Dadurch ist es 
                                           möglich, das Verhalten des addLogs abhängig von der aufrufenden Quelle zu beeinflussen. 
                                           </li> 
      <li> <b>!useExcludes</b> - Ein eventuell im Quell-Device gesetztes Attribut "DbLogExclude" wird von der Funktion berücksichtigt. Soll dieses 
                                 Attribut nicht berücksichtigt werden, kann das Schüsselwort "!useExcludes" verwendet werden. </li>
      </ul>
      <br>
      
      Das Datenbankfeld "EVENT" wird automatisch mit "addLog" belegt. <br>
	  Es wird KEIN zusätzlicher Event im System erzeugt !<br><br>
      
	  <b>Beispiele:</b> <br>
	  set &lt;name&gt; addLog SMA_Energymeter:Bezug_Wirkleistung <br>
	  set &lt;name&gt; addLog TYPE=SSCam:state <br>
	  set &lt;name&gt; addLog MyWetter:(fc10.*|fc8.*) <br>
	  set &lt;name&gt; addLog MyWetter:(wind|wind_ch.*) 20 !useExcludes <br>
	  set &lt;name&gt; addLog TYPE=CUL_HM:FILTER=model=HM-CC-RT-DN:FILTER=subType!=(virtual|):(measured-temp|desired-temp|actuator) <br><br>
      
      set &lt;name&gt; addLog USV:state CN=di.cronjob <br>
      In der valueFn-Funktion wird der Aufrufer "di.cronjob" über die Variable $CN ausgewertet und davon abhängig der 
      Timestamp dieses addLog korrigiert: <br><br>
      valueFn = if($CN eq "di.cronjob" and $TIMESTAMP =~ m/\s00:00:[\d:]+/) { $TIMESTAMP =~ s/\s([^\s]+)/ 23:59:59/ }      
      
    </ul><br>
	  
    <code>set &lt;name&gt; clearReadings </code><br><br>
      <ul> Leert Readings die von verschiedenen DbLog-Funktionen angelegt wurden. </ul><br>
	  
    <code>set &lt;name&gt; eraseReadings </code><br><br>
      <ul> Löscht alle Readings außer dem Reading "state". </ul><br>
	  
    <code>set &lt;name&gt; commitCache </code><br><br>
      <ul>Im asynchronen Modus (<a href="#DbLogattr">Attribut</a> asyncMode=1), werden die im Speicher gecachten Daten in die Datenbank geschrieben 
	  und danach der Cache geleert. Der interne Timer des asynchronen Modus wird dabei neu gesetzt.
      Der Befehl kann nützlich sein um manuell oder z.B. über ein AT den Cacheinhalt zu einem definierten Zeitpunkt in die 
	  Datenbank zu schreiben. </ul><br>

    <code>set &lt;name&gt; configCheck </code><br><br>
      <ul>Es werden einige wichtige Einstellungen geprüft und Empfehlungen gegeben falls potentielle Verbesserungen
	  identifiziert wurden. 
	  </ul><br/>

    <code>set &lt;name&gt; count </code><br><br>
      <ul>Zählt die Datensätze in den Tabellen current und history und schreibt die Ergebnisse in die Readings 
	  countCurrent und countHistory.</ul><br>
	  
    <code>set &lt;name&gt; countNbl </code><br><br>
      <ul>
      Die non-blocking Ausführung von "set &lt;name&gt; count".
      <br><br>

      <b>Hinweis:</b> <br>
      Obwohl die Funktion selbst non-blocking ist, muß das DbLog-Device im asynchronen Modus betrieben werden (asyncMode = 1)
      um FHEM nicht zu blockieren ! 
      </ul><br>

    <code>set &lt;name&gt; deleteOldDays &lt;n&gt;</code><br/><br>
      <ul>Löscht Datensätze in Tabelle history, die älter sind als &lt;n&gt; Tage sind. 
	  Die Anzahl der gelöschten Datens&auml;tze wird in das Reading lastRowsDeleted geschrieben.</ul><br>

    <code>set &lt;name&gt; deleteOldDaysNbl &lt;n&gt;</code><br><br>
      <ul>
      Identisch zu Funktion "deleteOldDays" wobei deleteOldDaysNbl nicht blockierend ausgeführt wird.
      <br><br>

      <b>Hinweis:</b> <br>
      Obwohl die Funktion selbst non-blocking ist, muß das DbLog-Device im asynchronen Modus betrieben werden (asyncMode = 1)
      um FHEM nicht zu blockieren !     
      </ul><br>	  

	<a name="DbLogsetexportCache"></a>
    <code>set &lt;name&gt; exportCache [nopurge | purgecache] </code><br><br>
      <ul>Wenn DbLog im asynchronen Modus betrieben wird, kann der Cache mit diesem Befehl in ein Textfile geschrieben
	  werden. Das File wird per Default in dem Verzeichnis (global->modpath)/log/ erstellt. Das Zielverzeichnis kann mit
	  dem <a href="#DbLogattr">Attribut</a> "expimpdir" geändert werden. <br>
	  Der Name des Files wird automatisch generiert und enthält den Präfix "cache_", gefolgt von dem DbLog-Devicenamen und
	  dem aktuellen Zeitstempel, z.B. "cache_LogDB_2017-03-23_22-13-55". <br>
      Mit den Optionen "nopurge" bzw. "purgecache" wird festgelegt, ob der Cacheinhalt nach dem Export gelöscht werden
      soll oder nicht. Mit "nopurge" (default) bleibt der Cacheinhalt erhalten. <br>
      Das <a href="#DbLogattr">Attribut</a> "exportCacheAppend" bestimmt dabei, ob mit jedem Exportvorgang ein neues Exportfile 
      angelegt wird (default) oder der Cacheinhalt an das bestehende (neueste) Exportfile angehängt wird.      
      </ul><br>
	  
    <code>set &lt;name&gt; importCachefile &lt;file&gt; </code><br><br>
      <ul>Importiert ein mit "exportCache" geschriebenes File in die Datenbank. 
	  Die verfügbaren Dateien werden per Default im Verzeichnis (global->modpath)/log/ gesucht und eine Drop-Down Liste
	  erzeugt sofern Dateien gefunden werden. Das Quellverzeichnis kann mit dem <a href="#DbLogattr">Attribut</a> expimpdir geändert werden. <br>
	  Es werden nur die Dateien angezeigt, die dem Muster "cache_", gefolgt von dem DbLog-Devicenamen entsprechen. <br> 
	  Zum Beispiel "cache_LogDB_2017-03-23_22-13-55", falls das Log-Device "LogDB" heißt. <br>
      Nach einem erfolgreichen Import wird das File mit dem Präfix "impdone_" versehen und erscheint dann nicht mehr
	  in der Drop-Down Liste. Soll ein Cachefile in eine andere als der Quelldatenbank importiert werden, kann das 
      DbLog-Device im Filenamen angepasst werden damit dieses File den Suchktiterien entspricht und in der Drop-Down Liste
      erscheint. </ul><br>
	  
    <code>set &lt;name&gt; listCache </code><br><br>
      <ul>Wenn DbLog im asynchronen Modus betrieben wird (Attribut asyncMode=1), können mit diesem Befehl die im Speicher gecachten Events 
	  angezeigt werden.</ul><br>

    <code>set &lt;name&gt; purgeCache </code><br><br>
      <ul>Im asynchronen Modus (<a href="#DbLogattr">Attribut</a> asyncMode=1), werden die im Speicher gecachten Daten gelöscht. 
      Es werden keine Daten aus dem Cache in die Datenbank geschrieben. </ul><br>
	  
    <code>set &lt;name&gt; reduceLog &lt;no&gt;[:&lt;nn&gt;] [average[=day]] [exclude=device1:reading1,device2:reading2,...] </code><br><br>
      <ul>Reduziert historische Datensätze, die älter sind als &lt;no&gt; Tage und (optional) neuer sind als &lt;nn&gt; Tage 
          auf einen Eintrag (den ersten) pro Stunde je Device & Reading.<br>
          Innerhalb von device/reading können <b>SQL-Wildcards "%" und "_"</b> verwendet werden. <br><br>
		  
		  Das Reading "reduceLogState" zeigt den Ausführungsstatus des letzten reduceLog-Befehls. <br><br>
          Durch die optionale Angabe von 'average' wird nicht nur die Datenbank bereinigt, sondern alle numerischen Werte 
		  einer Stunde werden auf einen einzigen Mittelwert reduziert. <br>
          Durch die optionale Angabe von 'average=day' wird nicht nur die Datenbank bereinigt, sondern alle numerischen 
		  Werte eines Tages auf einen einzigen Mittelwert reduziert. (impliziert 'average') <br><br>
          
          Optional kann als letzer Parameter "exclude=device1:reading1,device2:reading2,...." 
		  angegeben werden um device/reading Kombinationen von reduceLog auszuschließen. <br><br>
          
          Optional kann als letzer Parameter "include=device:reading" angegeben werden um 
		  die auf die Datenbank ausgeführte SELECT-Abfrage einzugrenzen, was die RAM-Belastung verringert und die 
		  Performance erhöht. <br><br>
          
          <ul>
          <b>Beispiel: </b> <br>
          set &lt;name&gt; reduceLog 270 average include=Luftdaten_remote:% <br>
          
          </ul>
          <br>
          
          <b>ACHTUNG:</b> Es wird dringend empfohlen zu überprüfen ob der standard INDEX 'Search_Idx' in der Tabelle 'history' existiert! <br>
		  Die Abarbeitung dieses Befehls dauert unter Umständen (ohne INDEX) extrem lange. FHEM wird durch den Befehl bis 
		  zur Fertigstellung <b>komplett blockiert !</b> <br><br>
          
          </ul><br>
		  
    <code>set &lt;name&gt; reduceLogNbl &lt;no&gt;[:&lt;nn&gt;] [average[=day]] [exclude=device1:reading1,device2:reading2,...]</code><br><br>
	      <ul>
	      Führt die gleiche Funktion wie "set &lt;name&gt; reduceLog" aus. Im Gegensatz zu reduceLog wird mit FHEM wird durch den Befehl reduceLogNbl nicht 
	      mehr blockiert da diese Funktion non-blocking implementiert ist ! 
          <br><br>

          <b>Hinweis:</b> <br>
          Obwohl die Funktion selbst non-blocking ist, muß das DbLog-Device im asynchronen Modus betrieben werden (asyncMode = 1)
          um FHEM nicht zu blockieren ! 
          </ul><br>
		  
    <code>set &lt;name&gt; reopen [n]</code><br/><br/>
      <ul>Schließt die Datenbank und öffnet sie danach sofort wieder wenn keine Zeit [n] in Sekunden angegeben wurde. 
	  Dabei wird die Journaldatei geleert und neu angelegt.<br/>
      Verbessert den Datendurchsatz und vermeidet Speicherplatzprobleme. <br>
	  Wurde eine optionale Verzögerungszeit [n] in Sekunden angegeben, wird die Verbindung zur Datenbank geschlossen und erst 
	  nach Ablauf von [n] Sekunden wieder neu verbunden. 
	  Im synchronen Modus werden die Events in dieser Zeit nicht gespeichert. 
	  Im asynchronen Modus werden die Events im Cache gespeichert und nach dem Reconnect in die Datenbank geschrieben. </ul><br>

    <code>set &lt;name&gt; rereadcfg </code><br/><br/>
      <ul>Schließt die Datenbank und öffnet sie danach sofort wieder. Dabei wird die Journaldatei geleert und neu angelegt.<br/>
      Verbessert den Datendurchsatz und vermeidet Speicherplatzprobleme.<br/>
      Zwischen dem Schließen der Verbindung und dem Neuverbinden werden die Konfigurationsdaten neu gelesen</ul><br/>

    <code>set &lt;name&gt; userCommand &lt;validSqlStatement&gt;</code><br/><br/>
      <ul>
        Führt einfache sql select Befehle auf der Datenbank aus. Der Befehl und ein zurückgeliefertes 
		Ergebnis wird in das Reading "userCommand" bzw. "userCommandResult" geschrieben. Das Ergebnis kann nur 
		einzeilig sein. 
		Die Ausführung von SQL-Befehlen in DbLog sind deprecated. Dafür sollte das Auswertungsmodul 
		<a href=https://fhem.de/commandref_DE.html#DbRep>DbRep</a> genutzt werden.</br>
      </ul><br>

  </ul><br>


  <a name="DbLogget"></a>
  <b>Get</b>
  <ul>
  <code>get &lt;name&gt; ReadingsVal&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; &lt;device&gt; &lt;reading&gt; &lt;default&gt;</code><br/>
  <code>get &lt;name&gt; ReadingsTimestamp &lt;device&gt; &lt;reading&gt; &lt;default&gt;</code><br/>
  <br/>
  Liest einen einzelnen Wert aus der Datenbank, Benutzung und Syntax sind weitgehend identisch zu ReadingsVal() und ReadingsTimestamp().<br/>
  </ul>
  <br/>
  <br/>
  <ul>
    <code>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;column_spec&gt; </code>
    <br><br>
    Liesst Daten aus der Datenbank. Wird durch die Frontends benutzt um Plots
    zu generieren ohne selbst auf die Datenank zugreifen zu müssen.
    <br>
    <ul>
      <li>&lt;in&gt;<br>
        Ein Parameter um eine Kompatibilität zum Filelog herzustellen.
        Dieser Parameter ist per default immer auf <code>-</code> zu setzen.<br>
        Folgende Ausprägungen sind zugelassen:<br>
        <ul>
          <li>current: die aktuellen Werte aus der Tabelle "current" werden gelesen.</li>
          <li>history: die historischen Werte aus der Tabelle "history" werden gelesen.</li>
          <li>-: identisch wie "history"</li>
        </ul> 
      </li>
	  
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
	  
      <li>&lt;from&gt; / &lt;to&gt;<br>
        Wird benutzt um den Zeitraum der Daten einzugrenzen. Es ist das folgende
        Zeitformat oder ein Teilstring davon zu benutzen:<br>
        <ul><code>YYYY-MM-DD_HH24:MI:SS</code></ul></li>
		
      <li>&lt;column_spec&gt;<br>
        Für jede column_spec Gruppe wird ein Datenset zurückgegeben welches
        durch einen Kommentar getrennt wird. Dieser Kommentar repräsentiert
        die column_spec.<br>
        Syntax: &lt;device&gt;:&lt;reading&gt;:&lt;default&gt;:&lt;fn&gt;:&lt;regexp&gt;<br>
        <ul>
          <li>&lt;device&gt;<br>
            Der Name des Devices. Achtung: Gross/Kleinschreibung beachten!<br>
            Es kann ein % als Jokerzeichen angegeben werden.</li>
          <li>&lt;reading&gt;<br>
            Das Reading des angegebenen Devices zur Datenselektion.<br>
            Es kann ein % als Jokerzeichen angegeben werden.<br>
            Achtung: Gross/Kleinschreibung beachten!
          </li>
          <li>&lt;default&gt;<br>
            Zur Zeit noch nicht implementiert.
          </li>
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
            </ul></li>
            <li>&lt;regexp&gt;<br>
              Diese Zeichenkette wird als Perl Befehl ausgewertet. 
			  Die regexp wird vor dem angegebenen &lt;fn&gt; Parameter ausgeführt.
              <br>
              Bitte zur Beachtung: Diese Zeichenkette darf keine Leerzeichen
              enthalten da diese sonst als &lt;column_spec&gt; Trennung
              interpretiert werden und alles nach dem Leerzeichen als neue
              &lt;column_spec&gt; gesehen wird.<br>
			  
              <b>Schlüsselwörter</b>
              <li>$val ist der aktuelle Wert die die Datenbank für ein Device/Reading ausgibt.</li>
              <li>$ts ist der aktuelle Timestamp des Logeintrages.</li>
              <li>Wird als $val das Schlüsselwort "hide" zurückgegeben, so wird dieser Logeintrag nicht
                  ausgegeben, trotzdem aber für die Zeitraumberechnung verwendet.</li>
              <li>Wird als $val das Schlüsselwort "ignore" zurückgegeben, so wird dieser Logeintrag
                  nicht für eine Folgeberechnung verwendet.</li>
            </li>
        </ul></li>
		
      </ul>
    <br><br>
    <b>Beispiele:</b>
      <ul>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature</code></li>
        
		<li><code>get myDbLog current ALL - - %:temperature</code></li><br>
            Damit erhält man alle aktuellen Readings "temperature" von allen in der DB geloggten Devices.
            Achtung: bei Nutzung von Jokerzeichen auf die history-Tabelle kann man sein FHEM aufgrund langer Laufzeit lahmlegen!
        
		<li><code>get myDbLog - - 2012-11-10_10 2012-11-10_20 KS300:temperature::int1</code><br>
           gibt Daten aus von 10Uhr bis 20Uhr am 10.11.2012</li>
        
		<li><code>get myDbLog - all 2012-11-10 2012-11-20 KS300:temperature</code></li>
        
		<li><code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature KS300:rain::delta-h KS300:rain::delta-d</code></li>
        
		<li><code>get myDbLog - - 2012-11-10 2012-11-20 MyFS20:data:::$val=~s/(on|off).*/$1eq"on"?1:0/eg</code><br>
           gibt 1 zurück für alle Ausprägungen von on* (on|on-for-timer etc) und 0 für alle off*</li>
        
		<li><code>get myDbLog - - 2012-11-10 2012-11-20 Bodenfeuchte:data:::$val=~s/.*B:\s([-\.\d]+).*/$1/eg</code><br>
           Beispiel von OWAD: Ein Wert wie z.B.: <code>"A: 49.527 % B: 66.647 % C: 9.797 % D: 0.097 V"</code><br>
           und die Ausgabe ist für das Reading B folgende: <code>2012-11-20_10:23:54 66.647</code></li>
        
		<li><code>get DbLog - - 2013-05-26 2013-05-28 Pumpe:data::delta-ts:$val=~s/on/hide/</code><br>
           Realisierung eines Betriebsstundenzählers. Durch delta-ts wird die Zeit in Sek zwischen den Log-
           Einträgen ermittelt. Die Zeiten werden bei den on-Meldungen nicht ausgegeben welche einer Abschaltzeit 
           entsprechen würden.</li>
      </ul>
    <br><br>
  </ul>

  <b>Get</b> für die Nutzung von webcharts
  <ul>
    <code>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;device&gt; &lt;querytype&gt; &lt;xaxis&gt; &lt;yaxis&gt; &lt;savename&gt; </code>
    <br><br>
    Liest Daten aus der Datenbank aus und gibt diese in JSON formatiert aus. Wird für das Charting Frontend genutzt
    <br>

    <ul>
      <li>&lt;name&gt;<br>
        Der Name des definierten DbLogs, so wie er in der fhem.cfg angegeben wurde.</li>
      
	  <li>&lt;in&gt;<br>
        Ein Dummy Parameter um eine Kompatibilität zum Filelog herzustellen.
        Dieser Parameter ist immer auf <code>-</code> zu setzen.</li>
      
	  <li>&lt;out&gt;<br>
        Ein Dummy Parameter um eine Kompatibilität zum Filelog herzustellen. 
        Dieser Parameter ist auf <code>webchart</code> zu setzen um die Charting Get Funktion zu nutzen.
      </li>
      
	  <li>&lt;from&gt; / &lt;to&gt;<br>
        Wird benutzt um den Zeitraum der Daten einzugrenzen. Es ist das folgende
        Zeitformat zu benutzen:<br>
        <ul><code>YYYY-MM-DD_HH24:MI:SS</code></ul></li>
      
	  <li>&lt;device&gt;<br>
        Ein String, der das abzufragende Device darstellt.</li>
      
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
      
	  <li>&lt;xaxis&gt;<br>
        Ein String, der die X-Achse repräsentiert</li>
      
	  <li>&lt;yaxis&gt;<br>
         Ein String, der die Y-Achse repräsentiert</li>
      
	  <li>&lt;savename&gt;<br>
         Ein String, unter dem ein Chart in der Datenbank gespeichert werden soll</li>
      
	  <li>&lt;chartconfig&gt;<br>
         Ein jsonstring der den zu speichernden Chart repräsentiert</li>
      
	  <li>&lt;pagingstart&gt;<br>
         Ein Integer um den Startwert für die Abfrage 'getTableData' festzulegen</li>
      
	  <li>&lt;paginglimit&gt;<br>
         Ein Integer um den Limitwert für die Abfrage 'getTableData' festzulegen</li>
      </ul>
    <br><br>
    
    <b>Beispiele:</b>
      <ul>
        <li><code>get logdb - webchart "" "" "" getcharts</code><br>
            Liefert alle gespeicherten Charts aus der Datenbank</li>
        
		<li><code>get logdb - webchart "" "" "" getdevices</code><br>
            Liefert alle verfügbaren Devices aus der Datenbank</li>
        
		<li><code>get logdb - webchart "" "" ESA2000_LED_011e getreadings</code><br>
            Liefert alle verfügbaren Readings aus der Datenbank unter Angabe eines Gerätes</li>
        
		<li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e timerange TIMESTAMP day_kwh</code><br>
            Liefert Chart-Daten, die auf folgenden Parametern basieren: 'xaxis', 'yaxis', 'device', 'to' und 'from'<br>
            Die Ausgabe erfolgt als JSON, z.B.: <code>[{'TIMESTAMP':'2013-02-11 00:10:10','VALUE':'0.22431388090756'},{'TIMESTAMP'.....}]</code></li>
        
		<li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e savechart TIMESTAMP day_kwh tageskwh</code><br>
            Speichert einen Chart unter Angabe eines 'savename' und seiner zugehörigen Konfiguration</li>
        
		<li><code>get logdb - webchart "" "" "" deletechart "" "" 7</code><br>
            Löscht einen zuvor gespeicherten Chart unter Angabe einer id</li>
      </ul>
    <br><br>
  </ul>

  <a name="DbLogattr"></a>
  <b>Attribute</b>
   <br><br>
 
  <ul>
    <a name="addStateEvent"></a>
    <li><b>addStateEvent</b>
    <ul>
	  <code>attr &lt;device&gt; addStateEvent [0|1]
	  </code><br>
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
    <a name="asyncMode"></a>
    <li><b>asyncMode</b>
    <ul>
	  <code>attr &lt;device&gt; asyncMode [1|0]
	  </code><br>
	  
      Dieses Attribut stellt den Arbeitsmodus von DbLog ein. Im asynchronen Modus (asyncMode=1), werden die zu speichernden Events zunächst in Speicher
	  gecacht. Nach Ablauf der Synchronisationszeit (Attribut syncInterval) oder bei Erreichen der maximalen Anzahl der Datensätze im Cache
	  (Attribut cacheLimit) werden die gecachten Events im Block in die Datenbank geschrieben.
	  Ist die Datenbank nicht verfügbar, werden die Events weiterhin im Speicher gehalten und nach Ablauf des Syncintervalls in die Datenbank
	  geschrieben falls sie dann verfügbar ist. <br>
	  Im asynchronen Mode werden die Daten nicht blockierend mit einem separaten Hintergrundprozess in die Datenbank geschrieben.
	  Det Timeout-Wert für diesen Hintergrundprozess kann mit dem Attribut "timeout" (Default 86400s) eingestellt werden.
	  Im synchronen Modus (Normalmodus) werden die Events nicht gecacht und sofort in die Datenbank geschrieben. Ist die Datenbank nicht 
	  verfügbar, gehen sie verloren.<br>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="bulkInsert"></a>
    <li><b>bulkInsert</b>
    <ul>
	  <code>attr &lt;device&gt; bulkInsert [1|0]
	  </code><br>
	  
      Schaltet den Insert-Modus zwischen "Array" (default) und "Bulk" um. Der Bulk Modus führt beim Insert von sehr 
      vielen Datensätzen in die history-Tabelle zu einer erheblichen Performancesteigerung vor allem im asynchronen 
      Mode. Um die volle Performancesteigerung zu erhalten, sollte in diesem Fall das Attribut "DbLogType" 
      <b>nicht</b> die current-Tabelle enthalten. <br>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="commitMode"></a>
    <li><b>commitMode</b>
    <ul>
	  <code>attr &lt;device&gt; commitMode [basic_ta:on | basic_ta:off | ac:on_ta:on | ac:on_ta:off | ac:off_ta:on]
	  </code><br>
	  
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
    <a name="cacheEvents"></a>
    <li><b>cacheEvents</b>
    <ul>
	  <code>attr &lt;device&gt; cacheEvents [2|1|0]
	  </code><br>
	  <ul>
      <li>cacheEvents=1: es werden Events für das Reading CacheUsage erzeugt wenn ein Event zum Cache hinzugefügt wurde. </li>
	  <li>cacheEvents=2: es werden Events für das Reading CacheUsage erzeugt wenn im asynchronen Mode der Schreibzyklus in die 
	                     Datenbank beginnt. CacheUsage enthält zu diesem Zeitpunkt die Anzahl der in die Datenbank zu schreibenden
						 Datensätze. </li><br>
	  </ul>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
     <a name="cacheLimit"></a>
     <li><b>cacheLimit</b>
     <ul>
	   <code>
	   attr &lt;device&gt; cacheLimit &lt;n&gt; 
	   </code><br>
	 
       Im asynchronen Logmodus wird der Cache in die Datenbank weggeschrieben und geleert wenn die Anzahl &lt;n&gt; Datensätze
       im Cache erreicht ist (Default: 500). Der Timer des asynchronen Logmodus wird dabei neu auf den Wert des Attributs "syncInterval" 
       gesetzt. Im Fehlerfall wird ein erneuter Schreibversuch frühestens nach syncInterval/2 gestartet. <br>
     </ul>
     </li>
  </ul>
  <br>
  
  <ul>
     <a name="colEvent"></a>
     <li><b>colEvent</b>
     <ul>
	   <code>
	   attr &lt;device&gt; colEvent &lt;n&gt; 
	   </code><br>
	 
	   Die Feldlänge für das DB-Feld EVENT wird userspezifisch angepasst. Mit dem Attribut kann der Default-Wert im Modul
	   verändert werden wenn die Feldlänge in der Datenbank manuell geändert wurde. Mit colEvent=0 wird das Datenbankfeld 
	   EVENT nicht gefüllt. <br>
	   <b>Hinweis:</b> <br> 
	   Mit gesetztem Attribut gelten alle Feldlängenbegrenzungen auch für SQLite DB wie im Internal COLUMNS angezeigt !  <br>
     </ul>
     </li>
  </ul>
  <br>
  
  <ul>
     <a name="colReading"></a>
     <li><b>colReading</b>
     <ul>
	   <code>
	   attr &lt;device&gt; colReading &lt;n&gt; 
	   </code><br>
	 
	   Die Feldlänge für das DB-Feld READING wird userspezifisch angepasst. Mit dem Attribut kann der Default-Wert im Modul
	   verändert werden wenn die Feldlänge in der Datenbank manuell geändert wurde. Mit colReading=0 wird das Datenbankfeld 
	   READING nicht gefüllt. <br>
	   <b>Hinweis:</b> <br>
	   Mit gesetztem Attribut gelten alle Feldlängenbegrenzungen auch für SQLite DB wie im Internal COLUMNS angezeigt !  <br>
     </ul>
     </li>
  </ul>
  <br>
  
  <ul>
     <a name="colValue"></a>
     <li><b>colValue</b>
     <ul>
	   <code>
	   attr &lt;device&gt; colValue &lt;n&gt; 
	   </code><br>
	 
	   Die Feldlänge für das DB-Feld VALUE wird userspezifisch angepasst. Mit dem Attribut kann der Default-Wert im Modul
	   verändert werden wenn die Feldlänge in der Datenbank manuell geändert wurde. Mit colValue=0 wird das Datenbankfeld 
	   VALUE nicht gefüllt. <br>
	   <b>Hinweis:</b> <br>
	   Mit gesetztem Attribut gelten alle Feldlängenbegrenzungen auch für SQLite DB wie im Internal COLUMNS angezeigt !  <br>
     </ul>
     </li>
  </ul>
  <br>
  
  <ul>
     <a name="DbLogType"></a>
     <li><b>DbLogType</b>
     <ul>
	   <code>
	   attr &lt;device&gt; DbLogType [Current|History|Current/History|SampleFill/History]
	   </code><br>
	 
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
    <a name="DbLogSelectionMode"></a>
    <li><b>DbLogSelectionMode</b>
    <ul>
	  <code>
	  attr &lt;device&gt; DbLogSelectionMode [Exclude|Include|Exclude/Include]
	  </code><br>
      
	  Dieses fuer DbLog-Devices spezifische Attribut beeinflußt, wie die Device-spezifischen Attribute
      DbLogExclude und DbLogInclude (s.u.) ausgewertet werden.<br>
      Fehlt dieses Attribut, wird "Exclude" als Default angenommen. <br>
   
      <ul>
        <li>Exclude: DbLog verhaelt sich wie bisher auch, alles was ueber die RegExp im DEF angegeben ist, wird geloggt, bis auf das,
                     was ueber die RegExp in DbLogExclude ausgeschlossen wird. <br>
                     Das Attribut DbLogInclude wird in diesem Fall nicht beruecksichtigt</li>
        <li>Include: Es wird nur das geloggt was ueber die RegExp in DbLogInclude (im Quelldevice) eingeschlossen wird. <br>
                     Das Attribut DbLogExclude wird in diesem Fall ebenso wenig beruecksichtigt wie die Regex im DEF. Auch
                     der Devicename (des Quelldevice) geht in die Auswertung nicht mit ein. </li>
        <li>Exclude/Include: Funktioniert im Wesentlichen wie "Exclude", nur das sowohl DbLogExclude als auch DbLogInclude
                             geprueft werden. Readings die durch DbLogExclude zwar ausgeschlossen wurden, mit DbLogInclude aber wiederum eingeschlossen werden,
                             werden somit dennoch geloggt. </li>
      </ul>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="DbLogInclude"></a>
    <li><b>DbLogInclude</b>
    <ul>
      <code>
      attr &lt;device&gt; DbLogInclude regex:MinInterval[:force],[regex:MinInterval[:force]] ...
      </code><br>
      
	  Wird DbLog genutzt, wird in allen Devices das Attribut <i>DbLogInclude</i> propagiert. 
	  DbLogInclude funktioniert im Endeffekt genau wie DbLogExclude, ausser dass Readings mit diesen RegExp 
	  in das Logging eingeschlossen statt ausgeschlossen werden koennen. <br>
      Ist MinIntervall angegeben, wird der Logeintrag nicht geloggt, wenn das Intervall noch nicht erreicht <b>und</b> der Wert 
      des Readings sich nicht verändert hat. 
      Ist der optionale Parameter "force" hinzugefügt, wird der Logeintrag auch dann nicht nicht geloggt, wenn sich der 
      Wert des Readings verändert hat. <br>
      Siehe auch das DbLog Attribut <i>DbLogSelectionMode</i>. Es beeinflußt wie DbLogExclude und DbLogInclude ausgewertet 
      werden. <br><br>

	  <b>Beispiel</b> <br>
      <code>attr MyDevice1 DbLogInclude .*</code> <br>
      <code>attr MyDevice2 DbLogInclude state,(floorplantext|MyUserReading):300,battery:3600</code> <br>
      <code>attr MyDevice2 DbLogInclude state,(floorplantext|MyUserReading):300:force,battery:3600:force</code>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="DbLogExclude"></a>
    <li><b>DbLogExclude</b>
    <ul>
      <code>
      attr &lt;device&gt; DbLogExclude regex:MinInterval[:force],[regex:MinInterval[:force]] ...
      </code><br>
    
      Wird DbLog genutzt, wird in allen Devices das Attribut <i>DbLogExclude</i> propagiert. 
	  Der Wert des Attributes wird als Regexp ausgewertet und schliesst die damit matchenden Readings von einem Logging aus. 
	  Einzelne Regexp werden durch Komma getrennt. <br>
      Ist MinIntervall angegeben, wird der Logeintrag nicht geloggt, wenn das Intervall noch nicht erreicht <b>und</b> der 
      Wert des Readings sich nicht verändert hat. 
      Ist der optionale Parameter "force" hinzugefügt, wird der Logeintrag auch dann nicht geloggt, wenn sich der 
      Wert des Readings verändert hat. <br>
      Siehe auch das DbLog Attribut <i>DbLogSelectionMode</i>. Es beeinflußt wie DbLogExclude und DbLogInclude ausgewertet 
      werden. <br><br>
    
	  <b>Beispiel</b> <br>
      <code>attr MyDevice1 DbLogExclude .*</code> <br>
      <code>attr MyDevice2 DbLogExclude state,(floorplantext|MyUserReading):300,battery:3600</code> <br>
      <code>attr MyDevice2 DbLogExclude state,(floorplantext|MyUserReading):300:force,battery:3600:force</code>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
     <a name="DbLogValueFn"></a>
     <li><b>DbLogValueFn</b>
     <ul>
	   <code>
	   attr &lt;device&gt; DbLogValueFn {}
	   </code><br>
       
       Wird DbLog genutzt, wird in allen Devices das Attribut <i>DbLogValueFn</i> propagiert.
	   Es kann über einen Perl-Ausdruck auf die Variablen $TIMESTAMP, $READING, $VALUE (Wert des Readings) und 
	   $UNIT (Einheit des Readingswert) zugegriffen werden und diese verändern, d.h. die veränderten Werte werden geloggt.
       Außerdem hat man lesenden Zugriff auf $EVENT für eine Auswertung im Perl-Ausdruck. 
	   $EVENT kann nicht verändert werden. <br>
	   Soll $TIMESTAMP verändert werden, muss die Form "yyyy-mm-dd hh:mm:ss" eingehalten werden, ansonsten wird der 
	   geänderte $timestamp nicht übernommen.
	   Zusätzlich kann durch Setzen der Variable "$IGNORE=1" der Datensatz vom Logging ausgeschlossen werden. <br> 
       Die devicespezifische Funktion in "DbLogValueFn" wird vor der eventuell im DbLog-Device vorhandenen Funktion im Attribut 
       "valueFn" auf den Datensatz angewendet.
       <br><br>
	   
	   <b>Beispiel</b> <br>
       <pre>
attr SMA_Energymeter DbLogValueFn
{ 
  if ($READING eq "Bezug_WirkP_Kosten_Diff"){
    $UNIT="Diff-W";
  }
  if ($READING =~ /Einspeisung_Wirkleistung_Zaehler/ && $VALUE < 2){
    $IGNORE=1;
  }
}
	   </pre>
     </ul>
     </li>
  </ul>
  
  <ul>
    <a name="dbSchema"></a>
    <li><b>dbSchema</b>
    <ul>
      <code>
      attr &lt;device&gt; dbSchema &lt;schema&gt;
      </code><br>
	  
      Dieses Attribut ist setzbar für die Datenbanken MySQL/MariaDB und PostgreSQL. Die Tabellennamen (current/history) werden 
      durch das angegebene Datenbankschema ergänzt. Das Attribut ist ein advanced Feature und nomalerweise nicht nötig zu setzen.
      <br>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="disable"></a>
    <li><b>disable</b>
    <ul>
      <code>
      attr &lt;device&gt; disable [0|1]
      </code><br>
    
      Das DbLog Device wird disabled (1) bzw. enabled (0). 
      <br>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
     <a name="excludeDevs"></a>
     <li><b>excludeDevs</b>
     <ul>
	   <code>
	   attr &lt;device&gt; excludeDevs &lt;devspec1&gt;[#Reading],&lt;devspec2&gt;[#Reading],&lt;devspec...&gt; 
	   </code><br>
      
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
     <a name="expimpdir"></a>
     <li><b>expimpdir</b>
     <ul>
	   <code>
	   attr &lt;device&gt; expimpdir &lt;directory&gt; 
	   </code><br>
      
	   In diesem Verzeichnis wird das Cachefile beim Export angelegt bzw. beim Import gesucht. Siehe set-Kommandos 
	   <a href="#DbLogsetexportCache">"exportCache"</a> bzw. "importCachefile". Das Default-Verzeichnis ist "(global->modpath)/log/". 
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
     <a name="exportCacheAppend"></a>
     <li><b>exportCacheAppend</b>
     <ul>
	   <code>
	   attr &lt;device&gt; exportCacheAppend [1|0]
	   </code><br>
	   
       Wenn gesetzt, wird beim Export des Cache ("set &lt;device&gt; exportCache") der Cacheinhalt an das neueste bereits vorhandene
       Exportfile angehängt. Ist noch kein Exportfile vorhanden, wird es neu angelegt. <br>
       Ist das Attribut nicht gesetzt, wird bei jedem Exportvorgang ein neues Exportfile angelegt. (default)<br/>
     </ul>
     </li>
  </ul>
  <br>
  
  <ul>
     <a name="noNotifyDev"></a>
     <li><b>noNotifyDev</b>
     <ul>
	   <code>
	   attr &lt;device&gt; noNotifyDev [1|0]
	   </code><br>
	   
       Erzwingt dass NOTIFYDEV nicht gesetzt und somit nicht verwendet wird.<br>
     </ul>
     </li>
  </ul>
  <br>
  
  <ul>
     <a name="noSupportPK"></a>
     <li><b>noSupportPK</b>
     <ul>
	   <code>
	   attr &lt;device&gt; noSupportPK [1|0]
	   </code><br>
	   
       Deaktiviert die programmtechnische Unterstützung eines gesetzten Primary Key durch das Modul.<br>
     </ul>
     </li>
  </ul>
  <br>
  
  <ul>
    <a name="showproctime"></a>
    <li><b>showproctime</b>
    <ul>
	  <code>attr &lt;device&gt; showproctime [1|0]
	  </code><br>
	  
      Wenn gesetzt, zeigt das Reading "sql_processing_time" die benötigte Abarbeitungszeit (in Sekunden) für die SQL-Ausführung der
	  durchgeführten Funktion. Dabei wird nicht ein einzelnes SQL-Statement, sondern die Summe aller notwendigen SQL-Abfragen innerhalb der
	  jeweiligen Funktion betrachtet. Das Reading "background_processing_time" zeigt die im Kindprozess BlockingCall verbrauchte Zeit.<br>
	  
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="showNotifyTime"></a>
    <li><b>showNotifyTime</b>
    <ul>
	  <code>attr &lt;device&gt; showNotifyTime [1|0]
	  </code><br>
	  
      Wenn gesetzt, zeigt das Reading "notify_processing_time" die benötigte Abarbeitungszeit (in Sekunden) für die 
	  Abarbeitung der DbLog Notify-Funktion. Das Attribut ist für Performance Analysen geeignet und hilft auch die Unterschiede
	  im Zeitbedarf bei der Umschaltung des synchronen in den asynchronen Modus festzustellen. <br>
	  
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="syncEvents"></a>
    <li><b>syncEvents</b>
    <ul>
	  <code>attr &lt;device&gt; syncEvents [1|0]
	  </code><br>
	  
      es werden Events für Reading NextSync erzeugt. <br>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="syncInterval"></a>
    <li><b>syncInterval</b>
    <ul>
	  <code>attr &lt;device&gt; syncInterval &lt;n&gt;
	  </code><br>
	  
      Wenn DbLog im asynchronen Modus betrieben wird (Attribut asyncMode=1), wird mit diesem Attribut das Intervall in Sekunden zur Speicherung
	  der im Speicher gecachten Events in die Datenbank eingestellt. Der Defaultwert ist 30 Sekunden. <br>
	  
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="suppressAddLogV3"></a>
    <li><b>suppressAddLogV3</b>
    <ul>
	  <code>attr &lt;device&gt; suppressAddLogV3 [1|0]
	  </code><br>
	  
      Wenn gesetzt werden verbose 3 Logeinträge durch die addLog-Funktion unterdrückt.  <br>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="suppressUndef"></a>
    <li><b>suppressUndef</b>
    <ul>
	  <code>attr &lt;device&gt; suppressUndef <n>
	  </code><br>
      Unterdrueckt alle undef Werte die durch eine Get-Anfrage zb. Plot aus der Datenbank selektiert werden <br><br>

	  <b>Beispiel</b> <br>
      <code>#DbLog eMeter:power:::$val=($val>1500)?undef:$val</code>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="timeout"></a>
    <li><b>timeout</b>
    <ul>
	  <code>
	  attr &lt;device&gt; timeout &lt;n&gt;
	  </code><br>
      Setzt den Timeout-Wert für den Schreibzyklus in die Datenbank im asynchronen Modus (default 86400s). <br>
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="traceFlag"></a>
    <li><b>traceFlag</b>
    <ul>
	  <code>
	  attr &lt;device&gt; traceFlag &lt;ALL|SQL|CON|ENC|DBD|TXN&gt;
	  </code><br>
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
    <a name="traceHandles"></a>
    <li><b>traceHandles</b>
    <ul>
	  <code>attr &lt;device&gt; traceHandles &lt;n&gt;
	  </code><br>
	  
      Wenn gesetzt, werden alle &lt;n&gt; Sekunden die systemweit vorhandenen Datenbank-Handles im Logfile ausgegeben.
      Dieses Attribut ist nur für Supportzwecke relevant. (Default: 0 = ausgeschaltet) <br>
	  
    </ul>
    </li>
  </ul>
  <br>
  
  <ul>
    <a name="traceLevel"></a>
    <li><b>traceLevel</b>
    <ul>
	  <code>
	  attr &lt;device&gt; traceLevel &lt;0|1|2|3|4|5|6|7&gt;
	  </code><br>
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
    <a name="useCharfilter"></a>
    <li><b>useCharfilter</b>
    <ul>
	  <code>
	  attr &lt;device&gt; useCharfilter [0|1] <n>
	  </code><br>
      wenn gesetzt, werden nur ASCII Zeichen von 32 bis 126 im Event akzeptiert. (default: 0) <br>
	  Das sind die Zeichen " A-Za-z0-9!"#$%&'()*+,-.\/:;<=>?@[\\]^_`{|}~". <br>
	  Umlaute und "€" werden umgesetzt (z.B. ä nach ae, € nach EUR).  <br>
    </ul>
    </li>
  </ul>
  <br>

  <ul>
     <a name="valueFn"></a>
     <li><b>valueFn</b>
     <ul>
	   <code>
	   attr &lt;device&gt; valueFn {}
	   </code><br>
      
	   Es kann über einen Perl-Ausdruck auf die Variablen $TIMESTAMP, $DEVICE, $DEVICETYPE, $READING, $VALUE (Wert des Readings) und 
	   $UNIT (Einheit des Readingswert) zugegriffen werden und diese verändern, d.h. die veränderten Werte werden geloggt.
       Außerdem hat man lesenden Zugriff auf $EVENT für eine Auswertung im Perl-Ausdruck. 
	   Diese Variable kann aber nicht verändert werden. <br>
	   Soll $TIMESTAMP verändert werden, muss die Form "yyyy-mm-dd hh:mm:ss" eingehalten werden, ansonsten wird der 
	   geänderte $timestamp nicht übernommen.
	   Zusätzlich kann durch Setzen der Variable "$IGNORE=1" ein Datensatz vom Logging ausgeschlossen werden. <br><br>
	   
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
     <a name="verbose4Devs"></a>
     <li><b>verbose4Devs</b>
     <ul>
	   <code>
	   attr &lt;device&gt; verbose4Devs &lt;device1&gt;,&lt;device2&gt;,&lt;device..&gt; 
	   </code><br>
      
	   Mit verbose Level 4 werden nur Ausgaben bezüglich der in diesem Attribut aufgeführten Devices im Logfile protokolliert. Ohne dieses 
       Attribut werden mit verbose 4 Ausgaben aller relevanten Devices im Logfile protokolliert.
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
        "Data::Dumper": 0,
        "DBI": 0,
        "Blocking": 0,
        "Time::HiRes": 0,
        "Time::Local": 0,
        "HttpUtils": 0,
        "Encode": 0        
      },
      "recommends": {
        "FHEM::Meta": 0,
        "Devel::Size": 0,
        "Data::Peek": 0
      },
      "suggests": {
        "DBD::Pg" :0,
        "DBD::mysql" :0,
        "DBD::SQLite" :0
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


