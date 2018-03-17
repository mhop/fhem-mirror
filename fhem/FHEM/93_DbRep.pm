##########################################################################################################
# $Id$
##########################################################################################################
#       93_DbRep.pm
#
#       (c) 2016-2018 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This Module can be used to select and report content of databases written by 93_DbLog module
#       in different manner.
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
#  Credits:
#  - viegener for some input
#  - some proposals to boost and improve SQL-Statements by JoeALLb
#
###########################################################################################################################
#
# Definition: define <name> DbRep <DbLog-Device>
#
# This module uses credentials of the DbLog-Device
#
###########################################################################################################################
#  Versions History:
#  
# 7.14.5       17.03.2018       perl warnings of DbLog $dn,$dt,$evt,$rd in changeval_Push & complex
# 7.14.4       11.03.2018       increased timeout of BlockingCall in DbRep_firstconnect
# 7.14.3       07.03.2018       DbRep_firstconnect changed - get lowest timestamp in database, DbRep_Connect deleted
# 7.14.2       04.03.2018       fix perl warning
# 7.14.1       01.03.2018       currentfillup_Push bugfix for PostgreSQL
# 7.14.0       26.02.2018       syncStandby
# 7.13.3       25.02.2018       commandref revised (forum:#84953)
# 7.13.2       24.02.2018       DbRep_firstconnect changed, bug fix in DbRep_collaggstr for aggregation = month
# 7.13.1       20.02.2018       commandref revised
# 7.13.0       17.02.2018       changeValue can handle perl code {} as "new string"
# 7.12.0       16.02.2018       compression of dumpfile, restore of compressed files possible
# 7.11.0       12.02.2018       new command "repairSQLite" to repair a corrupted SQLite database
# 7.10.0       10.02.2018       bugfix delete attr timeYearPeriod if set other time attributes, new "changeValue" command
# 7.9.0        09.02.2018       new attribute "avgTimeWeightMean" (time weight mean calculation), code review of selection
#                               routines, maxValue handle negative values correctly, 
#                               one security second for correct create TimeArray in DbRep_normRelTime
# 7.8.1        04.02.2018       bugfix if IsDisabled (again), code review, bugfix last dataset is not selected if timestamp
#                               is fully set ("date time"), fix "$runtime_string_next = "$runtime_string_next.999";" if 
#                               $runtime_string_next is part of sql-execute place holder AND contains date+time
# 7.8.0        04.02.2018       new command "eraseReadings"  
# 7.7.1        03.02.2018       minor fix in DbRep_firstconnect if IsDisabled
# 7.7.0        29.01.2018       attribute "averageCalcForm", calculation sceme "avgDailyMeanGWS", "avgArithmeticMean" for 
#                               averageValue
# 7.6.1        27.01.2018       new attribute "sqlCmdHistoryLength" and "fetchMarkDuplicates" for highlighting multiple
#                               datasets by fetchrows
# 7.6.0        26.01.2018       events containing "|" possible in fetchrows & delSeqDoublets, fetchrows displays multiple  
#                               $k entries with timestamp suffix $k (as index), sqlCmdHistory (avaiable if sqlCmd was 
#                               executed)
# 7.5.5        25.01.2018       minor change in delSeqDoublets
# 7.5.4        24.01.2018       delseqdoubl_DoParse reviewed to optimize memory usage, executeBeforeDump executeAfterDump 
#                               now available for "delSeqDoublets"
# 7.5.3        23.01.2018       new attribute "ftpDumpFilesKeep", version management added to FTP-usage
# 7.5.2        23.01.2018       fix typo DumpRowsCurrrent, dumpFilesKeep can be set to "0", commandref revised
# 7.5.1        20.01.2018       DbRep_DumpDone changed to create background_processing_time before execute "executeAfterProc" 
#                               Commandref updated
# 7.5.0        16.01.2018       DbRep_OutputWriteToDB, set options display/writeToDB for (max|min|sum|average|diff)Value
# 7.4.1        14.01.2018       fix old dumpfiles not deleted by dumpMySQL clientSide
# 7.4.0        09.01.2018       dumpSQLite/restoreSQLite, 
#                               backup/restore now available when DbLog-device has reopen xxxx running, 
#                               executeBeforeDump executeAfterDump also available for optimizeTables, vacuum, restoreMySQL, 
#                               restoreSQLite, 
#                               attribute executeBeforeDump / executeAfterDump renamed to executeBeforeProc & executeAfterProc
# 7.3.1        08.01.2018       fix syntax error for perl < 5.20
# 7.3.0        07.01.2018       DbRep-charfilter avoid control characters in datasets to export, impfile_Push errortext
#                               improved, 
#                               expfile_DoParse changed to use aggregation for split selects in timeslices (avoid heavy 
#                               memory consumption)
# 7.2.1        04.01.2018       bugfix month out of range that causes fhem crash
# 7.2.0        27.12.2017       new attribute "seqDoubletsVariance"
# 7.1.0        22.12.2017       new attribute timeYearPeriod for reports correspondig to e.g. electricity billing,
#                               bugfix connection check is running after restart allthough dev is disabled 
# 7.0.0        18.12.2017       don't set $runtime_string_first,$runtime_string_next,$ts if time/aggregation-attributes 
#                               not set, change_Push redesigned, new command get blockinginfo, identify if reopen is 
#                               running on dblog-device and postpone the set-command
# 6.4.3        17.12.2017       bugfix in delSeqDoublets, fetchrows if datasets contain characters like "' <blank> and s.o.
# 6.4.2        15.12.2017       change "delSeqDoublets" to respect attribute "limit" (adviceDelete,adviceRemain), 
#                               commandref revised
# 6.4.1        13.12.2017       new Attribute "sqlResultFieldSep" for field separate options of sqlCmd result
# 6.4.0        10.12.2017       prepare module for usage of datetime picker widget (Forum:#35736) 
# 6.3.2        05.12.2017       make direction of fetchrows switchable ASC <-> DESC by attribute fetchRoute
# 6.3.1        04.12.2017       fix DBD::mysql::st execute failed: Expression #1 of SELECT list is not in GROUP BY clause
#                               and contains nonaggregated column 'DEVELfhem.history.TIMESTAMP' which is not functionally 
#                               dependent on columns in GROUP BY clause; this is incompatible with 
#                               sql_mode=only_full_group_by  
#                               Forum:https://forum.fhem.de/index.php/topic,65860.msg725595.html#msg725595 ,
#                               fix currentfillup_Push PostgreSQL -> use $runtime_string_next as Timestring during current
#                               insert
# 6.3.0        04.12.2017       support addition format d:xx h:xx m:xx s:xx for attributes timeDiffToNow, timeOlderThan
# 6.2.3        04.12.2017       fix localtime(time); (current time deduction) in DbRep_createTimeArray
# 6.2.2        01.12.2017       support all aggregations for delSeqDoublets, better output filesize when mysql dump finished
# 6.2.1        30.11.2017       support delSeqDoublets without device,reading is set and support device-devspec, reading list,
#                               minor fixes in delSeqDoublets
# 6.2.0        29.11.2017       enhanced command delSeqDoublets by "delete"
# 6.1.0        29.11.2017       new command delSeqDoublets (adviceRemain,adviceDelete), add Option to LASTCMD
# 6.0.0        18.11.2017       FTP transfer dumpfile after dump, delete old dumpfiles within Blockingcall (avoid freezes)
#                               commandref revised, minor fixes
# 5.8.6        30.10.2017       don't limit attr reading, device if the attr contains a list
# 5.8.5        19.10.2017       filter unwanted characters in "procinfo"-result 
# 5.8.4        17.10.2017       DbRep_createSelectSql, DbRep_createDeleteSql, currentfillup_Push switch to devspec 
# 5.8.3        16.10.2017       change to use DbRep_createSelectSql: minValue,diffValue - DbRep_createDeleteSql: delEntries
# 5.8.2        15.10.2017       sub DbRep_createTimeArray
# 5.8.1        15.10.2017       change to use DbRep_createSelectSql: sumValue,averageValue,exportToFile,maxValue
# 5.8.0        15.10.2017       adapt DbRep_createSelectSql for better performance if time/aggregation not set, 
#                               can set table as flexible argument for countEntries, fetchrows (default: history),
#                               minor fixes
# 5.7.1        13.10.2017       tableCurrentFillup fix for PostgreSQL, commandref revised
# 5.7.0        09.10.2017       tableCurrentPurge, tableCurrentFillup
# 5.6.4        05.10.2017       abortFn's adapted to use abortArg (Forum:77472)
# 5.6.3        01.10.2017       fix crash of fhem due to wrong rmday-calculation if month is changed, Forum:#77328
# 5.6.2        28.08.2017       commandref revised
# 5.6.1        18.07.2017       commandref revised, minor fixes
# 5.6.0        17.07.2017       default timeout changed to 86400, new get-command "procinfo" (MySQL)
# 5.5.2        16.07.2017       dbmeta_DoParse -> show variables (no global)
# 5.5.1        16.07.2017       wrong text output in state when restoreMySQL was aborted by timeout
# 5.5.0        10.07.2017       replace $hash->{dbloghash}{DBMODEL} by $hash->{dbloghash}{MODEL} (DbLog was changed)
# 5.4.0        03.07.2017       restoreMySQL - restore of csv-files (from dumpServerSide), 
#                               RestoreRowsHistory/ DumpRowsHistory, Commandref revised
# 5.3.1        28.06.2017       vacuum for SQLite added, readings enhanced for optimizeTables / vacuum, commandref revised
# 5.3.0        26.06.2017       change of DbRep_mysqlOptimizeTables, new command optimizeTables
# 5.2.1        25.06.2017       bugfix in sqlCmd_DoParse (PRAGMA, UTF8, SHOW)
# 5.2.0        14.06.2017       UTF-8 support for MySQL (fetchrows, srvinfo, expfile, impfile, insert)
# 5.1.0        13.06.2017       column "UNIT" added to fetchrow result
# 5.0.6        13.06.2017       add Aria engine to DbRep_mysqlOptimizeTables
# 5.0.5        12.06.2017       bugfixes in DbRep_DumpAborted, some changes in dumpMySQL, optimizeTablesBeforeDump added to
#                               mysql_DoDumpServerSide, new reading DumpFileCreatedSize
# 5.0.4        09.06.2017       some improvements and changes of mysql_DoDump, commandref revised, new attributes 
#                               executeBeforeDump, executeAfterDump
# 5.0.3        07.06.2017       mysql_DoDumpServerSide added
# 5.0.2        06.06.2017       little improvements in mysql_DoDumpClientSide
# 5.0.1        05.06.2017       dependencies between dumpMemlimit and dumpSpeed created, enhanced verbose 5 logging
# 5.0.0        04.06.2017       MySQL Dump nonblocking added
# 4.16.1       22.05.2017       encode json without JSON module, requires at least fhem.pl 14348 2017-05-22 20:25:06Z
# 4.16.0       22.05.2017       format json as option of sqlResultFormat, state will never be deleted in "DbRep_delread" 
# 4.15.1       20.05.2017       correction of commandref
# 4.15.0       17.05.2017       SUM(VALUE),AVG(VALUE) recreated for PostgreSQL, Code reviewed and optimized
# 4.14.2       16.05.2017       SQL-Statements optimized for Wildcard "%" usage if used, Wildcard "_" isn't supported
#                               furthermore, "averageValue", "sumValue", "maxValue", "minValue", "countEntries" 
#                               performance optimized, 
#                               commandref revised  
# 4.14.1       16.05.2017       limitation of fetchrows result datasets to 1000 by attr limit 
# 4.14.0       15.05.2017       UserExitFn added as separate sub (DbRep_userexit) and attr userExitFn defined,
#                               new subs ReadingsBulkUpdateTimeState, ReadingsBulkUpdateValue, 
#                               ReadingsSingleUpdateValue, commandref revised
# 4.13.7       11.05.2017       attribute sqlResultSingleFormat became sqlResultFormat, sqlResultSingle deleted and 
#                               sqlCmd contains now all format possibilities (separated,mline,sline,table), 
#                               commandref revised 
# 4.13.6       10.05.2017       minor changes
# 4.13.5       09.05.2017       cover dbh prepare in eval to avoid crash (sqlResult_DoParse)
# 4.13.4       09.05.2017       attribute sqlResultSingleFormat: mline sline table, attribute "allowDeletion" is now
#                               also valid for sqlResult, sqlResultSingle and delete command is forced
# 4.13.3       09.05.2017       flexible format of reading SqlResultRow_xxx for proper and sort sequence 
# 4.13.2       09.05.2017       sqlResult, sqlResultSingle are able to execute delete, insert, update commands
#                               error corrections
# 4.13.1       09.05.2017       change substitution in sqlResult, sqlResult_DoParse
# 4.13.0       09.05.2017       acceptance of viegener change with some corrections (separating lines with ]|[ in Singleline)
# viegener     07.05.2017       New sets sqlSelect execute arbitrary sql command returning each row as single reading (fields separated with |)
#                               allowing replacement of timestamp values according to attribute definition --> §timestamp_begin§ etc
#                               and sqlSelectSingle for executing an sql command returning a single reading (separating lines with §) 
# 4.12.2       17.04.2017       DbRep_checkUsePK changed
# 4.12.1       07.04.2017       get tableinfo changed for MySQL
# 4.12.0       31.03.2017       support of primary key for insert functions
# 4.11.4       29.03.2017       bugfix timestamp in minValue, maxValue if VALUE contains more than one
#                               numeric value (like in sysmon)
# 4.11.3       26.03.2017       usage of daylight saving time changed to avoid wrong selection when wintertime
#                               switch to summertime, minor bug fixes
# 4.11.2       16.03.2017       bugfix in func dbmeta_DoParse (SQLITE_DB_FILENAME)
# 4.11.1       28.02.2017       commandref completed
# 4.11.0       18.02.2017       added [current|previous]_[month|week|day|hour]_begin and 
#                               [current|previous]_[month|week|day|hour]_end as options of timestamp
# 4.10.3       01.02.2017       rename reading "diff-overrun_limit-" to "diff_overrun_limit_", 
#                               DbRep_collaggstr day aggregation changed back from 4.7.5 change
# 4.10.2       16.01.2017       bugfix uninitialized value $renmode if RenameAgent
# 4.10.1       30.11.2016       bugfix importFromFile format problem if UNIT-field wasn't set
# 4.10         28.12.2016       del_DoParse changed to use Wildcards, del_ParseDone changed to use readingNameMap
# 4.9          23.12.2016       function readingRename added
# 4.8.6        17.12.2016       new bugfix group by-clause due to incompatible changes made in MyQL 5.7.5
#                               (Forum #msg541103)
# 4.8.5        16.12.2016       bugfix group by-clause due to Forum #msg540610
# 4.8.4        13.12.2016       added "group by ...,table_schema" to select in dbmeta_DoParse due to Forum #msg539228,
#                               commandref adapted, changed "not_enough_data_in_period" to "less_data_in_period"
# 4.8.3        12.12.2016       balance diff to next period if value of period is 0 between two periods with 
#                               values 
# 4.8.2        10.12.2016       bugfix negativ diff if balanced
# 4.8.1        10.12.2016       added balance diff to diffValue, a difference between the last value of an
#                               old aggregation period to the first value of a new aggregation period will be take over now
# 4.8          09.12.2016       diffValue selection chenged to "between"
# 4.7.7        08.12.2016       code review
# 4.7.6        07.12.2016       DbRep version as internal, check if perl module DBI is installed
# 4.7.5        05.12.2016       DbRep_collaggstr day aggregation changed
# 4.7.4        28.11.2016       sub DbRep_calcount changed due to Forum #msg529312
# 4.7.3        20.11.2016       new diffValue function made suitable to SQLite
# 4.7.2        20.11.2016       commandref adapted, state = Warnings adapted
# 4.7.1        17.11.2016       changed fieldlength to DbLog new standard, diffValue state Warnings due to 
#                               several situations and generate readings not_enough_data_in_period, diff-overrun_limit
# 4.7          16.11.2016       sub diffValue changed due to Forum #msg520154, attr diffAccept added,
#                               diffValue now able to calculate if counter was going to 0
# 4.6.1        01.11.2016       daylight saving time check improved
# 4.6          31.10.2016       bugfix calc issue due to daylight saving time end (winter time)
# 4.5.1        18.10.2016       get svrinfo contains SQLite database file size (MB),
#                               modified timeout routine
# 4.5          17.10.2016       get data of dbstatus, dbvars, tableinfo, svrinfo (database dependend)
# 4.4          13.10.2016       get function prepared
# 4.3          11.10.2016       Preparation of get metadata
# 4.2          10.10.2016       allow SQL-Wildcards (% _) in attr reading & attr device
# 4.1.3        09.10.2016       bugfix delEntries running on SQLite
# 4.1.2        08.10.2016       old device in DEF of connected DbLog device will substitute by renamed device if 
#                               it is present in DEF 
# 4.1.1        06.10.2016       NotifyFn is getting events from global AND own device, set is reduced if
#                               ROLE=Agent, english commandref enhanced
# 4.1          05.10.2016       DbRep_Attr changed 
# 4.0          04.10.2016       Internal/Attribute ROLE added, sub DbRep_firstconnect changed 
#                               NotifyFN activated to start deviceRename if ROLE=Agent
# 3.13         03.10.2016       added deviceRename to rename devices in database, new Internal DATABASE
# 3.12         02.10.2016       function minValue added
# 3.11.1       30.09.2016       bugfix include first and next day in calculation if Timestamp is exactly 'YYYY-MM-DD 00:00:00'
# 3.11         29.09.2016       maxValue calculation moved to background to reduce FHEM-load
# 3.10.1       28.09.2016       sub impFile -> changed $dbh->{AutoCommit} = 0 to $dbh->begin_work
# 3.10         27.09.2016       diffValue calculation moved to background to reduce FHEM-load,
#                               new reading background_processing_time
# 3.9.1        27.09.2016       Internal "LASTCMD" added
# 3.9          26.09.2016       new function importFromFile to import data from file (CSV format)
# 3.8          16.09.2016       new attr readingPreventFromDel to prevent readings from deletion
#                               when a new operation starts
# 3.7.3        11.09.2016       changed format of diffValue-reading if no value was selected
# 3.7.2        04.09.2016       problem in diffValue fixed if if no value was selected
# 3.7.1        31.08.2016       Reading "errortext" added, commandref continued, exportToFile changed,
#                               diffValue changed to fix wrong timestamp if error occur
# 3.7          30.08.2016       exportToFile added (exports data to file (CSV format)
# 3.6          29.08.2016       plausibility checks of database column character length
# 3.5.2        21.08.2016       fit to new commandref style
# 3.5.1        20.08.2016       commandref continued
# 3.5          18.08.2016       new attribute timeOlderThan
# 3.4.4        12.08.2016       current_year_begin, previous_year_begin, current_year_end, previous_year_end
#                               added as possible values for timestmp attribute
# 3.4.3        09.08.2016       fields for input using "insert" changed to "date,time,value,unit". Attributes
#                               device, reading will be used to complete dataset,
#                               now more informations available about faulty datasets in arithmetic operations
# 3.4.2        05.08.2016       commandref complemented, fieldlength used in function "insert" trimmed to 32 
# 3.4.1        04.08.2016       check of numeric value type in functions maxvalue, diffvalue
# 3.4          03.08.2016       function "insert" added
# 3.3.3        16.07.2016       bugfix of aggregation=week if month start is 01 and month end is 12 AND 
#                               the last week of december is "01" like in 2014 (checked in version 11804)
# 3.3.2        16.07.2016       readings completed with begin of selection range to ensure valid reading order,
#                               also done if readingNameMap is set
# 3.3.1        15.07.2016       function "diffValue" changed, write "-" if no value
# 3.3          12.07.2016       function "diffValue" added
# 3.2.1        12.07.2016       DbRep_Notify prepared, switched from readingsSingleUpdate to readingsBulkUpdate
# 3.2          11.07.2016       handling of db-errors is relocated to blockingcall-subs (checked in version 11785)
# 3.1.1        10.07.2016       state turns to initialized and connected after attr "disabled" is switched from "1" to "0"
# 3.1          09.07.2016       new Attr "timeDiffToNow" and change subs according to that
# 3.0          04.07.2016       no selection if timestamp isn't set and aggregation isn't set with fetchrows, delEntries
# 2.9.9        03.07.2016       english version of commandref completed
# 2.9.8        01.07.2016       changed fetchrows_ParseDone to handle readingvalues with whitespaces correctly
# 2.9.7        30.06.2016       moved {DBLOGDEVICE} to {HELPER}{DBLOGDEVICE}
# 2.9.6        30.06.2016       sql-call changed for countEntries, averageValue, sumValue avoiding
#                               problems if no timestamp is set and aggregation is set
# 2.9.5        30.06.2016       format of readingnames changed again (substitute ":" with "-" in time)
# 2.9.4        30.06.2016       change readingmap to readingNameMap, prove of unsupported characters added
# 2.9.3        27.06.2016       format of readingnames changed avoiding some problems after restart and splitting
# 2.9.2        27.06.2016       use Time::Local added, DbRep_firstconnect added
# 2.9.1        26.06.2016       german commandref added  
# 2.9          25.06.2016       attributes showproctime, timeout added
# 2.8.1        24.06.2016       sql-creation of sumValue, maxValue, fetchrows changed 
#                               main-routine changed
# 2.8          24.06.2016       function averageValue changed to nonblocking function
# 2.7.1        24.06.2016       changed blockingcall routines, changed to unique abort-function
# 2.7          23.06.2016       changed function countEntries to nonblocking
# 2.6.3        22.06.2016       abort-routines changed, dbconnect-routines changed
# 2.6.2        21.06.2016       aggregation week corrected
# 2.6.1        20.06.2016       routine maxval_ParseDone corrected
# 2.6          31.05.2016       maxValue changed to nonblocking function
# 2.5.3        31.05.2016       function delEntries changed
# 2.5.2        31.05.2016       ping check changed, DbRep_Connect changed
# 2.5.1        30.05.2016       sleep in nb-functions deleted
# 2.5          30.05.2016       changed to use own $dbh with DbLog-credentials, function sumValue, fetchrows
# 2.4.2        29.05.2016       function sumValue changed
# 2.4.1        29.05.2016       function fetchrow changed
# 2.4          29.05.2016       changed to nonblocking function for sumValue
# 2.3          28.05.2016       changed sumValue to "prepare" with placeholders
# 2.2          27.05.2016       changed fetchrow and delEntries function to "prepare" with placeholders
#                               added nonblocking function for delEntries
# 2.1          25.05.2016       codechange
# 2.0          24.05.2016       added nonblocking function for fetchrow
# 1.2          21.05.2016       function and attribute for delEntries added
# 1.1          20.05.2016       change result-format of "count", move runtime-counter to sub DbRep_collaggstr
# 1.0          19.05.2016       Initial
#

package main;

use strict;                           
use warnings;
use POSIX qw(strftime);
use Time::HiRes qw(gettimeofday tv_interval);
use Scalar::Util qw(looks_like_number);
eval "use DBI;1" or my $DbRepMMDBI = "DBI";
use DBI::Const::GetInfoType;
use Blocking;
use Color;                           # colorpicker Widget
use Time::Local;
use Encode qw(encode_utf8);
use IO::Compress::Gzip qw(gzip $GzipError);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
# no if $] >= 5.018000, warnings => 'experimental';
no if $] >= 5.017011, warnings => 'experimental::smartmatch';  

sub DbRep_Main($$;$);
sub DbLog_cutCol($$$$$$$);           # DbLog-Funktion nutzen um Daten auf maximale Länge beschneiden

my $DbRepVersion = "7.14.5";

my %dbrep_col = ("DEVICE"  => 64,
                 "TYPE"    => 64,
                 "EVENT"   => 512,
                 "READING" => 64,
                 "VALUE"   => 128,
                 "UNIT"    => 32
                );
                           
###################################################################################
# DbRep_Initialize
###################################################################################
sub DbRep_Initialize($) {
 my ($hash) = @_;
 $hash->{DefFn}        = "DbRep_Define";
 $hash->{UndefFn}      = "DbRep_Undef";
 $hash->{ShutdownFn}   = "DbRep_Shutdown"; 
 $hash->{NotifyFn}     = "DbRep_Notify";
 $hash->{SetFn}        = "DbRep_Set";
 $hash->{GetFn}        = "DbRep_Get";
 $hash->{AttrFn}       = "DbRep_Attr";
 $hash->{FW_deviceOverview} = 1;
 
 $hash->{AttrList} =   "disable:1,0 ".
                       "reading ".                       
                       "allowDeletion:1,0 ".
                       "averageCalcForm:avgArithmeticMean,avgDailyMeanGWS,avgTimeWeightMean ".
                       "device " .
					   "dumpComment ".
                       "dumpCompress:1,0 ".
					   "dumpDirLocal ".
					   "dumpDirRemote ".
					   "dumpMemlimit ".
					   "dumpSpeed ".
					   "dumpFilesKeep:0,1,2,3,4,5,6,7,8,9,10 ".
					   "executeBeforeProc ".
					   "executeAfterProc ".
                       "expimpfile ".
					   "fetchRoute:ascent,descent ".
                       "fetchMarkDuplicates:red,blue,brown,green,orange ".
					   "ftpDebug:1,0 ".
					   "ftpDir ".
                       "ftpDumpFilesKeep:1,2,3,4,5,6,7,8,9,10 ".
					   "ftpPassive:1,0 ".
					   "ftpPwd ".
					   "ftpPort ".
					   "ftpServer ".
					   "ftpTimeout ".
					   "ftpUse:1,0 ".
					   "ftpUser ".
					   "ftpUseSSL:1,0 ".
                       "aggregation:hour,day,week,month,no ".
					   "diffAccept ".
					   "limit ".
					   "optimizeTablesBeforeDump:1,0 ".
                       "readingNameMap ".
                       "readingPreventFromDel ".
                       "role:Client,Agent ".
                       "seqDoubletsVariance ".
                       "showproctime:1,0 ".
                       "showSvrInfo ".
                       "showVariables ".
                       "showStatus ".
                       "showTableInfo ".
                       "sqlCmdHistoryLength:0,5,10,15,20,25,30,35,40,45,50 ".
					   "sqlResultFormat:separated,mline,sline,table,json ".
					   "sqlResultFieldSep:|,:,\/ ".
					   "timeYearPeriod ".
                       "timestamp_begin ".
                       "timestamp_end ".
                       "timeDiffToNow ".
                       "timeOlderThan ".
                       "timeout ".
					   "userExitFn ".
                       $readingFnAttributes;
  
return undef;   
}

###################################################################################
# DbRep_Define
###################################################################################
sub DbRep_Define($@) {
  # define <name> DbRep <DbLog-Device> 
  #       ($hash)  [1]        [2]      
  #
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  
 return "Error: Perl module ".$DbRepMMDBI." is missing. Install it on Debian with: sudo apt-get install libdbi-perl" if($DbRepMMDBI);
 
  my @a = split("[ \t][ \t]*", $def);
  
  if(int(@a) < 2) {
        return "You need to specify more parameters.\n". "Format: define <name> DbRep <DbLog-Device> <Reading> <Timestamp-Begin> <Timestamp-Ende>";
        }
  
  $hash->{LASTCMD}             = " ";
  $hash->{ROLE}                = AttrVal($name, "role", "Client");
  $hash->{HELPER}{DBLOGDEVICE} = $a[2];
  $hash->{VERSION}             = $DbRepVersion;
  $hash->{NOTIFYDEV}           = "global,".$name;                     # nur Events dieser Devices an DbRep_Notify weiterleiten 
  my $dbconn                   = $defs{$a[2]}{dbconn};
  $hash->{DATABASE}            = (split(/;|=/, $dbconn))[1];
  $hash->{UTF8}                = defined($defs{$a[2]}{UTF8})?$defs{$a[2]}{UTF8}:0;
  
  my ($err,$hl)                = DbRep_getCmdFile($name."_sqlCmdList");
  if(!$err) {
      $hash->{HELPER}{SQLHIST} = $hl;
      Log3 ($name, 4, "DbRep $name - history sql commandlist read from file ".$attr{global}{modpath}."/FHEM/FhemUtils/cacheDbRep");
  }
  
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+int(rand(45)), 'DbRep_firstconnect', $hash, 0);
  
  Log3 ($name, 4, "DbRep $name - initialized");
  ReadingsSingleUpdateValue ($hash, 'state', 'initialized', 1);
   
return undef;
}

###################################################################################
# DbRep_Set
###################################################################################
sub DbRep_Set($@) {
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name           = $a[0];
  my $opt            = $a[1];
  my $prop           = $a[2];
  my $dbh            = $hash->{DBH};
  my $dblogdevice    = $hash->{HELPER}{DBLOGDEVICE};
  $hash->{dbloghash} = $defs{$dblogdevice};
  my $dbmodel        = $hash->{dbloghash}{MODEL};
  my $dbname         = $hash->{DATABASE};
  my $sd ="";
  
  my (@bkps,$dir);
  $dir = AttrVal($name, "dumpDirLocal", "./");  # 'dumpDirRemote' (Backup-Verz. auf dem MySQL-Server) muß gemountet sein und in 'dumpDirLocal' eingetragen sein
  $dir = $dir."/" unless($dir =~ m/\/$/);
	
  opendir(DIR,$dir);
  if ($dbmodel =~ /MYSQL/) {
      $dbname = $hash->{DATABASE};
      $sd = $dbname."_history_.*.csv"; 
  } elsif ($dbmodel =~ /SQLITE/) {
      $dbname = $hash->{DATABASE};
      $dbname = (split /[\/]/, $dbname)[-1];
      $dbname = (split /\./, $dbname)[0];
      $sd = $dbname."_.*.sqlitebkp";
  }               
  while (my $file = readdir(DIR)) {
      next unless (-f "$dir/$file");
      next unless ($file =~ /^$sd/);
      push @bkps,$file;
  }
  closedir(DIR);
  my $cj = @bkps?join(",",reverse(sort @bkps)):" ";
  
  # Drop-Down Liste bisherige Befehle in "sqlCmd" erstellen
  my $hl = $hash->{HELPER}{SQLHIST}.",___purge_historylist___" if($hash->{HELPER}{SQLHIST});
  
  my $setlist = "Unknown argument $opt, choose one of ".
                "eraseReadings:noArg ".
                (($hash->{ROLE} ne "Agent")?"sumValue:display,writeToDB ":"").
                (($hash->{ROLE} ne "Agent")?"averageValue:display,writeToDB ":"").
                (($hash->{ROLE} ne "Agent")?"changeValue ":"").
                (($hash->{ROLE} ne "Agent")?"delEntries:noArg ":"").
				(($hash->{ROLE} ne "Agent")?"delSeqDoublets:adviceRemain,adviceDelete,delete ":"").
                "deviceRename ".
				(($hash->{ROLE} ne "Agent")?"readingRename ":"").
                (($hash->{ROLE} ne "Agent")?"exportToFile:noArg ":"").
                (($hash->{ROLE} ne "Agent")?"importFromFile:noArg ":"").
                (($hash->{ROLE} ne "Agent")?"maxValue:display,writeToDB ":"").
                (($hash->{ROLE} ne "Agent")?"minValue:display,writeToDB ":"").
                (($hash->{ROLE} ne "Agent")?"fetchrows:history,current ":"").  
                (($hash->{ROLE} ne "Agent")?"diffValue:display,writeToDB ":"").   
                (($hash->{ROLE} ne "Agent")?"insert ":"").
                (($hash->{ROLE} ne "Agent")?"sqlCmd ":"").
                (($hash->{ROLE} ne "Agent" && $hl)?"sqlCmdHistory:".$hl." ":"").
                (($hash->{ROLE} ne "Agent")?"syncStandby ":"").
				(($hash->{ROLE} ne "Agent")?"tableCurrentFillup:noArg ":"").
				(($hash->{ROLE} ne "Agent")?"tableCurrentPurge:noArg ":"").
				(($hash->{ROLE} ne "Agent" && $dbmodel =~ /MYSQL/ )?"dumpMySQL:clientSide,serverSide ":"").
                (($hash->{ROLE} ne "Agent" && $dbmodel =~ /SQLITE/ )?"dumpSQLite:noArg ":"").
                (($hash->{ROLE} ne "Agent" && $dbmodel =~ /SQLITE/ )?"repairSQLite ":"").
				(($hash->{ROLE} ne "Agent" && $dbmodel =~ /MYSQL/ )?"optimizeTables:noArg ":"").
				(($hash->{ROLE} ne "Agent" && $dbmodel =~ /SQLITE|POSTGRESQL/ )?"vacuum:noArg ":"").
				(($hash->{ROLE} ne "Agent" && $dbmodel =~ /MYSQL/)?"restoreMySQL:".$cj." ":"").
                (($hash->{ROLE} ne "Agent" && $dbmodel =~ /SQLITE/)?"restoreSQLite:".$cj." ":"").
                (($hash->{ROLE} ne "Agent")?"countEntries:history,current ":"");
  
  return if(IsDisabled($name));
    
  if ($opt =~ /eraseReadings/) {
       $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
       # Readings löschen die nicht in der Ausnahmeliste (Attr readingPreventFromDel) stehen
       DbRep_delread($hash);
       return undef;
  }
  
  if ($opt eq "dumpMySQL" && $hash->{ROLE} ne "Agent") {
       $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
	   if ($prop eq "serverSide") {
           Log3 ($name, 3, "DbRep $name - ################################################################");
           Log3 ($name, 3, "DbRep $name - ###             New database serverSide dump                 ###");
           Log3 ($name, 3, "DbRep $name - ################################################################");
	   } else {
           Log3 ($name, 3, "DbRep $name - ################################################################");
           Log3 ($name, 3, "DbRep $name - ###             New database clientSide dump                 ###");
           Log3 ($name, 3, "DbRep $name - ################################################################");
	   }
	   # Befehl vor Procedure ausführen
       DbRep_beforeproc($hash, "dump");
	   DbRep_Main($hash,$opt,$prop);
       return undef;
  }
  
  if ($opt eq "dumpSQLite" && $hash->{ROLE} ne "Agent") {
       $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
       Log3 ($name, 3, "DbRep $name - ################################################################");
       Log3 ($name, 3, "DbRep $name - ###                    New SQLite dump                       ###");
       Log3 ($name, 3, "DbRep $name - ################################################################"); 
	   # Befehl vor Procedure ausführen
       DbRep_beforeproc($hash, "dump");
	   DbRep_Main($hash,$opt,$prop);
       return undef;
  }
  
  if ($opt eq "repairSQLite" && $hash->{ROLE} ne "Agent") {
       $prop = $prop?$prop:36000;
       if($prop) {
           unless($prop =~ /^(\d+)$/) { return " The Value of $opt is not valid. Use only figures 0-9 without decimal places !";};
           # unless ($aVal =~ /^[0-9]+$/) { return " The Value of $aName is not valid. Use only figures 0-9 without decimal places !";}
       }
       $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
       Log3 ($name, 3, "DbRep $name - ################################################################");
       Log3 ($name, 3, "DbRep $name - ###                New SQLite repair attempt                 ###");
       Log3 ($name, 3, "DbRep $name - ################################################################"); 
       Log3 ($name, 3, "DbRep $name - start repair attempt of database ".$hash->{DATABASE}); 
       # closetime Datenbank
       my $dbloghash = $hash->{dbloghash};
       my $dbl = $dbloghash->{NAME};
       CommandSet(undef,"$dbl reopen $prop");
       
	   # Befehl vor Procedure ausführen
       DbRep_beforeproc($hash, "repair");
	   DbRep_Main($hash,$opt);
       return undef;
  }
  
  if ($opt =~ /restoreMySQL|restoreSQLite/ && $hash->{ROLE} ne "Agent") {
       $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";  
       Log3 ($name, 3, "DbRep $name - ################################################################");
       Log3 ($name, 3, "DbRep $name - ###             New database Restore/Recovery                ###");
       Log3 ($name, 3, "DbRep $name - ################################################################");
	   # Befehl vor Procedure ausführen
       DbRep_beforeproc($hash, "restore");
	   DbRep_Main($hash,$opt,$prop);
       return undef;
  }
  
  if ($opt =~ /optimizeTables|vacuum/ && $hash->{ROLE} ne "Agent") {
       $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
       Log3 ($name, 3, "DbRep $name - ################################################################");
       Log3 ($name, 3, "DbRep $name - ###          New optimize table / vacuum execution           ###");
       Log3 ($name, 3, "DbRep $name - ################################################################");
	   # Befehl vor Procedure ausführen
       DbRep_beforeproc($hash, "optimize");	   
	   DbRep_Main($hash,$opt);
       return undef;
  }
  
  if ($opt =~ m/delSeqDoublets/ && $hash->{ROLE} ne "Agent") {
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";  
      if ($prop =~ /delete/ && !AttrVal($hash->{NAME}, "allowDeletion", 0)) {
          return " Set attribute 'allowDeletion' if you want to allow deletion of any database entries. Use it with care !";
      } 
      DbRep_beforeproc($hash, "delSeq");	  
      DbRep_Main($hash,$opt,$prop); 
      return undef;      
  } 
  
  if ($hash->{HELPER}{RUNNING_BACKUP_CLIENT}) {
      $setlist = "Unknown argument $opt, choose one of ".
                (($hash->{ROLE} ne "Agent")?"cancelDump:noArg ":"");
  }
  
  if ($hash->{HELPER}{RUNNING_REPAIR}) {
      $setlist = "Unknown argument $opt, choose one of ".
                (($hash->{ROLE} ne "Agent")?"cancelRepair:noArg ":"");
  }
  
  if ($opt eq "cancelDump" && $hash->{ROLE} ne "Agent") {
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
      BlockingKill($hash->{HELPER}{RUNNING_BACKUP_CLIENT});
	  Log3 ($name, 3, "DbRep $name -> running Dump has been canceled");
	  ReadingsSingleUpdateValue ($hash, "state", "Dump canceled", 1);
      return undef;
  } 
  
  if ($opt eq "cancelRepair" && $hash->{ROLE} ne "Agent") {
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
      BlockingKill($hash->{HELPER}{RUNNING_REPAIR});
	  Log3 ($name, 3, "DbRep $name -> running Repair has been canceled");
	  ReadingsSingleUpdateValue ($hash, "state", "Repair canceled", 1);
      return undef;
  } 
  
  #######################################################################################################
  ##        keine Aktionen außer die über diesem Eintrag solange Reopen xxxx im DbLog-Device läuft
  #######################################################################################################
  if ($hash->{dbloghash}{HELPER}{REOPEN_RUNS} && $opt !~ /\?/) {
      my $ro = (split(" ",FmtDateTime(gettimeofday()+$hash->{dbloghash}{HELPER}{REOPEN_RUNS})))[1];
      Log3 ($name, 3, "DbRep $name - connection $dblogdevice to db $dbname is closed until $ro - $opt postponed");
	  ReadingsSingleUpdateValue ($hash, "state", "connection $dblogdevice to $dbname is closed until $ro - $opt postponed", 1);
	  return;
  }
  #######################################################################################################
  
  if ($opt =~ /countEntries/ && $hash->{ROLE} ne "Agent") {
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
      my $table = $prop?$prop:"history";
      DbRep_Main($hash,$opt,$table);
      
  } elsif ($opt =~ /fetchrows/ && $hash->{ROLE} ne "Agent") {
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
      my $table = $prop?$prop:"history";
      DbRep_Main($hash,$opt,$table);
      
  } elsif ($opt =~ m/(max|min|sum|average|diff)Value/ && $hash->{ROLE} ne "Agent") {
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
      if (!AttrVal($hash->{NAME}, "reading", "")) {
          return " The attribute reading to analyze is not set !";
      }
      if ($prop && $prop =~ /writeToDB/) {
          if (!AttrVal($hash->{NAME}, "device", "") || AttrVal($hash->{NAME}, "device", "") =~ /[%.*:=,]/ || AttrVal($hash->{NAME}, "reading", "") =~ /[,\s]/) {
              return "<html>If you want write results back to database, attributes \"device\" and \"reading\" must be set.<br>
                      In that case \"device\" mustn't be a <a href='https://fhem.de/commandref.html#devspec\'>devspec</a> and mustn't contain SQL-Wildcard (%).<br>
                      The \"reading\" to evaluate has to be a single reading and no list.</html>";
          }
      }
      DbRep_Main($hash,$opt,$prop);
      
  } elsif ($opt =~ m/delEntries|tableCurrentPurge/ && $hash->{ROLE} ne "Agent") {
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
      if (!AttrVal($hash->{NAME}, "allowDeletion", undef)) {
          return " Set attribute 'allowDeletion' if you want to allow deletion of any database entries. Use it with care !";
      }        
      DbRep_Main($hash,$opt);
      
  } elsif ($opt =~ m/tableCurrentFillup/ && $hash->{ROLE} ne "Agent") {   
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";  
      DbRep_Main($hash,$opt);
      
  } elsif ($opt eq "deviceRename") {
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
      my ($olddev, $newdev) = split(",",$prop);
      if (!$olddev || !$newdev) {return "Both entries \"old device name\", \"new device name\" are needed. Use \"set $name deviceRename olddevname,newdevname\" ";}
      $hash->{HELPER}{OLDDEV}  = $olddev;
      $hash->{HELPER}{NEWDEV}  = $newdev;
	  $hash->{HELPER}{RENMODE} = "devren";
      DbRep_Main($hash,$opt);
      
  } elsif ($opt eq "readingRename") {
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
      my ($oldread, $newread) = split(",",$prop);
      if (!$oldread || !$newread) {return "Both entries \"old reading name\", \"new reading name\" are needed. Use \"set $name readingRename oldreadingname,newreadingname\" ";}
      $hash->{HELPER}{OLDREAD} = $oldread;
      $hash->{HELPER}{NEWREAD} = $newread;
	  $hash->{HELPER}{RENMODE} = "readren";
      DbRep_Main($hash,$opt);
      
  } elsif ($opt eq "insert" && $hash->{ROLE} ne "Agent") {
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";  
      if ($prop) {
          if (!AttrVal($hash->{NAME}, "device", "") || !AttrVal($hash->{NAME}, "reading", "") ) {
              return "One or both of attributes \"device\", \"reading\" are not set. It's mandatory to set both to complete dataset for manual insert !";
          }
          
          # Attribute device & reading dürfen kein SQL-Wildcard % enthalten
          return "One or both of attributes \"device\", \"reading\" containing SQL wildcard \"%\". Wildcards are not allowed in function manual insert !" 
                 if(AttrVal($hash->{NAME},"device","") =~ m/%/ || AttrVal($hash->{NAME},"reading","") =~ m/%/ );
          
          my ($i_date, $i_time, $i_value, $i_unit) = split(",",$prop);
                    
          if (!$i_date || !$i_time || !$i_value) {return "At least data for \"Date\", \"Time\" and \"Value\" is needed to insert. \"Unit\" is optional. Inputformat is 'YYYY-MM-DD,HH:MM:SS,<Value(32)>,<Unit(32)>' ";}

          unless ($i_date =~ /(\d{4})-(\d{2})-(\d{2})/) {return "Input for date is not valid. Use format YYYY-MM-DD !";}
          unless ($i_time =~ /(\d{2}):(\d{2}):(\d{2})/) {return "Input for time is not valid. Use format HH:MM:SS !";}
          my $i_timestamp = $i_date." ".$i_time;
          my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($i_timestamp =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
           
          eval { my $ts = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };
           
          if ($@) {
              my @l = split (/at/, $@);
              return " Timestamp is out of range - $l[0]";         
          }          
          
          my $i_device  = AttrVal($hash->{NAME}, "device", "");
          my $i_reading = AttrVal($hash->{NAME}, "reading", "");
          
          # Daten auf maximale Länge (entsprechend der Feldlänge in DbLog DB create-scripts) beschneiden wenn nicht SQLite
          if ($dbmodel ne 'SQLITE') {
              $i_device   = substr($i_device,0, $dbrep_col{DEVICE});
              $i_reading  = substr($i_reading,0, $dbrep_col{READING});
              $i_value    = substr($i_value,0, $dbrep_col{VALUE});
              $i_unit     = substr($i_unit,0, $dbrep_col{UNIT}) if($i_unit);
          }
          
          $hash->{HELPER}{I_TIMESTAMP} = $i_timestamp;
          $hash->{HELPER}{I_DEVICE}    = $i_device;
          $hash->{HELPER}{I_READING}   = $i_reading;
          $hash->{HELPER}{I_VALUE}     = $i_value;
          $hash->{HELPER}{I_UNIT}      = $i_unit;
          $hash->{HELPER}{I_TYPE}      = my $i_type = "manual";
          $hash->{HELPER}{I_EVENT}     = my $i_event = "manual";          
          
      } else {
          return "Data to insert to table 'history' are needed like this pattern: 'Date,Time,Value,[Unit]'. \"Unit\" is optional. Spaces are not allowed !";
      }
      DbRep_Main($hash,$opt);
      
  } elsif ($opt eq "exportToFile" && $hash->{ROLE} ne "Agent") {
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
      if (!AttrVal($hash->{NAME}, "expimpfile", "")) {
          return "The attribute \"expimpfile\" (path and filename) has to be set for export to file !";
      }
      DbRep_Main($hash,$opt);
      
  } elsif ($opt eq "importFromFile" && $hash->{ROLE} ne "Agent") {
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
      if (!AttrVal($hash->{NAME}, "expimpfile", "")) {
          return "The attribute \"expimpfile\" (path and filename) has to be set for import from file !";
      }
      DbRep_Main($hash,$opt);
      
  } elsif ($opt =~ /sqlCmd|sqlCmdHistory/) {
      return "\"set $opt\" needs at least an argument" if ( @a < 3 );
      # remove arg 0, 1 to get SQL command
      my $sqlcmd;
      if($opt eq "sqlCmd") {
          shift @a;
          shift @a;
          $sqlcmd = join(" ", @a);
      }
      if($opt eq "sqlCmdHistory") {
          $prop =~ tr/ A-Za-z0-9!"#$%&'()*+,-.\/:;<=>?@[\\]^_`{|}~äöüÄÖÜß€/ /cs;
          $prop =~ s/<c>/,/g;          
          $sqlcmd = $prop;
          if($sqlcmd eq "___purge_historylist___") {
              delete($hash->{HELPER}{SQLHIST});
              DbRep_setCmdFile($name."_sqlCmdList","",$hash);         # Löschen der sql History Liste im DbRep-Keyfile
              return "SQL command historylist of $name deleted.";
          }
      }
      $hash->{LASTCMD} = $sqlcmd?"$opt $sqlcmd":"$opt";
	  if ($sqlcmd =~ m/^\s*delete/is && !AttrVal($hash->{NAME}, "allowDeletion", undef)) {
          return " Attribute 'allowDeletion = 1' is needed for command '$sqlcmd'. Use it with care !";
      }  
      DbRep_Main($hash,$opt,$sqlcmd);
	 
  } elsif ($opt =~ /changeValue/) {
      shift @a;
      shift @a;
      $prop = join(" ", @a);
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
      unless($prop =~ m/^\s*(".*",".*")\s*$/) {return "Both entries \"old string\", \"new string\" are needed. Use \"set $name changeValue \"old string\",\"new string\" (use quotes)";}
      my $complex = 0;
      my ($oldval,$newval) = ($prop =~ /^\s*"(.*?)","(.*?)"\s*$/);

      if($newval =~ m/[{}]/) {
          if($newval =~ m/^\s*(\{.*\})\s*$/s) {
              $newval  = $1;
              $complex = 1;
              my %specials = (
                 "%VALUE" => $name,
                 "%UNIT" => $name,
              );
              $newval = EvalSpecials($newval, %specials);
          } else {
              return "The expression of \"new string\" has to be included in \"{ }\" ";
          }
      }
      $hash->{HELPER}{COMPLEX} = $complex;
      $hash->{HELPER}{OLDVAL}  = $oldval;
      $hash->{HELPER}{NEWVAL}  = $newval;
      $hash->{HELPER}{RENMODE} = "changeval";
      DbRep_beforeproc($hash, "changeval");
      DbRep_Main($hash,$opt);
	 
  }  elsif ($opt =~ m/syncStandby/ && $hash->{ROLE} ne "Agent") {   
      unless($prop) {return "A DbLog-device (standby) is needed to sync. Use \"set $name syncStandby <DbLog-standby name>\" ";}
      if(!exists($defs{$prop}) || $defs{$prop}->{TYPE} ne "DbLog") {
          return "The device \"$prop\" doesn't exist or is not a DbLog-device. ";
      }
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";  
      DbRep_Main($hash,$opt,$prop);
      
  } else {
      return "$setlist";
  }  
  
return undef;
}

###################################################################################
# DbRep_Get
###################################################################################
sub DbRep_Get($@) {
  my ($hash, @a) = @_;
  return "\"get X\" needs at least an argument" if ( @a < 2 );
  my $name    = $a[0];
  my $opt     = $a[1];
  my $prop    = $a[2];
  my $dbh     = $hash->{DBH};
  my $dblogdevice    = $hash->{HELPER}{DBLOGDEVICE};
  $hash->{dbloghash} = $defs{$dblogdevice};
  my $dbmodel = $hash->{dbloghash}{MODEL};
  my $dbname  = $hash->{DATABASE};
  my $to      = AttrVal($name, "timeout", "86400");
  
  my $getlist = "Unknown argument $opt, choose one of ".
                "svrinfo:noArg ".
				"blockinginfo:noArg ".
                "minTimestamp:noArg ".
                (($dbmodel eq "MYSQL")?"dbstatus:noArg ":"").
                (($dbmodel eq "MYSQL")?"tableinfo:noArg ":"").
				(($dbmodel eq "MYSQL")?"procinfo:noArg ":"").
                (($dbmodel eq "MYSQL")?"dbvars:noArg ":"") 
                ;
  
  return if(IsDisabled($name));
  
  if ($hash->{dbloghash}{HELPER}{REOPEN_RUNS} && $opt !~ /\?|procinfo|blockinginfo/) {
      my $ro = (split(" ",FmtDateTime(gettimeofday()+$hash->{dbloghash}{HELPER}{REOPEN_RUNS})))[1];
      Log3 ($name, 3, "DbRep $name - connection $dblogdevice to db $dbname is closed until $ro - $opt postponed");
	  ReadingsSingleUpdateValue ($hash, "state", "connection $dblogdevice to $dbname is closed until $ro - $opt postponed", 1);
	  return;
  }
  
  if ($opt =~ /dbvars|dbstatus|tableinfo|procinfo/) {
      return "Dump is running - try again later !" if($hash->{HELPER}{RUNNING_BACKUP_CLIENT});
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
      return "The operation \"$opt\" isn't available with database type $dbmodel" if ($dbmodel ne 'MYSQL');
	  ReadingsSingleUpdateValue ($hash, "state", "running", 1);
      DbRep_delread($hash);  # Readings löschen die nicht in der Ausnahmeliste (Attr readingPreventFromDel) stehen
      $hash->{HELPER}{RUNNING_PID} = BlockingCall("dbmeta_DoParse", "$name|$opt", "dbmeta_ParseDone", $to, "DbRep_ParseAborted", $hash);    
  
  } elsif ($opt eq "svrinfo") {
      return "Dump is running - try again later !" if($hash->{HELPER}{RUNNING_BACKUP_CLIENT});
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
      DbRep_delread($hash); 
      ReadingsSingleUpdateValue ($hash, "state", "running", 1);
      $hash->{HELPER}{RUNNING_PID} = BlockingCall("dbmeta_DoParse", "$name|$opt", "dbmeta_ParseDone", $to, "DbRep_ParseAborted", $hash);      
  
  } elsif ($opt eq "blockinginfo") {
      return "Dump is running - try again later !" if($hash->{HELPER}{RUNNING_BACKUP_CLIENT});
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
      DbRep_delread($hash); 
      ReadingsSingleUpdateValue ($hash, "state", "running", 1);   
	  DbRep_getblockinginfo($hash);	  
  
  } elsif ($opt eq "minTimestamp") {
      return "Dump is running - try again later !" if($hash->{HELPER}{RUNNING_BACKUP_CLIENT});
      $hash->{LASTCMD} = $prop?"$opt $prop":"$opt";
      DbRep_delread($hash); 
      ReadingsSingleUpdateValue ($hash, "state", "running", 1);   
	  DbRep_firstconnect($hash);	  
  
  } else {
      return "$getlist";
  } 
  
return undef;
}

###################################################################################
# DbRep_Attr
###################################################################################
sub DbRep_Attr($$$$) {
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};
  $hash->{dbloghash} = $defs{$hash->{HELPER}{DBLOGDEVICE}};
  my $dbmodel = $hash->{dbloghash}{MODEL};
  my $do;
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    
    # nicht erlaubte / nicht setzbare Attribute wenn role = Agent
    my @agentnoattr = qw(aggregation
                         allowDeletion
						 dumpDirLocal
                         reading
                         readingNameMap
                         readingPreventFromDel
                         device
						 diffAccept
						 executeBeforeProc
						 executeAfterProc
                         expimpfile
						 ftpUse
						 ftpUser
						 ftpUseSSL
						 ftpDebug
						 ftpDir
						 ftpPassive
						 ftpPort
						 ftpPwd
						 ftpServer
						 ftpTimeout
						 dumpMemlimit
						 dumpComment
						 dumpSpeed
						 optimizeTablesBeforeDump
                         seqDoubletsVariance
                         sqlCmdHistoryLength
						 timeYearPeriod
                         timestamp_begin
                         timestamp_end
                         timeDiffToNow
                         timeOlderThan
						 sqlResultFormat
                         );
    
    if ($aName eq "disable") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        my $val = ($do == 1 ?  "disabled" : "initialized");
		ReadingsSingleUpdateValue ($hash, "state", $val, 1);
        if ($do == 0) {
            RemoveInternalTimer($hash);
            InternalTimer(time+5, 'DbRep_firstconnect', $hash, 0);
        } else {
            my $dbh = $hash->{DBH};
            $dbh->disconnect() if($dbh);
        }
    }
    
    if ($cmd eq "set" && $hash->{ROLE} eq "Agent") {
        foreach (@agentnoattr) {
           return ("Attribute $aName is not usable due to role of $name is \"$hash->{ROLE}\"  ") if ($_ eq $aName);
        }
    }
    
    if ($aName eq "readingPreventFromDel") {
        if($cmd eq "set") {
            if($aVal =~ / /) {return "Usage of $aName is wrong. Use a comma separated list of readings which are should prevent from deletion when a new selection starts.";}
            $hash->{HELPER}{RDPFDEL} = $aVal;
        } else {
            delete $hash->{HELPER}{RDPFDEL} if($hash->{HELPER}{RDPFDEL});
        }
    }
    
    if ($aName eq "sqlCmdHistoryLength") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        if ($do == 0) {
            delete($hash->{HELPER}{SQLHIST});
            DbRep_setCmdFile($name."_sqlCmdList","",$hash);         # Löschen der sql History Liste im DbRep-Keyfile
        }
    }
	
	if ($aName eq "userExitFn") {
        if($cmd eq "set") {
            if(!$aVal) {return "Usage of $aName is wrong. The function has to be specified as \"<UserExitFn> [reading:value]\" ";}
			my @a = split(/ /,$aVal,2);
            $hash->{HELPER}{USEREXITFN} = $a[0];
			$hash->{HELPER}{UEFN_REGEXP} = $a[1] if($a[1]);
        } else {
            delete $hash->{HELPER}{USEREXITFN} if($hash->{HELPER}{USEREXITFN});
			delete $hash->{HELPER}{UEFN_REGEXP} if($hash->{HELPER}{UEFN_REGEXP});
        }
    }
    
    if ($aName eq "role") {
        if($cmd eq "set") {
            if ($aVal eq "Agent") {
                # check ob bereits ein Agent für die angeschlossene Datenbank existiert -> DbRep-Device kann dann keine Agent-Rolle einnehmen
                foreach(devspec2array("TYPE=DbRep")) {
                    my $devname = $_;
                    next if($devname eq $name);
                    my $devrole = $defs{$_}{ROLE};
                    my $devdb = $defs{$_}{DATABASE};
                    if ($devrole eq "Agent" && $devdb eq $hash->{DATABASE}) { return "There is already an Agent device: $devname defined for database $hash->{DATABASE} !"; }
                }
                # nicht erlaubte Attribute löschen falls gesetzt
                foreach (@agentnoattr) {
                    delete($attr{$name}{$_});
                }
                
                $attr{$name}{icon} = "security";
            }
            $do = $aVal;
        } else {
            $do = "Client";
        }
        $hash->{ROLE} = $do;
        delete($attr{$name}{icon}) if($do eq "Client");
    }
                         
    if ($cmd eq "set") {
		if ($aName =~ /seqDoubletsVariance/) {
            unless (looks_like_number($aVal)) { return " The Value of $aName is not valid. Only figures are allowed !";}
        }
		if ($aName eq "timeYearPeriod") {
		    # 06-01 02-28
            unless ($aVal =~ /^(\d{2})-(\d{2}) (\d{2})-(\d{2})$/ )
			    { return "The Value of \"$aName\" isn't valid. Set the account period as \"MM-DD MM-DD\".";}
            my ($mm1, $dd1, $mm2, $dd2) = ($aVal =~ /^(\d{2})-(\d{2}) (\d{2})-(\d{2})$/);
			my (undef,undef,undef,$mday,$mon,$year1,undef,undef,undef) = localtime(time);     # Istzeit Ableitung
			my $year2 = $year1;
            # a  b   c  d
            # 06-01 02-28 , wenn c < a && $mon < a -> Jahr(a)-1, sonst Jahr(c)+1
		    my $c = ($mon+1).$mday;
	        my $e = $mm2.$dd2;
            if ($mm2 <= $mm1 && $c <= $e) {
			    $year1--;
			} else {
			    $year2++;
			}
            eval { my $t1 = timelocal(00, 00, 00, $dd1, $mm1-1, $year1-1900); 
			       my $t2 = timelocal(00, 00, 00, $dd2, $mm2-1, $year2-1900); };
            if ($@) {
                my @l = split (/at/, $@);
                return " The Value of $aName is out of range - $l[0]";
            }
            delete($attr{$name}{timestamp_begin}) if ($attr{$name}{timestamp_begin});
            delete($attr{$name}{timestamp_end}) if ($attr{$name}{timestamp_end});
            delete($attr{$name}{timeDiffToNow}) if ($attr{$name}{timeDiffToNow});
            delete($attr{$name}{timeOlderThan}) if ($attr{$name}{timeOlderThan});
            return undef;
        }
        if ($aName eq "timestamp_begin" || $aName eq "timestamp_end") {
            my ($a,$b,$c) = split('_',$aVal);
            if ($a =~ /^current$|^previous$/ && $b =~ /^hour$|^day$|^week$|^month$|^year$/ && $c =~ /^begin$|^end$/) {
                delete($attr{$name}{timeDiffToNow}) if ($attr{$name}{timeDiffToNow});
                delete($attr{$name}{timeOlderThan}) if ($attr{$name}{timeOlderThan});
                return undef;
            }
            $aVal = DbRep_formatpicker($aVal);		
            unless ($aVal =~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/) 
                {return " The Value of $aName is not valid. Use format YYYY-MM-DD HH:MM:SS or one of \"current_[year|month|day|hour]_begin\",\"current_[year|month|day|hour]_end\", \"previous_[year|month|day|hour]_begin\", \"previous_[year|month|day|hour]_end\" !";}
           
            my ($yyyy, $mm, $dd, $hh, $min, $sec) = ($aVal =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
           
            eval { my $epoch_seconds_begin = timelocal($sec, $min, $hh, $dd, $mm-1, $yyyy-1900); };
           
            if ($@) {
                my @l = split (/at/, $@);
                return " The Value of $aName is out of range - $l[0]";
            }
            delete($attr{$name}{timeDiffToNow}) if ($attr{$name}{timeDiffToNow});
            delete($attr{$name}{timeOlderThan}) if ($attr{$name}{timeOlderThan});
        }
		if ($aName =~ /ftpTimeout|timeout|diffAccept/) {
            unless ($aVal =~ /^[0-9]+$/) { return " The Value of $aName is not valid. Use only figures 0-9 without decimal places !";}
        } 
		if ($aName eq "readingNameMap") {
            unless ($aVal =~ m/^[A-Za-z\d_\.-]+$/) { return " Unsupported character in $aName found. Use only A-Z a-z _ . -";}
        }
		if ($aName eq "timeDiffToNow") {
            unless ($aVal =~ /^[0-9]+$/ || $aVal =~ /^\s*[dhms]:([\d]+)\s*/ && $aVal !~ /.*,.*/ )
			    { return "The Value of \"$aName\" isn't valid. Set simple seconds like \"86400\" or use form like \"d:10 h:6 m:12 s:20\". Refer to commandref !";}
            delete($attr{$name}{timestamp_begin}) if ($attr{$name}{timestamp_begin});
            delete($attr{$name}{timestamp_end}) if ($attr{$name}{timestamp_end});
            delete($attr{$name}{timeOlderThan}) if ($attr{$name}{timeOlderThan});
            delete($attr{$name}{timeYearPeriod}) if ($attr{$name}{timeYearPeriod});
        } 
		if ($aName eq "timeOlderThan") {
            unless ($aVal =~ /^[0-9]+$/ || $aVal =~ /^\s*[dhms]:([\d]+)\s*/ && $aVal !~ /.*,.*/ )
			    { return "The Value of \"$aName\" isn't valid. Set simple seconds like \"86400\" or use form like \"d:10 h:6 m:12 s:20\". Refer to commandref !";}
            delete($attr{$name}{timestamp_begin}) if ($attr{$name}{timestamp_begin});
            delete($attr{$name}{timestamp_end}) if ($attr{$name}{timestamp_end});
            delete($attr{$name}{timeDiffToNow}) if ($attr{$name}{timeDiffToNow});
            delete($attr{$name}{timeYearPeriod}) if ($attr{$name}{timeYearPeriod});
        }
		if ($aName eq "dumpMemlimit" || $aName eq "dumpSpeed") {
            unless ($aVal =~ /^[0-9]+$/) { return "The Value of $aName is not valid. Use only figures 0-9 without decimal places.";}
			my $dml = AttrVal($name, "dumpMemlimit", 100000);
			my $ds  = AttrVal($name, "dumpSpeed", 10000);
			if($aName eq "dumpMemlimit") {
			    unless($aVal >= (10 * $ds)) {return "The Value of $aName has to be at least '10 x dumpSpeed' ! ";}
			}
			if($aName eq "dumpSpeed") {
			    unless($aVal <= ($dml / 10)) {return "The Value of $aName mustn't be greater than 'dumpMemlimit / 10' ! ";}
			}
        }
		if ($aName eq "ftpUse") {
            delete($attr{$name}{ftpUseSSL});
        }
		if ($aName eq "ftpUseSSL") {
            delete($attr{$name}{ftpUse});
        }
		if ($aName eq "reading" || $aName eq "device") {
            if ($dbmodel && $dbmodel ne 'SQLITE') {
			    my $attrname = uc($aName);
                if ($dbmodel eq 'POSTGRESQL' && $aVal !~ m/,/) {
                    return "Length of \"$aName\" is too big. Maximum length for database type $dbmodel is $dbrep_col{$attrname}" if(length($aVal) > $dbrep_col{$attrname});
                } elsif ($dbmodel eq 'MYSQL' && $aVal !~ m/,/) {
                    return "Length of \"$aName\" is too big. Maximum length for database type $dbmodel is $dbrep_col{$attrname}" if(length($aVal) > $dbrep_col{$attrname});
                }
            }
		}

    }  
return undef;
}

###################################################################################
# DbRep_Notify Eventverarbeitung
###################################################################################
sub DbRep_Notify($$) {
 # Es werden nur die Events von Geräten verarbeitet die im Hash $hash->{NOTIFYDEV} gelistet sind (wenn definiert).
 # Dadurch kann die Menge der Events verringert werden. In sub DbRep_Define angeben.
 # Beispiele:
 # $hash->{NOTIFYDEV} = "global";
 # $hash->{NOTIFYDEV} = "global,Definition_A,Definition_B";
 
 my ($own_hash, $dev_hash) = @_;
 my $myName  = $own_hash->{NAME};   # Name des eigenen Devices
 my $devName = $dev_hash->{NAME};   # Device welches Events erzeugt hat
 
 return if(IsDisabled($myName));    # Return if the module is disabled
 
 my $events = deviceEvents($dev_hash,0);  
 return if(!$events);

 foreach my $event (@{$events}) {
     $event = "" if(!defined($event));
     my @evl = split("[ \t][ \t]*", $event);
     
#    if ($devName = $myName && $evl[0] =~ /done/) {
#      InternalTimer(time+1, "browser_refresh", $own_hash, 0);
#    }
     
     if ($own_hash->{ROLE} eq "Agent") {
	     # wenn Rolle "Agent" Verbeitung von RENAMED Events
         next if ($event !~ /RENAMED/);
         
         my $strucChanged;
         # altes in neues device in der DEF des angeschlossenen DbLog-device ändern (neues device loggen)
         my $dblog_name = $own_hash->{dbloghash}{NAME};            # Name des an den DbRep-Agenten angeschlossenen DbLog-Dev
         my $dblog_hash = $defs{$dblog_name};
         
         if ( $dblog_hash->{DEF} =~ m/( |\(|\|)$evl[1]( |\)|\||:)/ ) {
             $dblog_hash->{DEF} =~ s/$evl[1]/$evl[2]/;
             $dblog_hash->{REGEXP} =~ s/$evl[1]/$evl[2]/;
             # Definitionsänderung wurde vorgenommen
             $strucChanged = 1;
             Log3 ($myName, 3, "DbRep Agent $myName - $dblog_name substituted in DEF, old: \"$evl[1]\", new: \"$evl[2]\" "); 
         }  
         
         # DEVICE innerhalb angeschlossener Datenbank umbenennen
         Log3 ($myName, 4, "DbRep Agent $myName - Evt RENAMED rec - old device: $evl[1], new device: $evl[2] -> start deviceRename in DB: $own_hash->{DATABASE} ");
         $own_hash->{HELPER}{OLDDEV}  = $evl[1];
         $own_hash->{HELPER}{NEWDEV}  = $evl[2];
		 $own_hash->{HELPER}{RENMODE} = "devren";
         DbRep_Main($own_hash,"deviceRename");
         
         # die Attribute "device" in allen DbRep-Devices mit der Datenbank = DB des Agenten von alten Device in neues Device ändern
         foreach(devspec2array("TYPE=DbRep")) {
             my $repname = $_;
             next if($_ eq $myName);
             my $repattrdevice = $attr{$_}{device};
             next if(!$repattrdevice);
             my $repdb         = $defs{$_}{DATABASE};
             if ($repattrdevice eq $evl[1] && $repdb eq $own_hash->{DATABASE}) { 
                 $attr{$_}{device} = $evl[2];
                 # Definitionsänderung wurde vorgenommen
                 $strucChanged = 1;
                 Log3 ($myName, 3, "DbRep Agent $myName - $_ attr device changed, old: \"$evl[1]\", new: \"$evl[2]\" "); 
             }
         }
     # if ($strucChanged) {CommandSave("","")};
     } 
 }
return;
}

###################################################################################
# DbRep_Undef
###################################################################################
sub DbRep_Undef($$) {
 my ($hash, $arg) = @_;
 
 RemoveInternalTimer($hash);
 
 my $dbh = $hash->{DBH}; 
 $dbh->disconnect() if(defined($dbh));
 
 BlockingKill($hash->{HELPER}{RUNNING_PID}) if (exists($hash->{HELPER}{RUNNING_PID}));
 BlockingKill($hash->{HELPER}{RUNNING_BACKUP_CLIENT}) if (exists($hash->{HELPER}{RUNNING_BACKUP_CLIENT}));
 BlockingKill($hash->{HELPER}{RUNNING_BCKPREST_SERVER}) if (exists($hash->{HELPER}{RUNNING_BCKPREST_SERVER})); 
 BlockingKill($hash->{HELPER}{RUNNING_OPTIMIZE}) if (exists($hash->{HELPER}{RUNNING_OPTIMIZE}));

 DbRep_delread($hash,1);
    
return undef;
}

###################################################################################
# DbRep_Shutdown
###################################################################################
sub DbRep_Shutdown($) {  
  my ($hash) = @_;
 
  my $dbh = $hash->{DBH}; 
  $dbh->disconnect() if(defined($dbh)); 
  DbRep_delread($hash,1);
  RemoveInternalTimer($hash);
  
return undef; 
}

###################################################################################
#        First Init DB Connect 
#        Verbindung zur DB aufbauen und den Timestamp des ältesten 
#        Datensatzes ermitteln
###################################################################################
sub DbRep_firstconnect($) {
  my ($hash) = @_;
  my $name       = $hash->{NAME};
  my $to         = "120";
  my $dbloghash  = $hash->{dbloghash};
  my $dbconn     = $dbloghash->{dbconn};
  my $dbuser     = $dbloghash->{dbuser};

  RemoveInternalTimer($hash, "DbRep_firstconnect");
  return if(IsDisabled($name));
  if ($init_done == 1) {
      Log3 ($name, 3, "DbRep $name - Connectiontest to database $dbconn with user $dbuser") if($hash->{LASTCMD} ne "minTimestamp");
      $hash->{HELPER}{RUNNING_PID} = BlockingCall("DbRep_getMinTs", "$name", "DbRep_getMinTsDone", $to, "DbRep_getMinTsAborted", $hash);        
      $hash->{HELPER}{RUNNING_PID}{loglevel} = 5 if($hash->{HELPER}{RUNNING_PID});  # Forum #77057
  } else {
      InternalTimer(time+1, "DbRep_firstconnect", $hash, 0);
  }

return;
}

####################################################################################################
#     den ältesten Datensatz (Timestamp) in der DB bestimmen 
####################################################################################################
sub DbRep_getMinTs($) {
 my ($name)     = @_;
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $mintsdef   = "1970-01-01 01:00:00";
 my ($dbh,$sql,$err,$mints);

 # Background-Startzeit
 my $bst = [gettimeofday];
 
 eval { $dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 }); };
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|''|$err";
 }
 
 # SQL-Startzeit
 my $st = [gettimeofday];
 
 eval { $mints = $dbh->selectrow_array("SELECT min(TIMESTAMP) FROM history;"); }; 
 
 $dbh->disconnect;
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 $mints = $mints?encode_base64($mints,""):encode_base64($mintsdef,"");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$mints|$rt|0";
}

####################################################################################################
# Auswertungsroutine den ältesten Datensatz (Timestamp) in der DB bestimmen 
####################################################################################################
sub DbRep_getMinTsDone($) {
  my ($string) = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $name       = $hash->{NAME};
  my $mints      = decode_base64($a[1]);
  my $bt         = $a[2];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[3]?decode_base64($a[3]):undef;
  my $dblogdevice    = $hash->{HELPER}{DBLOGDEVICE};
  $hash->{dbloghash} = $defs{$dblogdevice};
  my $dbconn         = $hash->{dbloghash}{dbconn};
  
   if ($err) {
      readingsBeginUpdate($hash);
      ReadingsBulkUpdateValue ($hash, "errortext", $err);
      ReadingsBulkUpdateValue ($hash, "state", "disconnected");
      readingsEndUpdate($hash, 1);
      delete($hash->{HELPER}{RUNNING_PID});
      Log3 ($name, 2, "DbRep $name - DB connect failed. Make sure credentials of database $hash->{DATABASE} are valid and database is reachable.");
      return;
  }
  
  $hash->{HELPER}{MINTS} = $mints;
  my $state = ($hash->{LASTCMD} eq "minTimestamp")?"done":"connected";

  readingsBeginUpdate($hash);
  ReadingsBulkUpdateValue ($hash, "timestamp_oldest_dataset", $mints) if($hash->{LASTCMD} eq "minTimestamp");
  ReadingsBulkUpdateTimeState($hash,$brt,$rt,$state);
  readingsEndUpdate($hash, 1);
  
  Log3 ($name, 4, "DbRep $name - Connectiontest to db $dbconn successful") if($hash->{LASTCMD} ne "minTimestamp");
  
  $hash->{HELPER}{MINTS} = $mints;
  
  delete($hash->{HELPER}{RUNNING_PID});
  
return;
}

####################################################################################################
#             Abbruchroutine den ältesten Datensatz (Timestamp) in der DB bestimmen 
####################################################################################################
sub DbRep_getMinTsAborted(@) {
  my ($hash,$cause) = @_;
  my $name = $hash->{NAME};
  
  $cause = $cause?$cause:"Timeout: process terminated";
  Log3 ($name, 1, "DbRep $name -> BlockingCall $hash->{HELPER}{RUNNING_PID}{fn} pid:$hash->{HELPER}{RUNNING_PID}{pid} $cause");
  
  readingsBeginUpdate($hash);
  ReadingsBulkUpdateValue ($hash, "errortext", $cause);
  ReadingsBulkUpdateValue ($hash, "state", "disconnected");
  readingsEndUpdate($hash, 1);
  
  delete($hash->{HELPER}{RUNNING_PID});
return;
}

################################################################################################################
#                                              Hauptroutine
################################################################################################################
sub DbRep_Main($$;$) {
 my ($hash,$opt,$prop) = @_;
 my $name        = $hash->{NAME}; 
 my $to          = AttrVal($name, "timeout", "86400");
 my $reading     = AttrVal($name, "reading", "%");
 my $device      = AttrVal($name, "device", "%");
 my $dbloghash   = $hash->{dbloghash};
 my $dbmodel     = $dbloghash->{MODEL};
 
 # Entkommentieren für Testroutine im Vordergrund
 # testexit($hash);
 
 return if( ($hash->{HELPER}{RUNNING_BACKUP_CLIENT}   || 
             $hash->{HELPER}{RUNNING_BCKPREST_SERVER} ||
             $hash->{HELPER}{RUNNING_REPAIR}          ||
             $hash->{HELPER}{RUNNING_OPTIMIZE})       && 
             $opt !~ /dumpMySQL|restoreMySQL|dumpSQLite|restoreSQLite|optimizeTables|vacuum|repairSQLite/ );
 
 # Readings löschen die nicht in der Ausnahmeliste (Attr readingPreventFromDel) stehen
 DbRep_delread($hash);
 
 if ($opt =~ /dumpMySQL|dumpSQLite/) {	   
     BlockingKill($hash->{HELPER}{RUNNING_BACKUP_CLIENT}) if (exists($hash->{HELPER}{RUNNING_BACKUP_CLIENT}));
     BlockingKill($hash->{HELPER}{RUNNING_BCKPREST_SERVER}) if (exists($hash->{HELPER}{RUNNING_BCKPREST_SERVER}));
	 BlockingKill($hash->{HELPER}{RUNNING_OPTIMIZE}) if (exists($hash->{HELPER}{RUNNING_OPTIMIZE}));
     
     if($dbmodel =~ /MYSQL/) {
	     if ($prop eq "serverSide") {
	         $hash->{HELPER}{RUNNING_BCKPREST_SERVER} = BlockingCall("mysql_DoDumpServerSide", "$name", "DbRep_DumpDone", $to, "DbRep_DumpAborted", $hash);
		     ReadingsSingleUpdateValue ($hash, "state", "serverSide Dump is running - be patient and see Logfile !", 1);
	     } else {
	         $hash->{HELPER}{RUNNING_BACKUP_CLIENT} = BlockingCall("mysql_DoDumpClientSide", "$name", "DbRep_DumpDone", $to, "DbRep_DumpAborted", $hash);
		     ReadingsSingleUpdateValue ($hash, "state", "clientSide Dump is running - be patient and see Logfile !", 1);
	     }
     }
     if($dbmodel =~ /SQLITE/) {
         $hash->{HELPER}{RUNNING_BACKUP_CLIENT} = BlockingCall("DbRep_sqliteDoDump", "$name", "DbRep_DumpDone", $to, "DbRep_DumpAborted", $hash);
         ReadingsSingleUpdateValue ($hash, "state", "SQLite Dump is running - be patient and see Logfile !", 1);    
     }
     return;
 }
 
 if ($opt =~ /restoreMySQL/) {	
     BlockingKill($hash->{HELPER}{RUNNING_BCKPREST_SERVER}) if (exists($hash->{HELPER}{RUNNING_BCKPREST_SERVER}));
     BlockingKill($hash->{HELPER}{RUNNING_OPTIMIZE}) if (exists($hash->{HELPER}{RUNNING_OPTIMIZE}));
     $hash->{HELPER}{RUNNING_BCKPREST_SERVER} = BlockingCall("mysql_RestoreServerSide", "$name|$prop", "DbRep_restoreDone", $to, "DbRep_restoreAborted", $hash);
	 ReadingsSingleUpdateValue ($hash, "state", "restore database is running - be patient and see Logfile !", 1);
     return;
 }
 
 if ($opt =~ /restoreSQLite/) {	
     BlockingKill($hash->{HELPER}{RUNNING_BCKPREST_SERVER}) if (exists($hash->{HELPER}{RUNNING_BCKPREST_SERVER}));
     BlockingKill($hash->{HELPER}{RUNNING_OPTIMIZE}) if (exists($hash->{HELPER}{RUNNING_OPTIMIZE}));
     $hash->{HELPER}{RUNNING_BCKPREST_SERVER} = BlockingCall("DbRep_sqliteRestore", "$name|$prop", "DbRep_restoreDone", $to, "DbRep_restoreAborted", $hash);
	 ReadingsSingleUpdateValue ($hash, "state", "restore database is running - be patient and see Logfile !", 1);
     return;
 }
 
 if ($opt =~ /optimizeTables|vacuum/) {	
     BlockingKill($hash->{HELPER}{RUNNING_OPTIMIZE}) if (exists($hash->{HELPER}{RUNNING_OPTIMIZE}));
     BlockingKill($hash->{HELPER}{RUNNING_BCKPREST_SERVER}) if (exists($hash->{HELPER}{RUNNING_BCKPREST_SERVER}));     
     $hash->{HELPER}{RUNNING_OPTIMIZE} = BlockingCall("DbRep_optimizeTables", "$name", "DbRep_OptimizeDone", $to, "DbRep_OptimizeAborted", $hash);
	 ReadingsSingleUpdateValue ($hash, "state", "optimize tables is running - be patient and see Logfile !", 1);
     return;
 }
 
 if ($opt =~ /repairSQLite/) {	
     BlockingKill($hash->{HELPER}{RUNNING_BACKUP_CLIENT}) if (exists($hash->{HELPER}{RUNNING_BCKPREST_SERVER}));
     BlockingKill($hash->{HELPER}{RUNNING_OPTIMIZE}) if (exists($hash->{HELPER}{RUNNING_OPTIMIZE}));
     BlockingKill($hash->{HELPER}{RUNNING_REPAIR}) if (exists($hash->{HELPER}{RUNNING_REPAIR}));
     $hash->{HELPER}{RUNNING_REPAIR} = BlockingCall("DbRep_sqliteRepair", "$name", "DbRep_RepairDone", $to, "DbRep_RepairAborted", $hash);
	 ReadingsSingleUpdateValue ($hash, "state", "repair database is running - be patient and see Logfile !", 1);
     return;
 }
 
 if (exists($hash->{HELPER}{RUNNING_PID}) && $hash->{ROLE} ne "Agent") {
     Log3 ($name, 3, "DbRep $name - WARNING - old process $hash->{HELPER}{RUNNING_PID}{pid} will be killed now to start a new BlockingCall");
     BlockingKill($hash->{HELPER}{RUNNING_PID});
 }
 
 ReadingsSingleUpdateValue ($hash, "state", "running", 1);
 
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
 
 # Ausgaben und Zeitmanipulationen
 Log3 ($name, 4, "DbRep $name - -------- New selection --------- "); 
 Log3 ($name, 4, "DbRep $name - Command: $opt $prop"); 
 
 # zentrales Timestamp-Array und Zeitgrenzen bereitstellen
 my ($epoch_seconds_begin,$epoch_seconds_end,$runtime_string_first,$runtime_string_next);
 my $ts = "no_aggregation";                                        # Dummy für eine Select-Schleife wenn != $IsTimeSet || $IsAggrSet
 my ($IsTimeSet,$IsAggrSet,$aggregation) = DbRep_checktimeaggr($hash); 
 if($IsTimeSet || $IsAggrSet) {
     ($epoch_seconds_begin,$epoch_seconds_end,$runtime_string_first,$runtime_string_next,$ts) = DbRep_createTimeArray($hash,$aggregation,$opt);
 } else {
     Log3 ($name, 4, "DbRep $name - Timestamp begin human readable: not set") if($opt !~ /tableCurrentPurge/);  
     Log3 ($name, 4, "DbRep $name - Timestamp end human readable: not set") if($opt !~ /tableCurrentPurge/); 
 }
 
 Log3 ($name, 4, "DbRep $name - Aggregation: $aggregation") if($opt !~ /tableCurrentPurge|tableCurrentFillup|fetchrows|insert/); 
 
 #####  Funktionsaufrufe ##### 
 if ($opt eq "sumValue") {
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("sumval_DoParse", "$name§$device§$reading§$prop§$ts", "sumval_ParseDone", $to, "DbRep_ParseAborted", $hash);
	 
 } elsif ($opt =~ m/countEntries/) {
     my $table = $prop;
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("count_DoParse", "$name§$table§$device§$reading§$ts", "count_ParseDone", $to, "DbRep_ParseAborted", $hash);
	 
 } elsif ($opt eq "averageValue") { 
     Log3 ($name, 4, "DbRep $name - averageValue calculation sceme: ".AttrVal($name,"averageCalcForm","avgArithmeticMean"));
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("averval_DoParse", "$name§$device§$reading§$prop§$ts", "averval_ParseDone", $to, "DbRep_ParseAborted", $hash); 
 
 } elsif ($opt eq "fetchrows") {
     my $table = $prop;             
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("fetchrows_DoParse", "$name|$table|$device|$reading|$runtime_string_first|$runtime_string_next", "fetchrows_ParseDone", $to, "DbRep_ParseAborted", $hash);
    
 } elsif ($opt =~ /delSeqDoublets/) {
     my $cmd = $prop?$prop:"adviceRemain"; 
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("delseqdoubl_DoParse", "$name§$cmd§$device§$reading§$ts", "delseqdoubl_ParseDone", $to, "DbRep_ParseAborted", $hash);
    
 } elsif ($opt eq "exportToFile") {            
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("expfile_DoParse", "$name§$device§$reading§$ts", "expfile_ParseDone", $to, "DbRep_ParseAborted", $hash);
    
 } elsif ($opt eq "importFromFile") {             
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("impfile_Push", "$name", "impfile_PushDone", $to, "DbRep_ParseAborted", $hash);
    
 } elsif ($opt eq "maxValue") {        
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("maxval_DoParse", "$name§$device§$reading§$prop§$ts", "maxval_ParseDone", $to, "DbRep_ParseAborted", $hash);   
         
 } elsif ($opt eq "minValue") {        
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("minval_DoParse", "$name§$device§$reading§$prop§$ts", "minval_ParseDone", $to, "DbRep_ParseAborted", $hash);   
         
 } elsif ($opt eq "delEntries") {         
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("del_DoParse", "$name|history|$device|$reading|$runtime_string_first|$runtime_string_next", "del_ParseDone", $to, "DbRep_ParseAborted", $hash);        
 
 } elsif ($opt eq "tableCurrentPurge") {
     undef $runtime_string_first;
     undef $runtime_string_next;      
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("del_DoParse", "$name|current|$device|$reading|$runtime_string_first|$runtime_string_next", "del_ParseDone", $to, "DbRep_ParseAborted", $hash);        
 
 } elsif ($opt eq "tableCurrentFillup") {         
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("currentfillup_Push", "$name|$device|$reading|$runtime_string_first|$runtime_string_next", "currentfillup_Done", $to, "DbRep_ParseAborted", $hash);        
 
 } elsif ($opt eq "diffValue") {        
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("diffval_DoParse", "$name§$device§$reading§$prop§$ts", "diffval_ParseDone", $to, "DbRep_ParseAborted", $hash);   
         
 } elsif ($opt eq "insert") { 
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("insert_Push", "$name", "insert_Done", $to, "DbRep_ParseAborted", $hash);   
         
 } elsif ($opt =~ /deviceRename|readingRename/) { 
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("change_Push", "$name|$device|$reading|$runtime_string_first|$runtime_string_next", "change_Done", $to, "DbRep_ParseAborted", $hash);   
         
 } elsif ($opt =~ /changeValue/) {
     $hash->{HELPER}{RUNNING_PID} = BlockingCall("changeval_Push", "$name§$device§$reading§$runtime_string_first§$runtime_string_next§$ts", "change_Done", $to, "DbRep_ParseAborted", $hash);   
     
 } elsif ($opt =~ /sqlCmd/ ) {
    # Execute a generic sql command
    $hash->{HELPER}{RUNNING_PID} = BlockingCall("sqlCmd_DoParse", "$name|$opt|$runtime_string_first|$runtime_string_next|$prop", "sqlCmd_ParseDone", $to, "DbRep_ParseAborted", $hash);     
 
 } elsif ($opt =~ /syncStandby/ ) {
    # Befehl vor Procedure ausführen
    DbRep_beforeproc($hash, "syncStandby");
    $hash->{HELPER}{RUNNING_PID} = BlockingCall("DbRep_syncStandby", "$name§$device§$reading§$runtime_string_first§$runtime_string_next§$ts§$prop", "DbRep_syncStandbyDone", $to, "DbRep_ParseAborted", $hash);     
 }
                              
$hash->{HELPER}{RUNNING_PID}{loglevel} = 5 if($hash->{HELPER}{RUNNING_PID});  # Forum #77057
return;
}

################################################################################################################
#                              Create zentrales Timsstamp-Array
################################################################################################################
sub DbRep_createTimeArray($$$) {
 my ($hash,$aggregation,$opt) = @_;
 my $name = $hash->{NAME}; 

 # year   als Jahre seit 1900 
 # $mon   als 0..11
 # $time = timelocal( $sec, $min, $hour, $mday, $mon, $year ); 
 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);       # Istzeit Ableitung
 my ($tsbegin,$tsend,$dim,$tsub,$tadd);
 my ($rsec,$rmin,$rhour,$rmday,$rmon,$ryear);
 
 ######################################################################################
 #  absolute Auswertungszeiträume statische und dynamische (Beginn / Ende) berechnen 
 ######################################################################################
 
 my $mints = $hash->{HELPER}{MINTS}?$hash->{HELPER}{MINTS}:"1970-01-01 01:00:00";  # Timestamp des 1. Datensatzes verwenden falls ermittelt
 $tsbegin = AttrVal($name, "timestamp_begin", $mints);
 $tsbegin = DbRep_formatpicker($tsbegin);
 $tsend = AttrVal($name, "timestamp_end", strftime "%Y-%m-%d %H:%M:%S", localtime(time));
 $tsend = DbRep_formatpicker($tsend);
 
 if ( my $tap = AttrVal($name, "timeYearPeriod", undef)) {
     # a  b   c  d
     # 06-01 02-28 , wenn c < a && $mon < a -> Jahr(a)-1, sonst Jahr(c)+1
	 my $ybp = $year+1900;	
     my $yep = $year+1900;
	 $tap =~ qr/^(\d{2})-(\d{2}) (\d{2})-(\d{2})$/p;
	 my $mbp = $1;
	 my $dbp = $2;
	 my $mep = $3;
	 my $dep = $4;
	 my $c = ($mon+1).$mday;
	 my $e = $mep.$dep;
     if ($mep <= $mbp && $c <= $e) {
	     $ybp--;
	 } else {
	     $yep++;
	 }
	 $tsbegin = "$ybp-$mbp-$dbp 00:00:00";
	 $tsend   = "$yep-$mep-$dep 23:59:59";
 }

 if (AttrVal($name,"timestamp_begin","") eq "current_year_begin" ||
     AttrVal($name,"timestamp_end","") eq "current_year_begin") {
     $tsbegin = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,0,1,0,$year)) if(AttrVal($name,"timestamp_begin","") eq "current_year_begin");
	 $tsend   = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,0,1,0,$year)) if(AttrVal($name,"timestamp_end","") eq "current_year_begin");
 } 
 
 if (AttrVal($name, "timestamp_begin", "") eq "current_year_end" ||
          AttrVal($name, "timestamp_end", "") eq "current_year_end") {
     $tsbegin = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,23,31,11,$year)) if(AttrVal($name,"timestamp_begin","") eq "current_year_end");
	 $tsend   = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,23,31,11,$year)) if(AttrVal($name,"timestamp_end","") eq "current_year_end");
 }
 
 if (AttrVal($name, "timestamp_begin", "") eq "previous_year_begin" ||
          AttrVal($name, "timestamp_end", "") eq "previous_year_begin") {
     $tsbegin = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,0,1,0,$year-1)) if(AttrVal($name, "timestamp_begin", "") eq "previous_year_begin");
	 $tsend   = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,0,1,0,$year-1)) if(AttrVal($name, "timestamp_end", "") eq "previous_year_begin");
 } 
 
 if (AttrVal($name, "timestamp_begin", "") eq "previous_year_end" ||
          AttrVal($name, "timestamp_end", "") eq "previous_year_end") {
     $tsbegin = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,23,31,11,$year-1)) if(AttrVal($name, "timestamp_begin", "") eq "previous_year_end");
	 $tsend   = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,23,31,11,$year-1)) if(AttrVal($name, "timestamp_end", "") eq "previous_year_end");
 } 
 
 if (AttrVal($name, "timestamp_begin", "") eq "current_month_begin" ||
          AttrVal($name, "timestamp_end", "") eq "current_month_begin") {
     $tsbegin = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,0,1,$mon,$year)) if(AttrVal($name, "timestamp_begin", "") eq "current_month_begin");
	 $tsend   = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,0,1,$mon,$year)) if(AttrVal($name, "timestamp_end", "") eq "current_month_begin");
 } 
 
 if (AttrVal($name, "timestamp_begin", "") eq "current_month_end" ||
          AttrVal($name, "timestamp_end", "") eq "current_month_end") {
     $dim = $mon-1?30+(($mon+1)*3%7<4):28+!($year%4||$year%400*!($year%100));
	 $tsbegin  = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,23,$dim,$mon,$year)) if(AttrVal($name, "timestamp_begin", "") eq "current_month_end");
     $tsend    = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,23,$dim,$mon,$year)) if(AttrVal($name, "timestamp_end", "") eq "current_month_end");
 } 
 
 if (AttrVal($name, "timestamp_begin", "") eq "previous_month_begin" ||
          AttrVal($name, "timestamp_end", "") eq "previous_month_begin") {
     $ryear = ($mon-1<0)?$year-1:$year;
	 $rmon  = ($mon-1<0)?11:$mon-1;
     $tsbegin  = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,0,1,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "previous_month_begin");
	 $tsend    = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,0,1,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "") eq "previous_month_begin");
 } 
 
 if (AttrVal($name, "timestamp_begin", "") eq "previous_month_end" ||
          AttrVal($name, "timestamp_end", "") eq "previous_month_end") {
     $ryear = ($mon-1<0)?$year-1:$year;
	 $rmon  = ($mon-1<0)?11:$mon-1;
	 $dim   = $rmon-1?30+(($rmon+1)*3%7<4):28+!($ryear%4||$ryear%400*!($ryear%100));
	 $tsbegin  = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,23,$dim,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "previous_month_end");
     $tsend    = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,23,$dim,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "") eq "previous_month_end");
 } 
 
 if (AttrVal($name, "timestamp_begin", "") eq "current_week_begin" ||
          AttrVal($name, "timestamp_end", "") eq "current_week_begin") {
	 $tsub = 0 if($wday == 1);            # wenn Start am "Mo" keine Korrektur
	 $tsub = 86400 if($wday == 2);        # wenn Start am "Di" dann Korrektur -1 Tage
	 $tsub = 172800 if($wday == 3);       # wenn Start am "Mi" dann Korrektur -2 Tage
	 $tsub = 259200 if($wday == 4);       # wenn Start am "Do" dann Korrektur -3 Tage
	 $tsub = 345600 if($wday == 5);       # wenn Start am "Fr" dann Korrektur -4 Tage
	 $tsub = 432000 if($wday == 6);       # wenn Start am "Sa" dann Korrektur -5 Tage
	 $tsub = 518400 if($wday == 0);       # wenn Start am "So" dann Korrektur -6 Tage
	 ($rsec,$rmin,$rhour,$rmday,$rmon,$ryear) = localtime(time-$tsub);
	 $tsbegin = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,0,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "current_week_begin");
	 $tsend   = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,0,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "") eq "current_week_begin");
 } 
 
 if (AttrVal($name, "timestamp_begin", "") eq "current_week_end" ||
          AttrVal($name, "timestamp_end", "") eq "current_week_end") {
	 $tadd = 518400 if($wday == 1);       # wenn Start am "Mo" dann Korrektur +6 Tage
	 $tadd = 432000 if($wday == 2);       # wenn Start am "Di" dann Korrektur +5 Tage
	 $tadd = 345600 if($wday == 3);       # wenn Start am "Mi" dann Korrektur +4 Tage
	 $tadd = 259200 if($wday == 4);       # wenn Start am "Do" dann Korrektur +3 Tage
	 $tadd = 172800 if($wday == 5);       # wenn Start am "Fr" dann Korrektur +2 Tage
	 $tadd = 86400 if($wday == 6);        # wenn Start am "Sa" dann Korrektur +1 Tage
	 $tadd = 0 if($wday == 0);            # wenn Start am "So" keine Korrektur
	 ($rsec,$rmin,$rhour,$rmday,$rmon,$ryear) = localtime(time+$tadd);
	 $tsbegin  = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,23,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "current_week_end");
	 $tsend    = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,23,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "") eq "current_week_end");
 } 
 
 if (AttrVal($name, "timestamp_begin", "") eq "previous_week_begin" ||
          AttrVal($name, "timestamp_end", "") eq "previous_week_begin") {
	 $tsub = 604800 if($wday == 1);       # wenn Start am "Mo" dann Korrektur -7 Tage
	 $tsub = 691200 if($wday == 2);       # wenn Start am "Di" dann Korrektur -8 Tage
	 $tsub = 777600 if($wday == 3);       # wenn Start am "Mi" dann Korrektur -9 Tage
	 $tsub = 864000 if($wday == 4);       # wenn Start am "Do" dann Korrektur -10 Tage
	 $tsub = 950400 if($wday == 5);       # wenn Start am "Fr" dann Korrektur -11 Tage
	 $tsub = 1036800 if($wday == 6);      # wenn Start am "Sa" dann Korrektur -12 Tage
	 $tsub = 1123200 if($wday == 0);      # wenn Start am "So" dann Korrektur -13 Tage
	 ($rsec,$rmin,$rhour,$rmday,$rmon,$ryear) = localtime(time-$tsub);
	 $tsbegin = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,0,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "previous_week_begin");
	 $tsend   = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,0,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "") eq "previous_week_begin");
 }
 
 if (AttrVal($name, "timestamp_begin", "") eq "previous_week_end" ||
          AttrVal($name, "timestamp_end", "") eq "previous_week_end") {
	 $tsub = 86400 if($wday == 1);        # wenn Start am "Mo" dann Korrektur -1 Tage
	 $tsub = 172800 if($wday == 2);       # wenn Start am "Di" dann Korrektur -2 Tage
	 $tsub = 259200 if($wday == 3);       # wenn Start am "Mi" dann Korrektur -3 Tage
	 $tsub = 345600 if($wday == 4);       # wenn Start am "Do" dann Korrektur -4 Tage
	 $tsub = 432000 if($wday == 5);       # wenn Start am "Fr" dann Korrektur -5 Tage
	 $tsub = 518400 if($wday == 6);       # wenn Start am "Sa" dann Korrektur -6 Tage
	 $tsub = 604800 if($wday == 0);       # wenn Start am "So" dann Korrektur -7 Tage
	 ($rsec,$rmin,$rhour,$rmday,$rmon,$ryear) = localtime(time-$tsub);
	 $tsbegin  = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,23,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "previous_week_end");
	 $tsend    = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,23,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "") eq "previous_week_end");
 } 
 
 if (AttrVal($name, "timestamp_begin", "") eq "current_day_begin" ||
          AttrVal($name, "timestamp_end", "") eq "current_day_begin") {
     $tsbegin = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,0,$mday,$mon,$year)) if(AttrVal($name, "timestamp_begin", "") eq "current_day_begin");
	 $tsend   = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,0,$mday,$mon,$year)) if(AttrVal($name, "timestamp_end", "") eq "current_day_begin");
 } 
 
 if (AttrVal($name, "timestamp_begin", "") eq "current_day_end" ||
          AttrVal($name, "timestamp_end", "") eq "current_day_end") {
     $tsbegin = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,23,$mday,$mon,$year)) if(AttrVal($name, "timestamp_begin", "") eq "current_day_end");
     $tsend   = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,23,$mday,$mon,$year)) if(AttrVal($name, "timestamp_end", "") eq "current_day_end");
 } 
 
 if (AttrVal($name, "timestamp_begin", "") eq "previous_day_begin" ||
          AttrVal($name, "timestamp_end", "") eq "previous_day_begin") {
	 $rmday = $mday-1;
	 $rmon  = $mon;
	 $ryear = $year;
	 if($rmday<1) {
	     $rmon--;
		 if ($rmon<0) {
		     $rmon=11;
		     $ryear--;
		 }
         $rmday = $rmon-1?30+(($rmon+1)*3%7<4):28+!($ryear%4||$ryear%400*!($ryear%100));  # Achtung: Monat als 1...12 (statt 0...11)
	 }
     $tsbegin = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,0,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "previous_day_begin");
	 $tsend   = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,0,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "") eq "previous_day_begin");
 } 
 
 if (AttrVal($name, "timestamp_begin", "") eq "previous_day_end" ||
          AttrVal($name, "timestamp_end", "") eq "previous_day_end") {
	 $rmday = $mday-1;
	 $rmon  = $mon;
	 $ryear = $year;
	 if($rmday<1) {
	     $rmon--;
		 if ($rmon<0) {
		     $rmon=11;
		     $ryear--;
		 }
         $rmday = $rmon-1?30+(($rmon+1)*3%7<4):28+!($ryear%4||$ryear%400*!($ryear%100));  # Achtung: Monat als 1...12 (statt 0...11)
	 }
     $tsbegin = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,23,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "previous_day_end");
     $tsend   = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,23,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "") eq "previous_day_end");
 } 
 
 if (AttrVal($name, "timestamp_begin", "") eq "current_hour_begin" ||
          AttrVal($name, "timestamp_end", "") eq "current_hour_begin") {
     $tsbegin = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,$hour,$mday,$mon,$year)) if(AttrVal($name, "timestamp_begin", "") eq "current_hour_begin");
	 $tsend   = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,$hour,$mday,$mon,$year)) if(AttrVal($name, "timestamp_end", "") eq "current_hour_begin");
 } 
 
 if (AttrVal($name, "timestamp_begin", "") eq "current_hour_end" ||
          AttrVal($name, "timestamp_end", "") eq "current_hour_end") {
	 $tsbegin = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,$hour,$mday,$mon,$year)) if(AttrVal($name, "timestamp_begin", "") eq "current_hour_end");
     $tsend   = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,$hour,$mday,$mon,$year)) if(AttrVal($name, "timestamp_end", "") eq "current_hour_end");
 } 
 
 if (AttrVal($name, "timestamp_begin", "") eq "previous_hour_begin" ||
          AttrVal($name, "timestamp_end", "") eq "previous_hour_begin") {
     $rhour = $hour-1;
	 $rmday = $mday;
	 $rmon  = $mon;
	 $ryear = $year;
	 if($rhour<0) {
	     $rhour = 23;
		 $rmday = $mday-1;
		 if($rmday<1) {
	         $rmon--;
		     if ($rmon<0) {
		         $rmon=11;
		         $ryear--;
		     }
			 $rmday = $rmon-1?30+(($rmon+1)*3%7<4):28+!($ryear%4||$ryear%400*!($ryear%100));  # Achtung: Monat als 1...12 (statt 0...11)
		 }
	 }
     $tsbegin = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,$rhour,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "previous_hour_begin");
	 $tsend   = strftime "%Y-%m-%d %T",localtime(timelocal(0,0,$rhour,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "") eq "previous_hour_begin");
 } 
 
 if (AttrVal($name, "timestamp_begin", "") eq "previous_hour_end" ||
          AttrVal($name, "timestamp_end", "") eq "previous_hour_end") {
     $rhour = $hour-1;
	 $rmday = $mday;
	 $rmon  = $mon;
	 $ryear = $year;
	 if($rhour<0) {
	     $rhour = 23;
		 $rmday = $mday-1;
		 if($rmday<1) {
	         $rmon--;
		     if ($rmon<0) {
		         $rmon=11;
		         $ryear--;
		     }
			 $rmday = $rmon-1?30+(($rmon+1)*3%7<4):28+!($ryear%4||$ryear%400*!($ryear%100));  # Achtung: Monat als 1...12 (statt 0...11)
		 }
	 }
	 $tsbegin = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,$rhour,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_begin", "") eq "previous_hour_end"); 
     $tsend   = strftime "%Y-%m-%d %T",localtime(timelocal(59,59,$rhour,$rmday,$rmon,$ryear)) if(AttrVal($name, "timestamp_end", "") eq "previous_hour_end"); 
 }  
 
 # extrahieren der Einzelwerte von Datum/Zeit Beginn
 my ($yyyy1, $mm1, $dd1, $hh1, $min1, $sec1) = ($tsbegin =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/); 
 # extrahieren der Einzelwerte von Datum/Zeit Ende 
 my ($yyyy2, $mm2, $dd2, $hh2, $min2, $sec2) = ($tsend =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
        	 
 ######################################################################################
 #  relative Auswertungszeit Beginn berücksichtigen  
 ######################################################################################
 # Umwandeln in Epochesekunden Beginn
 my $epoch_seconds_begin = timelocal($sec1, $min1, $hh1, $dd1, $mm1-1, $yyyy1-1900) if($tsbegin);
 my ($timeolderthan,$timedifftonow) = DbRep_normRelTime($hash);
 
 if($timedifftonow) {
     $epoch_seconds_begin = time() - $timedifftonow;
     Log3 ($name, 4, "DbRep $name - Time difference to current time for calculating Timestamp begin: $timedifftonow sec"); 
 } elsif ($timeolderthan) {
     $epoch_seconds_begin = timelocal(00, 00, 01, 01, 01-1, 1970-1900);
 }
 
 my $tsbegin_string = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_begin);
 Log3 ($name, 5, "DbRep $name - Timestamp begin epocheseconds: $epoch_seconds_begin") if($opt !~ /tableCurrentPurge/);   
 Log3 ($name, 4, "DbRep $name - Timestamp begin human readable: $tsbegin_string") if($opt !~ /tableCurrentPurge/);  
 
 ######################################################################################
 #  relative Auswertungszeit Ende berücksichtigen  
 ######################################################################################
 # Umwandeln in Epochesekunden Endezeit
 my $epoch_seconds_end = timelocal($sec2, $min2, $hh2, $dd2, $mm2-1, $yyyy2-1900); 
 
 $epoch_seconds_end = $timeolderthan ? (time() - $timeolderthan) : $epoch_seconds_end;

 #$epoch_seconds_end = AttrVal($name, "timeOlderThan", undef) ? 
 #                          (time() - AttrVal($name, "timeOlderThan", undef)) : $epoch_seconds_end;
 Log3 ($name, 4, "DbRep $name - Time difference to current time for calculating Timestamp end: $timeolderthan sec") if(AttrVal($name, "timeOlderThan", undef)); 
 
 my $tsend_string = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
 
 Log3 ($name, 5, "DbRep $name - Timestamp end epocheseconds: $epoch_seconds_end") if($opt !~ /tableCurrentPurge/); 
 Log3 ($name, 4, "DbRep $name - Timestamp end human readable: $tsend_string") if($opt !~ /tableCurrentPurge/); 

 ######################################################################################
 #  Erstellung Wertehash für Aggregationen
 ######################################################################################
 my $runtime = $epoch_seconds_begin;                                    # Schleifenlaufzeit auf Beginn der Zeitselektion setzen
 my $runtime_string;                                                    # Datum/Zeit im SQL-Format für Readingname Teilstring
 my $runtime_string_first;                                              # Datum/Zeit Auswertungsbeginn im SQL-Format für SQL-Statement
 my $runtime_string_next;                                               # Datum/Zeit + Periode (Granularität) für Auswertungsende im SQL-Format 
 my $reading_runtime_string;                                            # zusammengesetzter Readingname+Aggregation für Update
 my $tsstr   = strftime "%H:%M:%S", localtime($runtime);                # für Berechnung Tagesverschieber / Stundenverschieber
 my $testr   = strftime "%H:%M:%S", localtime($epoch_seconds_end);      # für Berechnung Tagesverschieber / Stundenverschieber
 my $dsstr   = strftime "%Y-%m-%d", localtime($runtime);                # für Berechnung Tagesverschieber / Stundenverschieber
 my $destr   = strftime "%Y-%m-%d", localtime($epoch_seconds_end);      # für Berechnung Tagesverschieber / Stundenverschieber
 my $msstr   = strftime "%m", localtime($runtime);                      # Startmonat für Berechnung Monatsverschieber
 my $mestr   = strftime "%m", localtime($epoch_seconds_end);            # Endemonat für Berechnung Monatsverschieber
 my $ysstr   = strftime "%Y", localtime($runtime);                      # Startjahr für Berechnung Monatsverschieber
 my $yestr   = strftime "%Y", localtime($epoch_seconds_end);            # Endejahr für Berechnung Monatsverschieber
 
 my $wd = strftime "%a", localtime($runtime);                           # Wochentag des aktuellen Startdatum/Zeit
 my $wdadd = 604800 if($wd eq "Mo");                                    # wenn Start am "Mo" dann nächste Grenze +7 Tage
 $wdadd = 518400 if($wd eq "Di");                                       # wenn Start am "Di" dann nächste Grenze +6 Tage
 $wdadd = 432000 if($wd eq "Mi");                                       # wenn Start am "Mi" dann nächste Grenze +5 Tage
 $wdadd = 345600 if($wd eq "Do");                                       # wenn Start am "Do" dann nächste Grenze +4 Tage
 $wdadd = 259200 if($wd eq "Fr");                                       # wenn Start am "Fr" dann nächste Grenze +3 Tage
 $wdadd = 172800 if($wd eq "Sa");                                       # wenn Start am "Sa" dann nächste Grenze +2 Tage
 $wdadd = 86400  if($wd eq "So");                                       # wenn Start am "So" dann nächste Grenze +1 Tage
             
 Log3 ($name, 5, "DbRep $name - weekday of start for selection: $wd  ->  wdadd: $wdadd") if($wdadd); 
 
 my $aggsec;
 if ($aggregation eq "hour") {
     $aggsec = 3600;
 } elsif ($aggregation eq "day") {
     $aggsec = 86400;
 } elsif ($aggregation eq "week") {
     $aggsec = 604800;
 } elsif ($aggregation eq "month") {
     $aggsec = 2678400;                      # Initialwert, wird in DbRep_collaggstr für jeden Monat berechnet
 } elsif ($aggregation eq "no") {
     $aggsec = 1;
 } else {
    return;
 }
 
my %cv = (
  tsstr             => $tsstr,
  testr             => $testr,
  dsstr             => $dsstr,
  destr             => $destr,
  msstr             => $msstr,
  mestr             => $mestr,
  ysstr             => $ysstr,
  yestr             => $yestr,
  aggsec            => $aggsec,
  aggregation       => $aggregation,
  epoch_seconds_end => $epoch_seconds_end,
  wdadd             => $wdadd
);
$hash->{HELPER}{CV} = \%cv;

    my $ts;              # für Erstellung Timestamp-Array zur nonblocking SQL-Abarbeitung
    my $i = 1;           # Schleifenzähler -> nur Indikator für ersten Durchlauf -> anderer $runtime_string_first
    my $ll;              # loopindikator, wenn 1 = loopausstieg
 
    # Aufbau Timestampstring mit Zeitgrenzen entsprechend Aggregation
    while (!$ll) {
        # collect aggregation strings         
        ($runtime,$runtime_string,$runtime_string_first,$runtime_string_next,$ll) = DbRep_collaggstr($hash,$runtime,$i,$runtime_string_next);
        $ts .= $runtime_string."#".$runtime_string_first."#".$runtime_string_next."|";
        $i++;
    } 

return ($epoch_seconds_begin,$epoch_seconds_end,$runtime_string_first,$runtime_string_next,$ts);
}

####################################################################################################
#  Zusammenstellung Aggregationszeiträume
####################################################################################################
sub DbRep_collaggstr($$$$) {
 my ($hash,$runtime,$i,$runtime_string_next) = @_;
 my $name = $hash->{NAME};
 my $runtime_string;                                               # Datum/Zeit im SQL-Format für Readingname Teilstring
 my $runtime_string_first;                                         # Datum/Zeit Auswertungsbeginn im SQL-Format für SQL-Statement
 my $ll;                                                           # loopindikator, wenn 1 = loopausstieg
 my $runtime_orig;                                                 # orig. runtime als Grundlage für Addition mit $aggsec
 my $tsstr             = $hash->{HELPER}{CV}{tsstr};               # für Berechnung Tagesverschieber / Stundenverschieber      
 my $testr             = $hash->{HELPER}{CV}{testr};               # für Berechnung Tagesverschieber / Stundenverschieber
 my $dsstr             = $hash->{HELPER}{CV}{dsstr};               # für Berechnung Tagesverschieber / Stundenverschieber
 my $destr             = $hash->{HELPER}{CV}{destr};               # für Berechnung Tagesverschieber / Stundenverschieber
 my $msstr             = $hash->{HELPER}{CV}{msstr};               # Startmonat für Berechnung Monatsverschieber
 my $mestr             = $hash->{HELPER}{CV}{mestr};               # Endemonat für Berechnung Monatsverschieber
 my $ysstr             = $hash->{HELPER}{CV}{ysstr};               # Startjahr für Berechnung Monatsverschieber
 my $yestr             = $hash->{HELPER}{CV}{yestr};               # Endejahr für Berechnung Monatsverschieber
 my $aggregation       = $hash->{HELPER}{CV}{aggregation};         # Aggregation
 my $aggsec            = $hash->{HELPER}{CV}{aggsec};              # laufende Aggregationssekunden
 my $epoch_seconds_end = $hash->{HELPER}{CV}{epoch_seconds_end};
 my $wdadd             = $hash->{HELPER}{CV}{wdadd};               # Ergänzungstage. Starttag + Ergänzungstage = der folgende Montag (für week-Aggregation)  
 
 # only for this block because of warnings if some values not set
 no warnings 'uninitialized'; 

         # keine Aggregation (all between timestamps)
         if ($aggregation eq "no") {
             $runtime_string       = "no_aggregation";                                         # für Readingname
             $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime);
             $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);  
             $ll = 1;
         }
         
         # Monatsaggregation
         if ($aggregation eq "month") {
             $runtime_orig = $runtime;
             
             # Hilfsrechnungen
             my $rm   = strftime "%m", localtime($runtime);                    # Monat des aktuell laufenden Startdatums d. SQL-Select
             my $ry   = strftime "%Y", localtime($runtime);                    # Jahr des aktuell laufenden Startdatums d. SQL-Select
             my $dim  = $rm-2?30+($rm*3%7<4):28+!($ry%4||$ry%400*!($ry%100));  # Anzahl Tage des aktuell laufenden Monats
             Log3 ($name, 5, "DbRep $name - act year:  $ry, act month: $rm, days in month: $dim, endyear: $yestr, endmonth: $mestr"); 
             $aggsec = $dim * 86400;
             
             $runtime = $runtime+3600 if(DbRep_dsttest($hash,$runtime,$aggsec) && (strftime "%m", localtime($runtime)) > 6);      # Korrektur Winterzeitumstellung (Uhr wurde 1 Stunde zurück gestellt)
                                  
             $runtime_string = strftime "%Y-%m", localtime($runtime);          # für Readingname
             
             if ($i==1) {
                 # nur im ersten Durchlauf
                 $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime_orig);
             }
             
             if ($ysstr == $yestr && $msstr == $mestr || $ry ==  $yestr && $rm == $mestr) {
                 $runtime_string_first = strftime "%Y-%m-01", localtime($runtime) if($i>1);
                 $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
                 $ll=1;
                
             } else {
                 if(($runtime) > $epoch_seconds_end) {
                     #$runtime_string_first = strftime "%Y-%m-01", localtime($runtime) if($i>11);  # ausgebaut 24.02.2018
                     $runtime_string_first = strftime "%Y-%m-01", localtime($runtime);                      
                     $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
                     $ll=1;
                 } else {
                     $runtime_string_first = strftime "%Y-%m-01", localtime($runtime) if($i>1);
                     $runtime_string_next  = strftime "%Y-%m-01", localtime($runtime+($dim*86400));
                     
                 } 
             }
         my ($yyyy1, $mm1, $dd1) = ($runtime_string_next =~ /(\d+)-(\d+)-(\d+)/);
         $runtime = timelocal("00", "00", "00", "01", $mm1-1, $yyyy1-1900);
         
         # neue Beginnzeit in Epoche-Sekunden
         $runtime = $runtime_orig+$aggsec;
         }
         
         # Wochenaggregation
         if ($aggregation eq "week") {          
             $runtime = $runtime+3600 if($i!=1 && DbRep_dsttest($hash,$runtime,$aggsec) && (strftime "%m", localtime($runtime)) > 6);      # Korrektur Winterzeitumstellung (Uhr wurde 1 Stunde zurück gestellt)
             $runtime_orig = $runtime; 

             my $w  = strftime "%V", localtime($runtime);            # Wochennummer des aktuellen Startdatum/Zeit
             $runtime_string = "week_".$w;                           # für Readingname
             my $ms = strftime "%m", localtime($runtime);            # Startmonat (01-12)
             my $me = strftime "%m", localtime($epoch_seconds_end);  # Endemonat (01-12)
             
             if ($i==1) {
                 # nur im ersten Schleifendurchlauf
                 $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime);
                 
                 # Korrektur $runtime_orig für Berechnung neue Beginnzeit für nächsten Durchlauf 
                 my ($yyyy1, $mm1, $dd1) = ($runtime_string_first =~ /(\d+)-(\d+)-(\d+)/);
                 $runtime = timelocal("00", "00", "00", $dd1, $mm1-1, $yyyy1-1900);
                 $runtime = $runtime+3600 if(DbRep_dsttest($hash,$runtime,$aggsec) && (strftime "%m", localtime($runtime)) > 6);           # Korrektur Winterzeitumstellung (Uhr wurde 1 Stunde zurück gestellt)
                 $runtime = $runtime+$wdadd;
                 $runtime_orig = $runtime-$aggsec;                             
                 
                 # die Woche Beginn ist gleich der Woche vom Ende Auswertung
                 if((strftime "%V", localtime($epoch_seconds_end)) eq ($w) && ($ms+$me != 13)) {                  
                     $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end); 
                     $ll=1;
                 } else {
                      $runtime_string_next  = strftime "%Y-%m-%d", localtime($runtime);
                 }
             } else {
                 # weitere Durchläufe
                 if(($runtime+$aggsec) > $epoch_seconds_end) {
                     $runtime_string_first = strftime "%Y-%m-%d", localtime($runtime_orig);
                     $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end); 
                     $ll=1;
                 } else {
                     $runtime_string_first = strftime "%Y-%m-%d", localtime($runtime_orig) ;
                     $runtime_string_next  = strftime "%Y-%m-%d", localtime($runtime+$aggsec);  
                 }
             }
         
         # neue Beginnzeit in Epoche-Sekunden
         $runtime = $runtime_orig+$aggsec;           
         }
     
         # Tagesaggregation
         if ($aggregation eq "day") {  
             $runtime_string       = strftime "%Y-%m-%d", localtime($runtime);                      # für Readingname
             $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime) if($i==1);
             $runtime_string_first = strftime "%Y-%m-%d", localtime($runtime) if($i>1);
             $runtime = $runtime+3600 if(DbRep_dsttest($hash,$runtime,$aggsec) && (strftime "%m", localtime($runtime)) > 6);                          # Korrektur Winterzeitumstellung (Uhr wurde 1 Stunde zurück gestellt)
                                               
             if((($tsstr gt $testr) ? $runtime : ($runtime+$aggsec)) > $epoch_seconds_end) {
                 $runtime_string_first = strftime "%Y-%m-%d", localtime($runtime);                    
                 $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime) if( $dsstr eq $destr);
                 $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
                 $ll=1;
             } else {
                 $runtime_string_next  = strftime "%Y-%m-%d", localtime($runtime+$aggsec);   
             }
         Log3 ($name, 5, "DbRep $name - runtime_string: $runtime_string, runtime_string_first: $runtime_string_first, runtime_string_next: $runtime_string_next");

         # neue Beginnzeit in Epoche-Sekunden
         $runtime = $runtime+$aggsec;         
         }
     
         # Stundenaggregation
         if ($aggregation eq "hour") {
             $runtime_string       = strftime "%Y-%m-%d_%H", localtime($runtime);                   # für Readingname
             $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime) if($i==1);
             $runtime = $runtime+3600 if(DbRep_dsttest($hash,$runtime,$aggsec) && (strftime "%m", localtime($runtime)) > 6);                          # Korrektur Winterzeitumstellung (Uhr wurde 1 Stunde zurück gestellt)
             $runtime_string_first = strftime "%Y-%m-%d %H", localtime($runtime) if($i>1);
             
             my @a = split (":",$tsstr);
             my $hs = $a[0];
             my $msstr = $a[1].":".$a[2];
             @a = split (":",$testr);
             my $he = $a[0];
             my $mestr = $a[1].":".$a[2];
             
             if((($msstr gt $mestr) ? $runtime : ($runtime+$aggsec)) > $epoch_seconds_end) {
                 $runtime_string_first = strftime "%Y-%m-%d %H", localtime($runtime);                 
                 $runtime_string_first = strftime "%Y-%m-%d %H:%M:%S", localtime($runtime) if( $dsstr eq $destr && $hs eq $he);
                 $runtime_string_next  = strftime "%Y-%m-%d %H:%M:%S", localtime($epoch_seconds_end);
                 $ll=1;
             } else {
                 $runtime_string_next  = strftime "%Y-%m-%d %H", localtime($runtime+$aggsec);   
             }
        
         # neue Beginnzeit in Epoche-Sekunden
         $runtime = $runtime+$aggsec;         
         }
         
return ($runtime,$runtime_string,$runtime_string_first,$runtime_string_next,$ll);
}

####################################################################################################
# nichtblockierende DB-Abfrage averageValue
####################################################################################################
sub averval_DoParse($) {
 my ($string) = @_;
 my ($name,$device,$reading,$prop,$ts) = split("\\§", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $acf        = AttrVal($name, "averageCalcForm", "avgArithmeticMean");     # Festlegung Berechnungsschema f. Mittelwert
 my $qlf        = "avg";
 my ($dbh,$sql,$sth,$err,$selspec,$addon);

 # Background-Startzeit
 my $bst = [gettimeofday];

 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|$device|$reading|''|$err|''";
 }
     
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
  
 # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef) 
 my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash); 
 Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");
 
 # Timestampstring to Array
 my @ts = split("\\|", $ts);
 Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");

 if($acf eq "avgArithmeticMean") {
     # arithmetischer Mittelwert
     # vorbereiten der DB-Abfrage, DB-Modell-abhaengig
     $addon = '';
     if ($dbloghash->{MODEL} eq "POSTGRESQL") {
         $selspec = "AVG(VALUE::numeric)";
     } elsif ($dbloghash->{MODEL} eq "MYSQL") {
         $selspec = "AVG(VALUE)";
     } elsif ($dbloghash->{MODEL} eq "SQLITE") {
         $selspec = "AVG(VALUE)";
     } else {
         $selspec = "AVG(VALUE)";
     }
     $qlf = "avgam";
 } elsif ($acf eq "avgDailyMeanGWS") {
     # Tagesmittelwert Temperaturen nach Schema des deutschen Wetterdienstes
     # SELECT VALUE FROM history WHERE DEVICE="MyWetter" AND READING="temperature" AND TIMESTAMP >= "2018-01-28 $i:00:00" AND TIMESTAMP <= "2018-01-28 ($i+1):00:00" ORDER BY TIMESTAMP DESC LIMIT 1; 
     $addon   = "ORDER BY TIMESTAMP DESC LIMIT 1";
     $selspec = "VALUE";
     $qlf     = "avgdmgws";
 } elsif ($acf eq "avgTimeWeightMean") {
     $addon   = "ORDER BY TIMESTAMP ASC";
     $selspec = "TIMESTAMP,VALUE";
     $qlf     = "avgtwm";
 }
	 
 # SQL-Startzeit
 my $st = [gettimeofday];
      
 # DB-Abfrage zeilenweise für jeden Array-Eintrag
 my $arrstr;
 foreach my $row (@ts) {
     my @a                     = split("#", $row);
     my $runtime_string        = $a[0];
     my $runtime_string_first  = $a[1];
     my $runtime_string_next   = $a[2];
     
     if($acf eq "avgArithmeticMean") {
         # arithmetischer Mittelwert (Standard)
         #           
         if ($IsTimeSet || $IsAggrSet) {
             $sql = DbRep_createSelectSql($hash,"history",$selspec,$device,$reading,"'$runtime_string_first'","'$runtime_string_next'",$addon); 
	     } else {
	         $sql = DbRep_createSelectSql($hash,"history",$selspec,$device,$reading,undef,undef,$addon);
	     }
         Log3 ($name, 4, "DbRep $name - SQL execute: $sql");
         
         eval{ $sth = $dbh->prepare($sql);
               $sth->execute();
             };	         
	     if ($@) {
             $err = encode_base64($@,"");
             Log3 ($name, 2, "DbRep $name - $@");
             $dbh->disconnect;
             return "$name|''|$device|$reading|''|$err|''";
         }
	 
         my @line = $sth->fetchrow_array();
     
         Log3 ($name, 5, "DbRep $name - SQL result: $line[0]") if($line[0]);
	 
         if(AttrVal($name, "aggregation", "") eq "hour") {
             my @rsf = split(/[" "\|":"]/,$runtime_string_first);
             $arrstr .= $runtime_string."#".$line[0]."#".$rsf[0]."_".$rsf[1]."|";  
         } else {
             my @rsf = split(" ",$runtime_string_first);
             $arrstr .= $runtime_string."#".$line[0]."#".$rsf[0]."|"; 
         }
     
     } elsif ($acf eq "avgDailyMeanGWS") {
         # Berechnung des Tagesmittelwertes (Temperatur) nach der Vorschrift des deutschen Wetterdienstes
         # Berechnung der Tagesmittel aus 24 Stundenwerten, Bezugszeit für einen Tag i.d.R. 23:51 UTC des 
         # Vortages bis 23:50 UTC, d.h. 00:51 bis 23:50 MEZ 
         # Wenn mehr als 3 Stundenwerte fehlen -> Berechnung aus den 4 Hauptterminen (00, 06, 12, 18 UTC), 
         # d.h. 01, 07, 13, 19 MEZ
         # https://www.dwd.de/DE/leistungen/klimadatendeutschland/beschreibung_tagesmonatswerte.html
         #
         my $sum = 0;
         my $anz = 0;                   # Anzahl der Messwerte am Tag
         my($t01,$t07,$t13,$t19);       # Temperaturen der Haupttermine
         my ($bdate,undef) = split(" ",$runtime_string_first);
         for my $i (0..23) {
             my $bsel = $bdate." ".sprintf("%02d",$i).":00:00";
             my $esel  = ($i<23)?$bdate." ".sprintf("%02d",$i).":59:59":$runtime_string_next;

	         $sql = DbRep_createSelectSql($hash,"history",$selspec,$device,$reading,"'$bsel'","'$esel'",$addon);
             Log3 ($name, 4, "DbRep $name - SQL execute: $sql");
     
             eval{ $sth = $dbh->prepare($sql);
                   $sth->execute();
                 };	
	         if ($@) {
                 $err = encode_base64($@,"");
                 Log3 ($name, 2, "DbRep $name - $@");
                 $dbh->disconnect;
                 return "$name|''|$device|$reading|''|$err|''";
             }
             my $val = $sth->fetchrow_array();
             Log3 ($name, 5, "DbRep $name - SQL result: $val") if($val); 
             $val = DbRep_numval ($val);    # nichtnumerische Zeichen eliminieren			 
             if(defined($val) && looks_like_number($val)) {
                 $sum += $val;
                 $t01 = $val if($val && $i == 00);   # Wert f. Stunde 01 ist zw. letzter Wert vor 01
                 $t07 = $val if($val && $i == 06);
                 $t13 = $val if($val && $i == 12);
                 $t19 = $val if($val && $i == 18);
                 $anz++;
             }
         }
         if($anz >= 21) {        
             $sum = $sum/24;
         } elsif ($anz >= 4 && $t01 && $t07 && $t13 && $t19) {
             $sum = ($t01+$t07+$t13+$t19)/4;
         } else {
             $sum = "insufficient values";
         }
 
         if(AttrVal($name, "aggregation", "") eq "hour") {
             my @rsf = split(/[" "\|":"]/,$runtime_string_first);
             $arrstr .= $runtime_string."#".$sum."#".$rsf[0]."_".$rsf[1]."|";  
         } else {
             my @rsf = split(" ",$runtime_string_first);
             $arrstr .= $runtime_string."#".$sum."#".$rsf[0]."|"; 
         }      
     
     } elsif ($acf eq "avgTimeWeightMean") {
         # zeitgewichteten Mittelwert berechnen
         # http://massmatics.de/merkzettel/#!837:Gewichteter_Mittelwert
         #
         # $tsum = timestamp letzter Messpunkt - timestamp erster Messpunkt
         # $t1 = timestamp wert1
         # $t2 = timestamp wert2
         # $dt = $t2 - $t1
         # $t1 = $t2 
         # .....
         # (val1*$dt/$tsum) + (val2*$dt/$tsum) + .... + (valn*$dt/$tsum)
         #
         
         # gesamte Zeitspanne $tsum zwischen ersten und letzten Datensatz der Zeitscheibe ermitteln
         my ($tsum,$tf,$tl,$tn,$to,$dt,$val,$val1);
         my $sum = 0;
         my $addonf = 'ORDER BY TIMESTAMP ASC LIMIT 1';
         my $addonl = 'ORDER BY TIMESTAMP DESC LIMIT 1';
         my $sqlf   = DbRep_createSelectSql($hash,"history","TIMESTAMP",$device,$reading,"'$runtime_string_first'","'$runtime_string_next'",$addonf);
         my $sqll   = DbRep_createSelectSql($hash,"history","TIMESTAMP",$device,$reading,"'$runtime_string_first'","'$runtime_string_next'",$addonl);
         
         eval { $tf = ($dbh->selectrow_array($sqlf))[0];
                $tl = ($dbh->selectrow_array($sqll))[0];
              };
	     if ($@) {
             $err = encode_base64($@,"");
             Log3 ($name, 2, "DbRep $name - $@");
             $dbh->disconnect;
             return "$name|''|$device|$reading|''|$err|''";
         }
         
         if(!$tf || !$tl) {
             # kein Start- und/oder Ende Timestamp in Zeitscheibe vorhanden -> keine Werteberechnung möglich
             $sum = "insufficient values";
         } else {
             my ($yyyyf, $mmf, $ddf, $hhf, $minf, $secf) = ($tf =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
             my ($yyyyl, $mml, $ddl, $hhl, $minl, $secl) = ($tl =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
             $tsum = (timelocal($secl, $minl, $hhl, $ddl, $mml-1, $yyyyl-1900))-(timelocal($secf, $minf, $hhf, $ddf, $mmf-1, $yyyyf-1900));          
         
             if ($IsTimeSet || $IsAggrSet) {
                 $sql = DbRep_createSelectSql($hash,"history",$selspec,$device,$reading,"'$runtime_string_first'","'$runtime_string_next'",$addon);
	         } else {
	             $sql = DbRep_createSelectSql($hash,"history",$selspec,$device,$reading,undef,undef,$addon); 
	         }
             Log3 ($name, 4, "DbRep $name - SQL execute: $sql"); 
             
             eval{ $sth = $dbh->prepare($sql);
                   $sth->execute();
                 };		         
             if ($@) {
                 $err = encode_base64($@,"");
                 Log3 ($name, 2, "DbRep $name - $@");
                 $dbh->disconnect;
                 return "$name|''|$device|$reading|''|$err|''";
             }         

             my @twm_array =  map { $_->[0]."_ESC_".$_->[1] } @{$sth->fetchall_arrayref()};
             
             foreach my $twmrow (@twm_array) {
                 ($tn,$val) = split("_ESC_",$twmrow);
				 $val = DbRep_numval ($val);    # nichtnumerische Zeichen eliminieren
                 my ($yyyyt1, $mmt1, $ddt1, $hht1, $mint1, $sect1) = ($tn =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
                 $tn = timelocal($sect1, $mint1, $hht1, $ddt1, $mmt1-1, $yyyyt1-1900);
                 if(!$to) {
                     $val1 = $val;
                     $to = $tn;
                     next;
                 }
                 $dt = $tn - $to;
                 $sum += $val1*($dt/$tsum);
                 $val1 = $val;
                 $to = $tn;
                 Log3 ($name, 5, "DbRep $name - data element: $twmrow");
                 Log3 ($name, 5, "DbRep $name - time sum: $tsum, delta time: $dt, value: $val1, twm: ".$val1*($dt/$tsum));                 
             }             
         }              
         if(AttrVal($name, "aggregation", "") eq "hour") {
             my @rsf = split(/[" "\|":"]/,$runtime_string_first);
             $arrstr .= $runtime_string."#".$sum."#".$rsf[0]."_".$rsf[1]."|";  
         } else {
             my @rsf = split(" ",$runtime_string_first);
             $arrstr .= $runtime_string."#".$sum."#".$rsf[0]."|"; 
         } 
     }
 }   
  
 $sth->finish;
 $dbh->disconnect;
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 # Ergebnisse in Datenbank schreiben
 my ($wrt,$irowdone);
 if($prop =~ /writeToDB/) {
     ($wrt,$irowdone,$err) = DbRep_OutputWriteToDB($name,$device,$reading,$arrstr,$qlf);
     if ($err) {
         Log3 $hash->{NAME}, 2, "DbRep $name - $err"; 
         $err = encode_base64($err,"");
         return "$name|''|$device|$reading|''|$err|''";
     }
     $rt = $rt+$wrt;
 }
  
 # Daten müssen als Einzeiler zurückgegeben werden
 $arrstr = encode_base64($arrstr,"");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$arrstr|$device|$reading|$rt|0|$irowdone";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage averageValue
####################################################################################################
sub averval_ParseDone($) {
  my ($string) = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $name       = $hash->{NAME};
  my $arrstr     = decode_base64($a[1]);
  my $device     = $a[2];
     $device     =~ s/[^A-Za-z\/\d_\.-]/\//g;
  my $reading    = $a[3];
     $reading    =~ s/[^A-Za-z\/\d_\.-]/\//g;
  my $bt         = $a[4];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[5]?decode_base64($a[5]):undef;
  my $irowdone   = $a[6];
  my $reading_runtime_string;
  
  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      return;
  }
  
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
  
  my $acf = AttrVal($name, "averageCalcForm", "avgArithmeticMean");
  if($acf eq "avgArithmeticMean") {
      $acf = "AM"
  } elsif ($acf eq "avgDailyMeanGWS") {
      $acf = "DMGWS";
  } elsif ($acf eq "avgTimeWeightMean") {
      $acf = "TWM";
  }
  
  # Readingaufbereitung
  readingsBeginUpdate($hash);
  
  my @arr = split("\\|", $arrstr);
  foreach my $row (@arr) {
      my @a                = split("#", $row);
      my $runtime_string   = $a[0];
      my $c                = $a[1];
      my $rsf              = $a[2]."__";
      
      if (AttrVal($hash->{NAME}, "readingNameMap", "")) {
          $reading_runtime_string = $rsf.AttrVal($hash->{NAME}, "readingNameMap", "")."__".$runtime_string;
      } else {
          my $ds   = $device."__" if ($device);
          my $rds  = $reading."__" if ($reading);
          $reading_runtime_string = $rsf.$ds.$rds."AVG".$acf."__".$runtime_string;
      }
      if($acf eq "DMGWS") {
	      ReadingsBulkUpdateValue ($hash, $reading_runtime_string, looks_like_number($c)?sprintf("%.1f",$c):$c);
      } else {
          ReadingsBulkUpdateValue ($hash, $reading_runtime_string, $c?sprintf("%.4f",$c):"-");
      }
  }

  ReadingsBulkUpdateValue ($hash, "db_lines_processed", $irowdone) if($hash->{LASTCMD} =~ /writeToDB/);
  ReadingsBulkUpdateTimeState($hash,$brt,$rt,"done");  
  readingsEndUpdate($hash, 1);
  
  delete($hash->{HELPER}{RUNNING_PID});
  
return;
}

####################################################################################################
# nichtblockierende DB-Abfrage count
####################################################################################################
sub count_DoParse($) {
 my ($string) = @_;
 my ($name,$table,$device,$reading,$ts) = split("\\§", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my ($dbh,$sql,$sth,$err,$selspec);

 # Background-Startzeit
 my $bst = [gettimeofday];
 
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|$device|$reading|''|$err|$table";
 }
     
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
 
 # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef) 
 my ($IsTimeSet,$IsAggrSet,$aggregation) = DbRep_checktimeaggr($hash); 
 Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");
  
 # Timestampstring to Array
 my @ts = split("\\|", $ts);
 Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts"); 
 
 # SQL-Startzeit
 my $st = [gettimeofday];
    
 # DB-Abfrage zeilenweise für jeden Timearray-Eintrag
 my $arrstr;
 foreach my $row (@ts) {
     my @a                     = split("#", $row);
     my $runtime_string        = $a[0];
     my $runtime_string_first  = $a[1];
     my $runtime_string_next   = $a[2];      

     if ($IsTimeSet || $IsAggrSet) {
         $sql = DbRep_createSelectSql($hash,$table,"COUNT(*)",$device,$reading,"'$runtime_string_first'","'$runtime_string_next'",'');
	 } else {
	     $sql = DbRep_createSelectSql($hash,$table,"COUNT(*)",$device,$reading,undef,undef,''); 
	 }
     Log3 ($name, 4, "DbRep $name - SQL execute: $sql");
     
     eval{ $sth = $dbh->prepare($sql);
           $sth->execute();
         };	
     if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         return "$name|''|$device|$reading|''|$err|$table";
     }
	 
	 # DB-Abfrage -> Ergebnis in @arr aufnehmen
     my @line = $sth->fetchrow_array();
     
     Log3 ($name, 5, "DbRep $name - SQL result: $line[0]") if($line[0]);   
	 
     if($aggregation eq "hour") {
         my @rsf = split(/[" "\|":"]/,$runtime_string_first);
         $arrstr .= $runtime_string."#".$line[0]."#".$rsf[0]."_".$rsf[1]."|";  
     } else {
         my @rsf = split(" ",$runtime_string_first);
         $arrstr .= $runtime_string."#".$line[0]."#".$rsf[0]."|"; 
     }
 }
 
 $sth->finish;
 $dbh->disconnect;
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 # Daten müssen als Einzeiler zurückgegeben werden
 $arrstr = encode_base64($arrstr,"");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$arrstr|$device|$reading|$rt|0|$table";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage count
####################################################################################################
sub count_ParseDone($) {
  my ($string) = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $name       = $hash->{NAME};
  my $arrstr     = decode_base64($a[1]);
  my $device     = $a[2];
     $device     =~ s/[^A-Za-z\/\d_\.-]/\//g;
  my $reading    = $a[3];
     $reading    =~ s/[^A-Za-z\/\d_\.-]/\//g;
  my $bt         = $a[4];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[5]?decode_base64($a[5]):undef;
  my $table      = $a[6];
  my $reading_runtime_string;
  
   if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      return;
  }
  
  Log3 ($name, 5, "DbRep $name - SQL result decoded: $arrstr") if($arrstr);
  
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
  
  # Readingaufbereitung
  readingsBeginUpdate($hash);
  
  my @arr = split("\\|", $arrstr);
  foreach my $row (@arr) {
      my @a                = split("#", $row);
      my $runtime_string   = $a[0];
      my $c                = $a[1];
      my $rsf              = $a[2]."__";
         
      if (AttrVal($hash->{NAME}, "readingNameMap", "")) {
          $reading_runtime_string = $rsf.AttrVal($hash->{NAME}, "readingNameMap", "")."__".$runtime_string;
      } else {
          my $ds  = $device."__" if ($device);
          my $rds = $reading."__" if ($reading);
          $reading_runtime_string = $rsf.$ds.$rds."COUNT_".$table."__".$runtime_string;
      }
         
	  ReadingsBulkUpdateValue ($hash, $reading_runtime_string, $c?$c:"-");
  }
  
  ReadingsBulkUpdateTimeState($hash,$brt,$rt,"done");
  readingsEndUpdate($hash, 1);
  
  delete($hash->{HELPER}{RUNNING_PID});
  
return;
}

####################################################################################################
# nichtblockierende DB-Abfrage maxValue
####################################################################################################
sub maxval_DoParse($) {
 my ($string) = @_;
 my ($name,$device,$reading,$prop,$ts) = split("\\§", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my ($dbh,$sql,$sth,$err);

 # Background-Startzeit
 my $bst = [gettimeofday];
  
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|$device|$reading|''|$err|''";
 }
     
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
 
 # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef) 
 my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash); 
 Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");
  
 # Timestampstring to Array
 my @ts = split("\\|", $ts);
 Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");   
 
 # SQL-Startzeit
 my $st = [gettimeofday];
 
 # DB-Abfrage zeilenweise für jeden Array-Eintrag
 my @row_array;
 foreach my $row (@ts) {
     my @a                     = split("#", $row);
     my $runtime_string        = $a[0];
     my $runtime_string_first  = $a[1];
     my $runtime_string_next   = $a[2];    
     
     $runtime_string = encode_base64($runtime_string,"");   
     
     if ($IsTimeSet || $IsAggrSet) {
         $sql = DbRep_createSelectSql($hash,"history","VALUE,TIMESTAMP",$device,$reading,"'$runtime_string_first'","'$runtime_string_next'","ORDER BY TIMESTAMP");
	 } else {
	     $sql = DbRep_createSelectSql($hash,"history","VALUE,TIMESTAMP",$device,$reading,undef,undef,"ORDER BY TIMESTAMP");	 
	 }
     Log3 ($name, 4, "DbRep $name - SQL execute: $sql");
     
     eval{ $sth = $dbh->prepare($sql);
           $sth->execute();
         };	
     if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         return "$name|''|$device|$reading|''|$err|''";
     } 
         
     my @array= map { $runtime_string." ".$_ -> [0]." ".$_ -> [1]."\n" } @{ $sth->fetchall_arrayref() };
         
     if(!@array) {
         if(AttrVal($name, "aggregation", "") eq "hour") {
             my @rsf = split(/[" "\|":"]/,$runtime_string_first);
             @array = ($runtime_string." "."0"." ".$rsf[0]."_".$rsf[1]."\n");
         } else {
             my @rsf = split(" ",$runtime_string_first);
             @array = ($runtime_string." "."0"." ".$rsf[0]."\n");
         }
     } 
     push(@row_array, @array);  
 }
  
 $sth->finish;
 $dbh->disconnect;
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
  
 Log3 ($name, 5, "DbRep $name -> raw data of row_array result:\n @row_array");
 
 #---------- Berechnung Ergebnishash maxValue ------------------------ 
 my $i = 1;
 my %rh = ();
 my ($lastruntimestring,$row_max_time,$max_value);
  
 foreach my $row (@row_array) {
     my @a = split("[ \t][ \t]*", $row);
     my $runtime_string = decode_base64($a[0]);
     $lastruntimestring = $runtime_string if ($i == 1);
     my $value          = $a[1];
     $a[-1]             =~ s/:/-/g if($a[-1]);          # substituieren unsupported characters -> siehe fhem.pl
     my $timestamp      = ($a[-1]&&$a[-2])?$a[-2]."_".$a[-1]:$a[-1];
      
     # Leerzeichen am Ende $timestamp entfernen
     $timestamp         =~ s/\s+$//g;
      
     # Test auf $value = "numeric"
     if (!looks_like_number($value)) {
         Log3 ($name, 2, "DbRep $name - ERROR - value isn't numeric in maxValue function. Faulty dataset was \nTIMESTAMP: $timestamp, DEVICE: $device, READING: $reading, VALUE: $value.");
         $err = encode_base64("Value isn't numeric. Faulty dataset was - TIMESTAMP: $timestamp, VALUE: $value", "");
         return "$name|''|$device|$reading|''|$err|''";
     }
      
     Log3 ($name, 5, "DbRep $name - Runtimestring: $runtime_string, DEVICE: $device, READING: $reading, TIMESTAMP: $timestamp, VALUE: $value");
            
     if ($runtime_string eq $lastruntimestring) {
         if (!defined($max_value) || $value >= $max_value) {
             $max_value    = $value;
             $row_max_time = $timestamp;
             $rh{$runtime_string} = $runtime_string."|".$max_value."|".$row_max_time;            
         }
     } else {
         # neuer Zeitabschnitt beginnt, ersten Value-Wert erfassen 
         $lastruntimestring = $runtime_string;
         undef $max_value;
         if (!defined($max_value) || $value >= $max_value) {
             $max_value    = $value;
             $row_max_time = $timestamp;
             $rh{$runtime_string} = $runtime_string."|".$max_value."|".$row_max_time; 
         }
     }
     $i++;
 }
 #---------------------------------------------------------------------------------------------
     
 Log3 ($name, 5, "DbRep $name - result of maxValue calculation before encoding:");
 foreach my $key (sort(keys(%rh))) {
     Log3 ($name, 5, "runtimestring Key: $key, value: ".$rh{$key}); 
 }
     
 # Ergebnishash als Einzeiler zurückgeben bzw. Übergabe Schreibroutine
 my $rows = join('§', %rh); 
 
 # Ergebnisse in Datenbank schreiben
 my ($wrt,$irowdone);
 if($prop =~ /writeToDB/) {
     ($wrt,$irowdone,$err) = DbRep_OutputWriteToDB($name,$device,$reading,$rows,"max");
     if ($err) {
         Log3 $hash->{NAME}, 2, "DbRep $name - $err"; 
         $err = encode_base64($err,"");
         return "$name|''|$device|$reading|''|$err|''";
     }
     $rt = $rt+$wrt;
 }
 
 my $rowlist = encode_base64($rows,"");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$rowlist|$device|$reading|$rt|0|$irowdone";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage maxValue
####################################################################################################
sub maxval_ParseDone($) {
  my ($string) = @_;
  my @a = split("\\|",$string);
  my $hash      = $defs{$a[0]};
  my $name      = $hash->{NAME};
  my $rowlist   = decode_base64($a[1]);
  my $device    = $a[2];
     $device    =~ s/[^A-Za-z\/\d_\.-]/\//g;
  my $reading   = $a[3];
     $reading   =~ s/[^A-Za-z\/\d_\.-]/\//g;
  my $bt        = $a[4];
  my ($rt,$brt) = split(",", $bt);
  my $err       = $a[5]?decode_base64($a[5]):undef;
  my $irowdone  = $a[6];
  my $reading_runtime_string;
  
  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      return;
  }
  
  my %rh = split("§", $rowlist);
 
  Log3 ($name, 5, "DbRep $name - result of maxValue calculation after decoding:");
  foreach my $key (sort(keys(%rh))) {
      Log3 ($name, 5, "DbRep $name - runtimestring Key: $key, value: ".$rh{$key}); 
  }
  
  # Readingaufbereitung
  readingsBeginUpdate($hash);
  
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
 
  foreach my $key (sort(keys(%rh))) {
      my @k = split("\\|",$rh{$key});
      my $rsf  = $k[2]."__" if($k[2]);
      
      if (AttrVal($hash->{NAME}, "readingNameMap", "")) {
          $reading_runtime_string = $rsf.AttrVal($hash->{NAME}, "readingNameMap", "")."__".$k[0];
      } else {
          my $ds   = $device."__" if ($device);
          my $rds  = $reading."__" if ($reading);
          $reading_runtime_string = $rsf.$ds.$rds."MAX__".$k[0];
      }
      my $rv = $k[1];

      ReadingsBulkUpdateValue ($hash, $reading_runtime_string, defined($rv)?sprintf("%.4f",$rv):"-");
  }
  
  ReadingsBulkUpdateValue ($hash, "db_lines_processed", $irowdone) if($hash->{LASTCMD} =~ /writeToDB/);
  ReadingsBulkUpdateTimeState($hash,$brt,$rt,"done");
  readingsEndUpdate($hash, 1);

  delete($hash->{HELPER}{RUNNING_PID});
  
return;
}

####################################################################################################
# nichtblockierende DB-Abfrage minValue
####################################################################################################
sub minval_DoParse($) {
 my ($string) = @_;
 my ($name,$device,$reading,$prop,$ts) = split("\\§", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my ($dbh,$sql,$sth,$err);

 # Background-Startzeit
 my $bst = [gettimeofday];
  
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|$device|$reading|''|$err|''";
 }
     
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
  
 # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef) 
 my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash); 
 Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");
 
 # Timestampstring to Array
 my @ts = split("\\|", $ts);
 Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");   
 
 # SQL-Startzeit
 my $st = [gettimeofday];
 
 # DB-Abfrage zeilenweise für jeden Array-Eintrag
 my @row_array;
 foreach my $row (@ts) {
     my @a                     = split("#", $row);
     my $runtime_string        = $a[0];
     my $runtime_string_first  = $a[1];
     my $runtime_string_next   = $a[2];   
     
     $runtime_string = encode_base64($runtime_string,"");
     
     if ($IsTimeSet || $IsAggrSet) {
         $sql = DbRep_createSelectSql($hash,"history","VALUE,TIMESTAMP",$device,$reading,"'$runtime_string_first'","'$runtime_string_next'","ORDER BY TIMESTAMP"); 
	 } else {
	     $sql = DbRep_createSelectSql($hash,"history","VALUE,TIMESTAMP",$device,$reading,undef,undef,"ORDER BY TIMESTAMP");	 
	 }
     Log3 ($name, 4, "DbRep $name - SQL execute: $sql");
     
     eval{ $sth = $dbh->prepare($sql);
           $sth->execute();
         };	
     if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         return "$name|''|$device|$reading|''|$err|''";
     } 
         
     my @array= map { $runtime_string." ".$_ -> [0]." ".$_ -> [1]."\n" } @{ $sth->fetchall_arrayref() };
         
     if(!@array) {
         if(AttrVal($name, "aggregation", "") eq "hour") {
             my @rsf = split(/[" "\|":"]/,$runtime_string_first);
             @array = ($runtime_string." "."0"." ".$rsf[0]."_".$rsf[1]."\n");
         } else {
             my @rsf = split(" ",$runtime_string_first);
             @array = ($runtime_string." "."0"." ".$rsf[0]."\n");
         }
     }      
     push(@row_array, @array);  
 }

 $sth->finish;
 $dbh->disconnect;
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
  
 Log3 ($name, 5, "DbRep $name -> raw data of row_array result:\n @row_array");
 
 #---------- Berechnung Ergebnishash minValue ------------------------ 
 my $i = 1;
 my %rh = ();
 my $lastruntimestring;
 my $row_min_time; 
 my ($min_value,$value);
  
 foreach my $row (@row_array) {
     my @a = split("[ \t][ \t]*", $row);
     my $runtime_string = decode_base64($a[0]);
     $lastruntimestring = $runtime_string if ($i == 1);
     $value             = $a[1];
     $min_value         = $a[1] if ($i == 1);
     $a[-1]             =~ s/:/-/g if($a[-1]);          # substituieren unsupported characters -> siehe fhem.pl
     my $timestamp      = ($a[-1]&&$a[-2])?$a[-2]."_".$a[-1]:$a[-1];
      
     # Leerzeichen am Ende $timestamp entfernen
     $timestamp         =~ s/\s+$//g;
      
     # Test auf $value = "numeric"
     if (!looks_like_number($value)) {
         # $a[-1] =~ s/\s+$//g;
         Log3 ($name, 2, "DbRep $name - ERROR - value isn't numeric in minValue function. Faulty dataset was \nTIMESTAMP: $timestamp, DEVICE: $device, READING: $reading, VALUE: $value.");
         $err = encode_base64("Value isn't numeric. Faulty dataset was - TIMESTAMP: $timestamp, VALUE: $value", "");
         return "$name|''|$device|$reading|''|$err|''";
     }
      
     Log3 ($name, 5, "DbRep $name - Runtimestring: $runtime_string, DEVICE: $device, READING: $reading, TIMESTAMP: $timestamp, VALUE: $value");
      
     $rh{$runtime_string} = $runtime_string."|".$min_value."|".$timestamp if ($i == 1);  # minValue des ersten SQL-Statements in hash einfügen
      
     if ($runtime_string eq $lastruntimestring) {
         if (!defined($min_value) || $value < $min_value) {
             $min_value    = $value;
             $row_min_time = $timestamp;
             $rh{$runtime_string} = $runtime_string."|".$min_value."|".$row_min_time;            
         }
     } else {
         # neuer Zeitabschnitt beginnt, ersten Value-Wert erfassen 
         $lastruntimestring = $runtime_string;
         $min_value         = $value;
         $row_min_time      = $timestamp;
         $rh{$runtime_string} = $runtime_string."|".$min_value."|".$row_min_time; 
     }
     $i++;
 }
 #---------------------------------------------------------------------------------------------
     
 Log3 ($name, 5, "DbRep $name - result of minValue calculation before encoding:");
 foreach my $key (sort(keys(%rh))) {
     Log3 ($name, 5, "runtimestring Key: $key, value: ".$rh{$key}); 
 }
     
 # Ergebnishash als Einzeiler zurückgeben bzw. an Schreibroutine übergeben
 my $rows = join('§', %rh); 
 
 # Ergebnisse in Datenbank schreiben
 my ($wrt,$irowdone);
 if($prop =~ /writeToDB/) {
     ($wrt,$irowdone,$err) = DbRep_OutputWriteToDB($name,$device,$reading,$rows,"min");
     if ($err) {
         Log3 $hash->{NAME}, 2, "DbRep $name - $err"; 
         $err = encode_base64($err,"");
         return "$name|''|$device|$reading|''|$err|''";
     }
     $rt = $rt+$wrt;
 }
 
 my $rowlist = encode_base64($rows,"");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$rowlist|$device|$reading|$rt|0|$irowdone";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage minValue
####################################################################################################
sub minval_ParseDone($) {
  my ($string) = @_;
  my @a = split("\\|",$string);
  my $hash = $defs{$a[0]};
  my $name = $hash->{NAME};
  my $rowlist   = decode_base64($a[1]);
  my $device    = $a[2];
     $device    =~ s/[^A-Za-z\/\d_\.-]/\//g;
  my $reading   = $a[3];
     $reading   =~ s/[^A-Za-z\/\d_\.-]/\//g;
  my $bt        = $a[4];
  my ($rt,$brt) = split(",", $bt);
  my $err       = $a[5]?decode_base64($a[5]):undef;
  my $irowdone  = $a[6];
  my $reading_runtime_string;
  
  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      return;
  }
  
  my %rh = split("§", $rowlist);
 
  Log3 ($name, 5, "DbRep $name - result of minValue calculation after decoding:");
  foreach my $key (sort(keys(%rh))) {
      Log3 ($name, 5, "DbRep $name - runtimestring Key: $key, value: ".$rh{$key}); 
  }
  
  # Readingaufbereitung
  readingsBeginUpdate($hash);
  
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
 
  foreach my $key (sort(keys(%rh))) {
      my @k = split("\\|",$rh{$key});
      my $rsf  = $k[2]."__" if($k[2]);
      
      if (AttrVal($hash->{NAME}, "readingNameMap", "")) {
          $reading_runtime_string = $rsf.AttrVal($hash->{NAME}, "readingNameMap", "")."__".$k[0];
      } else {
          my $ds   = $device."__" if ($device);
          my $rds  = $reading."__" if ($reading);
          $reading_runtime_string = $rsf.$ds.$rds."MIN__".$k[0];
      }
      my $rv = $k[1];
	  
      ReadingsBulkUpdateValue ($hash, $reading_runtime_string, defined($rv)?sprintf("%.4f",$rv):"-");
  }
  
  ReadingsBulkUpdateValue ($hash, "db_lines_processed", $irowdone) if($hash->{LASTCMD} =~ /writeToDB/);
  ReadingsBulkUpdateTimeState($hash,$brt,$rt,"done");
  readingsEndUpdate($hash, 1);

  delete($hash->{HELPER}{RUNNING_PID});
  
return;
}

####################################################################################################
# nichtblockierende DB-Abfrage diffValue
####################################################################################################
sub diffval_DoParse($) {
 my ($string) = @_;
 my ($name,$device,$reading,$prop,$ts) = split("\\§", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbmodel    = $dbloghash->{MODEL};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my ($dbh,$sql,$sth,$err,$selspec);

 # Background-Startzeit
 my $bst = [gettimeofday];
  
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|$device|$reading|''|''|''|$err|''";
 }
     
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
  
 # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef) 
 my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash); 
 Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");
 
 # Timestampstring to Array
 my @ts = split("\\|", $ts);
 Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");  
 
 #vorbereiten der DB-Abfrage, DB-Modell-abhaengig
 if($dbmodel eq "MYSQL") {
     $selspec = "TIMESTAMP,VALUE, if(VALUE-\@V < 0 OR \@RB = 1 , \@diff:= 0, \@diff:= VALUE-\@V ) as DIFF, \@V:= VALUE as VALUEBEFORE, \@RB:= '0' as RBIT ";
 } else {
     $selspec = "TIMESTAMP,VALUE";
 }
 
 # SQL-Startzeit
 my $st = [gettimeofday];
 
 # DB-Abfrage zeilenweise für jeden Array-Eintrag
 my @row_array;
 my @array;

 foreach my $row (@ts) {
     my @a                     = split("#", $row);
     my $runtime_string        = $a[0];
     my $runtime_string_first  = $a[1];
     my $runtime_string_next   = $a[2];  
     $runtime_string           = encode_base64($runtime_string,""); 
     
	 if($dbmodel eq "MYSQL") {
	     eval {$dbh->do("set \@V:= 0, \@diff:= 0, \@diffTotal:= 0, \@RB:= 1;");};   # @\RB = Resetbit wenn neues Selektionsintervall beginnt
     }
	 if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         return "$name|''|$device|$reading|''|''|''|$err|''";
     }
	 
     if ($IsTimeSet || $IsAggrSet) {
         $sql = DbRep_createSelectSql($hash,"history",$selspec,$device,$reading,"'$runtime_string_first'","'$runtime_string_next'",'');
	 } else {
	     $sql = DbRep_createSelectSql($hash,"history",$selspec,$device,$reading,undef,undef,''); 
	 }
     Log3 ($name, 4, "DbRep $name - SQL execute: $sql");
     
     eval{ $sth = $dbh->prepare($sql);
           $sth->execute();
         };	
     if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         return "$name|''|$device|$reading|''|''|''|$err|''";
     
	 } else {
		 if($dbmodel eq "MYSQL") {
		     @array = map { $runtime_string." ".$_ -> [0]." ".$_ -> [1]." ".$_ -> [2]."\n" } @{ $sth->fetchall_arrayref() };
         } else {
		     @array = map { $runtime_string." ".$_ -> [0]." ".$_ -> [1]."\n" } @{ $sth->fetchall_arrayref() };	
   
			 if (@array) {
			     my @sp;
			     my $dse = 0;
				 my $vold;
			     my @sqlite_array;
                 foreach my $row (@array) {
                     @sp = split("[ \t][ \t]*", $row, 4);
                     my $runtime_string = $sp[0]; 
                     my $timestamp      = $sp[2]?$sp[1]." ".$sp[2]:$sp[1];				 
                     my $vnew           = $sp[3];
                     $vnew              =~ tr/\n//d;				 
                     
					 $dse = ($vold && (($vnew-$vold) > 0))?($vnew-$vold):0;
				     @sp = $runtime_string." ".$timestamp." ".$vnew." ".$dse."\n";
					 $vold = $vnew;
                     push(@sqlite_array, @sp);
                 }
			     @array = @sqlite_array;
	         }
		 }
		 
         if(!@array) {
             if(AttrVal($name, "aggregation", "") eq "hour") {
                 my @rsf = split(/[" "\|":"]/,$runtime_string_first);
                 @array = ($runtime_string." ".$rsf[0]."_".$rsf[1]."\n");
             } else {
                 my @rsf = split(" ",$runtime_string_first);
                 @array = ($runtime_string." ".$rsf[0]."\n");
             }
         }
         push(@row_array, @array);
     }  
 }
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);

 $dbh->disconnect;
  
 Log3 ($name, 5, "DbRep $name - raw data of row_array result:\n @row_array");
 
 my $difflimit = AttrVal($name, "diffAccept", "20");   # legt fest, bis zu welchem Wert Differenzen akzeptiert werden (Ausreißer eliminieren)
 
  # Berechnung diffValue aus Selektionshash
  my %rh = ();                    # Ergebnishash, wird alle Ergebniszeilen enthalten
  my %ch = ();                    # counthash, enthält die Anzahl der verarbeiteten Datasets pro runtime_string
  my $lastruntimestring;
  my $i = 1;
  my $lval;                       # immer der letzte Wert von $value
  my $rslval;                     # runtimestring von lval
  my $uediff;                     # Übertragsdifferenz (Differenz zwischen letzten Wert einer Aggregationsperiode und dem ersten Wert der Folgeperiode)
  my $diff_current;               # Differenzwert des aktuellen Datasets 
  my $diff_before;                # Differenzwert vorheriger Datensatz
  my $rejectstr;                  # String der ignorierten Differenzsätze
  my $diff_total;                 # Summenwert aller berücksichtigten Teildifferenzen
  my $max = ($#row_array)+1;      # Anzahl aller Listenelemente

  Log3 ($name, 5, "DbRep $name - data of row_array result assigned to fields:\n");
    
  foreach my $row (@row_array) {
      my @a = split("[ \t][ \t]*", $row, 6);
      my $runtime_string = decode_base64($a[0]);
      $lastruntimestring = $runtime_string if ($i == 1);
      my $timestamp      = $a[2]?$a[1]."_".$a[2]:$a[1];
      my $value          = $a[3]?$a[3]:0;  
      my $diff           = $a[4]?sprintf("%.4f",$a[4]):0;   

#      if ($uediff)	  {
#	      $diff = $diff + $uediff;
#		  Log3 ($name, 4, "DbRep $name - balance difference of $uediff between $rslval and $runtime_string");
#		  $uediff = 0;
#	  } 
      
      # Leerzeichen am Ende $timestamp entfernen
      $timestamp         =~ s/\s+$//g;
      
      # Test auf $value = "numeric"
      if (!looks_like_number($value)) {
          $a[3] =~ s/\s+$//g;
          Log3 ($name, 2, "DbRep $name - ERROR - value isn't numeric in diffValue function. Faulty dataset was \nTIMESTAMP: $timestamp, DEVICE: $device, READING: $reading, VALUE: $value.");
          $err = encode_base64("Value isn't numeric. Faulty dataset was - TIMESTAMP: $timestamp, VALUE: $value", "");
          return "$name|''|$device|$reading|''|''|''|$err|''";
      }

      Log3 ($name, 5, "DbRep $name - Runtimestring: $runtime_string, DEVICE: $device, READING: $reading, \nTIMESTAMP: $timestamp, VALUE: $value, DIFF: $diff");
      
	  # String ignorierter Zeilen erzeugen 
	  $diff_current = $timestamp." ".$diff;
	  if($diff > $difflimit) {
	      $rejectstr .= $diff_before." -> ".$diff_current."\n";
	  }
	  $diff_before = $diff_current;
	  
	  # Ergebnishash erzeugen
      if ($runtime_string eq $lastruntimestring) {
          if ($i == 1) {
			  $diff_total = $diff?$diff:0 if($diff <= $difflimit);
              $rh{$runtime_string} = $runtime_string."|".$diff_total."|".$timestamp; 	
              $ch{$runtime_string} = 1 if($value);
              $lval = $value;
              $rslval = $runtime_string;			  
          }
          
          if ($diff) {
		      if($diff <= $difflimit) {
                  $diff_total = $diff_total+$diff;
			  }
              $rh{$runtime_string} = $runtime_string."|".$diff_total."|".$timestamp;
              $ch{$runtime_string}++ if($value && $i > 1);
              $lval = $value;
              $rslval = $runtime_string;			  
          }
      } else {
          # neuer Zeitabschnitt beginnt, ersten Value-Wert erfassen und Übertragsdifferenz bilden
          $lastruntimestring = $runtime_string;
          $i  = 1;
		  
		  $uediff = $value - $lval if($value > $lval);
          $diff = $uediff;
          $lval = $value if($value);	# Übetrag über Perioden mit value = 0 hinweg !
          $rslval = $runtime_string;
		  Log3 ($name, 4, "DbRep $name - balance difference of $uediff between $rslval and $runtime_string");
		  
		  
          $diff_total = $diff?$diff:0 if($diff <= $difflimit);
          $rh{$runtime_string} = $runtime_string."|".$diff_total."|".$timestamp;
          $ch{$runtime_string} = 1 if($value);	

          $uediff = 0;		  
      } 
      $i++;
  }
  
 Log3 ($name, 4, "DbRep $name - result of diffValue calculation before encoding:");
 foreach my $key (sort(keys(%rh))) {
     Log3 ($name, 4, "runtimestring Key: $key, value: ".$rh{$key}); 
 }
 
 my $ncp = DbRep_calcount($hash,\%ch);
 
 my ($ncps,$ncpslist);
 if(%$ncp) {
     Log3 ($name, 3, "DbRep $name - time/aggregation periods containing only one dataset -> no diffValue calc was possible in period:");
     foreach my $key (sort(keys%{$ncp})) {
         Log3 ($name, 3, $key) ;
     }
 $ncps = join('§', %$ncp);	
 $ncpslist = encode_base64($ncps,""); 
 }
  
 # Ergebnishash als Einzeiler zurückgeben
 # ignorierte Zeilen ($diff > $difflimit)
 my $rowsrej = encode_base64($rejectstr,"") if($rejectstr);
 
 # Ergebnishash  
 my $rows = join('§', %rh);

 # Ergebnisse in Datenbank schreiben
 my ($wrt,$irowdone);
 if($prop =~ /writeToDB/) {
     ($wrt,$irowdone,$err) = DbRep_OutputWriteToDB($name,$device,$reading,$rows,"diff");
     if ($err) {
         Log3 $hash->{NAME}, 2, "DbRep $name - $err"; 
         $err = encode_base64($err,"");
         return "$name|''|$device|$reading|''|''|''|$err|''";
     }
     $rt = $rt+$wrt;
 }
 
 my $rowlist = encode_base64($rows,"");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);
 
 $rt = $rt.",".$brt;
 
 return "$name|$rowlist|$device|$reading|$rt|$rowsrej|$ncpslist|0|$irowdone";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage diffValue
####################################################################################################
sub diffval_ParseDone($) {
  my ($string) = @_;
  my @a = split("\\|",$string);
  my $hash = $defs{$a[0]};
  my $name = $hash->{NAME};
  my $rowlist    = decode_base64($a[1]);
  my $device     = $a[2];
     $device     =~ s/[^A-Za-z\/\d_\.-]/\//g;
  my $reading    = $a[3];
     $reading    =~ s/[^A-Za-z\/\d_\.-]/\//g;
  my $bt         = $a[4];
  my ($rt,$brt)  = split(",", $bt);
  my $rowsrej    = $a[5]?decode_base64($a[5]):undef;     # String von Datensätzen die nicht berücksichtigt wurden (diff Schwellenwert Überschreitung)
  my $ncpslist   = decode_base64($a[6]);                 # Hash von Perioden die nicht kalkuliert werden konnten "no calc in period" 
  my $err        = $a[7]?decode_base64($a[7]):undef;
  my $irowdone   = $a[8];
  my $reading_runtime_string;
  my $difflimit  = AttrVal($name, "diffAccept", "20");   # legt fest, bis zu welchem Wert Differenzen akzeptoert werden (Ausreißer eliminieren)AttrVal($name, "diffAccept", "20");
  
   if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      return;
  }

 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
 
 # Auswertung hashes für state-Warning
 $rowsrej =~ s/_/ /g;
 Log3 ($name, 3, "DbRep $name -> data ignored while calc diffValue due to threshold overrun (diffAccept = $difflimit): \n$rowsrej")
          if($rowsrej);
 $rowsrej =~ s/\n/ \|\| /g;
 
 my %ncp    = split("§", $ncpslist);
 my $ncpstr;
 if(%ncp) {
     foreach my $ncpkey (sort(keys(%ncp))) {
         $ncpstr .= $ncpkey." || ";    
     }
 }
 
 # Readingaufbereitung
 my %rh = split("§", $rowlist);
 
 Log3 ($name, 4, "DbRep $name - result of diffValue calculation after decoding:");
 foreach my $key (sort(keys(%rh))) {
     Log3 ($name, 4, "DbRep $name - runtimestring Key: $key, value: ".$rh{$key}); 
 }
  
 readingsBeginUpdate($hash);
 
  foreach my $key (sort(keys(%rh))) {
      my @k    = split("\\|",$rh{$key});
      my $rts  = $k[2]."__";
	  $rts     =~ s/:/-/g;      # substituieren unsupported characters -> siehe fhem.pl
  
      if (AttrVal($hash->{NAME}, "readingNameMap", "")) {
          $reading_runtime_string = $rts.AttrVal($hash->{NAME}, "readingNameMap", "")."__".$k[0];
      } else {
          my $ds   = $device."__" if ($device);
          my $rds  = $reading."__" if ($reading);                                   
          $reading_runtime_string = $rts.$ds.$rds."DIFF__".$k[0];
      }
      my $rv = $k[1];

      ReadingsBulkUpdateValue ($hash, $reading_runtime_string, $rv?sprintf("%.4f",$rv):"-");
    
  }

  ReadingsBulkUpdateValue ($hash, "db_lines_processed", $irowdone) if($hash->{LASTCMD} =~ /writeToDB/);
  ReadingsBulkUpdateValue ($hash, "diff_overrun_limit_".$difflimit, $rowsrej) if($rowsrej);
  ReadingsBulkUpdateValue ($hash, "less_data_in_period", $ncpstr) if($ncpstr);
  ReadingsBulkUpdateTimeState($hash,$brt,$rt,($ncpstr||$rowsrej)?"Warning":"done");
  
  readingsEndUpdate($hash, 1);

  delete($hash->{HELPER}{RUNNING_PID});
  
return;
}

####################################################################################################
# nichtblockierende DB-Abfrage sumValue
####################################################################################################
sub sumval_DoParse($) {
 my ($string) = @_;
 my ($name,$device,$reading,$prop,$ts) = split("\\§", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my ($dbh,$sql,$sth,$err,$selspec);

 # Background-Startzeit
 my $bst = [gettimeofday];
 
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|$device|$reading|''|$err|''";
 }
     
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
  
 # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef) 
 my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash); 
 Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet"); 
 
 # Timestampstring to Array
 my @ts = split("\\|", $ts);
 Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts"); 
 
 #vorbereiten der DB-Abfrage, DB-Modell-abhaengig
 if ($dbloghash->{MODEL} eq "POSTGRESQL") {
     $selspec = "SUM(VALUE::numeric)";
 } elsif ($dbloghash->{MODEL} eq "MYSQL") {
     $selspec = "SUM(VALUE)";
 } elsif ($dbloghash->{MODEL} eq "SQLITE") {
     $selspec = "SUM(VALUE)";
 } else {
     $selspec = "SUM(VALUE)";
 }
	
 # SQL-Startzeit
 my $st = [gettimeofday];  

 # DB-Abfrage zeilenweise für jeden Array-Eintrag
 my $arrstr;
 foreach my $row (@ts) {
     my @a                     = split("#", $row);
     my $runtime_string        = $a[0];
     my $runtime_string_first  = $a[1];
     my $runtime_string_next   = $a[2];       
     
     if ($IsTimeSet || $IsAggrSet) {
         $sql = DbRep_createSelectSql($hash,"history",$selspec,$device,$reading,"'$runtime_string_first'","'$runtime_string_next'",'');
	 } else {
         $sql = DbRep_createSelectSql($hash,"history",$selspec,$device,$reading,undef,undef,'');
	 }
     Log3 ($name, 4, "DbRep $name - SQL execute: $sql");
     
     eval{ $sth = $dbh->prepare($sql);
           $sth->execute();
         };	
	 if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         return "$name|''|$device|$reading|''|$err|''";
     }
	 
     # DB-Abfrage -> Ergebnis in @arr aufnehmen
     my @line = $sth->fetchrow_array();
     
     Log3 ($name, 5, "DbRep $name - SQL result: $line[0]") if($line[0]);     
	 
     if(AttrVal($name, "aggregation", "") eq "hour") {
         my @rsf = split(/[" "\|":"]/,$runtime_string_first);
         $arrstr .= $runtime_string."#".$line[0]."#".$rsf[0]."_".$rsf[1]."|";  
     } else {
         my @rsf = split(" ",$runtime_string_first);
         $arrstr .= $runtime_string."#".$line[0]."#".$rsf[0]."|"; 
     }
 }

 $sth->finish;
 $dbh->disconnect;
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 # Ergebnisse in Datenbank schreiben
 my ($wrt,$irowdone);
 if($prop =~ /writeToDB/) {
     ($wrt,$irowdone,$err) = DbRep_OutputWriteToDB($name,$device,$reading,$arrstr,"sum");
     if ($err) {
         Log3 $hash->{NAME}, 2, "DbRep $name - $err"; 
         $err = encode_base64($err,"");
         return "$name|''|$device|$reading|''|$err|''";
     }
     $rt = $rt+$wrt;
 }
  
 # Daten müssen als Einzeiler zurückgegeben werden
 $arrstr = encode_base64($arrstr,"");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$arrstr|$device|$reading|$rt|0|$irowdone";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage sumValue
####################################################################################################
sub sumval_ParseDone($) {
  my ($string) = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $name       = $hash->{NAME};
  my $arrstr     = decode_base64($a[1]);
  my $device     = $a[2];
     $device     =~ s/[^A-Za-z\/\d_\.-]/\//g;
  my $reading    = $a[3];
     $reading    =~ s/[^A-Za-z\/\d_\.-]/\//g;
  my $bt         = $a[4];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[5]?decode_base64($a[5]):undef;
  my $irowdone   = $a[6];
  my $reading_runtime_string;
  
   if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      return;
  }
  
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
  
  # Readingaufbereitung
  readingsBeginUpdate($hash);

  my @arr = split("\\|", $arrstr);
  foreach my $row (@arr) {
      my @a                = split("#", $row);
      my $runtime_string   = $a[0];
      my $c                = $a[1];
      my $rsf              = $a[2]."__";
      
      if (AttrVal($hash->{NAME}, "readingNameMap", "")) {
          $reading_runtime_string = $rsf.AttrVal($hash->{NAME}, "readingNameMap", "")."__".$runtime_string;
      } else {
          my $ds   = $device."__" if ($device);
          my $rds  = $reading."__" if ($reading);
          $reading_runtime_string = $rsf.$ds.$rds."SUM__".$runtime_string;
      }
         
	  ReadingsBulkUpdateValue ($hash, $reading_runtime_string, $c?sprintf("%.4f",$c):"-");
  }
  
  ReadingsBulkUpdateValue ($hash, "db_lines_processed", $irowdone) if($hash->{LASTCMD} =~ /writeToDB/);
  ReadingsBulkUpdateTimeState($hash,$brt,$rt,"done");
  readingsEndUpdate($hash, 1);
  
  delete($hash->{HELPER}{RUNNING_PID});  
  
return;
}

####################################################################################################
# nichtblockierendes DB delete
####################################################################################################
sub del_DoParse($) {
 my ($string) = @_;
 my ($name,$table,$device,$reading,$runtime_string_first,$runtime_string_next) = split("\\|", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my ($dbh,$sql,$sth,$err,$rows);
 
 # Background-Startzeit
 my $bst = [gettimeofday];
 
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|''|$err|''|''|''";
 }
 
 # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef) 
 my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash); 
 Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");
 
 # SQL zusammenstellen für DB-Operation
 if ($IsTimeSet || $IsAggrSet) {
     $sql = DbRep_createDeleteSql($hash,$table,$device,$reading,$runtime_string_first,$runtime_string_next,''); 
 } else {
     $sql = DbRep_createDeleteSql($hash,$table,$device,$reading,undef,undef,''); 
 }

 $sth = $dbh->prepare($sql); 
     
 Log3 ($name, 4, "DbRep $name - SQL execute: $sql");        
 
 # SQL-Startzeit
 my $st = [gettimeofday];
 
 eval {$sth->execute();};
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     $dbh->disconnect;
     return "$name|''|''|$err|''|''|''";
 } 
     
 $rows = $sth->rows;
 $dbh->commit() if(!$dbh->{AutoCommit});
 $dbh->disconnect;

 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 Log3 ($name, 5, "DbRep $name - Number of deleted rows: $rows");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$rows|$rt|0|$table|$device|$reading";
}

####################################################################################################
# Auswertungsroutine DB delete
####################################################################################################
sub del_ParseDone($) {
  my ($string) = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $name       = $hash->{NAME};
  my $rows       = $a[1];
  my $bt         = $a[2];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[3]?decode_base64($a[3]):undef;
  my $table      = $a[4];
  my $device     = $a[5];
     $device     =~ s/[^A-Za-z\/\d_\.-]/\//g; 
  my $reading    = $a[6];
     $reading    =~ s/[^A-Za-z\/\d_\.-]/\//g; 
  
   if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      return;
  }
 
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
  
  my ($reading_runtime_string, $ds, $rds);
  if (AttrVal($hash->{NAME}, "readingNameMap", "")) {
      $reading_runtime_string = AttrVal($hash->{NAME}, "readingNameMap", "")."--DELETED_ROWS--";
  } else {
      $ds   = $device."--" if ($device && $table ne "current");
      $rds  = $reading."--" if ($reading && $table ne "current");
      $reading_runtime_string = $ds.$rds."--DELETED_ROWS_".uc($table)."--";
  }
  
  readingsBeginUpdate($hash);

  ReadingsBulkUpdateValue ($hash, $reading_runtime_string, $rows);
         
  $rows = ($table eq "current")?$rows:$ds.$rds.$rows;
  Log3 ($name, 3, "DbRep $name - Entries of $hash->{DATABASE}.$table deleted: $rows");  
  
  ReadingsBulkUpdateTimeState($hash,$brt,$rt,"done");
  
  readingsEndUpdate($hash, 1);

  delete($hash->{HELPER}{RUNNING_PID});
  
return;
}

####################################################################################################
# nichtblockierendes DB insert
####################################################################################################
sub insert_Push($) {
 my ($name)     = @_;
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $utf8       = defined($hash->{UTF8})?$hash->{UTF8}:0;
 my ($err,$sth);
 
 # Background-Startzeit
 my $bst = [gettimeofday];
 
 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1, AutoInactiveDestroy => 1, mysql_enable_utf8 => $utf8 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|''|$err";
 }
 
 # check ob PK verwendet wird, @usepkx?Anzahl der Felder im PK:0 wenn kein PK, $pkx?Namen der Felder:none wenn kein PK 
 my ($usepkh,$usepkc,$pkh,$pkc) = DbRep_checkUsePK($hash,$dbloghash,$dbh);
  
 my $i_timestamp = $hash->{HELPER}{I_TIMESTAMP};
 my $i_device    = $hash->{HELPER}{I_DEVICE};
 my $i_type      = $hash->{HELPER}{I_TYPE};
 my $i_event     = $hash->{HELPER}{I_EVENT};
 my $i_reading   = $hash->{HELPER}{I_READING};
 my $i_value     = $hash->{HELPER}{I_VALUE};
 my $i_unit      = $hash->{HELPER}{I_UNIT} ? $hash->{HELPER}{I_UNIT} : " "; 
 
 # SQL zusammenstellen für DB-Operation
 Log3 ($name, 5, "DbRep $name -> data to insert Timestamp: $i_timestamp, Device: $i_device, Type: $i_type, Event: $i_event, Reading: $i_reading, Value: $i_value, Unit: $i_unit");     
 
 # SQL-Startzeit
 my $st = [gettimeofday];

 # insert history mit/ohne primary key
 if ($usepkh && $dbloghash->{MODEL} eq 'MYSQL') {
     eval { $sth = $dbh->prepare("INSERT IGNORE INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
 } elsif ($usepkh && $dbloghash->{MODEL} eq 'SQLITE') {
     eval { $sth = $dbh->prepare("INSERT OR IGNORE INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
 } elsif ($usepkh && $dbloghash->{MODEL} eq 'POSTGRESQL') {
     eval { $sth = $dbh->prepare("INSERT INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"); };
 } else {
     eval { $sth = $dbh->prepare("INSERT INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
 }
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
	 $dbh->disconnect();
     return "$name|''|''|$err";
 }
 
 $dbh->begin_work();
  
 eval {$sth->execute($i_timestamp, $i_device, $i_type, $i_event, $i_reading, $i_value, $i_unit);};
 
 my $irow;
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - Insert new dataset into database failed".($usepkh?" (possible PK violation) ":": ")."$@");
     $dbh->rollback();
     $dbh->disconnect();
     return "$name|''|''|$err";
 } else {
     $dbh->commit();
     $irow = $sth->rows;
     $dbh->disconnect();
 } 

 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$irow|$rt|0";
}

####################################################################################################
# Auswertungsroutine DB insert
####################################################################################################
sub insert_Done($) {
  my ($string) = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $name       = $hash->{NAME};
  my $irow       = $a[1];
  my $bt         = $a[2];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[3]?decode_base64($a[3]):undef;
  
  my $i_timestamp = delete $hash->{HELPER}{I_TIMESTAMP};
  my $i_device    = delete $hash->{HELPER}{I_DEVICE};
  my $i_type      = delete $hash->{HELPER}{I_TYPE};
  my $i_event     = delete $hash->{HELPER}{I_EVENT};
  my $i_reading   = delete $hash->{HELPER}{I_READING};
  my $i_value     = delete $hash->{HELPER}{I_VALUE};
  my $i_unit      = delete $hash->{HELPER}{I_UNIT}; 
  
  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      return;
  } 

  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
  
  readingsBeginUpdate($hash);
    
  ReadingsBulkUpdateValue ($hash, "number_lines_inserted", $irow);    
  ReadingsBulkUpdateValue ($hash, "data_inserted", $i_timestamp.", ".$i_device.", ".$i_type.", ".$i_event.", ".$i_reading.", ".$i_value.", ".$i_unit); 
  ReadingsBulkUpdateTimeState($hash,$brt,$rt,"done");
  
  readingsEndUpdate($hash, 1);
  
  Log3 ($name, 5, "DbRep $name - Inserted into database $hash->{DATABASE} table 'history': Timestamp: $i_timestamp, Device: $i_device, Type: $i_type, Event: $i_event, Reading: $i_reading, Value: $i_value, Unit: $i_unit");  

  delete($hash->{HELPER}{RUNNING_PID});
  
return;
}

####################################################################################################
#   Current-Tabelle mit Device,Reading Kombinationen aus history auffüllen
####################################################################################################
sub currentfillup_Push($) {
 my ($string)     = @_;
 my ($name,$device,$reading,$runtime_string_first,$runtime_string_next) = split("\\|", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $utf8       = defined($hash->{UTF8})?$hash->{UTF8}:0;
 my ($err,$sth,$sql,$devs,$danz,$ranz);
 
 # Background-Startzeit
 my $bst = [gettimeofday];
 
 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1, AutoInactiveDestroy => 1, mysql_enable_utf8 => $utf8 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|''|$err|''|''";
 }
 
 # check ob PK verwendet wird, @usepkx?Anzahl der Felder im PK:0 wenn kein PK, $pkx?Namen der Felder:none wenn kein PK 
 my ($usepkh,$usepkc,$pkh,$pkc) = DbRep_checkUsePK($hash,$dbloghash,$dbh);
 
 # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef) 
 my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash); 
 Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet"); 
 
 ($devs,$danz,$reading,$ranz) = DbRep_specsForSql($hash,$device,$reading);
  
 # SQL-Startzeit
 my $st = [gettimeofday];

 # insert history mit/ohne primary key
 # SQL zusammenstellen für DB-Operation
 if ($usepkc && $dbloghash->{MODEL} eq 'MYSQL') {
     $sql  = "INSERT IGNORE INTO current (TIMESTAMP,DEVICE,READING) SELECT timestamp,device,reading FROM history where ";
     $sql .= "DEVICE LIKE '$devs' AND "      if($danz <= 1 && $devs !~ m(^%$) && $devs =~ m(\%));
     $sql .= "DEVICE = '$devs' AND "         if($danz <= 1 && $devs !~ m(\%));
     $sql .= "DEVICE IN ($devs) AND "        if($danz > 1);
     $sql .= "READING LIKE '$reading' AND "  if($ranz <= 1 && $reading !~ m(^%$) && $reading =~ m(\%));
     $sql .= "READING = '$reading' AND "     if($ranz <= 1 && $reading !~ m(\%));
     $sql .= "READING IN ($reading) AND "    if($ranz > 1);
     if ($IsTimeSet) {
	     $sql .= "TIMESTAMP >= '$runtime_string_first' AND TIMESTAMP < '$runtime_string_next' ";
     } else {
         $sql .= "1 ";
     }
	 $sql .= "group by timestamp,device,reading ;";
	 
 } elsif ($usepkc && $dbloghash->{MODEL} eq 'SQLITE') {
     $sql  = "INSERT OR IGNORE INTO current (TIMESTAMP,DEVICE,READING) SELECT timestamp,device,reading FROM history where ";
     $sql .= "DEVICE LIKE '$devs' AND "      if($danz <= 1 && $devs !~ m(^%$) && $devs =~ m(\%));
     $sql .= "DEVICE = '$devs' AND "         if($danz <= 1 && $devs !~ m(\%));
     $sql .= "DEVICE IN ($devs) AND "        if($danz > 1);
     $sql .= "READING LIKE '$reading' AND "  if($ranz <= 1 && $reading !~ m(^%$) && $reading =~ m(\%));
     $sql .= "READING = '$reading' AND "     if($ranz <= 1 && $reading !~ m(\%));
     $sql .= "READING IN ($reading) AND "    if($ranz > 1);
     if ($IsTimeSet) {
	     $sql .= "TIMESTAMP >= '$runtime_string_first' AND TIMESTAMP < '$runtime_string_next' ";
     } else {
         $sql .= "1 ";
     }
	 $sql .= "group by timestamp,device,reading ;";
 
 } elsif ($usepkc && $dbloghash->{MODEL} eq 'POSTGRESQL') {
         $sql  = "INSERT INTO current (DEVICE,TIMESTAMP,READING) SELECT device, (array_agg(timestamp ORDER BY reading ASC))[1], reading FROM history where ";
         $sql .= "DEVICE LIKE '$devs' AND "      if($danz <= 1 && $devs !~ m(^%$) && $devs =~ m(\%));
         $sql .= "DEVICE = '$devs' AND "         if($danz <= 1 && $devs !~ m(\%));
         $sql .= "DEVICE IN ($devs) AND "        if($danz > 1);
         $sql .= "READING LIKE '$reading' AND "  if($ranz <= 1 && $reading !~ m(^%$) && $reading =~ m(\%));
         $sql .= "READING = '$reading' AND "     if($ranz <= 1 && $reading !~ m(\%));
         $sql .= "READING IN ($reading) AND "    if($ranz > 1);
         if ($IsTimeSet) {
	         $sql .= "TIMESTAMP >= '$runtime_string_first' AND TIMESTAMP < '$runtime_string_next' ";
         } else {
             $sql .= "true ";
         }
	 $sql .= "group by device,reading ON CONFLICT ($pkc) DO NOTHING; ";
 
 } else {
     if($dbloghash->{MODEL} ne 'POSTGRESQL') {
	     # MySQL und SQLite
         $sql  = "INSERT INTO current (TIMESTAMP,DEVICE,READING) SELECT timestamp,device,reading FROM history where ";
         $sql .= "DEVICE LIKE '$devs' AND "      if($danz <= 1 && $devs !~ m(^%$) && $devs =~ m(\%));
         $sql .= "DEVICE = '$devs' AND "         if($danz <= 1 && $devs !~ m(\%));
         $sql .= "DEVICE IN ($devs) AND "        if($danz > 1);
         $sql .= "READING LIKE '$reading' AND "  if($ranz <= 1 && $reading !~ m(^%$) && $reading =~ m(\%));
         $sql .= "READING = '$reading' AND "     if($ranz <= 1 && $reading !~ m(\%));
         $sql .= "READING IN ($reading) AND "    if($ranz > 1);
         if ($IsTimeSet) {
	         $sql .= "TIMESTAMP >= '$runtime_string_first' AND TIMESTAMP < '$runtime_string_next' ";
         } else {
             $sql .= "1 ";
         }
	     $sql .= "group by device,reading ;";
	 } else {
	     # PostgreSQL
         $sql  = "INSERT INTO current (DEVICE,TIMESTAMP,READING) SELECT device, (array_agg(timestamp ORDER BY reading ASC))[1], reading FROM history where ";
         $sql .= "DEVICE LIKE '$devs' AND "      if($danz <= 1 && $devs !~ m(^%$) && $devs =~ m(\%));
         $sql .= "DEVICE = '$devs' AND "         if($danz <= 1 && $devs !~ m(\%));
         $sql .= "DEVICE IN ($devs) AND "        if($danz > 1);
         $sql .= "READING LIKE '$reading' AND "  if($ranz <= 1 && $reading !~ m(^%$) && $reading =~ m(\%));
         $sql .= "READING = '$reading' AND "     if($ranz <= 1 && $reading !~ m(\%));
         $sql .= "READING IN ($reading) AND "    if($ranz > 1);
         if ($IsTimeSet) {
	         $sql .= "TIMESTAMP >= '$runtime_string_first' AND TIMESTAMP < '$runtime_string_next' ";
         } else {
             $sql .= "true ";
         }
	     $sql .= "group by device,reading;";
	 }
 }
 
 # Log SQL Statement
 Log3 ($name, 4, "DbRep $name - SQL execute: $sql");     
 
 eval { $sth = $dbh->prepare($sql); };
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
	 $dbh->disconnect();
     return "$name|''|''|$err|''|''";
 }
 
 
 my $irow;
 $dbh->begin_work();
  
 eval {$sth->execute();};
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - Insert new dataset into database failed".($usepkh?" (possible PK violation) ":": ")."$@");
     $dbh->rollback();
     $dbh->disconnect();
     return "$name|''|''|$err|''|''";
 } else {
     $dbh->commit();
     $irow = $sth->rows;
     $dbh->disconnect();
 } 
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$irow|$rt|0|$device|$reading";
}

####################################################################################################
#                      Auswertungsroutine Current-Tabelle auffüllen
####################################################################################################
sub currentfillup_Done($) {
  my ($string) = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $name       = $hash->{NAME};
  my $irow       = $a[1];
  my $bt         = $a[2];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[3]?decode_base64($a[3]):undef;
  my $device     = $a[4]; 
  my $reading    = $a[5];

  undef $device if ($device =~ m(^%$));
  undef $reading if ($reading =~ m(^%$));
  
  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      return;
  } 

  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
  
  my $rowstr;
  $rowstr = $irow if(!$device && !$reading);
  $rowstr = $irow." - limited by device: ".$device if($device && !$reading);
  $rowstr = $irow." - limited by reading: ".$reading if(!$device && $reading);
  $rowstr = $irow." - limited by device: ".$device." and reading: ".$reading if($device && $reading); 
  
  readingsBeginUpdate($hash);
  ReadingsBulkUpdateValue($hash, "number_lines_inserted", $rowstr);        
  ReadingsBulkUpdateTimeState($hash,$brt,$rt,"done");
  readingsEndUpdate($hash, 1);
  
  Log3 ($name, 3, "DbRep $name - Table '$hash->{DATABASE}'.'current' filled up with rows: $rowstr");

  delete($hash->{HELPER}{RUNNING_PID});
  
return;
}

####################################################################################################
# nichtblockierendes DB deviceRename / readingRename
####################################################################################################
sub change_Push($) {
 my ($string) = @_;
 my ($name,$device,$reading,$runtime_string_first,$runtime_string_next) = split("\\|", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $table      = "history";
 my ($dbh,$err,$sql);
 
 # Background-Startzeit
 my $bst = [gettimeofday];
 
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|''|$err";
 }
 
 my $renmode = $hash->{HELPER}{RENMODE};

 # SQL-Startzeit
 my $st = [gettimeofday];
 
 my ($sth,$old,$new);
 eval { $dbh->begin_work() if($dbh->{AutoCommit}); };   # Transaktion wenn gewünscht und autocommit ein
 if ($@) {
     Log3($name, 2, "DbRep $name -> Error start transaction - $@");
 }
 
 if ($renmode eq "devren") {
     $old  = delete $hash->{HELPER}{OLDDEV};
     $new  = delete $hash->{HELPER}{NEWDEV};
	 
	 # SQL zusammenstellen für DB-Operation
     Log3 ($name, 5, "DbRep $name -> Rename old device name \"$old\" to new device name \"$new\" in database $dblogname ");
	 
	 # prepare DB operation
	 $old =~ s/'/''/g;       # escape ' with ''
	 $new =~ s/'/''/g;       # escape ' with ''
	 $sql = "UPDATE history SET TIMESTAMP=TIMESTAMP,DEVICE='$new' WHERE DEVICE='$old'; ";
	 Log3 ($name, 4, "DbRep $name - SQL execute: $sql"); 
	 $sth = $dbh->prepare($sql) ;
 
 } elsif ($renmode eq "readren") {
     $old = delete $hash->{HELPER}{OLDREAD};
     $new = delete $hash->{HELPER}{NEWREAD};
	 
	 # SQL zusammenstellen für DB-Operation
     Log3 ($name, 5, "DbRep $name -> Rename old reading name \"$old\" to new reading name \"$new\" in database $dblogname ");
	 
	 # prepare DB operation
	 $old =~ s/'/''/g;       # escape ' with ''
	 $new =~ s/'/''/g;       # escape ' with ''
	 $sql = "UPDATE history SET TIMESTAMP=TIMESTAMP,READING='$new' WHERE READING='$old'; ";
	 Log3 ($name, 4, "DbRep $name - SQL execute: $sql"); 
	 $sth = $dbh->prepare($sql) ;
     
 }          
 
 $old =~ s/''/'/g;       # escape back 
 $new =~ s/''/'/g;       # escape back 
 
 my $urow;
 eval { $sth->execute(); };
 if ($@) {
     $err = encode_base64($@,"");
	 my $m = ($renmode eq "devren")?"device":"reading";
     Log3 ($name, 2, "DbRep $name - Failed to rename old $m name \"$old\" to new $m name \"$new\": $@");
	 $dbh->rollback() if(!$dbh->{AutoCommit});
     $dbh->disconnect();
     return "$name|''|''|$err";
 } else {
     $dbh->commit() if(!$dbh->{AutoCommit});
     $urow = $sth->rows;
     $dbh->disconnect();
 } 

 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$urow|$rt|0|$old|$new";
}

####################################################################################################
# nichtblockierendes DB deviceRename / readingRename
####################################################################################################
sub changeval_Push($) {
 my ($string) = @_;
 my ($name,$device,$reading,$runtime_string_first,$runtime_string_next,$ts) = split("\\§", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $table      = "history";
 my $complex    = $hash->{HELPER}{COMPLEX};     # einfache oder komplexe Werteersetzung
 my ($dbh,$err,$sql,$urow);
 
 # Background-Startzeit
 my $bst = [gettimeofday];
 
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1, AutoInactiveDestroy => 1 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|''|$err";
 }

 # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef) 
 my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash); 
 Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");

 # SQL-Startzeit
 my $st = [gettimeofday];
 
 my ($sth,$old,$new);
 eval { $dbh->begin_work() if($dbh->{AutoCommit}); };   # Transaktion wenn gewünscht und autocommit ein
 if ($@) {
     Log3($name, 2, "DbRep $name -> Error start transaction - $@");
 }
 
 if (!$complex) {
     $old = delete $hash->{HELPER}{OLDVAL};
     $new = delete $hash->{HELPER}{NEWVAL};
     
	 # SQL zusammenstellen für DB-Operation
     Log3 ($name, 5, "DbRep $name -> Change old value \"$old\" to new value \"$new\" in database $dblogname ");
	 
	 # prepare DB operation
	 $old =~ s/'/''/g;       # escape ' with ''
	 $new =~ s/'/''/g;       # escape ' with ''
 
     # SQL zusammenstellen für DB-Update
     my $addon = $old =~ /%/?"WHERE VALUE LIKE '$old'":"WHERE VALUE='$old'";
     if ($IsTimeSet) {
         $sql = DbRep_createUpdateSql($hash,$table,"TIMESTAMP=TIMESTAMP,VALUE='$new' $addon",$device,$reading,"'$runtime_string_first'","'$runtime_string_next'",'');
     } else {
         $sql = DbRep_createUpdateSql($hash,$table,"TIMESTAMP=TIMESTAMP,VALUE='$new' $addon",$device,$reading,undef,undef,'');
     }
	 Log3 ($name, 4, "DbRep $name - SQL execute: $sql"); 
	 $sth = $dbh->prepare($sql) ;
     
     $old =~ s/''/'/g;       # escape back 
     $new =~ s/''/'/g;       # escape back 
 
     eval { $sth->execute(); };
     if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - Failed to change old value \"$old\" to new value \"$new\": $@");
	     $dbh->rollback() if(!$dbh->{AutoCommit});
         $dbh->disconnect();
         return "$name|''|''|$err";
     } else {
         $dbh->commit() if(!$dbh->{AutoCommit});
         $urow = $sth->rows;
     }
     
 } else {
     $old = delete $hash->{HELPER}{OLDVAL};
     $new = delete $hash->{HELPER}{NEWVAL};
     $old =~ s/'/''/g;       # escape ' with ''
     
     # Timestampstring to Array
     my @ts = split("\\|", $ts);
     Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");
     
     # DB-Abfrage zeilenweise für jeden Array-Eintrag
     $urow = 0;
     my $selspec = "DEVICE,READING,TIMESTAMP,VALUE,UNIT";
     my $addon   = $old =~ /%/?"AND VALUE LIKE '$old'":"AND VALUE='$old'";
     foreach my $row (@ts) {
         my @a                     = split("#", $row);
         my $runtime_string        = $a[0];
         my $runtime_string_first  = $a[1];
         my $runtime_string_next   = $a[2];
         
         if ($IsTimeSet || $IsAggrSet) {
             $sql = DbRep_createSelectSql($hash,"history",$selspec,$device,$reading,"'$runtime_string_first'","'$runtime_string_next'",$addon); 
	     } else {
	         $sql = DbRep_createSelectSql($hash,"history",$selspec,$device,$reading,undef,undef,$addon);
	     }
         Log3 ($name, 4, "DbRep $name - SQL execute: $sql");
         
         eval{ $sth = $dbh->prepare($sql);
               $sth->execute();
             };	         
	     if ($@) {
             $err = encode_base64($@,"");
             Log3 ($name, 2, "DbRep $name - $@");
             $dbh->disconnect;
             return "$name|''|''|$err";
         }
         
         no warnings 'uninitialized'; 
         #                     DEVICE   _ESC_  READING  _ESC_     DATE _ESC_ TIME        _ESC_  VALUE    _ESC_   UNIT
         my @row_array = map { $_->[0]."_ESC_".$_->[1]."_ESC_".($_->[2] =~ s/ /_ESC_/r)."_ESC_".$_->[3]."_ESC_".$_->[4]."\n" } @{$sth->fetchall_arrayref()}; 
         use warnings;
         
         Log3 ($name, 4, "DbRep $name - Now change values of selected array ... "); 
         
         foreach my $upd (@row_array) {
             # für jeden selektierten (zu ändernden) Datensatz Userfunktion anwenden und updaten
             my ($device,$reading,$date,$time,$value,$unit) = ($upd =~ /^(.*)_ESC_(.*)_ESC_(.*)_ESC_(.*)_ESC_(.*)_ESC_(.*)$/);
         
             my $oval  = $value;  # Selektkriterium für Update alter Valuewert
             my $VALUE = $value;
 	         my $UNIT  = $unit;
             eval $new;
	         if ($@) {
                 $err = encode_base64($@,"");
                 Log3 ($name, 2, "DbRep $name - $@");
                 $dbh->disconnect;
                 return "$name|''|''|$err";
             }
             
             $value = $VALUE if(defined $VALUE);
 	         $unit  = $UNIT  if(defined $UNIT);
             # Daten auf maximale Länge beschneiden (DbLog-Funktion !)
             (undef,undef,undef,undef,$value,$unit) = DbLog_cutCol($hash->{dbloghash},"1","1","1","1",$value,$unit);
             
             $value =~ s/'/''/g;       # escape ' with ''
             $unit  =~ s/'/''/g;       # escape ' with ''
             
             # SQL zusammenstellen für DB-Update
             $sql = "UPDATE history SET TIMESTAMP=TIMESTAMP,VALUE='$value',UNIT='$unit' WHERE TIMESTAMP = '$date $time' AND DEVICE = '$device' AND READING = '$reading' AND VALUE='$oval'";
	         Log3 ($name, 5, "DbRep $name - SQL execute: $sql"); 
	         $sth = $dbh->prepare($sql) ;
     
             $value =~ s/''/'/g;       # escape back 
             $unit  =~ s/''/'/g;       # escape back 
 
             eval { $sth->execute(); };
             if ($@) {
                 $err = encode_base64($@,"");
                 Log3 ($name, 2, "DbRep $name - Failed to change old value \"$old\" to new value \"$new\": $@");
	             $dbh->rollback() if(!$dbh->{AutoCommit});
                 $dbh->disconnect();
                 return "$name|''|''|$err";
             } else {
                 $dbh->commit() if(!$dbh->{AutoCommit});
                 $urow++;
             }
         }
     }
 }
 
 $dbh->disconnect();

 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$urow|$rt|0|$old|$new";
}

####################################################################################################
# Auswertungsroutine DB deviceRename/readingRename/changeValue
####################################################################################################
sub change_Done($) {
  my ($string) = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $name       = $hash->{NAME};
  my $urow       = $a[1];
  my $bt         = $a[2];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[3]?decode_base64($a[3]):undef;
  my $old        = $a[4];
  my $new        = $a[5]; 
  
  my $renmode = delete $hash->{HELPER}{RENMODE};
  
  # Befehl nach Procedure ausführen
  my $erread = DbRep_afterproc($hash, $renmode);
  
  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      return;
  } 

  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
  
  readingsBeginUpdate($hash);
  ReadingsBulkUpdateValue ($hash, "number_lines_updated", $urow);
  
  if($renmode eq "devren") {
	  ReadingsBulkUpdateValue ($hash, "device_renamed", "old: ".$old." to new: ".$new) if($urow != 0);
      ReadingsBulkUpdateValue ($hash, "device_not_renamed", "Warning - old: ".$old." not found, not renamed to new: ".$new) 
	      if($urow == 0);
  }
  if($renmode eq "readren") {
	  ReadingsBulkUpdateValue ($hash, "reading_renamed", "old: ".$old." to new: ".$new)  if($urow != 0);
      ReadingsBulkUpdateValue ($hash, "reading_not_renamed", "Warning - old: ".$old." not found, not renamed to new: ".$new) 
	      if ($urow == 0);
  }
  if($renmode eq "changeval") {
	  ReadingsBulkUpdateValue ($hash, "value_changed", "old: ".$old." to new: ".$new)  if($urow != 0);
      ReadingsBulkUpdateValue ($hash, "value_not_changed", "Warning - old: ".$old." not found, not changed to new: ".$new) 
	      if ($urow == 0);
  }
  
  ReadingsBulkUpdateTimeState($hash,$brt,$rt,"done");
  readingsEndUpdate($hash, 1);
  
  if ($urow != 0) {
      Log3 ($name, 3, "DbRep ".(($hash->{ROLE} eq "Agent")?"Agent ":"")."$name - DEVICE renamed in \"$hash->{DATABASE}\", old: \"$old\", new: \"$new\", number: $urow ") if($renmode eq "devren"); 
	  Log3 ($name, 3, "DbRep ".(($hash->{ROLE} eq "Agent")?"Agent ":"")."$name - READING renamed in \"$hash->{DATABASE}\", old: \"$old\", new: \"$new\", number: $urow ") if($renmode eq "readren"); 
	  Log3 ($name, 3, "DbRep ".(($hash->{ROLE} eq "Agent")?"Agent ":"")."$name - VALUE changed in \"$hash->{DATABASE}\", old: \"$old\", new: \"$new\", number: $urow ") if($renmode eq "changeval");  
  } else {
      Log3 ($name, 3, "DbRep ".(($hash->{ROLE} eq "Agent")?"Agent ":"")."$name - WARNING - old device \"$old\" was not found in database \"$hash->{DATABASE}\" ") if($renmode eq "devren");
      Log3 ($name, 3, "DbRep ".(($hash->{ROLE} eq "Agent")?"Agent ":"")."$name - WARNING - old reading \"$old\" was not found in database \"$hash->{DATABASE}\" ") if($renmode eq "readren"); 	
	  Log3 ($name, 3, "DbRep ".(($hash->{ROLE} eq "Agent")?"Agent ":"")."$name - WARNING - old value \"$old\" not found in database \"$hash->{DATABASE}\" ") if($renmode eq "changeval");        
  }

  delete($hash->{HELPER}{RUNNING_PID});
  
return;
}

####################################################################################################
# nichtblockierende DB-Abfrage fetchrows
####################################################################################################
sub fetchrows_DoParse($) {
 my ($string) = @_;
 my ($name,$table,$device,$reading,$runtime_string_first,$runtime_string_next) = split("\\|", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $limit      = AttrVal($name, "limit", 1000);
 my $utf8       = defined($hash->{UTF8})?$hash->{UTF8}:0;
 my $fetchroute = AttrVal($name, "fetchRoute", "descent");
 $fetchroute    = ($fetchroute eq "descent")?"DESC":"ASC";
 my ($err,$dbh,$sth,$sql,$rowlist,$nrows);
 
 # Background-Startzeit
 my $bst = [gettimeofday];

 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1, mysql_enable_utf8 => $utf8 });};
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|''|$err|''";
 }

 # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef) 
 my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash); 
 Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet"); 
 
 # SQL zusammenstellen für DB-Abfrage
 if ($IsTimeSet) {
     $sql = DbRep_createSelectSql($hash,$table,"DEVICE,READING,TIMESTAMP,VALUE,UNIT",$device,$reading,"'$runtime_string_first'","'$runtime_string_next'","ORDER BY TIMESTAMP $fetchroute LIMIT ".($limit+1));
 } else {
     $sql = DbRep_createSelectSql($hash,$table,"DEVICE,READING,TIMESTAMP,VALUE,UNIT",$device,$reading,undef,undef,"ORDER BY TIMESTAMP $fetchroute LIMIT ".($limit+1));
 }
 
 $sth = $dbh->prepare($sql);
 
 Log3 ($name, 4, "DbRep $name - SQL execute: $sql");    

 # SQL-Startzeit
 my $st = [gettimeofday];
 
 eval{$sth->execute();};	 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     $dbh->disconnect;
     return "$name|''|''|$err|''";
 } 
 
 no warnings 'uninitialized'; 
 my @row_array = map { $_->[0]."_ESC_".$_->[1]."_ESC_".($_->[2] =~ s/ /_ESC_/r)."_ESC_".$_->[3]."_ESC_".$_->[4]."\n" } @{$sth->fetchall_arrayref()}; 

 use warnings;
 $nrows = $#row_array+1;                # Anzahl der Ergebniselemente  
 pop @row_array if($nrows>$limit);      # das zuviel selektierte Element wegpoppen wenn Limit überschritten
 
 s/\|/_E#S#C_/g for @row_array;         # escape Pipe "|"
 if ($utf8) {
     $rowlist = Encode::encode_utf8(join('|', @row_array));
 } else {
     $rowlist = join('|', @row_array);
 }
 Log3 ($name, 5, "DbRep $name -> row result list:\n$rowlist");
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);

 $dbh->disconnect;
 
 # Daten müssen als Einzeiler zurückgegeben werden
 $rowlist = encode_base64($rowlist,"");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$rowlist|$rt|0|$nrows";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage fetchrows
####################################################################################################
sub fetchrows_ParseDone($) {
  my ($string) = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $rowlist    = decode_base64($a[1]);
  my $bt         = $a[2];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[3]?decode_base64($a[3]):undef;
  my $nrows      = $a[4];
  my $name       = $hash->{NAME};
  my $reading    = AttrVal($name, "reading", undef);
  my $limit      = AttrVal($name, "limit", 1000);
  my $color      = "<html><span style='color: #".AttrVal($name, "fetchMarkDuplicates", "000000").";'>";  # Highlighting doppelter DB-Einträge
  $color =~ s/#// if($color =~ /red|blue|brown|green|orange/);
  my $ecolor     = "</span></html>";   # Ende Highlighting
  my @i;
  my @row;
  my $reading_runtime_string;
  
  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      return;
  } 
  
  my @row_array = split("\\|", $rowlist);
  s/_E#S#C_/\|/g for @row_array;                    # escaped Pipe return to "|"
  
  Log3 ($name, 5, "DbRep $name - row_array decoded: @row_array");
  
  # Readingaufbereitung
  readingsBeginUpdate($hash);
  my $orow;
  my $dz = 1;                      # Index des Vorkommens im Selektionsarray
  foreach my $row (@row_array) {
      if($orow) {
          if($orow eq $row) {
              $dz++;
              
          } else {
              $dz = 1;
          }
      }
      $orow = $row;
      if($dz > 1) {
          # Hervorhebung von multiplen Datensätzen
          # $dz = "<html><span style='color: ".$color.";'>".$dz."</span></html>";
      }
      my @a = split("_ESC_", $row, 6);     
      my $dev = $a[0];
      my $rea = $a[1];
      $a[3]   =~ s/:/-/g;          # substituieren unsupported characters ":" -> siehe fhem.pl
      my $ts  = $a[2]."_".$a[3];
      my $val = $a[4];
	  my $unt = $a[5];
      $val = $unt?$val." ".$unt:$val;
      
      if ($reading && AttrVal($hash->{NAME}, "readingNameMap", "")) {
          if($dz > 1 && AttrVal($name, "fetchMarkDuplicates", undef)) {
              $reading_runtime_string = $ts."__".$color.$dz."__".AttrVal($hash->{NAME}, "readingNameMap", "").$ecolor;
          } else {
              $reading_runtime_string = $ts."__".$dz."__".AttrVal($hash->{NAME}, "readingNameMap", "");
          }
      } else {
          if($dz > 1 && AttrVal($name, "fetchMarkDuplicates", undef)) {
              $reading_runtime_string = $ts."__".$color.$dz."__".$dev."__".$rea.$ecolor;
          } else {
              $reading_runtime_string = $ts."__".$dz."__".$dev."__".$rea;
          }
      }
     
	  ReadingsBulkUpdateValue($hash, $reading_runtime_string, $val);
  }
  my $sfx = AttrVal("global", "language", "EN");
  $sfx = ($sfx eq "EN" ? "" : "_$sfx");
  
  ReadingsBulkUpdateValue($hash, "number_fetched_rows", ($nrows>$limit)?$nrows-1:$nrows);
  ReadingsBulkUpdateTimeState($hash,$brt,$rt,($nrows-$limit>0)?
      "<html>done - Warning: present rows exceed specified limit, adjust attribute <a href='https://fhem.de/commandref${sfx}.html#DbRepattrlimit' target='_blank'>limit</a></html>":"done");
  readingsEndUpdate($hash, 1);

  delete($hash->{HELPER}{RUNNING_PID});
  
return;
}

####################################################################################################
#                                    DB-Abfrage delSeqDoublets
####################################################################################################
sub delseqdoubl_DoParse($) {
 my ($string) = @_;
 my ($name,$opt,$device,$reading,$ts) = split("\\§", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $utf8       = defined($hash->{UTF8})?$hash->{UTF8}:0;
 my $limit      = AttrVal($name, "limit", 1000);
 my $var        = AttrVal($name, "seqDoubletsVariance", undef);
 my $table      = "history";
 my ($err,$dbh,$sth,$sql,$rowlist,$nrows,$selspec,$st,$var1,$var2);
 
 # Background-Startzeit
 my $bst = [gettimeofday];

 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1, mysql_enable_utf8 => $utf8 });};
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|''|$err|''|$opt";
 }

 # Timestampstring to Array
 my @ts = split("\\|", $ts);
 Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts"); 
 
 $selspec = "DEVICE,READING,TIMESTAMP,VALUE";
  
 # SQL zusammenstellen für DB-Abfrage
 $sql = DbRep_createSelectSql($hash,$table,$selspec,$device,$reading,"?","?","ORDER BY DEVICE,READING,TIMESTAMP ASC");
 $sth = $dbh->prepare_cached($sql);
 
 # DB-Abfrage zeilenweise für jeden Timearray-Eintrag
 my @remain;
 my @todel; 
 my $nremain = 0;
 my $ntodel  = 0;
 my $ndel    = 0;
 my $rt      = 0;
 
 no warnings 'uninitialized'; 
 
 foreach my $row (@ts) {
     my @a                     = split("#", $row);
     my $runtime_string        = $a[0];
     my $runtime_string_first  = $a[1];
     my $runtime_string_next   = $a[2];  
     $runtime_string           = encode_base64($runtime_string,""); 
	  
	 # SQL-Startzeit
     $st = [gettimeofday];
     
     # SQL zusammenstellen für Logausgabe
	 my $sql1 = DbRep_createSelectSql($hash,$table,$selspec,$device,$reading,"'$runtime_string_first'","'$runtime_string_next'",'');  
     Log3 ($name, 4, "DbRep $name - SQL execute: $sql1"); 
 
	 eval{$sth->execute($runtime_string_first, $runtime_string_next);};
     if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         return "$name|''|''|$err|''|$opt";
     } 
 
     # SQL-Laufzeit ermitteln
     $rt = $rt+tv_interval($st);
        
     # Beginn Löschlogik, Zusammenstellen der löschenden DS (warping)
	 # Array @sel -> die VERBLEIBENDEN Datensätze, @warp -> die zu löschenden Datensätze
     my (@sel,@warp);
     my ($or,$oor,$odev,$oread,$oval,$ooval,$ndev,$nread,$nval);
     my $i = 0;
     foreach my $nr (map { $_->[0]."_ESC_".$_->[1]."_ESC_".($_->[2] =~ s/ /_ESC_/r)."_ESC_".$_->[3] } @{$sth->fetchall_arrayref()}) {               
         ($ndev,$nread,undef,undef,$nval) = split("_ESC_", $nr);    # Werte des aktuellen Elements
	     $or = pop @sel;                                            # das letzte Element der Liste                         
         ($odev,$oread,undef,undef,$oval) = split("_ESC_", $or);    # Value des letzten Elements      
         if (looks_like_number($oval) && $var) {                    # Varianz +- falls $val numerischer Wert
             $var1 = $oval + $var;
             $var2 = $oval - $var;
         } else {
             undef $var1;
             undef $var2;
         }
	     $oor = pop @sel;                                           # das vorletzte Element der Liste
		 $ooval = (split '_ESC_', $oor)[-1];                        # Value des vorletzten Elements
		 if ($ndev.$nread ne $odev.$oread) {
             $i = 0;                                                # neues Device/Reading in einer Periode -> ooor soll erhalten bleiben
		     push (@sel,$oor) if($oor);
		     push (@sel,$or) if($or);
		     push (@sel,$nr);
		 } elsif ($i>=2 && ($ooval eq $oval && $oval eq $nval) || ($i>=2 && $var1 && $var2 && ($ooval <= $var1) && ($var2 <= $ooval) && ($nval <= $var1) && ($var2 <= $nval)) ) {
		     push (@sel,$oor);
		     push (@sel,$nr);
             push (@warp,$or);                                      # Array der zu löschenden Datensätze				 
             if ($opt =~ /delete/ && $or) {                         # delete Datensätze
		         my ($dev,$read,$date,$time,$val) = split("_ESC_", $or);
				 my $dt = $date." ".$time;
				 chomp($val);
				 $dev  =~ s/'/''/g;                                 # escape ' with ''
				 $read =~ s/'/''/g;                                 # escape ' with ''
				 $val  =~ s/'/''/g;                                 # escape ' with ''
				 $st = [gettimeofday];
				 my $dsql = "delete FROM $table where TIMESTAMP = '$dt' AND DEVICE = '$dev' AND READING = '$read' AND VALUE = '$val';";
				 my $sthd = $dbh->prepare($dsql); 
                 Log3 ($name, 4, "DbRep $name - SQL execute: $dsql"); 
					 
				 eval {$sthd->execute();};
				 if ($@) {
                     $err = encode_base64($@,"");
                     Log3 ($name, 2, "DbRep $name - $@");
                     $dbh->disconnect;
                     return "$name|''|''|$err|''|$opt";
                 } 
				 $ndel = $ndel+$sthd->rows;
                 $dbh->commit() if(!$dbh->{AutoCommit});
					 
				 $rt = $rt+tv_interval($st);
			 }		 
         } else {
		     push (@sel,$oor) if($oor);
		     push (@sel,$or) if($or);
		     push (@sel,$nr);
		 }
         $i++;
     }
     if(@sel && $opt =~ /adviceRemain/) {
         # die verbleibenden Datensätze nach Ausführung (nur zur Anzeige) 
         push(@remain,@sel) if($#remain+1 < $limit);      
     }
     if(@warp && $opt =~ /adviceDelete/) {
         # die zu löschenden Datensätze (nur zur Anzeige)
         push(@todel,@warp) if($#todel+1 < $limit);    
     }

     $nremain = $nremain + $#sel+1 if(@sel);
     $ntodel = $ntodel + $#warp+1 if(@warp);
     my $sum = $nremain+$ntodel;
     Log3 ($name, 3, "DbRep $name -> rows analyzed by \"$hash->{LASTCMD}\": $sum") if($sum && $opt =~ /advice/); 
 }
 
 Log3 ($name, 3, "DbRep $name -> rows deleted by \"$hash->{LASTCMD}\": $ndel") if($ndel);
  
 my $retn = ($opt =~ /adviceRemain/)?$nremain:($opt =~ /adviceDelete/)?$ntodel:$ndel; 

 my @retarray = ($opt =~ /adviceRemain/)?@remain:($opt =~ /adviceDelete/)?@todel:" ";
 s/\|/_E#S#C_/g for @retarray;         # escape Pipe "|" 
 if ($utf8 && @retarray) {
     $rowlist = Encode::encode_utf8(join('|', @retarray));
 } elsif(@retarray) {
     $rowlist = join('|', @retarray);
 } else {
     $rowlist = 0;
 }
 
 use warnings;
 Log3 ($name, 5, "DbRep $name -> row result list:\n$rowlist");

 $dbh->disconnect;
 
 # Daten müssen als Einzeiler zurückgegeben werden
 $rowlist = encode_base64($rowlist,"");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
return "$name|$rowlist|$rt|0|$retn|$opt";
}

####################################################################################################
#             Auswertungsroutine delSeqDoublets
####################################################################################################
sub delseqdoubl_ParseDone($) {
  my ($string) = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $rowlist    = decode_base64($a[1]);
  my $bt         = $a[2];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[3]?decode_base64($a[3]):undef;
  my $nrows      = $a[4];
  my $opt        = $a[5];
  my $name       = $hash->{NAME};
  my $reading    = AttrVal($name, "reading", undef);
  my $limit      = AttrVal($name, "limit", 1000);
  my @row;
  my $l = 1;
  my $reading_runtime_string;
  my $erread;
  
  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      return;
  } 
  
  # Befehl nach Procedure ausführen
  $erread = DbRep_afterproc($hash, "delSeq");
  
  # Readingaufbereitung
  readingsBeginUpdate($hash);
  
  no warnings 'uninitialized'; 
  if ($opt !~ /delete/ && $rowlist) {
      my @row_array = split("\\|", $rowlist);
      s/_E#S#C_/\|/g for @row_array;        # escaped Pipe return to "|"
      Log3 ($name, 5, "DbRep $name - row_array decoded: @row_array");
      foreach my $row (@row_array) {
	      last if($l >= $limit);
          my @a = split("_ESC_", $row, 5); 
		  my $dev = $a[0];
          my $rea = $a[1];
          $a[3]   =~ s/:/-/g;               # substituieren unsupported characters ":" -> siehe fhem.pl
          my $ts  = $a[2]."_".$a[3];
          my $val = $a[4];
             
          if ($reading && AttrVal($hash->{NAME}, "readingNameMap", "")) {
              $reading_runtime_string = $ts."__".AttrVal($hash->{NAME}, "readingNameMap", "") ;
          } else {
              $reading_runtime_string = $ts."__".$dev."__".$rea;
          }
	      ReadingsBulkUpdateValue($hash, $reading_runtime_string, $val);
		  $l++;
      }
  }
  
  use warnings;
  my $sfx = AttrVal("global", "language", "EN");
  $sfx = ($sfx eq "EN" ? "" : "_$sfx");

  my $rnam = ($opt =~ /adviceRemain/)?"number_rows_to_remain":($opt =~ /adviceDelete/)?"number_rows_to_delete":"number_rows_deleted"; 
  ReadingsBulkUpdateValue($hash, "$rnam", "$nrows");
  ReadingsBulkUpdateTimeState($hash,$brt,$rt,($l >= $limit)?
      "<html>done - Warning: not all items are shown, adjust attribute <a href='https://fhem.de/commandref${sfx}.html#DbRepattrlimit' target='_blank'>limit</a> if you want see more</html>":"done");
  readingsEndUpdate($hash, 1);

  delete($hash->{HELPER}{RUNNING_PID});
return;
}

####################################################################################################
# nichtblockierende DB-Funktion expfile
####################################################################################################
sub expfile_DoParse($) {
 my ($string) = @_;
 my ($name, $device, $reading, $ts) = split("\\§", $string);
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $utf8       = defined($hash->{UTF8})?$hash->{UTF8}:0;
 my ($dbh,$sth,$sql);
 my $err=0;

 # Background-Startzeit
 my $bst = [gettimeofday];

 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1, mysql_enable_utf8 => $utf8 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|''|$err|''|''";
 }
 
 my $outfile = AttrVal($name, "expimpfile", undef);
 if (open(FH, ">:utf8", "$outfile")) {
     binmode (FH) if(!$utf8);
 } else {
     $err = encode_base64("could not open ".$outfile.": ".$!,"");
     return "$name|''|''|$err";
 }
 
 # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef) 
 my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash); 
 Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet"); 
 
 # Timestampstring to Array
 my @ts = split("\\|", $ts);
 Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts"); 
 
 # SQL-Startzeit
 my $st = [gettimeofday];
 
 # DB-Abfrage zeilenweise für jeden Array-Eintrag
 my $arrstr;
 my $nrows = 0;
 my $addon = "ORDER BY TIMESTAMP";
 no warnings 'uninitialized'; 
 foreach my $row (@ts) {
     my @a                     = split("#", $row);
     my $runtime_string        = $a[0];
     my $runtime_string_first  = $a[1];
     my $runtime_string_next   = $a[2];   
 
     if ($IsTimeSet || $IsAggrSet) {
         $sql = DbRep_createSelectSql($hash,"history","TIMESTAMP,DEVICE,TYPE,EVENT,READING,VALUE,UNIT",$device,$reading,"'$runtime_string_first'","'$runtime_string_next'",$addon);
	 } else {
         $sql = DbRep_createSelectSql($hash,"history","TIMESTAMP,DEVICE,TYPE,EVENT,READING,VALUE,UNIT",$device,$reading,undef,undef,$addon);
	 }
     Log3 ($name, 4, "DbRep $name - SQL execute: $sql");
     
     eval{ $sth = $dbh->prepare($sql);
           $sth->execute();
         };	
	 if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         return "$name|''|''|$err|''|''";
     } 
 
     while (my $row = $sth->fetchrow_arrayref) {
         print FH DbRep_charfilter(join(',', map { s{"}{""}g; "\"$_\"";} @$row)), "\n";
         Log3 ($name, 5, "DbRep $name -> write row:  @$row");
         # Anzahl der Datensätze
         $nrows++;
     }
 
 }     
 close(FH);

 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);

 $sth->finish;
 $dbh->disconnect;
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$nrows|$rt|$err|$device|$reading";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Funktion expfile
####################################################################################################
sub expfile_ParseDone($) {
  my ($string) = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $nrows      = $a[1];
  my $bt         = $a[2];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[3]?decode_base64($a[3]):undef;
  my $name       = $hash->{NAME};
  my $device     = $a[4];
     $device     =~ s/[^A-Za-z\/\d_\.-]/\//g; 
  my $reading    = $a[5];
     $reading    =~ s/[^A-Za-z\/\d_\.-]/\//g; 
  
  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      return;
  } 
 
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
  
  my $ds   = $device." -- " if ($device);
  my $rds  = $reading." -- " if ($reading);
  my $export_string = $ds.$rds." -- ROWS EXPORTED TO FILE -- ";
  
  readingsBeginUpdate($hash);
  ReadingsBulkUpdateValue ($hash, $export_string, $nrows); 
  ReadingsBulkUpdateTimeState($hash,$brt,$rt,"done");
  readingsEndUpdate($hash, 1);
  
  my $rows = $ds.$rds.$nrows;
  Log3 ($name, 3, "DbRep $name - Number of exported datasets from $hash->{DATABASE} to file ".AttrVal($name, "expimpfile", undef).": $rows.");

  delete($hash->{HELPER}{RUNNING_PID});
  
return;
}

####################################################################################################
# nichtblockierende DB-Funktion impfile
####################################################################################################
sub impfile_Push($) {
 my ($name) = @_;
 my $hash       = $defs{$name};
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbmodel    = $hash->{dbloghash}{MODEL};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 my $utf8       = defined($hash->{UTF8})?$hash->{UTF8}:0;
 my $err=0;
 my $sth;

 # Background-Startzeit
 my $bst = [gettimeofday];

 my $dbh;
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1, AutoInactiveDestroy => 1, mysql_enable_utf8 => $utf8 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|''|$err";
 }
 
 # check ob PK verwendet wird, @usepkx?Anzahl der Felder im PK:0 wenn kein PK, $pkx?Namen der Felder:none wenn kein PK 
 my ($usepkh,$usepkc,$pkh,$pkc) = DbRep_checkUsePK($hash,$dbloghash,$dbh);
 
 my $infile = AttrVal($name, "expimpfile", undef);
 if (open(FH, "<:utf8", "$infile")) {
     binmode (FH) if(!$utf8);
 } else {
     $err = encode_base64("could not open ".$infile.": ".$!,"");
     return "$name|''|''|$err";
 }
 
 # only for this block because of warnings if details inline is not set
 no warnings 'uninitialized'; 
 
 # SQL-Startzeit
 my $st = [gettimeofday];
 
 my $al;
 # Datei zeilenweise einlesen und verarbeiten !
 # Beispiel Inline:  
 # "2016-09-25 08:53:56","STP_5000","SMAUTILS","etotal: 11859.573","etotal","11859.573",""
 
 # insert history mit/ohne primary key
 if ($usepkh && $dbloghash->{MODEL} eq 'MYSQL') {
     eval { $sth = $dbh->prepare_cached("INSERT IGNORE INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
 } elsif ($usepkh && $dbloghash->{MODEL} eq 'SQLITE') {
     eval { $sth = $dbh->prepare_cached("INSERT OR IGNORE INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
 } elsif ($usepkh && $dbloghash->{MODEL} eq 'POSTGRESQL') {
     eval { $sth = $dbh->prepare_cached("INSERT INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"); };
 } else {
     eval { $sth = $dbh->prepare_cached("INSERT INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
 }
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
	 $dbh->disconnect();
     return "$name|''|''|$err";
 }
 
 $dbh->begin_work();
 
 my $irowdone = 0;
 my $irowcount = 0;
 my $warn = 0;
 while (<FH>) {
     $al = $_;
     chomp $al; 
     my @alarr = split("\",\"", $al);
	 foreach(@alarr) {
         tr/"//d;
     }
     my $i_timestamp = $alarr[0];
     # $i_timestamp =~ tr/"//d;
     my $i_device    = $alarr[1];
     my $i_type      = $alarr[2];
     my $i_event     = $alarr[3];
     my $i_reading   = $alarr[4];
     my $i_value     = $alarr[5];
     my $i_unit      = $alarr[6] ? $alarr[6]: " ";
     $irowcount++;
     next if(!$i_timestamp);  #leerer Datensatz
     
     # check ob TIMESTAMP Format ok ?
     my ($i_date, $i_time) = split(" ",$i_timestamp);
     if ($i_date !~ /(\d{4})-(\d{2})-(\d{2})/ || $i_time !~ /(\d{2}):(\d{2}):(\d{2})/) {
         $err = encode_base64("Format of date/time is not valid in row $irowcount of $infile. Must be format \"YYYY-MM-DD HH:MM:SS\" !","");
         Log3 ($name, 2, "DbRep $name -> ERROR - Import from file $infile was not done. Invalid date/time field format in row $irowcount.");    
         close(FH);
         $dbh->rollback;
         return "$name|''|''|$err";
     }
     
     # Daten auf maximale Länge (entsprechend der Feldlänge in DbLog DB create-scripts) beschneiden wenn nicht SQLite
     if ($dbmodel ne 'SQLITE') {
         $i_device   = substr($i_device,0, $dbrep_col{DEVICE});
         $i_event    = substr($i_event,0, $dbrep_col{EVENT});
         $i_reading  = substr($i_reading,0, $dbrep_col{READING});
         $i_value    = substr($i_value,0, $dbrep_col{VALUE});
         $i_unit     = substr($i_unit,0, $dbrep_col{UNIT}) if($i_unit);
     }     
     
     Log3 ($name, 5, "DbRep $name -> data to insert Timestamp: $i_timestamp, Device: $i_device, Type: $i_type, Event: $i_event, Reading: $i_reading, Value: $i_value, Unit: $i_unit");     
     
     if($i_timestamp && $i_device && $i_reading) {
         
         eval {$sth->execute($i_timestamp, $i_device, $i_type, $i_event, $i_reading, $i_value, $i_unit);};
 
         if ($@) {
             $err = encode_base64($@,"");
             Log3 ($name, 2, "DbRep $name - Failed to insert new dataset into database: $@");
             close(FH);
             $dbh->rollback;
             $dbh->disconnect;
             return "$name|''|''|$err";
         } else {
             $irowdone++
         }
       
     } else {
         my $c = !$i_timestamp?"field \"timestamp\" is empty":!$i_device?"field \"device\" is empty":"field \"reading\" is empty";
         $err = encode_base64("format error in in row $irowcount of $infile - cause: $c","");
         Log3 ($name, 2, "DbRep $name -> ERROR - Import of datasets NOT done. Formaterror in row $irowcount of $infile - cause: $c");     
         close(FH);
         $dbh->rollback;
         $dbh->disconnect;
         return "$name|''|''|$err";
     }   
 }
 
 $dbh->commit;
 $dbh->disconnect;
 close(FH);
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$irowdone|$rt|$err";
}

####################################################################################################
#             Auswertungsroutine der nichtblockierenden DB-Funktion impfile
####################################################################################################
sub impfile_PushDone($) {
  my ($string)   = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $irowdone   = $a[1];
  my $bt         = $a[2];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[3]?decode_base64($a[3]):undef;
  my $name       = $hash->{NAME};
  
  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      return;
  } 
 
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 

  my $import_string = " -- ROWS IMPORTED FROM FILE -- ";
  
  readingsBeginUpdate($hash);
  ReadingsBulkUpdateValue ($hash, $import_string, $irowdone);
  ReadingsBulkUpdateTimeState($hash,$brt,$rt,"done");
  readingsEndUpdate($hash, 1);

  Log3 ($name, 3, "DbRep $name - Number of imported datasets to $hash->{DATABASE} from file ".AttrVal($name, "expimpfile", undef).": $irowdone");  

  delete($hash->{HELPER}{RUNNING_PID});
  
return;
}

####################################################################################################
# nichtblockierende DB-Abfrage sqlCmd - generischer SQL-Befehl - name | opt | sqlcommand
####################################################################################################
# set logdbrep sqlCmd select count(*) from history
# set logdbrep sqlCmd select DEVICE,count(*) from history group by DEVICE HAVING count(*) > 10000
sub sqlCmd_DoParse($) {
  my ($string) = @_;
  my ($name, $opt, $runtime_string_first, $runtime_string_next, $cmd) = split("\\|", $string);
  my $hash       = $defs{$name};
  my $dbloghash  = $hash->{dbloghash};
  my $dbconn     = $dbloghash->{dbconn};
  my $dbuser     = $dbloghash->{dbuser};
  my $dblogname  = $dbloghash->{NAME};
  my $dbpassword = $attr{"sec$dblogname"}{secret};
  my $utf8       = defined($hash->{UTF8})?$hash->{UTF8}:0;
  my $srs        = AttrVal($name, "sqlResultFieldSep", "|");
  my $err;

  # Background-Startzeit
  my $bst = [gettimeofday];

  my $dbh;
  eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1, AutoInactiveDestroy => 1, mysql_enable_utf8 => $utf8 });};
 
  if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|$opt|$cmd|''|''|$err";
  }
     
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 

  my $sql = ($cmd =~ m/\;$/)?$cmd:$cmd.";"; 
  # Allow inplace replacement of keywords for timings (use time attribute syntax)
  $sql =~ s/§timestamp_begin§/'$runtime_string_first'/g;
  $sql =~ s/§timestamp_end§/'$runtime_string_next'/g;

#  Debug "SQL :".$sql.":";
  
  Log3($name, 4, "DbRep $name - SQL execute: $sql");        

  # SQL-Startzeit
  my $st = [gettimeofday];
  
  my ($sth,$r);
  
  eval {$sth = $dbh->prepare($sql);
        $r = $sth->execute();
       }; 
  
  if ($@) {
     # error bei sql-execute
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - ERROR - $@");
     $dbh->disconnect;
     return "$name|''|$opt|$sql|''|''|$err";       
  }
 
  my @rows;
  my $nrows = 0;
  if($sql =~ m/^\s*(select|pragma|show)/is) {
    while (my @line = $sth->fetchrow_array()) {
      Log3 ($name, 4, "DbRep $name - SQL result: @line");
      my $row = join("$srs", @line);
      
	  # join Delimiter "§" escapen
	  $row =~ s/§/|°escaped°|/g;
      
      push(@rows, $row);
      # Anzahl der Datensätze
      $nrows++;
    }
  } else {
     $nrows = $sth->rows;
     eval {$dbh->commit() if(!$dbh->{AutoCommit});};
     if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - ERROR - $@");
         $dbh->disconnect;
         return "$name|''|$opt|$sql|''|''|$err";       
     }
	 
	 push(@rows, $r);
	 my $com = (split(" ",$sql, 2))[0];
	 Log3 ($name, 3, "DbRep $name - Number of entries processed in db $hash->{DATABASE}: $nrows by $com");  
  }
  
  $sth->finish;

  # SQL-Laufzeit ermitteln
  my $rt = tv_interval($st);

  $dbh->disconnect;
 
  # Daten müssen als Einzeiler zurückgegeben werden
  my $rowstring = join("§", @rows); 
  $rowstring = encode_base64($rowstring,"");

  # Background-Laufzeit ermitteln
  my $brt = tv_interval($bst);

  $rt = $rt.",".$brt;
 
  return "$name|$rowstring|$opt|$sql|$nrows|$rt|$err";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage sqlCmd
####################################################################################################
sub sqlCmd_ParseDone($) {
  my ($string)   = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $name       = $hash->{NAME};
  my $rowstring  = decode_base64($a[1]);
  my $opt        = $a[2];
  my $cmd        = $a[3];
  my $nrows      = $a[4];
  my $bt         = $a[5];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[6]?decode_base64($a[6]):undef;
  my $srf        = AttrVal($name, "sqlResultFormat", "separated");
  my $srs        = AttrVal($name, "sqlResultFieldSep", "|");
  
  if ($err) {
    ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
    ReadingsSingleUpdateValue ($hash, "state", "error", 1);
    delete($hash->{HELPER}{RUNNING_PID});
    return;
  }
  
  Log3 ($name, 5, "DbRep $name - SQL result decoded: $rowstring") if($rowstring);
  
  no warnings 'uninitialized'; 
  
  # Readingaufbereitung
  readingsBeginUpdate($hash);

  ReadingsBulkUpdateValue ($hash, "sqlCmd", $cmd); 
  ReadingsBulkUpdateValue ($hash, "sqlResultNumRows", $nrows);
  
  # Drop-Down Liste bisherige sqlCmd-Befehle füllen und in Key-File sichern
  # my $hl      = $hash->{HELPER}{SQLHIST};
  my @sqlhist = split(",",$hash->{HELPER}{SQLHIST});
  $cmd =~ s/\s/&nbsp;/g;
  $cmd =~ s/,/<c>/g;
  my $hlc = AttrVal($name, "sqlCmdHistoryLength", 0);                       # Anzahl der Einträge in Drop-Down Liste
  if(!@sqlhist || (@sqlhist && !($cmd ~~ @sqlhist))) {
      unshift @sqlhist,$cmd;
      pop @sqlhist if(@sqlhist > $hlc);
      my $hl = join(",",@sqlhist);
      $hash->{HELPER}{SQLHIST} = $hl;
      DbRep_setCmdFile($name."_sqlCmdList",$hl,$hash);       
  }
  
  if ($srf eq "sline") {
      $rowstring =~ s/§/]|[/g;
      $rowstring =~ s/\|°escaped°\|/§/g;
      ReadingsBulkUpdateValue ($hash, "SqlResult", $rowstring);
    
  } elsif ($srf eq "table") {
	  my $res = "<html><table border=2 bordercolor='darkgreen' cellspacing=0>";
	  my @rows = split( /§/, $rowstring );
      my $row;
	  foreach $row ( @rows ) {
	      $row =~ s/\|°escaped°\|/§/g;
		  $row =~ s/$srs/\|/g if($srs !~ /\|/);
		  $row =~ s/\|/<\/td><td style='padding-right:5px;padding-left:5px'>/g;
          $res .= "<tr><td style='padding-right:5px;padding-left:5px'>".$row."</td></tr>";
      }
	  $row .= $res."</table></html>";
	  
	  ReadingsBulkUpdateValue ($hash,"SqlResult", $row);	
	  
  } elsif ($srf eq "mline") {
      my $res = "<html>";
	  my @rows = split( /§/, $rowstring );
      my $row;
	  foreach $row ( @rows ) {
	      $row =~ s/\|°escaped°\|/§/g;
          $res .= $row."<br>";
      }
	  $row .= $res."</html>";
	  
      ReadingsBulkUpdateValue ($hash, "SqlResult", $row );
	  
  } elsif ($srf eq "separated") {
      my @rows = split( /§/, $rowstring );
	  my $bigint = @rows;
	  my $numd = ceil(log10($bigint));
	  my $formatstr = sprintf('%%%d.%dd', $numd, $numd);
      my $i = 0;
      foreach my $row ( @rows ) {
          $i++;
          $row =~ s/\|°escaped°\|/§/g;
	      my $fi = sprintf($formatstr, $i);
		  ReadingsBulkUpdateValue ($hash, "SqlResultRow_".$fi, $row);
      }
  } elsif ($srf eq "json") {
      my %result = ();
      my @rows = split( /§/, $rowstring );
	  my $bigint = @rows;
	  my $numd = ceil(log10($bigint));
	  my $formatstr = sprintf('%%%d.%dd', $numd, $numd);
      my $i = 0;
      foreach my $row ( @rows ) {
          $i++;
          $row =~ s/\|°escaped°\|/§/g;
          my $fi = sprintf($formatstr, $i);		  
		  $result{$fi} = $row;
      }
      my $json = toJSON(\%result);   # at least fhem.pl 14348 2017-05-22 20:25:06Z
	  ReadingsBulkUpdateValue ($hash, "SqlResult", $json);
  }

  ReadingsBulkUpdateTimeState($hash,$brt,$rt,"done");
  readingsEndUpdate($hash, 1);
  
  delete($hash->{HELPER}{RUNNING_PID});
  
return;
}

####################################################################################################
# nichtblockierende DB-Abfrage get db Metadaten
####################################################################################################
sub dbmeta_DoParse($) {
 my ($string)    = @_;
 my @a           = split("\\|",$string);
 my $name        = $a[0];
 my $hash        = $defs{$name};
 my $opt         = $a[1];
 my $dbloghash   = $hash->{dbloghash};
 my $dbconn      = $dbloghash->{dbconn};
 my $db          = $hash->{DATABASE};
 my $dbuser      = $dbloghash->{dbuser};
 my $dblogname   = $dbloghash->{NAME};
 my $dbpassword  = $attr{"sec$dblogname"}{secret};
 my $dbmodel     = $dbloghash->{MODEL};
 my $utf8        = defined($hash->{UTF8})?$hash->{UTF8}:0;
 my ($dbh,$sth,$sql);
 my $err;

 # Background-Startzeit
 my $bst = [gettimeofday];
 
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1, mysql_enable_utf8 => $utf8 });};
 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|''|''|$err";
 }
 
 # only for this block because of warnings if details of readings are not set
 no warnings 'uninitialized'; 
  
 # Liste der anzuzeigenden Parameter erzeugen, sonst alle ("%"), abhängig von $opt
 my $param = AttrVal($name, "showVariables", "%") if($opt eq "dbvars");
 $param = AttrVal($name, "showSvrInfo", "[A-Z_]") if($opt eq "svrinfo");
 $param = AttrVal($name, "showStatus", "%") if($opt eq "dbstatus");
 $param = "1" if($opt =~ /tableinfo|procinfo/);    # Dummy-Eintrag für einen Schleifendurchlauf
 my @parlist = split(",",$param); 
 
 # SQL-Startzeit
 my $st = [gettimeofday];
 
 my @row_array;
 
 # due to incompatible changes made in MyQL 5.7.5, see http://johnemb.blogspot.de/2014/09/adding-or-removing-individual-sql-modes.html
 if($dbmodel eq "MYSQL") {
     eval {$dbh->do("SET sql_mode=(SELECT REPLACE(\@\@sql_mode,'ONLY_FULL_GROUP_BY',''));");};
 }
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     $dbh->disconnect;
     return "$name|''|''|''|$err";
 }
 
 if ($opt ne "svrinfo") {
    foreach my $ple (@parlist) {
         if ($opt eq "dbvars") {
             $sql = "show variables like '$ple';";
         } elsif ($opt eq "dbstatus") {
             $sql = "show global status like '$ple';";
         } elsif ($opt eq "tableinfo") {
             $sql = "show Table Status from $db;";
         } elsif ($opt eq "procinfo") {
             $sql = "show full processlist;";
         }

         Log3($name, 4, "DbRep $name - SQL execute: $sql"); 
 
         $sth = $dbh->prepare($sql); 
         eval {$sth->execute();};
 
         if ($@) {
		     # error bei sql-execute
             $err = encode_base64($@,"");
             Log3 ($name, 2, "DbRep $name - $@");
             $dbh->disconnect;
             return "$name|''|''|''|$err";
         
		 } else {
             # kein error bei sql-execute
             if ($opt eq "tableinfo") {
			     $param = AttrVal($name, "showTableInfo", "[A-Z_]");
                 $param =~ s/,/\|/g;
                 $param =~ tr/%//d;
			     while ( my $line = $sth->fetchrow_hashref()) {
				 
				     Log3 ($name, 5, "DbRep $name - SQL result: $line->{Name}, $line->{Version}, $line->{Row_format}, $line->{Rows}, $line->{Avg_row_length}, $line->{Data_length}, $line->{Max_data_length}, $line->{Index_length}, $line->{Data_free}, $line->{Auto_increment}, $line->{Create_time}, $line->{Check_time}, $line->{Collation}, $line->{Checksum}, $line->{Create_options}, $line->{Comment}");
					 
                     if($line->{Name} =~ m/($param)/i) {
				         push(@row_array, $line->{Name}.".engine ".$line->{Engine}) if($line->{Engine});
					     push(@row_array, $line->{Name}.".version ".$line->{Version}) if($line->{Version});
					     push(@row_array, $line->{Name}.".row_format ".$line->{Row_format}) if($line->{Row_format});
					     push(@row_array, $line->{Name}.".number_of_rows ".$line->{Rows}) if($line->{Rows});
					     push(@row_array, $line->{Name}.".avg_row_length ".$line->{Avg_row_length}) if($line->{Avg_row_length});
					     push(@row_array, $line->{Name}.".data_length_MB ".sprintf("%.2f",$line->{Data_length}/1024/1024)) if($line->{Data_length});
					     push(@row_array, $line->{Name}.".max_data_length_MB ".sprintf("%.2f",$line->{Max_data_length}/1024/1024)) if($line->{Max_data_length});
					     push(@row_array, $line->{Name}.".index_length_MB ".sprintf("%.2f",$line->{Index_length}/1024/1024)) if($line->{Index_length});
						 push(@row_array, $line->{Name}.".data_index_length_MB ".sprintf("%.2f",($line->{Data_length}+$line->{Index_length})/1024/1024));
					     push(@row_array, $line->{Name}.".data_free_MB ".sprintf("%.2f",$line->{Data_free}/1024/1024)) if($line->{Data_free});
					     push(@row_array, $line->{Name}.".auto_increment ".$line->{Auto_increment}) if($line->{Auto_increment});
					     push(@row_array, $line->{Name}.".create_time ".$line->{Create_time}) if($line->{Create_time});
					     push(@row_array, $line->{Name}.".update_time ".$line->{Update_time}) if($line->{Update_time});
					     push(@row_array, $line->{Name}.".check_time ".$line->{Check_time}) if($line->{Check_time});
					     push(@row_array, $line->{Name}.".collation ".$line->{Collation}) if($line->{Collation});
					     push(@row_array, $line->{Name}.".checksum ".$line->{Checksum}) if($line->{Checksum});
					     push(@row_array, $line->{Name}.".create_options ".$line->{Create_options}) if($line->{Create_options});
					     push(@row_array, $line->{Name}.".comment ".$line->{Comment}) if($line->{Comment});
                     }
				 }
             } elsif ($opt eq "procinfo") {
			       my $res = "<html><table border=2 bordercolor='darkgreen' cellspacing=0>";
				   $res .= "<tr><td style='padding-right:5px;padding-left:5px;font-weight:bold'>ID</td>";
				   $res .= "<td style='padding-right:5px;padding-left:5px;font-weight:bold'>USER</td>";
				   $res .= "<td style='padding-right:5px;padding-left:5px;font-weight:bold'>HOST</td>";
				   $res .= "<td style='padding-right:5px;padding-left:5px;font-weight:bold'>DB</td>";
				   $res .= "<td style='padding-right:5px;padding-left:5px;font-weight:bold'>CMD</td>";
				   $res .= "<td style='padding-right:5px;padding-left:5px;font-weight:bold'>TIME_Sec</td>";
				   $res .= "<td style='padding-right:5px;padding-left:5px;font-weight:bold'>STATE</td>";
				   $res .= "<td style='padding-right:5px;padding-left:5px;font-weight:bold'>INFO</td>";
				   $res .= "<td style='padding-right:5px;padding-left:5px;font-weight:bold'>PROGRESS</td></tr>";
			       while (my @line = $sth->fetchrow_array()) {
                       Log3 ($name, 4, "DbRep $name - SQL result: @line");
					   my $row = join("|", @line);
					   $row =~ tr/ A-Za-z0-9!"#$%&'()*+,-.\/:;<=>?@[\]^_`{|}~//cd; 
		               $row =~ s/\|/<\/td><td style='padding-right:5px;padding-left:5px'>/g;
                       $res .= "<tr><td style='padding-right:5px;padding-left:5px'>".$row."</td></tr>";
                   }
                   my $tab .= $res."</table></html>";
                   push(@row_array, "ProcessList ".$tab);

			 } else {
			     while (my @line = $sth->fetchrow_array()) {
                     Log3 ($name, 4, "DbRep $name - SQL result: @line");
                     my $row = join("§", @line);
                     $row =~ s/ /_/g;
                     @line = split("§", $row);                     
					 push(@row_array, $line[0]." ".$line[1]);
			     }
			 }
		 } 
         $sth->finish;
     }
 } else {
     $param =~ s/,/\|/g;
     $param =~ tr/%//d;
     # Log3 ($name, 5, "DbRep $name - showDbInfo: $param");
     
     if($dbmodel eq 'SQLITE') {
         my $sf = $dbh->sqlite_db_filename();
         if ($@) {
		     # error bei sql-execute
             $err = encode_base64($@,"");
             Log3 ($name, 2, "DbRep $name - $@");
             $dbh->disconnect;
             return "$name|''|''|''|$err";
         } else {
		     # kein error bei sql-execute
             my $key = "SQLITE_DB_FILENAME";
             push(@row_array, $key." ".$sf) if($key =~ m/($param)/i);
         }
         my @a = split(' ',qx(du -m $hash->{DATABASE})) if ($^O =~ m/linux/i || $^O =~ m/unix/i);
         my $key = "SQLITE_FILE_SIZE_MB";
         push(@row_array, $key." ".$a[0]) if($key =~ m/($param)/i);
     }
     
     my $info;
     while( my ($key,$value) = each(%GetInfoType) ) {
         eval { $info = $dbh->get_info($GetInfoType{"$key"}) };
         if ($@) {
             $err = encode_base64($@,"");
             Log3 ($name, 2, "DbRep $name - $@");
             $dbh->disconnect;
             return "$name|''|''|''|$err";
         } else {
		     if($utf8) {
                 $info = Encode::encode_utf8($info) if($info);
			 }
             push(@row_array, $key." ".$info) if($key =~ m/($param)/i);
         }
     }
 }
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 $dbh->disconnect;
 
 my $rowlist = join('§', @row_array);
 Log3 ($name, 5, "DbRep $name -> row_array: \n@row_array");
 
 # Daten müssen als Einzeiler zurückgegeben werden
 $rowlist = encode_base64($rowlist,"");
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$rowlist|$rt|$opt|0";
}

####################################################################################################
# Auswertungsroutine der nichtblockierenden DB-Abfrage get db Metadaten
####################################################################################################
sub dbmeta_ParseDone($) {
  my ($string) = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $name       = $hash->{NAME};
  my $rowlist    = decode_base64($a[1]);
  my $bt         = $a[2];
  my $opt        = $a[3];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[4]?decode_base64($a[4]):undef;
  
   if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      return;
  }
    
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
  
  # Readingaufbereitung
  readingsBeginUpdate($hash);
  
  my @row_array = split("§", $rowlist);
  Log3 ($name, 5, "DbRep $name - SQL result decoded: \n@row_array") if(@row_array);
  
  my $pre = "";
  $pre    = "VAR_" if($opt eq "dbvars");
  $pre    = "STAT_" if($opt eq "dbstatus");
  $pre    = "INFO_" if($opt eq "tableinfo");
  
  foreach my $row (@row_array) {
      my @a = split(" ", $row, 2);
      my $k = $a[0];
      my $v = $a[1];
	  ReadingsBulkUpdateValue ($hash, $pre.$k, $v);
  }
  
  ReadingsBulkUpdateTimeState($hash,$brt,$rt,"done");
  readingsEndUpdate($hash, 1);
  
  # InternalTimer(time+0.5, "browser_refresh", $hash, 0);
  
  delete($hash->{HELPER}{RUNNING_PID});
  
return;
}

####################################################################################################
#                             optimize Tables alle Datenbanken 
####################################################################################################
sub DbRep_optimizeTables($) {
 my ($name)        = @_;
 my $hash          = $defs{$name};
 my $dbloghash     = $hash->{dbloghash};
 my $dbconn        = $dbloghash->{dbconn};
 my $dbuser        = $dbloghash->{dbuser};
 my $dblogname     = $dbloghash->{NAME};
 my $dbmodel       = $dbloghash->{MODEL};
 my $dbpassword    = $attr{"sec$dblogname"}{secret};
 my $dbname        = $hash->{DATABASE};
 my $value         = 0;
 my ($dbh,$sth,$query,$err,$r,$db_MB_start,$db_MB_end);
 my (%db_tables,@tablenames);
 
 # Background-Startzeit
 my $bst = [gettimeofday];
 
 # Verbindung mit DB
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 if ($@) {
	 $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|$err|''|''";
 }
 
 # SQL-Startzeit
 my $st = [gettimeofday];
 
 if ($dbmodel =~ /MYSQL/) {
     # Eigenschaften der vorhandenen Tabellen ermitteln (SHOW TABLE STATUS -> Rows sind nicht exakt !!)
     $query = "SHOW TABLE STATUS FROM `$dbname`";
 
     Log3 ($name, 5, "DbRep $name - current query: $query ");
     Log3 ($name, 3, "DbRep $name - Searching for tables inside database $dbname....");
    
     eval { $sth = $dbh->prepare($query);
            $sth->execute;
	      };
     if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - Error executing: '".$query."' ! MySQL-Error: ".$@);
		 $sth->finish;
		 $dbh->disconnect;
         return "$name|''|$err|''|''";
     }
    
     while ( $value = $sth->fetchrow_hashref()) {
	     # verbose 5 logging
	     Log3 ($name, 5, "DbRep $name - ......... Table definition found: .........");
         foreach my $tk (sort(keys(%$value))) {
             Log3 ($name, 5, "DbRep $name - $tk: $value->{$tk}") if(defined($value->{$tk}) && $tk ne "Rows");
         }
	     Log3 ($name, 5, "DbRep $name - ......... Table definition END ............");
	 
         # check for old MySQL3-Syntax Type=xxx   
	     if (defined $value->{Type}) {
             # port old index type to index engine, so we can use the index Engine in the rest of the script
             $value->{Engine} = $value->{Type}; 
         }
         $db_tables{$value->{Name}} = $value;
    
     }

     @tablenames = sort(keys(%db_tables));
 
     if (@tablenames < 1) {
         $err = "There are no tables inside database $dbname ! It doesn't make sense to backup an empty database. Skipping this one.";
	     Log3 ($name, 2, "DbRep $name - $err");
	     $err = encode_base64($@,"");
		 $sth->finish;
		 $dbh->disconnect;
         return "$name|''|$err|''|''";
     }

     # Tabellen optimieren 
	 $hash->{HELPER}{DBTABLES} = \%db_tables;
     ($err,$db_MB_start,$db_MB_end) = DbRep_mysqlOptimizeTables($hash,$dbh,@tablenames);
	 if ($err) {
	     $err = encode_base64($err,"");
		 return "$name|''|$err|''|''";
	 }
 }
 
 if ($dbmodel =~ /SQLITE/) {
	 # Anfangsgröße ermitteln
     $db_MB_start = (split(' ',qx(du -m $hash->{DATABASE})))[0] if ($^O =~ m/linux/i || $^O =~ m/unix/i);
     Log3 ($name, 3, "DbRep $name - Size of database $dbname before optimize (MB): $db_MB_start");
     $query  ="VACUUM";
	 Log3 ($name, 5, "DbRep $name - current query: $query ");
 
     Log3 ($name, 3, "DbRep $name - VACUUM database $dbname....");
     eval {$sth = $dbh->prepare($query);
           $r = $sth->execute();
          }; 
	 if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - Error executing: '".$query."' ! SQLite-Error: ".$@);
		 $sth->finish;
		 $dbh->disconnect;
         return "$name|''|$err|''|''";
	 }
	 
	 # Endgröße ermitteln
	 $db_MB_end = (split(' ',qx(du -m $hash->{DATABASE})))[0] if ($^O =~ m/linux/i || $^O =~ m/unix/i);
	 Log3 ($name, 3, "DbRep $name - Size of database $dbname after optimize (MB): $db_MB_end");
 }
  
 if ($dbmodel =~ /POSTGRESQL/) {
     # Anfangsgröße ermitteln
     $query = "SELECT pg_size_pretty(pg_database_size('$dbname'))"; 
     Log3 ($name, 5, "DbRep $name - current query: $query ");
     eval { $sth = $dbh->prepare($query);
            $sth->execute;
	      };
     if ($@) {
	     $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - Error executing: '".$query."' ! PostgreSQL-Error: ".$@);
	     $sth->finish;
	     $dbh->disconnect;
         return "$name|''|$err|''|''";
     }
     
	 $value = $sth->fetchrow();
	 $value =~ tr/MB//d;
     $db_MB_start = sprintf("%.2f",$value);
     Log3 ($name, 3, "DbRep $name - Size of database $dbname before optimize (MB): $db_MB_start");
     
     Log3 ($name, 3, "DbRep $name - VACUUM database $dbname....");
     
	 $query = "vacuum history";
	 
	 Log3 ($name, 5, "DbRep $name - current query: $query ");
 
     eval {$sth = $dbh->prepare($query);
           $sth->execute();
          }; 
	 if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - Error executing: '".$query."' ! PostgreSQL-Error: ".$@);
		 $sth->finish;
		 $dbh->disconnect;
         return "$name|''|$err|''|''";
	 }
	 
	 # Endgröße ermitteln
     $query = "SELECT pg_size_pretty(pg_database_size('$dbname'))"; 
     Log3 ($name, 5, "DbRep $name - current query: $query ");
     eval { $sth = $dbh->prepare($query);
            $sth->execute;
	      };
     if ($@) {
	     $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - Error executing: '".$query."' ! PostgreSQL-Error: ".$@);
	     $sth->finish;
	     $dbh->disconnect;
         return "$name|''|$err|''|''";
     }
     
	 $value = $sth->fetchrow();
	 $value =~ tr/MB//d;
	 $db_MB_end = sprintf("%.2f",$value);
	 Log3 ($name, 3, "DbRep $name - Size of database $dbname after optimize (MB): $db_MB_end");
 }
  
 $sth->finish;
 $dbh->disconnect;
  
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);

 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 Log3 ($name, 3, "DbRep $name - Optimize tables of database $dbname finished, total time used: ".sprintf("%.0f",$brt)." sec.");
 
return "$name|$rt|''|$db_MB_start|$db_MB_end";
}

####################################################################################################
#             Auswertungsroutine optimize tables
####################################################################################################
sub DbRep_OptimizeDone($) {
  my ($string)     = @_;
  my @a            = split("\\|",$string);
  my $hash         = $defs{$a[0]};
  my $bt           = $a[1];
  my ($rt,$brt)    = split(",", $bt);
  my $err          = $a[2]?decode_base64($a[2]):undef;
  my $db_MB_start  = $a[3];
  my $db_MB_end    = $a[4];
  my $name         = $hash->{NAME};
  my $erread;
  
  delete($hash->{HELPER}{RUNNING_OPTIMIZE});
  
  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      return;
  } 
 
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
    
  readingsBeginUpdate($hash);
  ReadingsBulkUpdateValue($hash, "SizeDbBegin_MB", $db_MB_start);
  ReadingsBulkUpdateValue($hash, "SizeDbEnd_MB", $db_MB_end);
  readingsEndUpdate($hash, 1);
  
  # Befehl nach Procedure ausführen
  $erread = DbRep_afterproc($hash, "optimize");
  
  my $state = $erread?$erread:"optimize tables finished";
  readingsBeginUpdate($hash);
  ReadingsBulkUpdateTimeState($hash,$brt,undef,$state);
  readingsEndUpdate($hash, 1);

  Log3 ($name, 3, "DbRep $name - Optimize tables finished successfully. ");
  
return;
}

####################################################################################################
# nicht blockierende Dump-Routine für MySQL (clientSide)
####################################################################################################
sub mysql_DoDumpClientSide($) {
 my ($name)                     = @_;
 my $hash                       = $defs{$name};
 my $dbloghash                  = $hash->{dbloghash};
 my $dbconn                     = $dbloghash->{dbconn};
 my $dbuser                     = $dbloghash->{dbuser};
 my $dblogname                  = $dbloghash->{NAME};
 my $dbpassword                 = $attr{"sec$dblogname"}{secret};
 my $dbname                     = $hash->{DATABASE};
 my $dump_path_def              = $attr{global}{modpath}."/log/";
 my $dump_path                  = AttrVal($name, "dumpDirLocal", $dump_path_def);
 $dump_path                     = $dump_path."/" unless($dump_path =~ m/\/$/);
 my $optimize_tables_beforedump = AttrVal($name, "optimizeTablesBeforeDump", 0);
 my $memory_limit               = AttrVal($name, "dumpMemlimit", 100000);
 my $my_comment                 = AttrVal($name, "dumpComment", "");
 my $dumpspeed                  = AttrVal($name, "dumpSpeed", 10000);
 my $ebd                        = AttrVal($name, "executeBeforeProc", undef);
 my $ead                        = AttrVal($name, "executeAfterProc", undef);
 my $mysql_commentstring        = "-- ";
 my $character_set              = "utf8";
 my $repver                     = $hash->{VERSION};
 my $sql_text                   = '';
 my $sql_file                   = '';
 my $dbpraefix                  = "";
 my ($dbh,$sth,$tablename,$sql_create,$rct,$insert,$first_insert,$backupfile,$drc,$drh,
     $sql_daten,$inhalt,$filesize,$totalrecords,$status_start,$status_end,$err,$db_MB_start,$db_MB_end);
 my (@ar,@tablerecords,@tablenames,@tables,@ergebnis);
 my (%db_tables);
 
 # Background-Startzeit
 my $bst = [gettimeofday];
 
 Log3 ($name, 3, "DbRep $name - Starting dump of database '$dbname'");

 #####################  Beginn Dump  ######################## 
 ##############################################################
	 
 undef(%db_tables);

 # Startzeit ermitteln 
 my ($Sekunden, $Minuten, $Stunden, $Monatstag, $Monat, $Jahr, $Wochentag, $Jahrestag, $Sommerzeit) = localtime(time);
 $Jahr      += 1900;
 $Monat     += 1;
 $Jahrestag += 1;
 my $CTIME_String = strftime "%Y-%m-%d %T",localtime(time);
 my $time_stamp   = $Jahr."_".sprintf("%02d",$Monat)."_".sprintf("%02d",$Monatstag)."_".sprintf("%02d",$Stunden)."_".sprintf("%02d",$Minuten);
 my $starttime    = sprintf("%02d",$Monatstag).".".sprintf("%02d",$Monat).".".$Jahr."  ".sprintf("%02d",$Stunden).":".sprintf("%02d",$Minuten);
    
 my $fieldlist = "";
	
 # Verbindung mit DB
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 if ($@) {
	 $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|$err|''|''|''|''|''|''|''";
 }
 
 # SQL-Startzeit
 my $st = [gettimeofday];
 
 #####################  Mysql-Version ermitteln  ######################## 
 eval { $sth = $dbh->prepare("SELECT VERSION()");
        $sth->execute;
	  };
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
	 $dbh->disconnect;
     return "$name|''|$err|''|''|''|''|''|''|''";
 }
  
 my @mysql_version = $sth->fetchrow;
 my @v             = split(/\./,$mysql_version[0]);

 if($v[0] >= 5 || ($v[0] >= 4 && $v[1] >= 1) ) {
     # mysql Version >= 4.1
     $sth = $dbh->prepare("SET NAMES '".$character_set."'");
     $sth->execute;
     # get standard encoding of MySQl-Server
     $sth = $dbh->prepare("SHOW VARIABLES LIKE 'character_set_connection'");
     $sth->execute;
     @ar = $sth->fetchrow; 
     $character_set = $ar[1];
 } else {
     # mysql Version < 4.1 -> no SET NAMES available
     # get standard encoding of MySQl-Server
     $sth = $dbh->prepare("SHOW VARIABLES LIKE 'character_set'");
     $sth->execute;
     @ar = $sth->fetchrow; 
     if (defined($ar[1])) { $character_set=$ar[1]; }
 }
 Log3 ($name, 3, "DbRep $name - Characterset of collection and backup file set to $character_set. ");
    
 
 # Eigenschaften der vorhandenen Tabellen ermitteln (SHOW TABLE STATUS -> Rows sind nicht exakt !!)
 undef(@tables);
 undef(@tablerecords);
 my %db_tables_views;
 my $t      = 0;
 my $r      = 0;
 my $st_e   = "\n";
 my $value  = 0;
 my $engine = '';
 my $query  ="SHOW TABLE STATUS FROM `$dbname`";
 
 Log3 ($name, 5, "DbRep $name - current query: $query ");
 
 if ($dbpraefix ne "") {
     $query.=" LIKE '$dbpraefix%'"; 
	 Log3 ($name, 3, "DbRep $name - Searching for tables inside database $dbname with prefix $dbpraefix....");
 } else {
	 Log3 ($name, 3, "DbRep $name - Searching for tables inside database $dbname....");
 }
    
 eval { $sth = $dbh->prepare($query);
        $sth->execute;
	  };
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - Error executing: '".$query."' ! MySQL-Error: ".$@);
	 $dbh->disconnect;
     return "$name|''|$err|''|''|''|''|''|''|''";
 }
    
 while ( $value = $sth->fetchrow_hashref()) {
     $value->{skip_data} = 0;         #defaut -> backup data of table
	 
	 # verbose 5 logging
	 Log3 ($name, 5, "DbRep $name - ......... Table definition found: .........");
     foreach my $tk (sort(keys(%$value))) {
         Log3 ($name, 5, "DbRep $name - $tk: $value->{$tk}") if(defined($value->{$tk}) && $tk ne "Rows");
     }
	 Log3 ($name, 5, "DbRep $name - ......... Table definition END ............");
	 
	 # decide if we need to skip the data while dumping (VIEWs and MEMORY)
     # check for old MySQL3-Syntax Type=xxx 
     
	 if (defined $value->{Type}) {
         # port old index type to index engine, so we can use the index Engine in the rest of the script
         $value->{Engine} = $value->{Type}; 
         $engine = uc($value->{Type});
         
		 if ($engine eq "MEMORY") {
             $value->{skip_data} = 1;
         }
     }

     # check for > MySQL3 Engine = xxx 
     if (defined $value->{Engine}) {
         $engine = uc($value->{Engine});
         
		 if ($engine eq "MEMORY") {
             $value->{skip_data} = 1;
         }
     }

     # check for Views - if it is a view the comment starts with "VIEW" 
     if (defined $value->{Comment} && uc(substr($value->{Comment},0,4)) eq 'VIEW') {
         $value->{skip_data}   = 1;
         $value->{Engine}      = 'VIEW'; 
         $value->{Update_time} = '';
         $db_tables_views{$value->{Name}} = $value;
     } else {
         $db_tables{$value->{Name}} = $value;
     }
         
     # cast indexes to int, cause they are used for builing the statusline
     $value->{Rows}         += 0;
     $value->{Data_length}  += 0;
     $value->{Index_length} += 0;
 }
 $sth->finish;

 @tablenames = sort(keys(%db_tables));
 
 # add VIEW at the end as they need all tables to be created before
 @tablenames = (@tablenames,sort(keys(%db_tables_views)));
 %db_tables  = (%db_tables,%db_tables_views);
 $tablename  = '';
 
 if (@tablenames < 1) {
     $err = "There are no tables inside database $dbname ! It doesn't make sense to backup an empty database. Skipping this one.";
	 Log3 ($name, 2, "DbRep $name - $err");
	 $err = encode_base64($@,"");
	 $dbh->disconnect;
     return "$name|''|$err|''|''|''|''|''|''|''";
 }

 if($optimize_tables_beforedump) {
     # Tabellen optimieren vor dem Dump
	 $hash->{HELPER}{DBTABLES} = \%db_tables;
     ($err,$db_MB_start,$db_MB_end) = DbRep_mysqlOptimizeTables($hash,$dbh,@tablenames);
	 if ($err) {
	     $err = encode_base64($err,"");
		 return "$name|''|$err|''|''|''|''|''|''|''";
	 }
 }
    
 # Tabelleneigenschaften für SQL-File ermitteln
 $st_e .= "-- TABLE-INFO\n";
    
 foreach $tablename (@tablenames) {
     my $dump_table = 1;
     
	 if ($dbpraefix ne "") {
         if (substr($tablename,0,length($dbpraefix)) ne $dbpraefix) {
             # exclude table from backup because it doesn't fit to praefix
             $dump_table = 0;
         }
     }
                        
     if ($dump_table == 1) {
         # how many rows
		 $sql_create = "SELECT count(*) FROM `$tablename`";
		 eval { $sth = $dbh->prepare($sql_create); 
		        $sth->execute;
			      };
         if ($@) {
		     $err = "Fatal error sending Query '".$sql_create."' ! MySQL-Error: ".$@;
             Log3 ($name, 2, "DbRep $name - $err");
			 $err = encode_base64($@,"");
			 $dbh->disconnect;
             return "$name|''|$err|''|''|''|''|''|''|''";
         }
	     $db_tables{$tablename}{Rows} = $sth->fetchrow;
         $sth->finish;  
         
		 $r += $db_tables{$tablename}{Rows};
         push(@tables,$db_tables{$tablename}{Name});    # add tablename to backuped tables
         $t++;
         
		 if (!defined $db_tables{$tablename}{Update_time}) {
             $db_tables{$tablename}{Update_time} = 0;
         }
            
         $st_e .= $mysql_commentstring."TABLE: $db_tables{$tablename}{Name} | Rows: $db_tables{$tablename}{Rows} | Length: ".($db_tables{$tablename}{Data_length}+$db_tables{$tablename}{Index_length})." | Engine: $db_tables{$tablename}{Engine}\n";
         if($db_tables{$tablename}{Name} eq "current") {
		     $drc = $db_tables{$tablename}{Rows};
		 }
         if($db_tables{$tablename}{Name} eq "history") {
		     $drh = $db_tables{$tablename}{Rows};
		 }
	 }
 }
 $st_e .= "-- EOF TABLE-INFO";
    
 Log3 ($name, 3, "DbRep $name - Found ".(@tables)." tables with $r records.");

 # AUFBAU der Statuszeile in SQL-File:
 # -- Status | tabellenzahl | datensaetze | Datenbankname | Kommentar | MySQLVersion | Charset | EXTINFO
 #
 $status_start = $mysql_commentstring."Status | Tables: $t | Rows: $r ";
 $status_end   = "| DB: $dbname | Comment: $my_comment | MySQL-Version: $mysql_version[0] ";
 $status_end  .= "| Charset: $character_set $st_e\n".
                 $mysql_commentstring."Dump created on $CTIME_String by DbRep-Version $repver\n".$mysql_commentstring;

 $sql_text = $status_start.$status_end;
 
 # neues SQL-Ausgabefile anlegen
 ($sql_text,$first_insert,$sql_file,$backupfile,$err) = DbRep_NewDumpFilename($sql_text,$dump_path,$dbname,$time_stamp,$character_set);
 if ($err) {
     Log3 ($name, 2, "DbRep $name - $err");
	 $err = encode_base64($err,"");
     return "$name|''|$err|''|''|''|''|''|''|''";
 } else {
     Log3 ($name, 5, "DbRep $name - New dumpfile $sql_file has been created.");
 }
 
 #####################  jede einzelne Tabelle dumpen  ########################    
	
 $totalrecords = 0;
 
 foreach $tablename (@tables) {
     # first get CREATE TABLE Statement 
     if($dbpraefix eq "" || ($dbpraefix ne "" && substr($tablename,0,length($dbpraefix)) eq $dbpraefix)) {
         Log3 ($name, 3, "DbRep $name - Dumping table $tablename (Type ".$db_tables{$tablename}{Engine}."):");
			
		 $a = "\n\n$mysql_commentstring\n$mysql_commentstring"."Table structure for table `$tablename`\n$mysql_commentstring\n";
            
		 if ($db_tables{$tablename}{Engine} ne 'VIEW' ) {
             $a .= "DROP TABLE IF EXISTS `$tablename`;\n";
         } else {
             $a .= "DROP VIEW IF EXISTS `$tablename`;\n";
         }
         
		 $sql_text  .= $a;
         $sql_create = "SHOW CREATE TABLE `$tablename`";
		 
		 Log3 ($name, 5, "DbRep $name - current query: $sql_create ");
         
		 eval { $sth = $dbh->prepare($sql_create);
		        $sth->execute;
		      };
		 if ($@) {
			 $err = "Fatal error sending Query '".$sql_create."' ! MySQL-Error: ".$@;
             Log3 ($name, 2, "DbRep $name - $err");
			 $err = encode_base64($@,"");
			 $dbh->disconnect;
             return "$name|''|$err|''|''|''|''|''|''|''";
         }
         
		 @ergebnis = $sth->fetchrow;
         $sth->finish;
         $a = $ergebnis[1].";\n";
         
		 if (length($a) < 10) {
             $err = "Fatal error! Couldn't read CREATE-Statement of table `$tablename`! This backup might be incomplete! Check your database for errors. MySQL-Error: ".$DBI::errstr;
             Log3 ($name, 2, "DbRep $name - $err");
         } else {
             $sql_text .= $a;
			 # verbose 5 logging
             Log3 ($name, 5, "DbRep $name - Create-SQL found:\n$a");
         }
            
         if ($db_tables{$tablename}{skip_data} == 0) {
             $sql_text .= "\n$mysql_commentstring\n$mysql_commentstring"."Dumping data for table `$tablename`\n$mysql_commentstring\n";
             $sql_text .= "/*!40000 ALTER TABLE `$tablename` DISABLE KEYS */;";

             DbRep_WriteToDumpFile($sql_text,$sql_file);
             $sql_text = "";

             # build fieldlist
             $fieldlist  = "(";
             $sql_create = "SHOW FIELDS FROM `$tablename`";
			 Log3 ($name, 5, "DbRep $name - current query: $sql_create ");
             
			 eval { $sth = $dbh->prepare($sql_create); 
			        $sth->execute;
			      };
             if ($@) {
				 $err = "Fatal error sending Query '".$sql_create."' ! MySQL-Error: ".$@;
                 Log3 ($name, 2, "DbRep $name - $err");
				 $err = encode_base64($@,"");
				 $dbh->disconnect;
                 return "$name|''|$err|''|''|''|''|''|''|''";
             }
             
			 while (@ar = $sth->fetchrow) {
                 $fieldlist .= "`".$ar[0]."`,";
             }
             $sth->finish;
			 
			 # verbose 5 logging
             Log3 ($name, 5, "DbRep $name - Fieldlist found: $fieldlist");
                
             # remove trailing ',' and add ')'
             $fieldlist = substr($fieldlist,0,length($fieldlist)-1).")";

             # how many rows
             $rct = $db_tables{$tablename}{Rows};               
			 Log3 ($name, 5, "DbRep $name - Number entries of table $tablename: $rct");

			 # create insert Statements
             for (my $ttt = 0; $ttt < $rct; $ttt += $dumpspeed) {
                 # default beginning for INSERT-String
                 $insert       = "INSERT INTO `$tablename` $fieldlist VALUES (";
                 $first_insert = 0;
                    
                 # get rows (parts)
                 $sql_daten = "SELECT * FROM `$tablename` LIMIT ".$ttt.",".$dumpspeed.";";
                    
				 eval { $sth = $dbh->prepare($sql_daten); 
				        $sth->execute;
				      };
				 if ($@) {
				     $err = "Fatal error sending Query '".$sql_daten."' ! MySQL-Error: ".$@;
                     Log3 ($name, 2, "DbRep $name - $err");
					 $err = encode_base64($@,"");
					 $dbh->disconnect;
                     return "$name|''|$err|''|''|''|''|''|''|''";
                 }
                    
				 while ( @ar = $sth->fetchrow) {
                     #Start the insert
                     if($first_insert == 0) {
                         $a = "\n$insert";
                     } else {
                         $a = "\n(";
                     }
                        
                     # quote all values
                     foreach $inhalt(@ar) { $a .= $dbh->quote($inhalt).","; }
                        
                     # remove trailing ',' and add end-sql
                     $a         = substr($a,0, length($a)-1).");";
                     $sql_text .= $a;
                        
					 if($memory_limit > 0 && length($sql_text) > $memory_limit) {
                         ($filesize,$err) = DbRep_WriteToDumpFile($sql_text,$sql_file);
						 # Log3 ($name, 5, "DbRep $name - Memory limit '$memory_limit' exceeded. Wrote to '$sql_file'. Filesize: '".DbRep_byteOutput($filesize)."'");
                         $sql_text = "";
                     }
                 }
                 $sth->finish;
             }
             $sql_text .= "\n/*!40000 ALTER TABLE `$tablename` ENABLE KEYS */;\n";
         }

         # write sql commands to file
         ($filesize,$err) = DbRep_WriteToDumpFile($sql_text,$sql_file);
         $sql_text = "";

         if ($db_tables{$tablename}{skip_data} == 0) {
             Log3 ($name, 3, "DbRep $name - $rct records inserted (size of backupfile: ".DbRep_byteOutput($filesize).")");
		     $totalrecords += $rct;
         } else {
		     Log3 ($name, 3, "DbRep $name - Dumping structure of $tablename (Type ".$db_tables{$tablename}{Engine}." ) (size of backupfile: ".DbRep_byteOutput($filesize).")");
         }
            
     }
 }
   
 # end
 DbRep_WriteToDumpFile("\nSET FOREIGN_KEY_CHECKS=1;\n",$sql_file);
 ($filesize,$err) = DbRep_WriteToDumpFile($mysql_commentstring."EOB\n",$sql_file);
 
 # Datenbankverbindung schliessen
 $sth->finish() if (defined $sth);
 $dbh->disconnect();
 
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 # Dumpfile komprimieren wenn dumpCompress=1
 my $compress = AttrVal($name,"dumpCompress",0);
 if($compress) {
     # $err nicht auswerten -> wenn compress fehlerhaft wird unkomprimiertes dumpfile verwendet
     ($err,$backupfile) = DbRep_dumpCompress($hash,$backupfile);
     $filesize = (stat("$dump_path$backupfile"))[7];
 }
 
 # Dumpfile per FTP senden und versionieren
 my ($ftperr,$ftpmsg,@ftpfd) = DbRep_sendftp($hash,$backupfile); 
 my $ftp = $ftperr?encode_base64($ftperr,""):$ftpmsg?encode_base64($ftpmsg,""):0;
 my $ffd = join(", ", @ftpfd);
 $ffd    = $ffd?encode_base64($ffd,""):0;
 
 # alte Dumpfiles löschen
 my @fd  = DbRep_deldumpfiles($hash,$backupfile);
 my $bfd = join(", ", @fd );
 $bfd    = $bfd?encode_base64($bfd,""):0;

 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 my $fsize = DbRep_byteOutput($filesize);
 $fsize = encode_base64($fsize,"");
 
 Log3 ($name, 3, "DbRep $name - Finished backup of database $dbname, total time used: ".sprintf("%.0f",$brt)." sec.");
 
return "$name|$rt|''|$dump_path$backupfile|$drc|$drh|$fsize|$ftp|$bfd|$ffd";
}

####################################################################################################
#                  nicht blockierende Dump-Routine für MySQL (serverSide)
####################################################################################################
sub mysql_DoDumpServerSide($) {
 my ($name)                     = @_;
 my $hash                       = $defs{$name};
 my $dbloghash                  = $hash->{dbloghash};
 my $dbconn                     = $dbloghash->{dbconn};
 my $dbuser                     = $dbloghash->{dbuser};
 my $dblogname                  = $dbloghash->{NAME};
 my $dbpassword                 = $attr{"sec$dblogname"}{secret};
 my $dbname                     = $hash->{DATABASE};
 my $optimize_tables_beforedump = AttrVal($name, "optimizeTablesBeforeDump", 0);
 my $dump_path_rem              = AttrVal($name, "dumpDirRemote", "./");
 $dump_path_rem                 = $dump_path_rem."/" unless($dump_path_rem =~ m/\/$/);
 my $ebd                        = AttrVal($name, "executeBeforeProc", undef);
 my $ead                        = AttrVal($name, "executeAfterProc", undef);
 my $table                      = "history";
 my ($dbh,$sth,$err,$db_MB_start,$db_MB_end,$drh);
 my (%db_tables,@tablenames);
 
 # Background-Startzeit
 my $bst = [gettimeofday];
 
 # Verbindung mit DB
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 if ($@) {
	 $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|$err|''|''|''|''|''|''|''";
 }
 
 # Eigenschaften der vorhandenen Tabellen ermitteln (SHOW TABLE STATUS -> Rows sind nicht exakt !!)
 my $value  = 0;
 my $query  ="SHOW TABLE STATUS FROM `$dbname`";
 
 Log3 ($name, 5, "DbRep $name - current query: $query ");
 
 Log3 ($name, 3, "DbRep $name - Searching for tables inside database $dbname....");
    
 eval { $sth = $dbh->prepare($query);
        $sth->execute;
	  };
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - Error executing: '".$query."' ! MySQL-Error: ".$@);
	 $dbh->disconnect;
     return "$name|''|$err|''|''|''|''|''|''|''";
 }
    
 while ( $value = $sth->fetchrow_hashref()) {
	 # verbose 5 logging
	 Log3 ($name, 5, "DbRep $name - ......... Table definition found: .........");
     foreach my $tk (sort(keys(%$value))) {
         Log3 ($name, 5, "DbRep $name - $tk: $value->{$tk}") if(defined($value->{$tk}) && $tk ne "Rows");
     }
	 Log3 ($name, 5, "DbRep $name - ......... Table definition END ............");
	 
     # check for old MySQL3-Syntax Type=xxx   
	 if (defined $value->{Type}) {
         # port old index type to index engine, so we can use the index Engine in the rest of the script
         $value->{Engine} = $value->{Type}; 
     }
     $db_tables{$value->{Name}} = $value;
    
 }
 $sth->finish;

 @tablenames = sort(keys(%db_tables));
 
 if (@tablenames < 1) {
     $err = "There are no tables inside database $dbname ! It doesn't make sense to backup an empty database. Skipping this one.";
	 Log3 ($name, 2, "DbRep $name - $err");
	 $err = encode_base64($@,"");
	 $dbh->disconnect;
     return "$name|''|$err|''|''|''|''|''|''|''";
 }
 
 if($optimize_tables_beforedump) {
     # Tabellen optimieren vor dem Dump
	 $hash->{HELPER}{DBTABLES} = \%db_tables;
     ($err,$db_MB_start,$db_MB_end) = DbRep_mysqlOptimizeTables($hash,$dbh,@tablenames);
	 if ($err) {
	     $err = encode_base64($err,"");
		 return "$name|''|$err|''|''|''|''|''|''|''";
	 }
 }
 
 Log3 ($name, 3, "DbRep $name - Starting dump of database '$dbname', table '$table'");

 # Startzeit ermitteln 
 my ($Sekunden, $Minuten, $Stunden, $Monatstag, $Monat, $Jahr, $Wochentag, $Jahrestag, $Sommerzeit) = localtime(time);
 $Jahr      += 1900;
 $Monat     += 1;
 $Jahrestag += 1;
 my $time_stamp = $Jahr."_".sprintf("%02d",$Monat)."_".sprintf("%02d",$Monatstag)."_".sprintf("%02d",$Stunden)."_".sprintf("%02d",$Minuten);
 
 my $bfile = $dbname."_".$table."_".$time_stamp.".csv";
 Log3 ($name, 5, "DbRep $name - Use Outfile: $dump_path_rem$bfile");

 # SQL-Startzeit
 my $st = [gettimeofday];

 my $sql = "SELECT * FROM history INTO OUTFILE '$dump_path_rem$bfile' FIELDS TERMINATED BY ',' ENCLOSED BY '\"' LINES TERMINATED BY '\n'; ";

 eval {$sth = $dbh->prepare($sql);
       $drh = $sth->execute();
      }; 
  
  if ($@) {
     # error bei sql-execute
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
	 $dbh->disconnect;
     return "$name|''|$err|''|''|''|''|''|''|''";     
  }
  
 $sth->finish;
 $dbh->disconnect;
  
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);

 # Dumpfile komprimieren wenn dumpCompress=1
 my $compress = AttrVal($name,"dumpCompress",0);
 if($compress) {
     # $err nicht auswerten -> wenn compress fehlerhaft wird unkomprimiertes dumpfile verwendet
     ($err,$bfile) = DbRep_dumpCompress($hash,$bfile);
 }
 
 # Größe Dumpfile ermitteln ("dumpDirRemote" muß auf "dumpDirLocal" gemountet sein) 
 my $dump_path_def = $attr{global}{modpath}."/log/";
 my $dump_path_loc = AttrVal($name,"dumpDirLocal", $dump_path_def);
 $dump_path_loc    = $dump_path_loc."/" unless($dump_path_loc =~ m/\/$/);
 my $filesize = (stat($dump_path_loc.$bfile))[7]?(stat($dump_path_loc.$bfile))[7]:"n.a.";
 
 Log3 ($name, 3, "DbRep $name - Number of exported datasets: $drh");
 Log3 ($name, 3, "DbRep $name - Size of backupfile: ".DbRep_byteOutput($filesize));
 
 # Dumpfile per FTP senden und versionieren
 my ($ftperr,$ftpmsg,@ftpfd) = DbRep_sendftp($hash,$bfile); 
 my $ftp = $ftperr?encode_base64($ftperr,""):$ftpmsg?encode_base64($ftpmsg,""):0;
 my $ffd = join(", ", @ftpfd);
 $ffd    = $ffd?encode_base64($ffd,""):0;
 
 # alte Dumpfiles löschen
 my @fd  = DbRep_deldumpfiles($hash,$bfile);
 my $bfd = join(", ", @fd );
 $bfd    = $bfd?encode_base64($bfd,""):0;
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);
 
 my $fsize = DbRep_byteOutput($filesize);
 $fsize = encode_base64($fsize,"");

 $rt = $rt.",".$brt;
 
 Log3 ($name, 3, "DbRep $name - Finished backup of database $dbname - total time used: ".sprintf("%.0f",$brt)." seconds");
 
return "$name|$rt|''|$dump_path_rem$bfile|n.a.|$drh|$fsize|$ftp|$bfd|$ffd";
}

####################################################################################################
#                                      Dump-Routine SQLite
####################################################################################################
sub DbRep_sqliteDoDump($) {
 my ($name)                     = @_;
 my $hash                       = $defs{$name};
 my $dbloghash                  = $hash->{dbloghash};
 my $dbname                     = $hash->{DATABASE};
 my $dbconn                     = $dbloghash->{dbconn};
 my $dbuser                     = $dbloghash->{dbuser};
 my $dblogname                  = $dbloghash->{NAME};
 my $dbpassword                 = $attr{"sec$dblogname"}{secret};
 my $dump_path_def              = $attr{global}{modpath}."/log/";
 my $dump_path                  = AttrVal($name, "dumpDirLocal", $dump_path_def);
 $dump_path                     = $dump_path."/" unless($dump_path =~ m/\/$/);
 my $optimize_tables_beforedump = AttrVal($name, "optimizeTablesBeforeDump", 0);
 my $ebd                        = AttrVal($name, "executeBeforeProc", undef);
 my $ead                        = AttrVal($name, "executeAfterProc", undef);
 my ($dbh,$err,$db_MB,$r,$query,$sth);
 
 # Background-Startzeit
 my $bst = [gettimeofday];
 
 # Verbindung mit DB
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 if ($@) {
	 $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|$err|''|''|''|''|''|''|''";
 }
  
 if($optimize_tables_beforedump) {
     # Vacuum vor Dump
	 # Anfangsgröße ermitteln
     $db_MB = (split(' ',qx(du -m $dbname)))[0] if ($^O =~ m/linux/i || $^O =~ m/unix/i);
     Log3 ($name, 3, "DbRep $name - Size of database $dbname before optimize (MB): $db_MB");
     $query  ="VACUUM";
	 Log3 ($name, 5, "DbRep $name - current query: $query ");
 
     Log3 ($name, 3, "DbRep $name - VACUUM database $dbname....");
     eval {$sth = $dbh->prepare($query);
           $r = $sth->execute();
          }; 
	 if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - Error executing: '".$query."' ! SQLite-Error: ".$@);
		 $sth->finish;
		 $dbh->disconnect;
         return "$name|''|$err|''|''|''|''|''|''|''";     
	 }
	 
	 # Endgröße ermitteln
	 $db_MB = (split(' ',qx(du -m $dbname)))[0] if ($^O =~ m/linux/i || $^O =~ m/unix/i);
	 Log3 ($name, 3, "DbRep $name - Size of database $dbname after optimize (MB): $db_MB");
 } 
 
 $dbname = (split /[\/]/, $dbname)[-1];
  
 Log3 ($name, 3, "DbRep $name - Starting dump of database '$dbname'");

 # Startzeit ermitteln 
 my ($Sekunden, $Minuten, $Stunden, $Monatstag, $Monat, $Jahr, $Wochentag, $Jahrestag, $Sommerzeit) = localtime(time);
 $Jahr      += 1900;
 $Monat     += 1;
 $Jahrestag += 1;
 my $time_stamp = $Jahr."_".sprintf("%02d",$Monat)."_".sprintf("%02d",$Monatstag)."_".sprintf("%02d",$Stunden)."_".sprintf("%02d",$Minuten);
 
 $dbname = (split /\./, $dbname)[0];
 my $bfile = $dbname."_".$time_stamp.".sqlitebkp";
 Log3 ($name, 5, "DbRep $name - Use Outfile: $dump_path$bfile");

 # SQL-Startzeit
 my $st = [gettimeofday];

 eval { $dbh->sqlite_backup_to_file($dump_path.$bfile); }; 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     $dbh->disconnect;
     return "$name|''|$err|''|''|''|''|''|''|''";     
 }
  
 $dbh->disconnect;
  
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 # Dumpfile komprimieren
 my $compress = AttrVal($name,"dumpCompress",0);
 if($compress) {
     # $err nicht auswerten -> wenn compress fehlerhaft wird unkomprimiertes dumpfile verwendet
     ($err,$bfile) = DbRep_dumpCompress($hash,$bfile);
 }

 # Größe Dumpfile ermitteln
 my @a = split(' ',qx(du $dump_path$bfile)) if ($^O =~ m/linux/i || $^O =~ m/unix/i);
 
 my $filesize = ($a[0])?($a[0]*1024):"n.a.";
 my $fsize    = DbRep_byteOutput($filesize);
 Log3 ($name, 3, "DbRep $name - Size of backupfile: ".$fsize);
 
 # Dumpfile per FTP senden und versionieren
 my ($ftperr,$ftpmsg,@ftpfd) = DbRep_sendftp($hash,$bfile); 
 my $ftp = $ftperr?encode_base64($ftperr,""):$ftpmsg?encode_base64($ftpmsg,""):0;
 my $ffd = join(", ", @ftpfd);
 $ffd    = $ffd?encode_base64($ffd,""):0;
 
 # alte Dumpfiles löschen
 my @fd  = DbRep_deldumpfiles($hash,$bfile);
 my $bfd = join(", ", @fd );
 $bfd    = $bfd?encode_base64($bfd,""):0;
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);
 
 $fsize = encode_base64($fsize,"");

 $rt = $rt.",".$brt;
 
 Log3 ($name, 3, "DbRep $name - Finished backup of database $dbname - total time used: ".sprintf("%.0f",$brt)." seconds");
 
return "$name|$rt|''|$dump_path$bfile|n.a.|n.a.|$fsize|$ftp|$bfd|$ffd";
}

####################################################################################################
#             Auswertungsroutine der nicht blockierenden DB-Funktion Dump
####################################################################################################
sub DbRep_DumpDone($) {
  my ($string)   = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $bt         = $a[1];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[2]?decode_base64($a[2]):undef;
  my $bfile      = $a[3];
  my $drc        = $a[4];
  my $drh        = $a[5];
  my $fs         = $a[6]?decode_base64($a[6]):undef;
  my $ftp        = $a[7]?decode_base64($a[7]):undef;
  my $bfd        = $a[8]?decode_base64($a[8]):undef;
  my $ffd        = $a[9]?decode_base64($a[9]):undef;
  my $name       = $hash->{NAME};
  my $erread;
  
  delete($hash->{HELPER}{RUNNING_BACKUP_CLIENT});
  delete($hash->{HELPER}{RUNNING_BCKPREST_SERVER});
  
  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      return;
  } 
 
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
  
  readingsBeginUpdate($hash);
  ReadingsBulkUpdateValue($hash, "DumpFileCreated", $bfile);
  ReadingsBulkUpdateValue($hash, "DumpFileCreatedSize", $fs);
  ReadingsBulkUpdateValue($hash, "DumpFilesDeleted", $bfd);
  ReadingsBulkUpdateValue($hash, "DumpRowsCurrent", $drc);
  ReadingsBulkUpdateValue($hash, "DumpRowsHistory", $drh);
  ReadingsBulkUpdateValue($hash, "FTP_Message", $ftp) if($ftp);
  ReadingsBulkUpdateValue($hash, "FTP_DumpFilesDeleted", $ffd) if($ffd);
  ReadingsBulkUpdateValue($hash, "background_processing_time", sprintf("%.4f",$brt));
  readingsEndUpdate($hash, 1);

  # Befehl nach Procedure ausführen
  $erread = DbRep_afterproc($hash, "dump");
  
  my $state = $erread?$erread:"Database backup finished";
  readingsBeginUpdate($hash);
  ReadingsBulkUpdateTimeState($hash,undef,undef,$state);
  readingsEndUpdate($hash, 1);

  Log3 ($name, 3, "DbRep $name - Database dump finished successfully. ");
  
return;
}

####################################################################################################
#                                      Dump-Routine SQLite
####################################################################################################
sub DbRep_sqliteRepair($) {
 my ($name)       = @_;
 my $hash         = $defs{$name};
 my $dbloghash    = $hash->{dbloghash};
 my $db           = $hash->{DATABASE};
 my $dbname       = (split /[\/]/, $db)[-1];
 my $dbpath       = (split /$dbname/, $db)[0];
 my $dblogname    = $dbloghash->{NAME};
 my $sqlfile      = $dbpath."dump_all.sql";
 my ($c,$clog,$ret,$err);

 # Background-Startzeit
 my $bst = [gettimeofday];
  
 $c = "echo \".mode insert\n.output $sqlfile\n.dump\n.exit\" | sqlite3 $db; ";
 $clog = $c;
 $clog =~ s/\n/ /g;
 Log3 ($name, 4, "DbRep $name - Systemcall: $clog");
 $ret = system qq($c);
 if($ret) {
     $err = "Error in step \"dump corrupt database\" - see logfile";
     $err = encode_base64($err,"");
     return "$name|''|$err";
 }
 
 $c = "mv $db $db.corrupt";
 $clog = $c;
 $clog =~ s/\n/ /g;
 Log3 ($name, 4, "DbRep $name - Systemcall: $clog");
 $ret = system qq($c);
 if($ret) {
     $err = "Error in step \"move atabase to corrupt-db\" - see logfile";
     $err = encode_base64($err,"");
     return "$name|''|$err";
 }
 
 $c = "echo \".read $sqlfile\n.exit\" | sqlite3 $db;";
 $clog = $c;
 $clog =~ s/\n/ /g;
 Log3 ($name, 4, "DbRep $name - Systemcall: $clog");
 $ret = system qq($c);
 if($ret) {
     $err = "Error in step \"read dump to new database\" - see logfile";
     $err = encode_base64($err,"");
     return "$name|''|$err";
 }
 
 $c = "rm $sqlfile";
 $clog = $c;
 $clog =~ s/\n/ /g;
 Log3 ($name, 4, "DbRep $name - Systemcall: $clog");
 $ret = system qq($c);
 if($ret) {
     $err = "Error in step \"delete $sqlfile\" - see logfile";
     $err = encode_base64($err,"");
     return "$name|''|$err";
 }
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);
 
return "$name|$brt|0";
}

####################################################################################################
#             Auswertungsroutine der nicht blockierenden DB-Funktion Dump
####################################################################################################
sub DbRep_RepairDone($) {
  my ($string)   = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $brt        = $a[1];
  my $err        = $a[2]?decode_base64($a[2]):undef;
  my $dbloghash  = $hash->{dbloghash};
  my $name       = $hash->{NAME};
  my $erread;
  
  delete($hash->{HELPER}{RUNNING_REPAIR});
  
  # Datenbankverbindung in DbLog wieder öffenen
  my $dbl = $dbloghash->{NAME};
  CommandSet(undef,"$dbl reopen");
  
  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      return;
  } 
 
  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
  
  readingsBeginUpdate($hash);
  ReadingsBulkUpdateValue($hash, "background_processing_time", sprintf("%.4f",$brt));
  readingsEndUpdate($hash, 1);

  # Befehl nach Procedure ausführen
  $erread = DbRep_afterproc($hash, "repair");
  
  my $state = $erread?$erread:"Repair finished $hash->{DATABASE}";
  readingsBeginUpdate($hash);
  ReadingsBulkUpdateTimeState($hash,undef,undef,$state);
  readingsEndUpdate($hash, 1);

  Log3 ($name, 3, "DbRep $name - Database repair $hash->{DATABASE} finished. - total time used: ".sprintf("%.0f",$brt)." seconds.");
  
return;
}

####################################################################################################
#                                     Restore SQLite
####################################################################################################
sub DbRep_sqliteRestore ($) {
 my ($string) = @_;
 my ($name,$bfile) = split("\\|", $string);
 my $hash          = $defs{$name};
 my $dbloghash     = $hash->{dbloghash};
 my $dbconn        = $dbloghash->{dbconn};
 my $dbuser        = $dbloghash->{dbuser};
 my $dblogname     = $dbloghash->{NAME};
 my $dbpassword    = $attr{"sec$dblogname"}{secret};
 my $dump_path_def = $attr{global}{modpath}."/log/";
 my $dump_path     = AttrVal($name, "dumpDirLocal", $dump_path_def);
 $dump_path        = $dump_path."/" unless($dump_path =~ m/\/$/);
 my $ebd           = AttrVal($name, "executeBeforeProc", undef);
 my $ead           = AttrVal($name, "executeAfterProc", undef);
 my ($dbh,$err,$dbname);
 
 # Background-Startzeit
 my $bst = [gettimeofday];
 
 # Verbindung mit DB
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 if ($@) {
	 $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|$err|''|''";
 }
 
 eval { $dbname = $dbh->sqlite_db_filename(); };
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     $dbh->disconnect;
     return "$name|''|$err|''|''";     
 }
 
 $dbname = (split /[\/]/, $dbname)[-1];
 
 # Dumpfile dekomprimieren wenn gzip
 if($bfile =~ m/.*.gzip$/) {
     ($err,$bfile) = DbRep_dumpUnCompress($hash,$bfile);
     if ($err) {
         $err = encode_base64($err,"");
         $dbh->disconnect;
         return "$name|''|$err|''|''";  
     }
 }
  
 Log3 ($name, 3, "DbRep $name - Starting restore of database '$dbname'");

 # SQL-Startzeit
 my $st = [gettimeofday];

 eval { $dbh->sqlite_backup_from_file($dump_path.$bfile); }; 
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     $dbh->disconnect;
     return "$name|''|$err|''|''";       
 }
  
 $dbh->disconnect;
  
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 Log3 ($name, 3, "DbRep $name - Restore of $dump_path$bfile into '$dbname' finished - total time used: ".sprintf("%.0f",$brt)." seconds.");
 
return "$name|$rt|''|$dump_path$bfile|n.a.";
}

####################################################################################################
#                  Restore MySQL (serverSide)
####################################################################################################
sub mysql_RestoreServerSide($) {
 my ($string) = @_;
 my ($name, $bfile)      = split("\\|", $string);
 my $hash                = $defs{$name};
 my $dbloghash           = $hash->{dbloghash};
 my $dbconn              = $dbloghash->{dbconn};
 my $dbuser              = $dbloghash->{dbuser};
 my $dblogname           = $dbloghash->{NAME};
 my $dbpassword          = $attr{"sec$dblogname"}{secret};
 my $dbname              = $hash->{DATABASE};
 my $dump_path_rem       = AttrVal($name, "dumpDirRemote", "./");
 $dump_path_rem          = $dump_path_rem."/" unless($dump_path_rem =~ m/\/$/);
 my $table               = "history";
 my ($dbh,$sth,$err,$drh);
 
 # Background-Startzeit
 my $bst = [gettimeofday];
 
 # Verbindung mit DB
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoInactiveDestroy => 1 });};
 if ($@) {
	 $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|$err|''|''";   
 }
 
 # Dumpfile dekomprimieren wenn gzip
 if($bfile =~ m/.*.gzip$/) {
     ($err,$bfile) = DbRep_dumpUnCompress($hash,$bfile);
     if ($err) {
         $err = encode_base64($err,"");
         $dbh->disconnect;
         return "$name|''|$err|''|''";  
     }
 }
 
 Log3 ($name, 3, "DbRep $name - Starting restore of database '$dbname', table '$table'.");

 # SQL-Startzeit
 my $st = [gettimeofday];

 my $sql = "LOAD DATA CONCURRENT INFILE '$dump_path_rem$bfile' IGNORE INTO TABLE $table FIELDS TERMINATED BY ',' ENCLOSED BY '\"' LINES TERMINATED BY '\n'; ";

 eval {$sth = $dbh->prepare($sql);
       $drh = $sth->execute();
      }; 
  
  if ($@) {
     # error bei sql-execute
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
	 $dbh->disconnect;
     return "$name|''|$err|''|''";     
  }
  
 $sth->finish;
 $dbh->disconnect;
  
 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 Log3 ($name, 3, "DbRep $name - Restore of $dump_path_rem$bfile into '$dbname', '$table' finished - total time used: ".sprintf("%.0f",$brt)." seconds.");
 
return "$name|$rt|''|$dump_path_rem$bfile|n.a.";
}

####################################################################################################
#                                  Auswertungsroutine Restore
####################################################################################################
sub DbRep_restoreDone($) {
  my ($string)   = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $bt         = $a[1];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[2]?decode_base64($a[2]):undef;
  my $bfile      = $a[3];
  my $drh        = $a[4];
  my $name       = $hash->{NAME};
  my $erread;
  
  delete($hash->{HELPER}{RUNNING_BACKUP_CLIENT});
  delete($hash->{HELPER}{RUNNING_BCKPREST_SERVER});
  
  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      return;
  } 
  
  readingsBeginUpdate($hash);
  ReadingsBulkUpdateValue($hash, "RestoreRowsHistory", $drh);
  readingsEndUpdate($hash, 1);
  
  # Befehl nach Procedure ausführen
  $erread = DbRep_afterproc($hash, "restore");
  
  my $state = $erread?$erread:"Restore of $bfile finished";
  readingsBeginUpdate($hash);
  ReadingsBulkUpdateTimeState($hash,$brt,undef,$state);
  readingsEndUpdate($hash, 1);

  Log3 ($name, 3, "DbRep $name - Database restore finished successfully. ");
  
return;
}

####################################################################################################
#      Übertragung Datensätze in weitere DB
####################################################################################################
sub DbRep_syncStandby($) {
 my ($string) = @_;
 my ($name,$device,$reading,$runtime_string_first,$runtime_string_next,$ts,$stbyname) = split("\\§", $string);
 my $hash       = $defs{$name};
 my $table      = "history";
 my $utf8       = defined($hash->{UTF8})?$hash->{UTF8}:0;
 my ($dbh,$dbhstby,$err,$sql,$irows,$irowdone);
 # Quell-DB
 my $dbloghash  = $hash->{dbloghash};
 my $dbconn     = $dbloghash->{dbconn};
 my $dbuser     = $dbloghash->{dbuser};
 my $dblogname  = $dbloghash->{NAME};
 my $dbpassword = $attr{"sec$dblogname"}{secret};
 # Standby-DB
 my $stbyhash   = $defs{$stbyname};
 my $stbyconn   = $stbyhash->{dbconn};
 my $stbyuser   = $stbyhash->{dbuser};
 my $stbypasswd = $attr{"sec$stbyname"}{secret};
 my $stbyutf8   = defined($stbyhash->{UTF8})?$stbyhash->{UTF8}:0;
 
 # Background-Startzeit
 my $bst = [gettimeofday];
 
 # Verbindung zur Quell-DB
 eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1, mysql_enable_utf8 => $utf8 });};
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|''|$err";
 }
 
 # Verbindung zur Standby-DB
 eval {$dbhstby = DBI->connect("dbi:$stbyconn", $stbyuser, $stbypasswd, { PrintError => 0, RaiseError => 1, AutoCommit => 1, mysql_enable_utf8 => $stbyutf8 });};
 if ($@) {
     $err = encode_base64($@,"");
     Log3 ($name, 2, "DbRep $name - $@");
     return "$name|''|''|$err";
 }
 
 # ist Zeiteingrenzung und/oder Aggregation gesetzt ? (wenn ja -> "?" in SQL sonst undef) 
 my ($IsTimeSet,$IsAggrSet) = DbRep_checktimeaggr($hash); 
 Log3 ($name, 5, "DbRep $name - IsTimeSet: $IsTimeSet, IsAggrSet: $IsAggrSet");

 # SQL-Startzeit
 my $st = [gettimeofday];
 
 my ($sth,$old,$new);
 eval { $dbh->begin_work() if($dbh->{AutoCommit}); };   # Transaktion wenn gewünscht und autocommit ein
 if ($@) {
     Log3($name, 2, "DbRep $name -> Error start transaction - $@");
 }
     
 # Timestampstring to Array
 my @ts = split("\\|", $ts);
 Log3 ($name, 5, "DbRep $name - Timestamp-Array: \n@ts");
     
 # DB-Abfrage zeilenweise für jeden Array-Eintrag
 $irows    = 0;
 $irowdone = 0;
 my $selspec = "TIMESTAMP,DEVICE,TYPE,EVENT,READING,VALUE,UNIT";
 my $addon   = '';
 foreach my $row (@ts) {
     my @a                     = split("#", $row);
     my $runtime_string        = $a[0];
     my $runtime_string_first  = $a[1];
     my $runtime_string_next   = $a[2];
         
     if ($IsTimeSet || $IsAggrSet) {
         $sql = DbRep_createSelectSql($hash,"history",$selspec,$device,$reading,"'$runtime_string_first'","'$runtime_string_next'",$addon); 
     } else {
         $sql = DbRep_createSelectSql($hash,"history",$selspec,$device,$reading,undef,undef,$addon);
     }
     Log3 ($name, 4, "DbRep $name - SQL execute: $sql");
         
     eval{ $sth = $dbh->prepare($sql);
           $sth->execute();
         };	         
     if ($@) {
         $err = encode_base64($@,"");
         Log3 ($name, 2, "DbRep $name - $@");
         $dbh->disconnect;
         return "$name|''|''|$err";
     }
         
     no warnings 'uninitialized'; 
     #                          DATE _ESC_ TIME      _ESC_  DEVICE   _ESC_  TYPE    _ESC_   EVENT    _ESC_  READING  _ESC_   VALUE   _ESC_   UNIT
     my @row_array = map { ($_->[0] =~ s/ /_ESC_/r)."_ESC_".$_->[1]."_ESC_".$_->[2]."_ESC_".$_->[3]."_ESC_".$_->[4]."_ESC_".$_->[5]."_ESC_".$_->[6] } @{$sth->fetchall_arrayref()}; 
     use warnings;
         
     (undef,$irowdone,$err) = DbRep_WriteToDB($name,$dbhstby,$stbyhash,"0",@row_array) if(@row_array);
     if ($err) {
         Log3 ($name, 2, "DbRep $name - $err");
         $err = encode_base64($err,"");
         $dbh->disconnect;
         $dbhstby->disconnect();
         return "$name|''|''|$err";
     }
     $irows += $irowdone;
 }
 
 $dbh->disconnect();
 $dbhstby->disconnect();

 # SQL-Laufzeit ermitteln
 my $rt = tv_interval($st);
 
 # Background-Laufzeit ermitteln
 my $brt = tv_interval($bst);

 $rt = $rt.",".$brt;
 
 return "$name|$irows|$rt|0";
}

####################################################################################################
#         Auswertungsroutine Übertragung Datensätze in weitere DB
####################################################################################################
sub DbRep_syncStandbyDone($) {
  my ($string) = @_;
  my @a          = split("\\|",$string);
  my $hash       = $defs{$a[0]};
  my $name       = $hash->{NAME};
  my $irows      = $a[1];
  my $bt         = $a[2];
  my ($rt,$brt)  = split(",", $bt);
  my $err        = $a[3]?decode_base64($a[3]):undef;
  
  if ($err) {
      ReadingsSingleUpdateValue ($hash, "errortext", $err, 1);
      ReadingsSingleUpdateValue ($hash, "state", "error", 1);
      delete($hash->{HELPER}{RUNNING_PID});
      Log3 ($name, 4, "DbRep $name -> BlockingCall change_Done finished");
      return;
  } 

  # only for this block because of warnings if details of readings are not set
  no warnings 'uninitialized'; 
  
  readingsBeginUpdate($hash);
  ReadingsBulkUpdateValue ($hash, "number_lines_inserted_Standby", $irows); 
  ReadingsBulkUpdateTimeState($hash,$brt,$rt,"done");
  readingsEndUpdate($hash, 1);
  
  # Befehl nach Procedure ausführen
  my $erread = DbRep_afterproc($hash, "syncStandby");

  delete($hash->{HELPER}{RUNNING_PID});
  
return;
}

####################################################################################################
#                    Abbruchroutine Timeout Restore
####################################################################################################
sub DbRep_restoreAborted(@) {
  my ($hash,$cause) = @_;
  my $name = $hash->{NAME};
  my $dbh  = $hash->{DBH}; 
  my $erread;
  
  $cause = $cause?$cause:"Timeout: process terminated";
  Log3 ($name, 1, "DbRep $name - BlockingCall $hash->{HELPER}{RUNNING_BACKUP_CLIENT}{fn} pid:$hash->{HELPER}{RUNNING_PID}{pid} $cause") if($hash->{HELPER}{RUNNING_BACKUP_CLIENT});
  Log3 ($name, 1, "DbRep $name - BlockingCall $hash->{HELPER}{RUNNING_BCKPREST_SERVER}{fn} pid:$hash->{HELPER}{RUNNING_PID}{pid} $cause") if($hash->{HELPER}{RUNNING_BCKPREST_SERVER});

  # Befehl nach Procedure ausführen
  no warnings 'uninitialized'; 
  $erread = DbRep_afterproc($hash, "restore");
  $erread = ", ".(split("but", $erread))[1] if($erread);
  
  my $state = $cause.$erread;
  $dbh->disconnect() if(defined($dbh));
  ReadingsSingleUpdateValue ($hash, "state", $state, 1);
  
  Log3 ($name, 2, "DbRep $name - Database restore aborted by \"$cause\" ");
  
  delete($hash->{HELPER}{RUNNING_BACKUP_CLIENT});
  delete($hash->{HELPER}{RUNNING_BCKPREST_SERVER});
return;
}

####################################################################################################
#                    Abbruchroutine Timeout DB-Abfrage
####################################################################################################
sub DbRep_ParseAborted(@) {
  my ($hash,$cause) = @_;
  my $name = $hash->{NAME};
  my $dbh = $hash->{DBH}; 
  my $erread;
  
  $cause = $cause?$cause:"Timeout: process terminated";
  Log3 ($name, 1, "DbRep $name -> BlockingCall $hash->{HELPER}{RUNNING_PID}{fn} pid:$hash->{HELPER}{RUNNING_PID}{pid} $cause");
  
  # Befehl nach Procedure ausführen
  no warnings 'uninitialized'; 
  $erread = DbRep_afterproc($hash, "command");
  $erread = ", ".(split("but", $erread))[1] if($erread);    
  
  $dbh->disconnect() if(defined($dbh));
  ReadingsSingleUpdateValue ($hash,"state",$cause, 1);
  
  delete($hash->{HELPER}{RUNNING_PID});
return;
}

####################################################################################################
#                    Abbruchroutine Timeout DB-Dump
####################################################################################################
sub DbRep_DumpAborted(@) {
  my ($hash,$cause) = @_;
  my $name = $hash->{NAME};
  my $dbh  = $hash->{DBH}; 
  my ($erread);
  
  $cause = $cause?$cause:"Timeout: process terminated";
  Log3 ($name, 1, "DbRep $name - BlockingCall $hash->{HELPER}{RUNNING_BACKUP_CLIENT}{fn} pid:$hash->{HELPER}{RUNNING_BACKUP_CLIENT}{pid} $cause") if($hash->{HELPER}{RUNNING_BACKUP_CLIENT});
  Log3 ($name, 1, "DbRep $name - BlockingCall $hash->{HELPER}{RUNNING_BCKPREST_SERVER}{fn} pid:$hash->{HELPER}{RUNNING_BCKPREST_SERVER}{pid} $cause") if($hash->{HELPER}{RUNNING_BCKPREST_SERVER});
  
  # Befehl nach Procedure ausführen
  no warnings 'uninitialized'; 
  $erread = DbRep_afterproc($hash, "dump");
  $erread = ", ".(split("but", $erread))[1] if($erread);
  
  my $state = $cause.$erread;
  $dbh->disconnect() if(defined($dbh));
  ReadingsSingleUpdateValue ($hash, "state", $state, 1);
  
  Log3 ($name, 2, "DbRep $name - Database dump aborted by \"$cause\" ");
  
  delete($hash->{HELPER}{RUNNING_BACKUP_CLIENT});
  delete($hash->{HELPER}{RUNNING_BCKPREST_SERVER});
return;
}

####################################################################################################
#                    Abbruchroutine Timeout DB-Abfrage
####################################################################################################
sub DbRep_OptimizeAborted(@) {
  my ($hash,$cause) = @_;
  my $name = $hash->{NAME};
  my $dbh  = $hash->{DBH}; 
  my ($erread);
  
  $cause = $cause?$cause:"Timeout: process terminated";
  Log3 ($name, 1, "DbRep $name -> BlockingCall $hash->{HELPER}{RUNNING_OPTIMIZE}}{fn} pid:$hash->{HELPER}{RUNNING_OPTIMIZE}{pid} $cause");
  
  # Befehl nach Procedure ausführen
  no warnings 'uninitialized'; 
  $erread = DbRep_afterproc($hash, "optimize");
  $erread = ", ".(split("but", $erread))[1] if($erread);
  
  my $state = $cause.$erread;
  $dbh->disconnect() if(defined($dbh));
  ReadingsSingleUpdateValue ($hash, "state", $state, 1);
  
  Log3 ($name, 2, "DbRep $name - Database optimize aborted by \"$cause\" ");
  
  delete($hash->{HELPER}{RUNNING_OPTIMIZE}); 
return;
}

####################################################################################################
#                    Abbruchroutine Repair SQlite
####################################################################################################
sub DbRep_RepairAborted(@) {
  my ($hash,$cause) = @_;
  my $name      = $hash->{NAME};
  my $dbh       = $hash->{DBH}; 
  my $dbloghash = $hash->{dbloghash};
  my $erread;
  
  $cause = $cause?$cause:"Timeout: process terminated";
  Log3 ($name, 1, "DbRep $name -> BlockingCall $hash->{HELPER}{RUNNING_REPAIR}{fn} pid:$hash->{HELPER}{RUNNING_REPAIR}{pid} $cause");
  
  # Datenbankverbindung in DbLog wieder öffenen
  my $dbl = $dbloghash->{NAME};
  CommandSet(undef,"$dbl reopen");
  
  # Befehl nach Procedure ausführen
  no warnings 'uninitialized'; 
  $erread = DbRep_afterproc($hash, "repair");
  $erread = ", ".(split("but", $erread))[1] if($erread);    
  
  $dbh->disconnect() if(defined($dbh));
  ReadingsSingleUpdateValue ($hash,"state",$cause, 1);
  
  delete($hash->{HELPER}{RUNNING_REPAIR});
return;
}

####################################################################################################
#  SQL-Statement zusammenstellen für DB-Abfrage
####################################################################################################
sub DbRep_createSelectSql($$$$$$$$) {
 my ($hash,$table,$selspec,$device,$reading,$tf,$tn,$addon) = @_;
 my $name    = $hash->{NAME};
 my $dbmodel = $hash->{dbloghash}{MODEL};
 my ($sql,$devs,$danz,$ranz);
 my $tnfull = 0;
 
 ($devs,$danz,$reading,$ranz) = DbRep_specsForSql($hash,$device,$reading);
 
 if($tn && $tn =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/) {
     $tnfull = 1;
 }
 
 $sql = "SELECT $selspec FROM $table where ";
 $sql .= "DEVICE LIKE '$devs' AND "      if($danz <= 1 && $devs !~ m(^%$) && $devs =~ m(\%));
 $sql .= "DEVICE = '$devs' AND "         if($danz <= 1 && $devs !~ m(\%));
 $sql .= "DEVICE IN ($devs) AND "        if($danz > 1);
 $sql .= "READING LIKE '$reading' AND "  if($ranz <= 1 && $reading !~ m(^%$) && $reading =~ m(\%));
 $sql .= "READING = '$reading' AND "     if($ranz <= 1 && $reading !~ m(\%));
 $sql .= "READING IN ($reading) AND "    if($ranz > 1);
 if (($tf && $tn)) {
     $sql .= "TIMESTAMP >= $tf AND TIMESTAMP ".($tnfull?"<=":"<")." $tn ";
 } else {
     if ($dbmodel eq "POSTGRESQL") {
	     $sql .= "true ";
	 } else {
	      $sql .= "1 ";
	 }
 }
 $sql .= "$addon;";

return $sql;
}

####################################################################################################
#  SQL-Statement zusammenstellen für DB-Updates
####################################################################################################
sub DbRep_createUpdateSql($$$$$$$$) {
 my ($hash,$table,$selspec,$device,$reading,$tf,$tn,$addon) = @_;
 my $name    = $hash->{NAME};
 my $dbmodel = $hash->{dbloghash}{MODEL};
 my ($sql,$devs,$danz,$ranz);
 my $tnfull = 0;
 
 ($devs,$danz,$reading,$ranz) = DbRep_specsForSql($hash,$device,$reading);
 
 if($tn =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/) {
     $tnfull = 1;
 }

 $sql = "UPDATE $table SET $selspec AND ";
 $sql .= "DEVICE LIKE '$devs' AND "      if($danz <= 1 && $devs !~ m(^%$) && $devs =~ m(\%));
 $sql .= "DEVICE = '$devs' AND "         if($danz <= 1 && $devs !~ m(\%));
 $sql .= "DEVICE IN ($devs) AND "        if($danz > 1);
 $sql .= "READING LIKE '$reading' AND "  if($ranz <= 1 && $reading !~ m(^%$) && $reading =~ m(\%));
 $sql .= "READING = '$reading' AND "     if($ranz <= 1 && $reading !~ m(\%));
 $sql .= "READING IN ($reading) AND "    if($ranz > 1);
 if (($tf && $tn)) {
     $sql .= "TIMESTAMP >= $tf AND TIMESTAMP ".($tnfull?"<=":"<")." $tn ";
 } else {
     if ($dbmodel eq "POSTGRESQL") {
	     $sql .= "true ";
	 } else {
	      $sql .= "1 ";
	 }
 }
 $sql .= "$addon;";

return $sql;
}

####################################################################################################
#  SQL-Statement zusammenstellen für Löschvorgänge
####################################################################################################
sub DbRep_createDeleteSql($$$$$$$) {
 my ($hash,$table,$device,$reading,$tf,$tn,$addon) = @_;
 my $name    = $hash->{NAME};
 my $dbmodel = $hash->{dbloghash}{MODEL};
 my ($sql,$devs,$danz,$ranz);
 my $tnfull = 0;
 
 if($table eq "current") {
     $sql = "delete FROM $table; ";
	 return $sql;
 }
 
 ($devs,$danz,$reading,$ranz) = DbRep_specsForSql($hash,$device,$reading);
 
 if($tn =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/) {
     $tnfull = 1;
 }
 
 $sql = "delete FROM $table where ";
 $sql .= "DEVICE LIKE '$devs' AND "      if($danz <= 1 && $devs !~ m(^%$) && $devs =~ m(\%));
 $sql .= "DEVICE = '$devs' AND "         if($danz <= 1 && $devs !~ m(\%));
 $sql .= "DEVICE IN ($devs) AND "        if($danz > 1);
 $sql .= "READING LIKE '$reading' AND "  if($ranz <= 1 && $reading !~ m(^%$) && $reading =~ m(\%));
 $sql .= "READING = '$reading' AND "     if($ranz <= 1 && $reading !~ m(\%));
 $sql .= "READING IN ($reading) AND "    if($ranz > 1);
 if ($tf && $tn) {
     $sql .= "TIMESTAMP >= '$tf' AND TIMESTAMP ".($tnfull?"<=":"<")." '$tn' $addon;";
 } else {
     if ($dbmodel eq "POSTGRESQL") {
	     $sql .= "true;";
	 } else {
	      $sql .= "1;";
	 }
 }

return $sql;
}

####################################################################################################
#               Ableiten von Device, Reading-Spezifikationen 
####################################################################################################
sub DbRep_specsForSql($$$) {
 my ($hash,$device,$reading) = @_;
 my $name    = $hash->{NAME};
 
 my @dvspcs = devspec2array($device);
 my $devs = join(",",@dvspcs);
 $devs =~ s/'/''/g;               # escape ' with ''
 my $danz = $#dvspcs+1;
 if ($danz > 1) {
     $devs =~ s/,/','/g;
	 $devs = "'".$devs."'";
 }
 Log3 $name, 5, "DbRep $name - Device specifications use for select: $devs";
 
 $reading =~ s/'/''/g;            # escape ' with ''
 my @reads = split(",",$reading);
 my $ranz = $#reads+1;
 if ($ranz > 1) {
     $reading =~ s/,/','/g;
	 $reading = "'".$reading."'";
 }
 Log3 $name, 5, "DbRep $name - Reading specification use for select: $reading";

return ($devs,$danz,$reading,$ranz);
}

####################################################################################################
#    Check ob Zeitgrenzen bzw. Aggregation gesetzt sind, evtl. übertseuern (je nach Funktion)
#    Return "1" wenn Bedingung erfüllt, sonst "0"
####################################################################################################
sub DbRep_checktimeaggr ($) {
 my ($hash)      = @_;
 my $name        = $hash->{NAME};
 my $IsTimeSet   = 0;
 my $IsAggrSet   = 0;
 my $aggregation = AttrVal($name,"aggregation","no");

 if ( AttrVal($name,"timestamp_begin",undef) || AttrVal($name,"timestamp_end",undef) ||
	  AttrVal($name,"timeDiffToNow",undef) || AttrVal($name,"timeOlderThan",undef) || AttrVal($name,"timeYearPeriod",undef) ) {
	  $IsTimeSet = 1;
 }
 
 if ($aggregation ne "no") {
     $IsAggrSet = 1;
 }
 if($hash->{LASTCMD} =~ /delSeqDoublets/) {
     $aggregation = ($aggregation eq "no")?"day":$aggregation;       # wenn Aggregation "no", für delSeqDoublets immer "day" setzen
	 $IsAggrSet   = 1;
 }
 if($hash->{LASTCMD} =~ /averageValue/ && AttrVal($name,"averageCalcForm","avgArithmeticMean") eq "avgDailyMeanGWS") {
     $aggregation = "day";       # für Tagesmittelwertberechnung des deutschen Wetterdienstes immer "day"
	 $IsAggrSet   = 1;
 }
 if($hash->{LASTCMD} =~ /delEntries|fetchrows|deviceRename|readingRename|tableCurrentFillup/) {
	 $IsAggrSet   = 0;
	 $aggregation = "no";
 }
 if($hash->{LASTCMD} =~ /deviceRename|readingRename/) {
	 $IsTimeSet = 0;
 }  
 if($hash->{LASTCMD} =~ /changeValue/) {
	 if($hash->{HELPER}{COMPLEX}) {
         $IsAggrSet   = 1;
	     $aggregation = "day";  
     } else {
         $IsAggrSet   = 0;
	     $aggregation = "no";     
     }
 }  
 if($hash->{LASTCMD} =~ /syncStandby/ ) {
     if($aggregation !~ /day|hour|week/) {
         $aggregation = "day";
	     $IsAggrSet   = 1;
     }
 }

return ($IsTimeSet,$IsAggrSet,$aggregation);
}

####################################################################################################
#    ReadingsSingleUpdate für Reading, Value, Event
####################################################################################################
sub ReadingsSingleUpdateValue ($$$$) {
 my ($hash,$reading,$val,$ev) = @_;
 my $name = $hash->{NAME};
 
 readingsSingleUpdate($hash, $reading, $val, $ev);
 DbRep_userexit($name, $reading, $val);

return;
}

####################################################################################################
#    Readingsbulkupdate für Reading, Value
#    readingsBeginUpdate und readingsEndUpdate muss vor/nach Funktionsaufruf gesetzt werden
####################################################################################################
sub ReadingsBulkUpdateValue ($$$) {
 my ($hash,$reading,$val) = @_;
 my $name = $hash->{NAME};
 
 readingsBulkUpdate($hash, $reading, $val);
 DbRep_userexit($name, $reading, $val);

return;
}

####################################################################################################
#    Readingsbulkupdate für processing_time, state
#    readingsBeginUpdate und readingsEndUpdate muss vor/nach Funktionsaufruf gesetzt werden
####################################################################################################
sub ReadingsBulkUpdateTimeState ($$$$) {
 my ($hash,$brt,$rt,$sval) = @_;
 my $name = $hash->{NAME};
 
 if(AttrVal($name, "showproctime", undef)) {
     readingsBulkUpdate($hash, "background_processing_time", sprintf("%.4f",$brt)) if(defined($brt)); 
     DbRep_userexit($name, "background_processing_time", sprintf("%.4f",$brt)) if(defined($brt));  
     readingsBulkUpdate($hash, "sql_processing_time", sprintf("%.4f",$rt)) if(defined($rt)); 
     DbRep_userexit($name, "sql_processing_time", sprintf("%.4f",$rt)) if(defined($rt)); 
 }
  
 readingsBulkUpdate($hash, "state", $sval);
 DbRep_userexit($name, "state", $sval);

return;
}

####################################################################################################
#  Anzeige von laufenden Blocking Prozessen
####################################################################################################
sub DbRep_getblockinginfo($@) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  
  my @rows;
  our %BC_hash;
  my $len = 99;
  foreach my $h (values %BC_hash) {
      next if($h->{terminated} || !$h->{pid});
	  my @allk = keys%{$h};
	  foreach my $k (@allk) {
	      Log3 ($name, 5, "DbRep $name -> $k : ".$h->{$k});
	  }
      my $fn   = (ref($h->{fn})  ? ref($h->{fn})  : $h->{fn});
      my $arg  = (ref($h->{arg}) ? ref($h->{arg}) : $h->{arg});
	  my $arg1 = substr($arg,0,$len);
	  $arg1    = $arg1."..." if(length($arg) > $len+1);
      my $to   = ($h->{timeout}  ? $h->{timeout}  : "N/A");
      my $conn = ($h->{telnet}   ? $h->{telnet}   : "N/A");
      push @rows, "$h->{pid}|ESCAPED|$fn|ESCAPED|$arg1|ESCAPED|$to|ESCAPED|$conn";
  } 
   
  # Readingaufbereitung
  readingsBeginUpdate($hash);
  
  if(!@rows) {
      ReadingsBulkUpdateTimeState($hash,undef,undef,"done - No BlockingCall processes running");
      readingsEndUpdate($hash, 1);
	  return;
  }
  
  my $res = "<html><table border=2 bordercolor='darkgreen' cellspacing=0>";
  $res .= "<tr><td style='padding-right:5px;padding-left:5px;font-weight:bold'>PID</td>";
  $res .= "<td style='padding-right:5px;padding-left:5px;font-weight:bold'>FUNCTION</td>";
  $res .= "<td style='padding-right:5px;padding-left:5px;font-weight:bold'>ARGUMENTS</td>";
  $res .= "<td style='padding-right:5px;padding-left:5px;font-weight:bold'>TIMEOUT</td>";
  $res .= "<td style='padding-right:5px;padding-left:5px;font-weight:bold'>CONNECTEDVIA</td></tr>";
  foreach my $row (@rows) {
      $row =~ s/\|ESCAPED\|/<\/td><td style='padding-right:5px;padding-left:5px'>/g;
      $res .= "<tr><td style='padding-right:5px;padding-left:5px'>".$row."</td></tr>";
  }
  my $tab = $res."</table></html>";

  ReadingsBulkUpdateValue ($hash,"BlockingInfo",$tab);	
  ReadingsBulkUpdateValue ($hash,"Blocking_Count",$#rows+1);	

  ReadingsBulkUpdateTimeState($hash,undef,undef,"done");
  readingsEndUpdate($hash, 1);
  
return;
}

####################################################################################################
#    relative Zeitangaben als Sekunden normieren
#
# liefert die Attribute timeOlderThan, timeDiffToNow als Sekunden normiert zurück
####################################################################################################
sub DbRep_normRelTime ($) {
 my ($hash) = @_;
 my $name = $hash->{NAME};
 my $tdtn = AttrVal($name, "timeDiffToNow", undef);
 my $toth = AttrVal($name, "timeOlderThan", undef);
 
 if($tdtn && $tdtn =~ /^\s*[dhms]:(([\d]+.[\d]+)|[\d]+)\s*/) {
     my ($d,$h,$m,$s);
	 if($tdtn =~ /.*d:(([\d]+.[\d]+)|[\d]+).*/) {
	     $d =  $tdtn;
	     $d =~ s/.*d:(([\d]+.[\d]+)|[\d]+).*/$1/e; 
	 }
	 if($tdtn =~ /.*h:(([\d]+.[\d]+)|[\d]+).*/) {
	     $h =  $tdtn;
         $h =~ s/.*h:(([\d]+.[\d]+)|[\d]+).*/$1/e;
	 }
	 if($tdtn =~ /.*m:(([\d]+.[\d]+)|[\d]+).*/) {
	     $m =  $tdtn;
         $m =~ s/.*m:(([\d]+.[\d]+)|[\d]+).*/$1/e;
	 }
	 if($tdtn =~ /.*s:(([\d]+.[\d]+)|[\d]+).*/) {
	     $s =  $tdtn;
         $s =~ s/.*s:(([\d]+.[\d]+)|[\d]+).*/$1/e ;
	 }
     
	 no warnings 'uninitialized'; 
	 Log3($name, 4, "DbRep $name - timeDiffToNow - day: $d, hour: $h, min: $m, sec: $s ");
	 use warnings;
     $d = $d?($d*86400)+1:0;      # one security second for correct create TimeArray
     $h = $h?($h*3600)+1:0;
     $m = $m?($m*60)+1:0;
     $s = $s?$s:0;

     $tdtn = $d + $h + $m +$s;
 }
 
 if($toth && $toth =~ /^\s*[dhms]:(([\d]+.[\d]+)|[\d]+)\s*/) {
     my ($d,$h,$m,$s);
	 if($toth =~ /.*d:(([\d]+.[\d]+)|[\d]+).*/) {
	     $d =  $toth;
	     $d =~ s/.*d:(([\d]+.[\d]+)|[\d]+).*/$1/e; 
	 }
	 if($toth =~ /.*h:(([\d]+.[\d]+)|[\d]+).*/) {
	     $h =  $toth;
         $h =~ s/.*h:(([\d]+.[\d]+)|[\d]+).*/$1/e;
	 }
	 if($toth =~ /.*m:(([\d]+.[\d]+)|[\d]+).*/) {
	     $m =  $toth;
         $m =~ s/.*m:(([\d]+.[\d]+)|[\d]+).*/$1/e;
	 }
	 if($toth =~ /.*s:(([\d]+.[\d]+)|[\d]+).*/) {
	     $s =  $toth;
         $s =~ s/.*s:(([\d]+.[\d]+)|[\d]+).*/$1/e ;
	 }

	 no warnings 'uninitialized'; 
	 Log3($name, 4, "DbRep $name - timeDiffToNow - day: $d, hour: $h, min: $m, sec: $s ");
	 use warnings;
     $d = $d?($d*86400)+1:0;            # one security second for correct create TimeArray
     $h = $h?($h*3600)+1:0;
     $m = $m?($m*60)+1:0;
     $s = $s?$s:0;

     $toth = $d + $h + $m +$s;
 }
return ($toth,$tdtn);
}

###############################################################################
#              Zeichencodierung für Fileexport filtern 
###############################################################################
sub DbRep_charfilter ($) { 
  my ($txt) = @_;
  
  # nur erwünschte Zeichen, Filtern von Steuerzeichen
  $txt =~ tr/ A-Za-z0-9!"#$%&'()*+,-.\/:;<=>?@[\\]^_`{|}~äöüÄÖÜß€//cd;      
  
return($txt);
}

###################################################################################
#                    Befehl vor Procedure ausführen
###################################################################################
sub DbRep_beforeproc ($$) {
  my ($hash, $txt) = @_;
  my $name         = $hash->{NAME};
  
  # Befehl vor Procedure ausführen
  my $ebd = AttrVal($name, "executeBeforeProc", undef);
  if($ebd) {
      Log3 ($name, 3, "DbRep $name - execute command before $txt: '$ebd' ");
	  my $err = AnalyzeCommandChain(undef, $ebd);     
	  if ($err) {
          Log3 ($name, 2, "DbRep $name - command before $txt message: \"$err\" ");
          my $erread = "Warning - message from command before $txt appeared";
		  ReadingsSingleUpdateValue ($hash, "before".$txt."_message", $err, 1);
		  ReadingsSingleUpdateValue ($hash, "state", $erread, 1);
      }
  }  

return;  
}

###################################################################################
#                    Befehl nach Procedure ausführen
###################################################################################
sub DbRep_afterproc ($$) {
  my ($hash, $txt) = @_;
  my $name         = $hash->{NAME};
  my $erread;
  
  # Befehl nach Procedure ausführen
  no warnings 'uninitialized'; 
  my $ead = AttrVal($name, "executeAfterProc", undef);
  if($ead) {
      Log3 ($name, 4, "DbRep $name - execute command after $txt: '$ead' ");
	  my $err = AnalyzeCommandChain(undef, $ead);     
	  if ($err) {
          Log3 ($name, 2, "DbRep $name - command after $txt message: \"$err\" ");
		  ReadingsSingleUpdateValue ($hash, "after".$txt."_message", $err, 1);
		  $erread = "Warning - $txt finished, but command after $txt message appeared";
      }
  }

return $erread;  
}

##############################################################################################
#   timestamp_begin, timestamp_end bei Einsatz datetime-Picker entsprechend
#   den Anforderungen formatieren     
##############################################################################################
sub DbRep_formatpicker ($) {   
  my ($str) = @_;    
  if ($str =~ /^(\d{4})-(\d{2})-(\d{2})_(\d{2}):(\d{2})$/) {
      # Anpassung für datetime-Picker Widget
	  $str =~ s/_/ /;
	  $str = $str.":00";
  }
  if ($str =~ /^(\d{4})-(\d{2})-(\d{2})_(\d{2}):(\d{2}):(\d{2})$/) {
      # Anpassung für datetime-Picker Widget
	  $str =~ s/_/ /;
  }  
return $str;		
}

####################################################################################################
#    userexit - Funktion um userspezifische Programmaufrufe nach Aktualisierung eines Readings
#    zu ermöglichen, arbeitet OHNE Event abhängig vom Attr userExitFn
#
#    Aufruf der <UserExitFn> mit $name,$reading,$value
####################################################################################################
sub DbRep_userexit ($$$) {
 my ($name,$reading,$value) = @_;
 my $hash = $defs{$name};
 
 return if(!$hash->{HELPER}{USEREXITFN});
 
 if(!defined($reading)) {$reading = "";}
 if(!defined($value))   {$value   = "";}
 $value =~ s/\\/\\\\/g;  # escapen of chars for evaluation
 $value =~ s/'/\\'/g; 
 
 my $re = $hash->{HELPER}{UEFN_REGEXP}?$hash->{HELPER}{UEFN_REGEXP}:".*:.*";
			 
 if("$reading:$value" =~ m/^$re$/ ) {
     my @res;
	 my $cmd = $hash->{HELPER}{USEREXITFN}."('$name','$reading','$value')";
     $cmd  = "{".$cmd."}";
	 my $r = AnalyzeCommandChain(undef, $cmd);
 }
return;
}

####################################################################################################
#                 delete Readings before new operation
####################################################################################################
sub DbRep_delread($;$$) {
 # Readings löschen die nicht in der Ausnahmeliste (Attr readingPreventFromDel) stehen
 my ($hash,$shutdown) = @_;
 my $name   = $hash->{NAME};
 my @allrds = keys%{$defs{$name}{READINGS}};
 if($shutdown) {
     my $do = 0;
     foreach my $key(@allrds) {
         # Highlighted Readings löschen und save statefile wegen Inkompatibilitär beim Restart
         if($key =~ /<html><span/) {
             $do = 1;
             delete($defs{$name}{READINGS}{$key});
         }
     }
     WriteStatefile() if($do == 1);
     return undef;
 } 
 my @rdpfdel = split(",", $hash->{HELPER}{RDPFDEL}) if($hash->{HELPER}{RDPFDEL});
 if(@rdpfdel) {
     foreach my $key(@allrds) {
         # Log3 ($name, 1, "DbRep $name - Reading Schlüssel: $key");
         my $dodel = 1;
         foreach my $rdpfdel(@rdpfdel) {
             if($key =~ /$rdpfdel/ || $key eq "state") {
                 $dodel = 0;
             }
         }
         if($dodel) {
             delete($defs{$name}{READINGS}{$key});
         }
     }
 } else {
     foreach my $key(@allrds) {
         # Log3 ($name, 1, "DbRep $name - Reading Schlüssel: $key");
         delete($defs{$name}{READINGS}{$key}) if($key ne "state");
     }
 }
return undef;
}

####################################################################################################
#                          erstellen neues SQL-File für Dumproutine
####################################################################################################
sub DbRep_NewDumpFilename ($$$$$){
    my ($sql_text,$dump_path,$dbname,$time_stamp,$character_set) = @_;
	my $part       = "";
    my $sql_file   = $dump_path.$dbname."_".$time_stamp.$part.".sql";
    my $backupfile = $dbname."_".$time_stamp.$part.".sql";
    
    $sql_text .= "/*!40101 SET NAMES '".$character_set."' */;\n";
    $sql_text .= "SET FOREIGN_KEY_CHECKS=0;\n";
    
    my ($filesize,$err) = DbRep_WriteToDumpFile($sql_text,$sql_file);
	if($err) {
	    return (undef,undef,undef,undef,$err);
	}
    chmod(0777,$sql_file);
    $sql_text        = "";
    my $first_insert = 0;
	
return ($sql_text,$first_insert,$sql_file,$backupfile,undef);
}

####################################################################################################
#                          Schreiben DB-Dumps in SQL-File
####################################################################################################
sub DbRep_WriteToDumpFile ($$) {
    my ($inh,$sql_file) = @_;
    my $filesize;
	my $err = 0;
    
    if(length($inh) > 0) {
        unless(open(DATEI,">>$sql_file")) {
		    $err = "Can't open file '$sql_file' for write access";
		    return (undef,$err);
		}
        print DATEI $inh;
        close(DATEI);
       
        $filesize = (stat($sql_file))[7];
    }

return ($filesize,undef);
}

####################################################################################################
#             Filesize (Byte) umwandeln in KB bzw. MB
####################################################################################################
sub DbRep_byteOutput ($) {
    my $bytes  = shift;
	
	return if(!defined($bytes));
	return $bytes if(!looks_like_number($bytes));
    my $suffix = "Bytes";
    if ($bytes >= 1024) { $suffix = "KB"; $bytes = sprintf("%.2f",($bytes/1024));};
    if ($bytes >= 1024) { $suffix = "MB"; $bytes = sprintf("%.2f",($bytes/1024));};
    my $ret = sprintf "%.2f",$bytes;
    $ret.=' '.$suffix;

return $ret;
}

####################################################################################################
#                      Schreibroutine in DbRep Keyvalue-File
####################################################################################################
sub DbRep_setCmdFile($$$) {
  my ($key,$value,$hash) = @_;
  my $fName = $attr{global}{modpath}."/FHEM/FhemUtils/cacheDbRep";
  
  my $param = {
               FileName   => $fName,
               ForceType  => "file",
              };
  my ($err, @old) = FileRead($param);
  
  DbRep_createCmdFile($hash) if($err); 
  
  my @new;
  my $fnd;
  foreach my $l (@old) {
    if($l =~ m/^$key:/) {
      $fnd = 1;
      push @new, "$key:$value" if(defined($value));
    } else {
      push @new, $l;
    }
  }
  push @new, "$key:$value" if(!$fnd && defined($value));

return FileWrite($param, @new);
}

####################################################################################################
#                           anlegen Keyvalue-File für DbRep wenn nicht vorhanden
####################################################################################################
sub DbRep_createCmdFile ($) {
  my ($hash) = @_;
  my $fName  = $attr{global}{modpath}."/FHEM/FhemUtils/cacheDbRep";
  
  my $param = {
               FileName   => $fName,
               ForceType  => "file",
              };
  my @new;
  push(@new, "# This file is auto generated from 93_DbRep.",
             "# Please do not modify, move or delete it.",
             "");

return FileWrite($param, @new);
}

####################################################################################################
#                       Leseroutine aus DbRep Keyvalue-File
####################################################################################################
sub DbRep_getCmdFile($) {
  my ($key) = @_;
  my $fName = $attr{global}{modpath}."/FHEM/FhemUtils/cacheDbRep";
  my $param = {
               FileName   => $fName,
               ForceType  => "file",
              };
  my ($err, @l) = FileRead($param);
  return ($err, undef) if($err);
  for my $l (@l) {
    return (undef, $1) if($l =~ m/^$key:(.*)/);
  }

return (undef, undef);
}

####################################################################################################
#             Tabellenoptimierung MySQL
####################################################################################################
sub DbRep_mysqlOptimizeTables ($$@) {
  my ($hash,$dbh,@tablenames) = @_;
  my $name   = $hash->{NAME};
  my $dbname = $hash->{DATABASE};
  my $ret    = 0;
  my $opttbl = 0;
  my $db_tables = $hash->{HELPER}{DBTABLES};
  my ($engine,$tablename,$query,$sth,$value,$db_MB_start,$db_MB_end);

  # Anfangsgröße ermitteln
  $query = "SELECT sum( data_length + index_length ) / 1024 / 1024 FROM information_schema.TABLES where table_schema='$dbname' "; 
  Log3 ($name, 5, "DbRep $name - current query: $query ");
  eval { $sth = $dbh->prepare($query);
         $sth->execute;
	   };
  if ($@) {
      Log3 ($name, 2, "DbRep $name - Error executing: '".$query."' ! MySQL-Error: ".$@);
	  $sth->finish;
	  $dbh->disconnect;
      return ($@,undef,undef);
  }
  $value = $sth->fetchrow();
	 
  $db_MB_start = sprintf("%.2f",$value);
  Log3 ($name, 3, "DbRep $name - Size of database $dbname before optimize (MB): $db_MB_start");
     
  Log3($name, 3, "DbRep $name - Optimizing tables");
  
  foreach $tablename (@tablenames) {
      #optimize table if engine supports optimization
	  $engine = '';
      $engine = uc($db_tables->{$tablename}{Engine}) if($db_tables->{$tablename}{Engine});

	  if ($engine =~ /(MYISAM|BDB|INNODB|ARIA)/) {
	      Log3($name, 3, "DbRep $name - Optimizing table `$tablename` ($engine). It will take a while.");
          my $sth_to = $dbh->prepare("OPTIMIZE TABLE `$tablename`");
          $ret = $sth_to->execute; 
           
 		  if ($ret) {
              Log3($name, 3, "DbRep $name - Table ".($opttbl+1)." `$tablename` optimized successfully.");
			  $opttbl++;
          } else {
			  Log3($name, 2, "DbRep $name - Error while optimizing table $tablename. Continue with next table or backup.");
          }
      }
  }

  Log3($name, 3, "DbRep $name - $opttbl tables have been optimized.") if($opttbl > 0);
	 
  # Endgröße ermitteln
  eval { $sth->execute; };
  if ($@) {
      Log3 ($name, 2, "DbRep $name - Error executing: '".$query."' ! MySQL-Error: ".$@);
	  $sth->finish;
	  $dbh->disconnect;
      return ($@,undef,undef);
  }
  
  $value = $sth->fetchrow();
  $db_MB_end = sprintf("%.2f",$value);
  Log3 ($name, 3, "DbRep $name - Size of database $dbname after optimize (MB): $db_MB_end");
	 
  $sth->finish;
  
return (undef,$db_MB_start,$db_MB_end);
}

####################################################################################################
#             Dump-Files im dumpDirLocal löschen bis auf die letzten "n" 
####################################################################################################
sub DbRep_deldumpfiles ($$) {
  my ($hash,$bfile) = @_; 
  my $name          = $hash->{NAME};
  my $dbloghash     = $hash->{dbloghash};
  my $dump_path_def = $attr{global}{modpath}."/log/";
  my $dump_path_loc = AttrVal($name,"dumpDirLocal", $dump_path_def);
  my $dfk           = AttrVal($name,"dumpFilesKeep", 3);
  my $pfix          = (split '\.', $bfile)[1];
  my $dbname        = (split '_', $bfile)[0];
  my $file          = $dbname."_.*".$pfix.".*";    # Files mit/ohne Endung "gzip" berücksichtigen
  my @fd;

  if(!opendir(DH, $dump_path_loc)) {
      push(@fd, "No files deleted - Can't open path '$dump_path_loc'");
      return @fd;
  }
  my @files = sort grep {/^$file$/} readdir(DH);
  @files = sort { (stat("$dump_path_loc/$a"))[9] cmp (stat("$dump_path_loc/$b"))[9] } @files
        if(AttrVal("global", "archivesort", "alphanum") eq "timestamp");
  closedir(DH);
  
  Log3($name, 5, "DbRep $name - Dump files have been found in dumpDirLocal '$dump_path_loc': ".join(', ',@files) );
  
  my $max = int(@files)-$dfk;
  
  for(my $i = 0; $i < $max; $i++) {
      push(@fd, $files[$i]);
      Log3($name, 3, "DbRep $name - Deleting old dumpfile '$files[$i]' ");
      unlink("$dump_path_loc/$files[$i]");
  }

return @fd;
}

####################################################################################################
#                                  Dumpfile  komprimieren  
####################################################################################################
sub DbRep_dumpCompress ($$) {
  my ($hash,$bfile) = @_; 
  my $name          = $hash->{NAME};
  my $dump_path_def = $attr{global}{modpath}."/log/";
  my $dump_path_loc = AttrVal($name,"dumpDirLocal", $dump_path_def);
  $dump_path_loc    =~ s/(\/$|\\$)//;
  my $input         = $dump_path_loc."/".$bfile;
  my $output        = $dump_path_loc."/".$bfile.".gzip";

  Log3($name, 3, "DbRep $name - compress file $input");
  
  my $stat = gzip $input => $output ,BinModeIn => 1;
  if($GzipError) {
      Log3($name, 2, "DbRep $name - gzip of $input failed: $GzipError");
      return ($GzipError,$input);
  }
  
  Log3($name, 3, "DbRep $name - file compressed to output file: $output");
  unlink("$input");
  Log3($name, 3, "DbRep $name - input file deleted: $input");

return (undef,$bfile.".gzip");
}

####################################################################################################
#                                  Dumpfile dekomprimieren  
####################################################################################################
sub DbRep_dumpUnCompress ($$) {
  my ($hash,$bfile) = @_; 
  my $name          = $hash->{NAME};
  my $dump_path_def = $attr{global}{modpath}."/log/";
  my $dump_path_loc = AttrVal($name,"dumpDirLocal", $dump_path_def);
  $dump_path_loc    =~ s/(\/$|\\$)//;
  my $input         = $dump_path_loc."/".$bfile;
  my $outfile       = $bfile;
  $outfile          =~ s/\.gzip//;
  my $output        = $dump_path_loc."/".$outfile;

  Log3($name, 3, "DbRep $name - uncompress file $input");
  
  my $stat = gunzip $input => $output ,BinModeOut => 1;
  if($GunzipError) {
      Log3($name, 2, "DbRep $name - gunzip of $input failed: $GunzipError");
      return ($GunzipError,$input);
  }
  
  Log3($name, 3, "DbRep $name - file uncompressed to output file: $output");
  
  # Größe dekomprimiertes File ermitteln
  my @a = split(' ',qx(du $output)) if ($^O =~ m/linux/i || $^O =~ m/unix/i);
 
  my $filesize = ($a[0])?($a[0]*1024):undef;
  my $fsize    = DbRep_byteOutput($filesize);
  Log3 ($name, 3, "DbRep $name - Size of uncompressed file: ".$fsize);

return (undef,$outfile);
}

####################################################################################################
#             erzeugtes Dump-File aus dumpDirLocal zum FTP-Server übertragen 
####################################################################################################
sub DbRep_sendftp ($$) {
  my ($hash,$bfile) = @_; 
  my $name          = $hash->{NAME};
  my $dump_path_def = $attr{global}{modpath}."/log/";
  my $dump_path_loc = AttrVal($name,"dumpDirLocal", $dump_path_def);
  my $file          = (split /[\/]/, $bfile)[-1];
  my $ftpto         = AttrVal($name,"ftpTimeout",30);
  my $ftpUse        = AttrVal($name,"ftpUse",0);   
  my $ftpuseSSL     = AttrVal($name,"ftpUseSSL",0); 
  my $ftpDir        = AttrVal($name,"ftpDir","/");
  my $ftpPort       = AttrVal($name,"ftpPort",21);   
  my $ftpServer     = AttrVal($name,"ftpServer",undef);
  my $ftpUser       = AttrVal($name,"ftpUser","anonymous");
  my $ftpPwd        = AttrVal($name,"ftpPwd",undef);
  my $ftpPassive    = AttrVal($name,"ftpPassive",0);
  my $ftpDebug      = AttrVal($name,"ftpDebug",0);
  my $fdfk          = AttrVal($name,"ftpDumpFilesKeep", 3);
  my $pfix          = (split '\.', $bfile)[1];
  my $dbname        = (split '_', $bfile)[0];
  my $ftpl          = $dbname."_.*".$pfix.".*";    # Files mit/ohne Endung "gzip" berücksichtigen
  my ($ftperr,$ftpmsg,$ftp);
  
  # kein FTP verwenden oder möglich
  return ($ftperr,$ftpmsg) if((!$ftpUse && !$ftpuseSSL) || !$bfile);
  
  if(!$ftpServer) {
      $ftperr = "FTP-Error: FTP-Server isn't set.";
	  Log3($name, 2, "DbRep $name - $ftperr");
      return ($ftperr,undef);
  }

  if(!opendir(DH, $dump_path_loc)) {
      $ftperr = "FTP-Error: Can't open path '$dump_path_loc'";
	  Log3($name, 2, "DbRep $name - $ftperr");
	  return ($ftperr,undef);
  }
  
  my $mod_ftpssl = 0;
  my $mod_ftp    = 0;
  my $mod;
  
  if ($ftpuseSSL) {
      # FTP mit SSL soll genutzt werden
	  $mod = "Net::FTPSSL => e.g. with 'sudo cpan -i Net::FTPSSL' ";
      eval { require Net::FTPSSL; };
      if(!$@){
          $mod_ftpssl = 1;
          import Net::FTPSSL;
      }
  } else {
      # nur FTP
      $mod = "Net::FTP";
      eval { require Net::FTP; };
      if(!$@){
          $mod_ftp = 1;
          import Net::FTP;
      }
  }

  if ($ftpuseSSL && $mod_ftpssl) {    
      # use ftp-ssl
	  my $enc = "E";
      eval { $ftp = Net::FTPSSL->new($ftpServer, Port => $ftpPort, Timeout => $ftpto, Debug => $ftpDebug, Encryption => $enc) }
	             or $ftperr = "FTP-SSL-ERROR: Can't connect - $@";
  } elsif (!$ftpuseSSL && $mod_ftp) {    
      # use plain ftp
      eval { $ftp = Net::FTP->new($ftpServer, Port => $ftpPort, Timeout => $ftpto, Debug => $ftpDebug, Passive => $ftpPassive) }
	             or $ftperr = "FTP-Error: Can't connect - $@";
  } else {
      $ftperr = "FTP-Error: required module couldn't be loaded. You have to install it first: $mod.";
  }
  if ($ftperr) {
      Log3($name, 2, "DbRep $name - $ftperr");
      return ($ftperr,undef);
  }
  
  my $pwdstr = $ftpPwd?$ftpPwd:" ";          
  $ftp->login($ftpUser, $ftpPwd) or $ftperr = "FTP-Error: Couldn't login with user '$ftpUser' and password '$pwdstr' ";
  if ($ftperr) {
      Log3($name, 2, "DbRep $name - $ftperr");
      return ($ftperr,undef);
  }
  
  $ftp->binary();
  
  # FTP Verzeichnis setzen
  $ftp->cwd($ftpDir) or $ftperr = "FTP-Error: Couldn't change directory to '$ftpDir' ";
  if ($ftperr) {
      Log3($name, 2, "DbRep $name - $ftperr");
      return ($ftperr,undef);
  }
  
  $dump_path_loc =~ s/(\/$|\\$)//;  
  Log3($name, 3, "DbRep $name - FTP: transferring ".$dump_path_loc."/".$file);
  
  $ftpmsg = $ftp->put($dump_path_loc."/".$file);
  if (!$ftpmsg) {
      $ftperr = "FTP-Error: Couldn't transfer ".$file." to ".$ftpServer." into dir ".$ftpDir;
	  Log3($name, 2, "DbRep $name - $ftperr");
  } else {
      $ftpmsg = "FTP: ".$file." transferred successfully to ".$ftpServer." into dir ".$ftpDir; 
      Log3($name, 3, "DbRep $name - $ftpmsg");	  
  }
  
  # Versionsverwaltung FTP-Verzeichnis
  my (@ftl,@ftpfd);
  if($ftpuseSSL) {
      @ftl = sort grep {/^$ftpl$/} $ftp->nlst();
  } else {
      @ftl = sort grep {/^$ftpl$/} @{$ftp->ls()};
  }
  Log3($name, 5, "DbRep $name - FTP: filelist of \"$ftpDir\": @ftl");
  my $max = int(@ftl)-$fdfk;
  for(my $i = 0; $i < $max; $i++) {
      push(@ftpfd, $ftl[$i]);
      Log3($name, 3, "DbRep $name - FTP: deleting old dumpfile '$ftl[$i]' ");
      $ftp->delete($ftl[$i]);
  }

return ($ftperr,$ftpmsg,@ftpfd);
}

####################################################################################################
#                 Test auf Daylight saving time
####################################################################################################
sub DbRep_dsttest ($$$) {
 my ($hash,$runtime,$aggsec) = @_;
 my $name = $hash->{NAME};
 my $dstchange = 0;

 # der Wechsel der daylight saving time wird dadurch getestet, dass geprüft wird 
 # ob im Vergleich der aktuellen zur nächsten Selektionsperiode von "$aggsec (day, week, month)" 
 # ein Wechsel der daylight saving time vorliegt

 my $dst      = (localtime($runtime))[8];                      # ermitteln daylight saving aktuelle runtime
 my $time_str = localtime($runtime+$aggsec);                   # textual time representation
 my $dst_new  = (localtime($runtime+$aggsec))[8];              # ermitteln daylight saving nächste runtime

 if ($dst != $dst_new) {
     $dstchange = 1;
 }

 Log3 ($name, 5, "DbRep $name - Daylight savings changed: $dstchange (on $time_str)"); 

return $dstchange;
}

####################################################################################################
#                          Counthash Untersuchung 
#  Logausgabe der Anzahl verarbeiteter Datensätze pro Zeitraum / Aggregation
#  Rückgabe eines ncp-hash (no calc in period) mit den Perioden für die keine Differenz berechnet
#  werden konnte weil nur ein Datensatz in der Periode zur Verfügung stand
####################################################################################################
sub DbRep_calcount ($$) {
 my ($hash,$ch) = @_;
 my $name = $hash->{NAME};
 my %ncp = (); 
 
 Log3 ($name, 4, "DbRep $name - count of values used for calc:");
 foreach my $key (sort(keys%{$ch})) {
     Log3 ($name, 4, "$key => ". $ch->{$key});
     
	 if($ch->{$key} eq "1") {
	     $ncp{"$key"} = " ||";
	 } 
 }
return \%ncp;
}

####################################################################################################
#                         Funktionsergebnisse in Datenbank schreiben
####################################################################################################
sub DbRep_OutputWriteToDB($$$$$) {
  my ($name,$device,$reading,$arrstr,$optxt) = @_;
  my $hash       = $defs{$name};
  my $dbloghash  = $hash->{dbloghash};
  my $dbconn     = $dbloghash->{dbconn};
  my $dbuser     = $dbloghash->{dbuser};
  my $dblogname  = $dbloghash->{NAME};
  my $dbmodel    = $hash->{dbloghash}{MODEL};
  my $DbLogType  = AttrVal($hash->{dbloghash}{NAME}, "DbLogType", "History");
  my $supk       = AttrVal($hash->{dbloghash}{NAME}, "noSupportPK", 0);
  my $dbpassword = $attr{"sec$dblogname"}{secret};
  my $utf8       = defined($hash->{UTF8})?$hash->{UTF8}:0;
  $device        =~ s/[^A-Za-z\/\d_\.-]/\//g;
  $reading       =~ s/[^A-Za-z\/\d_\.-]/\//g;
  my $type       = "calculated";
  my $event      = "calculated";
  my $unit       = "";
  my $wrt        = 0;
  my $irowdone   = 0;
  my ($dbh,$sth_ih,$sth_uh,$sth_ic,$sth_uc,$err,$timestamp,$value,$date,$time,$rsf,$aggr,@row_array);
  
  if(!$hash->{dbloghash}{HELPER}{COLSET}) {
      $err = "No result of \"$hash->{LASTCMD}\" to database written. Cause: column width in \"$hash->{DEF}\" isn't set";
      return ($wrt,$irowdone,$err);
  }
  
  no warnings 'uninitialized';
  (undef,undef,$aggr) = DbRep_checktimeaggr($hash);
  $reading = $optxt."_".$aggr."_".$reading;
  
  $type = $defs{$device}{TYPE} if($defs{$device});                # $type vom Device ableiten
  
  if($optxt =~ /avg|sum/) {
      my @arr = split("\\|", $arrstr);
      foreach my $row (@arr) {
          my @a              = split("#", $row);
          my $runtime_string = $a[0];                             # Aggregations-Alias (nicht benötigt)
          $value             = $a[1]?sprintf("%.4f",$a[1]):undef;
          $rsf               = $a[2];                             # Datum / Zeit für DB-Speicherung
          ($date,$time)      = split("_",$rsf);
          $time              =~ s/-/:/g if($time);
          
          if($time !~ /^(\d{2}):(\d{2}):(\d{2})$/) {
              if($aggr =~ /no|day|week|month/) {
                  $time = "23:59:58";
              } elsif ($aggr =~ /hour/) {
                  $time = "$time:59:58";
              }
          }
          if ($value) {
              # Daten auf maximale Länge beschneiden (DbLog-Funktion !)
              ($device,$type,$event,$reading,$value,$unit) = DbLog_cutCol($hash->{dbloghash},$device,$type,$event,$reading,$value,$unit);
              push(@row_array, "$date $time|$device|$type|$event|$reading|$value|$unit");             
          } 
      }
  }

  if($optxt =~ /min|max|diff/) { 
      my %rh = split("§", $arrstr);
      foreach my $key (sort(keys(%rh))) {
          my @k         = split("\\|",$rh{$key});
          $rsf          = $k[2];                               # Datum / Zeit für DB-Speicherung
          $value        = $k[1]?sprintf("%.4f",$k[1]):undef;
          ($date,$time) = split("_",$rsf);
          $time         =~ s/-/:/g if($time);
      
          if($time !~ /^(\d{2}):(\d{2}):(\d{2})$/) {
              if($aggr =~ /no|day|week|month/) {
                  $time = "23:59:58";
              } elsif ($aggr =~ /hour/) {
                  $time = "$time:59:58";
              }
          }
          if ($value) {
              # Daten auf maximale Länge beschneiden (DbLog-Funktion !)
              ($device,$type,$event,$reading,$value,$unit) = DbLog_cutCol($hash->{dbloghash},$device,$type,$event,$reading,$value,$unit);
              push(@row_array, "$date $time|$device|$type|$event|$reading|$value|$unit");             
          } 
      }
  }  
  
  if (@row_array) {
      # Schreibzyklus aktivieren
      eval {$dbh = DBI->connect("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0, RaiseError => 1, AutoCommit => 1, mysql_enable_utf8 => $utf8 });};
      if ($@) {
          $err = $@;
          Log3 ($name, 2, "DbRep $name - $@");
          return ($wrt,$irowdone,$err);
      }
       
      # check ob PK verwendet wird, @usepkx?Anzahl der Felder im PK:0 wenn kein PK, $pkx?Namen der Felder:none wenn kein PK 
      my ($usepkh,$usepkc,$pkh,$pkc);
      if (!$supk) {
          ($usepkh,$usepkc,$pkh,$pkc) = DbRep_checkUsePK($hash,$dbloghash,$dbh);
      } else {
          Log3 $hash->{NAME}, 5, "DbRep $name -> Primary Key usage suppressed by attribute noSupportPK in DbLog \"$dblogname\"";
      }
      
      if (lc($DbLogType) =~ m(history)) {
          # insert history mit/ohne primary key
          if ($usepkh && $dbloghash->{MODEL} eq 'MYSQL') {
              eval { $sth_ih = $dbh->prepare_cached("INSERT IGNORE INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          } elsif ($usepkh && $dbloghash->{MODEL} eq 'SQLITE') {
              eval { $sth_ih = $dbh->prepare_cached("INSERT OR IGNORE INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          } elsif ($usepkh && $dbloghash->{MODEL} eq 'POSTGRESQL') {
              eval { $sth_ih = $dbh->prepare_cached("INSERT INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"); };
          } else {
              eval { $sth_ih = $dbh->prepare_cached("INSERT INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
          }
          if ($@) {
              $err = $@;
              Log3 ($name, 2, "DbRep $name - $@");
              return ($wrt,$irowdone,$err);
          }
		  # update history mit/ohne primary key
          if ($usepkh && $hash->{MODEL} eq 'MYSQL') {
		      $sth_uh = $dbh->prepare("REPLACE INTO history (TYPE, EVENT, VALUE, UNIT, TIMESTAMP, DEVICE, READING) VALUES (?,?,?,?,?,?,?)"); 
	      } elsif ($usepkh && $hash->{MODEL} eq 'SQLITE') {  
		      $sth_uh = $dbh->prepare("INSERT OR REPLACE INTO history (TYPE, EVENT, VALUE, UNIT, TIMESTAMP, DEVICE, READING) VALUES (?,?,?,?,?,?,?)");
	      } elsif ($usepkh && $hash->{MODEL} eq 'POSTGRESQL') {
		      $sth_uh = $dbh->prepare("INSERT INTO history (TYPE, EVENT, VALUE, UNIT, TIMESTAMP, DEVICE, READING) VALUES (?,?,?,?,?,?,?) ON CONFLICT ($pkc) 
		                               DO UPDATE SET TIMESTAMP=EXCLUDED.TIMESTAMP, DEVICE=EXCLUDED.DEVICE, TYPE=EXCLUDED.TYPE, EVENT=EXCLUDED.EVENT, READING=EXCLUDED.READING, 
								       VALUE=EXCLUDED.VALUE, UNIT=EXCLUDED.UNIT");
	      } else {
	          $sth_uh = $dbh->prepare("UPDATE history SET TYPE=?, EVENT=?, VALUE=?, UNIT=? WHERE (TIMESTAMP=?) AND (DEVICE=?) AND (READING=?)");
	      }
      }
      
      if (lc($DbLogType) =~ m(current) ) {
          # insert current mit/ohne primary key
	      if ($usepkc && $hash->{MODEL} eq 'MYSQL') {
              eval { $sth_ic = $dbh->prepare("INSERT IGNORE INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };	  
	      } elsif ($usepkc && $hash->{MODEL} eq 'SQLITE') {
	          eval { $sth_ic = $dbh->prepare("INSERT OR IGNORE INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
	      } elsif ($usepkc && $hash->{MODEL} eq 'POSTGRESQL') {
	          eval { $sth_ic = $dbh->prepare("INSERT INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"); };
	      } else {
	          # old behavior
	          eval { $sth_ic = $dbh->prepare("INSERT INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
	      }
          if ($@) {
              $err = $@;
              Log3 ($name, 2, "DbRep $name - $@");
              return ($wrt,$irowdone,$err);
          }
	      # update current mit/ohne primary key
          if ($usepkc && $hash->{MODEL} eq 'MYSQL') {
		      $sth_uc = $dbh->prepare("REPLACE INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); 
	      } elsif ($usepkc && $hash->{MODEL} eq 'SQLITE') {  
		      $sth_uc = $dbh->prepare("INSERT OR REPLACE INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)");
	      } elsif ($usepkc && $hash->{MODEL} eq 'POSTGRESQL') {
		      $sth_uc = $dbh->prepare("INSERT INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT ($pkc) 
		                               DO UPDATE SET TIMESTAMP=EXCLUDED.TIMESTAMP, DEVICE=EXCLUDED.DEVICE, TYPE=EXCLUDED.TYPE, EVENT=EXCLUDED.EVENT, READING=EXCLUDED.READING, 
								       VALUE=EXCLUDED.VALUE, UNIT=EXCLUDED.UNIT");
	      } else {
	          $sth_uc = $dbh->prepare("UPDATE current SET TIMESTAMP=?, TYPE=?, EVENT=?, VALUE=?, UNIT=? WHERE (DEVICE=?) AND (READING=?)");
	      }
      }
      
      eval { $dbh->begin_work() if($dbh->{AutoCommit}); };
      if ($@) {
          Log3($name, 2, "DbRep $name -> Error start transaction for history - $@");
      }
      
      Log3 $hash->{NAME}, 5, "DbRep $name - data prepared to db write:"; 
      
      # SQL-Startzeit
      my $wst = [gettimeofday]; 
      
	  my $ihs = 0;
	  my $uhs = 0;
      foreach my $row (@row_array) {
          my @a = split("\\|",$row);
          $timestamp = $a[0];
          $device    = $a[1];
          $type      = $a[2];
          $event     = $a[3];
          $reading   = $a[4];
          $value     = $a[5];
          $unit      = $a[6];
          Log3 $hash->{NAME}, 5, "DbRep $name - $row";
          
          eval {
              # update oder insert history
              if (lc($DbLogType) =~ m(history) ) {
                  my $rv_uh = $sth_uh->execute($type,$event,$value,$unit,$timestamp,$device,$reading); 
				  if ($rv_uh == 0) {
				      $sth_ih->execute($timestamp,$device,$type,$event,$reading,$value,$unit);
					  $ihs++; 
				  } else {
				      $uhs++;
				  }
              }
              # update oder insert current
              if (lc($DbLogType) =~ m(current) ) {
                  my $rv_uc = $sth_uc->execute($timestamp,$type,$event,$value,$unit,$device,$reading);
                  if ($rv_uc == 0) {
                      $sth_ic->execute($timestamp,$device,$type,$event,$reading,$value,$unit);
                  }
              }
          };
 
          if ($@) {
              $err = $@;
              Log3 ($name, 2, "DbRep $name - $@");
              $dbh->rollback;
              $dbh->disconnect;
	          $ihs = 0;
	          $uhs = 0;
              return ($wrt,0,$err);
          } else {
              $irowdone++;
          }
      }    
      
      eval {$dbh->commit() if(!$dbh->{AutoCommit});};
      $dbh->disconnect;
      
	  Log3 $hash->{NAME}, 3, "DbRep $name - number of lines updated in \"$dblogname\": $uhs"; 
      Log3 $hash->{NAME}, 3, "DbRep $name - number of lines inserted into \"$dblogname\": $ihs"; 
      
      # SQL-Laufzeit ermitteln
      $wrt = tv_interval($wst);
  } 
  
return ($wrt,$irowdone,$err);
}

####################################################################################################
#                              Werte eines Array in DB schreiben
# Übergabe-Array: $date_ESC_$time_ESC_$device_ESC_$type_ESC_$event_ESC_$reading_ESC_$value_ESC_$unit
# $histupd = 1 wenn history update, $histupd = 0 nur gistory insert
#
####################################################################################################
sub DbRep_WriteToDB($$$@) {
  my ($name,$dbh,$dbloghash,$histupd,@row_array) = @_;
  my $hash      = $defs{$name};
  my $dblogname = $dbloghash->{NAME};
  my $DbLogType = AttrVal($dbloghash->{NAME}, "DbLogType", "History");
  my $supk      = AttrVal($dbloghash->{NAME}, "noSupportPK", 0);
  my $wrt       = 0;
  my $irowdone  = 0;
  my ($sth_ih,$sth_uh,$sth_ic,$sth_uc,$err);
         
  # check ob PK verwendet wird, @usepkx?Anzahl der Felder im PK:0 wenn kein PK, $pkx?Namen der Felder:none wenn kein PK 
  my ($usepkh,$usepkc,$pkh,$pkc);
  if (!$supk) {
      ($usepkh,$usepkc,$pkh,$pkc) = DbRep_checkUsePK($hash,$dbloghash,$dbh);
  } else {
      Log3 $hash->{NAME}, 5, "DbRep $name -> Primary Key usage suppressed by attribute noSupportPK in DbLog \"$dblogname\"";
  }
      
  if (lc($DbLogType) =~ m(history)) {
      # insert history mit/ohne primary key
      if ($usepkh && $dbloghash->{MODEL} eq 'MYSQL') {
          eval { $sth_ih = $dbh->prepare_cached("INSERT IGNORE INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
      } elsif ($usepkh && $dbloghash->{MODEL} eq 'SQLITE') {
          eval { $sth_ih = $dbh->prepare_cached("INSERT OR IGNORE INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
      } elsif ($usepkh && $dbloghash->{MODEL} eq 'POSTGRESQL') {
          eval { $sth_ih = $dbh->prepare_cached("INSERT INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"); };
      } else {
          eval { $sth_ih = $dbh->prepare_cached("INSERT INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
      }
      if ($@) {
          $err = $@;
          Log3 ($name, 2, "DbRep $name - $@");
          return ($wrt,$irowdone,$err);
      }
	  # update history mit/ohne primary key
      if ($usepkh && $dbloghash->{MODEL} eq 'MYSQL') {
	      $sth_uh = $dbh->prepare("REPLACE INTO history (TYPE, EVENT, VALUE, UNIT, TIMESTAMP, DEVICE, READING) VALUES (?,?,?,?,?,?,?)"); 
	  } elsif ($usepkh && $dbloghash->{MODEL} eq 'SQLITE') {  
	      $sth_uh = $dbh->prepare("INSERT OR REPLACE INTO history (TYPE, EVENT, VALUE, UNIT, TIMESTAMP, DEVICE, READING) VALUES (?,?,?,?,?,?,?)");
	  } elsif ($usepkh && $dbloghash->{MODEL} eq 'POSTGRESQL') {
	      $sth_uh = $dbh->prepare("INSERT INTO history (TYPE, EVENT, VALUE, UNIT, TIMESTAMP, DEVICE, READING) VALUES (?,?,?,?,?,?,?) ON CONFLICT ($pkc) 
	                               DO UPDATE SET TIMESTAMP=EXCLUDED.TIMESTAMP, DEVICE=EXCLUDED.DEVICE, TYPE=EXCLUDED.TYPE, EVENT=EXCLUDED.EVENT, READING=EXCLUDED.READING, 
							       VALUE=EXCLUDED.VALUE, UNIT=EXCLUDED.UNIT");
	  } else {
	      $sth_uh = $dbh->prepare("UPDATE history SET TYPE=?, EVENT=?, VALUE=?, UNIT=? WHERE (TIMESTAMP=?) AND (DEVICE=?) AND (READING=?)");
	  }
  }
      
  if (lc($DbLogType) =~ m(current) ) {
      # insert current mit/ohne primary key
      if ($usepkc && $dbloghash->{MODEL} eq 'MYSQL') {
          eval { $sth_ic = $dbh->prepare("INSERT IGNORE INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };	  
      } elsif ($usepkc && $dbloghash->{MODEL} eq 'SQLITE') {
          eval { $sth_ic = $dbh->prepare("INSERT OR IGNORE INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
      } elsif ($usepkc && $dbloghash->{MODEL} eq 'POSTGRESQL') {
          eval { $sth_ic = $dbh->prepare("INSERT INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT DO NOTHING"); };
      } else {
          # old behavior
          eval { $sth_ic = $dbh->prepare("INSERT INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); };
      }
      if ($@) {
          $err = $@;
          Log3 ($name, 2, "DbRep $name - $@");
          return ($wrt,$irowdone,$err);
      }
      # update current mit/ohne primary key
      if ($usepkc && $dbloghash->{MODEL} eq 'MYSQL') {
	      $sth_uc = $dbh->prepare("REPLACE INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)"); 
      } elsif ($usepkc && $dbloghash->{MODEL} eq 'SQLITE') {  
	      $sth_uc = $dbh->prepare("INSERT OR REPLACE INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)");
      } elsif ($usepkc && $dbloghash->{MODEL} eq 'POSTGRESQL') {
	      $sth_uc = $dbh->prepare("INSERT INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?) ON CONFLICT ($pkc) 
	                               DO UPDATE SET TIMESTAMP=EXCLUDED.TIMESTAMP, DEVICE=EXCLUDED.DEVICE, TYPE=EXCLUDED.TYPE, EVENT=EXCLUDED.EVENT, READING=EXCLUDED.READING, 
							       VALUE=EXCLUDED.VALUE, UNIT=EXCLUDED.UNIT");
      } else {
          $sth_uc = $dbh->prepare("UPDATE current SET TIMESTAMP=?, TYPE=?, EVENT=?, VALUE=?, UNIT=? WHERE (DEVICE=?) AND (READING=?)");
      }
  }
      
  eval { $dbh->begin_work() if($dbh->{AutoCommit}); };
  if ($@) {
      Log3($name, 2, "DbRep $name -> Error start transaction for history - $@");
  }
      
  Log3 $hash->{NAME}, 5, "DbRep $name - data prepared to db write:"; 
      
  # SQL-Startzeit
  my $wst = [gettimeofday]; 
      
  my $ihs = 0;
  my $uhs = 0;
  foreach my $row (@row_array) {
      my ($date,$time,$device,$type,$event,$reading,$value,$unit) = ($row =~ /^(.*)_ESC_(.*)_ESC_(.*)_ESC_(.*)_ESC_(.*)_ESC_(.*)_ESC_(.*)_ESC_(.*)$/);
      Log3 $hash->{NAME}, 5, "DbRep $name - $row";     
      my $timestamp = $date." ".$time;
          
      eval {
          # update oder insert history
          if (lc($DbLogType) =~ m(history) ) {
              my $rv_uh = 0;
              if($histupd) {
                  $rv_uh = $sth_uh->execute($type,$event,$value,$unit,$timestamp,$device,$reading); 
              }
			  if ($rv_uh == 0) {
			      $sth_ih->execute($timestamp,$device,$type,$event,$reading,$value,$unit);
				  $ihs++; 
			  } else {
			      $uhs++;
			  }
          }
          # update oder insert current
          if (lc($DbLogType) =~ m(current) ) {
              my $rv_uc = $sth_uc->execute($timestamp,$type,$event,$value,$unit,$device,$reading);
              if ($rv_uc == 0) {
                  $sth_ic->execute($timestamp,$device,$type,$event,$reading,$value,$unit);
              }
          }
      };
 
      if ($@) {
          $err = $@;
          Log3 ($name, 2, "DbRep $name - $@");
          $dbh->rollback;
          $ihs = 0;
          $uhs = 0;
          return ($wrt,0,$err);
      } else {
          $irowdone++;
      }
  }    
      
  eval {$dbh->commit() if(!$dbh->{AutoCommit});};
      
  Log3 $hash->{NAME}, 3, "DbRep $name - number of lines updated in \"$dblogname\": $uhs" if($uhs); 
  Log3 $hash->{NAME}, 3, "DbRep $name - number of lines inserted into \"$dblogname\": $ihs" if($ihs); 
      
  # SQL-Laufzeit ermitteln
  $wrt = tv_interval($wst);
  
return ($wrt,$irowdone,$err);
}

################################################################
# check ob primary key genutzt wird
################################################################
sub DbRep_checkUsePK ($$$){
  my ($hash,$dbloghash,$dbh) = @_;
  my $name       = $hash->{NAME};
  my $dbconn     = $dbloghash->{dbconn};
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
  Log3 $hash->{NAME}, 5, "DbRep $name -> Primary Key used in $db.history: $pkh";
  Log3 $hash->{NAME}, 5, "DbRep $name -> Primary Key used in $db.current: $pkc";

return ($upkh,$upkc,$pkh,$pkc);
}

################################################################
# extrahiert aus dem übergebenen Wert nur die Zahl
################################################################
sub DbRep_numval ($){
  my ($val) = @_;
  return undef if(!defined($val));
  $val = ($val =~ /(-?\d+(\.\d+)?)/ ? $1 : "");
  
return $val;
}

####################################################################################################
# Browser Refresh nach DB-Abfrage
####################################################################################################
sub browser_refresh($) { 
  my ($hash) = @_;                                                                     
  RemoveInternalTimer($hash, "browser_refresh");
  {FW_directNotify("#FHEMWEB:WEB", "location.reload('true')", "")};
  #  map { FW_directNotify("#FHEMWEB:$_", "location.reload(true)", "") } devspec2array("WEB.*");
return;
}

####################################################################################################
#                 Test-Sub zu Testzwecken
####################################################################################################
sub testexit ($) {
my ($hash) = @_;
my $name = $hash->{NAME};

 if ( !DbRep_Connect($hash) ) {
     Log3 ($name, 2, "DbRep $name - DB connect failed. Database down ? ");
     ReadingsSingleUpdateValue ($hash, "state", "disconnected", 1);
     return;
 } else {
     my $dbh = $hash->{DBH};
     Log3 ($name, 3, "DbRep $name - --------------- FILE INFO --------------"); 
     my $sqlfile = $dbh->sqlite_db_filename();
     Log3 ($name, 3, "DbRep $name - FILE : $sqlfile ");
#     # $dbh->table_info( $catalog, $schema, $table)
#     my $sth = $dbh->table_info('', '%', '%');
#     my $tables = $dbh->selectcol_arrayref($sth, {Columns => [3]});
#     my $table = join ', ', @$tables;
#     Log3 ($name, 3, "DbRep $name - SQL_TABLES : $table"); 
     
     Log3 ($name, 3, "DbRep $name - --------------- PRAGMA --------------"); 
     my @InfoTypes =  ('sqlite_db_status');

    
   foreach my $row (@InfoTypes) {
       # my @linehash =  $dbh->$row;
       
       my $array= $dbh->$row ;
       # push(@row_array, @array);
       while ((my $key, my $val) = each %{$array}) {
       Log3 ($name, 3, "DbRep $name - PRAGMA : $key : ".%{$val});
       }
       
    }
    # $sth->finish;
   
    $dbh->disconnect;
 }
return;
}


1;

=pod
=item helper
=item summary    Reporting & Management content of DbLog-DB's. Content is depicted as readings
=item summary_DE Reporting & Management von DbLog-DB Content. Darstellung als Readings
=begin html

<a name="DbRep"></a>
<h3>DbRep</h3>
<ul>
  <br>
  The purpose of this module is browsing and managing the content of DbLog-databases. The searchresults can be evaluated concerning to various aggregations and the appropriate 
  Readings will be filled. The data selection will been done by declaration of device, reading and the time settings of selection-begin and selection-end.  <br><br>
  
  All database operations are implemented nonblocking. Optional the execution time of SQL-statements in background can also be determined and provided as reading.
  (refer to <a href="#DbRepattr">attributes</a>). <br>
  All existing readings will be deleted when a new operation starts. By attribute "readingPreventFromDel" a comma separated list of readings which are should prevent
  from deletion can be provided. <br><br>
  
  Currently the following functions are provided: <br><br>
  
     <ul><ul>
     <li> Selection of all datasets within adjustable time limits. </li>
     <li> Exposure of datasets of a Device/Reading-combination within adjustable time limits. </li>
     <li> Selection of datasets by usage of dynamically calclated time limits at execution time. </li>
     <li> Highlighting doublets when select and display datasets (fetchrows) </li>
     <li> Calculation of quantity of datasets of a Device/Reading-combination within adjustable time limits and several aggregations. </li>
     <li> The calculation of summary-, difference-, maximum-, minimum- and averageValues of numeric readings within adjustable time limits and several aggregations. </li>
     <li> write back results of summary-, difference-, maximum-, minimum- and average calculation into the database </li>
     <li> The deletion of datasets. The containment of deletion can be done by Device and/or Reading as well as fix or dynamically calculated time limits at execution time. </li>
     <li> export of datasets to file (CSV-format). </li>
     <li> import of datasets from file (CSV-Format). </li>
     <li> rename of device/readings in datasets </li>
     <li> change of reading values in the database </li>
     <li> automatic rename of device names in datasets and other DbRep-definitions after FHEM "rename" command (see <a href="#DbRepAutoRename">DbRep-Agent</a>) </li>
	 <li> Execution of arbitrary user specific SQL-commands </li>
	 <li> creation of backups of the database in running state non-blocking (MySQL, SQLite) </li>
	 <li> transfer dumpfiles to a FTP server after backup incl. version control</li>
	 <li> restore of SQLite-dumps and MySQL serverSide-backups non-blocking </li>
	 <li> optimize the connected database (optimizeTables, vacuum) </li>
	 <li> report of existing database processes (MySQL) </li>
	 <li> purge content of current-table </li>
	 <li> fill up the current-table with a (tunable) extract of the history-table</li>
	 <li> delete consecutive datasets with different timestamp but same values (clearing up consecutive doublets) </li>
     <li> Repair of a corrupted SQLite database ("database disk image is malformed") </li>
     <li> transmission of datasets from source database into another (Standby) database (syncStandby) </li>
     </ul></ul>
     <br>
     
  To activate the function "Autorename" the attribute "role" has to be assigned to a defined DbRep-device. The standard role after DbRep definition is "Client.
  Please read more in section <a href="#DbRepAutoRename">DbRep-Agent</a> . <br><br>
  
  DbRep provides a UserExit function. By that interface the user can execute own program code dependent from free 
  definable Reading/Value-combinations (Regex). The interface works without respectively independent from event 
  generation.
  Further informations you can find as described at <a href="#DbRepattr">attribute</a> "userExitFn". <br><br>
  
  FHEM-Forum: <br>
  <a href="https://forum.fhem.de/index.php/topic,53584.msg452567.html#msg452567">Modul 93_DbRep - Reporting and Management of database content (DbLog)</a>.<br><br>
 
  <br>
   
  <b>Preparations </b> <br><br>
  
  The module requires the usage of a DbLog instance and the credentials of the database definition will be used. <br>
  Only the content of table "history" will be included if isn't other is explained. <br><br>
  
  Overview which other Perl-modules DbRep is using: <br><br>
  
  Net::FTP     (only if FTP-Transfer after database dump is used)     <br>
  Net::FTPSSL  (only if FTP-Transfer with encoding after database dump is used)   <br>  
  POSIX           <br>
  Time::HiRes     <br>
  Time::Local     <br>
  Scalar::Util    <br>
  DBI             <br>
  Color           (FHEM-module) <br>
  IO::Compress::Gzip            <br>
  IO::Uncompress::Gunzip        <br>
  Blocking        (FHEM-module) <br><br>
  
  Due to performance reason the following index should be created in addition: <br>
  <code>
  CREATE INDEX Report_Idx ON `history` (TIMESTAMP, READING) USING BTREE;
  </code>
</ul>
<br>

<a name="DbRepdefine"></a>
<b>Definition</b>

<br>
<ul>
  <code>
    define &lt;name&gt; DbRep &lt;name of DbLog-instance&gt; 
  </code>
  
  <br><br>
  (&lt;name of DbLog-instance&gt; - name of the database instance which is wanted to analyze needs to be inserted)

</ul>

<br><br>

<a name="DbRepset"></a>
<b>Set </b>
<ul>

 Currently following set-commands are included. They are used to trigger the evaluations and define the evaluation option option itself.
 The criteria of searching database content and determine aggregation is carried out by setting several <a href="#DbRepattr">attributes</a>.
 <br><br>
 
 <ul><ul>
    <li><b> averageValue [display | writeToDB]</b> 
                                 - calculates the average value of database column "VALUE" between period given by 
                                 timestamp-<a href="#DbRepattr">attributes</a> which are set. 
                                 The reading to evaluate must be specified by attribute "reading".  <br>
                                 By attribute "averageCalcForm" the calculation variant for average determination will be configured.
                                 At the moment the following methods are implemented: <br><br>

	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>avgArithmeticMean</b>  </td><td>: the arithmetic average is calculated (default) </td></tr>
                                      <tr><td> <b>avgDailyMeanGWS</b>    </td><td>: calculates the daily medium temperature according the 
                                                                                    <a href='https://www.dwd.de/DE/leistungen/klimadatendeutschland/beschreibung_tagesmonatswerte.html'>specifications</a> of german weather service. <br>
                                                                                    This variant uses aggregation "day" automatically. </td></tr>
                                      <tr><td> <b>avgTimeWeightMean</b>  </td><td>: calcultes a time weighted average mean value is calculated </td></tr>
								   </table>
	                               </ul>
	                               <br>
                                 
                                 Is no or the option "display" specified, the results are only displayed. Using 
                                 option "writeToDB" the calculated results are stored in the database with a new reading
                                 name. <br>
                                 The new readingname is built of a prefix and the original reading name. 
                                 The prefix is made up of the creation function and the aggregation. <br>
                                 The timestamp of the new stored readings is deviated from aggregation period, 
                                 unless no unique point of time of the result can be determined. 
                                 The field "EVENT" will be filled with "calculated".<br><br>
                                 
                                 <ul>
                                 <b>Example of building a new reading name from the original reading "totalpac":</b> <br>
                                 avgam_day_totalpac <br>
                                 # &lt;creation function&gt;_&lt;aggregation&gt;_&lt;original reading&gt; <br>                         
                                 </ul>
                                 </li><br>
                                 
    <li><b> cancelDump </b>   -  stops a running database dump. </li> <br>
                                 
    <li><b> changeValue </b>  -  changes the saved value of readings.
                                 If the selection is limited to particular device/reading-combinations by  
                                 <a href="#DbRepattr">attribute</a> "device" respectively "reading", it is considered as well
                                 as possibly defined time limits by time attributes (time.*).  <br>
                                 If no limits are set, the whole database is scanned and the specified value will be 
                                 changed. <br><br>
                                 
                                 <ul>
                                 <b>Syntax: </b> <br>
                                 set &lt;name&gt; changeValue "&lt;old string&gt;","&lt;new string&gt;"  <br><br>
                                 
                                 The strings have to be quoted and separated by comma.
                                 A "string" can be: <br>
                                 
<pre>
&lt;old string&gt; : * a simple string with/without spaces, e.g. "OL 12"
               * a string with usage of SQL-wildcard, e.g. "%OL%"
                 
&lt;new string&gt; : * a simple string with/without spaces, e.g. "12 kWh"
               * Perl code embedded in {}, e.g. {$VALUE = (split(",",$VALUE))[0]}. 
                 The perl expression the variables $VALUE and $UNIT are committed to. The variables are changable within
                 the perl code. The returned value of VALUE and UNIT are saved into the database field 
                 VALUE respectively UNIT of the dataset.                        
</pre>
                                 
                                 <b>Examples: </b> <br>
                                 set &lt;name&gt; changeValue "OL","12 OL"  <br>               
                                 # the old field value "OL" is changed to "12 OL".  <br><br>
                                 
                                 set &lt;name&gt; changeValue "%OL%","12 OL"  <br>
                                 # contains the field VALUE the substring "OL", it is changed to "12 OL". <br><br>
                                 
                                 set &lt;name&gt; changeValue "12 kWh","{$VALUE,$UNIT = split(" ",$VALUE)}"  <br>
                                 # the old field value "12 kWh" is splitted to VALUE=12 and UNIT=kWh and saved into the database fields <br><br>

                                 set &lt;name&gt; changeValue "24%","{$VALUE = (split(" ",$VALUE))[0]}"  <br>
                                 # if the old field value begins with "24", it is splitted and VALUE=24 is saved (e.g. "24 kWh")
                                 <br><br>
                                 
                                 Summarized the relevant attributes to control function changeValue are: <br><br>

	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>device</b>            </td><td>: selection only of datasets which contain &lt;device&gt; </td></tr>
                                      <tr><td> <b>reading</b>           </td><td>: selection only of datasets which contain &lt;reading&gt; </td></tr>
                                      <tr><td> <b>time.*</b>            </td><td>: a number of attributes to limit selection by time </td></tr>
 	                                  <tr><td> <b>executeBeforeProc</b> </td><td>: execute a FHEM command (or perl-routine) before start of changeValue </td></tr>
                                      <tr><td> <b>executeAfterProc</b>  </td><td>: execute a FHEM command (or perl-routine) after changeValue is finished </td></tr>
                                      </table>
	                               </ul>
	                               <br>
	                               <br>
								 
								 <b>Note:</b> <br>
                                 Even though the function itself is designed non-blocking, make sure the assigned DbLog-device
                                 is operating in asynchronous mode to avoid FHEMWEB from blocking. <br><br> 
                                 </li> <br>
                                 </ul>
                                 
    <li><b> countEntries [history|current] </b> -  provides the number of table-entries (default: history) between period set 
	                                               by timestamp-<a href="#DbRepattr">attributes</a> if set. 
                                                   If timestamp-attributes are not set, all entries of the table will be count. 
												   The <a href="#DbRepattr">attributes</a> "device" and "reading" can be used to 
												   limit the evaluation.  </li> <br>
                                                   
                           
    <li><b> delEntries </b>   -  deletes all database entries or only the database entries specified by <a href="#DbRepattr">attributes</a> Device and/or 
	                             Reading and the entered time period between "timestamp_begin", "timestamp_end" (if set) or "timeDiffToNow/timeOlderThan". <br><br>
                                 
                                 <ul>
                                 "timestamp_begin" is set:  deletes db entries <b>from</b> this timestamp until current date/time <br>
                                 "timestamp_end" is set  :  deletes db entries <b>until</b> this timestamp <br>
                                 both Timestamps are set :  deletes db entries <b>between</b> these timestamps <br><br>
                                 
                                 Due to security reasons the attribute <a href="#DbRepattr">attribute</a> "allowDeletion" needs to be set to unlock the 
								 delete-function. <br>
                                 </li>
								 <br>
                                 </ul>
								 
    <li><b> delSeqDoublets [adviceRemain | adviceDelete | delete]</b> -  show respectively delete identical sequentially datasets.
                                 Therefore Device,Reading and Value of the sequentially datasets are compared.
	                             Not deleted are the first und the last dataset of a aggregation period (e.g. hour,day,week and so on) as 
								 well as the datasets before or after a value change (database field VALUE). <br>
								 The <a href="#DbRepattr">attributes</a> to define the scope of aggregation,time period, device and reading are 
								 considered. If attribute aggregation is not set or set to "no", it will change to the default aggregation 
								 period "day". For datasets containing numerical values it is possible to determine a variance with <a href="#DbRepattr">attribute</a>
                                 "seqDoubletsVariance". Up to this value consecutive numerical datasets are handled as identical and should be 
                                 deleted.
	                             <br><br>
								 
	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>adviceRemain</b>  </td><td>: simulates the remaining datasets in database after delete-operation (nothing will be deleted !) </td></tr>
                                      <tr><td> <b>adviceDelete</b>  </td><td>: simulates the datasets to delete in database (nothing will be deleted !) </td></tr>
                                      <tr><td> <b>delete</b>        </td><td>: deletes the consecutive doublets (see example) </td></tr>
                                   </table>
	                               </ul>
	                               <br>

                                 Due to security reasons the attribute <a href="#DbRepattr">attribute</a> "allowDeletion" needs to be set for 
								 execute the "delete" option. <br>
								 The amount of datasets to show by commands "delSeqDoublets adviceDelete", "delSeqDoublets adviceRemain" is 
								 initially limited (default: 1000) and can be adjusted by <a href="#DbRepattr">attribute</a> "limit".
								 The adjustment of "limit" has no impact to the "delSeqDoublets delete" function, but affects <b>ONLY</b> the 
								 display of the data.  <br>
							     Before and after this "delSeqDoublets" it is possible to execute a FHEM command or Perl-script 
                                 (please see <a href="#DbRepattr">attributes</a>  "executeBeforeProc" and "executeAfterProc"). 
                                 <br><br>                                 
								  
								 <ul>
								 <b>Example</b> - the remaining datasets after executing delete-option are are marked as <b>bold</b>: <br><br>
								 <ul>
                                 <b>2017-11-25_00-00-05__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 2017-11-25_00-02-26__eg.az.fridge_Pwr__power 0             <br>
                                 2017-11-25_00-04-33__eg.az.fridge_Pwr__power 0             <br>
                                 2017-11-25_01-06-10__eg.az.fridge_Pwr__power 0             <br>
                                 <b>2017-11-25_01-08-21__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 <b>2017-11-25_01-08-59__eg.az.fridge_Pwr__power 60.32 </b>     <br>
                                 <b>2017-11-25_01-11-21__eg.az.fridge_Pwr__power 56.26 </b>     <br>
                                 <b>2017-11-25_01-27-54__eg.az.fridge_Pwr__power 6.19  </b>     <br>
                                 <b>2017-11-25_01-28-51__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 2017-11-25_01-31-00__eg.az.fridge_Pwr__power 0             <br>
                                 2017-11-25_01-33-59__eg.az.fridge_Pwr__power 0             <br>
                                 <b>2017-11-25_02-39-29__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 <b>2017-11-25_02-41-18__eg.az.fridge_Pwr__power 105.28</b>     <br>
                                 <b>2017-11-25_02-41-26__eg.az.fridge_Pwr__power 61.52 </b>     <br>
                                 <b>2017-11-25_03-00-06__eg.az.fridge_Pwr__power 47.46 </b>     <br>
                                 <b>2017-11-25_03-00-33__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 2017-11-25_03-02-07__eg.az.fridge_Pwr__power 0             <br>
                                 2017-11-25_23-37-42__eg.az.fridge_Pwr__power 0             <br>
                                 <b>2017-11-25_23-40-10__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 <b>2017-11-25_23-42-24__eg.az.fridge_Pwr__power 1     </b>     <br>
                                 2017-11-25_23-42-24__eg.az.fridge_Pwr__power 1             <br>
                                 <b>2017-11-25_23-45-27__eg.az.fridge_Pwr__power 1     </b>     <br>
                                 <b>2017-11-25_23-47-07__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 2017-11-25_23-55-27__eg.az.fridge_Pwr__power 0             <br>
                                 <b>2017-11-25_23-48-15__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 <b>2017-11-25_23-50-21__eg.az.fridge_Pwr__power 59.1  </b>     <br>
                                 <b>2017-11-25_23-55-14__eg.az.fridge_Pwr__power 52.31 </b>     <br>
                                 <b>2017-11-25_23-58-09__eg.az.fridge_Pwr__power 51.73 </b>     <br>
                                 </ul>
								 </ul>
                                
                                 </li>
								 <br>
								 <br>
								 
    <li><b> deviceRename </b> -  renames the device name of a device inside the connected database (Internal DATABASE).
                                 The devicename will allways be changed in the <b>entire</b> database. Possibly set time limits or restrictions by 
                                 <a href="#DbRepattr">attributes</a> device and/or reading will not be considered.  <br><br>
                                 
                                 <ul>
                                 <b>Example: </b> <br> 
                                 set &lt;name&gt; deviceRename &lt;old device name&gt;,&lt;new device name&gt;  <br>               
                                 # The amount of renamed device names (datasets) will be displayed in reading "device_renamed". <br>
                                 # If the device name to be renamed was not found in the database, a WARNUNG will appear in reading "device_not_renamed". <br>
                                 # Appropriate entries will be written to Logfile if verbose >= 3 is set.
                                 <br><br>
								 
								 <b>Note:</b> <br>
                                 Even though the function itself is designed non-blocking, make sure the assigned DbLog-device
                                 is operating in asynchronous mode to avoid FHEMWEB from blocking. <br><br> 
                                 </li> <br>
                                 </ul>     
    
    <li><b> diffValue [display | writeToDB]</b>    
                                 - calculates the difference of database column "VALUE" between period given by 
                                 <a href="#DbRepattr">attributes</a> "timestamp_begin", "timestamp_end" or "timeDiffToNow / timeOlderThan". 
                                 The reading to evaluate must be defined using attribute "reading". 
                                 This function is mostly reasonable if readingvalues are increasing permanently and don't write value-differences to the database. 
                                 The difference will be generated from the first available dataset (VALUE-Field) to the last available dataset between the 
								 specified time linits/aggregation, in which a balanced difference value of the previous aggregation period will be transfered to the
								 following aggregation period in case this period contains a value. <br>
								 An possible counter overrun (restart with value "0") will be considered (compare <a href="#DbRepattr">attribute</a> "diffAccept"). <br><br>
								 
								 If only one dataset will be found within the evalution period, the difference can be calculated only in combination with the balanced
								 difference of the previous aggregation period. In this case a logical inaccuracy according the assignment of the difference to the particular aggregation period
								 can be possible. Hence in warning in "state" will be placed and the reading "less_data_in_period" with a list of periods
								 with only one dataset found in it will be created. 
								 <br><br>
								 
                                 <ul>
                                 <b>Note: </b><br>								 
								 Within the evaluation respectively aggregation period (day, week, month, etc.) you should make available at least one dataset 
                                 at the beginning and one dataset at the end of each aggregation period to take the difference calculation as much as possible.
                                 <br>
                                 <br>
                                 </ul>
                                 
                                 Is no or the option "display" specified, the results are only displayed. Using 
                                 option "writeToDB" the calculation results are stored in the database with a new reading
                                 name. <br>
                                 The new readingname is built of a prefix and the original reading name. 
                                 The prefix is made up of the creation function and the aggregation. <br>
                                 The timestamp of the new stored readings is deviated from aggregation period, 
                                 unless no unique point of time of the result can be determined. 
                                 The field "EVENT" will be filled with "calculated".<br><br>
                                 
                                 <ul>
                                 <b>Example of building a new reading name from the original reading "totalpac":</b> <br>
                                 diff_day_totalpac <br>
                                 # &lt;creation function&gt;_&lt;aggregation&gt;_&lt;original reading&gt; <br>   
                                 </ul>								 
                                 </li><br>
                                 

  <li><b> dumpMySQL [clientSide | serverSide]</b>    
	                             -  creates a dump of the connected MySQL database.  <br>
								 Depending from selected option the dump will be created on Client- or on Server-Side. <br>
								 The variants differs each other concerning the executing system, the creating location, the usage of
                                 attributes, the function result and the needed hardware ressources. <br>
								 The option "clientSide" e.g. needs more powerful FHEM-Server hardware, but saves all available
								 tables inclusive possibly created views. <br>
                                 With attribute "dumpCompress" a compression of dump file after creation can be switched on.
								 <br><br>
								 
								 <ul>
								 <b><u>Option clientSide</u></b> <br>
	                             The dump will be created by client (FHEM-Server) and will be saved in FHEM log-directory by 
								 default.
                                 The target directory can be set by <a href="#DbRepattr">attribute</a> "dumpDirLocal" and has to be
								 writable by the FHEM process. <br>
								 Before executing the dump a table optimization can be processed optionally (see attribute 
								 "optimizeTablesBeforeDump") as well as a FHEM-command (attribute "executeBeforeProc"). 
                                 After the dump a FHEM-command can be executed as well (see attribute "executeAfterProc"). <br><br>
								 
								 <b>Note: <br>
								 To avoid FHEM from blocking, you have to operate DbLog in asynchronous mode if the table
                                 optimization want to be used ! </b> <br><br>
								 
								 By the <a href="#DbRepattr">attributes</a> "dumpMemlimit" and "dumpSpeed" the run-time behavior of the function can be 
								 controlled to optimize the performance and demand of ressources. <br><br>

								 The attributes relevant for function "dumpMySQL clientSide" are: <br><br>
	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> dumpComment              </td><td>: User comment in head of dump file  </td></tr>
                                      <tr><td> dumpCompress             </td><td>: compress of dump files after creation </td></tr>
                                      <tr><td> dumpDirLocal             </td><td>: the local destination directory for dump file creation </td></tr>
                                      <tr><td> dumpMemlimit             </td><td>: limits memory usage </td></tr>
                                      <tr><td> dumpSpeed                </td><td>: limits CPU utilization </td></tr>
	                                  <tr><td> dumpFilesKeep            </td><td>: number of dump files to keep </td></tr>
	                                  <tr><td> executeBeforeProc        </td><td>: execution of FHEM command (or perl-routine) before dump </td></tr>
                                      <tr><td> executeAfterProc         </td><td>: execution of FHEM command (or perl-routine) after dump </td></tr>
	                                  <tr><td> optimizeTablesBeforeDump </td><td>: table optimization before dump </td></tr>
                                   </table>
	                               </ul>
	                               <br> 								 
                                 
								 After a successfull finished dump the old dumpfiles are deleted and only the number of files 
                                 defined by attribute "dumpFilesKeep" (default: 3) remain in the target directory 
                                 "dumpDirLocal". If "dumpFilesKeep = 0" is set, all
                                 dumpfiles (also the current created file), are deleted. This setting can be helpful, if FTP transmission is used
                                 and the created dumps are only keep remain in the FTP destination directory. <br><br>

								 The <b>naming convention of dump files</b> is:  &lt;dbname&gt;_&lt;date&gt;_&lt;time&gt;.sql[.gzip] <br><br>
								 
								 The created dumpfile may imported on the MySQL-Server by e.g.: <br><br>
								 
								   <ul>
								   mysql -u &lt;user&gt; -p &lt;dbname&gt; < &lt;filename&gt;.sql <br><br>
								   </ul>
								 
								 to restore the database from the dump. <br><br><br>
                                 
								 
								 <b><u>Option serverSide</u></b> <br>
								 The dump will be created on the MySQL-Server and will be saved in its Home-directory 
								 by default. <br>
								 The whole history-table (not the current-table) will be exported <b>CSV-formatted</b> without
								 any restrictions. <br>
								 
								 Before executing the dump a table optimization can be processed optionally (see attribute 
								 "optimizeTablesBeforeDump") as well as a FHEM-command (attribute "executeBeforeProc"). <br><br>
								 
								 <b>Note: <br>
								 To avoid FHEM from blocking, you have to operate DbLog in asynchronous mode if the table
                                 optimization want to be used ! </b> <br><br>
								 
								 After the dump a FHEM-command can be executed as well (see attribute "executeAfterProc"). <br><br>
                                 
								 The attributes relevant for function "dumpMySQL serverSide" are: <br><br>
	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> dumpDirRemote            </td><td>: destination directory of dump file on remote server  </td></tr>
                                      <tr><td> dumpCompress             </td><td>: compress of dump files after creation </td></tr>
                                      <tr><td> dumpDirLocal             </td><td>: the local mounted directory dumpDirRemote </td></tr>
	                                  <tr><td> dumpFilesKeep            </td><td>: number of dump files to keep </td></tr>
	                                  <tr><td> executeBeforeProc        </td><td>: execution of FHEM command (or perl-routine) before dump </td></tr>
                                      <tr><td> executeAfterProc         </td><td>: execution of FHEM command (or perl-routine) after dump </td></tr>
	                                  <tr><td> optimizeTablesBeforeDump </td><td>: table optimization before dump </td></tr>
                                   </table>
	                               </ul>
	                               <br> 
								 
                                 The target directory can be set by <a href="#DbRepattr">attribute</a> "dumpDirRemote". 
                                 It must be located on the MySQL-Host and has to be writable by the MySQL-server process. <br>
								 The used database user must have the "FILE"-privilege. <br><br>
								 
								 <b>Note:</b> <br>
								 If the internal version management of DbRep should be used and the size of the created dumpfile be 
								 reported, you have to mount the remote  MySQL-Server directory "dumpDirRemote" on the client 
								 and publish it to the DbRep-device by fill out the <a href="#DbRepattr">attribute</a> 
								 "dumpDirLocal". <br>
								 Same is necessary if ftp transfer after dump is to be used (attribute "ftpUse" respectively "ftpUseSSL").
								 <br><br>

                                 <ul>                                 
                                 <b>Example: </b> <br>
                                 attr &lt;name&gt; dumpDirRemote /volume1/ApplicationBackup/dumps_FHEM/ <br>
								 attr &lt;name&gt; dumpDirLocal /sds1/backup/dumps_FHEM/ <br>
								 attr &lt;name&gt; dumpFilesKeep 2 <br><br>
								 
                                 # The dump will be created remote on the MySQL-Server in directory 
								 '/volume1/ApplicationBackup/dumps_FHEM/'. <br>
								 # The internal version management searches in local mounted directory '/sds1/backup/dumps_FHEM/' 
								 for present dumpfiles and deletes these files except the last two versions. <br>
                                 <br>
                                 </ul>								 
								 
								 If the internal version management is used, after a successfull finished dump old dumpfiles will 
								 be deleted and only the number of attribute "dumpFilesKeep" (default: 3) would remain in target 
								 directory "dumpDirLocal" (the mounted "dumpDirRemote").
								 In that case FHEM needs write permissions to the directory "dumpDirLocal". <br><br>		

								 The <b>naming convention of dump files</b> is:  &lt;dbname&gt;_&lt;date&gt;_&lt;time&gt;.csv[.gzip] <br><br>
								 
								 You can start a restore of table history from serverSide-Backup by command: <br><br>
								   <ul>
								   set &lt;name&gt; &lt;restoreMySQL&gt; &lt;filename&gt;.csv[.gzip] <br><br>
								   </ul>
								
                                 <br><br>

								 <b><u>FTP-Transfer after Dump</u></b> <br>
								 If those possibility is be used, the <a href="#DbRepattr">attribute</a> "ftpUse" or 
								 "ftpUseSSL" has to be set. The latter if encoding for FTP is to be used. 
                                 The module also carries the version control of dump files in FTP-destination by attribute 
                                 "ftpDumpFilesKeep". <br>
								 Further <a href="#DbRepattr">attributes</a> are: <br><br>
								 
	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> ftpUse      </td><td>: FTP Transfer after dump will be switched on (without SSL encoding) </td></tr>
                                      <tr><td> ftpUser     </td><td>: User for FTP-server login, default: anonymous </td></tr>
                                      <tr><td> ftpUseSSL   </td><td>: FTP Transfer with SSL encoding after dump </td></tr>
                                      <tr><td> ftpDebug    </td><td>: debugging of FTP communication for diagnostics </td></tr>
	                                  <tr><td> ftpDir      </td><td>: directory on FTP-server in which the file will be send into (default: "/") </td></tr>
	                                  <tr><td> ftpDumpFilesKeep </td><td>: leave the number of dump files in FTP-destination &lt;ftpDir&gt; (default: 3) </td></tr>
                                      <tr><td> ftpPassive  </td><td>: set if passive FTP is to be used </td></tr>
	                                  <tr><td> ftpPort     </td><td>: FTP-Port, default: 21 </td></tr>
									  <tr><td> ftpPwd      </td><td>: password of FTP-User, not set by default </td></tr>
									  <tr><td> ftpServer   </td><td>: name or IP-address of FTP-server. <b>absolutely essential !</b> </td></tr>
									  <tr><td> ftpTimeout  </td><td>: timeout of FTP-connection in seconds (default: 30). </td></tr>
                                   </table>
	                               </ul>
	                               <br>
	                               <br>
                                 </ul>
								   
								 </li><br>
                                 
    <li><b> dumpSQLite </b>   -  creates a dump of the connected SQLite database.  <br>
	                             This function uses the SQLite Online Backup API and allow to create a consistent backup of the 
                                 database during the normal operation.
	                             The dump will be saved in FHEM log-directory by default.
                                 The target directory can be defined by <a href="#DbRepattr">attribute</a> "dumpDirLocal" and 
                                 has to be writable by the FHEM process. <br>
								 Before executing the dump a table optimization can be processed optionally (see attribute 
								 "optimizeTablesBeforeDump"). 
                                 <br><br>
								 
								 <b>Note: <br>
								 To avoid FHEM from blocking, you have to operate DbLog in asynchronous mode if the table
                                 optimization want to be used ! </b> <br><br>
                                 
                                 Before and after the dump a FHEM-command can be executed (see attribute "executeBeforeProc", 
                                 "executeAfterProc"). <br><br>
                                 
								 The attributes relevant for function "dumpMySQL serverSide" are: <br><br>
	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> dumpCompress             </td><td>: compress of dump files after creation </td></tr>
                                      <tr><td> dumpDirLocal             </td><td>: the local mounted directory dumpDirRemote </td></tr>
	                                  <tr><td> dumpFilesKeep            </td><td>: number of dump files to keep </td></tr>
	                                  <tr><td> executeBeforeProc        </td><td>: execution of FHEM command (or perl-routine) before dump </td></tr>
                                      <tr><td> executeAfterProc         </td><td>: execution of FHEM command (or perl-routine) after dump </td></tr>
	                                  <tr><td> optimizeTablesBeforeDump </td><td>: table optimization before dump </td></tr>
                                   </table>
	                               </ul>
	                               <br> 
                                 
								 After a successfull finished dump the old dumpfiles are deleted and only the number of attribute 
								 "dumpFilesKeep" (default: 3) remain in the target directory "dumpDirLocal". If "dumpFilesKeep = 0" is set, all
                                 dumpfiles (also the current created file), are deleted. This setting can be helpful, if FTP transmission is used
                                 and the created dumps are only keep remain in the FTP destination directory. <br><br>

								 The <b>naming convention of dump files</b> is:  &lt;dbname&gt;_&lt;date&gt;_&lt;time&gt;.sqlitebkp[.gzip] <br><br>
					 
                                 The database can be restored by command "set &lt;name&gt; restoreSQLite &lt;filename&gt;" <br>
                                 The created dump file can be transfered to a FTP-server. Please see explanations about FTP-
                                 transfer in topic "dumpMySQL". <br><br>
								 </li><br>
                                 
    <li><b> eraseReadings </b>   - deletes all created readings in the device, except reading "state" and readings, which are  
                                 contained in exception list defined by attribute "readingPreventFromDel".                                
                                 </li><br>
								 
    <li><b> exportToFile </b> -  exports DB-entries to a file in CSV-format of time period set by time attributes. 
                                 Limitations of selections can be set by <a href="#DbRepattr">attributes</a> Device and/or Reading. 
                                 The filename will be defined by <a href="#DbRepattr">attribute</a> "expimpfile". <br> 
                                 By setting attribute "aggregation" the export of datasets will be splitted into time slices 
                                 recording the specified aggregation. 
                                 Is, for example, "aggregation = month" set, the data are selected in monthly packets and written
                                 into the exportfile. Thereby the usage of main memory is optimized if very large amount of data
                                 is exported and avoid the "died prematurely" error.                                  
                                 </li> <br>
                                 
    <li><b> fetchrows [history|current] </b>    
                              -  provides <b>all</b> table entries (default: history) 
	                             of time period set by time <a href="#DbRepattr">attributes</a> respectively selection conditions
                                 by attributes "device" and "reading". 
                                 An aggregation set will <b>not</b> be considered.  <br>
								 The direction of data selection can be determined by <a href="#DbRepattr">attribute</a> 
								 "fetchRoute". <br><br>
                                 
                                 Every reading of result is composed of the dataset timestring , an index, the device name
                                 and the reading name.
                                 The function has the capability to reconize multiple occuring datasets (doublets).
                                 Such doublets are marked by an index > 1. <br>
                                 Doublets can be highlighted in terms of color by setting attribut e"fetchMarkDuplicates". <br><br>
                                 
                                 <b>Note:</b> <br>
                                 Highlighted readings are not displayed again after restart or rereadcfg because of they are not
                                 saved in statefile. <br><br>
                                 
                                 This attribute is preallocated with some colors, but can be changed by colorpicker-widget: <br><br>
                                 
                                 <ul>
                                 <code>
                                 attr &lt;DbRep-Device&gt; widgetOverride fetchMarkDuplicates:colorpicker
                                 </code>
                                 </ul>                                 
                                 <br>
                                 
                                 The readings of result are composed like the following sceme: <br><br>
                                 
                                 <ul>
                                 <b>Example:</b> <br>
                                 2017-10-22_03-04-43__1__SMA_Energymeter__Bezug_WirkP_Kosten_Diff <br>
                                 # &lt;date&gt;_&lt;time&gt;__&lt;index&gt;__&lt;device&gt;__&lt;reading&gt;
                                 </ul>                                 
                                 <br>

                                 For a better overview the relevant attributes are listed here in a table: <br><br>

	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>fetchRoute</b>            </td><td>: direction of selection read in database </td></tr>
                                      <tr><td> <b>limit</b>                 </td><td>: limits the number of datasets to select and display </td></tr>
                                      <tr><td> <b>fetchMarkDuplicates</b>   </td><td>: Highlighting of found doublets </td></tr>
                                      <tr><td> <b>device</b>                </td><td>: select only datasets which are contain &lt;device&gt; </td></tr>
                                      <tr><td> <b>reading</b>               </td><td>: select only datasets which are contain &lt;reading&gt; </td></tr>
                                      <tr><td> <b>time.*</b>                </td><td>: A number of attributes to limit selection by time </td></tr>
                                   </table>
	                               </ul>
	                               <br>
	                               <br>                                 

								 <b>Note:</b> <br>
                                 Although the module is designed non-blocking, a huge number of selection result (huge number of rows) 
								 can overwhelm the browser session respectively FHEMWEB. 
								 Due to the sample space can be limited by <a href="#DbRepattrlimit">attribute</a> "limit". 
                                 Of course ths attribute can be increased if your system capabilities allow a higher workload. <br><br>
								 </li> <br> 
                                 
    <li><b> insert </b>       -  use it to insert data ito table "history" manually. Input values for Date, Time and Value are mandatory. The database fields for Type and Event will be filled in with "manual" automatically and the values of Device, Reading will be get from set <a href="#DbRepattr">attributes</a>.  <br><br>
                                 
                                 <ul>
                                 <b>input format: </b>   Date,Time,Value,[Unit]    <br>
                                 # Unit is optional, attributes of device, reading must be set ! <br>
                                 # If "Value=0" has to be inserted, use "Value = 0.0" to do it. <br><br>
                                 
                                 <b>example:</b>         2016-08-01,23:00:09,TestValue,TestUnit  <br>
                                 # Spaces are NOT allowed in fieldvalues ! <br>
                                 <br>
								 
								 <b>Note: </b><br>
                                 Please consider to insert AT LEAST two datasets into the intended time / aggregatiom period (day, week, month, etc.) because of
								 it's needed by function diffValue. Otherwise no difference can be calculated and diffValue will be print out "0" for the respective period !
                                 <br>
                                 <br>
								 </li>
                                 </ul>
                                 
    <li><b> importFromFile </b> - imports datasets in CSV format from file into database. The filename will be set by <a href="#DbRepattr">attribute</a> "expimpfile". <br><br>
                                 
                                 <ul>
                                 <b>dataset format: </b>  "TIMESTAMP","DEVICE","TYPE","EVENT","READING","VALUE","UNIT"  <br><br>						 
                                 # The fields "TIMESTAMP","DEVICE","TYPE","EVENT","READING" and "VALUE" have to be set. The field "UNIT" is optional.
                                 The file content will be imported transactional. That means all of the content will be imported or, in case of error, nothing of it. 
                                 If an extensive file will be used, DON'T set verbose = 5 because of a lot of datas would be written to the logfile in this case. 
                                 It could lead to blocking or overload FHEM ! <br><br>
                                 
                                 <b>Example: </b>        "2016-09-25 08:53:56","STP_5000","SMAUTILS","etotal: 11859.573","etotal","11859.573",""  <br>
                                 <br>
                                 </li> <br>
                                 </ul>    
    
    <li><b> maxValue [display | writeToDB]</b>     
                                 - calculates the maximum value of database column "VALUE" between period given by 
                                 <a href="#DbRepattr">attributes</a> "timestamp_begin", "timestamp_end" or "timeDiffToNow / timeOlderThan". 
                                 The reading to evaluate must be defined using attribute "reading". 
                                 The evaluation contains the timestamp of the <b>last</b> appearing of the identified maximum value 
                                 within the given period.  <br>
                                 
                                 Is no or the option "display" specified, the results are only displayed. Using 
                                 option "writeToDB" the calculated results are stored in the database with a new reading
                                 name. <br>
                                 The new readingname is built of a prefix and the original reading name. 
                                 The prefix is made up of the creation function and the aggregation. <br>
                                 The timestamp of the new stored readings is deviated from aggregation period, 
                                 unless no unique point of time of the result can be determined. 
                                 The field "EVENT" will be filled with "calculated".<br><br>
                                 
                                 <ul>
                                 <b>Example of building a new reading name from the original reading "totalpac":</b> <br>
                                 max_day_totalpac <br>
                                 # &lt;creation function&gt;_&lt;aggregation&gt;_&lt;original reading&gt; <br>                         
                                 </ul>
                                 </li><br>
                                 
    <li><b> minValue [display | writeToDB]</b>     
                                 - calculates the minimum value of database column "VALUE" between period given by 
                                 <a href="#DbRepattr">attributes</a> "timestamp_begin", "timestamp_end" or "timeDiffToNow / timeOlderThan". 
                                 The reading to evaluate must be defined using attribute "reading". 
                                 The evaluation contains the timestamp of the <b>first</b> appearing of the identified minimum 
                                 value within the given period.  <br>
                                 
                                 Is no or the option "display" specified, the results are only displayed. Using 
                                 option "writeToDB" the calculated results are stored in the database with a new reading
                                 name. <br>
                                 The new readingname is built of a prefix and the original reading name. 
                                 The prefix is made up of the creation function and the aggregation. <br>
                                 The timestamp of the new stored readings is deviated from aggregation period, 
                                 unless no unique point of time of the result can be determined. 
                                 The field "EVENT" will be filled with "calculated".<br><br>
                                 
                                 <ul>
                                 <b>Example of building a new reading name from the original reading "totalpac":</b> <br>
                                 min_day_totalpac <br>
                                 # &lt;creation function&gt;_&lt;aggregation&gt;_&lt;original reading&gt; <br>                         
                                 </ul>
                                 </li><br>   

	<li><b> optimizeTables </b> - optimize tables in the connected database (MySQL). <br>
							      Before and after an optimization it is possible to execute a FHEM command. 
                                  (please see <a href="#DbRepattr">attributes</a>  "executeBeforeProc", "executeAfterProc") 
                                  <br><br>
                                
								 <ul>
								 <b>Note:</b> <br>
                                 Even though the function itself is designed non-blocking, make sure the assigned DbLog-device
                                 is operating in asynchronous mode to avoid FHEMWEB from blocking. <br><br>           
								 </li><br>
                                 </ul>   
								 
    <li><b> readingRename </b> - renames the reading name of a device inside the connected database (see Internal DATABASE).
                                 The readingname will allways be changed in the <b>entire</b> database. Possibly set time limits or restrictions by 
                                 <a href="#DbRepattr">attributes</a> device and/or reading will not be considered.  <br><br>
                                 
                                 <ul>
                                 <b>Example: </b> <br> 
                                 set &lt;name&gt; readingRename &lt;old reading name&gt;,&lt;new reading name&gt;  <br>               
                                 # The amount of renamed reading names (datasets) will be displayed in reading "reading_renamed". <br>
                                 # If the reading name to be renamed was not found in the database, a WARNUNG will appear in reading "reading_not_renamed". <br>
                                 # Appropriate entries will be written to Logfile if verbose >= 3 is set.
                                 <br><br>
								 
								 <b>Note:</b> <br>
                                 Even though the function itself is designed non-blocking, make sure the assigned DbLog-device
                                 is operating in asynchronous mode to avoid FHEMWEB from blocking. <br><br> 
                                 </li> <br>
                                 </ul>

    <li><b> repairSQLite </b>  - repairs a corrupted SQLite database. <br>
                                 A corruption is usally existent when the error message "database disk image is malformed"
                                 appears in reading "state" of the connected DbLog-device.
                                 If the command was started, the connected DbLog-device will firstly disconnected from the 
                                 database for 10 hours (36000 seconds) automatically (breakup time). After the repair is
                                 finished, the DbLog-device will be connected to the (repaired) database immediately. <br>
								 As an argument the command can be completed by a differing breakup time (in seconds). <br>
                                 The corrupted database is saved as &lt;database&gt;.corrupt in same directory.   <br><br>
                                 
                                 <ul>
                                 <b>Example: </b><br>  
                                 set &lt;name&gt; repairSQLite  <br>               
                                 # the database is trying to repair, breakup time is 10 hours <br>
                                 set &lt;name&gt; repairSQLite 600 <br>   
                                 # the database is trying to repair, breakup time is 10 minutes
                                 <br><br>
								 
								 <b>Note:</b> <br>
                                 It can't be guaranteed, that the repair attempt proceed successfully and no data loss will result. 
                                 Depending from corruption severity data loss may occur or the repair will fail even though
                                 no error appears during the repair process. Please make sure a valid backup took place ! <br><br> 
                                 </li> <br>
                                 </ul> 	                                 
								 
    <li><b> restoreMySQL &lt;file&gt;.csv[.gzip] </b>  - imports the content of table history from a serverSide-backup. <br>
                                 The function provides a drop-down-list of files which can be used for restore.
                                 Therefore you have to mount the remote directory "dumpDirRemote" of the MySQL-Server on the 
								 Client and make it usable to the DbRep-device by setting the <a href="#DbRepattr">attribute</a> 
								 "dumpDirLocal". <br>
								 All files with extension "csv[.gzip]" and if the filename is beginning with the name of the connected database 
								 (see Internal DATABASE) are listed. <br><br>
								 </li><br>
                                 
    <li><b> restoreSQLite &lt;File&gt;.sqlitebkp[.gzip] </b>  - restores a backup of SQLite database. <br>
                                 The function provides a drop-down-list of files which can be used for restore.
                                 The data stored in the current database are deleted respectively overwritten. 
                                 All files with extension "sqlitebkp[.gzip]" and if the filename is beginning with the name of the connected database 
								 will are listed. <br><br>
								 </li><br>

	<li><b> sqlCmd </b>        - executes an arbitrary user specific command. <br>
                                 If the command contains a operation to delete data, the <a href="#DbRepattr">attribute</a> 
								 "allowDeletion" has to be set for security reason. <br>
                                 The statement doesn't consider limitations by attributes "device", "reading", "time.*" 
                                 respectively "aggregation". <br>
								 If the <a href="#DbRepattr">attribute</a> "timestamp_begin" respectively "timestamp_end" 
								 is assumed in the statement, it is possible to use placeholder "<b>§timestamp_begin§</b>" respectively
								 "<b>§timestamp_end§</b>" on suitable place. <br><br>
								 
								 If you want update a dataset, you have to add "TIMESTAMP=TIMESTAMP" to the update-statement to avoid changing the 
								 original timestamp. <br><br>
								 
	                             <ul>
                                 <b>Examples of SQL-statements: </b> <br><br> 
								 <ul>
                                 <li>set &lt;name&gt; sqlCmd select DEVICE, count(*) from history where TIMESTAMP >= "2017-01-06 00:00:00" group by DEVICE having count(*) > 800 </li>
                                 <li>set &lt;name&gt; sqlCmd select DEVICE, count(*) from history where TIMESTAMP >= "2017-05-06 00:00:00" group by DEVICE </li>
								 <li>set &lt;name&gt; sqlCmd select DEVICE, count(*) from history where TIMESTAMP >= §timestamp_begin§ group by DEVICE </li>
                                 <li>set &lt;name&gt; sqlCmd select * from history where DEVICE like "Te%t" order by `TIMESTAMP` desc </li>
                                 <li>set &lt;name&gt; sqlCmd select * from history where `TIMESTAMP` > "2017-05-09 18:03:00" order by `TIMESTAMP` desc </li>
                                 <li>set &lt;name&gt; sqlCmd select * from current order by `TIMESTAMP` desc  </li>
                                 <li>set &lt;name&gt; sqlCmd select sum(VALUE) as 'Einspeisung am 04.05.2017', count(*) as 'Anzahl' FROM history where `READING` = "Einspeisung_WirkP_Zaehler_Diff" and TIMESTAMP between '2017-05-04' AND '2017-05-05' </li>
                                 <li>set &lt;name&gt; sqlCmd delete from current  </li>
                                 <li>set &lt;name&gt; sqlCmd delete from history where TIMESTAMP < "2016-05-06 00:00:00" </li>
                                 <li>set &lt;name&gt; sqlCmd update history set TIMESTAMP=TIMESTAMP,VALUE='Val' WHERE VALUE='TestValue' </li>
                                 <li>set &lt;name&gt; sqlCmd select * from history where DEVICE = "Test" </li>
                                 <li>set &lt;name&gt; sqlCmd insert into history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES ('2017-05-09 17:00:14','Test','manuell','manuell','Tes§e','TestValue','°C') </li>    
                                 </ul>
								 <br>
								 
								 The result of the statement will be shown in <a href="#DbRepReadings">Reading</a> "SqlResult".
							     The formatting of result can be choosen by <a href="#DbRepattr">attribute</a> "sqlResultFormat", as well as the used
								 field separator can be determined by <a href="#DbRepattr">attribute</a> "sqlResultFieldSep". <br><br>
							
                                 The module provides a command history once a sqlCmd command was executed successfully.
                                 To use this option, activate the attribute "sqlCmdHistoryLength" with list lenght you want. <br><br>
                                 
                                 For a better overview the relevant attributes for sqlCmd are listed in a table: <br><br>

	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>allowDeletion</b>       </td><td>: activates capabilty to delete datasets </td></tr>
                                      <tr><td> <b>sqlResultFormat</b>     </td><td>: determines presentation style of command result </td></tr>
                                      <tr><td> <b>sqlResultFieldSep</b>   </td><td>: choice of a useful field separator for result </td></tr>
                                      <tr><td> <b>sqlCmdHistoryLength</b> </td><td>: activates command history and length </td></tr>
                                   </table>
	                               </ul>
	                               <br>
	                               <br>  

								 <b>Note:</b> <br>
                                 Even though the module works non-blocking regarding to database operations, a huge 
								 sample space (number of rows/readings) could block the browser session respectively 
								 FHEMWEB.								 
								 If you are unsure about the result of the statement, you should preventively add a limit to 
								 the statement. <br><br>
								 </li><br>
                                 </ul>  

    <li><b> sqlCmdHistory </b>   - If history is activated by <a href="#DbRepattr">attribute</a> "sqlCmdHistoryLength", an already
                                   successfully executed sqlCmd-command can be repeated from a drop-down list. <br>
                                   By execution of the last list entry, "__purge_historylist__", the list itself can be deleted. <br>
								   If the statement contains "," this character is displayed as "&lt;c&gt;" in the history 
                                   list due to technical restrictions. <br>
                                   </li><br>								 

	<li><b> sumValue [display | writeToDB]</b>     
                                 - calculates the summary of database column "VALUE" between period given by 
	                             <a href="#DbRepattr">attributes</a> "timestamp_begin", "timestamp_end" or 
								 "timeDiffToNow / timeOlderThan". The reading to evaluate must be defined using attribute
								 "reading". Using this function is mostly reasonable if value-differences of readings 
								 are written to the database. <br>

                                 Is no or the option "display" specified, the results are only displayed. Using 
                                 option "writeToDB" the calculation results are stored in the database with a new reading
                                 name. <br>
                                 The new readingname is built of a prefix and the original reading name. 
                                 The prefix is made up of the creation function and the aggregation. <br>
                                 The timestamp of the new stored readings is deviated from aggregation period, 
                                 unless no unique point of time of the result can be determined. 
                                 The field "EVENT" will be filled with "calculated".<br><br>
                                 
                                 <ul>
                                 <b>Example of building a new reading name from the original reading "totalpac":</b> <br>
                                 sum_day_totalpac <br>
                                 # &lt;creation function&gt;_&lt;aggregation&gt;_&lt;original reading&gt; <br>                         
                                 </li> <br>
                                 </ul>
                                 <br>
                                 
    <li><b> syncStandby &lt;DbLog-Device Standby&gt; </b>    
                                 -  datasets of the connected database (source) are transmitted into another database 
                                 (Standby-database). <br>
                                 Here the "&lt;DbLog-Device Standby&gt;" is the DbLog-Device what is connected to the 
                                 Standby-database. <br><br>
                                 All the datasets which are determined by timestamp-<a href="#DbRepattrlimit">attributes</a>
                                 or respectively the attributes "device", "reading" are transmitted. <br>
                                 The datasets are transmitted in time slices accordingly to the adjusted aggregation.
                                 If the attribute "aggregation" has value "no" or "month", the datasets are transmitted 
                                 automatically in daily time slices into standby-database. 
                                 Source- and Standby-database can be of different types.
								 <br><br>

                                 The relevant attributes to control the syncStandby function are: <br><br>

	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>aggregation</b>  </td><td>: adjustment of time slices for data transmission (hour,day,week) </td></tr>
                                      <tr><td> <b>device</b>       </td><td>: transmit only datasets which are contain &lt;device&gt; </td></tr>
                                      <tr><td> <b>reading</b>      </td><td>: transmit only datasets which are contain &lt;reading&gt; </td></tr>
                                      <tr><td> <b>time.*</b>       </td><td>: A number of attributes to limit selection by time  </td></tr>
                                   </table>
	                               </ul>
	                               <br>
	                               <br>                                 
								 </li> <br>
		
	<li><b> tableCurrentFillup </b> - the current-table will be filled u with an extract of the history-table.  
	                                  The <a href="#DbRepattr">attributes</a> for limiting time and device, reading are considered.
                                      Thereby the content of the extract can be affected. In the associated DbLog-device the attribute "DbLogType" should be set to 
                                      "SampleFill/History". </li> <br> 		
								 
	<li><b> tableCurrentPurge </b> - deletes the content of current-table. There are no limits, e.g. by attributes "timestamp_begin", "timestamp_end", device, reading 
                                     and so on, considered.	</li> <br> 

	<li><b> vacuum </b>       - optimize tables in the connected database (SQLite, PostgreSQL). <br>
							    Before and after an optimization it is possible to execute a FHEM command. 
                                (please see <a href="#DbRepattr">attributes</a>  "executeBeforeProc", "executeAfterProc") 
                                <br><br>
                                
								<ul>
								<b>Note:</b> <br>
                                Even though the function itself is designed non-blocking, make sure the assigned DbLog-device
                                is operating in asynchronous mode to avoid FHEM from blocking. <br><br>           
								</li>
                                </ul><br>							 
               
  <br>
  </ul></ul>
  
  <b>For all evaluation variants (except sqlCmd,deviceRename,readingRename) applies: </b> <br>
  In addition to the needed reading the device can be complemented to restrict the datasets for reporting / function. 
  If no time limit attribute is set but aggregation is set, the period from the oldest dataset in database to the current 
  date/time will be used as selection criterion. If the oldest dataset wasn't identified, then '1970-01-01 01:00:00' is used
  as start date (see get &lt;name&gt; "minTimestamp" also).
  If both time limit attribute and aggregation isn't set, the selection on database is runnung without timestamp criterion.
  <br><br>
  
  <b>Note: </b> <br>
  
  If you are in detail view it could be necessary to refresh the browser to see the result of operation as soon in DeviceOverview section "state = done" will be shown.
  
  <br><br>

</ul>  

<a name="DbRepget"></a>
<b>Get </b>
<ul>

 The get-commands of DbRep provide to retrieve some metadata of the used database instance. 
 Those are for example adjusted server parameter, server variables, datadasestatus- and table informations. THe available get-functions depending of 
 the used database type. So for SQLite curently only "get svrinfo" is usable. The functions nativ are delivering a lot of outpit values. 
 They can be limited by function specific <a href="#DbRepattr">attributes</a>. The filter has to be setup by a comma separated list. 
 SQL-Wildcard (%) can be used to setup the list arguments. 
 <br><br>
 
 <b>Note: </b> <br>
 After executing a get-funktion in detail view please make a browser refresh to see the results ! 
 <br><br>
 
 <ul><ul>
    <li><b> blockinginfo </b> - list the current system wide running background processes (BlockingCalls) together with their informations. 
	                            If character string is too long (e.g. arguments) it is reported shortened.
                                </li>     
                                <br><br>
								
    <li><b> dbstatus </b> -  lists global informations about MySQL server status (e.g. informations related to cache, threads, bufferpools, etc. ). 
                             Initially all available informations are reported. Using the <a href="#DbRepattr">attribute</a> "showStatus" the quantity of
                             results can be limited to show only the desired values. Further detailed informations of items meaning are 
                             explained <a href=http://dev.mysql.com/doc/refman/5.7/en/server-status-variables.html>there</a>.  <br>
                             
                                 <br><ul>
                                 <b>Example</b>  <br>
                                 get &lt;name&gt; dbstatus  <br>
                                 attr &lt;name&gt; showStatus %uptime%,%qcache%    <br>               
                                 # Only readings containing "uptime" and "qcache" in name will be created
                                 </li> 
                                 <br><br>
                                 </ul>                               
                                 
    <li><b> dbvars </b> -  lists global informations about MySQL system variables. Included are e.g. readings related to InnoDB-Home, datafile path, 
                           memory- or cache-parameter and so on. The Output reports initially all available informations. Using the 
                           <a href="#DbRepattr">attribute</a> "showVariables" the quantity of results can be limited to show only the desired values. 
                           Further detailed informations of items meaning are explained 
                           <a href=http://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html>there</a>. <br>
                           
                                 <br><ul>
                                 <b>Example</b>  <br>
                                 get &lt;name&gt; dbvars  <br>
                                 attr &lt;name&gt; showVariables %version%,%query_cache%    <br>               
                                 # Only readings containing "version" and "query_cache" in name will be created
                                 </li> 
                                 <br><br>
                                 </ul>  

    <li><b> minTimestamp </b> - Identifies the oldest timestamp in the database (will be executed implicitely at FHEM start).
                                The timestamp is used as begin of data selection if no time attribut is set to determine the
                                start date.                                
                                </li>     
                                <br><br>                                     

    <li><b> procinfo </b> - reports the existing database processes in a summary table (only MySQL). <br>
	                        Typically only the own processes of the connection user (set in DbLog configuration file) will be
							reported. If all precesses have to be reported, the global "PROCESS" right has to be granted to the 
							user. <br>
							As of MariaDB 5.3 for particular SQL-Statements a progress reporting will be provided 
							(table row "PROGRESS"). So you can track, for instance, the degree of processing during an index
							creation. <br>
							Further informations can be found
                            <a href=https://mariadb.com/kb/en/mariadb/show-processlist/>there</a>. <br>
                            </li>     
                            <br><br>								 

    <li><b> svrinfo </b> -  common database server informations, e.g. DBMS-version, server address and port and so on. The quantity of elements to get depends
                            on the database type. Using the <a href="#DbRepattr">attribute</a> "showSvrInfo" the quantity of results can be limited to show only 
                            the desired values. Further detailed informations of items meaning are explained                             
                            <a href=https://msdn.microsoft.com/en-us/library/ms711681(v=vs.85).aspx>there</a>. <br>
                                 
                                 <br><ul>
                                 <b>Example</b>  <br>
                                 get &lt;name&gt; svrinfo  <br>
                                 attr &lt;name&gt; showSvrInfo %SQL_CATALOG_TERM%,%NAME%   <br>               
                                 # Only readings containing "SQL_CATALOG_TERM" and "NAME" in name will be created
                                 </li> 
                                 <br><br>
                                 </ul>                                                      
                                 
    <li><b> tableinfo </b> -  access detailed informations about tables in MySQL database which is connected by the DbRep-device. 
	                          All available tables in the connected database will be selected by default. 
                              Using the<a href="#DbRepattr">attribute</a> "showTableInfo" the results can be limited to tables you want to show. 
							  Further detailed informations of items meaning are explained <a href=http://dev.mysql.com/doc/refman/5.7/en/show-table-status.html>there</a>.  <br>
                                 
                                 <br><ul>
                                 <b>Example</b>  <br>
                                 get &lt;name&gt; tableinfo  <br>
                                 attr &lt;name&gt; showTableInfo current,history   <br>               
                                 # Only informations related to tables "current" and "history" are going to be created
                                 </li> 
                                 <br><br>
                                 </ul>                                                                                   
  <br>
  </ul></ul>
  
</ul>  


<a name="DbRepattr"></a>
<b>Attributes</b>

<br>
<ul>
  Using the module specific attributes you are able to define the scope of evaluation and the aggregation. <br><br>
  
  <b>Note for SQL-Wildcard Usage:</b> <br>
  Within the attribute values of "device" and "reading" you may use SQL-Wildcard "%", Character "_" is not supported as a wildcard. 
  The character "%" stands for any characters.  <br>
  This rule is valid to all functions <b>except</b> "insert", "importFromFile" and "deviceRename". <br>
  The function "insert" doesn't allow setting the mentioned attributes containing the wildcard "%". <br> 
  In readings the wildcard character "%" will be replaced by "/" to meet the rules of allowed characters in readings.
  <br><br>
  
  <ul><ul>
  <li><b>aggregation </b>     - Aggregation of Device/Reading-selections. Possible is hour, day, week, month or "no". 
                                Delivers e.g. the count of database entries for a day (countEntries), Summation of 
								difference values of a reading (sumValue) and so on. Using aggregation "no" (default) an 
								aggregation don't happens but the output contaims all values of Device/Reading in the defined time period.  </li> <br>

  <li><b>allowDeletion </b>   - unlocks the delete-function  </li> <br>
  
  <li><b>averageCalcForm </b> - specifies the calculation variant of average peak by "averageValue".                                 
                                </li><br>

  <li><b>device </b>          - Selection of a particular device. <br>
                                You can specify <a href="https://fhem.de/commandref.html#devspec">device specifications (devspec)</a>. <br> 
								Inside of device specifications a SQL wildcard (%) will be evaluated as a normal ASCII-character. 
								The device names are derived from device specification and the active devices in FHEM before 
                                SQL selection will be carried out. </li> <br>
  
                                <ul>
							    <b>Examples:</b> <br>
								<code>attr &lt;name&gt; device TYPE=DbRep</code> <br>
								# select datasets of active present devices with Type "DbRep" <br> 
								<code>attr &lt;name&gt; device MySTP_5000</code> <br>
								# select datasets of device "MySTP_5000" <br> 
								<code>attr &lt;name&gt; device SMA.*</code> <br>
								# select datasets of devices starting with "SMA" <br> 
								<code>attr &lt;name&gt; device SMA_Energymeter,MySTP_5000</code> <br>
								# select datasets of devices "SMA_Energymeter" and "MySTP_5000" <br>
								<code>attr &lt;name&gt; device %5000</code> <br>
								# select datasets of devices ending with "5000" <br>  								
								</ul>
								<br><br>

  <li><b>diffAccept </b>      - valid for function diffValue. diffAccept determines the threshold,  up to that a calaculated difference between two 
                                straight sequently datasets should be commenly accepted (default = 20). <br>
                                Hence faulty DB entries with a disproportional high difference value will be eliminated and don't tamper the result.
                                If a threshold overrun happens, the reading "diff_overrun_limit_&lt;diffLimit&gt;" will be generated 
								(&lt;diffLimit&gt; will be substituted with the present prest attribute value). <br>
								The reading contains a list of relevant pair of values. Using verbose=3 this list will also be reported in the FHEM
                                logfile. 								
								</li><br> 

                                <ul>
							    Example report in logfile if threshold of diffAccept=10 overruns: <br><br>
							  
                                DbRep Rep.STP5000.etotal -> data ignored while calc diffValue due to threshold overrun (diffAccept = 10): <br>
							    2016-04-09 08:50:50 0.0340 -> 2016-04-09 12:42:01 13.3440 <br><br>
							  
                                # The first dataset with a value of 0.0340 is untypical low compared to the next value of 13.3440 and results a untypical
							      high difference value. <br>
							    # Now you have to decide if the (second) dataset should be deleted, ignored of the attribute diffAccept should be adjusted. 
                                </ul><br> 

								 
  <li><b>disable </b>         - deactivates the module  </li> <br>
  
  <li><b>dumpComment </b>     - User-comment. It will be included in the header of the created dumpfile by 
                                command "dumpMySQL clientSide".   </li> <br>
                                
  <li><b>dumpCompress </b>    - if set, the dump files are compressed after operation of "dumpMySQL" bzw. "dumpSQLite" </li> <br>
  
  <li><b>dumpDirLocal </b>    - Target directory of database dumps by command "dumpMySQL clientSide"
                                (default: "{global}{modpath}/log/" on the FHEM-Server). <br>
								In this directory also the internal version administration searches for old backup-files 
								and deletes them if the number exceeds attribute "dumpFilesKeep". 
								The attribute is also relevant to publish a local mounted directory "dumpDirRemote" to
								DbRep. </li> <br>
								
  <li><b>dumpDirRemote </b>   - Target directory of database dumps by command "dumpMySQL serverSide" 
                                (default: the Home-directory of MySQL-Server on the MySQL-Host). </li> <br>
  
  <li><b>dumpMemlimit </b>    - tolerable memory consumption for the SQL-script during generation period (default: 100000 characters). 
                                Please adjust this parameter if you may notice memory bottlenecks and performance problems based 
								on it on your specific hardware. </li> <br>
  
  <li><b>dumpSpeed </b>       - Number of Lines which will be selected in source database with one select by dump-command 
                                "dumpMySQL ClientSide" (default: 10000). 
                                This parameter impacts the run-time and consumption of resources directly.  </li> <br>

  <li><b>dumpFilesKeep </b>   - The specified number of dumpfiles remain in the dump directory (default: 3). 
                                If there more (older) files has been found, these files will be deleted after a new database dump 
								was created successfully. 
								The global attrubute "archivesort" will be considered. </li> <br> 
  
  <li><b>executeAfterProc </b> - you can specify a FHEM-command which should be executed <b>after dump</b>. <br>
                                 Perl functions have to be enclosed in {} .<br><br>

                                <ul>
							    <b>Example:</b> <br><br>
								attr &lt;name&gt; executeAfterProc set og_gz_westfenster off; <br>
								attr &lt;name&gt; executeAfterProc {adump ("&lt;name&gt;")} <br><br>
								
								# "adump" is a function defined in 99_myUtils.pm e.g.: <br>
								
<pre>
sub adump {
    my ($name) = @_;
    my $hash = $defs{$name};
    # own function, e.g.
    Log3($name, 3, "DbRep $name -> Dump finished");
 
    return;
}
</pre>
</ul>
</li>
  
  <li><b>executeBeforeProc </b> - you can specify a FHEM-command which should be executed <b>before dump</b>. <br>
                                  Perl functions have to be enclosed in {} .<br><br>

                                <ul>
							    <b>Example:</b> <br><br>
								attr &lt;name&gt; executeBeforeProc set og_gz_westfenster on; <br>
								attr &lt;name&gt; executeBeforeProc {bdump ("&lt;name&gt;")} <br><br>
								
								# "bdump" is a function defined in 99_myUtils.pm e.g.: <br>
								
<pre>
sub bdump {
    my ($name) = @_;
    my $hash = $defs{$name};
    # own function, e.g.
    Log3($name, 3, "DbRep $name -> Dump starts now");
 
    return;
}
</pre>
</ul>
</li>

  <li><b>expimpfile </b>      - Path/filename for data export/import </li> <br>
  
  <li><b>fetchMarkDuplicates </b> 
                              - Highlighting of multiple occuring datasets in result of "fetchrows" command </li> <br>
  
  <li><b>fetchRoute [descent | ascent] </b>  - specify the direction of data selection of the fetchrows-command. <br><br>
                                                          <ul>
                                                          <b>descent</b> - the data are read descent (default). If 
                                                                               amount of datasets specified by attribut "limit" is exceeded,
                                                                               the newest x datasets are shown. <br><br>
                                                          <b>ascent</b> - the data are read ascent .  If
                                                                               amount of datasets specified by attribut "limit" is exceeded,
                                                                               the oldest x datasets are shown. <br>
														  </ul>
														  
														</li> <br><br>
  
  <li><b>ftpUse </b>          - FTP Transfer after dump will be switched on (without SSL encoding). The created 
                                database backup file will be transfered non-blocking to the FTP-Server (Attribut "ftpServer"). 
							    </li> <br>
								
  <li><b>ftpUseSSL </b>       - FTP Transfer with SSL encoding after dump. The created database backup file will be transfered 
                                non-blocking to the FTP-Server (Attribut "ftpServer"). </li> <br>
								
  <li><b>ftpUser </b>         - User for FTP-server login, default: "anonymous". </li> <br>
  
  <li><b>ftpDebug </b>        - debugging of FTP communication for diagnostics. </li> <br>
  
  <li><b>ftpDir </b>          - directory on FTP-server in which the file will be send into (default: "/"). </li> <br>
  
  <li><b>ftpDumpFilesKeep </b> - leave the number of dump files in FTP-destination &lt;ftpDir&gt; (default: 3). Are there more 
                                (older) dump files present, these files are deleted after a new dump was transfered successfully. </li> <br>   
  
  <li><b>ftpPassive </b>      - set if passive FTP is to be used </li> <br>
  
  <li><b>ftpPort </b>         - FTP-Port, default: 21 </li> <br>
  
  <li><b>ftpPwd </b>          - password of FTP-User, is not set by default </li> <br>
  
  <li><b>ftpServer </b>       - name or IP-address of FTP-server. <b>absolutely essential !</b> </li> <br>
  
  <li><b>ftpTimeout </b>      - timeout of FTP-connection in seconds (default: 30). </li> <br>
  
  <a name="DbRepattrlimit"></a>
  <li><b>limit </b>           - limits the number of selected datasets by the "fetchrows", or the shown datasets of "delSeqDoublets adviceDelete", 
                                "delSeqDoublets adviceRemain" commands (default: 1000). 
                                This limitation should prevent the browser session from overload and 
								avoids FHEMWEB from blocking. Please change the attribut according your requirements or change the 
								selection criteria (decrease evaluation period). </li> <br>
  
  <li><b>optimizeTablesBeforeDump </b>  - if set to "1", the database tables will be optimized before executing the dump
                                          (default: 0).  
                                          Thereby the backup run-time time will be extended. <br><br>
                                          <ul>
                                          <b>Note</b> <br>
                                          The table optimizing cause locking the tables and therefore to blocking of
										  FHEM if DbLog isn't working in asynchronous mode (DbLog-attribute "asyncMode") !
                                          <br>
										  </ul>
                                          </li> <br> 

  <li><b>reading </b>         - Selection of a particular reading.
                                More than one reading are specified as a comma separated list. <br>
								If SQL wildcard (%) is set in a list, it will be evaluated as a normal ASCII-character. <br>
                                </li> <br>  
								
                                <ul>
							    <b>Examples:</b> <br>
								<code>attr &lt;name&gt; reading etotal</code> <br> 
								<code>attr &lt;name&gt; reading et%</code> <br>
								<code>attr &lt;name&gt; reading etotal,etoday</code> <br>
								</ul>
								<br><br>

  <li><b>readingNameMap </b>  - the name of the analyzed reading can be overwritten for output  </li> <br>

  <li><b>role </b>            - the role of the DbRep-device. Standard role is "Client". The role "Agent" is described 
                                in section <a href="#DbRepAutoRename">DbRep-Agent</a>. </li> <br>    

  <li><b>readingPreventFromDel </b>  - comma separated list of readings which are should prevent from deletion when a 
                                       new operation starts  </li> <br>
                                       
  <li><b>seqDoubletsVariance </b> - accepted variance (+/-) for the command "set &lt;name&gt; delSeqDoublets". <br>
                                    The value of this attribute describes the variance up to it consecutive numeric values (VALUE) of
                                    datasets are handled as identical and should be deleted. "seqDoubletsVariance" is an absolut numerical value, 
                                    which is used as a positive as well as a negative variance. </li> <br>

                                    <ul>
							        <b>Examples:</b> <br>
								    <code>attr &lt;name&gt; seqDoubletsVariance 0.0014 </code> <br>
								    <code>attr &lt;name&gt; seqDoubletsVariance 1.45   </code> <br>
								    </ul>
								    <br><br> 

  <li><b>showproctime </b>    - if set, the reading "sql_processing_time" shows the required execution time (in seconds) 
                                for the sql-requests. This is not calculated for a single sql-statement, but the summary 
								of all sql-statements necessara for within an executed DbRep-function in background. </li> <br>

  <li><b>showStatus </b>      - limits the sample space of command "get &lt;name&gt; dbstatus". SQL-Wildcard (%) can be used.    </li> <br>

                                <ul>
                                <b>Example: </b><br>
                                attr &lt;name&gt; showStatus %uptime%,%qcache%  <br>
                                # Only readings with containing "uptime" and "qcache" in name will be shown <br>
                                </ul><br>  
  
  <li><b>showVariables </b>   - limits the sample space of command "get &lt;name&gt; dbvars". SQL-Wildcard (%) can be used. </li> <br>

                                <ul>
                                <b>Example: </b><br>
                                attr &lt;name&gt; showVariables %version%,%query_cache% <br>
                                # Only readings with containing "version" and "query_cache" in name will be shown <br>
                                </ul><br>  
                              
  <li><b>showSvrInfo </b>     - limits the sample space of command "get &lt;name&gt; svrinfo". SQL-Wildcard (%) can be used.    </li> <br>

                                <ul>
                                <b>Example: </b><br>
                                attr &lt;name&gt; showSvrInfo %SQL_CATALOG_TERM%,%NAME%  <br>
                                # Only readings with containing "SQL_CATALOG_TERM" and "NAME" in name will be shown <br>
                                </ul><br>  
                              
  <li><b>showTableInfo </b>   - limits the tablename which is selected by command "get &lt;name&gt; tableinfo". SQL-Wildcard 
                                (%) can be used.   </li> <br>

                                <ul>
                                <b>Example: </b><br>
                                attr &lt;name&gt; showTableInfo current,history  <br>
                                # Only informations about tables "current" and "history" will be shown <br>
                                </ul><br>  
								
  <li><b>sqlCmdHistoryLength </b> 
                              - activates the command history of "sqlCmd" and determines the length of it  </li> <br>

  
  <li><b>sqlResultFieldSep </b> - determines the used field separator (default: "|") in the result of command "set &lt;name&gt; sqlCmd".  </li> <br>

  <li><b>sqlResultFormat </b> - determines the formatting of the "set &lt;name&gt; sqlCmd" command result. 
                                Possible options are: <br><br>
                                <ul>
                                <b>separated </b> - every line of the result will be generated sequentially in a single 
								                    reading. (default) <br><br>
                                <b>mline </b>     - the result will be generated as multiline in 
								                    <a href="#DbRepReadings">Reading</a> SqlResult. 
													<br><br>	
                                <b>sline </b>     - the result will be generated as singleline in 
								                    <a href="#DbRepReadings">Reading</a> SqlResult. 
													Datasets are separated by "]|[". <br><br>
                                <b>table </b>     - the result will be generated as an table in 
								                    <a href="#DbRepReadings">Reading</a> SqlResult. <br><br>
                                <b>json </b>      - creates <a href="#DbRepReadings">Reading</a> SqlResult as a JSON 
								                    coded hash. 
								                    Every hash-element consists of the serial number of the dataset (key)
													and its value. </li> <br><br> 
													 
   
        To process the result, you may use a userExitFn in 99_myUtils for example: <br>		
		<pre>
        sub resfromjson {
          my ($name,$reading,$value) = @_;
          my $hash   = $defs{$name};

          if ($reading eq "SqlResult") {
            # only reading SqlResult contains JSON encoded data
            my $data = decode_json($value);
	      
		    foreach my $k (keys(%$data)) {
		      
			  # use your own processing from here for every hash-element 
		      # e.g. output of every element that contains "Cam"
		      my $ke = $data->{$k};
		      if($ke =~ m/Cam/i) {
		        my ($res1,$res2) = split("\\|", $ke);
                Log3($name, 1, "$name - extract element $k by userExitFn: ".$res1." ".$res2);
		      }
	        }
          }
        return;
        }
  	    </pre> 
        </ul>
		<br>  
        
                                
  <li><b>timeYearPeriod </b> - By this attribute an annual time period will be determined for database data selection. 
                               The time limits are calculated dynamically during execution time. Every time an annual period is determined. 
                               Periods of less than a year are not possible to set. <br>
                               This attribute is particularly intended to make reports synchronous to an account period, e.g. of an energy- or gas provider.
                               </li> <br> 
                               
                               <ul>
							   <b>Example:</b> <br><br>
							   attr &lt;name&gt; timeYearPeriod 06-25 06-24 <br><br>
								
							   # evaluates the database within the time limits 25. june AAAA and 24. june BBBB. <br>
                               # The year AAAA respectively year BBBB is calculated dynamically depending of the current date. <br>
                               # If the current date >= 25. june and =< 31. december, than AAAA = current year and BBBB = current year+1 <br>
                               # If the current date >= 01. january und =< 24. june, than AAAA = current year-1 and BBBB = current year
							   </ul>
							   <br><br>
                              
  <li><b>timestamp_begin </b> - begin of data selection (*)  </li> <br>
  
  <li><b>timestamp_end </b>   - end of data selection. If not set the current date/time combination will be used. (*) </li> <br>
  
  (*) The format of timestamp is as used with DbLog "YYYY-MM-DD HH:MM:SS". For the attributes "timestamp_begin", "timestamp_end" 
  you can also use one of the following entries. The timestamp-attribute will be dynamically set to: <br><br>
                              <ul>
                              <b>current_year_begin</b>     : matches "&lt;current year&gt;-01-01 00:00:00"         <br>
                              <b>current_year_end</b>       : matches "&lt;current year&gt;-12-31 23:59:59"         <br>
                              <b>previous_year_begin</b>    : matches "&lt;previous year&gt;-01-01 00:00:00"        <br>
                              <b>previous_year_end</b>      : matches "&lt;previous year&gt;-12-31 23:59:59"        <br>
                              <b>current_month_begin</b>    : matches "&lt;current month first day&gt; 00:00:00"    <br>
                              <b>current_month_end</b>      : matches "&lt;current month last day&gt; 23:59:59"     <br>
                              <b>previous_month_begin</b>   : matches "&lt;previous month first day&gt; 00:00:00"   <br>
                              <b>previous_month_end</b>     : matches "&lt;previous month last day&gt; 23:59:59"    <br>
                              <b>current_week_begin</b>     : matches "&lt;first day of current week&gt; 00:00:00"  <br>
                              <b>current_week_end</b>       : matches "&lt;last day of current week&gt; 23:59:59"   <br>
                              <b>previous_week_begin</b>    : matches "&lt;first day of previous week&gt; 00:00:00" <br>
                              <b>previous_week_end</b>      : matches "&lt;last day of previous week&gt; 23:59:59"  <br>
                              <b>current_day_begin</b>      : matches "&lt;current day&gt; 00:00:00"                <br>
                              <b>current_day_end</b>        : matches "&lt;current day&gt; 23:59:59"                <br>
                              <b>previous_day_begin</b>     : matches "&lt;previous day&gt; 00:00:00"               <br>
                              <b>previous_day_end</b>       : matches "&lt;previous day&gt; 23:59:59"               <br>
                              <b>current_hour_begin</b>     : matches "&lt;current hour&gt;:00:00"                  <br>
                              <b>current_hour_end</b>       : matches "&lt;current hour&gt;:59:59"                  <br>
                              <b>previous_hour_begin</b>    : matches "&lt;previous hour&gt;:00:00"                 <br>
                              <b>previous_hour_end</b>      : matches "&lt;previous hour&gt;:59:59"                 <br>                              </ul><br>
  
  Make sure that "timestamp_begin" < "timestamp_end" is fulfilled. <br><br>
  
                                <ul>
							    <b>Example:</b> <br><br>
								attr &lt;name&gt; timestamp_begin current_year_begin <br>
								attr &lt;name&gt; timestamp_end  current_year_end <br><br>
								
								# Analyzes the database between the time limits of the current year. <br>
								</ul>
								<br><br>
  
  <b>Note </b> <br>
  
  If the attribute "timeDiffToNow" will be set, the attributes "timestamp_begin" respectively "timestamp_end" will be deleted if they were set before.
  The setting of "timestamp_begin" respectively "timestamp_end" causes the deletion of attribute "timeDiffToNow" if it was set before as well.
  <br><br>
  
  <li><b>timeDiffToNow </b>   - the <b>begin</b> of data selection will be set to the timestamp <b>"&lt;current time&gt; - 
                                &lt;timeDiffToNow&gt;"</b> dynamically (e.g. if set to 86400, the last 24 hours are considered by data 
								selection). The time period will be calculated dynamically at execution time.     </li> <br> 

                                <ul>
							    <b>Examples for input format:</b> <br>
								<code>attr &lt;name&gt; timeDiffToNow 86400</code> <br>
                                # the start time is set to "current time - 86400 seconds" <br>
								<code>attr &lt;name&gt; timeDiffToNow d:2 h:3 m:2 s:10</code> <br>
                                # the start time is set to "current time - 2 days 3 hours 2 minutes 10 seconds" <br>							
								<code>attr &lt;name&gt; timeDiffToNow m:600</code> <br> 
                                # the start time is set to "current time - 600 minutes" gesetzt <br>
								<code>attr &lt;name&gt; timeDiffToNow h:2.5</code> <br>
                                # the start time is set to "current time - 2,5 hours" <br>
								</ul>
								<br><br>								

  <li><b>timeOlderThan </b>   - the <b>end</b> of data selection will be set to the timestamp <b>"&lt;aktuelle Zeit&gt; - 
                                &lt;timeOlderThan&gt;"</b> dynamically. Always the datasets up to timestamp 
								"&lt;current time&gt; - &lt;timeOlderThan&gt;" will be considered (e.g. if set to 
								86400, all datasets older than one day are considered). The time period will be calculated dynamically at 
								execution time. <br>
								The valid input format for attribute "timeOlderThan" is identical to attribute "timeDiffToNow". </li> <br> 

  <li><b>timeout </b>         - set the timeout-value for Blocking-Call Routines in background in seconds (default 86400)  </li> <br>

  <li><b>userExitFn   </b>   - provides an interface to execute user specific program code. <br>
                               To activate the interfaace at first you should implement the subroutine which will be 
                               called by the interface in your 99_myUtls.pm as shown in by the example:     <br>

		<pre>
        sub UserFunction {
          my ($name,$reading,$value) = @_;
          my $hash = $defs{$name};
          ...
          # e.g. output transfered data
          Log3 $name, 1, "UserExitFn $name called - transfer parameter are Reading: $reading, Value: $value " ;
          ...
        return;
        }
  	    </pre>        
							   The interface activation takes place by setting the subroutine name into the attribute.
                               Optional you may set a Reading:Value combination (Regex) as argument. If no Regex is 
							   specified, all value combinations will be evaluated as "true" (related to .*:.*). 
							   <br><br>
							   
							   <ul>
							   <b>Example:</b> <br>
                               attr <device> userExitFn UserFunction .*:.* <br>
                               # "UserFunction" is the name of subroutine in 99_myUtils.pm.
							   </ul>
							   <br>
							   
							   The interface works generally without and independent from Events.
							   If the attribute is set, after every reading generation the Regex will be evaluated.
							   If the evaluation was "true", set subroutine will be called. 
							   For further processing following parameters will be forwarded to the function: <br><br>
                               
							   <ul>
                               <li>$name - the name of the DbRep-Device </li>
                               <li>$reading - the name of the created reading </li>
                               <li>$value - the value of the reading </li>
							   
							   </ul>
							   </li>
							   <br><br> 
							   
</ul></ul></ul>

<a name="DbRepReadings"></a>
<b>Readings</b>

<br>
<ul>
  Regarding to the selected operation the reasults will be shown as readings. At the beginning of a new operation all old readings will be deleted to avoid 
  that unsuitable or invalid readings would remain.<br><br>
  
  In addition the following readings will be created: <br><br>
  
  <ul><ul>
  <li><b>state  </b>                         - contains the current state of evaluation. If warnings are occured (state = Warning) compare Readings
                                               "diff_overrun_limit_&lt;diffLimit&gt;" and "less_data_in_period"  </li> <br>
  
  <li><b>errortext </b>                      - description about the reason of an error state </li> <br>
  
  <li><b>background_processing_time </b>     - the processing time spent for operations in background/forked operation </li> <br>
  
  <li><b>sql_processing_time </b>            - the processing time wasted for all sql-statements used for an operation </li> <br>
  
  <li><b>diff_overrun_limit_&lt;diffLimit&gt;</b>  - contains a list of pairs of datasets which have overrun the threshold (&lt;diffLimit&gt;) 
                                                     of calculated difference each other determined by attribute "diffAccept" (default=20). </li> <br>
  
  <li><b>less_data_in_period </b>            - contains a list of time periods within only one dataset was found.  The difference calculation considers
                                               the last value of the aggregation period before the current one. Valid for function "diffValue". </li> <br>	

  <li><b>SqlResult </b>                      - result of the last executed sqlCmd-command. The formatting can be specified
                                               by <a href="#DbRepattr">attribute</a> "sqlResultFormat" </li> <br>
											
  <li><b>sqlCmd </b>                         - contains the last executed sqlCmd-command </li> <br>
  
  </ul></ul>
  <br><br>

</ul>

<a name="DbRepAutoRename"></a>
<b>DbRep Agent - automatic change of device names in databases and DbRep-definitions after FHEM "rename" command</b>

<br>
<ul>
  By the attribute "role" the role of DbRep-device will be configured. The standard role is "Client". If the role has changed to "Agent", the DbRep device 
  react automatically on renaming devices in your FHEM installation. The DbRep device is now called DbRep-Agent. <br><br>
  
  By the DbRep-Agent the following features are activated when a FHEM-device has being renamed: <br><br>
  
  <ul><ul>
  <li> in the database connected to the DbRep-Agent (Internal Database) dataset containing the old device name will be searched and renamed to the 
       to the new device name in <b>all</b> affected datasets. </li> <br>
       
  <li> in the DbLog-Device assigned to the DbRep-Agent the definition will be changed to substitute the old device name by the new one. Thereby the logging of 
       the renamed device will be going on in the database. </li> <br>
  
  <li> in other existing DbRep-definitions with Type "Client" a possibly set attribute "device = old device name" will be changed to "device = new device name". 
       Because of that, reporting definitions will be kept consistent automatically if devices are renamed in FHEM. </li> <br>

  </ul></ul>
  
  The following restrictions take place if a DbRep device was changed to an Agent by setting attribute "role" to "Agent". These conditions will be activated 
  and checked: <br><br>
  
  <ul><ul>
  <li> within a FHEM installation only one DbRep-Agent can be configured for every defined DbLog-database. That means, if more than one DbLog-database is present, 
  you could define same numbers of DbRep-Agents as well as DbLog-devices are defined.  </li> <br>
  
  <li> after changing to DbRep-Agent role only the set-command "renameDevice" will be available and as well as a reduced set of module specific attributes will be  
       permitted. If a DbRep-device of privious type "Client" has changed an Agent, furthermore not permitted attributes will be deleted if set.  </li> <br>

  </ul></ul>
  
  All activities like database changes and changes of other DbRep-definitions will be logged in FHEM Logfile with verbose=3. In order that the renameDevice 
  function don't running into timeout set the timeout attribute to an appropriate value, especially if there are databases with huge datasets to evaluate. 
  As well as all the other database operations of this module, the autorename operation will be executed nonblocking. <br><br>
  
        <ul>
        <b>Example </b> of definition of a DbRep-device as an Agent:  <br><br>             
        <code>
        define Rep.Agent DbRep LogDB  <br>
        attr Rep.Agent devStateIcon connected:10px-kreis-gelb .*disconnect:10px-kreis-rot .*done:10px-kreis-gruen <br>
        attr Rep.Agent icon security      <br>
        attr Rep.Agent role Agent         <br>
        attr Rep.Agent room DbLog         <br>
        attr Rep.Agent showproctime 1     <br>
        attr Rep.Agent stateFormat { ReadingsVal("$name","state", undef) eq "running" ? "renaming" : ReadingsVal("$name","state", undef). " &raquo;; ProcTime: ".ReadingsVal("$name","sql_processing_time", undef)." sec"}  <br>
        attr Rep.Agent timeout 86400      <br>
        </code>
        <br>
        </ul>
		
  <b>Note:</b> <br>
     Even though the function itself is designed non-blocking, make sure the assigned DbLog-device
     is operating in asynchronous mode to avoid FHEMWEB from blocking. <br><br> 
  
</ul>

=end html
=begin html_DE

<a name="DbRep"></a>
<h3>DbRep</h3>
<ul>
  <br>
  Zweck des Moduls ist es, den Inhalt von DbLog-Datenbanken nach bestimmten Kriterien zu durchsuchen, zu managen, das Ergebnis hinsichtlich verschiedener 
  Aggregationen auszuwerten und als Readings darzustellen. Die Abgrenzung der zu berücksichtigenden Datenbankinhalte erfolgt durch die Angabe von Device, Reading und
  die Zeitgrenzen für Auswertungsbeginn bzw. Auswertungsende.  <br><br>
  
  Alle Datenbankoperationen werden nichtblockierend ausgeführt. Die Ausführungszeit der (SQL)-Hintergrundoperationen kann optional ebenfalls als Reading bereitgestellt
  werden (siehe <a href="#DbRepattr">Attribute</a>). <br>
  Alle vorhandenen Readings werden vor einer neuen Operation gelöscht. Durch das Attribut "readingPreventFromDel" kann eine Komma separierte Liste von Readings 
  angegeben werden die nicht gelöscht werden sollen. <br><br>
  
  Aktuell werden folgende Operationen unterstützt: <br><br>
  
     <ul><ul>
     <li> Selektion aller Datensätze innerhalb einstellbarer Zeitgrenzen </li>
     <li> Darstellung der Datensätze einer Device/Reading-Kombination innerhalb einstellbarer Zeitgrenzen. </li>
     <li> Selektion der Datensätze unter Verwendung von dynamisch berechneter Zeitgrenzen zum Ausführungszeitpunkt. </li>
     <li> Dubletten-Hervorhebung bei Datensatzanzeige (fetchrows) </li>
     <li> Berechnung der Anzahl von Datensätzen einer Device/Reading-Kombination unter Berücksichtigung von Zeitgrenzen 
	      und verschiedenen Aggregationen. </li>
     <li> Die Berechnung von Summen-, Differenz-, Maximum-, Minimum- und Durchschnittswerten numerischer Readings 
	      in Zeitgrenzen und verschiedenen Aggregationen. </li>
     <li> Speichern von Summen-, Differenz- , Maximum- , Minimum- und Durchschnittswertberechnungen in der Datenbank </li>
     <li> Löschung von Datensätzen. Die Eingrenzung der Löschung kann durch Device und/oder Reading sowie fixer oder 
	      dynamisch berechneter Zeitgrenzen zum Ausführungszeitpunkt erfolgen. </li>
     <li> Export von Datensätzen in ein File im CSV-Format </li>
     <li> Import von Datensätzen aus File im CSV-Format </li>
     <li> Umbenennen von Device/Readings in Datenbanksätzen </li>
     <li> Ändern von Reading-Werten (VALUES) in der Datenbank </li>
     <li> automatisches Umbenennen von Device-Namen in Datenbanksätzen und DbRep-Definitionen nach FHEM "rename" 
	      Befehl (siehe <a href="#DbRepAutoRename">DbRep-Agent</a>) </li>
	 <li> Ausführen von beliebigen Benutzer spezifischen SQL-Kommandos </li>
	 <li> Backups der FHEM-Datenbank im laufenden Betrieb erstellen (MySQL, SQLite) </li>
	 <li> senden des Dumpfiles zu einem FTP-Server nach dem Backup incl. Versionsverwaltung </li>
	 <li> Restore von SQLite-Dumps und MySQL serverSide-Backups </li>
	 <li> Optimierung der angeschlossenen Datenbank (optimizeTables, vacuum) </li>
	 <li> Ausgabe der existierenden Datenbankprozesse (MySQL) </li>
	 <li> leeren der current-Tabelle </li>
	 <li> Auffüllen der current-Tabelle mit einem (einstellbaren) Extrakt der history-Tabelle</li>
     <li> Bereinigung sequentiell aufeinander folgender Datensätze mit unterschiedlichen Zeitstempel aber gleichen Werten (sequentielle Dublettenbereinigung) </li>
	 <li> Reparatur einer korrupten SQLite Datenbank ("database disk image is malformed") </li>
     <li> Übertragung von Datensätzen aus der Quelldatenbank in eine andere (Standby) Datenbank (syncStandby) </li>
     </ul></ul>
     <br>
     
  Zur Aktivierung der Funktion "Autorename" wird dem definierten DbRep-Device mit dem Attribut "role" die Rolle "Agent" zugewiesen. Die Standardrolle nach Definition
  ist "Client". Mehr ist dazu im Abschnitt <a href="#DbRepAutoRename">DbRep-Agent</a> beschrieben. <br><br>
  
  DbRep stellt dem Nutzer einen UserExit zur Verfügung. Über diese Schnittstelle kann der Nutzer in Abhängigkeit von 
  frei definierbaren Reading/Value-Kombinationen (Regex) eigenen Code zur Ausführung bringen. Diese Schnittstelle arbeitet
  unabhängig von einer Eventgenerierung. Weitere Informationen dazu ist unter <a href="#DbRepattr">Attribut</a> 
  "userExitFn" beschrieben. <br><br>
  
  FHEM-Forum: <br>
  <a href="https://forum.fhem.de/index.php/topic,53584.msg452567.html#msg452567">Modul 93_DbRep - Reporting und Management von Datenbankinhalten (DbLog)</a>. <br><br>
  
  FHEM-Wiki: <br>
  <a href="https://wiki.fhem.de/wiki/DbRep_-_Reporting_und_Management_von_DbLog-Datenbankinhalten">DbRep - Reporting und Management von DbLog-Datenbankinhalten</a>. <br><br>
 
  <b>Voraussetzungen </b> <br><br>
  
  Das Modul setzt den Einsatz einer oder mehrerer DbLog-Instanzen voraus. Es werden die Zugangsdaten dieser 
  Datenbankdefinition genutzt. <br>
  Es werden nur Inhalte der Tabelle "history" berücksichtigt wenn nichts anderes beschrieben ist. <br><br>
  
  Überblick welche anderen Perl-Module DbRep verwendet: <br><br>
    
  Net::FTP     (nur wenn FTP-Transfer nach Datenbank-Dump genutzt wird)     <br>
  Net::FTPSSL  (nur wenn FTP-Transfer mit Verschlüsselung nach Datenbank-Dump genutzt wird)   <br>
  POSIX           <br>
  Time::HiRes     <br>
  Time::Local     <br>
  Scalar::Util    <br>
  DBI             <br>
  Color           (FHEM-Modul) <br>
  IO::Compress::Gzip           <br>
  IO::Uncompress::Gunzip       <br>
  Blocking        (FHEM-Modul) <br><br>
  
  Aus Performancegründen sollten zusätzlich folgender Index erstellt werden: <br>
  <code>
  CREATE INDEX Report_Idx ON `history` (TIMESTAMP, READING) USING BTREE;
  </code>
</ul>
<br>

<a name="DbRepdefine"></a>
<b>Definition</b>

<br>
<ul>
  <code>
    define &lt;name&gt; DbRep &lt;Name der DbLog-Instanz&gt; 
  </code>
  
  <br><br>
  (&lt;Name der DbLog-Instanz&gt; - es wird der Name der auszuwertenden DBLog-Datenbankdefinition angegeben <b>nicht</b> der Datenbankname selbst)

</ul>

<br><br>

<a name="DbRepset"></a>
<b>Set </b>
<ul>

 Zur Zeit gibt es folgende Set-Kommandos. Über sie werden die Auswertungen angestoßen und definieren selbst die Auswertungsvariante. 
 Nach welchen Kriterien die Datenbankinhalte durchsucht werden und die Aggregation erfolgt, wird durch <a href="#DbRepattr">Attribute</a> gesteuert. 
 <br><br>
 
 <ul><ul>
    <li><b> averageValue [display | writeToDB]</b> 
                                 - berechnet einen Durchschnittswert des Datenbankfelds "VALUE" in den 
                                 gegebenen Zeitgrenzen ( siehe <a href="#DbRepattr">Attribute</a>). 
                                 Es muss das auszuwertende Reading über das <a href="#DbRepattr">Attribut</a> "reading" 
								 angegeben sein. <br>
                                 Mit dem Attribut "averageCalcForm" wird die Berechnungsvariante zur Mittelwertermittlung definiert.
                                 Zur Zeit sind folgende Varianten implementiert: <br><br>

	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>avgArithmeticMean</b>  </td><td>: es wird der arithmetische Mittelwert berechnet 
                                                                                    (default) </td></tr>
                                      <tr><td> <b>avgDailyMeanGWS</b>    </td><td>: berechnet die Tagesmitteltemperatur entsprechend den
                                                                                    <a href='https://www.dwd.de/DE/leistungen/klimadatendeutschland/beschreibung_tagesmonatswerte.html'>Vorschriften</a> des Deutschen Wetterdienstes. <br>
                                                                                    Diese Variante verwendet automatisch die Aggregation "day". </td></tr>
                                      <tr><td> <b>avgTimeWeightMean</b>  </td><td>: berechnet den zeitgewichteten Mittelwert </td></tr>
								   </table>
	                               </ul>
	                               <br>
                                   
                                 Ist keine oder die Option "display" angegeben, werden die Ergebnisse nur angezeigt. Mit 
                                 der Option "writeToDB" werden die Berechnungsergebnisse mit einem neuen Readingnamen
                                 in der Datenbank gespeichert. <br>
                                 Der neue Readingname wird aus einem Präfix und dem originalen Readingnamen gebildet. 
                                 Der Präfix setzt sich aus der Bildungsfunktion und der Aggregation zusammen. <br>
                                 Der Timestamp der neuen Readings in der Datenbank wird von der eingestellten Aggregationsperiode 
                                 abgeleitet, sofern kein eindeutiger Zeitpunkt des Ergebnisses bestimmt werden kann. 
                                 Das Feld "EVENT" wird mit "calculated" gefüllt.<br><br>
                                 
                                 <ul>
                                 <b>Beispiel neuer Readingname gebildet aus dem Originalreading "totalpac":</b> <br>
                                 avgam_day_totalpac <br>
                                 # &lt;Bildungsfunktion&gt;_&lt;Aggregation&gt;_&lt;Originalreading&gt; <br>                         
                                 </li> <br>
                                 </ul>

    <li><b> cancelDump </b>   -  bricht einen laufenden Datenbankdump ab. </li> <br>
    
    <li><b> changeValue </b>  -  ändert den gespeicherten Wert eines Readings.
                                 Ist die Selektion auf bestimmte Device/Reading-Kombinationen durch die 
                                 <a href="#DbRepattr">Attribute</a> "device" bzw. "reading" beschränkt, werden sie genauso 
                                 berücksichtigt wie gesetzte Zeitgrenzen (Attribute time.*).  <br>
                                 Fehlen diese Beschränkungen, wird die gesamte Datenbank durchsucht und der angegebene Wert 
                                 geändert. <br><br>
                                 
                                 <ul>
                                 <b>Syntax: </b> <br>
                                 set &lt;name&gt; changeValue "&lt;alter String&gt;","&lt;neuer String&gt;"  <br><br>
                                 
                                 Die Strings werden in Doppelstrich eingeschlossen und durch Komma getrennt. 
                                 Dabei kann "String" sein: <br>
                                 
<pre>
&lt;alter String&gt; : * ein einfacher String mit/ohne Leerzeichen, z.B. "OL 12"
                 * ein String mit Verwendung von SQL-Wildcard, z.B. "%OL%"
                 
&lt;neuer String&gt; : * ein einfacher String mit/ohne Leerzeichen, z.B. "12 kWh"
                 * Perl Code eingeschlossen in {}, z.B. {$VALUE = (split(",",$VALUE))[0]}. 
                   Dem Perl-Ausdruck werden die Variablen $VALUE und $UNIT übergeben. Sie können innerhalb
                   des Perl-Code geändert werden. Der zurückgebene Wert von $VALUE und $UNIT wird in dem Feld 
                   VALUE bzw. UNIT des Datensatzes gespeichert.                        
</pre>
                                 
                                 <b>Beispiele: </b> <br>
                                 set &lt;name&gt; changeValue "OL","12 OL"  <br>               
                                 # der alte Feldwert "OL" wird in "12 OL" geändert.  <br><br>
                                 
                                 set &lt;name&gt; changeValue "%OL%","12 OL"  <br>
                                 # enthält das Feld VALUE den Teilstring "OL", wird es in "12 OL" geändert. <br><br>
                                 
                                 set &lt;name&gt; changeValue "12 kWh","{$VALUE,$UNIT = split(" ",$VALUE)}"  <br>
                                 # der alte Feldwert "12 kWh" wird in VALUE=12 und UNIT=kWh gesplittet und in den Datenbankfeldern gespeichert <br><br>

                                 set &lt;name&gt; changeValue "24%","{$VALUE = (split(" ",$VALUE))[0]}"  <br>
                                 # beginnt der alte Feldwert mit "24", wird er gesplittet und VALUE=24 gespeichert (z.B. "24 kWh")
                                 <br><br>
                                 
                                 Zusammengefasst sind die zur Steuerung von changeValue relevanten Attribute: <br><br>

	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>device</b>            </td><td>: Selektion nur von Datensätzen die &lt;device&gt; enthalten </td></tr>
                                      <tr><td> <b>reading</b>           </td><td>: Selektion nur von Datensätzen die &lt;reading&gt; enthalten </td></tr>
                                      <tr><td> <b>time.*</b>            </td><td>: eine Reihe von Attributen zur Zeitabgrenzung </td></tr>
	                                  <tr><td> <b>executeBeforeProc</b> </td><td>: ausführen FHEM Kommando (oder perl-Routine) vor Start changeValue </td></tr>
                                      <tr><td> <b>executeAfterProc</b>  </td><td>: ausführen FHEM Kommando (oder perl-Routine) nach Ende changeValue </td></tr>
                                      </table>
	                               </ul>
	                               <br>
	                               <br>
								 
								 <b>Hinweis:</b> <br>
                                 Obwohl die Funktion selbst non-blocking ausgelegt ist, sollte das zugeordnete DbLog-Device
                                 im asynchronen Modus betrieben werden um ein Blockieren von FHEMWEB zu vermeiden (Tabellen-Lock). <br><br> 
                                 </li> <br>
                                 </ul>
								 
    <li><b> countEntries [history | current] </b> 
                                 -  liefert die Anzahl der Tabelleneinträge (default: history) in den gegebenen 
	                             Zeitgrenzen (siehe <a href="#DbRepattr">Attribute</a>). 
                                 Sind die Timestamps nicht gesetzt werden alle Einträge gezählt. 
                                 Beschränkungen durch die <a href="#DbRepattr">Attribute</a> Device bzw. Reading 
								 gehen in die Selektion mit ein.  </li> <br>

    <li><b> delEntries </b>   -  löscht alle oder die durch die <a href="#DbRepattr">Attribute</a> device und/oder 
	                             reading definierten Datenbankeinträge. Die Eingrenzung über Timestamps erfolgt 
								 folgendermaßen: <br><br>
                                 
                                 <ul>
                                 "timestamp_begin" gesetzt:  gelöscht werden DB-Einträge <b>ab</b> diesem Zeitpunkt bis zum aktuellen Datum/Zeit <br>
                                 "timestamp_end" gesetzt  :  gelöscht werden DB-Einträge <b>bis</b> bis zu diesem Zeitpunkt <br>
                                 beide Timestamps gesetzt :  gelöscht werden DB-Einträge <b>zwischen</b> diesen Zeitpunkten <br>
                                 
                                 <br>
                                 Aus Sicherheitsgründen muss das <a href="#DbRepattr">Attribut</a> "allowDeletion" 
								 gesetzt sein um die Löschfunktion freizuschalten. <br>
                                 </li>
								 <br>
                                 </ul>
								 
    <li><b> delSeqDoublets [adviceRemain | adviceDelete | delete]</b>   -  zeigt bzw. löscht aufeinander folgende identische Datensätze.
	                             Dazu wird Device,Reading und Value ausgewertet. Nicht gelöscht werden der erste und der letzte Datensatz 
								 einer Aggregationsperiode (z.B. hour, day, week usw.) sowie die Datensätze vor oder nach einem Wertewechsel 
								 (Datenbankfeld VALUE). <br>
								 Die <a href="#DbRepattr">Attribute</a> zur Aggregation,Zeit-,Device- und Reading-Abgrenzung werden dabei 
								 berücksichtigt. Ist das Attribut "aggregation" nicht oder auf "no" gesetzt, wird als Standard die Aggregation 
								 "day" verwendet. Für Datensätze mit numerischen Werten kann mit dem <a href="#DbRepattr">Attribut</a>
                                 "seqDoubletsVariance" eine Abweichung eingestellt werden, bis zu der aufeinander folgende numerische Werte als
                                 identisch angesehen und gelöscht werden sollen.
	                             <br><br>
								 
	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>adviceRemain</b>  </td><td>: simuliert die nach der Operation in der DB verbleibenden Datensätze (es wird nichts gelöscht !) </td></tr>
                                      <tr><td> <b>adviceDelete</b>  </td><td>: simuliert die zu löschenden Datensätze (es wird nichts gelöscht !) </td></tr>
                                      <tr><td> <b>delete</b>        </td><td>: löscht die sequentiellen Dubletten (siehe Beispiel) </td></tr>
                                   </table>
	                               </ul>
	                               <br>

                                 Aus Sicherheitsgründen muss das <a href="#DbRepattr">Attribut</a> "allowDeletion" für die "delete" Option
								 gesetzt sein. <br>
								 Die Anzahl der anzuzeigenden Datensätze der Kommandos "delSeqDoublets adviceDelete", "delSeqDoublets adviceRemain" ist 
								 zunächst begrenzt (default 1000) und kann durch das <a href="#DbRepattr">Attribut</a> "limit" angepasst werden.
								 Die Einstellung von "limit" hat keinen Einfluss auf die "delSeqDoublets delete" Funktion, sondern beeinflusst <b>NUR</b> die 
								 Anzeige der Daten.	 <br>
                                 Vor und nach der Ausführung von "delSeqDoublets" kann ein FHEM-Kommando bzw. Perl-Routine ausgeführt werden. 
                                 (siehe <a href="#DbRepattr">Attribute</a>  "executeBeforeProc", "executeAfterProc")
                                 <br><br>						   
								  
								 <ul>
								 <b>Beispiel</b> - die nach Verwendung der delete-Option in der DB verbleibenden Datensätze sind <b>fett</b>
								 gekennzeichnet:<br><br>
								 <ul>
                                 <b>2017-11-25_00-00-05__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 2017-11-25_00-02-26__eg.az.fridge_Pwr__power 0             <br>
                                 2017-11-25_00-04-33__eg.az.fridge_Pwr__power 0             <br>
                                 2017-11-25_01-06-10__eg.az.fridge_Pwr__power 0             <br>
                                 <b>2017-11-25_01-08-21__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 <b>2017-11-25_01-08-59__eg.az.fridge_Pwr__power 60.32 </b>     <br>
                                 <b>2017-11-25_01-11-21__eg.az.fridge_Pwr__power 56.26 </b>     <br>
                                 <b>2017-11-25_01-27-54__eg.az.fridge_Pwr__power 6.19  </b>     <br>
                                 <b>2017-11-25_01-28-51__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 2017-11-25_01-31-00__eg.az.fridge_Pwr__power 0             <br>
                                 2017-11-25_01-33-59__eg.az.fridge_Pwr__power 0             <br>
                                 <b>2017-11-25_02-39-29__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 <b>2017-11-25_02-41-18__eg.az.fridge_Pwr__power 105.28</b>     <br>
                                 <b>2017-11-25_02-41-26__eg.az.fridge_Pwr__power 61.52 </b>     <br>
                                 <b>2017-11-25_03-00-06__eg.az.fridge_Pwr__power 47.46 </b>     <br>
                                 <b>2017-11-25_03-00-33__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 2017-11-25_03-02-07__eg.az.fridge_Pwr__power 0             <br>
                                 2017-11-25_23-37-42__eg.az.fridge_Pwr__power 0             <br>
                                 <b>2017-11-25_23-40-10__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 <b>2017-11-25_23-42-24__eg.az.fridge_Pwr__power 1     </b>     <br>
                                 2017-11-25_23-42-24__eg.az.fridge_Pwr__power 1             <br>
                                 <b>2017-11-25_23-45-27__eg.az.fridge_Pwr__power 1     </b>     <br>
                                 <b>2017-11-25_23-47-07__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 2017-11-25_23-55-27__eg.az.fridge_Pwr__power 0             <br>
                                 <b>2017-11-25_23-48-15__eg.az.fridge_Pwr__power 0     </b>     <br>
                                 <b>2017-11-25_23-50-21__eg.az.fridge_Pwr__power 59.1  </b>     <br>
                                 <b>2017-11-25_23-55-14__eg.az.fridge_Pwr__power 52.31 </b>     <br>
                                 <b>2017-11-25_23-58-09__eg.az.fridge_Pwr__power 51.73 </b>     <br>
                                 </ul>
								 </ul>
                                
                                 </li>
								 <br>
								 <br>
                             
    <li><b> deviceRename </b> -  benennt den Namen eines Device innerhalb der angeschlossenen Datenbank (Internal 
	                             DATABASE) um.
                                 Der Gerätename wird immer in der <b>gesamten</b> Datenbank umgesetzt. Eventuell gesetzte 
								 Zeitgrenzen oder Beschränkungen durch die <a href="#DbRepattr">Attribute</a> Device bzw. 
								 Reading werden nicht berücksichtigt.  <br><br>
                                 
                                 <ul>
                                 <b>Beispiel: </b><br>  
                                 set &lt;name&gt; deviceRename &lt;alter Devicename&gt;,&lt;neuer Devicename&gt;  <br>               
                                 # Die Anzahl der umbenannten Device-Datensätze wird im Reading "device_renamed" ausgegeben. <br>
                                 # Wird der umzubenennende Gerätename in der Datenbank nicht gefunden, wird eine WARNUNG im Reading "device_not_renamed" ausgegeben. <br>
                                 # Entsprechende Einträge erfolgen auch im Logfile mit verbose=3
                                 <br><br>
								 
								 <b>Hinweis:</b> <br>
                                 Obwohl die Funktion selbst non-blocking ausgelegt ist, sollte das zugeordnete DbLog-Device
                                 im asynchronen Modus betrieben werden um ein Blockieren von FHEMWEB zu vermeiden (Tabellen-Lock). <br><br> 
                                 </li> <br>
                                 </ul>
          
    <li><b> diffValue [display | writeToDB] </b>    
                                 - berechnet den Differenzwert des Datenbankfelds "VALUE" in den Zeitgrenzen (Attribute) "timestamp_begin", "timestamp_end" bzw "timeDiffToNow / timeOlderThan". 
                                 Es muss das auszuwertende Reading im Attribut "reading" angegeben sein. 
                                 Diese Funktion ist z.B. zur Auswertung von Eventloggings sinnvoll, deren Werte sich fortlaufend erhöhen und keine Wertdifferenzen wegschreiben. <br>								 
                                 Es wird immer die Differenz aus dem Value-Wert des ersten verfügbaren Datensatzes und dem Value-Wert des letzten verfügbaren Datensatzes innerhalb der angegebenen
                                 Zeitgrenzen/Aggregation gebildet, wobei ein Übertragswert der Vorperiode (Aggregation) zur darauf folgenden Aggregationsperiode 
                                 berücksichtigt wird sofern diese einen Value-Wert enhtält.  <br>
								 Dabei wird ein Zählerüberlauf (Neubeginn bei 0) mit berücksichtigt (vergleiche <a href="#DbRepattr">Attribut</a> "diffAccept"). <br>
								 Wird in einer auszuwertenden Zeit- bzw. Aggregationsperiode nur ein Datensatz gefunden, kann die Differenz in Verbindung mit dem 
								 Differenzübertrag der Vorperiode berechnet werden. in diesem Fall kann es zu einer logischen Ungenauigkeit in der Zuordnung der Differenz
                                 zu der Aggregationsperiode kommen. Deswegen wird eine Warnung im "state" und das 						 
								 Reading "less_data_in_period" mit einer Liste der betroffenen Perioden wird erzeugt. <br><br>
								 
                                 <ul>
                                 <b>Hinweis: </b><br>
                                 Im Auswertungs- bzw. Aggregationszeitraum (Tag, Woche, Monat, etc.) sollten dem Modul pro Periode mindestens ein Datensatz 
                                 zu Beginn und ein Datensatz gegen Ende des Aggregationszeitraumes zur Verfügung stehen um eine möglichst genaue Auswertung 
                                 der Differenzwerte vornehmen zu können.
                                 <br>
                                 <br>
                                 </ul>
                                 Ist keine oder die Option "display" angegeben, werden die Ergebnisse nur angezeigt. Mit 
                                 der Option "writeToDB" werden die Berechnungsergebnisse mit einem neuen Readingnamen
                                 in der Datenbank gespeichert. <br>
                                 Der neue Readingname wird aus einem Präfix und dem originalen Readingnamen gebildet. 
                                 Der Präfix setzt sich aus der Bildungsfunktion und der Aggregation zusammen. <br>
                                 Der Timestamp der neuen Readings in der Datenbank wird von der eingestellten Aggregationsperiode 
                                 abgeleitet, sofern kein eindeutiger Zeitpunkt des Ergebnisses bestimmt werden kann. 
                                 Das Feld "EVENT" wird mit "calculated" gefüllt.<br><br>
                                 
                                 <ul>
                                 <b>Beispiel neuer Readingname gebildet aus dem Originalreading "totalpac":</b> <br>
                                 diff_day_totalpac <br>
                                 # &lt;Bildungsfunktion&gt;_&lt;Aggregation&gt;_&lt;Originalreading&gt; <br>                         
                                 </li> <br>
                                 </ul>

    <li><b> dumpMySQL [clientSide | serverSide]</b>    
	                             -  erstellt einen Dump der angeschlossenen MySQL-Datenbank.  <br>
								 Abhängig von der ausgewählten Option wird der Dump auf der Client- bzw. Serverseite erstellt. <br>
								 Die Varianten unterscheiden sich hinsichtlich des ausführenden Systems, des Erstellungsortes, der 
								 Attributverwendung, des erzielten Ergebnisses und der benötigten Hardwareressourcen. <br>
								 Die Option "clientSide" benötigt z.B. eine leistungsfähigere Hardware des FHEM-Servers, sichert aber alle
								 Tabellen inklusive eventuell angelegter Views. <br>
                                 Mit dem Attribut "dumpCompress" kann eine Komprimierung der erstellten Dumpfiles eingeschaltet werden.
								 <br><br>
								 
								 <ul>
								 <b><u>Option clientSide</u></b> <br>
	                             Der Dump wird durch den Client (FHEM-Rechner) erstellt und per default im log-Verzeichnis des Clients 
								 gespeichert. 
								 Das Zielverzeichnis kann mit dem <a href="#DbRepattr">Attribut</a> "dumpDirLocal" verändert werden und muß auf
								 dem Client durch FHEM beschreibbar sein. <br>
								 Vor dem Dump kann eine Tabellenoptimierung (Attribut "optimizeTablesBeforeDump") oder ein FHEM-Kommando 
								 (Attribut "executeBeforeProc") optional zugeschaltet werden. 
                                 Nach dem Dump kann ebenfalls ein FHEM-Kommando (siehe Attribut "executeAfterProc") ausgeführt werden. <br><br>
								 
								 <b>Achtung ! <br>
								 Um ein Blockieren von FHEM zu vermeiden, muß DbLog im asynchronen Modus betrieben werden wenn die
								 Tabellenoptimierung verwendet wird ! </b> <br><br>
								 
                                 Über die <a href="#DbRepattr">Attribute</a> "dumpMemlimit" und "dumpSpeed" kann das Laufzeitverhalten der 
								 Funktion beeinflusst werden um eine Optimierung bezüglich Performance und Ressourcenbedarf zu erreichen. <br><br>						 
                                 
								 Die für "dumpMySQL clientSide" relevanten Attribute sind: <br><br>
	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> dumpComment              </td><td>: User-Kommentar im Dumpfile  </td></tr>
                                      <tr><td> dumpCompress             </td><td>: Komprimierung des Dumpfiles nach der Erstellung </td></tr>
                                      <tr><td> dumpDirLocal             </td><td>: das lokale Zielverzeichnis für die Erstellung des Dump </td></tr>
                                      <tr><td> dumpMemlimit             </td><td>: Begrenzung der Speicherverwendung </td></tr>
                                      <tr><td> dumpSpeed                </td><td>: Begrenzung die CPU-Belastung </td></tr>
	                                  <tr><td> dumpFilesKeep            </td><td>: Anzahl der aufzubwahrenden Dumpfiles </td></tr>
	                                  <tr><td> executeBeforeProc        </td><td>: ausführen FHEM Kommando (oder perl-Routine) vor dem Dump </td></tr>
                                      <tr><td> executeAfterProc         </td><td>: ausführen FHEM Kommando (oder perl-Routine) nach dem Dump </td></tr>
	                                  <tr><td> optimizeTablesBeforeDump </td><td>: Tabelloptimierung vor dem Dump ausführen </td></tr>
                                   </table>
	                               </ul>
	                               <br>                                
                                 
                                 Nach einem erfolgreichen Dump werden alte Dumpfiles gelöscht und nur die Anzahl Files, definiert durch
                                 das Attribut "dumpFilesKeep" (default: 3), verbleibt im Zielverzeichnis "dumpDirLocal". Falls "dumpFilesKeep = 0" 
                                 gesetzt ist, werden alle Dumpfiles (auch das aktuell erstellte File), gelöscht. 
                                 Diese Einstellung kann sinnvoll sein, wenn FTP aktiviert ist
                                 und die erzeugten Dumps nur im FTP-Zielverzeichnis erhalten bleiben sollen. <br><br>
								 
								 Die <b>Namenskonvention der Dumpfiles</b> ist:  &lt;dbname&gt;_&lt;date&gt;_&lt;time&gt;.sql[.gzip] <br><br>
								 
								 Das erzeugte Dumpfile kann z.B. mit: <br><br>
								 
								   <ul>
								   mysql -u &lt;user&gt; -p &lt;dbname&gt; < &lt;filename&gt;.sql <br><br>
								   </ul>
								 
								 auf dem MySQL-Server ausgeführt werden um die Datenbank aus dem Dump wiederherzustellen. <br><br>
								 <br>
								 
								 <b><u>Option serverSide</u></b> <br>
								 Der Dump wird durch den MySQL-Server erstellt und per default im Home-Verzeichnis des MySQL-Servers 
								 gespeichert. <br>
								 Es wird die gesamte history-Tabelle (nicht current-Tabelle) <b>im CSV-Format</b> ohne 
								 Einschränkungen exportiert. <br>
								 Vor dem Dump kann eine Tabellenoptimierung (Attribut "optimizeTablesBeforeDump") 
								 optional zugeschaltet werden . <br><br>
								 
								 <b>Achtung ! <br>
								 Um ein Blockieren von FHEM zu vermeiden, muß DbLog im asynchronen Modus betrieben werden wenn die
								 Tabellenoptimierung verwendet wird ! </b> <br><br>
								 
								 Vor und nach dem Dump kann ein FHEM-Kommando (siehe Attribute "executeBeforeProc", "executeAfterProc") ausgeführt 
								 werden. <br><br>

								 Die für "dumpMySQL serverSide" relevanten Attribute sind: <br><br>
	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> dumpDirRemote            </td><td>: das Erstellungsverzeichnis des Dumpfile dem entfernten Server </td></tr>
                                      <tr><td> dumpCompress             </td><td>: Komprimierung des Dumpfiles nach der Erstellung </td></tr>
                                      <tr><td> dumpDirLocal             </td><td>: Directory des lokal gemounteten dumpDirRemote-Verzeichnisses  </td></tr>
	                                  <tr><td> dumpFilesKeep            </td><td>: Anzahl der aufzubwahrenden Dumpfiles </td></tr>
	                                  <tr><td> executeBeforeProc        </td><td>: ausführen FHEM Kommando (oder perl-Routine) vor dem Dump </td></tr>
                                      <tr><td> executeAfterProc         </td><td>: ausführen FHEM Kommando (oder perl-Routine) nach dem Dump </td></tr>
	                                  <tr><td> optimizeTablesBeforeDump </td><td>: Tabelloptimierung vor dem Dump ausführen </td></tr>
                                   </table>
	                               </ul>
	                               <br>  
								 
								 Das Zielverzeichnis kann mit dem <a href="#DbRepattr">Attribut</a> "dumpDirRemote" verändert werden. 
								 Es muß sich auf dem MySQL-Host gefinden und durch den MySQL-Serverprozess beschreibbar sein. <br>
								 Der verwendete Datenbankuser benötigt das "FILE"-Privileg. <br><br>
								 
								 <b>Hinweis:</b> <br>
								 Soll die interne Versionsverwaltung und die Dumpfilekompression des Moduls genutzt, sowie die Größe des erzeugten 
                                 Dumpfiles ausgegeben werden, ist das Verzeichnis "dumpDirRemote" des MySQL-Servers auf dem Client zu mounten 
								 und im <a href="#DbRepattr">Attribut</a> "dumpDirLocal" dem DbRep-Device bekannt zu machen. <br>
								 Gleiches gilt wenn der FTP-Transfer nach dem Dump genutzt werden soll (Attribut "ftpUse" bzw. "ftpUseSSL"). 
								 <br><br>

                                 <ul>                                 
                                 <b>Beispiel: </b> <br>
                                 attr &lt;name&gt; dumpDirRemote /volume1/ApplicationBackup/dumps_FHEM/ <br>
								 attr &lt;name&gt; dumpDirLocal /sds1/backup/dumps_FHEM/ <br>
								 attr &lt;name&gt; dumpFilesKeep 2 <br><br>
								 
                                 # Der Dump wird remote auf dem MySQL-Server im Verzeichnis '/volume1/ApplicationBackup/dumps_FHEM/' 
								   erstellt. <br>
								 # Die interne Versionsverwaltung sucht im lokal gemounteten Verzeichnis '/sds1/backup/dumps_FHEM/' 
								 vorhandene Dumpfiles und löscht diese bis auf die zwei letzten Versionen. <br>
                                 <br>
                                 </ul>								 
								 
                                 Wird die interne Versionsverwaltung genutzt, werden nach einem erfolgreichen Dump alte Dumpfiles gelöscht 
								 und nur die Anzahl "dumpFilesKeep" (default: 3) verbleibt im Zielverzeichnis "dumpDirRemote". 
								 FHEM benötigt in diesem Fall Schreibrechte auf dem Verzeichnis "dumpDirLocal". <br><br>		

								 Die <b>Namenskonvention der Dumpfiles</b> ist:  &lt;dbname&gt;_&lt;date&gt;_&lt;time&gt;.csv[.gzip] <br><br>
								 
								 Ein Restore der Datenbank aus diesem Backup kann durch den Befehl: <br><br>
								   <ul>
								   set &lt;name&gt; &lt;restoreMySQL&gt; &lt;filename&gt;.csv[.gzip] <br><br>
								   </ul>
								
                                 gestartet werden. <br><br>	

                                 
								 <b><u>FTP Transfer nach Dump</u></b> <br>
								 Wenn diese Möglichkeit genutzt werden soll, ist das <a href="#DbRepattr">Attribut</a> "ftpUse" oder 
								 "ftpUseSSL" zu setzen. Letzteres gilt wenn eine verschlüsselte Übertragung genutzt werden soll. <br>
                                 Das Modul übernimmt ebenfalls die Versionierung der Dumpfiles im FTP-Zielverzeichnis mit Hilfe des Attributes 
                                 "ftpDumpFilesKeep".                                 
								 Für die FTP-Übertragung relevante <a href="#DbRepattr">Attribute</a> sind: <br><br>
								 
	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> ftpUse      </td><td>: FTP Transfer nach dem Dump wird eingeschaltet (ohne SSL Verschlüsselung) </td></tr>
                                      <tr><td> ftpUser     </td><td>: User zur Anmeldung am FTP-Server, default: anonymous </td></tr>
                                      <tr><td> ftpUseSSL   </td><td>: FTP Transfer mit SSL Verschlüsselung nach dem Dump wird eingeschaltet </td></tr>
                                      <tr><td> ftpDebug    </td><td>: Debugging des FTP Verkehrs zur Fehlersuche </td></tr>
	                                  <tr><td> ftpDir      </td><td>: Verzeichnis auf dem FTP-Server in welches das File übertragen werden soll (default: "/") </td></tr>
	                                  <tr><td> ftpDumpFilesKeep </td><td>: Es wird die angegebene Anzahl Dumpfiles im &lt;ftpDir&gt; belassen (default: 3) </td></tr>
                                      <tr><td> ftpPassive  </td><td>: setzen wenn passives FTP verwendet werden soll </td></tr>
	                                  <tr><td> ftpPort     </td><td>: FTP-Port, default: 21 </td></tr>
									  <tr><td> ftpPwd      </td><td>: Passwort des FTP-Users, default nicht gesetzt </td></tr>
									  <tr><td> ftpServer   </td><td>: Name oder IP-Adresse des FTP-Servers. <b>notwendig !</b> </td></tr>
									  <tr><td> ftpTimeout  </td><td>: Timeout für die FTP-Verbindung in Sekunden (default: 30). </td></tr>
                                   </table>
	                               </ul>
	                               <br>
	                               <br>
								
								 </ul>   
								 </li><br>
                                 
    <li><b> dumpSQLite </b>   -  erstellt einen Dump der angeschlossenen SQLite-Datenbank.  <br>
	                             Diese Funktion nutzt die SQLite Online Backup API und ermöglicht es konsistente Backups der SQLite-DB
                                 in laufenden Betrieb zu erstellen.
                                 Der Dump wird per default im log-Verzeichnis des FHEM-Rechners gespeichert. 
								 Das Zielverzeichnis kann mit dem <a href="#DbRepattr">Attribut</a> "dumpDirLocal" verändert werden und muß
								 durch FHEM beschreibbar sein.
					             Vor dem Dump kann optional eine Tabellenoptimierung (Attribut "optimizeTablesBeforeDump") 
                                 zugeschaltet werden.
                                 <br><br>
								 
								 <b>Achtung ! <br>
								 Um ein Blockieren von FHEM zu vermeiden, muß DbLog im asynchronen Modus betrieben werden wenn die
								 Tabellenoptimierung verwendet wird ! </b> <br><br>
								 
								 Vor und nach dem Dump kann ein FHEM-Kommando (siehe Attribute "executeBeforeProc", "executeAfterProc") 
                                 ausgeführt werden. <br><br>				 
                                 
                 	             Die für diese Funktion relevanten Attribute sind: <br><br>
	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> dumpCompress             </td><td>: Komprimierung des Dumpfiles nach der Erstellung </td></tr>
                                      <tr><td> dumpDirLocal             </td><td>: Directory des lokal gemounteten dumpDirRemote-Verzeichnisses  </td></tr>
	                                  <tr><td> dumpFilesKeep            </td><td>: Anzahl der aufzubwahrenden Dumpfiles </td></tr>
	                                  <tr><td> executeBeforeProc        </td><td>: ausführen FHEM Kommando (oder perl-Routine) vor dem Dump </td></tr>
                                      <tr><td> executeAfterProc         </td><td>: ausführen FHEM Kommando (oder perl-Routine) nach dem Dump </td></tr>
	                                  <tr><td> optimizeTablesBeforeDump </td><td>: Tabelloptimierung vor dem Dump ausführen </td></tr>
                                   </table>
	                               </ul>
	                               <br> 
                                   
								 Nach einem erfolgreichen Dump werden alte Dumpfiles gelöscht und nur die Anzahl Files, definiert durch das 
                                 Attribut "dumpFilesKeep" (default: 3), verbleibt im Zielverzeichnis "dumpDirLocal". Falls "dumpFilesKeep = 0" gesetzt, werden
                                 alle Dumpfiles (auch das aktuell erstellte File), gelöscht. Diese Einstellung kann sinnvoll sein, wenn FTP aktiviert ist
                                 und die erzeugten Dumps nur im FTP-Zielverzeichnis erhalten bleiben sollen. <br><br>
								 
								 Die <b>Namenskonvention der Dumpfiles</b> ist:  &lt;dbname&gt;_&lt;date&gt;_&lt;time&gt;.sqlitebkp[.gzip] <br><br>
								 
								 Die Datenbank kann mit "set &lt;name&gt; restoreSQLite &lt;Filename&gt;" wiederhergestellt 
                                 werden. <br>
                                 Das erstellte Dumpfile kann auf einen FTP-Server übertragen werden. Siehe dazu die Erläuterungen
                                 unter "dumpMySQL". <br><br>
								 </li><br>

    <li><b> eraseReadings </b>   - Löscht alle angelegten Readings im Device, außer dem Reading "state" und Readings, die in der 
                                 Ausnahmeliste definiert mit Attribut "readingPreventFromDel" enthalten sind.                                
                                 </li><br>
                                 
    <li><b> exportToFile </b> -  exportiert DB-Einträge im CSV-Format in den gegebenen Zeitgrenzen. 
                                 Einschränkungen durch die <a href="#DbRepattr">Attribute</a> Device bzw. Reading gehen in die Selektion mit ein. 
                                 Der Filename wird durch das <a href="#DbRepattr">Attribut</a> "expimpfile" bestimmt. <br>
                                 Durch das Attribut "aggregation" wird der Export der Datensätze in Zeitscheiben der angegebenen Aggregation 
                                 vorgenommen. Ist z.B. "aggregation = month" gesetzt, werden die Daten in monatlichen Paketen selektiert und in
                                 das Exportfile geschrieben. Dadurch wird die Hauptspeicherverwendung optimiert wenn sehr große Datenmengen
                                 exportiert werden sollen und vermeidet den "died prematurely" Abbruchfehler.                                 
                                 </li><br>
        
    <li><b> fetchrows [history|current] </b>    
                                 -  liefert <b>alle</b> Tabelleneinträge (default: history) 
	                             in den gegebenen Zeitgrenzen bzw. Selektionsbedingungen durch die <a href="#DbRepattr">Attribute</a> 
                                 "device" und "reading".
                                 Eine evtl. gesetzte Aggregation wird dabei <b>nicht</b> berücksichtigt. <br>
								 Die Leserichtung in der Datenbank kann durch das <a href="#DbRepattr">Attribut</a> 
								 "fetchRoute" bestimmt werden. <br><br>
                                 
                                 Jedes Ergebnisreading setzt sich aus dem Timestring des Datensatzes, einem Index, dem Device
                                 und dem Reading zusammen.
                                 Die Funktion fetchrows ist in der Lage mehrfach vorkommende Datensätze (Dubletten) zu erkennen.
                                 Solche Dubletten sind mit einem Index > 1 gekennzeichnet. <br>
                                 Dubletten können mit dem Attribut "fetchMarkDuplicates" farblich hervorgehoben werden. <br><br>
                                 
                                 <b>Hinweis:</b> <br>
                                 Hervorgehobene Readings werden nach einem Restart bzw. nach rereadcfg nicht mehr angezeigt da
                                 sie nicht im statefile gesichert werden (Verletzung erlaubter Readingnamen durch Formatierung). 
                                 <br><br>                
                                 
                                 Dieses Attribut ist mit einigen Farben vorbelegt, kann aber mit dem colorpicker-Widget 
                                 überschrieben werden: <br><br>
                                 
                                 <ul>
                                 <code>
                                 attr &lt;name&gt; widgetOverride fetchMarkDuplicates:colorpicker
                                 </code>
                                 </ul>                                 
                                 <br>
                                 
                                 Die Ergebnisreadings von fetchrows sind nach folgendem Schema aufgebaut: <br><br>
                                 
                                 <ul>
                                 <b>Beispiel:</b> <br>
                                 2017-10-22_03-04-43__1__SMA_Energymeter__Bezug_WirkP_Kosten_Diff <br>
                                 # &lt;Datum&gt;_&lt;Zeit&gt;__&lt;Index&gt;__&lt;Device&gt;__&lt;Reading&gt;
                                 </ul>                                 
                                 <br>

                                 Zur besseren Übersicht sind die zur Steuerung von fetchrows relevanten Attribute hier noch einmal
                                 dargestellt: <br><br>

	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>fetchRoute</b>            </td><td>: Leserichtung des Selekts innerhalb der Datenbank </td></tr>
                                      <tr><td> <b>limit</b>                 </td><td>: begrenzt die Anzahl zu selektierenden bzw. anzuzeigenden Datensätze  </td></tr>
                                      <tr><td> <b>fetchMarkDuplicates</b>   </td><td>: Hervorhebung von gefundenen Dubletten </td></tr>
                                      <tr><td> <b>device</b>                </td><td>: Selektion nur von Datensätzen die &lt;device&gt; enthalten </td></tr>
                                      <tr><td> <b>reading</b>               </td><td>: Selektion nur von Datensätzen die &lt;reading&gt; enthalten </td></tr>
                                      <tr><td> <b>time.*</b>                </td><td>: eine Reihe von Attributen zur Zeitabgrenzung </td></tr>
                                   </table>
	                               </ul>
	                               <br>
	                               <br>                                 

								 <b>Hinweis:</b> <br>
                                 Auch wenn das Modul bezüglich der Datenbankabfrage nichtblockierend arbeitet, kann eine 
								 zu große Ergebnismenge (Anzahl Zeilen bzw. Readings) die Browsersesssion bzw. FHEMWEB 
								 blockieren. Aus diesem Grund wird die Ergebnismenge mit dem 
								 <a href="#DbRepattrlimit">Attribut</a> "limit" begrenzt. Bei Bedarf kann dieses Attribut 
								 geändert werden, falls eine Anpassung der Selektionsbedingungen nicht möglich oder 
								 gewünscht ist. <br><br>
								 </li> <br> 								 
       
    <li><b> insert </b>       -  Manuelles Einfügen eines Datensatzes in die Tabelle "history". Obligatorisch sind Eingabewerte für Datum, Zeit und Value. 
                                 Die Werte für die DB-Felder Type bzw. Event werden mit "manual" gefüllt, sowie die Werte für Device, Reading aus den gesetzten  <a href="#DbRepattr">Attributen </a> genommen.  <br><br>
                                 
                                 <ul>
                                 <b>Eingabeformat: </b>   Datum,Zeit,Value,[Unit]  <br>               
                                 # Unit ist optional, Attribute "reading" und "device" müssen gesetzt sein  <br>
                                 # Soll "Value=0" eingefügt werden, ist "Value = 0.0" zu verwenden. <br><br>
                                 
                                 <b>Beispiel: </b>        2016-08-01,23:00:09,TestValue,TestUnit  <br>
                                 # Es sind KEINE Leerzeichen im Feldwert erlaubt !<br>
                                 <br>
								 
								 <b>Hinweis: </b><br>
                                 Bei der Eingabe ist darauf zu achten dass im beabsichtigten Aggregationszeitraum (Tag, Woche, Monat, etc.) MINDESTENS zwei 
								 Datensätze für die Funktion diffValue zur Verfügung stehen. Ansonsten kann keine Differenz berechnet werden und diffValue 
								 gibt in diesem Fall "0" in der betroffenen Periode aus !
                                 <br>
                                 <br>
								 </li>
                                 </ul>
    
    <li><b> importFromFile </b> - importiert Datensätze im CSV-Format aus einem File in die Datenbank. Der Filename wird 
	                              durch das <a href="#DbRepattr">Attribut</a> "expimpfile" bestimmt. <br><br>
                                 
                                 <ul>
                                 <b>Datensatzformat: </b>  "TIMESTAMP","DEVICE","TYPE","EVENT","READING","VALUE","UNIT"  <br><br>              
                                 # Die Felder "TIMESTAMP","DEVICE","TYPE","EVENT","READING" und "VALUE" müssen gesetzt sein. Das Feld "UNIT" ist optional.
                                 Der Fileinhalt wird als Transaktion importiert, d.h. es wird der Inhalt des gesamten Files oder, im Fehlerfall, kein Datensatz des Files importiert. 
                                 Wird eine umfangreiche Datei mit vielen Datensätzen importiert sollte KEIN verbose=5 gesetzt werden. Es würden in diesem Fall sehr viele Sätze in
                                 das Logfile geschrieben werden was FHEM blockieren oder überlasten könnte. <br><br>
                                 
                                 <b>Beispiel: </b>        "2016-09-25 08:53:56","STP_5000","SMAUTILS","etotal: 11859.573","etotal","11859.573",""  <br>
                                 <br>
                                 </li> <br>
                                 </ul>    
    
    <li><b> maxValue [display | writeToDB] </b>     
                                 - berechnet den Maximalwert des Datenbankfelds "VALUE" in den Zeitgrenzen 
	                             (Attribute) "timestamp_begin", "timestamp_end" bzw. "timeDiffToNow / timeOlderThan". 
                                 Es muss das auszuwertende Reading über das <a href="#DbRepattr">Attribut</a> "reading" 
								 angegeben sein. 
                                 Die Auswertung enthält den Zeitstempel des ermittelten Maximumwertes innerhalb der 
								 Aggregation bzw. Zeitgrenzen.  
                                 Im Reading wird der Zeitstempel des <b>letzten</b> Auftretens vom Maximalwert ausgegeben
								 falls dieser Wert im Intervall mehrfach erreicht wird. <br>
                                 
                                 Ist keine oder die Option "display" angegeben, werden die Ergebnisse nur angezeigt. Mit 
                                 der Option "writeToDB" werden die Berechnungsergebnisse mit einem neuen Readingnamen
                                 in der Datenbank gespeichert. <br>
                                 Der neue Readingname wird aus einem Präfix und dem originalen Readingnamen gebildet. 
                                 Der Präfix setzt sich aus der Bildungsfunktion und der Aggregation zusammen. <br>
                                 Der Timestamp der neuen Readings in der Datenbank wird von der eingestellten Aggregationsperiode 
                                 abgeleitet, sofern kein eindeutiger Zeitpunkt des Ergebnisses bestimmt werden kann. 
                                 Das Feld "EVENT" wird mit "calculated" gefüllt.<br><br>
                                 
                                 <ul>
                                 <b>Beispiel neuer Readingname gebildet aus dem Originalreading "totalpac":</b> <br>
                                 max_day_totalpac <br>
                                 # &lt;Bildungsfunktion&gt;_&lt;Aggregation&gt;_&lt;Originalreading&gt; <br>                         
                                 </li> <br>
                                 </ul>                                
                                 
    <li><b> minValue [display | writeToDB]</b>     
                                 - berechnet den Minimalwert des Datenbankfelds "VALUE" in den Zeitgrenzen 
	                             (Attribute) "timestamp_begin", "timestamp_end" bzw. "timeDiffToNow / timeOlderThan". 
                                 Es muss das auszuwertende Reading über das <a href="#DbRepattr">Attribut</a> "reading" 
								 angegeben sein. 
                                 Die Auswertung enthält den Zeitstempel des ermittelten Minimumwertes innerhalb der 
								 Aggregation bzw. Zeitgrenzen.  
                                 Im Reading wird der Zeitstempel des <b>ersten</b> Auftretens vom Minimalwert ausgegeben 
								 falls dieser Wert im Intervall mehrfach erreicht wird. <br>
                                 
                                 Ist keine oder die Option "display" angegeben, werden die Ergebnisse nur angezeigt. Mit 
                                 der Option "writeToDB" werden die Berechnungsergebnisse mit einem neuen Readingnamen
                                 in der Datenbank gespeichert. <br>
                                 Der neue Readingname wird aus einem Präfix und dem originalen Readingnamen gebildet. 
                                 Der Präfix setzt sich aus der Bildungsfunktion und der Aggregation zusammen. <br>
                                 Der Timestamp der neuen Readings in der Datenbank wird von der eingestellten Aggregationsperiode 
                                 abgeleitet, sofern kein eindeutiger Zeitpunkt des Ergebnisses bestimmt werden kann. 
                                 Das Feld "EVENT" wird mit "calculated" gefüllt.<br><br>
                                 
                                 <ul>
                                 <b>Beispiel neuer Readingname gebildet aus dem Originalreading "totalpac":</b> <br>
                                 min_day_totalpac <br>
                                 # &lt;Bildungsfunktion&gt;_&lt;Aggregation&gt;_&lt;Originalreading&gt; <br>                         
                                 </li> <br>
                                 </ul>                                 
								 
	<li><b> optimizeTables </b> - optimiert die Tabellen in der angeschlossenen Datenbank (MySQL). <br>
								  Vor und nach der Optimierung kann ein FHEM-Kommando ausgeführt werden. 
                                  (siehe <a href="#DbRepattr">Attribute</a>  "executeBeforeProc", "executeAfterProc")
                                  <br><br>
								 
								<ul>
								<b>Hinweis:</b> <br>
                                Obwohl die Funktion selbst non-blocking ausgelegt ist, muß das zugeordnete DbLog-Device
                                im asynchronen Modus betrieben werden um ein Blockieren von FHEMWEB zu vermeiden. <br><br>           
								</li>
                                </ul><br>
                                                         				 
    <li><b> readingRename </b> - benennt den Namen eines Readings innerhalb der angeschlossenen Datenbank (siehe Internal DATABASE) um.
                                 Der Readingname wird immer in der <b>gesamten</b> Datenbank umgesetzt. Eventuell 
								 gesetzte Zeitgrenzen oder Beschränkungen durch die <a href="#DbRepattr">Attribute</a> 
								 Device bzw. Reading werden nicht berücksichtigt.  <br><br>
                                 
                                 <ul>
                                 <b>Beispiel: </b><br>  
                                 set &lt;name&gt; readingRename &lt;alter Readingname&gt;,&lt;neuer Readingname&gt;  <br>               
                                 # Die Anzahl der umbenannten Device-Datensätze wird im Reading "reading_renamed" 
								   ausgegeben. <br>
                                 # Wird der umzubenennende Readingname in der Datenbank nicht gefunden, wird eine 
								   WARNUNG im Reading "reading_not_renamed" ausgegeben. <br>
                                 # Entsprechende Einträge erfolgen auch im Logfile mit verbose=3.
                                 <br><br>
								 
								 <b>Hinweis:</b> <br>
                                 Obwohl die Funktion selbst non-blocking ausgelegt ist, sollte das zugeordnete DbLog-Device
                                 im asynchronen Modus betrieben werden um ein Blockieren von FHEMWEB zu vermeiden (Tabellen-Lock). <br><br> 
                                 </li> <br>
                                 </ul>  

    <li><b> repairSQLite </b>  - repariert eine korrupte SQLite-Datenbank. <br>
                                 Eine Korruption liegt im Allgemeinen vor wenn die Fehlermitteilung "database disk image is malformed"
                                 im state des DbLog-Devices erscheint.
                                 Wird dieses Kommando gestartet, wird das angeschlossene DbLog-Device zunächst automatisch für 10 Stunden
                                 (36000 Sekunden) von der Datenbank getrennt (Trennungszeit). Nach Abschluss der Reparatur erfolgt 
                                 wieder eine sofortige Neuverbindung zur reparierten Datenbank. <br>
								 Dem Befehl kann eine abweichende Trennungszeit (in Sekunden) als Argument angegeben werden. <br>
                                 Die korrupte Datenbank wird als &lt;database&gt;.corrupt im gleichen Verzeichnis gespeichert.                                  <br><br>
                                 
                                 <ul>
                                 <b>Beispiel: </b><br>  
                                 set &lt;name&gt; repairSQLite  <br>               
                                 # Die Datenbank wird repariert, Trennungszeit beträgt 10 Stunden <br>
                                 set &lt;name&gt; repairSQLite 600 <br>   
                                 # Die Datenbank wird repariert, Trennungszeit beträgt 10 Minuten
                                 <br><br>
								 
								 <b>Hinweis:</b> <br>
                                 Es ist nicht garantiert, dass die Reparatur erfolgreich verläuft und keine Daten verloren gehen. 
                                 Je nach Schwere der Korruption kann Datenverlust auftreten oder die Reparatur scheitern, auch wenn
                                 kein Fehler im Ablauf signalisiert wird. Ein Backup der Datenbank sollte unbedingt vorhanden 
                                 sein ! <br><br> 
                                 </li> <br>
                                 </ul> 								 

    <li><b> restoreMySQL &lt;File&gt;.csv[.gzip] </b>  - importiert den Inhalt der history-Tabelle aus einem serverSide-Backup. <br>
                                 Die Funktion stellt über eine Drop-Down Liste eine Dateiauswahl für den Restore zur Verfügung.
                                 Dazu ist das Verzeichnis "dumpDirRemote" des MySQL-Servers auf dem Client zu mounten 
								 und im <a href="#DbRepattr">Attribut</a> "dumpDirLocal" dem DbRep-Device bekannt zu machen. <br>
								 Es werden alle Files mit der Endung "csv[.gzip]" und deren Name mit der 
								 verbundenen Datenbank beginnt (siehe Internal DATABASE), aufgelistet . <br><br>
								 </li><br>
                                 
    <li><b> restoreSQLite &lt;File&gt;.sqlitebkp[.gzip] </b>  - stellt das Backup einer SQLite-Datenbank wieder her. <br>
                                 Die Funktion stellt über eine Drop-Down Liste die für den Restore zur Verfügung stehenden Dateien
                                 zur Verfügung. Die aktuell in der Zieldatenbank enthaltenen Daten werden gelöscht bzw. 
                                 überschrieben.
                                 Es werden alle Files mit der Endung "sqlitebkp[.gzip]" und deren Name mit dem Namen der 
								 verbundenen Datenbank beginnt, aufgelistet . <br><br>
								 </li><br>
								 
    <li><b> sqlCmd </b>        - führt ein beliebiges Benutzer spezifisches Kommando aus. <br>
                                 Enthält dieses Kommando eine Delete-Operation, muss zur Sicherheit das 
								 <a href="#DbRepattr">Attribut</a> "allowDeletion" gesetzt sein. <br>
                                 Bei der Ausführung dieses Kommandos werden keine Einschränkungen durch gesetzte Attribute
                                 "device", "reading", "time.*" bzw. "aggregation" berücksichtigt. <br>
								 Sollen die im Modul gesetzten <a href="#DbRepattr">Attribute</a> "timestamp_begin" bzw. 
								 "timestamp_end" im Statement berücksichtigt werden, können die Platzhalter 
								 "<b>§timestamp_begin§</b>" bzw. "<b>§timestamp_end§</b>" dafür verwendet werden. <br><br>
								 
								 Soll ein Datensatz upgedated werden, ist dem Statement "TIMESTAMP=TIMESTAMP" hinzuzufügen um eine Änderung des
								 originalen Timestamps zu verhindern. <br><br>
								 
	                             <ul>
                                 <b>Beispiele für Statements: </b> <br><br> 
								 <ul>
                                 <li>set &lt;name&gt; sqlCmd select DEVICE, count(*) from history where TIMESTAMP >= "2017-01-06 00:00:00" group by DEVICE having count(*) > 800 </li>
                                 <li>set &lt;name&gt; sqlCmd select DEVICE, count(*) from history where TIMESTAMP >= "2017-05-06 00:00:00" group by DEVICE </li>
								 <li>set &lt;name&gt; sqlCmd select DEVICE, count(*) from history where TIMESTAMP >= §timestamp_begin§ group by DEVICE </li>
                                 <li>set &lt;name&gt; sqlCmd select * from history where DEVICE like "Te%t" order by `TIMESTAMP` desc </li>
                                 <li>set &lt;name&gt; sqlCmd select * from history where `TIMESTAMP` > "2017-05-09 18:03:00" order by `TIMESTAMP` desc </li>
                                 <li>set &lt;name&gt; sqlCmd select * from current order by `TIMESTAMP` desc  </li>
                                 <li>set &lt;name&gt; sqlCmd select sum(VALUE) as 'Einspeisung am 04.05.2017', count(*) as 'Anzahl' FROM history where `READING` = "Einspeisung_WirkP_Zaehler_Diff" and TIMESTAMP between '2017-05-04' AND '2017-05-05' </li>
                                 <li>set &lt;name&gt; sqlCmd delete from current  </li>
                                 <li>set &lt;name&gt; sqlCmd delete from history where TIMESTAMP < "2016-05-06 00:00:00" </li>
                                 <li>set &lt;name&gt; sqlCmd update history set TIMESTAMP=TIMESTAMP,VALUE='Val' WHERE VALUE='TestValue' </li>
                                 <li>set &lt;name&gt; sqlCmd select * from history where DEVICE = "Test" </li>
                                 <li>set &lt;name&gt; sqlCmd insert into history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES ('2017-05-09 17:00:14','Test','manuell','manuell','Tes§e','TestValue','°C') </li>    
                                 </ul>
								 <br>
								 
								 Das Ergebnis des Statements wird im <a href="#DbRepReadings">Reading</a> "SqlResult" dargestellt.
								 Die Ergebnis-Formatierung kann durch das <a href="#DbRepattr">Attribut</a> "sqlResultFormat" ausgewählt, sowie der verwendete
								 Feldtrenner durch das <a href="#DbRepattr">Attribut</a> "sqlResultFieldSep" festgelegt werden. <br><br>
                                 
                                 Das Modul stellt optional eine Kommando-Historie zur Verfügung sobald ein SQL-Kommando erfolgreich 
                                 ausgeführt wurde.
                                 Um diese Option zu nutzen, ist das Attribut "sqlCmdHistoryLength" mit der gewünschten Listenlänge
                                 zu aktivieren. <br><br>
                                 
                                 Zur besseren Übersicht sind die zur Steuerung von sqlCmd relevanten Attribute hier noch einmal
                                 dargestellt: <br><br>

	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>allowDeletion</b>       </td><td>: aktiviert Löschmöglichkeit </td></tr>
                                      <tr><td> <b>sqlResultFormat</b>     </td><td>: legt die Darstellung des Kommandoergebnis fest  </td></tr>
                                      <tr><td> <b>sqlResultFieldSep</b>   </td><td>: Auswahl Feldtrenner im Ergebnis </td></tr>
                                      <tr><td> <b>sqlCmdHistoryLength</b> </td><td>: Aktivierung Kommando-Historie und deren Umfang</td></tr>
                                   </table>
	                               </ul>
	                               <br>
	                               <br>  
                                 
								 <b>Hinweis:</b> <br>
                                 Auch wenn das Modul bezüglich der Datenbankabfrage nichtblockierend arbeitet, kann eine 
								 zu große Ergebnismenge (Anzahl Zeilen bzw. Readings) die Browsersesssion bzw. FHEMWEB 
								 blockieren. Wenn man sich unsicher ist, sollte man vorsorglich dem Statement ein Limit 
								 hinzufügen. <br><br>
                                 </li> <br>
                                 </ul>
                                 
    <li><b> sqlCmdHistory </b>   - Wenn mit dem <a href="#DbRepattr">Attribut</a> "sqlCmdHistoryLength" aktiviert, kann
                                   aus einer Liste ein bereits erfolgreich ausgeführtes sqlCmd-Kommando wiederholt werden. <br>
                                   Mit Ausführung des letzten Eintrags der Liste, "__purge_historylist__", kann die Liste gelöscht 
                                   werden. <br>
                                   Falls das Statement "," enthält, wird dieses Zeichen aus technischen Gründen in der 
                                   History-Liste als "&lt;c&gt;" dargestellt. <br>
								   </li><br>
								 
    <li><b> sumValue [display | writeToDB]</b>     
                                 - Berechnet die Summenwerte des Datenbankfelds "VALUE" in den Zeitgrenzen 
	                               (Attribute) "timestamp_begin", "timestamp_end" bzw. "timeDiffToNow / timeOlderThan". 
                                   Es muss das auszuwertende Reading im <a href="#DbRepattr">Attribut</a> "reading" 
								   angegeben sein. Diese Funktion ist sinnvoll wenn fortlaufend Wertedifferenzen eines 
								   Readings in die Datenbank geschrieben werden.  <br>
                                 
                                   Ist keine oder die Option "display" angegeben, werden die Ergebnisse nur angezeigt. Mit 
                                   der Option "writeToDB" werden die Berechnungsergebnisse mit einem neuen Readingnamen
                                   in der Datenbank gespeichert. <br>
                                   Der neue Readingname wird aus einem Präfix und dem originalen Readingnamen gebildet. 
                                   Der Präfix setzt sich aus der Bildungsfunktion und der Aggregation zusammen. <br>
                                   Der Timestamp der neuen Readings in der Datenbank wird von der eingestellten Aggregationsperiode 
                                   abgeleitet, sofern kein eindeutiger Zeitpunkt des Ergebnisses bestimmt werden kann. 
                                   Das Feld "EVENT" wird mit "calculated" gefüllt.<br><br>
                                 
                                   <ul>
                                   <b>Beispiel neuer Readingname gebildet aus dem Originalreading "totalpac":</b> <br>
                                   sum_day_totalpac <br>
                                   # &lt;Bildungsfunktion&gt;_&lt;Aggregation&gt;_&lt;Originalreading&gt; <br>                         
                                   </li> <br>
                                   </ul>
                                   <br>
                                   
    <li><b> syncStandby &lt;DbLog-Device Standby&gt; </b>    
                                 -  Es werden die Datensätze aus der angeschlossenen Datenbank (Quelle) direkt in eine weitere 
                                 Datenbank (Standby-Datenbank) übertragen. 
                                 Dabei ist "&lt;DbLog-Device Standby&gt;" das DbLog-Device, welches mit der Standby-Datenbank
                                 verbunden ist. <br><br>
                                 Es werden alle Datensätze übertragen, die durch Timestamp-<a href="#DbRepattrlimit">Attribute</a>
                                 bzw. die Attribute "device", "reading" bestimmt sind. <br>
                                 Die Datensätze werden dabei in Zeitscheiben entsprechend der eingestellten Aggregation übertragen.
                                 Hat das Attribut "aggregation" den Wert "no" oder "month", werden die Datensätze automatisch 
                                 in Tageszeitscheiben zur Standby-Datenbank übertragen. 
                                 Quell- und Standby-Datenbank können unterschiedlichen Typs sein.
								 <br><br>

                                 Die zur Steuerung der syncStandby Funktion relevanten Attribute sind: <br><br>

	                               <ul>
                                   <table>  
                                   <colgroup> <col width=5%> <col width=95%> </colgroup>
                                      <tr><td> <b>aggregation</b>  </td><td>: Einstellung der Zeitscheiben zur Übertragung (hour,day,week) </td></tr>
                                      <tr><td> <b>device</b>       </td><td>: Übertragung nur von Datensätzen die &lt;device&gt; enthalten </td></tr>
                                      <tr><td> <b>reading</b>      </td><td>: Übertragung nur von Datensätzen die &lt;reading&gt; enthalten </td></tr>
                                      <tr><td> <b>time.*</b>       </td><td>: Attribute zur Zeitabgrenzung der zu übertragenden Datensätze.  </td></tr>
                                   </table>
	                               </ul>
	                               <br>
	                               <br>                                 
								 </li> <br>
								 
	<li><b> tableCurrentFillup </b> - Die current-Tabelle wird mit einem Extrakt der history-Tabelle aufgefüllt. 
	                                  Die <a href="#DbRepattr">Attribute</a> zur Zeiteinschränkung bzw. device, reading werden ausgewertet.
                                      Dadurch kann der Inhalt des Extrakts beeinflusst werden. Im zugehörigen DbLog-Device sollte sollte das Attribut 
                                      "DbLogType=SampleFill/History" gesetzt sein. </li> <br> 
									 
	<li><b> tableCurrentPurge </b> - löscht den Inhalt der current-Tabelle. Es werden keine Limitierungen, z.B. durch die Attribute "timestamp_begin", 
	                                 "timestamp_end", device, reading, usw. , ausgewertet.	</li> <br> 
								 
	<li><b> vacuum </b>      - optimiert die Tabellen in der angeschlossenen Datenbank (SQLite, PostgreSQL). <br>
							   Vor und nach der Optimierung kann ein FHEM-Kommando ausgeführt werden. 
                               (siehe <a href="#DbRepattr">Attribute</a>  "executeBeforeProc", "executeAfterProc") 
                               <br><br>
								 
							   <ul>
							   <b>Hinweis:</b> <br>
                               Obwohl die Funktion selbst non-blocking ausgelegt ist, muß das zugeordnete DbLog-Device
                               im asynchronen Modus betrieben werden um ein Blockieren von FHEM zu vermeiden. <br><br>           
							   </li>
                               </ul><br>
								                              
  <br>
  </ul></ul>
  
  <b>Für alle Auswertungsvarianten (Ausnahme sqlCmd,deviceRename,readingRename) gilt: </b> <br>
  Zusätzlich zu dem auszuwertenden Reading kann das Device mit angegeben werden um das Reporting nach diesen Kriterien einzuschränken. 
  Sind keine Zeitgrenzen-Attribute angegeben jedoch das Aggregations-Attribut gesetzt, wird der Zeitstempel des ältesten 
  Datensatzes in der Datenbank als Startdatum und das aktuelle Datum/die aktuelle Zeit als Zeitgrenze genutzt.
  Konnte der älteste Datensatz in der Datenbank nicht ermittelt werden, wird '1970-01-01 01:00:00' als Selektionsstart
  genutzt (siehe get &lt;name&gt; minTimestamp).
  Sind weder Zeitgrenzen-Attribute noch Aggregation angegeben, wird die Datenselektion ohne Timestamp-Einschränkungen
  ausgeführt.  
  <br><br>
  
  <b>Hinweis: </b> <br>
  
  In der Detailansicht kann ein Browserrefresh nötig sein um die Operationsergebnisse zu sehen sobald im DeviceOverview "state = done" angezeigt wird. 
  <br><br>

</ul>  

<a name="DbRepget"></a>
<b>Get </b>
<ul>

 Die Get-Kommandos von DbRep dienen dazu eine Reihe von Metadaten der verwendeten Datenbankinstanz abzufragen. 
 Dies sind zum Beispiel eingestellte Serverparameter, Servervariablen, Datenbankstatus- und Tabelleninformationen. Die verfügbaren get-Funktionen 
 sind von dem verwendeten Datenbanktyp abhängig. So ist für SQLite z.Zt. nur "svrinfo" verfügbar. Die Funktionen liefern nativ sehr viele Ausgabewerte, 
 die über über funktionsspezifische <a href="#DbRepattr">Attribute</a> abgrenzbar sind. Der Filter ist als kommaseparierte Liste anzuwenden. 
 Dabei kann SQL-Wildcard (%) verwendet werden. 
 <br><br>
 
 <b>Hinweis: </b> <br>
 Nach der Ausführung einer get-Funktion in der Detailsicht einen Browserrefresh durchführen um die Ergebnisse zu sehen ! 
 <br><br>
 
 
 <ul><ul>
    <li><b> blockinginfo </b> - Listet die aktuell systemweit laufenden Hintergrundprozesse (BlockingCalls) mit ihren Informationen auf. 
	                            Zu lange Zeichenketten (z.B. Argumente) werden gekürzt ausgeschrieben.
                                </li>     
                                <br><br>
							
    <li><b> dbstatus </b> -  Listet globale Informationen zum MySQL Serverstatus (z.B. Informationen zum Cache, Threads, Bufferpools, etc. ). 
                             Es werden zunächst alle verfügbaren Informationen berichtet. Mit dem <a href="#DbRepattr">Attribut</a> "showStatus" kann die 
                             Ergebnismenge eingeschränkt werden, um nur gewünschte Ergebnisse abzurufen. Detailinformationen zur Bedeutung der einzelnen Readings 
                             sind <a href=http://dev.mysql.com/doc/refman/5.7/en/server-status-variables.html>hier</a> verfügbar.  <br>
                             
                                 <br><ul>
                                 <b>Bespiel</b>  <br>
                                 get &lt;name&gt; dbstatus  <br>
                                 attr &lt;name&gt; showStatus %uptime%,%qcache%    <br>               
                                 # Es werden nur Readings erzeugt die im Namen "uptime" und "qcache" enthalten 
                                 </li> 
                                 <br><br>
                                 </ul>                               
                                 
    <li><b> dbvars </b> -  Zeigt die globalen Werte der MySQL Systemvariablen. Enthalten sind zum Beispiel Angaben zum InnoDB-Home, dem Datafile-Pfad, 
                           Memory- und Cache-Parameter, usw. Die Ausgabe listet zunächst alle verfügbaren Informationen auf. Mit dem 
                           <a href="#DbRepattr">Attribut</a> "showVariables" kann die Ergebnismenge eingeschränkt werden um nur gewünschte Ergebnisse 
                           abzurufen. Weitere Informationen zur Bedeutung der ausgegebenen Variablen sind 
                           <a href=http://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html>hier</a> verfügbar. <br>
                           
                                 <br><ul>
                                 <b>Bespiel</b>  <br>
                                 get &lt;name&gt; dbvars  <br>
                                 attr &lt;name&gt; showVariables %version%,%query_cache%    <br>               
                                 # Es werden nur Readings erzeugt die im Namen "version" und "query_cache" enthalten
                                 </li> 
                                 <br><br>
                                 </ul>  

    <li><b> minTimestamp </b> - Ermittelt den Zeitstempel des ältesten Datensatzes in der Datenbank (wird implizit beim Start von
                                FHEM ausgeführt).
                                Der Zeitstempel wird als Selektionsbeginn verwendet wenn kein Zeitattribut den Selektionsbeginn
                                festlegt.                                
                                </li>     
                                <br><br>                                 

    <li><b> procinfo </b> - Listet die existierenden Datenbank-Prozesse in einer Tabelle auf (nur MySQL). <br>
	                        Typischerweise werden nur die Prozesse des Verbindungsusers (angegeben in DbLog-Konfiguration)
							ausgegeben. Sollen alle Prozesse angezeigt werden, ist dem User das globale Recht "PROCESS" 
							einzuräumen. <br>
							Für bestimmte SQL-Statements wird seit MariaDB 5.3 ein Fortschrittsreporting (Spalte "PROGRESS")
							ausgegeben. Zum Beispiel kann der Abarbeitungsgrad bei der Indexerstellung verfolgt werden. <br>
							Weitere Informationen sind 
                            <a href=https://mariadb.com/kb/en/mariadb/show-processlist/>hier</a> verfügbar. <br>
                            </li>     
                            <br><br>
                         
								 
    <li><b> svrinfo </b> -  allgemeine Datenbankserver-Informationen wie z.B. die DBMS-Version, Serveradresse und Port usw. Die Menge der Listenelemente 
                            ist vom Datenbanktyp abhängig. Mit dem <a href="#DbRepattr">Attribut</a> "showSvrInfo" kann die Ergebnismenge eingeschränkt werden.
                            Weitere Erläuterungen zu den gelieferten Informationen sind 
                            <a href=https://msdn.microsoft.com/en-us/library/ms711681(v=vs.85).aspx>hier</a> zu finden. <br>
                                 
                                 <br><ul>
                                 <b>Bespiel</b>  <br>
                                 get &lt;name&gt; svrinfo  <br>
                                 attr &lt;name&gt; showSvrInfo %SQL_CATALOG_TERM%,%NAME%   <br>               
                                 # Es werden nur Readings erzeugt die im Namen "SQL_CATALOG_TERM" und "NAME" enthalten
                                 </li> 
                                 <br><br>
                                 </ul>                                                      
                                 
    <li><b> tableinfo </b> -  ruft Tabelleninformationen aus der mit dem DbRep-Device verbundenen Datenbank ab (MySQL). 
	                          Es werden per default alle in der verbundenen Datenbank angelegten Tabellen ausgewertet. 
                              Mit dem <a href="#DbRepattr">Attribut</a> "showTableInfo" können die Ergebnisse eingeschränkt werden. Erläuterungen zu den erzeugten 
                              Readings sind  <a href=http://dev.mysql.com/doc/refman/5.7/en/show-table-status.html>hier</a> zu finden.  <br>
                                 
                                 <br><ul>
                                 <b>Bespiel</b>  <br>
                                 get &lt;name&gt; tableinfo  <br>
                                 attr &lt;name&gt; showTableInfo current,history   <br>               
                                 # Es werden nur Information der Tabellen "current" und "history" angezeigt
                                 </li> 
                                 <br><br>
                                 </ul>                                                      
                                                     
  <br>
  </ul></ul>
  
</ul>  


<a name="DbRepattr"></a>
<b>Attribute</b>

<br>
<ul>
  Über die modulspezifischen Attribute wird die Abgrenzung der Auswertung und die Aggregation der Werte gesteuert. <br><br>
  
  <b>Hinweis zur SQL-Wildcard Verwendung:</b> <br>
  Innerhalb der Attribut-Werte für "device" und "reading" kann SQL-Wildcards "%" angegeben werden. 
  Dabei wird "%" als Platzhalter für beliebig viele Zeichen verwendet. 
  Das Zeichen "_" wird nicht als SQL-Wildcard supported.  <br>
  Dies gilt für alle Funktionen <b>ausser</b> "insert", "importFromFile" und "deviceRename". <br>
  Die Funktion "insert" erlaubt nicht, dass die genannten Attribute das Wildcard "%" enthalten. Character "_" wird als normales Zeichen gewertet.<br>
  In Ergebnis-Readings wird das Wildcardzeichen "%" durch "/" ersetzt um die Regeln für erlaubte Zeichen in Readings einzuhalten.
  <br><br>
  
  <ul><ul>
  <li><b>aggregation </b>     - Zusammenfassung der Device/Reading-Selektionen in Stunden,Tages,Kalenderwochen,Kalendermonaten oder "no". Liefert z.B. die Anzahl der DB-Einträge am Tag (countEntries), Summation von Differenzwerten eines Readings (sumValue), usw. Mit Aggregation "no" (default) erfolgt keine Zusammenfassung in einem Zeitraum sondern die Ausgabe ergibt alle Werte eines Device/Readings zwischen den definierten Zeiträumen.  </li> <br>

  <li><b>allowDeletion </b>   - schaltet die Löschfunktion des Moduls frei   </li> <br>
  
  <li><b>averageCalcForm </b> - legt die Berechnungsvariante für die Ermittlung des Durchschnittswertes mit "averageValue" fest.                                 
                                </li><br>

  <li><b>device </b>          - Abgrenzung der DB-Selektionen auf ein bestimmtes Device. <br>
                                Es können <a href="https://fhem.de/commandref_DE.html#devspec">Geräte-Spezifikationen (devspec)</a>
								angegeben werden. <br> 
								Innerhalb von Geräte-Spezifikationen wird SQL-Wildcard (%) als normales ASCII-Zeichen gewertet. 
								Die Devicenamen werden vor der Selektion aus der Geräte-Spezifikationen und den aktuell in FHEM 
								vorhandenen Devices abgeleitet. </li> <br>
  
                                <ul>
							    <b>Beispiele:</b> <br>
								<code>attr &lt;name&gt; device TYPE=DbRep</code> <br>
								<code>attr &lt;name&gt; device MySTP_5000</code> <br> 
								<code>attr &lt;name&gt; device SMA.*,MySTP.*</code> <br> 
								<code>attr &lt;name&gt; device SMA_Energymeter,MySTP_5000</code> <br>
								<code>attr &lt;name&gt; device %5000</code> <br>
								</ul>
								<br><br>

  <li><b>diffAccept </b>      - gilt für Funktion diffValue. diffAccept legt fest bis zu welchem Schwellenwert eine berechnete positive Werte-Differenz 
                                zwischen zwei unmittelbar aufeinander folgenden Datensätzen akzeptiert werden soll (Standard ist 20). <br>
								Damit werden fehlerhafte DB-Einträge mit einem unverhältnismäßig hohen Differenzwert von der Berechnung ausgeschlossen und 
								verfälschen nicht das Ergebnis. Sollten Schwellenwertüberschreitungen vorkommen, wird das Reading "diff_overrun_limit_&lt;diffLimit&gt;"
								erstellt. (&lt;diffLimit&gt; wird dabei durch den aktuellen Attributwert ersetzt) 
								Es enthält eine Liste der relevanten Wertepaare. Mit verbose 3 werden diese Datensätze ebenfalls im Logfile protokolliert.
								</li> <br> 

                                  <ul>
							      Beispiel Ausgabe im Logfile beim Überschreiten von diffAccept=10: <br><br>
							  
                                  DbRep Rep.STP5000.etotal -> data ignored while calc diffValue due to threshold overrun (diffAccept = 10): <br>
							      2016-04-09 08:50:50 0.0340 -> 2016-04-09 12:42:01 13.3440 <br><br>
							  
                                  # Der erste Datensatz mit einem Wert von 0.0340 ist untypisch gering zum nächsten Wert 13.3440 und führt zu einem zu hohen
							      Differenzwert. <br>
							      # Es ist zu entscheiden ob der Datensatz gelöscht, ignoriert, oder das Attribut diffAccept angepasst werden sollte. 
                                  </ul><br> 
							  
  <li><b>disable </b>         - deaktiviert das Modul   </li> <br>
  
  <li><b>dumpComment </b>     - User-Kommentar. Er wird im Kopf des durch den Befehl "dumpMyQL clientSide" erzeugten Dumpfiles 
                                eingetragen.   </li> <br>
                                
  <li><b>dumpCompress </b>    - wenn gesetzt, werden die Dumpfiles nach "dumpMySQL" bzw. "dumpSQLite" komprimiert </li> <br>
  
  <li><b>dumpDirLocal </b>    - Zielverzeichnis für die Erstellung von Dumps mit "dumpMySQL clientSide". 
                                default: "{global}{modpath}/log/" auf dem FHEM-Server. <br>
								Ebenfalls werden in diesem Verzeichnis alte Backup-Files durch die interne Versionsverwaltung von 
								"dumpMySQL" gesucht und gelöscht wenn die gefundene Anzahl den Attributwert "dumpFilesKeep"
								überschreitet. Das Attribut dient auch dazu ein lokal gemountetes Verzeichnis "dumpDirRemote"
								DbRep bekannt zu machen. </li> <br>
								
  <li><b>dumpDirRemote </b>   - Zielverzeichnis für die Erstellung von Dumps mit "dumpMySQL serverSide". 
                                default: das Home-Dir des MySQL-Servers auf dem MySQL-Host </li> <br>
  
  <li><b>dumpMemlimit </b>    - erlaubter Speicherverbrauch für SQL-Script zur Generierungszeit (default: 100000 Zeichen). 
                                Bitte den Parameter anpassen, falls es zu Speicherengpässen und damit verbundenen Performanceproblemen
                                kommen sollte. </li> <br>
  
  <li><b>dumpSpeed </b>       - Anzahl der abgerufenen Zeilen aus der Quelldatenbank (default: 10000) pro Select durch "dumpMySQL ClientSide". 
                                Dieser Parameter hat direkten Einfluß auf die Laufzeit und den Ressourcenverbrauch zur Laufzeit.  </li> <br>

  <li><b>dumpFilesKeep </b>   - Es wird die angegebene Anzahl Dumpfiles im Dumpdir belassen (default: 3). Sind mehr (ältere) Dumpfiles 
                                vorhanden, werden diese gelöscht nachdem ein neuer Dump erfolgreich erstellt wurde. Das globale
								Attribut "archivesort" wird berücksichtigt. </li> <br> 
  
  <li><b>executeAfterProc </b> - Es kann ein FHEM-Kommando angegeben werden welches <b>nach dem Dump</b> ausgeführt werden soll. <br>
                                 Funktionen sind in {} einzuschließen.<br><br>

                                <ul>
							    <b>Beispiel:</b> <br><br>
								attr &lt;name&gt; executeAfterProc set og_gz_westfenster off; <br>
								attr &lt;name&gt; executeAfterProc {adump ("&lt;name&gt;")} <br><br>
								
								# "adump" ist eine in 99_myUtils definierte Funktion. <br>
								
<pre>
sub adump {
    my ($name) = @_;
    my $hash = $defs{$name};
    # die eigene Funktion, z.B.
    Log3($name, 3, "DbRep $name -> Dump ist beendet");
 
    return;
}
</pre>
</ul>
</li>
								
  <li><b>executeBeforeProc </b> - Es kann ein FHEM-Kommando angegeben werden welches <b>vor dem Dump</b> ausgeführt werden soll. <br>
                                 Funktionen sind in {} einzuschließen.<br><br>

                                <ul>
							    <b>Beispiel:</b> <br><br>
								attr &lt;name&gt; executeBeforeProc set og_gz_westfenster on; <br>
								attr &lt;name&gt; executeBeforeProc {bdump ("&lt;name&gt;")} <br><br>
								
								# "bdump" ist eine in 99_myUtils definierte Funktion. <br>
								
<pre>
sub bdump {
    my ($name) = @_;
    my $hash = $defs{$name};
    # die eigene Funktion, z.B.
    Log3($name, 3, "DbRep $name -> Dump startet");
 
    return;
}
</pre>
</ul>
</li>
  
  <li><b>expimpfile </b>      - Pfad/Dateiname für Export/Import in/aus einem File.  </li> <br>
  
  <li><b>fetchMarkDuplicates </b> 
                              - Markierung von mehrfach vorkommenden Datensätzen im Ergebnis des "fetchrows" Kommandos </li> <br>
  
  <li><b>fetchRoute [descent | ascent] </b>  - bestimmt die Leserichtung des fetchrows-Befehl. <br><br>
                                                          <ul>
                                                          <b>descent</b> - die Datensätze werden absteigend gelesen (default). Wird 
                                                                               die durch das Attribut "limit" festgelegte Anzahl der Datensätze 
                                                                               überschritten, werden die neuesten x Datensätze angezeigt. <br><br>
                                                          <b>ascent</b> - die Datensätze werden aufsteigend gelesen.  Wird
                                                                               die durch das Attribut "limit" festgelegte Anzahl der Datensätze 
                                                                               überschritten, werden die ältesten x Datensätze angezeigt. <br>
														  </ul>
														  
														</li> <br><br>
  
  <li><b>ftpUse </b>          - FTP Transfer nach dem Dump wird eingeschaltet (ohne SSL Verschlüsselung). Das erzeugte 
                                Datenbank Backupfile wird non-blocking zum angegebenen FTP-Server (Attribut "ftpServer") 
								übertragen. </li> <br>
								
  <li><b>ftpUseSSL </b>       - FTP Transfer mit SSL Verschlüsselung nach dem Dump wird eingeschaltet. Das erzeugte 
                                Datenbank Backupfile wird non-blocking zum angegebenen FTP-Server (Attribut "ftpServer") 
								übertragen. </li> <br>
								
  <li><b>ftpUser </b>         - User zur Anmeldung am FTP-Server, default: "anonymous". </li> <br>
  
  <li><b>ftpDebug </b>        - Debugging der FTP Kommunikation zur Fehlersuche. </li> <br>
  
  <li><b>ftpDir </b>          - Verzeichnis des FTP-Servers in welches das File übertragen werden soll (default: "/"). </li> <br>
  
  <li><b>ftpDumpFilesKeep </b> - Es wird die angegebene Anzahl Dumpfiles im &lt;ftpDir&gt; belassen (default: 3). Sind mehr 
                                (ältere) Dumpfiles vorhanden, werden diese gelöscht nachdem ein neuer Dump erfolgreich 
                                übertragen wurde. </li> <br> 
  
  <li><b>ftpPassive </b>      - setzen wenn passives FTP verwendet werden soll </li> <br>
  
  <li><b>ftpPort </b>         - FTP-Port, default: 21 </li> <br>
  
  <li><b>ftpPwd </b>          - Passwort des FTP-Users, default nicht gesetzt </li> <br>
  
  <li><b>ftpServer </b>       - Name oder IP-Adresse des FTP-Servers. <b>notwendig !</b> </li> <br>
  
  <li><b>ftpTimeout </b>      - Timeout für die FTP-Verbindung in Sekunden (default: 30). </li> <br>
								 
  <a name="DbRepattrlimit"></a>
  <li><b>limit </b>           - begrenzt die Anzahl der resultierenden Datensätze im select-Statement von "fetchrows", bzw. der anzuzeigenden Datensätze
                                der Kommandos "delSeqDoublets adviceDelete", "delSeqDoublets adviceRemain" (default 1000). 
								Diese Limitierung soll eine Überlastung der Browsersession und ein 
								blockieren von FHEMWEB verhindern. Bei Bedarf entsprechend ändern bzw. die 
								Selektionskriterien (Zeitraum der Auswertung) anpassen. </li> <br>
								
  <li><b>optimizeTablesBeforeDump </b>  - wenn "1", wird vor dem Datenbankdump eine Tabellenoptimierung ausgeführt (default: 0).  
                                          Dadurch verlängert sich die Laufzeit des Dump. <br><br>
                                          <ul>
                                          <b>Hinweis </b> <br>
                                          Die Tabellenoptimierung führt zur Sperrung der Tabellen und damit zur Blockierung von
										  FHEM falls DbLog nicht im asynchronen Modus (DbLog-Attribut "asyncMode") betrieben wird !
                                          <br>
										  </ul>
                                          </li> <br> 
  
  <li><b>reading </b>         - Abgrenzung der DB-Selektionen auf ein bestimmtes oder mehrere Readings.
                                Mehrere Readings werden als Komma separierte Liste angegeben. <br>
								SQL Wildcard (%) wird in einer Liste als normales ASCII-Zeichen gewertet. <br>
                                </li> <br>  
								
                                <ul>
							    <b>Beispiele:</b> <br>
								<code>attr &lt;name&gt; reading etotal</code> <br>
								<code>attr &lt;name&gt; reading et%</code> <br>
								<code>attr &lt;name&gt; reading etotal,etoday</code> <br>
								</ul>
								<br><br>
  
  <li><b>readingNameMap </b>  - der Name des ausgewerteten Readings wird mit diesem String für die Anzeige überschrieben  </li> <br>
  
  <li><b>readingPreventFromDel </b>  - Komma separierte Liste von Readings die vor einer neuen Operation nicht gelöscht 
                                werden sollen  </li> <br>
								
  <li><b>role </b>            - die Rolle des DbRep-Device. Standard ist "Client". Die Rolle "Agent" ist im Abschnitt 
                                <a href="#DbRepAutoRename">DbRep-Agent</a> beschrieben.   </li> <br>
								
  <li><b>seqDoubletsVariance </b> - akzeptierte Abweichung (+/-) für das Kommando "set &lt;name&gt; delSeqDoublets". <br>
                                    Der Wert des Attributs beschreibt die Abweichung bis zu der aufeinanderfolgende numerische Werte (VALUE) von 
                                    Datensätze als gleich angesehen und gelöscht werden sollen. "seqDoubletsVariance" ist ein absoluter Zahlenwert, 
                                    der sowohl als positive als auch negative Abweichung verwendet wird. </li> <br>

                                    <ul>
							        <b>Beispiele:</b> <br>
								    <code>attr &lt;name&gt; seqDoubletsVariance 0.0014 </code> <br>
								    <code>attr &lt;name&gt; seqDoubletsVariance 1.45   </code> <br>
								    </ul>
								    <br><br>                                     
                                
  <li><b>showproctime </b>    - wenn gesetzt, zeigt das Reading "sql_processing_time" die benötigte Abarbeitungszeit (in Sekunden) 
                                für die SQL-Ausführung der durchgeführten Funktion. Dabei wird nicht ein einzelnes 
								SQl-Statement, sondern die Summe aller notwendigen SQL-Abfragen innerhalb der jeweiligen 
								Funktion betrachtet.   </li> <br>
								
  <li><b>showStatus </b>      - grenzt die Ergebnismenge des Befehls "get &lt;name&gt; dbstatus" ein. Es können SQL-Wildcard (%) verwendet werden.    </li> <br>

                                <ul>
                                <b>Bespiel: </b> <br>  
                                attr &lt;name&gt; showStatus %uptime%,%qcache%  <br>
                                # Es werden nur Readings erzeugt die im Namen "uptime" und "qcache" enthalten <br>
                                </ul><br>  
  
  <li><b>showVariables </b>   - grenzt die Ergebnismenge des Befehls "get &lt;name&gt; dbvars" ein. Es können SQL-Wildcard (%) verwendet werden.    </li> <br>

                                <ul>
                                <b>Bespiel: </b> <br>
                                attr &lt;name&gt; showVariables %version%,%query_cache% <br>
                                # Es werden nur Readings erzeugt die im Namen "version" und "query_cache" enthalten <br>
                                </ul><br>  
                              
  <li><b>showSvrInfo </b>     - grenzt die Ergebnismenge des Befehls "get &lt;name&gt; svrinfo" ein. Es können SQL-Wildcard (%) verwendet werden.    </li> <br>

                                <ul>
                                <b>Bespiel: </b> <br>
                                attr &lt;name&gt; showSvrInfo %SQL_CATALOG_TERM%,%NAME%  <br>
                                # Es werden nur Readings erzeugt die im Namen "SQL_CATALOG_TERM" und "NAME" enthalten <br>
                                </ul><br>  
                              
  <li><b>showTableInfo </b>   - grenzt die Ergebnismenge des Befehls "get &lt;name&gt; tableinfo" ein. Es können SQL-Wildcard (%) verwendet werden.    </li> <br>

                                <ul>
                                <b>Bespiel: </b> <br>
                                attr &lt;name&gt; showTableInfo current,history  <br>
                                # Es werden nur Information der Tabellen "current" und "history" angezeigt <br>
                                </ul><br>  

  <li><b>sqlResultFieldSep </b> - legt den verwendeten Feldseparator (default: "|") im Ergebnis des Kommandos "set ... sqlCmd" fest.    </li> <br>
  
  <li><b>sqlCmdHistoryLength </b> 
                              - aktiviert die Kommandohistorie von "sqlCmd" und legt deren Länge fest  </li> <br>
								
  <li><b>sqlResultFormat </b> - legt die Formatierung des Ergebnisses des Kommandos "set &lt;name&gt; sqlCmd" fest. 
                                Mögliche Optionen sind: <br><br>
  
								<ul>
                                <b>separated </b> - die Ergebniszeilen werden als einzelne Readings fortlaufend 
                                                    generiert. (default)<br><br> 
                                <b>mline </b>     - das Ergebnis wird als Mehrzeiler im <a href="#DbRepReadings">Reading</a>
                                                    SqlResult dargestellt. <br><br>	
                                <b>sline </b>     - das Ergebnis wird als Singleline im <a href="#DbRepReadings">Reading</a>
                                                    SqlResult dargestellt. Satztrenner ist"]|[". <br><br>
                                <b>table </b>     - das Ergebnis wird als Tabelle im <a href="#DbRepReadings">Reading</a>
                                                    SqlResult dargestellt. <br><br>	
                                <b>json </b>      - erzeugt das <a href="#DbRepReadings">Reading</a> SqlResult als
								                    JSON-kodierten Hash.
													Jedes Hash-Element (Ergebnissatz) setzt sich aus der laufenden Nummer
													des Datensatzes (Key) und dessen Wert zusammen. </li><br><br>
        
		Die Weiterverarbeitung des Ergebnisses kann z.B. mit der folgenden userExitFn in 99_myUtils.pm erfolgen: <br>
		<pre>
        sub resfromjson {
          my ($name,$reading,$value) = @_;
          my $hash   = $defs{$name};

          if ($reading eq "SqlResult") {
            # nur Reading SqlResult enthält JSON-kodierte Daten
            my $data = decode_json($value);
	      
		    foreach my $k (keys(%$data)) {
		      
			  # ab hier eigene Verarbeitung für jedes Hash-Element 
		      # z.B. Ausgabe jedes Element welches "Cam" enthält
		      my $ke = $data->{$k};
		      if($ke =~ m/Cam/i) {
		        my ($res1,$res2) = split("\\|", $ke);
                Log3($name, 1, "$name - extract element $k by userExitFn: ".$res1." ".$res2);
		      }
	        }
          }
        return;
        }
  	    </pre>  	
													
                                </ul><br>  
                                
  <li><b>timeYearPeriod </b> - Mit Hilfe dieses Attributes wird eine jährliche Zeitperiode für die Datenbankselektion bestimmt. 
                               Die Zeitgrenzen werden zur Ausführungszeit dynamisch berechnet. Es wird immer eine Jahresperiode 
                               bestimmt. Eine unterjährige Angabe ist nicht möglich. <br>
                               Dieses Attribut ist vor allem dazu gedacht Auswertungen synchron zu einer Abrechnungsperiode, z.B. der eines 
                               Energie- oder Gaslieferanten, anzufertigen. 
                               </li> <br> 
                               
                               <ul>
							   <b>Beispiel:</b> <br><br>
							   attr &lt;name&gt; timeYearPeriod 06-25 06-24 <br><br>
								
							   # wertet die Datenbank in den Zeitgrenzen 25. Juni AAAA bis 24. Juni BBBB aus. <br>
                               # Das Jahr AAAA bzw. BBBB wird in Abhängigkeit des aktuellen Datums errechnet. <br>
                               # Ist das aktuelle Datum >= 25. Juni und =< 31. Dezember, dann ist AAAA = aktuelles Jahr und BBBB = aktuelles Jahr+1 <br>
                               # Ist das aktuelle Datum >= 01. Januar und =< 24. Juni, dann ist AAAA = aktuelles Jahr-1 und BBBB = aktuelles Jahr
							   </ul>
							   <br><br>
  
  <li><b>timestamp_begin </b> - der zeitliche Beginn für die Datenselektion (*)   </li> <br>
  
  <li><b>timestamp_end </b>   - das zeitliche Ende für die Datenselektion. Wenn nicht gesetzt wird immer die aktuelle 
                                Datum/Zeit-Kombi für das Ende der Selektion eingesetzt. (*)  </li> <br>
															
  
  (*) Das Format von Timestamp ist wie in DbLog "YYYY-MM-DD HH:MM:SS". Für die Attribute "timestamp_begin", "timestamp_end" 
  kann ebenso eine der folgenden Eingaben verwendet werden. Dabei wird das timestamp-Attribut dynamisch belegt: <br><br>
                              <ul>
                              <b>current_year_begin</b>     : entspricht "&lt;aktuelles Jahr&gt;-01-01 00:00:00"          <br>
                              <b>current_year_end</b>       : entspricht "&lt;aktuelles Jahr&gt;-12-31 23:59:59"          <br>
                              <b>previous_year_begin</b>    : entspricht "&lt;vorheriges Jahr&gt;-01-01 00:00:00"         <br>
                              <b>previous_year_end</b>      : entspricht "&lt;vorheriges Jahr&gt;-12-31 23:59:59"         <br>
                              <b>current_month_begin</b>    : entspricht "&lt;aktueller Monat erster Tag&gt; 00:00:00"    <br>
                              <b>current_month_end</b>      : entspricht "&lt;aktueller Monat letzter Tag&gt; 23:59:59"   <br>
                              <b>previous_month_begin</b>   : entspricht "&lt;Vormonat erster Tag&gt; 00:00:00"           <br>
                              <b>previous_month_end</b>     : entspricht "&lt;Vormonat letzter Tag&gt; 23:59:59"          <br>
                              <b>current_week_begin</b>     : entspricht "&lt;erster Tag der akt. Woche&gt; 00:00:00"     <br>
                              <b>current_week_end</b>       : entspricht "&lt;letzter Tag der akt. Woche&gt; 23:59:59"    <br>
                              <b>previous_week_begin</b>    : entspricht "&lt;erster Tag Vorwoche&gt; 00:00:00"           <br>
                              <b>previous_week_end</b>      : entspricht "&lt;letzter Tag Vorwoche&gt; 23:59:59"          <br>
                              <b>current_day_begin</b>      : entspricht "&lt;aktueller Tag&gt; 00:00:00"                 <br>
                              <b>current_day_end</b>        : entspricht "&lt;aktueller Tag&gt; 23:59:59"                 <br>
                              <b>previous_day_begin</b>     : entspricht "&lt;Vortag&gt; 00:00:00"                        <br>
                              <b>previous_day_end</b>       : entspricht "&lt;Vortag&gt; 23:59:59"                        <br>
                              <b>current_hour_begin</b>     : entspricht "&lt;aktuelle Stunde&gt;:00:00"                  <br>
                              <b>current_hour_end</b>       : entspricht "&lt;aktuelle Stunde&gt;:59:59"                  <br>
                              <b>previous_hour_begin</b>    : entspricht "&lt;vorherige Stunde&gt;:00:00"                 <br>
                              <b>previous_hour_end</b>      : entspricht "&lt;vorherige Stunde&gt;:59:59"                 <br>
                              </ul><br>
  
  Natürlich sollte man immer darauf achten dass "timestamp_begin" < "timestamp_end" ist.  <br><br>

                                <ul>
							    <b>Beispiel:</b> <br><br>
								attr &lt;name&gt; timestamp_begin current_year_begin <br>
								attr &lt;name&gt; timestamp_end  current_year_end <br><br>
								
								# Wertet die Datenbank in den Zeitgrenzen des aktuellen Jahres aus. <br>
								</ul>
								<br><br>
  
  <b>Hinweis </b> <br>
  
  Wird das Attribut "timeDiffToNow" gesetzt, werden die eventuell gesetzten anderen Zeit-Attribute 
  ("timestamp_begin","timestamp_end","timeYearPeriod") gelöscht.
  Das Setzen von "timestamp_begin" bzw. "timestamp_end" bedingt die Löschung von anderen Zeit-Attribute falls sie vorher gesetzt waren.
  <br><br>
  
  <li><b>timeDiffToNow </b>   - der <b>Selektionsbeginn</b> wird auf den Zeitpunkt <b>"&lt;aktuelle Zeit&gt; - &lt;timeDiffToNow&gt;"</b> 
                                gesetzt (z.b. werden die letzten 24 Stunden in die Selektion eingehen wenn das Attribut auf "86400" gesetzt 
								wurde). Die Timestampermittlung erfolgt dynamisch zum Ausführungszeitpunkt.     </li> <br>
								
                                <ul>
							    <b>Eingabeformat Beispiel:</b> <br>
								<code>attr &lt;name&gt; timeDiffToNow 86400</code> <br>
                                # die Startzeit wird auf "aktuelle Zeit - 86400 Sekunden" gesetzt <br>
								<code>attr &lt;name&gt; timeDiffToNow d:2 h:3 m:2 s:10</code> <br>
                                # die Startzeit wird auf "aktuelle Zeit - 2 Tage 3 Stunden 2 Minuten 10 Sekunden" gesetzt <br>							
								<code>attr &lt;name&gt; timeDiffToNow m:600</code> <br> 
                                # die Startzeit wird auf "aktuelle Zeit - 600 Minuten" gesetzt <br>
								<code>attr &lt;name&gt; timeDiffToNow h:2.5</code> <br>
                                # die Startzeit wird auf "aktuelle Zeit - 2,5 Stunden" gesetzt <br>
								</ul>
								<br><br>
								
  <li><b>timeOlderThan </b>   - das <b>Selektionsende</b> wird auf den Zeitpunkt <b>"&lt;aktuelle Zeit&gt; - &lt;timeOlderThan&gt;"</b> 
                                gesetzt. Dadurch werden alle Datensätze bis zu dem Zeitpunkt "&lt;aktuelle 
								Zeit&gt; - &lt;timeOlderThan&gt;" berücksichtigt (z.b. wenn auf 86400 gesetzt, werden alle
								Datensätze die älter als ein Tag sind berücksichtigt). Die Timestampermittlung erfolgt 
								dynamisch zum Ausführungszeitpunkt. <br>
								Es gelten die gleichen Eingabeformate wie für das Attribut "timeDiffToNow".   </li> <br> 
								
  <li><b>timeout </b>         - das Attribut setzt den Timeout-Wert für die Blocking-Call Routinen in Sekunden  
                                (Default: 86400) </li> <br>
								
  <li><b>userExitFn   </b>    - stellt eine Schnittstelle zur Ausführung eigenen Usercodes zur Verfügung. <br>
                                Um die Schnittstelle zu aktivieren, wird zunächst die aufzurufende Subroutine in 
							    99_myUtls.pm nach folgendem Muster erstellt:     <br>

		<pre>
        sub UserFunction {
          my ($name,$reading,$value) = @_;
          my $hash = $defs{$name};
          ...
          # z.B. übergebene Daten loggen
          Log3 $name, 1, "UserExitFn $name called - transfer parameter are Reading: $reading, Value: $value " ;
          ...
        return;
        }
  	    </pre>
	                           
							   Die Aktivierung der Schnittstelle erfogt durch Setzen des Funktionsnamens im Attribut. 
							   Optional kann ein Reading:Value Regex als Argument angegeben werden. Wird kein Regex 
							   angegeben, werden alle Wertekombinationen als "wahr" gewertet (entspricht .*:.*). 
							   <br><br>
							   
							   <ul>
							   <b>Beispiel:</b> <br>
                               attr <device> userExitFn UserFunction .*:.* <br>
                               # "UserFunction" ist die Subroutine in 99_myUtils.pm.
							   </ul>
							   <br>
							   
							   Grundsätzlich arbeitet die Schnittstelle OHNE Eventgenerierung bzw. benötigt zur Funktion keinen
							   Event. Sofern das Attribut gesetzt ist, erfolgt Die Regexprüfung NACH der Erstellung eines
							   Readings. Ist die Prüfung WAHR, wird die angegebene Funktion aufgerufen. 
							   Zur Weiterverarbeitung werden der aufgerufenenen Funktion folgende Variablen übergeben: <br><br>
                               
							   <ul>
                               <li>$name - der Name des DbRep-Devices </li>
                               <li>$reading - der Namen des erstellen Readings </li>
                               <li>$value - der Wert des Readings </li>
							   
							   </ul>
							   </li>
							   <br><br> 

</ul></ul>
</ul>

<a name="DbRepReadings"></a>
<b>Readings</b>

<br>
<ul>
  Abhängig von der ausgeführten DB-Operation werden die Ergebnisse in entsprechenden Readings dargestellt. Zu Beginn einer neuen Operation 
  werden alle alten Readings einer vorangegangenen Operation gelöscht um den Verbleib unpassender bzw. ungültiger Readings zu vermeiden.  
  <br><br>
  
  Zusätzlich werden folgende Readings erzeugt (Auswahl): <br><br>
  
  <ul><ul>
  <li><b>state  </b>                      - enthält den aktuellen Status der Auswertung. Wenn Warnungen auftraten (state = Warning) vergleiche Readings
                                            "diff_overrun_limit_&lt;diffLimit&gt;" und "less_data_in_period"  </li> <br>

  <li><b>errortext  </b>                  - Grund eines Fehlerstatus </li> <br>

  <li><b>background_processing_time </b>  - die gesamte Prozesszeit die im Hintergrund/Blockingcall verbraucht wird </li> <br>

  <li><b>diff_overrun_limit_&lt;diffLimit&gt;</b>  - enthält eine Liste der Wertepaare die eine durch das Attribut "diffAccept" festgelegte Differenz
                                                     &lt;diffLimit&gt; (Standard: 20) überschreiten. Gilt für Funktion "diffValue". </li> <br>

  <li><b>less_data_in_period </b>         - enthält eine Liste der Zeitperioden in denen nur ein einziger Datensatz gefunden wurde. Die
                                            Differenzberechnung berücksichtigt den letzten Wert der Vorperiode.  Gilt für Funktion "diffValue". </li> <br>	

  <li><b>sql_processing_time </b>         - der Anteil der Prozesszeit die für alle SQL-Statements der ausgeführten 
                                            Operation verbraucht wird </li> <br>
											
  <li><b>SqlResult </b>                   - Ergebnis des letzten sqlCmd-Kommandos. Die Formatierung erfolgt entsprechend
                                            des <a href="#DbRepattr">Attributes</a> "sqlResultFormat" </li> <br>
											
  <li><b>sqlCmd </b>                      - das letzte ausgeführte sqlCmd-Kommando </li> <br>											
  </ul></ul>
  <br>

</ul>

<a name="DbRepAutoRename"></a>
<b>DbRep Agent - automatisches Ändern von Device-Namen in Datenbanken und DbRep-Definitionen nach FHEM "rename" Kommando</b>

<br>
<ul>
  Mit dem Attribut "role" wird die Rolle des DbRep-Device festgelegt. Die Standardrolle ist "Client". Mit der Änderung der Rolle in "Agent" wird das Device 
  veranlasst auf Umbenennungen von Geräten in der FHEM Installation zu reagieren. <br><br>
  
  Durch den DbRep-Agenten werden folgende Features aktiviert wenn ein Gerät in FHEM mit "rename" umbenannt wird: <br><br>
  
  <ul><ul>
  <li> in der dem DbRep-Agenten zugeordneten Datenbank (Internal Database) wird nach Datensätzen mit dem alten Gerätenamen gesucht und dieser Gerätename in
       <b>allen</b> betroffenen Datensätzen in den neuen Namen geändert. </li> <br>
       
  <li> in dem DbRep-Agenten zugeordneten DbLog-Device wird in der Definition das alte durch das umbenannte Device ersetzt. Dadurch erfolgt ein weiteres Logging
       des umbenannten Device in der Datenbank. </li> <br>
  
  <li> in den existierenden DbRep-Definitionen vom Typ "Client" wird ein evtl. gesetztes Attribut "device = alter Devicename" in "device = neuer Devicename" 
       geändert. Dadurch werden Auswertungsdefinitionen bei Geräteumbenennungen automatisch konstistent gehalten. </li> <br>

  </ul></ul>
  
  Mit der Änderung in einen Agenten sind folgende Restriktionen verbunden die mit dem Setzen des Attributes "role = Agent" eingeschaltet 
  und geprüft werden: <br><br>
  
  <ul><ul>
  <li> es kann nur einen Agenten pro Datenbank in der FHEM-Installation geben. Ist mehr als eine Datenbank mit DbLog definiert, können
       ebenso viele DbRep-Agenten eingerichtet werden </li> <br>
  
  <li> mit der Umwandlung in einen Agenten wird nur noch das Set-Komando "renameDevice" verfügbar sein sowie nur ein eingeschränkter Satz von DbRep-spezifischen 
       Attributen zugelassen. Wird ein DbRep-Device vom bisherigen Typ "Client" in einen Agenten geändert, werden evtl. gesetzte und nun nicht mehr zugelassene 
       Attribute glöscht.  </li> <br>

  </ul></ul>
  
  Die Aktivitäten wie Datenbankänderungen bzw. Änderungen an anderen DbRep-Definitionen werden im Logfile mit verbose=3 protokolliert. Damit die renameDevice-Funktion
  bei großen Datenbanken nicht in ein timeout läuft, sollte das Attribut "timeout" entsprechend dimensioniert werden. Wie alle Datenbankoperationen des Moduls 
  wird auch das Autorename nonblocking ausgeführt. <br><br>
  
        <ul>
        <b>Beispiel </b> für die Definition eines DbRep-Device als Agent:  <br><br>             
        <code>
        define Rep.Agent DbRep LogDB  <br>
        attr Rep.Agent devStateIcon connected:10px-kreis-gelb .*disconnect:10px-kreis-rot .*done:10px-kreis-gruen <br>
        attr Rep.Agent icon security      <br>
        attr Rep.Agent role Agent         <br>
        attr Rep.Agent room DbLog         <br>
        attr Rep.Agent showproctime 1     <br>
        attr Rep.Agent stateFormat { ReadingsVal("$name","state", undef) eq "running" ? "renaming" : ReadingsVal("$name","state", undef). " &raquo;; ProcTime: ".ReadingsVal("$name","sql_processing_time", undef)." sec"}  <br>
        attr Rep.Agent timeout 86400      <br>
        </code>
        <br>
        </ul>
		
  <b>Hinweis:</b> <br>
  Obwohl die Funktion selbst non-blocking ausgelegt ist, sollte das zugeordnete DbLog-Device
  im asynchronen Modus betrieben werden um ein Blockieren von FHEMWEB zu vermeiden (Tabellen-Lock). <br><br> 
  
</ul>

=end html_DE
=cu